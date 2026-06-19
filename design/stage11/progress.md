# Stage 11 Progress — Parametric Structs & Collections

Parametric structs: **done** (T0–T6). Collections: **in progress** (M1–M5 done).
Cleanup: §1 (colon-paren sugar), §2 (keyword/StrView), §3 (iterator-test flatten), §4a (phantom tyvar) — all **done**.
Back to [../progress.md](../progress.md)

86 tests pass; `make bootstrap` is a byte-identical fixed point.

---

## Stage 11 collections (`design/stage11/collections.md`)

| Task | Description | Status | Key functions / files |
|---|---|---|---|
| M1 | **Allocator protocol + default + arena conformance** — the `Allocator` protocol (the design's Zig-shaped `alloc`/`realloc`/`free` contract); a tagged `AllocHandle` (`{kind, data}`) a collection stores in one field and dispatches through; libc + arena backends behind `alloc-handle-{alloc,realloc,free}`; a process-global default (libc) handle; field-setting constructors `libc-allocator` / `arena-allocator`. Compiler bugfix: aggregate-typed `defvar` globals now emit `zeroinitializer` (was an invalid `0`). The old `Seq` protocol in `lib/seq.nuc` renamed to `IntIndexable` to free the `Seq` name for the M3 collection protocol. | Done | `lib/allocator.nuc` (protocol, `AllocHandle`, `AllocKind`, helpers, `g-default-alloc`, `default-allocator`); `lib/seq.nuc` (`IntIndexable`); `examples/allocator-test.nuc` + `tests/expected/allocator-test.out`; `emit-defvar` aggregate-init arm (`src/nucleusc.nuc`) |
| M2 | `Iterator` protocol, `into`, `doseq`; lazy `map`/`filter`/`reduce` | Done | `lib/iterator.nuc` (`Iterator` parametric protocol, `IntRangeIter`, `I64ArrayIter`, `MapIterI64`, `FilterIterI64`, `BinaryCallI64`, reduce functions); `lib/seq.nuc` (`BinaryCall`); `lib/macros.nuc` (`doseq`, `into`); `examples/iterator-test.nuc` + `tests/expected/iterator-test.out` |
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
   function-object type `F`. The `callfn`/`foldop` call is resolved at stamp time.
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
   enforced structurally at stamp time (no `&where` bound — the parametric-protocol `&where`
   frontier is still deferred), so a `K` lacking either errors with a missing-method
   diagnostic when the table is first stamped.
3. **FNV-1a folds bytes; the offset basis is a signed-literal trick.** Scalars fold every
   value byte little-endian, `CStr` folds chars to the NUL. The 64-bit offset basis
   `0xcbf29ce484222325` has its high bit set, so it is written as the two's-complement
   decimal `-3750763034362895579` (the same constant the compiler's own `hash-struct-shape`
   seeds with) — the unsigned hex would overflow the signed-literal range. The fold runs in
   `i64` and is cast to `usize` at the end (the protocol's return type).
4. **HashMap does NOT extend `(Coll E)`.** `Coll`'s `conj` takes a single element `E`, but a
   map insert needs both a key and a value, so the element type is ambiguous. HashMap extends
   only `(Assoc K V)` and `Drop`; `count`/`empty?` are standalone generic methods (callable by
   receiver-type dispatch, no protocol needed). HashSet extends `(Coll T)` normally (`conj` ==
   `insert`).
5. **`get`/`keys`/`vals` are standalone, not protocol methods.** Their result types are
   derived from `Self` (`hmap-get → (Maybe V)`; the key iterator type varies by `Self`), an
   associated-types shape the protocol machinery cannot express. `Assoc` carries only
   `assoc`/`dissoc`; `Set` carries `union`/`difference`/`intersection`/`contains?`. Each
   concrete map/set provides the rest as ordinary generic functions (`hmap-get`,
   `hmap-iter-keys`, `hashset-iter`).
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

---

## Known limitations (deferred)

1. ~~**Colon binding sugar with a parenthesized RHS:** `name:(ref (Vector T))` does
   not tokenize. Use `(name (ref (Vector T)))`.~~ **Resolved** (cleanup §1): the
   reader now fuses a trailing-colon atom immediately followed by `(` into
   `(name <paren-form>)` (`fuse-colon-paren` in `lib/reader.nuc`). Both
   `name:(ref (Vector T))` and the list form compile identically.
2. **`declare` with a parametric return type** requires the list-form name node:
   `(declare (p2_make (P2 i32 i32)) (...))`.
3. **Generic functions bounded on a parametric protocol** (`&where ((Seq E) Self)`) are
   not supported — the `&where` parser requires `(Var Protocol)` with plain symbols. The
   associated-types frontier is deferred to a future pass. Conformance is exercised via
   `extend` + stamp-time checking + ordinary overload resolution (the `examples/parametric.nuc`
   working pattern).
