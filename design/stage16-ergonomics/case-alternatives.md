# `case` alternatives: one arm matching several values

Stage 16, item "`case` taking a list"
([overview.md](overview.md) §"`case` taking a list").
**Done, 2026-08-31.**

The item as filed reads: *"`(case foo :bar 1 (:baz :qux) 2 3)` — expands to
individual comparisons at compile time"*, with the open question of **how to
tell whether a parenthesised value is the thing to match or a list of things to
match**. This document is that question's answer and its bill.

## 1. What the tree measured

Two facts decided the shape before any option was written down. Both come from
walking every `.nuc` in `src/`, `lib/`, `examples/` and `tests/`.

| Measurement | Value |
|---|---|
| `case` forms in the tree | 55 |
| …containing a run of adjacent arms with an identical result | 19 |
| Arms those runs would collapse | 44 |
| Largest single run | 12 (`src/type-utils.nuc`, the `TY-I1`…`TY-CHAR` integer-kind test) |
| `case` forms using a compound expression in a value slot | **0** |

**Element-shape heuristics are dead on arrival.** Of the 19 collapsible runs,
**17 are bare symbols** (`TY-STRUCT TY-UNION`, `NODE-FLOAT NODE-SYM`), 1 ints, 1
strings. So the tempting rule — "a list of literals is a set of values, a list
headed by a symbol is a call" — misreads the *dominant* use. Whatever separates
the two readings has to be syntactic and explicit; nothing about the elements
can carry it.

## 2. The wrinkle, stated precisely

The competitor is not a list *value*. Nucleus has no `(1 2 3)` literal — that
shape is already a diagnosed error (`case-clause-hint`, §4). The competitor is a
**call**: `(case x (+ 1 1) 10 3 20 99)` compiles today and yields `10`. So the
real question was whether to take an expression position away.

Three probes constrained the marker choice, each run against `build/nucleusc` at
stage16 head:

- `[1 2]` builds a real `(Vector i32)` and `#{…}` a real set. A container
  literal as the marker makes "compare the scrutinee *against* this vector/set"
  unspellable — the filed wrinkle in its worst form.
- `'(1 2)` is not inert data: it errors `quote needs the node runtime`. A quoted
  list *constructs a `Node` cons list at runtime*, and quote is already carrying
  the field-selector meaning from [dot-forms.md](dot-forms.md) §5.
- `(:or 1 2)` is **not** a syntax error either — it routes to `invoke` on a
  `Keyword`. No such method exists anywhere in the tree, so the shape is
  unclaimed in practice, which is what makes it available as a marker.

## 3. Options and the decision

| | Spelling | Cost |
|---|---|---|
| A | `(case foo :bar 1 (:baz :qux) 2 3)` — bare list | Permanently removes "a value slot is an expression". Escape becomes `((+ a b))` or a `let`. Zero in-tree breakage, but a *silent* misread survives wherever a call's head and args are same-typed: `(case x (f y) r d)`. Forces rewording `case-clause-hint`. |
| **B** | **`(case foo :bar 1 (:or :baz :qux) 2 3)` — keyword-marker head** | **5 characters. Takes nothing away; no escape hatch needed; parens stay calls everywhere; `case-clause-hint` stands verbatim. Matches the convention [keyword-markers.md](keyword-markers.md) just established.** |
| C | `'(:baz :qux)` — quoted list | Quote already means two other things here, and it lies: the elements must be *evaluated* as constants (`TY-STRUCT`) while quote says "don't". |
| D | `#{:baz :qux}` / `[:baz :qux]` | Reads best, costs most — see §2. |
| E | Leave `case` alone, add `(in? x v ...)` | No syntax decision, and `in?` is independently useful, but it does not answer the item and the 12-arm site reads worse. |

**Decided: B, marker `:or`.** The deciding argument is that the compiler already
ships a diagnostic defending "parens in value position is a call" — the Stage 15
W4d hint exists precisely because people write `(case x (0 body) (1 body))` out
of muscle memory. Under A that mistake becomes *half*-legal: the value slot
silently accepts `(0 body)` as the set {0, body} while the result slot still
errors, so the user gets an error whose text now contradicts the language. Under
B the wrong shape stays wrong and the right shape is unmistakable.

`:or` over `:any`/`:one-of`: the expansion *is* an `or` of `=`s, and the arm
reads as the disjunction it compiles to.

The grain-rub accepted with B: keywords are **values** in expression position and
**markers** everywhere else (`:rest`, `:where`, `:repr`), and a `case` value slot
is an expression position. It is the same trade `:repr tagged` took — one
convention, spelled the same way in every position that means "marker".

## 4. As built

Ten lines inside `case` in `lib/macros.nuc`, **no compiler change**. A value
slot that is a `NODE-CELL` whose head is a `NODE-KEYWORD` named `or` expands to
an `or` of one `=` per element; anything else expands exactly as before.

Two details worth keeping:

- **One result copy, not one per alternative.** `(case x (:or a b) r d)` becomes
  `(cond (or (= x a) (= x b)) r true d)`, not `(cond (= x a) r (= x b) r true
  d)`. Collapsing an arm-run therefore *shrinks* code rather than being an IR
  no-op, which is why §5's adoption is a real diff and not a reformat.
- **`when` is not callable from this macro body.** `case` is defined above
  `when` in `lib/macros.nuc`, and a macro body is compiled at *definition* time,
  so it sees only what precedes it. The shape test uses `cond` (a special form,
  always available) and `and` (defined above `case`). This is the same rule that
  keeps `die-at` out of macro bodies — the body is ordinary user-scope code.

Empty `(:or)` is `false` — it matches nothing. That is the identity of a
disjunction and matches every other variadic in the file (`(+)` → `0`, `(and)` →
`true`, `(or)` → `false`), so it needs no diagnostic; a macro body could not
raise a located one anyway.

**Verified**: enum symbols, integers and C strings as alternatives; a plain
parenthesised value still calls (`(case 2 (+ 1 1) 10 3 20 99)` → `10`); and the
W4d hint still fires verbatim on `(case x (0 "zero") (1 "one") "other")` — the
outcome the decision turned on. `examples/case.nuc` covers all three.

**Not built, by decision:** `in?` as a standalone macro (§3 option E — `or` of
`=` already names the semantic once), and nested `(:or …)` inside an
alternatives list.

## 5. Adoption in `src/`

19 sites, 5 files, **-32 lines** (`type-utils.nuc` -37, `type-mangle.nuc` -3,
`nucleusc.nuc` -2, `abi.nuc` -1, `nuch.nuc` merges two arms and their two
comments into one). Bootstrap converges, 935 tests, and the **committed boot
binary compiles it unchanged** — the prelude is read from `lib/macros.nuc` at
compile time, so a new macro needs no boot refresh to be usable in `src/`.

The rule applied was **collapse where the arms share a reason, not merely a
value.** The mechanical reading — merge every run of arms with identical results
— makes a handful of these tables *worse*, and five runs were left alone for
that reason, all in `type-utils.nuc`:

| Left as-is | Why |
|---|---|
| `type-size`: `TY-BOOL`/`TY-I8` → 1 | A width ladder (`i8` 1, `i16` 2, `i32` 4 …). The two agree by coincidence; merging breaks the column that is the table's whole point. |
| `type-size`: `(:or TY-CHAR TY-ERR)`/`TY-F32` → 4 | Char and Err are both i32-repr — one reason, merged. `f32` being 4 is a different fact, and merging it would break the float block below. |
| `type-size`: `(:or TY-USIZE TY-SSIZE)`/`(:or TY-STRUCT TY-UNION)` | Pointer-width ints are ptr-sized *definitionally*; an aggregate is ptr-sized as a deliberate conservative choice, which the comment between them explains. Merging strands that comment over half a run. |
| `is-int-type` and `is-unsigned`: the plain-integer run vs `TY-ERR`/`TY-CHAR` | The ordinary integers collapse to one arm; `Err` and `Char` each keep a line explaining why an i32-repr *non*-integer answers yes. A single 12-element `(:or …)` would orphan both comments. |

That last one is the shape to remember: a per-arm comment is a *reason*, and an
arm carrying one is not interchangeable with its neighbours even when it returns
the same value. `is-float-type` (5 arms → 1) and `is-ptr-like` (2 → 1) have no
such comments and collapse whole.
