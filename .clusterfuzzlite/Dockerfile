# ClusterFuzzLite build image. The action runs rmoriebricklayer; the parsers that read bytes
# from outside the job (bundle signatures in DER, source URLs, CSV numbers, fetched HTML) are
# the package's, so the targets are the package's libFuzzer harnesses, built at the commit the
# action's base image was made from (BL_REF; keep it in step with the Dockerfile digest).
FROM gcr.io/oss-fuzz-base/base-builder@sha256:1f9cf74bc3d7029b528494542f9d9851b256dceed38d3f420989434dc5ae0760
# The base image's Ubuntu ships an old R; the package's sources need R >= 4.3 (Rvprintf), so R
# comes from CRAN's Ubuntu repository for whichever release the base image is.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates gnupg dirmngr software-properties-common \
 && . /etc/os-release \
 && gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys E298A3A825C0D65DFD57CBB651716619E084DAB9 \
 && gpg --export E298A3A825C0D65DFD57CBB651716619E084DAB9 > /etc/apt/trusted.gpg.d/cran.gpg \
 && echo "deb https://cloud.r-project.org/bin/linux/ubuntu ${UBUNTU_CODENAME}-cran40/" > /etc/apt/sources.list.d/cran.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends r-base-dev libcurl4-openssl-dev pkg-config zip \
 && rm -rf /var/lib/apt/lists/* \
 && R --version | head -1
ENV BL_REF=f8d2707b56b8815b15d5983e4076e6b06ad36367
RUN git clone --quiet https://github.com/rootcoder007/rmorie-bricklayer "$SRC/rmorie-bricklayer" \
 && git -C "$SRC/rmorie-bricklayer" checkout --quiet "$BL_REF"
COPY . "$SRC/rmbl-action"
COPY .clusterfuzzlite/build.sh "$SRC/build.sh"
WORKDIR "$SRC/rmbl-action"
