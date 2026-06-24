# Generics, Polymorphism, and Protocols

## Polymorphism: overloaded `defn` (multimethods)

A `defn` whose name already exists but whose **parameter types differ** does not redefine — it adds a *method* to that name. Calls dispatch on the whole argument tuple (multiple dispatch).

```lisp
(defstruct Circle rad:i32)
(defstruct Rect w:i32 h:i32)

(defn area:i32 (c:ptr:Circle) (return (* (* (c rad) (c rad)) 3)))
(defn area:i32 (s:ptr:Rect)   (return (* (s w) (s h))))

(defn kind:i32 (x:i32) (return 1))   ; overload on primitive type
(defn kind:i32 (x:f64) (return 2))

(defn sum:i32 (a:i32) (return a))            ; overload on arity
(defn sum:i32 (a:i32 b:i32) (return (+ a b)))
```

**Symbol mangling.** A name with a single method keeps its unmangled symbol `@name` and stays C-callable. A name with two or more methods becomes an overload set: each method is emitted under a mangled symbol `@name.<tok>...` where each `<tok>` names a parameter type (`i32`, `f64`, `pCircle` for `ptr:Circle`, the struct name for a by-value struct, …). The mangle decision is made after a whole-file prescan, so all methods of a name agree.

**Resolution (tiers).** A call resolves in order: **(0)** an exact match (structural type equality: primitives by identity, structs by definition, pointers by pointee); **(1)** a bounded-generic template whose constraints the arguments satisfy; **(2)** a safe **widen / untyped-int-literal** adaptation — an `i32` argument supplied where an `i64` method exists, or a literal `1` supplied where the parameter is `i8`/`f64` (the chosen arguments are coerced to the parameter types). A unique match wins; an ambiguous or absent match is a compile error listing the offending name. *(A `defcast`-based coercion tier is not implemented — no cast-rule registry exists in-tree.)*

**Return types may differ per method** (`(defn parse:i32 …)` vs `(defn parse:f64 …)` is fine since they dispatch on arguments). A return type bound only by no argument (no way to choose from the call) is out of scope.

**Cross-unit.** Overloaded functions export through `.nuch` as `defmethod` forms and dispatch correctly from an importing translation unit (link the importer against the library's `.o`). See [.nuch Header Format](compiler.md#nuch-header-format).

**Struct-typed parameters.** Because overloading on struct types is a primary use case, a `defn` parameter may be typed as a (pointer to a) struct defined later in the same file; struct names are pre-registered before signatures are scanned.

Implementation: a generic registry (`g-generics`) holds each name's method set; `emit-defn` emits each method under its resolved symbol; `emit-dispatch` routes a call head to an intrinsic operator, an overloaded set, or an ordinary scope-bound function. Solitary functions and C/extern calls take the ordinary path and emit byte-identical IR.

## Protocols: `defprotocol` and `extend`

A **protocol** names a capability — a set of required method signatures — and is purely compile-time: it emits no code. The signatures may mention the type variable `Self`.

```lisp
(defprotocol Shape
  (area:i32  (self:ptr:Self))
  (label:ptr (self:ptr:Self)))
```

`extend Type Protocol` is a **checked, code-free conformance assertion**. It runs after the whole-file prescan: for each required signature it substitutes `Self → Type` and requires that a concrete method already resolves at the exact tier (the implementations are ordinary overloaded `defn`s). It records the `(Type, Protocol)` fact and emits nothing.

```lisp
(defn area:i32  (s:ptr:Circle) (return (* (* (s rad) (s rad)) 3)))
(defn label:ptr (s:ptr:Circle) (return "circle"))

(extend Circle Shape)   ; OK — both methods exist for Circle
```

If a required method is missing, compilation fails with a diagnostic naming each absent method (e.g. `Square does not implement Shape.label`) — the precise error an overload set alone cannot give.

**`Self` and pointer-ness.** Conformance matching is by exact type, so the protocol signature's pointer-ness must match the implementation's. Since structs are conventionally passed by pointer, write `(self:ptr:Self)` to match `(defn … (s:ptr:Circle) …)`; a by-value `(self:Self)` would require a by-value `(s:Circle)` implementation.

**No code, multiple protocols per implementation.** Because `extend` adds no methods, one concrete function can satisfy several protocols at once — the protocol is a *predicate over the method set*, not the owner of an implementation.

**Protocol inheritance.** `extend`'s subject may itself be a protocol: `(extend Ord Eq)` declares that conforming to `Ord` additionally requires conforming to `Eq`, so `(extend i32 Ord)` records `(i32, Eq)` too. Operators satisfy protocol requirements for built-in numerics with no user method, so `lib/numeric.nuc`'s `Eq`/`Ord`/`Num` apply to `i32`/`i64`/`f32`/`f64` out of the box.

**Cross-unit.** `defprotocol` and `extend` (type-conformance and protocol-inheritance) export verbatim through `.nuch`; an importing unit re-registers the protocol and trusts the recorded conformance (it does not re-check). See [.nuch Header Format](compiler.md#nuch-header-format).

*Not yet implemented (within protocols):* inline-`defn` sugar inside `extend`, and the dynamic `(dyn Protocol)` form. Conformance currently requires a concrete (non-generic) implementation.

## Parametric protocols

A **parametric protocol** carries extra type parameters beyond `Self`. These
extra parameters are bound explicitly at the `extend` site, enabling element-
typed collection protocols without full associated types.

```lisp
(defprotocol (Seq E)
  (get:E ((self (ref Self)) i:usize))
  (len:usize ((self (ref Self)))))
```

The element parameter `E` is a free symbol in the protocol's required-method
signatures. At the `extend` site, bind it to the conforming type's element:

```lisp
(extend (Vector T) (Seq T))   ; binds E := T for each stamped Vector instance
```

Conformance is checked **at stamp time**: when `Vector.i32` is stamped, the
protocol's required methods (with `Self → Vector.i32` and `E → i32`) must
resolve to concrete implementations, else a compile-time error names the missing
method. This produces earlier, clearer diagnostics than lazy (use-time)
checking.

**Associated types** are supported: a parametric protocol's parameters are
*functionally determined by the conforming type* (the conformance registry keeps
at most one record per `(type, protocol)` pair), so a generic function bounded on
a parametric protocol can recover those parameters from the conforming variable
without threading them explicitly. The conformance record retains the bound
arguments (`(extend IntRangeIter (Iterator i32))` records `args = {i32}`), and a
`&where` bound names them. See [Associated-type bounds](#associated-type-bounds-where-protocol-arg--var)
below and `design/stage11/assoc-types.md`.

## Bounded generic `defn`

A `defn` whose parameter list carries a `&where` clause is a **bounded generic
template**: it is generic over one or more named type variables, each constrained
to a protocol. The body is *monomorphized* — re-emitted with the variables
substituted by concrete types — once per distinct instantiation, and cached.
Statically dispatched, zero runtime overhead.

```lisp
(import-use numeric)                      ; Eq / Ord / Num over the operators

(defn maxv:T (a:T b:T &where (Ord T))     ; T is a type variable bounded by Ord
  (if (< a b) b a))                       ; operators dispatch on T directly

(maxv 3 9)        ; → stamps @maxv.i32.i32; (< a b) is an inline icmp
(maxv 2.5 1.5)    ; → stamps @maxv.f64.f64; (< a b) is an inline fcmp
```

Because operators are generic methods, the body uses `<` directly and the
constraint is the standard `Ord`; built-in numeric types conform automatically.

- **`&where`** follows all value parameters; each constraint is a 2-element list
  whose tail is the conforming variable. The head is **either** a bare protocol
  name — `(Protocol Var)` — **or** a protocol *application* `((Protocol Arg…) Var)`
  for a parametric protocol (see [Associated-type bounds](#associated-type-bounds-where-protocol-arg--var)).
  Multiple constraints are allowed (e.g. `&where (Ord T) (Show U)`).
- **Type variables are declared-only:** a name is a type variable iff it is bound
  in a `&where` constraint. Any other unknown type identifier is still an
  `unknown type` error, so typos stay caught.
- **Binding** gathers the concrete type at every bare occurrence of a variable
  among the arguments and requires they agree; the bound type must conform
  (nominally, via `extend`) to the variable's protocol(s). There is no unifier:
  variables appear only in **bare** parameter/return positions. A nested position
  (`(ptr T)`, etc.) in a plain `&where` generic is rejected. For a parametric
  struct receiver, the type variable **is** permitted in nested positions like
  `(ptr T)` and `(ref T)` — those tyvars are inferred from the receiver, not
  supplied via `&where`. See [Parametric struct templates](structs-unions.md#parametric-struct-templates-defstruct-name-t-).
- **Abstract return (B1).** The return type may be a type variable bound by a
  parameter (`maxv:T` above); the concrete return is known per instantiation.
  A return variable bound by *no* parameter (Haskell `read`) is rejected — it
  needs the deferred `(dyn …)` form.
- **Resolution: concrete beats generic.** An exact concrete method always wins
  over a generic template for the same name (tier 0 ≫ tier 1).
- **Def-time checking (A2).** A template body is type-checked **once at its
  definition** against the abstract protocol interface, *before* any call. A value
  of type variable `T` is typed abstractly; a call on it that resolves to a method
  of `T`'s `&where` protocols (with `Self → T`), or to another generic whose
  constraints `T`'s constraints satisfy, is checked precisely (and yields a precise
  result type). The check is **lenient**: the only hard def-time error is a
  genuinely unknown function name (a typo) —
  ```lisp
  (defn maxv:T (a:T b:T &where (Ord T))
    (when (greater a b) …))   ; error at the defn: unknown function 'greater'
  ```
  A *known* operation that the abstract interface can't confirm — an operator
  (`(< a b)`), or a foreign/variadic call (`(printf …)`) on an abstract value — is
  **deferred to stamp time** rather than rejected, since it may well be valid for
  the concrete type (A1 catches it if not). When such a deferred call *does* fail
  for a concrete instantiation, the stamp-time error carries an instantiation note
  pointing back to the call site:
  ```
  file:NN: error: no matching method for overloaded 'dbl' with given argument types
    note: while instantiating @weird.f64.f64 (requested at file:12)
  ```
  The constraint protocol's existence is also checked at the `defn`.
- **Cross-unit.** A generic template exports verbatim through `.nuch`
  (`(defn (maxv T) ((a T) (b T) &where (Ord T)) …)`); an importing unit
  re-registers it (trusting the exporter's A2 check) and stamps its own
  instantiations locally, calling the exporter's concrete protocol methods by
  their mangled symbols.

Implementation: templates are registered as `METHOD-GENERIC` in `g-generics`
(retaining the body); `generic-resolve` adds the protocol-bound tier and, on a
unique match, `generic-instantiate` substitutes type variables, stamps a concrete
method (registered immediately so the call site can name its symbol) and queues
the body on a worklist drained at the end of the top-level loop. The A2 check
(`check-generic-templates` / `gcheck`) runs at the outermost top-level after all
names/protocols/conformances are registered, typing the body with parameters
bound to abstract `TY-TYVAR` types — which never reach codegen, since templates
emit only after monomorphization.

### Associated-type bounds: `&where ((Protocol Arg…) Var)`

When the bound names a **parametric protocol**, the constraint head is a protocol
*application* — the same spelling `extend` uses — and each argument is either
**recovered** or **constrained**:

```lisp
(defprotocol (Iterator Elem)
  ((next (Maybe Elem)) ((self (ref Self)))))

(defprotocol (UnaryFn Arg Ret)
  ((apply Ret) ((self (ref Self)) (x Arg))))

(defstruct (MapIter I F) source:I f:F)   ; no phantom params

(defn (next (Maybe E)) ((self (ref (MapIter I F)))
                        &where ((Iterator S) I)      ; recover S := I's element
                               ((UnaryFn S E) F))    ; check S, recover E := F's result
  (let ((res (Maybe S)) (next (.& self source)))
    (match res
      ((some v) (return (some (apply (.& self f) v))))
      (none (return none)))))
```

- **Recover vs. constrain is decided per-argument, at dispatch.** An argument that
  is an as-yet-unbound type variable (`S`, `E`) is **recovered** — bound to the
  value the conforming type's conformance recorded. An argument that is concrete
  (`((Iterator i32) I)`) or already bound is **constrained** — required to equal
  the recorded value, else a `constraint 'P' parameter mismatch: expected …,
  found …` error.
- **Recovery is a fixpoint.** A variable recovered by one constraint (`S` from
  `((Iterator S) I)`) can be the input of another (`((UnaryFn S E) F)`), so the
  constraints are resolved repeatedly until no new variable binds — regardless of
  textual order.
- **The conforming variable may be a free type parameter or a recovered tyvar.**
  It does not have to come from a struct-template application in the parameter list.
  A bare type parameter used directly as a parameter type — `C` in `(c (ref C))` —
  can be the conforming variable: `&where ((IterColl It) C)` recovers `It` from
  `C`'s `IterColl` conformance, with `C` itself bound from the call argument at
  dispatch. A tyvar recovered by an earlier constraint can in turn be the conforming
  variable of a later one: `&where ((IterColl It) C) ((Iterator E) It)` first
  recovers `It`, then uses it to recover `E`. The fixpoint and the dispatch-time
  binding handle both; see `examples/assoc-iter-return.nuc`.
- **Coherence makes this sound:** a type conforms to a given protocol at most once
  (the `(type, protocol)` dedup in the conformance registry), so the recovered
  arguments are functionally determined by the conforming type — no ambiguity, no
  runtime dispatch object, zero overhead. A monomorphized method is byte-identical
  to the same method with the types spelled out.
- **Missing conformance** (the conforming variable's type does not `extend` the
  protocol) rejects the candidate, surfacing the standard *no matching method* /
  *does not satisfy the required protocol constraint* diagnostic.

This replaces the older "phantom param" workaround, where the source and result
element types had to be declared as extra struct parameters and threaded by every
call site. See `design/stage11/assoc-types.md` for the full design.

### Conforming combinators: `&where` on `extend`

A generic combinator struct can itself **conform** to the protocol it implements
by placing a `&where` clause on the `extend` form. The protocol-application
argument is recovered at stamp time from the combinator's field conformances,
using the same fixpoint A2 runs at dispatch.

```lisp
(extend (MapIter I F) (Iterator E)
        &where ((Iterator S) I)        ; I yields S
               ((UnaryFn S E) F))      ; F maps S -> E; recover E
```

Read: "`(MapIter I F)` conforms to `(Iterator E)`, where `I` is an `Iterator`
yielding `S` and `F` maps `S → E`." `E` is neither a struct parameter nor
concrete — it is recovered from `F`'s `UnaryFn` conformance when a concrete
`(MapIter IntRangeIter SqFn)` is stamped.

**Syntax.** The `&where` clause is appended to the `extend` form using the
identical spelling used on `defn`. A `&where`-free `extend` is unchanged:

```lisp
(extend (Vector T) (Seq T))            ; T is a template param — unchanged
(extend IntRangeIter (Iterator i32))   ; i32 is concrete — unchanged
```

**Determination.** Every type variable appearing in the protocol application or
in any `&where` constraint must be *determined*:

1. **Seed.** The subject template's own parameters (`I`, `F`) are always
   determined — they are the stamp arguments.
2. **Step (repeat to fixpoint).** For each constraint `((Proto Arg…) V)` whose
   conforming variable `V` is determined, every tyvar in an `Arg` position
   becomes determined.
3. **Check.** Every tyvar in the protocol application must be determined after
   convergence. An undetermined tyvar is an error:
   ```
   extend: protocol parameter 'E' is not determined by the subject or any &where constraint
   ```

Worked example — `(extend (MapIter I F) (Iterator E) &where ((Iterator S) I) ((UnaryFn S E) F))`:

| pass | determined set | reason |
|---|---|---|
| seed | `{I, F}` | template params |
| 1 | `+S` | `((Iterator S) I)`: `I` determined → recover `S` |
| 1 | `+E` | `((UnaryFn S E) F)`: `F` determined → recover `E`; check `S` |
| done | `{I, F, S, E}` | `E` (protocol-app arg) is determined ✓ |

**Recover vs. constrain** follows the same per-argument rule as at the `defn`
site: an unbound tyvar is recovered, a concrete or already-bound value is
constrained (checked for equality against the recorded conformance arg).

**Stamp-time recording.** When a concrete instance such as
`(MapIter IntRangeIter SqFn)` is stamped, the recovery fixpoint runs against
`IntRangeIter`'s `Iterator` conformance and `SqFn`'s `UnaryFn` conformance.
The result — e.g. `Conformance{Iterator, args=[i32]}` — is recorded in the
conformance registry exactly as if the `extend` had been written with a concrete
arg. The stamped combinator is thereafter a first-class `Iterator`.

**Cross-unit.** A `&where`-bearing template `extend` exports through `.nuch` with
its `&where` clause intact. The exporter cannot serialize the per-instance
recovered args for instances it never stamped, so an importing unit re-runs the
template `extend` (parsing the `&where` clause, re-running the determination
fixpoint, and re-registering the template conformance); the stamp-time recovery
then fires in the importing unit when it stamps a concrete instance such as
`(MapIter IntRangeIter SqFn)`. A `&where`-free template `extend`
(`(extend (Vector T) (Seq T))`) is re-registered the same way. The conforming
variables' conformances (here `IntRangeIter`'s `Iterator`, `SqFn`'s `UnaryFn`)
must be in scope in the importing unit when it stamps the instance. See
[.nuch Header Format](compiler.md#nuch-header-format).

**Chaining.** Because a stamped combinator records an `Iterator` conformance,
it can be the *source* of another combinator. Stamping is bottom-up (the inner
struct is stamped first), so the inner conformance is recorded before the outer
combinator's recovery reads it:

```lisp
; FilterIter conforms to (Iterator S), recovering S from the source's conformance.
(extend (FilterIter I F) (Iterator S)
        &where ((Iterator S) I)
               ((UnaryFn S i32) F))

; A generic reduce over any Iterator, element type recovered from its conformance.
(defn reduce:Acc ((g (ref G)) (init Acc) (it (ref I))
                  &where ((Iterator S) I)
                         ((FoldFn Acc S) G))
  ...)

; Two-level chain: squares of [1,5) filtered to evens, summed = 4+16 = 20.
(reduce sum 0 (ref (FilterIter (MapIter IntRangeIter SqFn) EvenPred)))
```

See `examples/assoc-types-extend.nuc` for the complete working example
(a `map → filter → reduce` chain over `i32`, generically typed).

**Ordering.** The `extend` form (and the field types' own conformances) must be
processed before the instance is stamped. In practice, instances are stamped at
call sites in `main`-level code, which appears after all top-level `extend`
forms — the same ordering constraint that governs all `extend`. A multi-level
chain (`FilterIter` over `MapIter`) is handled by the bottom-up stamp recursion
already built into `struct-template-stamp`.

**Cross-unit combinators** are fully supported. The exporting unit serializes the
complete `extend` form (including its `&where` clause) through `.nuch`; the
importing unit re-runs the template `extend` via `emit-extend`, reconstructing the
`TmplConformance` and its constraint clause. Stamp-time recovery then fires in the
importing unit when a concrete instance is stamped there. See
`examples/assoc-types-extend-cross.nuc` for an end-to-end cross-unit chain test and
`design/stage11/assoc-types-extend.md` §10 for the design.

### Bound kinds: named protocols, blanket (`Any`/`Struct`), and `Valid`

A `&where` constraint names one of three kinds of bound (a name is still a type
variable iff it appears in a constraint, so every kind keeps tyvars declared-only
and typos caught):

| Bound | Conformance | Checked |
|---|---|---|
| named protocol (`Ord`, `Num`, …) | nominal, via `extend` | def-site (A2) + at the call |
| **blanket** `Any` / `Struct` (§10.1) | automatic / structural | nothing (`Any`); is-a-struct (`Struct`) |
| **`Valid`** (§10.2) | structural, **inferred from the body** | at the call site |

- **`Any`** is the no-constraint constraint — every type conforms, no methods
  required. It lets a fully generic function name its variable: `(defn id:T (x:T
  &where (Any T)) (return x))`. Operations on an `Any`-bound value are deferred to
  stamp time.
- **`Struct`** holds for any struct type or pointer-to-struct. (Its member-access
  `get` method is supplied by callable-values; see `design/stage9/callable-values.md`.)
  Both are **hardcoded** built-ins; a user-declarable blanket facility is parked in
  `design/stage999-future.md`.
- **`Valid`** does not name a protocol — the required interface is *inferred* from
  the body. At each call site the concrete type is substituted and the body is
  type-checked **without emitting** (the per-call-site non-emitting stamp), so a
  type that can't support an operation is rejected **at the call site**, and so are
  uses of values *derived* from `T`:
  ```lisp
  (defn twice:T (x:T &where (Valid T)) (+ x x))
  (twice 21)        ; ok — i32 supports +
  (twice some-ptr)  ; error at this call: 'ptr:Blob' does not satisfy the Valid bound of 'twice'
  ```
  `Valid` is itself written explicitly (it *nominates* structural checking); a bare
  `&where (T)` with no protocol remains an error.
  
Using `Valid` with a public API is risky whether it's inside the library code or a user
method on a library function because it may unexpectedly match unowned call sites. 
It's safer to prefer named protocols and treat `Valid` as an escape hatch.

### The `Clone` protocol

`Clone` is a prelude-registered protocol whose single method returns a fresh,
independently-owned copy of `Self`:

```lisp
(defprotocol Clone
  ((clone Self) ((self (ref Self)))))
```

It is the obligation `vfn` clone-capture imposes on each captured value (Stage 13,
`design/stage13/lambda.md`). Conformance has two paths, the same split built-in
numerics use for `Eq`/`Ord`:

- **Automatic (structural).** Any *trivially-copyable* type conforms automatically
  with a bitwise copy — a primitive (any scalar, pointer, `CStr`, `Err`, `usize`,
  …), or an aggregate (struct / untagged union) that does **not** conform to `Drop`.
  No `extend` is written; the conformance is recognized by a structural predicate
  alongside `Any`/`Struct` (`blanket-conforms`), so a Drop-free value satisfies a
  `&where (Clone T)` bound with no boilerplate and the closure that captures it owns
  nothing.
- **Hand-written (nominal).** An owning (`Drop`) type is *excluded* from the
  automatic rule — a bitwise copy of an owned resource would double-free — so it
  conforms by a hand-written `clone` plus `(extend <S> Clone)`, deep-copying its
  resources (a collection's `clone` allocates a fresh buffer through its stored
  allocator and copies the elements). A hand-written `clone` is an ordinary tier-0
  method, so it is dispatched in preference to the bitwise default whenever it
  exists.

A `Drop` type with **no** `Clone` conformance — neither automatic (it is `Drop`,
hence excluded) nor hand-written — is **not** `Clone`: a `&where (Clone T)` bound
rejects it at the call site. (Stage 13's `vfn` turns that rejection into a directed
"use `mfn` to move it instead" diagnostic.) Drop-ness is the same nominal,
transitively-recorded fact the `with` cleanup uses: a wrapper struct that owns a
`Drop` field is itself `extend`ed to `Drop`, so its own recorded conformance is the
transitive answer.

*Not yet implemented:* same-name overloading that mixes imported and
locally-defined methods; `&rest` together with `&where`; REPL generic
instantiation; non-type/const parameters in parametric generics; higher-kinded
or partially applied type parameters.
