# The rmoriebricklayer image: R, the analysis packages, and the package installed (rmbl on PATH).
# Pinned by digest; the tag is what Dependabot (docker, .github/dependabot.yml) tracks.
# Digest from tag 1.1.1 (rmorie-bricklayer 1654a814, the 1.1.1 release as on CRAN), 2026-11-18.
# Dependabot opens the bump and dependabot-merge.yml merges and releases it;
# to bump by hand: skopeo inspect --format '{{.Digest}}' docker://ghcr.io/rootcoder007/rmorie-bricklayer:1.1.1
FROM ghcr.io/rootcoder007/rmorie-bricklayer:1.1.1@sha256:28249dc3306fbf0a3ec87e8648b926e5c654b007d806fe43c1895dd6a36e6543

COPY entrypoint.sh check.R /rmbl/
COPY spec /rmbl/spec
ENTRYPOINT ["/rmbl/entrypoint.sh"]
