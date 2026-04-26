# Cleanup and utilities

## LLM interactions

#### Designer:

In other languages, giving an LLM agent a long-running REPL to interface with during development can greatly improve its performance. What tooling is necessary for Nucleus to do that well?

#### Robot:

The biggest wins come from things that close the feedback loop without leaving the REPL:

- **`macroexpand` / `macroexpand1` at the REPL** (also called out below). Agents can't reason about a macro's behavior by reading the source — they need to see the actual expansion for a specific call site.
- **Readable printing of every value** (also below). Right now structs and quoted lists print as raw addresses, which is unusable: an agent that calls `(foo)` and sees `0x7f...` cannot tell if the answer is correct.
- **Inspection of compile-time state.** Forms like `(symbol-info 'foo)` or `(struct-fields 'Node)` would let an agent ask the compiler what it knows, instead of grepping the source. The JIT already has the data — it just isn't reachable from user code.
- **Structured error output.** REPL errors currently print to stderr as free-form text. A machine-readable mode (file, line, form, message) would let a wrapper feed errors back into the agent's context cleanly.
- **A non-interactive batch mode for the REPL.** Piping a sequence of forms through `nucleusc -i` and getting one structured result per form, with output not interleaved with prompts, is what an agent driver actually wants. The buffering caveat in `docs/builtins.md` (stdout from JIT'd code is block-buffered when stdin is a pipe) is the first thing to fix.
- **Persistent session state across redefinitions.** The current "cannot redefine a function" rule is fine for batch compilation but is the single biggest friction point for agent-driven REPL use. Loosening this — even if it requires a fresh JIT module per redefinition — pays for itself immediately.

Of these, readable print + macroexpand + structured errors are the prerequisites; the rest can come later.

## Read/Print

#### Designer:

Most things should be printable at the REPL and the printed representation should be readable.

Right now builtins like quoted lists and strings print addresses at the REPL. The REPL should probably print both the address and the readable representation or the name of the type if there isn't a readable representation.

Floats don't seem to be readable at all.

Later, there should be polymorphic read and print functions such that anyone defining or importing a type can add ways to print and read it, but we don't have a mechanism for polymorphism yet.

#### Robot:

The compiler already has a working printer for `Node` (`print-node` at `src/nucleusc.nuc:322`) — that's what powers macro debugging. It's the right starting point for the REPL's default printer for quoted lists and symbols.

Strings are easier than they look: the JIT knows the static type of the top-level expression, so when the result is `ptr` returned from a string literal or a function declared as returning a C string, the REPL can dispatch to a string printer. The catch is that `ptr` is overloaded — many things return `ptr`. A pragmatic rule: if the expression is a literal string or a call to a function whose declared return type is a known string-yielding form, print as a string; otherwise print the address. Erring on the side of "show address + best-effort readable form" matches the designer's suggestion and avoids guessing wrong silently.

Floats are a separate issue and worth addressing first because it's purely additive: the reader needs to recognize `1.5`, `-0.25`, `1e10` as float literals, and the printer needs a `%g`-style formatter. No polymorphism required.

For the polymorphism problem long term: the cheapest thing that could work is a global hash table keyed by type-id mapping to a print function pointer, populated by `def-print-method`. That's not a real generic-function system but it's enough to get user-defined types printable, and it can be replaced later when polymorphism is designed properly. This belongs in stage 7+, not here — for stage 6, hardcoded printers for the handful of built-in types are sufficient.

A subtle point: "readable" in the Lisp sense means `(read (print x)) = x`. That's a strong invariant and worth preserving where possible (numbers, strings, symbols, quoted lists), but explicitly giving up on it for opaque types (raw pointers, function pointers, JIT'd closures) by printing `#<ptr 0x...>` is fine — as long as the reader rejects `#<...>` syntax loudly rather than silently misparsing it.

## Variadic functions

#### Designer:

Arithmetic functions in Lisp usually take arbitrarily many arguments. That would be nice.

Optional or rest parameters for user-defined functions would also be nice.

#### Robot:

Two distinct features hiding in one section:

1. **Variadic arithmetic** is a macro problem, not a language problem. `(+ a b c d)` can expand to `(+ (+ (+ a b) c) d)` at compile time with zero runtime overhead, which is exactly the design principle ("many macros"). The current builtin `+` is binary; making it n-ary at the macro layer doesn't touch the core. This is the right move and should happen first because it's small and doesn't constrain the rest of the design.

2. **User-defined `&rest` / optional parameters** is harder because there are two reasonable implementations with very different cost models:

   - **Macro-style rest**: the rest args are collected into a `Node` cons list at the call site by a macro expansion. Zero runtime cost when the call is fully expanded at compile time, but the function can't be called from C and can't be passed as a function pointer in the usual way.
   - **C-style varargs**: the function uses the platform vararg ABI (`va_list`, etc.). Calls from C work, but the callee has to know how many args it got, types are erased, and there's a real per-call cost.

   These aren't mutually exclusive — Common Lisp has `&rest` (boxed list) distinct from `&optional` (named slots) distinct from C varargs (`...`). Nucleus already has `&rest` in `defmacro` (see `docs/builtins.md`), and it consumes a `Node` list. Reusing that surface for `defn &rest` is the consistent choice, with the understanding that those functions are not directly C-callable. C-style `...` should remain reserved for actual C interop.

   Optional parameters are a third axis. The minimum viable form is `&optional name default` where the default is evaluated at call site (the Lisp default — Scheme's let-style default works fine). Implement at the call-site rewrite layer, not in the function body, so the callee doesn't carry an "is-supplied" flag unless the caller asks for one.

Recommendation: ship n-ary arithmetic as macros immediately (small, unblocks ergonomic improvements everywhere). Defer `&rest` / `&optional` for `defn` until after the print/read work — it's a bigger change and the design space deserves a separate pass.

## Macro expansion

#### Designer:

`macroexpand` and `macroexpand-1` (or maybe an optional depth arg) need to be available in the REPL

#### Robot:

The compiler already has the expansion machinery (`emit-macro-expand` at `src/nucleusc.nuc:1651`). Surfacing it as a REPL builtin means: take a quoted form, look up the head symbol in the macro table, run one expansion step (for `macroexpand-1`) or expand to fixpoint (for `macroexpand`), and return the result as a `Node` so the existing printer can render it.

A depth argument is more useful than two separate forms in practice — `(macroexpand form 1)`, `(macroexpand form 5)`, `(macroexpand form -1)` for fully-expanded covers all cases. Keeping `macroexpand-1` as a Lisp-tradition alias is harmless.

One trap: macros run in the compiler's own JIT'd context, which has access to compiler internals. Exposing `macroexpand` as a runtime function in user code means user code can trigger compile-time evaluation. That's fine — it's the same boundary as `defmacro` itself — but it means `macroexpand` should refuse to run (or run in a sandbox) when called from a context where the compiler isn't loaded. In the standalone-binary case, calling `macroexpand` should be a clear error, not a crash.

(The Designer's section originally had a typo `macroexapnd1`, fixed to `macroexpand-1`.)

## Expressions

#### Designer:

In Lisp, everything is an expression that returns a value. C has statements which do not.

Expressions are better if they don't add overhead. If they do, perhaps the compiler can optimize it away if the return value isn't used.

The last expression in a form should usually be the return value of the enclosing form if there's no explicit `return`.

#### Robot:

This is the largest semantic change in stage 6 and worth more design thought before implementation. Three observations:

1. **LLVM doesn't impose overhead.** `if`, `while`, blocks, etc. all become SSA values for free at the IR level — phi nodes are cheap, and dead values are eliminated by the most basic LLVM passes. The "if you don't use the value it disappears" property comes for free once the front end emits the value at all. So the overhead concern is really a front-end concern: don't emit code to *materialize* a value into a temporary unless something asks for it.

2. **Implicit return of last expression.** This is a flag day for existing code. Every `defn` that currently relies on falling off the end (returning whatever is in the return register, which is currently undefined behavior) becomes well-defined. That's a strict improvement, but every test that happens to pass today by accident needs review. The migration is mechanical but not free. Worth doing — but worth doing once, decisively, with the compiler self-host pass as the gate.

3. **Statement-vs-expression boundary in current code.** The compiler today treats `(if ...)` as a special form that branches and doesn't yield a value; binding sites use explicit `(set! x ...)`. Making `if` an expression means `(let ((x (if c a b))) ...)` works without a temporary. This needs a small rework of the codegen for `if`, `while` (returns last body value or unit), `block`/`do`, and `let`. None of these are individually hard; they share the pattern of "emit a phi at the join point if a value is requested."

4. **`return` semantics.** If everything is an expression, what does `(return x)` mean inside a nested expression? In Common Lisp it's `block`/`return-from` — non-local exit. In Rust it returns from the enclosing function. Nucleus currently has explicit `return` matching C. The simplest design: keep `return` as an early-return from the enclosing `defn`, and let "implicit last-expression value" be the *fallback* when no `return` was hit. That matches user intuition from both C and Rust and avoids introducing block labels.

Recommendation: do this *after* read/print/macroexpand. Those are local additions; this changes the semantics of every function. The right time is when there's a stable test suite to catch regressions — and ideally after the compiler is modularized (next section), so the codegen changes are localized.

## Modular compiler

#### Designer:

The source for the compiler is pretty monolithic right now. Here are some potential improvements:

### Move C header parsing and generation to a library

C interop is core to the language, but does it have to be in the compiler's core source file? Separating it would improve readability.

#### Robot:

`src/nucleusc.nuc` is 4171 lines. C header parsing and generation is a substantial fraction of that — `emit-c-include` and friends, plus `emit-cheader-*` (around lines 2208 and 3323–3400). Pulling them into `lib/cheader.nuc` (or splitting parser and generator) is straightforward in principle: the boundary is clean (input: file path or form list; output: forms or text).

The actual blocker is bootstrap. The compiler that's being built can't `import` libraries that don't yet exist in compiled form, and stage-3b interop made the compiler depend on its own C-header parsing to read libc. If `cheader.nuc` is itself a library that the compiler imports, there's a chicken-and-egg: compiling the compiler needs the cheader library, which needs to be compiled by... the compiler. Two ways out:

1. **Internal split, single binary.** Move the code to `src/cheader.nuc` and have `src/nucleusc.nuc` `(import cheader)` it as a *source* import (not a `.nuch` import). Source imports inline definitions, so the resulting compiler is still a single binary. This gets the readability benefit without the bootstrap problem. Recommended.

2. **External library.** Build `lib/cheader.nuc` as a `.so` and have the compiler load it dynamically. This works only after the compiler can already produce shared libraries (stage 3a is done), and it makes the compiler depend on a runtime library to start up. More flexibility, more failure modes. Not worth it for stage 6.

Other separations that would help readability, in rough size order:
- **REPL** (`repl-*` functions, ~400 lines) — the cleanest split, since the REPL only needs the public compiler API.
- **Macro expansion** (`emit-macro-expand` and the macro table) — already conceptually distinct.
- **Type system / desugar** — small but central; splitting it would force the compiler's internal types to be a stable interface, which is good discipline.
- **Codegen primitives** (LLVM IR emission helpers) — would benefit from being separate, but likely the last to split because everything calls into it.

The single most impactful split is probably the REPL, because it's growing fastest and is the part most likely to need iteration as the LLM-interaction tooling above gets built. Pulling C header handling out is the right second step.

A note on principle: the design overview says "Simplicity of implementation is prioritized over design purity." A 4000-line file is not in itself a problem. The reason to split is to make changes easier and to let new contributors orient themselves — both of which become more relevant as the language matures. Don't split for aesthetics; split where the friction is real.
