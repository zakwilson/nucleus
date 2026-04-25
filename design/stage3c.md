# Stage 3c: Deferred C interop issues

Issues identified during Stage 3b that were deferred for correctness-over-completeness reasons. These should be addressed before Nucleus is used with C libraries beyond libc.

## C header parsing gaps

The current `clang -E` parser handles function declarations, basic typedefs, and extern variables. The following C constructs are skipped or produce incorrect results:

### Unions

Unions are skipped entirely. C libraries that expose union types in their API (e.g. `SDL_Event`, `pthread_mutexattr_t`) cannot be used directly. Options:

- Parse unions as structs using the size of the largest member
- Map unions to opaque `ptr` and require field access via casts
- Full union support with a `defunion` form

### Anonymous and nested structs

Anonymous structs inside other structs (common in system headers) are skipped. Named nested structs are partially handled. The parser needs to handle:

- `struct outer { struct { int x; } inner; }` — anonymous inner struct
- `struct outer { struct inner { int x; } field; }` — named inner struct
- Unnamed bit-fields and padding fields

### Bit-fields

Struct bit-fields (`int flags : 3;`) are not parsed. These are common in low-level system structs. Supporting them requires:

- Parsing the `: width` syntax
- Computing correct field offsets with bit-level granularity
- Generating shift/mask code for field access

### `_Complex` types

`_Complex float` / `_Complex double` are skipped. These appear in `<complex.h>` and occasionally in other math headers. Low priority unless math library interop is needed.

### `static inline` functions

`static inline` function bodies in headers are skipped (the parser fast-forwards past the body). Some C libraries provide important functionality only as `static inline` (e.g. helper macros expanded to inline functions). Options:

- Parse and compile inline function bodies (requires full C expression parsing)
- Ignore them and require users to write Nucleus wrappers
- Extract just the signature and emit a `declare` (won't link without the body)

### Variadic macros and function-like macros

`#define` macros are fully expanded by `clang -E`, so they don't appear in the parser input. However, some C APIs rely on macros that expand to compound literals or statement expressions, which the Nucleus parser can't handle. Users must write manual wrappers for these.

### Enum with explicit values

The parser does not currently import C enums. Adding support for `enum { A = 0, B = 1, ... }` would be useful for interop with C libraries that use enums for flags and constants.

## Struct ABI compatibility

### Padding and alignment

Nucleus structs currently use LLVM's default struct layout, which matches the C ABI on x86-64 for simple cases. However:

- The compiler does not verify that Nucleus struct definitions match C struct layout
- No mechanism exists to specify alignment (`__attribute__((aligned(N)))`)
- Packed structs (`__attribute__((packed))`) are not supported
- Struct layout on non-x86-64 platforms has not been tested

### Opaque struct handles

Many C libraries use opaque struct pointers (`typedef struct Foo *FooRef`). The current parser maps all pointers to `ptr`, which is correct for the LLVM level but loses documentation value. Consider whether to preserve typedef names as aliases.

## Type system gaps

### `const` and `volatile` qualifiers

C qualifiers are stripped during parsing. This is correct for code generation (LLVM handles const through metadata, not types) but loses intent information.

### `restrict` pointers

The `restrict` qualifier is stripped. LLVM can use `noalias` for optimization, but this is low priority.

### `long double`

`long double` is 80-bit on x86-64 Linux. Nucleus has no floating-point types at all yet. This is blocked on adding float/double support.

### Function pointers in struct fields

Function pointer fields in C structs are mapped to `ptr`. The type information is lost. With Nucleus's `TY-FN` type support, these could be represented accurately.

## Platform portability

### 32-bit support

The compiler hardcodes `size_t` = `i64`, pointer size = 8 bytes, and `target triple = "x86_64-pc-linux-gnu"`. Supporting 32-bit targets requires:

- Making `size_t` mapping platform-dependent
- Updating pointer size assumptions
- Changing the target triple

### Non-Linux platforms

macOS and Windows have different system header layouts and ABI conventions. The `clang -E` approach should work cross-platform (clang is available everywhere), but the parser may encounter platform-specific syntax.

## init-libc replacement ✓

The hardcoded `init-libc` table has been removed. Both `(include module)` and REPL startup now use C header parsing via `clang -E`. The REPL pre-loads stdio.h, stdlib.h, string.h, ctype.h, and unistd.h at startup. All libc functions from those headers are available, not just the previously hardcoded subset.
