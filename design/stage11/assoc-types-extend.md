# Extend-site associated-type recovery (composable combinators)

**Status:** A4.0–A4.5 **done** (92 tests, byte-identical bootstrap). A4.5 extends
`defn &where` to support the compound `((Protocol Arg…) Var)` constraint form for
conforming variables that are free type parameters or previously-recovered tyvars
— the gap that blocked C2.1/C2.2b/C2.2c, now closed (`examples/assoc-iter-return.nuc`
compiles and prints `count=5`).

The A4.5 capability fell out of the A1/A4.0 machinery already in place rather than
requiring new inference: `parse-where-constraints` (src/nucleusc.nuc) already adds
every constraint's conforming variable to the tyvar set, so a bare free parameter
`C` in `(ref C)` (Case 1) and a tyvar recovered by an earlier constraint
(`It` in Case 2) are both registered tyvars by the time the determination fixpoint
in `register-generic-defn` runs. The fixpoint seeds `C` (determined by the
`(ref C)` parameter pattern via `pattern-determines-tyvar`), then recovers `It`
from `((IterColl It) C)`, then `E` from `((Iterator E) It)`. At dispatch,
`generic-method-bind` binds `C` from the argument type (`unify-tpat` on `(ref C)`
vs `(ref Span)`) and `recover-assoc-into` runs the same fixpoint to bind `It`/`E`
from the recorded conformances *before* `generic-constraints-ok` reads the bound
of the recovered var — so the recovered-conforming-var case (Case 2) resolves with
no extra code. The only outstanding work for A4.5 was operational: add the
expected-output fixture and refresh the committed bootstrap (the stale `bin/nucleusc`
predated the source fix). Byte-identical bootstrap holds because the compiler's own
source uses no compound `defn &where`, so the path is inert during self-compile (§9).

A4.3 made the `&where` clause survive `--emit-nuch` (`emit-nuch-extend` now emits
every node of the `extend` form, not just subject+protocol) and made the importer
re-run the template `extend` (`register-imported-conformance` delegates a
template-subject — `NODE-CELL` — extend to `emit-extend`, which re-parses the
`&where`, re-runs the determination fixpoint, and re-registers the
`TmplConformance`). Per-instance recovery (A4.2) then fires in the importing unit
when it stamps a concrete combinator. End-to-end cross-unit test:
`examples/assoc-types-extend-cross.nuc` imports the combinator through a committed
`.nuch` header (`lib/mapiterlib.nuch`, generated from
`tests/fixtures/mapiterlib.nuc`) and stamps `(MapIter IntRangeIter SqFn)` into a
generic `reduce` bounded on `((Iterator S) I)` — recovery of `E = i32` happens in
the importing unit, across the boundary (89/89 tests). The bootstrap stays
byte-identical because the only `.nuch` the compiler itself imports (`src/llvm.nuch`)
carries no template extends, so both new paths are inert during self-compile.

A4.2 made a `&where`-bearing template `extend` actually record the per-instance
`Conformance` with recovered associated args at stamp time. A stamped
`(MapIter IntRangeIter SqFn)` now records `Conformance{Iterator, args=["i32"]}`,
so it is a first-class `Iterator`: a generic `reduce` bounded on `((Iterator S) I)`
consumes it, and a `(FilterIter (MapIter …) pred)` chain stamps the inner combinator
first (natural bottom-up recursion via `struct-template-stamp`), recording its
conformance before the outer `FilterIter`'s recovery reads it. End-to-end test:
`examples/assoc-types-extend.nuc` (+ `tests/expected/assoc-types-extend.out`),
a 2-level `map → filter → reduce` chain over `i32`, generically. The §8.2 recursion
risk is benign: `proto-sigs-resolve`'s required-method check goes through
`generic-binds-for`, a pure binding *probe* (no stamping), and the reserve-name-first
memoization in `struct-template-stamp-types` guards re-entry on the same instance.
The §8.1 multi-level *stamp-before-extend* re-check (an instance stamped before its
`extend`, whose source is *also* a deferred combinator) is handled conservatively by
a **soft defer** (recovery returns 0 → the check is skipped, not errored); a full
deferred-requeue is out of scope for A4.2 and not exercised by the library/example
path (instances are stamped in `main`, after all top-level `extend` forms).
**Series:** A4 — the follow-on to associated types (A0–A3, [assoc-types.md](assoc-types.md)).
**Prerequisite:** A0–A2 (shipped). This builds directly on the conformance-arg
retention (A0), the `&where` protocol-application parser (A1), and the
dispatch-time recovery fixpoint (A2); it does **not** redesign them, it *reuses*
them at a second site.
**Motivation:** fully apply associated types to `lib/iterator.nuc` — generic,
*chainable* `map`/`filter`/`reduce` combinators over any element type — which A0–A2
alone cannot express.

---

## 0. One-paragraph summary

A0–A2 let a generic **`defn`** recover a protocol's associated parameters from a
conforming type's retained conformance args (`&where ((Iterator S) I)` reads `I`'s
element type back out). That removed the phantom-param tax from *method
signatures*. But it left a hole: a generic combinator **cannot itself conform** to
the protocol it implements, because `(extend (MapIter I F) (Iterator E))` names a
result element `E` that is neither a struct parameter nor concrete — it is
recoverable only from `F`'s conformance, and `emit-extend` has no recovery
machinery. A4 closes the hole by accepting a `&where` clause **on the `extend`
form** and running the *same* recovery fixpoint A2 runs at dispatch, but at struct
**stamp time**, so the per-instance `Conformance` is recorded with the recovered
args. Once a stamped `(MapIter IntRangeIter Double)` records
`Conformance{Iterator, args=[i32]}`, every existing A2 bound (`((Iterator S) I)`,
`doseq`, a generic `reduce`) consumes it through the ordinary conformance lookup —
and combinators compose to arbitrary depth.

---

## 1. Problem statement

### 1.1 What A0–A2 gave us, and the wall it hits

With associated types shipped, the phantom-free combinator from
[assoc-types.md](assoc-types.md) §2.3 compiles and runs:

```lisp
(defstruct (MapIter I F) source:I f:F)

(defn (next (Maybe E)) ((self (ref (MapIter I F)))
                        &where ((Iterator S) I) ((UnaryFn S E) F))
  (let ((res (Maybe S)) (next (.& self source)))
    (match res
      ((some v) (return (some (apply (.& self f) v))))
      (none (return none)))))
```

`S` (source element) and `E` (result element) are recovered, not threaded. Good.
But this `MapIter` is a **dead end**:

- It cannot be the *source* of another combinator. A `FilterIter` wrapping it
  would need `&where ((Iterator S) I)` with `I = (MapIter …)` — which requires
  `MapIter` to *conform* to `Iterator`. It does not.
- It cannot be passed to a generic consumer bounded on `Iterator`
  (`collect-all`, a generic `reduce`, `sum-i32-iter`): the bound's conformance
  check (`generic-constraints-ok`, src/nucleusc.nuc:5466 → `conformance-lookup`)
  fails for a `MapIter` instance.
- It cannot be driven by `doseq` (a `next`-loop macro) if `doseq` is keyed on the
  `Iterator` conformance.

A combinator that can only be driven by a hand-written `(next …)` loop is not a
library combinator; it is a one-off.

### 1.2 Why `extend` cannot express it today

The natural spelling is:

```lisp
(extend (MapIter I F) (Iterator E))
```

`E` is not one of `MapIter`'s parameters (`I`, `F`); it is the element type
`MapIter` *yields*, determined by `F`'s `(UnaryFn S E)` conformance.
`emit-extend`'s template-subject branch (src/nucleusc.nuc:6714) requires every
protocol-application argument to be one of the template's own tyvars: it stores the
binding nodes verbatim (`tmpl-conformance-add`, src:6578) and, at stamp time,
substitutes **only the template tyvars** into them (`tmpl-conformance-check-one`,
src:6611 → `subst-tyvars-node bnode (stt tyvars) …`). A free `E` survives
unsubstituted and dies in `parse-type-from-node` as **`unknown type: E`**.

This was confirmed empirically against the shipped compiler:

```lisp
; (extend (MapIter I F) (Iterator E) &where ((Iterator S) I) ((UnaryFn S E) F))
;   → trailing &where is silently ignored by emit-extend; at the first stamp of a
;     concrete MapIter the check fires:  error: unknown type: E
```

A trailing `&where` on `extend` is **parsed away** today (`emit-extend` only reads
`(node-at form 1)`/`(node-at form 2)`), so the clause that *would* determine `E` is
not even seen.

### 1.3 The regression vs. phantom params

Note the irony: the **phantom-param** verbose form
(`examples/phantom-tyvar-test.nuc`, `MapIterVerbose I F S E`) *can* conform and
chain — `(extend (MapIterVerbose I F S E) (Iterator E))` binds `E` to a real
(fourth) parameter, threaded explicitly by the caller. Associated types removed the
phantom params from the signature but, without A4, **lose the composability the
phantom form had**. A4 restores it: clean signatures *and* chaining.

---

## 2. Surface syntax — `&where` on `extend`

The one new surface is a `&where` clause appended to an `extend` form, spelled
**identically** to the `&where` clause A1 already parses for `defn`:

```lisp
(extend (MapIter I F) (Iterator E)
        &where ((Iterator S) I)
               ((UnaryFn S E) F))
```

Read: "`(MapIter I F)` conforms to `(Iterator E)`, where `I` is an `Iterator`
yielding `S`, `F` maps `S → E`." `E` in the protocol application `(Iterator E)` is
**determined** by the `&where` clause, exactly as `E` in a `defn`'s return type
`(Maybe E)` is determined by A1's fixpoint.

### 2.1 What stays unchanged (backward compatible)

Both existing `extend` shapes parse and behave identically — the `&where` branch is
purely additive:

```lisp
(extend (Vector T) (Seq T))            ; arg T is a template param      (T4, unchanged)
(extend IntRangeIter (Iterator i32))   ; arg i32 is concrete            (A0, unchanged)
```

A `&where`-free `extend` never enters the new path. The compiler's own source and
every current library use only these two shapes, which is what keeps the bootstrap
byte-identical (§9).

### 2.2 Recover vs. constrain — unchanged from A2

Each argument in a `&where` constraint is **recovered** if it is an as-yet-unbound
tyvar and **constrained** (checked for equality) if it is concrete or already
bound — *exactly* A2's rule (assoc-types.md §2.4), decided per-argument at
recovery time, not by the protocol. A4 changes only *when* the rule runs (stamp
time), not the rule.

### 2.3 The protocol-application arg may now be a recovered tyvar

The only generalization to the protocol position itself: in
`(extend Subject (Proto Arg…))`, an `Arg` that is a tyvar may now be one **bound by
the `&where` clause** (e.g. `E`), in addition to today's "a template parameter"
(`T`) or "concrete" (`i32`). Determination (§3) decides which; the binding then
flows into the recorded conformance args (§4).

---

## 3. Determination at the extend site (mirror of A1 §3.4)

Every tyvar that appears in the protocol application `(Iterator E)` or in any
`&where` constraint must be **determined**, by the same fixpoint A1 runs in
`register-generic-defn` (src/nucleusc.nuc:5241–5278):

1. **Seed:** every **template parameter** of the subject (`I`, `F` for
   `(MapIter I F)`) is determined. (At A1 the seed was "tyvars bound by a parameter
   pattern"; here the analogue is "the subject template's own tyvars", which are
   always determined because they *are* the instance's stamp arguments.)
2. **Step (repeat to fixpoint):** for each constraint `((Proto Arg…) V)` whose
   conforming variable `V` is determined, every tyvar appearing in an `Arg`
   position becomes determined.
3. **Check:** every tyvar mentioned in the protocol application `(Iterator E)`
   must be determined after convergence; otherwise it is an error —
   `extend: protocol parameter 'E' is not determined by the subject or any &where
   constraint`.

Worked example, `(extend (MapIter I F) (Iterator E) &where ((Iterator S) I) ((UnaryFn S E) F))`:

| pass | determined set | reason |
|---|---|---|
| seed | `{I, F}` | template params |
| 1 | `+S` | `((Iterator S) I)`: `I` determined → recover `S` |
| 1 | `+E` | `((UnaryFn S E) F)`: `F` determined → recover `E` (and re-check `S`) |
| done | `{I, F, S, E}` | `E` (the protocol-app arg) is determined ✓ |

This is the **same `collect-constraint-arg-tyvars` + determination loop** A1 already
contains; A4 factors it into a shared helper (§5) and runs it over the subject's
template tyvars as the seed.

---

## 4. Stamping changes (the core of A4)

The data already exists per-instance; A4 only fills the recovered args into it. The
plan moves A2's recovery from dispatch time to **stamp time**.

### 4.1 `TmplConformance` gains a constraint clause

`TmplConformance` (src/nucleusc.nuc:405) today holds `{template, proto, bindings,
nbindings}`. Add the parsed `&where` clause, mirroring the `Method` constraint
fields (`con-protos`/`con-vars`/`con-args`/`con-nargs`, src:346–356):

```
TmplConformance:
  template, proto, bindings, nbindings        ; (unchanged: the (Iterator E) arg nodes)
  con-protos, con-vars, con-args, con-nargs   ; NEW: the &where clause, or empty
  num-constraints                             ; NEW: 0 for a &where-free extend
```

A `&where`-free `extend` records `num-constraints = 0`; nothing downstream changes
for it.

### 4.2 `emit-extend` parses the `&where` and runs determination

In the template-subject branch (src/nucleusc.nuc:6714), after `extend-proto-name`
yields the protocol name + arg nodes:

1. If a trailing `&where` marker is present in `form`, parse the constraint list
   with the **shared constraint parser** (§5) — the same code path
   `register-generic-defn` uses, producing `con-protos`/`con-vars`/`con-args`/
   `con-nargs`. (Today `emit-extend` ignores anything past `(node-at form 2)`.)
2. Run the determination fixpoint (§3), seeded with the template's tyvars
   (`(struct-template-lookup name)` → `tyvars`). Error on any undetermined
   protocol-app tyvar.
3. `tmpl-conformance-add` stores the binding nodes **and** the parsed constraint
   clause on the `TmplConformance`.

The existing count-check `proto-nargs == num-params` stays. The
protocol-on-protocol and blanket-protocol early returns (src:6744, 6753) are
untouched — `&where` is meaningless there and may be rejected if present.

### 4.3 `tmpl-conformance-check-one` recovers the assoc args at stamp time

This is where A2's fixpoint runs. `tmpl-conformance-check-one` (src:6611) currently
substitutes the template tyvars into the binding nodes and records the result.
A4 inserts a recovery step *before* that substitution, when
`num-constraints > 0`:

Given an instance `iname` stamped from template `st` with concrete arg spellings
`arg-spellings` (length `nargs`, the template tyvars in order):

1. **Seed a binding map** keyed by tyvar name: each template tyvar →
   its concrete spelling (`I → "IntRangeIter"`, `F → "Double"`). The associated
   tyvars (`S`, `E`) start unbound.
2. **Run the recovery fixpoint** — the generalized `generic-recover-assoc` /
   `recover-one-constraint` (§5). For each constraint `((Proto Arg…) V)` whose `V`
   is now a concrete spelling `CV`:
   - look up `conformance-args(CV, Proto)` (the A0 args-bearing record, src:6230);
   - pair each `Arg[i]` with `args[i]`: an unbound tyvar `Arg[i]` → bind it
     (**recover**); a concrete/bound `Arg[i]` → unify/check (**constrain**), erroring
     on mismatch.
   Repeat until no new binding. For `MapIter`: `((Iterator S) IntRangeIter)`
   recovers `S = i32`; `((UnaryFn S E) Double)` checks `S = i32` against `Double`'s
   arg and recovers `E = i32`.
3. **Substitute the full map** (template tyvars + recovered `S`/`E`) into the
   binding nodes `(Iterator E)`, then `parse-type-from-node` + `type-spelling` as
   today → `pspellings = ["i32"]`.
4. `verify-conformance-params` records the per-instance
   `Conformance{type=MapIter.IntRangeIter.Double, proto=Iterator, args=["i32"]}` —
   the **identical** call the `(Vector i32)/(Seq i32)` path already makes, just with
   a recovered rather than substituted arg.

After this, the stamped `MapIter` is a first-class `Iterator` in the registry.

### 4.4 `verify-conformance-params` (check=1) at stamp time — must still pass

With `check=1`, `verify-conformance-params` substitutes the recovered param
spellings into the protocol's required-method signatures and verifies a matching
concrete method resolves for `iname`. For `MapIter` the required method is
`(next (Maybe E))` with `E = i32` → it looks for `(next (Maybe i32))` on
`(MapIter IntRangeIter Double)`. The combinator's own `next` (the A1-bounded
generic method) monomorphizes to exactly that signature, so the check is satisfied
by the method we already wrote.

**Ordering risk (flag for implementation):** the conformance check may need
`MapIter`'s `next` to be resolvable (possibly instantiated) at the moment
`tmpl-conformance-check-one` runs. The T4 path already resolves required methods at
stamp time for `(Vector i32)/(Seq i32)`, so the machinery exists; A4 must confirm
the recovered-arg case resolves the bounded `next` the same way and does not
recurse forever (a `next` whose own body stamps the same instance). Pin this in a
test before declaring done.

### 4.5 `tmpl-conformance-recheck-stamped` — same recovery for pre-stamped instances

When an instance is stamped *before* the `extend` form is processed,
`tmpl-conformance-recheck-stamped` (src:6651) replays the per-instance check from
the `StructDef` origin args. It calls `tmpl-conformance-check-one`, so it inherits
the §4.3 recovery for free — no separate code path, provided the recovery is *in*
`check-one` and not in `emit-extend`.

---

## 5. Refactor: one recovery engine, two sites

A4's whole thesis is that extend-site recovery **is** dispatch-site recovery run at
a different time against a different seed. The implementation should make that
literal by extracting two shared helpers:

1. **`parse-where-constraints`** — lift the constraint loop from
   `register-generic-defn` (src:5173–5218) into a helper that, given the `&where`
   tail nodes, fills `con-protos`/`con-vars`/`con-args`/`con-nargs` and collects
   constraint-arg tyvars (`collect-constraint-arg-tyvars`). Called by both
   `register-generic-defn` (A1) and `emit-extend` (A4).
2. **`recover-assoc-into`** — generalize `generic-recover-assoc` /
   `recover-one-constraint` (src:5380–5436) to operate on an explicit
   `(tyvar-names[], bound[], num-constraints, con-protos, con-vars, con-args,
   con-nargs)` tuple instead of reaching into a `Method*` and a fixed `out-bound`
   array. A2's `generic-method-bind` then calls it with the method's tyvars +
   `out-bound`; A4's `tmpl-conformance-check-one` calls it with the
   template-tyvar+assoc map. The fixpoint, the recover-vs-constrain test, the
   missing-conformance soft-fail, and the constraint-mismatch diagnostic are shared
   verbatim — the only difference is the seed and the value representation
   (`Type*` at dispatch vs. canonical spelling at stamp; pick one — spellings are
   the stamp-time currency and `conformance-args` already returns spellings).

This refactor is the bulk of A4 and the reason it is low-risk: no new inference, just
a second caller of A2's proven fixpoint. Doing it as a pure extract-method first
(A2 still green, bootstrap byte-identical) de-risks the rest.

---

## 6. The library payoff (`lib/iterator.nuc`)

With A4, `lib/iterator.nuc` becomes element-generic and composable. Sketch of the
end state (full rewrite belongs to the A4 implementation task, not this doc):

```lisp
(defprotocol (Iterator E) ((next (Maybe E)) ((self (ref Self)))))      ; unchanged
(defprotocol (UnaryFn Arg Ret) ((apply Ret) ((self (ref Self)) (x Arg))))
(defprotocol (FoldFn Acc Elem) ((fold Acc) ((self (ref Self)) (acc Acc) (x Elem))))

(defstruct (MapIter I F) source:I f:F)
(defn (next (Maybe E)) ((self (ref (MapIter I F)))
                        &where ((Iterator S) I) ((UnaryFn S E) F)) …)
(extend (MapIter I F) (Iterator E) &where ((Iterator S) I) ((UnaryFn S E) F))   ; A4

(defstruct (FilterIter I F) source:I pred:F)
(defn (next (Maybe S)) ((self (ref (FilterIter I F)))
                        &where ((Iterator S) I) ((UnaryFn S i32) F)) …)          ; pred S→i32 truthy
(extend (FilterIter I F) (Iterator S) &where ((Iterator S) I) ((UnaryFn S i32) F))  ; A4

; A single generic reduce over ANY iterator, recovering the element type:
(defn reduce:Acc ((g (ref G)) (init Acc) (it (ref I))
                  &where ((Iterator S) I) ((FoldFn Acc S) G)) …)
```

Because `MapIter`/`FilterIter` now conform to `Iterator`, the three i64-specialized
combinators (`MapIterI64`, `FilterIterI64`, `CallI64`, `BinaryCallI64`, and the
three `reduce-*-i64` functions) collapse into the generic forms above, and the
`map → filter → reduce` chain in `examples/iterator-test.nuc` is expressed
generically over any element type:

```lisp
(reduce sum 0  (FilterIter (MapIter src square) even?))   ; src: any (Iterator E)
```

`doseq` over a `MapIter`/`FilterIter` works for the same reason (conformance is now
recorded). This is the concrete deliverable A4 unlocks; A0–A3 cannot express it.

---

## 7. Coherence (unchanged from A0)

One conformance per `(type, proto)` (`conformance-add` dedup, src:6265). A second
`extend` of the same stamped instance for the same protocol with *differing*
recovered args is an error, exactly as A0 enforces for concrete args. The
single-conformance rule is what makes the recovered args functionally determined and
therefore recoverable by downstream A2 bounds — the same coherence argument as
assoc-types.md §0/§3.1, now applied to recovered (not just concrete) args.

---

## 8. Ordering and termination hazards (the real risks)

A4's correctness rests on stamping order, because recovery reads conformances that
must already be recorded.

1. **Bottom-up stamping.** Recovering `S` from `((Iterator S) I)` needs `I`'s
   `Iterator` conformance recorded *before* the outer combinator's check runs. For a
   base source (`IntRangeIter`, extended concretely up-front) this holds trivially.
   For a nested combinator (`FilterIter` over `MapIter`), the inner `MapIter`
   instance must be stamped — and its conformance recorded — before the outer
   `FilterIter` instance's check. Stamping is already recursive (stamping
   `(FilterIter (MapIter …) P)` stamps `(MapIter …)` first), and
   `tmpl-conformance-check-instance` fires per stamp, so the inner conformance
   *should* be recorded first. **Validate this is actually the order**; if not, a
   deferred re-check queue (like `tmpl-conformance-recheck-stamped` in reverse) is
   the fallback.
2. **Recovery before required-method resolution.** §4.4: the `next` whose
   resolution the conformance check demands is itself the bounded generic whose body
   recurses into `next` on the source. Guard against unbounded recursion (a
   `g-stamping-in-progress` style guard, or resolving the conformance lazily).
3. **Recovery needs the conformance, conformance needs the recovery.** Within a
   single combinator there is no cycle (the source's conformance is independent),
   but a hypothetical mutually-recursive combinator pair could deadlock the
   fixpoint. Out of scope; document as a non-goal.

These are the items most likely to bite; a test matrix of base / one-level /
two-level / three-level chains, plus stamp-before-extend and extend-before-stamp
orderings, is the acceptance bar.

---

## 9. Bootstrap invariant (non-negotiable)

The compiler's own source and every shipped library use only `&where`-free
`extend` forms, so A4 must be **byte-identical-bootstrap** like A0–A2:

- The §5 refactor (extract-method) changes no behaviour → empty IR diff.
- The §4 recovery path runs **only** when `num-constraints > 0` on a
  `TmplConformance`, which no current `extend` produces → inert during self-compile.
- A bootstrap diff after any A4 task is a bug; re-converge before proceeding (same
  discipline as the assoc-types prompt).

The library rewrite (§6) *does* change `lib/iterator.nuc` and its example output,
but those are library/example artifacts, not compiler source — the compiler does not
import `lib/iterator.nuc`, so the bootstrap stays byte-identical there too.

---

## 10. `.nuch` export / cross-unit (mirror A0 rule (a))

An `(extend (MapIter I F) (Iterator E) &where …)` must export to `.nuch` **with its
`&where` clause**, so the importer's `register-imported-conformance` /
re-run-`emit-extend` path (A0 §4.5 rule (a), src:6788) repopulates the
`TmplConformance` constraint clause and recovers args at stamp time *in the
importing unit*. The exporter cannot serialize the per-instance recovered args for
instances it never stamped; this is the same cross-unit template-conformance gap A0
already documents (assoc-types.md §6 Q4 decision), now extended to carry the
`&where` tail in the exported `extend` form. Concrete-arg and same-unit stamps are
unaffected.

**Implemented (A4.3).** Two edits in `src/nucleusc.nuc`:

- **Export.** `emit-nuch-extend` now serializes *every* node of the `extend`
  form (not just subject + protocol), so a trailing `&where ((Proto Arg…) V) …`
  round-trips verbatim through `fprint-node`. A `&where`-free extend (`node-len ==
  3`) emits `(extend Subject Protocol)`, byte-identical to before.

- **Import.** `register-imported-conformance` now detects a template subject (the
  subject node is a `NODE-CELL`, e.g. `(MapIter I F)` or `(Vector T)`) and
  delegates the whole form to `emit-extend`. `emit-extend`'s template branch
  re-parses any `&where`, re-runs the determination fixpoint, re-registers the
  `TmplConformance` with its constraint clause, and rechecks already-stamped
  instances — emitting no IR (a template subject defines no type), so it is safe on
  the import path. The per-instance `Conformance` with recovered args is then
  produced by A4.2's stamp-time recovery when the importing unit stamps a concrete
  instance. This also (correctly) closes the older gap where even a `&where`-free
  template extend (`(extend (Vector T) (Seq T))`) was dropped on `.nuch` import
  (A0 §4.5 / assoc-types.md §6 Q4 listed this as a pre-existing limitation).

The conforming variables' conformances (e.g. `IntRangeIter`'s `Iterator`, `SqFn`'s
`UnaryFn`) must be in scope in the importing unit at the point it stamps the
instance, so recovery can read them. Byte-identical bootstrap holds because the
only `.nuch` the compiler imports, `src/llvm.nuch`, carries no template extends.
End-to-end test: `examples/assoc-types-extend-cross.nuc` imports the combinator
through `lib/mapiterlib.nuch` (no `.nuc` on the search path, so the header wins)
and stamps `(MapIter IntRangeIter SqFn)` into a generic `reduce` bounded on
`((Iterator S) I)`. Output `reduce(map sq [1,5)) = 30`. A negative check (stripping
the `&where` from the header) reproduces the pre-A4 failure `unknown type: E`,
confirming the test exercises the feature.

---

## 11. Out of scope (unchanged from A0–A2, restated)

- **Higher-kinded recovered args** — a recovered `Arg` that is itself parametric
  with a free var (`Elem = (Maybe T)`, `T` free). Concrete/fully-applied args fine.
- **Lambdas / closures** — function objects stay named structs conforming to
  `UnaryFn`/`FoldFn`.
- **Multi-conformance with differing args** — forbidden by coherence (§7).
- **Mutually-recursive combinator conformances** — the §8.3 fixpoint deadlock case.
- **`get`/`keys`/`vals` as `Assoc`/`Set` protocol methods** — still its own task
  (assoc-types.md §5); A4 makes it no easier or harder.

---

## 12. Build order (subtasks) and acceptance gates

Dependency order; each gated by `make test` + `make bootstrap` byte-identical via
**build-test-runner**, per AGENTS.md. Per CLAUDE.md this is a multi-phase
compiler task on one large file — dispatch each subtask to the named subagent; keep
the orchestrating thread for integration.

| Task | What | Agent | Gate |
|---|---|---|---|
| **A4.0** | Extract `parse-where-constraints` and `recover-assoc-into` shared helpers from A1/A2 (pure refactor; A2 still green). | systems-impl-engineer | byte-identical bootstrap; A2 tests unchanged |
| **A4.1** | `TmplConformance` constraint fields; `emit-extend` parses trailing `&where` + runs the determination fixpoint (§3, §4.1–4.2). Parsed-but-unused is fine here; no recovery yet. | systems-impl-engineer | byte-identical; a `&where` `extend` parses, a `&where`-free one is unchanged |
| **A4.2** ✅ | `tmpl-conformance-check-one` runs `recover-assoc-into` at stamp time and records the per-instance `Conformance` with recovered args (§4.3–4.5); ordering guards (§8). **Landed:** byte-identical bootstrap; `(MapIter IntRangeIter SqFn)` records `Conformance{Iterator, [i32]}`; the `map → filter → reduce` chain compiles and runs (`examples/assoc-types-extend.nuc`, 88/88). | systems-impl-engineer | byte-identical; a stamped `(MapIter IntRangeIter Double)` records `Conformance{Iterator, [i32]}`; chaining + generic `reduce` over a combinator compile and run |
| **A4.3** ✅ | `.nuch` round-trip of the `&where`-bearing `extend` (§10). **Landed:** `emit-nuch-extend` serializes the full `extend` form (incl. `&where`); `register-imported-conformance` delegates a template-subject extend to `emit-extend` so the `TmplConformance` (and its `&where` clause) is reconstructed in the importer, with stamp-time recovery firing there. Cross-unit test `examples/assoc-types-extend-cross.nuc` (`.nuch` at `lib/mapiterlib.nuch`); byte-identical bootstrap; 89/89. | systems-impl-engineer | imported combinator conformance recovers args in the importing unit |
| **A4.4** ✅ | Rewrite `lib/iterator.nuc` to generic chainable combinators (§6); collapse the `*I64` specializations; rewrite `examples/iterator-test.nuc` (multi-level generic chain) + `examples/assoc-types.nuc`; update `docs/iterators.md`/`docs/generics.md`/`docs/collections.md`; flip progress. **Landed:** `lib/iterator.nuc` rewritten with `UnaryFn`/`FoldFn`/`MapIter`/`FilterIter`/`reduce`; the `i64`-specialized `*I64` types retired; `examples/iterator-test.nuc` uses the generic API; 89/89 tests; byte-identical bootstrap. | focused-task-implementer (lib/examples) + api-docs-writer (docs/progress) | `make test` green; chain output matches; docs describe extend-site `&where` |
| **A4.5** ✅ | Extend `defn &where` to support the compound `((Protocol Arg…) Var)` form for conforming variables that are *free type parameters* (bare unbound tyvars in parameter positions, not from a struct-template application) and *previously-recovered tyvars* (a tyvar that was itself recovered by an earlier constraint in the same `&where` clause). See §14. **Landed:** the capability fell out of the A1/A4.0 helpers already in place — `parse-where-constraints` seeds every conforming variable into the tyvar set, the `register-generic-defn` determination fixpoint recovers the chain (`C → It → E`), and dispatch-time `generic-method-bind`/`recover-assoc-into` binds `C` from the argument and the recovered vars before `generic-constraints-ok` reads them. Only the test fixture + bootstrap refresh remained. `examples/assoc-iter-return.nuc` prints `count=5`; 92/92 tests; byte-identical bootstrap; C2.1/C2.2b/C2.2c unblocked. | systems-impl-engineer | `examples/assoc-iter-return.nuc` compiles and prints `count=5`; 92 tests pass; byte-identical bootstrap |

**Definition of done:** the `map → filter → reduce` chain runs **generically** over
an arbitrary element type with no phantom params and no i64 specialization;
combinators conform to `Iterator` and nest to ≥3 levels; the compiler still
self-compiles byte-identically; docs and progress reflect the shipped surface.

**A4.5 definition of done:** `examples/assoc-iter-return.nuc` compiles and
runs (`count=5`); all 92 tests green; bootstrap byte-identical; `C2.1` / `C2.2b` /
`C2.2c` unblocked.

---

## 13. Empirical premises (verified against the shipped compiler before writing)

1. **`defn`-site `&where ((Iterator S) I) ((UnaryFn S E) F)` works** —
   `examples/assoc-types.nuc` compiles, recovers `S`/`E`, prints `2 4 6`. (A2 path.)
2. **`extend`-site recovery does not** — `(extend (MapIter I F) (Iterator E) &where …)`
   ignores the `&where` and dies `unknown type: E` at the first `MapIter` stamp.
   (The hole A4 fills.)
3. **A stamped combinator is not found by an `Iterator` bound** — passing a
   `(MapIter …)` to a generic bounded `((Iterator i32) I)` errors with
   `no matching method` (no recorded conformance). (Why chaining is blocked today.)
4. **`let` has no type inference** (`let: missing :type`) — so there is no back-door
   to recover an element type without a bound; the conformance route (A4) is the
   only one.

---

## 14. A4.5 — `defn &where` compound constraint support

### 14.1 Observed gap

`defn &where` with the compound `((Protocol Arg…) Var)` constraint form fails for
two related cases:

**Case 1 — free type parameter as conforming variable.** A `defn` whose parameter
type is a bare unbound symbol (not a struct-template application) cannot use that
symbol as the conforming variable in a compound constraint:

```lisp
(defprotocol (IterColl It)
  (mk-iter:It ((self (ref Self)))))

; FAILS today: "defn: &where constraint must name a protocol and a variable"
(defn count-coll:i32 ((c (ref C)) &where ((IterColl It) C))
  ...)
```

`C` appears in `(ref C)`, a bare pointer-to-unknown-type — the compiler does not
recognize it as a tyvar from the parameter pattern alone.

**Case 2 — recovered tyvar as conforming variable.** Even if Case 1 were fixed, the
second constraint in a chained `&where` may use a tyvar that was *recovered* by the
first constraint as its conforming variable:

```lisp
(defn count-coll:i32 ((c (ref C))
                      &where ((IterColl It) C)   ; C conforming → recover It
                             ((Iterator E) It))  ; It conforming → recover E
  ...)
```

`It` is not a parameter-bound tyvar; it is recovered from `C`'s `IterColl`
conformance. The second constraint `((Iterator E) It)` must therefore see the
**post-fixpoint** tyvar set, not the initial one.

These two cases together are what `examples/assoc-iter-return.nuc` exercises. The
file exists and was intended as the validation spike for this capability, but it
was written before the compiler support landed; it currently fails to compile.

### 14.2 What already works

The compound `((Protocol Arg…) Var)` form *does* work in `defn &where` when `Var`
is a tyvar already bound by a **struct-template application** in the parameter list
(the A1/A2 path). For example, `(defn (next (Maybe E)) ((self (ref (MapIter I F)))
&where ((Iterator S) I) ((UnaryFn S E) F))` compiles and runs: `I` and `F` come
from the `(MapIter I F)` template application, so they are in the initial tyvar set;
`S` and `E` are then recovered in a single fixpoint pass. The `defn`-level
`generic-resolve` path already reads back these recovered args at dispatch.

The gap is only for conforming variables that are **not** already in the initial
tyvar set — i.e., those introduced directly as parameter types or recovered by a
prior constraint in the same clause.

### 14.3 Likely root cause

`defn-has-receiver-tyvars` / `register-generic-defn` (src/nucleusc.nuc) determine
the initial tyvar set by scanning parameter and return-type patterns for struct-
template applications. A bare type symbol (e.g. `C` in `(ref C)`) that is neither a
registered struct name nor one of those template tyvars is not added to the set.

Consequently the `&where` parser, when it encounters `((IterColl It) C)`, checks
that `C` is a known tyvar — and fails with "must name a protocol and a variable"
because `C` is not yet in the set.

**Fix direction:**
1. **Seed from `&where` conforming variables.** When parsing a `defn`'s `&where`
   clause, treat any *unrecognized bare symbol* in a conforming-variable position as
   a new free tyvar and add it to the initial tyvar set. (A conforming variable that
   names a registered struct or concrete type is a type constraint, not a new tyvar;
   this case is already forbidden or irrelevant.)
2. **Iterative fixpoint over the full constraint list.** After seeding with both
   parameter-pattern tyvars and `&where` conforming variables, run the same
   determination fixpoint A1 already implements — recovering `Arg` tyvars for each
   constraint whose `Var` is determined. A recovered tyvar (like `It` after pass 1)
   is then available as a conforming variable in later constraints (like
   `((Iterator E) It)`).
3. **Dispatch-time recovery.** The call-site resolution (`generic-method-bind`,
   `generic-resolve` tier-1) already runs the recovery fixpoint. Confirm it handles
   the case where the conforming variable's type is recovered, not just directly
   provided as a call argument — or extend it to do so.

### 14.4 Acceptance criteria

- `examples/assoc-iter-return.nuc` compiles and prints `count=5`.
- Add `tests/expected/assoc-iter-return.out` containing `count=5` so it runs in
  `make test`.
- All existing 92 tests still pass; `make bootstrap` is byte-identical.
- The fix must not change the behaviour of existing `defn &where` with template-
  bound conforming variables (the A1/A2 paths are exercised by the 92-test suite).

### 14.5 Out of scope

- `defn &where` with a concrete (non-tyvar) conforming variable — already rejected
  or unsupported; leave unchanged.
- Mutually-recursive `&where` recovery (two constraints that each recover the
  other's conforming variable) — document as a non-goal if encountered.
- Any change to `extend &where` (A4.0–A4.4 paths) — those are complete and must
  remain byte-identical.
</content>
</invoke>
