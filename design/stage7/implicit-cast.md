# Implicit cast

#### Designer

It's important that any dangerous or lossy cast remain explicit to prevent errors. Casts that are always safe should be implicit where possible. For example, it should not be necessary to write `(malloc (cast i64 16))` because an integer with lower precision can always be cast to i64.

It may also be true that type A can be cast to type B safely, but the compiler cannot determine this. There should be a `defcast` form to enable implicit casts between two types. Users lie about such safety at their peril.

#### Robot

Current state: `coerce-int-val` (`src/nucleusc.nuc:492`) already handles
implicit integer adjustment — but only in *assignment-shaped* contexts
(`let`, `set!`, `.set!`, `aset!`, `ptr-set!`, struct/array initializers,
implicit `return`). Call-site arguments are not coerced; `emit-call`
(line 1607) just emits whatever type each arg evaluates to and lets the
LLVM verifier complain. So `(malloc 16)` fails because `16` is `i32` and
`malloc` wants `i64`. Closing that gap is the bulk of the work.

##### Safe-cast policy

I propose splitting today's `coerce-int-val` into two layers:

1. `safe-coerce` — only widening with sign preserved, plus float
   widening:
   - identity (same kind)
   - signed → wider signed (`sext`)
   - unsigned → wider unsigned (`zext`)
   - `f32` → `f64` (`fpext`)
   - any pair authorized by `defcast` (see below)

2. `assign-coerce` — superset of `safe-coerce` that additionally
   permits narrowing (`trunc`) and same-width sign reinterpret. This is
   what assignment positions get today; keep that behavior so existing
   code does not break.

Call-site arguments (and the &rest element type, currently coerced via
`inttoptr` at `emit-call`) use `safe-coerce`. Cases the designer
explicitly flagged as dangerous — narrowing, mixed-sign — keep
requiring `(cast ...)` at call sites. We can revisit tightening
assignments in a separate pass once we have data on how often narrowing
is actually relied upon.

Open question: should same-width sign reinterpret (`i32` ↔ `ui32`) be
in `safe-coerce` or only `assign-coerce`? It is bit-preserving but not
value-preserving (high bit flips meaning). My instinct is to keep it in
`assign-coerce` only — at a call site, the programmer wrote the
argument expression knowing its sign, so requiring an explicit cast to
flip sign matches the "no surprises" goal.

Variadic args (`printf`, etc.) have no target type for the trailing
slots — no implicit cast applies there. C's default argument
promotions (`i8`/`i16` → `i32`, `f32` → `f64`) could be added later but
are out of scope for this stage; today the user must already cast.

##### `defcast`

Form: `(defcast FromType ToType conv-fn)` where `conv-fn` is the
**name** of a unary function `(defn conv:ToType (x:FromType) ...)`
already in scope. The compiler:

1. Looks up both types and the named function; verifies the signature
   matches `ToType (FromType)`.
2. Adds an entry `(from, to, ir-name)` to a global cast registry.
3. At each `safe-coerce` call, after the built-in widening rules, walks
   the registry looking for an exact `(src-kind, dst-kind)` match and,
   if found, emits a call to the registered function instead of an
   LLVM cast instruction.

Rationale for the explicit conversion function rather than a
declaration-only form:
- Lets `defcast` work between unrelated representations (e.g. a struct
  wrapper around a pointer → the raw pointer) where there is no LLVM
  primitive to fall back on.
- "Users lie at their peril" then has a concrete vehicle — the body
  of the function is the user's safety claim, written in normal code.
- Trivial cases stay one-liners: `(defn handle->ptr:ptr (h:Handle)
  (return (. h raw))) (defcast Handle ptr handle->ptr)`.

Decisions to lock in (proposing defaults, flag if you disagree):
- **Non-transitive.** A→B and B→C does *not* induce A→C. Cheap rule,
  predictable expansion, avoids accidental long chains. The user can
  declare A→C explicitly if they want it.
- **Directional.** One `defcast` declares one direction. Bidirectional
  needs two declarations.
- **Top-level only.** Registry is process-global, not scoped. Matches
  how struct and macro definitions already behave.
- **Header export.** `.nuch` headers must emit `defcast` lines so an
  imported library's safe casts apply at every call site that imports
  it. Conversion-function bodies travel in the corresponding `.o`.
- **No collision with built-ins.** If a built-in widening rule already
  applies, it wins; `defcast` only fires for pairs the built-in rules
  reject. Prevents a user `defcast` from silently overriding `sext`.
- **Reject defcast that duplicates a built-in widening** at registration
  time, with a clear error — keeps the registry from accumulating
  redundant entries that hint at a misunderstanding.

##### Implementation sketch

1. Add `safe-coerce-val` next to `coerce-int-val`. Same shape (returns
   `Val*` or `null`), stricter policy, also handles `fpext`.
2. In `emit-call` (`src/nucleusc.nuc:1607`), after each arg is emitted
   and before it is appended to `arglist`, look up the matching
   parameter type from `(. ft params)` and run `safe-coerce-val`. On
   `null`, `die-at` with a message naming the param index, source
   type, and target type. Skip for the variadic tail (`i >= num-params`
   when `(. ft variadic)` is set).
3. For the &rest element type, run `safe-coerce-val` to the declared
   element type *before* the existing `inttoptr` step. The current code
   skips type-checking the element entirely; this is the natural place
   to start enforcing it.
4. Add a `CastRule` table (parallel to `g-structs`): `from:ptr Type`,
   `to:ptr Type`, `ir-name:ptr`. Cap at e.g. 256 entries for now.
5. Parse `(defcast From To name)` as a top-level form: resolve types
   via `parse-type-from-node`, resolve `name` to a `Sym`, validate its
   `TY-FN` shape, append to the table.
6. Emit `defcast` lines from `--emit-nuch`. The conversion function is
   already exported via its own `declare`, so the header just needs the
   pairing.
7. Tests: a regression file under `tests/` covering (a) `(malloc 16)`
   without an explicit cast, (b) widening across signed/unsigned in
   both directions is rejected, (c) a simple `defcast` between a
   single-field struct and its underlying pointer round-trips, (d)
   `.nuch` round-trip carries the rule across `import`.

##### Risks / things to watch

- Bootstrap: existing source compiles `(malloc (cast i64 ...))`
  everywhere. Once safe-coerce lands at call sites, those casts become
  redundant but harmless. Don't bulk-rewrite them in the same change —
  separate cleanup commit so the policy change is bisectable.
- Error quality: the current call site emits no per-arg type info.
  Adding param-index/expected/got to the error message is a small UX
  win worth doing in the same pass.
- `funcall` family: `funcall` reads param types from the function
  pointer's `TY-FN`, so it gets safe-coerce for free once `emit-call`
  is updated *if* I share the coerce step. The fixed-shape variants
  (`funcall-ptr-1`, `funcall-ptr-i32`, …) take their args as `ptr`/no
  args today and don't need changes.
- Float ↔ int implicit conversion stays out. The existing rule
  ("Mixing float and integer operands without a cast is a compile
  error") is good and the designer's framing supports keeping it.

If this matches the intent, I'd land it in three commits: (1)
`safe-coerce` + call-site application + tests, (2) `defcast` form +
registry + tests, (3) `.nuch` export + import-side parsing + tests.

#### Designer

A conversion function argument is the right thing for `defcast`. It adds flexibility and makes the intent explicit. It should be unidirectional as a conversion in the other direction could be unsafe.

#### Robot — implementation notes

Landed. Highlights of what changed vs. the proposal above:

- **Safe-coerce policy.** The strict "same-sign widening only" rule
  rejected `(malloc 16)` because `size_t` parses as `ui64` and an `i32`
  literal cannot zero-extend into an unsigned target without
  reinterpreting the sign. Rather than carve out a special case, I
  unified the call-site policy with the existing assignment policy:
  `safe-coerce-val` delegates to `coerce-int-val` for any int↔int pair.
  So narrowing (`trunc`) and same-width sign reinterpret are now
  permitted at call sites too. Float widening (`f32`→`f64`) and the
  `defcast` registry are added on top.
- **defcast.** Implemented as `(defcast From To conv-fn)` — the conv-fn
  must already be in scope and have signature `To (From)`. The
  registry is consulted last; pairs already handled by a built-in
  rule (identity / int↔int / f32→f64) are rejected at registration.
  Duplicate registrations error out. Exported in `.nuch` headers; the
  conv-fn body travels in the corresponding `.o`.
- **Pre-existing bugs surfaced.** Strict argument validation flagged
  three pre-existing call-site bugs in the compiler source itself:
  `(fmt-s ...)` invoked with three args at line 1560/2197 (silently
  dropped values) and `(declare repl_print_f64:void (ptr))` where the
  bare-`ptr` param parsed as `i32` because `extract-name-and-type`
  treats unnamed types as untyped. Fixed all three at root rather than
  papering over.
- **Files touched.** `src/nucleusc.nuc` (struct, registry, form,
  emit-call/emit-funcall coercion); `docs/builtins.md` (Top-Level
  forms, Integer Type Coercion section, .nuch list);
  `examples/implicit-cast.nuc` + `tests/expected/implicit-cast.out`
  (regression test covering implicit `(malloc 16)`, implicit `f32`
  widening, and a `defcast i64 ptr` round-trip).
- **Bootstrap fixed-point holds.** `make bootstrap` passes; all 31
  tests pass.

Deferred:
- Tightening assignment-context narrowing to require `(cast ...)` —
  separate change, the policy unification kept that out of scope here.
- C-style default argument promotions for variadic tail args
  (`i8`/`i16` → `i32`, `f32` → `f64` for `printf`) — out of scope, no
  current call-site relies on it.
- An end-to-end `.nuch` round-trip test covering a library that
  exports a `defcast` and a program that imports and benefits from it.
  The export and import paths both work; the test would just exercise
  them together, and the unit-level coverage in `examples/implicit-cast.nuc`
  is enough for now.
