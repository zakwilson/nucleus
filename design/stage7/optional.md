# Optional args

## Status

Shipped. `&optional` parameters work in `defn` with defaults evaluated at the
call site in the caller's scope. `&optional` cannot be combined with `&rest`.
Implicit casts apply to defaults. Function pointers and C interop see the
fixed full arity. See `examples/optional.nuc` for tests.

#### Designer

`(defn foo:int (bar:int &optional (baz:int 42) (qux:int 666)) ...)`

It should probably be an error to combine &optional and &rest. &optional args must provide default values. &optional args must go after required args.

#### Robot

Not ready to implement — the sketch leaves several decisions open and conflicts with prior design. Questions and comments below.

**Conflict with `stage6-rest-optional.md`.** That document (the prior design pass on this feature) explicitly says `&optional` and `&rest` *can* coexist, with `&optional` first: `(defn f (a &optional b &rest c) ...)` — rewrite fills in `&optional` defaults, then collects the leftovers into `&rest`. This document says the combination should be an error. Which wins? Banning it is simpler and matches the "fewest features needed" principle, but if we ban it we should update `stage6-rest-optional.md` to retract that section. Recommendation: ban for now, revisit if a real use case shows up.

**Default expression evaluation site.** `stage6-rest-optional.md` says defaults are evaluated *at the call site* (the Common Lisp default), so `(defn next:i64 (&optional (n:i64 (now-counter))))` gets a fresh counter per call. That implies the rewrite is a syntactic substitution before type checking — the default expression is spliced into the caller's lexical scope. Confirm? This has consequences:

- The default expression sees the *caller's* locals/macros, not the callee's. This is surprising if a default references something defined only in the callee's module.
- If we instead evaluate at definition site, defaults must be constants or refer only to module-level bindings — simpler but less expressive.
- Recommendation: call-site evaluation, matching CL and matching how `&rest` is already rewritten. Document the scoping consequence.

**Can defaults reference earlier parameters?** CL allows `(defn f (a &optional (b a)) ...)`. Useful but adds complexity (the rewrite must bind earlier args to fresh names to avoid double-evaluation when they're non-trivial expressions). Recommendation: defer; require defaults to be self-contained expressions in v1.

**Type of the default.** Must the default expression's type match the declared parameter type exactly, or do implicit casts (the other stage-7 feature) apply? Recommendation: implicit casts apply — that's the whole point of having both features in the same stage.

**Function pointers.** `&rest` already documents that taking a pointer gives the fixed-arity compiled form. For `&optional`, the compiled function has fixed maximum arity; calling through a pointer requires the caller to pass all args including the ones that would have defaulted. Confirm this is the intended behavior and document it.

**C interop.** `&optional` functions are fixed-arity at the ABI level (full arity, all params present), so C callers can call them — but must supply all arguments. The "optional" only applies to Nucleus call sites. Confirm and document.

**Call-site rewrite location.** Same pass as `&rest` (after macro expansion, before type checking)? Presumably yes — the infrastructure is shared. Worth stating explicitly.

**Test plan.** Suggest:
- `(defn foo:i64 (a:i64 &optional (b:i64 10)) (+ a b))` — `(foo 5)` → 15, `(foo 5 7)` → 12.
- Multiple optionals, partial fill: `(foo 1)`, `(foo 1 2)`, `(foo 1 2 3)`.
- Default expression is non-constant and call-site-evaluated.
- Default uses an implicit cast (e.g. `i32` literal default for an `i64` param).
- Error: `&optional` before required args.
- Error: `&optional` arg without a default.
- Error: `&optional` combined with `&rest` (assuming we ban it).
- Self-host pass.

#### Designer

Ban combining &rest and &optional. I had thought to allow the combination because Common Lisp allows them, but Common Lisp includes the kitchen sink and we're not doing that here. Ammend the old doc.

Evaluate at the call site and document.

We can defer use of bindings in defaults for the first pass if there are significant costs, but `let` allows bindings to reference previous bindings, so consistent behavior is strongly preferred here.

Implicit casts should apply in optional bindings.

Function pointers can remain fixed arity for now, as can C interop. Both should be documented.

The rewrite location should be the same as &rest.
