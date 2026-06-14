# Nucleus — Progress Summary

Current branch: `stage10-safety` (Stage 10 errors E1–E4 + safety flip + C1–C4 cleanup/niche)

---

## Done

### Stage 0–5 (complete)
- Stage 0: initial C-hosted compiler targeting LLVM IR
- Stage 1: self-hosting (compiler compiles itself)
- Stage 2: macros, `defmacro`/`gensym`/`funcall-ptr-1`, reader macros
- Stage 3a: libraries and linking
- Stage 3b: C interop — unsigned types, function pointers, C header parsing, `--emit-cheader`

### Stage 6 (all planned items done or deferred)
| Item | Status |
|---|---|
| Float literals (`f32`/`f64`, `+inf.0`/`-inf.0`/`+nan.0`, `fadd`/`fcmp`/`sitofp`/`fptrunc`, C interop) | Done |
| Readable REPL printing (NODE-STR/quoted short-circuit, `#<ptr 0x...>` fallback) | Done |
| `macroexpand` / `macroexpand-1` (REPL forms, optional depth arg) | Done |
| `macroexpand-all` (recursive descent through all subforms) | Done |
| Structured REPL error output (`--repl-format=text\|json`) | Done |
| Line-buffered REPL stdout (`setvbuf` in `repl-main`) | Done |
| N-ary arithmetic macros (`lib/varmath.nuc` → `lib/macros.nuc` via prelude) | Done |
| Extract REPL → `src/repl.nuc` (source-imported by `nucleusc.nuc`) | Done |
| Extract C header handling → `src/cheader.nuc` | Done |
| Move `lib/format.nuc` → `src/format.nuc`, `lib/llvm.nuch` → `src/llvm.nuch` | Done (`design/stage6-libs.md`) |
| Prelude (`lib/prelude.nuc`): auto-prepended to every compilation; `exclude-prelude` opt-out | Done (`design/stage6-libs.md`) |
| Binary primitives renamed `__+` → `_+` etc.; old `__ binops` removed | Done |
| Binary output (`--emit-binary` / `-o`), optimization flag (`-O`) | Done |
| Fix `macroexapnd1` typo | Done |
| `cond` intent / Emacs mode keywords | Done |
| Expressions as values: `cond`/`if` yield branch value; `do`/`let` yield last; `while` is `void`; `defn` implicit return | Done (`design/stage6-expressions.md`) |
| REPL function redefinition (thunk + ORC resource tracker; cross-module callers see new impl) | Done (`design/stage6-redefinition.md`) |
| `&rest` for `defn` (macro-style: cons list built at call site via `@make-cell`) | Done (`design/stage6-rest-optional.md`) |
| `&optional` for `defn` (defaults evaluated at call site, fixed-arity ABI) | Done (`design/stage7/optional.md`) |
| Pointer syntax: `*Node` → `(ptr Node)` / `ptr:Node` sugar; `*` syntax removed | Done (`design/stage6-pointer-syntax.md`) |
| Symbol interning: `(= 'foo 'foo)` is true; reader and `quote` share a process-global intern table; special-form dispatch uses identity instead of `strcmp` | Done (`design/stage6-symbols.md`) |

### Stage 8 Phase A — Target descriptor foundation
| Item | Status |
|---|---|
| `Target` struct (triple/datalayout/ptr-size/ptr-align) populated from LLVM at startup; `g-target` (output, --target-aware) and `g-host-target` (JIT, always host) globals | Done (`design/stage8/platform.md`) |
| Hardcoded `target triple = "x86_64-pc-linux-gnu"` removed — the output module emits `g-target`'s datalayout + `g-target-triple`, JIT modules emit `g-host-target`'s triple (the descriptor's fields are read inline at each emission site); output module also gets a `target datalayout` line for the first time | Done |
| `--target=<triple>` CLI flag — overrides output triple; JIT modules stay on host | Done (x86 backend only until Phase B) |
| Hardcoded `align 8` / `align 4` removed from most `load` / `store` / `alloca` emissions; LLVM infers alignment from datalayout | Done |
| `size_t` / `ssize_t` / `ptrdiff_t` / `intptr_t` / `uintptr_t` resolved against `g-target.ptr-size` at C-header parse time | Done (`src/cheader.nuc`) |
| `g-target-triple` / `g-target-ptr-bytes` descriptor drives `type-size` / `sizeof` / alignments for `TY-PTR`/scalars. (The struct ABI-size layout walk lives in Phase C's `abi-struct-size`; plain `type-size` returns the pointer-sized slot for a struct.) | Done |

### Stage 8 Phase B — multi-target backends
| Item | Status |
|---|---|
| `targets-init-all` registers X86 / AArch64 / ARM backends (Info/Target/TargetMC/AsmPrinter); both `target-init` and `jit-ensure-init` route through it | Done (`design/stage8/platform.md`) |
| `--target=<triple>` now resolves for the full matrix: `x86_64`/`i386`-linux, `x86_64`/`aarch64`-darwin, `x86_64`-windows-msvc/gnu, `aarch64`/`arm`-linux — each emits correct `target datalayout` (incl. 32-bit `p:32:32`) | Done |
| Cross-target emission regression test added to `tests/run-tests.sh` | Done |

### Stage 8 Phase C — ABI lowering (x86_64 System V)
| Item | Status |
|---|---|
| Diagnosed: struct-by-value C interop was ABI-broken even on x86_64 (no `byval`/`sret`/register coercion); `pair_sum`→3 not 7, 24-byte struct segfaulted | Done |
| Reverse-engineered clang 19 x86_64 SysV coercion table + classification rules (`design/stage8/platform.md`) | Done |
| `abi-classify` + helpers (`abi-struct-size`/`abi-struct-align` layout walk, eightbyte classification → `byval`/`sret`/register coercion); only `TY-STRUCT` leaves the DIRECT path so scalar IR is byte-identical | Done (reimplemented onto the stage 9 refactor during the merge) |
| Wired the three coupled sites — `declare` (`emit-nuch-declare-import`), `emit-call-with-args` (arg coercion via `abi-arg-frag` + `sret`/coerce return reconstruction via `abi-emit-struct-call`), `defn` (signature via `abi-print-param`/`abi-ret-ir` + prologue reconstruction via `abi-emit-param-prologue` + `emit-struct-ret`) | Done |
| Acceptance gate `tests/abi/` covers all 3 directions (Nucleus→C, C→Nucleus, Nucleus→Nucleus) vs system `cc`; folded into `make test` | Done |
| `prescan-all-structs` (whole-unit struct layout registration so a `defn` can take/return a struct defined *later* or in an import) | Deferred — by-value struct params/returns require definition-before-use (holds for the gate + the compiler, which passes only pointers) |

### Stage 8 Phase D — `long` data model
| Item | Status |
|---|---|
| C `long`/`unsigned long` resolve per target data model via `target-long-size` (ILP32 + LLP64/Windows → 32-bit, LP64 → 64-bit); was hardcoded 64-bit | Done |
| `c-parse-type` tracks `long` count so `long` vs `long long` differ (`long long` always 64-bit) | Done |
| `long-abi-*` regression test (4 targets) in `tests/run-tests.sh`; host (LP64) output unchanged so bootstrap holds | Done |
| Remaining cross-platform interop (macOS/MSVC header flavors: `__darwin_size_t`, MSVC `_Bool`, SAL `_In_`/`_Out_`, `__int64`) | Deferred (needs SDK headers to test) |

### Stage 8 Phase E — struct layout verification
| Item | Status |
|---|---|
| `tests/layout/` harness (q13a option a): shared `structs.h` imported by `layout.nuc` and `#include`d by `layout.c`; diffs Nucleus `sizeof`/field-offset vs platform `cc` over the q14 corpus (primitives, mixed-size padding pairs, nested + anonymous struct fields, timespec-shaped, mixed record) | Done (`design/stage8/platform.md`) |
| Wired into `make test` (gates the build) and `make layout-test`; mismatch = build failure | Done |
| Root-cause parser fix surfaced by the harness: implicit-int `short` (`short` ≡ `short int`) was mis-parsed in `c-parse-type` (declarator consumed as base type → struct silently skipped); now peeks past `short` like `long`. Bootstrap unaffected | Done (`src/cheader.nuc`) |

### Stage 8 Phase F — Windows build
| Item | Status |
|---|---|
| `build.ps1` — PowerShell mirror of the Linux build (shim → ensure-boot → self-host → link); `-Toolchain mingw` (default, open-source: `x86_64-pc-windows-gnu`, clang+LLD, `--export-all-symbols`) and `-Toolchain msvc` (`x86_64-pc-windows-msvc`, clang→link.exe/lld-link); `-Bootstrap`/`-UpdateBootstrap`/`-Clean`. Byte-clean stdout via `Start-Process` (avoids PS 5.1 UTF-16 BOM) | Done (`design/stage8/platform.md`) |
| `bootstrap.bat` — cmd.exe wrapper over `build.ps1 -Bootstrap` (prefers `pwsh`) | Done |
| Committed Windows boot IR (`boot/nucleusc-x86_64-windows-{gnu,msvc}.ll`), cross-emitted on Linux, `llvm-as`-validated; `make windows-boot` regenerates them and `make update-bootstrap` keeps all boot flavors in lock-step | Done |
| Boot IR is ABI-clean on Win64 (compiler's own IR has zero real aggregate-by-value), so it bootstraps despite Win64 ABI lowering not being ported | Verified |
| Win64 aggregate ABI at the C boundary; REPL symbol export under MSVC; on-hardware testing | Deferred (untestable on Linux host) |

### Stage 9 — Polymorphism (`design/stage9/polymorphism.md`)
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

### Stage 9 cleanup (`design/stage9/cleanup.md`)
| Item | Status |
|---|---|
| `case` macro (`lib/macros.nuc`); applied to `emit-nuch-header`, `emit-nuch-import-forms`, `fprint-node`, `emit-toplevel-forms`; `examples/case.nuc` | Done |
| Error attribution: `stamp-macro-lines` propagates the macro call-site line onto line-0 quasiquote nodes; shadowing errors use the form-cell line | Done |
| Name (non-)shadowing: one symbol = one kind, checked at every top-level definer; fixed `i64`/`double` self-shadows | Done |
| i64 hardcoding: target descriptor (`g-target-triple` / `g-target-ptr-bytes`) + host `ptr-bytes`; `sizeof`/`type-size`/triple parameterized. Remaining: `emit-qq-helpers` Node ABI | Done (qq-helper ABI deferred) |

### Stage 10 unions & tagged sums (`design/stage10/unions.md`)
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

### Stage 10 error handling (`design/stage10/errors.md`, `errors-prompt.md`)
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

---

## Deferred (needs design decision or blocked on above)

| Item | Blocker / Note |
|---|---|
| Polymorphic print/read (`def-print-method`) | Now expressible via Stage 9 multimethods/protocols |
| C header library as external `.so` | Separate from internal split already done |
| Stage 3c: bit-fields, `long double`, `_Complex` | Deferred per `design/stage3c.md`; unions done (stage 10), struct ABI done (stage 8) |
| Lambda / closures | `design/stage999-future.md` |
| Map/reduce/filter | `design/stage999-future.md` |
| Polymorphism / protocol system | Done — Stage 9 (`design/stage9/polymorphism.md`) |
| `dyn`, parametric generics (nested tyvars), `defcast` tier | Deferred — see `design/stage9/` §11 / `callable-values.md` |
| Vectors/hashes | `design/stage999-future.md` |
| Gensym reader macro | `design/stage999-future.md` |

---

## Known constraints / gotchas

- Variadic arithmetic macros now live in `lib/macros.nuc` and are auto-prepended via `lib/prelude.nuc`; binary primitives are `_+ _- _* _/`.
- Macro JIT names collide after sanitization if two macros share the same non-alphanumeric character; fixed by appending macro index (`__macro_<sanitized>_<index>`).
- REPL `defn` redefinition uses thunk indirection (`@foo` → load `@foo.tgt` → call `@foo.impl.<N>`) because pure resource-tracker swap leaves cross-module call sites with stale baked-in addresses. See `design/stage6-redefinition.md` "Result".
