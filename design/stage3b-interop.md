# C interop

#### Designer:

YAGNI, worse is better, etc.... Simpler approaches are preferred here, except that users of the language will expect to be able to use any C library, and to make everything but macros available to C users. Correctness is therefore required when it comes to C interop.

#### Robot:

Stage 3a delivered `.nuch` headers, `.o` object files, and `.nuch` import. What remains for C interop is:

1. **`--emit-cheader`** — generate a C `.h` from a Nucleus source file
2. **`.so` shared object** — Makefile target for shared libraries
3. **C header consumption** — replace the hardcoded `init-libc` table with actual header parsing
4. **LLVM declarations** — move the LLVM ORC/JIT declarations to a hand-written `.nuch` file

### Questions and comments for the designer

**1. Scope of C header parsing.** The stage3a document proposes a minimal C parser that handles function declarations, structs, typedefs, `#define` integer constants, and `extern` variables. Real system headers are complex — they use preprocessor conditionals (`#ifdef`), GNU extensions (`__attribute__`), platform-specific typedefs (`size_t` via `__SIZE_TYPE__`), and deeply nested `#include` chains.

Two practical approaches:

- **Curated shim headers.** Write simplified `.h` files (e.g. `include/libc/stdio.h`) that declare only what Nucleus needs, in clean C syntax the parser can handle. Users who need additional C functions add declarations to these shims or write their own. This is what many language FFIs do (Zig, Nim's older c2nim).

- **Shell out to `clang -E`.** Run the C preprocessor on the real header to get a flat, expanded declaration stream with no `#ifdef` or macros. Parse that. This handles platform differences automatically but means the parser must handle the full expanded output (which includes a lot of noise from transitive includes).

Which approach do you prefer? The curated shim approach is simpler and more predictable. The `clang -E` approach is more correct but requires a more robust parser.

**2. Type mapping ambiguities.** C's `int` is 32-bit on x86-64 Linux but the mapping isn't always this clean. Specific questions:

- `size_t` / `ssize_t` — map to `i64` unconditionally (correct on x86-64, wrong on 32-bit)?
- `unsigned` types — Nucleus doesn't have unsigned integers. Should `unsigned int` map to `i32` (same bit width, different semantics) or should the compiler warn/error?
- `enum` — map to `i32`?
- `void*` vs typed pointers — Nucleus has a single `ptr` type, so all pointer types collapse. This is fine for ABI but loses type safety. Is that acceptable for now?

**3. Struct layout and ABI.** The compiler currently lays out structs sequentially. C structs have platform-specific padding and alignment rules (e.g. an `i32` followed by an `i64` gets 4 bytes of padding on x86-64). Options:

- Add alignment/padding logic to the Nucleus compiler to match the C ABI. This is the correct long-term solution.
- Use `__attribute__((packed))` in generated C headers to match Nucleus's sequential layout. This is fragile and breaks interop with existing C libraries that use natural alignment.
- Accept the mismatch and document it — Nucleus structs that interop with C must be manually padded by the programmer.

This matters for correctness. Which approach should we take?

**4. Function pointers and callbacks.** C libraries commonly take function pointer arguments (e.g. `qsort` takes a comparator). The current `add-libc` encoding supports at most 4 parameters and can't represent function pointer parameter types. The new system needs to handle these. Is full function pointer type representation a requirement for this stage, or can it be deferred?

**5. `include` vs `import` unification.** After C header parsing is implemented, `include` (for C headers) and `import` (for `.nuc`/`.nuch` files) remain separate forms with different syntax and behavior. Should they stay separate, or should `import` subsume `include`? For example:

- `(import "stdio.h")` — detect `.h` extension and route to the C parser
- `(import stdio :lang c)` — explicit language annotation
- Keep `(include stdio)` as-is — separate forms for separate ecosystems

**6. The LLVM `.nuch` file.** Moving the LLVM declarations from `init-libc` to a hand-written `llvm.nuch` seems straightforward — the declarations are already in the right shape. Should this be done as a first step (independent of C header parsing) to reduce the size of `init-libc`?

**7. `.so` shared library scope.** The Makefile needs a target for building `.so` from Nucleus sources. Should there also be an `install` target that puts `.so`, `.h`, and `.nuch` in standard locations (`/usr/local/lib`, `/usr/local/include`)? Or is that premature?

## Completion criteria

This stage is complete when:

* `--emit-cheader` generates a valid C header from a Nucleus source file
* A C program can `#include` the generated header and link to the `.o` or `.so`
* `(include stdio)` works via parsed headers instead of hardcoded tables
* LLVM declarations use a `.nuch` file instead of `init-libc` entries
* The compiler can compile itself and pass all tests after these changes
