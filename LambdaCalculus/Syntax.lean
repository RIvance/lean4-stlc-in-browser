prelude
import Init.Data.String
import Init.Data.ToString
import Init.Data.Array
import Init.Control.State

/-! Named syntax for a simply typed language with unit, booleans, naturals, and fixed points. -/

namespace LambdaCalculus

/-- Zero-based positions, with UTF-16 columns for browser editors. -/
structure Position where
  line : Nat := 0
  column : Nat := 0
deriving Repr, BEq, Inhabited

structure Span where
  start : Position := {}
  stop : Position := {}
deriving Repr, BEq, Inhabited

inductive Ty where
  | unit
  | nat
  | bool
  | arr (τ σ : Ty)
deriving Repr, DecidableEq, BEq, Inhabited

scoped infixr:60 " ⟶ " => Ty.arr

def Ty.pretty : Ty → String
  | .unit => "Unit"
  | .nat => "Nat"
  | .bool => "Bool"
  | τ ⟶ σ =>
    let domain := match τ with
      | _ ⟶ _ => "(" ++ τ.pretty ++ ")"
      | _ => τ.pretty
    domain ++ " → " ++ σ.pretty

instance : ToString Ty := ⟨Ty.pretty⟩

inductive BinOp where
  | add | sub | mul | eq | lt
deriving Repr, BEq, Inhabited

def BinOp.result : BinOp → Ty
  | .eq | .lt => .bool
  | _ => .nat

def BinOp.pretty : BinOp → String
  | .add => "+"
  | .sub => "−"
  | .mul => "*"
  | .eq => "=="
  | .lt => "<"

inductive Expr where
  | var (p : Span) (x : String)
  | unit (p : Span)
  | nat (p : Span) (n : Nat)
  | bool (p : Span) (b : Bool)
  | lam (p : Span) (x : String) (τ : Ty) (e : Expr)
  | app (p : Span) (e₁ e₂ : Expr)
  | letE (p : Span) (x : String) (e₁ e₂ : Expr)
  | fix (p : Span) (x : String) (τ : Option Ty) (e : Expr)
  | seq (p : Span) (e₁ e₂ : Expr)
  | ite (p : Span) (e₁ e₂ e₃ : Expr)
  | bin (p : Span) (op : BinOp) (e₁ e₂ : Expr)
deriving Repr, Inhabited

/-- A persistent definition or an expression, independent of any user interface. -/
inductive Command where
  | define (p : Span) (x : String) (e : Expr)
  | expr (e : Expr)
deriving Repr, Inhabited

def Expr.span : Expr → Span
  | .var p _ | .unit p | .nat p _ | .bool p _ | .lam p _ _ _ | .app p _ _
  | .letE p _ _ _ | .fix p _ _ _ | .seq p _ _ | .ite p _ _ _ | .bin p _ _ _ => p

/-- Declarations scope over the rest of the program; a final declaration returns unit. -/
def programExpr : List Command → Expr
  | [] => .unit {}
  | .expr e :: [] => e
  | .expr e₁ :: commands =>
    let e₂ := programExpr commands
    .seq ⟨e₁.span.start, e₂.span.stop⟩ e₁ e₂
  | .define p x e₁ :: commands =>
    let e₂ := if commands.isEmpty then .unit ⟨p.stop, p.stop⟩ else programExpr commands
    .letE ⟨p.start, e₂.span.stop⟩ x e₁ e₂

def Expr.pretty : Expr → String
  | .var _ x => x
  | .unit _ => "()"
  | .nat _ n => toString n
  | .bool _ b => toString b
  | .lam _ x τ e => "((" ++ x ++ ": " ++ τ.pretty ++ ") ⇒ " ++ e.pretty ++ ")"
  | .app _ e₁ e₂ => e₁.pretty ++ "(" ++ e₂.pretty ++ ")"
  | .letE _ x e₁ e₂ => "(let " ++ x ++ " = " ++ e₁.pretty ++ " in " ++ e₂.pretty ++ ")"
  | .fix _ x τ e =>
    let binder := τ.map (fun τ => "(" ++ x ++ ": " ++ τ.pretty ++ ")") |>.getD x
    "(fix " ++ binder ++ " ⇒ " ++ e.pretty ++ ")"
  | .seq _ e₁ e₂ => "{ " ++ e₁.pretty ++ "\n" ++ e₂.pretty ++ " }"
  | .ite _ e₁ e₂ e₃ => "(if " ++ e₁.pretty ++ " then " ++ e₂.pretty ++ " else " ++ e₃.pretty ++ ")"
  | .bin _ op e₁ e₂ => "(" ++ e₁.pretty ++ " " ++ op.pretty ++ " " ++ e₂.pretty ++ ")"

structure Diagnostic where
  phase : String
  message : String
  span : Span
deriving Repr, Inhabited

def Diagnostic.pretty (d : Diagnostic) : String :=
  s!"{d.phase} at {d.span.start.line + 1}:{d.span.start.column + 1}: {d.message}"

end LambdaCalculus
