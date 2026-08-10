# Compiler Reference

## Compiler Flags

By default `nucleusc <file.nuc>` produces a linked native executable (`a.out` unless `-o` is given). The compiler embeds LLVM: it parses its own generated IR, emits an object file via `LLVMTargetMachineEmitToFile`, and shells out to a link driver for the final link step — `clang` by default, `avr-gcc` on an AVR `--target=`, `riscv64-linux-gnu-gcc` when *cross*-compiling to a `riscv64` `--target=`, or whatever `--linker=` names.

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
| `--emit-nuch` | Output a `.nuch` header instead of compiling. Extracts function signatures, struct definitions, constants, enums, and macros. The prelude and the file's own imports are prescanned first (types only — nothing is emitted), so an exported signature may name an imported type: `Node`, `StrView`, `String`, `(Maybe T)`, the `!T` sugar. |
| `--emit-cheader` | Output a C header (`.h`) instead of compiling. Emits `#pragma once`, `#include <stdint.h>` / `<stdbool.h>` / `<stddef.h>`, tagged typedefs for structs and unions (`typedef struct Pt { … } Pt;`, so both `Pt` and `struct Pt` work), extern function declarations, `extern` declarations for public `defvar` globals (see [Reaching a library's globals from C](#reaching-a-librarys-globals-from-c)), `#define` constants, and enums. For a namespaced library, function declarations use the C-legal mangled link name (`geom__area`, not the Nucleus name `geom/area`), so a C consumer links against the same symbol the library emits — and a struct's typedef name is mangled the same way (`} gt__Pt;`, not `} Pt;`), since two namespaces may each define a `Pt` and an unprefixed typedef would collide if both headers were included together. A `user`-namespace library's header is unaffected. An **overloaded** or **operator-named** function is declared under the per-signature symbol it really links as, each method with its own C name (see [Overloaded and operator-named functions in a C header](#overloaded-and-operator-named-functions-in-a-c-header)). A name that is a **word C or C++ reserves** (`union`, `signed`, `class`, `delete`) is renamed with a trailing `_` and re-bound with an `asm` label, so only its C spelling moves (see [Names C reserves](#names-c-reserves)). Header emission resolves the whole unit's signatures, so a source that does not compile produces the compiler's ordinary error rather than a header. See [Namespaced type names](types.md#namespaced-type-names). |
| `-i` / `--interactive` | Start the REPL (interactive Read-Eval-Print Loop). |
| `-I<path>` / `-I <path>` | Add a directory to the import search path. Searched after the source file's directory and `lib/`. |
| `--repl-format=text\|json` | Format for REPL error output. Default `text` (legacy `  error: <msg>` lines). With `json`, each error is emitted as a single-line JSON object: `{"file":..,"line":..,"message":..}`. Suitable for agent-driven REPL sessions. |
| `--target=<triple>` | Cross-compile: set the output module's target triple and datalayout (sourced from LLVM) instead of the host's. In-process JIT modules (compile-time bodies, `defmacro`, REPL) always stay on the host. Registered backends: X86 (`x86_64`/`i386`), AArch64 (`aarch64`), ARM (`arm`), AVR (`avr`), RISCV (`riscv64`); Linux, Darwin, and Windows (msvc/gnu) triples all resolve. Pointer size, `size_t`, and struct layout follow the selected target. The reloc model is chosen per target (static for `avr`, PIC otherwise). A `riscv64` triple additionally defaults CPU/features/ABI to `generic-rv64` / `+m,+a,+f,+d,+c` / `lp64d` (RV64GC, the glibc-compatible baseline) — LLVM's own empty-features default is bare RV64I with a soft-float ABI, silently incompatible with a real riscv64 Linux target, so a correct default (not a user-supplied flag) is load-bearing here. When the resolved ABI is non-empty, `--emit-llvm` output carries a `!llvm.module.flags` block pinning `target-abi` (e.g. `!"lp64d"`); every other target emits no module-flags block at all. On `riscv64`, struct-by-value follows the lp64d **hard-float** calling convention: an aggregate is first flattened (nested structs and arrays expand into their scalar members; a union never flattens), and a flattened list of exactly one FP real, two FP reals, or one FP real plus one integer — in either order — travels in FP registers (`float`, `{double,double}`, `{i32,float}`, `{float,i32}`) as long as the registers it needs are still free at that argument position. Anything else — three or more members, a union, an over-wide member, a **variadic** argument, or exhausted registers (fa0-fa7 / a0-a7, with a hidden `sret` pointer spending one of the latter) — takes the integer convention, coercing a struct ≤ 16 bytes to `i64`/`{i64,i64}`; a struct over 16 bytes passes as a plain pointer / returns via `sret` (no `byval`). A return is classified against a0/a1/fa0/fa1, which are always available, so a return never falls back for want of registers — see [Passing and returning structs by value](structs-unions.md#passing-and-returning-structs-by-value). On `avr`, every struct/union passed or returned by value (any size) uses the aarch64-style plain-pointer `ABI-MEMORY` convention — no `byval`, since the SysV eightbyte register-chunk model that other targets use doesn't fit an 8-bit target with no such registers (see [Passing and returning structs by value](structs-unions.md#passing-and-returning-structs-by-value)) — and `f64`/`double` is a compile-time error (no hardware double), both as an explicit annotation and as a bare float literal's default type; `f32` and `i64` remain fully supported (see [Built-in Types](types.md#built-in-types)). |
| `--mcpu=<cpu>` | The target CPU/device passed to LLVM's `TargetMachine` (e.g. `--target=avr --mcpu=attiny1634`). Only meaningful with `--target=`; the host target always uses the empty (generic) CPU. For AVR, use the device name when LLVM lists it (`attiny1634`) or the family core for a device LLVM doesn't know (`avrxmega3` covers the AVR-Dx parts). Currently the datalayout for a given triple is CPU-independent, so `--mcpu` selects the codegen ISA, not the ABI. For `riscv64`, `--mcpu` overrides only the CPU (default `generic-rv64`); the `+m,+a,+f,+d,+c` features and `lp64d` ABI module flag are fixed per-triple defaults, unaffected by `--mcpu`. |
| `--mmcu=<device>` | The AVR device name passed to the link driver as `-mmcu=<device>` (e.g. `--target=avr --mcpu=avrxmega3 --mmcu=avr32dd20`). Only consulted on an AVR triple; ignored otherwise. Distinct from `--mcpu`: `--mcpu` picks the LLVM codegen ISA/family (`avrxmega3` covers a whole AVR-Dx family core), while `--mmcu` picks the exact device for avr-gcc's device-specific linker script and startup code. When `--mmcu` is not given, the link step falls back to the `--mcpu` value — sufficient when `--mcpu` already names an exact device (e.g. `attiny1634`), but a bare family core like `avrxmega3` still links (a generic family layout) rather than erroring, so pass `--mmcu=<device>` explicitly whenever the target is a specific chip. |
| `--linker=<cmd>` | Override the link-driver command/path used for the final link step. Wins over the triple-based default (`clang` for hosted targets, `avr-gcc` for an AVR `--target=`, `riscv64-linux-gnu-gcc` for a `riscv64` `--target=` **when cross-compiling**) regardless of triple. On a riscv64 *host* the sysroot is `/`, so a `riscv64` target keeps the plain `clang` default rather than reaching for the triplet-prefixed cross driver — the latter is a Debian-family naming convention that other riscv64 distros do not ship. Pass `--linker=cc` (or `--linker=gcc`) if the native host has no `clang`. |
| `--link-arg=<arg>` | Pass one verbatim argument to the link driver, appended after the object file. Generalizes `-l<lib>`/`-L<dir>` (which route through the same mechanism) to arbitrary linker flags. |

## Diagnostics

Every compiler error is printed as

```
<path>:<line>: error: <message>
```

on stderr, optionally followed by an indented `  note:` line (used to point a
monomorphization failure back at the instantiation that requested it).

**Every diagnostic names a real line.** This is a guarantee, not a
best-effort: the test suite compiles every fixture and fails if any diagnostic
reports `:0:`. It is worth stating explicitly because a whole family of errors
— unresolved names, `let`/`with` initializers, retired special-form spellings,
`defvar` initializers, `match` arm patterns — used to report line 0.

The reason is worth knowing if you work on the compiler: **a bare symbol node
has no source line.** The reader interns symbols, so all occurrences of a
spelling anywhere in the program share one `Node`, and a per-occurrence line
cannot be stored on it (writing one would be visible to every other
occurrence). A diagnostic whose subject is a symbol therefore borrows the line
of the *enclosing form*, which does carry one — `node-line`
(`lib/node.nuc`) is the helper that expresses this, and `emit-node` maintains
the ambient enclosing line for the one site that cannot be handed a node
(`emit-symbol-ref`, reached with only the operand).

### Unresolved names

`unknown: <name>` is a name in head position with no function, macro or special
form behind it; `undefined: <name>` is the same failure in value position. Since
resolution is by [reachability, not import
order](toplevel.md#cross-file-resolution-reachability-not-import-order), a name
defined *anywhere in the compilation unit* resolves — so an unresolved name is
one of four things, and the message says which.

**0. It is a `qualifier/name` whose qualifier is not in scope in this file.**
[What an import brings into scope](toplevel.md#what-an-import-brings-into-scope)
is the whole answer — another file's `(import-prefixed …)` does not make its
prefix spellable here, and a namespace nobody imported is not spellable at all.
This one is not a reachability failure — the definition is in the unit — so it
is reported as what it is. When the qualifier is a prefix *some other* file
bound, the note names that file, because that is the fix:

```
main.nuc:2: error: unknown: gx/area — 'gx' is not in scope in this file
  note: an import prefix is file-scoped: another file in this unit binds 'gx' to
  lib/geometry.nuc, but a prefix reaches only the file whose own import declares
  it. This file has no import qualifiers in scope.
```

Otherwise the note gives the general rule and lists what this file *can* spell.
A **protocol** reference reaches the same note through its own head ("unknown
protocol" / "not a declared protocol") rather than through `unknown:`:

```
main.nuc:6: error: extend: unknown protocol 'shapes/Shape'
  note: 'shapes' is not in scope in this file — a prefixed import binds its
  library under the prefix it names and not under the library's own namespace,
  and an unimported namespace is not nameable at all. In scope here: sh.
```

**1. The C header declared it, and the importer could not describe it.** The
header, line and reason, instead of a spelling guess:

```
prog.nuc:12: error: unknown: 'strtold' — its C header declaration was skipped
  (/usr/include/stdlib.h:114: a by-value parameter or return of unknown type 'long double')
```

**2. It is defined in a file that no import reaches.** Reachability is still
required (a file outside the unit is not part of the program), but the compiler
looks for the name in the `.nuc` / `.nuch` files on its import search path — the
current file's directory, `lib/`, and each `-I` directory — and names the one
that defines it. The fix is to import that file:

```
main.nuc:1: error: unknown: y-later — not defined anywhere in this compilation unit
  note: 'y-later' is defined in ./yf.nuc, which no import in this unit reaches
```

The same note is attached to `unknown type:`, which is how the reachability rule
shows up for a struct, union or protocol named in a signature.

This search is a textual scan of files outside the unit, run only on the way to
aborting the compile, so it is a `note:` — the primary error above it is true on
its own. It suppresses the did-you-mean below, since naming the file is a
strictly better answer than guessing at a spelling.

**3. Nothing defines it.** The common typo. A near-miss among the registered
functions, macros, type names and globals is named:

```
t.nuc:4: error: unknown: printfx (did you mean 'printf'?)
t.nuc:7: error: unknown: close (did you mean 'fclose'?)
```

The allowance scales with length — names under 4 characters get no suggestion,
4–6 characters allow one edit, 7 and up allow two — so a short name never draws
a coincidental match. With nothing close enough, the message states what was
searched:

```
t.nuc:4: error: unknown: qzx-frobnicate — not defined anywhere in this compilation unit
```

**A suggestion is a spelling this file can write.** The candidate's own
namespace decides how it is rendered: a name in this file's namespace, in
`user`, or in a namespace this file flattened is offered bare; one reachable
only through an import prefix is offered qualified; and a candidate this file
cannot reach at all — including a private definition in another namespace — is
not offered. So a library function imported as `(import-prefixed lib zx)` is
suggested as `zx/zfun`, not as the bare `zfun` that just failed.

### Not a function

A name that *is* defined, but in a registry with no head-position meaning, says
so instead of claiming to be unknown:

```
t.nuc:9: error: 'Shape' names a protocol, not a function
t.nuc:11: error: 'Maybe' names a type, not a function
```

The same table drives the one-symbol-one-kind rule below, so the noun in this
message and the noun in a collision diagnostic are the same answer.

### One symbol, one kind

A symbol may name only one kind of thing. Every top-level definer checks the
name it is about to introduce against every registry — special forms, built-in
type names, macros, functions, values, protocols, structs, unions and templates
— and refuses a name that already denotes a *different* kind:

```
t.nuc:4: error: 'Shape' already names a protocol — a symbol may name only one kind of thing
```

Two properties are worth knowing. The check is for a binding of a **different**
kind, not for the highest-priority binding, so it does not matter which registry
would win in head position; and because every definer registers its own name in
a prescan before any form is emitted, a cross-kind clash is reported at
whichever of the two definitions is **emitted first**, naming the other one's
kind. Same-kind reuse stays legal: an overloaded `defn`, a re-imported
`defstruct`, a redefined macro.

### Call arity

A call must supply an admissible number of arguments, and the rule depends on
what the callee's signature says:

| Callee | Admissible argument count |
|---|---|
| an ordinary `defn` / `extern` | exactly `num-params` |
| a `defn` with `&optional` | `num-params - <optional count>` … `num-params` |
| a `defn` with `&rest` | at least `num-params - 1` (the rest slot folds the tail) |
| a function imported from a C header, declared variadic (`printf`) | at least the fixed prefix |
| a hand-written `declare` | at least `num-params` — see below |
| a function-pointer value called indirectly | exactly `num-params` |
| a `(BoxedFn …)` / `(dyn P)` handle | exactly the box signature's `num-params` |

```
t.nuc:9: error: call to 'f': expected 1 args, got 2
t.nuc:9: error: call to 'f': expected 2 args, got 1
t.nuc:7: error: call to 'opt': expected at most 2 args, got 3
t.nuc:7: error: call to 'r': expected at least 2 args, got 1
```

**A hand-written `declare` is open-tailed.** A `declare` is a prototype you
*assert*, not a body the compiler has seen, and Nucleus has no `...` spelling
(`&rest` / `&optional` are `defn`-only and are [rejected in a
declaration](toplevel.md)). So declaring a C variadic function means declaring
its fixed parameters and letting the extra arguments ride the call site, and the
arity check admits that: more arguments than parameters is legal against a
declared signature, *fewer* is still an error. Importing the function's C header
instead (`(import "stdio.h")`) is the precise route — the header carries a real
variadic flag, so the fixed prefix is checked exactly and the tail is free.

An **overloaded** name (two or more `defn`s sharing a spelling), a multimethod,
a protocol method and a bounded-generic template are resolved by argument
*types*, so a wrong count is reported as a resolution failure — `no matching
method for overloaded 'f' with argument types (…)` — rather than by this check.

### Unbalanced brackets

An unterminated form reports **two** locations: the opening line of the
innermost form that was still waiting for its closer, and — on a `note:` line —
the first line that opens a *new* form in column 0 while some form was still
open. The second number is the one that localizes the mistake, because a
top-level form starting inside another form is the first point at which a
missing closer becomes observable. The note also says how many forms were open
there, which is how many closers are missing.

```
t.nuc:12: error: unterminated list
  note: line 23 starts a new form in column 0 while 1 form(s) are still open -- a ')' is probably missing before line 23
```

If the imbalance is inside the file's *last* top-level form there is no such
line, and the note says so rather than inventing a number:

```
t.nuc:9: error: unterminated list
  note: end of file reached with 3 form(s) still open
```

All four bracket kinds participate — `(`/`)`, `[`/`]` (vector literal),
`{`/`}` (map literal), `#{`/`}` (set literal) — and the note names the closer
the unterminated form is actually waiting for.

The mirror-image mistake, an *extra* closer, is reported where the excess
closer is (paren counting cannot know which one was the intruder) together with
the opening line of the form it would have closed, which bounds the search to a
single top-level form:

```
t.nuc:13: error: unexpected )
  note: the form opened at line 10 is already closed -- look for an extra ')' between lines 10 and 13
```

One extra-closer mistake does not reach the reader at all: an extra `)` inside a
`let`/`with` binding list ends the list early and turns the next binding into a
body form, and if the file is otherwise balanced it parses fine. That is
diagnosed at the `let`:

```
(let (a:i32 1)      ; <- this ')' ends the binding list
      b:i32 2)      ; <- so b:i32 and 2 are body forms
  ...)
```

```
t.nuc:11: error: let: 'b:i32' is a body form, not a binding -- an extra ')' probably ended the binding list early
```

Note the binding list left behind (`(a:i32 1)`) has an *even* element count, so
the separate "binding list must be even" check — which fires when an extra `)`
lands after a binding *name* instead of after its value — does not see this
shape.

## REPL

Start with `nucleusc -i`. The REPL reads one form at a time, JIT-compiles it, and prints the result. Multi-line input is supported (the REPL detects unbalanced parentheses and prompts for continuation lines with `...>`).

Supported top-level forms in the REPL: `defn`, `defvar`, `defconst`, `defenum`, `defstruct`, `extern`, `import`, `import-use`, `import-prefixed`, `import-only`, `unsafe/import-private`, `defmacro`, `def-rmacro`, `compile-time`, `macroexpand`, `macroexpand-1`, `macroexpand-all`. Any other form (including bare symbols, integers, and function calls) is evaluated as an expression.

Result printing is type-aware: integer kinds print as decimal, string literals print as `"..."` with escapes, quoted forms (`'foo`, `(quote ...)`) print using the AST printer, and other pointer values print as `#<ptr 0x...>`. The reader rejects `#<...>` syntax with a clear error so a printed unreadable value can't silently round-trip as input.

`macroexpand` / `macroexpand-1` print the expansion of a quoted form. `(macroexpand '(when c b))` expands to fixpoint; `(macroexpand-1 '(when c b))` expands one step. An optional integer second arg overrides the depth: `(macroexpand 'form 2)` expands at most twice; `(macroexpand 'form -1)` expands to fixpoint. Subforms are not recursed into (matches Common Lisp `macroexpand`). If the form is not a macro call (head is missing or not a registered macro), the REPL prints `not a macro call: <form>` rather than echoing the input unchanged. `macroexpand-all` expands the head to fixpoint and then recursively expands every subform; quoted/quasiquoted forms are left untouched.

Functions defined in the REPL persist across inputs and can call each other. All libc functions (stdio, stdlib, string, ctype, unistd) are pre-loaded — no `(import-use ...)` needed.

Imported libraries work: `(import-use mathlib)` makes `square`, `cube`, etc. available. The standard macros (`if`, `when`, `unless`, `for`, `dotimes`, `->`) are auto-imported at REPL startup, so they're usable without `(import-use macros)`. The `Node` struct and `NODE-*` constants are pre-registered for macro support.

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
| `(imports)` | Print resolved paths of all `import`/`import-use` entries, one per line. |
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
- `(import-use node)` brings in the AST utilities (`make-cell`, `node-at`, `node-len`, `node-is-list`); they allocate via `arena-alloc` and the arena initializes lazily on first call.
- stdout from JIT'd code is line-buffered (`setvbuf(stdout, NULL, _IOLBF, 0)` is called on REPL startup) so printf output appears immediately in both terminal and pipe-driven sessions.

## .nuch Header Format

A `.nuch` file is an S-expression file containing declarations extracted from a Nucleus source file. It allows importing a library's interface without its source code — function bodies are resolved at link time from the corresponding `.o` file.

```lisp
; .nuch header for lib/mathlib.nuc
(declare square (x:i32) :i32)
(declare cube (x:i32) :i32)
```

Supported forms: `declare` (function signatures), `defstruct`, `defconst`, `defenum`, `defmacro` (full body preserved), `defmethod` (one overloaded method, carrying its mangled symbol explicitly), `defprotocol` / `extend` (protocol definitions and conformance facts, exported verbatim), `defcast` (full form preserved — the conv-fn must already be `declare`d earlier in the same header), and a producing module's `defvar` globals (re-emitted as `extern` so importers see the symbol without its initializer). A solitary function exports as `declare`; an overloaded one exports a `defmethod` per method so each keeps its distinct symbol:

```lisp
(defmethod "@area.pCircle" (area i32) ((c (ptr Circle))))
(defmethod "@area.pRect"   (area i32) ((s (ptr Rect))))
```

Importing a `.nuch` with `declare` or `defmethod` forms registers the function both as a global binding (so it can be called) and as a method in the overload registry (so it can be *resolved by signature* — a protocol conformance the importing unit asserts, a `(dyn P)` vtable slot). This is the same pair of registrations a local `defn` makes. The one difference is that the imported method's symbol is a fact, not a decision: the defining unit emitted it, so the importing unit's mangling never renames it, however many local overloads of the name join the set. Imported `defprotocol` forms re-register the protocol; imported `extend` forms with a *concrete* subject record the conformance fact without re-checking it (the exporting unit already verified it). An imported `extend` whose subject is a struct *template* (`(extend (Vector T) (Seq T))`, or an associated-type combinator `(extend (MapIter I F) (Iterator E) &where …)`) is re-run as a template conformance: the exporter cannot serialize the recovered args for instances it never stamped, so the importer re-registers the template conformance (carrying any `&where` clause, which is exported verbatim on the `extend` form) and recovers the per-instance args at stamp time when it stamps a concrete instance locally. Imported `defcast` forms re-register the cast rule; imported `extern` forms emit an `external global`. See [Polymorphism](generics.md#polymorphism-overloaded-defn-multimethods) and [Protocols](generics.md#protocols-defprotocol-and-extend).

### Namespaced libraries (`.nuch` round-trip)

When the source declares a namespace, its public symbols emit *mangled* link names (`geom/area` → `@geom__area`; see [namespaces](#namespaces)). The `.nuch` carries that namespace so an importer re-resolves the symbols under the correct link name: the header opens with the namespace directive (and a `set-ir-prefix` line if the library overrode the default prefix), and the importer's `do-import` re-runs the **same** ir-name computation while that namespace is current.

```lisp
; .nuch header for lib/nsgeom.nuc
(ns geom)
(declare area ((w i32) (h i32)) :i32)
(declare perimeter ((w i32) (h i32)) :i32)
```

Importing this with `(import-prefixed "nsgeom.nuch" g)` makes `g/area` resolve to `@geom__area` — matching the link name in the library's `.o`. Overloaded methods already carry their fully-mangled symbol on the `defmethod` form (`@geom__area.i32.i32`), so they round-trip unchanged; the `(ns …)` line additionally fixes the link name of *solitary* `declare`d functions and `extern` globals (which the importer otherwise rebuilds from the bare name). A library in the default `user` namespace emits **no** `(ns …)` line and bare names, so its header is byte-identical to before.

The same round trip applies to a namespaced **type**: the header's `(defstruct Pt ...)` line is unqualified, as it always was, but the leading `(ns gt)` directive tells the importer to re-register it as `gt/Pt` — so `(import-prefixed "nsgeom.nuch" g)` makes `g/Pt` resolve to the library's `%gt__Pt` LLVM type and, for `--emit-cheader`, its `gt__Pt` C typedef, exactly as `g/area` resolves to `@geom__area`. See [Namespaced type names](types.md#namespaced-type-names).

## Regenerating committed headers

The `lib/*.nuch` and `lib/*.h` headers are generated by `--emit-nuch` / `--emit-cheader` and also committed, so they can fall behind the compiler that produced them: nothing in the build reads the committed copies (`make lib-headers` and `make lib-cheaders` overwrite them), and a consumer only discovers the mismatch when a declaration no longer describes the library.

`make check-headers` verifies that every committed header still matches a fresh emission, byte for byte — header emission is a pure function of the source, so any difference is drift. It also fails on a `lib/*.nuc` with no committed header, on a header whose recorded source no longer exists, and on a header that records an **absolute** source path (which regenerates only on the machine that produced it). The same check runs inside `make test` as the `headers-generated` unit.

`scripts/check-headers.sh --fix` regenerates the drifted headers. Prefer it to the `make` targets: those are driven by `$(wildcard lib/*.nuc)` and so cannot reach `lib/mapiterlib.nuch`, whose source is `tests/fixtures/mapiterlib.nuc`. Each generated header names its own source on its first line, which is what the check reads — a hand-written header such as `src/llvm.nuch` has no such line and is left alone.

## Reaching a library's globals from C

A public `defvar` is exported to the generated C header as an `extern` declaration, so a C consumer reads and writes the same object the Nucleus library does:

```lisp
(defvar counter:i32 7)
(defvar :const limit:i32 99)
(defvar tick-count:i64 41)
(defvar- hidden:i32 5)          ; private — not exported
```

```c
extern int32_t counter;
extern const int32_t limit;
extern int64_t tick_count asm("tick-count");
```

Three rules are worth knowing:

* **A hyphenated name gets an `asm` label.** See [Hyphenated names in a C header](#hyphenated-names-in-a-c-header) below — the rule is the same for a global and a function.
* **`:const` becomes C's `const`.** It is the same read-only-storage guarantee.
* **`defvar-` is not exported**, the same as every other private definer.

A global whose type has no faithful C spelling is **omitted with a comment** rather than declared:

```c
/* m-skip: type has no C spelling here; not exported */
```

This covers `(array T N)`, union-template instances like `(Maybe i32)`, closure and type-erased box types. The reason it is an omission rather than a best effort is that the fallback spelling would be `void*` — pointer-sized, which is right for a pointer and silently wrong for anything else, and a declaration the C compiler trusts and gets wrong is worse than one that is missing. Pointer-typed globals *are* exported under all three spellings (`ptr:T`, `raw:T`, `ref:T`); the latter two currently widen to `void*`, as they already do in function signatures.

## Hyphenated names in a C header

`-` is an ordinary character in a Nucleus name and is illegal in a C identifier, so every name a header exports is rewritten. Which rewrite depends on **whether the linker resolves the name**:

| Kind of name | C spelling | Why |
|---|---|---|
| `defn`, `defvar` | sanitized **+ `asm("real-symbol")`** | The object defines `@my-func`; the header must both spell an identifier and name that symbol, and one token cannot do both. |
| struct field, function parameter, `defunion` arm, enum tag, `#define` from `defconst` | sanitized | Nothing links against these — the name only has to parse. |
| struct / union type name | sanitized | Same: a typedef name is not a symbol. |

```nucleus
(defconst BUF-LEN 4)
(defstruct My-Rec a-field:i32 xs:(array i32 BUF-LEN))
(defn my-bump (n-arg:i32):i32 (return (+ n-arg 1)))
(defn plain (n:i32):i32 (return n))
```

```c
#define BUF_LEN 4
typedef struct My_Rec {
    int32_t a_field;
    int32_t xs[BUF_LEN];
} My_Rec;
int32_t my_bump(int32_t n_arg) asm("my-bump");
int32_t plain(int32_t n);
```

A struct or union is emitted with a **tag** as well as a typedef, and the two share
a spelling (C keeps them in separate namespaces), so both `My_Rec` and
`struct My_Rec` name the completed type. The tag is what a header's own references
use — a nested field, a by-value parameter, a by-value return — so without it every
by-value use of a library's type failed to compile against the header the compiler
generated for it.

Sanitizing a linked name *without* the label gives a header that parses and then fails to **link** — strictly worse than one that fails to parse, because the error moves away from its cause. The label is emitted only where the sanitized spelling differs from the link name, so `plain` above carries none and a library with C-legal names gets a fully portable header.

Two consequences worth knowing:

* **`asm` labels are a GCC/Clang extension.** A library with hyphenated public names produces a header that needs one of those compilers; a library that names its exports in C-legal form does not.
* **Sanitizing is not injective.** `foo-bar` and `foo_bar` both spell `foo_bar`. This is caught loudly at the consumer (`conflicting asm label`, or a duplicate member), never silently mis-bound, but the fix is to rename in Nucleus.

## Overloaded and operator-named functions in a C header

The "real symbol" above is not always the function's name. A name that carries
more than one method is [mangled per signature](generics.md#polymorphism-overloaded-defn-multimethods),
and an **operator** name is mangled even when it carries only one — its generic
always holds the intrinsic seed method beside the user's, so `=` on a struct
links as `eq.Pt.Pt`, never `=`. C gets one declaration per method, each with its
own identifier and its own label:

```nucleus
(defstruct Pt x:i32 y:i32)
(defn scale (p:(ref Pt) k:i32):i32 …)     ; overloaded…
(defn scale (a:i32 k:i32):i32 …)          ; …two methods, one name
(defn = (a:Pt b:Pt):i1 …)                 ; operator
(defn solo (n:i32):i32 …)                 ; solitary, non-operator
```

```c
int32_t scale_pPt_i32(void* p, int32_t k) asm("scale.pPt.i32");
int32_t scale_i32_i32(int32_t a, int32_t k) asm("scale.i32.i32");
_Bool eq_Pt_Pt(struct Pt a, struct Pt b) asm("eq.Pt.Pt");
int32_t solo(int32_t n);
```

Only the solitary non-operator function keeps its bare name and needs no label.
The C identifier is the mangled symbol with its dots sanitized, so it is distinct
for each method by construction, and the label is the symbol verbatim. Whether a
name is overloaded is a property of the whole compilation unit rather than of the
file, so header emission runs the same signature prescan a real compilation does
— a library that contributes one `hash` to a name the prelude also defines still
exports it as `hash.pString`, which is what its object file defines.

A **bounded-generic template** — a `&where` clause, or a receiver over a
parametric struct such as `(Vector T)` — is not exported at all: it has no symbol
until a call site stamps it. Those become comments, the same way an
un-C-representable signature does:

```c
/* insert: generic template; not exported */
```

`usize` and `ssize` map to `size_t` and `ptrdiff_t` (hence the `<stddef.h>` include);
`Char` and `Err` are builtin scalars, not structs, and map to `uint32_t` and
`int32_t`.

A header names only the types its own file defines. A signature mentioning a type
from an imported library still spells that type, but the generated header emits no
`#include` for the library it came from, so the consumer must include that
library's header first — `lib/string-split.h` uses `StrView` and does not pull in
`lib/prelude.h`.

## Names C reserves

A legal C identifier is more than a legal sequence of characters. `union`,
`signed`, `default` and `class` are ordinary Nucleus names, and emitting one
verbatim gives a header that does not parse. Every identifier the header
emitter produces — a function, a parameter, a struct field, a struct or union
tag, an enum tag, a global, a `#define` — is renamed with a trailing `_` when it
is a word C or C++ reserves, and a name the linker resolves keeps its symbol
through the same `asm` label mechanism a hyphenated name uses:

```nucleus
(defstruct Box class:i32 signed:i32)
(defvar delete:i32 41)
(defn union (a:i32 b:i32):i32 …)
```

```c
typedef struct Box {
    int32_t class_;
    int32_t signed_;
} Box;
extern int32_t delete_ asm("delete");
int32_t union_(int32_t a, int32_t b) asm("union");
```

Only the C spelling moves; the symbol is untouched, so an object compiled
before the header was generated still links against it.

**C++'s keywords are reserved here too**, not only C's, because a generated
header is routinely read through `extern "C"` from C++ — where `class` and
`delete` are as fatal as `union` is in C — and because `new`, `try`, `template`,
`operator` and `namespace` are all names a Nucleus library plausibly defines.
The `iso646.h` spellings (`and`, `or`, `not`, `xor`, …) are covered for the same
reason.

An identifier built by **joining** two parts is tested as a whole rather than
part by part, so a `defenum`'s members keep the spelling their prefix already
makes legal: `(defenum Kind auto static default)` exports `Kind_default`, not
`Kind_default_`.

## Separate compilation and symbol linkage

Importing a `.nuc` file **inlines** it: the importing unit re-emits the imported file's definitions into its own LLVM module. So two objects compiled from two files that import the same library each carry a full copy of that library — and of the prelude, which every non-`(exclude-prelude)` file imports.

Those copies are identical by construction, so the compiler emits them with LLVM `weak_odr` linkage and the linker keeps exactly one. Two separately compiled Nucleus objects therefore link, and the merged copy is a single object at run time: one `g-arena`, one intern table, one copy of a library's `defvar`.

Linkage follows *ownership*, which is the file a definition was written in:

| Definition | Linkage | Why |
|---|---|---|
| A form in the unit's own entry file | external | The unit owns it; this is what a library exports. |
| A form in a file the unit imports | `weak_odr` | A copy; every unit importing that file has the same one. |
| A monomorphized template instance (`(Vector u8)`'s methods, `gmax.i32.i32`) | `weak_odr` | Belongs to no file — any unit that instantiates the template at the same types derives the identical body under the identical symbol. |
| A private definer (`defn-`, `defvar-`, …) | `internal` | Not an exported symbol at all; see [namespaces](#namespaces). |

Two consequences worth knowing:

* A **duplicate definition across two Nucleus objects is not a link error** for anything but a root-owned name — the copies merge silently, which is the point. Duplicates *within* a unit are still rejected by the compiler, so this does not weaken the one-name-one-definition rule inside a compilation unit.
* An imported function that the program never calls is **not** dead-stripped from the IR, because `weak_odr` may not be discarded. This is deliberate: macros are JIT-compiled during compilation and resolve their callees against the running program's symbol table, so a definition the optimizer had removed would be unfindable. Recovering the size costs a link flag (`-ffunction-sections` plus `--gc-sections`), not a change here.

An `(exclude-prelude)` library avoids the copies entirely — it imports nothing, so its object contains only its own definitions.

### Run-time initializers in a multi-object build

A `defvar` with a *run-time* initializer (one the compiler cannot fold to a constant) is initialized from the emitting unit's `@__nucleus_init` constructor. When several objects each inline the file that declares it, each object's constructor initializes the now-shared global, so the initializer runs **once per object, not once per program** — measured, with a counter-bumping initializer in a two-object link observing 2. For an idempotent initializer this is invisible; for one that allocates it leaks the earlier result.

Compiling with `-c` warns, at the `defvar`'s own location:

```
lib/dshare.nuc:3: warning: defvar: 'd-runs' has a run-time initializer, and this
object only imports the file that declares it -- every object that imports that
file runs the initializer again on the one shared global. Give it a compile-time
constant initializer, or move it into the object that owns it
```

It is a **warning**, not an error, because a single Nucleus object linked against C code is a supported shape and there the initializer runs exactly once. It fires only under `-c` — the one flag that says "relocatable object bound for a link with other objects". A default whole-program build is correct by construction, and `--emit-llvm` says nothing about the eventual link (it is equally how a whole program is inspected), so both are silent.

The fix the message names is the real one: give the global a compile-time constant initializer. Those cover more than literals — named constants, `(sizeof T)`, `(as T x)`, addresses, constant struct and array aggregates — so most library globals can be written that way, and one that is costs *less*, since no constructor is emitted at all.

Running such an initializer exactly once is **not** simply a matter of adding a guard: the initializer queue is one list in source order and ownership interleaves within it, so grouping the shared initializers reorders them against legal cross-file reads, and guarding them in place makes one object skip work another object's constructor may not have done yet — trading a leak for a silent use-before-init. See the W9 item 2 note in `design/stage15-stress-test/progress.md`.
