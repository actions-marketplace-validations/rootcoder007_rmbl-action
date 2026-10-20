# Wolfram Language

[`capsule.wls`](capsule.wls) writes `data.csv` and a plain `data_provenance.json` with
`Export` (`"CSV"` and `"RawJSON"`), and leaves the pin and the signature to the action's
`mode: sign`, as in [`examples/any`](../any):

```yaml
      - run: wolframscript -file examples/wolfram/capsule.wls capsules/squares
      - uses: rootcoder007/rmbl-action@v1
        with:
          path: capsules
          mode: sign
          key: ${{ secrets.CAPSULE_KEY }}
```

It is not run in CI: the Wolfram Engine needs an activated licence (a Wolfram ID) on the
runner, which this repository does not have. The `example-sign` job runs the same path with
POSIX sh and awk producers.

A native-signing variant is possible: `Hash[ByteArray[...], "SHA256", "HexString"]` gives
the digests, HMAC-SHA-256 can be built from `Hash` as RFC 2104 defines it (or with a built-in
HMAC where your version has one), and the JSON would have to be written in the canonical
form of [`docs/bundle-format.md`](../../docs/bundle-format.md) section 2 (keys sorted by
bytes, no whitespace, the `</` escape) and checked against
[`spec/vectors/`](../../spec/vectors).
