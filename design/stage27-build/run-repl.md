# `nucleus run-repl`: a running program with a prompt

**Status: RL-1 and RL-2 built 2026-10-26, uncommitted.** The defaults in §3 are unconfirmed.

## 1. The request

The user expected `nucleus run-repl` to run the program, as `nucleus run`
does, while a REPL inspects and modifies its state. The bare REPL becomes
`nucleus repl`. Until now, `run-repl` was that bare session: the project's
flags and C requirements, with nothing imported.

## 2. What exists

- **An import at the prompt** compiles the file's closure into one JIT module.
  Since the G-3 fix in BT-11, it also runs the imported `defvar`
  initializers. Calling `(app.main/main)` by hand already works (BT-11's
  charge-shaped unit).
- **Globals are shared.** A `set!` at the prompt changes what the imported
  code reads, because there is one storage.
- **`(ns X)` at the prompt re-enters an imported namespace**, and its names
  then resolve bare.
- **A `defn` typed at the prompt is redefinable.** The prompt's `defn` arm
  routes calls through a thunk, `@f`, which loads the current
  `@f.impl.N` from `@f.tgt`. A redefinition removes the old impl's resource
  tracker. A function that came in through an import has no thunk, so
  redefining it fails: `lookup of f.tgt failed`.

## 3. Decisions (defaults, not ruled)

- **D-THREAD: `main` runs on a thread of its own, and the prompt stays on the
  process's main thread.** The REPL's recovery (`repl-protect`'s `longjmp`,
  the compile-time fault handler) is per-thread state that has only ever run
  on the main thread, so it stays there. The cost: a toolkit that insists on
  the process's main thread, as Cocoa does, can't run under `run-repl`.
  Linux GTK only needs one consistent thread. Calling GTK from the prompt is
  the program's thread-safety problem, as in any threaded GTK program. Use
  `g_idle_add` to run on the program's thread.
- **D-NS: the prompt starts in the entry file's namespace**, so the
  program's globals and functions are reachable by their bare names.
- **D-EOF: end of input waits for `main`.** A piped script doesn't stop the
  program it was written to poke. The process then exits with `main`'s
  status, as `nucleus run` does. Ctrl-C still kills the process. When `main`
  returns while the prompt is open, the session says so and stays open.
- **D-KEEP: while the program runs, a redefinition keeps the old code.** The
  program's thread may be executing it, so the old tracker isn't removed.
  The cost is a little JIT memory per redefinition.
- **D-OWN: only the program's own files are redefinable** (RL-2). These are
  the files under the entry file's directory, which excludes the stdlib and
  installed libraries. Thunking every import would tax every call into the
  stdlib.

## 4. Phases

### RL-1: run `main` beside the prompt

- **The compiler:** `nucleusc -i FILE [-- ARGS]` imports `FILE`, enters its
  namespace, and calls `main` (nullary or `(argc argv)`, as in `--run`) on a
  new thread, with `argv[0]` set to `FILE`. `-i` without a file is
  unchanged. `--` is accepted with `-i FILE`.
- **The tool:**
  - `nucleus repl` is the old `run-repl`.
  - `nucleus run-repl [-- ARGS]` passes `-i ENTRY -- ARGS`, plus the
    project's flags.
  - A project with `:c-sources` is refused by both, because its objects
    can't join a JIT session. `nucleus run` builds it instead.
- **D-KEEP** applies to the prompt's `defn` redefinition and to `forget`.
- **Tests:**
  - a program that loops on a global, with the prompt reading the global and
    then setting it to end the loop, and the exit status checked;
  - argv reaching `main`;
  - `nucleus repl` importing nothing.

### RL-2: redefine the program's functions

- **In `-i FILE` mode,** a `defn` from one of the program's own files
  (D-OWN) is emitted as `@f.impl.0`, with a thunk `@f` and
  `@f.tgt = global ptr @f.impl.0` in a module of its own, the same scheme
  as the prompt's `defn` arm. Calls inside the import go through `@f`.
- **The prompt's `defn` arm** then finds the imported `Sym` and its `.tgt`.
  It JITs `@f.impl.N` and repoints `.tgt`. Running code picks up the new
  body at its next call.
- **Private `defn-`** impls are emitted with external linkage, because the
  thunk module must reach them.
- **Tests:**
  - a redefinition takes effect on the running loop's next iteration;
  - a stdlib function stays unthunked;
  - a signature change is refused, as it is for a prompt `defn` today.

## 5. Built

- **RL-1.** `-i FILE` also sets the session's C requirements to `FILE`'s,
  so `--c-requirements-of=` is needed only by the bare `repl`. The REPL loop
  body became `repl-eval-text`, and startup feeds it the entry's import and
  its `ns` as text. `main` is found by its qualified key in the entry's
  namespace, which is read from the recorded file namespaces and matched by
  realpath. It is entered through the JIT symbol `main`. `nucleus repl` is
  allowed in a library project, without a C-requirements root.
- **RL-2.**
  - **The rename scans the import's `define` lines** rather than using
    ProgDefn spans, which the REPL's per-entry buffer doesn't keep reliably.
    The owned functions are the new `Sym`s whose `src-file` is under the
    entry's directory and not under the stdlib root, one per IR name, with
    `main` excluded.
  - **Every thunk is added before any `.tgt` update.** The first update's
    lookup materializes the import, which calls them all.
  - **Two prompt bugs were fixed on the way.** `defn-` at the prompt was
    read as an expression (`unknown: defn-`), and once it reached the arm,
    its thunk used `ns-ir-base`'s name instead of the file-private one. The
    arm now takes the IR name from the `Sym` that `emit-defn` registered.
  - **A signature change is refused only while the program runs.** With no
    program, the earlier undefined-behavior caveat stands, unchanged.
- **Tests** are in tests/suite-build.nuc:
  - `rl1-run-repl-runs-main`: argv, the entry's namespace, the exit status,
    `repl` importing nothing, no `main`, and the `:c-sources` refusal;
  - `rl2-redefine-while-running`: a live `defn-` redefinition, the
    signature refusal, and no stdlib `.impl` defines in the dumped IR;
  - `bt11-charge-shaped-build-run-repl` now drives `repl` and `run-repl`.
- **Follow-ups the user found with charge (2026-10-26).**
  - **The entry's own imports didn't reach the prompt.** `(str 8)` was
    unknown, although `main.nuc` imports `nucleus.fmt`, because import
    bindings are per file and the prompt's are its own. Under the REPL,
    `do-import` now keeps each file's bindings by path
    (`g-path-imports`). The prompt's `ns` arm adds the bindings of every
    file that declared that namespace to the prompt's own
    (`repl-adopt-ns-imports`). They stay after a later `ns`, because one
    prompt binding list is simpler than one per namespace, and a superset
    resolves the same names.
  - **A struct result printed nothing.** The eval function returned `void`
    for an aggregate. It now returns a heap copy. A `StrView` or `String`
    prints quoted (the `String` is then dropped), and any other aggregate
    prints `#<Type>`. A literal view is given its length with `strlen`, so
    the printer never takes a `CStr` (the cstr-residue audit).
  - Tests: the golden `repl-aggregates`, and `(str 8)` in the charge-shaped
    `run-repl` unit.
  - **A race in the "main returned" note.** The program thread printed it
    with `emit`, which formats into the compiler's one process-wide buffer
    (`g-emit-buf`). The prompt's compile was writing to that buffer at the
    same time, and the charge-shaped unit crashed once under the full
    suite's load. The thread now formats into a `String` of its own and
    `fwrite`s it. Program code still shares the compiler's `g-arena` and
    intern tables, because the session declares the host's globals (§3.2 of
    macro-call-linking). The docs say so instead of fixing it.

- **`--repl-format=text|json`** is accepted by `repl` and `run-repl` and
  passed to the compiler (2026-10-27). Only those two commands accept it,
  because only they start a REPL.
- **`--diagnostics=text|edn`** is accepted by every tool command (2026-10-27).
  It goes to each compile, to the import scan, and to `run`/`repl`'s
  in-process hand-off. The tool's own errors, warnings and notes render through
  `diag-render` too. The build libraries' `FILE:LINE: error: MSG` strings are
  split back into a location and a message. On an edge it rides in the new
  `Edge.report` arguments, which the command hash leaves out, so switching it
  rebuilds nothing.
