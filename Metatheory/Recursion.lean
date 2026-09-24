import Metatheory.Safety

/-! General recursion preserves safety without implying termination. -/

namespace LambdaCalculus

/-- The source term `fix (x : τ) ⇒ x` is well typed at every type τ. -/
theorem selfFixedPointTyped : Γ ⊢ .fix p x (some τ) (.var q x) ∶ τ := by {
  exact .fix (Or.inr rfl) (.var (by simp [lookup]))
}

private theorem expressionSelfLoopTimesOut
  (h : Machine.step ⟨.expr ρ e, κ⟩ = .ok ⟨.expr ρ e, κ⟩) :
  runMachine fuel ⟨.expr ρ e, κ⟩ steps
  = .error ⟨"Resource limit", "Evaluation exceeded the machine step limit.", {}⟩
:= by {
  induction fuel generalizing steps with
  | zero => rfl
  | succ fuel ih => simpa only [runMachine, h, Except.bind] using ih (steps := steps + 1)
}

/-- No finite evaluation budget can produce a value for this well-typed term. -/
theorem selfFixedPointTimesOut :
  evaluateIn ρ (.fix p x (some τ) (.var q x)) fuel
  = .error ⟨"Resource limit", "Evaluation exceeded the machine step limit.", {}⟩
:= by {
  let ρ' := (x, EnvEntry.recursive x (.var q x) ρ) :: ρ
  have h : Machine.step ⟨.expr ρ' (.var q x), []⟩ = .ok ⟨.expr ρ' (.var q x), []⟩ := by {
    simp only [Machine.step, ρ', lookup, beq_self_eq_true, ↓reduceIte]
    rfl
  }
  cases fuel with
  | zero => rfl
  | succ fuel => exact expressionSelfLoopTimesOut (fuel := fuel) (steps := 1) h
}

end LambdaCalculus
