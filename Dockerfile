# The rmoriebricklayer image: R, the analysis packages, and the package source in /bricklayer.
FROM ghcr.io/rootcoder007/rmorie-bricklayer:latest

# Install the package from that source when the image does not already have it installed.
RUN Rscript -e 'quit(status = !requireNamespace("rmoriebricklayer", quietly = TRUE))' \
 || (apt-get update && apt-get install -y --no-install-recommends zlib1g-dev \
     && rm -rf /var/lib/apt/lists/* \
     && MAKEFLAGS="-j$(nproc)" R CMD INSTALL --no-docs --no-html /bricklayer)

COPY entrypoint.sh check.R /rmbl/
COPY spec /rmbl/spec
ENTRYPOINT ["/rmbl/entrypoint.sh"]
