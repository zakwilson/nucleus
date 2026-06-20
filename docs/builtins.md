# Nucleus Built-ins Reference

> **This file has been split into focused reference documents.**
> See [docs/index.md](index.md) for the new entry point and table of contents.

The sections below are preserved for compatibility with existing links in design documents.
For new reading, prefer the split files listed in the index.

---

Built-in forms and functions as implemented in `src/nucleusc.nuc`.

## Compiler Flags

By default `nucleusc <file.nuc>` produces a linked native executable (`a.out` unless `-o` is given). The compiler embeds LLVM: it parses its own generated IR, emits an object file via `LLVMTargetMachineEmitToFile`, and shells out to `clang` for the final link step.

| Flag | Description |
|------|-------------|
| `-o <path>` | Output path. For binary mode the default is `a.out`; with `-c` the default is `out.o`; with `--emit-llvm` output still goes to stdout. |
| `-c` | Emit a `.o` object file instead of linking a binary. |
| `--emit-llvm` / `-S` | Output textual LLVM IR to stdout (the legacy default). Required when the consumer wants `.ll` text — bootstrap, library `.ll` rules, and the `make bootstrap` fixed-point check all pass this flag. |
| `-l<lib>` / `-L<dir>` | Forwarded to `clang` at the link step. |
| `-O0` / `-O1` / `-O2` / `-O3` (or bare `-O` = `-O2`) | Optimization level. Default is `-O0`. At `-O1` and above the LLVM **middle-end pass pipeline** (`default<O`N`>` — mem2reg, instcombine, LICM, GVN, LoopVectorize, SLPVectorize, …) runs on the module before codegen, in addition to setting the backend `CodeGenOptLevel`. At `-O0` neither runs (straight to `LLVMTargetMachineEmitToFile`). Only affects the object/binary path; `--emit-llvm` always emits unoptimized textual IR. Higher levels make the build noticeably slower. |
| `-Ofast` | `-O3` plus `-ffast-math`. |
| `-ffast-math` | Emit `fast` flags on floating-point arithmetic (`fadd`/`fsub`/`fmul`/`fdiv`/`frem`), permitting reassociation, contraction, and no-signed-zero/no-NaN assumptions. This is what lets the optimizer vectorize FP **reductions** (e.g. `pi += …`); without it an FP reduction stays scalar even at `-O3` because reordering would change results. Comparisons are left unflagged. Changes numerical results — opt-in only. |
| `-march=native` | Target the host CPU and its full feature set (via `LLVMGetHostCPUName` / `LLVMGetHostCPUFeatures`) instead of the generic baseline, so vectorized loops use the widest available registers (e.g. 256-bit AVX rather than 128-bit SSE2). Host-only — do not combine with `--target=`. Produces non-portable objects. |
| `--emit-nuch` | Output a `.nuch` header instead of compiling. Extracts function signatures, struct definitions, constants, enums, and macros. |
| `--emit-cheader` | Output a C header (`.h`) instead of compiling. Emits `#pragma once`, `#include <stdint.h>`, typedefs for structs, extern function declarations, `extern` declarations for `defvar` and `extern` globals, `#define` constants, and enums. |
| `-i` / `--interactive` | Start the REPL (interactive Read-Eval-Print Loop). |
| `-I<path>` / `-I <path>` | Add a directory to the import search path. Searched after the source file's directory and `lib/`. |
| `--repl-format=text\|json` | Format for REPL error output. Default `text` (legacy `  error: <msg>` lines). With `json`, each error is emitted as a single-line JSON object: `{"file":..,"line":..,"message":..}`. Suitable for agent-driven REPL sessions. |
| `--target=<triple>` | Cross-compile: set the output module's target triple and datalayout (sourced from LLVM) instead of the host's. In-process JIT modules (compile-time bodies, `defmacro`, REPL) always stay on the host. Registered backends: X86 (`x86_64`/`i386`), AArch64 (`aarch64`), ARM (`arm`); Linux, Darwin, and Windows (msvc/gnu) triples all resolve. Pointer size, `size_t`, and struct layout follow the selected target. |

## REPL

Start with `nucleusc -i`. The REPL reads one form at a time, JIT-compiles it, and prints the result. Multi-line input is supported (the REPL detects unbalanced parentheses and prompts for continuation lines with `...>`).

Supported top-level forms in the REPL: `defn`, `defvar`, `defconst`, `defenum`, `defstruct`, `include`, `extern`, `import`, `defmacro`, `def-rmacro`, `compile-time`, `macroexpand`, `macroexpand-1`, `macroexpand-all`. Any other form (including bare symbols, integers, and function calls) is evaluated as an expression.

Result printing is type-aware: integer kinds print as decimal, string literals print as `"..."` with escapes, quoted forms (`'foo`, `(quote ...)`) print using the AST printer, and other pointer values print as `#<ptr 0x...>`. The reader rejects `#<...>` syntax with a clear error so a printed unreadable value can't silently round-trip as input.

`macroexpand` / `macroexpand-1` print the expansion of a quoted form. `(macroexpand '(when c b))` expands to fixpoint; `(macroexpand-1 '(when c b))` expands one step. An optional integer second arg overrides the depth: `(macroexpand 'form 2)` expands at most twice; `(macroexpand 'form -1)` expands to fixpoint. Subforms are not recursed into (matches Common Lisp `macroexpand`). If the form is not a macro call (head is missing or not a registered macro), the REPL prints `not a macro call: <form>` rather than echoing the input unchanged. `macroexpand-all` expands the head to fixpoint and then recursively expands every subform; quoted/quasiquoted forms are left untouched.

Functions defined in the REPL persist across inputs and can call each other. All libc functions (stdio, stdlib, string, ctype, unistd) are pre-loaded — no `(include ...)` needed.

Imported libraries work: `(import mathlib)` makes `square`, `cube`, etc. available. The standard macros (`if`, `when`, `unless`, `for`, `dotimes`, `->`) are auto-imported at REPL startup, so they're usable without `(import macros)`. The `Node` struct and `NODE-*` constants are pre-registered for macro support.

Errors in the REPL are caught and recovered; the REPL continues after an error (including source syntax errors, IR parse errors, and JIT errors). Source syntax errors recover as an ordinary value path: the reader returns a `!T` (Stage 10 E4) rather than aborting, so an unbalanced `)` or an unterminated form reports its diagnostic and the session keeps going. With `--repl-format=json`, each REPL-level error (missing form arg, JIT lookup failure, recovered error) is emitted as a single-line JSON object on stderr.

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
- `(import node)` brings in the AST utilities (`make-cell`, `node-at`, `node-len`, `node-is-list`); they allocate via `arena-alloc` and the arena initializes lazily on first call.
- stdout from JIT'd code is line-buffered (`setvbuf(stdout, NULL, _IOLBF, 0)` is called on REPL startup) so printf output appears immediately in both terminal and pipe-driven sessions.

## .nuch Header Format

A `.nuch` file is an S-expression file containing declarations extracted from a Nucleus source file. It allows importing a library's interface without its source code — function bodies are resolved at link time from the corresponding `.o` file.

```lisp
; .nuch header for lib/mathlib.nuc
(declare square:i32 (x:i32))
(declare cube:i32 (x:i32))
```

Supported forms: `declare` (function signatures), `defstruct`, `defconst`, `defenum`, `defmacro` (full body preserved), `defmethod` (one overloaded method, carrying its mangled symbol explicitly), `defprotocol` / `extend` (protocol definitions and conformance facts, exported verbatim), `defcast` (full form preserved — the conv-fn must already be `declare`d earlier in the same header), and a producing module's `defvar` globals (re-emitted as `extern` so importers see the symbol without its initializer). A solitary function exports as `declare`; an overloaded one exports a `defmethod` per method so each keeps its distinct symbol:

```lisp
(defmethod "@area.pCircle" (area i32) ((c (ptr Circle))))
(defmethod "@area.pRect"   (area i32) ((s (ptr Rect))))
```

Importing a `.nuch` with `defmethod` forms registers the methods for dispatch in the importing unit and emits an LLVM `declare` under each mangled symbol (resolved at link time). Imported `defprotocol` forms re-register the protocol; imported `extend` forms record the conformance fact without re-checking it (the exporting unit already verified it). Imported `defcast` forms re-register the cast rule; imported `extern` forms emit an `external global`. See [Polymorphism](#polymorphism-overloaded-defn-multimethods) and [Protocols](#protocols-defprotocol-and-extend).


## Top-Level Forms

| Name | Description | C Equivalent |
|------|-------------|--------------|
| `defn` | Define a function. Supports `&rest` for variadic functions: `(defn name (a:t &rest xs:elem) ...)`. The rest parameter receives a `Node*` cons-list head built at the call site (so each call site emits `@make-cell` calls and the program must define a compatible `make-cell`). The element type annotation is documentation only — non-`ptr` args are `inttoptr`'d into `Node.car`. `&rest` functions are not directly C-callable; calling through a function pointer requires manually constructing the rest list. `&rest` must be the second-to-last param. Supports `&optional` for trailing parameters with defaults: `(defn name (a:t &optional (b:t default) ...) ...)`. Each `&optional` param must be a 2-element list `(name:type default-expr)`. Defaults are evaluated at the call site in the caller's scope (Common Lisp semantics), so non-constant defaults like `(next-counter)` produce a fresh value per call. Implicit casts apply to defaults. The compiled function has fixed maximum arity at the LLVM/C ABI level — calling through a function pointer or from C requires supplying every argument including the optional ones. `&optional` cannot be combined with `&rest`. A struct-by-value parameter or return is lowered to the platform C ABI (see [Passing and returning structs by value](#passing-and-returning-structs-by-value)). **Docstring**: if the first body form is a string literal AND there is at least one more form after it, that string is captured as the function's docstring (visible via `(doc fn)` and `(apropos)`); a function whose body is a single string literal is treated as returning the string, not as having a docstring. The same convention applies to `defmacro`. **Overloadable:** defining `defn` again with the same name but different parameter types adds a method — see [Polymorphism](#polymorphism-overloaded-defn-multimethods). | function definition |
| `defconst` | Define a compile-time constant | `#define` / `enum` constant |
| `defenum` | Define an enumeration | `enum` |
| `defvar` | Define a global variable `(defvar name:type [init])`. The optional init must be a literal the language can express in constant position: an integer literal (any int width, signed or unsigned), float literal (`f32` / `f64`), string literal (storage type must be `ptr`), `null` (ptr only), `true` / `false` (`i1`/`bool` only), `(char "x")` (any int type), or a name bound by `defconst` / `defenum` (the constant value is folded in). Omitted inits default to zero / `null` / `false`; a global of **aggregate** type (struct or union) with no init is zero-filled (`zeroinitializer`), so e.g. `(defvar g:MyStruct)` is valid. `set!` works on the result. The symbol is exported with default linkage and is visible to C consumers (`extern T name;`) and other Nucleus modules (`(extern name:type)`). Storage class specifiers (`static`, `register`, `thread_local`) are deferred — see `design/stage888-deferred.md`. | global variable definition |
| `defstruct` | Define a struct type, or a parametric struct template when the name is a list: `(defstruct (Name T ...) ...)`. See [Parametric struct templates](#parametric-struct-templates-defstruct-name-t-). | `struct` |
| `defunion` | Define a tagged sum `(defunion Name (arm field:type ...) ... bare-arm)` or a template `(defunion (Name T ...) ...)`. See [Unions and tagged sums](#unions-and-tagged-sums). | tagged `struct {int tag; union {...} payload;}` |
| `defprotocol` | Define a protocol: a named set of required method signatures (types may mention `Self` and extra element parameters). Compile-time only; emits no code. See [Protocols](#protocols-defprotocol-and-extend) and [Parametric protocols](#parametric-protocols). | — (concept: interface/trait) |
| `extend` | Assert conformance `(extend Type Protocol)` or parametric conformance `(extend (Name T) (Protocol T))`: checks that each required signature resolves, then records the fact. Code-free. See [Protocols](#protocols-defprotocol-and-extend) and [Parametric protocols](#parametric-protocols). | — |
| `include` | Include a C standard library module. `(include stdio)` preprocesses `stdio.h` with `clang -E` and imports all extern function declarations. Any C header can be used: `(include math)` includes `math.h`. | `#include` |
| `import` | Import a Nucleus library or C header. `(import name)` resolves `name.nuc` (source) or `name.nuch` (header) from source directory, `lib/`, `-I` paths, `$NUCLEUS_LIB`, or `/usr/local/share/nucleus/lib` (the install-time default used by `make install`). `(import "stdio.h")` preprocesses a C header with `clang -E` and imports extern function declarations. Source imports inline all definitions; header imports emit `declare` (extern) for functions. Duplicate imports are silently skipped. | — |
| `declare` | Declare an external function signature `(declare name:rettype (params...))`. Used in `.nuch` header files and at the top level. | function prototype |
| `extern` | Declare a foreign global variable `(extern name:type)`. The compiler emits `@name = external global T`, leaving storage and initialization to the linker. Works for both C-defined and Nucleus-defined producers; the matching `defvar` may live in another `.o` file. | `extern` declaration |
| `defmacro` | Define a compile-time macro `(defmacro name (params...) body...)`. Supports `&rest` for variadic macros: `(defmacro name (a b &rest rest) ...)` — `rest` receives a cons list of remaining args. Parameters (and the `&rest` list) are typed `ptr:Node` inside the body, so `(. p car)`, `(. p cdr)`, `(. p kind)`, and `(. p s)` work directly with no `(cast ptr:Node ...)`. The macro can splice a parameter into a quasiquote regardless of the value type the user-supplied expression evaluates to at the call site — see [Macros and pass-through arguments](#macros-and-pass-through-arguments) below. | macro |
| `defcast` | Register an implicit conversion `(defcast From To conv-fn)`. `conv-fn` must be a unary function with signature `To (From)` already in scope; the compiler emits a call to it whenever an arg of `From` is supplied where `To` is expected. Pairs already covered by built-in coercion (identity, int↔int, `f32`→`f64`) are rejected at registration. Rules are unidirectional and non-transitive — declare each direction explicitly, and chain through an intermediate type by writing the chain yourself. Exported in `.nuch` headers. | implicit conversion |
| `def-rmacro` | Define a reader macro `(def-rmacro "prefix" symbol)`. When `prefix` appears at the start of a token, the reader wraps the next form: `(symbol form)`. Built-in reader macros: `'` (quote), `` ` `` (quasiquote), `~` (unquote), `~@` (unquote-splice), `@` (deref). | — |
| `exclude-prelude` | Suppress the implicit `(import prelude)` for this source file. Must be the first top-level form; takes no arguments. Use when a file should compile against the bare language without the standard macros, `Node` struct, or `(include string)` declarations. | — |

### One symbol, one kind

A symbol may name only **one** kind of thing: a special form, a built-in type (`i32`, `ptr`, `double`, …), a struct type, a protocol, a macro, a function, or a value (`defvar`/`defconst`/`defenum` member/`extern`). Defining a name that already names a *different* kind is an error, e.g. `(defn double …)` clashes with the `double` type alias, and `(defstruct i32 …)` clashes with the built-in type. Same-kind reuse is still allowed: overloaded `defn` (multimethods) and REPL/`defstruct` redefinition. This keeps name resolution unambiguous across the language's namespaces.

## Type Syntax and Desugar

Types are attached to names with `:` syntax: `name:type` (e.g., `x:i32`, `main:int`). A desugar pass runs before compilation, splitting colon-typed symbols in binding positions into canonical list form:

- `foo:int` → `(foo int)` — name and type as separate symbols
- `node:ptr:Node` → `(node (ptr Node))` — pointer-to-Node
- `pp:ptr:ptr:Node` → `(pp (ptr ptr Node))` — pointer-to-pointer-to-Node

Pointers to a typed element use the `ptr` constructor: `(ptr T)` is a **non-null** pointer to `T`, and `(ptr ptr T)` chains. Bare `ptr` (with no element) is the opaque `void*` pointer — it carries no element contract, so non-null obligations do not apply to it.

### Pointer kinds: `(ptr T)`, `(raw T)`, and `?T` (Stage 10, flipped)

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

**Uniform `?` (Maybe)** (Stage 10 Phase F): `?T` ≡ `(Maybe T)` with no
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

Use `(.& obj field)` to obtain a pointer to a field without loading it. Result is typed `(ptr field-type)`, so it composes with `.set!`, `deref`, and further `.&` calls — e.g. `(.set! (.& o point) x 10)` writes through a value-typed nested struct field.

### Passing and returning structs by value

A struct used directly (not behind `ptr`) as a `defn`/`declare` parameter or return type is passed/returned per the **platform C ABI**, so it interoperates correctly with C functions compiled by the system `cc`. On x86_64 System V this means small structs are coerced into registers (e.g. `{i32,i32}` → one `i64`; a struct with a `float` field whose eightbyte also holds an integer → `i64`), and structs larger than 16 bytes are passed `byval` / returned via a hidden `sret` pointer. Other targets' ABIs are not yet implemented (see `design/stage8/platform.md`). A struct value is produced by dereferencing a pointer (`@p`) and consumed by storing the call result (`(ptr-set! q (make ...))`); field *access* still requires a pointer (`(. p f)` needs `p : (ptr S)`), so to read fields of a by-value struct parameter, first store it: `(let (q:ptr:S (alloca S)) (ptr-set! q p) (. q f))`. A function may take or return a struct defined anywhere in the same compilation unit or an import — struct definitions are registered before function signatures are resolved.

### C header struct ingestion

C headers consumed via `(include foo)` or `(import "foo.h")` now register their `struct Foo { ... };` and `typedef struct { ... } Bar;` definitions as Nucleus structs with the same name. Anonymous inline struct fields are registered as memoized anonymous structs (same `__anon_struct_h<hex>` machinery). Pass-by-value parameters typed as a C struct work through this path. `union { ... }` fields, named unions, and `typedef union` are registered as untagged union types (stage 10 — see [Unions and tagged sums](#unions-and-tagged-sums)); headers like SDL's or pthread's no longer degrade over them. Field types that the parser cannot represent yet (arrays, bitfields, multi-declarator lines like `int a, b;`) cause the whole struct to be skipped — registered as opaque `ptr` at use sites — rather than registering a layout-incompatible partial struct.

In inline type positions (the type argument of `cast`, `sizeof`, `alloca`), either the canonical list form or the colon sugar works: `(cast (ptr Node) x)` and `(cast ptr:Node x)` are equivalent.

Desugar operates on binding positions in `defn`, `defvar`, `defstruct`, `extern`, `declare`, and `let`. Expression bodies are not desugared; typed symbols in value position (e.g., from macro expansion) are handled by the compiler directly.

Both the sugared `:` syntax and the canonical list form are accepted in all binding positions. Macros that manipulate types can work with the canonical list form; macros that don't care about types can use the `:` sugar and it will be desugared before compilation.

Macro output is desugared before compilation, so macro-generated code can use either form.

## Unions and tagged sums

Stage 10 (design/stage10/unions.md) adds two layers: raw **untagged unions**
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

## Parametric protocols

A **parametric protocol** carries extra type parameters beyond `Self`. These
extra parameters are bound explicitly at the `extend` site, enabling element-
typed collection protocols.

```lisp
(defprotocol (Seq E)
  (get:E ((self (ref Self)) i:usize))
  (len:usize ((self (ref Self)))))
```

The element parameter `E` is a free symbol in the protocol's required-method
signatures. At the `extend` site, bind it to the conforming type's element:

```lisp
(extend (Vector T) (Seq T))   ; binds E := T for each stamped Vector instance
```

Conformance is checked **at stamp time**: when `Vector.i32` is stamped, the
protocol's required methods (with `Self → Vector.i32` and `E → i32`) must
resolve to concrete implementations, else a compile-time error names the missing
method. This produces earlier, clearer diagnostics than lazy (use-time)
checking.

**Associated types** are supported. A parametric protocol's parameters are
functionally determined by the conforming type (one conformance per
`(type, protocol)` pair), so a `&where` bound may name a parametric protocol via a
protocol application — `&where ((Seq E) Self)` — and recover the element type from
the conforming variable's conformance instead of re-spelling it at every use. Each
argument is recovered when it is an unbound type variable and constrained
(checked) when concrete. See the *Associated-type bounds* section of
[generics.md](generics.md) and `design/stage11/assoc-types.md`.

## Error handling: `Err`, `deferror`, `!T`, handlers (Stage 10)

Recoverable errors are ordinary return values (design/stage10/errors.md). A
fallible function returns `(Result T Err)`, written with the sugar `!T`. The
caller must `match`, `try`, or `unwrap` before using the value. The
unrecoverable tier is unchanged: `die`/`die-at` still abort.

**`Err`** is a distinct builtin scalar type represented as `i32` (C-legible),
distinguished from a plain `i32` so the error machinery can key on it. Id `0`
is reserved ("no error"); real ids are dense from `1`.

**`deferror`** defines an error value and registers its name + message:

```lisp
(deferror config-missing "config file not found")
```

`config-missing` becomes a compile-time `Err` constant. The name is the stable
contract; the id is a per-build representation (assigned in definition order,
capped at 4095). Names are program-global. `.nuch` headers export `deferror`
verbatim; importers re-register and get their own dense ids.

**The `!` type sugar** (recognized only in type positions, so no clash with
`!=`):

| Spelling | Expansion | Reading |
|---|---|---|
| `!T`  | `(Result T Err)`           | fallible value — `T` as written (`!i64` is `(Result i64 Err)`) |
| `!?T` | `(Result (Maybe T) Err)`   | error, or none, or value |
| `?!T` | `(Maybe (Result T Err))`   | a fallible result that may be absent (value-`Maybe` over a Result) |

After the Phase F flip `?` is uniform `(Maybe T)` (no `(ref …)` injection), so
`?` and `!` compose without asymmetry — both take their payload as written
(`!?i64` is `(Result (Maybe i64) Err)`; `?ptr:T` is the niche-encoded
nullable pointer). The
`(Result T E)` template now lives in the prelude, always available. Because the
toplevel signature prescan now resolves imported (prelude) types, `name:!Config`
parses in ordinary signatures — which is the point of the sugar, since
`name:(Result Config Err)` does not parse (parenthesized type in a colon
position). `!` over a parenthesized payload has no sugar; write
`(Result (ref FILE) Err)` longhand.

**Construction.** In `return` position (and the implicit-return tail) of a
function declared `!T`, bare `(ok v)` / `(err E)` resolve against the return
type (the union target-typing rule). **Reading rule:** `(err E)` means "give up
unless a bound handler repairs"; `(err! E)` means "give up unconditionally" —
it bypasses the handler chain and returns the error value. Use `err!` when you
want an unconditional error return regardless of any bound handlers. Elsewhere
(non-return positions, custom `(Result T MyErrStruct)` types), use
`(make (Result T Err) ok v)`; stored Results are plain data with no handler
machinery.

**Elimination.**

| Form | Meaning |
|---|---|
| `match` | the eliminator — `((ok v) …)` / `((err e) …)` arms |
| `(try r)` | propagation macro (`lib/error.nuc`, needs `(import error)`): yields the `ok` value, or re-returns the error via `err!` from the enclosing `!T` function |
| `(unwrap r)` | the `ok` payload, or — on `err` — print `err-name`/`err-message` and abort (needs `printf` in scope for the message) |
| `(unwrap-or r d)` | the `ok` payload, or `d` (evaluated only on the `err` arm) |
| `(err-name e)` / `(err-message e)` | the descriptor strings for an `Err` value |

```lisp
(include stdio)
(import error)
(deferror parse-failed "could not parse value")

(defn checked:!i64 (n:i64)
  (when (< n (cast i64 0)) (return (err parse-failed)))
  (return (ok n)))

(defn doubled:!i64 (n:i64)
  (let (v:i64 (try (checked n)))          ; propagate on err
    (return (ok (* v (cast i64 2))))))

(match (checked x)
  ((ok v)  ...)
  ((err e) (printf "%s: %s\n" (err-name e) (err-message e))))
```

**C layout of `!T`.** The representation depends on the payload:

- `!SomeStruct`, `!i64`, `!f32`, etc. (non-pointer payload) — the tagged
  struct `{i32 tag; union payload}` plus the `Err` id constants as an enum.
  Fully legible and constructible from C. `sizeof(!T) == sizeof(Result.T.Err)`.
- `!ptr:T` (`(Result (ref T) Err)` over a typed pointer, rule 3 niche layout)
  — a bare `T*` with the ERR_PTR convention: `ok` values are the pointer
  directly; `err` values occupy the top-page range
  `[ptrtoint(-4095), ptrtoint(-1)]` (ids 1–4095). C code that understands the
  ERR_PTR convention can consume it directly. `sizeof(!ptr:T) == sizeof(T*)`.
  Use `&repr tagged` on the `defunion` to opt out and force the struct layout
  when a C consumer needs it unconditionally (see [Niche layout and `&repr`](#niche-layout-and-repr-stage-10-c4)).

Nothing propagates across a function boundary by a mechanism C doesn't
understand.

### Handler-aware `err` and `with-handler` (E3)

When `(import error)` is in scope, returning `(err E)` from a `!T` function
consults the dynamically-bound handler chain before returning the error value. A
matching handler can **repair** the fault: the function returns `(ok v)` instead
of the error. `(err! E)` always bypasses the chain.

**Where the check fires.** Only at `(return (err E))` and the implicit-return
tail of a function whose declared return type is `!T` (i.e. `(Result T Err)`
with the builtin `Err` as the error arm). A stored `Result`, an `(err …)` in
any non-return position, or a custom `(Result T MyErrStruct)` type are plain
values — no handler machinery applies.

**`(err E detail)`.** An optional second argument of type `ptr` passes a
transient context pointer to the handler. It is borrowed for the call and never
stored in the error value:

```lisp
(return (err config-missing path))   ; handler receives path as detail
```

**`with-handler`.** Binds a handler in the current dynamic extent (from
`lib/error.nuc`; requires `(import error)`):

```lisp
(with-handler (error-value repair-type handler-fn ctx) body…)
```

- `error-value` — a `deferror` constant; the handler fires only on this error.
- `repair-type` — the value type `T` of the `!T` function being repaired.
  Declared explicitly because the handler may be active across many sites
  returning different `T`s, and the compiler needs the type at the `err` site
  to make the match sound and to wrap `(ok v)` correctly.
- `handler-fn` — a function `(fn (Maybe repair-type) (ptr ptr))` taking `(ctx
  detail)` and returning `(Maybe repair-type)`. Return `(some v)` to repair;
  return `none` to decline (the error propagates).
- `ctx` — an arbitrary `ptr` forwarded to every call of `handler-fn`.

**Handler keying.** A handler matches only when **both** the error id and the
site's repair type `T` agree. A handler bound for `(config-missing, Config)`
fires at `!Config` sites and is invisible to a `!FILE` site raising the same
error. The type key is the type's mangled-name string (pointer-compare with
`strcmp` fallback, separate-compilation-safe).

**Semantics.**

- *Origin-only, once.* Handlers run at the `(err E)` site, never at `(try …)`
  propagation. `try` re-returns via `err!`, so propagation never re-checks
  handlers.
- *CL unbind rule.* While a handler executes, the chain is rewound past that
  handler. An error raised inside a handler finds only outer handlers — no
  self-match, no infinite recursion.
- *Zero happy-path cost.* The handler check sits only on the `(err E)` return
  path. Programs that bind no handlers pay one global pointer load and null
  compare per `err` return, on the error path only. `err!` costs nothing extra.

**Gating.** The handler machinery lives in `lib/error.nuc`. Without
`(import error)`, `(err E)` behaves like `(err! E)` — the check is never
emitted. `try`, `with-handler`, `Handler`, and `err-find-handler` all require
the import.

**v1 limitation.** Handler repair types must be value types. A repair type that
is a `(ref X)` (i.e. a `(Maybe (ref X))`-shaped return from the handler fn) is
not supported in v1.

**Example** (see also `examples/handlers.nuc`):

```lisp
(include stdio)
(import error)

(deferror config-missing "config file not found")

; A fallible function. (err config-missing) consults bound handlers first.
; err! would bypass them unconditionally.
(defn load-num:!i64 (n:i64)
  (when (= n (cast i64 0))
    (return (err config-missing)))    ; handler may repair → (ok v)
  (return (ok (* n (cast i64 10)))))

; A repairing handler: (some v) repairs, none declines.
(defn (repair-from-ctx (Maybe i64)) (ctx:ptr detail:ptr)
  (return (some (deref (cast ptr:i64 ctx)))))

(defn main:i32 ()
  ; No handler bound: (err config-missing) returns the error value.
  (match (load-num (cast i64 0))
    ((ok v)  (printf "ok %lld\n" v))
    ((err e) (printf "err: %s\n" (err-name e))))

  ; Repairing handler bound for (config-missing, i64): err → (ok 777).
  (let (fixed:i64 (cast i64 777))
    (with-handler (config-missing i64 repair-from-ctx (cast ptr (addr-of fixed)))
      (match (load-num (cast i64 0))
        ((ok v)  (printf "repaired: %lld\n" v))   ; prints: repaired: 777
        ((err e) (printf "err: %s\n" (err-name e))))))
  0)
```

### Standalone `signal`

```lisp
(signal E RepairType)            ; → (Maybe RepairType)
(signal E RepairType detail)     ; detail:ptr, borrowed for the handler call
```

`signal` asks bound handlers for *policy* without returning. It walks the same
handler chain `with-handler` binds, looking for a handler keyed on `(E,
RepairType)` — exactly `err-find-handler`'s key — and, on a match, calls it
under the CL unbind rule and yields its `(Maybe RepairType)`; `none` (no handler
matched, or the handler declined) is the default. `RepairType` is a **type**
operand (parsed, not evaluated), like `with-handler`'s `type-token`.

Unlike `(err E)`, `signal` is **not tied to return position** and does **not**
wrap the result in `(ok v)` — it hands the `(Maybe RepairType)` straight back, so
the caller decides what to do (continue in place, fall back, propagate). This is
errors.md §4's "low-level code asks high-level code for policy" shape — e.g. an
allocator's grow path signalling for a replacement block, falling back to its own
behavior if policy declines:

```lisp
(import error)
(deferror out-of-memory "allocation grow needs a policy decision")

(defn grow:i64 (need:i64)
  (match (signal out-of-memory i64 (cast ptr (addr-of need)))
    ((some sz) sz)               ; a handler supplied a size: continue
    (none      (cast i64 0))))   ; declined / no handler: the fallback

(defn (grant-double (Maybe i64)) (ctx:ptr detail:ptr)
  (return (some (* (deref (cast ptr:i64 detail)) (cast i64 2)))))

(with-handler (out-of-memory i64 grant-double null)
  (grow (cast i64 8)))           ; → 16
```

`signal` requires `(import error)` (it references the handler chain). Its result
is a **value** `(Maybe T)`, eliminated with `match` (not `if-some`, which is
pointer-only). The **v1 repair-type-is-a-value-type limitation** applies: a
`(ref X)` niche-pointer repair is not a struct, so the struct-return call path
cannot carry it (`examples/signal.nuc`).

## Standard Macros (`lib/macros.nuc`)

Defined via `defmacro`. The compiler auto-imports `lib/prelude.nuc` (which defines the `Node` struct, the `NODE-*` enum, and `(import macros)`) into every program, so all of these are available without an explicit `(import macros)`. To opt out — e.g. when a source file should compile against the bare language with no macros, no `Node` type, and no `string` libc declarations — make `(exclude-prelude)` the first form in the file.

| Name | Signature | Expands To |
|------|-----------|------------|
| `if` | `(if test then else)` | `(cond test then true else)` |
| `case` | `(case form v1 r1 v2 r2 ... default)` | `(cond (= form v1) r1 (= form v2) r2 ... true default)` |
| `when` | `(when condition body...)` | `(cond condition (do body...))` |
| `unless` | `(unless condition body...)` | `(cond (not condition) (do body...))` |
| `zero?` | `(zero? x)` | `(= x 0)` |
| `null?` | `(null? x)` | `(= x null)` |
| `for` | `(for (var:type init) test step body)` | `(let (var:type init) (while test body step))` |
| `dotimes` | `(dotimes (var:type n) body)` | `(let (var:type 0) (while (< var n) body (inc! var)))` |
| `doseq` | `(doseq (var iter-ref) body...)` | Loop over an iterator: calls `(next iter-ref)` each step, binds the element to `var`, and runs `body...`; stops on `none`. `iter-ref` must be a `(ref IterType)` where `IterType` conforms to `(Iterator E)`. See [Iterators](#iterators-libiteratornuc-stage-11). |
| `into` | `(into coll-sym iter-ref)` | Drain an iterator into a collection: calls `(next iter-ref)` each step and `(conj coll-sym elem)` for each element; stops on `none`. Requires `coll-sym` to be a `(ref CollType)` with a `conj` method. See [Iterators](#iterators-libiteratornuc-stage-11). |
| `->` | `(-> x form ...)` | Threads `x` through each form. If a form contains `_`, the value replaces `_`; otherwise inserts as first arg (thread-first). Bare symbols wrap as `(sym value)`. `_` is only special inside `->`. |

`case` is multi-way equality dispatch: it compares `form` against each value `vi` with `=` and yields the first matching result `ri`. The final unpaired argument is the **required** default. Because `=` is overloadable, `case` works over any type with an equality (integers, enum constants, symbols, C strings). `form` is re-evaluated per comparison, so it should be side-effect free.

`(import arena)` additionally provides `(new T)` — allocate one zeroed `T` from the arena, typed `(ref T)` (non-null: `arena-alloc` aborts on exhaustion rather than returning null). It expands to `(cast (ref T) (arena-alloc (sizeof T)))`, collapsing the cast + `sizeof` boilerplate for the common "allocate a single struct" case. It is **not** in the prelude (it depends on `arena-alloc`), so it requires an explicit `(import arena)`.

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
| `with` | Like `let`, but **owns** any binding whose init is a libc allocator (`malloc`/`calloc`/`realloc`/`strdup`, possibly through `cast`) or whose declared type conforms to the `Drop` protocol. Owned bindings are released at scope exit (libc → `free`; Drop → statically dispatched `(drop b)`, null-guarded) in reverse binding order, on fall-through and on early `return`. The compiler verifies at compile time that an owned resource does not **escape** the scope — see [Pointer lifecycle](#pointer-lifecycle-with-escape-analysis). Use `(move b)` to transfer ownership out. | `let` + scoped `free` / RAII |
| `cond` | Multi-way conditional; yields the matched branch's value (strict-typed across branches) | `if` / `else if` / `else` chain |
| `case` | Integer-keyed dispatch; lowers to LLVM `switch`. Each clause is `(KEY body...)` where KEY is an integer literal, a list of integer literals, or the symbol `_` (default). With no `_` clause, an unmatched scrutinee hits `unreachable` (UB). Yields the matched branch's value (strict-typed across branches), like `cond`. | `switch` / `default:` |
| `match` | Eliminate a `defunion` value (or a `defenum` integer) by arm, with exhaustiveness checking. See [Unions and tagged sums](#unions-and-tagged-sums). | `switch` on the tag |
| `make` | Construct a `defunion` value by arm: `(make Type arm args...)` — the explicit-instance spelling required for template instances, e.g. `(make (Result i64 i32) ok v)`. | designated initializer |
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
| `.` | Struct field access; equivalent to head position `(s field)` and lowers to the `_get` primitive for a plain struct. | `s.field` |
| `_get` | Low-level struct field read (compiler-internal primitive; bypasses any user `get` override). Prefer head position `(s field)` in ordinary code; use `_get` only where head position would dispatch wrongly (a user `get` method reading its own field, or a struct held in a special-form-named variable). | `s.field` |
| `.set!` | Struct field assignment; yields the stored value | `s.field = val` |
| `get` | Member access / field read: `(get s 'field)` ≡ `(s field)`; for a plain struct this lowers to the `_get` primitive (zero-overhead), overridable per type. See [Callable values](#callable-values-non-function-call-position) | `s.field` |
| `invoke` | General call on a value: `(invoke s 3)` ≡ `(s 3)`; user-defined (`Seq`/`Call`) | `s(3)` / `s[3]` |
| `sizeof` | Size of a type | `sizeof(T)` |
| `alloca` | Stack-allocate memory | `alloca()` / VLA |
| `char` | `(char "x")` — a `Char` value (codepoint) from a single-byte string; sugar for the `\x` char literal. See [Char literals](types.md#char-literals--a). | `(Char)'c'` |
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
| `some` | `(some r)` — wrap a non-null `(ref T)` as `?T` / `(Maybe (ref T))`. Pure relabel, no IR. | — |
| `as-ref` | `(as-ref p)` — launder a raw pointer into `?T` (null stays none). Pure relabel, no IR; narrow before use. | — |
| `unwrap` | `(unwrap m)` — the `(ref T)` inside a `?T`, or trap (`llvm.trap`) if none. The one runtime branch nullability costs, paid only where written. | `assert(p); p` |
| `unwrap-or` | `(unwrap-or m default)` — the `(ref T)` inside, or `default` (evaluated only on the none path; must itself be `(ref ...)`-compatible). | `p ? p : d` |
| `if-some` | `(if-some (x m) then else)` — if `m` is non-null, bind `x:(ref T)` in `then`; else evaluate `else`. Desugars to `cond`, so its value/typing rules match `if`. | `if ((x = m)) … else …` |
| `when-some` | `(when-some (x m) body…)` — one-armed `if-some`. | `if ((x = m)) { … }` |
| `move` | `(move b)` — transfer ownership of a `with`-owned binding out: disarms its scope-exit cleanup, yields the value with its escape taint cleared, and marks `b` consumed (later uses are "use after move"; reassignment revives it). | — |
| `defer` | `(defer expr)` — register `expr` as an ad-hoc cleanup on the enclosing binding scope (nearest `let`/`with`/function body), re-emitted at every exit path in reverse registration order. Lexical, not dynamic: it runs at scope exit whether or not control reached the `defer` site. | `goto cleanup` discipline |

## Pointer lifecycle: `with` escape analysis

A `with` binding whose init is a libc allocator, or whose declared type
conforms to the `Drop` protocol, is an **owning binding**: its resource is
released at scope exit, so any pointer still aliasing it afterwards would
dangle. The compiler tracks aliases (its **taint**) at compile time and rejects
escapes (see `design/stage10/lifecycle.md`):

- Taint follows pointer **identity**: binding a tainted value (`let`/`with`/
  `set!`), `cast`, `ptr+`, `.&`, `addr-of`, and control-flow joins keep it.
  Copying the pointee **value** out (`deref`, field loads) clears it — so
  `(return (deref p))` and `(return (p count))` are fine.
- **Escape sinks** (compile errors on tainted operands): `return` (explicit or
  implicit), and stores into longer-lived memory (`set!` to an outer binding;
  `aset!`/`.set!`/`ptr-set!` into memory not owned by the same or an inner
  `with`). Manually calling `free`/`drop` on an owning binding is a
  double-free error.
- **`(move b)`** is the sanctioned way out: it disarms the cleanup, clears the
  taint, and consumes the binding.
- Passing a tainted value as a **function argument** is allowed (arguments are
  borrows; the callee retaining the pointer is the same residual risk as C),
  and pointers loaded *out of* the resource are not tracked — these are the
  two documented imprecision boundaries of the cheap, intraprocedural tier.

The `Drop` protocol is an ordinary Stage 9 protocol; conforming makes a type
`with`-manageable with zero dispatch overhead:

```
(defprotocol Drop
  (drop:void (self:ptr:Self)))
(defn drop:void (self:ptr:Res) ...)   ; concrete method
(extend Res Drop)                      ; checked, code-free conformance
(with (r:ptr:Res (make-res)) ...)      ; (drop r) fires at scope exit
```

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
  (`(ptr T)`, etc.) in a plain `&where` generic is rejected. For a parametric
  struct receiver, the type variable **is** permitted in nested positions like
  `(ptr T)` and `(ref T)` — those tyvars are inferred from the receiver, not
  supplied via `&where`. See [Parametric struct templates](#parametric-struct-templates-defstruct-name-t-).
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
instantiation; non-type/const parameters in parametric generics; higher-kinded
or partially applied type parameters.

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
literal selector const-folds to a static `getelementptr`+`load`, **identical to the
`_get` primitive and zero-overhead**. So `(c rad)` ≡ `(get c 'rad)` ≡ `(_get c rad)`.
Head position `(c rad)` is the idiomatic spelling; `_get` is the escape hatch (it
reads the field directly, skipping any user `get` override — so a user `get` method
uses `_get` for its own fields to avoid recursing into itself).

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

**Value-keyed `get` (computed selectors).** Dispatch splits on the selector kind.
A literal-symbol selector takes the member-access path above (the selector value
is always an interned symbol `ptr`). A **computed/value selector** — an `i32`, a
`CStr`, or any non-symbol value — instead resolves the `get` generic on the
selector's *actual* type, so a parametric `get` override can index by a real key:

```lisp
(defstruct (Bag K V) key:K val:V has:i32)
(defn (get (Maybe V)) ((self (ref (Bag K V))) key:K) …)   ; value-keyed lookup
(get bag "hello")    ; CStr selector → the (Bag K V) get method, returns (Maybe V)
(get bag 42)         ; i32  selector → the same method
(get bag 'val)       ; symbol selector → field access, returns the raw V field
```

The value-keyed override is found even when it is a parametric (generic) method:
the resolver binds the method's type variables and checks its `&where` constraints
before selecting it. If no `get` method matches the selector's type, the call
falls back to the struct intrinsic (a `ptr`-typed computed selector takes the
homogeneous computed-field branch; any other type is an error).

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

For parametric function-object conformance, use `(UnaryFn Arg Ret)` and
`(FoldFn Acc Elem)` from `lib/iterator.nuc`:

```lisp
(import iterator)
(defstruct Adder delta:i32)
(extend Adder (UnaryFn i32 i32))
(defn (apply i32) ((self (ref Adder)) (x i32))
  (return (+ x (self delta))))
; (apply adder 37) → 42  when delta=5
```

See `examples/callable.nuc` for a full demonstration.

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
no vtable. `get`/`invoke` overloads and `IntIndexable`/`Call` export through the
existing `defmethod`/`defprotocol`/`extend` machinery; there is no new `.nuch` form.

## Literal Values

| Name | Type | C Equivalent |
|------|------|--------------|
| `null` | ptr | `NULL` |
| `true` | bool (i1) | `1` / `true` |
| `false` | bool (i1) | `0` / `false` |
| `"…"` string literal | `CStr` | `"…"` (`char*`) |

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
| `usize` | Unsigned pointer-sized integer (resolves to `i32` on ILP32 targets, `i64` on LP64) | `size_t` |
| `ssize` | Signed pointer-sized integer (resolves to `i32` on ILP32 targets, `i64` on LP64) | `ssize_t` / `ptrdiff_t` |
| `ptr` | Opaque pointer | `void*` |
| `CStr` | C-style (null-terminated) string | `char*` |
| `void` | No value | `void` |

Pointer size and the target are not hardcoded as `i64`/`8` throughout codegen: a target descriptor (`g-target-triple`, `g-target-ptr-bytes`, defaulting to `x86_64-pc-linux-gnu` / 8 bytes) drives the emitted `target triple`, pointer/`CStr` type sizes and alignments, and the width of `sizeof` (a pointer-sized `size_t`). To target a 32-bit platform, set `g-target-ptr-bytes` to 4. (The macro/`compile-time` JIT still targets the host. One remaining 64-bit assumption is the hand-written `__cons`/`__append` IR in `emit-qq-helpers`.)

**`usize` and `ssize`** are the portable index and length types for pointer-sized arithmetic. They resolve to the target's pointer-width integer at compile time: `i32` on ILP32 (4-byte pointer) targets and `i64` on LP64 (8-byte pointer) targets. `usize` is unsigned; `ssize` is signed. They are valid in any type position and are handled correctly by `sizeof`, type mangling, `type-eq`, and arithmetic operators. Use `usize` for lengths, counts, and non-negative offsets; use `ssize` for signed differences or offsets that may be negative. Both participate in the standard numeric promotions and are mangled distinctly (e.g. `usize`, `ssize`) in method symbols and stamped struct names.

`CStr` is the type of a string literal — a C `char*`. It lowers to `ptr` (same ABI) and flows into any `ptr`-typed C function with no cast, but it is a **distinct type for operator dispatch**: `=` / `!=` on two `CStr` do a `strcmp` **content** comparison (so equal text compares equal across distinct buffers), whereas `=` on two raw `ptr` is pointer identity. `CStr` conforms to the `Eq` protocol (`lib/numeric.nuc`), so it works in an `Eq`-bounded generic; it is not `Ord` (no ordering — out of scope here, along with Unicode). Only `=` / `!=` are defined; other operators on `CStr` are an error. A `CStr` and a `ptr` are freely interconvertible with `cast` (no IR) and coerce automatically in value positions (assignment, return, field/array store); a string literal also passes directly to a plain `ptr` parameter. (Multimethod dispatch treats `CStr` as distinct — overload on `CStr` explicitly, or `cast` to `ptr`.) `strcmp` must be declared, which the prelude's `(include string)` provides. Example: `examples/cstr.nuc`.

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

## Allocators (`lib/allocator.nuc`, Stage 11)

The collection library owns and frees memory through an **allocator** rather than
a bare `malloc`, so a collection can be built against libc, an arena, or a future
allocator and still free with the same backend that built it. `(import allocator)`
brings in the protocol, the handle type, the backends, and a default.

### The `Allocator` protocol

The documented contract (Zig-shaped). `align` is part of the contract even where
a backend ignores it. The byte type is `(raw ui8)` (= C `unsigned char *`):

```lisp
(defprotocol Allocator
  ((alloc   (raw ui8)) ((self (ref Self)) size:usize align:usize))
  ((realloc (raw ui8)) ((self (ref Self)) (p (raw ui8)) old:usize new:usize align:usize))
  (free:void           ((self (ref Self)) (p (raw ui8)) size:usize align:usize)))
```

Note the **list-form method names** (`(alloc (raw ui8))`, not `alloc:(raw ui8)`):
a parenthesised type does not tokenise in a colon return/parameter position, so
both the name's return type and `(raw ui8)` parameters use the list binding form.

### Runtime dispatch: `AllocHandle`

A collection stores **one** allocator handle field and dispatches through it
without knowing the concrete backend — the design's "stored field" plumbing. The
protocol system is static-only (no vtables) and `funcall-ptr-*` cannot call a
3+-arg function pointer, so dispatch is a **tagged handle**, not a vtable:

```lisp
(defenum AllocKind ALLOC-LIBC ALLOC-ARENA)
(defstruct AllocHandle kind:i32 data:ptr)
```

| Helper | Signature | Behaviour |
|--------|-----------|-----------|
| `alloc-handle-alloc` | `((h (ref AllocHandle)) size:usize align:usize) -> (raw ui8)` | libc `malloc`, or `arena-alloc`; `kind` selects |
| `alloc-handle-realloc` | `((h (ref AllocHandle)) (p (raw ui8)) old:usize new:usize align:usize) -> (raw ui8)` | libc `realloc`, or arena fresh-alloc + `memcpy` of `min(old,new)` |
| `alloc-handle-free` | `((h (ref AllocHandle)) (p (raw ui8)) size:usize align:usize) -> void` | libc `free`, or no-op for the arena |

### Default and constructors

| Function | Signature | Use |
|----------|-----------|-----|
| `default-allocator` | `() -> (ref AllocHandle)` | the process-global libc handle; backs convenience constructors that omit an allocator |
| `libc-allocator` | `((h (ref AllocHandle))) -> (ref AllocHandle)` | initialise a caller-owned slot as a libc handle |
| `arena-allocator` | `((h (ref AllocHandle))) -> (ref AllocHandle)` | initialise a caller-owned slot as an arena handle (state lives in `lib/arena.nuc`'s globals) |

A collection stores the `AllocHandle` by value; use `(.& coll alloc-field)` to get
a `(ref AllocHandle)` into it for the helpers. Example: `examples/allocator-test.nuc`.

**Why no static `(extend MyAlloc Allocator)` in the library.** A generic method
literally named `free`/`realloc`/`malloc` shadows the libc symbol of that name for
the whole compilation unit (this is why `Drop` uses `drop`), and such a
conformance currently cannot be `import`ed at all — the imported file's transitive
`(include stdlib)` re-declares the libc symbol before the importing generics
finalize. A conformance defined *directly* in the consuming unit does compile.
See `design/stage11/progress.md` (M1) for the details and the deferred compiler fix.

## Iterators (`lib/iterator.nuc`, Stage 11)

`(import iterator)` provides the `Iterator` parametric protocol, two concrete
iterator structs (`IntRangeIter`, `I64ArrayIter`), generic function-object
protocols (`UnaryFn`, `FoldFn`), generic lazy combinators (`MapIter`, `FilterIter`),
and a generic `reduce`. The combinators conform to `Iterator` via `&where` on
`extend` (extend-site associated-type recovery), so they chain freely and can
be passed to any generic function bounded on `Iterator`.

See [docs/iterators.md](iterators.md) for the full reference, signatures, and
a worked `map → filter → reduce` example.
