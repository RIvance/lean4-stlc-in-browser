prelude
import LambdaCalculus.Typing.Rules

/-!
Checked typing certificates over the existing syntax. The unifier supplies
candidate fixed-point types in preorder; this independent structural checker
validates every rule. Proof fields are erased from compiled code.
-/

namespace LambdaCalculus

structure TypingCertificate (Γ : Ctx) (e : Expr) where
  type : Ty
  typing : Γ ⊢ e ∶ type

structure ProgramCertificate (Γ : Ctx) (source : List Command) where
  commands : List (Command × Ty)
  typing : Γ ⊢ᵖ commands
  erases : commands.map Prod.fst = source

def certify (Γ : Ctx) (e : Expr) (hints : List Ty) : Option (TypingCertificate Γ e × List Ty) :=
  match e with
  | .var _ x =>
    match h : lookup x Γ with
    | some τ => some (⟨τ, .var h⟩, hints)
    | none => none
  | .unit _ => some (⟨.unit, .unit⟩, hints)
  | .nat _ _ => some (⟨.nat, .nat⟩, hints)
  | .bool _ _ => some (⟨.bool, .bool⟩, hints)
  | .lam _ x τ e => do
    let (c, hints) ← certify ((x, τ) :: Γ) e hints
    return (⟨τ ⟶ c.type, .lam c.typing⟩, hints)
  | .app _ e₁ e₂ => do
    let (c₁, hints) ← certify Γ e₁ hints
    let (c₂, hints) ← certify Γ e₂ hints
    match c₁ with
    | ⟨τ ⟶ σ, h₁⟩ =>
      if h : c₂.type = τ then some (⟨σ, .app h₁ (h ▸ c₂.typing)⟩, hints) else none
    | _ => none
  | .letE _ x e₁ e₂ => do
    let (c₁, hints) ← certify Γ e₁ hints
    let (c₂, hints) ← certify ((x, c₁.type) :: Γ) e₂ hints
    return (⟨c₂.type, .letE c₁.typing c₂.typing⟩, hints)
  | .fix _ x a e => do
    let τ :: hints := hints | none
    if ha : a = none ∨ a = some τ then
      let (c, hints) ← certify ((x, τ) :: Γ) e hints
      if h : c.type = τ then
        let hτ := Eq.mp (congrArg (fun σ => (x, τ) :: Γ ⊢ e ∶ σ) h) c.typing
        some (⟨τ, .fix ha hτ⟩, hints)
      else none
    else none
  | .seq _ e₁ e₂ => do
    let (c₁, hints) ← certify Γ e₁ hints
    let (c₂, hints) ← certify Γ e₂ hints
    return (⟨c₂.type, .seq c₁.typing c₂.typing⟩, hints)
  | .ite _ e₁ e₂ e₃ => do
    let (c₁, hints) ← certify Γ e₁ hints
    let (c₂, hints) ← certify Γ e₂ hints
    let (c₃, hints) ← certify Γ e₃ hints
    if h₁ : c₁.type = .bool then
      if h₂ : c₃.type = c₂.type then
        some (⟨c₂.type, .ite (h₁ ▸ c₁.typing) c₂.typing (h₂ ▸ c₃.typing)⟩, hints)
      else none
    else none
  | .bin _ op e₁ e₂ => do
    let (c₁, hints) ← certify Γ e₁ hints
    let (c₂, hints) ← certify Γ e₂ hints
    if h₁ : c₁.type = .nat then
      if h₂ : c₂.type = .nat then
        some (⟨op.result, .bin (h₁ ▸ c₁.typing) (h₂ ▸ c₂.typing)⟩, hints)
      else none
    else none

def certifyProgram (Γ : Ctx) (cs : List Command) (hints : List Ty)
  : Option (ProgramCertificate Γ cs × List Ty)
:=
  match cs with
  | [] => some (⟨[], .nil, rfl⟩, hints)
  | .define p x e :: cs => do
    let (c, hints) ← certify Γ e hints
    let (cs, hints) ← certifyProgram ((x, c.type) :: Γ) cs hints
    return (
      ⟨
        (.define p x e, c.type) :: cs.commands,
        .define c.typing cs.typing,
        congrArg (fun cs => (.define p x e : Command) :: cs) cs.erases
      ⟩,
      hints
    )
  | .expr e :: cs => do
    let (c, hints) ← certify Γ e hints
    let (cs, hints) ← certifyProgram Γ cs hints
    return (
      ⟨
        (.expr e, c.type) :: cs.commands,
        .expr c.typing cs.typing,
        congrArg (fun cs => (.expr e : Command) :: cs) cs.erases
      ⟩,
      hints
    )

end LambdaCalculus
