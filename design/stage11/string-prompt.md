# Implementation prompt — Stage 11 M6 String

You are implementing **Stage 11 M6: the `String` type, the string protocols, and
the `Char` scalar** for the Nucleus self-hosting compiler. The specification is
**`design/stage11/string.md`** — it is the source of truth, including the Robot
design evaluation (§1–§5), the protocol shapes, and the resolved decisions table.
When this prompt and that doc disagree, the doc wins; if you think the design is
wrong, **stop and raise it** rather than silently diverging.

The shape (string.md §3): three read layers plus an owning type —
**`ByteStr` ⊂ `Str` ⊂ `String`** — over the existing borrowed `StrView` substrate
(`lib/strview.nuc`) and a `Vector ui8` buffer. The hard prerequisite is a **new
built-in `Char` scalar** (S0); everything else is library work on top of it, the
associated-type machinery (already shipped), and `Vector`.

Do the tasks in the §4 order. **S0 is the critical path** — a real compiler
addition that gates the `Char` library, codepoint iteration, and `push-char`/
`char-at`. Treat it like `usize`/`ssize` before collections.

---

## 1. Required reading (do this first, do not skip)

1. **`design/stage11/string.md`** — the spec (layering eval §1–§5, `Str`/`ByteStr`/
   `Char`/`String` method lists, the decisions table, the errors).
2. **`design/stage11/collections.md`** — the memory model `String` inherits:
   `Allocator`/`AllocHandle`, `Drop`/`with`, escape-taint on owned collections,
   `usize` indices, the `Iterator`/`into`/`doseq` story.
3. **`design/stage11/assoc-types.md`** + **`examples/assoc-iter-return.nuc`** — the
   associated-type machinery and the **proven value-return associated-iterator
   pattern** (`chars:CharI` / `bytes:ByteI` follow it; string.md eval §2).
4. **`CLAUDE.md`** (repo root) — workflow rules. Not optional.
5. **`context/local.md`** — the mandatory subagent-delegation workflow + subagent
   list.
6. **`context/build.md`**, **`context/macros-jit.md`**, **`context/repl.md`** —
   build flow, reader/JIT/macro mechanics (S0 reader work), REPL guidance.
7. Conventions you'll mirror / touch:
   - **`CStr` is the model distinct scalar for S0.** `src/nucleusc.nuc`:
     `TY-CSTR` in the type-kind enum (~:76), `ty-cstr` global (~:515),
     `make-type` init (~:941), `type-to-ir` (~:968), C-type string (~:998),
     `type-size` (~:1037), the `parse-type` name→type table (~:1834). Add a `Char`
     scalar (32-bit, over `ui32`) by the same pattern; IR `i32`, C `uint32_t`,
     size 4.
   - **`lib/reader.nuc`** — `lex-atom` (~:186), `next-tok` (~:244), the keyword
     literal path (~:643) — the model for lexing char literals `\a` / `\newline` /
     `\u{1F600}`. **Reconcile the existing byte-only `(char "x")` form**
     (`src/nucleusc.nuc:~11022`): it stores one byte in an int field; decide keep
     vs supersede.
   - **`lib/strview.nuc`** — the borrowed `{data,len}` substrate (byte `len`/`eq`/
     `hash`, `CStr` bridge). The byte/codepoint read layer (S3) extends this; do
     **not** duplicate `lib/hash.nuc`'s `fnv1a-byte`.
   - **`lib/vector.nuc`** — `String` wraps `(Vector ui8)`; reuse its growth,
     capacity, `AllocHandle`, and `Drop`.
   - **`lib/numeric.nuc`** — `Eq`/`Ord`; the `FromStr` conformances (S5) live here-
     adjacent so they ship with the scalars.
   - **`lib/error.nuc`** + **`docs/errors.md`** — `deferror` / `!T` / `try` for the
     bounds/validation errors.

---

## 2. How to work (process — enforced by CLAUDE.md)

- **Delegate; do not implement everything in the orchestrating thread.** Plan the
  split, dispatch each task (or sub-chunk) under ~100K tokens:
  - **`systems-impl-engineer`** — the `Char` scalar + char-literal reader (S0) and
    the protocol/error scaffolding (S2). Compiler/reader internals.
  - **`focused-task-implementer`** — well-specified library code once shapes are
    pinned (the `Char` UTF-8 lib S1, the `StrView` read layer S3, the `String` type
    S4, `split`/`trim`/`parse` S5).
  - **`build-test-runner`** — `make test` / `make bootstrap`, after every task.
  - **`api-docs-writer`** — `docs/` (a new `strings.md` + updates) and the progress
    tables.
  - **`Explore`** / **`general-purpose`** — read-only research so file reading stays
    off the main thread.
  Ask subagents for **concise summaries**, not file dumps.

- **Keep it green at every step.** After each task, `make test` passes and
  `make bootstrap` is a **byte-identical fixed point**. S0 is additive (no current
  source uses char literals or `Char`), so it must keep the bootstrap byte-identical;
  S1–S5 are new libraries inert until used. A bootstrap diff after S0 means the
  reader/type change touched existing tokens — investigate before proceeding.

- **Update docs and progress as a required closing step:** a `docs/strings.md` (the
  `Char` scalar + literals, `ByteStr`/`Str` protocols, `String` API, `parse`);
  `design/stage11/progress.md` (M6 row); fix root causes, only add a `context/` note
  for a genuinely unfixable environment gotcha.

---

## 3. Verify the ground before you build

The committed `bin/nucleusc` may link a newer libLLVM than the container ships; if
it fails to exec (126/127), rebuild from committed IR with `make boot-binary`
(or `make ensure-boot`) first. Then confirm the prerequisites with throwaway
`.nuc` files:

- **Associated-type protocol methods work** — re-run `examples/assoc-iter-return.nuc`
  (the `chars`/`bytes` uplift depends on it).
- **`StrView` + `Vector ui8` are healthy** — a `(Vector ui8)` builds/grows/drops, a
  `StrView` over its buffer `eq`/`hash`es.
- **No `Char` scalar exists yet** — `(cast Char 65)` / a `\a` literal fails to
  parse today (so S0 is genuinely new). Confirm before writing S0.

If any premise differs from string.md, **stop and report**.

---

## 4. What to build (in order)

### S0 — `Char` built-in distinct scalar + char literals (compiler; critical path)
- Add a **distinct 32-bit scalar `Char`** over `ui32` (model on `TY-CSTR`; see §1):
  IR `i32`, C `uint32_t`, size 4, `parse-type` name `"Char"`. Keep it **distinct**
  for dispatch (`=`/`!=` on two `Char`; `Char`-vs-int overloads); `cast` Char↔ui32
  is a same-width reinterpret (no IR), but `type-eq` must NOT collapse them.
- **Char literals** in the reader: `\a` (printable scalar), `\newline` + the named
  control codes, `\u{1F600}` (hex codepoint; reject surrogates / >0x10FFFF). Model
  on keyword lexing; emit a `Char`-typed literal value. Reconcile/supersede the
  byte-only `(char "x")` form.
- *Accept:* `\a`, `\newline`, `\u{41}` are `Char` values; `(= \a \a)` true,
  `(= \a \b)` false; `(cast ui32 \A)` = 65; `make bootstrap` **byte-identical**
  (additive); a focused example + `.out`.

### S1 — `Char` library: UTF-8 + classification (depends S0)
- `(defstruct DecodeResult ch:Char nbytes:usize ok:i32)`; `char-utf8-len`,
  `char-encode-utf8`, `char-decode-utf8 → DecodeResult`; `char-to-u32`,
  `char-from-u32 → !Char` (`invalid-codepoint`); ASCII classification
  (`char-is-ascii?`/`-digit?`/`-alpha?`/`-alnum?`/`-whitespace?`) + total
  `char-ascii-upper`/`char-ascii-lower`. **UTF-16 is out (stage888).**
- *Accept:* UTF-8 round-trips for 1–4-byte codepoints; invalid/truncated bytes give
  `ok=0`; surrogate `char-from-u32` errors.

### S2 — `ByteStr` + `Str` protocols + errors (depends S0)
- `(deferror str-index-out-of-bounds …)`, `invalid-char-boundary`, `invalid-utf8`,
  `invalid-codepoint`.
- `(defprotocol (ByteStr ByteI) …)` and `(defprotocol (Str CharI) …)` exactly per
  string.md (read-only; `Str` extends **`Eq` only** — eval §1; the `at`/slice ops
  return `!T`; `chars`/`bytes` are the associated-iterator protocol methods).
- *Accept:* the protocols compile; a trivial conformer (e.g. `CStr` — O(n)
  `byte-len`, no embedded NULs) satisfies the required methods.

### S3 — `StrView` read layer: byte/char iterators + slicing (depends S0, S2)
- On `lib/strview.nuc`: a `ByteIter` (`Iterator ui8`) and a `CharIter`
  (`Iterator Char`, UTF-8 decode via S1); `char-count` (O(n)), `char-at:!Char`
  (O(n)), `byte-at:!ui8`, `as-view`, `sub-bytes:!StrView` (bounds + boundary
  checks), `byte-find`, prefix/suffix/contains, `trim*`. `StrView` conforms
  `ByteStr`/`Str`/`Eq`/`Ord` (byte-lexicographic). This layer is **shared by
  `String`** via `as-view`, so bake in no owning assumptions.
- *Accept:* iterate the codepoints/bytes of a multi-byte `StrView`; nth-char past
  the end errors `str-index-out-of-bounds`; `sub-bytes` off a boundary errors
  `invalid-char-boundary`.

### S4 — `String` owning type (depends S0–S3, Vector)
- `(defstruct String bytes:(Vector ui8))` (thin wrapper — eval/impl §). Constructors
  `string-new`/`-alloc`/`-with-capacity`; **validating** `string-from-cstr:!String`
  / `string-from-view:!String` (`invalid-utf8`) + the `*-unchecked` escape hatch.
  Mutation `push-char`/`push-str:!void`/`pop-char`/`clear`/`truncate:!void`/
  `reserve`/`shrink-to-fit`. Conformances `(ByteStr StringByteIter)` /
  `(Str StringCharIter)` / `Eq` / `Ord` / `Hash` / `Drop` (drops the wrapped
  `Vector`). Reuse the S3 read layer through `as-view`. **Not** `Coll`/`Seq`
  (decided).
- *Accept:* build a `String` with `push-char`/`push-str`, iterate chars and bytes,
  round-trip to/from `CStr` (validated + error on bad UTF-8); a `with`-bound
  `String` frees its buffer; works as a `HashMap` key (Hash+Eq).

### S5 — `split`/`lines`/`trim` + `FromStr`/`parse` (depends S4)
- Standalone, `Self`-derived: `SplitIter`/`LineIter` (lazy, yield borrowed
  `StrView`s); `split` a multimethod over the pattern (`StrView` | `Char` | a
  `UnaryFn` predicate). `FromStr` protocol; **numeric libs implement it** for
  `i32`/`i64`/`f64`; `parse` a generic with the **target type as an explicit
  argument** (`(parse i32 s) → !i32`), failures as `!T`.
- *Accept:* `split`/`lines` produce the expected sub-views (lazy, no intermediate
  `Vector`); `(parse i32 "42")` ok, `(parse i32 "x")` errors; `(parse f64 …)` works.

### S6 — examples, tests, docs, progress
- Examples + `tests/expected/*.out` covering S0–S5 (char literals + UTF-8; String
  build/iterate/bounds; split/trim; parse ok+err). `docs/strings.md`; update
  `design/stage11/progress.md` (M6) and confirm `design/overview.md` references.

---

## 5. Landmines (read before writing a line)

1. **S0 must be byte-identical-additive.** No current source uses `\…` char
   literals or the `Char` type, so the bootstrap IR diff after S0 must be empty
   (modulo a deliberate, re-converged change if you alter the existing `(char "x")`
   form — confirm the diff is *only* that).
2. **Keep `Char` distinct.** It lowers to `i32`/`ui32` but must not be `type-eq` to
   them (or dispatch and literals lose meaning). Same-width `cast` is a reinterpret.
3. **`Str`/`ByteStr` are read-only; conformers don't own.** `CStr` and `StrView`
   must **not** be forced to conform to `Drop` (eval §1). Only `String` is `Drop`.
   Don't put mutation in the shared protocols.
4. **Borrowed views alias the owner's buffer.** `as-view`/`sub-bytes`/`split`
   results and the `*Iter`s borrow the `String`/`StrView` bytes — they must not
   outlive the owner (the `VecIter`-borrows-buffer caveat). Document it; don't copy.
5. **Value-return iterators + `addr-of`.** `chars`/`bytes` return the iterator by
   value (the spike convention); drive `next` via `(addr-of it)`.
6. **`(Maybe ptr)` is niche-encoded.** `Char` and `ui8` elements are non-pointer, so
   `(Maybe Char)`/`!Char`/`!ui8` are fine; don't introduce a `(Maybe ptr)` element.
7. **Paren-type binding forms.** Use the list form `(self (ref Self))` for paren
   types; `name:(ref StrView)` works only via the colon-paren sugar (cleanup §1, now
   live). `:!Char`/`:!StrView` colon return types tokenise (like `checked:!i64`).
8. **`.nuch` header gap (M1 finding #4).** `emit-nuch-header` doesn't process
   `(import …)` types, so a header for a lib whose signatures mention an imported
   struct fails. Keep `String` reasonably self-contained, or accept that
   `make lib-headers` (not part of the test/bootstrap gate) may fail for it.
9. **Validated owned `String` + escape analysis.** A `String` owns heap memory;
   Stage 10 taint analysis blocks returning/storing it out without a `move`. The
   validating constructors return `!String` — thread the error with `try`.

---

## 6. Definition of done

- S0–S5 implemented per `design/stage11/string.md`; the `Char` scalar, the
  `ByteStr`/`Str` protocols, the `String` type + conformances, and `parse` exist.
- `make test` passes; `make bootstrap` is a **byte-identical fixed point**.
- Examples/tests cover: char literals + a UTF-8 round-trip (S0/S1); a `String`
  built via `push-char`/`push-str`, iterated by `chars` and `bytes`, nth-char with
  an out-of-bounds **error** (S3/S4); a `with`-bound `String` freeing its buffer and
  serving as a `HashMap` key (S4); `split`/`trim` (S5); `parse i32`/`f64` ok+err
  (S5). Fixtures under `tests/expected/`.
- `docs/strings.md` written; `design/stage11/progress.md` M6 updated;
  `design/overview.md` references string.md/this prompt.
- Any genuine unfixable environment gotcha noted in the right `context/` file.

## 7. Explicitly out of scope (do not build)

- **The string-literal `CStr` → static `StrView` switch.** This is the end-of-stage
  compiler-adoption step (string.md eval §5, deferred) — the riskiest piece, done
  only after the type is stable. Literals **stay `CStr`** for this prompt.
- **Full Unicode case mapping/folding, UTF-16, grapheme segmentation, NFC/NFD,
  linguistic collation** — ASCII case + UTF-8 + codepoint only (stage888 notes).
- **`String` as `Coll`/`Seq`** (decided no); **sparse-index / `Vector Char`** string
  representations; **`Ord`-keyed maps**; lambdas/closures, `dyn`.
