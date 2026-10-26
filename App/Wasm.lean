prelude
import App.Json

/-! The WebAssembly C ABI is an adapter around the pure Lean library. -/

namespace App

@[export stlc_process]
def processJson (source : String) (checkOnly : Bool) : String :=
  resultJson (LambdaCalculus.process source checkOnly)

end App
