# rmbl-action: verify, drift-check, refresh or report rmoriebricklayer data capsules.
# A capsule is a directory holding data_provenance.json (checked with vrfcps()) and/or
# capsule_bundle.json (checked with cpsbndlvrf()). Inputs arrive as RMBL_* variables.
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

ws <- env("GITHUB_WORKSPACE", getwd())
root <- env("RMBL_PATH", ".")
mode <- env("RMBL_MODE", "verify")
fail_on <- env("RMBL_FAIL_ON", "error")
report_path <- env("RMBL_REPORT", "rmbl-report.md")
json_path <- env("RMBL_JSON", "rmbl-results.json")
glob <- env("RMBL_MANIFESTS", "")
pubkey <- env("RMBL_PUBLIC_KEY", "")
wayback <- flag("RMBL_WAYBACK", "false")
use_cache <- flag("RMBL_CACHE", "false")
allow_file <- flag("RMBL_ALLOW_FILE", "false")
if (!mode %in% c("verify", "drift", "refresh", "report")) {
  usage("mode must be verify, drift, refresh or report, not '%s'", mode)
}
if (!fail_on %in% c("error", "drift", "never")) {
  usage("fail-on must be error, drift or never, not '%s'", fail_on)
}
if (!dir.exists(root)) usage("path '%s' is not a directory", root)
cache_dir <- file.path(ws, ".rmbl-cache")
if (use_cache) {
  dir.create(cache_dir, showWarnings = FALSE, recursive = TRUE)
  options(rmoriebricklayer.dcache = cache_dir)
}

# capsule files, relative to the workspace, the cache and .git skipped
files <- list.files(root, pattern = "^(data_provenance|capsule_bundle)\\.json$",
                    recursive = TRUE, full.names = TRUE)
files <- sub("^\\./", "", files)
files <- files[!grepl("(^|/)(\\.git|\\.rmbl-cache)/", files)]
if (nzchar(glob)) {
  # ponytail: glob2rx's * also matches "/", so "data/*" reaches nested capsules
  files <- files[grepl(utils::glob2rx(glob), files)]
}
dirs <- sort(unique(dirname(files)))

short <- function(x) if (is.null(x) || !nzchar(x)) "" else substr(x, 1L, 12L)
str1 <- function(x) {
  x <- unlist(x)
  if (length(x) && !is.na(x[[1L]])) as.character(x[[1L]]) else NULL
}
fmt <- function(x) formatC(x, digits = 3, format = "g")
failed_rows <- function(chk, prefix = "") {
  bad <- chk$checks[!chk$checks$ok, , drop = FALSE]
  c(if (nrow(bad)) paste0(prefix, bad$check, ": ", bad$detail),
    if (length(chk$missing)) paste0(prefix, chk$missing, ": required check was never made"))
}
prov_json <- function(prov) tojs(prov, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA_real_)

# Fetch the capsule's source to a temp file: live (with the Wayback fallback fdl() makes),
# else the copy kept in the cache by an earlier run. Returns the path or NULL.
fetch_source <- function(url, snap, notes) {
  dest <- tempfile(fileext = paste0(".", tools::file_ext(url)))
  is_file <- startsWith(url, "file://")
  if (is_file && !allow_file) {
    notes$add("source is a file:// URL and allow-file is false")
    return(NULL)
  }
  ok <- tryCatch(
    fdl(url, dest, attwb = if (is_file) "" else snap, allowfile = is_file),
    error = function(e) {
      notes$add(paste("fetch refused:", conditionMessage(e)))
      FALSE
    })
  keep <- file.path(cache_dir, paste0("source-", substr(csha256(charToRaw(url)), 1L, 16L)))
  if (isTRUE(ok)) {
    if (use_cache) file.copy(dest, keep, overwrite = TRUE)
    return(dest)
  }
  if (use_cache && file.exists(keep)) {
    notes$add("source unreachable: used the copy cached by an earlier run")
    return(keep)
  }
  notes$add("source could not be fetched")
  NULL
}

check_capsule <- function(d) {
  notes <- local({
    v <- character()
    list(add = function(x) v <<- c(v, x), get = function() v)
  })
  res <- list(capsule = d, source = "", pinned_sha256 = "", fetched_sha256 = "",
              result = "ok", changed = FALSE, checks_passed = 0L, checks_total = 0L,
              drift = NULL, notes = character())
  prov_file <- file.path(d, "data_provenance.json")
  bundle_file <- file.path(d, "capsule_bundle.json")
  prov <- if (file.exists(prov_file)) loadprov(prov_file)
  if (!is.null(prov)) {
    res$source <- str1(prov$resource$direct_url) %||% str1(prov$source$url) %||% ""
    res$pinned_sha256 <- str1(prov$resource$sha256) %||% ""
    chk <- vrfcps(d)
    res$checks_passed <- sum(chk$checks$ok)
    res$checks_total <- nrow(chk$checks) + length(chk$missing)
    if (!isTRUE(chk$ok)) {
      res$result <- "error"
      for (x in failed_rows(chk)) notes$add(x)
    }
  }
  if (file.exists(bundle_file)) {
    bchk <- cpsbndlvrf(bundle_file, d, keyexp = if (nzchar(pubkey)) pubkey)
    res$checks_passed <- res$checks_passed + sum(bchk$checks$ok)
    res$checks_total <- res$checks_total + nrow(bchk$checks)
    if (!isTRUE(bchk$ok)) {
      res$result <- "error"
      for (x in failed_rows(bchk, "bundle ")) notes$add(x)
    }
  }

  if (mode %in% c("drift", "refresh") && !is.null(prov)) {
    if (!nzchar(res$source)) {
      notes$add("no resource$direct_url in the provenance: nothing to fetch")
      res$result <- "error"
    } else if (startsWith(res$source, "TODO")) {
      notes$add("the source URL is still a TODO")
      res$result <- "error"
    } else {
      got <- fetch_source(res$source, str1(prov$wayback$csv_snapshot), notes)
      if (is.null(got)) {
        res$result <- "error"
      } else {
        res$fetched_sha256 <- sha256file(got)
        res$changed <- !identical(tolower(res$fetched_sha256), tolower(res$pinned_sha256))
        dfile <- str1(prov$resource$filename)
        local <- if (!is.null(dfile)) file.path(d, dfile)
        is_csv <- grepl("\\.csv$", got, ignore.case = TRUE) ||
          grepl("\\.csv$", res$source, ignore.case = TRUE)
        cur <- if (is_csv) tryCatch(utils::read.csv(got, check.names = FALSE, stringsAsFactors = FALSE),
                                    error = function(e) NULL)
        if (res$changed) {
          ref <- if (is_csv && !is.null(local) && file.exists(local))
            tryCatch(utils::read.csv(local, check.names = FALSE, stringsAsFactors = FALSE),
                     error = function(e) NULL)
          if (!is.null(ref) && !is.null(cur)) {
            dr <- cpsdrft(ref, cur)
            cols <- dr$columns
            hit <- cols[!is.na(cols$drifted) & cols$drifted, , drop = FALSE]
            res$drift <- list(any = isTRUE(dr$anydrft), nref = dr$nref, ncur = dr$ncur,
                              added = dr$added, removed = dr$removed,
                              columns = lapply(seq_len(nrow(cols)), function(i) as.list(cols[i, ])))
            res$drift_summary <- paste0(
              sprintf("%d of %d columns drifted", nrow(hit), nrow(cols)),
              if (nrow(hit)) paste0(": ", paste(utils::head(sprintf("%s (stat %s, p %s, PSI %s)",
                hit$column, fmt(hit$statistic), fmt(hit$p_value), fmt(hit$psi)), 3L), collapse = "; ")),
              if (length(dr$added)) paste0("; added ", paste(dr$added, collapse = ", ")),
              if (length(dr$removed)) paste0("; removed ", paste(dr$removed, collapse = ", ")),
              sprintf("; rows %d -> %d", dr$nref, dr$ncur))
            if (dr$anydrft && res$result == "ok") res$result <- "drift"
            if (!dr$anydrft) notes$add("the bytes changed but no column drifted")
          } else {
            notes$add("the source's digest changed; the distributions could not be compared (no local CSV copy)")
            if (res$result == "ok") res$result <- "drift"
          }
        }
        if (mode == "refresh" && res$changed) {
          issues <- if (!is.null(cur) && !is.null(prov$schema)) valsch(cur, prov) else list()
          fatal <- vapply(issues, function(i) identical(i$severity, "fatal"), logical(1))
          if (is.null(dfile) || is.null(rel_ok(dfile))) {
            notes$add("refresh skipped: resource$filename is missing or not a plain relative path")
            res$result <- "error"
          } else if (any(fatal)) {
            notes$add(paste("refresh skipped: the new data fail the pinned schema:",
                            paste(vapply(issues[fatal], `[[`, "", "message"), collapse = "; ")))
            res$result <- "error"
          } else {
            prov$resource$sha256 <- res$fetched_sha256
            if (!is.null(prov$resource$size_bytes)) prov$resource$size_bytes <- file.size(got)
            if (!is.null(prov$resource$row_count_data_rows) && !is.null(cur)) {
              prov$resource$row_count_data_rows <- nrow(cur)
            }
            prov$resource$retrieved_utc <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
            if (wayback && grepl("^https?://", res$source)) {
              wb <- tryCatch(wbsave(res$source, quiet = TRUE), error = function(e) {
                notes$add(paste("wayback:", conditionMessage(e)))
                NULL
              })
              if (!is.null(wb) && nrow(wb) && wb$status[1L] %in% c("saved", "existing")) {
                prov$wayback$csv_snapshot <- wb$snapshot[1L]
                prov$wayback$captured_at_utc <- prov$resource$retrieved_utc
              } else if (!is.null(wb)) {
                notes$add(paste("wayback: capture", wb$status[1L], wb$message[1L]))
              }
            }
            js <- prov_json(prov)  # serialised first: nothing is written unless both can be
            file.copy(got, local, overwrite = TRUE)
            writeLines(js, prov_file)
            Sys.chmod(c(local, prov_file), "0666", use_umask = FALSE)
            notes$add("refreshed: new data and provenance written to the workspace")
            if (file.exists(bundle_file)) {
              notes$add("capsule_bundle.json no longer matches the data: re-sign it with cpsbndl()")
            }
            again <- vrfcps(d)
            if (!isTRUE(again$ok)) {
              res$result <- "error"
              for (x in failed_rows(again, "after refresh ")) notes$add(x)
            }
          }
        }
      }
    }
  }
  res$notes <- as.list(notes$get())  # always a JSON array
  res
}
# a data file name that stays inside the capsule
rel_ok <- function(f) {
  if (grepl("^(/|~)|(^|/)\\.\\.(/|$)|^[A-Za-z]:", f)) NULL else f
}
`%||%` <- function(a, b) if (is.null(a)) b else a

results <- lapply(dirs, function(d) {
  tryCatch(check_capsule(d), error = function(e) {
    list(capsule = d, source = "", pinned_sha256 = "", fetched_sha256 = "", result = "error",
         changed = FALSE, checks_passed = 0L, checks_total = 0L, drift = NULL,
         notes = list(paste("check stopped:", conditionMessage(e))))
  })
})

st <- vapply(results, `[[`, "", "result")
status <- if (any(st == "error")) "error" else if (any(st == "drift")) "drift" else "ok"
changed <- vapply(Filter(function(r) isTRUE(r$changed), results), `[[`, "", "capsule")

esc <- function(x) gsub("|", "\\|", gsub("\n", " ", x, fixed = TRUE), fixed = TRUE)
md <- c(sprintf("## rmbl capsule %s: %s", mode, status), "")
if (!length(dirs)) {
  md <- c(md, sprintf("No manifests found under `%s`%s.", root,
                      if (nzchar(glob)) sprintf(" matching `%s`", glob) else ""))
} else {
  md <- c(md, sprintf("%d capsule(s) under `%s`: %d ok, %d drift, %d error.", length(dirs), root,
                      sum(st == "ok"), sum(st == "drift"), sum(st == "error")), "",
          paste0("| Capsule | Source | Pinned SHA-256 | Result | Checks |",
                 if (mode %in% c("drift", "refresh")) " Drift |" else ""),
          paste0("|---|---|---|---|---|", if (mode %in% c("drift", "refresh")) "---|" else ""))
  for (r in results) {
    md <- c(md, paste0(sprintf("| `%s` | %s | `%s` | %s | %d/%d |", esc(r$capsule),
                               if (nzchar(r$source)) esc(r$source) else "-",
                               short(r$pinned_sha256), r$result, r$checks_passed, r$checks_total),
                       if (mode %in% c("drift", "refresh"))
                         sprintf(" %s |", esc(r$drift_summary %||%
                                                (if (isTRUE(r$changed)) "changed" else if (nzchar(r$fetched_sha256)) "unchanged" else "-")))
                       else ""))
  }
  for (r in results) if (length(r$notes)) {
    md <- c(md, "", sprintf("**%s**", r$capsule), "", paste0("- ", esc(unlist(r$notes))))
  }
}
md <- c(md, "", sprintf("rmoriebricklayer %s, mode `%s`, fail-on `%s`.",
                        utils::packageVersion("rmoriebricklayer"), mode, fail_on))
writeLines(md, report_path)
summ <- Sys.getenv("GITHUB_STEP_SUMMARY")
if (nzchar(summ)) cat(md, file = summ, sep = "\n", append = TRUE)
cat(md, sep = "\n")

writeLines(tojs(list(status = status, mode = mode, path = root, capsules = results),
                auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA_real_), json_path)

out <- Sys.getenv("GITHUB_OUTPUT")
if (nzchar(out)) {
  cat(sprintf("status=%s\nreport=%s\njson=%s\nchanged=%s\nverified=%d\nfailed=%d\n", status,
              report_path, json_path, paste(changed, collapse = ","),
              sum(st != "error"), sum(st == "error")), file = out, append = TRUE)
}

fail <- mode != "report" && switch(fail_on, error = status == "error",
                                    drift = status %in% c("error", "drift"), never = FALSE)
if (fail) cat(sprintf("::error::rmbl: status %s (fail-on %s)\n", status, fail_on))
quit(status = if (fail) 1L else 0L)
