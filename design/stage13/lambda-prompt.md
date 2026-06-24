# Lambdas and closures — implementation prompt

You are implementing the four lambda/closure forms (`fn`/`vfn`/`mfn`/`cfn`), the
`Clone` protocol, and the generalized frame-region escape analysis they depend
on. The full design and rationale live in [lambda.md](lambda.md); **read it
first** — this file is the condensed build order, the task split for the local
subagents, and the acceptance gates. Read lambda.md for the *why*; read this file
for *what to build, in what order, and who builds it*.

## How to run this (orchestration)

This is a multi-phase compiler task. **Do not implement it in the orchestrating
thread.** Split it into the tasks below and dispatch each to the named local agent
(roster: [context/local.md](../../context/local.md)). Keep the main thread for
planning and integration only.

**Context-budget rule — keep every task well under 100K tokens.** The compiler
core is large; an agent that reads it whole will blow its budget. Every task below
names the *specific functions / subsystems* to read. **There are no line anchors —
grep by name.** Instruct each agent to read only the named functions plus
lambda.md and this file, mirror existing mechanisms rather than invent parallel
ones, and return a concise summary (what changed, which functions, surprises), not
file dumps.

**Dependency order.** `L0` (ground-verify) anchors the rest. `L1` (escape
generalization) is the gating soundness fix and the one **non-additive** phase —
land it first. `L2` (`Clone`) is independent of `L1` but edits the compiler core,
so dispatch the two **sequentially**, not in parallel. `L3` (`fn` + capture
analysis) gates the closure machinery; `L4` (`vfn` + env + `invoke`) is the core
and depends on `L2`/`L3`; `L5` (`mfn`) and `L6` (`cfn`) depend on `L4` (and `L1`);
`L7` (conformance derivation) depends on `L4`; `L8` (C interop) depends on
`L3`–`L6`; `L9` (docs) is last.

**After every implementation task**, dispatch **build-test-runner** to run
`make test` + `make bootstrap` and confirm the boot artifacts re-converge. Do not
start the next task until the tree is green.

## Authoritative decisions (do not re-litigate)

From lambda.md:

1. **Four forms, capture mode fixed by keyword** (no per-variable capture list):
   `fn` (no runtime capture → function pointer), `vfn` (clone-capture, source
   survives), `mfn` (move-capture, source consumed), `cfn` (reference-capture,
   allocator + escape-checked).
2. **All closures lower to an anonymous struct (captured state) + an `invoke`
   method** of the closure's natural arity, callable through the existing
   callable-values routing — **no fixed arity, no mandatory `UnaryFn`/`FoldFn`
   conformance.**
3. **`fn` is a bare function pointer.** Its body may reference its own params,
   top-level names (not capture), and — *first cut* — **no enclosing locals at
   all**. Referencing a runtime local is a compile error pointing to
   `vfn`/`mfn`/`cfn`. (The "inlinable compile-time-constant local" relaxation is
   deferred — see out-of-scope.)
4. **`vfn` captures by clone** via the new `Clone` protocol. POD capture = bitwise
   clone (closure owns nothing, no `Drop`); `Drop` capture = deep clone (closure
   owns the copy → conforms to `Drop` with a synthesized method). **The source is
   never invalidated.** A `Drop` type with no `Clone` cannot be `vfn`-captured.
5. **`mfn` captures by move** through the existing `move` sink: source consumed
   (use-after-move), closure owns the resource and conforms to `Drop` (synthesized,
   drops the moved fields), **no allocator**, travels by value. It is the form that
   exports an owned value out of a `with` scope (the move disarms the source's
   `with`-cleanup, so the return is sound).
6. **`cfn` captures by reference**, takes an allocator (for the *environment's*
   storage when it must outlive the frame, not the referents), conforms to `Drop`
   to free that environment, and is escape-checked: the closure inherits each
   captured reference's region and may not escape it.
7. **Function-protocol conformance is derived structurally on demand.** When a
   closure flows into a `&where ((P …) F)` position, the compiler matches `invoke`
   against `P`'s single required method and synthesizes the conformance, reading
   the bound args off `invoke`'s signature. Producers never pre-`extend`.
8. **Escape analysis generalizes** from owned heap resources to **all frame-local
   storage**: taking the address of a `let`/`with` value binding, an `alloca`
   result, or a by-value parameter taints a region-tagged pointer that may not
   escape upward. **`let` gains no drop and no lifetime semantics** — this is a
   pointer-provenance check, not ownership.
9. **Capturing closures are not C-callable**: a public signature mentioning a
   closure type is excluded from `--emit-cheader` and warns; `fn` is emitted
   normally.

## Non-negotiable invariants

- **Additive at the IR level, except L1.** No existing source uses `fn`/`vfn`/
  `mfn`/`cfn` or `Clone`, so `L2`–`L9` must keep `make bootstrap` a fixed point and
  the boot artifacts byte-identical. **`L1` is the exception** — it adds an
  analysis check that runs over *all* code, so it can surface pre-existing sites;
  handle it with the Phase-F measure-then-flip discipline (warn-first, enumerate,
  triage, then error). A byte-identical bootstrap after L1 means either no compiler
  site takes-address-of-a-frame-local-and-escapes-it, or the genuine ones were
  fixed.
- **Zero overhead on the `fn` / POD-`vfn` path.** A `fn` is a plain function
  pointer; a POD `vfn` clone is a bitwise copy. These, inlined into a generic
  combinator, must monomorphize to the same IR a hand-written loop produces. Only
  owning/reference closures pay for an environment + indirect call.
- **Generated names must be IR-legal.** Lifted functions and synthesized `invoke`/
  `drop`/`clone` methods must never carry `!`/`?` in their emitted names (LLVM
  rejects them — see context/build.md); route generic method names through the
  existing `sanitize-for-ir` path and gensym lifted-function names without those
  chars.
- **C-ABI neutrality for `fn`.** A non-capturing `fn` decays to a real function
  pointer with the platform ABI; nothing about the closure forms changes the ABI
  of existing code.

---

## L0 — Ground-verify (read-only research)

**Agent: Explore** (or general-purpose). Read-only; produces the line anchors and
assumption-checks the build tasks need, keeping that reading out of the main thread.

**Find and report (concise map, not file dumps):**

1. **Escape/taint machinery** — where taint originates and is propagated in
   `node-type`; the escape sinks on `return` and store-out; `pkind-flow-check`; the
   `with` owning-binding logic (`emit-with` or equivalent); the `move` form; the
   `addr-of`/`.&`/`ptr+`/`cast` emitters that propagate taint. Confirm whether
   taint is a boolean or already carries any scope/region tag.
2. **Callable-values / `invoke`** — `emit-dispatch`, `emit-get-with-callee`, and
   how a non-function head routes to `invoke` (`docs/special-forms.md`; `lib/seq.nuc`).
3. **Generics/conformance** — `g-generics`, `generic-resolve`, `generic-instantiate`,
   `unify-tpat`, `check-generic-templates`/`gcheck`, the `Conformance` record,
   `emit-extend`, `register-imported-conformance`.
4. **Struct templates + mangling** — `register-struct-template`,
   `struct-template-stamp`(`-types`), `subst-tyvars-node`, `type-mangle-token`,
   `mangle-fn-name`, `finalize-generics`, `sanitize-for-ir`.
5. **Top-level emission + worklist** — the top-level form loop (`emit-toplevel-forms`),
   the deferred worklist generic instantiation queues and drains, and the IR streams
   (`g-decl-stream`/`g-def-stream`). **Key assumption to confirm:** a lifted
   top-level `defn` can be queued from inside expression emission and drained like a
   generic stamp.
6. **`Drop` dispatch + a synthesis precedent** — how `with` emits `(drop b)`; how a
   collection's hand-written `drop` is structured. **Confirm there is no existing
   "synthesized drop"** (closures will need a generated one) and identify the
   closest emission pattern to model it on.
7. **`gensym`** availability for fresh names.

**Done when:** the map above is returned with function names (and approximate
locations) for L1–L8, and assumptions 5 and 6 are confirmed or corrected.

### L0 findings (recorded — grep by NAME; line numbers may drift)

**Taint model — KEY:** taint is a **`Scope*` pointer** (field `taint` on the `Val`
struct, `src/compiler-types.nuc` ~281), NOT a boolean: it carries the owning scope
or null. Region tagging is therefore a natural extension, not a rewrite.

1. **Escape/taint** — `emit-addr-of` (`src/nucleusc.nuc` ~2371) returns a Val with
   `taint = sym.taint` (primary new-taint-source site); `node-type-addr-of`
   (`src/generics.nuc` ~2971) is the type-check mirror (sets pkind PTR-REF).
   `emit-return` (`src/nucleusc.nuc` ~2896–2910) is the escape sink — currently
   dies if `v.taint != null` ("resource bound by `with` escapes via return").
   `pkind-flow-check` (`src/type-utils.nuc` ~274). `emit-with` (~2987–3074) sets
   `sym.owns=1`, `sym.cslot`, `sym.taint=inner` (the Scope*). `emit-move` (~2820)
   disarms + marks `moved=1` + clears taint. Taint propagates through
   `emit-field-addr` (~2645), `emit-ptr-add` (~2564), `emit-cast` (~3300).
2. **Callable-values/`invoke`** — `emit-dispatch` (`src/nucleusc.nuc` ~3974–4115)
   is the special-form `when (= hp '…)` chain; `emit-callable-value` (~2224) routes
   invoke→get→_get; `emit-invoke-with-callee` (~2193) looks up the "invoke" generic;
   `emit-get-with-callee` (~2155). No fixed arity. Closure keywords `fn`/`vfn`/`mfn`/
   `cfn` go in the dispatch chain near `move` (~4106).
3. **Generics/conformance** — `generic-resolve` (`src/generics.nuc` ~422, tiers 0–2),
   `generic-instantiate` (~1323, stamps + queues a MonoJob), `unify-tpat` (~758),
   `check-generic-templates`/`gcheck` (~1730), `Conformance` defstruct
   (`src/compiler-types.nuc` ~395: type-name, proto-name, args, nargs), `emit-extend`
   (`src/generics.nuc` ~2634), `register-imported-conformance` (~2864),
   `blanket-conforms`/`blanket-lookup` (~2008–2032, the Any/Struct structural path).
4. **Struct templates + mangling** — `register-struct-template`
   (`src/union-registry.nuc` ~695), `struct-template-stamp-types` (~799),
   `struct-template-stamp` (~888), `subst-tyvars-node` (`src/type-mangle.nuc` ~110),
   `type-mangle-token` (~12, ptr→`p`-prefix), `mangle-fn-name` (`src/generics.nuc`
   ~176, `@prefix.fname.tok…`), `finalize-generics` (~339, assigns ir-names),
   `sanitize-for-ir` (`src/format.nuc` ~46, replaces `!`/`?`→`_`).
5. **Top-level + worklist** — `emit-toplevel-forms` (`src/nucleusc.nuc` ~5971–6117),
   calls `drain-mono-worklist` (`src/generics.nuc` ~1953) at the end; worklist is
   `g-mono-worklist` (Vector of `MonoJob*`; `MonoJob` defstruct = form, context,
   `src/compiler-types.nuc` ~435). IR streams `g-type/decl/def-stream`
   (`src/nucleusc.nuc` ~198–206). **Assumption 5 CONFIRMED:** a lifted top-level
   `defn` can be queued from inside expression emission and drained like a generic
   stamp.
6. **Drop dispatch + synthesis** — `emit-drop-cleanup` (`src/nucleusc.nuc` ~2842,
   null-guarded drop), `emit-scope-cleanups` (~2867, walks cleanup slots in reverse),
   `emit-walk-cleanups` (~2890, scope parent chain); manual `(drop binding)` on an
   owned binding is rejected in `emit-dispatch` (~3977). **Assumption 6 CONFIRMED:
   no synthesized drop exists** — closures generate the first; model it on
   `emit-scope-cleanups` (reverse, null-guarded, per-field drop dispatch).
7. **`gensym`** — `nucleus_gensym` FFI (`src/nucleusc.nuc` ~458, counter `g-gensym-id`
   ~290); emitted as a special form (~4050); returns an IR-legal `ptr` (no `!`/`?`).
   For deterministic lifted/closure names, prefer the struct-template-style mangling
   (`type-mangle-token` per capture type) over runtime gensym; route through
   `sanitize-for-ir`.

---

## L1 — Generalize the escape analysis to frame-local storage

**Agent: systems-impl-engineer.** The gating soundness fix and the only
non-additive phase. Mechanism-defining.

**Read (scoped):** the L0 escape map — taint origin/propagation in `node-type`,
the `return`/store-out sinks, `pkind-flow-check`, `move`, `addr-of`/`.&`.

**Build:**

1. **New taint source:** taking the address of frame-local storage — `addr-of`/
   `.&`/equivalent on a `let`/`with` value binding, an `alloca` result, or a
   by-value parameter. **Exclude** reference/pointer parameters (pointee is
   caller-owned) and pointers loaded *out of* a frame-local (existing imprecision
   boundary).
2. **Regions:** tag each frame-local pointer with the **scope-id** of the storage
   it points into. A store/return is an escape iff the destination outlives (is a
   lexical ancestor of) the source's region; `return` is the outermost destination.
   Preserve the existing shape — downward flow (args, inner scopes) is a borrow and
   stays legal; only upward escape is rejected. `move` and copy/`deref`-out still
   clear taint.
3. **Measure-then-flip (Phase F discipline).** First run the new check **warn-only**;
   dispatch build-test-runner to compile `src/`+`lib/`+`examples/` and **enumerate**
   any flagged sites. Triage: genuine `return &local`/store-out bugs get fixed; any
   false positive (e.g. a returned pointer derived from a `ref` param mis-attributed
   as frame-local) is refined out of the taint source. Only when the set is empty
   does the check become a hard error.

**Done when:** `(return (addr-of x))` for a `let`/`alloca`/by-value-param `x` is a
compile error; `(.& v …)` through a `(ref …)` parameter still returns fine; the
`alloca`+`with` collection idioms still build; and **`make bootstrap` is a fixed
point** (any surfaced compiler site fixed or refined away). → **build-test-runner.**

---

## L2 — The `Clone` protocol

**Agent: systems-impl-engineer.** Independent of L1; edits the core, so dispatch
after L1, not alongside it.

**Read (scoped):** how the hardcoded blanket protocols `Any`/`Struct` are
recognized (the structural-predicate path, not user `extend`) — `docs/generics.md`
§"Bound kinds"; the protocol registry and `extend` checking; how `Drop`-ness of a
type (transitive) is determined.

**Build:**

1. `(defprotocol Clone ((clone Self) ((self (ref Self)))))` registered as a known
   protocol.
2. **Automatic conformance** for any trivially-copyable type — a primitive or a
   struct with **no `Drop` field transitively** — as a compiler-known structural
   rule (modeled on `Struct`/`Any`, *not* user `extend`); its `clone` is a bitwise
   copy.
3. An owning type conforms by **hand-written** `clone`. A `Drop` type with no
   `Clone` conformance is *not* `Clone` (L4 turns a `vfn` capture of it into the
   directed "use `mfn`" error).

**Done when:** a primitive and a `Drop`-free struct satisfy a `&where (Clone T)`
bound with a bitwise clone; a hand-written `clone` on an owning type conforms; a
bare `Drop` struct does not. **Bootstrap byte-identical.** → **build-test-runner.**

---

## L3 — `fn` + free-variable/capture analysis + lambda lifting

**Agent: systems-impl-engineer.** Depends on L0. Builds the capture analysis L4
extends.

**Read (scoped):** the special-form dispatch in the emitter (how `with`/`let` are
recognized); param/return-type parsing for `defn` (reused for `(params):ret`,
honoring the colon-paren caveat — a parenthesized return type uses the list form);
the top-level worklist + `gensym` from L0; the fn-name→function-pointer decay.

**Build:**

1. Parse `(fn (params):ret body…)`. Run **free-variable analysis** over the body:
   classify each free symbol as a parameter, a top-level name (fine — not capture),
   or an **enclosing local** (capture).
2. **`fn` rejects any enclosing-local capture** (first cut) with a directed error:
   *"`fn` cannot capture runtime local 'x'; use vfn (clone), mfn (move), or cfn
   (reference)."*
3. **Lambda-lift** the `fn` body to a fresh gensym'd top-level `defn` (IR-legal
   name), queued on the top-level worklist and drained like a generic stamp; the
   `(fn …)` expression's value is that function's pointer (existing decay).

**Done when:** `(fn (x:i32):i32 (* x x))` yields a callable function pointer usable
inline and storable; referencing a top-level `defconst` works; referencing a
runtime local errors with the directed message. **Bootstrap byte-identical.** →
**build-test-runner.**

---

## L4 — Closure environment + `invoke`, and `vfn`

**Agent: systems-impl-engineer.** The core. Depends on L2 (`Clone`) and L3
(capture analysis + lifting).

**Read (scoped):** L3's capture analysis; struct-template stamping +
`subst-tyvars-node` (the anon struct is a generated struct type); generic-method
emission + `sanitize-for-ir` (the `invoke`/`drop` methods are generic methods);
callable-values `invoke` routing (L0); the `Clone` resolution from L2; the `with`
`(drop b)` dispatch (L0) for the synthesized drop.

**Build:**

1. For a capturing closure, generate an **anonymous struct** with one field per
   captured local; the form's value is an instance with the fields populated.
2. Generate an **`invoke` method** `((self (ref <Env>)) <params>) -> ret` whose body
   is the lambda body with each capture rewritten to an env-field access and each
   param bound normally. Register it so callable-values routes `(c arg…)` to it.
3. **`vfn` semantics:** populate each field by **`clone`** (every capture must
   conform to `Clone`, else the directed "use `mfn`" error). If any cloned field is
   `Drop`, the closure struct conforms to `Drop` with a **synthesized `drop`** that
   drops the owned fields in reverse order, null-guarded (model on the `with` drop
   dispatch). A POD-only `vfn` is a plain non-owning by-value struct.

**Done when:** `(vfn (x:i32):i32 (* x factor))` over an `i32` local is callable and
inlines to a bitwise-copy env; a `vfn` cloning a `Drop` value is callable, owns the
clone, and its synthesized `drop` fires under `with`; the source is untouched in
both cases. **Bootstrap byte-identical.** → **build-test-runner.**

---

## L5 — `mfn` (move-capture)

**Agent: focused-task-implementer** (reuses L4 machinery). Depends on L4 + L1.

**Read (scoped):** L4's env/`invoke`/synthesized-`drop`; the `move` sink (L0) — the
disarm + use-after-move marking.

**Build:** `mfn` populates each owned field by **moving** the captured local
through the `move` sink (disarm its `with`-cleanup, mark it consumed). The closure
owns the moved resources → synthesized `drop` over them (reuse L4); no allocator;
travels by value. Verify the **export-from-`with`** case: an `mfn` created inside a
`with`, moving the owned binding in, may be returned/`move`d out, and the resource
is freed via the closure's `drop` at its eventual scope.

**Done when:** moving an owned `Drop` local into an `mfn` consumes the source
(later use → use-after-move error), the returned closure owns and later drops the
resource, and no escape error fires because ownership transferred. **Bootstrap
byte-identical.** → **build-test-runner.**

---

## L6 — `cfn` (reference-capture)

**Agent: systems-impl-engineer.** Depends on L4 + L1.

**Read (scoped):** L4's env/`invoke`/drop; the `AllocHandle` model
(`docs/allocators.md`); L1's region tagging + escape sinks.

**Build:** `(cfn alloc (params):ret body…)` — env is a struct of **pointers** into
the captured locals; `alloc` (a `(ref AllocHandle)`, bare first operand) backs the
environment's storage when it must outlive the frame; the closure conforms to
`Drop` to free that environment via the allocator. **Region inheritance:** the
closure value inherits the region of each captured reference (L1); escaping any
captured referent's region is rejected at the existing sinks. Body-level
copy/`deref` extracts a value (clears taint) for results that must escape.

**Done when:** a `cfn` consumed within its referents' scope works; one that escapes
a captured `with`-owned referent's scope errors; a `with`-bound `cfn` frees its env
at scope exit. **Bootstrap byte-identical.** → **build-test-runner.**

---

## L7 — Structural function-protocol conformance derivation

**Agent: systems-impl-engineer.** Depends on L4. Enables closures as `map`/`reduce`/
`filter` arguments.

**Read (scoped):** `generic-resolve`/`unify-tpat`/the `Conformance` record (L0); how
`MapIter`/`reduce` express `&where ((UnaryFn S E) F)` (`docs/iterators.md`,
`docs/generics.md`).

**Build:** when a closure type flows into a `&where ((P …) V)` position where `P` is
a single-method "function-shaped" protocol, **match `invoke` against `P`'s required
method** and synthesize the closure's `(closure, P)` conformance, reading the bound
args (`S`, `E`) off `invoke`'s parameter/return types so recovery works. Decide and
document whether derivation fires for any single-method protocol or a recognized set
(watch the `(type, protocol)` coherence/dedup interaction).

**Done when:** an `fn`/`vfn` literal passed to a generic combinator bounded on
`(UnaryFn S E)`/`(FoldFn Acc E)` type-checks and stamps without a hand-written
function-object struct, and a `map`/`reduce` over a closure produces correct
results. **Bootstrap byte-identical.** → **build-test-runner.**

---

## L8 — C interop: cheader exclusion + warning

**Agent: focused-task-implementer.** Depends on L3–L6.

**Read (scoped):** `--emit-cheader`/`emit-cheader-*` and the `.nuch` declaration
emitters (`emit-nuch-*`); the closure-type marker from L4.

**Build:** a public function whose signature mentions a closure type — as return or
parameter — is **excluded from `--emit-cheader`** and **warns** at its definition.
A function that only *takes* a closure but isn't exported is unaffected; a
non-capturing `fn` (function pointer) is emitted to headers normally.

**Done when:** a closure-returning/closure-taking public `defn` is omitted from the
generated header with a warning; an `fn`-pointer-typed signature still emits.
**Bootstrap byte-identical.** → **build-test-runner.**

---

## L9 — Docs, examples, progress (close-out)

**Agent: api-docs-writer** (+ **focused-task-implementer** for example code).

- `examples/closures.nuc` (+ `tests/expected/`) exercising all four forms: an `fn`
  passed to a higher-order call, a POD `vfn` through `map`, an `mfn` exporting an
  owned value out of a `with`, and a `cfn` with the escape check; wire into
  `make test`.
- Document the forms and `Clone` in `docs/special-forms.md` (the four forms,
  `invoke` lowering), `docs/generics.md` (`Clone`, structural conformance
  derivation), and the escape generalization in the `with`/lifecycle section.
- Append a **"Robot — implementation status"** section to [lambda.md](lambda.md)
  recording what landed and any decision the implementation sharpened.
- Add a Stage 13 entry to [progress.md](../progress.md); create
  `design/stage13/progress.md` for the detailed L0–L9 table. (The overview entry
  already exists.)

---

## Explicitly out of scope (do not build)

- **The compiler `map`/`reduce`/`filter` refactor.** It is the motivating payoff,
  but a separate effort gated on the forms being stable, and it must use the
  zero-cost monomorphized path (L7). Not part of this prompt.
- **Inlinable compile-time-constant locals in `fn`** (the const-ness relaxation) —
  first cut forbids all enclosing-local capture in `fn`.
- **Auto-derived `clone`** for `Drop` structs (`#[derive(Clone)]`-style) — owning
  types hand-write `clone`. May be revisited within the stage if hand-written
  `clone` proves too heavy.
- **Mixed per-variable capture** (a capture list combining clone/move/ref in one
  closure) — keyword-per-mode only.
- **Self-reference / recursion** in an anonymous form.
- **Full nested-region precision**, if the first cut uses the function-frame
  boundary — the per-binding region comparison for closures bound in an outer scope
  capturing an inner local can follow once the coarse check is in place.

## Close-out checklist (required by AGENTS.md)

- After **every** task: `make test` + `make bootstrap` green, compiler compiles
  itself — via **build-test-runner**.
- L2–L9 stayed byte-identical; L1 re-converged the boot fixed point after triaging
  any surfaced sites.
- L9 docs/examples/progress landed; lambda.md has its implementation-status section;
  `design/stage13/progress.md` created.
