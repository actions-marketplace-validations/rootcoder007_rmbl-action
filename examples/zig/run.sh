#!/bin/sh
# Build and run the Zig producer (Zig 0.14): sh run.sh <capsule dir>
set -eu
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$1"
out=$(cd "$1" && pwd)
cd "${TMPDIR:-/tmp}"
zig build-exe -O ReleaseSafe -femit-bin=rmbl-capsule-zig "$here/capsule.zig"
exec ./rmbl-capsule-zig "$out"
