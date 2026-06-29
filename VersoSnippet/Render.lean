/-
VersoSnippet.Render — the general rendering core: SubVerso `Highlighted` → HTML
(`renderBlock`), the plain (non-literate) block builder, and anchor stripping.
-/
import SubVerso.Module
import SubVerso.Highlighting.Anchors
import Verso.Code.Highlighted
import Verso.Doc.Html
import Verso.Output.Html

open SubVerso.Highlighting (Highlighted)
open SubVerso.Module (Module ModuleItem)
open Verso.Output (Html)
open Verso.Doc (Genre Block Inline)

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
  let asText := fun (it : ModuleItem) =>
    if it.kind == `Lean.Parser.Command.moduleDoc then Highlighted.text it.code.toString
    else it.code
  -- Strip anchors on the whole sequence (single box) so markers that span items
  -- are removed; per box for multi-block.
  let codes : Array Highlighted :=
    if multiBlocks then display.map (fun it => stripAnchors (asText it))
    else #[stripAnchors (Highlighted.seq (nonHeader.map asText))]
  let mut st := st0
  let mut htmls : Array String := #[]
  for code in codes do
    let (h, st') := renderBlock showOutput code st
    st := st'; htmls := htmls.push h.asString
  return (htmls, st)
