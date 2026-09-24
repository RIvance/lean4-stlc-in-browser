prelude
import LambdaCalculus.Typing

/-!
A call-by-value closure machine. A continuation represents pending work explicitly,
so evaluation uses constant host stack space. Fuel counts machine transitions and
is an execution limit, independent of the language's types and terms.
-/

namespace LambdaCalculus

mutual
  inductive Value where
    | unit
    | nat (n : Nat)
    | bool (b : Bool)
    | closure (x : String) (τ : Ty) (e : Expr) (ρ : List (String × EnvEntry))
  deriving Inhabited

  /-- Recursive entries represent suspended fixed points, not object-language values. -/
  inductive EnvEntry where
    | value (v : Value)
    | recursive (x : String) (e : Expr) (ρ : List (String × EnvEntry))
  deriving Inhabited
end

abbrev Env := List (String × EnvEntry)

def Value.pretty : Value → String
  | .unit => "()"
  | .nat n => toString n
  | .bool b => toString b
  | .closure x τ _ _ => s!"⟨closure ({x}: {τ}) ⇒ …⟩"

inductive Frame where
  | argument (ρ : Env) (e : Expr) (p : Span)
  | call (v : Value) (p : Span)
  | binding (ρ : Env) (x : String) (e : Expr)
  | discard (ρ : Env) (e : Expr)
  | branch (ρ : Env) (e₁ e₂ : Expr) (p : Span)
  | operand (ρ : Env) (op : BinOp) (e : Expr) (p : Span)
  | binary (op : BinOp) (v : Value) (p : Span)

inductive Control where
  | expr (ρ : Env) (e : Expr)
  | value (v : Value)

structure Machine where
  control : Control
  stack : List Frame := []

def applyBinOp (op : BinOp) (v₁ v₂ : Value) (p : Span) : Except Diagnostic Value :=
  match v₁, v₂ with
  | .nat n, .nat m => .ok (match op with
    | .add => .nat (n + m)
    | .sub => .nat (n - m)
    | .mul => .nat (n * m)
    | .eq => .bool (n == m)
    | .lt => .bool (n < m))
  | _, _ => .error ⟨"Runtime error", "Arithmetic requires natural numbers.", p⟩

def Machine.step (s : Machine) : Except Diagnostic Machine := do
  match s.control with
  | .expr ρ e =>
    match e with
    | .var p x =>
      match lookup x ρ with
      | some (.value v) => return ⟨.value v, s.stack⟩
      | some (.recursive x e ρ) => return ⟨.expr ((x, .recursive x e ρ) :: ρ) e, s.stack⟩
      | none => .error ⟨"Runtime error", s!"Unbound variable '{x}'.", p⟩
    | .unit _ => return ⟨.value .unit, s.stack⟩
    | .nat _ n => return ⟨.value (.nat n), s.stack⟩
    | .bool _ b => return ⟨.value (.bool b), s.stack⟩
    | .lam _ x τ e => return ⟨.value (.closure x τ e ρ), s.stack⟩
    | .app p e₁ e₂ => return ⟨.expr ρ e₁, .argument ρ e₂ p :: s.stack⟩
    | .letE _ x e₁ e₂ => return ⟨.expr ρ e₁, .binding ρ x e₂ :: s.stack⟩
    | .fix _ x _ e => return ⟨.expr ((x, .recursive x e ρ) :: ρ) e, s.stack⟩
    | .seq _ e₁ e₂ => return ⟨.expr ρ e₁, .discard ρ e₂ :: s.stack⟩
    | .ite p e₁ e₂ e₃ => return ⟨.expr ρ e₁, .branch ρ e₂ e₃ p :: s.stack⟩
    | .bin p op e₁ e₂ => return ⟨.expr ρ e₁, .operand ρ op e₂ p :: s.stack⟩
  | .value v =>
    match s.stack with
    | [] => return s
    | k :: κ =>
      match k with
      | .argument ρ e p => return ⟨.expr ρ e, .call v p :: κ⟩
      | .call (.closure x _ e ρ) _ => return ⟨.expr ((x, .value v) :: ρ) e, κ⟩
      | .call _ p => .error ⟨"Runtime error", "Cannot call a non-function.", p⟩
      | .binding ρ x e => return ⟨.expr ((x, .value v) :: ρ) e, κ⟩
      | .discard ρ e => return ⟨.expr ρ e, κ⟩
      | .branch ρ e₁ e₂ p =>
        match v with
        | .bool b => return ⟨.expr ρ (if b then e₁ else e₂), κ⟩
        | _ => .error ⟨"Runtime error", "A condition must be a boolean.", p⟩
      | .operand ρ op e p => return ⟨.expr ρ e, .binary op v p :: κ⟩
      | .binary op v₁ p => return ⟨.value (← applyBinOp op v₁ v p), κ⟩

def runMachine (fuel : Nat) (s : Machine) (steps : Nat := 0) : Except Diagnostic (Value × Nat) :=
  match s.control, s.stack with
  | .value v, [] => .ok (v, steps)
  | _, _ =>
    match fuel with
    | 0 => .error ⟨"Resource limit", "Evaluation exceeded the machine step limit.", {}⟩
    | fuel + 1 => do runMachine fuel (← s.step) (steps + 1)

def evaluateIn (ρ : Env) (e : Expr) (fuel : Nat := 100000) : Except Diagnostic (Value × Nat) :=
  runMachine fuel ⟨.expr ρ e, []⟩

def evaluate (e : Expr) (fuel : Nat := 100000) : Except Diagnostic (Value × Nat) :=
  evaluateIn [] e fuel

end LambdaCalculus
