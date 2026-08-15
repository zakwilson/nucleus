# W1 — Whole-unit signature resolution

> **Status: W1a + W1b IMPLEMENTED 2026-07-31.** Cross-file function references
> now resolve on reachability. The mechanism is a **second** whole-graph prescan
> pass, `prescan-imported-signatures` (`src/nucleusc.nuc`, immediately after
> `prescan-defn-signatures`), run from `emit-toplevel-forms` at
> `g-toplevel-depth == 1` **after** this unit's own prescans; the path guard is
> `g-prescan-sigs`. See the "W1a/W1b as built"
> section at the bottom of this file for the answers to the questions the design
> posed (idempotence, `finalize-generics` per-file safety, the `declare`
> interaction, the deferred-union defect the change exposed, and the bootstrap
> evidence).
>
> **W1c IMPLEMENTED 2026-07-31** — the diagnostic surface now distinguishes a
> typo, a genuinely absent name, and a name defined in a file no import reaches
> (which it names). See "W1c as built", also at the bottom. **W1e is resolved by
> obsolescence** (no mechanism built).
>
> **W1d IMPLEMENTED 2026-07-31 as Option 2** — import cycles are legal. Note the
> W1d section below carries **two** decision boxes: Option 1 was decided and
> built first, then the user chose Option 2 the same day and it was built over
> the top. The Option 1 box is preserved as superseded, because its reasoning
> about what W1a did to the *recommended* spelling is still what `docs/` teaches;
> read the SUPERSEDED box that follows it for what actually shipped.

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

> **Status: IMPLEMENTED 2026-07-31.** Built essentially as specified; the
> wording landed almost verbatim. See "W1c as built" at the bottom of this file
> for the tier order, the precedence decision (the file note *suppresses* the
> did-you-mean), the two chokepoints, and the enumeration mechanism.

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

> **Decision (2026-07-31, after W1a/W1b landed): Option 1, and the recommended
> spelling is "neither imports the other; a common parent imports both."** Both
> obligations the box attaches to that branch are discharged — the message and the
> docs rule, below.
>
> The box asked the right question, and W1a answered it with evidence rather than
> taste. **Option 2 was investigated and is blocked on macros, not on the
> bootstrap.** Relaxing the `g-importing` guard to *skip* an in-progress path
> instead of erroring is sound for *resolution* — signatures are registered
> graph-wide before any emission, so every reference in a cycle would resolve — and
> the bootstrap risk the design doc feared turns out to be nil, since any program
> that reaches the guard today is already a hard error, so no compiling program's
> emission order can move. Three things still key on **emission**, and the first is
> a genuine blocker:
>
> 1. **`defmacro` registers at emission time.** `g-macros` is populated by
>    `emit-defmacro`, and `emit-list` consults it before special forms. In a cycle
>    A↔B where B uses a macro A defines, the skip emits B's body *inside* A's
>    processing, before A's `defmacro` form is reached — the invocation dies as an
>    unknown name. There is no macro prescan and one is not cheap to add: a macro
>    body is JIT-compiled, so registering it early means *emitting and JITing* it
>    early.
> 2. **`defconst`/`defenum`/`defstruct` layouts are emission-time.** Signatures
>    survive on names-only StructDefs; a *body* taking `(sizeof S)` or a by-value
>    field does not.
> 3. **`do-import`'s global-scope slice** `[start-len, end-len)` is computed around
>    the emission, so a skipped re-entry has no slice and `import-prefixed` over a
>    cycle member would alias nothing.
>
> So Option 2 buys one spelling of one shape and costs a macro-prescan design. It
> is not refused on principle — if a future stage wants it, item 1 is the thing to
> scope first.
>
> **What makes Option 1 correct now rather than merely cheap** is that its advice
> changed meaning under W1a. Pre-W1a, *"remove the back-import"* told the author to
> write a file that references `a-fn` without importing `af` — the sloppy,
> order-dependent pattern §2.1 exists to complain about, which is exactly the box's
> objection. Post-W1a that pattern is no longer sloppy and no longer
> order-dependent: **an import establishes reachability, not visibility.** A file
> that does not import what it references is now spelling the language's actual
> rule, and measured to work in *both* orders (`m1`/`m2` in the accept matrix).
> Option 1 no longer "makes the sloppy spelling work" — W1a made that spelling
> correct, and Option 1 just declines to also allow the cycle.
>
> **Obligation 1 — the message says so positively.** Both `g-importing` raise sites
> in `do-import` (`src/nucleusc.nuc`) now read:
>
> ```
> import: circular import of 'af' -- remove this back-import; a cross-file
> reference does not require an import, so two mutually dependent files can both
> be imported by a common parent, in any order
> ```
>
> **Obligation 2 — `docs/` states the language rule.** `docs/toplevel.md`'s
> "Cross-file resolution: reachability, not import order" section states it, and
> its mutual-dependency bullet gives the spelling explicitly: a common parent
> imports both, neither imports the other, and `(declare …)` is the spelling when
> one of the pair must also be importable standalone.
>
> `run_w1_circular_still_errors` (`tests/run-tests.sh`) pins the hard error, so
> relaxing it later stays a deliberate act.

> **SUPERSEDED — Decision (2026-07-31, later the same day): the user chose
> Option 2. Cycles are legal. IMPLEMENTED.** The Option 1 box above is kept in
> full: its reasoning about *why the advice changed meaning under W1a* is still
> correct and is still what `docs/` teaches as the **recommended** spelling. What
> changed is only that the compiler now also *allows* the cycle instead of
> refusing it. The deliberate act the pinned test existed to force is this box.
>
> **Mechanism.** Both `g-importing` sites in `do-import` (`src/nucleusc.nuc`, the
> `NODE-STR` `.nuc`-path branch and the `NODE-SYM` branch) call
> `note-import-cycle` and `return` instead of `die-at`. The skipped path is
> deliberately **not** added to `g-imported` — that list stays "finished files",
> and its `[start-len, end-len)` slice is what a later prefixed import reuses.
> Emission is therefore idempotent per path exactly as the spec asked: each file
> emits once, at first reach. Measured working: two-file cycles in both
> compilation orders, three-file cycles, self-import, and the `import-use`
> (prefix-null) spelling.
>
> **The bootstrap prediction held.** `make bootstrap` was byte-identical on the
> first pass, and a pre/post `--emit-llvm` sweep over `examples/` + `lib/` was
> 168 files byte-identical, 0 differing. Both follow from the same argument the
> Option 1 box made: any program that reaches the guard today is already a hard
> error, so no *compiling* program's emission order can move.
>
> **What is diagnosed rather than supported.** Scope was fixed up front: **no
> macro prescan** (registering macros early means *emitting and JIT-compiling*
> them early — its own stage). So each emission-time coupling gets a located,
> specific diagnostic naming the cycle. The Option 1 box listed three; measuring
> them corrected two entries and turned up a fourth:
>
> 1. **`defmacro` — confirmed**, and it is joined by `defconst` and `defenum`
>    *members* (the box did not separate these from the layout item; they are
>    name-registration failures, not layout failures, and they share a
>    chokepoint). All three now route through two new tiers in
>    `unresolved-name-message` — `cycle-prefix-message` and
>    `cycle-definer-message` — placed above W1c's unreachable-file tier. The
>    definer scan (`text-defines-name`) gained a `defenum`-member sweep: it
>    matched only the token after the keyword, i.e. the enum's *name*, so
>    `W1-BLUE` was invisible. That also closed the same blind spot in W1c's
>    unreachable-file note.
> 2. **`defconst`/`defenum`/`defstruct` layouts — the layout half was
>    HALF WRONG.** The box said "a *body* taking `(sizeof S)` … does not
>    [survive]". Measured: **`(sizeof S)` across a cycle is correct**, and so is
>    `(alloca S)` — both lower to a GEP/alloca over the LLVM *named* type, which
>    LLVM resolves from the `%S = type {…}` line emitted later in the same
>    module. What genuinely breaks is anything that reads the **compiler's own**
>    field table or `abi-sizeof`: field access/assignment/address, struct
>    literals, a by-value field of another struct, and by-value parameters,
>    returns and arguments. `cycle-pending-sdef` /
>    `reject-cycle-pending-layout` / `reject-cycle-pending-sdef`
>    (`src/type-utils.nuc`, beside `reject-opaque-type`, whose site list they
>    mirror) cover these.
> 3. **The prefix-alias slice — confirmed**, and it matters more than the box
>    implies, because the bare `(import foo)` spelling *is* the prefixed one
>    (prefix defaults to the lib name). A cycle written with `(import …)`
>    therefore always suppresses an alias set. It is harmless as long as the
>    files refer to each other unqualified — which is the language's actual rule
>    — and `cycle-prefix-message` says exactly that when they do not.
> 4. **NEW, and the one with teeth: a by-value struct at an ABI boundary was a
>    silent miscompile.** `abi-classify` sized a not-yet-laid-out struct at 0 and
>    emitted `define i32 @f(i0 %v.arg)` on the definition side against a call
>    site that passed two `i64`s. The only symptom was an **unlocated**
>    `failed to parse generated IR` pointing into the generated file. The check
>    lives in `abi-classify` itself (`src/abi.nuc`) — the single chokepoint
>    `emit-defn`, the `declare` emitter, `emit-call-with-args` and
>    `emit-return`/`emit-struct-ret` all funnel through — with `emit-defn`'s
>    parameter and return sites checking first so the common case gets an exact
>    line instead of the ambient `g-form-line`.
>
> Every one of these is gated on `g-import-cycles != null`, so the whole
> diagnostic surface is dead code for any unit without a cycle — which is every
> unit that compiled before this change.
>
> **Also fixed here (pre-existing, reproduces on the committed boot):** two `.nuc`
> *string-path* imports in one file died `import: prefix 'c' is already bound to
> '<first path>'`. `emit-import-prefixed` defaulted **every** `NODE-STR` import's
> prefix to `c` — correct for a C header, wrong for a Nucleus path, which
> `do-import` already treats as a Nucleus file. A `.nuc`/`.nuch` path now defaults
> from its **basename** (`path-import-default-prefix`, beside
> `import-default-prefix`), the same rule the symbol spelling uses, so
> `(import "lib/list.nuc")` and `(import list)` both bind `list/…`. Two paths with
> the same basename now collide under a prefix the author can recognize, fixed the
> same way as for symbols — an explicit second operand. Chosen over "derive from
> the full resolved path" because `do-import` does **not** run `resolve-import` on
> a string path (it uses the string verbatim), so the basename is the only stable
> component; and over "leave `.nuc` paths prefixless" because the bare `import`
> keyword is defined to be the prefix-qualified one.
>
> **Also fixed (memory safety, found while writing these messages):**
> `src/format.nuc`'s helpers passed `snprintf`'s return — the length the output
> *would* have had — straight to `arena-strndup`, which `memcpy`s that many bytes
> out of a fixed stack buffer. Any diagnostic longer than the buffer was a stack
> over-read, reachable today via W1c's absolute-path notes. All helpers now clamp
> through `fmt-take`, and the string-carrying ones moved 512 → 1024 so a
> two-path cycle note fits whole.
>
> **If a future stage wants full cycles**, item 1 is still the thing to scope
> first, and it is still a macro *prescan* — i.e. a design for emitting and
> JIT-compiling macro bodies ahead of their file's emission. Items 2 and 4 would
> be a graph-wide **layout** prescan, which is a separate and probably larger
> problem: front-loading `defstruct` emission reorders the type section for every
> program (see conventions.md, "Front-loading a prescan reorders the type
> section"), so it cannot be additive the way W1a's signature prescan was.
>
> > **Built 2026-08-15 as W9 item 40, and the sentence above is wrong in exactly
> > one word: *emission*.** The layout prescan front-loads `defstruct`
> > **registration** and not its emission — `emit-defstruct` splits at the line
> > where it starts writing IR, so every `%Name = type {…}` line is still printed
> > by the definer at the point it always was. Measured over 396 programs: 0 new
> > errors, 0 changed error texts, and 17 files whose only diff is a *stamped
> > instance's* type line moving within the type section, with the line multiset
> > identical — the inert class, not a new one. Items 2 and 4 are closed, and so
> > is item 3's remaining half, so what a cycle cannot carry is down to a
> > `defmacro` and a `deferror` id: the two things that only an EMITTER produces.
> > Item 1 keeps its scoping note above and is now **ruled** rather than open —
> > registering a macro *is* emitting one, so it is not this technique's shape.
>
> **Tests.** `run_w1_circular_still_errors` is replaced — not deleted — by
> `run_w1d_cycle_accepts` (5 units: both orders, `import-use`, three-file,
> self-import; each compiles, links, runs and asserts an exit status),
> `run_w1d_cycle_diagnoses` (8 units: macro, defconst, defenum member, field
> assignment, struct literal, by-value parameter, prefix alias, plus
> duplicate-still-rejected-inside-a-cycle), and `run_w1d_path_prefix` (4 units).
> Both orders return *different* values (2 and 1), so they cannot pass by
> accident against one shared answer. 303 → 319 PASS, 0 FAIL.

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

> **Decision (2026-07-31, after W1a/W1b landed): §2.3 is
> resolved-by-obsolescence. No forward-declaration mechanism was built, and none
> should be.** The requirement the hazard box states is met — but by an existing
> mechanism, and the box's *symptom* was already stale when it was written down.
>
> **Premise correction: shape 3 no longer reproduces, and did not before W1a
> either.** Re-probed 2026-07-31 against `build/nucleusc` at `e45720c`, all four
> spellings compile, link and run:
>
> | Shape | Result |
> |---|---|
> | `declare` + `defn` of the same function, same file | exit 0, one `define`, no stray `declare` |
> | `(import def1)` then `(declare only-fn (i32):i32)` | exit 0 |
> | `(declare only-fn (i32):i32)` then `(import def1)` | exit 0 |
> | `declare` cycle-breaker, parent importing **both** files | exit 0, runs correctly (returns 2) |
>
> So the `duplicate method signature` shape-3 symptom is gone. **The requirement
> still stands regardless**, because W1a makes every `declare` whose definition is
> reachable *become* shape 3 — and it holds after W1a: all four spellings above
> still pass, and two of them are pinned as `run_w1_declare_cycle_breaker` and
> `run_w1_declare_plus_import`.
>
> **What actually satisfies it** is `emit-nuch-declare-import`'s
> `(when (!= (scope-lookup g-globals fname) null) (return))` — a `declare` whose
> name is already in the global scope stands down for the definition. Not W3c's
> `prescan-explicit-declares` (a different table), which was the natural guess.
> W1a makes that guard fire *more* often, which is why the shapes get safer rather
> than more fragile.
>
> **One fragile edge, pre-existing and left alone:** the guard keys on the **bare**
> name, and an overloaded (mangled) generic has no bare-name scope entry — so a
> `declare` naming an *overloaded* function would still register a stray `Sym`.
> Untested, out of W1's scope, recorded here so it is not rediscovered as new.
>
> **Remaining use case for `declare`, which is why it stays:** a file that is one
> half of a mutually recursive pair *and* must be importable on its own. The common
> parent's imports do not exist in that build, so reachability alone cannot supply
> the other half's signature. `docs/toplevel.md` documents `declare` for exactly
> this and no longer presents it as needed for ordinary cross-file references.

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

> **Status (W1c, 2026-07-31): the rule is untouched; the message got the same
> treatment as `unknown:`.** `parse-type-name` (`src/union-registry.nuc`) now
> raises through `unknown-type-message`, which carries both the
> "not defined anywhere in this compilation unit" wording and the
> unreachable-file note. `run_w1c_unreachable_type` is the guard.

---

## W1a/W1b as built (2026-07-31)

### The mechanism

Two whole-graph prescan passes, not one:

1. **`prescan-imported-types`** (unchanged) — walks the import graph depth-first
   registering every reachable file's struct/union type **names** and templates.
2. **`prescan-imported-signatures`** (new, `src/nucleusc.nuc`, immediately below
   `prescan-defn-signatures`) — walks the same graph registering every reachable
   file's **protocols** and **defn signatures**.

Two passes rather than one because a signature's types must resolve against the
*whole* graph's type names. A single walk would prescan file F's signatures
before a sibling G that their parent imports after it, reintroducing exactly the
ordering dependency W1 removes, one level down. (The compiler's own source would
have hit this immediately: `src/generics.nuc`'s signatures name `Method` /
`Generic`, defined in `src/compiler-types.nuc`, a sibling import.)

The new walk is **pre-order** (a file's own signatures, then its imports'), and
`emit-toplevel-forms` calls it *after* the outermost unit's own prescans. Both
choices are deliberate: they make the sequence of registrations — and therefore
the order in which parametric instances are first stamped, which is the order
their `%Name = type {…}` lines are queued — as close as possible to the order
today's interleaved prescan/emit walk produces. Only the *timing* moves:
everything is registered before any form is emitted.

Skips in the new walk, each for a specific reason:

* already on `g-prescan-sigs` — the graph can reach a file twice (the diamond);
* already on `g-imported` — the REPL processes one import per command, so a
  later command's walk can reach a file the session already loaded (whose
  signatures are therefore already registered). Without this a second REPL
  import would report a duplicate for every signature in the first one's graph;
* a `.nuch` header — its importer (`emit-nuch-import-forms`) deliberately does
  **not** run `prescan-defn-signatures`; a header's entries arrive as
  `declare` / `defmethod` / template-`defn` forms with their own registration
  paths, so prescanning here would double-register. `.nuch` resolution therefore
  keeps exactly its previous (ordinal) behaviour;
* a C-header string import — reading one shells out to clang (pass 1's rule).

Only the `NODE-SYM` import spelling is walked, matching pass 1; a `.nuc`/`.nuch`
**string path** import is still left to emission.

### The idempotence question — possibility (3), not idempotent at all

`generic-register-method` (`src/generics.nuc`) **appends unconditionally** — no
name+arity+node keying, no byte-identical check — and `generic-add-method` then
sets `finalized = 0`. So a second `prescan-defn-signatures` over the same file
re-adds every method and the next `finalize-generics` sees each one twice and
dies `duplicate method signature for overloaded '<name>'`. That is possibility
**(3)** in the design's list, and it is the reason the walk needs a path guard
rather than relying on registration being harmless.

Implemented exactly as the design prescribed: `g-prescan-sigs` (a Node string
list beside `g-prescan-visited`, reset in `compiler-init`) records each path the
walk prescans, and `emit-toplevel-forms` samples it against `g-source-path`
**before** the walk runs and skips its own `prescan-protocols` /
`prescan-defn-signatures` for a path on it. **The duplicate-signature check was
not weakened**: two different files defining the same name+arity still error
(pinned by `run_w1_still_rejects`).

`finalize-generics` still runs at exactly the point `prescan-defn-signatures`
would have called it — the skip branch calls it directly — so a generic that
gained methods since (a `.nuch` `defmethod` import, a REPL redefinition) is
mangled at the same moment as before. Only the *registration* moved earlier.

### W1b — namespaces, and `finalize-generics` per file

The walk applies each visited file's own leading `(ns …)` and `set-ir-prefix`
while prescanning it, starting from `user` and restoring `g-current-ns` /
`g-ns-seen` afterwards — the `do-import` shape. This is load-bearing, not
hygiene: `scope-define` qualifies a global's key against `g-current-ns`, and
`generic-new` snapshots the namespace's ir-prefix into `Generic.ir-prefix` for
`finalize-generics` to bake into the solitary method's ir-name. Prescanning a
namespaced file under the *importer's* namespace would register it under the
wrong key and mangle it under the wrong prefix. `run_w1_ns` is the guard.

`finalize-generics` **is** safe to call once per visited file, and no split into
register/finalize halves was needed. `generic-add-method` already clears
`finalized` precisely so a later unit's registrations re-mangle an
already-finalized generic (its own comment says so), and this all happens in the
prescan phase, before any affected body is emitted, so no already-emitted
reference can carry a stale ir-name.

### W1e's hazard: real, and already handled — by `scope-lookup`, not by a new check

The W1e Status box's shape 3 (a `declare` plus a reachable `defn` of the same
name dying `duplicate method signature`) **does not reproduce** — re-probed on
`e45720c` in all four spellings before this work started. The mechanism that
makes it work is `emit-nuch-declare-import`'s
`(when (!= (scope-lookup g-globals fname) null) (return))`: a `declare` whose
name is already a registered solitary `defn` is a complete no-op — it neither
registers a second signature nor emits a second LLVM `declare`. (W3c's
`prescan-explicit-declares` is a different table and is not what closes it.)

W1a makes that early return fire *more* often, not less — the name is now in
`g-globals` before any file is emitted — so the requirement is met by
construction rather than by a new compatible-prototype check. The `declare`
cycle-breaker still compiles, links and returns the right answer, in both the
"declare only" and "declare plus an import of the definer" shapes
(`run_w1_declare_cycle_breaker`). The fragile edge, unchanged by this work and
worth knowing: the early return keys on the *bare name* in `g-globals`, so a
`declare` naming an **overloaded** (mangled) function — which has no bare-name
scope entry — would still register a bare `Sym` beside the generic. No test
exercises that today; it is pre-existing and out of W1's scope.

### The defect this exposed, and fixed: eager union backing-struct lines

`defunion-register` (`src/union-registry.nuc`) wrote the backing struct's
`%X = type { i32, %__anon_union_… }` line **eagerly** into `g-type-stream` and
set `emitted = 1`, while the anon payload union it names sits on the *deferred*
queue (`g-pending-unions`), emitted only when `pending-union-deps-ready` says its
own named dependencies are present. For a scalar payload (`!i32`, `!ptr`,
`!raw:Node` — everything the compiler itself uses) the union is ready at the very
next drain and nobody notices. For a **struct** payload (`!String`) the union
waits for `%String`, which arrives with a later import — and *every module
assembled in between* carries the reference with no definition.

This is pre-existing, and reproduces on the committed boot compiler:

```lisp
(compile-time (printf "ct ran\n"))
(import-use string)
(defn wrap (sv:StrView):!String (return (string-from-view sv)))
(defn main ():i32 (return 0))
```

→ `lib/macros.nuc:11: compile-time: IR parse error: <compile-time>:4:34:
error: use of undefined type named '__anon_union_h5cc06870e474e483'`.

W1a widens it enormously (the stamp now happens during the prescan, so the
dangling window covers every `defmacro`/`compile-time` JIT module in the build),
which is how it was found: eleven examples failed identically.

Fixed at the root — the backing struct is queued on `g-pending-unions` instead of
written eagerly **exactly when writing it now would dangle** (payload union
present, not yet emitted, and its own deps not ready). The queue emits it via
`emit-pending-struct-ir-type`, whose text is character-identical to the `fprintf`
it replaces, and queue order puts it after the anon union, in dependency order.
Every scalar/pointer payload keeps the eager write and its IR position, which is
what keeps the compiler's own IR unaffected by this half of the change.
`run_w1_deferred_union_payload` is the guard.

Generalizable lesson (recorded in `context/conventions.md`): the deferred-type
queue's contract is *"a `%Name = type {…}` line enters the shared buffer only
once every named type it references is already there"*, and `emitted` means
"present in the module currently being assembled". A path that writes a type line
outside the queue must re-establish that contract itself.

### The second defect this fixed: a symbol mangled *after* it was emitted

Found by sweeping every `lib/*.nuc` and `examples/*.nuc` through the pre- and
post-W1a compilers. Two examples' IR differed in more than type-line order —
`examples/rest-defn.nuc` (`@append` → `@append.ptr.ptr`) and
`examples/string-test.nuc` (`@byte-len` → `@byte_len.pStrView`, and ~20 siblings).
Both are W1a producing the *correct* symbol where the old compiler produced an
accidental one.

`emit-defn` reads `defn-ir-name` at emission time, and `finalize-generics` decides
solitary-vs-mangled from the method set known *at that moment*. Under the ordinal
rule a file could be emitted before a later import registered a second method of
the same name: the definition went out as the solitary `@append`, the generic then
became mangled, and every call site emitted afterwards went through
`emit-generic-call` and named `@append.ptr.ptr`. Minimal repro, on the committed
boot compiler (`lib/list.nuc`'s concrete `append` + `lib/vector.nuc`'s `append`
template):

```lisp
(import-use "lib/list.nuc")
(import-use vector)
(defn main ():i32
  (let (c:ptr (make-cell null null 0) r:ptr (append c c)) (return 0)))
```

→ `define ptr @append(...)` but `call ptr @append.ptr.ptr(...)`, and the link
dies `use of undefined value '@append.ptr.ptr'`. `rest-defn.nuc` and
`string-test.nuc` escaped it only because every call to the affected names
happened to be emitted *before* the overloading import, inside the defining
library itself.

Registering every reachable signature before any form is emitted makes the
solitary-vs-mangled decision final before the first `define` is written, so the
definition and every call site cannot disagree. `run_w1_late_overload_symbol` is
the guard. **Observable consequence worth stating plainly:** a Nucleus function
whose name is overloaded anywhere in the reachable graph now *always* gets the
mangled symbol, where before it might have kept the bare `@name` depending on
import order — so a C consumer that linked against such a bare name was relying on
the bug and must use the mangled symbol (or the library must stop overloading the
name, or spell an explicit `set-ir-prefix`/solitary alias).

### Sweep evidence (pre- vs post-W1a, every `lib/` and `examples/` program)

| Outcome | Count |
|---|---|
| Byte-identical IR | 104 |
| Type-definition **order** only (normalized-identical) | 55 |
| Real IR difference — the late-overload symbol fix above | 2 |
| Compiled before, fails now | **0** |
| Failed before, compiles now | 5 (`lib/string.nuc` — the anon-union defect above; four W5-era features the committed boot predates) |

### Verification

* **The corrected repro E compiles in both import orders and returns 7**;
  the namespaced pair compiles in both orders and returns 42
  (`run_w1_mutual`, `run_w1_ns` — both fail on the committed boot compiler).
* Diamond (11), two-routes-to-one-file (10), two-independent-higher-files (12)
  all still compile, link and run (`run_w1_graph_shapes`).
* A genuine duplicate still errors; a genuinely missing symbol still errors
  (`run_w1_still_rejects`).
* A mutual `(import …)` pair still errors `import: circular import of 'w1-ca'`
  at a real line — pinned so W1d stays a deliberate decision
  (`run_w1_circular_still_errors`).
* `make test` **292 PASS, 0 FAIL** (279 before; +13 new units).
  `make abi-test`, `make layout-test` both PASS.
* **`make bootstrap` was NOT byte-identical on the first pass, and the diff was
  proven inert before the boot was reconverged.** 44 changed lines, *all* of them
  `%Name = type {…}` definitions moving within the type section: normalizing both
  files by sorting the type-definition lines and dropping blanks makes them
  **byte-identical**, i.e. the *set* of type definitions is unchanged and **zero**
  `declare` / `define` / string-table / function-body lines differ. The types that
  moved (`%Maybe.i32`, `%Maybe.i64`, `%Result.ptr.Err`, `%Vector.pConstraint`,
  `%Vector.cstr`, `%VecIter.pCleanup`, `%VecIter.pMethod`,
  `%Maybe.Entry.cstr.pType` and their anon unions) are exactly the instances an
  imported file's *signatures* stamp: front-loading the signature prescan
  front-loads their first stamp. LLVM named struct types are order-independent
  within a module (the queue's own header comment says so, and the pre-W1a output
  already contained forward references among these very lines), so the move is
  semantically inert. The new compiler is a **fixed point on its own** — compiled
  with `build/nucleusc`, linked, and used to recompile `src/nucleusc.nuc`, the two
  IRs are byte-identical — so the `make bootstrap` diff was purely "stage1 comes
  from the old boot". Reconverged per `context/build.md`.

---

## W1c as built (2026-07-31)

### The four tiers, and the precedence decision

One chokepoint per namespace. `unresolved-name-message` (`src/nucleusc.nuc`)
composes `unknown:` (head position) and `undefined:` (value position); the new
`unknown-type-message`, beside it, composes `unknown type:` and is called from
`parse-type-name` (`src/union-registry.nuc`) — a call *up* into `nucleusc.nuc`,
which is legal from an imported module and is how `generics.nuc` already reaches
`macroexpand-form`.

| # | Tier | Text |
|---|---|---|
| 1 | C-header skip (W3c, unchanged) | `unknown: 'strtold' — its C header declaration was skipped (<header>:<line>: <reason>)` |
| 2 | Unreachable file (new) | `unknown: y-later — not defined anywhere in this compilation unit`<br>`  note: 'y-later' is defined in <path>, which no import in this unit reaches` |
| 3 | Did-you-mean (W4a, unchanged) | `unknown: printfx (did you mean 'printf'?)` |
| 4 | Defined nowhere (new wording) | `unknown: qzx — not defined anywhere in this compilation unit` |

**Tier 2 suppresses tier 3.** Naming the file that defines the exact name is a
strictly better answer than guessing at a spelling, and firing both would offer
two contradictory diagnoses of one failure. They collide almost never anyway:
the scan matches the name *exactly*, so a genuine misspelling finds no file and
falls straight through to tier 3. Tier 3's text is byte-for-byte what it was, so
`w4a-suggest-spelling`'s pinned string needed no change; tiers 2 and 4 only
*append* to the `verb: name` prefix, so `w1-missing-rejected`,
`w4a-undefined-value`, the `unknown type:` pins and every `run_reject` substring
match keep passing untouched. **No existing test expectation was modified.**

The note is a second line inside the message string — `die-at`/`report-at` print
the message verbatim after the `path:line: error: ` prefix, so `\n  note: …`
lays out exactly like the existing monomorphization note, with no change to the
reporting functions.

### Why a textual scan, and why only on the error path

`unreachable-definer-file` runs a **textual** scan of file bytes rather than
invoking the reader. `read-program`/`desugar` mutate `g-src` / `g-pos` /
`g-line` / `g-source-path` / `g-peek` / `g-peek-valid`; re-entering them while a
diagnostic is being composed is a reentrancy hazard for no benefit. The scan
skips line comments and string literals, which removes the two obvious
false-positive sources; a definer spelled inside a quasiquoted macro body could
still match, which is why the result is phrased as a `note:` and the primary
error text is true on its own.

It is safe to be this expensive because it is unreachable except on the way to
`exit`. **Both** callers of `unresolved-name-message` — `emit-symbol-ref`'s
value position and `emit-dispatch`'s head position — and `parse-type-name`'s
raise are `die-at`, which carries `noreturn`. (The design brief flagged this as
uncertain; it is not. In the REPL `die-at` unwinds via `repl_throw` rather than
`exit`, which is still one scan per *failed* command.) Measured: a fixture that
fails with `undefined:` compiles in the same 0.135 s as one that succeeds.

Search directories are exactly `resolve-import`'s first three — the current
source file's directory, `lib/` relative to cwd, and each `-I` — deduplicated,
non-recursive, `.nuc`/`.nuch` only, first match wins. `$NUCLEUS_LIB` and the
compiled-in install prefix are deliberately **excluded**: a file there is a
stdlib file the user cannot add to their project by editing an import, so
naming it would be advice they cannot act on.

### Skipping files already in the unit — and the one that is on no list

A file already in the unit cannot be the answer: if it were, the name would have
resolved. `path-in-unit` checks `g-prescan-visited` (the type prescan's walk),
`g-prescan-sigs` (W1a's signature walk) and `g-imported` (import emission) —
together every way a `.nuc` enters the unit.

Except one. **The unit's root file is on none of them**, because nothing imports
it; without a fourth check the scan could name the entry point itself
("no import reaches your own entry point" — true and useless). `g-source-path`
covers it only while the root is the file being emitted, so
`emit-toplevel-forms` now records `g-unit-entry-path` at `g-toplevel-depth == 1`
(diagnostic-only; reset in `compiler-init`). Verified with a namespaced file
imported by the entry point and referenced by its *unqualified* name: the
reference fails, and no note is produced, because the defining file is in the
unit.

### Directory enumeration: POSIX, hand-declared, and validated not trusted

`(import-use "dirent.h")` does not help — the C-header reader registers
`struct dirent` as **opaque** (its `char d_name[256]` member is a shape
`c-parse-struct-decl` declines), so a field access on it is refused with W3a's
opaque diagnostic. `glob_t` is opaque for the same class of reason. So
`opendir`/`readdir`/`closedir` are declared by hand beside the scan. This is not
a new platform dependency in kind: the compiler already requires POSIX
`popen`/`pclose` to run `clang -E` for every C-header import.

`d_name`'s byte offset (19: `ino_t` + `off_t` + `unsigned short` +
`unsigned char` on 64-bit glibc and musl) is **validated, not trusted** — POSIX
does not fix the layout. An entry is used only when the bytes at that offset are
a short NUL-terminated name ending in `.nuc`/`.nuch`, so on a platform whose
layout differs the scan finds nothing and the diagnostic degrades to its primary
text. It can never put garbage in a message, and the read stays inside the
kernel-filled dirent buffer either way, `d_name` being the last member.

### Verification

* `run_w1c_unreachable_file` — the note names the sibling file, and its negative
  control `w1c-note-advice-works` compiles, **links and runs** the same program
  once the named import is added: the note has to be advice that works.
* `run_w1c_defined_nowhere` — the tier-4 wording, and *no* `note:` line.
* `run_w1c_unreachable_type` — §2.7's type constraint, same note, from the
  `parse-type-name` chokepoint.
* Both note units also assert no `:0:`, and every fixture keeps feeding
  `run_no_line_zero`.
* `make test` **297 PASS / 0 FAIL** (293 before). `make bootstrap`
  **byte-identical on the first pass** — W1c touches only error paths and
  message text, so it cannot move emitted IR. `make abi-test`,
  `make layout-test` PASS. `boot/nucleusc.ll` deliberately not refreshed: it
  still bootstraps the new source.
