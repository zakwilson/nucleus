# Type erasure — the shared fat-pointer machine (`BoxedFn` + `(dyn Protocol)`)

The design for Nucleus's **one** type-erasure mechanism — a two-word fat
pointer with a static per-concrete-type vtable — and its two instantiations:
**`BoxedFn`** (storable, owning, heap-boxed closures) and **`(dyn Protocol)`**
(type-erased values of any user protocol, enabling unbound-abstract returns and
heterogeneous collections).

This is filed as a Stage 13 doc because its live, scheduled client is the
closure feature ([closure-enhancements.md](closure-enhancements.md) **CE-4**,
storable closures, gated behind **CE-3**). But it deliberately **generalizes**
the Stage 9 *rung-5 `(dyn Protocol)`* deferral
([polymorphism.md](../stage9/polymorphism.md) §8.10 rung 4, §8.5/B2, and the
"Still deferred" summary): the realization recorded here is that CE-4's
recommended `BoxedFn` and Stage 9's deferred `(dyn Protocol)` are **the same
mechanism at two scopes**, and so they must be built as one machine. This doc
**supersedes** both the CE-4 Option 3 sketch and the Stage 9 rung-5 deferral
with a single committed plan.

Read [closure-enhancements.md](closure-enhancements.md) (the **CE-4** section in
full) and [polymorphism.md](../stage9/polymorphism.md) (the dynamic-escape-hatch
passage, the rung ladder, §8.5/B2) for the two sides this converges; read
[lambda.md](lambda.md) for the closure machinery whose synthesized `invoke`/`drop`
methods *are* the vtable slots. This file is *what to build, in what order, and
who builds it*.

## How to run this (orchestration)

Multi-phase compiler task touching the ABI, the type registry, the conformance
registry, and codegen. **Do not implement it in the orchestrating thread.**
Split into the phases below and dispatch each to the named local agent (roster:
[context/local.md](../../context/local.md)); keep the main thread for planning
and integration.

**Context-budget rule — keep every task well under 100K tokens.** The compiler
core is large; an agent that reads it whole will blow its budget. Every phase
names the *specific functions / subsystems* to read. **There are no line anchors
— grep by NAME; line numbers drift.** Instruct each agent to read only the named
functions plus this file, mirror the existing parametric-struct / conformance /
ABI mechanisms rather than invent parallel ones, and return a concise summary
(what changed, which functions, surprises). After every implementation phase,
dispatch **build-test-runner** for `make test` + `make bootstrap` and confirm the
boot re-converges before the next phase starts.

## Summary

| # | Phase | Kind | Agent | Gates |
|---|---|---|---|---|
| TE-0 | Ground-verify (read-only map) | survey | systems-impl-engineer | confirms CE-3, the vtable-slot thunks, the registries |
| TE-1 | Fat-pointer value kind + ABI lowering | core | systems-impl-engineer | every later phase |
| TE-2 | Static per-type vtable synthesis / dedup / addressing | core | systems-impl-engineer | boxing coercion |
| TE-3 | Boxing coercion at assignment into an erased slot | core (hardest) | systems-impl-engineer | box `Drop` + forwarding |
| TE-4 | Box `Drop` + forwarding-through-vtable conformance | core | systems-impl-engineer | both instantiations |
| TE-5 | **Instantiation A — `BoxedFn`** (surface + structural admission + live use cases) | feature | systems-impl-engineer | the closure-storage payoff |
| TE-6 | **Instantiation B — general `(dyn Protocol)`** (nominal conformance, B2, heterogeneous) | feature | systems-impl-engineer | supersedes the rung-5 deferral |
| TE-7 | Docs / examples / progress | docs | api-docs-writer | close-out |

TE-1 … TE-4 are the **shared machine** and are strictly ordered. TE-5
(`BoxedFn`) lands **before** TE-6 (`(dyn P)`): it has the live, scheduled use
case *and* its vtable thunks already exist (the per-env synthesized
`invoke`/`drop` — "the box just takes their addresses"), so it validates the
machine against its hardest client first (see motivation §"`BoxedFn` is the
harder client").

## Non-negotiable invariants

- **Zero-cost static/monomorphized path strictly preserved.** Type erasure adds
  **nothing** to the inline `fn` / POD-`vfn` / `let`-bound monomorphic closure
  path (CE-1) or to inline-monomorphized generics. The fat pointer, the vtable,
  the heap box, and the indirect call exist **only** when a value is explicitly
  boxed into an erased slot. The hot path stays inline and direct-call. This is
  the whole reason the feature is opt-in.
- **Generated names stay IR-legal.** Every synthesized name — the per-type
  vtable global, the box's `Drop`/forwarding methods, any thunk — must route
  through the existing `sanitize-for-ir` path so `!`/`?`/`/` never reach an
  emitted symbol (mirror the closure forms' use of it and `type-mangle`).
- **C-ABI story is explicit.** The fat pointer is a two-word by-value aggregate;
  decide and document whether a public `defn` mentioning a `BoxedFn`/`(dyn P)`
  type crosses `--emit-cheader`. v1 follows **L8's precedent**: such a defn is
  *excluded* from the header with an explanatory comment + a definition-site
  warning (the fat pointer carries Nucleus-side `Drop`/vtable semantics with no
  faithful C spelling). `fn`-pointer signatures continue to emit normally.
- **Bootstrap re-convergence.** The shared machine touches the ABI (TE-1) and
  the type/conformance registries, so a controlled `make update-bootstrap`
  refresh is permitted where a phase genuinely drifts the boot, but each phase
  must end with `build/stage2.ll == build/nucleusc.ll` and tests green. Phases
  that are inert under self-compilation (the compiler never boxes a value)
  should stay byte-identical with **no** refresh — verify, do not assume.

---

## Motivation — why one machine, not two

Two deferred features were specified independently, and on inspection they are
the same construct:

- **Stage 9's `(dyn Protocol)`** (polymorphism.md): a fat pointer
  `{ptr vtable, ptr data}` with a *static per-impl vtable global*; static calls
  never touch the vtable (zero overhead on the monomorphic path); it is the
  **only runtime-cost rung** (rung 5), opt-in, and it is what unlocks **B2**
  (returning an unbound-abstract protocol value, §8.5) and **heterogeneous
  collections**.
- **CE-4's `BoxedFn`** (closure-enhancements.md Option 3): a two-word fat pointer
  `{ data, vtable }` with a *static per-env-type vtable* `{ invoke, drop,
  clone? }`. Assigning any closure into a `BoxedFn` slot heap-allocates the env,
  points at its vtable, and yields a uniform owning value.

`(BoxedFn (i32) i32)` is essentially `(dyn (UnaryFn i32 i32))`. They share the
representation, the per-concrete-type static vtable, the boxing coercion at
assignment into an erased slot, the box's `Drop`, and the
forwarding-through-vtable conformance. **The outcome to avoid:** shipping
`BoxedFn` as a standalone one-off and then re-implementing ~90% of it again for
`dyn`. This doc therefore designs **one shared type-erasure machine** and
instantiates `BoxedFn` and `(dyn P)` on top of it.

### `BoxedFn` is *not required by* but *strongly benefits from* the shared machine

`BoxedFn` can technically be built without general `dyn`, and it is the
*narrower* construct — its protocol target is fixed (the `Fn` family), and its
vtable thunks **already exist** as the per-env synthesized `invoke`/`drop`
methods from L4/L6, so "the box just takes their addresses." But it needs the
**exact same new infrastructure** as `dyn` (fat-pointer value kind + ABI,
per-type static vtable synthesis/dedup, boxing coercion, box `Drop` +
forwarding conformance). Building it bespoke buys nothing and costs the
duplication. Hence: one machine.

### `BoxedFn` is the *harder* client, not a toy — so design against it

`BoxedFn` is the **owning, droppable, allocator-carrying** box: a boxed closure
env must carry `drop` *and* the allocator and conform to `Drop`. A POD `(dyn
Show)` need not own or free its data. Therefore:

- Design the machine against `BoxedFn`'s requirements (owning + `Drop` +
  allocator-threaded) and the **POD-`dyn` case falls out** (it simply has a
  null/no-op `drop` slot and no allocator to thread).
- Design it for POD-`Show` first and you would have to **extend** it later to
  carry ownership and an allocator.

This is also why `BoxedFn` is **gated behind CE-3**: the concrete env must
travel *by value* into the heap box, which needs CE-3's by-value-struct ABI
(`emit-struct-ret` typed copy + `emit-call-with-args` first-class load) and
CE-3's `with`-drop `TY-STRUCT` arming — both of which **just landed** (see
[progress.md](progress.md) CE-3). `(dyn P)` over a POD type does not need CE-3,
but building the owning client first makes the POD client free.

---

## Representation

A type-erased value is a **two-word fat pointer**, a by-value aggregate:

```
{ data: ptr,        ; heap-allocated payload (the boxed env / the boxed value)
  vtable: ptr }     ; address of the static per-concrete-type vtable global
```

The **vtable** is a static, immutable global synthesized **once per concrete
type**, a record of function pointers:

```
{ invoke,           ; the type's call/dispatch thunk (BoxedFn: the env's `invoke`)
  drop,             ; the type's `drop` thunk (null / no-op for POD types)
  clone? }          ; optional; v1 may omit (see open questions)
```

**Field order is `{ data, vtable }`** (CE-4's order). Stage 9 sketched
`{ vtable, data }`; that was never built, and this doc commits to `{ data,
vtable }` uniformly — it is a free choice and unifying it removes a latent
inconsistency.

**Rationale vs. the rejected three-word inline `{ env, invoke, drop }`** (CE-4's
representation sub-choice, restated as the committed decision): the
fat-pointer-plus-static-vtable form

- **amortizes the vtable** across every instance of a concrete type (the thunks
  are stored once in a global, not re-copied into every value);
- keeps the value **pointer-pair-sized** (two words), so it is cache-friendly
  packed into a `Vector` slot or a struct field;

whereas the three-word inline form is simpler but fatter and re-stores the
thunks per value. **Committed: fat pointer + static vtable.** This matches
both CE-4's recommendation and the Stage 9 `(dyn)` sketch.

---

## The shared machine

Five concerns, each a build-phase boundary (TE-1 … TE-4; the box-side surface is
TE-5).

### (a) The fat-pointer value kind + ABI lowering — TE-1

A first-class two-word aggregate value kind that lowers correctly across **pass
/ return / store**. This *sits on CE-3*: the fat pointer is exactly a small
by-value struct, so its passing/return follows the same `abi-classify`
MEMORY/COERCE1/COERCE2 path that CE-3 just fixed in `emit-struct-ret` /
`emit-call-with-args` / `abi-arg-frag`. The new work is registering the fat
pointer as a recognized aggregate type (a fixed two-`ptr` layout, interned once)
and ensuring `store`/`load`/bind/return treat it as a value, not a pointer.

### (b) Per-type static vtable synthesis, dedup, and addressing — TE-2

For each concrete type that is ever boxed, synthesize **one** static global
vtable holding the addresses of that type's thunks:

- **`BoxedFn`:** the thunks are the **already-synthesized** per-env `invoke`
  (`fn-make-invoke-method`) and `drop` (`fn-make-drop-method`) methods — the box
  takes their addresses. No new thunks to write; just locate the emitted method
  symbols and store their addresses in the vtable.
- **`(dyn P)`:** the thunks are the methods of the type's declared `extend P`
  conformance (the box takes the addresses of the registered conformance
  methods).

**Dedup:** memoize the vtable global per `(concrete-type, protocol/signature)`
exactly as the parametric-struct machinery memoizes a stamped mangled name —
reserve-name-first, intern, reuse. Two boxes of the same env type **share one
vtable global**. **Addressing:** the vtable name routes through
`sanitize-for-ir` / `type-mangle`; the box's `vtable` field is set to its
address at box-construction time.

### (c) The boxing coercion at assignment into an erased slot — TE-3 (hardest)

When a concrete closure/value flows into an **erased slot** (a `BoxedFn`- or
`(dyn P)`-typed `let`/`with` binding, parameter, struct field, `Vector` element,
or `return`), emit a **boxing coercion**:

1. **Conformance admission first.** Confirm the source type conforms to the
   slot's protocol/signature. The lookup must admit **both** structural
   conformance (L7 `derive-closure-conformance`, for closures → the `Fn` family)
   **and** nominal `extend` conformance (for `(dyn P)`). See §"Conformance:
   structural vs nominal must unify" below.
2. **Move the payload to the heap.** Heap-allocate (or move) the concrete
   payload through an allocator — for `BoxedFn` this is the env struct travelling
   *by value* into the box (the CE-3 by-value-struct ABI), threaded through an
   allocator like `cfn` threads its stored `AllocHandle`.
3. **Point at the vtable.** Set `data = heap ptr`, `vtable = &<the TE-2 vtable
   for this concrete type>`.
4. **Yield a uniform owning value** of the fat-pointer kind.

This is the moment that turns *many concrete types* into *one slot* — the core
of type erasure.

### (d) Box `Drop` — TE-4

The fat pointer conforms to `Drop`: at scope exit it calls `vtable.drop(data)`
(running the boxed payload's own `drop`, e.g. the env's synthesized field-drops)
and then **frees `data` via the stored allocator**. A POD box has a null/no-op
`drop` slot and only frees (or, if the allocator is a no-op arena, nothing). This
reuses the existing `with-drop-method` / `emit-drop-cleanup` / `type-conforms-drop`
cleanup machinery — the box is just another `Drop`-conforming type, registered
once.

### (e) Forwarding-through-vtable protocol conformance — TE-4

The box conforms to its parameter's protocol by **forwarding through the
vtable**: `(invoke box args…)` lowers to an indirect call
`vtable.invoke(data, args…)`; a `(dyn P)` method call lowers to
`vtable.<slot>(data, args…)`. The conformance is **type-checked by the box's
signature/protocol parameter** — `(BoxedFn (i32) i32)` conforms to
`(UnaryFn i32 i32)`; `(dyn Show)` conforms to `Show`.

### Conformance: structural vs nominal must unify

The two instantiations key conformance differently and the boxing-coercion
lookup (step 1 above) **must admit both**:

- **`BoxedFn`** derives closure → `UnaryFn`/`FoldFn` *structurally* (L7
  `derive-closure-conformance`, by matching the synthesized `invoke` against the
  protocol's single required method).
- **`(dyn P)`** keys off a *declared* `extend` (nominal) conformance.

So the lookup in the boxing coercion tries structural derivation (closures into
the `Fn` family) and falls back to nominal `conformance-lookup` (arbitrary
protocols) — one unified entry point, obeying the existing
one-conformance-per-`(type, protocol)` coherence.

### Surface: signature- vs protocol-parameterized

`BoxedFn` is parameterized by a **signature** `(params…) ret`; `(dyn P)` by a
**protocol name**. For the `Fn` family these *coincide*: the protocol's single
method's signature *is* the parameter, so `(BoxedFn (i32) i32)` and
`(dyn (UnaryFn i32 i32))` denote the same box.

---

## Instantiation A — `BoxedFn` (TE-5)

`(BoxedFn (params…) ret)` — a nameable, fixed-size, signature-parameterized
handle that erases the concrete env. It is the **owning, droppable,
allocator-carrying** box:

- **vtable thunks = the already-synthesized per-env `invoke`/`drop`** (L4/L6).
  The box's vtable `invoke` slot is the env's `invoke`; the `drop` slot is the
  env's synthesized `drop` (or null for a POD env).
- **Conformance admission = structural (L7).** A closure literal flowing into a
  `BoxedFn` slot conforms via `derive-closure-conformance`.
- **Allocator-threaded** like `cfn`: the box stores the `AllocHandle` it boxed
  through, and its `Drop` frees `data` via that handle.

Enables the three live use cases CE-4 calls out:

1. `(Vector (BoxedFn (i32) i32))` — a homogeneous-slot collection of
   heterogeneously-captured closures;
2. a **struct field** of `BoxedFn` type;
3. a `(BoxedFn …)` **return** — closing the CE-4 env-naming gap noted in
   [progress.md](progress.md) (a `defn` returning a closure *object* currently
   errors "unknown type" because the anonymous `__vfn_env_N` can't be spelled as
   a return type; `BoxedFn` is the spellable, fixed-layout return type).

---

## Instantiation B — general `(dyn Protocol)` (TE-6)

`(dyn P)` for an arbitrary user protocol `P` via **nominal `extend`
conformance**; the vtable is built from the type's declared `extend P` impls
(TE-2). This realizes the Stage 9 rung-5 deferral:

- enables **B2** — returning an unbound-abstract protocol value
  (polymorphism.md §8.5; e.g. `(defn parse:(dyn Show) (s:ptr) …)`), which §8.5
  rejected "until `dyn` lands";
- enables **heterogeneous collections** (`(Vector (dyn Show))`);
- uses the same structural-vs-nominal unification in the conformance lookup (the
  POD-`dyn` case is the no-`Drop`, no-allocator specialization of the machine);
- **downstream beneficiary:** the *computed/reflective field access* deferred in
  [callable-values.md](../stage9/callable-values.md) (heterogeneous computed
  `get`) — another future `dyn` client, mentioned here so the connection is on
  record; not built in v1.

---

## Prerequisites & relationships

- **CE-3 (by-value struct ABI) — hard prerequisite.** The concrete env must
  travel by value into the heap box; this needs CE-3's `emit-struct-ret` typed
  copy, `emit-call-with-args` first-class load, and `with-drop-method`
  `TY-STRUCT` arming. CE-3 has landed (progress.md). The general POD-`(dyn P)`
  case does not strictly need CE-3, but the machine is designed against the
  owning client, which does.
- **L7 (structural conformance derivation).** `derive-closure-conformance` is
  the `BoxedFn` conformance-admission path; the boxing coercion's lookup must
  call into it (structural) before nominal `conformance-lookup`.
- **Allocators.** The box threads an allocator exactly like `cfn` threads its
  stored `AllocHandle` — the allocator backs the heap payload and the box's
  `Drop` frees through it.
- **Parametric-type registry (Stage 11 T1).** `BoxedFn` and `(dyn P)` are
  registered/stamped like parametric structs (reserve-name-first, intern mangled
  name, pending-IR queue), reusing that memoization for vtable dedup.

---

## Build order / phases

Each phase: **Agent**, **Read (scoped)** (grep by NAME), **Build**, **Done
when**. A **build-test-runner** gate runs after every implementation phase.

### TE-0 — Ground-verify (read-only map)

**Agent: systems-impl-engineer** (read-only; or Explore for fan-out).
**Read (scoped):** `fn-make-env-struct` / `g-vfn-env-id` / `__vfn_env_N`,
`fn-make-invoke-method`, `fn-make-drop-method`, `fn-emit-env-value`
(modes 0/1/2), `emit-cfn`/`emit-vfn`/`emit-mfn` (lambda.md / `nucleusc.nuc`);
the conformance registry (`derive-closure-conformance` in `generics.nuc`,
`conformance-lookup`, `g-conformances`/`g-protocols`); the parametric-struct
registry and `struct-template-stamp` (Stage 11 T1, reserve-name-first + pending
IR queue); `abi-classify`/`emit-struct-ret`/`abi-arg-frag`/`emit-call-with-args`
(`abi.nuc`); `with-drop-method`/`emit-drop-cleanup`/`type-conforms-drop`/
`emit-move`; `sanitize-for-ir` / `type-mangle` / `__fnty_N`; `AllocHandle`
threading in `cfn`. Confirm CE-3 landed (progress.md).
**Build:** nothing — produce a precise map: where the fat-pointer value kind
inserts; which emitted symbols the vtable slots address; which lookup is the
unified conformance-admission point; whether the boot is inert (the compiler
boxes nothing) so TE-1…TE-5 can target byte-identical.
**Done when:** the map names the exact insertion points and the agent confirms
the per-env `invoke`/`drop` symbols are addressable as vtable slots. → review.

### TE-1 — Fat-pointer value kind + ABI lowering

**Agent: systems-impl-engineer.**
**Read (scoped):** `abi-classify`, `emit-struct-ret`, `abi-arg-frag`,
`emit-call-with-args` (the CE-3 by-value paths), the type-interning / parametric
registry, `type-size`.
**Build:** register the two-`ptr` fat-pointer aggregate (interned once); lower
pass / return / store / bind as a by-value aggregate over the CE-3
MEMORY/COERCE1/COERCE2 path; ensure `load`/`store` treat it as a value.
**Done when:** a hand-constructed fat pointer round-trips by value through a
binding, a call argument, a return, and a `Vector` slot with no corruption.
**Likely byte-identical (compiler boxes nothing); verify, refresh only if it
drifts.** → build-test-runner.

### TE-2 — Static per-type vtable synthesis / dedup / addressing

**Agent: systems-impl-engineer.**
**Read (scoped):** `fn-make-invoke-method` / `fn-make-drop-method` (the emitted
method symbols), `struct-template-stamp` memoization, `sanitize-for-ir` /
`type-mangle`, the global-emission path.
**Build:** for a given concrete type, emit one static vtable global
`{ invoke, drop, clone? }` of the right thunk addresses; memoize per
`(concrete-type, protocol/signature)` (reserve-name-first, intern, reuse) so a
second box of the same type reuses the global; route the vtable name through
`sanitize-for-ir`.
**Done when:** two boxes of the same env type share one IR-legal vtable global;
the `invoke`/`drop` slots point at the correct synthesized thunks. → build-test-runner.

### TE-3 — Boxing coercion at assignment into an erased slot

**Agent: systems-impl-engineer** (the hardest core).
**Read (scoped):** the coercion sites (`emit-let`/`emit-with` binding,
parameter passing, struct-field store, `Vector` element store, `return`);
`derive-closure-conformance` + `conformance-lookup` (the unified admission);
`cfn`'s `AllocHandle` threading; the CE-3 by-value env move.
**Build:** at each erased-slot assignment, (1) admit conformance via the unified
lookup (structural then nominal); (2) move the payload to the heap through the
allocator; (3) set `data`/`vtable`; (4) yield the fat-pointer value.
**Done when:** assigning a `vfn`/`mfn`/`cfn` into a `(BoxedFn …)` slot produces a
correct fat pointer with the payload on the heap and `vtable` pointing at the
TE-2 global; the unified lookup admits both a structural closure conformance and
a nominal `extend` conformance. → build-test-runner.

### TE-4 — Box `Drop` + forwarding-through-vtable conformance

**Agent: systems-impl-engineer.**
**Read (scoped):** `with-drop-method`, `emit-drop-cleanup`, `type-conforms-drop`,
the `invoke`/callable-values dispatch path, `emit-call`.
**Build:** register the fat pointer as `Drop`-conforming (call `vtable.drop(data)`
then free `data` via the stored allocator; POD → no-op drop, free only); lower
`(invoke box args…)` and `(dyn P)` method calls to an indirect call through the
matching vtable slot; type-check the conformance by the box's
signature/protocol parameter.
**Done when:** a `BoxedFn` drops with no leak and no double-free (the env's own
field-drops run, then the box frees); `(invoke box args…)` dispatches correctly
through the vtable; a use-after-drop is rejected. → build-test-runner.

### TE-5 — Instantiation A: `BoxedFn` surface + live use cases

**Agent: systems-impl-engineer.**
**Read (scoped):** the type-parser (so `(BoxedFn (params…) ret)` parses in a
type position), the parametric-type registration, `derive-closure-conformance`,
the `__vfn_env_N` return-type gap noted in progress.md.
**Build:** wire `(BoxedFn (params…) ret)` as a spellable parametric type that
denotes the fat pointer specialized to the `Fn` family; connect the structural
admission; close the env-naming gap so a `(BoxedFn …)` return works.
**Done when:** all three live cases run end-to-end — `(Vector (BoxedFn (i32) i32))`
of heterogeneously-captured closures iterated and invoked; a struct field of
`BoxedFn` type; and a `defn` returning a `(BoxedFn …)` — each with correct `Drop`
at the box's eventual scope (no leak/double-free). Example:
`examples/boxedfn.nuc`. → build-test-runner.

### TE-6 — Instantiation B: general `(dyn Protocol)`

**Agent: systems-impl-engineer.**
**Read (scoped):** the protocol registry (`g-protocols` / `extend` / declared
conformance methods), the §8.5/B2 rejection site in the return-type checker, the
nominal `conformance-lookup`, the unified admission from TE-3.
**Build:** `(dyn P)` as a spellable type over an arbitrary user protocol; build
its vtable from the declared `extend P` methods (TE-2); lift the §8.5 "returns
an unbound protocol" rejection so a `(dyn P)` return is now legal (B2); allow
`(Vector (dyn P))` (heterogeneous collections); reuse the TE-3 boxing coercion
and TE-4 forwarding.
**Done when:** a function returning `(dyn Show)` compiles and runs (B2); a
heterogeneous `(Vector (dyn Show))` holding two distinct concrete types iterates
and dispatches correctly; the conformance lookup admits the nominal path.
Example: `examples/dyn-protocol.nuc`. → build-test-runner.

### TE-7 — Docs / examples / progress

**Agent: api-docs-writer.** Update `docs/generics.md` (`BoxedFn`, `(dyn P)`, the
shared type-erasure machine, the cost note), `docs/special-forms.md` (closure
storage story), progress.md, and confirm the overview.md entry + cross-links.

---

## Open questions / out of scope for v1

- **Multi-protocol boxes** (`(dyn (Show Eq))` / `BoxedFn` conforming to several
  protocols at once). v1 is **single-protocol**; the vtable holds one protocol's
  method set.
- **`clone` on boxes.** The vtable reserves a `clone?` slot but v1 may **omit**
  it — a box is move-only / non-cloneable until a concrete need appears (cloning
  a box means deep-cloning the heap payload through the allocator, which needs
  the env to be `Clone`).
- **Object-safety / method-set selection.** Which protocols are "box-safe"
  (single dispatch, no `Self`-by-value returns, no generic methods) — v1
  restricts to the obviously-safe shapes (the `Fn` family is trivially safe);
  general object-safety rules are deferred.
- **Coherence interaction.** The unified structural-vs-nominal lookup must keep
  one-conformance-per-`(type, protocol)`; v1 must not let a structurally-derived
  `Fn` conformance and a hand-written `extend` collide for the same type/protocol
  (the L7 coherence rule already covers the `Fn` family).
- **`cfn`-of-pointer escape interaction.** Boxing a `cfn` that captured a
  pointer-typed local by reference inherits the known `cfn`-of-pointer escape
  imprecision (closure-enhancements.md §"Known soundness gap"); boxing does not
  *fix* it and may *extend* its reach (a dangling box). v1 documents this; the
  full fix is the deferred per-binding region precision.
- **C-ABI crossing.** v1 excludes `BoxedFn`/`(dyn P)`-mentioning public defns
  from `--emit-cheader` (L8 precedent). A faithful C representation of the fat
  pointer + `Drop` semantics is out of scope.

## Close-out checklist (required by AGENTS.md)

- After **every** phase: `make test` + `make bootstrap` green, compiler compiles
  itself — via **build-test-runner**. Phases inert under self-compilation stay
  byte-identical (no refresh, verify); ABI-touching phases may take a controlled
  refresh but must re-converge (`build/stage2.ll == build/nucleusc.ll`).
- Update [progress.md](progress.md) with a per-phase row (TE-1 … TE-6) and note
  the storability decision is now *implemented* (CE-4 superseded by this doc).
- Update language docs: `docs/generics.md` (`BoxedFn`, `(dyn P)`, the shared
  type-erasure machine + cost profile), `docs/special-forms.md` (closure storage
  story — what is storable and at what cost).
- Confirm the [overview.md](../overview.md) entry and the cross-links from
  closure-enhancements.md (CE-4) and polymorphism.md (the rung-5 deferral) point
  here.

---

## Robot — implementation status

**TE-0 … TE-7 are all done.** 129 tests pass (99 auto-discovered
`examples/*.nuc` + 30 named fixture checks); `make bootstrap` is a
byte-identical fixed point (`build/stage2.ll == build/nucleusc.ll`). Zero
regressions from the L0–CE-3 baseline.

**What shipped:**

- **Shared machine (TE-1 … TE-4):** lazy-registered `__fatptr` `TY-STRUCT` (16
  bytes, rides CE-3 ABI-COERCE2 path unchanged); per-`(type, proto)` static
  vtable globals `@__vt.<type>.<proto>` memoized via parallel arrays in
  `union-registry.nuc`; boxing coercion chokepoint `maybe-box-into-slot`
  (unified structural/nominal admission via `admit-erased-conformance`); shared
  `@__boxedfn_drop` thunk for box `Drop`.
- **TE-5 (`BoxedFn`):** `(BoxedFn (params…) ret)` type surface in
  `union-registry.nuc`; `emit-box-bare-fn` / `ensure-fnfwd-vtable` for
  non-capturing closures; four live cases in `examples/boxedfn.nuc`.
- **TE-6 (`(dyn Protocol)`):** `(dyn P)` type surface in `union-registry.nuc`;
  `dyn-vtable-method-irname` + `emit-dyn-forward` for named-method dispatch;
  B2 unbound-abstract returns; `examples/dyn-protocol.nuc`.
- **C-ABI:** `cheader-mentions-closure` extended to detect `BoxedFn` / `dyn`
  type-AST heads; public defns mentioning them are excluded from `--emit-cheader`
  with an explanatory comment and a definition-site warning. Covered by
  `tests/fixtures/box-cheader.nuc`.

**v1 deferrals (unchanged from the Open questions section):** multi-method
`(dyn P)`; parametric `(dyn (Seq E))`; object-safety enforcement beyond natural
parse rejection; multi-protocol boxes; `clone` on boxes; per-allocator box
handles (current: process-default libc only); cfn-box double-free avoidance
(cfn vtable drop forced null — cfn env leaks on box `Drop`).
