#!/usr/bin/env bash
# Build the libFuzzer targets with the engine and sanitizer ClusterFuzzLite selects
# ($CXXFLAGS, $LIB_FUZZING_ENGINE), from the package checkout the Dockerfile made.
#   fuzz_der    the DER parser and RSA big-integer arithmetic (bundle signatures)
#   fuzz_url    the URL policy and redirect rule (capsule sources)
#   fuzz_strtod decimal-to-double, checked bit for bit against libc (CSV and manifest numbers)
#   fuzz_siu    the SIU report parsers (fetched HTML and text)
set -euo pipefail
FZ="$SRC/rmorie-bricklayer/inst/fuzz"
PKG="$SRC/rmorie-bricklayer/src"
cd "$FZ"
RCPP=$(R CMD config --cppflags)
RLIB=$(R RHOME)/lib
# libR and the libraries it pulls in travel with the binaries: the runner image has no R
mkdir -p "$OUT/lib"
RLD="-L$RLIB -Wl,-rpath,\$ORIGIN/lib -lR"
FLAGS="-std=gnu++17 -DR_USE_C99_IN_CXX -I$PKG $RCPP $CXXFLAGS"
$CXX $FLAGS fuzz_der.cpp -o "$OUT/fuzz_der" $LIB_FUZZING_ENGINE $RLD
$CXX $FLAGS fuzz_strtod.cpp -o "$OUT/fuzz_strtod" $LIB_FUZZING_ENGINE $RLD
$CXX $FLAGS fuzz_siu.cpp "$PKG/siu_parse.cpp" "$PKG/siu_resolve.cpp" -o "$OUT/fuzz_siu" $LIB_FUZZING_ENGINE
$CC $CFLAGS -I"$PKG" $RCPP -c "$PKG/rmbl_progress.c" -o /tmp/rmbl_progress.o
$CXX $FLAGS -DRMBL_FUZZ_EXPORTS fuzz_url.cpp "$PKG/rmbl_fetch.cpp" /tmp/rmbl_progress.o \
  -o "$OUT/fuzz_url" $LIB_FUZZING_ENGINE $RLD $(curl-config --libs)
for t in der url strtod siu; do
  (cd "corpus/$t" && zip -q -r "$OUT/fuzz_${t}_seed_corpus.zip" .)
  printf '[libfuzzer]\ntimeout = 10\nrss_limit_mb = 2048\n' > "$OUT/fuzz_$t.options"
done
# every shared library the binaries need that the runner does not ship (libR, BLAS, LAPACK,
# gfortran, ICU, readline, pcre2, ...): resolved here with ldd and copied next to them
for b in "$OUT"/fuzz_der "$OUT"/fuzz_strtod "$OUT"/fuzz_url "$OUT"/fuzz_siu; do
  ldd "$b" | awk '/=> \//{print $3}' | grep -Ev '/lib(c|m|dl|rt|pthread|gcc_s|stdc\+\+)\.so' \
    | while read -r so; do cp -n "$so" "$OUT/lib/" 2>/dev/null || true; done
done
ls "$OUT"
