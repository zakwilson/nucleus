# Optimization

#### Designer

A C program converted to Nucleus runs as fast with `nucleusc -O3` as `clang -O0` while optimized clang is nearly 3x faster. Nucleus will need to catch up.

#### Robot

Most likely lack of optimizations in the Nucleus compiler — and specifically a structural one, not a translation issue.

Look at docs/builtins.md for -O:
  
  ▎ -O0/-O1/-O2/-O3 … LLVM backend codegen optimization level. 
  
  That's the codegen pipeline (instruction selection / register allocation / scheduling). It is not the LLVM middle-end optimizer — the pass manager that runs mem2reg, instcombine, LICM, GVN, the loop unroller, and crucially the LoopVectorize / SLPVectorize passes. nucleusc parses its IR and goes straight to LLVMTargetMachineEmitToFile, so none of those passes run.  Concretely, that means relative to clang -O3 the Nucleus build is missing: 
  
  - mem2reg — every let/set!/inc! stays as alloca+load+store in the loop. pi, i, x all round-trip through stack slots each iteration.
  - LICM — the (cast f64 (bit-and i 1)) and the 2*i-1 sub-expression aren't hoisted/strength-reduced as aggressively.
  - LoopVectorize — the whole point of the i & 0x1 trick in the C source is to give the vectorizer a closed-form alternating sign so it can SIMD the loop. Without the middle-end pipeline that pass never fires, so you're running scalar fadd/fdiv on each iteration while the C version is doing 4× or 8× wide vector ops.
  
Secondary contributors (smaller effect):
  
  - The IR Nucleus emits for fadd/fmul/fdiv doesn't carry fast-math flags (fast, reassoc, nsz, etc.). Even with the full opt pipeline, an FP reduction like pi += … won't vectorize without reassoc because reordering changes results. clang -O3 alone also doesn't set these — you only get FP-reduction vectorization with -ffast-math/-Ofast — so if your C build used -Ofast, that's an additional gap on top of the missing middle-end.
  - rounds being a global (same in both versions) forces a reload on the loop test unless the optimizer proves no aliasing; again, that's a middle-end job that isn't running on the Nucleus side.
   
The translation itself and the language's expressiveness aren't the problem — the IR shape is fine. The gap is that nucleusc -O3 isn't the same animal as clang -O3; it's closer to "clang -O0 with a good register allocator."

----

● User answered Claude's questions:
  ⎿  · What was the C reference (the ~3x-faster build) compiled with? This sets the parity target. → -O3 (no fast-math)
     · How much should this task cover? → Pipeline + fast-math + native width
     · How should native CPU/vector width be handled? → Add opt-in -march=native (Recommended)

#### Implementation (done)

The diagnosis held exactly. Three changes, all confined to the object/binary
emission path (`compile-and-link`) — `--emit-llvm` is untouched, so the
self-host fixed-point check is unaffected:

1. **Middle-end pass pipeline.** `compile-and-link` now runs
   `LLVMRunPasses(mod, "default<O`N`>", tm, opts)` (new PassBuilder C API, LLVM
   19) between IR parse and `LLVMTargetMachineEmitToFile`, gated on `-O1+`.
   `default<O3>` bundles mem2reg, instcombine, LICM, GVN, LoopVectorize, and
   SLPVectorize. `g-opt-level` still also feeds the backend `CodeGenOptLevel`.
   The PassBuilder symbols are already in the linked `libLLVM-19.so`, so no
   Makefile change was needed — only `declare`s in `src/llvm.nuch`.

2. **Fast-math** (`-ffast-math`, and `-Ofast` = `-O3 -ffast-math`). FP
   arithmetic emits a `fast` flag (`fadd fast`, `fdiv fast`, …); comparisons are
   left unflagged. This is what unlocks reassociation of the `pi += …`
   reduction so it can vectorize. clang `-O3` alone doesn't do this either — it
   needs `-Ofast`/`-ffast-math` — so this is the piece that closes the gap on
   the specific benchmark.

3. **`-march=native`.** `LLVMCreateTargetMachine` is given the host CPU and
   feature string (`LLVMGetHostCPUName` / `LLVMGetHostCPUFeatures`) instead of
   the generic baseline, so vectorized loops use the widest available registers
   (AVX `ymm` rather than SSE2 `xmm`). Generic stays the default so objects
   remain portable. Host-only — not for use with `--target=`.

Measured on the Leibniz-pi benchmark (2×10⁸ terms, branchless alternating sign):

| build | time | vs -O0 |
|-------|------|--------|
| `-O0` | 0.60 s | 1.0× (stack-bound allocas, scalar) |
| `-O3` | 0.21 s | 2.9× (mem2reg → registerized scalars) |
| `-O3 -ffast-math -march=native` | 0.057 s | 10.6× (4-wide AVX `vaddpd`/`vdivpd` reduction) |

`-O3` alone reproduces the ~3× that was the original parity target (matching a C
`-O3` baseline); fast-math + native width is an opt-in extra that goes past it.
Disassembly confirms each layer: `-O0` spills locals to the stack each
iteration, `-O3` keeps them in registers, and the fast build emits packed
256-bit FP ops with interleaved accumulators.
