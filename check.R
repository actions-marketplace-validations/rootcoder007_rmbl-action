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
  rows <- list()
  keep_rows <- function(chk, label) {
    ck <- chk$checks
    if (length(chk$missing)) {
      ck <- rbind(ck, data.frame(check = chk$missing, ok = FALSE,
                                 detail = "required check was never made"))
    }
    rows[[length(rows) + 1L]] <<- cbind(part = label, ck)
  }
  res$size_bytes <- NA_real_
  res$rows <- NA_real_
  if (!is.null(prov)) {
    dfile0 <- str1(prov$resource$filename)
    if (!is.null(dfile0) && file.exists(file.path(d, dfile0))) {
      res$size_bytes <- file.size(file.path(d, dfile0))
    }
    res$rows <- as.numeric(str1(prov$resource$row_count_data_rows) %||% NA)
    res$source <- str1(prov$resource$direct_url) %||% str1(prov$source$url) %||% ""
    res$pinned_sha256 <- str1(prov$resource$sha256) %||% ""
    chk <- vrfcps(d)
    keep_rows(chk, "provenance")
    res$checks_passed <- sum(chk$checks$ok)
    res$checks_total <- nrow(chk$checks) + length(chk$missing)
    if (!isTRUE(chk$ok)) {
      res$result <- "error"
      for (x in failed_rows(chk)) notes$add(x)
    }
  }
  if (file.exists(bundle_file)) {
    bchk <- cpsbndlvrf(bundle_file, d, keyexp = if (nzchar(pubkey)) pubkey)
    keep_rows(bchk, "bundle")
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
            res$.drift <- dr
            # the Benford first-digit screen of each numeric column, old and new data
            bf <- function(x) if (is.numeric(x)) tryCatch(benfordtst(x)$p_value, error = function(e) NA_real_) else NA_real_
            res$.benford <- lapply(dr$columns$column, function(nm) c(ref = bf(ref[[nm]]), cur = bf(cur[[nm]])))
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
            keep_rows(again, "after refresh")
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
  res$.rows <- if (length(rows)) do.call(rbind, rows)
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
mark <- c(ok = "✔", drift = "⚠", error = "✖")
host <- function(u) {
  if (!nzchar(u)) return("-")
  if (startsWith(u, "file://")) return("local file")
  sub("^[a-z]+://([^/:]+).*$", "\\1", u)
}
num <- function(x, digits = 3) ifelse(is.na(x), "-", trimws(formatC(x, digits = digits, format = "g")))
kb <- function(b) if (is.na(b)) "-" else if (b < 1024^2) sprintf("%.1f KB", b / 1024) else sprintf("%.1f MB", b / 1024^2)
pkgver <- as.character(utils::packageVersion("rmoriebricklayer"))

md <- c(sprintf("## rmbl capsule %s with [rmoriebricklayer %s](https://github.com/rootcoder007/rmorie-bricklayer)",
                mode, pkgver), "")
if (!length(dirs)) {
  md <- c(md, sprintf("✔ No manifests found under `%s`%s.", root,
                      if (nzchar(glob)) sprintf(" matching `%s`", glob) else ""))
} else {
  md <- c(md, sprintf("**%s %s**: %d capsule%s under `%s`: %d ok, %d drift, %d error", mark[[status]], status,
                      length(dirs), if (length(dirs) == 1L) "" else "s", root,
                      sum(st == "ok"), sum(st == "drift"), sum(st == "error")), "",
          "| Capsule | Source | SHA-256 | Size | Rows | Result |",
          "|---|---|---|---|---|---|")
  for (r in results) {
    md <- c(md, sprintf("| `%s` | %s | `%s` | %s | %s | %s %s |", esc(r$capsule), esc(host(r$source)),
                        if (nzchar(r$pinned_sha256)) short(r$pinned_sha256) else "-",
                        kb(r$size_bytes %||% NA), if (is.na(r$rows %||% NA)) "-" else format(r$rows, big.mark = ","),
                        mark[[r$result]], r$result))
  }
  for (r in results) {
    md <- c(md, "", "<details>",
            sprintf("<summary>%s <code>%s</code>: %s, %d of %d checks passed (click to open)</summary>",
                    mark[[r$result]], r$capsule, r$result, r$checks_passed, r$checks_total), "")
    if (nzchar(r$source)) md <- c(md, sprintf("- Source: %s", esc(r$source)))
    if (nzchar(r$pinned_sha256)) md <- c(md, sprintf("- Pinned SHA-256: `%s`", r$pinned_sha256))
    if (nzchar(r$fetched_sha256)) md <- c(md, sprintf("- Fetched SHA-256: `%s`%s", r$fetched_sha256,
                                                      if (isTRUE(r$changed)) " (changed)" else " (same)"))
    if (!is.null(r$.rows)) {
      ck <- r$.rows
      md <- c(md, "", "| | Check | Detail |", "|---|---|---|",
              sprintf("| %s | %s%s | %s |", ifelse(ck$ok, mark[["ok"]], mark[["error"]]),
                      ifelse(ck$part == "provenance", "", paste0(ck$part, ": ")), esc(ck$check),
                      esc(ifelse(nzchar(ck$detail), ck$detail, "-"))))
    }
    dr <- r$.drift
    if (!is.null(dr)) {
      sm <- summary(dr)  # the package's own verdict
      md <- c(md, "", sprintf("**Drift: %s %s.** %d of %d columns drifted%s%s%s; rows %s to %s, alpha %s.",
                              if (isTRUE(sm$anydrft)) mark[["drift"]] else mark[["ok"]],
                              if (isTRUE(sm$anydrft)) "drift detected" else "no drift detected",
                              sm$ndri, sm$ntes,
                              if (length(sm$drifted)) paste0(" (", paste(sm$drifted, collapse = ", "), ")") else "",
                              if (length(sm$added)) paste0("; added ", paste(sm$added, collapse = ", ")) else "",
                              if (length(sm$removed)) paste0("; removed ", paste(sm$removed, collapse = ", ")) else "",
                              format(dr$nref, big.mark = ","), format(dr$ncur, big.mark = ","), dr$alpha))
      cols <- dr$columns
      if (nrow(cols)) {
        bfp <- do.call(rbind, r$.benford)
        md <- c(md, "",
                "| | Column | Type | Statistic | p | PSI | JS | Benford p (pinned / new) |",
                "|---|---|---|---|---|---|---|---|",
                sprintf("| %s | %s | %s | %s | %s | %s | %s | %s |",
                        ifelse(is.na(cols$drifted), "?", ifelse(cols$drifted, mark[["drift"]], mark[["ok"]])),
                        esc(cols$column), cols$type,
                        ifelse(is.na(cols$statistic), "-",
                               paste(ifelse(cols$type %in% c("numeric", "date"), "KS D", "χ²"),
                                     num(cols$statistic))),
                        num(cols$p_value), num(cols$psi), num(cols$jsdiv),
                        ifelse(is.na(bfp[, "ref"]) & is.na(bfp[, "cur"]), "-",
                               paste(num(bfp[, "ref"]), "/", num(bfp[, "cur"])))))
      }
    }
    if (length(r$notes)) md <- c(md, "", paste0("- ", esc(unlist(r$notes))))
    md <- c(md, "", "</details>")
  }
}
md <- c(md, "", "---", "", sprintf("mode `%s` · fail-on `%s` · rmoriebricklayer %s · %s",
                                    mode, fail_on, pkgver, R.version.string))
writeLines(enc2utf8(md), report_path, useBytes = TRUE)
summ <- Sys.getenv("GITHUB_STEP_SUMMARY")
if (nzchar(summ)) {
  con <- file(summ, "a", encoding = "UTF-8")
  writeLines(md, con)
  close(con)
}
cat(md, sep = "\n")

results <- lapply(results, function(r) r[!startsWith(names(r), ".") & !names(r) %in% c("size_bytes", "rows")])
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
