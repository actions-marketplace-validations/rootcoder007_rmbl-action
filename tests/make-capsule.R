# Test fixture: Rscript tests/make-capsule.R CAPSULE_DIR SOURCE_CSV [URL_PREFIX] [bundle]
# Writes a 300-row source CSV and a capsule pinning it, whose provenance points at
# file://<URL_PREFIX>/<SOURCE_CSV> (URL_PREFIX defaults to the current directory).
suppressPackageStartupMessages(library(rmoriebricklayer))
a <- commandArgs(TRUE)
dir <- a[[1L]]
src <- a[[2L]]
prefix <- if (length(a) > 2L) a[[3L]] else getwd()
set.seed(1)
df <- data.frame(id = 1:300, value = round(stats::rnorm(300), 6),
                 grade = sample(c("a", "b", "c"), 300, TRUE))
dir.create(dirname(src), showWarnings = FALSE, recursive = TRUE)
write.csv(df, src, row.names = FALSE)
dir.create(dir, showWarnings = FALSE, recursive = TRUE)
invisible(file.copy(src, file.path(dir, "data.csv"), overwrite = TRUE))
f <- file.path(dir, "data.csv")
prov <- list(name = "fixture",
             resource = list(filename = "data.csv",
                             direct_url = paste0("file://", prefix, "/", src),
                             sha256 = sha256file(f), size_bytes = file.size(f),
                             row_count_data_rows = nrow(df)),
             schema = list(expected_columns = names(df)),
             table = list(rounding = 5, suppression_limit = 10))
writeLines(tojs(prov, auto_unbox = TRUE, pretty = TRUE), file.path(dir, "data_provenance.json"))
if (length(a) > 3L && a[[4L]] == "bundle") {
  # sign every file of the capsule; the public key goes beside the capsule, not in it
  key <- fipskg("ML-DSA-44")
  b <- cpsbndl(dir, mkmnf(list(dataset = "fixture"), env = FALSE), key)
  writeLines(b$attestation$public, paste0(dir, ".pub"))
}
cat("capsule written to", dir, "\n")
