# Computed macro arguments — `macmap` and friends over a value

**Status: §2.1 at width (a) selected 2026-09-14; plan in §4, phases `C1`–`C4`.**
Supersedes the "`macmap` over a computed row list" entry in
[stage888-deferred.md](../stage888-deferred.md), whose stated blocker is stale —
see §1.3.

`macmap`'s rows are literal. The question is what it would take to write

```lisp
(macmap ((name arity) `(defn ~name () ~arity)) <something computed>)
```

and the same for the `:rest` family — `macfoldr`, `macfoldl`, `+`, `case`.

---

## 1. What already works

### 1.1 `~` inside a macro body is already "evaluate now"

A macro body runs in the JIT, so an unquote in its template is ordinary code
executing at expansion time. Since
[macro-call-linking.md](macro-call-linking.md) §3.1 that code may call the
program's own functions. Both halves compose, probed 2026-09-14:

```lisp
(import-use node)
(defn three-rows ():(raw Node) (return `(1 2 3)))
(defmacro gen (tmpl) `(macmap ((x) ~tmpl) ~(three-rows)))
(defn main ():i32 (return (gen `(+ ~x 10))))
```

Exits **13**. The row list is computed by a program `defn` and spliced into the
`macmap` as literal rows. **No compiler change was involved.** The template is
passed in as a parameter because a nested quasiquote would not protect it (§1.4
of [overview.md](overview.md)); that is the pre-existing workaround, not a new
cost.

So "computed rows" is already reachable. What it costs is a wrapper macro per
site, and the wrapper cannot itself be written at top level inside another macro
without the same §1.4 dance.

### 1.2 At source level the same spelling is an error

```
$ cat u1.nuc
(defn main ():i32 (return ~(+ 1 2)))
$ nucleusc u1.nuc -o u1
u1.nuc:1: error: unquote outside quasiquote
```

Raised at `src/nucleusc.nuc:12246`. The spelling is therefore **free**: there is
no existing meaning to displace, and any feature put here lights up exactly the
programs that are diagnostics today. That is the cheapest possible
backward-compatibility story.

A `~`-wrapped **macro argument** already arrives inspectable — a macro that
checks `(x 'kind)` sees `NODE-CELL` and can read the `(unquote 41)` payload
(probed, exit 42). So the marker survives the reader and reaches macro bodies
intact. Only the evaluation is missing.

### 1.3 The recorded blocker is stale

[stage888-deferred.md](../stage888-deferred.md) says a general form "would need
`macmap` to expand its own rows argument, which means calling `macroexpand-form`
from `lib/macros.nuc`" and violating the rule against `lib/` reaching into the
compiler's exported surface. That framing assumed *expansion* is the only route.
§1.1 shows *evaluation* is another, it is already legal, and it reaches no
compiler internals. The entry should be rewritten the way "Name pasting" was.

---

## 2. The options

### 2.1 Preferred — `~expr` marks an argument for compile-time evaluation

```lisp
(macmap ((name arity) `(defn ~name () ~arity)) ~(build-rows))
```

`~e` already reads as `(unquote e)`. At source level, instead of raising, the
compiler compiles `e` into the compile-time JIT, runs it, and substitutes the
`(raw Node)` it returns.

**Why this is the right one:**

* It is **one rule, not two**. `~` means "evaluate now" inside a macro body
  today (§1.1); this makes it mean the same thing one level out. Nothing new to
  teach — the inconsistency is what needs teaching now.
* The spelling is **free** (§1.2), so there is no migration and no ambiguity.
* It serves **"and friends" without touching any of them.** Done on macro
  arguments generally, `macfoldr`, `case` and the variadic operators gain the
  same capability with no per-macro change.
* Most of the machinery **exists**. Compiling an arbitrary body into the CT JIT
  and running it is `compile-time`'s `@__compile_time_main_N`; taking a `ptr`
  back and splicing it as source is `emit-macro-expand`. The new part is the
  glue and the policy, not the mechanism.
* Its three hard edges are **already solved** by the stage just landed: a
  reference to something defined below is L5's located refusal, a flush under
  cross-compilation is L8's, and re-entrancy is the nested flush L6 found and
  handled.

**The `:rest` family needs `~@` as well as `~`.** `macmap`'s rows are one
argument, so `~` suffices. `macfoldr`/`+`/`case` take `:rest`, so a computed list
must become *N arguments*, which is `~@e` — also read already, also an error
outside a quasiquote today, same treatment. Without it the option covers
`macmap` and not its friends.

**The sub-decision, which is where the real design work is.** Three widths, each
a superset of the last:

| | Where `~e` is evaluated | `macmap` changes | Notes |
|---|---|---|---|
| **(a)** | macro-argument position only | none | Narrowest that meets the ask. Costs a macro the ability to *inspect* a `~` argument — an undocumented accident (§1.2), not a feature in use. |
| **(b)** | a `ct-eval` builtin a macro body calls | ~3 lines, opt-in | Per-macro control over *whether* to evaluate; hands `lib/` an eval, which is the API-surface question [macro-call-linking.md](macro-call-linking.md) §10 already defers. |
| **(c)** | anywhere a form is emitted | none | Common Lisp's `#.`. Coherent, widest, most semantic surface to get right (expression vs top-level position, whether a non-`Node` result lifts to a literal). |

(a) is forward-compatible with (c): widening later breaks nothing, because
everything (c) adds is an error today. Recommend **starting at (a)**, and minting
(b) only if a macro turns up that must decide for itself.

### 2.2 Acceptable — quote the literal, evaluate by default

```lisp
(macmap SPEC '((a 1) (b 2)))     ; literal
(macmap SPEC (build-rows))       ; computed
```

**Dominated — it costs more than §2.1 and delivers less.**

* It needs the **same evaluation machinery**. Nothing is saved.
* It is **ambiguous, silently.** A one-parameter template takes each row whole,
  so a row may be any expression (`lib/macros.nuc:417`). `(macmap ((x) T) (foo))`
  means "one row, `foo`" today; under evaluate-by-default it means "call `foo`".
  Both readings compile. The `~` marker in §2.1 exists precisely to settle this,
  which is why your instinct to reach for it is right.
* It costs a **migration**: 33 call sites (5 `src/`, 4 `lib/`, 24
  `tests/`+`examples/`). The `lib/` edits renumber the string table, so the
  committed boot IR needs a refresh — recoverable, but it is work bought for
  nothing.

### 2.3 Last resort — a symbol evaluates, a list does not

**Do not build this.** The `let` idiom it implies does not exist: a runtime `let`
binding cannot be read at expansion time, so `(let ((rows …)) (macmap SPEC rows))`
could never work as written. The nearest real thing is a program **global**,
readable from a macro body since L6 — but only when named statically. For
`macmap` to read a global whose name it learns at expansion time it would need
dynamic lookup by mangled IR name (`LLVMOrcLLJITLookup`, already wired), which is
buildable and strictly less general than §2.1.

It is also ambiguous in the other direction: a bare symbol is a legal
one-parameter row.

### 2.4 The baseline — do nothing

§1.1's wrapper macro, which works today. Any feature has to beat *this*, not
beat "impossible". It costs one adapter macro per site and inherits §1.4's
nesting restriction. That is a real cost but a small one, and it is the honest
reason this can stay deferred if the tree has no second site that wants it.

### 2.5 Also considered — a supported `macroexpand` builtin

The deferral's own suggestion, made legitimate by minting a *named* API rather
than reaching into the accidental `-rdynamic` surface. Cheaper than an evaluator,
but it forces every row producer to be a macro rather than a function, and "macro
expand this argument" does not read as "evaluate this argument". Worse fit for
the same money.

---

## 3. Recommendation

**§2.1 at width (a), with `~@` alongside `~`.** One rule, a free spelling, no
migration, every `:rest` macro served at once, and its three sharp edges already
have refusals built and tested.

Before committing to it, two things are worth knowing and neither is expensive:

1. **Is there a second site?** §2.4 is a real answer while `macmap`'s computed
   rows want exactly one wrapper. [overview.md](overview.md) §1.5 found the
   `macrolet` evidence base was two sites; the same count should decide here.
2. **What may `e` return?** `(raw Node)` only is the honest start. Lifting an
   `i32` or a string literal to a node is convenience that can follow, and
   deciding it early is how (a) accidentally becomes (c).

---

## 4. The plan

### 4.1 The shape of the change

Two functions carry it, and both already exist.

**`expand-macro-call` (`src/nucleusc.nuc:11304`) is the one chokepoint.** It is
where a macro call's arguments are collected — the fixed params by `node-at`,
then the `:rest` list built in reverse by `make-cell` — and it already owns the
arity diagnostics and the `ct-mirror-flush` that precedes the lookup. A
substitution pass at the **top** of it, before the arity checks, is the whole
integration: rewrite the call's argument list, then let the existing body run
against the rewritten call unchanged. Before the arity checks because `~@e`
changes the count, and the "expects N args, got M" message must count what the
macro will actually receive.

**`compile-macro-body` (`src/nucleusc.nuc:15858`) is the evaluator.** Given a
`MacroDef`, a jit-name and a parameter list it compiles a body into a fresh CT
module with its own `g-macro-decls`, `g-ct-module-defns` and `g-ct-roots`. So:

> **A `~e` argument is compiled exactly like an anonymous, zero-parameter macro
> body.** Synthesize a `MacroDef` with `pcount` 0, hand `e` to
> `compile-macro-body`, flush its roots, look the symbol up, call it through
> `unsafe/funcall-ptr-1` with a null argument array, and substitute the `(raw
> Node)` it returns.

That reuse is why width (a) is cheap and why it is the width to pick: the mirror,
the closure walk, `--warn-ct-shadow`, and all three refusals — L5's forward
reference, L6's nested flush, L8's cross-target — are inherited rather than
rebuilt, because this *is* the macro-body path with a different caller.

### 4.2 What stays an error

The `unquote`/`unquote-splice` arm at `src/nucleusc.nuc:12246` stays exactly as
it is. It is reached only with no enclosing quasiquote to consume the form, and
after this change it is additionally not reached for a macro argument, because
the substitution consumed it first. Everywhere else — a function call's argument,
a `defn` body, top level — `~e` remains `unquote outside quasiquote`. That
boundary is the narrow option; widening it later is §2.1's table and is not this
stage.

### 4.3 Phases

**C1 — the evaluator, called from nowhere.** `ct-eval-node (e, line, who) :ptr`
plus a `g-ct-eval-id` counter for unique jit-names, on the L3 pattern of landing
the mechanism dead first. *Gate:* `make`, `make bootstrap` byte-identical (it is
unreachable, so it must be), mirror counter 0.

**C2 — `~e`, the single substitution.** The pass at the top of
`expand-macro-call`; an argument that is a two-element cell headed by `unquote`
is replaced by its evaluation. Both diagnostics land here: a body that does not
yield `(raw Node)`, and the refusal channel already spoken by
`ct-mirror-report-refusal` (it takes a `who` — pass something that names the
argument, not the macro, since the fault is in the caller's text).
*Gate:* `(macmap SPEC ~(build-rows))` works end to end; `make bootstrap`
byte-identical, since nothing in the tree spells `~` at source level.

**C3 — `~@e`, the splice.** Evaluate, require null or a `NODE-CELL` list, splice
its elements as N arguments. This is what serves the `:rest` family —
`macfoldr`, `macfoldl`, `+`, `case` — and without it the stage covers `macmap`
alone. *Gate:* `(macfoldr + 0 ~@(nums))` folds over a computed list; arity
diagnostics count post-splice.

**C4 — documentation and the stale deferral.** `docs/macros.md` gains the
feature and its boundary (§4.2); `context/macros-jit.md` gains a bullet;
[stage888-deferred.md](../stage888-deferred.md)'s "`macmap` over a computed row
list" is rewritten the way "Name pasting" was, since §1.3 shows its recorded
blocker is not the real one; `design/progress.md` and
[overview.md](../overview.md) record what was built.

### 4.4 Questions the phases must answer rather than assume

* **Does the type check exist to be written?** A quasiquote whose operand is not
  `Node`-typed is an undiagnosed pre-existing hole — `~5` reaches LLVM as
  `integer constant must have integer type`, naming generated code
  ([quasiquote-levels.md](quasiquote-levels.md) §10). C2 must not inherit that.
  Whether the check belongs on the emitted value's type in `ct-eval-node` or on
  `compile-macro-body`'s return path is C2's to determine.
* **The REPL.** `ct-mirror-flush` returns 1 immediately when `g-interactive` is
  set, because the REPL reaches the same end by JIT-compiling every top-level
  form. Whether `~e` therefore works at the REPL, or needs its own gate, is a
  probe — not an assumption. It must at minimum not crash.
* **Is `macrolet` on this path?** Both `defmacro` (`:15848`) and `macrolet`
  (`:16129`) compile through `compile-macro-body`, so a `macrolet`-bound macro
  should get `~e` for free. Confirm rather than assert.
* **Does the substitution need to recurse?** No, by decision: `~e` is recognised
  at the top level of an argument only. A `~` nested inside an argument's
  subforms stays an error. That keeps the rule statable in one sentence and is
  the narrow option's whole point.

### 4.5 As built — C1/C2 (2026-09-14), and four corrections to §4

**Done, both phases, 1034 tests.** `ct-subst-args` (`src/nucleusc.nuc:11358`) at
the top of `expand-macro-call`; `ct-eval-node` (`:16159`) synthesizing a
zero-parameter `MacroDef`; `compile-macro-body` gains an `is-arg` flag (`:15949`)
that carries the type check and the diagnostic subject. The reuse thesis held:
the mirror, the closure walk, the warning and all three refusals came along
without new code. Verified independently — `~(rows)` where `rows` calls `pick`
carries **both** through the mirror, exit 30.

Four things §4 got wrong:

1. **§4.4 overstates what C2 can do about the type hole.** "C2 must not inherit
   that" reads as though C2 might *close* the quasiquote hole. It cannot,
   cheaply or safely: that hole is at `emit-qq-form`'s level-1 unquote, on the
   path every macro in the tree uses, and it is a filed deferral owned by
   [quasiquote-levels.md](quasiquote-levels.md) §10.3. C2's check is a **second,
   independent** check on a new path. `~5` as a computed argument is now
   `the computed argument '~5' must evaluate to (raw Node), not i32`; `~5`
   *inside a quasiquote* is still LLVM's `'%t1' defined with type 'i32' but
   expected 'ptr'`. C4 must not record the hole as closed.

2. **§4.1's "rewrite the call's argument list" hides a real choice.** A generic
   body is re-emitted per stamp, so the *same* macro-call node reaches
   `expand-macro-call` more than once. Mutating in place would evaluate once and
   reuse; rebuilding (only when a `~` is present, which is what shipped)
   re-evaluates per stamp. Both are defensible; the document does not notice the
   question exists.

3. **§4.1 and §4.3 omit `push-function-state`.** A macro argument is substituted
   during `emit-node` of a function body, so `ct-eval-node` is a *mid-function*
   caller of `compile-macro-body`, and without the `push`/`pop` bracket the
   enclosing function's entry and body streams are reset under it.
   `macrolet-bind` is the precedent and `compile-macro-body`'s own comment names
   the requirement; the plan cites neither. The `macrolet` test is what proves
   the bracket load-bearing, because that unit is mid-function.

4. **§1.1 and §1.2's probe invocations were mis-spelled** — `(import node)` is
   `(import-use node)`, and there is no `-e` flag. Both *claims* reproduce once
   spelled correctly (exit 13; `unquote outside quasiquote`). Corrected above.

### 4.6 As built — C3 (2026-09-14)

**Done, 1040 tests.** `ct-subst-args` (`:11380`) recognises `unquote-splice`
beside `unquote`; the rebuild normalises each input cell to *the list of elements
it contributes* — one cell normally, the evaluated list for `~@e` — which is what
makes an empty splice contribute **zero** arguments rather than one null one.
`ct-eval-require-list` (`:1563`) is new; `ct-eval-node` and
`ct-eval-arg-spelling` gained a `splice` flag. Verified independently: a splice
into `macfoldr` and into a user `:rest` macro in one file exits 14, a dotted tail
is refused, and an empty splice makes a fixed-arity macro report "got 1".

Three corrections and one checked negative:

1. **§4.3's C3 gate was under-specified in a way that loses data.** "Require null
   or a `NODE-CELL` list" describes a test on the *head*, which admits `(1 . 2)`
   and silently drops the tail. The requirement is a **proper** list, which means
   walking it — one loop covers both the atom result and the dotted tail with one
   message.
2. **C1/C2 left `ct-eval-arg-spelling` hardcoding `"~"`.** Correct while `~` was
   the only marker, and the one place C2's code was wrong *for* C3: every
   diagnostic would have quoted the author's `~@(nums)` back at them as
   `~(nums)`. A computed argument's fault is in the caller's text, so the text
   must be echoed as written.
3. **The `~n` hole has two manifestations**, and the bare one is worse — see
   [quasiquote-levels.md](quasiquote-levels.md) §10.3, now corrected there.
4. **Checked negative:** `~e`/`~@e` evaluate **once per source site**, not once
   per `expand-macro-call` — probed in return position, in a `let` initializer,
   and through overload resolution, which consults `node-type`. §4.5's correction
   2 predicted a re-evaluation per stamp; in these three shapes there isn't one.

**A usability edge worth recording, found while verifying.** `lib/node.nuc`
offers `alloc-node`, `make-cell` and `intern-node` but **no integer-node
constructor**, and the obvious way to build a row list from computed numbers —
`` `(~n) `` with `n:i32` — lands squarely on the §10.3 hole. So a row producer
composes quasiquoted literals today rather than interpolating computed integers.
That is a documentation matter for C4, not a blocker, but it is the first thing
someone writing a real row producer will hit.
