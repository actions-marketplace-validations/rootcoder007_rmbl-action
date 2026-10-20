# C

[`capsule.c`](capsule.c) writes a signed capsule; [`make_capsule.c`](make_capsule.c) writes only a
pinned `data_provenance.json` next to an existing CSV (the `example-c` job).

OpenSSL 3's EVP API (`EVP_Digest`, `EVP_Q_mac` for HMAC), C11 plus POSIX `open_memstream()`
for the buffers. JSON is written by hand: `str()` applies the escapes and the fixed keys are
emitted in sorted order.

```sh
RMBL_KEY=... sh run.sh <capsule dir>     # gcc -std=c11 capsule.c -lcrypto, then run
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
      - run: sh examples/c/run.sh capsules/squares
        env:
          RMBL_KEY: ${{ secrets.CAPSULE_KEY }}
      - uses: rootcoder007/rmbl-action@v1
        with:
          path: capsules
          key: ${{ secrets.CAPSULE_KEY }}
          public-key: ${{ vars.CAPSULE_KEY_ID }}  # printed by the program
```

The test workflow's `example-native (c)` job writes the vectors of
[`spec/vectors/`](../../spec/vectors) with this program and compares them byte for byte, then
runs the action on a fresh capsule (status ok, signature row passing) and again after
flipping one byte of `data.csv` (the step fails on `file:data.csv` and `data_sha256`).
