import Std

/-!
WrapLean: converts a plain `.lean` file into a minimal Verso `#doc` page.

Prints the Verso-format page to stdout.
Writes `selected.json` alongside the input file.

Usage: wrap-lean <input.lean>
-/

-- ── Line classifiers ──────────────────────────────────────────────────────────

private def isWordChar (c : Char) : Bool := c.isAlphanum || c == '_'

/-- Matches `\s*--\s*<marker>\b` against a line. -/
private def matchesMarker (line marker : String) : Bool :=
  let t := line.trim
  if !t.startsWith "--" then false
  else
    let core := (t.drop 2).trimLeft
    core.startsWith marker &&
      (core.length == marker.length ||
       !isWordChar (core.get ⟨marker.utf8ByteSize⟩))

private def isShowStart    (l : String) : Bool := matchesMarker l "#show"
private def isShowEnd      (l : String) : Bool := matchesMarker l "#endshow"

private def isImportLine   (l : String) : Bool :=
  let t := l.trimLeft
  (t.startsWith "import " || t.startsWith "import\t") && t.length > 7

private def isHintLine     (l : String) : Bool :=
  l.trimLeft.startsWith "-- Write your Lean code"

/-- A `-- comment` line that is not a `#show`/`#endshow` marker. -/
private def isPlainComment (l : String) : Bool :=
  l.trimLeft.startsWith "--" && !isShowStart l && !isShowEnd l

private def isDeclStart    (l : String) : Bool :=
  let t := l.trimLeft
  ["@[", "private ", "protected ", "noncomputable ",
   "def ", "theorem ", "lemma ", "structure ", "class ",
   "instance ", "inductive ", "coinductive ", "abbrev ",
   "opaque ", "axiom "].any t.startsWith

/-- Net change in `/-`…`-/` block-comment depth across one line. -/
private def depthChange (line : String) : Int :=
  let rec go : List Char → Int → Int
    | '/' :: '-' :: rest, d => go rest (d + 1)
    | '-' :: '/' :: rest, d => go rest (d - 1)
    | _ :: rest,          d => go rest d
    | [],                 d => d
  go line.toList 0

/-- Strip `--` and surrounding whitespace from a comment line. -/
private def commentText (line : String) : String :=
  (line.trimLeft.drop 2).trim

-- ── Comment preprocessing ─────────────────────────────────────────────────────

/--
Rewrite runs of `-- text` lines that sit immediately before a Lean declaration
into `/-- text -/` doc comments.  Lean's elaborator preserves those in the
hover data Verso renders; plain `--` lines are silently dropped.
-/
private def preprocessComments (code : String) : String :=
  let lines := code.splitOn "\n" |>.toArray
  let mut result : Array String := #[]
  let mut i := 0
  while i < lines.size do
    let line := lines[i]!
    if isPlainComment line then
      let runStart := i
      let mut texts : Array String := #[]
      while i < lines.size && isPlainComment lines[i]! do
        texts := texts.push (commentText lines[i]!)
        i += 1
      -- Peek past blank lines for a declaration
      let mut k := i
      while k < lines.size && lines[k]!.trim.isEmpty do
        k += 1
      if k < lines.size && isDeclStart lines[k]! then
        let body := String.intercalate " " (texts.toList.filter (· != ""))
        result := result.push s!"/-- {body} -/"
      else
        for j in [runStart:i] do
          result := result.push lines[j]!
    else
      result := result.push line
      i += 1
  String.intercalate "\n" result.toList

-- ── JSON ─────────────────────────────────────────────────────────────────────

private def jsonNatList (xs : List Nat) : String :=
  "[" ++ String.intercalate ", " (xs.map toString) ++ "]"

private def buildJson
    (selected : Array Nat) (groups : Array (Array Nat)) (hasMarkers : Bool) : String :=
  let sel  := jsonNatList selected.toList
  let grps := "[" ++ String.intercalate ", "
                (groups.toList.map (jsonNatList ·.toList)) ++ "]"
  let hm   := if hasMarkers then "true" else "false"
  -- avoid s! brace ambiguity with explicit concatenation
  "{\"selected\": " ++ sel ++ ", \"groups\": " ++ grps ++
    ", \"has_markers\": " ++ hm ++ "}"

-- ── Main ──────────────────────────────────────────────────────────────────────

def main (args : List String) : IO Unit := do
  let path ← match args with
    | p :: _ => pure p
    | []     => do IO.eprintln "Usage: wrap-lean <input.lean>"; IO.Process.exit 1

  let src ← IO.FS.readFile path

  -- ── Pass 1: chunk splitting ────────────────────────────────────────────────
  -- chunks: (text, Option groupId)  — None means hidden (outside #show)
  let mut chunks  : Array (String × Option Nat) := #[]
  let mut imports : Array String := #[]
  let mut current : Array String := #[]
  let mut inShow     := false
  let mut hasMarkers := false
  let mut depth      : Int := 0
  let mut groupId    : Nat := 0

  -- Flush `current` into `chunks` and reset it.
  let flushCurrent (ch : Array (String × Option Nat)) (cur : Array String)
      (inSh : Bool) (gid : Nat) : Array (String × Option Nat) × Array String :=
    if cur.any (·.trim.length > 0) then
      (ch.push (String.intercalate "\n" cur.toList, if inSh then some gid else none), #[])
    else
      (ch, #[])

  for line in src.splitOn "\n" do
    if isShowStart line then
      (chunks, current) := flushCurrent chunks current inShow groupId
      hasMarkers := true
      groupId    := groupId + 1
      inShow     := true
      depth      := 0
    else if isShowEnd line then
      (chunks, current) := flushCurrent chunks current inShow groupId
      inShow := false
      depth  := 0
    else if isImportLine line && depth == 0 then
      imports := imports.push line.trim
    else
      depth := depth + depthChange line
      if line.trim.isEmpty && depth ≤ 0 then
        if inShow then
          current := current.push ""        -- preserve blanks inside #show
        else
          (chunks, current) := flushCurrent chunks current inShow groupId
      else if !isHintLine line then
        current := current.push line

  (chunks, _) := flushCurrent chunks current inShow groupId

  -- Drop empty chunks (text is all whitespace)
  chunks := chunks.filter fun (c, _) => c.trim.length > 0

  -- No markers → show everything as one group
  if !hasMarkers then
    chunks := chunks.map fun (c, _) => (c, some 1)

  -- ── Build selected / groups ───────────────────────────────────────────────
  let mut selected : Array Nat := #[]
  let mut groupMap : Std.HashMap Nat (Array Nat) := {}

  for (i, (_, g)) in chunks.toList.enum do
    if let some gid := g then
      selected := selected.push i
      groupMap := groupMap.insert gid
        ((groupMap.find? gid |>.getD #[]).push i)

  let sortedKeys  := (groupMap.toList.map Prod.fst).toArray.qsort (· < ·)
  let groups      := sortedKeys.map fun k => groupMap.find? k |>.getD #[]

  -- ── Write selected.json alongside the input file ──────────────────────────
  let dir := (System.FilePath.mk path).parent |>.getD (System.FilePath.mk ".")
  IO.FS.writeFile (dir / "selected.json") (buildJson selected groups hasMarkers)

  -- ── Emit Snippet.lean ─────────────────────────────────────────────────────
  let importsStr :=
    if imports.isEmpty then ""
    else String.intercalate "\n" imports.toList ++ "\n"

  let header :=
    "import VersoBlog\n" ++ importsStr ++
    "open Verso Genre Blog\n\n" ++
    "#doc (Page) \"Scratch\" =>\n" ++
    "%%%\n%%%\n\n" ++
    "```leanInit scratch\n```\n"

  let blocks := chunks.toList.map fun (code, g) =>
    let processed := if g.isSome then preprocessComments code else code
    "```lean scratch\n" ++ processed ++ "\n```"

  IO.print (header ++ String.intercalate "\n\n" blocks ++ "\n")
