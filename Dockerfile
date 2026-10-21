# The rmoriebricklayer image: R, the analysis packages, and the package installed (rmbl on PATH).
# Pinned by digest; the tag is what Dependabot (docker, .github/dependabot.yml) tracks.
# Digest from tag 1.0.0 = sha-cefdb1a (rmorie-bricklayer cefdb1a1, the 1.0.0 CRAN resubmission build), 2026-10-21.
# To bump by hand: skopeo inspect --format '{{.Digest}}' docker://ghcr.io/rootcoder007/rmorie-bricklayer:1.0.0
FROM ghcr.io/rootcoder007/rmorie-bricklayer:1.0.0@sha256:65ba624795effaf4fc919043f4e105c2d88a63ef2fec3e1280d735428b15f92a

COPY entrypoint.sh check.R /rmbl/
COPY spec /rmbl/spec
ENTRYPOINT ["/rmbl/entrypoint.sh"]
