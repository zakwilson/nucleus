# Stage 10 Progress

Status: **done** — back to [../progress.md](../progress.md)

---

## Stage 10 unions & tagged sums (`design/stage10/unions.md`)

| Item | Status |
|---|---|
| U1: untagged `(union ...)` — `TY-UNION`, max-size/max-align layout, anon memoization (`__anon_union_h<hex>`), deferred IR type defs (`drain-pending-union-irs`) | Done |
| U1: C header import of `union {...}` fields / named unions / `typedef union` (stage-3c skip lifted); cheader + `.nuch` export; SysV `abi-classify` merge over members at offset 0 | Done |
| U1: layout corpus (`tests/layout/`) extended with union cases vs the C oracle | Done |
| U2: `defunion` (monomorphic) — `{tag:i32, payload:union}` backing struct, generated `Union-arm` constructors, `make`, no raw tag/payload access outside `match` | Done |
| U2: `match` — exhaustiveness (compile error naming the missing arm), `case`/`switch` lowering, value-expression join, by-value binders, `(ref x)` in-place binders (pointer scrutinee), `defenum` scrutinee freebie | Done |
| U2: Drop rule (§7) — owning `with` binding of a union with Drop-conforming arm payloads rejected unless the union itself conforms to Drop | Done (v1 reject; tag-switch drop later) |
| U3: templates — `(defunion (Result T E) ...)`, explicit-instance `make`, memoized stamping, `.nuch` verbatim export + importer-side stamping | Done |
| U3: return-position target typing (§5c) — bare `(ok v)`/`(err e)` against the declared return type | Done (direct return form only) |
| U4: niche layout rules (`?T`/`!T` as layout instances), `:repr` | Done (C4: union-layout-classify → LAYOUT-NICHE-MAYBE rule 2 + LAYOUT-NICHE-ERRPTR rule 3 + niche lowering via `union-target-rewrite`; `examples/errptr.nuc`; `layout` test gate) |
| REPL: `defunion` definition + constructor declares in preamble; lazily-emitted union type defs drained into the preamble (libc preload, `include`, `import`) | Done |
| Examples/tests: `examples/unions.nuc`, `tests/repl/unions.in` | Done |

## Stage 10 error handling (`design/stage10/errors.md`, `errors-prompt.md`)

| Item | Status |
|---|---|
| E1: `Err` builtin scalar (`TY-ERR`, i32-repr, distinct for type-eq/mangling/handler-keying) | Done |
| E1: `deferror` — compile-time `Err` constant + descriptor table (dense ids from 1, cap 4095), emitted at module assembly only when errors are used (byte-identical otherwise); `.nuch` verbatim export | Done |
| E1: `err-name` / `err-message` — descriptor-table accessor intrinsics (GEP+load by element type; no count needed at the call site) | Done (compiler intrinsic, not a library fn — cross-module static-data coupling; see errors.md impl notes) |
| E1: `(Result T E)` moved to the prelude; `!T` / `!?T` / `?!T` type sugar in `parse-type-name` (`!` takes payload as written) | Done (`?!T` stamps once value-`Maybe` lands in E2) |
| E1: signature prescan resolves imported (prelude) types — `prescan-imported-types` walks the import tree before `prescan-defn-signatures`, so `!T`/`Node` parse in `defn` signatures (nullability.md §9 friction 2, pulled forward) | Done |
| E1: `try` propagation macro (`lib/error.nuc`, `(import error)`); `err!` unconditional-error opt-out (= `err` until E3) | Done |
| E1: `unwrap` / `unwrap-or` extended to `Result` operands (`unwrap` prints `err-name`/`err-message` then traps; needs `printf` in scope) | Done |
| E1: examples/tests — `examples/errors.nuc` | Done |
| E2: value `(Maybe T)` over non-pointers (prelude template; `(Maybe (ref T))` stays niche, `(Maybe T)` stamps `{tag,T}`); `match`/`make`/return-target-typing (incl. bare `none`); `?!T` sugar (value Maybe over a Result) | Done (`examples/value-maybe.nuc`) |
| E3: handler-aware `err` + `with-handler` + handler chain (`lib/error.nuc`) keyed on (error, repair-type); `(err E detail)`; CL unbind rule | Done (compiler-emitted `__err-handled` at `!T` err return sites via `union-target-rewrite`; handler call rides the Stage-8 struct-return ABI through `abi-emit-struct-call`; gated on the error lib being in scope so the compiler self-compiles byte-identically; `examples/handlers.nuc`) |
| E4: adopt `!T` at `die-at` sites (reader, coercion); shrink REPL `repl_throw` boundary | Done for the reader (`lib/reader.nuc`: `lex-*`/`next-tok`/`peek-tok`/`eat-tok`/`read-form`/`read-list`/`read-program` now return `!ptr`; every reader `die-at` → `report-at` + `(err! parse-error)`, internal calls propagate via `try`; diagnostics byte-preserved since `report-at` still prints path:line at the fault site. Batch driver uses a `read-program-or-die` wrapper (`exit 1` on err); REPL `match`es and recovers, so a syntax error is a value path, not a stale-`jmp_buf` longjmp. `die-at` stays the panic tier; no codegen change so the fixed point held with no converge round. `make test` 71/71, `make bootstrap` fixed point, boot re-converged.) Coercion-path adoption (the `pkind-flow-check` abort) deferred — larger cascade through the emitter. |
| Phase F: safety flip — `(ptr T)` non-null, `(raw T)` nullable, `?` uniform `(Maybe T)` | Done (5 parser edits flip the singleton + `(ptr T)` to PTR-REF and `null` to `raw`; `pkind-flow-check` exempts elem-less `void*` destinations — non-null is only meaningful on typed pointers, the direct analogue of the CStr refinement — so the flip's teeth land on `(ptr T)`/`(ref T)` slots; `addr-of`/`.&`/`alloca`/`array`/compound-literal now yield `ref`; all `?Foo` pointer-Maybes re-spelled `?ptr:Foo`, value-operand `?` stamps value-`Maybe`. `make test` 71/71, `make bootstrap` fixed point, boot re-converged. `noreturn die-at` was already landed at Stage-1.) |
| A2 (Stage 10 Phase C4) niche-encoded `!T` / `:repr` (union-layout-classify + ENUM/TAGGED/NICHE/ERRPTR rules) | Done (full niche encoding: MAYBE `None` → null, ERRPTR `Err` → `(i32)-1`; `:repr` tags in defunion; layout harness extended) |
| C1: N2 cold-site cleanup — ~25 nullable-launder `cast ptr:Sym` in cold emitter paths replaced with `?ptr:Sym` + existing null-guards; enabled by `noreturn die-at` (Phase F1) | Done (2026-06-14; two deliberate hold-outs: E3 `err-find-handler`/`g-handler-top` lookups, non-null by precondition; see nullability.md §9 finding 5) |
| C2: standalone `signal` — `(signal E RepairType [detail])` special form; walks handler chain via shared `emit-handler-call`; returns `(Maybe RepairType)` without return-position requirement | Done (2026-06-14; `examples/signal.nuc`) |
| C3: panic-tier hook — `unwrap`/`unwrap-or` on `Result` signal `unhandled-error` before aborting; gated on `error-lib-in-scope` + `unhandled-error` in scope | Done (2026-06-14; no-op when no handler bound) |
