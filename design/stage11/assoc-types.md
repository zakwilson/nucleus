# Associated types for protocols

**Status:** Design only — not yet implemented.
**Prerequisite:** Stage 11 cleanup §4a (phantom-param tyvar-recovery fix) — done.
**References:** parametric-structs *Known limitations #3*; cleanup §4b finding.

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

`&where` currently requires `(Protocol Var)` where both are **plain symbols**.
You cannot write:

```lisp
(defn map-into ... &where ((Iterator I) with (Elem = E)))
```

The parser (`register-generic-defn`, "each &where constraint must be (Protocol
Var)") rejects a parametric protocol name in the constraint position. This is
the "parametric-protocol `&where` frontier" (Known limitations #3).

### 1.3 What associated types solve

An associated type is a type name that a protocol *exposes*, and that a
conformer *binds* when it extends the protocol. Once `VecIter T` binds
`Elem = T` as part of its `(Iterator T)` conformance, any generic function
bounded on `(Iterator I)` can recover `Elem` from `I` without threading an
extra phantom param.

The desired end state:

```lisp
; No phantom params: MapIter is (MapIter I F), full stop.
(defstruct (MapIter I F)
  source:I
  f:F)

; 'E' is derived from the Iterator conformance of I, not declared separately.
(defn (next (Maybe E)) ((self (ref (MapIter I F)))
                        &where ((Iterator I) with (Elem = E))
                               ((CallFn F S E) with (Src = S)))
  ...)
```

---

## 2. Surface syntax

### 2.1 Declaring an associated type in a protocol

Use a `(type Name)` declaration inside `defprotocol`, before the methods:

```lisp
(defprotocol (Iterator Elem)
  (type Elem)
  ((next (Maybe Elem)) ((self (ref Self)))))
```

The `(type Elem)` line declares that `Elem` is an **associated type** of this
protocol. The position of `Elem` in the `(Iterator Elem)` parameter list still
matters (it is the first — and for this protocol, only — extra param). The
`(type ...)` declaration signals that this param is *associated* (bound by the
conformer) rather than *parametric* (supplied at every use site).

**Decision:** Use `(type Name)` rather than a sigil like `#Elem`. The `(type
...)` form is explicit, consistent with Nucleus's sexp style, and unambiguous
at the parser level — it is a list with head `type`, which is not a valid
method signature shape. A sigil `#Elem` would require a new reader token type
and complicates the parametric-protocol parameter list parsing.

For backward compatibility, **a protocol with no `(type ...)` declarations
remains purely parametric** — `(extend T (Protocol Arg))` syntax is unchanged.
A protocol with a `(type ...)` declaration gains the associated-type semantics
described below.

### 2.2 Conformance: binding the associated type

When a type extends a protocol that has associated types, the associated type is
bound by the conformance declaration. The existing `(extend T (Protocol Arg))`
syntax already carries this information — no new syntax is needed:

```lisp
; VecIter T conforms to (Iterator T) — so Elem is bound to T.
(extend (VecIter T) (Iterator T))

; IntRangeIter always yields i32 — so Elem is bound to i32.
(extend IntRangeIter (Iterator i32))
```

The associated type binding is: for each `(type Name)` declared in the
protocol, the corresponding positional argument in the `(Protocol Arg...)` list
in the `extend` form is the concrete type.

For `(Iterator Elem)`, `Elem` is the first (and only) extra param, so the first
argument to `(Iterator ...)` in the `extend` form is the bound value of `Elem`.

**No new syntax in `extend`.** The conformance record stored in `g-conformances`
gains an associated-type binding map, but the source form is unchanged.

### 2.3 Method signatures within the protocol

Inside the protocol body, `Elem` is used as a free type name in method
signatures. This is unchanged from the current parametric-protocol form:

```lisp
(defprotocol (Iterator Elem)
  (type Elem)
  ((next (Maybe Elem)) ((self (ref Self)))))
```

When the protocol is stamped for a concrete conforming type, `Elem` resolves to
the bound value from the conformance record.

### 2.4 Using the associated type in `&where` bounds

The key new syntax: inside a `&where` clause, a bound on a protocol with
associated types may optionally bind the associated type to a local tyvar:

```lisp
&where ((Iterator I) with (Elem = E))
```

This reads: "I conforms to `Iterator`, and the associated type `Elem` of that
conformance is bound to the tyvar `E` in this function's scope."

Multiple associated types in a single bound (not covered in this spec — see
§7.1) would use additional `(Name = V)` pairs.

A complete `defn` using this syntax:

```lisp
(defstruct (MapIter I F)
  source:I
  f:F)

(defn (next (Maybe E)) ((self (ref (MapIter I F)))
                        &where ((Iterator I) with (Elem = E))
                               ((Fn1 F E S) with (Src = S) (Dst = E)))
  (let ((res (Maybe S)) (next (.& self source)))
    (match res
      ((some v) (return (some (invoke (.& self f) v))))
      (none (return none)))))
```

When `MapIter` is stamped for a concrete `I=VecIter.i32`, the compiler:
1. Looks up the `(Iterator I)` conformance for `VecIter.i32`.
2. Reads the associated-type binding: `Elem = i32`.
3. Binds `E = i32` in the method's tyvar scope.
4. The return type `(Maybe E)` resolves to `(Maybe i32)`.

### 2.5 Standalone generic functions bounded by associated type

Associated-type `&where` also works in standalone generic functions:

```lisp
(defn collect-all ((it (ref I)) (out (ref (Vector E)))
                   &where ((Iterator I) with (Elem = E)))
  (let (done:i32 0)
    (while (= done 0)
      (let ((item (Maybe E)) (next it))
        (match item
          ((some v) (conj out v))
          (none (set! done 1)))))))
```

Here `E` is derived automatically from `I`'s conformance, so the caller writes:

```lisp
(let ((v (ref (Vector i32))) (alloca (Vector i32)))
  (vector-init v)
  (let ((it (ref IntRangeIter)) (alloca IntRangeIter))
    ; ... init it ...
    (collect-all it v)))
```

No phantom param for the element type.

---

## 3. Stamping and conformance-checking changes

### 3.1 `g-conformances` registry format

Currently `g-conformances` stores `(conforming-type, protocol-name, extra-args)`
tuples. The extra-args carry the positional arguments from `(extend T (Protocol
A B ...))`.

**Change:** extend each conformance entry with an **associated-type binding map**:

```
g-conformances entry:
  { conforming-type    ; concrete type key (e.g. "VecIter.i32")
    protocol-name      ; e.g. "Iterator"
    extra-args         ; list of concrete types (positional, as today)
    assoc-bindings     ; (name → concrete-type) for each (type Name) in protocol
  }
```

For `(extend (VecIter T) (Iterator T))` with `T` stamped to `i32`:
- `extra-args = [i32]`
- `assoc-bindings = {Elem → i32}`

The `assoc-bindings` map is populated at `emit-extend` time, immediately after
the extra-args are bound. For each `(type Name)` declared in the protocol (in
order), the corresponding positional extra-arg is the concrete type, and the
binding `Name → concrete-type` is stored.

The `assoc-bindings` map is **keyed by the associated-type name** (a string),
**valued by a type node** (the same representation as an extra-arg).

### 3.2 `emit-extend` changes

`emit-extend` currently validates that the extra-args count matches the
protocol's param count, then stores the conformance.

**Add:** after storing the conformance, build the `assoc-bindings` map. Walk
the protocol's `(type ...)` declarations in order; for each one, record
`name → extra-args[i]` in the map.

If the protocol has no `(type ...)` declarations, the map is empty and the
behaviour is unchanged.

**No change to source syntax** — the `(extend T (Protocol A))` form is identical.

### 3.3 `&where` parser changes

Currently `register-generic-defn` parses `&where` constraints as a flat list
of `(Protocol Var)` pairs, failing on any other shape.

**Change:** extend the parser to accept an optional `with (Name = Var)...`
suffix in a constraint:

```
constraint ::= (Protocol Var)
             | (Protocol Var) with (Name = Var) ...
```

The `with` keyword is checked after the `(Protocol Var)` pair is parsed. If
present, each `(Name = Var)` pair registers an associated-type tyvar binding
for this constraint.

These bindings are stored alongside the `&where` constraint in the generic
function's descriptor (the `g-generic-defns` entry), as a list of
`(assoc-name, local-tyvar-name)` pairs per constraint.

### 3.4 `unify-tpat` changes

`unify-tpat` recursively unifies a type pattern against a concrete type,
collecting tyvar bindings. It is called during method dispatch to bind the
receiver's tyvars.

**Add:** after unifying the receiver type pattern and collecting the standard
tyvar bindings, check whether any `&where` constraints have associated-type
bindings. For each such constraint `((Protocol V) with (Name = W))`:

1. Look up `V`'s concrete binding from the just-unified receiver bindings.
   (If `V` is the receiver type itself, it is already concrete.)
2. Look up the conformance of that concrete type in `g-conformances` for
   `Protocol`.
3. Read `assoc-bindings[Name]` from that conformance entry — this is the
   concrete type for `Name`.
4. Bind `W → concrete-type` in the current tyvar environment.

This is done **after** the standard positional unification, so the associated
bindings augment rather than replace it.

**Error cases:**
- If the concrete type for `V` does not conform to `Protocol`: emit a
  "does not conform to Protocol" diagnostic (the existing missing-conformance
  path), not a crash.
- If `Protocol` has no `(type Name)` declaration: emit a diagnostic "Protocol
  has no associated type 'Name'".

### 3.5 `register-generic-defn` changes

`register-generic-defn` builds the tyvar array for a generic function. The
array is currently sized by `count-pattern-nodes` over the parameter types (the
fix from cleanup §4a).

**Add:** for each `&where` constraint that has `with (Name = Var)` bindings,
include one additional tyvar slot per associated binding. This accounts for
tyvars that appear only in associated-type positions, not in any parameter
type pattern.

These extra tyvars are initialised to unbound and filled by `unify-tpat` at
dispatch time (§3.4).

### 3.6 `generic-resolve` / `generic-instantiate` changes

`generic-resolve` selects a generic method, then `generic-instantiate`
substitutes the concrete tyvars into the method body via `monomorphize-form`.

**No structural change** is needed in `generic-resolve` beyond the `unify-tpat`
augmentation in §3.4 — once the associated-type tyvars are bound by
`unify-tpat`, they flow through `generic-method-bind` → `generic-instantiate`
→ `monomorphize-form` unchanged. The monomorphiser already handles any
recovered tyvar by name lookup; the associated-type tyvars are just more names
in the same map.

### 3.7 Conformance check at stamp time

`struct-template-stamp-types` already calls `emit-extend` to check that a
stamped instance satisfies its declared `extend` forms. This is unchanged.

**What is new:** when a generic function is dispatched for a stamped type and
that dispatch path traverses an associated-type `&where` constraint, the
associated-type binding lookup (§3.4) must succeed. If it fails (the conformance
exists but has no `assoc-bindings` — i.e. was registered before this feature),
the error is "conformance for Protocol was registered without associated-type
bindings; re-extend or recompile". This handles transitional states during
migration (§4.1).

---

## 4. Migration path

### 4.1 Existing `(extend T (Protocol A))` forms

All existing conformances continue to work. The `assoc-bindings` map is
populated automatically from the `(type ...)` declarations in the protocol
definition and the positional extra-args in the `extend` form. The source
syntax is identical.

When an existing protocol gains a `(type Name)` declaration, all `(extend ...)`
forms that reference it are re-evaluated at compile time and the `assoc-bindings`
map is populated. No source changes to conformers are needed.

For the `Iterator` protocol specifically: `(extend IntRangeIter (Iterator i32))`
becomes, after the protocol gains `(type Elem)`, a conformance with
`assoc-bindings = {Elem → i32}`. The source line is unchanged.

### 4.2 Existing concrete-element combinators

`MapIterI64`, `FilterIterI64`, etc., in `lib/iterator.nuc` are fully
specialised to `i64` elements and use no phantom params. They are unaffected
by this change and continue to compile and run.

### 4.3 Phantom-param verbose forms

The `MapIterVerbose I F S E` pattern from `examples/phantom-tyvar-test.nuc`
continues to compile and run. It is the explicit threading workaround. Once
associated types are implemented, new code should prefer the two-param form
`(MapIter I F)` with `&where` associated-type extraction; existing verbose forms
need not be rewritten.

### 4.4 The `&where` parser backward compatibility

Existing `&where (Protocol Var)` constraints require no `with` clause and are
parsed identically. The `with` suffix is optional.

---

## 5. Out of scope

- **Multiple associated types per protocol.** The spec handles exactly one
  `(type ...)` declaration per protocol. Multiple associated types require a
  more complex conformance-binding map and disambiguation rules when two
  protocols expose types with the same name; deferred.

- **Higher-kinded types.** An associated type that is itself parametric (e.g.,
  `Elem = (Maybe T)` where `T` is free) requires higher-kinded unification;
  deferred.

- **Lambdas and closures.** The `F` (function object) type in combinators
  is always a named struct type conforming to a `Fn1`/`CallFn` protocol;
  anonymous function objects are a separate stage.

- **`get`/`keys`/`vals` as protocol methods on `Assoc`.** These return derived
  types (`(Maybe V)`, the key iterator type). Making them protocol methods would
  require associated types on `Assoc` as well; this spec covers `Iterator`
  only. `hmap-get` etc. remain standalone generic functions for now.

- **`&where` bounds on parametric protocols without associated types.** The
  parser still requires a plain-symbol protocol name in `(Protocol Var)` when
  `Protocol` is fully parametric (no `(type ...)` declarations). The
  `with (Name = Var)` extension handles only the associated-type case. The
  general parametric-protocol `&where` constraint (e.g., bounding on
  `(Seq i32)`) remains deferred.

---

## 6. Open questions

**Q1: Ambiguous associated type when a type conforms to multiple protocols with
the same associated-type name.**

If `VecIter T` conforms to both `(Iterator T)` and `(DoubleIterator T)`, and
both declare `(type Elem)`, then `&where ((Iterator I) with (Elem = E))` is
unambiguous (the protocol name disambiguates). But if a future generic function
writes `Elem` without a qualifying protocol, the compiler has no basis for
selection. **Decision needed at implementation time:** either (a) require the
qualifying `with` clause whenever there is ambiguity, emitting a diagnostic if
`Elem` is used unqualified and is ambiguous; or (b) require unique associated-type
names within a single conforming type across all protocols (a global constraint,
easier to check but restrictive).

**Q2: Associated-type extraction for a conformance that was stamped before the
protocol gained `(type ...)` declarations.**

If `lib/iterator.nuc` is compiled with the old `(Iterator E)` (no `(type
Elem)`), and then a downstream unit imports it and references a `(type Elem)`
declaration, the imported conformance records have no `assoc-bindings`. The
import/re-stamp path (`nuch` import) must re-evaluate `extend` forms on import
to populate `assoc-bindings` from the newly-declared protocol shape.
**Decision needed:** whether the importer triggers a re-`emit-extend` for all
known conformances of that protocol when the protocol definition changes on
import, or whether a simpler rule (recompile the library when its protocol gains
associated types) is acceptable in pre-release.

**Q3: Order of evaluation when `E` appears in a parameter type before the
`&where` clause that defines it.**

In:

```lisp
(defn (next (Maybe E)) ((self (ref (MapIter I F)))
                        &where ((Iterator I) with (Elem = E)))
  ...)
```

`E` appears in the return type `(Maybe E)` before `&where` establishes it. The
tyvar `E` must be registered at declaration time (from the `&where` clause) so
that `register-generic-defn` includes a slot for it, and then bound at dispatch
time (by `unify-tpat`). The existing `count-pattern-nodes` sizing (§4a fix)
handles parameter-position tyvars; return-position tyvars are currently sized
by `defn-has-receiver-tyvars`. **Verify at implementation time** that
associated-type tyvars appearing only in the return type are also included in
the tyvar array. The §3.5 fix (one extra slot per `with (Name = Var)`) should
cover this, but the interaction with `defn-has-receiver-tyvars` needs
explicit testing.
