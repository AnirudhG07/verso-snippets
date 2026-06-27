import VersoBlog
open Verso Genre Blog

#doc (Page) "Scratch" =>
%%%
%%%

```leanInit scratch
```
```lean scratch
def hello (name : String) : String :=
  s!"Hello, {name}!"
```

```lean scratch
#eval hello "world"
```

```lean scratch
def fib : Nat → Nat
  | 0 => 0
  | 1 => 1
  | n + 2 => fib n + fib (n + 1)
```

```lean scratch
#eval fib 10
```
