# Variadic `and`/`or` — implementation prompt

Make the logical `and`/`or` **variadic**, following the established split between
the `_+ _- _* _/` binary primitives and the `+ - * /` variadic prelude macros.
The short-circuit lowering stays a tight binary compiler primitive under new
names `_and`/`_or`; the user-facing `and`/`or` become variadic macros that
right-fold to them.

## Approach (fixed — do not re-litigate)

**Option B: macros + renamed binary primitives.** This was chosen over (A)
variadicizing the special form in-place and (C) macros-over-`cond`, because it
matches the proven `_+`/`+` precedent, keeps the optimal binary IR, and preserves
a byte-identical bootstrap. Rationale lives in the orchestrating session's
analysis; this file is the build order.

## Authoritative decisions

1. **`and`/`or` become variadic macros** in `lib/macros.nuc` that right-fold:
   `(and)`→`true`, `(or)`→`false`, `(and x)`→`x`, `(and a b c…)`→
   `(_and a (and b c…))`, symmetrically for `or` over `_or`.
2. **`_and`/`_or` are the binary short-circuit primitives** (the renamed
   special forms), routed to the existing `emit-short-circuit`. They are
   **documented public primitives**, available for hand-written binary
   short-circuit, consistent with how `_+` is exposed.
3. **The IR label prefix inside `emit-short-circuit` stays the literal
   `"and"`/`"or"`** (NOT `"_and"`/`"_or"`). Only the *dispatch symbol* changes
   to `_and`/`_or`. This keeps emitted IR labels (`and.rhs0`, `%and.val0`, …)
   byte-identical — the key to a no-refresh bootstrap.
4. **Cumulative narrowing is preserved by the nesting.** Each binary `_and`
   narrows its RHS by its LHS; a right-nested chain means each RHS sees all
   prior LHS non-null facts — identical to today's 2-arg behaviour, extended.
5. **Minor semantics change (accepted):** 1-arg `(and x)` now returns `x`
   unchecked (previously: `"and expects 2 args"`). This matches `+`/CL
   variadic semantics; the i1 check still fires for ≥2-arg forms inside
   `emit-short-circuit`. Document it.

## Non-negotiable invariants

- **Byte-identical bootstrap, no refresh.** After the change, `make` then
  `make bootstrap` must reconverge with `build/nucleusc.ll == build/stage2.ll`
  **without** running `make update-bootstrap`. The change is inert for the
  compiler's own source: `and`/`or` call sites macro-expand to nested
  `_and`/`_or`, which emit via the unchanged `emit-short-circuit` with
  unchanged `tag` labels. If the boot drifts, the narrowing-analyzer retarget
  (Step 2) is the prime suspect — a narrowing regression changes codegen.
- **Narrowing preserved end-to-end.** A chain like
  `(and (!= m null) (m kind) (> (m x) 0))` must narrow each clause by all
  prior ones (so `(m kind)` and `(m x)` typecheck under `m` non-null).
- **`make test` stays green** and the count rises with the new variadic tests.

## Read (scoped — grep by NAME; line numbers drift)

- `src/union-emit.nuc` — `emit-short-circuit` (the binary lowering + Stage-10
  narrowing via `test-true-nonnull`/`test-false-nonnull`/`narrow-names`).
  **Do not change its `tag` strings or its IR emission.**
- `src/nucleusc.nuc` — the special-form dispatch chain (`hp 'and`/`hp 'or` →
  `emit-short-circuit`); `g-special-form-set` member list (`"not" "and" "or"`);
  `test-true-nonnull` and `test-false-nonnull` (the narrowing fact collectors
  that currently flat-iterate `(and…)`/`(or…)`); `special-form-named` and the
  node-classification path that consumes the set; `emit-symbol-ref` (confirm
  `true`/`false` are `ty-i1` literals — they are).
- `src/generics.nuc` — `node-type` cases for `'and`/`'or` (return `ty-i1`).
- `lib/macros.nuc` — the `+ - * /` (`&rest` right-fold to `_+ _- _* _/`)
  macros: this is the exact pattern to mirror for `and`/`or`.
- `docs/special-forms.md` — the existing `and`/`or`/`not` rows. Find and follow
  wherever `_+`/`+` is documented for the primitive/macro split style.

## Build

### Step 0 — exhaustive reference sweep
Grep the whole tree for every compiler reference to the `and`/`or` symbols and
the strings `"and"`/`"or"`. Do not rely on the list below being complete.
Known sites: the dispatch chain, `g-special-form-set`, both narrowing
analyzers, and `node-type`. Report any additional site you find and retarget it
too.

### Step 1 — rename the primitive (compiler core)
- **Dispatch:** retarget the two dispatch lines from `'and`/`'or` to
  `'_and`/`'_or`, still calling `emit-short-circuit` with `is-and` 1/0.
- **`g-special-form-set`:** replace the `"and"` `"or"` members with `"_and"`
  `"_or"` (`"not"` stays). This keeps `special-form-named`/node-classification
  treating them as special forms (so they are not parsed as ordinary calls).
- **`node-type`:** retarget the `'and`/`'or` cases to `'_and`/`'_or` (both
  still `return ty-i1`). Remove the now-dead `'and`/`'or` cases.
- **Leave `emit-short-circuit` itself unchanged** (same `tag`, same IR).

### Step 2 — retarget the narrowing analyzers (the hidden cost)
`test-true-nonnull` and `test-false-nonnull` currently flat-iterate an N-ary
`(and…)`/`(or…)`. Under this approach, emit-time nodes are right-nested
**binary** `_and`/`_or` (macros expand before emit), so:
- In `test-true-nonnull`: replace the `(strcmp h "and")` flat-loop branch with
  a `(strcmp h "_and")` branch that, when `node-len == 3`, recurses on
  **both** children (`test-true-nonnull` child 1; `test-true-nonnull`
  child 2). Recursing both arms of a binary `_and` re-flattens the spine and
  is simpler than the current loop.
- Symmetrically, retarget `test-false-nonnull`'s `"or"` branch to `"_or"`,
  recursing both children.
- The `not`/`!=`/`=` cases stay unchanged.

Equivalence check: `(_and a (_and b c))` true ⇒ facts from `a`, `b`, `c` —
same as today's flat `(and a b c)`.

### Step 3 — add the variadic macros (`lib/macros.nuc`)
Next to `+ - * /`, same right-fold shape, i1 base cases (`true`/`false`):

```lisp
(defmacro and (&rest args)
  (cond (= args null) `true
        (= ((cast ptr:Node args) cdr) null) ((cast ptr:Node args) car)
        true `(_and ~((cast ptr:Node args) car)
                    (and ~@((cast ptr:Node args) cdr)))))

(defmacro or (&rest args)
  (cond (= args null) `false
        (= ((cast ptr:Node args) cdr) null) ((cast ptr:Node args) car)
        true `(_or ~((cast ptr:Node args) car)
                   (or ~@((cast ptr:Node args) cdr)))))
```

Mirror the surrounding macros' casting/quasiquote style exactly.

### Step 4 — verify the byte-identical bootstrap (the key invariant)
`make`, then `make bootstrap`. Expect reconvergence with **no**
`make update-bootstrap`. Why it should hold: macro defs compile into the
macro-JIT module, not `nucleusc.ll` (same as `+`/`-`/`*`/`/` today); every
compiler `and`/`or` call site expands to nested `_and`/`_or` emitting via the
unchanged `emit-short-circuit` with unchanged `tag` labels; `node-type` and the
analyzers retarget cleanly so narrowing is unchanged. **If it drifts, do not
refresh the boot — find the narrowing regression and fix it.**

### Step 5 — docs
- `docs/special-forms.md`: reframe the `and`/`or` rows as **variadic macros**
  that fold to the `_and`/`_or` binary primitives; document `(and)`→`true`,
  `(or)`→`false`, the short-circuit + narrowing behaviour, and the 1-arg
  unchecked relaxation. Cross-reference the `_+`/`+` convention. Add
  `_and`/`_or` as documented public binary primitives.
- Mirror whatever doc covers `_+`/`+` for style and placement.

### Step 6 — tests
- Find the existing `and`/`or` test coverage first, then extend/add: variadic
  `(and a b c d)`, `(or a b c)`, 0-arg, 1-arg, and a **narrowing** case
  `(and (!= m null) (m kind) (> (m field) 0))` proving non-null facts flow
  through a 3-arg chain.
- Wire into `make test`; confirm the count rises and `make bootstrap` remains a
  fixed point.

## Done when

- `(and a b c …)` and `(or a b c …)` compile and short-circuit for any arity;
  0-arg yield `true`/`false`, 1-arg yields the operand.
- A 3-arg chain narrows cumulatively (the `(and (!= m null) (m kind) …)` case
  typechecks).
- `_and`/`_or` are usable directly as documented binary primitives.
- `make test` green (count up); **`make bootstrap` byte-identical, no refresh.**

## Report back concisely

1. Every file/function changed (one line each), incl. any extra reference site
   the Step-0 sweep turned up beyond the known list.
2. Confirmation that `make` + `make test` (N pass) + `make bootstrap`
   (byte-identical, **no** `update-bootstrap`) all pass.
3. The new test names/labels and the narrowed 3-arg proof.
4. Anything that behaved differently from this prompt's predictions (especially
   any boot drift and its root cause).
