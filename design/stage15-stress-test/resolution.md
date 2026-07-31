# W1 — Whole-unit signature resolution

**Findings:** §2.1 (order-dependent registration), §2.2 (a direct import can be
actively wrong), §2.3 (`declare` is not a forward prototype), §2.4 (mutual
imports).

**Goal:** make cross-file function references resolve on **reachability**, not on
import order. A `defn` in any file of the compilation unit should be callable
from any other file in that unit, with no constraint on the shape of the import
graph and no load-bearing import ordering.

---

## Ground truth — how resolution works today

Read these before changing anything. Line numbers are as of this doc's writing;
confirm them.

### The single-pass structure

`src/nucleusc.nuc:9246` `emit-toplevel-forms` is the whole story:

```lisp
(defn emit-toplevel-forms (forms:(raw Node)):void
  (set! g-toplevel-depth (+ g-toplevel-depth 1))
  (set! forms (apply-leading-ns forms))         ; ns BEFORE prescans — see below
  (apply-early-set-ir-prefix forms)
  (when (= g-toplevel-depth 1)
    (prescan-imported-types forms))             ; types only, whole graph
  (prescan-struct-names forms)                  ; THIS FILE only
  (prescan-protocols forms)                     ; THIS FILE only
  (prescan-defn-signatures forms)               ; THIS FILE only
  … then walk forms in order, recursing into each `import` …
```

So a file's `defn` signatures enter the global scope when that file *starts*
being processed, and stay. The resulting rule is purely ordinal:

> **X may reference a function in Y ⟺ Y begins processing before X is emitted.**

Every symptom the port recorded across five phases is a corollary. Do not
re-derive them; the two that matter for design are:

* Two sibling importers of a shared middle file fail in **either** order, because
  the first expands it before the second's prescan has run.
* A file reachable by two routes is processed by whichever route runs first,
  which is what makes import *order* load-bearing and makes an innocent
  alphabetization a build break.

### The precedent that makes this tractable

`src/nucleusc.nuc:8884` `prescan-imported-types` **already does the whole-graph
walk we need**, for types:

* Walks the import tree depth-first from the outermost unit's forms.
* Dedups on resolved path via `g-prescan-visited` / `import-list-has`.
* Saves and restores `g-src` / `g-pos` / `g-line` / `g-source-path` / `g-peek` /
  `g-peek-valid` around each file read.
* Reads, `desugar`s, then calls `prescan-imported-types` + `prescan-struct-names`
  recursively.
* **Skips C-string imports** (`"stdio.h"`) — reading one would invoke clang.
* Registration is idempotent, so the real import later is unaffected.

**W1 is, in the first instance, extending that walk to also register protocols
and defn signatures.** That is the cheap 80%. The rest of this doc is the parts
that are not that easy.

### Import emission already dedups and detects cycles

`src/nucleusc.nuc:9606` `do-import`:

* `g-imported` records loaded paths; with `prefix == null` an already-loaded file
  returns early.
* `g-importing` is the in-progress set, and a re-entry dies **`import: circular
  import of '%s'`** — a real diagnostic, not a `duplicate method signature`.
* `g-import-aliased` / `g-import-prefixes` handle prefix-level dedup and reject
  two different files sharing a prefix.
* It saves/restores `g-current-ns` and `g-ns-seen` in addition to the reader
  globals.

**Note a discrepancy with the findings.** §2.4 reports mutual imports failing
with `duplicate method signature for overloaded '<name>'`. The compiler has an
explicit `circular import` path. Either the port hit a different route (bare
`(import foo)` goes through `emit-import-prefixed`, which computes a *default*
prefix from the library name — so `prefix` is **not** null and the
already-loaded early-return does not fire; it takes the aliasing path instead),
or the behaviour has changed. **Verify before designing** — see §3 of
[prompt.md](prompt.md).

> **Status: probed 2026-07-25 (after W4 landed). §2.4 is wrong; the
> default-prefix theory above is disproven for this shape.**
>
> Two-file mutual-import probe, bare `(import …)` in both files:
>
> ```lisp
> ; af.nuc
> (import bf)
> (defn a-fn (n:i32):i32 (if (= n 0) (return 1) (return (b-fn (- n 1)))))
> ; bf.nuc
> (import af)
> (defn b-fn (n:i32):i32 (if (= n 0) (return 2) (return (a-fn (- n 1)))))
> ; m.nuc
> (import af)
> (defn main ():i32 (return (a-fn 3)))
> ```
>
> → `bf.nuc:1: error: import: circular import of 'af'`
>
> So a bare mutual import takes the **`g-importing` circular path**, not the
> aliasing path, and reports at a real line (line 0 here was fixed by W4a). There
> is no `duplicate method signature` to chase and nothing to repair in
> `emit-import-prefixed` — the "fix *that* to give the `circular import`
> diagnostic instead" clause of W1d below is **moot**.
>
> **Path-form follow-up, probed 2026-07-31.** The paragraph above flagged the
> other spellings as untested. The **path form** is now tested and behaves
> identically: with `(import "<abs>/sx.nuc")` and `(import "<abs>/sy.nuc")` in the
> two files, the result is
> `sy.nuc:1: error: import: circular import of '<abs>/sx.nuc'`. Both the bare and
> path spellings reach the same `g-importing` guard, so neither is the route to
> §2.4's reported error. **`import-prefixed` remains unprobed** — probe it only if
> W1d's decision actually turns on it.

---

## Design

### W1a — extend the whole-graph prescan to signatures

Add protocol and defn-signature registration to the existing depth-first import
walk, so that after the prescan phase every reachable file's signatures are in
the global scope before any file is emitted.

Shape (do not treat as final code — the point is the ordering):

```
prescan-imported-units(forms):
  for each import form in forms:
    path = resolve-import(...)
    if C-header path: skip
    if visited(path): skip
    mark visited
    save reader+ns globals
      read + desugar file
      apply that file's own leading (ns …)      ; ← see W1b
      prescan-imported-units(inner-forms)       ; depth-first
      prescan-struct-names(inner-forms)
      prescan-protocols(inner-forms)
      prescan-defn-signatures(inner-forms)
    restore
```

The existing `prescan-imported-types` becomes this function, or delegates to it.
Keep the C-header skip. Keep idempotence: every register path this touches must
tolerate being called twice for the same definition, because
`prescan-defn-signatures` runs again when the file is really emitted.

**The idempotence question is the crux of W1a.** `generic-register-method`
(reached from `prescan-defn-signatures` at `src/nucleusc.nuc:9020`) is what
raises `duplicate method signature for overloaded '<name>'` — and §2.5/§2.6
confirm registration is by name+arity across the whole unit. Re-registering a
file's own signature must be a no-op, not a duplicate. Establish which of these
is true before writing the walk:

1. It is already idempotent (registration keyed on name+arity+same-defn-node).
2. It is idempotent only if the second registration is byte-identical.
3. It is not idempotent at all.

If (3), the fix is a `g-prescanned-signatures` guard (skip
`prescan-defn-signatures` for a path already signature-prescanned) rather than
loosening the duplicate check — **the duplicate check is load-bearing and must
keep rejecting genuine collisions** (two different files defining the same
name+arity, per §2.6). Do not weaken it into a silent last-wins.

### W1b — namespace correctness during the walk

`apply-leading-ns` runs *before* the prescans in `emit-toplevel-forms`
specifically so global keys and forward references are qualified consistently
(the comment says so). A whole-graph prescan must therefore apply **each visited
file's own** leading `(ns …)` while prescanning that file, and restore
afterwards — `do-import` already models the save/restore
(`g-current-ns` / `g-ns-seen`).

The current `prescan-imported-types` does **not** do this. That is latent today
because it only registers struct *names*; it stops being safe the moment defn
signatures (which are namespace-qualified) are registered the same way. Treat
this as part of W1a, not a follow-up.

Also confirm `finalize-generics` — called at the end of
`prescan-defn-signatures` — is safe to call once per visited file. See
`src/nuch.nuc:146-159`, which comments on exactly this ordering for the `.nuch`
path and is the closest existing precedent. If it is not safe per-file, split
`prescan-defn-signatures` into "register" and "finalize" halves and call finalize
once after the whole walk.

### W1c — retire the ordering requirement from the diagnostic surface

Once W1a lands, an `unknown: <name>` for a function that genuinely exists
somewhere in the unit should be impossible. The remaining `unknown:` cases are
real typos and genuinely-absent symbols.

Improve that error to say which it is: if the name resolves in *no* reachable
file, say so plainly; if it resolves in a file that is **not** reachable from the
entry point (§2.7's reachability constraint, which W1 does not remove), say
*that* — "`y-later` is defined in `yf.nuc`, which no import reaches from this
unit" is a far better error than `unknown: y-later`. This is the one piece of W1
that is user-visible polish rather than mechanism, and it composes with W4.

### W1d — mutual imports

With signatures registered graph-wide, a genuine mutual `(import)` pair no longer
*needs* double processing to resolve. Decide, and record the decision:

* **Option 1 (recommended):** keep `circular import` a hard error, but only for
  cycles that would require re-*emitting* a file. With W1a in place the common
  reason people reach for a cycle (mutual function references) no longer needs
  one, so the error becomes correct advice rather than an obstacle — provided the
  message says "you no longer need a cycle for mutual references; remove the
  back-import". Cheapest, and keeps emission single-pass.
* **Option 2:** allow cycles by making emission idempotent per path (emit each
  file at most once, at first reach). More permissive, more risk: it changes
  emission order and therefore the bootstrap IR.

Option 1 unless verification in §3 shows real code needs Option 2. If the port's
reported `duplicate method signature` turns out to be reachable via the
default-prefix aliasing path described above, fix *that* to give the
`circular import` diagnostic instead — a wrong error message for a real
situation.

> **Status: the §3 probe is done (2026-07-25) — see the Status box under "Import
> emission already dedups". The `duplicate method signature` clause is moot: a
> bare mutual import already gives `circular import` at a real line.**
>
> But the probe also sharpens the Option 1 / Option 2 choice, and not in Option
> 1's favour. Option 1's advice — *"remove the back-import"* — tells the author of
> a mutually recursive pair to write a file that calls `a-fn` without importing
> `af`. That is exactly the pattern §2.1 exists to complain about, and the one the
> three-file repro turns out to be entirely about. **Under Option 1, W1a would
> make the sloppy spelling work rather than making the clean spelling possible.**
>
> So decide W1d against this question, not against the old framing: *after W1a,
> what is the recommended spelling for two mutually recursive files?* If the
> answer is "each imports the other" the choice is Option 2 and the emission-order
> risk to the bootstrap must be faced. If it is "neither imports the other, both
> are imported by a parent" then Option 1 is fine but the `circular import`
> message must say so positively, and `docs/` must state that a cross-file
> reference does not require an import — which is a real language rule, not just a
> diagnostic tweak.

### W1e — `declare` as a forward prototype (§2.3)

`(declare f (...):T)` plus a real `(defn f (...):T ...)` in the same unit dies
`invalid redefinition of function 'f'`. With W1a, the C idiom this exists to
support (`r_bsp.c`'s local prototype for `R_StoreWallRange`) is no longer needed
for cross-file references — which is the *entire* reason the port wanted it.

**So W1e is likely unnecessary, and that is the finding.** Confirm it: after W1a,
is there any remaining case where a user needs to forward-declare a Nucleus
function? If not, record in this doc that §2.3 is resolved-by-obsolescence and do
**not** build a forward-declaration mechanism. If there is a case (mutual
*recursion* through a function pointer table, perhaps), scope it separately —
do not fold it into W1.

> **Status: probed 2026-07-25. §2.3 does not reproduce, and `declare` is already
> the working answer for mutual recursion. Do not build a forward-declaration
> mechanism.**
>
> Three shapes measured:
>
> 1. **`declare` + `defn` of the same function, same file** — `(declare f
>    (i32):i32)` then `(defn f (n:i32):i32 …)` then a call: **compiles and runs
>    correctly.** No `invalid redefinition`. §2.3's headline claim does not
>    reproduce in the obvious shape; either it needs a narrower spelling than the
>    finding records, or it has been fixed since.
> 2. **`declare` as a cycle-breaker across files** — replacing `bf.nuc`'s
>    `(import af)` with `(declare a-fn (i32):i32)` makes the mutually recursive
>    pair **compile and run correctly** (`a-fn`→`b-fn`→`a-fn`→`b-fn`, returns 2).
>    So mutual recursion across files *is* expressible today; the acyclic-import
>    constraint is worked around by declaring rather than importing.
> 3. **`declare` *and* an import of the definer** — a file that both
>    `(declare a-fn …)` and (transitively) imports the file defining `a-fn` dies
>    `af.nuc:2: error: duplicate method signature for overloaded 'a-fn'`.
>
> **Shape 3 is where the findings' `duplicate method signature` actually comes
> from** — §2.4 attributes it to mutual imports, but a bare mutual import gives
> `circular import` (Status box under "Import emission already dedups"). The
> message is real, the attributed cause is not. A port file carrying both a
> `declare` and an import of the definer would produce exactly this.
>
> **This is a direct hazard for W1a, and it is not written down anywhere else.**
> Once the whole-graph prescan registers every reachable file's signatures,
> *every* `declare` whose definition is reachable becomes shape 3 unless the
> prescan distinguishes a `declare` from a `defn`. Since `declare` is currently
> the only spelling for cross-file mutual recursion (shape 2), W1a would break the
> one working workaround while claiming to remove the need for it. Requirement:
> a `declare` matching a reachable `defn` of the same name+arity must be a
> compatible-prototype check, **not** a duplicate — while two `defn`s still
> collide (landmine 3 in [prompt.md](prompt.md) §5, which stays intact).

---

## Verified repro (as of this doc)

Three files, `build/nucleusc -I lib z.nuc`:

```lisp
; xf.nuc
(defn x-uses ():i32 (return (y-later)))
; yf.nuc
(defn y-later ():i32 (return 7))
; z.nuc
(import xf)
(import yf)
(defn main ():i32 (return (x-uses)))
```

→ `xf.nuc:0: error: unknown: y-later` (note: **line 0**, cf. W4).

Swapping the two imports in `z.nuc` does not help; per §2.1 there is no ordering
that works, which is the point.

> **Status: re-probed 2026-07-25 (after W4 landed). The last sentence above is
> false, and this repro does not motivate W1 on its own.**
>
> * The error now reads `xf.nuc:1: error: unknown: y-later` — W4a fixed the line.
> * **Swapping the two imports in `z.nuc` *does* help.** With `(import yf)` before
>   `(import xf)` the program compiles and returns 7. One ordering works; the
>   claim that none does is wrong.
> * **Making `xf.nuc` import `yf` — i.e. importing what you use — works in *both*
>   orders.** So as written, this repro only demonstrates that a file which
>   *declines to import what it references* is order-sensitive. That is arguably
>   correct behaviour, not a defect, and it is not a case worth spending W1a on.
>
> **The case that does motivate W1 is mutual recursion.** `a-fn` ↔ `b-fn` across
> two files (probe in §"Import emission already dedups", above) cannot be spelled
> with import-what-you-use discipline, because the import graph must stay acyclic
> — `import: circular import`. Real engine code is mutually recursive across
> modules, which is why the port has load-bearing import ordering in
> `src/g_game.nuc`.
>
> There are exactly **two** ways to express it today, and neither is
> import-what-you-use:
>
> 1. The sloppy pattern this repro uses — a file that does not import what it
>    references, relying on an ancestor to have imported it first. Order-sensitive,
>    and the thing §2.1 complains about.
> 2. **`(declare a-fn (i32):i32)` in place of the back-import.** Measured working
>    (see the W1e Status box below) — the cycle disappears and the pair compiles
>    and runs. This is a legitimate spelling, not a workaround, and it is the C
>    idiom §2.3 was about.
>
> So W1 is not "make the impossible possible" either. It is: **make the clean
> spelling — each file importing what it uses — legal for mutually recursive
> code, without breaking (2).** Route (2) working is also what makes W1a riskier
> than it looks; see the W1e box.
>
> **Restate W1's goal accordingly:** the defect is not "import order matters for
> sloppy code" — it is "**the compiler forces the sloppy pattern for mutually
> recursive code, and then makes it order-dependent**". W1a's whole-graph
> signature prescan is still the right mechanism; the justification and the
> accept criteria change. Before building W1, re-derive the port's actual shapes
> against this framing rather than against the three-file repro.

---

## Accept criteria

* The three-file repro above compiles and runs, in **both** import orders.
* The port's own harder shapes work: a file forward-referencing up into **two**
  independent higher files with no chaining; and a file reachable by two routes
  with no ordering constraint. Build both as `tests/` cases — they are the
  regressions that matter.
* **Added 2026-07-25 (see the two Status boxes above):** the two-file
  **mutual-recursion** shape — `af.nuc` and `bf.nuc` each importing the other and
  each calling the other's function — must compile, run, and be expressible
  *with* both files importing what they use. This is the shape that actually
  justifies W1; the three-file repro is order-sensitive only because `xf.nuc`
  declines to import `yf`, and it already passes today once that import is added.
  Whether the accepted spelling keeps the back-import or drops it is exactly the
  W1d decision — but a mutually recursive pair must have *some* clean spelling,
  which today it does not.
* **`make test` green; `make bootstrap` a byte-identical fixed point.** The
  compiler's own source compiles today, so W1 must not change its IR at all. A
  diff means the walk changed something for programs that already worked —
  investigate before proceeding.
* A genuine duplicate (two files, same name+arity) still errors.
* A genuinely missing symbol still errors, with the improved W1c message.
* `docs/` states the new rule in one sentence: *a `defn` in any reachable file of
  the unit is callable from any other; import order does not affect resolution.*
  The old ordinal rule is deleted, not softened.
* Note in this doc whether §2.3 and §2.4 turned out to need work, and what was
  decided.

## Out of scope for W1

Type **reachability** (§2.7) stays as-is: a struct type named in a unit's
signatures must still be defined in a file reachable from the entry point. That
is correct behaviour, not a defect — W1 removes the order constraint, not the
reachability constraint. Improve the *message* under W1c if it is unclear.
