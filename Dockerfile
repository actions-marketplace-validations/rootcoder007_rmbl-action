# The rmoriebricklayer image: R, the analysis packages, and the package installed (rmbl on PATH).
FROM ghcr.io/rootcoder007/rmorie-bricklayer:latest

COPY entrypoint.sh check.R /rmbl/
COPY spec /rmbl/spec
ENTRYPOINT ["/rmbl/entrypoint.sh"]
