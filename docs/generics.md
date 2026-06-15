# Generics, Polymorphism, and Protocols

## Polymorphism: overloaded `defn` (multimethods)

A `defn` whose name already exists but whose **parameter types differ** does not redefine — it adds a *method* to that name. Calls dispatch on the whole argument tuple (multiple dispatch).

```lisp
(defstruct Circle rad:i32)
(defstruct Rect w:i32 h:i32)

(defn area:i32 (c:ptr:Circle) (return (* (* (. c rad) (. c rad)) 3)))
(defn area:i32 (s:ptr:Rect)   (return (* (. s w) (. s h))))

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
(defn area:i32  (s:ptr:Circle) (return (* (* (. s rad) (. s rad)) 3)))
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

**Full associated types** (where the element type is *derived* from `Self`
rather than spelled explicitly at the `extend` site) are deferred. Parametric
protocols with explicit element binding at the `extend` site are the v1 form.
See `design/stage11/parametric-structs.md` §5 and §9.

**Limitation:** the `&where` parser requires single-symbol bounds
`(Protocol Var)`. Bounds that name a parametric protocol with an associated
element (`&where ((Seq E) Self)`) are not supported in v1 — the element-generic
frontier is deferred to a future pass. Generic functions bounded on a parametric
protocol must be expressed via ordinary `extend` + stamp-time checking on the
conforming type.

## Bounded generic `defn`

A `defn` whose parameter list carries a `&where` clause is a **bounded generic
template**: it is generic over one or more named type variables, each constrained
to a protocol. The body is *monomorphized* — re-emitted with the variables
substituted by concrete types — once per distinct instantiation, and cached.
Statically dispatched, zero runtime overhead.

```lisp
(import numeric)                          ; Eq / Ord / Num over the operators

(defn maxv:T (a:T b:T &where (Ord T))     ; T is a type variable bounded by Ord
  (if (< a b) b a))                       ; operators dispatch on T directly

(maxv 3 9)        ; → stamps @maxv.i32.i32; (< a b) is an inline icmp
(maxv 2.5 1.5)    ; → stamps @maxv.f64.f64; (< a b) is an inline fcmp
```

Because operators are generic methods, the body uses `<` directly and the
constraint is the standard `Ord`; built-in numeric types conform automatically.

- **`&where`** follows all value parameters; each constraint is single-variable
  `(Protocol Var)`. Multiple constraints are allowed (e.g. `&where (Ord T) (Show U)`).
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

*Not yet implemented:* same-name overloading that mixes imported and
locally-defined methods; `&rest` together with `&where`; REPL generic
instantiation; non-type/const parameters in parametric generics; higher-kinded
or partially applied type parameters.
