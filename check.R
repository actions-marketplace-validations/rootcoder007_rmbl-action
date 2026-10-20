# rmbl-action: verify, drift-check, refresh or report rmoriebricklayer data capsules.
# The checks, the report, the annotations and the outputs are the package's (cpschk(), format(),
# ghann(), ghcmt(), ghout()); this script reads the RMBL_* inputs, signs in mode sign, resolves the
# base ref with git, writes the files and posts the sticky comment.
suppressPackageStartupMessages(library(rmoriebricklayer))
options(morie.progress = FALSE)

env <- function(name, default = "") {
  v <- Sys.getenv(name, unset = "")
  if (nzchar(v)) v else default
}
usage <- function(...) {
  cat(sprintf("::error::%s\n", sprintf(...)))
  quit(status = 2L)
}
flag <- function(name, default) {
  v <- tolower(env(name, default))
  if (!v %in% c("true", "false")) usage("%s must be true or false, not '%s'", name, v)
  v == "true"
}
number <- function(name, default) {
  v <- suppressWarnings(as.numeric(env(name, default)))
  if (length(v) != 1L || !is.finite(v) || v <= 0) usage("%s must be a positive number", name)
  v
}

ws <- env("GITHUB_WORKSPACE", getwd())
root <- env("RMBL_PATH", ".")
mode <- env("RMBL_MODE", "verify")
fail_on <- env("RMBL_FAIL_ON", "error")
report_path <- env("RMBL_REPORT", "rmbl-report.md")
json_path <- env("RMBL_JSON", "rmbl-results.json")
# `key`: the data.rmorie.com key, or the shared secret of hmac bundles (masked by entrypoint.sh)
key <- Sys.getenv("RMBL_KEY")
Sys.unsetenv("RMBL_KEY")
comment <- tolower(env("RMBL_COMMENT", "false"))
psi_warn <- number("RMBL_PSI_WARN", "0.1")
psi_fail <- number("RMBL_PSI_FAIL", "0.25")
event <- env("GITHUB_EVENT_NAME")
base_ref <- env("RMBL_BASE_REF", if (event %in% c("pull_request", "pull_request_target")) env("GITHUB_BASE_REF") else "")
if (!mode %in% c("verify", "drift", "refresh", "report", "sign")) {
  usage("mode must be verify, drift, refresh, report or sign, not '%s'", mode)
}
if (!fail_on %in% c("warn", "drift", "error", "never")) {
  usage("fail-on must be warn, drift, error or never, not '%s'", fail_on)
}
if (!comment %in% c("true", "false", "dry-run")) usage("comment must be true, false or dry-run, not '%s'", comment)
if (psi_warn > psi_fail) usage("psi-warn (%g) must not exceed psi-fail (%g)", psi_warn, psi_fail)
if (!dir.exists(root)) usage("path '%s' is not a directory", root)
flags <- list(wayback = flag("RMBL_WAYBACK", "false"), cache = flag("RMBL_CACHE", "false"),
              allow_file = flag("RMBL_ALLOW_FILE", "false"), snapshot = flag("RMBL_SNAPSHOT", "false"))
cache_dir <- file.path(ws, ".rmbl-cache")
if (flags$cache) options(rmoriebricklayer.dcache = cache_dir)  # the data.rmorie.com tables too

# ---- mode sign: pin each provenance on its first run and write an hmac capsule_bundle.json with
# cpsbndl(), so a project in any language only has to write the data and a plain provenance.
# The capsules are then verified as in verify mode.
str1 <- function(x) {
  x <- unlist(x)
  if (length(x) && !is.na(x[[1L]])) as.character(x[[1L]]) else NULL
}
if (mode == "sign") {
  scheme <- env("RMBL_SCHEME", "hmac")
  overwrite <- flag("RMBL_OVERWRITE", "false")
  if (scheme != "hmac") usage("scheme must be hmac, not '%s'", scheme)
  if (!nzchar(key)) usage("mode sign needs key: the hmac secret, from a repository secret")
  files <- list.files(root, pattern = "^data_provenance\\.json$", recursive = TRUE, full.names = TRUE)
  files <- sub("^\\./", "", files)
  files <- files[!grepl("(^|/)(\\.git|\\.rmbl-cache)/", files)]
  glob <- env("RMBL_MANIFESTS")
  if (nzchar(glob)) files <- files[grepl(utils::glob2rx(glob), files)]
  sdirs <- sort(unique(dirname(files)))
  if (!length(sdirs)) usage("mode sign found no data_provenance.json under '%s'", root)
  have <- sdirs[file.exists(file.path(sdirs, "capsule_bundle.json"))]
  if (length(have) && !overwrite) {
    usage("capsule_bundle.json already exists in %s; set overwrite: true to sign again", paste(have, collapse = ", "))
  }
  for (d in sdirs) {
    pf <- file.path(d, "data_provenance.json")
    prov <- loadprov(pf)
    if (is.null(prov$resource$sha256)) {
      # the first pin, in the fields cpsrfrsh() writes (row_count_data_rows only when recorded)
      fn <- if (is.null(str1(prov$resource$filename))) "" else str1(prov$resource$filename)
      df <- file.path(d, fn)
      if (!nzchar(fn) || grepl("^(/|~)|(^|/)\\.\\.(/|$)|^[A-Za-z]:", fn) || !file.exists(df) || dir.exists(df)) {
        usage("%s: resource.filename must name the data file, relative to the capsule", pf)
      }
      dg <- sha256file(df)
      if (is.list(prov$source)) prov$source$sha256 <- dg
      prov$resource$sha256 <- dg
      prov$resource$size_bytes <- file.size(df)
      prov$resource$retrieved_utc <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
      if (!is.null(prov$resource$row_count_data_rows)) {
        prov$resource$row_count_data_rows <- nrow(utils::read.csv(df, check.names = FALSE))
      }
      writeLines(tojs(prov, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA), pf)
      cat(sprintf("pinned %s (sha256 %s)\n", pf, dg))
    }
    mf <- file.path(d, "manifest.json")
    b <- cpsbndl(d, if (file.exists(mf)) loadprov(mf) else mkmnf(list(), env = FALSE), key)
    cat(sprintf("signed %s: %d files, hmac key id %s\n", d, length(b$files), b$attestation$public))
  }
}

# an hmac secret is not a data-service key: it is never handed to data.rmorie.com
bundles <- list.files(root, pattern = "^capsule_bundle\\.json$", recursive = TRUE, full.names = TRUE)
hmac <- vapply(bundles, function(f) {
  tryCatch(identical(as.character(unlist(cpsbndlrd(f)$attestation$scheme))[1L], "hmac"), error = function(e) FALSE)
}, NA)
if (any(hmac)) Sys.unsetenv("MORIE_HOSTED_KEY")

# the base branch's copy of a manifest, through git (the ref needs fetching: fetch-depth 0)
base <- NULL
if (nzchar(base_ref)) {
  base <- function(path) {
    for (ref in unique(c(base_ref, paste0("origin/", base_ref)))) {
      out <- suppressWarnings(system2("git", c("show", sprintf("%s:./%s", ref, path)), stdout = TRUE, stderr = FALSE))
      if (is.null(attr(out, "status"))) {
        tf <- tempfile(fileext = ".json")
        writeLines(out, tf)
        return(tf)
      }
    }
    NULL
  }
  attr(base, "label") <- base_ref
}

x <- cpschk(root, if (mode == "sign") "verify" else mode, key = key, pubkey = env("RMBL_PUBLIC_KEY"), psiwarn = psi_warn, psifail = psi_fail,
            base = base, cache = if (flags$cache) cache_dir else FALSE, allowfile = flags$allow_file,
            snapshot = flags$snapshot, wayback = flags$wayback, glob = env("RMBL_MANIFESTS"))
# refreshed files belong to the runner's user, not this container's
changed <- vapply(Filter(function(cp) isTRUE(cp$changed), x$capsules), `[[`, "", "capsule")
if (mode == "refresh" && length(changed)) Sys.chmod(list.files(changed, full.names = TRUE), "0666", use_umask = FALSE)

cat(ghann(x), sep = "\n")
md <- format(x, failon = fail_on)
writeLines(enc2utf8(md), report_path, useBytes = TRUE, sep = "")
summ <- Sys.getenv("GITHUB_STEP_SUMMARY")
if (nzchar(summ)) cat(md, file = summ, append = TRUE)
cat(md)
writeLines(enc2utf8(format(x, fmt = "json")), json_path, useBytes = TRUE, sep = "")

# ---- sticky pull-request comment, edited in place (the marker ghcmt() puts first)
marker <- "<!-- rmbl-action -->"
comment_state <- "off"
if (comment != "false") {
  run_url <- if (nzchar(env("GITHUB_RUN_ID"))) sprintf("%s/%s/actions/runs/%s", env("GITHUB_SERVER_URL", "https://github.com"),
                                                       env("GITHUB_REPOSITORY"), env("GITHUB_RUN_ID"))
  body <- ghcmt(x, runurl = run_url, failon = fail_on, marker = marker)
  pr <- tryCatch(as.character(unlist(loadprov(env("GITHUB_EVENT_PATH", "/nonexistent"))$pull_request$number))[1L],
                 error = function(e) NA_character_)
  if (length(pr) != 1L || is.na(pr)) pr <- NULL
  if (comment == "dry-run") {
    writeLines(enc2utf8(body), "rmbl-comment.md", useBytes = TRUE)
    cat(sprintf("comment dry-run: would create or update the comment marked %s on %s; body in rmbl-comment.md\n",
                marker, if (is.null(pr)) "no pull request (not a pull_request event)" else paste0("pull request #", pr)))
    comment_state <- "dry-run"
  } else if (!nzchar(Sys.getenv("GITHUB_TOKEN"))) {
    cat("::warning::comment skipped: GITHUB_TOKEN is not set in the step env\n")
    comment_state <- "skipped"
  } else if (is.null(pr)) {
    cat("comment skipped: not a pull_request event\n")
    comment_state <- "skipped"
  } else {
    hdr <- tempfile()
    writeLines(c(paste("Authorization: Bearer", Sys.getenv("GITHUB_TOKEN")),
                 "Accept: application/vnd.github+json"), hdr)
    Sys.chmod(hdr, "0600")
    api <- sprintf("%s/repos/%s", env("GITHUB_API_URL", "https://api.github.com"), env("GITHUB_REPOSITORY"))
    call <- function(method, url, data = NULL) {
      args <- c("-sS", "-f", "-X", method, "-H", paste0("@", hdr), url)
      if (!is.null(data)) {
        df <- tempfile()
        writeLines(enc2utf8(tojs(list(body = data), auto_unbox = TRUE)), df, useBytes = TRUE)
        args <- c(args, "--data-binary", paste0("@", df))
      }
      out <- suppressWarnings(system2("curl", args, stdout = TRUE, stderr = TRUE))
      if (!is.null(attr(out, "status"))) stop(paste(out, collapse = " "), call. = FALSE)
      out
    }
    comment_state <- tryCatch({
      id <- NULL
      for (page in 1:10) {
        tf <- tempfile(fileext = ".json")
        writeLines(call("GET", sprintf("%s/issues/%s/comments?per_page=100&page=%d", api, pr, page)), tf)
        got <- fromjs(paste(readLines(tf, warn = FALSE), collapse = "\n"), simplifyVector = FALSE)
        hit <- Filter(function(cm) grepl(marker, if (is.null(cm$body)) "" else cm$body, fixed = TRUE), got)
        if (length(hit)) {
          id <- hit[[1L]]$id
          break
        }
        if (length(got) < 100L) break
      }
      if (is.null(id)) {
        call("POST", sprintf("%s/issues/%s/comments", api, pr), body)
        "created"
      } else {
        call("PATCH", sprintf("%s/issues/comments/%s", api, format(id, scientific = FALSE)), body)
        "updated"
      }
    }, error = function(e) {
      cat(sprintf("::warning::comment not posted (a pull request from a fork has a read-only token): %s\n",
                  conditionMessage(e)))
      "failed"
    })
    unlink(hdr)
  }
}

# ---- step outputs
out <- Sys.getenv("GITHUB_OUTPUT")
if (nzchar(out)) {
  o <- ghout(x, report = report_path, json = json_path, comment = comment_state)
  cat(sprintf("%s=%s\n", names(o), unlist(o)), sep = "", file = out, append = TRUE)
}

rank <- c(ok = 0L, warn = 1L, drift = 2L, error = 3L)
fail <- mode != "report" && rank[[x$status]] >= switch(fail_on, warn = 1L, drift = 2L, error = 3L, never = 99L)
if (fail) cat(sprintf("::error::rmbl: status %s (fail-on %s)\n", x$status, fail_on))
quit(status = if (fail) 1L else 0L)
