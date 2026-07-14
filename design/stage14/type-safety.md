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

### 6. Elem-less `:ptr` params/returns for statically-known types — **DONE (2026-07-13, see §14.3)**

~194 `:ptr` params across generics/union files, 62 `defn …:ptr` + ~671 bare-`ptr`
params in nucleusc.nuc, and nearly every top-level fn in cheader/nuch/repl.
`scope-define` takes `s:ptr` then casts to `ptr:Scope` (scope.nuc:19). Retyping a
`ptr`→`(raw T)`/`(ref T)` param or return is ABI/IR-identical (both lower to
`ptr`). **Fully reachable in `nucleusc.nuc` — see ground-truth correction 1.**
The elem-less `:ptr` signature population across the whole translation unit
(scope/type-utils/type-mangle → abi/union-registry/union-emit → generics →
nucleusc → repl/nuch/cheader) is now retyped per §14.3; the remainder is
genuinely `ptr`-to-`ptr` arrays (§14.4), identity/memo keys, or LLVM/FFI
plumbing — not further instances of this idiom.

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

### 14.3 — Type elem-less `:ptr` params/returns  *(mostly inert)* — **DONE (2026-07-13)**

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

**Status (batch 2, 2026-07-13): `abi.nuc`/`union-registry.nuc`/`union-emit.nuc`
done, byte-identical.** Every elem-less `:ptr` `defn` param/return whose
pointee was statically evident from the body was retyped, `(raw T)`-first per
decision 1:

- **`abi.nuc`**: `abi-alignof`/`abi-sizeof`/`abi-classify`'s `t` → `(raw
  Type)`; `abi-union-size`/`abi-struct-align`/`abi-struct-size`/
  `abi-class-eightbyte`'s `sd` → `(raw StructDef)`; `abi-eightbyte-ir`/
  `abi-ret-ir`/`abi-arg-frag`'s return, plus `abi-ret-ir`/`abi-emit-struct-call`'s
  `info` → `(raw AbiInfo)` and `ret` → `(raw Type)`, `ir-name`/`arglist` →
  `CStr`; `abi-emit-param-prologue`'s `ptype` → `(raw Type)`, `pname` → `CStr`;
  `emit-struct-ret`/`abi-arg-frag`/`coerce-int-val`'s `v`/`av` → `(raw Val)`,
  `coerce-int-val`'s `target` → `(raw Type)`; `check-ir-name-legal`'s
  `orig-name`/`ir-name` → `CStr`; `register-struct`'s `name` → `CStr` (matches
  the already-`CStr` `StructDef.name`/`.ir-name` fields from SM-4).
  `abi-classify`'s return also went `(raw AbiInfo)` (never actually null, but
  no confirmed non-null invariant worth a `(ref T)` promotion — decision-1
  default). `abi-class-eightbyte` (the byte-exact SysV classification loop) got
  **signature-only** changes — no reordering, per the file's leave-alone-the-
  logic constraint.
- **`union-registry.nuc`**: `hash-type`/`uniondef-for-type`/`result-union-of`/
  `result-ok-type`/`type-for-sdef`'s `t`/`sd` → `(raw Type)`/`(raw StructDef)`;
  `union-arm-index`/`union-payload-off`/`union-instance-type`'s `ud` → `(raw
  UnionDef)`; `union-template-stamp(-types)`'s `ut` → `(raw UnionTemplate)`;
  `struct-template-stamp(-types)`'s `st` → `(raw StructTemplate)`; `fnv-str`'s
  `s`, `lookup-struct`/`parse-type-name`/`uniondef-lookup`/`defunion-register`/
  `union-arm-index-in`'s `name` → `CStr`.
- **`union-emit.nuc`**: `v`/`sv`/`av`-shaped Val* params across the
  `emit-unwrap*`/`emit-match-niche-*`/`emit-match-enum` family → `(raw Val)`;
  `ud`-shaped UnionDef* params (`emit-union-construct`, `result-err-arm-is-err`,
  `emit-match-binders`, `emit-match-clauses`) → `(raw UnionDef)`; `elem`/`ty`/
  `target`/`repair-ty`-shaped Type* params (`emit-unwrap-niche-errptr`,
  `emit-unwrap-or-niche-errptr`, `niche-layout-of`, `emit-niche-construct`,
  `union-target-rewrite`, `emit-handler-call`, `stamp-maybe-type`) → `(raw
  Type)`; `emit-match-binders`/`emit-match-clauses`'s `staint` (a
  `Sym.taint`-shaped alias) → `(raw Scope)`; `enum-member-index`'s `ed` →
  `(raw EnumDef)`; `enumdef-lookup-member`/`enum-member-index`'s `member`,
  `emit-niche-construct`'s `arm` → `CStr`. ~30 redundant casts deleted — both
  the in-body `xxdd:ptr:X (cast ptr:X xx)` → `xxdd:(raw X) xx` rebind pattern
  and direct call-site casts (`(cast ptr v)`/`(cast ptr ud)`/`(cast ptr sv)`)
  that existed only to satisfy a callee's old elem-less `ptr` demand.

**Two traps found this batch, one matching the batch-1 class and one new.**

1. **`abi-print-param`'s `name`** looked like a safe `CStr` retype (every other
   `*name*`-suffixed param in this batch was) but the function opens by
   branching on `(= name null)` to distinguish a `define` (real parameter name)
   from a `declare` (types only — `name` is passed `null`). Retyping to `CStr`
   would turn that into `strcmp(name, null)`, crashing on every `declare` —
   exactly the `program-defn-record` shape from batch 1, just a different
   function. Left `name:ptr` with an explanatory comment at the definition.
2. **New this batch — identity-keyed memo lookups are not `CStr` candidates,
   even though they hold string content.** `boxedfn-memo-lookup`/
   `dyn-memo-lookup`'s `key` and `dyn-type`'s `proto` are compared with plain
   `=` against entries in a hand-rolled memo array, relying on **pointer
   identity** (the keys are interned) for the dedup to be correct — the same
   shape as `Node.s`/struct-field names on the NS-5 exclusion list
   (conventions.md), just one level removed from a struct field. A `CStr`
   retype would not crash (interned strings are content-equal wherever they
   are identity-equal, so the *result* is unchanged today) but would silently
   swap the comparison from identity to `strcmp`, which is the kind of
   invisible semantic drift the batch-1 lesson warns against generalizing away
   from. Since this whole `g-boxedfn-*`/`g-dyn-*`/`fatptr-*` type-erasure-memo
   family is already flagged in §14.5 ("mind union-registry import ordering")
   for the hand-rolled-growables pass, it was left entirely untouched here
   rather than partially migrated — `boxedfn-type`/`dyn-type`/
   `boxedfn-canonical`/`dyn-canonical`/`dyn-proto-of`/`ensure-fatptr-sdef`/
   `fatptr-type` all keep their original elem-less `ptr` signatures. (A related
   reason to leave `boxedfn-type`'s own return as `ptr`: it flows, unmarked,
   into callers that return it as `ref:Type` — e.g. `parse-type-from-node`'s
   `(return (boxedfn-type …))` — and retyping the return to `(raw Type)` would
   newly engage `pkind-flow-check` on that `raw`→`ref` transition, since
   elem-less `ptr` is flow-exempt but elem-typed `raw` is not. This is a
   compile-time break, not a runtime trap, but it is the general shape to
   watch for when a `ptr`-returning helper is consumed by multiple call sites
   with different downstream expectations.)

**Scope decision, not a trap: `Node*` params were left untouched this batch.**
Every `call`/`form`/`use-node`/`binders`/`clause-binders`/`arms`/`arms-raw`
param across all three files stayed elem-less `ptr`. These files are mostly
`emit-*` functions dispatching on AST shape, and the file-cluster order
schedules nucleusc.nuc/generics.nuc — where the bulk of `Node*`-typed code and
the `node-type`↔`emit-node` lockstep discipline (conventions.md) already
live — as later batches; retyping `Node*` piecemeal in just these three files
would be inconsistent with the (not-yet-migrated) rest of the codebase for no
compounding benefit. Recommend picking up `Node*` signature typing together
with the nucleusc.nuc/generics.nuc batch rather than as a separate pass.

Verification: `make` clean; `make test` 168/168; `make bootstrap` fixed point
(`stage1.ll == stage2.ll`); `build/nucleusc.ll` diffed **byte-identical, zero
lines** against the pre-batch baseline (same unmodified `bin/nucleusc` boot) —
confirmed after *each* file (abi.nuc, then +union-registry.nuc, then
+union-emit.nuc), not just at the end, so any regression would have been
isolated to a single file's edits. `examples/and-narrow.nuc` re-run clean; no
`(ref T)` promotions this batch, so the narrowing re-run is a formality (no
new flow-check obligations were introduced anywhere — every retype was `(raw
T)`, `CStr`, or left `ptr`, never `(ref T)`).

Next batch (per the file-cluster order): generics.nuc's own signatures — and,
per the scope decision above, a good point to also start on the `Node*`
population there, since generics.nuc already leans on the `node-type` half of
the emit/node-type lockstep.

**Status (batch 3, 2026-07-13): `generics.nuc` done in full — all 128 `defn`s
surveyed, byte-identical.** This is the largest single-file pass of the phase
(the file is bigger than batches 1+2 combined); every elem-less `:ptr`
param/return whose pointee was statically evident was retyped, `(raw T)`-first
per decision 1, including — per the batch-2 recommendation — the bulk of this
file's `Node*` population (the design doc's other explicit ask for this
batch):

- **`Generic*`/`Method*`/`Type*`/`Protocol*`/`StructTemplate*`/
  `TmplConformance*`/`StructDef*`/`BinOp*` single-object params/locals** across
  the whole registry/resolution/protocol machinery (`generic-lookup`,
  `generic-new`, `generic-remove-matching-user-method`, `type-eq`,
  `type-join`, `generic-find-method-exact`, `generic-binds-for`,
  `generic-resolve(-adapt-tier)`, `operator-user-resolve`,
  `generic-method-bind(-adapt)`, `generic-constraints-ok`,
  `generic-instantiate`, `resolve-param-type-bound`, `method-bound-ret-type`,
  `subst-param-types-bound`, `caller-has-constraint`, `sig-provides-call`,
  `abstract-call-via-protocol/-generic`, `gcheck(-walk-children)`,
  `gbind-decl-type`, `check-generic-template`, `method-has-nested-tyvar`,
  `method-has-valid`, `template-result-type`, `valid-resolve-type`,
  `valid-walk(-children)`, `valid-check-instance`, `protocol-lookup`,
  `protocol-new`, `type-conforms-drop`, `type-trivially-copyable`,
  `blanket-conforms`, `derive-closure-conformance`, `proto-sigs-resolve`,
  `builtin-op-result-type`, `method-satisfies-sig`, `tmpl-conformance-add/
  -check-one/-check-instance/-recheck-stamped`, `callable-get-type/
  -invoke-type/-value-type`) → `(raw Generic)`/`(raw Method)`/`(raw Type)`/
  `(raw Protocol)`/`(raw StructTemplate)`/`(raw TmplConformance)`/`(raw
  StructDef)`/`(raw BinOp)`.
- **`Node*` params** (the batch-2 recommendation): every `n`/`node`/`form`/
  `bind-node`/`params-node`/`pat`/`ptn`/`sig`/`sel-node`/`stamped`-shaped
  single-node param across the generic-registration, A2-checker, and
  node-type families → `(raw Node)`, including the `node-type`/`gcheck`/
  `valid-walk` dispatch functions themselves. The lockstep (conventions.md)
  was not at risk: these are param retypes only, not changes to what `Val`
  type any `emit-*` function returns — `node-type`'s own per-node-kind
  *return* typing (the half of the lockstep that must mirror `emit-node`) is
  untouched.
- **Generic name/spelling strings** (`name`, `fname`, `proto-name`,
  `type-name`, `typename`, `gname`, `cty`, `mname`, `iname`, `head`,
  `ir-prefix`, `mangled`, `sub`/`super`, `cvtype`'s sibling `proto`, etc.) →
  `CStr`, audited per the traps below.
- The **want channel** (`want:ptr` in `generic-resolve`,
  `generic-method-bind(-adapt)`, `generic-resolve-adapt-tier`,
  `node-type-call`) → `(raw Type)` uniformly, even though the shared global
  `g-want-type` (nucleusc.nuc) stays untyped `ptr` until the next batch — a
  bare-ptr argument coerces freely into the newly-typed param (the same free
  coercion batch 1/2 already proved).
- ~25 redundant `xx:ptr:X (cast ptr:X yy)` local-cast collapses to plain
  rebinds, plus a further ~15 now-dead inline `(cast ptr:Type _)`/`(cast
  ptr:Node _)` wrappers inside `->` chains simplified to direct field access
  once the chain's head was retyped (e.g. `(-> at (cast ptr:Type _) (_
  kind))` → `(at kind)`).

**New trap this batch, distinct from anything batch 1/2 hit: a `Node*`
dispatch-head param compared against a quoted-symbol literal (`(= hp 'let)`)
is safe to retype to `(raw Node)`, NOT a CStr/identity hazard.** `gcheck`,
`valid-walk`, and `node-type`'s head-symbol dispatch ladders (mirroring
`emit-list` in nucleusc.nuc) all bind `hp:ptr (cast ptr head)` — the head
*Node*, not its string — and dispatch via `(= hp 'let)`/`(= hp 'quote)`/etc.
`'let` reads as `(quote let)`; `emit-quote-tree`'s `NODE-SYM` case
(nucleusc.nuc) lowers a quoted bare symbol to a runtime `@intern-symbol(...)`
call, and `lib/node.nuc`'s `intern-symbol` returns one canonical, memoized
*Node* per unique spelling (not just an interned string) — so every
occurrence of a `let`-headed form anywhere, whether parsed from real source or
materialized by evaluating `'let`, shares the exact same Node pointer. `hp`'s
comparisons are therefore genuine Node-identity tests, never string
comparisons — retyping `hp` from bare `ptr` to `(raw Node)` cannot engage the
CStr/StrView mixed-operand rule (Node is not a string kind), so it is
IR-neutral regardless of pointer kind. This was verified empirically (byte-
identical before/after) and is the opposite lesson from the `tvname` trap
below: not every symbol-shaped comparison is a string comparison — check what
is actually being compared, not just the local variable's name.

**Identity-comparison trap, same class as batch 2's memo-key finding but a
direct case this time (not a memo table one hop removed):
`pattern-determines-tyvar`'s and `node-mentions-tyvar-named`'s `tvname`
param stay `ptr`, not `CStr`.** Both compare `tvname` directly against `(n
s)` — `Node.s`, the NS-5 identity substrate, itself never `CStr`. Before this
batch that `=` was a plain `icmp eq ptr`; retyping `tvname` to `CStr` would be
the *first* CStr hop in that specific comparison, turning it into a `strcmp`
that did not exist before — a real, non-inert IR change (extra `call
@strcmp`), not just a "theoretically fine because interned strings coincide"
case. The generalizable test used throughout this batch: a comparison is safe
to make CStr-inert only when it is *already* forced to `strcmp` by the other
operand (a string literal, or a field/param that was already `CStr` before
this edit) — if neither side was `CStr`/`StrView` before, introducing one now
is a genuine, detectable-by-diff behavior change, never "probably fine."
`make-tyvar-type`'s `m` parameter was left `ptr` for an unrelated, adjacent
reason: it is a deliberate type pun (a template `Method*` stored through
`Type.sdef`, which is declared `(raw StructDef)`) confined to the TY-TYVAR
A2-checker path that never reaches codegen — retyping it would either force a
type-mismatch at the `.set!` or require an explicit reinterpret-cast that
obscures the pun further, for no benefit since `TY-TYVAR` never flows to
`type-to-ir`/codegen anyway (conventions.md's `TY-TYVAR` note).

**No new null-check-on-parameter or conj/dispatch traps found this batch** —
audited every CStr candidate's own body for `(= param null)`/`(!= param
null)` and for `conj`-into-`(Vector ptr)` sinks; none of this file's
string-shaped params hit either shape. Every array-shaped param (`param-
types`, `argtypes`, `arg-nodes`, `tyvars`, `out-tyvars`, `out-bound`, `bound`,
`con-protos`/`con-vars`/`con-args`/`con-nargs`, `tyvar-names`, `spellings`,
`ptypes`, `pspellings`, `arg-spellings`, `bindings`, `sigs`, `args`) was left
`ptr` — these are genuinely `ptr`-to-`ptr` arrays (14.4's array-of-struct
territory, not this phase). A handful of **mixed-provenance returns were
deliberately left `ptr`** rather than promoted to `CStr`/`(raw Type)`/`(raw
Node)`: any function that can return a `Node.s`-derived identity value down
one path (`defn-name-only`, `defn-ir-name`, `defn-form-mangled-name`,
`gbind-name`, `method-undetermined-tyvar`, `tyvar-type-name`,
`extend-proto-name`) keeps its return as `ptr` on the same NS-5 reasoning as
`Sym.ir-name`/`Method.ir-name`, even where *other* return paths in the same
function are freshly-formatted strings that would individually be CStr-safe —
mixing is not worth the risk for a single return-type annotation. Functions
resolving through not-yet-typed downstream helpers (`gcheck`, `valid-walk`,
`sig-provides-call`, `abstract-call-via-protocol/-generic`,
`template-result-type`, `valid-resolve-type`) similarly kept `ptr` returns.

Verification: `make` clean; `make test` 168/168; `make bootstrap` fixed point
(`stage1.ll == stage2.ll`); `build/nucleusc.ll` diffed **byte-identical, zero
lines** against a from-scratch baseline built with the pre-batch source and
the same unmodified `bin/nucleusc` boot — checked incrementally after each of
the file's seven logical sections (generic registry; bounded-generic defn;
constraint resolution/instantiation; tyvar utilities+gcheck+valid-walk;
protocol/conformance; `emit-extend`+import; node-type family), so the one
paren-count slip this batch hit (removing a now-redundant `(cast ptr
...)` wrapper inside a deeply nested `when`/`let` in `prescan-protocols` left
one extra trailing `)`, caught immediately by `make`'s parse error before it
could be confused with anything semantic) was caught and fixed within its own
section rather than surfacing at the end. `examples/and-narrow.nuc` re-run
clean; no `(ref T)` promotions this batch (every retype was `(raw T)`, `CStr`,
or a deliberate `ptr`), so no new flow-check obligations were introduced.

**generics.nuc is now fully done for 14.3** — no further elem-less `:ptr`
signature population remains in this file (confirmed by re-running the
survey script against the final state: every remaining bare `:ptr` is either
a `ptr`-to-`ptr` array, an out-param box, or one of the deliberate
identity/type-pun exceptions documented above). Next batch (per the file-
cluster order): `nucleusc.nuc` — the largest remaining file, and the one that
owns the `emit-*`/`emit-node` half of the lockstep, so extra care is needed
there specifically when a param retype is adjacent to a function whose
*return Val's type* is also in play (as opposed to this batch, which only
ever touched param types). `nucleusc.nuc` also has many more `hp`/`h`
head-dispatch sites in `emit-list` matching the pattern documented above —
the same `(raw Node)` retype should be safe there too, but verify with the
same byte-identical-per-section discipline rather than assuming.

**Status (batch 4, 2026-07-13): `nucleusc.nuc` started — sections "Global
variables" through "Special forms" done (source lines 1-3290 of the pre-batch
file; roughly a third of the file), byte-identical, verified incrementally
after every section (not just at the end).** `nucleusc.nuc` is far larger
than any single file in batches 1-3 (10,074 pre-batch lines, 282 `defn`s), so
per the dispatch brief's explicit expectation this batch covers a clean
leading portion rather than the whole file. Sections completed, in order:
"Allocation helpers" (`alloc-val`/`nucleus_gensym`), "AST printer"
(`fprint-node`/`print-node`/`macro-jit-ensure-decl`/`split-typed`/
`extract-name-type`/`extract-name-and-type`), "Stage 14 defn-signature.md
S1" (`sig-name-is-bare`/`legacy-ret-node`/`defn-parse-sig`/
`normalize-ret-node`/`defn-ret-node`/`proto-sig-parse`), "Expression codegen"
(`emit-node` itself plus `emit-int`/`emit-char-literal`/`float-literal-ir`/
`emit-float`/`emit-string`/`emit-keyword`/`emit-quote-tree`/`ty-raw-node`/
`emit-quote`/`qq-is-tagged`/`emit-qq-list`/`emit-qq-form`/`emit-quasiquote`),
"Stage 10 flow narrowing + escape analysis" (`sym-effective-type`/
`narrow-apply`/`narrow-kill`/`node-is-null-sym`/`node-binding-name`/
`test-true-nonnull`/`test-false-nonnull`/`prescan-kill-sets`/
`scope-descends`/`taint-merge`/`val-copy-taint`/`taint-store-check`/
`emit-symbol-ref`), "Binary operations" (`add-binop`/`node-is-int-literal`/
`float-width`/`coerce-num-val`), "Stage 8 defcast registry"
(`register-cast-rule`/`lookup-cast-rule`/`safe-coerce-val`/`emit-defcast`/
`binop-coerce`/`strview-data-ir`/`emit-binop-vals`/`emit-binop`), "Cast"
(`emit-cast`), "Struct field access" (`union-field-guard`/
`struct-field-index`/`emit-field-load`/`emit-field-get`/`emit-field-set`),
"Callable values" (`selector-literal-sym`/`emit-selector-value`/
`emit-computed-field`/`emit-get-intrinsic`/`generic-resolve-nullable`/
`generic-has-receiver-method`/`emit-get-with-callee`/
`emit-invoke-with-callee`/`emit-callable-value`/`emit-get`/`emit-invoke`),
"sizeof, alloca, array ops, char, pointer ops" (`emit-sizeof`/
`emit-alloca-form`/`emit-aref`/`emit-aset`/`emit-char`/`emit-addr-of`/
`emit-funcall-void`/`emit-funcall-ptr-1`/`emit-funcall-ptr-i32`/
`emit-funcall-ptr-i64`/`emit-funcall-ptr-ptr`/`emit-funcall-value`/
`emit-funcall`/`emit-deref`/`emit-ptr-set`), the first two functions of
"Function calls" (`emit-call`/`emit-call-with-args` — signature-only: their
own deep `args`-array pointer arithmetic, TE-3/TE-6 boxing, and ABI-coercion
internals were deliberately left untouched as genuine raw-buffer manipulation,
not single-object casts), and "Special forms" (`is-libc-alloc`/
`with-drop-method`/`union-drop-arm`/`emit-defer`). ~92 `defn` signatures
touched: the large majority of params/returns retyped `(raw Node)` (~170
occurrences counting both params and the traversal-cursor local rebinds this
mandates), `(raw Type)` (~45), `(raw Val)` (~30), `(raw StructDef)` (~12),
`(raw Sym)`/`(raw Scope)`/`(raw Generic)` (~7 each), `(raw Method)`/
`(raw BinOp)`/`(raw UnionDef)` (a handful each), and CStr (~25, mostly
diagnostic-label params and IR-fragment-string helpers like
`float-literal-ir`/`emit-quote-tree`'s return, matching the established
`type-mangle-token`/`abi-ret-ir` precedent from batches 1-2). Dozens of now-
redundant `xx:ptr:X (cast ptr:X yy)` locals collapsed to plain rebinds per the
traversal-cursor rule, and the `-> v (_ f) (cast ptr:T _) (_ g)` thread-macro
idiom simplified to direct `((v f) g)` chains at every site this touched
(`emit-binop-vals`, `emit-cast`, `emit-aref`/`emit-aset`/`emit-deref`/
`emit-ptr-set`, `emit-field-get`/`emit-field-set`, `emit-get-intrinsic`,
`emit-addr-of`, the `emit-funcall-*` family, etc.) — the same simplification
batch 3 made in generics.nuc, now extended through nucleusc.nuc's own
`emit-*` family.

**`emit-node`'s own `n` param retyped to `(raw Node)`, and the lockstep held**
(conventions.md): only `emit-node`'s *parameter* changed; its dispatch
structure and the `Val`/type it returns down every path are byte-for-byte
unchanged, so `node-type` (generics.nuc) needed no matching edit. The same
reasoning applied to every other `emit-*` function touched this batch
(`emit-int`, `emit-string`, `emit-binop-vals`, `emit-cast`, `emit-field-get`/
`-set`, `emit-get-intrinsic`, the `emit-funcall-*` family, `emit-call(-with-
args)`, etc.): param-only retypes, zero changes to what any of them return.

**The `hp`/head-dispatch Node-identity pattern (batch-3 finding) recurred
several times in this batch's territory and was retyped every time, verified
empirically byte-identical each time — no new instance of the pattern broke
it:** `node-is-label-form`'s `(= head 'label)`, `qq-is-tagged`'s
`(= h tag)`/`(= h null)`, `emit-symbol-ref`'s `(= n 'null)`/`'true`/`'false`/
`'none)`, and `is-libc-alloc`'s `(= hp 'cast)`/`'malloc`/`'calloc`/`'realloc`/
`'strdup)`. `emit-list` itself — the file's actual head-dispatch function the
batch-3 note flagged as the "real" (not lookalike) site — was **not yet
reached**; it lives in the not-yet-touched "List dispatch" section (see
below).

**One local-elimination trap, found and fixed within this batch (new, not
in batches 1-3): collapsing a redundant cast is inert, but eliminating an
entire local variable is not.** `safe-coerce-val`'s cast-rule branch
originally bound both `rule:ptr` (from `lookup-cast-rule`) and a second local
`cr:ptr:CastRule (cast ptr:CastRule rule)` for field access. Retyping `rule`
to `(raw CastRule)` and then **deleting `cr` entirely**, rewiring its two
field reads onto `rule` directly, produced a real (48-line) `build/
nucleusc.ll` diff confined to that one function: one fewer `alloca`/`store`/
`load` triple shifted every later SSA temp number in the function. Caught
immediately by the byte-identical gate (not by inspection). Fix: keep `cr` as
a **plain rebind** (`cr:(raw CastRule) rule`) rather than eliminating it —
this preserves the exact alloca/instruction count and re-verified byte-
identical. Generalize: the "collapse `xx:ptr:X (cast ptr:X yy)` to a rebind"
instruction from batches 1-3 means *retype the cast, keep the local* — merging
two distinct locals into one (even when semantically redundant) is a genuine,
detectable IR change, not an inert cleanup. Every other redundant-cast removal
this batch removed only the cast expression itself (never a whole local
declaration) and stayed byte-identical throughout, including the cases where
a `(cast ptr X)` wrapper was deleted at a call site because the callee's
param was retyped out from under it (e.g. `val-copy-taint`, `struct-field-
index`/`union-field-guard` call sites, `emit-field-load`, `taint-store-
check`) — deleting a *call-site cast expression* is fine; deleting a *local
variable* is the trap.

**No null-check-on-parameter, identity-comparison, or conj-dispatch traps
found this batch** — every CStr candidate's body was audited for
`(= param null)`/`(!= param null)` guards and for flow into a `conj`-into-
`(Vector ptr)` sink before retyping; none of this batch's string-shaped
params hit either shape. `node-binding-name`'s return was the one deliberate
exception kept `ptr` (not retyped to CStr) for exactly the batch-2 reason:
its result is `conj`'d directly into a `(Vector ptr)` fact accumulator in
`test-true-nonnull`/`test-false-nonnull`, and a CStr argument does not adapt
to that bare-`ptr` dispatch parameter — now documented inline at its
definition, matching the `Val.val` precedent. The type-erasure memo family
(`boxedfn-canonical`/`dyn-canonical`/`boxedfn-drop-target`) was left
untouched throughout, per the batch-2 decision, and every value flowing into
one of those functions' still-`ptr` params coerced in freely with no cast
needed.

**No `(ref T)` promotions this batch** — every retype was `(raw T)`, `CStr`,
or a deliberate `ptr` left alone, so no new flow-check obligations were
introduced; `examples/and-narrow.nuc` re-run clean regardless, per the
close-out checklist.

Verification: `make` clean; `make test` 168/168; `make bootstrap` fixed point
(`stage1.ll == stage2.ll`); `build/nucleusc.ll` diffed **byte-identical, zero
lines** against a from-scratch baseline built with the pre-batch source and
the same unmodified `bin/nucleusc` boot — checked after *every* section
listed above (not just at the end), catching the `safe-coerce-val`
local-elimination regression immediately within its own section before it
could be confused with a later edit.

**`nucleusc.nuc` is NOT done — this is a partial pass on the largest file in
the phase.** Remaining, in file order, starting from source line 3292 (the
`; ============` marker immediately after this batch's last completed
section, "Special forms"): "Stage 13 — lambdas / closures" (design/stage13/
lambda.md), "Stage 13 L4 — closure environment + `invoke`, and `vfn`",
"Stage 13 type-erasure TE-2/TE-3/TE-4" (static vtable synthesis, box
coercion, Drop + forwarding — likely the most intricate remaining territory,
heavy with the `boxedfn-*`/`dyn-*` type-erasure machinery already flagged as
partially off-limits per batch 2), "Stage 8 scalar load/store helpers",
"Stage 8 inc!/dec!", "Stage 8 labels and goto", "Stage 8 struct/array
compound literals", "Macro expansion", **"List dispatch"** (this is where
`emit-list` itself lives — the file's actual head-dispatch function that the
batch-3 note and this batch's dispatch brief both flagged; every `hp`/`h`
site found so far in *other* functions retyped cleanly, so the same should
hold for `emit-list`, but verify empirically rather than assuming, per the
brief), "Top-level forms", "Name (non-)shadowing", "defn", "Compile-time JIT
helpers", "compile-time special form", "defmacro top-level form", "String
table emission", "Driver", "Desugar pass" (this is where `desugar-symbol` —
referenced but not yet retyped by this batch — lives), "Compiler
initialization", "Emit quasiquote helpers", "Open/close module streams", and
"Main entry point". Recommend **batch 4b resume at line 3292** ("Stage 13 —
lambdas / closures"), continuing the same per-section byte-identical
discipline, and budgeting extra care for the TE-2/TE-3/TE-4 sections given
their density and the pre-existing partial-migration state of the type-
erasure memo family.

**Status (batch 4b, 2026-07-13): `nucleusc.nuc` is now DONE for 14.3 — all
remaining sections (source lines 3292–end) retyped, byte-identical, verified
after every section.** Batch 4b resumed at line 3292 and completed all 22
listed sections in file order: "Stage 13 lambdas/closures", "Stage 13 L4
closure env + invoke/vfn", "Stage 13 type-erasure TE-2/TE-3/TE-4", "Stage 8
scalar load/store", "Stage 8 inc!/dec!", "Stage 8 labels and goto", "Stage 8
struct/array compound literals", "Macro expansion", "List dispatch",
"Top-level forms", "Name (non-)shadowing", "defn", "Compile-time JIT helpers",
"compile-time special form", "defmacro top-level form", "String table
emission", "Driver", "Desugar pass", "Compiler initialization", "Emit
quasiquote helpers", "Open/close module streams", and "Main entry point".
**141 `defn` signatures retyped.** Breakdown by target (counting both params
and the traversal-cursor/param-alias rebinds a retype mandates): `(raw Node)`
~131, `(raw Type)` ~31, `(raw Val)` ~11, `(raw StructDef)` ~8, `CStr` 31,
`(raw Scope)` 2, `(raw MacroDef)` 2, `(raw Sym)`/`(raw Cleanup)`/`(raw BinOp)`
1 each. `make` clean and `build/nucleusc.ll` diffed **byte-identical, zero
lines** against the pre-batch baseline (same unmodified `bin/nucleusc` boot)
after *every* section — 13 incremental checkpoints, not just at the end.

**The dominant method this batch was signature-only param retyping, which is
byte-identical by construction for the special-form/emit-* family.** Once a
`ptr` param becomes `(raw X)`, every `(cast ptr:X param)` already present in
the body (the ubiquitous `cc:ptr:Node (cast ptr:Node call)` alias in every
`emit-*` special form) is a `ptr`→`ptr` no-op, so leaving the body untouched
is provably inert. This is why `emit-list` — the file's actual head-dispatch
function the batch-3 note flagged — retyped cleanly with a one-line
`n:(raw Node)` change and no body edits: its `hp`/`h`/`head` dispatch **locals**
are derived from `n` and never touched, so the `(= hp 'return)` Node-identity
ladder is bit-for-bit unchanged. Cursor-collapse and thread-macro cleanup were
applied only where cheap and adjacent (section 1's `emit-fn`, section 2's
`fn-*` helpers); the TE-4 and later sections used signature-only edits for
throughput and safety. **No local was ever eliminated** (the batch-4
`safe-coerce-val` trap), so no SSA renumbering occurred anywhere.

**Overloaded-multimethod trap (new this batch, distinct from batch 4): `register-rmacro`
is an overloaded PAIR — `(prefix:ptr wrap-sym:ptr)` and
`(prefix:StrView wrap-sym:CStr)` — dispatch-distinguished by ptr-vs-StrView.**
The `(ptr,ptr)` overload serves `emit-def-rmacro`'s `(register-rmacro
(prefix-node s) (sym-node s))`; the `(StrView,CStr)` overload serves
`init-rmacros`'s string-literal calls. A bare `ptr` argument does NOT adapt to
a `CStr` parameter in `arg-adapts` (only `StrView`→`CStr` adapts — the whole
point of keeping `CStr` distinct is to *allow* `ptr`-vs-`CStr` overloading), so
retyping the first overload's `prefix`/`wrap-sym` to `CStr` would silently
break the `(ptr,ptr)` dispatch. **Left both overloads untouched.** Generalizable
rule: before retyping any string param, confirm the function is a *single* defn
— an overloaded name may be relying on the `ptr`/`CStr` distinction for
dispatch (grep `(defn NAME ` and count).

**Identity-vs-content audit outcomes (all confirmed via struct-field types, not
guessed):** `find-macro`/`enumdef-lookup`/`import-list-has`/`name-existing-kind`
all `=`-compare a stored name field (`MacroDef.name`/`EnumDef.name`/
`StructDef.name`/`Generic.name` — every one already `CStr`) against the param,
so the comparison ALREADY lowers to `strcmp` off the field (the mixed-operand
rule fires off *either* CStr operand, the scope-lookup precedent), making the
param's `CStr` retype inert. Conversely `import-alias-one`'s `sym-ir-name`
stays `ptr`: it is `!=`-compared against **`Sym.ir-name`, which is `ptr` (NS-5
identity)**, so a `CStr` retype there would newly introduce a `strcmp` — left
`ptr`. Null-check exemptions kept `ptr`: `admit-erased-conformance`'s
`proto-name` (`(!= proto-name null)`), `do-import`/`import-key`/
`emit-import-prefixed`'s `prefix` (`(= prefix null)` guards), `sym-set-src-loc`'s
`sym` retyped to `(raw Sym)` (raw is nullable, so `(= sym null)` stays `icmp`).

**Scope decisions (left `ptr` deliberately, documented so 4c doesn't re-touch):**
(1) the type-erasure memo family stayed untouched throughout — `boxedfn-drop-target`
(explicitly on the exclusion list), `boxedfn-canonical`/`dyn-canonical`/
`dyn-proto-of`/`boxedfn-sig-token` (union-registry.nuc), and the `g-vtable-*`
memo (`vtable-memo-lookup`/`-put`, whose `key`/`name` are pointer-identity
memo keys AND are 14.5-earmarked `g-vtable-keys`/`-names`); the *callers* of
these (`ensure-box-drop-fn`, `emit-box-*`, `ensure-vtable-for`, etc.) still had
their *other* params (Type*/Val*/Node*) retyped — a memo value flowing into an
untouched `ptr` memo param coerces freely. (2) The JIT/LLVM-C-API FFI helpers
(`jit-add-module`/`-rt`, `jit-call-ct-main-sym`, `make-target-for-triple`,
`compile-and-link`) and the CLI/filename plumbing (`main`'s `argv`,
`source-file` chain through `flush-module-ir`/`assemble-module-ir`,
`add-include-path`/`add-link-arg` — the latter two feed the 14.5-earmarked
`g-include-paths`/`g-link-args` malloc arrays) kept `ptr` string/buffer params:
these are LLVM handles / IR text buffers / argv, not compiler-internal
Node/Type/Val pointers, and carry no `=`/dispatch semantics inside the type
system. (3) Val-array params under pointer arithmetic (`emit-resolved-call`'s
`args`, `emit-dyn-forward`'s `args` — `(ptr+ (cast ptr:Val args) i)`) stayed
`ptr` (14.4's array-of-struct territory, per the batch-4 `emit-call-with-args`
precedent). (4) Node-tree-building helper *returns* (`fn-rewrite-*`,
`fn-make-int-node`, `union-ctor-form`, `defvar-init-ir`, `desugar-*`, the
`import-list-*` builders) kept `ptr` returns — they hand off freshly-built
`ref:Node`/make-cell trees consumed opaquely by `make-cell`'s `car`/`cdr` ptr
params, so `(raw Node)` buys nothing and would invite a `ref`→`raw` return
flow-check; the name-set-list helpers (`fn-bind-let-names`/`-param-names`,
`apply-leading-ns`) that return a *looked-up* `(raw Node)` value (not a fresh
`ref`) were the exception and did get `(raw Node)` returns, verified inert.

**No new null-check-on-parameter, conj-dispatch, or SSA-shift traps beyond the
overload finding.** `kind-noun`'s return retyped `ptr`→`CStr` (diagnostic-label
helper returning StrView literals; the chameleon collapse makes it byte-identical);
`fn-parse-ret-type`'s return retyped to `(raw Type)` (returns `ty-void`/parse
results, all plain pointers, no `ref`→`raw`). `examples/and-narrow.nuc` needs no
re-run — every retype was `(raw T)`/`CStr`/deliberate-`ptr`, zero `(ref T)`
promotions, so no new flow-check obligation was introduced.

**Status (batch 4c, 2026-07-13): `src/repl.nuc`, `src/nuch.nuc`,
`src/cheader.nuc` done; `src/format.nuc` deliberately left untouched.
Byte-identical, verified after every file. 14.3 is now COMPLETE.** Batch 4c
finished the source-imported sibling files. **16 `defn` signatures retyped**
(`(raw Node)` ×9, `(raw Type)` ×3, `CStr` ×5), each file diffed
**byte-identical, zero lines** against the pre-batch baseline (same unmodified
`bin/nucleusc` boot) immediately after its edits — four incremental checkpoints
— and a full `make` (compile + clang link) succeeds with the final
`build/nucleusc.ll` byte-identical to baseline.

- **`repl.nuc` (fully in scope, no carve-outs) — 5 retypes:** `repl-eval-form`'s
  `form` → `(raw Node)` (signature-only; its `f:ptr:Node (cast ptr:Node form)`
  alias becomes a raw→ref no-op, left as-is); `emit-fn-thunk`/`jit-thunk-module`'s
  `ft` → `(raw Type)` (emit-fn-thunk's `ftt:ptr:Type (cast ptr:Type ft)` collapsed
  to the endorsed rebind `ftt:(raw Type) ft`); `repl-error`'s `msg` and
  `repl-declare-union-ctors`'s `uname` → `CStr` (diagnostic message / union-name
  strings, no `=`/identity comparison, flow only into fprintf and a
  `CStr`-accepting `uniondef-lookup`). **Left `ptr` deliberately:**
  `repl-error-json-puts`'s `s` (`(= s null)` parameter null-check — the
  `program-defn-record`/`abi-print-param` trap class, CStr would crash);
  `repl-read-input`'s return (raw growable stdin buffer, `realloc`'d + `free`'d by
  caller); `rewrite-first-fname`/`update-fn-tgt`'s `buf`/`fname`/`impl-name`/`out`
  (IR-text `memcmp`/`fwrite` rewriter + `FILE*` + LLVM-symbol lookup names);
  `rt`/`fname-ir` in the `repl-jit-module-rt*` family (LLVM resource-tracker
  handles + IR-symbol text). `repl-register-node` has no `:ptr` param/return so
  its body `(cast ptr:StructDef …)` was left alone (14.2-style cleanup, out of
  scope here).
- **`nuch.nuc` (write-side text emitters carved out) — 5 retypes, all
  import/utility side:** `str-ends-with`'s `s` → `CStr` (the tail-vs-`suffix`
  comparison already lowers to `strcmp` off the already-`CStr` `suffix`, so inert);
  `emit-nuch-declare-import`/`emit-nuch-defmethod-import`/`emit-defunion-import`/
  `emit-nuch-import-forms`'s `form`/`forms` → `(raw Node)` (signature-only — these
  *register* declarations/methods/unions and dispatch imported forms; not
  emitters). **Left `ptr`:** every `emit-nuch-*` write function
  (`emit-nuch-list`/`defstruct`/`ret`/`declare`/`defconst`/`defenum`/`defmacro`/
  `defmethod`/`defn`/`defprotocol`/`extend`/`defcast`/`extern`/`header`) — these
  are the `.nuch` text emitters whose job is `print-node`/`printf`-assembling exact
  header output (leave-alone table + carve-out reasoning), including their
  `mangled`/`source-file` string params.
- **`cheader.nuc` (lexer byte-scanner + C-header emitters carved out) — 6
  retypes:** the two non-cursor/non-emitter classifiers `c-fn-noreturn`'s `fname`
  → `CStr` (name comparisons already `strcmp` off string literals) and
  `c-type-to-nucleus`'s `name` → `CStr` + return → `(raw Type)` (a type *lookup*;
  its sole consumer `c-parse-type` binds the result to a bare-`ptr` local, so the
  `(raw Type)` return is flow-exempt and inert); plus the four pure *decision
  helpers* that return a Node/bool and **do not** emit text —
  `extract-type-node`/`cheader-defn-ret-node`'s Node param → `(raw Node)`,
  `cheader-template-instance`/`cheader-mentions-closure`'s `tn` → `(raw Node)`.
  Two of these (`extract-type-node`, `cheader-mentions-closure`) are also called
  from the already-done `nucleusc.nuc`; **the `(node-at …)` → `(raw Node)`
  argument at those cross-file sites (`?ptr:Node` passed to a `(raw Node)` param)
  coerces cleanly and stays byte-identical** — a niche `(Maybe (ref Node))` weakens
  to `(raw Node)` exactly as it already weakened to bare `ptr`. **Left `ptr`
  (carve-out a — lexer byte-cursors):** `c-skip-ws`/`c-read-ident`/`c-skip-parens`/
  `c-parse-type`/`c-parse-func-decl`/`c-parse-struct-body`/`c-parse-struct-decl`/
  `read-pipe-output`/`emit-c-include` (all `buf`/`pos`/`len` raw-byte cursors or the
  clang-`-E` parse driver). **Left `ptr` (carve-out b — C-type-spelling string
  producers / header emitters):** `type-name-to-c`/`niche-sym-to-c`/`type-node-to-c`
  and every `emit-cheader-*`. The two FFI `declare`s (`popen`/`pclose`) keep their
  C-ABI `ptr` params.
- **`format.nuc` — 0 retypes, left entirely (the conservative call the brief
  invited).** Every function is either a fixed-arity `snprintf`-vararg wrapper
  (`fmt-i32`/`fmt-i64`/`fmt-s`/`fmt-sd`/`fmt-2s`/`fmt-3s`/`fmt-2s-i`/`fmt-i32-i32`)
  or a byte-by-byte string transformer/scanner (`sanitize-for-ir`/`sanitize-for-c`/
  `ir-name-append`/`ir-name-token`/`ir-name-illegal-char`). The `fmt`/`s` params
  ARE genuine C-strings, but a `CStr` retype deletes **zero** casts and simplifies
  **zero** comparisons (they flow straight to `snprintf` as varargs — `is-ptr-like`
  already treats `CStr`≡`ptr` there), so it clears neither half of the "clearly
  safe AND clearly beneficial" bar while carrying maximum blast radius (these are
  the most-called helpers in the tree) and the documented arity/segfault
  sensitivity. `ir-name-token` in particular is bootstrap-critical (its own comment
  warns any perturbation renames the compiler's hyphenated symbols) and returns its
  argument by pointer-identity on the fast path. None warrants a retype.

**One trap worth recording, matching batch 4b's overload finding shape but
resolved the other way:** the CStr candidates here were all confirmed *single*
`defn`s (`grep -c "(defn NAME "`), and each string param was audited for a
`(= param null)` guard (only `repl-error-json-puts`'s `s` had one → left `ptr`),
for identity comparison against a `ptr`-typed field (none), and for a
`conj`-into-`(Vector ptr)` sink (none). No new trap class emerged; the batch was
dominated by signature-only `(raw Node)` param retypes on
registration/dispatch/decision helpers, which are byte-identical by construction
(the in-body `(cast ptr:Node param)` alias becomes a raw→ref no-op). No `(ref T)`
promotions anywhere, so no flow-check obligation was introduced; `examples/and-
narrow.nuc` needs no re-run.

**14.3 is COMPLETE across the whole compiler translation unit** (scope/type-utils/
type-mangle → abi/union-registry/union-emit → generics → nucleusc → repl/nuch/
cheader; format left by design). `src/reader.nuc` / `lib/*.nuc` are library files —
a separate later concern if pursued at all. The full-suite `make test` +
`make bootstrap` fixed-point verification for the 14.3 batches runs in the
build-test-runner pipeline stage, not here.

### 14.4 — Parallel arrays → array-of-struct  *(controlled refresh)*

**Status (batch 1 — `UnionDef` arm arrays → `Arm`, 2026-07-13): DONE, controlled
refresh reconverged in one pass.** Introduced
`Arm{name:CStr, ptype:(raw Type), fnames:ptr, ftypes:ptr, nfields:i32}`
(compiler-types.nuc, immediately before `UnionDef`) and replaced `UnionDef`'s five
parallel arm arrays (`arm-names`/`arm-ptypes`/`arm-fnames`/`arm-ftypes`/
`arm-nfields`) with a single `(arms (ref (Vector (ref Arm))))` field. `num-arms`
was **kept** as the cached i32 length (it is the shared count, not one of the
parallel *data* arrays, and keeping it avoids churning every `(udd num-arms)`
loop into `(cast i32 (count …))`). Every ragged `(aref (cast ptr:ptr (udd arm-X))
i)` lockstep walk is gone — reads are now `(invoke (udd arms) (cast usize i))`
returning a `(ref Arm)` with direct field access (an arm bound once per iteration
where several of its fields are read). Touched: the build/classify/payload-union
sites in union-registry.nuc (`defunion-register`, `union-layout-classify`,
`arm-is-typed-ref`/`arm-is-err-field` refactored to take `(ref Arm)`,
`union-arm-index`/`union-arm-index-in` refactored to scan the Vector,
`result-ok-type`); the unwrap/construct/match readers in union-emit.nuc
(`emit-unwrap-result`, `emit-unwrap-or-result`, `emit-union-construct`,
`result-err-arm-is-err`, `emit-match-binders`, `emit-match-clauses`);
`union-drop-arm` (nucleusc.nuc); `repl-declare-union-ctors` (repl.nuc).

Findings worth carrying to the later 14.4 sub-steps:
- **A `(Vector (ref Arm))` field type resolves inside `compiler-types.nuc`**
  (imported at nucleusc.nuc:23, long before `(import-use vector)` at :463) because
  `prescan-imported-types`/`prescan-struct-names` register the `Vector` struct
  template and the `Arm` name **globally, before any form is emitted** — the same
  reason the `g-uniondefs` defvar (`(ref (Vector (ref UnionDef)))`, nucleusc.nuc:115)
  already resolves before the vector import. The pending-IR drain defers the
  `%Vector.…`/`%AllocHandle` dependency exactly as for the existing registry
  instances. So a compiler-internal struct **can** hold a typed `Vector` field.
- **The layout change reconverged in ONE pass** — `make bootstrap` PASSED
  (`stage1.ll == stage2.ll`) *before* `make update-bootstrap`, contrary to the
  "controlled refresh drifts" expectation. The refactor changes only the
  compiler's internal data structures and its arm-reading logic, **not the IR it
  emits for any construct**, and Vector-instance stamping is deterministic across
  the old boot and the new compiler — so the old boot emits the new source
  identically to the new compiler. `update-bootstrap` was still run at the
  milestone to keep the committed `boot/*.ll` fallback IRs synced. `make test`
  168/168 throughout.
- **`arm-fnames` was dead storage** (written by `defunion-register`, read
  nowhere) on the old `UnionDef`. `Arm.fnames` is likewise write-only today;
  retained to match this section's named `Arm{…, fnames, …}` shape (a later
  sub-step folds `fnames`/`ftypes` into a `Field{name,type}` element).
- **Spelling trap:** `x:ref:(Vector T)` (colon *before* the parametric paren)
  mis-parses in the reader; use list-form `(x (ref (Vector (ref Arm))))` for
  params or colon-paren `x:(ref (Vector (ref Arm)))`/list-form for let bindings.

**Status (batch 2 — `&where` quad → `Constraint` + `Conformance.args` →
`(Vector CStr)`, 2026-07-13): DONE, controlled refresh reconverged in one pass
(again).** Introduced `Constraint{proto:CStr, var:CStr, args:ptr, nargs:i32}`
(compiler-types.nuc, immediately before `Method`) and replaced **both** `Method`'s
and `TmplConformance`'s four parallel `&where` arrays
(`con-protos`/`con-vars`/`con-args`/`con-nargs`) with a single
`(constraints (raw (Vector (ref Constraint))))` field, keeping `num-constraints`
as the cached count (same rationale as `num-arms` in batch 1). `proto`/`var` are
`CStr` (not the old bare `ptr`): every comparison already had a `CStr`/StrView
operand on the other side (`tyvar-index-of`'s `name:CStr`, the `tvname`/`tyvar-name`
locals, the `"Valid"` literal), so the retype is byte-identical in lowering *and*
semantically honest; `args`/`nargs` stay a ragged `ptr[]`+count (the assoc-type
Arg-pattern nodes, like `Arm.fnames`/`ftypes`). Converted `Conformance.args` to
`(raw (Vector CStr))` (dropping the `nargs` field — the count is `(count args)`)
and folded `conformance-args-eq` into a value-equality helper over two Vectors
(element type `CStr` makes `!=` a strcmp); `(Vector CStr)` **already existed**
(`g-blanket`/`g-macro-decls`), so no new instance stamped for it. Every ragged
`(aref (cast ptr:ptr (mm con-X)) i)` lockstep walk is gone — a constraint is now
read `(constraints-at (mm constraints) i)` → a `(ref Constraint)` with direct field
access. Touched: the build/parse/fixpoint sites in generics.nuc
(`parse-where-constraints` now conjs `(ref Constraint)` records into the Vector;
`register-generic-defn` and the `emit-extend` `&where` path each create the Vector
via `(vector-new-in (addr-of g-arena-alloc))` and store it; `tmpl-conformance-add`
takes the Vector); the readers (`recover-one-constraint`/`recover-assoc-into`,
`generic-method-bind`/`-adapt`, `generic-constraints-ok`, `caller-has-constraint`,
`abstract-call-via-protocol`/`-generic`, `check-generic-template`,
`method-has-valid`, `tmpl-conformance-check-one`); and the
`conformance-add`/`-args`/`-args-eq` trio.

Findings from batch 2:
- **`count-pattern-nodes` was NOT deleted — the design's premise was wrong.** It
  sizes the **`tyvars`** array (`cap`/`slot-bound` in `register-generic-defn`
  generics.nuc and the `emit-extend` `&where` path), *not* the constraint arrays.
  The constraint arrays were exactly sized by `nc` (`node-len`-derived), which now
  becomes the Vector's grow-on-demand count. Since `tyvars` stays a raw arena array
  in this batch, `count-pattern-nodes` and all its call sites remain live. (The
  design line ":793-800, :969-976" referred to constraint sizing; those line ranges
  had already drifted and the code there is tyvar sizing.)
- **Reconverged in ONE pass again** — `make bootstrap` (`stage1.ll == stage2.ll`)
  PASSED *before* `make update-bootstrap`, for the same reason as batch 1: the
  refactor changes only internal data structures + constraint-reading logic, not the
  IR emitted for any construct, and the new `(Vector (ref Constraint))` instance
  stamps deterministically across the old boot and the new compiler.
  `update-bootstrap` still run to sync the committed fallback IRs. `make test`
  168/168 throughout; round-2 `make clean && make && make bootstrap` PASS.
- **The nullable `constraints` field forces a `raw→ref` assertion at every `invoke`
  read.** Most Methods are non-generic (null constraints), so the field is honestly
  `(raw …)`; the flow-checker then rejects `(invoke (mm constraints) i)` ("raw
  pointer where non-null (ref …) is required"). Centralized in a `constraints-at`
  helper (`(cast (ref (Vector (ref Constraint))) cons)` then `invoke`), sound because
  every call is guarded by `num-constraints > 0`. The two *builder* fixpoints
  (`register-generic-defn`, `emit-extend`) invoke the freshly-created **local** `ref`
  Vector directly, so they need no cast. The `conformance-args` return
  (`(raw (Vector CStr))`, `die-at`-guarded — `die-at` is not known-noreturn, so no
  narrowing) needed the same one-shot cast before its `invoke` loop.

**Status (batch 3a — `StructDef.field-names`/`field-types` → `Field`, 2026-07-13):
DONE, controlled refresh reconverged in one pass (again).** Introduced
`Field{name:ptr, type:(raw Type)}` (compiler-types.nuc, immediately before
`StructDef`) and replaced `StructDef`'s two parallel arrays (`field-names`/
`field-types`) with a single `(fields (raw (Vector (ref Field))))` field, keeping
`num-fields` as the cached count (same rationale as `num-arms`/`num-constraints`;
it is read on the hottest paths — `struct-field-index` and the ABI classifier).
This is the highest-surface 14.4 batch (~40 `field-names` + ~64 `field-types`
sites across abi/cheader/compiler-types/union-registry/generics/repl/nucleusc).

- **`Field.name` stays `ptr`, NOT `CStr`** — the batch-2 `Constraint.proto`
  reasoning (retype to CStr because every comparison already had a CStr operand)
  does *not* apply. `struct-field-index` (nucleusc.nuc) matches a selector against
  the field name by **pointer identity** (`(= (field name) fname)`, both interned
  ptrs) on the hot field-access path; struct-field names are on the NS-5
  identity-substrate exclusion list. A `CStr` retype would lower that hot compare
  to `strcmp` (behavior-preserving — interned strings are strcmp-equal — but a
  perf regression and an IR shift). `Field.type` is `(raw Type)` to match the
  stage-14 Type-pointer idiom and every consumer's `t:raw:Type` param; `(raw Type)`
  binds implicitly into the bare-`ptr` locals the readers use and returns fine
  into a `?ptr:Type` (verified: `callable-get-type` already returns a `(raw Type)`
  `Method.ret-type` into its `?ptr:Type`).
- **Two shared accessors, both in abi.nuc** (the earliest field reader, imported
  before union-registry): `field-at (fields i):ref:Field` (the batch-2
  `constraints-at` pattern — a `raw→ref` cast then `invoke`, sound because every
  caller loops under the `num-fields` bound so null `fields` is never indexed) and
  `struct-set-fields (sd fnames ftypes nf):void` (the single array→Vector
  conversion point — every builder that had parallel `fnames`/`ftypes` arrays now
  calls it; loop-in-place builders (emit-defstruct, the vfn/cfn env struct,
  struct-template-stamp, repl-register-node) were redirected to *local* arrays +
  one `struct-set-fields` call, keeping their per-field extract/emit logic byte
  -for-byte). Names are **not** re-interned in `struct-set-fields` — the caller's
  arrays already hold the canonical interned pointers, preserving identity.
- **`fields` is `(raw …)` (nullable), unlike `UnionDef.arms` which is `(ref …)`.**
  `register-struct` (the sole allocator) pre-registers a name-only struct with
  `num-fields 0` and `fields` null (from `new`); `struct-set-fields` fills it
  later. So the field is honestly nullable and reads go through the `field-at`
  cast, exactly the batch-2 nullable-`constraints` situation.
- **abi.nuc IR-lowering zone: field *access* retyped, algorithm untouched.**
  `abi-union-size`/`abi-struct-align`/`abi-struct-size`/`abi-class-eightbyte` had
  their `(aref (cast ptr:ptr (sdd field-types)) i)` reads swapped to
  `((field-at (sdd fields) i) type)` with the exact same iteration order and
  merge logic — `field-at` returns the identical `Type*` `aref` did, so the
  eightbyte classification result is byte-identical. `make abi-test` (`abi-interop`)
  PASSES, and `make bootstrap` stays byte-identical (the ABI codegen never shifts).
- **cheader.nuc text emitters: access retyped, string assembly untouched** (the
  14.3 batch-4c carve-out). The tagged-struct builder calls `struct-set-fields`;
  the typedef-alias path **shares** the source struct's `fields` Vector handle
  (immutable after build) + copies `num-fields`; the alias's `%name = type {…}`
  emit loop reads via `field-at` but keeps its exact fprintf/order.
- **Reconverged in ONE pass** — `make bootstrap` (`stage1.ll == stage2.ll`)
  PASSED *before* `make update-bootstrap`, despite touching abi.nuc. The task
  flagged possible drift, but the emitted IR for every construct (struct layout,
  ABI classification, field GEPs) is a function of the field *types*, which
  `field-at` reproduces exactly — the parallel-array→Vector change is invisible in
  output IR. The OLD boot (parallel-array StructDef internally) and NEW compiler
  (Vector StructDef) emit identical IR for the new source. `make test` 168/168 and
  `make abi-test` green throughout; round-2 `make clean && make && make bootstrap`
  byte-identical.

**Status (batch 3b — `Type.params`/`param-names`/`opt-defaults`, 2026-07-14):
DONE, controlled refresh reconverged in one pass (again).** Folded `Type`'s
**parallel** param pair (`params` = `Type*[]`, `param-names` = name-string[], both
length `num-params`) into a single `(params (raw (Vector (ref Field))))` field,
**reusing batch 3a's `Field{name, type}` struct** (no new element type, matching
the design's literal `Field{name, type}` suggestion). `num-params` is kept as the
cached count (same rationale as `num-arms`/`num-constraints`/`num-fields`). This
closes **14.4 entirely** — every genuine lockstep-walked parallel-array idiom on
`compiler-types.nuc` (UnionDef arms → `Arm`; Method/TmplConformance `&where` quads
→ `Constraint`; StructDef `field-names`/`field-types` → `Field`; Type
`params`/`param-names` → `Field`) is now an array-of-struct.

- **The `opt-defaults` tail asymmetry was resolved by *not* folding it.**
  `opt-defaults` is a **ragged tail** array of length `nopt` (NOT `num-params`):
  it holds default-value Node* forms for only the trailing `nopt` &optional params,
  indexed `0..nopt-1` (slot k ↔ param index `required + k`, `required = num-params
  - nopt`). It is not a parallel array to `params`, so — exactly like `Constraint.
  args`, `Arm.fnames`/`ftypes`, and `StructDef.origin-args` (all *single* ragged
  arrays kept raw by prior batches) — it stays a raw `ptr[]` + `nopt` count,
  **untouched**. This keeps the tail-offset arithmetic at its two live sites
  (`emit-call`'s default-fill read `opt-defaults[oi - required]` and `emit-defn`'s
  build write `opt-defaults[di - required]`) byte-for-byte, eliminating any
  misalignment risk. A `Field{name, type, default}` fold (default null except on
  the tail) was considered and rejected: it would either add a mostly-null `default`
  slot to the *shared* `Field` (churning `StructDef` too) or force a new `Param`
  struct, for no benefit over leaving the honest ragged tail alone.
- **`param-names` was dead storage → the field is dropped, not folded live.** No
  builder ever stored a non-null `Type.param-names` (only the two Type clones
  propagated it); `emit-defn` builds a *local* `param-names` array for the param
  prologue but never writes it onto the Type, and the REPL renders positional
  `%aN`/`pN` (it never reads `Type.param-names`). This is the same "dead parallel
  array" batch 1 found in `arm-fnames`. So the `param-names` field is deleted and
  `Field.name` is left null for every Type param (the `make-param-vec` builder does
  not thread names). Byte-faithful to the current always-null behavior.
- **Two shared build accessors in abi.nuc** (the earliest field reader, imported
  before every fn-type builder): `make-param-vec (ptypes np):(ref (Vector (ref
  Field)))` (builds the Vector with `name` null) and `type-set-params (t ptypes
  np):void` (the single array→Vector conversion point — `make-param-vec` + set
  `num-params`; mirrors `struct-set-fields`). **Reads reuse batch 3a's `field-at`**
  (Type's `params` is the same `(raw (Vector (ref Field)))` element type as
  StructDef's `fields`), so `((ft params)[i])` → `((field-at (ft params) i) type)`.
  Every ragged `(aref (cast ptr:ptr (ft params)) i)` walk is gone.
- **`boxedfn-sig-token` retyped to walk the Vector** (its param went `param-arr:ptr`
  → `params:(raw (Vector (ref Field)))`, walking via `field-at`). Both callers now
  pass a Vector: `boxedfn-type` builds the param Vector *once* via `make-param-vec`
  and reuses that same handle for both the token and the Type's `params` (immutable
  after build); `ensure-fnfwd-vtable` (nucleusc.nuc) already passed `(bt params)`.
- **One wholesale-handle site needed a materialize-back** (`repl.nuc`'s redefinition
  path): `generic-remove-matching-user-method` compares against `Method.param-types`
  (a *raw* array, untouched this batch) via `params-type-eq`, so the fn Type's param
  Vector is materialized back into a temp raw `Type*[]` before the call. Localized.
- **Touched:** compiler-types.nuc (Type struct + comments), abi.nuc (2 new
  accessors), and the build/read sites in generics.nuc, union-registry.nuc,
  cheader.nuc (its build-in-place `alloc (ft params)` + copy loop collapsed to one
  `type-set-params`), nuch.nuc, repl.nuc, nucleusc.nuc, plus the two Type clones
  (type-utils.nuc `type-as-pkind`, nucleusc.nuc `type-with-volatile` — `params`/
  `num-params` stay handle-copies; the dead `param-names` copy line is deleted).
- **Reconverged in ONE pass** — `make bootstrap` (`stage1.ll == stage2.ll`) PASSED
  *before* `make update-bootstrap`, for the fourth 14.4 batch running: the change is
  internal representation + param-reading logic only, invisible in emitted IR, and
  the new Vector-of-Field param lists stamp deterministically across the old boot and
  the new compiler. `make test` 168/168, `make abi-test` (`abi-interop`) green
  throughout; round-2 `make clean && make && make bootstrap` byte-identical. Extra
  territory-specific checks (boxedfn/closures/dyn/fnptr/optional/rest examples diffed
  against `tests/expected/*.out`) all matched — `optional.nuc` (two trailing
  optionals + a call-valued default) confirms the untouched opt-defaults tail path.

**14.4 is COMPLETE.** All four lockstep parallel-array idioms are array-of-struct
(`Arm`, `Constraint`, `Field` ×2). The remaining raw `ptr[]` fields on
`compiler-types.nuc` — `Constraint.args`, `Arm.fnames`/`ftypes`, `Type.opt-defaults`,
`StructDef.origin-args`, and the various tyvar/binding name arrays — are all *single*
ragged arrays with no lockstep partner, deliberately left raw (folding a lone array
into an element struct buys nothing). `Conformance.args` → `(Vector CStr)` was the
one non-element-struct conversion (batch 2).

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

**Status (batch 4, 2026-07-14): DONE, byte-identical bootstrap (one-pass
reconverge).** Sub-steps 1-4 below are now complete — see
[progress.md](../progress.md) for the full writeups. Batch 1
(`g-include-paths`/`g-link-args`): allocator-ordering wrinkle, the
`conj`-needs-explicit-`CStr`-cast finding, and the manual `-I`/`-l` end-to-end
verification. Batch 2 (`g-vtable-keys`/`-names`, `g-ns-prefix-keys`/`-vals`):
each pair became a `{key,val}` element-struct-backed `Vector` as anticipated
below, but the two tables landed on *different* pointer kinds for the Vector
handle itself — `g-vtable-table` is `(ref (Vector (ref VtableEntry)))` while
`g-ns-prefix-table` is `(raw (Vector (ref NsPrefixEntry)))` — because
`compiler-init` explicitly resets the ns-prefix table to null once per
compilation unit (a null literal cannot be assigned to a `ref`-typed variable
under the non-null-pointer flow checker), while the vtable memo is never
reset at all. Also corrected a stale inline comment ("nothing calls
ensure-vtable-for yet") that no longer matched the tree (TE-3 callers exist).
Batch 3 (`g-boxedfn-keys`/`-types`/`-count`/`-cap`, `g-dyn-keys`/`-types`/
`-protos`/`-count`/`-cap`, both union-registry.nuc): two new element structs
in compiler-types.nuc — `BoxedFnEntry{key:ptr, ty:(raw Type)}` (a 2-field
memo, as anticipated) and `DynEntry{key:ptr, ty:(raw Type), proto:ptr}` (a
3-field memo — the `(dyn P)` box additionally carries the protocol name,
confirming the design note's guess) — replacing the two cap-doubling
parallel-array pairs with `g-boxedfn-table:(ref (Vector (ref BoxedFnEntry)))`
and `g-dyn-table:(ref (Vector (ref DynEntry)))` (both `ref`, mirroring
`g-vtable-table`: neither is ever explicitly reset in `compiler-init`, unlike
`g-ns-prefix-table`). Identity-vs-content audit for both: **all** fields stay
`ptr`/`(raw Type)`, never `CStr` — `key` is looked up by pointer identity
(`boxedfn-memo-lookup`/`dyn-memo-lookup`, already interned via `intern-str`
at the call site) and `ty` is looked up by `sdef` pointer identity
(`boxedfn-canonical`/`dyn-canonical`/`dyn-proto-of`), matching batch 2's
`VtableEntry`/`NsPrefixEntry` finding exactly — this family was in fact
already flagged as identity-keyed by 14.3 batch 2's memo-lookup audit (see
that batch's note), so this batch only had to confirm, not discover, the
answer. The union-registry import-ordering caveat turned out to be a
**non-issue**, same shape as batch 1's arena-ordering finding: union-registry.nuc
is imported from nucleusc.nuc *after* both `(import-use vector)` and
`(import-use arena)` have already run (vector.nuc itself pulls in `allocator`
internally), so by the time these two `defvar`s are parsed, `Vector` and
`AllocHandle` are already fully registered — no different from `g-vtable-table`'s
position in nucleusc.nuc, well after the same imports. `pending-union-deps-ready`
/`drain-pending-union-irs` (union-registry.nuc:158-185) never actually engages
here: `BoxedFnEntry`/`DynEntry` have no by-value `TY-STRUCT`/`TY-UNION` fields
(only `ptr`/`(raw Type)`, both pointer-kind, lowering to opaque `ptr` per that
function's own doc comment), so the stamped `(Vector (ref BoxedFnEntry))`/
`(Vector (ref DynEntry))` instances never queue a deferred dependency on their
own account — same as batches 1-2's new Vector instances. Bootstrap reconverged
in **one pass** (`make bootstrap` PASSED before `update-bootstrap`) — no 2-stage
manual workaround needed, consistent with every other 14.5 batch so far; the
change is invisible in emitted IR for any existing `BoxedFn`/`(dyn P)` program
(the memo's *lookup semantics* are unchanged, only its storage). `make test`
168/168; `boxedfn`/`dyn-comb`/`dyn-protocol`/`comb-storage` examples diff-exact
against `tests/expected/*.out`; `make update-bootstrap` refreshed all boot IRs;
round-2 `make clean && make && make bootstrap` byte-identical.

Batch 4 (`Generic.methods`/`num-methods`/`cap`): retired the hand-rolled
`methods:ptr`/`num-methods:i32`/`cap:i32` triple and its manual cap-doubling
grow thunk (`generic-add-method`) for a single
`(methods (ref (Vector (ref Method))))` field — `ref`, matching
`g-vtable-table`/`g-boxedfn-table`/`g-dyn-table` (a `Generic` is arena-allocated
once by `generic-new` and never explicitly reset to null). `generic-add-method`
collapsed to one `conj`. `generic-remove-matching-user-method` (the REPL
redefinition path) needed a genuinely new primitive — **`Vector` had no delete
operation**, only `insert` — so `remove-at ((self (ref (Vector T))) i:usize):void`
was added to `lib/vector.nuc`, mirroring `insert`'s shape (shift `(i,len)` left
by one, shrink `len`). ~30 read sites across generics.nuc/nucleusc.nuc converted
from `(dotimes (i (gg num-methods)) (aref (cast ptr:ptr (gg methods)) i))` to
`(dotimes (i (cast i32 (count (gg methods)))) (invoke (gg methods) (cast usize i)))`,
keeping every downstream local's declared type unchanged (only the initializer
changed, per "retype the cast, keep the local"). **Verification-time finding:**
a mechanical grep-and-replace across the two files caught every site spelled
`(gg methods)`/`(g methods)`/`(igg methods)`, but missed the one site expressed
through the `->` threading macro — `gcheck`'s intrinsic-operator peephole
(`(-> g (cast ptr:Generic _) (_ methods))`, textually invisible to a literal
search for the field name). Left un-migrated, it kept `aref`'ing the new
Vector-struct pointer as a raw `Method*[]`, segfaulting deep inside
`check-generic-templates` — but only for a program exercising the A2 checker on
a **bounded generic with `&where` constraints** (`reduce`, lib/iterator.nuc), so
the compiler's own self-compile and plain Vector-only programs built clean while
`(import-use vector)` alone (pulling in iterator.nuc transitively) crashed every
target compile. No `gdb`/`valgrind` available in the container; diagnosed via
`clang -fsanitize=address` (compiler-rt's static archives were missing for this
clang, so the working recipe was `clang -c -fsanitize=address` on both
`build/nucleusc.ll` and `src/repl_shim.c`, linked with **`gcc`**, which supplies
`libasan` — ASan's trace pointed straight at the stray `aref`). Lesson for future
`.field`-style grep-based migrations: also search for `(-> ` / `_ field)`
head-position-substitution uses of the field name, not just the literal
accessor form. `make test` 168/168; `make bootstrap` fixed point reconverged in
**one pass**; `make update-bootstrap` refreshed all boot IRs; round-2
`make clean && make && make bootstrap` byte-identical; 25
assoc/coll/comb/dyn/generic/hashmap/hashset/iterator/protocol/vector examples
diff-exact against `tests/expected/*.out`. Sub-steps 5-6 remain open.

**Build, cold-first:**
1. `g-include-paths`, `g-link-args` (fixed 64-slot `malloc` → `(Vector CStr)`).
   **DONE (2026-07-14).**
2. `g-vtable-keys`/`-names`, `g-ns-prefix-keys`/`-vals` (→ parallel `(Vector CStr)`
   or a `{key,val}` element struct). **DONE (2026-07-14).**
3. The type-erasure memos `g-boxedfn-*`, `g-dyn-*` — **mind union-registry import
   ordering** (these live in union-registry.nuc, imported early; a
   `(Vector (ref BoxKey))` element there must respect the `AllocHandle` pending-IR
   drain, union-registry.nuc:159-172). **DONE (2026-07-14)** — the ordering
   caveat turned out to be a non-issue (see status note above); one-pass
   reconverge.
4. `Generic.methods` (→ `(ref (Vector (ref Method)))`, deleting the grow thunk).
   **DONE (2026-07-14)** — plus a new `Vector.remove-at` primitive (see status
   note above); one-pass reconverge.
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
