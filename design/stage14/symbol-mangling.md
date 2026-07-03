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

- `sanitize-for-c` applies `ir-name-token` *first*, then its blanket map —
  cheader prototypes must name the real linkable symbol (`full_QMARK`),
  not a fiction (`full_`).
- `.nuch` round-trip: solitary declare/import are symmetric through the
  shared `ns-ir-base` (fixed together in SM-1); `defmethod` entries carry
  the stored mangled string verbatim — confirm with a `?`-named method
  exported and re-imported (add to `make lib-headers` smoke or the new
  example).

### SM-4 — the remaining verbatim sinks

- `%Foo` struct/union type names get the same token map at registration/
  emission (union-registry.nuc:63,120,141-143; nucleusc.nuc:3603) — a
  `?`-named struct is unidiomatic but must not emit illegal IR.
- Audit for other raw `@%s`/`%%%s` name pastes (survey list §1.8) and
  route stragglers through the shared helper.

### SM-5 — diagnostic backstop, docs, adoption

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
