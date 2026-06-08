# Nucleus Built-ins Reference

Built-in forms and functions as implemented in `src/nucleusc.nuc`.

## Compiler Flags

By default `nucleusc <file.nuc>` produces a linked native executable (`a.out` unless `-o` is given). The compiler embeds LLVM: it parses its own generated IR, emits an object file via `LLVMTargetMachineEmitToFile`, and shells out to `clang` for the final link step.

| Flag | Description |
|------|-------------|
| `-o <path>` | Output path. For binary mode the default is `a.out`; with `-c` the default is `out.o`; with `--emit-llvm` output still goes to stdout. |
| `-c` | Emit a `.o` object file instead of linking a binary. |
| `--emit-llvm` / `-S` | Output textual LLVM IR to stdout (the legacy default). Required when the consumer wants `.ll` text — bootstrap, library `.ll` rules, and the `make bootstrap` fixed-point check all pass this flag. |
| `-l<lib>` / `-L<dir>` | Forwarded to `clang` at the link step. |
| `-O0` / `-O1` / `-O2` / `-O3` (or bare `-O` = `-O2`) | LLVM backend codegen optimization level. Default is `-O0`; higher levels make the build noticeably slower. |
| `--emit-nuch` | Output a `.nuch` header instead of compiling. Extracts function signatures, struct definitions, constants, enums, and macros. |
| `--emit-cheader` | Output a C header (`.h`) instead of compiling. Emits `#pragma once`, `#include <stdint.h>`, typedefs for structs, extern function declarations, `#define` constants, and enums. |
| `-i` / `--interactive` | Start the REPL (interactive Read-Eval-Print Loop). |
| `-I<path>` / `-I <path>` | Add a directory to the import search path. Searched after the source file's directory and `lib/`. |
| `--repl-format=text\|json` | Format for REPL error output. Default `text` (legacy `  error: <msg>` lines). With `json`, each error is emitted as a single-line JSON object: `{"file":..,"line":..,"message":..}`. Suitable for agent-driven REPL sessions. |

## REPL

Start with `nucleusc -i`. The REPL reads one form at a time, JIT-compiles it, and prints the result. Multi-line input is supported (the REPL detects unbalanced parentheses and prompts for continuation lines with `...>`).

Supported top-level forms in the REPL: `defn`, `defvar`, `defconst`, `defenum`, `defstruct`, `include`, `extern`, `import`, `defmacro`, `def-rmacro`, `compile-time`, `macroexpand`, `macroexpand-1`, `macroexpand-all`. Any other form (including bare symbols, integers, and function calls) is evaluated as an expression.

Result printing is type-aware: integer kinds print as decimal, string literals print as `"..."` with escapes, quoted forms (`'foo`, `(quote ...)`) print using the AST printer, and other pointer values print as `#<ptr 0x...>`. The reader rejects `#<...>` syntax with a clear error so a printed unreadable value can't silently round-trip as input.

`macroexpand` / `macroexpand-1` print the expansion of a quoted form. `(macroexpand '(when c b))` expands to fixpoint; `(macroexpand-1 '(when c b))` expands one step. An optional integer second arg overrides the depth: `(macroexpand 'form 2)` expands at most twice; `(macroexpand 'form -1)` expands to fixpoint. Subforms are not recursed into (matches Common Lisp `macroexpand`). If the form is not a macro call (head is missing or not a registered macro), the REPL prints `not a macro call: <form>` rather than echoing the input unchanged. `macroexpand-all` expands the head to fixpoint and then recursively expands every subform; quoted/quasiquoted forms are left untouched.

Functions defined in the REPL persist across inputs and can call each other. All libc functions (stdio, stdlib, string, ctype, unistd) are pre-loaded — no `(include ...)` needed.

Imported libraries work: `(import mathlib)` makes `square`, `cube`, etc. available. The standard macros (`if`, `when`, `unless`, `for`, `dotimes`, `->`) are auto-imported at REPL startup, so they're usable without `(import macros)`. The `Node` struct and `NODE-*` constants are pre-registered for macro support.

Errors in the REPL are caught and recovered; the REPL continues after an error (including IR parse errors and JIT errors). With `--repl-format=json`, each REPL-level error (missing form arg, JIT lookup failure, recovered error) is emitted as a single-line JSON object on stderr.

Functions can be redefined. Redefining a `defn` confirms with `redefined` (vs. `defined` for first sight) and the new body wins for **all** callers, including ones JIT'd before the redefinition. This is implemented by routing every call through a stable `@<name>` thunk that loads the latest impl pointer from `@<name>.tgt`; each definition is JIT'd as `@<name>.impl.<N>` under its own LLVM ORC resource tracker, and the previous tracker is removed on redefinition. `(addr-of foo)` returns the thunk address, so captured pointers also see the latest impl.

Limitations:
- Functions need explicit `(return ...)` to return values (same as batch mode).
- Redefining a function with a different signature is allowed by the REPL but existing callers were compiled against the old signature; calls through them have undefined behavior. Restart the session if the type changes.
- `set!` only works on local variables, not globals.
- `defvar` initializers must be integer literals (no expressions).
- `(import node)` brings in the AST utilities (`make-cell`, `node-at`, `node-len`, `node-is-list`); they allocate via `arena-alloc` and the arena initializes lazily on first call.
- stdout from JIT'd code is line-buffered (`setvbuf(stdout, NULL, _IOLBF, 0)` is called on REPL startup) so printf output appears immediately in both terminal and pipe-driven sessions.

## .nuch Header Format

A `.nuch` file is an S-expression file containing declarations extracted from a Nucleus source file. It allows importing a library's interface without its source code — function bodies are resolved at link time from the corresponding `.o` file.

```lisp
; .nuch header for lib/mathlib.nuc
(declare square:i32 (x:i32))
(declare cube:i32 (x:i32))
```

Supported forms: `declare` (function signatures), `defstruct`, `defconst`, `defenum`, `defmacro` (full body preserved), `defmethod` (one overloaded method, carrying its mangled symbol explicitly), and `defprotocol` / `extend` (protocol definitions and conformance facts, exported verbatim). A solitary function exports as `declare`; an overloaded one exports a `defmethod` per method so each keeps its distinct symbol:

```lisp
(defmethod "@area.pCircle" (area i32) ((c (ptr Circle))))
(defmethod "@area.pRect"   (area i32) ((s (ptr Rect))))
```

Importing a `.nuch` with `defmethod` forms registers the methods for dispatch in the importing unit and emits an LLVM `declare` under each mangled symbol (resolved at link time). Imported `defprotocol` forms re-register the protocol; imported `extend` forms record the conformance fact without re-checking it (the exporting unit already verified it). See [Polymorphism](#polymorphism-overloaded-defn-multimethods) and [Protocols](#protocols-defprotocol-and-extend).

## Top-Level Forms

| Name | Description | C Equivalent |
|------|-------------|--------------|
| `defn` | Define a function. Supports `&rest` for variadic functions: `(defn name (a:t &rest xs:elem) ...)`. The rest parameter receives a `Node*` cons-list head built at the call site (so each call site emits `@make-cell` calls and the program must define a compatible `make-cell`). The element type annotation is documentation only — non-`ptr` args are `inttoptr`'d into `Node.car`. `&rest` functions are not directly C-callable; calling through a function pointer requires manually constructing the rest list. `&rest` must be the second-to-last param. **Overloadable:** defining `defn` again with the same name but different parameter types adds a method — see [Polymorphism](#polymorphism-overloaded-defn-multimethods). | function definition |
| `defconst` | Define a compile-time constant | `#define` / `enum` constant |
| `defenum` | Define an enumeration | `enum` |
| `defvar` | Define a global variable | global variable definition |
| `defstruct` | Define a struct type | `struct` |
| `defprotocol` | Define a protocol: a named set of required method signatures (types may mention `Self`). Compile-time only; emits no code. See [Protocols](#protocols-defprotocol-and-extend). | — (concept: interface/trait) |
| `extend` | Assert conformance `(extend Type Protocol)`: checks that each required signature resolves to a concrete method with `Self → Type`, then records the fact. Code-free. See [Protocols](#protocols-defprotocol-and-extend). | — |
| `include` | Include a C standard library module. `(include stdio)` preprocesses `stdio.h` with `clang -E` and imports all extern function declarations. Any C header can be used: `(include math)` includes `math.h`. | `#include` |
| `import` | Import a Nucleus library or C header. `(import name)` resolves `name.nuc` (source) or `name.nuch` (header) from source directory, `lib/`, or `-I` paths. `(import "stdio.h")` preprocesses a C header with `clang -E` and imports extern function declarations. Source imports inline all definitions; header imports emit `declare` (extern) for functions. Duplicate imports are silently skipped. | — |
| `declare` | Declare an external function signature `(declare name:rettype (params...))`. Used in `.nuch` header files and at the top level. | function prototype |
| `extern` | Declare an external (foreign) global variable | `extern` declaration |
| `defmacro` | Define a compile-time macro `(defmacro name (params...) body...)`. Supports `&rest` for variadic macros: `(defmacro name (a b &rest rest) ...)` — `rest` receives a cons list of remaining args. | macro |
| `def-rmacro` | Define a reader macro `(def-rmacro "prefix" symbol)`. When `prefix` appears at the start of a token, the reader wraps the next form: `(symbol form)`. Built-in reader macros: `'` (quote), `` ` `` (quasiquote), `~` (unquote), `~@` (unquote-splice), `@` (deref). | — |
| `exclude-prelude` | Suppress the implicit `(import prelude)` for this source file. Must be the first top-level form; takes no arguments. Use when a file should compile against the bare language without the standard macros, `Node` struct, or `(include string)` declarations. | — |

## Type Syntax and Desugar

Types are attached to names with `:` syntax: `name:type` (e.g., `x:i32`, `main:int`). A desugar pass runs before compilation, splitting colon-typed symbols in binding positions into canonical list form:

- `foo:int` → `(foo int)` — name and type as separate symbols
- `node:ptr:Node` → `(node (ptr Node))` — pointer-to-Node
- `pp:ptr:ptr:Node` → `(pp (ptr ptr Node))` — pointer-to-pointer-to-Node

Pointers to a typed element use the `ptr` constructor: `(ptr T)` is a pointer to `T`, and `(ptr ptr T)` chains. Bare `ptr` (with no element) remains the opaque `void*` pointer.

In inline type positions (the type argument of `cast`, `sizeof`, `alloca`), either the canonical list form or the colon sugar works: `(cast (ptr Node) x)` and `(cast ptr:Node x)` are equivalent.

Desugar operates on binding positions in `defn`, `defvar`, `defstruct`, `extern`, `declare`, and `let`. Expression bodies are not desugared; typed symbols in value position (e.g., from macro expansion) are handled by the compiler directly.

Both the sugared `:` syntax and the canonical list form are accepted in all binding positions. Macros that manipulate types can work with the canonical list form; macros that don't care about types can use the `:` sugar and it will be desugared before compilation.

Macro output is desugared before compilation, so macro-generated code can use either form.

## Standard Macros (`lib/macros.nuc`)

Defined via `defmacro`. The compiler auto-imports `lib/prelude.nuc` (which defines the `Node` struct, the `NODE-*` enum, and `(import macros)`) into every program, so all of these are available without an explicit `(import macros)`. To opt out — e.g. when a source file should compile against the bare language with no macros, no `Node` type, and no `string` libc declarations — make `(exclude-prelude)` the first form in the file.

| Name | Signature | Expands To |
|------|-----------|------------|
| `if` | `(if test then else)` | `(cond test then true else)` |
| `when` | `(when condition body...)` | `(cond condition (do body...))` |
| `unless` | `(unless condition body...)` | `(cond (not condition) (do body...))` |
| `zero?` | `(zero? x)` | `(= x 0)` |
| `null?` | `(null? x)` | `(= x null)` |
| `for` | `(for (var:type init) test step body)` | `(let (var:type init) (while test body step))` |
| `dotimes` | `(dotimes (var:type n) body)` | `(let (var:type 0) (while (< var n) body (inc! var)))` |
| `->` | `(-> x form ...)` | Threads `x` through each form. If a form contains `_`, the value replaces `_`; otherwise inserts as first arg (thread-first). Bare symbols wrap as `(sym value)`. `_` is only special inside `->`. |

## Variadic Arithmetic

`+ - * /` are macros that expand to nested binary primitive calls. They live in `lib/macros.nuc` and are available in every program via the auto-imported prelude. The binary primitives `_+ _- _* _/` are the actual binops; the macros exist to break the expansion cycle.

| Form          | Expansion                                       |
|---------------|-------------------------------------------------|
| `(+)`         | `0`                                             |
| `(+ x)`       | `x`                                             |
| `(+ a b ...)` | `(_+ a (+ b ...))` — right-fold                |
| `(*)`         | `1`                                             |
| `(* a b ...)` | `(_* a (* b ...))` — right-fold                |
| `(- x)`       | `(_- 0 x)` — unary negation                    |
| `(- a b)`     | `(_- a b)`                                     |
| `(- a b ...)` | `(- (_- a b) ...)` — left-fold                 |
| `(/ x)`       | `(_/ 1 x)` — integer reciprocal                |
| `(/ a b ...)` | `(/ (_/ a b) ...)` — left-fold                 |

## Special Forms

`do`, `let`, and `cond` are *expressions*: each yields the value of its
last evaluated sub-expression. For `cond`, every live branch must
produce the same type, otherwise the form's value is `void` (which is
fine for statement position but rejects use in value position). If a
`cond` has no `true` final clause, the implicit fallthrough contributes
`undef` of the result type. `if` (which expands to `cond`) inherits
this behavior. `while` is statement-shaped: it always yields `void`.

`defn` implicitly returns its last expression's value when control
reaches the end of the body without an explicit `return`. The last
expression's type must match the declared return type; if the last
expression yields `void` (e.g., a side-effect or no-return call like
`die-at`), a default zero/null of the return type is emitted.

| Name | Description | C Equivalent |
|------|-------------|--------------|
| `do` | Sequence multiple expressions; yields the last | `{ ... }` block |
| `let` | Bind local variables; yields the body's last expression | local variable declaration |
| `with` | Like `let`, but auto-frees any binding whose init expression is a libc allocator (`malloc`/`calloc`/`realloc`/`strdup`, possibly through `cast`). Frees fire on fall-through and on early `return` from inside the body. Disarm a single binding by storing `null` to it (`free(NULL)` is a no-op) — useful when the pointer escapes via the body. | `let` + scoped `free` |
| `cond` | Multi-way conditional; yields the matched branch's value (strict-typed across branches) | `if` / `else if` / `else` chain |
| `while` | Loop; yields `void` | `while` |
| `set!` | Assign to a variable | `x = val` |
| `inc!` | Increment a variable | `x++` / `x += 1` |
| `return` | Return from function | `return` |
| `not` | Logical negation | `!x` |
| `and` | Short-circuit logical AND | `&&` |
| `or` | Short-circuit logical OR | `\|\|` |
| `cast` | Type cast | `(type)x` |
| `addr-of` | Take address of a variable | `&x` |
| `deref` | Dereference a pointer (reader sugar: `@p` → `(deref p)`) | `*p` |
| `ptr-set!` | Write through a pointer | `*p = val` |
| `ptr+` | Pointer arithmetic | `p + n` |
| `.` | Struct field access | `s.field` |
| `.set!` | Struct field assignment | `s.field = val` |
| `get` | Member access / field read: `(get s 'field)` ≡ `(s field)` ≡ `(. s field)`; overridable per type. See [Callable values](#callable-values-non-function-call-position) | `s.field` |
| `invoke` | General call on a value: `(invoke s 3)` ≡ `(s 3)`; user-defined (`Seq`/`Call`) | `s(3)` / `s[3]` |
| `sizeof` | Size of a type | `sizeof(T)` |
| `alloca` | Stack-allocate memory | `alloca()` / VLA |
| `char` | Character literal | `'c'` |
| `aref` | Array element access | `arr[i]` |
| `aset!` | Array element assignment | `arr[i] = val` |
| `quote` | Yields its argument as a `Node*` (reader sugar: `'x` → `(quote x)`). Quoted symbols are interned — see [Symbols](#symbols). | — |
| `quasiquote` | Like `quote` but `~expr` splices a runtime value and `~@list` splices a list (reader: `` `x ``, `~x`, `~@x`) | — |
| `compile-time` | Execute body forms at compile time via LLVM JIT; output goes to stderr | — |
| `funcall` | Call a typed function pointer: `(funcall fn args...)`. The function pointer must have a `TY-FN` type with known return type and parameter types. | `fn(args...)` |
| `funcall-void` | Call a function pointer with no arguments and no return value | `fn()` |
| `funcall-ptr-1` | Call a `ptr` function pointer with one `ptr` argument, returning `ptr` | `fn(arg)` |
| `funcall-ptr-i32` | Call a `ptr` function pointer with no arguments, returning `i32` | `((int(*)())fn)()` |
| `funcall-ptr-i64` | Call a `ptr` function pointer with no arguments, returning `i64` | `((long(*)())fn)()` |
| `funcall-ptr-ptr` | Call a `ptr` function pointer with no arguments, returning `ptr` | `((void*(*)())fn)()` |
| `gensym` | Return a fresh unique symbol `Node*` (e.g. `__gs_0`); for use in macro bodies to avoid variable capture | — |

## Binary Operators

| Name | Description | C Equivalent |
|------|-------------|--------------|
| `+` | Addition | `a + b` |
| `-` | Subtraction | `a - b` |
| `*` | Multiplication | `a * b` |
| `/` | Division (signed: `sdiv`, unsigned: `udiv`) | `a / b` |
| `%` | Remainder (signed: `srem`, unsigned: `urem`) | `a % b` |
| `bit-and` | Bitwise AND | `a & b` |
| `bit-or` | Bitwise OR | `a \| b` |
| `bit-xor` | Bitwise XOR | `a ^ b` |
| `bit-shl` | Shift left | `a << b` |
| `bit-shr` | Shift right (signed: arithmetic `ashr`, unsigned: logical `lshr`) | `a >> b` |
| `=` | Equal | `a == b` |
| `!=` | Not equal | `a != b` |
| `<` | Less than (signed: `slt`, unsigned: `ult`) | `a < b` |
| `<=` | Less or equal (signed: `sle`, unsigned: `ule`) | `a <= b` |
| `>` | Greater than (signed: `sgt`, unsigned: `ugt`) | `a > b` |
| `>=` | Greater or equal (signed: `sge`, unsigned: `uge`) | `a >= b` |

Operators are **ordinary generic functions** (§10.3). Each built-in operator is a generic; when the operands are built-in numerics (or pointers, for comparisons) the resolver selects the built-in method, which emits its inline instruction (`add nsw`, `icmp slt`, …) directly — a **front-end peephole**, not an LLVM pass — so there is no `call` and the IR is byte-identical to a non-polymorphic compiler even at `-O0`.

**Mixed operands now resolve** (§10.3): an untyped integer literal adapts to the other operand's type (`(+ x 1)` with `x:i64`), and a narrower integer/float widens to the wider (`(+ i32 i64)`, `(+ f32 f64)`). Genuinely mismatched operands (e.g. two different typed pointers in arithmetic, or mixed signedness) are still rejected.

**User operator overloading.** Because operators are generics, a type becomes "addable"/"comparable" by defining a method. The variadic `+ - * /` macros fold to the binary primitives `_+ _- _* _/`, so arithmetic is overloaded on those names; the comparison operators are overloaded directly:

```lisp
(defstruct V2 x:i32 y:i32)
(defn _+:ptr:V2 (a:ptr:V2 b:ptr:V2) …)   ; (+ u v) now dispatches here
(defn =:i1     (a:ptr:V2 b:ptr:V2) …)    ; (= u v) dispatches here
```

A user operator method is emitted under a mangled symbol (`@add.pV2.pV2`, `@eq.pV2.pV2` — the symbols `+`/`=` are mapped to IR-safe mnemonics). A call with operand types that match no user method falls back to the built-in inline peephole.

The **standard numeric protocols** live in `lib/numeric.nuc`: `Eq` (`= !=`), `Ord` (`< <= > >=`, a superset of `Eq` via `(extend Ord Eq)`), and `Num` (`_+ _- _* _/`). Built-in numeric types conform automatically (their intrinsic operators satisfy the requirements); a user type conforms by defining the methods and asserting `(extend ptr:MyType Ord)`. See [Bounded generic `defn`](#bounded-generic-defn).

## Polymorphism: overloaded `defn` (multimethods)

A `defn` whose name already exists but whose **parameter types differ** does not redefine — it adds a *method* to that name. Calls dispatch on the whole argument tuple (multiple dispatch).

```lisp
(defstruct Circle rad:i32)
(defstruct Rect w:i32 h:i32)

(defn area:i32 (c:ptr:Circle) (return (* (* (. c rad) (. c rad)) 3)))
(defn area:i32 (s:ptr:Rect)   (return (* (. s w) (. s h))))

(defn kind:i32 (x:i32) (return 1))   ; overload on primitive type
(defn kind:i32 (x:f64) (return 2))

(defn sum:i32 (a:i32) (return a))            ; overload on arity
(defn sum:i32 (a:i32 b:i32) (return (+ a b)))
```

**Symbol mangling.** A name with a single method keeps its unmangled symbol `@name` and stays C-callable. A name with two or more methods becomes an overload set: each method is emitted under a mangled symbol `@name.<tok>...` where each `<tok>` names a parameter type (`i32`, `f64`, `pCircle` for `ptr:Circle`, the struct name for a by-value struct, …). The mangle decision is made after a whole-file prescan, so all methods of a name agree.

**Resolution (tiers).** A call resolves in order: **(0)** an exact match (structural type equality: primitives by identity, structs by definition, pointers by pointee); **(1)** a bounded-generic template whose constraints the arguments satisfy; **(2)** a safe **widen / untyped-int-literal** adaptation — an `i32` argument supplied where an `i64` method exists, or a literal `1` supplied where the parameter is `i8`/`f64` (the chosen arguments are coerced to the parameter types). A unique match wins; an ambiguous or absent match is a compile error listing the offending name. *(A `defcast`-based coercion tier is not implemented — no cast-rule registry exists in-tree.)*

**Return types may differ per method** (`(defn parse:i32 …)` vs `(defn parse:f64 …)` is fine since they dispatch on arguments). A return type bound only by no argument (no way to choose from the call) is out of scope.

**Cross-unit.** Overloaded functions export through `.nuch` as `defmethod` forms and dispatch correctly from an importing translation unit (link the importer against the library's `.o`). See [.nuch Header Format](#nuch-header-format).

**Struct-typed parameters.** Because overloading on struct types is a primary use case, a `defn` parameter may be typed as a (pointer to a) struct defined later in the same file; struct names are pre-registered before signatures are scanned.

Implementation: a generic registry (`g-generics`) holds each name's method set; `emit-defn` emits each method under its resolved symbol; `emit-dispatch` routes a call head to an intrinsic operator, an overloaded set, or an ordinary scope-bound function. Solitary functions and C/extern calls take the ordinary path and emit byte-identical IR.

## Protocols: `defprotocol` and `extend`

A **protocol** names a capability — a set of required method signatures — and is purely compile-time: it emits no code. The signatures may mention the type variable `Self`.

```lisp
(defprotocol Shape
  (area:i32  (self:ptr:Self))
  (label:ptr (self:ptr:Self)))
```

`extend Type Protocol` is a **checked, code-free conformance assertion**. It runs after the whole-file prescan: for each required signature it substitutes `Self → Type` and requires that a concrete method already resolves at the exact tier (the implementations are ordinary overloaded `defn`s). It records the `(Type, Protocol)` fact and emits nothing.

```lisp
(defn area:i32  (s:ptr:Circle) (return (* (* (. s rad) (. s rad)) 3)))
(defn label:ptr (s:ptr:Circle) (return "circle"))

(extend Circle Shape)   ; OK — both methods exist for Circle
```

If a required method is missing, compilation fails with a diagnostic naming each absent method (e.g. `Square does not implement Shape.label`) — the precise error an overload set alone cannot give.

**`Self` and pointer-ness.** Conformance matching is by exact type, so the protocol signature's pointer-ness must match the implementation's. Since structs are conventionally passed by pointer, write `(self:ptr:Self)` to match `(defn … (s:ptr:Circle) …)`; a by-value `(self:Self)` would require a by-value `(s:Circle)` implementation.

**No code, multiple protocols per implementation.** Because `extend` adds no methods, one concrete function can satisfy several protocols at once — the protocol is a *predicate over the method set*, not the owner of an implementation.

**Protocol inheritance.** `extend`'s subject may itself be a protocol: `(extend Ord Eq)` declares that conforming to `Ord` additionally requires conforming to `Eq`, so `(extend i32 Ord)` records `(i32, Eq)` too. Operators satisfy protocol requirements for built-in numerics with no user method, so `lib/numeric.nuc`'s `Eq`/`Ord`/`Num` apply to `i32`/`i64`/`f32`/`f64` out of the box.

**Cross-unit.** `defprotocol` and `extend` (type-conformance and protocol-inheritance) export verbatim through `.nuch`; an importing unit re-registers the protocol and trusts the recorded conformance (it does not re-check). See [.nuch Header Format](#nuch-header-format).

*Not yet implemented (within protocols):* inline-`defn` sugar inside `extend`, and the dynamic `(dyn Protocol)` form. Conformance currently requires a concrete (non-generic) implementation.

## Bounded generic `defn`

A `defn` whose parameter list carries a `&where` clause is a **bounded generic
template**: it is generic over one or more named type variables, each constrained
to a protocol. The body is *monomorphized* — re-emitted with the variables
substituted by concrete types — once per distinct instantiation, and cached.
Statically dispatched, zero runtime overhead.

```lisp
(import numeric)                          ; Eq / Ord / Num over the operators

(defn maxv:T (a:T b:T &where (Ord T))     ; T is a type variable bounded by Ord
  (if (< a b) b a))                       ; operators dispatch on T directly

(maxv 3 9)        ; → stamps @maxv.i32.i32; (< a b) is an inline icmp
(maxv 2.5 1.5)    ; → stamps @maxv.f64.f64; (< a b) is an inline fcmp
```

Because operators are generic methods (§10.3), the body uses `<` directly and the
constraint is the standard `Ord`; built-in numeric types conform automatically.

- **`&where`** follows all value parameters; each constraint is single-variable
  `(Protocol Var)`. Multiple constraints are allowed (e.g. `&where (Ord T) (Show U)`).
- **Type variables are declared-only:** a name is a type variable iff it is bound
  in a `&where` constraint. Any other unknown type identifier is still an
  `unknown type` error, so typos stay caught.
- **Binding** gathers the concrete type at every bare occurrence of a variable
  among the arguments and requires they agree; the bound type must conform
  (nominally, via `extend`) to the variable's protocol(s). There is no unifier:
  variables appear only in **bare** parameter/return positions. A nested position
  (`(ptr T)`, etc.) is rejected (deferred to full parametric generics).
- **Abstract return (B1).** The return type may be a type variable bound by a
  parameter (`maxv:T` above); the concrete return is known per instantiation.
  A return variable bound by *no* parameter (Haskell `read`) is rejected — it
  needs the deferred `(dyn …)` form.
- **Resolution: concrete beats generic.** An exact concrete method always wins
  over a generic template for the same name (tier 0 ≫ tier 1).
- **Def-time checking (A2).** A template body is type-checked **once at its
  definition** against the abstract protocol interface, *before* any call. A value
  of type variable `T` is typed abstractly; a call on it that resolves to a method
  of `T`'s `&where` protocols (with `Self → T`), or to another generic whose
  constraints `T`'s constraints satisfy, is checked precisely (and yields a precise
  result type). The check is **lenient**: the only hard def-time error is a
  genuinely unknown function name (a typo) —
  ```lisp
  (defn maxv:T (a:T b:T &where (Ord T))
    (when (greater a b) …))   ; error at the defn: unknown function 'greater'
  ```
  A *known* operation that the abstract interface can't confirm — an operator
  (`(< a b)`), or a foreign/variadic call (`(printf …)`) on an abstract value — is
  **deferred to stamp time** rather than rejected, since it may well be valid for
  the concrete type (A1 catches it if not). When such a deferred call *does* fail
  for a concrete instantiation, the stamp-time error carries an instantiation note
  pointing back to the call site:
  ```
  file:NN: error: no matching method for overloaded 'dbl' with given argument types
    note: while instantiating @weird.f64.f64 (requested at file:12)
  ```
  The constraint protocol's existence is also checked at the `defn`.
- **Cross-unit.** A generic template exports verbatim through `.nuch`
  (`(defn (maxv T) ((a T) (b T) &where (Ord T)) …)`); an importing unit
  re-registers it (trusting the exporter's A2 check) and stamps its own
  instantiations locally, calling the exporter's concrete protocol methods by
  their mangled symbols.

Implementation: templates are registered as `METHOD-GENERIC` in `g-generics`
(retaining the body); `generic-resolve` adds the protocol-bound tier and, on a
unique match, `generic-instantiate` substitutes type variables, stamps a concrete
method (registered immediately so the call site can name its symbol) and queues
the body on a worklist drained at the end of the top-level loop. The A2 check
(`check-generic-templates` / `gcheck`) runs at the outermost top-level after all
names/protocols/conformances are registered, typing the body with parameters
bound to abstract `TY-TYVAR` types — which never reach codegen, since templates
emit only after monomorphization.

### Bound kinds: named protocols, blanket (`Any`/`Struct`), and `Valid`

A `&where` constraint names one of three kinds of bound (a name is still a type
variable iff it appears in a constraint, so every kind keeps tyvars declared-only
and typos caught):

| Bound | Conformance | Checked |
|---|---|---|
| named protocol (`Ord`, `Num`, …) | nominal, via `extend` | def-site (A2) + at the call |
| **blanket** `Any` / `Struct` (§10.1) | automatic / structural | nothing (`Any`); is-a-struct (`Struct`) |
| **`Valid`** (§10.2) | structural, **inferred from the body** | at the call site |

- **`Any`** is the no-constraint constraint — every type conforms, no methods
  required. It lets a fully generic function name its variable: `(defn id:T (x:T
  &where (Any T)) (return x))`. Operations on an `Any`-bound value are deferred to
  stamp time.
- **`Struct`** holds for any struct type or pointer-to-struct. (Its member-access
  `get` method is supplied by callable-values; see `design/stage9/callable-values.md`.)
  Both are **hardcoded** built-ins; a user-declarable blanket facility is parked in
  `design/stage999-future.md`.
- **`Valid`** does not name a protocol — the required interface is *inferred* from
  the body. At each call site the concrete type is substituted and the body is
  type-checked **without emitting** (the per-call-site non-emitting stamp), so a
  type that can't support an operation is rejected **at the call site**, and so are
  uses of values *derived* from `T`:
  ```lisp
  (defn twice:T (x:T &where (Valid T)) (+ x x))
  (twice 21)        ; ok — i32 supports +
  (twice some-ptr)  ; error at this call: 'ptr:Blob' does not satisfy the Valid bound of 'twice'
  ```
  `Valid` is itself written explicitly (it *nominates* structural checking); a bare
  `&where (T)` with no protocol remains an error.
  
Using `Valid` with a public API is risky whether it's inside the library code or a user
method on a library function because it may unexpectedly match unowned call sites. 
It's safer to prefer named protocols and treat `Valid` as an escape hatch.

*Not yet implemented:* same-name overloading that mixes imported and
locally-defined methods; `&rest` together with `&where`; REPL generic
instantiation; full parametric generics (nested/multiple unbound variables,
generic struct layout).

## Callable values (non-function call position)

A **non-function value in head position**, `(s arg…)`, is no longer an error — it
dispatches by its sole argument into one of two reserved generics:

| call | argument | desugars to | meaning |
|---|---|---|---|
| `(s field)` / `(s 'field)` | a **literal symbol** | `(get s 'field)` | member access |
| `(s 3)` / `(s a b…)` | anything else | `(invoke s 3 …)` | indexing / general call |

A **bare symbol argument is always a field selector**, never a variable — field
interpretation wins so it never depends on what is in scope. To dispatch a value
held in a variable, call `invoke` explicitly: `(invoke s x)`.

**`get` — member access (the `Struct` default).** Every struct conforms to the
built-in `Struct` blanket protocol, whose `get` is supplied by an **intrinsic**: a
literal selector const-folds to a static `getelementptr`+`load`, **byte-identical
to `.` and zero-overhead**. So `(c rad)` ≡ `(. c rad)` ≡ `(get c 'rad)`.

```lisp
(defstruct Point x:i32 y:i32)
(p x)          ; ≡ (. p x) — a plain field load
```

The intrinsic is **overridable**: a concrete user `get` method for a type sits at
tier 0 and out-ranks the blanket intrinsic, so it owns *all* member access on that
type. A user `get` takes the selector as an interned symbol (`ptr`):

```lisp
(defn get:i32 (self:ptr:Temp sel:ptr)
  (if (= sel 'f) (return …) (return (. self c))))   ; (t f) and (t c) both route here
```

**`invoke` — indexing / general call.** A type "becomes callable" by defining
`invoke` methods; there is **no** built-in default (a struct pointer with an
integer selector is unbound unless it defines an integer `invoke` — it does *not*
fall back to `aref`). Dispatch is ordinary multimethod resolution on the whole
argument tuple, so the same value answers both forms by argument:

```lisp
(defstruct Vec data:ptr:i32 len:i32)
(defn invoke:i32 (self:ptr:Vec i:i32) (return (aref (. self data) i)))
(v 3)          ; ⇒ (invoke v 3) → element access
(v len)        ; ⇒ (get v 'len) → the length field
```

The `Seq` and `Call` protocols (`lib/seq.nuc`) name the `invoke` capability:
`Seq` is integer-indexable (`(invoke:i32 (self:ptr:Self i:i32))`), `Call` is a
unary `ptr→ptr` function object. Because protocols fix concrete signatures (no
associated types yet), the element/argument types are concrete.

**Computed selector (`get` only).** An *explicit* `(get callee expr)` whose
selector is a compound expression (not a bare/quoted symbol) reads a field chosen
at runtime: the selector is compared by pointer identity against the struct's
interned field symbols. Restricted to **homogeneous** structs (all fields one
type) so the result type is well-defined; a heterogeneous struct is a clear error.

**Arbitrary-expression and function-pointer heads.** The head need not be a
symbol: `((mk-vec) 3)` and `(@p 3)` emit the head once and route the same way. A
head whose value is a **function pointer** folds to an indirect call, so
`(f a b)` works for a local/global fn-pointer variable `f` and the explicit
`funcall`/`funcall-ptr-*` forms are now compiler-internal (still accepted).

Everything resolves at compile time to a static GEP+load, a direct `call` to a
resolved method, or an indirect `call` through a fn-pointer — no dispatch object,
no vtable. `get`/`invoke` overloads and `Seq`/`Call` export through the existing
`defmethod`/`defprotocol`/`extend` machinery; there is no new `.nuch` form.

## Literal Values

| Name | Type | C Equivalent |
|------|------|--------------|
| `null` | ptr | `NULL` |
| `true` | bool (i1) | `1` / `true` |
| `false` | bool (i1) | `0` / `false` |

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
| `ptr` | Opaque pointer | `void*` |
| `void` | No value | `void` |

Float literals: `1.5`, `-0.25`, `1e10`, `1.5e-3`, `.5`. Default type is `f64`; narrow with `(cast f32 ...)`. Widen `f32`→`f64` and convert int↔float with `cast`. Special values use Scheme syntax: `+inf.0`, `-inf.0`, `+nan.0`. Float arithmetic uses `+ - * / %` and comparisons use `= != < <= > >=` (LLVM `fadd`/`fcmp`); operands must have the same float width — promote with explicit `cast`. Mixing float and integer operands without a cast is a compile error.

### Function Pointer Types

Function pointer types are written as `(fn:rettype (param-types...))` in sugared form, or `((fn rettype) (param-types...))` in desugared/canonical form.

In parameter position (where `(` would terminate the symbol for colon sugar), use the canonical list form:

```lisp
(defn apply:i32 ((f (fn i32) (i32 i32)) a:i32 b:i32)
  (return (funcall f a b)))
```

In `let` bindings, the binding name is also a list:

```lisp
(let ((f (fn i32) (i32 i32)) some-function)
  (funcall f 1 2))
```

A `defn` function name used in value position decays to a function pointer, matching C semantics:

```lisp
(defn add:i32 (a:i32 b:i32) (return (+ a b)))
(apply add 3 4)  ; passes add as a function pointer
```

### Integer Type Coercion

Integer types are implicitly coerced in assignment contexts (`let`, `set!`, `.set!`, `aset!`, `ptr-set!`):
- Same type: no conversion needed
- Same width, different sign (e.g. `i32` ↔ `ui32`): reinterpret (no IR instruction)
- Widening: `sext` for signed source, `zext` for unsigned source
- Narrowing: `trunc`

Mixed-sign binary operations (e.g. `i32 + ui32`) are rejected with a compile error. Use explicit `(cast ...)` to resolve.

## Libc Bindings

Pre-declared C standard library functions, available without `extern`.

### stdio

| Function | Signature | C Header |
|----------|-----------|----------|
| `printf` | `(ptr, ...) -> i32` | `<stdio.h>` |
| `fprintf` | `(ptr, ptr, ...) -> i32` | `<stdio.h>` |
| `snprintf` | `(ptr, i64, ptr, ...) -> i32` | `<stdio.h>` |
| `fputc` | `(i32, ptr) -> i32` | `<stdio.h>` |
| `fputs` | `(ptr, ptr) -> i32` | `<stdio.h>` |
| `fopen` | `(ptr, ptr) -> ptr` | `<stdio.h>` |
| `fclose` | `(ptr) -> i32` | `<stdio.h>` |
| `fread` | `(ptr, i64, i64, ptr) -> i64` | `<stdio.h>` |
| `fwrite` | `(ptr, i64, i64, ptr) -> i64` | `<stdio.h>` |
| `fseek` | `(ptr, i64, i32) -> i32` | `<stdio.h>` |
| `ftell` | `(ptr) -> i64` | `<stdio.h>` |
| `rewind` | `(ptr) -> void` | `<stdio.h>` |
| `perror` | `(ptr) -> void` | `<stdio.h>` |
| `open_memstream` | `(ptr, ptr) -> ptr` | `<stdio.h>` |
| `fflush` | `(ptr) -> i32` | `<stdio.h>` |
| `fgets` | `(ptr, i32, ptr) -> ptr` | `<stdio.h>` |

### stdlib

| Function | Signature | C Header |
|----------|-----------|----------|
| `malloc` | `(i64) -> ptr` | `<stdlib.h>` |
| `realloc` | `(ptr, i64) -> ptr` | `<stdlib.h>` |
| `free` | `(ptr) -> void` | `<stdlib.h>` |
| `exit` | `(i32) -> void` | `<stdlib.h>` |
| `strtol` | `(ptr, ptr, i32) -> i64` | `<stdlib.h>` |

### string

| Function | Signature | C Header |
|----------|-----------|----------|
| `memcpy` | `(ptr, ptr, i64) -> ptr` | `<string.h>` |
| `memset` | `(ptr, i32, i64) -> ptr` | `<string.h>` |
| `memcmp` | `(ptr, ptr, i64) -> i32` | `<string.h>` |
| `strlen` | `(ptr) -> i64` | `<string.h>` |
| `strcmp` | `(ptr, ptr) -> i32` | `<string.h>` |
| `strncmp` | `(ptr, ptr, i64) -> i32` | `<string.h>` |
| `strchr` | `(ptr, i32) -> ptr` | `<string.h>` |
| `strndup` | `(ptr, i64) -> ptr` | `<string.h>` |

### ctype

| Function | Signature | C Header |
|----------|-----------|----------|
| `isspace` | `(i32) -> i32` | `<ctype.h>` |
| `isdigit` | `(i32) -> i32` | `<ctype.h>` |

### unistd

| Function | Signature | C Header |
|----------|-----------|----------|
| `dup` | `(i32) -> i32` | `<unistd.h>` |
| `dup2` | `(i32, i32) -> i32` | `<unistd.h>` |
| `close` | `(i32) -> i32` | `<unistd.h>` |
