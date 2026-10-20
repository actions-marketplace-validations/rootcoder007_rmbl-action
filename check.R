# rmbl-action: verify, drift-check, refresh or report rmoriebricklayer data capsules.
# A capsule is a directory holding data_provenance.json (checked with vrfcps()) and/or
# capsule_bundle.json (checked with cpsbndlvrf()). Inputs arrive as RMBL_* variables.
suppressPackageStartupMessages(library(rmoriebricklayer))
options(morie.progress = FALSE)
`%||%` <- function(a, b) if (is.null(a)) b else a

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
glob <- env("RMBL_MANIFESTS", "")
pubkey <- env("RMBL_PUBLIC_KEY", "")
wayback <- flag("RMBL_WAYBACK", "false")
use_cache <- flag("RMBL_CACHE", "false")
allow_file <- flag("RMBL_ALLOW_FILE", "false")
snapshot <- flag("RMBL_SNAPSHOT", "false")
comment <- tolower(env("RMBL_COMMENT", "false"))
# the bands drftpsi() documents: below 0.1 stable, 0.1 to 0.25 worth a look, above 0.25 material
psi_warn <- number("RMBL_PSI_WARN", "0.1")
psi_fail <- number("RMBL_PSI_FAIL", "0.25")
event <- env("GITHUB_EVENT_NAME")
base_ref <- env("RMBL_BASE_REF", if (event %in% c("pull_request", "pull_request_target")) env("GITHUB_BASE_REF") else "")
if (!mode %in% c("verify", "drift", "refresh", "report")) {
  usage("mode must be verify, drift, refresh or report, not '%s'", mode)
}
if (!fail_on %in% c("warn", "drift", "error", "never")) {
  usage("fail-on must be warn, drift, error or never, not '%s'", fail_on)
}
if (!comment %in% c("true", "false", "dry-run")) usage("comment must be true, false or dry-run, not '%s'", comment)
if (psi_warn > psi_fail) usage("psi-warn (%g) must not exceed psi-fail (%g)", psi_warn, psi_fail)
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

rank <- c(ok = 0L, warn = 1L, drift = 2L, error = 3L)
worse <- function(a, b) if (rank[[b]] > rank[[a]]) b else a
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
# where the package raises a message, from explerr() (offline: it searches the package's code)
explain <- function(msg) {
  e <- tryCatch(explerr(msg, n = 1L), error = function(e) NULL)
  if (is.null(e) || !nrow(e)) return(NULL)
  sprintf("explained: raised by %s() (reached from %s); as written: \"%s\"",
          e$raised_by[1L], e$exported[1L], e$message[1L])
}
# ---- a small JSON Schema (2020-12 subset) validator over fromjs() output: type, enum,
# required, properties, additionalProperties, items, pattern, minLength, minimum.
# ponytail: the subset the files in spec/ use; $ref, oneOf and friends are not implemented.
spec_dir <- env("RMBL_SPEC_DIR", "/rmbl/spec")
spec <- function(name) fromjs(paste(readLines(file.path(spec_dir, name), warn = FALSE), collapse = "\n"),
                              simplifyVector = FALSE)
jtype <- function(x) {
  if (is.null(x)) return("null")
  if (is.list(x)) {
    if (!length(x)) return("empty")
    return(if (!is.null(names(x)) && all(nzchar(names(x)))) "object" else "array")
  }
  if (length(x) != 1L) return("array")
  if (is.logical(x)) "boolean" else if (is.character(x)) "string"
  else if (is.numeric(x)) (if (is.finite(x) && x == round(x)) "integer" else "number") else "unknown"
}
validate <- function(x, s, at = "$") {
  t <- jtype(x)
  if (!is.null(s$type)) {
    want <- unlist(s$type)
    if (!any(want == t | (want == "number" & t == "integer") | (t == "empty" & want %in% c("object", "array")))) {
      return(sprintf("%s: expected %s, got %s", at, paste(want, collapse = " or "), t))
    }
  }
  err <- character()
  if (!is.null(s$enum) && !(length(x) == 1L && x %in% unlist(s$enum))) {
    err <- c(err, sprintf("%s: must be one of %s", at, paste(unlist(s$enum), collapse = ", ")))
  }
  if (t == "string") {
    if (!is.null(s$pattern) && !grepl(s$pattern, x, perl = TRUE)) err <- c(err, sprintf("%s: does not match %s", at, s$pattern))
    if (!is.null(s$minLength) && nchar(x) < s$minLength) err <- c(err, sprintf("%s: shorter than %d", at, s$minLength))
  }
  if (t %in% c("integer", "number") && !is.null(s$minimum) && x < s$minimum) {
    err <- c(err, sprintf("%s: below %s", at, s$minimum))
  }
  if (t == "object") {
    miss <- setdiff(unlist(s$required), names(x))
    if (length(miss)) err <- c(err, sprintf("%s: missing required %s", at, paste(miss, collapse = ", ")))
    for (nm in names(x)) {
      sub <- s$properties[[nm]] %||% (if (is.list(s$additionalProperties)) s$additionalProperties)
      if (!is.null(sub)) err <- c(err, validate(x[[nm]], sub, paste0(at, ".", nm)))
    }
  } else if (t == "empty") {
    miss <- unlist(s$required)
    if (length(miss)) err <- c(err, sprintf("%s: missing required %s", at, paste(miss, collapse = ", ")))
  }
  if (t == "array" && is.list(s$items)) {
    for (i in seq_along(x)) err <- c(err, validate(x[[i]], s$items, sprintf("%s[%d]", at, i - 1L)))
  }
  err
}
spec_row <- function(path, schema_name) {
  x <- tryCatch(fromjs(paste(readLines(path, warn = FALSE), collapse = "\n"), simplifyVector = FALSE),
                error = function(e) e)
  err <- if (inherits(x, "error")) paste("not valid JSON:", conditionMessage(x)) else validate(x, spec(schema_name))
  data.frame(part = "spec", file = path, check = paste0("schema: ", basename(path)), ok = !length(err),
             detail = if (length(err)) paste(utils::head(err, 5L), collapse = "; ") else paste("valid against", schema_name),
             stringsAsFactors = FALSE)
}

rel_ok <- function(f) if (grepl("^(/|~)|(^|/)\\.\\.(/|$)|^[A-Za-z]:", f)) NULL else f

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
      x <- explain(conditionMessage(e))
      if (!is.null(x)) notes$add(x)
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

# Per-column verdict from cpsdrft() and the PSI bands: drift needs a flagged column above
# psi-fail; a flagged column below it, or any column above psi-warn, is a warning.
column_verdicts <- function(cols) {
  band <- ifelse(is.na(cols$psi), "-", ifelse(cols$psi > psi_fail, "fail", ifelse(cols$psi > psi_warn, "warn", "ok")))
  flagged <- !is.na(cols$drifted) & cols$drifted
  verdict <- ifelse(flagged & band == "fail", "drift", ifelse(flagged | band %in% c("warn", "fail"), "warn", "ok"))
  data.frame(band = band, verdict = verdict, stringsAsFactors = FALSE)
}

# The PR's manifest against the base branch's copy, through mnfrcmp(): the base copy is the
# record, the PR's observed values are what is "recomputed", each within the base's own tol.
git_base <- function(path) {
  for (ref in unique(c(base_ref, paste0("origin/", base_ref)))) {
    out <- suppressWarnings(system2("git", c("show", sprintf("%s:./%s", ref, path)),
                                    stdout = TRUE, stderr = FALSE))
    if (is.null(attr(out, "status"))) return(out)
  }
  NULL
}
manifest_diff <- function(d) {
  out <- list()
  for (m in file.path(d, c("manifest.json", "results/manifest.json"))) {
    base_txt <- git_base(m)
    if (!file.exists(m) && is.null(base_txt)) next
    if (is.null(base_txt)) {
      out[[m]] <- list(path = m, state = "added", changed = TRUE)
      next
    }
    if (!file.exists(m)) {
      out[[m]] <- list(path = m, state = "removed", changed = TRUE)
      next
    }
    tf <- tempfile(fileext = ".json")
    writeLines(base_txt, tf)
    base <- loadprov(tf)
    pr <- loadprov(m)
    if (!length(pr$results)) {
      out[[m]] <- list(path = m, state = "no results", changed = length(base$results) > 0L)
      next
    }
    stats <- lapply(pr$results, function(r) {
      v <- r$observed
      force(v)
      function(z) v
    })
    cmp <- tryCatch(mnfrcmp(base, NULL, stats), error = function(e) e)
    if (inherits(cmp, "error")) {
      out[[m]] <- list(path = m, state = paste("not compared:", conditionMessage(cmp)), changed = TRUE)
      next
    }
    out[[m]] <- list(path = m, state = "compared", changed = !isTRUE(cmp$ok),
                     results = cmp$results, removed = cmp$unchecked)
  }
  unname(out)
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
  keep_rows <- function(chk, label, file) {
    ck <- chk$checks
    if (length(chk$missing)) {
      ck <- rbind(ck, data.frame(check = chk$missing, ok = FALSE,
                                 detail = "required check was never made"))
    }
    rows[[length(rows) + 1L]] <<- cbind(part = label, file = file, ck)
  }
  # every capsule file against its schema in spec/, before the package's checks
  for (sp in list(c(prov_file, "capsule.schema.json"), c(bundle_file, "bundle.schema.json"),
                  c(file.path(d, "manifest.json"), "manifest.schema.json"),
                  c(file.path(d, "results", "manifest.json"), "manifest.schema.json"))) {
    if (!file.exists(sp[[1L]])) next
    row <- spec_row(sp[[1L]], sp[[2L]])
    rows[[length(rows) + 1L]] <- row
    res$checks_passed <- res$checks_passed + row$ok
    res$checks_total <- res$checks_total + 1L
    if (!row$ok) {
      res$result <- "error"
      notes$add(paste0(row$check, ": ", row$detail))
    }
  }
  res$.size <- NA_real_
  res$.rows_n <- NA_real_
  res$.bounds <- "-"
  if (!is.null(prov)) {
    res$source <- str1(prov$resource$direct_url) %||% str1(prov$source$url) %||% ""
    res$pinned_sha256 <- str1(prov$resource$sha256) %||% ""
    dfile0 <- str1(prov$resource$filename)
    if (!is.null(dfile0) && file.exists(file.path(d, dfile0))) res$.size <- file.size(file.path(d, dfile0))
    res$.rows_n <- suppressWarnings(as.numeric(str1(prov$resource$row_count_data_rows) %||% NA))
    rnd <- str1(prov$table$rounding)
    sup <- str1(prov$table$suppression_limit) %||% str1(prov$table$suplim)
    if (!is.null(rnd) || !is.null(sup)) {
      res$.bounds <- paste(c(if (!is.null(rnd)) paste("round", rnd), if (!is.null(sup)) paste("supp", sup)),
                           collapse = " · ")
    }
    chk <- vrfcps(d)
    keep_rows(chk, "provenance", prov_file)
    res$checks_passed <- res$checks_passed + sum(chk$checks$ok)
    res$checks_total <- res$checks_total + nrow(chk$checks) + length(chk$missing)
    if (!isTRUE(chk$ok)) {
      res$result <- "error"
      for (x in failed_rows(chk)) notes$add(x)
    }
    if (snapshot) {
      if (grepl("^https?://", res$source)) {
        s <- tryCatch(wbsnpurl(res$source), error = function(e) NULL)
        res$snapshot <- s %||% ""
        ts <- if (!is.null(s)) regmatches(s, regexpr("(?<=/web/)[0-9]{14}", s, perl = TRUE)) else character()
        res$snapshot_utc <- if (length(ts)) format(as.POSIXct(ts, "%Y%m%d%H%M%S", tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ") else ""
        notes$add(if (is.null(s)) "snapshot: none found (or the archive could not be reached)"
                  else sprintf("snapshot: %s (%s)", s, res$snapshot_utc))
      } else {
        notes$add("snapshot: not looked up (not an http(s) source)")
      }
    }
  }
  if (file.exists(bundle_file)) {
    bchk <- cpsbndlvrf(bundle_file, d, keyexp = if (nzchar(pubkey)) pubkey)
    keep_rows(bchk, "bundle", bundle_file)
    res$checks_passed <- res$checks_passed + sum(bchk$checks$ok)
    res$checks_total <- res$checks_total + nrow(bchk$checks)
    if (!isTRUE(bchk$ok)) {
      res$result <- "error"
      for (x in failed_rows(bchk, "bundle ")) notes$add(x)
    }
  }
  if (nzchar(base_ref)) res$.manifests <- manifest_diff(d)

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
            dr <- cpsdrft(ref, cur, psithr = psi_fail)
            res$.drift <- dr
            # the Benford first-digit screen of each numeric column, old and new data
            bf <- function(x) if (is.numeric(x)) tryCatch(benfordtst(x)$p_value, error = function(e) NA_real_) else NA_real_
            res$.benford <- lapply(dr$columns$column, function(nm) c(ref = bf(ref[[nm]]), cur = bf(cur[[nm]])))
            cols <- dr$columns
            cv <- column_verdicts(cols)
            res$.verdicts <- cv
            hit <- cols[cv$verdict != "ok", , drop = FALSE]
            res$drift <- list(any = isTRUE(dr$anydrft), nref = dr$nref, ncur = dr$ncur,
                              added = dr$added, removed = dr$removed,
                              columns = lapply(seq_len(nrow(cols)), function(i) c(as.list(cols[i, ]), as.list(cv[i, ]))))
            res$drift_summary <- paste0(
              sprintf("%d of %d columns past a band", nrow(hit), nrow(cols)),
              if (nrow(hit)) paste0(": ", paste(utils::head(sprintf("%s (stat %s, p %s, PSI %s)",
                hit$column, fmt(hit$statistic), fmt(hit$p_value), fmt(hit$psi)), 3L), collapse = "; ")),
              if (length(dr$added)) paste0("; added ", paste(dr$added, collapse = ", ")),
              if (length(dr$removed)) paste0("; removed ", paste(dr$removed, collapse = ", ")),
              sprintf("; rows %d -> %d", dr$nref, dr$ncur))
            found <- if (any(cv$verdict == "drift") || length(dr$added) || length(dr$removed)) "drift"
                     else if (any(cv$verdict == "warn")) "warn" else "ok"
            res$result <- worse(res$result, found)
            if (found == "ok") notes$add("the bytes changed but no column crossed a band")
          } else {
            notes$add("the source's digest changed; the distributions could not be compared (no local CSV copy)")
            res$result <- worse(res$result, "warn")
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
            keep_rows(again, "after refresh", prov_file)
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

fp <- co2fp(lapply(dirs, function(d) {
  tryCatch(check_capsule(d), error = function(e) {
    x <- explain(conditionMessage(e))
    list(capsule = d, source = "", pinned_sha256 = "", fetched_sha256 = "", result = "error",
         changed = FALSE, checks_passed = 0L, checks_total = 0L, drift = NULL,
         notes = as.list(c(paste("check stopped:", conditionMessage(e)), x)))
  })
}))
results <- fp$value

st <- vapply(results, `[[`, "", "result")
status <- if (length(st)) names(rank)[max(rank[st]) + 1L] else "ok"
changed <- vapply(Filter(function(r) isTRUE(r$changed), results), `[[`, "", "capsule")
mdiffs <- unlist(lapply(results, function(r) r$.manifests), recursive = FALSE)
manifest_changed <- any(vapply(mdiffs, function(m) isTRUE(m$changed), logical(1)))

# ---- annotations: inline in the Files tab and the run header
ann_data <- function(x) gsub("\n", "%0A", gsub("\r", "%0D", gsub("%", "%25", x, fixed = TRUE), fixed = TRUE), fixed = TRUE)
ann_prop <- function(x) gsub(",", "%2C", gsub(":", "%3A", ann_data(x), fixed = TRUE), fixed = TRUE)
for (r in results) {
  f <- if (file.exists(file.path(r$capsule, "data_provenance.json"))) file.path(r$capsule, "data_provenance.json")
       else file.path(r$capsule, "capsule_bundle.json")
  ck <- r$.rows
  if (!is.null(ck)) for (i in which(!ck$ok)) {
    cat(sprintf("::error file=%s,title=%s::%s\n", ann_prop(ck$file[i]),
                ann_prop(paste("rmbl", ck$part[i], ck$check[i])), ann_data(ck$detail[i])))
  }
  other <- unlist(r$notes)
  other <- other[grepl("^(fetch refused|source could not|no resource|the source URL is still|refresh skipped|check stopped)", other)]
  for (x in other) cat(sprintf("::error file=%s,title=rmbl::%s\n", ann_prop(f), ann_data(x)))
  if (r$result %in% c("drift", "warn")) {
    cat(sprintf("::warning file=%s,title=rmbl %s::%s\n", ann_prop(f), r$result,
                ann_data(r$drift_summary %||% "the source changed")))
  }
}

# ---- Markdown report
esc <- function(x) gsub("|", "\\|", gsub("\n", " ", x, fixed = TRUE), fixed = TRUE)
mark <- c(ok = "✔", warn = "⚠", drift = "⚠", error = "✖")
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
  md <- c(md, sprintf("**%s %s**: %d capsule%s under `%s`: %d ok, %d warn, %d drift, %d error", mark[[status]], status,
                      length(dirs), if (length(dirs) == 1L) "" else "s", root,
                      sum(st == "ok"), sum(st == "warn"), sum(st == "drift"), sum(st == "error")), "",
          "| Capsule | Source | SHA-256 | Size | Rows | Bounds | Result |",
          "|---|---|---|---|---|---|---|")
  for (r in results) {
    md <- c(md, sprintf("| `%s` | %s | `%s` | %s | %s | %s | %s %s |", esc(r$capsule), esc(host(r$source)),
                        if (nzchar(r$pinned_sha256)) short(r$pinned_sha256) else "-",
                        kb(r$.size %||% NA), if (is.na(r$.rows_n %||% NA)) "-" else format(r$.rows_n, big.mark = ","),
                        esc(r$.bounds %||% "-"), mark[[r$result]], r$result))
  }
  if (length(mdiffs)) {
    md <- c(md, "", sprintf("### Manifests against `%s`%s", base_ref,
                            if (manifest_changed) ": changed" else ": unchanged"))
    for (m in mdiffs) {
      if (!identical(m$state, "compared")) {
        md <- c(md, "", sprintf("`%s`: %s", m$path, m$state))
        next
      }
      rr <- m$results
      md <- c(md, "", sprintf("`%s`: %d result%s compared%s", m$path, nrow(rr), if (nrow(rr) == 1L) "" else "s",
                              if (length(m$removed)) paste0(", removed: ", paste(m$removed, collapse = ", ")) else ""),
              "", "| | Result | Base | PR | Change | Tol |", "|---|---|---|---|---|---|",
              sprintf("| %s | %s | %s | %s | %s | %s |",
                      ifelse(rr$status == "MATCH", mark[["ok"]], ifelse(rr$status == "NOT_RECORDED", "new", mark[["error"]])),
                      esc(rr$name), num(rr$recorded, 6), num(rr$recomputed, 6),
                      ifelse(is.na(rr$delta), "-", ifelse(rr$status == "MATCH", paste(num(rr$delta), "(within tol)"),
                                                          paste(num(rr$delta), "(outside tol)"))),
                      num(rr$tol)))
    }
  }
  for (r in results) {
    md <- c(md, "", "<details>",
            sprintf("<summary>%s <code>%s</code>: %s, %d of %d checks passed (click to open)</summary>",
                    mark[[r$result]], r$capsule, r$result, r$checks_passed, r$checks_total), "")
    if (nzchar(r$source)) md <- c(md, sprintf("- Source: %s", esc(r$source)))
    if (nzchar(r$pinned_sha256)) md <- c(md, sprintf("- Pinned SHA-256: `%s`", r$pinned_sha256))
    if (nzchar(r$fetched_sha256)) md <- c(md, sprintf("- Fetched SHA-256: `%s`%s", r$fetched_sha256,
                                                      if (isTRUE(r$changed)) " (changed)" else " (same)"))
    if (!identical(r$.bounds %||% "-", "-")) md <- c(md, sprintf("- Publication bounds recorded: %s", r$.bounds))
    if (!is.null(r$.rows)) {
      ck <- r$.rows
      md <- c(md, "", "| | Check | Detail |", "|---|---|---|",
              sprintf("| %s | %s%s | %s |", ifelse(ck$ok, mark[["ok"]], mark[["error"]]),
                      ifelse(ck$part %in% c("provenance", "spec"), "", paste0(ck$part, ": ")), esc(ck$check),
                      esc(ifelse(nzchar(ck$detail), ck$detail, "-"))))
    }
    dr <- r$.drift
    if (!is.null(dr)) {
      sm <- summary(dr)  # the package's own verdict
      cv <- r$.verdicts
      md <- c(md, "", sprintf("**Drift: %s %s.** %d of %d columns flagged by the package (%s)%s%s; PSI bands: warn above %g, fail above %g; rows %s to %s, alpha %s.",
                              mark[[r$result]],
                              c(ok = "no column crossed a band", warn = "a column crossed the warn band",
                                drift = "drift above the fail band", error = "see the checks")[[r$result]],
                              sm$ndri, sm$ntes,
                              if (length(sm$drifted)) paste(sm$drifted, collapse = ", ") else "none",
                              if (length(sm$added)) paste0("; added ", paste(sm$added, collapse = ", ")) else "",
                              if (length(sm$removed)) paste0("; removed ", paste(sm$removed, collapse = ", ")) else "",
                              psi_warn, psi_fail,
                              format(dr$nref, big.mark = ","), format(dr$ncur, big.mark = ","), dr$alpha))
      cols <- dr$columns
      if (nrow(cols)) {
        bfp <- do.call(rbind, r$.benford)
        md <- c(md, "",
                "| | Column | Type | Statistic | p | PSI (band) | JS | Benford p (pinned / new) |",
                "|---|---|---|---|---|---|---|---|",
                sprintf("| %s | %s | %s | %s | %s | %s | %s | %s |",
                        mark[cv$verdict], esc(cols$column), cols$type,
                        ifelse(is.na(cols$statistic), "-",
                               paste(ifelse(cols$type %in% c("numeric", "date"), "KS D", "χ²"),
                                     num(cols$statistic))),
                        num(cols$p_value), paste0(num(cols$psi), ifelse(cv$band == "-", "", paste0(" (", cv$band, ")"))),
                        num(cols$jsdiv),
                        ifelse(is.na(bfp[, "ref"]) & is.na(bfp[, "cur"]), "-",
                               paste(num(bfp[, "ref"]), "/", num(bfp[, "cur"])))))
      }
    }
    if (length(r$notes)) {
      nt <- unlist(r$notes)
      md <- c(md, "", paste0(ifelse(startsWith(nt, "explained:"), "  - ", "- "), esc(nt)))
    }
    md <- c(md, "", "</details>")
  }
}
ci <- fp$co2int
md <- c(md, "", "---", "",
        sprintf("Footprint of these checks (co2fp(), %s): %.1f s wall, %.1f s CPU, %.3g Wh, %.3g gCO2e at %.4g gCO2e/kWh (%s%s).",
                if (fp$method == "rapl") "measured with RAPL" else "modelled, Green Algorithms",
                fp$durs, fp$cputms, fp$enekwh$total * 1000, fp$co2eg, ci$g_per_kwh, ci$name,
                if (is.na(ci$year)) "" else paste0(", ", ci$year)),
        "",
        sprintf("mode `%s` · fail-on `%s` · rmoriebricklayer %s · %s",
                mode, fail_on, pkgver, R.version.string))
writeLines(enc2utf8(md), report_path, useBytes = TRUE)
summ <- Sys.getenv("GITHUB_STEP_SUMMARY")
if (nzchar(summ)) {
  con <- file(summ, "a", encoding = "UTF-8")
  writeLines(md, con)
  close(con)
}
cat(md, sep = "\n")

# ---- sticky pull-request comment, edited in place (marker below)
marker <- "<!-- rmbl-action -->"
comment_state <- "off"
if (comment != "false") {
  body <- paste(c(marker, md), collapse = "\n")
  if (nchar(body) > 65000L) body <- paste0(substr(body, 1L, 65000L), "\n\n(report cut to fit a comment; the full one is in the job summary)")
  pr <- tryCatch(str1(loadprov(env("GITHUB_EVENT_PATH", "/nonexistent"))$pull_request$number), error = function(e) NULL)
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
        hit <- Filter(function(cm) grepl(marker, cm$body %||% "", fixed = TRUE), got)
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

# ---- JSON (the report-only fields, named with a leading dot, stay out) and outputs
for (i in seq_along(results)) {
  m <- results[[i]]$.manifests
  if (!is.null(m)) results[[i]]$manifests <- lapply(m, function(x) {
    if (!is.null(x$results)) x$results <- lapply(seq_len(nrow(x$results)), function(j) as.list(x$results[j, ]))
    x
  })
}
results <- lapply(results, function(r) r[!startsWith(names(r), ".")])
writeLines(tojs(list(status = status, mode = mode, path = root, capsules = results),
                auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA_real_), json_path)

out <- Sys.getenv("GITHUB_OUTPUT")
if (nzchar(out)) {
  cat(sprintf("status=%s\nreport=%s\njson=%s\nchanged=%s\nverified=%d\nfailed=%d\nmanifest-changed=%s\ncomment=%s\n",
              status, report_path, json_path, paste(changed, collapse = ","),
              sum(st != "error"), sum(st == "error"), tolower(manifest_changed), comment_state),
      file = out, append = TRUE)
}

fail <- mode != "report" && rank[[status]] >= switch(fail_on, warn = 1L, drift = 2L, error = 3L, never = 99L)
if (fail) cat(sprintf("::error::rmbl: status %s (fail-on %s)\n", status, fail_on))
quit(status = if (fail) 1L else 0L)
