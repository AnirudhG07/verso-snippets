#!/usr/bin/env python3
"""
Extract Lean code blocks from a Verso-generated HTML page into a
self-contained HTML snippet (with hover tooltips and binding highlights).

Usage:
  python3 extract_lean.py <generated-index.html> [options]

Options:
  --index N       Extract the N-th block (0-based). Default: all blocks.
  --match TEXT    Extract blocks whose plain text contains TEXT.
  --out FILE      Output file. Default: demo.html
  --list          List all blocks with their indices and plain text.
  --no-enhance    Skip GitHub-style colors, copy button, and Try-it button.
"""

import argparse
import os
import re
import sys


# ---------------------------------------------------------------------------
# Tag-depth-balanced extraction from raw HTML source
# ---------------------------------------------------------------------------

def extract_tag_contents(source: str, open_pattern: re.Pattern, tag: str) -> list[str]:
    """Find every match of open_pattern and extract it to its balanced closing tag."""
    close_tag = f'</{tag}>'
    open_re = re.compile(rf'<{tag}(?:\s[^>]*)?>',  re.IGNORECASE)
    results = []
    start = 0
    while True:
        m = open_pattern.search(source, start)
        if not m:
            break
        pos = m.start()
        depth = 1
        scan = pos + len(m.group(0))
        while depth > 0:
            next_open = open_re.search(source, scan)
            next_close_idx = source.find(close_tag, scan)
            if next_close_idx == -1:
                depth = 0
                scan = len(source)
                break
            next_open_idx = next_open.start() if next_open else len(source)
            if next_open_idx < next_close_idx:
                depth += 1
                scan = next_open_idx + len(next_open.group(0))
            else:
                depth -= 1
                scan = next_close_idx + len(close_tag)
        results.append(source[pos:scan])
        start = scan
    return results


def extract_style_blocks(source: str) -> list[str]:
    blocks = extract_tag_contents(source, re.compile(r'<style\b[^>]*>', re.IGNORECASE), 'style')
    result = []
    for b in blocks:
        inner = re.sub(r'^<style[^>]*>', '', b, count=1)
        inner = re.sub(r'</style>$', '', inner)
        result.append(inner)
    return result


def extract_inline_scripts(source: str) -> list[str]:
    all_blocks = extract_tag_contents(source, re.compile(r'<script\b[^>]*>', re.IGNORECASE), 'script')
    result = []
    for b in all_blocks:
        open_tag = re.match(r'<script\b[^>]*>', b, re.IGNORECASE)
        if open_tag and 'src=' in open_tag.group(0):
            continue
        inner = re.sub(r'^<script[^>]*>', '', b, count=1)
        inner = re.sub(r'</script>$', '', inner)
        result.append(inner)
    return result


def extract_lean_blocks(source: str) -> list[str]:
    pattern = re.compile(r'<code\b[^>]*class="[^"]*\bhl\b[^"]*\blean\b[^"]*\bblock\b[^"]*"[^>]*>', re.IGNORECASE)
    return extract_tag_contents(source, pattern, 'code')


# ---------------------------------------------------------------------------
# Plain-text extraction
# ---------------------------------------------------------------------------

def strip_tags(html: str) -> str:
    text = re.sub(r'<[^>]+>', '', html)
    text = text.replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>') \
               .replace('&quot;', '"').replace('&#39;', "'").replace('&nbsp;', ' ')
    return text


# ---------------------------------------------------------------------------
# Pair each code block with its optional lean-output block
# ---------------------------------------------------------------------------

def extract_blocks_with_output(source: str, lean_blocks: list[str]) -> list[tuple[str, str]]:
    results = []
    for block_html in lean_blocks:
        idx = source.find(block_html)
        if idx == -1:
            results.append((block_html, ''))
            continue
        after = source[idx + len(block_html):]
        m = re.match(r'\s*(<pre\s[^>]*class="[^"]*lean-output[^"]*"[^>]*>.*?</pre>)', after, re.DOTALL)
        output_html = m.group(1) if m else ''
        results.append((block_html, output_html))
    return results


# ---------------------------------------------------------------------------
# Enhancement: GitHub-style colors + Copy + Try it! (from see.lean)
# ---------------------------------------------------------------------------

ENHANCE_CSS = """
/* ── GitHub-style syntax colors (from see.lean) ── */
:root {
  --verso-code-keyword-color: #cf222e;
  --verso-code-const-color:   #0550ae;
  --verso-code-var-color:     #24292f;
  --verso-code-color:         #24292f;
}

/* Code block container */
code.hl.lean.block {
  background-color: #f6f8fa;
  padding: 1rem;
  border-radius: 8px;
  border: 1px solid #d0d7de;
  position: relative;
  line-height: 1.45;
  font-size: 0.95em;
  margin: 1.5em 0;
  display: block;
  /* inter-text (whitespace + comments) in muted green */
  color: #22863a;
  font-style: italic;
}

/* Tokens override the block's italic/green defaults */
code.hl.lean.block .token {
  font-style: normal !important;
}
code.hl.lean.block .keyword {
  color: #cf222e !important;
}
code.hl.lean.block .const {
  color: #0550ae !important;
}
code.hl.lean.block .var {
  color: #24292f !important;
}
code.hl.lean.block .literal.string {
  color: #0a3069 !important;
}
code.hl.lean.block .sort {
  color: #953800 !important;
  font-weight: 600 !important;
}

/* ── Action buttons (Copy / Try it!) ── */
.code-block-actions {
  position: absolute;
  top: 8px;
  right: 8px;
  display: flex;
  flex-direction: row-reverse;
  gap: 8px;
  z-index: 10;
  opacity: 0;
  transition: opacity 0.2s ease;
}
code.hl.lean.block:hover .code-block-actions {
  opacity: 1;
}
.try-it-button, .copy-button {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 4px;
  background-color: transparent !important;
  border: 1px solid #1f2328 !important;
  border-radius: 6px;
  padding: 3px 10px;
  font-size: 0.75rem;
  font-weight: 500;
  color: #24292f !important;
  font-style: normal !important;
  text-decoration: none;
  font-family: sans-serif;
  transition: all 0.2s ease;
  cursor: pointer;
  white-space: nowrap;
}
.copy-button { padding: 3px 6px; }
.try-it-button svg, .copy-button svg {
  fill: none !important;
  stroke: currentColor;
}
.try-it-button:hover, .copy-button:hover {
  background-color: #f3f4f6 !important;
  border-color: #0969da !important;
  color: #0969da !important;
}
"""

ENHANCE_JS = """
window.addEventListener('load', () => {
  const COPY_ICON = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="pointer-events:none"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>';
  const CHECK_ICON = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>';
  const PLAY_ICON  = '<svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor" stroke="none" style="pointer-events:none"><path d="M8 5v14l11-7z"/></svg>';

  document.querySelectorAll('code.hl.lean.block').forEach(block => {
    const code = block.innerText;
    const actions = document.createElement('div');
    actions.className = 'code-block-actions';

    // Copy button
    const copyBtn = document.createElement('button');
    copyBtn.className = 'copy-button';
    copyBtn.title = 'Copy to clipboard';
    copyBtn.innerHTML = COPY_ICON;
    copyBtn.addEventListener('click', () => {
      navigator.clipboard.writeText(code).then(() => {
        copyBtn.innerHTML = CHECK_ICON;
        setTimeout(() => { copyBtn.innerHTML = COPY_ICON; }, 2000);
      });
    });

    // Try it! button — opens live.lean-lang.org
    const header = 'import Lean\\nopen Lean Meta Elab Tactic Term Command\\n\\n';
    const tryBtn = document.createElement('a');
    tryBtn.href = 'https://live.lean-lang.org/#code=' + encodeURIComponent(header + code);
    tryBtn.target = '_blank';
    tryBtn.className = 'try-it-button';
    tryBtn.title = 'Open in Lean 4 Web Editor';
    tryBtn.innerHTML = PLAY_ICON + '<span>Try it!</span>';

    actions.appendChild(copyBtn);
    actions.appendChild(tryBtn);
    block.appendChild(actions);
  });
});
"""


# ---------------------------------------------------------------------------
# Build self-contained HTML
# ---------------------------------------------------------------------------

SNIPPET_TEMPLATE = """\
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/sakura.css/css/sakura.css" type="text/css">
<style>
body {{
  background: #fff;
  color: #222;
  padding: 1rem 2rem;
  max-width: 860px;
  margin: 0 auto;
}}
.lean-snippet {{ font-family: monospace; }}
{css}
{enhance_css}
</style>
</head>
<body>
<div class="lean-snippet">
{blocks}
</div>
<script>const _versoDocsJson = {docs_json};</script>
<script src="{verso_data}/popper.js"></script>
<script src="{verso_data}/tippy.js"></script>
<script src="https://cdn.jsdelivr.net/npm/marked@11.1.1/marked.min.js"
        integrity="sha384-zbcZAIxlvJtNE3Dp5nxLXdXtXyxwOdnILY1TDPVmKFhl4r4nSUG1r8bcFXGVa4Te"
        crossorigin="anonymous"></script>
<script>
const _origFetch = window.fetch;
window.fetch = function(url, ...args) {{
  if (typeof url === 'string' && url.endsWith('-verso-docs.json')) {{
    return Promise.resolve(new Response(JSON.stringify(_versoDocsJson)));
  }}
  return _origFetch.call(this, url, ...args);
}};
{scripts}
</script>
{enhance_js}
</body>
</html>
"""


def build_html(
    css_blocks: list[str],
    script_blocks: list[str],
    selected_pairs: list[tuple[str, str]],
    docs_json_str: str,
    verso_data_path: str,
    enhance: bool = True,
) -> str:
    css = '\n'.join(css_blocks)

    blocks_parts = []
    for code_html, output_html in selected_pairs:
        parts = [code_html]
        if output_html:
            parts.append(output_html)
        blocks_parts.append('\n'.join(parts))
    blocks_html = '\n\n'.join(blocks_parts)

    combined_scripts = '\n\n'.join(
        s for s in script_blocks
        if 'querySelector' in s or 'tippy' in s.lower() or 'onload' in s.lower()
    )

    return SNIPPET_TEMPLATE.format(
        css=css,
        enhance_css=ENHANCE_CSS if enhance else '',
        blocks=blocks_html,
        docs_json=docs_json_str,
        scripts=combined_scripts,
        verso_data=verso_data_path,
        enhance_js=f'<script>{ENHANCE_JS}</script>' if enhance else '',
    )


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description='Extract Lean code blocks from Verso HTML')
    parser.add_argument('html_file', help='Path to the generated index.html')
    parser.add_argument('--index', type=int, default=None,
                        help='Extract block at this 0-based index')
    parser.add_argument('--match', type=str, default=None,
                        help='Extract blocks whose plain text contains TEXT')
    parser.add_argument('--out', type=str, default='demo.html',
                        help='Output file (default: demo.html)')
    parser.add_argument('--list', action='store_true',
                        help='List all blocks then exit')
    parser.add_argument('--no-enhance', action='store_true',
                        help='Skip GitHub-style colors, copy button, and Try-it button')
    args = parser.parse_args()

    html_path = os.path.realpath(args.html_file)
    if not os.path.exists(html_path):
        print(f'Error: file not found: {html_path}', file=sys.stderr)
        sys.exit(1)

    with open(html_path, 'r', encoding='utf-8') as f:
        source = f.read()

    lean_blocks = extract_lean_blocks(source)
    if not lean_blocks:
        print('No Lean code blocks found.', file=sys.stderr)
        sys.exit(1)

    pairs = extract_blocks_with_output(source, lean_blocks)

    if args.list:
        print(f'Found {len(pairs)} Lean code block(s):\n')
        for i, (code_html, output_html) in enumerate(pairs):
            plain = strip_tags(code_html).strip()
            first_line = plain.split('\n')[0][:80]
            suffix = '...' if len(plain.split('\n')[0]) > 80 else ''
            has_output = ' [+output]' if output_html else ''
            print(f'  [{i}]{has_output} {first_line}{suffix}')
        return

    if args.index is not None:
        if args.index >= len(pairs):
            print(f'Error: index {args.index} out of range (0..{len(pairs)-1})', file=sys.stderr)
            sys.exit(1)
        selected = [pairs[args.index]]
    elif args.match is not None:
        selected = [(c, o) for c, o in pairs if args.match in strip_tags(c)]
        if not selected:
            print(f'No blocks matched "{args.match}".', file=sys.stderr)
            sys.exit(1)
    else:
        selected = pairs

    # Find -verso-docs.json
    search_dir = os.path.dirname(html_path)
    docs_candidate = None
    for _ in range(6):
        candidate = os.path.join(search_dir, '-verso-docs.json')
        if os.path.exists(candidate):
            docs_candidate = candidate
            break
        search_dir = os.path.dirname(search_dir)

    docs_json_str = '{}'
    if docs_candidate:
        with open(docs_candidate, 'r', encoding='utf-8') as f:
            docs_json_str = f.read().strip()

    site_root = os.path.dirname(docs_candidate) if docs_candidate else os.path.dirname(html_path)
    verso_data_dir = os.path.join(site_root, '-verso-data')

    out_dir = os.path.dirname(os.path.realpath(args.out)) if os.path.dirname(args.out) else os.getcwd()
    if os.path.exists(verso_data_dir):
        try:
            verso_data_path = os.path.relpath(verso_data_dir, out_dir)
        except ValueError:
            verso_data_path = verso_data_dir
    else:
        verso_data_path = '_site/-verso-data'

    css_blocks = extract_style_blocks(source)
    script_blocks = extract_inline_scripts(source)

    html_out = build_html(
        css_blocks, script_blocks, selected,
        docs_json_str, verso_data_path,
        enhance=not args.no_enhance,
    )

    with open(args.out, 'w', encoding='utf-8') as f:
        f.write(html_out)

    enhance_note = '' if args.no_enhance else ' (with colors + copy + try-it)'
    print(f'Wrote {len(selected)} block(s) to {args.out}{enhance_note}')


if __name__ == '__main__':
    main()
