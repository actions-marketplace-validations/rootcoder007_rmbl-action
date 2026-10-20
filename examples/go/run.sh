#!/bin/sh
# Build and run the Go producer: sh run.sh <capsule dir>
set -eu
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$1"
out=$(cd "$1" && pwd)
(cd "$here" && go build -o "${TMPDIR:-/tmp}/rmbl-capsule-go" .)
exec "${TMPDIR:-/tmp}/rmbl-capsule-go" "$out"
