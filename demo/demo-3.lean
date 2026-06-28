import Std

-- This file has two anchored regions. Render the 2nd with:  ./lean-snippet demo/demo-3.lean --anchor part2

-- ANCHOR: part1
/-- Adding zero on the right changes nothing. -/
theorem add_zero' (n : Nat) : n + 0 = n := by simp
-- ANCHOR_END: part1

-- ANCHOR: part2
/-- Doubling a number is the same as adding it to itself. -/
theorem two_mul' (n : Nat) : 2 * n = n + n := by omega
-- ANCHOR_END: part2
