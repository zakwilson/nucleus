# Type System

## Type Syntax and Desugar

Types are attached to names with `:` syntax: `name:type` (e.g., `x:i32`, `main:int`). A desugar pass runs before compilation, splitting colon-typed symbols in binding positions into canonical list form:

- `foo:int` → `(foo int)` — name and type as separate symbols
- `node:ptr:Node` → `(node (ptr Node))` — pointer-to-Node
- `pp:ptr:ptr:Node` → `(pp (ptr ptr Node))` — pointer-to-pointer-to-Node

Pointers to a typed element use the `ptr` constructor: `(ptr T)` is a **non-null** pointer to `T`, and `(ptr ptr T)` chains. Bare `ptr` (with no element) is the opaque `void*` pointer — it carries no element contract, so non-null obligations do not apply to it.

Because bare `ptr` erases the element type, operations that need one (`aref`, `aset!`, `deref`, `unsafe/ptr+`, field access) reject it. The one place the element type is recovered automatically is an **`(array T …)` initializer**: `(let (a:ptr (array i32 1 2 3)) (aref a 1))` binds `a` as `ptr:i32`, because the element type is spelled in the initializer itself. This is deliberately limited to that syntactic form — a bare `:ptr` bound from anything else (a function result, `alloca`, `addr-of`) stays elem-less, since erasing the element type is exactly what a `void*` annotation is for. Where you want the element type from any other initializer, either spell it (`a:ptr:i32`) or omit the annotation entirely (a bare binding name adopts the initializer's full type).

In inline type positions (the type argument of `as`/`unsafe/cast`, `sizeof`, `alloca`), either the canonical list form or the colon sugar works: `(unsafe/cast (ptr Node) x)` and `(unsafe/cast ptr:Node x)` are equivalent.

**Colon-paren binding sugar.** A binding's type may also be a parenthesised form written directly after the colon, with no space: `name:(ref (Vector T))`, `v:(ptr u8)`, `f:(fn i32)(i32 i32)`. In list (binding) context the reader fuses a trailing-colon atom that is *immediately* followed by `(` into the canonical list node `(name <paren-form>)`. So `v:(ref (Vector i32))` is exactly `(v (ref (Vector i32)))`, in both parameter lists and `let` bindings. The fusion only fires when the colon is the last character of the atom and the very next character is `(` (no whitespace); a mid-colon symbol such as `foo:i32` is unaffected.

**Function-pointer types take a second, adjacent group.** A function pointer type is *two* parenthesised groups — `(fn ret)` and its parameter list — so the colon-paren fuse absorbs one more group when the first is `(fn …)`-headed **and the next character is `(` with no space**: `f:(fn i32)(i32 i32)` reads as `(f ((fn i32) (i32 i32)))`, and `acv:(fn void)()` (the zero-parameter case) as `(acv ((fn void) ()))`. Adjacency is required, exactly as for the first group — a *space*-separated second group is genuinely ambiguous with the next binding in the enclosing list (in `(f:(fn i32) (i32 i32) a:i32)` nothing distinguishes the parameter list from a `(name type)` binding), so it is not absorbed and `f` would be typed as a zero-parameter function pointer. `name:(fn ret)` with no following group is a *zero-parameter* function pointer, which is well-defined and useful (C's `ret (*)(void)`); it is only a mistake when you meant to give it parameters.

The corollary, since absorption is driven purely by adjacency: **put a space between a `(fn ret)` type and a parenthesised initializer.** `(let (f:(fn i32) (choose)) …)` binds `f` to the result of `(choose)`; written without the space, `(choose)` is absorbed as the type's parameter list and the binding list is left with an odd element count (a located `let: binding list must be even`). This is the same discipline the first group already requires — an adjacent `(` after a trailing colon always belongs to the type.

**Colon-chain fuse.** A colon chain ending in a paren also works: `name:k1:…:kN:(T …)` reads as `(name (k1 (… (kN (T …)))))`. The first segment is the binding name; each remaining segment wraps the paren form right-to-left as a unary constructor application — e.g. `v:ref:(Vector i32)` → `(v (ref (Vector i32)))`, `p:ptr:ptr:(fn i32)` → `(p (ptr (ptr (fn i32))))`. (The reader does not validate that segments are pointer-kind constructors — `a:Foo:(T)` fuses to `(a (Foo (T)))` and the type parser rejects the unknown segment naturally. An empty interior segment `a::(T)` is a reader error.) This applies to a parametric *return* type on a `defn` name too: `make-vec:ref:(Vector ptr)` reads as `(make-vec (ref (Vector ptr)))`. Either the colon-chain sugar or the canonical list form works in every binding position.

**Return-position lone-colon fuse.** A bare `:` immediately before `(` fuses to the paren form itself, with no name, so a parenthesised return type in `fn`/`defn`/lambda position may be written `):(T …)`. Thus `(fn (x:i32):(ref T) …)` reads as `(fn (x:i32) (ref T) …)`, and a keyword with a trailing colon followed by `(` fuses too (`:ptr:(Vector T)` → `(ptr (Vector T))`). This makes parenthesised returns use the same colon discipline as scalar returns — no space-separated exception is required.

**Whitespace near-miss.** Adjacency remains **required**: the sigil binds tight (matching `:keyword` lexing; fusing across whitespace could rewrite quoted data at a distance). If a binding name ends in `:` but is *not* adjacent to `(` — e.g. `x: (raw Node)` — the compiler reports a clear fatal error: `binding name ends in ':' (<atom>) -- write name:(Type) with no space, or (name Type)`. Write `name:(Type …)` with no space, or the canonical list form `(name Type …)`. A trailing-colon symbol in value or quoted positions stays legal.

**Quoted-data caveat.** The fuse fires syntactically, whether or not the form is quoted — so `'(foo:(bar))` reads as `'((foo (bar)))`. Authors of quoted data (or data that will be `read` at runtime) should space the paren: `'(foo: (bar))` or `'(foo (bar))`.

Desugar operates on binding positions in `defn`, `defvar`, `defstruct`, `extern`, `declare`, and `let`. Expression bodies are not desugared; typed symbols in value position (e.g., from macro expansion) are handled by the compiler directly.

Both the sugared `:` syntax and the canonical list form are accepted in all binding positions. Macros that manipulate types can work with the canonical list form; macros that don't care about types can use the `:` sugar and it will be desugared before compilation.

**Multi-binding `let`.** A single `let` accepts any number of name/init pairs in one flat binding list — both `:` sugar and list forms compose freely in the same binding list:

```lisp
(let ((a (ref AllocHandle)) (alloca AllocHandle)
      (v (ref (Vector i32))) (alloca (Vector i32))
      n:i32 7)
  ...)
```

The bindings are established in order (left to right); each init expression may reference names introduced earlier in the same list.

Macro output is desugared before compilation, so macro-generated code can use either form.

## Namespaced type names

**A `defstruct`, `defunion`, `defenum` or struct/union template defined inside `(ns n)` is keyed `n/Type`**, exactly like a `defn` or `defvar` declared there — see [`ns`](toplevel.md) and [What an import brings into scope](toplevel.md#what-an-import-brings-into-scope). Two namespaces may each define a type of the same name; they are two distinct types. Type identity (what `type-eq` checks for a struct or union) compares the underlying `StructDef`/`UnionDef` by pointer, so `(ns a) (defstruct Vector …)` and `(ns b) (defstruct Vector …)` are unrelated even when their field lists happen to match: distinct layouts, distinct field-access diagnostics (`no field 'c' on struct 'a/Vector'`), and distinct protocol conformances — extending `a/Vector` does not extend `b/Vector`.

A type reference resolves through the writing file's own import environment exactly like any other name, per the table in [What an import brings into scope](toplevel.md#what-an-import-brings-into-scope): `(import-prefixed lib p)` makes the type spellable as `p/Type` only; `(import-use lib)` makes it spellable both bare and as `<lib-namespace>/Type`; a file's own `(ns n)` makes it spellable both bare and as `n/Type`. The prelude, every un-namespaced library, and every C-header type are always reachable bare — they live in `user`, which every namespaced file can still see unqualified.

A qualifier that names no namespace in scope is refused rather than silently resolved — a mistyped or bogus prefix used to resolve to whatever type had that bare name, from any namespace, which is no longer true:

```lisp
(defstruct Cat n:i32)
(defn take ((c (ref nope/Cat))):i32 (return (_get c n)))
```

```
demo.nuc:2: error: unknown type: nope/Cat — 'nope' is not in scope in this file
  note: 'nope' is not in scope in this file — a prefixed import binds its
  library under the prefix it names and not under the library's own namespace,
  and an unimported namespace is not nameable at all. This file has no import
  qualifiers in scope.
```

A **bare** reference to a type that genuinely is defined in the compilation unit, but under a namespace this file never imported, gets a diagnostic that names the defining namespace rather than claiming the type does not exist anywhere — and, when this file has bound some prefix that reaches that namespace, a note offering the spelling it can actually write:

```
main.nuc:18: error: unknown type: Fox — defined in namespace 'dp'
  note: write 'dpx/Fox' here
```

If the file has bound nothing for that namespace, the message ends `— defined in namespace 'dp', which this file does not import` instead of offering a spelling. The same check fires in head position too, so a bare struct constructor (`(Fox 9)`) for a type in an unimported namespace gets the identical answer — this is not only an annotation-position rule.

**A parametric spelling gets the same answers.** `(Vector i32)`, `(Result i64 i32)` and any other `(Template Arg …)` type resolve their head through the same ladder, so an unimported template names the file that defines it:

```
demo.nuc:1: error: unknown type: Vector — not defined anywhere in this compilation unit
  note: 'Vector' is defined in lib/vector.nuch, which no import in this unit reaches
```

Writing a type where a type *constructor* belongs is a distinct error, since the head is a real type. The usual way to reach it is a doubled annotation — `x:i32:i32` means `(i32 i32)`:

```
demo.nuc:1: error: 'i32' is a type, not a type constructor -- (i32 ...) is not a type; a doubled annotation like x:T:T desugars to exactly this
```

**The emitted LLVM type name composes the namespace's IR prefix**, the same `<prefix>__<name>` composition a namespaced function or global already uses: a type declared in `(ns dp)` emits `%dp__Fox`, overridable with [`set-ir-prefix`](toplevel.md) exactly as for functions. A mangled overload token composes the same name, so an overloaded method on `dp/Fox` appears as `@f.dp__Fox` in a symbol. In the default `user` namespace nothing changes — `%Fox`, byte-identical to before namespaces existed.

`--emit-cheader` composes the same prefix into the emitted C `typedef` name, for the same collision reason: two namespaces' `Pt` would otherwise both emit `typedef struct {…} Pt;`, and a program that includes both headers would fail to compile. A struct declared in `(ns gt)` emits `} gt__Pt;` in place of `} Pt;`; a `user`-namespace struct's header is unaffected. See [`--emit-cheader`](compiler.md#compiler-flags).

## Pointer kinds: `(ptr T)`, `(raw T)`, and `?T`

Typed pointers carry a compile-time **kind**; all three lower to the same IR
`ptr` and are ABI-identical to a C `T*` (see `design/stage10/nullability.md`).
The safe default is **on**: a typed `(ptr T)` is non-null.

| Surface | Meaning | Deref | Null? |
|---|---|---|---|
| `(ptr T)` / `ptr:T`, `(ref T)` / `ref:T` | **non-null** — always a valid `T` (the default) | always safe | no |
| `(raw T)` / `raw:T`, bare `ptr` | **raw** — unchecked, the C-boundary / `void*` escape | allowed (your problem) | yes |
| `?T` ≡ `(Maybe T)` | **nullable-checked** — may be none | **compile error** until narrowed (pointer `T`) | yes |

`(ptr T)` and `(ref T)` are now synonyms (both non-null); `(ref T)` remains as
the explicit, greppable spelling. A genuinely nullable pointer is spelled
`(raw T)` / `raw:T`. The `null` literal is `raw`, so it flows into `raw`/`?`
slots but not into a non-null `(ptr T)`/`(ref T)` slot.

Only a **typed** non-null destination adds obligations: a `raw` or `?T` value
may not flow into a `(ptr T)`/`(ref T)` slot (binding, `set!`, field/element
store, argument, return) — narrow first, or assert with `(unsafe/cast ref:T x)`
(the audited C-boundary escape hatch — `as` refuses this exact conversion,
routing to `as-ref` for a checked launder or `unsafe/cast` for the unchecked
assertion; see [Implicit Type Coercion](#implicit-type-coercion)). An elem-less
bare `ptr` (`void*`) slot carries
no contract and is exempt. Widening (non-null→raw, non-null→`?T`, raw↔`?T`) is
always allowed. `none` is the null `?T` literal. Stack addresses are non-null by
construction: `(addr-of x)`, `(.& p f)`, `(alloca T)`, `(array T …)`, and a
`(S …)` compound literal all yield `(ref T)`.

**A global declared non-null must be initialized.** `(defvar g:ptr:T)` with no
initializer is a compile-time error: with no initializer the slot takes the
type's zero, which for a pointer is `null` — exactly the value the type says it
can never hold. The rule is the same one every other position enforces, and it
applies at a global only because there is now a way to write the initializer
(see [Run-time initializers](toplevel.md#run-time-initializers)).

```lisp
(defvar g:ptr:Thing)              ; error: non-null pointer type but no initializer
(defvar g:ptr:Thing (make-thing)) ; fine — the run-time initializer runs before main
(defvar g:(raw Thing))            ; fine — `raw` is honestly nullable
(defvar g:?ptr:Thing)             ; fine — a Maybe pointer may be none
(defvar g:ptr)                    ; fine — an elem-less bare `ptr` names no pointee
(defvar g:CStr)                   ; fine — CStr is not a typed pointer kind
```

The two carve-outs in that list are `pkind-flow-check`'s own, not extra
exceptions invented for globals: a bare `ptr` (`void*`) carries no non-null
contract because it names no pointee, and `CStr` is its own type kind.

Both are about the **destination**. A `CStr` *source* carries no non-null
contract either, so it may **not** flow into a typed non-null slot — `(defvar
g:ptr:T (as CStr null))` and `(as ptr:T (getenv "X"))` are both errors, for the
same reason a `raw` is. Use `as-ref` and narrow, or `unsafe/cast` to assert. This
is not a special case for `CStr`: it is the ordinary rule, which `CStr` used to
escape.

**Uniform `?` (Maybe)**: `?T` ≡ `(Maybe T)` with no
auto-`ref` injection. For a **pointer** operand it niche-encodes
(`?ptr:T` / `?ref:T` ≡ `(Maybe (ref T))`, one pointer, `null` = none); for a
**value** operand (`?i64`, `?SomeStruct`) it stamps the two-arm `{tag, T}` value
union from the prelude template. One spelling, two layouts. A nullable pointer
written `?ptr:Foo` makes the niche-encoding explicit. The value `(Maybe T)` is
built with `make` / return-position target typing (bare `none` / `(some v)`
resolve against a `(Maybe T)` return) and eliminated with `match`
(`((some v) …)` / `(none …)`). The pointer relabels (`some`/`none`/`as-ref`
outside return position, `if-some`/`when-some`/`unwrap`/`unwrap-or`) stay
pointer-only. `?!T` ≡ `(Maybe (Result T Err))` is the value-Maybe-over-Result
sugar (a fallible result that may be absent).

**Flow narrowing**: inside a region dominated by a successful non-null test, a
local `?ptr:T` binding reads as `(ref T)`. The compiler's own guard idioms are
the mechanism — `(when (= m null) (return …))`, `(if (!= m null) … …)`,
`(and (!= m null) (m field))` all narrow, as do `if-some`/`when-some`/`unwrap`.
A reassignment kills the narrow (sticky across joins); loop bodies drop narrows
established outside the loop for any binding the body assigns; `label` kills
all narrows (unknown predecessors). Kind mismatches at a `cond`/`if` join meet
conservatively (`raw` beats `Maybe` beats `ref`).

> **⚠ Sharp edge — branch *element* types must match.** The conservative meet
> above reconciles the pointer *kind*, but the branch **element** types must
> still be `type-eq`. Two pointer branches with *different element types* —
> e.g. `(raw Node)` (the type of `Node.car`/`Node.cdr` and of macro parameters)
> versus a bare `ptr`, a `ptr:i8`, or a quasiquoted `` `(...) `` (bare `ptr`) —
> do **not** unify; the `cond`/`if` collapses to `void`. That then fails
> wherever a value was expected (`let`/`set!` `init type mismatch`; a macro
> body returns `null`). Make the branches agree — usually `(as ptr <branch>)`
> the odd one (`ptr` ↔ `(raw Node)` is a no-op reinterpret — exactly the
> pointer-contract weakening `as` accepts). This bites most
> often in macros and AST-walking code; see the "Sharp edge" section in
> [macros.md](macros.md).

## Volatile qualifier

Volatility is declared through the **keyword-attribute slot**: a leading
`:volatile` keyword immediately before the declared name of a variable,
global, struct/union field, or `defn` param. For a pointer *target* (C's
`volatile T *`, the MMIO case), the keyword instead moves inside the pointer
constructor — `(ptr :volatile T)` / `(raw :volatile T)` / `(ref :volatile T)`
— since pointee volatility must travel with the pointer through params and
fields. Loads and stores of a value held at a volatile-qualified storage site
are emitted as `load volatile` / `store volatile` in LLVM IR; the compiler
will not elide, reorder, or coalesce them. Examples:

- `(defvar :volatile trap-zero:i32 0)` — volatile global
- `(let (:volatile x:i32 0) ...)` — volatile local (binds to the immediately following name only)
- `(defstruct R flags:i32 (:volatile status:i32))` — volatile field (parenthesized, keyword head)
- `(defn bump-counter ((p (ptr :volatile i32))):void ...)` — pointer to volatile `i32`; deref and `ptr-set!` through `p` are volatile

Volatility lives on the storage site, not the value: `volatile T` and `T` are assignment-compatible, and the qualifier is dropped/added at the access. Bare `ptr` (no element) cannot be made volatile — volatility attaches to the pointee, not to opaque pointers. Attributes never participate in type identity, overload resolution, dispatch, monomorphization, or name mangling — see [stage14/attributes.md](../design/stage14/attributes.md) for the full attribute-slot design.

> The older postfix spellings (`(T volatile)` list form, `T:volatile` colon segment) are retired: the compiler rejects them with a targeted error naming the `:volatile` attribute-slot spelling above.

## Const globals

A `defvar` global can be made read-only through the same keyword-attribute
slot as `:volatile`: a leading `:const` keyword immediately before the
declared name. `(defvar :const name:type init)` emits an LLVM `constant`
in place of the default mutable `global` — the value is placed in read-only
storage instead of writable data. This is a general, target-independent
feature (not AVR-specific): on a target with separate program/data memory
(e.g. AVR), a `constant` global can be kept out of RAM entirely; on other
targets it is simply placed in read-only data.

- `(defvar :const answer:i32 42)` — emits `@answer = constant i32 42`
- `(defvar mutable-count:i32 0)` — unmarked, unchanged — emits `@mutable-count = global i32 0`

**A `:const` global's initializer must be a compile-time constant.** The whole
constant grammar is available — a folded expression, `(as CStr "…")`,
`(addr-of g)`, an `(array T …)` or `(S …)` literal — but the run-time
initializer route is not: read-only storage cannot be written at startup, so
`(defvar :const g:i32 (compute))` is refused with a message saying so rather
than compiling into a store that would fault. See
[Global initializers](toplevel.md#global-initializers) for the full grammar.

Unlike `:volatile`, `:const` is meaningful **only** on a `defvar` global — a
struct/union field, `defn` param, `let`/`with` binding, or pointer target
type has no independent global-vs-constant storage class to select, and the
compiler rejects `:const` at any of those sites with a targeted error
(`':const' applies only to a defvar global, not a field, parameter, or
binding`).

`set!` against a `:const` global is a compile-time error: `(defvar :const
answer:i32 42) ... (set! answer 10)` dies with `set!: cannot assign to
'answer' -- declared :const` instead of compiling into a `store` to
read-only storage. Reads of a `:const` global (`(return answer)`) are
unaffected — they go through the normal load path. This check covers the
direct `set!` mutation syntax only; it is not an aliasing analysis (e.g. a
raw pointer obtained via `addr-of` and written through `ptr-set!` is not
tracked).

## Built-in Types

| Name | Description | C Equivalent |
|------|-------------|--------------|
| `int` / `i32` | 32-bit signed integer | `int32_t` |
| `i1` / `bool` | 1-bit boolean | `bool` |
| `i8` | 8-bit signed integer | `int8_t` / `char` |
| `i16` | 16-bit signed integer | `int16_t` |
| `i64` | 64-bit signed integer | `int64_t` |
| `ui8` | 8-bit unsigned integer | `uint8_t` |
| `ui16` | 16-bit unsigned integer | `uint16_t` |
| `ui32` | 32-bit unsigned integer | `uint32_t` |
| `ui64` | 64-bit unsigned integer | `uint64_t` |
| `f32` / `float` | IEEE-754 binary32 | `float` |
| `f64` / `double` | IEEE-754 binary64 | `double` |
| `usize` | Unsigned pointer-sized integer (resolves to `i32` on ILP32 targets, `i64` on LP64) | `size_t` |
| `ssize` | Signed pointer-sized integer (resolves to `i32` on ILP32 targets, `i64` on LP64) | `ssize_t` / `ptrdiff_t` |
| `ptr` | Opaque pointer | `void*` |
| `(array T N)` | Fixed-size array of N `T`; storage only, decays to `(ref T)` on read (see [Fixed-size arrays](#fixed-size-arrays--array-t-n)) | `T x[N]` |
| `CStr` | C-style (null-terminated) string | `char*` |
| `Char` | A 32-bit Unicode scalar value (codepoint) | `uint32_t` |
| `void` | No value | `void` |

Pointer size and the target are not hardcoded as `i64`/`8` throughout codegen: a target descriptor (`g-target-triple`, `g-target-ptr-bytes`, defaulting to `x86_64-pc-linux-gnu` / 8 bytes) drives the emitted `target triple`, pointer/`CStr` type sizes and alignments, and the width of `sizeof` (a pointer-sized `size_t`). To target a 32-bit or 16-bit platform, set `g-target-ptr-bytes` to 4 or 2 respectively. (The macro/`compile-time` JIT still targets the host.)

**`usize` and `ssize`** are the portable index and length types for pointer-sized arithmetic. They resolve to the target's pointer-width integer at compile time: `i32` on ILP32 (4-byte pointer) targets and `i64` on LP64 (8-byte pointer) targets. `usize` is unsigned; `ssize` is signed. They are valid in any type position and are handled correctly by `sizeof`, type mangling, `type-eq`, and arithmetic operators. Use `usize` for lengths, counts, and non-negative offsets; use `ssize` for signed differences or offsets that may be negative. Both participate in the standard numeric promotions and are mangled distinctly (e.g. `usize`, `ssize`) in method symbols and stamped struct names.

**A bare `"…"` string literal has static type `StrView`**, not `CStr` — a borrowed `{data:(ptr ui8), len:usize}` view over the literal's rodata storage (see [Strings](strings.md) for the full `StrView` API). `StrView` is a library struct, but its bare type is promoted into the prelude, so it is available everywhere without an import; its methods and protocol conformances still require `(import-use strview)`. A literal's backing storage is always NUL-terminated at `data[len]` (the same rodata global `CStr` literals always used), so a `StrView` value coerces to `CStr`/`ptr` **for free** (no IR) at any assignment, call argument, `as`/`unsafe/cast`, or return boundary, by taking `data` — this is what keeps every existing `:CStr`/`:ptr`-typed function, `printf`/libc call, and `strcmp`-style `=`/`!=` comparison working with a string literal unchanged. Only when a literal flows into a genuinely `StrView`-typed slot does it materialize the two-word `{data,len}` struct. In overloaded (`defn`/multimethod) dispatch, a `StrView`-typed argument adapts to a `CStr` parameter but *not* to a bare `ptr` parameter, reproducing the resolution a `CStr` literal produced before this type existed. A materialized `StrView` passed to a C variadic parameter (e.g. `printf`'s `%s`) contributes only its `data` pointer, never the two-word struct; a *fixed* (non-variadic) `StrView` by-value parameter is unaffected and still receives the full two-eightbyte struct per the platform ABI (`examples/strview-vararg-test.nuc`).

`CStr` is the C-interop `char*` type — the FFI boundary type a `:CStr`-typed parameter, field, or return expects. It lowers to `ptr` (same ABI) and flows into any `ptr`-typed C function with no cast, but it is a **distinct type for operator dispatch**: `=` / `!=` on two `CStr` (or a `CStr`/`ptr`/`StrView` mix) do a `strcmp`-style **content** comparison (so equal text compares equal across distinct buffers), whereas `=` on two raw `ptr` is pointer identity. **Comparing against the `null` literal is the one exception: `(= s null)` / `(!= s null)` on a `CStr` is a pointer-identity test, not a content comparison** — `strcmp(s, NULL)` is undefined behaviour in C, so a null check is always a null check. This makes the ordinary `(if (= s null) …)` guard safe on a `CStr` parameter, local, field, or global. (A `StrView` is a two-word struct and can never be null; compare its `data` field if you need that.) `CStr` conforms to the `Eq` protocol (`lib/numeric.nuc`), so it works in an `Eq`-bounded generic; it is not `Ord` (no ordering — out of scope here, along with Unicode). Only `=` / `!=` are defined; other operators on `CStr` are an error. A `CStr` and a `ptr` are freely interconvertible with `as` (no IR) and coerce automatically in value positions (assignment, return, field/array store). (Multimethod dispatch treats `CStr` as distinct — overload on `CStr` explicitly, or `as` to `ptr`.) `strcmp` must be declared, which the prelude's `(import-use "string.h")` provides. To bind an `Eq`-bounded generic at `StrView` from a literal, `(import-use strview)` must be in scope; otherwise `as` the literal to `CStr` explicitly. Example: `examples/cstr.nuc`.

A **global** of `CStr` type may be initialized with a string literal directly (`(defvar g-name:CStr "doom")`) or with the explicit `(as CStr "doom")` spelling — both emit the same `@g-name = global ptr @.str.N` line. `(as CStr …)` in an initializer works because a `defvar` init is a constant *expression*, not merely a literal; see [Global initializers](toplevel.md#global-initializers).

A `c"…"` literal — a `c` glued directly onto the opening quote, with no whitespace — is an explicit `CStr` literal: the bare `char*` GEP, no `{data,len}` view header, and no target-typing. It is the direct "I mean `char*`" spelling for FFI/format-string hot spots; the free `StrView`→`CStr` coercion above already covers the same cases, so `c"…"` is ergonomic, not required. A space keeps the tokens apart (`c "foo"` is the symbol `c` followed by an ordinary `StrView` literal); only the glued, lowercase-`c` form is the literal. See [Strings](strings.md) §3 and `examples/cstr-lit-test.nuc`.

**`Char`** is a single Unicode scalar value — a codepoint in `0..=0x10FFFF` excluding the UTF-16 surrogate range `0xD800..=0xDFFF` (Rust's `char` model; "character" means codepoint, not grapheme cluster). It is a **built-in distinct 32-bit scalar over `ui32`**, the same kind of distinct scalar `CStr` is: it lowers to IR `i32` (C `uint32_t`, size 4) and participates in the integer operators, but it is its own type for dispatch. `=` / `!=` on two `Char` compare codepoints (`(= \a \a)` is true, `(= \a \b)` is false), and a `Char`-vs-int overload is distinguishable. A same-width `as` (or `unsafe/cast`) between `Char` and `ui32`/`i32` is a no-op reinterpret (`(as ui32 \A)` is `65`). Because `Char` is distinct, two *typed* operands of different kind do **not** silently unify: `(= \a (as ui32 65))` is a compile error (`operand type mismatch`) — convert one side explicitly with `as`. An untyped integer literal still adapts to a `Char` operand, so `(= \a 97)` is allowed. Write a `Char` value with a [char literal](#char-literals--a) (below) or, equivalently, the `(char "x")` form. (The `Char` UTF-8 encode/decode and classification library is a separate task.)

Float literals: `1.5`, `-0.25`, `1e10`, `1.5e-3`, `.5`. Special values use Scheme syntax: `+inf.0`, `-inf.0`, `+nan.0`. Float arithmetic uses `+ - * / %` and comparisons use `= != < <= > >=` (LLVM `fadd`/`fcmp`).

**A float literal is untyped: it adapts to whatever float width the position wants**, and only falls back to `f64` when nothing asks for anything else. That covers both a binop operand — with `alpha:f32`, `(* alpha 2.0)` and `(* 2.0 alpha)` are both `f32`, in either order — and every *typed target* position: `(let (a:f32 0.1) …)`, `with`, `(set! a 0.1)`, `(.set! p x 0.1)`, `(return 0.1)` from an `f32` function (explicit or implicit), an `f32` field in a struct literal, an `f32` element in an `(array f32 …)`, an `f32` argument at a call, and an `f32` `defvar` initializer. None of these need an `(unsafe/cast f32 …)` wrapper, and the literal is rounded to single precision at compile time — no conversion instruction is emitted.

A bare float literal with no target is `f64`, so `(let (b 0.1) …)` and `(let (b:f64 0.1) …)` are both `f64`; adaptation never makes an unrequested `f32`. Two *typed* float operands of different width widen to the wider (`f32 * f64` is `f64`). Mixing float and integer operands without an explicit `unsafe/cast` is a compile error — a float literal adapts only to a *float* target, never to an integer one (`(let (a:i32 1.5) …)` is rejected).

A `f64` **value** (not a literal) narrows into an `f32` target implicitly and silently, with an `fptrunc`, the same way an `i64` value narrows into an `i32` slot; the explicit `(as f32 d)` spelling still refuses it as lossy and routes you to `(unsafe/cast f32 d)`. See [Implicit Type Coercion](#implicit-type-coercion) below for the full rule.

**`f64` is unsupported when `--target=avr`**: AVR has no hardware double, so `f64`/`double` is a compile-time error, whether written as an explicit type annotation or reached only through a bare float literal's default type (`(let (x 1.5) …)` is rejected even with no `f64` text in the source). The error names the `-mdouble=64` avr-gcc multilib escape hatch for a custom AVR build with software double support. `f32` *types* are unaffected, and `i64` remains fully supported (arithmetic links libgcc's software routines, e.g. `__muldi3`). **A float *literal* is rejected on AVR even in an `f32` position** (`(let (a:f32 1.5) …)`), because the check fires when the literal is emitted, before its target width is known; this predates the W2d literal adaptation — `(unsafe/cast f32 1.5)` was rejected at the same point — so an AVR program currently cannot spell a floating-point constant at all. Lifting it is AVR work, not literal-typing work. This check applies only to the AVR target module itself — compile-time/macro code always runs on the host regardless of `--target=`, so ordinary `f64` arithmetic inside a `defmacro`/`compile-time` body compiling *for* an AVR program is unaffected.

## Fixed-size arrays — `(array T N)`

`(array T N)` is a fixed-size array of `N` values of `T`, laid out inline exactly
as C's `T x[N]`. `N` is a compile-time constant *expression* — a literal, a
`defconst` / `defenum` name, or arithmetic over them — evaluated by the same
folder a [global initializer](toplevel.md#global-initializers) uses.

It is a **storage** type, so it is valid in exactly these positions:

* a `defvar` type — `(defvar g-table:(array i32 256))`
* a field of an aggregate — a `defstruct` field, or a member of an anonymous
  `(struct …)` / `(union …)`
* `(sizeof (array T N))`
* `(alloca (array T N))`, which reserves `N` slots of frame storage

**Reading an array decays it to a pointer**, exactly as in C: the value of an
array-typed global, field, or `alloca` is the address of element 0, typed
`(ref T)`. Nothing is loaded and nothing is copied.

```lisp
(defstruct Row tag:i8 (cells (array i32 4)) mark:i8)   ; C: struct { int8_t tag; int32_t cells[4]; int8_t mark; }

(defn row-first ((r (ref Row))):i32
  (aref (r cells) 0))          ; (r cells) is ptr:i32 — a GEP, no load

(defn scratch ():i32
  (let (buf:ptr:i32 (alloca (array i32 64)))   ; 64 slots of frame storage
    (aset! buf 0 1)
    (aref buf 0)))
```

Because it decays, an array is **refused** wherever a whole-array *value* would
have to exist — a by-value parameter or return, a `let` / `with` binding type, a
pointer element (`ptr:(array T N)`), a generic type argument, a nested array
(`(array (array T M) N)`), and as the target of `set!` or `.set!`. Each is a
compile-time error naming the `ptr:T` spelling that works. C has the same
restrictions for the same reason.

Layout, size and alignment match the platform C ABI: `sizeof` is
`N * sizeof(T)`, alignment is `T`'s, and a struct containing an array field
classifies for by-value passing element by element — so `struct { float v[2]; }`
travels in an SSE register, as C does it. This is gated by `make layout-test`
and `make abi-test`.

`--emit-cheader` renders an array field with C's postfix declarator
(`int32_t cells[4];`), keeping a named extent symbolic when the header also
exports the constant. `--emit-nuch` round-trips `(array T N)` unchanged, for both
a field and an array-typed global (exported as `(extern (g (array i32 3)))`).

An `(array T N)` global's initializer must be a **compile-time constant** — an
`(array T …)` literal, or nothing at all (`zeroinitializer`). There is no
run-time route for one, because an array binding names storage that `set!`
cannot target, so there is no assignment a startup initializer could perform;
the pointer form (`(defvar g:ptr:T (make-table))`) is what to declare when the
table has to be built at run time. For the constant grammar, see
[Global initializers](toplevel.md#global-initializers); for the array
**literal** used in expression position, see
[Special Forms](special-forms.md).

## Function Pointer Types

Function pointer types are written as `(fn:rettype (param-types...))` in sugared form, or `((fn rettype) (param-types...))` in desugared/canonical form.

In parameter, `let`-binding, struct-field and union-member positions, either the
canonical list form or the colon-paren sugar works — the reader fuses a
trailing-colon name immediately followed by `(`, then absorbs the adjacent
parameter-list group (see *Colon-paren binding sugar* above). **Both parenthesised
groups must be adjacent — `f:(fn i32)(i32 i32)`, not `f:(fn i32) (i32 i32)`**; a
space-separated second group is a separate element of the enclosing list, which
leaves `f` typed as a *zero-parameter* function pointer.

```lisp
; canonical list form
(defn apply ((f (fn i32) (i32 i32)) a:i32 b:i32):i32
  (return (funcall f a b)))

; colon-paren sugar — equivalent
(defn apply (f:(fn i32)(i32 i32) a:i32 b:i32):i32
  (return (funcall f a b)))
```

In `let` bindings, the binding name is also a list (or its colon-paren sugar):

```lisp
(let ((f (fn i32) (i32 i32)) some-function)   ; list form
  (funcall f 1 2))

(let (f:(fn i32)(i32 i32) some-function)      ; colon-paren sugar
  (funcall f 1 2))
```

A `defn` function name used in value position decays to a function pointer, matching C semantics:

```lisp
(defn add (a:i32 b:i32):i32 (return (+ a b)))
(apply add 3 4)  ; passes add as a function pointer
```

### Function-pointer globals

A `defvar` may be typed with a function-pointer type — the *hook* shape, where a
slot is declared once and filled in later:

```lisp
(defvar g-hook:(fn i32)(i32) null)   ; declared unwired
(defvar g-zero:(fn i32)(i32))        ; identical: the implicit zero is null
(defvar g-init:(fn i32)() (pick))    ; run-time initializer: filled at startup

(defn main ():i32
  (set! g-hook add1)                 ; assign any matching function
  (return (g-hook 41)))              ; call through it — funcall also works
```

**A function pointer is nullable and carries no non-null contract.** The pointer
kinds (`ref`/`raw`/`?T`) apply to `ptr`, not to `(fn ret)(params)`, so `null` is
a fn pointer's ordinary "not wired yet" value — the same status `CStr` and an
elem-less bare `ptr` have. Note the distinction from the *wrapper* spellings:
`ptr:(fn ret)(params)` and `(ref (fn ret)(params))` are pointers **to** a
function pointer, are non-null like any other typed pointer, and reject a `null`
initializer.

A hook filled by a [run-time initializer](toplevel.md#run-time-initializers) is
subject to the ordering rule like any other global, and calling *through* a hook
counts as reading it: `(defvar g-v:i32 (g-late 3))` above `(defvar g-late:(fn
i32)(i32) …)` is refused with both sites named, since `g-late` would still be
`null` when `g-v`'s initializer ran.

**Function pointers compare by identity.** `=` and `!=` on a function pointer
are machine identity — the same `icmp` a plain pointer gets — in every position
(global, parameter, local) and against any of: the `null` literal, another
function-pointer value, or a `defn` name used as a value.

```lisp
(if (= g-hook null) …)      ; not wired yet
(if (!= g-hook null) …)
(if (= g-hook add1) …)      ; still the default hook?
(if (= g-hook g-other) …)   ; two slots pointing at the same function
```

A function pointer is deliberately **not** admitted to the `CStr` content
comparison: `(= g-hook some-cstr)` is a compile error rather than a `strcmp` of
a function's machine code. Ordering (`<`, `<=`, …) is permitted and compares
addresses, as it does for `raw`.

A function-pointer slot is one target pointer wide, like any other pointer: a
global, a local, a parameter and a struct field each get the target's pointer
alignment (`align 8` on x86-64, `align 4` on a 32-bit target), and it is the
*target*'s width, not the host's.

## Implicit Type Coercion

The following conversions are applied automatically in assignment contexts (`let`, `set!`, `.set!`, `aset!`, `ptr-set!`, implicit and explicit `return`) **and at function call sites** (both direct calls and `funcall`). This is exactly the safe set `as` (see [Special Forms](special-forms.md#special-forms)) also accepts when written explicitly, plus `as`'s own pointer-contract-weakening allowance; `unsafe/cast` accepts this same set **and** everything lossy or contract-manufacturing besides (narrowing, `float`↔`int`, `ptr`↔`int`, `fn`↔`ptr`, element-retyping pointers, and laundering a `raw`/nullable pointer into a non-null slot):

- **Pointer ↔ pointer** (any element types): identity, no IR. `ptr`, `ptr:Node`, `ptr:i8` are interchangeable at boundaries; the cast only matters when the result feeds a typed-pointer-only operation (`.`, `aref`, `aset!`, `unsafe/ptr+`, `deref`).
- **`StrView` → `CStr` / `ptr`**: takes the view's `data` field — no IR for an unmaterialized string literal (whose value already *is* `data`), one `extractvalue` for a general `StrView` value. Trusts that the buffer is NUL-terminated at `data[len]`, always true for a literal but not guaranteed for an arbitrary sub-slice (see [Strings — Gotchas and constraints](strings.md)).
- **`ptr:S` → by-value `S`** (`S` a struct): one `load` of the pointee — the implicit form of `(deref p)`. This is what lets a `(S …)` compound literal, which is alloca-backed and evaluates to `(ref S)`, be written directly wherever a by-value `S` is expected: an element of an `(array S …)`, a struct-typed field in another struct literal, a `let`/`with` binding declared `:S`, an `aset!`/`ptr-set!` element store, and an implicit or explicit `return` from an `S`-returning function. Argument positions have always accepted it. The element type must match exactly (a compound literal of a *different* struct is still a type mismatch), and because the conversion is a `deref` it carries `deref`'s obligation: a `?T` source must be narrowed first. The explicit `(deref (S …))` spelling remains valid and emits byte-identical IR.
- **Integer ↔ integer**:
  - Same width, different sign (e.g. `i32` ↔ `ui32`): reinterpret, no IR.
  - Widening: `sext` for signed source, `zext` for unsigned source.
  - Narrowing: `trunc` — **except** that a narrowing of an integer *literal*
    whose value does not fit the target type is a **compile-time error**
    (`integer literal 300 does not fit ui8`), never a silent wrap. This applies
    only to literals with a known value (`(take8 300)`, `(let (b:i8 200) …)`,
    `(< u:ui8 300)`); narrowing a typed *value* still truncates (its runtime
    value is unknown). To deliberately wrap a literal, cast it explicitly with
    `unsafe/cast`: `(unsafe/cast i8 200)` is `-56`.
    A literal that *does* fit is not lossy, so the explicit `as` spelling
    accepts it too — `(as i8 5)` and `(let (a:i8 5) …)` are the same conversion
    and emit the same IR. Only the narrowing of a *value* is outside `as`'s
    safe set.
  - **`i1`/`bool` holds `{0, 1}`**, not a 1-bit two's-complement range, so the
    range check above admits exactly those two values: `(defvar g:i1 1)` and
    `(let (a:i1 0) …)` mean what `true` and `false` mean, while `(defvar g:i1
    5)` and `(defvar g:i1 -1)` are compile-time errors rather than a silent
    truncation to `true`. (`true`/`false` are their own literals and are not
    range-checked.)
- **Float ↔ float**:
  - Widening `f32` → `f64`: `fpext`.
  - Narrowing `f64` → `f32`: `fptrunc` for a *value*, and for a float **literal**
    no instruction at all — the literal is re-rendered as a single-precision
    constant at compile time. So `(let (a:f32 0.1) …)`, `(set! a 0.1)`,
    `(return 0.1)` from an `f32` function, `(P 0.1 0.2)` into `f32` fields,
    `(array f32 0.1)`, `(.set! p x 0.1)` and `(take 0.1)` against
    `(defn take (x:f32) …)` all work with the bare literal — no
    `(unsafe/cast f32 0.1)` wrapper. The narrowing of a *value* is silent, the
    same way a narrowing integer assignment is silent (see the `trunc` bullet
    above); unlike the integer case there is no range check, because float
    overflow saturates to `±inf` by IEEE rule rather than wrapping.
  - Rounding is decimal → `f64` → `f32` (two roundings), which is exactly what
    the explicit `(unsafe/cast f32 3.14)` spelling has always done. In practice
    this agrees with C's `3.14f` for essentially every constant, and `f32`
    arithmetic is otherwise bit-exact with C `float`.
- **User-registered**: any pair declared with `(defcast From To conv-fn)` (see [Top-level forms](toplevel.md)). The compiler emits a call to `conv-fn`. Built-in coercion always wins; `defcast` cannot shadow `sext`/`zext`/`fpext`.

**Binary operators unify their two operands** by exactly one rule, and the
result type is that unified type (a comparison always yields `bool`). The rule is
**symmetric in operand order** — `(* 2 x)` and `(* x 2)` type identically:

- An **untyped literal adapts to the other operand's type**: an integer literal
  to any integer *or* float operand (`(+ x:i64 1)`, `(* 2 u:ui32)`,
  `(* d:f64 2)`), a float literal to any *float* operand
  (`(* alpha:f32 2.0)` is `f32`, not `f64`). Two untyped literals fall back to
  `i32`, or `i64` when either value does not fit.
- A name bound by **`defconst` or a `defenum` member counts as that literal** —
  naming a constant does not change how it types. `(defconst K 512)` then
  `(<= ans:ui32 K)` behaves exactly as `(<= ans:ui32 512)`, in either operand
  order. A *local* binding that shadows the constant is an ordinary typed
  value, not a literal.
- **Two typed operands of the same kind widen** to the wider one:
  `(+ i32-value i64-value)` is `i64`, `(+ f32-value f64-value)` is `f64`.
- Everything else is a compile error at the operator: a float operand against an
  integer operand (`float and non-float operands`), mixed-sign integers such as
  `i32 + ui32` (`mixed signed/unsigned operands`), and a typed `Char` against a
  typed non-`Char` integer (`operand type mismatch`). Fix these with an explicit
  `(as ...)` (widening / same-width sign reinterpret) or `(unsafe/cast ...)`
  (narrowing, `float`↔`int`) on the binop side — the compiler will not
  sign-reinterpret or truncate a *typed* value for you.

Only a literal adapts freely; a typed value still obeys the coercion rules above.

Explicit `(unsafe/cast ...)` is also still required for cross-kind conversions: `int ↔ ptr`, `int ↔ float`, and `ptr ↔ float` — none of these are in `as`'s safe set.

`f64 → f32` is a special case: the **implicit** coercion at a typed slot performs
it (silently for a value, exactly as an `i64 → i32` assignment does), but the
**explicit** `(as f32 d)` still refuses it as lossy and routes you to
`(unsafe/cast f32 d)`. For a *value* that asymmetry is not float-specific —
`(as i32 n:i64)` is refused for the same reason while `(let (a:i32 n) …)`
truncates — and is a standing question about implicit narrowing in general.
For a *literal* the two have parted: `(as i8 5)` is accepted, because the value
is known to fit and the conversion is therefore lossless, while `(as f32 1.5)`
is still refused even though that literal is likewise exactly representable.
Both spellings work implicitly. The remaining float gap is a known defect, not a
rule.

**Multimethod dispatch is stricter than assignment.** A float *literal* adapts
to a narrower float parameter when selecting an overload (`(over 0.1)` picks
`(defn over (x:f32) …)`), but a typed `f64` *value* does not — dispatch never
narrows a runtime value to choose which function runs. Cast at the call, or add
the overload. This mirrors the integer rule, where a typed `i64` value likewise
only ever dispatches to an `i64`-or-wider parameter.

## Literal Values

| Name | Type | C Equivalent |
|------|------|--------------|
| `null` | ptr | `NULL` |
| `true` | bool (i1) | `1` / `true` |
| `false` | bool (i1) | `0` / `false` |
| `"…"` string literal | `StrView` | `"…"` (a `char*`/`{ptr,len}` view — see above) |
| `c"…"` string literal | `CStr` | `"…"` (bare `char*`, no view header) |
| `\a`, `\newline`, `\u{1F600}` char literal | `Char` | `(uint32_t)U'…'` |

**Integer literals** carry their full value (lexed as up to a 64-bit magnitude:
signed `i64` down to `-2^63`, unsigned up to `2^64-1`; a literal outside that
range is a positioned reader error). An integer literal has no intrinsic type —
it *adapts* to whatever integer (or float) type its context needs, wherever the
value fits: it passes to a wider or narrower parameter, `let`/field slot, or
binop operand as long as it is representable there (see *Implicit Type
Coercion*). When a literal's type is not otherwise constrained, it emits as
`i32` if it fits and `i64` otherwise, so `(take64 5000000000)` yields
`5000000000` (not a 32-bit wrap) while an out-of-range use like
`(take-i32 5000000000)` is a compile-time error. (Typed *values*, unlike
literals, only widen same-sign — see the coercion rules above.)

The same width rule and the same range check apply to a **named** constant. A
`defconst` is typed by its value, not fixed at `i32`: `(defconst BIG
5000000000)` is `i64`, so `(let (x:i64 BIG) …)` yields `5000000000`, while
`(let (x:i32 BIG) …)` and `(defvar g:i32 BIG)` are compile-time errors rather
than a silent 32-bit wrap. Enum members are always small enough to be `i32`.

The narrowest destination is `i1`/`bool`, whose value set is `{0, 1}` — the two
values `false` and `true` denote. `1` and `0` are legal numeric spellings of
them; every other literal, including `-1`, is rejected. Reading `i1` as a 1-bit
*integer* would give the range `[-1, 0]`, which is not the type Nucleus has.

## String literal escapes — `\n`, `\xHH`

Inside a `"…"` (or `c"…"`) string literal, a backslash introduces an escape.
The complete set:

| Escape | Byte | Notes |
|--------|------|-------|
| `\n` | 0x0A | newline |
| `\t` | 0x09 | tab |
| `\r` | 0x0D | carriage return |
| `\0` | 0x00 | NUL — but see the truncation note below |
| `\\` | 0x5C | a literal backslash |
| `\"` | 0x22 | a literal double quote |
| `\xHH` | 0x00–0xFF | a raw byte as **one or two** hex digits, either case |

Any other character after a backslash is a positioned reader error
(`unknown escape \<c>`); a `\x` with no following hex digit is likewise an
error (`\x escape needs at least one hex digit`).

**`\x` is capped at two hex digits — this is a deliberate difference from C.**
C's `\x` is *greedy*: it consumes every following hex digit, so C's `"\x41BC"`
is a single character whose value overflows. Nucleus stops after two digits, so
`"\x41BC"` is the three characters `A`, `B`, `C` (0x41, then the ordinary
literal characters `B` and `C`). Two digits express every byte, so the cap costs
nothing in practice and removes C's run-on footgun. One digit is accepted where
unambiguous — `"\xa"` and `"\x0a"` are the same byte.

```lisp
"MUS\x1a"        ; four bytes: 'M' 'U' 'S' 0x1A
"\x1b[0m"        ; an ANSI reset sequence
"\xff\xFF"       ; two 0xFF bytes — hex digits are case-insensitive
"\x41BC"         ; three characters: 'A' 'B' 'C'  (NOT one, as in C)
```

Note the `\x` spelling means something different in the two literal contexts:
inside a string, `"\x41"` is the escape for byte 0x41, while the standalone
*char literal* `\x` is the single printable character `x` (codepoint 120) — char
literals use `\u{…}` for a hex codepoint, as described in the next section.

**A string literal cannot carry an embedded NUL.** The reader decodes escapes
into a counted buffer, but the token stores the result as a NUL-terminated
`char*` and the count is dropped, so the literal's length is recovered
downstream with `strlen`. Both `"x\0y"` and `"x\x00y"` are therefore length 1,
truncated at the NUL. Build byte strings containing a zero byte at runtime
instead (see [Strings](strings.md)).

## Char literals — `\a`

A **char literal** is a backslash followed by one of three forms, evaluating to a self-evaluating `Char` value (a Unicode scalar). The leading `\` collides with neither keywords (leading `:`) nor strings (`"`), so it is unambiguous:

| Form | Meaning | Example |
|------|---------|---------|
| `\a` | A single printable codepoint — the character after the backslash | `\A` → 65, `\x` → 120, `\(` → 40 |
| `\name` | A named control code | `\newline` (0x0A), `\return` (0x0D), `\tab` (0x09), `\space` (0x20), `\nul` (0x00), `\escape` (0x1B), `\backspace` (0x08), `\delete` (0x7F) |
| `\u{HEX}` | An explicit codepoint as hex digits between braces | `\u{41}` → 65, `\u{1F600}` → 😀 (128512) |

The `\u{…}` form is validated at read time: a value above `0x10FFFF`, a UTF-16 surrogate (`0xD800..=0xDFFF`), an empty or non-hex body, or an unknown `\name` is a reader error (`invalid-codepoint` / `unknown named char literal`). A lone printable form is exactly the byte after the backslash, so a single-character spelling like `\u` (no brace) is the letter `u`, not a malformed escape.

```lisp
(printf "%u\n" (as ui32 \A))            ; 65
(printf "%u\n" (as ui32 \newline))      ; 10
(printf "%u\n" (as ui32 \u{1F600}))     ; 128512
(printf "%d\n" (if (= \a \a) 1 0))      ; 1
```

The `(char "x")` special form is equivalent sugar for the single-byte case: `(char "x")` and `\x` both produce the `Char` with codepoint 120. See `examples/char-test.nuc`.

## Keyword literals — `:foo`

**Keywords** are interned, self-evaluating names written as a colon followed by a non-empty identifier: `:foo`, `:http-method`, `:ok`. A keyword literal evaluates to a canonical `Keyword` value; two keyword literals with the same spelling are identical (`(= :foo :foo)` is `true`; `(= :foo :bar)` is `false`). `!=` follows the same identity semantics.

A `Keyword` has static type `Keyword` and conforms to both `Hash` and `Eq`, making it a natural key type for `HashMap` and member type for `HashSet`.

**Requires `(import-use keyword)`** — and transitively `(import-use strview)`, `(import-use hash)`, and `(import-use numeric)`. Without the import the compiler emits `undefined: keyword-intern`. See [Keywords and StrView](stdlib.md#strview-libstrviewnuc) for the full API.

```lisp
(import-use "stdio.h")
(import-use strview)
(import-use hash)
(import-use keyword)
(import-use allocator)
(import-use coll)
(import-use iterator)
(import-use hashmap)

(defn main ():i32
  ; Self-evaluation.
  (let (k:Keyword :foo)
    (printf "self-eval=%d\n" (if (= k :foo) 1 0)))    ; 1

  ; Identity equality.
  (printf "foo=foo? %d\n" (if (= :foo :foo) 1 0))     ; 1
  (printf "foo=bar? %d\n" (if (= :foo :bar) 1 0))     ; 0

  ; Keywords as HashMap keys.
  (with ((m (ref (HashMap Keyword i32))) (alloca (HashMap Keyword i32)))
    (hashmap-init m)
    (assoc m :a 1)
    (assoc m :b 2)
    (match (hmap-get m :a)
      ((some v) (printf "a=%d\n" v))                   ; a=1
      (none     (printf "absent\n"))))
  (return 0))
```

**Syntax disambiguation.** The keyword reader rule fires only when the entire atom starts with `:` and has a non-empty remainder. It does **not** interfere with:

- **Colon-chain type syntax** (`ptr:i8`, `ref:Foo`) — the colon is interior, not leading.
- **Colon-paren binding sugar** (`name:(ref T)`) — the colon is trailing on the name token; the paren that follows is read as a type expression.
- A bare `:` by itself remains a plain symbol.

**Intern pool limit.** The intern pool holds up to 256 distinct keywords per process. Exceeding this limit aborts with a diagnostic. 256 is ample for a typical program's keyword vocabulary.

## Symbols

A symbol is a `Node*` with `kind = NODE-SYM` and `s` pointing to its spelling. Symbols are **interned**: any two symbols with the same spelling are the same `Node*`, so identity is comparable with plain `=`.

```lisp
(= 'foo 'foo)              ; true — both forms read to the same Node*
(let (h (head form))
  (= h 'defn))             ; true iff the head symbol of `form` spells "defn"
```

The interning is global to the process. The reader interns at lex time, and `quote` of a symbol calls `intern-symbol` at runtime so a quoted symbol and a reader-produced symbol with the same spelling are bit-identical pointers. The intern table lives in `lib/node.nuc` (auto-imported via `lib/prelude.nuc`); user code never has to touch it directly.

`gensym` deliberately bypasses the intern table — `(gensym)` always returns a fresh unique `Node*` whose spelling (e.g. `__gs_0`) does not collide with anything else, so it is safe in hygienic macros.

Symbol identity replaces `strcmp` for matching known spellings. Prefer `(= h 'defn)` over `(= (strcmp (. h s) "defn") 0)`.
