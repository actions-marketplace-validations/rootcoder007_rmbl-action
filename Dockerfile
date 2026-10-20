# The rmoriebricklayer image: R, the analysis packages, and the package installed (rmbl on PATH).
# Pinned by digest; the tag is what Dependabot (docker, .github/dependabot.yml) tracks.
# Digest from tag 1.0.0 = sha-65de2c4 (rmorie-bricklayer 65de2c41), 2026-10-20.
# To bump by hand: skopeo inspect --format '{{.Digest}}' docker://ghcr.io/rootcoder007/rmorie-bricklayer:1.0.0
FROM ghcr.io/rootcoder007/rmorie-bricklayer:1.0.0@sha256:27b276bc4c9c3298cd16bb438e798773807e354c4b6815bfa1007a4459946431

COPY entrypoint.sh check.R /rmbl/
COPY spec /rmbl/spec
ENTRYPOINT ["/rmbl/entrypoint.sh"]
