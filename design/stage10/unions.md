# Stage 10 — Unions & tagged sums (the type A1 needs)

#### Designer

[errors.md](errors.md) §2 gates the generic `(Result T E)` (option A1) on
sum-types work; [nullability.md](nullability.md) §1 gates `(Maybe T)` over
non-pointer payloads on the same work. Design the unions required for A1.

#### Robot — response

Two layers, following Zig's factorization (`union` vs `union(enum)`): an
**untagged union** — the C-parity primitive, raw and unchecked, which also
closes a stage-3c deferral that currently makes whole C headers unusable —
and **tagged sums** layered on it (`defunion` + `match`), which is what
`Result`, `Maybe`-over-values, and payload-carrying user enums actually need.
A final convergence step gives the layout engine the niche rules under which
A2's `!T` and N1's `?T` become *instances* of the general type rather than
special cases. Graded throughout against the stage invariants
([safety.md](safety.md) §2): zero mandatory cost, C-ABI neutrality, raw
escape hatches, library-where-possible.

## 1. Requirements, pulled from the gating docs

| Need | Source | Satisfied by |
|---|---|---|
| `(Result T E)` with arbitrary payloads, by-value return | errors.md §2 A1 | §3 + §5 (templates) |
| `(Maybe T)` over non-pointers (`{has, val}`) | nullability.md §1 | §3 (a two-arm sum) |
| Niche encoding applied by layout, not special-cased | stage999 sum-types note | §6 |
| C headers with unions usable (`SDL_Event`, `pthread_mutexattr_t`) | stage3c.md | §2 |
| An eliminator with exhaustiveness checking | errors.md, stage999 `match` | §4 |

## 2. Layer 1 — untagged unions (raw, C parity)

A new type expression mirroring the anonymous-struct form:

```lisp
(union as-int:i64 as-float:f64 as-bytes:ptr)   ; anonymous, memoized
(defstruct Event kind:i32 (data (union key:Key mouse:Mouse)))
```

- **Representation.** `TY-UNION` on `Type`; size = max member size, align =
  max member align; every member at offset 0. LLVM has no union type, so it
  lowers the way clang does: a struct wrapping the largest-aligned member
  plus padding to size; with opaque pointers, member access is just a typed
  load/store at offset 0 — no bitcasts.
- **Anonymous and memoized** like `(struct …)` (`__anon_union_h<hex>` via the
  same FNV machinery); named untagged unions come from C headers (below) —
  Nucleus code that wants a named one wraps the anonymous form in a
  `defstruct` field or a future alias form. The good name `defunion` is
  reserved for the tagged layer (§3): raw unions are the edge case, and the
  edge case shouldn't own the ergonomic spelling.
- **Checking: none.** Reading a member other than the one last written is a
  reinterpretation — exactly `cast`'s contract. Untagged unions sit on the
  raw frontier (greppable, `unsafe`-flavored) alongside `cast`/`ptr+`.
- **C import.** Today a union field causes the *entire containing struct* to
  be skipped and registered opaque (docs/builtins.md). With `TY-UNION` the
  header parser registers `union { … }` fields and named unions directly —
  the stage-3c options table resolves to its third option ("full union
  support"), and the SDL/pthread class of headers stops degrading.
- **C export.** `type-to-cheader` emits `union { … }`; `.nuch` round-trips
  the definition like anonymous structs.
- **ABI.** `abi-classify` extends from TY-STRUCT to TY-UNION: classify every
  member at offset 0 and merge eightbyte classes per the SysV rules (the
  merge logic already exists for overlapping struct eightbytes). Win64/i386
  classification stays deferred exactly as it is for structs
  (stage8/platform.md) — unions inherit that status, they don't worsen it.

## 3. Layer 2 — `defunion`: tagged sums

```lisp
(defunion Shape
  (circle r:f64)
  (rect   w:f64 h:f64)
  point)                          ; payload-less arm
```

- **Representation.** A struct: `{tag:i32, payload:(union circle:… rect:…)}`.
  Tags are assigned in declaration order from 0 and are part of the C
  contract. Each arm's payload is a memoized anonymous struct of its fields
  (one field → just that field). A `defunion` *is* a struct containing a
  union, so by-value passing/returning, `sizeof`, field layout, and the
  stage-8 ABI path all come from existing machinery.
- **C view.** Exported as
  `struct Shape { int32_t tag; union { struct { double r; } circle; … } payload; };`
  plus an enum of tag constants (`Shape_circle = 0, …`) — fully legible and
  constructible from C, which is what lets a `(Result T E)`-returning
  function keep the "consumable from C" promise.
- **Constructors.** Generated ordinary functions, `Union-arm` by default:
  `(Shape-circle 2.0)`, `(Shape-point)` — value-returning, no allocation.
  errors.md's `(ok v)` / `(err e)` spellings are library sugar over these,
  not compiler forms. (One-symbol-one-kind: the *arm* names themselves are
  not bound; only the prefixed constructors are.)
- **No tag access outside `match`.** The payload is not addressable as a
  field and the tag is not readable directly; `match` (§4) is the
  eliminator. The raw escape hatch is a `cast` to the §2 representation —
  available, greppable, unchecked, consistent with the frontier convention.

## 4. `match`

```lisp
(match s
  ((circle r)   (* 3.14159 (* r r)))
  ((rect w h)   (* w h))
  (point        0.0))
```

- **Semantics.** One-level patterns: an arm name plus positional binders for
  its payload fields (`_` to ignore a field), or a bare arm name for
  payload-less arms, or `_` as a default arm. Binders are ordinary typed
  locals bound **by value** from the payload. The whole form is a value
  expression with `cond`/`case`'s existing strict cross-branch typing and
  phi/void-collapse rules — nothing new in the join logic.
- **Exhaustiveness.** Without `_`, covering every arm is **required**; a
  missing arm is a compile error naming it. This is the property that makes
  adding an arm to a union safe — every `match` without a default breaks
  loudly. (`?T`'s narrowing can't offer this; it's the main thing values
  gain from real sums.)
- **Lowering.** `case` on the tag — the existing builtin that lowers to LLVM
  `switch` — with typed field loads in each clause. An exhaustive `match`
  emits no default clause, so a corrupted tag hits `unreachable`, the same
  contract as C. Implementation is a compiler form, not a macro: it needs
  the registered union's arm table for binder types and exhaustiveness
  (compile-time metadata interrogation from macros doesn't exist yet; if it
  ever does, `match` could in principle migrate down).
- **Scrutinee.** A union value or a `ref`/`ptr` to one (auto-deref for the
  tag read; binders still copy payload fields). Binding payload fields *by
  reference* for in-place mutation is deferred — the raw cast is the interim
  escape hatch.
- **Freebie.** `match` over a `defenum` scrutinee: same exhaustiveness
  check against the member list, lowering to `case`. Cheap, and it gives
  enums the same add-a-member-breaks-loudly property.

## 5. Templates — what `(Result T E)` actually requires

Stage 9's bounded generics monomorphize *functions*, bind tyvars only in
bare positions, and explicitly defer "generic struct layout". Type
*definitions* are an easier problem than dispatch: instantiation at a type
**use** site is explicit, so there is no inference and no unification —
substitution is purely syntactic, and nested occurrences (`(ptr T)`, `?T`)
are fine.

```lisp
(defunion (Result T E)
  (ok  v:T)
  (err e:E))

(defn read-config:(Result Config IoErr) (path:ptr) …)
```

- A parameterized head declares a **template**; it defines no type by
  itself. A fully-applied use `(Result Config IoErr)` stamps (and memoizes,
  keyed on the argument types — the anon-struct discipline) a concrete
  union `Result.Config.IoErr`, mangled like generic-fn instantiations.
  `.nuch` exports the template; importers stamp their own instances, the
  same scheme generic fns already use cross-unit.
- **The constructor problem.** `(Result-ok 42)` cannot infer `E` from its
  argument — the same "return variable bound by no parameter" situation
  bounded generics already reject. Options: (a) an explicit-instance
  construction form, `(make (Result i64 IoErr) ok 42)`, with library sugar
  per concrete instance; (b) per-instance stamped constructor names
  (`Result.i64.IoErr-ok` — real but ugly); (c) **target-typing**: in
  `return` position inside a function declared to return
  `(Result i64 IoErr)`, plain `(ok 42)` / `(err e)` resolve against the
  declared type. (c) is the ergonomic end-state and exactly what errors.md's
  `try`/`err` forms want; (a) is the honest v1 and (c) layers on it without
  breaking anything. Note A2 dodges this entirely — its `err` values are
  niche constants needing no type argument — consistent with errors.md's
  sequencing (A2 first, A1 as the generalization).
- Generic *functions* over `(Result T E)` with `&where`-bound tyvars in the
  Result position still hit the bare-positions restriction; that's the
  stage-9 "full parametric generics" deferral, unchanged here. Concrete
  instantiations — which is all the compiler and examples need — are
  unaffected.

## 6. Niche layout — the convergence step

The layout engine applies, deterministically and documented (C sees the
result), in order:

1. **All arms payload-less** → no union, just the tag (an `i32`; ≅
   `defenum`).
2. **Two arms, one payload-less, one a single `(ref T)` field** → bare
   pointer; null encodes the payload-less arm. `(defunion (Maybe2 T) (some
   v:(ref T)) none)` then *is* N1's `?T` — same bits, same C type.
3. **Two arms, one a single `(ref T)`, one a single error-value field**
   (the `deferror` id type, which by construction inhabits the reserved
   top-page range) → bare pointer with the ERR_PTR encoding. `(Result
   (ref T) Err)` then *is* A2's `!T`.
4. **Otherwise** → the §3 tagged struct.

Rules 2–3 make the stage's existing niche machinery the optimizer's output
instead of a parallel type system; `pkind` remains as the implementation of
those cases, now reachable from `defunion`. A `:repr tagged` attribute (or
similar) should be available to *suppress* niching where a C consumer wants
the predictable struct — open question on spelling. Rules must stay this
short; anything cleverer (multi-arm niches, alignment-bit niches) is
explicitly out of scope.

## 7. Interactions with the rest of stage 10

- **Drop.** If any arm payload type conforms to `Drop`, dropping the union
  is a tag-switch dropping the live arm — mechanical, emitted like the
  existing `with` cleanups. V1 may simply *reject* `with`-managed unions
  with Drop-conforming arms and add the switch later; either way the rule is
  explicit, never silent leakage.
- **Escape analysis (L1).** Constructor arguments are stores: building a
  union arm from a `with`-owned pointer is a store-out sink exactly like
  `set!`/`aset!`; `match` binders that copy a pointer payload propagate
  taint like ordinary reads. No new analysis shape, just two new sites.
- **Narrowing (N1).** Untouched. `match` doesn't need flow narrowing — the
  binder *is* the narrowed value. A possible later sugar: `match` over a
  niche-encoded `?T`/`!T` scrutinee desugaring to `if-some`/`if-ok`, so one
  eliminator reads uniformly across §6's representations.

## 8. Staging

Each phase independently shippable, bootstrap byte-identical until a phase
deliberately converts code — the standing discipline.

| Phase | Content | Unblocks |
|---|---|---|
| **U1** | Untagged `(union …)`: TY-UNION, layout, anon memoization, C header import (stop skipping), cheader/.nuch export, SysV `abi-classify` merge | stage-3c headers (SDL, pthread) |
| **U2** | `defunion` (monomorphic) + constructors + `match` (exhaustiveness, `case` lowering, `defenum` freebie) + tagged C export + Drop rule | `(Maybe T)` over values; concrete `Result`-shaped types; payload-carrying enums |
| **U3** | Templates: parameterized `defunion`, explicit-instance construction (§5 option a), memoized stamping, `.nuch` template export | **A1**: `(Result T E)` as a library type |
| **U4** | Niche layout rules 1–3 + `:repr` opt-out; fold `?T`/`!T` in as layout instances | errors.md A2/A1 convergence |

U1 and U2 have no ordering dependency on errors.md's A2; U4 is where the two
designs meet.

## 9. Open questions

- **Naming.** `defunion` for the tagged layer (raw stays anonymous-only) —
  or `defsum`/`defvariant` if the designer wants `defunion` kept for C
  parity as stage3c.md once sketched.
- **Tag width.** `i32` for C legibility, or smallest-sufficient int (with
  `:repr` controlling it)?
- **Constructor target-typing** (§5c): adopt in U3, or defer until the
  errors.md `try`/`ok`/`err` forms force the issue?
- **By-reference `match` binders** for in-place payload mutation — v2, or
  never (raw cast suffices)?
- **`:repr tagged`** spelling, and whether niching (§6) is opt-out or
  opt-in for `defunion`s that C code constructs.

#### Designer

`defunion` is good for now. If it becomes ungood later, breaking changes are considered low-cost at this stage of development.

Make the tag width `i32` for now and defer `:repr` in stage999 until we need it. That may mean deferring errors.md A2 as well, which is fine. A1 is the core functionality and A2 becomes an optimization.

Implement target typing now.

Implement `match` by-reference binders.

#### Robot — implementation status

U1–U3 are implemented per the designer's directives (i32 tag, target typing,
`(ref x)` by-reference binders). U4 niche layout and `&repr` are also
implemented (Phase C4, 2026-06-14) — see the **U4 landed** entry below.
Status detail lives in [progress.md](progress.md) (stage 10 unions
table); user-facing documentation in docs/builtins.md §"Unions and tagged
sums" and §"Niche layout and `&repr`"; runtime coverage in
`examples/unions.nuc`, `examples/errptr.nuc`, `tests/repl/unions.in`, and
union/niche cases in the `tests/layout/` C-oracle corpus. Implementation notes:

- Target typing rewrites only the **directly returned** form (`(return (ok v))`
  and the implicit-return last form), not `if`/`cond` branches in tail
  position — `(if p (ok a) (err b))` as a body tail does not resolve; use
  explicit `return` in each branch.
- The `name:(Type args)` colon sugar does not parse for parenthesized types;
  binding positions use the list form: `(defn (f (Result i64 i32)) ...)`,
  `(let ((r (Result i64 i32)) init) ...)`.
- §7 Drop: v1 rejects an owning `with` binding of a union with
  Drop-conforming arm payloads unless the union itself conforms to Drop
  (`union-drop-arm` / the check in `emit-with`); the compiler-emitted
  tag-switch drop remains future work.
- `--emit-cheader` skips (with a comment) functions whose signatures mention
  template instances — instances have no C-safe exported spelling yet (the
  mangled name `Result.i64.i32` is not a C identifier). Monomorphic defunions
  export the §3 tagged struct + tag-constant enum.

**U4 landed (C4, 2026-06-14)** (`make test` 71/71, `make bootstrap` fixed point,
`examples/errptr.nuc`, `tests/layout/` niche gate). The niche layout engine
is fully implemented; `LAYOUT-ENUM / NICHE-MAYBE / NICHE-ERRPTR / TAGGED`
constants (`defconst` in nucleusc.nuc) drive all four rules. Implementation
notes:

- **`union-layout-classify`** is a standalone function that decides the
  layout in strict rule order, reading the arm table built by
  `defunion-register` and an explicit `repr` mode parsed from the arm chain.
  It sets a `niche-elem-out` pointer to the `(ref T)` payload's element type
  for the niche cases (rules 2/3) so downstream codegen can recover `T`.
- **`&repr` syntax.** A trailing `&repr tagged` or `&repr niche` in the arm
  list (stripped by `defunion-strip-repr`) explicitly controls the layout
  decision: `&repr tagged` forces rule 4 unconditionally; `&repr niche` forces
  a niche and dies with a compile error if the arms are not nicheable.
  `REPR-AUTO` (no marker) runs the rules in order.
- **Rule 1 (LAYOUT-ENUM).** All arms payload-less → the union is just an i32
  tag (no payload struct or union member emitted). The backing struct
  `type-to-ir` returns the tag-only struct. `&repr niche` on an all-enum union
  is a compile error ("an all-payload-less union is an enum, not a niche").
- **Rules 2/3 require a *typed* `(ref T)` payload** (`arm-is-typed-ref`). An
  elem-less `ptr` payload does not qualify — this deliberately keeps the
  reader's `!ptr` (elem-less `(Result ptr Err)`) in LAYOUT-TAGGED, preserving
  the byte-identical bootstrap.
- **Rule 2 (LAYOUT-NICHE-MAYBE).** Two arms: one payload-less, one a single
  `(ref T)` field. `union-instance-type` returns a `TY-PTR` with
  `pkind = PTR-MAYBE`; `(some p)` stores `p` directly; `none` is `null`.
  `sizeof` == pointer size; C sees `T*`.
- **Rule 3 (LAYOUT-NICHE-ERRPTR).** Two arms: one a single `(ref T)` field,
  one a single `Err` field. `union-instance-type` returns `pkind = PTR-ERRPTR`.
  `(ok p)` stores `p` directly; `(err E)` emits `inttoptr(0 - zext(E to iptr))`,
  placing the id in the reserved top page. `is-err` is
  `icmp uge (ptrtoint p) (0 - 4096)` — one compare with no discriminant.
  `sizeof` == pointer size; C sees `T*` with the documented ERR_PTR convention.
  `match` / `try` / `unwrap` / `unwrap-or` all route through this encoding
  transparently (`emit-match-niche-errptr`, `emit-unwrap-niche-errptr`, etc.).
- **Niche construction in return position** (`union-target-rewrite`): when the
  enclosing return type is a niche pointer, bare `(ok v)` / `(err E)` / `(some
  p)` / `none` are rewritten to `(__niche-ctor arm args…)`, which calls
  `emit-niche-construct` with the return type as the target.
- **`niche-layout-of`** (helper) maps a `TY-PTR` with non-AUTO pkind to the
  corresponding `LAYOUT-*` constant; returns `LAYOUT-TAGGED` for non-niche
  types. Used as the dispatch predicate across all elimination forms.
- **Bootstrap invariant.** The elem-less `!ptr` types in the compiler
  (`Result ptr Err`) have no `elem`, so `arm-is-typed-ref` returns 0 for them
  and they stay LAYOUT-TAGGED — stage1.ll == stage2.ll holds.
- **Layout harness extended.** `tests/layout/structs.h` and `tests/layout/layout.nuc`
  include two niche cases: `sizeof(?ptr:Pt)` and `sizeof(!ptr:Pt)` both == 8;
  `(some (cast ref:Pt pt))` round-trips `pt` unchanged. Gated into `make test`.
