# Stage 14 — Macro conditionals without casts

Macros whose bodies *branch* — pick an expansion with `cond`/`if` based on
argument shape — currently need casts to compile: the arg-returning branch must
be wrapped `(cast ptr …)`, and (historically) every member access needed
`(cast ptr:Node …)`. Casts are undesirable: each one is a place a wrong type
can hide, and this particular pattern is the *first* thing anyone writing a
variadic or shape-dispatching macro hits. This doc pins down exactly why the
casts are required, and designs their removal.

Repro (verified 2026-07-02, current `build/nucleusc`):

```lisp
(defmacro my-or2 (a b)
  (cond (= b null)
          a                 ; (raw Node) — the macro param
        true
          `(_or ~a ~b)))    ; quasiquote — bare ptr
; → error: macro 'my-or2': returned null
```

The same macro compiles and runs correctly once the arg branch is spelled
`(cast ptr a)`.

---

## 1. Ground truth (all verified against the current tree)

1. **Macro params are already typed `(raw Node)`** — `emit-defmacro` builds a
   `TY-PTR{elem=Node, pkind=PTR-RAW}` for every param
   (src/nucleusc.nuc:7487-7504). Member access `(args car)`, `(args kind)`,
   and chains `((args cdr) car)` compile with **no cast**. Verified: a
   variadic `+`-clone with zero `(cast ptr:Node …)` compiles and runs; every
   `(cast ptr:Node args)` in `lib/macros.nuc` is **vestigial**.
2. **Quasiquote results are typed elem-less bare `ptr`** — `emit-qq-list`,
   `emit-qq-form`, and the quoted-atom path all `(alloc-val ty-ptr …)`
   (src/nucleusc.nuc:977-1007). `ty-ptr` is `TY-PTR{elem=null, pkind=PTR-REF}`
   (src/type-utils.nuc:32-34). Note the `PTR-REF` claim is already imprecise:
   `` `(~@empty) `` genuinely evaluates to null.
3. **`(gensym)` is also typed bare `ptr`** (src/nucleusc.nuc:6256-6259),
   though it always returns a fresh symbol `Node*`.
4. **The `null` literal is typed elem-less `raw`** — `ty-raw` =
   `TY-PTR{elem=null, pkind=PTR-RAW}` (src/nucleusc.nuc:1251,
   src/type-utils.nuc:36-37).
5. **`type-eq` distinguishes elem-less from typed pointers** — for `TY-PTR` it
   recurses into `elem`, and "untyped ptr has elem=null, distinct from typed
   ptr" (src/generics.nuc:103-129). Pointer *kinds* are **not** compared by
   `type-eq`; joins reconcile them with `pkind-meet` (raw ⊔ anything = raw;
   src/type-utils.nuc:245-248). (docs/macros.md currently overstates this —
   it claims the pointer kind must match too; see §6.)
6. **Value-position joins collapse to void on `type-eq` failure.** Three
   duplicated copies of the same logic: `emit-cond`
   (src/nucleusc.nuc:5326-5338), `match` over unions
   (src/union-emit.nuc:1073-1083), and the niche-match/if-some arm helper
   (src/union-emit.nuc:1436-1443). Once `result-type` collapses to void it
   stays void.
7. **A macro returns its last body value only if its type kind is `TY-PTR`**
   (src/nucleusc.nuc:7507-7516). A collapsed-to-void `cond` therefore makes
   the macro return the literal `null`, surfacing as
   `macro '<name>': returned null` at first expansion.
8. **Elem-less bare `ptr` is the `void*` escape hatch everywhere else** — it
   flows freely into typed slots and typed values flow freely into bare
   `:ptr` slots (`pkind-flow-check` exemption, src/type-utils.nuc:263-281;
   the Phase-F "untyped-pointer refinement"). The **join is the one place**
   where bare-vs-typed mixing is not absorbed but instead destroys the value.

The causal chain, in one line: *quasiquote and `gensym` produce bare `ptr`,
macro args produce `(raw Node)`, the cond join refuses to reconcile elem-less
with typed, the macro's return filter then discards the void result* — and the
user-visible symptom is "cast your branches to `ptr`".

## 2. Non-goals

- Branches of genuinely different types (`(raw Node)` vs `i32`, or
  `(ref StructDef)` vs `(ref Type)`) still collapse to void. That is a real
  type error; nothing here weakens it.
- No change to `type-eq` itself (see rejected alternatives, §5).
- No change to macro-expansion mechanics, hygiene, or the JIT module protocol.

---

## 3. Design

Two complementary fixes. **MC-1 alone removes the cast requirement**; MC-2
makes the types honest so the requirement cannot regrow.

### MC-1 — teach the join to absorb elem-less pointers (`type-join`)

Factor the three duplicated join-logic sites (ground truth #6) into one shared
helper next to `pkind-meet` in src/type-utils.nuc:

```
type-join(result-type, bty) → type
  ; existing behavior, unchanged:
  if type-eq(result, bty):    result (pkind-meet'd when TY-PTR)
  ; the new absorption rule:
  if both TY-PTR and exactly one side has elem=null:
                              (raw E)   where E = the typed side's elem
  ; existing behavior, unchanged:
  else:                       void
```

Rationale for `(raw E)` exactly:

- **Element type = the typed side's.** This is the join-site analogue of the
  flow-check exemption (ground truth #8): bare `ptr` is `void*`, and `void*`
  meets `T*` at `T*`. It follows the conventions.md guidance for mixed joins
  — "give the branch its real element type, never cast the typed side back to
  bare ptr" — but has the compiler do it instead of the programmer.
- **Pointer kind = `PTR-RAW`, unconditionally** (not `pkind-meet` of the two
  sides). The elem-less side's pkind is a Phase-F default, not an audited
  contract — quasiquote results are claimed `PTR-REF` yet can be null (ground
  truth #2). The join must not manufacture a non-null claim, so the absorbed
  result is nullable-unchecked `raw` — consistent with the stage-14
  raw-first-then-ref policy and with macro ergonomics (deref-allowed, no
  narrowing obligation).
- Two elem-less sides (e.g. `null` vs `` `(…) ``) are `type-eq` today (both
  elems null) and keep today's `pkind-meet` path — no behavior change.

With MC-1, `my-or2` above joins `(raw Node)` ⊔ bare `ptr` = `(raw Node)`,
whose kind is `TY-PTR`, so the macro-return filter (#7) accepts it. Every
`(cast ptr …)` branch-unification cast in `lib/macros.nuc` (`+`, `*`, `and`,
`or`) becomes removable, as do user-code idioms like
`(if (= (n kind) NODE-CELL) (n cdr) null)` into a typed slot.

`node-type` lockstep: `cond`/`match` are deliberately **unmodelled** in
`node-type` (they return null; codegen keeps its own type — the documented
escape hatch in context/conventions.md), so MC-1 has no generics.nuc partner
change. Confirm during implementation that no `node-type` branch models these
joins.

### MC-2 — type the Node producers: quasiquote and `gensym` as `(raw Node)`

Retype the results of `emit-qq-list` / `emit-qq-form` (both the cons-building
and quoted-atom paths) and the `gensym` special form from `ty-ptr` to
`TY-PTR{elem=Node, pkind=PTR-RAW}`:

- Quasiquote literally returns a `Node*` (possibly null, hence `raw`); this is
  the same truth-telling movement that retyped `Node.car`/`Node.cdr` and the
  macro params to `(raw Node)`. It makes qq results first-class node values:
  `(` `(a b)` `car)` chains directly, and pure-qq `cond`s type as `(raw
  Node)` end to end.
- Build the `(raw Node)` type the way `emit-defmacro` already does
  (`make-type TY-PTR` + `elem = (parse-type-name "Node" 0)` + `pkind
  PTR-RAW`), lazily on first use and cached in a global; **fall back to
  `ty-ptr` when `Node` is not registered** (an `(exclude-prelude)` program can
  still use quote forms).
- MC-2 **requires MC-1 to land first**: without absorption, retyping qq would
  *regress* the currently-working `(cond … null … `(…))` mix (elem-less raw
  vs `(raw Node)` fails `type-eq`). With MC-1 the mix absorbs to `(raw
  Node)`.
- Plain `'form` quote results share the quoted-atom path and get the same
  type. This should be inert — quote results are compared with `=` (pointer
  identity; both sides TY-PTR kind → same `icmp`, no CStr/strcmp hazard) and
  bound into bare `:ptr` locals (exempt flow) throughout the compiler — but
  it is the widest-blast-radius part of MC-2; if implementation turns up a
  regression, scope quote-atoms out and keep qq+gensym only.

### MC-3 — cleanup: retire the casts and the workaround idioms

- `lib/macros.nuc`: delete all vestigial `(cast ptr:Node …)` member-access
  casts (removable **today**, independent of MC-1 — verified); after MC-1,
  delete the `(cast ptr …)` branch casts in `+`, `*`, `and`, `or`; retype the
  node-holding `:ptr` locals (`acc`, `cur`, `rest`, `result`, the gensym
  bindings) to `(raw Node)` where natural.
- `tests/`: the `repl-redefinition` test macros keep their casts on purpose?
  No — migrate them too; casts remain *valid* (no-op reinterpret), so any
  stragglers elsewhere don't break.
- New test: `examples/macro-cond-nocast.nuc` — a castless variadic operator
  macro, a castless `(if … (n cdr) null)` slot init, and a shape-dispatching
  `tprint`-style macro, with expected output under `tests/expected/`.

### MC-4 — docs and context

- docs/macros.md §"Sharp edge": rewrite — the sharp edge becomes "branches of
  genuinely different *element* types still collapse"; drop the cast recipe;
  fix the pre-existing overstatement that pointer *kinds* must match (they
  meet, ground truth #5).
- docs/toplevel.md `defmacro` row: drop the cast caveat pointer.
- design/progress.md "Known constraints" bullet on the `(raw Node)` sharp
  edge: mark resolved by this work.
- context/conventions.md, Stage-10 N2 bullet 3 ("mixed cond/if joins
  collapse"): update — bare-ptr mixing now absorbs to `(raw T)`; only
  differently-*typed* joins collapse.

## 4. Verification and bootstrap convergence

- **MC-1 may change emitted IR** even for untouched source: a
  statement-position `cond`/`match` that mixes bare and typed pointer branch
  values today collapses to void (no phi) and would now emit a dead phi.
  Measure with the standard before/after IR diff on `build/nucleusc.ll`; if
  non-empty, run the reconverging refresh (`make clean && make && make
  update-bootstrap && make clean && make && make bootstrap`). Plausibly the
  diff is empty (mixing in statement position is pointless, and mixing in
  value position was an error people worked around) — then MC-1 is
  byte-identical and cheap.
- **MC-2/MC-3 follow the same gate**: `lib/macros.nuc` edits shift the string
  pool (documented conventions.md gotcha), so convergence needs the
  two-pass refresh regardless of semantic inertness.
- Full gates per phase: `make test` (all examples; includes the REPL
  `repl-redefinition` macro path, which the bootstrap fixed point does not
  exercise), `make bootstrap`, and the new castless-macro test.

## 5. Rejected alternatives

- **Wildcard `type-eq` (elem-less matches any pointer).** `type-eq` also
  drives multimethod registration/lookup (`params-type-eq`, `defn-ir-name`)
  and overload identity; a wildcard there would merge `(f ptr)` with
  `(f ptr:Node)` overloads. The absorption belongs at the *join*, not in the
  equality.
- **Special-casing the macro return path only** (accept/rewrap void conds in
  `emit-defmacro`). Fixes the symptom for whole-body conds only — nested
  conds, `let` inits, and non-macro user code keep the trap; and it would
  paper over a genuinely-typed error too.
- **Typing quasiquote as `?Node` (`PTR-MAYBE`).** Honest about nullability
  but hostile to macro code: every member access would demand narrowing.
  `raw` is the established macro-ergonomics pkind (precedent: params,
  `car`/`cdr`).
- **Absorbing to the elem-less side (join = bare `ptr`).** Sound but
  information-destroying, and directly against the conventions.md guidance
  ("never by casting the ref side back to bare ptr"); the result would not
  chain member access.

## 6. Sequencing and relationship to other stage-14 work

Independent of [type-safety.md](type-safety.md) phases and of
[defn-signature.md](defn-signature.md); touches only the three join sites, two
qq emitters, one special form, and lib/docs. Landing MC-1/MC-2 *before*
type-safety phase 14.3 (param/return typing) is mildly preferable: 14.3 will
retype many `:ptr` signatures to `(raw T)`/`(ref T)`, and every such retyping
increases the chance an existing bare-vs-typed join starts collapsing — MC-1
removes that whole failure class up front.

Order within this work: **MC-1 → MC-2 → MC-3 → MC-4**, with the build/test
gate after each. MC-3's vestigial-`ptr:Node`-cast deletions can land any time
(even before MC-1); the branch-cast deletions need MC-1.
