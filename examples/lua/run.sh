#!/bin/sh
# Run the Lua 5.4 producer: sh run.sh <capsule dir>
set -eu
mkdir -p "$1"
exec lua "$(dirname "$0")/capsule.lua" "$1"
