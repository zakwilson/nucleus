# Structs and Unions

## Anonymous structs

`(struct field:type ...)` is a type expression accepted wherever a type is expected — `let` bindings, `defn` parameter and return types, `defstruct` field types, `(ptr (struct ...))`, casts. Members use the same `name:type` / `(name type)` form as `defstruct`. Anonymous structs are **memoized by structural content**: two `(struct ...)` literals with the same field name+type list share a single underlying `StructDef`, so values flow between sites that spell out the same shape. The synthetic LLVM type name is `%__anon_struct_h<16-hex>`, derived from a 64-bit FNV-1a hash of the field list.

Examples:

- `(let ((p (ptr (struct x:i32 y:i32))) (alloca (struct x:i32 y:i32))) ...)` — local of anonymous-struct shape
- `(defstruct Outer (pt (struct x:i32 y:i32)) tag:i32)` — nested by value
- `(defn take:i32 ((p (ptr (struct x:i32))))  ...)` — parameter typed as anonymous struct pointer

Use `(.& obj field)` to obtain a pointer to a field without loading it. Result is typed `(ptr field-type)`, so it composes with `.set!`, `deref`, and further `.&` calls — e.g. `(.set! (.& o point) x 10)` writes through a value-typed nested struct field.

## Passing and returning structs by value

A struct used directly (not behind `ptr`) as a `defn`/`declare` parameter or return type is passed/returned per the **platform C ABI**, so it interoperates correctly with C functions compiled by the system `cc`. On x86_64 System V this means small structs are coerced into registers (e.g. `{i32,i32}` → one `i64`; a struct with a `float` field whose eightbyte also holds an integer → `i64`), and structs larger than 16 bytes are passed `byval` / returned via a hidden `sret` pointer. Other targets' ABIs are not yet implemented (see `design/stage8/platform.md`). A struct value is produced by dereferencing a pointer (`@p`) and consumed by storing the call result (`(ptr-set! q (make ...))`); field *access* still requires a pointer (`(. p f)` needs `p : (ptr S)`), so to read fields of a by-value struct parameter, first store it: `(let (q:ptr:S (alloca S)) (ptr-set! q p) (. q f))`. A function may take or return a struct defined anywhere in the same compilation unit or an import — struct definitions are registered before function signatures are resolved.

## C header struct ingestion

C headers consumed via `(include foo)` or `(import "foo.h")` now register their `struct Foo { ... };` and `typedef struct { ... } Bar;` definitions as Nucleus structs with the same name. Anonymous inline struct fields are registered as memoized anonymous structs (same `__anon_struct_h<hex>` machinery). Pass-by-value parameters typed as a C struct work through this path. `union { ... }` fields, named unions, and `typedef union` are registered as untagged union types (see [Untagged `(union ...)`](#untagged-union-)); headers like SDL's or pthread's no longer degrade over them. Field types that the parser cannot represent yet (arrays, bitfields, multi-declarator lines like `int a, b;`) cause the whole struct to be skipped — registered as opaque `ptr` at use sites — rather than registering a layout-incompatible partial struct.

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
reinterpretation, exactly `cast`'s contract (no checking; the raw frontier):

```lisp
(defstruct Scalar kind:i32 (data (union as-int:i64 as-float:f64)))
(let (s:ptr:Scalar (alloca Scalar)
      (d (ptr (union as-int:i64 as-float:f64))) (.& s data))
  (.set! d as-int (cast i64 42))
  (d as-int))
```

`abi-classify` extends to unions (every member classified at offset 0, classes
merged per SysV), and `sizeof`/layout agree with the platform C compiler
(gated by `make layout-test`).

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
an explicit `cast` to the representation struct.

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

(defn (try-div (Result i64 i32)) (a:i64 b:i64)
  (when (= b (cast i64 0))
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
branches. Note that the `name:(Type ...)` colon sugar does not parse for
parenthesized types — use the list form `(name (Result i64 i32))` in binding
positions.

`.nuch` headers export `defunion` forms verbatim (template or monomorphic);
importers re-register the type and stamp their own instances. `--emit-cheader`
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
(include stdio)
(include stdlib)
(import error)
(defstruct Pt x:i32 y:i32)
(deferror not-found "point not found")

; !ptr:Pt is (Result (ref Pt) Err) via rule 3: pointer-sized, no struct.
(defn lookup:!ptr:Pt (p:ptr:Pt good:i32)
  (when (= good 0) (return (err not-found)))
  (return (ok (cast ref:Pt p))))

(defn main:i32 ()
  (let (pt:ptr:Pt (cast ptr:Pt (malloc (sizeof Pt))))
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
types, `defn` parameter and return types, `cast` targets, `sizeof` operands, and
`alloca`/`array` element types. The colon sugar composes:

```lisp
(defn count:usize (self:(ref (Vector T)))
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

**Known limitation:** the colon binding sugar does not work when the RHS is a
parenthesized type: `name:(ref (Vector T))` does not tokenize. Use the list
binding form instead: `(name (ref (Vector T)))`. This is a pre-existing
tokenizer limitation (not specific to parametric structs).

### Methods over a template

A `defn` whose parameter or return type mentions a registered struct template
applied to free symbols infers those symbols as the method's type variables —
bound by the parametric receiver, not by `&where`. The body is monomorphized
once per distinct concrete receiver type, reusing the rung-4 monomorphizer.

```lisp
(defn count:usize (self:(ref (Vector T)))
  (return (self len)))

(defn push:void ((self (ref (Vector T))) x:T)
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

(defn two-s:S ((self (ref (Two I F S E))))   ; returns the 3rd type-argument
  (return (cast S (self a))))
```

A call `(two-s t)` with `t:(ref (Two i32 f64 i32 i64))` binds `S := i32` from the
third receiver type-argument. This makes the verbose "thread an explicit element
type" combinator pattern (e.g. a `MapIter I F S E` carrying source/result element
types as phantom params) expressible with a single implementation.

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
`(declare (p2_make (P2 i32 i32)) (...))`.

See also `examples/parametric.nuc`, `examples/import-parametric.nuc`, and
`tests/abi/interop.nuc`.
