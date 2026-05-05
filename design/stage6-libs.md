# Library dependency issues

#### Designer

## Adding to the base language

I'm trying to make variadic math macros the default. It appears that requires a way to add a function, macro, struct, etc... to the base language without making it a special form (`emit-something`) which is currently absent.

## Library imports

While working on a stopgap solution, I found that hello.nuc cannot `(import macros)` because `Node` is not defined. macros.nuc cannot `(import node)` because `arena-alloc` is not defined. node.nuc cannot `(import arena)` because `g-arena` is not defined. A program other than the compiler seems unable to use any of these libraries.

These libraries either need to be self-contained (without significant repeated code), or they need a way to access symbols defined in the compiler.

## Acceptance criteria

Both of the following should be true:

* hello.nuc (and all other programs) should get access to the variadic math macros without an import.
* Libraries like node.nuc and macros.nuc should be importable from any program
* Libraries that have little or no use outside the compiler should be moved from lib to src

#### Robot

## Current state (uncommitted work-in-progress)

Reviewing the working tree before planning:

- `lib/varmath.nuc` deleted; its macros (`+ - * /`) folded into `lib/macros.nuc` (so `macros.nuc` now requires `Node` to import).
- `src/nucleusc.nuc` `init-binops` no longer registers `+ - * /` as binary builtins. Instead it registers two parallel sets of aliases: `__+ __- __* __/` (the previous escape hatch) **and** `_+ _- _* _/`. The float dispatcher accepts `+ -* /` and `_+ _- _* _/` but **not** `__+ ...` for floats — looks like an in-progress rename that's only half done.
- `lib/node.nuc` switched `(+ k 1)` → `(_+ k 1)` to survive the loss of builtin `+`.
- The compiler still calls `+ - * /` in dozens of places (it imports `macros` itself), so the bootstrap currently relies on the stage-1 binary having builtin `+` and the stage-2+ binary getting `+` via the auto-imported macro.

Before implementation can start, the designer needs to resolve the questions below.

## Blockers / questions

### Q1. What is the canonical name for the binary primitive?

`init-binops` currently registers both `__+` and `_+`. `lib/macros.nuc` uses `__+`; `lib/node.nuc` uses `_+`. Pick one and delete the other. (My read: `__+` was the earlier convention and the rename to `_+` is half-finished. The float-binop dispatcher only handles `_+ _- _* _/`, so completing the rename to `_+` is the path of least resistance — but `__` is the more common "private/internal" convention in lisps. Designer call.)

### Q2. How should the variadic math macros become available without an import?

Three options I see, each with tradeoffs:

a. **Auto-prepend a preamble to every compilation.** The compiler implicitly imports a fixed library (say `lib/prelude.nuc`) before the user's first form. Mirrors what the REPL already does ("standard macros are auto-imported at REPL startup"). Cheap to implement; matches REPL behavior; but means *every* program pays the parse/expand cost and can't opt out.

b. **Hard-code the macros in `src/nucleusc.nuc` as defmacro forms emitted into the macro table at startup,** the way `init-binops` populates binops. Same effect as (a) but the macro source lives in the compiler, not in `lib/`. Worse for editing/iterating on the macros.

c. **Promote `+ - * /` back to special forms in the compiler** that internally do the variadic right-fold. Fastest at compile time, no macro layer. But it removes them as a useful demonstration of macro power, and reintroduces "to extend the base language you must edit the compiler" — which is exactly what the design doc complains about.

My recommendation is (a). Confirm before I implement.

### Q3. How to break the `macros → node → arena → compiler-globals` import cycle?

The cycle is real and has three independent links:

1. **`macros.nuc` → `Node`.** `dotimes`, `->`, and the new variadic math macros all introspect `(. (cast (ptr Node) ...) car/cdr/kind)`. To make `macros` importable by any program, either:
   - **(i)** the `Node` struct is built into the compiler (declared automatically, like `int`/`ptr`), or
   - **(ii)** `macros.nuc` is split: a "simple" half (`if`/`when`/`unless`/`zero?`/`null?`/`for`) that has no Node dependency, and a "node-aware" half (`dotimes`/`->`/variadic math) that explicitly imports node. Programs that don't need the node-aware macros only import the simple half.
   - **(iii)** the macros are rewritten to use opaque accessor builtins (`car`/`cdr`/`kind`) that the compiler provides, with no struct visibility required.

2. **`node.nuc` → `arena-alloc`.** `make-cell` and friends call `arena-alloc`. For a user program that wants `node` utilities, either it must also `(import arena)` (and inherit the compiler-global dependency), or `node.nuc` must accept an allocator function pointer, or the compiler must provide a default arena.

3. **`arena.nuc` → `g-arena`/`g-arena-used`/`g-arena-cap`/`ARENA-SIZE` globals.** These are declared in the compiler. To make `arena` standalone the file must declare them itself — but then importing `arena` from both the compiler and a user program produces duplicate definitions.

The simplest cut that satisfies the acceptance criteria: option **1(i) + 2 (compiler provides default arena) + 3 (move globals into `arena.nuc`, remove duplicates from compiler).** This makes `Node` a built-in type and `arena` a self-contained library with its own globals; `macros` then imports `node` which imports `arena`, and the chain works for any program. But "make Node built-in" is a real design commitment — it permanently bakes the AST shape into the compiler.

Alternative: pursue **1(iii)** (opaque accessors) so user programs never see `Node` at all. Larger change to the compiler, but cleaner long-term.

Designer call needed.

### Q4. Which libraries move from `lib/` to `src/`?

Candidates I see by inspection (need designer confirmation):

- `lib/reader.nuc`, `lib/format.nuc`, `lib/llvm.nuch` — strongly tied to compiler internals; move to `src/`.
- `lib/arena.nuc`, `lib/node.nuc` — used by the compiler but also clearly useful to user programs (any AST-manipulating tool). Acceptance criterion #2 says "importable from any program," so keep in `lib/` and fix the cycle per Q3.
- `lib/macros.nuc`, `lib/mathlib.nuc`, `lib/list.nuc`, `lib/testmacros.nuc` — general-purpose, stay in `lib/`.

### Q5. Does the compiler still self-host after the changes?

The compiler source uses `+ - * /` extensively. After the change it will get them via the auto-prepended preamble (Q2). The bootstrap step that uses the *previous* compiler binary to compile the *new* source must therefore have a preamble-aware previous compiler, or the new source must remain compatible with the old binary. Need to confirm the bootstrap chain (per `context/build.md`) tolerates the transition — likely a one-shot stage where the new source still uses `__+`/`_+` while the auto-preamble lands, then a second commit that switches the compiler source to `+`/`-`/`*`/`/`.

---

I can implement once Q1, Q2, Q3, and Q4 have answers. Q5 is a sequencing question that will fall out of the others.

#### Designer

Q1: A single underscore is the preferred form

Q2: Auto-prepend a prelude. Create an `exclude-prelude` special form to prevent it. It's acceptable to require that it be the first form in a file if that provides technical advantages.

Q3: It's fine to add the `Node` struct to the compiler. A default arena is also fine with lazy initialization; in practice I expect most programs will only use it at compile time for macro expansion.

Q4: Just format.nuc and llvm.nuch for now.
