# Stage 14 — Target-typed generic constructors (result-type propagation)

**Status (2026-07-09): TC-1 through TC-4 fully implemented; TC-5 part 1 done, part 2
remaining.** All gates green: `make` clean, `make test` 168/168, `make bootstrap`
stage1==stage2. Boot artifacts converged (incl. Windows IRs).

- **TC-1 + TC-2 (the want channel):** the return-only-tyvar registration gate is
  lifted (a tyvar not determined by any parameter now registers as METHOD-GENERIC;
  the def-time death is retired). `generic-resolve`, `generic-resolve-adapt-tier`,
  `generic-method-bind`, `generic-method-bind-adapt`, and `node-type-call` carry a
  `want:?ptr:Type`; when tyvars remain unbound after args+assoc, `unify-tpat` fills
  them from the expected type over the return pattern (fill-only — never overrides
  an arg-derived binding). `g-want-type` is armed at let/with binding inits, `set!`
  RHS, explicit+implicit `return`, and `.set!` value position, and consumed once at
  `emit-generic-call` entry. A call that cannot resolve and carries a return-only
  tyvar reports `cannot infer type variable '%s' for '%s': no expected type at this
  position — annotate the binding`. **Bug fixed during TC-4a:** `generic-method-bind-adapt`
  (src/generics.nuc:~1500) early-exited `(when (= any-remaining 0) (return 0))`
  before want-fill, so a *zero-arg* return-only-tyvar generic never bound — the
  early-exit now fires only when the binding is actually complete (all tyvars bound).

- **TC-3 (binding materialization):** at `let`/`with` position, a declared
  `(ref S)` (S a struct) initialized with a by-value `S` materializes:
  `tc3-emit-binding-init` derives the want via two non-emitting `node-type` probes
  (whole `(ref S)`, then pointee `S`), emits once, and (iff the resolved init is
  by-value `S`) `tc3-materialize` allocas a backing slot, stores, binds the ref.
  Drop/move/escape reuse the existing `with-drop-method` TY-PTR arm. §1.2 residual
  (stamped parametric by-value drop) verified.

- **TC-4 (constructors + compiler adoption):** added the `*-new` / `*-new-alloc` /
  `*-new-capacity` (by-value) and `*-new-in` (heap) constructor families to
  lib/vector.nuc, lib/hashmap.nuc, lib/hashset.nuc (T / K,V bind from the declared
  type via want). Deleted `make-vec`/`mkvec`/`mkhash` from src/nucleusc.nuc and
  rewrote all ~43 registry-construction sites to `(vector-new-in (addr-of
  g-arena-alloc))` / `(hashmap-new-in …)` — the `cast`-over-`make-vec` type hole
  (stage999-future.md) is retired (element types now honest via want). Reader
  empty-literal hints retargeted to the new constructors.
  `examples/constructors.nuc` + `tests/expected/constructors.out` cover stack/
  with-Drop/explicit-alloc/heap-in-arena/HashMap-two-tyvar/HashSet; a negative
  fixture `tests/fixtures/tc-cannot-infer-tyvar.nuc` exercises the diagnostic.
  **Two gcheck fixes were required (TC-4a):** (1) a cell whose head names a
  registered struct template (`(Vector T)`) is a type operand, not a call; (2) a
  `ref`/`raw`/`ptr` wrapper-keyword head (`(ref (Vector T))`) is likewise a type
  spelling — both at src/generics.nuc:~1944. Without these, `(alloca (Vector T))`
  / `(cast (ref (Vector T)) …)` in a generic body died `in generic body: unknown
  function`. (The `ref`/`raw`/`ptr` half needed a 2-stage manual bootstrap: the
  `-in` heap bodies use `(ref (Vector T))`, so the boot had to gain `ref`-
  recognition before it could compile them — temporarily elide the `-in`
  constructors, build, refresh, restore, rebuild.)

- **TC-5 part 1 (union target-typing at want positions):** `union-target-rewrite`
  (src/union-emit.nuc:867) is parameterized by the target type (return-position
  callers pass `g-fn-ret-type` as before; the new want-position callers —
  `tc3-emit-binding-init` for let/with inits, and `emit-set` RHS — pass the
  declared slot type). So `(let (m:(Maybe i32) (some 5)))`, `(let (m:(Maybe i32)
  none))`, and `(set! m (some 7))` now construct without explicit `make`.
  Byte-identical/additive (the new positions previously died as unknown arms).
  The `.set!` value position is deferred — it sits before `(import-use union-emit)`
  in src/nucleusc.nuc, so `union-target-rewrite` is not in scope there.

- **TC-5 part 2 (value-position distribution) — REMAINING.** The want/rewrite
  does not yet distribute into `if`/`cond`/`do`/`match`/`let`-body tails, so
  `(let (m:(Maybe i32) (if c (some 5) none)))` does NOT rewrite the branches (the
  `if` form itself isn't an arm head). Implementing part 2 means recursing the
  `union-target-rewrite` into the value-position tail forms of those control
  constructs (and clearing it in statement positions) — replacing v1's "stays
  armed through control forms" with precise scoping. This is additive (those
  positions currently die) and independent of the rest.

Allocating, initializing, and returning collection-template instances is the
worst ergonomic spot in the language. The canonical local idiom spells the
type twice and splits construction across two statements
(`(with ((v (ref (Vector i32))) (alloca (Vector i32))) (vector-init v) …)`);
the compiler's own globals go through hand-rolled per-project macros
(`mkvec`/`mkhash`/`make-vec`, src/nucleusc.nuc:494-513) whose `cast` over
`make-vec` is the type hole stage999-future.md laments; and every collection
re-invents constructor names (`vector-init`/`hashmap-init`/`string-new`).

The root cause is single: **type variables bind from argument types only.**
A zero-argument `(vector-new)` has no argument to infer `T` from, and the
declared type at the binding does not flow into the call — so every
collection constructor is forced to be in-place over a receiver, the only
inference channel (lib/vector.nuc:17-22, docs/collections.md §Construction).

This doc designs the root fix: a one-shot, downward **expected-type channel**
("want") from positions that already declare a type — `let`/`with` binding
inits, `set!`, `return`, field stores — into generic resolution, where it
fills tyvars the arguments left unbound. Constructors then become ordinary
value-returning generic functions, and the same channel generalizes the
union `make`/return-position machinery to all typed positions (TC-5).

```lisp
;; locals — today                                ;; after
(with ((v (ref (Vector i32)))                    (with (v:ref:(Vector i32) (vector-new))
       (alloca (Vector i32)))                      (conj v 10)
  (vector-init v)                                  …)                ; drop fires as today
  (conj v 10) …)

;; compiler globals — today                      ;; after
(defmacro mkvec (T)                              (set! g-binops
  `(cast (ref (Vector (ref ~T)))                   (vector-new-in (addr-of g-arena-alloc)))
     (make-vec)))                                ; type from g-binops's declared type;
(set! g-binops (mkvec BinOp))                    ; no cast, no per-project macro
```

---

## 1. Ground truth (verified 2026-07-06 on `build/nucleusc`, branch stage14-cleanup)

### 1.1 Return-only tyvars are an explicit, deferred rejection

A `(defn vector-new () (Vector T) …)` dies **at definition time** with
`defn: type variable 'T' is not determined by any parameter (return-only
generics need dyn, deferred)` (generics.nuc:1121; compiled repro). Two
consequences: tyvar collection already sees return-position tyvars (the gate
counts them in order to reject), and TC-1 is lifting a deliberate gate, not
discovering new territory. The `dyn` route the message alludes to (a
type-erased return) remains separately deferred — TC is the static-dispatch
answer.

### 1.2 By-value Drop bindings and by-value constructors already compose

`with-drop-method` (src/nucleusc.nuc:3197-3254) arms Drop for **two** binding
shapes: `TY-PTR`-to-Drop-struct (the classic ref+alloca idiom) and — CE-3
fix (c) — a **by-value `TY-STRUCT` binding**, dropped through a synthesized
`(ref S)` against the binding's stack slot. Compiled repro: a `Res` struct
with a printing `drop`, built by a `string-new`-shaped by-value constructor
(alloca, init, `(return (deref r))`), bound with `(with (r:Res (make-res))
…)` — prints `body / dropped 42 / after`. So the constructor *shape* TC needs
is already legal and already owned; what's missing is only the type
inference. Still to verify in TC-3: the same by-value arm for a **stamped
parametric** instance (METHOD-GENERIC drop instantiation, nucleusc.nuc:3251).

### 1.3 By-value bindings are miserable to *use* — the receiver-shape problem

Every collection method takes `(ref (Vector T))`; there is no auto-ref. A
by-value binding pays `(addr-of …)` at every call — in-tree proof:
`join`'s `out:String (string-new)` calls `(join-push-cstr (addr-of out) …)`
per iteration (lib/combinators.nuc:367-375). A constructor story that hands
users by-value bindings would be a net ergonomics **loss** at use sites.
TC-3's materialization rule resolves this; note the language's own
convention already agrees — the compound struct literal `(StructName …)`
yields `ptr:StructName`, alloca-backed (docs/special-forms.md §compound
literal): construction expressions yielding a *pointer to storage* is the
established Nucleus idiom.

### 1.4 The downward channel exists for exactly one position

`g-fn-ret-type` (src/nucleusc.nuc:193) is a want channel scoped to return
position: `union-target-rewrite` (src/union-emit.nuc:864) consults it at
`emit-return` (nucleusc.nuc:5409) and the implicit end-of-body return
(nucleusc.nuc:7480) to rewrite `(ok v)`/`none`/`(err e)` into
`(make Type arm …)`. Everywhere else, union construction needs the explicit
`make` spelling. TC-2 generalizes the channel; TC-5 generalizes the rewrite.

### 1.5 The upward metadata and the hook points exist

- `generic-binds-for`/`method-bound-ret-type` (generics.nuc:248, 1380)
  already compute "the return type with tyvars substituted" — built for
  conformance probing and LW-2. The reverse direction (unify the return
  *pattern* against a concrete type to produce bindings) is the same
  structural walk `unify-tpat` (generics.nuc:808) already does for
  parameters.
- `emit-let` extracts the declared binding type **before** emitting the init
  (nucleusc.nuc:5491 → 5513) and already directs behavior with it — TE-3's
  `maybe-box-into-slot` at 5518 is slot-type-directed coercion in this exact
  spot. `emit-set` (nucleusc.nuc:5853) knows the slot type from scope lookup.
- LW-1/LW-2 (done) factored resolution into a shared, side-effect-free
  `generic-resolve-adapt-tier` with a dying (emit) and non-dying (node-type)
  mode — the exact pattern TC's resolver extension follows for the
  node-type↔emit lockstep.

### 1.6 What the reader literals already cover, and don't

`[…]`/`{…}`/`#{…}` expand (in the reader, lib/reader.nuc:609-655) to the
alloca+init+conj `let` shape and compose with `with`/Drop — but only for
**non-empty, scalar-literal** elements; the empty literal is a hard error
whose hint text points at the verbose idiom (reader.nuc:612), and there is
no allocator override. Literals stay; TC covers the empty/typed/allocator
cases they can't, and the error hints get retargeted in TC-4.

## 2. Non-goals

- **No want in call-argument positions** (an argument's expected type coming
  from the enclosing call's parameter list) — chicken-and-egg with overload
  resolution; explicitly out of scope for this stage.
- **No upward inference, no unification variables.** The want is one-shot
  and downward; it never flows back out of a call or joins with sibling
  constraints. Full bidirectional typing stays rejected (int-widening.md §5
  already rejected Go-style untyped constants on the same grounds).
- **Want never changes which method wins among argument-viable candidates.**
  It only fills tyvars the arguments left unbound. Tier-0 exact matches and
  all existing resolutions are untouched by construction.
- **No binding-type inference expansion.** CE-1's bare-symbol closure
  inference stays as-is; TC *needs* declared types (they are the want
  source), so the "type your bindings" culture is load-bearing, not
  ceremony.
- **No literal-typing changes.** LW owns literal adaptation; want composes
  with it (§3 TC-1) but does not re-type literals.
- **`defvar` inits stay literal-only** (stage999-future.md); globals adopt
  constructors via `set!` in init functions, which is where the compiler
  builds its registries anyway.

## 3. Design — the want channel, in five phases

### TC-1 — resolution: fill unbound tyvars from the expected type

Lift the generics.nuc:1121 gate: a tyvar appearing only in the return
spelling registers fine (METHOD-GENERIC); its determination is deferred to
call sites. Then extend `generic-resolve` (generics.nuc:464) — and the shared
adapt tier — with an optional `want:?ptr:Type`:

- **Tier 0** (exact concrete): unchanged, still wins outright.
- **Tier 1**: `generic-method-bind` binds from args as today; if the bound
  array is incomplete **and** want is non-null, unify the method's return
  pattern against want (`unify-tpat` over the return spelling, tyvars
  already bound by args held fixed — want fills, never overrides). Still
  incomplete → the candidate fails. Then `generic-constraints-ok` and
  instantiation exactly as today; `generic-instantiate` (generics.nuc:1542)
  and the mono cache are indifferent to which side derived the bindings.
- **Tier 2** (LW's adapt pool): same insertion point — bind from
  receiver/exact args, fill from want, *then* adapt remaining literal args.
  LW's invariant "adaptation never binds a tyvar" is preserved; want-fill is
  a binding step, not adaptation.
- **Ambiguity**: the existing accounting (`ncand`/`wn` > 1 → die) now counts
  want-completed candidates too. New diagnostic when a call has free tyvars
  and want is null or fails to unify:
  `cannot infer type variable 'T' for 'vector-new': no expected type at this
  position — annotate the binding` (never the misleading
  `no matching method`).

The probe used by `node-type-call` gets the same want parameter with the
non-dying mode (LW-2's shared-resolver pattern), returning null on
ambiguity/no-match as today.

Interaction checked: type-erasure's `abstract-call-via-generic` and
conformance probing drive `generic-binds-for` from *parameter* types only —
a return-only-tyvar method simply never matches there; lifting the
registration gate does not perturb the `dyn`/TE machinery.

### TC-2 — emit-side want positions + the node-type mirror (lands with TC-1)

Introduce `g-want-type` beside `g-fn-ret-type`, with save/set/restore
discipline (nesting-safe) at:

- `let`/`with` binding init — set to the declared type right before the
  `emit-node bval-node` at nucleusc.nuc:5513 (and the `with` twin);
- `set!` RHS — the slot's type (emit-set, nucleusc.nuc:5853);
- explicit and implicit `return` — `g-fn-ret-type` doubles as the want
  (nucleusc.nuc:5409, 7480);
- field stores (`.set!` value position) — the field's type.

**Consume-once at the first call**: `emit-call`/the generic-call path reads
`g-want-type` into a local and nulls the global *at entry, before emitting
arguments* — so argument subexpressions never see the outer want. Control
forms (`if`/`cond`/`do`/`match`/`let` bodies) leave it armed in v1, which
means the first call emitted anywhere in the init consumes it. Safety
analysis of that choice: a wrong grab requires a non-tail call with free
tyvars whose return pattern *unifies* with the outer declared type — and
even then the binding's final value is still checked against the declared
type by the existing `coerce-int-val` at nucleusc.nuc:5517, so the failure
mode is a diagnostic, never a silently wrong monomorph. TC-5 replaces
"stays armed" with explicit distribution to value positions and clearing in
statement positions.

**Lockstep**: the shared resolver carries the want, so emit and
`node-type-call` (generics.nuc:3554) cannot compute different types for the
same resolution. In contexts where the type model runs without a binding
target (narrowing probes, `callable-invoke-type`), it passes want = null and
types a want-dependent call as null — the documented node-type escape hatch,
same as pre-LW-2 widened calls: unknown, not divergent. TC-1+TC-2 are one
change for lockstep purposes; the bootstrap fixed point is the gate.

### TC-3 — binding materialization: value→ref at declared-ref bindings

**Status: implemented (2026-07-08).** See the top-of-file Status note. `tc3-emit-binding-init`
(src/nucleusc.nuc:5536) + `tc3-materialize` (:5508) implement the two-probe want
derivation and materialization; `emit-let` (:5632) and `emit-with` (:5709) call them.
`node-type-call`'s tier-2 (src/generics.nuc:3685) falls back to `g-want-type` so the
non-emitting probe drives generic resolution. Byte-identical (additive); `make test`
166/166; `make bootstrap` green. §1.2 residual (stamped parametric by-value drop) verified.

Resolves §1.3. New coercion rule at `let`/`with` binding position only: when
the declared type is `(ref S)` for a struct `S` and the init value is a
by-value `S` (type-eq on the pointee), the compiler materializes — allocas
an `S` backing slot, stores the value, and binds the name as the ref to it —
instead of today's `let: init type mismatch` death. Then:

```lisp
(with (v:ref:(Vector i32) (vector-new))   ; CP-1 chain sugar, already landed
  (conj v 10)                             ; methods take (ref …) — no addr-of
  …)                                      ; Drop arms via the existing TY-PTR shape
```

- The want passed to the init is derived from the declared type: try the
  whole type first (heap constructors return `(ref (Vector T))` — TC-4);
  if no candidate completes and the declared type is ref-to-struct, retry
  with the pointee and arm materialization iff the resolved return is
  by-value. Deterministic, two probes max.
- Drop/`move`/escape need **no new rules**: the materialized backing is
  frame storage (taint-frame, like any alloca ref — docs/special-forms.md
  §pointer-lifecycle), and `with` ownership uses the existing
  `with-drop-method` TY-PTR arm.
- Plain by-value bindings (`(with (r:Res (make-res)) …)`) keep working as
  verified in §1.2 — materialization is sugar on top, not a semantics
  change. This phase also carries the §1.2 residual verification (stamped
  parametric by-value drop).

### TC-4 — stdlib constructors, compiler adoption, retirement sweep

**Status: implemented (2026-07-09).** See the top-of-file Status note. The `*-new` /
`*-new-alloc` / `*-new-capacity` / `*-new-in` constructor families are in lib/vector.nuc,
lib/hashmap.nuc, lib/hashset.nuc; `make-vec`/`mkvec`/`mkhash` deleted and all ~43 compiler
registry sites rewritten to `(vector-new-in (addr-of g-arena-alloc))` / `(hashmap-new-in …)`.
Two gcheck fixes (struct-template heads + `ref`/`raw`/`ptr` wrapper heads, src/generics.nuc:~1944)
were required to compile the constructor bodies; the `ref`/`raw`/`ptr` half needed a 2-stage
manual bootstrap (boot had to gain recognition before it could compile the `-in` bodies).
Reader hints retargeted; `examples/constructors.nuc` + negative fixture added. Boot converged;
`make test` 168/168; `make bootstrap` green.

The constructor families, all ordinary generics (the `string-new` shape:
alloca, init, `(return (deref v))`):

```lisp
;; by value — stack/binding use; want binds T (K V) from the declared type
(defn vector-new () (Vector T))
(defn vector-new-alloc ((a (ref AllocHandle))) (Vector T))     ; element allocator
(defn vector-new-capacity (n:usize) (Vector T))
(defn hashmap-new () (HashMap K V))
(defn hashmap-new-alloc ((a (ref AllocHandle))) (HashMap K V))
(defn hashset-new () (HashSet T))
(defn hashset-new-alloc ((a (ref AllocHandle))) (HashSet T))

;; heap placement — struct itself allocated through the handle, elements too;
;; returns an escapable ref. The mkvec/mkhash replacement (arena-oriented:
;; a libc-backed heap shell has no drop-the-shell path — documented).
(defn vector-new-in ((a (ref AllocHandle))) (ref (Vector T)))
(defn hashmap-new-in ((a (ref AllocHandle))) (ref (HashMap K V)))
(defn hashset-new-in ((a (ref AllocHandle))) (ref (HashSet T)))
```

The `*-init` family stays as the implementation tier (and for
caller-managed storage); `String` gains nothing (its `*-new` set exists) but
demonstrates the naming convention TC standardizes on.

Adoption and retirement:

- src/nucleusc.nuc: delete `make-vec`/`mkvec`/`mkhash`, rewrite the ~25
  registry-construction sites to `…-new-in (addr-of g-arena-alloc)` —
  killing the `cast`-over-`make-vec` hole for good.
- lib/reader.nuc:612 (+ the set/map twins): empty-literal error hints point
  at `vector-new` etc. instead of the alloca+init idiom.
- Docs: docs/collections.md §Construction rewritten around the new idiom
  (the ref+alloca+init form demoted to "caller-managed storage");
  lib/vector.nuc:17-22's no-value-constructor rationale replaced;
  docs/generics.md documents the want channel; stage999-future.md's
  constructor lament resolved.
- Tests: `examples/constructors.nuc` (stack + with/Drop + explicit-allocator
  + heap-in-arena + a `(HashMap CStr i32)` two-tyvar bind); negative
  fixtures per the LW-5 idiom — a no-want zero-arg generic call
  (`cannot infer type variable`), and an ambiguity fixture (two zero-arg
  generics distinguishable only by want with a want that matches both...
  which requires two methods on one generic with unifiable returns — if
  unconstructible, the fixture documents that instead).

### TC-5 — generalize target typing: unions and value-position distribution

**Status: part 1 implemented (2026-07-09); part 2 remaining.** `union-target-rewrite`
(src/union-emit.nuc:867) is parameterized by the target type and run at the let/with
binding-init and `set!` RHS want positions (in addition to return positions), so union
construction works without explicit `make` there. The `.set!` value position is deferred
(it sits before `(import-use union-emit)` in src/nucleusc.nuc). Part 2 — distributing the
rewrite into `if`/`cond`/`do`/`match`/`let`-body value tails — is the remaining work
(additive; those positions currently die). See the top-of-file Status note.

Two halves, both riding the TC-2 channel:

1. **Union construction at every want position.** Parameterize
   `union-target-rewrite` (src/union-emit.nuc:864) by the target type
   (return-position callers pass `g-fn-ret-type`, exactly as today) and run
   it wherever TC-2 arms a want whose type is a defunion/niche:
   `(let (m:(Maybe i32) none))`, `(set! slot (some 5))`,
   `(.set! s result (ok 5))`, `(let (r:!i32 (err! oom)))` — all currently
   requiring `make` or a return detour. The rewrite is syntactic and
   already handles every arm/niche case; only its type source moves.
2. **Distribution through value-position control flow.** The want
   distributes into `if`/`cond` branch tails, `do` tails, `match` arm
   values, and `let` body tails — and is *cleared* in statement positions —
   replacing v1's "stays armed" with precise scoping. This makes
   `(let (m:(Maybe i32) (if c (some 5) none)))` construct both arms
   correctly. MC-1's shared `type-join` (done) already absorbs the
   elem-less joins this creates; the join sites don't change, the branches
   just arrive better-typed. node-type mirrors the distribution (same
   shared-resolver want in branch typing).

TC-5 retires the last `make` ceremony outside genuinely explicit-instance
construction, and closes the "target-typing is a return-position special
case" asymmetry.

## 4. Verification and bootstrap convergence

- **TC-1+TC-2**: additive by construction — no return-only generics exist in
  the tree, and want is only consulted when tyvars remain unbound after
  args, which never happens for existing methods. Expected **byte-identical**
  (`build/nucleusc.ll` diff + `make bootstrap` fixed point as the lockstep
  gate). New diagnostics exercised via fixtures only.
- **TC-3**: the materialization rule fires only on declared-ref +
  by-value-struct init, which today dies `let: init type mismatch` —
  additive, byte-identical.
- **TC-4**: **not** byte-identical (new lib functions; ~25 compiler call
  sites rewritten; string pool shifts) — one standard reconverging refresh
  (`make update-bootstrap` cycle per context/build.md), scheduled so no
  other refresh window is in flight. `make test` green before and after;
  the mkvec-replacement sites are behavior-identical (same arena handle,
  same element types), so runtime output is unchanged.
- **TC-5**: additive (the new rewrite positions currently die as unknown
  symbols or type mismatches); expected byte-identical pre-adoption, with
  any `make`-ceremony cleanup in src/lib as a separate, IR-identity-checked
  trailing sweep.
- Full gates after every phase: `make test`, `make bootstrap`; the JIT/macro
  path is exercised by the existing macro tests (want positions inside
  `defmacro` bodies emit under the same code paths).

## 5. Alternatives considered and rejected

- **Library-only `new` macro + `Init` protocol** (`(new (Vector i32) a)`
  expanding to alloca/heap-alloc + a protocol `init`). Ships without
  compiler changes (macros take type args — `mkvec` proves it), but keeps
  the type double-spell at bindings, cannot branch on conformance (a macro
  is syntactic, so POD vs `Init` types need different spellings), leaves
  `arena.nuc`'s `(new T)` semantics awkwardly overloaded, and becomes a
  surface to deprecate the day the root fix lands. Rejected as the
  destination; `mkvec`/`mkhash` simply live until TC-4.
- **`with-new` binding macro** (binding-integrated alloca+init). A third
  binding form to learn; solves only the local case; subsumed by TC-2+TC-3
  with no new form.
- **Extending `make` to struct templates** (`(make (Vector i32) a)` calling
  an `Init` conformance). Overloads `make`'s union-arm meaning, couples the
  compiler to a library generic by name (the `with`→`drop` coupling is
  precedent, but each instance is a cost), still spells the type at every
  construction site, and is subsumed by TC-1/TC-2.
- **Auto-ref receiver coercion** (a by-value struct local passed where a
  unique candidate wants `(ref S)` auto-takes its slot address). Fixes
  §1.3 at *every* call instead of once at the binding, but is a
  language-wide semantic change — aliasing and escape questions at every call
  site, dispatch interaction with the adapt tier, and a Rust-shaped rule in
  a C-shaped language. The binding-materialization rule gets ref-shaped
  bindings with today's call semantics, in one place.
- **Bare-symbol binding inference beyond closures** (generalize CE-1 so
  `(with (v (vector-new-typed-somehow)) …)` needs no annotation). Attacks
  the double-spell from the other side, but removes exactly the declared
  types the want channel feeds on, and hides types in a codebase whose
  culture deliberately spells them. Complementary at most; not part of TC.
- **Explicit type-application syntax** (`(vector-new @(Vector i32))`).
  New call-site surface duplicating information the binding already
  declares; the union `make` precedent shows explicit-instance spellings
  are needed only where *no* typed position exists — and those cases keep
  working via an annotated binding.
- **Full bidirectional typing / Go-style untyped results.** Threading
  expected types through every emit path; int-widening.md §5 already
  rejected this shape once. TC is the scoped version: one-shot,
  consume-once, declared positions only.

## 6. Sequencing and relationship to other stage-14 work

Hard prerequisites, all landed: **MC-1** (type-join — TC-5's branch
distribution feeds the shared join), **LW-1/LW-2** (the shared
dying/non-dying resolver TC-1 extends; also the tier-2 pool want must
compose with), **SM-1..5** (generics.nuc naming settled — TC edits
resolution in the same file; no shared lines expected, but landing after
avoids churn). The requested completeness/correctness review of the MC and
LW landings is a natural TC-0: TC-1 builds directly on
`generic-resolve-adapt-tier` and `type-join`, so reviewing them first
de-risks the extension point.

Soft edges:

- **TC-4 → 14.1/14.3 (type-safety)**: 14.1 retypes the registry
  `(Vector ptr)`s — the same construction sites TC-4 rewrites. Landing TC-4
  first means 14.1 edits construction lines that are already in final form
  (constructor call + declared type), instead of retyping `mkvec` casts
  that TC-4 is about to delete.
- **TC-4 stays out of S3's quiet-tree window** (defn-signature's tree-wide
  rewrite); TC-4 is itself a discrete refresh window — never two in flight.
- **TC-1/2/3/5 are additive and byte-identical** — they slot into the
  small-band positions of the staging order (with items like NS-1/NS-2),
  any time after the prerequisites.
- **No interaction** with NS (strings), UN (cast split — TC-4 *deletes*
  casts, which is upstream of UN-4's sweep and strictly helpful), AT, or
  the AVR/RISC-V track.

Order within the workstream: **TC-1+TC-2 (atomic, lockstep gate) → TC-3 →
TC-4 (refresh window) → TC-5**, with TC-5 movable ahead of TC-4 if a quiet
window is scarce — they are independent.
