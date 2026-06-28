/-
RenderSnippet — read SubVerso's highlighted-module JSON and emit a single,
self-contained HTML snippet using Verso's own rendering library.

Usage: render-snippet <input.json> <output.html> [--multi-blocks] [--no-enhance]
-/
import SubVerso.Module
import SubVerso.Highlighting.Anchors
import Verso.Code.Highlighted
import Verso.Code.Highlighted.WebAssets
import Verso.Output.Html
import Verso.Doc.Html
import Verso.Output.Html.KaTeX
import VersoManual.Markdown
import MD4Lean

open Lean (Json)
open SubVerso.Highlighting (Highlighted)
open SubVerso.Module (Module ModuleItem)
open Verso.Output (Html)
open Verso.Doc (Genre Block Inline)
open Verso.Code (highlightingStyle highlightingJs)
open Verso.Code.Highlighted.WebAssets (popper tippy marked)
open Verso.Genre.Manual.Markdown (blockFromMarkdown' strongEmphHeaders' inlineFromMarkdown')

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

-- ── Literate prose: render `/-! … -/` blocks as Markdown + LaTeX ───────────────

private def trimStr (s : String) : String :=
  let l := s.toList.dropWhile (·.isWhitespace)
  String.ofList (l.reverse.dropWhile (·.isWhitespace) |>.reverse)

private def afterPrefix (s p : String) : String :=
  if s.startsWith p then String.ofList (s.toList.drop p.length) else s

private def beforeSuffix (s p : String) : String :=
  if s.endsWith p then String.ofList (s.toList.take (s.length - p.length)) else s

/-- Strip the `/-! … -/` (or `/-- … -/`) delimiters from a module-doc block. -/
def stripModuleDoc (s : String) : String :=
  let s := trimStr s
  let s := if s.startsWith "/-!" then afterPrefix s "/-!"
           else if s.startsWith "/--" then afterPrefix s "/--"
           else if s.startsWith "/-" then afterPrefix s "/-"
           else s
  let s := if s.endsWith "-/" then beforeSuffix s "-/" else s
  trimStr s

/-- Render a Markdown string (with `$…$` LaTeX) to an HTML string using Verso's
    pure Markdown→AST path on the trivial genre. Headers are emitted as real
    `<hN>` (Genre.none has no header block, so they need handling here); all other
    blocks go through `blockFromMarkdown'` → `Block.toHtml`. -/
def proseHtml (md : String) (st0 : Verso.Code.Hover.State Html) :
    String × Verso.Code.Hover.State Html := Id.run do
  let opts : Verso.Doc.Html.Options Id := { logError := fun _ => pure () }
  match MD4Lean.parse md (MD4Lean.MD_DIALECT_COMMONMARK ||| MD4Lean.MD_FLAG_LATEXMATHSPANS) with
  | none => return ("<pre>" ++ ((md.replace "&" "&amp;").replace "<" "&lt;") ++ "</pre>", st0)
  | some doc =>
    let mut st := st0
    let mut out := ""
    for mb in doc.blocks do
      match mb with
      | .header lvl text =>
        let inls : Array (Inline G) :=
          text.filterMap (fun t => (inlineFromMarkdown' (g := G) t).toOption)
        let (h, st') := (G.toHtml opts () () {} {} {} (Inline.concat inls)).run st
        st := st'
        let n := toString (min (max lvl 1) 6)
        out := out ++ "<h" ++ n ++ ">" ++ h.asString ++ "</h" ++ n ++ ">\n"
      | _ =>
        match blockFromMarkdown' (g := G) mb (handleHeaders := strongEmphHeaders') with
        | .ok b =>
          let (h, st') := (G.toHtml opts () () {} {} {} b).run st
          st := st'; out := out ++ h.asString ++ "\n"
        | .error _ => pure ()
    return (out, st)

/-- A diagnostic message attached to code (e.g. `#eval` output, a warning). -/
abbrev Msg := Highlighted.Span.Kind × Highlighted.MessageContents Highlighted

/-- Pull every diagnostic message out of the tree, returning the code with the
    message-carrying `.span`s flattened to just their code, plus the collected
    messages. Token type-hovers and proof states (`.tactics`) are untouched. -/
partial def extractMessages : Highlighted → Highlighted × Array Msg
  | .span infos content =>
    let (c, ms) := extractMessages content
    (c, ms ++ infos)
  | .seq hls =>
    let (cs, ms) := hls.foldl (init := (#[], #[])) fun (acc : Array Highlighted × Array Msg) h =>
      let (c, m) := extractMessages h
      (acc.1.push c, acc.2 ++ m)
    (.seq cs, ms)
  | .tactics info s e content =>
    let (c, ms) := extractMessages content
    (.tactics info s e c, ms)
  | other => (other, #[])

/-- Walk the tree in render order, deferring each diagnostic message until just
    after the newline that ends its line. Returns the flattened atoms and any
    still-pending messages. This places `#eval`/`#check` output directly under
    the command it belongs to, regardless of how the tree is nested. -/
partial def collectLines : Highlighted → Array Msg → Array Highlighted × Array Msg
  | .seq cs, pending =>
    cs.foldl (init := (#[], pending)) fun (acc : Array Highlighted × Array Msg) c =>
      let (out, p) := collectLines c acc.2
      (acc.1 ++ out, p)
  | .span infos content, pending =>
    let (out, p) := collectLines content pending
    (out, p ++ infos)                              -- defer this command's messages
  | .text s, pending =>
    if s.contains '\n' && !pending.isEmpty then
      (#[.text s] ++ pending.map (fun (k, m) => Highlighted.point k m), #[])
    else
      (#[.text s], pending)
  | .tactics i a b c, pending => (#[.tactics i a b c], pending)  -- keep proof states whole
  | other, pending => (#[other], pending)

/-- With `showOutput`, attach each command's `#eval`/`#check` output on the line
    right below it. Without it, messages are dropped entirely (no hover, no block). -/
def withOutput (showOutput : Bool) (hl : Highlighted) : Highlighted :=
  if !showOutput then
    (extractMessages hl).1
  else
    let (atoms, pending) := collectLines hl #[]
    Highlighted.seq (atoms ++ pending.map (fun (k, m) => Highlighted.point k m))

/-- Render one highlighted fragment to a `<code class="hl lean block">`, threading
    the hover-dedup state so hover ids stay unique across blocks. -/
def renderBlock (showOutput : Bool) (code : Highlighted) (st : Verso.Code.Hover.State Html) :
    Html × Verso.Code.Hover.State Html :=
  Id.run <| (((withOutput showOutput code).blockHtml "snippet").run ctx).run st

-- ── Optional "enhance" layer: GitHub-style colors + copy / Try-it buttons ─────

def enhanceCss : String := "
:root {
  --verso-code-keyword-color: #cf222e;
  --verso-code-const-color:   #0550ae;
  --verso-code-var-color:     #24292f;
  --verso-code-color:         #24292f;
}
/* Comments (Verso gives them no color of their own) — GitHub green. */
code.hl.lean.block .doc-comment,
code.hl.lean.block .inter-text {
  color: #22863a;
  font-style: italic;
}
/* Keep real tokens upright even though inter-text above is italic. */
code.hl.lean.block .token:not(.doc-comment) { font-style: normal; }
/* #eval / #check output etc. — shown as a visible block, not an overlapping hover. */
code.hl.lean.block .verso-message {
  display: block;
  white-space: pre-wrap;
  font-style: normal;
  color: #24292f;
  background: #eef1f5;
  border-left: 0.2rem solid #4777ff;
  padding: 0.2rem 0.6rem;
  margin: 0.3rem 0;
  border-radius: 4px;
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
.snippet-actions button, .snippet-actions a, .snippet-actions summary {
  display: inline-flex; align-items: center; justify-content: center; gap: 4px;
  box-sizing: border-box; height: 1.55rem; padding: 0 16px;
  background: #fff; border: 1px solid #d0d7de; border-radius: 6px;
  font-size: 0.85rem; line-height: 1; font-weight: 500; color: #24292f;
  text-decoration: none; font-family: \"Helvetica Neue\", Arial, sans-serif;
  cursor: pointer; white-space: nowrap; transition: border-color 0.12s, background 0.12s;
}
.snippet-actions button:hover, .snippet-actions a:hover, .snippet-actions summary:hover {
  border-color: #0969da; color: #0969da; background: #f3f4f6;
}
"

def enhanceJs : String := "
window.addEventListener('load', () => {
  const actions = document.querySelector('.snippet-actions');
  if (!actions) return;
  const allBlocks = Array.from(document.querySelectorAll('code.hl.lean.block'));
  if (!allBlocks.length) return;
  // Copy the currently-visible code (the hidden content variant is skipped).
  const codeOf = () => Array.from(document.querySelectorAll('code.hl.lean.block'))
    .filter(b => b.offsetParent !== null).map(b => b.innerText).join('\\n\\n')
    || allBlocks.map(b => b.innerText).join('\\n\\n');
  const copyBtn = document.createElement('button');
  copyBtn.textContent = 'Copy';
  copyBtn.addEventListener('click', () => {
    navigator.clipboard.writeText(codeOf()).then(() => {
      copyBtn.textContent = 'Copied!';
      setTimeout(() => { copyBtn.textContent = 'Copy'; }, 2000);
    });
  });
  const tryBtn = document.createElement('a');
  tryBtn.textContent = 'Try it!'; tryBtn.target = '_blank';
  tryBtn.href = 'https://live.lean-lang.org/#code=' + encodeURIComponent(codeOf());
  tryBtn.addEventListener('click', () => {
    tryBtn.href = 'https://live.lean-lang.org/#code=' + encodeURIComponent(codeOf());
  });
  actions.appendChild(copyBtn); actions.appendChild(tryBtn);
});
"

/-- A permanent header bar above the code: the label (or empty) on the left,
    the Copy / Try-it buttons on the right. -/
def labelCss : String := "
.snippet-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
  font-family: \"Helvetica Neue\", Arial, sans-serif;
  background: #eaeef2;
  border: 1px solid #d0d7de;
  border-bottom: none;
  border-radius: 8px 8px 0 0;
  padding: 3px 12px;
  margin: 1.5em 0 0 0;
}
.snippet-title {
  font-size: 0.9rem;
  font-weight: 600;
  letter-spacing: 0.01em;
  color: #24292f;
}
.snippet-actions {
  display: flex;
  align-items: center;
  gap: 8px;
}
/* The code box joins the header below it: flat top corners, no gap. */
.snippet-header + code.hl.lean.block {
  margin-top: 0;
  border-top-left-radius: 0;
  border-top-right-radius: 0;
}
"

/-- HTML-escape the few characters that matter for a text label. -/
def escapeLabel (s : String) : String :=
  s.replace "&" "&amp;" |>.replace "<" "&lt;" |>.replace ">" "&gt;"

/-- Click-to-panel infoview JS/CSS for `--slide` mode (vendored in `web/`). -/
def panelJs  : String := include_str "web/panel.js"
def panelCss : String := include_str "web/panel.css"
def switcherJs  : String := include_str "web/switcher.js"
def switcherCss : String := include_str "web/switcher.css"

-- ── Literate-mode assets: KaTeX (math) + prose styling ─────────────────────────

private def b64Table : Array Char :=
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".toList.toArray

/-- Standard base64 encoding of a byte array (for inlining fonts as data URIs). -/
def base64 (bytes : ByteArray) : String := Id.run do
  let mut out := ""
  let n := bytes.size
  let mut i := 0
  while i + 3 ≤ n do
    let t := (bytes[i]!.toNat <<< 16) ||| (bytes[i+1]!.toNat <<< 8) ||| bytes[i+2]!.toNat
    out := out.push b64Table[(t >>> 18) &&& 63]!
    out := out.push b64Table[(t >>> 12) &&& 63]!
    out := out.push b64Table[(t >>> 6) &&& 63]!
    out := out.push b64Table[t &&& 63]!
    i := i + 3
  let rem := n - i
  if rem == 1 then
    let t := bytes[i]!.toNat <<< 16
    out := (out.push b64Table[(t >>> 18) &&& 63]!).push b64Table[(t >>> 12) &&& 63]!
    out := out ++ "=="
  else if rem == 2 then
    let t := (bytes[i]!.toNat <<< 16) ||| (bytes[i+1]!.toNat <<< 8)
    out := (out.push b64Table[(t >>> 18) &&& 63]!).push b64Table[(t >>> 12) &&& 63]!
    out := out.push b64Table[(t >>> 6) &&& 63]!
    out := out ++ "="
  return out

/-- Inline KaTeX's woff2 fonts into its CSS as `data:` URIs, so a literate
    snippet with math stays a single self-contained file. -/
def inlineKatexFonts (css : String) : String := Id.run do
  let mut out := css
  for (name, bytes) in Verso.Output.Html.katexFonts do
    if name.endsWith ".woff2" then
      let file := name.replace "katex/fonts/" ""
      out := out.replace ("fonts/" ++ file) ("data:font/woff2;base64," ++ base64 bytes)
  return out

def katexCss  : String := inlineKatexFonts Verso.Output.Html.katex.css
def katexJs   : String := Verso.Output.Html.katex.js
def katexMath : String := Verso.Output.Html.math.js

/-- Styling for the rendered `/-! … -/` Markdown prose blocks. -/
def proseCss : String := "
.prose {
  font-family: \"Helvetica Neue\", \"Segoe UI\", Roboto, Arial, sans-serif;
  line-height: 1.6; margin: 1.4em 0; color: #24292f;
}
.prose > :first-child { margin-top: 0; }
.prose > :last-child { margin-bottom: 0; }
.prose h1, .prose h2, .prose h3 { font-weight: 600; line-height: 1.25; margin: 1.2em 0 0.5em; }
.prose h1 { font-size: 1.6em; } .prose h2 { font-size: 1.3em; } .prose h3 { font-size: 1.1em; }
.prose p { margin: 0.7em 0; }
.prose ul, .prose ol { margin: 0.7em 0; padding-left: 1.5em; }
.prose li { margin: 0.2em 0; }
.prose a { color: #0969da; }
.prose blockquote {
  margin: 0.8em 0; padding: 0.1em 1em; color: #57606a; border-left: 0.25em solid #d0d7de;
}
.prose code {
  background: #eef1f5; border-radius: 4px; padding: 0.1em 0.35em;
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.9em; color: #0550ae;
}
.prose .math.display { display: block; text-align: center; margin: 1em 0; overflow-x: auto; }
"

/-- The hover-tooltip script stack (popper + tippy + the highlighting JS). -/
def hoverScripts : String :=
  "<script>" ++ popper ++ "</script>\n" ++
  "<script>" ++ tippy ++ "</script>\n" ++
  "<script>" ++ marked ++ "</script>\n" ++
  "<script>\n(function(){\n  const _origFetch = window.fetch;\n" ++
  "  window.fetch = function(url, ...args) {\n" ++
  "    if (typeof url === 'string' && url.endsWith('-verso-docs.json')) {\n" ++
  "      return Promise.resolve(new Response(JSON.stringify(_versoDocsJson)));\n" ++
  "    }\n    return _origFetch.call(this, url, ...args);\n  };\n})();\n</script>\n" ++
  "<script>" ++ highlightingJs ++ "</script>\n"

/-- Assemble the full self-contained HTML page. With `switcher`, both content
    variants are embedded and a header dropdown toggles Hover / Click panel /
    Literate live (the flags set the initial state). Otherwise a single mode is
    emitted (`slide`/`literate` decide which). -/
def page (blocks : String) (litBlocks : Option String) (docsJson : String) (enhance : Bool)
    (label : Option String) (slide : Option Bool) (literate : Bool) (switcher : Bool)
    (hasMath : Bool) : String :=
  let titleText := label.map escapeLabel |>.getD ""
  if switcher then
    -- Only embed the literate variant / KaTeX when the file actually has them.
    let hasLit := litBlocks.isSome
    let initHover := slide == none || slide == some true
    let initSlide := slide.isSome
    -- A file with prose starts in the literate (prose) view by default — the raw
    -- `/-! … -/` source isn't the nice view. `--no-switcher` keeps single mode.
    let initLit := hasLit
    let bodyClass :=
      (if initHover then "mode-hover " else "") ++
      (if initLit then "lit-view " else "") ++
      (if initSlide then (if initHover then "slide slide-both" else "slide slide-click") else "")
    let head :=
      "<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n" ++
      "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n" ++
      "<link rel=\"stylesheet\" href=\"https://cdn.jsdelivr.net/npm/sakura.css/css/sakura.css\" type=\"text/css\">\n" ++
      "<style>\nbody { background:#fff; color:#222; max-width:1180px; margin:0 auto; padding:1rem 2rem; }\n" ++
      highlightingStyle ++ "\n" ++ labelCss ++ "\n" ++ enhanceCss ++ "\n" ++ panelCss ++ "\n" ++
      (if hasMath then katexCss ++ "\n" else "") ++ (if hasLit then proseCss ++ "\n" else "") ++
      switcherCss ++ "\n</style>\n</head>\n" ++
      "<body class=\"" ++ bodyClass.trim ++ "\">\n"
    let cb := fun (val txt : String) (on : Bool) =>
      "<label><input type=\"checkbox\" class=\"mode-cb\" value=\"" ++ val ++ "\"" ++
        (if on then " checked" else "") ++ "> " ++ txt ++ "</label>"
    let dropdown :=
      "<details class=\"mode-switch\"><summary>View</summary><div class=\"mode-menu\">" ++
        cb "hover" "Hover" initHover ++ cb "slide" "Infoview" initSlide ++
        (if hasLit then cb "literate" "Literate" initLit else "") ++ "</div></details>"
    let header :=
      "<div class=\"snippet-header\"><span class=\"snippet-title\">" ++ titleText ++
        "</span><span class=\"snippet-actions\">" ++ dropdown ++ "</span></div>\n"
    -- Plain code blocks stay DIRECT children of `.lean-snippet` so the header/panel
    -- CSS (`.snippet-header + code`, `.lean-snippet > code`) keeps working; only the
    -- literate variant is wrapped, shown via `body.lit-view`.
    let snippet :=
      "<div class=\"lean-snippet\">\n" ++ header ++ blocks ++ "\n" ++
        (if hasLit then
          "<div class=\"snippet-content literate\">\n" ++ (litBlocks.getD "") ++ "\n</div>\n"
         else "") ++ "</div>\n"
    let body :=
      "<div class=\"snippet-layout\">\n" ++ snippet ++
        "<div class=\"info-panel-cell\"><aside class=\"info-panel\"></aside></div>\n</div>\n"
    let scripts :=
      "<script>const _versoDocsJson = " ++ docsJson ++ ";</script>\n" ++
      hoverScripts ++
      "<script>" ++ panelJs ++ "</script>\n" ++
      (if hasMath then "<script>" ++ katexJs ++ "</script>\n<script>" ++ katexMath ++ "</script>\n" else "") ++
      "<script>" ++ switcherJs ++ "</script>\n" ++
      (if enhance then "<script>" ++ enhanceJs ++ "</script>\n" else "")
    head ++ body ++ scripts ++ "</body>\n</html>\n"
  else
    let isSlide := slide.isSome
    let both    := slide == some true
    let bodyClass :=
      if isSlide then (if both then "slide slide-both" else "slide slide-click") else ""
    let head :=
      "<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n" ++
      "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n" ++
      "<link rel=\"stylesheet\" href=\"https://cdn.jsdelivr.net/npm/sakura.css/css/sakura.css\" type=\"text/css\">\n" ++
      "<style>\nbody { background:#fff; color:#222; max-width:860px; margin:0 auto; padding:1rem 2rem; }\n" ++
      highlightingStyle ++ "\n" ++ labelCss ++ "\n" ++
      (if enhance then enhanceCss else "") ++ "\n" ++
      (if isSlide then panelCss else "") ++ "\n" ++
      (if literate && hasMath then katexCss ++ "\n" else "") ++
      (if literate then proseCss else "") ++ "\n</style>\n</head>\n" ++
      (if isSlide then "<body class=\"" ++ bodyClass ++ "\">\n" else "<body>\n")
    let headerHtml :=
      if enhance || label.isSome then
        "<div class=\"snippet-header\"><span class=\"snippet-title\">" ++ titleText ++
          "</span><span class=\"snippet-actions\"></span></div>\n"
      else ""
    let snippet := "<div class=\"lean-snippet\">\n" ++ headerHtml ++ blocks ++ "\n</div>\n"
    let body :=
      if isSlide then
        "<div class=\"snippet-layout\">\n" ++ snippet ++
          "<div class=\"info-panel-cell\"><aside class=\"info-panel\"></aside></div>\n</div>\n"
      else snippet
    let scripts :=
      "<script>const _versoDocsJson = " ++ docsJson ++ ";</script>\n" ++
      (if isSlide && !both then "<script>" ++ marked ++ "</script>\n" else hoverScripts) ++
      (if isSlide then "<script>" ++ panelJs ++ "</script>\n" else "") ++
      (if literate && hasMath then "<script>" ++ katexJs ++ "</script>\n<script>" ++ katexMath ++ "</script>\n" else "") ++
      (if enhance then "<script>" ++ enhanceJs ++ "</script>\n" else "")
    head ++ body ++ scripts ++ "</body>\n</html>\n"

def usage : String :=
  "Usage: render-snippet <input.json> <output.html> [--no-switcher] [--multi-blocks] [--no-enhance] [--no-output] [--literate] [--slide|--slide=click|--slide=both] [--anchor NAME] [--label TEXT]"

/-- Strip `-- ANCHOR:`/`-- ANCHOR_END:` markers from highlighted code, falling
    back to the original on any anchor-parse error. -/
def stripAnchors (hl : Highlighted) : Highlighted :=
  match hl.anchored with
  | .ok a  => a.code
  | .error _ => hl

/-- Build the non-literate code blocks (one box, or one per command with
    `multiBlocks`), threading the hover state. Anchors are not applied here. -/
def buildPlainBlocks (items : Array ModuleItem) (showOutput multiBlocks : Bool)
    (st0 : Verso.Code.Hover.State Html) : Array String × Verso.Code.Hover.State Html := Id.run do
  let display := items.filter (fun it => !(skipKinds.contains it.kind))
  let nonHeader := items.filter (fun it => it.kind != `Lean.Parser.Module.header)
  -- `/-! … -/` module docs are highlighted as `unknown` tokens (so they'd show
  -- red/black). In the plain view render them as plain comment text → green.
  let codeFor := fun (it : ModuleItem) =>
    if it.kind == `Lean.Parser.Command.moduleDoc then Highlighted.text it.code.toString
    else stripAnchors it.code
  let codes : Array Highlighted :=
    if multiBlocks then display.map codeFor
    else #[Highlighted.seq (nonHeader.map codeFor)]
  let mut st := st0
  let mut htmls : Array String := #[]
  for code in codes do
    let (h, st') := renderBlock showOutput code st
    st := st'; htmls := htmls.push h.asString
  return (htmls, st)

/-- Build literate blocks: `/-! … -/` module docs → Markdown prose, interleaved
    with code runs in source order. -/
def buildLiterateBlocks (items : Array ModuleItem) (showOutput : Bool)
    (st0 : Verso.Code.Hover.State Html) : Array String × Verso.Code.Hover.State Html := Id.run do
  let mut st := st0
  let mut htmls : Array String := #[]
  let mut run : Array Highlighted := #[]
  for it in items do
    if it.kind == `Lean.Parser.Command.moduleDoc then
      if !run.isEmpty then
        let (h, st') := renderBlock showOutput (Highlighted.seq run) st
        st := st'; htmls := htmls.push h.asString; run := #[]
      let (proseStr, st') := proseHtml (stripModuleDoc it.code.toString) st
      st := st'; htmls := htmls.push ("<div class=\"prose\">\n" ++ proseStr ++ "\n</div>")
    else if !(skipKinds.contains it.kind) then
      run := run.push (stripAnchors it.code)
  if !run.isEmpty then
    let (h, st') := renderBlock showOutput (Highlighted.seq run) st
    st := st'; htmls := htmls.push h.asString
  return (htmls, st)

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
    | "--switcher"     :: more => switcher := true;    rest := more
    | "--no-switcher"  :: more => switcher := false;   rest := more
    | "--slide"        :: more => slide := some false; rest := more
    | "--slide=click"  :: more => slide := some false; rest := more
    | "--slide=both"   :: more => slide := some true;  rest := more
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

  -- `--anchor` focuses a single region, and `--no-enhance` means bare Verso
  -- styling (the switcher's header/colors are themselves enhancements), so both
  -- force single-mode.
  let useSwitcher := switcher && anchorName.isNone && enhance
  -- Literate prose / KaTeX are only worth their bytes when the file uses them.
  let hasProse := mod.items.any (fun it => it.kind == `Lean.Parser.Command.moduleDoc)
  let hasMath := mod.items.any (fun it =>
    it.kind == `Lean.Parser.Command.moduleDoc && it.code.toString.any (· == '$'))

  let mut st : Verso.Code.Hover.State Html := {}
  let mut plainHtmls : Array String := #[]
  let mut litHtmls : Array String := #[]
  let mut haveLit := false

  if useSwitcher then
    -- Render the plain variant always; the literate one only when there is prose
    -- to render differently (otherwise the two are identical — no point doubling).
    let (p, st1) := buildPlainBlocks mod.items showOutput multiBlocks st
    plainHtmls := p; st := st1
    if hasProse then
      let (l, st2) := buildLiterateBlocks mod.items showOutput st
      litHtmls := l; st := st2; haveLit := true
  else if literate then
    let (l, st') := buildLiterateBlocks mod.items showOutput st
    plainHtmls := l; st := st'
  else
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
      let (p, st') := buildPlainBlocks mod.items showOutput multiBlocks st
      plainHtmls := p; st := st'

  let blocks := String.intercalate "\n" plainHtmls.toList
  let litBlocks := if haveLit then some (String.intercalate "\n" litHtmls.toList) else none
  let docsJson := st.dedup.docJson.compress
  let label := labelText.orElse (fun _ => anchorName)
  IO.FS.writeFile outPath
    (page blocks litBlocks docsJson enhance label slide literate useSwitcher hasMath)
  IO.println s!"render-snippet: wrote {plainHtmls.size + litHtmls.size} block(s) to {outPath}"
  return 0
