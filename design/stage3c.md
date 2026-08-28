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

**Partly resolved (Stage 15 W3a, [stage15-stress-test/cheader.md](stage15-stress-test/cheader.md) §1.6).**
The *tag* form is now handled: `struct Foo;` / `typedef struct Foo Foo;` registers
a layout-less type, so `ptr:Foo` is a real named type rather than a bare `ptr`,
and every by-value use is refused with the header:line the type was declared on.
This changes that conclusion — the name is no longer lost. What this section
describes and W3a does **not** cover is the *pointer* typedef
(`typedef struct Foo *FooRef;`): the tag is registered, but `FooRef` itself is
still dropped, because the compiler has no pointer-typedef aliasing mechanism to
register it into. That remains open.

## Type system gaps

### `const` and `volatile` qualifiers

C qualifiers are stripped during parsing. This is correct for code generation (LLVM handles const through metadata, not types) but loses intent information.

**Corrected (Stage 15 W3b, [stage15-stress-test/cheader.md](stage15-stress-test/cheader.md) §1.5).**
"Stripped during parsing" was true only in the **leading** position. A qualifier
after the base type (`int const *p`, which C permits and which denotes the same
type) terminated the type; its token was eaten as the parameter name and the
following `*p` began a phantom second parameter defaulting to `ptr` — so
`void f(int const *p)` imported as a *two*-parameter `(i32, ptr)` function, and
`void _mm_clflush(void const *)` (reached transitively from `SDL2/SDL.h`) as the
IR-invalid `declare void @_mm_clflush(void, ptr)`. `const`, `volatile`,
`restrict`/`__restrict`/`__restrict__` and `_Atomic` are now consumed and
discarded in **every** position C allows them: anywhere in the
declaration-specifier sequence and after each `*`. The section's conclusion
stands (qualifiers carry no information Nucleus models); only the claim that they
were already being stripped was wrong.

### `restrict` pointers

The `restrict` qualifier is stripped. LLVM can use `noalias` for optimization, but this is low priority.

### `long double` — DONE (Stage 16 FL-7, 2026-08-26)

`long double` is 80-bit on x86-64 Linux, IEEE binary128 on aarch64 and riscv64,
and a plain `double` under MSVC and on AVR. It imports as the target's format
now, alongside `_Float16`/`__fp16` → `f16` and `_Float128`/`__float128` → `f128`.
See [stage16-ergonomics/c-boundary-defects.md](stage16-ergonomics/c-boundary-defects.md)
§6 and §13. What is still unrepresentable, deliberately: `__int128` and `_BitInt`.

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

## Does W3 strengthen the case for replacing the hand-rolled parser with libclang?

**Marginally — and less than expected.** Stage 15 W3 (see
[stage15-stress-test/cheader.md](stage15-stress-test/cheader.md)) put the
hand-rolled parser through three mainstream umbrella headers (`SDL2/SDL.h`,
`SDL2/SDL_mixer.h`, `png.h`) plus the POSIX/libc set. Every defect it turned up
was small and local once located:

* a qualifier position the grammar had simply forgotten (W3b, §1.5);
* a stray `)` that made the top-level two-way dispatch fall through (W3b);
* a forward declaration branch that returned early instead of registering a
  name (W3a, §1.6);
* a 16-entry parameter array that was written past (W3b);
* a `(free buf)` that became a use-after-free when the preprocessed text was
  cached (W3a).

None of these argues for a different architecture; each is a few lines. The
class this note expected to be the real argument — **following typedef chains
through a real system header** (`off_t` → `__off_t` → `long int`, SDL's `Uint32`
→ `unsigned int`) — turned out **not** to need a scoped symbol table over the
preprocessed unit. W3c settled it with a **flat name→type table resolved at the
point each `typedef` is parsed**: a C `typedef` at file scope is visible from
there to the end of the translation unit, and the preprocessed text is scanned in
order, so an entry can only ever resolve against entries recorded strictly before
it. That collapses a chain to one lookup, makes a cycle impossible by
construction, and is roughly 80 lines. Neighbouring gaps it exposed (`enum` was
not a declaration specifier; `__extension__` was not consumed) were a few lines
each.

So the prediction here was wrong in the direction that matters: **the typedef
work did not move the needle toward libclang.** What remains genuinely awkward by
hand is narrower and more structural — the **declarator grammar inside a struct
body**: array fields (`Uint8 data[16]`), bitfields, and multi-declarator lines
(`int a, b;`) all make the body parser abandon the whole struct. That is what
keeps `FILE` and SDL's `SDL_GUID` opaque. It is a real recursive-declarator
problem rather than a lookup problem, and it is the first place a real C front end
would pay for itself. The type-system gaps beside it (`long double`, `_Float128`,
`_Float16` — 156 skipped declarations across the standard headers) are not parser
problems at all and libclang would not have helped with them; Stage 16 FL-1…FL-7
closed all three directly.

The safety net matters here too: since W3b, a declaration the parser cannot
faithfully describe is **skipped with a located warning** rather than emitted as
invalid IR, so the cost of a remaining parser gap is a named missing function
instead of a failed build. That materially lowers the pressure to replace the
parser wholesale.

**Settled 2026-08-26 —
[stage16-ergonomics/cheader-parser-vs-libclang.md](stage16-ergonomics/cheader-parser-vs-libclang.md):
finish the parser.** The prediction above named the right item and then Stage 16
L1–L5 did it by hand: the struct-body declarator grammar now reads array members
with literal *and* constant-expression extents (`sizeof`-bearing ones included),
so `SDL_GUID` and the whole array class are no longer the blocker. Re-measured
across 32 headers, **102 of 111** named struct/union bodies lay out and **101 of
103** emitted C types match clang's `sizeof`. `FILE` is still opaque, but for a
*different* reason than this note gives — glibc 2.41's `_IO_FILE` carries
`int _flags2:24;`, a bitfield, not an array field. The nine remaining blocked
types were four shapes plus `long double`, four of them fell to a single ~15-line
repair, and of the three genuinely hard ones libclang would pay for exactly one
(`__attribute__((packed))`); bitfields and C11 anonymous members are blocked by
Nucleus having no way to express them, which a better front end does not fix.
(Both of those claims were re-priced in that document's §8 and the anonymous-member
half was withdrawn — the memoizer already lowers them. `long double` came off the
list entirely with FL-7.) A
libclang-shaped API was probed end to end from Nucleus and works — the SysV ABI
is not the obstacle — so the decision rests on economics, and those are laid out
there along with the triggers that would flip it.
