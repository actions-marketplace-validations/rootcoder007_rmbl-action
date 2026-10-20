#!/bin/sh
# Build and run the C producer (needs libssl-dev): sh run.sh <capsule dir>
set -eu
here=$(cd "$(dirname "$0")" && pwd)
bin="${TMPDIR:-/tmp}/rmbl-capsule-c"
mkdir -p "$1"
${CC:-gcc} -std=c11 -O2 -Wall -Wextra -Werror -o "$bin" "$here/capsule.c" -lcrypto
exec "$bin" "$1"
