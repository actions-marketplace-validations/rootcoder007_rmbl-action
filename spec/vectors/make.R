# Re-derive the test vectors of docs/bundle-format.md with rmoriebricklayer's own primitives
# (mnfcanon(), mnfdgst(), sha256file(), chmac()), then check the result with cpsbndlvrf().
# Usage: Rscript spec/vectors/make.R <output directory>
library(rmoriebricklayer)
out <- commandArgs(trailingOnly = TRUE)[1L]
cap <- file.path(out, "capsule")                      # the capsule: data, provenance, bundle
dir.create(cap, showWarnings = FALSE, recursive = TRUE)
wr <- function(name, text, nl = TRUE, at = out) {
  con <- file(file.path(at, name), "wb")
  writeBin(charToRaw(if (nl) paste0(text, "\n") else text), con)
  close(con)
}
key <- "rmbl-action-test-secret"
utc <- "2026-01-01T00:00:00Z"
# the note travels inside the signed payload: every escaping rule of the canonical form is in it
ctl <- function(...) rawToChar(as.raw(c(...)))
note <- paste0("vector \"q\" \\ </x / é \U1F600 tab", ctl(9), "lf", ctl(10), "cr", ctl(13),
               "bs", ctl(8), "ff", ctl(12), "c01", ctl(1), "c1f", ctl(31), "del", ctl(127), "ls ")
Encoding(note) <- "UTF-8"
wr("note.txt", note, nl = FALSE)

# the data file: x and its square, 1 to 3
wr("data.csv", "x,y\n1,1\n2,4\n3,9", at = cap)
csv <- file.path(cap, "data.csv")
prov <- list(
  name = "squares",
  source = list(url = "https://example.org/squares.csv", retrieved = substr(utc, 1L, 10L)),
  resource = list(filename = "data.csv", sha256 = sha256file(csv), size_bytes = file.size(csv),
                  row_count_data_rows = nrow(utils::read.csv(csv)))
)
wr("data_provenance.json", mnfcanon(prov), at = cap)

files <- lapply(c("data.csv", "data_provenance.json"), function(f) {
  p <- file.path(cap, f)
  list(path = f, sha256 = sha256file(p), size_bytes = file.size(p))
})
man_digest <- mnfdgst(mkmnf(list(), env = FALSE))        # no manifest.json: the empty manifest
inner <- list(meta = list(files = files, manifest_digest = man_digest, bundled_utc = utc), results = list())
payload <- list(digest = mnfdgst(inner), scheme = "hmac", public = chmac(key, "public"), context = "",
                prehash = "none", note = note, signed_utc = utc)
signed <- mnfdgst(payload)
sig <- chmac(key, signed)
bundle <- list(files = files, manifest_digest = man_digest, bundled_utc = utc,
               attestation = c(payload, list(signature = list(scheme = "hmac", signature = sig))))
wr("capsule_bundle.json", mnfcanon(bundle), at = cap)
wr("inner.canon.json", mnfcanon(inner), nl = FALSE)
wr("payload.canon.json", mnfcanon(payload), nl = FALSE)
wr("values.txt", paste(c(
  paste("key", key),
  paste("key_id", payload$public),
  paste("data_sha256", files[[1L]]$sha256),
  paste("provenance_sha256", files[[2L]]$sha256),
  paste("manifest_digest", man_digest),
  paste("attestation_digest", payload$digest),
  paste("payload_digest", signed),
  paste("signature", sig)), collapse = "\n"))

# the package's verifier accepts it, and a wrong key or a changed byte does not pass
bf <- file.path(cap, "capsule_bundle.json")
chk <- cpsbndlvrf(bf, cap, key = key, keyexp = payload$public)
ok <- chk$ok && isTRUE(vrfcps(cap)$ok) && !cpsbndlvrf(bf, cap, key = "wrong", keyexp = payload$public)$ok
if (!ok) {
  print(chk$checks)
  stop("the vectors do not verify")
}
