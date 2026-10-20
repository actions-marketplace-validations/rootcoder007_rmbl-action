## rmbl capsule verify with [rmoriebricklayer 1.0.0](https://github.com/rootcoder007/rmorie-bricklayer)

**✔ ok**: 3 capsules under `/tmp/tmp.FaUNFG09ob/all`: 3 ok, 0 warn, 0 drift, 0 error

| Capsule | Source | SHA-256 | Size | Rows | Bounds | Result |
|---|---|---|---|---|---|---|
| `/tmp/tmp.FaUNFG09ob/all/c` | example.org | `b56e1709a40a` | 0.1 KB | 4 | - | ✔ ok |
| `/tmp/tmp.FaUNFG09ob/all/python` | example.org | `b56e1709a40a` | 0.1 KB | 4 | - | ✔ ok |
| `/tmp/tmp.FaUNFG09ob/all/r` | example.org | `b56e1709a40a` | 0.1 KB | 4 | - | ✔ ok |

<details>
<summary>✔ <code>/tmp/tmp.FaUNFG09ob/all/c</code>: ok, 8 of 8 checks passed (click to open)</summary>

- Source: https://example.org/sample.csv
- Pinned SHA-256: `b56e1709a40acd15c7b00dcaeec2b07b3baab5f5164372dda7513fedfe26f41d`

| Status | Check | Detail |
|---|---|---|
| ✔ pass | schema: data_provenance.json | valid against capsule.schema.json |
| ✔ pass | provenance_readable | /tmp/tmp.FaUNFG09ob/all/c/data_provenance.json |
| ✔ pass | data_present | /tmp/tmp.FaUNFG09ob/all/c/sample.csv |
| ✔ pass | data_sha256 | b56e1709a40acd15c7b00dcaeec2b07b3baab5f5164372dda7513fedfe26f41d |
| ✔ pass | data_size_bytes | 79 bytes on disk |
| ✔ pass | data_readable | /tmp/tmp.FaUNFG09ob/all/c/sample.csv |
| ✔ pass | data_row_count | 4 rows on disk |
| ✔ pass | data_not_synthetic | no synthetic marker: sidecar, manifest and provenance all say real data |

</details>

<details>
<summary>✔ <code>/tmp/tmp.FaUNFG09ob/all/python</code>: ok, 8 of 8 checks passed (click to open)</summary>

- Source: https://example.org/sample.csv
- Pinned SHA-256: `b56e1709a40acd15c7b00dcaeec2b07b3baab5f5164372dda7513fedfe26f41d`

| Status | Check | Detail |
|---|---|---|
| ✔ pass | schema: data_provenance.json | valid against capsule.schema.json |
| ✔ pass | provenance_readable | /tmp/tmp.FaUNFG09ob/all/python/data_provenance.json |
| ✔ pass | data_present | /tmp/tmp.FaUNFG09ob/all/python/sample.csv |
| ✔ pass | data_sha256 | b56e1709a40acd15c7b00dcaeec2b07b3baab5f5164372dda7513fedfe26f41d |
| ✔ pass | data_size_bytes | 79 bytes on disk |
| ✔ pass | data_readable | /tmp/tmp.FaUNFG09ob/all/python/sample.csv |
| ✔ pass | data_row_count | 4 rows on disk |
| ✔ pass | data_not_synthetic | no synthetic marker: sidecar, manifest and provenance all say real data |

</details>

<details>
<summary>✔ <code>/tmp/tmp.FaUNFG09ob/all/r</code>: ok, 8 of 8 checks passed (click to open)</summary>

- Source: https://example.org/sample.csv
- Pinned SHA-256: `b56e1709a40acd15c7b00dcaeec2b07b3baab5f5164372dda7513fedfe26f41d`

| Status | Check | Detail |
|---|---|---|
| ✔ pass | schema: data_provenance.json | valid against capsule.schema.json |
| ✔ pass | provenance_readable | /tmp/tmp.FaUNFG09ob/all/r/data_provenance.json |
| ✔ pass | data_present | /tmp/tmp.FaUNFG09ob/all/r/sample.csv |
| ✔ pass | data_sha256 | b56e1709a40acd15c7b00dcaeec2b07b3baab5f5164372dda7513fedfe26f41d |
| ✔ pass | data_size_bytes | 79 bytes on disk |
| ✔ pass | data_readable | /tmp/tmp.FaUNFG09ob/all/r/sample.csv |
| ✔ pass | data_row_count | 4 rows on disk |
| ✔ pass | data_not_synthetic | no synthetic marker: sidecar, manifest and provenance all say real data |

</details>

---

Footprint of these checks (co2fp(), modelled, Green Algorithms): 0.3 s wall, 0.3 s CPU, 0.00444 Wh, 0.00171 gCO2e at 384.4 gCO2e/kWh (United States, 2025).

mode `verify` · fail-on `error` · rmoriebricklayer 1.0.0 · R version 4.6.1 (2026-06-24)
