import scripts.BuildWasm

/-! Integration checks for dependency upgrades using temporary local Git repositories. -/

open System BuildWasm

namespace BuildWasmTests

def ensure (condition : Bool) (message : String) : IO Unit := do
  unless condition do throw <| IO.userError message

def expectFailure (action : IO α) (message : String) : IO Unit := do
  let failed ← try
    let _ ← action
    pure false
  catch _ => pure true
  ensure failed message

def git (repository : FilePath) (args : Array String) : IO String :=
  run "git" (#[
    "-C", repository.toString, "-c", "user.name=Build tests", "-c", "user.email=build-tests@example.invalid",
    "-c", "commit.gpgSign=false", "-c", "tag.gpgSign=false"
  ] ++ args)

def writeConfig (root repository : FilePath) (tag : String) : IO Unit :=
  IO.FS.writeFile (root / "wasm/dependencies.json") <| (Lean.Json.mkObj [
    ("leanRepository", Lean.toJson repository.toString),
    ("libuv", Lean.toJson ({ repository := repository.toString, tag } : GitRelease)),
    ("emsdk", Lean.toJson ({ repository := repository.toString, tag := "sdk" } : GitRelease))
  ]).pretty

def checkDependencies (root : FilePath) : IO Unit := do
  let repository := root / "upstream"
  IO.FS.createDirAll (root / "wasm")
  let _ ← run "git" #["init", "--quiet", repository.toString]
  IO.FS.writeFile (repository / "payload") "first"
  let _ ← git repository #["add", "payload"]
  let _ ← git repository #["commit", "--quiet", "-m", "First release"]
  let first := (← git repository #["rev-parse", "HEAD"]).trimAscii.toString
  let _ ← git repository #["tag", "-a", "v1", "-m", "Annotated release"]
  let _ ← git repository #["tag", "sdk"]
  writeConfig root repository "v1"
  expectFailure (loadDependencies root) "A missing lock was accepted."
  updateDependencies root
  let (_, initial) ← loadDependencies root
  ensure (initial.libuv.revision == first) "The annotated tag was not peeled to its commit."
  ensure (initial.emsdk.revision == first) "The lightweight tag was not resolved."
  let lockPath := root / "wasm/dependencies.lock.json"
  let original ← IO.FS.readFile lockPath
  updateDependencies root
  ensure ((← IO.FS.readFile lockPath) == original) "Lock generation is not reproducible."

  let cache := root / "cache"
  let firstSource ← sourceCheckout cache repository.toString first
  ensure ((← IO.FS.readFile (firstSource / "payload")) == "first") "The locked source was not fetched."
  IO.FS.rename repository (root / "offline")
  let cached ← sourceCheckout cache repository.toString first
  ensure (cached == firstSource) "A cached checkout was not reusable offline."
  IO.FS.rename (root / "offline") repository

  IO.FS.writeFile (repository / "payload") "second"
  let _ ← git repository #["commit", "--quiet", "-a", "-m", "Second release"]
  let second := (← git repository #["rev-parse", "HEAD"]).trimAscii.toString
  let _ ← git repository #["tag", "v2"]
  writeConfig root repository "v2"
  expectFailure (loadDependencies root) "A stale lock was accepted."
  updateDependencies root
  let (_, upgraded) ← loadDependencies root
  ensure (upgraded.libuv.revision == second) "The release upgrade was not locked."
  let secondSource ← sourceCheckout cache repository.toString second
  ensure (secondSource != firstSource) "An upgrade reused the old source directory."
  ensure ((← IO.FS.readFile (secondSource / "payload")) == "second") "The upgraded source is stale."
  ensure ((← IO.FS.readFile (firstSource / "payload")) == "first") "The old source cache was overwritten."

  let sdk := root / "sdk"
  checkout sdk repository.toString first
  checkout sdk repository.toString second
  ensure ((← IO.FS.readFile (sdk / "payload")) == "second") "An existing SDK checkout did not upgrade."
  IO.FS.writeFile (sdk / "payload") "local edit"
  expectFailure (checkout sdk repository.toString first) "A dirty dependency checkout was overwritten."
  ensure ((← IO.FS.readFile (sdk / "payload")) == "local edit") "A local dependency edit was lost."

  let latest ← IO.FS.readFile lockPath
  writeConfig root repository "missing"
  expectFailure (updateDependencies root) "A nonexistent release was accepted."
  ensure ((← IO.FS.readFile lockPath) == latest) "A failed update replaced the previous lock."
  writeConfig root repository "v2"
  IO.FS.writeFile lockPath ((Lean.toJson { upgraded with schemaVersion := 2 }).pretty)
  expectFailure (loadDependencies root) "An unsupported lock schema was accepted."
  IO.println "Dependency checks passed: tags, locks, offline reuse, upgrades, and failed updates."

def checkHeaders (root : FilePath) : IO Unit := do
  let toolchain := root / "toolchain"
  IO.FS.createDirAll (toolchain / "include/lean")
  let metadata := "#define LEAN_VERSION_STRING \"9.8.7-rc1\"\n#define LEAN_VERSION_IS_RELEASE 0\n"
  IO.FS.writeFile (toolchain / "include/lean/version.h") (metadata ++ "#define LEAN_PLATFORM_TARGET \"native\"\n")
  let runtime := root / "runtime"
  prepareVersionHeader toolchain runtime
  let target := runtime / "include/lean/version.h"
  ensure
    ((← IO.FS.readFile target) == metadata ++ "#define LEAN_PLATFORM_TARGET \"wasm32-unknown-emscripten\"\n")
    "The compiler's version metadata was not preserved."
  let modified := (← target.metadata).modified
  prepareVersionHeader toolchain runtime
  ensure ((← target.metadata).modified == modified) "An unchanged version header was rewritten."
  IO.println "Version-header checks passed: fresh generation, prerelease metadata, and incremental reuse."

end BuildWasmTests

#eval IO.FS.withTempDir fun root => do
  BuildWasmTests.checkDependencies root
  BuildWasmTests.checkHeaders root
