# rmbl-action

A GitHub Action that checks the reproducible data capsules made with the R package
[rmoriebricklayer](https://github.com/rootcoder007/rmorie-bricklayer)
([www.rmorie.com](https://www.rmorie.com)). It finds every capsule under a directory,
checks it with the package's own functions, writes a Markdown report and a JSON file, adds
the report to the job summary, and fails the job according to `fail-on`.

A capsule is a directory holding `data_provenance.json` (the pinned record of a data file:
`resource$filename`, `resource$sha256`, optionally `resource$size_bytes`,
`resource$row_count_data_rows`, a `schema` block, and the source in `resource$direct_url`),
a signed `capsule_bundle.json` written by `cpsbndl()`, or both.

## Modes

| `mode` | What it does | Network |
|---|---|---|
| `verify` (default) | `vrfcps()` on each provenance: data present, SHA-256, size, row count, pinned schema, results manifest (`manifest.json`), pinned script digest, not synthetic. `cpsbndlvrf()` on each bundle: every file's digest, no unlisted files, the signature, and the signing key when `public-key` is given. | none |
| `drift` | `verify`, then downloads `resource$direct_url` with `fdl()` (falling back to the Wayback snapshot in `wayback$csv_snapshot`, or one looked up). When the digest differs from the pin, `cpsdrft()` compares the pinned CSV with the new one: Kolmogorov-Smirnov, chi-square homogeneity, population stability index and Jensen-Shannon divergence per column, plus added and removed columns. A byte change with no drifted column is reported but is not drift. | yes |
| `refresh` | `drift`, then for each changed source whose new data pass the pinned schema: writes the new data file and updates `resource$sha256`, `size_bytes`, `row_count_data_rows` and `retrieved_utc` in the provenance, in the workspace, so a later step can open a pull request. With `wayback: true` the source is captured with `wbsave()` and the snapshot recorded in `wayback$csv_snapshot`. A `capsule_bundle.json` is not re-signed (that needs your signing key): the report says so. | yes |
| `report` | `verify`, but the step never fails. | none |

## Usage

```yaml
- uses: actions/checkout@v4
- uses: rootcoder007/rmbl-action@v1
  with:
    path: capsules
```

### Pull request gate

```yaml
name: capsules
on:
  pull_request:
  push:
    branches: [main]
jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: rootcoder007/rmbl-action@v1
        with:
          path: capsules
          # public-key: ${{ vars.CAPSULE_PUBLIC_KEY }}  # pin the bundle signer
```

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
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/cache@v4
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
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
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
      - uses: peter-evans/create-pull-request@v7
        if: steps.rmbl.outputs.changed != ''
        with:
          branch: capsule-refresh
          title: "Refresh capsules: ${{ steps.rmbl.outputs.changed }}"
          body-path: ${{ runner.temp }}/rmbl-report.md
          commit-message: refresh capsules
```

The report and JSON paths are relative to the workspace; in the refresh workflow they are
written outside it so they do not end up in the pull request.

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `path` | `.` | Directory searched recursively for `data_provenance.json` and `capsule_bundle.json`. `.git` and `.rmbl-cache` are skipped. |
| `mode` | `verify` | `verify`, `drift`, `refresh` or `report` (see above). |
| `fail-on` | `error` | `error`, `drift` or `never` (see below). |
| `key` | | data.rmorie.com key, exported to the package as `MORIE_HOSTED_KEY`. Pass it from a secret. |
| `public-key` | | Public key (hex) every bundle must be signed with. Without it a bundle is only checked to be consistent with the key it carries. |
| `report` | `rmbl-report.md` | Markdown report path. |
| `json` | `rmbl-results.json` | JSON results path. |
| `manifests` | | Glob restricting the capsule files checked, matched against their path, e.g. `capsules/ontario/*`. `*` also matches `/`. |
| `wayback` | `false` | During `refresh`, capture each changed `https` source in the Wayback Machine. Needs `IA_S3_ACCESS_KEY` and `IA_S3_SECRET_KEY` in the step's `env`. A failed capture is a note in the report, not an error. |
| `cache` | `false` | Keep fetched sources and data.rmorie.com tables in `.rmbl-cache/` (save and restore it with `actions/cache`). A cached source is used only when the live fetch fails, and the report says so. |
| `allow-file` | `false` | Accept `file://` source URLs, for local mirrors and tests. |

## Outputs

| Output | Meaning |
|---|---|
| `status` | `ok`, `drift` or `error`: the worst result over all capsules. |
| `report` | Path of the Markdown report. |
| `json` | Path of the JSON results: per capsule the source, pinned and fetched digests, result, check counts, notes and the full per-column drift table. |
| `changed` | Comma-separated capsule directories whose source digest differs from the pin. |
| `verified` | Number of capsules without an error. |
| `failed` | Number of capsules with an error. |

## How it fails

Each capsule gets one result:

- `error`: a check failed (digest, size, rows, schema, results manifest, script, synthetic
  data, bundle file or signature), the source could not be fetched, or refreshed data broke
  the pinned schema.
- `drift`: the source changed and at least one column drifted, a column was added or
  removed, or the distributions could not be compared.
- `ok`: everything else.

| `fail-on` | Step fails when `status` is |
|---|---|
| `error` | `error` |
| `drift` | `error` or `drift` |
| `never` | never |

`mode: report` never fails. The step exits 1 when it fails, and 2 when an input is invalid
(an unknown mode, `fail-on` value or boolean, or a `path` that is not a directory). No
capsules under `path` is not a failure: the report says "No manifests found under `<path>`"
and `status` is `ok`.

## Versions

Pin a major version, `rootcoder007/rmbl-action@v1`. The `v1` tag is moved to each `v1.x.y`
release; pin a full tag such as `@v1.0.0`, or a commit SHA, to freeze it.

## How the image is built

`runs.using: docker` with this repository's `Dockerfile`: it starts from
`ghcr.io/rootcoder007/rmorie-bricklayer:latest` (R, the analysis packages and the package
source) and installs rmoriebricklayer from that source when the image does not already
have it installed, then adds `entrypoint.sh` and `check.R`. The checks are R calls to the
package's exported functions (`vrfcps()`, `cpsbndlvrf()`, `fdl()`, `cpsdrft()`,
`valsch()`, `wbsave()`); nothing else is installed.

## Security

- `key` is passed to the container only as an environment variable, masked in the log,
  and never written to a file. The package sends it only to the data service named in its signed services document (data.rmorie.com).
- `verify` and `report` make no network requests. `drift` and `refresh` download each
  capsule's `direct_url` (and its Wayback snapshot when the source is down).
- Nothing is uploaded anywhere, except that `wayback: true` asks the Internet Archive to
  capture the source URLs, using your archive.org keys.
- `file://` sources are refused unless `allow-file: true`.

## Licence

AGPL-3, as rmoriebricklayer.
