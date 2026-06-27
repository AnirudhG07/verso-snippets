#!/usr/bin/env bash
# Usage: ./make_demo.sh [options] [scratch.lean]
#
# Options:
#   --index N    Extract only block N into demo.html
#   --split      Write one file per block: demo-0.html, demo-1.html, ...
#   --no-enhance Skip GitHub colors, copy button, Try-it button
#
# Mark regions in scratch.lean with:
#   -- #show / -- #endshow
# Code outside markers compiles but won't appear in output.
set -euo pipefail

SCRATCH="scratch.lean"
INDEX=""
SPLIT=false
NO_ENHANCE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --index)   INDEX="$2"; shift 2 ;;
    --split)   SPLIT=true; shift ;;
    --no-enhance) NO_ENHANCE="--no-enhance"; shift ;;
    --*)       echo "Unknown option: $1" >&2; exit 1 ;;
    *)         SCRATCH="$1"; shift ;;
  esac
done

GENERATED_HTML="_site/index.html"
SELECTED="selected.json"

if [[ ! -f "$SCRATCH" ]]; then
  echo "Error: $SCRATCH not found." >&2; exit 1
fi

echo "→ Wrapping $SCRATCH into Snippet.lean ..."
python3 wrap_lean.py "$SCRATCH" > Snippet.lean

echo "→ Building ..."
lake build generate-snippet

echo "→ Generating site ..."
.lake/build/bin/generate-snippet

[[ -f "$GENERATED_HTML" ]] || { echo "Error: $GENERATED_HTML not found"; ls _site/; exit 1; }

echo "→ Extracting HTML blocks ..."

# Resolve which block indices to work with
if [[ -f "$SELECTED" ]]; then
  HAS_MARKERS=$(python3 -c "import json; print(json.load(open('$SELECTED')).get('has_markers', False))")
  if [[ "$HAS_MARKERS" == "True" ]]; then
    INDICES=$(python3 -c "import json; print(*json.load(open('$SELECTED'))['selected'])")
  else
    # No markers: all blocks
    INDICES=$(python3 extract_lean.py "$GENERATED_HTML" --list 2>/dev/null \
              | grep -oP '(?<=\[)\d+(?=\])' | tr '\n' ' ')
  fi
else
  INDICES=$(python3 extract_lean.py "$GENERATED_HTML" --list 2>/dev/null \
            | grep -oP '(?<=\[)\d+(?=\])' | tr '\n' ' ')
fi

if [[ -n "$INDEX" ]]; then
  # Single block requested explicitly
  python3 extract_lean.py "$GENERATED_HTML" --index "$INDEX" --out demo.html $NO_ENHANCE
  echo "Done! Open demo.html"

elif $SPLIT; then
  # One file per #show region (group of consecutive shown blocks)
  if [[ -f "$SELECTED" && "$(python3 -c "import json; print('groups' in json.load(open('$SELECTED')))")" == "True" ]]; then
    # Use groups from selected.json: each group → one file
    python3 - "$SELECTED" "$GENERATED_HTML" "$NO_ENHANCE" <<'PYEOF'
import json, sys, os, subprocess
sel = json.load(open(sys.argv[1]))
groups = sel.get('groups', [[i] for i in sel['selected']])
html = sys.argv[2]
no_enhance = sys.argv[3]
for n, group in enumerate(groups):
    indices = ','.join(str(i) for i in group)
    out = f'demo-{n}.html'
    cmd = ['python3', 'extract_lean.py', html, '--indices', indices, '--out', out]
    if no_enhance:
        cmd.append(no_enhance)
    subprocess.run(cmd, check=True)
    print(f'  wrote {out}')
PYEOF
  else
    # No groups: fall back to one file per block index
    for i in $INDICES; do
      OUT="demo-${i}.html"
      python3 extract_lean.py "$GENERATED_HTML" --index "$i" --out "$OUT" $NO_ENHANCE
      echo "  wrote $OUT"
    done
  fi
  echo "Done!"

else
  # All selected blocks in one file (default)
  SELECTED_ARG=""
  if [[ -f "$SELECTED" && "$HAS_MARKERS" == "True" ]]; then
    SELECTED_ARG="--selected $SELECTED"
  fi
  python3 extract_lean.py "$GENERATED_HTML" --out demo.html $SELECTED_ARG $NO_ENHANCE
  echo "Done! Open demo.html"
fi
