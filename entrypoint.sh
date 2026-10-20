#!/usr/bin/env bash
# rmbl-action entrypoint: hand the data-service key to the package, then run the checks.
set -euo pipefail

if [ -n "${RMBL_KEY:-}" ]; then
  echo "::add-mask::${RMBL_KEY}"
  export MORIE_HOSTED_KEY="${RMBL_KEY}"
fi
unset RMBL_KEY

# the workspace belongs to the runner's user, not this container's: let git read it
# (the manifest comparison runs `git show <base>:<path>`)
git config --global --add safe.directory "${GITHUB_WORKSPACE:-$PWD}" 2>/dev/null || true

exec Rscript --no-save --no-restore /rmbl/check.R
