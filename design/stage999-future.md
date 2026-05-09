# Future plans

Nothing here is fleshed out. Some ideas may be bad. Things here may never be implemented, or may be impossible.

## Lispiness

Nucleus is a replacement for C, but it should bring in as much Lisp goodness as it can without compromising C interop or adding runtime overhead.

### Lambda

Obviously

### Map/reduce/filter

Ideally polymorphic

### Polymorphism in general

With static typing and compile-time dispatch, this should have no runtime cost. I'm imagining a protocol/interface system in addition to concrete types

### Redefinition

The ability to redefine vars and fns in the REPL would be helpful. We don't have dynamic scope and probably shouldn't add it, so that implies recompiling everything depending on the var in question. The time to do that is acceptable, but the implementation complexity may not be.

### Closures

Lexical closures are a huge win for abstraction. Representing them in C may be tricky, but maybe there's a workaround or a way to give C a limited interface. Lifecycle could also be tricky.


### Gensym reader macro

Probably `#`, semantics like Clojure but not the postfix syntax

## Data structures

### Vectors and hashes as part of the language

Clojure uses these well. Not included by default at runtime of course, but good general-purpose implementations people would want to import if they don't need something purpose-built.

### defcall

Probably a subset of polymorphism. In Clojure, many things that are not fns in the traditional sense can be called as fns.

A type should be a cast (and maybe this should rely on defcast, or maybe it should be a new mechanism allowing destructive operations). A struct should be field access.

## Editor integration

Local Emacs interaction (eval-from-buffer, completion, jump-to-definition,
describe, macroexpand, REPL plumbing over `nucleusc -i`) landed in stage 7
— see `design/stage7/interaction-mode.md` and `docs/emacs.md`. Other
editors (VS Code, neovim) and any network protocol are deferred.

## Cleanup

`set!` should take multiple pairs like `let`.

`addr-of` probably needs a reader macro

`defvar` only accepts integer literals, wat?

## Memory management

The `with` form (added in stage6) is `let` plus auto-free for any binding
whose init expression is a libc allocator (`malloc`/`calloc`/`realloc`/`strdup`,
including through `cast`). Cleanups fire on fall-through and on early `return`
inside the body. Disarming a single binding is done by storing `null` to it,
since `free(NULL)` is a no-op.

Open question: whether to flip the default so plain `let` itself auto-frees,
with `let*` as the opt-out (the original shape proposed here). `with` exists
alongside `let` for now; revisit once it has wider use.

## Optimization

A C program converted to Nucleus runs as fast with `nucleusc -O3` as `clang -O0` while optimized clang is nearly 3x faster. Nucleus will need to catch up.

Most likely lack of optimizations in the Nucleus compiler — and specifically a structural one, not a translation issue.

Look at docs/builtins.md for -O:
  
  ▎ -O0/-O1/-O2/-O3 … LLVM backend codegen optimization level. 
  
  That's the codegen pipeline (instruction selection / register allocation / scheduling). It is not the LLVM middle-end optimizer — the pass manager that runs mem2reg,         
  instcombine, LICM, GVN, the loop unroller, and crucially the LoopVectorize / SLPVectorize passes. nucleusc parses its IR and goes straight to LLVMTargetMachineEmitToFile, so
  none of those passes run. 
  
  Concretely, that means relative to clang -O3 the Nucleus build is missing: 
  
  - mem2reg — every let/set!/inc! stays as alloca+load+store in the loop. pi, i, x all round-trip through stack slots each iteration.                                           
  - LICM — the (cast f64 (bit-and i 1)) and the 2*i-1 sub-expression aren't hoisted/strength-reduced as aggressively.                                                         
  - LoopVectorize — the whole point of the i & 0x1 trick in the C source is to give the vectorizer a closed-form alternating sign so it can SIMD the loop. Without the          
  middle-end pipeline that pass never fires, so you're running scalar fadd/fdiv on each iteration while the C version is doing 4× or 8× wide vector ops.
  
Secondary contributors (smaller effect):
  
  - The IR Nucleus emits for fadd/fmul/fdiv doesn't carry fast-math flags (fast, reassoc, nsz, etc.). Even with the full opt pipeline, an FP reduction like pi += … won't vectorize without reassoc because reordering changes results. clang -O3 alone also doesn't set these — you only get FP-reduction vectorization with -ffast-math/-Ofast — so if your C build used -Ofast, that's an additional gap on top of the missing middle-end.
  - rounds being a global (same in both versions) forces a reload on the loop test unless the optimizer proves no aliasing; again, that's a middle-end job that isn't running on
   the Nucleus side.
   
The translation itself and the language's expressiveness aren't the problem — the IR shape is fine. The gap is that nucleusc -O3 isn't the same animal as clang -O3; it's     
  closer to "clang -O0 with a good register allocator."                                                                                                                       
                                                        
