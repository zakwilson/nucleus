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

There are six work items of very different size. **Do them in the order in §4** —
that is not the order of importance, and the reasoning is in
[overview.md](overview.md) ("Ordering"). One item (W6) is a **design document
only**, not an implementation.

---

## 1. Required reading (do this first, do not skip)

1. **[overview.md](overview.md)** — this stage's scope, ranking and ordering.
2. **`/home/zak/code/nuc-doom-claude/NUCLEUS-FINDINGS.md`** — the findings report.
   Read §8 (the ranked summary) and §7 ("Things that worked well" — it tells you
   what *not* to break), then the sections for the item you are dispatching.
   Do **not** make subagents read the whole file; extract what each needs into its
   brief (see §2).
3. **`CLAUDE.md`** (repo root) — the workflow rules. Not optional.
4. **`context/local.md`** — the mandatory subagent-delegation workflow and the
   agent roster.
5. **`context/build.md`** — build flow and bootstrap artifacts.
6. **`context/conventions.md`** — required before any compiler edit, and directly
   relevant here: its **`node-type` mirrors `emit-node`** note *is* W2's bug class,
   and W2 adds the shared helper that prevents it recurring.
7. The spec doc for whichever item you are dispatching, plus:
   - W1 → `src/nucleusc.nuc` `emit-toplevel-forms` (~9246), `prescan-imported-types`
     (~8884), `prescan-defn-signatures` (~9020), `do-import` (~9606); `src/nuch.nuc:146-159`.
   - W2 → `src/generics.nuc` `node-type-call` (~3814), `node-type` (~3883);
     `src/nucleusc.nuc` `is-untyped-int-literal` (~1633), `binop-coerce` (~1782),
     `emit-binop-vals` (~1904-1953), `emit-int` (~1011).
   - W3 → `src/cheader.nuc` (esp. ~550-590); `design/stage3b-interop.md`,
     `design/stage3c.md`.
   - W4 → `lib/reader.nuc` `die-at`/`report-at` (35/54); `lib/macros.nuc`;
     `src/nucleusc.nuc` `emit-defconst` (~7459).
   - W5 → per sub-item, listed in `ergonomics.md`; W5c also needs
     `design/stage14/native-strings.md`.

---

## 2. How to work (process — enforced by CLAUDE.md and context/local.md)

**Delegate; do not implement in the orchestrating thread.** Plan the split, then
dispatch each chunk, each well under ~100K tokens. §4 names the chunks and the
agent for each. Agent selection per `context/local.md`:

* **principal-systems-architect** — *use sparingly*. Reserved for exactly two
  chunks in this stage: **W1a** (whole-graph resolution) and **W5f** (the union
  segfault, which is gnarly debugging with no obvious site). Do not spend it
  elsewhere.
* **systems-impl-engineer** — the compiler-internals chunks: W2a, W2b, W3a–c,
  W4a, W4c, W5d, and the W6 design document.
* **focused-task-implementer** — well-specified small work: W4b, W4d, W5a, W5b,
  W5c, W2d.
* **build-test-runner** — `make test` / `make bootstrap` runs and reporting.
* **api-docs-writer** — `docs/` updates and progress tracking (W4e's generated
  table is *not* this agent's job; it is code, dispatch it as such).
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
fourth onward — including two cases where the brief ordered a change to a test
that was already correct. Say so explicitly in each brief: *if a premise here is
wrong, say so directly; that is the most valuable thing you can return.*

**Keep it green at every step.** After each chunk: `make test` passes and
`make bootstrap` is a **byte-identical fixed point**. Read §5 on why that matters
more in this stage than usual.

**Closing steps are required, not optional:**
* `docs/` for every user-visible change (each spec doc lists its own).
* `design/stage15-stress-test/progress.md` — create it; record what landed, what
  deferred and why, and any new limitation discovered.
* Update each spec doc in place where it says to record a decision or a triage
  result (W1d, W1e, W2b, W2d, W3's header ladder, W5e, W6's §3.4 triage).
* Note this stage in `design/overview.md`'s document list.
* **Self-improving context:** fix root causes; add a `context/` note only for a
  genuinely unfixable environment gotcha.

---

## 3. Verify the ground before you build

Every repro in these docs was confirmed against `build/nucleusc` at the time of
writing. Re-confirm before building — and note that on this host the committed
`bin/nucleusc` may link a newer libLLVM than the container ships; if it fails to
exec (exit 126/127), rebuild from the committed IR with `make boot-binary` (or
`make ensure-boot`) first.

Confirm these five, which are load-bearing for the plan:

```lisp
; A — W2 §1.2: invalid IR
(defn main ():i32 (let (p:ptr (malloc (* 4096 (as i64 (sizeof i32))))) (return 0)))
;   expect: failed to parse generated IR … '%t4' defined with type 'i64' but expected 'i32'

; B — W2 §1.3: operand order changes the answer
(defvar cl:ui32 5)
(defn main ():i32 (let (t:ui32 9) (when (> t (* 2 cl)) (return 1))) (return 0))
;   expect: >: mixed signed/unsigned operands   (and: compiles if written (* cl 2))

; C — W4 §3.2: silent non-registration, line 0
(defconst K:i32 2)
(defn main ():i32 (return K))
;   expect: :0: error: undefined: K

; D — W5f §1.1: segfault
(defstruct Row (action (union acv:(fn void)())))
(defn main ():i32 (return 0))
;   expect: SIGSEGV, exit 139

; E — W1 §2.1: no import order works  (three files)
;   xf.nuc: (defn x-uses ():i32 (return (y-later)))
;   yf.nuc: (defn y-later ():i32 (return 7))
;   z.nuc:  (import xf) (import yf) (defn main ():i32 (return (x-uses)))
;   expect: xf.nuc:0: error: unknown: y-later   — in BOTH import orders
```

**One documented finding is known to be uncertain and must be checked before W1
is designed.** §2.4 reports mutual imports failing with `duplicate method
signature for overloaded '<name>'`, but `do-import` has an explicit
`import: circular import of '%s'` path. `resolution.md` §"Import emission already
dedups" explains the likely reason (bare `(import foo)` computes a *default*
prefix, so the already-loaded early-return does not fire and it takes the
aliasing path instead). Build a two-file mutual-import probe, find out which
error you actually get, and record it in `resolution.md` before deciding W1d.

If any of A–E no longer reproduces as documented, **stop and report** — the plan
was built on them.

---

## 4. What to build (in order)

### W4 — Diagnostics (do first) · spec: [diagnostics.md](diagnostics.md)

Four chunks. W4a is the substantial one; the rest are small and can run in
parallel with each other once W4a's approach is settled.

* **W4a** *(systems-impl-engineer)* — plumb real locations into the
  `unknown:`/`undefined:` name-resolution family. Prefer moving raises up to
  callers that have the node over threading lines into lookup helpers. Add the
  did-you-mean suggestion over the intrinsic table.
  *Accept:* none of the six line-0 cases in `diagnostics.md` reports `:0:`; a
  suite check greps error output for `:0:` and fails if present.
* **W4b** *(focused-task-implementer)* — `(defconst K:i32 2)` must not fail
  silently: implement the W4b decision (reject, recommended) and then sweep every
  sibling definer for the same "silently drops an unexpected annotation" bug.
  *Accept:* located diagnostic at the `defconst` line; sweep results recorded.
* **W4c** *(systems-impl-engineer)* — `unterminated list` reports the innermost
  unclosed form's line **and** the first column-0 line after it while depth is
  nonzero. Verify against a deliberately-broken 8-level file.
* **W4d + W4e** *(focused-task-implementer, then api-docs-writer)* — `case`
  clause-shape detection and the one-armed-`if` message; then the docs
  truthfulness pass, with `docs/stdlib.md`'s availability table **generated by a
  script wired into the suite**, plus the `case` and `addr-of` doc corrections.

### W2 — Literal-operand lockstep · spec: [literal-typing.md](literal-typing.md)

* **W2a** *(systems-impl-engineer)* — the core fix. Extract the type-level
  decision from `binop-coerce` into one `binop-result-type` helper; have both
  `node-type-call`'s intrinsic branch and emit call it. **The rule must live in
  exactly one function** — a copy is how this drifted.
  *Accept:* repros A and B compile; `(* 2 cl)` and `(* cl 2)` emit identical IR;
  the `{operand order} × {i32,i64,ui32,ui64} × {arith,cmp}` matrix passes.
* **W2b** *(systems-impl-engineer)* — make a `defconst` bound to an integer
  literal adapt like that literal. Coordinate with W4b's decision. If the
  provenance plumbing proves invasive, the acceptable outcome is a better
  diagnostic plus a deferral recorded in the spec doc — **not** a silent
  sign-reinterpret.
* **W2d** *(focused-task-implementer)* — float literals adapt to an `f32` target.
  Accept test: a `float`-typed DSP kernel matching C output bit-for-bit (the
  findings §3.6 confirm `f32` is already bit-exact with C `float`, so this is
  testable).

### W3 — C header interop · spec: [cheader.md](cheader.md)

Three chunks, W3a first (it is the smallest and unblocks the real test targets).

* **W3a** *(systems-impl-engineer)* — register opaque forward-declared struct
  types instead of skipping them (`src/cheader.nuc:558-560`). Usable as `ptr:T`;
  every other use gives a located diagnostic; a later full definition upgrades the
  entry in place.
* **W3b** *(systems-impl-engineer)* — the validity gate. Fix the `(void, ptr)`
  mis-parse, **and** make any unrepresentable declaration skip with a located
  warning rather than emitting invalid IR. Run the gate against `make lib-cheaders`
  output as a self-check.
* **W3c** *(systems-impl-engineer)* — `off_t`'s typedef chain must resolve to an
  integer type; a header-derived declaration conflicting with an explicit
  `declare` warns and the explicit one wins. Document the precedence rule.

Then climb the header ladder in `cheader.md` and **record how far you got**.

### W5 — Ergonomics and the union crash · spec: [ergonomics.md](ergonomics.md)

Six independent sub-items — **this is the item to fan out in parallel**, with two
exceptions noted below.

* **W5a, W5b, W5c** *(focused-task-implementer, parallel)* — `\x` escapes;
  `bit-not` as a macro over `(bit-xor x -1)`; `CStr`-typed `defvar`. W5c must read
  `design/stage14/native-strings.md` first (NS-3 flipped literals to `StrView`).
* **W5d** *(systems-impl-engineer)* — array-literal ergonomics: auto-`deref` for
  struct compound literals as elements, and element-type inference for
  array-of-pointer locals. **Do not regress the 1000-row `(array Struct …)` case** —
  it is how generated tables are built.
* **W5f** *(principal-systems-architect)* — the union/function-pointer segfault.
  `ergonomics.md` names the candidate sites and explicitly warns **not** to assume
  the obvious one. Outcome may be working code or a clean diagnostic; **no
  segfault under any of the four spellings listed.**
* **W5e** *(principal-systems-architect or systems-impl-engineer)* — `defn-` name
  isolation. **Sequence this AFTER W1**, or take the option-2 fallback for this
  stage: it touches the same global-key scheme W1 changes, and running both
  concurrently in separate subagents will conflict.

### W1 — Whole-unit signature resolution (do last) · spec: [resolution.md](resolution.md)

* **W1a + W1b** *(principal-systems-architect — one chunk, they are inseparable)*
  — extend the depth-first import walk to register protocols and defn signatures,
  applying **each visited file's own leading `(ns …)`** during its prescan. Resolve
  the idempotence question in `resolution.md` §W1a *before* writing the walk; if
  `generic-register-method` is not idempotent, add a per-path prescanned guard —
  **do not weaken the duplicate-signature check**, which must keep rejecting
  genuine collisions.
  *Accept:* repro E compiles in both orders; two-independent-higher-files and
  two-routes-to-one-file shapes work as `tests/` cases; genuine duplicates still
  error; **bootstrap byte-identical.**
* **W1c** *(systems-impl-engineer)* — the improved unresolved-name message,
  distinguishing "defined nowhere" from "defined in an unreachable file".
* **W1d, W1e** *(orchestrator decisions, recorded in `resolution.md`)* — the
  mutual-import policy (option 1 recommended) after the §3 probe; and the triage of
  whether `declare`-as-forward-prototype is still needed at all. **W1e is probably
  resolved-by-obsolescence — do not build a forward-declaration mechanism without
  first confirming a real remaining use case.**

### W6 — Nullability flow typing · spec: [nullability.md](nullability.md)

*(systems-impl-engineer — design document only, dispatch any time)*

Expand `nullability.md` into the full design per its own checklist. **No `src/`
edits**, with one exception: its item 6 asks whether §3.4 (a `let` local bound to
`null`) is actually independent of flow typing. **Triage that first** — it may be a
small fix mislabeled as a hard problem, in which case land it under W5 and say so.

---

## 5. Landmines (read before writing a line)

1. **The bootstrap fixed point is the primary safety net, and every item in this
   stage is supposed to keep it byte-identical.** The compiler's own source
   compiles today, so every fix here affects only programs that previously errored,
   crashed, or mis-emitted. **A non-empty bootstrap diff is a signal you changed
   behaviour you did not mean to — investigate it, do not
   `make update-bootstrap` past it.** W1a and W5d are the likeliest to move IR
   legitimately; if they do, confirm the diff is *exactly* the intended change.
2. **W2's whole point is that one rule lives in one place.** If you implement the
   type-level unification by copying `binop-coerce`'s logic into `node-type-call`,
   you have reproduced the original bug with extra steps.
3. **Do not weaken the duplicate-signature check to make W1a's idempotence
   easier.** It is load-bearing: two different files defining the same name+arity
   must still error (§2.6). Silent last-wins would be a regression worse than the
   bug being fixed.
4. **`prescan-imported-types` does not currently apply per-file namespaces.** That
   is latent today because it registers struct *names* only. It stops being safe
   the moment signatures go through the same walk. W1b is part of W1a, not a
   follow-up.
5. **C-header imports must stay skipped in the prescan walk.** Reading one invokes
   clang. The existing walk already skips string-path imports; preserve that.
6. **"Skip with a located warning" is a legitimate destination for W3**, not a
   cop-out. 95% of a header plus three named warnings beats
   `failed to parse generated IR`. Do not let an agent gold-plate W3 into a
   libclang rewrite — that is explicitly out of scope (§7).
7. **Nucleus consumes C functions and data structures, not C macros**
   (`design/overview.md`). Several `Mix_*` "functions" are preprocessor macros with
   no symbol. Header import will never surface those, correctly — do not chase it.
8. **W6 is a document.** If an agent starts editing `src/` for flow typing, stop
   it. The cheap version of narrowing is unsound and worse than the status quo;
   `nullability.md` explains why.
9. **Do not narrow a test to make it pass.** Two of the findings exist because a
   test was *right* and a prediction was wrong. When a self-test and the compiler
   disagree, establish which is correct before changing either.

---

## 6. Definition of done

* W1–W5 implemented per their spec docs, or with each deferral **recorded in that
  spec doc** with the reason and what was done instead. W6 delivered as a design
  document.
* `make test` passes; `make bootstrap` is a **byte-identical fixed point**.
* New `tests/` cases with `tests/expected/` fixtures for: the W2 operand matrix;
  the W1 two-independent-callees and two-routes shapes; all four W5f union
  spellings; each landed W5 sub-item; a W3 program calling a real function through
  an imported header; and the W4 no-`:0:` check.
* `docs/` updated per each spec doc. `docs/stdlib.md`'s availability table is
  generated, not curated.
* `design/stage15-stress-test/progress.md` created and accurate.
  `design/overview.md` references this stage.
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

## 7. Explicitly out of scope (do not build)

* **Replacing the hand-rolled C parser with libclang.** W3's bar is stated in
  `cheader.md`; a parser rewrite may be the right long-term answer but it is not
  this stage. Record the case for it in `design/stage3c.md` if the work makes it
  clearer.
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
