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

Adding this, gives you -

<iframe
  src="/demo/demo-1.html"
  style="width:100%;border:none;"
  loading="lazy"
></iframe>
```

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

_Note:_ If you want comments to come, use `/- ... -/` or `/-- ... -/` comments, instead of `-- comment` style. This is because Verso removes the latter from the generated code.

## Usage

Write your Lean code in any `proof.lean` file, then run:

```bash
lean-snippet proof.lean               # → lean-code.html
lean-snippet proof.lean --split       # → lean-code_1.html, lean-code_2.html, ...
lean-snippet proof.lean -o auth       # → auth.html
lean-snippet proof.lean -o auth --split  # → auth_1.html, auth_2.html, ...
```

Or run directly from the project root:

````bash
./make_demo.sh proof.lean
./make_demo.sh proof.lean --split

## Requirements

- **Lean 4** (`leanprover/lean4:v4.29.0`) via [elan](https://github.com/leanprover/elan)
- **Python 3**

## Setup

```bash
git clone https://github.com/AnirudhG07/verso-snippets
cd lean-snippet
lake build generate-snippet   # downloads Verso, ~5 min first time
````

Optionally install globally so you can use it from any directory:

```bash
ln -s "$PWD/lean-snippet" ~/bin/lean-snippet
```

## Options

| Flag                       | Description                                                         |
| -------------------------- | ------------------------------------------------------------------- |
| `-o NAME`, `--output NAME` | Base name for output files (default: `lean-code`)                   |
| `--split`                  | One file per `#show` region: `{base}_1.html`, `{base}_2.html`, ...  |
| `--index N`                | Extract only the N-th block (0-based)                               |
| `--no-enhance`             | Plain Verso styling — no GitHub colors, copy button, or Try-it link |
| `--setup`                  | First-time build of the Verso project (`lean-snippet` only)         |

## How it works

1. `wrap_lean.py` converts your `.lean` file into a minimal Verso `#doc` page, hoisting `import` lines and converting top-level `-- comments` before declarations to `/-- doc comments -/` (which survive elaboration).
2. `lake build` + the generated `generate-snippet` binary runs Verso, which elaborates the Lean code and produces `_site/index.html` with full hover data.
3. `extract_lean.py` pulls out the highlighted code blocks, inlines all JS/CSS (including Verso's tippy.js/popper.js), and writes a self-contained HTML file.

## Acknowledgements

Thanks to [Verso](https://github.com/leanprover/verso) and Lean FRO for making this amazing tool which makes Lean developer easily present their work on websites, slides, etc.
