# Implementation prompt — Stage 15 stress-test fixes

You are implementing **Stage 15**: the deficiencies found by using Nucleus for a
real external project. The specifications are the per-item docs in this directory
(`resolution.md`, `literal-typing.md`, `cheader.md`, `diagnostics.md`,
`ergonomics.md`, `nullability.md`) — they are the source of truth, including the
grounded file:line references and the design decisions. Where this prompt and a
spec doc disagree, **the spec doc wins**. If you think a design is wrong, **stop
and raise it** rather than silently diverging.

The findings this stage addresses live **outside this repo**, at
`/home/zak/code/nuc-doom-claude/NUCLEUS-FINDINGS.md`. Every `§n.n` reference in
these docs is a section of that file.

One item (W6) is a **design document only**, not an implementation.

---

## 0. Status — what is already done

**Do not re-dispatch a completed item.** [progress.md](progress.md) is the record
of what landed and is required reading before any dispatch.

| Item | Status |
|---|---|
| **W4** — Diagnostics | **Done** (W4a–W4e) |
| **W2** — Literal-operand lockstep | **Done** (W2a–W2d) |
| **W3** — C header interop | **Done** (W3a–W3c + the `declare`-parameter fallout) |
| **W5** — Ergonomics + union crash | **W5a, W5b, W5c, W5d, W5f done**; only W5e remains (sequenced after W1) |
| **W1** — Whole-unit signature resolution | Not started |
| **W6** — Nullability flow typing (design only) | Not started |

Measured on the integrated tree after W5a/W5c/W5d/W5f landed together: `make test`
**279 `PASS`, 0 `FAIL`**; `make bootstrap` byte-identical on the first pass;
`make abi-test` and `make layout-test` green.

**Remaining order: the §3.4 global-init null fix, then W5e, then W1.** W6's
design document is written; its §3.4 triage produced a small independent fix that
is *not* yet landed — `(defvar g:ptr:Thing null)` compiles clean and segfaults
while the identical local is rejected, because the global initializer is a
constant renderer that never routes through `coerce-int-val` and so never runs
`pkind-flow-check`. W5c deliberately left that hole untouched and pinned a
`CStr` carve-out (`tests/fixtures/w5c-cstr-null-exempt.nuc`) so the fix cannot
sweep `CStr` up with `ptr`. W5e stays sequenced after W1. This is the tail of `overview.md`'s W4→W2→W3→W5→W1 ordering; the
reasoning is unchanged, and W1's "goes last, against a green tree with the
diagnostics already improved" precondition is now satisfied.

Three of `overview.md`'s ordering claims have already paid off and are worth
knowing before you dispatch: W4's located diagnostics are what made W3c's
precedence bug findable, W2 and W3 each surfaced defects strictly larger than
their spec's framing, and every completed item held the bootstrap fixed point on
the first pass except the W3c `declare`-parameter fix (which needed one
`make update-bootstrap` reconverge, for a 6-line diff that was audited first).

---

## 1. Required reading (do this first, do not skip)

1. **[overview.md](overview.md)** — this stage's scope, ranking and ordering.
2. **[progress.md](progress.md)** — what has already landed, each chunk's premise
   corrections, and the limitations discovered along the way. Reading this is how
   you avoid re-deriving a correction someone already paid for.
3. **`/home/zak/code/nuc-doom-claude/NUCLEUS-FINDINGS.md`** — the findings report.
   Read §8 (the ranked summary) and §7 ("Things that worked well" — it tells you
   what *not* to break), then the sections for the item you are dispatching.
   Do **not** make subagents read the whole file; extract what each needs into its
   brief (see §2).
4. **`CLAUDE.md`** (repo root) — the workflow rules. Not optional.
5. **`context/local.md`** — the mandatory subagent-delegation workflow and the
   agent roster.
6. **`context/build.md`** — build flow and bootstrap artifacts.
7. **`context/conventions.md`** — required before any compiler edit.
8. The spec doc for whichever item you are dispatching, plus:
   - W5 → per sub-item, listed in `ergonomics.md`; W5c also needs
     `design/stage14/native-strings.md`.
   - W1 → `resolution.md` **including its two inline Status boxes**, which
     supersede the body text around them; `src/nucleusc.nuc` `emit-toplevel-forms`
     (~9246), `prescan-imported-types` (~8884), `prescan-defn-signatures` (~9020),
     `do-import` (~9606); `src/nuch.nuc:146-159`.

For the completed items, the "as built" addenda in `literal-typing.md`,
`cheader.md` and `diagnostics.md` are the accurate account of what the code now
does — prefer them over this prompt's original framing of those items.

---

## 2. How to work (process — enforced by CLAUDE.md and context/local.md)

**Delegate; do not implement in the orchestrating thread.** Plan the split, then
dispatch each chunk, each well under ~100K tokens. §4 names the chunks and the
agent for each. Agent selection per `context/local.md`:

* **principal-systems-architect** — *use sparingly*. Reserved for exactly two
  chunks in what remains: **W5f** (the union segfault, which is gnarly debugging
  with no obvious site) and **W1a** (whole-graph resolution). Do not spend it
  elsewhere.
* **systems-impl-engineer** — the compiler-internals chunks: W5d, W1c, and the W6
  design document.
* **focused-task-implementer** — well-specified small work: W5a, W5c.
* **build-test-runner** — `make test` / `make bootstrap` runs and reporting.
* **api-docs-writer** — `docs/` updates and progress tracking.
* **Explore** / **general-purpose** — read-only research, to keep file reading out
  of the main thread.

Ask subagents for **concise summaries, not file dumps.**

**Write the briefs yourself and put the facts in them.** These spec docs already
carry the grounded file:line references and the verified repros — copy the
relevant ones into each brief rather than telling an agent to read all of
`NUCLEUS-FINDINGS.md` plus this whole directory. That is the single biggest cost
control available, and it was learned the hard way on the project that produced
these findings.

**Ask every agent to correct you.** On the project that generated these findings,
a dispatched agent found a wrong premise in its brief in *every* phase from the
fourth onward. This stage has now reproduced that exactly: W2a corrected a
predicate name and a repro's reproduction conditions, W2b found the spec's
"constants are stored `i64`" claim false, W3a corrected "the fix is one branch",
W3b found the finding was about type *qualifiers* and not `void` at all, W3c
found the defect was "no scalar typedef resolves" rather than one degrading
chain, W4c found the file's premise about which line was blamed was backwards,
and the §3 probes below falsified this prompt's own W1 repro. Say so explicitly
in each brief: *if a premise here is wrong, say so directly; that is the most
valuable thing you can return.*

**Keep it green at every step.** After each chunk: `make test` passes and
`make bootstrap` is a **byte-identical fixed point**. Read §5 on why that matters
more in this stage than usual.

**Closing steps are required, not optional:**
* `docs/` for every user-visible change (each spec doc lists its own).
* `design/stage15-stress-test/progress.md` — update it; record what landed, what
  deferred and why, and any new limitation discovered.
* Update each spec doc in place where it says to record a decision or a triage
  result (remaining: W5e, W6's §3.4 triage; W1d and W1e's §3 probe is already
  recorded — see below).
* Note this stage in `design/overview.md`'s document list.
* **Self-improving context:** fix root causes; add a `context/` note only for a
  genuinely unfixable environment gotcha.

---

## 3. Verify the ground before you build

Every repro in these docs was confirmed against `build/nucleusc` at the time of
writing. **Re-confirm before building.** Note that on this host the committed
`bin/nucleusc` may link a newer libLLVM than the container ships; if it fails to
exec (exit 126/127), `make` rebuilds it from the committed IR automatically
(`ensure-boot`).

**Run the probes from the repo root.** The prelude is resolved relative to the
invocation, so a probe run from elsewhere fails with
`import: cannot find 'prelude'` at line 0 — an artifact of the working directory,
not a live bug.

### Measured state of the five load-bearing repros (re-probed 2026-07-31)

```lisp
; A — W2 §1.2: invalid IR.  FIXED (W2a). Now compiles, links and runs, exit 0.
(defn main ():i32 (let (p:ptr (malloc (* 4096 (as i64 (sizeof i32))))) (return 0)))

; B — W2 §1.3: operand order changes the answer.  FIXED (W2a). Now exit 0.
(defvar cl:ui32 5)
(defn main ():i32 (let (t:ui32 9) (when (> t (* 2 cl)) (return 1))) (return 0))

; C — W4 §3.2: silent non-registration at line 0.  FIXED (W4b), by rejection:
(defconst K:i32 2)
(defn main ():i32 (return K))
;   now: c.nuc:1: error: defconst: takes no type annotation; write (defconst K 2)

; D — W5f §1.1: segfault.  STILL LIVE — SIGSEGV, exit 139.
(defstruct Row (action (union acv:(fn void)())))
(defn main ():i32 (return 0))
```

Repro **D is the only one of the five still failing as originally documented**,
and it is the pre-flight check for W5f. A–C are now regression tests, not repros:
if any of them fails again, something has regressed.

### Repro E was wrong, and the corrected shape is what W1 must be built against

The original E (`xf` calls `y-later` in `yf`; `z` imports both) claimed to fail
**in both import orders**. It does not. Measured:

* `(import xf) (import yf)` → `xf.nuc:1: error: unknown: y-later`
* `(import yf) (import xf)` → **compiles, exit 0**

One ordering works, so as written E only shows that a file which declines to
import what it references is order-sensitive — arguably correct behaviour.
`resolution.md`'s own Status box says the same and is the authority here; this
prompt was the stale copy.

**The shape that genuinely admits no ordering is mutual dependency**, and it does
still fail today:

```lisp
; mx.nuc
(defn x-uses ():i32 (return (y-later)))
(defn x-helper ():i32 (return 7))
; my.nuc
(defn y-later ():i32 (return (x-helper)))
; m.nuc
(import mx) (import my) (defn main ():i32 (return (x-uses)))
```

* `(import mx) (import my)` → `mx.nuc:1: error: unknown: y-later`
* `(import my) (import mx)` → `my.nuc:1: error: unknown: x-helper`

Neither order resolves, and import-what-you-use cannot fix it because the import
graph must stay acyclic. **This is repro E for all W1 purposes.** Use it in the
brief and in `tests/`.

The **diamond** shape (two files importing one shared leaf) already works today —
verified, exit 0. Do not spend W1 on it; do add it as a regression test.

### The §2.4 mutual-import uncertainty is discharged

This section previously ordered a probe before W1d could be decided.
**It has been run** (recorded in `resolution.md`, "Import emission already dedups"
Status box) and re-confirmed today: a bare mutual `(import …)` takes the explicit
`g-importing` path and reports `import: circular import of 'X'` at a real line.
There is no `duplicate method signature` to chase, so W1d's "fix
`emit-import-prefixed` to give the circular diagnostic instead" clause is moot.

That Status box flagged the **path-form** spelling as untested. It is now tested:
`(import "/abs/path/sx.nuc")` in both directions also reports
`import: circular import of '<path>'`. Both spellings take the same path; nothing
reaches the aliasing route. Prefixed imports (`import-prefixed`) remain unprobed —
probe them only if W1d's decision actually turns on them.

If **D**, or either arm of the corrected **E**, no longer reproduces as stated
above, **stop and report** — the remaining plan is built on them.

---

## 4. What to build

### W5 — Ergonomics and the union crash (do first) · spec: [ergonomics.md](ergonomics.md)

Five sub-items remain and are independent — **this is the item to fan out in
parallel**, with the two exceptions noted below.

* **W5b** — *(done)* `bit-not` as a macro over `(bit-xor x -1)` (`lib/macros.nuc:79`).
  W4a's stopgap "no unary 'bit-not'" suggestion was removed when it landed, as the
  spec required. Its section is gone from `ergonomics.md` and it is recorded in
  `progress.md`.
* **W5a, W5c** *(focused-task-implementer, parallel)* — `\x` escapes (still live:
  `"MUS\x1a"` dies `unknown escape \x`, now with a correct line); `CStr`-typed
  `defvar`. W5c must read `design/stage14/native-strings.md` first (NS-3 flipped
  literals to `StrView`).
* **W5d** *(systems-impl-engineer)* — array-literal ergonomics: auto-`deref` for
  struct compound literals as elements, and element-type inference for
  array-of-pointer locals. **Do not regress the 1000-row `(array Struct …)` case** —
  it is how generated tables are built.
* **W5f** *(principal-systems-architect)* — the union/function-pointer segfault,
  **confirmed live today at exit 139**. `ergonomics.md` names the candidate sites
  and explicitly warns **not** to assume the obvious one. Outcome may be working
  code or a clean diagnostic; **no segfault under any of the four spellings
  listed.**
* **W5e** *(principal-systems-architect or systems-impl-engineer)* — `defn-` name
  isolation. **Sequence this AFTER W1**, or take the option-2 fallback for this
  stage: it touches the same global-key scheme W1 changes, and running both
  concurrently in separate subagents will conflict.

### W1 — Whole-unit signature resolution (do last) · spec: [resolution.md](resolution.md)

Read `resolution.md`'s inline Status boxes first — they correct the body text
around them, and one of them retires part of W1d.

* **W1a + W1b** *(principal-systems-architect — one chunk, they are inseparable)*
  — extend the depth-first import walk to register protocols and defn signatures,
  applying **each visited file's own leading `(ns …)`** during its prescan. Resolve
  the idempotence question in `resolution.md` §W1a *before* writing the walk; if
  `generic-register-method` is not idempotent, add a per-path prescanned guard —
  **do not weaken the duplicate-signature check**, which must keep rejecting
  genuine collisions.
  *Accept:* the **corrected** repro E (§3, mutual dependency) compiles in both
  orders; the diamond shape stays working; two-independent-higher-files and
  two-routes-to-one-file shapes work as `tests/` cases; genuine duplicates still
  error; **bootstrap byte-identical.**
* **W1c** *(systems-impl-engineer)* — the improved unresolved-name message,
  distinguishing "defined nowhere" from "defined in an unreachable file". Note the
  baseline moved under W4a: these messages now carry real lines, so W1c is about
  the *wording*, not the location.
* **W1d, W1e** *(orchestrator decisions, recorded in `resolution.md`)* — the
  mutual-import policy (option 1 recommended) — its blocking probe is done, see §3;
  and the triage of whether `declare`-as-forward-prototype is still needed at all.
  **W1e is probably resolved-by-obsolescence — do not build a forward-declaration
  mechanism without first confirming a real remaining use case.** W3c's fallout
  changed `declare`'s parameter parsing (see `cheader.md`'s addendum); re-read it
  before triaging W1e.

### W6 — Nullability flow typing · spec: [nullability.md](nullability.md)

*(systems-impl-engineer — design document only, dispatch any time)*

Expand `nullability.md` into the full design per its own checklist. **No `src/`
edits**, with one exception: its item 6 asks whether §3.4 (a `let` local bound to
`null`) is actually independent of flow typing. **Triage that first** — it may be a
small fix mislabeled as a hard problem, in which case land it under W5 and say so.

### Completed — for reference only

W4 (diagnostics), W2 (literal-operand lockstep) and W3 (C header interop) are
done. Their chunk-by-chunk accounts, premise corrections and test inventories are
in [progress.md](progress.md) and in each spec doc's "as built" addendum. Do not
re-dispatch them; do read them when a remaining item touches the same code, which
W5d and W1 both do.

---

## 5. Landmines (read before writing a line)

1. **The bootstrap fixed point is the primary safety net, and every item in this
   stage is supposed to keep it byte-identical.** The compiler's own source
   compiles today, so every fix here affects only programs that previously errored,
   crashed, or mis-emitted. **A non-empty bootstrap diff is a signal you changed
   behaviour you did not mean to — investigate it, do not
   `make update-bootstrap` past it.** Track record so far: every chunk held it on
   the first pass except the W3c `declare`-parameter fix, whose 6-line diff was
   audited against all 189 compiling `examples`/`lib`/`fixtures` programs *before*
   reconverging. Match that bar. W1a and W5d are the likeliest remaining items to
   move IR legitimately.
2. **Do not weaken the duplicate-signature check to make W1a's idempotence
   easier.** It is load-bearing: two different files defining the same name+arity
   must still error (§2.6). Silent last-wins would be a regression worse than the
   bug being fixed.
3. **`prescan-imported-types` does not currently apply per-file namespaces.** That
   is latent today because it registers struct *names* only. It stops being safe
   the moment signatures go through the same walk. W1b is part of W1a, not a
   follow-up.
4. **C-header imports must stay skipped in the prescan walk.** Reading one invokes
   clang. The existing walk already skips string-path imports; preserve that. W3a
   added a name-only `cheader-prescan-opaque` pass alongside it — W1a must not
   collapse the two.
5. **Build W1 against the corrected repro E (§3), not the one this document used
   to carry.** The original shape compiles under one ordering, so an implementation
   validated against it can pass while fixing nothing. The mutual-dependency shape
   is the one that admits no ordering.
6. **W6 is a document.** If an agent starts editing `src/` for flow typing, stop
   it. The cheap version of narrowing is unsound and worse than the status quo;
   `nullability.md` explains why.
7. **Do not narrow a test to make it pass.** Two of the findings exist because a
   test was *right* and a prediction was wrong. When a self-test and the compiler
   disagree, establish which is correct before changing either. W3c's fallout is
   the live example in this repo: three suite heredocs were relying on a `declare`
   defect, and the correct move was to fix the heredocs *after* establishing the
   compiler was wrong — not before.
8. **A `defmacro` body cannot call `die-at`/`report-at`** (found during W4d, in
   `progress.md`'s limitations list). If a W5 sub-item's cleanest fix looks like
   "make the macro raise a good error", it is not available; the fix has to live in
   the compiler, as W4d's `case-clause-hint` does.

---

## 6. Definition of done

* W1 and W5 implemented per their spec docs, or with each deferral **recorded in
  that spec doc** with the reason and what was done instead. W6 delivered as a
  design document. *(W2, W3, W4 — done.)*
* `make test` passes; `make bootstrap` is a **byte-identical fixed point**.
* New `tests/` cases with `tests/expected/` fixtures for: the corrected W1
  mutual-dependency shape, the diamond, and two-routes-to-one-file; all four W5f
  union spellings; and each landed W5 sub-item. *(The W2 operand matrix, the W3
  header program and the W4 no-`:0:` check are in and passing.)*
* `docs/` updated per each spec doc.
* `design/stage15-stress-test/progress.md` accurate — it now has a W5 section;
  keep it current as the remaining sub-items land. `design/overview.md`
  references this stage.
* **The external regression:** the Doom port at `/home/zak/code/nuc-doom-claude`
  rebuilds against the new compiler with its workarounds removed — specifically,
  the load-bearing import ordering in `src/g_game.nuc` and the
  `(as ui32 SOME_DEFCONST)` comparison casts — and both demo gates
  (`build/test_demo`, `build/test_demo_monsters`) still report bit-exact. This is
  the only test that proves the stage achieved its purpose. Run it; if the port
  needs source changes beyond *deleting* workarounds, that is a finding — record
  it. Note that repo has its own `prompt.md`/`PROGRESS.md` conventions and a
  "never revert work with git" rule; do not restructure it, only remove
  workarounds the compiler no longer requires.
  **The `(as ui32 …)` half is unblocked now** — W2a/W2b landed — so that half can
  be run before W1 rather than waiting for the whole stage.

## 7. Explicitly out of scope (do not build)

* **Replacing the hand-rolled C parser with libclang.** W3 met its bar without it
  (all three header-ladder rungs reached). If W3's "as built" account makes the
  long-term case clearer, record it in `design/stage3c.md` — do not act on it here.
* **Struct packing (§4.1) and fixed-size array struct fields (§4.2).** Both are
  real gaps and both are genuinely painful in the port — but both want a
  layout-attribute design that overlaps
  [stage14/attributes.md](../stage14/attributes.md)'s reserved-but-unimplemented
  `:align`/`:section` slots. Doing them piecemeal here would pre-empt that design.
  Note them in `design/stage15-stress-test/progress.md` as the top candidates for
  the next stage.
* **Nullability flow-typing implementation** (W6 is design only), nullability
  *inference* across function boundaries, and `?T` monad ergonomics.
* **Type reachability** (§2.7): a struct type named in a unit's signatures must
  still be defined in a reachable file. W1 removes the *order* constraint, not the
  reachability constraint. Improve the message (W1c); do not change the rule.
* Anything the findings report lists in its §7 "Things that worked well" —
  cross-file struct prescan, typed function pointers + `funcall`, arity
  overloading, `f32` bit-exactness, duplicate same-value `defconst`, `.set!` struct
  copies, compile speed. Those are the load-bearing behaviours this stage must not
  disturb.
