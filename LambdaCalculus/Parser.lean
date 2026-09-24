prelude
import LambdaCalculus.Syntax

/-!
A lexer and recursive-descent parser written in Lean. Arrows have Unicode and
ASCII spellings. Application accepts `f x y`, `f(x)(y)`, and adjacent `f(x, y)`;
parameter lists such as `(x: Nat, y: Nat) ⇒ e` expand into curried functions.
Named definitions accept the same typed parameters before `=`.
-/

namespace LambdaCalculus

structure Token where
  text : String
  span : Span
deriving Repr, Inhabited

private def advancePosition (p : Position) (c : Char) : Position :=
  if c == '\n' then ⟨p.line + 1, 0⟩
  else ⟨p.line, p.column + if c.toNat > 0xffff then 2 else 1⟩

private def nameStart (c : Char) : Bool :=
  c.isAlpha || c == '_' || (0x370 ≤ c.toNat && c.toNat ≤ 0x3ff)

private def nameContinue (c : Char) : Bool := nameStart c || c.isDigit || c == '\''

private def keywords : List String :=
  ["let", "def", "fix", "in", "if", "then", "else", "true", "false", "Unit", "Nat", "Bool"]

private partial def skipBlock (cs : List Char) (p start : Position) (depth : Nat)
  : Except Diagnostic (List Char × Position)
:= do
  match cs with
  | [] => .error ⟨"Parse error", "Unterminated block comment.", ⟨start, p⟩⟩
  | '/' :: '*' :: cs => skipBlock cs ⟨p.line, p.column + 2⟩ start (depth + 1)
  | '*' :: '/' :: cs =>
    let p' := { p with column := p.column + 2 }
    if depth == 1 then return (cs, p') else skipBlock cs p' start (depth - 1)
  | c :: cs => skipBlock cs (advancePosition p c) start depth

private partial def lexLoop (cs : List Char) (p : Position) (tokens : Array Token)
  : Except Diagnostic (Array Token)
:= do
  if tokens.size ≥ 2048 then
    .error ⟨"Resource limit", "Source exceeds the 2048 token limit.", ⟨p, p⟩⟩
  else
    match cs with
    | [] => return tokens.push ⟨"", ⟨p, p⟩⟩
    | '/' :: '/' :: cs =>
      let (comment, rest) := cs.span (· != '\n')
      lexLoop rest ⟨p.line, p.column + 2 + comment.foldl (fun n c => n + if c.toNat > 0xffff then 2 else 1) 0⟩ tokens
    | '/' :: '*' :: cs =>
      let (rest, p') ← skipBlock cs ⟨p.line, p.column + 2⟩ p 1
      lexLoop rest p' tokens
    | c :: rest =>
      if c.isWhitespace then lexLoop rest (advancePosition p c) tokens
      else if nameStart c || c.isDigit then
        let predicate := if c.isDigit then Char.isDigit else nameContinue
        let (tail, rest) := rest.span predicate
        let text := String.ofList (c :: tail)
        let p' := (c :: tail).foldl advancePosition p
        lexLoop rest p' (tokens.push ⟨text, ⟨p, p'⟩⟩)
      else
        let (text, rest, count) := match c, rest with
          | '=', '>' :: rest => ("⇒", rest, 2)
          | '-', '>' :: rest => ("→", rest, 2)
          | '=', '=' :: rest => ("==", rest, 2)
          | '−', rest => ("-", rest, 1)
          | c, rest => (String.singleton c, rest, 1)
        let p' := { p with column := p.column + count }
        if ["(", ")", "{", "}", ",", ":", "⇒", "→", "=", "+", "-", "*", "<", "=="].contains text then
          lexLoop rest p' (tokens.push ⟨text, ⟨p, p'⟩⟩)
        else .error ⟨"Parse error", s!"Unexpected character '{c}'.", ⟨p, p'⟩⟩

def tokenize (source : String) : Except Diagnostic (Array Token) :=
  if source.utf8ByteSize > 65536 then
    .error ⟨"Resource limit", "Source exceeds the 64 KiB limit.", {}⟩
  else lexLoop ((source.replace "\r\n" "\n").replace "\r" "\n").toList {} #[]

private structure ParserState where
  tokens : Array Token
  index : Nat := 0
  layout : Bool := true

private abbrev Parser := StateT ParserState (Except Diagnostic)

private def peek : Parser Token := do return (← get).tokens[(← get).index]!

private def take : Parser Token := do
  let t ← peek
  modify fun s => { s with index := s.index + 1 }
  return t

private def fail (message : String) : Parser α := do
  throw ⟨"Parse error", message, (← peek).span⟩

private def expect (text : String) : Parser Token := do
  let t ← peek
  if t.text == text then take
  else fail s!"Expected '{text}', found {if t.text.isEmpty then "end of input" else "'" ++ t.text ++ "'"}."

private def isIdentifier (text : String) : Bool :=
  text.toList.head?.any nameStart && !keywords.contains text

private def identifier : Parser Token := do
  let t ← peek
  if isIdentifier t.text then take
  else fail "Expected a variable name."

private def startsSimpleAtom (text : String) : Bool :=
  isIdentifier text || text == "true" || text == "false" || text.toList.head?.any Char.isDigit

/-- Token positions distinguish adjacent calls from whitespace or comment-separated arguments. -/
private def nextIsAdjacent : Parser Bool := do
  let s ← get
  return s.index > 0 && s.tokens[s.index - 1]!.span.stop == s.tokens[s.index]!.span.start

private def lineBreakBefore : Parser Bool := do
  let s ← get
  return s.index > 0 && s.tokens[s.index - 1]!.span.stop.line < s.tokens[s.index]!.span.start.line

private def withLayout (layout : Bool) (action : Parser α) : Parser α := do
  let previous := (← get).layout
  modify fun s => { s with layout }
  let result ← action
  modify fun s => { s with layout := previous }
  return result

private def stopsSequence (text : String) : Bool :=
  ["", "}", ")", ",", "in", "then", "else"].contains text

private def checkNesting (depth : Nat) : Parser Unit := do
  if depth == 0 then throw ⟨"Resource limit", "Syntax nesting exceeds the 256 level limit.", (← peek).span⟩

private partial def parseTy (depth : Nat) : Parser Ty := do
  checkNesting depth
  let t ← take
  let τ ← match t.text with
    | "Unit" => pure Ty.unit
    | "Nat" => pure Ty.nat
    | "Bool" => pure Ty.bool
    | "(" => do
      let τ ← parseTy (depth - 1)
      let _ ← expect ")"
      pure τ
    | _ => throw ⟨"Parse error", "Expected a type: Unit, Nat, Bool, or a function type.", t.span⟩
  if (← peek).text == "→" then
    let _ ← take
    return τ ⟶ (← parseTy (depth - 1))
  else return τ

private structure Parameter where
  start : Position
  name : String
  type : Ty

/-- Parse a nonempty typed parameter group after its opening parenthesis. -/
private partial def parseParameters (depth : Nat) (start : Position) : Parser (List Parameter) := do
  checkNesting depth
  let x ← identifier
  let _ ← expect ":"
  let τ ← parseTy (depth - 1)
  let parameters ← if (← peek).text == "," then do
      let _ ← take
      parseParameters (depth - 1) (← peek).span.start
    else do
      let _ ← expect ")"
      pure []
  return ⟨start, x.text, τ⟩ :: parameters

private partial def parseDefParameters (depth : Nat) : Parser (List Parameter) := do
  if (← peek).text != "(" then return []
  let t ← take
  let parameters ← parseParameters depth t.span.start
  return parameters ++ (← parseDefParameters (depth - parameters.length))

private def abstractParameters (parameters : List Parameter) (e : Expr) : Expr :=
  parameters.foldr (fun p e => .lam ⟨p.start, e.span.stop⟩ p.name p.type e) e

private def binaryInfo (text : String) : Option (BinOp × Nat) :=
  match text with
  | "==" => some (.eq, 10)
  | "<" => some (.lt, 10)
  | "+" => some (.add, 20)
  | "-" => some (.sub, 20)
  | "*" => some (.mul, 30)
  | _ => none

mutual
  private partial def parseExpr (depth : Nat) : Parser Expr := do
    checkNesting depth
    let t ← peek
    if t.text == "let" || t.text == "def" then
      let (p, x, e₁) ← parseBinding depth
      let e₂ ← if (← peek).text == "in" then do
          let _ ← take
          parseExpr (depth - 1)
        else if (← peek).text == "" || (← peek).text == "}" then
          pure (.unit ⟨p.stop, p.stop⟩)
        else if ← lineBreakBefore then
          pure (programExpr (← parseStatements (depth - 1)))
        else fail "Expected 'in' or a newline after the binding."
      return .letE ⟨p.start, e₂.span.stop⟩ x e₁ e₂
    else if t.text == "fix" then
      let _ ← take
      let (x, τ) ← if (← peek).text == "(" then do
          let _ ← take
          let x ← identifier
          let _ ← expect ":"
          let τ ← parseTy (depth - 1)
          let _ ← expect ")"
          pure (x.text, some τ)
        else do
          let x ← identifier
          pure (x.text, none)
      let _ ← expect "⇒"
      let e ← parseExpr (depth - 1)
      return .fix ⟨t.span.start, e.span.stop⟩ x τ e
    else if t.text == "if" then
      let _ ← take
      let e₁ ← parseExpr (depth - 1)
      let _ ← expect "then"
      let e₂ ← parseExpr (depth - 1)
      let _ ← expect "else"
      let e₃ ← parseExpr (depth - 1)
      return .ite ⟨t.span.start, e₃.span.stop⟩ e₁ e₂ e₃
    else parseBinary depth 0

  private partial def parseBinding (depth : Nat) : Parser (Span × String × Expr) := do
    checkNesting depth
    let t ← take
    let x ← identifier
    let parameters ← if t.text == "def" then parseDefParameters (depth - 1) else pure []
    let depth := depth - parameters.length - 1
    let annotation ← if t.text == "def" && (← peek).text == ":" then do
        let _ ← take
        let τ ← parseTy depth
        pure (some (parameters.foldr (fun p σ => p.type ⟶ σ) τ))
      else pure none
    let _ ← expect "="
    let e ← withLayout true (parseExpr depth)
    let e := abstractParameters parameters e
    let p := ⟨t.span.start, e.span.stop⟩
    return (p, x.text, if t.text == "def" then .fix p x.text annotation e else e)

  private partial def parseStatements (depth : Nat) : Parser (List Command) := do
    checkNesting depth
    let t ← peek
    if t.text == "" || t.text == "}" then return []
    let command ← if t.text == "let" || t.text == "def" then do
        let (p, x, e₁) ← parseBinding depth
        if (← peek).text == "in" then
          let _ ← take
          let e₂ ← parseExpr (depth - 1)
          pure (.expr (.letE ⟨p.start, e₂.span.stop⟩ x e₁ e₂))
        else if (← peek).text == "" || (← peek).text == "}" || (← lineBreakBefore) then
          pure (.define p x e₁)
        else fail "Expected 'in' or a newline after the binding."
      else pure (.expr (← parseExpr depth))
    if stopsSequence (← peek).text then return [command]
    unless ← lineBreakBefore do fail "Expected a newline between statements."
    return command :: (← parseStatements (depth - 1))

  private partial def parseBinary (depth minimum : Nat) : Parser Expr := do
    checkNesting depth
    let e ← parseAtom depth
    let e ← parseApplications depth e
    parseOperators depth minimum e

  private partial def parseOperators (depth minimum : Nat) (e₁ : Expr) : Parser Expr := do
    match binaryInfo (← peek).text with
    | some (op, precedence) =>
      if precedence < minimum then return e₁
      let _ ← take
      let e₂ ← parseBinary (depth - 1) (precedence + 1)
      parseOperators depth minimum (.bin ⟨e₁.span.start, e₂.span.stop⟩ op e₁ e₂)
    | none => return e₁

  private partial def parseApplications (depth : Nat) (e₁ : Expr) : Parser Expr := do
    if (← get).layout && (← lineBreakBefore) then return e₁
    let t ← peek
    if t.text == "(" then
      let adjacent ← nextIsAdjacent
      let _ ← take
      if (← peek).text == ")" then
        let close ← take
        parseApplications depth (.app ⟨e₁.span.start, close.span.stop⟩ e₁ (.unit close.span))
      else parseApplications depth (← withLayout false (parseArguments depth adjacent e₁))
    else if t.text == "{" || (startsSimpleAtom t.text && !(← nextIsAdjacent)) then
      let e₂ ← parseAtom (depth - 1)
      parseApplications depth (.app ⟨e₁.span.start, e₂.span.stop⟩ e₁ e₂)
    else return e₁

  private partial def parseArguments (depth : Nat) (adjacent : Bool) (e₁ : Expr) : Parser Expr := do
    let e₂ ← parseExpr (depth - 1)
    if (← peek).text == "," then
      unless adjacent do fail "Comma-separated arguments require '(' immediately after the function."
      let _ ← take
      parseArguments depth adjacent (.app ⟨e₁.span.start, e₂.span.stop⟩ e₁ e₂)
    else
      let close ← expect ")"
      return .app ⟨e₁.span.start, close.span.stop⟩ e₁ e₂

  private partial def parseLambda (depth : Nat) (start : Position) : Parser Expr := do
    let parameters ← parseParameters depth start
    let _ ← expect "⇒"
    let e ← parseExpr (depth - parameters.length)
    return abstractParameters parameters e

  private partial def parseAtom (depth : Nat) : Parser Expr := do
    checkNesting depth
    let t ← peek
    if t.text == "(" then
      let _ ← take
      if (← peek).text == ")" then
        let close ← take
        return .unit ⟨t.span.start, close.span.stop⟩
      let s ← get
      let isLambda := (s.tokens[s.index + 1]?).any (·.text == ":")
      if isLambda then parseLambda depth t.span.start
      else
        let e ← withLayout false (parseExpr (depth - 1))
        let _ ← expect ")"
        return e
    else if t.text == "{" then
      let _ ← take
      let commands ← withLayout true (parseStatements (depth - 1))
      let close ← expect "}"
      return if commands.isEmpty then .unit ⟨t.span.start, close.span.stop⟩ else programExpr commands
    else if t.text == "true" || t.text == "false" then
      let _ ← take
      return .bool t.span (t.text == "true")
    else if let some n := t.text.toNat? then
      let _ ← take
      return .nat t.span n
    else
      let x ← identifier
      return .var x.span x.text
end

/-- Also bounds left-associated call/operator chains before recursive type inference. -/
private def withinDepth : Nat → Expr → Bool
  | 0, _ => false
  | _ + 1, .var _ _ | _ + 1, .unit _ | _ + 1, .nat _ _ | _ + 1, .bool _ _ => true
  | n + 1, .lam _ _ _ e | n + 1, .fix _ _ _ e => withinDepth n e
  | n + 1, .app _ e₁ e₂ | n + 1, .letE _ _ e₁ e₂ | n + 1, .seq _ e₁ e₂ | n + 1, .bin _ _ e₁ e₂ =>
    withinDepth n e₁ && withinDepth n e₂
  | n + 1, .ite _ e₁ e₂ e₃ => withinDepth n e₁ && withinDepth n e₂ && withinDepth n e₃

private def finish (e : Expr) (s : ParserState) : Except Diagnostic Expr := do
  let t := s.tokens[s.index]!
  if t.text != "" then .error ⟨"Parse error", s!"Unexpected token '{t.text}'.", t.span⟩
  else if !withinDepth 256 e then .error ⟨"Resource limit", "Expression exceeds the 256 level limit.", e.span⟩
  else return e

def parseProgram (source : String) : Except Diagnostic (List Command) := do
  let tokens ← tokenize source
  let (commands, s) ← parseStatements 256 { tokens }
  let _ ← finish (programExpr commands) s
  return commands

def parse (source : String) : Except Diagnostic Expr := do
  return programExpr (← parseProgram source)

/-- Preserve a single declaration; combine a larger program into a scoped expression. -/
def parseCommand (source : String) : Except Diagnostic Command := do
  match ← parseProgram source with
  | [command] => return command
  | commands => return .expr (programExpr commands)

end LambdaCalculus
