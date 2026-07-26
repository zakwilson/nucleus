# Stage 15 Progress — Stress Testing (Doom port findings)

Back to [../progress.md](../progress.md). Stage overview: [overview.md](overview.md).

Only **W4** has landed anything. **W1, W2, W3, W5, W6 are not started** — no
code or docs exist for them yet beyond their spec docs
([resolution.md](resolution.md), [literal-typing.md](literal-typing.md),
[cheader.md](cheader.md), [ergonomics.md](ergonomics.md),
[nullability.md](nullability.md)).

## W4 — Diagnostics: locations and silent failures

Spec: [diagnostics.md](diagnostics.md). All five chunks done, in order
(W4a→W4b→W4c→W4d→W4e). Full detail, including each chunk's own "as built"
addendum with premise corrections and negative controls, lives in
`diagnostics.md` itself; this is the summary.

| Chunk | What landed | Status |
|---|---|---|
| **W4a** | Every compiler diagnostic now names a real line — the `unknown:`/`undefined:` family, `let`/`with` initializers, retired special-form spellings, `defvar` initializers, `match` arm patterns, `addr-of`/`set!`/`goto`/`export` subjects. Root cause: interned symbol nodes carry line 0 (shared across every occurrence of a spelling), so diagnostics borrow the enclosing form's line via `node-line`, plus an ambient `g-form-line` for the one call site (`emit-symbol-ref`) reached with only the bare operand. Added a did-you-mean (Levenshtein over the name registries, length-gated) and a small hand-written correction table (`bit-not` → "no unary 'bit-not'; write (bit-xor x -1)"). New suite-wide guard: `run_no_line_zero` fails if any fixture's diagnostic contains `:0:`. | **Done** |
| **W4b** | `(defconst K:i32 2)` (and the same shape on every sibling definer) used to register silently under the literal key `"K:i32"`, then die `undefined: K` at line 0 on first use — the worst failure mode in the stage. Decision: **reject**, not accept-as-type (per the spec's own recommendation). `emit-defconst` now rejects a colon-annotated or colon-paren-fused name with `<definer>: takes no type annotation; write (<definer> Name ...)` at the definer's own line. Swept every sibling (`defenum`, `defstruct`, `defprotocol`, `defmacro`, `defunion`, `deferror`, plus the private `-` variants) via a shared `reject-colon-in-def-name` helper — all had the identical bug, always in the annotation half (arity checks were already correct everywhere). Worst individual case found: `defstruct` didn't fail silently *or* cleanly — it produced a misleading `illegal character ':' in generated symbol` at line 0. 9 new fixtures. | **Done** |
| **W4c** | `unterminated list` reported only the innermost unclosed form's *opening* line (the file's premise that it blamed the *outermost* form was itself wrong — corrected in the addendum), which doesn't localize a deeply-nested miscount. Now reports that line **plus** a `note:` naming the first line that opens a new form in column 0 while a form is still open, and how many forms are open there — closing the gap that previously forced the Doom port to use an external Python paren-depth counter. Also diagnosed the "extra `)` inside a `let` binding list" shape by cause (`let: 'NAME' is a body form, not a binding -- an extra ')' probably ended the binding list early`) rather than the misleading downstream `undefined: NAME`; the spec's proposed "odd element count" heuristic for this shape doesn't actually fire (the shape leaves an *even* count), so a different, cause-based check was built instead. 6 new fixtures. | **Done** |
| **W4d** | `case` given its documented-but-wrong nested-clause form died `value is not callable: no invoke method is defined for this type` (naming the mechanism, not the mistake). Fixed at `emit-invoke-with-callee` (the one chokepoint every non-callable call head reaches) with a `case-clause-hint` that recognizes a bare-integer or bound-`_` head and rewrites the message to name the real flat syntax — confirmed **not fixable inside the macro body itself**: a `defmacro` body cannot call `die-at`/`report-at` (only the compiler's own source imports them; the prelude every macro body — including `case` — auto-imports does not). One-armed `if` now says `if requires an else branch; use (when test then…) for a guard` instead of the generic `macro: wrong number of args`; the generic macro-arity messages now name the macro and both counts. 4 new fixtures. No `lib/macros.nuc` changes, so bootstrap was byte-identical on the first pass. | **Done** |
| **W4e** | Two independent sub-parts, both done. **(1) Generated stdlib table:** `docs/stdlib.md`'s "no import needed" availability claims were wrong in both directions (`close`/`dup`/`dup2`/`isspace`/`isdigit` claimed-but-unavailable; ~190 real names undocumented). Replaced the hand-curated table with `scripts/gen-stdlib-table.py`, which probes every candidate name (full transitive enumeration of the prelude's actual header chain — `stdio.h`+`stdlib.h`+`string.h`, not just `string.h` as the spec's ground truth assumed) against `build/nucleusc --emit-llvm`, wired into the suite as `run_stdlib_table` (fails only on a false claim — a name the committed doc claims that no longer probes as available — not on host-legitimate incompleteness, since availability is libc-dependent). **(2) Docs truthfulness:** `docs/special-forms.md`'s `case` table row described a nonexistent nested-clause `switch`/`unreachable` lowering; `lib/macros.nuc:91` is a flat-argument equality-dispatch macro expanding to `cond`. Fixed by *deleting* the row — `case`, like `if`/`when`/`unless`/`dotimes`/`->`, belongs in `docs/macros.md`'s Standard Macros table, which already had the correct entry. The `addr-of` row read as more restrictive than reality (omitted that passing it as a call argument is an allowed borrow, only `return`/longer-lived stores are rejected) — restated positively with the C out-parameter idiom as the worked example, verified by compiling and running a probe (`build/nucleusc`, output `a=41 b=99`) before writing it down. Swept the rest of `docs/special-forms.md` for the same class of error (concrete claims about generated code/accepted syntax) with two-line probes; found nothing else wrong. Also closed a documentation gap the brief's checklist flagged: `docs/toplevel.md`/`docs/errors.md` had the W4b "takes no type annotation" note on `defconst`/`defenum` but not on `defstruct`/`defunion`/`defprotocol`/`defmacro`/`deferror`, despite all seven sharing the identical fix — added the note to the remaining five (re-verified against `build/nucleusc` first, not copied from the design doc). | **Done** |

### Cumulative test/bootstrap status after W4

`make test` check count grew monotonically through the chunk: 211 after W4a →
220 after W4b (+9) → 226 after W4c (+6) → 230 after W4d (+4) → 231 after W4e
(+1, `run_stdlib_table`). Final: **231/231**. `make bootstrap`: stage1 ==
stage2 byte-identical throughout every chunk, no `make update-bootstrap`
reconverge required at any point — expected, since W4 is diagnostics-only
(message text and doc content, never accepted syntax or emitted IR for any
previously-valid program).

### New limitations discovered during W4 (not yet fixed; not this stage's scope to fix here)

* **A `defmacro` body has no access to `die-at`/`report-at`.** Only the
  compiler's own source (`src/nucleusc.nuc`) imports `lib/reader.nuc`; the
  prelude every ordinary program (and every macro body, including
  library-shipped ones like `case`) auto-imports does not. A future
  compile-time-diagnostic facility for macro authors (e.g. exposing
  `report-at` through the prelude, or a dedicated `(macro-error line msg)`
  builtin) would be new scope, not a W4 fix. Found during W4d.
* **`context/build.md`'s parallel-test-suite timing figure (`~8.5s`) is
  stale** — measured baseline is now `~18.8s` (16-core host), predating the
  AVR/RISC-V gates and the W4a–W4d fixture batches. Found during W4e's
  generated-table sub-part; left uncorrected there and here, since it's
  session-continuity material outside this stage's `docs/`-truthfulness scope
  — flagged for whoever next audits `context/build.md`.
* **The literal-left binop mistyping** (`(_+ 1 x)`-shaped code mistypes to the
  literal's default `i32` instead of adapting to the non-literal operand's
  type) is live and was re-confirmed during W4a's incidental-finds pass. This
  is W2's item ([literal-typing.md](literal-typing.md)), not W4's — noted here
  only because W4a's sweep happened to re-trip it.

### Deferred / not applicable within W4

Nothing in W4's own scope was deferred — all five chunks (W4a–W4e) reached
**Done**. The stage's other five items (W1, W2, W3, W5, W6) are simply not
started; see [overview.md](overview.md) for the planned ordering
(W4→W2→W3→W5→W1, W6 design-only) and rationale.
