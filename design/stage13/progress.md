# Stage 13 Progress: Lambdas and closures

Detailed task table for the L0–L9 lambda/closure implementation. Design:
[lambda.md](lambda.md); build order / acceptance gates: [lambda-prompt.md](lambda-prompt.md).
**123 tests pass; `make bootstrap` is a byte-identical fixed point.**

**Follow-ons (not started):**
- [closure-enhancements.md](closure-enhancements.md) — feature enhancements that
  complete the closure feature: **CE-1** named closures (`let`/`with` env-type
  inference), **CE-2** mutable capture (`set!`/`inc!`/`dec!` on a capture),
  **CE-3** owning-closure export (by-value return), **CE-4** storable closures
  (`BoxedFn`, design exploration only); plus the `cfn`-of-pointer escape
  imprecision. Tracked here once dispatched.
- [functional-refactor.md](functional-refactor.md) — the dogfooding refactor of
  the compiler and libraries around named closures, eager sequence combinators,
  `Vector`, and iterators. Build order: phases **R1 … R4** (depends on CE-1).
  Tracked here once dispatched.
- [type-erasure.md](type-erasure.md) — the committed **shared type-erasure
  machine**: one two-word fat pointer + static per-type vtable that realizes
  CE-4's `BoxedFn` *and* the deferred Stage 9 rung-5 `(dyn Protocol)` as two
  instantiations of the same mechanism. Build order: phases **TE-0 … TE-7**
  (shared machine + `BoxedFn` first, then general `(dyn P)`); gated behind CE-3.
  Supersedes the CE-4 Option 3 sketch. Tracked here once dispatched.

| Phase | Status | What landed | Key functions / files | Notes / surprises |
|---|---|---|---|---|
| L0 — Ground-verify | Done | Read-only map of the escape/`invoke`/conformance/struct-template/worklist/`Drop` machinery; build assumptions confirmed | (read-only survey) | Taint is a `Scope*` (not boolean) → region tagging a natural extension; **no synthesized `drop` exists** (closures generate the first); a lifted top-level `defn` can be queued from inside expression emission and drained like a generic stamp |
| L1 — Escape generalization | Done | `addr-of`/`.&` on frame-local storage taints a region-tagged pointer; upward escape (return / store-out) rejected; reference/pointer params excluded; `move`/copy/`deref`-out clear taint | `emit-addr-of`, `node-type-addr-of`, `emit-return`, `pkind-flow-check`, `emit-move`, `emit-field-addr`, `emit-ptr-add`, `emit-cast` | **Only non-additive phase.** Measure-then-flip found no genuine `return &local` site in the compiler; re-converged byte-identical. `let` gains no drop/lifetime semantics — pointer-provenance only |
| L2 — `Clone` | Done | `Clone` protocol + automatic structural conformance (bitwise) for trivially-copyable types; hand-written `clone` for owning types; `Drop`-without-`Clone` is not `Clone` | `blanket-conforms`/`blanket-lookup` (alongside `Any`/`Struct`), `type-conforms-drop` | Modeled on built-in blanket rules, **not** user `extend` |
| L3 — `fn` | Done | Anonymous function → bare function pointer; free-variable/capture analysis; rejects enclosing-local capture with a directed error; lambda-lifts to a gensym top-level `defn` | `fn-capture-walk` / `fn-capture-check`, `emit-fn`, top-level worklist | First cut forbids **all** enclosing-local capture (the inlinable-const-local relaxation deferred). `fn` is the only form emitted to C headers |
| L4 — `vfn` + env + `invoke` | Done | Anonymous env struct `__vfn_env_N` (one field per capture) + `invoke` method of the closure's arity; per-field `clone`; synthesized `drop` iff any capture is `Drop`; POD-only = non-owning by-value | `fn-make-env-struct`, `fn-make-invoke-method`, `fn-rewrite-captures` (+`-list`/`-rest`/`-from`/`-let-binds`), `fn-emit-env-value`, `fn-make-drop-method`, `fn-force-generic-mangled`, `fn-caps-count`, `fn-env-ref-type`/`-ptr-type`, `emit-vfn` | **Direct env emission, not a struct literal** — `emit-struct-lit` misreads `(clone (addr-of x))` as `clone:=`. **`fn-force-generic-mangled` is load-bearing** (lone-`Drop` `@drop` hijack). `self` prepended onto the whole params spine. 112 tests |
| L5 — `mfn` | Done | Move-capture via a single mode flag on `fn-emit-env-value`; reuses all L4 machinery verbatim; `move` sink disarms + marks consumed | `emit-mfn`, `fn-emit-env-value` (mode 1) | Export-from-`with` confirmed at IR level: move disarms source cleanup → return sound, no escape error. Minimal factoring — one mode flag, no forked emitter |
| L6 — `cfn` | Done | Reference-capture; env is a struct of pointers + stored `AllocHandle`; takes a bare allocator operand; conforms to `Drop` to free the env; inherits each captured reference's region | `emit-cfn` | Region inheritance makes escape-checking fall out of L1's existing sinks. A `cfn` capturing only `(ref …)` params/globals may be returned freely |
| L7 — Structural conformance derivation | Done | A closure/`fn` flowing into `&where ((P …) V)` gets a synthesized forwarding conformance by matching `invoke` against `P`'s single required method; bound args read off `invoke`'s signature | conformance registry; bare-`fn` types interned as `__fnty_N` | **Recognized set = {`UnaryFn`, `FoldFn`}** — resolved toward the narrow side of lambda.md's open question. Idempotent; obeys one-conformance-per-`(type,protocol)` coherence |
| L8 — C interop | Done | Public `defn` mentioning a closure env type (return or param) excluded from `--emit-cheader` (an `/* ... exposes a closure type ... */` comment is left) + warns at its definition; `fn`-pointer signatures emit normally | `cheader-mentions-closure` (`__vfn_env_` prefix match); the defn-definition warning | Detection by **name prefix** — the cheader path is pre-codegen (AST-only), so a `StructDef` flag would be invisible. Warning gated to public, non-synthesized defns |
| L9a — Examples / tests | Done | `examples/closures.nuc` (all four forms, each passed inline to `reduce`); `tests/fixtures/closure-escape.nuc` (L1 negative); `tests/fixtures/closure-cheader.nuc` (L8 omission + warning + fn-pointer emission) | `examples/closures.nuc`, `tests/expected/closures.out`, the two fixtures | 117 tests pass. Closures are passed inline because anonymous env types can't be named in a binding (see limitations) |
| L9b — Docs / progress | Done | `docs/special-forms.md` (closure rows + `invoke`-lowering note + sharpened escape two-concerns split), `docs/generics.md` (`Clone` + structural-conformance section), this file, `design/progress.md` Stage 13 row + narrative, lambda.md "Robot — implementation status" | (docs/progress only) | No code or test changes |

## Pre-existing limitations (not closure bugs)

These reproduce on the boot `bin/nucleusc` independent of Stage 13, and cap what
is runnable end-to-end (IR-level-verified-only cases noted). They are flagged for
future compiler work, **not** as Stage 13 defects:

1. ~~**By-value struct return/passing corrupts** via an `emit-struct-ret` ABI bug
   (store ptr / `sret` instead of memcpy) → an owning/`Drop` env struct can't
   round-trip by value through a binding or a return.~~ — **lifted by CE-3**
   (`emit-struct-ret` now branches on `TY-PTR` to copy bytes via typed load/store;
   the symmetric arg path in `emit-call-with-args` emits a first-class load when
   `ptype` is `TY-STRUCT` and the arg is `(ref same-struct)`).
2. ~~**`with-drop-method` only arms `Drop` for `TY-PTR` bindings** (the `ptr:Res`
   idiom), not struct-value bindings → a `with`-bound owning closure's synthesized
   `drop` does not fire at scope exit. The "mfn exported from `with`, drops at its
   eventual scope" case is **IR-level-verified only**.~~ — **lifted by CE-3**
   (`with-drop-method` generalized to `TY-STRUCT`: struct-value bindings drop at
   scope exit and struct-value `Drop` captures can be moved into an `mfn`; the
   `mfn`-export case is now runnable end-to-end).
3. ~~**Anonymous env types can't be named in `let`/`with`**~~ — **lifted by CE-1**
   (below). A bare-symbol `let`/`with` binding with no `:type` now infers its type
   from the init value, so a closure can be bound to a name and called,
   `with`-dropped, or passed by name to a combinator.

A POD `vfn`/`mfn` over scalars is **fully runnable** (non-owning by-value env, no
`Drop`, passed inline) — `examples/closures.nuc` exercises this. The
owning-closure mechanism (synthesized `drop`, env conformance, move disarm) is now
**fully runnable end-to-end** — `examples/ce3-owning-closure.nuc` exercises
by-value owning-struct return, struct-value `with`-drop, and `mfn`
move-of-struct-value-`Drop`-capture together. **Remaining gap:** a `defn`
returning a closure *object* errors "unknown type" (the anonymous `__vfn_env_N`
can't be spelled as a return type) — the CE-4 env-naming gap, not a CE-3 defect.

## Feature enhancements (closure-enhancements.md)

| # | Status | What landed | Key functions / files | Notes / surprises |
|---|---|---|---|---|
| CE-1 — Named closures (`let`/`with` env-type inference) | Done | A bare-symbol `let`/`with` binding with no spelled `:type` adopts the type of its emitted init value, so a capturing closure (whose anonymous env type cannot be written) can be **named** — then called by name, dropped at a `with`-scope via the existing `TY-PTR` `with-drop-method` path, or passed as a **named** operand to a generic combinator. | `emit-let`, `emit-with` (`nucleusc.nuc`); inert reuse of `extract-name-and-type`, `coerce-int-val` (self-coerce no-op), `derive-closure-conformance` (`generics.nuc`) | **Additive / byte-identical, no refresh.** Gated to bare symbols with `ty == null` — the exact case that previously errored "missing `:type`" — so typed/destructuring bindings are untouched and the path is **inert under self-compilation** (the compiler has no untyped bindings). To infer, the init is emitted **before** the slot alloca only in the inference case (`pre-v` holder), preserving `g-tmp` ordering for the typed path. Conformance is **type-keyed** (`derive-closure-conformance` keys off the env spelling + recorded `invoke`), so a named operand resolves identically to an inline one. `examples/named-closures.nuc` (+ `.out`), 120 tests |
| CE-2 — Mutable capture | Done | Special-cased `set!`/`inc!`/`dec!` on a captured name in `fn-rewrite-captures`: mode 0/1 rewrites to `(.set! self c ...)` (field store); mode 2 (cfn) rewrites to `(ptr-set! (. self c) ...)` (store through captured pointer). `inc!`/`dec!` expand to read-modify-write: `(.set! self c (op (. self c) 1))` / `(ptr-set! (. self c) (op (deref (. self c)) 1))`. Non-captured targets fall through to the unchanged generic rewrite. | `fn-rewrite-captures` (`nucleusc.nuc`) — new `set!`/`inc!+dec!` special cases; `examples/ce2-mutable-capture.nuc`; `tests/expected/ce2-mutable-capture.out` | **Additive / byte-identical, no refresh.** No existing closure in the compiler mutates a capture, so the new branches are inert under self-compilation. `inc!`/`dec!` inside `if` branches each have a nested `let`, so the closing paren count differs by 1 from the `set!` case — a subtle balance point to note. 121 tests |
| CE-3 — Owning-closure export (by-value return) | Done | Fix (b): `emit-struct-ret` (`abi.nuc`) branches on `TY-PTR` to copy bytes via typed `load`/`store` (MEMORY) or `load reg0[/+8 reg1]` (COERCE1/COERCE2) rather than storing the pointer; `emit-call-with-args` coercion loop emits a `load` to first-class when `ptype` is `TY-STRUCT` and the arg is `(ref same-struct)` so `abi-arg-frag` (left unchanged) classifies correctly. Fix (c): `with-drop-method` + `emit-with` replace the `TY-PTR`-only gate with a `cond` over `TY-PTR`/`TY-STRUCT`; the `TY-STRUCT` branch synthesizes a `(ptr S)` query type, allocates `%name.drophandle.N = alloca ptr` pointing at the value slot (handle is `Cleanup.slot`/`sym cslot`; value slot stays `sym ir-name` for reads), and reuses `emit-drop-cleanup`/`emit-move` verbatim — `owns=1` on the struct binding is also what lets `emit-move` consume a struct-value `Drop` capture into an `mfn`. `emit-addr-of` gains `(sym moved)` guard (mirrors `emit-symbol-ref`). | `emit-struct-ret` (`abi.nuc`); `emit-call-with-args`, `with-drop-method`, `emit-with`, `emit-addr-of` (`nucleusc.nuc`) | **Bootstrap byte-identical, no refresh** — all CE-3 changes are inert under self-compilation. **+2 tests** (123 total): `examples/ce3-owning-closure.nuc` (by-value owning-struct return from `make-res` + `mfn` moving a struct-value `Drop` binding), `tests/fixtures/ce3-use-after-move.nuc` (negative: `addr-of` of a moved binding rejected). Note: `type-size` returns pointer size for structs so typed load/store is used — LLVM computes the real byte count; no `llvm.memcpy` decl needed. **Known boundary (CE-4 gap):** a `defn` returning a closure *object* still errors "unknown type" (anonymous `__vfn_env_N` can't be spelled as a return type); the by-value ABI and move/drop machinery are complete. |
