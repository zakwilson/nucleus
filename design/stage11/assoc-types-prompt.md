# Associated types — implementation prompt

You are implementing **associated types for protocols** in the Nucleus
self-hosting compiler. The full design, rationale, and revision history live in
**[assoc-types.md](assoc-types.md)** — **read it first**; it is the source of
truth. This file is the condensed build order, the subagent task split, and the
acceptance gates. When this prompt and the design doc disagree, **the doc wins**;
if you believe the design itself is wrong, **stop and raise it** rather than
silently diverging.

This rung removes the phantom-param tax on iterator/function-object combinators
(cleanup §4b) and subsumes the deferred "parametric-protocol `&where`" frontier
(parametric-structs *Known limitations #3*).

## The one idea to hold onto

There is **no new declaration syntax** and **no "parametric vs associated"
distinction**. The conformance registry already dedups on `(type, protocol)`
(`conformance-add`, src/nucleusc.nuc:~5964), which *is* associated-type
coherence — so every parametric-protocol parameter is recoverable. The entire
feature is:

1. **Retain** the parametric arguments in the conformance record (today they are
   checked by `emit-extend` and then **discarded** — `Conformance` stores only
   `{type-name, proto-name}`).
2. **Generalize** the `&where` constraint `(Protocol Var)` to a protocol
   *application* `((Protocol Arg…) Var)` — the same spelling `extend` already
   uses. Each `Arg` is **recovered** when it is an unbound tyvar, **constrained**
   (checked) when it is concrete/already-bound.
3. **Bind** those recovered tyvars at dispatch by reading them back out of the
   conforming variable's conformance record.

No infix `=`, no `with` keyword, no `(type …)` marker.

---

## How to run this (orchestration — enforced by CLAUDE.md)

This is a multi-phase compiler task touching one enormous file
(`src/nucleusc.nuc`). **Do not implement it in the orchestrating thread.** Split
it into the tasks below and dispatch each to the named local subagent (roster:
[context/local.md](../../context/local.md)). Keep the main thread for planning and
integration only.

**Context-budget rule — keep every task well under 100K tokens.** Every task
below names the *specific functions / line anchors* to read. Line numbers are
**approximate anchors that will have drifted — grep by name.** Instruct each
agent to:

- read only the named functions, plus `assoc-types.md` and this file;
- **mirror existing parametric-protocol / monomorphizer code** (`emit-extend`,
  `generic-method-bind`/`unify-tpat`, `register-generic-defn`) rather than invent
  a parallel mechanism;
- return a concise summary (what changed, which functions, surprises), not file
  dumps.

**Dependency order:** `A0` is the data foundation and gates everything. `A1`
(parser) is independent of `A0` and can proceed in parallel, but **A1 and A0 both
touch `src/nucleusc.nuc` — dispatch sequentially** to avoid merge friction. `A2`
(binding) depends on **both** A0 and A1. `A3` (tests/docs) is last.

**After every implementation task**, dispatch **build-test-runner** for
`make test` + `make bootstrap` and confirm the boot artifacts re-converge. Do not
start the next task until the tree is green.

## Authoritative decisions (do not re-litigate)

From `assoc-types.md`, including its §0 revision note:

1. **Constraint surface is `((Protocol Arg…) Var)`** — a protocol application in
   the slot where a bare protocol symbol already goes; the conforming variable
   stays in **tail position**; the constraint stays a **2-element list**. A bare
   symbol in element 0 remains the plain (no-parameter) protocol, unchanged.
2. **Recover vs. constrain is decided by the argument, not the protocol.** Unbound
   tyvar arg → recover; concrete/bound arg → check for equality. This is exactly
   how `unify-tpat` already treats positional args.
3. **Coherence:** one conformance per `(type, protocol)`. A second `extend` of the
   same pair with *different* args is an **error** (today it is silently dropped).
4. **No `(type …)` declaration, no `with`, no `=`.** Parametric protocols are
   declared exactly as they are today.
5. **Determination and dispatch-time binding are fixpoints** (a tyvar recovered by
   one constraint can be the input of another — `S` from `((Iterator S) I)` feeds
   `((UnaryFn S E) F)`).

## Non-negotiable invariants

- **Byte-identical bootstrap throughout.** The compiler's own source uses no
  associated-type bound, so **nothing here may change compiler output.** A0 edits
  hot paths (`emit-extend`, `conformance-add`) that run for every `extend` in the
  compiler and libs — behaviour (which conformances record, which methods resolve)
  must be unchanged, so the emitted IR is unchanged. **A bootstrap diff is a bug
  — investigate before proceeding.** Re-converge and confirm the IR diff is empty
  after each task.
- **Zero runtime overhead.** Associated types are a compile-time inference; a
  monomorphized method must be byte-identical to the same method written with the
  types spelled out. No dispatch object, no RTTI.
- **Typos still caught.** A tyvar that is neither parameter-determined nor
  recoverable from a determined constraint stays an error (the existing
  "not determined by any parameter" diagnostic, extended to the fixpoint).
- **Library code stays in libraries.** The combinator types (`MapIter`,
  `UnaryFn`, …) that exercise this feature are example/library code, not compiler
  changes.

---

## Verify the ground before you build

The committed `bin/nucleusc` may link a newer libLLVM than the container ships; if
it fails to exec (exit 126/127), rebuild from committed IR with `make boot-binary`
(or `make ensure-boot`) first. Then confirm, with throwaway `.nuc` files, the
three load-bearing premises:

1. **`&where` rejects a parametric constraint today.** `&where ((Iterator S) I)`
   fails at `register-generic-defn` ("each &where constraint must be (Protocol
   Var)", src/nucleusc.nuc:~5110) — this is what A1 lifts.
2. **Concrete conformance args are discarded today.** `(extend IntRangeIter
   (Iterator i32))` records `(IntRangeIter, Iterator)` with no `i32` (the
   `Conformance` struct, src/nucleusc.nuc:~378, has only `type-name`/`proto-name`)
   — this is what A0 fixes.
3. **The phantom-param verbose workaround compiles** (`examples/phantom-tyvar-test.nuc`
   / `MapIterVerbose I F S E`) — this is the baseline the new form replaces, and
   it must keep working (migration §4.3).

If any premise no longer holds as `assoc-types.md` describes, **stop and report.**

---

## What to build (in order)

### A0 — Retain conformance arguments (the data foundation)

**Agent: systems-impl-engineer.** Mechanism-heavy; gates A2. §§3.1, 3.2, 3.7.

**Read (scoped):** `Conformance` struct (src:~378); `conformance-lookup` /
`conformance-add` (src:~5954/5964); `emit-extend` and its `conformance-add` call
site (src:~6230) including where it resolves and count-checks the protocol args
against the protocol's `params`/`num-params` (`Protocol` struct, src:~365);
`TmplConformance` (src:~388), `tmpl-conformance-add` (src:~6250), and the
per-stamp check `tmpl-conformance-check-instance` (called from src:~2398); the
`.nuch` export/import path for `extend` (grep `emit-nuch` for the extend/defprotocol
branch) to confirm conformances re-run `emit-extend` on import.

**Build:**

1. Add `args:ptr` (array of resolved `Type*`, or type-spelling `Node*` — match
   whatever `emit-extend` has in hand at the call) and `nargs:i32` to
   `Conformance`. Empty/null for a plain protocol.
2. Thread the resolved protocol-application arguments through `conformance-add`
   into the new fields. Keep the `(type, proto)` dedup; additionally **reject a
   re-`extend` of the same pair with differing args** (coherence) with a clear
   diagnostic. (A re-`extend` with *identical* args stays a silent no-op.)
3. At stamp time, `tmpl-conformance-check-instance` must record the **substituted
   concrete** args in the per-instance `Conformance` (the template binding nodes
   substituted with the concrete instance args), not drop them.
4. Confirm the `.nuch` path repopulates `args` for free by re-running `emit-extend`
   on import (rule (a), §4.5). If it does **not** re-run `emit-extend`, note it and
   surface to the orchestrator — do not silently serialize a half-feature.

**Watch:** the coherence error (step 2) could fire during bootstrap if any current
lib double-extends a pair with different args. That would be a real latent issue —
surface it, don't paper over it.

**Done when:** every `extend` records its parametric args; `(extend IntRangeIter
(Iterator i32))` stores `args=[i32]`; a stamped `(Vector i32)` from `(extend
(Vector T) (Seq T))` stores `args=[i32]`; re-extend with different args errors;
the conformance args survive `.nuch` round-trip. **Bootstrap byte-identical**
(this only *adds* recorded data; no codegen change). → **build-test-runner.**

### A1 — Generalize the `&where` constraint parser

**Agent: systems-impl-engineer.** §§3.3, 3.4. Independent of A0 (parse + sizing),
but lands sequentially (same file).

**Read (scoped):** `register-generic-defn` (src:~5068) end to end — the constraint
loop (src:~5108, the "each &where constraint must be (Protocol Var)" /
"must name a protocol and a variable" checks), the capacity sizing via
`count-pattern-nodes` (src:~5093–5102), the tyvar collection via
`collect-pattern-tyvars` (src:~5126–5132), and the determination check
(src:~5133–5148); the `Method` struct's constraint fields `con-protos` /
`con-vars` / `num-constraints` (src:~346); helper `binding-type-node`,
`pattern-determines-tyvar` (grep).

**Build:**

1. Generalize the constraint loop: each constraint is still a 2-list `(C V)` with
   `V` a symbol (the conforming variable). `C` may now be **either** a symbol
   (plain protocol, unchanged path) **or** a list `(P Arg…)` where `P` is the
   protocol-name symbol and `Arg…` are argument patterns.
2. Store, per constraint, the protocol name, the conforming variable, and the
   **argument-pattern nodes** (extend the `Method` constraint storage — e.g. add
   `con-args` (array of node arrays) + `con-nargs`, mirroring `con-protos`/`con-vars`).
3. Collect tyvars appearing in `Arg…` into the method's tyvar set via the existing
   `collect-pattern-tyvars`, and size capacity by walking the constraint arg nodes
   with `count-pattern-nodes` too. With this, **no special per-binding slot
   accounting is needed** — assoc tyvars are sized/collected by the same node-walk
   as parameter tyvars.
4. Extend the determination check to a **fixpoint**: seed with parameter-determined
   tyvars; repeat — for each constraint `((P Arg…) V)` whose `V` is determined,
   mark every tyvar in a recoverable `Arg` position determined; any tyvar still
   undetermined after the fixpoint is the existing error.

**Done when:** `&where ((Iterator S) I)` and `&where ((Iterator S) I) ((UnaryFn S
E) F)` parse and register their tyvars; a plain `&where (Ord T)` parses
identically to today; a genuinely undetermined tyvar still errors. (Binding is
A2 — a parsed-but-unbound associated bound need not yet *resolve* a call here, but
must not crash.) **Bootstrap byte-identical.** → **build-test-runner.**

### A2 — Dispatch-time binding from conformance args

**Agent: systems-impl-engineer.** §§3.5, 3.6. The core inference. Depends on
**A0** (args stored) and **A1** (constraints parsed).

**Read (scoped):** `generic-method-bind` (src:~5183) and `unify-tpat` (grep the
defn — the recursive positional unifier described src:~5176) and how `out-bound`
is filled per tyvar index; `conformance-lookup` extended in A0 (and a new
`conformance-args` accessor); `generic-resolve` / `generic-instantiate` /
`monomorphize-form` (grep) only enough to confirm recovered tyvars flow through
unchanged once in `out-bound`.

**Build:** after the standard positional unification fills `out-bound`, resolve the
constraints to a **fixpoint**. Repeat until no new binding:

- For each constraint `((P Arg…) V)` whose `V` is now bound to a concrete type `CV`:
  1. Look up `CV`'s `Conformance` for `P` (the A0 args-bearing record).
  2. Pair each `Arg[i]` with the conformance's `args[i]`: an **unbound** tyvar
     `Arg[i]` → bind it (recover); otherwise **unify** the two (constrain), failing
     on mismatch.

The recovered bindings augment the standard ones in the same `out-bound` map and
flow unchanged through `generic-method-bind` → `generic-instantiate` →
`monomorphize-form`. **No change** to `generic-resolve`/`generic-instantiate`
beyond consuming the now-complete binding.

**Error cases (clear diagnostics, not crashes):**
- `CV` does not conform to `P` → the existing missing-conformance diagnostic.
- Conformance record has no `args` (stale `.nuch`) → "conformance for *P* recorded
  without parameter bindings; recompile".
- A constrain step mismatches → "constraint *P* parameter mismatch: expected
  S = i32, found i64".

**Done when:** the end-to-end `MapIter`/`UnaryFn` example from `assoc-types.md` §2.3
compiles, monomorphizes, and runs with **no phantom params**; `S`/`E` are recovered
from `I`/`F`'s conformances; a concrete constraint arg (`((Iterator i32) I)`) is
checked, not recovered; mismatches and missing conformances produce the diagnostics
above. **Bootstrap byte-identical.** → **build-test-runner.**

### A3 — Examples, tests, docs, progress (close-out)

**Agent: api-docs-writer** (docs/progress) with **focused-task-implementer** for
the example program.

- Add `examples/assoc-types.nuc` (+ `tests/expected/assoc-types.out`) exercising:
  a parametric `(Iterator E)` + a parametric function-object protocol (`(UnaryFn
  Arg Ret)`), a phantom-free `(MapIter I F)` with `&where ((Iterator S) I)
  ((UnaryFn S E) F)`, a standalone `collect-all` (§2.5), and at least one
  *constrain* case (`((Iterator i32) I)`) plus one expected-error case (commented
  or a separate `.nuc.fail` if the harness supports it). Wire into `make test`.
- Update [docs/generics.md](../../docs/generics.md): the constraint shape now
  admits a protocol application `((Protocol Arg…) Var)` with recover-vs-constrain
  semantics; remove the "Limitation: `&where` requires single-symbol bounds" note
  (now lifted). Update [docs/collections.md](../../docs/collections.md) /
  [docs/builtins.md](../../docs/builtins.md) where they say associated types are
  deferred.
- Append a **"Robot — implementation status"** section to
  [assoc-types.md](assoc-types.md) recording what landed, marking open questions
  Q2/Q3 resolved-as-designed and recording the Q4 (`.nuch`) decision actually taken.
- Update [progress.md](progress.md) (Stage 11 table) and confirm
  [overview.md](../overview.md) still describes the shipped surface; flip any
  "associated types deferred" row.
- **Self-improving context:** fix root causes; add a `context/` note only for a
  genuinely unfixable environment gotcha.

---

## Landmines (read before writing a line)

1. **Order is `((Protocol Arg…) Var)` — protocol first, variable last** — matching
   the existing `(Ord T)`. Do **not** flip it to `(Var (Protocol Arg…))`.
   (`extend` writes subject-first; `&where` writes protocol-first. That asymmetry
   is pre-existing — preserve it.)
2. **Recover vs. constrain is per-argument, decided at unify time** by whether the
   tyvar is bound yet. Do not branch on the protocol declaration.
3. **Both the determination check (A1) and the binding (A2) are fixpoints.** A
   single pass mis-handles interdependent constraints (`S` recovered then reused).
4. **`(Maybe ptr)` is niche-encoded** — pointer element types can't `match`. Keep
   the example's element types non-pointer.
5. **A0 touches `emit-extend`/`conformance-add` — hot paths.** Any behavioural
   change there breaks the byte-identical bootstrap. After A0 especially, confirm
   the IR diff is empty.
6. **Coherence error may surface a latent double-extend.** If A0's "differing args"
   check fires during bootstrap, that is a real issue in existing source — report
   it, don't suppress the check.

---

## Explicitly out of scope (do not build)

- **Higher-kinded associated types** (a recovered arg that is itself parametric
  with a free var, e.g. `Elem = (Maybe T)`). Concrete/fully-applied args are fine.
- **Lambdas / closures** — function objects stay named structs conforming to a
  `UnaryFn`/`BinaryFn`-style protocol.
- **Multi-conformance with differing args** — forbidden by coherence (A0 step 2).
- **Lifting `hmap-get`/`keys`/`vals` to `Assoc` protocol methods** — mechanically
  enabled by this feature, but its own task; this pass lands the
  Iterator/function-object combinator path only.
- **Return-only / `dyn` tyvars** — unchanged; still rejected.

## Close-out checklist (required by AGENTS.md)

- After **every** task: `make test` + `make bootstrap` green, boot artifacts
  re-converged, the compiler compiles itself — via **build-test-runner**.
- Bootstrap stayed **byte-identical** across the whole pass (no task adopts an
  associated-type bound in the compiler's own source).
- A3 examples/tests/docs/progress/overview landed; `assoc-types.md` carries an
  implementation-status section with the resolved open questions.
