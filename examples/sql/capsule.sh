#!/bin/sh
# A capsule from a SQL project: sqlite3 writes data.csv from squares.sql, then POSIX sh and
# OpenSSL write data_provenance.json and an hmac-signed capsule_bundle.json (HMAC in SQL
# itself is not reasonable). The canonical JSON is written with printf; the one free-text
# field, the note, is escaped byte by byte through od and awk.
# Usage: RMBL_KEY=... sh capsule.sh <capsule dir>
# RMBL_UTC fixes the time (YYYY-MM-DDThh:mm:ssZ), RMBL_NOTE_FILE names a file holding the note.
# The key reaches openssl on its command line: run this where other users cannot list processes.
set -eu
: "${RMBL_KEY:?set RMBL_KEY to the shared secret}"
dir=$1
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$dir"
utc=${RMBL_UTC:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}
date=$(printf %s "$utc" | cut -c 1-10)
note=${RMBL_NOTE_FILE:-/dev/null}

sha() { openssl dgst -sha256 -r "$@" | cut -d ' ' -f 1; }
hmac() { printf %s "$1" | openssl dgst -sha256 -hmac "$RMBL_KEY" -r | cut -d ' ' -f 1; }
size() { wc -c < "$1" | tr -d ' '; }
# the bytes of file $1 as a JSON string in the canonical form (docs/bundle-format.md): awk turns
# each byte into printf format text, plain for printable ASCII, an octal escape otherwise
jstr() {
  printf '"'
  # shellcheck disable=SC2059
  printf "$(od -An -v -tu1 "$1" | awk '
    function oct(v) { return sprintf("\\%03o", v) }
    { for (i = 1; i <= NF; i++) {
        v = $i + 0
        if (v == 34) s = oct(92) oct(34)
        else if (v == 92) s = oct(92) oct(92)
        else if (v == 10) s = oct(92) "n"
        else if (v == 13) s = oct(92) "r"
        else if (v == 9) s = oct(92) "t"
        else if (v == 8) s = oct(92) "b"
        else if (v == 12) s = oct(92) "f"
        else if (v < 32) s = oct(92) sprintf("u%04x", v)
        else if (v == 47 && prev == 60) s = oct(92) "/"
        else if (v == 37 || v > 126) s = oct(v)
        else s = sprintf("%c", v)
        printf "%s", s
        prev = v
    } }')"
  printf '"'
}

# 1. the data, from SQL
sqlite3 -batch < "$here/squares.sql" > "$dir/data.csv"

# 2. the provenance, pinned to the data (keys in sorted order)
rows=$(( $(wc -l < "$dir/data.csv") - 1 ))
printf '{"name":"squares","resource":{"filename":"data.csv","row_count_data_rows":%s,"sha256":"%s","size_bytes":%s},"source":{"retrieved":"%s","url":"https://example.org/squares.csv"}}\n' \
  "$rows" "$(sha "$dir/data.csv")" "$(size "$dir/data.csv")" "$date" > "$dir/data_provenance.json"

# 3. the bundle: the files, the empty manifest's digest, and an hmac attestation over both
entry() { printf '{"path":"%s","sha256":"%s","size_bytes":%s}' "$1" "$(sha "$dir/$1")" "$(size "$dir/$1")"; }
files="[$(entry data.csv),$(entry data_provenance.json)]"
mdig=$(printf '{"meta":[],"results":[]}' | sha)
adig=$(printf '{"meta":{"bundled_utc":"%s","files":%s,"manifest_digest":"%s"},"results":[]}' "$utc" "$files" "$mdig" | sha)
kid=$(hmac public)
head=$(mktemp)
trap 'rm -f "$head"' EXIT
# the attestation's fields without the signature, sorted; the signature sorts between them
{ printf '"context":"","digest":"%s","note":' "$adig"; jstr "$note"
  printf ',"prehash":"none","public":"%s","scheme":"hmac"' "$kid"; } > "$head"
sig=$(hmac "$({ printf '{'; cat "$head"; printf ',"signed_utc":"%s"}' "$utc"; } | sha)")
{ printf '{"attestation":{'; cat "$head"
  printf ',"signature":{"scheme":"hmac","signature":"%s"},"signed_utc":"%s"},"bundled_utc":"%s","files":%s,"manifest_digest":"%s"}\n' \
    "$sig" "$utc" "$utc" "$files" "$mdig"; } > "$dir/capsule_bundle.json"
echo "signed $dir (key id $kid)"
