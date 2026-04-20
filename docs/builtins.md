# Nucleus Built-ins Reference

Built-in forms and functions as implemented in `src/nucleusc.nuc`.

## Compiler Flags

| Flag | Description |
|------|-------------|
| `--emit-nuch` | Output a `.nuch` header instead of LLVM IR. Extracts function signatures, struct definitions, constants, enums, and macros. |
| `-i` / `--interactive` | Start the REPL (interactive Read-Eval-Print Loop). |

## REPL

Start with `nucleusc -i`. The REPL reads one form at a time, JIT-compiles it, and prints the result. Multi-line input is supported (the REPL detects unbalanced parentheses and prompts for continuation lines with `...>`).

Supported top-level forms in the REPL: `defn`, `defvar`, `defconst`, `defenum`, `defstruct`, `include`, `extern`, `import`, `defmacro`, `def-rmacro`, `compile-time`. Any other form (including bare symbols, integers, and function calls) is evaluated as an expression.

Functions defined in the REPL persist across inputs and can call each other. All libc functions (stdio, stdlib, string, ctype, unistd) are pre-loaded — no `(include ...)` needed.

Imported libraries work: `(import mathlib)` makes `square`, `cube`, etc. available. `(import macros)` loads the standard macros (`if`, `when`, `unless`, `for`, `dotimes`, `->`). The `Node` struct and `NODE-*` constants are pre-registered for macro support.

Errors in the REPL are caught and recovered; the REPL continues after an error (including IR parse errors and JIT errors). Redefining an already-defined function is refused with an error.

Limitations:
- Functions need explicit `(return ...)` to return values (same as batch mode).
- Functions cannot be redefined once defined (JIT limitation).
- `set!` only works on local variables, not globals.
- `defvar` initializers must be integer literals (no expressions).
- `(import node)` is not supported — `node.nuc` depends on compiler-internal allocator functions.
- stdout output from JIT'd code may be buffered when the REPL is driven by a pipe; in interactive terminal use, line-buffered output appears immediately.

## .nuch Header Format

A `.nuch` file is an S-expression file containing declarations extracted from a Nucleus source file. It allows importing a library's interface without its source code — function bodies are resolved at link time from the corresponding `.o` file.

```lisp
; .nuch header for lib/mathlib.nuc
(declare square:i32 (x:i32))
(declare cube:i32 (x:i32))
```

Supported forms: `declare` (function signatures), `defstruct`, `defconst`, `defenum`, `defmacro` (full body preserved).

## Top-Level Forms

| Name | Description | C Equivalent |
|------|-------------|--------------|
| `defn` | Define a function | function definition |
| `defconst` | Define a compile-time constant | `#define` / `enum` constant |
| `defenum` | Define an enumeration | `enum` |
| `defvar` | Define a global variable | global variable definition |
| `defstruct` | Define a struct type | `struct` |
| `include` | Include a C standard library module | `#include` |
| `import` | Import a Nucleus library `(import name)`. Resolves `name.nuc` (source) or `name.nuch` (header) from source directory or `lib/`. Source imports inline all definitions; header imports emit `declare` (extern) for functions. Duplicate imports are silently skipped. | — |
| `declare` | Declare an external function signature `(declare name:rettype (params...))`. Used in `.nuch` header files. | function prototype |
| `extern` | Declare an external (foreign) global variable | `extern` declaration |
| `defmacro` | Define a compile-time macro `(defmacro name (params...) body...)`. Supports `&rest` for variadic macros: `(defmacro name (a b &rest rest) ...)` — `rest` receives a cons list of remaining args. | macro |
| `def-rmacro` | Define a reader macro `(def-rmacro "prefix" symbol)`. When `prefix` appears at the start of a token, the reader wraps the next form: `(symbol form)`. Built-in reader macros: `'` (quote), `` ` `` (quasiquote), `~` (unquote), `~@` (unquote-splice), `@` (deref). | — |

## Type Syntax and Desugar

Types are attached to names with `:` syntax: `name:type` (e.g., `x:i32`, `main:int`). A desugar pass runs before compilation, splitting colon-typed symbols in binding positions into canonical list form:

- `foo:int` → `(foo int)` — name and type as separate symbols
- `bar:ptr:fn:Sym` → `(bar ptr fn Sym)` — multi-segment types

Desugar operates on binding positions in `defn`, `defvar`, `defstruct`, `extern`, `declare`, and `let`. Expression bodies are not desugared; typed symbols in value position (e.g., from macro expansion) are handled by the compiler directly.

Both the sugared `:` syntax and the canonical list form are accepted in all binding positions. Macros that manipulate types can work with the canonical list form; macros that don't care about types can use the `:` sugar and it will be desugared before compilation.

Macro output is desugared before compilation, so macro-generated code can use either form.

## Standard Macros (`lib/macros.nuc`)

Defined via `defmacro`. Use `(import macros)` to include them (note: `dotimes` and `->` require the `Node` struct to be defined, as they introspect the AST at macro expansion time).

| Name | Signature | Expands To |
|------|-----------|------------|
| `if` | `(if test then else)` | `(cond test then true else)` |
| `when` | `(when condition body)` | `(cond condition body)` |
| `unless` | `(unless condition body)` | `(cond (not condition) body)` |
| `zero?` | `(zero? x)` | `(= x 0)` |
| `null?` | `(null? x)` | `(= x null)` |
| `for` | `(for (var:type init) test step body)` | `(let (var:type init) (while test body step))` |
| `dotimes` | `(dotimes (var:type n) body)` | `(let (var:type 0) (while (< var n) body (inc! var)))` |
| `->` | `(-> x form ...)` | Threads `x` through each form. If a form contains `_`, the value replaces `_`; otherwise inserts as first arg (thread-first). Bare symbols wrap as `(sym value)`. `_` is only special inside `->`. |

## Special Forms

| Name | Description | C Equivalent |
|------|-------------|--------------|
| `do` | Sequence multiple expressions | `{ ... }` block |
| `let` | Bind local variables | local variable declaration |
| `cond` | Multi-way conditional | `if` / `else if` / `else` chain |
| `while` | Loop | `while` |
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
| `sizeof` | Size of a type | `sizeof(T)` |
| `alloca` | Stack-allocate memory | `alloca()` / VLA |
| `char` | Character literal | `'c'` |
| `aref` | Array element access | `arr[i]` |
| `aset!` | Array element assignment | `arr[i] = val` |
| `quote` | Yields its argument as a `Node*` constant (reader sugar: `'x` → `(quote x)`) | — |
| `quasiquote` | Like `quote` but `~expr` splices a runtime value and `~@list` splices a list (reader: `` `x ``, `~x`, `~@x`) | — |
| `compile-time` | Execute body forms at compile time via LLVM JIT; output goes to stderr | — |
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
| `/` | Division (signed) | `a / b` |
| `%` | Remainder (signed) | `a % b` |
| `bit-and` | Bitwise AND | `a & b` |
| `bit-or` | Bitwise OR | `a \| b` |
| `bit-xor` | Bitwise XOR | `a ^ b` |
| `bit-shl` | Shift left | `a << b` |
| `bit-shr` | Arithmetic shift right | `a >> b` |
| `=` | Equal | `a == b` |
| `!=` | Not equal | `a != b` |
| `<` | Less than | `a < b` |
| `<=` | Less or equal | `a <= b` |
| `>` | Greater than | `a > b` |
| `>=` | Greater or equal | `a >= b` |

## Literal Values

| Name | Type | C Equivalent |
|------|------|--------------|
| `null` | ptr | `NULL` |
| `true` | bool (i1) | `1` / `true` |
| `false` | bool (i1) | `0` / `false` |

## Built-in Types

| Name | Description | C Equivalent |
|------|-------------|--------------|
| `int` / `i32` | 32-bit signed integer | `int32_t` |
| `i1` / `bool` | 1-bit boolean | `bool` |
| `i8` | 8-bit signed integer | `int8_t` / `char` |
| `i16` | 16-bit signed integer | `int16_t` |
| `i64` | 64-bit signed integer | `int64_t` |
| `ptr` | Opaque pointer | `void*` |
| `void` | No value | `void` |

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
