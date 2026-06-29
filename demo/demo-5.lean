import Std

/-!
# Gauss's summation formula

A classic result: the sum of the first $n$ positive integers is
$$\sum_{i=1}^{n} i \;=\; \frac{n\,(n+1)}{2}.$$

We define the sum by recursion and prove the *doubled* identity
$2 \cdot S(n) = n\,(n+1)$ by induction on $n$ — this avoids dividing by $2$
in `Nat`, where division truncates.
-/

def sumTo : Nat → Nat
  | 0     => 0
  | n + 1 => (n + 1) + sumTo n

#check sumTo

/-!
The base case $n = 0$ holds by `rfl`. For the step we expand
$S(k+1) = (k+1) + S(k)$, distribute the $2$, rewrite with the induction
hypothesis $2\cdot S(k) = k\,(k+1)$, and the remaining goal
$2(k+1) + k(k+1) = (k+1)(k+2)$ closes once both products are expanded.
-/

theorem two_mul_sumTo (n : Nat) : 2 * sumTo n = n * (n + 1) := by
  induction n with
  | zero => rfl
  | succ k ih =>
    rw [sumTo, Nat.mul_add, ih, Nat.mul_succ, Nat.succ_mul]
    grind

#check two_mul_sumTo
