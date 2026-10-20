// A capsule from Node: data.csv, data_provenance.json and an hmac-signed capsule_bundle.json.
// Only node:crypto and node:fs. Usage: RMBL_KEY=... node capsule.mjs <capsule dir>
// RMBL_UTC fixes the time (YYYY-MM-DDThh:mm:ssZ), RMBL_NOTE_FILE names a file holding the note.
import { createHash, createHmac } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const [dir] = process.argv.slice(2);
const key = process.env.RMBL_KEY;
if (!dir || !key) throw new Error("usage: RMBL_KEY=... node capsule.mjs <capsule dir>");
const utc = process.env.RMBL_UTC || new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
const note = process.env.RMBL_NOTE_FILE ? readFileSync(process.env.RMBL_NOTE_FILE, "utf8") : "";

// The canonical form (docs/bundle-format.md): keys sorted by UTF-8 bytes, no whitespace,
// integers only, strings as JSON.stringify writes them plus "</" written "<\/".
const str = (s) => JSON.stringify(s).replaceAll("</", "<\\/");
const byBytes = (a, b) => Buffer.compare(Buffer.from(a), Buffer.from(b));
function canon(v) {
  if (typeof v === "string") return str(v);
  if (Number.isSafeInteger(v)) return String(v);
  if (Array.isArray(v)) return `[${v.map(canon).join(",")}]`;
  if (v && typeof v === "object") {
    return `{${Object.keys(v).sort(byBytes).map((k) => `${str(k)}:${canon(v[k])}`).join(",")}}`;
  }
  throw new Error(`not written in the canonical form: ${v}`);
}
const sha256 = (b) => createHash("sha256").update(b).digest("hex");
const hmac = (m) => createHmac("sha256", key).update(m).digest("hex");
const write = (name, text) => {
  writeFileSync(join(dir, name), text);
  const bytes = readFileSync(join(dir, name));
  return { path: name, sha256: sha256(bytes), size_bytes: bytes.length };
};

// 1. the data
let csv = "x,y\n";
for (let x = 1; x <= 3; x++) csv += `${x},${x * x}\n`;
const data = write("data.csv", csv);

// 2. the provenance, pinned to the data
const prov = {
  name: "squares",
  source: { url: "https://example.org/squares.csv", retrieved: utc.slice(0, 10) },
  resource: { filename: data.path, sha256: data.sha256, size_bytes: data.size_bytes, row_count_data_rows: 3 },
};
const provFile = write("data_provenance.json", canon(prov) + "\n");

// 3. the bundle: the files, the empty manifest's digest, and an hmac attestation over both
const files = [data, provFile];
const manifest_digest = sha256(canon({ meta: [], results: [] }));
const payload = {
  digest: sha256(canon({ meta: { files, manifest_digest, bundled_utc: utc }, results: [] })),
  scheme: "hmac",
  public: hmac("public"),
  context: "",
  prehash: "none",
  note,
  signed_utc: utc,
};
const signature = { scheme: "hmac", signature: hmac(sha256(canon(payload))) };
writeFileSync(join(dir, "capsule_bundle.json"),
  canon({ files, manifest_digest, bundled_utc: utc, attestation: { ...payload, signature } }) + "\n");
console.log(`signed ${dir} (key id ${payload.public})`);
