# The capsule, bundle and hmac attestation, byte by byte

This is what a program in any language has to write so that the action (and
rmoriebricklayer's `vrfcps()` and `cpsbndlvrf()`) verifies it. It is read off the R package
(1.0.0: `cpsbndl()` in `R/bundle.R`, `cpsatst()`/`cpschkatst()` in `R/attest.R`,
`cpssign()` in `R/sign.R`, `mnfcanon()`/`mnfdgst()` in `R/lib_manifest.R`, the string
encoder in `R/json_native.R`) and checked by the test vectors in
[`spec/vectors/`](../spec/vectors), which `spec/vectors/make.R` re-derives with the package
and the `vectors` CI job compares byte for byte. Every native example under
[`examples/`](../examples) writes those vectors byte for byte in CI.

If you do not want to write any of this, do not: write the data file and a plain
`data_provenance.json`, and let the action sign them (`mode: sign`, see the README).

## 1. The capsule

A capsule is a directory. It holds:

- one or more data files;
- `data_provenance.json`, which pins the data file (schema:
  [`spec/capsule.schema.json`](../spec/capsule.schema.json)). Required:
  `resource.filename` (relative to the directory, no `..`, not absolute) and
  `resource.sha256` (SHA-256 of the file's bytes, 64 hex). Checked when present:
  `resource.size_bytes` (bytes), `resource.row_count_data_rows` (CSV data rows, header
  excluded, as `utils::read.csv()` counts them). `name`, `source.url`, `source.retrieved`
  are what the report shows;
- optionally `capsule_bundle.json`, the signed bundle (section 3), and `manifest.json`.

The provenance can be written in any JSON layout: it is parsed, not hashed as text, except
that the bundle digests its bytes like any other file.

**First-run pin.** `mode: sign` (and the package's `cpsrfrsh()` on a first pin) fills, when
`resource.sha256` is absent: `resource.sha256` and, when `source` is an object,
`source.sha256` (both the data file's SHA-256), `resource.size_bytes`,
`resource.retrieved_utc` (`YYYY-MM-DDThh:mm:ssZ`), and `resource.row_count_data_rows` only
when it was already recorded. It rewrites the file with the package's pretty JSON writer.
A provenance that already has `resource.sha256` is left alone.

## 2. The canonical form

Every digest and signature below is taken over the *canonical form* of a JSON value
(`mnfcanon()`), as UTF-8 bytes with no trailing newline:

| Rule | Exactly |
|---|---|
| Whitespace | none: `{"a":1,"b":[1,2]}` |
| Object keys | sorted by their UTF-8 bytes (R sorts with `method = "radix"`), at every level |
| Arrays | in their order |
| Empty object or array | `[]` (R writes an empty list as `[]`; an empty manifest is `{"meta":[],"results":[]}`) |
| Integers | decimal, no exponent, no `.0` (`16`, `-5`, `3000000000`) |
| Other numbers | `%.17g` (`0.1` is `0.10000000000000001`). None of the fields here is one |
| `true`, `false`, `null` | as written |
| Strings | UTF-8 as is, including non-ASCII, U+2028, U+2029 and DEL (0x7f) |
| String escapes | `"` as `\"`, `\` as `\\`, newline `\n`, CR `\r`, tab `\t`, backspace `\b`, form feed `\f`; the other bytes below 0x20 as `\u00XX` with **lowercase** hex (`\u0001`, `\u001f`); `</` as `<\/`; nothing else |

The `</` rule is the one most libraries miss (jsonlite does it, so the package does). The
NUL character cannot occur (R strings cannot hold it).

What differs from common writers, so their output needs care or replacing:

| Writer | Differs on | Used here |
|---|---|---|
| JavaScript `JSON.stringify` (Node, Bun, Deno, TypeScript) | `</`; key order is insertion order | `JSON.stringify` per string, then `</` replaced; keys sorted by bytes by hand |
| Go `encoding/json` | always escapes U+2028/U+2029; escapes `<`, `>`, `&` unless `SetEscapeHTML(false)`; no `<\/` | a 15-line string writer; `sort.Strings` (byte order) for keys |
| Rust `serde_json` (`Value`, default features) | only `</` (keys are in a `BTreeMap`, byte order) | `to_string`, then `</` replaced |
| Python `json.dumps(..., ensure_ascii=False, separators=(",", ":"), sort_keys=True)` | `</`; `sort_keys` sorts by code point, the same as UTF-8 byte order | (morie writes its own) |
| Java, C, C++, Zig, Lua, POSIX sh | no JSON in the standard library | a minimal hand-written writer; the C, C++, Zig and sh ones write the fixed keys in sorted order |

Replacing `</` after escaping is exact: no escape sequence starts with `/` or ends with
`<`, so escaping neither creates nor breaks a `</`.

## 3. `capsule_bundle.json`

Schema: [`spec/bundle.schema.json`](../spec/bundle.schema.json). The file is parsed, so
its layout is free; the vectors write it in the canonical form plus `\n`. Fields:

- `files`: one object per file of the capsule, `{"path", "sha256", "size_bytes"}`: path
  relative to the capsule with `/`, SHA-256 hex (lowercase) of the bytes, size in bytes.
  `cpsbndl()` lists every regular file under the directory, recursively, dot-files
  included, sorted, except the bundle itself. The verifier re-hashes each listed file
  (`file:PATH` rows) and fails `no_unlisted_files` for any other file on disk (the bundle
  file excepted). Keep build outputs out of the capsule directory.
- `manifest_digest`: SHA-256 hex of the canonical form of the capsule's manifest. With no
  `manifest.json`, the empty manifest `{"meta":[],"results":[]}`:
  `43ee897435ca40346993b4d048187d560a840a8065350ed9e4eff69d6864efe7`. The action does
  not compare it with a manifest; it is covered by the signature.
- `bundled_utc`: `YYYY-MM-DDThh:mm:ssZ`.
- `attestation`: section 4.

## 4. The hmac attestation

```
inner   = {"meta": {"files": FILES, "manifest_digest": M, "bundled_utc": T}, "results": []}
digest  = hex(SHA-256(canon(inner)))
public  = hex(HMAC-SHA-256(key, "public"))          the key id; names the key, never reveals it
payload = {"digest": digest, "scheme": "hmac", "public": public, "context": "",
           "prehash": "none", "note": NOTE, "signed_utc": T2}
signed  = hex(SHA-256(canon(payload)))              64 lowercase hex characters
attestation = payload + {"signature": {"scheme": "hmac",
                                       "signature": hex(HMAC-SHA-256(key, signed))}}
```

- HMAC-SHA-256 is RFC 2104 over the UTF-8 bytes of the key and of the message; the message
  signed is the 64-character **hex text** of `signed`, not its 32 raw bytes.
- `context` is `""` and `prehash` `"none"` for hmac (the package refuses others).
- `note` is free text and is signed; `""` when there is none.
- The verifier (`cpschkatst()`) rebuilds `inner` from the bundle's own `files`,
  `manifest_digest` and `bundled_utc` and checks `digest` (row `manifest_digest`), checks
  `public` against `public-key` when given (`key_as_expected`), and with the secret given
  as `key` checks `HMAC-SHA-256(key, "public") == public` and then the signature
  (`signature`). Without the secret the `signature` row fails: hmac is a shared-secret
  scheme, so anyone holding the secret can sign.

## 5. Test vectors

[`spec/vectors/`](../spec/vectors), key `rmbl-action-test-secret`, both times
`2026-01-01T00:00:00Z`, and the note in [`note.txt`](../spec/vectors/note.txt), which holds
every escaping case: `"`, `\`, `</`, `/`, é, an emoji, tab, LF, CR, BS, FF, 0x01, 0x1f,
DEL and U+2028.

| File | What it is |
|---|---|
| `capsule/data.csv` | `x,y\n1,1\n2,4\n3,9\n` (16 bytes) |
| `capsule/data_provenance.json` | the canonical provenance plus `\n` (246 bytes) |
| `capsule/capsule_bundle.json` | the canonical bundle plus `\n` |
| `inner.canon.json` | `canon(inner)`, no newline: its SHA-256 is `digest` |
| `payload.canon.json` | `canon(payload)`, no newline: its SHA-256 is `signed` |
| `values.txt` | the values below |

| Value | Hex |
|---|---|
| key id (`public`) | `da884d9bd335b6a01e5354ef0f0f1f3df9a7a7ee8c2c00c7a893e47ed9abd053` |
| `data.csv` SHA-256 | `d625c4bc6e1804a94d1d5231b91f80bc2e8c9246e7d960d24b382345af850329` |
| `data_provenance.json` SHA-256 | `c7965655dbb567f385748bd60b627392c2e77e20b1e9c9323b1a7f2217f07dd8` |
| `manifest_digest` | `43ee897435ca40346993b4d048187d560a840a8065350ed9e4eff69d6864efe7` |
| attestation `digest` | `6711c3fedc38c514d1db3074725317e8952fdb2ed41d4044eb9e181e4ec2695d` |
| `signed` | `e3134f69f64d1a2e40e25c6b568a951c89832dcac2f28bac59e1c05f9762e6de` |
| `signature` | `756721d2dc1f441b13fe29ecfc62d57869ac9f77999555dc2d56c3b027f3e8b7` |

The provenance of the vectors:

```json
{"name":"squares","resource":{"filename":"data.csv","row_count_data_rows":3,"sha256":"d625c4bc6e1804a94d1d5231b91f80bc2e8c9246e7d960d24b382345af850329","size_bytes":16},"source":{"retrieved":"2026-01-01","url":"https://example.org/squares.csv"}}
```

`make.R` builds these from the package's primitives (`mnfcanon()`, `mnfdgst()`,
`sha256file()`, `chmac()`) and then requires `cpsbndlvrf()` to pass with the key and the key
id, `vrfcps()` to pass, and a wrong key to fail. To check a writer of your own: run it with
the vectors' time, key and note, and `cmp` its three files with `spec/vectors/capsule/`.
With an empty note and the current time the bytes differ, and the action is the check.
