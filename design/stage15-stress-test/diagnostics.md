# W4 — Diagnostics: locations and silent failures

**Findings:** §5.1 (line-0 reporting for a whole class of errors), §5.2
(`unterminated list` points at the form's start), §5.3 (errors name the macro,
not the mistake), §3.2 (`defconst` with a type annotation registers nothing,
silently), §6.1 (`case`'s documented syntax is not its real syntax), §6.2
(`docs/stdlib.md` coverage claims unreliable).

**Goal:** every error names a real location, and no wrong-but-plausible spelling
fails silently. **Do this item first** — it makes W1, W2 and W3 materially easier
to debug, and it is the highest ratio of user-visible improvement to
implementation risk in the stage.

---

## Ground truth

`lib/reader.nuc:35` `die-at` and `:54` `report-at` both take an `i32 line`. The
line-0 errors are not a formatting bug — they are call sites that genuinely do not
have a line number to pass, because the failure is detected during a *registration*
or *inference* phase that has lost the node.

Four line-0 cases are confirmed live (see §Verified repros):

| Spelling | Error | Finding |
|---|---|---|
| `(defconst K:i32 2)` then use `K` | `:0: error: undefined: K` | §3.2 |
| `(bit-not 3)` | `:0: error: unknown: bit-not` | §4.3 |
| sibling forward reference | `:0: error: unknown: y-later` | §2.1 |
| `let` local bound to `null`, later field write | `:0: … raw pointer where non-null (ref …) is required` | §3.4 |

Also line-0 per the findings: same-file `defvar` forward reference (§3.5) and
`(defvar- g:CStr null)` (§3.7).

The pattern: **the reference site has a line, but the diagnostic is raised from a
context that only has a name.** Fixing this is mostly plumbing a line (or the
`Node`) through to where the failure is detected — not redesigning anything.

---

## Design

### W4a — plumb locations into name-resolution failures

**Status: Done.** All seven confirmed line-0 cases now report the line of the
reference; `make test` (211 checks) and `make bootstrap` (stage1 == stage2,
byte-identical, no reconverge) are green. Implementation notes, including one
correction to this document's stated ground truth, are in
[§W4a as built](#w4a-as-built) below.

The `unknown: <name>` / `undefined: <name>` family is the biggest win. These are
raised when a symbol lookup fails; the *caller* knows the node.

Approach: find every `die-at 0` / `die-at (… 0)` and every `unknown:` /
`undefined:` raise, and thread the referencing node's line. Where the raise
happens inside a lookup helper with no node available, either pass the line in or
move the raise up to the caller. Prefer moving the raise up — a lookup that
returns "not found" and lets the caller report is more reusable than one that
dies.

Expected outcome for the table above: every entry reports the **line of the
reference**, and where the compiler can say more, it does:

* `bit-not` → `unknown: bit-not` at the call line. Bonus, cheap and worth it:
  suggest the real spelling. There is no unary bitwise-not (§4.3, W5) — so the
  message should say `no unary 'bit-not'; write (bit-xor x -1)`. A
  "did-you-mean" over the intrinsic table catches a whole class of these.
* Sibling forward reference → after W1 this becomes impossible; until W1 lands it
  should at least report the referencing line. Coordinate: W1c specifies the
  final message.

### W4b — `defconst` with a type annotation must not fail silently

`(defconst K:i32 2)` produces **no diagnostic at the definition**; the constant
never registers and every use dies `undefined: K` at line 0. That is the worst
failure mode in the stage: a plausible spelling, no error where the mistake is,
and a location-free error where it is not.

Decide and implement one of:

* **Reject it** — `defconst: takes no type annotation; write (defconst K 2)`,
  reported at the `defconst` line. Minimal, unambiguous, matches today's
  semantics. **Recommended.**
* **Accept it** — treat the annotation as the constant's type. More convenient,
  but it interacts with W2b (a `defconst` should behave like the literal it stands
  for, and an explicitly-typed one then must *not* adapt). If you accept, W2b must
  be coordinated, and the docs must be explicit about the difference.

Either way, `emit-defconst` (`src/nucleusc.nuc:7459`) is the site, and the test is
that the annotated form produces a located error or works — never silence.

Then sweep for siblings: **any definer that parses a name and silently drops an
unexpected annotation or arity has the same bug.** `defenum`, `defvar`,
`defstruct`, `defprotocol`, `defmacro` — check each. A definer that fails to
register should always say so at its own line.

### W4c — `unterminated list` should point at the imbalance

`lib/reader.nuc` reports where the unterminated form *starts*, which is nearly
useless past a few lines — the Doom port routinely nests 6–10
`let`/`if`/`when`/`dotimes` levels and its standard remedy is an **external
20-line Python paren-depth counter**. That a hand-rolled script outside the
toolchain is the best available tool is itself the finding.

Implement the counter's heuristic in the reader: while scanning, remember the line
of each still-open form, and on EOF report the innermost unclosed form's opening
line **and** the first line at or after it that begins a new form at column 0
while depth is still nonzero. That second number is what actually localizes the
mistake.

Related shape worth a dedicated diagnostic: an extra `)` inside a multi-binding
`let` closes the binding list early, silently turning the next binding into a body
statement, and surfaces as `unexpected )` at the *next top-level form*. If the
reader can notice "a `let` binding list ended at an odd element count", say so.

### W4d — errors that name the macro instead of the mistake

* **`case`** (§6.1, §5.3). `docs/special-forms.md` describes a nested-clause
  integer switch; the symbol actually resolves to `lib/macros.nuc`'s flat
  `(case scrutinee v1 r1 v2 r2 … default)` macro. The documented form **compiles
  and misparses**, then dies `value is not callable: no invoke method is defined
  for this type` — because `(0 body)` is parsed as calling the integer `0`.
  - Fix the **docs** (they describe a form that does not exist). `examples/case.nuc`
    is authoritative.
  - Fix the **error**: `case` should detect a clause-shaped argument (a list whose
    head is an integer or `_`) and say `case takes flat value/result pairs, not
    clauses: (case x 1 "one" 2 "two" "other")`. Detecting the wrong shape in the
    macro is cheap and turns a baffling error into a corrective one.
* **One-armed `if`** (§4.5). `(if test then)` dies `macro: wrong number of args`,
  which names the mechanism rather than the fix. Should be
  `if requires an else branch; use (when test then…) for a guard`.

These are small but they are exactly the errors a newcomer hits, and each one
currently costs a doc-reading detour.

### W4e — documentation truthfulness sweep

§6.2: `docs/stdlib.md`'s "no import needed" claims are wrong in both directions.
`close` is listed as pre-declared but dies `unknown: close`. Conversely `getenv`,
`remove`, `fopen`/`fwrite`/`fclose`, `snprintf`, `strncmp`, `strstr`, `memcmp` all
resolve and are not documented as such. `strcasecmp` is not pre-declared (it is in
`<strings.h>`), which is correct but undocumented.

**Generate this table rather than curating it.** A script that probes each claimed
name with a two-line program and regenerates the doc table is the only version of
this that stays true. Wire it into the test suite so the docs cannot drift again.

Also fix §6.3 while in the docs: `docs/special-forms.md` describes `addr-of` of
frame-local storage as escape-tracked in a way that reads as more restrictive than
it is. Passing `(addr-of local)` as a call argument **is** allowed — downward flow
is a borrow; only `return` and stores into longer-lived memory are rejected. State
that positively, with the C out-parameter transcription as the example, because the
port initially assumed it was disallowed and nearly invented a return struct
instead.

---

## Verified repros (as of this doc)

```
$ printf '(defconst K:i32 2)\n(defn main ():i32 (return K))\n' > t.nuc
$ build/nucleusc -I lib t.nuc -o t
t.nuc:0: error: undefined: K

$ printf '(defn main ():i32 (return (bit-not 3)))\n' > t.nuc
t.nuc:0: error: unknown: bit-not
```

Plus the three-file sibling repro in [resolution.md](resolution.md), which also
reports at line 0.

---

## Accept criteria

* **No compiler error reports line 0** for any of the six cases listed in Ground
  truth. Add a test that greps the suite's own error output for `:0:` and fails if
  it appears — that is what stops the class from regrowing.
* `(defconst K:i32 2)` produces a located diagnostic at its own line (or works,
  per the W4b decision). The sibling-definer sweep is done and its results
  recorded here.
* `unterminated list` reports the innermost unclosed form's line **and** the first
  suspicious column-0 line after it. Verify against a deliberately-broken file
  with 8 nesting levels.
* `case` given the documented-but-wrong clause form says what the right form is.
  One-armed `if` suggests `when`.
* `docs/stdlib.md`'s availability table is **generated** by a script run in the
  suite. `docs/special-forms.md`'s `case` entry matches `lib/macros.nuc`, and its
  `addr-of` entry states the borrow rule positively.
* `make test` green; `make bootstrap` byte-identical. Diagnostics-only changes must
  not move IR — if the bootstrap diffs, something other than a message changed.

---

## W4a as built

### Correction to "Ground truth"

This document's framing — "the failure is detected during a *registration* or
*inference* phase that has lost the node" — is not the mechanism. The mechanism
is narrower and mostly mechanical:

**`lib/reader.nuc` `read-form` interns symbol nodes.** `(when (= (t kind)
TOK-SYMBOL) (return (ok (intern-symbol (t s)))))` — every occurrence of a
spelling anywhere in the program is the *same* `Node`, and `intern-symbol`
sets its `line` to 0. Every other node kind (`NODE-INT`, `NODE-STR`,
`NODE-CHAR`, `NODE-FLOAT`, `NODE-KEYWORD`, and cells via `make-cell`) carries
its reader line. So `:0:` appeared wherever a diagnostic's subject was, or
could be, a bare symbol — which includes plenty of sites in ordinary emit
code, not just registration/inference phases.

The corollary is a constraint on the fix: **a line must never be written into a
symbol node**, because the write is observed by every other occurrence of that
spelling. The compiler was in fact already doing this — `stamp-macro-lines`
(`src/nucleusc.nuc`) recursed into symbol children and stamped their line-0
slots with the macro call site's line, so after the first macro expansion
mentioning `x`, every diagnostic anywhere about any `x` reported that call
site's line. Fixed here: `stamp-macro-lines` now skips `NODE-SYM` outright
(symbols have no children, so no traversal is lost).

Interning cannot be removed: symbol identity is compared by pointer throughout
the compiler (`(= n 'null)`, `(= head 'label)`, special-form dispatch), so
per-occurrence symbol nodes would break resolution wholesale.

### Mechanism chosen

Two, split by whether the raising code has a node in hand:

1. **Borrow the enclosing form's line (the large majority — ~110 raise sites
   across `nucleusc.nuc`, `generics.nuc`, `union-emit.nuc`,
   `union-registry.nuc`).** `node-line` (`lib/node.nuc`) returns a node's own
   line when it has one and a supplied fallback otherwise, and every fixed site
   passes the enclosing form node's line, which its emitter already holds
   (`cc` / `ff` / `nn` / `clause`). No signature changes; the borrowed line is
   visible at the raise.

2. **An ambient enclosing line, for `emit-symbol-ref` only.** `emit-symbol-ref`
   is reached from `emit-node` with *only* the operand, and `emit-node` has 98
   call sites, so an explicit parameter would have to be threaded through all
   of them. Instead `g-form-line` (beside `g-mono-context`) is maintained with
   strict save/restore in `emit-node` — the single dispatcher every operand
   passes through — and `emit-symbol-ref` takes an explicit `line:i32`
   parameter that `emit-node` fills from it (`emit-dispatch`, the other caller,
   passes the call cell's line directly). Rationale for not threading: the
   information is genuinely dynamically scoped; `die-at` already reads two
   ambient globals for the *other* two components of a location
   (`g-source-path`, `g-mono-context`); and threading gives each of 98 sites an
   opportunity to silently pass a wrong or zero line, whereas one dispatcher
   invariant cannot be forgotten by a future emitter.

`lib/reader.nuc` `read-program` additionally seeds each top-level spine cell
with the line of the form's *first token*, so a stray bare symbol at top level
("top-level form must be a list starting with a symbol") has a location too.

### Did-you-mean

`closest-known-name` (`src/nucleusc.nuc`) scans the same four registries
`name-existing-kind` consults — generics/methods, macros, struct and union type
names, and global values — for the nearest spelling by Levenshtein distance.
The allowance scales with length (`name-suggest-limit`): under 4 characters no
suggestion at all, 4–6 one edit, 7+ two. Without the length gate a name like
`K` "matches" the binop `%` at distance 1, which is worse than silence.

`known-name-correction` is the deliberately small special-case table for
spellings that are *wrong mental models* rather than typos, where the right
answer is a rewrite: `bit-not` / `bitnot` / `lognot` →
`no unary 'bit-not'; write (bit-xor x -1)`. Consulted before the general
search. When W5b lands a real `bit-not` macro the entry becomes dead and can be
dropped; the general did-you-mean is unaffected.

### Result

| Case | Before | After |
|---|---|---|
| §3.2 `(defconst K:i32 2)` then use `K` | `:0: undefined: K` | `t.nuc:2: undefined: K` |
| §4.3 `(bit-not 3)` | `:0: unknown: bit-not` | `t.nuc:1: no unary 'bit-not'; write (bit-xor x -1)` |
| §2.1 sibling forward reference | `xf.nuc:0: unknown: y-later` | `xf.nuc:1: unknown: y-later` |
| §3.4 `let` local bound to `null` | `:0: … raw pointer where non-null …` | `t.nuc:3: … raw pointer where non-null …` |
| §3.5 same-file `defvar` forward ref | `:0: undefined: gv` | `t.nuc:1: undefined: gv` |
| §3.7 `(defvar- g:CStr null)` | `:0: defvar: null requires ptr type` | `t.nuc:1: defvar: null requires ptr type` |
| bare `cast` in head position | `:0: 'cast' was split in Stage 14 …` | `t.nuc:3: 'cast' was split in Stage 14 …` |

§2.1 still fails to compile — that is W1's item; W4a's contract for it was the
location only.

### Regression protection

* `run_no_line_zero` (`tests/run-tests.sh`) compiles every
  `tests/fixtures/*.nuc` and fails if any diagnostic carries `:0:`. This is the
  check that stops the class from regrowing.
* `run_reject` now fails any existing or future rejection test whose stderr
  carries `:0:`, so the guarantee rides along with every message assertion.
* `run_reject_at` pins both the message **and** the `<path>:<line>: error:`
  prefix; five W4a fixtures use it.
* `run_w4a_sibling_forward` covers the three-file §2.1 case, asserting only
  "no `:0:`", so it keeps passing once W1 removes the error.

Both guards were verified against a negative control: reintroducing the
`emit-symbol-ref` line-0 bug makes `run_no_line_zero` and the pinned fixture
fail with the expected output, and restoring it makes them pass.

The three Ground-truth cases whose *continued rejection* is another item's call
(§3.2 belongs to W4b, §3.5 to W1, §3.7 to W5) have fixtures but no pinned
message — they are covered by the sweep, so W4b/W1/W5 can change the behavior
without touching a W4a test.

### Incidental finds (not W4a bugs)

* **`boot/nucleusc.ll` was un-buildable.** The `04c55ec Merge stage14` merge
  duplicated the `@emit-keyword` definition in the committed bootstrap IR (both
  merge sides' copies were kept; the second referenced `@.str.775` — `"_get"`,
  5 bytes — through a `[15 x i8]` GEP left over from the other side's string
  pool). `clang` rejects the module, so `make boot-binary` — and therefore any
  fresh checkout — failed with `invalid redefinition of function
  'emit-keyword'`; existing checkouts only worked because they still had a
  locally built, `.gitignore`d `bin/nucleusc` from before the merge. Repaired
  by deleting the stale duplicate. A whole-file audit (every `@.str.N`
  reference's array length against its definition) found exactly one
  inconsistency — that block — so the merge damage was limited to it.
* **The literal-left binop mistyping (progress.md "Known constraints") is
  live.** `(* 4 (as i64 (+ lb 1)))` in new code emitted `sext i32 <i64 value>`
  and was rejected by clang; worked around locally with
  `(as i64 (* 4 (+ lb 1)))` and commented at the site. W2's item.

## W4b as built

**Status: Done.** Decision: **reject** (the spec's recommended option, per
[Coordination note](#w4b--defconst-with-a-type-annotation-must-not-fail-silently)
with W2b). `make test` (220 checks — the 211 from W4a plus 9 new W4b
fixtures) and `make bootstrap` (stage1 == stage2, byte-identical, no
reconverge) are green.

### Confirmation of the brief's ground truth

The mechanism this document's task brief described was confirmed exactly, not
corrected: `defconst` is not in `desugar`'s list of binding positions (only
`defn`/`defvar`/`extern`/`declare` names, `defstruct` fields, and `let`/`with`
binding names are desugared — context/conventions.md), so `K:i32` in
`(defconst K:i32 2)` arrives at `emit-defconst` as one undesugared `NODE-SYM`
whose spelling is literally `"K:i32"`. It passed the old
`(!= (name kind) NODE-SYM)` check unchanged and `scope-define g-globals (name
s) …` registered the constant under the key `"K:i32"` — a key no later
reference to `K` could ever match. (The one drift from the brief: `emit-
defconst` is at `src/nucleusc.nuc:7624` as of this task, not the `:7459` the
document's Design section cites — line numbers had simply moved since that
section was written; the mechanism is identical.)

### Fix

`emit-defconst` now checks, before its existing `(!= (name kind) NODE-SYM)`
guard:

1. **A bare symbol whose spelling contains `:`** (`split-typed` on `(name s)`;
   a non-null `out-type-name` means an annotation was present) — reject with
   `defconst: takes no type annotation; write (defconst <name> <value>)`,
   substituting the parsed base name and the literal integer value so the
   message for `(defconst K:i32 2)` reads exactly `defconst: takes no type
   annotation; write (defconst K 2)`, per the brief.
2. **The colon-paren-fused `CELL` shape** — `K:(i32)` lexes as the atom `"K:"`
   immediately followed by `"(i32)"`, and `fuse-colon-paren` (lib/reader.nuc)
   fuses them into `(K (i32))` before `emit-defconst` ever sees it. Detected
   by checking `(name kind) = NODE-CELL` with a `NODE-SYM` car, so it gets the
   identical message instead of falling through to the generic, misleading
   `defconst: name must be symbol`.

Both checks die at `(cc line)` (the whole `(defconst …)` form's own line, not
the name node's — a bare symbol's own `line` is always 0, per the W4a
correction above) via ordinary `die-at`, matching every other `emit-defconst`
diagnostic.

### The sibling sweep

The brief's hypothesis — "any definer that parses a name and silently drops
an unexpected annotation or arity has the same bug" — held for **every**
sibling checked, always in the *annotation* half, never the *arity* half
(every definer's arity/shape checks were already correct, located, and
clear). A shared helper, `reject-colon-in-def-name` (`src/nucleusc.nuc`,
beside `split-typed`), covers the "bare symbol with an embedded `:`" shape
uniformly: called first, before any other dispatch on the name (including a
definer's own `CELL`/template-head check), it is a no-op for a `CELL` name or
a colon-free symbol, so it never disturbs a legitimate parametric head
(`(defstruct (Vector T) …)`, `(defprotocol (Seq E) …)`, `(defunion (Wrap T)
…)`). The colon-paren-fused `CELL` shape needed a bespoke check per definer,
because three of them (`defstruct`/`defprotocol`/`defunion`) have a
*legitimate* `CELL` name (a parametric template head) that the fix must not
misfire on — distinguished by checking for exactly one extra "parameter" that
is itself a nested `CELL` (impossible in genuine template syntax, where tyvar
names are always bare symbols).

| Definer | Probe | Before | After | Category |
|---|---|---|---|---|
| `defconst` | `(defconst K:i32 2)` | silently registers under key `"K:i32"`; use dies `undefined: K` | `defconst: takes no type annotation; write (defconst K 2)` at the `defconst` line | silent |
| `defconst` | `(defconst K:(i32) 2)` | `defconst: name must be symbol` (located, but misleading) | same annotation message | confusing but located |
| `defenum` | `(defenum E:i32 A B C)` (flat, well-formed members) | silently compiles: members A/B/C register fine, but the `EnumDef` itself never registers (its own `(= (en kind) NODE-SYM)` guard fails) — invisible unless `E`'s type identity is later consulted (e.g. `tyname-resolvable` in a generic receiver) | `defenum: takes no type annotation; write (defenum E ...)` at the `defenum` line | silent |
| `defenum` | `(defenum E:i32 (A 1))` (the brief's exact probe — a *malformed member* shape) | `defenum: value must be symbol` (located, but blames the wrong element — the member, not the annotated name) | same annotation message (now caught before the member loop even runs) | confusing but located |
| `defenum` | `(defenum E:(i32) A B C)` | same silent `EnumDef`-registration drop as above | same annotation message | silent |
| `defstruct` | `(defstruct S:i32 (f i32))` | registers a `StructDef` under `"S:i32"`, then dies downstream at `check-ir-name-legal`: `illegal character ':' in generated symbol for 'S:i32'` reported at **line 0** (`S:i32` is an interned `NODE-SYM`) | `defstruct: takes no type annotation; write (defstruct S ...)` at the `defstruct` line | **worst case found — silent-ish (wrong diagnostic entirely) + line 0** |
| `defstruct` | `(defstruct S:(i32) (f i32))` | `defstruct: type parameter must be a symbol` (located; blames "type parameter" — reads as a template-arity complaint, not a name-annotation mistake) | same annotation message | confusing but located |
| `defstruct` | `(defstruct (Box T) (v T))` (genuine template) | compiles fine | unchanged (helper is a no-op on a real template head) | — regression check |
| `defprotocol` | `(defprotocol P:i32 (bar …))` + later `(extend Foo P)` | compiles with **no diagnostic at all** at the definition; `extend` fails downstream with the unrelated `extend: unknown protocol 'P'` | `defprotocol: takes no type annotation; write (defprotocol P ...)` at the `defprotocol` line | silent |
| `defprotocol` | `(defprotocol P:(i32) (bar …))` | `defprotocol: protocol parameter must be a symbol` (located, but reads as an arity complaint) | same annotation message | confusing but located |
| `defprotocol` | `(defprotocol (Seq E) (get …))` (genuine parametric protocol) | compiles fine | unchanged | — regression check |
| `defmacro` | `(defmacro m:i32 (x) x)` + call `(m 1)` | compiles with **no diagnostic at all** at the definition; the call site fails with the unrelated `unknown: m` | `defmacro: takes no type annotation; write (defmacro m ...)` at the `defmacro` line | silent |
| `defunion` | `(defunion U:i32 (A x:i32) B)` | registers a `UnionDef` under `"U:i32"`, silently unlookupable | `defunion: takes no type annotation; write (defunion U ...)` at the `defunion` line | silent |
| `defunion` | `(defunion U:(i32) (A x:i32) B)` | `defunion: type parameter must be a symbol` (located, reads as arity) | same annotation message | confusing but located |
| `defunion` | `(defunion (Wrap T) (some v:T) none)` (genuine template) | compiles fine | unchanged | — regression check |
| `deferror` | `(deferror MyErr:i32 "bad")` + `(err! MyErr)` | compiles with **no diagnostic at all** at the definition; the use fails with the unrelated `undefined: MyErr` | `deferror: takes no type annotation; write (deferror MyErr "message")` at the `deferror` line | silent |
| `defvar` | `(defvar x:i32:i32 3)` (double annotation) | `defvar: missing :type on 'x'` (correct — `defvar` legitimately takes ONE annotation, and a multi-colon chain that doesn't resolve to a real type is rightly rejected) | unchanged | — not a bug (defvar's annotation is legitimate) |
| `defvar` | `(defvar x:i32 3 4)` (extra arg) | `defvar: expects name and optional init` at the `defvar` line | unchanged | already correct |
| `defvar` | `(defvar x 3)` (no annotation — `defvar` is the one definer where an annotation is *required*, so its "plausible mistake" is *omitting* one) | `defvar: missing :type on 'x'` reported at **line 0** — correct message, wrong location (`name-node` is a bare `NODE-SYM`, and `emit-defvar` read `(name-node line)` directly instead of borrowing the enclosing form's line) | same message at the correct line (`node-line` fix) | **found via the sweep, not silent — a stray line-0 regression, same class as W4a** |
| `defenum`/`defprotocol`/`defunion`/`defmacro`/`deferror` arity mistakes (missing members/sigs/arms/body/message; extra args) | one probe each | all already correctly located with clear messages | unchanged | already correct |
| `defconst-` (private variant) | `(defconst- K:i32 2)` | shares `emit-defconst` — same silent bug | same fix (shared code path) | silent, fixed for free |

### A premise this task's brief did not anticipate

The brief's own worked example for `defenum` — `(defenum E:i32 (A 1))` — uses
a **malformed member** (`(A 1)`, not the correct flat `A`), so its "located
but misleading" finding is real but incomplete: it only reproduces because
the member loop's own type check happens to fire first. With
**well-formed** members (`(defenum E:i32 A B C)`), there was no error
at all — the enum's own identity (`EnumDef.name`) simply vanished from
`g-enumdefs` while `A`/`B`/`C` kept working as plain values, which is a
strictly worse (fully silent) failure than the one the brief documented. The
fix (checking the enum's own name up front, before the member loop) closes
both shapes at once.

The `defstruct` case is the most severe finding in the whole sweep: unlike
every other silently-misregistering sibling, `S:i32` does not fail silently
*or* cleanly — it produces an actively misleading diagnostic
(`illegal character ':' in generated symbol`, which reads like an internal
compiler assertion, not a source mistake) at line 0, the exact defect class
W4a exists to eliminate. It survived W4a's own sweep only because W4a's
scope was the six confirmed Ground-truth cases, and a colon-annotated
`defstruct` name was not among them — it took W4b's definer-by-definer
sweep to surface it.

### Regression protection

Nine new fixtures (`tests/fixtures/w4b-*.nuc`, plus tightening the existing
`w4a-defconst-annotated.nuc`), all wired with `run_reject_at` (pins both the
message and the `<path>:<line>: error:` prefix — see W4a's Regression
protection section above for why `:0:` is checked automatically along the
way): `w4a-defconst-annotated`, `w4b-defconst-paren`,
`w4b-defenum-annotated`, `w4b-defstruct-annotated`,
`w4b-defprotocol-annotated`, `w4b-defmacro-annotated`,
`w4b-defunion-annotated`, `w4b-deferror-annotated`,
`w4b-defvar-missing-type`. Each fixture's header comment records the
before/after so the sweep table above and the test suite cannot drift apart.
No fixture was added for the three "genuine template head" regression checks
(`(Box T)` / `(Seq E)` / `(Wrap T)`) since those are covered by the existing
parametric-structs/protocols/unions test coverage; they were verified
manually (`./build/nucleusc`) to still compile before this change landed.

## W4c as built

**Status: Done.** `make test` (226 checks — the 220 from W4a+W4b plus 6 new W4c
fixtures) and `make bootstrap` (stage1 == stage2, byte-identical, no
`make update-bootstrap` reconverge) are green.

### Correction to this section's premise

This section says the reader "reports where the unterminated form *starts*,
which is nearly useless past a few lines". The first half is right and the
second half overstates it: **the reader already reports the *innermost*
unclosed form's opening line**, not the outermost. Measured against the
pre-change compiler on an 8-level `let` nest (`(defn main …)` on line 1,
`(let (v0 …)` … `(let (v7 …)` on lines 2–9, body on line 10, then N closers,
then a second top-level `(defn other …)`):

| closers supplied | innermost still-open form | reported |
|---|---|---|
| 1 of 8 | the `let` on line 8 | `t.nuc:8: error: unterminated list` |
| 7 of 8 | the `let` on line 2 | `t.nuc:2: error: unterminated list` |

The mechanism: `read-list` is recursive, so at EOF the *deepest* invocation
reports first and every enclosing one just propagates its `(err! parse-error)`
through `try` without reporting again. So the first number was never the
problem — **the missing half was always the second number**, which is what this
phase adds. Nothing in the fix had to change which form is blamed.

### The second location

Implemented exactly as this section specifies, with one deviation noted below.
Four reader globals (declared in `src/nucleusc.nuc` beside `g-peek`, maintained
in `lib/reader.nuc`):

* `g-paren-depth` — lexical nesting depth over **all four** bracket kinds
  (`(`/`)`, `[`/`]`, `{`/`}`, `#{`/`}`), bumped in `next-tok` as each bracket
  token is produced. Deliberately **not clamped at zero**: a negative depth is
  precisely "this closer has no matching opener anywhere", which is what
  distinguishes a stray top-level `)` from a `)` that merely turned up where a
  form was expected (inside an unclosed `[…]`, where the bracket it closes is
  real). String bodies and `;` comments never reach the token path, so unlike
  the external Python counter this is immune to a `)` inside a string literal.
* `g-form-open-line` — opening line of the `(` that most recently took the depth
  0 → 1 (the top-level form currently being read).
* `g-col0-open-line` / `g-col0-open-depth` — the heuristic itself: the **first**
  `(` that starts a line in column 0 while the depth is already nonzero, and the
  depth there.

Recorded while scanning, per the requirement: the column test is a
single-character lookbehind at the moment the token is produced (`g-pos` still
points at the bracket, so `g-src[g-pos-1] == '\n'` is exactly "this bracket is
the first character on its line"). That is strictly equivalent to a column
counter and needs no new mutable state threaded through `next-char`, which is
the only place newlines are counted — one fewer invariant a future lexer path
can forget to maintain.

`report-unterminated` (`lib/reader.nuc`) prints `report-at`'s existing
`<path>:<line>: error: <msg>` line, then one `  note:` line matching
`report-at`'s own note shape. Both callers use it: `read-list` and
`read-lit-elems`. It takes the closer the form is waiting for (`")"`, `"]"`,
`"}"`) so the advice is right for a vector/map/set literal too. It stays on the
`report-at` + `(err! parse-error)` path — no `die-at`, no `exit` — so REPL
recovery is unaffected (verified interactively as well as by `tests/repl/`).

**Deviation from the spec's wording.** The spec says "the first line *at or
after* it [the innermost unclosed form's opening line]". As built, the candidate
is the first such line **in the file**, without the "at or after" restriction,
because that restriction discards the most useful case. When the damage is in an
*early* top-level form, the innermost unclosed form at EOF is typically inside a
*later* form — e.g. `(defn a …` unclosed at line 1, `(defn b …` at line 3, a
`let` at line 4 that is what EOF interrupts. "First in file" reports line 3, the
exact point the file went wrong; "at or after line 4" would report nothing. The
two rules coincide in the common case (an unclosed nest followed by the next
top-level form), and "first in file" is never worse.

**Known limitation of the heuristic** (accepted, and the reason the deviation is
safe): a legitimate continuation line indented to column 0 inside a multi-line
form would be picked up as a false candidate. A scan of the whole repository —
`src/`, `lib/`, `examples/`, `tests/fixtures/`, `tests/repl/` — found **zero**
column-0 `(` at nonzero depth, so idiomatic Nucleus never produces one. The note
is advisory and the primary location is unaffected either way.

When there is no candidate the imbalance is inside the file's last top-level
form; the note then reports only how many forms were left open, never a bogus
second number.

### The odd-element `let` binding list — the spec's own repro does not have one

This is the part of the section that needed correcting rather than
implementing. Measured on the pre-change compiler:

| probe | shape | before |
|---|---|---|
| `(let (a:i32 1)` ⏎ `b:i32 2)` … `)))` (unbalanced) | binding list `(a:i32 1)` — **even**, 2 elements | `t.nuc:4: error: unexpected )` |
| the same, with one fewer `)` at the end so the file balances | same even binding list | `t.nuc:2: error: undefined: b:i32` |
| `(let (a:i32 1` ⏎ `b:i32)` … (extra `)` after a binding **name**) | binding list `(a:i32 1 b:i32)` — **odd**, 3 elements | `t.nuc:2: error: let: binding list must be even` |

Two findings:

1. **The check the spec asks for already exists and already fires.** An
   odd-element binding list is exactly what `emit-let`/`emit-with`'s even-count
   check catches, with a located, clear message.
2. **The shape the spec describes does not produce an odd element count.** An
   extra `)` after a binding's *value* leaves an even list (`(a:i32 1)`) and
   pushes the next binding into the **body**. So "notice that a `let` binding
   list ended at an odd element count" would not have diagnosed the spec's own
   repro. The odd count only arises from an extra `)` after a binding *name*,
   which is already handled.

The reader is also the wrong layer for the real shape, and not because of
generality: in the balanced variant the file parses **correctly** — there is no
imbalance for a reader-level check to see at all.

What was built instead, at the layer that can see it: `check-stray-typed-body`
(`src/nucleusc.nuc`, beside `check-colon-bindings`), called from `emit-let` and
`emit-with` after the binding loop and before the body loop. A `let`/`with`
**body** form that is a bare colon-typed symbol (`b:i32`) is never a meaningful
expression — it is the residue of a binding that fell out of the list — so it is
diagnosed by cause rather than by symptom:

```
t.nuc:11: error: let: 'b:i32' is a body form, not a binding -- an extra ')' probably ended the binding list early
```

Gated on the spelling not resolving in scope, so it can only ever replace a
diagnostic that was already fatal (`undefined: b:i32`), never pre-empt a working
program. It runs after the binding loop so the `inner` scope is populated. Per
[conventions.md CP-3](../../context/conventions.md), the even-count check is
*upstream* of this one and would mask it — but only for the odd-count shape,
which is a different mistake with its own correct message, so there is no
conflict.

For the **unbalanced** variant the reader still reports `unexpected )` at the
excess closer. That location is not wrong — paren counting cannot know which of
the two closers was the intruder, and the excess one is the only defensible
primary location — but it is unbounded, so the negative-depth test now adds:

```
t.nuc:13: error: unexpected )
  note: the form opened at line 10 is already closed -- look for an extra ')' between lines 10 and 13
```

which bounds the search to one top-level form. (The note is suppressed when the
depth is non-negative, i.e. when the `)` closes something real — a `)` inside an
unclosed `[…]` gets the bare message, as it should.)

### Result

| Case | Before | After |
|---|---|---|
| 8 levels, one `)` missing | `:12: unterminated list` | + `note: line 23 starts a new form in column 0 while 1 form(s) are still open -- a ')' is probably missing before line 23` |
| 8 levels, six `)` missing | `:12: unterminated list` | + `note: line 18 … while 6 form(s) are still open …` |
| imbalance in the file's last form | `:9: unterminated list` | + `note: end of file reached with 3 form(s) still open` (no second number invented) |
| unclosed `[` (vector literal) | `:7: unterminated vector literal` | + `note: line 9 … -- a ']' is probably missing before line 9` |
| extra `)` in a `let` binding list, file still balanced | `:11: undefined: b:i32` | `:11: let: 'b:i32' is a body form, not a binding -- an extra ')' probably ended the binding list early` |
| extra `)` in a `let` binding list, file unbalanced | `:13: unexpected )` | + `note: the form opened at line 10 is already closed -- look for an extra ')' between lines 10 and 13` |
| odd-element binding list (extra `)` after a *name*) | `:2: let: binding list must be even` | unchanged — already correct |

### Regression protection

Six fixtures (`tests/fixtures/w4c-*.nuc`), one per row above, all wired with the
existing `run_reject_at`. Its `loc` argument is a literal `grep -F`, so each
entry pins the **whole** primary line (`path:line: error: message`) in `loc` and
the **note with its second number** in `pattern` — a regression in either half
fails the test, with one compiler invocation per fixture. Each fixture's header
comment records its own before/after.

All six were negative-controlled against the pre-change compiler (`bin/nucleusc`,
the committed boot, which predates this phase): every one of the six assertions
fails there — five for a missing note, and `w4c-let-extra-paren` because the
message is entirely different. The fixtures are load-bearing, not tautological.

They also inherit W4a's `run_no_line_zero` sweep; none of the new diagnostics can
report line 0 (the reader's `g-line` starts at 1, and the `let` body check
borrows the enclosing form's line via `node-line`, per W4a).

### Bootstrap

`make bootstrap` is a byte-identical fixed point **without** `make
update-bootstrap`, as expected for a diagnostics-only change: the four new
globals and the two new reader functions are inert for any *valid* program, and
both stages compile the same source. This was the check on the riskiest part of
the change — `lib/reader.nuc` is on the compiler's own hot path, so any
accidental change to *accepted* syntax would have surfaced immediately.

### A note on reader-state hygiene

The four new globals are reset at the top of `read-program` rather than
save/restored at the three import sites that already save
`g-src`/`g-pos`/`g-line`/`g-peek`. `read-program` is the single entry point for
reading a whole file (batch driver, import, and REPL all call it), and reads
never interleave — an import is processed during *emission*, by which time the
importing file's own read has fully completed — so a reset at the one entry
point is complete, and adding a fourth pair of save/restore lines to three call
sites would be redundant state to keep in sync.

## W4d as built

**Status: Done.** `make test` (230 checks — the 226 from W4a+W4b+W4c plus 4
new W4d fixtures) and `make bootstrap` (stage1 == stage2, byte-identical, **no
`make update-bootstrap` reconverge needed on the first pass**) are green.

### Decision: fix at the failure site, not inside the `case` macro

This section's own text floats the macro-body route ("Detecting the wrong
shape in the macro is cheap") as the presumptive fix. It is not cheap — it is
**unworkable without new library plumbing**, confirmed empirically rather than
by inspection:

```
$ cat > /tmp/mtest.nuc <<'EOF'
(defmacro mtest (x)
  (do
    (die-at (x line) "mtest: deliberate macro-side diagnostic")
    x))
(defn main ():i32 (mtest 42) (return 0))
EOF
$ build/nucleusc -I lib /tmp/mtest.nuc -o /tmp/mtest
/tmp/mtest.nuc:3: error: unknown: die-at
```

A `defmacro` body is ordinary user-scope Nucleus code, JIT-compiled by
`emit-defmacro` into the same per-macro sub-module every macro invocation
resolves through (`expand-macro-call`'s `LLVMOrcLLJITLookup`). Its available
symbol set is whatever the *user's own file* has imported by that point, plus
whatever `emit-defmacro`'s comment calls "ordinary defns (`node-at`,
`intern-symbol`, ...)" — the small, stable AST/arena vocabulary macros are
meant to build ASTs with. `die-at`/`report-at` are defined in
`lib/reader.nuc`, which only the **compiler's own source** (`src/nucleusc.nuc`)
imports, explicitly, for its own diagnostics — `lib/prelude.nuc` (what every
ordinary program, including a `defmacro` body, auto-imports) does not pull it
in. So `case`, a macro shipped in `lib/macros.nuc` and loaded into *every*
compilation via the prelude, cannot call `die-at` any more than any other
user-written macro could — there is no special access for library-shipped
macros. Making this route work would mean designing and shipping a new
compile-time-diagnostic facility callable from macro bodies (e.g. exposing
`report-at`/`die-at` through the prelude, or a dedicated `(macro-error line
msg)` builtin) — real scope, not a cheap addition, and out of bounds for this
task.

The chosen fix is the brief's fallback, and turned out to be the only
practical option: **`emit-invoke-with-callee`** (`src/nucleusc.nuc`), the
single chokepoint every non-callable head funnels through regardless of how it
got there. A new helper, `case-clause-hint`, runs right before the existing
`die-at "value is not callable: ..."` and recognizes the two head shapes that
can never be a genuine call: a bare `NODE-INT` (`(0 ...)`), and a bound `_`
symbol (`(_ ...)`, only reachable if `_` is locally bound to something
non-callable — the `->` macro's placeholder convention, not a real call
target). Tracing the documented-but-wrong form confirms this is exactly where
it dies: `case`'s macro body (`lib/macros.nuc:91`) builds `(cond (= 1 (0
(printf ...))) (1 (printf ...)) true (_ (printf ...)))` from the clauses
verbatim (each clause node is spliced by `~(cur car)`/`~(rest car)`, unchanged,
so it keeps its **original reader line** — no line-stamping needed, unlike a
macro-synthesized form). Emitting the first `cond` test requires emitting `(0
(printf "zero\n"))` as a value, which is exactly the `emit-list` "arbitrary
head" branch → `emit-callable-value` → (no `get`, one non-symbol arg) →
`emit-invoke-with-callee` → no `invoke` method for `i32` → the die-at this
phase targets. Because the message change only replaces text at an
**already-fatal** call (never turns a working program into an error, never
makes a previously-rejected program compile), it is inert for every existing
program by construction — the "avoid `lib/macros.nuc`" bootstrap hazard this
brief warned about does not even arise, since nothing here touches
`lib/macros.nuc` at all.

This is more general than the letter of the brief asked for, exactly as the
brief anticipated: it also catches a bare integer literal called anywhere
outside a `case` form (`(3 4)`), with the same hint, at no extra implementation
cost — one check, reached from one call site, regardless of what macro (if
any) produced the offending form.

### The generic macro-arity messages

`expand-macro-call` (`src/nucleusc.nuc`) raised `(fmt-s "macro: wrong number of
args" 0)` / `(fmt-s "macro: not enough args" 0)` — a `%s`-less format string
fed a dummy `0` int argument, naming neither the macro nor either count. Per
the fixed-arity format-helper rule (context/conventions.md), this needed a new
helper of the right shape rather than overloading an existing one: `fmt-s-2i`
(`src/format.nuc`, one `%s` + two `%d`) was added beside `fmt-2s-i`. Both
messages now read `macro '<name>': expects <N> args, got <M>` (fixed arity) /
`macro '<name>': expects at least <N> args, got <M>` (variadic, `N` = the
`&rest`-excluding minimum). `if` (`(defmacro if (test then else))`,
`lib/macros.nuc:80`) additionally gets its own exact wording when called with
2 args (test+then, no else) — the one-armed-`if` habit carried over from
C/JS — ahead of the generic message: `if requires an else branch; use (when
test then…) for a guard`. `if`'s *expansion* is untouched; only the arity
diagnostic changed, per the brief's constraint.

### Result

| Case | Before | After |
|---|---|---|
| `case`'s documented-but-wrong clause form, `(case 1 (0 ...) (1 ...) (_ ...))` | `t.nuc:3: value is not callable: no \`invoke\` method is defined for this type` (names the clause's line, but not the mistake) | `t.nuc:3: 0 is not callable -- an integer literal can never appear in call position; if you meant a \`case\` clause: case takes flat value/result pairs, not clauses: (case x 1 "one" 2 "two" "other")` |
| `examples/case.nuc`, the real flat syntax | compiles, runs correctly | unchanged (regression-checked by the ordinary `examples/*.nuc` + `tests/expected/case.out` loop in `make test`, no new fixture needed) |
| one-armed `if`, `(if (= 1 1) (printf "y\n"))` | `t.nuc:1: macro: wrong number of args` | `t.nuc:1: if requires an else branch; use (when test then…) for a guard` |
| fixed-arity macro, too many args (`for` given 5 args instead of 4) | `t.nuc:2: macro: wrong number of args` | `t.nuc:2: macro 'for': expects 4 args, got 5` |
| variadic macro, too few args (`(case)`, 0 args, `form` required) | `t.nuc:2: macro: not enough args` | `t.nuc:2: macro 'case': expects at least 1 args, got 0` |

### Regression protection

Four fixtures (`tests/fixtures/w4d-*.nuc`), all wired with `run_reject_at`
(pins both the message and the `<path>:<line>: error:` prefix, so a location
regression fails the test too): `w4d-case-clause-form`,
`w4d-if-one-armed`, `w4d-macro-too-many-args`, `w4d-macro-too-few-args`. Each
fixture's header comment records its own before/after and the exact line the
diagnostic must land on. All four inherit W4a's `run_no_line_zero` sweep
(`make test`'s `w4a-no-line-zero` unit, which compiles every
`tests/fixtures/*.nuc`) — none of the new diagnostics can report line 0,
since every one borrows a real reader-sourced node's line (the clause node's
own line for the `case` fix; the whole macro-call cell's line,
`(unsafe/cast ptr:Node call) line`, for the arity fixes, exactly as
`expand-macro-call` already did before this change). No new fixture was added
for `case`'s correct flat syntax since `examples/case.nuc` /
`tests/expected/case.out` already exercises it via the standard examples loop.

### Bootstrap

Both changes live entirely in `src/nucleusc.nuc` (the `case-clause-hint`
helper plus its call site) and `src/format.nuc` (the new `fmt-s-2i` helper) —
neither touches `lib/macros.nuc`, so the special auto-imported-macros
string-pool-shift hazard this brief flagged never arises. `make bootstrap`
was byte-identical (`stage1.ll == stage2.ll`) on the **first** build, with no
`make update-bootstrap` reconverge pass required — the preferred outcome the
brief called out, achieved by construction rather than by discovering the
hazard and working around it.

## W4e (generated table) as built

**Status: Done.** `docs/stdlib.md`'s availability tables are now generated by
`scripts/gen-stdlib-table.py`, wired into the suite as the `stdlib-table-
generated` unit. `make test` (231 checks — the 230 above plus this one) and
`make bootstrap` (stage1 == stage2, byte-identical) are green. This item
touched no compiler source (`src/`, `lib/`) at all — script + docs + test
harness only — so the bootstrap gate was structurally guaranteed to be
unaffected; run anyway per the brief's instruction, confirmed clean.

### Correction to the brief's ground truth: the mechanism is bigger than `string.h`

The brief's root-cause claim — "`lib/prelude.nuc` line 11 is `(import-use
"string.h")`... that is why no hand-curated table can be correct" — is correct
as far as it goes but **incomplete**: it names only one of the three headers
actually in the auto-imported chain. `lib/prelude.nuc` does directly
`(import-use "string.h")`, but it also `(import-use node)` a few lines later,
which pulls in `lib/node.nuc`, which `(import-use arena)`s `lib/arena.nuc`,
which **itself** does:

```lisp
(import-use "stdio.h")
(import-use "stdlib.h")
(import-use "string.h")
```

So the true "no import needed" set is whatever `clang -E -x c -include <hdr>
/dev/null` resolves for **stdio.h + stdlib.h + string.h** transitively, not
`string.h` alone — that's why `printf`/`malloc`/`fopen` were ever callable
without an explicit import in the first place; the brief's own framing
sentence, if taken literally (string.h only), would not explain why `printf`
(a stdio.h function) resolves. Confirmed by reading `lib/arena.nuc:12-14` and
independently by probing: a program that starts with `(exclude-prelude)`
cannot call any of these three headers' functions; the ordinary auto-prelude
program can call all three headers' worth.

### A second, larger false-claim than the brief's own ground truth found

The brief's ground-truth table calls out `close`/`dup2` (listed under
"unistd") as the confirmed false claims and treats `isspace`/`isdigit`
("ctype") as untested. Measuring all five together: **`dup`, `isspace`, and
`isdigit` are equally unavailable** (`unknown: dup` / `unknown: isspace` /
`unknown: isdigit`), for the same root-cause reason as `close`/`dup2` — the
transitive header chain established above is stdio.h + stdlib.h + string.h;
`ctype.h` and `unistd.h` are **never reachable from it at all**, on any host.
So it is not just two names that were false — the doc's entire "ctype" and
"unistd" sections (five names total) were false, unconditionally, regardless
of host. The generated table has no "ctype"/"unistd" sections at all now
(zero of their claimed names probe as available), rather than emitting an
empty section header.

The brief's `strcasecmp` observation ("not pre-declared... which is correct
but undocumented" per the findings report, but measured available on this
host) is confirmed exactly as the brief describes, and is now baked into the
generator rather than trusted as a one-off note: `strcasecmp` is declared in
glibc's `<strings.h>`, which glibc's own `<string.h>` transitively includes
(confirmed by inspecting the preprocessed output: `# 1 "/usr/include/
strings.h"` appears when preprocessing `string.h`) — an implementation detail
of *this host's* glibc, not a portable guarantee, which is exactly the
generate-don't-curate argument the brief makes.

### The generator

`scripts/gen-stdlib-table.py` (no `scripts/` directory existed before this
task, so there was no established convention to match; Python was chosen over
bash/awk for this script specifically because the C-declaration parsing step
needs real paren/brace-depth tracking, which is far more reliable as a small
recursive-descent-style scanner than a regex pipeline — the orchestration
shape otherwise mirrors `tests/run-tests.sh`'s own conventions: a `--check`
mode for the suite, self-contained temp files, host-tolerant pass/fail).

**Candidate sourcing.** The brief allows a curated candidate list "if
enumerating the full reachable set is impractical." It turned out to be
practical: `clang -E -x c -include <hdr> /dev/null` for each of stdio.h/
stdlib.h/string.h, split into top-level (paren/brace-depth-0) `;`-terminated
statements, is parsed for a `NAME (ARGS)` declarator (first identifier
immediately followed by `(` in the statement — trailing `__attribute__((…))`/
`__asm__(…)` trailers come after it and are ignored). This is a full
transitive enumeration (~150-200 names across the three headers on this
host), unioned with every name currently claimed in `docs/stdlib.md`'s tables
(so a name that stops being available, or — as with `close`/`dup`/`dup2`/
`isspace`/`isdigit` — was never available, is caught and reported as
*removed*, never silently dropped from the candidate set just because header
enumeration didn't happen to find it). Per the brief's own instruction, the
doc is regenerated from probe results only, never from the candidate list
directly — a candidate that fails probing is simply absent from the output.

**Classification.** For each candidate, a one-line probe `(defn main ():i32
(<name>) (return 0))` is compiled with `build/nucleusc --emit-llvm`
concurrently (`ThreadPoolExecutor`, worker count following `NUCLEUS_TEST_JOBS`
so a debugging `NUCLEUS_TEST_JOBS=1` serial run doesn't also serialize this
script's internal probing); available iff stderr does **not** contain
`unknown: <name>` — exactly the brief's rule ("a different error (arity,
type) still means available").

**Signature rendering.** Each declaration's return/parameter C types are
mapped through the same coarse simplification the original hand-written table
already used (every pointer kind, including array-decayed and function-
pointer parameters, collapses to `ptr`; every integer kind maps to `i32`/`i64`
by width; `float`/`double` to `f32`/`f64`). A candidate whose return or any
parameter type has no confident mapping (`div_t`/`ldiv_t`/`lldiv_t`
struct-by-value returns, `va_list` parameters, `long double`) is **dropped
from the generated table rather than guessed at** — this is the concrete
form the brief's "scope your claims to what you actually measure" took here:
better to omit `qsort`'s cousin `lldiv` than assert a signature this script
isn't confident in. Reserved (leading-`_`) names are also excluded (matching
C's own "reserved to the implementation" convention; none of the doc's
existing claims used one).

### Result

The generated table grew from 25 hand-curated rows to 220 probe-confirmed
rows. Delta from the pre-existing (hand-curated) doc:

* **Removed (5, all false claims):** `close`, `dup`, `dup2`, `isdigit`,
  `isspace` — the entire former "unistd" and "ctype" sections.
* **Added (191, undocumented but available):** includes every name the
  brief's findings report called out (`getenv`, `remove`, `fopen`, `fwrite`,
  `fclose`, `snprintf`, `strncmp`, `strstr`, `memcmp`, `strcasecmp`) plus 181
  more from the full transitive enumeration (e.g. `qsort`, `bsearch`, `atoi`,
  `rand`/`srand`, `strdup`, `strtod`, `posix_memalign`, `arc4random`,
  `reallocarray`, `strlcpy`/`strlcat`) that the curated list never
  considered. Spot-linked (not just IR-compiled) a sample of the more obscure
  additions (`arc4random`, `reallocarray`, `posix_memalign`, `strlcpy`,
  `strlcat`, `clearenv`, `rpmatch`, `strtoq`, `strtouq`) to confirm they
  resolve at actual link time on this host, not just at the compiler's
  declaration-resolution level.

This is a substantially larger table than the brief's own worked examples
implied. That is a deliberate consequence of the brief's own stated
preference order — full enumeration over curation "if practical" — not scope
creep: every row is machine-verified, none is hand-added. If a smaller,
hand-picked subset is preferred for readability, the candidate-sourcing step
is the one place to change (e.g. filter to a maintained allow-list unioned
with the doc's own prior claims) without touching the probing/rendering
machinery.

### Framing paragraph

`docs/stdlib.md`'s opening paragraph no longer claims startup registration;
it names the real mechanism (prelude → node → arena's three header imports),
states the host/libc-dependence explicitly (pointing at `context/build.md`'s
musl note), and gives the regeneration command. The generated region is
delimited by `<!-- BEGIN GENERATED: availability (scripts/gen-stdlib-
table.py) -->` / `<!-- END GENERATED -->` markers placed immediately after
this paragraph; everything from the `---` rule onward (the hand-written
`StrView`/`Keyword` sections) is untouched — verified by diffing those
sections before/after regeneration.

### Host-dependence decision (design consideration the brief asked to be resolved explicitly)

**Decision: the suite check does not require an exact match against the
committed doc.** It fails only when a name the **committed** doc currently
claims as available no longer probes as available on the host running the
suite (`check_against_committed` in the script) — the actual finding this
whole phase exists to catch. It does **not** fail merely because the fresh
probe on this host finds additional available names beyond what's committed,
or is missing some the committed doc lists — availability is host/libc-
dependent by construction (glibc vs musl, `context/build.md`'s musl note), so
a different host (an Alpine/musl runner, in particular) legitimately has a
different available set, and requiring byte-identical output would make the
check fail spuriously there — "a check that fails spuriously on a different
host is worse than no check," per the brief. When the fresh table matches the
committed one exactly (the expected common case — this container's glibc is
what generated the committed table), the check additionally reports "exact
match" so a true regression on *this* host is still fully visible, just not
promoted to a hard failure unless it's specifically a false claim.

Verified with two negative controls (both reverted after verification, no
trace left in the committed doc):

1. **False claim reintroduced** (`close` spliced back into the generated
   region as if still claimed): `--check` printed `FAIL: docs/stdlib.md
   claims these are available without import, but they no longer probe as
   available on this host: close` and exited 1 — exactly the regression this
   phase exists to catch.
2. **Benign incompleteness** (the `abs` row deleted, simulating a doc
   committed from a host missing one name): `--check` printed `OK:
   host-diverged from the committed table, no false claims. 1 additionally
   available on this host: abs -- consider regenerating...` and exited 0 —
   confirming the design doesn't spuriously fail on the direction that's safe.

### Suite wiring and timing

`run_stdlib_table` (`tests/run-tests.sh`) follows the existing unit shape
(self-contained, buffers its `PASS`/`FAIL` line) and is dispatched with
`spawn run_stdlib_table` alongside the W4d units. `make gen-stdlib-table` is
the convenience Makefile target for actually regenerating the doc (the suite
unit only checks; it never writes).

Measured timing matters here because a slow new unit is a real cost to the
parallel suite. Standalone, `scripts/gen-stdlib-table.py --check` takes ~4.7s
wall (16-core host; ~200 concurrent `build/nucleusc` invocations, one per
candidate). But `tests/run-tests.sh`'s own baseline — measured by temporarily
disabling the new unit's `spawn` line and rerunning `make test` — is **already
~18.8s**, not the "~8.5s" `context/build.md` currently documents (that figure
predates the AVR/RISCV gates and the W4a–W4d fixture batches added since, and
has simply gone stale as the suite grew — not something this task changed).
Against that actual baseline, this unit's marginal cost to the full parallel
`make test` run is **~2.1s** (18.8s → 20.9s, both measured back-to-back on
the same host), because its internal ~4.7s of concurrent probing overlaps
with the tail of other still-running units rather than adding on top
serially. `context/build.md`'s timing figure was left as-is (out of this
task's scope, and it will keep drifting as more units are added regardless of
this one) but is noted here for whoever next audits it.

### A note on what this script does and doesn't verify

The probe classifies at `build/nucleusc --emit-llvm` (IR emission only, no
link), matching the brief's own methodology and the compiler-level meaning of
"available without import" (the compiler resolves the call rather than dying
`unknown: <name>`). It is not a link-level guarantee in general — a header
can declare a symbol glibc's preprocessor exposes but some other libc's
`.so` doesn't ship. On this host every generated row was additionally spot-
checked to link (see Result above), but the generated table's claim, precisely
scoped, is compile-time resolution, not "linked and ran" — consistent with the
brief's instruction not to read "it compiled" as more than what was measured.

## W4e (docs) as built

**Status: Done.** `make test` (231/231, unchanged from the generated-table
phase — this phase touched only `docs/` and this design doc) and `make
bootstrap` (stage1 == stage2, byte-identical) are green. Touched no compiler
source, `lib/`, or test fixtures.

### `docs/special-forms.md`'s `case` entry

Confirmed false exactly as this document's §6.1/W4d sections describe, and
confirmed **misfiled** as well as wrong: `case` is a macro (`lib/macros.nuc:91`,
`(defmacro case (form &rest clauses)) ...`), not a special form, and this
table is not where the language's other pure-sugar macros live — `if`,
`when`, `unless`, `dotimes`, `for`, `doseq`, `->`, `zero?`, `null?` appear
**nowhere** in `docs/special-forms.md` (verified by grep); they are documented
once, correctly, in `docs/macros.md`'s "Standard Macros" table. (`and`/`or`
are the one exception, and deliberately so — they are documented in full in
`special-forms.md` because they carry real short-circuit/narrowing semantics
worth a long-form writeup, with `macros.md` linking back for the fold table
only.) `case` fits the plain-sugar bucket, not the `and`/`or` bucket.

**The correct documentation already existed** — `docs/macros.md` line 10 (the
Standard Macros table) already had the true signature `(case form v1 r1 v2 r2
... default)` expanding to `(cond (= form v1) r1 ... true default)`, and line
23 already had accurate prose (equality dispatch, required trailing default,
overloadable `=`, re-evaluates `form` per comparison). Both were verified
against `lib/macros.nuc:91` and by compiling `examples/case.nuc` with
`build/nucleusc` (output: `zero`/`two`/`many`/`a vowel? 1`/`z vowel? 0`,
matching `tests/expected/case.out`). So the fix is not a rewrite, just a
**deletion**: the false, misfiled row is removed from `docs/special-forms.md`'s
table entirely, leaving the one correct copy in `docs/macros.md`. No dangling
reference — grepped the whole `docs/`/`design/`/`context/` tree for
`special-forms.md` mentions naming `case`; the only ones were this design
doc's own findings, which are historical (describe the bug that was fixed) and
correctly left alone per the "add a Status note, don't rewrite" rule for
*design* documents (this rule does not apply to `docs/`, which must simply be
true).

Independently re-verified the corrective diagnostic W4d built (`docs/`-visible
behavior, not just the fix): compiling the documented-but-wrong nested-clause
form now gives

```
$ build/nucleusc -I lib case_wrong.nuc
case_wrong.nuc:3: error: 0 is not callable -- an integer literal can never
appear in call position; if you meant a `case` clause: case takes flat
value/result pairs, not clauses: (case x 1 "one" 2 "two" "other")
```

exactly matching W4d's own Result table.

### `docs/special-forms.md`'s `addr-of` entry (§6.3)

Confirmed the finding: the table row said only that a frame-local address "is
escape-tracked so it cannot be returned," which is true but reads as though
`return` is the *only* thing tracked, or worse, that any onward use is
suspect. The file's own "Pointer lifecycle" section (lines ~183–246) already
had the correct, complete rule stated positively (escape sinks are `return`
and stores into longer-lived memory only; passing as a call argument is an
explicitly allowed borrow) — the bug was that the compact table row didn't
say this, and a reader skimming the table (as the brief notes the Doom port
did) would reasonably stop there and never reach the fuller section 150 lines
later.

**Verified the borrow claim empirically before writing it down**, per this
phase's own instruction not to re-derive claims from prose:

```lisp
(import-use "stdio.h")

; C out-parameter idiom: write a result through a pointer to caller storage.
(defn set-both (out-a:ptr:i32 out-b:ptr:i32):void
  (ptr-set! out-a 41)
  (ptr-set! out-b 99))

(defn main ():i32
  (let (a:i32 0 b:i32 0)
    (set-both (addr-of a) (addr-of b))
    (printf "a=%d b=%d\n" a b)
    (return 0)))
```

Compiles and runs with `build/nucleusc`, prints `a=41 b=99` — passing
`(addr-of local)` as a call argument works, and the callee's write is visible
to the caller after the call returns, confirming the answer to the brief's
question is **yes**. Also re-confirmed the negative case is still rejected
(`(defn bad ():ptr (let (x:i32 5) (return (addr-of x))))` →
`badreturn.nuc:3: error: address of frame-local storage escapes via return —
the pointed-to storage is reclaimed when this function returns`), so the two
passages (table row and "Pointer lifecycle" section) now agree and both match
the compiler.

The table row was rewritten to state the rule positively, with the C
out-parameter transcription as the worked example (per the brief), and to
point at "Pointer lifecycle" for the full sink list rather than repeat it.
The "Pointer lifecycle" section itself needed no change — it was already
correct; only its lack of a forward pointer from the compact row was the bug.

### Sweep of the rest of `docs/special-forms.md`

Probed every other row making a concrete, checkable claim about accepted
syntax or generated code, compiling two-line (or so) programs with
`build/nucleusc` rather than reading source:

| Claim | Probe | Result |
|---|---|---|
| `get`/`_get` "zero-overhead" plain field read | `(defstruct Point x:i32 y:i32) (defn getx (p:ptr:Point):i32 (return (p x)))`, inspected with `--emit-llvm` | Confirmed: body is `alloca`/`store`/`load`/`getelementptr`/`load`/`ret` — no `call` instruction. |
| `label`/`goto`: forward and backward both resolve | `goto` before a `label`, then a backward `goto` in a loop | Both resolved; loop ran to completion. |
| `label`: "duplicate declarations... last one in textual order is the canonical target" | `(goto dup) (label dup) (printf "first\n") (return 1) (label dup) (printf "second\n") (return 0)` — a **forward** `goto` to a name declared twice | Printed `second dup` — confirmed the *last* declaration wins, including for a jump that appears before either. |
| `goto-ptr`: "the IR lists every label declared in the current function as a possible destination" | `(label-addr b)` computed and dispatched with `goto-ptr` past an intervening `(label a)` | Landed on `b`, skipping `a` — confirmed. |
| `(StructName init...)`: shadowing a struct name with `defn` is a compile-time error | `(defstruct Point ...) (defn Point ():i32 (return 0))` | `error: 'Point' already names a type — a symbol may name only one kind of thing`. Confirmed (message text differs slightly in wording from the doc's paraphrase, but the doc doesn't quote an exact string, only describes the behavior — accurate). |
| `array`: designated + positional mixing, implicit length `max(positional-count, max-designated-index+1)` | `(array i32 1 2 (5 99))` then read indices 0–5 | `1 2 0 0 0 99` — length 6 (`max(2, 5+1)`), positions 0/1 positional, index 5 designated, gaps zero-filled. Confirmed exactly. |
| `(StructName init...)`: "positional inits fill the next field that has not been designated" | `(P3 (y 5) 10 20)` on a 3-field `x y z` struct — designate `y` first, then two positional | `x=10 y=5 z=20` — positional fills skipped the already-designated `y`. Confirmed exactly. |
| `and` cumulative narrowing (`(m field)` typechecks after `(!= m null)` in the same chain, short-circuits so the field read never executes on the null path) | `(and (!= m null) (do (printf "%d\n" (m v)) true))` called once with `(some b)` and once with `(as-ref null)` | Printed the value once, nothing the second time (no crash, no bogus read) — confirmed both the narrowing (it type-checked at all) and the short-circuit. |
| `if-some`/`when-some`/`unwrap`/`unwrap-or`/`as-ref`/`some` | Ran the existing `examples/maybe.nuc` against `build/nucleusc` rather than re-probing from scratch (already an `examples/`+`tests/expected/` regression pair exercising every one of these forms) | Output byte-matches `tests/expected/maybe.out`. Confirmed. |

**Nothing else in the file was found to be wrong.** The `unsafe/cast`/`as`
ladder's claims were not independently re-probed here — they were empirically
verified end-to-end in the prior Stage 14 UN-5 docs sweep (see
[`project_nucleus_un5_docs`](../../context/conventions.md) history) and no
change in this stage touches that machinery (confirmed by `git status`: this
branch's diff is confined to the diagnostics/stdlib-table area).

### Sibling gap found in `docs/toplevel.md` / `docs/errors.md`

Not a *false* claim (grepped `docs/` for any example showing a type-annotated
`defstruct`/`defunion`/`defprotocol`/`defmacro`/`deferror` name compiling —
none exists), but an **inconsistency** the brief's explicit checklist caught:
W4b made a colon-annotated name a hard error for all seven definers
(`defconst`, `defenum`, `defstruct`, `defunion`, `defprotocol`, `defmacro`,
`deferror`), and `docs/toplevel.md` already documented the rule for
`defconst` (row landed by the W4b docs pass) and `defenum` ("Like `defconst`,
the enum's own name takes no type annotation") — but **not** for `defstruct`,
`defunion`, `defprotocol`, or `defmacro`, and `docs/errors.md`'s `deferror`
section didn't mention it either. Silence isn't a false claim, but leaving
four of seven siblings undocumented while the other three explicitly state
the rule reads as though those four might behave differently. Re-verified all
five directly against `build/nucleusc` before writing anything down (all five
match the W4b as-built Result table exactly: `defstruct: takes no type
annotation; write (defstruct S ...)`, and the `defunion`/`defprotocol`/
`defmacro`/`deferror` analogues), then added one sentence each to
`docs/toplevel.md` (defstruct/defunion/defprotocol/defmacro rows, matching
`defenum`'s "Like `defconst`, ..." phrasing, and noting each definer's
genuine template/parametric head — `(Vector T)`/`(Seq E)` — is unaffected)
and to `docs/errors.md`'s `deferror` section.

### Not touched, and why

* `context/build.md`'s `~8.5s` parallel-suite-timing figure — the "W4e
  (generated table) as built" section above already found and flagged this as
  stale (measured baseline is now ~18.8s) but explicitly left it as out of
  scope for that phase. It remains out of scope here too: this phase's brief
  is a `docs/`-truthfulness sweep, and `context/build.md` is session-continuity
  material, not user-facing language documentation. Left as the prior phase's
  note for whoever next audits `context/build.md`.
* `docs/stdlib.md` — untouched, per the brief's explicit instruction (generated
  region is generator-owned; its framing paragraph was already fixed by the
  prior phase).
