import Lean

/-!
Build with `lean --run scripts/BuildWasm.lean` after activating Emscripten.
The build driver itself is Lean; external programs are compiler/toolchain tools.
-/

open System

namespace BuildWasm

def run (cmd : String) (args : Array String := #[]) (input : Option String := none) : IO String := do
  let output ← IO.Process.output { cmd, args } input
  if output.exitCode != 0 then
    throw <| IO.userError s!"{cmd} failed ({output.exitCode}):\n{output.stdout}\n{output.stderr}"
  if !output.stderr.isEmpty then (← IO.getStderr).putStr output.stderr
  return output.stdout

def execute (cmd : String) (args : Array String := #[]) : IO Unit := do
  let output ← run cmd args
  if !output.isEmpty then IO.print output

def parallel [Inhabited β] (jobs : Nat) (f : α → IO β) (items : Array α) : IO (Array β) := do
  let mut results := #[]
  let mut i := 0
  while i < items.size do
    let batch := items.extract i (i + jobs)
    let tasks ← batch.mapM fun item => IO.asTask (f item)
    let mut failure : Option IO.Error := none
    for task in tasks do
      match task.get with
      | .ok value => results := results.push value
      | .error error => failure := some error
    -- Reap the whole batch before reporting an error; no child build is abandoned.
    if let some error := failure then throw error
    i := i + jobs
  return results

structure GitRelease where
  repository : String
  tag : String
deriving Lean.FromJson, Lean.ToJson, BEq

structure DependencyConfig where
  leanRepository : String
  libuv : GitRelease
  emsdk : GitRelease
deriving Lean.FromJson

structure LockedRelease where
  release : GitRelease
  revision : String
deriving Lean.FromJson, Lean.ToJson

structure DependencyLock where
  schemaVersion : Nat
  libuv : LockedRelease
  emsdk : LockedRelease
deriving Lean.FromJson, Lean.ToJson

def readJson [Lean.FromJson α] (path : FilePath) : IO α := do
  let text ← IO.FS.readFile path
  match Lean.Json.parse text >>= Lean.fromJson? with
  | .ok value => return value
  | .error error => throw <| IO.userError s!"{path}: {error}"

def validRevision (revision : String) : Bool :=
  (revision.length == 40 || revision.length == 64) &&
    revision.toList.all (fun c => c.isDigit || ('a' ≤ c && c ≤ 'f'))

def resolveRelease (release : GitRelease) : IO LockedRelease := do
  let ref := "refs/tags/" ++ release.tag
  let output ← run "git" #["ls-remote", "--exit-code", release.repository, ref, ref ++ "^{}"]
  let mut direct := ""
  let mut peeled := ""
  for line in output.splitOn "\n" do
    match line.splitOn "\t" with
    | [revision, name] =>
      if name == ref then direct := revision
      else if name == ref ++ "^{}" then peeled := revision
    | _ => pure ()
  let revision := if peeled.isEmpty then direct else peeled
  unless validRevision revision do
    throw <| IO.userError s!"Cannot resolve tag {release.tag} in {release.repository}."
  return { release, revision }

def updateDependencies (root : FilePath) : IO Unit := do
  let config : DependencyConfig ← readJson (root / "wasm/dependencies.json")
  let lock : DependencyLock := {
    schemaVersion := 1
    libuv := ← resolveRelease config.libuv
    emsdk := ← resolveRelease config.emsdk
  }
  let path := root / "wasm/dependencies.lock.json"
  let temporary := path.withExtension "tmp"
  IO.FS.writeFile temporary ((Lean.toJson lock).pretty ++ "\n")
  IO.FS.rename temporary path
  IO.println s!"Updated {path}; review and commit it with wasm/dependencies.json."

def loadDependencies (root : FilePath) : IO (DependencyConfig × DependencyLock) := do
  let config : DependencyConfig ← readJson (root / "wasm/dependencies.json")
  let path := root / "wasm/dependencies.lock.json"
  unless ← path.pathExists do
    throw <| IO.userError "Missing dependency lock. Run: lean --run scripts/BuildWasm.lean --update-deps"
  let lock : DependencyLock ← readJson path
  unless lock.schemaVersion == 1 do throw <| IO.userError s!"Unsupported dependency lock schema: {lock.schemaVersion}"
  for (name, release, locked) in #[("libuv", config.libuv, lock.libuv), ("emsdk", config.emsdk, lock.emsdk)] do
    unless release == locked.release && validRevision locked.revision do
      throw <| IO.userError s!"Stale {name} lock. Run: lean --run scripts/BuildWasm.lean --update-deps"
  return (config, lock)

/-- Git computes content identities; no revision or archive checksum is maintained by hand. -/
def fingerprint (text : String) : IO String := do
  return (← run "git" #["hash-object", "--stdin"] (some text)).trimAscii.toString

def checkout (target : FilePath) (repository revision : String) : IO Unit := do
  unless validRevision revision do throw <| IO.userError s!"Invalid Git revision: {revision}"
  if !(← target.pathExists) then
    IO.println s!"Fetching {repository} at {revision}"
    let temporary : FilePath := ⟨target.toString ++ ".partial"⟩
    if ← temporary.pathExists then IO.FS.removeDirAll temporary
    IO.FS.createDirAll temporary
    let _ ← run "git" #["init", "--quiet", temporary.toString]
    let _ ← run "git" #["-C", temporary.toString, "remote", "add", "origin", repository]
    let _ ← run "git" #["-C", temporary.toString, "fetch", "--quiet", "--depth=1", "origin", revision]
    let _ ← run "git" #["-C", temporary.toString, "checkout", "--quiet", "--detach", revision]
    IO.FS.rename temporary target
  let origin := (← run "git" #["-C", target.toString, "remote", "get-url", "origin"]).trimAscii.toString
  unless origin == repository do throw <| IO.userError s!"Unexpected Git remote in {target}: {origin}"
  let dirty ← run "git" #["-C", target.toString, "status", "--porcelain", "--untracked-files=no"]
  unless dirty.isEmpty do throw <| IO.userError s!"Dependency checkout has local changes: {target}"
  let head := (← run "git" #["-C", target.toString, "rev-parse", "HEAD"]).trimAscii.toString
  if head != revision then
    let _ ← run "git" #["-C", target.toString, "fetch", "--quiet", "--depth=1", "origin", revision]
    let _ ← run "git" #["-C", target.toString, "checkout", "--quiet", "--detach", revision]
  let actual := (← run "git" #["-C", target.toString, "rev-parse", "HEAD"]).trimAscii.toString
  unless actual == revision do throw <| IO.userError s!"Git revision mismatch in {target}."

def sourceCheckout (cache : FilePath) (repository revision : String) : IO FilePath := do
  let target := cache / "sources" / (← fingerprint (repository ++ "\n" ++ revision))
  checkout target repository revision
  return target

def setupEmsdk (root target : FilePath) : IO Unit := do
  let (_, lock) ← loadDependencies root
  checkout target lock.emsdk.release.repository lock.emsdk.revision
  let executable := (target / "emsdk").toString
  execute executable #["install", lock.emsdk.release.tag]
  execute executable #["activate", lock.emsdk.release.tag]
  IO.println s!"Activate the SDK in your shell: source \"{target / "emsdk_env.sh"}\""

/-- Preserve the compiler's version metadata, changing only the cross-compilation target. -/
def prepareVersionHeader (toolchain runtime : FilePath) : IO Unit := do
  let header ← IO.FS.readFile (toolchain / "include/lean/version.h")
  let marker := "#define LEAN_PLATFORM_TARGET "
  unless (header.splitOn "\n").any (·.startsWith marker) do
    throw <| IO.userError "Lean's version header has no LEAN_PLATFORM_TARGET definition."
  let header := String.intercalate "\n" <| (header.splitOn "\n").map fun line =>
    if line.startsWith marker then marker ++ "\"wasm32-unknown-emscripten\"" else line
  let target := runtime / "include/lean/version.h"
  IO.FS.createDirAll target.parent.get!
  -- Preserve timestamps when nothing changed, so CMake can reuse its objects.
  let unchanged ← if ← target.pathExists then pure ((← IO.FS.readFile target) == header) else pure false
  unless unchanged do IO.FS.writeFile target header

partial def leanFiles (directory : FilePath) : IO (Array FilePath) := do
  let mut paths := #[]
  for entry in ← directory.readDir do
    if ← entry.path.isDir then paths := paths ++ (← leanFiles entry.path)
    else if entry.path.extension == some "lean" then paths := paths.push entry.path
  return paths

partial def cFiles (directory : FilePath) : IO (Array FilePath) := do
  let mut paths := #[]
  for entry in ← directory.readDir do
    if ← entry.path.isDir then paths := paths ++ (← cFiles entry.path)
    else if entry.path.extension == some "c" then paths := paths.push entry.path
  return paths

def relative (root path : FilePath) : FilePath :=
  ⟨(path.toString.drop (root.toString.length + 1)).toString⟩

def dependencies (text : String) : Array String := Id.run do
  let marker := "lean_object* initialize_"
  let mut names := #[]
  for line in text.splitOn "\n" do
    if line.startsWith marker then
      names := names.push (((line.drop marker.length).toString.splitOn "(").head!)
  return names

/-- Follow actual module imports from the Wasm adapter, excluding CLI and stale build files. -/
def applicationDependencies (directory : FilePath) : IO (Array FilePath × Array String) := do
  let marker := "LEAN_EXPORT lean_object* initialize_"
  let mut modules : Std.HashMap String (FilePath × Array String) := ∅
  for path in ← cFiles directory do
    let text ← IO.FS.readFile path
    for line in text.splitOn "\n" do
      if line.startsWith marker then
        let name := ((line.drop marker.length).toString.splitOn "(").head!
        modules := modules.insert name (path, dependencies text)
  let mut pending := #["LambdaCalculus_App_Wasm"]
  let mut seen : Std.HashSet String := ∅
  let mut files := #[]
  -- These helpers are called by Lean's C++ runtime during initialization and errors.
  let mut standard := #["Init_System_IO"]
  while !pending.isEmpty do
    let name := pending.back!
    pending := pending.pop
    if !seen.contains name then
      seen := seen.insert name
      let some (path, imports) := modules[name]? | throw <| IO.userError s!"Missing C module: {name}"
      files := files.push path
      for dependency in imports do
        if dependency.startsWith "Init" then
          if !standard.contains dependency then standard := standard.push dependency
        else pending := pending.push dependency
  return (files, standard)

def emit (stdlib generated source : FilePath) : IO (FilePath × Array String) := do
  let target := generated / (relative stdlib source).withExtension "c"
  IO.FS.createDirAll target.parent.get!
  if !(← target.pathExists) then
    let temporary := target.withExtension "tmp.c"
    let _ ← run "lean" #["-R", stdlib.toString, "-c", temporary.toString, source.toString]
    IO.FS.rename temporary target
  return (target, dependencies (← IO.FS.readFile target))

def emitStdlib (jobs : Nat) (stdlib generated : FilePath) (initial : Array String) : IO (Array FilePath) := do
  let mut modules : Std.HashMap String FilePath := ∅
  for path in (← leanFiles (stdlib / "Init")).push (stdlib / "Init.lean") do
    let name := String.intercalate "_" ((relative stdlib path).withExtension "").components
    modules := modules.insert name path
  let mut pending := initial
  let mut seen : Std.HashSet String := ∅
  let mut files := #[]
  while !pending.isEmpty do
    let batch := pending
    pending := #[]
    for name in batch do seen := seen.insert name
    let sources ← batch.mapM fun name => do
      match modules[name]? with
      | some path => pure path
      | none => throw <| IO.userError s!"Unknown standard-library dependency: {name}"
    for (path, imports) in ← parallel jobs (emit stdlib generated) sources do
      files := files.push path
      for name in imports do
        if !seen.contains name && !pending.contains name then pending := pending.push name
    IO.println s!"Emitted {files.size} standard library modules"
  return files

def compileC (compilerKey : String) (flags : Array String) (source : FilePath) : IO FilePath := do
  let target := source.withExtension "wasm.o"
  let signature := target.withExtension "flags"
  let key := compilerKey ++ "\n" ++ String.intercalate "\n" flags.toList
  let unchanged ← if ← signature.pathExists then pure ((← IO.FS.readFile signature) == key) else pure false
  let fresh ← if ← target.pathExists then
      pure (decide ((← source.metadata).modified ≤ (← target.metadata).modified))
    else pure false
  unless unchanged && fresh do
    let _ ← run "emcc" (flags ++ #["-c", source.toString, "-o", target.toString])
    IO.FS.writeFile signature key
  return target

def build : IO Unit := do
  let root ← IO.currentDir
  unless ← (root / "lakefile.toml").pathExists do throw <| IO.userError "Run from the repository root."
  let cache := root / ".lake/wasm"
  let output := root / "web/generated"
  IO.FS.createDirAll cache
  IO.FS.createDirAll output
  let jobs := max 1 (min 32 (((← IO.getEnv "JOBS").bind String.toNat?).getD 8))
  let (config, lock) ← loadDependencies root
  let version := (← run "lean" #["--short-version"]).trimAscii.toString
  let commit := (← run "lean" #["--githash"]).trimAscii.toString
  unless validRevision commit do
    throw <| IO.userError "The active Lean compiler must report its source revision with --githash."
  let emscripten := ((← run "emcc" #["--version"]).splitOn "\n").head!
  let toolchain : FilePath := ⟨(← run "lean" #["--print-prefix"]).trimAscii.toString⟩
  let source ← sourceCheckout cache config.leanRepository commit
  let uv ← sourceCheckout cache lock.libuv.release.repository lock.libuv.revision
  -- Separate generated C and CMake state whenever a compiler or dependency changes.
  let identity := Lean.Json.arr <| #[
    config.leanRepository, commit, toolchain.toString, emscripten,
    lock.libuv.release.repository, lock.libuv.revision,
    (← IO.getEnv "PATH").getD "", (← IO.getEnv "EM_CONFIG").getD "",
    (← run "cmake" #["--version"]),
    (← IO.FS.readFile (toolchain / "include/lean/version.h")),
    (← IO.FS.readFile (root / "wasm/CMakeLists.txt"))
  ].map Lean.toJson
  let artifacts := cache / "builds" / (← fingerprint identity.compress)
  IO.println s!"Build cache: {artifacts}"
  let runtime := artifacts / "runtime"
  prepareVersionHeader toolchain runtime
  execute "emcmake" #["cmake", "-S", (root / "wasm").toString, "-B", runtime.toString,
    s!"-DLEAN_SOURCE={source}", s!"-DLIBUV_SOURCE={uv}", s!"-DGIT_SHA1={commit}"]
  execute "cmake" #["--build", runtime.toString, "--target", "leanrt", "uv_a", "-j", toString jobs]
  execute "lake" #["build", "App.Wasm"]
  let (application, imports) ← applicationDependencies (root / ".lake/build/ir")
  let generated ← emitStdlib jobs (toolchain / "src/lean") (artifacts / "stdlib") imports
  let flags := #["-O2", "-flto", "-fwasm-exceptions", "-DNDEBUG", "-DLEAN_EMSCRIPTEN",
    s!"-I{runtime / "include"}", s!"-I{source / "src/include"}"]
  let headers ← run "sha256sum" #[(runtime / "include/lean/config.h").toString, (source / "src/include/lean/lean.h").toString]
  let compilerKey := emscripten ++ headers
  IO.println s!"Compiling {generated.size} C modules to WebAssembly objects"
  let objects ← parallel jobs (compileC compilerKey flags) generated
  let archive := artifacts / "libInit.a"
  if ← archive.pathExists then IO.FS.removeFile archive
  execute "emar" (#["rcs", archive.toString] ++ objects.map (·.toString))
  let appObjects ← parallel jobs (compileC compilerKey flags) application
  let bridge := artifacts / "bridge.o"
  execute "emcc" (flags ++ #["-c", (root / "wasm/bridge.c").toString, "-o", bridge.toString])
  IO.println "Linking browser module"
  execute "em++" (flags ++ #[bridge.toString] ++ appObjects.map (·.toString) ++ #[
    archive.toString, (runtime / "lib/libleanrt.a").toString, (runtime / "lib/libuv.a").toString,
    "--no-entry", "-sMODULARIZE=1", "-sEXPORT_ES6=1", "-sENVIRONMENT=web,worker,node",
    "-sALLOW_MEMORY_GROWTH=1", "-sSTACK_SIZE=8388608", "-sMAXIMUM_MEMORY=536870912",
    "-sEXPORTED_FUNCTIONS=['_stlc_init','_stlc_request','_malloc','_free']",
    "-sEXPORTED_RUNTIME_METHODS=['ccall','UTF8ToString']", "-o", (output / "stlc.mjs").toString
  ])
  let info := Lean.Json.mkObj [
    ("lean", Lean.toJson version), ("leanRevision", Lean.toJson commit),
    ("libuv", Lean.toJson lock.libuv.release.tag), ("libuvRevision", Lean.toJson lock.libuv.revision),
    ("emscripten", Lean.toJson emscripten),
    ("pipeline", Lean.toJson "Lean → C + Lean C++ runtime → LLVM → WebAssembly"),
    ("wasmBytes", Lean.toJson (← (output / "stlc.wasm").metadata).byteSize.toNat)
  ]
  IO.FS.writeFile (output / "build-info.json") (info.pretty ++ "\n")
  let notices := s!"Lean {version}\n\n" ++ (← IO.FS.readFile (source / "LICENSE"))
    ++ s!"\n\nLibUV {lock.libuv.release.tag}\n\n" ++ (← IO.FS.readFile (uv / "LICENSE"))
  IO.FS.writeFile (output / "THIRD-PARTY-NOTICES.txt") notices
  IO.println s!"Built {output / "stlc.wasm"}"

end BuildWasm

def main (args : List String) : IO Unit := do
  let root ← IO.currentDir
  match args with
  | ["--update-deps"] => BuildWasm.updateDependencies root
  | ["--setup-emsdk", target] => BuildWasm.setupEmsdk root (root / target)
  | [] => BuildWasm.build
  | ["--web"] =>
    BuildWasm.build
    BuildWasm.execute "npm" #["ci", "--prefix", "playground-core", "--no-audit", "--no-fund"]
    BuildWasm.execute "npm" #["run", "build", "--prefix", "playground-core"]
    BuildWasm.execute "npm" #["ci", "--prefix", "web", "--no-audit", "--no-fund"]
    BuildWasm.execute "npm" #["run", "build", "--prefix", "web"]
  | _ =>
    throw <| IO.userError
      "Usage: lean --run scripts/BuildWasm.lean [--web | --update-deps | --setup-emsdk DIRECTORY]"
