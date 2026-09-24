import LambdaCalculus.Typing

/-!
The certificate checker implements the declarative rules exactly. Every typing
derivation supplies enough fixed-point hints for certification, and every
successful public inference result has a declarative derivation.
-/

namespace LambdaCalculus

theorem certifyComplete (he : Γ ⊢ e ∶ τ) :
  ∃ hints, ∀ rest, certify Γ e (hints ++ rest) = some (⟨τ, he⟩, rest)
:= by {
  induction he with
  | var hx => {
    refine ⟨[], ?_⟩
    intro rest
    simp only [List.nil_append, certify]
    split
    · rename_i σ hσ
      have hτ := Option.some.inj (hσ.symm.trans hx)
      subst σ
      rfl
    · rename_i hnone
      rw [hx] at hnone
      contradiction
  }
  | unit => exact ⟨[], by { intro rest; rfl }⟩
  | nat => exact ⟨[], by { intro rest; rfl }⟩
  | bool => exact ⟨[], by { intro rest; rfl }⟩
  | lam he ih => {
    obtain ⟨hints, ih⟩ := ih
    exact ⟨hints, by { intro rest; simp [certify, ih] }⟩
  }
  | app h₁ h₂ ih₁ ih₂ => {
    obtain ⟨hints₁, ih₁⟩ := ih₁
    obtain ⟨hints₂, ih₂⟩ := ih₂
    exact ⟨hints₁ ++ hints₂, by { intro rest; simp [certify, List.append_assoc, ih₁, ih₂] }⟩
  }
  | letE h₁ h₂ ih₁ ih₂ => {
    obtain ⟨hints₁, ih₁⟩ := ih₁
    obtain ⟨hints₂, ih₂⟩ := ih₂
    exact ⟨hints₁ ++ hints₂, by { intro rest; simp [certify, List.append_assoc, ih₁, ih₂] }⟩
  }
  | @fix a τ x Γ e p ha he ih => {
    obtain ⟨hints, ih⟩ := ih
    exact ⟨τ :: hints, by { intro rest; simp [certify, ha, ih] }⟩
  }
  | seq h₁ h₂ ih₁ ih₂ => {
    obtain ⟨hints₁, ih₁⟩ := ih₁
    obtain ⟨hints₂, ih₂⟩ := ih₂
    exact ⟨hints₁ ++ hints₂, by { intro rest; simp [certify, List.append_assoc, ih₁, ih₂] }⟩
  }
  | ite h₁ h₂ h₃ ih₁ ih₂ ih₃ => {
    obtain ⟨hints₁, ih₁⟩ := ih₁
    obtain ⟨hints₂, ih₂⟩ := ih₂
    obtain ⟨hints₃, ih₃⟩ := ih₃
    refine ⟨hints₁ ++ hints₂ ++ hints₃, ?_⟩
    intro rest
    simp [certify, List.append_assoc, ih₁, ih₂, ih₃]
  }
  | bin h₁ h₂ ih₁ ih₂ => {
    obtain ⟨hints₁, ih₁⟩ := ih₁
    obtain ⟨hints₂, ih₂⟩ := ih₂
    exact ⟨hints₁ ++ hints₂, by { intro rest; simp [certify, List.append_assoc, ih₁, ih₂] }⟩
  }
}

theorem inferSound (h : infer Γ e = .ok τ) : Γ ⊢ e ∶ τ := by {
  unfold infer at h
  cases hc : inferCertified Γ e with
  | error d => rw [hc] at h; cases h
  | ok c => {
    rw [hc] at h
    cases h
    exact c.typing
  }
}

theorem inferProgramSound (h : inferProgram Γ cs = .ok checked) : Γ ⊢ᵖ checked := by {
  unfold inferProgram at h
  cases hc : inferProgramCertified Γ cs with
  | error d => rw [hc] at h; cases h
  | ok c => {
    rw [hc] at h
    cases h
    exact c.typing
  }
}

theorem inferProgramErases (h : inferProgram Γ cs = .ok checked) : checked.map Prod.fst = cs := by {
  unfold inferProgram at h
  cases hc : inferProgramCertified Γ cs with
  | error d => rw [hc] at h; cases h
  | ok c => {
    rw [hc] at h
    cases h
    exact c.erases
  }
}

/-- A final expression supplies the result type; declarations and empty programs return unit. -/
def programResultType : List (Command × Ty) → Ty
  | [(.expr _, τ)] => τ
  | _ :: cs => programResultType cs
  | [] => .unit

theorem programExprHasType (h : Γ ⊢ᵖ cs) :
  Γ ⊢ programExpr (cs.map Prod.fst) ∶ programResultType cs
:= by {
  induction h with
  | nil => exact .unit
  | @define Γ e τ x cs p he hcs ih => {
    cases cs with
    | nil => exact .letE he .unit
    | cons c cs => exact .letE he ih
  }
  | @expr Γ e τ cs he hcs ih => {
    cases cs with
    | nil => exact he
    | cons c cs => exact .seq he ih
  }
}

end LambdaCalculus
