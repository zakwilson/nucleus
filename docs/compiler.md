# Compiler Reference

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
| `--emit-cheader` | Output a C header (`.h`) instead of compiling. Emits `#pragma once`, `#include <stdint.h>`, typedefs for structs, extern function declarations, `extern` declarations for `defvar` and `extern` globals, `#define` constants, and enums. For a namespaced library, function declarations use the C-legal mangled link name (`geom__area`, not the Nucleus name `geom/area`), so a C consumer links against the same symbol the library emits. |
| `-i` / `--interactive` | Start the REPL (interactive Read-Eval-Print Loop). |
| `-I<path>` / `-I <path>` | Add a directory to the import search path. Searched after the source file's directory and `lib/`. |
| `--repl-format=text\|json` | Format for REPL error output. Default `text` (legacy `  error: <msg>` lines). With `json`, each error is emitted as a single-line JSON object: `{"file":..,"line":..,"message":..}`. Suitable for agent-driven REPL sessions. |
| `--target=<triple>` | Cross-compile: set the output module's target triple and datalayout (sourced from LLVM) instead of the host's. In-process JIT modules (compile-time bodies, `defmacro`, REPL) always stay on the host. Registered backends: X86 (`x86_64`/`i386`), AArch64 (`aarch64`), ARM (`arm`); Linux, Darwin, and Windows (msvc/gnu) triples all resolve. Pointer size, `size_t`, and struct layout follow the selected target. |

## REPL

Start with `nucleusc -i`. The REPL reads one form at a time, JIT-compiles it, and prints the result. Multi-line input is supported (the REPL detects unbalanced parentheses and prompts for continuation lines with `...>`).

Supported top-level forms in the REPL: `defn`, `defvar`, `defconst`, `defenum`, `defstruct`, `extern`, `import`, `import-use`, `import-prefixed`, `import-only`, `unsafe-import-private`, `defmacro`, `def-rmacro`, `compile-time`, `macroexpand`, `macroexpand-1`, `macroexpand-all`. Any other form (including bare symbols, integers, and function calls) is evaluated as an expression.

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
(declare square:i32 (x:i32))
(declare cube:i32 (x:i32))
```

Supported forms: `declare` (function signatures), `defstruct`, `defconst`, `defenum`, `defmacro` (full body preserved), `defmethod` (one overloaded method, carrying its mangled symbol explicitly), `defprotocol` / `extend` (protocol definitions and conformance facts, exported verbatim), `defcast` (full form preserved — the conv-fn must already be `declare`d earlier in the same header), and a producing module's `defvar` globals (re-emitted as `extern` so importers see the symbol without its initializer). A solitary function exports as `declare`; an overloaded one exports a `defmethod` per method so each keeps its distinct symbol:

```lisp
(defmethod "@area.pCircle" (area i32) ((c (ptr Circle))))
(defmethod "@area.pRect"   (area i32) ((s (ptr Rect))))
```

Importing a `.nuch` with `defmethod` forms registers the methods for dispatch in the importing unit and emits an LLVM `declare` under each mangled symbol (resolved at link time). Imported `defprotocol` forms re-register the protocol; imported `extend` forms with a *concrete* subject record the conformance fact without re-checking it (the exporting unit already verified it). An imported `extend` whose subject is a struct *template* (`(extend (Vector T) (Seq T))`, or an associated-type combinator `(extend (MapIter I F) (Iterator E) &where …)`) is re-run as a template conformance: the exporter cannot serialize the recovered args for instances it never stamped, so the importer re-registers the template conformance (carrying any `&where` clause, which is exported verbatim on the `extend` form) and recovers the per-instance args at stamp time when it stamps a concrete instance locally. Imported `defcast` forms re-register the cast rule; imported `extern` forms emit an `external global`. See [Polymorphism](generics.md#polymorphism-overloaded-defn-multimethods) and [Protocols](generics.md#protocols-defprotocol-and-extend).

### Namespaced libraries (`.nuch` round-trip)

When the source declares a namespace, its public symbols emit *mangled* link names (`geom/area` → `@geom__area`; see [namespaces](#namespaces)). The `.nuch` carries that namespace so an importer re-resolves the symbols under the correct link name: the header opens with the namespace directive (and a `set-ir-prefix` line if the library overrode the default prefix), and the importer's `do-import` re-runs the **same** ir-name computation while that namespace is current.

```lisp
; .nuch header for lib/nsgeom.nuc
(ns geom)
(declare (area i32) ((w i32) (h i32)))
(declare (perimeter i32) ((w i32) (h i32)))
```

Importing this with `(import-prefixed "nsgeom.nuch" g)` makes `g/area` resolve to `@geom__area` — matching the link name in the library's `.o`. Overloaded methods already carry their fully-mangled symbol on the `defmethod` form (`@geom__area.i32.i32`), so they round-trip unchanged; the `(ns …)` line additionally fixes the link name of *solitary* `declare`d functions and `extern` globals (which the importer otherwise rebuilds from the bare name). A library in the default `user` namespace emits **no** `(ns …)` line and bare names, so its header is byte-identical to before.
