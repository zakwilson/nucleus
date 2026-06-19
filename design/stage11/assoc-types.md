# Associated types for protocols

**Status:** Implemented (stage11-collections branch). A0–A2 complete; see §7 below.
**Prerequisite:** Stage 11 cleanup §4a (phantom-param tyvar-recovery fix) — done.
**References:** parametric-structs *Known limitations #3*; cleanup §4b finding.

---

## 0. Revision note (syntax)

An earlier draft of this document proposed a `with (Name = Var)` suffix on
`&where` constraints and a `(type Name)` declaration inside `defprotocol`. Both
were dropped after evaluation against the rest of the language:

- **`(Name = Var)` introduced infix `=`.** Nucleus is a prefix s-expression
  language with *no* infix syntax, and `=` is already the equality function
  (`(= done 0)`). Spelling a binding as `(Elem = E)` overloads a value operator
  as syntax — foreign to the language and to the reader.
- **`with` introduced a bare in-list keyword.** Nucleus's parameter-list markers
  are all `&`-prefixed (`&where`, `&rest`, `&optional`); there is no precedent
  for a bare keyword *inside* a constraint.
- **`(type Name)` and the "parametric vs associated" split were unnecessary.**
  The conformance registry already dedups on `(type, protocol)`
  (`conformance-add`, src/nucleusc.nuc:5964) — i.e. a type conforms to a given
  protocol **at most once**. That *is* the associated-type coherence rule
  ("the protocol's parameters are functionally determined by the conforming
  type"). So every parametric-protocol parameter is recoverable; there is no
  second flavour to distinguish.

The revised surface generalizes the **existing** `&where` constraint shape
`(Protocol Var)` to `((Protocol Arg…) Var)` — a protocol *application* in the
slot where a bare protocol name already goes. This reuses the `extend`
spelling verbatim, keeps the conforming variable in its existing tail position,
keeps every constraint a 2-element list, needs no new tokens, and folds the
deferred "parametric-protocol `&where`" frontier into the same mechanism.

---

## 1. Problem statement

### 1.1 The phantom-param workaround

`(Iterator E)` is today a parametric protocol: to declare that a type conforms
to it, you write `(extend (VecIter T) (Iterator T))`, binding the element type
`T` explicitly. This works for a single concrete iterator.

The problem surfaces with combinators. A `MapIter` must know:

- `I` — the source iterator type
- `F` — the mapping function type
- `S` — the element type that `I` yields ("source element type")
- `E` — the element type that `MapIter` itself yields ("result element type")

`S` and `E` are not stored in any field. They are **phantom params** — they exist
only to carry type information for the `next` method's return type and the call
to `F`. Because there are no associated types, the compiler cannot ask "what
does iterator `I` yield?". The caller must thread `S` explicitly.

The current workaround (verified working after cleanup §4a) is:

```lisp
(defstruct (MapIterVerbose I F S E)
  source:I
  f:F)

(defn (next (Maybe E)) ((self (ref (MapIterVerbose I F S E))))
  (let ((res (Maybe S)) (next (.& self source)))
    (match res
      ((some v) (return (some (callfn (.& self f) v))))
      (none (return none)))))
```

This works but forces every call site to spell out all four type params:
`(MapIterVerbose VecIter.i32 Double i32 f64)`. Every combinator layer adds two
more phantom params. Three levels of nesting (map + filter + map) require six
phantom params on the outermost type.

### 1.2 The `&where` parser gap

`&where` currently requires `(Protocol Var)` where **both elements are plain
symbols** (`register-generic-defn`, src/nucleusc.nuc:5110 — "each &where
constraint must be (Protocol Var)", which rejects any constraint whose first
element is not a symbol). You cannot name a parametric protocol in a constraint
at all, let alone recover its element type. This is the "parametric-protocol
`&where` frontier" (Known limitations #3).

### 1.3 What associated types solve

An associated type is a protocol parameter whose concrete value is **recovered
from the conforming type** rather than re-supplied at every use site. Once
`VecIter T` records, through its `(Iterator T)` conformance, *what it yields*,
any generic function bounded on `(Iterator …)` can read that element type back
out of `I` without threading an extra phantom param.

The desired end state:

```lisp
; No phantom params: MapIter is (MapIter I F), full stop.
(defstruct (MapIter I F)
  source:I
  f:F)

; S and E are recovered from the conformances of I and F — not declared
; separately, not threaded by the caller.
(defn (next (Maybe E)) ((self (ref (MapIter I F)))
                        &where ((Iterator S) I)
                               ((UnaryFn S E) F))
  ...)
```

`((Iterator S) I)` reads "`I` conforms to `Iterator`, yielding `S`";
`((UnaryFn S E) F)` reads "`F` maps `S` to `E`". `S` and `E` flow out of the
conformances and into the return type `(Maybe E)`.

---

## 2. Surface syntax

### 2.1 Declaring a parametric protocol (unchanged)

No new declaration syntax. A protocol with parameters beyond `Self` is written
exactly as it is today (parametric protocols already shipped in Stage 11):

```lisp
(defprotocol (Iterator Elem)
  ((next (Maybe Elem)) ((self (ref Self)))))
```

`Elem` is a free type name in the required-method signatures, bound positionally
at the `extend` site. There is **no `(type …)` marker** — every parameter of a
parametric protocol is an associated type, because the conformance registry
already permits at most one conformance per `(type, protocol)` pair
(`conformance-add`, src/nucleusc.nuc:5964). The protocol's parameters are
therefore functionally determined by the conforming type, which is precisely
what makes them recoverable.

### 2.2 Conformance: binding the associated type (unchanged source)

The existing `extend` form already carries the binding positionally — no new
syntax:

```lisp
; VecIter T conforms to (Iterator T) — so Elem is bound to T.
(extend (VecIter T) (Iterator T))

; IntRangeIter always yields i32 — so Elem is bound to i32.
(extend IntRangeIter (Iterator i32))
```

The only *implementation* change is that the conformance record must now
**retain** the bound arguments (today it discards them — see §3.1); the source
form is identical.

### 2.3 Using the associated type in `&where` bounds — the one new shape

Generalize the existing constraint shape

```
constraint ::= (Protocol Var)              ; today — Protocol is a bare symbol
```

to allow a **protocol application** in the protocol slot:

```
constraint ::= (Protocol Var)              ; plain protocol, no parameters
             | ((Protocol Arg…) Var)       ; parametric protocol; each Arg
                                           ;   recovers or constrains a parameter
```

The conforming variable `Var` stays in **tail position**, exactly as in
`(Ord T)`. The protocol slot — element 0 — may now be a list `(Protocol Arg…)`
instead of a bare symbol. Each `Arg` is matched positionally against the
parameters in the protocol's head (`(Iterator Elem)` → first arg is `Elem`),
mirroring how `extend` already binds them.

This is the **same spelling as `extend`'s protocol application** — `(Iterator T)`
at the `extend` site, `(Iterator S)` at the `&where` site — so there is one
protocol-application notation across the language, not two.

A complete `defn`:

```lisp
(defstruct (MapIter I F)
  source:I
  f:F)

(defn (next (Maybe E)) ((self (ref (MapIter I F)))
                        &where ((Iterator S) I)
                               ((UnaryFn S E) F))
  (let ((res (Maybe S)) (next (.& self source)))
    (match res
      ((some v) (return (some (apply (.& self f) v))))
      (none (return none)))))
```

where the function-object protocol is itself an ordinary parametric protocol:

```lisp
(defprotocol (UnaryFn Arg Ret)
  ((apply Ret) ((self (ref Self)) (x Arg))))

(defstruct Double dummy:i32)
(defn (apply i64) ((self (ref Double)) (x i64)) (return (* x (cast i64 2))))
(extend Double (UnaryFn i64 i64))
```

When `MapIter` is stamped for a concrete `I = VecIter.i32`, `F = Double`, the
compiler:
1. Binds `I = VecIter.i32`, `F = Double` from the receiver pattern (as today).
2. Reads `VecIter.i32`'s `Iterator` conformance and recovers its element →
   binds `S = i32`.
3. Reads `Double`'s `UnaryFn` conformance: arg `i64`, ret `i64`. The arg
   position carries the already-determined `S`, so it is **checked** (`i64` must
   equal `S = i32` — here it would mismatch and is a clean error; with a matching
   `VecIter.i64` source it succeeds). The ret position carries the undetermined
   `E`, so it is **recovered** → binds `E = i64`.
4. The return type `(Maybe E)` resolves to `(Maybe i64)`.

### 2.4 Recover vs. constrain is decided by the argument, not the protocol

An `Arg` in a constraint's protocol application is **recovered** when it is an as
yet unbound type variable, and **constrained** (checked for equality) when it is
already bound or concrete. This is exactly how `generic-method-bind` /
`unify-tpat` already treat positional arguments in a receiver pattern
(src/nucleusc.nuc:5176). It means a single mechanism covers both:

```lisp
&where ((Iterator S) I)     ; S unbound here → recover the element type of I
&where ((Iterator i32) I)   ; i32 concrete  → require that I yields exactly i32
```

The second form is the deferred "parametric-protocol `&where`" frontier
(cleanup §4 residual constraint, parametric-structs Known limitation #3). It
falls out of this design for free; it is no longer a separate exclusion.

### 2.5 Standalone generic functions

The same shape works in standalone generic functions:

```lisp
(defn collect-all ((it (ref I)) (out (ref (Vector E)))
                   &where ((Iterator E) I))
  (let (done:i32 0)
    (while (= done 0)
      (let ((item (Maybe E)) (next it))
        (match item
          ((some v) (conj out v))
          (none (set! done 1)))))))
```

Here `E` is recovered from `I`'s conformance, so the caller writes no element
param:

```lisp
(let ((v (ref (Vector i32))) (alloca (Vector i32)))
  (vector-init v)
  (let ((it (ref IntRangeIter)) (alloca IntRangeIter))
    ; ... init it ...
    (collect-all it v)))
```

Note `((Iterator E) I)` is *both* a bound (I must conform to `Iterator`) and an
extraction (E := I's element). One constraint, both jobs — the same way
`(Ord T)` both bounds and names `T` today.

---

## 3. Stamping and conformance-checking changes

### 3.1 `Conformance` registry format

The concrete-conformance record (`Conformance`, src/nucleusc.nuc:378) today
holds only `{type-name, proto-name}`; the parametric arguments in
`(extend IntRangeIter (Iterator i32))` are checked by `emit-extend` and then
**discarded**. Recovery is impossible until they are retained.

**Change:** add a positional argument array to each conformance record:

```
Conformance:
  type-name      ; concrete type key (e.g. "VecIter.i32")
  proto-name     ; e.g. "Iterator"
  args           ; ptr array of Type* (or type-spelling Node*), one per
                 ;   protocol parameter, in head order; null/empty for a
                 ;   plain (non-parametric) protocol
  nargs
```

For `(extend (VecIter T) (Iterator T))` stamped with `T = i32`: `args = [i32]`.
For `(extend IntRangeIter (Iterator i32))`: `args = [i32]`.

The dedup rule in `conformance-add` (src/nucleusc.nuc:5965) is unchanged: still
one record per `(type, proto)`. A second `extend` of the same `(type, proto)`
with *different* args is a coherence error (today it is silently dropped; with
recovery it must be rejected, since recovery would be ambiguous). For a plain
protocol with no parameters, `args` is empty and everything behaves as before.

The `TmplConformance` record (src/nucleusc.nuc:388) already retains the binding
pattern as `Node*`s; the new work is only to **propagate** those, substituted to
concrete types, into the per-instance `Conformance` recorded at stamp time
(`tmpl-conformance-check-instance`, src/nucleusc.nuc:2398) instead of dropping
them.

### 3.2 `emit-extend` changes

`emit-extend` (src/nucleusc.nuc:6230 calls `conformance-add`) currently validates
the parametric-arg count against the protocol's param count, substitutes them to
check the required methods, and then records only `(type, proto)`.

**Change:** pass the resolved argument list through to `conformance-add` so it is
stored in the new `args` field. No source-syntax change. For a template extend,
`tmpl-conformance-add` already stores the pattern; the per-stamp path records the
substituted concrete args.

### 3.3 `&where` parser changes (`register-generic-defn`)

Today the constraint loop (src/nucleusc.nuc:5108) requires each constraint to be
a 2-list of two symbols. Generalize element 0:

```
for each constraint (C V):
  require it is a 2-list and V is a symbol            ; V = conforming variable
  if C is a symbol:        plain protocol, no args    ; (unchanged path)
  if C is a list (P A…):   P is the protocol name (symbol),
                           A… are the argument patterns
```

For the parametric case, register `V` as a constraint variable (as today) and
additionally **collect any type variables appearing in `A…`** into the method's
tyvar set (`collect-pattern-tyvars` over each `A`, the same helper already used
for parameter patterns). Store, per constraint, the protocol name, the
conforming variable, and the argument-pattern nodes.

Because the assoc tyvars (`S`, `E`) now appear literally as nodes inside the
constraint, the capacity sizing (`count-pattern-nodes`, src/nucleusc.nuc:5097)
must also walk the constraint argument nodes. With that, **no special "one extra
slot per associated binding" accounting is needed** — assoc tyvars are sized and
collected by the same node-walk as every other tyvar. (This is simpler than the
earlier draft's separate slot bookkeeping.)

### 3.4 Determination check (`register-generic-defn`)

The existing check (src/nucleusc.nuc:5133) rejects any declared tyvar "not
determined by some parameter" (return-only tyvars need `dyn`, deferred). An
assoc tyvar like `S`/`E` is *not* determined by a parameter directly — it is
determined transitively, by being recovered from a constraint whose conforming
variable is itself determined.

**Change:** compute determination as a **fixpoint**:

1. Seed: every tyvar bound by a parameter pattern is determined.
2. Repeat until no change: for each constraint `((Proto Arg…) V)` whose `V` is
   determined, every tyvar that appears in a recoverable `Arg` position becomes
   determined.
3. Any tyvar still undetermined after the fixpoint is the existing error
   (return/constraint-only with no anchor → needs `dyn`).

This keeps the typo-catching guarantee (an undetermined tyvar is still an error)
while admitting the new transitive case.

### 3.5 `unify-tpat` / dispatch-time binding

`unify-tpat` (src/nucleusc.nuc:5176) binds the receiver/parameter tyvars from the
concrete argument tuple. After it has run the standard positional unification,
resolve the constraints to a fixpoint (mirroring §3.4, but now filling concrete
`Type*`s):

Repeat until no new binding:
- For each constraint `((Proto Arg…) V)` whose `V` is now bound to a concrete
  type `CV`:
  1. Look up `CV`'s `Conformance` for `Proto` (the new `args`-bearing record).
  2. For each `Arg[i]` paired with the conformance's `args[i]`: if `Arg[i]` is an
     unbound tyvar, bind it to `args[i]` (**recover**); otherwise unify the two
     (**constrain**), failing on mismatch.

A fixpoint is required because one constraint's recovered tyvar can be another
constraint's input (`S` recovered from `((Iterator S) I)` is then checked against
`((UnaryFn S E) F)`). The recovered bindings augment the standard ones and flow
unchanged through `generic-method-bind` → `generic-instantiate` →
`monomorphize-form` — they are just more names in the same substitution map.

**Error cases:**
- `CV` does not conform to `Proto`: the existing missing-conformance diagnostic.
- The conformance record has no `args` (a stale conformance recorded before this
  feature): "conformance for *Proto* was recorded without parameter bindings;
  recompile" — see migration §4.
- A `constrain` step mismatches (e.g. `S` recovered as `i32` but `F` maps `i64`):
  a clear "constraint *Proto* parameter mismatch: expected S = i32, found i64".

### 3.6 `generic-resolve` / `generic-instantiate` — no structural change

Once §3.5 binds the assoc tyvars, the monomorphizer substitutes them by name like
any other tyvar. No change beyond the `unify-tpat` augmentation.

### 3.7 Conformance check at stamp time — unchanged

`struct-template-stamp-types` → `tmpl-conformance-check-instance`
(src/nucleusc.nuc:2398) already checks a stamped instance against its `extend`
forms. The new work (§3.1/§3.2) is only that this path now *stores* the
substituted args in the per-instance `Conformance`, making them available to
§3.5 later.

---

## 4. Migration path

### 4.1 Existing `(extend …)` forms

All existing conformances continue to work; the source syntax is identical. The
`args` field is populated automatically from the protocol's parameter list and
the positional arguments already present in the `extend` form. No conformer
source changes. Because parametric protocols already shipped, there is no
"protocol gains parameters" retrofit — the parameters were always there; only
their *retention* in the conformance record is new.

### 4.2 Existing concrete-element combinators

`MapIterI64`, `FilterIterI64`, etc., in `lib/iterator.nuc` are fully specialised
to `i64` elements and use no phantom params. They are unaffected and continue to
compile and run.

### 4.3 Phantom-param verbose forms

The `MapIterVerbose I F S E` pattern from `examples/phantom-tyvar-test.nuc`
continues to compile and run. Once associated types land, new code should prefer
the two-param `(MapIter I F)` with `&where ((Iterator S) I) ((UnaryFn S E) F)`;
existing verbose forms need not be rewritten.

### 4.4 `&where` parser backward compatibility

Existing `&where (Protocol Var)` constraints (both symbols) parse identically —
they are the `C is a symbol` branch of §3.3. The protocol-application branch is
purely additive.

### 4.5 Stale conformance records across units

A `.nuch` produced before this feature records conformances without the `args`
field. Two acceptable handling rules (pre-release; pick at implementation time):
either (a) the importer re-runs `emit-extend` for imported `extend` forms so the
`args` are repopulated from the freshly-read protocol shape, or (b) bump the
`.nuch` format version and require recompiling libraries whose conformances are
consumed by an associated-type bound. The §3.5 "recorded without parameter
bindings" diagnostic catches the un-migrated case cleanly rather than crashing.

---

## 5. Out of scope

- **Higher-kinded associated types.** A parameter that is itself parametric
  (`Elem = (Maybe T)` with `T` free, recovered) requires higher-kinded
  unification; deferred. Concrete and fully-applied args (`(Maybe i32)`) are
  fine.

- **Lambdas and closures.** The function-object type `F` in combinators is always
  a named struct conforming to a `UnaryFn`/`BinaryFn`-style protocol; anonymous
  closures are a separate stage.

- **Multi-conformance with differing args.** A type conforming to one protocol
  with two different parameterizations (Rust's generic-trait multi-impl) stays
  forbidden — it is already forbidden by the `(type, proto)` dedup, and recovery
  requires that single-conformance coherence.

- **`get`/`keys`/`vals` as protocol methods on `Assoc`.** These return derived
  types (`(Maybe V)`, a key-iterator type). Making them protocol methods is now
  *mechanically* possible under this design (their result types are recoverable
  parameters of an `Assoc K V` protocol), but lifting `hmap-get` etc. from
  standalone generics to protocol methods is its own task; this spec lands the
  `Iterator`/function-object combinator path first.

---

## 6. Open questions

**Q1: Same parameter recovered from two protocols a type conforms to.**

A type may conform to both `(Iterator T)` and `(DoubleIterator T)`. A constraint
names the protocol explicitly — `((Iterator S) I)` vs `((DoubleIterator S) I)` —
so recovery is never ambiguous *as written*. There is no unqualified-`Elem` form
in this design (unlike the earlier draft's `(type Elem)`), so the ambiguity the
earlier draft worried about cannot arise. **No decision needed.**

**Q2 (resolved): return-position assoc tyvars.** `E` in `(next (Maybe E))`
appears in the return type *before* the `&where` clause binds it. This is already
handled: `register-generic-defn` collects tyvars from the return type
(src/nucleusc.nuc:5131) and sizes capacity by node count (5100). With §3.3, `E`
also appears inside the constraint `((UnaryFn S E) F)`, so it is declared there
too, and §3.4's fixpoint marks it determined. The only genuinely new machinery
is §3.5's conformance-driven binding.

**Q3 (resolved): order of binding across interdependent constraints.** Handled by
the §3.4 / §3.5 fixpoint: constraints are resolved repeatedly until no new tyvar
is bound, so a parameter recovered by one constraint (`S`) can serve as input to
another (`((UnaryFn S E) F)`) regardless of textual order.

**Q4: cross-unit conformance-arg propagation.** §4.5 lists two migration rules
for stale `.nuch` records. Decide at implementation time whether the importer
re-runs `emit-extend` (rule a) or the format version bumps (rule b). Rule (b) is
simpler and acceptable in pre-release; rule (a) is more robust for mixed-version
imports.

**Q4 decision taken (implementation):** Rule (a) — the `.nuch` importer re-runs
`emit-extend` for imported `extend` forms, repopulating `args` from the freshly-
read protocol shape. Concrete parametric extends from importers work correctly.
Template-subject extends (free tyvars in the exporter's `(extend (Vector T) (Seq T))`
form) are re-registered as `TmplConformance` records; the per-instance `Conformance`
with substituted concrete args is produced at stamp time in the importing unit. This
is a pre-existing limitation (the template is re-registered, not the already-stamped
instances from the exporter), surfaced by A0 but not introduced by it.

---

## 7. Robot — implementation status

**What landed (A0–A2, stage11-collections branch):**

- **A0 — Conformance arg retention.** `Conformance` struct gained `args:ptr` and
  `nargs:i32` fields. `conformance-add` stores the resolved protocol-application
  arguments and enforces coherence (a second `extend` of the same `(type, proto)`
  pair with *differing* args is now an error rather than a silent no-op). At stamp
  time, `tmpl-conformance-check-instance` propagates the substituted concrete args
  into the per-instance `Conformance`. Bootstrap byte-identical.

- **A1 — `&where` parser.** `register-generic-defn`'s constraint loop now accepts
  `((Protocol Arg…) Var)` as well as the existing `(Protocol Var)`. Argument-pattern
  nodes are collected into new `con-args`/`con-nargs` fields on `Method`. The tyvar
  set is sized and populated by walking constraint arg nodes through the existing
  `count-pattern-nodes`/`collect-pattern-tyvars` helpers (no separate slot
  accounting). The determination check is extended to a fixpoint: parameter-
  determined tyvars seed it; tyvars recovered from a determined constraint variable's
  conformance position become determined; anything still undetermined after
  convergence is the existing error. Bootstrap byte-identical.

- **A2 — Dispatch-time binding.** After the standard positional unification in
  `generic-method-bind`/`unify-tpat`, a fixpoint resolves the parametric constraints:
  for each `((P Arg…) V)` whose `V` is bound to a concrete type `CV`, the conformance
  record's `args` are paired with `Arg…` — unbound tyvars are recovered, concrete/
  bound args are constrained (checked). The recovered bindings augment `out-bound` and
  flow unchanged through `generic-instantiate`/`monomorphize-form`. Clear diagnostics
  for missing conformance and constraint mismatch. Bootstrap byte-identical.

- **A3 — Examples, tests, docs.** `examples/assoc-types.nuc` and
  `tests/expected/assoc-types.out` cover: the `MapIter`/`UnaryFn` phantom-free
  combinator; `collect-all` (§2.5 standalone generic with `&where ((Iterator E) I)`);
  `sum-i32-iter` (constrain case — `((Iterator i32) I)` checks not recovers); a
  commented error case showing the constraint-mismatch diagnostic. The test is
  auto-discovered by `tests/run-tests.sh` (no `.nuc.fail` harness exists).

**Open questions resolved:**

- **Q2 (return-position assoc tyvars):** resolved-as-designed. `E` in
  `(next (Maybe E))` appears in the return type before the `&where` clause; this is
  fine because `register-generic-defn` already collects tyvars from the return type,
  and the fixpoint (§3.4) marks `E` determined via the constraint.

- **Q3 (order of binding across interdependent constraints):** resolved-as-designed.
  The fixpoint handles any textual order; `S` recovered from `((Iterator S) I)` is
  available as input to `((UnaryFn S E) F)` after one pass.

- **Q4 (cross-unit conformance args):** rule (a) taken — the importer re-runs
  `emit-extend` so args are repopulated from the freshly-read protocol shape.
  Template-subject extends re-register as `TmplConformance`; per-instance
  conformances with concrete args are produced at stamp time in the importing unit.
  This is a pre-existing limitation for cross-unit template stamps, not introduced
  by this feature.

**Known remaining limitation:** the `get`/`keys`/`vals` as `Assoc` protocol methods
uplift (§5 out-of-scope item) is mechanically enabled but remains a separate task.
The `&where` on a parametric protocol is now fully implemented; the pre-existing
"standalone `&where ((Seq E) Self)`" limitation noted in earlier progress tables is
resolved.
