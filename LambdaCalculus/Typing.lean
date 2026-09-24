prelude
import LambdaCalculus.Typing.Certificate

/-!
Monomorphic type inference with an occurs check. A fixed point constrains its
binder and body to the same type. Unresolved recursive types require annotations;
no default type or polymorphic recursion is introduced.
-/

namespace LambdaCalculus

def expectType (p : Span) (τ σ : Ty) : Except Diagnostic Unit :=
  if τ == σ then .ok () else .error ⟨"Type error", s!"Expected {τ}, found {σ}.", p⟩

private inductive MetaTy where
  | unit | nat | bool
  | arr (τ σ : MetaTy)
  | var (n : Nat)
deriving Inhabited

private def metaTy : Ty → MetaTy
  | .unit => .unit
  | .nat => .nat
  | .bool => .bool
  | τ ⟶ σ => .arr (metaTy τ) (metaTy σ)

private def MetaTy.pretty : MetaTy → String
  | .unit => "Unit"
  | .nat => "Nat"
  | .bool => "Bool"
  | .var n => s!"?τ{n}"
  | .arr τ σ => "(" ++ τ.pretty ++ " → " ++ σ.pretty ++ ")"

private structure InferenceState where
  next : Nat := 0
  solutions : List (Nat × MetaTy) := []
  recursiveTypes : List (Span × MetaTy) := []

private abbrev Inference := StateT InferenceState (Except Diagnostic)

private def fresh : Inference MetaTy := do
  let s ← get
  set { s with next := s.next + 1 }
  return .var s.next

private partial def resolve : MetaTy → Inference MetaTy
  | .var n => do
    match (← get).solutions.find? (fun entry => entry.1 == n) with
    | some (_, τ) => resolve τ
    | none => return .var n
  | .arr τ σ => do return .arr (← resolve τ) (← resolve σ)
  | τ => pure τ

private def occurs (n : Nat) : MetaTy → Bool
  | .var m => n == m
  | .arr τ σ => occurs n τ || occurs n σ
  | _ => false

private def assign (p : Span) (n : Nat) (τ : MetaTy) : Inference Unit := do
  if occurs n τ then throw ⟨"Type error", "Recursive use would require an infinite type.", p⟩
  modify fun s => { s with solutions := (n, τ) :: s.solutions }

private partial def unify (p : Span) (τ σ : MetaTy) : Inference Unit := do
  let τ ← resolve τ
  let σ ← resolve σ
  match τ, σ with
  | .unit, .unit | .nat, .nat | .bool, .bool => pure ()
  | .var n, .var m => if n == m then pure () else assign p n σ
  | .var n, _ => assign p n σ
  | _, .var n => assign p n τ
  | .arr τ₁ τ₂, .arr σ₁ σ₂ => unify p τ₁ σ₁; unify p τ₂ σ₂
  | _, _ => throw ⟨"Type error", s!"Expected {τ.pretty}, found {σ.pretty}.", p⟩

private def inferExpr (Γ : List (String × MetaTy)) : Expr → Inference MetaTy
  | .var p x =>
    match lookup x Γ with
    | some τ => pure τ
    | none => throw ⟨"Type error", s!"Unbound variable '{x}'.", p⟩
  | .unit _ => pure .unit
  | .nat _ _ => pure .nat
  | .bool _ _ => pure .bool
  | .lam _ x τ e => do return .arr (metaTy τ) (← inferExpr ((x, metaTy τ) :: Γ) e)
  | .app _ e₁ e₂ => do
    let τ ← resolve (← inferExpr Γ e₁)
    match τ with
    | .arr τ σ => unify e₂.span τ (← inferExpr Γ e₂); return σ
    | .var _ =>
      let υ ← inferExpr Γ e₂
      let σ ← fresh
      unify e₁.span τ (.arr υ σ)
      return σ
    | _ => throw ⟨"Type error", s!"Cannot call a value of type {τ.pretty}.", e₁.span⟩
  | .letE _ x e₁ e₂ => do inferExpr ((x, ← inferExpr Γ e₁) :: Γ) e₂
  | .fix p x annotation e => do
    let τ ← match annotation with
      | some τ => pure (metaTy τ)
      | none => fresh
    modify fun s => { s with recursiveTypes := (p, τ) :: s.recursiveTypes }
    unify e.span τ (← inferExpr ((x, τ) :: Γ) e)
    return τ
  | .seq _ e₁ e₂ => do
    let _ ← inferExpr Γ e₁
    inferExpr Γ e₂
  | .ite _ e₁ e₂ e₃ => do
    unify e₁.span .bool (← inferExpr Γ e₁)
    let τ ← inferExpr Γ e₂
    unify e₃.span τ (← inferExpr Γ e₃)
    return τ
  | .bin _ op e₁ e₂ => do
    unify e₁.span .nat (← inferExpr Γ e₁)
    unify e₂.span .nat (← inferExpr Γ e₂)
    return metaTy op.result

private partial def closeType (p : Span) (τ : MetaTy) : Inference Ty := do
  match ← resolve τ with
  | .unit => return .unit
  | .nat => return .nat
  | .bool => return .bool
  | .arr τ σ => return (← closeType p τ) ⟶ (← closeType p σ)
  | .var _ =>
    throw ⟨"Type error", "Cannot infer a recursive type. Add a type annotation to 'def' or 'fix'.", p⟩

private def closeRecursiveTypes : Inference (List Ty) := do
  let τs ← (← get).recursiveTypes.mapM fun (p, τ) => closeType p τ
  return τs.reverse

/-- Successful inference carries a derivation checked independently of unification. -/
def inferCertified (Γ : Ctx) (e : Expr) : Except Diagnostic (TypingCertificate Γ e) := do
  let action : Inference (Ty × List Ty) := do
    let τ ← inferExpr (Γ.map fun (x, τ) => (x, metaTy τ)) e
    let hints ← closeRecursiveTypes
    return (← closeType e.span τ, hints)
  let ((τ, hints), _) ← action.run {}
  match certify Γ e hints with
  | some (c, []) =>
    if c.type = τ then return c
    else .error ⟨"Type error", "Inferred type does not match its typing derivation.", e.span⟩
  | _ => .error ⟨"Type error", "Could not validate the inferred typing derivation.", e.span⟩

def infer (Γ : Ctx) (e : Expr) : Except Diagnostic Ty := do
  return (← inferCertified Γ e).type

private def constrainCommands (Γ : List (String × MetaTy)) : List Command → Inference Unit
  | [] => pure ()
  | command :: commands => do
    match command with
    | .define _ x e =>
      let τ ← inferExpr Γ e
      constrainCommands ((x, τ) :: Γ) commands
    | .expr e =>
      let _ ← inferExpr Γ e
      constrainCommands Γ commands

/-- Infer an entire submission together, so later uses can constrain recursive definitions. -/
def inferProgramCertified (Γ : Ctx) (commands : List Command) : Except Diagnostic (ProgramCertificate Γ commands) := do
  let action : Inference (List Ty) := do
    constrainCommands (Γ.map fun (x, τ) => (x, metaTy τ)) commands
    closeRecursiveTypes
  let (hints, _) ← action.run {}
  match certifyProgram Γ commands hints with
  | some (cs, []) => return cs
  | _ => .error ⟨"Type error", "Could not validate the inferred program derivation.", {}⟩

def inferProgram (Γ : Ctx) (commands : List Command) : Except Diagnostic (List (Command × Ty)) := do
  return (← inferProgramCertified Γ commands).commands

end LambdaCalculus
