#!/bin/sh
# Run the SQL producer (sqlite3, openssl): sh run.sh <capsule dir>
set -eu
exec sh "$(dirname "$0")/capsule.sh" "$1"
