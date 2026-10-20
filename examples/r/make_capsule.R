# Write data_provenance.json next to a CSV, with rmoriebricklayer's own digest and JSON writer.
# Usage: Rscript make_capsule.R <csv path> <source url>
library(rmoriebricklayer)
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("usage: Rscript make_capsule.R <csv path> <source url>")
csv <- args[[1L]]
prov <- list(
  name = sub("\\.csv$", "", basename(csv)),
  source = list(url = args[[2L]], retrieved = format(Sys.Date(), "%Y-%m-%d")),
  resource = list(
    filename = basename(csv),                         # relative to the capsule directory
    sha256 = sha256file(csv),                          # what vrfcps() checks
    size_bytes = file.size(csv),
    row_count_data_rows = nrow(utils::read.csv(csv))   # data rows, header excluded
  )
)
writeLines(tojs(prov, auto_unbox = TRUE, pretty = TRUE),
           file.path(dirname(csv), "data_provenance.json"))
