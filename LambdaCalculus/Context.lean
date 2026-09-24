prelude
import LambdaCalculus.Syntax

namespace LambdaCalculus

abbrev Ctx := List (String × Ty)

/-- The most recent binding wins, including when a binder shadows itself. -/
def lookup (x : String) : List (String × α) → Option α
  | [] => none
  | (y, a) :: Γ => if x == y then some a else lookup x Γ

end LambdaCalculus
