# Container literal element types: keyword and symbol

Status: **DONE** (2026-08-16) — keyword elements, float hashing, symbol values
(tiers 1-2) and symbol literals (tier 3). 737 tests (was 721), `make bootstrap`
converges, abi/layout green. **Deferred by decision:** the quote-in-selector
ambiguity of §3.4(b), pending a larger field-access rethink.
Investigation measured against `build/nucleusc` at stage16 head; §6 records what
implementation found.

Today `[…]`, `#{…}` and `{…}` accept int, float and string elements only:

```
$ #{:foo :bar}
error: set literal elements must be scalar literals (int, float, or string)
```

**Conclusion up front: keyword is a reader-only change of about five lines;
symbol is a language design question with four independent blockers.** They are
not one item and should not be scheduled as one.

*(That was the investigation's conclusion and §1–§3 are its record. It did not
survive contact: three of the four "blockers" proved softer than the measurement
implied, and everything here shipped. Read §3.1, §3.3 and §3.5 before acting on
any claim in §1–§3.)*

## 1. Where the rule lives

Three functions in `src/reader.nuc`, ~25 lines total:

- `lit-elem-kind` (626) — node kind → coarse kind. `NODE-INT`→1, `NODE-FLOAT`→2,
  `NODE-STR`→3, anything else→0 (rejected).
- `lit-kind-type` (634) — coarse kind → **type spelling**: `"i32"`, `"f64"`,
  `"CStr"`. *(Now `lit-type-node`, returning a fresh type node — see §3.5.)*
- `infer-lit-type` (649) — walks a strided sub-sequence, enforces one kind
  across it, returns the spelling. *(Now returns the kind.)*

The three readers then build `(let ((g (ref (Coll E))) (alloca (Coll E))) …)`
with the elements spliced into `conj`/`assoc` forms, taking `E` from
`lit-kind-type` via `(lit-sym et)`.

That `lit-sym` is the load-bearing constraint: **the element type must be
spellable as a single symbol.** `i32`/`f64`/`CStr`/`Keyword` are; `(raw Node)`
is not.

## 2. Keyword: five lines

`Keyword` (`lib/keyword.nuc`) is already an interned value type conforming to
`Hash` and `Eq`, and `docs/collections.md` already documents keyword-keyed maps
as the idiomatic lightweight-key choice.

Measured — the *exact* expansion the reader would generate compiles and runs
today, for all three containers:

| Shape | Result |
|---|---|
| `(let ((g (ref (HashSet Keyword))) (alloca …)) (hashset-init g) (conj g :foo) (conj g :bar) g)` | `count=2` |
| `(HashMap Keyword i32)` + `assoc`/`match` | `b=2` |
| `(Vector Keyword)` + `conj`/`contains?` | `n=2 has-x=1` |

So the work is entirely in the reader:

1. `lit-elem-kind`: `(when (= (nn kind) NODE-KEYWORD) (return 4))`
2. `lit-kind-type`: `(when (= kind 4) (return "Keyword"))`
3. The four `"… (int, float, or string)"` diagnostics (reader.nuc 704, 753, 793,
   796) gain "or keyword".

No typing, codegen, library or lockstep work. `NODE-KEYWORD` already lowers to a
`keyword-intern` call in value position, which is why `(conj s :foo)` works
unchanged.

**The one wrinkle is the import.** The expansion names `Keyword`, so `#{:a :b}`
requires `(import-use keyword)` — a requirement `docs/types.md` already states
for keyword literals generally. The failure is well-diagnosed, not mysterious:

```
error: unknown type: Keyword — not defined anywhere in this compilation unit
  note: 'Keyword' is defined in lib/keyword.nuc, which no import in this unit reaches
```

Worth noting the asymmetry: `#{"a" "b"}` needs no `(import-use hash)` because
`hashset` reaches it transitively. A keyword literal is the first bracket literal
whose element type is not reachable from the collection import alone.

## 3. Symbol: four blockers, and a layering question

A symbol *value* today is `(quote foo)`, typed `(raw Node)`
(`src/generics.nuc:4988`). Each of the following is independently disqualifying:

1. **Bare `foo` cannot mean a symbol.** In `#{a b}`, `a` is a variable
   reference. Symbols must be written `'a`, which reads as the *list*
   `(quote a)` — so `lit-elem-kind`, which switches on a node's `kind`, cannot
   classify it at all. It needs a list-shape check. (This is the same ambiguity
   recorded in `stage888-deferred.md` under "Symbols for struct field access".)
2. **The element type is not a symbol.** `(raw Node)` is a compound type node,
   so `lit-kind-type`'s "return a spelling for `lit-sym`" contract breaks. The
   builder would need a type-*node* return, touching all three readers.
3. **Nullability refuses it.** Measured — `(conj v (quote a))` on a
   `(Vector (raw Node))`:
   `error: argument: raw pointer where non-null (ref ...) is required`.
   A raw pointer is nullable; the collections want non-null.
4. **No `Hash`/`Eq` for Node or ptr.** `lib/hash.nuc` extends `i32`, `i64`,
   `usize`, `CStr` only. Sets and map keys are dead without a conformance;
   vectors need `Eq` for `contains?`.

Past those, a symbol literal drags `Node`/arena into the artifact of any program
that writes one — the concern `compile-time-imports.md` measures.

### 3.1 What the Lisps do — and the claim it retires

An earlier draft of this section called the design question a **semantic fork**:
that an interned `Symbol` type would make `'foo` mean a `Node` in macro position
and a `Symbol` in literal position, one syntax with two meanings resolved by
context. **That framing was wrong, and checking it against the prior art is what
retires it.** Recorded here because it is the kind of claim that otherwise gets
inherited by the next design doc.

Common Lisp, Scheme and Clojure have no such duality. A symbol is an ordinary
first-class runtime value and `'foo` means the same thing in every position:

| | Symbol identity | Macro layer sees | Keywords |
|---|---|---|---|
| Common Lisp | Interned per package; `(eq 'foo 'foo)` → `T` | Ordinary conses and symbols | A symbol in the `KEYWORD` package that self-evaluates — not a separate type |
| Scheme | Interned by the reader; `(eq? 'a 'a)` → `#t` | Plain data (`syntax-rules`) or syntax objects (`syntax-case`) | None in the core |
| Clojure | Compared by value (ns + name), not by pointer | Plain data — lists, symbols, vectors | Interned in a global table, so identity-comparable |

In CL a symbol carries a name, a package, a value cell, a function cell and a
plist, and it is the *same object* whether it arrives as a macro argument or is
stored in a hash table at run time. `gensym` returns an **uninterned** symbol —
same type, absent from any package, which is exactly what makes it uncapturable.

Clojure is the useful one for us: it declined CL's symbol interning and then
recovered the ergonomics with keywords, which *are* globally interned. That is
why Clojure idiom reaches for `:foo` as a map key — the same rationale
`docs/collections.md` arrived at independently for `Keyword`.

**The one real duality in the prior art is Scheme's `syntax-case`,** whose macros
operate on *syntax objects* wrapping a datum with lexical context and source
location, bridged by `syntax->datum` / `datum->syntax`. Two properties matter
here: it exists to carry **hygiene**, not because the AST needed a different
representation (the plain symbol is still inside, retrievable), and the
conversion is **explicit and named**, never inferred from position. `syntax-rules`
hides it entirely. So even the one two-type system in the family does not fork a
syntax by context — which is the specific thing the retired claim asserted was
unavoidable.

### 3.2 The question that is actually open

Clojure's *architecture* is the relevant comparison. Its reader produces symbols
and persistent collections; its compiler then analyses those into its own `Expr`
tree. Clojure therefore has two representations too — but **macros only ever see
the first**, and the compiler's AST is invisible to user code.

Nucleus inverted that: macros traffic in `Node`, the compiler's own structure,
carrying `kind`, `car`/`cdr` and `line`. So the open question is not "may `'foo`
mean two things" but **"should the macro layer traffic in the compiler's node
type at all"** — and all three languages answer no.

Three options follow, in ascending cost:

1. **Do nothing.** `Keyword` already covers "an interned name used as a key",
   which is most of what symbols-in-collections is *for*. The gap is narrower
   than it looks.
2. **Make `Node` respectable as a value** — the CL/Scheme one-type answer.
   Nucleus symbols are *already* interned (`intern-symbol` returns a canonical
   pointer), so identity equality already holds; blockers 2–4 above are all
   "nobody extended it" rather than anything structural. Cheapest real path.
3. **A separate `Symbol` value type** — Clojure's answer — with an explicit
   projection at the macro boundary rather than positional overloading.

**`lib/keyword.nuc` is already a symbol type.** Intern table, cached hash,
id-compare equality, `Hash` + `Eq` — structurally what `Symbol` needs. In CL's
terms Nucleus has the `KEYWORD` package and no other, and options 2 and 3 are
largely a re-parameterisation of that same machine. CL's model argues the two
should be **one type distinguished by interning scope**, not two types.

So the cost that decides this is not semantic. It is that every option except
the first drags `Node`/arena into the artifact of any program naming a symbol —
the same dependency [compile-time-imports.md](compile-time-imports.md) measures.
**The two items want deciding together.**

*Confidence: the CL and Scheme rows are solid. The Clojure row is stated at the
level that is certain — symbols compare by value, keywords are globally interned;
the precise `identical?` behaviour for symbols across reads was not verified
against a REPL and should be before anything depends on it.*

### 3.3 Tiers 1–2 landed (2026-08-16) — and most of §3 dissolved

**Decision taken:** "make `Node` respectable as a value", on the grounds that the
compiler itself deals in symbols and further string→symbol refactoring is
planned. The compiler already links `Node`/arena, so the artifact-size cost that
shaped the other options does not apply to its own use.

Implemented (733 tests, was 728; `make bootstrap` converges; abi/layout green):

- **Tier 1** — `hash` over `(ref (ref Node))` in `lib/hash.nuc`, FNV-folding the
  canonical pointer.
- **Tier 2** — `quoted-datum-type` (`src/nucleusc.nuc`), called by **both**
  `emit-quote` and `node-type`'s quote arm, plus a `ty-ref-node` beside
  `ty-raw-node`.

Three of the four blockers in §3 were softer than measured, and it is worth
recording why, because the measurement was not wrong — the *inference* from it was:

- **Blocker 4 was half a blocker.** `=` on `(ref Node)` already worked; only
  `hash` was missing. And it needs **no `extend`** — `(extend (ref Node) Hash)`
  is refused (`'ref' is not a struct template`), but a bare overload resolves on
  its own. The conformance record only feeds `&where` bounds.
- **Blocker 3 was a typing artifact, not a value property.** `emit-quote` stamped
  `(raw Node)` on every quote, but `'foo` lowers to `intern-symbol`, whose
  signature returns `ref:Node`. The pessimism was in the compiler, not the value.
  Typing it honestly is the fix; no laundering is involved.
- **Blocker 2 never applied to the compiler's use case** — it is a *reader*
  constraint, and the motivating use (`(HashMap (ref Node) V)` in compiler code)
  writes its types out longhand.

The typing rule is **conditional on the quoted datum**, and that is the part
worth guarding: only `NODE-SYM` becomes non-null, because `'(a b)` builds cells
and `'()` **is** null. A blanket flip would type null as non-null and the flow
checker would stop catching it, silently. `run_s16_symbol_values` pins both
directions, and non-null narrows into a `(raw Node)` slot so no prior spelling
broke.

### 3.4 What tier 3 now requires

Two things, and the second is the interesting one.

**(a) The spelling problem, as predicted.** `lit-kind-type` returns a spelling
the readers stamp with `lit-sym`, and `(ref Node)` is not a single symbol. It
becomes a type-*node*-returning helper across the ~6 build sites, each needing a
fresh node per position. Plus `lit-elem-kind` needs a list-shape check, since
`'a` reads as `(quote a)` rather than an atom. Mechanical.

**(b) A wart tiers 1–2 exposed, which tier 3 would sharpen.** In head position a
selector is resolved as a field name first, and **the quote is silently
stripped**: measured, `(m 'count)` on a `(HashMap (ref Node) i32)` returns
`HashMap`'s `count` field. Not an error — a wrong answer. `(invoke m 'k)` is the
working spelling.

That is tolerable today because symbol keys are newly possible and rare. Ship
`#{'a 'b}` and `(m 'k)` becomes the obvious thing to write next to it, so the
wart moves from "obscure" to "on the happy path".

The principled fix is narrow and is the disambiguation
`stage888-deferred.md` asks for under "Symbols for struct field access": **an
explicitly quoted symbol is a value, never a selector.** A `(quote sym)` node in
selector position should suppress the field-name interpretation rather than be
stripped to its inner symbol. That is a strictly-narrowing change — it can only
affect sites that write `(x 'field)`, which today silently mean `(x field)` —
but it is a head-position semantics change, so it wants its own item, its own
A/B IR diff over the examples, and to land *before* tier 3 rather than with it.

### 3.5 Tier 3 landed (2026-08-16); the ambiguity deferred

Done as sketched in §3.4(a); 737 tests (was 733), bootstrap converges,
abi/layout green. `#{'a 'b}` / `['a 'b]` / `{'k 1}` infer `(ref Node)`.

**(b) was deliberately NOT taken.** Field access is due a larger rethink, so
fixing the quote-in-selector-position wart inside this item would have pre-empted
that design. The consequence is live and documented rather than hidden: symbol
map lookup must be spelled `(invoke m 'k)`, and `(m 'k)` silently reads a field.
`examples/symbol-keys-test.nuc` says so at the point of use and
`docs/collections.md` §"Symbols as keys" states it as a rule. **When field access
is redesigned, that is the constraint to carry forward** — an explicitly quoted
symbol should be a value, never a selector.

Two implementation notes worth keeping:

- **`infer-lit-type` returns a KIND now, not a spelling** (`!i32`, not `!ptr`),
  and `lit-kind-type` became `lit-type-node (kind line)` returning a fresh type
  *node*. Both changes are forced by the same thing: `(ref Node)` is compound, so
  there is no spelling for `lit-sym` to stamp. Returning the kind also removed
  the string round-trip the old shape needed.
- **A fresh node per position is load-bearing**, not defensive. The readers stamp
  the element type into both the `ref` binding and the `alloca`; the old code
  built two `(lit-sym et)` calls for exactly this reason and the comment said so.
  `lit-type-node` preserves it by constructing on every call.

Admission is a **shape** check (`lit-is-quoted-sym`: a 2-element `NODE-CELL`
headed by the symbol `quote` with a `NODE-SYM` argument), not a kind check —
every other element kind is one node-kind test. That is why its neighbours stay
refused, each pinned: `'(a b)` (quoted list), `'1` (quoted int), bare `a`
(variable reference), `(f x)` (call).

## 4. Two adjacent findings

**`#{1.0 2.0}` is already broken.** Floats are a documented element kind, but
`f64` has no `Hash` conformance:

```
lib/hashset.nuc:200: error: no matching method for overloaded 'hash' with argument types (ptr:f64)
```

`[1.0 2.0]` works — a vector needs no hash. So the "int, float, string" rule is
already one kind too generous for sets and maps, and `#{…}`/`{…}` should either
gain `(extend f64 Hash)` or refuse floats with a diagnostic that says why. This
is untested territory: no example program covers a float set.

**A stale comment.** `infer-lit-type`'s header claims "integer width is promoted
to i64 if any examined integer overshoots the signed-32 range" and that it can
return `"i64"`. Neither is true — `lit-kind-type` has no i64 row, and
`lit-elem-kind`'s own comment says the promotion is *deliberately* not done
because `(cast i64 bigval)` on an i32-typed literal truncates. The two comments
contradict; the second is correct.

## 5. Recommendation

Take keyword now, as its own change: five lines, three doc sentences
(`docs/collections.md` §element-type inference), one example program extended,
and the mixed-kind diagnostics updated. Fix the `f64`-in-a-set hole in the same
pass, since it is the same table.

Leave symbol until the layering question in §3.2 is decided — and decide it
alongside `compile-time-imports.md`, since the cost that separates the options is
the `Node`/arena dependency rather than anything about symbols. It is not
expensive *after* that decision and cheap-looking *before* it, which is the
combination worth being careful about.

## 6. What implementation found

Both halves landed as estimated; nothing in §1–§4 needed revising.

**Keyword** was the predicted three edits in `src/reader.nuc` — a `NODE-KEYWORD`
row in `lit-elem-kind`, a `"Keyword"` row in `lit-kind-type`, and the four
diagnostics. No typing, codegen or library work, and no `node-type`↔`emit-node`
lockstep exposure: nothing here is a special form.

**Float hashing** needed one thing §4 did not anticipate: the language has no
bitcast operator (`src/nucleusc.nuc:1826` mentions one only in a comment about
matching clang's float formatting). `(as i64 x)` converts the *value*, which
would fold every float with the same integer part to the same hash. The receiver
solves it for free — `hash` already takes `(ref f64)`, so the bits come back
through `(deref (unsafe/cast ptr:i64 self))`, a pun through a pointer the caller
already had to materialise. `f32` gets the same treatment through `ptr:i32`.

The one correctness case is `-0.0`: it is `=` to `0.0` but differs in bits, so
zero normalises to the `+0.0` pattern or a `-0.0` key is silently unfindable.
Pinned in `examples/hashset-lit-test.nuc` (`zcount=1`, `find-neg=1`). `NaN`
deliberately gets no special case — it is `=` to nothing including itself, so a
`NaN` key is unfindable whatever it hashes to; that is an equality property, not
a hashing bug, and pretending otherwise would need `hash` to lie.

**The refusal surface got its first tests.** §1 recorded that no fixture covered
container-literal errors at all. `run_s16_keyword_literal_refused` now covers the
four mixed-kind paths, the quoted-symbol refusal (which pins §3 as a *diagnostic*
rather than a crash), and the missing-`(import-use keyword)` case — the last
being the one that matters, since an unresolved `Keyword` inside a reader-generated
expansion reads as a compiler bug unless the note names the file.
