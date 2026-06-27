import VersoBlog
import Snippet

open Verso Genre Blog Site Syntax

open Output Html Template Theme in
def theme : Theme := { Theme.default with
  primaryTemplate := do
    return {{
      <html>
        <head>
          <meta charset="utf-8"/>
          <meta name="viewport" content="width=device-width, initial-scale=1"/>
          <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/sakura.css/css/sakura.css" type="text/css"/>
          <title>"Lean Snippet"</title>
          {{← builtinHeader }}
        </head>
        <body>
          <main style="padding: 1rem">
            {{ (← param "content") }}
          </main>
        </body>
      </html>
    }}
  }

def theSite : Site := site Snippet

def main := blogMain theme theSite
