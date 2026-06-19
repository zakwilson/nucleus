# Parametric structs

#### Designer

Stage 11 collections (`design/stage11/collections.md`) need generic container
types — `(Vector T)`, `(HashMap K V)`, `(HashSet T)` — and those are *parametric
structs*: a struct shape with one or more type parameters, stamped to a concrete
layout per use. The language has deferred this rung ("parametric generics /
generic-struct / associated types") since Stage 9. It is time to build it.

The bar is the same as everywhere in the polymorphism work: **no runtime overhead
when types are known at compile time.** A stamped instance must be an ordinary
monomorphic struct — identical IR, layout, ABI, and `sizeof` to the same struct
written out by hand.

#### Robot — design

This is a thin generalization of machinery that already exists. `defunion`
templates (`(defunion (Result T E) ...)`) already do exactly this for *tagged
unions*; bounded generic `defn` (Stage 9 rung 4) already monomorphizes *function
bodies* over type variables. Parametric structs are the struct analogue, and they
reuse both substrates rather than introducing a parallel one.

## 1. What already exists to build on

The union-template path is the blueprint (all line numbers `src/nucleusc.nuc`):

- **`UnionTemplate` registry** (src:150) — `{name, tyvars, ntv, form}`. Populated by
  **`register-union-template`** (src:2057): the head `(Result T E)` yields the name
  and the tyvar-name array; the whole `(defunion …)` form is retained verbatim.
  Registering a template defines **no type and emits no IR**.
- **Stamping** — **`union-template-stamp-types`** (src:2128): given concrete argument
  `Type*`s it (a) builds a mangled instance name `Result.<tok>.<tok>` via
  **`type-mangle-token`** (src:3915), (b) **memoizes** by that name
  (`uniondef-lookup`), and (c) on a miss substitutes the tyvars into the retained
  arm AST with **`subst-tyvars-node`** (src:4402) and registers the concrete instance
  (`defunion-register`).
- **`subst-tyvars-node`** (src:4402) / **`subst-tyvars-sym`** (src:4380) — structural
  copy of a Node tree replacing each tyvar symbol with the concrete type's spelling.
  Already handles the colon-sugar spellings (`ptr:T`).
- **Bounded-generic monomorphizer** — **`monomorphize-form`** (src:4583) stamps a
  concrete `defn` from a generic one by running `subst-tyvars-node` over the name,
  params, and body, queuing the result on the instantiation worklist (src:578).

Parametric structs add a **`StructTemplate`** registry and a
**`struct-template-stamp-types`** that mirror the union pair, and they lean on
`monomorphize-form` unchanged for the *methods* defined over a template.

## 2. Surface syntax

A `defstruct` whose name position is a **list** is a template (exactly the
`defunion` rule):

```lisp
(defstruct (Vector T)
  data:(ptr T)
  len:usize
  cap:usize)

(defstruct (HashMap K V)
  buckets:(ptr (Entry K V))
  ...)
```

The parameters are bare symbols; a single-element name list `(Foo)` (no params) is
an error — use a plain `defstruct`. Parameters are **types only** in v1; non-type
parameters (a compile-time array length, an integer) are out of scope (§9).

**Type application** — `(Vector i32)` — names the stamped instance type. It is legal
anywhere a type is: a field type, a `defn` parameter/return type, a `cast` target, a
`sizeof` operand, an `alloca`/`array` element. The colon-sugar composes:
`ptr:(Vector i32)` and `(ref (HashMap CStr i32))` both work.

## 3. Stamping and memoization

`struct-template-stamp-types` parallels src:2128 step for step:

1. **Mangled name.** `Vector` + `.` + `type-mangle-token` per argument →
   `Vector.i32`, `HashMap.CStr.i32`. Identical scheme to union instances and
   overloaded-fn mangling, so cross-unit stamps of the same instance collide on the
   same name (intended — memoization).
2. **Memoize** via `lookup-struct` on the mangled name. A hit returns the existing
   `type-for-sdef`; the instance is stamped at most once per unit.
3. **On a miss**, `subst-tyvars-node` rewrites the retained field-spec list (the
   template `form`'s cdr-cdr) with the concrete spellings, then the result is fed to
   the **existing `emit-defstruct`** path (src:9603) under the mangled name —
   producing a normal `StructDef` with concrete `field-types` and a normal
   `%Vector.i32 = type { … }` IR line. No new layout code: a stamped instance *is* an
   ordinary struct from `register-struct` (src:1472) onward.

**IR-emission timing.** A stamp can be triggered mid-emission (a `defn` signature
deep in a function references `(Vector i32)` for the first time). Unions already
solved this with a deferred-emission queue drained at a safe point
(`drain-pending-union-irs`, see [../stage10/progress.md](../stage10/progress.md) U1). Struct templates reuse the same
discipline: stamping *registers* the `StructDef` and *queues* its `%name = type {…}`
line; the queue drains at top-level boundaries (and into the REPL preamble) so the
type definition is never emitted in the middle of a function body. The `emitted`
flag on `StructDef` (src:9614) already guards against double-emit.

**Recursion.** A template that refers to its own instance through a pointer —
`(defstruct (Tree T) val:T left:(ptr (Tree T)) right:(ptr (Tree T)))` — stamps fine:
the pointer field needs only the *name* `Tree.i32`, which `register-struct` reserves
before fields are filled, so the self-reference resolves to the in-progress
`StructDef`. A template that embeds its own instance **by value** is an infinite
layout and is rejected (the same rule plain structs already enforce via
definition-before-use).

## 4. Methods over a parametric struct

A function over a template introduces the template's parameters as type variables
bound by the receiver:

```lisp
(defn count:usize (self:(ref (Vector T)))
  (return (self len)))

(defn push:void (self:(ref (Vector T)) x:T)
  (vector-ensure-cap self (+ (self len) 1))
  (aset! (self data) (self len) x)
  (.set! self len (+ (self len) 1)))
```

This is **bounded generic `defn`** (rung 4) with the tyvar list *inferred from the
parametric receiver* instead of written in `&where`. Mechanically: when a `defn`
parameter or return type mentions a registered struct template applied to free
symbols (`(Vector T)`, `T`), those free symbols become the method's tyvars, and the
method is queued for monomorphization exactly like an explicit `&where` generic.
Each concrete receiver type (`Vector.i32`) stamps the method body through
`monomorphize-form` (src:4583), substituting `T` → `i32`. The `&where` form remains
available for extra bounds (`&where (T Ord)`), which §5 needs.

**Resolution / zero overhead.** A call `(push v 3)` with `v : (ref Vector.i32)`
resolves to the stamped `push` for `Vector.i32` through the ordinary generic
resolver — a direct `call`, inlinable, no dispatch object. Field access `(v len)` /
`(. v len)` on the stamped instance is a static GEP+load (callable-values.md): the
instance is concrete, so member access is byte-identical to any hand-written struct.

## 5. Protocol conformance (and the element-generic gap)

Collections must conform to `Coll` / `Seq` / `Assoc` etc. Two layers:

- **Extend the template.** `(extend (Vector T) Coll)` asserts that *every* instance
  conforms. Conformance is checked **at stamp time**: when `Vector.i32` is stamped,
  the required methods (`count`, `iter`, …) must resolve for that instance, else a
  def-time error naming the missing method — the same checked-but-code-free model as
  today's `extend` (Stage 9 rung 2), lifted to "check per stamped instance."
- **Element-generic protocols (the real new requirement).** `Seq.get` returns the
  *element* type; `map` returns a collection of the *mapped* element type. Today a
  protocol substitutes only `Self` (`lib/seq.nuc` fixes `:i32`). A `Seq` abstract over
  element type needs the protocol to carry the element as a parameter —
  `(defprotocol (Seq E) (get:E (self:(ref Self) i:usize)) …)` — i.e. **parametric
  protocols / associated types.** This is the genuinely new design surface; §1's
  template machinery does not supply it.

  **Recommended scope for Stage 11:** support **parametric protocols** of the shape
  `(Protocol Self E…)` where the extra parameters are bound by the conforming
  instance — `(extend (Vector T) (Seq T))` binds `E := T`. That is enough for the
  collection protocols and is a direct generalization of the `Self`-only substitution
  already in `emit-extend` (src:2600). Full **associated types** (the element type
  *derived* from `Self` rather than supplied at `extend`) are deferred; spelling the
  element explicitly at the `extend` site avoids them.

## 6. Construction and the compound-literal ambiguity

Plain structs already have a value-position constructor: `(S e0 e1 …)` is a compound
literal yielding `ptr:S` (src:8834, src:9159). For a template this **collides** with
type application: in `(Vector i32 …)`, is `i32` a type argument or the first field
value? Unions dodge this (their constructors are the arm names `ok`/`err`, never the
type name). Structs cannot.

Resolution:

- **Type application is recognized in type position only** (after a `:`, or as a
  `defstruct` field type / `defn` signature type / `cast` target). There it always
  means "stamp the instance."
- **Value position uses the explicit form** `((Vector i32) v0 v1 …)`: the inner
  `(Vector i32)` stamps the type, the outer application is the ordinary compound
  literal over that concrete instance. This nests cleanly and is what the
  collections reader macros expand to (`[1 2 3]` → `((Vector i32) 1 2 3)`).
- **Bare `(Vector v0 v1 …)` in value position is an error** for a template name
  (ambiguous) — the diagnostic points at the explicit form.

In practice the heavyweight collections heap-allocate and own a buffer, so they are
built by **library constructors** (`vector-new`, `into`) and `make`-style helpers,
not bare compound literals; the explicit form matters mostly for lightweight value
structs like `(Pair K V)`.

## 7. C ABI and `.nuch` export

- **ABI.** A stamped instance is a monomorphic `TY-STRUCT`, so the Stage 8 SysV
  classifier (`abi-classify`) applies unchanged — by-value params/returns, `byval`/
  `sret`/register coercion all just work.
- **C name.** `Vector.i32` is not a valid C identifier. Export sanitizes the dot to a
  C-legible form (`Vector_i32`) via the existing `sanitize-for-ir`-style mapping used
  for mangled symbols, so `--emit-cheader` and `.nuch` consumers see a legal name.
- **`.nuch` export.** Mirror union templates: export the **template verbatim**
  (`(defstruct (Vector T) …)`) plus any stamped instances the unit actually used; an
  importer re-registers the template (a re-import is a no-op, src:2068) and
  **re-stamps on demand**. Methods over the template export as the existing rung-4
  generic `defmethod`/monomorphization machinery already exports them. The
  `emit-nuch-defstruct` path (src:11205) gains a template-name branch.

## 8. Index type prerequisite (`usize` / `ssize`)

Collections want a portable pointer-sized index/length type. There is **no
pointer-sized integer spellable in `.nuc` source** — `parse-type-name` knows
`i8…i64`, `ui8…ui64`, etc. but no pointer-sized alias (C's `size_t` is resolved only
inside the C-header parser, `src/cheader.nuc:96`, and is not a Nucleus type). Add two
builtin scalars — **`usize`** (unsigned) and **`ssize`** (signed) — that resolve to
the target's pointer-sized integer via `g-target-ptr-bytes` (the helper at src:901
already computes that IR type for `sizeof`). Small, self-contained, and required
before the collection signatures in collections.md can be written. Until they land,
`ui64`/`i64` are the stand-ins (correct on LP64, wrong on ILP32).

## 9. Scope and non-goals (v1)

- **Type parameters only.** No value/const parameters (`(Array T N)` with integer
  `N`) — deferred; fixed-size arrays stay a separate concern.
- **No partial application / higher-kinded params.** `(Vector T)` is applied to
  concrete types at use; you cannot pass `Vector` itself as a parameter.
- **No variance / subtyping.** `(Vector Cat)` is unrelated to `(Vector Animal)`;
  there is no subtyping in the language and none is added.
- **Associated types** (element derived from `Self`, not supplied at `extend`) —
  deferred (§5); parametric protocols with explicit element params are the v1 answer.
- **Heterogeneous instances** still need `dyn` (deferred to stage999).

## 10. Hook points (current line numbers)

- **Registry + register:** new `StructTemplate` struct beside `UnionTemplate`
  (src:150); `register-struct-template` modeled on `register-union-template`
  (src:2057); a `struct-template-lookup` beside `union-template-lookup` (src:1736).
- **Top-level dispatch:** `emit-defstruct` (src:9603) routes a *list* name to
  `register-struct-template` (define-no-IR), a *symbol* name to today's path.
- **Stamp:** `struct-template-stamp-types` modeled on `union-template-stamp-types`
  (src:2128) — mangle (`type-mangle-token`, src:3915), memoize (`lookup-struct`),
  `subst-tyvars-node` (src:4402), feed to the `emit-defstruct` body under the mangled
  name, queue the IR line (drain like `drain-pending-union-irs`).
- **Type parsing:** `parse-type-from-node` (src:2152) recognizes a list head that
  names a struct template and routes to the stamp (the union-template branch already
  shows the pattern for `(Maybe (ref T))` / `!T`).
- **Methods:** reuse `monomorphize-form` (src:4583); the tyvar-from-receiver
  inference is the only new piece in the `defn` prescan.
- **Conformance:** `emit-extend` (src:2600) gains the parametric-protocol element
  binding (§5); per-instance conformance check fires at stamp time.
- **Construction:** the compound-literal sites (src:8834, src:9159) reject a bare
  template name and accept the explicit `((Vector i32) …)` head.
- **Export:** `emit-nuch-defstruct` (src:11205) template branch.

## 11. Staging

Each step keeps `make test` / `make bootstrap` green and byte-identical for programs
that use no templates (the registry is inert until a stamp fires).

1. **`usize` / `ssize` builtin scalars** (§8) — independent, unblocks signatures.
2. **Template registry + stamping** (§§2–3): `(defstruct (Vector T) …)` registers;
   `(Vector i32)` in type position stamps a concrete struct; field access and
   `sizeof` work. No methods yet.
3. **Methods over templates** (§4): tyvar-from-receiver inference → `monomorphize-form`.
4. **Construction** (§6): the explicit `((Vector i32) …)` form; bare-name rejection.
5. **Parametric-protocol conformance** (§5): `(extend (Vector T) (Seq T))`, stamp-time
   check. This is the gate for collections' `Coll`/`Seq`/`Assoc`.
6. **C ABI + `.nuch` export** (§7): cross-unit templates, `--emit-cheader`.

## Open questions

1. **Element-generic protocols (§5).** *Resolved:* parametric protocols
   `(Protocol Self E…)` with the element bound at `extend` are the v1 answer; full
   associated types stay deferred.
2. **Method tyvar binding (§4).** Inferred-from-receiver only, or also require/allow
   an explicit `&where (T …)` to *name* the parameters? (Recommend: infer, with
   `&where` available purely for added bounds.)
3. **Construction surface (§6).** Confirm `((Vector i32) …)` as the value-position
   constructor and bare `(Vector …)` as an error for templates.
4. **Index scalar (§8).** *Resolved:* add both `usize` (unsigned) and `ssize`
   (signed) pointer-sized builtins.
5. **Stamp-time vs use-time conformance error (§5).** Report a missing `Coll` method
   when the instance is stamped, or lazily when a `Coll`-bounded call needs it?
   (Recommend stamp-time, for earlier/clearer diagnostics.)

#### Robot — implementation status

T0–T5 are fully implemented and all 75 tests pass; `make bootstrap` is a
byte-identical fixed point. Status detail lives in
[progress.md](progress.md) (stage 11 parametric structs table); user-facing
documentation in `docs/builtins.md` §"Parametric struct templates" and
§"Parametric protocols"; runtime coverage in `examples/parametric.nuc`,
`examples/import-parametric.nuc`, and `tests/abi/interop.nuc`.

**Open questions resolved as recommended:**

- **OQ2 (method tyvar binding):** RESOLVED as recommended — tyvars are inferred
  from the parametric receiver; `&where` is available purely for extra bounds.
  No `&where` clause is required (or allowed) to name the receiver-inferred
  variables.
- **OQ3 (construction surface):** RESOLVED as recommended — `((Vector i32) v0
  v1 …)` is the value-position constructor; bare `(Vector v0 v1 …)` with a
  template name in head position is a compile-time error pointing at the
  explicit form.
- **OQ5 (conformance error timing):** RESOLVED as recommended — conformance is
  checked at stamp time; a missing required method causes a def-time error
  naming the method when the concrete instance is first stamped.

**Known limitations (record for future work):**

1. **Colon binding sugar with a parenthesized RHS is unsupported.** A parameter
   spelled `name:(ref (Vector T))` does not tokenize correctly. Use the list
   binding form: `(name (ref (Vector T)))`. This is a pre-existing tokenizer
   limitation, not specific to parametric structs.
2. **`declare` with a parametric return type** requires the list-form name node:
   `(declare (p2_make (P2 i32 i32)) (...))`.
3. **Generic functions bounded on a parametric protocol** (`&where ((Container
   E) Self)` / associated-element bounds) are not supported in v1 — the `&where`
   parser requires `(Protocol Var)` with plain symbols. This is the deferred
   associated-types frontier (§9); conformance is exercised via `extend` +
   stamp-time checking + ordinary overload resolution of the protocol methods on
   a conforming instance. See `examples/parametric.nuc` for the working pattern.
