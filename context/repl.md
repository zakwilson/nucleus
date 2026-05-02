# Using the Nucleus REPL during development

The REPL is `build/nucleusc -i` (or `--interactive`). It runs the same compiler
binary in interactive mode: each top-level form is parsed, compiled to LLVM IR,
added to a persistent JIT session, and (for expression forms) called
immediately. Definitions persist across forms; errors are recovered via
`repl_throw` (setjmp/longjmp shim in `src/repl_shim.c`) instead of exiting.

stdio.h, stdlib.h, string.h, ctype.h, and unistd.h are pre-loaded at startup,
so libc functions are available without an explicit `(include ...)`.

## When LLM agents should reach for the REPL

Prefer the REPL when iteration speed matters more than reproducibility:

- **Probing language/compiler behavior.** "Does `(cast i64 -1)` sign-extend?",
  "What's the printed form of an empty `defstruct`?", "Does this macro expand
  the way I think?" — one form in the REPL beats writing a throwaway
  `examples/foo.nuc`, running `./build.sh`, and reading the output.
- **Exploring a library before using it.** Import the lib, call its functions
  with sample inputs, inspect return values. Faster than reading code top-down.
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
