# Security

## Reporting

Report a vulnerability privately with the "Report a vulnerability" button on this
repository's Security tab. Include the action version (tag or commit), the workflow step
that triggered it, and a reproducer. You will get an acknowledgement within 72 hours and a
fix or a documented decision within 30 days. A flaw in the checks themselves (digests,
signatures, drift statistics) belongs to
[rmoriebricklayer](https://github.com/rootcoder007/rmorie-bricklayer/security); report it
there, or here if unsure.

## Supported versions

The latest `v1.x.y` release, which the `v1` tag points to. Fixes are released as a new
patch version and `v1` is moved to it.

## What the action does with your secrets

See [Security in the README](../README.md#security): what `key` and `GITHUB_TOKEN` are used
for, which requests each mode makes, and what is uploaded.

## How the action itself is kept safe

- Every `uses:` in this repository's workflows is pinned to a full commit SHA, with the
  version in a comment; Dependabot proposes the updates.
- The base image is pinned by digest in the `Dockerfile`; Dependabot proposes a new
  digest when the tag moves.
- Workflows run with read-only tokens unless a job needs more, and say why.
- zizmor audits the workflows on every push; OpenSSF Scorecard runs weekly.
- `v1` is moved only by the release workflow, after the full test workflow passed on the
  same commit.
