import App.Json
import App.Repl

private def usage : String :=
  "Usage: lambdacalculus [--json] [--check] [FILE]\n"
  ++ "       lambdacalculus --repl [--quiet]\n"
  ++ "Read a program from FILE or standard input; --repl starts an interactive session."

private structure Options where
  json : Bool := false
  checkOnly : Bool := false
  file : Option String := none
  repl : Bool := false
  quiet : Bool := false

private def options : List String → Options → Except String Options
  | [], opts => .ok opts
  | "--json" :: args, opts => options args { opts with json := true }
  | "--check" :: args, opts => options args { opts with checkOnly := true }
  | "--repl" :: args, opts => options args { opts with repl := true }
  | "--quiet" :: args, opts => options args { opts with quiet := true }
  | arg :: args, opts =>
    if arg.startsWith "-" then .error s!"Unknown or incomplete option: {arg}"
    else if opts.file.isSome then .error "Expected at most one input file."
    else options args { opts with file := some arg }

def main (args : List String) : IO UInt32 := do
  if args == ["--help"] then IO.println usage; return 0
  let .ok opts := options args {} | do
    let .error message := options args {} | return 2
    (← IO.getStderr).putStrLn (message ++ "\n" ++ usage)
    return 2
  try
    if opts.repl then
      if opts.json || opts.checkOnly || opts.file.isSome then
        (← IO.getStderr).putStrLn "--repl cannot be combined with --json, --check, or a file."
        return (2 : UInt32)
      App.repl (← IO.getStdin) (← IO.getStdout) (!opts.quiet)
      return (0 : UInt32)
    if opts.quiet then
      (← IO.getStderr).putStrLn "--quiet requires --repl."
      return (2 : UInt32)
    let source ← match opts.file with
      | some path => IO.FS.readFile path
      | none => (← IO.getStdin).readToEnd
    let result := LambdaCalculus.process source opts.checkOnly
    if opts.json then IO.println (App.resultJson result)
    else match result with
      | none => (← IO.getStderr).putStrLn "Evaluation does not terminate."
      | some (.error d) => (← IO.getStderr).putStrLn d.pretty
      | some (.ok r) =>
        IO.println s!"{(r.value.map LambdaCalculus.Value.pretty).getD "✓"} : {r.type}"
        if !opts.checkOnly then IO.println s!"{r.steps} machine steps"
    return if result matches some (.ok _) then 0 else 1
  catch e =>
    (← IO.getStderr).putStrLn s!"I/O error: {e}"
    return 2
