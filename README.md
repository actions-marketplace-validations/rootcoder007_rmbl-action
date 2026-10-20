# rmbl-action

[![test](https://github.com/rootcoder007/rmbl-action/actions/workflows/test.yml/badge.svg)](https://github.com/rootcoder007/rmbl-action/actions/workflows/test.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/rootcoder007/rmbl-action/badge)](https://scorecard.dev/viewer/?uri=github.com/rootcoder007/rmbl-action)

A GitHub Action that checks reproducible data capsules: a data file pinned by a JSON
provenance record, optionally with a results manifest and a signed bundle. It finds every
capsule under a directory, checks it with the R package
[rmoriebricklayer](https://github.com/rootcoder007/rmorie-bricklayer)
([www.rmorie.com/provenance](https://www.rmorie.com/provenance)) inside a Docker image, writes a Markdown report
and a JSON file, adds the report to the job summary, annotates the failing files, and fails
the job according to `fail-on`.

The repository being checked can be in any language: a capsule is JSON plus data files, and
R runs only inside the action's container.

```yaml
permissions:
  contents: read
jobs:
  capsules:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - uses: rootcoder007/rmbl-action@v1
        with:
          path: capsules
```

A sample of the report it writes to the job summary is in
[`examples/rmbl-report.md`](examples/rmbl-report.md), with the matching JSON in
[`examples/rmbl-results.json`](examples/rmbl-results.json).

## Any language

The action is language-independent: it reads files, not code. A capsule is a data file, a
JSON provenance record and optionally a JSON bundle; what is checked is their bytes (SHA-256
digests) and their JSON values, and the signature is HMAC-SHA-256, which every platform has.
R runs only inside the action's container. So a project in any language takes one of two
paths, both tested in CI:

1. **Any language: write two files, let the action sign.** The program writes the data
   file and a plain `data_provenance.json` naming it; `mode: sign` pins the provenance and
   writes the signed `capsule_bundle.json` in CI with your key. Nothing but file output is
   needed in the producing language, which is what makes "every language" true.
2. **Native signing.** The program writes the pinned provenance and the signed bundle
   itself, following [`docs/bundle-format.md`](docs/bundle-format.md): the files, the
   canonical JSON form and the hmac attestation, byte by byte, with test vectors in
   [`spec/vectors/`](spec/vectors). Every native example below writes those vectors byte
   for byte in CI.

### Any language: write two files, let the action sign

```yaml
permissions:
  contents: read
jobs:
  capsules:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - run: ./produce capsules/squares  # your program, in whatever language: data.csv + data_provenance.json
      - uses: rootcoder007/rmbl-action@v1
        with:
          path: capsules
          mode: sign
          key: ${{ secrets.CAPSULE_KEY }}
      - uses: rootcoder007/rmbl-action@v1
        with:
          path: capsules
          key: ${{ secrets.CAPSULE_KEY }}
          public-key: ${{ vars.CAPSULE_KEY_ID }}  # the key id mode sign prints
```

The plain provenance needs only `{"resource": {"filename": "data.csv"}}`. `mode: sign` fills
`resource.sha256`, `size_bytes` and `retrieved_utc` when `resource.sha256` is absent, signs
every file of each capsule directory, fails when a bundle is already there unless
`overwrite: true`, and then verifies. Commit the pinned files, or upload them as an
artifact. See [`examples/any`](examples/any) (POSIX sh and awk, the `example-sign` job) and
[`examples/wolfram`](examples/wolfram).

### Per language

| Language | Example and recipe | Libraries | Tested in CI |
|---|---|---|---|
| any | [`examples/any`](examples/any): write two files, `mode: sign` | none | `example-sign` (POSIX sh, awk) |
| Wolfram Language | [`examples/wolfram`](examples/wolfram): `Export` the two files, `mode: sign` | none | no: the Wolfram Engine needs an activated licence the runner does not have |
| C | [`examples/c`](examples/c) | OpenSSL EVP, JSON by hand | `example-native (c)`, `example-c` |
| C++ | [`examples/cpp`](examples/cpp) | OpenSSL EVP, JSON by hand | `example-native (cpp)` |
| Go | [`examples/go`](examples/go) | standard library; own string writer (`encoding/json` escapes U+2028 and `<>&`) | `example-native (go)` |
| Rust | [`examples/rust`](examples/rust) | `sha2`, `hmac`, `serde_json` (`Cargo.lock`) | `example-native (rust)` |
| Zig | [`examples/zig`](examples/zig) | `std.crypto` (Zig 0.14), JSON by hand | `example-native (zig)` |
| Java | [`examples/java`](examples/java) | `java.security`, `javax.crypto`, a small canonical writer | `example-native (java)` |
| Node | [`examples/node`](examples/node) | `node:crypto`, sorted-key `JSON.stringify` | `example-native (node)` |
| TypeScript | [`examples/typescript`](examples/typescript) | `node:crypto`, run by Node's type stripping | `example-native (typescript)` |
| Bun | [`examples/bun`](examples/bun) | `node:crypto` as Bun implements it | `example-native (bun)` |
| Lua | [`examples/lua`](examples/lua) | none: SHA-256 and HMAC in plain Lua 5.4 | `example-native (lua)` |
| SQL (SQLite, DuckDB) | [`examples/sql`](examples/sql): the query writes the CSV, `sh` + `openssl dgst -hmac` signs | `sqlite3`, OpenSSL CLI | `example-native (sql)` |
| Python | [`examples/python/make_capsule.py`](examples/python/make_capsule.py) (provenance, standard library); [morie](https://github.com/rootcoder007/morie) signs | standard library; morie | `example-python`, `example-python-signed` |
| R | [`examples/r/make_capsule.R`](examples/r/make_capsule.R) (provenance); `cpsbndl()` signs | rmoriebricklayer | `example-r` |

Each native job writes the vectors of `spec/vectors/` and compares them byte for byte, runs
the action on a fresh capsule with `key` and `public-key` (status ok, the
`attestation:signature` row passing), then flips one byte of the data and checks that the
step fails on the `file:data.csv` and `data_sha256` rows. The `vectors` job re-derives
`spec/vectors/` with the package and diffs it.

### Provenance only

The R, Python and C `make_capsule` examples write only the provenance, which `verify` checks
without a bundle (verify locally with the `docker run` command under
[Local use](#local-use-without-github)).

Each example takes `<csv path> <source url>` and writes `data_provenance.json` next to the
CSV with `name`, `source.url`, `source.retrieved` and `resource.filename`, `sha256`,
`size_bytes`, `row_count_data_rows`. The test workflow runs all three on the same CSV,
checks each output with the action, and checks that the three files are identical apart
from the retrieval date.

The smallest capsule needs only `resource.filename` and `resource.sha256`. In Python, run
next to `data.csv`:

```python
import csv, hashlib, json, pathlib

f = pathlib.Path("data.csv")
with f.open(newline="") as fh:
    rows = sum(1 for _ in csv.reader(fh)) - 1  # data rows, header excluded
prov = {"resource": {"filename": f.name,
                     "sha256": hashlib.sha256(f.read_bytes()).hexdigest(),
                     "size_bytes": f.stat().st_size,
                     "row_count_data_rows": rows}}
pathlib.Path("data_provenance.json").write_text(json.dumps(prov, indent=2) + "\n")
```

In a shell, with `sha256sum` and `jq`:

```sh
f=data.csv
jq -n --arg f "$f" --arg sha "$(sha256sum "$f" | cut -d ' ' -f 1)" \
  --argjson size "$(wc -c < "$f")" --argjson rows "$(( $(wc -l < "$f") - 1 ))" \
  '{resource: {filename: $f, sha256: $sha, size_bytes: $size, row_count_data_rows: $rows}}' \
  > data_provenance.json
```

The shell row count assumes no quoted field holds a newline. The test workflow runs both
snippets as written here.

### Python authors and signs with morie

[morie](https://github.com/rootcoder007/morie), the Python sibling of the R packages, writes
capsules and signs them with `hmac`: HMAC-SHA-256 under a shared secret, in the bundle format
`cpsbndl()` writes. It is not on PyPI at this version; install it from GitHub:

```bash
pip install "git+https://github.com/rootcoder007/morie@main"
morie capsule init data/sample.csv --url https://example.org/sample.csv  # data/data_provenance.json
export MORIE_CAPSULE_KEY=...      # the shared secret; never on the command line
morie capsule sign data           # data/capsule_bundle.json, scheme hmac
morie capsule verify data         # the same checks, in Python
```

`morie capsule sign` prints the bundle's key id, the attestation's `public` field:
HMAC-SHA-256 of the string `public` under the secret. It names the key without revealing it.
In CI, keep the secret in a repository secret and give it to the action as `key`; pin the key
id with `public-key`:

```yaml
      - uses: rootcoder007/rmbl-action@v1
        with:
          path: data
          key: ${{ secrets.MORIE_CAPSULE_KEY }}
          public-key: ${{ vars.CAPSULE_KEY_ID }}
```

The action passes `key` to `cpsbndlvrf(key = )` (and so `cpschkatst(key = )`) only for a bundle
whose attestation scheme is `hmac`; a wrong secret fails the `attestation:signature` row and
the step. The test workflow's `example-python-signed` job runs these commands and both cases.

What still needs R today: signing with the post-quantum schemes (ML-DSA, SLH-DSA, XMSS:
`cpssign()`, `cpsbndl()`), and the drift statistics the action reports (`cpsdrft()`,
`benfordtst()`; `morie capsule drift` computes its own). Verifying all of them needs no R on
your side: the action brings it.

## The files

A capsule is a directory holding `data_provenance.json`, a signed `capsule_bundle.json`
written by `cpsbndl()`, or both, and optionally `manifest.json` or `results/manifest.json`.
Their formats are written down as JSON Schema 2020-12 in [`spec/`](spec), each property
naming the package function that reads or writes it:

- [`spec/capsule.schema.json`](spec/capsule.schema.json): `data_provenance.json` as
  `vrfcps()` reads it.
- [`spec/manifest.schema.json`](spec/manifest.schema.json): the manifest `mkmnf()`,
  `recrd()` and `wrmnfjs()` write.
- [`spec/bundle.schema.json`](spec/bundle.schema.json): `capsule_bundle.json` as `cpsbndl()`
  writes it.

Every file is validated against its schema before the package's checks run, and each
validation is a check row in the report (`schema: data_provenance.json`).

## Modes

| `mode` | What it does | Network |
|---|---|---|
| `verify` (default) | `vrfcps()` on each provenance: data present, SHA-256, size, row count, pinned schema (`valsch()`), results manifest, pinned script digest, not synthetic. `cpsbndlvrf()` on each bundle: every file's digest, no unlisted files, the signature (an `hmac` one with the secret in `key`), and the signing key when `public-key` is given. | none |
| `drift` | `verify`, then downloads `resource.direct_url` (else `source.url`) with `fdl()`, falling back to the Wayback snapshot in `wayback.csv_snapshot` or one looked up. When the digest differs from the pin, `cpsdrft()` compares the pinned CSV with the new one per column (Kolmogorov-Smirnov or chi-square, population stability index, Jensen-Shannon divergence, added and removed columns), and `benfordtst()` screens the first digits of numeric columns. | yes |
| `refresh` | `drift`, then for each changed source whose new data pass the pinned schema: writes the new data and updates `resource.sha256`, `size_bytes`, `row_count_data_rows` and `retrieved_utc` in the workspace, so a later step can open a pull request. With `wayback: true` the source is captured with `wbsave()` and `wayback.csv_snapshot` updated. A bundle is not re-signed (that needs your key); the report says so. | yes |
| `report` | `verify`, but the step never fails. | none |
| `sign` | For each directory holding `data_provenance.json`: pins it on its first run (`resource.sha256`, `size_bytes`, `retrieved_utc`, `source.sha256`; `row_count_data_rows` when recorded), writes `capsule_bundle.json` with `cpsbndl()` under `key` (scheme `hmac`, over every file of the directory and `manifest.json`'s digest, or the empty manifest's), then `verify`. Fails when a bundle exists unless `overwrite: true`, or without `key`. | none |

In every mode, with `base-ref` set (the default on pull requests) each manifest is compared
with the base branch's copy, and with `snapshot: true` the latest Internet Archive snapshot
of each `http(s)` source is looked up with `wbsnpurl()`.

## Workflows

### Verify on every push

```yaml
name: capsules
on: push
permissions:
  contents: read
jobs:
  rmbl-action:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - uses: rootcoder007/rmbl-action@v1
```

### Pull request gate with a sticky comment and the manifest diff

```yaml
name: capsules
on:
  pull_request:
  push:
    branches: [main]
permissions:
  contents: read
  pull-requests: write
jobs:
  verify:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0  # the base branch's manifests, for the comparison
          persist-credentials: false
      - uses: rootcoder007/rmbl-action@v1
        id: rmbl
        with:
          path: capsules
          comment: ${{ github.event_name == 'pull_request' }}
          # public-key: ${{ vars.CAPSULE_PUBLIC_KEY }}  # pin the bundle signer
        env:
          GITHUB_TOKEN: ${{ github.token }}
      - uses: actions/upload-artifact@v7
        if: ${{ !cancelled() }}  # keep the results of a failing check too
        with:
          name: rmbl-results
          path: |
            ${{ steps.rmbl.outputs.json }}
            ${{ steps.rmbl.outputs.report }}
```

The comment is edited in place on every run (it carries the hidden marker
`<!-- rmbl-action -->`). On a pull request from a fork the token is read-only: the comment
is skipped with a warning and the check still runs.

### Several capsule trees (monorepo)

One job per tree, each with its own summary and result:

```yaml
jobs:
  capsules:
    runs-on: ubuntu-24.04
    strategy:
      fail-fast: false
      matrix:
        tree: [capsules/ontario, capsules/quebec]
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - uses: rootcoder007/rmbl-action@v1
        with:
          path: ${{ matrix.tree }}
```

Or one job over all of them, restricted with `manifests` (for example `capsules/*`).

### Nightly drift check that opens an issue

```yaml
name: capsule drift
on:
  schedule:
    - cron: "17 4 * * *"
  workflow_dispatch:
permissions:
  contents: read
  issues: write
jobs:
  drift:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - uses: actions/cache@v6
        with:
          path: .rmbl-cache
          key: rmbl-${{ github.run_id }}
          restore-keys: rmbl-
      - uses: rootcoder007/rmbl-action@v1
        id: rmbl
        with:
          path: capsules
          mode: drift
          fail-on: never
          cache: true
          snapshot: true
          key: ${{ secrets.MORIE_HOSTED_KEY }}
      - name: Open an issue
        if: steps.rmbl.outputs.status != 'ok'
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh issue create --title "Capsule sources: ${{ steps.rmbl.outputs.status }}" \
            --body-file "${{ steps.rmbl.outputs.report }}"
```

### Weekly refresh that opens a pull request

```yaml
name: capsule refresh
on:
  schedule:
    - cron: "41 5 * * 1"
  workflow_dispatch:
permissions:
  contents: write
  pull-requests: write
jobs:
  refresh:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
      - uses: rootcoder007/rmbl-action@v1
        id: rmbl
        with:
          path: capsules
          mode: refresh
          fail-on: never
          wayback: true
          report: ${{ runner.temp }}/rmbl-report.md
          json: ${{ runner.temp }}/rmbl-results.json
        env:
          IA_S3_ACCESS_KEY: ${{ secrets.IA_S3_ACCESS_KEY }}
          IA_S3_SECRET_KEY: ${{ secrets.IA_S3_SECRET_KEY }}
      - uses: peter-evans/create-pull-request@v8
        if: steps.rmbl.outputs.changed != ''
        with:
          branch: capsule-refresh
          title: "Refresh capsules: ${{ steps.rmbl.outputs.changed }}"
          body-path: ${{ runner.temp }}/rmbl-report.md
          commit-message: refresh capsules
```

The report and JSON paths are relative to the workspace; in the refresh workflow they are
written outside it so they do not end up in the pull request.

## What the summary shows

The same Markdown is written to the `report` file, added to the job summary, and posted as
the comment:

1. A heading naming the mode and the rmoriebricklayer version in the image.
2. A status line: ✔ ok, ⚠ warn or drift, ✖ error, with the number of capsules in each.
3. One table over all capsules: directory, source host, pinned SHA-256 (first 12 hex
   digits), data size, row count, publication bounds (the provenance's
   `table.rounding` and `table.suppression_limit`, when recorded) and result.
4. With a base ref: per manifest, each recorded result's base and new value, the change,
   and whether it is within the base's tolerance (`mnfrcmp()` with the base copy as the
   record); results added or removed are listed.
5. One collapsible block per capsule, closed by default: the full source URL, the full
   pinned and fetched digests, the publication bounds, and every check row (✔/✖, check,
   detail) from the schema validation, `vrfcps()` and `cpsbndlvrf()`. A changed source adds
   the drift verdict in one line and a per-column table: type, Kolmogorov-Smirnov D or
   chi-square statistic, p-value, population stability index with its band, Jensen-Shannon
   divergence, and the Benford p-value of the pinned and the new data. Notes close the
   block: why a fetch failed, with `explerr()`'s account of where the message is raised;
   the snapshot found; what refresh wrote.
6. A footer: the energy and CO2e of the checks themselves from `co2fp()` (measured with
   RAPL where the counters are readable, else modelled with Green Algorithms), then mode,
   `fail-on`, package and R versions.

Every failed check is also a workflow annotation: `::error file=<capsule file>` (with the
line of a schema problem), and a `::warning` for each drift or warn row, so they show in the
run header and the Files tab. The JSON also lists every check row under `checks`.

When no capsule is found the report says "No manifests found under `<path>`".

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `path` | `.` | Directory searched recursively for `data_provenance.json` and `capsule_bundle.json`. `.git` and `.rmbl-cache` are skipped. |
| `mode` | `verify` | `verify`, `drift`, `refresh`, `report` or `sign`. |
| `fail-on` | `error` | `error`, `drift`, `warn` or `never` (see below). |
| `psi-warn` | `0.1` | PSI above which a changed column is a warning. |
| `psi-fail` | `0.25` | PSI above which a column the package flags is drift; passed to `cpsdrft()` as `psithr`. The defaults are the bands `drftpsi()` documents: below 0.1 stable, 0.1 to 0.25 worth a look, above 0.25 material. |
| `base-ref` | the pull request's base | Branch or ref to compare manifests with. Needs the ref in the checkout (`fetch-depth: 0`). Empty outside pull requests. |
| `comment` | `false` | `true`: create or update one comment on the pull request (needs `GITHUB_TOKEN` in the step env and `pull-requests: write`). `dry-run`: write the comment to `rmbl-comment.md` instead. |
| `snapshot` | `false` | Look up each `http(s)` source's latest Internet Archive snapshot (`wbsnpurl()`, read-only). Offline or unarchived: a note, never a failure. |
| `key` | | A secret, masked in the log; pass it from a repository secret. The data.rmorie.com key, exported to the package as `MORIE_HOSTED_KEY`; or the shared secret an `hmac` bundle is verified with (`cpsbndlvrf(key = )`) and, in `mode: sign`, signed with (`cpsbndl()`). When any bundle is `hmac`-signed it is not exported to the data service. |
| `public-key` | | Public key (hex) every bundle must be signed with; for an `hmac` bundle its key id. Without it a bundle is only checked to be consistent with the key it carries. |
| `scheme` | `hmac` | Signature scheme of `mode: sign`; `hmac` is the one supported (the post-quantum schemes need a key file, so sign those with `cpsbndl()` in R). |
| `overwrite` | `false` | `true`: `mode: sign` replaces an existing `capsule_bundle.json`. |
| `report` | `rmbl-report.md` | Markdown report path. |
| `json` | `rmbl-results.json` | JSON results path. |
| `manifests` | | Glob restricting the capsule files checked, matched against their path, e.g. `capsules/ontario/*`. `*` also matches `/`. |
| `wayback` | `false` | During `refresh`, capture each changed `https` source in the Wayback Machine. Needs `IA_S3_ACCESS_KEY` and `IA_S3_SECRET_KEY` in the step env. A failed capture is a note, not an error. |
| `cache` | `false` | Keep fetched sources and data.rmorie.com tables in `.rmbl-cache/` (save and restore it with `actions/cache`). A cached source is used only when the live fetch fails, and the report says so. |
| `allow-file` | `false` | Accept `file://` source URLs, for local mirrors and tests. |

On GitHub the key comes only from the `key` input: a variable named `RMBL_KEY` in the job's
or workflow's `env` never reaches the checks, so an empty `key` cannot sign with it. Run by
hand with `docker run`, `-e RMBL_KEY=...` is the key.

## Outputs

| Output | Meaning |
|---|---|
| `status` | `ok`, `warn`, `drift` or `error`: the worst result over all capsules. |
| `report` | Path of the Markdown report. |
| `json` | Path of the JSON results: per capsule the source, digests, result, check counts, notes, the per-column drift table, and the manifest comparison. |
| `changed` | Comma-separated capsule directories whose source digest differs from the pin. |
| `verified` | Number of capsules without an error. |
| `failed` | Number of capsules with an error. |
| `manifest-changed` | `true` when a manifest differs from the base ref's copy. |
| `comment` | `off`, `dry-run`, `skipped`, `created`, `updated` or `failed`. |

## How it fails

Each capsule gets one result:

- `error`: a check failed (schema, digest, size, rows, data schema, results manifest,
  script, synthetic data, bundle file or signature), the source could not be fetched, or
  refreshed data broke the pinned schema.
- `drift`: the source changed and a column the package flags has a PSI above `psi-fail`, or
  a column was added or removed.
- `warn`: the source changed and a column is flagged below `psi-fail` or has a PSI above
  `psi-warn`, or the distributions could not be compared. Bytes that changed with no
  column past a band are reported as `ok`.
- `ok`: everything else.

| `fail-on` | Step fails when `status` is |
|---|---|
| `error` | `error` |
| `drift` | `error` or `drift` |
| `warn` | `error`, `drift` or `warn` |
| `never` | never |

`mode: report` never fails. The step exits 1 when it fails, and 2 when an input is invalid.
No capsules under `path` is not a failure: `status` is `ok`. A changed manifest is reported,
not failed; gate on the `manifest-changed` output if you want that.

To see a failure without failing the job, set `fail-on: never` and act on `status`, or keep
the failure and add `continue-on-error: true` to the step: later steps then read
`steps.<id>.outcome` (`failure`) and the outputs, as the test workflow does.

## Permissions

| Feature | Token permissions |
|---|---|
| `verify`, `drift`, `report`, `sign`, the job summary, annotations | `contents: read` (`sign` writes into the workspace only) |
| `comment: true` | `pull-requests: write`, and `GITHUB_TOKEN` in the step env |
| `refresh` with a pull request (peter-evans/create-pull-request) | `contents: write`, `pull-requests: write` |
| Manifest comparison | none beyond `contents: read`; the base ref must be fetched (`fetch-depth: 0`) |

## Local use without GitHub

The same checks run from any stack, on a laptop or in another CI (GitLab, Jenkins), with
the action's own image:

```bash
docker build -t rmbl https://github.com/rootcoder007/rmbl-action.git#v1
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/github/workspace" -w /github/workspace \
  -e GITHUB_WORKSPACE=/github/workspace -e RMBL_PATH=capsules rmbl
```

This is the action's `verify` mode: the exit status follows `fail-on` (`-e RMBL_FAIL_ON=...`),
and the report and JSON land in `rmbl-report.md` and `rmbl-results.json`. Every input is an
`RMBL_` variable (`RMBL_MODE`, `RMBL_PUBLIC_KEY`, `RMBL_KEY`, `RMBL_ALLOW_FILE`, ...). The base
image `ghcr.io/rootcoder007/rmorie-bricklayer` has the package installed and `rmbl` on its
path; its `rmbl verify|drift|report <dir> [--json] [--fail-on ...]` runs the same checks
with the same report: `--psi-warn`, `--psi-fail`, `--base MANIFEST|DIR`, `--cache DIR`,
`--allow-file`, `--snapshot`, `--manifests GLOB` and `--no-footprint` are the inputs of this
action. From R, `cpschk()` returns the checks, `format()` the report or the JSON, and
`ghann()`, `ghcmt()` and `ghout()` the annotations, the comment body and the outputs this
action prints; `check.R` only reads the inputs, signs in mode `sign`, resolves the base ref
with git and posts the comment.

## Versions

`rootcoder007/rmbl-action@v1` follows the latest `v1.x.y` release; the `v1` tag is moved
only by the release workflow, after every test job passed on that commit. To freeze the
action, pin the full commit SHA of a release with its version in a comment, which
Dependabot (`package-ecosystem: github-actions`) keeps current:

```yaml
      - uses: rootcoder007/rmbl-action@<full commit SHA> # v1.0.0
```

Changes are listed in [`CHANGELOG.md`](CHANGELOG.md) and the release notes.

## How the image is built

`runs.using: docker` with this repository's `Dockerfile`: it starts from
`ghcr.io/rootcoder007/rmorie-bricklayer` (R, the analysis packages and rmoriebricklayer
installed) pinned by digest, and adds `entrypoint.sh`, `check.R` and `spec/`. The checks are
calls to the package's exported functions; nothing else is installed. A given action commit
therefore always runs the same package build. The `Dockerfile` records the tag the digest
came from; when the package's image is rebuilt, Dependabot (`package-ecosystem: docker`)
opens a pull request with the new digest, the test workflow runs on it, and a release moves
`v1` to it.

## Security

Report a vulnerability privately: [`.github/SECURITY.md`](.github/SECURITY.md).

- `key` is passed to the container only as an environment variable, masked in the log,
  and never written to a file. The package sends it only to the data service named in its
  signed services document (data.rmorie.com), and not at all when a bundle is `hmac`-signed:
  then it is the bundle's shared secret and is used only to verify the signature. Keep an
  hmac secret in a repository secret; anyone who has it can sign bundles that verify.
- `GITHUB_TOKEN`, when given for `comment`, is used only for the pull request's comments
  API, from a header file readable by the container's user and deleted after use.
- `verify` and `report` make no network requests except `snapshot: true` (archive.org's
  availability API) and `comment: true` (the GitHub API). `drift` and `refresh` download
  each capsule's source (and its Wayback snapshot when the source is down).
- Nothing is uploaded anywhere, except the comment and, with `wayback: true`, the request to
  the Internet Archive to capture the source URLs with your archive.org keys.
- `file://` sources are refused unless `allow-file: true`; plain `http://` and private
  addresses are refused by the package.

## Licence

AGPL-3, as rmoriebricklayer.
