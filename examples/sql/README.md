# SQL (SQLite, DuckDB)

[`squares.sql`](squares.sql) and [`capsule.sh`](capsule.sh) write a signed capsule.

The data comes from SQL: `sqlite3 < squares.sql` writes `data.csv` (a recursive CTE, CSV
on standard output with `.mode list` and `.separator ,`). With DuckDB the same query runs as
`COPY (...) TO 'data.csv' (HEADER)`. HMAC in SQL is not reasonable, so a POSIX `sh` step
signs with `openssl dgst -sha256` and `-hmac`: the canonical JSON is `printf` with the keys
in sorted order, and the one free-text field, the note, is escaped byte by byte through
`od` and `awk`. The key reaches `openssl` on its command line: run it where other users
cannot list processes (a CI runner is fine).

```sh
RMBL_KEY=... sh run.sh <capsule dir>     # sqlite3, then sh capsule.sh <dir>
```

The program writes `data.csv`, `data_provenance.json` (pinned: `resource.sha256`,
`size_bytes`, `row_count_data_rows`) and `capsule_bundle.json` (every file's digest and an
`hmac` attestation), all in the canonical JSON form of
[`docs/bundle-format.md`](../../docs/bundle-format.md). The shared secret comes from
`RMBL_KEY`; set `RMBL_UTC` (`YYYY-MM-DDThh:mm:ssZ`) to fix the time and `RMBL_NOTE_FILE` to
sign a note. Keep build outputs out of the capsule directory: the bundle must list every
file in it.

Verify it in CI with the secret in a repository secret and its key id pinned:

```yaml
      - run: sh examples/sql/run.sh capsules/squares
        env:
          RMBL_KEY: ${{ secrets.CAPSULE_KEY }}
      - uses: rootcoder007/rmbl-action@v1
        with:
          path: capsules
          key: ${{ secrets.CAPSULE_KEY }}
          public-key: ${{ vars.CAPSULE_KEY_ID }}  # printed by the program
```

The test workflow's `example-native (sql)` job writes the vectors of
[`spec/vectors/`](../../spec/vectors) with this program and compares them byte for byte, then
runs the action on a fresh capsule (status ok, signature row passing) and again after
flipping one byte of `data.csv` (the step fails on `file:data.csv` and `data_sha256`).
