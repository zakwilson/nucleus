# Platform and ABI issues

#### Designer:

* Pointer size shouldn't be hardcoded. Targets could later include 32-bit machines, microcontrollers, etc....
* Add support for Mac OS and Windows including ABI support and build scripts. Defer testing, since this container is Linux.
* Create a test for struct ABI compatibility with C

#### Robot — questions / blockers before implementation:

##### Scope

1. **One stage or three?** Each item below is a substantial change. My
   suggestion: split into `platform-target.md` (target descriptor +
   pointer size), `platform-os.md` (macOS/Windows ABI + build), and
   `platform-struct-abi.md` (verification harness). They can ship
   independently. OK to split, or keep as one doc?

2. **Target matrix.** Which targets are in-scope for this stage vs.
   "design must allow but no implementation"? Plausible options:
   - In-scope build/run: `x86_64-pc-linux-gnu` (current).
   - In-scope code-emission only (untested): `x86_64-apple-darwin`,
     `aarch64-apple-darwin`, `x86_64-pc-windows-msvc`,
     `x86_64-pc-windows-gnu`, `i386-pc-linux-gnu`.
   - Out of scope until later: ARM Linux, microcontrollers (no libc).

   Which of these does "support" need to cover for stage 8?

##### Pointer size / target descriptor

3. **Where does target info live?** Currently the triple is a literal
   string in 6 places (`src/nucleusc.nuc:3882, 4116, 4910, 4946, 4952`
   and `src/repl.nuc:1187, 1204, 1265`) and pointer size is baked into
   `type-size` at `src/nucleusc.nuc:533` (returns 8 for `TY-PTR`).
   Proposal: a single `Target` struct (triple, ptr-size, ptr-align,
   `size_t`-kind, endianness, datalayout-string) populated once at
   startup, threaded through the few sites that need it. Acceptable?

4. **`size_t` kind.** Today `cheader.nuc:79` maps `size_t → ty-ui64`
   unconditionally. On 32-bit it must be `ty-ui32`. Should `size_t` /
   `ssize_t` / `ptrdiff_t` / `intptr_t` become target-dependent
   aliases resolved at C-header parse time, or new pseudo-types that
   resolve later?

5. **`align 8` literals.** The IR generator hard-codes `align 8` for
   pointer loads/stores (dozens of sites in `nucleusc.nuc` and
   `repl.nuc`). For correctness on a 32-bit target these become
   `align 4`. Two paths:
   - (a) Replace with a `(ptr-align)` helper that prints the current
     target's pointer alignment.
   - (b) Stop emitting explicit `align` on pointer ops and let LLVM
     default from the datalayout string.
   I lean (b) because it's a smaller diff and matches how LLVM IR is
   typically written. Preference?

6. **DataLayout string.** Nucleus emits no `target datalayout` line
   today; LLVM falls back to a default. For correct struct layout on
   non-x86_64 targets we must emit one matching the triple. OK to
   obtain it from LLVM (`LLVMCreateTargetData` / `LLVMCopyStringRepOfTargetData`)
   at startup rather than hand-rolling per-target tables?

7. **`type-size` for structs is wrong.** `nucleusc.nuc:537` returns 8
   for any `TY-STRUCT`, which is fine when the value is only used to
   stamp `align` on a pointer load (LLVM ignores it anyway), but
   would be wrong if anything ever uses it for sizeof or memcpy of a
   struct value. Worth fixing as part of this work, or leave alone if
   no callers actually need a real struct size? (I haven't audited
   every caller — this is a question, not a claim.)

##### macOS / Windows ABI + build

8. **ABI lowering scope.** System V (Linux/macOS-x86_64) classifies
   structs into integer/SSE/memory and splits across registers.
   Win64 always passes structs >8 bytes by hidden pointer.
   AArch64 (macOS-arm64) has its own HFA/HVA rules. Today Nucleus
   passes/returns whatever LLVM does by default with `byval`/`sret`
   absent — which is *not* ABI-correct for aggregates on any of
   these platforms once the struct gets non-trivial. Question:
   does this stage commit to emitting correct ABI lowering for
   aggregate parameters/returns, or is "scalar-only ABI" the
   stage-8 deliverable with aggregates left as a known gap? The
   former is a much larger change (essentially porting clang's
   `TargetInfo`/`ABIInfo` logic).

9. **Symbol prefix on macOS.** Mach-O prepends a leading underscore
   to C symbols. LLVM handles this from the datalayout's `m:` field,
   so if (6) is done correctly this should be free — but the JIT /
   `dlsym` path (`repl.nuc`) may need a symbol-name normalization
   helper. Worth confirming experimentally before committing to a
   design.

10. **Windows toolchain choice.** Two viable paths:
    - MSVC ABI: link with `link.exe` or `lld-link`, use `.obj`/`.exe`,
      need to handle import libraries for system DLLs.
    - MinGW (GNU ABI): link with `ld.bfd`/`lld`, much closer to the
      Linux flow, but users typically want MSVC for native Windows.

    My suggestion: target MSVC ABI via `lld-link`, ship a `.bat`
    bootstrap. Acceptable, or do you want both?

11. **Build scripts.** Current `Makefile` shells out to `llvm-config`
    and `clang`. Windows: no make by default, no `llvm-config` shell
    script. Options:
    - Keep make, document Win requires WSL or `make` from MSYS2.
    - Add a parallel `build.ps1` / `build.bat`.
    - Replace with CMake (cross-platform but heavier).

    I lean: keep make as-is, add a thin `build.ps1` that does the
    same steps. OK?

12. **C header parsing on macOS/Windows.** `clang -E` works
    everywhere, but the standard headers it pulls in differ wildly
    (`__darwin_size_t`, `__int64`, MS SAL annotations like `_In_`).
    Question: does this stage promise that `(include "stdio.h")`
    works on macOS/Windows, or is C interop only promised on Linux
    until a later stage? If the former, the parser needs work
    beyond ABI; that's a meaningful expansion of scope.

##### Struct ABI verification test

13. **Test mechanism.** Three viable approaches:
    - (a) **Generate-and-compare offsets at runtime.** For each
      struct under test, emit a Nucleus translation unit that prints
      `sizeof` and `offsetof` for each field; emit the equivalent C
      file and run it through `cc`; diff the two. Works on any
      platform with a C compiler. Catches size, alignment, and
      field order.
    - (b) **Generate `_Static_assert` C harness.** Have Nucleus emit
      a C file containing `_Static_assert(sizeof(...) == N, ...)`
      and `_Static_assert(offsetof(...) == N, ...)` lines using its
      own computed values, then compile it with `cc`. Compile-time
      failure = ABI mismatch.
    - (c) **Use LLVM's `DataLayout` API** directly to compute
      offsets, compare to Nucleus's internal computation. Doesn't
      involve a C compiler but only verifies Nucleus is consistent
      with LLVM, not with the platform C compiler.

    I lean (a): catches the most divergence, runs in CI. (b) is
    cleaner but only catches things expressible as constant
    expressions. Preference?

14. **Test corpus.** Which structs go in the test? Suggested:
    - Each primitive type alone in a one-field struct.
    - Mixed-size pairs (`{i8; i64}`, `{i32; i8}`, etc.) to exercise
      padding.
    - Nested structs and arrays-in-structs.
    - Anonymous structs (recently landed — `anon-struct-plan.md`).
    - A few real C library structs (`struct stat`, `struct timespec`,
      `struct sockaddr_in`) parsed via `--emit-cheader`.

    OK, or do you want a different cut?

15. **What does "fail" mean?** If the test detects a mismatch between
    Nucleus and the platform C compiler, what's the expected
    response — abort the build, warn, or just report? My suggestion:
    test failure = build failure, since ABI mismatch is silently
    catastrophic at the C boundary.

#### Designer

1. Keep one doc for now.

2. We should have code emission for `x86_64-apple-darwin`, `aarch64-apple-darwin`, `x86_64-pc-windows-msvc`, `x86_64-pc-windows-gnu`, `i386-pc-linux-gnu`, and ARM Linux. Testing on real hardware is out of scope.

3. A `Target` struct is fine for now.

4. Resolve at header parse time.

5. Let LLVM handle it based on the datalayout string.

6. Obtain the datalayout string from LLVM for now.

7. Fix `type-size` for structs.

8. Port clang's `TargetInfo`/`ABIInfo` at this stage.

9. Don't commit to a design at this stage.

10. Do both. It's essential that Nucleus be usable with an entirely open source toolchain, but it's also nice to support platform defaults.

11. Yes, offer both make and build.ps1

12. C interop should work for all platforms.

13. Test agaginst cc (option A)

14. That's adequate as an initial test.

15. Test failure is build failure.

---

## Phase A — Target descriptor foundation (done)

Landed in `stage8-c-parity`. Covers the groundwork everything else builds
on; all tests + bootstrap fixed-point hold on x86_64-linux.

* `Target` struct (triple/datalayout/ptr-size/ptr-align), populated from
  LLVM at startup via `LLVMGetDefaultTargetTriple` +
  `LLVMCreateTargetMachine` + `LLVMCreateTargetDataLayout` +
  `LLVMCopyStringRepOfTargetData` + `LLVMPointerSize`.
* Two descriptors: `g-host-target` (always native, used for every
  in-process JIT module — CT body, defmacro, REPL eval, trace/thunk) and
  `g-target` (used for the final batch IR + `compile-and-link`'s
  TargetMachine; honors `--target=<triple>`). Split avoids the
  "incompatible data layouts" JIT error when cross-compiling.
* `--target=<triple>` CLI flag. Only the X86 backend is registered today,
  so the override works for `x86_64-apple-darwin` / `x86_64-pc-windows-*`
  (datalayout / mangling differ correctly) but rejects e.g.
  `aarch64-*` until Phase B initializes more backends.
* Output module now emits a `target datalayout = "..."` line in addition
  to `target triple = "..."`. Sourced from LLVM rather than hand-rolled,
  so layout is correct for whichever target is selected.
* All hardcoded `align N` literals removed from `load` / `store` /
  `alloca` / global emissions (the one survivor is the `align 1` on the
  `[N x i8]` string constant, which is correct on every platform). LLVM
  fills alignment in from the datalayout. `emit-load` / `emit-store`
  dropped their now-unused `align:i32` parameter.
* `size_t` / `ssize_t` / `ptrdiff_t` / `intptr_t` / `uintptr_t` resolved
  against `g-target.ptr-size` at C-header parse time in
  `src/cheader.nuc`. (Note: `long` is still mapped unconditionally to
  64-bit — fixing it properly requires modeling the LP64 vs LLP64 vs
  ILP32 ABI per platform, deferred to Phase D.)
* `type-size` and new `type-align` are now target-aware: `TY-PTR` /
  `TY-FN` use `g-target.ptr-size` / `ptr-align`; `TY-STRUCT` walks
  fields with proper padding via the new `align-up` helper and returns
  the ABI size (was hardcoded `8`). All previous call sites that fed
  `type-size` into `align N` emissions were dropped during the align
  cleanup, so this is only used for future memcpy/sizeof scenarios.

### Carried into later phases

* **Phase B — multi-target backends.** Register
  `LLVMInitializeAArch64*` / `LLVMInitializeARM*` so `--target=aarch64-*`
  / `--target=arm-*` actually emit IR. Probably register all the
  initialized targets at startup; the cost is module init + a slightly
  larger binary.
* **Phase C — ABI lowering.** Today aggregate parameters / returns are
  passed by whatever LLVM defaults to with no `byval` / `sret`, which is
  not ABI-correct on any platform once aggregates appear in signatures.
  Port clang's `TargetInfo` / `ABIInfo` per item 8 above.
* **Phase D — cross-platform C interop.** `long`'s ABI model, plus
  `__darwin_size_t`, `_Bool` on MSVC, MS SAL annotations (`_In_`,
  `_Out_`), `__int64`. Currently `cheader.nuc` only knows the GNU/Linux
  flavor.
* **Phase E — struct ABI verification.** Generate-and-compare-against-cc
  harness from question 13(a).
* **Phase F — Windows build.** `build.ps1`, MSVC vs MinGW link path,
  `.bat` bootstrap.
