# Ergonomic enhancements

## macrolet

`let`, but for macros, similar to Common Lisp. A macro with variable capture is a reliable way to turn any repeated pattern into an abstraction, but it's messy to combine variable capture with global scope.

It may be necessary to implement part of this in the prelude, or use a compile-time guard to ensure that `Node` in available.

A pre-existing issue this raises is the current inability to define macros without pulling `Node` and friends into built artifacts and runtime memory. It would be valuable to have a compile-time-only import when developing for constrained targets like AVR.

Design: [macrolet.md](macrolet.md). No prelude work and no `Node` guard turned out to be needed — a `macrolet` body has exactly `defmacro`'s compile-time requirements, and the compiler's own `alloc-node`/`make-cell`/`intern-symbol` (not the program's) are what a JIT'd macro body calls.

**The `Node`-in-the-artifact half was a separate, larger item and the premise needed correcting** — see [compile-time-imports.md](compile-time-imports.md). **Done**, in the recommended order: split the prelude, then generalize with `import-ct`, then reclaim the remainder at the link.

Measured first: a program with a `defmacro` and one without emitted the *same* sixteen node/arena/intern functions (17 `define`s, 1119 vs 1118 IR lines), because `lib/prelude.nuc` imported `lib/node.nuc` unconditionally. Defining a macro cost nothing extra; every program already paid. A trivial `main` is now **1 define / 169 lines / 1343 bytes of `.text`** (was 17 / 1119 / 4569), with no node or arena symbol linked.

**The prelude split** leaves only forms that emit no IR (the `Node`/`StrView` types, `NodeKind`, the macros, `Clone`, `Result`, `Maybe`); the runtime is `(import-use node)` like any other library. Demand is *diagnosed*, not auto-imported — `quote needs the node runtime — add (import-use node)` — which matches how `[…]`/`{…}`/`:kw` already behave and is the same check `import-ct` then needed for its own promise. Two emission sites, not one: `emit-quote-tree` and the `&rest` call site, which builds `@make-cell` cells nowhere near a quote. Blast radius was 7 of 150 examples. It also exposed a second, undeclared leak: `lib/arena.nuc` imports `stdio.h`/`stdlib.h`, so the prelude had been handing every program `printf` and `malloc` — nineteen examples and fixtures were relying on it without saying so.

**`(import-ct lib)`** registers a library's compile-time surface and emits none of its definitions, so `lib/error.nuc`'s `with-handler` can call `node-at` in its JIT'd body without every error-handling program carrying the node runtime. Implemented by redirecting the *definition* stream and letting the emitter run unchanged (a register-only walk is precisely the mirror-the-emitter pre-pass conventions.md warns about twice) — and only that stream, because every "already declared" latch becomes a lie the moment emission is redirected. The rule that took the most iterations: **compile-time-only is a property of the unit, not of one import edge.** A library asking for a compile-time surface must never take the runtime away from a program that imports the same library for real, in either order or through nesting; the whole-graph prescan already walks every import form except `import-ct`, so what it visited *is* "reachable for real".

**`-ffunction-sections`/`--gc-sections`** — the option that looked like a two-line `build.sh` change — turned out to be neither in `build.sh` nor a flag. `nucleusc` emits the object file itself, so a codegen flag on the *link* driver is a no-op, and neither the LLVM C API nor a registered `cl::opt` exposes `TargetOptions::FunctionSections` (measured: `LLVMParseCommandLineOptions` accepts `-function-sections` without complaint *and* changes nothing — a clean parse says nothing about whether an option exists). The section names are spelled in the IR instead, one per definition, with `-Wl,--gc-sections` on the link line; ELF only, since a Mach-O specifier is `SEGMENT,section` and COFF collects with `/OPT:REF`. The rule that had to be measured rather than assumed: **`.bss` versus `.data` is decided by the section NAME, not the initializer** — a zero global named `.data.x` is PROGBITS and newly costs file bytes, and a non-zero one named `.bss.x` is a hard LLVM error (which is what makes claiming `.bss` safe to do at all, and why it is claimed only for an initializer the compiler itself rendered as the type's zero).

**The headline consequence:** `examples/avr-blink.nuc` with its `(exclude-prelude)` line removed now links for the ATtiny1634 — 882 bytes of text against 858 with it, and 626 against 604 once the sections land, with the 126 bytes of `.data` gone entirely. "No macros at all, or no AVR" is no longer the choice. Hosted binaries shrink 9–27 % (`list` 3784 → 2852 bytes of text+rodata+data, `hello` 467 → 329). The one thing that gets *worse* is the compiler's own binary, by 0.46 % of `.text`: `-rdynamic` makes every symbol a GC root, so nothing is collectable and only the alignment padding remains — adding `--gc-sections` to its own link changes literally nothing, measured.

## Replace special symbols with keywords

Special symbols like `&rest` and `&where` are squatting on the valuable & character. They were added before keywords; using keywords for the same role would free up &, and might even simplify the reader.

Flipping the switch will touch hundreds of sites in the compiler and libraries, but it's a mechanical search and replace a simple script can perform.

Design: [keyword-markers.md](keyword-markers.md). **Done** — all four markers, not the two named: `&optional` and `&repr` were also live, and leaving either would have kept `&` reserved, which is the motive.

Two halves of the framing needed correcting first. **There is nothing in the reader to simplify** — `&` is already an ordinary symbol character (`is-sym-char` is a deny-list and 38 is not on it), there is no `&` prefix dispatch and no reader-macro entry, so each marker was a plain interned `NODE-SYM` matched positionally by a string compare. The change buys nothing there and everything in *conventions*: keywords already carry markers through `parse-decl-attrs` (`(defvar :const …)`, `(:volatile status:i32)`, `(ptr :volatile ui8)`), so the language had two spellings for one idea. And **`&` is not freed outright** — `.&` (field-address) is a live special form with ~200 uses, and `&` is illegal in any definition name regardless (`ir-name-illegal-char`). What is freed is `&` as a *prefix sigil*.

The mechanical part was smaller than "hundreds of sites" suggests: **fourteen recognition sites, seventeen comparisons**, collapsed into three helpers that take the marker's *bare* name (`"rest"`) — which is what stops the roster being re-spelled at each site, and removed every `"&rest"` string literal from the recognition path in one step. Nothing in the compiler *constructs* a marker, so conventions.md's `intern-symbol` sweep trap does not apply. Three sites needed thought rather than substitution: `macro-parse-params`' name-collection test is **negated** (it does not read like a detection site) and sits below a "param must be a symbol" check that rejects a keyword outright; `declare-param-type` sits directly above the arm that reads a keyword operand as a *type*, so without the marker check first `:rest` reports `unknown type: rest`; and `defunion-strip-repr` was the one site using `strcmp` rather than `=`.

**Two boot refreshes, not three.** `lib/macros.nuc`'s thirteen `&rest` headers are inside the compiler's own translation unit via the auto-prepended prelude, so a one-commit flip dies on the prelude before a single compiler form emits. Dual-accept + refresh, then sweep-and-retire together — the boot only has to *read* the new spelling, not still accept the old one. The retirement is a located hard error naming the replacement, placed at `desugar-params` rather than `emit-defn`'s own scan because desugar runs straight off the reader: a `&where` defn no longer registers as a template, so the prescan would otherwise die `unknown type: T` before the marker was ever seen. The other three marker-bearing shapes (`defmacro`, `extend`, `defunion` arm chains) are not desugared at all, so each needs its own chokepoint.

Two discoveries. **`&repr` had no test coverage at all** — documented in `docs/structs-unions.md`, used by nothing. And **`run_stdlib_table` had been dying silently**, hiding a real regression: `out="$(… --check)"` is the exact `set -e` trap its neighbour `run_headers_generated` documents at length, so the unit died before its FAIL line and only the exit code carried it — `make test` had been exiting 1 while showing zero FAILs. Behind it, the prelude split above had removed **165 libc functions** (`printf`, `malloc`, `exit`, `fopen`, …) from the no-import set while `docs/stdlib.md` went on claiming all 220. Both fixed. The general lesson: a harness that decides pass/fail by scanning output must *name* an empty result, or "N tests, zero FAIL" is only as good as the guarantee that every unit spoke.

760 tests (was 755), `make test` exits 0 for the first time, `make bootstrap` converges after each refresh, abi/layout/check-headers/avr green.

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

## Collection literals should accept variables, not just literals

`[a b c]` and `#{a b c}` refuse any element that is not a scalar literal, so a
set of `defenum` members cannot be written as one.

Design: [collection-literal-variables.md](collection-literal-variables.md).
**Done** — elements may now be any typed expression, and the item closed a
soundness bug on the way.

The restriction is a phase artifact, not a semantic rule: the readers rewrite
`[1 2 3]` into an already-typed `(let (g:(ref (Vector i32)) …) …)` at read time,
so the element type must be derivable from a token's node *kind* — and
`read-program` completes before any binding is registered, so for a local the
answer does not exist at any price. Nothing downstream objects: the identical
expansion with an enum member and a local spliced in compiles and runs today.
The fix is to defer the literal to a marker form the type pass can see, with the
element type coming from the want channel when one is armed and from the
elements otherwise (literals adapt to the value-tier elements; two values of
different types are an error).

**Target-first turned out to be a correctness fix, not just ergonomics.** Before
this item `(with ((v (ref (Vector i64))) [1 2 3]) (invoke v 0))` printed
`8589934593` — `0x2_00000001`, two `i32`s read back as one `i64` — because the
declared type was ignored and the reader's guess won. It prints `1` now, and no
stray `Vector.i32` is stamped. The *underlying* hole is general to stamped
template instances (a `(ref (Vector i32))` binds to a `(ref (Vector i64))` slot
and passes as that parameter with no error anywhere), unrelated to literals, and
deferred to its own document.

The implementation inverted the design's hardest question. It assumed the three
new heads would need real `node-type` arms and that the difficulty was keeping
stamping out of them; in fact **`node-type` must return null**, because Rung 3
*overwrites* emit's type rather than asserting against it, and E depends on a
want channel already consumed by the time Rung 3 runs. An arm that recomputed
would silently retype the value. Two other things the plan missed: the gensym has
to stay minted in the *reader* or every `%__gs_N` in the IR renames, and a want
must not excuse a mixed literal — the element scan runs in both paths, checking
elements against each other while a declared type names the element type.

Also worth recording: **a literal in expression position is a per-call
construction** — `hashset_init` plus one `conj` per element, buckets leaked — so
the motivating site (`binding-usable-spelling`) should still not adopt one. That
condition was a tautology and was deleted instead.

773 tests (was 760), byte-identical IR across all 30 literal-using examples and
fixtures, `make bootstrap` converges.

## Broad auto-cast to bool

It's a convenience in some languages, including lisps that most values can be used as booleans. Right now, Nucleus just uses i1 - neither broad acceptance nor a dedicated boolean type.

The `bool` type can be `true` or `false`. Internally, those can be 1 and 0, but there could be some ergonomic benefit to treating numbers as truthy like most lisps.
