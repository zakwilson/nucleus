# Orchestrator's record — Stage 15 stress-test fixes

**W1–W7 are complete; the stage was reopened on 2026-08-01 with two new items,
W8 and W9.** This document was the dispatch instruction set while W1–W7 were in
flight; it is kept as the record of how that work was run, what was actually
built, and the landmines a future stage of this shape should know about. The
W1–W7 record below is unchanged — nothing about it was revised when the stage
reopened. W8/W9 are new scope, not a re-opening of anything already closed. The specifications are the per-item docs in this directory
(`resolution.md`, `literal-typing.md`, `cheader.md`, `diagnostics.md`,
`ergonomics.md`, `nullability.md`, `selector-ambiguity.md`) — they remain the
source of truth for what shipped, including the grounded file:line references,
the design decisions, and each item's "as built" addendum.

The findings this stage addressed live **outside this repo**, at
`/home/zak/code/nuc-doom-claude/NUCLEUS-FINDINGS.md`. Every `§n.n` reference in
these docs is a section of that file.

One item (W6) was scoped as a **design document**, not an implementation; its
§3.4 triage sub-item turned out to be a small, independent, in-scope fix and
landed anyway (see §0 and §4 below).

---

## 0. Status

**W1–W7: every item Done.** **W8 and W9: added 2026-08-01, not started.**

| Item | Status |
|---|---|
| **W4** — Diagnostics | **Done** (W4a–W4e) |
| **W2** — Literal-operand lockstep | **Done** (W2a–W2d) |
| **W3** — C header interop | **Done** (W3a–W3c + the `declare`-parameter fallout) |
| **W5a, W5b, W5c, W5d, W5f** — Ergonomics + the union crash | **Done** |
| **W5e** — `defn-` name isolation | **Done** — Option 1, unconditional (an implicit per-file namespace for every private definer, decided by census: `src/` uses zero private definers of any kind, so no private-definer change could move the bootstrap) |
| **W1a + W1b** — Whole-graph signature/protocol prescan | **Done** |
| **W1c** — Unresolved-name diagnostic, three tiers | **Done** |
| **W1d** — Mutual-import policy | **Done** — decided twice the same day: Option 1 (keep `circular import` a hard error) was decided and built first, then **superseded by the user's choice of Option 2** (import cycles are legal, emitted idempotently per path) later the same day. `resolution.md`'s W1d section carries both decision boxes; the Option 1 box is kept in full because its reasoning about the *recommended* spelling is still what `docs/` teaches — Option 2 only changes whether the compiler also *permits* the alternative. |
| **W1e** — `declare` as a forward prototype | **Resolved by obsolescence**, no mechanism built |
| **W6** — Nullability flow typing | Design document **written** ([nullability.md](nullability.md)); its **§3.4 triage item landed** (a `null` global initializer into a typed non-null pointer is rejected like the identical local). Flow typing proper (§4 onward of the design) remains **design-only**, as scoped — no narrowing engine changes shipped in this stage. |
| **W7** — The bare-symbol selector always means "field name" | **Done** (options B + D + E; provenance: the author's own stress testing, not the Doom port — no `§` number) |
| **W8** — Combined declaration and initialization | **Designed, not started.** Spec: [../global-init.md](../global-init.md). Added to the stage 2026-08-01. |
| **W9** — Six defects found while measuring W8's design | **Reported, not fixed.** Enumerated in [../global-init.md](../global-init.md) §7. Added to the stage 2026-08-01. |

**Gate for W1–W7:** `make test` **328 PASS / 0 FAIL**; `make bootstrap`
byte-identical on the first pass; `make abi-test` and `make layout-test`
green. W8 and W9 have not been built and are not covered by it.

**The external regression — the only test that proves the stage achieved its
purpose (§6) — passed on 2026-08-01.** The Doom port at
`/home/zak/code/nuc-doom-claude` rebuilt against the finished compiler with
both named workarounds deleted, and both demo gates are bit-exact. Two
findings came out of that run and are recorded in §3 and §7 below, and in full
in [progress.md](progress.md)'s "The external Doom-port regression" section.

---

## 1. Required reading (as it stood during the stage; still the right order for a newcomer)

1. **[overview.md](overview.md)** — this stage's scope, ranking and ordering.
2. **[progress.md](progress.md)** — the complete record of what landed, each
   chunk's premise corrections, and the limitations discovered along the way.
   It is now the authoritative account; this document only orients.
3. **`/home/zak/code/nuc-doom-claude/NUCLEUS-FINDINGS.md`** — the findings
   report that seeded the stage. §8 is the ranked summary, §7 is "Things that
   worked well" (what the stage was not allowed to break).
4. **`CLAUDE.md`** (repo root) — the workflow rules.
5. **`context/local.md`** — the subagent-delegation workflow and the agent
   roster.
6. **`context/build.md`** / **`context/conventions.md`** — build flow and the
   compiler-editing gotchas, both required reading before touching `src/`.
7. The spec doc for whichever item you are studying — each carries an "as
   built" addendum (or, for W1d/W5e/W6 §3.4, an inline decision/Status box)
   that is the accurate account of what the code now does, more reliable than
   this document's original framing of any item.

---

## 2. How the work was done (process — enforced by CLAUDE.md and context/local.md)

This section is unchanged from the dispatch phase and is reusable guidance for
a future stage run the same way: **delegate; do not implement in the
orchestrating thread.**

* **principal-systems-architect** — reserved for gnarly, high-uncertainty
  work. Used for W5f (the union segfault, no obvious site going in) and W1a
  (whole-graph resolution).
* **systems-impl-engineer** — the compiler-internals chunks: W5d, W1c, the W6
  design document. W1d and W5e (both landed in the stage's final session) are
  the same shape of work — a compiler-internals change gated behind a design
  decision — and belong to this role too.
* **focused-task-implementer** — well-specified small work: W5a, W5c.
* **build-test-runner** — `make test` / `make bootstrap` runs and reporting.
* **api-docs-writer** — `docs/` updates and progress tracking, including this
  closing pass.
* **Explore** / **general-purpose** — read-only research, to keep file reading
  out of the main thread.

**Write the briefs yourself and put the facts in them.** The spec docs already
carry grounded file:line references and verified repros — copying the
relevant ones into each brief, rather than pointing an agent at the whole of
`NUCLEUS-FINDINGS.md` plus this whole directory, was the single biggest cost
control available.

**Ask every agent to correct you — this held for the entire stage, not just
the first half.** By the close of the stage a dispatched agent had found a
wrong premise in nearly every phase: W2a corrected a predicate name and a
repro's reproduction conditions; W2b found the spec's "constants are stored
`i64`" claim false; W3a corrected "the fix is one branch"; W3b found the
finding was about type *qualifiers*, not `void`; W3c found the defect was "no
scalar typedef resolves" rather than one degrading chain; W4c found the
file's premise about which line was blamed was backwards; the original §3
repro E (below) was wrong and had to be replaced before W1 could be built
against it. The four chunks that closed the stage kept the pattern exactly:
**W1d** found the design box's "a body taking `(sizeof S)` does not survive a
cycle" claim was *half* wrong (`sizeof`/`alloca` are fine — they resolve
against the LLVM named type, not the compiler's field table) and, measuring
rather than trusting the box's enumeration, turned up a *fourth*,
previously-unlisted coupling that was the only one silently miscompiling (a
by-value struct at an ABI boundary sized itself 0). **W5e** found a second,
unreported defect (`defvar-` collision, worse symptom than the reported
`defn-` one) fall out of the same census that decided the recommended option.
**W6 §3.4** found its own "zero compiler churn" blast-radius measurement was
one site short — it had scanned `src/`+`lib/` only, and `examples/` had a real
user of the hole. **The Doom-port regression run** found a live diagnostic
that asserts something false (`defconst`/`defenum` "not defined anywhere in
this compilation unit" when the name is merely not yet processed) — a defect
this stage did not set out to find and is now the top candidate for the next
one. *If you dispatch a stage like this again, keep asking for this
explicitly — the return on it has not diminished once across sixteen
chunks.*

**Keep it green at every step** held throughout: `make test` passed and
`make bootstrap` was a byte-identical fixed point after every chunk except
the two noted in §5.

---

## 3. Regression inventory

Every program below was, at some point in the stage, a **live failure** —
invalid IR, a wrong answer, a silent no-op, or a segfault. All are now fixed
and compile/link/run correctly. They are permanent regression markers: if any
one of them ever fails again, something has regressed. (§3 used to be phrased
as repros to *verify are still broken* before building against them; that
phase is over.)

```lisp
; A — W2 §1.2: was invalid IR. FIXED (W2a). Compiles, links, runs, exit 0.
(defn main ():i32 (let (p:ptr (malloc (* 4096 (as i64 (sizeof i32))))) (return 0)))

; B — W2 §1.3: operand order used to change the answer. FIXED (W2a). exit 0.
(defvar cl:ui32 5)
(defn main ():i32 (let (t:ui32 9) (when (> t (* 2 cl)) (return 1))) (return 0))

; C — W4 §3.2: was silent non-registration at line 0. FIXED (W4b), by rejection:
(defconst K:i32 2)
(defn main ():i32 (return K))
;   now: c.nuc:1: error: defconst: takes no type annotation; write (defconst K 2)

; D — W5f §1.1: was a SIGSEGV (exit 139). FIXED (W5f) — turned out to be a
; colon-paren *reader* gap (a function-pointer type is two paren groups and
; the fuse absorbed only one, leaving a stray '()' that read as NULL), not a
; union bug. Compiles, links, runs, exit 0.
(defstruct Row (action (union acv:(fn void)())))
(defn main ():i32 (return 0))
```

### Repro E — the original was wrong; the corrected shape is what W1 was built against, and both arms now work

Kept prominently because the correction is still instructive: this document
originally claimed a mutual-reference pair (`xf` calls `y-later` in `yf`; `z`
imports both) failed **in both import orders**. It did not — measured, one
ordering compiled cleanly. That means the original E only showed that a file
which declines to import what it references is order-sensitive, which is
arguably correct behaviour, not a bug. `resolution.md`'s own Status box made
the same point; this document was the stale copy of it at the time.

**The shape that genuinely admits no ordering is mutual *dependency***, and it
is what W1a/W1b were built and accepted against:

```lisp
; mx.nuc
(defn x-uses ():i32 (return (y-later)))
(defn x-helper ():i32 (return 7))
; my.nuc
(defn y-later ():i32 (return (x-helper)))
; m.nuc
(import mx) (import my) (defn main ():i32 (return (x-uses)))
```

Both arms now compile, link and run (`tests/` units `w1-mutual-order1` /
`w1-mutual-order2`) — no import edge is needed *between* `mx.nuc` and
`my.nuc` at all; a common parent importing both is sufficient and is the
**recommended** spelling (`docs/toplevel.md`'s "Cross-file resolution"
section states this as a language rule, not a diagnostic tweak).

**A second, complementary shape is also now legal, via a different
mechanism.** Two files that actually `(import)` *each other* — a literal
cycle, not just a shared parent — used to be a hard `circular import` error.
Since **W1d landed as Option 2**, that is legal too: the compiler emits each
file at most once, at first reach, idempotent per path. It remains the
**non-recommended** spelling (the common-parent form is still what `docs/`
teaches), but it is supported, with four emission-time couplings (a partner's
`defmacro`, a `defconst`/`defenum` member, a struct/union layout, a
`prefix/name` alias) diagnosed with a located, cycle-naming error rather than
silently miscompiled. See `resolution.md`'s W1d SUPERSEDED box and
[progress.md](progress.md)'s W1d table row for the full account.

**The diamond shape** (two files importing one shared leaf) worked before W1
and stays working (`w1-diamond`) — it never needed this stage's fix, and is
kept in the suite as a negative control that W1a's walk did not regress it.
**Two-independent-higher-files** and **two-routes-to-one-file**
(`w1-two-higher`, `w1-two-routes`) are the other permanent regression shapes
from the accept matrix.

---

## 4. What was built (per item — see progress.md and the spec doc for full detail)

### W4 — Diagnostics (done first, because it made every later item debuggable)

Five chunks (W4a–e), all done, in order. Every diagnostic now names a real
line (the interned-symbol-has-no-line-of-its-own root cause, fixed by
borrowing the enclosing form's line); `defconst`/every sibling definer rejects
a colon-annotated name at its own line instead of silently mis-registering;
unterminated forms name the line that actually localizes the imbalance;
`case`'s and one-armed `if`'s errors name the real mistake instead of the
mechanism; the generated stdlib-availability table and two stale
`docs/special-forms.md` claims were corrected. Detail: [diagnostics.md](diagnostics.md), [progress.md](progress.md).

### W2 — `node-type` ↔ `emit` literal-operand lockstep

Four chunks (W2a–d), all done. One root cause across the first two — a
binary operator's statically inferred type and its emitted type could
disagree, because they lived in two different functions — collapsed to a
single `binop-result-type` chokepoint; a `defconst`/`defenum` name now types
like the literal it stands for (and a too-large constant no longer wraps);
the float coercion chokepoint gained the case it was entirely missing,
closing both a rejection class and a silent miscompile. Detail:
[literal-typing.md](literal-typing.md), [progress.md](progress.md).

### W3 — C header interop

W3a/b/c plus the `declare`-parameter fallout, all done. Opaque
forward-declared C types (`struct Foo;`, `FILE`) register layout-less instead
of being skipped; east-position type qualifiers (`int const *p`) no longer
manufacture a phantom parameter; typedef chains resolve transitively instead
of degrading to `ptr` at the first unrecognized name. `SDL2/SDL.h` imports
with zero warnings, links and runs. Detail: [cheader.md](cheader.md),
[progress.md](progress.md).

### W5 — Ergonomics and the union crash

All six sub-items done. `\xHH` string escapes; `bit-not` as a one-argument
macro over `(bit-xor x -1)`; a `CStr`-typed `defvar` (which exposed and fixed
a `strcmp(ptr, null)` segfault reachable from any `(= cstr null)` guard);
array-literal ergonomics (auto-deref for struct compound-literal elements,
element-type inference for array-of-pointer locals); the union/function-pointer
segfault, root-caused to the colon-paren reader as described in repro D above;
and **W5e**, `defn-` name isolation, landed 2026-08-01 as **Option 1,
unconditional** — every private definer with no enclosing `(ns …)` is keyed
under an implicit per-file namespace (`#p1/helper`), decided by a census
showing the compiler's own source uses zero private definers of any kind, so
no private-definer change could move the bootstrap. A second, unreported
defect (`defvar-` collision, worse symptom) fell out of the same census and
was fixed by the same mechanism. Detail: [ergonomics.md](ergonomics.md)'s
per-item "as built" sections, [progress.md](progress.md).

### W1 — Whole-unit signature resolution (done last, as planned, against a green diagnostics-improved tree)

W1a+W1b (inseparable — the whole-graph prescan and its per-file namespace
correctness) extended `prescan-imported-signatures` to register every
reachable file's protocols and `defn` signatures before any form is emitted,
retiring the ordinal rule *"X may reference Y ⟺ Y begins processing before X
is emitted."* W1c distinguished the three ways an unresolved name can fail
(C-header skip, unreachable-file, plain typo) instead of leaving them all as
one generic message. **W1d**, landed 2026-07-31: mutual-import policy,
decided as Option 1 and built, then superseded the same day by the user's
choice of **Option 2** — import cycles are legal, emitted idempotently per
path, with four emission-time couplings diagnosed rather than silently
miscompiled (see §3 above for the mechanism summary and `resolution.md`'s two
decision boxes for the full reasoning, including why Option 1's advice was
correct advice *and* Option 2 was still worth having). **W1e** stayed
resolved by obsolescence — `emit-nuch-declare-import`'s existing
early-return-on-already-registered behaviour, which W1a makes fire *more*
often, already covers the one hazard the design doc worried about. Detail:
[resolution.md](resolution.md), [progress.md](progress.md).

### W6 — Nullability flow typing

The design document ([nullability.md](nullability.md)) is written in full,
covering the ground-truth narrowing engine that already existed, two live
soundness bugs found while measuring it, a two-form place language with
stability conditions, and a worked-examples/diagnostics/implementation-sketch
tail. Its **§3.4 triage item** — whether the "a `let` local bound to `null`"
complaint was actually independent of flow typing — resolved to "yes, and the
real defect is one line over": `defvar`'s **global** initializer bypassed the
same check the **local** path already enforced. That landed as a
narrowly-scoped fix (`defvar-init-ir` now calls the identical
`pkind-flow-check` predicate the local path calls), explicitly **not** a
narrowing-engine change — no `src/` code outside that one bypass was touched.
Left deliberately open, and recorded as the top follow-up: `emit-defvar`'s
**no-initializer** default emits the identical unsound `global ptr null`,
which the external Doom port hit 13 times in this stage's own closing run
(§3's finding 1, and [progress.md](progress.md)'s Doom-port-regression
section).

### W7 — The bare-symbol selector always means "field name"

Done, independent of every other item, before this closing pass began. See
[selector-ambiguity.md](selector-ambiguity.md) and
[progress.md](progress.md)'s W7 section for the full account — nothing about
it changed during this closing pass.

### W8 — Combined declaration and initialization *(added 2026-08-01; designed, not started)*

**Spec: [../global-init.md](../global-init.md).** It is the source of truth and
this section deliberately does not duplicate it.

**Headline goal: eliminate `compiler-init`, or reduce it to a few genuinely
special cases.** A global that should not be nullable is **declared and
initialized in one operation**, and the startup call is **zero-cost when
unused** — a program with no runtime initializer emits no `@__nucleus_init`, no
`llvm.global_ctors` entry and no synthesized `main`. That last is a hard
requirement, not an optimization; the stated reason is microcontroller binary
size.

Three things about it that a dispatcher should know before reading the spec:

* **It closes what W6 §1.5 parked.** `(defvar g:ptr:T)` still emits the
  identical unsound `global ptr null` that the explicit-`null` spelling now
  rejects. W6 could not close it because the language has no way to express
  deferred initialization of a non-null global. That is what this item builds.
  It is also §7's `emit-defvar` bullet below, now assigned rather than deferred.
* **Its G-0 subsumes §7's `defconst`/`defenum` import-order bullet** — the
  Doom-port regression run's second finding. G-0 is a prerequisite for the rest
  of W8 (an initializer expression can name another global, and would hit name
  resolution before it ever reached an ordering rule) and is **shippable on its
  own**.
* **The spec corrected two of its own first-draft conclusions**, both by reading
  `src/`: the `g-arena-alloc` migration blocker turned out to be a compile-time
  *constant* struct and dissolves, and a synthesized `main` wrapper turned out
  to be incompatible with zero-cost-when-unused. Both corrections are recorded
  in place, per this stage's practice.

### W9 — Six defects found while measuring W8's design *(added 2026-08-01; reported, not fixed)*

**Enumerated in [../global-init.md](../global-init.md) §7.** All six are
pre-existing, none was introduced by W1–W7, and all were hit while measuring —
not synthesized:

1. **`make lib-objs` / `make lib-so` are broken**, and reproduce on the
   committed boot compiler. `lib/arena.nuc` and `lib/node.nuc` die `duplicate
   definition of 'arena-init' / 'alloc-node'`; `lib/reader.nuc` dies
   `undefined: stderr`.
2. **Two separately compiled Nucleus objects cannot be linked** — each inlines
   the whole prelude, so `build/lib/vector.o` and `build/lib/hashmap.o` share
   **7** duplicate public global definitions (`@g-arena`, `@g-intern-table`, …)
   and `ld` refuses. The `exclude-prelude` route works; a non-freestanding
   library is currently unlinkable.
3. **`--emit-cheader` does not export globals.** A `defvar` reaches the `.nuch`
   as `(extern …)` but gets no `extern T name;` line in the C header, so a C
   consumer cannot reach it.
4. **`--emit-cheader` emits hyphenated, invalid C identifiers.** Independently
   confirmed: `(defstruct My-Rec (a-field i32))` + `(defn my-func (x:i32):i32 …)`
   emits `int32_t a-field;` and `int32_t my-func(int32_t x);` while the struct
   *type* name is correctly sanitized to `My_Rec`. **The defect is that
   `sanitize-for-c` reaches type names but not field names or function names —
   a missed call site, not a missing mechanism.** It breaks C interop for any
   hyphenated name, which is most of them.
5. **`(exclude-prelude)` in an *imported* file dies `unknown top-level form`**
   rather than being ignored or diagnosed as "must be the first form of the
   unit". `strip-exclude-prelude` is consulted only for the entry file.
6. **The misleading `undefined: X — not defined anywhere in this compilation
   unit`** for a `defvar`/`defconst`/`defenum` that *is* in the unit but has not
   been processed yet. **This overlaps W8's G-0 and is not filed twice** — G-0
   fixes the cause; in the interim the message deserves a W1c-style note, which
   is the pattern W1c already established for exactly this shape of "the
   diagnostic asserts something false" failure.

1 and 2 are directly relevant to W8: they are the multi-TU mode `global-init.md`
§2.4 depends on for its "an initializer reachable only from the consumer's
`main` cannot initialize a library" conclusion.

---

## 5. Landmines (as they stood; updated with how each resolved)

1. **The bootstrap fixed point was the primary safety net, and it held for
   nearly the whole stage.** Original prediction: *"W1a and W5d are the
   likeliest remaining items to move IR legitimately."* **Resolved:** W1a did
   move IR — 44 lines, all `%Name = type {…}` definitions moving within the
   type section (LLVM named types are order-independent in a module; sorting
   both files' type-definition lines made them byte-identical), proven inert
   and reconverged via the standard cycle. W5d, contrary to the prediction,
   held byte-identical on the first pass — its rule reaches an existing
   chokepoint (`coerce-int-val`) rather than introducing a new one, and no
   compiler source uses the shapes it relaxes. **Every other chunk in the
   stage — W1c, W1d, W2a–d, W3a/b, W5a/b/c/e/f, W6 §3.4, W7 — held
   byte-identical on the first pass**, with the sole other exception being
   the **W3c `declare`-parameter fix**, whose 6-line diff (exactly the
   compiler's own two `repl_print_f*` declarations) was audited against all
   189 compiling `examples`/`lib`/`fixtures` programs before reconverging.
   Final tally for the stage: **two** chunks legitimately moved IR (W1a,
   W3c-fallout), both proven inert before reconverging; every other chunk was
   additive by construction.
2. **The duplicate-signature check was never weakened.** Held throughout,
   including under W1d's cycle support — a `run_w1d_cycle_diagnoses` unit
   specifically asserts a genuine duplicate is still rejected *inside* a
   cycle, not just outside one.
3. **`prescan-imported-types` not applying per-file namespaces** was the
   latent hazard W1b closed as part of W1a, not as a follow-up. No later
   chunk reopened it.
4. **C-header imports stayed skipped in every prescan walk**, including
   W1d's cycle-support changes — a cycle diagnostic never needs to read a
   header, since the four couplings it covers (macro/const-member/layout/
   alias) are all pure-Nucleus concerns.
5. **W1 was built against the corrected repro E**, not the original — see §3.
   Confirmed still true at stage close: both arms of the mutual-dependency
   shape are permanent regression tests.
6. **W6 stayed a document**, with exactly one narrowly-scoped exception
   (§3.4's global-initializer fix) that the design doc itself flagged as
   possibly independent of flow typing and asked to be triaged first — it
   was, and the triage was correct. No narrowing-engine code shipped.
7. **No test was narrowed to make it pass**, and the pattern recurred at
   stage close: **W1d replaced `run_w1_circular_still_errors` with
   `run_w1d_cycle_accepts` rather than deleting it quietly** — the old test's
   assertion (cycles are a hard error) became false under the new decision,
   so it was superseded visibly, with a comment trail in `resolution.md`
   explaining why, rather than just removed.
8. **A `defmacro` body still cannot call `die-at`/`report-at`.** This
   directly shaped W1d's design: the reason cycles do not support macros is
   exactly this constraint (registering a macro early means *emitting and
   JIT-compiling* it early, which is a separate, unscoped problem) — not a
   diagnostic limitation that could be worked around inside `lib/macros.nuc`.

---

## 6. Definition of done — **met, 2026-08-01**

* W1 and W5 implemented per their spec docs, with every deferral recorded in
  that spec doc: **met.** (W1d's decision and mechanism are in
  `resolution.md`'s two inline boxes; W5e's in `ergonomics.md`'s "as built"
  section.) W6 delivered as a design document, plus its §3.4 triage item
  landed as an independent fix: **met.**
* `make test` passes; `make bootstrap` is a byte-identical fixed point:
  **met** — 328 PASS / 0 FAIL, `make abi-test`/`make layout-test` green.
* New `tests/` cases with `tests/expected/` fixtures for the corrected W1
  mutual-dependency shape, the diamond, two-routes-to-one-file, all four W5f
  union spellings, and each landed W5 sub-item: **met**, plus additional
  coverage the original definition-of-done did not anticipate (W1d's cycle
  accept/diagnose/prefix suites, W5e's private-isolation suite).
* `docs/` updated per each spec doc: **met** — each implementing agent
  updated its own feature's `docs/` pages as it landed; this closing pass
  additionally fixed a stale `docs/compiler.md` claim (the `bit-not`
  stopgap-error example, superseded by W5b) and documented `bit-not` itself,
  which had shipped with no `docs/` entry.
* `design/stage15-stress-test/progress.md` accurate, with a complete W5
  section: **met.** `design/overview.md` references this stage as done, not
  planned: **met.**
* **The external regression: met.** The Doom port at
  `/home/zak/code/nuc-doom-claude` rebuilt with its workarounds removed
  (`src/g_game.nuc`'s import ordering, the `(as ui32 SOME_DEFCONST)` casts),
  and both demo gates report bit-exact:

  ```
  == test_demo: 182 checks passed, 0 failed ==
  ALL 35 TICS BIT-EXACT

  == test_demo_monsters: 1654 checks passed, 0 failed ==
  ALL 150 TICS BIT-EXACT (WITH MONSTERS, vs the real engine)
  ```

  The run needed source changes beyond deleting workarounds — that is a
  finding, recorded per §7 below and in full in
  [progress.md](progress.md)'s Doom-port-regression section.

---

## 7. Explicitly out of scope (not built here; candidates for the next stage)

* **Replacing the hand-rolled C parser with libclang.** W3 met its bar
  without it (all three header-ladder rungs reached). Still not acted on.
* **Struct packing (§4.1) and fixed-size array struct fields (§4.2).** Both
  real gaps, both genuinely painful in the port, both wanting a
  layout-attribute design that overlaps
  [stage14/attributes.md](../stage14/attributes.md)'s reserved-but-unimplemented
  `:align`/`:section` slots. Still the top layout-design candidates for the
  next stage.
* **`defconst`/`defenum` members are still import-order dependent — the
  Doom-port regression run's finding. Now assigned: it is W8's G-0**
  ([../global-init.md](../global-init.md) §5), which extends W1a's whole-graph
  walk to value names and is shippable on its own. W1 covered `defn` signatures and
  protocols only; a name defined in a sibling file and referenced before that
  sibling is processed dies with a diagnostic that asserts it is "not defined
  anywhere in this compilation unit," which is false — it is merely not yet
  processed. Fixing this is architecturally the same shape of problem W1a
  solved for signatures (a whole-graph prescan), scoped separately here
  because `defconst`/`defenum` **values**, unlike signatures, are needed at
  *emission* time, not just at resolution time, so a naive prescan is not
  automatically additive the way W1a's was.
* **`emit-defvar`'s no-initializer unsoundness — the second Doom-port
  finding, and a duplicate of W6 §3.4's deliberately-left-open item, not a
  new one. Now assigned: it is W8's G-5** ([../global-init.md](../global-init.md)
  §5). `(defvar g:ptr:Thing)` still emits the same `global ptr null`
  the §3.4 fix now rejects for the explicit `null` spelling. Recorded twice
  (here and in W6's own section) because it was hit twice: once by the
  compiler's own 53-site census, once by the external port 13 times. W8 is the
  answer to "closing it needs a way to express deferred initialization of a
  non-null global, which the language does not have".
* **Nullability flow-typing implementation** (W6 stayed design-only),
  nullability *inference* across function boundaries, and `?T` monad
  ergonomics.
* **Type reachability** (§2.7): a struct type named in a unit's signatures
  must still be defined in a reachable file. W1 removed the *order*
  constraint, not the reachability constraint, and that did not change.
* Anything the findings report lists in its §7 "Things that worked well" —
  cross-file struct prescan, typed function pointers + `funcall`, arity
  overloading, `f32` bit-exactness, duplicate same-value `defconst`, `.set!`
  struct copies, compile speed. Verified undisturbed by the external
  regression run.
