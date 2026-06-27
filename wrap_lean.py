#!/usr/bin/env python3
"""
Convert a plain .lean file into a minimal Verso page for snippet use.

Splitting rules:
  - Outside #show regions: blank lines separate chunks.
  - Inside #show/#endshow: blank lines are PRESERVED (no splitting).
    The whole region becomes ONE lean block in the output HTML.
  - `import` lines are hoisted into the leanInit block (not code blocks).
  - Standalone `-- comment` lines immediately before a declaration are
    converted to `/-- comment -/` doc comments, which survive elaboration
    and appear in the rendered HTML.

Writes `selected.json` alongside Snippet.lean.

Usage: python3 wrap_lean.py scratch.lean > Snippet.lean
"""
import json
import os
import re
import sys
from collections import defaultdict

SHOW_START  = re.compile(r'^\s*--\s*#show\b',    re.IGNORECASE)
SHOW_END    = re.compile(r'^\s*--\s*#endshow\b', re.IGNORECASE)
HINT_LINE   = re.compile(r'^--\s*Write your Lean code')
IMPORT_LINE = re.compile(r'^\s*import\s+\S')
COMMENT_LINE = re.compile(r'^(\s*)--(?!#)(.*)$')   # -- comment (not a marker)
ATTR_OR_DECL = re.compile(                         # start of a Lean declaration
    r'^\s*(@\[|private\b|protected\b|noncomputable\b|'
    r'def\b|theorem\b|lemma\b|structure\b|class\b|instance\b|'
    r'inductive\b|coinductive\b|abbrev\b|opaque\b|axiom\b)'
)


def count_depth_change(line: str) -> int:
    """Net change in /- ... -/ block-comment depth for a single line."""
    depth, i = 0, 0
    while i < len(line) - 1:
        if line[i:i+2] == '/-':
            depth += 1; i += 2
        elif line[i:i+2] == '-/':
            depth -= 1; i += 2
        else:
            i += 1
    return depth


def preprocess_comments(code: str) -> str:
    """
    Convert standalone `-- comment` lines immediately before a declaration
    into `/-- comment -/` doc comments, which survive Lean's elaborator.
    Comments inside tactic blocks already survive as inter-text and are left alone.
    """
    lines = code.split('\n')
    result: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]

        # Collect a run of consecutive -- comment lines (skip markers)
        if COMMENT_LINE.match(line) and not re.match(r'^\s*--\s*#', line):
            run_start = i
            run_texts: list[str] = []
            while i < len(lines) and COMMENT_LINE.match(lines[i]) and \
                    not re.match(r'^\s*--\s*#', lines[i]):
                m = COMMENT_LINE.match(lines[i])
                run_texts.append(m.group(2).strip())
                i += 1

            # Peek ahead: is the next non-blank line a declaration / attribute?
            k = i
            while k < len(lines) and not lines[k].strip():
                k += 1
            next_is_decl = k < len(lines) and ATTR_OR_DECL.match(lines[k])

            if next_is_decl:
                # Emit as /-- ... -/ doc comment
                body = ' '.join(t for t in run_texts if t)
                result.append(f'/-- {body} -/')
            else:
                # Leave as-is (e.g. inside tactic blocks — they survive anyway)
                for j in range(run_start, i):
                    result.append(lines[j])
        else:
            result.append(line)
            i += 1

    return '\n'.join(result)


# ── Read source ──────────────────────────────────────────────────────────────
src = open(sys.argv[1]).read()

# ── Pass 1: split into chunks ─────────────────────────────────────────────────
# chunks: (code_text, group_id)  — group_id is None when hidden, int when shown
chunks: list[tuple[str, int | None]] = []
imports: list[str] = []
current: list[str] = []
in_show = False
has_markers = False
comment_depth = 0
group_counter = 0

for line in src.splitlines():
    if SHOW_START.match(line):
        has_markers = True
        if current:
            chunks.append(('\n'.join(current), group_counter if in_show else None))
            current = []
        group_counter += 1
        in_show = True
        comment_depth = 0
        continue

    if SHOW_END.match(line):
        if current:
            chunks.append(('\n'.join(current), group_counter if in_show else None))
            current = []
        in_show = False
        comment_depth = 0
        continue

    # Hoist import lines into leanInit (not valid inside lean blocks)
    if IMPORT_LINE.match(line) and comment_depth == 0:
        imports.append(line.strip())
        continue

    comment_depth += count_depth_change(line)

    if line.strip() == '' and comment_depth <= 0:
        if in_show:
            # Inside a #show region: preserve blank lines, don't split
            current.append('')
        else:
            # Outside: blank line → end of chunk
            if current:
                chunks.append(('\n'.join(current), None))
                current = []
    else:
        if not HINT_LINE.match(line):
            current.append(line)

if current:
    chunks.append(('\n'.join(current), group_counter if in_show else None))

# Drop empty chunks
chunks = [(c, g) for c, g in chunks if c.strip()]

# If no markers, show everything as one group
if not has_markers:
    chunks = [(c, 1) for c, _ in chunks]

# ── Write selected.json ───────────────────────────────────────────────────────
selected = [i for i, (_, g) in enumerate(chunks) if g is not None]

group_map: dict[int, list[int]] = defaultdict(list)
for i, (_, g) in enumerate(chunks):
    if g is not None:
        group_map[g].append(i)
groups: list[list[int]] = [group_map[k] for k in sorted(group_map)]

sidecar = os.path.join(os.path.dirname(os.path.abspath(sys.argv[1])), 'selected.json')
with open(sidecar, 'w') as f:
    json.dump({'selected': selected, 'groups': groups, 'has_markers': has_markers}, f)

# ── Build Snippet.lean ────────────────────────────────────────────────────────
extra_imports = '\n'.join(imports) + '\n' if imports else ''

header = (
    "import VersoBlog\n"
    f"{extra_imports}"
    "open Verso Genre Blog\n\n"
    '#doc (Page) "Scratch" =>\n'
    "%%%\n"
    "%%%\n\n"
    "```leanInit scratch\n```\n"
)

blocks = [
    f"```lean scratch\n{preprocess_comments(code) if g is not None else code}\n```"
    for code, g in chunks
]
print(header + "\n\n".join(blocks) + "\n", end='')
