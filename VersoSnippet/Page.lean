/-
VersoSnippet.Page — assemble the full self-contained HTML page, wiring the general
assets, the Infoview panel, the Literate (math) assets, and the View switcher.
-/
import VersoSnippet.Assets
import VersoSnippet.Literate
import Verso.Code.Highlighted
import Verso.Code.Highlighted.WebAssets

open Verso.Code (highlightingStyle)
open Verso.Code.Highlighted.WebAssets (marked)

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
    -- Each mode flag turns ITS own mode on; with no mode flag at all, every mode
    -- starts on. `--infoview=both` additionally turns hover on.
    let anyModeFlag := slide.isSome || literate
    let initHover := if anyModeFlag then slide == some true else true
    let initSlide := if anyModeFlag then slide.isSome else true
    let initLit := hasLit && (!anyModeFlag || literate)
    let bodyClass :=
      (if initHover then "mode-hover " else "") ++
      (if initLit then "lit-view " else "") ++
      (if initSlide then (if initHover then "slide slide-both" else "slide slide-click") else "")
    let head :=
      "<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n" ++
      "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n" ++
      "<link rel=\"stylesheet\" href=\"https://cdn.jsdelivr.net/npm/sakura.css/css/sakura.css\" type=\"text/css\">\n" ++
      "<style>\nbody { background:#fff; color:#222; max-width:880px; margin:0 auto; padding:1rem 2rem; }\n" ++
      highlightingStyle ++ "\n" ++ labelCss ++ "\n" ++ enhanceCss ++ "\n" ++ panelCss ++ "\n" ++
      (if hasMath && hasLit then katexCss ++ "\n" else "") ++ (if hasLit then proseCss ++ "\n" else "") ++
      switcherCss ++ "\n</style>\n</head>\n" ++
      "<body class=\"" ++ bodyClass.trim ++ "\">\n"
    let cb := fun (val txt : String) (on : Bool) =>
      "<label><input type=\"checkbox\" class=\"mode-cb\" value=\"" ++ val ++ "\"" ++
        (if on then " checked" else "") ++ "> " ++ txt ++ "</label>"
    -- Literate is always offered; if the file has no `/-! … -/` prose it stays
    -- visible but disabled, with a note explaining there's nothing to render.
    let litItem :=
      if hasLit then cb "literate" "Literate" initLit
      else
        "<label class=\"mode-na\" title=\"Literate view isn't needed here — this snippet has no /-! … -/ prose to render.\">" ++
          "<input type=\"checkbox\" class=\"mode-cb\" value=\"literate\" disabled> Literate</label>" ++
          "<div class=\"mode-na-note\">not needed — no prose in this code</div>"
    let dropdown :=
      "<details class=\"mode-switch\"><summary>View</summary><div class=\"mode-menu\">" ++
        cb "hover" "Hover" initHover ++ cb "slide" "Infoview" initSlide ++
        litItem ++ "</div></details>"
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
      (if hasMath && hasLit then "<script>" ++ katexJs ++ "</script>\n<script>" ++ katexMath ++ "</script>\n" else "") ++
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
