prelude
import LambdaCalculus

/-! JSON presentation at the application boundary; the language library does not import this module. -/

namespace App

open LambdaCalculus

private def hexDigit (n : Nat) : Char := Char.ofNat (if n < 10 then 48 + n else 87 + n)

def jsonString (s : String) : String :=
  "\"" ++ String.join (s.toList.map fun c =>
    if c == '"' then "\\\""
    else if c == '\\' then "\\\\"
    else if c.toNat < 32 then "\\u00" ++ String.ofList [hexDigit (c.toNat / 16), hexDigit (c.toNat % 16)]
    else String.singleton c) ++ "\""

private def positionJson (p : Position) : String :=
  "{\"line\":" ++ toString p.line ++ ",\"character\":" ++ toString p.column ++ "}"

def diagnosticJson (d : Diagnostic) : String :=
  "{\"phase\":" ++ jsonString d.phase ++ ",\"message\":" ++ jsonString d.message
  ++ ",\"range\":{\"start\":" ++ positionJson d.span.start ++ ",\"end\":" ++ positionJson d.span.stop ++ "}}"

def resultJson : Except Diagnostic Result → String
  | .error d => "{\"status\":\"error\",\"diagnostic\":" ++ diagnosticJson d ++ "}"
  | .ok r =>
    "{\"status\":\"success\",\"type\":" ++ jsonString r.type.pretty
    ++ ",\"term\":" ++ jsonString r.term.pretty
    ++ ",\"value\":" ++ (r.value.map (jsonString ∘ Value.pretty)).getD "null"
    ++ ",\"steps\":" ++ toString r.steps ++ "}"

end App
