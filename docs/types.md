# Type System

## Type Syntax and Desugar

Types are attached to names with `:` syntax: `name:type` (e.g., `x:i32`, `main:int`). A desugar pass runs before compilation, splitting colon-typed symbols in binding positions into canonical list form:

- `foo:int` → `(foo int)` — name and type as separate symbols
- `node:ptr:Node` → `(node (ptr Node))` — pointer-to-Node
- `pp:ptr:ptr:Node` → `(pp (ptr ptr Node))` — pointer-to-pointer-to-Node

Pointers to a typed element use the `ptr` constructor: `(ptr T)` is a **non-null** pointer to `T`, and `(ptr ptr T)` chains. Bare `ptr` (with no element) is the opaque `void*` pointer — it carries no element contract, so non-null obligations do not apply to it.

In inline type positions (the type argument of `cast`, `sizeof`, `alloca`), either the canonical list form or the colon sugar works: `(cast (ptr Node) x)` and `(cast ptr:Node x)` are equivalent.

**Colon-paren binding sugar.** A binding's type may also be a parenthesised form written directly after the colon, with no space: `name:(ref (Vector T))`, `v:(ptr u8)`, `f:(fn i32) (i32 i32)`. In list (binding) context the reader fuses a trailing-colon atom that is *immediately* followed by `(` into the canonical list node `(name <paren-form>)`. So `v:(ref (Vector i32))` is exactly `(v (ref (Vector i32)))`, in both parameter lists and `let` bindings. The fusion only fires when the colon is the last character of the atom and the very next character is `(` (no whitespace); a mid-colon symbol such as `foo:i32` is unaffected.

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
store, argument, return) — narrow first, or assert with `(cast ref:T x)` (the
audited C-boundary escape hatch). An elem-less bare `ptr` (`void*`) slot carries
no contract and is exempt. Widening (non-null→raw, non-null→`?T`, raw↔`?T`) is
always allowed. `none` is the null `?T` literal. Stack addresses are non-null by
construction: `(addr-of x)`, `(.& p f)`, `(alloca T)`, `(array T …)`, and a
`(S …)` compound literal all yield `(ref T)`.

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

## Volatile qualifier

A type can be tagged `volatile` in postfix position — either the list form `(T volatile)` or the sugared `T:volatile`. Loads and stores of a value held at a volatile-qualified storage site (variable, struct field, or pointer target) are emitted as `load volatile` / `store volatile` in LLVM IR; the compiler will not elide, reorder, or coalesce them. Examples:

- `x:i32:volatile` — local volatile variable (sugared)
- `(let (x (i32 volatile)) ...)` — same, list form
- `(defstruct R status:i32:volatile)` — field is volatile
- `(p (ptr (i32 volatile)))` — pointer to volatile `i32`; deref and `ptr-set!` through `p` are volatile

Volatility lives on the storage site, not the value: `volatile T` and `T` are assignment-compatible, and the qualifier is dropped/added at the access. Bare `ptr` (no element) cannot be made volatile — volatility attaches to the pointee, not to opaque pointers.

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
| `CStr` | C-style (null-terminated) string | `char*` |
| `void` | No value | `void` |

Pointer size and the target are not hardcoded as `i64`/`8` throughout codegen: a target descriptor (`g-target-triple`, `g-target-ptr-bytes`, defaulting to `x86_64-pc-linux-gnu` / 8 bytes) drives the emitted `target triple`, pointer/`CStr` type sizes and alignments, and the width of `sizeof` (a pointer-sized `size_t`). To target a 32-bit platform, set `g-target-ptr-bytes` to 4. (The macro/`compile-time` JIT still targets the host. One remaining 64-bit assumption is the hand-written `__cons`/`__append` IR in `emit-qq-helpers`.)

**`usize` and `ssize`** are the portable index and length types for pointer-sized arithmetic. They resolve to the target's pointer-width integer at compile time: `i32` on ILP32 (4-byte pointer) targets and `i64` on LP64 (8-byte pointer) targets. `usize` is unsigned; `ssize` is signed. They are valid in any type position and are handled correctly by `sizeof`, type mangling, `type-eq`, and arithmetic operators. Use `usize` for lengths, counts, and non-negative offsets; use `ssize` for signed differences or offsets that may be negative. Both participate in the standard numeric promotions and are mangled distinctly (e.g. `usize`, `ssize`) in method symbols and stamped struct names.

`CStr` is the type of a string literal — a C `char*`. It lowers to `ptr` (same ABI) and flows into any `ptr`-typed C function with no cast, but it is a **distinct type for operator dispatch**: `=` / `!=` on two `CStr` do a `strcmp` **content** comparison (so equal text compares equal across distinct buffers), whereas `=` on two raw `ptr` is pointer identity. `CStr` conforms to the `Eq` protocol (`lib/numeric.nuc`), so it works in an `Eq`-bounded generic; it is not `Ord` (no ordering — out of scope here, along with Unicode). Only `=` / `!=` are defined; other operators on `CStr` are an error. A `CStr` and a `ptr` are freely interconvertible with `cast` (no IR) and coerce automatically in value positions (assignment, return, field/array store); a string literal also passes directly to a plain `ptr` parameter. (Multimethod dispatch treats `CStr` as distinct — overload on `CStr` explicitly, or `cast` to `ptr`.) `strcmp` must be declared, which the prelude's `(include string)` provides. Example: `examples/cstr.nuc`.

Float literals: `1.5`, `-0.25`, `1e10`, `1.5e-3`, `.5`. Default type is `f64`; narrow with `(cast f32 ...)`. Widen `f32`→`f64` and convert int↔float with `cast`. Special values use Scheme syntax: `+inf.0`, `-inf.0`, `+nan.0`. Float arithmetic uses `+ - * / %` and comparisons use `= != < <= > >=` (LLVM `fadd`/`fcmp`); operands must have the same float width — promote with explicit `cast`. Mixing float and integer operands without a cast is a compile error.

## Function Pointer Types

Function pointer types are written as `(fn:rettype (param-types...))` in sugared form, or `((fn rettype) (param-types...))` in desugared/canonical form.

In parameter and `let`-binding positions, either the canonical list form or the
colon-paren sugar works — the reader fuses a trailing-colon name immediately
followed by `(` (see *Colon-paren binding sugar* above):

```lisp
; canonical list form
(defn apply:i32 ((f (fn i32) (i32 i32)) a:i32 b:i32)
  (return (funcall f a b)))

; colon-paren sugar — equivalent
(defn apply:i32 (f:(fn i32) (i32 i32) a:i32 b:i32)
  (return (funcall f a b)))
```

In `let` bindings, the binding name is also a list (or its colon-paren sugar):

```lisp
(let ((f (fn i32) (i32 i32)) some-function)   ; list form
  (funcall f 1 2))

(let (f:(fn i32) (i32 i32) some-function)     ; colon-paren sugar
  (funcall f 1 2))
```

A `defn` function name used in value position decays to a function pointer, matching C semantics:

```lisp
(defn add:i32 (a:i32 b:i32) (return (+ a b)))
(apply add 3 4)  ; passes add as a function pointer
```

## Implicit Type Coercion

The following conversions are applied automatically in assignment contexts (`let`, `set!`, `.set!`, `aset!`, `ptr-set!`, implicit return) **and at function call sites** (both direct calls and `funcall`):

- **Pointer ↔ pointer** (any element types): identity, no IR. `ptr`, `ptr:Node`, `ptr:i8` are interchangeable at boundaries; the cast only matters when the result feeds a typed-pointer-only operation (`.`, `aref`, `aset!`, `ptr+`, `deref`).
- **Integer ↔ integer**:
  - Same width, different sign (e.g. `i32` ↔ `ui32`): reinterpret, no IR.
  - Widening: `sext` for signed source, `zext` for unsigned source.
  - Narrowing: `trunc`.
- **`f32` → `f64`**: `fpext`.
- **User-registered**: any pair declared with `(defcast From To conv-fn)` (see [Top-level forms](toplevel.md)). The compiler emits a call to `conv-fn`. Built-in coercion always wins; `defcast` cannot shadow `sext`/`zext`/`fpext`.

Binary operators do *not* coerce — both operands must already match in kind. Mixing float and integer operands, or mixed-sign integer operands (e.g. `i32 + ui32`), or operands of different integer widths (e.g. `i64 + i32-literal`) are compile errors at the operator. Use explicit `(cast ...)` on the binop side.

Explicit `(cast ...)` is also still required for cross-kind conversions: `int ↔ ptr`, `int ↔ float`, `ptr ↔ float`, and `f64 → f32` narrowing.

## Literal Values

| Name | Type | C Equivalent |
|------|------|--------------|
| `null` | ptr | `NULL` |
| `true` | bool (i1) | `1` / `true` |
| `false` | bool (i1) | `0` / `false` |
| `"…"` string literal | `CStr` | `"…"` (`char*`) |

## Keyword literals — `:foo`

**Keywords** are interned, self-evaluating names written as a colon followed by a non-empty identifier: `:foo`, `:http-method`, `:ok`. A keyword literal evaluates to a canonical `Keyword` value; two keyword literals with the same spelling are identical (`(= :foo :foo)` is `true`; `(= :foo :bar)` is `false`). `!=` follows the same identity semantics.

A `Keyword` has static type `Keyword` and conforms to both `Hash` and `Eq`, making it a natural key type for `HashMap` and member type for `HashSet`.

**Requires `(import keyword)`** — and transitively `(import strview)`, `(import hash)`, and `(import numeric)`. Without the import the compiler emits `undefined: keyword-intern`. See [Keywords and StrView](stdlib.md#strview-libstrviewnuc) for the full API.

```lisp
(include stdio)
(import strview)
(import hash)
(import keyword)
(import allocator)
(import coll)
(import iterator)
(import hashmap)

(defn main:i32 ()
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
