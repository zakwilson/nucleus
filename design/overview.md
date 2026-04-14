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

## Design documents

- [initial.md](initial.md) — the stage-0 target program and expected output
- [stage0-plan.md](stage0-plan.md) — implementation plan for the stage-0 compiler (C host, LLVM IR backend)
- [stage1-self-host.md](stage1-self-host.md) — implementation plan for self-hosting the compiler
- [syntax.md](syntax.md) — notes on syntax
- [stage2-features.md](stage2-features.md) - early features following successful self-hosting
- [long-term-issues.md](long-term-issues.md) - potential problems for a mature implementation, deferred during early phases of development

## Agent feedback

Some design documents are structured as a conversation between a designer and a robot. Agents tasked with responding to a design document should add their feedback to the robot sections.
