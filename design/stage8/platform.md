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
  `src/cheader.nuc`. (`long`'s data model was handled later, in Phase D.)
* `type-size` and new `type-align` are now target-aware: `TY-PTR` /
  `TY-FN` use `g-target.ptr-size` / `ptr-align`; `TY-STRUCT` walks
  fields with proper padding via the new `align-up` helper and returns
  the ABI size (was hardcoded `8`). All previous call sites that fed
  `type-size` into `align N` emissions were dropped during the align
  cleanup, so this is only used for future memcpy/sizeof scenarios.

## Phase B — multi-target backends (done)

Landed in `stage8-c-parity`. Registers every backend Nucleus can emit for
so `--target=<triple>` resolves instead of erroring at
`LLVMGetTargetFromTriple`.

* New `targets-init-all` helper expands the static-inline
  `LLVMInitializeAll*` macros by calling the per-target entry points
  directly for X86, AArch64, and ARM (Info / Target / TargetMC /
  AsmPrinter each). Declarations added to `src/llvm.nuch`.
* Both registration sites — `target-init` (output path) and
  `jit-ensure-init` (in-process JIT) — now route through
  `targets-init-all`. It is idempotent; whichever runs first wins.
* Covers the full Phase-B target matrix: `x86_64`/`i386` (X86),
  `aarch64` (AArch64), `arm` (ARM) — Linux, Darwin, and Windows
  (msvc/gnu) triples all emit IR with the correct `target datalayout`
  obtained from LLVM. 32-bit triples (`i386`, `arm`) correctly produce
  `p:32:32` layouts and 4-byte pointer sizing.
* `tests/run-tests.sh` gained a cross-target emission guard: each triple
  in the matrix must emit IR carrying its own `target triple` line.
* The native (host) target is still what the JIT uses; cross-target only
  affects the final batch IR / object emission, so JIT data-layout
  compatibility is preserved.

The required LLVM backends (AArch64, ARM, X86) are all present in a
standard LLVM build (`llvm-config --targets-built`); no LLVM rebuild is
needed.

## Phase C — ABI lowering (x86_64 System V: done)

Landed in `stage8-c-parity`. Struct-by-value parameters and returns now
follow the platform C ABI on x86_64 System V, verified against the system
`cc` in all three directions (Nucleus→C, C→Nucleus, Nucleus→Nucleus) by
`tests/abi/` — now gating in `make test`. Bootstrap fixed-point and all 50
tests pass.

What was implemented (see the spec below for the algorithm):

* **`abi-classify`** + helpers (`abi-mark-eightbytes`, `abi-eightbyte-reg`,
  `abi-return-ir`, `abi-struct-name`) implementing the SysV eightbyte
  classification and coercion-type rules. Only `TY-STRUCT` is ever
  non-`DIRECT`, so every scalar/pointer path is byte-identical to before.
* **`declare`** lowers aggregate params/returns to `byval` / `sret` /
  register coercion.
* **`emit-call`** coerces struct arguments (materialize → load reg(s), or
  `byval` pointer copy) and reconstructs struct returns (read back from the
  `sret` slot, or round the coercion value through memory). Shared
  `arg-frag` / `abi-append-struct-arg` helpers; scalar arg formatting is
  unchanged.
* **`defn`** emits the ABI signature (shared `emit-abi-param`; leading
  `sret` param when MEMORY), reconstructs struct params into their `.addr`
  slot in the prologue (or binds the `byval` pointer directly), and routes
  both `return` and the implicit tail return through `emit-struct-ret`
  (sret store / register coercion). The current function's return `AbiInfo`
  and sret name live in `g-fn-ret-abi` / `g-fn-sret-name`.
* **`prescan-all-structs`** (run once from `main`, recursing imports in
  dispatch order via `prescan-import-structs`) registers every struct
  before defn signatures are prescanned, so a function may take/return a
  struct defined later in the unit or in an import. emit-defstruct is
  idempotent, so dispatch-order redefinition precedence (and the
  type-stream output) is unchanged — bootstrap holds.

Carried forward: the non-x86_64 ABIs (Win64, AArch64 AAPCS, ARM AAPCS,
i386 cdecl) plug in behind `abi-classify` keyed on `g-target`, deferred
until host-testable. Bit-fields / `long double` / `_Complex` / unions
remain out of scope per `design/stage3c.md`.

### The bug (now fixed)

Nucleus emits aggregate parameters and returns as first-class LLVM
values with no `byval` / `sret` and no register coercion — e.g.
`declare i32 @pair_sum(%Pair)` and `call i32 @pair_sum(%Pair %t8)`. That
is **not** the platform C ABI. clang lowers the same signatures per its
`TargetInfo`/`ABIInfo`, and LLVM does not reconstruct the C ABI from a
by-value aggregate on its own. Result: struct-by-value interop is broken
**even on the host (x86_64-linux)**. Empirically (verified this stage):

```
pair_sum({3,4})  -> 3     (want 7)     ; wrong register
big_sum(24-byte) -> garbage / segfault ; MEMORY class mishandled
```

This is the primary deliverable of item 8 ("port clang's
TargetInfo/ABIInfo").

### Acceptance gate

`tests/abi/` + `tests/run-abi-test.sh` (also `make abi-test`; folded into
`make test` per item 15, mismatch = build failure). Three directions:

* **Nucleus→C** and **Nucleus→Nucleus** — `interop.nuc` (Nucleus caller)
  links against `clib.c` (C callee, system `cc`) and also calls its own
  `nuc_*` struct functions.
* **C→Nucleus** — `driver.c` (C caller) links against `callee.nuc`
  (Nucleus-defined struct functions), exercising the defn-side ABI.

Output is diffed against `expected.out` (an all-C reference). Covers small
INTEGER-class coercion (`pair_*`), an INTEGER eightbyte containing a float
(`mixed_get`), and the >16-byte MEMORY case (`big_*`, byval + sret).

### x86_64 System V coercion (reverse-engineered from clang 19)

Per-eightbyte classification, then a coercion type per eightbyte:

| struct (x86_64)          | size | clang lowering          |
|--------------------------|------|-------------------------|
| `{i8}`                   | 1    | `i8`                    |
| `{i8,i8}`                | 2    | `i16`                   |
| `{i8,i8,i8}`             | 3    | `i24`                   |
| `{i32}`                  | 4    | `i32`                   |
| `{i32,i8}`               | 5    | `i64`                   |
| `{i32,i16}`              | 6    | `i64`                   |
| `{i64}`                  | 8    | `i64`                   |
| `{i64,i8}`               | 9    | `i64, i8`               |
| `{i64,i16}`              | 10   | `i64, i16`              |
| `{i64,i32}`              | 12   | `i64, i32`              |
| `{i64,i32,i8}`           | 13   | `i64, i64`              |
| `{i64,i64}`              | 16   | `i64, i64`              |
| `{i64,i64,i64}`          | 24   | `ptr byval(%T)` (MEMORY)|
| `{double}`               | 8    | `double`                |
| `{double,double}`        | 16   | `double, double`        |
| `{float,float}`          | 8    | `<2 x float>`           |
| `{float,float,float}`    | 12   | `<2 x float>, float`    |
| `{float}`                | 4    | `float`                 |
| `{i32,float}`/`{float,i32}` | 8 | `i64` (INTEGER wins)    |
| `{double,i64}`           | 16   | `double, i64`           |

Derived rules:

1. **Whole struct > 16 bytes → MEMORY.** Param: `ptr byval(%T) align A`.
   Return: `sret` — hidden first param `ptr sret(%T) align A`, function
   returns `void`, caller allocates the result slot. (Also MEMORY if a
   field is unaligned, but Nucleus aligns everything naturally, so skip.)
2. **≤ 16 bytes → 1 or 2 eightbytes**, each classified by the fields that
   overlap it (recurse into nested structs by absolute offset; Nucleus
   has no array-in-struct fields). Per eightbyte:
   - any integer/pointer field overlaps → **INTEGER**;
   - else any `f64` → **SSE/double**;
   - else `f32` only → **SSE/float**.
3. **Coercion type per eightbyte** holding `n` bytes (`n = min(8, size −
   8·k)`):
   - INTEGER: `i(8·n)` for `n ≤ 4`, else `i64`. (`i8/i16/i24/i32/i64`.)
   - SSE/double: `double`.
   - SSE/float: `<2 x float>` when `n == 8`, else `float`.
4. **Return type:** one eightbyte → that reg type; two → the anonymous
   struct `{T0, T1}` (built with `insertvalue`); MEMORY → `void` + sret.

This is machine-ABI compatible with clang (data lands in the same
GPR/XMM registers). The narrow integer widths (`i24`, etc.) also keep
loads from reading past the struct's storage.

### Codegen plan (the three sites are coupled)

`emit-call`, the `defn` emitter, and the `declare` emitter must change
**together** — there is one ABI, used uniformly, so a Nucleus caller and
a Nucleus callee agree (changing only one breaks Nucleus↔Nucleus struct
calls, which work today only because both currently use LLVM's default).

* **Classifier** — `abi-classify(type) -> AbiInfo{kind, reg0, reg1}` with
  `kind ∈ {DIRECT, MEMORY, COERCE1, COERCE2}`. Only `TY-STRUCT` is ever
  non-`DIRECT`, so every scalar/pointer path is untouched. Eightbyte
  marking reuses the Phase-A layout walk (`type-size`/`align-up`) for
  field offsets.
* **Shared signature printer** — emits the param list + return for both
  `declare` and `defn` from `AbiInfo` (byval/sret attributes, coercion
  types, the leading sret param).
* **`emit-call`** — for each struct arg: COERCE → `load`(s) of reg
  type(s) from the arg's storage, passed positionally; MEMORY → pass a
  pointer to a caller-owned copy with `byval`. For a struct return:
  COERCE → receive the reg value, `store` to a temp, hand back a Val
  whose storage is that temp; MEMORY → `alloca` a result slot, pass it as
  the leading `sret` arg, hand back that slot.
* **`defn`** — signature via the shared printer; **prologue** reconstructs
  each struct param into its `%name.addr` slot (COERCE: `store` the reg
  args at the right offsets; MEMORY: the `byval` pointer *is* the slot, so
  bind it directly), preserving today's "struct param ref = load from
  `.addr`" behavior. Stash the function's return `AbiInfo` in a global so
  returns can see it.
* **Return** — both `emit-return` and the implicit tail return route
  struct returns through one helper: COERCE → `store` the value to a
  temp, `load` the reg type(s), `ret` the reg / `{T0,T1}`; MEMORY →
  `store` to the `sret` pointer, `ret void`.

### Scope / deferrals

* This phase's codegen targets **x86_64 System V** (the only
  host-verifiable ABI; `make abi-test` runs against the system `cc`).
* **Win64** (structs > 8 bytes always by hidden pointer; ≤ 8 coerced to
  one integer), **AArch64 AAPCS** (HFA/HVA, ≤ 16 in regs else byref),
  **ARM AAPCS**, and **i386 cdecl** (all aggregates on the stack) plug in
  behind the same `abi-classify` dispatch, selected on `g-target`.
  Deferred until they can be tested (no host).
* Bit-fields, `long double`/`_Complex`, and unions remain out of scope
  per `design/stage3c.md`.
* The bootstrap is unaffected: `nucleusc.nuc` passes every aggregate by
  pointer, so the fixed-point test never exercises this path — `make
  abi-test` is the real gate.

## Phase D — `long` data model (done)

Landed in `stage8-c-parity`. C `long` / `unsigned long` now resolve to the
right width for the configured target's data model, instead of always
64-bit:

* **`target-long-size`** (`src/cheader.nuc`) returns 4 for ILP32
  (`g-target.ptr-size == 4`: i386, armv7) and for LLP64 (Windows x64,
  detected via `"windows"` in the triple), 8 for LP64 (Linux/macOS
  x86_64/aarch64).
* `c-parse-type` now tracks the `long` *count* (0 / 1 / 2) instead of a
  flag, so `long` and `long long` are distinguished; `long long` is always
  64-bit. `long double` is still skipped.
* On the host (LP64) `long` → i64 exactly as before, so the bootstrap is
  unchanged.
* Tested in `tests/run-tests.sh` (`long-abi-*`): a header with
  `long`/`long long`/`unsigned long` functions is parsed under four
  targets and the emitted declares checked (LP64 → i64; ILP32 & LLP64 →
  i32 for `long`, i64 for `long long`).

Carried forward (the rest of cross-platform C interop): macOS/MSVC header
*flavors* — `__darwin_size_t`, `_Bool` on MSVC, MS SAL annotations
(`_In_`, `_Out_`), `__int64`. `cheader.nuc` still assumes GNU/Linux system
headers; these need the corresponding SDK headers to test, so they're
deferred.

## Phase E — struct layout verification (done)

Landed in `stage8-c-parity`. Adds the field-offset/size half of ABI
verification (question 13(a), option (a) — generate-and-compare against the
platform `cc`); the calling-convention half was already covered by Phase C's
`tests/abi/`.

* `tests/layout/structs.h` is the single source of truth for the corpus
  (question 14): every primitive alone in a one-field struct; mixed-size
  pairs in both orders (`{i8;i64}`, `{i32;i8}`, `{i8;i32}`, `{i16;i64}`,
  `{i8;i16;i8}`, `{i64;i8}`) for padding/tail-padding; a named nested
  struct by value (`Outer{Inner; char}`); an anonymous inline struct field;
  a timespec-shaped struct; and a larger mixed record. It is **imported** by
  `tests/layout/layout.nuc` and **`#include`d** by `tests/layout/layout.c`,
  so both sides verify the *same* structs with no two-language drift.
* `layout.nuc` prints `sizeof` (Nucleus's `type-size` walk) and per-field
  byte offsets — computed as `(cast i64 (.& p field)) - (cast i64 p)` — for
  each struct; `layout.c` prints the identical lines via `sizeof` /
  `offsetof`. `tests/run-layout-test.sh` diffs them; a mismatch is a build
  failure (question 15). Wired into `make test` and exposed as
  `make layout-test`.
* Arrays/unions/bitfields stay out of scope: the C-header parser skips a
  struct containing one (registers it as opaque `ptr`), and `defstruct` has
  no array field type — consistent with the documented limitation.
* **Parser fix surfaced by this harness:** a bare `short` field (implicit-int
  `short` ≡ `short int`) was mis-parsed — `c-parse-type` set `is-short` and
  then consumed the *declarator name* as the base type, yielding `null` and
  silently skipping the whole struct (and equally breaking any `short`-returning
  declaration). `c-parse-type` now peeks past `short` exactly as it does for
  `long`: if `int` doesn't follow, `short` itself is the base type. Fixed at
  the root in `src/cheader.nuc`; bootstrap unaffected (the compiler's own
  headers never used implicit-int `short`, so no previously-successful parse
  changed).

### Carried into later phases

* **Phase F — Windows build.** `build.ps1`, MSVC vs MinGW link path,
  `.bat` bootstrap.
