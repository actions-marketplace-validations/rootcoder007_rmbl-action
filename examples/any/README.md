# Any language: write two files, let the action sign

A program in any language, with no crypto and no JSON library, makes a capsule by writing
two files into a directory:

- the data file (here `data.csv`);
- a plain `data_provenance.json` naming it: `{"resource": {"filename": "data.csv"}}` at the
  least, with `name` and `source.url` if you have them, and `resource.row_count_data_rows`
  (any number) if the CSV's row count should be pinned and checked too.

The action's `mode: sign` then pins the provenance on its first run (`resource.sha256`,
`size_bytes`, `retrieved_utc`, and `source.sha256`), writes `capsule_bundle.json` with an
`hmac` attestation under the `key` you pass from a repository secret, and verifies the
result. It fails when a bundle is already there unless `overwrite: true`.

- [`produce.sh`](produce.sh): POSIX sh, `printf` and a CSV.
- [`produce.awk`](produce.awk): awk, a stand-in for a language with nothing but file output
  (Wolfram Language, Fortran, COBOL, Stata, ...).

```yaml
      - run: sh examples/any/produce.sh capsules/squares   # any language
      - uses: rootcoder007/rmbl-action@v1
        with:
          path: capsules
          mode: sign
          key: ${{ secrets.CAPSULE_KEY }}
      - uses: rootcoder007/rmbl-action@v1
        with:
          path: capsules
          key: ${{ secrets.CAPSULE_KEY }}
          public-key: ${{ vars.CAPSULE_KEY_ID }}
```

The test workflow's `example-sign` job runs both producers, signs, verifies with the key id
pinned, checks that signing again fails without `overwrite` and works with it, that signing
without a key fails, and that a flipped byte of `data.csv` fails verification.
