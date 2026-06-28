# Lean4 Verso-snippets

Usually we just want 1 html file for 1 Lean4 code, not too many verso directories involved, but it should have all hover features Verso gives. You don't mind how big it is, just a simple thing you can utilize somewhere.

This tool generate self-contained HTML snippets from Lean 4 code — with hover tooltips (type info, docstrings, binding highlights), GitHub-style syntax colors, a copy button, and a "Try it!" link to the Lean web editor.

<div align="center">
<img width="681" height="327" alt="image" src="https://github.com/user-attachments/assets/c5137328-d93e-4851-8eb5-d449b3da2637" />
</div>

## What it produces

A single `.html` file you can open in a browser or embed anywhere via `<iframe>`. The file is fully self-contained — no external file dependencies.

```html
<iframe
  src="/demo/demo-1.html"
  style="width:100%;border:none;"
  loading="lazy"
></iframe>
```

Check out the demo's on the webpage [here](https://anirudhg07.github.io/src/projects/verso-snippets.html) to visualize them.

<!--
<img width="625" height="329" alt="image" src="https://github.com/user-attachments/assets/1bf0b33c-b913-4fc5-ad96-ea74f6aab96c" />
-->
<div align="center">
<img width="650" height="400" alt="image" src="https://github.com/user-attachments/assets/21832169-7139-4eb4-a9f2-78bf517b9319" />
</div>


## Presentation mode — `--slide`

For slides or embedding, hover tooltips get in the way. With `--slide` the
snippet renders with an **info panel joined to the right of the code** (split by
a blue seam): clicking a name shows its type/docs, clicking a tactic shows the
goal state, and clicking a variable highlights its other occurrences — all in
the panel, nothing pops up over the code.

```bash
./lean-snippet proof.lean --slide          # click-only (default)
./lean-snippet proof.lean --slide=both     # panel on click AND hover tooltips
```
<div align="center">
<img width="1221" height="499" alt="image" src="https://github.com/user-attachments/assets/03ce0452-3873-404c-8dc1-947d1310a058" />
</div>

`--slide=click` is the default; `--slide=both` keeps the normal hover tooltips
working alongside the click panel. Inspired by
[verso-slides](https://github.com/leanprover/verso-slides).

## Literate mode — `--literate`

Turn a `.lean` file into a mini-article: `/-! … -/` module-doc blocks render as
**Markdown prose** — headings, lists, bold, links — with **`$LaTeX$` math**
(typeset by KaTeX, fonts inlined so the file stays self-contained), interleaved
with the highlighted code and its `#eval` output.

```bash
./lean-snippet demo/demo-4.lean --literate
```

<div align="center">
<img width="883" height="398" alt="image" src="https://github.com/user-attachments/assets/93ae659b-966e-448a-bdb7-9456e2648203" />
</div>

Only `/-! … -/` blocks become prose; `/-- … -/` doc comments stay attached to
their declarations as usual. `--anchor` / `--multi-blocks` don't apply in
literate mode (the whole document is rendered in source order). Inspired by
[verso-templates](https://github.com/leanprover/verso-templates).


## Marking regions to convert to Html

You may want the whole Lean4 code or just a small portion of the Lean code into Html. Verso snippets covers it all.
All you need a Lean code, which builds correctly. Yes you can't convert a file which won't build correctly.

If you want the whole code, you don't have to do anything.
If you only want to display _part_ of a file (while still compiling the whole thing), wrap the region in **anchor comments** and select it with `--anchor`:

```lean
-- helper needed to compile, not displayed
def IsPrime (n : Nat) := 1 < n ∧ ∀ k, 1 < k → k < n → ¬ k ∣ n

-- ANCHOR: main
/-- Every number larger than 1 has a prime factor -/
theorem exists_prime_factor :
    ∀ n, 1 < n → ∃ k, IsPrime k ∧ k ∣ n := by
  ...
-- ANCHOR_END: main
```

```bash
./lean-snippet proof.lean --anchor main
```

- The whole file is compiled; only the named region is shown.
- Anchor comments (`-- ANCHOR:` / `-- ANCHOR_END:`) are stripped from the output even when you render the whole file.
- Anchors are a [SubVerso](https://github.com/leanprover/subverso) feature, so they can also name individual proof states — see SubVerso's docs.

### One box or many — `--multi-blocks`

By default the code renders as **a single continuous code box**. Pass
`--multi-blocks` to render **one box per top-level command** (each `def`,
`theorem`, `#eval`, … in its own box):

```bash
./lean-snippet proof.lean                 # one box (default)
./lean-snippet proof.lean --multi-blocks  # one box per command
```

### Comments and `#eval` output

Comments are preserved exactly as written — `--` line comments, `/-- … -/` doc
comments, and `/-! … -/` section comments all render as-is. `#eval` / `#check`
output and the goal state at each tactic are captured too, and appear on hover.

## Setup

Currently Version supported **Lean v4.29.0**.

The whole tool is driven by one shell script: **`lean-snippet`**. Clone the repo
and run the one-time setup, which downloads Verso and builds the binaries:

```bash
git clone https://github.com/AnirudhG07/verso-snippets
cd verso-snippets
./lean-snippet --setup
```

## Usage

Write your Lean code in any `.lean` file, then point the script at it:

```bash
./lean-snippet proof.lean                    # → lean-code.html (whole file, one box)
./lean-snippet proof.lean -o auth            # → auth.html
./lean-snippet proof.lean --multi-blocks     # one box per top-level command
./lean-snippet proof.lean --anchor main      # only the -- ANCHOR: main region
```

Run with no file and it uses `scratch.lean` from the current directory (or the
repo's `scratch.lean` as a fallback) — handy for quick experiments:

```bash
./lean-snippet                               # converts scratch.lean → lean-code.html
```

The output `.html` is written both into the repo and into your current
directory, so you can run the script from anywhere your `.lean` file lives.

### Install globally (optional)

Symlink it onto your `PATH` so you can drop the `./` and call it from any directory:

```bash
ln -s "$PWD/lean-snippet" ~/bin/lean-snippet
lean-snippet proof.lean
```

## Options

| Flag                       | Description                                                    |
| -------------------------- | -------------------------------------------------------------- |
| `-o NAME`, `--output NAME` | Base name for the output file (default: `lean-code`)           |
| `--multi-blocks`           | One box per top-level command (default: a single box)          |
| `--anchor NAME`            | Show only the `-- ANCHOR: NAME` … `-- ANCHOR_END: NAME` region |
| `--literate`               | Render `/-! … -/` blocks as prose (Markdown + `$LaTeX$`) between the code |
| `--slide[=click\|both]`    | Info in a joined right-side panel on click; `=both` keeps hovers too |
| `--no-enhance`             | Plain Verso styling — no GitHub colors, Copy, or Try-it button |
| `--setup`                  | First-time build of the renderer                               |

## How it works

The `lean-snippet` script chains three steps — all Lean, no scraping:

1. **Highlight** — your `.lean` becomes the `Snippet` module, and `lake build Snippet:highlighted` runs [SubVerso](https://github.com/leanprover/subverso), which drives the Lean compiler to emit highlighted **JSON** (tokens, hovers, `#eval` output, proof states). No Verso document is built.
2. **Render** — `render-snippet` (`verso-snippets/RenderSnippet.lean`) reads that JSON and uses Verso's own HTML library (`Verso.Code.Highlighted`) to produce the markup, CSS, and JS.
3. **Assemble** — it inlines Verso's `highlightingStyle`/`highlightingJs` plus the vendored `popper`/`tippy` so the single output file is fully self-contained.

Because `render-snippet` is input-independent it is built once; only the cheap highlight step re-runs per file. And because SubVerso supports every Lean release back to 4.0.0, old snippets keep rendering as Lean and Verso move forward.

## Acknowledgements

Thanks to [Verso](https://github.com/leanprover/verso) and Lean FRO for making this amazing tool which makes Lean developer easily present their work on websites, slides, etc.
