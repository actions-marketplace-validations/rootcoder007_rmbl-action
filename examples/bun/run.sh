#!/bin/sh
# Run the Bun producer: sh run.sh <capsule dir>
set -eu
mkdir -p "$1"
exec bun run "$(dirname "$0")/capsule.ts" "$1"
