#!/bin/sh
# Build and run the C++ producer (needs libssl-dev): sh run.sh <capsule dir>
set -eu
here=$(cd "$(dirname "$0")" && pwd)
bin="${TMPDIR:-/tmp}/rmbl-capsule-cpp"
mkdir -p "$1"
${CXX:-g++} -std=c++17 -O2 -Wall -Wextra -Werror -o "$bin" "$here/capsule.cpp" -lcrypto
exec "$bin" "$1"
