#!/usr/bin/env bash
# rmbl-action entrypoint: mask the key, hand it to the package, then run the checks.
set -euo pipefail

# On GitHub the key is the action's own `key` input (INPUT_KEY) and nothing else: an input left
# empty does not clear a job or workflow env of the same name, so an RMBL_KEY from there must
# never reach the checks (it would sign in mode sign). Run by hand (docker run -e RMBL_KEY=...),
# RMBL_KEY is the input.
if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
  unset RMBL_KEY
  if [ -n "${INPUT_KEY:-}" ]; then export RMBL_KEY="${INPUT_KEY}"; fi
fi
unset INPUT_KEY

if [ -n "${RMBL_KEY:-}" ]; then
  echo "::add-mask::${RMBL_KEY}"
  # the data-service key; check.R also reads RMBL_KEY as the hmac secret of a bundle, and drops
  # MORIE_HOSTED_KEY when a bundle is hmac-signed
  export MORIE_HOSTED_KEY="${RMBL_KEY}"
fi

# the workspace belongs to the runner's user, not this container's: let git read it
# (the manifest comparison runs `git show <base>:<path>`)
git config --global --add safe.directory "${GITHUB_WORKSPACE:-$PWD}" 2>/dev/null || true

exec Rscript --no-save --no-restore /rmbl/check.R
