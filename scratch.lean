-- Write your Lean code here. Run ./make_demo.sh to get demo.html.

def hello (name : String) : String :=
  s!"Hello, {name}!"

#eval hello "world"

def fib : Nat → Nat
  | 0 => 0
  | 1 => 1
  | n + 2 => fib n + fib (n + 1)

#eval fib 10
