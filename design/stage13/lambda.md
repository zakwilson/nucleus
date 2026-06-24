# Lambdas and closures

Languages with manual memory management rarely support closures because
capturing a variable allocated in a surrounding scope raises thorny questions
surrounding ownership, allocation, and deallocation. Nucleus already has most of
the machinery to constrain the problem; this stage assembles it into four
clearly-separated forms, introduces a `Clone` protocol, and extends the existing
escape analysis to make all four sound.

## Anonymous function vs closure

An **anonymous function** that does not capture any runtime values from its
enclosing scope can just be a function pointer. It is C-compatible and has no
runtime overhead.

A **closure** captures values and/or references from its enclosing scope. It has
to be concerned with ownership and lifetimes, has inherent runtime overhead (an
environment plus an indirect call), and cannot be cleanly called from C.
Closures are allowed in public APIs but trigger a compiler warning and are
excluded from generated C headers.

The dividing line is *what the form references from its enclosing scope* and
*how*, not which keyword is used:

| references from enclosing scope | form | representation | C-callable | overhead |
|---|---|---|---|---|
| only inlinable constants (or globals) | `fn` | function pointer | yes | none |
| runtime values, cloned | `vfn` | by-value struct (owning if a capture is `Drop`) | no | clone + indirect call |
| runtime values, moved | `mfn` | by-value owning struct | no | indirect call |
| runtime references | `cfn` | struct of pointers | no | indirect call |

Referencing a **top-level name** (`defconst`, a global `defvar`, another `defn`)
is *not* capture — it is an ordinary symbol reference, resolved the way any
function reaches a global. Only the use of an enclosing **local** (`let`/`with`
binding or a by-value parameter) is capture.

## Supporting features

Nucleus already has the tools to constrain the problem:

* `with` limits an owned allocation's lifetime to a given scope and runs its
  cleanup (`free`/`drop`) at scope exit.
* `Drop` lets the type system prove memory will be freed.
* `move` transfers an owned binding out, disarming its scope-exit cleanup and
  marking the source consumed (`docs/special-forms.md` §"move").
* The `Allocator` protocol specifies how a closure's environment is allocated
  and deallocated (`docs/allocators.md`).
* The `invoke` method makes a struct callable with ordinary call syntax
  (`docs/special-forms.md` §"Callable values"), so a closure object needs no new
  call form.
* The `with` escape analysis already tracks pointer provenance and rejects
  escapes for owned resources. This stage generalizes it to all frame-local
  storage (see [Lifetime and escape analysis](#lifetime-and-escape-analysis)).

## The `Clone` protocol

`vfn` captures by *value*, which for an owning (`Drop`) type must be a deep copy —
otherwise the source and the closure would both free one resource. This stage
introduces a `Clone` protocol for that:

```lisp
(defprotocol Clone
  ((clone Self) ((self (ref Self)))))
```

`clone` returns a new, independently-owned `Self`. A type that owns resources
implements it to deep-copy them (a collection's `clone` allocates a fresh buffer
through its stored `AllocHandle` and copies the elements). Allocation is internal
to `clone`, so `vfn` needs no allocator *parameter* even when a capture allocates.

**Automatic conformance.** Any trivially-copyable type — a primitive, or a struct
with no `Drop` field (transitively) — conforms to `Clone` automatically with a
bitwise copy, the same way built-in numerics conform to `Eq`/`Ord`
(`docs/generics.md`). Only a type that owns resources implements `clone` by hand.
A `Drop` type with no `Clone` implementation cannot be captured by `vfn`; the
compiler directs the author to `mfn` to move it instead.

## The four forms

Surface syntax (illustrative; the trailing `:ret` is the return type, matching
the `(x:i32):i32` convention — a parenthesized return type falls back to the
list form per the existing colon-paren rule):

```lisp
(fn          (x:i32):i32  body…)   ; anonymous function — no runtime capture
(vfn         (x:i32):i32  body…)   ; clone-capture closure (source survives)
(mfn         (x:i32):i32  body…)   ; move-capture closure (source consumed)
(cfn alloc   (x:i32):i32  body…)   ; reference-capture closure; alloc is a (ref AllocHandle)
```

`alloc` is the bare first operand — an argument, not a grouped sub-expression.
When it is itself a call producing the handle (`(default-allocator)`) the
parentheses are call parentheses, not grouping.

| form | capture | source after | requires | repr | alloc param | closure `Drop`? |
|---|---|---|---|---|---|---|
| `fn`  | none (inlinable consts) | unchanged | — | function pointer | no | no |
| `vfn` | clone | unchanged | `Clone` on captures | by-value struct | no | only if a capture is `Drop` |
| `mfn` | move | consumed | captures movable | by-value owning struct | no | yes (if it owns) |
| `cfn` | reference | borrowed | referents outlive closure | struct of pointers | yes | yes (frees env) |

### `fn` — anonymous function

`fn` is a true function pointer. Its body may reference:

1. its own parameters,
2. top-level names (`defconst` / global `defvar` / `defn`), and
3. enclosing locals **that are compile-time constants** — values that fold to an
   immediate and are inlined into the body, so there is no environment to carry.

Referencing a *runtime* local is a compile error directing the author to `vfn`,
`mfn`, or `cfn`:

```lisp
(defconst SCALE 3)

(map (fn (x:i32):i32 (* x SCALE)) v)        ; OK — SCALE folds to an immediate

(defn scale-by ((v (ref (Vector i32))) factor:i32)
  (map (fn (x:i32):i32 (* x factor)) v))     ; ERROR: 'factor' is a runtime local
                                             ;   note: use vfn (clone), mfn (move), or cfn (reference)
```

**Enforcement.** A free reference resolving to an enclosing local must be a
constant binding: a literal, `defconst`, enum constant, or a pure fold over
those. The compiler tracks a const-ness bit per binding. (Minimal first cut, if
const-folding of locals is deferred: `fn` may reference *no* enclosing local at
all — only parameters and top-level names — which is already sound and useful,
since `defconst` covers the constant case.)

`fn` is the only form emitted to C headers and the only form that decays to a
plain function pointer for callbacks like `qsort`.

### `vfn` — capture by clone

`vfn` clones each captured local into the environment (every capture must conform
to `Clone`). Its invariant: **the source always survives, untouched.**

```lisp
(defn scale-by ((v (ref (Vector i32))) factor:i32)
  (map (vfn (x:i32):i32 (* x factor)) v))    ; factor cloned (bitwise — i32 is POD)
```

For a POD capture, `clone` is a bitwise copy: no allocation, the closure owns
nothing, and the `vfn` is a carefree by-value struct — no `Drop`, no lifetime
concern. For an owning (`Drop`) capture, `clone` deep-copies: the closure owns an
independent copy, so the `vfn` conforms to `Drop` with a synthesized method that
drops its cloned fields, and it is a move-only owning value like the forms below.
The cost scales with the capture — copying a heavy value is heavy — but the
source is never invalidated.

A captured *pointer* value follows the frame-region rule like any pointer copy: a
cloned pointer does not extend its referent's life, so an escaping `vfn` over a
frame pointer is rejected (see the escape section).

### `mfn` — capture by move

`mfn` moves each captured owning local into the environment: the source is
**consumed** (use-after-move thereafter) and the closure becomes its sole owner.
This is the existing `move` sink (`docs/special-forms.md`) applied at the capture
site — explicit in the keyword, so the consumed source is intentional and the
existing use-after-move diagnostic guards mistakes.

The closure owns the moved-in resource, so an `mfn` conforms to `Drop`
(synthesized, dropping the moved fields) and is a **move-only** value. It needs no
allocator: the moved resource already owns its storage (and its own allocator) and
frees through the synthesized `drop`. Like `vfn` it travels by value.

`mfn` is the form that **exports an owned value out of a `with` scope** — the case
`vfn` cannot serve cheaply and `cfn` cannot serve at all:

```lisp
(with (buf:(Buffer) (make-buffer 1024))        ; buf is owned (Drop) in this scope
  (return (mfn (msg:CStr):void (append buf msg))))   ; buf MOVED into the closure
; the move disarms buf's with-cleanup; the returned closure now owns buf and
; drops it when the closure is itself dropped.
```

Returning the closure is legal precisely *because* the move transferred ownership:
`buf` is no longer with-owned (its cleanup is disarmed), so nothing dangles — the
resource leaves with the closure.

Choosing between `vfn` and `mfn` over a `Drop` capture is exactly the
source-survival question:

* need the source alive too → `vfn`, and pay for the clone;
* don't need the source → `mfn`, free, and the source is consumed.

### `cfn` — capture by reference

`cfn` captures each used local by reference and takes an explicit allocator and a
full type signature, returning an anonymous struct with an `invoke` method. The
environment is a struct of pointers into the captured storage.

```lisp
(with (buf:(raw ui8) (malloc 1024))
  (let ((log (cfn default-allocator (msg:CStr):void (write buf msg))))
    (consume log)))                  ; OK — log is consumed within buf's scope
;   (return log)                     ; ERROR: closure aliases with-owned 'buf', escapes
```

**The allocator is for the closure object's own storage**, not for the captured
variables (those are borrowed, not owned). A `cfn` that does not outlive its
creating frame can keep its environment on the stack; one that must persist has
its environment allocated through `alloc`, and the closure conforms to `Drop` so a
`with`-bound `cfn` frees that environment at scope exit, like a collection.

**Referent lifetimes are a separate obligation.** The allocator governs where the
environment lives; the escape/region analysis (below) guarantees the *referents*
outlive the closure. A returned `cfn` may therefore reference only things that
outlive the function — caller memory reached through a reference parameter,
globals, or heap owned by an outer scope — never a local of the creating frame.

To export a value computed from a captured reference, copy or `deref` it in the
body so the closure's result is a *value*, not a tainted reference (the existing
"copying the pointee out clears taint" rule).

## Representation and calling

All four closure forms lower to an **anonymous struct holding the captured state
plus an `invoke` method** of the closure's natural arity. Because callable-values
routes `(c arg…)` to `invoke` on the mere *existence* of an `invoke` method
(`docs/special-forms.md` §"Callable values"), a closure is callable with ordinary
syntax and needs no fixed protocol and no arity ceiling — arity is whatever
`invoke` declares.

**Conformance to function protocols is a use-site concern, derived on demand.**
Nothing about a closure pre-commits it to `UnaryFn`/`FoldFn` or any arity family.
A generic consumer that must *recover* element types from its function argument
(e.g. `MapIter` recovering result `E` from `F` via `&where ((UnaryFn S E) F)` —
`docs/iterators.md`) names the protocol/arity it needs in its own `&where` clause;
the compiler then synthesizes the closure's conformance by **structurally matching
`invoke` against the protocol's single required method**, reading the bound
arguments (`S`, `E`) straight off `invoke`'s parameter and return types. So the
`FnN` family is consumer-side vocabulary ("here is the shape I consume"), never an
obligation imposed on closures in general.

*Open mechanism question:* whether structural derivation fires for any
single-method "function-shaped" protocol or only a recognized set. The former is
more general; watch the `(type, protocol)` coherence/dedup interaction in the
conformance registry.

## Lifetime and escape analysis

Closing a closure over a reference to a stack local exposes a hole that already
exists in the language, independent of closures: a pointer to a local can escape
by being returned or stored, a use-after-free. This stage closes it by
generalizing the existing escape analysis.

### Two separate concerns

These must not be conflated:

1. **Ownership / `Drop` / cleanup** — *`with`-only*. Determines *what code runs*
   at scope exit (`free`/`drop`). `let` performs **no** lifetime checks and runs
   **no** drops; it is a plain binding. This stage does not change that.
2. **Frame-region escape checking** — a compile-time *pointer-provenance*
   analysis that applies to *all* frame-local storage (`let` and `with` value
   bindings, `alloca` results, by-value parameters). It runs no code and confers
   no ownership; it only decides whether a *pointer* may outlive the storage it
   points into.

A `with`-owned heap resource is subject to both: its `drop` runs at scope exit
(concern 1, existing) and its pointer may not escape (concern 2, existing). A
plain `let` local is subject only to concern 2 — and that is the part being
generalized. Crucially, **`let` gains no drop and no lifetime semantics**; the
analysis simply observes that frame storage is reclaimed at scope exit regardless
of how it was bound, so a pointer into it must not outlive its scope.

### Taint source

The new taint source is *taking the address of frame-local storage*:
`addr-of`/`.&`/equivalent applied to a `let`/`with` value binding, an `alloca`
result, or a by-value parameter (copied into the frame). It is **not**:

* a **reference/pointer parameter** — its pointee lives in the caller, so a
  pointer derived from it may be returned:

  ```lisp
  (defn first:(ref i32) ((v (ref (Vector i32))))
    (return (.& v …)))          ; pointee is caller-owned — stays legal
  ```
* a pointer **loaded out of** a frame-local — already an untracked imprecision
  boundary.

```lisp
(defn bad:ptr:i32 ()
  (let ((x:i32 5))
    (return (addr-of x))))      ; now rejected: address of frame-local 'x' escapes

(defn leak:ptr ((p Point))      ; by-value param — copied into the frame
  (return (addr-of (.& p x))))  ; rejected: address of a field of frame-local 'p'
```

### Regions and sinks

Each frame-local pointer is tagged with the **scope-id** of the storage it points
into ("region"). A store or return is an escape iff the destination *outlives*
(is a lexical ancestor of) the source's region; `return` is the outermost
destination. The lattice keeps the existing shape — **downward flow is a borrow
(allowed), upward escape is an error** — so passing `(ref (alloca …))` *down* into
inner scopes and callees still works; only escaping *up* is rejected.

Because scopes are lexical and the analysis is intraprocedural, a region is just a
scope-id and the check is a scope-ancestry comparison — a modest extension of the
boolean taint bit already propagated, not a general borrow checker.

`move` remains the sanctioned way to transfer out, and copying/`deref`-ing the
pointee out remains the way to extract a value (both clear taint), exactly as
today.

### How each form interacts

* **`fn`** — references no runtime local, so it produces no frame-region taint.
* **`vfn`** — clones values; a cloned *pointer* value carries the source's region
  like any pointer copy, so an escaping `vfn` over a frame pointer is rejected.
  An owning clone (`Drop` capture) is owned outright by the closure, so there is
  no referent to dangle — it is just a `Drop` value managed normally.
* **`mfn`** — the move disarms each source's cleanup and transfers ownership into
  the closure, so the closure may safely outlive the source's original scope;
  nothing dangles because ownership moved. The closure is a `Drop` value managed
  normally.
* **`cfn`** — the closure value **inherits the region of each captured
  reference**; if it escapes any captured referent's region, the escape is
  rejected at the existing sinks. This is the thin layer that makes
  `with`-over-`cfn` sound.

### Sequencing

Land the generalized frame-region escape check **before** the closure forms. It
is a standalone soundness fix (`return &local`) with value on its own, it lets the
region-tagging be validated on the simplest case before capture plumbing is added,
and it makes the closure forms fall out cheaply: `vfn`'s "captured pointer values
carry their region" becomes true by construction, and `cfn`'s rule collapses to
"inherit the region of each `(ref …)` capture; reject on escape."

## C interop

Capturing closures (`vfn`, `mfn`, `cfn`) are not C-callable. Internally that is
fine; but a public API that **exposes a closure type** — as a return type or as a
parameter type — is not C-representable, so:

* such a function (and any closure type it mentions) is **excluded from generated
  C headers** (`--emit-cheader`), and
* the compiler **warns** at the definition site.

A function that merely *takes* a closure but is only called internally is
unaffected. A non-capturing `fn` decays to a plain function pointer and is fully
C-callable, so it is emitted to headers normally.

## Compiler refactor

After the four forms are stable, many explicit loops in the compiler can be
replaced with `map`/`reduce`/`filter` over the `Seq`/`Iterator` protocols. This is
the dogfooding target — but the compiler is performance-sensitive and self-hosts,
so the refactor must use the **monomorphized, zero-cost path**: an `fn` or
POD-capturing `vfn` literal passed inline to a generic combinator is stamped
against the concrete element type and inlines to the same IR the hand-written loop
produced (a POD `vfn` clone is a bitwise copy). The structural conformance
derivation above is what lets such a literal satisfy a combinator's
`(UnaryFn S E)` / `(FoldFn Acc E)` bound without a hand-written function-object
struct. Owning or type-erased closures (the indirect-call, allocating path) should
stay out of hot compiler loops.

## Deferred / out of scope

* **Mixed per-variable capture** (some cloned, some moved, some by reference in one
  closure). The four forms fix the capture mode per closure; a value that must be
  copied uses `vfn`, one consumed uses `mfn`, a reference uses `cfn`. Body-level
  copy/`deref` handles per-value adjustment. A C++-style explicit capture list was
  considered and set aside in favor of the keyword-per-mode split.
* **Auto-derived `clone`** for `Drop` structs (a `#[derive(Clone)]`-style deep
  copy synthesized field-by-field). The protocol ships now; derivation is a later
  convenience — until then, owning types hand-write `clone`. May be revisited
  within stage 13 if hand-written `clone` proves too heavy for the closure
  use cases that drive this stage.
* **Self-reference / recursion.** An anonymous form cannot name itself; recursive
  closures (named-`let` / fixpoint) are out of scope.
* **Nested-region precision.** The first cut may use the function-frame boundary
  (catches the common cross-function `return &local` and returned-closure leaks);
  full per-binding region comparison is required for closures bound in an outer
  scope that capture an inner-scope local, and can follow once the coarse check is
  in place.
