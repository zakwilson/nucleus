# Deferred

## C interop boundaries

- **`static inline` functions from headers** — body skipped, declaration
  not emitted. Headers that expose important functionality only as
  `static inline` (common in modern libc and helper headers) require
  hand-written wrappers. See `stage3c.md`.
- **Function-like C macros expanding to compound literals or statement
  expressions** — `clang -E` expands them, but the Nucleus parser can't
  consume the result. Manual wrappers required.
- **Variadic functions defined in Nucleus** — can call C variadics
  (`printf`), but cannot `defn` a variadic function using `va_list` /
  `va_start` / `va_arg`. `&rest` is macro-level, not C ABI.
- **`&rest` functions are not C-callable** — fixed at the ABI boundary;
  rest args are built into a list `Node` at the call site.
- **`--emit-cheader` skips template-instance signatures** — exported
  functions whose return/param types include a stamped template instance
  (e.g. `(Result Config Err)` from `!Config`) are silently omitted from
  the generated header (`cheader-template-instance`, src/cheader.nuc:829,
  emits a `/* not exported */` comment). Fix requires a naming convention
  for instances (e.g. `nuc_Result_Config_Err`). Blocked on no exported
  surface having adopted `!T` yet; revisit when it does (errors.md §11.7).
- **C++ interop — a library, not a language feature.** Nucleus reaches C
  and nothing else, so any C++ API without a C facade is unreachable. First
  concrete want, named 2026-09-11: ORC's `JITDylib::setLinkOrder`, which
  [stage20-macros/macro-call-linking.md](stage20-macros/macro-call-linking.md)
  §4 option B needed to say "host first, program second" and could not reach —
  LLVM's C API exposes a search order for explicit lookups only. Whatever this
  becomes, it is a **library** (`lib/`, or a generated shim beside the header
  importer), not core syntax: name mangling, vtable layout, exceptions and
  templates are an ABI to model at the boundary, not semantics to add to the
  language. Note the standing constraint it runs into — Stage 16 retired
  `src/repl_shim.c` and the compiler is pure Nucleus, so a design that
  reintroduces a C++ translation unit into the compiler's own build is
  answering a different question than one that ships a library for programs.
  No plan; filed so the next "we'd need C++ for that" has somewhere to land.

## Stage 10 safety / error-handling deferrals

### `errdefer`

Dropped from error handling v1 (errors.md §12). The `defer` + explicit
error-path combination has covered every case so far. Reintroduce if
adoption finds a pattern that genuinely needs it.

### Handler repair over niche pointers

In E3, a `with-handler` whose repair type is a niche-encoded `(ref X)`
(i.e. `(Maybe (ref X))` is a plain `ptr`, not a struct) is not supported
by the handler-invocation path (`emit-handler-call`,
src/union-emit.nuc:615, 828, 871). V1 handler repair types must be value
types (structs / scalars). The original blocker — `(Maybe (ref X))` not
being a proper layout instance — was lifted when U4/C4's niche layout
engine landed (stage10/progress.md), so this is now unblocked; the
handler path itself has just not been extended.

### `die-at` hook

The C3 panic-tier hook fires only on unwrap failure
(`emit-unwrap-result` / `emit-unwrap-niche-errptr` consult the
`'unhandled-error` handler chain); a bare `die-at` abort does not. So a
REPL/test harness binding `'unhandled-error` sees unwrap failures but
not direct `die-at` aborts. Recorded as-built in errors.md's C3 block;
wire the `die-at` path through the hook if a consumer ever needs it.

## Strings / Unicode (Stage 11 `string.md` deferrals)

### UTF-16 encode/decode on `Char`

An earlier `string.md` draft listed UTF-16 alongside UTF-8 on the `Char`
protocol. Deferred (Q-utf16): Nucleus is a UTF-8 language and there is no
concrete consumer (no Windows wide-API interop story). Reintroduce a
`char-encode-utf16` / `char-decode-utf16` pair only when a real consumer
appears; the surrogate-pair logic is well-understood and self-contained.

### Full Unicode case mapping / folding

`string.md` ships **ASCII-only** `upcase`/`downcase` (and `char-ascii-upper`/
`char-ascii-lower`) in its first pass (Q-case). Full Unicode case mapping and
case folding are deferred: they need the Unicode case tables (multi-codepoint
expansions like `ß → SS`, locale-sensitive rules like Turkish dotless-i), which
is a data-table + algorithm effort disproportionate to the first string release.
`collections.md` already flagged `upcase`/`downcase` as "Unicode/locale-fraught."
Grapheme-cluster segmentation and NFC/NFD normalization belong to the same future
Unicode-tables library.

### Seq

I really want strings to be Seq, or to add another protocol. It should be
possible to `doseq` a string. (Today it takes an explicit iterator binding
plus `doseq-iter` + `&it` ceremony: bind `(chars sv)` or `(bytes sv)`,
then `(doseq-iter (c &it) …)` — see examples/strview-read-test.nuc.)

## Variadic declare

  A declare is open-tailed — floor at num-params, no ceiling. A uniform exact rule compiled and self-hosted fine and a parser-aware sweep reported zero affected
  sites, but three suite heredocs write (declare printf (fmt:CStr):i32) and call it with 3–6 arguments, docs/toplevel.md documents that idiom, and src/nuch.nuc's
  own diagnostic actively recommends it. So a declare is a prototype the user asserts, and Nucleus has no ... spelling.

  The agent stated the cost plainly rather than burying it: a .nuch-imported Nucleus defn is also open-tailed, so cross-module calls with too many arguments stay
  undiagnosed. An explicit variadic marker for declare would make the open tail opt-in — that's the natural follow-up.

  One implementation note that generalizes: the rule must not gate on kind == TY-FN, because a BoxedFn/(dyn P) handle carries its arity on a TY-STRUCT type. A
  kind gate would have silently stopped checking that path.
  
## Possible bugs

~~`as` rejects float literals that round, but an implicit cast may be allowed. Investigate surprising behaviors.~~ **Resolved 2026-08-14** as W9 item 30 — see
design/stage15-stress-test/progress.md. `as` now admits a float literal that round-trips exactly, so `(as f32 1.5)` matches what `(let (a:f32 1.5) …)` already
accepted. One asymmetry survives on purpose: the implicit path still *rounds* `3.14` silently (W2d Option A) where `as` refuses it, because if `as` rounded too
then nothing in the language would mean "this conversion is exact".

**A user generic hijacks a library parameter of the same name in head position**
(found 2026-10-07, Stage 24 AL-1). A library function whose parameter `f` is
read as `(f 'off)` stops compiling when the program defines a `:where` generic
named `f`. The head resolves to the generic, and the error names the quote:
"quote needs the node runtime". A local binding should out-rank every global.
`lib/nucleus/allocator.nuc` names its `FixedBuffer` parameter `fb` to stay clear
of it, and its `Tracking` parameter `tr`: AL-6 first wrote `t`, which
`s21-extend-alias-subject`'s `(defn t …)` hijacked.

**The REPL cannot really import a library that an earlier import pulled in
through `import-ct`** (found 2026-10-07, Stage 24 AL-1). `(import-use
nucleus.error)` ct-imports `nucleus.node`, and with it `arena` and `allocator`.
A later `(import-use nucleus.arena)` then reports each definition as "imported
compile-time-only". The batch compiler resolves this order correctly
(`s16-import-ct-real-import-wins-ct-first`). `tests/repl/stdlib.in` imports
`nucleus.arena` before `nucleus.error` to avoid it.

**Macros are not namespaced by their library** (found 2026-10-08, Stage 24 AL-3).
Suppose two `import-use`d libraries both define a macro `new` (`nucleus.arena`
and `nucleus.create`). The bare name expands whichever loaded first, and no
diagnostic is given. A library macro also claims its name against a user
`defn` even under a prefixed import: "'make' already names a function", at the
library's line. AL-4 removes the arena's `new`. The general fix is to resolve
macros by namespace, as functions are.


## Flow-sensitive typing

Stage15 added some capabilities, and a later stage should examine expanding them.

## Symbols for struct field access

Bare symbols as arguments *may* be struct field names or *may* be variables. The
ambiguity is undesirable. **Being addressed** in Stage 16 — see
[stage16-ergonomics/dot-forms.md](stage16-ergonomics/dot-forms.md): the quoted
selector (`(get p 'x)`) becomes the only literal spelling, so a bare symbol in
selector position goes back to being an ordinary variable reference and
`(get p sel)` needs no annotation.

### What survives that fix: field iteration over a heterogeneous struct

Making the *spelling* regular does not make the operation total. A computed
selector lowers to a `select` chain over the field indices
(`emit-computed-field`), and that chain has one result type — so it is gated on
the struct being **homogeneous**:

```
get: computed field access requires a homogeneous struct, but 'Node' has fields of differing types
```

That gate is not a spelling problem and no selector syntax removes it: iterating
`Node`'s fields by symbol has no type to return. The options, none taken:

- a sum-typed result (`(get p sel)` returning a union over the field types),
  which makes every computed read a `match`;
- generated per-struct accessors, i.e. reflection over a struct's field table
  as compile-time data. The data now exists: `struct-fields` (Stage 22 ED-4.2,
  `docs/macros.md`) gives a macro the field table, so such accessors can be
  derived the way `derive-edn` derives codecs;
- restricting computed access to a declared homogeneous *subset* of fields.

Until one is chosen, computed field access stays what it is today: correct, and
available only where every field has the same type.

## Derived structural equality

A struct has no `=` unless its author defines one (conforming `Eq`,
`lib/numeric.nuc`). A literal operand compares by value only through that
definition (Stage 21, 2026-09-25); with none, the comparison is refused.
Having the compiler *derive* `=` field by field is its own decision, not taken:

- **Padding** — a byte-wise compare reads indeterminate bytes, so a derived `=`
  must compare field by field (bit-fields included), never `memcmp`.
- **Floats** — a field-wise `=` inherits IEEE (`NaN ≠ NaN`, `-0.0 = 0.0`), which
  breaks reflexivity; a bitwise compare breaks `-0.0 = 0.0` instead.
- **Pointer fields** — identity or pointee? Neither is right for every type
  (`&Node` wants identity; a `String`'s buffer wants content).
- **Unions and tagged sums** — compare the tag, then only the live arm.
- **Opt-in or automatic** — an explicit `(derive Eq S)`-style form, or implicit
  for every all-scalar struct; and whether `Hash` must be derived with it so a
  derived-`Eq` key works in a `HashMap`.

## Struct packing
 
 remains deferred — it wants a layout-attribute
  design that overlaps [stage14/attributes.md](../stage14/attributes.md)'s
  reserved-but-unimplemented `:align`/`:section` slots. Still the top
  layout-design candidate for the next stage.

## Type reachability
  
  a struct type named in a unit's signatures
  must still be defined in a reachable file. W1 removed the *order*
  constraint, not the reachability constraint, and that did not change.
  
This could make trouble using libraries with headers only, no source.

## Run-time `defconst`

Stage 21 item 8 ([defconst-values.md](../stage21-cleanup/defconst-values.md))
gave `defconst` the constant grammar and refuses a run-time initializer.

The shape that was designed and set aside:
- `defvar`'s G-3 path: `global` storage written once by `@__nucleus_init`,
  G-4 ordering, refused in a JIT module and on AVR;
- read-only through `readonly-global`;
- typed by annotation or by `node-type` of the initializer;
- shallow constness, like C's `T *const`.


## Compiler types

### (raw T) should (maybe) be ?T

* c-type-to-nucleus
* c-typedef-find
* cdecl-site-find

## A template stamp loses the pointer kind — `(Result raw:Node E)` / `(Maybe raw:T)` cannot be built

`union-template-stamp-types-in` (`src/union-registry.nuc`) substitutes a
template argument by its `type-spelling`, which spells every `TY-PTR` as
`ptr:elem` regardless of `pkind` — so a template stamped over a `raw`
(nullable) pointer payload comes back with a `ref` (non-null) payload and
refuses `null` at construction. Found by Stage 21 R-1
(`design/stage21-cleanup/one-reader.md` §2.1; `context/conventions.md`'s "A
template stamp loses the pointer KIND"): `lib/read.nuc`'s own error value
could not be `(Result raw:Node ReadError)` for exactly this reason, and is a
hand-written structural `defunion` instead (`ReadResult`, which `try`/`match`/
`unwrap` treat as a Result because `result-union-of` is structural rather than
template-instance-only). **Not closed by Stage 21 item 1** (2026-09-19):
[stage21-cleanup/pointer-kind-spellings.md](../stage21-cleanup/pointer-kind-spellings.md)
changed spellings and the pattern walkers, not the stamp — PK-4b found the
stamp still loses `pkind` and built around it (`sigil-unwrap-type` peels a
`TY-PTR` by *shape*, since a `(Vector &Pt)` / `(Vector ?&Pt)` /
`(Vector raw:Pt)` are one stamp whose recorded origin argument is whichever
kind stamped first; §6 "as built", and `context/conventions.md` "A template
stamp loses the pointer KIND"). Still deferred: every stamped `pkind` in
`src/` has to move together, since the memo key (`type-mangle-token`) does not
distinguish pointer kinds and the first stamp of either kind answers for both.

## A string-literal receiver in head position mis-parses a struct member access

`(("abc") 'len)` — or a macro yielding a string node in the same position —
emits `store %StrView` from a `ptr` temporary and fails to parse the generated
IR. Pre-existing; found while probing Stage 21 item 2
(`design/stage21-cleanup/one-reader.md`). Not diagnosed further.

## A transient `import: cannot find` in w9-multi-object-link

Seen once, 2026-09-10: `w9-multi-object-link` (`tests/suite-linking.nuc`) failed
a full serial run with

```
expected an object file
build/out/nt/w9-multi-object-link/side/w9side.nuc:1: error: import: cannot find 'w9share'
```

and passed on the immediately following full run, on the shuffled `--run`-per-name
pass, and on a sharded `make test`. One failure in roughly 2,300 test executions;
cold (`rm -rf build/out`) it passes, and 20/20 in isolation.

What makes it interesting rather than merely flaky: **`emit-into` resolved the
same `w9share` from the same search directory microseconds earlier**, in the same
helper (`w9-objects`), and only `compile-object-in` failed. Between the two calls
the only change on disk is that `share/w9side.nuch` was created. The test right
before it in registration order is `w9-lib-no-shared-runtime-init`, which spawns a
compiler for every one of the 43 `lib/*.nuc`.

The suspicion is that a transient failure inside import resolution is reported as
absence: `import-form-path` decides with `file-exists`, and `do-import` turns a
null answer into `import: cannot find`, so a stat that fails for a reason other
than ENOENT is indistinguishable from a file that is not there. If that is what
happened, the defect is the conflation, not the transient — a failed stat should
say so rather than blame the import.

Not reproduced, so not fixed. Worth an hour with `strace` on a loop of the full
serial suite before changing anything; a speculative fix to a path that cannot be
made to fail is worse than the flake.

## A threaded test runner

`test-main --shard i/n` (2026-09-10) parallelises the native suite the naive
way: `n` whole processes, each striding the registration list, fanned out by
`run-nuctests`. It bought most of what was there to buy, but it is not the good
version and the numbers say where the rest went.

Measured, 753 tests on 16 cores:

| runner | wall | CPU |
|---|---|---|
| serial (`test-run-all` before this) | 239.3s | 88% |
| 16 process shards, static stride | 36.3s | 861% |
| 32 shards | 37.1s | 926% |
| 48 shards | 39.1s | 914% |
| `xargs -P16`, one process per test | 31.5s | 1068% |

Two things worth keeping. **Oversubscription does not help** — 32 and 48 shards
are slower than 16, so the ~900% ceiling is not scheduling slack that more
workers would soak up. It is contention: `sys` time is at or above `user` time in
every row, because each test forks `nucleusc`, `clang` and the linker and then
moves files through its scratch directory. The runner loop is not the cost; the
per-test subprocess is. **Dynamic beats static by ~15%** (31.5s vs 36.3s): a
static stride leaves a tail, and per-test dispatch balances for free — but it
pays 753 process startups to get there, which is where its extra ~120s of CPU
goes.

So the smarter version is a thread pool pulling from a shared work queue: it
gets the dynamic balance without the startup tax, and one process means the
registration list, the interned symbol table and the fixture reads are shared
rather than rebuilt 16 times. Combined with TF-E's in-process compiler track it
would remove the fork entirely, which is the only thing that moves the 900%
ceiling.

What blocks it today:

- **No threads.** `lib/process.nuc` is fork/exec only (`spawn`, `process-wait`,
  `process-capture`); there are no pthread bindings anywhere in `lib/` or `src/`.
- **The runner's state is process-wide.** `g-test-scratch` (`lib/test.nuc`) is a
  `defvar` that `test-scratch-set` rewrites per test, `g-test-no-skip` is a
  global policy flag, and failure text accumulates in one buffer behind
  `test-fail-begin`. A pool needs all three per-worker, which is a thread-local
  story Nucleus has not had to tell yet.
- **Record ordering.** Nothing consumes `build/nuctests.out` in order today, so
  interleaving is free now — but a threaded runner writing one stdout wants a
  per-worker buffer flushed whole, or records will interleave mid-line.

Not urgent: 82.8s for `make test` is not the bottleneck it was at 282s. Revisit
when TF-E makes in-process compilation real, since that is the change that makes
threads worth more than processes.

## `align 8` on 16-bit pointer slots under `--target=avr`

Found while porting the AVR units into `tests/suite-target.nuc` (Stage 18 TF-6,
2026-09-10). Stage 14 AVR-2 fixed the quasiquote helper's Node cell — 22 bytes,
`align 1` — and `tests/fixtures/avr2-16bit.nuc` pinned it. The same module,
emitted for `attiny1634`, then still carried 93 `align 8` operands, three of
them on POINTER slots:

    store ptr %t12, ptr %nnn.addr.14, align 8
    store ptr %t0, ptr %nn.addr.2, align 8

A pointer is two bytes there, so eight is not merely generous: on a
strict-alignment backend an over-claimed alignment is a promise the emitter has
no way to keep, and LLVM is entitled to use it.

**Re-measured 2026-09-23, after Stage 21 item 6:** the pointer-slot half is
**gone** — that module now emits **zero** `store ptr …, align 8`. It was never a
general codegen fault; all three came from the hand-written `@__cons`/`@__append`
IR in `emit-qq-helpers`, and the AST-as-a-collection relayout deleted that
runtime outright (quasiquote calls `lib/node.nuc`, which is compiled *for* the
target like any other library code). What remains is the milder half named
above: 98 `align 8` operands, all on `i64` slots and the arena's `i64` globals —
legal, but AVR's preferred alignment for every type is 1.

Still not fixed, and still a codegen change rather than a test change: the
alignment on those slots comes from the host default instead of the target's
datalayout. `avr2-16bit-one` is the unit the fix lands in — it was rewritten
with item 6 around i16 pointer arithmetic (`ptrtoint … to i16`, no `to i64`,
`declare ptr @malloc(i16)`, an i16-indexed GEP) now that there is no
hand-emitted helper to pin, and an `i64`-slot absence assertion belongs beside
those once the alignment is datalayout-derived.

## Mixed-literal diagnostics name their types inconsistently

Found while porting the container-literal refusals into `tests/suite-s16.nuc`
(Stage 18 TF-6, 2026-09-10). Four spellings of one error, measured:

    set literal: mixed element types -- 'Keyword' and 'StrView'
    map literal: mixed key types -- 'Keyword' and 'StrView'
    vector literal: mixed element types
    map literal: mixed value types

The set and map-key forms name the two types that conflicted; the vector and
map-value forms do not, so a reader of `[:a 1]` is told only that the elements
disagree and has to work out which two. The types are available at each of the
four sites — the two that report them prove it — so this is a message that was
not carried across rather than information the emitter lacks.

Not fixed here because it is a diagnostic change and the units that would gate
it are the ones being ported. `s16-kwlit-refused-mix-vec` and
`s16-kwlit-refused-mix-val` pin the current wording, so the fix has somewhere to
land: extend those two needles with the type names once the message carries
them.

## `tests/fixtures/box-cheader.nuc` does not compile, so half of it is unreachable

**Resolved 2026-09-25.** A header mode now compiles first, so the fixture had to
compile: `make-boxed` returns a boxed `fn` (with `(import-use allocator)`), and
`l13-cheader-warns` asserts both warnings, at lines 21 and 25. See
design/progress.md.

The fixture's own comment says both box-typed defns are "warned at definition".
Only `make-boxed` is. `--emit-llvm` on the fixture exits 1:

    line 19  warning  'make-boxed' exposes a closure or type-erased box type …
    line 20  error    BoxedFn: can only box a closure value (a capturing
                      closure's (ref Env), or a bare `fn`)

`make-boxed`'s body is `(return 0)`, and an integer cannot be boxed into the
`(BoxedFn (i32) i32)` it declares. The compile stops there, so `use-dyn` at
line 23 is never reached and never warns. `--emit-cheader` is unaffected — it
scans signatures, not bodies — which is why both omission comments appear and
the header side of the fixture is sound.

The retired shell asserted `warning:.*exposes a closure or type-erased box
type` over the whole stderr blob, with `|| true` swallowing the exit status,
and its comment records the symptom without the cause: "(at least one box-typed
defn fires)". `l13-cheader-warns` now pins both halves — the warning that fires
at line 19 and the error at line 20 — so the defect is visible rather than
absorbed.

Fixing it means giving `make-boxed` a body that produces its declared return
type. That edits an IR-snapshot input, and `emit_all` snapshots stderr as well
as stdout, so the recorded `.ll.err` changes and the snapshot must be re-taken
with the reason recorded in `design/progress.md`. Whoever does it should also
decide whether `use-dyn`'s warning firing is worth a second assertion or
whether `l13-cheader-warns` simply loses its error half.

## The suite has no `--shuffle`

`build/nuctests` answers `--list`, `--run <name>`, `--shard <i>/<n>` and
`--no-skip`. It has no way to permute the order in which `test-run-all` walks
the registration list, so the order-independence check every retirement batch
ran is external: `--list | shuf`, then one `--run` per name. That is 966
process spawns and about six minutes, where an in-process shuffled run would
cost what a normal run costs.

`build/nuctest` (the TF-2 runner, deleted at TF-7) had `--shuffle <seed>`, over
shell units. Nothing carried it across, because the property it protects is
already structural in the native suite — every test owns a scratch directory
keyed by its name, and `test-duplicate-name` refuses a suite where two could
claim one path. What a shuffle still catches is the *other* kind of coupling:
the process-global registries a test leaves behind (`g-fail-buf`, the interner)
and any assertion that quietly depends on a file an earlier test wrote.

The shape is small: a `--shuffle <seed>` flag, a permutation of the index
sequence `test-run-all` strides, and the same seed printed in the run's first
record so a failure is reproducible. Sharding must keep working alongside it —
shuffle the whole list, then stride — or a shuffled run and a sharded run
cannot both be trusted. Deferred rather than absorbed into TF-7, which was a
deletion.

## Stage 20 macro deferrals

Named while designing [stage20-macros/overview.md](stage20-macros/overview.md)
§8. `macmap` is the first thing that makes the first two cost something.

### Name pasting — **no longer blocked, still not wanted**

There is no `concat_idents!`, and the reason recorded here was that nothing could
`intern` over formatted parts from a macro body under Stage 20's decision 8 (call
nothing outside `lib/node.nuc`). **That blocker is gone.** Decision 8 was retired
by [stage20-macros/macro-call-linking.md](stage20-macros/macro-call-linking.md)
§3.1: a macro body may call its own helpers, so composing a spelling and interning
it is an ordinary `defn` — measured 2026-09-12 at L8, `(str "g-" …)` →
`intern-node` → a spliced symbol, exit 42.

What remains is a design preference, which is the part that was always load-bearing.
The one place in the tree that wants it is the `repl.nuc` field table, where the
struct field and the global differ only by a `g-` prefix, and a two-column row
answers it explicitly and greppably. A pasted name is ungreppable, which is why
Rust's `concat_idents!` has been unstable for a decade. Reconsider only when a
second table wants it — and note that a paste helper is now something a *program*
can write for itself without the language growing a form.

### Nothing in `lib/` may reach into the compiler's exported surface

**The rule is not a desirable end state — see
[compiler-api-surface.md](compiler-api-surface.md) (raised 2026-09-15) for why
and for the options.** The short form: the forbidden examples are exactly what
tooling needs, and more of the surface is of potential use to both bundled and
third-party libraries. The rule below stands until something replaces it.

A rule, not a deferral, and the residue of the entry that stood here. `-rdynamic`
exports 2,285 symbols from `build/nucleusc`, of which 1,658 are spelled as
ordinary lowercase-hyphenated Nucleus identifiers — `macroexpand-form`,
`desugar-form` and `find-macro` among them. That is an accidental, unversioned
API surface, and no library file may name it.

The deferral this rule was attached to — "a macro body may call only what the
compiler binary exports" — was designed 2026-09-11 as
[stage20-macros/macro-call-linking.md](stage20-macros/macro-call-linking.md),
Stage 20 part three, after probing established that it is not only a missing
feature: a program `defn` whose name lands on one of those 1,658 binds to the
*compiler's* function silently, and with a mismatched signature segfaults the
compiler. Naming a supported compile-time API — and hiding the rest — stays
deferred there (§10).


### The REPL does not accept a top-level macro that expands to a definition

Noted 2026-10-03 while building Stage 22 ED-4.1
([stage22-edn/macro-definitions.md](stage22-edn/macro-definitions.md) §3).

**Symptom.** At the prompt, `(derive-area Sq)` fails with
`unknown: defn — not defined anywhere in this compilation unit`, where
`derive-area` expands to a `defn`. It fails the same way before and after
ED-4.1. In a compiled file the same call works.

**Cause.** The REPL chooses a handler for each prompt form by its head, using
the per-definer arms in `src/repl.nuc` (`defn`, `defvar`, `defstruct`,
`defmacro`, …). A macro call matches none of them, so the form takes the
expression path, which compiles the expansion as a function body, where
`defn` is not a form.

**Fix sketch.** Expand a top-level macro call first, splice a `(do …)`, and
re-dispatch each resulting form through the same arms.

**Two follow-ons:**
- The REPL's `defn` arm handles only a solitary name (`repl.nuc`, the
  redefinition thunk). A macro that produces overloads, which is the point of
  derivation (ED-4), also needs the REPL to support overloads.
- A REPL `extend` arm must see the expansion's methods. Batch compilation gets
  this from `late-prescan`; the REPL already registers each `defn` as it
  arrives.

**Not wanted until** a REPL user derives codecs at the prompt. Importing a
companion library that a compiled file derived already works.

## List literals are not (ref Node)

List literals are (ptr Node), but functions defined in node.nuc like `contains?` expect &Node.

## Namespace issues

- After a failed import in the REPL, its namespace stays cached.
- A .nuch header drops an import-use of a library in user, so the import closure is lost through that header.

## The C importer's lookups are linear scans

`lookup-struct` (`src/union-registry.nuc`) walks every registered struct, and
`c-typedef-find` (`src/type-utils.nuc`) walks a linked list. Typed C pointers
look up more names than the importer did before. As a result, a `gtk/gtk.h`
import went from 1.77 s to 2.33 s (+32%), and before that change
`c-parse-type` was already 39% of a GTK import's samples. A HashMap keyed by
name for each table is the likely fix. typed-c-pointers.md §4 TP-0.

**Not wanted until** import time matters more than it does today.

## Stage 24 allocator rulings to revisit after use

Both were ruled on 2026-10-07 to take the simpler option first
([stage24-allocation/overview.md](../stage24-allocation/overview.md) §10).

- **Q5: a full `FixedBuffer` returns null.** The alternative
  is to fall back to a parent allocator, as Zig's `stackFallback` does. With a
  parent, the type is an `Arena` whose first block it does not own, like C++'s
  `monotonic_buffer_resource`, so the two types could merge. Revisit once
  real code shows whether callers keep writing their own fallback.
- **Q6: the default allocator is the fixed global `heap`.** The alternative is
  an implicit, dynamically scoped current allocator, like Odin's
  `context.allocator`, rebound by a `(with-allocator a …)` form. Revisit once
  there is enough code to judge whether threading an allocator explicitly is a
  burden, or whether a hidden one would make call sites unclear.

## A type conforms to a parametric protocol at most once

Stage 11 made the one-record-per-(type, protocol) rule the associated-type
coherence rule ([stage11/assoc-types.md](../stage11/assoc-types.md) §0, §5): a
`:where ((Iterator E) I)` recovers `E` from `I`'s single record
(`recover-one-constraint`, `src/generics.nuc`). Stage 24 ran into it: §5 of
[stage24-allocation/overview.md](../stage24-allocation/overview.md) has `String`
conform to both `(InitFrom StrView)` and `(InitFrom &String)`, which is refused
(`re-extends protocol 'InitFrom' with different associated arguments`). The
`&String`, `&(Vector ui8)` and `&(Vector T)` sources are therefore plain `init`
overloads. `new`/`make` reach them through dispatch, but `conforms?` cannot see
them.

Risks of lifting the rule outright:

- **Recovery goes silently wrong.** With two records, `conformance-args` returns
  the first, so a generic infers the wrong parameter instead of failing.
- **Some protocols cannot be multi-conformed at all.** A parameter that appears
  only in a return type (`(Iterator E)`'s `next`) would give methods that differ
  only by return type, which overload resolution cannot pick between.
- **Lost error checking.** `(extend Foo (Seq i32))` then `(extend Foo (Seq i64))`
  is an error today. It catches typos and two libraries disagreeing.
- **Every registry site assumes one record**, and each would need the arguments
  in its key:
  - `conformance-find`, `-lookup` and `-args`;
  - the re-extend path in `verify-conformance-params`;
  - the `conforms?` argument comparison;
  - the CQ-1b "no" records, where a no for `(InitFrom i32)` would refuse a later
    `(InitFrom StrView)`;
  - template conformances and `.nuch` replay.

  A missed site answers wrongly rather than failing.
- **Future `dyn`.** DP's vtable names would need the protocol arguments.

**The safe shape**, if a second protocol needs this, is Rust's split between a
trait's generic parameters and its associated types, inferred rather than
declared:
- Allow a second conformance only when every parameter appears in some method's
  argument list. `InitFrom` and `TryInitFrom` qualify; `Iterator`, `Seq`, `Coll`
  and `Assoc` keep the rule.
- In a `:where` on such a protocol, pick the record using parameters the call
  has already bound. Report ambiguity when a parameter is unbound and several
  records exist; never take the first.
- Add the arguments to the key at every site above.

The compiler's own source has no multi-conformance, so a byte-identical boot
gate applies.

**Not wanted until** a second protocol needs it. Today it only makes `String`'s
`&String` source visible to `conforms?`, and `(InitFrom StrView)` over
`(string-as-view &s)` already copies a `String` losslessly.
