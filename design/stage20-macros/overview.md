# Stage 20 — macro sequence operations

**Status: designed and built 2026-09-11. M1–M6 done** (986 tests, bootstrap
converged). Every claim in §1 and every prototype in §2–§3 was run against
`build/nucleusc` as it stands on this date. §9 records the deltas building them
forced on this plan — five of them, and §9.2, §9.5 and §9.8 each correct a claim
made above by measuring it.

**Goal.** Two facilities a macro author cannot write today without copying the
same ten lines of list-walking:

* **`macmap`** — apply one template to every row of a literal table and splice
  the results in sequence.
* **`mfoldl` / `mfoldr`** — fold a template over a variadic argument list,
  left- or right-nested. The generalisation of `+ - * /` and of `and` / `or`.

**Why this is a stage and not a commit.** The headline finding is that both are
implementable as ordinary library macros with **no compiler change at all**
(§2.1, §3), which would make this an afternoon's work in `lib/macros.nuc`. What
makes it a stage is that the library form has three edges the prototype hits
immediately — a `macmap` cannot be written in top-level position (§2.2), it
cannot be written inside another macro's body (§1.4), and when it is called
wrongly it reports the error against machinery the caller never wrote (§2.5).
Each edge is a real gap in the macro system that `macmap` merely happens to be
the first thing to stand on. Shipping `macmap` without them ships a facility that
works in the examples and fails in the compiler's own best use for it.

---

## 1. Ground truth (verified 2026-09-11 against the tree)

### 1.1 What the macro system already provides

| Piece | Where | Relevance |
| --- | --- | --- |
| `defmacro`, `:rest`, `gensym` | `docs/macros.md` | The substrate. `:rest` must be second-to-last. |
| `macrolet` | `src/nucleusc.nuc:15345` (`emit-macrolet`) | Lexically scoped macros; body is a `do`. **Expression position only.** |
| quasiquote / `~` / `~@` | `src/nucleusc.nuc:2416-2464` | `~x` reads as `(unquote x)`, `~@x` as `(unquote-splice x)` — ordinary two-element cells, tagged by `qq-is-tagged`. |
| top-level macro expansion | `src/nucleusc.nuc:17077` (`toplevel-expand-macro`, Stage 18 TF-4) | A macro may stand where a definition stands; a `(do …)` expansion **splices**, each child dispatched as a top-level form of its own. |
| `(do)` with no forms | used by `lib/fmt.nuc`'s `str-into` | Legal. This is what an empty `macmap` expands to (§2.4). |

**A quasiquoted form passed as a macro argument arrives as inspectable data.**
Probed: `(probe \`(foo ~x 1))` gives the macro a `NODE-CELL` of length 2 whose
head is the symbol `quasiquote`, whose second element is `(foo (unquote x) 1)`.
Nothing about a template argument is special — it is a list with a known head.
That is what makes every design below possible.

### 1.2 The shape in the tree: a census

An s-expression-aware scan of `src/*.nuc` + `lib/*.nuc` for **runs of three or
more consecutive sibling forms with identical structure, differing only at
leaves** (script kept at `design/stage20-macros/`, reproduced in §7):

| | |
| --- | --- |
| Runs found | **296** |
| Forms covered | **1,551** |
| Runs varying at exactly 1 leaf | 68 |
| … at exactly 2 leaves | 210 |
| … at 3 or more | 18 |

That is a lower bound on `macmap`'s reach — it counts only *consecutive siblings*
and only *exact* structural matches, so a run interrupted by one comment-bearing
exception (`src/reader.nuc:936`, four uniform rows then a fifth that wraps its
result) is not counted.

The largest individual sites:

| Site | Rows | Shape |
| --- | --- | --- |
| `src/union-registry.nuc:271` | 25 | `(when (= name "…") (return (as ptr ty-…)))` — `builtin-type-name` |
| `src/repl.nuc:1773` | 55 | `(set! (st 'f) g-f)` — `repl-snapshot` |
| `src/repl.nuc:1887` | 35 | `(set! g-f (st 'f))` — `repl-restore` |
| `src/repl.nuc:1857` | 22 | `(repl-vec-truncate g-f (st 'n-f))` |
| `src/nucleusc.nuc:3559` | 16 | `(add-binop …)` — a five-column table |
| `src/nucleusc.nuc:11382` | 14 | `(add-binding-kind …)` — a seven-column table |
| `src/nucleusc.nuc:12128` | 7 | `(when (= bare "…") (return 1))` — `unsafe-op-named` |
| `src/nucleusc.nuc:18165` | 6 | `(register-rmacro v "…" "…")` |

**The REPL snapshot is the case that makes the argument.** `ReplState` declares
**55 fields**; `repl-snapshot` writes 55 `(set! (st 'f) g-f)`; `repl-restore`
writes 22 truncations and 35 restores. The same list of names is spelled out
**four times**, in two of which it must appear in reverse order. Nothing checks
that the four agree. The tree already knows this is the hazard — the comment
above `builtin-type-name` (`src/union-registry.nuc:265`) says a second copy of
its list "would drift from it", and that function exists precisely so that a
second copy is not written.

### 1.3 What a macro body may call — narrower than `context/macros-jit.md` says

`context/macros-jit.md` states that a macro body "may also call ordinary program
`defn`s … so the symbol resolves from the `-rdynamic` host binary at JIT-link
time". The examples it gives are `node-at` and `intern-symbol`. **Probed, and the
rule is not what the sentence implies:**

```lisp
(defn pname (n:(raw Node)):void …)          ; an ordinary defn in the program
(defmacro probe (t) (pname (t 'car)) `0)    ; a macro body calling it
```
```
JIT session error: Symbols not found: [ pname ]
macro 'probe': JIT lookup failed
```

A macro body may call **only what the compiler binary itself exports** — its own
`defn`s and the libraries it links (`lib/node.nuc`, `lib/intern.nuc`,
`lib/strview.nuc`, …), plus libc. `node-at` and `intern-symbol` work not because
they belong to the program but because they are in `build/nucleusc`. The program
being compiled is not linked yet, so a function it defines can never be there.

**Retired 2026-09-12 by part three**
([macro-call-linking.md](macro-call-linking.md)), which is where this defect was
found and where the rule became *provenance decides, not the linker*: a macro body
may now call the program's own `defn`s, and the first bullet below no longer binds.
The second is a standing rule and does bind. The paragraph is kept because it is
what part one was designed against.

Two consequences that shaped this stage:

* ~~**A macro body cannot call a recursive helper it defines itself**, and cannot
  recurse (a self-reference in head position is a macro *call*, i.e. expansion).
  Any tree walk a macro needs must be written iteratively, inline, in the body.~~
  Closed by part three L4: a body may call its own helpers and recurse through
  one. A self-reference in head position is still a macro call. §2.1's lowering
  still needs no walk, which is why part one did not wait for this.
* **`-rdynamic` exports all 2,280 compiler symbols**, `macroexpand-form`,
  `find-macro` and `desugar-form` among them. That is an accidental, unversioned
  API surface. `lib/macros.nuc` must not reach into it: a standard-library macro
  that calls `macroexpand-form` couples the standard library to a compiler
  internal that no gate protects. Rule for this stage: **the macros added here
  call nothing outside `lib/node.nuc`.**

This paragraph is a correction to `context/macros-jit.md` and should land there
as part of M1.

### 1.4 Quasiquote has no nesting level

Probed: inside a macro body, `` `(f `(g ~x)) `` with `x` bound to `42` builds
`(f (quasiquote (g 42)))`. The inner `~x` fired at the **outer** level.
`emit-qq-form` (`src/nucleusc.nuc:2449`) checks `qq-is-tagged form 'unquote` at
every depth with no counter, so an inner backtick is an ordinary list head and
protects nothing.

The direct consequence for this stage, probed end to end:

```lisp
(defmacro say-all (:rest parts)
  `(macmap ((p) `(printf "%s\n" ~p)) ~parts))
```
```
error: undefined: p — not defined anywhere in this compilation unit
```

**A `macmap` cannot be written inside another macro's body.** This rules out the
otherwise obvious cleanup of `lib/fmt.nuc`'s `str-into` and `lib/io.nuc`'s
`print` family, which are hand-rolled folds over `:rest` (§3.2).

There is a workaround, and it is good enough to be the recommended idiom (§2.6):
splicing a template that was *received as a parameter* is not nesting, because
the received node is never walked as source. Probed working.

### 1.5 The two production `macrolet` sites

`macrolet` is used exactly twice outside tests and examples, and **both uses are
a `macmap` written the long way** — bind a template to a name, call it N times,
never use the name again:

* `src/nucleusc.nuc:2870` — `text-token-is-definer`, the example that opened this
  document. One `true-if` template, 13 applications, split into two groups by an
  early `return`.
* `src/cheader.nuc:3890` — `emit-cheader-declare`. One `result` template, four
  applications over `(code, message)` pairs.

That is the whole evidence base for `macrolet`'s value as a *definition*
mechanism: two sites, neither of which wants a name. `macrolet` remains right for
the capturing-abstraction case it was designed for (`examples/macrolet.nuc`), but
the tree's actual demand is for the applied form.

---

## 2. `macmap`

```lisp
(macmap ((tok) `(when (!= (text-token-is text start e ~tok) 0) (return 1)))
  ("defn" "defmacro" "defvar" "defconst"))

(macmap ((res ret) `(when (= test ~res) (return ~ret)))
  (((+ 2 2) "four!") ("dammit" "curses!") (null 0)))
```

`(macmap (PARAMS TEMPLATE) (ROW …))` — bind `PARAMS` to each `ROW` in turn,
expand `TEMPLATE` once per row, splice the results in order.

### 2.1 It lowers to `macrolet`, and needs no tree walk

The implementation that matters is the one that does **not** substitute anything
itself. `macmap` rewrites to a `macrolet` binding plus one application per row,
and lets the existing macro machinery compile the template exactly as if the user
had written the `macrolet` by hand:

```lisp
(macmap ((tok) TMPL) ("a" "b"))
⇒ (macrolet ((G (tok) TMPL)) (G "a") (G "b"))        ; G from (gensym)
```

Nothing walks the template; nothing needs to know what an `unquote` is; the
template's line numbers, its diagnostics and its access to `gensym` are whatever
`macrolet` already gives. The whole macro is 12 lines:

```lisp
(defmacro macmap (spec rows)
  (let (g:ptr               (gensym)
        (params (raw Node)) (spec 'car)
        (tmpl (raw Node))   (node-at spec 1)
        nparams:i32         (node-len (spec 'car))
        calls:ptr           null
        (row (raw Node))    rows)
    (while (!= row null)
      (let ((r (raw Node)) (row 'car))
        (if (= nparams 1)
          (set! calls `(~@calls (~g ~r)))
          (set! calls `(~@calls (~g ~@r)))))
      (set! row (row 'cdr)))
    `(macrolet ((~g ~params ~tmpl)) ~@calls)))
```

**Verified working today**, against unmodified `build/nucleusc`, for both the
one-parameter and the multi-parameter form, in expression and statement position,
with `return` inside the template.

### 2.2 The one real gap: top-level position

`macmap`'s best use in this tree is generating definitions — and there the
lowering fails:

```
error: unknown top-level form: macrolet
```

`macrolet` is an expression emitter (`emit-macrolet`), reachable only from
`emit-node`. A top-level `(macrolet …)` is refused by name.

A second lowering does work at top level — a gensym'd global `defmacro` followed
by the applications, spliced through `do`, which `toplevel-expand-macro` already
dispatches child by child:

```lisp
⇒ (do (defmacro G (name val) TMPL) (G one 1) (G two 2))   ; verified working
```

But it works *only* at top level: `defmacro` inside a function body is refused
(`unknown: defmacro`). So the two positions need two different lowerings, and a
macro cannot see which position it is in. Three ways out:

| Option | Cost | Verdict |
| --- | --- | --- |
| **A.** Two spellings — `macmap` and a top-level variant | Zero compiler work; a seam the user must learn for no reason they can see | No |
| **B.** Teach the compiler that `macrolet` may stand at top level | Small: bind → dispatch each body child as a top-level form → pop. `macrolet-bind` is already factored out (`src/nucleusc.nuc:15355`), and the splicing dispatch already exists for `do` | **Yes** |
| **C.** Make `macmap` a compiler special form that substitutes directly | Best diagnostics and no gensym leak, but it is a tree walk, a new builtin, and a violation of "few builtins, many macros" | No |

**B is the decision.** It costs one arm in the top-level dispatcher, it makes
`macmap` a single library macro with one lowering for both positions, and it
lifts a refusal that was never argued for — a top-level `macrolet` is a
perfectly sensible way to write a family of related definitions, and the reason
it is refused today is that nothing had needed it.

The gensym'd binding under B is scoped to the `macmap` and disappears, which C
would also give and A's top-level lowering would not (it leaks a `__gs_N` macro
into the namespace for the rest of the file).

### 2.3 Row shape: the arity rule

A row is destructured **only when the template takes more than one parameter**:

* one parameter — the row is the argument, whole. `("defn" "defmacro")` is two
  rows of one string.
* *n* > 1 parameters — the row is a list of exactly *n* elements, spliced as the
  argument list. `((1 10) (2 20))` is two rows of two.

The alternative — always destructure, so the single-column case is written
`(("defn") ("defmacro"))` — is rejected because the single-column case is the
common one and the parentheses carry no information.

The rule has one ambiguity worth stating rather than discovering: with one
parameter, a row that is itself a list is passed **whole**, so
`(macmap ((x) \`(f ~x)) ((+ 2 2) 3))` binds `x` to `(+ 2 2)` and then to `3`. That
is the useful reading — the second of the two examples at the head of this
section relies on rows being arbitrary expressions — and it is what falls out of
the lowering with no special case.

A row whose length disagrees with the parameter count is a user error; see §2.5.

### 2.4 Edge cases

* **No rows.** `(macmap SPEC ())` expands to `(do)`, which is legal and emits
  nothing (`lib/fmt.nuc`'s `str-into` already relies on this). It must **not**
  reach the lowering — the naive version produces a `macrolet` with no body and
  reports `macrolet: expects a binding list and at least one body form`, naming
  a form the user did not write (§2.5).
* **`:rest` in the template parameters.** Falls out of `macrolet`, which parses
  its parameter list with the same code as `defmacro`. A row may then be longer
  than the fixed parameters. No work; add a test.
* **Nesting.** A `macmap` inside a `macmap` template is an inner quasiquote and
  is therefore broken (§1.4). Diagnose it rather than let it fail as
  `undefined: <param>` — see M3.

### 2.5 Diagnostics, and the gap underneath them

Every malformed `macmap` call today reports against the lowering:

| Written | Reported |
| --- | --- |
| `(macmap SPEC ())` | `macrolet: expects a binding list and at least one body form` |
| a row of the wrong length | `macro 'G': expects 2 args, got 1` — `G` is `__gs_7` |
| a `macmap` inside a template | `undefined: p` |

This is not a `macmap` problem; it is the gap `context/macros-jit.md` already
names: **a macro body cannot raise a compiler diagnostic.** `die-at` and
`report-at` live in `src/reader.nuc` and are imported only by the compiler's own
source, so no macro in `lib/` can reject its own call site. The file records this
as "a real feature, not a workaround", and this stage is where the bill comes
due — `macmap` is the first standard macro whose *shape* can be got wrong in
several distinct ways, and every one of them currently surfaces as a message
about machinery the caller never typed.

The fix is small and general: a builtin, available in any macro or `macrolet`
body, that reports at a node's line and aborts the expansion —

```lisp
(macro-error node "macmap: row 3 has 1 element, but the template takes 2")
```

It is one emitter arm over the existing `report-at`, it serves every macro
author and not just this stage, and without it `macmap` ships with a
user-visible seam. See M3.

### 2.6 Sharing one table across several templates

The REPL snapshot case (§1.2) needs the *same* 55 rows applied by four different
templates. Rows are literal, and a macro's arguments are not expanded, so
`(macmap SPEC (repl-state-fields))` cannot work — `rows` would be the unexpanded
call.

The idiom that does work, verified end to end, is to invert it: the table lives
in a wrapper macro that takes the *template* as its parameter.

```lisp
(defmacro over-repl-fields (spec)
  `(macmap ~spec ((source-path g-source-path) (src g-src) (pos g-pos) …)))

(over-repl-fields ((f g) `(set! (st '~f) ~g)))          ; in repl-snapshot
(over-repl-fields ((f g) `(set! ~g (st '~f))))          ; in repl-restore
```

This is **not** the nested-quasiquote case of §1.4: `~spec` splices a node
received as a parameter, which is never walked as source, so the template's own
unquotes survive intact. Probed working with two different templates over one
table.

Note the two columns. A one-column table cannot serve this case, because the
field is `src` and the global is `g-src` and the language has no way to paste a
prefix onto a name at expansion time. Two columns is the right answer anyway —
it is explicit, it is greppable, and it does not require inventing a name-pasting
facility whose only known caller is this one table. Name pasting is deferred
(§8).

### 2.7 What `macmap` is not for

The census (§1.2) over-counts if read naively. Several of its largest runs have
better answers already in the language, and the design should say so plainly so
that `macmap` is not adopted as a reflex:

* **`unsafe-op-named` (7 rows) and `cheader-defvar-type-ok` (5 rows)** are
  `(when (= x "lit") (return k))` chains against one subject. Those are `case`
  with `(:or …)`, or a `#{…}` set membership test — both already in the language,
  both clearer, and `case` does not cost an expansion per row.
* **`builtin-type-name` (25 rows)** is a name → value lookup. `macmap` would
  shorten the source without changing that it is a linear scan; if that function
  ever matters for speed, the answer is a table, not a macro.
* **`(emit g-out "…")` runs** (31 and 25 lines) vary only in a string constant
  and are already as short as they can be; a `macmap` over them adds a template
  and saves nothing.

`macmap` earns its place where the repeated element is a **form, not a value** —
something that `return`s, `set!`s, declares, or otherwise cannot be lifted into a
data table and looped over at run time. That is `text-token-is-definer`,
`emit-cheader-declare`, the four `repl.nuc` walks, `add-binop`, `add-binding-kind`
and `register-rmacro`: between 120 and 160 forms, not 1,551.

---

## 3. `mfoldl` / `mfoldr`

```lisp
(mfoldr op unit a b c)  ⇒  (op a (op b c))     ; () ⇒ unit,  (a) ⇒ a
(mfoldl op unit a b c)  ⇒  (op (op a b) c)
```

Both are library macros, both work today, both are about 10 lines. Verified:
`(mfoldr _+ 0 1 2 3 4)` = 10, `(mfoldl _- 0 10 1 2 3)` = 4, `(mfoldl _* 1 2 3 4)`
= 24, `(mfoldr _+ 0)` = 0, `(mfoldr _+ 0 7)` = 7.

### 3.1 Measured: rewriting the six operators over them is not a win

`lib/macros.nuc` spends **62 non-blank lines** on `+ - * /` and `and` / `or`, six
recursive `cond`s that differ only in identity element and fold direction. The
obvious cleanup is to delegate all six. An s-expression census of every
`+ - * / and or` call site in `src/`, `lib/`, `tests/` and `examples/`:

| Arity | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 10 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Sites | 2 | 8 | **2,909** | 106 | 57 | 13 | 7 | 1 |

3,103 sites; **94% are binary.** Counting expansions (a right-fold operator costs
N expansions for N arguments today, because the 1-argument base case is itself an
expansion; a left-fold one costs N−1):

| | Expansions |
| --- | --- |
| Today | **6,073** |
| All six delegate unconditionally to `mfold*` | 6,206 (**+133**) |
| Operators keep their 0/1/2-ary base cases, delegate only N ≥ 3 | 5,780 (**−293**) |

So the "flatten a deep recursive expansion" argument, which is the natural reason
to reach for a fold, **does not survive contact with the tree**: the deep case is
184 sites out of 3,103, and delegating the binary case costs more than the deep
case saves. Either way the difference is under 5% of a count that is itself
nowhere near any hot path.

**Ruling.** Rewrite the six, but keep their 0/1/2-ary base cases and delegate
only N ≥ 3 — it is the variant that is not a regression, and it still takes the
six bodies from 62 lines to about 30. Do not claim a compile-time win for it.
The gate is byte-identical output (§6): the final tree for every arity is
unchanged, so every emitted byte must be too.

### 3.2 What they are actually for

The case for `mfoldl`/`mfoldr` is the **next** variadic operator, not the six
that already exist. Today a library author who wants a variadic `max`, `bit-or`,
`str-cat` or `min` must hand-copy a ten-line recursive `cond` and get the
identity element and the fold direction right by eye. The tree already shows what
that leads to: eight hand-rolled `:rest` folds outside `lib/macros.nuc`
(`lib/fmt.nuc`'s `str-into`, `str`, `str-alloc`; `lib/io.nuc`'s `print`,
`println`, `eprint`, `eprintln`; `src/strfmt.nuc`'s `fstr`, `emit`), of which
`str-into` is a fold in exactly this sense and the rest are its callers.

`str-into` is also the clearest demonstration of §1.4's limit: it folds into a
`do` *sequence* rather than a nest, which is `macmap` over `:rest`, and it cannot
be written that way because the template would be a nested quasiquote. Until the
quasiquote gains levels (§8), the sequence fold stays hand-written and only the
nesting folds are served. Say so in the docs rather than letting an author
discover it as `undefined: p`.

### 3.3 Naming

`macmap` / `mfoldl` / `mfoldr` mixes two prefixes for one family. The tree's
convention is hyphenated words, and these are three faces of the same facility.
**Recommendation: `macmap`, `macfoldl`, `macfoldr`** — one prefix, no hyphen
inside the prefix, and `macmap` unchanged since it is the name already written
down. `mfoldl`/`mfoldr` survive as the design's working names in this document
only.

---

## 4. Decisions

1. **`macmap` is a library macro in `lib/macros.nuc`**, lowered to `macrolet`
   plus one application per row. No tree walk, no new builtin. (§2.1)
2. **The compiler gains top-level `macrolet`** — bind, dispatch each body form as
   a top-level form, pop — so one lowering serves both positions. (§2.2)
3. **Rows destructure only for multi-parameter templates.** A single-parameter
   row is the argument, whole. (§2.3)
4. **An empty row list expands to `(do)`**, handled in `macmap` before the
   lowering. (§2.4)
5. **A macro body gets `macro-error`**, so `macmap` (and every other library
   macro) can reject its own call site instead of leaking its lowering. (§2.5)
6. **A shared row table is written as a wrapper macro taking the template as a
   parameter.** Two columns where a field and a global differ in spelling; no
   name-pasting facility. (§2.6)
7. **`macfoldl`/`macfoldr` are library macros**; the six operators delegate only
   for arity ≥ 3 and keep their base cases. (§3.1)
8. **The macros added here call nothing outside `lib/node.nuc`** — no reaching
   into the compiler's `-rdynamic` surface. (§1.3)
9. **Migrate the sites, in this stage.** A facility with no caller is not
   finished; the two `macrolet` sites and the four `repl.nuc` walks are the
   proof that it works, and the `repl.nuc` one is the only one that removes an
   actual drift hazard.

---

## 5. Phases

**M1 — `macmap`, expression position.** The macro in `lib/macros.nuc`; the empty
row list; the arity rule. Migrate `text-token-is-definer` (`src/nucleusc.nuc:2866`)
and `emit-cheader-declare` (`src/cheader.nuc:3883`), the two sites that are
already this pattern written the long way. Correct `context/macros-jit.md` per
§1.3. Gate: byte-identical IR snapshot — both migrated sites must emit exactly
what the `macrolet` did.

**M2 — top-level `macrolet`.** One arm in the top-level dispatcher beside
`toplevel-expand-macro`. Unblocks `macmap` in definition position; test with a
`macmap` that generates a family of `defn`s and one that generates `defstruct`s.
Note the pre-scan limit that already applies to any macro-produced definition
(`docs/macros.md`: not forward-referenceable, cannot produce an `extend` with its
methods) — it applies here unchanged and belongs in the docs, not in a fix.

**M3 — `macro-error`.** The builtin from §2.5, over the existing `report-at`.
Then `macmap`'s own shape checks: row length vs parameter count, malformed spec,
a template that is not a quasiquote, and a nested `macmap` (§1.4) reported as
itself rather than as `undefined: <param>`. This is the phase that serves macro
authors generally; it is scheduled third because M1 and M2 are what make its
absence visible, not because it is least important.

**M4 — `macfoldl` / `macfoldr`.** The two macros; rewrite `+ - * /` and
`and` / `or` keeping their 0/1/2-ary base cases. Gate: byte-identical bootstrap
across the whole tree — with base cases kept, not one emitted byte may move.

**M5 — the `repl.nuc` migration.** `over-repl-fields` (§2.6) plus the four
walks. 55 field names spelled once instead of four times. Gate: byte-identical,
plus the REPL suite, since a dropped field is a silent state leak between
prompts and the IR snapshot would not see it.

**M6 — docs and an example.** `docs/macros.md` gains `macmap`, `macfoldl`,
`macfoldr` and the top-level `macrolet` rule; `examples/macrolet.nuc` gains a
sibling, or grows the applied form beside the named one.

M1 → M2 → M3 is the order the edges are discovered in; M4 is independent of all
three and may be done at any point; M5 needs M1 only.

---

## 6. Tests and gates

* **Byte-identical output at every phase.** Every migration in this stage is a
  source refactor whose expansion is the same tree, so the IR snapshot is the
  right gate and it is a strict one. M4 in particular: if any emitted byte moves,
  the base-case rewrite is wrong.

  *As built, this was too strong in two different ways and was tightened rather
  than waived — see §9.2 (the string table is per compilation, so the gate became
  "no instruction moves") and §9.8 (a table emits in table order, so M5's became
  "a pure permutation of the instruction multiset"). Both held. Over the 2,690-
  artifact snapshot corpus at close: 2,341 byte-identical, 342 differing only in
  string constants, one real difference — `lib/macros.nuc`'s own `.nuch`, which
  is the changed source's own header — and six new artifacts, the M6 example.*
* **One test per shape**, in `tests/suite-s16.nuc` beside the existing `macrolet`
  block (or a new `suite-s20.nuc` if the block outgrows it): one- and
  multi-parameter rows; zero, one and many rows; rows that are lists under a
  one-parameter template; `:rest` in the template; a template containing
  `return`; expression, statement and top-level position; a `macmap` inside a
  `let`, a `cond` arm and a loop body; nested `macmap` rejected with its own
  message.
* **Rejection tests for every message M3 adds**, via `check-source-rejects`,
  matching the existing `macrolet` rejection block (`tests/suite-s16.nuc:149-185`).
* **The bootstrap converges** and the compiler self-compiles, per the standing
  requirement.

## 7. Reproducing the census

The two scans behind §1.2 and §3.1 are an s-expression parser plus a sibling-run
matcher and an arity counter. They are throwaway analysis, not tooling: keep them
in `design/stage20-macros/` so the numbers can be re-derived when the tree moves,
and do not add them to the build.

## 8. Deferred, and non-goals

* **Nested quasiquote levels.** §1.4. The fix is a level counter in
  `emit-qq-form`/`emit-qq-list` and a `quasiquote`/`unquote` pairing rule, which
  is a change to the core of macro expansion with a byte-identical gate over
  every macro in the tree. It is its own piece of work, it is what would let
  `str-into` and a `macmap` inside a macro body be written, and it should be
  designed before it is attempted. **Named here because `macmap` is the first
  thing that makes its absence cost something.**
* **Name pasting** — composing `g-src` from `src` at expansion time. Deferred in
  favour of two-column tables (§2.6). Worth reconsidering only if a second table
  wants it; Rust's `concat_idents!` is unstable after a decade for reasons that
  apply here too.
* ~~**A macro body calling the program's own `defn`s** (§1.3).~~ **Shipped**, as
  part three ([macro-call-linking.md](macro-call-linking.md), phases L1-L8,
  2026-09-11/12): the program's functions *are* JIT-compiled on demand during
  compilation, into a per-flush compile-time mirror module. It was a substantial
  feature, and correctly not one `macmap` waited for — §2.1's lowering walks
  nothing. It was also a soundness bug, which is why it came back so soon.
* **`macmap` over a computed list** — rows that are not literal. The wrapper-macro
  idiom (§2.6) covers the case that motivated it; a general form would need
  `macmap` to expand its rows argument, which means reaching into
  `macroexpand-form` and violating decision 8.
* **Hygiene.** Out of scope, as everywhere else in this macro system: names in a
  template resolve at the call site, which is the point. `gensym` remains the
  tool for a template that needs a private name.
* **Retiring `macrolet`.** Not proposed. `macmap` covers the applied case;
  `macrolet` keeps the named, capturing case it was designed for.

---

## 9. As built — M1 (2026-09-11)

`macmap` is 24 lines at the end of `lib/macros.nuc`. 967 tests (the new
`s20-macmap` in `tests/suite-s16.nuc` beside the `macrolet` block), bootstrap
converged, `lib/macros.nuch` regenerated. Four deltas from the plan.

### 9.1 The binding is a fixed name, not a `gensym`

§2.1 and §2.2 both said the `macrolet` binding is gensym'd. It cannot be:
`gensym` numbers from **one global counter**, so a `gensym` in `macmap` renumbers
every `__gs_N` in every function emitted after the first `macmap` in the unit.
Measured on the first attempt — `__gs_740` became `__gs_742` and the diff ran to
53,578 lines, none of it a real change.

The binding is the fixed name `__macmap`. It is safe because the only forms
inside the body are the applications `macmap` itself builds, an inner `macrolet`
shadows an outer binding of the same name and restores it on pop
(`emit-macrolet`), and `__` is reserved. It also reads better in a diagnostic
than `__gs_7` would, which §2.5 wanted anyway.

### 9.2 The gate is "no instruction moves", not byte-identical

§6 asked for byte-identical output. **That is unattainable for any change to
`lib/macros.nuc`**, for a reason worth stating: `g-strs` is one table per
*compilation*, not per module, so every macro body's quasiquote interns its
symbol spellings into the table the **program** module emits, as constants the
program never references. A hello-world already carries 92 such dead entries from
the prelude's own macro bodies. Adding `macmap` adds three (`__macmap`, interned
once per quasiquote in its body) and renumbers every `@.str` after them.

The gate actually used, and the one M2/M4 should use: **normalise `@.str.N`
numbering and diff; nothing outside added string constants may move.** For M1
the whole IR delta is five dead constants — three `__macmap` and two `true-if`
— and not one instruction. The table itself is now a deferred item
(`design/stage888-deferred.md`).

### 9.3 `text-token-is-definer` keeps its `macrolet`

§5 listed both production `macrolet` sites as M1 migrations. Only
`emit-cheader-declare` migrated cleanly — one template, one table, zero IR delta,
since the template it replaced interned the same symbols.

`text-token-is-definer` applies **one template to two groups split by an early
return**, which is what `macrolet` is for. Two `macmap`s there would spell the
template twice, and by §9.2 a second spelling interns a second copy of all seven
of its symbols. It ends up a hybrid instead — `macrolet` names the template once,
and a `macmap` per group supplies the arguments — which is the honest reading of
the site and the concrete demonstration that **`macmap` does not subsume
`macrolet`**. The thirteen application lines still collapse to four table lines.

### 9.4 M2 — the top-level scope is closed by a spliced sentinel

§2.2 said the change was "one arm in the top-level dispatcher". It is two, and
the second is the interesting one. The dispatch loop processes **one form at a
time**, rewriting its cons cell in place and re-dispatching (that is how a `do`
expansion splices, `toplevel-expand-macro`), so a `macrolet` arm cannot bind, run
its body and pop the way `emit-macrolet` does — it returns long before the body
has been dispatched.

So `emit-toplevel-macrolet` binds, splices the body forms, and splices a
synthetic `(__macrolet-end N)` after them; a second arm pops `N` on reaching it.
Nesting falls out of the stack discipline, and the bound test is `fifty` in
`s20-macmap-toplevel` — an inner binding of the same name shadowing an outer one
— with a `(defn mk …)` after the body proving the outer scope really closed.

The alternative, recursing into a fresh dispatch loop for the body, would have
re-run the per-form root-hoist bookkeeping `emit-toplevel-forms` owns. The spine
copy the two paths share is now `toplevel-splice`.

One test died of this: `s16-macrolet-refused-toplevel` asserted
`unknown top-level form: macrolet`, which is the refusal M2 lifts. It is replaced
by `s20-macrolet-toplevel-body-is-toplevel`, which pins the rule that outlived
it — a top-level `macrolet` body is a list of *top-level* forms, so a binding
that expands to a value is as wrong there as any other non-definition.

Body definitions are invisible to the pre-scans, exactly as macro-produced ones
already are. For `macmap` that costs nothing (its body forms are all macro calls,
which a prescan could not see through anyway), so it stays a documented limit.

### 9.5 M4 — the win is the base cases, not the fold

§3.1 measured the fold rewrite as roughly neutral and concluded "the payoff is
not performance". Re-measured after building it, that is **wrong, and wrong in
the useful direction**: 6,066 macro expansions across the tree become **3,282, a
46% reduction**.

The saving is not the fold. It is the explicit 2-ary arm the rewrite made room
for. Today's right-fold operator reaches a binary call as
`(+ a b)` → `(_+ a (+ b))` → `b` — two expansions, because the 1-argument base
case is itself an expansion. Spelling out `(+ a b)` → `(_+ a b)` costs one, on
2,908 of 3,100 sites. §3.1's model had assumed the binary case stayed on the
recursive path; the census script now models it correctly.

No claim is made about wall-clock; the count is the honest number.

The gate held exactly as §9.2 defined it. Compiling the *unmodified* HEAD tree
against only the new prelude — 13 MB of IR, exercising every operator at every
arity the compiler contains — moves **not one instruction**. The whole delta is
which symbol spellings the operator macro bodies intern: `+` becomes `macfoldr`,
`and` becomes `macfoldr`/`_and`/`true`, and so on.

`macfoldl`/`macfoldr` sit at the top of `lib/macros.nuc`, before the operators
that call them, so their bodies use `cond` only — nothing defined below them is
callable from them yet, the same rule `case` records further down.

Naming went as §3.3 recommended: `macmap`, `macfoldl`, `macfoldr`.

### 9.6 M3 — `macro-error`, and the one thing still owed

`(macro-error node "message")` is a special form beside `gensym` in `emit-list`,
lowering to `call void @nucleus_macro_error(ptr, ptr, i64)` — a `defn` in
`src/nucleusc.nuc` that the macro/CT JIT module resolves from this binary exactly
as it resolves `nucleus_gensym`, and which calls `die-at`, so under the REPL it
returns to the prompt rather than ending the session.

Two decisions worth recording:

* **The message is a string literal**, not a `StrView` expression. A library
  macro has no formatting available to it anyway (`fstr` is the compiler's own),
  and a literal's data pointer and byte count are both constants at the call —
  `emit-string` with a null target hands back exactly that pair — so the emitter
  needs no by-value aggregate ABI and no target-dependent lowering of its own.
* **The guard is `in-jit-module`**, the existing predicate for "codegen is
  redirected into a macro/CT module". Outside one the form is refused rather than
  emitted as a call a program could not link. That also makes it reachable from a
  `compile-time` body, which needed the declare added at the second module
  assembly site.

`node-type` gained the lockstep arm (void — the expansion aborts, so nothing
consumes the value) and the name joined both reserved-name sets.

**Adopted after a bootstrap refresh.** `lib/macros.nuc` is read by the
*bootstrap* binary during `make`, and the committed `bin/nucleusc` predated
`macro-error`, so `macmap` could not use it until `make update-bootstrap` ran —
the same sequence as `2b3434e`, "refresh the bootstrap, drop the `case` `:or`
shim". `macmap` now raises three of its own: a spec that is not
`((param …) template)`, a row that is not a list under a multi-parameter
template, and a row whose length does not match. The third reports at *the
offending row's* line, not at the `macmap`.

**The guard order in those checks is load-bearing, and finding that out cost a
segfault.** Member access on a null `(raw Node)` dereferences — and this code
runs inside the compiler, at expansion time, so it takes the compiler down
before any diagnostic can be raised. The written-out chain

```lisp
(when (or (= spec null) (!= (spec 'kind) NODE-CELL)
          (= (spec 'cdr) null) (= ((spec 'cdr) 'car) null))
```

is safe only because `or` short-circuits and each term is reached past its own
guard; with the last two swapped, `(macmap (x) (1 2))` is exit 139. The comment
above it in `lib/macros.nuc` says so, because the ordering looks arbitrary and
is not. A malformed spec also reports against `rows` when `spec` is the empty
`()` — an empty node has no line, and a diagnostic at line 0 is what §6's
`w4a-no-line-zero` audit exists to catch.

### 9.7 Member access, not `node-at`/`node-len`

The prototypes in §2.1 and §3 were written in files with `(import-use node)`.
`lib/macros.nuc` has no such import — the prelude registers the `Node` *type* but
no node runtime — so a `lib/node.nuc` signature is not in scope at the point the
macro body is type-checked, even though the JIT'd body would resolve the symbol
at link time (§1.3). `macmap` walks with `(x 'car)` / `(x 'cdr)` and counts its
parameters with a loop, like every other macro in that file.

### 9.8 M5 — two tables, not one, and the gate §5 named cannot be met

`repl-snapshot` and `repl-restore` are one top-level `macrolet` now, binding
`over-repl-globals` and `over-repl-registries` over the two `defn`s. Four
deltas from §2.6.

**Two tables, because the two walks are not the same walk.** §2.6 wrote one
`over-repl-fields`. 32 of the fields are a global copied in and out; the other
22 are a `(count g-X)` watermark going in and a `repl-vec-truncate` coming back,
and six of those rows are not even mechanically related to their field name
(`n-macrolet`/`g-macrolet-stack`, `n-vtables`/`g-vtable-table`, `n-mono`/
`g-mono-worklist` and three more) — which is the two-column argument of §2.6
making itself again, one level down. `globals-len` is in neither: it is a field
of the `Scope` that `g-globals` points at, so no `(field global)` row can spell
it, and it stays written by hand between the two.

**The gate is not byte-identical and cannot be.** §5 asked for it. But a table
emits in *table* order, and neither original walk was in table order: the
restore spelled its 32 globals **backwards**, and hoisted the `g-generics`
truncate to the front of its 22. Both had to move. What is checkable is what
moved, so the gate became: normalise `@.str.N`, diff, and require that the
non-string delta be a **pure permutation** — same multiset of instructions,
different order. It is, exactly:

* `repl-restore`'s 110 lines, the two reorders above;
* the definition order of seven `repl_vec_truncate.*`/`remove_at.*`
  monomorphisations, because `pGeneric` is no longer the first one stamped;
* 125 added `@.str` constants and **none removed** — the field names the two
  macro bodies intern, §9.2's string table again.

`repl-snapshot` is unchanged, instruction for instruction.

**That the reorders are safe is an argument, not a measurement, so it is written
down.** Every row reads one location and writes another, and no row's source is
any other row's destination — 54 independent copies in each direction — so order
is free within each walk. Two things pinned it from outside and both still hold:
the per-generic `GenericMark` loop must run before `g-generics` is truncated
(it is above the whole `macmap`, and its comment now says *why* rather than
restating the adjacency it no longer has), and the drain cursors are clamped
after the truncates (unchanged). The restore's reversal was never a discipline
in the first place — `cheader-skipped`/`cheader-typedefs` were already in
forward order inside it, which a genuine unwind would not have been.

**A table halves the drift hazard; an audit closes it.** Adding a field to
`defstruct ReplState` and forgetting a row still compiles and still leaks that
global from one prompt into the next, and no REPL golden notices unless it
happens to name that global — the same silence the stage set out to remove,
one move further back. `scripts/check-repl-roster.py` (unit `repl-roster` in
`tests/suite-audits.nuc`, beside `cstr-residue`) parses `src/repl.nuc` and
requires that every `ReplState` field but `globals-len` be exactly one row, in
the struct's own order, and that no row name a field the struct dropped.
Verified failing in all four directions before it was wired in.

### 9.9 M6 — the example is the `repl.nuc` pattern in miniature

`examples/macmap.nuc` beside `examples/macrolet.nuc`, golden in
`tests/expected/macmap.out`. It covers the arity rule (bare rows under a
one-parameter template, lists otherwise), `:rest` with rows of differing length,
a top-level `macmap` generating a family of `defn`s, and `macfoldl` vs
`macfoldr` shown with a **non-associative** operator, since with an associative
one the two are indistinguishable by output.

The section that earns its place is §2.6's idiom: a two-field `Cursor` with a
save and a load over one `over-cursor` table. It is the smallest thing that
shows why the table is passed the *template* rather than the other way round,
and it names `src/repl.nuc` as the reason the shape exists.
