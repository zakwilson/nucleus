Nucleus is a replacement for C using Lisp style syntax and macros with LLVM as its target. It is a low level systems programming language meant to manipulate memory directly, and when required, unsafely.

## Goals

### True drop-in substitute for C

- Zero mandatory runtime overhead relative to C
- C interop - include C libraries and call C functions with no overhead
- Use C structs and arrays natively

### Lisp syntax

- The language is written as a direct representation of linked lists of symbols, numbers, and strings
- Reader macros add syntactic sugar for things like dereferencing pointers
- User-defined reader macros will be possible
- A vector type like Clojure could be useful, or at least improve readability
- Member access for arrays and structs by calling them like functions - maybe provide a way to overload this

### Full language at compile time

- Macros run at compile time have full access to the Nucleus language, as in most Lisps
- Language features and libraries required for macro expansion may not be necessary at runtime
- Something like Common Lisp's eval-when or a compile-time-only include form is probably required for some advanced macros

### Optional compiler at runtime

- It must be possible to compile and load code at runtime
- Because it adds overhead, the compiler is available as a library
- This allows eval, a REPL, and the ability to interrogate compile-time metadata during development
- For development, a REPL harness can load code files so the developer can use the REPL without the code including it

### Macros are the killer feature

- Macros allow significant abstraction at compile time without requiring runtime overhead
- Reader macros allow sugar for common syntactic patterns

### TODO/undecided:

- Syntax for storage class specifiers
- Other metadata or compiler hints

## Design principles

- Simplicity of implementation is prioritized over design purity ("worse is better")
- Small core - it's better to have few builtins and more libraries
- Few special forms - it's especially better to have few builtins with special behavior
- Many macros - where ergonomics or expressiveness require special behavior, macros are the preferred implementation
- Macros vs functions - In Lisp, it is conventional to prefer functions over macros wherever possible. In Nucleus, runtime overhead is is equally important.
- LLVM native - Nucleus targets LLVM and relies on its infrastructure to simplify implementation when possible.
- C-compatible - Nucleus is a drop-in replacement for C with a superset of C's functionality. It must be able to use any C library's functions and data structures, but not its macros. Likewise, any functions and data structures from a Nucleus library must be consumable from C.

## Design documents

- [initial.md](initial.md) — the stage-0 target program and expected output
- [stage0-plan.md](stage0-plan.md) — implementation plan for the stage-0 compiler (C host, LLVM IR backend)
- [stage1-self-host.md](stage1-self-host.md) — implementation plan for self-hosting the compiler
- [syntax.md](syntax.md) — notes on syntax
- [stage2-features.md](stage2-features.md) - early features following successful self-hosting
- [stage3b-interop.md](stage3b-interop.md) — C interop: unsigned types, function pointers, C header parsing, `--emit-cheader`
- [stage3c.md](stage3c.md) — deferred C interop issues: unions, bit-fields, struct ABI, platform portability
- [stage6-cleanup.md](stage6-cleanup.md) — REPL, printing, macroexpand, n-ary arithmetic, modularization
- [stage6-plan.md](stage6-plan.md) — implementation plan for the non-blocked items in stage6-cleanup.md
- [stage6-floats.md](stage6-floats.md) — design for `f32` / `f64` types (deferred from stage 6)
- [stage6-redefinition.md](stage6-redefinition.md) — design for REPL function redefinition (deferred from stage 6)
- [stage9/polymorphism.md](stage9/polymorphism.md) — Stage 9 polymorphism: the dispatch engine. §§1–8 survey the options and the chosen hybrid (overloaded `defn` multimethods + protocols as a thin checked layer); §9 is the authoritative build spec with landed implementation status (rungs 1–4); §10 specifies the planned **engine extensions** — blanket protocols + `Any`, inferred structural bounds (`Valid`), and operators-as-ordinary-functions (`Num`/`Eq`/`Ord` + user operator overloading); design decisions resolved at the end
- [stage9/callable-values.md](stage9/callable-values.md) — Stage 9: what happens when a non-function is in the call position. **Landed** (impl-status section at end) — `(callee …)` desugars by argument type to `get` (symbol selector → member access, the struct default via the `Struct` blanket protocol, byte-identical to `.` and overridable) or `invoke` (general call; `Seq`/`Call` library protocols in `lib/seq.nuc`, e.g. integer → element). Field selectors are symbol *values* (literal → zero-overhead static GEP; computed → runtime field dispatch over homogeneous structs). Arbitrary-expression heads work and a fn-pointer head folds to `funcall`. Builds on the engine extensions in polymorphism.md §10
- [stage10/safety.md](stage10/safety.md) — Stage 10 umbrella: safety without breaking C compat or adding mandatory runtime cost. Resolved decisions (scope = lifecycle + nullability; non-null via opt-in `(ref T)` then flip; `unsafe` as a naming convention), shared invariants, and the L1→N1→L2→N2→L3 staging. Links the two workstream specs
- [stage10/lifecycle.md](stage10/lifecycle.md) — Stage 10: the `with` lifecycle. Escape/taint analysis in `node-type` (a `with`-owned pointer escaping via return or store-out is a compile-time error; deref/field copies are fine), a `Drop` protocol generalizing the libc-allocator special-case (+ `defer`), and `move` for ownership transfer (replacing the `(set! p null)` disarm) with a double-free check
- [stage10/nullability.md](stage10/nullability.md) — Stage 10: non-null `(ref T)` and nullable `(Maybe (ref T))` / `?T` (niche-encoded, C-ABI-identical to `T*`). Transition forms (`if-some`/`unwrap`/`unwrap-or`/`some`/`none`/`as-ref`), flow narrowing so existing `(when (= x null) …)` guards *are* the narrowing mechanism, and the opt-in-then-flip migration
- [progress.md](progress.md) — terse summary of done / pending / deferred work
- [stage6-rest-optional.md](stage6-rest-optional.md) — design for `&rest` / `&optional` parameters in `defn`
- [stage6-expressions.md](stage6-expressions.md) — design for expressions-as-values and implicit return
- [stage6-pointer-syntax.md](stage6-pointer-syntax.md) — replace `*T` pointer syntax with `(ptr T)` constructor
- [long-term-issues.md](long-term-issues.md) - potential problems for a mature implementation, deferred during early phases of development

## Agent feedback

Some design documents are structured as a conversation between a designer and a robot. Agents tasked with responding to a design document should add their feedback to the robot sections.

Agents encountering new design documents should add them to the above list.

## Pre-release

Nucleus is currently in pre-release development. Breaking changes are expected without warning.
