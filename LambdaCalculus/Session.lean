prelude
import LambdaCalculus.Parser
import LambdaCalculus.Semantics

/-! Pure language operations and persistent sessions, with no IO or transport dependencies. -/

namespace LambdaCalculus

structure Result where
  type : Ty
  term : Expr
  value : Option Value := none
  steps : Nat := 0

structure Binding where
  name : String
  type : Ty
  value : Value

structure Session where
  bindings : List Binding := []

def Session.context (s : Session) : Ctx := s.bindings.map fun b => (b.name, b.type)
def Session.environment (s : Session) : Env := s.bindings.map fun b => (b.name, .value b.value)

def Session.check (s : Session) (source : String) : Except Diagnostic Result := do
  let e ← parse source
  return ⟨← infer s.context e, e, none, 0⟩

private def runExpr (s : Session) (e : Expr) (fuel : Nat) : Except Diagnostic Result := do
  let τ ← infer s.context e
  let (v, steps) ← evaluateIn s.environment e fuel
  return ⟨τ, e, some v, steps⟩

def Session.run (s : Session) (source : String) (fuel : Nat := 100000) : Except Diagnostic Result := do
  runExpr s (← parse source) fuel

/-- Submissions are checked together and committed atomically; their evaluation shares one budget. -/
def Session.submit (s : Session) (source : String) (fuel : Nat := 100000)
  : Except Diagnostic (Session × Result)
:= do
  let commands ← parseProgram source
  let checked ← inferProgram s.context commands
  let mut session := s
  let mut result : Result := ⟨.unit, programExpr commands, some .unit, 0⟩
  for (command, τ) in checked do
    let e := match command with
      | .define _ _ e | .expr e => e
    let (v, steps) ← evaluateIn session.environment e (fuel - result.steps)
    result := { result with steps := result.steps + steps }
    match command with
    | .define _ x _ =>
      session := ⟨⟨x, τ, v⟩ :: session.bindings⟩
      result := { result with type := .unit, value := some .unit }
    | .expr _ => result := { result with type := τ, value := some v }
  return (session, result)

def process (source : String) (fuel : Nat := 100000) (checkOnly : Bool := false) : Except Diagnostic Result :=
  if checkOnly then ({} : Session).check source else ({} : Session).run source fuel

end LambdaCalculus
