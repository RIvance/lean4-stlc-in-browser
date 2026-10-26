import Metatheory.Safety

/-! General recursion preserves safety without implying termination. -/

namespace LambdaCalculus

/-- The source term `fix (x : τ) ⇒ x` is well typed at every type τ. -/
theorem selfFixedPointTyped : Γ ⊢ .fix p x (some τ) (.var q x) ∶ τ := by {
  exact .fix (Or.inr rfl) (.var (by simp [lookup]))
}

private theorem expressionSelfLoopDiverges
  (h : Machine.step ⟨.expr ρ e, κ⟩ = .ok ⟨.expr ρ e, κ⟩) :
  runMachine ⟨.expr ρ e, κ⟩ steps = none
:= by {
  have impossible : ∀ k r, runMachine ⟨.expr ρ e, κ⟩ k ≠ some r := by {
    intro k r hr
    refine (
      runMachine.partial_correctness
        (motive := fun s _ _ => s = ⟨.expr ρ e, κ⟩ → False)
        ?_ ⟨.expr ρ e, κ⟩ k r hr rfl
    )
    intro run ih s k r heq hs
    subst s
    simp only [h] at heq
    exact ih ⟨.expr ρ e, κ⟩ (k + 1) r heq rfl
  }
  cases hr : runMachine ⟨.expr ρ e, κ⟩ steps with
  | none => rfl
  | some r => exact False.elim (impossible steps r hr)
}

/-- This well-typed term has no completed evaluation. -/
theorem selfFixedPointDiverges : evaluateIn ρ (.fix p x (some τ) (.var q x)) = none := by {
  let ρ' := (x, EnvEntry.recursive x (.var q x) ρ) :: ρ
  have h : Machine.step ⟨.expr ρ' (.var q x), []⟩ = .ok ⟨.expr ρ' (.var q x), []⟩ := by {
    simp only [Machine.step, ρ', lookup, beq_self_eq_true, ↓reduceIte]
    rfl
  }
  unfold evaluateIn
  rw [runMachine.eq_def]
  exact expressionSelfLoopDiverges (steps := 1) h
}

end LambdaCalculus
