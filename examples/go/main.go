// A capsule from Go: data.csv, data_provenance.json and an hmac-signed capsule_bundle.json,
// with the standard library only. Usage: RMBL_KEY=... go run . <capsule dir>
// RMBL_UTC fixes the time (YYYY-MM-DDThh:mm:ssZ), RMBL_NOTE_FILE names a file holding the note.
package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

type obj = map[string]any
type arr = []any

// str writes a JSON string in the canonical form. encoding/json is not used for strings: it
// always escapes U+2028 and U+2029, escapes <, > and & unless SetEscapeHTML(false), and never
// writes "</" as "<\/", where the canonical form does the opposite on all three.
func str(s string) string {
	var b strings.Builder
	b.WriteByte('"')
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c == '"':
			b.WriteString(`\"`)
		case c == '\\':
			b.WriteString(`\\`)
		case c == '\n':
			b.WriteString(`\n`)
		case c == '\r':
			b.WriteString(`\r`)
		case c == '\t':
			b.WriteString(`\t`)
		case c == '\b':
			b.WriteString(`\b`)
		case c == '\f':
			b.WriteString(`\f`)
		case c < 0x20:
			fmt.Fprintf(&b, `\u%04x`, c)
		case c == '/' && i > 0 && s[i-1] == '<':
			b.WriteString(`\/`)
		default:
			b.WriteByte(c) // UTF-8 bytes as they are
		}
	}
	b.WriteByte('"')
	return b.String()
}

// canon writes v in the canonical form: object keys sorted by bytes, no whitespace, integers.
func canon(v any) string {
	switch v := v.(type) {
	case string:
		return str(v)
	case int:
		return strconv.Itoa(v)
	case arr:
		parts := make([]string, len(v))
		for i, x := range v {
			parts[i] = canon(x)
		}
		return "[" + strings.Join(parts, ",") + "]"
	case obj:
		keys := make([]string, 0, len(v))
		for k := range v {
			keys = append(keys, k)
		}
		sort.Strings(keys) // byte order
		parts := make([]string, len(keys))
		for i, k := range keys {
			parts[i] = str(k) + ":" + canon(v[k])
		}
		return "{" + strings.Join(parts, ",") + "}"
	}
	log.Fatalf("not written in the canonical form: %#v", v)
	return ""
}

func sha(b []byte) string { s := sha256.Sum256(b); return hex.EncodeToString(s[:]) }

func main() {
	key := os.Getenv("RMBL_KEY")
	if len(os.Args) != 2 || key == "" {
		log.Fatal("usage: RMBL_KEY=... go run . <capsule dir>")
	}
	dir := os.Args[1]
	utc := os.Getenv("RMBL_UTC")
	if utc == "" {
		utc = time.Now().UTC().Format("2006-01-02T15:04:05Z")
	}
	note := ""
	if f := os.Getenv("RMBL_NOTE_FILE"); f != "" {
		b, err := os.ReadFile(f)
		if err != nil {
			log.Fatal(err)
		}
		note = string(b)
	}
	mac := func(m string) string {
		h := hmac.New(sha256.New, []byte(key))
		h.Write([]byte(m))
		return hex.EncodeToString(h.Sum(nil))
	}
	write := func(name, text string) obj {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(text), 0o644); err != nil {
			log.Fatal(err)
		}
		return obj{"path": name, "sha256": sha([]byte(text)), "size_bytes": len(text)}
	}

	// 1. the data
	csv := "x,y\n"
	for x := 1; x <= 3; x++ {
		csv += fmt.Sprintf("%d,%d\n", x, x*x)
	}
	data := write("data.csv", csv)

	// 2. the provenance, pinned to the data
	prov := obj{
		"name":   "squares",
		"source": obj{"url": "https://example.org/squares.csv", "retrieved": utc[:10]},
		"resource": obj{"filename": "data.csv", "sha256": data["sha256"], "size_bytes": data["size_bytes"],
			"row_count_data_rows": 3},
	}
	provFile := write("data_provenance.json", canon(prov)+"\n")

	// 3. the bundle: the files, the empty manifest's digest, and an hmac attestation over both
	files := arr{data, provFile}
	manifestDigest := sha([]byte(canon(obj{"meta": arr{}, "results": arr{}})))
	inner := obj{"meta": obj{"files": files, "manifest_digest": manifestDigest, "bundled_utc": utc}, "results": arr{}}
	att := obj{
		"digest": sha([]byte(canon(inner))), "scheme": "hmac", "public": mac("public"),
		"context": "", "prehash": "none", "note": note, "signed_utc": utc,
	}
	att["signature"] = obj{"scheme": "hmac", "signature": mac(sha([]byte(canon(att))))}
	bundle := obj{"files": files, "manifest_digest": manifestDigest, "bundled_utc": utc, "attestation": att}
	write("capsule_bundle.json", canon(bundle)+"\n")
	fmt.Printf("signed %s (key id %s)\n", dir, att["public"])
}
