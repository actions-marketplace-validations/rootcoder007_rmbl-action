// A capsule from C++17: data.csv, data_provenance.json and an hmac-signed capsule_bundle.json,
// with OpenSSL's EVP API and the canonical JSON written by hand (keys in sorted order).
// Build: g++ -std=c++17 -O2 -o capsule capsule.cpp -lcrypto
// Usage: RMBL_KEY=... ./capsule <capsule dir>
// RMBL_UTC fixes the time (YYYY-MM-DDThh:mm:ssZ), RMBL_NOTE_FILE names a file holding the note.
#include <openssl/evp.h>
#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <fstream>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>

static std::string hex(const unsigned char *p, size_t n) {
    static const char *d = "0123456789abcdef";
    std::string s;
    for (size_t i = 0; i < n; i++) { s += d[p[i] >> 4]; s += d[p[i] & 15]; }
    return s;
}
static std::string sha(const std::string &m) {
    unsigned char md[EVP_MAX_MD_SIZE];
    unsigned int n = 0;
    if (!EVP_Digest(m.data(), m.size(), md, &n, EVP_sha256(), nullptr)) throw std::runtime_error("sha256");
    return hex(md, n);
}
static std::string hmac(const std::string &key, const std::string &m) {
    unsigned char md[EVP_MAX_MD_SIZE];
    size_t n = 0;
    if (!EVP_Q_mac(nullptr, "HMAC", nullptr, "SHA256", nullptr, key.data(), key.size(),
                   reinterpret_cast<const unsigned char *>(m.data()), m.size(), md, sizeof md, &n))
        throw std::runtime_error("hmac");
    return hex(md, n);
}
// A JSON string in the canonical form (docs/bundle-format.md).
static std::string str(const std::string &s) {
    std::string o = "\"";
    for (size_t i = 0; i < s.size(); i++) {
        unsigned char c = static_cast<unsigned char>(s[i]);
        switch (c) {
        case '"': o += "\\\""; break;
        case '\\': o += "\\\\"; break;
        case '\n': o += "\\n"; break;
        case '\r': o += "\\r"; break;
        case '\t': o += "\\t"; break;
        case '\b': o += "\\b"; break;
        case '\f': o += "\\f"; break;
        default:
            if (c < 0x20) { char u[8]; std::snprintf(u, sizeof u, "\\u%04x", c); o += u; }
            else if (c == '/' && i > 0 && s[i - 1] == '<') o += "\\/";
            else o += static_cast<char>(c);
        }
    }
    return o + "\"";
}
static std::string kv(const std::string &k, const std::string &v) { return str(k) + ":" + v; }
static void put(const std::string &path, const std::string &text) {
    std::ofstream f(path, std::ios::binary);
    f << text;
    if (!f) throw std::runtime_error("cannot write " + path);
}
// {"path":...,"sha256":...,"size_bytes":...}: the keys in sorted order
static std::string entry(const std::string &name, const std::string &text) {
    return "{" + kv("path", str(name)) + "," + kv("sha256", str(sha(text))) + "," +
           kv("size_bytes", std::to_string(text.size())) + "}";
}

int main(int argc, char **argv) {
    const char *k = std::getenv("RMBL_KEY");
    if (argc != 2 || !k || !*k) { std::cerr << "usage: RMBL_KEY=... " << argv[0] << " <capsule dir>\n"; return 2; }
    const std::string key = k, dir = argv[1];
    std::string utc = std::getenv("RMBL_UTC") ? std::getenv("RMBL_UTC") : "";
    if (utc.empty()) {
        char b[32];
        std::time_t now = std::time(nullptr);
        std::strftime(b, sizeof b, "%Y-%m-%dT%H:%M:%SZ", std::gmtime(&now));
        utc = b;
    }
    std::string note;
    if (const char *nf = std::getenv("RMBL_NOTE_FILE")) {
        std::ifstream f(nf, std::ios::binary);
        std::stringstream ss;
        ss << f.rdbuf();
        note = ss.str();
    }

    // 1. the data
    std::string csv = "x,y\n";
    for (int x = 1; x <= 3; x++) csv += std::to_string(x) + "," + std::to_string(x * x) + "\n";
    put(dir + "/data.csv", csv);

    // 2. the provenance, pinned to the data
    std::string prov = "{" + kv("name", str("squares")) + "," +
        kv("resource", "{" + kv("filename", str("data.csv")) + "," + kv("row_count_data_rows", "3") + "," +
                       kv("sha256", str(sha(csv))) + "," + kv("size_bytes", std::to_string(csv.size())) + "}") + "," +
        kv("source", "{" + kv("retrieved", str(utc.substr(0, 10))) + "," +
                     kv("url", str("https://example.org/squares.csv")) + "}") + "}\n";
    put(dir + "/data_provenance.json", prov);

    // 3. the bundle: the files, the empty manifest's digest, and an hmac attestation over both
    std::string files = "[" + entry("data.csv", csv) + "," + entry("data_provenance.json", prov) + "]";
    std::string mdig = sha("{\"meta\":[],\"results\":[]}");
    std::string inner = "{" + kv("meta", "{" + kv("bundled_utc", str(utc)) + "," + kv("files", files) + "," +
                                         kv("manifest_digest", str(mdig)) + "}") + "," + kv("results", "[]") + "}";
    std::string kid = hmac(key, "public");
    // the attestation's fields without the signature, sorted; the signature sorts between them
    std::string head = kv("context", str("")) + "," + kv("digest", str(sha(inner))) + "," + kv("note", str(note)) +
                       "," + kv("prehash", str("none")) + "," + kv("public", str(kid)) + "," + kv("scheme", str("hmac"));
    std::string tail = kv("signed_utc", str(utc));
    std::string sig = hmac(key, sha("{" + head + "," + tail + "}"));
    std::string att = "{" + head + "," + kv("signature", "{" + kv("scheme", str("hmac")) + "," +
                      kv("signature", str(sig)) + "}") + "," + tail + "}";
    put(dir + "/capsule_bundle.json", "{" + kv("attestation", att) + "," + kv("bundled_utc", str(utc)) + "," +
        kv("files", files) + "," + kv("manifest_digest", str(mdig)) + "}\n");
    std::cout << "signed " << dir << " (key id " << kid << ")\n";
    return 0;
}
