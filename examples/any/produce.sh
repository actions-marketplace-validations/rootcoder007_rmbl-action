#!/bin/sh
# The universal path from plain POSIX sh: write the data and a plain provenance, nothing else.
# No digest, no JSON library, no key: the action's mode sign pins and signs them in CI.
# Usage: sh produce.sh <capsule dir>
set -eu
mkdir -p "$1"
{ echo "x,y"; for x in 1 2 3; do printf '%d,%d\n' "$x" $((x * x)); done; } > "$1/data.csv"
printf '%s\n' '{"name": "squares", "source": {"url": "https://example.org/squares.csv"}, "resource": {"filename": "data.csv"}}' \
  > "$1/data_provenance.json"
