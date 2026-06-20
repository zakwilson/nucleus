# Stage 11 Progress — Parametric Structs & Collections

Parametric structs: **done** (T0–T6). Collections: **done** (M1–M5 done; A0–A2 associated types done; A4.0–A4.4 extend-site recovery + generic iterator rewrite done). M6 String: **done** (S0–S6 all complete — `Char` scalar + literals, `lib/char.nuc`, `lib/string-errors.nuc`, `lib/string-protocols.nuc`, `lib/strview.nuc`, `lib/strview-str.nuc`, `lib/string.nuc`, `lib/parse.nuc`, `lib/string-split.nuc`, `docs/strings.md`).
Cleanup: §1 (colon-paren sugar), §2 (keyword/StrView), §3 (iterator-test flatten), §4a (phantom tyvar) — all **done**. Second cleanup: C2.0 (generalize value-keyed `get` dispatch), C2.2a (`get:(Maybe V)` on `Assoc`; `hmap-get` deleted), C2.3/C2.4/C2.6 (doc/design judgement cleanups), C2.5 (remove legacy protocols `Call`/`BinaryCall`/`IntIndexable`), C2.7 + C2.8 (doc/comment rationale sweep + resolved-limitation close-out) — **done**. A4.5 (`defn &where` compound `((Protocol Arg) Var)` constraints) — **done** (`examples/assoc-iter-return.nuc` prints `count=5`, byte-identical bootstrap). C2.1 (`iter` lifted into `Coll` as `(Coll E It)` with a value-returning associated iterator; `doseq`/`into` migrated to generic-`Coll` dispatch, with `doseq-iter`/`into-iter` retained for bare iterator refs) + C2.2b (`keys:Ki`/`vals:Vi` lifted into `Assoc` as `(Assoc K V Ki Vi)` with associated iterator types; `HashMapValIter` added; `HashMap` conforms to `(Assoc K V (HashMapKeyIter K V) (HashMapValIter K V))`) + C2.2c (`(Entry K V)` pair + `HashMap` conforms to `(Coll (Entry K V) (HashMapEntryIter K V))`) — **done** (95 tests, byte-identical bootstrap).
Back to [../progress.md](../progress.md)

102 tests pass; `make bootstrap` is a byte-identical fixed point.

**M6 String design (`design/stage11/string.md`):** evaluated and specified. Key
calls — `Str` is a read-only contract extending `Eq` only (not `Coll`/`Seq`/`Drop`);
three-layer split `ByteStr` ⊂ `Str` ⊂ `String`; error-handling (not panic/Maybe)
for bounds/validation; `Char` a new built-in distinct scalar with `\a`/`\newline`/
`\u{…}` literals; string literals migrate to a borrowed static `StrView`, not owned
`String`. **Associated-type uplift validated:** `examples/assoc-iter-return.nuc`
confirms a protocol method can return a bare associated type used as a later
constraint's conforming variable (the `chars`/`bytes` uplift), so those can be real
protocol methods rather than standalone functions.

### M6 String — implementation status

| Task | Description | Status | Key functions / files |
|---|---|---|---|
| S0 | **`Char` built-in distinct scalar + char literals** (critical path). A new `TY-CHAR` type-kind — a distinct 32-bit scalar over `ui32` modeled on `TY-CSTR`: IR `i32`, C `uint32_t`, size 4, integer for ops/coercion but **distinct** under `type-eq` so `=`/`!=` dispatch and `Char`-vs-int overloads keep meaning (two typed differently-kinded operands no longer auto-unify in `binop-coerce`). Reader: a `TOK-CHAR`/`NODE-CHAR` carries the validated Unicode scalar value; `lex-char-literal` lexes `\a` (printable), `\newline`+named control codes, and `\u{HEX}` (range + surrogate checked). The byte-only `(char "x")` form now yields `Char` (sugar for `\x`). Additive — `make bootstrap` stays byte-identical. | Done | `src/nucleusc.nuc` (`TY-CHAR` enum, `ty-char` singleton + `types-init`, `type-to-ir`/`type-to-c`/`type-size`/`is-int-type`/`int-width`/`is-unsigned`/`type-mangle-token`/`type-spelling`/`parse-type-name`, `emit-char-literal`, `node-type`/`gcheck`/`valid-walk`/`node-type-call` arms, `emit-char` + `defvar-init-ir` `(char …)`, `binop-coerce` Char guard, `TOK-CHAR`, `emit-quote-tree` data path); `lib/prelude.nuc` (`NODE-CHAR`); `lib/reader.nuc` (`lex-char-literal`, `hex-digit-val`, `make-char-tok`, `next-tok` `\` dispatch, `read-form` `TOK-CHAR` arm); `examples/char-test.nuc` + `tests/expected/char-test.out` |
| S1 | `Char` UTF-8 + classification lib (`char-utf8-len`, `char-encode-utf8`, `char-decode-utf8`/`DecodeResult`, `char-from-u32`/`char-to-u32`, ASCII classification + `char-ascii-upper`/`char-ascii-lower`). Note: classification functions named without `?` suffix (`char-is-ascii`, `char-is-digit`, etc.) — `?` is invalid in LLVM IR identifiers for non-generic `defn` names (same reason `!` suffix is forbidden, per `context/build.md`). | Done | `lib/char.nuc` (`DecodeResult`, all encode/decode/classification functions, `invalid-codepoint` error); `examples/char-utf8-test.nuc` + `tests/expected/char-utf8-test.out` |
| S2 | **`ByteStr`/`Str` protocols + four string error codes** — `lib/string-errors.nuc` (four `deferror` codes); `lib/string-protocols.nuc` (`ByteStr ByteI` + `Str CharI` read-only protocol shapes; `(extend Str Eq)` records Eq inheritance); smoke test `examples/string-protocols-test.nuc` confirms error codes compile, are non-zero, and are mutually distinct; all 96 tests pass. | Done | `lib/string-errors.nuc`, `lib/string-protocols.nuc`, `examples/string-protocols-test.nuc`, `tests/expected/string-protocols-test.out` |
| S3 | **`StrView` read layer + `ByteStr`/`Str` conformances** — `lib/strview.nuc`: `StrView{data,len}`, `ByteIter`/`CharIter` (Iterator conformances), all read-layer helpers (`strview-byte-len`/`byte-at`/`bytes`/`chars`/`sub-bytes`/`byte-find`/`char-count`/`char-at`/`empty`/`starts-with`/`ends-with`/`contains-str`/trim trio), `Eq`/`Ord`/`Hash` conformances; `lib/strview-str.nuc` breaks the circular-import cycle and wires `(extend StrView (ByteStr ByteIter))` + `(extend StrView (Str CharIter))`; force-mangle shim `_StrMangleShim` for `?`-named Str methods (removed when CStr/String provide second impls). | Done | `lib/strview.nuc`, `lib/strview-str.nuc`, `examples/strview-test.nuc`/`strview-read-test.nuc`, `tests/expected/*.out` |
| S4 | **`String` owning type** — `lib/string.nuc`: `(defstruct String bytes:(Vector ui8))`; `string-as-view` (zero-copy StrView bridge); constructors `string-new`/`string-new-alloc`/`string-with-capacity`; validating constructors `string-from-view`/`string-from-cstr`/`string-from-cstr-unchecked`; mutation: `string-push-char`/`string-push-str` (`!i32`)/`string-pop-char`/`string-clear`/`string-truncate` (`!i32`)/`string-reserve`/`string-shrink-to-fit`; internal `string-push-bytes-raw`; `Drop` (delegates to Vector drop); `ByteStr`/`Str` conformances (delegate through `string-as-view`); `Eq`/`Ord`/`Hash` conformances; works as `HashMap` key. All 90 tests pass; byte-identical bootstrap. | Done | `lib/string.nuc`, `examples/string-test.nuc`, `tests/expected/string-test.out` |
| S5 | **`FromStr`/`parse` + `split`/`lines`/`trim`** — `lib/parse.nuc`: `(defprotocol (FromStr R) ...)` with phantom `(self Self)` first arg; `parse` macro `(parse T sv)` → `(from-str (cast T 0) sv)`; `parse-int-error`/`parse-float-error` deferrors; conformances for `i32`/`i64` (via `strtol`/`strtoll`) and `f64` (via `strtod`), all strict (no leading whitespace, trailing garbage → error). `lib/string-split.nuc`: `SplitIter`/`LineIter` (done-flag design — avoids `(Maybe StrView)` JIT struct issue); `strview-split`/`strview-lines` constructors; `split-iter-next`/`split-iter-done`/`lines-iter-next`/`lines-iter-done` API. Trim (strview-trim/trim-start/trim-end) already in `lib/strview.nuc` (S3). All 102 tests pass; byte-identical bootstrap. | Done | `lib/parse.nuc`, `lib/string-split.nuc`, `examples/parse-test.nuc`, `examples/string-split-test.nuc`, `tests/expected/parse-test.out`, `tests/expected/string-split-test.out` |
| S6 | **Docs** — `docs/strings.md` (§1–§8: Char scalar + literals, Char functions, StrView read layer, ByteStr/Str protocols, String owning type, split/lines/trim, FromStr/parse, error codes); `docs/index.md` updated (new Strings row + 8 new import entries); `docs/stdlib.md` StrView stale note updated; `design/stage11/progress.md` + `design/progress.md` updated. | Done | `docs/strings.md`, `docs/index.md`, `docs/stdlib.md`, `design/stage11/progress.md`, `design/progress.md` |

---

## Stage 11 collections (`design/stage11/collections.md`)

| Task | Description | Status | Key functions / files |
|---|---|---|---|
| M1 | **Allocator protocol + default + arena conformance** — the `Allocator` protocol (the design's Zig-shaped `alloc`/`realloc`/`free` contract); a tagged `AllocHandle` (`{kind, data}`) a collection stores in one field and dispatches through; libc + arena backends behind `alloc-handle-{alloc,realloc,free}`; a process-global default (libc) handle; field-setting constructors `libc-allocator` / `arena-allocator`. Compiler bugfix: aggregate-typed `defvar` globals now emit `zeroinitializer` (was an invalid `0`). The old `Seq` protocol in `lib/seq.nuc` renamed to `IntIndexable` to free the `Seq` name for the M3 collection protocol. | Done | `lib/allocator.nuc` (protocol, `AllocHandle`, `AllocKind`, helpers, `g-default-alloc`, `default-allocator`); `lib/seq.nuc` (`IntIndexable`); `examples/allocator-test.nuc` + `tests/expected/allocator-test.out`; `emit-defvar` aggregate-init arm (`src/nucleusc.nuc`) |
| M2 | `Iterator` protocol, `into`, `doseq`; generic lazy `map`/`filter`/`reduce` | Done | `lib/iterator.nuc` (`Iterator` parametric protocol, `IntRangeIter`, `I64ArrayIter`, `UnaryFn`/`FoldFn` function-object protocols, `MapIter`/`FilterIter` generic combinators conforming to `Iterator` via `&where`-on-`extend`, generic `reduce`); `lib/macros.nuc` (`doseq`, `into`); `examples/iterator-test.nuc` + `tests/expected/iterator-test.out` |
| M3 | **`Vector T`** — dynamically-sized heap sequence (STL `vector` in spirit); O(1) amortized `conj`/`append`/`invoke` (capacity doubling), O(n) `insert`; `Coll`/`Seq` conformance; capacity ops (`capacity`/`reserve`/`vector-init-capacity`); `VecIter` forward cursor (`Iterator` conformance); `Drop` frees the buffer at `with`-scope exit. Fill-in-place constructors (`vector-init`) infer `T` from the receiver. | Done | `lib/vector.nuc` (`Vector`, `VecIter`, `count`/`conj`/`empty?`/`invoke`/`append`/`contains?`/`insert`, capacity ops, `next`/`iter-init`); `lib/coll.nuc` (`Coll`/`Seq`/`Drop` protocols); `examples/vector-test.nuc` + `tests/expected/vector-test.out` |
| M4 | **`Hash` lib + `HashMap K V` + `HashSet T`** — open-addressing tables (linear probing, power-of-two cap, tombstone deletion, 75% load-factor doubling). `Hash` protocol with FNV-1a conformances for `i32`/`i64`/`usize`/`CStr`; new `(Assoc K V)` and `(Set E)` protocols in `lib/coll.nuc`. HashMap: `assoc`/`dissoc` (`Assoc`), standalone `hmap-get → (Maybe V)`, `count`/`empty?`, `HashMapKeyIter`. HashSet: `insert`/`contains?`/`set-remove`, mutating `union`/`difference`/`intersection` (`Set`), `conj`/`count`/`empty?` (`Coll`), `HashSetIter`. Both own their byte arrays through the stored `AllocHandle` and `Drop` them at `with`-scope exit. | Done | `lib/hash.nuc` (`Hash`, `fnv1a-byte`/`fnv1a-int`, scalar+CStr conformances); `lib/coll.nuc` (`Assoc`/`Set` protocols); `lib/hashmap.nuc` (`HashMap`, `HashMapKeyIter`, resize/probe); `lib/hashset.nuc` (`HashSet`, `HashSetIter`, set algebra); `examples/hashmap-test.nuc` + `examples/hashset-test.nuc` + `tests/expected/*.out`. Compiler fix: latent `ptr-get` typo in `lib/vector.nuc`'s `vector-init-alloc` (never instantiated) corrected to `deref`. |
| M5 | **Reader-macro literals `[…]` / `{…}` / `#{…}` → constructors** — the reader recognises the bracket delimiters and expands each to a `let` that stack-allocates the stamped collection, runs its in-place init (default libc allocator), `conj`/`assoc`-es each element, and yields the `(ref Coll)`; placed as a `with` RHS the outer `with` fires `Drop`. Element types are inferred from scalar literals (int→`i32`, float→`f64`, string→`CStr`); empty/mixed-kind/non-scalar/odd-map literals are reader errors. | Done | `src/nucleusc.nuc` (`TokKind` enum: `TOK-LBRACK`/`TOK-RBRACK`/`TOK-LBRACE`/`TOK-RBRACE`/`TOK-HASHBRACE`); `lib/reader.nuc` (`is-sym-char` delimiter exclusions, `next-tok` bracket lexing, `read-vector-literal`/`read-hashmap-literal`/`read-hashset-literal`, `infer-lit-type`/`read-lit-elems`, `lit-*` node builders); `examples/{vector,hashmap,hashset}-lit-test.nuc` + `tests/expected/*.out`; `Makefile` (`COMPILER_DEPS`: source-inlined libs now rebuild `$(BIN)`) |

### M5 design decisions and limitations

1. **Expansion shape = `let` + init + conj, yielding the ref.** The reader builds
   `(let ((__gs (ref (Coll E))) (alloca (Coll E))) (init __gs) (conj __gs e1) … __gs)`.
   The fresh `__gs` symbol is produced by `nucleus_gensym` (the same fresh-NODE-SYM
   path `(gensym)` uses) and reused by pointer in every position. The literal builds
   with the default libc allocator; an explicit-allocator collection still uses the
   `(alloca …)` + `vector-init-alloc` idiom.
2. **Element-type inference is by literal kind, integers always `i32`.** A NODE-INT
   infers `i32`, NODE-FLOAT `f64`, NODE-STR `CStr`. There is **no** magnitude-based
   `i64` promotion: the compiler types every integer literal as `i32` (`emit-int`),
   has no native `i64` integer literal, and `(cast i64 bigval)` on an i32-typed literal
   *truncates*. So promoting would silently corrupt large values — dropped on purpose.
   Bare literals match the corresponding element parameter directly (i32/f64/CStr), so
   the expansion needs no per-element casts. An `i64`/other-typed collection must use
   the explicit `(alloca …)` + init idiom.
3. **Delimiters claimed from the symbol lexer.** `[` `]` `{` `}` were previously
   symbol chars; `is-sym-char` now rejects them so a trailing `]`/`}` terminates the
   preceding atom. `#{` is matched as a two-char sequence in `next-tok` before `#` is
   lexed as a symbol char (a lone `#` still lexes as an atom). All four delimiter
   characters appear in current source only inside string literals, so claiming them
   is non-breaking; the compiler's own source uses no collection literals, so the
   reader never calls `nucleus_gensym` during self-compile → bootstrap byte-identical.
4. **Makefile dependency gap fixed (root cause).** `$(BIN)` previously depended only
   on `src/*.nuc`, so edits to source-inlined libs like `lib/reader.nuc` did not
   trigger a rebuild (a stale-binary trap). Added `COMPILER_DEPS` listing every
   source-inlined `.nuc` the compiler imports (`src/format.nuc`, the prelude chain,
   `lib/error.nuc`, `lib/reader.nuc`).

### M1 design decisions and limitations

1. **Dispatch is a tagged handle, not a static `extend` conformance.** Collections
   need *dynamic* dispatch (one stored allocator field, concrete type unknown at the
   call site). The protocol system is static-only (no vtables) and `funcall-ptr-*`
   only calls function pointers of arity 0/1 with ptr/i32/i64 results, so a C vtable
   of `(data size align) -> (raw ui8)` entries cannot be called. The tagged
   `AllocHandle` (`kind` discriminant + `data`) is exactly the spec's "Plumbing
   (decided): stored field".
2. **A static `Allocator` conformance is currently un-importable from a library.** A
   generic method literally named `free`/`realloc`/`malloc` lowers to LLVM `@free`
   etc. and shadows the libc symbol for the whole unit (1-arg `(free p)` would target
   the 4-arg generic — UB; this is why `Drop` uses `drop`). Defining the conformance
   *directly* in the consuming unit compiles, but **importing** it fails with "invalid
   redefinition": the imported file's transitive `(include stdlib)` re-emits
   `declare @realloc`/`@free` before the importing file's generics finalize.
   Root cause: `emit-c-include` (`src/cheader.nuc`) skips a libc declare only if the
   name is already in `g-globals`, but the importing file's generics are registered
   (via `prescan-defn-signatures` → `finalize-generics`) only *after* the nested
   import's stdlib include runs. **Fix deferred** (a prescan/include ordering change,
   risky for the byte-identical bootstrap; not needed by M1's tagged-handle path).
3. **`(raw u8)` spelling.** The design's `u8` byte type is `ui8` in Nucleus
   (`unsigned char`); `u8` is not a type name. A parenthesised type in a colon return
   position (`alloc:(raw ui8)`) does not tokenise — use the list-form name
   `((alloc (raw ui8)) ...)` (the same workaround as parenthesised parameters).
4. **`.nuch`/cheader of a lib that uses an imported lib's *type* fails.** `emit-nuch-header`
   does not process `(import …)` to register imported types, so a function signature
   mentioning an imported struct (e.g. `AllocHandle`) reports "unknown type". This is
   why M1 keeps the allocator in a single self-contained `lib/allocator.nuc` rather
   than splitting protocol/helpers across files. (Pre-existing: `lib/node.nuch` fails
   the same way; `make lib-headers` is not part of `make test`/`make bootstrap`.)

### M2 design decisions and limitations

1. **`(Maybe ptr)` niche-encoded — cannot use `match`.** When the element type is a
   pointer kind (`TY-PTR`), `(Maybe ptr)` collapses to a nullable pointer with niche
   encoding. `match` cannot be used on it. Use `i32` or `i64` as element types and
   `match` normally. All iterators in M2 use `i64` elements.
2. **No runtime vtable dispatch; MapIter/FilterIter are parametric on F.** Because
   protocols dispatch statically, lazy combinator types must be parametric on the
   function-object type `F`. The concrete `apply`/`fold` call is resolved at stamp
   time. The combinators (`MapIter`/`FilterIter` + `UnaryFn`/`FoldFn`) are
   **element-generic**: `(MapIter I F)` conforms to `(Iterator E)` where `E` is
   recovered at stamp time from `F`'s `UnaryFn` conformance via `&where` on
   `extend`. This is A4 (`design/stage11/assoc-types-extend.md`), implemented and
   complete. The former `i64`-specialized `MapIterI64`/`FilterIterI64`/`CallI64`/
   `BinaryCallI64` types have been retired.
3. **`(Maybe T)` construction in non-return position.** `none` and `(some v)` work
   in return position. Elsewhere use `(make (Maybe T) none)` / `(make (Maybe T) some v)`.
4. **Field access via `(.& self field)` required for `addr-of`.** `(addr-of expr)` only
   accepts a bare symbol. Use `(.& self fieldname)` to get a reference to a struct field
   stored by value, then call `next` on it.
5. **`doseq` and `into` macros add strings to the compiler's string pool.** Since
   `lib/macros.nuc` is auto-imported via prelude into *every* compilation including the
   compiler itself, adding these macros shifted string indices. Two rounds of
   `make update-bootstrap` + `make clean && make` were needed to converge.
6. **`gensym` takes no arguments.** `(gensym)` not `(gensym "name")`.
7. **Gensym'd let bindings need list-form for types.** `(let ((~sym i32) init))` not
   `(let (~sym:i32 init))` — the `:` form does not tokenize for a gensym'd symbol.

### M4 design decisions and limitations

1. **Built-in types can `extend` a protocol with a real method body.** `lib/hash.nuc`
   does `(extend i32 Hash)` + `(defn hash:usize ((self (ref i32))) ...)` (and the same for
   `i64`/`usize`/`CStr`). Unlike `lib/numeric.nuc`'s code-free conformances (the built-in
   `=`/`<` operators *already* satisfy `Eq`/`Ord`), there is no built-in `hash` op, so each
   conformance supplies an actual method over a `(ref Self)` receiver. Dispatch on
   `(hash some-ref)` is static by the first argument's type, exactly as for user types.
2. **Generic `hash` dispatch goes through `(hash (addr-of local-of-type-K))`.** A
   collection's key/element `K` is a tyvar; to hash it, copy the stored key into a `K`-typed
   local and pass its address. The conformance is selected at stamp time per concrete `K`.
   `K` must be both `Hash` (for the table) and `Eq` (for `=` collision resolution); both are
   enforced structurally at stamp time (the parametric-protocol `&where` frontier is now
   resolved — A0–A2, see `design/stage11/assoc-types.md`), so a `K` lacking either errors
   with a missing-method diagnostic when the table is first stamped.
3. **FNV-1a folds bytes; the offset basis is a signed-literal trick.** Scalars fold every
   value byte little-endian, `CStr` folds chars to the NUL. The 64-bit offset basis
   `0xcbf29ce484222325` has its high bit set, so it is written as the two's-complement
   decimal `-3750763034362895579` (the same constant the compiler's own `hash-struct-shape`
   seeds with) — the unsigned hex would overflow the signed-literal range. The fold runs in
   `i64` and is cast to `usize` at the end (the protocol's return type).
4. **HashMap conforms to `(Coll (Entry K V) (HashMapEntryIter K V))` and `(Assoc K V (HashMapKeyIter K V) (HashMapValIter K V))`** (since C2.1/C2.2b/C2.2c).
   `Coll`'s element type is the key/value pair `(Entry K V)` (a plain value struct): `conj`
   inserts an `Entry` (= `assoc` of its key/val) and `iter` yields `Entry` values via
   `HashMapEntryIter`. `Assoc` is now `(Assoc K V Ki Vi)` with value-returning `keys:Ki` and
   `vals:Vi` protocol methods; `HashMap` binds `Ki = HashMapKeyIter K V` and `Vi = HashMapValIter K V`.
   HashMap also extends `Drop`. (Before C2.2c, HashMap did not extend `Coll` because a single-element
   `conj` was ambiguous for a key/value map; the pair element type resolves that.) HashSet extends
   `(Coll T (HashSetIter T))`, Vector extends `(Coll T (VecIter T))` — both with `conj` == append/insert.
5. **`get`, `iter`, `keys`, and `vals` are all protocol methods.** `get` was lifted into `Assoc`
   (C2.2a: `(get (Maybe V))`); `iter` was lifted into `Coll` (C2.1: `iter:It`, value-returning
   associated iterator); `keys`/`vals` were lifted into `Assoc` (C2.2b: `keys:Ki`/`vals:Vi`,
   value-returning associated iterators, same alloca+set+deref convention). `Assoc` carries
   `assoc`/`dissoc`/`get`/`keys`/`vals`; `Set` carries `union`/`difference`/`intersection`/`contains?`.
6. **Open-addressing invariants.** Cap is always a power of two, so the bucket index is
   `(bit-and (hash …) (- cap 1))`. States are `0=empty / 1=occupied / 2=tombstone`; lookup
   stops at the first empty slot and skips tombstones; `assoc`/`insert` reuse the first
   tombstone seen on an absent-key insert. The 75% load-factor doubling guarantees empty
   slots always remain, so probe loops in `contains?`/`get`/`set-remove` always terminate.
   `union` scans `other` and inserts into `self` (insert may resize `self`, but never touches
   `other`); `intersection`/`difference` scan `self` and only tombstone in place (no resize
   mid-scan), so cached buffer pointers stay valid.
7. **Mutating set algebra.** `union`/`difference`/`intersection` mutate the receiver in place
   (the efficient primitive, per spec); a fresh-result variant would be `iter` + `into` (M5).
8. **Set delete is `set-remove`, not `remove`.** A generic method named `remove` would shadow
   libc `remove(path)` for the unit (the same libc-name-collision rule that makes `Drop` use
   `drop`, not `free`).
9. **`deref`, not `ptr-get`, loads through a `(ref T)`.** `ptr-get` is not a builtin; a latent
   `ptr-get` in `lib/vector.nuc`'s `vector-init-alloc` (a receiver-inferred generic never
   instantiated by any test, so never compiled) was corrected to `deref` as part of M4.
10. **Hash-order is non-deterministic in output.** Iterating a HashMap/HashSet visits buckets
    in storage order, which depends on the hash and probe sequence. The example tests never
    print iterated keys/members directly — they print a count or an order-independent sum — so
    the expected `.out` files stay deterministic.

---

## Stage 11 cleanup — pre-string pass (`design/stage11/cleanup.md`)

| Task | Description | Status | Key files |
|---|---|---|---|
| §1 | **Colon-paren binding sugar** — `name:(ref (Vector T))` now fuses into `(name <paren-form>)` in the reader's list-reading path (`fuse-colon-paren` in `lib/reader.nuc`). Works in `defn` params, `let` bindings, `defstruct` fields, `extern`, and `declare`. Bootstrap byte-identical (no current source uses the new form). | Done | `lib/reader.nuc` (`fuse-colon-paren`, `read-list`); docs in `docs/types.md` §"Colon-paren binding sugar" and §"Function Pointer Types" |
| §2 | **`StrView` substrate + `Keyword` literal `:foo`** — see detailed section below. Also fixes a latent `emit-extern` dedup bug (two libs both declaring `(extern stderr:ptr)` → LLVM "redefinition of global"). | Done | `lib/strview.nuc`, `lib/keyword.nuc`, `lib/reader.nuc`, `src/nucleusc.nuc`; `examples/{keyword,strview}-test.nuc` |
| §3 | **Iterator-test flatten** — `examples/iterator-test.nuc` multi-binding `let` already supported; nested `let`s flattened to a single flat binding list. No language change; output unchanged. Docs: note added to `docs/types.md` §"Type Syntax and Desugar" (multi-binding `let`). | Done | `examples/iterator-test.nuc` |
| §4a | **Phantom/positional tyvar recovery** — `register-generic-defn` and `defn-has-receiver-tyvars` now size the `tyvars` arena array by `count-pattern-nodes` (total node count of parameter/return type patterns) rather than by parameter count alone. Fixes segfault + `unknown type` for generic methods over multi-param templates with trailing phantom type params. Bootstrap byte-identical. | Done | `src/nucleusc.nuc` (`count-pattern-nodes`, `register-generic-defn`, `defn-has-receiver-tyvars`); `examples/phantom-tyvar-test.nuc` + `tests/expected/phantom-tyvar-test.out`; docs in `docs/structs-unions.md` |

---

## Stage 11 cleanup — second pass (`design/stage11/cleanup2.md`)

| Task | Description | Status | Key files |
|---|---|---|---|
| C2.7+C2.8 | **Doc/comment rationale sweep + resolve limitation #3** — all "impossible without associated types" comments updated; `docs/parametric-structs.md` limitation #3 marked resolved; `docs/collections.md`, `docs/special-forms.md`, `docs/builtins.md`, `docs/index.md`, `docs/structs-unions.md`, `design/stage9/callable-values.md` rationale passes done | Done | `lib/coll.nuc`, `lib/seq.nuc`, `docs/collections.md`, `docs/special-forms.md`, `docs/builtins.md`, `docs/index.md`, `docs/structs-unions.md`, `design/stage9/callable-values.md`, `design/stage11/parametric-structs.md` |
| C2.0 | **Compiler: generalize `get` dispatch** — `emit-get-with-callee` split into a literal-symbol branch (unchanged, static GEP field access) and a computed/value-selector branch (`generic-resolve-nullable` on hit → call generic `get` override; on miss → field intrinsic). `generic-resolve-nullable` added as a non-dying variant of `generic-resolve`. Bootstrap byte-identical on current source. | Done | `src/nucleusc.nuc` (`emit-get-with-callee`, `generic-resolve-nullable`); `examples/get-dispatch-test.nuc` + `tests/expected/get-dispatch-test.out` |
| C2.2a | **`get:(Maybe V)` into `Assoc` protocol; `hmap-get` deleted** — `Assoc K V` now declares `((get (Maybe V)) ((self (ref Self)) key:K))` as a protocol method; `HashMap` provides the conforming method body; the standalone `hmap-get` generic is removed; all call sites migrated to `(get m key)`. | Done | `lib/coll.nuc` (`Assoc` protocol), `lib/hashmap.nuc` (`get` method, `hmap-get` removed), `examples/{hashmap,hashmap-lit,keyword}-test.nuc`, `examples/assoc-get-test.nuc` + `tests/expected/assoc-get-test.out` |
| C2.5 | **Remove `Call`/`BinaryCall`/`IntIndexable` from `lib/seq.nuc`; migrate `examples/callable.nuc` to `UnaryFn`/`FoldFn`** — the fixed-element-type callable protocols are retired; `examples/callable.nuc` rewritten using the generic `UnaryFn`/`FoldFn` from `lib/iterator.nuc`; docs updated | Done | `lib/seq.nuc` (protocols removed), `examples/callable.nuc` (rewritten), `tests/expected/callable.out`, `docs/special-forms.md`, `docs/builtins.md`, `docs/index.md` |
| C2.3 | **`Set.select` comment corrected** — confirmed as a deliberate design choice (not a limitation), not a missing associated-type feature; comment in `lib/coll.nuc` updated accordingly | Done | `lib/coll.nuc` |
| C2.4 | **Reconcile `design/stage11/collections.md` §Seq with shipped lazy-iterator reality** — §Seq updated to document the shipped `Iterator`/`MapIter`/`FilterIter` shape rather than the pre-implementation sketch | Done | `design/stage11/collections.md` |
| C2.6 | **Frame `examples/phantom-tyvar-test.nuc` as legacy regression test** — file comment updated to identify it as a legacy regression test for the §4a phantom-tyvar fix, superseded by associated-type approaches | Done | `examples/phantom-tyvar-test.nuc` |
| C2.1 | **Lift `iter` into `Coll` with associated iterator type `It`; migrate `doseq`/`into`** — `Coll` is now `(Coll E It)` with `iter:It` (value return: alloca + set + `(deref …)`, the spike pattern); `Vector`/`HashSet`/`HashMap` conform with a value-returning `iter`, wrapping their (now internal) fill-in-place helpers. `doseq`/`into` migrated to dispatch generically over any `Coll`: `(doseq (var coll IterType) …)` / `(into dest src IterType)` call the protocol `iter`, bind the result to a typed local, and drive `(next (addr-of it))`. `IterType` is named explicitly because Nucleus `let` has no binding-type inference and `addr-of` needs a named local (not an rvalue). New `doseq-iter`/`into-iter` keep the pre-C2.1 bare-iterator-ref form for pure iterators (`IntRangeIter`, `MapIter`, `FilterIter`, `HashMapKeyIter`). | Done | `lib/coll.nuc` (`Coll E It` + `iter`), `lib/vector.nuc`, `lib/hashset.nuc`, `lib/hashmap.nuc` (value-returning `iter` + extends), `lib/macros.nuc` (`doseq`/`into` migrated + `doseq-iter`/`into-iter` added); `examples/{vector,hashset,hashmap,iterator}-test.nuc` migrated; `examples/coll-iter-test.nuc` + `tests/expected/coll-iter-test.out` |
| C2.2b | **Lift `keys`/`vals` into `Assoc` with associated iterator types** — `Assoc` is now `(Assoc K V Ki Vi)` with `keys:Ki` and `vals:Vi` (value-return, same alloca+set+deref convention as `iter`); `(defstruct (HashMapValIter K V) vbuf:ptr sbuf:ptr pos:usize cap:usize)` added, conforming to `(Iterator V)` with `hmap-iter-vals` fill helper; `HashMap` conforms to `(Assoc K V (HashMapKeyIter K V) (HashMapValIter K V))`. | Done | `lib/coll.nuc` (`Assoc K V Ki Vi`, `keys`/`vals` methods); `lib/hashmap.nuc` (`HashMapValIter`, `hmap-iter-vals`, `keys`/`vals` methods, extend); `examples/assoc-keys-vals-test.nuc` + `tests/expected/assoc-keys-vals-test.out` |
| C2.2c | **`(Entry K V)` struct; `HashMap` conforms to `(Coll (Entry K V) (HashMapEntryIter K V))`** — added `(defstruct (Entry K V) key:K val:V)` (value-struct pair element), `(defstruct (HashMapEntryIter K V) …)` conforming to `(Iterator (Entry K V))` (`next` yields `(some (Entry …))` per occupied bucket), the fill helper `hmap-iter-entries`, the value-returning `iter:(HashMapEntryIter K V)`, the `(Coll (Entry K V) …)` extend, and `conj` over an `Entry` (= `assoc` its key/val). `keys`/`vals` remain separate single-projection iterators (C2.2b). | Done | `lib/hashmap.nuc` (`Entry`, `HashMapEntryIter`, `iter`, `conj`, extend); `examples/entry-test.nuc` + `tests/expected/entry-test.out`; also covered by `examples/coll-iter-test.nuc` |

---

## Stage 11 cleanup §2 — keyword type on a shared `StrView` substrate

| Task | Description | Status | Key functions / files |
|---|---|---|---|
| §2 | **`StrView` substrate + `Keyword` literal `:foo`.** `lib/strview.nuc` is a self-contained immutable byte-slice (`{data:(ptr ui8), len:usize}`) exposing `strview-len`/`strview-eq` (memcmp + length)/`strview-hash` (reuses `lib/hash.nuc`'s `fnv1a-byte` fold) + a `CStr` bridge, with `Hash` and `Eq` conformances. `lib/keyword.nuc` builds an interned, self-evaluating `Keyword` on top: a fixed-size (256) global table, linear-scanned by `keyword-intern`; identity `Eq` (compare `id`) and cached `Hash` (return `cached-hash`), so a keyword is a usable `HashMap` key. The reader recognises a leading-colon atom as a `TOK-KEYWORD`/`NODE-KEYWORD`; the compiler lowers `:foo` to a synthetic `(keyword-intern "foo")` call (reusing the struct-return ABI + dispatch). | Done | `lib/strview.nuc` (`StrView`, ops, `Hash`/`Eq`); `lib/keyword.nuc` (`Keyword`, `keyword-intern`, intern table, `Eq`/`Hash`); `lib/prelude.nuc` (`NODE-KEYWORD` appended to `NodeKind`); `lib/reader.nuc` (`lex-atom` keyword recognition, `read-form` `NODE-KEYWORD` arm); `src/nucleusc.nuc` (`TOK-KEYWORD`, `emit-keyword`, `node-type`/`fprint-node`/`emit-quote-tree` arms, `emit-extern` dedup); `examples/{keyword,strview}-test.nuc` + `tests/expected/*.out` |

### Cleanup §2 design decisions and limitations

1. **`:foo` lowers to a synthetic `(keyword-intern "foo")` call.** Rather than hand-roll
   the struct-by-value-returning call IR, `emit-keyword` builds a synthetic `NODE-CELL`
   `(keyword-intern <NODE-STR>)` and routes it through the ordinary emit path, so dispatch,
   the sret/coerce struct-return ABI, and `node-type` all reuse existing machinery. A program
   using `:foo` must `(import keyword)` — exactly as `[…]`/`{…}` require their collection libs;
   without it the synthetic call dies with `undefined: keyword-intern`.
2. **`Eq` is by VALUE; `Hash` is by `(ref Self)`.** The `Eq` protocol is `(=:i1 (a:Self b:Self))`
   and the collection key path loads two `K` VALUES and calls `(= k1 k2)`, so `Keyword`/`StrView`
   `=`/`!=` take value params. A by-value struct is not directly field-addressable (`(a id)`
   parses as a callable head), so the value `=` copies each param to a local and reads fields
   through `(addr-of local)`. `Hash` follows the protocol's `(ref Self)` receiver.
3. **The intern pool is keyword-specific, a linear scan over a fixed array — NOT a HashMap.**
   A HashMap keyed on keywords would be circular. 256 entries is ample; overflow aborts with a
   diagnostic. Names are copied NUL-terminated into their own `malloc` block so the StrView
   `strview-to-cstr` bridge is sound for any interned keyword name.
4. **`StrView` keeps the byte/eq/hash core only — no `Char`/codepoint/UTF-8 layer.** That layer
   belongs to M6 `String` (`design/stage11/string.md`), which will reuse this same substrate.
   `strview-hash` is the length-counted analogue of the `CStr` `Hash` conformance (folds exactly
   `len` bytes instead of stopping at a NUL), so a view with embedded NULs still hashes fully.
5. **`NODE-KEYWORD` appended last in the `NodeKind` enum.** Existing `NODE-*` ordinals are
   unchanged, and the compiler's own source contains no keyword literals / colon-led atoms, so
   the new reader/emit paths are inert during self-compile → the committed boot binary and the
   new compiler emit byte-identical IR for `src/nucleusc.nuc` (verified directly).
6. **Compiler root-cause fix: `emit-extern` now dedups by symbol name.** Importing two libraries
   that each `(extern stderr:ptr)` (e.g. `keyword` + `hashmap`) previously emitted
   `@stderr = external global ptr` twice — an LLVM "redefinition of global". `emit-extern` now
   skips re-emitting an already-bound extern (idempotent redeclaration). Latent before this pass
   because no prior test imported two stderr-declaring libs at once.

---

## Stage 11 parametric structs (`design/stage11/parametric-structs.md`)

| Task | Description | Status | Key functions / files |
|---|---|---|---|
| T0 | **`usize` / `ssize` builtin scalars** — two pointer-sized integer types resolving to `i32` on ILP32 targets and `i64` on LP64; `usize` unsigned, `ssize` signed; valid in any type position; handled by `parse-type-name`, `type-to-ir`, `sizeof`/`type-size`, `type-mangle-token`, `type-eq` | Done | `parse-type-name` (scalar ladder), `ty-usize` / `ty-ssize` singletons beside `ty-ui64` / `ty-i64`; `g-target-ptr-bytes` consulted at `type-to-ir` time |
| T1 | **Template registry + stamping** — `(defstruct (Vector T) ...)` registers a `StructTemplate` (name, tyvar array, retained form); `(Vector i32)` in type position stamps `Vector.i32` via `struct-template-stamp-types`, memoized by mangled name; deferred IR lines queued and drained at top-level boundaries; `parse-type-from-node` extended with struct-template list-head branch; pointer self-reference (`(defstruct (Tree T) ... (ptr (Tree T)))`) stamps correctly | Done | `StructTemplate` struct (beside `UnionTemplate`); `register-struct-template`; `struct-template-lookup`; `struct-template-stamp-types`; `subst-tyvars-node` (reused); `type-mangle-token` (reused); `lookup-struct` / `emit-defstruct` body; `drain-pending-struct-irs` (same discipline as `drain-pending-union-irs`) |
| T2 | **Methods over a template** — tyvar-from-receiver inference: when a `defn` parameter or return type mentions a registered struct template applied to free symbols, those symbols become the method's tyvars; monomorphized per concrete receiver via `monomorphize-form`; `&where` available for extra bounds only | Done | `monomorphize-form` (reused, rung-4); `defn` prescan tyvar-from-receiver inference; `generic-resolve` / `generic-find-method-exact` (method selection) |
| T3 | **Construction + compound-literal ambiguity** — `((Vector i32) v0 v1 ...)` stamps the type then builds a compound literal; bare `(Vector v0 ...)` in value position is a compile-time error naming the explicit form | Done | Compound-literal / struct-name-as-constructor sites; `parse-type-from-node` for the inner stamp |
| T4 | **Parametric-protocol conformance** — `(defprotocol (Seq E) ...)` carries extra params beyond `Self`; `(extend (Vector T) (Seq T))` binds `E := T`; conformance checked at stamp time: each required method (with `Self → stamped-instance` and `E → concrete-element`) must resolve; def-time error names the missing method | Done | `emit-extend`; `g-protocols` / `g-conformances` registries; conformance check hook at `struct-template-stamp-types`; `Self` + extra-param substitution in `emit-extend` |
| T5 | **C ABI + `.nuch` export** — stamped instance passes through existing `abi-classify` unchanged (verified by `tests/abi/interop.nuc`); `.nuch` emits the template verbatim + generic methods; importer re-registers and re-stamps on demand; `sanitize-for-c` (`src/format.nuc`) maps dots (and any non-`[A-Za-z0-9_]` chars) to `_` for `--emit-cheader` only (`Vector.i32` → `Vector_i32`); LLVM IR keeps dotted names | Done | `emit-nuch-defstruct` (template-name branch added); `sanitize-for-c` (new helper, `src/format.nuc`); cheader path (`src/cheader.nuc`); `tests/abi/interop.nuc` + `tests/abi/clib.c` + `tests/expected/` ABI gate |
| T6 | **Examples, docs, progress** | Done | `examples/parametric.nuc`; `examples/import-parametric.nuc`; `lib/boxlib.nuc` / `lib/boxlib.nuch`; `tests/expected/parametric.out`; `docs/builtins.md`; this file; `design/progress.md` |

---

## Examples and tests

| File | What it covers |
|---|---|
| `examples/parametric.nuc` | Template definition, type application, methods, explicit construction `((Vector i32) ...)`, parametric-protocol (`Container E`) conformance, `usize` |
| `examples/import-parametric.nuc` | Cross-unit `.nuch` template export and re-stamp on import; uses `lib/boxlib.nuc` / `lib/boxlib.nuch` |
| `lib/boxlib.nuc` / `lib/boxlib.nuch` | Minimal library exporting a parametric struct template for import test |
| `tests/abi/interop.nuc` + `tests/abi/clib.c` | By-value ABI parity for a stamped `(P2 i32 i32)` across the C boundary |
| `tests/expected/parametric.out` | Expected output for `examples/parametric.nuc` |
| `examples/phantom-tyvar-test.nuc` | Cleanup §4a — generic methods over a template with phantom (field-less) trailing type params; positional tyvar recovery from the stamped receiver, including a phantom param in the return type and a verbose `MapIter`-style combinator |
| `examples/get-dispatch-test.nuc` | Cleanup C2.0 — value-keyed `get` dispatch: a parametric `(Bag K V)` `get:(Maybe V)` is selected for `CStr`/`i32` computed selectors, while a literal `'val` selector still does plain field access |

---

## Known limitations (deferred)

1. ~~**Colon binding sugar with a parenthesized RHS:** `name:(ref (Vector T))` does
   not tokenize. Use `(name (ref (Vector T)))`.~~ **Resolved** (cleanup §1): the
   reader now fuses a trailing-colon atom immediately followed by `(` into
   `(name <paren-form>)` (`fuse-colon-paren` in `lib/reader.nuc`). Both
   `name:(ref (Vector T))` and the list form compile identically.
2. **`declare` with a parametric return type** requires the list-form name node:
   `(declare (p2_make (P2 i32 i32)) (...))`.
3. ~~**Generic functions bounded on a parametric protocol** (`&where ((Seq E) Self)`) are
   not supported — the `&where` parser requires `(Var Protocol)` with plain symbols. The
   associated-types frontier is deferred to a future pass.~~ **Resolved** (A0–A2, associated
   types): the `&where` constraint now accepts `((Protocol Arg…) Var)` — a protocol application
   in the constraint head. Each `Arg` is recovered (if an unbound tyvar) or constrained (if
   concrete or already bound). Dispatch-time fixpoint binding reads recovered args from the
   conforming variable's stored conformance record. See `design/stage11/assoc-types.md` §7.
4. ~~**Generic combinators cannot conform to `Iterator` (no extend-site recovery).**~~ **Resolved (A4.0–A4.4, all complete).** A `&where` clause on `extend` runs A2's recovery fixpoint at stamp time, recording the per-instance `Conformance` with recovered args. A stamped `(MapIter IntRangeIter SqFn)` records `Conformance{Iterator, args=[i32]}` and is a first-class `Iterator`. `lib/iterator.nuc` has been rewritten: the `i64`-specialized `MapIterI64`/`FilterIterI64`/`CallI64`/`BinaryCallI64` types are retired; generic `MapIter`/`FilterIter`/`UnaryFn`/`FoldFn`/`reduce` are the library API. Combinators chain freely (`FilterIter` over `MapIter` works via bottom-up stamp recursion). `.nuch` round-trip of `&where`-bearing template extends is implemented (A4.3). Cross-unit test: `examples/assoc-types-extend-cross.nuc`. All 89 tests pass; byte-identical bootstrap. See `design/stage11/assoc-types-extend.md` for the full record.
