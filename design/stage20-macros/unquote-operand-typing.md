# Typing the unquote operand — the fix for §10.3

**Status: BUILT 2026-09-15 — U1 (§6), U2 (§7), U3 (§8).** Closes
[quasiquote-levels.md](quasiquote-levels.md) §10.3, which
[computed-macro-arguments.md](computed-macro-arguments.md) C3 corrected from one
manifestation to two and promoted in priority — and which is really **three**
(§6.2).

---

## 1. One cause, two faces

`emit-qq-form`'s level-1 unquote branch (`src/nucleusc.nuc:2704`) emits the
operand and uses the resulting `Val` **without checking its type**. Everything
in §10.3 follows from that one omission.

| shape | what the author sees | why |
|---|---|---|
| nested, `` `(_+ 0 ~n) `` | `'%t0' defined with type 'i32' but expected 'ptr'`, naming generated code | the `Val` is passed to `@__cons`, and LLVM is the first thing to object |
| **bare**, `` `~n `` | `macro 'm': returned null` — no line, no `~`, no type | the `Val` *is* the body's value, and `compile-macro-body`'s body loop keeps `last-val` only for a `TY-PTR`, so a non-pointer is dropped on the floor |

The second is the worse message and the one that hides its own cause, but it is
not a second defect. **Both go through the same branch, so one check retires
both** — the `last-val` filter merely decides which symptom you get.

## 2. The fix

### U1 — check the operand where it is emitted

In `emit-qq-form`'s level-1 unquote branch and `emit-qq-list`'s unquote-splice
branch, require the emitted `Val`'s type to be node-typed.

**Reuse, do not rewrite.** C2 already built both halves for the computed-argument
path, and this is the same question one level over:

* `ct-node-typed?` (`src/nucleusc.nuc:1519`) — TY-PTR whose element is `Node` or
  absent. Bare `ptr` is admitted deliberately, because the compiler's own node
  producers (`macroexpand-form`, `expand-macro-call`) are declared that way, and
  `?&Node` is a TY-PTR with the null niche.
* `ct-eval-require-node` (`:1533`) — the message shape, already worded for this
  exact class. It needs the subject generalised from "the computed argument
  '~5'" to cover an unquote operand; the note ("must evaluate to a node — what a
  quasiquote, `quote` or a ':(raw Node)' function yields") already says the right
  thing for both.

### U2 — the residual: a macro body that yields no node at all

`(defmacro m () 5)` has no unquote, so U1 never sees it, and the `TY-PTR` filter
still turns it into `returned null`. Same class, separate site: check the macro
body's own result type in `compile-macro-body`'s body loop, where the `Val`
already is — which is where C2 put the equivalent check for `is-arg`.

### U3 — `node-int` in `lib/node.nuc`

`lib/node.nuc` offers `alloc-node`, `make-cell`, `intern-node` and
`intern-symbol`, and **no integer-node constructor**. That is why interpolating a
computed integer — the natural way to write a producer for a `~@e` argument list
— has no clean spelling.

It is *not*, however, impossible. Probed: a program builds one in six lines with
`alloc-node` plus `(set! (n 'kind) NODE-INT)` and `(set! (n 'i) …)`, and it
works end to end (exit 3). So U3 is not "add the only way", it is "stop making
people poke fields" — a five-line library addition with no compiler change, so
that U1's diagnostic can point at a one-liner rather than a recipe.

## 3. The risk that decides the gate

**`ct-node-typed?` is stricter than LLVM.** LLVM accepts *any* `ptr` into
`@__cons`; the predicate accepts only bare `ptr` and `ptr:Node`. So a macro that
unquotes a pointer to something else compiles today and would newly be an error
under U1. Nothing in the tree is known to do that — but that is a measurement,
not an argument, and this project has the procedure for it.

**Land U1 warn-only, sweep, require zero fires, then promote.** That is exactly
L8's `--warn-ct-shadow` methodology: the warning defaulted on only because it
fired zero times across `lib/`, `src/` and `examples/`, measured. The sweep here
is the same set plus `tests/`, whose fixtures deliberately contain odd macros and
are therefore the most likely place to find a legitimate counter-example.

The other two gate items are cheap:

* **`make bootstrap` byte-identical.** A type check emits no IR, so any movement
  means the check changed behaviour for valid code.
* **No expectation churn.** Nothing asserts the current LLVM text — it cannot,
  being undiagnosed — so no existing test should need editing. If one does, that
  is a finding, not a fix-up.

One open question for U3: adding a `defn` to `lib/node.nuc` may move the
compiler's own output if `src/` reaches that file. Check before assuming that
phase's gate is free; if it does move, U3 is where a boot refresh lands.

## 4. The alternative: lift instead of diagnose

`~n` where `n:i32` could **build a `NODE-INT`** rather than erroring — Common
Lisp's comma inserts any datum, and this would close the usability gap outright
instead of documenting it.

**Not proposed, for four reasons**, the last of which is the real one:

1. **It is U1 plus a conversion, never instead of it.** A struct or an arbitrary
   pointer has no node representation, so the diagnostic is still required for
   everything outside the lifted set. Lifting only shrinks how often it fires.
2. **The lifted set is arbitrary.** i32 and i64, plainly — then `StrView`?
   `String`? `bool`? `f64`? `Symbol` (which `intern-node` already covers)? A
   partial set is worse than none, because the rule stops being statable.
3. **[quasiquote-levels.md](quasiquote-levels.md) §10.1's arithmetic rests on
   unquote being Node-only.** `~~'v` ≡ `~v` is derived from the operand having to
   evaluate to a `Node*`; making unquote polymorphic puts that identity back in
   play for no reason connected to this defect.
4. **It masks a real error.** `~x` where `x` is accidentally an `i32` instead of
   a node is a *mistake*, and today's only virtue is that it is a loud one.
   Lifting makes it silently produce an integer literal in the expansion — the
   same species of silence as the `-rdynamic` collision that made part three a
   soundness item.

**When it becomes right:** after U1 ships and its fires are measured. If they are
dominated by the i32 case, lifting is a convenience with evidence behind it
instead of a guess — and it can then be added compatibly, because everything it
would newly accept is an error under U1.

## 5. Phases

**U1 — the check, warn-only, and the measurement. DONE 2026-09-15, see §6.** The
branch in `emit-qq-form`/`emit-qq-list`, reusing `ct-node-typed?` and
`ct-eval-require-node`'s wording, behind a warning rather than a `die-at`.
*Gate:* `make bootstrap` byte-identical; a sweep of `lib/`, `src/`, `examples/`
and `tests/` reporting its fires. **Zero is the condition for U2.** A non-zero
count is a finding that changes the design, not an obstacle to work around.

**U2 — promote to an error, and close the bare face. DONE 2026-09-15, see §7.**
U1's warning becomes a located `die-at`; `compile-macro-body`'s body loop gains
the result-type check. *Gate:* both §10.3 rows become located errors naming the
author's own text; the `returned null` shape no longer reachable from a typed
mistake; tests in `tests/suite-refusals.nuc` for both faces and for
`(defmacro m () 5)`. **The body-loop half is a new site U1's sweep did not
measure, so it gets U1's gate rather than U1's result:** warn-only, sweep,
promote on zero.

**U3 — `node-int`. DONE 2026-09-15, see §8.** `lib/node.nuc`, five lines, no
compiler change; U1's note updated to name it. *Gate:* `make test`; confirm
whether `src/` reaches `lib/node.nuc` before assuming bootstrap is unaffected.

**Documentation:** [quasiquote-levels.md](quasiquote-levels.md) §10.3 and its §8
bullet stop being open items and point here;
[computed-macro-arguments.md](computed-macro-arguments.md) §4.6's usability note
resolves.

---

## 6. U1 as built

**Zero fires. U2 may proceed.**

### 6.1 The check

`qq-require-node-operand` (`src/nucleusc.nuc:1559`), 21 lines, called from
`emit-qq-form`'s level-1 unquote arm and `emit-qq-list`'s level-1 splice arm and
nowhere else. `ct-node-typed?` and `ct-eval-arg-spelling` are reused verbatim.

**It is a sibling of `ct-eval-require-node`, not a reuse of it** — the one thing
§2 got wrong. That function's subject comes from `ct-body-who`, which assumes a
compile-time body; quasiquote is also legal in an ordinary `defn`, where
`ct-body-who` would announce a plain function as "compile-time block". The note
is §2's, and the message names the operand as the author spelled it.

### 6.2 A third manifestation §10.3 does not record

`emit-qq-list`'s splice arm has the same hole against `@__append`:
`` `(_+ 0 ~@n) `` with `n:i32` was a fourth undiagnosed shape, reproducing on
the committed `bin/nucleusc` like the other two. C3's `splice` flag made it free
— the diagnostic quotes back `~@n`, and the note switches to "`~@` splices its
value in as source", matching `ct-eval-require-list`'s existing wording.

### 6.3 The sweep

**478 `.nuc` files** across `lib/`, `src/`, `examples/` and `tests/`, each
compiled individually with the new binary, stderr captured: **zero fires.** The
20 warnings that did appear are pre-existing C-header and cheader-export ones.

**§3's risk is measured, not assumed.** 196 of the 478 exit non-zero — 163
refusal fixtures, plus the 13 `src/` modules and 20 `tests/suite-*.nuc` that do
not stand alone — so "it never fired" could have meant "it was never reached".
Two independent readings close that:

* A second compiler was built whose check warns on **success** instead of
  failure. It reports the level-1 arm reached **50,207 times across 64 files** —
  `lib/macros.nuc` 43,524 of them, `src/nucleusc.nuc` 1,765, down to
  `examples/quasiquote.nuc`'s 2.
* **No failing fixture contains an unquote token at all**, so nothing was cut
  short before its `~`. The 13 `src/` modules and 20 suite files are covered by
  `src/nucleusc.nuc` and `tests/nuctests.nuc`, which compile clean.

### 6.4 The other two gate items

`make bootstrap` byte-identical (`PASS: stage1.ll == stage2.ll`), and zero
warnings while the compiler compiles itself. `make test` **1040/0/0** with no
expectation edited — §3's prediction that nothing asserts the current text held.

### 6.5 What the author sees now

```
u1-nested.nuc:3: warning: the unquote operand '~n' must evaluate to (raw Node), not i32
  note: `~` substitutes its value as source, so it must evaluate to a node — what a quasiquote, `quote` or a ':(raw Node)' function yields
u1-nested.nuc:1: compile-time: IR parse error: <compile-time>:200:30: error: '%t5' defined with type 'i32' but expected 'ptr'
  %t6 = call ptr @__cons(ptr %t5, ptr null)
```

Both §10.3 rows, and §6.2's third, produce the first two lines at the author's
own line naming the author's own text. The old symptom still follows behind,
because U1 warns and continues; U2 is where the `die-at` replaces it.

---

## 7. U2 as built

**Two halves with two different gates, because only one of them had been
measured.**

### 7.1 Part one — the promotion

`qq-require-node-operand`'s `diag-emit "warning"` became `die-at`, note
unchanged and both call sites untouched. §5 is right that this half needed no
new measurement: U1's sweep already established that nothing in the tree reaches
that arm with a non-node operand.

### 7.2 Part two — the macro body's own value, and its own sweep

`compile-macro-body`'s body loop already called `ct-eval-require-node` on the
last body form for the C1 caller; the guard dropped its `is-arg` conjunct, so
every macro and `macrolet` body is checked too. `(compile-time …)` is *not* on
this path — it assembles its own module (§5.5 of
[macro-call-linking.md](macro-call-linking.md)) — which is what makes
`ct-body-who` safe to reuse here: at this site it can only ever say
`macro '<name>'`, never "compile-time block".

Three things the plan did not settle:

1. **The line is the body form's, not `ff`'s.** `ff` is the whole `defmacro`
   form, so blaming `(ff 'line)` would report line 1 for a body ending ten lines
   down. `(node-line (node-at ff bi) (ff 'line))` gets the form's own line and
   falls back for an interned symbol, which carries none. The C1 caller keeps
   `(ff 'line)` — its `ff` is the synthetic one-form body, whose line already
   *is* the caller's text — so C2's tested line numbers do not move.
2. **The note branches, the message does not.** §5's instruction was exactly
   right: `die-at`'s line is already generic (`ct-body-who` names either
   subject), and only the note's opening clause is caller-specific. It branches
   on `g-ct-body-arg`, the same flag `ct-body-who` keys on, so the two can never
   disagree; the computed-argument wording is byte-for-byte what C1 shipped.
3. **`node-int` is named only in `qq-require-node-operand`'s note.** The two
   notes share a tail, and naming it in the shared tail would have moved C1's
   text — which §5 explicitly ruled out. The unquote site is where `~n` with
   `n:i32` actually appears, so that is where the spelling belongs.

**The sweep: zero fires, and reach proven twice over.** Same procedure and same
478 files as §6.3, with the body-loop half warn-only.

* **0 fires.** The only 20 warnings in the whole sweep are §6.3's pre-existing
  C-header and cheader-export ones — the identical set, so the new check
  contributed none.
* **12,111 reaches across 403 of the 478 files**, by the success-warning probe
  `context/conventions.md` prescribes. This site is reached far more broadly
  than U1's: every compilation unit compiles `lib/macros.nuc`'s macro bodies, so
  the floor is 23 reaches for any file that gets past its imports at all.
* **The 75 files with zero reaches contain no macro body that was skipped.**
  Twelve of them mention `defmacro`/`macrolet`: six `src/` modules and five
  `tests/suite-*.nuc` that do not stand alone (covered by `src/nucleusc.nuc`'s
  1,822 reaches and `tests/nuctests.nuc`'s 477), plus `examples/avr-isr.nuc`,
  where the only occurrence is in a comment explaining that a top-level macro
  would not work. The remaining 63 are AVR examples and refusal fixtures with no
  macro in them.
* **Every *failing* file with a macro is accounted for.** Four fixtures
  (`w4b-defmacro-annotated`, three `w4d-*`) reach exactly 23 — the prelude
  baseline, measured against a one-line program — because each is refused before
  or without a body of its own.

**Zero, so it was promoted.** No exemption was needed or invented: the one class
worth worrying about, `macro-error` as a terminal form (it is `:void`), does not
occur in the tree.

### 7.3 What the void-collapse sharp edge became

`docs/macros.md`'s `cond`-collapses-to-void edge listed `returned null` as its
second symptom. It is now
`macro 'm' must evaluate to (raw Node), not void` at the body form's line — the
same check, reached by a different mistake, and a strictly better message.
`returned null` survives only for a body whose value is node-*typed* and null at
run time (`(let ((n (raw Node)) null) n)`, probed), which is not a type mistake
and has nothing better to say.

### 7.4 What the author sees now

```
u2-nested.nuc:3: error: the unquote operand '~n' must evaluate to (raw Node), not i32
  note: `~` substitutes its value as source, so it must evaluate to a node — what a quasiquote, `quote`, `node-int` or a ':(raw Node)' function yields

u2-splice.nuc:3: error: the unquote operand '~@n' must evaluate to (raw Node), not i32
  note: `~@` splices its value in as source, so it must evaluate to a node — what a quasiquote, `quote`, `node-int` or a ':(raw Node)' function yields

u2-noqq.nuc:1: error: macro 'm' must evaluate to (raw Node), not i32
  note: a macro body's value is substituted as source, so it must evaluate to a node — what a quasiquote, `quote` or a ':(raw Node)' function yields
```

The bare face (`` `~n ``) produces the first of these, identically — it is the
same branch, which was §1's whole claim. Nothing follows any of them: the LLVM
parse error and `returned null` are both unreachable now, which is what
`check-ct-refused`'s clean-of-LLVM assertion pins.

### 7.5 Tests and gate

Two new units in `tests/suite-refusals.nuc`, beside the Stage 20 C cluster and
using its `check-ct-refused` helper (which asserts the line, the message, the
note, exit 1, that LLVM's own text does not leak, *and* that the header modes
still succeed — they never compile a macro body):
`s20-unquote-operand-not-a-node` (nested, bare, splice) and
`s20-macro-body-not-a-node` (`(defmacro m () 5)`, plus a multi-line body that
proves the line is the body form's). `make bootstrap` byte-identical after each
half; `make test` **1042/0/0** with no expectation edited.

## 8. U3 as built

`(node-int v:i64):&Node` in `lib/node.nuc`, six lines, beside `make-cell`.

**No `line` parameter**, unlike `make-cell`: a synthesized node has no source
position, and `node-line`'s fallback to the enclosing form is exactly the
mechanism for that — `intern-node` is the precedent. `arena-alloc` zero-fills,
so `kind` and `i` are the only fields to write. An `i32` widens at the call, so
`(node-int n)` with `n:i32` — the shape U2 refuses without it — needs no cast.

**`src/` does reach `lib/node.nuc`** (`src/nucleusc.nuc:980` is
`(import-use node)`), so §3's open question resolves *yes*: the compiler's own
IR gained an 18-line `weak_odr define ptr @node-int` and `build/nucleusc.ll`
moved. The bootstrap is unaffected all the same — stage1 and stage2 compile the
same source and emit the same definition — and `make bootstrap` is byte-identical
without a boot refresh. What did need regenerating is the **committed generated
headers**: `lib/node.h` and `lib/node.nuch` are checked by
`tests/suite-audits.nuc`, which failed `STALE` until
`scripts/check-headers.sh --fix` ran. That is the real cost of adding a `defn`
to `lib/`, and it is not in §2's "no compiler change" framing.

**It is compile-time-runtime resolved, like `node-at`.** `node-int` is under the
library root *and* exported by the compiler binary, which is §3.1's conjunction
in [macro-call-linking.md](macro-call-linking.md) — so a macro body calling it
records no mirror root and cross-compiles unaffected (probed under
`--target=riscv64-unknown-linux-gnu`: clean but for the pre-existing sysroot
header warnings).

Tested by `s20-node-int` in `tests/suite-s16.nuc`: the one-liner
`` `(_* ~(node-int n) 2) `` with `n:i32` (exit 42), and the shape that wanted it
— a `~@e` producer building `(1 2 3 4)` out of computed integers (exit 10),
which is the row producer §4.6 of
[computed-macro-arguments.md](computed-macro-arguments.md) said had no clean
spelling. `make bootstrap` byte-identical; `make test` **1043/0/0**;
`abi-test`, `layout-test`, `avr-test` and `check-headers` all green
(`riscv-test` skips for the container's missing cross libc, as before).
