# Stage 8 Progress

Status: **done** — back to [../progress.md](../progress.md)

---

## Stage 8 Phase A — Target descriptor foundation

| Item | Status |
|---|---|
| `Target` struct (triple/datalayout/ptr-size/ptr-align) populated from LLVM at startup; `g-target` (output, --target-aware) and `g-host-target` (JIT, always host) globals | Done (`design/stage8/platform.md`) |
| Hardcoded `target triple = "x86_64-pc-linux-gnu"` removed — the output module emits `g-target`'s datalayout + `g-target-triple`, JIT modules emit `g-host-target`'s triple (the descriptor's fields are read inline at each emission site); output module also gets a `target datalayout` line for the first time | Done |
| `--target=<triple>` CLI flag — overrides output triple; JIT modules stay on host | Done (x86 backend only until Phase B) |
| Hardcoded `align 8` / `align 4` removed from most `load` / `store` / `alloca` emissions; LLVM infers alignment from datalayout | Done |
| `size_t` / `ssize_t` / `ptrdiff_t` / `intptr_t` / `uintptr_t` resolved against `g-target.ptr-size` at C-header parse time | Done (`src/cheader.nuc`) |
| `g-target-triple` / `g-target-ptr-bytes` descriptor drives `type-size` / `sizeof` / alignments for `TY-PTR`/scalars. (The struct ABI-size layout walk lives in Phase C's `abi-struct-size`; plain `type-size` returns the pointer-sized slot for a struct.) | Done |

## Stage 8 Phase B — multi-target backends

| Item | Status |
|---|---|
| `targets-init-all` registers X86 / AArch64 / ARM backends (Info/Target/TargetMC/AsmPrinter); both `target-init` and `jit-ensure-init` route through it | Done (`design/stage8/platform.md`) |
| `--target=<triple>` now resolves for the full matrix: `x86_64`/`i386`-linux, `x86_64`/`aarch64`-darwin, `x86_64`-windows-msvc/gnu, `aarch64`/`arm`-linux — each emits correct `target datalayout` (incl. 32-bit `p:32:32`) | Done |
| Cross-target emission regression test added to `tests/run-tests.sh` | Done |

## Stage 8 Phase C — ABI lowering (x86_64 System V)

| Item | Status |
|---|---|
| Diagnosed: struct-by-value C interop was ABI-broken even on x86_64 (no `byval`/`sret`/register coercion); `pair_sum`→3 not 7, 24-byte struct segfaulted | Done |
| Reverse-engineered clang 19 x86_64 SysV coercion table + classification rules (`design/stage8/platform.md`) | Done |
| `abi-classify` + helpers (`abi-struct-size`/`abi-struct-align` layout walk, eightbyte classification → `byval`/`sret`/register coercion); only `TY-STRUCT` leaves the DIRECT path so scalar IR is byte-identical | Done (reimplemented onto the stage 9 refactor during the merge) |
| Wired the three coupled sites — `declare` (`emit-nuch-declare-import`), `emit-call-with-args` (arg coercion via `abi-arg-frag` + `sret`/coerce return reconstruction via `abi-emit-struct-call`), `defn` (signature via `abi-print-param`/`abi-ret-ir` + prologue reconstruction via `abi-emit-param-prologue` + `emit-struct-ret`) | Done |
| Acceptance gate `tests/abi/` covers all 3 directions (Nucleus→C, C→Nucleus, Nucleus→Nucleus) vs system `cc`; folded into `make test` | Done |
| `prescan-all-structs` (whole-unit struct layout registration so a `defn` can take/return a struct defined *later* or in an import) | Deferred — by-value struct params/returns require definition-before-use (holds for the gate + the compiler, which passes only pointers) |

## Stage 8 Phase D — `long` data model

| Item | Status |
|---|---|
| C `long`/`unsigned long` resolve per target data model via `target-long-size` (ILP32 + LLP64/Windows → 32-bit, LP64 → 64-bit); was hardcoded 64-bit | Done |
| `c-parse-type` tracks `long` count so `long` vs `long long` differ (`long long` always 64-bit) | Done |
| `long-abi-*` regression test (4 targets) in `tests/run-tests.sh`; host (LP64) output unchanged so bootstrap holds | Done |
| Remaining cross-platform interop (macOS/MSVC header flavors: `__darwin_size_t`, MSVC `_Bool`, SAL `_In_`/`_Out_`, `__int64`) | Deferred (needs SDK headers to test) |

## Stage 8 Phase E — struct layout verification

| Item | Status |
|---|---|
| `tests/layout/` harness (q13a option a): shared `structs.h` imported by `layout.nuc` and `#include`d by `layout.c`; diffs Nucleus `sizeof`/field-offset vs platform `cc` over the q14 corpus (primitives, mixed-size padding pairs, nested + anonymous struct fields, timespec-shaped, mixed record) | Done (`design/stage8/platform.md`) |
| Wired into `make test` (gates the build) and `make layout-test`; mismatch = build failure | Done |
| Root-cause parser fix surfaced by the harness: implicit-int `short` (`short` ≡ `short int`) was mis-parsed in `c-parse-type` (declarator consumed as base type → struct silently skipped); now peeks past `short` like `long`. Bootstrap unaffected | Done (`src/cheader.nuc`) |

## Stage 8 Phase F — Windows build

| Item | Status |
|---|---|
| `build.ps1` — PowerShell mirror of the Linux build (shim → ensure-boot → self-host → link); `-Toolchain mingw` (default, open-source: `x86_64-pc-windows-gnu`, clang+LLD, `--export-all-symbols`) and `-Toolchain msvc` (`x86_64-pc-windows-msvc`, clang→link.exe/lld-link); `-Bootstrap`/`-UpdateBootstrap`/`-Clean`. Byte-clean stdout via `Start-Process` (avoids PS 5.1 UTF-16 BOM) | Done (`design/stage8/platform.md`) |
| `bootstrap.bat` — cmd.exe wrapper over `build.ps1 -Bootstrap` (prefers `pwsh`) | Done |
| Committed Windows boot IR (`boot/nucleusc-x86_64-windows-{gnu,msvc}.ll`), cross-emitted on Linux, `llvm-as`-validated; `make windows-boot` regenerates them and `make update-bootstrap` keeps all boot flavors in lock-step | Done |
| Boot IR is ABI-clean on Win64 (compiler's own IR has zero real aggregate-by-value), so it bootstraps despite Win64 ABI lowering not being ported | Verified |
| Win64 aggregate ABI at the C boundary; REPL symbol export under MSVC; on-hardware testing | Deferred (untestable on Linux host) |
