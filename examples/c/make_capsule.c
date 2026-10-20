/* Write data_provenance.json next to a CSV: SHA-256 with OpenSSL's EVP API, JSON by hand.
 * Build: gcc -std=c11 -O2 -o make_capsule make_capsule.c -lcrypto
 * Usage: ./make_capsule <csv path> <source url>
 * Rows are counted as lines after the header; a quoted field holding a newline would be
 * counted twice (use a CSV parser for such files). C++ can call the same code unchanged. */
#include <openssl/evp.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

/* a JSON string literal: quote, backslash and control characters escaped */
static void json_str(FILE *out, const char *s) {
    fputc('"', out);
    for (; *s; s++) {
        unsigned char c = (unsigned char)*s;
        if (c == '"' || c == '\\') fprintf(out, "\\%c", c);
        else if (c < 0x20) fprintf(out, "\\u%04x", c);
        else fputc(c, out);
    }
    fputc('"', out);
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s <csv path> <source url>\n", argv[0]);
        return 2;
    }
    FILE *in = fopen(argv[1], "rb");
    if (!in) { perror(argv[1]); return 1; }

    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    EVP_DigestInit_ex(ctx, EVP_sha256(), NULL);
    unsigned char buf[65536], md[EVP_MAX_MD_SIZE];
    unsigned int mdlen = 0;
    long long size = 0, lines = 0;
    int last = '\n';
    size_t n;
    while ((n = fread(buf, 1, sizeof buf, in)) > 0) {
        EVP_DigestUpdate(ctx, buf, n);
        size += (long long)n;
        for (size_t i = 0; i < n; i++) if (buf[i] == '\n') lines++;
        last = buf[n - 1];
    }
    fclose(in);
    if (size > 0 && last != '\n') lines++;          /* a last line without a newline */
    EVP_DigestFinal_ex(ctx, md, &mdlen);
    EVP_MD_CTX_free(ctx);
    char hex[2 * EVP_MAX_MD_SIZE + 1];
    for (unsigned int i = 0; i < mdlen; i++) sprintf(hex + 2 * i, "%02x", md[i]);

    /* the capsule directory and file name */
    const char *slash = strrchr(argv[1], '/');
    const char *file = slash ? slash + 1 : argv[1];
    char dir[4096], stem[1024], outpath[4200], date[11];
    snprintf(dir, sizeof dir, "%.*s", slash ? (int)(slash - argv[1]) : 1, slash ? argv[1] : ".");
    snprintf(stem, sizeof stem, "%s", file);
    size_t sl = strlen(stem);
    if (sl > 4 && strcmp(stem + sl - 4, ".csv") == 0) stem[sl - 4] = '\0';
    snprintf(outpath, sizeof outpath, "%s/data_provenance.json", dir);
    time_t now = time(NULL);
    strftime(date, sizeof date, "%Y-%m-%d", localtime(&now));

    FILE *out = fopen(outpath, "w");
    if (!out) { perror(outpath); return 1; }
    fputs("{\n  \"name\": ", out); json_str(out, stem);
    fputs(",\n  \"source\": {\n    \"url\": ", out); json_str(out, argv[2]);
    fprintf(out, ",\n    \"retrieved\": \"%s\"\n  },\n", date);
    fputs("  \"resource\": {\n    \"filename\": ", out); json_str(out, file);
    fprintf(out, ",\n    \"sha256\": \"%s\",\n    \"size_bytes\": %lld,\n    \"row_count_data_rows\": %lld\n  }\n}\n",
            hex, size, lines > 0 ? lines - 1 : 0);
    fclose(out);
    return 0;
}
