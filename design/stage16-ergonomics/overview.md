# Ergonomic enhancements

Every open item raised across this stage's documents — things still needing a
decision, things still needing work, and things deliberately left as-is — is
indexed in one place: [deferred.md](deferred.md). Check there before starting
new Stage 16 work rather than re-deriving "is this still open?" from scratch.

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

Its two recorded follow-ups are **closed 2026-08-29** ([keyword-markers.md](keyword-markers.md) §9-§10). The `has-rest`-by-count bug was not the stale flag §7 filed it as: `finalize-generics` binds the prescan's Type for a solitary name, so a call *above* an `:optional` defn took the `:rest` path, and three widening tiers gate on `(= (m has-rest) 0)`, so an overloaded `:optional` method never resolved. Fixing it exposed that `has-rest` was one of **three** fields on which the prescan's Type and `emit-defn`'s disagreed — `nopt`/`opt-defaults` were the others. And a never-instantiated parametric union's `:repr` turned out **not** to need the general "when is a template body checked" question opened: the mode is decidable with no stamp, so `register-union-template` runs the real `defunion-strip-repr` for its diagnostics — which also restores this item's own `&repr` retirement chokepoint, silently true only of *concrete* unions until now.

Two halves of the framing needed correcting first. **There is nothing in the reader to simplify** — `&` is already an ordinary symbol character (`is-sym-char` is a deny-list and 38 is not on it), there is no `&` prefix dispatch and no reader-macro entry, so each marker was a plain interned `NODE-SYM` matched positionally by a string compare. The change buys nothing there and everything in *conventions*: keywords already carry markers through `parse-decl-attrs` (`(defvar :const …)`, `(:volatile status:i32)`, `(ptr :volatile ui8)`), so the language had two spellings for one idea. And **`&` is not freed outright** — `.&` (field-address) is a live special form with ~200 uses, and `&` is illegal in any definition name regardless (`ir-name-illegal-char`). What is freed is `&` as a *prefix sigil*.

The mechanical part was smaller than "hundreds of sites" suggests: **fourteen recognition sites, seventeen comparisons**, collapsed into three helpers that take the marker's *bare* name (`"rest"`) — which is what stops the roster being re-spelled at each site, and removed every `"&rest"` string literal from the recognition path in one step. Nothing in the compiler *constructs* a marker, so conventions.md's `intern-symbol` sweep trap does not apply. Three sites needed thought rather than substitution: `macro-parse-params`' name-collection test is **negated** (it does not read like a detection site) and sits below a "param must be a symbol" check that rejects a keyword outright; `declare-param-type` sits directly above the arm that reads a keyword operand as a *type*, so without the marker check first `:rest` reports `unknown type: rest`; and `defunion-strip-repr` was the one site using `strcmp` rather than `=`.

**Two boot refreshes, not three.** `lib/macros.nuc`'s thirteen `&rest` headers are inside the compiler's own translation unit via the auto-prepended prelude, so a one-commit flip dies on the prelude before a single compiler form emits. Dual-accept + refresh, then sweep-and-retire together — the boot only has to *read* the new spelling, not still accept the old one. The retirement is a located hard error naming the replacement, placed at `desugar-params` rather than `emit-defn`'s own scan because desugar runs straight off the reader: a `&where` defn no longer registers as a template, so the prescan would otherwise die `unknown type: T` before the marker was ever seen. The other three marker-bearing shapes (`defmacro`, `extend`, `defunion` arm chains) are not desugared at all, so each needs its own chokepoint.

Two discoveries. **`&repr` had no test coverage at all** — documented in `docs/structs-unions.md`, used by nothing. And **`run_stdlib_table` had been dying silently**, hiding a real regression: `out="$(… --check)"` is the exact `set -e` trap its neighbour `run_headers_generated` documents at length, so the unit died before its FAIL line and only the exit code carried it — `make test` had been exiting 1 while showing zero FAILs. Behind it, the prelude split above had removed **165 libc functions** (`printf`, `malloc`, `exit`, `fopen`, …) from the no-import set while `docs/stdlib.md` went on claiming all 220. Both fixed. The general lesson: a harness that decides pass/fail by scanning output must *name* an empty result, or "N tests, zero FAIL" is only as good as the guarantee that every unit spoke.

760 tests (was 755), `make test` exits 0 for the first time, `make bootstrap` converges after each refresh, abi/layout/check-headers/avr green.

## The `&` type sigil, and the `&` address-of operator

The character the item above freed. Design: [ref-sigil.md](ref-sigil.md).
**Done** (2026-08-30) — `&T` is sugar for `ref:T` in every type position, with
`x:&(Vector T)` and `):&T` falling out of the existing colon-paren fuse for
free; and `&x` is sugar for `(addr-of x)` in every value position (§6), the
~854-site form that is the most verbose thing in ordinary Nucleus code.

The two meanings are split by position **within the token**: a `&` that begins
a token is the address-of reader macro (matched in `next-tok`, before
`lex-atom`), and a `&` inside one is the type sigil. Neither rule consults
context. They meet only at a standalone `&T` in a type slot, which the reader
has already written as `(addr-of T)` — so `parse-type-from-node` and
`node-is-ptr-wrapper` read that head as `ref`, which is the whole cost of
having both.

The decision that made it small is **where** it expands: in the lexer, at the
one point an atom's text is finalized, rather than in the type parser beside the
`?`/`!` prefixes. A type spelling is read by more than the type parser — `x:&T`
goes through `split-colon-segments`, and `(Vector &T)` is walked by
`collect-pattern-tyvars`, which collects any unresolvable symbol as a **tyvar**,
so a parser-side sigil would have registered `&T` as a type variable instead of
failing. Expanding to `ref:` before the parser exists hands every consumer the
canonical spelling, and the change touched no other pass.

Two atoms neither rule may claim, and neither does: `.&` (interior `&`, so the
sigil keys on segment-start position and the reader macro never sees it) and
the four retired `&x` markers — left unexpanded by the sigil, and skipped by
the reader macro via `at-legacy-marker`, so they still name their keyword
replacement rather than failing later as `unknown type: rest`. Their roster is
one function (`legacy-marker-tail`) both consult rather than a second copy.

Deliberately **not** adopted in `src/`/`lib/`: that needs `make
update-bootstrap` first, so leaving the sources alone keeps this a pure
addition and `make bootstrap` converges byte-identically with no boot refresh.

## Replace .set! with variadic set!

I'm split between a simple variadic set! with an extra quoted symbol or variable resolving to symbol for struct field assignment, or a more generic mechanism allowing its extension to arbitrary scenarios.

## `as` sugar

It would be nice if something like `(contains #{"foo" "bar"} (as CStr baz))` could be written as `(contains #{"foo" "bar"} baz:CStr)`. I don't want to make the reader work too hard though.

Evaluation: [as-sugar.md](as-sugar.md). **Done** (2026-08-23) — evaluated and
implemented in the same pass, exactly as the evaluation recommended: the atom
form only, at emit time, with the parenthesised form excluded and diagnosed.
**804 tests (was 799)**, `make bootstrap` byte-identical on the first try,
`examples/as-sugar.nuc` plus four rejection fixtures. Findings follow.

Two follow-ups landed during adoption, both recorded in as-sugar.md: a boot
refresh (§10 — a stale boot *reinterprets* the new spelling rather than
rejecting it, so it fails only where the difference is observable), and
**selector position** (§11 — a bare symbol in `(m k)` is classified as a field
name before it ever reaches `emit-symbol-ref`, so `(m k:CStr)` died with `no
field 'k:CStr'`; fixed in the shared `selector-literal-sym` classifier, on the
scope-free rule that a field name can never carry a colon).

**The reader needs no work at all** — and
the one spelling that would require some is exactly the one to leave out.
`baz:CStr` already lexes as a single symbol; `split-typed` cuts it downstream and
`emit-symbol-ref` **discards** the type half, so `baz:CStr` compiles today and
means `baz` — as does `baz:NoSuchType`, which is the same silently-unvalidated
colon spelling the W4b `defconst` sweep chased out of definition names. So the
slot is free, and the change is ~30 lines in two functions (`emit-symbol-ref` +
its `node-type-sym` lockstep partner), reusing `emit-as`'s conversion body lifted
into a shared `as-convert`.

**Where it goes decides whether seven passes break.** A tree rewrite (reader or
desugar) is the tempting shape and the wrong one: seven passes strip a
value-position annotation and key on the bare name — the `set!` target, closure
capture detection and rewrite, the Stage 10 non-null flow facts, const folding,
plus the two typing halves. Demonstrated: `(when (!= p:?ptr:N null) (p k))`
narrows today and `(when (!= (as ?ptr:N p) null) (p k))` does **not**. Emitting
the cast inside `emit-symbol-ref`, leaving the node a `NODE-SYM`, keeps all seven
working and keeps `set!`/`addr-of` on the lvalue reading for free.

**Exposure is 16 sites, measured** by instrumenting the compiler and running it
over `src/`, all 150 examples and `lib/`: every one a `for`/`dotimes` loop counter
(`i:i32`, `i:usize`) whose annotation names the variable's own type, so the cast
is identity and emits no IR. The adoptable set on the other side is **2411 of
3327** `(as …)` forms in `src/`+`lib/` (72 %) — bare-symbol operand, atom-spellable
type, led by `ptr` ×1055 and `ptr:ptr` ×323. `unsafe/cast` deliberately gets no
sugar: the short spelling should be the safe one.

**The real price is a third meaning for one atom.** `name:Type` is already a
declaration in binding position and a *type* in type position (`ptr:Node`); this
makes it a cast in value position, so `(let (a:i32 b:i32) …)` declares `a` and
casts `b`. Not ambiguous to the compiler — no position takes both a type and a
value — but the tree already has locals named `raw`, `ref` and `fn`
(`reader.nuc:948` `raw:ptr`, `generics.nuc:536` `raw:i32`, `nucleusc.nuc:2235`
`ref:CStr`), where one atom would carry all three readings. If that is too much,
`baz::CStr` reaches the identical code path with no extra reader work and keeps
the readings apart.

Parenthesised types (`q:(ref P)`) are the part to **exclude**: the colon-paren
fuse already claims them in every list context, so `(getp q:(ref P))` reads as a
*call* `(q (ref P))` and dies `unknown: ref`. The fuse cannot be made
value-aware — its output is indistinguishable from `(v i)` indexing and `(m 'k)`
lookup. `deftype` is the answer, as it was for
[container-type-sugar.md](container-type-sugar.md): an alias makes any type a
single token, and the atom sugar works on single tokens. Worth doing regardless:
that near-miss deserves a diagnostic naming the fix instead of `unknown: ref`.

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

Design: [repl-libraries.md](repl-libraries.md). **The item understates it, and
the understatement is the finding.** `import` does work; what does not work is
everything a library needs *after* the import. **Sixteen of the 34 modules in
`lib/` fail to import at all** — every collection, every string module, and the
prelude itself — and no generic function, no lambda and no collection literal
can be evaluated at the prompt at all, import or no import. The ones that load
are exactly the ones that name no prelude type.

Seven independent defects, all reproduced against `bin/nucleusc`. Three are the
same underlying mistake in different clothes: **a compiler global whose
invariant holds for one module and one process, reused by a driver that
assembles many modules and never exits.** `StructDef.emitted` means "written
once this process", so a type emitted into a REPL module that is then discarded
is marked done forever — `context/repl.md`'s "module-assembly invariant" section
is a hand-maintained workaround for exactly that, and it has *already* been
forgotten once (`lookup-or-make-anon-struct` bypasses the queue it assumes).
`drain-mono-worklist` has **one call site in the whole compiler**, at the tail of
`emit-toplevel-forms`, which a prompt entry never reaches — so every stamped
body, lambda lift and closure method is a call to a function that is never
emitted, while two *sibling* queues were REPL-adapted and this one silently was
not. And `die-at` longjmps out of `do-import` through every save/restore pair,
which is why the whole session afterwards reports `lib/iterator.nuc:1`.

Two things the transcript hides. The REPL's error-recovery block is **dead
code** — `repl_try` is called twice per form, so a throw resumes at the second
call and the arm at the first never runs; `tests/expected/repl-s16-macrolet.out`
has been documenting that silently by *lacking* a line. And a failed import
leaves `g-importing` dirty, so retrying the same import is a **silent no-op**,
which is what made the reported session look like it was making progress when it
was not.

The prelude is the root: the REPL never loads it, hand-mirroring `Node` and four
of the seven `NODE-*` ordinals instead (`NODE-CHAR` therefore types differently
at the prompt than in a batch compile) — and that hand mirror writes `%Node` into
the preamble without setting `emitted`, which is precisely what makes the real
prelude unloadable on top of it. So the diagnostic that says `import the prelude`
names a fix that cannot be applied. [../4a-repl-issues.md](../4a-repl-issues.md)
reports the same class against the first-pass REPL; the hand mirror is the patch
that closed *those* cases, and this is that decision's bill.

Also recorded, because both cost reading time and both are stated wrongly in the
tree: `<compile-time>` in a REPL IR error is the hardcoded MemoryBuffer name, not
the compile-time path (the module's own ID is `'<repl>'`), and the
prefix-qualified imports do not "fall to the compiler path" as
`src/repl.nuc:474-483` and `design/stage12/namespaces.md:202` both claim — there
is no compiler path from the prompt; they fall to the *expression* path and are
compiled as calls. The REPL being the dispatch site that gets forgotten is
already on record in this file, from the `deftype` work; this item is the
standing evidence for it.

One alternative was evaluated and deferred (§3.6): replacing `repl_try` with
Nucleus's own `!T` channel, which is the direction Stage 10 §7.2 already named
and which the reader half of the REPL loop already uses. It is gated on `!void`,
which does not exist — `try` propagates only inside an `!T` function, so one
converted `die-at` pulls its whole transitive call graph with it, and emit
functions overwhelmingly return `void`. R1 reshapes the shim instead. The prize
that would justify the full conversion is multi-error reporting (`die-at` calls
`exit(1)`, and `src/` has no error-count machinery, so the compiler reports one
error per run), not REPL tidiness.

**Done: R1 (2026-08-24), R2, R3, R4 and R5 (2026-08-25).**
Staged R1–R5, R1 (the unwind) first because every other fix is unobservable while
state corruption masks it. None of the eight REPL fixtures that existed when this
was filed imports a Nucleus library — `lib/` is tested only through batch
compiles, which always get the auto-prelude — which is why a total failure of the
REPL's library surface never showed up in `make test`.

R1 shipped the shim reshape (`repl_protect(body, ctx)`, plus a depth counter so
an unprotected `die-at` exits instead of jumping into a returned frame — both
properties carried across unchanged when the shim was rewritten in Nucleus on
2026-08-30, see c-header-layout.md §11), a
`ReplState` snapshot/restore spelling the roster once and truncating every
append-only registry to a per-form watermark, and the `g-prescan-sigs` ordering
fix. That last one could not be the literal "move the push" the plan called for:
the pre-order push is also the walk's cycle breaker, so the marker had to be
*split* into an in-flight list and a completed list. Byte-identical batch IR
across all 152 examples and `make bootstrap` converged with no boot refresh;
`tests/expected/repl-s16-macrolet.out` gained the `error (recovered)` line it
never had, and `tests/repl/import-error.in` is the new fixture — the first REPL
fixture that imports at all. See
[repl-libraries.md](repl-libraries.md) §3.4, "R1 as built".

R2 deleted the hand mirror outright: `repl-preload-prelude` feeds the reader
`"(import-use prelude)"` where its predecessor fed `"(import-use macros)"`, so
the REPL boots through the same import arm batch `main` splices, and the prelude
pulls in `lib/macros.nuc` itself. **The 34-module probe goes 18 clean → 33
clean**, one fresh session each; the survivor is `node`, already scoped out as a
JIT symbol-resolution item. All seven `NODE-*` ordinals now agree with a batch
compile — three of them previously had no binding at the prompt at all, so the
mirror was silently *wrong*, not merely short. Startup cost +22 ms (188 → 210).
One pre-existing defect surfaced and was filed rather than fixed (**D8**): a
declare latch scoped to a CT module's own buffers is blind to the REPL preamble,
so two imports in one session can collide on `declare ptr @alloc-node()`. See
[repl-libraries.md](repl-libraries.md) §3.1, "R2 as built".

R3 gave the REPL its own monomorphization drain. `drain-mono-worklist` has
exactly one call site in the compiler — the tail of `emit-toplevel-forms`, which
a prompt entry never reaches — so every stamped body, lifted lambda and closure
method was a call whose callee was never emitted. `repl-flush-mono` drains into a
module of its own, JITted untracked on the main dylib (a `defn`'s per-impl module
carries a resource tracker the next redefinition removes, which would silently
un-define unrelated stamps), and backfills one ABI-lowered `declare` per `define`
into the preamble afterwards, because `g-mono-drained` is a persistent cursor and
a body emitted for one entry is otherwise invisible to the next. **The reported
transcript now works end to end.** It also closed D8, the declare collision R2
surfaced, whose root cause is §3.3's principle one level down: a dedup list
scoped to the CT module's own buffers while the assembled module is *preamble +
ct-decl + ct-def*. A latch is a claim about a buffer, and is only correct if it
names the buffer it is about.
[repl-libraries.md](repl-libraries.md) §3.2, "R3 as built".

R4 retired the process-wide `StructDef.emitted` latch. A `StructDef` now records
*which buffer* holds its `%Name = type {…}` line — `emit-epoch` (the module,
bumped by `open-module-streams`), `in-type-buf`, `in-preamble` — and one
predicate, `sdef-in-module`, replaces every read that meant "already in this
module"; `emitted` keeps only the redefinition question it also answered. Making
the copy sites collapse into one rule took more than tidying them: a REPL module
used to be assembled as *preamble + its own type buffer*, which is exactly why
the preamble could only be appended to after the JIT and why each arm carried its
own `strdup`. **The preamble is now the type section of every module**, absorbed
at close by `repl-absorb-type-buf` — six ad-hoc copies became one rule, and
`context/repl.md`'s hand-maintained invariant became a description of a
mechanism. D6 is closed (a `?T`-returning `defn` then a `match` at the next entry
used to die `Cannot allocate unsized type`), and a capturing `vfn`/`mfn` at the
prompt works for the first time — its env struct's type line was going to the def
buffer while the `invoke` body it types was drained into a later module.
Byte-identical emitted IR for all 186 fixed inputs (152 examples + 34 `lib/`
modules) plus 96 header-mode outputs, `make bootstrap` at its fixed point,
808 PASS / 0 FAIL. Still open (**D9**): a type is recoverable across modules only
if it is queued or absorbed, and a `defstruct` inside a REPL `(compile-time …)`
is neither. See [repl-libraries.md](repl-libraries.md) §3.3, "R4 as built".

R5 closed the item. All six import spellings are top-level arms now — `import`,
`import-prefixed`, `import-ct` and `unsafe/import-private` used to fall to the
*expression* path and be compiled as a call whose head was `import`. The
objection the code recorded against doing this (that alias-injecting forms would
confuse a name-keyed declare backfill) was stale twice over: R3's backfill is
keyed on definitions, and **Stage 15 B2b had already deleted
`inject-import-aliases`**, so no spelling injects alias `Sym`s at all. Two
defects were hiding behind "compiled as a call" and only became reachable once
the forms reached their emitters — a private definition emitted `internal` is
invisible to every later REPL module, so `unsafe/import-private` could import a
symbol nobody could then call; and `do-import` asks `ct-sink-here` three times,
which in the REPL disagreed with itself, because an imported file at the prompt
runs at `g-toplevel-depth` 1 (the depth that means "unit root" everywhere else)
and re-sampled `g-real-reachable` from inside the file being sunk — filing a
compile-time-only import on the EMITTED list, so a later real import of it was
deduplicated away. Both are fixed and both fixes are inert in batch. The
diagnostics half: the seven `(import the prelude)` messages now route through
W1c's `unknown-type-message`, so they name the file that defines `Maybe`/
`Result`; every import at the prompt says `  imported <lib>` or
`  <lib> already imported`, answered by *measuring* the four registries an
import can grow rather than by re-deriving `do-import`'s dedup gates; and the
per-method conformance detail became `\n  note:` lines below its headline
instead of bare `fprintf`s above it. Batch output byte-identical for the same
186 inputs plus 96 header-mode outputs, `make bootstrap` at its fixed point,
809 PASS / 0 FAIL with a new `repl-import-forms` fixture. Two items are left
open deliberately: **D9** above, and the `(import-use node)` duplicate-symbol
item (§6 of the design), which is a JIT symbol-resolution question rather than
an import one. See [repl-libraries.md](repl-libraries.md) §3.5, "R5 as built".

**D9 is now closed too, in two steps.** D9 proper (2026-08-25) made the general
statement the epoch permits — *a type is recoverable across modules only if it is
queued or absorbed* — and ruled that a `defstruct` inside `(compile-time …)`
defines a **program** type, which fixed a batch defect that exited 0 on invalid
IR. It left the *name's visibility* open: the type was usable in a body but not
in a **signature**, because `prescan-struct-names` never descended into a
`compile-time` body. **D9a** (2026-08-29) closed that with a descent rather than
the "much wider blast radius" the note predicted — the body's `cdr` is already
the chain the walk consumes, so the two type prescans recurse into themselves
with an `in-ct` flag, filtered to `defstruct` by a predicate `emit-compile-time`
itself calls. The value prescans deliberately do not descend, because a CT
`defvar`/`defn` writes into the CT module alone. 908 PASS / 0 FAIL, 187+96
outputs byte-identical, boot refreshed and the new fixed point confirmed. See
[repl-libraries.md](repl-libraries.md) §3.3, "D9 as built" and "D9a as built".

**The last item §6 filed as out of scope is closed too (2026-08-29), and its
diagnosis was wrong** — see
[repl-jit-symbol-precedence.md](repl-jit-symbol-precedence.md). `(import-use
node)` did not fail because `-rdynamic` makes ORC prefer the host's copies:
LLJIT already links its own `<Process Symbols>` JITDylib **last in the default
link order**, so a module's own definitions win, and five probes against the real
LLVM 19 C API pin every step. The compiler was attaching a *second, redundant*
process generator to the **main** JITDylib — and a definition generator does not
merely resolve a name, it **defines** it where it is attached. So the first macro
module that referenced `alloc-node` claimed that name in main permanently, and
every later module defining it was a redefinition. The fix is the deletion of
those two calls. `-rdynamic` is untouched and stays load-bearing
([compile-time-imports.md](compile-time-imports.md) §9), measured both ways.
All **34** `lib/` modules now import in a fresh session, where R2 recorded 33 of
34. The `LLVMOrcSymbolPredicate` filter the item's first candidate would have
needed does exist and is consulted per lookup — it simply was not necessary.

It exposes one residual, pinned rather than papered over by
`tests/repl/host-runtime.in`: after `(import-use node)` the session defines its
own `intern-symbol`, so a macro **first expanded after** the import mints its
symbols from a second intern table, and `emit-node` dispatches special forms by
**pointer** identity — `(mc 9)` answers `unknown: cond`. It is loud, confined to
special-form heads (a function head resolves by spelling), and absent for a macro
already expanded before the import, since ORC materialisation is lazy and
one-shot. Its root cause is symbol *identity*, not symbol *precedence*, and §5 of
the new document names three routes with a recommendation. 913 PASS / 0 FAIL,
187+96 outputs byte-identical, boot refreshed and the new fixed point confirmed.

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

## Same kind is not same type (the template-ref equality hole)

The hole the item above deferred: `(ref (Vector i32))` binds to a
`(ref (Vector i64))` slot, passes as that parameter, and stores into that field,
with no error anywhere.

Design: [template-ref-equality.md](template-ref-equality.md). **Done** (2026-08-29).

It is **D3's chokepoint**, one arm lower. `coerce-int-val`'s `(when (= sk dk)
(return v))` is where FP-1 inserted the function-pointer answer, and its own
sentence — "two function pointers are the same KIND and are not thereby the same
type" — is true with *pointer* substituted throughout. `fn-slot-type-compat` was
never fn-specific (it recurses through pointers and ends at `type-eq`), so the
rule is that function renamed `slot-type-compat` and *called* at the line FP-1
wrote around. Two corrections to the shared-cause story: there is a **third**
site, `defvar-addr-of-ir`, the constant renderer — conventions.md's second
typed-slot path, on its sixth bite — and the pointer kinds were the only *silent*
ones, since a struct, array or union mismatch was already caught by the LLVM
verifier, at a line in a file the user did not write.

**The rule was the easy half.** Measured blast radius, by installing the
predicate as a report-and-accept probe and compiling the tree: **61 sites — 60 in
`src/`, 0 in `lib/`, 1 in `examples/`**. The one in `examples/` was a real
mistake the laxness hid (a lambda declared `:ptr:(ptr i32)` returning a
`(ptr i32)`). All 60 in `src/` are one call, `vector-new-in`, and one *second*
defect: a generic whose type variable appears only in its **return type** is
memoized and mangled on its parameter types alone, so the compiler contained
exactly one `vector-new-in` — stamped `(Vector i32)` by whichever site got there
first — and the other 59 silently took it. `type-eq`'s key stopped being a key.
It was benign only by layout accident (`(Vector T)` has no `T`-typed field); the
by-value sibling `vector-new-capacity` reserves `n × sizeof T` from the wrong `T`
and is caught only by LLVM.

Two smaller findings fell out of fixing that. **A computation with no reader is
not "advisory", it is unverified**: the full A1 determination fixpoint was
computed at template registration and never read, while the question's one
consumer used a params-only approximation of it — which, the moment a symbol
depended on the answer, called `reduce`'s constraint-recovered `S` return-only
and renamed every `reduce` stamp in the corpus. And `pattern-determines-tyvar`,
which documents itself as mirroring `unify-tpat`, was the one of the three copies
of the §3.7 alias expansion that did not expand parametric type aliases.

912 tests (was 908), boot refreshed, **185 of 187 modules byte-identical** in the
IR sweep — the two that move are `.$r.<ret>` renames of return-only-tyvar
constructor stamps and nothing else — and all 374 header-mode outputs unchanged.

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

**Part 1 done (2026-08-22)**, `db895b2` — the type divorce
([bool-type-plan.md](bool-type-plan.md)). **Part 2 done (2026-08-29)** — nil
punning, the narrowing arm, and the non-null diagnostic
([bool-truthiness.md](bool-truthiness.md) §"As built"). One shared rule,
`condition-bool`, replaces the six sites' five inline `(!= kind TY-BOOL)` tests;
`raw`/`CStr`/`?T` lower to `icmp ne ptr … null`, a value-`Maybe` to a tag
compare, a non-null `ptr` and a `!T` each to their own diagnostic, everything
else to "condition must be bool, not `<type>`". 888 tests (was 883), bootstrap
converges with **no** boot refresh (nothing in `src/` uses the sugar yet). The
plan's one wrong prediction: `test-false-nonnull` needs **no** mirror arm — a
bare symbol being *false* proves the binding null, and the inverted guard
`(when (not m) …)` narrows through the existing `not` delegation instead.
Deliberately still refused: "all numbers are true" and zero-is-false (both by
the design's own ruling), and `TY-FN` in condition position (not on the list,
and `is-ptr-like` excludes it by design).

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

## Any libc detail must be reachable from pure Nucleus

Nucleus is a drop-in replacement for C, so it must be usable anywhere C is
usable — which means any required libc detail (a layout, a size, a calling
convention, an attribute a call depends on) has to be obtainable from a pure
Nucleus program. The REPL's `src/repl_shim.c` existed partly because it was not:
its own header comment said *"jmp_buf is an opaque, platform-specific type that
Nucleus cannot express directly."* Cost constraint: it may add size to the
compiler, but must add none to compiled programs that do not use it.

Design: [c-header-layout.md](c-header-layout.md). **Done (2026-08-26)** — all
five staged items (L1–L5) landed, in the staged order (L1 → L2 → L3 → L5 →
L4). `setjmp` is the symptom; the defect is general to C header import, and
the survey is the argument.

**The motivating instance was then collected (2026-08-30).** `src/repl_shim.c`
is deleted — the last C source file in the tree — and the compiler is pure
Nucleus: `repl-protect`/`repl-throw` on `_setjmp`/`longjmp` through the header,
and `repl-print-f64`/`repl-print-f32` calling a JIT'd `(fn f64)()` thunk directly
now that FP-2 gave the indirect call the direct call's ABI rules. Neither
`Makefile` nor `build.ps1` compiles C any more. c-header-layout.md §11.

**The cost story is already paid.** Two programs, one with `(import-use
"setjmp.h")` and one without, link to **15848 bytes, byte-identical**. LLVM type
definitions are compile-time only, and unused imported functions are already
reclaimed at the link by Stage 16's own section stripping. Nothing below has to
invent a cost story, only preserve one. (The comparison needs both files to share
a *basename* — the binary embeds it, and the resulting one-byte diff reads as a
cost difference and is not one.)

**The defect is that a struct member the C parser cannot represent becomes `ptr`,
silently.** `%__jmp_buf_tag = type { ptr, i32, ptr }` — 24 bytes where C says 200,
no error, no warning, and `(alloca __jmp_buf_tag 1)` handed to `setjmp` smashes
the stack. Isolated to four lines of C: a **direct** array member (`long a[8]`)
abandons the struct and fails *safe* as a located opaque-type error, while the
same array **behind a typedef** resolves to nothing, becomes `ptr`, and fails
silently. glibc hides both of `jmp_buf`'s large members behind typedefs.

**The rule is already written in the tree, at `src/cheader.nuc:583-585`** — *"a
typedef the parser cannot follow must be an error or a skip, never a silent
`ptr`"* — and `c-parse-type` already raises `cheader-mark-unrep` on all five
shapes that matter. It has two consumers, the function-declaration boundary and
the typedef recorder, and **neither is a struct member**. The second of those is a
literal working template for the save/clear/check/restore the fix needs.

**The survey, which is the strongest part of the argument.** Across 15 headers,
65 comparable struct types, **18 wrong-size rows / 16 distinct types** — `jmp_buf`
24/200, `siginfo_t` 24/128, `in6_addr` 8/16, `itimerspec` 16/32, `__fpos_t`
24/16, and so on. Classifying 34 named libc types: 12 OK, 4 silently WRONG, 14
OPAQUE (refused with a located error), 4 ABSENT. And a census of 232 struct
bodies over 30 headers finds **163 (70 %) carry a shape the body parser cannot
read** — 132 of them nothing worse than an array member with a literal extent.
The honest reading, against the framing that filed this: most of that 70 % fails
*safe*; the silent class is the narrower, sharper set where an unparseable body is
reached *indirectly*, through a typedef or an opaque tag. Both are worth fixing
and they are the same fix.

**Three findings the framing did not contain.** `struct timespec` — two scalar
fields — is unusable because `clang -E` puts a `#` **linemarker inside the
body** and `c-skip-ws` skips whitespace only; that blocks `stat` and `itimerspec`
too, so it has to land before the array work or the array work delivers none of
them. `struct epoll_event` is 16/12 because Nucleus ignores
`__attribute__((packed))` — same silent-wrong *class*, different mechanism, out of
scope. And `struct __attribute__((__may_alias__)) sockaddr` registers a phantom
opaque type literally named `__attribute__`.

**Staging L1 → L2 → L3 → L4, with the cost of L1 landing alone stated rather than
hidden.** L1 (an unresolvable member makes the struct opaque) is pure safety and
independent; it also removes five wrong `stdio.h` type lines from **163 of the
186 sweep modules** and leaves `setjmp`/`siglongjmp` undeclared-with-a-reason
until L3. Its warning volume is **zero new loud warnings** — `c-decl-skip-reason`
returns the unrepresentable reason first, and every arm that raises it is on
W3c's quiet, reported-at-the-point-of-use tier.

**The IR-neutrality sweep is the wrong gate here, twice over.** It is *blind*: the
whole tree imports six C headers, exposing 14 of the 65 surveyed struct types, so
a change that broke `signal.h`, `pthread.h` or `netinet/in.h` outright would sweep
clean. And it is *not neutral*: 163 of 186 modules change. So the bar becomes a
**characterized diff** — every hunk must be a `%X = type` line for a named type
(or an `__anon_struct_hXXXX` rename following from one, since anonymous C structs
are memoized by content hash), with the 96 header-mode outputs still
byte-identical. Same shape as the D9 case above, where the blind spot was a
*stream*; here it is *coverage*.

**On integrating C typedefs with `deftype`: separate registries, shared lookup
path.** The brief's hypothesis — that a C array typedef "has no Nucleus
representation" only because the eager path needs a `Type*` and there was no
array type — is **right, and it is what makes the array work cheap**. It is not
the whole story: the C table has no `Node` to be lazy with (the parser works over
a text buffer, not an AST), its order semantics are deliberately the *opposite*
of `deftype`'s and are what make a cycle impossible by construction, and its
redefinition and export policies are opposite too. Against the "one answer to
what a name means" argument: `parse-type-name` already consults five sources in
sequence, so a sixth probe is the established pattern, not a new cost. What the
question does uncover is a real gap — a C **struct** name is a Nucleus type name
(`ptr:FILE` works), a C **scalar typedef** is not: `x:off_t` is `unknown type`,
because `g-cheader-typedefs` has exactly one reader, inside the C parser. So
`(defn seek (fd:i32 off:off_t):off_t …)` cannot be written, which is a direct hit
on the goal. L5 — written up as a recommendation, **now approved** — is a sixth
probe in `parse-type-name` placed
*after* the alias probe, a `type-name-collision` arm so `(deftype off_t …)` is
refused rather than dead, a distinct message for the table's recorded-but-
unrepresentable entries, and — the one place a lazy body would genuinely have
been easier — the new probe consulting `g-array-ok` itself, because a `Type` that
arrives already parsed is exactly what `reject-array-type` exists to backstop.

**As built.** 834 tests (was 813), `make bootstrap` converges, abi/layout/
check-headers (69/69) green. Two corrections surfaced during implementation
and are recorded in place in [c-header-layout.md](c-header-layout.md) rather
than silently folded in: the L3 aggregate-array-typedef fix needs **two**
sites moved together (the alias registered in `c-parse-struct-decl`, but the
`%X = type {…}` line is actually written later by `struct-upgrade-aliases`,
keyed on that alias — editing only the first site is a no-op); and L5's
"consult `g-array-ok` itself" was not implementable as written, because
`parse-type-from-node` reads-and-clears the permission *before* delegating a
bare name to `parse-type-name` — fixed by classifying each delegation as a
nesting (consume) or a same-type reference (inherit), which also closed a
pre-existing, pre-L5 bug (`(deftype Buf (array i32 4))` + `(defvar env:Buf)`
was refused). A third bug was found and fixed along the way, not anticipated
by the design: `ReplState` snapshotting `cheader-skipped` but not
`g-cheader-typedefs` was reasoned about as a write-safety question and is
actually a read hazard — a rolled-back REPL form could leave a typedef entry
pointing at a StructDef the rollback had just removed, reproduced as `IR
parse error: base element of getelementptr must be sized`. And **L4 is not
"inert for every other header"** as staged: the compiler's own `unistd.h`
import puts `vfork` on the `returns_twice` by-name list, so L4 changed the
compiler's own IR and needed the same `make update-bootstrap` refresh L1 and
L2 did — the one item in the sequence for which "L3, L4 and L5 converge with
no refresh" turned out false.

The worked example is [examples/setjmp-guard.nuc](../../examples/setjmp-guard.nuc)
(§7), now a running test (`tests/expected/setjmp-guard.out`): `(defvar
env:jmp_buf)` is 200 bytes of storage, `_setjmp`/`_longjmp` decay to a single
pointer word with `returns_twice` on the declaration, and a `:volatile`
counter survives the jump. Three details are glibc's, not the compiler's, and
are written down in [docs/structs-unions.md](../../docs/structs-unions.md)
now that this lands: `setjmp`/`sigsetjmp` are unconditional macros to
`_setjmp`/`__sigsetjmp` on glibc, so a Nucleus `(setjmp env)` reaches a
different, signal-mask-saving function than C source `setjmp(e)` does — spell
`_setjmp` for C's behaviour; and `longjmp` already gets `noreturn` from the
same by-name list.

**Follow-ups, deferred and recorded in [c-header-layout.md](c-header-layout.md)
§6**, none of which regress anything L1–L5 touched: an inline function-pointer
struct member still abandons the struct (blocks `sigaction`/`sigevent_t` —
*closed later as FP-4*); a *with-body* aggregate array typedef
(`typedef struct T {…} Name[N];`) still discards its extent (zero occurrences
surveyed — *closed 2026-08-29 as CD-3, with the multi-declarator field line and
the typedef declarator list, in [c-header-layout.md](c-header-layout.md) §8*);
`__attribute__((packed))` is still ignored (`epoll_event` 16 vs 12, silently —
*closed later as PK-1…PK-3*); `--emit-cheader` renders
a C typedef bare, with no `#include` of the header it came from (*closed
2026-08-29 — the header did not compile at all without it, which the recorded
counter-argument had not measured; [c-header-layout.md](c-header-layout.md)
§9.2*); and
`Sym.returns-twice` is write-only by design (no Nucleus-side consumer, unlike
`noreturn`) — *still true of the READER, but it gained a third writer on
2026-08-29 when `returns_twice` became user-declarable on a `defn`;
[c-header-layout.md](c-header-layout.md) §10*. The survey's own oracle needed a correction too: a `sizeof`-only
comparison missed that `SDL_HapticConstant` matched on size (40 bytes, both
sides) while every field after the first was at the wrong offset and the
struct's alignment was wrong — offsets and alignment are the right oracle,
and the shipped gates (`run_l2_layout_matrix`, `make layout-test`) compare
them, not just size.

**Whether to finish those follow-ups by hand or switch to libclang was then
evaluated on its own:**
[cheader-parser-vs-libclang.md](cheader-parser-vs-libclang.md). **Finish the
parser.** The §1.5 census that motivated the question is stale — it measured
70 % of struct bodies blocked *before* L1–L5. Re-measured today across 32
headers: **102 of 111** named bodies lay out, **101 of 103** emitted C types
match clang's `sizeof` exactly (the one mismatch is `epoll_event`/packed), and
the nine blocked types reduce to four shapes plus one type-system item. Four of
the nine fall to a **single ~15-line repair** — the inline function-pointer
branch already exists at `src/cheader.nuc:1398-1405` and already collapses the
field to `ptr`; it just drops the field *name*, because it skips `(*name)`
wholesale instead of reading through it.

A libclang-shaped API was probed end to end from Nucleus (by-value `CXCursor`
arguments, by-value `CXString` return, a Nucleus function used as a C callback
taking two by-value structs) and **works** — the ABI is not the obstacle. The
economics are: the dependency is smaller than it looks (`bin/nucleusc` already
links `libLLVM.so.19.1`, 129 MB, and already shells out to `clang`; libclang is
+38 MB), performance is a wash (the hand-rolled parse is free to measurement —
the whole 103 ms header-import delta is the `clang -E` subprocess already paid,
and `-fsyntax-only` costs ~2 % more than `-E`), and it is **not** a line-count
win (only 1,314 of `cheader.nuc`'s 3,085 lines are the reader; the rest is the
`--emit-cheader` writer, which libclang does not touch). Of the three genuinely
hard remaining items, libclang pays for exactly one: `__attribute__((packed))`.
Bitfields and C11 anonymous members are hard because *Nucleus cannot express
them*, and a better front end answers a question the language cannot yet ask.
**All three landed without one, 2026-08-28** (c-boundary-defects.md §14–§16);
Nucleus expresses both now, and the census is 111/111.

Two defects the original survey could not see turned up while probing: **a bare
`unsigned` or `signed` is not a type** (`unsigned x;` abandons the struct,
`unsigned f(void);` is dropped — `unsigned int` is fine), which is zero
occurrences in pedantically-written glibc headers and pervasive in third-party
ones, including libclang's own `clang-c/Index.h`; and **that path records no
skip reason**, so the use site says the bare `unknown: … not defined anywhere`
rather than W3c's `… its C header declaration was skipped (<reason>)`. Staged as
C1 (the ~50-line tranche), C2 (record a reason on every skip path), C3 (packed,
its own item since it reaches `defstruct`), C4 (pass `--target`/`-isysroot` into
the `clang -E` line at `src/cheader.nuc:977`, which today reads *host* headers
when cross-compiling — a prerequisite for the AVR/RISC-V tracks under either
front end). The document also states the triggers that would flip the answer.

**C4 landed 2026-08-29** ([cheader-parser-vs-libclang.md](cheader-parser-vs-libclang.md)
§9). The retrofit §4.3 priced as one of libclang's three outright wins came to
one `snprintf` argument — but the item was two things, and the second is one no
front end supplies: `clang -E` does not fold `sizeof`, so the array-extent
evaluator computes sizes itself and had to be made target-correct alongside
(`int` is 16 bits on AVR, `long` is 4, `size_t` is pointer-sized). Measured on
AVR: `declare i64 @strlen(ptr)` → `declare i16 @strlen(ptr)`, and 59 glibc
declarations → 42 avr-libc ones. The host path is untouched by construction (the
flags are empty unless the target triple differs from the host's) and measured
byte-identical over 187 modules. A target whose headers are not installed falls
back to the host's **with a warning** rather than refusing, since refusing would
retire every cross lane in the suite; a header on no search path at all is now a
located error instead of a silent empty import.

### The §4 frictions, re-read as language defects

Design: [c-boundary-defects.md](c-boundary-defects.md). The three "frictions"
`cheader-parser-vs-libclang.md` §4.1 attributes to a libclang binding are not
costs of that binding — two of them are defects in Nucleus that every C library
with a callback or a by-value struct hits. Measuring them turned up **two live
silent miscompiles** §4 could not see, because the binding it built used
`unsafe/cast` and `unsafe/funcall-ptr-*` throughout and so never exercised the
typed path.

**Function-pointer types are erased at every C boundary, in both directions.**
The importer collapses them to `ptr` in all four declarator positions (parameter
`src/cheader.nuc:787`, member `:1404`, typedef `:1654`, and the
function-returning-function-pointer shape not modelled at all), so `qsort`,
`atexit` and every callback API needs `(unsafe/cast ptr f)`; `--emit-cheader`
collapses them to `void*` (`src/type-utils.nuc:404`), which is not standard C
(ISO C does not define function-pointer↔`void *` conversion). **The type system
is not the gap** — the identical declaration written by hand as
`(declare qsort2 (… (cmp (fn i32) (ptr ptr))) :void)` type-checks and emits
correctly.

**And the type it hands back means nothing.** `safe-coerce-val` short-circuits
on `sk == dk` (`src/nucleusc.nuc:3605`) before any signature comparison, so every
typed fn-pointer slot — `let`, `set!`, `.set!`, argument — accepts any function
(`fn-sig-eq` exists, computes the right answer at the call site, and is
discarded); and `emit-funcall-value` (`:6145`) never consults the parameter list
after the arity check, so an indirect call performs **no** coercion, no
diagnostic, no vararg promotion and no ABI lowering. Demonstrated: the same
function called directly and through a pointer prints `907` and `7`; an
`(fn i32)()` slot fed an `():f64` function prints `-1780842467`. One call site
already routes around this by hand (`src/union-emit.nuc:689`). This is why the
ordering is forced — fixing the importer first would trade a compile error for
silent stack corruption in exactly the case that motivated it.

**A struct value is not a member-access receiver** (`(. v x)` on a by-value
parameter or a call result), which is friction 2 and is not C-specific.
Staged FP-1…FP-5 (enforce signatures → lower indirect calls → render fn types in
diagnostics, the importer, and the generated header) then SV-1/SV-2 (struct-value
receivers, and the docs that teach a longer idiom than the language requires),
with C1/C2 riding along in `cheader.nuc`.

**The same document then closes the four deferred C-parity items** — the missing
float types, `packed`, bitfields, and C11 anonymous members — on the standard
that Nucleus should express anything C can. Two were smaller than their
deferrals imply. **Wide floats are not blocked on the bootstrap**: LLVM already
carries `half`/`x86_fp80`/`fp128` and their ABIs (measured, all three targets),
and although a decimal literal is rejected at those widths, f64→f80 and f64→f128
are *exact* widenings, so the constant renderer is integer bit-shuffling on the
f64 pattern — the compiler never needs f80 arithmetic to compile an f80 program
(FL-1…FL-7; `long double` is `x86_fp80` on x86-64 but `fp128` on aarch64/riscv64,
so the Nucleus types are the representations and the C name maps per target).
**C11 anonymous members are mostly already built**: clang's model is an ordinary
nested member reached by a two-level GEP, and Nucleus's anon-struct/union
memoizer (`union-registry.nuc:63`/`:107`) — which the C parser already calls —
supplies exactly that, so the sibling document's "Nucleus has nothing to lower
that onto" is stale; only name lookup through the member is missing (AN-1/AN-2).
Bitfields are the real work (BF-1…BF-4), and they share one prerequisite with
anonymous members: both break "one Nucleus field = one LLVM member at the same
index", fixed once by a resolved field reference (FR-1) carrying a GEP path plus
an optional bit range. `packed` is the cheapest (PK-1…PK-3) and its non-obvious
half is that `emit-load`/`emit-store` derive `align` from the type, so a packed
field needs `align 1` or the IR carries a false promise. **All four landed
(2026-08-26/28.)** The shared FR-1 prerequisite was the load-bearing call: it
converged byte-identically on its own, and it is why anonymous members came in
under their "medium" price while bitfields came in over theirs — see
c-boundary-defects.md §15 and §16.

Two limits are named rather than planned around. **Decimal literals at f80/f128
stay f64-rounded** — staged separately as
[future/decimal-float-literals.md](../future/decimal-float-literals.md)
(DL-1…DL-4: a correctly-rounded decimal→binary converter routed through
`float-literal-ir-at`, which also retires `f32-const-ir`'s existing
decimal→f64→f32 double-rounding). Nothing is blocked on it and it has no
ordering constraint in either direction; it is separate because a *nearly*
correctly-rounded converter is indistinguishable from a correct one until it is
not. **`_Complex` is out of scope** — a distinct type constructor with its own
ABI class and Annex G arithmetic, much easier to add after FL-1 than with it.

**The gate is the differential layout test, widened to every target.**
`tests/run-layout-test.sh` diffs `sizeof` and every field offset against the
platform `cc`, but it *runs* both binaries, so it validates the host only —
and bitfield and packing rules are target-parameterised. The fix is
`clang --target=<triple> -ffreestanding -fsyntax-only` over generated
`_Static_assert`s: a complete compile-time layout oracle on every target clang
supports, with no execution, sysroot, linking or libclang. Verified on x86_64,
aarch64, riscv64 and avr — and it earns its place immediately, since
`struct BF { int a:3; unsigned b:5; short c:9; int d; }` is 8 bytes on x86-64
and is not on AVR (16-bit `int`), where `int c:24` is a hard error rather than a
different layout. Acceptance is the 32-header census going 102/111 → 111/111.

**Status: the whole plan landed.** Phases 1–4 (D1–D7) and the float phase (D8)
2026-08-26; packing (D10, PK-1/PK-2/PK-3), bitfields (D9, FR-1 + BF-1…BF-4),
anonymous members (D11, AN-1/AN-2) and the flexible array member (C1a)
2026-08-28. **The census closed at 111/111**, with every one of the nine
formerly-blocked types sizing exactly as `cc` sizes it. `c-boundary-defects.md`
§12, §13, §14, §15 and §16 record what each item turned out to be.

The two corrections worth carrying forward from the last two phases. **AN was
cheaper than priced and BF was dearer, for the same reason:** the "language
question" AN was priced for — lowering a name that reaches through a member —
is FR-1, which bitfields needed anyway, so AN came to two functions on top of a
prerequisite already paid for. Bitfields cost what they cost not because the
type was hard but because C leaves allocation implementation-defined and AVR,
aarch64 and the SysV targets genuinely disagree; only the cross-target oracle
found that. And **`(array T 0)` could not represent a flexible array member** —
zero is already the layout prescan's provisional-length marker — so C1a spells
one `(array T -1)`.

Three plan corrections came out of the float work: FL-3's hex
literals needed a real 128-bit significand rather than a lexer arm (through
`strtod`'s f64 the hex spelling would have been no more precise than decimal at
f80/f128, which is its entire purpose); naming `f80` off x86 became a diagnostic
rather than a documented caveat, since it was emitting `x86_fp80` no other
backend can select; and **FL-7 does not unblock `max_align_t`** — clang's
definition is held up by a member `__attribute__((__aligned__(…)))`, so it comes
off the blocked list with PK-3, and the census figure moves with it.

Two more came out of packing. **One of the three C attribute positions has to be
ignored**: `typedef struct { … } S __attribute__((packed));` is warned-and-
discarded by both clang and gcc, so honouring it would disagree with every C
compiler on the platform. And **the cross-target oracle paid for itself on its
first run, but not on the predicted defect** — it found that AVR's
`BIGGEST_ALIGNMENT` is 8 bits, so every type there is byte-aligned and Nucleus
had been oversizing plain structs on that target since long before packing
existed. A host-only layout test structurally cannot see that.

And one from `aligned(N)`. The plan called it "not in the type" and therefore
cheap; re-measured against a *definition* rather than a declaration, **clang does
put it in the type** — `%struct.A = type { i32, [12 x i8] }` — and has to, since
LLVM computes array strides and GEP offsets from the element list alone. So PK-3
is a padding machine with a source-index → element-index remap, not a flag, and
that is what carried it past `max_align_t` to a member `aligned(N)` that actually
displaces a field. The oracle then caught the AVR half of the same mistake: an
`aligned(N)` raises an alignment past `BIGGEST_ALIGNMENT` there too, so PK-1's
AVR short-circuit had to move below the aggregate arms.

And three from bitfields, all of the same kind and all found by the oracle
rather than by reading a spec: **AVR drops C's declared-type rule entirely**
(GCC's `PCC_BITFIELD_TYPE_MATTERS` is off there, so bit-fields pack straight
across byte boundaries and only a zero-width member still forces a byte);
**`packed` drops the crossing rule but not the zero-width one** (a `:0` still
forces bit 32 in a packed struct); and **aarch64 gives every bit-field its
declared type's alignment, named or unnamed, and keeps a zero-width one's even
under `packed`**, where the SysV targets give an unnamed bit-field none. The
first implementation was green on eight shapes and wrong on all three rules;
shapes I, J and K in `s16-bf-layout-cross-target` exist to tell them apart.

### Does this change the libclang answer?

No — see [cheader-parser-vs-libclang.md](cheader-parser-vs-libclang.md) §8, the
re-price its own §7 called for. Deciding to implement bitfields and anonymous
members was that document's second stated trigger, so the question was reopened
properly. **The answer holds and one of its arguments had to be withdrawn to say
so honestly**: §5.2's claim that these items are hard "because Nucleus has no way
to express them" is stale for anonymous members, which are nine-tenths built
already. What decides it is a count — **four of roughly fifteen items in §§6–9
are parser work**, and libclang replaces those four and none of the other eleven.
The reason is structural: `defstruct` must be able to *declare* a bitfield and a
packed struct and `--emit-cheader` must *write* both back out, so the layout
algorithms must live in `abi.nuc` whichever front end reads the headers. That
takes `packed` — the one row §2 conceded to libclang outright — down with it.
libclang's real remaining advantage, correct bitfield offsets on every target, is
better bought as the cross-target *test* oracle above than as a linked
dependency.
