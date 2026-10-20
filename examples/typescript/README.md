# TypeScript

[`capsule.ts`](capsule.ts) writes a signed capsule.

The Node recipe with types: `node:crypto`, `node:fs`, no packages. Node 22.18 and later run
the file directly (type stripping); in a `tsc` project compile it as usual. Keys sorted by
UTF-8 bytes, strings through `JSON.stringify` with `</` replaced.

```sh
RMBL_KEY=... sh run.sh <capsule dir>     # node capsule.ts <dir>
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
      - run: sh examples/typescript/run.sh capsules/squares
        env:
          RMBL_KEY: ${{ secrets.CAPSULE_KEY }}
      - uses: rootcoder007/rmbl-action@v1
        with:
          path: capsules
          key: ${{ secrets.CAPSULE_KEY }}
          public-key: ${{ vars.CAPSULE_KEY_ID }}  # printed by the program
```

The test workflow's `example-native (typescript)` job writes the vectors of
[`spec/vectors/`](../../spec/vectors) with this program and compares them byte for byte, then
runs the action on a fresh capsule (status ok, signature row passing) and again after
flipping one byte of `data.csv` (the step fails on `file:data.csv` and `data_sha256`).
