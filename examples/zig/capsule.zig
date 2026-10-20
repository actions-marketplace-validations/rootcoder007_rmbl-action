// A capsule from Zig 0.14: data.csv, data_provenance.json and an hmac-signed capsule_bundle.json,
// with std.crypto and the canonical JSON written by hand (keys in sorted order).
// Usage: RMBL_KEY=... zig run capsule.zig -- <capsule dir>
// RMBL_UTC fixes the time (YYYY-MM-DDThh:mm:ssZ), RMBL_NOTE_FILE names a file holding the note.
const std = @import("std");
const Sha256 = std.crypto.hash.sha2.Sha256;
const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;
const Buf = std.ArrayList(u8);

fn hex(d: [32]u8) [64]u8 {
    const digits = "0123456789abcdef";
    var o: [64]u8 = undefined;
    for (d, 0..) |b, i| {
        o[2 * i] = digits[b >> 4];
        o[2 * i + 1] = digits[b & 15];
    }
    return o;
}
fn sha(m: []const u8) [64]u8 {
    var d: [32]u8 = undefined;
    Sha256.hash(m, &d, .{});
    return hex(d);
}
fn hmac(key: []const u8, m: []const u8) [64]u8 {
    var d: [32]u8 = undefined;
    HmacSha256.create(&d, m, key);
    return hex(d);
}
// a JSON string in the canonical form (docs/bundle-format.md)
fn str(b: *Buf, s: []const u8) !void {
    try b.append('"');
    for (s, 0..) |c, i| {
        switch (c) {
            '"' => try b.appendSlice("\\\""),
            '\\' => try b.appendSlice("\\\\"),
            '\n' => try b.appendSlice("\\n"),
            '\r' => try b.appendSlice("\\r"),
            '\t' => try b.appendSlice("\\t"),
            8 => try b.appendSlice("\\b"),
            12 => try b.appendSlice("\\f"),
            0...7, 11, 14...31 => try b.writer().print("\\u{x:0>4}", .{c}),
            '/' => try b.appendSlice(if (i > 0 and s[i - 1] == '<') "\\/" else "/"),
            else => try b.append(c),
        }
    }
    try b.append('"');
}
// {"path":...,"sha256":...,"size_bytes":...}: the keys in sorted order
fn entry(b: *Buf, name: []const u8, text: []const u8) !void {
    try b.appendSlice("{\"path\":");
    try str(b, name);
    try b.appendSlice(",\"sha256\":");
    try str(b, &sha(text));
    try b.writer().print(",\"size_bytes\":{d}}}", .{text.len});
}
fn put(dir: std.fs.Dir, name: []const u8, text: []const u8) !void {
    try dir.writeFile(.{ .sub_path = name, .data = text });
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const args = try std.process.argsAlloc(a);
    const key = std.process.getEnvVarOwned(a, "RMBL_KEY") catch "";
    if (args.len != 2 or key.len == 0) {
        std.debug.print("usage: RMBL_KEY=... zig run capsule.zig -- <capsule dir>\n", .{});
        std.process.exit(2);
    }
    var dir = try std.fs.cwd().openDir(args[1], .{});
    defer dir.close();
    const utc = std.process.getEnvVarOwned(a, "RMBL_UTC") catch blk: {
        const es = std.time.epoch.EpochSeconds{ .secs = @intCast(std.time.timestamp()) };
        const yd = es.getEpochDay().calculateYearDay();
        const md = yd.calculateMonthDay();
        const ds = es.getDaySeconds();
        break :blk try std.fmt.allocPrint(a, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
            yd.year,                 md.month.numeric(),       md.day_index + 1,
            ds.getHoursIntoDay(), ds.getMinutesIntoHour(), ds.getSecondsIntoMinute(),
        });
    };
    const note = if (std.process.getEnvVarOwned(a, "RMBL_NOTE_FILE")) |f|
        try std.fs.cwd().readFileAlloc(a, f, 1 << 20)
    else |_|
        "";

    // 1. the data
    var csv = Buf.init(a);
    try csv.appendSlice("x,y\n");
    for (1..4) |x| try csv.writer().print("{d},{d}\n", .{ x, x * x });
    try put(dir, "data.csv", csv.items);

    // 2. the provenance, pinned to the data
    var prov = Buf.init(a);
    try prov.appendSlice("{\"name\":\"squares\",\"resource\":{\"filename\":\"data.csv\",\"row_count_data_rows\":3,\"sha256\":");
    try str(&prov, &sha(csv.items));
    try prov.writer().print(",\"size_bytes\":{d}}},\"source\":{{\"retrieved\":", .{csv.items.len});
    try str(&prov, utc[0..10]);
    try prov.appendSlice(",\"url\":\"https://example.org/squares.csv\"}}\n");
    try put(dir, "data_provenance.json", prov.items);

    // 3. the bundle: the files, the empty manifest's digest, and an hmac attestation over both
    var files = Buf.init(a);
    try files.append('[');
    try entry(&files, "data.csv", csv.items);
    try files.append(',');
    try entry(&files, "data_provenance.json", prov.items);
    try files.append(']');
    const mdig = sha("{\"meta\":[],\"results\":[]}");
    var inner = Buf.init(a);
    try inner.appendSlice("{\"meta\":{\"bundled_utc\":");
    try str(&inner, utc);
    try inner.appendSlice(",\"files\":");
    try inner.appendSlice(files.items);
    try inner.appendSlice(",\"manifest_digest\":");
    try str(&inner, &mdig);
    try inner.appendSlice("},\"results\":[]}");
    const kid = hmac(key, "public");
    // the attestation's fields without the signature, sorted; the signature sorts between them
    var head = Buf.init(a);
    try head.appendSlice("\"context\":\"\",\"digest\":");
    try str(&head, &sha(inner.items));
    try head.appendSlice(",\"note\":");
    try str(&head, note);
    try head.appendSlice(",\"prehash\":\"none\",\"public\":");
    try str(&head, &kid);
    try head.appendSlice(",\"scheme\":\"hmac\"");
    var tail = Buf.init(a);
    try tail.appendSlice("\"signed_utc\":");
    try str(&tail, utc);
    const payload = try std.fmt.allocPrint(a, "{{{s},{s}}}", .{ head.items, tail.items });
    const sig = hmac(key, &sha(payload));
    var out = Buf.init(a);
    try out.writer().print("{{\"attestation\":{{{s},\"signature\":{{\"scheme\":\"hmac\",\"signature\":\"{s}\"}},{s}}},\"bundled_utc\":", .{ head.items, &sig, tail.items });
    try str(&out, utc);
    try out.writer().print(",\"files\":{s},\"manifest_digest\":\"{s}\"}}\n", .{ files.items, &mdig });
    try put(dir, "capsule_bundle.json", out.items);
    std.debug.print("signed {s} (key id {s})\n", .{ args[1], &kid });
}
