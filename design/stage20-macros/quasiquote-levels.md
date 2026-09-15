# Stage 20, part two — Quasiquote nesting levels

*Designed 2026-09-11, built 2026-09-11 (Q1–Q5; §10). Brought back from the
deferral in [deferred/overview.md](../deferred/overview.md) §"Quasiquote has no
nesting level", which asked for a design before an attempt. Part of Stage 20
rather than a stage of its own: it is the same subject — what a macro can write —
and [overview.md](overview.md) §1.4 is where the defect was found. Phases keep
their own `Q` prefix the way Stage 18's two pieces kept `R` and `TF`.*

The whole of it is **one counter threaded through three functions**, and what
makes it work rather than a patch is the gate: it changes the core of macro
expansion, and the only acceptable evidence is that it moves **zero bytes** of
the compiler's output over the whole corpus. §5 shows why that gate is attainable
here, where the rest of Stage 20's was not.

---

## 1. What is broken

`emit-qq-form` and `emit-qq-list` (`src/nucleusc.nuc:2436-2473`) ask
`qq-is-tagged form 'unquote` at **every** depth with no counter. An inner
backtick is therefore an ordinary list head that protects nothing: it is quoted
as the symbol `quasiquote` and its operand is walked at the *outer* level, so
every `~` inside it fires immediately.

Probed 2026-09-11 against `bin/nucleusc` at `ed4cec6`:

```lisp
(defmacro say-all (:rest parts)
  `(macmap ((p) `(println ~p)) ~parts))
```
```
qq2.nuc:4: error: undefined: p — not defined anywhere in this compilation unit
```

`p` is the *inner* template's parameter. The inner `~p` was resolved against
`say-all`'s bindings, where nothing named `p` exists, so the failure is not a
missing feature reported as one — it is an inner template silently evaluated at
the wrong level.

### 1.1 What it costs

**A macro cannot generate a macro body.** Every template a macro wants to emit
is a nested quasiquote, so:

* `lib/fmt.nuc`'s `str-into` and `lib/io.nuc`'s `print` family stay hand-rolled
  one-piece-at-a-time recursions. Each piece needs *wrapping* (`(to-str ~p
  ~out)`), which `~@` cannot do — it splices a rest list unchanged — so the
  natural spelling is a `macmap` over `:rest`, and that is exactly the spelling
  the missing level forbids. [overview.md](overview.md) §3.2 named these two
  as the cleanup `macmap` could not have. (**Half wrong, measured in §10.2:**
  the `print` family is four thin wrappers over `str-into`, not a fold. Only
  `str-into` recurses.)
* Any library macro that wants to expand into a `macrolet`, a `macmap`, or a
  `defmacro` with a non-trivial body is out of reach for the same reason.

What is **not** blocked, and was probed working, is a macro-generated
*definition* whose body needs no inner unquote:

```lisp
(macmap ((n) `(defmacro ~n () '(+ 1 1))) (foo bar))
(defn main ():i32 (return (+ (foo) (bar))))   ; exits 4
```

So the pre-scan already registers a macro-produced `defmacro`. The blocker is
the level counter alone, which is what makes this stage's payoff concrete rather
than speculative.

### 1.2 What already works and must keep working

[overview.md](overview.md) §2.6's idiom — pass the template **in** as a
parameter and splice it — is not nesting, because a received node is spliced,
never walked as source, so its unquotes survive. `src/repl.nuc`'s
`over-repl-globals` / `over-repl-registries` are built on it and are live
production code. Nothing in this stage touches that path: a spliced node never
reaches `emit-qq-form` at all.

---

## 2. The rule

Level 1 is the outermost quasiquote. `quasiquote` raises; `unquote` and
`unquote-splice` lower. Only a level-1 unquote is code; everything else is data.

| form, seen at level L | L = 1 | L > 1 |
| --- | --- | --- |
| `(quasiquote X)` | data: `(quasiquote X@2)` | data: `(quasiquote X@L+1)` |
| `(unquote X)`, form position | **emit X as code** | data: `(unquote X@L-1)` |
| `(unquote-splice X)`, list element | **append X's value** | data element: `(unquote-splice X@L-1)` |
| `(unquote-splice X)`, form position | `error: unquote-splice outside list` | data: `(unquote-splice X@L-1)` |
| anything else | walk unchanged | walk unchanged |

A quasiquote reached *through* an unquote is a fresh outermost one and starts at
1 again — it arrives via `emit-node`, not via the walk, so this falls out of the
structure rather than needing a rule.

`~~x` inside `` `(f `(g ~~x)) `` therefore works by construction: the outer
`unquote` at level 2 rebuilds itself as data and lowers to 1, where the inner
one fires. No special case.

**The delta at level 1 is exactly one table row.** Today a `(quasiquote X)` seen
at level 1 falls through to `emit-qq-list` and is walked as an ordinary
two-element list — the symbol, then X **at level 1**. The fix walks X at level 2
instead. Every other level-1 behaviour is untouched, character for character.
That is the gate argument of §5, and it is worth stating as the design's central
claim rather than as an implementation note.

---

## 3. The change

Four functions in `src/nucleusc.nuc`, plus one new helper. No new syntax, no new
global, no reader change, no bootstrap shim.

### 3.1 A parameter, not a global — decided

The level must be a plain `i32` parameter on `emit-qq-form` / `emit-qq-list`,
not a `g-qq-level`.

Two reasons, both structural. A global would need save/restore around the
`emit-node` re-entry at level 1, and `context/conventions.md`'s standing rule is
that **a longjmp skips every save/restore on the stack** — `die-at` inside an
unquoted expression is an ordinary occurrence, so the restore would be skipped on
exactly the path a diagnostic takes. And `src/repl.nuc:311-318` already carries
one save/restore for `g-qq-used` for related reasons; a second such global earns
a second such site in the REPL and a third place to forget it. A parameter is
reentrant for free and has no unwind story to get wrong.

### 3.2 The shape

```lisp
; Rebuild a two-element tagged form — (quasiquote X), (unquote X),
; (unquote-splice X) — as DATA, walking X at `inner` rather than at the level
; the tag was seen at. design/stage20-macros/quasiquote-levels.md §2.
(defn emit-qq-tagged (form:(raw Node) scope:&Scope inner:i32):&Val
  (set! g-qq-used 1)
  (let (fc:(raw Node) form
        tag:StrView (emit-quote-tree (fc 'car))
        val:&Val (emit-qq-form (node-at form 1) scope inner)
        t1:StrView (new-tmp))
    (emit g-body-stream "  " t1 " = call ptr @__cons(ptr " (val 'val) ", ptr null)\n")
    (let (t2:StrView (new-tmp))
      (emit g-body-stream "  " t2 " = call ptr @__cons(ptr " tag ", ptr " t1 ")\n")
      (return (alloc-val (ty-raw-node) t2)))))
```

`emit-qq-form` gains `level:i32` and three arms before its existing fall-through:

```lisp
(when (!= (qq-is-tagged form 'quasiquote) 0)
  (return (emit-qq-tagged form scope (+ level 1))))
(when (!= (qq-is-tagged form 'unquote) 0)
  (when (= level 1) (return (emit-node (node-at form 1) scope)))
  (return (emit-qq-tagged form scope (- level 1))))
(when (!= (qq-is-tagged form 'unquote-splice) 0)
  (when (= level 1) (die-at (fn 'line) "unquote-splice outside list"))
  (return (emit-qq-tagged form scope (- level 1))))
```

`emit-qq-list` gains `level:i32`, passes it down both recursions unchanged, and
guards its splice arm with `(= level 1)` — deeper, the element falls through to
`emit-qq-form`, which rebuilds it as one ordinary element. `emit-quasiquote`
passes `1`. `qq-is-tagged` is unchanged.

### 3.3 Three details that are easy to get wrong

* **`g-qq-used`.** The new path emits `@__cons` without going through
  `emit-qq-list`, and the `declare`/`define` of `__cons` is gated on that flag at
  three sites (`nucleusc.nuc:14907`, `:15205`, `:18818`). `emit-qq-tagged` sets
  it itself. `g-node-ctor-used` and `require-node-runtime` come along free, via
  `emit-quote-tree` on the tag.
* **Do not refactor the two existing `__cons` emissions** into the new helper.
  `new-tmp` order is what names `%N`, so any reordering moves bytes; the point of
  the stage is a zero-diff gate, and the minimal diff is what buys it. One extra
  `__cons` spelling is a cheap price.
* **Reconstructed cells carry line 0**, because `__cons` stores 0 where
  `make-cell` takes a line. This is already true of every cell a quasiquote
  builds, so it introduces no new class of bad location — it is recorded here so
  the next reader of a line-0 diagnostic inside doubly-generated code does not
  hunt for a regression.

---

## 4. What does not change, and why each was checked

`context/conventions.md`'s `node-type`↔`emit-node` lockstep makes "which other
site knows about this arm" a required question, so each is answered here rather
than discovered later.

* **Five prescans skip a quasiquote subtree whole** and are unaffected:
  `fn-capture-walk` (`:7460`), the closure rewrite (`:7734`), `prescan-labels`
  (`:10651`), `macroexpand-all-form` (`:11196`), and `defvar-check-init-order`
  (`:13351`). None descends, so none can observe a level.
* **`node-type`'s `quasiquote` arm returns `null`** (`src/generics.nuc:5211`) —
  deliberately unmodelled, because an unquote can inject any type. Levels do not
  change that: at level ≥2 the result is always `(raw Node)`, which is narrower
  than `null`, not wider. No edit.
* **`gcheck` and `valid-walk`** return `ty-ptr` for a quasiquote
  (`generics.nuc:2770`, `:3071`). Unchanged for the same reason.
* **The reader is already correct.** `` ` ``, `~` and `~@` are rmacros
  (`nucleusc.nuc:18254-18257`); a nested backtick already reads as a nested
  `(quasiquote …)` cell. Nothing to do.
* **No generated header moves.** `src/nucleusc.nuc` has no `.nuch` (only
  `src/llvm.nuch` does), so changing `emit-qq-form`'s signature produces no
  `make lib-headers` churn and the `headers-generated` audit is untouched.
* **No bootstrap shim.** The change adds no syntax the boot compiler cannot
  read, so `boot/nucleusc.ll` compiles the new source directly.

---

## 5. The gate

**Zero diffs, no normalisation, no allowlist**, over the full
`scripts/stage17/ir-snapshot.sh` corpus (2,690 artifacts), plus `make bootstrap`
converging and 987 tests green.

That is a stronger gate than Stage 20 could hold, and the reason is measurable
rather than hoped for. `design/stage20-macros/nested-qq-scan.py` reads
`lib/`, `src/`, `examples/`, `tests/fixtures/` and `tests/` tracking paren depth
and open-backtick depth, skipping comments, string literals and char literals:

```
scanned 471 files, 0 nested backticks
```

Nothing in the tree reaches the new arm. Combined with §2's claim that the level-1
delta is confined to `(quasiquote X)` seen inside a quasiquote, the output cannot
move — and if it does, the scan is wrong or the implementation is, which is
exactly the pair the gate should be able to tell apart.

Two contrasts worth keeping, since Stage 20's gate had to be replaced twice:

* `g-strs` is one string table per **compilation**, so Stage 20's prelude change
  interned dead `@.str` constants into every program and made byte-identity
  unattainable. This stage changes no prelude source, so it interns nothing new.
  The new arm's `intern-symbol` of `quasiquote`/`unquote` happens only in a
  program that nests, of which there are none until the tests add them.
* `src/nucleusc.nuc` is deliberately **not** a snapshot input (the script says
  so, and why). The compiler's own IR does move — a parameter is added to three
  functions — and `make bootstrap`'s fixed point covers that ground better, as
  it did for Stage 17.

Re-baselining is not available as an escape here: `snapshot --force` and a
recorded reason in `design/progress.md` are the only route, and a diff in this
stage means the semantics moved for a program that does not nest, which is the
regression the gate exists to catch.

---

## 6. Phases

### Q1 — the counter

§3, under §5's gate. The core of the stage and the only phase that touches macro
expansion. Lands with its tests (§7).

Expected size: ~25 lines changed in `src/nucleusc.nuc`, one new 12-line function.

### Q2 — the unbalanced-unquote diagnostic

`~x` with no enclosing quasiquote reports, today:

```
error: unknown: unquote — not defined anywhere in this compilation unit
```

which names an implementation detail (the rmacro's expansion) rather than the
mistake. With levels in, the message can be the mistake: *`unquote` outside a
quasiquote*. One arm in `emit-node`'s dispatch beside the existing `quasiquote`
arm, dying rather than producing a value.

Checked in advance: **no test or fixture depends on the current text** (grepped
`tests/*.nuc` and `tests/fixtures/*.nuc`). The arm produces no value, so the
`node-type` lockstep has nothing to mirror — but confirm that reading the rule
before writing the arm, not after.

Separated from Q1 on purpose: it is the one part of the stage that can legitimately
move a byte of output, and it should not be able to muddy Q1's verdict.

### Q3 — the example

`examples/qq-levels.nuc` + `tests/expected/qq-levels.out`, auto-discovered by the
goldens. What it must show, in the order a reader needs it:

1. a macro that generates a macro, and both being called;
2. `~~x` — the double unquote reaching the outer macro's binding through two
   levels;
3. the payoff shape: a `macmap` written inside a `defmacro` body — the §1 probe,
   now working;
4. `~@` at level 2 surviving as data and splicing at level 1.

### Q4 — documentation

* `docs/macros.md` — **four** claims go stale at once: the `maxn` note
  ("What does not work is a `macmap` there"), the `macmap` rule bullet ("A
  `macmap` cannot be written inside a `defmacro` or `macrolet` body"), and the
  §2.6 workaround paragraph, which stays as a *legitimate* idiom (§1.2) but loses
  its "because nesting is impossible" framing. Add the nesting rule as a table —
  §2's table is already in the right shape for a reference page.
* `context/conventions.md` — the entry that records quasiquote's flatness; plus
  anything Q1 turns up.
* `design/deferred/overview.md` — retire the item and point it here.
* `design/overview.md` — one bullet, house style.
* `design/progress.md` — the outcome, per the close protocol.

### Q5 — the payoff, separable

Rewrite `lib/fmt.nuc`'s `str-into` and `lib/io.nuc`'s `print` family as a
`macmap` over `:rest`. This is the thing the deferral was named for, and the
honest proof the feature is worth having.

**It is listed last and marked separable because it is the one phase whose gate
is not "zero diffs".** These are prelude-reachable library sources, so they are
*in* the snapshot corpus. The expansion shape changes from a right-nested
recursion (`(do A (do B C))`) to a flat sequence (`(do A B C)`); both should
lower to the same instruction sequence, but "should" is not a gate. Classify with
`normdiff.py` (kept from Stage 20) and require the delta to be empty or a pure
permutation, with the reason recorded. If it is neither, Q5 can be dropped
without touching Q1–Q4 — the feature stands on its own.

---

## 7. Tests

In `tests/suite-s16.nuc`, beside the existing 35 `macmap`/`macrolet` units:

* **`qq-nested-template`** — the §1 probe, as a `check-source-exit`: a macro
  generating a macro, both called, the program's exit status carrying the
  result. Fails on the pre-change binary, which is what makes it a test of this
  stage rather than of quasiquote in general.
* **`qq-double-unquote`** — `~~x` reaching the outer binding.
* **`qq-inner-splice`** — `~@` at level 2 as data, spliced at level 1.
* **`qq-level-one-unchanged`** — a single-level template with `~` and `~@`,
  asserting the emitted IR is what it was. Cheap, and it is the unit that fails
  loudly if the counter is threaded wrong in the common case.
* **`qq-splice-outside-list`** — `check-source-rejects`, pinning the level-1
  `unquote-splice outside list` text that Q1 must preserve.
* **`qq-unquote-outside-quasiquote`** — Q2's new diagnostic.
* **`repl`** — one `tests/repl/*.in` line exercising a nested template
  interactively, since the REPL's `g-qq-used` save/restore is the one piece of
  state this path shares with another subsystem.

---

## 8. Deferred, and non-goals

* **Hygiene.** Unchanged and out of scope. Nucleus macros are unhygienic
  everywhere and nesting does not make that worse: an inner template's names
  resolve at the inner expansion's call site, which is the same rule one level
  up.
* **Name pasting** — composing `g-src` from `src` at expansion time. Stays
  deferred (`deferred/overview.md`); two-column tables answer it and the one
  production site is `src/repl.nuc`'s roster.
* **A macro body calling the program's own `defn`s.** Stays deferred. Note that
  this stage does *not* relax it: the body of a macro that generates a macro is
  still JIT-linked against the compiler binary only.
* **`quasiquote` arity at depth.** `(quasiquote a b)` nested is not tagged
  (`qq-is-tagged` requires exactly two elements) and becomes ordinary data, where
  the top-level form is refused by `emit-quasiquote`'s arity check. Pre-existing,
  harmless, and not worth an inconsistent second check.
* **`macmap` over a computed list.** Unrelated and still deferred; nesting does
  not bring it closer.

Two pre-existing defects this work surfaced and deliberately did not fix, both
byte-identical on the pre-change binary:

* **An unquote whose operand is not `Node`-typed is not diagnosed** (§10.3), in
  **two** shapes. Nested in a list, `~5` emits `call ptr @__cons(ptr 5, …)` and
  comes back from LLVM as `integer constant must have integer type`, naming
  generated code the author never wrote. **Bare**, `` `~n `` yields
  `macro 'm': returned null` — no line, no `~`, no type — because
  `compile-macro-body`'s body loop keeps `last-val` only for a `TY-PTR`. It is a
  typing question about unquote operands, not about levels, and fixing it moves
  diagnostic text — so it wants its own gate, not this one's.
  **CLOSED 2026-09-15** by
  [unquote-operand-typing.md](unquote-operand-typing.md) U1–U3, which found a
  **third** shape §10.3 does not record (`~@` against `@__append`) and added
  `node-int` so the thing that failed has a spelling.
* **A macro cannot produce a `defmacro` at the REPL** (§10.4) — `unknown:
  defmacro`, because the REPL's top-level dispatcher does not re-dispatch a
  definer out of an expansion. Independent of nesting; the same program is fine
  in batch mode.

---

## 9. Open questions (answered in §10)

1. **Does Q5 move bytes?** §6 says classify rather than predict. The answer
   decides whether Q5 lands in this stage or becomes its own item.
2. **Should Q2's arm live in `emit-node` or in the rmacro registration?**
   Refusing at read time would give a better location but would forbid
   `(unquote x)` as a legitimate data literal in a quoted form, which today is
   legal. The `emit-node` arm is the conservative choice and is what §6 assumes;
   confirm against `'(a ~b)` before writing it.

---

## 10. As built

**The gate held exactly, twice.** `scripts/stage17/ir-snapshot.sh verify` —
`checked 2690 artifact(s)` / `PASS: emitted output is byte-identical to the
snapshot` — first for Q1 alone, then again with Q2 on top. No normalisation, no
allowlist, no re-baseline. §5's argument was the whole reason to expect it and it
is the first Stage 20 gate that did not have to be weakened.

The code is what §3 said: `emit-qq-tagged` is 12 lines, `emit-qq-form` and
`emit-qq-list` gained an `i32` and three arms between them, `emit-quasiquote`
passes `1`. Nothing in §4 needed editing — the five prescans, `node-type`,
`gcheck`/`valid-walk`, the reader and the headers were all correct as they stood.

Four deltas, three of which correct something stated higher up.

### 10.1 `~~x` is not the idiom; `~'~x` is

§2's table is right about the arithmetic and silent about the thing a user
actually trips on. **Nucleus's unquote requires its operand to evaluate to a
`Node*`**, where Common Lisp's comma inserts any datum. So CL's `,,k` — embed the
outer macro's argument in the inner template — is `~'~k` here: the outer `~k`
yields the node the caller passed, `'` makes the inner template hold it as a
literal, and the inner `~` reads it back. `~@'~xs` is the splicing counterpart,
for a `:rest` list.

A bare `~~k` lowers correctly and means something else: *evaluate `k` at the
inner expansion*, where the outer macro's parameters no longer exist. It is
well-defined and almost never what you want, which is why `examples/qq-levels.nuc`
and `docs/macros.md` both lead with `~'~`. The checkable statement of the
arithmetic is the equivalence `~~'v` ≡ `~v`, which is what `s20-qq-double-unquote`
asserts.

### 10.2 The `print` family was never a fold

§1.1 inherited "`str-into` and the `print` family stay hand-rolled folds" from
[overview.md](overview.md) §3.2, and it is half wrong. `print`, `println`,
`eprint` and `eprintln` are four-line wrappers that bind one buffer and call
`str-into`; only `str-into` recurses. **Q5 is one macro, not five**, which is why
the phase came out smaller than it was budgeted for.

### 10.3 `~<non-Node expression>` leaks an LLVM parse error

**CLOSED 2026-09-15 by [unquote-operand-typing.md](unquote-operand-typing.md)**
U1 (the check, warn-only, swept) and U2 (promoted to a located `die-at`, plus
the macro body's own value). Two corrections that section records and this one
got wrong: there are **three** manifestations, not the two tabulated below —
`emit-qq-list`'s splice arm has the same hole against `@__append`, so
`` `(_+ 0 ~@n) `` with `n:i32` was a fourth undiagnosed shape — and the
"no clean way to do the thing that fails" below is now `node-int`
(`lib/node.nuc`, U3).

Found while writing §10.1's probe, because `~~k` produces exactly this shape:

```
error: integer constant must have integer type
  %t2 = call ptr @__cons(ptr 5, ptr null)
```

`~5` — an unquote whose operand is not `Node`-typed — is not diagnosed; the
invalid `@__cons` argument reaches LLVM and comes back as an IR parse error
naming generated code the author never wrote. **Pre-existing**: byte-identical on
the pre-change binary, so it is nothing this work introduced. Not fixed here
either — it is a typing question about unquote operands, not about levels, and a
fix would move diagnostic text under a gate this stage wanted clean. Filed in §8.

**There are two manifestations, not one — the second is worse and was missed
here.** Found 2026-09-14 by
[computed-macro-arguments.md](computed-macro-arguments.md) C3, and both
reproduce byte-for-byte on the committed `bin/nucleusc`, so both predate that
work too:

| shape | what the author sees |
|---|---|
| nested in a list, `` `(_+ 0 ~n) `` | the IR parse error above — bad, but it does name a type conflict |
| **bare**, `` `~n `` as the body's value | `macro 'm': returned null` — **no line, no mention of `~`, and no type in it at all** |

The bare case is the one to fix first. Its cause is not the `@__cons` argument
but `compile-macro-body`'s body loop, which keeps `last-val` only when the
`Val`'s type is `TY-PTR`: a non-node value is dropped on the floor and the macro
silently yields null, so the diagnostic describes a symptom two steps removed
from the mistake.

C3 also records *why this became more likely to be hit*: interpolating a computed
integer is the natural way to write a producer for a spliced argument list ("emit
N of these"), which is exactly `` `~n ``. A `~e` author tends to return
quasiquoted structure; a `~@e` author is more often counting. Until this is
fixed, a row producer composes quasiquoted literals — and note `lib/node.nuc` has
`alloc-node`, `make-cell` and `intern-node` but **no integer-node constructor**,
so there is currently no clean way to do the thing that fails.

*(That last sentence is what U3 answered: `(node-int v)` is in `lib/node.nuc`
since 2026-09-15, and it is compile-time-runtime resolved like `node-at`, so a
macro body calling it needs no mirror and cross-compiles unaffected.)*

### 10.4 A macro cannot produce a `defmacro` at the REPL

Probed, and pre-existing with or without nesting: a `macmap` producing a
`defmacro` fails at the REPL with `unknown: defmacro`, because the REPL's
top-level dispatcher does not re-dispatch a definer out of an expansion. The same
program compiles and runs in batch mode, which is what §1.1's probe showed.

So `tests/repl/s20-qq-levels.in` exercises a nested template *inside a function
body* — which does work — plus a recovered error and the same call again, since
`g-qq-used`'s save/restore across the REPL's longjmp is the one piece of state
this path shares with another subsystem. Filed in §8 rather than fixed.

### 10.5 Q2's message

`unquote outside quasiquote` / `unquote-splice outside quasiquote`, from one arm
in `emit-node` beside the `quasiquote` arm. Open question 2 is settled the way §6
assumed: the arm is in `emit-node` and not in the reader, confirmed against
`'(a ~b)`, which still reads as an ordinary two-element list.

### 10.6 Q5 landed, and it makes the boot refresh load-bearing

`str-into` is two lines, down from an eight-line three-arm `cond` recursion:

```lisp
(defmacro str-into (out :rest parts)
  `(macmap ((p) `(to-str ~p ~'~out)) ~parts))
```

**The delta came out at the bar §6 set.** Over 2,696 artifacts: 2,651
byte-identical; 34 differing only in `@.str` constants (the per-compilation
string table of §5); **4 a pure permutation**, verified as an identical sorted
line multiset — `%TestCase`, its `Maybe` payload union and `%Maybe.TestCase` are
emitted after `%Diagnostic`/`%SexpStr` instead of before, in `lib/test.nuc` and
the one example that imports it; 1 real, `lib_fmt.nuc.nuch`, which is the changed
source's own generated interface; and 6 new, the example Q3 adds. **No
instruction moved anywhere.**

The permutation is the lowering, not the semantics. `macmap` leaves a `macrolet`
in the tree until emit, where the old recursion was fully macro-expanded before
the body was walked — so the walk reaches `to-str`'s parametric stamp at a
different point and the type registry emits in that order. LLVM type definitions
are order-independent, and `make bootstrap`, `make test` and `make check-headers`
agree.

**The cost the design did not name.** `lib/fmt.nuc` now *uses* a nested template,
and `src/nucleusc.nuc` uses `str-into` at 47 sites across seven modules — so the
committed `boot/nucleusc.ll` must already understand levels before Q5 can be
compiled at all. Probed: the pre-change compiler reports
`lib/fmt.nuc:200: error: undefined: p` on any program that prints. The boot
refresh therefore stops being milestone bookkeeping and becomes a **hard ordering
constraint** — Q1/Q2 land, the boot is refreshed from that compiler, and only
then may Q5 touch `lib/`. `make` cannot do this for you: `$(BIN)` depends on
`lib/*.nuc` and builds with `$(BOOT)`, so a single commit that changes both at
once is unbuildable from a stale boot, and the refresh has to be run by hand in
that order.
