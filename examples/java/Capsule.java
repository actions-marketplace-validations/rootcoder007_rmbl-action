// A capsule from Java: data.csv, data_provenance.json and an hmac-signed capsule_bundle.json,
// with java.security, javax.crypto and a small canonical JSON writer (Java has no JSON in the
// JDK). Usage: RMBL_KEY=... java Capsule.java <capsule dir>
// RMBL_UTC fixes the time (YYYY-MM-DDThh:mm:ssZ), RMBL_NOTE_FILE names a file holding the note.
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Arrays;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

public class Capsule {
    static final HexFormat HEX = HexFormat.of();

    /** A JSON string in the canonical form (docs/bundle-format.md). */
    static String str(String s) {
        StringBuilder b = new StringBuilder("\"");
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"' -> b.append("\\\"");
                case '\\' -> b.append("\\\\");
                case '\n' -> b.append("\\n");
                case '\r' -> b.append("\\r");
                case '\t' -> b.append("\\t");
                case '\b' -> b.append("\\b");
                case '\f' -> b.append("\\f");
                default -> {
                    if (c < 0x20) b.append(String.format("\\u%04x", (int) c));
                    else if (c == '/' && i > 0 && s.charAt(i - 1) == '<') b.append("\\/");
                    else b.append(c);
                }
            }
        }
        return b.append('"').toString();
    }

    /** The canonical form: object keys sorted by their UTF-8 bytes, no whitespace, integers. */
    static String canon(Object v) {
        if (v instanceof String s) return str(s);
        if (v instanceof Integer || v instanceof Long) return v.toString();
        if (v instanceof List<?> l) return l.stream().map(Capsule::canon).collect(Collectors.joining(",", "[", "]"));
        if (v instanceof Map<?, ?> m) {
            return m.keySet().stream().map(k -> (String) k)
                .sorted((a, b) -> Arrays.compareUnsigned(a.getBytes(StandardCharsets.UTF_8), b.getBytes(StandardCharsets.UTF_8)))
                .map(k -> str(k) + ":" + canon(m.get(k))).collect(Collectors.joining(",", "{", "}"));
        }
        throw new IllegalArgumentException("not written in the canonical form: " + v);
    }

    static String sha(byte[] b) throws Exception {
        return HEX.formatHex(MessageDigest.getInstance("SHA-256").digest(b));
    }

    static Map<String, Object> obj(Object... kv) {
        Map<String, Object> m = new LinkedHashMap<>();
        for (int i = 0; i < kv.length; i += 2) m.put((String) kv[i], kv[i + 1]);
        return m;
    }

    public static void main(String[] args) throws Exception {
        String key = System.getenv("RMBL_KEY");
        if (args.length != 1 || key == null || key.isEmpty()) {
            throw new IllegalArgumentException("usage: RMBL_KEY=... java Capsule.java <capsule dir>");
        }
        Path dir = Path.of(args[0]);
        String utc = System.getenv("RMBL_UTC");
        if (utc == null || utc.isEmpty()) utc = Instant.now().truncatedTo(ChronoUnit.SECONDS).toString();
        String noteFile = System.getenv("RMBL_NOTE_FILE");
        String note = noteFile == null ? "" : Files.readString(Path.of(noteFile), StandardCharsets.UTF_8);
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(key.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
        java.util.function.Function<String, String> hmac =
            m -> HEX.formatHex(mac.doFinal(m.getBytes(StandardCharsets.UTF_8)));

        // 1. the data
        StringBuilder csv = new StringBuilder("x,y\n");
        for (int x = 1; x <= 3; x++) csv.append(x).append(',').append(x * x).append('\n');
        Map<String, Object> data = write(dir, "data.csv", csv.toString());

        // 2. the provenance, pinned to the data
        Map<String, Object> prov = obj(
            "name", "squares",
            "source", obj("url", "https://example.org/squares.csv", "retrieved", utc.substring(0, 10)),
            "resource", obj("filename", "data.csv", "sha256", data.get("sha256"),
                            "size_bytes", data.get("size_bytes"), "row_count_data_rows", 3));
        Map<String, Object> provFile = write(dir, "data_provenance.json", canon(prov) + "\n");

        // 3. the bundle: the files, the empty manifest's digest, and an hmac attestation over both
        List<Object> files = List.of(data, provFile);
        String manifestDigest = sha(canon(obj("meta", List.of(), "results", List.of())).getBytes(StandardCharsets.UTF_8));
        Map<String, Object> inner = obj("meta", obj("files", files, "manifest_digest", manifestDigest, "bundled_utc", utc),
                                        "results", List.of());
        Map<String, Object> att = obj(
            "digest", sha(canon(inner).getBytes(StandardCharsets.UTF_8)), "scheme", "hmac",
            "public", hmac.apply("public"), "context", "", "prehash", "none", "note", note, "signed_utc", utc);
        String signed = sha(canon(att).getBytes(StandardCharsets.UTF_8));
        att.put("signature", obj("scheme", "hmac", "signature", hmac.apply(signed)));
        write(dir, "capsule_bundle.json",
              canon(obj("files", files, "manifest_digest", manifestDigest, "bundled_utc", utc, "attestation", att)) + "\n");
        System.out.println("signed " + dir + " (key id " + att.get("public") + ")");
    }

    static Map<String, Object> write(Path dir, String name, String text) throws Exception {
        byte[] b = text.getBytes(StandardCharsets.UTF_8);
        Files.write(dir.resolve(name), b);
        return obj("path", name, "sha256", sha(b), "size_bytes", b.length);
    }
}
