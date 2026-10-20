# Changelog

Releases follow semantic versioning; `v1` always points to the latest `v1.x.y`.

## Unreleased

- First release: modes `verify`, `drift`, `refresh` and `report`; JSON Schema validation of
  every capsule file (`spec/`); hmac and post-quantum bundle signatures; manifest
  comparison with the base branch; sticky pull-request comment; annotations; `fail-on`
  levels and PSI bands.
- Base image `ghcr.io/rootcoder007/rmorie-bricklayer:1.0.0` pinned by digest.
- Report tables name every status column and spell the status next to its symbol.
- The pull-request comment links to its run.
