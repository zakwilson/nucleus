# Stage 9 Progress

Status: **done** — back to [../progress.md](../progress.md)

---

## Stage 9 — Polymorphism (`design/stage9/polymorphism.md`)

| Item | Status |
|---|---|
| Rung 1: overloaded `defn` multimethods — `g-generics` registry, mangling, resolver, prescan, `.nuch` `defmethod` | Done (§9.7) |
| Rung 2: `defprotocol` / `extend` — `g-protocols` / `g-conformances`, checked code-free conformance | Done (§9.7) |
| Rung 3: non-emitting `node-type` pass (shared with `emit-node`, no drift) | Done (§9.7) |
| Rung 4: bounded generic `defn` (`&where`, named tyvars), monomorphizer, A2 def-time check | Done (§9.7) |
| §10.1: resolution tiers — widen + untyped-int-literal adaptation in the shared resolver | Done (§11) |
| §10.3: operators as ordinary generic functions; inline peephole; user operator overloading; `Num`/`Eq`/`Ord` (`lib/numeric.nuc`); protocol-on-protocol `(extend Ord Eq)` | Done (§11) |
| §10.1: blanket protocols `Any` / `Struct` (`g-blanket`, automatic/structural conformance) | Done (§11) |
| §10.2: `Valid` inferred structural bound (per-call-site non-emitting stamp; derived values) | Done (§11) |
| Callable values (`callable-values.md`): non-function head → `get` (Struct member-access intrinsic, byte-identical to `.`, overridable) / `invoke` (user-supplied, `Seq`/`Call`); computed-symbol field access (homogeneous); arbitrary-expression heads + `funcall` folding | Done (`callable-values.md` impl status) |
| Examples: `overload`, `protocol`, `generic`, `operators`, `blanket`, `valid`, `callable` | Done |

## Stage 9 cleanup (`design/stage9/cleanup.md`)

| Item | Status |
|---|---|
| `case` macro (`lib/macros.nuc`); applied to `emit-nuch-header`, `emit-nuch-import-forms`, `fprint-node`, `emit-toplevel-forms`; `examples/case.nuc` | Done |
| Error attribution: `stamp-macro-lines` propagates the macro call-site line onto line-0 quasiquote nodes; shadowing errors use the form-cell line | Done |
| Name (non-)shadowing: one symbol = one kind, checked at every top-level definer; fixed `i64`/`double` self-shadows | Done |
| i64 hardcoding: target descriptor (`g-target-triple` / `g-target-ptr-bytes`) + host `ptr-bytes`; `sizeof`/`type-size`/triple parameterized. Remaining: `emit-qq-helpers` Node ABI | Done (qq-helper ABI deferred) |
