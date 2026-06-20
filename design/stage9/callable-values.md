# Stage 9 — Callable values (non-function call position)

#### Designer

The next step in stage 9: define what happens when a **non-function** sits in the
call position — `(x …)` where `x` is not a function. The **default for a struct
should be member access**; the programmer should be able to **override or add to**
that using the polymorphism mechanisms (overloaded `defn`, protocols, bounded
generics). Example: a type implementing a `Seq` protocol, in the call position with
an integer argument, returns the element at that index.

Hard requirement, as everywhere in stage 9: **no runtime overhead when types are
known at compile time.**

#### Robot — design

This is the **committed design**. It is a thin layer over the rungs-1–4 dispatch
substrate plus the Stage 9 *extensions* — blanket protocols, symbols-as-values, and
operators-as-functions — whose **engine pieces are specified in
[polymorphism.md §10](polymorphism.md)**. This doc owns only the *call-position*
semantics; it references §10 for the mechanisms it builds on.

The earlier "field name is syntax vs. index is a value" crux (§2) is **resolved** by
treating field selectors as symbol *values*: dispatch becomes uniform, and member
access is the `Struct` blanket protocol's built-in method, not a hardcoded syntactic
special case.

## 1. The call position today

A list head goes name → code through one funnel:

- **`emit-list` (src:3699) requires the head to be a symbol** (src:3703-3704). An
  arbitrary-expression head — `((mk) 3)` — is rejected up front.
- The symbol is matched **macro table → special forms → `emit-dispatch`** (src:3749).
  `emit-dispatch` (src:3685) tries the generic registry (`generic-lookup`, src:1438),
  then falls back to `scope-lookup` (src:3694) and `emit-call`.
- **The "not a function" wall.** `emit-call-with-args` (src:3113) emits the args, then
  at src:3166 checks `(. ft kind) != TY-FN` and **dies `"not a function: %s"`**. This
  is where a struct-typed variable in head position dies today, and it is the single
  hook the feature attaches to.

Two existing forms already do the two things "calling a value" should mean:

- **Member access** — the `.` special form (`emit-field-get`, src:2710). Its second
  operand is a **literal field-name symbol**; it checks the operand is a
  pointer-to-struct (src:2716-2718) and emits `getelementptr` + `load`. Zero overhead.
- **Indexing** — `aref` (src:2811): `(aref p i)` on a typed pointer with an evaluated
  integer.
- **Function-pointer calls** — `funcall` (src:2949): a `TY-FN` *value* is callable only
  through this explicit form, never by sitting in head position.

The dispatch engine is reused wholesale: `g-generics` / `generic-resolve` (src:1727) /
`generic-find-method-exact` (src:1589); protocols + conformance (`g-protocols`,
`g-conformances`, `emit-extend` src:2600); the non-emitting `node-type` pass (src:1052,
`node-type-call` src:1023). The feature desugars into these, it does not parallel them.

## 2. The design at a glance

`(callee a b …)` where `callee` resolves to a non-function value of static type `T`
**desugars by the (sole) argument type** into one of two reserved generics:

| call | argument | desugars to | meaning |
|---|---|---|---|
| `(s rad)` / `(s 'rad)` | a **symbol** (incl. bare-field sugar) | `(get s 'rad)` | member access |
| `(s 3)` | anything else (integer, …) | `(invoke s 3)` | general call / index |

- **`get`** is the field-access generic. Every struct conforms to the **`Struct`
  blanket protocol** ([polymorphism.md §10.1](polymorphism.md)), whose required `get`
  is supplied by a built-in **intrinsic** that emits the same GEP+load as `.` — so
  member access is the struct default with **zero overhead** and is **overridable**
  (a user `get` method out-ranks the intrinsic).
- **`invoke`** is the general-call generic. A type "becomes callable" by defining
  `invoke` methods; the `Seq` example is just an `invoke` method for an integer
  selector.

Because a selector is now a *value*, the old §2 crux (a field name is unevaluated
syntax) is gone: `get`/`invoke` dispatch on argument *types* like any other
multimethod. The only subtlety is keeping the common `(s field)` case zero-overhead,
handled by a literal-symbol fold (§3.2).

## 3. Dispatch model

### 3.1 Desugar by argument type

At the "not a function" hook (src:3166) and the `emit-dispatch` fallthrough (src:3685):
a non-`TY-FN` resolved head with a **single symbol-typed argument** ⇒ `get`; otherwise
⇒ `invoke`. Both then resolve through `generic-resolve`/`emit-generic-call` (src:3661)
exactly like a normal overloaded call. The symbol-vs-other test is a minimal,
type-based two-way split — not a general "argument shape" table.

### 3.2 Symbols as values — and keeping the common case free

A field selector is an **interned symbol value** (`NODE-SYM`; identity by pointer,
docs/builtins.md §Symbols). Two cases:

- **Literal symbol** (`(s 'rad)`, or the bare `(s rad)` sugar): the compiler has the
  symbol and `T`'s layout at compile time, so it **constant-folds to a static
  `getelementptr` + `load`** — byte-identical to `.`, zero overhead, fully typed
  (result is that field's type). This is a **front-end fold**, not an LLVM
  optimization: the dynamic path calls into the runtime intern table, which LLVM
  cannot see through.
- **Computed symbol** (`(get s some-sym)`, `some-sym` a variable/expression): the
  **callee's type is still static**, so no RTTI — only the *field* is dynamic. The
  compiler emits a branch comparing `some-sym` against `T`'s compile-time field
  symbols (pointer identity), each arm a static GEP. Bounded `O(fields)`, opt-in,
  pay-for-use.

**Typing gate (honest limit).** A literal selector has a precise static result type; a
*computed* selector does not — fields differ in type, so the result type is
well-defined only for a **homogeneous** struct, or via a **type-erased** result
(`dyn`, deferred). So literal-symbol field access ships now; **computed (reflective)
field access is restricted to homogeneous structs or deferred behind `dyn`** — the
same wall as B2 returns (polymorphism.md §8.5).

### 3.3 Member access via the `Struct` blanket protocol

Member access is *not* a hardcoded fallback; it is the `get` generic's built-in
**intrinsic method** for "any struct + symbol selector," named by the **`Struct`
blanket protocol** (polymorphism.md §10.1). `Struct` is a *pure predicate* with
automatic conformance for every struct — it **requires** `get` and **provides
nothing**; the intrinsic satisfies the requirement. This is the §8.1
implementation-vs-predicate split: the protocol owns no code.

The payoff over a syntactic fallback: member access is **overridable**. A concrete
user `get` (or `invoke`) method for a type sits at tier 0 and out-ranks the blanket
intrinsic (concrete-beats-generic, polymorphism.md §8.6).

### 3.4 Indexing and the `Seq` / `Callable` library protocols

A non-symbol selector routes to `invoke`. Indexing is just an `invoke` method:

```lisp
(defstruct Vec data:ptr:i32 len:i32)
(defn invoke:i32 (self:ptr:Vec i:i32) (return (aref (. self data) i)))

(vec 3)    ; ⇒ (invoke vec 3)  → element access
(vec len)  ; ⇒ (get vec 'len)  → the length field (member access)
```

`Seq` / `Callable` are ordinary **library** protocols over `invoke`, used to *name and
check* the capability:

```lisp
(defprotocol Seq (invoke:i32 (self:ptr:Self i:i32)))   ; indexable by i32
(extend Vec Seq)
```

**Element type fixed in these protocols.** `IntIndexable`/`Call` fix concrete element
and argument types. The parametric rung has shipped (Stage 11 parametric structs +
associated types A0–A4); element-generic function-object protocols are now available
as `(UnaryFn Arg Ret)` / `(FoldFn Acc Elem)` in `lib/iterator.nuc`. The fixed-type
protocols remain for existing users and are planned for removal in C2.5 (see
`design/stage11/cleanup2.md`). The call mechanism does not depend on them — `(vec 3)`
works from the `invoke` method alone.

### 3.5 Resolution, precedence, and the bare-symbol rule

- **Precedence:** user `get`/`invoke` methods (tier 0) ≫ the `Struct`/index built-in
  intrinsics (lowest tier). Member access is overridable; indexing is purely
  user-supplied.
- **Bare symbol = quoted-field sugar.** `(point x)` ≡ `(point 'x)` ≡ `(get point 'x)`
  when `x` names a field of `point` — preserving the overview's
  member-access-by-call ergonomic. To force value dispatch on a same-named variable,
  write `(invoke point x)` explicitly. Field interpretation wins because it does not
  depend on what is in scope (most predictable).

## 4. Scope decisions

### 4.1 Head generality

**First cut: symbol head only** — change only what happens when `scope-lookup` finds a
*value* (non-`TY-FN`). Covers every motivating example (a variable holding a
struct/seq pointer). **Planned next: arbitrary-expression heads** — relax src:3703-3704
so `((mk-vec) 3)` and `(@p 3)` work (emit the head, read its type, route the same way);
macros/special forms are unaffected (they only matched symbol heads).

### 4.2 Folding `funcall` into the call position

Once §4.1's arbitrary-head path exists, `(fp a b)` for a `TY-FN` *value* lowers to
today's `funcall` automatically, retiring the explicit `funcall`/`funcall-ptr-*` family
as a *surface* (kept as the implementation). Planned with §4.1.

### 4.3 Assignment through the call position

`(s field)` returns the loaded value (like `.`). Assignment keeps `.set!` / `aset!`. A
future `set!`-place could make `(set! (s i) v)` mean an `invoke-set!` method, but that
wants the generic `set!`-place work (polymorphism.md §4) and is **out of scope** here.

### 4.4 Struct-pointer + integer selector

A `ptr:Struct` head with an integer selector is **unbound unless the type implements an
integer `invoke`** (i.e. conforms to `Seq`). It does *not* default to `aref`
(C array-of-structs indexing), which would be a surprising implicit behaviour; a struct
that wants indexing says so with a `Seq`/`invoke` impl. Plain non-struct typed pointers
keep `aref` as their integer behaviour.

## 5. Hook points (current line numbers)

- **Desugar / dispatch:** the not-a-function wall (src:3166) and `emit-dispatch`
  (src:3685) — detect a non-`TY-FN` head; symbol-typed sole arg ⇒ `get`, else
  ⇒ `invoke`; resolve via `generic-resolve` (src:1727) / `emit-generic-call` (src:3661).
- **`get` struct intrinsic:** factor the field-index lookup + GEP/load out of
  `emit-field-get` (src:2710); literal selector ⇒ static GEP (the const-fold);
  computed selector ⇒ branch over the struct's interned field symbols.
- **`invoke`:** ordinary generic resolution; no special emission.
- **Type pass:** `node-type-call` (src:1023) and the `node-type` tail (src:1101) mirror
  the desugar — returning the `get` field type (literal) or the `invoke` method's
  `ret-type`. Bootstrap enforces no drift (rung-3 invariant).
- **Reserved names:** seed `get` and `invoke` in `init-generics` / `finalize-generics`
  (src:1680); `get` carries the `Struct` blanket intrinsic.
- **Blanket conformance:** `Struct` via the `g-blanket` mechanism (polymorphism.md
  §10.1).
- **No new `.nuch` form** — `get`/`invoke` overloads and `Seq`/`Callable` export through
  the existing `defmethod` / `defprotocol` / `extend` machinery.

## 6. Zero-overhead & C-ABI

Every path resolves at compile time to: a literal-symbol `get` (≡ `.` GEP+load, free), a
computed-symbol `get` (a bounded branch + GEP, only when you ask for it), or an `invoke`
that is a direct `call` to a resolved method (LLVM may inline). No dispatch object, no
vtable. `get`/`invoke` are ordinary overload sets, so their C-export story is §5/§9.4 of
polymorphism.md (solitary → unmangled; overloaded → mangled). `defprotocol`/`extend` emit
no code. Nothing here touches the C ABI beyond what overloaded `defn` established.

## 7. Staging (the call-position rung)

Slots after blanket protocols land (polymorphism.md §10.4 step 3 — needed for the
`Struct` default); benefits from operators-as-functions (step 2) but does not block on
it. Each step keeps `make test` / `make bootstrap` green.

1. **Hook + desugar.** Detect a non-`TY-FN` head; route symbol-arg ⇒ `get`,
   else ⇒ `invoke`; resolve via the engine; mirror in `node-type-call`. Ships
   user-defined `invoke` (indexing/`Seq`) and user `get`.
2. **`Struct` member-access default.** The `get` struct intrinsic with the
   literal-symbol const-fold (depends on blanket protocols). Ships the struct default.
3. **Computed-symbol field access** (runtime branch, homogeneous typing gate) — or defer
   behind `dyn`.
4. **`Seq` / `Callable`** library protocols + `examples/callable.nuc` +
   `tests/expected/callable.out`.
5. **Later:** arbitrary-expression heads (§4.1); `funcall` unification (§4.2);
   `set!`-place (§4.3).

## 8. Alternatives considered (rejected / subsumed)

- **Compiler-known method-name per argument kind** (integer→`nth`, string→`get`…): a
  compiler-owned "shape → method" table. **Subsumed** by symbols-as-values + arg-type
  dispatch (§3.1), which needs no such table.
- **Type-keyed macro call handlers (`defcall`)**: a per-type handler over *unevaluated*
  syntax. Its one unique power — overriding member access and per-type *syntactic* DSLs
  (keyword args) — is partly granted by the overridable `Struct` intrinsic (§3.3);
  **deferred** as a future escape hatch, since it needs new type-aware-macro machinery
  and pushes semantics into userland.
- **Value-dispatch only, keep `.` for fields**: smallest, but fails the kickoff's
  "default for a struct is member access." **Rejected.**
- **Reader-level rewrite**: impossible — the reader has no types and cannot know `x` is a
  non-function. **Rejected.**

## Open questions

1. **One generic or two?** Adopted: two — `get` (symbol selector → field) and `invoke`
   (general). Alternative: a single `invoke` dispatching on symbol-vs-other arg type
   (no `get` name). Confirm two.
2. **Bare-symbol rule (§3.5).** Confirm `(point x)` is quoted-field sugar (field wins
   over a same-named variable), forcing `(invoke point x)` for value dispatch.
3. **Struct-pointer + integer (§4.4).** Confirm *unbound unless `Seq`* (recommended) vs.
   defaulting to `aref`.
4. **Computed-symbol field access (§3.2).** Ship restricted to homogeneous structs,
   defer entirely behind `dyn`, or out of scope for now?
5. **Reserved names.** `get` / `invoke` vs `apply` / `call` / `$`; `Seq` (+ `Callable`?)
   as the standard protocol names.
6. **Head generality / `funcall` (§4.1–4.2).** Arbitrary-expression heads and `funcall`
   unification in this rung, or a follow-up?

#### Designer

1. Two. `get` as a function is desirable to let users customize field access behavior on their own types cleanly.
2. Yes, allow the sugared form for now.
3. Don't default to `aref`.
4. Restrict for now, defer `dyn` to stage999.
5. `get` for field access, `invoke` for callables. `Seq` and `Call` for the protocol names.
6. `funcall` can probably become compiler-internal. Do arbitrary expression heads at this point unless there's a major blocker.

---

## Implementation status — landed (2026-06-08)

All five staging steps (§7) are implemented in `src/nucleusc.nuc`; `make test`
(37 cases, incl. `examples/callable.nuc`) and `make bootstrap` (stage1.ll ==
stage2.ll, byte-identical) are green. This section is authoritative where it
refines the design above.

**Steps 1–2 — desugar + `get`/`invoke` + the `Struct` member-access intrinsic.**
`get` and `invoke` are reserved **special forms** (`emit-get` / `emit-invoke`),
and the non-`TY-FN` head case of `emit-dispatch` routes a value head through the
same `emit-callable-value` desugar, so `(s f)`, `(get s 'f)`, `(s 3)` and
`(invoke s 3)` share one resolution path. A single literal-symbol argument →
`get`; everything else → `invoke`. `selector-literal-sym` detects a literal
selector (a bare `NODE-SYM` or `(quote sym)`); a bare symbol is *always* a field,
never a variable (§3.5), so the routing never depends on scope. Member access is
the `get` generic's built-in intrinsic: the field-index lookup + GEP/load were
factored out of `emit-field-get` into `struct-field-index` / `emit-field-load`,
which the literal `get` path calls directly — **verified byte-identical to `.`**.
A concrete user `get` method (params `(ptr:T, ptr)`) is found by
`generic-find-method-exact` at tier 0 and out-ranks the intrinsic (§3.3/§3.5); the
selector is passed as the interned symbol `Node*`. `invoke` has no default —
resolution goes through the ordinary `generic-resolve`, so a struct pointer with
an integer selector is **unbound unless an integer `invoke` exists** (§4.4: it does
*not* fall back to `aref`).

**Step 3 — computed-symbol field access.** `emit-computed-field` handles an
*explicit* `(get callee expr)` whose selector is a compound expression: a chain of
`select` instructions compares the selector (by pointer identity) against the
struct's interned field symbols to pick an index, then an array-style GEP+load.
Restricted to **homogeneous** structs (all field types `type-eq`) so the result
type is well-defined; a heterogeneous struct is a clear def-time error. `dyn`
(heterogeneous/erased) stays deferred to stage999 per decision 4.

**Step 4 — `Seq` / `Call`.** Ordinary library protocols over `invoke` in
`lib/seq.nuc` (`Seq` = `invoke:i32 (self:ptr:Self i:i32)`, `Call` =
`invoke:ptr (self:ptr:Self arg:ptr)`); they export through the existing
`defprotocol` machinery (no new `.nuch` form). `examples/callable.nuc` +
`tests/expected/callable.out` cover member access by call, `Seq` indexing vs.
member access on one value, a `Call` function object, and a user `get` override.

**Step 5 — arbitrary-expression heads + `funcall` folding.** `emit-list` no longer
requires a symbol head: a non-symbol head (`((mk) 3)`, `(@p 3)`) is emitted once
and routed through `emit-callable-value`. A head whose value is `TY-FN` folds to an
indirect call via `emit-funcall-value` (extracted from `emit-funcall`, which is now
a thin wrapper) — so `(f a b)` works for a local/global fn-pointer variable and the
explicit `funcall` / `funcall-ptr-*` family is **compiler-internal** (still
accepted as a surface). `emit-dispatch` now takes the direct-call path only for a
real function symbol (`is-local = 0`, `TY-FN`); every other head is a value.

**Type pass (no drift).** `node-type` mirrors the desugar: `node-type-get` /
`node-type-invoke` for the special forms, and `node-type-call`'s non-`TY-FN` branch
for the value-head case, all via shared `callable-get-type` / `callable-invoke-type`
/ `callable-value-type`. They mirror only the **exact tier** (a tier-0 user method's
return, or the literal field's type) and return null otherwise, so codegen's own
type stands where the type pass is imprecise — the rung-3 bootstrap invariant holds.

**Deferred (as designed):** `dyn`-typed / heterogeneous computed field access; a
`set!`-place form `(set! (s i) v)` (§4.3, wants generic places); an element-generic
`Seq` (wants associated/parametric types); and cross-unit `get`/`invoke` overload
*merging* (single-unit dispatch and `.nuch` export both work).
