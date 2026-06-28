import Std

/-!
# Fibonacci, literately

This snippet mixes **prose**, math, and Lean. Render it with:
`./lean-snippet demo/demo-4.lean --literate`.

The $n$-th Fibonacci number $F_n$ satisfies the recurrence

$$F_n = F_{n-1} + F_{n-2}, \qquad F_0 = 0,\ F_1 = 1.$$

Here is a direct, structurally-recursive definition:
-/

def fib : Nat → Nat
  | 0     => 0
  | 1     => 1
  | n + 2 => fib n + fib (n + 1)

/-!
Lean accepts that this terminates (the arguments shrink), so we can just
evaluate it. For example $F_{10} = 55$:
-/

#eval fib 10
