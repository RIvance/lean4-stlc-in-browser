prelude
import LambdaCalculus.Context

/-!
Declarative typing for the interpreter's syntax. Context lookup uses the first
matching name, so binders shadow earlier bindings. Fixed points have their
body's type; optional source annotations constrain that same type.
-/

namespace LambdaCalculus

set_option quotPrecheck false

set_option hygiene false in
scoped notation:50 Γ " ⊢ " e " ∶ " τ:50 => HasType Γ e τ

inductive HasType : Ctx → Expr → Ty → Prop where

-- [ Variable ]
-- Γ(x) = τ
-- ────────────────── Typ-Var
-- Γ ⊢ x : τ
| var : lookup x Γ = some τ → Γ ⊢ .var p x ∶ τ

-- [ Unit ]
-- ────────────────── Typ-Unit
-- Γ ⊢ () : Unit
| unit : Γ ⊢ .unit p ∶ .unit

-- [ Natural ]
-- ────────────────── Typ-Nat
-- Γ ⊢ n : Nat
| nat : Γ ⊢ .nat p n ∶ .nat

-- [ Boolean ]
-- ────────────────── Typ-Bool
-- Γ ⊢ b : Bool
| bool : Γ ⊢ .bool p b ∶ .bool

-- [ Abstraction ]
-- Γ, x : τ ⊢ e : σ
-- ──────────────────────────── Typ-Abs
-- Γ ⊢ (x : τ) ⇒ e : τ → σ
| lam :
    (x, τ) :: Γ ⊢ e ∶ σ →
    Γ ⊢ .lam p x τ e ∶ (τ ⟶ σ)

-- [ Application ]
-- Γ ⊢ e₁ : τ → σ    Γ ⊢ e₂ : τ
-- ───────────────────────────── Typ-App
-- Γ ⊢ e₁ e₂ : σ
| app :
    Γ ⊢ e₁ ∶ (τ ⟶ σ) →
    Γ ⊢ e₂ ∶ τ →
    Γ ⊢ .app p e₁ e₂ ∶ σ

-- [ Let ]
-- Γ ⊢ e₁ : τ    Γ, x : τ ⊢ e₂ : σ
-- ──────────────────────────────── Typ-Let
-- Γ ⊢ let x = e₁ in e₂ : σ
| letE :
    Γ ⊢ e₁ ∶ τ →
    (x, τ) :: Γ ⊢ e₂ ∶ σ →
    Γ ⊢ .letE p x e₁ e₂ ∶ σ

-- [ Fixed point ]
-- Γ, x : τ ⊢ e : τ    a is absent or is τ
-- ─────────────────────────────────────── Typ-Fix
-- Γ ⊢ fix (x : a) ⇒ e : τ
| fix :
    (a = none ∨ a = some τ) →
    (x, τ) :: Γ ⊢ e ∶ τ →
    Γ ⊢ .fix p x a e ∶ τ

-- [ Sequence ]
-- Γ ⊢ e₁ : τ    Γ ⊢ e₂ : σ
-- ──────────────────────────── Typ-Seq
-- Γ ⊢ { e₁; e₂ } : σ
| seq :
    Γ ⊢ e₁ ∶ τ →
    Γ ⊢ e₂ ∶ σ →
    Γ ⊢ .seq p e₁ e₂ ∶ σ

-- [ Conditional ]
-- Γ ⊢ e₁ : Bool    Γ ⊢ e₂ : τ    Γ ⊢ e₃ : τ
-- ────────────────────────────────────────── Typ-If
-- Γ ⊢ if e₁ then e₂ else e₃ : τ
| ite :
    Γ ⊢ e₁ ∶ .bool →
    Γ ⊢ e₂ ∶ τ →
    Γ ⊢ e₃ ∶ τ →
    Γ ⊢ .ite p e₁ e₂ e₃ ∶ τ

-- [ Binary operation ]
-- Γ ⊢ e₁ : Nat    Γ ⊢ e₂ : Nat
-- ───────────────────────────── Typ-Bin
-- Γ ⊢ e₁ op e₂ : result(op)
| bin :
    Γ ⊢ e₁ ∶ .nat →
    Γ ⊢ e₂ ∶ .nat →
    Γ ⊢ .bin p op e₁ e₂ ∶ op.result

set_option hygiene false in
scoped notation:50 Γ " ⊢ᵖ " cs:50 => ProgramHasType Γ cs

inductive ProgramHasType : Ctx → List (Command × Ty) → Prop where

-- ────────────────── Program-Empty
-- Γ ⊢ []
| nil : Γ ⊢ᵖ []

-- Γ ⊢ e : τ    Γ, x : τ ⊢ cs
-- ──────────────────────────── Program-Define
-- Γ ⊢ (define x e : τ) :: cs
| define : Γ ⊢ e ∶ τ → (x, τ) :: Γ ⊢ᵖ cs → Γ ⊢ᵖ (.define p x e, τ) :: cs

-- Γ ⊢ e : τ    Γ ⊢ cs
-- ──────────────────────────── Program-Expr
-- Γ ⊢ (e : τ) :: cs
| expr : Γ ⊢ e ∶ τ → Γ ⊢ᵖ cs → Γ ⊢ᵖ (.expr e, τ) :: cs

end LambdaCalculus
