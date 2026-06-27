# Lean4 Verso-snippets

Usually we just want 1 html file for 1 Lean4 code, not too many verso directories involved, but it should have all hover features Verso gives. You don't mind how big it is, just a simple thing you can utilize somewhere.

This tool generate self-contained HTML snippets from Lean 4 code — with hover tooltips (type info, docstrings, binding highlights), GitHub-style syntax colors, a copy button, and a "Try it!" link to the Lean web editor.

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

<img width="815" height="429" alt="image" src="https://github.com/user-attachments/assets/1bf0b33c-b913-4fc5-ad96-ea74f6aab96c" />

## Marking regions to convert to Html

You may want the whole Lean4 code or just a small portion of the Lean code into Html. Verso snippets covers it all.
All you need a Lean code, which builds correctly. Yes you can't convert a file which won't build correctly.

If you want the whole code, you don't have to do anything.
If you only want to display _part_ of a file (while still compiling the whole thing), mark the regions you want shown:

```lean
-- helper needed to compile, not displayed
def IsPrime (n : Nat) := 1 < n ∧ ∀ k, 1 < k → k < n → ¬ k ∣ n

-- #show
/-- Every number larger than 1 has a prime factor -/
theorem exists_prime_factor :
    ∀ n, 1 < n → ∃ k, IsPrime k ∧ k ∣ n := by
  ...
-- #endshow
```

- Code outside markers compiles but won't appear in the output HTML.
- Multiple `-- #show` / `-- #endshow` pairs are supported.
- With `--split`, each marked region becomes its own file.
- Without markers, the entire file is shown.

### One box or many — `--multi-blocks`

By default the shown code renders as **a single continuous code box**, blank
lines and all. If you'd rather have blank lines break the code into separate
boxes (one per blank-line-separated group), pass `--multi-blocks`:

```bash
./lean-snippet proof.lean                 # one box (default)
./lean-snippet proof.lean --multi-blocks  # a separate box per blank-line group
```

`--multi-blocks` controls boxes **within one HTML file**, whereas `--split`
controls separate **files** per `#show` region — the two compose.

### Comments — `--raw-comments`

Verso drops bare `-- comment` lines during elaboration, so by default
`lean-snippet` handles them for you:

- A run of `-- comments` **immediately before a declaration** is converted to a `/-- ... -/` doc comment and shown attached to that declaration.
- A block of **only** `-- comments` (with no declaration) is dropped — Verso cannot render it.

Pass `--raw-comments` to turn this off and keep `-- comments` exactly as written
(Verso will then drop them). For prose you always want kept, prefer `/-- ... -/`
or `/-! ... -/` comments directly.

## Requirements

- **Lean 4** (`leanprover/lean4:v4.29.0`) via [elan](https://github.com/leanprover/elan)
- **Python 3** (used by the HTML extractor)

## Setup

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
./lean-snippet proof.lean                 # → lean-code.html
./lean-snippet proof.lean --split         # → lean-code_1.html, lean-code_2.html, ...
./lean-snippet proof.lean -o auth         # → auth.html
./lean-snippet proof.lean -o auth --split # → auth_1.html, auth_2.html, ...
```

Run with no file and it uses `scratch.lean` from the current directory (or the
repo's `scratch.lean` as a fallback) — handy for quick experiments:

```bash
./lean-snippet                            # wraps scratch.lean → lean-code.html
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

| Flag                       | Description                                                         |
| -------------------------- | ------------------------------------------------------------------- |
| `-o NAME`, `--output NAME` | Base name for output files (default: `lean-code`)                   |
| `--split`                  | One file per `#show` region: `{base}_1.html`, `{base}_2.html`, ...  |
| `--index N`                | Extract only the N-th block (0-based)                               |
| `--no-enhance`             | Plain Verso styling — no GitHub colors, copy button, or Try-it link |
| `--multi-blocks`           | Split code into separate boxes on blank lines (default: one box)    |
| `--raw-comments`           | Keep `-- comments` as-is (default: convert to `/-- docs -/`)        |
| `--setup`                  | First-time build of the Verso project (`lean-snippet` only)         |

## How it works

The `lean-snippet` script chains three steps:

1. **`wrap-lean`** (a Lean 4 binary, source in `verso-snippets/WrapLean.lean`) converts your `.lean` file into a minimal Verso `#doc` page — hoisting `import` lines, honoring `#show`/`#endshow` markers, and converting `-- comments` immediately before a declaration into `/-- doc comments -/` (which survive elaboration).
2. **`generate-snippet`** (`verso-snippets/Main.lean`) runs Verso, which elaborates the Lean code and produces `_site/index.html` with full hover data.
3. **`extract_lean.py`** pulls out the highlighted code blocks, inlines all JS/CSS (including Verso's tippy.js/popper.js), and writes the self-contained HTML file.

## Acknowledgements

Thanks to [Verso](https://github.com/leanprover/verso) and Lean FRO for making this amazing tool which makes Lean developer easily present their work on websites, slides, etc.
