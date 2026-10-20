//! A capsule from Rust: data.csv, data_provenance.json and an hmac-signed capsule_bundle.json,
//! with the sha2, hmac and serde_json crates. Usage: RMBL_KEY=... cargo run -- <capsule dir>
//! RMBL_UTC fixes the time (YYYY-MM-DDThh:mm:ssZ), RMBL_NOTE_FILE names a file holding the note.
use hmac::{Hmac, Mac};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{env, fs, path::Path, time::SystemTime};

/// The canonical form. serde_json's `Value` keeps objects in a BTreeMap (keys sorted by
/// bytes) and writes compact JSON with the canonical escapes, except that it writes "</" as
/// is where the canonical form writes "<\/". Escaping never makes or breaks a "</", so a
/// replace afterwards gives the canonical bytes.
fn canon(v: &Value) -> String {
    serde_json::to_string(v).expect("JSON").replace("</", "<\\/")
}

fn sha(b: &[u8]) -> String {
    format!("{:x}", Sha256::digest(b))
}

/// Days since 1970-01-01 to a civil date (H. Hinnant's algorithm), for the UTC stamp.
fn utc_now() -> String {
    let s = SystemTime::now().duration_since(SystemTime::UNIX_EPOCH).unwrap().as_secs() as i64;
    let (days, rem) = (s.div_euclid(86400), s.rem_euclid(86400));
    let z = days + 719468;
    let era = z.div_euclid(146097);
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + if m <= 2 { 1 } else { 0 };
    format!("{y:04}-{m:02}-{d:02}T{:02}:{:02}:{:02}Z", rem / 3600, rem / 60 % 60, rem % 60)
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let key = env::var("RMBL_KEY").unwrap_or_default();
    if args.len() != 2 || key.is_empty() {
        panic!("usage: RMBL_KEY=... cargo run -- <capsule dir>");
    }
    let dir = Path::new(&args[1]);
    let utc = env::var("RMBL_UTC").unwrap_or_else(|_| utc_now());
    let note = env::var("RMBL_NOTE_FILE").map(|f| fs::read_to_string(f).unwrap()).unwrap_or_default();
    let mac = |m: &str| {
        let mut h = Hmac::<Sha256>::new_from_slice(key.as_bytes()).unwrap();
        h.update(m.as_bytes());
        format!("{:x}", h.finalize().into_bytes())
    };
    let write = |name: &str, text: &str| {
        fs::write(dir.join(name), text).unwrap();
        json!({"path": name, "sha256": sha(text.as_bytes()), "size_bytes": text.len()})
    };

    // 1. the data
    let mut csv = String::from("x,y\n");
    for x in 1..=3 {
        csv += &format!("{x},{}\n", x * x);
    }
    let data = write("data.csv", &csv);

    // 2. the provenance, pinned to the data
    let prov = json!({
        "name": "squares",
        "source": {"url": "https://example.org/squares.csv", "retrieved": &utc[..10]},
        "resource": {"filename": "data.csv", "sha256": data["sha256"], "size_bytes": data["size_bytes"],
                     "row_count_data_rows": 3}
    });
    let prov_file = write("data_provenance.json", &(canon(&prov) + "\n"));

    // 3. the bundle: the files, the empty manifest's digest, and an hmac attestation over both
    let files = json!([data, prov_file]);
    let manifest_digest = sha(canon(&json!({"meta": [], "results": []})).as_bytes());
    let inner = json!({"meta": {"files": files, "manifest_digest": manifest_digest, "bundled_utc": utc},
                       "results": []});
    let mut att = json!({
        "digest": sha(canon(&inner).as_bytes()), "scheme": "hmac", "public": mac("public"),
        "context": "", "prehash": "none", "note": note, "signed_utc": utc
    });
    att["signature"] = json!({"scheme": "hmac", "signature": mac(&sha(canon(&att).as_bytes()))});
    let bundle = json!({"files": files, "manifest_digest": manifest_digest, "bundled_utc": utc,
                        "attestation": att});
    fs::write(dir.join("capsule_bundle.json"), canon(&bundle) + "\n").unwrap();
    println!("signed {} (key id {})", dir.display(), att["public"].as_str().unwrap());
}
