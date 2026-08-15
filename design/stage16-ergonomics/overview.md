# Ergonomic enhancements

## macrolet

`let`, but for macros, similar to Common Lisp. A macro with variable capture is a reliable way to turn any repeated pattern into an abstraction, but it's messy to combine variable capture with global scope.

It may be necessary to implement part of this in the prelude, or use a compile-time guard to ensure that `Node` in available.

A pre-existing issue this raises is the current inability to define macros without pulling `Node` and friends into built artifacts and runtime memory. It would be valuable to have a compile-time-only import when developing for constrained targets like AVR.

Design: [macrolet.md](macrolet.md). No prelude work and no `Node` guard turned out to be needed — a `macrolet` body has exactly `defmacro`'s compile-time requirements, and the compiler's own `alloc-node`/`make-cell`/`intern-symbol` (not the program's) are what a JIT'd macro body calls.

**The `Node`-in-the-artifact half is a separate, larger item and the premise needed correcting** — see [compile-time-imports.md](compile-time-imports.md). Measured: a program with a `defmacro` and one without emit the *same* sixteen node/arena/intern functions (17 `define`s, 1119 vs 1118 IR lines), because `lib/prelude.nuc` imports `lib/node.nuc` unconditionally. Defining a macro costs nothing extra; every program already pays. Recommendation there is to split the prelude first (types and `lib/macros.nuc` emit no IR; only `node`/`arena` do), then generalize with an `import-ct` form.

## Replace special symbols with keywords

Special symbols like `&rest` and `&where` are squatting on the valuable & character. They were added before keywords; using keywords for the same role would free up &, and might even simplify the reader.

Flipping the switch will touch hundreds of sites in the compiler and libraries, but it's a mechanical search and replace a simple script can perform.

## Replace .set! with variadic set!

I'm split between a simple variadic set! with an extra quoted symbol or variable resolving to symbol for struct field assignment, or a more generic mechanism allowing its extension to arbitrary scenarios.
