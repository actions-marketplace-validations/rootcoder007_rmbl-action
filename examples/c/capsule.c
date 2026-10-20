/* A capsule from C: data.csv, data_provenance.json and an hmac-signed capsule_bundle.json,
 * with OpenSSL's EVP API and the canonical JSON written by hand (keys in sorted order) into
 * POSIX open_memstream() buffers.
 * Build: gcc -std=c11 -O2 -o capsule capsule.c -lcrypto
 * Usage: RMBL_KEY=... ./capsule <capsule dir>
 * RMBL_UTC fixes the time (YYYY-MM-DDThh:mm:ssZ), RMBL_NOTE_FILE names a file holding the note. */
#define _POSIX_C_SOURCE 200809L
#include <openssl/evp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct { char *p; size_t n; FILE *f; } buf;
static void bopen(buf *b) { b->p = NULL; b->n = 0; b->f = open_memstream(&b->p, &b->n); }
static void bclose(buf *b) { fclose(b->f); }

static void hex(const unsigned char *p, size_t n, char *out) {
    for (size_t i = 0; i < n; i++) sprintf(out + 2 * i, "%02x", p[i]);
}
static void sha(const char *m, size_t n, char out[65]) {
    unsigned char md[EVP_MAX_MD_SIZE];
    unsigned int len = 0;
    if (!EVP_Digest(m, n, md, &len, EVP_sha256(), NULL)) { fputs("sha256 failed\n", stderr); exit(1); }
    hex(md, len, out);
}
static void hmac(const char *key, const char *m, char out[65]) {
    unsigned char md[EVP_MAX_MD_SIZE];
    size_t len = 0;
    if (!EVP_Q_mac(NULL, "HMAC", NULL, "SHA256", NULL, key, strlen(key), (const unsigned char *)m, strlen(m),
                   md, sizeof md, &len)) { fputs("hmac failed\n", stderr); exit(1); }
    hex(md, len, out);
}
/* a JSON string in the canonical form (docs/bundle-format.md) */
static void str(FILE *o, const char *s) {
    fputc('"', o);
    for (size_t i = 0; s[i]; i++) {
        unsigned char c = (unsigned char)s[i];
        switch (c) {
        case '"': fputs("\\\"", o); break;
        case '\\': fputs("\\\\", o); break;
        case '\n': fputs("\\n", o); break;
        case '\r': fputs("\\r", o); break;
        case '\t': fputs("\\t", o); break;
        case '\b': fputs("\\b", o); break;
        case '\f': fputs("\\f", o); break;
        default:
            if (c < 0x20) fprintf(o, "\\u%04x", c);
            else if (c == '/' && i > 0 && s[i - 1] == '<') fputs("\\/", o);
            else fputc(c, o);
        }
    }
    fputc('"', o);
}
static void put(const char *dir, const char *name, const char *text, size_t n) {
    char path[4096];
    snprintf(path, sizeof path, "%s/%s", dir, name);
    FILE *f = fopen(path, "wb");
    if (!f || fwrite(text, 1, n, f) != n || fclose(f)) { perror(path); exit(1); }
}
/* {"path":...,"sha256":...,"size_bytes":...}: the keys in sorted order */
static void entry(FILE *o, const char *name, const buf *b) {
    char h[65];
    sha(b->p, b->n, h);
    fputs("{\"path\":", o); str(o, name);
    fputs(",\"sha256\":", o); str(o, h);
    fprintf(o, ",\"size_bytes\":%zu}", b->n);
}

int main(int argc, char **argv) {
    const char *key = getenv("RMBL_KEY");
    if (argc != 2 || !key || !*key) { fprintf(stderr, "usage: RMBL_KEY=... %s <capsule dir>\n", argv[0]); return 2; }
    const char *dir = argv[1];
    char utc[32], date[11];
    const char *fixed = getenv("RMBL_UTC");
    if (fixed && *fixed) snprintf(utc, sizeof utc, "%s", fixed);
    else { time_t now = time(NULL); strftime(utc, sizeof utc, "%Y-%m-%dT%H:%M:%SZ", gmtime(&now)); }
    snprintf(date, sizeof date, "%.10s", utc);
    buf note;
    bopen(&note);
    const char *nf = getenv("RMBL_NOTE_FILE");
    if (nf) {
        FILE *f = fopen(nf, "rb");
        if (!f) { perror(nf); return 1; }
        int c;
        while ((c = fgetc(f)) != EOF) fputc(c, note.f);
        fclose(f);
    }
    bclose(&note);

    /* 1. the data */
    buf csv;
    bopen(&csv);
    fputs("x,y\n", csv.f);
    for (int x = 1; x <= 3; x++) fprintf(csv.f, "%d,%d\n", x, x * x);
    bclose(&csv);
    put(dir, "data.csv", csv.p, csv.n);

    /* 2. the provenance, pinned to the data */
    char dsha[65];
    sha(csv.p, csv.n, dsha);
    buf prov;
    bopen(&prov);
    fputs("{\"name\":\"squares\",\"resource\":{\"filename\":\"data.csv\",\"row_count_data_rows\":3,\"sha256\":", prov.f);
    str(prov.f, dsha);
    fprintf(prov.f, ",\"size_bytes\":%zu},\"source\":{\"retrieved\":", csv.n);
    str(prov.f, date);
    fputs(",\"url\":\"https://example.org/squares.csv\"}}\n", prov.f);
    bclose(&prov);
    put(dir, "data_provenance.json", prov.p, prov.n);

    /* 3. the bundle: the files, the empty manifest's digest, and an hmac attestation over both */
    buf files;
    bopen(&files);
    fputc('[', files.f); entry(files.f, "data.csv", &csv); fputc(',', files.f);
    entry(files.f, "data_provenance.json", &prov); fputc(']', files.f);
    bclose(&files);
    char mdig[65], kid[65], adig[65], pdig[65], sig[65];
    const char *empty = "{\"meta\":[],\"results\":[]}";
    sha(empty, strlen(empty), mdig);
    buf inner;
    bopen(&inner);
    fputs("{\"meta\":{\"bundled_utc\":", inner.f); str(inner.f, utc);
    fprintf(inner.f, ",\"files\":%s,\"manifest_digest\":", files.p); str(inner.f, mdig);
    fputs("},\"results\":[]}", inner.f);
    bclose(&inner);
    sha(inner.p, inner.n, adig);
    hmac(key, "public", kid);
    /* the attestation's fields without the signature, sorted; the signature sorts between them */
    buf head;
    bopen(&head);
    fputs("\"context\":\"\",\"digest\":", head.f); str(head.f, adig);
    fputs(",\"note\":", head.f); str(head.f, note.p);
    fputs(",\"prehash\":\"none\",\"public\":", head.f); str(head.f, kid);
    fputs(",\"scheme\":\"hmac\"", head.f);
    bclose(&head);
    buf pay;
    bopen(&pay);
    fprintf(pay.f, "{%s,\"signed_utc\":", head.p); str(pay.f, utc); fputc('}', pay.f);
    bclose(&pay);
    sha(pay.p, pay.n, pdig);
    hmac(key, pdig, sig);
    buf out;
    bopen(&out);
    fprintf(out.f, "{\"attestation\":{%s,\"signature\":{\"scheme\":\"hmac\",\"signature\":\"%s\"},\"signed_utc\":", head.p, sig);
    str(out.f, utc);
    fputs("},\"bundled_utc\":", out.f); str(out.f, utc);
    fprintf(out.f, ",\"files\":%s,\"manifest_digest\":\"%s\"}\n", files.p, mdig);
    bclose(&out);
    put(dir, "capsule_bundle.json", out.p, out.n);
    printf("signed %s (key id %s)\n", dir, kid);
    return 0;
}
