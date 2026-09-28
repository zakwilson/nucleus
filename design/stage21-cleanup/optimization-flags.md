# Optimization flags restored (`-O1+` pipeline, `-ffast-math`, `-Ofast`, `-march=native`)

**Status:** built 2026-09-28.

## What was wrong

`docs/compiler.md` documented `-Ofast`, `-ffast-math` and `-march=native`, and
said `-O1`+ runs LLVM's middle-end pipeline. None of it was true: the three
flags died `unknown flag`, and `-O3` only set the backend `CodeGenOptLevel`.
On the Leibniz-π benchmark (`../leibniz`, 10⁹ terms) `nucleusc -O3` ran in
2.78 s, the same as `-O0` and as `clang -O0`. `clang -Ofast -march=native`
ran in 0.26 s, roughly 10× faster.

All four came in with [stage8/optimization.md](../stage8/optimization.md)
(commit `965ed6e6`, on `stage8-c-parity`). They were lost in merge `f065de8a`,
when that branch was merged onto the refactored stage-9 compiler and the ABI
work was reimplemented from spec. Nothing removed them on purpose: no commit
touches them, and no design document argues against them. The `LLVMRunPasses`
and `LLVMGetHostCPU*` declarations survived in `src/llvm.nuch` without a
caller.

## The fast-math "conflict" does not apply to them

Every later reference to fast-math is about the **compiler process**:

- Stage 15 W2d took `-ffast-math` off the Makefile's link line for
  `build/nucleusc`. `crtfastmath.o` sets FTZ/DAZ for the whole process, and
  the compiler folds float literals with host FP, so `1e-45` folded to 0
  ([stage15-stress-test/literal-typing.md](../stage15-stress-test/literal-typing.md),
  `context/conventions.md`).
- `float-literal-fits` and `global-init.md` §3/§4 inherit that constraint.

A user-facing `-ffast-math` only needs fast-math flags on the **output**
module's instructions. That does not touch the compiler's FP environment, so
it leaves the constraint intact, with one condition: the flags must not reach
JIT'd compile-time bodies, which run in the compiler process.

## Design

All three pieces live in `compile-and-link`, after `LLVMParseIRInContext` and
before `LLVMTargetMachineEmitToFile`:

1. **`-march=native`**: `LLVMGetHostCPUName` / `LLVMGetHostCPUFeatures`
   replace the target descriptor's cpu/features. The flag is refused with
   `--target=` (exit 2).
2. **`-ffast-math`** (`set-module-fast-math`): walk every instruction and set
   `LLVMFastMathAll` wherever `LLVMCanValueUseFastMathFlags` allows. Stage 8
   did this in the emitter instead, and only on the five binops. The
   post-parse walk is better on three counts:
   - `--emit-llvm` is byte-identical with or without the flag, so the
     bootstrap fixed point cannot move.
   - JIT modules never pass through `compile-and-link`, so the compiler
     process stays strict IEEE by construction rather than by a guard.
   - It covers everything clang's `-ffast-math` flags (`fneg`, `fcmp`, FP
     `phi`/`select`/calls), which makes it an actual equivalent.

   The cost of flagging `fcmp` is that `nnan` makes a NaN self-test unreliable,
   the same as in C.
3. **`-O1`+** (`run-opt-pipeline`): `LLVMRunPasses(mod, "default<ON>", tm)`,
   then `rehome-folded-bss`, which is the one new interaction since stage 8.
   On ELF, `write-ir-section` names each global's section in the IR, and
   `global-section-prefix` picks `.bss` from the initializer *at emit time*. A
   runtime-initialized global (W8 G-3) is zero then. GlobalOpt's static-ctor
   evaluator later folds `@__nucleus_init`'s store into its initializer. That
   leaves a non-zero initializer in an SHT_NOBITS section, which fails emission
   (`SHT_NOBITS section '.bss.h-init' cannot have fixups`,
   `examples/fnptr-global.nuc` at `-O2`). clang avoids this because
   `-fdata-sections` names sections after optimization; the C API has no such
   switch. So after the pipeline, any `.bss.X` global with a non-null
   initializer moves to `.data.X`.

`-Ofast` is `-O3 -ffast-math`. Unlike clang's, it does not link
`crtfastmath.o`. Vectorizing a reduction does not need FTZ/DAZ, and flushing
denormals is a process-wide effect the user should ask for by name, with
`--link-arg=-ffast-math`.

## Measured (Ryzen 7 PRO 6850U, LLVM 19, 10⁹ terms)

| build | Nucleus | clang (C) |
|---|---|---|
| `-O3` | 1.07 s | 1.05 s |
| `-Ofast` | 0.55 s | 0.53 s |
| `-Ofast -march=native` | 0.27 s | 0.27 s |

Before the fix, Nucleus `-O3` took 2.78 s. The ported benchmark itself had no
performance defect. Its `--emit-llvm` output, fed to `clang -O3` after `sed`
added `fast` flags, matched C at every level before any compiler change.

## Gates

- `make test`: **1214 / 0 / 0**. New units:
  - `s21-ofast-vectorizes-fp-reduction`: packed `divpd` under `-Ofast`,
    none under `-O3`, output checked by value
    (`tests/fixtures/s21-fp-reduction.nuc`);
  - `s21-march-native-refuses-target`;
  - `s21-optimized-ctor-fold-leaves-bss`.
- `make bootstrap`: **PASS**. `--emit-llvm` is untouched by every flag, so
  the compiler's `.ll` is unchanged and no boot refresh was needed.
- All 160 golden examples pass at `-O0`, `-O2`, `-O3`, `-Ofast` and
  `-Ofast -march=native`. Before the `.bss` fix, `fnptr-global` failed at
  every optimized level.
- The compiler built by its own `-O2` pipeline
  (`nucleusc -O2 src/nucleusc.nuc --link-arg=…`) emits byte-identical IR for
  itself.
- `scripts/cstr-allowlist.txt`: +2 `CStr` sites, both LLVM strings (the
  pipeline error and `LLVMGetSection`).

## Found, not fixed

Float `!=` lowers to `fcmp one`, the *ordered* not-equal. So `(!= x x)` is
false for a NaN at every opt level, while C's `!=` (`fcmp une`) says true.
The comparison table is at `src/nucleusc.nuc` (`"!=" "fcmp one"`).
