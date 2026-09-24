import LambdaCalculus.Semantics
import LambdaCalculus.Typing.Rules

/-!
Typing of the actual closure machine's runtime objects. A suspended recursive
entry is checked in its captured context extended by its own type. Its captured
environment is finite and does not contain a circular typing derivation.
-/

namespace LambdaCalculus

set_option quotPrecheck false

set_option hygiene false in
scoped notation:50 "⊢ᵥ " v " ∶ " τ:50 => ValueHasType v τ
set_option hygiene false in
scoped notation:50 "⊢ᵣ " r " ∶ " τ:50 => EntryHasType r τ
set_option hygiene false in
scoped notation:50 ρ " ⊨ " Γ:50 => EnvHasType ρ Γ

mutual
  inductive ValueHasType : Value → Ty → Prop where

  -- ────────────────── Val-Unit
  -- ⊢ () : Unit
  | unit : ⊢ᵥ .unit ∶ .unit

  -- ────────────────── Val-Nat
  -- ⊢ n : Nat
  | nat : ⊢ᵥ .nat n ∶ .nat

  -- ────────────────── Val-Bool
  -- ⊢ b : Bool
  | bool : ⊢ᵥ .bool b ∶ .bool

  -- ρ ⊨ Γ    Γ, x : τ ⊢ e : σ
  -- ──────────────────────────── Val-Closure
  -- ⊢ ⟨λx : τ. e, ρ⟩ : τ → σ
  | closure :
      ρ ⊨ Γ →
      (x, τ) :: Γ ⊢ e ∶ σ →
      ⊢ᵥ .closure x τ e ρ ∶ (τ ⟶ σ)

  inductive EntryHasType : EnvEntry → Ty → Prop where

  -- ⊢ v : τ
  -- ────────────────── Entry-Value
  -- ⊢ value(v) : τ
  | value : ⊢ᵥ v ∶ τ → ⊢ᵣ .value v ∶ τ

  -- ρ ⊨ Γ    Γ, x : τ ⊢ e : τ
  -- ──────────────────────────── Entry-Rec
  -- ⊢ recursive(x, e, ρ) : τ
  | recursive :
      ρ ⊨ Γ →
      (x, τ) :: Γ ⊢ e ∶ τ →
      ⊢ᵣ .recursive x e ρ ∶ τ

  inductive EnvHasType : Env → Ctx → Prop where

  -- ────────────────── Env-Empty
  -- ∅ ⊨ ∅
  | nil : [] ⊨ []

  -- ⊢ r : τ    ρ ⊨ Γ
  -- ──────────────────────────── Env-Extend
  -- ρ, x ↦ r ⊨ Γ, x : τ
  | cons : ⊢ᵣ r ∶ τ → ρ ⊨ Γ → (x, r) :: ρ ⊨ (x, τ) :: Γ
end

set_option hygiene false in
scoped notation:50 "⊢ᶠ " k " ∶ " τ " ⇒ " σ:50 => FrameHasType k τ σ
set_option hygiene false in
scoped notation:50 "⊢ᵏ " κ " ∶ " τ " ⇒ " σ:50 => StackHasType κ τ σ
set_option hygiene false in
scoped notation:50 "⊢ᶜ " c " ∶ " τ:50 => ControlHasType c τ
set_option hygiene false in
scoped notation:50 "⊢ₘ " s " ∶ " τ:50 => MachineHasType s τ

inductive FrameHasType : Frame → Ty → Ty → Prop where

-- ρ ⊨ Γ    Γ ⊢ e : τ
-- ───────────────────────────── Frame-Arg
-- ⊢ argument(ρ, e) : (τ → σ) ⇒ σ
| argument : ρ ⊨ Γ → Γ ⊢ e ∶ τ → ⊢ᶠ .argument ρ e p ∶ (τ ⟶ σ) ⇒ σ

-- ⊢ v : τ → σ
-- ─────────────────── Frame-Call
-- ⊢ call(v) : τ ⇒ σ
| call : ⊢ᵥ v ∶ (τ ⟶ σ) → ⊢ᶠ .call v p ∶ τ ⇒ σ

-- ρ ⊨ Γ    Γ, x : τ ⊢ e : σ
-- ──────────────────────────── Frame-Bind
-- ⊢ binding(ρ, x, e) : τ ⇒ σ
| binding : ρ ⊨ Γ → (x, τ) :: Γ ⊢ e ∶ σ → ⊢ᶠ .binding ρ x e ∶ τ ⇒ σ

-- ρ ⊨ Γ    Γ ⊢ e : σ
-- ──────────────────────────── Frame-Discard
-- ⊢ discard(ρ, e) : τ ⇒ σ
| discard : ρ ⊨ Γ → Γ ⊢ e ∶ σ → ⊢ᶠ .discard ρ e ∶ τ ⇒ σ

-- ρ ⊨ Γ    Γ ⊢ e₁ : τ    Γ ⊢ e₂ : τ
-- ─────────────────────────────────── Frame-Branch
-- ⊢ branch(ρ, e₁, e₂) : Bool ⇒ τ
| branch : ρ ⊨ Γ → Γ ⊢ e₁ ∶ τ → Γ ⊢ e₂ ∶ τ → ⊢ᶠ .branch ρ e₁ e₂ p ∶ .bool ⇒ τ

-- ρ ⊨ Γ    Γ ⊢ e : Nat
-- ─────────────────────────────────── Frame-Operand
-- ⊢ operand(ρ, op, e) : Nat ⇒ result(op)
| operand : ρ ⊨ Γ → Γ ⊢ e ∶ .nat → ⊢ᶠ .operand ρ op e p ∶ .nat ⇒ op.result

-- ⊢ v : Nat
-- ───────────────────────────────── Frame-Binary
-- ⊢ binary(op, v) : Nat ⇒ result(op)
| binary : ⊢ᵥ v ∶ .nat → ⊢ᶠ .binary op v p ∶ .nat ⇒ op.result

inductive StackHasType : List Frame → Ty → Ty → Prop where

-- ─────────────────── Stack-Empty
-- ⊢ [] : τ ⇒ τ
| nil : ⊢ᵏ [] ∶ τ ⇒ τ

-- ⊢ k : τ ⇒ σ    ⊢ κ : σ ⇒ υ
-- ──────────────────────────── Stack-Cons
-- ⊢ k :: κ : τ ⇒ υ
| cons : ⊢ᶠ k ∶ τ ⇒ σ → ⊢ᵏ κ ∶ σ ⇒ υ → ⊢ᵏ k :: κ ∶ τ ⇒ υ

inductive ControlHasType : Control → Ty → Prop where

-- ρ ⊨ Γ    Γ ⊢ e : τ
-- ─────────────────── Control-Expr
-- ⊢ ⟨ρ, e⟩ : τ
| expr : ρ ⊨ Γ → Γ ⊢ e ∶ τ → ⊢ᶜ .expr ρ e ∶ τ

-- ⊢ v : τ
-- ─────────────────── Control-Value
-- ⊢ value(v) : τ
| value : ⊢ᵥ v ∶ τ → ⊢ᶜ .value v ∶ τ

inductive MachineHasType : Machine → Ty → Prop where

-- ⊢ c : τ    ⊢ κ : τ ⇒ σ
-- ─────────────────────── Machine
-- ⊢ ⟨c, κ⟩ : σ
| mk : ⊢ᶜ c ∶ τ → ⊢ᵏ κ ∶ τ ⇒ σ → ⊢ₘ ⟨c, κ⟩ ∶ σ

end LambdaCalculus
