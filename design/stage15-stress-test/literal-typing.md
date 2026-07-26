# W2 — `node-type` ↔ `emit` literal-operand lockstep

**Findings:** §1.2 (invalid IR from `(* <literal> (as i64 X))`), §1.3 (operand
order changes signedness inference), §3.1 (`defconst` folds as signed `i32`
unlike the literal it stands for), §3.6 (float literals do not adapt to `f32`).

**Goal:** a binary operator's *statically inferred* type equals the type it
actually emits. One root cause covers §1.2 and §1.3; §3.1 and §3.6 are the same
theme (a name or a literal carrying a type it should not) and are cheap to fix
alongside.

---

## Ground truth

### The root cause is one line

`src/generics.nuc:3814` `node-type-call`, intrinsic-binop branch:

```lisp
(let (bop:ptr:BinOp (unsafe/cast ptr:BinOp (m0 binop)))
  (when (!= (bop is-cmp) 0) (return ty-i1))
  (return (node-type (node-at n 1) scope)))     ; ← the type of operand 1 ONLY
```

So `node-type` of a binop is "whatever the **first** operand types as". Meanwhile
`emit` unifies both operands.

### What emit actually does

`src/nucleusc.nuc`:

* `1633` `is-untyped-int-literal` — "true if a node denotes an untyped integer
  literal, so it may adapt to the type of the other operand".
* `1782` `binop-coerce` — the widen/adapt tier: untyped int literals plus
  int/float widening. Returns null when no adaptation applies.
* `1904-1908` in `emit-binop-vals` — calls `binop-coerce` and replaces `av`/`bv`
  with the adapted pair.
* `1952-1953` — *after* adaptation, `(!= (is-unsigned (av type)) (is-unsigned (bv
  type)))` dies `%s: mixed signed/unsigned operands — use explicit cast`.
* `1011-1024` `emit-int` (Stage 14 LW-4) — emits an integer literal at its
  truthful width and sets `is-lit 1` on the `Val`, which is the marker
  `binop-coerce` keys on.

`node-type` (`src/generics.nuc:3883`) types `NODE-INT` as `ty-i32` (or `ty-i64`
if out of i32 range) and `NODE-FLOAT` as `ty-f64`, with an explicit LW-4 lockstep
comment. That part is fine in isolation — the bug is that the *binop* node-type
never consults `binop-coerce`'s logic.

`conventions.md` already documents this exact hazard class ("`node-type` mirrors
`emit-node`"). This is a lockstep violation of the kind the repo already knows
about; W2 is closing one instance of it.

### Why it produces two different symptoms

* **§1.2, invalid IR.** `(malloc (* 4096 (as i64 (sizeof i32))))`. Emit widens the
  literal and produces `i64`. `node-type` says `i32` (operand 1 is the literal).
  The argument-coercion machinery trusts `node-type`, sees `i32` where `i64` is
  wanted, and inserts a `sext i32 → i64` on a value that is already `i64` →
  `'%t4' defined with type 'i64' but expected 'i32'` at IR-parse time.
* **§1.3, spurious mixed-sign error.** `(> tspan (* 2 clipangle))` with both
  `ui32`. `node-type` of the inner `*` says `i32` (from `2`), so the comparison
  is typed `i32` vs `ui32` and dies at `1953` — even though emit would have
  produced `ui32` on both sides. Reordering to `(* clipangle 2)` makes
  `node-type` return `ui32` and it compiles.

Same defect, opposite direction: once node-type says `i32` the downstream either
inserts a bogus cast or rejects a valid program, depending on which consumer
looks first.

---

## Design

### W2a — unify operand types in `node-type-call` (the fix)

Replace "return operand 1's type" with the same unification `binop-coerce`
performs. The cleanest form is to **extract the type-level half of
`binop-coerce`** into a shared helper both sides call, so the two cannot drift
again:

```
binop-result-type(a-type, b-type, a-node, b-node) -> ?Type
```

with the rule, mirroring `binop-coerce` exactly:

* If one operand is an untyped int literal (`is-untyped-int-literal`) and the
  other is typed → the typed one's type.
* Both untyped literals → today's default (`i32`, or `i64` if either does not fit
  — match `emit-int`'s LW-4 behaviour, do not invent a new rule).
* Both typed → the widening result, or null if irreconcilable (node-type is
  allowed to not know; it must **never** die — see the LW-2 comment already in
  `node-type-call`).
* Comparison ops still return `ty-i1` before any of this.

Then `node-type-call`'s intrinsic branch calls the helper, and `binop-coerce`'s
value-level path is refactored to use it for the type decision. **Do not
duplicate the rule in two places** — a copy is how this drifted in the first
place.

Float widening is part of `binop-coerce` today; keep it in the shared helper so
`(+ 1.0 x:f32)` behaves consistently (see W2d).

### W2b — `defconst` folding (§3.1)

A bare literal `512` adapts to either operand; `(defconst K 512)` resolves to a
concretely-typed `i32` and does not. `(<= ans K)` with `ans:ui32` dies where the
inline literal compiles. Naming a constant should not change how it types.

Investigate `emit-defconst` (`src/nucleusc.nuc:7459`) and how a `defconst`
reference is emitted. The intended behaviour: **a `defconst` bound to an integer
literal should behave like that literal** — i.e. carry "untyped int literal"
provenance so `is-untyped-int-literal` (or an equivalent predicate on the *symbol
reference*) accepts it, and it adapts at the use site.

Constraints:

* Constants that do not fit `i32` are stored `i64` today and need `unsafe/cast`
  rather than `as` (the port wraps `ANG180`/`ANG270` in helpers because of this).
  Whatever provenance mechanism is chosen must carry the *value*, not just a flag,
  so a large constant still types as `i64` and a small one adapts.
* An explicitly-typed constant must keep its type. Today `defconst` takes no type
  annotation at all (§3.2, W4), so this is only a question if W4's diagnostic work
  leads to *accepting* an annotation. Coordinate: if W4 makes
  `(defconst K:i32 2)` a hard error, W2b is unconstrained; if W4 makes it *work*,
  an annotated constant must not adapt.
* Bit-shift counts and return/assignment positions already work; do not regress
  them.

If the provenance plumbing turns out to be invasive, the acceptable smaller fix is
to make the diagnostic actionable (name the constant and both types, suggest the
cast) and record §3.1 as deferred with that reasoning. **Do not** fix it by making
comparisons silently sign-reinterpret.

### W2c — `defvar` initialized from a `defconst`/`defenum` (§3.8)

Already works; the docs imply otherwise ("init must be a literal"). Documentation
only: state that the restriction is about *expressions*, and that a named
constant or enum member is the preferred spelling. Fold into W4's doc pass if
convenient.

### W2d — float literals in `f32` context (§3.6)

`(let (alpha:f32 0.0) ...)` dies `let: init type mismatch`; every float constant
in `f32` code must be written `(unsafe/cast f32 1.0)`. Integer literals adapt;
float literals do not. That asymmetry is the finding.

Decide between:

* **Adapt float literals to an `f32` target** the way int literals adapt — the
  consistent choice, and it composes with the shared helper from W2a.
* **Leave it and document it**, on the grounds that silent double-rounding
  (decimal → f64 → f32) is a real hazard.

Choice: adapt, because the hazard already exists — users write
`(unsafe/cast f32 3.14)` today and get exactly the same double-rounding. Making
it implicit does not add a rounding step; it removes a wart. The port confirmed
`(unsafe/cast f32 3.14)` equals C's `3.14f` for its constants, and that
`f32` arithmetic is otherwise bit-exact with C `float` — so the target semantics
are known-good and testable.

`binop-coerce`'s float-widening path is the place, and the accept
test is a `float`-typed DSP kernel matching C output bit-for-bit.

---

## Verified repros (as of this doc)

```lisp
; §1.2 — invalid IR
(defn main ():i32 (let (p:ptr (malloc (* 4096 (as i64 (sizeof i32))))) (return 0)))
```
→ `failed to parse generated IR: … '%t4' defined with type 'i64' but expected 'i32'`
→ `%t5 = sext i32 %t4 to i64`

```lisp
; §1.3 — operand order
(defvar cl:ui32 5)
(defn main ():i32 (let (t:ui32 9) (when (> t (* 2 cl)) (return 1))) (return 0))
```
→ `:2: error: >: mixed signed/unsigned operands — use explicit cast`
(and compiles if written `(* cl 2)`)

---

## Accept criteria

* Both repros above compile and run, and `(* 2 cl)` / `(* cl 2)` are
  indistinguishable in behaviour and in emitted IR.
* A test matrix over `{literal-first, literal-second, both-typed, both-literal}`
  × `{i32, i64, ui32, ui64}` × `{arith, comparison}`, asserting compile success
  and the expected result type. This is the regression that stops the drift
  recurring; put it in `tests/` with an expected-output fixture.
* The type rule lives in **one** function called by both `node-type` and emit.
* **`make bootstrap` byte-identical.** The compiler's own source compiles today,
  so W2 must not change its IR — the fix only affects programs that previously
  errored or mis-emitted. A non-empty diff needs investigating, not
  `make update-bootstrap`.
* `conventions.md`'s node-type↔emit note gains a line pointing at the shared
  helper as the way this class of bug is now prevented.
* W2b and W2d each land, or are recorded here as deferred **with the reasoning
  and the fallback that was done instead** (better diagnostic / doc note).
