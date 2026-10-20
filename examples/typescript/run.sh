#!/bin/sh
# Run the TypeScript producer with Node's built-in type stripping (Node 22.18+): sh run.sh <capsule dir>
set -eu
mkdir -p "$1"
exec node "$(dirname "$0")/capsule.ts" "$1"
