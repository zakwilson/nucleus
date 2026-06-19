# Collections cleanup (pre-string)

Four ergonomic/feature gaps surfaced while writing the Stage 11 collection
libraries and their tests. This doc is the **source of truth** for the cleanup
work; the implementation prompt is `design/stage11/cleanup-prompt.md`.

Each item below records the original observation, what was actually found when it
was investigated against the current tree, the root cause, and the recommended
approach. Findings were verified by compiling throwaway `.nuc` programs with the
boot-rebuilt `bin/nucleusc` (LLVM 19 host); the relevant evidence is noted inline.

---

## 1. Sugared parametric binding form — `name:(ref (Vector T))`  ✅ DONE

**Status:** Implemented in `lib/reader.nuc` (`fuse-colon-paren`, called from
`read-list`). In list (binding) context, a freshly-read symbol whose spelling
ends in `:` and is immediately followed by `(` (no whitespace, no token peeked
ahead) is fused into `(name <paren-form>)` — the exact shape
`extract-name-and-type` already accepts. Verified byte-identical to the list-form
spelling (IR diff is only the module-id header) in both parameter and `let`
positions; `make test` (83) and `make bootstrap` (fixed point) both pass without
re-baselining `boot/` (no current source uses the new form, so compiler output is
unchanged). Docs: `docs/types.md` §Type Syntax (Colon-paren binding sugar) and
§Function Pointer Types.

**Original:** List form is required with parametric types. A sugared form like
`name:(ref (Vector T))` would be nice. The reason for the current limitation is
probably that an open-paren unconditionally starts a new list, but desugar
already has special handling.

**Finding (confirmed real).** The colon is an ordinary symbol character
(`is-sym-char` in `lib/reader.nuc` does not exclude `:`), so `name:type` lexes as
**one** atom token and the type-splitting (`split-typed` / `extract-name-and-type`
in `src/nucleusc.nuc`) only ever operates *within* a single symbol token. When you
write `name:(ref (Vector T))`, the lexer emits the atom `name:` and then a
separate `(ref ...)` list, and nothing rejoins them.

**The target form already exists.** `extract-name-and-type` already accepts the
list binding `(name (ref (Vector T)))` (it has a `NODE-CELL` arm that parses the
type via `parse-type-from-node`). So the sugar is a pure reader rewrite to the
form the compiler already handles — exactly the "desugar already has special
handling" intuition.

**Fix.** In the reader's list-reading path, when an atom token ends in `:` and is
**immediately** (no intervening whitespace) followed by `(`, fuse them into the
list node `(name <paren-form>)`. Localised to the reader; additive (no current
source writes a trailing-colon atom adjacent to a paren). Must re-converge the
byte-identical bootstrap because it touches the reader, but behaviour is unchanged
for all existing source.

**Scope:** small. **Priority:** cosmetic — nice-to-have, lands opportunistically.

**Accept:** `(defn f:i32 (v:(ref (Vector i32))) ...)` and a `let` binding
`(let (v:(ref (Vector i32)) init) ...)` both compile, identically to their
list-form spellings; `make bootstrap` stays byte-identical.

---

## 2. Keyword type — `:foo` (and the keyword/string overlap)  ✅ DONE

**Status:** Implemented. `lib/strview.nuc` is the shared, self-contained
`StrView` substrate (immutable `{data:(ptr ui8), len:usize}`; `len`/`eq`/`hash`
reusing `lib/hash.nuc`'s `fnv1a-byte` fold + a `CStr` bridge; `Hash`/`Eq`
conformances). `lib/keyword.nuc` builds the interned, self-evaluating `Keyword`
on top (256-entry linear-scan intern pool; identity `Eq`, cached `Hash`). The
reader recognises a leading-colon atom (`TOK-KEYWORD` → `NODE-KEYWORD`); the
compiler lowers `:foo` to a synthetic `(keyword-intern "foo")` call. `:foo`
self-evaluates, `(= :foo :foo)`/`(= :foo :bar)` behave, and a keyword is a usable
`HashMap` key (`examples/keyword-test.nuc`). `make test` (86) and `make bootstrap`
both pass; the boot binary and the new compiler emit byte-identical IR for the
compiler source (keyword/StrView are inert until used). A second compiler change
fell out: `emit-extern` now dedups an extern symbol re-declared by two imported
libs (a latent LLVM "redefinition of global"). See `design/stage11/progress.md`
§"Cleanup §2" for the full decision record; docs in `docs/types.md` (Keyword) and
`docs/collections.md` (keywords as keys).

**Original:** A keyword type would pair well with HashMap. Like most Lisps, a
keyword is a symbol that starts with a colon and always evaluates to itself.

**Finding.** Genuine new feature, not sugar. Today `:` is a plain symbol char, so
`:foo` lexes as the symbol `":foo"` and fails to resolve in value position. A
keyword needs four pieces:

1. **Reader** — recognise a leading-colon token as a keyword literal node.
2. **Representation** — an **interned, immutable** name; equality and hash are
   cheap (identity / cached).
3. **Self-evaluation** — `:foo` emits/loads the canonical keyword object.
4. **`Hash` + `Eq` conformances** — the whole point is ergonomic `HashMap` keys.

### Keyword/string overlap — examined

The assumption that keyword and `String` (M6) overlap is **partly** true, and the
honest shared core is narrow. They differ where it matters:

| | Keyword | String (M6) |
|---|---|---|
| Lifetime | interned, immutable, process-lived | owned, growable, `Drop`-freed |
| Equality | identity (pointer/id) | byte/codepoint value compare |
| Storage | one canonical copy in an intern pool | its own `Vector u8` buffer |

Forcing keyword to *be* a String (owned/growable) would be wrong, and pulling the
full UTF-8 / `Char` / codepoint machinery into keyword would over-scope it
(keyword names are effectively identifiers). **But** there is a real, reusable
substrate underneath both — and it is the same substrate `string.md` already
selected ("Rust's approach: a thin wrapper over a byte vector"):

> **`StrView` — an immutable, non-owning UTF-8 byte slice: `{ data:(ptr u8),
> len:usize }`.** Length-prefixed (not NUL-terminated) so it generalises to
> sub-slices and embedded NULs. Operations: `len`, byte equality (`memcmp`), byte
> hashing, a `CStr` bridge (to/from), and (later) codepoint iteration.

- **Keyword** = an *interned handle* whose payload is a `StrView` into an intern
  arena; identity eq + a cached hash, with `StrView` available for printing and
  first-intern. The **intern pool** is keyword-specific.
- **String** (M6) = an *owned, growable* `Vector u8` that lends a `StrView` over
  its buffer (`as-str`) for hashing/eq/iteration, and adds mutation + the `Char`
  / codepoint layer on top.

So the byte hashing and equality already partly exist and should be **shared, not
duplicated**: `lib/hash.nuc`'s `fnv1a-byte` / `fnv1a-int` fold bytes (the `CStr`
conformance already folds to NUL), and that is exactly what a length-counted
`StrView` hash needs. Build the `StrView` substrate as its own self-contained lib
(`lib/strview.nuc`, following `lib/allocator.nuc`'s single-file convention),
seeded by the existing FNV byte fold, and have keyword import it. M6 String then
imports the **same** substrate rather than reinventing a byte/eq/hash layer.

**Explicitly keep out of keyword (defer to String's doc):** ownership/growth,
mutation, and the full `Char` / UTF-8 codepoint-iterator surface. Keyword needs
only: bytes in, identity, hash, eq, print.

**Scope:** moderate, cross-cutting but contained. **Priority:** do with or just
after M6 String — most valuable once the shared substrate exists, and it gives
`HashMap` ergonomic keys.

**Accept:** `:foo` self-evaluates; `(= :foo :foo)` is true and `(= :foo :bar)`
false; a keyword is usable as a `HashMap` key (`{:a 1 :b 2}` once the reader's
map-literal inference learns the keyword element type, or via the explicit
constructor); the `StrView` substrate is a separate importable lib that M6 String
can reuse for its byte/hash/eq layer; bootstrap byte-identical (keyword/StrView
are inert until used).

---

## 3. Multi-binding `let` in iterator-test — already supported

**Original:** `iterator-test.nuc` has a bunch of nested `let`s. Why isn't this a
single `let` with multiple bindings?

**Finding (premise is mistaken).** `let` **already** supports multiple bindings.
`emit-let` consumes a flat, even-length binding list and iterates name/value pairs
by index; `extract-name-and-type` accepts **both** `name:type` and the list form
`(name type)`. A single flat `let` mixing the two forms compiles and runs:

```lisp
(let ((a (ref A)) (alloca A)
      (b (ref B)) (alloca B)
      n:i32 7)
  ...)        ; verified: prints 14 = 3 + 4 + 7
```

The nested `let`s in `iterator-test.nuc` are **stylistic, not forced** — the
allocas are independent; the `memcpy` dependencies live in statement position
*after* the bindings, so all of them collapse into one binding list.

**Action:** flatten `examples/iterator-test.nuc` to a single `let` (no language
change). Add a one-line note to the docs that the list binding form composes in a
multi-binding `let`, since it was not obvious to the test's author.

**Scope:** trivial. **Accept:** flattened example produces byte-identical output;
its `.out` fixture is unchanged.

---

## 4. Generic iterators — one implementation per element type

**Original:** Iterator has a separate implementation for every element type.
That's ridiculous. The compiler knows the collection's element type; it should be
possible to template them as `&where (Any T)`. If not, there is a missing feature.

**Finding (complaint valid; the suspected missing feature is real).** Probed
against the current tree:

- A **basic** generic iterator parametric on one element type **works today**:
  `(defstruct (Once E) val:E done:i32)` + `(extend (Once E) (Iter E))` + `match`
  on `(Maybe E)` compiles and runs. So the simple case is not blocked.
- The **realistic combinator** shape breaks. A generic `MapIter` must thread the
  *source's* element type `S` and the *result* type `E` as separate type
  parameters — precisely because there are **no associated types** to ask "what
  does iterator `I` yield?". Those extra parameters are **phantom** (not stored in
  any field), and the monomorphiser mishandles multi-parameter templates with
  trailing phantom params:
  - `(defstruct (MapIter I F S E) source:I f:F)` + a `next` method using `S` in
    its body → **`error: unknown type: S`** at stamp time.
  - A reduced `(defstruct (Two I F S E) a:I b:F)` with a method using phantom `S`
    → **the compiler segfaults** (exit 139).

This is two distinct gaps:

**4a — phantom/positional tyvar recovery is broken (a bug). DONE.** Multi-param
templates whose trailing type params do not appear in any field cannot be
recovered during method monomorphisation (`unknown type` at best, segfault at
worst). At minimum the **segfault must become a clean diagnostic**. Fixing the
recovery would also unblock *verbose-but-single-implementation* generic
combinators — you thread explicit `S`/`E` params (ugly, but one impl instead of
N). This is the near-term, isolated fix. **Implement it in this pass.**

*Resolution:* the recovery machinery (`unify-tpat` recursing positionally on a
stamped struct's `origin-args`) was already correct — it binds every receiver
type-argument, phantom params included. The actual bug was an **arena buffer
overflow** in `register-generic-defn`: the `tyvars` array was sized
`nc + nparams + 1` ("one tyvar per parameter"), but a *single* receiver parameter
applying an N-arg template (`(ref (Two I F S E))`) contributes one tyvar per
type-argument. With `nparams = 1` and four receiver tyvars the array (size 2)
overran into adjacent arena memory: one phantom param corrupted a pointer
(`unknown type: S`), two corrupted enough to segfault — a textbook
size-by-the-wrong-quantity overflow. Fix: size the array by the **node count** of
each parameter/return type pattern (a safe upper bound on collectible tyvars, via
the new `count-pattern-nodes` helper), in both `register-generic-defn` and
`defn-has-receiver-tyvars`. The recovered bindings then flow through the unchanged
`generic-method-bind` → `generic-instantiate` → `monomorphize-form` path. Verified
byte-identical: the compiler emits identical IR for its own source and all 69
examples before/after the fix (it uses no phantom-param generic methods itself),
so no `boot/` re-baseline was needed. See `examples/phantom-tyvar-test.nuc`.

**4b — associated types (the proper fix).** Let `(Iterator E)` expose its element
type so a combinator is parametric only on the concrete iterator/function types
and *derives* `E`, eliminating the phantom params entirely. This is the deferred
"parametric-protocol `&where` / associated-types frontier" already recorded in
parametric-structs *Known limitations #3*. It is a real language-design effort,
not a focused fix. **Write a design doc for it in this pass; do not implement.**

**Residual constraints to record (independent of 4a/4b):**

- `&where` cannot name a *parametric* protocol — the parser requires
  `(Protocol Var)` with plain symbols (see `register-generic-defn`,
  "each &where constraint must be (Protocol Var)"). So a generic `reduce` bounded
  on a parametric function-object protocol would rely on stamp-time structural
  checks (worse error messages) rather than an explicit bound.
- `(Maybe ptr)` is niche-encoded (nullable pointer), so a **pointer** element type
  cannot use `match` — non-pointer element types only (M2 limitation #1).
- On the original `&where (Any T)` phrasing: `Any` is a no-op bound and is **not**
  the unlock. The blockers are associated-type derivation (4b) and the
  phantom-param recovery bug (4a), not the bound.

**Scope:** 4a medium/isolated; 4b large (design only this pass). **Accept (4a):**
the segfault case compiles to a clean error or (better) works; a verbose generic
`MapIter` threading explicit `S`/`E` params compiles, monomorphises, and runs;
bootstrap byte-identical. **Accept (4b):** `design/stage11/assoc-types.md` exists,
is referenced from `design/overview.md`, and specifies the surface syntax,
stamping, and conformance-checking changes — implementation deferred.

---

## Recommended sequencing

| Item | Effort | When |
|---|---|---|
| 3 — flatten example + doc note | trivial | now |
| 1 — colon-paren reader sugar | small | now / opportunistic |
| 4a — fix phantom-param crash (→ diagnostic + verbose-generic combinators) **DONE** | medium, isolated | before/alongside String |
| 2 — keyword type on a shared `StrView` substrate | medium | with/after M6 String |
| 4b — associated types (design doc only) | large (design) | own doc, post-String |
