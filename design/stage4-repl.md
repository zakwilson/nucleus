# The Read Eval Print Loop

####  Designer:

Lisp developers traditionally develop with a long-running process connected to their editor providing information editors for other languages get through static analysis. LLM tools can interact similarly, iteratively testing improvements to a program in a tight loop without having to recompile the world and rebuild state from scratch.

Nucleus needs a REPL. That should be easy now that it has a JIT compiler and libraries.

#### Robot:

The JIT infrastructure (`g-jit`, `jit-add-module`, `jit-ensure-init`) already does 90% of what a REPL needs. The compiler can parse source, generate LLVM IR, add it to a running JIT instance, and call the resulting functions — that's the eval in read-eval-print. The main work is turning this batch pipeline into an interactive loop.

**Architecture.** The REPL would be a separate binary (`nuc-repl` or `nucleus -i`) that links against the compiler's extracted libraries (reader, type system, scope, codegen — the stage-3 refactor). Its main loop:

1. **Read** — Read one top-level form from stdin. The existing `read-form` works on a source buffer; it needs a minor adaptation to read from a line buffer or stream incrementally. Multi-line input requires detecting incomplete forms (unmatched parens) and prompting for continuation lines.

2. **Eval** — Feed the form through the compiler's top-level dispatch. `defn`, `defvar`, `defstruct`, `defmacro`, `include`, and `import` work as in batch mode, emitting IR and adding it to the JIT. Expression forms get wrapped in a temporary `__repl_eval_N` function (similar to `__compile_time_main_N`), JIT-compiled, and called.

3. **Print** — The tricky part. Nucleus is statically typed and currently has no runtime type information. For the REPL to print results meaningfully, it needs to know the type of the expression it just evaluated. The compiler already infers this during codegen (`emit-expr` tracks types). The REPL can use that type to select a printer: `i32`/`i64` → print as integer, `ptr` → print as hex address (or as string if it came from a string literal), `f64` → print as float. Struct types could get a generic printer if structs carry field metadata. This is where having the type system as a library pays off.

**Persistent state.** The JIT session (`g-jit`) and the global scope (`g-globals`) persist across REPL inputs. A function defined on line 1 is callable on line 50. This is already how `compile-time` works — each `compile-time` block sees definitions from prior blocks. The REPL generalizes this to all top-level forms.

**Mutable globals.** `defvar` in batch mode emits LLVM IR globals. In the REPL, the same mechanism works — the global lives in JIT memory and persists for the session. `set!` on globals should work out of the box since the JIT resolves symbols across modules.

**Error recovery.** In batch compilation, errors call `die-at` which calls `exit(1)`. The REPL must catch errors and continue. This means replacing `die-at` (in REPL mode) with a longjmp or equivalent that unwinds back to the read prompt. The simplest approach: `setjmp` at the top of the REPL loop, and have `die-at` call `longjmp` instead of `exit` when a REPL flag is set. Partial IR from the failed form should be discarded (don't call `jit-add-module`).

**Editor integration.** The designer mentions editor-connected development. The standard approach is a socket/pipe protocol where the editor sends forms and receives results. A minimal version: the REPL reads from stdin and writes to stdout, and the editor talks to it over a subprocess pipe. A richer version could implement a simple protocol (one form per message, delimited by a marker) that supports:
- Eval-in-context (send a form, get the result and type back)
- Symbol lookup (what type is `foo`? where was it defined?)
- Completion (list symbols in scope matching a prefix)

For LLM tool use specifically, the REPL's stdin/stdout interface is already sufficient — an LLM agent can send forms and read results the same way a human would. The key value is the persistent JIT state: the agent can define a function, test it, redefine it, and iterate without recompiling from scratch each time.

**Readline / line editing.** For interactive use, link against libreadline or libedit for history and editing. This is a C library, so `(include readline)` would add it once the libc declaration table has the right entries (or use the new native import to wrap it).

**Dependencies on stage 3.** The REPL benefits enormously from the library refactor. Without it, the REPL would need to duplicate or link against the entire compiler. With extracted libraries, it imports just what it needs (`reader`, `types`, `scope`, `codegen`) and stays lean. The import mechanism also means the user can `(import mylib)` in the REPL and immediately use those definitions interactively.

#### Designer:

Editor integration is deferred for the first pass. Line editing is required eventually, but the project must remain under the Apache license with LLVM exceptions. It can't add a permanent dependency on GNU readline due to the license. It looks like libedit has a compatible license.

The REPL is a separate binary from the compiler, but it is desirable to refactor the compiler if that simplifies implementation

#### Robot:

Comments and questions that should be resolved before implementation.

**1. setjmp/longjmp are not in the libc table.** The error recovery design depends on `setjmp`/`longjmp`, but neither is currently in the compiler's `add-libc` declarations. `setjmp` is also unusual: on most platforms it operates on a `jmp_buf` which is a large opaque type (200 bytes on x86_64 glibc). Nucleus has no way to express `typedef`-sized opaque stack buffers today. Options: (a) add `setjmp`/`longjmp` to the libc table with `jmp_buf` treated as a fixed-size byte array allocated via `malloc` or the arena, (b) write a small C shim that wraps `setjmp`/`longjmp` behind a simpler API (e.g. `repl_try()` returns 0 on first call, 1 on error; `repl_throw()` jumps back), (c) use `sigsetjmp`/`siglongjmp` which have the same problem. The C shim approach is simplest because it hides the `jmp_buf` type entirely from Nucleus and only exposes two `ptr`→`i32` functions. **Decision needed: which approach for setjmp?**

**2. IR output model needs rethinking for the REPL.** The batch compiler accumulates IR in three `open_memstream` buffers (`g-type-stream`, `g-decl-stream`, `g-def-stream`), then dumps them all to stdout at the end of `main`. The REPL can't use this model — it needs to produce a complete IR module string per form and feed it to `jit-add-module`. This is similar to how `compile-time` already works (it creates its own memstreams per block), but the REPL needs this for *every* top-level form, not just `compile-time` blocks. The question is whether the REPL resets and reuses the global streams per form, or whether it creates fresh streams each iteration. Resetting the globals is simpler but requires careful cleanup of partial state on error (ties back to the setjmp question). **Decision needed: per-form fresh streams, or reset-and-reuse?**

**3. The reader currently operates on a complete source buffer.** `read-program` reads the entire file into memory, then parses all forms. For the REPL, input arrives line by line. The design mentions "minor adaptation" but the reader globals (`g-src`, `g-pos`) assume a contiguous buffer. Two approaches: (a) accumulate input lines into a growing buffer until the form is complete (detect balanced parens/brackets), then hand the buffer to the existing reader — this is simple and keeps the reader unchanged, (b) modify the reader to pull from a stream. Approach (a) is strongly preferred since it avoids touching a well-tested library. The paren-balancing logic is simple: count open/close parens and keep prompting for continuation lines until balanced. Edge case: string literals and comments can contain parens that shouldn't be counted. A minimal lexer-level paren counter (that tracks whether we're inside a string or comment) is needed for correctness.

**4. The REPL binary needs the full codegen pipeline, not just libraries.** The document says the REPL "imports just what it needs (reader, types, scope, codegen) and stays lean." But the extracted libraries currently are `reader.nuc`, `node.nuc`, `list.nuc`, `arena.nuc`, `macros.nuc`, and `format.nuc`. The core codegen — `emit-expr`, `emit-defn`, the entire type system, scope management, the top-level dispatch — is still inline in `nucleusc.nuc` (~2700 lines). The REPL either needs those extracted as libraries too (a large refactoring effort), or it needs to effectively include most of `nucleusc.nuc`. A pragmatic first pass: the REPL binary *is* the compiler with a different `main` — it links the same object file but replaces the entry point. This could be done by factoring the compiler's `main` into a `compiler-main` function and a `repl-main` function, both linking against the same compiled codegen. **Decision needed: extract codegen first, or build the REPL as a modified compiler binary?**

**5. Redefining functions in JIT.** The design assumes redefinition works ("the agent can define a function, test it, redefine it"). But LLVM ORC JIT resolves symbols at lookup time. If a function `foo` is defined in module 1, then a new `foo` is defined in module 2, the JIT's behavior depends on symbol resolution order. By default, ORC searches newer modules first, so the new definition wins for *new* callers, but existing compiled code that already has a direct call to the old `foo` will keep calling the old one. This is fine for interactive use (each eval compiles fresh) but surprising if you redefine a function that another already-JIT'd function calls. **Is this acceptable for the first pass, or does the REPL need to warn on redefinition?**

**6. Memory management across iterations.** The compiler currently uses a single arena (`ARENA-SIZE = 16MB`) for all allocations. In batch mode this is fine — allocate, compile, exit. In a long-running REPL session, the arena will eventually fill up. Options: (a) grow the arena (replace with `realloc`-backed allocation), (b) add a per-form sub-arena that gets freed after each eval (but persistent definitions like `defn` need to survive), (c) accept the 16MB limit as adequate for interactive sessions and document it. **Decision needed: arena lifetime strategy for the REPL.**

**7. `include` in the REPL.** The libc table (`init-libc` / `add-libc`) is populated once during compiler startup. In the REPL, a user might type `(include math)` to get math functions. This should work if `init-libc` has already run, since `include` just activates a subset of the pre-registered declarations. But if the user expects to include arbitrary C headers (the interop goal), that's a different story. **Confirm: `include` in the REPL is limited to the hardcoded libc table, same as batch mode?**

**8. Compile-time blocks in the REPL.** In batch mode, `(compile-time ...)` JITs code and runs it during compilation. In the REPL, everything is already JIT'd — there's no meaningful distinction between compile-time and runtime. Should `(compile-time expr)` in the REPL just eval `expr` normally? Or should it be an error? The most useful behavior is probably treating it as a no-op wrapper (eval the body, don't print the result), since users might paste code that contains `compile-time` blocks.

**9. Order of implementation.** Suggested sequence given the questions above:

   1. **Add setjmp/longjmp support** — either via C shim or libc table extension. Test with a simple program that recovers from an error.
   2. **Factor compiler main into reusable emit pipeline** — extract the top-level dispatch loop and stream setup into callable functions. The batch compiler's `main` becomes a thin wrapper. This is needed regardless of whether codegen gets fully extracted to libraries.
   3. **Build REPL main loop** — a new source file (`src/nuc-repl.nuc` or similar) that calls the extracted emit pipeline in a loop. Per-form: read input, set up streams, emit IR, add to JIT, call the eval wrapper, print result, recover on error.
   4. **Input handling** — paren-balanced line accumulation, continuation prompts.
   5. **Result printing** — type-aware printer using the inferred type from `emit-expr`.
   6. **Line editing** — libedit integration (deferred per designer, but the REPL should be usable without it via raw stdin).

#### Designer:

1. Use the C shim for now. This will be replaced once there's better C interop.
2. Fresh streams are cleaner.
3. Use a growing buffer for now.
4. Modify the compiler for now. Single binary with a -i/--interactive flag.
5. Warn on redefinition.
6. Grow the arena. Most development machines have more than 16mb to spare in 2026.
7. `include` works like batch mode. Now, that means hardcoded tables. Later, it will mean reading C headers.
8. The REPL is effectively compile time, so `compile-time` blocks should run and print something.
