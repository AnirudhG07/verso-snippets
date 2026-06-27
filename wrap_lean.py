#!/usr/bin/env python3
"""
Convert a plain .lean file into a minimal Verso page for snippet use.

Splitting rules:
  - Blank lines separate chunks (each chunk → one lean block).
  - `-- #show` / `-- #endshow` also split chunks AND mark those chunks
    for inclusion in demo.html. Code outside markers is still sent to
    Verso (so the file compiles), but won't appear in the output HTML.
  - If NO markers are present, ALL chunks are shown.

Writes `selected.json` alongside Snippet.lean listing which block
indices to include in the output.

Usage: python3 wrap_lean.py scratch.lean > Snippet.lean
"""
import json
import os
import re
import sys

SHOW_START = re.compile(r'^\s*--\s*#show\b', re.IGNORECASE)
SHOW_END   = re.compile(r'^\s*--\s*#endshow\b', re.IGNORECASE)
HINT_LINE  = re.compile(r'^--\s*Write your Lean code')

src = open(sys.argv[1]).read()

# ── Pass 1: split into chunks, tracking which are inside #show/#endshow ──
chunks: list[tuple[str, bool]] = []   # (code_text, is_shown)
current: list[str] = []
in_show = False
has_markers = False

for line in src.splitlines():
    if SHOW_START.match(line):
        has_markers = True
        if current:
            chunks.append(('\n'.join(current), in_show))
            current = []
        in_show = True
        continue
    if SHOW_END.match(line):
        if current:
            chunks.append(('\n'.join(current), in_show))
            current = []
        in_show = False
        continue
    if line.strip() == '':
        if current:
            chunks.append(('\n'.join(current), in_show))
            current = []
    else:
        if not HINT_LINE.match(line):
            current.append(line)

if current:
    chunks.append(('\n'.join(current), in_show))

# Drop empty chunks
chunks = [(c, s) for c, s in chunks if c.strip()]

# If no markers were used, show everything
if not has_markers:
    chunks = [(c, True) for c, s in chunks]

# ── Write selected.json ──
selected = [i for i, (_, shown) in enumerate(chunks) if shown]
sidecar = os.path.join(os.path.dirname(os.path.abspath(sys.argv[1])),
                       'selected.json')
with open(sidecar, 'w') as f:
    json.dump({'selected': selected, 'has_markers': has_markers}, f)

# ── Build Snippet.lean ──
header = (
    "import VersoBlog\n"
    "open Verso Genre Blog\n\n"
    '#doc (Page) "Scratch" =>\n'
    "%%%\n"
    "%%%\n\n"
    "```leanInit scratch\n"
    "```\n"
)

blocks = [f"```lean scratch\n{code}\n```" for code, _ in chunks]
print(header + "\n\n".join(blocks) + "\n", end='')
