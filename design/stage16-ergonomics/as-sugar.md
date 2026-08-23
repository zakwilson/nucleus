# Stage 16 — `as` sugar in value position: `baz:CStr`

**Status:** Evaluated **and implemented** 2026-08-23 — A1, A2, A3 and A4 all
landed as recommended. 804 tests (was 799), `make bootstrap` byte-identical on
the first try, `examples/as-sugar.nuc` plus four rejection fixtures. The reader
was not touched. Implementation notes, including the two things the evaluation
below did not predict, are in §9.

Original recommendation, unchanged: **do the atom form, at emit time, in two
functions** (`emit-symbol-ref` + `node-type-sym`); leave the parenthesised form
to `deftype` aliases. The reader needs **no work at all** — the concern in the
item ("I don't want to make the reader work too hard") is answerable with "then
don't touch it", and the one spelling that *would* require reader work is
precisely the one to exclude.

The ask: `(contains #{"foo" "bar"} (as CStr baz))` written as
`(contains #{"foo" "bar"} baz:CStr)`.

---

## 1. Ground truth — what `baz:CStr` did before this change

Every claim in this section was checked against the tree on 2026-08-23, by
compiling probe programs with `build/nucleusc` and by instrumenting the compiler
(see §3).

**The reader does not participate.** `:` is an ordinary symbol character, so
`baz:CStr` lexes as one `NODE-SYM` whose spelling contains a colon. The split is
done far downstream by `split-typed` (`src/nucleusc.nuc:1272`), which every
consumer calls for itself.

**In value position the annotation is already parsed, and then thrown away.**
`emit-symbol-ref` (`src/nucleusc.nuc:3240`) splits at line 3255 and discards the
type half; its own comment says why — "so typed names (e.g. `i:i32` from macro
expansion) resolve correctly in value position". Consequences, each verified:

| Probe | Today |
|---|---|
| `(printf "%ld\n" x:i32)`, `x` an `i64` local | compiles, means `x`, exit 0 |
| `(printf "%ld\n" x:NoSuchType)` | **compiles**, exit 0 — a type that does not exist is not even looked up |
| `(printf "%d\n" x::i64)` | compiles, means `x` (the `::` spelling is equally free) |
| `(take x:i64)`, `x` an `i32` local | compiles; the ordinary argument coercion widens |
| `5:i64` | `undefined: 5:i64` — the lexer makes it one symbol, so literals are outside the sugar without lexer work |
| `null:raw:N` | `undefined: null:raw:N` — `null`/`true`/`false`/`none` are matched by interned symbol *identity* above the split, so an annotated one never reaches it |
| `(getp q:(ref P))` | `unknown: ref — not defined anywhere in this compilation unit` |

The last row is the important one. **The parenthesised form is not free**: the
Stage 11/14 colon-paren fuse (`fuse-colon-paren`, `src/reader.nuc:865`) fires in
*every* list context, binding or not, so `q:(ref P)` in an argument list is read
as the two-element cell `(q (ref P))` — which in value position is a *call* of
the local `q`, routed to the Stage 9 callable-value path, and dies on `ref`.

**So the spelling's value-position slot is free, but occupied by a silent
no-op** — which is a wart in its own right. `x:NoSuchType` compiling is the
same class of bug as the `defconst` one W4b swept
(`reject-colon-in-def-name`): a colon-bearing spelling that survives into a
position nothing validates.

**No clash with namespaces.** Qualified names use `/` (`p/name`,
`qa/describe` — docs/macros.md, docs/generics.md), not `:`.

## 2. The cost is not implementation, it is a third meaning for one atom

`name:Type` already has two meanings, both documented (docs/types.md §1, §15):

1. **Declaration** — `(let (x:i32 …))`, `(defn f (v:(raw Node)) …)`,
   `(defstruct S next:raw:Node)`. First segment is a *name*.
2. **Type expression** — the type argument of `as`/`unsafe/cast`/`sizeof`/
   `alloca`, and any nested type position: `ptr:Node`, `ref:Vector:i32`,
   `raw:i8`. First segment is a *pointer-kind constructor*, not a name.

The proposal adds a third: **value expression, meaning a cast**. All three are
disambiguated purely by position, and the tree already contains the collision
that makes this concrete — locals named after pointer kinds:

| Site | Binding | Same atom read as a type |
|---|---|---|
| `src/reader.nuc:948` | `raw:ptr` — local `raw`, type `ptr` | raw pointer to `void*` |
| `src/generics.nuc:536,551,1107,1638` | `raw:i32` — local `raw`, type `i32` | raw pointer to `i32` |
| `src/nucleusc.nuc:2235` | `ref:CStr` — local `ref`, type `CStr` | reference to `CStr` |
| `src/repl.nuc:647,651,655` | `fn:ptr` — local `fn`, type `ptr` | — |

After the change, `raw:i32` means "declare local `raw` as `i32`" in a binding
slot, "raw pointer to `i32`" in a type slot, and "cast local `raw` to `i32`" in
a value slot. Nothing is ambiguous to the *compiler* — no position accepts both
a type and a value — but a reader of the source must know the position to know
the reading. The sharpest local form of this is the binding list, where the
positions alternate: in `(let (a:i32 b:i32) …)`, `a:i32` declares and `b:i32`
casts.

This is the item's real price. It is a judgement call, not a defect; §7 sketches
the one alternative that avoids it at no extra implementation cost.

## 3. How much existing code changes meaning: 16 sites, all identity

Measured, not estimated. `emit-symbol-ref` was instrumented to print every
value-position symbol carrying an annotation, and the instrumented compiler was
run over `src/` (self-compile), all 150 `examples/`, and the `lib/` files they
pull in:

**16 distinct sites tree-wide.** Nine in the compiler (`src/abi.nuc` ×5,
`src/cheader.nuc` ×2, `src/nucleusc.nuc:1251`, `src/union-emit.nuc:466`), five in
`examples/`, two in `lib/` (`string.nuc:90`, `strview.nuc:325`). Every one is a
loop counter — `i:i32`, `j:i32`, `fi:i32`, `i:usize` — written in the idiom
`lib/macros.nuc` documents for `for`/`dotimes`
(`(for (i:i32 0) (< i:i32 n) (inc! i:i32) …)`, macros.nuc:133). In every one the
annotation names the variable's actual type, so the cast would be **identity**:
`as` step 3 (`type-eq` → `as-retype`, `src/nucleusc.nuc:4013`) emits no IR.

That is the whole exposure inside this repo. The external gate is the Doom port
at `/home/zak/code/nuc-doom-claude` (~25k lines), which no in-repo measurement
covers and which should be compiled before and after.

## 4. Where the change goes — and why the site decides whether seven passes break

**Not the reader.** A reader-level rewrite of `x:T` → `(as T x)` would destroy
meaning (2): `(as ptr:i8 x)` would become `(as (as i8 ptr) x)`. The reader is
position-blind by design and must stay so.

**Not desugar either**, and this is the finding worth carrying: **seven passes
strip a value-position annotation and key on the bare name**, so any
implementation that rewrites the *tree* silently changes what they see.

| Pass | Site | Keys on |
|---|---|---|
| `emit-symbol-ref` | `nucleusc.nuc:3255` | the value read |
| `node-type-sym` | `generics.nuc:4583` | its lockstep partner (conventions.md) |
| `emit-set` | `nucleusc.nuc:9660` | the `set!` *target* (an lvalue — never a cast) |
| `fn-capture-walk` | `nucleusc.nuc:6780` | is this name a closure capture |
| `fn-rewrite-captures` | `nucleusc.nuc:7041` (+7086 `addr-of`, 7137 `set!`) | rewrite capture → env field |
| `node-binding-name` | `nucleusc.nuc:2387` | Stage 10 non-null flow facts |
| `node-is-const-int-literal` / `const-fold-int` | `nucleusc.nuc:3411`, `11688` | literal adaptation, global initializers |

Demonstrated for the flow facts — the three arms of one probe file:

```nucleus
(defn f (p:?ptr:N):i32 (when (!= p null)            (return (p k))) (return 0))  ; OK
(defn g (p:?ptr:N):i32 (when (!= p:?ptr:N null)     (return (p k))) (return 0))  ; OK today
(defn h (p:?ptr:N):i32 (when (!= (as ?ptr:N p) null)(return (p k))) (return 0))  ; ERROR
```

`h` fails with `field access: value may be null — narrow with if-some/when-some,
unwrap, or a (when (= x null) ...) guard before use`: `node-binding-name` returns
null for a non-`NODE-SYM` node, so wrapping the guard operand in `as` loses the
narrowing. `g` works because the annotation is stripped and the fact is still
keyed on `p`.

**So: implement it in `emit-symbol-ref`, leaving the node a `NODE-SYM`.** All
seven passes keep working unchanged, `set!` targets and `addr-of` keep the
lvalue reading for free, and the change is confined to the two functions the
conventions file already pairs. `emit-symbol-ref` has exactly two callers
(`nucleusc.nuc:1800`, the `emit-node` `NODE-SYM` arm, and `nucleusc.nuc:10961`,
the callable-value head), so "value position" is well-defined and small.

Shape, following the conventions.md "one shared rule function, never two mirrored
copies" rule that `binop-result-type` and `as-int-narrowing` already set: lift
`emit-as`'s conversion body (steps 1–7, `nucleusc.nuc:4073`+) into
`as-convert (v src dst line)`, have `emit-as` and `emit-symbol-ref` both call it,
and have `node-type-sym` return the parsed annotation type instead of the Sym's.
Two details the split must get right: the annotation has to apply *after* the
`is-const` branch (so an annotated `defconst` name still folds, then converts),
and the four self-evaluating names sit *above* the split, so `null:raw:N` stays
unsupported unless given explicit arms — which it should not be, since Phase F
makes `null` raw and `(as ptr:N null)` is refused anyway.

## 5. Semantics: it must be `as`, and that is the good news

`as` is not reinterpretation. `emit-as` routes pointer↔pointer through
`as-ptr-convert`, which fires the Stage 10 pkind flow gate (never a `type-eq`
identity short-circuit, "so it would silently launder raw→ref"); int→int
narrowing goes through `as-int-narrowing` and is refused; `defcast` rules extend
the set; StrView collapses. The sugar inherits all of it. Three consequences:

- **`x:T` stops being decorative and starts being checked.** `x:NoSuchType`
  becomes `unknown type`, and an annotation that contradicts the binding becomes
  a diagnostic instead of a lie. This is a strict improvement and is arguably
  worth the change on its own.
- **`unsafe/cast` deliberately gets no sugar.** 1253 sites, 776 of them with a
  bare-symbol operand — and they stay long. The asymmetry is the point: the
  short spelling should be the safe one.
- The `as` want channel (TC-2) is armed by `emit-as` around its operand. In the
  sugar the "operand" is a name already in scope, so there is nothing to arm —
  one less moving part, but also the reason the sugar can never subsume the
  target-typed uses of `as` (e.g. `(as (ref (Vector (ref Cleanup))) (vector-new-in …))`).

## 6. What it buys, measured

Across `src/` + `lib/` there are **3327** `(as …)` forms. **2411 (72 %)** have a
bare-symbol operand *and* an atom-spellable type — the adoptable set. The
distribution is concentrated: `ptr` 1055, `ptr:ptr` 323, `i64` 195, `CStr` 112,
`usize` 111, `ptr:i8` 103, `ptr:i32` 61, `ptr:Val` 54, `ptr:Node` 49,
`raw:Node` 46.

`(as ptr f)` → `f:ptr` saves 5 characters and, more usefully, one paren level in
an argument list — the motivating example is exactly that shape. Total ≈ 12k
characters across the compiler, which is not the argument; the argument is that
casts stop nesting.

Not adoptable: **916** forms whose operand is not a bare symbol (a call, a field
access, a literal); **14** with a parenthesised type; **14** whose operand is the
`->` threading hole — `->` matches the hole by `strcmp` against `"_"`
(`lib/macros.nuc:280`), so `_:ptr:Node` is not recognised as a hole and the
value silently fails to thread. That last one deserves a line in the docs if the
sugar lands.

## 7. Recommendation

**A1 — atom form only, at emit time.** `emit-symbol-ref` + `node-type-sym`, via
a shared `as-convert` lifted out of `emit-as`. ~30 lines. No reader change, no
desugar change, no new special form, six analyses untouched.

**A2 — exclude the parenthesised form; do not make the fuse value-aware.** It
cannot be: the fuse output `(name <paren-form>)` *is* the canonical binding shape
and, in value position, is indistinguishable from `(v i)` collection indexing and
`(m 'k)` lookup, both of which the Stage 9 callable-value path already claims.
The answer is `deftype`, which landed earlier in this stage: an alias makes any
type a single token, and the atom sugar works on single tokens.
`container-type-sugar.md` reached the same conclusion from the other direction
("aliases and the colon sugar compose, and that combination is the real answer"),
and this item is the third case of it.

**A3 — improve the near-miss diagnostic.** Today `(getp q:(ref P))` reports
`unknown: ref`, which names neither the mistake nor the fix. Since the shape is
detectable at the callable-value site (head is a local binding, sole argument is
a pointer-kind symbol), it can say so and point at `deftype` or the explicit
`as`. This is worth doing whether or not A1 lands.

**A4 — gates.** `make test`; `make bootstrap` byte-identical (the 16 sites in §3
must emit identical IR — `as-retype`/`as-ptr-convert` emit none on those paths,
but verify rather than assume, and note `as-retype` allocates a fresh `Val` and
copies taint, so a `defconst` name's `is-lit` provenance is the thing to watch);
and a before/after compile of the Doom port.

**If the third meaning (§2) is judged too expensive**, the alternative that costs
nothing extra is a **distinct spelling**: `baz::CStr` reaches the identical code
path (verified: it compiles today and means `baz`, because `split-typed` cuts at
the *first* colon and the second segment is discarded with the rest), needs no
reader work either, and keeps the declaration / type / cast readings visually
apart. It is uglier, and it collides with nothing: `a::(T)` is already a reader
error ("empty segment in colon-chain"), and no source spells `::`.

## 8. Docs, if it lands

- `docs/types.md` §Types: add the third reading beside the two it documents,
  with the position rule and the `let`-binding-list alternation as the worked
  example. Also record — independently of this item — that a value-position
  annotation is currently *ignored*, which is undocumented today.
- `docs/macros.md` / `lib/macros.nuc`: the `for`/`dotimes` idiom
  `(inc! i:i32)` / `(< i:i32 n)` keeps working (identity cast, and the `set!`
  target keeps the lvalue reading), but the annotation is no longer decoration —
  say so where the idiom is documented.
- The `->` hole caveat from §6.

---

## 9. Implementation notes (2026-08-23)

Landed as designed. Three functions changed shape and two were added:

- **`as-convert (v dst line)`** (`src/nucleusc.nuc`, immediately above
  `emit-as`) — steps 1–8 of `emit-as`, lifted verbatim with `(cc line)` replaced
  by the `line` parameter. `emit-as` keeps only what needs a *node*: the arity
  check, `parse-type-from-node`, and the TC-2 want-channel save/restore around
  its operand. This is the conventions.md shared-rule shape: the sugar calls the
  rule, it does not mirror it.
- **`value-annot-type (annot line)`** (`src/generics.nuc`, above
  `node-type-sym`) — the destination type of an annotation, or null. It exists
  because the two halves need *different* failure behaviour from one answer:
  `parse-type-name` aborts on an unknown spelling, and node-type may not abort
  (conventions.md), so the `tyname-resolvable` probe runs first and an
  unresolvable annotation yields null. node-type then reports "not modelled" and
  `emit-symbol-ref` raises the located `unknown type '…' in the annotation '…'`.
- **`emit-symbol-ref` split into `emit-symbol-ref-bound` + a wrapper.** The
  bound half is the old body from the `scope-lookup` down; the wrapper keeps the
  four self-evaluating arms, does the split, calls the bound half, and converts.
  The split is what avoids teaching each of the old body's six return paths
  (const, ct-only, fn-value, array decay, load, undefined) about annotations.
- **`node-type-sym`** gains one arm, after the lookup so an unbound annotated
  name still reports "unknown" from emit rather than typing successfully.
- **`emit-callable-value`** gains the §A3 near-miss check.

**Two things the evaluation above got wrong, both minor and both in the same
direction — a spelling it assumed would work does not:**

1. `(f x):CStr` does **not** annotate a computed operand. The evaluation
   recorded non-symbol operands as "not adoptable" but did not notice *why* the
   spelling fails: `:CStr` after `)` lexes as a **keyword**, not as a trailing
   annotation, so it is not even a near-miss — it is a `Keyword` value in
   argument position. Documented in docs/types.md as one of the three limits.
2. The §A3 diagnostic's first draft had **three** `%s` in a `fmt-2s` — the
   format-helper arity trap conventions.md opens with, written by the person who
   had just re-read that section. Caught before the build. The check itself
   needed no scope lookup after all: none of `ptr`/`ref`/`raw`/`fn` names a
   function or binding anywhere in the tree, so the fused shape cannot collide
   with a real call.

**The gates came in clean and that is itself the measurement.** `make bootstrap`
converged byte-identical on the first attempt, which is the §3 prediction
(16 sites, all identity casts, `as-retype`/`as-ptr-convert` emitting no IR)
holding at full scale — the compiler's own `for`/`dotimes` counters now go
through `as-convert` and produce the same IR they did as decorations. No source
in `src/` or `lib/` was migrated to the sugar: adoption is a separate, mechanical
change, and doing it in the same commit would have made the bootstrap result
meaningless.

**The external gate (§A4) could not run, and that is not this change's doing.**
The Doom port at `/home/zak/code/nuc-doom-claude` does not compile against this
repo's HEAD at all — `src/doomdata.nuc:66` is refused with `as: raw pointer CStr
where non-null ptr:ui8 is required` (the W9 item 7 tightening), and past that
`src/w_file.nuc:43` collides on `SEEK_SET` with `g_game.nuc:111` (the
one-name-one-definition rule). Both reproduce **byte-identically** under the
committed boot compiler (`bin/nucleusc`, which predates this change) across ten
entry points, so the port is red for earlier work and needs updating on its own
side. What that does give is the weak form of the gate: the front end's
behaviour on 25k lines of external source is unchanged up to the point where it
already failed. The strong form — does the sugar's new refusal set reject
anything real — remains unmeasured until the port builds again.

## 10. Adoption and the boot refresh (2026-08-23, follow-up)

Reported after the feature landed: *"the sugar does not work when the type is
`usize`."* It does — the boot did not.

`make` builds `src/` with `bin/nucleusc`, and the committed boot predated the
feature, so it read every adopted annotation the old way: **discard it, use the
bare name**. That is silent and harmless wherever an ordinary coercion re-derives
the type, which covered sixteen of the seventeen sites adopted in
`src/nucleusc.nuc` (`g-source-path:CStr`, `NODE-SYM:i32`, `i0:i64`, `sp:CStr`,
`buf:CStr`, …). The seventeenth, `(invoke g-include-paths j:usize)`, is an
argument whose type **selects an overload**, so dropping it dispatched on `i32`
and failed `no matching method for overloaded 'invoke' with argument types
(ptr:Vector.cstr, i32)`. One type failing out of five is what made it look like a
`usize` bug in the feature; every shape of `usize` sugar compiles and runs
correctly under `build/nucleusc` (bare, chained `ptr:usize`, `return`, `let`
init, both binop operand slots, field store, dispatch argument, `dotimes`
counter, and `ssize` beside it).

Resolved by refreshing the bootstrap, the repo's standing two-commit dance
(`Boot for deftype`, `Boot for variables in collection literals`). `make
update-bootstrap` could not run — its `$(BIN)` dependency is the build that was
failing — so the seed came from the relink escape (context/conventions.md): the
already-built `build/nucleusc` implements the sugar, so it emitted the new
`boot/nucleusc.ll` directly, `make boot-binary` relinked `bin/nucleusc` from it,
and `make windows-boot` kept the committed Windows IRs in lockstep.

**The adoption is IR-neutral, verified rather than assumed.** A pre-adoption copy
of the tree (HEAD's `src/nucleusc.nuc` against the same `src/`+`lib/`) compiled
with the same compiler yields IR **byte-identical** to the adopted tree's, module
header aside — 0 diff lines over 155,044. Gates after the refresh: 804 tests,
`make bootstrap` converges, abi/layout/check-headers/avr green.

The durable lesson is in conventions.md rather than here: before adopting a new
spelling in `src/`, ask what the boot will *silently* make of it, not whether the
boot rejects it. A rejected spelling fails loudly at the first site; a
reinterpreted one fails only where the difference is observable, which makes a
stale boot look like a type-specific defect in the new feature.
