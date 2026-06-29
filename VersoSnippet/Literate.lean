/-
VersoSnippet.Literate — the `--literate` feature: `/-! … -/` module docs rendered
as Markdown prose with `$LaTeX$` math (KaTeX, fonts inlined), interleaved with code.
-/
import VersoSnippet.Render
import Verso.Doc.Html
import Verso.Output.Html.KaTeX
import VersoManual.Markdown
import MD4Lean

open SubVerso.Highlighting (Highlighted)
open SubVerso.Module (ModuleItem)
open Verso.Output (Html)
open Verso.Doc (Genre Block Inline)
open Verso.Genre.Manual.Markdown (blockFromMarkdown' strongEmphHeaders' inlineFromMarkdown')

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
