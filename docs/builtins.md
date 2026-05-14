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

### REPL meta forms

For tooling and interactive use, the REPL recognizes these forms in addition to top-level forms:

| Form | Description |
|------|-------------|
| `(defined? sym)` | Print `1` if the symbol is bound (fn / var / const / macro / struct), else `0`. |
| `(kind-of sym)` | Print one of `fn`, `macro`, `rmacro`, `var`, `const`, `struct`, or `<unbound>`. |
| `(type-of expr)` | Print the static type of an expression in Nucleus syntax (e.g. `i32`, `ptr:Node`). For functions defined via `defn`, prints the full signature `(fn ret name0:t0 name1:t1 ... &rest &optional ...)` with the original parameter names; for function-pointer types and other sources that don't preserve names, positional `pN` is used. Routes through the type-checker without committing IR to the JIT. |
| `(dir)` | List every known name (globals, macros, structs) with a one-line summary. Functions show signatures with parameter names; consts show values. |
| `(apropos "needle")` | Substring search across known names AND docstrings; prints summaries (and the docstring) for matches. The arg may be a string or symbol. |
| `(complete "prefix")` | Prefix search; prints just the matching names — useful for editor completion. |
| `(imports)` | Print resolved paths of all `(import name)` entries, one per line. |
| `(casts)` | Print every registered `defcast` rule as `from -> to via fn`. |
| `(expansion-of form)` | Like `(macroexpand-all 'form)` but takes the form unquoted. |
| `(last-error)` | Print the most recent recovered REPL error (line + message), or `(none)`. JSON-formatted under `--repl-format=json`. |
| `(time form)` | Evaluate `form` via the normal eval path and print elapsed CPU time in microseconds. |
| `(locate sym)` | Print `<file>:<line>` of the symbol's definition. Reports `<unbound>` or `(no source recorded)` for built-in primitives and prelude-registered struct/consts. |
| `(forget sym)` / `(reset! sym)` | Drop a REPL-local definition so the name becomes unbound. For functions, also tears down the impl resource-tracker; the thunk module persists, so the function's signature is locked for the rest of the session (a redefinition with a different signature still requires a session restart). |
| `(trace fn)` / `(untrace fn)` | Toggle entry/exit logging for a function. `trace` JITs a `@<name>.trace` shim with the same ABI, copies the current impl pointer into `@<name>.trace.impl`, and repoints `@<name>.tgt` at the shim. Args/returns are not pretty-printed — only `[trace] enter <name>` / `[trace] exit <name>`. Redefining a traced function silently disables tracing (the redef path overwrites `@<name>.tgt` with the new impl directly). |

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

Supported forms: `declare` (function signatures), `defstruct`, `defconst`, `defenum`, `defmacro` (full body preserved), `defcast` (full form preserved — the conv-fn must already be `declare`d in the same header).

## Top-Level Forms

| Name | Description | C Equivalent |
|------|-------------|--------------|
| `defn` | Define a function. Supports `&rest` for variadic functions: `(defn name (a:t &rest xs:elem) ...)`. The rest parameter receives a `Node*` cons-list head built at the call site (so each call site emits `@make-cell` calls and the program must define a compatible `make-cell`). The element type annotation is documentation only — non-`ptr` args are `inttoptr`'d into `Node.car`. `&rest` functions are not directly C-callable; calling through a function pointer requires manually constructing the rest list. `&rest` must be the second-to-last param. Supports `&optional` for trailing parameters with defaults: `(defn name (a:t &optional (b:t default) ...) ...)`. Each `&optional` param must be a 2-element list `(name:type default-expr)`. Defaults are evaluated at the call site in the caller's scope (Common Lisp semantics), so non-constant defaults like `(next-counter)` produce a fresh value per call. Implicit casts apply to defaults. The compiled function has fixed maximum arity at the LLVM/C ABI level — calling through a function pointer or from C requires supplying every argument including the optional ones. `&optional` cannot be combined with `&rest`. **Docstring**: if the first body form is a string literal AND there is at least one more form after it, that string is captured as the function's docstring (visible via `(doc fn)` and `(apropos)`); a function whose body is a single string literal is treated as returning the string, not as having a docstring. The same convention applies to `defmacro`. | function definition |
| `defconst` | Define a compile-time constant | `#define` / `enum` constant |
| `defenum` | Define an enumeration | `enum` |
| `defvar` | Define a global variable | global variable definition |
| `defstruct` | Define a struct type | `struct` |
| `include` | Include a C standard library module. `(include stdio)` preprocesses `stdio.h` with `clang -E` and imports all extern function declarations. Any C header can be used: `(include math)` includes `math.h`. | `#include` |
| `import` | Import a Nucleus library or C header. `(import name)` resolves `name.nuc` (source) or `name.nuch` (header) from source directory, `lib/`, `-I` paths, `$NUCLEUS_LIB`, or `/usr/local/share/nucleus/lib` (the install-time default used by `make install`). `(import "stdio.h")` preprocesses a C header with `clang -E` and imports extern function declarations. Source imports inline all definitions; header imports emit `declare` (extern) for functions. Duplicate imports are silently skipped. | — |
| `declare` | Declare an external function signature `(declare name:rettype (params...))`. Used in `.nuch` header files and at the top level. | function prototype |
| `extern` | Declare an external (foreign) global variable | `extern` declaration |
| `defmacro` | Define a compile-time macro `(defmacro name (params...) body...)`. Supports `&rest` for variadic macros: `(defmacro name (a b &rest rest) ...)` — `rest` receives a cons list of remaining args. Parameters (and the `&rest` list) are typed `ptr:Node` inside the body, so `(. p car)`, `(. p cdr)`, `(. p kind)`, and `(. p s)` work directly with no `(cast ptr:Node ...)`. The macro can splice a parameter into a quasiquote regardless of the value type the user-supplied expression evaluates to at the call site — see [Macros and pass-through arguments](#macros-and-pass-through-arguments) below. | macro |
| `defcast` | Register an implicit conversion `(defcast From To conv-fn)`. `conv-fn` must be a unary function with signature `To (From)` already in scope; the compiler emits a call to it whenever an arg of `From` is supplied where `To` is expected. Pairs already covered by built-in coercion (identity, int↔int, `f32`→`f64`) are rejected at registration. Rules are unidirectional and non-transitive — declare each direction explicitly, and chain through an intermediate type by writing the chain yourself. Exported in `.nuch` headers. | implicit conversion |
| `def-rmacro` | Define a reader macro `(def-rmacro "prefix" symbol)`. When `prefix` appears at the start of a token, the reader wraps the next form: `(symbol form)`. Built-in reader macros: `'` (quote), `` ` `` (quasiquote), `~` (unquote), `~@` (unquote-splice), `@` (deref). | — |
| `exclude-prelude` | Suppress the implicit `(import prelude)` for this source file. Must be the first top-level form; takes no arguments. Use when a file should compile against the bare language without the standard macros, `Node` struct, or `(include string)` declarations. | — |

## Type Syntax and Desugar

Types are attached to names with `:` syntax: `name:type` (e.g., `x:i32`, `main:int`). A desugar pass runs before compilation, splitting colon-typed symbols in binding positions into canonical list form:

- `foo:int` → `(foo int)` — name and type as separate symbols
- `node:ptr:Node` → `(node (ptr Node))` — pointer-to-Node
- `pp:ptr:ptr:Node` → `(pp (ptr ptr Node))` — pointer-to-pointer-to-Node

Pointers to a typed element use the `ptr` constructor: `(ptr T)` is a pointer to `T`, and `(ptr ptr T)` chains. Bare `ptr` (with no element) remains the opaque `void*` pointer.

### Volatile qualifier

A type can be tagged `volatile` in postfix position — either the list form `(T volatile)` or the sugared `T:volatile`. Loads and stores of a value held at a volatile-qualified storage site (variable, struct field, or pointer target) are emitted as `load volatile` / `store volatile` in LLVM IR; the compiler will not elide, reorder, or coalesce them. Examples:

- `x:i32:volatile` — local volatile variable (sugared)
- `(let (x (i32 volatile)) ...)` — same, list form
- `(defstruct R status:i32:volatile)` — field is volatile
- `(p (ptr (i32 volatile)))` — pointer to volatile `i32`; deref and `ptr-set!` through `p` are volatile

Volatility lives on the storage site, not the value: `volatile T` and `T` are assignment-compatible, and the qualifier is dropped/added at the access. Bare `ptr` (no element) cannot be made volatile — volatility attaches to the pointee, not to opaque pointers.

### Anonymous structs

`(struct field:type ...)` is a type expression accepted wherever a type is expected — `let` bindings, `defn` parameter and return types, `defstruct` field types, `(ptr (struct ...))`, casts. Members use the same `name:type` / `(name type)` form as `defstruct`. Anonymous structs are **memoized by structural content**: two `(struct ...)` literals with the same field name+type list share a single underlying `StructDef`, so values flow between sites that spell out the same shape. The synthetic LLVM type name is `%__anon_struct_h<16-hex>`, derived from a 64-bit FNV-1a hash of the field list.

Examples:

- `(let ((p (ptr (struct x:i32 y:i32))) (alloca (struct x:i32 y:i32))) ...)` — local of anonymous-struct shape
- `(defstruct Outer (pt (struct x:i32 y:i32)) tag:i32)` — nested by value
- `(defn take:i32 ((p (ptr (struct x:i32))))  ...)` — parameter typed as anonymous struct pointer

Writing through a *value-typed* nested anonymous-struct field (`(. o pt)` where `pt` is `(struct ...)` not `(ptr (struct ...))`) currently requires going via a helper or using a pointer-typed nested field, because there is no field-address operator yet.

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

## Macros and pass-through arguments

Macro parameters are typed `ptr:Node` — the macro sees AST. When the macro
splices a parameter into its expansion via `~param`, the resulting form is
compiled as if the user had written that expression directly at the call site,
so the *value* type the parameter evaluates to in the expansion is whatever
the user wrote — `i32`, `ptr:i8`, `f64`, `Foo`, etc.

This means a single macro can take, inspect, and splice arguments of different
value types — there is no value-level `T` to keep consistent across calls;
only the AST representation is uniform.

```
; Pick a printf format from the literal kind, then splice the original
; expression in. The macro inspects (. x kind) at expansion time; the
; spliced ~x is compiled at the call site with whatever type it has.
(defmacro tprint (x)
  (cond (= (. x kind) NODE-INT) `(printf "%d\n" ~x)
        (= (. x kind) NODE-STR) `(printf "%s\n" ~x)
        (= (. x kind) NODE-FLOAT) `(printf "%f\n" ~x)
        true                    `(printf "%p\n" ~x)))

(tprint 42)        ; → (printf "%d\n" 42)        — i32 at the call site
(tprint "hi")      ; → (printf "%s\n" "hi")      — ptr:i8 at the call site
(tprint 3.14)      ; → (printf "%f\n" 3.14)      — f64 at the call site
(tprint some-ptr)  ; → (printf "%p\n" some-ptr)  — ptr at the call site
```

Inside the macro `x` is `ptr:Node`; the spliced `~x` carries no type
constraint into the expansion. The host compiler types the resulting form
using its normal rules.

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
| `case` | Integer-keyed dispatch; lowers to LLVM `switch`. Each clause is `(KEY body...)` where KEY is an integer literal, a list of integer literals, or the symbol `_` (default). With no `_` clause, an unmatched scrutinee hits `unreachable` (UB). Yields the matched branch's value (strict-typed across branches), like `cond`. | `switch` / `default:` |
| `while` | Loop; yields `void` | `while` |
| `set!` | Assign to a variable; yields the assigned value | `x = val` |
| `inc!` | Increment a variable by 1 (or by an optional delta). Yields the new value. | `x++` / `x += n` |
| `dec!` | Decrement a variable by 1 (or by an optional delta). Yields the new value. | `x--` / `x -= n` |
| `label` | Declare a function-scoped label. Forward and backward gotos both resolve. Duplicate declarations of the same name are allowed — the last one in textual order is the canonical target. | label: |
| `goto` | Unconditional jump to a label declared anywhere in the current function. | `goto label` |
| `label-addr` | Yields a `ptr` to a label (for computed gotos). | `&&label` (GCC) |
| `goto-ptr` | Indirect branch to a label address. The IR lists every label declared in the current function as a possible destination. | `goto *p` (GCC) |
| `return` | Return from function | `return` |
| `not` | Logical negation | `!x` |
| `and` | Short-circuit logical AND | `&&` |
| `or` | Short-circuit logical OR | `\|\|` |
| `cast` | Type cast | `(type)x` |
| `addr-of` | Take address of a variable | `&x` |
| `deref` | Dereference a pointer (reader sugar: `@p` → `(deref p)`) | `*p` |
| `ptr-set!` | Write through a pointer; yields the stored value | `*p = val` |
| `ptr+` | Pointer arithmetic | `p + n` |
| `.` | Struct field access | `s.field` |
| `.set!` | Struct field assignment; yields the stored value | `s.field = val` |
| `sizeof` | Size of a type | `sizeof(T)` |
| `alloca` | Stack-allocate memory | `alloca()` / VLA |
| `char` | Character literal | `'c'` |
| `aref` | Array element access | `arr[i]` |
| `aset!` | Array element assignment; yields the stored value | `arr[i] = val` |
| `(StructName init...)` | Compound struct literal. Each `init` is either `(field val)` for a designated initializer or a bare value for a positional one (positional inits fill the next field that has not been designated). Unspecified fields are zero-initialized. Yields `ptr:StructName`, alloca-backed (stack lifetime is the enclosing function). Defining a function with the same name as a struct is a compile-time error (the function would shadow the constructor). | `(struct S){.f = v, ...}` |
| `array` | `(array ElemType init...)` — array compound literal. Each `init` is either `(index val)` (designated) or a bare value (positional). Length is implicit: `max(positional-count, max-designated-index + 1)`. Unspecified slots are zero-initialized. Yields `ptr:ElemType`, alloca-backed. | `(T[]){1, 2, [3] = 99}` |
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

Binary operators require both operands to have the same sign. Mixed-sign operations are rejected at compile time.

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

### Implicit Type Coercion

The following conversions are applied automatically in assignment contexts (`let`, `set!`, `.set!`, `aset!`, `ptr-set!`, implicit return) **and at function call sites** (both direct calls and `funcall`):

- **Pointer ↔ pointer** (any element types): identity, no IR. `ptr`, `ptr:Node`, `ptr:i8` are interchangeable at boundaries; the cast only matters when the result feeds a typed-pointer-only operation (`.`, `aref`, `aset!`, `ptr+`, `deref`).
- **Integer ↔ integer**:
  - Same width, different sign (e.g. `i32` ↔ `ui32`): reinterpret, no IR.
  - Widening: `sext` for signed source, `zext` for unsigned source.
  - Narrowing: `trunc`.
- **`f32` → `f64`**: `fpext`.
- **User-registered**: any pair declared with `(defcast From To conv-fn)` (see top-level forms). The compiler emits a call to `conv-fn`. Built-in coercion always wins; `defcast` cannot shadow `sext`/`zext`/`fpext`.

Binary operators do *not* coerce — both operands must already match in kind. Mixing float and integer operands, or mixed-sign integer operands (e.g. `i32 + ui32`), or operands of different integer widths (e.g. `i64 + i32-literal`) are compile errors at the operator. Use explicit `(cast ...)` on the binop side.

Explicit `(cast ...)` is also still required for cross-kind conversions: `int ↔ ptr`, `int ↔ float`, `ptr ↔ float`, and `f64 → f32` narrowing.

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
