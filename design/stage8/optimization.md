# Optimization

A C program converted to Nucleus runs as fast with `nucleusc -O3` as `clang -O0` while optimized clang is nearly 3x faster. Nucleus will need to catch up.

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
