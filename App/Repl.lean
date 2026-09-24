import LambdaCalculus

/-! A terminal REPL using only Lean's standard IO library and the pure language API. -/

namespace App

open LambdaCalculus

def replHelp : String :=
  "Enter an expression, let x = expression, or def f (x: Nat) = expression for recursion.\n"
  ++ ":type EXPR   check a type without evaluation\n"
  ++ ":env         show visible bindings\n"
  ++ ":reset       clear all bindings\n"
  ++ ":load FILE   submit a file and keep its top-level bindings\n"
  ++ ":{ and :}    begin and end a multiline submission\n"
  ++ ":help        show this help\n"
  ++ ":quit        exit (also :q or end of input)"

private def render (r : Result) : String :=
  s!"{(r.value.map Value.pretty).getD "✓"} : {r.type}"

private def submit (s : Session) (source : String) (fuel : Nat) (output : IO.FS.Stream) : IO Session := do
  match s.submit source fuel with
  | .error d => output.putStrLn d.pretty; return s
  | .ok (s', r) => output.putStrLn (render r); return s'

private def environment (s : Session) (output : IO.FS.Stream) : IO Unit := do
  let mut names : List String := []
  for b in s.bindings do
    unless names.contains b.name do
      output.putStrLn s!"{b.name} = {b.value.pretty} : {b.type}"
      names := b.name :: names
  if names.isEmpty then output.putStrLn "No bindings."

/-- Streams make the REPL usable with a terminal, a pipe, or a Lean test harness. -/
def repl (input output : IO.FS.Stream) (fuel : Nat := 100000) (prompts : Bool := true) : IO Unit := do
  if prompts then output.putStrLn "STLC in Lean. Enter :help for commands."
  let mut session : Session := {}
  let mut multiline : Option String := none
  let mut running := true
  while running do
    if prompts then
      output.putStr (if multiline.isSome then "…  " else "λ> ")
      output.flush
    let line ← input.getLine
    if line.isEmpty then
      if multiline.isSome then output.putStrLn "Unfinished multiline input: expected :}."
      running := false
    else
      let command := line.trimAscii.toString
      if let some source := multiline then
        if command == ":}" then
          session ← submit session source fuel output
          multiline := none
        else multiline := some (source ++ line)
      else if command.isEmpty then pure ()
      else if command == ":quit" || command == ":q" then running := false
      else if command == ":help" then output.putStrLn replHelp
      else if command == ":{" then multiline := some ""
      else if command == ":reset" then
        session := {}
        output.putStrLn "Bindings cleared."
      else if command == ":env" then environment session output
      else if command.startsWith ":type " then
        match session.check (command.drop 6).toString with
        | .ok r => output.putStrLn r.type.pretty
        | .error d => output.putStrLn d.pretty
      else if command.startsWith ":load " then
        try
          let source ← IO.FS.readFile (command.drop 6).toString
          session ← submit session source fuel output
        catch e => output.putStrLn s!"I/O error: {e}"
      else if command.startsWith ":" then output.putStrLn "Unknown command. Enter :help for commands."
      else session ← submit session line fuel output

end App
