# The rmoriebricklayer image: R, the analysis packages, and the package installed (rmbl on PATH).
# Pinned by digest; the tag is what Dependabot (docker, .github/dependabot.yml) tracks.
# Digest from tag 1.0.0 = sha-07ed9f6 (rmorie-bricklayer 07ed9f66, the 1.0.0 CRAN resubmission build), 2026-10-21.
# To bump by hand: skopeo inspect --format '{{.Digest}}' docker://ghcr.io/rootcoder007/rmorie-bricklayer:1.0.0
FROM ghcr.io/rootcoder007/rmorie-bricklayer:v1.0.3@sha256:85032c8931d6840a14d7924f73fc71421bf63409702bb2f6a2bde50b9a7a4ffe

COPY entrypoint.sh check.R /rmbl/
COPY spec /rmbl/spec
ENTRYPOINT ["/rmbl/entrypoint.sh"]
