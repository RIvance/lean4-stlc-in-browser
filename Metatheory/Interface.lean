import Metatheory.Typing
import Metatheory.Safety
import LambdaCalculus.Session

/-! The public pure API returns declaratively typed syntax and values. -/

namespace LambdaCalculus

def ResultHasType (Γ : Ctx) (r : Result) : Prop :=
  (Γ ⊢ r.term ∶ r.type) ∧ ∀ v, r.value = some v → (⊢ᵥ v ∶ r.type)

theorem checkSound {s : Session} (h : s.check source = .ok r) : ResultHasType s.context r := by {
  unfold Session.check at h
  cases he : parse source with
  | error d => rw [he] at h; cases h
  | ok e => {
    rw [he] at h
    change (do pure (⟨← infer s.context e, e, none, 0⟩ : Result)) = .ok r at h
    cases hτ : infer s.context e with
    | error d => rw [hτ] at h; cases h
    | ok τ => {
      rw [hτ] at h
      cases h
      exact ⟨inferSound hτ, by { intro v hv; cases hv }⟩
    }
  }
}

theorem runSound {s : Session} (hρ : s.environment ⊨ s.context) (h : s.run source fuel = .ok r) :
  ResultHasType s.context r
:= by {
  unfold Session.run at h
  cases he : parse source with
  | error d => rw [he] at h; cases h
  | ok e => {
    rw [he] at h
    change (
      do
        let τ ← infer s.context e
        let (v, steps) ← evaluateIn s.environment e fuel
        pure (⟨τ, e, some v, steps⟩ : Result)
    ) = .ok r at h
    cases hτ : infer s.context e with
    | error d => rw [hτ] at h; cases h
    | ok τ => {
      rw [hτ] at h
      cases hv : evaluateIn s.environment e fuel with
      | error d => rw [hv] at h; cases h
      | ok result => {
        rcases result with ⟨v, steps⟩
        rw [hv] at h
        cases h
        have heτ := inferSound hτ
        have hsafe := evaluateInSafe (fuel := fuel) hρ heτ
        rw [hv] at hsafe
        exact ⟨heτ, by { intro v' h'; cases h'; exact hsafe }⟩
      }
    }
  }
}

/-- This is the entry point shared by the native CLI and the Wasm adapter. -/
theorem processSound (h : process source fuel checkOnly = .ok r) : ResultHasType [] r := by {
  cases checkOnly
  · exact runSound (s := {}) .nil h
  · exact checkSound (s := {}) h
}

theorem inferredEvaluationSafe (hρ : ρ ⊨ Γ) (h : infer Γ e = .ok τ) :
  match evaluateIn ρ e fuel with
  | .ok (v, _) => ⊢ᵥ v ∶ τ
  | .error d => d = ⟨"Resource limit", "Evaluation exceeded the machine step limit.", {}⟩
:= by {
  exact evaluateInSafe hρ (inferSound h)
}

end LambdaCalculus
