import Std

open Std (HashMap)

-- Two anchored regions. Render the 2nd with:  ./lean-snippet demo/demo-3.lean --anchor part2

-- ANCHOR: part1
/-- Naive Fibonacci — structural recursion, so termination is automatic. -/
def fib : Nat → Nat
  | 0     => 0
  | 1     => 1
  | n + 2 => fib n + fib (n + 1)

#check @fib
#eval fib 10
-- ANCHOR_END: part1

-- ANCHOR: part2
/-- Dynamic-programming Fibonacci: memoise into a `HashMap` carried by `StateM`. -/
def fibMemo : Nat → StateM (HashMap Nat Nat) Nat
  | 0     => pure 0
  | 1     => pure 1
  | n + 2 => do
    if let some cached := (← get)[n + 2]? then
      return cached
    let value := (← fibMemo n) + (← fibMemo (n + 1))
    modify (·.insert (n + 2) value)
    return value

/-- Run the memoised computation starting from an empty table. -/
def fibDP (n : Nat) : Nat := (fibMemo n).run' {}

#check @fibDP
#eval fibDP 30
-- ANCHOR_END: part2
