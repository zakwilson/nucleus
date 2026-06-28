# Functional refactor — implementation prompt

The build order for refactoring the compiler and libraries to express loops via
**named closures, eager sequence combinators, collections, and iterators**. It
**dogfoods [Stage 13](lambda.md)** end-to-end: the `fn`/`vfn`/`mfn`/`cfn` closure
forms + structural `UnaryFn`/`FoldFn` conformance, the named/mutable/owning
closure enhancements (CE-1…CE-3), **and the type-erasure machine**
([type-erasure.md](type-erasure.md) — `BoxedFn` storable closures + `(dyn P)`
erased values), on top of the earlier collections work (`Vector`/`HashMap`/
`HashSet` + the `Coll`/`Iterator` protocols in `lib/coll.nuc`/`lib/iterator.nuc`).
It is not a new language stage — it is the motivating payoff those features were
built for.

**Prerequisites — all landed.** Every Stage 13 dependency this refactor leans on
is **Done** (see [progress.md](progress.md)): **CE-1 (named closures)** gives the
env-type-inference fallback that lets a closure be bound to a name in `let`/`with`
(so combinators take both inline *and* named operands); **CE-2 (mutable capture)**
makes stateful `vfn`/`mfn` accumulators work; **CE-3 (owning-closure export)** lets
a closure leave its creating scope by value; and **CE-4 storable closures** shipped
as **`BoxedFn`** via the type-erasure machine (TE-0…TE-7), so a combinator can now
**return** or **store** a closure. The original draft of this prompt treated CE-3
and CE-4 as out of scope ("closures used downward only") because they had not yet
landed; that restriction is **lifted** — see decision 3 and the new R1
closure-returning combinators below. The one hard invariant that survives: the
**hot compiler loops stay zero-cost** (inline/named monomorphic closures passed
*downward*); boxing — the allocating, indirect-call path — is reserved for the
library/examples and genuinely heterogeneous storage, never the R3 hot path.

Read [lambda.md](lambda.md) for the closure machinery,
[type-erasure.md](type-erasure.md) for `BoxedFn`/`(dyn P)`, and
[lambda-prompt.md](lambda-prompt.md) for the conformance-derivation design; this
file is *what to build, in what order, and who builds it*.

## How to run this (orchestration)

Multi-phase compiler+library task. **Do not implement it in the orchestrating
thread.** Split into the phases below and dispatch each to the named local agent
(roster: [context/local.md](../../context/local.md)); keep the main thread for
planning and integration.

**Context-budget rule — keep every task well under 100K tokens.** The compiler
core is large; an agent that reads it whole will blow its budget. Every phase
names the *specific functions / subsystems* to read. **There are no line anchors
— grep by NAME; line numbers drift.** Instruct each agent to read only the named
functions plus this file, mirror existing mechanisms rather than invent parallel
ones, and return a concise summary (what changed, which functions, surprises) —
not file dumps.

**Dependency order.** `R1` (combinators — its consuming combinators need CE-1, its
closure-*returning* combinators additionally need TE-5 `BoxedFn`) and `R2`
(registry migration) gate `R3`'s reach; `R1` and `R2` are independent and may
dispatch **in parallel**. `R3` (compiler loop refactor) and `R4` (lib/examples)
follow.
**After every implementation task**, dispatch **build-test-runner** to run
`make test` + `make bootstrap` and confirm the boot re-converges. Do not start
the next task until the tree is green.

## Authoritative decisions (do not re-litigate)

1. **Language-deep, not macro-over-native-shapes.** Build the real eager
   combinator library over `(Coll E It)` / `(Iterator E)` and refactor loops into
   functional pipelines. Do **not** add intermediate macro-style helpers over the
   compiler's raw `ptr+` arrays / `Node` cdr-lists as a substitute — the raw
   arrays migrate to `Vector` (R2) and the cdr-lists get a real `ListIter` (R1).
   Adopting the *already-existing* `dotimes`/`doseq`/`for` macros (`lib/macros.nuc`)
   for plain counted/collection walks is in scope and orthogonal — those are
   iteration forms, not the rejected combinator-substitute.
2. **AST `Node` cdr-lists are reached via a cons-list `ListIter`**, not by
   rewriting the AST representation. The compiler is built around `Node` cdr
   cells; migrating it to `Vector` is out of scope (a rewrite). A `ListIter`
   conforming to `Iterator` lets `find`/`any?`/`reduce`/`doseq` reach AST loops
   without changing the representation.
3. **Hot compiler loops use closures downward only (zero-cost); the library may
   return/store them (boxed).** Every combinator that runs in the compiler's hot
   path (R3) consumes its closure operand within the call (inline or via a CE-1
   named `(ref Env)` passed *down*) and is fully monomorphized — no fat pointer,
   no heap box, no indirect call. That zero-cost discipline is non-negotiable for
   R3. Separately, now that CE-3/CE-4 have landed, the **combinator library** (R1)
   *may* return and store closures via `BoxedFn`/`(dyn P)` — that is the new
   closure-returning-combinator cluster (R1) and the heterogeneous-storage
   examples (R4). The boxed, allocating path is opt-in and stays **out of R3's hot
   loops**; it is exercised only where the value is genuinely
   returned/stored/heterogeneous (library surface + examples), never as a
   substitute for a downward inline closure.
4. **Controlled bootstrap refresh is allowed** where a refactor produces
   structurally cleaner code that drifts IR; a one-time `make update-bootstrap`
   is acceptable *only* with structural justification, and the boot must
   re-converge to a fixed point with tests green throughout. Unjustified drift
   is a regression to debug, not a refresh.
5. **Full scope.** Refactor all viable candidates across every priority cluster
   (R3/R4), including the plain `dotimes`-able counted loops — not just the
   high-value `find`/`any?`/`reduce` clusters.
6. **This is Stage 13 dogfooding, not Stage 14.** It lands in `design/stage13/`
   and updates the existing [progress.md](progress.md). No new stage row in
   `design/overview.md`.

## Non-negotiable invariants

- **Byte-identical bootstrap where the change is inert; controlled refresh only
  where structurally required.** R1 and R4 are expected to keep `make bootstrap`
  a fixed point with **no** `make update-bootstrap` (R1 is library-only, R4 is
  library/examples-only, like `+`/`-`/`*`/`/` today). R2 and R3 touch the
  compiler's own registry shape / codegen and may drift IR — there a one-time
  refresh per batch is allowed, but the boot must re-converge
  (`build/stage2.ll == build/nucleusc.ll`) and tests must stay green.
- **Zero-cost monomorphic hot path strictly preserved (type erasure stays
  opt-in).** The R3 compiler-loop refactor must add **no** fat pointer, heap box,
  or indirect call to the hot path — the inline/named-`let` monomorphic closure
  stays the only shape R3 emits. `BoxedFn`/`(dyn P)` are the deliberately-
  allocating storage path ([type-erasure.md](type-erasure.md)'s "keep out of hot
  loops" rule); they appear only in the R1 closure-returning combinators (library)
  and R4 heterogeneous examples, never in a converted compiler loop. A boxed value
  in an R3 batch is a zero-cost regression to back out, not an idiom to adopt.
- **Closure-returning combinators stay inert under self-compilation.** The R1
  closure-returning combinators (`compose`/`partial`/`constantly`/`complement`/…)
  return `(BoxedFn …)`, but must be **generic over their signature** so they are
  stamped only on use. The compiler imports no combinator lib and boxes nothing,
  so these stay unused in the boot and `make bootstrap` is byte-identical — verify
  the same way TE-1 did (`grep '%__fatptr = type' build/nucleusc.ll` = 0; no
  `@__vt.*`/`@__boxedfn_drop` in the boot IR). A *concrete* (non-generic)
  `BoxedFn`-returning lib defn would force `__fatptr`/box-`Drop` emission into
  every module and drift the boot — keep them parametric.
- **Conformance is type-keyed, not literal-only.** `derive-closure-conformance`
  operates on the bound type's spelling + the struct's recorded `invoke` method —
  it never inspects whether the operand was a literal or a name. Once CE-1 lets a
  binding carry `(ref Env)`, named closures conform to combinators via the same
  `(ref G)`→`G=Env` deref inline literals use today. Do not special-case literals.
- **Narrowing is preserved.** When refactoring near `test-true-nonnull` /
  `test-false-nonnull` (the `and`/`or`/`_and`/`_or` narrowing analyzers), the
  3-arg `and-narrow` proof (`examples/and-narrow.nuc`) must still typecheck.
  Re-run it after touching that neighborhood.
- **Generated names stay IR-legal.** Any synthesized iterator/combinator method
  routed through generics must keep `!`/`?` out of emitted names (LLVM rejects
  them) — route through the existing `sanitize-for-ir` path.
- **Iteration order is observable.** Several registries are read during
  definition prescan and JIT-macro expansion. The `Vector` substrate is
  append-only and order-preserving; a registry migration (R2) must not reorder
  elements. Convert one registry at a time behind a build gate.
- **Leave-alone loops stay imperative.** The leave-alone lists in R3 and R4 (ABI
  codegen, parser/lexer/REPL state machines, convergence fixpoints,
  protocol-method synthesis, `match`-lowering, hash-table probe internals,
  iterator `next` bodies) are excluded — abstracting them hides control flow or
  risks byte-identical codegen. They may adopt order-preserving `dotimes` only.

## Read (scoped — grep by NAME; line numbers drift)

The R1 combinator reads:

- `lib/iterator.nuc` — `reduce` (the verbatim template to mirror, ~133),
  `Iterator E` protocol (~34), `UnaryFn` (~76), `FoldFn` (~82), lazy `MapIter`
  (~89) / `FilterIter` (~109), concrete iters `IntRangeIter`/`I64ArrayIter`/`VecIter`.
- `lib/coll.nuc` — the `Coll E It` / `Seq` / `Assoc` / `Set` / `Drop` protocols
  (~54–130) that combinators are generic over.
- `lib/list.nuc` — the cons-cell `Node*` ops (`cons`/`first`/`rest`/`append`)
  that a `ListIter` will drive.
- `lib/macros.nuc` — the existing `dotimes` (~143) / `doseq` (~178) /
  `doseq-iter` (~205) / `for` (~131) / `into` (~226) forms, currently unused by
  the compiler.
- `lib/string-split.nuc` — `SplitIter`/`LineIter` use a `done` flag and do **not**
  conform to `Iterator`; the file header (~21) documents a planned `doseq-split`.
- `src/generics.nuc` — `derive-closure-conformance` (~2235), recognized-set gate
  to `{UnaryFn, FoldFn}` (~2241), the `invoke`-match + bound-arg derivation
  (~2248–2353), and the two call sites `recover-one-constraint` (~1199) /
  `generic-constraints-ok` (~1334).
- `examples/boxedfn.nuc` / `examples/dyn-protocol.nuc` — the `BoxedFn`/`(dyn P)`
  *spelling* and the box-`Drop` discipline (`(drop (addr-of e))` per stored box,
  exactly once) that the closure-returning combinators and the heterogeneous
  examples follow. The boxing-coercion machinery itself (`maybe-box-into-slot` /
  `emit-box-closure` in `nucleusc.nuc`, `boxedfn-type`/`boxedfn-canonical` in
  `union-registry.nuc`) is **already built** — the combinators only *use* the
  `(BoxedFn …)` surface as a return/element type; they do not touch the emitter.

The R2/R3 registry reads:

- `src/nucleusc.nuc` — the established `(defvar (g-X (ref (Vector ptr))))`
  pattern + `make-vec` arena constructor (~425–497); the existing Vector globals
  `g-pending-unions` (~120), `g-lbl-tbl` (~172), `g-nundo` (~189),
  `g-mono-worklist` (~227), `g-macro-decls` (~306), `g-program-defns` (~314).
- The ~17 raw-array registries (each `g-X:ptr` + `g-X-len`/`g-num-X` + often a
  `g-cap-X`): hand-rolled growables `g-generics` (`generics.nuc` ~27),
  `g-protocols` (~2037), `g-conformances` (~2220), `g-proto-supers` (~2441),
  `g-tmpl-conformances` (~2734), `g-strs` (`nucleusc.nuc` ~148), the parallel
  arrays `g-fnty-names`/`g-fnty-types` (`type-mangle.nuc` ~63) and
  `g-deferror-*-sids` (`nucleusc.nuc` ~126); and the fixed arena pre-allocs
  `g-structs` (~102), `g-uniondefs` (~110), `g-union-templates` (~112),
  `g-struct-templates` (~116), `g-enumdefs` (~118), `g-binops` (~214),
  `g-macros` (~288), `g-rmacros` (~293), `g-blanket` (~284), `g-cast-rules` (~165).
  The iteration idiom to replace is `while (< i g-num-X) … (ptr+ (cast ptr:TX g-X) i) …`.

## Build

### R1 — Eager combinator library

**Agent: systems-impl-engineer.** Depends on CE-1. Adds the combinators the
refactor is built on.

**Read (scoped):** `reduce` (`lib/iterator.nuc`) as the verbatim template; the
`Coll E It` / `Iterator E` protocols; `derive-closure-conformance` and the
`{UnaryFn, FoldFn}` recognized set; `lib/list.nuc` cons ops; `lib/string.nuc`
/`lib/strview.nuc` byte/char access; the `SplitIter`/`LineIter` `done`-flag loops
in `lib/string-split.nuc`.

**Build:**
1. Eager combinators over `(Coll E It)` **and** `(Iterator E)`, each mirroring
   `reduce`'s `&where` signature (operand typed `(name (ref Tyvar))`):
   - Transformations: `map` (→new `Vector`), `filter` (→new `Vector`),
     `remove-if`, `for-each`, `flat-map`.
   - Search: `find` (→`Maybe E`, early stop), `find-index` (→`i32`, early stop).
   - Quantifiers: `any?`/`exists?`, `every?`/`all?`, `count` (by predicate) —
     all early-stop.
   - Folds: `foldr` (right fold; `reduce` is the left fold), plus thin wrappers
     `sum`/`product`/`min`/`max`.
   - Ordering: `sort`/`sort-by` (in-place on `Vector`). A comparator closure is a
     binary predicate — if `{UnaryFn, FoldFn}` does not cover it, either extend
     the recognized set minimally or take an `fn` pointer (decide and document).
   - Joinery: `join`/`emit-joined` — drive a closure that emits one element,
     separated; this covers the "emit each with a separator" cluster (~28 sites).
   - `do-last` / `keep-last` for the implicit-progn-last-value cluster.
2. **New iterators** so the combinators reach more shapes:
   - `ListIter` — conform the cons-cell `Node*` to `Iterator` (drive `rest`→`null`).
   - Char/byte iterators for `String`/`CStr` at the coll layer (the FNV-hash and
     UTF-8 loops fold bytes).
   - Conform `SplitIter`/`LineIter` to `Iterator` (replace the `done`-flag shape
     the header documents as deferred), enabling `doseq-split`.
3. **Closure-returning combinators** (the storable-closure payoff — *new with
   `BoxedFn`*). Higher-order combinators that **produce** a closure and return it
   by value as a `(BoxedFn (params…) ret)` — impossible before TE-5 (a `defn`
   could not spell a closure return type; the anonymous `__vfn_env_N` was
   unnameable). Each is **generic over its signature** so it stamps on use only
   (keeping the boot byte-identical — see the invariant above):
   - `compose`/`comp` — `(compose g f)` → a box `x → (g (f x))`.
   - `partial` — `(partial f a)` → a box `x → (f a x)` (partial application).
   - `constantly` — `(constantly v)` → a box `_ → v`.
   - `complement` — `(complement pred)` → the negated-predicate box.
   - `conjoin`/`disjoin` — combine predicate boxes under `and`/`or` → a box.

   The returned box owns its heap env and conforms to `Drop`; tests drop each
   returned box exactly once (no leak/double-free), following the
   `(drop (addr-of …))` discipline in `examples/boxedfn.nuc`. **Operand choice
   (decide per combinator and document, mirroring the `sort`-comparator
   decision):** an operand that is itself a `(BoxedFn …)` lets composition *nest*,
   but then the returned env owns it by move (`mfn`-style) and must drop it
   transitively — verify no leak/double-free on nested boxes; if nesting is not
   yet solid, restrict v1 operands to bare `fn` pointers (non-capturing), which the
   returned box captures by value with a null env-drop slot.

**Done when:** every *consuming* combinator has an `examples/` test exercising it
with **both an inline closure operand and a named one** (proving CE-1);
`map`/`filter`/`find`/`any?`/`every?` work over a `Vector`, a cons-list (via
`ListIter`), and `String` chars; the FNV hash expressed as `reduce` over the byte
iterator matches the hand-written hash; **and** each closure-returning combinator
(`compose`/`partial`/`constantly`/`complement`/`conjoin`) has an example that
builds, calls, and drops the returned `BoxedFn` exactly once (proving the
storable-closure payoff). **`make bootstrap` byte-identical, no refresh**
(library-only, like `+`/`-`/`*`/`/`) — verify no `%__fatptr`/`@__vt.*`/
`@__boxedfn_drop` reached the boot IR (the combinators are generic/unused there).
→ build-test-runner.

---

### R2 — Raw-array registry → `Vector` migration

**Status: Done (2026-06-27).** All 18 listed registries migrated; 136 tests pass;
`make bootstrap` byte-identical fixed point (no drift — better than the predicted
controlled refresh); boot artifacts refreshed. Details + the three out-of-spec
type-erasure registries left for a follow-up are in
[progress.md](progress.md#stage-13--functional-refactor-r2-raw-array-registry--vector-2026-06-27).

**Agent: focused-task-implementer** (per-registry batches), **build-test-runner**
gates between batches. Independent of R1; may run in parallel.

**Read (scoped):** the established `(defvar (g-X (ref (Vector ptr))))` pattern and
`make-vec` (`src/nucleusc.nuc` ~425–497); each registry's declaration, its growth
thunk (for the hand-rolled growables), and every `ptr+`/`g-num-X` read site.

**Build:**
1. Convert the **hand-rolled growables first** (`g-generics`, `g-protocols`,
   `g-conformances`, `g-proto-supers`, `g-tmpl-conformances`, `g-strs`, the
   parallel arrays, `g-deferror-*-sids`) — each conversion *deletes* its
   `g-num-*`/`g-cap-*`/`memcpy` growth thunk and swaps the `ptr+` loop for
   `count`/`invoke`.
2. Then the **fixed arena pre-allocs** (`g-structs`, `g-uniondefs`, …, `g-cast-rules`).
3. **One registry at a time**, `make` + `make test` after each. Preserve
   iteration order (Vector is append-only/order-preserving). Mind the registries
   read during prescan + JIT-macro expansion.

**Substrate-only — element type stays concrete.** This migration swaps the array
*substrate* (raw `ptr+`/`g-num-X` growable → `(Vector ptr)`); it does **not**
change what the slots hold. The handler tables (`g-macros`/`g-rmacros`/`g-binops`/
`g-cast-rules`/`g-blanket`) keep their concrete struct-pointer entries — do **not**
re-represent them as `(Vector (dyn P))` or `(Vector (BoxedFn …))`. Those tables are
read on the hot prescan / JIT-macro-expansion path, where the erased indirect-call
+ heap-box path would be a zero-cost regression (see the zero-cost invariant).
Erased-handler registries are a possible future direction, explicitly **not** this
refactor.

**Done when:** all ~17 registries are `(Vector ptr)`, no `ptr+`/`g-num-X` read
sites remain for them, and the compiler compiles itself. **Controlled refresh
allowed** (pointer origins change); `make bootstrap` must re-converge to a fixed
point. → build-test-runner.

---

### R3 — Compiler loop refactor (full scope)

**Status: Partial done (2026-06-28).** Batch 1 complete: `src/scope.nuc`,
`src/type-mangle.nuc`, `src/nuch.nuc`, `src/union-registry.nuc` (first batch
of sites only). 136 tests pass; byte-identical bootstrap. Remaining R3 work
(lookup clusters in `src/generics.nuc`, `src/nucleusc.nuc`, etc.) continues.

Key gotcha discovered: `dotimes` takes exactly **one** body form (`(defmacro
dotimes (spec body))`). Multi-statement bodies must be wrapped in `(do ...)`.
See `context/conventions.md`.

**Agent: focused-task-implementer** / **systems-impl-engineer**, dispatched by
file cluster; **build-test-runner** gates between batches. Depends on R1 + R2.

**Read (scoped):** per cluster — the lookup/quantifier/reduce/map/join/for-each
loops inventoried below; the `emit-short-circuit` neighborhood for the narrowing
invariant.

**Build:** apply combinators + `dotimes`/`doseq` across the ~280 viable loops in
`src/`, in this priority order (each cluster is its own dispatch chunk):
1. **find / lookup (~38)** → `find`/`find-index`. Cluster: the 4 near-identical
   `union-registry.nuc` lookups; the 7 generic/protocol/conformance lookups in
   `generics.nuc`; `find-macro` (`nucleusc.nuc` — two copies of the same loop);
   the 5 `guard-name-kind` lookups in a row; `type-mangle`/`scope` lookups.
2. **any? / every? (~39)** → `any?`/`every?`. Member/ancestor scans over a `Node`
   cdr-list or scope parent-chain (`scope-is-ancestor`, name-in-list);
   `params-type-eq`, string-arrays-eq, all-bounds-non-null, all-deps-emitted.
3. **reduce / sum / string-build (~33)** → `reduce`/`sum`/`join`. Field
   size/align max folds (`abi.nuc`); slot-bound sum tallies; the 3 FNV hash folds;
   string-concat builders; the 8 "implicit-do, keep-last" bodies → `do-last`.
4. **map-into array (~20)** → `map`/`map-into!`. The parallel `aset!` field/param
   parses across `union-registry.nuc`/`nucleusc.nuc`/`generics.nuc`.
5. **join-print (~28)** → `emit-joined`. IR param lists, struct/field type lists,
   phi/label/value lists, space-separated node print — the single most repetitive
   shape in the codebase.
6. **for-each side-effect (~140)** → `doseq`/`for-each`. Scope-define, prescan,
   validate, scope-cleanups, IR-emit-per-element.
7. **counted loops (the `let i=0; while; inc!` idiom, ~280 instances)** →
   `dotimes`. The `dotimes` macro already exists and is unused.
8. **count / list-length (~6)** → `list-length` (or `count` over `ListIter`).

**Leave-alone (do not refactor — `dotimes` only where order-safe):** SysV ABI
codegen (`abi.nuc` `abi-class-eightbyte` and the class/offset loops); C-header
buffer cursor scans and parser state machines (`cheader.nuc`, `repl.nuc` input
state machine, lexer digit consumption); convergence fixpoints (`macroexpand-form`,
generic determination / constraint-recovery); protocol-method synthesis
(`generics.nuc`); `match`-lowering switch/case + exhaustiveness (`union-emit.nuc`);
array/struct-literal lowering and `defn`/`defmacro`/`cond` body emitters with
tail-return/branch-label logic; the `argv` driver; any IR-emit loop on the ABI
path where the body must not be reordered.

**Done when:** every viable cluster is converted; the leave-alone list is
untouched (or `dotimes`-only); `examples/and-narrow.nuc` still typechecks
(narrowing preserved). **Controlled refresh per batch; `make bootstrap`
re-converges to a fixed point, tests green throughout.** → build-test-runner.

---

### R4 — Library & examples refactor

**Agent: focused-task-implementer.** Depends on R1 (and benefits from R2).
Lower-risk dogfooding; examples do not affect the bootstrap.

**Read (scoped):** the `lib/` and `examples/` loop inventory; the new
combinators/iterators from R1.

**Build:**
- **`lib/` (~73 loops):** FNV hash folds (`strview.nuc`, `hash.nuc`, `node.nuc`)
  → `reduce` over the new byte iterator; `strview-byte-find`, `keyword-intern`,
  `err-find-handler` → `find`; UTF-8 validators (`string.nuc`) → `every?` (note
  each threads decode state — keep as a stateful fold if a pure predicate obscures
  it); the hashmap state-zeroing loops → `memset` (match the existing
  `hashset.nuc` pattern); `reader.nuc:420` → `dotimes`; the 6 hand-rolled
  split-iteration sites → `doseq-split` (once `SplitIter` conforms to `Iterator`).
- **`examples/` (~32 loops):** counted loops (`mutual.nuc`, `hello.nuc`,
  `ifwhile.nuc`) → `dotimes`; the hand-rolled `collect-all` → combinator/`into`;
  `&rest` sum loops → `reduce`; existing `doseq`/`into` sites may move to the new
  combinators where clearer.
- **Storable-closure & `dyn` dogfood (new):** alongside the TE-5/TE-6 baseline
  (`examples/boxedfn.nuc`, `examples/dyn-protocol.nuc`), add an example that wires
  the R1 closure-returning combinators to storage end-to-end — e.g. a `(Vector
  (BoxedFn (i32) i32))` built from `partial`/`compose` results, walked with
  `for-each`/`map`, each box dropped once — and one that holds heterogeneous values
  behind `(dyn P)` and dispatches over them with a combinator. These prove the
  combinators compose with the type-erased storage path; examples don't affect the
  boot.

**Leave-alone:** hash-table probe internals (`hashset`/`hashmap`/`node` intern
probes — the `done` flag *is* the probe control flow); iterator `next` bodies that
skip tombstones (they *are* the filter primitive); parser/lexer state machines in
`reader.nuc` (each threads reader globals and tail-splices AST cells);
`memmove`/capacity-doubling in `vector.nuc`.

**Done when:** the high-value `lib/` sites are converted and `examples/` uses the
new combinators as the idiom. `make test` green; `make bootstrap` mostly inert (a
refresh is allowed only if a `lib/` prelude change on the bootstrap path drifts,
and must re-converge). → build-test-runner.

## Sequencing & dependencies

```
CE-1 (named closures) ──► R1 (combinators) ──┬──► R3 (compiler refactor, full)
                                             │
                         R2 (registry migration) ──┘
                                             │
                                             └──► R4 (lib/examples)
```
CE-1 (in closure-enhancements.md) gates R1's named-operand story; **TE-5
(`BoxedFn`, in type-erasure.md) gates R1's closure-returning cluster** — both are
Done. R1 + R2 gate R3's reach. R2 is independent of R1 (parallelizable). R4
follows R1 and adds the storable-closure / `dyn` examples.

## Bootstrap policy (summary)

| Phase | Expected bootstrap | Refresh |
|---|---|---|
| R1 — combinators | byte-identical (library-only) | no |
| R2 — registry migration | drifts (pointer origins) | controlled, reconverge |
| R3 — compiler refactor | drifts (codegen/registry shape) | controlled per batch, reconverge |
| R4 — lib/examples | mostly inert; examples don't affect boot | only if a `lib/` prelude change drifts |

Unjustified drift at any phase is a regression to debug, not a refresh.

## Risk register

| Risk | Mitigation |
|---|---|
| `{UnaryFn, FoldFn}` set too narrow for `sort`/combinators (R1) | Decide minimally (extend set or take `fn` pointer); document |
| Registry migration (R2) changes order/timing | One registry at a time behind gates; Vector is order-preserving |
| Codegen refactor (R3) drifts IR unpredictably | Batch by file/cluster; fixed-point check each batch; leave-alone list protects hot paths |
| Narrowing analyzer regression near `test-*-nonnull` | Re-run `examples/and-narrow.nuc` after touching that neighborhood |
| Multi-session scope (R3 is ~280 sites) | Cluster priority order; each cluster its own dispatch chunk; build-test gates between |
| Boxing creeps into an R3 hot loop (zero-cost regression) | Decision 3 + zero-cost invariant; R3 combinators are downward inline/named only; reject any `BoxedFn`/`(dyn P)` in a converted compiler loop at review |
| A concrete `BoxedFn`-returning combinator drifts the boot (R1) | Keep closure-returning combinators generic (stamped on use); verify no `%__fatptr`/`@__vt.*`/`@__boxedfn_drop` in `build/nucleusc.ll` |
| Nested boxes (a `BoxedFn` captured by a returned `BoxedFn`) leak / double-free | Verify each returned box drops exactly once with a captured-box operand; if shaky, restrict v1 operands to bare `fn` pointers and document |

## Explicitly out of scope (do not build)

- **Rewriting the AST representation.** `Node` cdr-lists stay; reached via
  `ListIter`, not converted to `Vector`.
- **Lazy-iterator pipelines as the refactor target.** The lazy `MapIter`/
  `FilterIter` exist but their `alloca`+struct setup is *not* more succinct. The
  refactor targets eager combinators. (The lazy combinators remain available.)
- **Boxing in the hot compiler loops (R3).** CE-3/CE-4 have landed, so
  owning-closure export and storable closures (`BoxedFn`/`(dyn P)`) are now
  *available* — the R1 library and the R4 examples *use* them. What stays out of
  scope is putting the boxed, allocating, indirect-call path into a **converted
  compiler loop**: R3 stays zero-cost monomorphic (decision 3 + the zero-cost
  invariant), consuming only downward inline/named closures.
- **Re-representing handler registries as `(dyn P)`/`BoxedFn`.** The `g-macros`/
  `g-binops`/`g-cast-rules`/`g-blanket` tables *could* hold `(dyn P)` values, but
  they sit on the hot prescan / JIT-macro-expansion path; R2 keeps their concrete
  struct-pointer element type and migrates only the array substrate to `Vector`.
  Erased-handler registries are a possible future direction, not this refactor.
- **A new design stage.** This is Stage 13 dogfooding; no `stage14/`, no
  `design/overview.md` stage row.
- **Generator/`yield` iteration, destructuring `doseq`, infinite `(loop)` with
  `break`/`continue`.** None exist and none are added here.

## Close-out checklist (required by AGENTS.md)

- After **every** phase: `make test` + `make bootstrap` green, compiler compiles
  itself — via **build-test-runner**.
- R1 and R4 stayed byte-identical (no refresh); R2 and R3 re-converged the boot
  fixed point after a justified controlled refresh.
- The 3-arg `and-narrow` narrowing proof still typechecks after R3.
- Update [progress.md](progress.md) with a per-phase row table (R1 … R4)
  mirroring the L0–L9 table; note the combinator set landed, the registry count
  migrated, and any surprise (especially any bootstrap drift and its root cause).
- Update language docs (`docs/iterators.md`, `docs/macros.md`) for the new eager
  combinators and `ListIter`, and `docs/generics.md` (Type erasure §) for the
  closure-returning combinators that return `BoxedFn`, consistent with how
  `_+`/`+`, `reduce`, and `BoxedFn`/`(dyn P)` are already documented.

## Report back concisely (per phase)

1. Every file/function changed (one line each), incl. any extra site a sweep
   turned up beyond the named clusters.
2. Confirmation that `make` + `make test` (N pass) + `make bootstrap` (fixed
   point; note whether a controlled refresh was needed and why) all pass.
3. Anything that behaved differently from this prompt's predictions — especially
   any boot drift and its root cause, or any conformance/narrowing surprise.
