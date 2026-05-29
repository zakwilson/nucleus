# Nucleus — Progress Summary

Current branch: `stage8-c-parity`

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
| Hardcoded `target triple = "x86_64-pc-linux-gnu"` removed — 8 emission sites route through `emit-output-module-target` / `emit-jit-module-target`; output module also gets `target datalayout` line for the first time | Done |
| `--target=<triple>` CLI flag — overrides output triple; JIT modules stay on host | Done (x86 backend only until Phase B) |
| Hardcoded `align 8` / `align 4` removed from all `load` / `store` / `alloca` emissions; LLVM now infers alignment from datalayout; `emit-load`/`emit-store` lost their unused `align:i32` parameter | Done |
| `size_t` / `ssize_t` / `ptrdiff_t` / `intptr_t` / `uintptr_t` resolved against `g-target.ptr-size` at C-header parse time | Done (`src/cheader.nuc`) |
| `type-size` for `TY-STRUCT` computes real ABI size via a layout walk over fields; `type-size` / `type-align` for `TY-PTR` use `g-target.ptr-size`/`ptr-align`; added `align-up` helper | Done |

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
| `abi-classify` + helpers (eightbyte classification → `byval`/`sret`/register coercion); only `TY-STRUCT` leaves the DIRECT path so scalar IR is byte-identical | Done |
| Wired the three coupled sites — `declare`, `emit-call` (arg coercion + sret/coerce return reconstruction), `defn` (signature + prologue param reconstruction + `emit-struct-ret`) | Done |
| `prescan-all-structs` (run once from `main`, recurses imports in dispatch order) so `defn` can take/return structs defined later or in imports; preserves redefinition precedence + type-stream order (bootstrap holds) | Done |
| Acceptance gate `tests/abi/` covers all 3 directions (Nucleus→C, C→Nucleus, Nucleus→Nucleus) vs system `cc`; folded into `make test` | Done |

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

---

## Deferred (needs design decision or blocked on above)

| Item | Blocker / Note |
|---|---|
| Polymorphic print/read (`def-print-method`) | Needs polymorphism mechanism |
| C header library as external `.so` | Separate from internal split already done |
| Stage 3c: unions, bit-fields, struct ABI, `long double`, `_Complex` | Deferred per `design/stage3c.md` |
| Lambda / closures | `design/stage999-future.md` |
| Map/reduce/filter | `design/stage999-future.md` |
| Polymorphism / protocol system | `design/stage999-future.md` |
| Vectors/hashes | `design/stage999-future.md` |
| Gensym reader macro | `design/stage999-future.md` |

---

## Known constraints / gotchas

- Variadic arithmetic macros now live in `lib/macros.nuc` and are auto-prepended via `lib/prelude.nuc`; binary primitives are `_+ _- _* _/`.
- Macro JIT names collide after sanitization if two macros share the same non-alphanumeric character; fixed by appending macro index (`__macro_<sanitized>_<index>`).
- REPL `defn` redefinition uses thunk indirection (`@foo` → load `@foo.tgt` → call `@foo.impl.<N>`) because pure resource-tracker swap leaves cross-module call sites with stale baked-in addresses. See `design/stage6-redefinition.md` "Result".
