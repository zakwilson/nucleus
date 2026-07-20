# Stage 14 — Symbol mangling for `?` and `!` in function names

Builtins get `set!`, `aset!`, `inc!`, and the library is full of `empty?`/
`contains?` — but a *user* `defn foo?` or `defn push!` dies, and not even
with a source error. This doc designs the mangling extension that gives user
names full `?`/`!` parity, fixes the documented single-conformer mangling
bug as a corollary, and retires the `_StrMangleShim` workaround.

Repro (verified 2026-07-02, current `build/nucleusc`):

```lisp
(defn full?:i32 (n:i32) 1)   ; --emit-llvm silently emits: define i32 @full?(...)
                             ; object path: LLVM parse error
                             ; "expected '(' in function argument list"
```

---

## 1. Ground truth (verified 2026-07-02 by repro + survey)

1. **LLVM's unquoted identifier set is `[-a-zA-Z$._][-a-zA-Z$._0-9]*`** —
   hyphen is legal (why `@arena-alloc` works), `?`/`!` are not. Quoted
   identifiers `@"full?"` are legal and produce a working ELF object whose
   symbol is literally `full?` (verified through `llc` + `nm`) — ELF allows
   these bytes; only C *source* can't spell them.
2. **Two disjoint naming worlds exist.** *Solitary* defns (plain defn OR a
   single-conformer protocol method — same code path) get ir-name =
   **source name verbatim** at src/generics.nuc:354 (`finalize-generics`,
   the `n-user==1 ∧ no-generic ∧ no-intrinsic` branch), with the same
   verbatim fallback in `defn-ir-name` (generics.nuc:505 via `ns-ir-base`,
   nucleusc.nuc:1852). *Overloaded* names go through `mangle-fn-name` →
   `op-name-token` → `sanitize-for-ir` (generics.nuc:174-178, 148-165).
3. **`sanitize-for-ir` is a blanket replace, and its safe set excludes
   hyphens** (src/format.nuc:46-62: only `[0-9a-zA-Z_.]` survive; all else
   → `_`). Verified: overloads of `is-both?` emit `@is_both_.pA` — hyphen
   *and* `?` both collapse to `_`. So `foo?`, `foo!`, and `foo-` are
   indistinguishable post-sanitize (lossy), and — the design landmine —
   **routing solitary defns through `sanitize-for-ir` would rename every
   hyphenated symbol in the tree** (`arena-alloc`→`arena_alloc`),
   destroying bootstrap byte-identity and the C ABI. The `?`/`!` transform
   must be targeted and leave every other character alone.
4. **The `?`-breaking path and the single-conformer bug are the same
   line.** generics.nuc:354 is both why `defn full?` emits `@full?` and why
   a single-conformer generic like `str-empty?` needed the
   `_StrMangleShim` dummy conformer (lib/strview-str.nuc:55-73) to force
   the ≥2-conformer mangled branch. Verified: a single `?`-named
   struct-receiver defn emits verbatim and dies; adding a second overload
   flips it to `@…_.p<T>`.
5. **Operator names already solved this problem** — the precedent:
   `op-name-token` (generics.nuc:148-165) maps `_+`→`add`, `=`→`eq`,
   `<`→`lt`, etc. through an explicit mnemonic table, falling through to
   `sanitize-for-ir`. A `?`/`!` mapping belongs at exactly this layer.
6. **Composition order** (mangle-fn-name): base token (`op-name-token`) →
   namespace `ns-compose` prefix (`<prefix>__<base>`) → per-param
   `.<type-mangle-token>` suffixes. The solitary path and `ns-ir-base` do
   the prefix step only, on the raw name.
7. **The REPL derives symbol names independently and already diverges**:
   src/repl.nuc:161,228,248,275-291,609-621 build thunk/lookup/patch names
   from raw `sanitize-for-ir(fname)` — for a `?` name that's `foo_` while
   batch would emit `@foo?`; for a *hyphenated* name it's `arena_alloc`
   while batch emits `@arena-alloc`. The `?` divergence is moot today
   (such defns don't compile); the hyphen divergence is a suspected
   pre-existing REPL-redefinition bug to ground-verify during SM-2.
8. **Other verbatim (breaking) name sinks**: `emit-defvar` globals
   (nucleusc.nuc:6544), `.nuch` solitary import (nuch.nuc:250 — symmetric
   with export, both re-derive via `ns-ir-base`), and `%Foo` struct/union
   type names (union-registry.nuc:63,120,141-143). `--emit-cheader`'s
   `sanitize-for-c` (format.nuc:69-84) already maps `?`/`!`→`_` — i.e. it
   names a symbol that doesn't exist; it must name the real one.
9. **Blast radius is contained**: no `?`/`!`-named defn or call exists in
   `src/` (grep-verified) — all live in `lib/` (`empty?`/`contains?` on
   Vector/HashSet/HashMap, `any?`/`every?`/`exists?`/`all?` combinators,
   the four `Str` predicates + shim). So the compiler's own bootstrap IR
   cannot change if the transform leaves non-`?`/`!` names untouched.
   No `!`-named defns exist anywhere yet.
10. **No reader work needed**: `?`/`!` are ordinary symbol chars
    (lib/reader.nuc:82-96); the `?T`/`!T` sugars key on the leading char
    of a *type token* after the first-colon split, so `defn foo?:!i32`
    already parses as name `foo?`, return `!i32` (survey-verified).
11. **No diagnostic exists** — the failure is a downstream LLVM parse
    error pointing at generated IR, not at the user's source line.

## 2. Decisions

- **Mnemonic mapping, not quoting**: every `?` in a name becomes `_QMARK`,
  every `!` becomes `_BANG` (any position, every occurrence — Clojure's
  munge precedent). Distinct, greppable in `nm`/objdump, C-linkable, and
  it composes with the existing `__` namespace separator and `.tok` param
  suffixes without new separators.
- **Applied once, at the base-token layer**, shared by every path that
  builds an ir-name (solitary, overloaded, fallback, defvar, nuch import,
  REPL). One new helper beside `op-name-token`; call it `ir-name-token`.
- **Everything else stays byte-for-byte**: hyphens and all other chars are
  untouched on the solitary path (the §1.3 invariant), and the overloaded
  path keeps its existing blanket sanitize *after* the `?`/`!` map — so
  existing overloaded symbols change only where they contained `?`
  (`empty_.…` → `empty_QMARK.…`).
- **Collision policy**: a user name containing a literal `_QMARK`/`_BANG`
  substring can collide with a mangled one; accepted (pre-release),
  documented in docs/functions naming notes.
- **Solitary always tokenizes** — line 354 builds its base the same way
  the overloaded path does, which *is* the fix for the single-conformer
  bug; the shim dies.

## 3. Design — phases

### SM-1 — the shared token map + chokepoint unification

**Status: DONE (2026-07-03).** `ir-name-token` (+ helper `ir-name-append`) added
in src/generics.nuc beside `op-name-token`; maps `?`→`_QMARK`, `!`→`_BANG`, all
other bytes (hyphens included) pass through, with a pointer-unchanged fast path
for names with neither char. Wired into four sites: `op-name-token`'s
`sanitize-for-ir` fallthrough (overloaded path), the solitary branch in
`finalize-generics` (generics.nuc), and `ns-ir-base` (nucleusc.nuc) — the last
covering `defn-ir-name`'s fallback, `emit-defvar`/`extern` globals, and the
`.nuch` solitary import + cheader function-name derivation in one chokepoint.
`_StrMangleShim` and its four dummy conformers deleted from lib/strview-str.nuc;
`str-empty?` et al. now resolve honestly on the solitary path. The compiler
imports lib code with overloaded `?` methods (`contains?`/`empty?` on
HashSet/HashMap), so its own self-compiled IR legitimately shifted
`@contains_.…`→`@contains_QMARK.…`; this required the standard bootstrap
reconverge (`make update-bootstrap` then `make clean && make`). Fixed point
(stage1==stage2) restored; 144/144 tests pass (was 143 + the new example).
New example `examples/predicate-names.nuc` + `tests/expected/predicate-names.out`;
`nm` on its binary shows `full_QMARK`, `push_BANG`, `blank_QMARK` (ex-shim
single-conformer shape), `zeroed_QMARK.pMeters`/`.pSeconds`. Bonus: because the
fix landed in `ns-ir-base`, `--emit-cheader` now prints the real linkable symbol
(`full_QMARK`) instead of the prior illegal `full?` for solitary `?`/`!` names —
partially anticipating SM-3 for that path (the `sanitize-for-c` map and cheader
overload param-suffix gap remain SM-3). Deferred to SM-5: the now-stale
`context/build.md` gotcha bullets and the stale `context/conventions.md` note
"`?`/`!` in user function names break LLVM symbols", plus the `docs/functions.md`
naming section.

- New `ir-name-token` (src/generics.nuc, beside `op-name-token`):
  replace `?`→`_QMARK`, `!`→`_BANG`, pass everything else through
  unchanged. `op-name-token` applies it before its `sanitize-for-ir`
  fallthrough; the solitary branch (generics.nuc:354), `ns-ir-base`
  (nucleusc.nuc:1852 — covers the `defn-ir-name` fallback at
  generics.nuc:505 and the `.nuch` solitary import at nuch.nuc:250), and
  `emit-defvar` (nucleusc.nuc:6544) all route the bare name through it.
- Delete `_StrMangleShim` + its four dummy conformers
  (lib/strview-str.nuc:55-73); `str-empty?` et al. become honest
  single-conformer methods on the now-correct solitary path.
- Gates: **bootstrap byte-identical** (no `?`/`!` in src/, hyphens
  untouched — this gate *is* the §1.3 landmine check); `make test`; new
  example `examples/predicate-names.nuc` (a plain `full?`, a `push!`, an
  overloaded `?` pair, a single-conformer protocol `?` method — the
  ex-shim shape) with expected output.

### SM-2 — REPL alignment

**Status: DONE (2026-07-03).** The redefinition path threads a single
`fname-ir` binding derived at exactly two root sites: the defvar
`external global` declaration (repl.nuc:161) and the defn `fname-ir` let
(repl.nuc:228); the other listed lines (248, 275-291, 609-621) all consume
that binding, so fixing the two roots fixes the chain. Both switched from
raw `sanitize-for-ir` to `ns-ir-base` — the *same* function `emit-defvar`
(nucleusc.nuc:6597) and `defn-ir-name`'s solitary fallback (generics.nuc:567
→ ns-ir-base) use, so `fname-ir` now equals byte-for-byte the symbol
`emit-defn`/`emit-defvar` write into the module (`@my-add`, `@even_QMARK`).
`ns-ir-base` (not bare `ir-name-token`) is correct because it also composes
`g-current-ns`'s prefix, matching batch if the REPL user does `(ns …)` — and
it is the identity of `ir-name-token` under the default `user` namespace
(empty prefix), so the common REPL case is unaffected beyond the `?`/`!`/
hyphen mapping. `defn-ir-name` itself was *not* used because it prepends `@`
and takes param-types for the overloaded lookup; the REPL wants the bare
name and only ever handles the solitary case (one thunk `@fname` + one
`@fname.tgt` per bare name — overloading isn't representable in this
machinery), which is precisely `ns-ir-base`.

**Both suspected bugs ground-verified real** (2026-07-03, then fixed): not
merely redefinition — the *first* definition already broke. A hyphenated
`(defn my-add …)` emits `define … @my-add(` but the REPL derived
`fname-ir="my_add"`, so the thunk declared `@my_add`, the `@fname(`→`@impl(`
rewrite missed (buffer has `@my-add(`), and `update-fn-tgt` looked up the
non-existent `@my_add.impl.0` → "Symbols not found". A `?`-named
`(defn even? …)` emits `@even_QMARK` (SM-1) but the REPL derived
`fname-ir="even_"` → same failure against `@even_.impl.0`. After the fix all
of hyphen/`?`/`!` round-trip through define/call/redefine/call, including a
redefinition observed through a *second* function that calls the redefined
one (thunk dispatch via the corrected name). `tests/repl/redefinition.in`
and `tests/expected/repl-redefinition.out` extended with a hyphenated
`my-add` (+ a `use-add` caller proving cross-fn thunk dispatch) and a
`?`-named `even?` case. `make test` + `make bootstrap` (stage1==stage2)
green; `build/nucleusc.ll` is *not* byte-identical (repl.nuc is compiled
into the compiler binary, so swapping its callee changes its IR) — but the
batch *emission* path is untouched and the bootstrap fixed point holds,
which are the load-bearing gates.

### SM-3 — export surfaces tell the truth

**Status: DONE (2026-07-03).** The `ir-name-token`-first transform is composed at
`sanitize-for-c`'s three call sites (all in src/cheader.nuc — the two type-name
typedef sites `emit-cheader-defstruct`/`emit-cheader-defunion` and the `struct %s`
reference in `type-name-to-c`) as `(sanitize-for-c (ir-name-token name))`, rather
than folded inside `sanitize-for-c` itself. Reason: `sanitize-for-c` lives in
src/format.nuc, which is `import-use`d (nucleusc.nuc:420) *before* generics.nuc
(604) where `ir-name-token` is defined; imports are processed inline, so a call up
to `ir-name-token` from a format.nuc body is an unresolved-forward-reference at
emit time (won't compile), and duplicating the `?`/`!` map into format.nuc would
violate SM-1 §2's "applied once, one shared helper" invariant. Composing at the
(post-generics) cheader call sites is functionally exactly "ir-name-token first,
then the blanket map" while keeping the transform single-homed. Order is
load-bearing: `ir-name-token` must run *before* the blanket sanitize or `?` would
collapse to `_` and collide. For a name with no `?`/`!`, `ir-name-token` is a
pointer-identity no-op, so every existing header stays byte-identical; the
compiler's own IR shifts only in cheader.nuc's three functions (no string-pool
change — `_QMARK`/`_BANG` remain @.str.518/519), and `make bootstrap`'s fixed point
holds in one pass (stage1==stage2). A doc note on `sanitize-for-c` records the
compose-order contract for future callers.

The `.nuch` round-trip was **ground-verified real, not just design-asserted**
(2026-07-03): a solitary `full?`/`push!` export as `(declare (full? i32) ...)` and
re-import through the shared `ns-ir-base` to `@full_QMARK`/`@push_BANG`; an
overloaded `?` pair (`even?` on i32/i64) exports as
`(defmethod "@even_QMARK.i32" ...)` / `.i64` carrying the stored mangled string,
and re-imports to the same symbols. A consumer importing the `.nuch` links against
the lib object and runs (`full=1 push=8 even4=1 even7=0 even6L=1`) — proving the
exporter's symbols and the importer's re-derived declarations agree at link time.
Fixtures `tests/fixtures/sm3-predlib.nuc` (functions, solitary + overloaded) and
`tests/fixtures/sm3-typenames.nuc` (`?`/`!` struct/union type names); six new
checks in tests/run-tests.sh (`sm3-nuch-roundtrip`, `sm3-lib-symbols`,
`sm3-cheader-fn-legal`, `sm3-import-resolves-mangled`, `sm3-nuch-link-and-run`,
`sm3-cheader-typenames`). `make test` all-green; `make bootstrap` green.

Two **pre-existing gaps observed and left for a future pass** (outside SM-3's
sanitize-for-c-call-sites scope, noted here so they aren't lost):
1. `emit-cheader-declare` prints the bare `ns-ir-base(fname)` for *every* function
   regardless of overload status, so an overloaded function emits N identical
   prototypes (e.g. two `int32_t even_QMARK(...)` lines) — a C-illegal duplicate.
   This is general (not `?`-specific) overload-unaware cheader export.
2. Union arm names, enum variant names, and struct field names are printed *raw*
   in the cheader (no sanitizer at all), so a `?`/`!`-named arm/variant/field would
   still emit illegal C. Only the struct/union *type* name goes through
   sanitize-for-c today. Both are broader cheader-completeness work, not the SM-3
   symbol-mangling surface.

- `sanitize-for-c` applies `ir-name-token` *first*, then its blanket map —
  cheader prototypes must name the real linkable symbol (`full_QMARK`),
  not a fiction (`full_`).
- `.nuch` round-trip: solitary declare/import are symmetric through the
  shared `ns-ir-base` (fixed together in SM-1); `defmethod` entries carry
  the stored mangled string verbatim — confirm with a `?`-named method
  exported and re-imported (add to `make lib-headers` smoke or the new
  example).

### SM-4 — the remaining verbatim sinks

**Status: DONE (2026-07-03).** `%Foo` struct/union type names now route through
`ir-name-token`. The design's premise that `type-to-ir` is the single type-REFERENCE
chokepoint proved **incomplete** (ground-verified: `(defstruct Full? …)` + a field
access emitted `getelementptr inbounds %Full?, …`, a straggler that bypasses
`type-to-ir` entirely). GEP aggregate-type operands, `alloca`/`load`/`store` type
operands across `union-emit.nuc` and `nucleusc.nuc` each print the struct name
**directly** from a StructDef in hand, not via `type-to-ir`. So there is no single
reference chokepoint. The fix is a StructDef-level cache instead of a per-site wrap:

- **New field `StructDef.ir-name`** (compiler-types.nuc), computed **once** in
  `register-struct` (abi.nuc — the sole StructDef allocator; `repl-register-node`
  and every anon/fatptr/env builder route through it, grep-verified) as
  `(ir-name-token name)`. `sd.name` stays the **raw source spelling and the lookup
  key** — `lookup-struct` matches a source type token like `Full?` by interned-
  pointer identity, so mangling `name` would break resolution; `ir-name` is the
  LLVM spelling only. For a name without `?`/`!`, `ir-name-token` is a pointer-
  identity no-op, so `ir-name == name` for every existing struct/union and the
  whole compiler self-IR is byte-identical modulo the mechanical shift below.
- **Every IR emission site** switched from `(sd name)` to `(sd ir-name)`:
  `type-to-ir` TY-STRUCT/TY-UNION; the definition emitters (`emit-defstruct`,
  `emit-pending-struct-ir-type`, `emit-union-ir-type`, and the direct backing-
  struct line in `defunion-register`); and ~35 GEP/alloca/load/store type-operand
  sites in `union-emit.nuc`/`nucleusc.nuc`. Diagnostic messages keep `(sd name)`
  (user-facing = source name). Two sites hold only a name string (not a StructDef):
  `emit-box-struct-move`'s heap-move load/store and it wrap `(ir-name-token …)`
  there (`struct-name` must stay source-spelled for the `(sizeof …)` it also feeds,
  which resolves the struct by source name).
- **Anon/synth names left alone** (`__anon_struct_h…`, `__anon_union_h…`,
  `__vfn_env_%d`, `__fatptr`, `__boxedfn.…`, `__dyn.…`): all fixed or already
  `sanitize-for-ir`'d, so `ir-name-token` is a provable no-op and their unwrapped
  definition sites agree with the `ir-name` reference side byte-for-byte.
- **`ir-name-token` (+ `ir-name-append`) RELOCATED** generics.nuc → format.nuc,
  beside `sanitize-for-ir`/`sanitize-for-c`. Forced by import order: `type-utils.nuc`
  (#567) and `union-registry.nuc` (#584) are `import-use`d **before** generics.nuc
  (#604), and `type-to-ir`/`register-struct`/the union emitters can't forward-
  reference a generics.nuc definition (the SM-3 wall — ground-verified: the direct
  call errored `unknown: ir-name-token`). SM-3's "wrap at a later call site" cannot
  apply because `type-to-ir`'s callers are everywhere; relocating the single home
  (not duplicating — SM-1 §2 preserved) makes it reachable from every consumer.
- **Out of scope (noted, not type names):** goto/`indirectbr` label names
  (`%lbl.<arm>`, nucleusc.nuc) still print arm names raw — a distinct surface from
  `%Foo` type names; C-imported struct types in cheader.nuc emit LLVM names from C
  identifiers, which cannot contain `?`/`!` (provably safe, and SM-3's domain).
- **Gates:** `make bootstrap` fixed point (stage1==stage2) holds **in one pass** —
  the compiler source has no `?`/`!` structs, so the whole transform is inert on it;
  `build/nucleusc.ll` before/after is *not* byte-identical, but the only shift is the
  mechanical relocation of `ir-name-token`/`ir-name-append` + their `_QMARK`/`_BANG`
  string constants (moved earlier → +2 `@.str` renumber) plus the extra `StructDef`
  field — root-caused, no hyphen regression (no `@arena-alloc`→`@arena_alloc` rename
  in the normalized diff). 151/151 `make test`. New example
  `examples/predicate-types.nuc` (+`tests/expected/predicate-types.out`): `?`/`!`
  structs, a `?`-union with `match`, and a `?`-struct embedded by value in another
  struct; the emitted `.ll` shows `%Full_QMARK`/`%Reset_BANG`/`%Shape_QMARK`
  definitions and every reference spelled identically, `%Gauge = type { %Full_QMARK,
  i32 }` cross-checks def-vs-ref agreement, and `llvm-as` validates the module.

- `%Foo` struct/union type names get the same token map at registration/
  emission (union-registry.nuc:63,120,141-143; nucleusc.nuc:3603) — a
  `?`-named struct is unidiomatic but must not emit illegal IR.
- Audit for other raw `@%s`/`%%%s` name pastes (survey list §1.8) and
  route stragglers through the shared helper.

### SM-5 — diagnostic backstop, docs, adoption

**Status: DONE (2026-07-03).** A pure char-class predicate `ir-name-illegal-char`
(src/format.nuc, beside `ir-name-token`/`sanitize-for-ir`/`sanitize-for-c`) scans a
FINAL ir-name and returns the first byte outside LLVM's unquoted-identifier body
`[A-Za-z0-9$._-]` (a leading `@`/`%` sigil is skipped, since callers like
`defn-ir-name` pass the whole `"@name"`; hyphen and `$` are legal and never
flagged — the SM-1 targeted-not-blanket invariant). A die-at-calling wrapper
`check-ir-name-legal(line, orig-name, ir-name)` (src/abi.nuc, immediately before
`register-struct`) turns a hit into a clean source-level diagnostic naming the
original definition. The wrapper lives in abi.nuc, not format.nuc, because format
is import-used (nucleusc.nuc:420) before reader.nuc (507) where `die-at` is defined
— the same import-order wall SM-3/SM-4 document; abi.nuc (582) is the earliest home
reachable by both `die-at` and every chokepoint. Wired into seven define/declare
chokepoints, one added line each (all downstream of abi.nuc, and the predicate
auto-skips the `@`/`%` sigil so already-prefixed strings pass straight through):
`emit-defvar`, `emit-extern`, `emit-defn` (only the `(defn-is-mangled)==0` solitary
branch — the mangled branch already went through `sanitize-for-ir`), `emit-defstruct`
(nucleusc.nuc); `defunion-register` (union-registry.nuc); `emit-cheader-defstruct`,
`emit-cheader-defunion` (cheader.nuc — provably always no-ops since `sanitize-for-c`
output is `[A-Za-z0-9_]` ⊂ legal, kept for defense-in-depth/consistency). Deliberately
NOT wired: `type-name-to-c` (no `line` param, recursive, output always legal),
`register-struct` itself (no `line` param, ~14 mostly-synthetic call sites — the two
real user-named ones are covered by `emit-defstruct`/`defunion-register` via
`sd.ir-name` after the fact), stamped parametric-template instance names
(compiler-composed from safe tokens), and the REPL's own name derivation (its `(defn
…)` still flows through `emit-defn`, so it is checked there). Verified: a `(defn
weird%name …)` — `%` is legal in a Nucleus symbol per lib/reader.nuc's permissive
`is-sym-char` but illegal in an LLVM identifier body, and `ir-name-token` leaves it
unchanged (the emitted ir-name is literally `@weird%name`) — now fails with
`illegal character '%' in generated symbol for 'weird%name' (ir-name '@weird%name') —
LLVM identifiers allow only [A-Za-z0-9$._-]` instead of a downstream LLVM parse
error. New negative fixture `tests/fixtures/sm5-illegal-char.nuc` + a
`sm5-illegal-char-rejected` check in tests/run-tests.sh (must-FAIL-with-message
pattern). The change is purely additive and inert for every existing name (no `?`/`!`
or other illegal char in src/ or lib/), so `make bootstrap` converges in ONE pass
(stage1==stage2, byte-identical `build/nucleusc.ll`) with no reconverge; 152/152
`make test`. Docs deferred out of this task's scope (per the SM-5 task boundary):
the stale context/build.md gotcha bullets, the docs/functions.md naming section,
and the stale context/conventions.md note remain for a separate docs pass; lib-helper
`?`-suffix re-adoption stays the user's optional call.

- At define/declare emission, any *still*-illegal character in a final
  ir-name is a source-level error naming the definition — never again the
  raw LLVM parse error (the backstop for chars beyond `?`/`!`; keeps the
  failure mode honest if someone names a function `foo$bar%`).
- Docs: context/build.md — delete the two now-stale gotcha bullets (the
  `!`/`?`-invalid-in-defn-name entry and the ≥2-conformer `?`-mangling
  limitation); docs/functions naming section documents the mapping and
  the `_QMARK`/`_BANG` collision caveat; conventions.md note if the
  compiler ever adopts `?` names internally.
- Adoption (optional, user's call): lib helpers deliberately named
  cast-free (`char-is-ascii` and friends, named to dodge this bug) may
  take their idiomatic `?` suffixes back.

## 4. Verification and bootstrap convergence

SM-1's byte-identity gate on `build/nucleusc.ll` is the load-bearing one:
the compiler contains no `?`/`!` names, so any diff means the transform
touched something it shouldn't (almost certainly a hyphen). lib/ symbol
changes (`empty_.…`→`empty_QMARK.…`, shim removal) alter example IR only —
covered by `make test` output diffs. REPL changes ride the
`repl-redefinition` test. Standard reconverging refresh per landed phase
(compiler-source string-pool shifts). Definition of done: the §3 example
runs; `nm` on its binary shows `full_QMARK`/`push_BANG`; the two
context/build.md gotchas are deleted because they are no longer true.

## 5. Alternatives considered and rejected

- **Quoted LLVM identifiers (`@"full?"`)**. Verified to work end-to-end,
  and keeps symbols maximally readable — but no emission path uses quoting
  today (grep-verified), so *every* `@%s`/`%%%s` format site (~15+ for
  calls alone, plus declares, vtables, abi struct-call paths) must become
  quote-aware, the REPL's textual `@fname(` rewrite gets fragile, and the
  resulting symbols are permanently un-declarable from C. The mnemonic
  approach is one helper at one layer with house precedent.
- **Blanket `sanitize-for-ir` on the solitary path** ("just always
  sanitize"). The obvious fix and a catastrophe: hyphens aren't in the
  safe set, so it renames every hyphenated symbol in the tree, breaking
  bootstrap byte-identity and every C-visible name (§1.3).
- **Diagnostic-only** (reject `?`/`!` with a good error). Codifies the
  builtin/user mismatch this doc exists to remove.
- **Short cryptic escapes** (`?`→`_p`, or hex `$3F`). Collision-prone
  against real naming conventions (`_p` suffixes abound) or unreadable in
  tooling; `_QMARK`/`_BANG` are verbose exactly once per symbol and
  unambiguous.
- **Fixing hyphen lossiness on the overloaded path too** (`is-both` vs
  `is_both` overload collision). Real but theoretical (no such pairs
  exist), and preserving hyphens in overloaded tokens would rewrite every
  overloaded symbol in the compiler IR — a whole-tree reconverge for no
  reported pain. Noted for a future pass; the shared-helper structure
  makes it a one-line change when wanted.

## 6. Sequencing and relationship to other stage-14 work

Touches `finalize-generics`/naming helpers, repl.nuc, and the export
emitters — no overlap with the CP (done)/MC/LW/S/T surfaces or the
AVR/RISC-V target plumbing. Small enough to slot anywhere in the backbone's
small-item band (with MC/LW, order among them free); the only mild
preference is landing before defn-signature S3 or type-safety touch lib/
broadly, purely to keep refresh windows discrete. Order within: **SM-1 →
SM-2 → SM-3 → SM-4 → SM-5**, gates after each; SM-2 may surface the
pre-existing REPL hyphen bug, which is independently worth the fix.
