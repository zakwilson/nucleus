# `(dyn P)` for arbitrary protocols — lifting the v1 limits

**Status: future.** Extends Stage 13's type-erasure machine
([stage13/type-erasure.md](../stage13/type-erasure.md), TE-6) from
single-method, non-parametric protocols to (nearly) arbitrary ones:
multi-method protocols, parametric protocol *applications* with concrete
arguments, and a principled per-method dyn-safety rule instead of the blanket
single-method gate. First named client: the native-IO `Writer` protocol
([native-io.md](native-io.md) §1.1, which currently contorts to stay
single-method — its "Option B" assumes this doc).

## 1. Ground truth (verified against the tree, 2026-07-07)

Grep by NAME; line numbers drift. All sites are in `src/nucleusc.nuc` unless
noted.

- **The machine** (all shipped, TE-1…TE-6): fat pointer `{data, vtable}`
  (16-byte `__fatptr` `TY-STRUCT`, CE-3 ABI path); per-`(type, proto)` static
  vtable `@__vt.<type>.<proto> = internal constant { ptr, ptr }
  { ptr method0, ptr drop-or-null }` — **slot 0 = the method, slot 1 =
  drop** — memoized by interned spelling key in the `g-vtable-keys` /
  `g-vtable-names` parallel arrays; boxing coercion chokepoint
  `maybe-box-into-slot` with unified structural/nominal admission
  (`admit-erased-conformance`); shared `@__boxedfn_drop` thunk that **reads
  the drop slot at index 1 verbatim**.
- **The v1 gates to lift are two `die-at`s in `dyn-vtable-method-irname`:**
  `(!= (ppp num-sigs) 1)` → "only single-method protocols are boxable in v1"
  and `(> (ppp num-params) 0)` → "parametric protocols are not boxable in
  v1". Everything downstream already speaks in slots:
  - `dyn-method-slot` scans `P`'s sigs by method name and returns the **sig
    index** — it is already multi-method-shaped; today index and vtable slot
    coincide only because there is one sig (a second sig's index 1 would
    collide with the drop slot).
  - `emit-dyn-forward` takes a `slot`, GEPs the **hardcoded `{ ptr, ptr }`**
    vtable type, loads the thunk, coerces args against `sigs[slot]`, and
    emits the indirect call with `data` as the `(ref Self)` receiver.
  - The dispatch hook in `emit-generic-call` (first argument is a dyn box +
    the generic names one of `P`'s methods → forward) is slot-agnostic.
- **`subst-proto-sig-node` already accepts a params/args pair** —
  `dyn-vtable-method-irname` calls it with `(ppp params) null 0`. The
  parametric case is plumbing, not new machinery.
- **Conformance records retain bound protocol args** (stage11 assoc-types A0;
  `Conformance.args`, coherence-checked on re-extend in `src/generics.nuc`).
  This is the admission hook parametric `(dyn (P args…))` needs.
- **Object-safety v1**: methods whose non-receiver params or return mention
  `Self` are rejected (whole-protocol, at the dyn site). Receivers are
  `(ref Self)` — the forward passes `data` as the receiver pointer.
- **No formal super-protocols exist.** The `Protocol` record
  (`src/compiler-types.nuc`) is `{name, sigs, num-sigs, params, num-params}` —
  "`Str` extends `Eq`" (docs/strings.md §4) is a documentation convention,
  not a compiler fact. There is nothing to embed in a vtable.
- **Bootstrap inertness**: the compiler's own source never boxes —
  `dyn-canonical`/`boxedfn-canonical` return null at every site during
  self-compilation — so **every phase below can target a byte-identical
  bootstrap** (verify, do not assume; the TE discipline).

## 2. Scope

**In:** multi-method protocols; parametric protocol applications with all
arguments concrete (`(dyn (Iterator i32))`); per-method dyn-safety with
call-site diagnostics; the `BoxedFn`/"Fn" special-case cleanup this enables.

**Out (with reasons):**

- **Multi-protocol boxes** `(dyn (Show Eq))` — the spelling now *collides*
  with parametric application (`(Show Eq)` parses as protocol `Show` applied
  to argument `Eq`). Would need a distinct form (`(dyn (+ Show Eq))` or
  similar) and vtable concatenation. Workaround exists: declare a combined
  protocol and `extend` it. Deferred until a client appears.
- **Downcasting / RTTI** (`(dyn P)` → concrete `T`): needs a type-identity
  word the vtable doesn't carry. Deferred.
- **Super-protocol vtables**: no formal `extends` mechanism exists to encode
  (above). If protocol requirements ever become compiler facts, embedded
  super-vtable pointers are the standard shape; out of scope here.
- **`clone` on boxes, per-allocator box handles, cfn-box drop gap, C-ABI
  crossing** — unchanged TE deferrals, orthogonal to this doc.

## 3. Design

### 3.1 Vtable layout — append, don't relayout

Committed layout for a protocol with methods `m0 … m(k-1)`:

```
{ ptr m0, ptr drop, ptr m1, …, ptr m(k-1) }
```

i.e. **the existing two slots keep their positions** (`m0` at 0, `drop` at 1)
and further methods append at `2…k`. Slot mapping is one total function:
`slot(sig i) = (if (= i 0) 0 (+ i 1))`.

Rationale over the "clean" `{drop, m0, m1, …}` relayout: the shared
`@__boxedfn_drop` thunk (reads index 1), the `BoxedFn` callable path (loads
index 0), and every already-emitted single-method example vtable stay
**textually identical** — a `k = 1` protocol still emits
`internal constant { ptr, ptr }` byte-for-byte. The clean layout buys
contiguous method slots at the price of churning both existing clients and
every example's IR for zero behavior change; non-contiguity costs one small
mapping function. This is the same additive-over-aesthetic call the TE
phases made throughout.

The vtable constant's IR type generalizes from the hardcoded `{ ptr, ptr }`
to a struct of `k+1` `ptr`s (`{ ptr, ptr, ptr }` for two methods, …). Both
`ensure-vtable-for` (emission) and `emit-dyn-forward` (the GEP) derive the
spelling from `num-sigs` — the protocol is in hand at both sites.

A **dyn-unsafe method** (§3.3) still owns its slot, emitted as `ptr null` —
slots are positional by declaration order, never compacted, so adding a safe
method after an unsafe one cannot shift earlier slots.

### 3.2 Synthesis and dispatch — generalize the existing single case

- **`dyn-vtable-method-irname` → per-sig resolution.** The existing body
  (substitute `Self`→concrete via `subst-proto-sig-node`, parse name/params,
  `generic-find-method-exact`) becomes the loop body over `sigs[0…k)`;
  the two v1 `die-at` gates are deleted. A sig that fails per-method safety
  (§3.3) yields a null slot instead of dying; a *safe* sig with no concrete
  impl still dies (the conformance was declared incomplete — same error as
  today).
- **`dyn-method-slot`** already returns the sig index; the call site applies
  `slot(i)`. The `emit-generic-call` hook is unchanged.
- **`emit-dyn-forward`**: GEP against the `k+1`-slot type; before loading,
  if the resolved sig is classified unsafe, `die-at` with the method name
  and the *reason* it is unboxable (§3.3) — a compile-time error, since
  classification is static.

### 3.3 Per-method dyn-safety (replaces the whole-protocol gate)

A method is **dyn-callable** iff:

1. its receiver is `(ref Self)` (the forward passes `data` as a pointer;
   a by-value `Self` receiver has no uniform ABI class once erased);
2. `Self` does not appear in any non-receiver parameter or the return type
   (v1's existing rule — the concrete type is erased at the call site;
   binary methods like `Eq`'s are the canonical exclusion);
3. the signature introduces no type variables beyond the protocol's own
   parameters (a per-call generic method would need per-call
   monomorphization through an erased pointer — impossible by construction);
4. after substituting the application's concrete protocol args (§3.4), all
   parameter/return types are concrete.

A protocol is **boxable iff at least one method is dyn-callable**. Unsafe
methods get null slots and a targeted call-site error
(`"(dyn Str): 'eq' is not dyn-callable: Self appears in a non-receiver
parameter"`); safe methods work. This is Rust's per-method
`where Self: Sized` opt-out shape rather than its old whole-trait
object-safety wall — chosen because real protocols mix (a mostly-callable
protocol with one binary method shouldn't lose `dyn` entirely, and the
"declare a narrower protocol" workaround duplicates conformances).

### 3.4 Parametric applications — `(dyn (Iterator i32))`

- **Parse**: the `dyn` type form accepts an application list
  `(dyn (P arg…))` beside the bare name (today rejected as unparseable).
  Every `arg` must be a **concrete type** — a tyvar in a `dyn` application
  is an error (`(dyn (Iterator E))` is not a thing; erasure fixes the
  instance).
- **Key**: the vtable memo key and `@__vt` symbol already build from
  spellings — the application spelling (`(Iterator i32)`) slots in via the
  existing `type-mangle-token`/`sanitize-for-ir` route.
- **Substitution**: pass the application args through
  `subst-proto-sig-node`'s existing params/args parameters (today `null 0`)
  so each sig resolves at `Self`→concrete, `E`→`i32`.
- **Admission**: `admit-erased-conformance` checks the nominal conformance
  *instance* — the `Conformance.args` retained by assoc-types A0 must match
  the application's args (the same spelling comparison the re-extend
  coherence check uses). `(extend Foo (Iterator i32))` admits
  `(dyn (Iterator i32))`, not `(dyn (Iterator i64))`.
- **Safety interplay**: rule 4 of §3.3 runs *after* substitution, so an
  associated-type-shaped signature (`(next:(Maybe E) …)`) is dyn-callable
  once `E` is fixed by the application.

### 3.5 `BoxedFn` convergence (optional tail)

With multi-method + parametric `dyn`, `(BoxedFn (i32) i32)` and
`(dyn (UnaryFn i32 i32))` genuinely coincide (type-erasure.md predicted
this). The `BoxedFn` surface stays — it is the ergonomic spelling and
carries the *structural* admission path for closures — but
`ensure-vtable-for`'s `strcmp proto "Fn"` special case can retire in favor
of the general parametric route, with structural derivation folded into
`admit-erased-conformance` as the closure-typed branch. Pure cleanup; no
user-visible change; do it last or not at all.

## 4. Phases

Each phase ends with `make test` + `make bootstrap`; every phase should be
**byte-identical** (the compiler boxes nothing — verify per the TE
discipline). Orchestration follows type-erasure.md's pattern: scoped reads,
grep by name, one systems-impl-engineer per phase, build-test-runner gates.

- **DP-0 — ground-verify.** Confirm §1's map still holds (this doc will age);
  in particular that `dyn-method-slot` still returns sig indices, the drop
  thunk still reads index 1, and `subst-proto-sig-node`'s args path is
  exercised by the extend checker (so DP-3 reuses tested code).
- **DP-1 — layout + synthesis.** §3.1 slot mapping + `k+1`-slot constant
  emission; `dyn-vtable-method-irname` → per-sig loop with null slots for
  unsafe methods (§3.3 classification as a pure predicate, shared with
  DP-2's diagnostics). Single-method vtables must emit byte-identical text.
- **DP-2 — dispatch.** `slot(i)` at the `dyn-method-slot` consumer;
  `emit-dyn-forward` generalized GEP + unsafe-method call-site diagnostic.
  Gate: a two-method protocol example dispatches both methods through one
  box; a mixed safe/unsafe protocol errors only on the unsafe call.
- **DP-3 — parametric applications.** Parse `(dyn (P arg…))`,
  concrete-args check, memo/symbol keying, substitution plumbing,
  `Conformance.args` admission. Gate: `(Vector (dyn (Iterator i32)))`
  holding two distinct conformers iterates via `next` through the vtable;
  `(dyn (Iterator i64))` rejects an `(Iterator i32)`-only conformer with a
  clear error.
- **DP-4 — docs + close-out.** Rewrite docs/generics.md's "v1 scope limits"
  (multi-method and parametric move from "not supported" to specified
  behavior; per-method safety documented with the four rules);
  `examples/dyn-multi.nuc` + `examples/dyn-parametric.nuc`; progress.md.

## 5. First clients (why this is worth building)

- **native-io `Writer`/`Fmt`** ([native-io.md](native-io.md)): Option B
  gives `Writer` a real `flush` method, so a `(dyn Writer)` held by the
  compiler's emission path can be flushed generically instead of the flush
  living as a concrete-type-only function. Also unlocks a multi-method
  `Reader` protocol when one is wanted.
- **Heterogeneous iteration**: `(Vector (dyn (Iterator T)))` — mixed
  iterator sources driven uniformly.
- **The Stage 9 rung-5 endgame**: `(dyn P)` was always meant to be the
  general dynamic escape hatch; the single-method gate made it a proof of
  mechanism. This doc makes it the feature.
- **Computed/reflective field access** (callable-values.md deferral) remains
  a future client; nothing here blocks or builds it.

## 6. Open questions

- **By-value-`Self` receivers**: could in principle be admitted via a
  synthesized shim thunk (load the concrete value from `data`, call the
  by-value method) since the shim is emitted per concrete type where the
  size *is* known. Deferred — no client; rule 1 stays until one appears.
- **Multi-protocol spelling** if that feature is ever wanted (§2's syntax
  collision needs resolving first).
- **Vtable identity for `=`**: two boxes of the same concrete type share a
  vtable global; whether `=` on `(dyn P)` should mean anything (data
  pointer identity? forwarded content compare?) is undecided — v1 keeps
  boxes non-`Eq`, matching today.
