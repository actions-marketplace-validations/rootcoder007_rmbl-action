#!/bin/sh
# Run the Java producer from source (Java 21+): sh run.sh <capsule dir>
set -eu
mkdir -p "$1"
exec java "$(dirname "$0")/Capsule.java" "$1"
