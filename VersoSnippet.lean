/-
VersoSnippet — generate a single, self-contained HTML snippet from SubVerso's
highlighted-module JSON, using Verso's own rendering library.

Split by concern: VersoSnippet.Render (core), .Literate (`--literate`),
.Assets (inlined CSS/JS + vendored web assets), and .Page (page assembly).
-/
import VersoSnippet.Render
import VersoSnippet.Literate
import VersoSnippet.Page
