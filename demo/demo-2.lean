import Std

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