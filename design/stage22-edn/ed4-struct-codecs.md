# ED-4 — struct codecs

**Status:** designed 2026-10-02; **built 2026-10-03**, all of ED-4.0 … ED-4.6 (§6, "As built"). ED-4.1 is written up in [macro-definitions.md](macro-definitions.md) §6. Milestones ED-4.0 … ED-4.6. Built on the
decisions taken at the Stage 22 checkpoint ([overview.md](overview.md) §6, Q3–Q6),
and on two follow-ups the user answered the same day:

- A struct with no `(ns …)` is tagged `#user/Point`.
- An anonymous struct is tagged `#nucleus/struct`.

## Decisions this design implements

| Q | Decision |
| --- | --- |
| Q3 | A **compiler primitive** reports a struct's fields as a list of name/type pairs that a macro can walk. Derivation is **explicit**, so a library's codecs can live in an optional companion library (`geometry` → `geometry-edn`) that a program which never serializes those types does not import or link. |
| Q4 | **Tags are namespace-qualified**, as the EDN spec requires of user tags: `#geom/Point`, `#user/Point`, and `nucleus/` for builtins (`#nucleus/struct`). Reading checks that the tag equals the destination's qualified name exactly. |
| Q5 | **Strict.** A missing key is an error, and so is an unknown key. |
| Q6 | **Untagged collections:** a map reads into a `HashMap`, a vector into a `Vector`, a set into a `HashSet`. A named struct is always tagged. Key types the current `HashMap` cannot cleanly handle are excluded for now. |
| Q8 | Interning stays. A non-interning path is deferred within Stage 22. |

## 1. Ground truth (verified 2026-10-02)

- **Macro bodies run in the JIT, inside the compiler process**
  ([context/macros-jit.md](../../context/macros-jit.md)).
  - Compiler state reaches a macro body through special forms that lower to calls
    into functions the compiler binary exports. `gensym` → `nucleus_gensym`
    (`src/nucleusc.nuc:1092`) and `macro-error` → `nucleus_macro_error` (`:1117`)
    are the pattern to copy.
  - The `ast-*` reads are the same idea (`src/generics.nuc:3481`, with typing at
    `:3592`/`:3918`/`:6632`). They are a `node-type`↔`emit-node` lockstep site
    ([context/conventions.md](../../context/conventions.md)).
- **`StructDef`** (`src/compiler-types.nuc:308`):
  - `name` is the canonical key: `<ns>/<bare>` inside an `(ns …)`, the bare name in
    `user`.
  - `fields` is `?&(Vector &Field)`, in declaration order.
  - So the primitive has every fact it needs, the tag included.
- **A macro cannot emit an `extend` together with its methods**
  (`docs/macros.md:558`). It is worse than documented: a macro-produced `defn` is
  never registered as a method. It shadows rather than overloads, and a
  macro-produced template vanishes. The causes, a prototype fix, and its
  measurements are in [macro-definitions.md](macro-definitions.md).
- **A generic is read as the file that wrote it** (`docs/toplevel.md:280`).
  - A generic in `lib/edn` therefore cannot see a plain `edn-read` overload that
    `geometry-edn` defines.
  - It *does* reach a protocol method wherever the `extend` put it
    (`docs/generics.md:117`).
  - So element and field codecs must be protocol methods. That makes the macro
    `extend` limitation the crux of ED-4.
- **Protocol signatures may put `Self` in any position**, but pointer-ness must
  match exactly (`docs/generics.md:75`).
- **Collections** (`lib/vector.nuc`, `lib/hashmap.nuc`, `lib/hashset.nuc`):
  - **They do not drop their elements.** `drop` frees the buffers only
    (`lib/hashmap.nuc:342`).
  - **Types with both `Hash` and `Eq`:** `i32`, `i64`, `usize`, `f32`, `f64`,
    `StrView`, `CStr`, `Symbol`, `String`, `Keyword`. `Char`, `bool` and the
    collections themselves have no `Hash`.
- **The ED-3 codecs** (`lib/edn.nuc:391-586`):
  - `edn-read (dst:&T n:?&Node):ReadResult` for each scalar.
  - `edn-write (out:&String v:T):!void`, with each scalar passed by value.
  - The `&String` reader requires an *initialized* `String` and replaces its
    contents (`:576`).

## 2. Design

### 2.1 The primitive

Two macro-body special forms. Each lowers to a call into a compiler export, the
way `gensym` does:

| Form | Returns |
| --- | --- |
| `(struct-fields t)` | `((x i32) (y (Vector i64)) (z (struct a:i8 b:i8)))` — one `(name type)` pair per field, in declaration order |
| `(type-name t)` | the qualified name as a symbol: `geom/Point`, or `user/Point` in the default namespace |

- **Input.** `t` is a `Node`: the type as the macro's caller spelled it.
  - It resolves through the **calling file's** import environment, which is the
    file being compiled while the expansion runs (verified in ED-4.0).
  - `struct-fields` accepts a `(struct …)` type expression as well as a named
    struct.
- **Type spellings in the result** are canonical (registry keys), for a macro to
  *inspect*. The derived code never spells a field's type: it reaches each field
  through `(ref dst 'x)` and lets dispatch pick the codec. So a companion file
  needs no names beyond the struct itself.
- **Refusals,** reported at the macro's call site:
  - the type is not a struct;
  - the struct is a template, or a template instance;
  - it has bit-fields or anonymous members, which cannot be written as a
    `(name type)` pair;
  - the struct has no layout (an opaque C type). A struct defined below the
    macro call is not refused: the layout pre-scan has already laid it out
    (ED-4.0 item 5).
- **Format-agnostic.** Neither form knows about EDN. Another format's library
  derives from the same two forms (Q3).

### 2.2 Macro-produced definitions (compiler)

[macro-definitions.md](macro-definitions.md) has the full examination.
`toplevel-expand-macro` runs the file pre-scan's sequence (protocols, struct names,
signatures, values) over the forms it splices, before dispatching them. While it
does, `finalize-generics` never renames a method that already has a symbol.

- **What this gives.** Macro-produced `defn`s become real methods: they overload,
  and a template survives. A `(do (defn …) (extend …))` conforms whatever the
  order of its forms.
- **Measured on a prototype:** the suite and bootstrap are unchanged, and the
  self IR and every example compile byte-identically.
- **Why each form is registered once.** Signature registration is not
  idempotent. The file pre-scan does not descend into a macro call, so each
  spliced form is registered exactly once.
- **What remains.** Forward references to macro-produced definitions still follow
  definition order (`docs/macros.md:554`).
- **A bug to fix alongside it.** `(do …)` expansions in a namespaced library
  never reach its `.nuch` (macro-definitions.md §4). Every companion library is
  namespaced, so this blocks separate compilation of companions.

### 2.3 The `EdnCodec` protocol (`lib/edn.nuc`)

```lisp
(defprotocol EdnCodec
  (edn-decode  (dst:&Self n:?&Node):ReadResult)
  (edn-encode  (out:&String v:&Self):!void)
  (edn-release (v:&Self):void))
```

- **Method names.** The methods are internal names. The public `edn-read` and
  `edn-write` keep their ED-3 scalar overloads (by-value writes stay) and gain one
  generic overload each, bounded by `:where (EdnCodec T)`. A concrete overload
  outranks the generic one, so scalar calls do not change.
- **Ownership: one rule for every owning destination.** `dst` is *uninitialized
  storage*.
  - On `ok`, `dst` owns everything the decode built.
  - On `err`, it owns nothing: a partial decode releases what it built, in reverse
    order.
  - `edn-release` frees a successful decode deeply: a `Vector` of `String`s
    releases each element, then the vector.
  - Collections still do not drop their elements. `edn-release` is the EDN-aware
    deep free, and the collection library is unchanged.
  - **This changes ED-3's `&String` rule** (an initialized `String`, contents
    replaced) to the uninitialized-storage rule. Pre-release, so no shim.
- **Conformances in `lib/edn`:**
  - every ED-3 scalar, where `edn-release` is a no-op and `String` drops;
  - `(Vector T)`, `(HashSet T)` and `(HashMap K V)`, each conditional on its
    element types conforming (verified in ED-4.0).
- **Collections allocate** through the default allocator. An allocator-taking
  variant is out of scope.

### 2.4 Collections (Q6)

| EDN | Destination | Rule |
| --- | --- | --- |
| `[…]` | `(Vector T)` | A list `(…)` is `edn-type`. Strict, since EDN keeps the two distinct. |
| `#{…}` | `(HashSet T)` | `T` must be a key type (below). |
| `{…}`, untagged | `(HashMap K V)` | `K` must be a key type. A tagged map is `edn-type`. |

- **Key types:** `Keyword`, `StrView`, `i32`, `i64`.
  - **Excluded:**
    - `String`, which `HashMap` would leak, since it never drops keys. Interned
      `StrView` is the clean spelling.
    - Floats: a NaN key can never be found.
    - `Char` and `bool`, which have no `Hash`.
    - Collections and structs, which have no `Hash`.
    - Any other EDN key shape, which is allowed by the spec but excluded for now.
  - An excluded key type fails at compile time, with no matching `edn-decode`.
- **Writing.** A `Vector` keeps its order. A `HashSet` or `HashMap` writes in hash
  order, so a round trip compares the decoded values, not the text: `edn-eq`
  compares sets and maps in written order.

### 2.5 Struct codecs: `derive-edn` (`lib/edn.nuc`)

```lisp
(ns geometry-edn)
(import-use geometry)
(import-use edn)
(derive-edn Point Rect)
```

`(derive-edn T …)` expands, for each `T`, to three `defn`s plus their `extend`,
spliced at top level (§2.2):

- **`(defn edn-encode (out:&String v:&T):!void …)`** writes `#geom/Point {:x 1 :y 2}`:
  - keys are the field names as keywords, in declaration order;
  - each value goes through `edn-encode` on `(ref v 'x)`.
- **`(defn edn-decode (dst:&T n:?&Node):ReadResult …)`** checks, in order:
  1. The value is tagged and its tag equals `(type-name T)`. Otherwise
     `edn-wrong-tag`, naming both tags; an untagged map names the missing tag.
  2. The tagged value is a map. Otherwise `edn-type`.
  3. Every key is a keyword naming a field. Otherwise `edn-unknown-key`.
  4. Every field has a key. Otherwise `edn-missing-key`, at the map's line.
  5. Each field decodes through `edn-decode` on `(ref dst 'x)`. A failure
     releases the fields already built.
- **`(defn edn-release (v:&T):void …)`** releases each field, in reverse order.
- **Error paths accumulate.** A field's failure gets its key prefixed onto the
  message, so a nested failure reads
  `:a :x: expected an integer, got a string`, outermost first, at the inner
  value's line.
- **Anonymous-struct fields** (`(struct a:i8 b:i8)`) are expanded inline,
  recursively. They are written and read as `#nucleus/struct {:a … :b …}`. An
  anonymous struct gets no conformance of its own, so a collection of anonymous
  structs is out of scope.
- **Checks done in the macro.** It refuses pointer-like field spellings (`&…`,
  `?&…`, `ptr`, `(ptr …)`), naming the field. Any other field type with no
  `EdnCodec` conformance fails when the derived code is compiled: no matching
  `edn-decode`.
- **Nested named structs** dispatch through `EdnCodec`. A companion must import
  the companion that derived the inner type's codec. The type itself needs no
  import if the derivation's spelling reaches it.
- **Public calls.** `(edn-read &p n)` and `(edn-write &out &p)` reach these
  methods through the generic overloads in §2.3.

### 2.6 New errors (`lib/edn.nuc`)

| Code | When |
| --- | --- |
| `edn-wrong-tag` | the tag is missing, or is not the destination's qualified name |
| `edn-missing-key` | a struct field has no key in the map |
| `edn-unknown-key` | a key is not a keyword, or names no field |

## 3. Milestones

### ED-4.0 — ground truth

Small throwaway probes, each answering one question. Record the answers here
before building.

1. A macro-body special form that calls a compiler export resolves names in the
   **caller's** import environment. Probe with a prefixed import.
2. Conditional template conformance: `(extend (Vector T) EdnCodec)` with a
   generic `edn-decode (dst:&(Vector T) …) :where (EdnCodec T)` stamps for
   `(Vector i32)` and refuses `(Vector &i32)`.
3. A generic in one namespace reaches a protocol method that a third namespace's
   `extend` added. This is the companion-library shape.
4. Protocol methods returning `ReadResult` and `!void` conform and dispatch.
5. The probe from 1 also reports a struct's fields when the struct is defined
   *after* the macro call in the same file, or shows that it cannot. The answer
   decides the wording of the refusal in §2.1.

**Answers (2026-10-03):**

1. **Yes.** `(struct-fields g/Pt)` after `(import geom g)` resolves through the
   prefix: the JIT runs mid-expansion, while the calling file's environment is
   current.
2. **No, at first.** A plain `:where` constraint on a template `extend` was
   skipped (`nargs` 0), so `(extend (Box T) P :where (P T))` conformed every
   instance and refused the ones whose method could not stamp. Built as a
   condition (§6).
3. **Yes,** confirmed by ED-4.1's companion tests.
4. **Yes,** both conform and dispatch.
5. **It can.** The layout pre-scan lays out every struct in the file before any
   form is dispatched, so a struct defined below the call reports its fields.
   The "no fields yet" refusal is therefore only for a type with no layout at
   all (an opaque C type), and says so.

### ED-4.1 — macro-produced definitions (compiler) — **built 2026-10-03**

Exactly the plan in [macro-definitions.md](macro-definitions.md) §5:

1. late registration, plus the never-rename rule, for top-level macro expansions
   and top-level `macrolet` bodies;
2. the function-pointer binding check;
3. the `.nuch` splice bug;
4. tests of every probe, including the three-namespace companion shape compiled
   as one unit and through `.nuch`;
5. `docs/macros.md`;
6. the usual gates, plus byte-identical self IR against the previous compiler.

### ED-4.2 — `struct-fields` and `type-name` (compiler)

- **Change:** the two exports and the special-form lowering. Mind the
  `node-type`↔`emit-node` lockstep and the format-helper arity
  ([context/conventions.md](../../context/conventions.md)).
- **Tests:**
  - named, namespaced, `user` and anonymous structs;
  - a prefixed import;
  - each refusal in §2.1;
  - the diagnostics manifest.
- **Docs:** `docs/macros.md`, `docs/builtins.md`.
- **Gates:** as for ED-4.1.

### ED-4.3 — `EdnCodec` and collections (`lib/edn.nuc`)

- **Change:**
  - the protocol;
  - the scalar conformances;
  - the `&String` ownership change;
  - the collection conformances and key-type limits;
  - the generic `edn-read`/`edn-write` overloads;
  - `edn-release`;
  - `edn-wrong-tag`.
- **Tests:** a round trip for each collection; each key-type refusal; a partial
  decode that fails releases what it built (count allocations with a counting
  allocator).

### ED-4.4 — `derive-edn` (`lib/edn.nuc`)

- **Change:** the macro in §2.5, plus `edn-missing-key` and `edn-unknown-key`.
- **Tests:**
  - flat, nested and anonymous-field structs;
  - collection-typed fields;
  - every error, with its accumulated path and line;
  - the `user/` tag;
  - an expected-tag mismatch across namespaces;
  - a pointer field refused at the macro.

### ED-4.5 — companion-library test and example

- **Fixtures:** `tests/fixtures/` gets a `geometry` namespace and a
  `geometry-edn` companion.
- **Unlinked check:** a program that imports only `geometry` links nothing from
  `lib/edn` (check the object's symbols).
- **Example:** `examples/edn-struct.nuc` with `tests/expected/edn-struct.out`.
- **Headers:** regenerate `lib/edn.nuch` and `lib/edn.h`.

### ED-4.6 — docs and close-out

- `docs/edn.md`: a struct-codecs section, collections, ownership, the new errors,
  and the change to the `&String` rule.
- `docs/macros.md`: the primitive.
- `design/progress.md`, this document's as-built notes, and `context/` notes.

## 4. Out of scope (first pass)

- Generic and template structs.
- Unions and enums as field types.
- Pointer fields.
- Optional or nullable fields, and default values. Q5 is strict.
- Collections of anonymous structs.
- Allocator-parameterized decoding.
- Composite and float keys.
- Pretty-printing.
- Reading a tagged value whose type is chosen by its tag. The destination type is
  always known statically.

## 5. Risks

- **ED-4.0 item 2 fails** (no conditional template conformance). Fallback: emit
  per-instance collection conformances from `derive-edn` for each collection field
  type it sees. That works for fields, but not for a top-level `(Vector Point)`.
- **Order-dependent symbols** for late methods: the first macro-produced overload
  in a namespace keeps the solitary symbol. This is harmless, because headers
  record real symbols, but it is visible in IR (macro-definitions.md §3). An
  earlier worry here, that a macro re-emitting its own argument would get the
  argument registered twice, does not hold: the file pre-scan never descends into
  a macro call.
- **Hash-order writing** makes text-level golden output order-dependent. Keep
  golden tests to vectors and structs, and test sets and maps by decoded value.

## 6. As built (2026-10-03)

**Compiler.**

- **Conditional conformance** (`src/generics.nuc`): in
  `tmpl-conformance-check-one-in`, a plain constraint that fails for a stamped
  instance (`tmpl-plain-constraints-hold?`) skips the instance instead of
  checking its methods. The skipped check is queued on `g-pending-tmpl-checks`
  (`PendingTmplCheck`, `src/compiler-types.nuc`), and `conformance-add` retries
  the queue whenever it records a new conformance. That retry is what makes a
  `(Box Pt)` stamped by a field conform once a later `derive-…` expansion
  extends `Pt`. Inert on existing code: identical IR for every input.
- **`struct-fields` / `type-name`** (`src/nucleusc.nuc`): the exports
  `nucleus_struct_fields` / `nucleus_type_name` share `macro-struct-arg`, which
  resolves the type with `parse-type-from-node` and applies the refusals. A
  field's type node is `type-display` read back through the reader, so it is the
  user's spelling with canonical names (a `?&` pointer reads as `?ref:T`).
  Lowering in `emit-macro-type-query`; typing (`ty-ref-node`), the
  `gcheck-special-form` set, both JIT-module declares and the reserved-name set
  carry both names.
- **Refusals** are as §2.1, plus "only available inside a defmacro…" outside a
  macro body. A bare template name is caught before the type parse, which would
  otherwise say `unknown type`.

**`lib/edn.nuc`.**

- **Scalar conformances** come from a private macro, `edn-scalar-codec`, one call
  per type: the first use of ED-4.1 inside the standard library.
- **Key types** are a method-less marker protocol, `EdnKey`, extended by exactly
  `Keyword`, `StrView`, `i32` and `i64`. The set and map conformances require it
  beside `EdnCodec`.
- **A repeated map key** is checked at decode (`edn-dup-key`) even though
  `edn-parse` already refuses one, so a hand-built tree cannot leak the replaced
  value.
- **`derive-edn`** expands to one `edn-derive-struct` call and one `extend` per
  type. `edn-derive-struct` builds the three functions from `struct-fields`. The
  derived code calls only `lib/edn` helpers (`edn-put`, `edn-struct-map`,
  `edn-struct-keys`, `edn-at-key`, `edn-failed?`) and the protocol methods.
- **Anonymous-struct fields** get three gensym-named functions of their own
  (a nested `edn-derive-struct` with tag `nucleus/struct`), not inline code: the
  field's decode needs its own `return`s.
- **The macros call only the compile-time runtime** (node builders, `String`,
  `symbol-intern`), never a `lib/edn` function, so a derivation needs no
  compile-time mirror and cross-compiles. `edn-str-node`, which builds a string
  literal node, is a public macro because the exported `edn-derive-struct`
  expands it in the importer.
- **No hygiene.** The expansion names `lib/edn` functions bare, so a deriving
  file needs `(import-use edn)` (documented in `docs/edn.md`).
- **Paths** name struct keys only; a vector element's index is not part of the
  path (`:replicas :port: …`).

**The unlinked check** compares IR rather than object symbols: a program that
imports only the type library has no `@edn` symbol in its `--emit-llvm` output.

**Tests:**

- In `tests/suite-s22.nuc`:
  - `s22-struct-fields`
  - `s22-conditional-conformance`
  - `s22-conditional-conformance-retry`
  - `s22-edn-collections`
  - `s22-derive-edn-flat`
  - `s22-derive-edn-nested`
  - `s22-derive-edn-release` (glibc `mallinfo2` around 20,000 failing and
    succeeding reads; skipping one release shows as megabytes)
  - `s22-edn-companion` (with the unlinked check)
  - `s22-edn-companion-nuch`
  - `s22-ref-of-marker-named-local`: an incidental fix. `&rest` in an
    expression is `(ref rest)` again; it had been the reader's unexpanded
    legacy-marker symbol.
- Diagnostics manifest rows: `s22-struct-fields-not-struct`, `-template`,
  `-instance`, `-bitfield`, `-runtime`, `s22-type-name-anon`,
  `s22-derive-edn-pointer`, `s22-edn-key-type`.
- The golden example `examples/edn-struct.nuc`.

**Gates:**

- `make test`: 1275 passed, plus the 5 known LLVM-22 data-layout failures;
- `make bootstrap` PASS;
- `check-headers` clean (89);
- dump-ast corpus: only the edited sources differ;
- IR identical to the pre-ED-4.2 compiler for the 213 inputs it can compile;
  `lib/edn.nuc` and `examples/edn-struct.nuc` use the new forms.
