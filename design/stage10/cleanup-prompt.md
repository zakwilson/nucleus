# Stage 10 — Cleanup & deferred items: implementation prompt

You are finishing the **deferred tail of Stage 10**. The four feature areas
below are the items left open after the unions (U1–U3), errors (E1–E4 reader),
nullability (N1/N2 first tranche), and safety-flip (Phase F) work landed. The
full design and rationale live in [unions.md](unions.md) and [errors.md](errors.md);
this file is the condensed, actionable spec — read those two when you need the
*why* (pointers given per phase), read this for *what to build and in what order*.

Skim the **implementation-status** sections before starting — they record exactly
what already exists and the deviations from the original design:
[unions.md](unions.md) "robot — implementation status" (U1–U3),
[errors.md](errors.md) §"robot — implementation status" (E1–E4 + flip),
[nullability.md](nullability.md) §9 (N1/N2 + flip, **especially the friction
findings**), and [progress.md](progress.md) (the Stage 10 tables).

## What's being finished

| Phase | Item | Source design | Scope |
|---|---|---|---|
| **C1** | N2 cold-site cleanup (~25 `cast ptr:Sym` waivers) | nullability.md §9 finding 5 | small, mechanical, byte-identical |
| **C2** | standalone `signal` (call a handler outside return position) | errors.md §4, §13 Q6 | small library + small compiler form |
| **C3** | E4 coercion-path adoption + panic-tier signal hook | errors.md §7.2, §4, §12 (E4) | medium; uses C2 |
| **C4** | the niche layout engine: **U4** + **A2** | unions.md §6, errors.md §2/§8 | large; the capstone |

**These four are largely independent.** C4 is the only invasive one; C1/C2/C3
do not depend on it, and nothing depends on C4. Recommended order is the table
order: C1 as a low-risk warm-up that re-acquaints you with the pointer-kind
machinery, C2 because C3's panic hook uses it, then C4 last. Each phase is
independently shippable and must leave the tree green; do not start C4 with C1–C3
half-done.

### Authoritative decisions (already resolved — do not re-litigate)

These were settled in the designer↔robot dialogues; they constrain the work:

1. **A1 is the built error model; A2 is an optimization the layout engine applies
   automatically** (errors.md §7.4, unions.md §6). A2 is *not* a separate type or
   surface form — `(Result (ref T) Err)` keeps its exact surface (`!`, `ok`/`err`,
   `match`, `try`), and C4 only changes its *representation*.
2. **Error ids are capped at 4095** (errors.md §8), already enforced by
   `deferror`, *specifically* to keep them in the top-page range A2's ERR_PTR
   encoding needs. No renumbering is required by C4.
3. **`pkind` is ignored by `type-eq` / `hash-type` / `type-mangle-token` /
   `type-to-ir`** (nullability.md §9, flip.md). This is the load-bearing
   invariant: a pointer's *kind* never changes emitted IR or mangling. C1 leans on
   it for byte-identity; C4 must preserve it for the niche kinds it adds.
4. **`die-at` is the panic tier and carries `noreturn`** (landed at flip Stage-1),
   so `(when (= x null) (die-at …))` already narrows past the guard. C1 and C3
   both exploit this.
5. **Niche layout reuses the existing pkind machinery as its implementation**
   (unions.md §6: "pkind remains as the implementation of those cases, now
   reachable from `defunion`"). C4 builds a *classifier* that dispatches to
   existing PTR-MAYBE machinery and one new ERR_PTR path — it does **not** build a
   parallel type system.

### Non-negotiable invariants (safety.md §2, errors.md §1)

- **Zero mandatory runtime cost.** Happy paths cost nothing new. A2's `is-err`
  is one unsigned compare on the error path; `signal`'s walk is paid only where a
  handler is bound.
- **C-ABI neutrality / consumable from C.** After C4, a `(Result (ref T) Err)`
  *is* a `T*` to C with a documented reserved top-page range (errors.md §2) — the
  same property `(Maybe (ref T))` already has. `&repr tagged` exists precisely so
  a C consumer can demand the predictable `{i32 tag; union}` struct instead.
- **Library where possible.** Keep `signal`'s chain walk in `lib/error.nuc`
  alongside the existing `Handler`/`err-find-handler`/`with-handler`; the compiler
  supplies only what needs the site's type (the typed handler call).
- **Bootstrap discipline.** After every phase: `make test` (examples + REPL
  sessions) and `make bootstrap` (stage1.ll == stage2.ll fixed point) must pass,
  and all boot artifacts (Linux + Windows IRs, `bin/nucleusc`) must re-converge in
  lock-step (build.md: `make clean && make && make update-bootstrap && make clean
  && make && make bootstrap`). C1/C2 are byte-identical (no codegen change). C3
  and C4 *deliberately convert code* and may require a converge round — each phase
  notes where, and that is the only place byte-identity is allowed to break.

---

## Phase C1 — N2 cold-site cleanup (the ~25 `cast ptr:Sym` waivers)

The cheapest item, and a warm-up. nullability.md §9 finding 5 left **~25 guarded
`(cast ptr:Sym (scope-lookup …))`-style sites** in colder paths still laundering
a nullable lookup into a non-null pointer with a raw `cast`, bypassing the flow
checker. Replace each with a `?Sym` binding narrowed by the site's existing
null-guard — now that `die-at` is `noreturn`, the guards already narrow.

### Where they are

Enumerate with `grep -n "cast ptr:Sym" src/nucleusc.nuc src/repl.nuc` (and the
analogous `cast ptr:StructDef` / `cast ptr:Method` / `cast ptr:Generic` /
`cast ptr:Protocol` lookup-result casts). The friction note names the clusters:
**defvar/defconst/inc-dec/addr-of emitters, the `gcheck`/`valid` walkers, and
`src/repl.nuc`**. Exclude the legitimate non-lookup casts — pointer *arithmetic*
over `(sc syms)` arrays (`(ptr+ (cast ptr:Sym (sc syms)) i)`) and the
`(.set! (cast ptr:Sym fsym) noreturn 1)` field-stores are not nullable-launders
and stay as they are. The targets are specifically `(cast ptr:Sym (scope-lookup
…))` / `(cast ptr:Sym (scope-define …))` where the cast is hiding a `?Sym`.

### The conversion

Per site, replace
```lisp
(let (sym:ptr:Sym (cast ptr:Sym (scope-lookup scope name)))
  …uses sym…)
```
with a `?ptr:Sym` binding plus narrowing — whichever the site already implies:

- If a `(when (= sym null) (die-at …))` (or `(return …)`) guard follows, bind
  `sym:?ptr:Sym` and keep the guard; `noreturn`/`return` narrows `sym` to
  `ref:Sym` for the rest of the scope automatically (nullability.md §4).
- If the site is genuinely "can't be null here, but the checker can't prove it"
  and has no guard, add `(if-some (sym (scope-lookup …)) …)` or `(when-some …)`.
- `scope-define` is **never-null** (it dies internally on failure, like
  `generic-resolve`) — bind its result `ref:Sym` directly, no cast, no guard.

**Byte-identical throughout** (decision §3): kind changes lower to the same IR.
After the batch: `make test`, `make bootstrap` fixed point, boot re-converged.
Update nullability.md §9 finding 5 to record the count remaining (target: zero in
the named clusters; note any deliberate hold-outs with the reason, e.g. a
correlated-field invariant like finding 4's `Cleanup.defer-scope`).

**C1 done when:** the named cold clusters carry no nullable-launder
`cast ptr:Sym`; bootstrap byte-identical; nullability.md §9 finding 5 updated.

---

## Phase C2 — standalone `signal`

errors.md §4 (C-lite) designed `signal` as "how low-level code asks high-level
code for *policy* without returning"; §13 Q6 deferred it from E3's v1 ("recoverable
later over the same chain"). Build it now over the **existing** handler chain.

### Surface

```lisp
(signal E RepairType)            ; → (Maybe RepairType)
(signal E RepairType detail)     ; detail:ptr, borrowed for the call
```

`signal` walks `g-handler-top` for a handler matching `(E, type-token(RepairType))`
— exactly `err-find-handler`'s key — and, on a match, applies the CL unbind rule
(save top, set top to `h->prev`, call, restore) and returns the handler's
`(Maybe RepairType)` result. `none` (handler declined, or no handler) is the
default. **Unlike `err`/`__err-handled`, `signal` is not tied to return position
and does not wrap the result in `(ok v)`** — it hands the `(Maybe T)` straight
back, so the caller decides what to do (continue in place, fall back, propagate).

This makes errors.md §4's arena-OOM shape expressible again — the motivating case:
```lisp
(when (= block null)
  (if-some (b (signal 'out-of-memory (ref i8) (cast ptr need)))
    (set! block b)                       ; a handler supplied a block: continue
    (do (perror "arena grow") (exit 1))))  ; declined: today's behavior
```

### Implementation

The typed handler call needs the site's `RepairType` for the cast (same reason
`__err-handled` is compiler-emitted, errors.md §11.4), so `signal` is a
**compiler-emitted form**, not a pure library fn. But it is *most* of
`emit-err-handled` with two pieces removed (no err-arm default, no `(ok v)`
re-wrap). **Refactor, don't duplicate:** extract the shared core of
`emit-err-handled` (src/nucleusc.nuc:~6340 `emit-err-handled` / the
`__err-handled` special form) into a helper that both call —

- `emit-handler-call(eid, repair-type, detail, scope) -> ref:Val` yielding a
  `(Maybe repair-type)`: compute `type-token(repair-type)` (the type's mangled
  name as a CStr — `type-mangle-token`, as the `with-handler` token at
  lib/error.nuc:67 does), call `err-find-handler`, and on a non-null handler do
  the save/restore + `abi-emit-struct-call` of the loaded `hfn` (callee, arglist
  `"ptr %ctx, ptr %detail"`, `info = abi-classify((Maybe T))`) — the exact
  Stage-8 struct-return path `emit-err-handled` already uses (not
  `emit-funcall-value`; see errors.md §"E3 landed" deviation 3). On a null
  handler, yield `none`.
- `emit-err-handled` becomes: build the `(err E)` default slot, call
  `emit-handler-call`, and on `(some v)` overwrite the slot with `(ok v)` — its
  current body, now delegating the walk/call.
- `emit-signal` is just `emit-handler-call` returning its `(Maybe T)` directly.

Register `signal` as a special form (the `(when (= hp 'signal) …)` dispatch
alongside `__err-handled` at src/nucleusc.nuc:~8578) and in the
no-argument-eval / head-symbol tables (the `type-token`/`make`/`err!` group at
:~4619 and :~8621), since its second operand is a **type**, not a value. Like
`with-handler`'s `type-token`, the `RepairType` operand is parsed as a type, not
evaluated. Gate nothing extra: `signal` only resolves when `(import error)` is in
scope (it references `err-find-handler`/`g-handler-top`), so the compiler's own
self-compile is unaffected — byte-identical until something *uses* `signal`.

The repair-type-must-be-a-value-type limitation from E3 applies (errors.md §"E3
landed" deviation: a `(Maybe (ref X))` niche-pointer repair isn't a struct, so
the struct-call path can't carry it) — document it, don't fix it here.

**C2 done when:** `(signal E T [detail])` walks the chain, calls a matching
handler under the CL unbind rule, and yields its `(Maybe T)`; `emit-err-handled`
shares the extracted core (no logic duplicated); a new `examples/signal.nuc`
exercises decline + repair (the arena-shape is the natural demo); bootstrap
byte-identical (compiler binds no handler); `make test` green.

---

## Phase C3 — E4 coercion-path adoption + panic-tier signal hook

E4 converted the **reader** (`lib/reader.nuc`) from `die-at` to `!T` returns
(errors.md §"Phase E4 landed"); the **emitter/coercion path was left** because
converting `emit-node` itself to `!ref:Val` cascades through ~74 emitters
(stage10/progress.md E4 row). This phase does the *tractable* remainder in two parts.

### Part A — convert contained recoverable coercion sites to `!T`

**Do not convert `emit-node` or the `emit-*` spine.** "Where practical"
(the directive) means: leaf checks whose immediate caller can absorb a `Result`
without forcing the whole emitter to thread it. Follow the **reader's exact
pattern** (it is the template, errors.md §E4): a recoverable diagnostic becomes
`(do (report-at line msg) (return (err! <a-deferror>)))`, internal calls
propagate with `try`, success wraps with `(ok …)`. Use `report-at` (lib/reader.nuc:45)
so the human-readable `path:line` + `g-mono-context` diagnostic is printed at the
fault site byte-for-byte as today; the propagated `Err` is only the value-channel
signal. Use `err!` (not `err`) — a coercion type-mismatch is not a negotiable
condition.

Candidate self-contained sub-pipelines (audit before committing — pick ones whose
callers form a closed set you can convert together):

- the `coerce-int-val` / `coerce-num-val` / `safe-coerce-val` family already
  returns `?Val` (null = failure) — their *callers* that turn a null into a
  `die-at` are the conversion targets;
- a contained validation helper cluster where the call graph is shallow.

Each converted function gets `(import error)` (already transitively in the
compiler via the reader) and a `(deferror …)` for its condition class. Convert
**one closed sub-graph at a time**, `make test` + bootstrap after each. This is
byte-identical *only* if no codegen path changes; realistically a converted
return type changes call sites, so expect a converge round — that is allowed here
(a deliberate conversion), verify the boot re-converges.

Be honest about the ceiling: most of the ~345 `die-at` sites in
`src/nucleusc.nuc` are **unrecoverable bugs** and *should stay `die-at`* (the
panic tier, decision §4). The goal is to move the genuinely-recoverable
*compile-input* errors (bad coercions, malformed user forms) onto `!T`, not to
eliminate `die-at`.

### Part B — the panic-tier signal hook (uses C2)

errors.md §4 ("the panic tier gets a hook for free") and the §"Reference" note:
`unwrap` / `die-at` can `signal` a condition **before** aborting, so a REPL or
test harness can log, pretty-print, or record the error first. With C2's
`signal` now built, add the hook:

- Before `die-at` (and `unwrap`-on-`err`) abort, `signal 'unhandled-error` with a
  `detail` carrying the message (a `ptr` to the formatted string), `(Maybe void)`
  / a trivial repair type — declined-by-default, so absent a handler the behavior
  is exactly today's abort.
- This is the one place a handler is *consulted on the panic path*; it must not
  change behavior when no handler is bound (the chain walk returns `none` →
  fall through to abort). Keep it gated on `error-lib-in-scope` so the compiler's
  own `die-at` sites emit no extra code during self-compile (byte-identical).

The REPL is the obvious first beneficiary — it can bind an `'unhandled-error`
handler to record the diagnostic before the existing `repl_throw` boundary fires
(this is CL's debugger-hook, errors.md §4). Wiring the REPL to use it is optional
polish; the hook's *presence* (off by default) is the deliverable.

**C3 done when:** at least one closed coercion/validation sub-graph returns `!T`
with diagnostics byte-preserved via `report-at`; `die-at`/`unwrap` signal
`'unhandled-error` before aborting (no-op without a handler); `make test` green,
boot re-converged; the remaining `die-at` sites are confirmed as the intended
panic tier (note the count in errors.md / stage10/progress.md).

---

## Phase C4 — the niche layout engine (U4 + A2)

The capstone and the convergence step both designs point at: **U4** (unions.md §6
+ §9, the `&repr` control and niche rules 1–3) and **A2** (errors.md §2/§8, the
ERR_PTR encoding) are the *same layout-rule engine*. Today `Result`/`Maybe` over
pointers are still emitted as fat `{i32 tag; union}` structs (stage10/progress.md U4/A2
rows); this phase makes the layout engine niche-encode the pointer cases, so
`(Maybe (ref T))` *is* a bare nullable pointer and `(Result (ref T) Err)` *is* a
bare ERR_PTR-tagged pointer — both ABI-identical to `T*` at the C boundary.

Read **unions.md §6** (the four ordered rules) and **errors.md §2 "A2"** + **§8**
(the encoding and the id cap) before starting.

### The classifier (the engine)

Add `union-layout-classify(arms) -> {LAYOUT-ENUM, LAYOUT-NICHE-MAYBE,
LAYOUT-NICHE-ERRPTR, LAYOUT-TAGGED}`, consulted in `defunion-register`
(src/nucleusc.nuc:1751, right before the `{tag, payload}` backing struct is built
at :1838) and at template-stamp time (`union-template-stamp-types`, :1941).
Apply unions.md §6's rules **in order**:

1. **All arms payload-less** → `LAYOUT-ENUM`: just the `i32` tag (≅ `defenum`).
2. **Exactly two arms, one payload-less, one a single `(ref T)` field** →
   `LAYOUT-NICHE-MAYBE`: a bare pointer, `null` = the payload-less arm. This is
   *already* what `(Maybe (ref T))` produces (the N1 PTR-MAYBE niche, a parser
   special case at src/nucleusc.nuc:~1939). The engine must produce the
   **identical** `TY-PTR(elem=T, PTR-MAYBE)` representation so it stays
   byte-identical — i.e. dispatch to the existing pkind machinery, do not
   reimplement.
3. **Exactly two arms, one a single `(ref T)` field, one a single `Err` field**
   → `LAYOUT-NICHE-ERRPTR`: a bare pointer with the ERR_PTR encoding (new — see
   below). `(Result (ref T) Err)` then *is* A2's `!T`.
4. **Otherwise** → `LAYOUT-TAGGED`: the existing §3 `{i32 tag; union}` struct,
   unchanged.

**`&repr tagged` forces rule 4** (suppresses niching) — the opt-out a C consumer
that constructs the union wants (unions.md §6, §9). Spelling: a trailing `&repr
<mode>` marker on the `defunion` form, parsed in `defunion-register`'s arm loop
(skip it as a non-arm marker, like `&where`/`&rest` are handled elsewhere). The
design doc's prior spelling was `:repr`; the directive uses **`&repr`** — adopt
`&repr`, supporting at minimum `&repr tagged`; accept `&repr niche` as "require a
niche, error if the arms aren't nicheable" if cheap. The high-bits / alignment-
padding niches the directive muses about are **explicitly out of v1 scope**
(unions.md §6: "anything cleverer … is explicitly out of scope") — `&repr` is the
*extensible surface* those would later plug into; v1 implements rules 1–3 + the
`tagged` opt-out only.

### Byte-identity guard (read this carefully)

The compiler's *own* in-tree consumer of `!T` is the reader, which returns
`!ptr` (`(Result ptr Err)`). Bare `ptr` post-flip is non-null but **elem-less
(`void*`)**. **Restrict rule 3 (and rule 2) to a *typed* `(ref T)` ok payload
(elem present, non-void).** An elem-less `(Result ptr Err)` then stays
`LAYOUT-TAGGED` — so the reader's representation does **not** change and the
bootstrap stays byte-identical. This mirrors the flip's `void*` exemption
(nullability.md §9.1: a non-null obligation on a pointer with no pointee protects
nothing; here, a niche over a typeless pointer buys nothing and would needlessly
churn the reader). A2 is then exercised by new examples with a typed `(ref T)`
ok arm, exactly its intended "special-case optimization" role (errors.md §7.4).

If you find a way to niche the reader's `!ptr` too, that is a *deliberate*
conversion requiring a converge round and re-verification of every reader
`match`/`try` site — not recommended for this phase; keep the elem-less exemption.

### The ERR_PTR encoding (rule 3, the new code)

Per errors.md §2 "A2" and §8 (ids capped 1..4095, in the top page):

- **`(ok p)`** where `p:(ref T)` → store `p` directly. `p` is non-null (the flip
  guarantees it) and never in the top page, so it can't collide with an error.
- **`(err E)`** → `inttoptr(0 - zext(E to i64))` — a pointer in `[-4095, -1]`,
  i.e. the top page (`0xFFFF…F001 .. 0xFFFF…FFFF`). Id 0 ("no error") maps to
  `null`, which is never a valid `(ok)` either, so it's a safe sentinel.
- **`is-err(r)`** → `icmp uge (ptrtoint r), (0 - 4096)` — one unsigned compare
  against `0xFFFF…F000`. A valid object address is never ≥ that, so this cleanly
  discriminates with no discriminant word.
- **extract the id** on the err arm → `0 - (ptrtoint r)`, truncated to `Err`'s
  `i32`.
- **`match`** on a `LAYOUT-NICHE-ERRPTR` value → branch on `is-err`; the `ok`
  arm binds `p = r` typed `(ref T)`; the `err` arm binds `e` as the extracted
  `Err`. `try` / `unwrap` / `unwrap-or` (already `Result`-aware, errors.md §E1)
  route through the same match lowering, so they need no new surface — only the
  *eliminator's* lowering switches on the layout.
- **`type-size`** of a `LAYOUT-NICHE-ERRPTR` / `LAYOUT-NICHE-MAYBE` union is one
  pointer; **`type-to-ir`** is `ptr`; **`type-to-cheader`** is `T*` with a
  documented reserved-range comment. The pointer-ness must be invisible to
  `type-eq`/mangling exactly as `pkind` is (decision §3) — reuse a pkind-style
  kind (e.g. extend the niche representation with a PTR-ERRPTR pkind, or carry
  the layout on the `UnionDef` and key codegen off it). Whichever: changing the
  layout must not perturb mangling of *other* types.

Construction (`ok`/`err`/`make`), the handler-aware `__err-handled` err site
(errors.md §E3 — it builds `(err E)` and `(ok v)` via `emit-union-construct`),
and `match`/`unwrap` all branch on the layout: `LAYOUT-TAGGED` keeps today's
struct path; the niche layouts use the encodings above. `emit-union-construct`
(src/nucleusc.nuc:6266) is the natural chokepoint for ok/err construction.

### The `(Maybe (ref T))` convergence (rule 2)

Today `(Maybe (ref T))` is a parser special case (PTR-MAYBE), separate from the
value-`Maybe` template stamp. U4's goal (unions.md §6) is for the layout engine
to *own* the decision so `(Maybe (ref T))` and a `(defunion (Maybe2 T) (some
v:(ref T)) none)` stamp produce the same bits. **Minimum viable convergence:**
route the `defunion`/template-stamp path through `union-layout-classify`, and when
it returns `LAYOUT-NICHE-MAYBE`, produce the existing PTR-MAYBE representation.
You may leave the parser's `(Maybe (ref T))` fast path in place (it already
yields the right bits) — the deliverable is that *`defunion` stamping* now reaches
the niche, not that the parser special case is deleted. Deleting it is a nice-to-
have only if byte-identity holds.

### Staging C4 internally

1. The classifier + `&repr` parsing + `LAYOUT-ENUM`/`LAYOUT-TAGGED` (the latter
   is just "what happens today") — byte-identical, no behavior change yet.
2. Rule 2 reached from `defunion` stamping (dispatch to existing PTR-MAYBE) —
   byte-identical (same bits).
3. Rule 3 — the new ERR_PTR construct/match/is-err lowering, behind the
   typed-`(ref T)` guard so the reader is untouched. New examples
   (`examples/errptr.nuc` or extend `examples/errors.nuc`) with a typed `(ref T)`
   ok arm; a `tests/layout/` C-oracle case confirming `sizeof == sizeof(void*)`
   and the C-side `T*` round-trip; a REPL session if warranted.

**C4 done when:** `union-layout-classify` drives layout; `&repr tagged` forces the
struct; `(Maybe (ref T))` and `(Result (ref T) Err)` over a **typed** payload are
pointer-sized and C-legible as `T*`; `is-err`/`match`/`ok`/`err`/`try`/`unwrap`
work on the niche layout; the reader's elem-less `!ptr` is unchanged (bootstrap
byte-identical through stages 1–2, a deliberate converge round only if you niche
beyond the guard); `make test` green with new niche examples + a layout-oracle
case; boot re-converged.

---

## Explicitly out of scope (do not build)

- **Cleverer niches** — multi-arm niches, tag-in-high-bits, flag-bits-in-
  alignment-padding (unions.md §6). `&repr` is designed to admit them later; v1 is
  rules 1–3 + `&repr tagged`.
- **Converting the whole emitter to `!T`** (C3) — `emit-node` and the `emit-*`
  spine stay `die-at`/`ref:Val`; only closed recoverable sub-graphs convert.
- **`dyn`** for handler typing (errors.md §13.2) — a future musing.
- **`errdefer`**, **`if-ok`**, **exceptions** — all rejected/deferred in the
  errors design (errors-prompt.md "out of scope"); unchanged here.
- **Namespaced error names** — waits for namespaces (errors.md §8, §12 "later").

---

## Close-out checklist (required by AGENTS.md)

- **Docs.** Update [docs/builtins.md](../../docs/builtins.md): the "Unions and
  tagged sums" section for `&repr` and the niche layouts; the "Error handling"
  section for `signal` and A2's `T*` C-encoding contract; the pointer-kinds
  section if C1 changes any documented surface.
- **Design docs (designer↔robot convention).** Append/extend the "robot —
  implementation status" sections: U4 outcome in [unions.md](unions.md), A2 +
  `signal` + the E4 coercion increment in [errors.md](errors.md). Reconcile
  nullability.md §9 finding 5 (C1). Flip the U4/A2 and N2-cold-site rows in
  [progress.md](progress.md) from Deferred to Done with notes.
- **Context files** (AGENTS.md self-improving-context step): if C2/C4 surface a
  non-obvious build or JIT gotcha (e.g. the macro-JIT decl machinery, or a
  layout/ABI interaction), add a concise note to the right
  [context](../../context) file — fix root causes, document only inherent
  constraints.
- **Green tree after every phase.** `make test` + `make bootstrap` fixed point,
  all boot artifacts (Linux + Windows IRs, `bin/nucleusc`) re-converged. The
  compiler must compile itself. Never leave a stopping point unable to self-host.
