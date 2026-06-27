-- Write your Lean 4 code here, then run:
--   ./lean-snippet            (uses this file by default)
--   ./lean-snippet --split    (one HTML file per #show region)
--
-- Mark regions to display with #show / #endshow:
--
--   -- #show
--   theorem my_theorem : 1 + 1 = 2 := by decide
--   -- #endshow
--
-- Everything outside markers compiles but won't appear in the output.
-- See Demo/AuthVerify.lean for a full worked example.

import Std

-- #show
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

-- #endshow
