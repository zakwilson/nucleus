# Stage 14 — Type safety: retiring the untyped-pointer legacy

The compiler is largely typed at the surface — parametric structs, protocols,
tagged unions, `(ref T)`/`(Maybe T)`, closures, allocators — but its own
*internals* still carry a large body of pre-type legacy: cross-references between
core records are declared as elem-less `ptr`, and every read of such a field is
re-decorated with a `(cast ptr:T …)` that merely re-attaches a statically-known
type the compiler could have tracked all along. There are **3,674** `(cast …)`
forms across `src/` today; the plurality of them are pure ceremony.

This stage removes that ceremony. It replaces untyped `ptr` fields, parameters,
and returns with concrete typed pointers / `CStr` / typed collections; folds
integer-tag dispatch that is really a closed sum into `defunion`/`match`; and
element-types the registry `Vector`s so the compiler's own data structures carry
their real types. The payoff is fewer casts (each one is a place a wrong type can
hide), typed field access, exhaustiveness checking on the sums, and the compiler
dogfooding the type-safety features it grew for its users.

This is the type-safety complement to Stage 13's loop-safety dogfooding. It is
**not** a new language feature — every facility used here already ships. Like the
Stage 11 parametric-structs work and the Stage 13 registry migration, most of it
is representation-inert and stays byte-identical; the structural changes take a
controlled reconverging refresh.

---

## Relationship to Stage 13 functional-refactor

Stage 13's [functional-refactor.md](../stage13/functional-refactor.md) already did
the *substrate* and *loop* half of the cleanup. Stage 14 does the *type* half.
They are complementary and must not be confused:

| | Stage 13 R2 / R3 (done) | Stage 14 (this doc) |
|---|---|---|
| **R2 — registry substrate** | Migrated ~18 hand-rolled `g-X:ptr`+`g-num-X`+`memcpy` growables to `(ref (Vector ptr))`. **Substrate only** — the element type stayed `ptr`, the handler tables kept concrete pointer entries. Byte-identical. | Element-*types* those Vectors: `(Vector ptr)` → `(Vector (ref StructDef))` etc., deleting the per-consume `(cast ptr:X (invoke …))`. |
| **R3 — compiler loops** | Converted counted loops to `dotimes` and AST cdr-list walks to `doseq-iter`/`ListIter`. **Loops, not types.** Explicitly left every registry lookup as `dotimes` (combinators crash over a `(VecIter ptr)`). | Leaves the loop *shape* alone; types the *elements* the loops read and the *fields* they dereference. |
| **What's untouched by 13** | Field types in `compiler-types.nuc`; elem-less `:ptr` params/returns; the integer-tag sums (`Cleanup`, `AbiInfo.kind`, `MethodKind`, `UnionDef.layout`); the parallel-array-as-struct patterns; the type-erasure memos R2 left out of spec. | **All of the above** — this is the entire Stage 14 scope. |

The one-line distinction: **R2/R3 changed how the compiler *loops* and where its
arrays *live*; Stage 14 changes what its records *are*.** Stage 14 keeps R3's
zero-cost invariant verbatim (no `(dyn P)`/`BoxedFn`/boxing on the prescan / JIT /
emit hot paths; the handler tables `g-macros`/`g-rmacros`/`g-binops`/
`g-cast-rules`/`g-blanket` keep their concrete struct-pointer element type —
typed elements, yes; type erasure, no) and reuses R2/R3's bootstrap-policy axis
(byte-identical where inert, controlled reconverging refresh where structural).

---

## Authoritative decisions (do not re-litigate)

1. **`(raw T)`-first, `(ref T)`-selective.** Retype an untyped `ptr` field or
   parameter to the *nullable* `(raw T)` (or `CStr`) first. This is
   representation-inert and adds **zero** new flow obligations: `pkind-flow-check`
   (type-utils.nuc:274) returns early for any destination whose pkind is not
   `PTR-REF`, and `(raw T)` is `PTR-RAW`. Promote a field/param to the *non-null*
   `(ref T)` only where non-null is a genuine invariant *and* every write site is
   known-non-null — because `(ref T)` turns the flow check **on** at those writes.
   *(Ground-verified: §"Ground-truth corrections".)*

2. **Registries stay ordered `Vector`s; `HashMap` is a side index only.**
   `g-strs`/`g-structs`/`g-uniondefs`/… are iterated in insertion order to emit
   reproducible IR (string table, struct declarations, `.nuch` output). Element
   typing them is fine; **reordering them is not**. A `HashMap` name→record index
   may be added *beside* an ordered Vector to speed a hot linear-scan lookup, but
   never as the registry's storage-of-record. (Consensus: only if profiling ever
   justifies it — see deferred.)

3. **Registry elements become `(ref RecordType)`.** Registry entries are always
   non-null (each is a freshly `arena-alloc`'d record `conj`'d in), so `(ref T)`
   is the honest element type; the `conj` sites store a value that is non-null by
   construction. Lookups that can miss still return `(Maybe (ref T))` / `?ptr:T`.
   *(String-keyed registries like `g-fnty-names` become `(Vector CStr)`.)*

4. **Zero-cost hot path is preserved exactly (type erasure stays out).** No
   `(dyn P)`/`BoxedFn`/heap box/indirect call is added to the prescan / JIT-macro
   / emit hot paths. Handler tables keep concrete struct-pointer elements. This is
   the Stage 13 invariant, unchanged.

5. **Closed sums fold to `defunion`/`match` — without relayout where possible.**
   `Cleanup` (the pilot), `MethodKind`, `AbiInfo.kind`, and `UnionDef.layout`
   become tagged sums / `case` dispatch so the compiler checks exhaustiveness. The
   two hottest and most-mutated structures, **`Type` and `Node`, stay plain
   structs** (deferred — see §Deferred, with reasons).

6. **Bootstrap: byte-identical for pointer-for-pointer retyping + cast deletion;
   controlled reconverging refresh for structural change.** Reuse the Stage 13
   axis. `make update-bootstrap` only at stable milestones, and the boot must
   re-converge to a fixed point (`build/stage2.ll == build/nucleusc.ll`) with
   tests green throughout.

---

## Non-negotiable invariants

- **Byte-identical where inert.** Retyping an elem-less `ptr` destination to
  `(raw T)`/`CStr` and deleting the now-redundant `(cast …)` at its read sites is
  IR-identical (`(raw T)` and `CStr` both lower to `ptr`; the cast was a no-op).
  Verify per batch by snapshotting `build/nucleusc.ll`, applying the change,
  rebuilding, and `diff`-ing: a non-empty diff on an inert batch is a bug.
  `make bootstrap` (stage1==stage2) does **not** catch a lost strcmp or a wrong
  narrowing — the before/after IR diff does (conventions.md, "Verifying a
  behavior-neutral type migration").
- **Controlled refresh must re-converge.** Element-typing a Vector changes its
  mangled instance name (`%Vector.ptr` → `%Vector.StructDef`) and drifts IR;
  array-of-struct changes layout; a `defunion` conversion changes a struct into a
  `{tag,payload}`. These take a one-time `make update-bootstrap` per milestone,
  after which stage1==stage2 must hold and all tests pass.
- **Deterministic emit order.** The Vector migrations preserve insertion order
  (Vector is append-only). Any `HashMap` side index is additive.
- **`CStr` is `strcmp`, not identity.** Never retype a `ptr`→`CStr` on a field
  compared by pointer identity (notably any interned-symbol path, e.g. `Node.s`):
  `=`/`!=` on a `CStr` operand lowers to `strcmp`. Retype to `CStr` only where the
  content comparison is what's wanted (and it usually is — it deletes an explicit
  `(= (strcmp a b) 0)`). *(conventions.md, "CStr is ABI-identical to ptr".)*
- **`node-type`↔`emit-node` lockstep.** Any change to the result type an `emit-*`
  returns must update the matching `node-type` branch in the same change
  (conventions.md). Field/param retyping that changes a returned `Val`'s element
  type touches both.
- **LLVM opaque handles stay `ptr`.** `Sym.tracker`/`trace-tracker`
  are LLVM C-API handles with no Nucleus type; they stay `ptr` forever.
  *(Correction, 2026-07-12: this bullet previously also listed `trace-saved` as an
  "LLVM opaque handle" — that is wrong; `trace-saved` holds a saved copy of `ir-name`,
  a C string. It still stays `ptr`, but for the identity reason below, not because it
  is an LLVM handle.)*
- **Identity-compared C strings stay `ptr`, not `CStr`.** `Sym.ir-name` (and
  `trace-saved`, which mirrors it) are freshly-formatted, **non-interned** C strings
  compared by *pointer identity* (`import-alias-one`) and null-checked
  (`inject-import-aliases`). A `CStr` retype lowers `=`/`!=` to `strcmp`, and
  `(= ir-name null)`→`strcmp(x, null)` **crashes**. Content comparison of an ir-name,
  where genuinely wanted, is already spelled explicitly (`program-defn-lookup`'s
  `strcmp`). This generalizes the `Node.s` rule to any non-interned, identity-keyed
  string field.
- **`?`/`!` stay out of emitted names** and format-helper arity stays exact
  (conventions.md) — unchanged constraints, listed so a sweep doesn't trip them.

---

## Ground-truth corrections (verified against the tree, 2026-07-02)

Four read-only surveys seeded this plan; the starred claims were re-checked
against the code and the compiler was actually run. Corrections:

1. **The "prelude types can't appear in `nucleusc.nuc` signatures" constraint is
   STALE — there is no enabling fix to do.** The Stage 10 N2 note (and the
   leftover comment at `nucleusc.nuc:8398`, "spelled `:ptr` because Node is a
   prelude type and the toplevel signature prescan runs before the prelude
   import") predates `prescan-imported-types` (`nucleusc.nuc:7913`), which the
   driver now runs for the outermost unit only (`g-toplevel-depth == 1`,
   `nucleusc.nuc:8234-8235`) precisely to "pre-register imported types so this
   unit's defn signatures can name prelude types and the `!T` sugar." Evidence:
   **384** existing `nucleusc.nuc` signatures already name `compiler-types.nuc`
   structs (`emit-node:ref:Val (n:ptr scope:ref:Scope)`, `?ptr:Method`, etc.), and
   `make-vec`'s signature is a *parametric* `(ref (Vector ptr))`. Empirically
   confirmed: a fresh toplevel unit with
   `(defn make-str-node:ref:Node (…))` / `(defn node-kind-of:i32 (n:ptr:Node))`
   compiles cleanly (exit 0; `%Node = type {…}` and both `@`-signatures emitted).
   **Consequence:** idiom 6 (typing elem-less `:ptr` params/returns) is fully
   reachable in `nucleusc.nuc` itself — the finding's hedge "as far as the
   prelude-signature constraint allows" is void. The `import-list-push` `:ptr`
   comment is deleted when field/param typing reaches it (a comment fix, not a
   compiler change).

2. **The *real* friction at those sites is the Phase-F pointer semantics, not
   prescan ordering.** After the Stage 10 flip, `ptr:T` / `(ptr T)` mean **non-null
   `PTR-REF`**; raw is `(raw T)`. So a linked-list cursor that reads a `(raw Node)`
   link field (`Node.car`/`cdr` are `(raw Node)`, prelude.nuc:18-19) must itself be
   typed `(raw Node)`, not `ptr:Node`. Empirically: an `ilf` traversal with
   `cur:ptr:Node` dies with *"assignment: raw pointer where non-null (ref …) is
   required"* at `(set! cur (cur cdr))`; retyping the cursor `cur:(raw Node)`
   compiles clean (exit 0). This is exactly why decision 1 says `(raw T)`-first.

3. **`Cleanup.defer-scope` is already `ref:Scope`** (compiler-types.nuc:257), and
   the dispatch site does a **redundant** `(cast ref:Scope (cl defer-scope))`
   (nucleusc.nuc:4988) — a leftover cast on an already-typed field, deletable in
   this stage. Several `name`-family fields are already `CStr`
   (`StructDef.name`/`Sym.name`/`Generic.name`/`Conformance.type-name`/
   `proto-name`), so the field-typing sweep should skip them, not "reclassify" them.

4. **The census is slightly larger than reported and the `Type` struct sits at a
   different line.** Tree-wide `(cast …)` = **3,674**; `ptr:Node` **745**,
   `ptr:ptr` **556**, `ptr:Type` **276**, `ptr:Val` **119**, `ptr:StructDef` **87**,
   `ptr:Method` **57**, `ptr:Sym` **38**, `ptr:Generic` **28**, `ptr:UnionDef`/
   `ptr:Scope` **18** each. The `Type` struct is at compiler-types.nuc:**179** (not
   the ~58-71 the finding cited — line anchors below are re-verified). There are
   **26** `(ref (Vector ptr))` registry globals tree-wide (finding said ~24).

Everything else the surveys reported was confirmed: `pkind-flow-check`'s
elem-less exemption; `Scope.syms` holds inline `Sym` values and `scope-define`
returns a `ref:Sym` *into* that array; the `Cleanup` three-shape sum and its
null-probe dispatch; the parallel arm/constraint arrays; the hand-rolled
growables R2 left behind.

---

## Idiom inventory (verified file:line anchors)

Grep by name — line numbers drift. Anchors are as of 2026-07-02.

### 1. Untyped cross-reference fields in `compiler-types.nuc`

The root cause. Every `ptr` below is a statically-known type re-attached by a cast
at each read site:

- **`Type`** (179-201): `ret`→`Type*`, `elem`→`Type*`, `params`→`Type*[]`,
  `sdef`→`StructDef*`, `opt-defaults`→`Node*[]`, `param-names`→`CStr[]`.
- **`StructDef`** (114-132): `field-names`→`CStr[]`, `field-types`→`Type*[]`,
  `src-file`→`CStr`, `udef`→`UnionDef*`, `origin-template`→`StructTemplate*`,
  `origin-args`→`Type*[]`. (`name` already `CStr`.)
- **`UnionDef`** (139-152): `sdef`/`union-sd`→`StructDef*`, the 5-wide arm arrays
  (`arm-names`→`CStr[]`, `arm-ptypes`→`Type*[]`, `arm-fnames`→`CStr*[]`,
  `arm-ftypes`→`Type**[]`, `arm-nfields`→`i32[]`), `niche-elem`→`Type*`.
- **`Sym`** (211-246): `type`/`ntype`→`(raw Type)`, `home`/`taint`→`(raw Scope)`,
  `const-val`/`cslot`/`src-file`/`docstring`→`CStr`, `ir-name`/`trace-saved`→
  **stay `ptr`** (identity-compared / non-interned — see invariants; the census
  originally listed these two as `CStr`, which is wrong),
  `tracker`/`trace-tracker`→**LLVM opaque, stay `ptr`**. *(Done 2026-07-12, §14.2.)*
- **`Scope`** (268-275): `parent`→`Scope*`, `syms`→inline `Sym[]` (see idiom 4),
  `cleanup-slots`→`Cleanup*[]`.
- **`Val`** (282-297): `type`→`Type*`, `taint`→`Scope*`, `val`→`CStr`.
- **`Method`** (338-363), **`Generic`** (365-377), **`Protocol`** (385-394),
  **`ProgDefn`** (319-324), **`MonoJob`** (445-447), **`Conformance`** (405-409),
  **`TmplConformance`** (428-440), **`CastRule`**/**`BinOp`**/**`LabelEntry`**/
  **`NarrowUndo`**/**`RMacro`**/**`MacroDef`** — the same pattern.

The precedent that this works: `Node.car`/`cdr` are already `(raw Node)`
(prelude.nuc:18-19) and `Cleanup.defer-scope` is `ref:Scope`
(compiler-types.nuc:257). The untyped fields are pure legacy.

### 2. `(Vector ptr)` registries with untyped elements — **DONE (2026-07-06, see §14.1)**

All 26 registries now carry typed elements. (The original census: 26 globals via
`defvar (g-… (ref (Vector ptr)))`. Producer idiom was `(conj g-X (cast ptr rec))`;
consumer idiom was `(cast ptr:X (invoke g-X (cast usize i)))`.) Element types by
registry:

| Registry | Element | Registry | Element |
|---|---|---|---|
| `g-structs` | `StructDef` | `g-generics` | `Generic` |
| `g-uniondefs` | `UnionDef` | `g-protocols` | `Protocol` |
| `g-enumdefs` | `EnumDef` | `g-conformances` | `Conformance` |
| `g-union-templates` | `UnionTemplate` | `g-tmpl-conformances` | `TmplConformance` |
| `g-struct-templates` | `StructTemplate` | `g-mono-worklist` | `MonoJob` |
| `g-strs` | `StrLit` | `g-binops` | `BinOp` |
| `g-cast-rules` | `CastRule` | `g-macros` | `MacroDef` |
| `g-macro-decls` | `CStr` *(name-string dedup set, not MacroDef)* | `g-rmacros` | `RMacro` |
| `g-program-defns` | `ProgDefn` | `g-lbl-tbl` | `LabelEntry` |
| `g-nundo` | `NarrowUndo` | `g-pending-unions` | (pending record) |
| `g-fnty-names` | `CStr` | `g-fnty-types` | `Type` |
| `g-deferror-name-sids` | `i32`-boxed sid | `g-deferror-msg-sids` | `i32`-boxed sid |
| `g-proto-supers` | (proto-super pair) | `g-blanket` | (blanket entry) |

Lookup functions are linear scans: `enumdef-lookup` (nucleusc.nuc:6669-region),
`generic-lookup` (generics.nuc:~17), `uniondef-lookup` (union-registry.nuc:561),
`conformance-lookup` (generics.nuc:2056+, keyed by a *string pair* via
`conformance-args-eq`, generics.nuc:2089).

### 3. Parallel arrays that are really array-of-struct

- **UnionDef 5-wide arm arrays** — built union-registry.nuc:789-800, scanned
  :611-618 (`(aref (cast ptr:ptr (ud arm-ptypes)) i)` etc.). Replacement: an
  `Arm{name, ptype, fnames, ftypes, nfields}` element in a `(Vector (ref Arm))`.
- **Method `&where` constraint quad** `con-protos`/`con-vars`/`con-args`/
  `con-nargs` (compiler-types.nuc:352-361; used generics.nuc:1250, :1389, :1433,
  :1678; `con-args` is ragged). Replacement: `Constraint{proto, var, args}`.
- **TmplConformance mirrors the quad** (compiler-types.nuc:436-440).
- **StructDef `field-names`/`field-types`**, **Type `params`/`param-names`/
  `opt-defaults`** — parallel arrays → `Field{name, type}` element.
- **`Conformance.args`** is a `CStr[]` compared by `strcmp` via
  `conformance-args-eq` (generics.nuc:2089-2094) → `(Vector CStr)` with a
  value-equality helper.

### 4. Remaining hand-rolled growables (survived Stage 13 R2)

- **`Scope.syms`** + `len` + `cap` — inline `Sym[]`, grown scope.nuc:28-35 (arena
  realloc + `memcpy` of `(sizeof Sym)` values), read scope-lookup:59-63.
  `scope-define` returns `(cast ref:Sym sym)` = a pointer **into** the array
  (scope.nuc:36,43) — a pointer-stability hazard for a Vector migration (§14.5).
- **`Scope.cleanup-slots`** + `ncleanups` + `ccleanups` — `Cleanup*[]`, grown
  scope.nuc:82-89.
- **`Generic.methods`** + `num-methods` + `cap` — `Method*[]`, grown
  generics.nuc:43-50 (`aset! (cast ptr:ptr (gg methods)) …`).
- **vtable memo** `g-vtable-keys`/`g-vtable-names` (nucleusc.nuc:3799-3800).
- **`g-ns-prefix-keys`/`g-ns-prefix-vals`** (nucleusc.nuc:393-394).
- **type-erasure memos R2 left out of spec** (see [progress.md] R2 note):
  `g-boxedfn-keys`/`-types`/`-count`/`-cap` (union-registry.nuc:369-396) and
  `g-dyn-keys`/`-types`/`-protos`/`-count`/`-cap` (union-registry.nuc:467-500) —
  cap-doubling arena arrays.
- **`g-include-paths`/`g-link-args`** — fixed 64-slot `malloc`
  (nucleusc.nuc:399/9333, :322/9249).

*(`g-fnty-names`/`g-fnty-types` are **already** `(Vector ptr)` — R2 migrated the
substrate; Stage 14 only element-types them, §14.1.)*

### 5. Integer-tag dispatch that is really a closed sum

- **`Cleanup`** (compiler-types.nuc:251-257) — doc-comment literally says "Exactly
  one shape is set": legacy libc free (slot only) / Drop call (slot + drop-\*) /
  `defer` (defer-node + defer-scope). Dispatched by null-probing at
  nucleusc.nuc:4984-4993 (`(cond (!= (cl defer-node) null) … (!= (cl drop-fn)
  null) … else …)`). **The `defunion` pilot.**
- **`AbiInfo.kind`** (`AbiKind`: `ABI-DIRECT`/`ABI-MEMORY{size,align}`/
  `ABI-COERCE1{reg0}`/`ABI-COERCE2{reg0,reg1}`) — 25 dispatch sites in abi.nuc.
- **`MethodKind`** (`METHOD-INTRINSIC`/`-USER`/`-GENERIC`) — 31 compares in
  generics.nuc.
- **`UnionDef.layout`** (`LAYOUT-ENUM`/`-NICHE-MAYBE`/`-NICHE-ERRPTR`/`-TAGGED`)
  + `niche-elem` payload — 26 dispatch sites across union-emit.nuc/union-registry.nuc.
- **`Type.kind` ladders** (near-identical in type-utils.nuc:43-207,
  type-mangle.nuc:14-122, abi.nuc:30-53, `type-eq` generics.nuc:106-132; ~171
  dispatch sites tree-wide) and **`NodeKind`** compares — the kind-ladder→`case`
  sweep candidates, **without relayout** (`Type`/`Node` stay structs).

### 6. Elem-less `:ptr` params/returns for statically-known types

~194 `:ptr` params across generics/union files, 62 `defn …:ptr` + ~671 bare-`ptr`
params in nucleusc.nuc, and nearly every top-level fn in cheader/nuch/repl.
`scope-define` takes `s:ptr` then casts to `ptr:Scope` (scope.nuc:19). Retyping a
`ptr`→`(raw T)`/`(ref T)` param or return is ABI/IR-identical (both lower to
`ptr`). **Fully reachable in `nucleusc.nuc` — see ground-truth correction 1.**

### 7. `ptr:ptr`/`ptr:i32` out-parameter boxes

`split-typed`/`extract-name-type` (nucleusc.nuc:656-695), io-ntv counters
(generics.nuc:656-681), `generic-binds-for` (generics.nuc:199),
`union-layout-classify` niche-elem-out (union-registry.nuc:657); ~40 `addr-of`
box sites in generics.nuc. Replacement: small result structs / `(Maybe T)` /
typed `ref:i32`. **Low priority — deferred (multi-value-return ergonomics).**

### 8. Import/prescan cons-cell lists in bare-`ptr` globals

`import-list-*` (nucleusc.nuc:8386-8426), `g-imported` family. Node-based
intrusive cons lists. **No longer blocked** (correction 1) — reachable as
`?ptr:Node`/`(raw Node)`, but low-value; the `:ptr` comment is corrected here.

---

## Problem → facility mapping

| Legacy idiom | Type-safe facility | Effect |
|---|---|---|
| Elem-less `ptr` field + `(cast ptr:T (obj f))` at reads | `(raw T)` field (idiom 1) | deletes the read casts; field access is direct |
| `ptr` field holding an interned symbol name, compared by content | `CStr` field | deletes `(= (strcmp …) 0)`; `=` lowers to strcmp |
| `(Vector ptr)` registry + `(cast ptr:X (invoke …))` | `(Vector (ref X))` (idiom 2) | deletes the consume casts; typed element |
| Parallel arrays walked in lockstep by index (idiom 3) | element struct `Field`/`Arm`/`Constraint` in a typed `Vector` | one indexable record; deletes ragged `aref (cast ptr:ptr …)` |
| Hand-rolled `g-X`+`len`+`cap`+`memcpy` growable (idiom 4) | `(ref (Vector (ref X)))` + `conj`/`count`/`invoke` | deletes the grow thunk |
| Integer tag + null-probe / `cond` ladder (idiom 5) | `defunion` + `match` (Cleanup) or `case` over the enum | exhaustiveness-checked dispatch |
| Elem-less `:ptr` param/return (idiom 6) | `(raw T)`/`(ref T)`/`CStr` param/return | callers/callees typed end-to-end; deletes body casts |
| `ptr:ptr` out-param box (idiom 7) | result struct / `(Maybe T)` / `ref:i32` | deferred |

---

## Leave-alone (do not touch)

| Zone | Reason |
|---|---|
| `abi.nuc` IR-text lowering (`abi-class-eightbyte`, class/offset loops) | Byte-exact IR generation; a wrong reorder is an ABI bug. (`AbiInfo.kind`→`defunion` is the *only* candidate here, and it's optional — §14.6.) |
| `cheader.nuc` C-lexer byte scanning (`c-skip-ws`/`c-parse-type`/…, lines ~35-533) | State-machine over raw bytes; typing the cursor hides control flow. |
| `nuch.nuc` / `cheader.nuc` text emitters | Produce exact `.nuch`/C output; leave the string plumbing. |
| `Sym.tracker`/`trace-tracker`/`trace-saved` | LLVM C-API opaque handles — no Nucleus type exists. Stay `ptr`. |
| `g-tmpl-conf-check-hook` and other fn-ptr hooks | Genuinely type-erased late-binding hooks (Stage 12 N8 pattern); not a re-typing target. |
| Stage 13 R3 leave-alone list | Convergence fixpoints, `match`-lowering, hash-probe internals, iterator `next` bodies — reaffirmed. |
| Handler tables `g-macros`/`g-rmacros`/`g-binops`/`g-cast-rules`/`g-blanket` | Element-type them (idiom 2) but keep concrete struct-pointer entries — no `(dyn P)`/`BoxedFn` (zero-cost invariant). |

## Deferred (record with reasons)

| Deferred item | Reason |
|---|---|
| **`Type` → `defunion`** | Hottest structure; shared mutated singletons (`type-with-volatile`/`type-as-pkind` clone in place); `defunion` relayout would cascade through `type-to-ir`/`type-size`/`type-eq`/`type-mangle-token` and re-layer the bootstrap. Kind-ladder→`case` (idiom 5) is fine; the *struct* stays. |
| **`Node` → `defunion`** | The AST spine; a shared mutated structure the reader tail-splices. Same re-layering cost. Stays a struct (Stage 13 already declined to migrate its representation). |
| **`Node.car`/`cdr` → `?ptr:Node`/`(ref Node)`** | Whole-tree obligation cascade: every cdr-walk cursor and macro that chains field access would need narrowing. They stay `(raw Node)`. |
| **Out-param boxes (idiom 7)** | Wants multi-value-return ergonomics that don't exist yet; result-struct rewrites are churn until then. |
| **Import/prescan cons lists (idiom 8)** | Reachable now, but low-value Node plumbing; not worth the churn this stage. |
| **`HashMap` side indexes for name lookups** | Only if profiling shows the linear scans hurt; must stay beside the ordered Vector (decision 2). |

---

## Phased build plan

Dispatch per the repo's subagent workflow ([context/local.md](../../context/local.md)):
mechanical per-file batches to **focused-task-implementer**; the genuinely-new
pieces (the `Cleanup` `defunion` pilot, `Scope.syms` pointer-stability) to
**systems-impl-engineer**; **build-test-runner** gates between every batch;
**api-docs-writer** for the close-out. Every compiler-touching prompt must direct
the agent to read [context/conventions.md](../../context/conventions.md) first.

Phase order follows the consensus impact×feasibility ranking. 14.1–14.3 are the
bulk of the cast deletion; 14.4–14.6 are structural; 14.7 is record-only.

### T14.0 — Ground-truth & discipline (no compiler change)

**Done in this doc.** Records the verified facts (§Ground-truth corrections):
prelude/compiler-types types resolve in toplevel signatures (no prescan enabling
fix needed); the real friction is Phase-F `ptr:T`=`PTR-REF`; `(raw T)`-first is
byte-identical. Establishes the two verification methods every phase uses:

1. **Inert batch** → snapshot `build/nucleusc.ll`, apply, rebuild, `diff` must be
   empty (catches lost strcmp / wrong pkind that `make bootstrap` misses).
2. **Structural batch** → `make test` green, then `make update-bootstrap` +
   `make clean && make` + `make bootstrap` re-converges (stage1==stage2).

No agent work beyond confirming the build is green at HEAD.

### 14.1 — Element-type the registry `Vector`s  *(controlled refresh)* — **DONE (2026-07-06)**

**Status:** complete. All 26 registries carry typed elements; no `(cast ptr:X
(invoke g-X …))` consume cast remains tree-wide; `make test` 166/166; `make
bootstrap` reconverges. `g-fnty-names`/`g-fnty-types` were retired altogether
(replaced by the `g-fnty (HashMap CStr ref:Type)` in type-mangle.nuc during the
Stage 11/13 work). The final four — `g-conformances`/`g-proto-supers` →
`(Vector (ref Conformance))`, `g-blanket`/`g-macro-decls` → `(Vector CStr)` —
landed in one batch. Two doc corrections from the close-out audit: (a) the §2
table's `g-macro-decls` row was stale (it is a per-JIT-module macro-decl *name*
dedup set produced by `intern-str` and consumed by `strcmp`, not a `MacroDef`
registry — the `MacroDef` registry is the separate, already-typed `g-macros`);
(b) the bootstrap prediction below was over-cautious — see the corrected note.

**Agent: focused-task-implementer** (per-registry batches); build-test-runner
between. **Read (scoped):** the `make-vec`/`(ref (Vector ptr))` pattern
(nucleusc.nuc:429-497); each registry's `defvar`, its `conj` producer(s), its
`invoke`/`count` consumer(s), and its `-lookup` scan.

**Build:** for each of the 26 registries, change `(ref (Vector ptr))` →
`(ref (Vector (ref RecordType)))` (or `(Vector CStr)` for `g-fnty-names`),
rewrite `(conj g-X (cast ptr rec))` → `(conj g-X rec)` (rec already
`(ref RecordType)`), and delete the `(cast ptr:X …)` wrapping every
`(invoke g-X i)`. One registry per batch; **preserve insertion order**; mind the
registries read during prescan / JIT-macro expansion (start with the coldest).

**Bootstrap:** controlled refresh — the Vector instance mangles from `%Vector.ptr`
to `%Vector.<Record>`, and each `conj`/`invoke`/`count`/iterator method stamps for
the new instance, so IR drifts. Refresh at the end of the phase (not per batch),
then re-converge. *(Correction, verified 2026-07-06: the `make bootstrap`
fixed-point compares two compilations by the **`bin/nucleusc` binary**, not the
checked-in `boot/nucleusc.ll`; since `bin/nucleusc` is rebuilt from source each
run, it already stamps the new typed Vector instances in **both** stages, so the
fixed point holds **even before** `make update-bootstrap`. The committed
`boot/*.ll` is only a fallback to rebuild the binary via `ensure-boot` when it
can't run — so it can be stale without breaking convergence. `make update-bootstrap`
is still correct to run at the milestone, to keep the fallback IR synced.)*
**Watch:** the `(Maybe ptr)`-niche-vs-matchable tension
(conventions.md says matchable; R3 progress says combinators crash over a
`(VecIter ptr)`). Element-typing does **not** require combinator iteration —
lookups stay `dotimes` — so this is orthogonal; but if a `(ref X)` element changes
`(next it)`'s `(Maybe (ref X))` matchability, keep the loop a `dotimes` (idiom
holds). *(Open question OQ4 — resolved: no converted site relied on matching
`(next it)` over the retyped Vector; lookups stayed `dotimes` and the standard
pointer-weakening coercion `(ref T)`→`ptr:T` handled every consumer annotation
without any re-annotation.)*

**Done when:** all 26 registries carry a typed element; no `(cast ptr:X (invoke
g-X …))` remains; `make bootstrap` re-converges; tests green. ✓

### 14.2 — Type the `compiler-types.nuc` cross-reference fields  *(mostly inert)*

**Status (batch 1, 2026-07-12): `Type` + `Sym` done, byte-identical.** `Type.ret`/
`elem`→`(raw Type)`, `Type.sdef`→`(raw StructDef)`; `Sym.type`/`ntype`→`(raw Type)`,
`Sym.home`/`taint`→`(raw Scope)`; `Sym.const-val`/`cslot`/`src-file`/`docstring`→
`CStr`. **Two census corrections (see below):** `Sym.ir-name` and `Sym.trace-saved`
stay **`ptr`**, NOT `CStr` — `ir-name` is compared by *pointer identity*
(`import-alias-one`'s alias-collision check; ir-names are freshly formatted, not
interned) and null-checked (`inject-import-aliases`), so a `CStr` retype lowers both
to `strcmp` (the null case emitting the crashing `strcmp(x, null)`). `trace-saved`
holds a saved copy of `ir-name` (assigned back on untrace), so it must mirror
`ir-name`'s type. Verification: bare `ptr` is PTR-REF post-Phase-F, but
`pkind-flow-check` exempts elem-less destinations, so retyping a field to `(raw T)`
only breaks at an *uncast* read feeding a *typed* `(ref T)` slot — none existed for
these fields (build was clean without any cursor retypes). Redundant-cast deletions
were confined to **raw/plain contexts** (field-access-then-use and `sd:ptr`-param
args); the far more common `(cast ptr:Type (x elem/type/sdef))`→`et:ptr:Type`/
`ft:ptr:Type`/`sd:ptr:StructDef` *let-binding* idiom keeps its cast (it now asserts
non-null raw→ref — retyping those locals is 14.3, not here). ~14 casts deleted
(type-utils/union-registry/nucleusc/repl/abi) + the `defer-scope` cast (now at
nucleusc.nuc:5371, drifted from :4988). The remaining `compiler-types.nuc` structs
(StructDef, UnionDef, Scope, Val, Method, …) are future batches.

**Status (batch 2, 2026-07-12): the remaining 16 structs done, byte-identical.**
`StructDef.src-file`→`CStr`, `udef`→`(raw UnionDef)`, `origin-template`→
`(raw StructTemplate)`; `UnionDef.sdef`/`union-sd`→`(raw StructDef)`,
`niche-elem`→`(raw Type)`; `UnionTemplate.form`/`StructTemplate.form`→
`(raw Node)`; `Scope.parent`→`(raw Scope)`; `Val.type`→`(raw Type)`,
`taint`→`(raw Scope)`; `ProgDefn.ir-name`→`CStr`, `ret`→`(raw Type)`;
`BinOp.name`/`instr`/`instr-u`→`CStr`; `Method.ret-type`/`fn-type`→`(raw Type)`,
`binop`→`(raw BinOp)`, `body`→`(raw Node)`, `origin-template`→`(raw Method)`;
`TmplConformance.template`→`(raw StructTemplate)`, `proto`→`(raw Protocol)`;
`MonoJob.form`→`(raw Node)`, `context`→`CStr`; `MacroDef.jit-name`/`src-file`/
`docstring`→`CStr`; `RMacro.prefix`/`wrap-sym`→`CStr`; `LabelEntry.name`→`CStr`;
`CastRule.from`/`to`→`(raw Type)`, `ir-name`→`CStr`; `NarrowUndo.name`→`CStr`,
`old-ntype`→`(raw Type)`.

**Three census findings beyond the batch-1 identity check, all verified against
call sites (not guessed):**
- **`Method.ir-name` stays `ptr`** — same class as `Sym.ir-name`. `defn-ir-name`/
  `defn-form-mangled-name` (generics.nuc:566/595) and the mangled-name cache probe
  in `generic-method-bind-adapt` (generics.nuc:2544) null-check it
  (`(!= (-> m … ir-name) null)`) before any comparison, and it is a genuine null
  for `METHOD-INTRINSIC`/not-yet-mangled methods (generics.nuc:98/338/1175). A
  `CStr` retype turns that guard into a crashing `strcmp(x, null)`.
- **`Val.val` stays `ptr`** — not an identity case, but a *dispatch* one: several
  match/cond-join phi accumulators (`union-emit.nuc`/`nucleusc.nuc`, `(conj vals
  (bv val))`) collect it into a `(Vector ptr)`. `conj`'s generic dispatch binds
  that Vector's element tyvar to `ptr`, and a `CStr` argument does not adapt to a
  bare `ptr` parameter (arg-adapts treats them as distinct on purpose, per the
  string-lattice note in conventions.md) — a `CStr` retype broke that call
  (`no matching method for overloaded 'conj'`) rather than staying inert. Found
  by attempting the retype and rebuilding, not by inspection alone — a reminder
  that the identity-comparison checklist doesn't cover every way a field can be
  non-inert.
- **`RMacro.wrap-sym` is a plain string despite the name** — never a Node/Sym
  pointer. It flows only into `intern-symbol` (lib/reader.nuc:452, via
  `Tok.s`/`TOK-RMACRO`), which canonicalizes by content; `register-rmacro`'s own
  second overload already declares it `wrap-sym:CStr`. `RMacro.prefix` is only
  ever byte-indexed (`char-at`) during the reader's longest-prefix-match scan —
  also plain content, safe as `CStr`.
- Everything else CStr-retyped (`ProgDefn.ir-name`, `BinOp.name`/`instr`/
  `instr-u`, `MonoJob.context`, `MacroDef.jit-name`, `LabelEntry.name`,
  `CastRule.ir-name`, `NarrowUndo.name`) was confirmed content-only by tracing
  every read site: explicit `strcmp` (`program-defn-lookup`, `lbl-find`),
  content comparison against string literals already relying on the mixed-
  operand strcmp rule (`builtin-op-result-type`'s `(= (bop name) "=")`), or
  formatted straight into an IR/diagnostic stream and never compared.
  `NarrowUndo.name` in particular only ever flows into `scope-lookup`, which
  already does a content compare against `Sym.name` (itself `CStr` since Stage
  12) — so it was never the identity case the field name suggested.

A handful of inline `(cast ptr:X (obj field))` reads with no named local (e.g.
`((cast ptr:BinOp (m0 binop)) is-cmp)`, `((cast ptr:Type (vv type)) kind)`, the
`origin-template` identity check in `unify-tpat`) were simplified to direct field
access — the far more common named-local idiom (`sd:ptr:StructDef (cast
ptr:StructDef (udd sdef))`) keeps its cast per the batch-1 precedent (14.3
territory). `make test` 168/168; `make bootstrap` fixed point; `build/nucleusc.ll`
diffed **byte-identical, zero lines**, against a from-scratch baseline build of
the pre-batch source with the same (old) boot compiler — stronger than the
per-batch snapshot check since it also confirms no drift snuck in between
sub-edits.

All 16 `compiler-types.nuc` structs listed in this section are now done. What's
left for a hypothetical batch 3 is the parallel/array fields explicitly deferred
to 14.4 (`field-names`/`field-types`, the `UnionDef` arm arrays, `origin-args`,
the `Method`/`TmplConformance` `&where` constraint quads) and `Scope.syms`/
`cleanup-slots` (14.5).

**Agent: focused-task-implementer** (per-struct batches); systems-impl-engineer
for `Type`/`Sym` (highest fan-out). **Read (scoped):** the target struct in
compiler-types.nuc; the `emit-*`/`node-type-*`/lookup functions that read its
fields.

**Build:** retype each `ptr` cross-reference field to `(raw T)`/`CStr` per idiom 1
(skip the already-`CStr` names; skip the LLVM opaque handles). Delete the
now-redundant `(cast ptr:T (obj f))` at read sites — but **only** where the
consuming context is raw/plain; a cast that *asserts* non-null `(cast (ref T) …)`
into a `(ref T)` slot stays. Promote a field to `(ref T)` only where non-null is a
real invariant and its writes are known-non-null (decision 1). Reclassify
`Val.val`, `Sym.ir-name`/`const-val`/`cslot`/`docstring`/`src-file` as `CStr`
(they're arena-owned C strings; watch the strcmp caveat — none of these are
compared by identity). Delete the redundant `(cast ref:Scope (cl defer-scope))`
(correction 3) and fix the `import-list-push` stale comment (correction 1).

**Bootstrap:** byte-identical for the `(raw T)`/`CStr` retypes + cast deletion
(verify by empty `build/nucleusc.ll` diff per batch). If a field is promoted to
`(ref T)`, that batch drifts (flow checks engage) → controlled refresh.

**Done when:** the untyped cross-reference fields carry real types; the read-site
casts are gone; `make bootstrap` fixed point (or re-converged for `ref` batches);
tests green. This is the single biggest cast-deletion phase.

### 14.3 — Type elem-less `:ptr` params/returns  *(mostly inert)*

**Agent: focused-task-implementer**, dispatched by file cluster
(scope/type-utils/type-mangle → abi/union-registry/union-emit → generics →
nucleusc → cheader/nuch/repl). **Read (scoped):** each cluster's `defn`
signatures + the casts in their bodies.

**Build:** retype `:ptr` params/returns to `(raw T)`/`(ref T)`/`CStr` where the
type is statically known, `(raw T)`-first (decision 1). The traversal-cursor rule
(correction 2): a local that reads a `(raw Node)` link field must be `(raw Node)`,
not `ptr:Node`. `nucleusc.nuc` signatures are fully in scope — no prescan
constraint. Delete body casts made redundant by the typed param.

**Bootstrap:** byte-identical for `(raw T)`/`CStr`; `(ref T)` param/return
promotions drift (flow checks) → controlled refresh. Verify inert batches with the
IR diff.

**Done when:** the elem-less `:ptr` signature population is materially reduced;
byte-identical (or re-converged) per batch; tests green.

**Status (batch 1, 2026-07-12): `scope.nuc`/`type-utils.nuc`/`type-mangle.nuc`
done, byte-identical.** `scope-new`/`scope-define`/`scope-lookup`/
`scope-push-cleanup`'s `Scope*` param → `(raw Scope)`; `scope-define`'s `type`
→ `(raw Type)`; every `Type*` param/return across `type-utils.nuc` (`type-to-ir`,
`type-is-strview`, `type-to-c`, `type-size`, `is-int-type`, `is-float-type`,
`is-ptr-like`, `int-width`, `is-unsigned`, `int-literal-fits`, `ptr-pkind`,
`type-as-pkind`, `pkind-flow-check`'s `src`/`dst`, `require-derefable`'s `t`)
and `type-mangle.nuc` (`type-mangle-token`, `type-spelling`, both param and
return) → `(raw Type)`/`CStr`; `collapse-strlit-cstr`'s `v` → `(raw Val)`;
`subst-tyvars-sym`'s `s` (a plain colon-spelling string) → `CStr`;
`subst-tyvars-node`'s `node` → `(raw Node)` (nullable, matches its `(when (=
node null) (return null))`); `pkind-flow-check`'s `ctx` and
`require-derefable`'s `op` (diagnostic-label strings, always literals) →
`CStr`. Every `tt:ptr:Type (cast ptr:Type t)`-style redundant local cast
collapsed to a plain rebind (`tt:raw:Type t`); ~15 casts deleted in these three
files plus 5 more at call sites tree-wide once the callee no longer demanded
elem-less `ptr` (`require-derefable` call sites in `nucleusc.nuc`×4 and
`union-emit.nuc`×1 dropped their `(cast ptr pt/ct/st …)` wrapper).

**One genuine non-inert finding (caught only by the empirical IR-diff/test
gate, not by inspection):** `program-defn-record`'s `irn` parameter looked like
a safe `CStr` retype by the same reasoning as `ProgDefn.ir-name` (already
`CStr` since 14.2), but the function immediately does `(when (= irn null)
(return))` — a **null-check on the parameter itself**, not the field. Retyping
`irn` to `CStr` turned that guard into `strcmp(irn, null)`, which segfaults on
every single compile (even `hello.nuc`) since `strcmp` dereferences its second
argument. `program-defn-lookup`'s `irn` has no such guard (only an explicit
`strcmp` against the always-non-null `pd ir-name`) and would have been safe as
`CStr`, but is left `ptr` anyway for consistency with its sibling and to avoid
inviting the same trap if a null-guard is ever added there. Both stay `ptr`,
matching the `Sym.ir-name`/`Method.ir-name` precedent (14.2's census) exactly —
this is the same failure class, just one hop further from the field. Found by
bisecting a `make test` regression (a universal segfault survived the OLD
boot's typecheck of the new source, since the bug is a runtime behavior change,
not a type error) down to this single line; fixed by reverting both
`program-defn-lookup`/`program-defn-record`'s `irn` to `ptr` with an explanatory
comment at each site.

Verification: `make test` 168/168; `make bootstrap` fixed point
(`stage1.ll == stage2.ll`); `build/nucleusc.ll` diffed **byte-identical, zero
lines** against a from-scratch baseline built with the pre-batch source and the
same (unmodified) `bin/nucleusc` boot — the strongest check, and the one that
would have caught the `program-defn-record` regression even without `make
test`. `examples/and-narrow.nuc` re-run per the close-out checklist (no
narrowing-affecting promotions in this batch, but confirmed clean regardless).
Next batch (per the file-cluster order): abi/union-registry/union-emit's own
signatures.

### 14.4 — Parallel arrays → array-of-struct  *(controlled refresh)*

**Agent: systems-impl-engineer** (new element structs + layout change); build-test
gates. **Read (scoped):** the arm-array build/scan (union-registry.nuc:789-800,
:611-618); the `&where` quad users (generics.nuc:1250/1389/1433/1678); `Conformance.args`
+ `conformance-args-eq` (generics.nuc:2089).

**Build:** introduce element structs — `Arm{name, ptype, fnames, ftypes,
nfields}`, `Constraint{proto, var, args}`, `Field{name, type}` — each held in a
typed `(Vector (ref …))`, replacing the parallel arrays on `UnionDef`, `Method`,
`TmplConformance`, `StructDef`, `Type`. Convert `Conformance.args` to
`(Vector CStr)` with a value-equality helper (folding `conformance-args-eq`). This
also deletes the conservative upper-bound arena sizing (`count-pattern-nodes`,
generics.nuc:793-800, :969-976), since Vectors grow on demand.

**Bootstrap:** layout changes (fields replaced by a Vector handle) → controlled
refresh per struct; re-converge.

**Done when:** the ragged `aref (cast ptr:ptr …)` lockstep-array walks are gone;
tests green; boot re-converged.

### 14.5 — Remaining hand-rolled growables → `Vector`  *(controlled refresh)*

**Agent: focused-task-implementer** for the cold ones; **systems-impl-engineer**
for `Scope.syms`. **Read (scoped):** each growable's grow thunk + read sites
(idiom 4 anchors).

**Build, cold-first:**
1. `g-include-paths`, `g-link-args` (fixed 64-slot `malloc` → `(Vector CStr)`).
2. `g-vtable-keys`/`-names`, `g-ns-prefix-keys`/`-vals` (→ parallel `(Vector CStr)`
   or a `{key,val}` element struct).
3. The type-erasure memos `g-boxedfn-*`, `g-dyn-*` — **mind union-registry import
   ordering** (these live in union-registry.nuc, imported early; a
   `(Vector (ref BoxKey))` element there must respect the `AllocHandle` pending-IR
   drain, union-registry.nuc:159-172).
4. `Generic.methods` (→ `(ref (Vector (ref Method)))`, deleting the grow thunk).
5. **`Scope.cleanup-slots`** (→ `(ref (Vector (ref Cleanup)))`).
6. **`Scope.syms`** — *the pointer-stability caveat (systems-impl-engineer).*
   `scope-define` returns a `ref:Sym` *into* the inline array (scope.nuc:36,43);
   an inline-value `(Vector Sym)` relocates on growth and dangles that ref.
   Recommended: `(Vector (ref Sym))` — heap/arena-allocate each `Sym`, store the
   pointer; growth moves the pointer array, not the `Sym` objects, so the returned
   ref stays stable. Preserves the `scope-define` contract; costs one indirection
   on the hot `scope-lookup` scan. **This is the riskiest migration — see OQ2;
   defer if profiling flags the indirection.**

**Bootstrap:** controlled refresh (layout + storage change); re-converge.

**Done when:** the hand-rolled growables are gone (or `Scope.syms` explicitly
deferred per OQ2); tests green; boot re-converged.

### 14.6 — Closed sums → `defunion`/`case`  *(pilot then sweep)*

**Agent: systems-impl-engineer** for the `Cleanup` pilot; **focused-task-implementer**
for the mechanical `case` sweeps. **Read (scoped):** `Cleanup` (compiler-types.nuc:251)
+ its dispatch (nucleusc.nuc:4984-4993); then per sum, its dispatch sites.

**Build:**
1. **Pilot — `Cleanup` → `defunion`.** Model the three shapes as arms
   (`(libc-free slot)` / `(drop slot fn ty ret)` / `(defer node scope)`) and
   rewrite the null-probe `cond` (nucleusc.nuc:4984-4993) as an exhaustive
   `match`. Validates the pattern before the sweep. *(JIT gotcha: `(Maybe
   <struct>)` fails in the macro-expansion JIT module — Cleanup dispatch is on the
   emit path, not the JIT path, so this is safe; keep it that way.)*
2. **`MethodKind`, `UnionDef.layout`, `AbiInfo.kind`** — fold the integer-tag
   compares to `case` over the existing `defenum` (or `defunion` for
   `AbiInfo.kind` carrying `reg0`/`reg1`/`size`/`align` payloads). `AbiInfo.kind`
   is optional (abi.nuc is a leave-alone IR zone — do it only if it stays
   byte-identical). `UnionDef.layout`'s `niche-elem` payload rides along.
3. **`Type.kind` / `NodeKind` ladders** — mechanical kind-ladder→`case` sweep over
   the ~171 dispatch sites **without relayout** (`Type`/`Node` stay structs). This
   is exhaustiveness sugar over the enum, not a representation change.

**Bootstrap:** the `Cleanup` `defunion` changes its layout (struct →
`{tag,payload}`) → controlled refresh. The `case`-over-enum sweeps should be
byte-identical if `case`/`cond` lower identically — verify with the IR diff; if
`case` drifts, refresh once for the sweep.

**Done when:** the closed sums are exhaustiveness-checked; tests green; boot
re-converged (or byte-identical for the `case` sweeps).

### 14.7 — Deferred tail (record only)

No build. Confirm the deferred items (§Deferred) are logged with reasons; leave
`Type`/`Node`-as-`defunion`, `Node.car/cdr` promotion, out-param boxes, import
lists, and HashMap side indexes for a future stage.

### Close-out (required by AGENTS.md)

- **api-docs-writer:** the language surface does not change (this is
  compiler-internal cleanup), so `docs/` needs at most a note in any
  compiler-internals doc; the substantive close-out is **[progress.md]** (a Stage
  14 detail table) and this doc's implementation-status section.
- Update the `import-list-push` comment (correction 1) and delete the redundant
  `defer-scope` cast (correction 3) — bundled into 14.2/14.3, noted here so they
  aren't lost.
- Re-run `examples/and-narrow.nuc` after any batch that touches narrowing
  (`(ref T)` promotions engage the flow analyzer).
- Verification per batch: **inert** → empty `build/nucleusc.ll` diff; **structural**
  → `make test` green + `make update-bootstrap` + `make bootstrap` fixed point.
  `make update-bootstrap` only at phase milestones.

---

## Sequencing & dependencies

```
T14.0 (ground-truth, done) ─┬─► 14.1 registry element typing ──┐
                            ├─► 14.2 field typing ─────────────┼─► 14.4 array-of-struct ─┐
                            └─► 14.3 param/return typing ───────┘                        ├─► 14.6 closed sums
                                                        14.5 growables → Vector ─────────┘
                                                                                          14.7 (record only)
```

14.1/14.2/14.3 are independent bulk cast-deletion and may batch in parallel across
files (they touch different sites; coordinate on `compiler-types.nuc` edits). 14.4
depends on 14.1 (element structs live in typed Vectors) and 14.2 (the parallel
fields are typed first). 14.5 is independent. 14.6 benefits from 14.2 (`Cleanup`
fields typed before the `defunion` conversion). Build-test-runner gates every
batch.

## Bootstrap policy (summary)

| Phase | Expected bootstrap | Refresh |
|---|---|---|
| 14.1 registry element typing | drifts (Vector instance mangles) | controlled, reconverge (end of phase). **Verified 2026-07-06:** the fixed point held *before* `update-bootstrap` (the convergence test compares the `bin/nucleusc` binary, rebuilt from source each run, not the checked-in `boot/*.ll`); refresh still correct to keep the fallback IR synced. |
| 14.2 field typing — `(raw T)`/`CStr` | byte-identical | no (verify empty IR diff) |
| 14.2 field typing — `(ref T)` promotions | drifts (flow checks engage) | controlled, reconverge |
| 14.3 param/return typing — `(raw T)`/`CStr` | byte-identical | no (verify empty IR diff) |
| 14.3 param/return — `(ref T)` promotions | drifts | controlled, reconverge |
| 14.4 array-of-struct | drifts (layout) | controlled, reconverge |
| 14.5 growables → Vector | drifts (storage/layout) | controlled, reconverge |
| 14.6 Cleanup defunion | drifts (struct→tagged) | controlled, reconverge |
| 14.6 case-over-enum sweeps | byte-identical (verify) | no if IR diff empty |

Unjustified drift at an inert phase is a bug to debug, not a refresh.

## Risk register

| Risk | Mitigation |
|---|---|
| `(raw T)` retype silently flips a `=` to strcmp (a `ptr`→`CStr` on an identity-compared field) | conventions.md CStr rule; empty-IR-diff gate catches the lost/gained strcmp hunk |
| A `(ref T)` promotion cascades non-null obligations further than expected | `(raw T)`-first (decision 1); promote in a separate, small batch; re-run and-narrow |
| Registry element typing breaks a `(next it)` match / combinator | element typing keeps lookups as `dotimes` (idiom 2); OQ4; don't introduce combinators here |
| `Scope.syms` Vector migration dangles the `ref:Sym` return | `(Vector (ref Sym))` (boxed), not inline; OQ2; defer if the indirection costs on scope-lookup |
| union-registry import ordering breaks a new parametric instance | mind `pending-union-deps-ready` drain (union-registry.nuc:159-172) for the boxedfn/dyn memo migration |
| `Cleanup` defunion hits a JIT `(Maybe <struct>)` gotcha | Cleanup dispatch is emit-path only; keep it off the JIT path |
| Multi-session scope (thousands of casts) | phase/cluster batching; build-test gate each batch; IR-diff proves inertness |

---

## Open questions / resolved-decisions

| # | Question | Resolution |
|---|---|---|
| RD1 | Registry storage after typing | **Ordered `Vector` stays** (deterministic emit order); `HashMap` only as an additive side index (decision 2). |
| RD2 | Field/param retype target | **`(raw T)`/`CStr` first** (byte-identical, zero obligations); `(ref T)` selectively where non-null is real and writes are known-non-null (decision 1, verified). |
| RD3 | Registry element type | **`(ref RecordType)`** — entries are always non-null (arena-alloc'd + conj'd); string-keyed registries → `(Vector CStr)` (decision 3). |
| RD4 | Prelude-type-in-signature enabling fix | **None needed.** `prescan-imported-types` already registers imported type names for the outermost unit; verified a toplevel `Node`-typed signature compiles. The stale `:ptr` comment is corrected, not worked around (correction 1). |
| RD5 | Handler-table element type | Concrete struct-pointer, **no `(dyn P)`/`BoxedFn`** (zero-cost invariant, decision 4). |
| RD6 | `Type`/`Node` as `defunion` | **Deferred** — hottest, shared-mutated, bootstrap re-layering. Kind-ladder→`case` only (decision 5). |
| OQ1 | `(ref T)` vs `(raw T)` for registry elements | Recommend `(ref T)` (non-null entries); resolve empirically in 14.1 batch 1 — fall back to `(raw T)` if `conj`-site obligations prove noisy. |
| OQ2 | Migrate `Scope.syms` at all? | Recommend `(Vector (ref Sym))` if done (pointer-stability); **defer** unless profiling shows the hand-rolled growable is a burden — it's the riskiest migration and adds an indirection to the hot `scope-lookup` scan. |
| OQ3 | `HashMap` side index for `conformance-lookup`/`generic-lookup` string scans | Only if profiling justifies; must sit beside the ordered Vector, never replace it. |
| OQ4 | Does a `(ref X)` registry element change `(next it)` `(Maybe (ref X))` matchability vs the `(Maybe ptr)` niche? | Element typing keeps lookups as `dotimes`, so orthogonal; verify in 14.1 that no converted site relies on matching `(next it)` over the retyped Vector. |
| OQ5 | `AbiInfo.kind` → `defunion`? | Optional; abi.nuc is a leave-alone IR-lowering zone — do it only if it stays byte-identical (14.6 step 2). |
