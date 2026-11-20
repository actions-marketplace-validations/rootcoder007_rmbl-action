# Changelog

Releases follow semantic versioning; `v1` always points to the latest `v1.x.y`.

## 1.1.1 (2026-11-12)

- Base image bumped to the rmoriebricklayer 1.1.1 release build (58249e4c). Four functions have new names there, and a capsule's schema names `anytab()` where it named `anltab()`; `rmbl migrate` rewrites a script's calls of the old names. The curated tables at data.rmorie.com need no sign-in, so a workflow that pulls one needs no key. The image is built on a Wolfi base whose glibc carries the fix for CVE-2026-84243.

## 1.1.0 (2026-11-01)

- Base image bumped to the rmoriebricklayer 1.1.0 release build (ac3f047c). It carries the 1.0.5 fixes (the JSON reader works on R 4.1 to 4.4 again, records holding arrays and deep nesting; no connection is left open when a file cannot be read; `arccap()` sends files larger than one upload in checked parts) and the 1.1.0 one: a bundle check started by `unshare` from util-linux before 2.38 (Ubuntu 22.04) no longer waits out its whole time limit and reports a timeout.

## 1.0.4 (2026-10-31)

- Base image bumped to the rmoriebricklayer 1.0.3 release build (e026b54e): a Wolfi base with no known CVEs, SLH-DSA-SHA2-128s as the default signer, `cpsxvrf()` cross-checks with OpenSSL 3.5, and `tsstmp()` public timestamps.
- Base image bumped to the rmoriebricklayer 1.0.4 release build (b15a1d25; its CRAN copy has one help page per function again). `verify` and `report` now refuse a capsule whose source is a `file://` URL unless `allow-file: true`, as `drift` and `refresh` already did; set `allow-file: true` for capsules made from a file in the repository. `public-key` must be the expected key or key id in hexadecimal, 16 digits at least; a shorter value stops the step before any check.
- New base images now arrive by themselves: Dependabot opens the bump, `dependabot-merge.yml` merges it once every check passes and cuts the next patch release, which moves `v1`.

## 1.0.1 (2026-10-22)

- New input `archive`: when a source cannot be fetched, `drift` and `refresh` fall back to the copy kept on archive.rmorie.com with the pinned SHA-256 (public copies need no key), and with `wayback: true` a changed source the Wayback Machine refuses is saved there instead. Off by default.
- Saving to the archive needs no secret: in a job allowed `id-token: write` the package uses GitHub's OIDC token, and the repository is the saver. New output `keyless` says whether the job had that permission.
- Base image bumped to the rmoriebricklayer 1.0.2 release build (1052d5d7), which brings `cpschk(archive =)` and keyless saving.
- Base image bumped earlier to the rmoriebricklayer 1.0.0 CRAN resubmission build 07ed9f66 (package links to rmorie.com written as plain text; CRAN runs a fast core of the tests and skips re-computing the vignettes). An error raised during a footprint-measured check is now named after the check (`cpschk:`), not `co2fp:`. `spec/capsule.schema.json` now matches the package's schema (it gains `kind`, which marks a proof ledger).
- Base image bumped earlier to the rmoriebricklayer 1.0.0 release build ae81bf7a, the commit on CRAN and in the rOpenSci submission (its dashboard report tests now pass on macOS, where the report embeds PNG figures instead of SVG).

## 1.0.0 (2026-10-20)

- Base image bumped to the rmoriebricklayer 1.0.0 release build (4d4229e0): XMSS from `rmbl sign`, the 0.5.x name aliases, drift report and dashboard.
- ClusterFuzzLite runs the package's libFuzzer targets on pull requests and weekly.
- The key is read only from the action's `key` input (`INPUT_KEY`): a job-level `RMBL_KEY` no
  longer signs in `mode: sign` when `key` is empty. Mode `sign` signs through the package's
  `cpsseal()`.
- `check.R` is a thin shell over rmoriebricklayer 1.0.0: the checks, report, JSON,
  annotations, comment body and outputs come from `cpschk()`, `ghann()`, `ghcmt()` and
  `ghout()`. Inputs and outputs are unchanged. The JSON adds every check row (`checks`),
  annotations carry the line of a schema problem, and failed rows carry `explerr()` notes.
  Base image bumped to the rmorie-bricklayer 1.0.0 build with those functions.
- `mode: sign` (inputs `scheme`, `overwrite`): pins each `data_provenance.json` on its first
  run and writes an hmac `capsule_bundle.json` with `cpsbndl()` under `key`, then verifies,
  so a program in any language only writes the data and a plain provenance.
- `docs/bundle-format.md`: the capsule, the canonical JSON form, the bundle and the hmac
  attestation byte by byte, with test vectors in `spec/vectors/` that CI re-derives with
  the package.
- Native signing examples for C, C++, Go, Rust, Zig, Java, Node, TypeScript, Bun, Lua and
  SQL (sqlite3 with sh and OpenSSL), each writing the vectors byte for byte and verified,
  then tampered with, in CI; universal examples in POSIX sh, awk and Wolfram Language.
- First release: modes `verify`, `drift`, `refresh` and `report`; JSON Schema validation of
  every capsule file (`spec/`); hmac and post-quantum bundle signatures; manifest
  comparison with the base branch; sticky pull-request comment; annotations; `fail-on`
  levels and PSI bands.
- Base image `ghcr.io/rootcoder007/rmorie-bricklayer:1.0.0` pinned by digest.
- Report tables name every status column and spell the status next to its symbol.
- The pull-request comment links to its run.
