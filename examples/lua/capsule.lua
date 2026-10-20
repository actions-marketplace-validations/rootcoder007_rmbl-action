-- A capsule from Lua 5.4: data.csv, data_provenance.json and an hmac-signed capsule_bundle.json,
-- with no modules at all: SHA-256 and HMAC (RFC 6234, RFC 2104) in plain Lua 5.4, on its
-- 64-bit integers and bitwise operators, and a small canonical JSON writer.
-- Usage: RMBL_KEY=... lua capsule.lua <capsule dir>  (the directory must exist)
-- RMBL_UTC fixes the time (YYYY-MM-DDThh:mm:ssZ), RMBL_NOTE_FILE names a file holding the note.
local K = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}
local M = 0xffffffff
local function rotr(x, n) return ((x >> n) | (x << (32 - n))) & M end

local function sha256(msg) -- the raw 32-byte digest
  local h = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }
  local len = #msg
  msg = msg .. "\x80" .. string.rep("\0", (55 - len) % 64) .. string.pack(">I8", len * 8)
  for i = 1, #msg, 64 do
    local w = { string.unpack(">" .. string.rep("I4", 16), msg, i) }
    for t = 17, 64 do
      local a, b = w[t - 15], w[t - 2]
      w[t] = (w[t - 16] + (rotr(a, 7) ~ rotr(a, 18) ~ (a >> 3)) + w[t - 7]
              + (rotr(b, 17) ~ rotr(b, 19) ~ (b >> 10))) & M
    end
    local a, b, c, d, e, f, g, hh = table.unpack(h)
    for t = 1, 64 do
      local t1 = (hh + (rotr(e, 6) ~ rotr(e, 11) ~ rotr(e, 25)) + ((e & f) ~ (~e & g)) + K[t] + w[t]) & M
      local t2 = ((rotr(a, 2) ~ rotr(a, 13) ~ rotr(a, 22)) + ((a & b) ~ (a & c) ~ (b & c))) & M
      hh, g, f, e, d, c, b, a = g, f, e, (d + t1) & M, c, b, a, (t1 + t2) & M
    end
    for j, v in ipairs({ a, b, c, d, e, f, g, hh }) do h[j] = (h[j] + v) & M end
  end
  return string.pack(">I4I4I4I4I4I4I4I4", table.unpack(h))
end

local function tohex(s) return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end
local function sha(s) return tohex(sha256(s)) end
local function hmac(key, msg)
  if #key > 64 then key = sha256(key) end
  key = key .. string.rep("\0", 64 - #key)
  local function pad(x) return (key:gsub(".", function(c) return string.char(c:byte() ~ x) end)) end
  return tohex(sha256(pad(0x5c) .. sha256(pad(0x36) .. msg)))
end

-- The canonical form (docs/bundle-format.md). An array is a table made with arr(); every
-- other table is an object, its keys sorted with Lua's string order, which is byte order in
-- the C locale a script starts in.
local ARRAY = {}
local function arr(t) return setmetatable(t, ARRAY) end
local ESC = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
              ['\b'] = '\\b', ['\f'] = '\\f' }
local function str(s)
  s = s:gsub('[%c"\\]', function(c)
    return ESC[c] or (c:byte() < 0x20 and string.format("\\u%04x", c:byte())) or c
  end)
  return '"' .. s:gsub("</", "<\\/") .. '"'
end
local function canon(v)
  if type(v) == "string" then return str(v) end
  if math.type(v) == "integer" then return tostring(v) end
  assert(type(v) == "table", "not written in the canonical form")
  local parts = {}
  if getmetatable(v) == ARRAY then
    for i, x in ipairs(v) do parts[i] = canon(x) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys)
  for i, k in ipairs(keys) do parts[i] = str(k) .. ":" .. canon(v[k]) end
  return "{" .. table.concat(parts, ",") .. "}"
end

local dir, key = arg[1], os.getenv("RMBL_KEY")
assert(dir and key and key ~= "", "usage: RMBL_KEY=... lua capsule.lua <capsule dir>")
local utc = os.getenv("RMBL_UTC")
if not utc or utc == "" then utc = os.date("!%Y-%m-%dT%H:%M:%SZ") end
local note = ""
if os.getenv("RMBL_NOTE_FILE") then
  local f = assert(io.open(os.getenv("RMBL_NOTE_FILE"), "rb"))
  note = f:read("a")
  f:close()
end
local function write(name, text)
  local f = assert(io.open(dir .. "/" .. name, "wb"))
  f:write(text)
  f:close()
  return { path = name, sha256 = sha(text), size_bytes = #text }
end

-- 1. the data
local rows = { "x,y\n" }
for x = 1, 3 do rows[#rows + 1] = string.format("%d,%d\n", x, x * x) end
local data = write("data.csv", table.concat(rows))

-- 2. the provenance, pinned to the data
local prov = {
  name = "squares",
  source = { url = "https://example.org/squares.csv", retrieved = utc:sub(1, 10) },
  resource = { filename = "data.csv", sha256 = data.sha256, size_bytes = data.size_bytes, row_count_data_rows = 3 },
}
local prov_file = write("data_provenance.json", canon(prov) .. "\n")

-- 3. the bundle: the files, the empty manifest's digest, and an hmac attestation over both
local files = arr({ data, prov_file })
local manifest_digest = sha(canon({ meta = arr({}), results = arr({}) }))
local inner = { meta = { files = files, manifest_digest = manifest_digest, bundled_utc = utc }, results = arr({}) }
local att = { digest = sha(canon(inner)), scheme = "hmac", public = hmac(key, "public"), context = "",
              prehash = "none", note = note, signed_utc = utc }
att.signature = { scheme = "hmac", signature = hmac(key, sha(canon(att))) }
write("capsule_bundle.json",
  canon({ files = files, manifest_digest = manifest_digest, bundled_utc = utc, attestation = att }) .. "\n")
print(string.format("signed %s (key id %s)", dir, att.public))
