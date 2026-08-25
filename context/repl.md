# Using the Nucleus REPL during development

The REPL is `build/nucleusc -i` (or `--interactive`). It runs the same compiler
binary in interactive mode: each top-level form is parsed, compiled to LLVM IR,
added to a persistent JIT session, and (for expression forms) called
immediately. Definitions persist across forms instead of exiting. Recovery is
split by error kind: **reader/source syntax errors** (unbalanced `)`,
unterminated form, bad escape, …) are an ordinary `!T` value path as of Stage 10
E4 — `read-program` returns `(err parse-error)`, the REPL `match`es it and
continues; **eval/JIT errors** (and the `die-at` panic tier) still unwind via
`repl_throw` (setjmp/longjmp shim in `src/repl_shim.c`).

Since Stage 16 R1 that unwind is a real one. `repl_protect(body, ctx)` runs the
body as a callback so its `setjmp` frame is still live when the `longjmp` fires,
and the session state a `longjmp` skipped the restore of — reader state, the
import/prescan lists, `g-toplevel-depth`, namespace/privacy flags, the stream
globals, and a watermark for every append-only registry — is spelled once in
`ReplState` and rolled back by `repl-restore`. Two consequences when probing:
a recovered error now prints `  error: error (recovered)` after the diagnostic,
and **a failed import leaves the session exactly as it found it** — later
diagnostics are attributed to `<repl>` again, a retry of the failed import
reports rather than silently doing nothing, and a name the half-loaded library
registered before dying no longer resolves. See
[design/stage16-ergonomics/repl-libraries.md](../design/stage16-ergonomics/repl-libraries.md)
§3.4 for what is *not* rolled back (the preamble, the string pool, the JIT
session) and why.

stdio.h, stdlib.h, string.h, ctype.h, and unistd.h are pre-loaded at startup,
so libc functions are available without an explicit `(include ...)`.

Since Stage 16 R2 the session also boots by evaluating `(import-use prelude)`
through the ordinary import arm (`repl-preload-prelude`), which is what batch
`main` splices in. So `Node`, all seven `NODE-*` ordinals, `StrView`,
`(Maybe T)`/`?T`, `(Result T E)`/`!T`, `Clone` and the standard macros are in
scope at the prompt and mean exactly what they mean in a batch compile. This
replaced a hand-written mirror of a slice of the prelude, which had drifted:
`NODE-FLOAT`, `NODE-KEYWORD` and `NODE-CHAR` had no binding at all. It costs
about 22 ms of the ~210 ms startup.

## When LLM agents should reach for the REPL

Prefer the REPL when iteration speed matters more than reproducibility:

- **Probing language/compiler behavior.** "Does `(cast i64 -1)` sign-extend?",
  "What's the printed form of an empty `defstruct`?", "Does this macro expand
  the way I think?" — one form in the REPL beats writing a throwaway
  `examples/foo.nuc`, running `./build.sh`, and reading the output.
- **Exploring a library before using it.** Import the lib, call its functions
  with sample inputs, inspect return values. Faster than reading code top-down.
  **Working as of 2026-08-25.** Stage 16 R2 boots the session with
  `(import-use prelude)` through the ordinary import arm, so 33 of the 34
  modules in `lib/` import in a fresh session (`node` is the exception —
  the compiler is `-rdynamic` and ORC resolves `alloc-node` to the host's copy).
  R3 added the REPL's own `repl-flush-mono`, so generics, lambdas and collection
  literals evaluate at the prompt and stamps stay resolvable across entries, and
  closed the two-imports-collide-on-a-`declare` bug (D8). R4 replaced the
  process-wide `StructDef.emitted` latch with a module epoch, so a type defined
  at one entry is still there at the next (D6 — a `?i32`-returning `defn` then a
  `match` used to die with `IR parse error: Cannot allocate unsized type`), and
  capturing `vfn`/`mfn` closures now work at the prompt. R5 closed D7: all six
  import spellings — `import-use`, `import-only`, `import`, `import-prefixed`,
  `import-ct`, `unsafe/import-private` — are now top-level arms rather than
  calls, and each prints `  imported <lib>` or `  <lib> already imported`, so a
  deduplicated retry is distinguishable from one that loaded. See
  [design/stage16-ergonomics/repl-libraries.md](../design/stage16-ergonomics/repl-libraries.md)
  §3.5. D9 closed the last of §3.3's type-recoverability residue: a
  `(compile-time (defstruct …))` typed at the prompt is now usable at later
  entries, and a `?T` stamped inside a `compile-time` body no longer dies
  `IR parse error: Cannot allocate unsized type`.
- **Reproducing a bug interactively.** Once you have a minimal trigger, paste
  it into the REPL to vary inputs without recompiling. Especially useful for
  bugs in macros, type inference, or codegen where the failure is a specific
  form rather than a whole-program interaction.
- **Checking that a fix actually works** before committing to a full
  `make test` cycle — eval the previously-failing form, confirm, then run
  the suite.

## When NOT to use the REPL

- **Anything that needs to be reproducible or shared.** Put it in
  `examples/` or `tests/` so future sessions (and CI) see the same thing.
- **Multi-file or `import`-heavy work.** The REPL can `import`, but if you're
  iterating on changes to an imported source file, you have to restart the
  session — at that point a batch compile is no slower.
- **Final verification.** Self-host (`make bootstrap`) and `make test` are the
  source of truth. The REPL can mislead because redefinition order, JIT symbol
  resolution, and the preloaded headers don't perfectly match batch mode.
- **Anything you'd report as "done."** REPL state is invisible to the user
  and gone when the process exits. If a result matters, capture it as a test
  or example.

## Practical notes for agent use

- Drive it via `Bash` with a heredoc: `build/nucleusc -i <<'EOF' ... EOF`.
  The prompt (`nuc> ` / `...> `) goes to **stderr**; eval results go to
  **stderr** too (the REPL uses stderr for all interactive output). Capture
  with `2>&1` if you want to see results in the tool output.
- Each session is fresh — there is no persisted history between Bash calls.
  Bundle the setup and the probe into one heredoc.
- Redefining a `defn` is supported. The new body wins for every caller —
  including ones JIT'd before the redefinition — because calls go through a
  stable thunk that dispatches to the latest impl. The REPL prints
  `redefined` to confirm. Captured pointers from `(addr-of foo)` also see
  the latest. Redefining with a different signature is unsafe (existing
  callers were compiled against the old type); restart the session if the
  signature changes.
- The REPL is effectively a giant `compile-time` block, so `(compile-time
  ...)` forms run normally — don't strip them when pasting code.
- Errors don't kill the session; on error the partial form's IR is discarded
  and the prompt returns. Use this to probe failure cases cheaply.
- Every import form answers, since R5. A heredoc that imports N libraries now
  produces N extra lines on stderr; a failed import prints its diagnostic
  instead of a confirmation.

## Where a REPL module's types come from (for compiler work)

Since Stage 16 R4 this is a mechanism, not a rule to remember. **The preamble
(`g-repl-preamble`) is the type section of every module the session assembles.**
A module is *preamble + strings + decls + defs*; it no longer carries a type
buffer of its own alongside the preamble, so there is nothing to keep in sync.

Three pieces make that true:

1. **`g-module-epoch`** identifies the module whose buffers are open. It starts
   at 1 and `open-module-streams` increments it.
2. **A `StructDef` records where its `%Name = type {…}` line went**:
   `emit-epoch` (which module's buffer), `in-type-buf` (was that the module's
   *type* buffer, or a def / compile-time buffer that dies with the module), and
   `in-preamble`. `emitted` still means only "this type has a definition at all",
   which is what the `defstruct`/`defunion` redefinition diagnostics ask.
3. **Two functions in `src/type-utils.nuc` are the whole interface.**
   `sdef-in-module` answers "is this type's definition present in the module
   being assembled" (`in-preamble || emit-epoch == g-module-epoch`);
   `sdef-note-emitted sd out` records a write. Every emission site calls them —
   `emit-defstruct`, `fn-make-env-struct`, the cheader writers, the pending-union
   drain and `pending-union-deps-ready`. **A new site that writes a type line
   calls `sdef-note-emitted` and inherits the rest.**

At module close `repl-absorb-type-buf` (`src/repl.nuc`) moves the type buffer
into the preamble and marks the StructDefs whose lines are in it. A module
assembled *inside* another one — `repl-flush-mono`'s drain — calls
`repl-cycle-type-buf` first, which absorbs the entry's buffer early and starts a
fresh one, so both modules read those types from the preamble and neither defines
them twice.

Outside the REPL there is one epoch and no preamble, so `sdef-in-module` is
identically `emitted` and batch IR cannot move. One writer deliberately does
*not* land in the type buffer and so is not carried forward:
`fn-make-env-struct` in batch, whose line belongs in the def stream, where it
always was.

**The rule the epoch makes sayable (D9): a type is recoverable across modules
only if it is queued or absorbed.** Absorbed = its line went to the type buffer,
which `repl-absorb-type-buf` moves into the preamble. Queued = it is on
`g-pending-unions`, so a later drain re-emits it once its epoch is stale — which
is why `emit-defstruct` queues every StructDef it writes, and why a `defstruct`
inside a prompt-typed `(compile-time …)` is usable at the next entry. Note what
queueing does *not* buy: it recovers a type across **epochs**, not across
**buffers**, and batch has exactly one epoch — see conventions.md, "Queueing
buys recoverability across EPOCHS, not across BUFFERS". That is why the batch
half of the same case needed a different fix: D9 ruled that a `defstruct` inside
`(compile-time …)` defines a *program* type, so that arm writes its line to
`g-type-stream` rather than to the CT module's own buffer, and the queue entry
is redundant for this shape (kept as the general invariant, measured inert). See
[design/stage16-ergonomics/repl-libraries.md](../design/stage16-ergonomics/repl-libraries.md)
§3.3 for the rest, including the one batch shape D9 leaves open — a CT-defined
type named in a *signature*, which the prescan refuses before any emission.
