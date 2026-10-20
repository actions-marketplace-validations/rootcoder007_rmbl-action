# The rmoriebricklayer image: R, the analysis packages, and the package installed (rmbl on PATH).
# Pinned by digest; the tag is what Dependabot (docker, .github/dependabot.yml) tracks.
# Digest from tag 1.0.0 = sha-4d4229e (rmorie-bricklayer 4d4229e0, the 1.0.0 release build), 2026-10-20.
# To bump by hand: skopeo inspect --format '{{.Digest}}' docker://ghcr.io/rootcoder007/rmorie-bricklayer:1.0.0
FROM ghcr.io/rootcoder007/rmorie-bricklayer:1.0.0@sha256:4d598c8c4c7be4871c63dfc47c518433ee8f7419d2edb49e42766c310aae8e85

COPY entrypoint.sh check.R /rmbl/
COPY spec /rmbl/spec
ENTRYPOINT ["/rmbl/entrypoint.sh"]
