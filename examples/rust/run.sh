#!/bin/sh
# Build (from Cargo.lock) and run the Rust producer: sh run.sh <capsule dir>
set -eu
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$1"
cargo run --quiet --locked --release --manifest-path "$here/Cargo.toml" -- "$1"
