# STLC in Lean (Compiles to WebAssembly)

A general purpose Lean programming experiment: a parser, type checker,
call-by-value interpreter with fixed points, persistent sessions, terminal REPL,
and build driver implemented in Lean. An independent browser adapter uses the supplied
`playground-core` and executes the compiled Lean program in WebAssembly.
All browser analysis and evaluation happen locally in workers; deployment
consists of static files.

```text
let twice = (f: Nat → Nat, x: Nat) ⇒ f (f x)
let increment = (n: Nat) ⇒ n + 1
twice increment 40
```

The result is `42 : Nat`.

The [metatheory](Metatheory/README.md) gives inductive typing rules over the same
syntax and proves inference soundness, interpreter progress and preservation,
and safety of the public API. `lake build` checks the proofs alongside the CLI.

## Run natively

Install [elan](https://github.com/leanprover/elan); `lean-toolchain` selects the
Lean compiler. No additional Lean packages are needed.

```sh
lake build
lake exe lambdacalculus examples/twice.stlc
lake exe lambdacalculus examples/factorial.stlc
lake exe lambdacalculus --check examples/twice.stlc
lake exe lambdacalculus --json examples/twice.stlc
lake exe lambdacalculus --repl
lake test
```

Omit the filename to read standard input. `--fuel N` sets the machine step
limit, including zero. Exit statuses are 0 for success, 1 for a language error,
and 2 for command-line or filesystem errors. `--check` parses and checks types
without evaluating. JSON results include the type, value, parsed expression,
step count, or a diagnostic with a UTF-16 source range.

## Pure Lean REPL

```text
λ> let x = 10
() : Unit
λ> let addX = (y: Nat) ⇒ x + y
() : Unit
λ> let x = 99
() : Unit
λ> addX(2)
12 : Nat
λ> :type addX
Nat → Nat
λ> :quit
```

`let x = e` creates a persistent binding; `def f = e` creates a recursive one.
A declaration returns `Unit`; use `:env` to inspect its bound value. Ordinary
`let x = e in e′` and brace blocks have local bindings. Multiline submissions
and loaded files keep their top-level declarations. A failed parse, type check,
or evaluation rolls back the entire submission. Closures retain the environment
in which they were defined, including their original recursive definitions
across redefinitions at the prompt.

| Command | Meaning |
| --- | --- |
| `:type e` | Infer an expression's type without evaluating it |
| `:env` | Show currently visible bindings |
| `:reset` | Clear the session |
| `:load FILE` | Submit a file and keep its top-level declarations |
| `:{` … `:}` | Enter a program over multiple lines |
| `:help` | Show help |
| `:quit`, `:q`, EOF | Exit |

`--repl --quiet` suppresses prompts for pipes and scripts; `--fuel N` controls
the shared evaluation budget for a submission. The REPL uses Lean's standard
streams and filesystem APIs. It requires neither Node.js nor WebAssembly.

## Use the core as a Lean library

`import LambdaCalculus` exposes immutable syntax, parsing, type inference,
evaluation, and persistent sessions. The library is pure Lean and has no IO,
JSON, C exports, CLI, or browser dependencies. Both frontends consume this API:

```lean
import LambdaCalculus
open LambdaCalculus

def exampleSession : Except Diagnostic String := do
  let (s, _) ← ({} : Session).submit "let x = 40"
  let (_, r) ← s.submit "x + 2"
  return (r.value.map Value.pretty).getD ""

#eval exampleSession  -- Except.ok "42"
```

`parse`, `parseProgram`, `parseCommand`, `infer`, `inferProgram`, `evaluate`, and
`evaluateIn` are also usable separately. `Session.check` and `Session.run` treat
the input as a scoped program; `Session.submit` also preserves its top-level
declarations. An environment contains values and suspended recursive entries.
The JSON encoder is in `App.Json`; terminal operations are in `App.Repl` and
`Main`; the C export is in `App.Wasm`. Nothing in `LambdaCalculus/` imports
these adapters. The Wasm build follows the imports of `App.Wasm`, so it does
not include the CLI or REPL.

## Build and open the playground

The build driver is **Lean**, in [`scripts/BuildWasm.lean`](scripts/BuildWasm.lean).
Install Emscripten, CMake, Make, Git, sha256sum, and Node.js ≥22.12, or use
the pinned Nix development shell:

```sh
nix develop
lean --run scripts/BuildWasm.lean --web
npm run dev --prefix web
```

Open the local URL printed by Vite. The `--web` option builds the Wasm module,
installs the locked npm dependencies, builds `playground-core`, and bundles
the application. Omit `--web` to rebuild just the interpreter. `JOBS=4` controls
build concurrency. The first build fetches the Lean runtime at the active
compiler's exact source revision and LibUV at its locked revision. Sources and
compilation are cached under `.lake/wasm/`; compiler and dependency changes
select a separate build directory automatically.

### Upgrade build dependencies

| Dependency | Version source | Upgrade |
| --- | --- | --- |
| Lean | `lean-toolchain` | Change the toolchain and rebuild; runtime sources, headers, and notices follow automatically. |
| LibUV | `libuv.tag` in `wasm/dependencies.json` | Change the tag, run the lock update command below, then rebuild. |
| Emscripten SDK used by CI | `emsdk.tag` in `wasm/dependencies.json` | Change the tag and update the lock; CI installs that release automatically. |
| Node.js used by CI and Nix | `.node-version` | Change the major version and re-enter the development shell; CI reads the same file. |
| Nix development tools | `flake.lock` | Run `nix flake update nixpkgs`, then re-enter `nix develop`. |
| Browser packages | The relevant `package.json` | Run `npm install --prefix web` or `npm install --prefix playground-core` to update its lock. |

After changing an external release tag, regenerate its resolved Git revisions:

```sh
lean --run scripts/BuildWasm.lean --update-deps
```

Commit `wasm/dependencies.json` and the generated `wasm/dependencies.lock.json`
together. Normal builds use the lock and reject stale entries; hashes and
version-specific download URLs never need hand editing. Repository addresses
live in the manifest, including `leanRepository` for a Lean fork or mirror.

To use the same [Emscripten SDK](https://emscripten.org/docs/getting_started/downloads.html)
as CI outside Nix:

```sh
lean --run scripts/BuildWasm.lean --setup-emsdk .lake/emsdk
source .lake/emsdk/emsdk_env.sh
lean --run scripts/BuildWasm.lean --web
```

The driver also accepts an already activated Emscripten installation, including
the version supplied by `flake.lock`. Its compiler identity participates in
cache invalidation. Dependency updates still need a build and test run to
check upstream compatibility.

### Preview and deploy

To preview the production output:

```sh
npm run preview --prefix web
```

Deploy the contents of `web/dist/` on a static HTTP(S) host that serves `.wasm`
as `application/wasm`. The application uses relative asset paths. No language
server, application backend, CDN, SharedArrayBuffer, or cross-origin isolation
headers are required. Opening `index.html` as a `file:` URL does not provide
the HTTP environment needed by module workers.

The editor provides example programs, syntax highlighting, automatic type
diagnostics, Run/Stop, parsed-expression inspection, and local persistence
through `playground-core`. Each file is an independent program; the entry
file is evaluated. The language has no input primitive or module imports.

## Language

Types are `Unit`, `Nat`, `Bool`, and function types `τ → σ`. Arrows associate
to the right. Every function parameter has an explicit type. Bindings are
monomorphic: `let` is nonrecursive, while `def` introduces general recursion
through a fixed point. This extends the original STLC with recursion; programs
can now diverge.

| Construct | Example |
| --- | --- |
| Abstraction | `(x: Nat) ⇒ x + 1` |
| Curried abstraction | `(x: Nat, y: Nat) ⇒ x + y` |
| Application | `increment 41` or `increment(41)` |
| Curried application | `add 20 22` or `add(20, 22)` |
| Let expression | `let x = 6 in x * 7` |
| Recursive definition | `def sum (n: Nat) = if n == 0 then 0 else n + sum (n - 1)` |
| Unit | `()` or an empty block `{}` |
| Conditional | `if 3 < 4 then 42 else 0` |
| Natural arithmetic | `2 + 3 * 4`, `3 - 8` |
| Natural comparison | `x == y`, `x < y` |
| Grouping | `(2 + 3) * 4` |

All application forms share the highest precedence and associate to the left:
`f x y` means `(f x) y`. Multiplication,
addition/subtraction, and comparisons follow in descending precedence; binary
operators also associate to the left. Use parentheses to group an argument:
`f (g x)`, `f (x + 1)`, or `f (if b then x else y)`.

Comma-separated calls require `(` immediately after the function:
`f(x, y)` is shorthand for `f x y`. Spaces or comments before `(` allow only
one grouped argument, so `f (x)` is valid but `f (x, y)` is not. A newline ends
the preceding expression in a file or block.
There are no tuples. `f()` applies `f` to unit, just like `f(())` or `f ()`.
Arguments separated by spaces or comments are also accepted, as in `f x` or
`f /* argument */ x`. Parentheses allow application to continue across lines.

Comma-separated parameters are curried in the same order:
`(f: Nat → Nat, x: Nat) ⇒ f (f x)` means
`(f: Nat → Nat) ⇒ (x: Nat) ⇒ f (f x)`. Each parameter needs its own type
annotation. Partial application, lexical scope, and shadowing follow the same
rules in either spelling. These forms expand into the existing single-parameter
functions and single-argument applications in the Lean parser.

Named definitions accept parameters before `=`:
`def add (x: Nat, y: Nat) = x + y` and
`def add (x: Nat) (y: Nat) = x + y` both mean
`def add = (x: Nat) ⇒ (y: Nat) ⇒ x + y`. Parameter groups may be mixed,
and partial application works the same way. An optional type after the last
parameter group annotates the result: `def add (x: Nat, y: Nat): Nat = x + y`.
Without parameters, an annotation describes the whole bound value, as in
`def add: Nat → Nat → Nat = (x: Nat, y: Nat) ⇒ x + y`.

### Statements, blocks, and recursion

Files and brace blocks contain newline-separated statements. A newline can
replace `in` after a binding; the binding scopes over the remaining statements:

```text
def factorial (n: Nat) =
  if n == 0 then 1 else n * factorial (n - 1)
let answer = factorial 5
answer
```

This returns `120 : Nat`. The outer braces are optional for a file. Blocks
evaluate every statement from left to right and return the last expression.
An empty file/block, or one ending in a `let` or `def` declaration, returns
`() : Unit`. Initializers are still evaluated. A block's bindings stay local.
Use a block to put several statements in a function body or binding initializer.

An explicit `in` always requires a following expression: `let x = 1 in` and
`def f (x: Nat) = x in` are parse errors, even with a trailing newline.
Newlines after `=`, `⇒`, `in`, `then`, `else`, or an infix operator continue the
required expression. A leading infix operator also continues the preceding
expression. Otherwise a completed expression ends at a newline. Blank lines and
comments do not create additional statements. Parentheses keep a multiline call
together, for example:

```text
(f
  x)
```

`def f = e in e′` expands to `let f = (fix f ⇒ e) in e′`. For type `τ`,
`fix f ⇒ e` requires `e : τ` under `f : τ`, and itself has type `τ`.
The type checker solves monomorphic constraints with an occurs check. It infers
ordinary recursive functions such as factorial. If a recursive type remains
ambiguous, annotate it explicitly, for example
`def loop (n: Nat): Nat = loop n`. The direct fixed-point spelling
also accepts an annotation: `fix (x: Nat) ⇒ x`.

Evaluation unfolds a fixed point when its recursive name is used. Suspended
environment entries capture its original scope without cyclic Lean data.
Nontermination, including `def x: Nat = x`, is bounded by the machine-step
budget, and the browser's Stop button can terminate its worker.

Both conditional branches must have the same type, and the condition must have type `Bool`.
Only the selected branch is evaluated. Arithmetic and comparison operands
must have type `Nat`; subtraction truncates at zero. Natural numbers have
arbitrary precision in both native and Wasm builds.

The parser also accepts the ASCII arrow spellings used by `tmp/language.tex`
and the keyboard hyphen for subtraction. Identifiers start with an ASCII
letter, underscore, or Greek character in U+0370–U+03FF; subsequent characters
may also be digits or apostrophes. Keywords are reserved. Line comments start
with `//`; `/* ... */` comments can nest.

Closures capture their definition environment, so shadowing a captured name
does not change the closure. The interpreter uses an explicit continuation
stack and left-to-right call-by-value evaluation. Execution has a default
budget of 100,000 machine transitions. Parsing accepts at most 64 KiB of UTF-8,
2047 non-EOF tokens, and 256 levels of syntax/expression depth. These are
resource limits of the implementation. The browser worker has a maximum
Wasm memory of 512 MiB and can be terminated with Stop.

## Compilation pipeline

```text
Lean sources ── Lean compiler ────── C
                                      │
Lean C++ runtime + LibUV filesystem ───┤
                                      ↓
                           Emscripten / LLVM / LTO
                                      ↓
                          stlc.mjs + stlc.wasm
                                      ↓
                          playground-core worker
```

The driver re-emits C for the exact standard-library dependencies using the
pinned native compiler. It cross-compiles those files, the interpreter, and
Lean's runtime; no native archive is linked into Wasm. A small C ownership
bridge initializes Lean and copies each returned JSON string into a buffer
that JavaScript frees. There is no JavaScript implementation of the language.

The runtime uses its built-in bignum implementation and the system allocator,
avoiding GMP and mimalloc dependencies. It uses Emscripten's single-thread
libc. The asynchronous LibUV networking modules are excluded; Lean's normal
IO initialization and filesystem helpers are linked with real LibUV code.
Upstream runtime sources are unmodified, and undefined symbols fail the build.
The runtime and Emscripten configuration come from the Lean source revision
reported by the active compiler.

Generated modules remain in `web/generated/`, with toolchain information in
`build-info.json`; the production bundle remains in `web/dist/`. These outputs
are ignored by Git and rebuilt from source.
