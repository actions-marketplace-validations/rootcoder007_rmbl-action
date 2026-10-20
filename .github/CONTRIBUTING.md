# Contributing

Issues and pull requests are welcome. A change that alters what is checked or how it is
reported should come with a step in `.github/workflows/test.yml` that shows it, including
the failing case.

## Running the action locally

The action is a Docker image, so it runs without GitHub:

```bash
docker build -t rmbl-local .
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/github/workspace" -w /github/workspace \
  -e GITHUB_WORKSPACE=/github/workspace -e RMBL_PATH=caps rmbl-local
```

Make a test capsule with `tests/make-capsule.R` (see the `modes` job). The workflows also
run under [act](https://github.com/nektos/act): `act -j modes`.

## Before you push

- `pipx run zizmor==1.31.1 .` reports no findings at `--min-severity low`.
- New `uses:` are pinned to a full commit SHA with a `# vX.Y.Z` comment.
- New workflow permissions are the least the job needs, with a comment saying why.

## Releases

Run the `release` workflow from main with the new version (`vX.Y.Z`). It runs every test
job on that commit, then creates the tag, moves `v1` and drafts the release; publishing
the draft lists it on the Marketplace.
