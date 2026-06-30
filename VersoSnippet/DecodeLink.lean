/-
DecodeLink — print the Lean source behind a live.lean-lang.org share link
(or read stdin with `-`). Used internally by `lean-snippet link=…`; not meant
to be called directly. A Lean port of the former `decode-link.py`.

Handles the editor's three share formats in the URL fragment:
  #code=…   plain, percent-encoded   (what our own "Try it!" button emits)
  #codez=…  LZ-string compressed
  #url=…    a URL the editor loads the code from (fetched with `curl -sL`)
-/

-- ── LZ-string decoder (decompressFromEncodedURIComponent), no deps ─────────────

/-- The shared 0–61 prefix (`A-Za-z0-9`) plus `+` at 62; index 63 is the alphabet's
    only variable slot — `-` for `decompressFromEncodedURIComponent`, `/` for
    `decompressFromBase64`. -/
def lzKey : String :=
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+-$"

/-- Index of a character in the lz-string alphabet (0 if absent, matching lenient
    decoding). Both `-` (URI-safe) and `/` (base64) map to 63, so either share
    format decodes; `=` base64 padding falls through to 0 (never read). -/
def keyIndex (c : Char) : Nat :=
  if c == '/' then 63 else (lzKey.toList.findIdx? (· == c)).getD 0

/-- The bit-reader state threaded through `readBits`: the 6-bit values, the
    `resetValue` (bit width per input char), and the cursor. -/
structure BitReader where
  data : Array Nat
  resetValue : Nat
  val : Nat
  position : Nat
  index : Nat

/-- Read `log2 maxpower` bits LSB-first from the stream (`maxpower` is a power of
    two: `read(1 << k)` reads `k` bits), mirroring lz-string's `read`. -/
def readBits (maxpower : Nat) : StateM BitReader Nat := do
  let mut bits := 0
  let mut power := 1
  while power != maxpower do
    let st ← get
    let resb := st.val &&& st.position
    let position1 := st.position >>> 1
    if position1 == 0 then
      set { st with position := st.resetValue
                  , val := st.data.getD st.index 0
                  , index := st.index + 1 }
    else
      set { st with position := position1 }
    if resb != 0 then
      bits := bits ||| power
    power := power <<< 1
  return bits

/-- Port of lz-string's `_decompress`: decode `data` (per-char bit values) into
    the original string. `resetValue` is the per-char bit width. -/
def lzDecompress (data : Array Nat) (resetValue : Nat) : String :=
  let length := data.size
  let go : StateM BitReader String := do
    let nxt ← readBits 4
    if nxt == 2 then return ""
    let firstCp ← readBits (if nxt == 0 then 256 else 65536)
    let firstStr := String.singleton (Char.ofNat firstCp)
    -- slots 0,1,2 are sentinels (never read); slot 3 holds the first entry
    let mut dictionary : Array String := #["", "", "", firstStr]
    let mut dictSize := 4
    let mut numBits := 3
    let mut enlargeIn := 4
    let mut w := firstStr
    let mut result := firstStr
    while true do
      if (← get).index > length then return ""
      let mut c ← readBits (1 <<< numBits)
      if c == 0 || c == 1 then
        let cp ← readBits (if c == 0 then 256 else 65536)
        dictionary := dictionary.push (String.singleton (Char.ofNat cp))
        dictSize := dictSize + 1
        c := dictSize - 1
        enlargeIn := enlargeIn - 1
      else if c == 2 then
        return result
      if enlargeIn == 0 then
        enlargeIn := 1 <<< numBits
        numBits := numBits + 1
      if c > dictSize then
        return result      -- malformed; bail with what we have
      let entry := if c == dictSize then w ++ String.singleton w.front
                   else dictionary.getD c ""
      result := result ++ entry
      dictionary := dictionary.push (w ++ String.singleton entry.front)
      dictSize := dictSize + 1
      enlargeIn := enlargeIn - 1
      w := entry
      if enlargeIn == 0 then
        enlargeIn := 1 <<< numBits
        numBits := numBits + 1
    return result
  go.run' { data, resetValue, val := data.getD 0 0, position := resetValue, index := 1 }

/-- Decompress a `#codez=` payload. The editor turns spaces into '+', so undo
    that, then decode against `lzKey` with a 6-bit (`resetValue = 32`) width. -/
def decompressCodez (s : String) : String :=
  let s := s.replace " " "+"
  lzDecompress (s.toList.map keyIndex).toArray 32

-- ── Percent-decoding (`#code=`) ────────────────────────────────────────────────

/-- Value of a single hex digit, if it is one. -/
def hexVal (c : Char) : Option Nat :=
  let n := c.toNat
  if n ≥ 48 ∧ n ≤ 57 then some (n - 48)          -- 0-9
  else if n ≥ 97 ∧ n ≤ 102 then some (n - 87)    -- a-f
  else if n ≥ 65 ∧ n ≤ 70 then some (n - 55)     -- A-F
  else none

/-- Percent-decode `%XX` byte escapes (UTF-8 aware), like `urllib.parse.unquote`.
    A stray `%` not followed by two hex digits is left as-is. `+` is preserved. -/
def percentDecode (s : String) : String :=
  let rec go : List Char → ByteArray → ByteArray
    | '%' :: a :: b :: rest, acc =>
      match hexVal a, hexVal b with
      | some hi, some lo => go rest (acc.push (UInt8.ofNat (hi * 16 + lo)))
      | _, _ => go (a :: b :: rest) (acc ++ (String.singleton '%').toUTF8)
    | c :: rest, acc => go rest (acc ++ (String.singleton c).toUTF8)
    | [], acc => acc
  String.fromUTF8! (go s.toList ByteArray.empty)

-- ── URL fragment parsing (`#url=` / `#code=` / `#codez=`) ──────────────────────

/-- Split `s` on the first occurrence of `sep`. -/
def splitFirst (s sep : String) : Option (String × String) :=
  match s.splitOn sep with
  | a :: b :: rest => some (a, String.intercalate sep (b :: rest))
  | _ => none

/-- Resolve the code behind an `https?://…` share link by inspecting its fragment
    (or query) for `url` / `code` / `codez`, like Python's `code_from_url`. -/
def codeFromUrl (u : String) : IO String := do
  let frag :=
    if (u.splitOn "#").length ≥ 2 then String.intercalate "#" ((u.splitOn "#").drop 1)
    else if (u.splitOn "?").length ≥ 2 then String.intercalate "?" ((u.splitOn "?").drop 1)
    else u
  let mut parts : List (String × String) := []
  for kv in frag.splitOn "&" do
    match splitFirst kv "=" with
    | some (k, v) => parts := parts ++ [(k, v)]
    | none => pure ()
  let lookup := fun key => (parts.find? (·.1 == key)).map (·.2)
  if let some target := lookup "url" then
    IO.Process.run { cmd := "curl", args := #["-sL", "--", percentDecode target] }
  else if let some code := lookup "code" then
    return percentDecode code
  else if let some codez := lookup "codez" then
    -- The fragment may percent-encode base64's `+` / `/` / `=` (e.g. `%2F`), so
    -- undo that before decompressing, matching the editor's `decodeURIComponent`.
    return decompressCodez (percentDecode codez)
  else
    IO.eprintln "decode-link: no #code= / #codez= / #url= found in the URL"
    IO.Process.exit 1

def main (args : List String) : IO UInt32 := do
  let src := args.head?.getD "-"
  let code ←
    if src == "-" then (← IO.getStdin).readToEnd
    else if src.startsWith "http://" || src.startsWith "https://" then codeFromUrl src
    else IO.FS.readFile src
  IO.print code
  return 0
