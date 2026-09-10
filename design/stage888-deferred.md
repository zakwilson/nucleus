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
  rest args are built as a `Node*` cons list at the call site.
- **`--emit-cheader` skips template-instance signatures** — exported
  functions whose return/param types include a stamped template instance
  (e.g. `(Result Config Err)` from `!Config`) are silently omitted from
  the generated header (`cheader-template-instance`, src/cheader.nuc:829,
  emits a `/* not exported */` comment). Fix requires a naming convention
  for instances (e.g. `nuc_Result_Config_Err`). Blocked on no exported
  surface having adopted `!T` yet; revisit when it does (errors.md §11.7).

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
plus `doseq-iter` + `addr-of` ceremony: bind `(chars sv)` or `(bytes sv)`,
then `(doseq-iter (c (addr-of it)) …)` — see examples/strview-read-test.nuc.)

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
  as compile-time data;
- restricting computed access to a declared homogeneous *subset* of fields.

Until one is chosen, computed field access stays what it is today: correct, and
available only where every field has the same type.

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


## Compiler types

### (raw T) should (maybe) be ?T

* c-type-to-nucleus
* c-typedef-find
* cdecl-site-find

## Pointer-kind spellings: make the sugar general, or ban the ambiguous half

Raised 2026-09-07, after the `&`/`@` adoption sweep across `src/`, `lib/` and
`examples/` (see [progress.md](progress.md) and
[stage16-ergonomics/ref-sigil.md](stage16-ergonomics/ref-sigil.md) §5/§6).

The `&` sigil is split by position **inside the token**: `p:&T` is the lexer
rewrite to `ref:` and leaves no trace, while a standalone `&T` is the address-of
reader macro and reaches the parser as `(addr-of T)`. In a type slot that node is
accepted (`parse-type-from-node`, `node-is-ptr-wrapper`, and since 2026-09-06
`type-node-to-c`), so it compiles and emits identical IR — but `--emit-nuch`
prints `defprotocol` and generic-template forms **verbatim**, so the odd spelling
lands in a committed header. `a15f38e` wrote 2,469 of them into `src/` before
anyone noticed; the sweep that removed them is convention, not a rule the
compiler enforces.

Two coherent end-states, and they point opposite ways:

- **Make it general.** `&T` should be legal and canonical in every type slot,
  round-tripping through `--emit-nuch` as `&T` or `(ref T)`. The reader cannot
  decide by position, so the node has to *remember it was written `&`* — a
  distinct head both the type path and the value path accept, printed back as
  the source spelling. Cost is the usual reach list: the `node-type`↔`emit-node`
  lockstep, `gcheck`'s value-path wrapper test, and `fn-rewrite-captures`.
  §6 costed the wrapping-with-`addr-of` alternative at zero value-side changes
  precisely by *not* doing this; that trade should be re-priced now that the
  spelling has 3,000 uses rather than none.
- **Ban the ambiguous half.** Make a standalone `&T` in a type slot a
  diagnostic naming `ref:T` / `(ref T)`, so the convention is mechanical instead
  of a thing a sweep has to re-derive. Cheap — one arm in
  `parse-type-from-node` — but it retires `(sizeof &Pt)`, `(as &Pt q)`,
  `(link &Pt)` and `(Vector &Pt)`, which §"Where the two meet" blesses and
  `examples/ref-sigil.nuc` plus `s16-ref-sigil-both-meanings` exercise.

The general principle worth settling first: **a spelling whose meaning depends
on where the reader happens to be should not be silently accepted.** Today three
spellings of the same pointer kind (`ptr:T`, `ref:T`, `&T`) differ in nothing
the type system can see, yet differed for a year in what `--emit-cheader`
printed (`T*` vs `void*` — fixed 2026-09-06) and still differ in what
`--emit-nuch` prints. `raw:T` is the remaining case: it widens to `void*` in a C
header deliberately, which is defensible for a nullable pointer and is still a
header whose fidelity depends on which synonym the author typed.

## String literal limit

Whether the current string literal length limit is desirable should be revisited

## macmap, maybe macreduce

```lisp
(macmap ((tok) `(when (!= (text-token-is text start e ~tok) 0) (return 1)))
  ("defn" "defmacro" "defvar" "defconst"))
```

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
`align 1` — and `tests/fixtures/avr2-16bit.nuc` pins it. But the same module,
emitted for `attiny1634`, still carries 93 `align 8` operands, and three of them
are on POINTER slots:

    store ptr %t12, ptr %nnn.addr.14, align 8
    store ptr %t0, ptr %nn.addr.2, align 8

A pointer is two bytes there, so eight is not merely generous: on a
strict-alignment backend an over-claimed alignment is a promise the emitter has
no way to keep, and LLVM is entitled to use it. The `i64` slots (`alloca i64,
align 8`) are a separate and milder question — legal, but AVR's preferred
alignment for every type is 1.

Not fixed here because it is a codegen change, not a test change, and the unit
that would gate it is the one being ported. `avr2-16bit-attiny1634` /
`avr2-16bit-avrxmega3` pin the qq-helper's `align 1` by presence, so the fix has
somewhere to land; add the pointer-slot absence to those two units once the
alignment comes from the datalayout rather than the host default.

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
