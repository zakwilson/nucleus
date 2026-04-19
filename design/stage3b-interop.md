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

**8. Unsigned type representation in LLVM IR.** LLVM IR integers are signless — `i32` serves for both signed and unsigned. The distinction only matters at the operation level (e.g. `sdiv` vs `udiv`, `sext` vs `zext`, `icmp slt` vs `icmp ult`). Adding `ui8`, `ui16`, `ui32`, `ui64` to Nucleus means:

- New `TypeKind` variants (e.g. `TY-UI8`, `TY-UI32`, `TY-UI64`)
- Arithmetic and comparison emit must choose signed vs unsigned LLVM instructions based on operand type
- Mixed-sign operations need a policy: error, implicit conversion, or explicit cast required?
- `type-to-ir` maps both `i32` and `ui32` to LLVM `i32` — the types are purely a Nucleus-level distinction

What is the policy for mixed-sign arithmetic (e.g. `(+ x:i32 y:ui32)`)? Require explicit cast, or silently promote?

**9. Struct padding/alignment implementation strategy.** The designer chose C ABI-compatible layout. The current `emit-sizeof` and struct field access use `getelementptr inbounds %StructName, ptr %p, i32 0, i32 <field-index>`, which delegates layout to LLVM's struct type. This means LLVM already inserts correct padding *if* the LLVM struct type is defined correctly (i.e. not as a packed struct). Questions:

- Are Nucleus struct LLVM type definitions currently emitted as packed? If so, changing to natural alignment may change the layout of existing Nucleus structs, breaking self-hosting. Need a migration strategy.
- For C-imported structs, the field types must exactly match the C ABI types (e.g. C `int` must map to LLVM `i32`, not `i64`). Is this sufficient, or do we also need explicit alignment attributes?

**10. `clang -E` parser scope.** After preprocessing, `clang -E` output still contains: typedef chains, anonymous structs/unions, `_Bool`, `_Complex`, `__builtin_*` references, `__attribute__` on declarations, `_Noreturn`, `static inline` function bodies, and `_Static_assert`. What is the minimum subset to parse at this stage? A proposed minimum:

- Function declarations (including variadic)
- Struct definitions (with nested struct pointers but not nested anonymous structs)
- Typedef aliases
- Enum definitions
- Extern variable declarations
- Skip: `static inline` bodies, `_Static_assert`, `_Complex`, unions

Is this subset acceptable, or are unions needed for this stage?

**11. Function pointer syntax in Nucleus.** Full function pointer types need a surface syntax. Possibilities:

- `(fn (i32 ptr) i32)` — a type expression meaning "function taking i32 and ptr, returning i32"
- `(fnptr i32 ptr -> i32)` — arrow-style
- `(ptr (fn i32 ptr : i32))` — wrapping fn in ptr

The choice affects how function pointer parameters are declared in `defn`, how they appear in struct fields, and how they're written in `.nuch` headers. Which syntax does the designer prefer?

**12. `import` string path resolution.** With unified `import`, `(import "stdio.h")` needs to find the header. Resolution options:

- Search a built-in list of system include paths (e.g. `/usr/include`)
- Use `clang -E -v` to discover the system include paths once
- Accept a `-I` flag to the compiler, matching C convention
- For `.nuc`/`.nuch` files, search relative to the importing file, then a library path

All of these? Some subset? Is `-I` required at this stage?

**13. `--emit-cheader` handling of Nucleus-only types.** All current Nucleus types (`Node`, `Sym`, `Type`, `Tok`, `Scope`, etc.) are plain structs of integers and pointers — fully C-representable. Cons cells and quoted lists are just `Node` structs with `car`/`cdr` pointers; there is no runtime or GC that would make them opaque to C. Therefore `--emit-cheader` can emit all current types without special handling. If a future stage introduces types with no C equivalent (e.g. closures with captured environments), that would require a policy decision at that time.

#### Designer:

1. Reliance on clang is a good solution in keeping with an LLVM-native design. The ideal implementation uses library calls rather than shelling out, but either will work at this stage. Nucleus must be able to use structs and functions from any library written in C, but ugly workarounds for edge cases are acceptable at this stage.

2. Type mapping must be correct, which means Nucleus must support all C types. Missing types like `ui32` for unsigned 32-bit integers should be added at this stage.

3. Nucleus structs should match the C ABI. At a future optimization stage, it may be appropriate to add a compiler flag for a more compact output.

4. This is the time to add full function pointer support. Nucleus will also get lambda, but implementing it is optional at this stage.

5. Unify `import` and `include` at this stage. Make the argument a string. Dispatch on file extension.

6. Refactor `init-libc` using a .nuch header.

7. An install target is premature at this point as long as there's an easy way to run things from the project directory with the necessary search paths.

8. Require explicit casts.

9. Check whether struct alignment needs changes and develop a strategy for migration if it does. Avoid alignment attributes and just match C at this stage.

10. Go with a subset, but create a stage3c document to address remaining potential incompatibilities.

11. TODO - the whole type syntax needs a revision before I pick a syntax for function pointers.

12. Keep the current convention of searching relative to the source file, then `$(pwd)/lib` by default, but add th `-I` flag.

13. Emit everything — all current types are C-representable. All Nucleus types must remain C-representable; introducing a type that cannot be represented in C would be a design violation.

## Completion criteria

This stage is complete when:

* `--emit-cheader` generates a valid C header from a Nucleus source file
* A C program can `#include` the generated header and link to the `.o` or `.so`
* `(include stdio)` works via parsed headers instead of hardcoded tables
* LLVM declarations use a `.nuch` file instead of `init-libc` entries
* The compiler can compile itself and pass all tests after these changes

