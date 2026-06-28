/-
RenderSnippet — read SubVerso's highlighted-module JSON and emit a single,
self-contained HTML snippet using Verso's own rendering library.

Usage: render-snippet <input.json> <output.html> [--multi-blocks] [--no-enhance]

This replaces the old "build a Verso document, then scrape the HTML with Python"
pipeline. The JSON comes from SubVerso's `:highlighted` Lake facet, which drives
the Lean compiler directly — so comments, `#eval` output, and proof states are
all present, and we render them with Verso's library (robust to HTML changes).
-/
import SubVerso.Module
import SubVerso.Highlighting.Anchors
import Verso.Code.Highlighted
import Verso.Code.Highlighted.WebAssets
import Verso.Output.Html

open Lean (Json)
open SubVerso.Highlighting (Highlighted)
open SubVerso.Module (Module ModuleItem)
open Verso.Output (Html)
open Verso.Doc (Genre)
open Verso.Code (highlightingStyle highlightingJs)
open Verso.Code.Highlighted.WebAssets (popper tippy marked)

/-- The trivial genre: its `TraverseContext` is `Unit`, so we can build a
    rendering context with no document around the code. -/
abbrev G : Genre := Genre.none

/-- A rendering context with no links and default options (proof states on). -/
def ctx : Verso.Code.HighlightHtmlM.Context G where
  linkTargets := {}
  traverseContext := ()
  definitionIds := {}
  options := {}

/-- Command kinds that carry no displayable code. -/
def skipKinds : List Lean.Name :=
  [`Lean.Parser.Module.header, `Lean.Parser.Command.eoi]

/-- Render one highlighted fragment to a `<code class="hl lean block">`, threading
    the hover-dedup state so hover ids stay unique across blocks. -/
def renderBlock (code : Highlighted) (st : Verso.Code.Hover.State Html) :
    Html × Verso.Code.Hover.State Html :=
  Id.run <| ((code.blockHtml "snippet").run ctx).run st

-- ── Optional "enhance" layer: GitHub-style colors + copy / Try-it buttons ─────

def enhanceCss : String := "
:root {
  --verso-code-keyword-color: #cf222e;
  --verso-code-const-color:   #0550ae;
  --verso-code-var-color:     #24292f;
  --verso-code-color:         #24292f;
}
code.hl.lean.block {
  background-color: #f6f8fa;
  padding: 1rem;
  border-radius: 8px;
  border: 1px solid #d0d7de;
  position: relative;
  line-height: 1.5;
  font-size: 0.95em;
  margin: 1.5em 0;
  display: block;
  overflow-x: auto;
}
.code-block-actions {
  position: absolute; top: 8px; right: 8px;
  display: flex; flex-direction: row-reverse; gap: 8px; z-index: 10;
  opacity: 0; transition: opacity 0.2s ease;
}
code.hl.lean.block:hover .code-block-actions { opacity: 1; }
.try-it-button, .copy-button {
  display: flex; align-items: center; gap: 4px;
  background: transparent; border: 1px solid #1f2328; border-radius: 6px;
  padding: 3px 10px; font-size: 0.75rem; font-weight: 500; color: #24292f;
  text-decoration: none; font-family: sans-serif; cursor: pointer; white-space: nowrap;
}
.try-it-button:hover, .copy-button:hover {
  border-color: #0969da; color: #0969da; background: #f3f4f6;
}
"

def enhanceJs : String := "
window.addEventListener('load', () => {
  document.querySelectorAll('code.hl.lean.block').forEach(block => {
    const code = block.innerText;
    const actions = document.createElement('div');
    actions.className = 'code-block-actions';
    const copyBtn = document.createElement('button');
    copyBtn.className = 'copy-button'; copyBtn.textContent = 'Copy';
    copyBtn.addEventListener('click', () => {
      navigator.clipboard.writeText(code).then(() => {
        copyBtn.textContent = 'Copied!';
        setTimeout(() => { copyBtn.textContent = 'Copy'; }, 2000);
      });
    });
    const tryBtn = document.createElement('a');
    tryBtn.href = 'https://live.lean-lang.org/#code=' + encodeURIComponent(code);
    tryBtn.target = '_blank'; tryBtn.className = 'try-it-button'; tryBtn.textContent = 'Try it!';
    actions.appendChild(copyBtn); actions.appendChild(tryBtn);
    block.appendChild(actions);
  });
});
"

/-- Assemble the full self-contained HTML page. -/
def page (blocks : String) (docsJson : String) (enhance : Bool) : String :=
  let head :=
    "<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n" ++
    "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n" ++
    "<link rel=\"stylesheet\" href=\"https://cdn.jsdelivr.net/npm/sakura.css/css/sakura.css\" type=\"text/css\">\n" ++
    "<style>\nbody { background:#fff; color:#222; max-width:860px; margin:0 auto; padding:1rem 2rem; }\n" ++
    highlightingStyle ++ "\n" ++ (if enhance then enhanceCss else "") ++ "\n</style>\n</head>\n<body>\n"
  let scripts :=
    "<script>const _versoDocsJson = " ++ docsJson ++ ";</script>\n" ++
    "<script>" ++ popper ++ "</script>\n" ++
    "<script>" ++ tippy ++ "</script>\n" ++
    "<script>" ++ marked ++ "</script>\n" ++
    "<script>\n(function(){\n  const _origFetch = window.fetch;\n" ++
    "  window.fetch = function(url, ...args) {\n" ++
    "    if (typeof url === 'string' && url.endsWith('-verso-docs.json')) {\n" ++
    "      return Promise.resolve(new Response(JSON.stringify(_versoDocsJson)));\n" ++
    "    }\n    return _origFetch.call(this, url, ...args);\n  };\n})();\n</script>\n" ++
    "<script>" ++ highlightingJs ++ "</script>\n" ++
    (if enhance then "<script>" ++ enhanceJs ++ "</script>\n" else "")
  head ++ "<div class=\"lean-snippet\">\n" ++ blocks ++ "\n</div>\n" ++ scripts ++ "</body>\n</html>\n"

def usage : String :=
  "Usage: render-snippet <input.json> <output.html> [--multi-blocks] [--no-enhance] [--anchor NAME]"

/-- Strip `-- ANCHOR:`/`-- ANCHOR_END:` markers from highlighted code, falling
    back to the original on any anchor-parse error. -/
def stripAnchors (hl : Highlighted) : Highlighted :=
  match hl.anchored with
  | .ok a  => a.code
  | .error _ => hl

def main (args : List String) : IO UInt32 := do
  -- Parse: positional input/output, plus flags. `--anchor` takes a value.
  let mut pos : Array String := #[]
  let mut multiBlocks := false
  let mut enhance := true
  let mut anchorName : Option String := none
  let mut rest := args
  while !rest.isEmpty do
    match rest with
    | "--multi-blocks" :: more => multiBlocks := true; rest := more
    | "--no-enhance"   :: more => enhance := false;    rest := more
    | "--anchor" :: name :: more => anchorName := some name; rest := more
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

  -- Determine which highlighted fragments become code blocks.
  let codes : Array Highlighted ←
    match anchorName with
    | some name =>
      -- Show only the named ANCHOR region.
      match (Highlighted.seq (anchorItems.map (·.code))).anchored with
      | .error e => do IO.eprintln s!"render-snippet: anchor error: {e}"; return 1
      | .ok a =>
        match a.anchors[name]? with
        | some hl => pure #[hl]
        | none    => do
          IO.eprintln s!"render-snippet: no anchor named '{name}'"; return 1
    | none =>
      -- One block by default; per-command with --multi-blocks. Markers stripped.
      if multiBlocks then pure (displayItems.map (fun it => stripAnchors it.code))
      else pure #[stripAnchors (Highlighted.seq (anchorItems.map (·.code)))]

  let mut st : Verso.Code.Hover.State Html := {}
  let mut htmls : Array String := #[]
  for code in codes do
    let (h, st') := renderBlock code st
    st := st'
    htmls := htmls.push h.asString

  let blocks := String.intercalate "\n" htmls.toList
  let docsJson := st.dedup.docJson.compress
  IO.FS.writeFile outPath (page blocks docsJson enhance)
  IO.println s!"render-snippet: wrote {htmls.size} block(s) to {outPath}"
  return 0
