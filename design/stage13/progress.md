# Stage 13 Progress: Lambdas and closures

Detailed task table for the L0–L9 lambda/closure implementation. Design:
[lambda.md](lambda.md); build order / acceptance gates: [lambda-prompt.md](lambda-prompt.md).
**117 tests pass; `make bootstrap` is a byte-identical fixed point.**

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

1. **By-value struct return/passing corrupts** via an `emit-struct-ret` ABI bug
   (store ptr / `sret` instead of memcpy) → an owning/`Drop` env struct can't
   round-trip by value through a binding or a return.
2. **`with-drop-method` only arms `Drop` for `TY-PTR` bindings** (the `ptr:Res`
   idiom), not struct-value bindings → a `with`-bound owning closure's synthesized
   `drop` does not fire at scope exit. The "mfn exported from `with`, drops at its
   eventual scope" case is **IR-level-verified only**.
3. **Anonymous env types can't be named in `let`/`with`** (no type inference for
   env types) → closures must be passed inline as combinator arguments; you can't
   bind one to a name and call it later.

A POD `vfn`/`mfn` over scalars is **fully runnable** (non-owning by-value env, no
`Drop`, passed inline) — that is what `examples/closures.nuc` exercises. The
owning-closure mechanism (synthesized `drop`, env conformance, move disarm) is
generated correctly and is exactly what `with-drop-method` would consult —
verified at the IR level.
