# Lua

[`capsule.lua`](capsule.lua) writes a signed capsule.

No modules at all: SHA-256 (RFC 6234) and HMAC (RFC 2104) are written in plain Lua 5.4,
on its 64-bit integers and bitwise operators (about 40 lines), chosen over `luaossl` or a
`sha2` rock so that nothing has to be installed beside the interpreter. It needs Lua 5.3 or
later (5.1 and LuaJIT have no integer bitwise operators). Arrays are tables made with
`arr()`, everything else is an object whose keys `table.sort` orders, byte order in the C
locale a script starts in.

```sh
RMBL_KEY=... sh run.sh <capsule dir>     # lua capsule.lua <dir>
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
      - run: sh examples/lua/run.sh capsules/squares
        env:
          RMBL_KEY: ${{ secrets.CAPSULE_KEY }}
      - uses: rootcoder007/rmbl-action@v1
        with:
          path: capsules
          key: ${{ secrets.CAPSULE_KEY }}
          public-key: ${{ vars.CAPSULE_KEY_ID }}  # printed by the program
```

The test workflow's `example-native (lua)` job writes the vectors of
[`spec/vectors/`](../../spec/vectors) with this program and compares them byte for byte, then
runs the action on a fresh capsule (status ok, signature row passing) and again after
flipping one byte of `data.csv` (the step fails on `file:data.csv` and `data_sha256`).
