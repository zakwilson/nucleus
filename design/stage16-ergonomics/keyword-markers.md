# Keyword markers: retiring `&rest` / `&where` / `&optional` / `&repr`

Stage 16, item "Replace special symbols with keywords"
([overview.md](overview.md) §"Replace special symbols with keywords").
**Done, 2026-08-16.**

## 1. The premise, corrected

The item as filed reads: *"Special symbols like `&rest` and `&where` are
squatting on the valuable `&` character. They were added before keywords; using
keywords for the same role would free up `&`, and might even simplify the
reader."*

Three parts of that needed correcting before the work started.

**There are four markers, not two.** `&rest` (101 uses), `&where` (185),
`&optional` (39), `&repr` (18). A sweep of the first two would have left `&`
still reserved, which is the whole motive.

**The reader has nothing to simplify.** `&` is already an ordinary symbol
character: `is-sym-char` (`src/reader.nuc:146-160`) is a deny-list naming only
whitespace, `()`, `"`, `;`, `[]{}`, and 38 is not on it. There is no `&` prefix
dispatch, no entry in the reader-macro table (`src/nucleusc.nuc:16792-16799`
registers exactly `~@ ~ ' \` @`), and no byte-38 test anywhere in `src/` or
`lib/`. `&rest` was a plain interned `NODE-SYM` recognized positionally by a
string compare on `Node.s`. The change is therefore worth nothing to the reader
and everything to the *conventions*: keywords already carry markers elsewhere
(`(defvar :const x:i32 9)`, `(defstruct F (:volatile status:i32))`,
`(ptr :volatile ui8)`, through `parse-decl-attrs` at
`src/union-registry.nuc:1348-1386`), so the language had two spellings for one
idea.

**`&` is not freed outright.** `.&` (field-address) is a live special form —
`emit-field-addr` at `src/nucleusc.nuc:9870`, reserved at `:17030`, ~200 uses
across the tree — and `&` remains illegal in any *definition* name regardless,
because `ir-name-illegal-char` (`src/format.nuc:223-238`) rejects it and
`check-ir-name-legal` (`src/abi.nuc:1069-1078`) raises on it. What this frees is
`&` as a **prefix sigil**. That is the useful half, and the one-convention
argument stands without it.

## 2. Decisions

| | |
|---|---|
| Scope | all four markers |
| Spelling | 1:1 — `:rest` `:where` `:optional` `:repr` |
| `&repr`'s mode operand | kept: `:repr tagged` / `:repr niche`, not collapsed to `:tagged`/`:niche` — same parser, and room for a third mode |
| Old spelling | located hard error naming the replacement |

`:repr tagged` over `:tagged`: collapsing marker and mode saves two tokens but
puts two unrelated words (`tagged`, `niche`) into the same namespace as the
markers, and a third layout mode would need a third top-level keyword.

The hard error follows the two in-tree precedents for retiring a spelling: the
Stage 14 `cast`→`as` retirement (`unsafe-namespace.md` UN-5) and the legacy
`name:ret` signature, whose *detection* machinery
(`sig-name-is-bare`/`legacy-ret-node`) is retained purely so each chokepoint can
say what to write instead (conventions.md, "`defn` signature").

## 3. What the change actually is

**Fourteen recognition sites, seventeen comparisons**, each a content compare
guarded by a `(= (x kind) NODE-SYM)` test. They collapse into three helpers in
`src/nucleusc.nuc`, placed beside `print-node` — nucleusc.nuc's whole-unit
prescan registers all its `defn`s before any import is processed, so
`generics.nuc` / `nuch.nuc` / `union-registry.nuc` all reach them:

- `marker-named (n name)` — the kind test folded in, null-safe, and callers pass
  the **bare** word (`"rest"`). That is what keeps the roster from being
  re-spelled fourteen times, and it removed every `"&rest"` string literal from
  the recognition path in one step.
- `marker-spelling (n)` — the source text for a diagnostic that quotes the
  marker back. The lexer strips a keyword's leading colon
  (`src/reader.nuc:426-439`), so it has to be put back; `declare-param-type` is
  the only caller.
- `marker-any (n)` — the three markers that terminate a parameter walk, for
  `defn-has-receiver-tyvars`. `:repr` is deliberately absent: it marks a
  defunion arm chain, never a parameter list.

Nothing in the compiler *constructs* a marker — every `intern-symbol` call in
`src/` was checked, so conventions.md's "a spelling sweep must also grep
`intern-symbol`" trap does not apply here.

Three sites needed more than a substitution:

- **`macro-parse-params`' name-collection pass** (`src/nucleusc.nuc:13781`) is a
  **negated** marker test, which does not read like a detection site; and the
  `"param must be a symbol"` check just above it rejects a `NODE-KEYWORD`
  outright, so the marker test had to move *ahead* of it.
- **`declare-param-type`** (`src/nuch.nuc:260`) sits directly above the arm that
  reads a `NODE-KEYWORD` operand as a *type* (`:i64`). Without the marker check
  first, `(declare f (a:i32 :rest xs:i32):i32)` reports `unknown type: rest`
  instead of the explicit refusal.
- **`defunion-strip-repr`** (`src/union-registry.nuc:839`) was the one site using
  `strcmp` rather than the overloaded `=`.

**The retirement** is `legacy-marker-name` + `reject-legacy-marker`, called from
four chokepoints — one per shape of form that carries a marker:

| Chokepoint | Covers |
|---|---|
| `desugar-params` (`src/nucleusc.nuc:14318`) | `defn`, `declare`, `defstruct` |
| `macro-parse-params` | `defmacro`, `macrolet` |
| `emit-extend`'s node-3 check (`src/generics.nuc:4284`) | `extend` |
| `defunion-strip-repr` | `defunion` arm chains |

`desugar-params` rather than `emit-defn`'s own scan, because desugar runs
straight off the reader, **before** any prescan: a `&where` defn no longer
registers as a template, so `prescan-defn-signatures` would otherwise reach
`parse-type-from-node` and die `unknown type: T` before `emit-defn` ever saw the
marker. The other three forms are not desugared at all, which is why each needs
its own.

## 4. Why two boot refreshes

`lib/macros.nuc`'s thirteen `&rest` macro headers are inside the **compiler's own
translation unit**: the prelude is auto-prepended (`prepend-prelude-import`,
`src/nucleusc.nuc:17390`) and `lib/prelude.nuc` imports `macros`, so the boot
compiler parses them on the very first `make` (`Makefile:85-87`). A one-commit
flip dies on the prelude before a single compiler form emits — the
chicken-and-egg class `context/build.md` enumerates.

So:

1. **Dual accept.** `marker-named` matches a `NODE-KEYWORD`, *or* a `NODE-SYM`
   whose first byte is `&` and whose tail equals the name. Sources unchanged.
   `make test` 755, fixed point holds, refresh.
2. **Sweep and retire, together.** With a dual-accepting boot, the tree can
   adopt `:rest` *and* drop `&rest` support in one step. Second refresh.

Three refreshes collapse to two because the boot only has to *read* the new
spelling, not still accept the old one.

The sweep itself is one command over `src/ lib/ examples/ tests/ docs/
context/` — 58 files:

```
sed -i 's/&\(rest\|optional\|where\|repr\)/:\1/g'
```

No over-matches: the other `&`-led tokens in the tree (`&body`, `&mut`,
`&local`, `&&label`, `&attributes`) are prose about other languages or an
unimplemented Stage 8 proposal, `.&` contains no marker name, and the one
`&optional` in `editor/nucleus-mode.el` is Emacs Lisp's own. `design/` (~460
occurrences) is historical record and was left alone.

## 5. What had to be measured rather than assumed

**`:rest` in a parameter list was already grammatically free.** It reads as
`NODE-KEYWORD` with `s = "rest"`, misses the `NODE-SYM`-guarded scan, misses
`extract-name-and-type`'s keyword-headed-**cell** branch
(`src/nucleusc.nuc:1364`, which needs a `NODE-CELL`), and fell through to
`defn: missing :type on param '(null)'`. Additive at the grammar level — a
marker keyword and an attribute keyword never occupy the same position.

**`fuse-colon-paren` does not fire on a marker.** It requires the atom to *end*
in `:` (`src/reader.nuc:1004-1008`), and a keyword's colon is leading and
already stripped, so `:where(Ord T)` with no separating space parses as marker +
constraint. Pinned. Worth knowing while writing the test: `:where((Ord T))` is
*not* the no-space form of `:where (Ord T)` — it is one constraint spelled
`((Ord T))`, and it correctly reports `each :where constraint must be
(Protocol Var)`.

**`print-node` already emits `:name` for a `NODE-KEYWORD`**
(`src/nucleusc.nuc:1062-1063`), which matters more than it looks: `.nuch` is a
**serialization format**, and `emit-nuch-defmacro` / `emit-nuch-defn` /
`emit-nuch-extend` print marker-bearing forms verbatim. The round-trip needed no
work — `scripts/check-headers.sh --fix` after the sweep reported *"regenerated
0"*, i.e. the sed-written headers already matched what the compiler emits.

**An `:optional` default that is itself a keyword value is safe.** The default
lives one level down inside a 2-element cell (`src/nucleusc.nuc:13196-13200`)
while the marker scan walks the top level only, so
`(defn f (a:i32 :optional (k:Keyword :fallback)):i32 …)` is unambiguous. Pinned,
because this is the one place a marker keyword and a *value* keyword appear in
the same form.

## 6. Two things the work uncovered

**`&repr` had no test coverage at all.** It was documented in
`docs/structs-unions.md` and used by nothing — not one example, fixture, or
library. `run_s16_keyword_markers` now covers both modes.

**`run_stdlib_table` had been dying silently, hiding a real regression.** It did
`out="$(python3 scripts/gen-stdlib-table.py --check 2>&1)"` — the exact `set -e`
trap its neighbour `run_headers_generated` documents at length: a failing
command substitution in a bare assignment kills the unit before its `FAIL` line,
so the harness saw an empty result file, printed nothing, and only the script's
**exit code** carried the failure. `make test` had been exiting 1 while showing
zero FAILs.

Behind it: the prelude split (this stage's `compile-time-imports.md`) removed
the `prelude → node → arena → stdio.h/stdlib.h` chain, so **165 libc functions**
(`printf`, `malloc`, `free`, `exit`, `fopen`, …) stopped being available without
an import, while `docs/stdlib.md` went on claiming all 220. Fixed both: the unit
now reports, and `docs/stdlib.md` is regenerated to the 55 `string.h` functions
that are actually reachable. The doc is host- and libc-dependent by construction
(the generator's own header says so), which is precisely why it is generated and
gated rather than hand-maintained.

**Generalisable:** a test harness that decides pass/fail by *scanning output*
must treat an empty result as a failure it can name. This one does count it
(`[ ! -s "$out" ] && fail=1`), but prints nothing, so the signal existed and was
invisible. Any assertion of the form "N tests, zero FAIL" is only as good as the
guarantee that every unit spoke.

## 7. Deliberately not done

- **The `has-rest`-by-count bug.** `src/nucleusc.nuc:15100-15102` and
  `src/nuch.nuc:570-573` infer `has-rest` from
  `(< (defn-params-count params) (node-len params))` rather than a marker scan,
  so an `:optional` defn is registered `has-rest = 1`. Pre-existing, untouched
  by the rename, and real — but folding a semantic fix into a spelling sweep
  would make both harder to review. **Follow-up.**
- **A never-instantiated parametric union's arms are never parsed**, so
  `(defunion (Box T) … &repr tagged)` with no instantiation reports nothing. Not
  introduced here: the same is true of the existing `:repr mode must be
  \`tagged\` or \`niche\`` diagnostic, verified both ways. Template arm
  diagnostics fire at stamp time, and that is a separate question about when a
  template body should be checked.
- **Reserving the markers in `g-special-form-set`.** That set is a reservation
  against *shadowing by a definer* (conventions.md, "`g-special-form-set` is a
  RESERVATION"), and a keyword cannot be a definition name, so there is nothing
  to reserve.
- **Deciding what `&` is for next.** Freed as a prefix; no claimant.

## 8. Verification

| Gate | Result |
|---|---|
| `make test` | **760** (was 755): +4 new assertions, +1 unit that had never reported |
| `make bootstrap` | `stage1.ll == stage2.ll`, converged after each of the two refreshes |
| `make abi-test` / `make layout-test` | PASS |
| `make check-headers` | 69 headers match |
| `make avr-test` | 8 PASS — blink 604, blink-dx 346, uart-hello 862, isr 654, global-init 604/bss=1 |

`make test` now exits **0**; before this it exited 1 with no FAIL line printed.

New unit `run_s16_keyword_markers`, four assertions:

- `s16-keyword-markers-accepted` — all four markers in one program, plus
  `:where(Ord T)` adjacency and a `Keyword`-valued `:optional` default.
- `s16-keyword-markers-legacy-rejected` — all seven legacy spelling × definer
  combinations name their replacement.
- `s16-keyword-markers-rules-preserved` — position, exclusivity, the `declare`
  refusal, and the generic-method refusal all still fire under the new spelling.
- `s16-keyword-markers-nuch-roundtrip` — a generated header carries `:where` and
  `:rest`, contains no `&` at all, and re-imports and runs.

**Definition of done:** no tracked source, test, or doc uses an `&` marker (the
only remaining mentions are the retirement fixtures, three comments explaining
what the rejection prevents, and Emacs Lisp's own `&optional`); each legacy
spelling is a located hard error naming its replacement; the boot IRs carry no
`&`-marker string constant; suite green; boot converged.
