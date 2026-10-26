import LambdaCalculus.Semantics.Typing

/-! Type safety of the executable closure machine, including recursive entries. -/

namespace LambdaCalculus

theorem lookupEnvHasType (hρ : ρ ⊨ Γ) (hx : lookup x Γ = some τ) :
  ∃ r, lookup x ρ = some r ∧ (⊢ᵣ r ∶ τ)
:= by {
  induction Γ generalizing ρ with
  | nil => simp [lookup] at hx
  | cons binding Γ ih => {
    rcases binding with ⟨y, σ⟩
    cases hρ with | cons hr hρ =>
    cases hxy : (x == y) with
    | true => {
      simp only [lookup, hxy, ↓reduceIte] at hx
      have hστ := Option.some.inj hx
      subst σ
      exact ⟨_, by simp only [lookup, hxy, ↓reduceIte], hr⟩
    }
    | false => {
      simp only [lookup, hxy, Bool.false_eq_true, ↓reduceIte] at hx ⊢
      exact ih hρ hx
    }
  }
}

theorem applyBinOpSafe (h₁ : ⊢ᵥ v₁ ∶ .nat) (h₂ : ⊢ᵥ v₂ ∶ .nat) :
  ∃ v, applyBinOp op v₁ v₂ p = .ok v ∧ (⊢ᵥ v ∶ op.result)
:= by {
  cases h₁
  cases h₂
  cases op <;> exact ⟨_, rfl, by constructor⟩
}

theorem stepSafe (hs : ⊢ₘ s ∶ τ) : ∃ s', s.step = .ok s' ∧ (⊢ₘ s' ∶ τ) := by {
  cases hs with | mk hc hκ =>
  cases hc with
  | expr hρ he => {
    cases he with
    | var hx => {
      obtain ⟨r, hr, hτ⟩ := lookupEnvHasType hρ hx
      cases hτ with
      | value hv => exact ⟨_, by { simp only [Machine.step, hr]; rfl }, .mk (.value hv) hκ⟩
      | recursive hρ' he => {
        refine ⟨_, ?_, .mk (.expr (.cons (.recursive hρ' he) hρ') he) hκ⟩
        simp only [Machine.step, hr]
        rfl
      }
    }
    | unit => exact ⟨_, rfl, .mk (.value .unit) hκ⟩
    | nat => exact ⟨_, rfl, .mk (.value .nat) hκ⟩
    | bool => exact ⟨_, rfl, .mk (.value .bool) hκ⟩
    | lam he => exact ⟨_, rfl, .mk (.value (.closure hρ he)) hκ⟩
    | app h₁ h₂ => exact ⟨_, rfl, .mk (.expr hρ h₁) (.cons (.argument hρ h₂) hκ)⟩
    | letE h₁ h₂ => exact ⟨_, rfl, .mk (.expr hρ h₁) (.cons (.binding hρ h₂) hκ)⟩
    | fix _ he => exact ⟨_, rfl, .mk (.expr (.cons (.recursive hρ he) hρ) he) hκ⟩
    | seq h₁ h₂ => exact ⟨_, rfl, .mk (.expr hρ h₁) (.cons (.discard hρ h₂) hκ)⟩
    | ite h₁ h₂ h₃ => exact ⟨_, rfl, .mk (.expr hρ h₁) (.cons (.branch hρ h₂ h₃) hκ)⟩
    | bin h₁ h₂ => exact ⟨_, rfl, .mk (.expr hρ h₁) (.cons (.operand hρ h₂) hκ)⟩
  }
  | value hv => {
    cases hκ with
    | nil => exact ⟨_, rfl, .mk (.value hv) .nil⟩
    | cons hk hκ => {
      cases hk with
      | argument hρ he => exact ⟨_, rfl, .mk (.expr hρ he) (.cons (.call hv) hκ)⟩
      | call hf => {
        cases hf with | closure hρ he =>
        exact ⟨_, rfl, .mk (.expr (.cons (.value hv) hρ) he) hκ⟩
      }
      | binding hρ he => exact ⟨_, rfl, .mk (.expr (.cons (.value hv) hρ) he) hκ⟩
      | discard hρ he => exact ⟨_, rfl, .mk (.expr hρ he) hκ⟩
      | branch hρ h₁ h₂ => {
        cases hv with | @bool b =>
        cases b
        · exact ⟨_, rfl, .mk (.expr hρ h₂) hκ⟩
        · exact ⟨_, rfl, .mk (.expr hρ h₁) hκ⟩
      }
      | operand hρ he => exact ⟨_, rfl, .mk (.expr hρ he) (.cons (.binary hv) hκ)⟩
      | @binary v₁ op p h₁ => {
        obtain ⟨v, heq, hτ⟩ := applyBinOpSafe (op := op) (p := p) h₁ hv
        exact ⟨_, by { simp only [Machine.step, heq]; rfl }, .mk (.value hτ) hκ⟩
      }
    }
  }
}

theorem preservation (hs : ⊢ₘ s ∶ τ) (hstep : s.step = .ok s') : ⊢ₘ s' ∶ τ := by {
  obtain ⟨s'', heq, hτ⟩ := stepSafe hs
  cases heq.symm.trans hstep
  exact hτ
}

theorem progress (hs : ⊢ₘ s ∶ τ) : ∃ s', s.step = .ok s' := by {
  obtain ⟨s', hstep, _⟩ := stepSafe hs
  exact ⟨s', hstep⟩
}

theorem terminalHasType (hs : ⊢ₘ ⟨.value v, []⟩ ∶ τ) : ⊢ᵥ v ∶ τ := by {
  cases hs with | mk hc hκ =>
  cases hκ
  cases hc with | value hv => exact hv
}

/-- Every completed execution of a typed machine returns a value of its result type. -/
theorem runMachineResultSafe (hr : runMachine s steps = some r) (hs : ⊢ₘ s ∶ τ) :
  match (generalizing := false) r with
  | .ok (v, _) => ⊢ᵥ v ∶ τ
  | .error _ => False
:= by {
  refine (
    runMachine.partial_correctness
      (motive := fun s _ r => (⊢ₘ s ∶ τ) → match r with
        | .ok (v, _) => ⊢ᵥ v ∶ τ
        | .error _ => False
      )
      ?_ s steps r hr hs
  )
  intro run ih s k r h hs
  obtain ⟨s', hstep, hs'⟩ := stepSafe hs
  rcases s with ⟨c, κ⟩
  cases c with
  | expr ρ e => {
    simp only [hstep] at h
    exact ih s' (k + 1) r h hs'
  }
  | value v => {
    cases κ with
    | nil => cases h; exact terminalHasType hs
    | cons F κ => {
      simp only [hstep] at h
      exact ih s' (k + 1) r h hs'
    }
  }
}

/-- A typed execution may diverge, but it cannot return a runtime error. -/
theorem runMachineSafe (hs : ⊢ₘ s ∶ τ) :
  match runMachine s steps with
  | none => True
  | some (.ok (v, _)) => ⊢ᵥ v ∶ τ
  | some (.error _) => False
:= by {
  cases hr : runMachine s steps with
  | none => trivial
  | some r => {
    cases r with
    | error d => exact runMachineResultSafe hr hs
    | ok r => rcases r with ⟨v, k⟩; exact runMachineResultSafe hr hs
  }
}

theorem evaluateInSafe (hρ : ρ ⊨ Γ) (he : Γ ⊢ e ∶ τ) :
  match evaluateIn ρ e with
  | none => True
  | some (.ok (v, _)) => ⊢ᵥ v ∶ τ
  | some (.error _) => False
:= by {
  exact runMachineSafe (.mk (.expr hρ he) .nil)
}

theorem evaluateSafe (he : [] ⊢ e ∶ τ) :
  match evaluate e with
  | none => True
  | some (.ok (v, _)) => ⊢ᵥ v ∶ τ
  | some (.error _) => False
:= by {
  exact evaluateInSafe .nil he
}

theorem evaluatePreservesTyping (he : [] ⊢ e ∶ τ) (h : evaluate e = some (.ok (v, steps))) : ⊢ᵥ v ∶ τ := by {
  have hsafe := evaluateSafe he
  rw [h] at hsafe
  exact hsafe
}

theorem evaluateNoRuntimeError (he : [] ⊢ e ∶ τ) : evaluate e ≠ some (.error d) := by {
  intro h
  have hsafe := evaluateSafe he
  rw [h] at hsafe
  exact hsafe
}

end LambdaCalculus
