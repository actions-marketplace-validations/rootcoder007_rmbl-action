# Zig

[`capsule.zig`](capsule.zig) writes a signed capsule.

`std.crypto.hash.sha2.Sha256` and `std.crypto.auth.hmac.sha2.HmacSha256`, written for Zig
0.14 (the `std.ArrayList` and writer APIs changed in 0.15). JSON is written by hand: a
`str()` that applies the escapes, and the fixed keys emitted in sorted order.

```sh
RMBL_KEY=... sh run.sh <capsule dir>     # zig build-exe, then run
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
      - run: sh examples/zig/run.sh capsules/squares
        env:
          RMBL_KEY: ${{ secrets.CAPSULE_KEY }}
      - uses: rootcoder007/rmbl-action@v1
        with:
          path: capsules
          key: ${{ secrets.CAPSULE_KEY }}
          public-key: ${{ vars.CAPSULE_KEY_ID }}  # printed by the program
```

The test workflow's `example-native (zig)` job writes the vectors of
[`spec/vectors/`](../../spec/vectors) with this program and compares them byte for byte, then
runs the action on a fresh capsule (status ok, signature row passing) and again after
flipping one byte of `data.csv` (the step fails on `file:data.csv` and `data_sha256`).
