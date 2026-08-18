# Variables in collection literals

`[a b c]`, `#{a b c}` and `{k v}` accept only scalar *literals* today — int,
float, string, keyword, and quoted symbol. A name is refused:

```
error: set literal elements must be scalar literals (int, float, string, keyword, or quoted symbol)
```

**Status: done.** Implemented as described below, with three corrections
recorded in §10.

**Conclusion up front: the restriction is a phase artifact, not a semantic rule,
and nothing downstream objects to a variable element — measured.** The fix is to
stop expanding the literal in the reader and defer it to a form the type pass
can see. That is a real change (a new special form, a `node-type`↔`emit-node`
pair, template stamping moved to emit) but a contained one, and it closes a
silent mis-typing that exists today.

Follows [container-literal-elements.md](container-literal-elements.md), which
widened the permitted *literal* kinds to keyword and symbol. This item widens
the permitted *expressions*.

## 1. Why the restriction exists

The three readers do not hand a "vector literal" node downstream. They rewrite
the literal on the spot, at read time, into an already-typed form:

```lisp
[1 2 3]
; becomes, in read-vector-literal (src/reader.nuc:731)
(let (g123:(ref (Vector i32)) (alloca (Vector i32)))
  (vector-init g123) (conj g123 1) (conj g123 2) (conj g123 3) g123)
```

To write `(Vector i32)` the reader must know `i32` **syntactically**, and its
only input is the element's node kind. `lit-elem-kind` (`:645`) is a switch on
`NODE-INT` / `NODE-FLOAT` / `NODE-STR` / `NODE-KEYWORD` plus a shape check for
`(quote sym)`; `lit-type-node` (`:666`) maps that to a type node; `infer-lit-type`
(`:683`) enforces one kind across the sequence.

A `NODE-SYM` such as `BK-GLOBAL` could be a local, a global, an enum member, a
`defconst`, a function, or a type name. Nothing in the reader can tell — and
`read-program` (`:1078`) is a whole-file phase that completes before any binding
is registered, so for a **local** the answer does not exist yet at any price.

So the rule is not "a collection may only hold literals". It is "the reader can
only type what it can see in a token."

## 2. Nothing downstream objects — measured

The generated shape works unchanged with non-literal elements. Hand-writing the
exact expansion the reader would produce, with an enum member and an ordinary
local spliced in:

```lisp
(defenum BK BK-GLOBAL BK-PROTOCOL BK-GENERIC BK-MACRO)
(let (kind:i32 BK-MACRO other:i32 7)
  (let (g:(ref (HashSet i32)) (alloca (HashSet i32)))
    (hashset-init g) (conj g BK-GLOBAL) (conj g BK-PROTOCOL) (conj g other)
    …))
```

```
n=3 has-macro=0 has-7=1 has-global=1
```

`conj`, `count` and `contains?` are indifferent. The entire restriction lives in
about 25 lines of `src/reader.nuc`.

## 3. Design

### 3.1 The reader emits a form instead of an expansion

`read-vector-literal` / `read-hashset-literal` / `read-hashmap-literal` stop
building the `let` and emit a marker cell carrying the elements verbatim:

```lisp
[a b c]        ->  (vector-lit a b c)
#{a b c}       ->  (hashset-lit a b c)
{k1 v1 k2 v2}  ->  (hashmap-lit k1 v1 k2 v2)
```

The readers keep only what needs the token stream: reading elements to the
close token (`read-lit-elems`, `:712`), the odd-count check for maps, and the
opening line, which is stamped on the marker cell so every later diagnostic
still blames the `[`.

`lit-elem-kind`, `lit-type-node` and `infer-lit-type` move out of the reader
and become the literal-tier half of the element-type rule (§3.3).

Three new heads are reserved in `g-special-form-set`
(`build-special-form-set`, `src/nucleusc.nuc:17047`). That set is a reservation
against shadowing, which is exactly what is wanted: a user `defn vector-lit`
must not capture a reader-generated form.

### 3.2 Element type: target first, elements second

The want channel already supplies a declared type at every position that names
one — a `let`/`with` binding, a `set!` target, a `return`, a `.set!` field, and
`as` (`g-want-type`, `src/nucleusc.nuc:266`; the roster is spelled out in
`emit-as`'s comment at `:4050`). When a want is armed and it is a
`(Vector E)` / `(HashSet E)` / `(HashMap K V)` instance, **E comes from the
want** and each element coerces to it through the ordinary coercion path.

```lisp
(let (v:(ref (Vector i64)) [1 2 3]))        ; (Vector i64)
(contains? #{BK-GLOBAL BK-MACRO} kind)      ; no want -> infer: (HashSet i32)
```

Target-first is not only ergonomics. Today the declared type is ignored and the
reader's guess wins, unchecked — see §6.1.

When no want is armed, E is the join of the elements under §3.3.

### 3.3 Mixing: literals adapt, values must agree

One function computes E, called by both `node-type` and emit — the decay-rule
discipline (conventions.md, "A decay rule belongs in ONE function that emit and
node-type both CALL"). It partitions the elements:

- **Literal-tier** elements (`NODE-INT`, `NODE-FLOAT`) have no fixed type and
  adapt to whatever the rest settles on. This is what the language already does
  at a call site: `(conj v 1)` on a `(Vector i64)` is accepted.
- **Value-tier** elements — everything else, including a `defconst`/`defenum`
  name, which is a typed `i32` — must all have the *same* type. Two that differ
  is an error.

| Literal | E | Note |
|---|---|---|
| `[1 2 3]` | `i32` | all literal-tier; unchanged from today |
| `[1 n]`, `n:i64` | `i64` | literal adapts to the value |
| `[a b]`, `a:i32 b:i64` | — | error: mixed element types (names both) |
| `[a b]`, `a:i32 b:i32` | `i32` | |
| `[1 2 3]` at `(Vector i64)` | `i64` | want wins (§3.2) |
| `[n 1]` at `(Vector i32)`, `n:i64` | — | error: `n` does not fit the declared `i32` |

Widening a literal is free and already routine. Narrowing a **value** is never
inserted: measured today, `(conj v big)` with `big:i64` on a `(Vector i32)`
reports `no matching method for overloaded 'conj' with argument types
(ptr:Vector.i32, i64)`, and that refusal is the behaviour to preserve.

Rejected alternatives: *strict* (every element identical, literals included)
would refuse `[1 n]` at `n:i64` while `(conj v 1)` on the same vector is legal —
an inconsistency with no upside. A *full numeric join* over values needs a
signed/unsigned rule (`[a u]` at `a:i32 u:ui32`) and inserts coercions on
values, which is where silent surprises come from.

### 3.4 Empty literals

`[]` with a want becomes legal and yields an empty collection of the wanted
type. With no want it keeps today's error, which already names the fix:

```
error: empty vector literal: use (vector-new), e.g. (let (v:(ref (Vector T)) (vector-new)) ...)
```

This falls out of §3.2 rather than being a feature of its own: the empty case is
just "no elements to infer from", and the want is the other source.

### 3.5 The expansion still exists — it just moves

`emit-vector-lit` builds the same AST the reader builds today, now with a known
`E`, and calls `emit-node` on it. Nothing about the emitted code changes; only
who decides `E` and when.

Building AST at emit time and emitting it is established practice in this
compiler — `fn-make-drop-method` synthesizes a whole method this way. Emitting
the expansion rather than open-coding it keeps one description of what a literal
means.

### 3.6 Evaluation order

With calls admissible as elements (`[(f x) (g y)]`), order becomes observable.
Specify and test **left to right**, keys before values within a map pair, which
is what the conj/assoc chain already produces.

## 4. What this touches

**`node-type` returns null, and that is the right answer** — not the
compromise it looks like. `node-type` (`src/generics.nuc:4893`) dispatches on the
head symbol for cells, and the three new heads take the same unmodelled escape
`cond`, `macrolet` and `quasiquote` take.

The reason is specific and worth stating, because the opposite conclusion is the
natural one: **Rung 3 overwrites, it does not assert.** `emit-node` ends with
`(let (t (node-type n scope)) (when (!= t null) (.set! v type t)))` — a non-null
answer *replaces* the type emit computed. And E depends on the want channel,
which is armed around a binding init and already consumed by the time Rung 3
runs (the discipline is spelled out at `generics.nuc:4872`). A `node-type` arm
that recomputed E would therefore answer for a **different** element type than
the one emit just built, and silently retype the Val. Returning null keeps the
one computation that saw the real want.

The cost is that `node-type` now knows less about a literal than it did when the
reader expanded it into a `let` — a call whose argument is a literal no longer
resolves through the node-type path. That is safe by construction: null means
"emit's own type stands", emit resolves the call from the emitted argument Vals,
and node-type is documented as allowed to not-know.

**Stamping happens where it always did.** Because emit rebuilds the same `let`
and calls `emit-node` on it, the type node goes through ordinary type resolution
and `struct-template-stamp-types` (`src/union-registry.nuc:1252`, memoized on the
interned instance name) at the same point in the pipeline as before. Nothing had
to move.

**Macro bodies and `.nuch`.** A literal inside a macro template is expanded at
read time today; after this change the marker form survives into the template
and expands at the use site — which is more correct (the use site's want
applies) but is a behaviour change. `.nuch` exports macro bodies verbatim
through `print-node`, so an exported macro containing a literal would carry
`(vector-lit …)`, and the reading compiler must already know the head. Nothing
in `lib/` currently does this (§7), so the ordering is free — but it must stay
that way until the boot compiler understands the form.

**Line attribution.** The reader owns these diagnostics today and has the
opening line in hand. The marker cell must carry it, and the emit-side
diagnostics must use it rather than the ambient `g-form-line`.

## 5. Diagnostics

Every current message must survive, re-pointed at the literal's line:

- `vector literal: mixed element types` gains the two offending element types
  and their positions, since with variables the clash is no longer visible in
  the source text: `mixed element types: element 0 is i32, element 1 is i64`.
- The "must be scalar literals" messages **disappear** — that is the feature.
  What replaces them is the ordinary unresolved-name error when an element does
  not resolve, which is strictly better than the current blanket refusal.
- `#{…}` and `{…}` need `Hash` and `Eq` on E. With arbitrary element types this
  becomes a reachable error rather than a theoretical one, and the message
  should name the element type and the missing protocol.
- The `Keyword`-needs-`(import-use keyword)` note (container-literal-elements.md
  §2) still applies and is unaffected.

## 6. Adjacent defects this does NOT fix

### 6.1 Template-ref types are not checked on assignment or argument passing

Measured, and **not** caused by literals:

```lisp
(defn takes ((v (ref (Vector i64)))):i64 (return (invoke v 0)))
(with ((a (ref (Vector i32))) [1 2 3])
  (let (b:(ref (Vector i64)) a)      ; accepted
    (takes a)))                      ; accepted
```

No error at any of the three positions. A `(ref (Vector i32))` binds to a
`(ref (Vector i64))` slot and passes as a `(ref (Vector i64))` argument. The
same holds for unrelated element types — `(let (v:(ref (Vector CStr)) [1 2 3]))`
compiles clean.

The visible consequence today runs through the literal path:

```lisp
(with ((v (ref (Vector i64))) [1 2 3])
  (printf "%lld\n" (invoke v 0)))     ; prints 8589934593
```

`8589934593` is `0x2_00000001` — elements 1 and 2, read back as one `i64`. Both
`Vector.i32` and `Vector.i64` are stamped into the module. §3.2's target-first
rule removes *this* instance of it by making the literal build a `(Vector i64)`
in the first place, but the underlying hole is general to stamped template
instances and needs a type-equality check at every binding, argument, `set!` and
`return`. That has its own blast radius and belongs in its own document.

### 6.2 A collection literal in expression position is a per-call construction

Not a defect in the feature, but the reason the motivating site should not
adopt it. `(contains? #{1 2 3 4 5 6 7 8 9} kind)` inside a function emits, per
call:

```
9 × @conj.pHashSet.i32.i32
1 × @hashset_init.pHashSet.i32
1 × @contains_QMARK.pHashSet.i32.i32
```

`hashset_init` mallocs buckets, each `conj` hashes and probes, and no drop is
emitted for the temporary, so the buckets leak per evaluation. (In a `with`
binding the drop runs; in bare expression position there is no binding to drop.)
Deferring the expansion does not change any of this — the same chain is emitted,
just later.

The motivating case, `binding-usable-spelling`
(`src/nucleusc.nuc:10658`), wants a compile-time membership test over nine enum
constants. A runtime `HashSet` is the wrong tool for that at any level of reader
support. In that specific instance the test is also redundant: the nine kinds in
the `or` chain are exactly the nine `case` arms of `binding-src-ns` that can
return a non-null namespace, and the other four of the thirteen registered kinds
(`BK-SPECIAL`, `BK-PRIMITIVE`, `BK-FNTY`, `BK-CONFORMANCE`) fall through to
`(return null)`, which the caller already handled at
`(when (= ns null) (return (as ptr bare)))`. The condition is always true where
it stands, and the function's own comment says so — "since B7 that is every row
that HAS a `src-ns`". Deleting it beats any spelling of the set.

## 7. Bootstrap and risk

**Three collection literals appear in the compiler's own sources** —
`build-special-form-set` and the integer-type set (`src/nucleusc.nuc`) and the
special-form guard in `src/generics.nuc:2523`, that last one a set of *quoted
symbols*. (An earlier scan said zero; the pattern missed `#{`, which is neither
space- nor paren-preceded. Corrected.) So the compiler compiles its own literals
through the new path, and `make bootstrap` is the strongest gate this change
has: a wrong `E` on any of the three would not merely change IR, it would change
the compiler's behaviour.

The regression surface is 35 files across `examples/` and `tests/fixtures/`
(30 of them standalone-compilable) that use literals, all with literal-only
elements, all of which must keep compiling to the same thing. Diffing per-file `--emit-llvm` output before and
after is the gate: for a literal-only element list the new path must select the
same `E` the reader did, so the IR should be **byte-identical**. Any drift is a
bug in the §3.3 rule, not a reason to refresh.

The one intended IR difference is where a want is armed and disagrees with the
element inference — i.e. exactly the §6.1 shape, which today mis-compiles.

## 8. Testing

- **Parity:** every existing literal example and fixture emits byte-identical
  IR. This is the main gate.
- **Variables:** local, global, `defvar`, `defconst`, `defenum` member, and a
  call, in all three literal kinds.
- **Target-first:** `(let (v:(ref (Vector i64)) [1 2 3]))` builds a
  `Vector.i64`, stamps no `Vector.i32`, and round-trips `1` through
  `(invoke v 0)` — the direct regression test for §6.1's `8589934593`.
- **Mixing:** `[1 n]` at `n:i64` gives `(Vector i64)`; `[a b]` at `a:i32 b:i64`
  errors and the message names both types and positions.
- **No value narrowing:** `[n 1]` at a declared `(Vector i32)` with `n:i64` is
  refused.
- **Empty:** `[]` with a want yields an empty typed collection; `[]` with no
  want keeps the `(vector-new)` message.
- **Order:** `[(f) (g)]` where both print — left to right; map keys before
  values.
- **Conformance:** `#{s1 s2}` over a struct with no `Hash` names the type and
  the protocol.
- **Shadowing:** `(defn vector-lit …)` is refused by the special-form
  reservation.
- **Macro body:** a macro whose template contains `[1 2 3]` still works, and the
  use site's want applies.

## 9. Staging

1. **Reserve the three heads** and add the marker forms, with the reader still
   doing today's expansion for literal-only lists. Inert; proves the
   reservation and the `.nuch` path.
2. **Move the element-type rule** out of the reader into the shared function,
   still literal-only. Byte-identical gate.
3. **Defer the expansion**: reader emits markers, `node-type`/`emit-node` arms
   handle them, stamping at emit. Byte-identical gate again — this is the step
   that can drift, and the step where the `node-type` purity question is
   settled.
4. **Admit value-tier elements** (§3.3) and the want-first rule (§3.2).
5. **Empty-with-want** (§3.4), diagnostics (§5), docs.

Steps 1–3 are refactors with a byte-identical gate; the feature is 4–5. If
step 3's stamping question turns out to be intractable, the work stops there
having lost nothing.

## 10. What changed during implementation

Three corrections to the plan above, and one boundary the design did not
anticipate.

**`node-type` returns null.** §4 called the stamping/purity question "the one
genuinely hard spot" and assumed the three heads would need real arms. They do
not, and the reason inverts the assumption: **Rung 3 overwrites rather than
asserts**, so an arm that recomputed E from a want channel already consumed
would silently retype the Val. Null — the `cond`/`macrolet`/`quasiquote` escape
— is the answer that keeps the one computation that saw the real want. The whole
staging plan's step 3 evaporated with it; the element-type rule lives in exactly
one place because there is only one caller, which is stronger than the
"one function, two callers" the design asked for.

**A want does not excuse a mixed literal.** Pure target-first made
`#{:a "b"}` at a declared `(HashSet Keyword)` fail deep inside `conj` instead of
saying "mixed element types", regressing five existing assertions from
[container-literal-elements.md](container-literal-elements.md). The rule
implemented is narrower and better: the element scan runs in **both** paths, but
when a want is armed it only checks the literal's elements against *each other*
and skips value-tier elements entirely — a declared type names the element type,
and `conj`/`assoc` at that type is the more precise check for a value.

**The gensym is still minted in the reader.** Not in the plan, and load-bearing
for the byte-identical gate: `nucleus_gensym`'s counter order is read order, so
minting at emit time would have renamed every `%__gs_N` in the IR. The reader
mints it and stores it in the marker form.

**A value element's type must be spellable.** Inference goes back through
`type-spelling`, which is the compiler's own round-trip spelling but flattens
`(ref T)` to `ptr:T` and cannot spell an array or function type. Rather than
silently stamp `(Vector ptr:P)` where the user wrote a `(ref P)` element, those
are refused with the fix named — declare the collection's type, which takes the
want path and is exact (it spells the instance by its own registry name,
`Vector.i64`, so no element re-spelling happens at all). Scalars, `CStr`,
`Char`, `usize` and struct types all round-trip.

**Four `symlit-refused-*` assertions changed meaning.** They pinned one blanket
"must be scalar literals" message; removing that refusal is the feature. Each
now fails for its own reason, and the reasons are what the shape check always
meant: `'(a b)` and `'1` are `(raw Node)` and refused by nullability at a
`(ref Node)` element, `#{a b}` reports the undefined variable `a`, `#{(f x)}`
the unknown `f`.

## 11. Verification

- **Byte-identical** IR across all 30 standalone-compilable literal-using
  examples and fixtures, before and after, and again after the boot refresh.
- `make test` **773 PASS** (was 760), no FAIL, no SKIP — +13 assertions in
  `run_s16_literal_variables`, plus the four re-pointed `symlit-refused-*`.
- `make bootstrap` converges (`stage1.ll == stage2.ll`), `boot/nucleusc.ll ==
  build/nucleusc.ll`. The compiler's own three `#{…}` literals — including the
  quoted-symbol set at `generics.nuc:2523` — go through the new path.
- abi-test, layout-test, check-headers (69), avr-test (8) all pass.
- The §6.1 regression is closed at the literal:
  `(with ((v (ref (Vector i64))) [1 2 3]) (invoke v 0))` prints `1`, and no
  `Vector.i32` is stamped. The general template-ref hole is untouched, as
  scoped.

## Out of scope

- The template-ref type-equality hole (§6.1) — its own document.
- Making a constant collection cheap (§6.2): a compile-time-constructed or
  static collection is a separate feature, and the honest advice for a constant
  membership test today is `case`, an `or` chain, or a bitmask.
- Element-type *coercion* beyond literal adaptation — no user-defined
  conversions, no `StrView`/`CStr` chameleon behaviour beyond what the ordinary
  coercion path already does.
- Nested literals (`[[1 2] [3 4]]`). Falls out of the design if the inner
  literal's want is armed by the outer element position, but it is untested
  ground and should not gate this item.
