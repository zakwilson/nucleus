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

---

## W2a as built

**Status: done.** `make bootstrap` byte-identical (`stage1.ll == stage2.ll`),
`make test` 235 PASS / 0 FAIL (was 231 before this work). W2b, W2c and W2d
remain open and are unaffected by this change.

### The shared rule and where it lives

```lisp
(defn binop-result-type (at:(raw Type) bt:(raw Type)
                         a-node:(raw Node) b-node:(raw Node)):?ptr:Type
```

**Home: `src/nucleusc.nuc`, immediately above `binop-coerce`.** Both callers:

* `binop-coerce` (same file) keeps only its value-level half — the `type-eq`
  same-type short-circuit, then `binop-result-type` for the whole type decision,
  then `coerce-num-val` on each operand. Its `cond` ladder is gone.
* `node-type-call` (`src/generics.nuc`, intrinsic-binop branch) returns `ty-i1`
  for a comparison as before, then calls the helper with both operands'
  `node-type`s.

`nucleusc.nuc` imports `generics.nuc` and not the reverse, so this is a
"backwards" call — but it is not a cycle and needs no new import. Every `.nuc`
inlines into one translation unit and `prescan-defn-signatures` registers
`nucleusc.nuc`'s own signatures before any form is emitted, so `generics.nuc`
can name a `nucleusc.nuc` function; it already did, for `macroexpand-form`.
Placing the rule beside `binop-coerce` is deliberate: physical adjacency to the
value-level half it was extracted from is the anti-drift device, and both of its
own dependencies (`node-is-int-literal`, `float-width`) live within 100 lines of
it.

### The rule as implemented

Null in either type, or a non-numeric operand → null. Equal types → that type.
Otherwise, in order:

1. Exactly one operand is an untyped **int** literal → the other's type
   (int *or* float; `coerce-num-val` supplies the `sitofp`/`uitofp`).
2. Neither is an int literal, at least one side is a float type, and exactly one
   operand is an untyped **float** literal → the other's type. Ordered *after*
   (1) so `(+ 1.0 2)` still types `f64` (the int literal adapts to the float
   literal's default), and gated on a float operand so `(* n:i32 2.0)` stays the
   existing "mixed float and non-float operands" error.
3. Both typed: int-vs-float → null; `Char` vs non-`Char` → null; two floats →
   the wider; two ints of differing signedness → **null**; two ints → the wider.

Both operands being untyped literals needs no special case: they fall through to
(3), where `emit-int`'s LW-4 widths (`i32`, or `i64` when the value does not
fit) settle it — matching the spec's "do not invent a new rule".

Null is returned, never a `die-at`, for every unreconcilable pair — `node-type`
is allowed to not know, and `emit-binop-vals` still raises the real diagnostic.

### The float outcome (F)

**Landed, in the binop position only.** `(* alpha:f32 2.0)` and `(* 2.0 alpha)`
are both `f32`; previously they widened to `double` and then mis-stored into the
`float` slot (`store float %t5` where `%t5` is `double`). This required a new
`node-is-float-literal` predicate beside `node-is-int-literal`. A float literal
adapts only to a *float* operand — never to an integer one, which stays an
explicit-cast error.

This is the binop half of W2d. The other half — a float literal in a
non-binop coercion position, `(let (alpha:f32 0.0) …)` — is untouched and still
requires `(unsafe/cast f32 0.0)`.

### Where this doc / the brief was wrong

* **The predicate is named `node-is-int-literal`, not `is-untyped-int-literal`**
  (`src/nucleusc.nuc`, right after the `add-binop` table). No symbol named
  `is-untyped-int-literal` exists; that phrase is only in the comment above it.
* **"`(* 2 cl)` and `(* cl 2)` … indistinguishable in emitted IR" cannot mean
  byte-identical text.** The emitter preserves source operand order, so the two
  spellings differ by exactly `mul i32 2, %t2` vs `mul i32 %t2, 2` — a
  meaningless difference for a commutative operator, and the *only* one
  remaining after the fix (measured: the two fixtures' full `.ll`s differ in
  those two lines and nothing else, module header aside). The test therefore
  normalizes the module header and the operand order **within genuinely
  commutative instructions only** (`add mul and or xor fadd fmul`); IR types,
  opcodes (`mul` vs `mul nsw`, `icmp ugt` vs `icmp sgt`), instruction sequence,
  and the operand order of non-commutative instructions such as `icmp` are all
  compared verbatim. Verified to have teeth by mutating a type and a signedness
  opcode and confirming the diff catches both.
* **The §1.2 repro does not fail under `--emit-llvm`.** `--emit-llvm` writes
  textual IR without parsing it, so `(malloc (* 4096 (as i64 (sizeof i32))))`
  exits 0 there; the `'%t4' defined with type 'i64' but expected 'i32'` error
  appears only on the compile-and-link path. Reproducing §1.2 needs
  `nucleusc file.nuc -o out` (or `build.sh`), not `--emit-llvm`. Same for §3.6.
* **`node-type`'s `NODE-INT`/`NODE-FLOAT` branches needed no change**, as the
  doc says — confirmed.

### Consequences worth knowing

* `node-type` of a binop now returns **null** when either operand's own
  `node-type` is null (previously it returned operand 1's type regardless). This
  is the safe direction: `emit-node`'s rung-3 cross-check leaves emit's own
  unified type standing, which is the truth. It also makes the answer symmetric
  in operand order, which the old code was not.
* No new macro expansion happens during the type pass. `node-type` returns null
  for a macro-headed cell, so an operand type is already null before
  `node-is-int-literal`/`node-is-float-literal` (which do expand) are reached.
* The `(as i64 (* 4 (+ lb 1)))` workaround in `name-edit-distance`
  (`src/nucleusc.nuc`) **is now redundant** — the natural
  `(* 4 (as i64 (+ lb 1)))` spelling compiles correctly under the new compiler
  (verified). It is deliberately left in place: the committed boot compiler
  predates the fix and still mis-emits the literal-left form, so switching the
  spelling would break `make` until the next `update-bootstrap`. Its comment now
  records this instead of describing a live bug.

### Tests added

* `examples/binop-literal-typing.nuc` + `tests/expected/binop-literal-typing.out`
  — the matrix ({literal-first, literal-second, both-typed, both-literal} ×
  {`i32`, `i64`, `ui32`, `ui64`} × {arith, comparison}), the widening pairs, the
  §1.2 / §1.3 / §3.6 repros, and the float cases. Result types are observed via
  **multimethod dispatch** on a `tkind` overload set, so a wrong unification
  prints a wrong type name rather than hiding in IR text. Signedness is observed
  by value (`4000000000` as `ui32`: unsigned ordering and `udiv` give different
  answers than signed). The committed boot compiler *fails to compile* this
  file, which is the teeth.
* `tests/fixtures/w2a-order-lit-first.nuc` / `-second.nuc` +
  `run_w2a_order_identical` in `tests/run-tests.sh` — the operand-order IR
  equivalence described above.
* `tests/fixtures/w2a-mixed-sign.nuc` / `w2a-mixed-sign-cmp.nuc` — two typed
  operands of different signedness must **still** be rejected, in the arithmetic
  and the comparison form. Pinned with `run_reject_at`, so the location is part
  of the assertion.

### Docs updated

* `docs/types.md` — the "Binary operators do *not* coerce" paragraph was
  **already stale before W2a** (it claimed `(+ i32 i64)` was an error; Stage 9
  §10.3 widening has worked for a long time). Replaced with the actual
  unification table plus the operand-order symmetry guarantee. The float-literal
  paragraph now documents binop adaptation and explicitly scopes the remaining
  `(let (a:f32 0.0) …)` gap to non-binop positions.
* `docs/special-forms.md` / `docs/builtins.md` — "Mixed operands now resolve"
  gains the float-literal case, the result-type statement, and the
  operand-order symmetry.
* `context/conventions.md` — the node-type↔emit-node note gains the
  "shared rule function, not two mirrored copies" paragraph naming
  `binop-result-type`, and records why the `generics.nuc` → `nucleusc.nuc`
  call direction is legal.

---

## W2b as built

**Status: done.** `make bootstrap` byte-identical (`stage1.ll == stage2.ll`),
`make test` 240 PASS / 0 FAIL (was 235 after W2a). W2c is closed by the doc
change noted below; W2d's non-binop half remains open and is unaffected.

The full fix landed — the "acceptable smaller outcome" (better diagnostic,
§3.1 deferred) was **not** taken. Threading a scope into the shared rule turned
out to be four signatures and four call sites, well short of invasive.

### The provenance carrier

Two new `Sym` fields (`src/compiler-types.nuc`):

```lisp
  const-lit:i32       ; this is-const symbol stands for an INTEGER LITERAL
  const-lit-i64:i64   ; …and this is its value
```

Set by `emit-defconst` and `emit-defenum` (and the REPL's hand-registered
`NODE-*` mirror in `src/repl.nuc`, which shadows `lib/prelude.nuc`'s `defenum`);
deliberately **not** set by `emit-deferror`, whose constants are `Err`-typed —
`is-int-type` is true for `TY-ERR`, so without an explicit opt-in an error
constant would have started unifying with plain integers.

**Why a dedicated field rather than reusing `Val.is-lit`.** The brief flagged
`is-lit` as overloaded; it is, and the overload is on the *Val*, where `is-lit=1`
+ a `StrView` type means "unmaterialized string literal" (NS-3). The two uses
are disjoint by type, so setting `is-lit` on an *integer* Val is safe — and that
is exactly what `emit-symbol-ref` now does for a `const-lit` symbol, giving the
constant the same value-level provenance `emit-int` gives an inline literal. The
new fields live on `Sym`, which had no such overload, and carry the value across
the definition→use gap that a Val cannot. Vararg behaviour was checked
explicitly: every `is-lit` consumer on the vararg path (`abi-arg-frag`, the
variadic-slot StrView collapse in `emit-call-with-args`) is gated on
`type-is-strview`, so `(printf "%d\n" SOME_CONST)` is untouched — verified by
test, not by reading.

### Both sides of the lockstep

The type rule stays in exactly one function. `binop-result-type` gained a
`scope:(raw Scope)` parameter and asks a new shared predicate:

```lisp
(defn operand-is-int-literal (n:(raw Node) scope:(raw Scope)):i32
  (when (!= (node-is-int-literal n) 0) (return 1))
  (return (node-is-const-int-literal n scope)))
```

`node-is-const-int-literal` sits beside `node-is-int-literal`. The scope is
threaded, not shortcut: a `defconst` always lives in `g-globals`, but a **local
binding shadows it**, and a shadowed local is not a literal — looking the name
up in `g-globals` directly (which would have avoided all the threading) makes
`(let (K:i32 3) (< K u:ui32))` compile and silently reinterpret the sign. That
is pinned by `tests/fixtures/w2b-shadow-local.nuc`.

The scope reaches the value side through `binop-coerce` → `emit-binop-vals`,
whose two callers (`emit-binop`, `emit-operator-dispatch`) both already had one.
`node-type-call` passes its own. Net: `binop-result-type`, `binop-coerce`,
`emit-binop-vals` each gained one parameter; nothing else moved.

**The trap that cost the most time:** `(* v K)` expands to `(_* v (* K))` — the
variadic operator macros wrap the *tail*, so a binop's second operand node is a
CELL, never the bare symbol. `node-is-int-literal` already macroexpands a CELL
for exactly this reason; `node-is-const-int-literal` must too. Without it the
fix worked in operand-1 position and silently did not in operand-2 position —
reintroducing precisely the operand-order asymmetry W2a existed to remove, and
in a form that the §3.1 repro (which uses `<=`, not a variadic macro) does not
catch. Any future predicate over a binop operand node needs the same
macroexpand.

### The `defenum` decision: members get the same treatment

An enum member carries no distinct nominal type — its `Sym` type is plain `i32`,
and `match` exhaustiveness keys off the `EnumDef`, not the type. Withholding
literal provenance would therefore recreate the identical wart one level over:
`(= c:ui32 GREEN)` rejected while `(= c:ui32 1)` compiles. Pinned by the `enum`
line of `examples/defconst-literal-typing.nuc`. `deferror` constants are the
deliberate exception (above).

### The `BIG` truncation

`emit-defconst` hardcoded `ty-i32` while `const-val` carried the full decimal
string. Fixed by typing the constant at `emit-int`'s LW-4 width, **shared** as a
function rather than copied: `int-literal-type(v)` (`src/nucleusc.nuc`, directly
above `emit-int`) is now called by `emit-int`, `emit-defconst`, and
`node-type`'s `NODE-INT` branch (`src/generics.nuc`) — three former copies of
the same `if`.

Carrying the value also arms the existing LW-4 range check at `coerce-int-val`,
so `(let (x:i32 BIG) …)` is now `integer literal 5000000000 does not fit i32`
rather than a wrap.

**A second narrowing site was found while fixing this**, outside
`coerce-int-val`'s chokepoint: `defvar-init-ir` hands a decimal string straight
to LLVM as a global initializer, and LLVM truncates `i32 5000000000` to
705032704 *without complaint*. This one pre-dates W2b — `(defvar g:i32
5000000000)` with an inline literal wrapped the same way — and is fixed for both
spellings with the same `int-literal-fits` rule
(`tests/fixtures/w2b-defvar-{const,lit}-narrow.nuc`).

### Where this doc / the brief was wrong

* **"Constants that do not fit `i32` are stored `i64` today"** (the W2b
  constraint list) is false; they were stored `ty-i32` and wrapped. The brief
  had already corrected this by measurement, and the correction is the reason
  the `BIG` case is a silent wrong answer rather than an ergonomic wart.
* **"An explicitly-typed constant must keep its type"** is moot, as the brief
  reasoned: W4b makes `(defconst K:i32 512)` a hard error
  (`tests/fixtures/w4a-defconst-annotated.nuc`), so there is no annotated form
  to preserve. Confirmed, not assumed.
* **The brief's worry that `is-lit` on a `defconst` Val "could change vararg
  behaviour"** did not materialize, for a structural reason worth recording:
  every `is-lit` reader on that path is conjoined with `type-is-strview`. The
  danger was real but is already fenced by type.

### Consequences worth knowing

* A `cond`/`if` join with one constant branch and a differently-typed integer
  branch now **widens** (LW-6's `type-join` literal rule) where it previously
  collapsed to `void` and failed at the use: `(let (r:i64 (if c K s64)) …)`
  compiles now and did not before. This follows from "a constant behaves like
  the literal" and is not a separate decision.
* `node-is-int-literal`'s **other** five call sites — the multimethod-dispatch
  `is-lit` flags in `src/generics.nuc` (`arg-adapts`) — were deliberately left
  alone. Those decide *overload selection*, so widening the literal set there
  would silently re-route existing dispatch (the compiler passes `defconst`s to
  overloaded functions constantly). Extending them is a separate, deliberate
  change; `operand-is-int-literal` is documented as binop-only.
* `make bootstrap` stayed byte-identical, which is a real signal rather than
  luck: no `defconst` in `src/`+`lib/` exceeds `i32` (max 1032), and the
  compiler's constant-vs-typed binops are either same-type (short-circuited by
  `type-eq`) or against `i64`/`usize`, where "adopt the other operand's type"
  and "widen to the wider" give the same answer.

### Tests added

* `examples/defconst-literal-typing.nuc` +
  `tests/expected/defconst-literal-typing.out` — the matrix (a `defconst`
  against `{i32, i64, ui32, ui64}` in both operand orders, arithmetic and
  comparison), with **every constant line paired with the identical
  inline-literal line** so the two rows must print the same thing; the §3.1
  repro against its inline spelling; both-constant vs both-literal; the `BIG`
  value through a local, a `defvar` fold, and a vararg; the `defenum` member
  case; and the shadowing local. Result types are observed through a `tkind`
  overload set (W2a's device). The committed boot compiler **fails to compile**
  this file, which is the teeth.
* `tests/fixtures/w2b-shadow-local.nuc` — the scope requirement, as a
  `run_reject_at`.
* `tests/fixtures/w2b-const-narrow.nuc`,
  `tests/fixtures/w2b-defvar-const-narrow.nuc`,
  `tests/fixtures/w2b-defvar-lit-narrow.nuc` — the value-carrying requirement at
  both narrowing sites, named and inline.

### Docs updated

* `docs/types.md` — the binop unification list gains the named-constant clause
  (and the shadowing exception); the integer-literal section gains the width
  rule and the range check for named constants.
* `docs/toplevel.md` / `docs/builtins.md` — the `defconst` and `defenum` rows
  now state the behaviour rather than "always typed `i32`"; the `defvar` row
  records that a named constant is the preferred spelling for a named bound
  (this closes **W2c**, whose only deliverable was that doc correction) and that
  an out-of-range initializer is an error.
* `docs/special-forms.md` / `docs/builtins.md` — "Mixed operands now resolve"
  gains the named-constant case.
* `context/conventions.md` — the `node-type`↔`emit-node` note records the
  variadic-macro operand-wrapper trap and why the scope had to be threaded.

---

## W2d as built

**Status: done.** `make bootstrap` byte-identical (`stage1.ll == stage2.ll`),
`make test` **245 PASS / 0 FAIL** (was 240 after W2b). `make avr-test`,
`make abi-test` and `make layout-test` also green. This closes W2 — W2a, W2b,
W2c and W2d have all landed.

### The finding was bigger than "float literals do not adapt"

`coerce-int-val` (`src/abi.nuc`) — despite its name the general coercion
chokepoint, handling `ptr`/`CStr`/`StrView` as well as integers — had **no
float case at all**. That single hole had two opposite consequences depending
on how each caller reads a null return:

* **Callers that read null as a type error rejected an `f32` target.** Measured:
  `let`/`with` init, `set!`, `.set!` field store, explicit `return`, *implicit*
  return, struct-literal positional **and designated** initializers, array
  positional **and designated** initializers. (The brief listed five; `.set!`
  and the implicit return are two more, found by grepping every
  `coerce-int-val` call site rather than reproducing from the finding.)
* **The one caller that reads null as "leave the argument alone" silently
  miscompiled.** `emit-call-with-args` (`src/nucleusc.nuc`) coerces an argument
  only when its IR type differs from the parameter's and *keeps the original
  value* when `safe-coerce-val` returns null. `safe-coerce-val` knew only
  `f32`→`f64`, so `(take 2.5)` against `(defn take (x:f32):f32 …)` emitted
  `call float @take(double 2.5)` — accepted by the IR parser, printed
  `0.000000`. The same for a non-literal `f64` argument.

So the brief's reframing is right and is the shape of the fix: **the float
coercion path was missing**, not merely literal adaptation.

**A third bug, in a position the brief recorded as already working.**
`(defvar gf:f32 1.5)` does emit `@gf = global float 1.5` — but `1.5` is exactly
representable as a single. `(defvar gf:f32 3.14)` emitted
`@gf = global float 3.14` and died at IR-parse time:

```
error: floating point constant invalid for type
@gf = global float 3.14, align 4
```

LLVM accepts a *decimal* constant for `float` only when it round-trips exactly;
otherwise the constant must be written in the hexadecimal form (the 64 bits of
the double the intended float widens to — clang emits `float 0x40091EB860000000`
for `3.14f`). The comment in `defvar-init-ir` claiming "LLVM accepts the same
decimal/hex form for both" was simply false. A global initializer is a
*constant*, so unlike every other position it cannot be repaired with an
`fptrunc` instruction.

### The chokepoint

All eight rejecting positions and the argument position route through
**`coerce-int-val`** — directly for the eight, and via `safe-coerce-val` for
call arguments. It is therefore the one place the rule needed to land, and the
whole fix is:

* `coerce-int-val` (`src/abi.nuc`) gains a float↔float branch, placed after the
  integer branch: a float **literal** is re-rendered as a constant at the target
  width (no instruction); anything else gets `fpext`/`fptrunc`.
* `safe-coerce-val` (`src/nucleusc.nuc`) replaces its inline `f32`→`f64`-only
  clause with a delegation to `coerce-int-val` for *any* float pair. The
  widening direction produces byte-identical IR (same `fpext float … to double`
  text), so existing programs are unchanged; the narrowing direction is the
  miscompile fix.
* `coerce-num-val` (the binop path, `src/nucleusc.nuc`) likewise delegates
  float↔float to `coerce-int-val` instead of carrying its own copy of the
  `fpext`/`fptrunc` emission. This is also what makes `(* alpha:f32 2.0)` fold
  its literal to `fmul float %a, 0x4000000000000000` instead of emitting an
  `fptrunc double 2.0 to float` first.
* `defvar-init-ir` renders through the new shared width-aware renderer.

Net: **one** float coercion rule, called from three places, in the same shape
W2a used for `binop-result-type` and W2b for `int-literal-type`.

### The literal carrier and the rendering rule

Two new `Val` fields (`src/compiler-types.nuc`), the float counterpart of LW-4's
`is-lit`/`lit-i64`:

```lisp
  is-flit:i32     ; set only by emit-float
  lit-f64:f64     ; …and the value its lexeme denotes
```

A **deliberately separate flag**, not a third overload of `is-lit`. `is-lit`
already means "int literal" and, with a `StrView` type, "unmaterialized string
literal"; a third meaning would require auditing every existing reader for float
reachability, and two of them (`abi-arg-frag`, the variadic `StrView` collapse
in `emit-call-with-args`) sit on the vararg path where floats genuinely appear.

Three small functions in `src/nucleusc.nuc`, beside `float-literal-ir`:

* `float-literal-value (lex)` → the double the lexeme denotes. The three
  Scheme-style tokens are spelled out (`strtod` does not know `+inf.0`); every
  other lexeme the reader accepts is exactly what `strtod` accepts.
* `f32-const-ir (d)` → the LLVM constant text for `d` at `float` width: round
  trip through `(as f64 (unsafe/cast f32 d))` and print the 64 bits in hex,
  read out through the value's own storage since Nucleus has no bitcast
  operator. Output matches clang byte for byte.
* `float-literal-ir-at (lex ty)` → the width-aware renderer. An `f64` target
  keeps the historical lexeme normalization verbatim, so every existing
  program's IR is byte-identical.

`emit-float` tags the Val and keeps typing the literal `f64`; adaptation stays
the *consumer's* decision, made where the target type is known — exactly as for
an integer literal.

### The decision: **Option A** (silent `fptrunc` for non-literals)

Recorded as asked. A non-literal `f64` narrowing into an `f32` target emits an
`fptrunc`, silently, with no diagnostic. Reasoning, strongest first:

1. **It is not a new policy — it is the existing one.** `coerce-int-val`'s
   integer branch, five lines up, silently truncates a typed `i64` into an
   `i32` slot at these exact same positions, and range-checks only *literals*.
   Measured, not assumed: `(let (b:i64 300000000000 a:i32 b) …)` compiles today
   and prints `-647710720`, and `(tk b)` against `(defn tk (x:i32) …)` does the
   same. Option B would have made floats the only kind that behaves differently
   at the shared chokepoint, replacing the asymmetry W2d exists to remove with
   a new one.
2. **C interop.** `conventions.md`'s standing invariant is that Nucleus is a
   drop-in replacement for C; C converts `double`→`float` implicitly at every
   one of these positions. Ported C code would fail to compile under Option B.
3. **Option B needs strictly more machinery to be coherent.** Literal-gating
   would immediately raise the W2b question one level over (does a named float
   constant count?), which needs a float analogue of `Sym.const-lit` —
   for a rule that contradicts the integer policy.
4. The status quo in argument position was a *miscompile*, so nothing can
   legitimately depend on it; both options replace it. Given (1)–(3), A is the
   one that also makes the language smaller.

**The tension Option A inherits, stated plainly:** the explicit `(as f32 d)`
still refuses the conversion as lossy and routes to `unsafe/cast`, while the
implicit coercion at an annotated slot performs it. That is real, but it is
**not float-specific** — `(as i32 n:i64)` is refused while `(let (a:i32 n) …)`
truncates. It is one language-wide question about implicit narrowing at typed
slots, and if it is ever revisited it must be revisited at `coerce-int-val` for
both kinds at once, not for floats alone. Documented in `docs/types.md` rather
than quietly resolved in one direction.

**Multimethod dispatch is deliberately stricter than assignment.** `arg-adapts`
(`src/generics.nuc`) now admits a float *literal* into a narrower float
parameter — without it a solitary `(defn take (x:f32) …)` accepted `(take 0.1)`
while an *overloaded* one reported `no matching method … (f64)`, which is the
same wart one level over that W2b closed for `defenum` members. A typed `f64`
**value** still does not adapt: dispatch *selects which function runs*, and
silently narrowing a runtime value to make that choice is a different and worse
decision than narrowing into a slot the programmer annotated. This mirrors the
integer branch, which likewise requires `(>= (int-width pt) (int-width at))` for
typed values. The change is **strictly additive**: tier 0
(`generic-find-method-exact`) still claims an exact `f64` overload first, so no
existing call is re-routed — only previously-unresolvable calls become
resolvable. Threaded as a fourth `is-flit` parameter through all four
`arg-adapts` call sites, including **both halves of the lockstep** (the emit
tier and `node-type-call`'s mirror of it).

### The range check that isn't

LW-4 rejects an integer literal that does not fit its target. W2d deliberately
does **not** do the float analogue: `(let (x:f32 1e300) …)` saturates to `+inf`
rather than erroring. Integer narrowing wraps — a value discontinuity with no
mathematical meaning — whereas float overflow to `±inf` is an IEEE-754-defined
result, and C agrees (`float d = 1e300;` is a clang *warning*, not an error).
Worth revisiting only alongside a general "lossy literal" warning tier.

### `-ffast-math` had to come off the compiler's own link line

Folding a literal at compile time means the **compiler process's** floating
point decides the constant. The Makefile linked `build/nucleusc` (and
`bin/nucleusc`, and the stage-2 binary) with `-ffast-math`, which on Linux/x86
pulls in `crtfastmath.o` and sets FTZ/DAZ in MXCSR for the whole process — so
every denormal single was folded to zero: `(defvar d:f32 1e-45)` emitted
`float 0x0000000000000000` where clang emits `float 0x36A0000000000000`.

Fixed at the root (a `NATIVE_OPT` variable in the Makefile, with the reason
recorded there so it does not come back) rather than worked around in the fold.
The compiler does no floating-point work of its own, so fast-math bought
nothing; a compiler must evaluate constants under strict IEEE semantics. This
changes no emitted IR, so the bootstrap is unaffected.

### Where this doc / the brief was wrong

* **"A position that already works: `(defvar gf:f32 1.5)`."** True only because
  `1.5` is exactly representable. `3.14` fails the IR parse. See above.
* **The brief's list of five rejecting positions is incomplete** — `.set!` field
  store and the *implicit* return reject too, and the struct/array *designated*
  initializer forms are separate call sites from the positional ones. Found by
  auditing `coerce-int-val`'s callers, not by reproducing the finding.
* **The spec's "`binop-coerce`'s float-widening path is the place"** is not
  where W2d landed. That path only serves binops (W2a already fixed it); the
  eight rejecting positions and the argument miscompile all route through
  `coerce-int-val`, so that is the place. `coerce-num-val`'s float branch was in
  fact *removed* and delegated there.
* **The decision to adapt is technically sound** — asked to flag it if not. The
  double rounding the doc worried about is real but pre-existing and unchanged:
  decimal → `f64` → `f32` is exactly what `(unsafe/cast f32 3.14)` has always
  done. Verified explicitly for every constant in the accept test that
  `strtof(s) == (float)strtod(s)`, i.e. the double rounding is invisible for
  them; a decimal for which it is visible does exist in principle, and would be
  equally visible in the explicit spelling.

### Known interaction, not a regression: AVR

`avr-reject-f64` fires inside `emit-float`, before the literal's target width is
known, so on `--target=avr` a float literal is rejected even in an `f32`
position (`(let (a:f32 1.5) …)`). This **predates** W2d — the pre-W2d spelling
`(unsafe/cast f32 1.5)` hits the identical rejection, since `emit-float` runs
before the cast — so an AVR program has never been able to spell a
floating-point constant at all. W2d does change what "finalized as f64" means
(a literal in an `f32` context no longer is one), which makes the check
genuinely premature; moving it is AVR work with its own gate (`make avr-test`,
green). Recorded in `docs/types.md`'s AVR paragraph.

Also unchanged and out of scope: `defconst` still rejects a float value
(`defconst: value must be integer literal`), so there are no named float
constants to give provenance to; and `type-join`'s literal-widening rule (LW-6)
is integer-only, so a value-position `(if c 1.0 y:f32)` still collapses to void.
Neither is a regression.

### Tests added

* `examples/float-literal-typing.nuc` +
  `tests/expected/float-literal-typing.out` — every position that used to
  reject an `f32` target, checked **by value** and not by exit code: `let`,
  `with`, `set!`, `.set!`, explicit and implicit `return`, struct literal
  (positional and designated), `(array f32 …)`, call argument (literal *and*
  non-literal), overload dispatch, the `defvar` global initializer including
  the `3.14` case that failed the IR parse, `+inf.0`/`-inf.0` and the denormal
  `1e-45` the fast-math process folded to zero — plus the `f64` lanes that must
  **stay** `f64` (`(let (b:f64 0.1))` and the bare `(let (c 0.1))`) and the W2a
  binop cases as a regression. Values print with `%.9g`, which round-trips an
  IEEE single exactly, so `0.1` vs `0.100000001` is the visible difference
  between a value that really went through `float` and one that stayed
  `double`; every printed value was checked against an equivalent C program.
  Static types are observed through a `tkind` overload set (W2a's device).
* `tests/fixtures/w2d-dsp-biquad.nuc` + `tests/fixtures/w2d-dsp-biquad.c` +
  `run_w2d_dsp_bitexact` (`tests/run-tests.sh`) — the spec's accept criterion.
  A direct-form-I biquad with an input generator and a triangular window, all
  coefficients written as bare float literals with no cast anywhere, printing
  each output's exact 32-bit pattern as well as `%.9g`. Compared against the
  C twin compiled by the container's clang: **bit-exact, every sample and the
  accumulator, at `-O0` and `-O2`.** Two things are load-bearing in the
  comparison and are commented in both files: every expression is written as an
  explicit *binary* tree (Nucleus's variadic `+`/`*` macros are
  right-associative, C's operators are left-associative, and for floating point
  those are different numbers), and the C side is built with
  `-ffp-contract=off` (clang contracts `a*b+c` to an FMA where the target has
  one; Nucleus never emits the `contract` flag). The Nucleus side goes through
  the real compile-and-link path, not `--emit-llvm` — `--emit-llvm` never parses
  the IR it writes, so it cannot catch either an invalid float constant or a
  type-mismatched call operand, which is exactly how both of those bugs stayed
  invisible.
* `tests/fixtures/w2d-float-into-int.nuc`,
  `tests/fixtures/w2d-mixed-float-int-binop.nuc`,
  `tests/fixtures/w2d-dispatch-no-narrow.nuc` — the three boundaries the fix
  must not cross, pinned with `run_reject_at` so the location is part of the
  assertion: a float literal does not fall into an integer slot, does not adapt
  to an integer binop operand, and a typed `f64` value does not narrow to win an
  overload.

### Docs updated

* `docs/types.md` — the float-literal paragraph is rewritten around "a float
  literal is untyped and adapts to whatever float width the position wants",
  listing the positions and stating explicitly that a bare literal with no
  target is still `f64`; the coercion table's `f32 → f64` bullet becomes a full
  float↔float bullet (literal fold vs. value `fptrunc`, no range check, and the
  double-rounding statement); the "explicit `unsafe/cast` still required" line
  drops `f64 → f32` and gains a paragraph naming the `as`-vs-assignment
  asymmetry as a general, pre-existing question; a new paragraph states the
  dispatch rule; the AVR paragraph records the float-literal interaction.
* `docs/special-forms.md` — the `as` row said it "accepts exactly what the
  implicit-coercion machinery accepts in an assignment position", which W2d
  makes false; it now says the *non-lossy part*, and names the deliberate
  strictness. "Mixed operands now resolve" notes the adaptation applies outside
  binops too.
* `docs/builtins.md` — the same two edits, plus its **stale mirror** of the
  types.md coercion section (which still used the retired `cast` spelling and
  claimed "Binary operators do *not* coerce" — a claim W2a had already
  corrected in types.md but not here) brought in line.
* `docs/toplevel.md` / `docs/builtins.md` — the `defvar` row records that an
  `f32` initializer is rounded to single precision at compile time and equals
  C's `3.14f`.
* `context/conventions.md` — a note on the coercion chokepoint: what
  `coerce-int-val` actually is despite its name, and the null-return asymmetry
  (eight callers raise, one silently passes through) that is why one missing
  case produced both a rejection and a miscompile.
