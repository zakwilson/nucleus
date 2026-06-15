# Stage 11 Progress — Parametric Structs

Status: **done** (T0–T5) — back to [../progress.md](../progress.md)

75 tests pass; `make bootstrap` is a byte-identical fixed point.

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

---

## Known limitations (deferred)

1. **Colon binding sugar with a parenthesized RHS:** `name:(ref (Vector T))` does
   not tokenize. Use `(name (ref (Vector T)))`. Pre-existing tokenizer limitation.
2. **`declare` with a parametric return type** requires the list-form name node:
   `(declare (p2_make (P2 i32 i32)) (...))`.
3. **Generic functions bounded on a parametric protocol** (`&where ((Seq E) Self)`) are
   not supported — the `&where` parser requires `(Var Protocol)` with plain symbols. The
   associated-types frontier is deferred to a future pass. Conformance is exercised via
   `extend` + stamp-time checking + ordinary overload resolution (the `examples/parametric.nuc`
   working pattern).
