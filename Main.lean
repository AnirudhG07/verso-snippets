/-
Main — the `render-snippet` executable: parse args, read SubVerso's highlighted
JSON, and write one self-contained HTML file.
-/
import VersoSnippet

open Lean (Json)
open SubVerso.Highlighting (Highlighted)
open SubVerso.Module (Module ModuleItem)
open Verso.Output (Html)

def usage : String :=
  "Usage: render-snippet <input.json> <output.html> [--no-switcher] [--multi-blocks] [--no-enhance] [--no-output] [--literate] [--infoview|--infoview=click|--infoview=both] [--anchor NAME] [--label TEXT]"

def main (args : List String) : IO UInt32 := do
  -- Parse: positional input/output, plus flags. `--anchor` takes a value.
  let mut pos : Array String := #[]
  let mut multiBlocks := false
  let mut enhance := true
  let mut showOutput := true
  -- none = off, some false = click-only, some true = both (click + hover)
  let mut slide : Option Bool := none
  let mut literate := false
  let mut switcher := true   -- the mode switcher is on by default
  let mut anchorName : Option String := none
  let mut labelText : Option String := none
  let mut rest := args
  while !rest.isEmpty do
    match rest with
    | "--multi-blocks" :: more => multiBlocks := true; rest := more
    | "--no-enhance"   :: more => enhance := false;    rest := more
    | "--no-output"    :: more => showOutput := false; rest := more
    | "--literate"     :: more => literate := true;    rest := more
    | "-l"             :: more => literate := true;    rest := more
    | "--switcher"     :: more => switcher := true;    rest := more
    | "--no-switcher"  :: more => switcher := false;   rest := more
    | "--infoview"       :: more => slide := some false; rest := more
    | "--infoview=click" :: more => slide := some false; rest := more
    | "--infoview=both"  :: more => slide := some true;  rest := more
    | "-i"               :: more => slide := some false; rest := more
    | "-i=click"         :: more => slide := some false; rest := more
    | "-i=both"          :: more => slide := some true;  rest := more
    | "--anchor" :: name :: more => anchorName := some name; rest := more
    | "--label"  :: text :: more => labelText := some text; rest := more
    | a :: more =>
      if a.startsWith "--" then
        IO.eprintln s!"Unknown option: {a}"; return 1
      pos := pos.push a; rest := more
    | [] => pure ()
  let (inPath, outPath) ← match pos.toList with
    | [i, o] => pure (i, o)
    | _      => do IO.eprintln usage; return 1

  let raw ← IO.FS.readFile inPath
  let json ← IO.ofExcept (Json.parse raw)
  let mod  ← IO.ofExcept (Module.fromJson? json)

  -- Items shown as code (drop the import header and end-of-input).
  let displayItems := mod.items.filter (fun it => !(skipKinds.contains it.kind))
  -- For anchor parsing, keep everything except the import header: a trailing
  -- `-- ANCHOR_END:` comment attaches to the end-of-input token's trivia.
  let anchorItems := mod.items.filter (fun it => it.kind != `Lean.Parser.Module.header)
  if displayItems.isEmpty then
    IO.eprintln "render-snippet: no displayable code found in input"
    return 1

  -- `--no-enhance` means bare Verso styling (the switcher header/colors are
  -- themselves enhancements), so it forces single-mode. `--anchor` now keeps the
  -- switcher: the region is the Hover/Infoview content, Literate is just disabled.
  let useSwitcher := switcher && enhance
  -- Literate prose / KaTeX are only worth their bytes when the file uses them.
  let hasProse := mod.items.any (fun it => it.kind == `Lean.Parser.Command.moduleDoc)
  let hasMath := mod.items.any (fun it =>
    it.kind == `Lean.Parser.Command.moduleDoc && it.code.toString.any (· == '$'))

  let mut st : Verso.Code.Hover.State Html := {}
  let mut plainHtmls : Array String := #[]
  let mut litHtmls : Array String := #[]
  let mut haveLit := false

  -- The plain content (Hover/Infoview): an anchored region if asked; a literate
  -- interleaving for single-mode `--literate`; otherwise the whole file.
  match anchorName with
  | some name =>
    match (Highlighted.seq (anchorItems.map (·.code))).anchored with
    | .error e => do IO.eprintln s!"render-snippet: anchor error: {e}"; return 1
    | .ok a =>
      match a.anchors[name]? with
      | some hl =>
        let (h, st') := renderBlock showOutput hl st
        st := st'; plainHtmls := #[h.asString]
      | none => do IO.eprintln s!"render-snippet: no anchor named '{name}'"; return 1
  | none =>
    if literate && !useSwitcher then
      let (l, st') := buildLiterateBlocks mod.items showOutput st
      plainHtmls := l; st := st'
    else
      let (p, st') := buildPlainBlocks mod.items showOutput multiBlocks st
      plainHtmls := p; st := st'

  -- The literate variant for the switcher: only with prose, and not for an
  -- anchored region (which carries no `/-! … -/` prose of its own).
  if useSwitcher && hasProse && anchorName.isNone then
    let (l, st') := buildLiterateBlocks mod.items showOutput st
    litHtmls := l; st := st'; haveLit := true

  let blocks := String.intercalate "\n" plainHtmls.toList
  let litBlocks := if haveLit then some (String.intercalate "\n" litHtmls.toList) else none
  let docsJson := st.dedup.docJson.compress
  let label := labelText.orElse (fun _ => anchorName)
  IO.FS.writeFile outPath
    (page blocks litBlocks docsJson enhance label slide literate useSwitcher hasMath)
  IO.println s!"render-snippet: wrote {plainHtmls.size + litHtmls.size} block(s) to {outPath}"
  return 0
