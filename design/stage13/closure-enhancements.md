# Closure feature enhancements — implementation prompt

Enhancements that make the Stage 13 closure feature (`fn`/`vfn`/`mfn`/`cfn`,
[lambda.md](lambda.md)) **more complete and more capable**, beyond the L0–L9
core that already landed. These are language/compiler-feature changes, distinct
from the dogfooding loop refactor in [functional-refactor.md](functional-refactor.md)
(which *consumes* some of these — it depends on **CE-1** below).

Read [lambda.md](lambda.md) for the closure machinery and
[lambda-prompt.md](lambda-prompt.md) for the conformance-derivation design; this
file is *what to build, in what order, and who builds it*. It also records two
items that are **design exploration / known gaps**, not yet scheduled
(**CE-4 storable closures**, and the `cfn`-of-pointer escape imprecision).

## How to run this (orchestration)

Multi-phase compiler task. **Do not implement it in the orchestrating thread.**
Split into the enhancements below and dispatch each to the named local agent
(roster: [context/local.md](../../context/local.md)); keep the main thread for
planning and integration. **Context-budget rule — keep every task well under
100K tokens:** each enhancement names the specific functions to read; **no line
anchors — grep by NAME, line numbers drift.** After every implementation task,
dispatch **build-test-runner** for `make test` + `make bootstrap` and confirm
the boot re-converges before starting the next.

## Summary

| # | Enhancement | Kind | Status | Gates |
|---|---|---|---|---|
| CE-1 | Named closures (`let`/`with` env-type inference) | feature | ready (S) | the refactor's named-operand story |
| CE-2 | Mutable capture (`set!`/`inc!`/`dec!` on a capture) | bug-shaped gap | ready (S) | stateful closures + `cfn` write-back |
| CE-3 | Owning-closure export (by-value return) | feature epic | ready (M) | returning an owning closure out of a `with` |
| CE-4 | Storable closures (`BoxedFn`) | design exploration | **not scheduled** | closures in collections / struct fields |

CE-1, CE-2, CE-3 are mutually independent and may land in any order (CE-3
benefits from being validated against CE-1's binding path but does not require
it). CE-4 is a future direction documented here for completeness; it builds on
CE-3.

## Non-negotiable invariants

- **Additive / byte-identical where inert.** No existing compiler source uses
  closures, so CE-1 (inference-only) and CE-2 (additive rewrite) must keep
  `make bootstrap` a fixed point with **no** `make update-bootstrap`. CE-3 touches
  the struct-return ABI and `with`-drop arming and **may drift** — a one-time
  controlled refresh is allowed but the boot must re-converge
  (`build/stage2.ll == build/nucleusc.ll`) with tests green.
- **Generated names stay IR-legal.** Any synthesized method routed through
  generics must keep `!`/`?` out of emitted names — route through the existing
  `sanitize-for-ir` path.
- **Zero-cost path is preserved.** None of these may add overhead to the inline
  `fn` / POD-`vfn` monomorphized path that the refactor's hot loops depend on.
  CE-4's type-erased path is explicitly opt-in and stays out of hot loops.

---

## CE-1 — Named closures (the refactor enabler)

**Agent: systems-impl-engineer.** The sole typechecker change; gates the
refactor's named-operand story. Today a closure can only be passed *inline*,
because the anonymous env type cannot be spelled in a `let`/`with` binding (no
type inference for env types — limitation (a) of the lambda progress).

**Read (scoped):** `emit-let` (`nucleusc.nuc` ~4199, die ~4214) and `emit-with`
(~4270): the binding path that dies when no `:type` is spelled; the init value's
type is available at `((cast ptr:Val v) type)` (~4221) but never consulted.
`extract-name-and-type` (~701). `emit-cfn` (~3738) / `emit-vfn`/`emit-mfn`
(~3823): all yield a `(ref Env)` `TY-PTR` Val. `derive-closure-conformance`
(`generics.nuc` ~2235): confirm a named binding conforms once it carries
`(ref Env)`.

**Build:**
1. When `extract-name-and-type` returns null **and** the binding node is a bare
   symbol (no destructuring), fall back to inferring `ty` from the emitted init
   value's type (`((cast ptr:Val v) type)`), in both `emit-let` (after the init
   is emitted) and `emit-with`. The subsequent `coerce-int-val` becomes a
   self-coerce no-op for the matching case.
2. Gate the fallback tightly: bare-symbol bindings only, so existing
   destructuring/typed bindings are unaffected. Do not introduce inference for
   non-closure types beyond what the init already exposes.

**Done when:** `(let (f … (cfn …)) (f 1))` and `(with ((f … (cfn …))) (f 1))`
both compile and run (a `cfn` capturing a `with`-owned referent drops correctly
via the existing `TY-PTR` `with-drop-method` path); a `let`-bound `cfn` passed to
`reduce` as a **named** operand type-checks and runs (proving conformance is
type-keyed — `derive-closure-conformance` keys off the env spelling + the
recorded `invoke`, never on whether the operand was a literal or a name).
**`make bootstrap` byte-identical, no refresh.** → build-test-runner.

---

## CE-2 — Mutable capture (`set!`/`inc!`/`dec!` on a captured name)

**Agent: focused-task-implementer.** An **accidental gap**, small fix. Today a
closure body can *read* a capture but not *write* it: `fn-rewrite-captures`
rewrites a captured name to a field **read** (`(. self f)` for vfn/mfn,
`(deref (. self f))` for cfn) and special-cases `.`/`.&`/`.set!`/`addr-of` — but
**not** plain `set!`/`inc!`/`dec!`. Those fall into the generic "rewrite every
argument" branch, so `(set! n v)` becomes `(set! (. self n) v)`, and `emit-set`
(`nucleusc.nuc` ~4529, *"target must be symbol"*) rejects it. Two expectations
break on this one missing rewrite:

- **Stateful `vfn`/`mfn` closures** — the canonical accumulator/counter. The
  runtime machinery is already present: `invoke`'s `self` is `(ref Env)`, so an
  env field *is* mutable and a mutation would persist across calls.
- **`cfn` write-back** — a by-reference closure that can only read its referents
  is half a by-reference capture; `set!` through the captured reference is the
  defining capability.

**Read (scoped):** `fn-rewrite-captures` (`nucleusc.nuc` ~3218 — the bare-symbol
case ~3222 and the `.set!` case it already special-cases); `emit-set` (~4525);
`emit-inc`/`emit-dec`/`emit-inc-dec` (~4642–4671) — `inc!`/`dec!` are
**special-form emitters, not macros over `set!`**, so they reach the rewrite with
their own heads and each need handling; the cfn pointer-field convention in
`fn-emit-env-value` mode 2 (~3661).

**Build:**
1. In `fn-rewrite-captures`, special-case a head of `set!`/`inc!`/`dec!` whose
   target is a captured name `c` (mirror the existing `.set!` special case):
   - **vfn/mfn (mode 0/1):** the env field holds the value, so rewrite
     `(set! c v)` → `(.set! self c v)` (a field store) and recurse on `v`;
     `(inc! c)`/`(dec! c)` → the field-store equivalent. The mutation lands in the
     env field and persists across `invoke` calls.
   - **cfn (mode 2):** the env field holds a *pointer* to the original local
     (the read rewrite is `(deref (. self c))`), so **store through that pointer**
     — write `v` at the address `(. self c)` (mirror the deref-read with a
     deref-write / `ptr-set!`). This is true by-reference write-back; keep the L1
     store-sink checks so writing a tainted value is still rejected.
2. A `set!`/`inc!`/`dec!` whose target is **not** a capture (a closure-local
   `let` binding or param) stays untouched — it already rewrites correctly as an
   ordinary form.

**Done when:** an inline `mfn` accumulator that mutates a captured cell across
the calls a combinator makes works (e.g. `(reduce (mfn (acc:i32 x:i32):i32
(inc! seen) (+ acc x)) 0 r)` leaves `seen` = element count); with CE-1, a
`let`-bound stateful closure called repeatedly returns 1, 2, 3, …; a `cfn` writes
back through a captured reference and the enclosing scope observes the mutation;
`set!` on a non-captured closure-local is unaffected. **`make bootstrap`
byte-identical** (additive — no existing closure mutates a capture).
→ build-test-runner.

---

## CE-3 — Owning-closure export (return an owning closure by value)

**Agent: systems-impl-engineer.** A feature epic. Lifts the two pre-existing
compiler limitations that gate *returning an owning closure by value out of its
creating scope* — the `mfn`-export / `with`-drop case the lambda design
headlines, currently IR-level-verified only.

**Why it is separate from CE-1.** A closure value is `(ref Env)`. For
**bind/call/pass-down**, `with-drop-method` (`nucleusc.nuc` ~2808) already arms a
drop for any `(ref Struct)` whose pointee conforms to `Drop`, and the heap-vs-stack
split does the work: a **cfn** env is **heap-allocated** through its handle
(`fn-emit-env-value` mode 2) so its `(ref Env)` env-free drop fires via the
existing `TY-PTR` path; a **vfn/mfn** env is a **frame `alloca`** (mode 0/1), so
its `(ref Env)` binds/calls/passes-*down* fine but **cannot be returned** (L1
rejects the frame escape). Returning an owning closure therefore means it must
leave the frame **by value** as a `TY-STRUCT`, which is exactly the path the two
limitations block.

**Read (scoped):** `emit-struct-ret` (`abi.nuc` ~241) and its sibling arg path
`abi-arg-frag` (~280); the `return` callers (`nucleusc.nuc` ~4185, ~6162);
`with-drop-method` (~2808, the `TY-PTR` early-return gate ~2810) and its arming
site (~4287); `type-conforms-drop` (`generics.nuc` ~2082); `emit-move` (~4079).

**Build:**
1. **(b) by-value struct return/passing:** move `emit-struct-ret`'s
   `store ptr`/`sret` to a typed `memcpy` across the MEMORY/COERCE1/COERCE2
   branches, and the symmetric argument path.
2. **(c) `with`-drop arming:** add a `TY-STRUCT` branch to `with-drop-method`
   mirroring the existing `TY-PTR`-elem logic, handle alloca-slot vs value, and
   update the autofree/union guards. **This branch does double duty** (see the
   `with-drop`↔`type-conforms-drop` inconsistency in the risk note): arming
   `owns=1` for a struct-value `with`-binding is also what lets `emit-move`
   consume a struct-value `Drop` capture into an `mfn` (today only `TY-PTR`
   `with`-bindings reach `owns=1`, so a struct-value capture can't be moved at
   all). Verify both consumers — a returned-by-value owning closure *and* an
   `mfn` moving a struct-value capture out of a `with`.

**Done when:** the design's headline `mfn`-export case runs end-to-end — an `mfn`
created inside a `with`, **moving** a struct-value `Drop` binding in, may be
returned by value, the move consumes the source (later use → use-after-move), and
the resource drops at the returned closure's eventual scope with no double-free;
a `with`-bound owning struct value also drops correctly. (Today verified only in
two separate halves — move-disarm on a `ptr:Res`, synthesized field-drop on a
`let`-bound struct — because (b)/(c) are unfixed; landing both joins them.)
**Controlled refresh allowed (ABI drift); boot must re-converge.**
→ build-test-runner.

> **Risk — `with-drop`↔`type-conforms-drop` inconsistency.** `emit-move` needs
> the source `owns=1`, but only `TY-PTR` `with`-bindings reach `owns=1`
> (`with-drop-method` ~2808); a synthesized field-drop needs the env field to be
> `type-conforms-drop`, which only fires for `TY-STRUCT`/`TY-UNION`
> (`generics.nuc` ~2082). So today **move-and-consume and synthesized-drop are
> mutually exclusive**: a moved `ptr:Res` field gets no env drop (leak), and a
> struct-value `Drop` capture has `owns=0` so it can't be moved at all.
> *Mitigation:* (c)'s `TY-STRUCT` branch resolves it for genuine (struct-value)
> owning closures — once struct-value `with`-bindings arm `owns=1`, the move path
> and the already-`TY-STRUCT`-aware `type-conforms-drop` align. The `ptr:Res`
> (raw-pointer) case stays unhandled and is not a genuine `Drop`-typed owning
> closure (out of scope). Gate on the `mfn`-export "done when", which exercises
> both halves together.

---

## CE-4 — Storable closures (design exploration — not yet scheduled)

This explains **why a closure cannot be stored** (in a `Vector`, a struct field,
or returned as a heterogeneous value) today, and the **options** for changing
that. It is a design note, not a build order — no agent assignment yet.

### Why closures aren't storable now

Every capturing closure has a **distinct, anonymous, monomorphic** type.
`fn-make-env-struct` mints a fresh env struct `__vfn_env_N` per closure literal
(counter `g-vfn-env-id`); the value of a `(vfn …)`/`(mfn …)`/`(cfn …)` is a
`(ref __vfn_env_N)`. Three properties of that type **each independently** block
storage:

1. **Anonymous.** The env struct name is compiler-minted and never appears in
   source, so there is no spelling to put in a *type position* — a struct field
   type, a `(Vector T)` element type, a `defn` return type. (CE-1's inference
   dodges this for a `let`/`with` *binding* by copying the init's concrete type;
   it never hands the user a *name* to write elsewhere.)
2. **Per-site, not shared.** Two closure literals get two env structs even when
   structurally identical (each mints a fresh `N`). There is no single type that
   "every arity-1 `i32→i32` closure" shares. L7's `derive-closure-conformance`
   matches a closure's `invoke` against `UnaryFn`/`FoldFn` *at a use site* — that
   is structural conformance for one generic call, **not** a shared, nameable,
   storable type.
3. **Value-typed, size varies by capture.** The env is an inline by-value struct
   whose size is the sum of its captures (a POD `vfn` over one `i32` is 4 bytes;
   one over three pointers is 24). A `Vector` slot or a fixed struct field needs a
   single uniform size, which a family of differently-captured closures lacks.

The through-line: **storage needs a written, fixed-layout type; a capturing
closure has an unwritten, per-site, variably-sized one.** What *does* work today
follows directly — an inline closure argument is monomorphized into the generic
combinator (the env type is a resolved type parameter, never named, zero-cost),
and a `let`-bound closure (CE-1) is one concrete type at one frame slot. Both are
*one concrete type at one site*; storage is the moment you need *many* concrete
types behind *one* slot.

### What is already storable

A non-capturing **`fn`** decays to a real function pointer; function-pointer
types are interned and nameable (`__fnty_N`, `type-mangle.nuc`) and fixed-size,
so a `(Vector fnptr)` or a struct field of fn-pointer type works **now** — for
the *stateless* handler case. The gap is purely about carrying *captured state*
behind a uniform slot.

### Options for storable stateful closures (cheapest/narrowest first)

- **Option 0 — `fn` + explicit state argument.** Keep the callback a bare `fn`
  and thread state as an ordinary parameter the caller passes at each call (the C
  `(callback, void* userdata)` idiom). Zero new machinery, fully storable,
  C-compatible; loses closure ergonomics and makes the caller route the state.
  *Covers many "table of handlers" cases today.*
- **Option 1 — Closed union of known closure types.** When the stored set is
  finite and known, wrap them in a `defunion` (one arm per concrete env type, or
  a hand-written function object), store the union, dispatch by `match`.
  Type-safe, no heap if envs are by-value, no new feature — but closed-set only,
  verbose, and it leans on the by-value-struct-in-aggregate ABI (the path CE-3
  fixes).
- **Option 2 — Homogeneous monomorphic storage.** Allow the anonymous env type
  to be *named* (a type alias minted at the literal, or a `typeof`-style
  spelling), enabling a `(Vector ThatEnv)` of closures from the *same* literal
  (e.g. accumulated in a loop). Zero-cost and monomorphic, but only homogeneous —
  different literals still differ — so narrow reach; mostly a stepping stone.
- **Option 3 — Type-erased boxed closure `(BoxedFn (params…) ret)` (the real
  feature).** *Now committed and superseded by
  [type-erasure.md](type-erasure.md) — the shared fat-pointer machine that
  realizes this option and the deferred Stage 9 `(dyn Protocol)` as one
  mechanism.* A nameable, fixed-size, signature-parameterized handle that erases
  the concrete env: a two-word fat pointer `{ data: ptr, vtable: ptr }` where
  `data` is the heap-allocated env and `vtable` is a static per-env-type record
  `{ invoke, drop, clone? }`. Assigning any closure into a `BoxedFn`-typed slot
  heap-allocates (or moves) the env through an allocator, points at the env's
  vtable, and yields a uniform owning value. `BoxedFn` conforms to `Drop` (free
  the env via `vtable.drop` + the stored allocator) and to the `Fn` protocols
  (forward through `vtable.invoke`), type-checked by its signature parameter — so
  `(Vector (BoxedFn (i32) i32))`, a struct field of that type, and a `(BoxedFn …)`
  return all just work.
  - *This is the `Box<dyn Fn>` / `std::function` analog* — the genuinely
    first-class answer.
  - *Cost:* an indirect call + a heap allocation per box — exactly the
    type-erased, allocating path lambda.md says to keep out of hot loops. That is
    acceptable precisely because *storage is never the zero-cost monomorphized
    case*; the hot path keeps inline/`let`-bound monomorphic closures (Option 0 /
    CE-1), and `BoxedFn` is opt-in for genuinely heterogeneous storage.
  - *Representation sub-choice:* the two-word fat pointer + **static per-type
    vtable** amortizes the vtable across instances and keeps the value
    pointer-pair-sized (cache-friendly in a `Vector`); a three-word inline
    `{ env, invoke, drop }` is simpler but fatter and re-stores the thunks per
    value. **Recommend the fat-pointer + vtable.**
  - *New machinery:* a `BoxedFn` parametric type; vtable synthesis per concrete
    env type (the `invoke`/`drop` thunks already exist as the synthesized methods
    — the box just takes their addresses); a boxing coercion at assignment into a
    `BoxedFn` slot; and `Drop` + `Fn`-protocol conformance for the box. Builds on
    **CE-3** (the env must travel by value to the heap, so the by-value-struct ABI
    fix is a prerequisite).

### Recommendation

Document **Option 0 + `fn`-pointers** as the supported storage idiom *now* — they
cover the stateless and explicit-state cases, and the compiler refactor never
stores a closure (combinators consume them inline), so it is unblocked. Treat
**Option 3 (`BoxedFn`)** as the committed *future* direction for first-class
storable closures, gated behind CE-3 and explicitly **not** part of the Stage 13
dogfooding. Options 1–2 remain as ad-hoc user-space patterns, not language work.

---

## Known soundness gap — `cfn`-of-a-pointer escape imprecision

Independent of the enhancements above and tracked here so it is not mistaken for
a design choice. `emit-addr-of` (`nucleusc.nuc` ~2437) excludes `TY-PTR` bindings
from frame-taint (the "a pointer loaded out of a frame-local may legitimately be
returned" imprecision boundary). A consequence: a `cfn` capturing a
**pointer-typed local** by reference stores `&local` (the slot address) but
inherits **no** frame region, so the closure **compiles and can be returned** —
dangling, because the env then holds the address of a dead frame slot. This is
the deferred **nested-region precision** from lambda.md §Deferred, surfacing
through closures. A full fix is per-binding region comparison (vs. the current
function-frame boundary); a cheaper interim is to taint `addr-of` of a *named
local* even when its type is `TY-PTR` (distinguishing it from a pointer *loaded
out of* a frame-local, which stays exempt). Out of scope until it bites; recorded
so it is on the list.

## Close-out checklist (required by AGENTS.md)

- After **every** implemented enhancement: `make test` + `make bootstrap` green,
  compiler compiles itself — via **build-test-runner**.
- CE-1 and CE-2 stayed byte-identical (no refresh); CE-3 re-converged the boot
  after a justified controlled refresh.
- Update [progress.md](progress.md) with a per-enhancement row (CE-1 … CE-3) and
  note the storability decision (CE-4) and the `cfn`-of-pointer gap.
- Update language docs: `docs/special-forms.md` (mutable capture; the four forms'
  binding/storage story), `docs/generics.md` (if CE-4 lands, `BoxedFn`).
