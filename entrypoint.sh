#!/usr/bin/env bash
# rmbl-action entrypoint: hand the data-service key to the package, then run the checks.
set -euo pipefail

if [ -n "${RMBL_KEY:-}" ]; then
  echo "::add-mask::${RMBL_KEY}"
  export MORIE_HOSTED_KEY="${RMBL_KEY}"
fi
unset RMBL_KEY

exec Rscript --no-save --no-restore /rmbl/check.R
