#!/bin/sh
# Build (nothing to build) and run the Node producer: sh run.sh <capsule dir>
set -eu
mkdir -p "$1"
exec node "$(dirname "$0")/capsule.mjs" "$1"
