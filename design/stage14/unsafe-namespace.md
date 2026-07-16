# Stage 14 — The `unsafe` namespace and the `as` form

Nucleus deliberately keeps unchecked operations — it is a C replacement — but
today the most dangerous one hides in plain sight. A single `cast` form covers
everything from a no-op re-typing to `inttoptr`, silently truncating integers
and laundering nullable `raw` pointers into non-null `ref`s with **zero IR and
zero checking**. Because the overwhelming majority of `cast` sites are safe
ceremony (widening a loop index, re-attaching a statically-known element type),
grepping for `cast` as an audit tool has terrible signal: ~5,300 sites of which
only a small minority can actually go wrong.

This stage splits the spelling by risk:

- **`as`** — a new form for *statically safe* conversions: everything the
  implicit-coercion machinery already accepts, plus pure pointer-contract
  weakening. Refuses anything lossy or contract-manufacturing, and honors the
  nullability flow check that `cast` bypasses.
- **`unsafe/cast`** — today's `cast`, verbatim semantics, honest name.
- The other *always*-unsafe forms (`funcall-ptr-*`, `ptr+`,
  `unsafe-import-private`) move under the same `unsafe/` prefix.

After the migration, `grep -rn 'unsafe/' src lib` enumerates every
contract-subverting site in the tree — the audit trail Stage 10 promised.

**Lineage.** stage10/safety.md §1 resolved *"`unsafe` is a naming convention,
not an enforced lexical construct, in this stage"* and deferred the real
gathering: *"Relegate raw ops to an `unsafe/`-named namespace/library"*, with
flip.md noting *"no `unsafe` namespace yet — arrives with namespaces"*. Stage 12
delivered namespaces. The stage888-deferred.md "`unsafe` lexical block" entry
records the same plan. This doc is the follow-through; the *enforced block*
remains deferred (§Rejected).

---

## 1. Ground truth (verified against the tree, 2026-07-02)

1. **One `cast` form, no checks.** `emit-cast` (nucleusc.nuc:1623-1687),
   dispatched by interned-head identity at nucleusc.nuc:6314; `node-type-cast`
   (generics.nuc:3105) just returns the parsed target type. The conversion
   ladder, in order:

   | Case | Emitted IR |
   |---|---|
   | same `TypeKind` — incl. **ptr↔ptr any elems, raw↔ptr, ptr↔ref** (:1633) | none (reinterpret) |
   | ptr-like ↔ ptr-like, CStr↔ptr (:1638); fn ↔ ptr (:1645) | none |
   | int→int same width, different sign (:1653) | none |
   | int→int narrowing (:1656) | `trunc` |
   | int→int widening (:1658) | `zext`/`sext` by source sign |
   | int→ptr (:1661) / ptr→int (:1663) | `inttoptr` / `ptrtoint` |
   | float↔float (:1666) | `fpext`/`fptrunc` |
   | int→float (:1673) / float→int (:1678) | `uitofp`/`sitofp` / `fptoui`/`fptosi` |
   | anything else (:1682) | compile error |

   The only "check" is that the kind pair is in the ladder. No range check, no
   null check, and — the load-bearing hole — **`emit-cast` never calls
   `pkind-flow-check`**: `(cast ptr:Sym someRaw)` launders nullable `raw` into
   non-null `ref` silently (docs/types.md:61 calls this the "unchecked
   promise").

2. **The safe-conversion machinery already exists.** `safe-coerce-val`
   (nucleusc.nuc:1390) is the canonical call-site/return coercion: identity,
   int↔int via `coerce-int-val` (abi.nuc:428 — which, unlike `cast`, **does**
   call `pkind-flow-check` for `(ref T)` destinations), f32→f64 `fpext`, and
   user `defcast` rules (`register-cast-rule`/`lookup-cast-rule`/`g-cast-rules`,
   nucleusc.nuc:1370-1457; `defcast` explicitly rejects declaring the built-in
   pairs). `binop-coerce` (nucleusc.nuc:1466) handles operator widening. `as`
   is a thin explicit wrapper over this machinery, not a new rule set.

3. **Special forms dispatch on the raw interned head, before namespace
   resolution.** The ladder at nucleusc.nuc:6280-6392 compares `(head s)` by
   pointer identity against quoted symbols; `qualify-name` (nucleusc.nuc:1720)
   runs only inside global `scope-define`/`scope-lookup` (scope.nuc:18,:45).
   Since `/` is an ordinary symbol character, `unsafe/cast` reads as a single
   `NODE-SYM` with **no reader change**, and routing it is one more identity
   compare in the ladder. Real namespace machinery never sees special forms —
   so `unsafe/` here is a *pseudo-namespace*: a reserved spelling in the
   special-form table, not a resolvable module (§D1).

4. **Census and the Stage-14 interaction.** `(cast ` sites: **src/ 3,680,
   lib/ 1,093, examples/ 527, tests/ 42** (~5,340). Pointer-targeted ~66%
   (`ptr` 983, `ptr:Node` 863, `ptr:ptr` 556, `ptr:Type` 276, `ptr:Val` 119, …)
   — almost all same-kind reinterprets re-attaching statically-known types.
   Integer-targeted ~32% (`i64` 836, `usize` 351, `ui32` 210, `i32` 207, …) —
   overwhelmingly literal/counter widening and sign reinterprets. Float/CStr/
   raw/ref targets are noise (<1%). **Most of these sites are scheduled for
   deletion, not renaming**: type-safety 14.1-14.3 deletes the ceremonial
   pointer casts by typing fields/params, MC-3 deletes the macro casts, LW-5
   sweeps the ~991 vestigial int casts. The split sweep here (UN-4) touches
   only the survivors — which is exactly why it sequences after them (§7).

5. **The always-unsafe inventory.** All special forms
   (`g-special-form-set`, nucleusc.nuc:9028-9062): `funcall-ptr-1/-i32/-i64/
   -ptr` (nucleusc.nuc:2445/2460/2471/2482) — type-erased indirect calls that
   *assume* a signature, only checking the operands are `ptr`; `ptr+`
   (union-emit.nuc:1571) — unchecked `getelementptr` arithmetic; `aref`/`aset!`
   (nucleusc.nuc:2303/2332) — unchecked indexing; `deref`/`ptr-set!`
   (nucleusc.nuc:2545/2558) — raw loads/stores (typed-ptr-gated, and `deref`
   calls `require-derefable`, but no null check on `raw`); `alloca` (:2284),
   `addr-of` (:2378, escape-checked since Stage 13), `funcall`/`funcall-void`
   (:2536/:2435, typed fn-pointer calls), `invoke` (:2260);
   `unsafe-import-private` (toplevel form). There is no `transmute`/`bitcast` —
   `cast` is the sole reinterpret form. Manual `free` is a libc function, not a
   form.

6. **`as` is unclaimed.** No form, binding, or import keyword named `as`
   anywhere in src/lib/examples/tests. The adjacent `as-ref` (dispatch
   nucleusc.nuc:6334) is the *runtime-checked* raw→`(Maybe (ref T))` launder —
   it completes the family rather than conflicting (§D5).

---

## 2. Non-goals

- **No enforced `(unsafe …)` lexical block.** Still deferred
  (stage888-deferred.md entry stands). The namespace delivers the grep/audit
  value now; a future block can consume the roster this stage creates.
- **No change to implicit coercion.** Call-site adaptation, binop widening,
  literal typing, the elem-less-`ptr` `void*` flow exemption
  (`pkind-flow-check`, type-utils.nuc:274) all stay exactly as they are. `as`
  is an explicit spelling of existing rules, not a new checker.
- **No runtime checks added anywhere** (zero-mandatory-cost invariant).
  Range-checked narrowing is deferred to a future `try-as` (§Deferred).
- **No type renames.** `(raw T)`, bare `ptr`, `CStr` spellings are untouched;
  the pointer-kind system already carries the pointer-contract story.
- **Not a general unsafe-effect system.** Functions built *on* unsafe ops
  (allocators, collections internals) do not become `unsafe/`-named; the
  boundary is the primitive operation, and the library's safety is its API
  contract.

---

## 3. Design decisions

### D1 — `unsafe` is a reserved pseudo-namespace

`unsafe/<op>` heads are routed by the special-form dispatch ladder exactly like
today's bare heads (one identity compare each; `'unsafe/cast` is an ordinary
quoted symbol). No `import` is required — like every special form, they are
unconditionally available. To keep the spelling unambiguous:

- `(ns unsafe)` is a compile error ("'unsafe' is reserved"), so no user global
  can ever be stored under an `unsafe/` key.
- The greppable audit surface is the literal prefix `unsafe/`.

*Why not a real namespace member?* Special forms are not scope-resolved
(ground truth 3); making their availability import-conditional would add
resolver complexity, break "special forms are always available", and buy no
additional auditability — grep works the same either way. *Why `/` and not
`.`?* Qualified names in Nucleus are spelled with `/` (`geom/area`); dots are
import-*path* syntax only (stage12/namespaces.md). A dotted head would need new
reader rules for zero gain.

### D2 — the roster: three classes

**Class 1 — split (safe and unsafe uses share one name today):**

| Old | New |
|---|---|
| `cast` (safe subset) | `as` |
| `cast` (everything else) | `unsafe/cast` |

**Class 2 — moved wholesale (always unsafe):**

| Old | New |
|---|---|
| `funcall-ptr-1` / `-i32` / `-i64` / `-ptr` | `unsafe/funcall-ptr-1` / `-i32` / `-i64` / `-ptr` |
| `ptr+` | `unsafe/ptr+` |
| `unsafe-import-private` | `unsafe/import-private` |

`funcall-ptr-*` assume a call signature out of thin air — the wildest ops in
the language. `ptr+` *manufactures a pointer* at an unchecked offset (its
result escapes as a contract-carrying value, unlike an `aref` element read).
`unsafe-import-private` already self-identifies; the move is spelling
consistency.

**Class 3 — stays bare (with the criterion):** `deref`, `ptr-set!`, `aref`,
`aset!`, `alloca`, `addr-of`, `funcall`/`funcall-void`, `invoke`.

The criterion: **a form moves under `unsafe/` iff its name alone does not
identify the hazard, or one name covers both safe and unsafe uses.** Class 3
fails both prongs: each name is unique, greppable, and always means exactly
what it says; their residual hazard is carried by the *operand type* (`raw` vs
`ref` — the Stage 10 kind system marks it, and `deref` on a `(ref T)`,
`addr-of` under Stage 13 escape analysis, and `funcall` through a *typed* fn
pointer are as checked as the language gets). These are also the C-parity
bread-and-butter: prefixing raw array access in a systems language would turn
ordinary code into a wall of `unsafe/` and destroy the very signal the
namespace exists to provide. (Bounds-checked debug builds are the better
long-term answer for `aref`/`aset!` — §Deferred.)

### D3 — `as`: the statically-safe conversion form

`(as TYPE expr)`, same shape as `cast` (exactly 2 args, colon-paren sugar
applies). Acceptance rule, stated once:

> **`as` accepts exactly (a) what the implicit coercion machinery would accept
> in an assignment position, plus (b) pure pointer-contract weakening — and
> nothing else.**

Concretely:

| Conversion | IR | Rule source |
|---|---|---|
| identity / same type | none | (a) |
| int→int widening | `zext`/`sext` by source sign | (a) `coerce-int-val` |
| int→int same width, different sign | none | (a) — parity with implicit (OQ1) |
| f32→f64 | `fpext` | (a) `safe-coerce-val` |
| user `defcast` rules | per rule | (a) `g-cast-rules` |
| CStr ↔ ptr-like | none | (a) `coerce-int-val` |
| elem-less bare `ptr` → typed (the `void*` hatch) | none | (a) flow exemption |
| `(ref T)` → `(raw T)`; typed ptr → elem-less bare `ptr` | none | (b) weakening |

Rejected by `as`, with error messages that route to the right tool:

- **narrowing / truncation, float→int, f64→f32** — "lossy conversion: use
  `unsafe/cast`" ;
- **`(raw T)` → `(ref T)`/`(ptr T)`** — "raw pointer where non-null is
  required: narrow it, use `as-ref` (checked), or `unsafe/cast` (unchecked
  assertion)" — i.e. `as` **honors `pkind-flow-check`**, closing the laundering
  hole for the safe spelling;
- **ptr↔int, fn↔ptr, element-retyping ptr↔ptr** — "reinterpretation: use
  `unsafe/cast`".

Implementation: `emit-as` = parse target type, run `safe-coerce-val` extended
with the two weakening rules; `node-type-as` mirrors `node-type-cast`
(the **node-type↔emit-node lockstep** applies — conventions.md). `as`
preserves `cast`'s taint-copy behavior for `with`-owned pointers (reinterprets
copy escape taint).

Why include the same-width sign reinterpret: the implicit machinery already
performs it silently at every call boundary; an explicit form *stricter* than
the invisible rules would be incoherent. It is lossless bitwise (recorded as
OQ1 in case the implicit set is ever tightened).

### D4 — `unsafe/cast` is today's `cast`, verbatim

Same emitter, same conversion ladder, same absence of checks — only the
spelling changes. Its accepted set is a strict superset of `as`'s, so a
migration is never blocked by classification: when in doubt, `unsafe/cast`
compiles. It deliberately does **not** reject as-safe conversions (that would
require the sweep to know exact operand types up front and would break
macro-generated code); a "this could be `as`" lint is a possible later tier
(OQ5).

### D5 — the conversion family, complete

| Spelling | When | Checking |
|---|---|---|
| *(implicit)* | assignment/call/return/binop positions | safe set, invisible |
| `as` | explicit safe conversion or contract weakening | static; refuses lossy/laundering |
| `as-ref` | nullable `raw` from C → `(Maybe (ref T))` | runtime null check |
| `defcast` | user-declared conversions | extends the safe set (implicit *and* `as`) |
| `unsafe/cast` | reinterpret, truncate, ptr↔int, launder | none — the signed waiver |

### D6 — the bare spellings are retired at the end

Pre-release rules apply (AGENTS.md): after the sweep, bare `cast`,
`funcall-ptr-*`, `ptr+`, and `unsafe-import-private` become **targeted hard
errors** naming the replacement ("`cast` was split in Stage 14: use `as`
(safe) or `unsafe/cast` (unchecked)"), not silent unknown-form fallthroughs.
The boot chain is handled by the standard dual-accept → refresh → rewrite →
error sequence (§4), mirroring defn-signature's S1→S4.

---

## 4. Phased build plan

Dispatch per [context/local.md](../../context/local.md); every
compiler-touching prompt directs the agent to read
[context/conventions.md](../../context/conventions.md) first.

### UN-1 — the `as` form *(additive; byte-identical)*

**Agent: systems-impl-engineer** (coercion machinery + lockstep). Add `emit-as`
(wrapping `safe-coerce-val` + weakening rules + `pkind-flow-check`), the
dispatch entry, `g-special-form-set` membership, and `node-type-as`
(lockstep with the emit side). Diagnostics route per D3. New example
`examples/as-conversions.nuc` (accepted set end-to-end) + expected output;
negative diagnostics exercised the way existing error-path tests do it.
No source uses `as` yet → bootstrap byte-identical.

**Status (2026-07-14): DONE.** `emit-as` + helpers `as-retype` / `as-die-flow`
/ `as-ptr-convert` land right after `emit-cast` (src/nucleusc.nuc). The emitter
is an explicit 8-step ladder, *not* a blind wrapper of `safe-coerce-val`: it
reuses the existing machinery (`coerce-int-val` for int-widening and the StrView
collapse, an inline `fpext` for f32→f64, the `lookup-cast-rule` `defcast` call,
and `is-ptr-like`/`ptr-pkind`/`type-eq` for the pointer classification) but
gates each case so the *rejected* subset (narrowing, float→int, f64→f32,
raw/nullable→non-null laundering, ptr↔int, fn↔ptr, element-retyping ptr↔ptr)
dies with a routing diagnostic instead of silently coercing. Two subtleties
drove the design:

- **`safe-coerce-val` is too permissive to delegate to wholesale.** Its
  `sk==dk` identity branch returns the operand *typed as the source*, and for
  two `TY-PTR` types that means it would accept a `(raw T)`→`(ref T)` launder or
  a `%Foo`→`%Bar` reinterpret as "identity". And `coerce-int-val` happily
  `trunc`s a narrowing. So `as` routes every pointer pair through
  `as-ptr-convert` (which honors the `pkind-flow-check` obligation the D3 table
  demands and rejects element-retyping) *before* any `type-eq` short-circuit,
  and rejects int narrowing by width *before* calling `coerce-int-val`.
- **`type-eq` ignores pkind** (generics.nuc:114 compares only the pointee), so a
  `type-eq`-based identity fast path would launder `(raw T)`→`(ref T)`. The
  identity fast path (step 3) therefore only runs *after* the pointer step has
  consumed every pointer pair; it is reached only by non-pointer same-type
  values.

Dispatch: `'as` → `emit-as` (nucleusc.nuc emit-list ladder) and `'as` →
`node-type-as` (generics.nuc node-type ladder); `"as"` added to
`g-special-form-set` (73 members). Colon-paren sugar needed **no** work — the
reader's `fuse-colon-paren` (lib/reader.nuc) fuses a colon-chain type argument
(`ptr:(Vector T)` → `(ptr (Vector T))`) for *every* list element regardless of
head, so `(as ptr:Rec p)` / `(as raw:Rec r)` parse for free exactly as they do
for `cast`.

**Lockstep:** `node-type-as` returns `parse-type-from-node` of the target node —
identical to `node-type-cast`. This is correct because `emit-as` returns a Val
typed *exactly* the parsed target type on every accepted path (int widening →
`coerce-int-val target`; f32→f64 → `alloc-val target`; defcast →
`alloc-val target`; every pointer/identity path → `as-retype …dst`; StrView →
`coerce-int-val target`). The rung-3 override (nucleusc.nuc:930, emit-node
replaces a node's propagated type with `node-type`'s answer when non-null) then
sets the same type it already had — a no-op — so the passes cannot drift. A
*rejected* `as` dies in `emit-as` before propagating a type, exactly as an
unsupported `cast` dies in `emit-cast`, so node-type-as returning the target for
a would-be-rejected form (it does not re-check acceptance) never surfaces.

Verification: `make` succeeded in one pass with the committed boot (the "new
special-form the OLD boot can't bridge" scenario did **not** occur — UN-1 is
purely additive and no `src/` uses `as`), `make bootstrap` is byte-identical
(stage1.ll == stage2.ll, no `update-bootstrap`), `make test` is **172/172**
(168 baseline + `examples/as-conversions.nuc` + 3 rejection fixtures
`tests/fixtures/as-{lossy,raw-to-ref,reinterpret}.nuc`). The three routing
diagnostics, verbatim:
- lossy: `as: lossy conversion from i32 to i8 -- use unsafe/cast`
- launder: `as: raw pointer ptr:Rec where non-null ptr:Rec is required -- use as-ref (checked) or unsafe/cast (unchecked assertion)`
- reinterpret: `as: reinterpretation from ptr:Sym to ptr:Rec -- use unsafe/cast`

(`type-spelling` collapses pkind, so both `raw:Rec` and `ref:Rec` render
`ptr:Rec` in the launder message — cosmetic; the routing to `as-ref` is intact.)

### UN-2 — `unsafe/` routing + reservation *(additive; byte-identical)*

**Agent: focused-task-implementer.** Add head-identity routes and
`g-special-form-set` entries for `unsafe/cast`, `unsafe/funcall-ptr-1/-i32/
-i64/-ptr`, `unsafe/ptr+`, `unsafe/import-private` — each falling into the
existing emitter beside its bare alias (which stays accepted for now). Reserve
the namespace: `(ns unsafe)` → die-at. New-code convention flips here: from
UN-2 on, new code uses the new spellings.

**Status (2026-07-14): DONE.** Every new `unsafe/<op>` head is an added `or`
arm on the existing `(when (= hp 'bare-alias) …)` test, in both dispatch
ladders that must stay in lockstep (conventions.md):

- **emit-list** (`src/nucleusc.nuc`, the same ladder UN-1 landed `as` in):
  `(when (or (= hp 'cast) (= hp 'unsafe/cast)) (return (emit-cast n scope)))`,
  and the equivalent `or` for `funcall-ptr-1`/`-i32`/`-i64`/`-ptr` and `ptr+` —
  each calling the *identical* `emit-*` function as its bare alias, zero
  reimplementation.
- **node-type** (`src/generics.nuc`): the same `or` pattern added to the
  `node-type-cast`/`ty-ptr`/`ty-i32`/`ty-i64`/`node-type (node-at n 1) scope`
  branches for `cast`/`funcall-ptr-*`/`ptr+` respectively — required by the
  node-type↔emit-node lockstep (conventions.md); a `unsafe/cast` the emitter
  accepts must type identically in the non-emitting pass.
- **`unsafe/import-private`** is not an emit-list/node-type expression — it's a
  toplevel form dispatched by the `case hp` ladder in `emit-toplevel-forms`
  (`src/nucleusc.nuc`) — so it needed a different shape: a **duplicate `case`
  arm** `'unsafe/import-private (emit-unsafe-import-private (cast ptr f))`
  right after the existing `'unsafe-import-private` arm (a `case` clause is
  one key per body, unlike `cond`'s `or`-friendly test position). It also
  needed a matching addition to `prescan-imported-types`'s import-head string
  check (`(= ph "unsafe/import-private")`) — the toplevel-type-prescan walk
  that recognizes every import-shaped form to pre-register the imported unit's
  struct names ahead of this unit's own signature prescan; missing this would
  have left `unsafe/import-private`'s imported types invisible to signatures
  in the *same* file, a silent gap rather than a compile error.
- **`g-special-form-set`** gained all 7 new spellings, grouped together with a
  comment rather than interleaved with their bare aliases, so the roster added
  by this phase stays visually greppable. (The set's header comment claimed
  "73 members" pre-UN-2, but the actual list had drifted to 86 well before
  this phase — stale since at least before UN-1, which inherited and merely
  incremented the wrong figure. Corrected here to the true count: 86 → 93.)
- **`(ns unsafe)` reservation**: `emit-ns` (`src/nucleusc.nuc`) now checks
  `(= (name-node s) "unsafe")` immediately after the existing
  slash-in-namespace-name guard, `die-at`ing `'unsafe' is a reserved namespace
  name`. `name-node s` is a `ptr` (identity-substrate `Node.s`) compared
  against a string literal — the mixed-operand rule (conventions.md) fires the
  content-comparing `strcmp` lowering here, not identity, exactly like the
  neighboring `(= h "defn-")`-style checks elsewhere in the same dispatch
  loop; this is a content check on purpose (the *spelling* "unsafe" is
  reserved, not any particular interned Node instance).

Verification: `make` (the current committed boot compiler) succeeded in one
pass — this is another "new special-form dispatch symbol" scenario like UN-1,
and again did **not** need the 2-stage manual bootstrap workaround, since
nothing in `src`/`lib` references any `unsafe/*` spelling yet. `make
bootstrap` is byte-identical (stage1.ll == stage2.ll, no `update-bootstrap`).
`make test` is **174/174** (172 UN-1 baseline + 2 new): the positive
`examples/unsafe-spellings.nuc` runs `unsafe/cast` (same-width sign
reinterpret), `unsafe/ptr+` (pointer arithmetic — writes through a `ptr+`-
computed address are visible through the matching `unsafe/ptr+` address, since
both compute the identical offset), `unsafe/funcall-ptr-i32` (an indirect call
through a function-pointer value obtained via `(cast ptr some-zero-arg-defn)`,
which lowers to a no-IR `TY-FN`→`ptr` reinterpret), and `unsafe/import-private`
(pulling in both the public *and* the private symbol of a new two-symbol demo
library, `lib/unsafe-priv-demo.nuc`, under a prefix — proving the private
symbol crossed the `g-import-include-private` gate that a plain
`import-prefixed` would have filtered) — each printed back to back with its
bare-spelling counterpart, and the outputs are byte-identical pairs:

```
cast            = 4294967295
unsafe/cast     = 4294967295
ptr+            = a=30 b=40
unsafe/ptr+     = a=30 b=40
funcall-ptr-i32 = 42
unsafe/funcpi32 = 42
pd/pub-double   = 42
pd/priv-secret  = 99
```

The rejection fixture `tests/fixtures/unsafe-ns-reserved.nuc` (`(ns unsafe)`
as the leading form) dies with the exact designed message: `'unsafe' is a
reserved namespace name`.

**Deliberately out of scope, left for UN-3/UN-4:** two structural recognizer
helpers also pattern-match the bare spellings for def-time/syntactic purposes
— `gcheck-special-form` (`src/generics.nuc`, recognizes a special-form head so
the generic-template A2 body walk doesn't treat it as an unresolved function
call) and `is-libc-alloc` (`src/nucleusc.nuc`, recognizes a `cast`-wrapped
allocator call as a `with`-binding init). Neither was touched — the task's
explicit roster was head-identity routes + `g-special-form-set` + the `ns`
reservation, not every place `'cast`/`'ptr+` is compared in the compiler. A
practical consequence: `(unsafe/cast T x)` used inside a *generic template
body*, or a `with`-binding init spelled `(with (p:ptr (unsafe/cast ptr
(malloc …))) …)`, would not be recognized by those two helpers today (the
first would report an unresolved-function error in the A2 walk; the second
would just not detect the allocator idiom for whatever purpose it uses that
for). Neither surfaced in this phase's tests since no such usage was written
against the new spellings. If UN-3/UN-4's tree-wide migration hits either
gap, extend both helpers with the same `or`-arm pattern used everywhere else
in this phase.

### UN-3 — boot refresh + Class-2 migration *(one controlled refresh)*

**Agents: build-test-runner (refresh), focused-task-implementer (sweep).**
One reconverging refresh (`make update-bootstrap` + reconverge) so the boot
compiler accepts the new spellings; then rewrite the small Class-2 population
tree-wide (`funcall-ptr-*` in the defmacro/JIT plumbing, `ptr+` in the
collections internals, `unsafe-import-private` sites). Plain head renames are
IR-inert (verify per file with the `build/nucleusc.ll` diff); heads inside
quasiquoted macro bodies shift the string pool (conventions.md gotcha) — those
files take the standard reconverging refresh.

**Status (2026-07-14): DONE.** The boot refresh had already landed in the
prior step of this milestone (`boot/nucleusc.ll` + the two Windows boot IRs
already carry `unsafe/*` string constants), so this phase was a pure
mechanical sweep: every bare Class-2 call site in `src/`/`lib/` rewritten to
its `unsafe/`-prefixed spelling, same emitter, zero semantic change.

- **`ptr+` → `unsafe/ptr+`: 79 sites** across `lib/arena.nuc` (1),
  `src/scope.nuc` (2), `src/nuch.nuc` (1), `lib/keyword.nuc` (2),
  `src/cheader.nuc` (7), `src/repl.nuc` (5), `lib/string-split.nuc` (2),
  `lib/string.nuc` (5), `lib/node.nuc` (3), `src/union-registry.nuc` (4),
  `lib/strview.nuc` (6), `lib/reader.nuc` (4), `src/generics.nuc` (4),
  `src/nucleusc.nuc` (33).
- **`funcall-ptr-*` → `unsafe/funcall-ptr-*`: 4 sites** —
  `src/nucleusc.nuc:6683` (`funcall-ptr-1`, the macro-JIT invocation path) and
  `src/repl.nuc:539/543/547` (`funcall-ptr-i32`/`-i64`/`-ptr`, the REPL's
  result-printing dispatch).
- **`unsafe-import-private` → `unsafe/import-private`: 0 sites.** Re-grepped
  per the task's instruction to confirm rather than assume — every remaining
  hit in the tree is a comment, the `emit-toplevel-forms` case arm, the
  `prescan-imported-types` string check, or the `emit-unsafe-import-private`
  definition itself (all UN-2 territory, correctly left alone); no library
  or compiler source actually invokes the form, so there was nothing to
  rewrite for this member of the roster.
- **Macro-body check:** every file touched was audited for `defmacro` forms
  with quasiquoted bodies (the conventions.md string-pool-shift gotcha).
  `lib/arena.nuc` and `lib/string-split.nuc` do define macros (`new`,
  `doseq-split`), but their `ptr+` sites sit in ordinary functions earlier in
  the file, outside any backtick template. `src/nucleusc.nuc`, `src/repl.nuc`,
  and `src/nuch.nuc` only contain `"defmacro"` as a case-dispatch string
  literal (the compiler's own `emit-defmacro` machinery), not an authored
  macro body. No edited call site landed inside a quasiquoted form.
- **Verification:** `grep -rn '(ptr+ |(funcall-ptr-[1i]' src lib | grep -v
  unsafe/` returns only the three comment-line mentions in
  `src/nucleusc.nuc:2884/2899/2910` (prose, correctly untouched). `make clean
  && make` succeeded in one pass. `make test` is **174/174** (unchanged from
  the UN-2 baseline — a pure spelling sweep adds no new tests). `make
  bootstrap` converged **byte-identical on the first try** (stage1.ll ==
  stage2.ll) — no macro-body sites meant no reconverging refresh was needed,
  and `boot/nucleusc.ll` was left untouched by this phase (already current
  from the prior step), matching the task's guidance not to run
  `update-bootstrap` redundantly.

### UN-4 — the `cast` split sweep *(after the deletion work — see §7)*

**Agent: focused-task-implementer** per file cluster; build-test-runner gates.
Runs only **after** MC-3, LW-5, and type-safety 14.2/14.3 (recommended: after
all of T) have deleted the ceremonial majority. For each surviving
`(cast T x)`: classify by the **source** value's type — if the D3 set accepts,
rewrite to `(as T x)`; else `(unsafe/cast T x)`. The known raw→ref laundering
sites (the stage-10 C1 ~25 `cast ptr:Sym` waivers) become explicit
`unsafe/cast` — or graduate to `as-ref`/narrowing where that is a one-line
improvement. Both spellings emit byte-identical IR to the `cast` they replace,
so the per-file IR-identity diff is the gate; a mis-classification is caught by
`as`'s checker at compile time, not by IR drift. Macro-body sites → refresh
rule as in UN-3.

**Status (2026-07-15): DONE.** All prerequisites (type-safety 14.1-14.7, MC-1-4,
LW-1-6, defn-signature S1-S4) were complete, unblocking the sweep. Worked file
cluster by file cluster (`src/` 13 files, `lib/` 18 files, then `examples/` +
`tests/` in one bulk batch given ~70 small files) with a bulk-convert-`(cast `
→`(as `-then-fix-via-compile-error loop: `as`'s checker rejects an unsafe
conversion with a diagnostic naming the exact line and reason, so every
misclassification surfaced as a compile error to fix, not silent IR drift —
in practice a stronger, faster-converging gate than the per-file IR-identity
diff the design sketched, since it needs no snapshot/diff tooling and the
`unsafe/cast` fallback (D4: a strict superset of `as`, never rejects) means
an uncertain site can always be resolved by falling back to it with zero risk
of a wrong answer, only a slightly less precise classification.

**Site counts:** src/ 2,568, lib/ ~603, examples/+tests/ ~306 — 3,477 sites
classified total (the ground-truth §1.4 census's ~5,340 estimate, less the
~1,860 the 14.2/14.3/MC-3/LW-5 deletion work already removed before this
phase started). The large majority became `as`; a substantial minority
`unsafe/cast`, dominated by a handful of recurring shapes: `node-at`/`.car`/
`.cdr` AST-cursor results and bare `ptr`-typed function parameters (nullable/
raw, not `as`-eligible against a non-null target — the single largest
category by far), `usize`/`i64`→`i32`/`i8` narrowing (`count`/`strlen`/
`sizeof`/`ptr-bytes` results), int↔ptr reinterprets (pointer-arithmetic
idioms, JIT addresses, `funcall-ptr-*` targets), fn↔ptr reinterprets
(type-erased hook installation, indirect-call targets), and struct fields
typed `(raw T)` (`Type.sdef`, `Type.elem`, `Val.type`, `Field.type`) cast to
a non-null target — the raw→ref laundering class D2 anticipated, just far
more numerous in practice than the "~25 `cast ptr:Sym` waivers" estimate
(that figure was scoped to one specific target type; the general pattern
recurs for every struct-typed field across the compiler).

**Two real, previously-unknown gaps surfaced and were fixed, not routed
around:**
1. **`gcheck-special-form` didn't recognize the `unsafe/` roster inside
   generic template bodies** — exactly the gap UN-2/UN-3 flagged and
   deliberately deferred ("a generic-template body... written with the new
   `unsafe/` spelling would not be recognized... a gap for UN-3/UN-4 to
   close if it matters" — it did). Hit immediately on `vector-new-in`'s
   heap-placement cast; without the fix, `(unsafe/cast T x)` inside *any*
   `&where`-bounded or receiver-tyvar template body died `in generic body:
   unknown function 'unsafe/cast'` in the A2 checker. Fixed by adding `as`
   and the four `unsafe/*` forms to `gcheck-special-form` (src/generics.nuc)
   alongside their bare counterparts — closing this once unblocked every
   subsequent collection template (`hashmap-new-in` needed the identical
   fix pattern with zero further gcheck work). Required the standard
   2-stage bootstrap: temporarily revert the one call site the OLD boot
   couldn't yet compile, build + `update-bootstrap` with the gcheck fix
   itself (which the OLD boot *can* compile, since it's ordinary source),
   then re-apply and rebuild from the new boot.
2. **int↔float is not in `as`'s safe set at all** (confirmed from the D3
   table, not assumed: only `f32→f64` float-widening is listed — no
   int→float or float→int in either direction). `lib/parse.nuc`'s `parse`
   macro (`` `(from-str (cast ~ty 0) ~sv)` ``, instantiated with a concrete
   type at every call site) needed `unsafe/cast` because it's called with
   `f64` among its targets — a literal `0` cast to `f64` is exactly as
   unsafe by this classification as any other int→float conversion,
   regardless of representability.

**Verification:** `make test` 174/174 and `make bootstrap` byte-identical
after every file/batch; a full clean rebuild plus a full `examples/*.nuc`
blast-radius recompile (every file, not just the fixture-tested ones) found
zero regressions beyond the two already-documented pre-existing failures
(`comb-shapes.nuc`, `thread-macros.nuc`). Two cast sites lived outside the
`.nuc` file-glob the sweep initially covered — `tests/run-tests.sh`'s
embedded test-program heredocs and `tests/repl/*.in` REPL-transcript
fixtures — found via a final tree-wide `grep -rn '(cast '` audit and
converted (simple `i64` literal-widening, safely `as`). That audit leaves
exactly one live non-comment hit: `pkind-flow-check`'s own die-at message in
src/type-utils.nuc mentions "cast" as advice prose inside a diagnostic
string, not a code form — left for UN-5 to respell alongside the rest of
the docs/messages sweep rather than trigger a further bootstrap reconverge.
**Every live `(cast T x)` form in the tree is now `(as T x)` or
`(unsafe/cast T x)`.**

### UN-5 — retirement + docs

**Agents: focused-task-implementer (errors), api-docs-writer (docs).** Remove
the bare spellings from dispatch and add the targeted hard errors (D6) —
byte-identical once no uses remain. Docs sweep: docs/types.md (the coercion
catalog gains the `as`/`unsafe/cast` split; the `(cast ref:T x)` narrowing
"assertion" example at types.md:61 is respelled), docs/special-forms.md rows,
docs/builtins.md gains an "Unsafe operations" section listing the roster and
the audit command `grep -rn 'unsafe/' src lib`, docs/macros.md `cast` mentions,
[progress.md](../progress.md), and this doc's implementation-status section.

**Status (2026-07-16): errors DONE, docs DONE (see the docs-sweep bullet at the end of this section).** Every
dispatch site that previously accepted the bare spelling as a silent alias now
dies with a targeted D6 error instead:

- **emit-list** (`src/nucleusc.nuc`) and **node-type** (`src/generics.nuc`) —
  the `(when (or (= hp 'bare) (= hp 'unsafe/x)) …)` arms UN-2 added were split:
  a bare-head arm that `die-at`s, followed by an `unsafe/x`-only arm that keeps
  calling the exact same emitter/typer as before. Applied to `cast`,
  `funcall-ptr-1`/`-i32`/`-i64`/`-ptr`, and `ptr+`, in both files (the
  node-type↔emit-node lockstep — conventions.md).
- **`emit-toplevel-forms`'s `case hp` ladder** (`src/nucleusc.nuc`) — the
  `'unsafe-import-private` arm now `die-at`s instead of calling
  `emit-unsafe-import-private`; the `'unsafe/import-private` arm is untouched.
- Exact messages (single-quoted names, matching this file's own spelling
  style): `'cast' was split in Stage 14: use 'as' (safe) or 'unsafe/cast'
  (unchecked)`; `'funcall-ptr-1' was split in Stage 14: use
  'unsafe/funcall-ptr-1'` (and the `-i32`/`-i64`/`-ptr` siblings); `'ptr+' was
  split in Stage 14: use 'unsafe/ptr+'`; `'unsafe-import-private' was split in
  Stage 14: use 'unsafe/import-private'`.
- **`g-special-form-set`** membership is unchanged — the bare spellings stay
  registered so the names remain reserved (a `defn`/`defvar`/etc. still can't
  shadow `cast`, `ptr+`, etc.); only their *dispatch behavior* changed.
  `gcheck-special-form` (generics.nuc) and `is-libc-alloc` (nucleusc.nuc) —
  the two structural recognizers UN-2 explicitly left alone — were left alone
  again here too: neither emits/types a form, so there is nothing for them to
  "retire"; a bare `cast` reaching either is still syntactically recognized
  (harmless), and actually emitting/monomorphizing it hits the real dispatch
  site above and dies there regardless of which recognizer saw it first.
- **A real, previously-invisible gap surfaced and was fixed**:
  `fn-make-drop-method` (nucleusc.nuc, the cfn env-drop synthesizer) built two
  AST nodes headed by `(intern-symbol "cast")` — a `(cast (raw ui8) self)`
  pointer reinterpret and a `(cast usize 8)` alignment literal — neither of
  which the grep-based UN-3/UN-4 sweeps could see (they match literal `(cast
  `text, not a dynamically-`intern-symbol`'d head). Left as bare `"cast"`,
  every with-bound closure with an owned env would have died at drop-method
  emission the instant UN-5 landed. Both now synthesize `"unsafe/cast"`
  instead (verbatim D2 Class 1: identical emitter, zero behavior change) — a
  tree-wide `intern-symbol "cast"|"ptr+"|"funcall-ptr` grep after the fix
  confirms these were the only two live sites of this shape.
- **The one live diagnostic-string mention UN-4 deferred** —
  `pkind-flow-check`'s die-at in `src/type-utils.nuc` ("...assert with `(cast
  (ref T) ...)`") and its preceding doc comment — now say `unsafe/cast`
  (following its own advice literally would otherwise hit the new hard error).
- **`examples/unsafe-spellings.nuc`** no longer demonstrates bare spellings
  side-by-side with their `unsafe/` counterparts (that coexistence premise is
  gone); it now demonstrates `as` + the `unsafe/`-prefixed roster alone.
  `tests/expected/unsafe-spellings.out` updated to match. Four new negative
  fixtures (`tests/fixtures/un5-bare-{cast,ptr-plus,funcall-ptr,import-
  private}.nuc`) + `run_reject` entries in `tests/run-tests.sh` prove each
  bare spelling now dies with its exact D6 message. `lib/unsafe-priv-demo.nuc`
  used no bare spelling and needed no change.
- **Verification:** post-fix tree-wide grep of `src/`, `lib/`, `examples/`,
  `tests/` for `(cast `, `(ptr+ `, `(funcall-ptr-[1i]`, and
  `unsafe-import-private` confirms every remaining hit is a comment/prose
  mention or one of the new negative fixtures (which intentionally contain the
  bare spelling as the thing under test). `make clean && make` succeeded in
  one pass with the committed boot (no new dispatch *symbols* were added, only
  new arms over already-known `hp` comparisons and new string literals, so
  this was not a "breaking change the OLD boot can't bridge" case). `make
  test` **178/178** (174 UN-4 baseline + 4 new `un5-bare-*-rejected` fixtures).
  `make bootstrap` converged **byte-identical on the first try** (stage1.ll ==
  stage2.ll) — no `update-bootstrap` needed, matching this table's prediction:
  the new die-at strings and the flipped dispatch behavior are both
  source-order-deterministic and exercise no code path in the compiler's own
  (now bare-spelling-free) self-compilation. `boot/nucleusc.ll`/`bin/nucleusc`
  intentionally left untouched (consistent with UN-1/UN-2/UN-3 precedent: no
  refresh needed when already byte-identical).
- **Docs sweep DONE (2026-07-16, api-docs-writer pass).** The four files this
  section named — docs/types.md (coercion catalog + the `cast ref:T x`
  narrowing-assertion example), docs/special-forms.md (`cast`/`ptr+`/
  `funcall-ptr-*`/`unsafe-import-private` rows split into "retired" + the
  `unsafe/`-prefixed replacement), docs/builtins.md (new "Unsafe operations"
  section + `grep -rn 'unsafe/' src lib` audit command), docs/macros.md (`cast`
  mentions) — are all updated to the `as`/`unsafe/cast` split. A second,
  exhaustive `grep -rn '(cast \|ptr\+\|funcall-ptr\|unsafe-import-private'
  docs/` pass beyond that four-file list (matching this file's own D6 error
  text) additionally found and fixed live bare-spelling code examples in
  docs/errors.md, docs/stdlib.md, docs/structs-unions.md, docs/strings.md,
  docs/iterators.md, docs/collections.md, plus stale `unsafe-import-private`
  mentions in docs/toplevel.md and docs/compiler.md's REPL-supported-forms
  list, and a generic `funcall-ptr-*` family reference in docs/allocators.md.
  Every respelling was classified per-site against `build/nucleusc` (not
  guessed from the D2/D3 tables alone) — several sites simplified to drop the
  cast entirely where LW-4 literal-widening already makes it redundant, and a
  stale `(Iterator i64)`/"cast to i64" description of `ListIter`/`SplitIter`/
  `LineIter` (actually `(Iterator ptr)` since a pre-Stage-14 commit,
  `97fd3c4`) was corrected in docs/iterators.md and docs/strings.md since it
  blocked classifying the recovery cast correctly. `docs/builtins.md`'s
  pre-existing stale duplicate rows (outside the new section) were
  deliberately left alone, per the frozen-monolith precedent (not in
  `docs/index.md`). See [progress.md](../progress.md) for the file-by-file
  summary.

---

## 5. Verification & bootstrap policy

| Phase | Expected bootstrap | Gate |
|---|---|---|
| UN-1 `as` | byte-identical (additive) | make test + bootstrap fixed point |
| UN-2 routing | byte-identical (additive) | same |
| UN-3 refresh + Class-2 sweep | one controlled refresh, then per-file inert | IR diff per file; refresh for macro-body files |
| UN-4 cast split sweep | inert per file (same emitters) | IR diff per file; refresh for macro-body files |
| UN-5 retirement | byte-identical (no uses remain) | make test + bootstrap |

Full suite (`make test`) and self-compilation (`make bootstrap`) after every
batch; unjustified drift on an inert batch is a bug, not a refresh.

**Definition of done:** bare `cast`/`funcall-ptr-*`/`ptr+`/
`unsafe-import-private` are hard errors; `grep -rn 'unsafe/' src lib`
enumerates every unchecked-operation site; `as` covers the safe residue; tests
green; boot converged.

---

## 6. Rejected alternatives

- **Enforced `(unsafe …)` block now.** Meaningful enforcement needs a
  transitivity decision (do functions built on unsafe ops taint their
  callers?) — an effect system; without it the block is ceremony at exactly
  the granularity the namespace already provides. The namespace also builds
  the roster a future block would consume. Deferred, unchanged.
- **`unsafe.cast` (dot spelling).** Qualified names use `/`; dots are
  import-path syntax only. New reader rules for zero gain.
- **Real namespace membership (import-gated).** Special forms aren't
  scope-resolved; conditional availability adds complexity and no audit value.
- **Move all raw ops (`deref`, `aref`, …).** Signal destruction: when
  everything is `unsafe/`, nothing is. The operand-type system already marks
  the hazardous cases (D2).
- **`as` as a macro over `cast`.** A macro cannot see operand types, so it
  cannot restrict the set; the checker must live at emit/node-type level.
- **`as` stricter than the implicit rules** (e.g. rejecting sign reinterpret
  or the `void*` flows). Incoherent — the plain assignment on the next line
  would accept what the explicit form refused.
- **`unsafe/cast` rejecting as-safe conversions.** Forces exact type knowledge
  onto every migration and macro; keep it a superset, lint later (OQ5).
- **Runtime-checked narrowing inside `as`.** Hidden cost in a form that reads
  like a static cast; belongs to `try-as` (§Deferred).

## 7. Sequencing (staging.md integration)

- **UN-1 → UN-2 → UN-3** are additive-then-one-refresh and independent of the
  backbone; they may land early, in any slot whose refresh window doesn't
  overlap another item's, and outside S3's quiet-tree window. Landing them
  early flips the new-code convention cheaply and lets MC/LW/T phases write
  surviving casts in final spelling as they go.
- **{MC-3, LW-5, 14.2/14.3} → UN-4 (hard edge):** the split sweep must follow
  the cast-*deletion* work, or it renames thousands of casts that are about to
  be deleted (double churn). Recommended slot: after T completes — UN-4/UN-5
  are the backbone's tail and the stage's close-out.
- **LW-4 synergy:** its representability machinery is what a future `try-as`
  would reuse; no edge, just shared ground.

## 8. Open questions / deferred

| # | Item | Position |
|---|---|---|
| OQ1 | same-width sign reinterpret in `as` | **Include** (parity with implicit); revisit only if the implicit set is ever tightened |
| OQ2 | lift the `(ns unsafe)` reservation for a curated `lib/unsafe.nuc` | Keep reserved in v1; lift deliberately if compiler-owned unsafe helpers want a home |
| OQ3 | promote raw-operand `deref`/`ptr-set!` to `unsafe/` | Revisit after T lands `(ref T)` adoption data — if raw derefs become rare, the promotion gets cheap |
| OQ4 | bounds-checked debug mode for `aref`/`aset!` | Deferred — the better answer than renaming; zero-cost in release builds |
| OQ5 | lint: `unsafe/cast` where `as` would do | Later tier, after UN-5; needs no design now |
| — | `try-as` (range-checked narrowing → `!T`/`(Maybe T)`) | Deferred; pairs with LW-4's representability checks |
