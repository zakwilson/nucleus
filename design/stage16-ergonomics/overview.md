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

## Potential `as` sugar

It would be nice if something like `(contains #{"foo" "bar"} (as CStr baz))` could be written as `(contains #{"foo" "bar"} baz:CStr)`. I don't want to make the reader work too hard though.

## Container type sugar

`(ref (HashMap CStr i32))` is ugly

## `import` doesn't seem to work in the REPL

## Container type literals should take more element types

Container literals can only contain int, float, or string. They should at least be able to take keyword and symbol.

Design: [container-literal-elements.md](container-literal-elements.md). **Done** — all of it, though keyword and symbol turned out to be two items rather than one.

**Keyword** was a reader-only change of about five lines: `Keyword` already conforms to `Hash`/`Eq`, so the expansion the reader generates already compiled. Its one wrinkle is that `Keyword` lives in `lib/keyword.nuc`, making it the first bracket literal whose element type the collection import does not reach — `#{:a :b}` needs `(import-use keyword)`, and the missing-import note names the file.

**Symbol** took the "make `Node` respectable as a value" path, chosen because the compiler itself deals in symbols and further string→symbol refactoring is planned. Three of the four recorded blockers proved softer than the measurement implied: `=` already worked and only `hash` was missing (and needs no `extend` — that takes a struct template, but a bare overload on `(ref (ref Node))` resolves); nullability was a *typing* artifact, since `'foo` lowers to `intern-symbol`, whose signature already returns `ref:Node`; and the spelling constraint was reader-only. So `quoted-datum-type` now types a quoted **symbol** `(ref Node)` while leaving `'(a b)`/`'()` raw — a node-type↔emit-node lockstep pair, both sites calling one rule — and `#{'a 'b}` / `['a 'b]` / `{'k 1}` infer `(ref Node)` via a **shape** check for `(quote <symbol>)`, so `'(a b)`, `'1` and a bare `a` stay refused. That forced `infer-lit-type` to return a *kind* and `lit-kind-type` to become `lit-type-node`, returning a fresh type **node**, since `(ref Node)` is compound. Symbol keys need no import at all — `Node` is in the prelude.

**Deferred by decision:** in head position a selector resolves as a field name and the quote is silently stripped, so `(m 'count)` reads a field rather than looking up a symbol; lookup must be spelled `(invoke m 'k)`. Field access is due a larger rethink, and the constraint to carry into it is that an explicitly quoted symbol should be a value, never a selector.

On the framing: the earlier "semantic fork" objection — that `'foo` would have to mean a `Node` in macro position and a `Symbol` in literal position — was retired by checking Common Lisp, Scheme and Clojure, which all make a symbol an ordinary first-class value meaning the same thing everywhere; even Scheme's syntax objects bridge by explicit `syntax->datum`/`datum->syntax` rather than by context. The real question was whether the macro layer should traffic in `Node`, the *compiler's* structure, at all — all three answer no — and the deciding cost is the `Node`/arena dependency, which is [compile-time-imports.md](compile-time-imports.md)'s subject.

Also fixed in the same pass: `#{1.0 2.0}` was *already* broken — `f64` had no `Hash` conformance, so floats were one kind too generous for sets and maps. `f64`/`f32` now hash their bit pattern (there is no bitcast operator; the bits come back through the `(ref Self)` receiver), with `-0.0` normalised to `+0.0` so it stays findable.
