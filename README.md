# Lean4 Verso-snippets

Usually we just want 1 html file for 1 Lean4 code, not too many verso directories involved, but it should have all hover features Verso gives. You don't mind how big it is, just a simple thing you can utilize somewhere.

This tool generates self-contained HTML snippets from Lean 4 code — with hover tooltips (type info, docstrings, binding highlights), GitHub-style syntax colors, a copy button, and a "Try it!" link to the Lean web editor. Each snippet also carries a built-in **View** switcher to flip between three modes — **Hover**, **Infoview**, and **Literate** — live in the browser (see [below](#the-view-switcher--the-main-thing)).

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

## The "View" switcher — the main thing

Every snippet ships with a **View** dropdown in its header, next to the Copy and
Try-it buttons. All three renderings are baked into the one self-contained file,
so the dropdown switches between them **live in the browser** — instantly, with
no regeneration and no extra files.

<!-- PIC: the default snippet with the "View" dropdown open (Hover / Infoview / Literate) -->
<div align="center">
<!-- <img width="900" alt="the View dropdown" src="" /> -->
</div>

The three are independent checkboxes, so they combine freely (e.g. **Literate**
prose _with_ the **Infoview** panel). The opening view is picked for you — a file
with `/-! … -/` prose opens in **Literate**, otherwise in **Hover** — and the
flags below just set that initial state:

| Flag                             | Opening view                                         |
| -------------------------------- | ---------------------------------------------------- |
| _(none)_                         | Hover — or Literate if the file has `/-! … -/` prose |
| `--infoview` / `--infoview=both` | Infoview (`=both` keeps hover tooltips too)          |
| `--literate`                     | Literate                                             |
| `--no-switcher`                  | no dropdown — a single fixed mode                    |

`--no-switcher` and `--no-enhance` (plain Verso styling) produce a single fixed
mode. `--anchor` keeps the switcher — Hover and Infoview work on the selected
region. The **Literate** checkbox is always present; when there's no `/-! … -/`
prose to show (an anchored region, or a file with none) it stays in the menu but
greyed-out and disabled, with a note that there's nothing to render.

### Hover

The classic view: hover any name, tactic, or `#eval` to get a tooltip with its
type, docstring, or output, and hover a binder to light up its other
occurrences. Best for reading and for pages where the reader explores at their
own pace.

<!-- PIC: a hover tooltip -->
<div align="center">
<!-- <img width="700" alt="hover tooltip" src="" /> -->
</div>

### Infoview — `--infoview`

For slides and embeds, hover tooltips get in the way. **Infoview** joins an info
panel to the right of the code (split by a blue seam): click a name for its
type/docs, a tactic for its goal state, or a variable to highlight its
occurrences — all in the panel, nothing popping up over the code.

<div align="center">
<img width="1221" height="499" alt="image" src="https://github.com/user-attachments/assets/03ce0452-3873-404c-8dc1-947d1310a058" />
</div>

`--infoview=both` keeps the normal hover tooltips working alongside the panel.
This view is inspired by [verso-slides](https://github.com/leanprover/verso-slides).

### Literate — `--literate`

Turn a `.lean` file into a mini-article: `/-! … -/` blocks render as **Markdown
prose** — headings, lists, bold, links — with **`$LaTeX$` math** (typeset by
KaTeX, fonts inlined so the file stays self-contained), interleaved with the
highlighted code and its `#eval` output. `/-- … -/` doc comments stay attached to
their declarations as usual.

<div align="center">
<img width="883" height="398" alt="image" src="https://github.com/user-attachments/assets/93ae659b-966e-448a-bdb7-9456e2648203" />
</div>

Inspired by [verso-templates](https://github.com/leanprover/verso-templates).

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

| Flag                       | Description                                                                                                                              |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `-o NAME`, `--output NAME` | Base name for the output file (default: `lean-code`)                                                                                     |
| `--multi-blocks`           | One box per top-level command (default: a single box)                                                                                    |
| `--anchor NAME`            | Show only the `-- ANCHOR: NAME` … `-- ANCHOR_END: NAME` region                                                                           |
| `--literate`               | Start in literate mode (`/-! … -/` → Markdown + `$LaTeX$` prose)                                                                         |
| `--infoview[=click\|both]` | Start in Infoview (click-panel) mode; `=both` also keeps hovers (inspired by [verso-slides](https://github.com/leanprover/verso-slides)) |
| `--no-switcher`            | Emit a single fixed mode instead of the default "View" dropdown                                                                          |
| `--no-enhance`             | Plain Verso styling — no GitHub colors, Copy, or Try-it button                                                                           |
| `--setup`                  | First-time build of the renderer                                                                                                         |

## How it works

The `lean-snippet` script chains three steps — all Lean, no scraping:

1. **Highlight** — your `.lean` becomes the `Snippet` module, and `lake build Snippet:highlighted` runs [SubVerso](https://github.com/leanprover/subverso), which drives the Lean compiler to emit highlighted **JSON** (tokens, hovers, `#eval` output, proof states). No Verso document is built.
2. **Render** — `render-snippet` (`verso-snippets/RenderSnippet.lean`) reads that JSON and uses Verso's own HTML library (`Verso.Code.Highlighted`) to produce the markup, CSS, and JS.
3. **Assemble** — it inlines Verso's `highlightingStyle`/`highlightingJs` plus the vendored `popper`/`tippy` so the single output file is fully self-contained.

Because `render-snippet` is input-independent it is built once; only the cheap highlight step re-runs per file. And because SubVerso supports every Lean release back to 4.0.0, old snippets keep rendering as Lean and Verso move forward.

## Custom CSS

Every snippet is one self-contained `.html` with all its styling in a single
`<style>` block, so restyling is easy — two ways, depending on scope.

**Per-file tweak (no rebuild).** Open the generated `.html` and drop your own
`<style>` anywhere _after_ the existing one; later rules win by the normal CSS
cascade. For example, to narrow a snippet and restyle the header bar:

```html
<style>
  body {
    max-width: 720px;
  }
  .snippet-header {
    background: #1e1e2e;
  }
  .snippet-title {
    color: #fff;
  }
</style>
```

The class names are stable: `.lean-snippet`, `.snippet-header`,
`.snippet-actions`, `code.hl.lean.block`, `.info-panel`, `.prose`, and the
`.mode-switch` dropdown; syntax colors come from Verso's
`code.hl.lean.block .token…` classes.

**Tool-wide change (rebuild once).** To change the defaults for _every_ snippet,
edit the stylesheet sources and rebuild:

- `verso-snippets/web/panel.css` — the Infoview panel + blue seam
- `verso-snippets/web/switcher.css` — the View dropdown
- the `enhanceCss` / `labelCss` / `proseCss` string defs in
  `verso-snippets/RenderSnippet.lean` — GitHub colors, header bar, and prose

Then run `./lean-snippet --setup` (the CSS is embedded into the renderer at build
time). The page width lives in the `body { max-width: … }` rule.

## Acknowledgements

Thanks to [Verso](https://github.com/leanprover/verso) and Lean FRO for making this amazing tool which makes Lean developer easily present their work on websites, slides, etc.
