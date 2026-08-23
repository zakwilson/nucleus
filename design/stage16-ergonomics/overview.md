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

Evaluation: [container-type-sugar.md](container-type-sugar.md). **The proposed
spelling buys zero characters** — `ref:(HashMap CStr i32)` is 22 characters and
already works in every type position (the Stage 14 CP-1 chain fuse, never
applied to collections in the docs or in any source file); `ref:HashMap:(CStr
i32)` is also 22 and would cost the reader a pointer-kind special case to keep
`p:ptr:(fn i32)` wrapping. The paren-free `ref:HashMap:CStr:i32` (20) works too,
but only while every type argument is a single token.

**Two characters is not why nobody adopted it.** The sugar appears in no real
source file, while the list form it replaces appears 55× as `(ref (Vector T))`,
43× as `(ref (HashSet T))`, 36× as `(ref (HashMap K V))`. The type expression
itself is the cost, not its punctuation — so the recommendation is **type
aliases** (`(deftype SymTab (ref (HashMap CStr i32)))` → `m:SymTab`), the one
option that removes the expression from the use sites rather than compressing
it, and the one that adds no reader rule at all. There is no way to name a type
in Nucleus today: no `deftype`, nothing alias-like in `src/`, `docs/`, or
`design/`. Transparent, not nominal — same stamped type, same mangled name, one
overload — which is what keeps `type-spelling` untaught and the bootstrap
byte-identical until a file actually adopts one.

**Aliases and the colon sugar compose, and that combination is the real
answer.** A single-token type name already works through the plain colon sugar
in every declaration position — `defvar` name, field, param, return, `let`,
`with`, chain tail — with nothing new to implement, so
`(defvar g-special-form-set:NameSet …)` needs only the alias. On that binding
the sugar alone saves 5%, the alias alone 32%, the two together 37%. It also
explains why the sugar was never adopted: it is at its best exactly when the
type is one token, and the tree has almost no single-token collection types to
use it on. Aliases create them — and in doing so make arity-driven chains
(which only compress *multi-token* expressions) largely pointless.

**Done** (2026-08-22) — all four steps: `deftype`/`deftype-`, the silent
mis-parse fixed, the compiler's own sources adopted, and parametric aliases.
**799 tests (was 778)**, bootstrap byte-identical, `examples/type-aliases.nuc`.
CT-A (arity-driven flat chains) is **dropped**: it compresses only multi-token
type expressions, which is exactly what the other three remove.

Phase 1 gave `deftype`/`deftype-`, transparent, with forward references,
alias-of-alias, `.nuch` export and `deftype-` privacy.
Three corrections came out of building it. `guard-name-kind` **cannot** carry
collisions the way the design assumed — it skips every row reporting the kind
being defined, and struct/template/enum/alias all report `NK-TYPE`, so
type-over-type is invisible to it by construction; since aliases are probed
last, a colliding alias is *dead*, not merely ambiguous, so `deftype` needed its
own `type-name-collision` check running on both the prescan and emit passes to
catch a clashing type declared either above or below it. And "the `.nuch`
carries definer forms verbatim" was wrong: **both** `.nuch` sides are explicit
form lists, so an unlisted form is silently dropped — the header emitted a
`declare` naming a `Count` it did not carry. The same shape then bit twice more,
in `--emit-cheader` (which resolved type names by spelling, so an alias leaked
out as `struct Count`, a header that does not compile) and in the REPL's own
form chain. **A new top-level form has six dispatch sites here** — prescan, emit,
`.nuch` export, `.nuch` import, C header, REPL — plus the special-form set and
`text-token-is-definer`; only the first two follow from the feature's
description.

Probing for the filed spelling also **turned up a silent mis-parse** to fix
first, independent of the option chosen: `x:ref:Vector:ref:Node` puts `ref` and
`Node` in template-argument position, where `collect-pattern-tyvars` collects
any unresolvable symbol as a tyvar (bare `ptr` *is* resolvable, which is why
`ref:Vector:ptr:i8` gets an honest arity error and this does not). The `defn` is
classified as an unmonomorphized template, `emit-defn` skips its define, and
nothing is reported — the call site fails with `no matching method for
overloaded 'f'` about a function that was dropped from the module. **Fixed**:
a pointer kind in type-argument position is refused by name (only `ref` can get
there — bare `ptr`/`raw` are types, which is the whole asymmetry), and any type
*pattern* whose argument count misses the template's arity now gets the arity
error the concrete path already gave. `docs/types.md` gained the working
container-chain spellings and the rule that a type argument may not itself be a
chain.

**Adoption** took the compiler's own three sites — `NameSet`, `ConstraintVec`,
`ImportVec` — each verified byte-identical against a pre-adoption
`build/nucleusc.ll`. Two lessons. Adopting a *new* form in `src/` needs
`make update-bootstrap` **first**, because `boot/nucleusc.ll` is the compiler
that builds `src/`; that is the two-commit dance the repo history already shows.
And the §3.10 guidance ("kind inside the alias when it is stable, outside when
the type is genuinely held both ways") decided all three by itself: `NameSet` is
only ever a `ref`, while the other two are `raw` on a field and `ref` once a site
has proved non-null — a difference the Stage 10 pointer-kind discipline exists
to keep visible, so it stayed at the use site. Two high-count spellings were
deliberately left alone: `(ref (Vector ptr))` is what Stage 14's type-safety work
retypes site by site, so an alias would obstruct it.

**Parametric aliases** (`(deftype (Vec T) (ref (Vector T)))`) close it out. They
substitute the argument *nodes* rather than `StructTemplate`'s spellings,
because in a method receiver an argument may still be a free tyvar with no
`Type*` to spell. The receiver case is the one the design flagged, and its
diagnosis was half right: an unexpanded `(Vec T)` matches no template and no
pointer wrapper, so `collect-pattern-tyvars` walks straight past it and `T` is
never collected — the opposite mechanism from the predicted "alias name
collected as a tyvar", same consequence. The trap worth carrying forward is that
`MAX-TYPE-ALIAS-DEPTH` in the parse path did **not** protect the pattern path,
and `(deftype (A T) (A T))` hung the compiler until that descent got its own
guard: a depth counter is a property of each recursion site, not of the concept.

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

It's a convenience in some languages, including lisps that most values can be used as booleans. Right now, Nucleus just uses i1 - neither broad acceptance nor a dedicated boolean type. I would like to add a dedicated `bool` type to represent truth, and automatic casts when something wants `bool` even though that's obviously lossy.

The `bool` type can be `true` or `false`. Internally, those can be 1 and 0, but there could be some ergonomic benefit to treating all numbers as truthy like most lisps. That probably means all primitive values are true, but raw pointers and references to `null` or `none` are false.

Evaluation: [bool-truthiness.md](bool-truthiness.md). **Split the item and drop
one half.** The dedicated type is worth doing and smaller than it looks (under 70
`:i1` sites; `bool` is *already* a spelling for `ty-i1` and already dispatches, so
the change is a divorce from the integers, not a new type — and it deletes the
`{0,1}` range rule rather than adding one). Note that "all numbers are true"
*requires* it: `false` would otherwise be a number, hence true.

But that number rule is the half to drop. In a static language every conditional
it newly admits is one whose answer is already known — `(when n:i32 …)` is a
constant, and so is `(when p:ptr:Node …)` since Stage 10 made `ptr` non-null — so
it shortens **zero** lines of working code while silently inverting `(when
(str-empty? s) …)`, `(when (char-is-digit c) …)` and every C `int` predicate,
which return `i32` (confirmed by running them). It is also the exact blind spot
`conventions.md` records from W9 item 31, where a wrong `i1` survived every
bootstrap because its only consumers were truthiness tests. And it is the only
option that cannot be revised: it gives `(when n:i32 …)` the opposite of the
meaning anyone would later want, where the alternatives leave it an error.

What survives is **nil punning** — `raw`/`CStr`/`?T`/`Maybe`, 1,135 null-test
sites in `src/` — and it belongs at the six condition sites (`cond`, `while`,
`not`, `_and`/`_or` ×2), *not* in the coercion set as the item words it: a lossy
implicit coercion contradicts types.md's "exactly `as`'s safe set" invariant and
would make a `bool` parameter a universal overload candidate, against the
already-decided rule that dispatch is stricter than assignment. The one cost the
framing misses is that `test-true-nonnull` matches node *shapes*, so a bare
symbol needs its own arm or `(when m (m kind))` typechecks the test and then
fails on the body. Zero-is-false is the larger prize (a further 522 sites, and it
matches this codebase's `(!= flag 0)` idiom — C semantics fit here where Lisp's
do not) and stays available later.

Fixed out of that evaluation, on its own and ahead of any `bool` work:
[varargs-promotion.md](varargs-promotion.md). Arguments past a variadic callee's
fixed prefix took no default argument promotions, so `(printf "%d %f" n:i16
x:f32)` passed `i16`/`float` where C passes `i32`/`double` — `-300` printed as
`-1940914476` and `2.5` as `0.000000`. Nothing to do with `bool`; `bool` was
simply next in line. The fix is keyed on argument **position**, not on a
source/target type pair, which is why it sits at the argument walk beside the
StrView vararg rule rather than in `coerce-int-val` — it delegates the widening
back to that chokepoint so `zext`-vs-`sext` stays decided once. 10 of 149
examples changed IR, **0 changed output** (all ten were `bool` under `%d`, the
case that was already right by luck). 777 tests, bootstrap converges.

## `case` taking a list

`lisp (case foo :bar 1 (:baz :qux) 2 3)` - expands to individual comparisons at compile time
