#!/usr/bin/env bash
# Usage: ./make_demo.sh [scratch.lean]
# Converts your plain Lean code into highlighted HTML with hover tooltips.
set -euo pipefail

SCRATCH="${1:-scratch.lean}"
GENERATED_HTML="_site/index.html"
OUT="demo.html"

if [[ ! -f "$SCRATCH" ]]; then
  echo "Error: $SCRATCH not found." >&2
  exit 1
fi

echo "→ Wrapping $SCRATCH into Snippet.lean ..."
python3 wrap_lean.py "$SCRATCH" > Snippet.lean

echo "→ Building ..."
lake build generate-snippet

echo "→ Generating site ..."
.lake/build/bin/generate-snippet

if [[ ! -f "$GENERATED_HTML" ]]; then
  echo "Error: expected HTML not found at $GENERATED_HTML" >&2
  ls _site/ >&2
  exit 1
fi

echo "→ Extracting HTML blocks ..."
python3 extract_lean.py "$GENERATED_HTML" --out "$OUT"
echo "Done! Open $OUT in your browser."
