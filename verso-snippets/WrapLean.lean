/-!
WrapLean: converts a plain `.lean` file into a minimal Verso `#doc` page.

Prints the Verso-format page to stdout and writes `selected.json` alongside
the input file (recording which blocks are inside `#show` regions).

Usage: wrap-lean <input.lean>

Splitting rules (mirrors the original `wrap_lean.py`):
  - Outside `#show` regions: blank lines separate chunks.
  - Inside `#show`/`#endshow`: blank lines are preserved (one block per region).
  - `import` lines are hoisted into the page header.
  - A run of `-- comment` lines immediately before a declaration becomes a
    `/-- doc comment -/`, which survives elaboration and shows in the output.
-/

-- ── String helpers (stable across the Lean 4.29 String/Slice overhaul) ────────

private def ltrim (s : String) : String :=
  String.ofList (s.toList.dropWhile (·.isWhitespace))

private def rtrim (s : String) : String :=
  String.ofList (s.toList.reverse.dropWhile (·.isWhitespace)).reverse

private def trimS (s : String) : String := rtrim (ltrim s)

private def hasPrefix (s pre : String) : Bool :=
  pre.toList.isPrefixOf s.toList

private def dropN (s : String) (n : Nat) : String :=
  String.ofList (s.toList.drop n)

private def isBlank (s : String) : Bool :=
  s.toList.all (·.isWhitespace)

/-- A chunk with no Lean command: every line is blank or a `--` line comment.
    Verso cannot elaborate such a block (it parses to no command and errors on
    EOF), and there is nothing to render, so these are dropped. -/
private def isLineCommentOnly (chunk : String) : Bool :=
  chunk.splitOn "\n" |>.all (fun l => isBlank l || hasPrefix (ltrim l) "--")

-- ── Line classifiers ──────────────────────────────────────────────────────────

private def isWordChar (c : Char) : Bool := c.isAlphanum || c == '_'

/-- Matches `\s*--\s*<marker>` with a word boundary after the marker. -/
private def matchesMarker (line marker : String) : Bool :=
  let t := trimS line
  if !hasPrefix t "--" then false
  else
    let core := (ltrim (dropN t 2)).toList
    let m    := marker.toList
    m.isPrefixOf core &&
      (match core.drop m.length with
       | []     => true
       | c :: _ => !isWordChar c)

private def isShowStart (l : String) : Bool := matchesMarker l "#show"
private def isShowEnd   (l : String) : Bool := matchesMarker l "#endshow"

private def isImportLine (l : String) : Bool :=
  let t := ltrim l
  hasPrefix t "import " || hasPrefix t "import\t"

private def isHintLine (l : String) : Bool :=
  hasPrefix (ltrim l) "-- Write your Lean code"

/-- A `-- comment` line that is not a `#show`/`#endshow` marker. -/
private def isPlainComment (l : String) : Bool :=
  hasPrefix (ltrim l) "--" && !isShowStart l && !isShowEnd l

private def isDeclStart (l : String) : Bool :=
  let t := ltrim l
  ["@[", "private ", "protected ", "noncomputable ",
   "def ", "theorem ", "lemma ", "structure ", "class ",
   "instance ", "inductive ", "coinductive ", "abbrev ",
   "opaque ", "axiom "].any (hasPrefix t ·)

/-- Net change in `/-`…`-/` block-comment depth across one line. -/
private def depthChange (line : String) : Int :=
  let rec go : List Char → Int → Int
    | '/' :: '-' :: rest, d => go rest (d + 1)
    | '-' :: '/' :: rest, d => go rest (d - 1)
    | _ :: rest,          d => go rest d
    | [],                 d => d
  go line.toList 0

/-- Strip the `--` leader and surrounding whitespace from a comment line. -/
private def commentText (line : String) : String :=
  trimS (dropN (ltrim line) 2)

-- ── Comment preprocessing ─────────────────────────────────────────────────────

/--
Rewrite runs of `-- text` lines immediately before a declaration into
`/-- text -/` doc comments; Lean's elaborator preserves those in hover data.
-/
private def preprocessComments (code : String) : String := Id.run do
  let lines := code.splitOn "\n" |>.toArray
  let mut result : Array String := #[]
  let mut i := 0
  while i < lines.size do
    if isPlainComment lines[i]! then
      let runStart := i
      let mut texts : Array String := #[]
      while i < lines.size && isPlainComment lines[i]! do
        texts := texts.push (commentText lines[i]!)
        i := i + 1
      -- Peek past blank lines for a declaration
      let mut k := i
      while k < lines.size && isBlank lines[k]! do
        k := k + 1
      if k < lines.size && isDeclStart lines[k]! then
        let body := String.intercalate " " (texts.toList.filter (· != ""))
        result := result.push s!"/-- {body} -/"
      else
        for j in [runStart:i] do
          result := result.push lines[j]!
    else
      result := result.push lines[i]!
      i := i + 1
  return String.intercalate "\n" result.toList

-- ── JSON ─────────────────────────────────────────────────────────────────────

private def jsonNatList (xs : List Nat) : String :=
  "[" ++ String.intercalate ", " (xs.map toString) ++ "]"

private def buildJson
    (selected : Array Nat) (groups : Array (Array Nat)) (hasMarkers : Bool) : String :=
  let sel  := jsonNatList selected.toList
  let grps := "[" ++ String.intercalate ", "
                (groups.toList.map (fun g => jsonNatList g.toList)) ++ "]"
  let hm   := if hasMarkers then "true" else "false"
  "{\"selected\": " ++ sel ++ ", \"groups\": " ++ grps ++
    ", \"has_markers\": " ++ hm ++ "}"

-- ── Main ──────────────────────────────────────────────────────────────────────

def main (args : List String) : IO Unit := do
  let path ← match args with
    | p :: _ => pure p
    | []     => do IO.eprintln "Usage: wrap-lean <input.lean>"; IO.Process.exit 1

  let src ← IO.FS.readFile path

  -- ── Pass 1: chunk splitting ────────────────────────────────────────────────
  -- A chunk is (text, group?) where group? = none means hidden (outside #show).
  let mut chunks  : Array (String × Option Nat) := #[]
  let mut imports : Array String := #[]
  let mut current : Array String := #[]
  let mut inShow     := false
  let mut hasMarkers := false
  let mut depth      : Int := 0
  let mut groupId    : Nat := 0

  -- Pure helper: append `current` to `chunks` if it holds any real content.
  let pushChunk := fun (ch : Array (String × Option Nat)) (cur : Array String)
      (inSh : Bool) (gid : Nat) =>
    if cur.any (fun l => !isBlank l) then
      ch.push (String.intercalate "\n" cur.toList, if inSh then some gid else none)
    else
      ch

  for line in src.splitOn "\n" do
    if isShowStart line then
      chunks := pushChunk chunks current inShow groupId
      current := #[]
      hasMarkers := true
      groupId := groupId + 1
      inShow := true
      depth := 0
    else if isShowEnd line then
      chunks := pushChunk chunks current inShow groupId
      current := #[]
      inShow := false
      depth := 0
    else if isImportLine line && depth == 0 then
      imports := imports.push (trimS line)
    else
      depth := depth + depthChange line
      if isBlank line && depth ≤ 0 then
        if inShow then
          current := current.push ""        -- preserve blanks inside #show
        else
          chunks := pushChunk chunks current inShow groupId
          current := #[]
      else if !isHintLine line then
        current := current.push line

  chunks := pushChunk chunks current inShow groupId

  -- Drop chunks with no elaborable content (blank or pure `--` comments)
  chunks := chunks.filter (fun c => !isLineCommentOnly c.1)

  -- No markers → show everything as a single group
  if !hasMarkers then
    chunks := chunks.map (fun c => (c.1, some 1))

  -- ── selected indices + groups ─────────────────────────────────────────────
  let mut selected : Array Nat := #[]
  for i in [0:chunks.size] do
    if (chunks[i]!).2.isSome then
      selected := selected.push i

  let maxGid := chunks.foldl (init := 0) fun acc c =>
    match c.2 with
    | some k => Nat.max acc k
    | none   => acc

  let groups : Array (Array Nat) := Id.run do
    let mut gs : Array (Array Nat) := #[]
    for gid in [1:maxGid+1] do
      let mut bucket : Array Nat := #[]
      for i in [0:chunks.size] do
        if (chunks[i]!).2 == some gid then
          bucket := bucket.push i
      if bucket.size > 0 then
        gs := gs.push bucket
    return gs

  -- ── Write selected.json alongside the input file ──────────────────────────
  let dir := (System.FilePath.mk path).parent |>.getD (System.FilePath.mk ".")
  IO.FS.writeFile (dir / "selected.json") (buildJson selected groups hasMarkers)

  -- ── Emit Snippet.lean to stdout ───────────────────────────────────────────
  let importsStr :=
    if imports.isEmpty then ""
    else String.intercalate "\n" imports.toList ++ "\n"

  let header :=
    "import VersoBlog\n" ++ importsStr ++
    "open Verso Genre Blog\n\n" ++
    "#doc (Page) \"Scratch\" =>\n" ++
    "%%%\n%%%\n\n" ++
    "```leanInit scratch\n```\n"

  let blocks := chunks.toList.map fun c =>
    let processed := if c.2.isSome then preprocessComments c.1 else c.1
    "```lean scratch\n" ++ processed ++ "\n```"

  IO.print (header ++ String.intercalate "\n\n" blocks ++ "\n")
