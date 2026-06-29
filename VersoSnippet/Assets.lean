/-
VersoSnippet.Assets — the inlined CSS/JS embedded into every snippet: GitHub-style
colors + Copy/Try-it, the header bar, the hover stack, plus the vendored Infoview
panel and View-switcher assets (from `web/`).
-/
import Verso.Code.Highlighted
import Verso.Code.Highlighted.WebAssets

open Verso.Code (highlightingJs)
open Verso.Code.Highlighted.WebAssets (popper tippy marked)

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
  margin: 0.8rem 0;
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

/-- Vendored web assets: the Infoview click-to-panel (`panel.*`) and the live
    "View" switcher dropdown (`switcher.*`). -/
def panelJs     : String := include_str "web/panel.js"
def panelCss    : String := include_str "web/panel.css"
def switcherJs  : String := include_str "web/switcher.js"
def switcherCss : String := include_str "web/switcher.css"

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
