# Stage 21 item 8 — `defconst` takes literals and constant aggregates

**Status:** built 2026-09-28. DC-0, DC-1, DC-2, DC-3 and DC-5 are done; DC-4
(float folding) was not built. §8 records where the build differs from the
plan. Scope was decided the same day (§7): literals and constant aggregates,
`defvar :const` retired, `&NAME` a documented hole. Run-time initializers are
deferred.

**Ask.** `defconst` accepts only an integer literal. It should accept what a
`defvar` initializer accepts. For now that means the constant grammar, not the
run-time tier.

**Verdict.** Nothing blocks it. Two existing defects in `defvar :const` have to
be fixed first (§2), because tier A below inherits its mechanism. The compiler
uses only integer `defconst`s, so every step before DC-5 leaves its own `.ll`
byte-identical and needs no boot refresh.

## 1. Today (measured)

- `emit-defconst` (`src/nucleusc.nuc:14255`) refuses any value that is not a
  `NODE-INT` (`:14292`, `defconst: value must be integer literal`). It refuses
  constant expressions too: `(defconst K (+ 2 3))` fails, although
  `(defvar g:i32 (+ 2 3))` folds. It also refuses a type annotation (W4b,
  `:14278–14290`). Its premise was that an annotation had nothing to mean.
- A `defconst` has **no storage**. The `Sym` carries `is-const`, the IR text
  `const-val`, and W2b's provenance `const-lit`/`const-lit-i64`. A reference
  (`emit-symbol-ref-bound`, `:3888`) builds a `Val` from them tagged `is-lit`,
  so the name adapts at a use site exactly as the literal would.
- The readers of that provenance are the constant folder (`:13213`: array
  extents, `defvar` constant initializers, `--emit-cheader` extents), the
  `defvar` renderer (`:13738`, which refuses a constant at a non-integer
  type), `prescan-defconst-name` (`:17659`, G-0 forward references), the
  `.nuch` writer (`src/nuch.nuc:92`, verbatim), the C-header writer
  (`#define`), and `import-ct`. A constant survives `import-ct` because it is a
  substitution rather than a definition.
- The tree has 471 `defconst`s. Every one is an integer.
- `defvar`'s initializer has three tiers (docs/toplevel.md, `defvar` row):
  **constant** (literals, named constants, folded integer expressions,
  `(sizeof T)`, `(as T x)`, `&g`, `(array T …)` and `(S …)` aggregates);
  **run-time** (anything else, run once by `@__nucleus_init`); and
  **refused**. `(defvar :const NAME:T init)` places a constant-tier value in
  LLVM `constant` storage. 11 sites in `src/ lib/ examples/ tests/` use it.
- Float arithmetic is not in the constant grammar.
  `(defvar :const g:f64 (* 2.0 1.5))` is refused as a run-time initializer.

## 2. Prerequisite defects in `defvar :const` (found by this probe)

- **D1 — a field write to a `:const` global compiles and segfaults.**
  `(defvar :const g:Pt (Pt 1 2))` followed by `(set! (g 'x) 5)` compiles, then
  exits 139 when run. `emit-set` checks `readonly-global` only when the place
  is a bare name (`:10915`). docs/types.md:474 disclaims writes through `&x`
  pointers, but `(g 'x)` is direct syntax on the name itself.
- **D2 — `.nuch` exports a `:const` global as `(extern :const)`.**
  `emit-nuch-extern` (`src/nuch.nuc:172`) prints element 1 of the form, and on
  a `:const` global that is the attribute keyword. An importer therefore gets
  no declaration, and read-only status cannot cross a header at all, because
  `extern` has no `:const`.

Both fixes outlive the retirement of `defvar :const` (DC-5). The place check
keys on `readonly-global`, which tier A sets. `(extern :const NAME:T)` is how
a tier-A constant crosses a header, and it is also the right spelling for a C
`const` global.

## 3. The model

A `defconst` names a value that never changes. It takes `defvar`'s *constant*
initializer grammar, with an optional type annotation. **The value's shape
chooses the tier.**

### Tier L — a literal: substitution, no storage

This tier covers a value that is, or folds to, one literal: integer, float,
`"…"`, `c"…"`, character, `true`/`false`, `null`. The `Sym` gains a
`const-node` field that holds the folded literal. A reference **re-emits that
node at the use site**, so the name behaves exactly like the literal in every
position the literal already works in:

- a float adapts to an `f32` slot;
- `"…"` stays an unmaterialized `StrView` that decays to `CStr` for free;
- an integer keeps W2b.

This needs no provenance fields for each kind. A literal node contains no
names, so there is no hygiene question. Because this tier has no storage, it
works wherever today's integers work: macro bodies, `compile-time` blocks,
`import-ct`, the REPL, and AVR.

Integers keep `const-val`/`const-lit`/`const-lit-i64`, because the folders read
them. `node-type` of a constant name must answer `node-type` of its
`const-node`, the `node-type`↔`emit-node` lockstep
(context/conventions.md).

A tier-L constant has no address. `&K` is refused:
`&: constant 'K' has no storage; bind it with let or defvar to take an
address`.

### Tier A — a constant aggregate or address: read-only storage

This tier covers what `defvar-const-init-ir` renders that is not a single
literal: `(S …)`, `(array T …)`, `&g`, and `(as T x)` over a non-literal. It
is emitted as `defvar :const` is today: `@NAME = constant T …`, or `internal`
for `defconst-`, with `def-ir-base` naming. Reads go through the normal load
path. After D1, every write rooted at the name is refused.

Storage rather than substitution, because:

- a substituted table is a fresh stack copy at every use, so `(TABLE i)` would
  copy 1 KB to read 4 bytes;
- a table has to be passable by address.

The type comes from the annotation if one is given. Otherwise it is read off
the value: `(S …)` gives `S`, `(array T …)` gives `(array T N)`, `&g` gives
`&` of `g`'s type, and `(as T x)` gives `T`.

**`&NAME` yields a writable `&T`.** The language has no read-only pointer
kind, so a callee can write through it into read-only storage. This is the
hole `defvar :const` documents today (docs/types.md:474), and the docs carry
it across unchanged: the check covers syntax rooted at the name, not
aliasing. A read-only pointer kind is its own candidate item.

### Out of scope: run-time initializers

A value outside the constant grammar, such as a call or an allocation, is
refused: `defconst: 'NAME' needs a run-time initializer; a constant's value
must be known at compile time -- use defvar`. This is the refusal
`defvar :const` gives today (`:14186`), reworded, and the
`g3-init-const-storage` fixture moves onto it. A run-time tier (a binding set
once by `@__nucleus_init`, read-only afterwards, constness shallow) is
recorded in [deferred/overview.md](../deferred/overview.md).

### The annotation

`(defconst K:T v)` becomes legal and is parsed by `defvar`'s own
`extract-decl-name-and-type`, so every spelling a `defvar` name takes works
here. An annotated constant **has** type `T` and does not adapt. This is the
constraint literal-typing.md §W2b set for the case where an annotation was
ever accepted. A literal value is still range-checked (`int-literal-fits`). A
constant needs no declaration attributes, so `:const`, `:volatile` and
`:thread-local` are refused.

## 4. Where a constant is used

| Use | L | A |
|---|---|---|
| value position | the literal | load |
| `&NAME` | refused: no storage | the storage's address, writable (documented) |
| array extent, constant folder | integers fold, as today | refused: not a compile-time integer |
| `defvar` initializer | as the literal | inlines the rendered constant (stored on the `Sym`) |
| macro body, `compile-time` | yes | refused (`reject-ct-only`, like a program `defvar`) |
| `import-ct` | survives | dropped |
| `.nuch` | verbatim folded literal | `(extern :const NAME:T)` (needs D2) |
| `--emit-cheader` | `#define` in C spelling (float `%.17g`, escaped string) | `extern const T NAME;` |
| REPL | as today | as `defvar :const` today |

## 5. Retiring `defvar :const`

Every constant-tier `(defvar :const NAME:T init)` becomes
`(defconst NAME:T init)`. What changes for a scalar is that it no longer has
storage: it becomes an immediate, which on AVR is better than a flash read. Two
things go with that, and nothing in the tree depends on either outside the
tests that pin the storage class itself:

- a read-only *scalar* with an address, which is now `&K` refused;
- a linkable C `const` scalar, which is now `#define`.

After retirement, `(defvar :const …)` is refused with `defvar: ':const' was
retired -- write (defconst NAME:T init)`. The `DECL-ATTR-CONST` bit stays,
because tier A and `extern :const` set it internally.

The 11 sites:

- `examples/cstr-defvar.nuc:37` and `examples/avr-global-init.nuc:30` become
  tier L.
- `examples/avr-global-init.nuc:31` (an `(array ui8 4)`) becomes tier A, and it
  keeps its flash placement.
- `tests/suite-linking.nuc:480` pins a `.rodata` section. It moves to a tier-A
  aggregate.
- `tests/suite-cheader.nuc:121` pins `extern const int32_t limit;`. It splits
  into a scalar that pins `#define limit 99` and an aggregate that pins
  `extern const`.
- `tests/fixtures/avr6-const*.nuc` move to `defconst`. `-mutate-rejected`
  pins D1's message.
- `tests/fixtures/g3-init-const-storage.nuc` pins the run-time refusal above.
- The comments at `src/compiler-types.nuc:242` and `src/cheader.nuc:4667`
  follow.

## 6. Steps

- **DC-0 — D1 and D2.** These are independent and land first.
  - D1: `emit-set` refuses a place whose root name is `readonly-global`
    (field, index and nested chains) with the existing message. `aset` and
    `.set!` get the same check.
  - D2: `emit-nuch-extern` writes the declaration after the attributes and
    carries `:const`, and `extern` accepts `:const` and sets
    `readonly-global`.
  - Units: the D1 shape (`(set! (g 'x) 5)`, currently exit 139) is refused;
    a `.nuch` round trip of a `:const` global.
- **DC-1 — tier L.**
  - `const-node`, substitution in `emit-symbol-ref-bound`, the `node-type`
    lockstep, `prescan-defconst-name` registering every single-literal value,
    the folded integer expression (`(+ 2 3)`), the `&K` refusal, and the
    header writers.
  - Units cover every literal kind at every adapting position: `f32`
    let/arg/return; `StrView` and `CStr` slots; the `printf` vararg; a macro
    body; `import-ct`; a forward reference; a `.nuch` round trip; and
    `--emit-cheader`.
- **DC-2 — the annotation.** The two W4b refusal sites become the `defvar`
  name parser. `w4a-defconst-annotated` and `w4b-defconst-paren`
  (tests/manifest/diagnostics.sexp:265–268) flip from reject to accept, with a
  golden showing that an annotated constant does not adapt.
- **DC-3 — tier A, and the run-time refusal.** Tier A goes through
  `emit-defvar`'s storage path with `:const` semantics, reads its type off the
  value, and uses D2's extern for headers.
- **DC-4 (optional) — float folding** in the shared constant folder. This lets
  `(defconst TAU (* 2.0 PI))` stay in tier L, and `defvar` gains it too.
- **DC-5 — retire `defvar :const`.** Sweep the 11 sites (§5), add the
  retirement refusal, and update the docs.

Docs:

- docs/toplevel.md: the `defconst` row, and the `defvar` row's `:const` and
  run-time-refusal wording.
- docs/types.md: Const globals becomes a pointer to `defconst` and keeps the
  `&NAME` caveat. Integer literals and the W2b paragraph also change.
- docs/compiler.md: the header sections.

Gates: `make`, `make test`, `make bootstrap` converged, and
`ir-snapshot.sh verify` byte-identical for the compiler's own build. Adopting
the new tiers in `src/` or `lib/` waits for a boot refresh, since the boot
compiler builds `nucleusc` from both.

## 7. Decisions (2026-09-28)

1. **Retire `defvar :const`**: yes, as DC-5.
2. **`&NAME` on a tier-A constant**: keep the writable address and document
   it as `:const` does.
3. **Run-time initializers**: out of scope for now. They are refused and
   recorded as deferred.

## 8. As built (2026-09-28)

Differences from §3–§6:

- **`&K` message.** It reads `ref: constant 'K' has no storage -- bind it with
  let or defvar to take its address`. Before this item, `&K` on an integer
  `defconst` emitted invalid IR (`expected value token`).
- **A `defvar` initialized from a tier-A constant reads it at startup.** It is
  a run-time initializer, not an inlined copy of the rendered constant (§4
  said "inlines"). So on AVR, `(defvar g:Pt ORIGIN)` is refused; name the
  aggregate literal instead.
- **Macro bodies and `compile-time` read tier A.** §4 said refused; both
  work, and a macro body reads the constant's real value.
- **`import-ct` withholds tier A the way it withholds a `defvar`.** A program
  use is the located `imported compile-time-only` error. This needed a
  pre-existing bug fixed first: `emit-symbol-ref-bound` checked `ct-only` only
  for `is-local = 0`, and every global is `is-local = 1`. So a withheld
  `defvar`, read or taken with `&`, emitted a load of an undefined `@name`.
  The check now runs for every non-constant reference and in `emit-ref`.
  Unit: `s16-import-ct-global-read-refused`.
- **Arrays.** `&TABLE` is `&(array T N)`. A bare `TABLE` decays to `&T`, as a
  `defvar` array does. Passing a struct constant to a `&S` parameter uses the
  implicit lvalue address-of, which is the same writable-address hole as `&NAME`.
- **Writes refused.** `emit-set` refuses `set!` on a tier-L name before its
  `is-local` check; it used to say `undefined local`. `inc!`/`dec!` get the same
  refusal.
- **Headers.**
  - `.nuch` writes a tier-A constant as `(extern :const (NAME Type))`, in list
    form, from the source's own type node. A namespaced struct key would
    otherwise render as `ns/Pt`.
  - The C header writes a float from its source lexeme, not `%.17g`. A lexeme
    C cannot read is omitted with a comment.
  - The C header avoids `cheader-type-c`, which spells a namespaced struct by
    its registry key (`struct cl__cl_Pt`). Both writers use
    `defconst-type-node` (a synthesized `(array T N)`, the struct head, or the
    annotation).
- **D2 also fixed `:volatile`.** `emit-nuch-extern` dropped the declaration
  after *any* leading attribute, so `examples/logic.nuc`'s `.nuch` read
  `(extern :volatile)`. It is now `(extern :volatile trap-zero:i32)`.
- **DC-4 not built.** `(defconst TAU (* 2.0 PI))` is refused as a run-time
  initializer. Float folding in the shared folder would lift it, for `defvar`
  too.

Tests:

- `examples/defconst-values.nuc` (golden) covers every literal kind at an
  adapting position, the annotation, tier A, and forward references.
- Eleven `dc-*` reject rows cover the refusals in
  `tests/manifest/diagnostics.sexp`.
- `dc-defconst-*` units in `tests/suite-exports.nuc` cover `.nuch`, the C
  header, a link-and-run round trip, and an importer's write being refused.
- `w9-cheader-*` pin `#define limit ((int32_t)99)` beside an aggregate
  `extern const` that a C consumer reads.
- `w4a-defconst-annotated` flipped to accept. `w4b-defconst-paren` now pins the
  doubled-annotation error that `defvar` gives for `x:(i32)`.

IR snapshot: every differing artifact is a fixture or example this item edited,
plus `examples/logic`'s `.nuch` (the D2 fix above). The compiler's own `.ll` is
unchanged, and `make check-headers` passes.
