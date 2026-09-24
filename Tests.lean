import LambdaCalculus
import App.Json
import App.Repl
import Lean

open LambdaCalculus App

structure TestCase where
  name : String
  source : String
  type : String := ""
  value : String := ""
  error : String := ""
  fuel : Nat := 100000
  checkOnly : Bool := false
deriving Lean.ToJson

private def success (name source type value : String) : TestCase := ⟨name, source, type, value, "", 100000, false⟩
private def failure (name source error : String) : TestCase := ⟨name, source, "", "", error, 100000, false⟩

def cases : Array TestCase := #[
  success "natural" "42" "Nat" "42",
  success "boolean" "true" "Bool" "true",
  success "unit" "()" "Unit" "()",
  success "unit argument" "((u: Unit) ⇒ 42)()" "Nat" "42",
  success "empty block" "{}" "Unit" "()",
  success "comment only file" "// no expressions\n/* done */" "Unit" "()",
  success "newline bindings" "let x = 40\nlet y = 2\nx + y" "Nat" "42",
  success "blank lines and comments" "let x = 40 // first\n\n/* gap */\nlet y = 2\nx + y\n" "Nat" "42",
  success "CRLF bindings" "let x = 40\r\nlet y = 2\r\nx + y" "Nat" "42",
  success "CR bindings" "let x = 40\rlet y = 2\rx + y" "Nat" "42",
  success "trailing file binding" "let x = 42" "Unit" "()",
  success "trailing file binding newline" "let x = 42\n" "Unit" "()",
  success "trailing block binding" "{ 42\nlet x = 1 }" "Unit" "()",
  success "trailing recursive binding" "def id = (x: Nat) ⇒ x" "Unit" "()",
  success "file sequence" "1\ntrue\n42" "Nat" "42",
  success "block sequence" "{ 1\ntrue\n42\n}" "Nat" "42",
  success "block binding scope" "let x = { let y = 40\ny + 2 }\nx" "Nat" "42",
  success "block argument" "((x: Nat) ⇒ x + 1) { let y = 40\ny + 1 }" "Nat" "42",
  success "multiline application grouping" "let f = (x: Nat) ⇒ x + 1\n(f\n41)" "Nat" "42",
  success "newlines separate applications" "let f = (x: Nat) ⇒ x + 1\nf\n41" "Nat" "41",
  success "operator continuation" "let x = 20 +\n22\nx" "Nat" "42",
  success "leading operator continuation" "let x = 20\n+ 22\nx" "Nat" "42",
  success "explicit in newline" "let x = 40 in\nx + 2" "Nat" "42",
  success "implicit nested expression binding" "if true then let x = 40\nx + 2 else 0" "Nat" "42",
  success "recursive factorial"
    "def factorial = (n: Nat) ⇒ { if n == 0 then 1 else n * factorial (n − 1) }\nfactorial 5" "Nat" "120",
  success "explicit recursive binding"
    "def sum = (n: Nat) ⇒ if n == 0 then 0 else n + sum (n − 1) in sum 10" "Nat" "55",
  success "direct fixed point"
    "(fix f ⇒ (n: Nat) ⇒ if n == 0 then 1 else n * f (n − 1))(5)" "Nat" "120",
  success "recursive value" "def x = if true then 42 else x\nx" "Nat" "42",
  success "annotated recursive value" "def x: Nat = 42 in x" "Nat" "42",
  success "recursive type constrained by later use"
    "def loop = (n: Nat) ⇒ loop n\nif true then 42 else loop 0" "Nat" "42",
  success "recursive lexical capture"
    "let k = 2\ndef sum = (n: Nat) ⇒ if n == 0 then k else k + sum (n − 1)\nlet k = 99\nsum 2" "Nat" "6",
  success "recursive name shadowed by parameter" "def f = (f: Nat) ⇒ f\nf 42" "Nat" "42",
  success "named factorial"
    "def factorial (n: Nat) =\n  if n == 0 then 1 else n * factorial (n − 1)\nfactorial 5" "Nat" "120",
  success "trailing named definition" "def id (x: Nat) = x\n" "Unit" "()",
  success "named definition with explicit in"
    "def sum (n: Nat) = if n == 0 then 0 else n + sum (n − 1) in sum 10" "Nat" "55",
  success "recursive parameter groups"
    "def sum (n: Nat) (acc: Nat) = if n == 0 then acc else sum(n − 1, acc + n)\nsum(10, 0)" "Nat" "55",
  success "named higher order parameters"
    "def twice (f: Nat → Nat, x: Nat) = f (f x)\ndef increment (n: Nat) = n + 1\ntwice(increment, 40)"
    "Nat" "42",
  success "mixed parameter groups" "def add (x: Nat, y: Nat) (z: Nat) = x + y + z in add(20, 21, 1)" "Nat" "42",
  success "named partial application"
    "def add (x: Nat, y: Nat) = x + y\nlet increment = add 1\nincrement 41" "Nat" "42",
  success "named block body and lexical capture"
    ("let k = 2\ndef sum (n: Nat) = {\n  let next = n − 1\n"
    ++ "  if n == 0 then k else k + sum next\n}\nlet k = 99\nsum 2") "Nat" "6",
  success "named unit parameter" "def answer (u: Unit) = 42\nanswer()" "Nat" "42",
  success "named parameter shadowing" "def f (x: Nat) (x: Bool) = x\nf(42, false)" "Bool" "false",
  success "named parameter shadows recursive name" "def f (f: Nat) = f\nf 42" "Nat" "42",
  success "named result annotation"
    "def sum (n: Nat, acc: Nat): Nat = if n == 0 then acc else sum(n − 1, acc + n)\nsum(10, 0)" "Nat" "55",
  success "named function result annotation"
    "def add (x: Nat): Nat → Nat = (y: Nat) ⇒ x + y in add(20, 22)" "Nat" "42",
  success "named recursive result annotation" "def loop (n: Nat): Nat = loop n" "Unit" "()",
  success "named recursion constrained by later use"
    "def loop (n: Nat) = loop n\nif true then 42 else loop 0" "Nat" "42",
  success "nested named definition" "if true then def id (x: Nat) = x in id 42 else 0" "Nat" "42",
  success "recursive certificate preorder"
    ("def number: Nat = 41\ndef flag: Bool = true\n"
    ++ "def apply (f: Nat → Nat, x: Nat) = f x\n"
    ++ "if flag then apply((n: Nat) ⇒ n + 1, number) else 0") "Nat" "42",
  success "nested recursive certificates"
    ("def outer (n: Nat) = {\n  def flag (b: Bool) = b\n"
    ++ "  def inner (m: Nat) = if m == 0 then n else inner (m − 1)\n"
    ++ "  if flag true then inner 2 else 0\n}\nouter 42") "Nat" "42",
  success "precedence" "2 + 3 * 4" "Nat" "14",
  success "left associativity" "9 − 3 − 2" "Nat" "4",
  success "truncated subtraction" "3 − 8" "Nat" "0",
  success "comparison precedence" "2 + 3 * 4 == 14" "Bool" "true",
  success "less than" "3 < 2" "Bool" "false",
  success "conditional" "if false then 1 else 2" "Nat" "2",
  success "nested conditional" "if true then if false then 1 else 2 else 3" "Nat" "2",
  success "unicode lambda" "((x: Nat) ⇒ x + 1)(41)" "Nat" "42",
  success "ASCII input aliases" "((f: Nat -> Nat) => f(4))((x: Nat) => x * x)" "Nat" "16",
  success "higher order" "let twice = (f: Nat → Nat) ⇒ (x: Nat) ⇒ f(f(x)) in twice((n: Nat) ⇒ n + 1)(40)" "Nat" "42",
  success "curried calls" "((x: Nat) ⇒ (y: Nat) ⇒ x + y)(20)(22)" "Nat" "42",
  success "whitespace higher order"
    ("// Functions can accept and return other functions.\n"
    ++ "let twice = (f: Nat → Nat) ⇒ (x: Nat) ⇒ f (f x) in\n"
    ++ "let increment = (n: Nat) ⇒ n + 1 in\ntwice increment 40") "Nat" "42",
  success "curried whitespace application" "((x: Nat) ⇒ (y: Nat) ⇒ x + y) 20 22" "Nat" "42",
  success "mixed application associates left" "((x: Nat) ⇒ (y: Nat) ⇒ x + y) 20(22)" "Nat" "42",
  success "spaced parenthesized calls" "((x: Nat) ⇒ (y: Nat) ⇒ x + y) (20)(22)" "Nat" "42",
  success "application precedence" "let double = (x: Nat) ⇒ x * 2 in double 2 + 3 * double 4" "Nat" "28",
  success "grouped application argument" "((x: Nat) ⇒ x) (20 + 22)" "Nat" "42",
  success "comment separated application" "let f = (x: Nat) ⇒ x + 1 in f/* argument */41" "Nat" "42",
  success "conditional application argument" "((x: Nat) ⇒ x + 1) (if true then 41 else 0)" "Nat" "42",
  success "let application argument" "((x: Nat) ⇒ x + 1) (let x = 40 in x + 1)" "Nat" "42",
  success "application before keyword" "if ((b: Bool) ⇒ b) true then 42 else 0" "Nat" "42",
  success "comma calls" "((x: Nat) ⇒ (y: Nat) ⇒ x + y)(20, 22)" "Nat" "42",
  success "parenthesized function comma call" "(((x: Nat) ⇒ (y: Nat) ⇒ x + y))(20, 22)" "Nat" "42",
  success "multiple parameters"
    ("let twice = (f: Nat → Nat, x: Nat) ⇒ f (f x) in\n"
    ++ "let increment = (n: Nat) ⇒ n + 1 in\ntwice(increment, 40)") "Nat" "42",
  success "comma call partial application"
    "let add = (x: Nat, y: Nat, z: Nat) ⇒ x + y + z in let f = add(20, 21) in f 1" "Nat" "42",
  success "grouped parameter type" "((f: (Nat → Nat), x: Nat) ⇒ f x)((n: Nat) ⇒ n + 1, 41)" "Nat" "42",
  success "multiple parameter shadowing" "((x: Nat, x: Bool) ⇒ x)(42, false)" "Bool" "false",
  success "multiple parameter closure" "((x: Nat, y: Nat) ⇒ x + y) 20" "Nat → Nat" "⟨closure (y: Nat) ⇒ …⟩",
  success "multiple parameter capture"
    "let x = 10 in let f = (y: Nat, z: Nat) ⇒ x + y + z in let x = 99 in f(1, 1)" "Nat" "12",
  success "lexical capture" "let x = 10 in let f = (y: Nat) ⇒ x + y in let x = 99 in f(2)" "Nat" "12",
  success "binder shadowing" "((x: Nat) ⇒ ((x: Bool) ⇒ x)(false))(42)" "Bool" "false",
  success "let shadowing" "let x = 1 in let x = x + 1 in x" "Nat" "2",
  success "function branch" "(if true then (x: Nat) ⇒ x * x else (x: Nat) ⇒ x + 1)(6)" "Nat" "36",
  success "returned closure" "(x: Nat) ⇒ x" "Nat → Nat" "⟨closure (x: Nat) ⇒ …⟩",
  success "arrow associativity" "(f: Nat → Bool → Nat) ⇒ f" "(Nat → Bool → Nat) → Nat → Bool → Nat" "⟨closure (f: Nat → Bool → Nat) ⇒ …⟩",
  success "unicode names" "let α = 41 in ((β: Nat) ⇒ α + β)(1)" "Nat" "42",
  success "nested comments" "/* outer /* inner */ done */ 6 * 7 // answer" "Nat" "42",
  success "big literal" "99999999999999999999999999" "Nat" "99999999999999999999999999",
  success "wasm tagged integer boundary" "2147483647 + 2" "Nat" "2147483649",
  success "big multiplication" "99999999999999999999999999 * 10000000000000000000000000" "Nat"
    "999999999999999999999999990000000000000000000000000",
  failure "unbound variable" "missing" "Type error",
  failure "wrong argument" "((x: Nat) ⇒ x)(false)" "Type error",
  failure "bad branch" "if true then 1 else false" "Type error",
  failure "bad condition" "if 1 then 2 else 3" "Type error",
  failure "bad arithmetic" "false + 1" "Type error",
  failure "non-function call" "1(2)" "Type error",
  failure "no recursion" "let f = (x: Nat) ⇒ f(x) in f(1)" "Type error",
  failure "dangling let in" "let x = 1 in" "Parse error",
  failure "dangling let in newline" "let x = 1 in\n" "Parse error",
  failure "dangling block let in" "{ let x = 1 in\n}" "Parse error",
  failure "dangling def in" "def f = (x: Nat) ⇒ x in\n" "Parse error",
  failure "dangling final declaration in" "let x = 1\nlet y = 2 in" "Parse error",
  failure "binding requires separator" "let x = 1 let y = 2" "Parse error",
  failure "block scope does not escape" "{ let x = 42\nx }\nx" "Type error",
  failure "explicit in scope does not escape" "let x = 42 in x\nx" "Type error",
  failure "discarded expression is checked" "false + 1\n42" "Type error",
  failure "recursive argument mismatch" "def f = (n: Nat) ⇒ if n == 0 then 0 else f true\nf 0" "Type error",
  failure "recursive result mismatch" "def f = (n: Nat) ⇒ if n == 0 then true else f (n − 1) + 1\nf 0" "Type error",
  failure "recursive annotation mismatch" "def x: Nat = false\nx" "Type error",
  failure "recursive occurs check" "def f = f f" "Type error",
  failure "ambiguous recursive type" "def f = (n: Nat) ⇒ f n" "Type error",
  failure "named parameter annotation required" "def f (x) = x" "Parse error",
  failure "named empty parameter group" "def f () = 42" "Parse error",
  failure "named trailing parameter comma" "def f (x: Nat,) = x" "Parse error",
  failure "named unclosed parameter group" "def f (x: Nat = x" "Parse error",
  failure "named missing body" "def f (x: Nat) =\n" "Parse error",
  failure "named dangling in" "def f (x: Nat) = x in\n" "Parse error",
  failure "named parameter scope does not escape" "def f (x: Nat) = x\nx" "Type error",
  failure "named recursive argument mismatch" "def f (n: Nat) = if n == 0 then 0 else f true\nf 0" "Type error",
  failure "named result annotation mismatch" "def f (x: Nat): Bool = x" "Type error",
  failure "named ambiguous recursive type" "def f (n: Nat) = f n" "Type error",
  { (failure "named recursive divergence" "def f (n: Nat): Nat = f n in f 0" "Resource limit") with fuel := 100 },
  { (failure "recursive divergence" "def f: Nat → Nat = (n: Nat) ⇒ f n in f 0" "Resource limit") with fuel := 100 },
  { (failure "strict recursive binding" "def x: Nat = x\n42" "Resource limit") with fuel := 100 },
  { (failure "strict block sequence" "{ fix (x: Nat) ⇒ x\n42 }" "Resource limit") with fuel := 100 },
  failure "no self application" "(x: Nat) ⇒ x(x)" "Type error",
  failure "non-function whitespace application" "42 false" "Type error",
  failure "wrong whitespace argument" "((x: Nat) ⇒ x) false" "Type error",
  failure "wrong comma argument" "((x: Nat, y: Nat) ⇒ x + y)(20, false)" "Type error",
  failure "whole input" "42 then false" "Parse error",
  failure "adjacent literals are not whitespace application" "42false" "Parse error",
  failure "space before comma call" "((x: Nat, y: Nat) ⇒ x + y) (20, 22)" "Parse error",
  failure "newline before comma call" "((x: Nat, y: Nat) ⇒ x + y)\n(20, 22)" "Parse error",
  failure "comment before comma call" "((x: Nat, y: Nat) ⇒ x + y)/* gap */(20, 22)" "Parse error",
  failure "no tuples" "(20, 22)" "Parse error",
  failure "trailing argument comma" "((x: Nat) ⇒ x)(42,)" "Parse error",
  failure "missing argument" "((x: Nat, y: Nat) ⇒ x + y)(20,,22)" "Parse error",
  failure "trailing parameter comma" "(x: Nat,) ⇒ x" "Parse error",
  failure "missing parameter annotation" "(x: Nat, y) ⇒ x" "Parse error",
  failure "empty parameter list" "() ⇒ 42" "Parse error",
  failure "wrong unit argument" "((x: Nat) ⇒ x)()" "Type error",
  failure "missing annotation" "(x) ⇒ x" "Parse error",
  failure "unknown type" "(x: Anything) ⇒ x" "Parse error",
  failure "reserved binder" "let if = 1 in if" "Parse error",
  failure "unclosed comment" "1 /* never closed" "Parse error",
  success "empty input" "" "Unit" "()",
  failure "nul is not a terminator" ("42" ++ String.singleton (Char.ofNat 0) ++ "false") "Parse error",
  failure "UTF-16 columns" "/* 😀 */ false + 1" "Type error",
  failure "Windows newlines" "// heading\r\nfalse + 1" "Type error",
  failure "CR newlines" "// heading\rfalse + 1" "Type error",
  { (failure "zero fuel" "42" "Resource limit") with fuel := 0 },
  { (success "check without evaluation" "42" "Nat" "") with fuel := 0, checkOnly := true },
  failure "source size" (String.ofList (List.replicate 65537 ' ')) "Resource limit",
  failure "nesting limit" (String.ofList (List.replicate 257 '(') ++ "1" ++ String.ofList (List.replicate 257 ')')) "Resource limit",
  failure "token limit" (String.intercalate " + " (List.replicate 1025 "1")) "Resource limit",
  failure "left spine limit" (String.intercalate " + " (List.replicate 257 "1")) "Resource limit",
  failure "whitespace application depth" (String.intercalate " " (List.replicate 257 "f")) "Resource limit",
  failure "comma application depth" ("f(" ++ String.intercalate ", " (List.replicate 257 "1") ++ ")") "Resource limit",
  failure "multiple parameter depth"
    ("(" ++ String.intercalate ", " (List.replicate 257 "x: Nat") ++ ") ⇒ x") "Resource limit",
  failure "named parameter depth"
    ("def f (" ++ String.intercalate ", " (List.replicate 257 "x: Nat") ++ ") = x") "Resource limit",
  failure "named parameter group depth"
    ("def f " ++ String.intercalate " " (List.replicate 257 "(x: Nat)") ++ " = x") "Resource limit",
  failure "statement depth" (String.intercalate "\n" (List.replicate 257 "1")) "Resource limit",
  failure "block depth" (String.ofList (List.replicate 257 '{') ++ "1" ++ String.ofList (List.replicate 257 '}')) "Resource limit"
]

private def check (test : TestCase) : IO Unit := do
  let result := process test.source test.fuel test.checkOnly
  let valid := match result with
    | .error d => d.phase == test.error && !test.error.isEmpty
    | .ok r => test.error.isEmpty && r.type.pretty == test.type && (r.value.map Value.pretty).getD "" == test.value
  unless valid do throw <| IO.userError s!"{test.name}: {resultJson result}"
  if let .ok r := result then
    let roundTrip := process r.term.pretty test.fuel test.checkOnly
    let preserved := match roundTrip with
      | .ok r' => r.type == r'.type && r.steps == r'.steps && r.value.map Value.pretty == r'.value.map Value.pretty
      | .error _ => false
    unless preserved do throw <| IO.userError s!"Pretty-printer round trip failed: {test.name}"

private def checkCurrying : IO Unit := do
  let nested := "let twice = (f: Nat → Nat) ⇒ (x: Nat) ⇒ f(f(x)) in "
  let compact := "let twice = (f: Nat → Nat, x: Nat) ⇒ f (f x) in "
  let increment := "let increment = (n: Nat) ⇒ n + 1 in "
  let .ok expected := process (nested ++ increment ++ "twice(increment)(40)")
    | throw <| IO.userError "Curried baseline failed"
  let expectedResult := (expected.term.pretty, expected.type, expected.value.map Value.pretty, expected.steps)
  for declaration in [nested, compact] do
    for application in ["twice increment 40", "twice(increment, 40)", "twice(increment)(40)"] do
      let .ok actual := process (declaration ++ increment ++ application)
        | throw <| IO.userError s!"Curried syntax failed: {declaration}{application}"
      let actualResult := (actual.term.pretty, actual.type, actual.value.map Value.pretty, actual.steps)
      unless actualResult == expectedResult do
        throw <| IO.userError "Curried syntax did not preserve the term, type, value, and step count"
  for (source, column) in [("add(20, false)", 8), ("add 20 false", 7)] do
    let .error d := process ("let add = (x: Nat, y: Nat) ⇒ x + y in\n" ++ source)
      | throw <| IO.userError "Expected a curried argument diagnostic"
    unless d.span.start == ⟨1, column⟩ && d.span.stop == ⟨1, column + 5⟩ do
      throw <| IO.userError "Curried argument diagnostic has an incorrect source span"
  IO.println "6 curried syntax combinations preserve terms, types, values, and step counts."

private def checkDefParameters : IO Unit := do
  let definitions := [
    "def sum = (n: Nat) ⇒ (acc: Nat) ⇒ ",
    "def sum (n: Nat) (acc: Nat) = ",
    "def sum (n: Nat, acc: Nat) = "
  ]
  let annotatedDefinitions := [
    "def sum: Nat → Nat → Nat = (n: Nat) ⇒ (acc: Nat) ⇒ ",
    "def sum (n: Nat) (acc: Nat): Nat = ",
    "def sum (n: Nat, acc: Nat): Nat = "
  ]
  let suffix := "if n == 0 then acc else sum(n − 1, acc + n) in sum(10, 0)"
  for group in [definitions, annotatedDefinitions] do
    let .ok expected := process (group.head! ++ suffix)
      | throw <| IO.userError "Recursive definition baseline failed"
    let expectedResult := (expected.term.pretty, expected.type, expected.value.map Value.pretty, expected.steps)
    for declaration in group do
      let .ok actual := process (declaration ++ suffix)
        | throw <| IO.userError s!"Named parameter syntax failed: {declaration}"
      let actualResult := (actual.term.pretty, actual.type, actual.value.map Value.pretty, actual.steps)
      unless actualResult == expectedResult do
        throw <| IO.userError "Named parameters did not preserve the term, type, value, and step count"
  for (source, start, stop) in [
    ("def f (n: Nat) =\n  n + false\nf 0", (1, 6), (1, 11)),
    ("def f (n: Nat): Nat =\n  if n == 0 then 0 else f true\nf 0", (1, 26), (1, 30)),
    ("def f (n: Nat) = n in\n", (1, 0), (1, 0))
  ] do
    let .error d := process source | throw <| IO.userError "Expected a named parameter diagnostic"
    unless d.span.start == ⟨start.1, start.2⟩ && d.span.stop == ⟨stop.1, stop.2⟩ do
      throw <| IO.userError s!"Named parameter diagnostic has an incorrect source span: {repr d.span}"
  IO.println "6 recursive definition spellings preserve terms, types, values, and step counts."

private def transcript (input : String) (fuel : Nat := 100000) : IO String := do
  let source ← IO.mkRef ({ data := input.toUTF8 } : IO.FS.Stream.Buffer)
  let output ← IO.mkRef ({} : IO.FS.Stream.Buffer)
  App.repl (IO.FS.Stream.ofBuffer source) (IO.FS.Stream.ofBuffer output) fuel false
  return String.fromUTF8! (← output.get).data

private def checkTranscript (name input expected : String) (fuel : Nat := 100000) : IO Unit := do
  let output ← transcript input fuel
  unless output == expected do throw <| IO.userError s!"REPL {name}:\nExpected:\n{expected}\nFound:\n{output}"

private def checkRepl : IO Unit := do
  checkTranscript "state and lexical scope"
    ("let x = 10\nlet addX = (y: Nat) ⇒ x + y\nlet x = 99\naddX(2)\n:type addX\n"
    ++ "let x = false + 1\nx\nlet x = x + 1\n:env\n:reset\n:env\nx\n:quit\n42\n")
    ("() : Unit\n() : Unit\n() : Unit\n12 : Nat\nNat → Nat\n"
    ++ "Type error at 1:9: Expected Nat, found Bool.\n99 : Nat\n() : Unit\n"
    ++ "x = 100 : Nat\naddX = ⟨closure (y: Nat) ⇒ …⟩ : Nat → Nat\n"
    ++ "Bindings cleared.\nNo bindings.\nType error at 1:1: Unbound variable 'x'.\n")
  checkTranscript "multiline definition"
    ":{\nlet twice = (f: Nat → Nat) ⇒\n  (x: Nat) ⇒ f(f(x))\n:}\ntwice((x: Nat) ⇒ x + 1)(40)\n"
    "() : Unit\n42 : Nat\n"
  checkTranscript "curried syntax"
    ("let twice = (f: Nat → Nat, x: Nat) ⇒ f (f x)\nlet increment = (n: Nat) ⇒ n + 1\n"
    ++ "twice increment 40\ntwice(increment, 40)\ntwice(increment)(40)\n:type twice increment\n")
    "() : Unit\n() : Unit\n42 : Nat\n42 : Nat\n42 : Nat\nNat → Nat\n"
  checkTranscript "persistent recursion and redefinition"
    ("def factorial = (n: Nat) ⇒ if n == 0 then 1 else n * factorial (n − 1)\n"
    ++ "factorial 5\nlet saved = factorial\ndef factorial = (n: Nat) ⇒ 0\nsaved 4\nfactorial 4\n")
    "() : Unit\n120 : Nat\n() : Unit\n() : Unit\n24 : Nat\n0 : Nat\n"
  checkTranscript "named recursive definition"
    (":{\ndef factorial (n: Nat) =\n  if n == 0 then 1 else n * factorial (n − 1)\n:}\n"
    ++ ":type factorial\nfactorial 5\nlet saved = factorial\ndef factorial (n: Nat) = 0\nsaved 4\n"
    ++ "def add (x: Nat) (y: Nat): Nat = x + y\n:type add 20\nadd(20, 22)\n")
    "() : Unit\nNat → Nat\n120 : Nat\n() : Unit\n() : Unit\n24 : Nat\n() : Unit\nNat → Nat\n42 : Nat\n"
  checkTranscript "script bindings and private blocks"
    ":{\nlet x = 40\nlet y = 2\nx + y\n:}\nx\n:{\n{ let x = 0\nx }\n:}\nx\n"
    "42 : Nat\n40 : Nat\n0 : Nat\n40 : Nat\n"
  checkTranscript "batch rollback and shared fuel"
    ":{\nlet x = 42\n43\n:}\n:type x\n"
    ("Resource limit at 1:1: Evaluation exceeded the machine step limit.\n"
    ++ "Type error at 1:1: Unbound variable 'x'.\n") 1
  checkTranscript "recursive type constrained across a submission"
    ":{\ndef loop = (n: Nat) ⇒ loop n\nif true then 42 else loop 0\n:}\n:type loop\n"
    "42 : Nat\nNat → Nat\n"
  checkTranscript "ordinary let expression" "let x = 1 in x + 1\n:env\n" "2 : Nat\nNo bindings.\n"
  checkTranscript "failed definition and zero fuel"
    ":type 42\nlet x = 42\n:type x\n"
    ("Nat\nResource limit at 1:1: Evaluation exceeded the machine step limit.\n"
    ++ "Type error at 1:1: Unbound variable 'x'.\n") 0
  checkTranscript "unfinished multiline input" ":{\n42\n" "Unfinished multiline input: expected :}.\n"
  checkTranscript "invalid command" ":unknown\n:q\n42\n" "Unknown command. Enter :help for commands.\n"
  checkTranscript "help" ":help\n" (App.replHelp ++ "\n")
  IO.FS.withTempFile fun handle path => do
    handle.putStr "let answer = 42\n"
    handle.flush
    checkTranscript "load a file" s!":load {path}\nanswer + 1\n" "() : Unit\n43 : Nat\n"
  let s : Session := {}
  let .ok (s', _) := s.submit "let x = 42" | throw <| IO.userError "Pure session binding failed"
  unless s.bindings.isEmpty && s'.bindings.length == 1 do
    throw <| IO.userError "Session updates did not preserve the original immutable state"
  let .ok (_, r) := s'.submit "x + 1" | throw <| IO.userError "Pure session evaluation failed"
  unless r.value.map Value.pretty == some "43" do throw <| IO.userError "Pure session result is incorrect"
  IO.println "14 pure Lean REPL transcripts and immutable session checks passed."

def main (args : List String) : IO Unit := do
  if args == ["--corpus"] then IO.println (Lean.toJson cases).compress
  else
    for test in cases do check test
    let .error d := process "/* 😀 */ false + 1" | throw <| IO.userError "Expected a diagnostic"
    unless d.span.start.column == 9 && d.span.stop.column == 14 do
      throw <| IO.userError "Diagnostic columns are not UTF-16 offsets"
    for source in ["// heading\r\nfalse + 1", "// heading\rfalse + 1"] do
      let .error d := process source | throw <| IO.userError "Expected a diagnostic"
      unless d.span.start == ⟨1, 0⟩ && d.span.stop == ⟨1, 5⟩ do
        throw <| IO.userError "Diagnostic positions do not respect CR/CRLF newlines"
    IO.println s!"{cases.size} native tests passed, including successful pretty-printer round trips."
    checkCurrying
    checkDefParameters
    checkRepl
