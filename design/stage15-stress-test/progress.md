# Stage 15 Progress — Stress Testing (Doom port findings)

Back to [../progress.md](../progress.md). Stage overview: [overview.md](overview.md).

**W4 and W2 are complete** (W2a/W2b/W2c/W2d all landed). **W3a is done**
(§1.6, opaque forward-declared C types); **W3b** (§1.5) and **W3c** (§1.4)
remain. **W1, W5, W6 are not started** — no code or docs exist for the
not-started items yet beyond their spec docs ([resolution.md](resolution.md),
[literal-typing.md](literal-typing.md), [cheader.md](cheader.md),
[ergonomics.md](ergonomics.md), [nullability.md](nullability.md)).

## W2 — `node-type` ↔ `emit` literal-operand lockstep

Spec: [literal-typing.md](literal-typing.md) (with a "W2a as built" addendum
carrying the premise corrections and the full test/doc inventory).

| Chunk | What landed | Status |
|---|---|---|
| **W2a** | `node-type` of a binary operator returned *operand 1's type alone* while emit unified both operands, so the static type and the emitted type disagreed and downstream consumers trusted the wrong one: `(malloc (* 4096 (as i64 (sizeof i32))))` emitted `i64` but typed `i32`, and the argument coercer stacked a bogus `sext i32 <i64 value>` on it; `(> t:ui32 (* 2 cl:ui32))` was rejected as mixed-sign while `(* cl 2)` compiled. The type rule now lives in exactly **one** function, `binop-result-type` (`src/nucleusc.nuc`, immediately above `binop-coerce`), called by `binop-coerce` for the type decision (it keeps only its value-level cast emission) and by `node-type-call` (`src/generics.nuc`) for the propagated type. A binop's result is now the *unified* operand type and is symmetric in operand order. Also fixed the float direction found alongside the two specced repros: an untyped **float** literal now adapts to an `f32` operand (`(* alpha:f32 2.0)` is `f32`, not `double`-then-mis-stored) via a new `node-is-float-literal`; it still adapts only to a *float* operand, never an integer one. Two typed operands of different signedness are **still** rejected — the unification never sign-reinterprets. 4 new checks (the type matrix as a run example, the operand-order IR equivalence, two mixed-sign rejections). | **Done** |
| **W2b** | `defconst` provenance (§3.1) — a named constant now types like the literal it stands for, in both operand orders and on both sides of the lockstep. Carrier: two new `Sym` fields (`const-lit`, `const-lit-i64`) set by `emit-defconst`/`emit-defenum` (and the REPL's `NODE-*` mirror) but deliberately **not** by `deferror` (an `Err` is `is-int-type`-true and must not unify with plain integers); the *value* rides along, not just a flag, so `emit-symbol-ref` can tag the Val `is-lit`/`lit-i64` exactly as `emit-int` does. The single rule stays single: `binop-result-type` gained a `scope` parameter and calls one new predicate `operand-is-int-literal`; the scope is threaded (through `binop-coerce` and `emit-binop-vals`, whose two callers both already had one) rather than shortcut to `g-globals`, because a **local binding shadows the constant** and a shadowed local is not a literal. Also fixed the silent-wrong-answer half: `emit-defconst` hardcoded `ty-i32` while `const-val` carried the full decimal string, so `(defconst BIG 5000000000)` printed `705032704`; constants are now typed at `emit-int`'s LW-4 width, shared as `int-literal-type` and called from all three former copies (`emit-int`, `emit-defconst`, `node-type`'s NODE-INT). Carrying the value arms the existing `coerce-int-val` range check, and a **second, pre-existing narrowing hole** found while fixing it — `defvar-init-ir` hands a decimal string straight to LLVM, which truncates `i32 5000000000` without complaint — is closed for the named *and* inline spellings. `defenum` members get the same treatment (they carry no distinct nominal type, so withholding it would recreate the wart one level over). 5 new checks. | **Done** |
| **W2c** | Doc-only: `defvar` initialized from a `defconst`/`defenum` already works (§3.8); the docs implied "init must be a literal" forbade it. Folded into W2b's doc pass — the `defvar` rows in `docs/toplevel.md`/`docs/builtins.md` now say the restriction is about *expressions* and that a named constant is the preferred spelling for a named bound. | **Done** |
| **W2d** | Float literals in **non-binop** coercion positions (§3.6). The finding was bigger than specced: `coerce-int-val` (`src/abi.nuc` — despite the name, THE implicit-coercion chokepoint for ptr/CStr/StrView/int alike) had **no float case at all**, and its callers disagree on what a null return means. Eight typed-slot positions raised a type error (`let`/`with`, `set!`, `.set!` field store, explicit *and implicit* `return`, struct-literal and array initializers — positional and designated); the ninth, `emit-call-with-args`, treats null as "leave the argument alone" and so **silently miscompiled**, emitting `call float @take(double 2.5)` for `(take 2.5)` and printing `0.000000`. A **third** bug surfaced in the position the brief recorded as already working: LLVM accepts a decimal constant for `float` only when it round-trips exactly, so `(defvar g:f32 1.5)` worked while `(defvar g:f32 3.14)` emitted `@g = global float 3.14` and died at IR-parse time — and a global initializer is a constant, so it cannot be repaired with an `fptrunc`. All fixed at the one chokepoint: `coerce-int-val` gains a float↔float branch (a float **literal** re-renders as a constant at the target width, no instruction; a value gets `fpext`/`fptrunc`), and `coerce-num-val` + `safe-coerce-val` delegate to it instead of carrying copies. New `Val.is-flit`/`lit-f64` (deliberately separate from `is-lit`, which already carries two meanings) plus three renderers — `float-literal-value`, `f32-const-ir`, `float-literal-ir-at`. **Decision: Option A** — a non-literal `f64`→`f32` narrows silently, because `coerce-int-val`'s integer branch five lines up already does exactly that (measured: `(let (b:i64 300000000000 a:i32 b) …)` prints `-647710720` today) and C converts implicitly at every one of these positions. Dispatch is deliberately stricter: `arg-adapts` admits a float *literal* into a narrower float parameter (strictly additive — tier 0 still claims an exact `f64` overload) but never a typed `f64` value. Also removed `-ffast-math` from the compiler's own link line: it set FTZ/DAZ process-wide, folding every denormal literal to zero. 5 new checks, incl. the spec's accept criterion — a float DSP kernel bit-exact with C at `-O0` and `-O2`. | **Done** |

### Test/bootstrap status after W2a/W2b/W2d

`make test` **245/245** (231 → 235 after W2a → 240 after W2b → 245 after W2d);
`make avr-test`, `make abi-test`, `make layout-test` also green. `make bootstrap` stage1 == stage2
byte-identical on the first pass, no `make update-bootstrap` reconverge — as the
spec required: the compiler's own source compiles today, so the fix may only
affect programs that previously errored or mis-emitted.

Two premise corrections worth carrying forward (detail in the spec's addendum):
the predicate is named **`node-is-int-literal`**, not `is-untyped-int-literal`;
and the §1.2/§3.6 repros **do not fail under `--emit-llvm`** (which writes
textual IR without parsing it) — reproducing them needs the compile-and-link
path. The `(as i64 (* 4 (+ lb 1)))` workaround in `name-edit-distance` is now
redundant but deliberately left in place, since the committed boot compiler
predates the fix.

W2b's own premise corrections: the spec's "constants that do not fit `i32` are
stored `i64` today" was **false** (they were stored `ty-i32` and wrapped), and
W4b's rejection of `(defconst K:i32 512)` does leave W2b unconstrained on the
annotated-constant question — confirmed against the compiler, not assumed. The
trap that cost the most time: the variadic operator macros wrap the tail, so
`(* v K)` expands to `(_* v (* K))` and a binop's **second** operand node is a
CELL, not the bare symbol — a predicate over binop operands must macroexpand it,
or the fix silently works in operand-1 position only.

## W3 — C header interop

Spec: [cheader.md](cheader.md) (with a "W3a as built" addendum carrying the
premise corrections, the representation/upgrade design, and the full test
inventory).

| Chunk | What landed | Status |
|---|---|---|
| **W3a** | §1.6 — a C header's `struct Foo;` / `typedef struct Foo Foo;` was **skipped entirely**, so the type never registered and a later `ptr:Foo` died `unknown type: Foo`: C's standard opaque-handle idiom, which made every SDL handle type and `FILE` unusable and forced the Doom port to hand-mirror them. Now registered layout-less (`StructDef.opaque`, cleared in `struct-set-fields` — the single chokepoint every field-populating path funnels through, so "acquires a layout" and "stops being opaque" cannot drift), legal behind a pointer everywhere including a `defn` signature, and refused by value at six sites (`sizeof`, `alloca`, both field-access paths, `defn` parameter + return, `defstruct` field) with the misuse's own line **and** the header:line the type was declared on, recovered from clang -E's linemarkers. A later definition upgrades the entry **in place** through one shared emitter, in all three orderings real headers use (`struct Tag;` then `struct Tag {…};`; then via `typedef struct Tag {…} Name;`, whose body parses anonymously and never registered the tag at all; and a `typedef struct Tag Name;` alias registered while the tag was opaque, linked by a new `StructDef.alias-of`). Two premises corrected: the fix is **not** "one branch" — `c-parse-type` had to be taught to keep returning `ptr` for an opaque tag (its by-value `struct Tag` lookup would otherwise have emitted `declare void @f(%Tag)` for an undefined type, manufacturing more of the §1.5 invalid-IR failure this stage exists to remove), and the spec's own §1.6 probe cannot pass from import-time registration at all, because `prescan-defn-signatures` resolves signatures **before** any import runs and `prescan-imported-types` skips C-string imports by design — so W3a adds a name-only `cheader-prescan-opaque` pass that registers exactly the names the real import will define (which also made a fully-defined `ptr:Mix_Chunk` usable in a signature, not just the opaque `ptr:Mix_Music`). `unknown type:` also gained a location: the prescan resolved a signature against the defn's **name** node (an interned NODE-SYM, line always 0) and `desugar-typed` stamped every desugared binding cell from the same kind of node — both now borrow the enclosing form's line, which gives a real line to every diagnostic raised off a defn parameter, `defvar`/`extern`/`declare` name, `defstruct` field or `let`/`with` binding name. Incidental: `MAX-STRUCTS` 256 → 1024 (measured: three mainstream umbrella headers in one unit need between 200 and 256 slots), and preprocessed header text is now cached by path — 5 clang invocations → 3 for a `hello.nuc` build, ~30% faster than before W3a — which surfaced that `emit-c-include` ended with `(free buf)`, correct with a per-call buffer but a use-after-free (presenting as a *hang*, only on the second import of the same header) once shared. 10 new checks. | **Done** |
| **W3b** | §1.5 — a conservative validity gate on every synthesized `declare` (`SDL2/SDL.h` still emits `declare void @_mm_clflush(void, ptr)`, invalid IR discovered only at the end of compilation). Not started. | Not started |
| **W3c** | §1.4 — `off_t`'s typedef chain resolving to `ptr`, and the declaration-precedence rule between a header-derived `declare` and an explicit one. Not started. | Not started |

### Test/bootstrap status after W3a

`make test` **255/255** (245 → 255). `make bootstrap` stage1 == stage2
byte-identical on the first pass, no `make update-bootstrap` reconverge.
Because W3 touches shared code, inertness was verified beyond the fixed point:
`make lib-cheaders`, `make lib-headers`, and the emitted LLVM IR of **every**
`lib/*.nuc` and `examples/*.nuc` are byte-identical against a compiler built
from the pre-change tree (`git archive HEAD` + the committed boot compiler).

### New limitations discovered during W3a (not fixed here)

* **`Uint8`/`Uint32`-typed struct fields degrade to `ptr`.** `Mix_Chunk.volume`
  (`Uint8`) types as `ptr`, so `(c volume)` fails `return type mismatch` while
  `(c allocated)` (`int`) works. This is §1.4's typedef-chain defect surfacing in
  a *field* rather than a return type — W3c's scope. It is why the SDL_mixer
  fixture reads `allocated`.
* **`--emit-llvm` exiting 0 is not evidence of valid IR** — it writes the
  textual module without parsing it. The spec's `SDL2/SDL.h` probe now exits 0
  under `--emit-llvm` (§1.6 fixed) and still fails under `-o` (§1.5 open).

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
