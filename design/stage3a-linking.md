# Linking and C Interop


#### Designer:

Now that Nucleus has libraries, it needs to be able to compile .o linkable object files and .so dynamically linkable object files. There should be a compiler flag for generating header files in addition to the compiled code.

There should be a separate cheader clibrary and the additional option to output a C-compatible header. The library should also read C headers. `include` should transition to this instead of hardcoded tables.

Invoking clang in the makefile for linking is appropriate at this stage.

#### Robot:

This breaks down into three largely independent workstreams: **output modes** (`.o` / `.so` emission), **C header generation**, and **C header consumption** (replacing the hardcoded libc tables). They share a dependency on a `.nuch` header format, which was already sketched in stage3-libraries.md.

**Output modes (`.o` and `.so`).** The compiler currently emits textual LLVM IR to stdout. Producing object files means piping that IR through LLVM's backend. Two approaches:

1. **Shell-level pipeline** — `nucleusc foo.nuc | llc -filetype=obj -o foo.o`. This already works today and just needs a driver flag or Makefile target. For `.so`, add `-reloc-model=pic` to `llc` and `-shared` to the final `clang` link.

2. **In-process via LLVM C API** — The compiler already links against LLVM for the JIT. Adding `LLVMTargetMachineEmitToFile` would let it produce `.o` directly without shelling out. This is more self-contained but adds significant API surface (target triple setup, pass pipeline, etc.).

Recommendation: start with approach 1 via Makefile targets and a thin shell wrapper (`nuc build foo.nuc -o foo.o`). The LLVM C API approach can come later if eliminating the `llc` dependency matters.

**C header generation.** As noted in stage3-libraries.md, this is a mechanical translation from `.nuch` declarations to C types. The type mapping is 1:1 for primitives (`i32` → `int32_t`, `i64` → `int64_t`, `ptr` → `void*`, `i8` → `int8_t`). Struct types map to C structs with the same field layout. Function pointers need care — Nucleus `(fn (i32 ptr) i64)` maps to `int64_t (*)(int32_t, void*)`.

A compiler flag `--emit-cheader` is simpler than a separate tool, since the compiler already has all the type infrastructure loaded. It can reuse `type-to-ir` patterns but emit C syntax instead of LLVM IR syntax.

**C header consumption (replacing `include`).** This is the most impactful change. The current `emit-include` / `init-libc` system is ~70 lines of hardcoded `add-libc` calls with a fixed-width parameter encoding (up to 4 params, no struct types, no function pointer params). Replacing it with actual C header parsing means:

1. **Minimal C header parser.** Full C parsing is a non-goal — the parser only needs to handle: `typedef`, function declarations, struct definitions, `#define` integer constants, and `extern` variable declarations. Ignoring: preprocessor conditionals (`#ifdef`), macros with bodies, inline functions, C++ features. The parser reads a `.h` file and produces the same internal representation that `add-libc` currently builds.

2. **Migration path.** The existing `init-libc` table stays functional while the C parser is built. Once the parser can handle the libc headers the compiler actually uses (stdio, stdlib, string, ctype, unistd), the hardcoded table can be removed. The LLVM C API declarations are trickier — those headers are complex. A pragmatic approach is to provide a hand-written `llvm-orc.nuch` file for the LLVM functions rather than trying to parse the real LLVM headers.

3. **System header location.** The parser needs to find system headers. On Linux, `/usr/include` is standard. A `--sysroot` flag or `C_INCLUDE_PATH` env var handles non-standard locations. For cross-compilation this matters; for bootstrapping on the dev machine it's straightforward.

**Linking via clang.** The Makefile currently runs `llc` then `clang` for linking. This is already the right shape. The changes needed are:
- A `lib` target that builds `.o` files from `lib/*.nuc`
- A `shared` target that builds `.so` with `-fPIC` / `-shared`
- Correct `-L` / `-l` flags for linking Nucleus libraries
- An install target that puts `.so`, `.h`, and `.nuch` files in the right places

**`.nuch` generation.** The compiler needs a `--emit-nuch` flag that outputs the S-expression header instead of (or in addition to) LLVM IR. This walks the same top-level forms but emits declarations instead of definitions — function signatures, struct definitions, constants, and macro source. The macro source must be the *unexpanded* form, since macros are source-level transforms.

**Risks and open questions:**

- **C header parsing scope.** How much of C's declaration syntax needs to be supported? Function pointers as parameters, `const`, `volatile`, anonymous structs, bitfields — each adds complexity. A pragmatic subset that handles the headers Nucleus actually uses (libc + a curated LLVM subset) is more realistic than a general-purpose C parser.

- **ABI compatibility.** Nucleus structs must match C struct layout for interop. The compiler currently lays out structs sequentially, which matches C for simple cases but may diverge on padding/alignment for mixed-size fields. This needs verification against `clang -fdump-record-layouts`.

- **Variadic functions.** The libc table already marks variadic functions. The C header parser needs to recognize `...` in parameter lists and propagate this to the internal representation. The compiler's call emission must continue using the correct LLVM `call` vs variadic call convention.

#### Designer:

YAGNI, worse is better, etc.... Simpler approaches are preferred here, except that users of the language will expect to be able to use any C library. Correctness is therefore required when it comes to C interop.

## Completion criteria

This stage is complete when Nucleus can do all of the following:

* Output a .o object file and .h header which a C program can `include` and link to
* Output a .so shared object file and .h header which a C program can `include` and dynamically link to
* Output a .nuch header for the above
* Link using clang as a linker in the Makefile
* `include` a C header and use its library functions
* `import` a .nuch header and use its functions and macros

### Pre-implementation

#### Robot:

**Order of implementation.** Dependencies dictate the sequence. `.nuch` generation is the foundation — multiple features depend on having a header format.

1. **`--emit-nuch` flag.** Add a compiler mode that walks top-level forms and emits `.nuch` S-expression headers instead of LLVM IR. This captures function signatures (`declare`), struct definitions (`defstruct`), constants (`defconst`), and macro source (`defmacro`). Test by round-tripping: compile a library to `.nuch`, then `(import foo)` using the `.nuch` file and verify the program links and runs correctly.

2. **`.o` output via Makefile.** Add targets for compiling `.nuc` → `.ll` → `.o`. This is just plumbing around existing tools (`nucleusc` + `llc`). Add a `lib/*.o` build rule. Test by building `lib/arena.nuc` as a `.o` and linking it into a test program.

3. **`.so` output.** Extend the `.o` targets with PIC compilation and shared linking. Add an `install` target. Test by building a shared library from a Nucleus source file and dynamically linking it from a C program.

4. **`--emit-cheader` flag.** Translate `.nuch` (or internal compiler state) to C `.h` syntax. The type mapping is mechanical. Test by generating a header from a Nucleus library, including it from a C program, and verifying the types match.

5. **Minimal C header parser.** This is the largest piece. Parse a subset of C declaration syntax sufficient for libc headers: function declarations, struct definitions, typedefs, `extern` variables, `#define` integer constants. The parser produces the same internal `LibcDecl`-style representation.

6. **Replace `init-libc` with parsed headers.** Switch `(include stdio)` from the hardcoded table to actually reading `/usr/include/stdio.h` (or a curated subset). Keep the LLVM declarations as a hand-written `.nuch` file. Remove `init-libc` and `add-libc` once all includes use the parser.

7. **`.nuch` import in `import`.** Extend the existing `(import foo)` to check for `foo.nuch` when `foo.nuc` is not found. Process declarations (emit `declare` in IR), register macros for JIT, but skip function bodies. The linker resolves symbols from the corresponding `.o` / `.so`.

**Bootstrap considerations.** Steps 1-4 add new compiler flags and Makefile targets — no changes to the language or bootstrap needed. Step 5 (C parser) is new Nucleus code that can be developed as a library (`lib/cheader.nuc`). Step 6 changes how `include` works internally but keeps the same user-facing semantics, so the bootstrap needs updating only after the cutover. Step 7 extends `import` semantics and requires a bootstrap update.

**What can be deferred.** The C header parser (steps 5-6) is the riskiest and least urgent piece. The hardcoded libc table works fine for now. Steps 1-4 and 7 deliver the core value: Nucleus libraries that are compilable, linkable, and consumable from both Nucleus and C.
