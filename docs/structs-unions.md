# Structs and Unions

## Anonymous structs

`(struct field:type ...)` is a type expression accepted wherever a type is expected — `let` bindings, `defn` parameter and return types, `defstruct` field types, `(ptr (struct ...))`, `as`/`unsafe/cast` targets. Members use the same `name:type` / `(name type)` form as `defstruct`. Anonymous structs are **memoized by structural content**: two `(struct ...)` literals with the same field name+type list share a single underlying `StructDef`, so values flow between sites that spell out the same shape. The synthetic LLVM type name is `%__anon_struct_h<16-hex>`, derived from a 64-bit FNV-1a hash of the field list.

Examples:

- `(let ((p (ptr (struct x:i32 y:i32))) (alloca (struct x:i32 y:i32))) ...)` — local of anonymous-struct shape
- `(defstruct Outer (pt (struct x:i32 y:i32)) tag:i32)` — nested by value
- `(defn take ((p (ptr (struct x:i32)))):i32  ...)` — parameter typed as anonymous struct pointer

Use `(.& obj field)` to obtain a pointer to a field without loading it. Result is typed `(ptr field-type)`, so it composes with `.set!`, `deref`, and further `.&` calls — e.g. `(.set! (.& o point) x 10)` writes through a value-typed nested struct field.

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
  (+ (aref (r cells) 0) (aref (r cells) 1)))
```

Consequently an array field cannot be assigned as a whole (`(.set! r cells …)`
is refused, as `s.xs = …` is in C); write through the decayed pointer with
`aset!`, or copy with `memcpy`. `(.& r cells)` gives the same address as
`(r cells)`.

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

A struct used directly (not behind `ptr`) as a `defn`/`declare` parameter or return type is passed/returned per the **platform C ABI**, so it interoperates correctly with C functions compiled by the system `cc`. On x86_64 System V this means small structs are coerced into registers (e.g. `{i32,i32}` → one `i64`; a struct with a `float` field whose eightbyte also holds an integer → `i64`), and structs larger than 16 bytes are passed `byval` / returned via a hidden `sret` pointer. aarch64, `avr`, and `riscv64` instead pass every `ABI-MEMORY`-classified struct as a plain pointer (no `byval` — none of those targets' ABIs has that attribute); on `avr` this applies to **every** struct/union regardless of size, not just those over 16 bytes, because the SysV eightbyte classifier's register-sized-chunk model has no counterpart on an 8-bit target — `abi-classify` bypasses eightbyte classification for `avr` entirely rather than adapting it. On `riscv64` (lp64d), struct-by-value follows the psABI's **hard-float** rules. An aggregate is first *flattened*: nested structs and arrays expand recursively into their scalar members, and a union never flattens. If the flattened list is exactly one FP real, two FP reals, or one FP real plus one integer ≤ XLEN **in either order**, the value travels in FP registers with its members' own IR types and offsets — `struct {float f;}` → `float`, `struct {double a,b;}` → `{double,double}`, `struct {float v[2];}` → `{float,float}` (two separate FPRs, where x86_64 SysV packs the same struct into one `<2 x float>` eightbyte), `struct {i32 i; f32 f;}` → `{i32,float}`, `struct {f32 f; i32 i;}` → `{float,i32}`. This applies only while the registers the rule needs are still free at that argument position: the budget is fa0-fa7 and a0-a7, an `ABI-MEMORY` return spends one of the latter on its hidden `sret` pointer, and every argument in a call or parameter list is charged in declaration order. Anything that does not qualify — three or more flattened members, a union, an over-wide member, a **variadic** argument (the `...` tail always uses the integer convention, with no flattening and no FP registers), or exhausted registers — falls back to the integer convention, coercing a struct ≤ 16 bytes into integer registers (`i64` / `{i64,i64}`). Returns are classified against a0/a1/fa0/fa1, which are always available, so a return never falls back for want of registers. A struct value is produced by dereferencing a pointer (`@p`) and consumed by storing the call result (`(ptr-set! q (make ...))`); field *access* still requires a pointer (`(. p f)` needs `p : (ptr S)`), so to read fields of a by-value struct parameter, first store it: `(let (q:ptr:S (alloca S)) (ptr-set! q p) (. q f))`. A function may take or return a struct defined anywhere in the same compilation unit or an import — struct definitions are registered before function signatures are resolved.

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
  (aset! tbl 1 (P 10 11)))                     ; element store
```

The same applies to `set!`, `ptr-set!`, `.set!`, union-variant construction, and
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

C headers consumed via `(import-use "foo.h")` or `(import "foo.h" prefix)` now register their `struct Foo { ... };` and `typedef struct { ... } Bar;` definitions as Nucleus structs with the same name. Anonymous inline struct fields are registered as memoized anonymous structs (same `__anon_struct_h<hex>` machinery). Pass-by-value parameters typed as a C struct work through this path. `union { ... }` fields, named unions, and `typedef union` are registered as untagged union types (see [Untagged `(union ...)`](#untagged-union-)); headers like SDL's or pthread's no longer degrade over them. Field types that the parser cannot represent yet (arrays, bitfields, multi-declarator lines like `int a, b;`) cause the whole struct to be skipped — it becomes an **opaque type** (below) rather than a layout-incompatible partial struct.

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

A type stays opaque either because no header in the translation unit defines it,
or because its definition uses a construct the C declaration parser cannot
represent (bitfields, arrays, multi-declarator lines) — `FILE` is the second
kind, and SDL's `SDL_GUID` (`struct { Uint8 data[16]; }`) is another. Both are
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

## Typedefs in imported declarations

A C `typedef` of a scalar, pointer, function pointer or enum resolves to the type
it names, **transitively**:

```c
typedef long int __off_t;
typedef __off_t  off_t;          /* off_t -> __off_t -> long int -> i64 */
typedef unsigned char Uint8;     /* -> ui8  */
typedef unsigned int  Uint32;    /* -> ui32 */
typedef char        *string_t;   /* -> ptr  */
typedef int   (*handler)(int);   /* -> ptr  */
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
machine word. In practice the unrepresentable set is `long double`, `_Float128`,
`_Float16`, an array typedef (`typedef int v4[4];`), and a typedef of a struct
whose body the parser could not read.

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
prog.nuc:12: error: unknown: 'strtold' — its C header declaration was skipped
(/usr/include/stdlib.h:127: a by-value 'long double' (no Nucleus type is that
wide))
```

These are common and irrelevant to a build that never calls the function —
`<math.h>` alone contributes ~30 `long double` entries, and importing
`SDL2/SDL.h` reaches 165 across everything it pulls in — so warning about each at
import time would bury the tier above. Nothing is silent either way: the reason,
header and line are delivered exactly where they matter.

A declaration is skipped when it has:

* a **by-value struct or union** parameter or return type with no known layout
  (an opaque tag, or a body the parser could not represent) — there is no LLVM
  type to name, and substituting a pointer would silently use the wrong ABI;
* a **`void` parameter** in a non-empty parameter list — never valid C, always a
  mis-parse, and the exact shape LLVM rejects with *"void type only allowed for
  function results"*;
* an **opaque** parameter or return type;
* a **by-value parameter or return whose type could not be resolved** — an
  unfollowable typedef, or a builtin Nucleus has no width for (`long double`,
  `_Float128`);
* **more than 32 parameters** (the importer's fixed parameter array), so a
  truncated signature is never registered.

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
      (d (ptr (union as-int:i64 as-float:f64))) (.& s data))
  (.set! d as-int 42)
  (d as-int))
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
      (slot (ptr (union acv:(fn void)() ac1:(fn i32)(ptr) n:i32))) (.& r action))
  (.set! slot acv some-void-fn)
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
fields (`(s tag)` is an error directing you to `match`); the escape hatch is
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
  (requires a pointer scrutinee): `((circle (ref r)) (ptr-set! r (* @r 2.0)))`.
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

### Niche layout and `&repr` (Stage 10 C4)

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

**`&repr` attribute.** An optional trailing `&repr mode` in a `defunion` arm
list overrides the automatic rule selection:

```lisp
; Force the tagged struct even for two-arm pointer shapes (e.g. when a C
; consumer constructs the union directly and needs the predictable layout).
(defunion (MaybeRef T)
  (some v:(ref T))
  none
  &repr tagged)

; Require a niche — compile error if the arms are not nicheable.
(defunion (Nullable T)
  (ok  v:(ref T))
  (err e:Err)
  &repr niche)
```

- `&repr tagged` — always produce rule-4 layout regardless of arm shapes.
- `&repr niche` — require niche layout; die at compile time if the arms do not
  qualify (error: "arms are not nicheable").
- No `&repr` marker — automatic: apply rules 1–4 in order.

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
    (.set! pt x 42)
    (match (lookup pt 1)
      ((ok q)  (printf "ok x=%d\n" (q x)))
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
  (return (self len)))

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
bound by the parametric receiver, not by `&where`. The body is monomorphized
once per distinct concrete receiver type, reusing the rung-4 monomorphizer.

```lisp
(defn count (self:(ref (Vector T))):usize
  (return (self len)))

(defn push ((self (ref (Vector T))) x:T):void
  ; ... grow if needed, store x, increment len
  )
```

The method call `(count v)` with `v:(ref Vector.i32)` resolves to a direct
`call` (inlinable, zero dispatch overhead). Field access `(v len)` on a stamped
instance is a static GEP+load — byte-identical to any hand-written struct.

`&where` remains available for **extra bounds** on the type variable:
`&where (T Ord)` constrains `T` beyond what the receiver alone asserts.

A receiver type variable is bound **positionally** from the stamped receiver, so
a template's trailing type parameters that appear in **no field** ("phantom"
params) are still recovered and may be named in a method's signature — including
its return type:

```lisp
; S and E appear in no field; they are bound positionally from the receiver.
(defstruct (Two I F S E) a:I b:F)

(defn two-s ((self (ref (Two I F S E)))):S   ; returns the 3rd type-argument
  (return (unsafe/cast S (self a))))
```

A call `(two-s t)` with `t:(ref (Two i32 f64 i32 i64))` binds `S := i32` from the
third receiver type-argument. This makes the verbose "thread an explicit element
type" combinator pattern (e.g. a `MapIter I F S E` carrying source/result element
types as phantom params) expressible with a single implementation. Associated types
(A0–A4, see [Generics](generics.md#associated-type-bounds-where-protocol-arg--var))
supersede this pattern for new code: the two-param `(MapIter I F)` recovers the
element type via `&where` constraints on `extend`, requiring no phantom params.
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

**Known limitation (`.nuch` consumer):** when a `declare` form has a
parametric return type, the list-form name node is required:
`(declare p2_make (...) (P2 i32 i32))`.

See also `examples/parametric.nuc`, `examples/import-parametric.nuc`, and
`tests/abi/interop.nuc`.
