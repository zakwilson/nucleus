# REPL function redefinition

The REPL currently rejects redefinition of an already-defined function
with `error: cannot redefine '<name>' in REPL` (`src/nucleusc.nuc:3865`).
Redefinition is the single biggest friction point for agent-driven
REPL use, identified in [stage6-cleanup.md](stage6-cleanup.md) under
"LLM interactions" and listed as item 6 in
[stage6-plan.md](stage6-plan.md), where it was deferred during stage-6
implementation.

## Why it was deferred

Discovery #5 in [stage6-plan.md](stage6-plan.md): the LLVM C bindings
exposed in `lib/llvm.nuch` do not include the ORC resource-tracker
APIs that would let us cleanly remove an old definition before adding
its replacement. ORC's main JITDylib rejects symbol redefinition by
default, so a naive "compile and add" attempt fails when the symbol
already exists.

Two tractable paths were identified; the cleaner one (per-form
modules + resource trackers) needs new bindings, and the rougher one
(IR-name suffixing) needs invasive plumbing through `emit-defn`. The
choice between them is the design call this document is meant to
unblock.

## Designer:

(Not yet written — robot below proposes an approach.)

## Robot:

### Goal

`(defn foo:i64 () 1)` followed by `(defn foo:i64 () 2)` succeeds. A
subsequent `(foo)` returns 2. A function `bar` that calls `foo`,
defined either before or after the `foo` redefinition, also sees the
latest `foo`.

Captured function pointers from the old definition keep pointing at
old code. This matches every other JIT'd Lisp and is documented, not
fixed.

### Two implementation paths

**Path A — resource trackers + per-form modules.** ORC supports
`LLVMOrcCreateNewResourceTracker(jd)` to create a tracker bound to a
JITDylib, `LLVMOrcLLJITAddLLVMIRModuleWithRT(jit, rt, tsm)` to add a
module under a tracker, and `LLVMOrcResourceTrackerRemove(rt)` to
remove every symbol added under that tracker. The natural unit is
*one tracker per top-level form*: define `foo`, get tracker T1; redefine
`foo`, remove T1's symbols, then add the new `foo` under T2.

This is the path the LLVM project recommends and the one that
generalizes to "remove this definition" (for an `unset!` form later).
The cost is exposing three new bindings in `lib/llvm.nuch` and storing
a resource-tracker handle next to each definition in the REPL's
symbol table.

**Path B — IR-name suffixing.** Rename the LLVM symbol on each
redefinition: `foo` → `foo__1`, `foo__2`, etc. The Nucleus-level name
stays `foo`; the symbol-table entry maps `foo` to whatever IR name was
used most recently. References to `foo` from later code resolve through
the symbol table at IR-emission time, so they pick up the new IR
name automatically.

This works without new LLVM bindings but requires plumbing an
`ir-name` parameter through `emit-defn` and any helper that emits a
function definition or a call site. It's also strictly worse for
debuggability — the IR symbol no longer matches the source name.

**Recommendation:** Path A. The binding additions are small and
symmetric with the bindings we already expose, and the design
generalizes cleanly. Path B is the fallback if ORC's resource-tracker
API turns out to behave differently from the C++ docs at the C-binding
level.

### Detailed design (Path A)

**1. New bindings.** Add to `lib/llvm.nuch`:

```
LLVMOrcResourceTrackerRef
LLVMOrcCreateNewResourceTracker(LLVMOrcJITDylibRef JD);

LLVMErrorRef
LLVMOrcResourceTrackerRemove(LLVMOrcResourceTrackerRef RT);

void
LLVMOrcReleaseResourceTracker(LLVMOrcResourceTrackerRef RT);

LLVMErrorRef
LLVMOrcLLJITAddLLVMIRModuleWithRT(
  LLVMOrcLLJITRef J,
  LLVMOrcResourceTrackerRef RT,
  LLVMOrcThreadSafeModuleRef TSM);
```

These four are all that's needed.

**2. Per-form modules.** `repl-jit-module` (`src/nucleusc.nuc:4074`)
already exists; the change is making it run *per top-level form* rather
than per session. Each form gets a fresh `LLVMModuleRef`, its own
`LLVMOrcThreadSafeModuleRef` wrapper, and a fresh resource tracker.
The IR text accumulator that currently spans the whole REPL session
becomes form-scoped.

**3. Tracker storage.** The REPL's symbol table grows a per-symbol
`tracker:LLVMOrcResourceTrackerRef` field. On redefinition: look up
the old tracker, call `LLVMOrcResourceTrackerRemove`, then
`LLVMOrcReleaseResourceTracker`, then proceed with the normal define
path under the new tracker.

**4. Lookup invalidation.** The REPL caches `LLVMOrcExecutorAddress`
values returned from `LLVMOrcLLJITLookup`. On redefinition, those
caches must be invalidated for the redefined name. Simplest: don't
cache — look up every time. The cost is a hash lookup per call from
the REPL's outer driver, not from JIT'd code, so it's negligible.

**5. Drop the rejection.** Remove the `cannot redefine` error path at
`src/nucleusc.nuc:3865`. Replace with a "redefining" notice for
parity with the existing "defined" notice at `:3826`.

### Edge cases

- **Redefining with a different signature.** `(defn foo:i64 () 1)` then
  `(defn foo:ptr () "hi")` — allow it. Existing callers had the old
  signature compiled in; they'll fail at lookup time when the symbol
  resolves to the new function with the wrong type. That's the same
  failure mode as any JIT'd dynamic language and matches the
  documented "captured pointers go stale" caveat.

- **Mutually recursive definitions.** `(defn even:i64 (n:i64) ...)`
  references `odd` before `odd` is defined. Today the compiler emits
  a `declare` for `odd` and ORC resolves it on first call. With per-
  form modules, the `declare` lives in `even`'s module and the
  `define` lives in `odd`'s module — ORC's symbol resolver handles
  this fine across modules in the same JITDylib.

- **Redefining a macro.** Macros run at compile time and are stored in
  a separate table. Redefining a macro is a separate problem (the
  macro JIT module has its own lifecycle; see Discovery #3). Not in
  scope for this doc — file as a follow-up.

- **`unset!` / `undefn`.** Once resource trackers are wired up,
  removing a definition is `LLVMOrcResourceTrackerRemove` plus the
  symbol-table entry deletion. Add as a separate REPL form
  (`(undefn foo)`) — small surface, useful for agents that want to
  reset state.

### Test plan

- Define `foo` returning 1; call `(foo)` → 1.
- Redefine `foo` returning 2; call `(foo)` → 2.
- Define `bar` calling `foo`; call `(bar)` → 2.
- Redefine `foo` returning 3; call `(bar)` → 3.
- Capture `fp:ptr` = `foo` after the first definition; redefine `foo`;
  call through `fp` — must still return 1 (documented behavior).
- Redefine `foo` with a different return type; call through the new
  signature works; old captured `fp` produces undefined-but-not-crash
  results (or document a "stale pointer" failure mode if we choose to
  detect it).

### Completion criteria

- The `cannot redefine` error is gone for ordinary `defn` redefinitions
  at the REPL.
- Functions calling redefined functions see the latest definition.
- The compiler self-hosts and the existing test suite passes.
- The four new LLVM bindings are documented in `docs/builtins.md` (or
  wherever LLVM bindings live).
- A REPL session demonstrating redefinition is captured in the
  test suite.
