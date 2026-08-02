# W6 — Nullability flow typing (design only)

**Finding:** §3.3. Also triages §3.4 (a `let` local bound to `null`) and §1.1's
cousin problem of `unsafe/cast` overuse.

**This item is a design document, not an implementation.** Produce the design;
implement in a later stage.

---

## 0. Summary — and four corrections to this document's original premises

This file was written before Stage 15's W2 and W4 landed, and before anyone
re-read the Stage 10 implementation. Re-probing against `build/nucleusc` at
`stage15-stress-test` (commit `6984a67`) contradicts it on four points. Each is
recorded here because the corrections, not the original plan, are what the
implementation should be built on.

| # | Original premise | Ground truth (measured) |
|---|---|---|
| **C1** | "there is no flow-sensitive narrowing" | **False.** A complete flow-narrowing engine has existed since Stage 10 (`src/nucleusc.nuc:1469-1660`, driven from `emit-cond`/`emit-while`/`emit-label`/`emit-set`). `(when (= m null) (return …))`, `(if (!= m null) …)`, `(and …)`-chains, `if-some`/`when-some` and sticky reassignment kills all work today. It is gated to **`?T` (PTR-MAYBE) bindings referenced by bare name** — that gate, not the absence of the feature, is §3.3. |
| **C2** | §3.4 is "a `let` local **inferred** raw, so a **later field write** fails, **at line 0**" | **False on all three counts.** The local is *explicitly declared* `ptr:T`; the rejection is of the `null` **initializer**, reported at the `let`, not at any later write; a field write through a genuinely `raw` local succeeds. Post-W4 the location is correct (no line 0). See §1.5. |
| **C3** | Globals allow `(defvar- g:ptr:T null)` — decide whether the asymmetry is "intentional", and if so relax locals to match | **The asymmetry is a soundness hole in the *global* path, not a feature to copy.** `(defvar- g:ptr:Intercept null)` compiles to `@g = global ptr null` and **segfaults on first use** (measured). The local path is the correct one. §3.4's proposed direction of fix is backwards. See §1.5. |
| **C4** | The desugar-to-`if-some` route may be blocked because `(Maybe ptr)` is niche-encoded and pointer element types cannot `match` | **The named blocker does not apply** — `if-some` on a pointer never reaches `match`. But the route is still rejected, for the opposite reason: `emit-if-some` (`src/union-emit.nuc:377-421`) **already desugars into the narrowing engine**, synthesizing a `(!= x null)` `cond` test precisely so `narrow-apply` fires. Narrowing is the primitive; `if-some` is the sugar. Desugaring narrowing to `if-some` would be circular. See §5. |

Two **live soundness bugs** in the existing engine were found while measuring
this (§2). Both are in exactly the invalidation territory W6 must specify, both
segfault today, and both have **zero blast radius** to fix (nothing in `src/`,
`lib/`, or the port declares a `?`-typed global).

And the headline empirical result (§3): a complete, safe, checked spelling for
the port's §3.3 shape **already exists and works** —

```lisp
(when-some (fs (as-ref (li frontsector)))     ; fs reads as ptr:Sector here
  …)
```

— and the port used `as-ref` **zero times** across **2113** `unsafe/cast`s. §3.3
is therefore *majority* a discoverability failure of a shipped mechanism, with a
real but much smaller residue of missing capability. That reshapes the work from
"build flow typing" into a four-tier plan (§8) whose first tier is documentation
and diagnostics.

---

## 1. Ground truth: what the compiler does today

Everything in this section was verified by probe against `build/nucleusc` on
2026-07-31. Probes are run from the repo root (the prelude resolves relative to
the invocation).

### 1.1 The pointer-kind lattice and its single chokepoint

Three kinds share one IR type (`src/compiler-types.nuc:85-87`):

| Kind | Spelling | Deref | Flow into a `(ref T)` slot |
|---|---|---|---|
| `PTR-RAW` | `(raw T)`, `raw:T` | allowed, unchecked | **rejected** |
| `PTR-MAYBE` | `?ptr:T`, `?T`, `(Maybe (ref T))` | **rejected** until narrowed | **rejected** |
| `PTR-REF` | `ptr:T`, `ref:T` | allowed | allowed |

Two gates enforce this, both in `src/type-utils.nuc`:

* **`pkind-flow-check` (`type-utils.nuc:401-413`)** — the *flow* gate. Fires only
  when the **destination** is `PTR-REF` *and* has an element type (an elem-less
  bare `ptr` is the `void*` hatch and is exempt, `type-utils.nuc:408`). Reached
  from exactly three call sites, all funnelling through one coercion chokepoint:
  * `src/abi.nuc:580` — inside `coerce-int-val`, ctx `"assignment"`. This is
    every binding init, `set!`, and field/element store.
  * `src/nucleusc.nuc:3785` — ctx `"argument"`.
  * `src/nucleusc.nuc:6160` — ctx `"return"`.
* **`require-derefable` (`type-utils.nuc:417-419`)** — the *deref* gate. Fires
  only on `PTR-MAYBE`. `raw` is exempt (the signed waiver). Seven call sites
  (field access, `aref`, `aset!`, `deref`, `ptr-set!`, `.set!`, `.&`, `match`).

**Consequence, and it is the crux of §3.3:** a `(raw T)` value may be deref'd and
field-chained freely; it is refused *only* when it flows into a declared non-null
**slot**. Verified — with `Line.frontsector : (raw Sector)`:

```lisp
(when (!= ((li frontsector) floorheight) ((li backsector) floorheight)) …)  ; compiles, no cast
```

This means the `unsafe/cast` at `p_map.nuc:1184` — and the 47 other casts in
field-access head position across the port — are **not compiler-forced at all**.

### 1.2 The flow-narrowing engine that already exists

`src/nucleusc.nuc:1469-1660`, specified in `design/stage10/nullability.md §4`,
landed 2026-06-12.

| Piece | Location | Role |
|---|---|---|
| `sym-effective-type` | `nucleusc.nuc:1489-1492` | **the single shared rule function**: `Sym.ntype` if narrowed, else `Sym.type` |
| `narrow-mark` / `narrow-restore` | `1494`, `1520-1533` | region save/restore over a global undo stack |
| `narrow-apply` | `1501-1516` | narrow one name; **the two gates live here** |
| `narrow-kill` / `narrow-kill-all` | `1536-1548` | sticky kill via a `kstamp` bump; `label` kills all |
| `node-binding-name` | `1564-1572` | **places are bare symbols only** |
| `test-true-nonnull` / `test-false-nonnull` | `1578-1633` | fact extraction: `!=`/`=` vs `null`, `and`/`_and`, `or`/`_or`, `not` |
| `prescan-kill-sets` | `1645-1657` | textual `set!` scan before a loop body emits |

Drive points: `emit-cond` (`6607-6695` — per-arm marks, accumulated
failed-test facts `acc`, and **`after`** facts that dominate the code following
the `cond` when every prior body terminated — this is the early-return guard),
`emit-while` (`6732-6762`), `emit-label` (`6981`, kills all), `emit-set`
(`6835`).

`sym-effective-type` is read by both the emit side (`nucleusc.nuc:1889`, `6057`)
and the type side (`generics.nuc:3692`, `nucleusc.nuc:4666`). **The
`node-type`↔`emit-node` lockstep is already solved for narrowing by exactly the
W2 remedy** — one rule function that both sides call. §8.5 says how to keep it
that way.

### 1.3 Measured coverage — what narrows today

| # | Probe | Result |
|---|---|---|
| P1 | `?ptr:T` param, `(when (!= m null) (return (use m)))` | **narrows** |
| P2 | `(raw T)` param, same guard | **rejected** — `argument: raw pointer where non-null…` |
| P3 | `(let (fs:?ptr:T (l field)) (when (!= fs null) (use fs)))` | **narrows** |
| P4 | `(when (!= (l field) null) (use (l field)))` — field read, no rebind | **rejected** — `value may be null…` |
| P5 | **`raw` field** widened into a `?ptr:T` local, then guarded | **narrows**, runs correctly (`with=42 without=-1`) |
| W1 | `(when-some (fs (as-ref (li frontsector))) …)` on a `raw` field | **narrows**, runs correctly |
| A1 | `(and (!= m null) (!= n null))` | **narrows both** |
| A2 | `(when (= m null) (return 0))` then `(use m)` | **narrows the rest of the body** |
| A3 | `(set! m s)` from a non-null `s`, then `(use m)` | **narrows** |
| C1/C2 | the same shapes with the guard **removed** | **correctly rejected** (negative controls) |

The two gates in `narrow-apply` produce exactly this boundary:

```lisp
(when (= (sym is-local) 0) (return))                  ; nucleusc.nuc:1505  → "locals" only
(when (!= (ptr-pkind eff) PTR-MAYBE) (return))        ; nucleusc.nuc:1507  → ?T only, never raw
```

plus `node-binding-name` (`1564`) accepting only a bare `NODE-SYM` → **no field
reads, ever**.

### 1.4 What §3.3 actually is

Three independent things wearing one finding number:

* **§3.3a — `raw` never narrows** (`nucleusc.nuc:1507`). The port declared every
  nullable back-pointer `(raw Sector)` / `(raw Mobj)` (`r_defs.nuc:188-189,
  225-226`), because that is the natural transcription of a C `sector_t *`. `raw`
  is the *waiver* kind, and the waiver is deliberately not narrowed.
* **§3.3b — a field read is not a narrowable place** (`nucleusc.nuc:1564`). Real
  and missing. This is the hard case.
* **§3.3c — `as-ref` exists, is the answer to most of §3.3a, and nobody found
  it.** See §3.

### 1.5 §3.4, triaged

**Verdict: not part of W6. It needs no flow analysis. But it is not the cheap fix
the brief describes, because the fix runs in the opposite direction.**

Measured, exactly:

```lisp
(defn main () i32
  (let (in:ptr:Intercept null)          ; ← line 8
    (.set! in frac 1.0)                 ; ← line 9
    0))
```
```
p34.nuc:8: error: assignment: raw pointer where non-null (ref ...) is required — …
```

* The type is **declared**, not inferred. The rejection is of the `null`
  *initializer* flowing into a `PTR-REF` slot (`abi.nuc:580` →
  `pkind-flow-check`). It is the *correct* diagnosis of a real error: `null`
  types as `ty-raw` (`nucleusc.nuc:1841`), and a `ptr:T` slot means non-null.
* **The location is fixed** — W4 did this. It reports the `let`, not line 0.
  *Residual imprecision worth a W4-class follow-up:* the error blames the `let`
  **head** line, not the offending binding's own line. In a multi-line binding
  list (`e.nuc`, binding on lines 6-7) it still reports line 4.
* **A later field write is not the failure.** `(let (p:raw:Intercept null)
  (.set! p frac 1.0) …)` compiles clean — `require-derefable` exempts `raw`.
* **The global is the bug.** `(defvar- g:ptr:Intercept null)` compiles and
  segfaults on first use. `defvar`'s global initializer is a **separate constant
  renderer** (`nucleusc.nuc:7883-7887`) that checks only `ty-kind == TY-PTR` and
  never consults the pkind — it does not route through `coerce-int-val`, so
  `pkind-flow-check` never runs. This is structurally the same class of bypass
  W2b found for integer truncation ("the global-initializer path bypasses the
  coercion chokepoint").

**Recommended disposition — report only, do not land here.**

1. The ergonomic need behind §3.4 ("a mutable slot that starts empty") is
   *already served correctly*: declare it `raw:T` or `?ptr:T`. Both accept
   `null`; `?ptr:T` then narrows at the guard (P5). Nothing to add.
2. The genuine defect is `(defvar g:ptr:T null)`. Fix: have the global-init path
   consult the pkind for the `null` and symbol cases, i.e. reject `null` into a
   `PTR-REF` destination with an element type, reusing `pkind-flow-check`'s
   exemptions verbatim.
   *Blast radius, measured:* all six `null`-initialised globals in `src/`+`lib/`
   (`lib/error.nuc:47`, `lib/keyword.nuc:56`, `union-registry.nuc:339-340`,
   `nucleusc.nuc:340,345`) are **elem-less bare `ptr`** and therefore already
   exempt. Zero compiler churn. The port has ~6 typed-ptr sites
   (`d_items.nuc:44`, `doomstat.nuc:98`, `p_maputl.nuc:295`, `g_game.nuc:159`,
   `states.nuc:64,363`) which must become `(raw T)` — an idiom that port already
   uses elsewhere (`g_game.nuc:158`, `r_bsp.nuc:58`, `i_sdlsound.nuc:94-95`).
3. **Sequencing:** this touches the same "`null` into a typed global slot" path
   that **W5c** (a `CStr`-typed `defvar` accepting `null`) is editing
   concurrently. It must be dispatched *after* W5c lands, as a separate item, and
   the two must agree on one question: `pkind-flow-check` treats `CStr` as
   ref-compatible (`type-utils.nuc:384-388`), so if W5c makes `(defvar g:CStr
   null)` legal, the tightened global gate must carve `CStr` out explicitly or it
   will re-reject W5c's accept criterion.

**Status: item 2 landed (2026-07-31), exactly as recommended.** `defvar-init-ir`
(`src/nucleusc.nuc`) now calls `pkind-flow-check ty-raw ty …` on the `null`
branch, after the `CStr` early return — the *same* predicate the local path calls
rather than a re-derivation, so its three exemptions (`(raw T)`/`?T` not being
`PTR-REF`, and the elem-less-`ptr` untyped-destination refinement) come for free
and the two paths cannot drift. `ty-raw` is precisely the type
`emit-symbol-ref` gives the `null` symbol in value position. Ctx string is
`"defvar"`, so the message body matches the local's word for word.
Fixtures: `tests/fixtures/w6-defvar-null-{ptr-elem,ref,accepts}.nuc`.

*Two corrections to the blast-radius measurement above.* (a) The scan covered
`src/`+`lib/` only. Widening it to `examples/` finds a **seventh** site —
`examples/colon-paren-types.nuc:23`, `(defvar empty:(ptr Link) null)`, the
NUL-terminator of a hand-rolled linked list, whose `next` field and `chain-sum`
parameter are `(ptr Link)` for the same reason. It is the one place in the tree
that actually relied on the hole, and it was fixed the way the doc prescribes for
the port: the three nullable slots became `(raw Link)`. The example's output is
unchanged and its actual subject (colon-paren type sugar) is untouched — `(raw
Link)` is the same sugar, and `(ptr Link)` still appears in `with-value`, the
`let` bindings and the lambda. (b) "Zero compiler churn" holds: `make bootstrap`
was byte-identical on the first pass, since the change only adds a rejection.

The **no-initializer** sibling — `emit-defvar`'s default path emits `global ptr
null` for any `is-ptr-like` type, so `(defvar g:ptr:Thing)` is the same unsound
null-in-a-non-null-slot wearing a different spelling — was measured and
deliberately **left open**: the compiler's own source has **53** such globals (20
`ty-*:ref:Type`, `g-globals:ref:Scope`, and 32 `(ref (Vector …))`/`(ref (HashSet
…))`/`(ref (HashMap …))` registry tables), every one a process-lifetime singleton
filled by `types-init`/`compiler-init` after definition. Closing it is not a
check but a language question — deferred initialization of a non-null global — and
answering it with `?T` + narrowing would touch every use of `ty-i32` and friends.
It belongs to W6 proper, not to this triage item.

**Closure note, 2026-08-02.** The no-initializer half recorded above as open is
now closed, by **W8's G-5** ([../global-init.md](../global-init.md)):
`(defvar g:ptr:T)` — a `PTR-REF` global with an element type and no initializer
at all — is rejected with a located error, exactly as the explicit-`null`
spelling has been since item 2 above landed. `ptr:T` means non-null at a global
as it does everywhere else, and the language gap this section identified (no
way to express deferred initialization of a non-null global) is what G-0
through G-3 built to make the rejection safe to add: `(defvar g:ptr:T
(make-thing))` now typechecks with `g` non-null, whether `make-thing` is a
compile-time constant (G-1/G-2) or a runtime call run from `@__nucleus_init`
before `main` (G-3). This closes the triage recorded above without revising
it — the "not part of W6, needs no flow analysis" verdict above was correct,
and this is exactly the "deferred-initialization language question" the
section said the fix belonged to.

---

## 2. Two live soundness bugs in the existing engine

Both are pre-existing Stage 10 defects, both are in W6's invalidation territory,
and both **must be fixed before any tier of §8 widens what narrows** — widening
a leaky rule multiplies the leak.

### N-BUG-1 — a `?T` **global** narrows, and a call can invalidate it

```lisp
(defvar- gsec:?ptr:Sector null)
(defn clear ():void (set! gsec null))
(defn g2 ():i32
  (when (!= gsec null)
    (clear)
    (return (use gsec)))          ; accepted today → segfault
  -1)
```
`$ ./g2` → **Segmentation fault**.

**Root cause.** `narrow-apply` gates on `Sym.is-local` (`nucleusc.nuc:1505`), but
`defvar` registers globals with **`is-local = 1`** (`nucleusc.nuc:7993`, and
`:8396`). The flag means "is a variable slot", not "is frame-local". The
authoritative test already exists and is documented 1900 lines away, where escape
analysis gets it right:

> `nucleusc.nuc:3387-3388` — "note defvar globals carry is-local=1, so
> `home != g-globals` is the authoritative test, not is-local."

**Fix.** In `narrow-apply`, replace the `is-local` gate with `(!= (sym home)
g-globals)`. Two lines.

**Blast radius: zero.** `grep` for `?`-typed globals returns **0 hits** in
`src/`, `lib/`, and the entire Doom port. Nothing can currently be relying on
this.

### N-BUG-2 — an **address-taken** local narrows across a write through its address

```lisp
(defn clear (pp:ptr:?ptr:Sector):void (ptr-set! pp null))
(defn u2 (m:?ptr:Sector):i32
  (when (!= m null)
    (clear (addr-of m))
    (return (use m)))             ; accepted today → segfault
  -1)
```
`$ ./u2` → **Segmentation fault**.

**Root cause.** The kill set is textual `set!` only (`prescan-kill-sets`,
`nucleusc.nuc:1645`) plus the `emit-set` backstop. A write through a pointer
obtained from `(addr-of m)` is neither.

**Fix.** Mark the `Sym` when its address is taken — `emit-addr-of` and `.&` on a
binding slot set `Sym.addr-taken = 1` — and refuse to narrow such a binding
(`narrow-apply` returns early). Conservative and cheap. A per-function prescan is
*not* required if the mark is set at emit time and `narrow-apply` is only ever
consulted at or after the guard: the address-taking must be lexically visible
before it can be exploited within the same region. **Caveat to verify at
implementation time:** an address taken *after* the narrowing point but before
the use inside the same region (`(when (!= m null) (clear (addr-of m)) (use m))`)
requires the mark to also *kill* an existing narrow, not merely prevent a new
one. Implement it as both: set the flag **and** call `narrow-kill`.

This is the same hazard class as §4.3's field-read invalidation, which is why it
belongs to this design rather than to a separate bug ticket.

---

## 3. The empirical result: §3.3 is majority a discoverability failure

`as-ref` is the blessed `raw → ?T` launder — a pure relabel, no IR. Combined with
`when-some` it gives a fully checked narrowing of a `raw` field read **today**:

```lisp
(defn w1 (li:ptr:Line):i32
  (when-some (fs (as-ref (li frontsector)))    ; fs : ptr:Sector inside
    (return (use fs)))
  -1)
```
Compiles, runs, correct on both the non-null and null paths (`with=42
without=-1`). **Zero `unsafe/cast`.** The equivalent without `when-some` (P5) also
works:

```lisp
(let (bs:?ptr:Sector (li backsector))          ; raw→Maybe widening is allowed
  (when (!= bs null) (use bs)))                ; bs : ptr:Sector inside
```

### Census of the port (2026-07-31)

| Measure | Count |
|---|---|
| `unsafe/cast` total | **2113** |
| `unsafe/cast` to a `ptr:T`/`(ref T)` (the "narrowing shape") | **817** |
| …of those, in `let`-binding-init position (**compiler-forced**) | **317** |
| …in field-access head position (**not forced at all** — §1.1) | **47** |
| uses of `as-ref` | **0** |

`as-ref` appears in the docs only as a single table row
(`docs/special-forms.md:81`, `docs/builtins.md:966`) with no worked example, and
in the error text as the terse clause *"launder with (as-ref …) + narrowing"* —
which names the safe option and the unsafe option with equal weight, while only
the unsafe one can be applied without restructuring the code. A porter under time
pressure takes `unsafe/cast` every time. **That is a diagnostic and documentation
defect, and it is the single highest-leverage thing in this whole item.**

### What is genuinely missing after `as-ref`

Only the shape where the guard is written **outside** the binding — which is the
dominant C idiom and what all three Doom sites do:

```lisp
(when (!= (li frontsector) null)                       ; guard here…
  (let (sector:ptr:Sector (li frontsector))            ; …use here. Rejected today.
    …))
```

Converting this to the working form is mechanical but non-local (it inverts the
nesting). Closing it is what §4 designs.

---

## 4. The narrowing rule

### 4.1 Places

A **place** is a syntactic path expression that the rule can track. Exactly two
forms; anything else is not a place and never narrows.

* **`P-LOCAL`** — a bare symbol resolving to a `let`/`with` binding or a by-value
  parameter. *(Exists today: `node-binding-name`, `nucleusc.nuc:1564`.)*
* **`P-FIELD`** — a chain `(b f₁ f₂ … fₙ)`, `n ≥ 1`, where `b` is a `P-LOCAL` and
  every `fᵢ` is a **struct field name**, resolved statically, with no call, no
  index, and no computed component anywhere in the chain. *(New.)*

Its **key** is the spelling of the resolved path — base `Sym` identity plus the
interned field-name sequence. Two occurrences narrow together iff their keys are
equal. `(mo target)` and `(mo2 target)` are different places; `(a b c)` and
`(a b)` are different places (narrowing `(a b c)` says nothing about `(a b)`).

Deliberately **not** places: globals (§4.2 S3), array/index expressions
(`(aref v i)`), any expression containing a call, `deref`/`ptr-set!` results,
union arms, and anything reached through an elem-less bare `ptr` (there is no
static field there to key on).

### 4.2 Stability conditions

A place is **stable** over a region `R` (the code dominated by the guard, up to
the point of use) iff:

**For `P-LOCAL` `x`:**
* **S1** — no `set!` of `x` in `R`. *(Exists: `prescan-kill-sets` + `emit-set`
  backstop.)*
* **S2** — `x`'s address is never taken. **New; this is N-BUG-2.**
* **S3** — `x`'s home scope is not `g-globals`. **New; this is N-BUG-1.**

**For `P-FIELD` `(b f₁ … fₙ)`:** all of S1–S3 on `b`, plus, anywhere in `R`
between the guard and the use:
* **F1** — **no call of any kind.** Any `defn` call, generic/protocol dispatch,
  C `declare`d function, `funcall-ptr`, or macro-expanded form that lowers to a
  call. No purity analysis, no callee inspection. This is the conservative
  default and §4.5 says what could relax it.
* **F2** — **no store through any pointer**: `.set!`, `aset!`, `ptr-set!`, or a
  `set!` whose target is a field/element. Not type-filtered in v1 — any store
  kills every live `P-FIELD` narrow.
* **F3** — no `label`. *(Exists: `narrow-kill-all`, `nucleusc.nuc:6981`.)*
* **F4** — the region is not a loop body entered with the narrow already live.
  *(Exists for `P-LOCAL`; extend the `prescan-kill-sets` sweep to kill every live
  `P-FIELD` narrow whose base is assigned, and — because F1/F2 cannot be
  evaluated across a back-edge — **kill all `P-FIELD` narrows at any loop
  entry**.)*

**The rule.** Inside a region dominated by a test that proves a stable place
non-null, that place's type reads as `PTR-REF` (via `type-as-pkind`,
`type-utils.nuc:351`). Outside the region, or once any condition above is
violated, it reverts to its declared kind — permanently for that region (kills
are sticky via `kstamp`, `nucleusc.nuc:1536-1539`).

**`P-FIELD` narrowing is intra-region and short-lived by construction.** F1 in
particular means most `P-FIELD` narrows die within a few forms. That is
intended: it is what makes the rule sound without dataflow analysis, and §7 shows
it is still enough for the port.

### 4.3 What kinds may be narrowed

`PTR-MAYBE` → `PTR-REF`. *(Exists.)*

**`PTR-RAW` → `PTR-REF` is the open policy decision.** It is *sound* under the
same conditions — `raw` and `?T` are representationally identical and both gates
already key off `ptr-pkind`. It is a one-line change (`nucleusc.nuc:1507`). The
argument against is that `raw` is the language's declared **waiver**: its whole
contract is "the compiler is not reasoning about this pointer", and narrowing it
quietly makes `raw` a second, weaker `?T`, eroding the distinction the pointer
lattice exists to draw.

**Recommendation: do not narrow `raw`.** Instead make `as-ref` the one-token
opt-in (§8.1) and let the diagnostic teach it. This keeps exactly one meaning for
`raw`, keeps the audit story (`grep as-ref` = "checked launder",
`grep unsafe/cast` = "unchecked assertion" — which is what §3.3 asked for), and
still removes essentially all of the port's 317 forced casts. Revisit only if a
later port shows `as-ref` insertion is itself the friction.

### 4.4 What establishes a narrowing

All of these already extract facts through `test-true-nonnull` /
`test-false-nonnull` (`nucleusc.nuc:1578-1633`); the work is extending them from
`node-binding-name` to the place language of §4.1.

| Form | Narrows | Status |
|---|---|---|
| `(when (!= x null) …)` / `(if (!= x null) A B)` | `x` in the then-arm | exists for `P-LOCAL` |
| `(when (= x null) …)` / `(if (= x null) A B)` | `x` in the **else**-arm | exists |
| `(and (!= a null) E)` — and `(_and …)`, post-expansion | `a` inside `E` and inside the body | exists |
| `(or (= a null) E)` / `(not …)` | dual of the above | exists |
| `(cond (t₁ b₁) (t₂ b₂) …)` | each failed `tᵢ`'s false-facts hold for all later pairs | exists (`acc`, `nucleusc.nuc:6623`) |
| **`(when (= x null) (return …))`** → rest of the body | the whole enclosing region | exists (`after`, `nucleusc.nuc:6695`; requires every prior body to have terminated) |
| `while` condition | inside the loop body | exists (`nucleusc.nuc:6754-6762`) |
| `if-some` / `when-some` | the bound name in the then-arm | exists (§5) |
| `(set! x v)` where `v` is non-null | `x` after the assignment | exists (`nucleusc.nuc:6414`) |

The early-return guard is already the highest-value form and it already works —
for `P-LOCAL`. Extending it to `P-FIELD` is the single most valuable delta.

### 4.5 Invalidation, and what could relax later

**Conservative default (v1):** the union of S1–S3 and F1–F4 above. Any call, any
store, any loop entry, any `label`, any `set!` of the base, any address-take.

Relaxations, in increasing order of cost, all explicitly **deferred**:

* **R1 — type-directed store filtering.** F2 currently kills on any store. It
  could kill only stores whose destination type could alias the narrowed field's
  containing struct. Cheap, and would help chains like `(.set! sector linecount
  …)` (a store to an `i32` field) not killing a `(li frontsector)` narrow.
* **R2 — callee effect summaries.** F1 could consult a computed "writes no
  pointer field of type T" summary. This is real interprocedural analysis and is
  a **non-goal** (§9); recorded only so the boundary is explicit.
* **R3 — an explicit `(assume-stable …)` region.** A user-visible escape hatch
  that suspends F1/F2 over a block. Rejected for v1: it is `unsafe/cast` with
  extra steps and reintroduces exactly the auditability problem §3.3 complains
  about.

---

## 5. The `if-some` desugaring analysis — verdict: **reject, and invert**

The brief asks whether flow narrowing can be a *shorthand that desugars to*
`if-some`, and flags `(Maybe ptr)`'s niche encoding + the Stage 11
"pointer element types cannot `match`" limitation as a possible blocker.

**The named blocker does not apply.** Reading `emit-if-some`
(`src/union-emit.nuc:377-421`): for a pointer operand, `if-some` never reaches
`match`. It allocas a slot, stores the value, defines the binder, synthesizes the
node `(!= x null)`, wraps it in a `cond`, and calls `emit-cond`. The niche
encoding is irrelevant because the tagged-sum eliminator is never invoked.

**But the route is still rejected, for a stronger reason: the dependency already
runs the other way.** `emit-if-some`'s own comment states it:

> `union-emit.nuc:378-381` — "desugar to cond: the synthesized `(!= x null)` test
> **is the standard narrowing point**, so x reads as (ref T) exactly inside the
> then arm … Reuses cond's phi typing, fall-through, and after-the-form narrowing
> rules wholesale."

`if-some` is **built on** `narrow-apply`. Desugaring narrowing into `if-some`
would be circular — and would be strictly worse even if it terminated, because
`if-some` introduces a **binding**, and a binding is precisely what `P-FIELD`
narrowing exists to avoid needing. It also cannot express the early-return guard
(`(when (= x null) (return …))` narrows a region with no then-arm to bind into),
which §4.4 identifies as the highest-value form.

Two further facts settle it:

* `emit-if-some` **hard-requires `PTR-MAYBE`** (`union-emit.nuc:397-398`,
  *"value must be (Maybe (ref …)) — launder a raw pointer with (as-ref …)"*). A
  desugaring of a `raw`-typed guard would have to synthesize the `as-ref` itself,
  i.e. re-decide §4.3 invisibly.
* `emit-if-some` emits an `alloca` + `store` per site (`union-emit.nuc:401-402`).
  Desugaring every guard through it would put a stack slot behind every null
  check in the language.

**Verdict:** flow narrowing is the primitive. `if-some`/`when-some` remain sugar
over it. W6 extends the primitive; `if-some` inherits any improvement for free.
The relationship documented in `docs/types.md:82-92` is already correct and needs
no change.

---

## 6. Diagnostics

Per this item's own brief, **this matters more than the narrowing itself**. The
current message is the reason the port has 2113 `unsafe/cast`s and 0 `as-ref`s:
it names the safe and unsafe routes in one undifferentiated clause and shows
neither.

Today (`type-utils.nuc:413`):
```
assignment: raw pointer where non-null (ref ...) is required — launder with
(as-ref ...) + narrowing, or assert with (unsafe/cast (ref T) ...)
```

### 6.1 The rule: say which condition failed, and name the place

Every "cannot narrow here" message must answer three questions: **what place**,
**which condition**, **what to write instead**. `pkind-flow-check` is the single
site (`type-utils.nuc:401`), so all of these are produced in one function — but
it needs two new inputs threaded from the caller: the **place key** of the source
expression (or none) and the **reason** the narrow is absent.

**D1 — a stable place, guarded, but invalidated by a call (F1).** The flagship
message; this is the spec's own example.
```
p_map.nuc:946: error: argument: `(tmt target)` may be null.
  It was proven non-null at p_map.nuc:931, but `P_Random` was called at
  p_map.nuc:945 and a call may store through any pointer, so a field read is
  no longer known non-null.
  Bind it while it is known non-null:
      (let (tt:ptr:Mobj (tmt target)) …)   ; at p_map.nuc:931, before the call
  or launder and narrow explicitly:
      (when-some (tt (as-ref (tmt target))) …)
```

**D2 — invalidated by a store (F2).**
```
error: argument: `(li frontsector)` may be null.
  It was proven non-null at line 519, but line 521 stores through a pointer
  (`aset!`), and a store may write any field, so the narrowing was dropped.
  Bind it before the store: (let (sector:ptr:Sector (li frontsector)) …)
```

**D3 — not a place at all.** The expression is not in the §4.1 place language.
```
error: assignment: `(aref (sector lines) j)` may be null and cannot be narrowed.
  Only a local binding, a parameter, or a chain of struct field reads from one
  of those can be tracked across a null check — an indexed element cannot,
  because the index may change.
  Narrow it through a binding:
      (when-some (li (as-ref (aref (sector lines) j))) …)
```

**D4 — a global (S3).** Directly the N-BUG-1 case, and the port's
`p_map.nuc:364` shape.
```
error: `ceilingline` is a global and may be null.
  A global is never narrowed by a null check: any call, and any other thread of
  control, may reassign it. Copy it into a local first:
      (when-some (cl (as-ref ceilingline)) …)
```

**D5 — address-taken (S2).** The N-BUG-2 case.
```
error: `m` may be null.
  A null check does not narrow `m` because its address is taken at line 8
  (`(addr-of m)`), so a call may write through that address.
```

**D6 — killed by reassignment (S1) / loop entry (F4) / `label` (F3).**
```
error: `m` may be null.
  It was proven non-null at line 12, but line 14 assigns to it, and the
  narrowing does not survive a reassignment.
```
```
error: `(mo target)` may be null.
  A field read is not narrowed inside a loop body: the loop re-enters, and on a
  later iteration the check has not run. Bind it before the loop, or re-check
  inside it.
```

**D7 — the `raw` case (§4.3), rewritten.** This replaces the message that
produced 2113 casts. It must lead with the checked route and *show it*:
```
error: assignment: `(li frontsector)` is a raw pointer, and `sector` is declared
  non-null (ptr:Sector).
  A raw pointer is not narrowed by a null check — `raw` means "unchecked".
  Launder it into a checked nullable and narrow:
      (when-some (sector (as-ref (li frontsector))) …)
  If you are asserting a fact the compiler cannot see, say so explicitly:
      (unsafe/cast ptr:Sector (li frontsector))
```

### 6.2 Positive requirements

* Every message that mentions a proven-non-null fact **cites the guard's
  `file:line`**. The narrowing engine must therefore record the line at which
  each fact was established (a field on the undo entry / place record). Without
  this, D1/D2/D6 degrade to the current puzzle.
* Every message shows **runnable replacement source**, not a description of one.
* `as-ref` is named **first**, `unsafe/cast` last and framed as an assertion.
* No message may be produced with a line of 0 — the suite's `run_no_line_zero`
  guard (W4) covers this and must be extended over the new messages.

---

## 7. Worked examples

### 7.1 ACCEPTED — `p_setup.nuc:517-526`, `p-group-lines` (defn at :495)

The site the finding names. `Line.frontsector`/`backsector` are `(raw Sector)`
(`r_defs.nuc:225-226`).

**Today:**
```lisp
(dotimes (i numlines)
  (let (li:ptr:Line (line-at i))
    (when (!= (li frontsector) null)
      (let (sector:ptr:Sector (unsafe/cast ptr:Sector (li frontsector)))   ; forced
        (aset! (unsafe/cast ptr:ptr:Line (sector lines)) (sector linecount) li)
        (.set! sector linecount (+ (sector linecount) 1))))
    (when (and (!= (li backsector) null) (!= (li frontsector) (li backsector)))
      (let (sector:ptr:Sector (unsafe/cast ptr:Sector (li backsector)))    ; forced
        …))))
```

**Under this design** — the `unsafe/cast`s vanish; nothing else moves:
```lisp
(when (!= (li frontsector) null)
  (let (sector:ptr:Sector (li frontsector))        ; narrowed: P-FIELD, F1/F2 hold
    (aset! …) (.set! sector linecount …)))
```

**Why it is accepted.** `(li frontsector)` is `P-FIELD` over `li`, a `let`-local
that is never `set!` (S1), never address-taken (S2), not a global (S3). Between
the guard and the use there is **nothing at all** — no call (F1), no store (F2).
The `aset!` and `.set!` come *after* the narrowed read and so cannot invalidate
it. The second guard is an `and`-chain, already supported by
`test-true-nonnull`'s `_and` arm (`nucleusc.nuc:1587-1590`).

Note this site is **inside a `dotimes`**, i.e. a loop body. F4 kills `P-FIELD`
narrows at loop *entry*; it does not forbid establishing one *inside* the body,
which is what happens here. This distinction must be implemented precisely.

### 7.2 ACCEPTED — `p_map.nuc:426-429`, `P_ZMovement` (defn at :416)

```lisp
(when (and (!= (bit-and (mo flags) MF_FLOAT) 0) (!= (mo target) null))
  (when (and (= (bit-and (mo flags) MF_SKULLFLY) 0) (= (bit-and (mo flags) MF_INFLOAT) 0))
    (let (tgt:ptr:Mobj (unsafe/cast ptr:Mobj (mo target)))                 ; → (mo target)
      …)))
```

**Why it is accepted, and why it matters.** The guard and the use are separated
by an entire nested `when` whose condition performs **two field reads and two
`bit-and`s**. None of those is a call or a store, so F1 and F2 hold and the
narrow survives. This is the example that shows the rule is not so brittle as to
be useless: intervening *pure computation* — the common case between a guard and
its payload — does not kill a narrow. Only calls and stores do.

### 7.3 ACCEPTED at the binding, REJECTED at the later use — `p_map.nuc:931-946`, `PIT_CheckThing` (defn at :908)

```lisp
(when (and (!= (tmt target) null)                                    ; guard, :931
           (let (tt:ptr:Mobj (unsafe/cast ptr:Mobj (tmt target)))    ; :932 → ACCEPTED
             (or …)))
  (when (= (unsafe/cast ptr:Mobj thing) (unsafe/cast ptr:Mobj (tmt target)))   ; :937
    (return 1))
  …
  (let (damage:i32 (* (+ (% (P_Random) 8) 1) ((tmt info) damage)))    ; :945 — CALL
    (P_DamageMobj (unsafe/cast (raw Mobj) thing) tmthing (tmt target) damage)))  ; :946
```

* **`:932` — accepted.** The `and`-chain proves `(tmt target)` non-null in
  conjunct 1; conjunct 2 is the binding, with no call or store between. Cast
  removed.
* **`:937` — no narrowing needed at all.** `(tmt target)` is only compared with
  `=`; it never enters a non-null slot. Both `unsafe/cast`s on this line are
  *already* unnecessary today (§1.1) and `as` would accept them.
* **`:946` — correctly rejected.** `P_Random` is called at `:945`, so F1 fails
  and the narrow is dead. This is **exactly the unsoundness the brief warns
  about**, occurring in real port code, and the rule catches it. It is also the
  site that produces diagnostic **D1**.
  *And note the punchline:* `P_DamageMobj`'s parameters are all `(raw Mobj)`
  (`p_map.nuc:2152`), so `:946` needs **no narrowing whatsoever** — the
  `unsafe/cast (raw Mobj)` on `thing` is a ptr→raw *widening* that plain `as`
  accepts. Two of the three casts on this line were never required.

### 7.4 REJECTED — `p_map.nuc:360-365`, a narrowed **global**

```lisp
(if (and (and (!= ceilingline null)
              (!= (unsafe/cast ptr:Line ceilingline) null))
         (and (!= ((unsafe/cast ptr:Line ceilingline) backsector) null)
              (= (as i32 ((unsafe/cast ptr:Sector ((unsafe/cast ptr:Line ceilingline) backsector)) ceilingpic))
                 skyflatnum)))
    …)
```

`ceilingline` is a **global** (`p_map.nuc:200`, `(raw Line)`). Rejected by S3:
no narrowing, ever, regardless of guards. Diagnostic **D4**. The required
rewrite copies it into a local once:

```lisp
(when-some (cl (as-ref ceilingline))
  (when-some (bs (as-ref (cl backsector)))
    (when (= (as i32 (bs ceilingpic)) skyflatnum) …)))
```

This site is also the clearest argument for fixing **N-BUG-1** before widening
anything: today, had `ceilingline` been declared `?ptr:Line`, the compiler would
have narrowed it and accepted a use that any intervening call could invalidate.
The port's redundant double-null-test on lines 362-363 suggests the author did
not trust the guard either.

### 7.5 REJECTED — synthetic, the spec's own counterexample

```lisp
(when (!= (mo target) null)
  (some-call-that-may-clear-target mo)
  (let (t:ptr:Mobj (mo target)) …))          ; F1 fails → rejected, diagnostic D1
```

### 7.6 REJECTED — indexed element

```lisp
(when (!= (aref (sector lines) j) null)
  (let (li:ptr:Line (aref (sector lines) j)) …))   ; not a place → D3
```
`j` may change; an indexed element is outside the §4.1 place language by
construction.

---

## 8. Implementation sketch

Four tiers. **Each is independently shippable, and they are ordered by
value-per-unit-risk — which is the reverse of the order the finding implies.**
Tiers 0 and 1 together are expected to remove the large majority of the port's
317 forced casts without any new analysis at all.

### 8.0 Tier 0 — diagnostics and documentation *(no new capability; highest value)*

* Rewrite `type-utils.nuc:413` and `:412` per **D7** and §6: lead with
  `as-ref`/`when-some`, show runnable replacement source, frame `unsafe/cast` as
  an assertion. `pkind-flow-check` needs the offending source expression's
  spelling threaded in from its three callers (`abi.nuc:580`,
  `nucleusc.nuc:3785`, `:6160`) to name the place.
* Add a worked "narrowing a nullable pointer" section to `docs/types.md`
  alongside the existing §"Flow narrowing" (`docs/types.md:82-92`), with the
  `as-ref` + `when-some` recipe. `as-ref` currently has no example anywhere.
* Files: `src/type-utils.nuc`, `src/abi.nuc`, `src/nucleusc.nuc`, `docs/types.md`,
  `docs/special-forms.md`, `docs/builtins.md`.

### 8.1 Tier 1 — fix the two soundness bugs *(prerequisite for Tiers 2-3)*

* **N-BUG-1**: `narrow-apply` (`nucleusc.nuc:1505`) — swap the `is-local` gate for
  `(!= (sym home) g-globals)`. Add diagnostic **D4**.
* **N-BUG-2**: add `Sym.addr-taken` (`compiler-types.nuc`, beside `is-local` at
  `:301`); set it in `emit-addr-of` and the `.&` path; make `narrow-apply` refuse
  **and** `narrow-kill` an existing narrow when it is set. Add **D5**.
* Regression tests: the two segfault probes in §2, as compile-failure tests.
* Blast radius: zero (`?`-typed globals: 0 in `src/`, `lib/`, and the port).
  Expect a byte-identical bootstrap.

### 8.2 Tier 2 — the place language and `P-FIELD` narrowing *(the real feature)*

The change is concentrated because the engine already exists. Five edits:

1. **Place keys.** New `place-key` helper beside `node-binding-name`
   (`nucleusc.nuc:1564`): returns an interned key for a `P-LOCAL` or `P-FIELD`
   node, else null. Must resolve field names through the same interning the
   struct-field path uses (`context/conventions.md`, struct-field interning) so
   two spellings of one path produce one key.
2. **Fact extraction.** `test-true-nonnull` / `test-false-nonnull`
   (`nucleusc.nuc:1578-1633`) call `place-key` instead of `node-binding-name`.
   The accumulators stay `(Vector ptr)` of keys. No structural change.
3. **Narrow state.** `P-LOCAL` narrows stay on `Sym.ntype`. `P-FIELD` narrows
   need a **per-function place table** (key → narrowed `Type*` + establishing
   line), with the same mark/restore/kstamp discipline as `g-nundo`
   (`nucleusc.nuc:1494-1533`). Reuse `NarrowUndo` with a key field rather than
   inventing a parallel stack.
4. **Reads.** This is the lockstep-critical edit — see §8.5.
5. **Invalidation.** F1: a kill-all-`P-FIELD` hook at every call-emission site;
   the cheapest sound placement is a single call inside the common call emitter
   rather than at each of its callers. F2: the same hook from `.set!`, `aset!`,
   `ptr-set!`. F4: extend `prescan-kill-sets` (`nucleusc.nuc:1645`) and kill all
   `P-FIELD` narrows at `emit-while` entry (`nucleusc.nuc:6739`).

Files: `src/nucleusc.nuc` (the engine, `emit-cond`, `emit-while`, `emit-label`,
the call emitter, the store paths), `src/type-utils.nuc` (diagnostics),
`src/compiler-types.nuc` (`NarrowUndo` field), `src/generics.nuc:3692` (the
type-side reader).

### 8.3 Tier 3 — deferred

R1 (type-directed store filtering) and the §4.3 `raw`-narrowing policy, if the
next port shows Tier 0-2 insufficient. R2 is a non-goal.

### 8.4 Test plan

* The full §7 matrix as fixtures: four accepted, three rejected, each asserting
  the **exact diagnostic text**, not merely that it failed.
* The §2 segfault probes as compile-failure tests.
* Extend `run_no_line_zero` over every new message.
* The real gate, per this stage's definition of success: rebuild the Doom port
  with its `unsafe/cast`s removed at the §7 sites and confirm both demo gates
  stay bit-exact.
* Byte-identical bootstrap through Tier 1; Tier 2 changes no compiler IR unless
  the compiler's own source has a narrowable `P-FIELD` guard — it should be
  checked, not assumed.

### 8.5 The `node-type` ↔ `emit-node` lockstep

`context/conventions.md` records this as the repo's standing hazard, and W2's
resolution was to make the rule live in **exactly one function that both sides
call**. **For narrowing that discipline is already in place and must not be
broken:** `sym-effective-type` (`nucleusc.nuc:1489-1492`) is the sole accessor,
read by the emit side (`nucleusc.nuc:1889`, `:6057`) and the type side
(`generics.nuc:3692`, `nucleusc.nuc:4666`).

Three concrete obligations for Tier 2:

1. **Add exactly one new accessor** — `place-effective-type (key, declared)` —
   consulted by *every* reader of a field-read's type, on both sides. Under no
   circumstances may the emit path consult the place table directly while
   `node-type` recomputes the declared type; that is precisely the W2 bug class,
   and it would be worse here because it produces a *silent miscompile* (an
   unchecked null flowing into a `ref` slot) rather than a rejection.
2. **Preserve the ordering invariant.** Narrowing state is mutated *during the
   emit walk* (`emit-cond` calls `narrow-names` as it emits each arm) — there is
   no separate analysis pass. Any `node-type` query about a narrowed place is
   therefore only valid at the same point in that walk. Tier 2 must not
   introduce a pre-pass that asks about narrowing before `emit-cond` has run,
   and any new caller must be audited against this.
3. **Make the gate observable.** The two `narrow-apply` gates
   (`nucleusc.nuc:1505,1507`) and the new F1/F2 kills should record *why* a
   narrow was refused, so §6's diagnostics report the actual reason rather than a
   guess. A diagnostic that guesses the reason will drift from the rule, which is
   the same failure mode one step removed.

---

## 9. Non-goals

Explicitly out of scope, and not to be reintroduced by an implementation prompt:

* **Full dataflow analysis.** No CFG construction, no fixpoint, no dominator
  computation. The design is deliberately a syntactic, emit-time, region-scoped
  rule — which is what makes it implementable inside the existing single-pass
  emitter.
* **Nullability inference across function boundaries.** Signatures and struct
  fields are where nullability is *declared* (`design/stage10/nullability.md §5`).
  Narrowing is and stays intraprocedural.
* **Callee effect summaries / purity analysis** (R2). F1's "any call kills a
  `P-FIELD` narrow" is the permanent v1 rule.
* **Alias analysis.** F2 kills on any store. R1 is the only relaxation ever
  contemplated and it is deferred.
* **`?T` monad ergonomics** — no `map`/`and-then`/`?.`-style chaining, no
  auto-propagation. `if-some`/`when-some`/`unwrap`/`unwrap-or` are the surface.
* **Narrowing through indexed elements, unions, or elem-less bare `ptr`.**
* **Changing `raw`'s meaning.** §4.3 recommends against narrowing `raw`; if a
  later stage revisits it, that is a language-design decision requiring its own
  document.
* **Making `(defvar g:ptr:T null)` work.** §1.5 — that is a hole to close, not a
  feature to extend. Dispatched separately, after W5c.

---

## 10. Accept criteria for the eventual implementation

* The §7 matrix passes with exact-text diagnostic assertions: 7.1, 7.2, 7.3(:932)
  accepted; 7.3(:946), 7.4, 7.5, 7.6 rejected.
* The two §2 segfault probes become compile-time errors.
* `as-ref` has a worked example in `docs/types.md`; the `raw`-into-`ref` message
  leads with it.
* No new message can report line 0 (`run_no_line_zero`).
* The compiler self-compiles; bootstrap is byte-identical through Tier 1.
* The Doom port rebuilds with the §7 casts removed and both demo gates stay
  bit-exact.

## 11. Open questions for the implementer

1. **F4 loop precision.** §7.1's accepted site is *inside* a `dotimes`. The rule
   must kill `P-FIELD` narrows carried *into* a loop while still allowing one to
   be established *within* the body. Confirm `emit-while`'s existing
   mark/restore (`nucleusc.nuc:6754-6762`) gives this for free, or make it
   explicit.
2. **N-BUG-2's kill-vs-refuse ordering** (§2) — verify the address-take that
   occurs *after* the guard but *before* the use is caught.
3. **`dotimes`/`doseq` lowering.** These are macros; confirm they lower to
   `while`/`label` such that F3/F4 fire. `emit-label`'s `narrow-kill-all`
   (`nucleusc.nuc:6981`) may already cover it, in which case F4 is partly
   redundant — measure rather than assume.
4. **W5c interaction** (§1.5) — `pkind-flow-check` treats `CStr` as
   ref-compatible (`type-utils.nuc:384-388`); the tightened global gate must not
   re-reject `(defvar g:CStr null)`.
