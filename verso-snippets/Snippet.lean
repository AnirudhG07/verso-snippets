-- Write your Lean 4 code here, then run:
--   ./lean-snippet                 (uses this file by default)
--   ./lean-snippet --multi-blocks  (one box per top-level command)
--
-- To show only part of a file (while still compiling the whole thing),
-- wrap a region in anchor comments and select it with --anchor NAME:
--
--   ./lean-snippet scratch.lean --anchor demo
--
-- Comments are preserved as-is — no conversion needed.
-- See Demo/AuthVerify.lean for a full worked example.

import Std

-- ANCHOR: demo
open Std.Do

def sum_to_n : Int → Id Int := fun n ↦
  (do
      let mut total := (0 : Int)
      let mut i := (1 : Int)
      while i <= n do
        total := total + i
        i := i + (1 : Int)
      return total)

#eval sum_to_n 10
-- ANCHOR_END: demo
