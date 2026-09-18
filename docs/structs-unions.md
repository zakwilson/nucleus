# Structs and Unions

## Anonymous structs

*(For C11's unnamed **member** whose fields are visible from the outer struct, see
[Anonymous members](#anonymous-members--anon-t) below — a different feature.)*

`(struct field:type ...)` is a type expression accepted wherever a type is expected — `let` bindings, `defn` parameter and return types, `defstruct` field types, `(ptr (struct ...))`, `as`/`unsafe/cast` targets. Members use the same `name:type` / `(name type)` form as `defstruct`. Anonymous structs are **memoized by structural content**: two `(struct ...)` literals with the same field name+type list share a single underlying `StructDef`, so values flow between sites that spell out the same shape. The synthetic LLVM type name is `%__anon_struct_h<16-hex>`, derived from a 64-bit FNV-1a hash of the field list.

Examples:

- `(let ((p (ptr (struct x:i32 y:i32))) (alloca (struct x:i32 y:i32))) ...)` — local of anonymous-struct shape
- `(defstruct Outer (pt (struct x:i32 y:i32)) tag:i32)` — nested by value
- `(defn take ((p (ptr (struct x:i32)))):i32  ...)` — parameter typed as anonymous struct pointer

Use `(addr-of obj 'field)` to obtain a pointer to a field without loading it. Result is typed `(ptr field-type)`, so it composes with a `set!` place, `deref`, and further `addr-of` calls — e.g. `(set! ((addr-of o 'point) 'x) 10)` writes through a value-typed nested struct field.

## Packed structs — `(defstruct :packed …)`

`:packed` between `defstruct` and the name is C's `__attribute__((packed))`: every
field sits at the next byte with no padding, and the struct's own alignment is 1.

```lisp
(defstruct :packed WireHdr tag:i8 len:i32 flags:i16)   ; sizeof 7
(defstruct        PlainHdr tag:i8 len:i32 flags:i16)   ; sizeof 12
```

Three things change together, and only the first is visible in a `sizeof`:

- The layout: field offsets and the total size drop their padding, and a packed
  struct nested inside another contributes alignment 1 to it.
- The LLVM type line becomes `<{ … }>`.
- **Every read and write through a packed field emits `align 1`.** A packed field
  can sit at any byte, so an access claiming the field type's natural alignment
  would be a false promise — a fault on a strict-alignment target and a
  miscompile under vectorization on x86.

`(addr-of p 'field)` on a packed struct hands back an ordinary `(ref T)`, which carries
no alignment record — a load through *that* pointer claims the type's natural
alignment again. This is the same hole C has (`&packed.x` is why GCC has
`-Waddress-of-packed-member`); take the field by value instead.

**On import**, `__attribute__((packed))` is honoured in the two positions C
honours it: before the tag (`struct __attribute__((packed)) S { … };`) and after
the closing brace (`struct S { … } __attribute__((packed));`), including the
`__packed__` spelling. It is deliberately *ignored* after the declared name of a
typedef (`typedef struct { … } S __attribute__((packed));`) because clang and gcc
both ignore it there — honouring it would produce a `sizeof` that disagrees with
every C compiler on the platform. This is what makes `struct epoll_event` import
at 12 bytes rather than 16.

**On export**, `--emit-cheader` writes the attribute back out after the closing
brace, so a C consumer of a generated header gets the same layout.

**On AVR every type is byte-aligned** (`BIGGEST_ALIGNMENT` is 8 bits), so packed
and unpacked structs lay out identically there; the annotation is accepted and
has no effect.

## Over-aligned structs and fields — `:align N`

`__attribute__((aligned(N)))` is the opposite mechanism to `:packed`: it *raises*
an alignment. `:align N` takes an integer operand (a power of two, at most 4096)
and goes in the same two places a declaration attribute goes — before the struct
name, or heading a field cell:

```lisp
(defstruct :align 32 CacheLine v:i64)          ; sizeof 32, alignment 32
(defstruct Slot c:i8 (:align 16 v:i32))        ; v at offset 16, sizeof 32
```

Alignment only ever goes up. `(defstruct :align 2 S x:i32)` leaves `S` at
alignment 4, exactly as C does. On a `:packed` struct the two compose: packing
drops every field to alignment 1 and `:align` then raises what it names, so
`(defstruct :packed :align 4 D c:i8 i:i32)` is 8 bytes with `i` still at offset 1,
while `(defstruct :packed E c:i8 (:align 4 i:i32))` puts `i` back at 4.

Two consequences beyond the offsets:

- **The gap becomes a real `[k x i8]` element in the LLVM type**, because LLVM
  models neither form of over-alignment and computes array strides and GEP
  offsets from the element list alone. `(defstruct :align 16 A x:i32)` emits
  `%A = type { i32, [12 x i8] }`, which is also what clang emits.
- **Every `alloca` and global of an over-aligned struct states its alignment**,
  since LLVM would otherwise derive the smaller one from that same element list.

**On import** all three positions C honours are read — before the tag, after the
closing brace, and on a member — with both the `aligned` and `__aligned__`
spellings. The argument may be an integer or `__alignof__(T)` / `sizeof(T)`; the
`aligned(__alignof__(T))` idiom is the common one in real headers, where it pins
a member's natural alignment rather than raising it, and it is what
`max_align_t` is built from. An argument that is none of those (a macro that
survived preprocessing, an arithmetic expression) leaves the type opaque with a
recorded reason rather than a guessed layout.

**On export**, `--emit-cheader` writes both the struct-level and the member-level
attribute back out.

## Bit-fields — `(:bits W name:T)`

A field cell headed by `:bits` declares a C bit-field: `W` bits of an integer
field of declared type `T`, sharing storage with its neighbours.

```lisp
(defstruct Hdr (:bits 4 ver:ui32) (:bits 4 hlen:ui32) (:bits 24 flow:ui32))
```

`W` must be between 0 and 64 and no wider than `T` (`':bits 40' exceeds the 32
bits of its declared type`), and `T` must be an integer type. A **zero** width
is C's unnamed boundary member: it stores nothing and forces the next bit-field
to start at the next boundary of its declared type.

```lisp
(defstruct C (:bits 1 x:ui32) (:bits 0 z:ui32) (:bits 1 y:ui32))   ; sizeof 8
```

Reads and writes look like any other field — `(get p 'ver)`, `(set! (p 'ver) 4)` —
and a signed bit-field sign-extends on read, as in C. **`(addr-of p 'ver)` is refused**:
a bit-field shares its bytes with its neighbours and has no address. That is C's
own rule (`&s.bits` is ill-formed there too), not a Nucleus limitation.

The layout rules are C's, which means they are the *platform's*: a bit-field may
not cross a boundary of its declared type, `:packed` drops that rule but not the
zero-width one, and AVR drops the crossing rule while keeping a zero-width
member's byte boundary. Nucleus matches the platform C compiler on every target
it supports — see
[design/stage16-ergonomics/c-boundary-defects.md](../design/stage16-ergonomics/c-boundary-defects.md)
§15.4 for the measured table.

**On import**, `int x:3;` and the unnamed forms `unsigned :3;` / `unsigned :0;`
are all read. **On export**, `--emit-cheader` writes the width back out.

## Anonymous members — `(:anon T)`

C11 lets a struct hold an unnamed struct or union member whose *own* field names
are visible from the outside. `(:anon T)` declares one over an already-declared
type:

```lisp
(defstruct Inner a:i32 b:i32)
(defstruct Outer tag:i32 (:anon Inner) z:i32)
(defstruct Inline tag:i32 (:anon (struct a:i32 b:i32)))   ; C's own spelling

(defn read (p:ptr:Outer):i32 (return (get p 'a)))     ; reaches through the member
```

The member is an ordinary nested member — it occupies its own space and has its
own alignment — and the lookup for a name that is not a direct field descends
through it, at any depth, including through an anonymous union. A name supplied
by **two** anonymous members is ambiguous and refused, as C refuses it; give the
member you mean a name.

`T` must be a struct or a union. `--emit-cheader` **refuses** an `:anon` member:
C writes an anonymous member by inlining its body, so a member naming a declared
type has no standard C spelling.

**On import**, `struct { … };` and `union { … };` with no declarator are read as
anonymous members, which is how `sigcontext` and `rusage` are written.

## Flexible array members

A C trailing member declared `T name[];` is read as a flexible array member: it
contributes no bytes to the struct's size, and appears in the LLVM type as
`[0 x T]`. `struct cmsghdr` is the usual example. There is no `defstruct`
spelling for one; it exists so real headers import.

## Fixed-size array fields

A field may have the type `(array T N)` — a fixed-size array stored **inline**,
laid out exactly as C's `T name[N];`:

```lisp
(defstruct Row tag:i8 (cells (array i32 4)) mark:i8)
;  C: struct { int8_t tag; int32_t cells[4]; int8_t mark; };   sizeof 24
```

This works for a `defstruct` field, an anonymous `(struct …)` member and an
anonymous `(union …)` member alike — one rule for "a field of an aggregate".
Size, alignment and every field offset match the platform C ABI, and a
by-value struct with an array field is classified for passing element by
element (so `struct { float v[2]; }` travels in an SSE register). Both are
gated: `make layout-test` diffs Nucleus's `sizeof`/`offsetof` against the
platform C compiler's, and `make abi-test` links a Nucleus caller against a C
callee.

**Reading an array field decays it to `(ref T)`** — the address of element 0,
via the field GEP with no load — so it is directly indexable:

```lisp
(defn row-sum ((r (ref Row))):i32
  (+ (aref (r 'cells) 0) (aref (r 'cells) 1)))
```

Consequently an array field cannot be assigned as a whole (`(set! (r 'cells) …)`
is refused, as `s.xs = …` is in C); write through the decayed pointer with
an element place, or copy with `memcpy`. `(addr-of r 'cells)` gives the same address as
`(r 'cells)`.

A `defvar` of a struct with an array field can be given a constant initializer
that nests both — see
[Global initializers](toplevel.md#global-initializers):

```lisp
(defvar g-row:Row (Row 1 (array i32 9 8 7 6) 2))
```

`--emit-cheader` renders the field with C's postfix declarator; `--emit-nuch`
round-trips the `(array T N)` spelling unchanged. See
[Fixed-size arrays](types.md#fixed-size-arrays--array-t-n) for the type's full
rules, including where it is refused.

## Passing and returning structs by value

A struct used directly (not behind `ptr`) as a `defn`/`declare` parameter or return type is passed/returned per the **platform C ABI**, so it interoperates correctly with C functions compiled by the system `cc`. On x86_64 System V this means small structs are coerced into registers (e.g. `{i32,i32}` → one `i64`; a struct with a `float` field whose eightbyte also holds an integer → `i64`), and structs larger than 16 bytes are passed `byval` / returned via a hidden `sret` pointer. aarch64, `avr`, and `riscv64` instead pass every `ABI-MEMORY`-classified struct as a plain pointer (no `byval` — none of those targets' ABIs has that attribute); on `avr` this applies to **every** struct/union regardless of size, not just those over 16 bytes, because the SysV eightbyte classifier's register-sized-chunk model has no counterpart on an 8-bit target — `abi-classify` bypasses eightbyte classification for `avr` entirely rather than adapting it. On `riscv64` (lp64d), struct-by-value follows the psABI's **hard-float** rules. An aggregate is first *flattened*: nested structs and arrays expand recursively into their scalar members, and a union never flattens. If the flattened list is exactly one FP real, two FP reals, or one FP real plus one integer ≤ XLEN **in either order**, the value travels in FP registers with its members' own IR types and offsets — `struct {float f;}` → `float`, `struct {double a,b;}` → `{double,double}`, `struct {float v[2];}` → `{float,float}` (two separate FPRs, where x86_64 SysV packs the same struct into one `<2 x float>` eightbyte), `struct {i32 i; f32 f;}` → `{i32,float}`, `struct {f32 f; i32 i;}` → `{float,i32}`. This applies only while the registers the rule needs are still free at that argument position: the budget is fa0-fa7 and a0-a7, an `ABI-MEMORY` return spends one of the latter on its hidden `sret` pointer, and every argument in a call or parameter list is charged in declaration order. Anything that does not qualify — three or more flattened members, a union, an over-wide member, a **variadic** argument (the `...` tail always uses the integer convention, with no flattening and no FP registers), or exhausted registers — falls back to the integer convention, coercing a struct ≤ 16 bytes into integer registers (`i64` / `{i64,i64}`). Returns are classified against a0/a1/fa0/fa1, which are always available, so a return never falls back for want of registers. A struct value is produced by dereferencing a pointer (`@p`) and consumed by storing the call result (`(set! (deref q) (make ...))`). Reading a field needs no pointer: `(get p 'f)`, `(p 'f)` and `(_get p 'f)` all accept a struct **value** — a by-value parameter, a `let`-bound struct local, or a call result read in place (`(get (mk 3) 'f)`). Writing one does: a member place and the 2-argument `addr-of` need the receiver's storage, so they take the same receivers 1-argument `addr-of` does — a binding, not a temporary (`(set! ((mk 3) 'f) 1)` is an error; bind it first). A function may take or return a struct defined anywhere in the same compilation unit or an import — struct definitions are registered before function signatures are resolved.

### Compound literals in by-value struct positions

A `(S …)` compound literal is alloca-backed and evaluates to `(ref S)`, not to a
struct *value*. Wherever a by-value `S` is expected, the pointer is loaded
implicitly — one `load`, the same instruction `(deref …)` emits — so the literal
can be written directly:

```lisp
(defstruct P (x i32) (y i32))
(defstruct Row (p P) (n i32))

(defn mk (a:i32):P (return (P a (* a 2))))     ; by-value return

(let (tbl:ptr:P (array P (P 1 2) (P 3 4))      ; array element
      v:P       (P 5 6)                        ; let / with binding
      r:ptr:Row (Row (P 7 8) 9)                ; struct-typed field
      m:P       (mk 3))
  (set! (aref tbl 1) (P 10 11)))                     ; element store
```

The same applies to every `set!` place, union-variant construction, and
call arguments (which have always accepted it). Two constraints:

* The struct type must match exactly — a compound literal of a *different*
  struct in an `S` slot is still a type mismatch.
* The conversion is a `deref`, so it carries `deref`'s obligation: a `?T` source
  must be narrowed (`if-some` / `when-some` / `unwrap` / a null guard) first.

The explicit `(deref (S …))` spelling remains valid everywhere and emits
byte-identical IR; the two are interchangeable, including within one `(array S …)`.
Unspecified slots of an `(array S …)` and omitted fields of a struct literal
zero-fill, struct-, union- and `CStr`-typed slots included.

## C header struct ingestion

C headers consumed via `(import-use "foo.h")` or `(import "foo.h" prefix)` now register their `struct Foo { ... };` and `typedef struct { ... } Bar;` definitions as Nucleus structs with the same name. Anonymous inline struct fields are registered as memoized anonymous structs (same `__anon_struct_h<hex>` machinery). Pass-by-value parameters typed as a C struct work through this path. `union { ... }` fields, named unions, and `typedef union` are registered as untagged union types (see [Untagged `(union ...)`](#untagged-union-)); headers like SDL's or pthread's no longer degrade over them.

An **inline function-pointer member** (`void (*f)(int);`) imports as a real
`(fn void)(i32)` field, as does the same shape behind a `typedef` and in a
parameter, a `typedef` declarator, or a function's return
(`void (*signal(int, void (*)(int)))(int)`) — see
[Function pointer types](types.md#function-pointer-types). If the declarator's
inner types are ones the parser cannot describe, the field narrows to a plain
`ptr` (a function pointer is pointer-sized either way, so the layout is
unaffected) rather than making the struct opaque.

A **multi-declarator field line** shares one run of declaration specifiers
across several declarators, each with its own pointer stars, array extents and
bit-field width:

```c
struct cd { int a, b; char *s, *t; int x, y[3]; unsigned p : 3, q : 5; };
```

imports as `%cd = type { i32, i32, ptr, ptr, i32, [3 x i32], [1 x i8] }`. The one
shape that is refused is declarators that **disagree in pointer depth**
(`int *p, q;`): the first declarator's `*` has already collapsed the base type
into `ptr`, so there is nothing left to give `q`, and the struct goes opaque
rather than giving `q` the wrong type.

A declaration may also carry a declarator list **after the body**, and every
declarator in it is a type name:

```c
typedef struct png_image_struct { … } png_image, *png_imagep;
typedef struct { int r; } Rec, RecAlias, RecArr[3];
struct S { int a; long b; } x, y;
```

`png_image` and `Rec`/`RecAlias` are second names for the body; `png_imagep` is
a pointer typedef (`ptr`, whatever the body was); `RecArr` is an array of it,
which decays in parameter position exactly as a first-position array typedef
does. In the last line `x` and `y` are C **variables**, which Nucleus does not
import at all — only `struct S` is taken from the line, and the declarators are
consumed so the declaration after them is read from the right place.

A member whose type the parser genuinely cannot represent — an array whose extent does not fold to a compile-time constant, a declarator list of mixed pointer depth, or a by-value use of an unresolvable typedef — makes the **whole struct opaque** (below), with a located error at every by-value use, rather than a layout-incompatible partial struct. (Bit-fields, C11 anonymous members, multi-declarator lines and flexible array members are all represented now — see the sections above.) A size is never guessed: a member reached indirectly, through a typedef the parser could not follow, used to resolve to `ptr` silently, giving a wrong struct *layout* with no diagnostic; it is refused the same way a direct unrepresentable member always was.

### Array members

A struct field whose C declaration carries an array extent is read as
`(array T N)`, laid out exactly as the corresponding
[fixed-size array field](#fixed-size-array-fields):

```c
struct sockaddr_in6 { ... uint8_t sin6_addr[16]; ... };            /* literal extent */
struct grid          { int cells[3][4]; };                         /* [a][b] folds right-to-left into (array (array i32 4) 3) */
struct with_pad      { char pad[15 * sizeof(int) - sizeof(void*)]; int x; };  /* constant-expression extent */
```

The extent may be a decimal literal, a macro that expands to one, a
multi-dimensional `[a][b]…` (folded right-to-left into nested array types), or
a constant expression — `+ - * / % << >> ( )`, integer literals, and
`sizeof(type)` — evaluated by the importer's own integer evaluator. **The
expression is folded for the emission *target*, never the preprocessing
host**: `clang -E` always preprocesses for the machine running the compiler
even under `--target=`, so an extent naming `sizeof(long)` or `sizeof(void*)`
is evaluated against the *target's* type sizes.

An extent the evaluator cannot fold — an unexpanded macro, a `sizeof` of a
type it cannot resolve, a name that is not a compile-time constant — does not
produce a guess: the struct is left opaque, exactly as if the member could not
be parsed at all.

A `#` linemarker `clang -E` writes **inside** a struct body — a routine
preprocessing artifact, not a code smell — no longer aborts the struct either;
`struct timespec`, `struct stat` and `struct itimerspec` all import correctly
because of this.

`__attribute__((packed))` and other layout attributes are still not modeled:
`struct epoll_event` imports at 16 bytes where C's packed attribute makes it
12, silently. Only the shapes above are covered.

A header's type names are visible to `defn` **signatures** in the importing unit,
not only inside function bodies — `(defn play (m:ptr:Mix_Music):i32 …)` resolves,
even though signatures are resolved before imports are processed.

## Opaque (forward-declared) C types

A C header may name a type without defining it:

```c
struct SDL_Window;                        /* forward declaration    */
typedef struct Mix_Music Mix_Music;       /* opaque handle typedef  */
```

This is C's standard opaque-handle idiom, and `FILE` is an instance of it on
glibc. Nucleus registers the **name** with no layout, so:

* **`ptr:Foo` / `(ref Foo)` / `(raw Foo)` are legal** — everywhere, including in
  a `defn` signature. That is all a handle needs, and it is exactly what C
  permits.
* **Every by-value use is refused**, with the source location of the misuse *and*
  the header and line the type was declared on:

  ```
  prog.nuc:8: error: sizeof: 'CHOpaque' is an opaque type declared at
  ./foo.h:11; only pointers to it are valid
  ```

  The refused constructions are `(sizeof Foo)`, `(alloca Foo)`, field access
  through a `ptr:Foo`, a by-value `defn` parameter or return type, and a
  by-value `defstruct` field. A size is never guessed: a silently wrong one
  would misjudge an allocation.
* **A definition arriving later upgrades the entry in place.** Real headers write
  `struct Foo;` first and `struct Foo { … };` afterwards (glibc's `<stdio.h>`
  declares `struct _IO_FILE;` three times before defining it); the tag keeps its
  identity, so a `ptr:Foo` written before the definition sees the fields. The
  upgrade also reaches any `typedef struct Foo Bar;` alias registered while the
  tag was still opaque.

A type stays opaque either because no header in the translation unit defines
it — `FILE` is this case: a plain `(import-use "stdio.h")` only ever sees
`typedef struct _IO_FILE FILE;`, never `struct _IO_FILE`'s body — or because
its definition uses a construct the C declaration parser cannot represent: an
array member whose extent does not fold to a compile-time constant, or a
declarator list whose declarators disagree in pointer depth (`int *p, q;`). The
five constructs that used to belong on this list — bit-fields, C11 anonymous
members, inline function-pointer members, multi-declarator lines, and the
flexible array member — are all represented now, so `FILE`, `sigcontext`,
`rusage`, `sigaction`, `cmsghdr` and `tcp_info` lay out with the same sizes and
offsets the platform `cc` gives them. Both are
usable as handles; neither can be used by value. `examples/cheader-opaque.nuc`
is a worked example (a real `fopen`/`fprintf`/`fgets` round trip through
`ptr:FILE`).

A function declaration whose first token is `struct` or `union` and which omits
`extern` — `struct Tag *f(int);` — is imported normally. glibc always writes
`extern`, but musl deliberately omits it, so on Alpine every function returning a
`struct X *` used to be dropped without a word.

## Type qualifiers in imported declarations

`const`, `volatile`, `restrict` (and its `__restrict` / `__restrict__`
spellings) and `_Atomic` are accepted **everywhere C allows them** — anywhere in
the declaration-specifier sequence, before or after the base type, and after
every `*`. They carry no information Nucleus models and do not change the
emitted type, so the importer consumes and discards them:

```c
const int *p        int const *p        int * const p
volatile int *p     int volatile *p     int const * restrict const p
```

all import as a single `ptr` parameter. This matters more than it looks: before
Stage 15 W3b only the *leading* position was handled, so an "east" qualifier
ended the type, its token was eaten as the parameter's name, and the following
`*p` began a phantom **second** parameter — `void f(int const *p)` imported as a
two-parameter `(i32, ptr)` function. Only the `void` spelling produced IR that
LLVM rejected; the rest were silently wrong at the ABI.

### Declaration specifiers are order-independent

C's integer specifiers may be written in any order and a bare `unsigned` or
`signed` is itself a type (implicitly `unsigned int` / `signed int`), so all six
of these import identically to the corresponding `ui32`/`i32` and `ui64`/`i16`:

```c
unsigned a;   signed b;      unsigned int c;   int unsigned d;
unsigned long e;  long unsigned f;  short unsigned g;  unsigned short h;
```

A base this parser has no width for (`__int128`, `_BitInt(N)`) is *not* narrowed
to `int` — it reaches the unresolved-base path and the enclosing declaration is
skipped with a reason, as it was before.

## Typedefs in imported declarations

A C `typedef` of a scalar, pointer, function pointer or enum resolves to the type
it names, **transitively**:

```c
typedef long int __off_t;
typedef __off_t  off_t;          /* off_t -> __off_t -> long int -> i64 */
typedef unsigned char Uint8;     /* -> ui8  */
typedef unsigned int  Uint32;    /* -> ui32 */
typedef char        *string_t;   /* -> ptr  */
typedef int   (*handler)(int);   /* -> (fn i32)(i32) */
typedef enum { A, B } mode_t2;   /* -> i32  (a C enum's underlying type) */
typedef struct Foo   *FooPtr;    /* -> ptr  */
```

Resolution happens where the `typedef` is parsed, so a chain costs one lookup at
each use and a self-referential typedef cannot loop. `enum` is understood as a
declaration specifier too, tagged (`enum Tag e`) or inline (`enum { A, B } e`),
and lowers to `i32`. A `typedef` of a struct or union keeps going through the
struct registry, so it can be used as `ptr:Name` and — when its layout is known —
by value.

This applies uniformly to **return types, parameters and struct fields**. Before
Stage 15 W3c an unfollowed typedef resolved to `ptr`, so `lseek` imported as
`declare ptr @lseek(i32, ptr, i32)` (its `off_t` return *and* its `off_t`
parameter both wrong), and a `Uint8` struct field typed as a pointer — giving a
wrong struct *layout*, silently. `examples/cheader-posix.nuc` is a worked example:
`open`/`write`/`lseek`/`read`/`close` driven entirely through `<fcntl.h>` and
`<unistd.h>`, using `lseek`'s `off_t` as an integer on both sides.

A typedef the parser cannot follow is **never silently `ptr`**. The name is
recorded as known-but-unrepresentable and any *by-value* use of it is refused
(below); a *pointer* to it stays `ptr`, which is correct — every C pointer is one
machine word. Stage 16 FL-7 emptied most of this set: `long double`, `_Float128`,
`__float128`, `_Float16` and `__fp16` all import as real types now (see [The
wide float widths](types.md#the-wide-float-widths-and-which-targets-have-them)).
What remains is `__int128` and `_BitInt`, both deliberately unscheduled, and a
typedef of a struct whose body the parser could not read (see
[Array members](#array-members) for when that is).

### Array typedefs decay like any other C array

`typedef long __jmp_buf[8];` (a scalar element) and `typedef struct Tag
Name[N];` (an aggregate element — the upgrade this alias gets when `Tag`'s own
body becomes known is the same one described in
[Opaque types](#opaque-forward-declared-c-types)) are both representable, as
`(array T N)`, under the same extent rules as a
[struct member](#array-members). C decays an array **parameter or return** to
a pointer, and the importer follows the same rule at the same boundary — a
**struct member** of the typedef's type does not decay, exactly as a C struct
member never does:

```c
int setjmp(jmp_buf env);          /* jmp_buf = struct __jmp_buf_tag[1] */
struct s { jmp_buf saved; };      /* member: stays the full inline array */
```

```
declare i32 @setjmp(ptr) returns_twice        ; parameter: decayed to one word
%s = type { [1 x %__jmp_buf_tag] }            ; member: still the full inline array
```

A **with-body** aggregate array typedef — `typedef struct Tag { ... } Name[N];`,
body and array declarator in the same statement — is read the same way, tagged
or not:

```c
typedef struct cd_tag { int x, y; } cd_tagarr[2];
typedef struct { int x, y; } cd_anonarr[3];
void take(cd_tagarr a);
```
```
%cd_tag = type { i32, i32 }
@v = global [2 x %cd_tag] zeroinitializer      ; (defvar v:cd_tagarr)
declare void @take(ptr)                        ; parameter: decayed
```

An untagged body has no C tag for the type name to hang on, so the importer
mints one — `%__carr.<typedef name>` — which is what a `(defvar u:cd_anonarr)`
shows as its element type. It is a compiler-minted name and is not spellable.

### Comma-separated typedef declarator lists

`typedef int a, *b;` declares two names, each with its own pointer depth and
its own array extents, and each is recorded:

```c
typedef int  cd_ta, *cd_tb;      /* cd_ta -> i32,  cd_tb -> ptr        */
typedef long cd_tc, cd_td[4];    /* cd_tc -> i64,  cd_td -> [4 x i64]  */
```

As with a [multi-declarator struct field
line](#c-header-struct-ingestion), the one case that is refused is a later
declarator whose base the first declarator's `*` already consumed
(`typedef int *a, b;` — `b` is recorded known-but-unrepresentable rather than
given `a`'s type).

## A C typedef is a Nucleus type name

A C typedef — scalar, pointer, function pointer, enum, or (per above) array —
is usable directly as a Nucleus type name, in every position a type is
expected: a `defn` parameter or return, a `defvar`, a struct field, a `let` or
`with` binding. It is **transparent**, exactly like a Nucleus
[`deftype`](types.md#type-aliases--deftype) alias: `type-eq` to the type it
names, one overload for dispatch, and it mangles as that type, not as its own
name.

```lisp
(import-use "unistd.h")
(defn seek (fd:i32 off:off_t):off_t off)   ; -> i64 @seek(i32, i64) — off_t IS i64
```

```lisp
(import-use "setjmp.h")
(defvar env:jmp_buf)                        ; 200 bytes of storage — jmp_buf is an array typedef
```

**A `deftype` is never masked by an import, and never masks one either.** A
type name is probed the same way regardless of which came from where: a
`(deftype off_t ...)` naming an already-imported C typedef is refused, in
either declaration order, the same way redefining any other type name is —
see [Type aliases — `deftype`](types.md#type-aliases--deftype):

```
prog.nuc:2: error: deftype: 'off_t' already names a C typedef imported from
/usr/include/unistd.h — an alias of an existing type name would never resolve
```

**A known-but-unrepresentable typedef gets its own message**, distinct from an
absent name:

```
prog.nuc:2: error: 'weird_ld_t' names a C type this compiler cannot represent (/tmp/weird.h:1)
```

versus the ordinary `unknown type: 'nosuch' — not defined anywhere in this
compilation unit` for a name that was never a typedef at all.

**Known limitation: a `defn` signature or a `defvar`'s declared type is
resolved before any import runs**, in the whole-unit signature prescan (see
[Declarations the importer skips](#declarations-the-importer-skips) for the
same ordering elsewhere). A typedef the prescan cannot yet finish — because
its element is a struct whose body import hasn't laid out yet, such as
`sigset_t` — is indistinguishable there from a name that was never a typedef,
so a **signature** naming it gets the plain `unknown type: sigset_t (did you
mean '__sigset_t'?)` rather than the message above. A **body** position,
reached after the import has actually run, resolves it correctly:
`(sizeof sigset_t)` is `128`, matching clang, even though `(defn f
(x:sigset_t):i32 ...)` is refused.

An array typedef is a storage type, just like the Nucleus `(array T N)`
spelling it now stands for, and is refused at the same positions with the same
message — see [Fixed-size arrays](types.md#fixed-size-arrays--array-t-n).
`(defn g (x:jmp_buf):i32 ...)` is refused as storage, not a value;
`(defvar env:jmp_buf)` and a struct field of that type are the legal
positions.

`--emit-cheader` does not add an `#include` for the header a rendered
typedef came from — unlike a type borrowed from another Nucleus unit (see
[`--emit-cheader`](compiler.md#compiler-flags)), a consumer of the generated
header is expected to `#include` the same C header itself.

## Declaration precedence: an explicit `declare` wins

When a unit contains both an explicit `(declare NAME …)` and a C header that
declares the same function, **the explicit declaration wins, whichever comes
first in the file**, and a signature mismatch warns naming both sources:

```
prog.nuc:2: warning: declaration of 'lseek' as i64 (i32, i64, i64) conflicts
with /usr/include/unistd.h:339, which declares it as i64 (i32, i64, i32);
the explicit declaration wins
```

Exactly one `declare` reaches the emitted module — LLVM rejects a second one for
the same symbol even when the two agree. If the explicit declaration follows the
import, it is emitted at the import's position rather than its own, so code
between the two still resolves the name.

Before this rule both orders were silent and disagreed with each other: whichever
came first won. The dangerous ordering is `import` then `declare`, where the
header quietly replaced the author's correct declaration.

A `declare` arriving from an imported `.nuch` header is not covered — its forms
are read during emission, too late to precede a C import — and keeps the older
first-wins behaviour.

The comparison is over the **rendered signature**, so a declaration that agrees
with the header is silent. Note that this only works if the declaration says what
you meant: write each parameter's type, named (`whence:i32`) or bare (`i32`) —
both carry it. See [`declare`](toplevel.md) for the parameter grammar.

## Declarations the importer skips

A C declaration the importer recognizes as a function but cannot faithfully
describe is **skipped**, never emitted. Two reporting tiers:

**Reported immediately, on stderr**, when the importer could not *parse* what the
header said:

```
/usr/include/foo.h:412: warning: skipping C declaration 'foo_apply': a by-value
'FooCtx' with no known layout
```

The warning names the **C header and the declaration's own line** (recovered from
`clang -E`'s linemarkers), not the `.nuc` file that imported it. It is always on —
there is no flag — and deduplicated by function name, so a header imported twice
or pulled in transitively by two others reports once. The volume is nil in
practice: `<stdio.h>`, `<stdlib.h>`, `<string.h>`, `<unistd.h>`, `<fcntl.h>`,
`<time.h>`, `<math.h>`, `<signal.h>`, `<pthread.h>`, `<netinet/in.h>`,
`<sys/stat.h>`, `png.h`, `SDL2/SDL.h` and `SDL2/SDL_mixer.h` each import with
zero such warnings.

**Reported at the point of use**, when the declaration parsed correctly but names
a type Nucleus has no equivalent for:

```
prog.nuc:12: error: unknown: 'wide' — its C header declaration was skipped
(/usr/include/thing.h:127: a by-value '__int128' (no Nucleus type is that wide))
```

These are irrelevant to a build that never calls the function, so warning about
each at import time would bury the tier above. Nothing is silent either way: the
reason, header and line are delivered exactly where they matter. This tier used
to be dominated by `long double` — ~30 entries from `<math.h>` alone, 165 across
everything `SDL2/SDL.h` pulls in — and FL-7 removed all of them.

A declaration is skipped when it has:

* a **by-value struct or union** parameter or return type with no known layout
  (an opaque tag, or a body the parser could not represent) — there is no LLVM
  type to name, and substituting a pointer would silently use the wrong ABI;
* a **`void` parameter** in a non-empty parameter list — never valid C, always a
  mis-parse, and the exact shape LLVM rejects with *"void type only allowed for
  function results"*;
* an **opaque** parameter or return type;
* a **by-value parameter or return whose type could not be resolved** — an
  unfollowable typedef, or a builtin Nucleus has no width for (`__int128`,
  `_BitInt`);
* **more than 32 parameters** (the importer's fixed parameter array), so a
  truncated signature is never registered;
* a **declarator shape the parser does not recognize at all** — a parenthesised
  declarator (`int (f)(int);`) is the canonical case. This one reports only at
  the point of use, since a preprocessed header is full of variables and macro
  remnants that legitimately take the same path, and a warning on every one of
  them would bury the tier above.

Skipping is a deliberate destination, not a failure mode: a program that gets 95%
of a header plus three named diagnostics is in far better shape than one that gets
`failed to parse generated IR` from the LLVM parser thousands of lines after the
import.

A **struct-by-value parameter or return that *is* representable** is lowered
through the same platform C ABI as a `defn` or a `.nuch` `declare` — so
`div`/`ldiv`/`lldiv` import as `declare i64 @div(i32, i32)` /
`declare { i64, i64 } @ldiv(i64, i64)`, and `fopencookie`'s 32-byte struct
parameter as `ptr byval(%cookie_io_functions_t) align 8`, matching what the call
site emits.

## Recognized libc function attributes: `noreturn` and `returns_twice`

A C header carries no attribute metadata the importer trusts — even an
explicit `__attribute__((noreturn))` is discarded — so a small set of
well-known libc functions is recognized **by name** instead and gets the
matching LLVM attribute on its `declare`: `exit`, `abort`, `_exit`, `_Exit`,
`quick_exit`, `abort_handler_s`, `longjmp` and `siglongjmp` get `noreturn` (a
statement-position call to one terminates its block, so a
`(when (= x null) (exit 1))` guard narrows the tested binding past it, exactly
as a call to a `noreturn` Nucleus `defn` does); `setjmp`, `_setjmp`,
`__sigsetjmp`, `sigsetjmp`, `savectx`, `vfork` and `getcontext` get
`returns_twice`. The setjmp family needs the by-name list for the same reason
`noreturn` does: `clang -E -x c -include setjmp.h /dev/null` contains **zero**
`returns_twice` annotations on glibc, because clang supplies the attribute
itself, treating these as compiler builtins. Without it, the optimizer may
turn a call into a `tail call`, which reuses the frame the later `longjmp`
needs to return into.

Three details are properties of **glibc's headers**, not of the compiler, and
matter to any program that calls into this family:

* **`setjmp` is a macro on glibc**, unconditionally: `#define setjmp(env)
  _setjmp (env)`. A C header import admits object-like integer-constant macros
  ([Integer constants from a C header](compiler.md#integer-constants-from-a-c-header))
  but never a **function-like** one, so a Nucleus `(setjmp env)` reaches the
  *function* `setjmp` — which is
  `__sigsetjmp(env, 1)` and additionally saves the signal mask — where C source
  spelling `setjmp(e)` reaches `_setjmp`, which does not. **Spell `_setjmp`
  explicitly to get C's behaviour.**
* **`sigsetjmp` is likewise `#define sigsetjmp(env, savemask) __sigsetjmp
  (env, savemask)`**; the callable symbol is `__sigsetjmp`.
* **`longjmp` already gets `noreturn`** from the list above, so a block
  containing a `longjmp` call ends there, same as any other `noreturn` call.

Both attributes are also **user-declarable** on a Nucleus `defn` — see
[Declaration attributes](toplevel.md#declaration-attributes). The by-name list
above is only how they are recovered for functions that arrive through a C
header, which carries nothing to read them from.

A local that must survive the jump needs `:volatile` — a `longjmp` does not
restore registers, so an optimizer-promoted local reads back its pre-jump
value otherwise. See [Volatile qualifier](types.md#volatile-qualifier).
`examples/setjmp-guard.nuc` is a full worked example: a `(defvar env:jmp_buf)`
storage declaration, `_setjmp`/`_longjmp` driving a retry loop, and a
`:volatile` counter that survives the jump — nothing here is writable through
any other combination of C header import features. The compiler's own REPL is
the second: `repl-protect` / `repl-throw` (`src/repl.nuc`) are the non-local
exit behind interactive error recovery, and replaced the last C file in the
tree.

One shape a *global* still cannot take: `(array SomeCStructTag N)`. A `defvar`'s
type is resolved by the global prescan, which runs before any `(import-use
"header.h")` is read, so the tag is still the layout-less placeholder
`cheader-prescan-opaque` registered and the array element is refused. A
`defvar` whose type is the C *typedef* (`(defvar env:jmp_buf)`) is unaffected,
because `emit-defvar` re-resolves it; and `(alloca (array Tag N))` inside a
function body is unaffected, because bodies are emitted after the import. That
is why `repl-protect` allocates its jump buffer in the frame rather than in a
static array.

## Unions and tagged sums

Stage 10 (`design/stage10/unions.md`) adds two layers: raw **untagged unions**
(C parity) and **tagged sums** (`defunion` + `match`) layered on them.

### Untagged `(union ...)`

`(union member:type ...)` is a type expression accepted wherever a type is
expected, mirroring the anonymous-struct form: size = max member size, align =
max member align, every member at offset 0. Like `(struct ...)` it is memoized
by structural content (`%__anon_union_h<16-hex>`). Named untagged unions come
from C headers; Nucleus code wraps the anonymous form in a `defstruct` field.

Member access goes through a pointer to the union and is a typed load/store at
offset 0 — reading a member other than the one last written is a
reinterpretation, exactly `unsafe/cast`'s contract (no checking; the raw frontier):

```lisp
(defstruct Scalar kind:i32 (data (union as-int:i64 as-float:f64)))
(let (s:ptr:Scalar (alloca Scalar)
      (d (ptr (union as-int:i64 as-float:f64))) (addr-of s 'data))
  (set! (d 'as-int) 42)
  (d 'as-int))
```

`abi-classify` extends to unions (every member classified at offset 0, classes
merged per SysV), and `sizeof`/layout agree with the platform C compiler
(gated by `make layout-test`).

**Function-pointer members are supported** — this is C's `actionf_t` idiom, one
slot shared by several function arities (the shape a state table carries in
every row). A member's type is a normal function-pointer type, so it may be
written in the canonical list form or with the colon-paren sugar, whose
parameter-list group must be *adjacent* to `(fn ret)` (see
[Function Pointer Types](types.md#function-pointer-types)):

```lisp
(defstruct Row
  tics:i32
  (action (union acv:(fn void)()          ; void (*)(void)
                 ac1:(fn i32)(ptr)        ; int (*)(void *)
                 n:i32)))                 ; ... sharing the slot with a scalar

(let (r:ptr:Row (alloca Row)
      (slot (ptr (union acv:(fn void)() ac1:(fn i32)(ptr) n:i32))) (addr-of r 'action))
  (set! (slot 'acv) some-void-fn)
  (funcall (slot acv)))
```

The union is one pointer wide, so it is bit-identical to the plain-`ptr`-field
alternative (`(unsafe/cast ptr some-fn)` stored, `funcall`ed back per call site)
— the union simply names each intended signature instead of re-deriving it at
every use. `--emit-cheader` renders it as an ordinary C `union { void* acv;
void* ac1; int32_t n; }` member, and `--emit-nuch` round-trips it as the
canonical nested form `((fn void) ())` with the same memoization hash.

A member position must be a `name:type` / `(name type)` declaration: a stray
empty list `()` there is a located error, not a crash. (Before Stage 15 W5f the
whole construct segfaulted the compiler at `defstruct` registration, because
`acv:(fn void)()` left the `()` dangling as an extra, null member.)

### `defunion` — tagged sums

```lisp
(defunion Shape
  (circle r:f64)
  (rect   w:f64 h:f64)
  point)                ; payload-less arm
```

Representation: a struct `{tag:i32, payload:(union ...)}`. Tags are assigned
in declaration order from 0 and are part of the C contract (`--emit-cheader`
exports the tagged struct plus an `enum Shape_tag` of constants). Each arm's
payload is the single field's type, or a memoized anonymous struct of the
fields. By-value passing/returning rides the stage-8 struct ABI.

**Constructors** are generated ordinary functions named `Union-arm`:
`(Shape-circle 2.0)`, `(Shape-point)` — value-returning, no allocation.
`(make Shape rect 3.0 4.0)` is the equivalent explicit form (and the only
spelling for template instances, below). The arm names themselves are not
bound (one-symbol-one-kind); only the prefixed constructors are.

**No raw access outside `match`**: the tag and payload are not readable as
fields (`(s 'tag)` is an error directing you to `match`); the escape hatch is
an explicit `unsafe/cast` to the representation struct.

### `match`

```lisp
(match s
  ((circle r)   (* 3.14159 (* r r)))
  ((rect w h)   (* w h))
  (point        0.0))
```

- One-level patterns: `(arm binders...)`, a bare arm name for payload-less
  arms, or `_` as a default arm. Binders are positional; `_` ignores a field.
- A plain binder binds the payload field **by value**. A `(ref x)` binder
  binds `x:(ref field-type)` aliasing the field in place for mutation
  (requires a pointer scrutinee): `((circle (ref r)) (set! (deref r) (* @r 2.0)))`.
- **Exhaustiveness**: without `_`, covering every arm is required; a missing
  arm is a compile error naming it. Adding an arm breaks every defaultless
  `match` loudly.
- The whole form is a value expression with `cond`'s strict cross-branch
  typing and void-collapse rules. Lowers to `case`/LLVM `switch` on the tag;
  an exhaustive match emits no default clause (a corrupted tag is UB, the C
  contract).
- Scrutinee: a `defunion` value or a `ptr`/`ref` to one (auto-deref for the
  tag read). Also works over a `defenum` scrutinee with bare member names as
  patterns and the same exhaustiveness rule.

### Templates: `(defunion (Result T E) ...)`

A parameterized head declares a **template**; it defines no type by itself. A
fully-applied use stamps and memoizes a concrete instance:

```lisp
(defunion (Result T E)
  (ok  v:T)
  (err e:E))

(defn try-div (a:i64 b:i64) (Result i64 i32)
  (when (= b 0)
    (return (err 1)))          ; return-position target typing
  (return (ok (/ a b))))

(let ((r (Result i64 i32)) (try-div x y))
  (match r
    ((ok v)  ...)
    ((err e) ...)))
```

Substitution is purely syntactic (use sites are explicit; no inference).
Construction is via `(make (Result i64 i32) ok v)` or **target typing**: in
`return` position of a function declared to return a `defunion` (or template
instance), a bare `(arm args...)` resolves against the declared type. The
rewrite applies only to the directly returned form, not through `if`/`cond`
branches. The `name:(Type ...)` colon-paren sugar works for parenthesized
types — `r:(Result i64 i32)` (and the chain form `r:ref:(…)`) read directly
in binding positions, equivalent to the list form `(name (Result i64 i32))`.

`.nuch` headers export `defunion` forms verbatim (template or monomorphic);
importers re-register the type — under the header's own namespace, so a union
declared in `(ns shapes)` is imported as `shapes/Opt` and its arm constructors
link against `@shapes__Opt-Some`, exactly as compiling that library's `.nuc`
source would give you — and stamp their own instances. `--emit-cheader`
exports monomorphic defunions as the tagged struct + tag enum; functions whose
signatures mention template instances are skipped with a comment (no C
spelling for instances yet).

**Drop interaction**: a `with`-owned binding of a tagged union whose arms hold
`Drop`-conforming payloads is a compile error (freeing the box would leak the
live arm) unless the union itself conforms to `Drop` — write the tag switch
in its `drop` method with `match`.

### Niche layout and `:repr` (Stage 10 C4)

The layout engine applies four rules in strict order to decide a `defunion`'s
representation:

| Rule | Arms shape | Layout | C type | Nucleus type |
|---|---|---|---|---|
| 1 | All arms payload-less | `i32` tag only (≅ `defenum`) | `int32_t` | direct tag value |
| 2 | Two arms: one payload-less + one single `(ref T)` field | bare pointer, `null` = payload-less arm | `T*` | `(Maybe (ref T))` / `?ptr:T` |
| 3 | Two arms: one single `(ref T)` field + one single `Err` field | bare pointer, ERR_PTR encoding | `T*` (reserved top-page range) | `(Result (ref T) Err)` / `!ptr:T` |
| 4 | Everything else | `{i32 tag; union payload}` tagged struct | tagged struct + enum constants | `(Result T E)`, multi-arm, etc. |

Rules are applied in order; the first that matches wins. Niche rules (2 and 3)
require the `(ref T)` payload to name a concrete pointee type — an elem-less
bare `ptr` does not qualify and the union falls through to rule 4.

**ERR_PTR encoding (rule 3).** `(ok p)` stores the `(ref T)` pointer `p`
directly. `(err E)` encodes the error id as `inttoptr(0 - id)`, placing it in
the top page of the address space (ids 1–4095, ensured by `deferror`'s cap).
`is-err` is a single unsigned compare: `ptrtoint(p) >= (0 - 4096)`. A valid
object address is never in the top page, so the two ranges never overlap. The
whole niche-ERRPTR value is ABI-identical to a `T*` — no discriminant word, no
struct wrapper; `sizeof(!ptr:T) == sizeof(T*)`.

**`:repr` attribute.** An optional trailing `:repr mode` in a `defunion` arm
list overrides the automatic rule selection:

```lisp
; Force the tagged struct even for two-arm pointer shapes (e.g. when a C
; consumer constructs the union directly and needs the predictable layout).
(defunion (MaybeRef T)
  (some v:(ref T))
  none
  :repr tagged)

; Require a niche — compile error if the arms are not nicheable.
(defunion (Nullable T)
  (ok  v:(ref T))
  (err e:Err)
  :repr niche)
```

- `:repr tagged` — always produce rule-4 layout regardless of arm shapes.
- `:repr niche` — require niche layout; die at compile time if the arms do not
  qualify (error: "arms are not nicheable").
- No `:repr` marker — automatic: apply rules 1–4 in order.

**All elimination forms are representation-transparent.** `match`, `try`,
`unwrap`, and `unwrap-or` all accept a niche-layout value and dispatch on the
correct encoding automatically. User code does not need to know which rule
applies.

```lisp
(import-use "stdio.h")
(import-use "stdlib.h")
(import-use error)
(defstruct Pt x:i32 y:i32)
(deferror not-found "point not found")

; !ptr:Pt is (Result (ref Pt) Err) via rule 3: pointer-sized, no struct.
(defn lookup (p:ptr:Pt good:i32):!ptr:Pt
  (when (= good 0) (return (err not-found)))
  (return (ok (as ref:Pt p))))

(defn main ():i32
  (let (pt:ptr:Pt (as ptr:Pt (malloc (sizeof Pt))))
    (set! (pt 'x) 42)
    (match (lookup pt 1)
      ((ok q)  (printf "ok x=%d\n" (q 'x)))
      ((err e) (printf "err: %s\n" (err-name e))))
    (free pt))
  0)
```

See also `examples/errptr.nuc`.

## Parametric struct templates: `(defstruct (Name T ...) ...)`

Stage 11 adds parametric struct templates — the struct analogue of `defunion`
templates. A `defstruct` whose name position is a **list** registers a template;
it defines no type and emits no IR until used. A **type application** in type
position stamps a concrete monomorphic instance.

### Defining a template

```lisp
(defstruct (Vector T)
  data:(ptr T)
  len:usize
  cap:usize)

(defstruct (Pair K V)
  key:K
  val:V)
```

The parameters are bare type symbols. A single-element name list `(Foo)` (no
type parameters) is an error — use a plain `defstruct`. Type parameters are
types only; value/const parameters (e.g. a compile-time array length) are not
supported.

### Type application

`(Name T ...)` in **type position** stamps a concrete monomorphic struct named
`Name.T` (dot-separated, using the same `type-mangle-token` scheme as union
instances and overloaded-fn mangling). Stamping is memoized: `(Vector i32)` in
multiple locations produces the same `StructDef`.

Type application is recognized in type position only — after `:`, in field
types, `defn` parameter and return types, `as`/`unsafe/cast` targets, `sizeof`
operands, and `alloca`/`array` element types. The colon sugar composes:

```lisp
(defn count (self:(ref (Vector T))):usize
  (return (self 'len)))

(defstruct Tree
  val:i32
  left:(ptr (Tree i32))   ; pointer self-reference — fine
  right:(ptr (Tree i32)))
```

A template that embeds its own instance **by value** is an infinite layout error
(the same rule plain structs enforce). A pointer self-reference stamps without
issue: `register-struct` reserves the name before fields are filled.

### Construction

Value-position construction uses the **explicit two-level form**: the inner
`(Name T ...)` stamps the concrete type, and the outer application is an
ordinary compound literal over that instance:

```lisp
((Vector i32) data len cap)     ; builds a Vector.i32 value
((Pair CStr i32) k v)           ; builds a Pair.CStr.i32 value
```

A **bare `(Vector v0 v1 ...)` in value position is a compile error** for a
template name — it is ambiguous (is `v0` a type argument or the first field?)
and the diagnostic points at the explicit two-level form.

The colon binding sugar now works when the RHS is a parenthesized type:
`name:(ref (Vector T))` fuses in the reader, and the chain form
`name:ref:(Vector T)` works too — both equivalent to the list binding form
`(name (ref (Vector T)))`. (Earlier this did not tokenize; the Stage 14
colon-paren fuse closed that gap.)

### Methods over a template

A `defn` whose parameter or return type mentions a registered struct template
applied to free symbols infers those symbols as the method's type variables —
bound by the parametric receiver, not by `:where`. The body is monomorphized
once per distinct concrete receiver type, reusing the rung-4 monomorphizer.

```lisp
(defn count (self:(ref (Vector T))):usize
  (return (self 'len)))

(defn push ((self (ref (Vector T))) x:T):void
  ; ... grow if needed, store x, increment len
  )
```

The method call `(count v)` with `v:(ref Vector.i32)` resolves to a direct
`call` (inlinable, zero dispatch overhead). Field access `(v 'len)` on a stamped
instance is a static GEP+load — byte-identical to any hand-written struct.

`:where` remains available for **extra bounds** on the type variable:
`:where (T Ord)` constrains `T` beyond what the receiver alone asserts.

A receiver type variable is bound **positionally** from the stamped receiver, so
a template's trailing type parameters that appear in **no field** ("phantom"
params) are still recovered and may be named in a method's signature — including
its return type:

```lisp
; S and E appear in no field; they are bound positionally from the receiver.
(defstruct (Two I F S E) a:I b:F)

(defn two-s ((self (ref (Two I F S E)))):S   ; returns the 3rd type-argument
  (return (unsafe/cast S (self 'a))))
```

A call `(two-s t)` with `t:(ref (Two i32 f64 i32 i64))` binds `S := i32` from the
third receiver type-argument. This makes the verbose "thread an explicit element
type" combinator pattern (e.g. a `MapIter I F S E` carrying source/result element
types as phantom params) expressible with a single implementation. Associated types
(A0–A4, see [Generics](generics.md#associated-type-bounds-where-protocol-arg--var))
supersede this pattern for new code: the two-param `(MapIter I F)` recovers the
element type via `:where` constraints on `extend`, requiring no phantom params.
The four-param verbose form is kept as a regression test
(`examples/phantom-tyvar-test.nuc`) but is not the recommended approach.

### `.nuch` export and C ABI

A stamped instance is an ordinary monomorphic `TY-STRUCT`: the Stage 8 SysV
classifier (`abi-classify`) applies unchanged. By-value parameters and return
values work with no special handling.

`.nuch` export emits the template verbatim (`(defstruct (Vector T) ...)`);
importers re-register the template and re-stamp instances on demand. Concrete
instances are not serialized into the header (same precedent as union templates;
re-stamping reproduces an identical layout). Methods export through the existing
rung-4 generic `defmethod` / monomorphization machinery.

C-legible names: `--emit-cheader` maps dots (and any non-`[A-Za-z0-9_]`
character) to `_` via `sanitize-for-c` (`src/cheader.nuc`), so `Vector.i32`
exports as `Vector_i32`. LLVM IR keeps the dotted name (dots are legal in IR).

A `declare` with a parametric return type puts it after the parameter list,
as a list or attached: `(declare p2_make (...) (P2 i32 i32))` or
`(declare p2_make (...):(P2 i32 i32))`; the legacy name node
`(declare (p2_make (P2 i32 i32)) ...)` is refused.

See also `examples/parametric.nuc`, `examples/import-parametric.nuc`, and
`tests/abi/interop.nuc`.
