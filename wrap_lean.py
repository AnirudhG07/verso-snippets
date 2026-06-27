#!/usr/bin/env python3
"""
Convert a plain .lean file into a minimal Verso page for snippet use.
Splits on blank lines — each paragraph becomes a separate lean code block.

Usage: python3 wrap_lean.py scratch.lean > Snippet.lean
"""
import re
import sys

src = open(sys.argv[1]).read()

# Split on blank lines; each paragraph of non-blank lines = one lean block
chunks: list[str] = []
current: list[str] = []
for line in src.splitlines():
    if line.strip() == '':
        if current:
            chunks.append('\n'.join(current))
            current = []
    else:
        current.append(line)
if current:
    chunks.append('\n'.join(current))

# Drop the boilerplate hint comment if present
chunks = [c for c in chunks if not re.match(r'^--\s*Write your Lean code', c)]

header = (
    "import VersoBlog\n"
    "open Verso Genre Blog\n\n"
    '#doc (Page) "Scratch" =>\n'
    "%%%\n"
    "%%%\n\n"
    "```leanInit scratch\n"
    "```\n"
)

blocks = [f"```lean scratch\n{chunk}\n```" for chunk in chunks]
print(header + "\n\n".join(blocks) + "\n", end='')
