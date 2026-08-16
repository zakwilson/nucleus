# Compile-time-only imports

Stage 16. Status: **done** (2026-08-16) — (b) split the prelude, then (a)
`import-ct`, then (d) per-definition sections + `--gc-sections`. 755 tests (was
752 after (a), 743 after (b), 736 before). Bootstrap converges.

Raised in [overview.md](overview.md) alongside `macrolet` as "the current
inability to define macros without pulling `Node` and friends into built
artifacts and runtime memory".

## 1. The premise needed correcting

Defining a macro is not what pulled `Node` in. **Every** program pulled it in.

Measured with the stage-15 compiler (`bin/nucleusc`, x86_64), two programs that
differ only by a `defmacro`:

```nucleus
; with-macro.nuc                     ; no-macro.nuc
(defmacro twice (x) `(_+ ~x ~x))
(defn main ():i32                    (defn main ():i32
  (let (a:i32 21) (return (twice a))))  (let (a:i32 21) (return (_+ a a))))
```

| | `define`s emitted | IR lines |
|---|---|---|
| with the macro | 17 | 1119 |
| without the macro | 17 | 1118 |
| **either, after (b)** | **1** | **169** |

Both emitted the same sixteen library functions:

```
arena-init  arena-grow  arena-alloc  arena-strndup  arena-strdup
alloc-node  make-cell   intern-hash  intern-raw-insert  intern-grow
intern-symbol  node-at  node-len  node-line  node-is-list  node-kind
```

They survived linking (`nm` on the linked binary still showed `alloc-node`,
`make-cell`, `intern-symbol`, `arena-alloc` as `W`) — nothing is
garbage-collected, because the emitted linkage is `weak_odr` and the link line
uses neither `-ffunction-sections` nor `--gc-sections`. A trivial `main` cost
4569 bytes of `.text`; it now costs **1343**, with no node/arena symbol linked.

The cause was `lib/prelude.nuc`'s unconditional `(import-use node)`, not
`defmacro`.

## 2. What compile time actually needs

A macro body compiled by `emit-defmacro` becomes its own JIT module. That module
carries `declare`s for `@alloc-node`, `@make-cell`, `@intern-symbol` and
resolves them **against the compiler process** through the ORC dylib generator —
which is exactly why the main module's globals are deliberately kept out of it
(src/nucleusc.nuc, the `defvar` arm's comment: "CT and macro JIT modules pull in
`g-decl-bufp` but not `g-def-bufp` … otherwise prelude globals (from node /
arena / intern table) would duplicate across modules").

So the program's own copies of `alloc-node`/`make-cell`/`intern-symbol` are
**never used at compile time**. They are needed at run time only by a program
that evaluates `'sym` or a quasiquote in emitted code — `emit-quote` lowers
those to calls.

That is the whole shape of the problem: the prelude bundled a compile-time-only
capability (the `Node` type, `lib/macros.nuc`, the constructors JIT'd macro
bodies call *in the compiler*) with a runtime one (the arena, the intern table,
the constructors emitted code calls *in the program*), and there was no way to
ask for the first alone.

## 3. Why it mattered

`(exclude-prelude)` was the only escape, and it is all-or-nothing:
`examples/avr-blink.nuc` takes it and thereby gives up `if`, `when`, `unless`,
the variadic arithmetic operators and `->` as well. Its own comment stated the
constraint — the prelude's node/arena/intern runtime "references host-only libc
(`perror`/`malloc`) absent from freestanding avr-libc, so it would fail to
link".

An AVR part with 2 KB of flash cannot spend 4.5 KB on an intern table it never
reaches. The choice was "no macros at all" or "no AVR".

**That choice is gone.** `examples/avr-blink.nuc` with the `(exclude-prelude)`
line deleted links for the ATtiny1634: 882 bytes of text against 858 with it
(626 against 604 after §9). The example keeps the directive because it also pins
that path; a new AVR program does not need one.

## 4. Options (as designed)

**(a) A compile-time-only import form** — `(import-ct <lib>)`: register types,
signatures and macros; emit nothing. The register/emit split already exists and
is already understood — `.nuch` imports are exactly "REGISTER + EMIT, split by
mode" (conventions.md). This is the form the overview asks for, and it is the
one that composes: any library can be imported for its compile-time surface
alone.

The catch is that it is a *promise the program must keep*: a program that
`import-ct`s `node` and then writes `'foo` has no `intern-symbol` to call. That
needs a diagnostic at the use, not a link error.

**(b) Split the prelude.** Independent of (a), and probably wanted anyway:
`Node`/`NodeKind`/`StrView` are type definitions that emit no IR, and
`lib/macros.nuc` emits no IR either. Only `lib/node.nuc` + `lib/arena.nuc` are
runtime.

**(c) Demand-driven emission** — emit an imported library's `defn` only if
something references it. The most general answer and the largest change; it also
walks straight into the class conventions.md warns about twice (a pre-pass that
mirrors an emitter must mirror its skips; a non-emitting mode inherits none of
the emitter's diagnoses). Not recommended as the first step; **still not done**.

**(d) `-ffunction-sections -Wl,--gc-sections` in `build.sh`.** Not a language
feature and does not help the AVR link, yet it is a few lines and would shrink
every hosted binary. Worth doing regardless. **Done** — see §9, where both
claims in that sentence turned out to be wrong: it is not a `build.sh` change,
and it is worth more on AVR than anywhere else.

## 5. What (b) landed

`lib/prelude.nuc` keeps only forms that emit no IR — the `Node` and `StrView`
types, `NodeKind`, `lib/macros.nuc`, `Clone`, `Result`, `Maybe` — and drops
`(import-use node)`. The runtime is a library like any other.

**The demand is diagnosed, not auto-imported.** `require-node-runtime`
(src/nucleusc.nuc) refuses a program-module node-constructor call by name:
`quote needs the node runtime — add (import-use node)`. That matches how every
other lowering-to-a-library sugar already behaves (`[…]` needs `vector`, `{…}`
needs `hashmap`, `:kw` needs `keyword`), and it is the same check (a) then needs
for its own promise, so it was built once.

**There are two emission sites, not one.** `emit-quote-tree` is the obvious one.
The second is the `&rest` call site in `emit-call-with-args`, which folds
trailing arguments into `@make-cell` cells nowhere near a quote — a check on
quote alone would have left that a link error. A third route reaches
`emit-quote-tree` indirectly: a literal selector for a user `get` method interns
its symbol at run time (`emit-selector-value`).

The exemption is `emitting-program-ir` — a JIT module resolves against the
compiler process, and the REPL's quote handling is independently broken (§7).

**Measured blast radius: 7 of 150 examples, 1 of the fixtures.** Everything else
never touched the runtime it was paying for. Each now says `(import-use node)`.

**A second, undocumented leak came out with it.** `lib/arena.nuc` imports
`stdio.h`, `stdlib.h` and `string.h`, so the prelude's node import had been
supplying `printf` and `malloc` to *every* program. Twelve examples and seven
fixtures used one without importing it, and inline heredoc fixtures in
`tests/run-tests.sh` did too. Those are now honest about what they use. This is
worth remembering as a class: **a transitive import is an undeclared dependency
that only shows up when the intermediate node is removed.**

`w9-multi-object-weak-prelude` asserted a weak `arena-init` in two objects as
its proof that an imported file is duplicated per object. That premise died with
the split; it now asserts the same property on the fixture's own inlined import,
which is what it was always really about.

## 6. What (a) landed

`(import-ct lib)` — one form, flatten semantics, matching `import-use`.

**Implemented by redirecting the definition stream, not by a register-only
walk.** The emitter runs unchanged and its `define`s / `@g = global`s go to a
sink. This is deliberate: conventions.md warns twice that a pre-pass mirroring
an emitter must mirror its skips and inherits none of its diagnoses, and a
register-only walk would be exactly that pre-pass.

**Only that one stream.** Redirecting the other two makes the compiler lie to
itself:

- The **type** stream is free at run time, a macro body may still name the type,
  and dropping a `%Name = type {…}` leaves a later `%Name` reference dangling.
- The **decl** stream is guarded by "already declared" latches —
  `g-malloc-decl-done`, `g-trap-declared`, `g-nuch-registered` — each recording
  a `declare` the module is thereafter assumed to hold. Measured: with the decl
  stream redirected, `lib/arena.nuc`'s own `defmacro` JIT'd a `@malloc` call
  into a module whose declare had been discarded. This is the general shape —
  **any latch that means "this is in the module" becomes false the moment
  emission is redirected**, so redirect as little as possible.

**The promise is checked at the use.** `Sym.ct-only` is set at the three sites
whose definition went to the sink — `emit-defn`'s solitary binding, `emit-defvar`
and `prescan-defvar-name` — and *not* in `scope-define`, which would also have
caught C-header and `.nuch` names whose definitions live in libc or a `.o` and
are not withheld at all. `reject-ct-only` fires at the two chokepoints that turn
a Sym into program IR: `emit-call-with-args` (every direct and multimethod call)
and `emit-symbol-ref`'s non-local branch (a global read or a function taken as a
value), placed *after* the `is-const` arm because a `defconst` is a compile-time
substitution with no storage and survives fine.

Residue, deliberate: an **overloaded** ct-only callee dispatches through the
generic registry rather than a Sym, so it falls through to a link error. The
check never false-positives, which is the property that matters.

**Compile-time-only is a property of the UNIT, not of one import edge.** This is
the part that took the most iterations and is the least obvious.

`lib/error.nuc` says `(import-ct node)`. A program that handles errors *and*
quotes must still get the node runtime. The first implementation let the CT
import claim the path on `g-imported`, so a later `(import-use node)` was
deduplicated away and the program was refused at its own quote — correct in one
import order, silently wrong in the other.

The rule that fixed it: a file's definitions are withheld **only if no ordinary
import anywhere in the unit reaches it**. `prescan-imported-signatures` already
walks the whole import graph before any form is emitted and follows every import
form *except* `import-ct`, so the set of paths it visited is exactly "reachable
for real". `g-real-reachable` snapshots it (the lists are prepend-only, so
holding the head is a genuine snapshot), and `ct-sink-here` asks per file.

Two consequences worth keeping:

- **The decision is per file, not a nesting depth.** An ordinary import reached
  *through* a compile-time-only one is still ordinary, so `emit-import-forms`
  sets the mode explicitly in both directions and hands a real import back
  `g-def-stream-program`. Measured before that fix: `lib/vector.nuc`, imported
  for real by the program *and* pulled in by a ct-imported library, had every
  definition marked ct-only and the program was refused at its own `[1 2 3]`.
- **A template stamp belongs to no file**, so `drain-mono-worklist` writes to
  `g-def-stream-program` rather than `g-def-stream`. The stamp is memoized as
  emitted by `g-mono-drained`, and the thing that calls it may be the program.

A path that is genuinely CT-only records on `g-ct-imported`, not `g-imported`,
so a real import that the graph walk could not see (a string-path import, which
no prescan walks) still re-reads and emits the file. Verified safe for
node/arena; re-reading a library that registers protocol conformances is not,
which is why the graph-level decision is the primary mechanism and this is only
the fallback.

A C header never sinks: it emits only declarations and libc supplies the
definitions either way.

## 7. Left open

- **(c) is not done.** (d) landed; see §9.
- **The REPL cannot quote, and could not before this work either.** `'a` at the
  prompt fails with `use of undefined value '@intern-symbol'`, and
  `(import-use node)` there fails differently (`Duplicate definition of symbol
  'intern-symbol'`). `require-node-runtime` exempts `g-interactive` so REPL
  behaviour is byte-for-byte unchanged. This belongs to the overview's separate
  "`import` doesn't seem to work in the REPL" item.
- **`import-ct` has one spelling.** No prefixed / `import-only` variant. Nothing
  in tree wants one yet.

## 8. Relationship to `macrolet`

None on the critical path. `macrolet` inherits `defmacro`'s compile-time
requirements exactly — the same `Node` type, the same JIT'd constructors in the
compiler process — so it neither worsens nor is blocked by this. The overview's
note that `macrolet` "may need a compile-time guard to ensure `Node` is
available" resolves to: it needs precisely what `defmacro` already needs, and
under `(exclude-prelude)` both are equally unavailable.

## 9. What (d) landed

Every definition goes into its own ELF section and the link line carries
`-Wl,--gc-sections`. That is the only thing that reclaims what §4a and §4b
cannot: a `weak_odr` definition may not be discarded (that is exactly why the
linkage word is `weak_odr` and not `linkonce_odr` — conventions.md), and the
string table is emitted into the program module whole, entries only a macro's
JIT module ever used included.

### The flags do not exist where the option said they did

`build.sh` runs `nucleusc`, and `nucleusc` emits the object file itself through
`LLVMTargetMachineEmitToFile`. `-ffunction-sections` is a *codegen* flag, so
passing it to the link driver is a no-op — the object is already written by
then. The two obvious routes both fail:

- **The LLVM C API has no switch.** `TargetOptions::FunctionSections` is not
  reachable through `LLVMCreateTargetMachine` or `LLVMTargetMachineOptions*` in
  LLVM 19.
- **The cl::opt is not registered.** `-function-sections` lives in
  `CommandFlags.cpp` and is created by `codegen::RegisterCodeGenFlags`, which
  only `llc`-style tools construct. Measured: `LLVMParseCommandLineOptions` with
  `-function-sections` returns success — it does not diagnose an unknown option
  — and the emitted object is byte-identical to one emitted without it. **A
  clean `LLVMParseCommandLineOptions` says nothing about whether the option
  exists.**

So the section names are spelled in the IR (`section ".text.foo"`), which is
what `-ffunction-sections`/`-fdata-sections` amount to, and only the
`-Wl,--gc-sections` half is a link-line change.

### Three rules, each of which was a measurement

**The name must be the symbol's.** MC caches sections by name, so two
definitions written to one name become one section, and a merged section is
collected only if *every* definition in it is dead. Uniqueness is not decoration.

**`.bss` versus `.data` is decided by the NAME, not the initializer.**
`getELFKindForNamedSection` maps a `.bss`-prefixed name to `SHT_NOBITS` and
leaves everything else `SHT_PROGBITS` — the initializer does not get a vote.
Measured both directions: `@z = global i32 0, section ".data.z"` is PROGBITS and
newly costs file bytes (a 64-element zero array cost 256), and
`@nz = global i32 7, section ".bss.nz"` is a **hard error**
(`SHT_NOBITS section '.bss.nz' cannot have non-zero initializers`), not a silent
zero. The error is what makes the rule safe to state at all, so
`global-section-prefix` claims `.bss` only for an initializer this compiler
rendered as the type's zero — a streamed constant aggregate takes `.data`, which
is never wrong, only occasionally wasteful.

**Only ELF.** A Mach-O section specifier is `SEGMENT,section` and LLVM rejects a
bare name; COFF garbage collection is `/OPT:REF`. `elf-object-format` keys off
the triple, and the JIT is excluded separately via `emitting-program-ir`: a JIT
module is built for the **host** while the section spelling follows the
**target**, so cross-compiling to ELF from a Mach-O host would otherwise hand
the in-process JIT an invalid specifier. The string table is the one site that
takes the decision as a parameter rather than asking `ir-sections-on` — it is
written at module-assembly time, after the stream swaps that predicate reads
have been undone, so a CT or macro module would look like the program module
there.

### Measured

Hosted (x86_64 Linux), `.text`/`.rodata`/`.data` of the linked binary:

| | before | after |
|---|---|---|
| `hello` | 306 / 145 / 16 | 306 / 15 / 8 |
| `macrolet` | 581 / 211 / 16 | 581 / 57 / 8 |
| `valid` | 1300 / 298 / 16 | 1300 / 164 / 8 |
| `operators` | 1577 / 327 / 16 | 1321 / 193 / 8 |
| `list` | 3568 / 200 / 16 | 2800 / 44 / 8 |
| `callable` | 3502 / 281 / 16 | 2638 / 127 / 8 |
| `quasiquote` | 3642 / 228 / 16 | 2866 / 72 / 8 |

`examples/avr-blink.nuc` on the ATtiny1634, `text`/`data`:

| | before | after |
|---|---|---|
| with the prelude | 882 / 126 | 626 / 0 |
| under `(exclude-prelude)` | 858 / 0 | 604 / 0 |

The 126 bytes of `.data` §7 predicted are gone, and the four AVR examples now
link at 346–862 bytes of text where they occupied 858–1070.

**The compiler's own binary is the one thing that gets slightly worse** —
`.text` 574693 → 577333 (+0.46 %), `.rodata` 59919 → 60101 — and adding
`-Wl,--gc-sections` to its link in the Makefile changes **nothing**, measured
byte-for-byte. `-rdynamic` puts every symbol in the dynamic symbol table, and a
dynamically-exported symbol is a GC root, so there is nothing left to collect;
what remains is per-section alignment padding. The Makefile is therefore
unchanged. (`-rdynamic` is load-bearing — the macro JIT resolves against it —
so this is not a flag to trade away for the 0.46 %.)

### Escape hatch

None was added. `--link-arg=` already exists and its arguments are appended
*after* the compiler's own flag, so `--link-arg=-Wl,--no-gc-sections` turns the
collection back off (the pair is last-wins). That matters for a program that
looks its own symbols up with `dlsym`: without `-rdynamic` its defined globals
are not exported, so nothing roots them. `s16-gc-sections-drops-unused-import`
pins both directions.
