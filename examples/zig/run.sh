#!/bin/sh
# Build and run the Zig producer (Zig 0.14): sh run.sh <capsule dir>
set -eu
bin="${TMPDIR:-/tmp}/rmbl-capsule-zig"
mkdir -p "$1"
zig build-exe -O ReleaseSafe -femit-bin="$bin" "$(dirname "$0")/capsule.zig"
exec "$bin" "$1"
