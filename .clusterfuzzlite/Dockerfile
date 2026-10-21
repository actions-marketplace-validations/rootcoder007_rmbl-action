# ClusterFuzzLite build image. The action runs rmoriebricklayer; the parsers that read bytes
# from outside the job (bundle signatures in DER, source URLs, CSV numbers, fetched HTML) are
# the package's, so the targets are the package's libFuzzer harnesses, built at the commit the
# action's base image was made from (BL_REF; keep it in step with the Dockerfile digest).
FROM gcr.io/oss-fuzz-base/base-builder@sha256:1f9cf74bc3d7029b528494542f9d9851b256dceed38d3f420989434dc5ae0760
RUN apt-get update \
 && apt-get install -y --no-install-recommends r-base-dev libcurl4-openssl-dev pkg-config zip \
 && rm -rf /var/lib/apt/lists/*
ENV BL_REF=cefdb1a194f61f18b5161a72006a6e31a8f7c730
RUN git clone --quiet https://github.com/rootcoder007/rmorie-bricklayer "$SRC/rmorie-bricklayer" \
 && git -C "$SRC/rmorie-bricklayer" checkout --quiet "$BL_REF"
COPY . "$SRC/rmbl-action"
COPY .clusterfuzzlite/build.sh "$SRC/build.sh"
WORKDIR "$SRC/rmbl-action"
