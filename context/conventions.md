# Conventions

## Design documents

When a feature in a design document gets implemented, add a **Status:** note but preserve the original design discussion and commentary. The design reasoning is a valuable record of how decisions were made and remains useful context for future work even after implementation.

## Format helpers are fixed-arity (`src/format.nuc`)

`fmt-s` takes **exactly one** `%s` argument; `fmt-i32` exactly one `%d`/`%ld`, etc. They are plain functions, not variadic. Passing a format string with more conversions than the helper's parameter count makes `snprintf` read a garbage vararg and typically **segfaults the compiler** (no error — just a crash with empty output). For multiple substitutions use the dedicated variants: `fmt-2s` (two strings), `fmt-sd` (string + int), `fmt-i32-i32` (two ints), `fmt-2s-i` (two strings + int). If you need a new shape, add a helper in `src/format.nuc` rather than overloading an existing one. **Three strings is the widest shape that exists (`fmt-3s`)** — compose in two calls (`(fmt-2s "%s\n%s" head note)`) rather than adding a `%s` a helper cannot feed.

**This trap is not "you might forget" — it is that a violation on a COLD error
path is invisible forever**, and it has **two** failure modes, only one of which
is loud. Over-supplying (a format with more conversions than the helper feeds)
crashes only when the garbage vararg is used as a *pointer*: a trailing `%s`
segfaults with no output, but a trailing `%d` prints a **garbage number** —
`call: expected 2 args, got 100` — which is a silently wrong diagnostic and
therefore worse. Under-supplying (fewer arguments than the helper has
parameters) is silent in both directions.

Stage 15 W9 swept **every** helper against its own parameter count and found
**seven** pre-existing violations, not the three a `fmt-s`-only grep had
recorded: four over-supplied (`call: expected %d args, got %d`, `BoxedFn call:
expected %d args, got %d`, `(dyn %s): '%s' is not a declared protocol`, and
`extend: '%s' is a protocol, so its supertype '%s' must be a protocol too` in
`generics.nuc` — the one the `fmt-s` grep missed) and three under-supplied
(`(fmt-sd "%%tc3.mat.%d" g-tmp)`, two `(fmt-2s "ptr %s" x)` in `abi.nuc`).
All seven are fixed, and each of the four diagnostics now has a test
(`tests/fixtures/w9-*`) — **a corrected format string that nothing executes is
one edit away from regressing**, which is the durable half of the fix.

Two structural consequences worth keeping:

- **Every one of the seven was also a wrong-arity CALL**, so the Stage 15 W9
  call-arity check (`call-arity-ok` / `check-call-arity`, `src/nucleusc.nuc`)
  now catches this whole class at the language level. The hand-count is still
  worth doing when you *write* a diagnostic, but it is no longer the only net.
- **Sweeping by grep is what under-counted it.** A scanner that parses each
  `(fmt-* "…" …)` call and compares the format's conversion count against the
  helper's parameter count finds all of them in one pass; a regex over `fmt-s`
  finds the ones you already suspect. Prefer the former.

**Buffer size is a second, quieter trap (fixed in Stage 15 W1d — know it, don't
re-break it).** Each helper formats into a fixed `alloca` and then called
`arena-strndup buf n` with **`snprintf`'s return value**, which is the length the
output *would* have had, not what was written — so any over-long message
`memcpy`'d past the end of a stack buffer. It became reachable once diagnostics
started embedding absolute file paths (W1c's unreachable-definer note, W1d's
import-cycle notes): two long paths plus prose overruns 512 bytes silently. Every
helper now clamps through **`fmt-take`**, and the string-carrying ones hold 1024.
If you add a helper, clamp with `fmt-take`; if a new diagnostic comes back
truncated mid-sentence, the message is over the cap, not the formatter.

## `node-type` mirrors `emit-node` (keep them in lockstep)

`emit-node` (`src/nucleusc.nuc`) sets the type a node propagates to its parent from
`node-type(n, scope)` (Stage 9 rung 3) whenever that returns non-null. So the
non-emitting type pass and codegen share **one typing rule per node kind**. Since
the Stage 12 module split the two halves live in **different files**: `emit-node`
and the `emit-*` family in `src/nucleusc.nuc`, the entire `node-type` family (the
`node-type` dispatcher plus `node-type-call` / `node-type-block` / `node-type-field`
/ … helpers) in `src/generics.nuc`. Editing one file without its partner is the
easy mistake. If you add a new special form to `emit-list`, or change the result
type any `emit-*` function returns, **update the matching branch in `node-type`
(generics.nuc) in the same change**.
The `make bootstrap` fixed-point test enforces this: a divergence makes the
compiler emit different IR than it consumes and `stage1.ll != stage2.ll`. A form
that `node-type` deliberately does not model returns null (codegen then keeps its
own type) — that's the escape hatch for control-flow/expansion-dependent results
(`cond`, macros, `quasiquote`), not a license to skip updating modelled forms.

**The structural fix for this class is a shared rule function, not two mirrored
copies.** Stage 15 W2a is the worked example: `node-type-call`'s intrinsic-binop
branch returned *operand 1's type alone* while `emit-binop-vals`/`binop-coerce`
unified both operands, so `(* 4096 (as i64 X))` emitted `i64` but typed `i32`
(the argument coercer then stacked a bogus `sext i32 <i64 value>`) and
`(> t:ui32 (* 2 cl:ui32))` was rejected as mixed-sign while `(* cl 2)` compiled.
The rule now lives in exactly one function — **`binop-result-type`**
(`src/nucleusc.nuc`, immediately above `binop-coerce`) — which `binop-coerce`
calls for the type decision (it keeps only the value-level cast emission) and
`node-type-call` (`src/generics.nuc`) calls for the propagated type. Prefer this
shape whenever a typing rule is non-trivial: mirroring the *logic* in both files
is what drifts; mirroring a *call* cannot. Note the direction is fine even
though `nucleusc.nuc` imports `generics.nuc` and not vice versa — every `.nuc`
inlines into one translation unit and `prescan-defn-signatures` registers
`nucleusc.nuc`'s own signatures before any form is emitted, so `generics.nuc`
forward-references into `nucleusc.nuc` (it already did, for `macroexpand-form`).

The shape recurs whenever a *second* position has to decide a question an
emitter already decides. Stage 15 W8 G-1's `as-int-narrowing`
(`src/type-utils.nuc`) is the smaller worked example: the int→int safety rule
for `as` — widening safe, narrowing lossy — is now one function that both
`emit-as` step 5 and the global-initializer constant folder *call*, rather than
one `(< (int-width dst) (int-width src))` written twice. Even a one-comparison
rule is worth extracting once a second asker exists; the cost is four lines and
the alternative is a divergence nobody notices until a program compiles in one
position and is refused in the other.

Two follow-on lessons from W2b, which extended that same rule to make a
`defconst`/`defenum` name behave like the literal it stands for:

- **A binop operand node is often a CELL, not the bare operand.** The variadic
  operator macros wrap the tail: `(* v K)` expands to `(_* v (* K))`, so the
  *second* operand node handed to `binop-result-type` is `(* K)`, never the
  symbol `K`. `node-is-int-literal` macroexpands a CELL for exactly this reason,
  and any new predicate over a binop operand must do the same — W2b's first cut
  did not, and the fix worked in operand-1 position while silently not working
  in operand-2 position, reintroducing the very order-asymmetry W2a removed. The
  §3.1 repro (`(<= ans K)`, a direct binop) does not catch it; only a `+`/`*`
  spelling does. Test both positions **and** both a macro and a non-macro
  operator.
- **Resolving a name needs the scope, not `g-globals`.** A `defconst` always
  lives in the global scope, so consulting `g-globals` directly looks like a
  free way to avoid threading a scope parameter. It is wrong: a local binding
  shadows the constant, and a shadowed local is an ordinary typed value.
  `binop-result-type`/`binop-coerce`/`emit-binop-vals` each carry a
  `scope:(raw Scope)` for this; `tests/fixtures/w2b-shadow-local.nuc` is the
  guard. Provenance that depends on *what a name means here* must be looked up
  through the scope chain that emission itself used.

## Rung 3 OVERWRITES emit's type — a form typed from emit-time state must return null

`emit-node` ends with

```lisp
(let (t (node-type n scope)) (when (!= t null) (set! (v 'type) t)))
```

so a non-null `node-type` answer **replaces** the type codegen just computed. It
is not an assertion and there is no mismatch diagnostic: disagree and the Val is
silently retyped, which is how a wrong type reaches the next bootstrap.

The consequence for a new special form: if its type depends on state that only
exists *during* emission, `node-type` must take the unmodelled escape (`return
null`, as `cond`/`macrolet`/`quasiquote` do) rather than recompute. The want
channel is exactly such state — `g-want-type` is armed only around a binding-init
probe/emit and is already consumed by the time Rung 3 runs (`generics.nuc`, the
TC-3 comment). Stage 16's collection literals hit this: `(vector-lit …)` takes
its element type from the want when one is armed, so a `node-type` arm that
recomputed would answer for a *different* element type than the one emit had
just built the collection with.

This does **not** weaken the node-type↔emit-node lockstep above; it is where the
lockstep is satisfied by having one computation instead of two. The price is
that node-type knows less — a generic call whose argument is such a form no
longer resolves through the node-type path — and that is safe by construction,
because null means "emit's own type stands" and emit resolves the call from the
emitted argument Vals.

## `coerce-int-val` is THE coercion chokepoint — and one caller reads a null return as "do nothing"

Despite the name, `coerce-int-val` (`src/abi.nuc`) is not integer-specific: it
is the single implicit-coercion chokepoint for `ptr`/`CStr`/`StrView`, integers,
and (since Stage 15 W2d) floats. Everything that assigns a value into a *typed
slot* routes through it — `let`/`with` init, `set!`, `.set!` field store,
explicit and implicit `return`, struct-literal and array initializers (positional
**and** designated are separate call sites), union-variant construction — plus
`coerce-num-val` (binops) and `safe-coerce-val` (call arguments) which delegate
to it. **Add a new implicit conversion here, not at the call sites.** The one
documented exception is a conversion keyed on the argument's *position* rather
than on a source/target type pair — see "A conversion keyed on POSITION cannot
live in the type-pair chokepoint" below.

The trap that makes a missing case cost double: those callers do not agree on
what a null return means. All of the typed-slot ones raise a "type mismatch"
diagnostic — but the argument loop in `emit-call-with-args`
(`src/nucleusc.nuc`) deliberately **leaves the argument untouched**
("preserving the prior pass-through behavior"). So one absent conversion is a
*rejection* in eight positions and a silent *miscompile* in the ninth. W2d found
exactly this: `coerce-int-val` had no float case, so `(let (a:f32 0.0) …)` died
`let: init type mismatch` while `(take 2.5)` against `(defn take (x:f32) …)`
compiled clean, emitted `call float @take(double 2.5)`, and printed `0.000000`.
When auditing a coercion gap, check the argument path separately — it will not
have told you.

**The argument path is not merely a different *reaction* to a null return — it
often does not reach `coerce-int-val` at all.** `safe-coerce-val` delegates down
only for StrView, int↔int, float↔float and `defcast` pairs; every other pair
falls through to its *own* null return. And `emit-call-with-args` performs
several conversions *before* it, of which the load-bearing one is **CE-3's
by-value struct normalization** (Stage 13): if the parameter is a by-value `S`
and the argument is a pointer to that same `S`, it loads the pointee. So the
argument position accepted `(take (P 1 2))` for two stages while every *typed
slot* rejected the identical `(let (v:P (P 1 2)) …)` — the same rule living in
one place and not the other. Stage 15 W5d added the ptr→by-value-struct load to
`coerce-int-val`, which is what makes a bare `(S …)` compound literal legal as
an `(array S …)` element, a struct-typed field of another literal, a `:S`
binding, an `aset!` store, and a by-value `return`. When you find an asymmetry
between "works as an argument" and "rejected at a slot", look for a
pre-`safe-coerce-val` normalization in `emit-call-with-args` before concluding
the chokepoint has the rule.

**A conversion added here that is a `deref` must carry `deref`'s obligation.**
The ptr→struct load calls `require-derefable` (`src/type-utils.nuc`) exactly as
`emit-deref`/`aref`/`aset!` do, so a `?T` source is rejected with the narrowing
diagnostic rather than silently loaded. Sugar that lowers to an unsafe operation
must not be safer-looking than the explicit spelling it replaces.

**`abi.nuc` bodies cannot call `generics.nuc`.** `coerce-int-val` needed
`type-eq` and could not have it: `nucleusc.nuc` imports `abi` (line ~664) before
`generics` (~686), and an imported module's bodies emit when it is processed, so
only *earlier* imports plus `nucleusc.nuc`'s own prescanned signatures resolve.
(`alloc-val`/`emit-load` live in `nucleusc.nuc` and are forward-referenced
freely; `type-eq` is not.) W5d spells out `type-eq`'s TY-STRUCT rule — same
`StructDef` — inline instead. The general rule: from an imported module you may
call *up* into `nucleusc.nuc` and *back* into earlier imports, never *forward*
into a later one.

**There is a SECOND value-into-a-typed-slot path that does not route through
`coerce-int-val` at all: `defvar-init-ir` (`src/nucleusc.nuc`), the global
initializer.** An LLVM global initializer is a *constant*, so it cannot be built
by emitting instructions — `defvar-init-ir` renders a literal directly into the
`@g = global …` line and re-derives, by hand, whatever rules the chokepoint
applies to the same value in a *local* slot. Every rule it forgets is a silent
divergence between `(defvar g:T lit)` and `(let (x:T lit) …)`, and this has now
bitten **five** times — the first four found while working on something else,
the fifth (recorded after the list) created by a fix and caught in the same
change:

- **W2b, integer narrowing.** The decimal string went straight to LLVM, which
  truncates `i32 5000000000` to `705032704` without complaint, while the local
  was rejected. Fixed with an `int-literal-fits` call here.
- **W2d, float width.** LLVM accepts a decimal for `float` only when it
  round-trips exactly, so `(defvar g:f32 3.14)` emitted IR-invalid
  `global float 3.14` — and unlike every value position it could not be repaired
  with an `fptrunc`, because there is no instruction to emit. Fixed by
  re-rendering the literal at the target width (`float-literal-ir-at`).
- **W6, nullability.** `pkind-flow-check` never ran, so
  `(defvar g:ptr:Thing null)` compiled clean and segfaulted on first use while
  `(let (p:ptr:Thing null) …)` was correctly rejected. Fixed by calling
  `pkind-flow-check` here with `ty-raw` as the source type — exactly what
  `emit-symbol-ref` gives the `null` symbol in value position.
- **W8 G-5, the OTHER half of the same hole: no initializer at all.**
  `(defvar g:ptr:Thing)` took `type-zero-const-ir`'s `null` — the identical
  wrong value, reached by writing less rather than more. `defvar-require-init`
  (`src/nucleusc.nuc`, beside `emit-defvar`) now refuses it, and it asks the
  **same two questions `pkind-flow-check` asks** — `(= (ptr-pkind ty) PTR-REF)`
  and `(!= (ty elem) null)` — rather than re-deriving them, so the `CStr` and
  elem-less-bare-`ptr` carve-outs come along for free. A hand-written
  `(= (ty kind) TY-PTR)` test here would have rejected ~1550 legitimate bare
  `:ptr` globals in this compiler's own source.

**A fifth bite, W9 item 30, arrives by the opposite route and is the one to
remember when you RELAX a rule.** The other four are rules the renderer forgot
to copy. This one is a rule that had exactly one asker *because it always said
no*: `emit-as` refused every `f64`→`f32`, so no float `as` could ever reach a
global initializer and `defvar-init-ir` needed no float arm —
`design/global-init.md` says so explicitly, and was right at the time. The
moment `as` started accepting an exactly-representable literal,
`(defvar g:f32 (as f32 1.5))` became legal and fell through to G-3's soft-mode
exit as a **runtime** initializer, storing from `@__nucleus_init` while
`(defvar g:f32 1.5)` one line above stayed a constant — a live difference on any
target whose ctors do not run (§4.6's AVR rule). Generalize as: **a rule with
one asker because it always refuses acquires its other askers the moment it
starts accepting.** Enumerate the positions when you relax a rejection, not when
you write it; and treat "position X can't reach this, it's always refused" in a
design note as a claim with an expiry date.

**Since Stage 15 W8 G-1 the renderer also FOLDS**: an integer destination
accepts an arbitrary constant expression (arithmetic/bit ops over literals,
`defconst`/`defenum` names, `(char "x")`, `(sizeof T)` and `(as IntT x)`), and a
pointer-like destination accepts `(as PtrT x)` — which is what makes
`(as CStr "…")` legal — and `(addr-of other-global)`. Three things about that
are worth knowing before you touch it:

- **A folded result is treated as an untyped integer literal of that value**, so
  it faces the *same* `int-literal-fits` call a written literal faces and no
  second range rule exists. No result `Type` is tracked through the fold; a
  proposal to track one is a proposal to re-derive `binop-result-type` in a
  second place, which is the shape W2a exists to delete.
- **Folding introduces arithmetic faults the renderer never had.** They are
  located `die-at`s, never a wrap or a poisoned constant: `+`/`-`/`*` overflow
  out of i64, `/` and `%` by zero (executing it would SIGFPE *the compiler*),
  `INT64_MIN / -1`, and a shift count outside `[0,64)`. The overflow tests must
  run **before** the operation — the compiler's own `+`/`-`/`*` emit `add nsw`
  etc., so inspecting an overflowed result is inspecting LLVM poison.
- **`(sizeof T)` in the renderer is NOT the same computation as `(sizeof T)` in
  a function body**, and the difference needs an extra guard. `emit-sizeof`
  emits a GEP over the LLVM *named* type, which LLVM resolves from a
  `%Name = type {…}` line anywhere in the module; the fold has no instruction
  stream and must ask `abi-sizeof`, which reads the compiler's own field table.
  That table is empty for a struct an import cycle has not laid out yet — the
  case `src/type-utils.nuc`'s W1d note describes — so `cfold-sizeof` calls
  `reject-cycle-pending-layout` in addition to `reject-opaque-type`. Without it
  a cross-cycle `(sizeof S)` folds silently to **0**. Any future constant
  evaluation of a *layout* question inherits this obligation.

The lesson is the shape of the fix, not the individual bugs: **call the shared
predicate rather than re-deriving its conditions.** W6's version is the model —
`pkind-flow-check` carries three carve-outs (`CStr` is ref-compatible, an
elem-less bare `ptr` destination has no non-null contract, a non-`PTR-REF`
destination is unconstrained) and calling it inherits all three, where a
hand-written `(= (ty pkind) PTR-REF)` test would have re-broken the ~1550 bare
`:ptr` bindings in this compiler's own source. When you add an implicit
conversion or a slot-entry check to `coerce-int-val`, **ask whether the constant
renderer needs the same rule**, and if so give it the same *call*, not a copy.

**Since Stage 15 W8 G-3 the renderer is also the CLASSIFIER, and the mechanism
is worth copying.** An initializer it cannot render is no longer an error — it
is a *runtime* initializer, queued for `@__nucleus_init`. The obvious
implementation is a `defvar-init-const?` predicate beside the renderer; that is
a second classifier and it drifts. Instead `g-defvar-soft` (`src/nucleusc.nuc`,
beside `g-array-ok`) is armed by `defvar-const-init-ir` around **one** call and
turns only the renderer's *terminal* "init must be a compile-time constant"
raise into a `null` return. Every other raise inside it still fires, and that
line is the whole design: a malformed constant, an out-of-range literal or a
nullability violation is an **error**, not a runtime initializer. The flag is 0
during aggregate *element* rendering, so an element must still be constant.
Generalize as: when a function that currently *dies* has to start answering a
question instead, soften exactly the "I don't recognise this" exit and leave the
"I recognise it and it's wrong" exits alone.

Two related facts worth having:

- **A float constant for LLVM's `float` type usually cannot be written in
  decimal.** LLVM accepts a decimal only when it round-trips exactly, so
  `float 3.14` is `error: floating point constant invalid for type` while
  `float 1.5` is fine — which is how `(defvar g:f32 1.5)` looked like proof
  that the `defvar` path worked. The general spelling is the hex form (the 64
  bits of the double the float widens to, `0x40091EB860000000` for `3.14f`),
  produced by `f32-const-ir` (`src/nucleusc.nuc`). A *global initializer* is a
  constant, so it cannot be repaired with an `fptrunc` instruction the way every
  value position can — it needs the literal re-rendered at the target width.
- **The compiler's own link flags are part of its constant-folding semantics.**
  Folding a literal at compile time evaluates it in the *compiler* process, so
  `-ffast-math` on `build/nucleusc` (FTZ/DAZ via `crtfastmath.o`) silently
  folded every denormal single to zero. It was removed from the Makefile in
  W2d and must not come back; the compiler does no FP work of its own, so it
  bought nothing. Any future compile-time evaluation of target arithmetic
  inherits this constraint.

## `defn` signature: return type follows the params (`(defn NAME (params):ret …)`)

The named-function signature is the fn-style `(defn NAME (params):ret body…)` —
the return type is the operand at **index 3** (a `NODE-KEYWORD` `:i32`/`:ptr:Node`,
a bare `NODE-SYM`, or a `NODE-CELL` `(Maybe i32)`), body starts at **index 4**
(index 5 with a trailing `noreturn`). `defprotocol` method sigs, `declare`, and the
`.nuch` `defmethod`/`declare` entries use the same grammar. The old
return-in-the-name style (`(defn foo:ret (params) …)`, list-head
`(defn (next (Maybe T)) (params) …)`) was **retired in Stage 14 S4** and is now a
**hard error** — but the *detection* machinery (`sig-name-is-bare` /
`legacy-ret-node` / `defn-name-only`) is retained so each chokepoint can recognize a
legacy shape and emit a targeted "legacy 'name:ret' syntax is no longer supported"
diagnostic quoting the offending name. Every reader of a defn shape must still funnel
through `defn-parse-sig` / `defn-ret-node` / `sig-name-is-bare` — **do not hardcode
the ret/body index.**

The legacy hard-error lives at **four** def-time chokepoints, because there is no
single one: `defn-parse-sig` (plain `defn`/`defn-`), **`register-generic-defn`**
(bounded-generic *templates* bypass `defn-parse-sig` — the prescan routes them there
and `emit-defn` returns early for templates), `emit-nuch-declare-import` (`declare`),
and the sig-storage loop in `protocol-register-form` (protocol method sigs are stored
verbatim and parsed lazily, so `proto-sig-parse` — which only reads the `(dyn P)`
forwarding path — is not the registration chokepoint). Any committed `.nuch` you
import (`src/llvm.nuch` is imported by the compiler itself) must be **new-style** — a
legacy declare/template there now dies at import.

The trap this bit (design/stage14/defn-signature.md S3): a **new-style body-start
of 4 vs the legacy 3** must be recomputed anywhere the body is walked from the
form. The generic-template A2 checker (`check-generic-template`) and the Valid
instance walk (`valid-check-instance`) both hardcoded `j:i32 3`; with a new-style
CELL return (e.g. `(defn constantly ((v V) :where (Ord V)) (BoxedFn (V) V) …)`)
that walked the return `(BoxedFn (V) V)` as a body form and read its `(V …)` as a
call to an unknown function `V`. Fix: `j = (if (sig-name-is-bare (node-at form 1))
4 3)`. A bare-symbol or keyword return survives a legacy walk harmlessly (it's just
a variable ref), so this only surfaces on a **parenthesised** return in a template
whose body the A2/Valid pass walks — a rare combination that no earlier test hit.

The five internal defn **synthesizers** (lambda lift, closure `invoke`/`drop`,
defunion arm ctors, type-erasure forwarding methods — all in nucleusc.nuc/
generics.nuc) build the new-style shape by consing the return operand *between*
the params node and the body sublist (a bare `NODE-SYM` from `type-spelling`);
the generic stamper is style-preserving via `monomorphize-form` +
`subst-tyvars-node`'s keyword branch, so it needs no change. Switching a
synthesizer's style is **invisible in emitted IR** (ir-names derive from the
colon-stripped name and the parsed types), so a closure/union program's IR is
byte-identical across the flip — verify with a before/after `--emit-llvm` diff, not
`make bootstrap` (both stages share the change).

## `defn` bodies are not desugared (colon-symbols survive)

`desugar` only rewrites **binding positions** of known forms: the `defn` name and
param list, `defvar`/`extern`/`declare` names, `defstruct` fields, and `let`/`with`
binding *names*. A `defn`'s **body is left untouched**, so a colon-typed symbol in
the body (`r:T`, `x:ptr:Node`, `(cast i32 …)`) stays a single `NODE-SYM` —
`split-typed`/`extract-name-and-type` parse it lazily in value position. So an AST
transform that walks a `defn` form sees the *desugared* shapes in the signature
(`(a T)`, `(maxv T)`) but the *raw colon* shapes in the body (`r:T`). The Stage 9
generic monomorphizer (`subst-tyvars-node`) therefore substitutes at the
colon-*segment* level (like `subst-self-node` for protocols), not by matching
standalone symbol nodes — that handles both shapes uniformly.

**In value position that annotation is an `as` CAST, applied in exactly one
place — and that placement is load-bearing.** Stage 16
(design/stage16-ergonomics/as-sugar.md) made `baz:CStr` mean `(as CStr baz)`,
implemented in `emit-symbol-ref` + `node-type-sym` (the lockstep pair), both
calling `value-annot-type` (generics.nuc) for the destination and `as-convert`
(nucleusc.nuc, split out of `emit-as`) for the conversion.

**It is NOT a tree rewrite, and must never become one.** SEVEN passes split a
value-position annotation and key on the bare name: `emit-symbol-ref-bound`, the
`emit-set` target, `fn-capture-walk`, `fn-rewrite-captures` (+ its `addr-of` and
`set!` arms), `node-binding-name` (the Stage 10 non-null flow facts),
`node-is-const-int-literal` / `const-fold-int`, and `node-type-sym`. Emitting the
cast at the value read leaves the node a `NODE-SYM`, so all seven keep working
and `set!`/`addr-of` keep the lvalue reading for free. A reader or `desugar`
rewrite would break them at once — the demonstration is
`(when (!= p:?ptr:N null) (p k))`, which narrows, against
`(when (!= (as ?ptr:N p) null) (p k))`, which does not (`node-binding-name`
returns null for a non-`NODE-SYM`). A reader rewrite would additionally destroy
the *type* reading: `(as ptr:i8 x)` would become `(as (as i8 ptr) x)`.

Two consequences of the cast semantics. The annotation is now **checked** —
`x:NoSuchType` was compiling silently, the same unvalidated-colon-spelling class
W4b swept out of definition *names* (`reject-colon-in-def-name`), one position
further along. And `node-type-sym` must not abort, so it resolves through
`value-annot-type`'s `tyname-resolvable` probe and returns null (= "not
modelled") on an unknown spelling, leaving the located error to emit.

Two spellings are deliberately outside the sugar. A **parenthesised** type
(`q:(ref P)`) is claimed by the colon-paren fuse in every list context and reads
as the call `(q (ref P))` — `emit-callable-value` diagnoses that shape by name;
the fix for a user is `deftype`. And the four self-evaluating names
(`null`/`true`/`false`/`none`) are matched by interned identity *above* the
split, so `null:raw:T` is an undefined name, not a cast.

## Colon-binding diagnostics span multiple chokepoints (CP-3)

A trailing-colon binding name (the whitespace near-miss, e.g. `x: (raw Node)`) is **not** caught by a single chokepoint — the desugar/emit split means top-level and body-local bindings take different paths. `split-colon-segments`/`desugar-symbol` only cover **top-level** binding positions (defvar/defn-name/params); a `defn` body is not desugared (see the note above), so a `let`/`with` inside a body never reaches the desugar path — `emit-let`/`emit-with`'s even-count check masks it first. And `defstruct` field CELLs bypass colon desugar entirely. CP-3 therefore needs complementary checks at three sites: `split-colon-segments` (desugar path), `extract-name-and-type` (both the SYM and CELL branches, emit-time), and a `check-colon-bindings` scan in `emit-let`/`emit-with` before the even-count check. Lesson: don't assume a single chokepoint for binding-name diagnostics — when adding one, audit both the desugar and emit trees for every binding-introducing form.

## A global's initializer may not name the global it initializes — builders take the collection

Stage 15 W8 G-5 turned ~48 of the compiler's globals into combined
declaration+initializations. Four of the helpers that built them
(`init-binops`, `init-rmacros`, `init-blanket`, `init-generics`) appended to the
global they were building — `(conj g-binops op)` — which is fine from a separate
`compiler-init` and **impossible** from the global's own initializer: the slot
is still null while its value is being computed. The fix is uniform and worth
copying: the appender takes the collection as its **first parameter**
(`add-binop`, `register-rmacro`), and the builder creates a local, fills it, and
returns it. Where the appender is also called from ordinary code, split rather
than re-point — `generic-alloc` (allocate + initialise) and `generic-new`
(`generic-alloc` + `conj g-generics`) in `src/generics.nuc` are the worked
example, so the registration and the construction cannot drift.

Two related facts from the same step:

- **A `defvar` whose initializer is a constant STRUCT literal must be declared
  after the struct's layout is available**, not merely after its name resolves.
  `g-arena-alloc` could not move above the first registry as
  `design/global-init.md` §2.10 planned, because `%AllocHandle` comes in with
  `(import-use vector)` far below; the renderer sees a fieldless registry entry
  and dies *"too many initializers for struct 'AllocHandle'"*. It did not need
  to move up: a constant initializer is applied by the loader, so it has no
  order, and every reference to it is `(addr-of …)`, which is an address rather
  than a read.
- **A `(defvar g:ptr (addr-of-ish some-function))` cannot be a constant when the
  function is defined in a LATER import.** A constant `@fn` reference is
  resolved at the defvar's own emission point. The compiler's two late-binding
  hooks are structurally unable to satisfy that — the defvar must sit above the
  file that *reads* the hook and the callee is defined below it — so they stay
  run-time initializers. If a hook global looks like it "should" be a constant,
  check which side of the import edge the callee is on.

## An ordering dependency laundered through two calls is invisible to every check

Also G-5. `g-generics`' builder calls `generic-alloc` → `ns-ir-prefix` →
`strcmp(g-current-ns, "user")`. Nothing in the initializer *names*
`g-current-ns`, so G-4's syntactic forward-reference check cannot see it by
construction (`design/global-init.md` §4.2 declares this class permanently
undetectable — it needs callee effect summaries). Declaring `g-generics` above
`g-current-ns` would have `strcmp`'d a null pointer at process start, before
`main`.

The practical rule when you give a global a runtime initializer: **read the
callee's body, not just the initializer expression.** The old imperative init
function often *documented* the dependency in a comment (`compiler-init`'s said
"g-current-ns must be set before init-generics"); a census of `set!` statements
does not carry those comments forward.

## A "value from a call" position that omits the want channel resolves by stamp order

`g-want-type` (TC-2) is armed at let/with binding inits, `set!` RHS, explicit and
implicit `return`, `.set!` value position — and, since G-5, at **`as`**. `as` was
the missing one, and the failure it produced is the model for the class: a
generic whose type variable appears only in its *return* type
(`vector-new-in`, the whole `*-new` family) has no argument to bind from, so
with no want it resolves against whichever instance the unit stamped **first**.
`scope-new`'s `(as (ref (Vector (ref Cleanup))) (vector-new-in …))` read
correctly for the compiler's whole life only because that call site *was* the
first `vector-new-in` emitted; stamping any other element type earlier
retargeted it. In the `as` spelling that surfaces as `as`'s own reinterpretation
error; **in the `unsafe/cast` spelling it is completely silent.**

Two takeaways. First, if you add a position that names a type, ask whether it
arms the want — the arm sites are enumerable by grepping `g-want-type`. Second,
when a construction site's element type comes from an annotation, prefer binding
it (`(let (v:(ref (Vector T)) (vector-new-in a)) …)`) over casting it; the
binding has always armed the want and says where `T` comes from.

## A drain at `emit-toplevel-forms` depth 1 has a SECOND caller: the REPL

`emit-toplevel-forms` at `g-toplevel-depth == 1` is the natural place to do
whole-unit work — `check-generic-templates`, `drain-mono-worklist`, and (Stage
15 W8 G-3) `drain-init-worklist` all live there, because by then every
top-level form of every reachable file has been walked. The trap is assuming
that point is only ever reached from the batch driver. **It is not: a REPL
`(import-use …)` calls `emit-import-use` → `emit-toplevel-forms` at depth 1**,
and what it produces goes into a module ORC then JITs.

That matters whenever the drained artefact only works in a *linked* program.
G-3's registration global is the worked example: `drain-init-worklist` appended
`@llvm.global_ctors`, which is correct for a batch object and inert in a JIT
module — LLVM 19's ORC C API has no initializer entry point — so an
`import-use`d library's global initializer was registered and never ran, and
the global silently read back 0. The fix is a `g-interactive` early return in
the drain plus an explicit JIT-and-call in **both** REPL routes (the `defvar`
arm and the import arm), which is why `repl-emit-init-fn`/`repl-run-init-fn`
exist as a pair — emit before `repl-jit-module` (the function must be in the
module), call after it (the symbol must exist).

So: if you add a depth-1 drain, ask what it emits and whether the JIT can honour
it. Note the symmetry with §4.6's AVR rule in `design/global-init.md` — "a
mechanism that is emitted but never runs" is the same defect in both places, and
neither is visible without looking at the value.

The sharper consequence, found in Stage 16 R5: **at the prompt, the file at depth
1 is the IMPORTED one.** The prompt itself is depth 0, so an import's own frame
occupies the depth batch reserves for the unit's root — and anything a depth-1
block treats as "this unit" is then a *library*. `(set! g-real-reachable
g-prescan-sigs)` is the case that bit: it re-sampled from inside a file an
`import-ct` was sinking, adding that file to the "reachable for real" set. Since
`do-import` asks `ct-sink-here` three times (choose the sink, pass it to
`emit-import-forms`, decide which list to file the path on), the first call said
"sink" and the third said "real" — so a compile-time-only import was recorded on
`g-imported`, the EMITTED list, and a later real import of the same library was
deduplicated away with nothing emitted for it. Now guarded on `g-ct-emitting`.
Two rules: before putting anything in a depth-1 block, ask what it means when the
depth-1 file is a library; and a question whose answer depends on mutable state
gets asked **once** and reused, not re-asked per use site.

## Emitting a function mid-emission needs the worklist, not a direct `emit-defn`

`emit-defn` calls `reset-function-state`, clobbering the per-function streams
(`g-entry-stream`/`g-body-stream`). So you cannot synthesize and emit a new
function while another function's body is being emitted. The generic
monomorphizer (rung 4) handles this by *registering* the stamped method
immediately (so the active call site can name its `@name.<tok>…` symbol) but
*queuing the body* on `g-mono-worklist`, drained by `drain-mono-worklist` at the
end of `emit-toplevel-forms` when no function emission is in progress. LLVM
textual IR allows forward references to functions defined later in the module, so
the call emitted earlier links fine. Reuse this pattern for any future
"emit-a-function-on-demand-from-a-call-site" feature.

## `TY-TYVAR` is a check-only type — never let it reach codegen

The `TY-TYVAR` type kind exists solely for the Stage 9 rung-4 **A2** def-time check
of bounded-generic bodies (`gcheck`/`check-generic-templates`): it types a
parameter declared as an abstract type variable so the checker can verify only the
constraints' protocol methods are used. Generic templates emit code *only after
monomorphization* (every type concrete), so `TY-TYVAR` must never flow into
`emit-*`, `type-to-ir`, `type-size`, or `type-mangle-token`. The `node-type`↔`emit`
lockstep is not at risk because the abstract scope exists only inside the A2 walk;
during real emission no scope binding is `TY-TYVAR`. If you add a new place that
manufactures or stores types, keep `TY-TYVAR` confined to the checker.

## `gcheck` recognizes type-spelling cells in generic bodies (TC-4a + TC-4b)

A cell whose head names a **registered struct template** — `(Box T)`, `(Vector i32)`,
`(HashMap K V)` — or a **type-wrapper keyword** (`ref`/`raw`/`ptr` — `(ref (Vector T))`,
`(raw Node)`) appearing in a generic body is a TYPE operand, not a function call.
`gcheck` (src/generics.nuc, top of the NODE-CELL symbol-head branch) checks
`node-template-of` (struct templates) and the `ref`/`raw`/`ptr` keywords, and returns
null (deferred) instead of falling through to the genuine-call path (which would die
`in generic body: unknown function 'Box'`/`'ref'` — these are types, not functions).
This is what lets a generic body use `(alloca (Box T))` / `(cast (ref (Vector T)) x)` /
`(sizeof (Vector T))` type operands (the TC-4 `*-new`/`*-new-in` constructor body shape).
Struct-template names and function/generic names do not collide in this codebase, so this
cannot mask a real call; a compound literal `((Vector i32) v0 …)` has a non-SYM (CELL)
head and never reaches this check. The precise stamped type is produced at monomorphization;
for the A2 walk the type is check-only (deferred/null is correct).

**The `ref`/`raw`/`ptr` half needed a 2-stage manual bootstrap.** The `-in` heap
constructors (`(defn vector-new-in ((a (ref AllocHandle))) (ref (Vector T)) …)`) use
`(cast (ref (Vector T)) …)` in the body, which needs the wrapper-keyword recognition.
But that recognition is itself in src/generics.nuc — source the OLD boot compiles — and
the old boot lacked it, so `make` died on the `-in` bodies (chicken-and-egg). Resolution
(build.md "Breaking changes the OLD boot can't bridge"): temporarily elide just the `-in`
constructors, `make` + `make update-bootstrap` (boot gains recognition without the bodies),
restore the `-in` constructors, `make` again (the new boot compiles them). Generalize this
whenever a gcheck fix is needed by source the boot must first compile.

**Latent TC-1 bug this surfaced:** `generic-method-bind-adapt` (src/generics.nuc:~1500)
early-exited `(when (= any-remaining 0) (return 0))` *before* want-fill, so a **zero-arg**
return-only-tyvar generic (the entire `*-new` family) never bound via the tier-2 path —
`any-remaining` is trivially 0 when there are no args. The early-exit (meant to skip
tier-2 double-counting of tier-1 exact matches) now fires only when the binding is actually
*complete* (all tyvars bound); an incomplete binding falls through to want-fill. Tier-1
(`generic-method-bind`) never had this bug, so the EMIT path worked — but the non-emitting
node-type probe (which uses tier-2) returned null, defeating TC-3's materialization probe.

## The byte-identical gate for a self-hosted-compiler edit is `make bootstrap`, not a literal `nucleusc.ll` diff

A change to any function that is itself compiled into the compiler (all of `src/*.nuc`,
including def-time checkers like `gcheck`) necessarily shifts the compiler's *own* IR —
so a before/after `./build/nucleusc --emit-llvm src/nucleusc.nuc` diff is **never empty**
for such a change, even when the change is 100% inert for compiled programs. The
non-emptiness is: (a) the edited function's body, plus (b) cascading SSA-temp renumbering
in every later function in the one-module compilation, plus (c) per-use symbol-name
`@.str` constants for any newly-referenced quoted symbols. To **prove** a self-hosted edit
is inert for existing programs: (1) `make bootstrap` (stage1==stage2 — the new compiler is
self-consistent); (2) `make test` green; (3) normalize the diff (strip all `%…` SSA names
and `@.str.N` numbers) and confirm the *only* remaining change is inside the edited
function(s). The design docs' "byte-identical (additive)" claims for TC-1/2/3 refer to
**existing program IR** being unchanged (those phases fire only where today's emit dies),
*not* to the literal `nucleusc.ll` diff — which a careful read of those phases shows also
shifted (new `tc3-*` functions, etc.) and was reconciled by the same `make bootstrap` gate.

## Widening what the C importer can represent moves the compiler's OWN declare set

`src/nucleusc.nuc` imports `<stdio.h>`, `<string.h>`, `<ctype.h>`, `<unistd.h>`
and `<stdlib.h>`, and the importer emits a `declare` for every function it can
represent. So teaching `c-parse-type` a new C type **adds `declare` lines to the
compiler's own IR** — Stage 16 FL-7 made `long double` representable and picked
up `strtold`, `qecvt`, `qfcvt`, `qgcvt` and the two `_r` forms.

The consequence is a `make bootstrap` failure that looks like a miscompile and is
not: stage1 comes from the committed *boot* compiler, which still skips those
declarations, so it differs from stage2 by exactly the new lines. Confirm the new
fixed point before touching the artifacts — emit stage3 with `build/nucleusc-stage2`
and diff it against stage2.ll — then `make update-bootstrap`, rebuild, and re-run
`make bootstrap`. A divergence that is *not* confined to the new declare lines is
a real one.

## Shifts: `bit-shr` on a signed operand is arithmetic, and a count ≥ width is poison

`bit-shr` lowers to `ashr` for a signed operand and `lshr` for an unsigned one,
so a logical right shift needs `(unsafe/cast ui64 x)` — and then the *count* must
be cast too, or the compiler rejects the form as mixed signed/unsigned. LLVM
makes any shift by ≥ the operand width poison, which a data-driven count reaches
easily (`128 - p` is a shift of 64 at `p = 64`). Wrap both in total helpers that
answer 0 / the operand at the out-of-range counts rather than open-coding shifts
whose count is computed; `u64-shr` / `u64-shl` / `u64-mask` in `type-utils.nuc`
are those.

## A layout test that RUNS both binaries can only ever check the host

`tests/run-layout-test.sh` compiles a struct with `cc` and with `nucleusc` and
diffs `sizeof`/`offsetof` at runtime, so it validates x86-64 and nothing else —
and alignment rules are target-parameterised. Stage 16 PK-1 added a
compile-time oracle instead: emit `(defvar s:i64 (sizeof S))` (it folds to
`@s = global i64 N` in the IR, no execution needed), generate the matching
`_Static_assert`s, and check them with `clang --target=<t> -ffreestanding
-fsyntax-only`. No sysroot, no linker, no libclang, every target clang supports.

It found a defect on its first run that had been shipping for the whole project:
**AVR's `BIGGEST_ALIGNMENT` is 8 bits**, so every type on that target is
byte-aligned regardless of width, and `abi-alignof` must return 1 there before
it consults the type. `struct { int8_t; int32_t; int16_t; }` is 7 bytes on AVR
and Nucleus was emitting 12.

## LLVM knows only the element list — an alignment the TYPE does not carry is a lie

`getelementptr … i32 0, i32 n` and `[k x %S]`'s stride are computed from the
emitted element list and nothing else, so any layout rule LLVM does not model
must be spelled into the type. `packed` it models (`<{ … }>`); an over-aligned
struct or member (Stage 16 PK-3) it does not, so the gap becomes a real
`[k x i8]` element — which is also what clang emits. Two consequences that are
easy to miss:

- **A pad is an element, so field index ≠ element index.** Every GEP needs the
  mapped one (`field-ir-index`). The off-by-one: the pad before field `i` shifts
  field `i` **itself**, so the count runs over `0..i`, not `0..i-1`.
- **An `alloca`/global must state the alignment explicitly**, because LLVM
  derives the aggregate's own from that same element list.

Make both computations answer "no change" unless the feature is actually
present; that is what keeps every existing type line and GEP byte-identical, and
it is what lets `make bootstrap` stay converged through the change.

## Folding a zero into a memoization key renames everything it keys

`hash-struct-shape` keys the anonymous struct/union memoizer, and its output is
the `%__anon_struct_h<hex>` name in the IR. Adding a per-field property to the
key must fold in only the NON-DEFAULT value: hashing the default for every field
that lacks the property is a different hash for the identical shape, and the
result is every anonymous C type in the program renamed (42 lines of bootstrap
diff, Stage 16 PK-3). "Absent" and "zero" are the same shape — the key must say
so.

## A REPL feature can vanish from a self-hosted compiler without moving one byte of its output

Every gate this project has looks at the **emitted program**: the IR snapshot
diffs `--emit-llvm`/`--emit-cheader`/`--emit-nuch` text, `make bootstrap` asks
only that the compiler reproduce itself, and `make test` runs compiled programs.
None of them is a *user* of the compiler's interactive surface.

So when the REPL introspection layer — sixteen documented meta forms, 542 lines —
was dropped by a rebase in 2026-06, all three gates stayed green for fifteen
months, and it surfaced only when someone typed `(type-of "foo")` at a prompt
(design/stage18-tooling/overview.md §1.1). There was no removing
commit to find, either: `git log -S` shows only the additions, because the branch
that reached HEAD never had them.

Two consequences when you work here:

- **A feature with no test is a feature that can silently disappear**, and the
  snapshot's byte-identity will report success while it does. `tests/repl/*.in`
  + `tests/expected/repl-*.out` is the harness for anything interactive; use the
  substring form (`run_repl_meta_loose`) only for output a golden cannot hold —
  a measured duration, or a listing of every library name.
- **A dead field is evidence, not litter.** `Sym.docstring` and `Sym.trace-saved`
  had zero readers because their readers had been deleted out from under them.
  Before retyping or removing an unread field, `git log -S` its name: if it was
  once read, the question is what happened to the reader. `Field.name` is the
  cautionary case — it was emptied *because* its only reader was already gone,
  and the comment justifying that cited the absence as the argument.

## A workaround outlives the bug it was written against, and a gate that names a directory does not cover the tree

Two halves of one 2026-09-03 finding, both in `lib/`.

Stage 17 C8 fixed the join rule so that `(if c "a" "b")` is a `StrView` (it used
to collapse to `CStr` unless the destination armed the want channel). `lib/fmt.nuc`'s
`bool` conformance had been written *around* that rule — `(strview-from-cstr (if
self c"true" c"false"))`, an explicit pair of C literals and a `strlen` per
formatted bool — and stayed that way after the rule changed, because nothing
fails when a workaround merely becomes unnecessary. **Fixing a rule is the moment
to grep for what was written against it**; the search term is the workaround's
shape (`strview-from-cstr` on a literal), not the rule's name.

The reason it survived a whole stage is the second half: `scripts/check-cstr.py`
walks `src/*.nuc`. That is the right scope for what it was built for, and it
reads as a tree-wide guarantee — so `lib/` kept `join`'s `sep:CStr`, a
`(UnaryFn S CStr)` renderer, `keyword-intern (cs CStr)`, an interner table keyed
by a bare `ptr` it cast back into a `Symbol` to hash, and a dead `arena-strdup`,
all of them the exact spellings the stage existed to remove. When a tripwire's
scope is narrower than the invariant's, say so where the invariant is stated —
`design/stage17-native-strings/overview.md` §2.7a is now the `lib/` half of the
list, since a second script counting a second directory would only move the line.

## A template function nothing instantiates has never been compiled

`lib/hashset.nuc`'s `hashset-new-in` spelled its allocation
`(as (ref (HashSet T)) (alloc-handle-alloc …))`, which `as` refuses — the handle
returns `ptr:ui8`, and reinterpreting it needs `unsafe/cast` (which
`hashmap-new-in`, three files over, already used). It shipped that way because
every `(HashSet …)` in the tree comes from a by-value `#{…}` literal, so the
function's body had never been type-checked, let alone emitted. The first caller
in two stages found it instantly.

A generic body is source until something stamps it. `make test` passing says
nothing about a template arm no fixture reaches, and the IR snapshot cannot see
it either — there is no IR. When you add a template function, add the call, or
accept that you have written untested text.

## A wrong value that only reaches a truthiness test is invisible to every gate

The bootstrap fixed point proves the compiler is *self-consistent*, not that it is
*right* — and the gap has a specific shape worth recognizing. Stage 15 W9 item 31:
`is-unsigned` had no `TY-I1` arm, so `i1` was read as signed, `(as i32 true)` was
`−1`, and `(< false true)` and `(> true false)` were BOTH false. It survived every
bootstrap for the whole project. The reason is that the compiler's own source held
that value in exactly six places, all of the shape `(let (x:i32 <comparison>) …)`,
and **every one of their consumers tests `(!= x 0)` or `(= x 0)`** — a predicate
`−1` and `1` satisfy identically. The compiler was carrying the defect and could
not observe it, so `stage1.ll == stage2.ll` held, `make test` was green, and the
corpus IR was stable.

Generalize it: **a wrong value leaves no trace in any fixed point if it only ever
flows into a truthiness test.** Boolean-ish `i32` flags are the common carrier
(that is the whole idiom in this codebase), but the same holds for any value whose
consumers only distinguish zero from non-zero, or non-null from null.

Two consequences for how to test:

- **Assert on the instruction, not only on the run.** `sext i1` and `zext i1`
  differ only above bit 0, so a run that checks `(if b …)` passes under both. The
  item-31 unit greps the emitted IR for `sext i1` / signed `icmp` on `i1` /
  `sitofp i1` precisely because the run cannot make that claim.
- **Distrust an expected-output file that looks odd.** Two of them had baselined
  the defect (`tests/expected/logic.out` said `(and) = -1` while
  `examples/logic.nuc`'s own header comment says `(and) => true`). A recorded
  expectation is evidence of what the compiler *did*, never of what it *should*
  do; when a fix moves one, read the source's own documentation before assuming
  the fix is wrong.

Related: the fix moves the bootstrap, so it needs the converge cycle in
[build.md](build.md) §"After a codegen change" — and the sweep is what turns
"this touches 22 call sites" into the measured "24 `sext i1`→`zext i1` sites,
0 diagnostics moved".

**And do not estimate the blast radius from the call-site count.** W9 item 32
read the *same* 22-call-site `is-unsigned` through one consumer and moved five
lines corpus-wide, leaving the compiler's own IR byte-identical and the
bootstrap untouched. Item 31 moved it because `i1` is pervasive in a compiler —
every comparison makes one; item 32 did not because an unsigned *narrow* index
is something embedded code writes and a compiler does not (it indexes with
signed `i32` and pointer-width `usize`, and `usize` emits no instruction at
all). **Blast radius follows the type's idiom in the code being compiled, not
the helper's fan-out.** Sweep to find out; do not reason it out.

## A warn-only sweep reporting zero must prove REACH, and the cheap proof is a compiler that warns on success

The `--warn-ct-shadow`/U1 procedure — land a tightening as a warning, sweep
`lib/`, `src/`, `examples/` and `tests/`, promote only on zero fires — has a
failure mode that looks exactly like success: **zero fires and zero reaches are
the same number.** Sweeping this tree by compiling every `.nuc` file individually
makes that concrete: of 478 files, **196 exit non-zero** (163 deliberate refusal
fixtures, plus the 13 `src/` modules and 20 `tests/suite-*.nuc` that do not stand
alone and are only reached through `src/nucleusc.nuc` and `tests/nuctests.nuc`).
A guard sitting past any of those abort points is never executed, and the sweep
cannot tell you so.

**Build a second compiler whose guard warns on the success path instead of the
failure path, and re-run the same sweep.** It costs two builds and turns "zero
fires" into "the branch was reached 50,207 times across 64 files and none of them
fired". Keep the probe binary out of the tree — copy it to the scratch directory
and revert the source edit immediately, before running the sweep, so the probe
can never be what gets committed. A second, independent reading is worth having
too (here: no failing fixture contains the token the guard is about), because the
probe measures the tree as it compiled, not as it is written.

The same caution applies to `make test`: the harness runs the compiler as a
subprocess and captures its stderr internally, so a green suite is not evidence
about a new warning's volume. Sweep with direct compiles and capture stderr
yourself.

**Measure the probe's per-file BASELINE before reading a count as coverage.**
The auto-imported prelude is compiled into every unit, so a guard anywhere the
prelude reaches has a floor: U2's macro-body guard reports 23 reaches for
`(defn main ():i32 (return 0))`. A refusal fixture reporting exactly 23 has had
*none of its own* constructs reached, and reads identically to one that had all
of them — so compile a one-line program with the probe, subtract, and only then
claim a file was covered. A file at the baseline is not evidence; find it
covered elsewhere (a `src/` module through `src/nucleusc.nuc`, a `tests/suite-*`
through `tests/nuctests.nuc`) or account for it by hand.

And a new guard on an *old* site does not inherit the old site's sweep. U1
measured `emit-qq-form`'s unquote arms; U2's second half sits in
`compile-macro-body`'s body loop, which that sweep never executed a single check
in. Same class of mistake, same file, different site — so it got its own
warn-only build, its own sweep and its own reach probe, and the numbers came out
an order of magnitude apart (12,111 reaches across 403 files versus 50,207
across 64), because the two sites have completely different populations.

## Testing a wrong-ADDRESS defect: keep both addresses mapped, or the test reports a signal

The natural repro for a bad index is the extreme one — W9 item 32 was filed from
`(aref p i)` with `i:ui32` at `4294967295`, which under `sext` read `p[-1]` and
returned the neighbouring element. That repro is perfect for *finding* the
defect and useless as a regression test: once fixed, the correct address is four
billion elements out and the program segfaults. A suite entry that passes by
crashing asserts nothing about the value, and it cannot tell a fixed compiler
from a differently-broken one.

**Construct the fixture so the right address and the wrong address are both
inside a live allocation.** Item 32's uses a `ui8` index of 200 against a pointer
60 elements into a 300-element buffer: unsigned lands on `[+200]`, signed on
`[-56]`, both mapped, both pre-seeded with distinct sentinels. A regression then
reads a *wrong value* and returns an exit code naming the check, which is a claim
a test can make. Same technique for the `ui16` case at 40000.

Two riders:

- **Cover the unrepresentable case on the instruction instead.** The `ui32`-at-2^31
  case that started the item cannot be written as a running check at all, so it
  is a `zext i32 … to i64` probe in `w9-unsigned-index`. Pair "what the program
  computed" with "what the compiler emitted" whenever the interesting input is
  out of reach.
- **Assert the branch you did *not* take.** A signedness fix is one `if`, and a
  blanket `zext` passes every unsigned check in the fixture. The signed index at
  −3 that must still reach backwards is what makes the test about the rule
  rather than about one direction of it.

## Emitted linkage: `weak_odr`, never `linkonce_odr` — the macro JIT resolves against the linked program

`def-linkage` (`src/nucleusc.nuc`) is the single place that decides a top-level
definition's LLVM linkage: `internal` when private, `weak_odr` when the unit only
carries a *copy* of the definition (any imported file's form, and every
monomorphized stamp — `drain-mono-worklist` arms `g-emitting-copy` for those),
external otherwise. Both emitters call it; do not re-derive the word at a new
emission site.

The trap is the choice of ODR variant. `linkonce_odr` and `weak_odr` merge
identically at link time and are equally non-interposable, so `linkonce_odr`
looks like the obvious pick — but it is **discardable when unreferenced**, and
`clang -O3` duly deletes every imported function it has fully inlined. Macros and
`ct-` functions are JIT-compiled *during* compilation and resolve their callees
by name against the running program's dynamic symbol table (`-rdynamic`), so a
deleted definition is unfindable: with `linkonce_odr` the compiler's own
`make bootstrap` dies `JIT session error: Symbols not found: [ alloc-node ]`
while `alloc-node` is plainly present in `stage2.ll`. The same failure is
reachable from any user program whose macro calls an imported function.
`weak_odr` may not be discarded, which is the whole reason to prefer it; the
price is that an unused imported function is no longer dead-stripped, and that
is now recovered at the link instead — one ELF section per definition
(`write-ir-section`, gated by `ir-sections-on`) plus `-Wl,--gc-sections` on the
link line. Two rules if you add an emission site: the section name must be the
symbol's, since MC merges same-named sections and a merged one survives if any
definition in it does; and LLVM keys SHT_NOBITS off the **name**, so `.bss.` is
a hard error with a non-zero initializer and `.data.` on a zero one newly costs
file bytes (`global-section-prefix` is the single decision).

Consequence for measuring a codegen change: normalize `weak_odr` away before
diffing IR, exactly as you strip SSA names (see the bootstrap-gate section
above), or every multi-file program looks like it moved.

`internal` has a second consumer that batch reasoning misses: **the REPL
assembles one module per entry**, so "private to this module" hides a private
definition from every later entry that can spell it. `def-linkage` therefore
returns `weak_odr` for a private definition under `g-interactive`; without it
`(unsafe/import-private lib p)` imports `p/secret` successfully and then dies
`Symbols not found: [ …p1__secret ]` at the call (Stage 16 R5). Batch is
unaffected because `g-interactive` is 0 there — which is also what keeps the
change out of the byte-identical bar.

## An ORC definition generator DEFINES what it reflects — and LLJIT already has one

Do not attach `LLVMOrcCreateDynamicLibrarySearchGeneratorForProcess` to the JIT's
**main** JITDylib. A `DefinitionGenerator` does not merely resolve a missing
symbol; when it fires it **defines** that symbol, as an absolute address, in the
JITDylib it is attached to. The name is then taken there for the life of the
session, and any later module that *defines* it is rejected —
`Duplicate definition of symbol 'alloc-node'`, which is exactly how
`(import-use node)` in the REPL failed until 2026-08-29.

`LLJITBuilderState` carries `LinkProcessSymbolsByDefault = true`, so LLJIT
already builds a `<Process Symbols>` JITDylib with a process search generator and
adds it **as the last item in the default link order**. Process symbols
(`printf`, `malloc`, and the compiler's own `-rdynamic` exports) therefore
resolve with no setup at all, *and* a module's own definitions take precedence
over them. Attaching a second generator to main is redundant and defeats the
precedence.

Three things measured against LLVM 19.1.7 while establishing this, each worth not
re-deriving:

* The `LLVMOrcSymbolPredicate` filter argument is real and is consulted **per
  looked-up symbol, per generate attempt** — a live hook, not a construction-time
  one. It can even be flipped between module adds.
* `-rdynamic` stays load-bearing. The process JITDylib reflects the dynamic
  symbol table, so without it a JIT'd macro body dies
  `Symbols not found: [ … ]`. See the `weak_odr` section above and
  `design/stage16-ergonomics/compile-time-imports.md` §9.
* There is **no C API for `JITDylib::setLinkOrder`**. If you ever need
  host-before-session resolution for one class of module, the only routes are a
  bare JITDylib plus `LLVMOrcCreateCustomCAPIDefinitionGenerator`, or emitting
  host-pinned absolute-symbol aliases. Both are real work; see
  `design/stage16-ergonomics/repl-jit-symbol-precedence.md` §5.

The consequence to keep in mind when changing REPL emission: **in the REPL the
session's own definition wins over the host compiler's.** That is right for a
prompt-typed `defn`, and it is why importing `lib/node.nuc` gives the session a
*second* intern table — and symbol identity is compared by pointer (see "Symbol
nodes are interned singletons").

## The want channel: target-typed construction (TC-1..TC-5)

A one-shot, downward expected-type ("want") flows from declared-type positions into
generic resolution, filling tyvars the arguments left unbound (design/stage14/target-
typed-constructors.md). `g-want-type` (src/nucleusc.nuc, beside `g-fn-ret-type`) is
**armed** (save/set/restore) at let/with binding inits, `set!` RHS, explicit+implicit
`return`, and `.set!` value position, and **consumed once** at `emit-generic-call` entry
(read into a local + nulled *before emitting arguments*, so an argument sub-call never
inherits the outer want). The shared resolver `generic-resolve-adapt-tier` and
`generic-method-bind(-adapt)` carry a `want:?ptr:Type`; `unify-tpat` fills a still-null
tyvar slot from want over the method's return pattern (fill-only — sets a null slot,
`type-eq`s an already-bound one; never overrides an arg-derived binding). A return-only-
tyvar generic (zero-arg `vector-new`) now registers as METHOD-GENERIC and resolves at a
typed position; with no want it reports `cannot infer type variable '%s' for '%s': no
expected type at this position — annotate the binding`.

**node-type must mirror this.** `node-type-call` takes `want`; when a caller hands null
(the `node-type` dispatcher, gcheck, valid-walk), it falls back to the armed `g-want-type`
so a non-emitting probe (TC-3's two-probe materialization derivation) drives resolution
identically to emit. Keep the resolver threaded through both: emit and node-type must not
diverge on a want-dependent call (the lockstep).

**TC-3 binding materialization:** a declared `(ref S)` binding (S a struct) initialized
with a by-value `S` (e.g. `(with (v:(ref (Vector i32)) (vector-new)) …)`) materializes —
`tc3-emit-binding-init` derives the want via two non-emitting probes (whole `(ref S)`,
then pointee `S`), emits once, and `tc3-materialize` allocas a backing slot + stores +
binds the ref. The materialized backing is frame storage, dropped through the existing
`with-drop-method` TY-PTR arm. Methods take `(ref …)`, so no `addr-of` per call (resolves
the receiver-shape problem).

**TC-5 union target-typing:** `union-target-rewrite` (src/union-emit.nuc) is parameterized
by the target type and runs at the let/with init, `set!` RHS, AND the value-position tails
of `if`/`cond`/`do`/`let`/`with`/`match` (not just return), so union construction works
without `make` everywhere a typed value is expected. Distribution: each control-form
emitter captures the armed want at entry (`my-want`) and re-arms `g-want-type` before
emitting a value tail — a prior statement (test/scrutinee) may have nulled it via
emit-generic-call's consume-once, so without the re-arm only the first branch would see it.
Recursion is natural: each emitter rewrites its own tail, then emit-node dispatches the
(rewritten) tail, so nested control forms rewrite level by level. The `.set!` value
position is NOT covered (it sits before `(import-use union-emit)` in src/nucleusc.nuc,
so the function isn't in scope there).


## A "this spelling is legal only HERE" rule is one consumed-once permission, not N refusals

Stage 15 W8 G-2 added `(array T N)`, a **storage** type meaningful in exactly
two declaration positions (a `defvar` type, an aggregate's field type) and
unsound everywhere a value copy is implied. The obvious implementation is a
`reject-<thing>` call at each position that must refuse — and it is the shape
that drifts: every position added later silently *accepts*, and nobody notices
until a program miscompiles.

The shape that does not drift is a **one-shot permission the parser consumes**.
`g-array-ok` (`src/nucleusc.nuc`, beside `g-form-line`) is armed by the four
sites that want an array and read-and-cleared at the top of
`parse-type-from-node` — the same consume-once discipline `emit-generic-call`
applies to `g-want-type`. The payoff is that **nesting falls out for free**:
`(ptr (array i32 4))` consumes the permission at the outer parse, so the
recursion into the element sees 0 and is refused — and so are
`(array (array i32 2) 3)`, `(Vector (array i32 4))`, `(Maybe (array …))` and
every constructor added in future, with no per-constructor check. Default is
refuse; the permitted set is enumerable by grepping the arm sites.

An explicit `reject-array-type` still exists in `src/type-utils.nuc`, but only
for the two positions the *syntactic* gate cannot see because the Type arrives
already parsed: `abi-classify` (a by-value parameter/return) and the
`set!`/`.set!` targets. That is the right division — gate the spelling where it
is spelled, backstop the type where it is used.

**One wrinkle worth knowing before you copy the pattern: a `defvar`'s type is
resolved TWICE**, once by G-0's `prescan-value-names` and once by `emit-defvar`.
If the permitted construct needs anything the prescan does not have, the two
resolutions disagree about what is legal. Here the array *length* is a constant
expression folded by `const-fold-int`, which routes through `macroexpand-form`
— and **macros are registered only when their file is emitted**, so at prescan
time `(array i32 (_* K 2))` folds and `(array i32 (* K 2))` does not. The fix is
a third permission state (mode 2, "provisional"): the prescan resolves the
element and leaves the length 0 without folding, which is sound because a
prescan Sym exists only so a forward *reference* resolves and every read of an
array binding goes through `array-decay` (which reads `elem`, never `arr-len`).
The claim is *checked* rather than asserted — a real `(array T 0)` is refused at
parse, so a zero length can only be provisional, and `type-to-ir` dies on one
rather than emitting `[0 x i32]`, which is legal LLVM (a flexible array member)
and would therefore have been silent.

## A new `TY-*` kind: the reach list, and the two sites that are silently wrong if missed

From the same step, as a checklist for the next one. Adding a type kind touches:
`type-to-ir`, `type-to-c`, `type-size`, `abi-sizeof`, `abi-alignof`,
`abi-class-eightbyte`, `type-eq`, `hash-type`, `type-mangle-token`,
`type-spelling`, `emit-zero-store`, the `defvar` zero default,
`parse-type-from-node`, plus every `node-type` mirror of an emitter you change.
Two of those fail *silently* rather than loudly:

- **`type-size` is an ALIGNMENT as often as it is a size.** Its result is fed
  straight into `align N` operands (`emit-defvar`, `emit-load`/`emit-store`,
  `emit-alloca-form`), which LLVM requires to be a power of two. `TY-STRUCT`
  returns the pointer size for exactly this reason, and `TY-ARRAY` returns the
  *element*'s size, not `N * sizeof(T)` — `alloca [3 x i32], align 12` is
  invalid IR. The real size lives in `abi-sizeof`, which is what `sizeof` and
  the layout walk read. If you add a kind whose "size" is not a power of two,
  answer `type-size` with its alignment and put the size in `abi-sizeof`.
- **`abi-class-eightbyte`'s per-field fall-through was `not a struct, not a
  float → INTEGER`.** A new aggregate-ish kind inherits that, and for an array
  of *integers* it is accidentally right, so every size/offset check passes.
  `struct { float v[2]; }` is where it breaks: 8 bytes either way, but the value
  travels in `rdi` instead of `xmm0`, so C and Nucleus disagree only **at the
  call**. `make layout-test` cannot see it; only `make abi-test` can. The
  per-field body is now factored into `abi-class-type-at` so a composite kind
  has somewhere to recurse — use it rather than adding a fourth arm to the loop.

Two more that are loud but easy to forget: **`type-with-volatile`
(`src/nucleusc.nuc`) is the one Type-cloning site** and must copy any new field
(a dropped `arr-len` becomes a zero-length array), and **`type-spelling` must
stay honest about round-tripping** — it is a conformance-registry key and a
generic-substitution replacement text, so a kind with no colon spelling is only
safe if that kind is refused in every position where the spelling is re-parsed.

## A consume-once permission does not survive a delegation

`g-array-ok` is read-and-cleared by `parse-type-from-node` on entry, and only
*then* does it delegate a bare symbol to `parse-type-name`. So any arm inside
`parse-type-name` that wants to consult the permission sees 0 — which is why an
array-bodied `deftype` at a `defvar` was refused for as long as `deftype`
existed, and why Stage 16 L5's "the new probe must consult `g-array-ok` itself"
was not implementable as written.

The fix is to classify each delegation. `(ptr (array i32 4))` is a **nesting**
and must not inherit — that is what consume-once is for. A bare name, and a
transparent alias's body, are the **same type node under another spelling** and
must inherit: `(set! g-array-ok array-ok)` immediately before the call.
`parse-type-name` then consumes it in turn (a thin wrapper capturing into
`resolve-type-name`'s third parameter), so its own `?T` / `!T` / colon
recursions see 0 without a clear at each one.

Generally: before writing code that reads a one-shot global, walk the callers
between the arming site and your reader and find the first read-and-clear. If a
transparent alias for the same concept already exists, the bug is usually already
observable through it — a two-line repro is cheaper than reasoning.

## A decay rule belongs in ONE function that emit and node-type both CALL

`array-decay` (`src/type-utils.nuc`) maps `TY-ARRAY` → `(ref T)` and is the
identity for everything else, so callers apply it unconditionally. It is called
from `emit-symbol-ref`, `emit-field-load`, the two union-member load arms,
`emit-field-addr` and `emit-alloca-form` — and from `node-type-sym`,
`node-type-field`, `callable-get-type` and `node-type-alloca`. That is the
`node-type`↔`emit-node` lockstep applied to a *type transformation* rather than
a typing rule, and it is the same lesson W2a's `binop-result-type` teaches:
mirroring the logic drifts, mirroring a call cannot. `node-type-alloca` is the
one that bit — it independently re-parses the type operand, so it needed both
the decay *and* the permission arm, or the non-emitting pass rejected what
codegen accepted.

## There are TWO type→C renderers, keyed differently, and only one of them is on the header path

`type-to-c` (`src/type-utils.nuc`) is keyed on a resolved `Type` and switches over
`TY-*`. `type-name-to-c` (`src/cheader.nuc`) is keyed on a type *name string* and
runs down a list of `(when (= name "…"))` arms. `--emit-cheader` renders through
the second one exclusively: it walks the form AST and spells each declaration from
the type *node* the source wrote. (Since W9 item 26 the pass does resolve the
unit's signatures — it has to, to know each function's symbol — so the two
renderers are now reachable from the same pass, which makes them agreeing more
load-bearing, not less.)

The second's last arm is **"assume struct"**: any name it does not recognize is
rendered `struct NAME`. So a builtin the list forgets is not a compile error and
not a `/* unknown */` — it is a plausible-looking `struct usize`, `struct Char`,
`struct Err` naming a tag no header defines. Three separate defects have now been
one instance of this: `usize`/`ssize` (14 committed headers, W9 item 3), then
`Char`/`Err` (W9 item 25). Each time, `type-to-c` had the right answer all along.

**When you add a builtin scalar type, add it to both.** The lists are not merely
similar, they answer the same question, and the one that is easy to forget is the
one nothing in the build exercises — a wrong header is discovered by a C consumer,
not by `make bootstrap` or `make test`. `scripts/check-headers.sh` only proves the
committed headers match the compiler; it cannot tell you they are *correct*, and
it will happily lock in a wrong spelling. The check that finds this is compiling a
generated header with `clang -fsyntax-only`, which the `w9-cheader-*` gates do.

`type-node-to-c`'s pointer arm keys on the head SYMBOL, so it has to name every
spelling of the same kind: `ptr`, `ref` (its documented synonym) and `addr-of`
(what a standalone `&T` in a type slot reads as). It named only `ptr` until
2026-09-06, so `(ref T)`/`&T` in an exported signature silently rendered `void*`
— pointer-sized and ABI-correct, which is why it survived, and why two
`w9-cheader-*` goldens had the `void*` spelling written into them. `raw` still
widens deliberately. Docs: `docs/compiler.md` §C headers.

## A standalone `&T` in a type slot is a `(ref T)` node — the same head as the value form

`&` at a token boundary is the `ref` reader macro (`read-macro-table-new`,
`lib/read.nuc`), so `(as &T x)`, `(Vector &T)`, `(p &T)` and `&x` all reach the
parser as `(ref …)`: one node, the non-null pointer in a type slot and the
address-of in a value slot, and `--emit-nuch` prints it canonically. Only a `&`
*inside* an atom (`p:&T`, `?&T`, `):&T`) is the type sigil the lexer rewrites to
`ref:`. `addr-of` is a value-world head the compiler still accepts (Stage 21
PK-1; retired in PK-5, pointer-kind-spellings.md §7) and no type consumer
recognizes it any more. Attached forms are still preferred in exported
signatures only as a matter of taste — nothing leaks into a header now.

## In C, a typedef is not a tag — emit both, and give them the same spelling

`typedef struct { … } Rec;` defines a typedef named `Rec` and **no** struct tag, so
`struct Rec` is a different, never-completed type. This was W9 item 25: the header
emitter used the anonymous form while `type-name-to-c` spells every reference to a
user type `struct Rec`, so the generated header could not use its own types by
value — a nested field or a by-value parameter both failed "incomplete type" —
while pointers kept working, because an incomplete tag is legal behind a pointer.
That asymmetry is why it survived: the pointer-shaped uses that dominate a C API
gave no sign.

`typedef struct Rec { … } Rec;` is the form to emit. Tag and typedef live in
separate C namespaces, so sharing the spelling is legal and makes both `Rec` and
`struct Rec` correct, which means no *reference* site needs a special case. The
alternative — teaching each reference site to drop the `struct ` prefix — was
tried locally (`cheader-by-value-c`) and is what the tag replaced.

## An exported symbol is a REGISTRY answer, not a spelling rule — ask, do not re-derive

`ns-ir-base fname` looks like "the symbol for this function" and is one only for a
**solitary, non-operator** `defn`. An overloaded name takes a per-signature
mangled symbol; an operator name takes one *even when it is the sole user method*,
because its generic always carries the intrinsic seed beside it — so `=` on a
struct links as `eq.Pt.Pt` and there is no `=` in the object at all. Both
decisions are made in `finalize-generics` (`src/generics.nuc`) and recorded on the
`Method`; `defn-form-mangled-name` reads them back, answering null exactly when
`ns-ir-base` is right.

W9 item 26 was the C header emitter deriving that answer itself. 100 of the 236
symbols the committed `lib/*.h` bound named nothing any object defined, and a
`defn` whose C name sanitized to `_` (every operator does) was declared twice
under one identifier. The `.nuch` emitter beside it never had the defect, because
it asked.

Whether a name is overloaded is a property of the **compilation unit**, not of the
file — a library that contributes one `hash` to a name the prelude also defines
still exports `hash.pString`. So an export pass must run the whole prescan
sequence, `prescan-imported-signatures` included, not just prescan its own forms.
Prescanning the file alone makes every such name look solitary, which is the same
wrong answer arrived at more expensively.

## A prescan runs with NO module stream open — an eager `fprintf` there is a null deref

`open-module-streams` is called only on the compile path; `--emit-nuch` and
`--emit-cheader` return before it. So `g-type-stream`/`g-decl-stream`/`g-def-stream`
are null for the whole of a header emission, and any code a *prescan* can reach
must not write IR. `lookup-or-make-anon-struct` (`src/union-registry.nuc`) was the
one eager writer among the anonymous-type constructors — its sibling
`lookup-or-make-anon-union` queues to `g-pending-unions` instead — so
`--emit-nuch` segfaulted on any anonymous struct in a signature, from the day it
was written until W9 item 26 (which is also how `--emit-cheader` acquired the
crash: it started prescanning).

Guard on `g-module-open`, and leave `emitted` **0** when you skip the write — the
flag means "already in the type buffer", and setting it while writing nothing
would suppress the real emission if one ever followed.

The guard used to read `(!= g-type-stream null)`, which was the honest condition
while the buffers were `FILE*`s. Stage 17 C3 made them `String` **values**, which
have no null, so the condition became a separate flag set by
`open-module-streams`. The lesson generalizes past this one guard: **a
representation change silently deletes every invariant that was riding on the old
representation's sentinel.** Grep for the sentinel test before changing the type,
not after — the compiler will not report a guard that has quietly become
`true`.

The other way out of this is to make the prescan *have* nothing to write:
`prescan-nuch-signatures` (W9 item 29) registers a header's names and emits no IR
at all, which is why it needs no stream guard and is correct in all three modes.
Prefer that shape when you can have it.

## A `.nuch` import is REGISTER + EMIT — split it by mode, and prove registration before emitting alone

`emit-nuch-declare-import`, `emit-nuch-defmethod-import` and `emit-extern` each do
both halves in one pass. The whole-graph prescan (W9 item 29) may only do the
**registration** half: hoisting the emission too would move every `declare` /
`external global` line to the top of `g-decl-stream` and change the IR of every
module that imports a header — `src/llvm.nuch`, so the compiler's own. Hence the
`NUCH-BOTH` / `NUCH-REG` / `NUCH-AFTER` parameter on all three.

Two traps in the emit-only half:

* **"Registered" is per NAME, not per header.** Every one of the three has an
  "already defined → return" skip (two headers declaring one `stderr`; the unit
  defining the name itself, W9 item 36), so the prescan may have registered some
  of a header's names and not others. Emitting the whole header on the strength
  of "this header was prescanned" writes `@x = external global` twice, which LLVM
  rejects. `g-nuch-registered` records `(path, name)` pairs and the emit-only path
  asks per name, falling back to register-and-emit when the answer is no.
* **Re-registering is an ERROR, not a no-op.** `generic-register-method` appends
  unconditionally, so a second pass over one `defmethod` makes `finalize-generics`
  report a duplicate overload. The per-path `g-prescan-sigs` guard —
  the same list `emit-toplevel-forms` reads for a `.nuc` file — is what stops it;
  `do-import` has set `g-source-path` to the header's own path by then.

A header cannot `import` (there is no `import` arm in `emit-nuch-import-forms`),
so the prescan does not recurse into one.

## In a shell test under `pipefail`, never pipe into `grep -q`

The shell suite this was written for is gone (Stage 18 TF-7), but every script
left in `tests/` and `scripts/` still runs under `set -uo pipefail`, and the trap
is one line away from returning.

`grep -q` exits at its first match, which SIGPIPEs the process feeding it, and
that non-zero status becomes the pipeline's — so an assertion that **matched**
reads as false. It is one-sided (a real non-match never trips it: grep then reads
to the end), so it surfaces as a few tests failing at random rather than as a
consistent wrong answer, and it only bites once the producer's output outgrows a
stdio buffer. Measured on the 54KB of IR one former unit grepped: 186 of 200
identical runs said "no match" for a pattern that is present. Either `grep "$@"
>/dev/null` (same exit status, reads to the end) or grep a file.

That fixes the producer-SIGPIPE half only. **`pipefail` also reports a producer
that legitimately fails** — which every rejection check has, since the compiler
exits non-zero on the error being asserted. `nucleusc … 2>&1 >/dev/null | grep -F
'the message'` is false whenever the message is present. Redirect stderr to a
file with `|| true`, then grep the file. (Every one of these is a non-issue in
`tests/suite-*.nuc`, where the compiler's status and its stderr are two fields of
one record.)

A second trap when writing a test *about* headers: `resolve-import` tries
`NAME.nuc` in every directory before any `NAME.nuch`, so a header sitting beside
its source is never imported (that ruling is pinned by `w9-import-prefers-source`).
Put the generated `.nuch` in a directory of its own and point `-I` at that, or the
test silently exercises the source instead.

## A legal C identifier is more than legal characters — and the escape goes on the JOIN

`sanitize-for-c` maps illegal *characters*. It has no notion of a reserved word,
so `union`, `signed`, `default` and `class` — all ordinary Nucleus names — reached
the generated header intact and it did not parse (W9 item 28).
`cheader-c-ident` now appends a `_` to a word C **or C++** reserves; C++ because a
generated header is routinely read through `extern "C"`, and because `new`, `try`,
`template` and `operator` are names a library plausibly defines.

Three things to keep in mind if you touch this:

* **Every complete C identifier goes through `cheader-c-ident`**, including a
  struct/union tag. The tag is an identifier (`struct union {…}` does not parse),
  and its *definition* and every *reference* must escape in lockstep — the same
  three-site lockstep (`type-name-to-c`, `emit-cheader-defstruct`,
  `emit-cheader-defunion`) that B3′ and W9 item 25 each had to repair.
* **Escape the join, not the fragment.** `Color_default` is already a fine
  identifier; escaping `default` inside it renames a C constant for no reason.
  `cheader-c-ident-join` tests the finished string — which can still land on a
  keyword (`and` + `eq`).
* **The `asm` label follows for free.** `cheader-asm-label` emits a label exactly
  when the C spelling differs from the link name, so a rename re-binds itself and
  the symbol never moves. Never rename an identifier without routing it through
  that comparison.

## `?`/`!` in names map to `_QMARK`/`_BANG` in emitted symbols — in EVERY name position, not just the exported ones

A `defn`, struct, or union name may contain `?`/`!` (`full?`, `push!`, `Full?`)
— `ir-name-token` (`src/format.nuc`) maps each `?`→`_QMARK` and each `!`→`_BANG`
in the emitted LLVM symbol (`@full_QMARK`, `%Full_QMARK`), applied at the
base-token layer shared by every ir-name derivation site (solitary/overloaded
`defn`, `defvar`/`extern` globals, `.nuch` import, REPL, struct/union type
names — see the `StructDef.name`/`.ir-name` note below); every other
character, hyphens included, is untouched. A residual illegal character
(anything outside `[A-Za-z0-9$._-]`) is caught at define/declare emission with
a clean source-level diagnostic (`check-ir-name-legal`, `src/abi.nuc`) instead
of a raw LLVM parse error.

**W9 item 39: the rule is "this becomes an LLVM identifier", not "this is a
global symbol".** Until that item the transform was applied only at the
global-symbol and type-name layers, so a **parameter**, a `let`/`with` binding,
a `match` binder and a `label`/`goto` target went out verbatim and LLVM rejected
the module the compiler had just written — `define i32 @add_QMARK(i32 %ok?.arg)`,
the function name mangled and the parameter three tokens away from it not. If
you add a construct that turns a user name into a `%…` local, it must call
`ir-name-token`. The current producers are `abi-print-param-to` +
`abi-emit-param-prologue` (two spellings of one `%<param>.arg`, so they must
agree), six `%<binder>.addr.N` sites in `union-emit.nuc`, `emit-let`/`emit-with`
and the drop-handle slot, the macro prologue, and the five producers of
`%lbl.<name>` (`emit-label`, `emit-goto`, `emit-label-addr`'s `blockaddress`,
`emit-goto-ptr`'s `indirectbr` list). **`scope-define` keys on the SOURCE name at
every one of them** — only the emitted slot string carries the escape.

**A leading digit is the other half of the rule, and a character class cannot
express it.** LLVM's unquoted identifier is `[%@][-a-zA-Z$._][-a-zA-Z$._0-9]*`:
a body character class *and* a first-position restriction. `ir-name-illegal-char`
tests only the class, and a digit is in it, so `(defn 2fast …)` passed every
front-end check and died at IR-parse time. `ir-name-token` now prefixes one `_`
(`@_2fast`, `%_2Pair`); `ir-name-leading-digit` is the matching predicate and
`check-ir-name-legal` reports it as its own message rather than as an "illegal
character", which would name a character its own list of legal ones contains.
C has the identical restriction — but the escape there goes in `cheader-c-ident`
(via `cheader-escape-leading-digit`), **not** in `sanitize-for-c`, for the reason
in the "escape goes on the JOIN" note above: `sanitize-for-c` also runs on
fragments, and `2circle` joined after `_2Shape_` is not at position 0. Use the
same `_` on both sides deliberately — that is what makes the C spelling equal the
link symbol, so `cheader-asm-label` emits nothing.

If the compiler's own source (`src/`, `lib/`) ever adopts `?`/`!`-suffixed
names internally — beyond the lib helpers that already do (`contains?`/
`empty?` on `HashSet`/`HashMap`), which only shifted the self-hosted IR
because the compiler imports them — the bootstrap output will shift
(string-pool renumbering) the same way SM-1/SM-3/SM-4 needed a
`make update-bootstrap` reconverge. Expect the same two-pass reconverge, not
a bug.

## `StructDef.name` is the source spelling / lookup key; `StructDef.ir-name` is the LLVM `%Name`

Two distinct slots (SM-4): **`name`** is the raw source symbol text and the
**lookup key** — `lookup-struct` matches a source type token (e.g. `Full?`) against
it by **interned-pointer identity**, so `name` must never be mangled or resolution
breaks. **`ir-name`** is the LLVM-safe spelling (`?`→`_QMARK`, `!`→`_BANG` via
`ir-name-token`; every other char, hyphens included, unchanged) and is what **every**
`%Name` reference and definition prints, so a `(defstruct Full? …)` emits legal
`%Full_QMARK`, not `%Full?`. `ir-name` is computed **once** in `register-struct`
(src/abi.nuc) — the sole StructDef allocator (the anon-struct/union, fatptr/boxedfn/dyn,
and closure-env builders all route through it), so setting
it there covers 100% of StructDefs. For a name without `?`/`!`, `ir-name-token` is a
pointer-identity no-op, so `ir-name == name` and the whole compiler self-IR is
byte-identical.

**There is NO single type-REFERENCE chokepoint.** `type-to-ir` handles Type→IR
strings, but GEP aggregate-type operands and `alloca`/`load`/`store` type operands
across `union-emit.nuc`/`nucleusc.nuc` print the struct name **directly** from a
StructDef in hand (`getelementptr inbounds %<name>, …`), bypassing `type-to-ir`.
Every one of these must use `(sd ir-name)`, not `(sd name)`. Rule of thumb: a struct
name going into an IR stream (`g-out`/`g-body-stream`/`g-type-stream`) uses
`ir-name`; a struct name in a **diagnostic** (`fmt-*`/`die-at`) or in
**source-symbol construction** (`intern-symbol`, a `(sizeof S)` node whose `S`
resolves by source name) uses `name`. Missing an IR site fails loudly at the LLVM
parser (`%Full?` → "expected comma after getelementptr's type"), not silently. Note
`ir-name` is also an (unrelated) field name on `Sym`/`ProgDefn`/`Method` (the emitted
`@symbol`); field access is per-struct-type so there is no collision.

## Symbol nodes are interned singletons — they have **no line**, and you must never write one

`lib/read.nuc`'s `rd-atom` interns every symbol it reads (`intern-node
(rd-expand-sigil tv)`): every occurrence of a spelling anywhere
in the program is the **same `Node`**, and `intern-symbol` sets its `line` to 0.
Every other node kind (`NODE-INT`, `NODE-STR`, `NODE-CHAR`, `NODE-FLOAT`,
`NODE-KEYWORD`, and cells via `make-cell`) is allocated per occurrence and does
carry its reader line.

Two consequences, both load-bearing:

- **`(sym line)` is 0, so a diagnostic whose subject is (or may be) a symbol
  must borrow the enclosing form's line.** Use `node-line` (`lib/node.nuc`):
  `(die-at (node-line subject (cc line)) …)` — it returns the node's own line
  when it has one and the fallback otherwise, so the same expression is correct
  whether the subject turns out to be a symbol or a cell. Stage 15 W4a converted
  ~110 raise sites to this shape. The guard that keeps it that way is
  `w4a-no-line-zero` in `tests/suite-audits.nuc` (compiles every fixture and
  reads the `line` field of every diagnostic) plus `check-no-line-zero` inside
  the manifest's own rejection runner. **That guard sees SITES only through
  FIXTURES**: a raise no fixture reaches is unaudited, which is how the type
  operand of `as`/`cast`/`sizeof`/`alloca`/`array` — and their `node-type`
  mirrors — kept passing `(tn 'line)` to `parse-type-from-node` until Stage 21
  PK-3 (`(as Nope 1)` reported `:0:`). A type operand is the classic
  may-be-a-symbol subject; hand the parser `(node-line tn (cc 'line))`.
- **Never `(set! (sym 'line) …)`.** The write is observed by every *other*
  occurrence of that spelling in the program. `stamp-macro-lines`
  (`src/nucleusc.nuc`) used to do exactly this while attributing macro
  expansions, so after the first expansion mentioning `x`, every later
  diagnostic about any `x` anywhere reported that macro's call line. It now
  skips `NODE-SYM` outright (symbols have no children, so nothing is lost).

Interning is not removable: symbol identity is compared **by pointer**
throughout the compiler (`(= n 'null)`, `(= head 'label)`, the special-form
`case hp` dispatch), so per-occurrence symbol nodes would break resolution
wholesale.

`emit-symbol-ref` is the one site that cannot be handed a node — `emit-node`
dispatches to it with only the operand, and `emit-node` has ~98 call sites. It
takes an explicit `line:i32` parameter filled from **`g-form-line`**, an ambient
"innermost enclosing form line" maintained with strict save/restore in
`emit-node`. That global is the *only* dynamic part of the scheme; it is the
line half of a diagnostic location, ambient exactly like `g-source-path` is its
file half. If you add a new emitter, you get it for free — but if you add a new
*raise*, prefer `node-line` with a node you already hold.

## Reader diagnostics: the innermost unclosed form is already blamed; bracket depth lives in `next-tok`

`read-list` is recursive, so at EOF the **deepest** invocation runs `report-at`
first and every enclosing one just propagates its `(err! parse-error)` through
`try` without reporting again. An `unterminated list` therefore names the
**innermost** still-open form's opening line, not the outermost — do not
"fix" it to report the innermost; it already does. (Stage 15 W4c's design doc
asserted the opposite; measured false.)

Bracket balance is tracked on the `Reader` itself (`rd-open-bracket` /
`rd-close-bracket`, `lib/read.nuc`, called as each bracket **token** is
produced) covering `(`/`)`, `[`/`]`, `{`/`}`, `#{`/`}`. Two properties are
load-bearing: the depth (the `paren-depth` field) is **not clamped at zero**
(a negative depth is exactly "this closer has no matching opener", which is
what distinguishes a stray top-level `)` from a `)` inside an unclosed
`[…]`), and because it counts tokens rather than characters it is immune to a
bracket inside a string literal or comment — unlike a naive external paren
counter. The four fields (`paren-depth`, `form-open-line`, `col0-open-line`,
`col0-open-depth`) live **on the `Reader` value**, not in a global — each
`reader`/`read-all` call starts a fresh one, so nothing needs resetting or
save/restoring across a nested read the way the old compiler globals did (a
Stage 21 R-2 simplification: an import site used to save/restore five reader
globals by hand; a nested read is now just a `Reader` in the callee's frame).

Column-0 detection needs no column counter: at the moment a bracket token is
produced `pos` still points at the bracket, so `src[pos-1] == '\n'` is exactly
"this bracket is the first character on its line" (`rd-at self (- pos 1)`).
Prefer that lookbehind to threading a column through the char-reading
primitives — one fewer invariant a future lexer path can forget. (Verified:
idiomatic Nucleus has **zero** column-0 `(` at nonzero depth across `src/`,
`lib/`, `examples/`, `tests/`, which is what makes "a column-0 `(` while a
form is open" a reliable imbalance signal.)

## An extra `)` in a `let` binding list leaves an EVEN binding list

The even-count check in `emit-let`/`emit-with` catches an extra `)` after a
binding **name** (`(let (a:i32 1` / `b:i32)` → 3 elements, odd). It cannot catch
an extra `)` after a binding's **value** (`(let (a:i32 1)` / `b:i32 2)` →
`(a:i32 1)`, 2 elements, even), which instead pushes the next binding into the
**body**. If the author compensates with one fewer `)` at the end, the file
parses *correctly* — so this is invisible to the reader too, and used to surface
only as `undefined: b:i32` at the use. `check-stray-typed-body`
(`src/nucleusc.nuc`, W4c) diagnoses it: a `let`/`with` body form that is a bare
colon-typed `NODE-SYM` not resolvable in scope is never a meaningful expression.
When reasoning about binding-list mistakes, keep the two shapes distinct — they
have different element parities, different failure modes, and different layers.

## Struct field names are interned — StructDef builders must use `intern-str`

`struct-field-index` (src/nucleusc.nuc) matches a selector against a struct's
`field-names` by **pointer identity** (`=`), not `strcmp`. This works because both
sides are interned: selectors arrive interned (the reader / `quote` intern symbol
spellings at lex time, so `(fn-node 's)` is the canonical string) and stored field
names are interned at build time via `intern-str` (interns the spelling, returns the
canonical string pointer). The three field-access paths — `.` (`emit-field-get`),
the `get` intrinsic (`emit-get-intrinsic`), and the non-emitting type pass
(`node-type-field`) — all route through `struct-field-index`, so they cannot drift.

There is exactly **one** place that populates a StructDef's `field-names`:
`emit-defstruct` (the normal path, incl. `.nuch` imports). It **must intern each name**
(`(intern-str fname)`). A raw string literal would `strcmp`-equal a selector but **not**
be pointer-identical, so the field would silently look absent (`-1` ⇒ "no field" / null
type). If you add a second StructDef builder, intern its field names too. The
`make bootstrap` fixed point does **not** exercise the REPL path — the
`repl-redefinition` test does (its `*`/`-`/`if` macros do `((cast ptr:Node args) 'cdr)`
at expansion time), so keep `make test` green, not just `make bootstrap`, when touching
field interning.

**A hand-mirrored struct drifts in its field TYPES too, and Stage 16 R2 removed the
only one.** `repl-register-node` used to build `Node` by hand for the REPL, and had to
mirror `lib/prelude.nuc`'s `defstruct Node` slot for slot. It did not: when `car`/`cdr`
were retyped `ptr`→`(raw Node)` the mirror kept bare `ty-ptr`, and three `NODE-*`
ordinals were never registered at all. The bare-`ptr` symptom is worth knowing on its
own — a macro that reads `(p car)` once works, while one that **chains** without a cast
(`((spec cdr) car)` in `dotimes`) dies in `emit-get-intrinsic` with "callable value: not
callable", because `(spec cdr)` returns an untyped `ptr` (elem=null) so `ek` resolves to
`TY-VOID` and the `TY-STRUCT`/`TY-UNION` gate fails. The REPL now imports the real
prelude instead (`repl-preload-prelude`), which is why the drift is gone rather than
merely fixed; see design/stage16-ergonomics/repl-libraries.md §3.1.

## `()` reads as a **NULL node** — never deref a user-supplied node without `node-line`/a guard

`read-list` returns `head`, which starts null, so the empty list `()` reads as a
**null `Node*`** — and `read-list` then wraps it in an ordinary cell whose `car`
is null. So any list a user writes can contain a null element, in any position:
a `(struct …)`/`(union …)` member, a `defstruct` field, a `defn`/`defmacro`
parameter, a `defunion` arm, a `let`/`with` binding, or an expression. Nucleus
does not null-check field access on a `(raw Node)`, so a bare `(n kind)` /
`(n s)` / `(n line)` on such an element **segfaults the compiler with no output
at all** — which is exactly what Stage 15 W5f was reported as ("union with a
function-pointer member segfaults"; ten separate sites were faulting).

Two rules when you touch a loop over user-written list elements:

- **Never compute a diagnostic's line with `((unsafe/cast ptr:Node x) line)`.**
  Use `(node-line x <enclosing-line>)` (`lib/node.nuc`) — it is null-safe *and*
  it upgrades an interned symbol's always-0 line to the enclosing form's (the
  W4a `:0:` class). The two are the same fix; the raw deref is never right.
  Note the trap this hides: the line argument is evaluated **before** the callee
  runs, so a null guard inside `extract-name-and-type` does not save a caller
  that dereferenced the node to build that callee's `line` argument.
- **Guard before a `kind`/`s` test in a marker scan.** `:rest`/`:optional`/
  `:where`/`:repr` scans run over the raw element list before any validation, so
  they see the null first. Bind the element as `(raw Node)` and `(and (!= e null)
  (= (e kind) NODE-SYM))`.

The shared chokepoints now diagnose rather than fault — `extract-name-and-type`
(struct/union members, defstruct fields, defn params, let/with bindings,
defunion arm fields) and `emit-node` (expression position) — so a **new** loop
usually only needs the two rules above rather than its own message. Guards are
error-path-only and cannot move emitted IR, so they never disturb the bootstrap.

See also "Symbol nodes are interned singletons" above: `node-line` is the single
accessor that answers both hazards, which is why "use `node-line`" is the whole
rule rather than two.

## A function-pointer type is TWO parenthesised groups — the colon-paren fuse must absorb both

`(fn ret)` and its parameter list are separate list elements
(`((fn ret) (params))` canonical), so the colon-paren binding fuse
(`rd-fuse-colon-paren`, `lib/read.nuc`) — which absorbs *one* paren form after an
atom whose final chain segment is open (`x:`, `x:?`, `?`; Stage 21 PK-2, called
from `rd-form` on every atom) — cannot express a function-pointer type by itself.
`rd-fuse-fn-params` (added in W5f, called from `rd-fuse-colon-paren` right after the
first recursive read) absorbs a **second, immediately-adjacent** group when the
first is `(fn …)`-headed, producing the nested `((fn ret) (params))` — which
`extract-name-and-type`'s CELL branch passes straight to
`parse-type-from-node`'s fn branch, and which composes for free with the
colon-chain wrap (`p:ptr:(fn i32)(i32)`) and the lone-colon return fuse.

Two things to know before touching this:

- **Adjacency is load-bearing, not a stylistic choice.** A *space*-separated
  second group cannot be absorbed: in `(f:(fn i32) (i32 i32) a:i32)` nothing
  distinguishes the parameter list from a `(name type)` binding of the enclosing
  list. `docs/types.md` documented the spaced spelling for years and it **never
  worked** — `f` bound as a zero-parameter fn and `(i32 i32)` became a junk
  parameter, so the mistake only surfaced at the call site
  (`call: expected 0 args, got -1`). It is still accepted silently; see the W5f
  deferral note.
- **`name:(fn ret)` with no following group is legal and means *zero*
  parameters** (C's `ret (*)(void)`), so the absorption cannot be made
  mandatory.

The one new footgun, accepted deliberately: in a `let`/`with` binding list the
element after the name *is the initializer*, so `(let (f:(fn i32)(choose)) …)`
now absorbs `(choose)` as the parameter list. That fails **loudly and located**
(`let: binding list must be even`, because the pair became one element), no
existing source in the tree writes it, and the fix is a space. There is no
better rule available — the reader has no type context, and a single-symbol
parameter list `(i32)` is structurally identical to a single-symbol call
`(choose)`.

## The string-type lattice: `StrView` / `String` / `Symbol` / `CStr` — gate pointer ABI on `is-ptr-like`, not `TY-PTR`

Four string-carrying types, and after Stage 17 the compiler's own strings are the
first three. **Pick by what you need to do with it:**

| type | is | pick it for |
|---|---|---|
| `StrView` | 16-byte `{data:(ptr ui8), len:usize}` borrowed view; the `"…"` literal type | text you write out or scan: IR operands, diagnostic fragments, an `fstr` result |
| `String` | owning, growable | a buffer you append to (the emission streams, `str-alloc`) |
| `Symbol` | one word at interned bytes, with a `[hash][len]` header *behind* the pointer | a NAME: `=` is pointer identity, `hash` is free, and it is NUL-terminated so `symbol-as-cstr` is a no-op |
| `CStr` | `char*`, content `=` | the FFI boundary, and nothing else |

**`Symbol` is the answer whenever a string is compared, hashed, stored in a
table, or eventually handed to C.** `Node.s`, scope keys, struct-field names,
`Sym.ir-name`, every path and triple, the `-I`/`-l` lists: all `Symbol`.

**A `StrView` is not NUL-terminated.** A literal's backing rodata happens to be,
which is why `strview-borrow-target` lets a view collapse to `ptr`/`CStr` with no
IR — but an `fstr` result ends at `len` with nothing after it. To reach a C
function, intern it: `(symbol-as-cstr (symbol-intern (fstr …)))`. The borrow is
silent and nothing typed catches it; `scripts/check-cstr.py` enumerates the whole
remaining boundary in `src/` instead, and `make test` fails on any change to it.

`(if c "a" "b")` is a `StrView`, materialized at the join (`join-strlit-branch`).
It collapsed to `CStr` before Stage 17 C8, which is what made a `ptr`-typed local
the accidental idiom for a two-literal `cond`; the local should be `StrView`.

`TY-CSTR` lowers to `ptr` in IR and is a plain `char*` at the ABI. It is a
*distinct kind* only so `=` / `!=` dispatch to a `strcmp` content comparison
(`emit-binop-vals`) instead of pointer identity. **Everywhere else it must behave
exactly like `TY-PTR`:** `type-to-ir` → `ptr`, `type-size` → 8, zero-init →
`null`, `cast` to/from `ptr` is a no-op, and it must never be `inttoptr`'d (it is
already a pointer). A bare `(= (t 'kind) TY-PTR)` ABI check therefore *misses*
`CStr` — use the `is-ptr-like` predicate ({`TY-PTR`, `TY-CSTR`}; `TY-FN`
deliberately excluded, `StrView` is a struct not a pointer). This bit the
`:rest` arg-folding (`emit-call-with-args`), which `inttoptr`'d any non-`TY-PTR`
arg and produced invalid `inttoptr ptr→ptr` for a `CStr` rest arg. When adding a
new pointer/integer ABI decision, branch on `is-ptr-like`.

This trap has now been hit **three** times: the `:rest` folding above, W5c's
`defvar-init-ir` string-literal/`null` gates, and W5d's `emit-zero-store`, which
filled an unspecified slot with the scalar `0` for anything that was not
`TY-PTR`/`TY-F32`/`TY-F64` — so a `CStr` or `TY-FN` slot got `store ptr 0` and a
struct/union slot got `store %P 0`, both rejected by the LLVM parser with
*"integer constant must have integer type"* (an aggregate zero is
`zeroinitializer`, and only aggregates and pointers have a spelling other than
`0`). Each instance was a *constant/ABI decision written as a kind test*. When
you add one, the question is never "is this `TY-PTR`" but "what does this type
lower to" — and for zero-fill specifically, remember the third bucket: scalars
(`0`), pointers-of-any-flavour (`null`), and aggregates (`zeroinitializer`).

**`TY-FN` is NOT in `is-ptr-like`, and it is not going to be. Ask
`is-ptr-repr`.** The exclusion is deliberate and load-bearing: `is-ptr-like`
means three things at once — "lowers to `ptr`", "participates in the free
`ptr`↔`CStr` value coercion", and "`=`/`!=` lower to `strcmp`" — and only the
first is true of a function pointer. Widening it to "fix" the next hole would
silently make `(= some-fn-ptr some-cstr)` a `strcmp` of a function's machine
code. `tests/fixtures/w9-fnptr-cstr-compare.nuc` is the tripwire for exactly
that; it must stay a diagnostic.

So the representation question has its own predicate, `is-ptr-repr`
(`src/type-utils.nuc`) = `is-ptr-like` ∪ {`TY-FN`}: *is this value one `ptr`
register?* Ask it for storage, constant and comparison decisions; ask
`is-ptr-like` for coercion and string decisions. **This rule cost two defects
before it had a name** (W9 items 18 and 19). The convention used to read "admit
`TY-FN` by name at each site", and by W9 it had been hand-written at three
storage sites (`emit-zero-store`, `type-zero-const-ir`, `defvar-init-ir`) and
two ABI sites (`abi-alignof`, `abi-sizeof`) — while the two *comparison* gates
in `emit-binop-vals` and `type-size` itself simply never got their copy. So
`(= hook null)` died `= expects integer operands` for a fn pointer in every
position (item 18), and every fn-pointer slot claimed `align 1` (item 19). Five
correct copies, three missing ones. That is the same shape as W9 item 15's GEP
index width, and the same lesson: **"write the extra arm at each site" is not a
convention, it is deferred drift.** A predicate whose doc comment states what it
is *not* for is the way to keep two rules separate — not eight copies of one of
them.

**`type-size` is the one home for "how wide is a slot", and it asks
`is-ptr-repr`** (W9 item 19). It used to list `TY-PTR` and `TY-CSTR` as arms and
omit `TY-FN`, which therefore fell to the default `(return 1)` — so every
fn-pointer global, alloca, load and store was emitted `align 1`. That is not a
miscompile but it is not free either: x86-64 tolerates unaligned access, which
is why it survived, but a strict-alignment backend must honour the claim and
splits the access byte-wise — one `ldr` became four `ldrb` plus three `orr` on
armv7, eight `lbu` plus shifts on rv64, for *every* fn-pointer load. `abi-alignof`
and `abi-sizeof` had each been given their own hand-written `TY-FN` arm (a third
and fourth copy of the rule) and now fall through to `type-size` instead.

Two facts worth keeping if you touch slot width again: the change moved 139 IR
lines across 41 corpus files and **every one of them was `align 1` → `align 8`
on a `ptr`** — nothing else, so a diff with any other shape in it means you
changed more than the alignment. And it moved **none** of the compiler's own IR:
`src/nucleusc.nuc` contains no `TY-FN` slot, so self-compilation cannot witness
this class of defect. `tests/fixtures/w9-fnptr-align.nuc` exists because of that
blind spot; its gate asserts the invariant (*no* `ptr`-valued slot claims
`align 1`) rather than a count, and asserts the width on a 32-bit target too.

**`null` into a `TY-FN` slot is gated on `Val.is-nlit`, not on a type test — and
it cannot be otherwise.** The literal `null` is typed `ty-raw`, and `raw`
resolves to that *same singleton* (`union-registry.nuc`), so a `raw`-declared
binding and the literal are indistinguishable by type. Any type-directed rule
admits both or neither, and admitting both makes every data pointer silently
callable. Hence a third literal flag on `Val` (W9 item 20), following exactly
the precedent W2d set when it added `is-flit` rather than overloading `is-lit` —
one flag, one meaning. The escape hatch stays explicit and *is* spellable, in an
extra pair of parens so the function type is one form:
`(unsafe/cast ((fn i32)(i32)) p)`. `tests/fixtures/w9-fnptr-null-launder.nuc` is
the tripwire for re-gating this on `is-ptr-repr`.

**And `TY-FN` is not a pointer *kind* either — `ptr-pkind` answers `PTR-RAW` for
it, like every non-`TY-PTR` kind.** So a fn pointer is outside the Phase-F
non-null regime by construction and `null` is its honest zero; the non-null
spelling people reach for, `ptr:(fn …)` / `(ref (fn …))`, is a pointer *to* a
function pointer and is still `PTR-REF`. Before concluding a `pkind-flow-check`
carve-out is a hole, check which of the two the destination actually is.

**`StrView` literal → `CStr`/`ptr` is a free coercion (the hidden-NUL hinge).** A
`"…"` literal's backing `@.str.N` rodata global is NUL-terminated at `data[len]`
(the table emitter appends `\00`), so a `StrView` literal coerces freely, in
value position, to `CStr` or `ptr` by taking `data` — no IR for an unmaterialized
literal (the chameleon's value *is* `data`), one `extractvalue` for a general
`StrView` value. This is what keeps every `fprintf`/`snprintf`/`strcmp`/libc
site in the compiler working unchanged after the NS-3 literal flip. Sound only
because literals are NUL-terminated; an arbitrary `strview-sub-bytes` slice may
not be — `strview-to-cstr` carries the same trust contract.

Two deliberate asymmetries: (1) `CStr`↔`ptr` coerce freely in *value* positions
(`coerce-int-val`) but **not** in multimethod dispatch (`arg-adapts`) — `CStr` is
distinct there on purpose, so you can overload `CStr` vs `ptr`; pass a literal to
a plain `ptr` function freely, but to a `ptr` *multimethod* cast explicitly. A
`StrView`-typed argument adapts to a `CStr` parameter but *not* to a bare `ptr`
parameter (reproducing the pre-NS-3 dispatch a `CStr` literal produced).
(2) Conformance is keyed by `type-spelling`, which must return `"CStr"` (not the
fall-through `"ptr"`) or `(extend CStr Eq)` won't match the call-site check.

**Mixed-operand rule (`emit-binop-vals`):** `=`/`!=` fire the strcmp lowering when
*either* operand is `CStr` or `StrView` (the other must be `ptr`/`CStr`/`StrView`;
a `StrView` operand contributes its `.data` pointer to the `strcmp`); two plain
`ptr` stay `icmp` identity. So `(= some-ptr "literal")` is a content test (the
literal is `StrView`) — this is what lets the compiler write `(= name "i32")`
instead of `(= (strcmp name "i32") 0)` without retyping `name`. The corollary
trap: any value you retype `ptr`→`CStr` (or `ptr`→`StrView`) makes *all* its
`=`/`!=` become strcmp, so never retype a field/param that is compared for
pointer identity — notably **`Node.s`** (the interned-symbol path) and
struct-field names. This is the NS-5 exclusion list: identity-substrate
`ptr`s stay `ptr`; only adopt `StrView` where a carried length removes a
`strlen`/re-scan and identity is not at stake. `strncmp` (prefix) has no
operator; leave those as calls.

**Corollary, stage17 C7-4b: `(= sv null)` is a compile error.** Retyping a
`ptr`/`CStr` field to `StrView` leaves its null guards *compiling* and turns them
into `strcmp(%data, null)` — the W5c null-check trap, one level down, and
invisible to any residue count (the borrow is inside the operator's own
lowering, not at a `CStr` parameter). A view is never null, so the comparison is now
rejected outright; when you retype a field, the guard you must rewrite is
`(str-empty? &v)`.

**Corollary, stage17 C7-5: a string literal inside `[…]`/`#{…}`/`{…}` is a
`StrView`.** It was `CStr` until C7-5 — the one place `"…"` was not a view — so
a `(symbol-as-view x)` handed to a literal-built set was silently borrowed back
to a C string *inside* the container's monomorphized `hash`/`=`, where
no source file shows it. Two consequences when you write one: the element
type reaches the whole container (`{"a" 1}` is a `(HashMap StrView i32)`), and a
retype like this needs no bootstrap shim if every literal binds through an
explicitly typed local — `(let ((s (ref (HashSet StrView)))) #{…})` is the shape
a `want` arms, so the old and new compilers agree on it. A container *declared*
`(HashSet CStr)` is unaffected: the literal still free-coerces at the call.

**Correction (stage14 14.3, 2026-07-12): `scope-define`/`scope-lookup` keys
are NOT identity-compared** (an earlier version of this note listed them
alongside `Node.s` as identity-substrate — stale). `Sym.name` has been `CStr`
since well before Stage 14 (commit 079a0135), so `scope-lookup`'s `(= (sym
name) key)` already lowers to `strcmp` regardless of the `name`/`key`
parameter's own declared type (the mixed-operand rule fires off `Sym.name`
alone) — this is *required*, not incidental: the global scope's namespace
qualification (`qualify-name`) produces a fresh, non-interned buffer on every
call, so an identity comparison would never match across two separate lookups
of the same qualified name. Retyping `scope-define`/`scope-lookup`'s `name`
param to `CStr` (14.3 batch 1) is therefore inert — verified with a
byte-identical `build/nucleusc.ll` diff. A stray same-commit comment at
`qualify-name` ("interned so scope-lookup's pointer-identity comparison
matches") is *also* stale for the same reason and should be read historically,
not as current behavior.

**The null-check trap generalizes beyond struct fields to any
null-checked parameter in the value's call chain.** `Sym.ir-name`/
`Method.ir-name` were kept `ptr` because *they* were null-checked; the same danger
recurs one hop away wherever a value **derived** from such a field flows
through a function that null-checks its own parameter with `=`/`!=` before
using it — the parameter's declared type governs that specific comparison's
lowering, independent of the field's type. Found the hard way in 14.3 batch 1:
`program-defn-record (irn:ptr …)` looked like a safe `CStr` retype (matching
the already-`CStr` `ProgDefn.ir-name` field it stores `irn` into) but the
function opens with `(when (= irn null) (return))` — a **parameter**
null-check, not a field one. Retyping `irn` to `CStr` turned that guard into
`strcmp(irn, null)`, segfaulting on *every* compile (the OLD boot's typecheck
of the new source can't catch this — it's a runtime behavior change, not a
type error, so `make` succeeds and the bug only surfaces at `make test`).
Audit a proposed field-matching retype by grepping the **parameter's own**
body for `(= name null)`/`(!= name null)`, not just the field's read sites.

**Correction (Stage 15 W5c): the `= null` half of this trap is FIXED — a
comparison against the `null` literal no longer lowers to `strcmp`.**
`emit-binop-vals` now suppresses the strcmp branch when either *operand node*
is the symbol `null` and the other operand is `is-ptr-repr` (W9 item 18
widened that gate from `is-ptr-like` so a function pointer qualifies too),
emitting the `icmp eq ptr` identity test instead. `strcmp(x, NULL)` is undefined behaviour
in C and segfaulted under glibc, so no correct program could depend on the old
lowering; the fix is strictly a bug fix. Consequence for the paragraph above:
`(when (= irn null) …)` in a `CStr`-typed parameter's body is now **safe**, and
a null-check alone is no longer a reason to keep a value `ptr`. This was found
while making a `CStr`-typed `defvar` spellable — `(defvar g:CStr null)` would
otherwise have compiled into a global whose only natural use crashed.

**Superseded by Stage 17 C7 (2026-08).** The identity substrate is no longer a
`ptr` you must not retype — it is `Symbol`, and `Symbol`'s `=` *is* pointer
identity, by definition rather than by everyone remembering. `Node.s`,
struct-field names, scope keys, `Sym.ir-name`/`Method.ir-name` and every path,
triple and JIT symbol are `Symbol` now. Read the paragraphs above historically:
they describe why the `ptr` substrate had to be left alone, and the answer the
stage reached was to give it a type that says what it is. What survives is the
narrower rule that a `StrView` is not NUL-terminated (see the lattice table at
the top of this section).

**Verifying a behavior-neutral type migration:** retyping `ptr`→`CStr` and
rewriting `(= (strcmp a b) 0)`→`(= a b)` is **byte-identical at the IR level**
(`CStr` lowers to `ptr`; the `=` emits the same `strcmp`+`icmp`). The NS-3
literal flip and NS-5 selective adoption are the same shape: target-aware
emission keeps the compiler's own `ptr`/`CStr`-context literals byte-identical
(the chameleon collapses to the bare pointer). The migration is provable:
snapshot `build/nucleusc.ll`, migrate, rebuild, `diff`. A non-zero diff is a
regression — most commonly a both-`ptr` comparison that lost its strcmp (a
`< call @strcmp` / `> icmp eq ptr` hunk) because neither operand ended up
`CStr`/`StrView`; fix by giving one side a `CStr` type. `make bootstrap`
(stage1==stage2) does **not** catch this (both stages share the change); the
before/after IR diff does.

## Member access is head position `(s 'field)`; `_get` is the bypass primitive

The `.` field-access special form was renamed **`_get`** (compiler-internal
primitive; `emit-field-get`) and ordinary code uses **head position `(s 'field)`**
instead (the callable-values `get` path: Struct-blanket intrinsic, byte-identical
GEP+load). The selector is **quoted** — see the next section. Stage 16 finished
the job: `.`, `.&`, `.set!`, `ptr-set!` and `aset!` are all gone (`get`, the
2-argument `addr-of`, and `set!` over a **place** replace them), but every one
stays **reserved** so a retired-form message carrying the replacement always
reaches the user. Two non-obvious hazards — both bit the `.`→head-position migration and are why `_get` still exists:

- **A user `get` method must read its own fields with `_get`, not head position.**
  `(self 'field)` inside a `(defn get … (self:ptr:T sel))` dispatches back into that
  same `get` method → infinite recursion → segfault. Use `(_get self 'field)` (direct,
  bypasses the override). Head position respects user `get` overrides; `_get` skips them.
- **A struct held in a variable named like a special form or macro collides.**
  `(cond 'field)` parses as the `cond` special form (special forms/macros are
  dispatched before scope lookup). Fix by renaming the variable (preferred) or using
  `(_get cond 'field)`. **Functions don't collide** — a local shadows them in scope
  lookup, so `(localvar 'field)` is member access even if a function shares the name.
  The one-time `.`→head-position migration special-cased reserved-named *direct*
  heads by routing them to `_get`; a reserved-named **`->` base** was not caught
  and had to be renamed.

**A field name is QUOTED; a bare symbol in selector position is a variable.**
`selector-literal-sym` (src/nucleusc.nuc) accepts `(quote sym)` and nothing else;
everything else is a computed selector. Selector position used to be the one
place in the language where a symbol was not a variable reference, and Stage 15's
W7 demotion (`callee-has-field` + `selector-shadowed-by-local`) and Stage 16's
`k:CStr` annotation hatch both existed to claw the value reading back; the flip
(`design/stage16-ergonomics/dot-forms.md` §5 step 3) deleted all three. Three
things that fall out of it, each of which had to be built:

- **`_get`, `.set!` and the 2-argument `addr-of` require a literal** and refuse a bare symbol rather
  than reading it as a variable — they name a field statically, so there is
  nothing for a computed selector to mean there (`die-nonliteral-selector`).
- **Head position and `get` route on the RECEIVER, not on the argument's shape.**
  `emit-callable-value` used to reach the member path only for a single
  literal-symbol argument; with the literal gone, `(p sel)` fell through to
  `emit-invoke-with-callee`. The gate is `is-member-access-receiver`
  (src/generics.nuc): a struct/union value or a pointer to one — the question
  `emit-get-intrinsic` actually asks. **Do not reuse `access-receiver-sdef`
  here**: it answers with a `StructDef` and so cannot speak for a `TY-UNION`.
- **An unbound bare symbol naming a real field is a missed quote**, not an
  undefined variable, and `emit-computed-field` says so with the spelling. That
  message is the whole migration story for a downstream tree.

**Selector position is no longer special, but the classifier still is.**
`selector-literal-sym` runs *before* anything emits, so a selector never reaches
`emit-symbol-ref` — the "one place a name becomes a value" that a value-position
feature is naturally built in. That is how Stage 16's `as` sugar landed and
`(m k:CStr)` still died with `no field 'k:CStr'` (as-sugar.md §11). Its saving
grace is that it is *shared*: emit (`emit-get-with-callee`) and node-type
(`callable-get-type`, generics.nuc) both call it, so the `node-type`↔`emit-node`
lockstep holds by construction. `is-member-access-receiver` is the same shape and
is called from both `emit-callable-value` and `callable-value-type` for the same
reason.

**A concrete type read as a TYVAR silently drops a whole instantiation.**
`tyname-resolvable` (src/generics.nuc) decides whether a symbol in a stamped
method's type pattern names a concrete type or a free type variable. Answer 0
for a concrete one and `collect-pattern-tyvars` collects it,
`defn-has-receiver-tyvars` returns 1, the stamp looks like an unmonomorphized
template, and **`emit-defn` skips its define** — while the call site still
references its ir-name. Nothing in the compiler complains: the symptom is
LLVM's own parser saying `use of undefined value '@count.pVector.Char'`, and
only for a program that reaches that instantiation.

It has drifted from `parse-type-name` four times (`__fnty_N`, `ptr:X`, `Char`,
and the `?`/`!` sigils — Stage 21 PK-4a, where a fake tyvar did not drop an
instantiation but *accepted every argument*: `(Vector i32)` bound the "tyvar"
`?Pt`). It now consults **`builtin-type-name`** — the probe that was extracted
FROM `parse-type-name` precisely to be asked without dying — rather than
`g-primitive-type-set`, which answers a different question (the
one-symbol-one-kind rule) and omits `Char`/`usize`/`ssize`/`raw`. When adding a
built-in type, `builtin-type-name` is the one list that matters here; adding it
only to `g-primitive-type-set` leaves generics over it silently broken. **Two
arms are still missing**: `deftype` aliases and C typedefs (both resolve in
`parse-type-name`, neither here), so a bare alias name in a template argument is
the same accept-anything shape — recorded in stage21-cleanup/overview.md.

**An arity overload still needs a `node-type` mirror.** `(addr-of x)` is a
binding's address and `(addr-of p 'f)` is a field's — one emitter, split on
`node-len`. `node-type-addr-of` has to split on the *same* arity or the 2-arg
form falls into the 1-arg path and types as `ptr:ptr:Point`, the address of the
BINDING. That is invisible in the value itself: it only surfaces where the type
is load-bearing (an argument position, an annotated binding), which is the
`node-type`↔`emit-node` lockstep at its least obvious. The mirror must also
reproduce emit's rules from the RAW field type — an array field decays to
`ptr:elem`, and wrapping `node-type-field`'s already-decayed answer gives
`ptr:ptr:elem`.

The `->` macro (`lib/macros.nuc`) was extended to substitute `_` in **head**
position (it scans the whole form, not just args), so a threaded value can land in
call position: `(-> s (_ 'field))` ⇒ `(s 'field)`.

## Head position is a VALUE position — a capture walk that skips it loses the receiver

`fn-capture-walk` and `fn-rewrite-captures` (`src/nucleusc.nuc`) used to skip a
form's head symbol, on the reasoning that it names a call or a special form. That
stopped being true when Stage 16 made `(s 'field)` the idiomatic member access:
the head is now the **receiver**, and the same holds for a callable value. Both
walk index 0 now — `is-local` (walk) and membership in `caps` (rewrite) are what
keep a call to a global from being read as a capture, so nothing else was needed.

The bug this closes is invisible to a grep: `(get p 'x)` inside a closure captured
`p` and `(p 'x)` did not, and `.set!` hid its half by walking its receiver
explicitly at index 1 — which the `set!` place form no longer does, because the
receiver moved into head position. Every member form the compiler *synthesizes*
has the same hazard; see the `quoted-selector` / `set-place-cell` helpers.

## A member place with a COMPUTED key is the `set` generic; a literal selector is always the field

`(set! (m k) v)` and `(set! (get m k) v)` become the ordinary call `(set m k v)`
when `k` is not a literal selector and the receiver's type has a `set` method
(`set-place-call`, `src/nucleusc.nuc`). A **literal** selector never dispatches,
and that is load-bearing, not a simplification: without it a collection that
defines `set` can no longer write its own fields — `(set! (self 'data) null)`
inside `Vector`'s `drop` dispatches back into the `set` method. It is the write
side of the `_get` recursion trap two sections up, and the rule is the split
`emit-get-with-callee` already makes (Branch A literal = member access, Branch B
computed = value-keyed dispatch).

Two consequences worth knowing:

- **The route is decided from `node-type`, not from an emitted Val.** The read
  path emits the receiver first because it has one consumer; a write has two (the
  generic call takes a value, the field write takes storage), so emitting to
  decide would emit the receiver twice.
- **`set-place-call` is the single route**, called by `emit-set-place` *and* by
  `node-type`'s `set!` branch, which types the place as `node-type` of the very
  cell emit builds. That is the lockstep this file opens with, discharged by
  having one answer rather than two that must agree.

`_get` never dispatches (it is the override bypass), and neither do the storage
places `(deref p)` / `(aref a i)`.

## Reading a struct value's field is direct; writing one needs a binding

Since Stage 16 SV-1 a struct **value** is a legal member-access receiver, so
`(get v 'f)`, head-position `(v 'f)`, and `(_get v 'f)` all work on a by-value
parameter, a `let`-bound struct local, or a call result read in place. The
emitter copies the value into a fresh slot (`materialize-struct-value`,
`src/nucleusc.nuc`) and `access-receiver-sdef` (`src/generics.nuc`) unwraps the
same receivers in the type pass — the cross-file lockstep this file opens with.

A member **place** (`(set! (v 'f) …)`) and the 2-argument `addr-of` are the
exception: they need the receiver's own **storage**, so they take exactly what
`addr-of` takes — a binding, whose slot they use directly. A temporary is an
error ("the receiver is a temporary struct value, so it has no address"), which
is also what stops a pointer into a compiler-made copy from being returned.

The older `(addr-of v)`-then-access shape (`lib/strview.nuc`,
`examples/comb-order.nuc:30`) is still correct and is how a member place on a
by-value parameter is spelled when the receiver is not already a name.

## Every `declare` emitter must ABI-lower exactly like the `define` — there are SIX, and three had silently drifted

A `declare` and the `define` it names are the same function seen from two
translation units, so a `declare` that prints raw `type-to-ir` for a by-value
struct parameter or return disagrees with the ABI-lowered `define` **on every
target** — not just riscv64. It is invisible until someone actually passes an
aggregate across the boundary, which is why it survived for stages.

Found while closing RV-6c, and fixed: `emit-nuch-defmethod-import`
(`src/nuch.nuc` — an imported *overloaded* method, distinct from
`emit-nuch-declare-import` right above it, which was always correct) and the
REPL's two preamble emitters (`src/repl.nuc` — the first-definition declare and
the global-redeclare loop). The repro is one library with two overloads, one
taking a struct by value: the define emitted `define i32 @area.Pt(i64 %p.arg)`
while the import emitted `declare i32 @area.Pt(%Pt)`.

The shape to copy is `emit-nuch-declare-import`: classify the return, print
`abi-ret-ir`, emit a `ptr sret(...) align N` first operand when the return is
ABI-MEMORY, then `abi-args-begin` + `abi-classify-arg` + `abi-print-param` per
parameter. Two traps in it:

- **Track a `need-comma` flag; do not test `j != 0` or `num-params != 0`.** An
  sret prefix already occupies the first operand slot, so at zero parameters a
  `num-params`-based separator drops the comma before a `...` and emits
  `(ptr sret(%T) align 8...)`. The REPL redeclare loop had exactly this shape.
- **`abi-print-param` hardcodes `g-out`.** The REPL preamble goes to
  `g-repl-preamble`, so it calls **`abi-print-param-to`** (the stream-parameterized
  body; `abi-print-param` is now the `g-out` wrapper over it). Either spelling
  works — `repl-declare-union-ctors` instead save/sets/restores `g-out` around
  its loop — but prefer `-to` for a new emitter: it cannot leak a swapped
  `g-out` down an early return.

**A fourth site was the same bug one layer down, and is also fixed**:
`emit-fn-thunk` (`src/repl.nuc`) built the redefinition trampoline's signature
from raw `type-to-ir`, so it disagreed with the impl's ABI-lowered `define`
*and* named a `%Pt` that `jit-thunk-module`'s standalone module never defined —
`use of undefined type named 'Pt'` before any declare mattered. By-value
structs did not work in the REPL at all. Two fixes, and the second is the
non-obvious one:

- The thunk forwards its parameters untouched to a callee with the identical
  lowered signature, so **the operand list is byte-for-byte the same in the
  signature and in the forwarded call** — build it once into a memstream and
  print it twice. `byval`/`sret` attributes are legal on a call operand, which
  is what makes the verbatim reuse correct for the MEMORY cases too. A MEMORY
  return lowers to `void` plus an sret operand, so it takes the same no-result
  path a genuinely `void` function does.
- `jit-thunk-module` now prepends **`g-repl-preamble`**, which is where the
  session's accumulated `%Name = type {…}` lines live (`repl-jit-module-rt-rewrite`
  already did this; the thunk module was the one module built without it).
  Only an sret/byval aggregate actually names a type — COERCE1/COERCE2 lower to
  `i64`/`double`/`<2 x float>` and need none — so this is invisible until a
  struct over 16 bytes crosses the REPL boundary. The preamble holds only types,
  `declare`s and `external global`s, so it cannot collide with the two symbols
  the thunk module defines.

`tests/repl/byval-structs.in` pins all three ABI classes plus redefinition.

## Argument-register state is AMBIENT: every parameter/argument walk must call `abi-args-begin` first

`abi-classify` was pure for its whole life, and on x86_64/aarch64/AVR it still
is — the lowering of a by-value struct depends only on its type. **riscv64
lp64d breaks that**: an FP-bearing aggregate is flattened into fa0-fa7 only
while the registers that rule needs are still free, and falls back to the
integer convention once they are not. So an *argument*'s classification depends
on every argument before it.

The split (Stage 14 RV-6c, `design/stage14/riscv-fp-abi.md` §4):

- **`abi-classify (t)`** — pure, all registers available. Correct for every
  non-riscv target and for **returns** everywhere (a0/a1/fa0/fa1 are always
  free, which is why a return never falls back).
- **`abi-classify-arg (t)`** — consults `g-abi-gpr-left`/`g-abi-fpr-left`/
  `g-abi-varargs` (declared beside `g-form-line`, `src/nucleusc.nuc`),
  classifies, and debits. On a non-riscv target it **tail-calls
  `abi-classify` and touches nothing**, which is the whole reason hosted IR
  stays byte-identical.

The invariant, which is the part that silently drifts:

> **Every walk over a function's parameter or argument list calls
> `abi-args-begin` first, then `abi-classify-arg` once per element in
> declaration order** — and `abi-args-varargs` when it crosses into the
> variadic tail.

There are seven such walks and they are *not* co-located: `emit-defn`'s
`define` signature loop, `emit-defn`'s prologue loop, `emit-call-with-args`,
`macro-jit-ensure-decl`, and the `.nuch` / C-header / REPL declare emitters.
Note two of them walk the **same** signature — a `define`'s parameter list and
its prologue are separate loops with the whole function body emitted between
them — and each resets independently; they agree because they see the same
types in the same order. Adding a new emitter that lowers parameters without
`abi-args-begin` inherits whatever budget the previous walk left behind, and on
a hosted target that is completely invisible.

Four generalisable points from implementing it:

- **The two functions that classify *internally* are where the invariant is
  easiest to get wrong.** `abi-emit-param-prologue` and `abi-arg-frag` call
  `abi-classify-arg` themselves, so it is their **caller's loop** that must
  call `abi-args-begin` — the reset does not live next to the classification.
- **Collapse redundant classification before making a classifier stateful.**
  Three sites classified the same entity twice (once for `info`, once for
  `kind`). That is merely wasteful against a pure function and *wrong* against
  a consuming one — it charges every struct argument twice. Fixed first, as a
  separate step.
- **A short-circuit return that skips classification still spends registers.**
  `abi-arg-frag`'s unmaterialized-StrView early return emits one pointer
  operand; it now calls `(abi-classify-arg ty-ptr)` purely for the debit.
  Classifying the StrView type there would have charged two GPRs for a
  fragment that passes one.
- **Record what the classifier decided; do not re-derive it.** `AbiInfo.rvfp`
  holds which flattening rule fired, so the consumer debits from the decision.
  The tempting alternative — `strcmp`-ing `reg0`/`reg1` against
  `"float"`/`"double"` — is a second copy of the rule, the exact shape
  `binop-result-type` exists to delete.

Verification without the hardware: there is no riscv64 machine in the
container, so the ABI evidence is a **clang comparison** — a header-free
reference `.c` (no `#include`: there is no riscv64 sysroot, so any include
fails) lowered with `clang --target=riscv64-unknown-linux-gnu -O0 -S
-emit-llvm`, diffed against the same shapes through
`nucleusc --target=riscv64-unknown-linux-gnu --emit-llvm`. That is what
`tests/fixtures/rv6-fp-abi.nuc` + the `rv6-*` units of
`tests/suite-target.nuc` pin permanently, together
with an x86_64 control asserting the same structs still lower as SysV. It is
**not** an execution gate; only a native `make abi-test` on riscv64 closes
that.

## Prefer overloads (polymorphism) over `-sv`/`-by-val`/`-from-x` name variants

Functions that perform the **same operation** and return the **same type** but
take differently-typed or differently-counted arguments should be **overloaded**
(multiple `defn`s with the same name), not given distinct names. Different
argument count is no barrier — Nucleus multimethods dispatch on arity and
per-argument type adaptation (`arg-adapts`) together. So `intern-string` has one
`(ptr, i32)` overload and one `(StrView)` overload — not `intern-string` +
`intern-string-sv`. A caller's argument tuple routes to the matching overload
automatically; the caller never chooses a suffix.

**When NOT to overload** (the extraordinary circumstances):

- An **unintended polymorphic match would be unsafe** — i.e., the operations are
  genuinely *different* despite similar names, and a caller's argument types
  could silently dispatch to the wrong one. (E.g., a `delete` that frees memory
  vs. a `delete` that clears a collection — overloading would be a footgun.)
- The function is on the **identity substrate** and the overloads would confuse
  pointer-identity dispatch (the `Node.s` trap, above).

Both exceptions are rare. When in doubt, overload — the diagnostic
(`"no matching method for overloaded '%s' with argument types (StrView, ptr)"`,
src/generics.nuc:arg-type-spellings) names the exact types the caller tried,
so a mismatch is immediately diagnosable.

**Dispatch adaptation rule** (the practical gotcha): in multimethod dispatch
(`arg-adapts`), a `StrView` argument adapts to a `CStr` parameter but **not** to
a bare `ptr` parameter (reproducing the pre-NS-3 dispatch). So an overload
intended for literal callers should type its string-consuming params `CStr`
(not bare `ptr`) when the argument will be a `StrView` literal — the `CStr`
typing admits both `CStr` and `StrView` callers via dispatch, while bare `ptr`
admits neither. (In *value* positions — `coerce-int-val` — a `StrView` literal
still coerces freely to `ptr` via the hidden-NUL collapse; the restriction is
dispatch-only.)

## C interop invariant

All Nucleus types must be representable in C. This is a core design requirement — Nucleus is a drop-in replacement for C, and any function or data structure defined in Nucleus must be consumable from C. If you encounter or are asked to create a type that cannot be represented as a C struct/function/enum (e.g. closures with hidden captured environments, tagged unions requiring runtime support), flag it as a design violation before proceeding.

## Stage 10 pointer-kind conversion gotchas (N2)

When converting a function or binding from `(ptr T)` to `(ref T)` / `?T`
(design/stage10/nullability.md §6), three recurring constraints:

- **`die-at` is not known to be noreturn.** A `(when (= x null) (die-at …))`
  guard does **not** narrow `x` past the guard — narrowing accumulates only
  when the guard body visibly terminates (`return`/`goto`). Restructure such
  sites to `(if-some (x m) then (die-at …))` instead. (A future `noreturn`
  attribute would make the guard idiom work as-is.)
- **Prelude types in `src/nucleusc.nuc` defn signatures work now** (stale
  constraint, removed 2026-07): `prescan-imported-types` (nucleusc.nuc, run for
  the outermost unit) names prelude types and the `!T` sugar before the
  signature prescan, so `ref:Node` / `ptr:Node` in a *signature* compiles —
  384 nucleusc.nuc signatures already name compiler-types structs, and
  `make-vec` has a parametric `(ref (Vector ptr))` return. The remaining
  gotcha is Phase-F semantics, not ordering: `ptr:T` is **non-null**, so a
  cursor walking a nullable link field (e.g. `Node.cdr`, typed `(raw Node)`)
  must itself be `(raw T)`, not `ptr:T`. Older `x:ptr` spellings justified by
  the prescan (e.g. the comment near `import-list-push`) are leftovers.
- **Mixed cond/if joins: bare-vs-typed absorbs, differently-typed still
  collapses.** `type-join` (src/generics.nuc, right after `type-eq`; called
  from `emit-cond`, `match`-over-unions, and the niche-match/if-some arm
  helper) is the single join-logic site. Joining a bare, elem-less `ptr`
  value with a `(ref T)`/`(ptr T)` value in a value-position `if`/`cond` now
  **absorbs** to `(raw T)` — the bare side is treated as the `void*` escape
  hatch, so the join takes the typed side's element type at pkind `PTR-RAW`
  unconditionally (never `pkind-meet`, since the elem-less side's claimed
  pkind is an unaudited Phase-F default). Joining two pointers with
  **different, both-typed element types** (`(raw Node)` vs `i32`, two
  distinct struct types) still collapses the phi to `void` — that remains a
  real type error; if the result is used, you get a malformed-IR clang error
  or a flow-check error. Fix that case by giving the other branch's binding
  its real element type — never by casting the typed side back to bare
  `ptr`. Design:
  [stage14/macro-conditional-casts.md](../design/stage14/macro-conditional-casts.md).

## `(Maybe ptr)` is niche-encoded — `match` works, but the representation is a bare pointer

When the element type of `Maybe` is a pointer kind (`TY-PTR`), the compiler
niche-encodes `(Maybe ptr:T)` as a nullable pointer (no tag word, null = none).
`match` works on niche-encoded Maybe: `(match m ((some p) ...) (none ...))`
branches on a null test and binds `p` as `(ref T)` in the `some` arm. The
alternatives `if-some`/`when-some`/`unwrap`/`unwrap-or` also work and may be
more concise for simple cases.

They work **only** there. `emit-if-some` requires `PTR-MAYBE` and says so
(*"value must be `(Maybe (ref ...))` — launder a raw pointer with `(as-ref ...)`"*),
so a *value* `Maybe` over a non-pointer `T` — what `(get m k)` returns for a
`(HashMap Symbol i64)` — has `match` as its only eliminator. The cheap way out is
usually to make the map's value type a `(ref …)`: `(HashMap Symbol (ref CMacro))`
keeps `when-some` and hands back the whole record instead of one field.

## `(import-use X)` in a file named `X.nuc` silently imports nothing

The compilation unit's ROOT file is on none of the import lists (see the rule of
that name above), so an `(import-use process)` inside a file called
`process.nuc` resolves to the file itself and the real `lib/process.nuc` is never
loaded. Every name from the module then goes missing, and the diagnostic is
accurate but reads like a bug in the module:

    error: unknown type: Command — not defined anywhere in this compilation unit
      note: 'Command' is defined in lib/process.nuc, which no import in this unit reaches

Found writing `examples/process.nuc` for Stage 19; the example is
`examples/subprocess.nuc` for this reason alone. **Never name a file after a
module it imports** — and when a "no import reaches it" note names a module you
demonstrably imported, check the root file's basename first.

## `Vector`'s `drop` frees the array and does NOT drop the elements

`(defn drop ((self (ptr (Vector T)))))` in `lib/vector.nuc` frees the element
buffer through the allocator handle and zeroes the header. It never calls `drop`
on an element, so a `(Vector String)`, `(Vector File)` or any other vector of
owning values leaks one heap buffer per element unless the owner walks it first.

Stage 19's `Command` sidesteps it rather than paying it: arguments accumulate
NUL-terminated into one `String` with a `(Vector usize)` of offsets, which is one
allocation, needs no element walk, and keeps the argv pointers stable.

## `(Result (Maybe T) Err)` does not compile for a struct `T`

Both spellings fail. The `:!(Maybe ExitStatus)` sugar does not parse — *"unknown
type: "* against an empty name — and the explicit list form
`(defn f (…) (Result (Maybe ExitStatus) Err)` compiles the body but rejects the
construction: `(ok m)` where `m:(Maybe ExitStatus)` gives *"type mismatch for a
field of arm 'ok'"*, and an unannotated `(ok (some st))` resolves `some` to the
pointer-niche variant instead (*"value must be non-null (ref …)"*) because the
`ok` wrapper carries no want channel inward.

Return something flatter until this is fixed. Stage 19's `process-try-wait`
returns `!bool` with the status parked on the receiver
(`design/stage19-process/overview.md` §8.1).

## A template stamp loses the pointer KIND — `(Result (raw T) E)` is `(Result (ref T) E)`

`union-template-stamp-types-in` / `struct-template-stamp-types-in`
(`src/union-registry.nuc`) substitute each argument by its `type-spelling`, and
`type-spelling` (`src/type-mangle.nuc`) spells every `TY-PTR` as `ptr:elem`
regardless of `pkind`. So `(Result (raw Node) ReadError)`, `(Result (raw Node)
i32)` and `(Maybe (raw Node))` all stamp a `ref` payload and refuse `null` at
construction (*"raw pointer where non-null (ref ...) is required"*). `!raw:Node`
works only because the two-arm `Err` shape takes the ERRPTR niche, whose
constructor is lenient. Found by Stage 21 R-1: the memo key is
`type-mangle-token` (`pNode` for both kinds), so the first stamp of either kind
answers for both — do not "fix" `type-spelling` locally; every stamped `pkind`
in `src/` moves with it (it belongs with the pointer-kind item).

Until then, a raw payload in a sum with a non-`Err` error arm is a **named**
union with the same arms — `(defunion ReadResult (ok v:raw:Node) (err
e:ReadError))` in `lib/read.nuc` — which `try`/`unwrap`/`match` treat exactly
like a `Result` because `result-union-of` is structural.

Two smaller traps from the same work: a two-element **call** in a positional
struct-literal slot, `(S a (f x))`, is read by `emit-struct-lit` as a designated
`(field value)` initializer (*"struct literal: no field 'f'"*) — construct through a
plain function instead; and a `defcast` whose `From` is a struct used to emit the
conversion call with the aggregate passed first-class, which a 16-byte struct
survived by register coincidence and a larger one segfaulted on — `coerce-via-cast-rule`
now goes through `abi-arg-frag`/`abi-emit-struct-call` like every other call.

## `macros.nuc` is auto-imported — adding macros shifts the string pool

`lib/macros.nuc` is transitively auto-imported into **every** compilation
including the compiler itself (via `lib/prelude.nuc`). Adding new macro
definitions (with quasiquote string literals like `"let"`, `"i32"`, etc.) shifts
the compiler's internal string pool numbering. This causes a spurious bootstrap
diff that has nothing to do with correctness. Convergence requires two passes:
1. `make update-bootstrap` — install the new compiler binary as the new boot artifact
2. `make clean && make` — rebuild from the new boot so stage1 == stage2
Then `make bootstrap` passes. The `make bootstrap` target diffs stage1 vs stage2,
not the new binary vs old boot.

## `(Vector ptr)` iteration with combinators

All compiler registries are `(Vector ptr)`. The element type `ptr` causes
`(Maybe ptr)` niche-encoding. Combinators like `doseq`, `for-each`, `find`,
`any?`, `every?`, and `reduce` that use `(match (next it) …)` internally now
work correctly over `(VecIter ptr)` since niche-encoded Maybe supports `match`.

For `(Vector ptr)` loops in `src/` compiler code, `dotimes` remains the
idiomatic choice for simple iterations, but combinators are now viable.

For Node* linked-list loops (AST cdr-lists): `ListIter` yields `ptr` directly
since niche-encoded `(Maybe ptr)` is now matchable. Recover each element with
`(cast ptr:Node elem)`.

## `dotimes` conversion gotchas (R3 compiler-loop refactor)

A trap recurs when converting a counted `(let (i:i32 0) (while (< i n) … (inc! i)))`
to `(dotimes (i:i32 n) …)` in `src/` compiler code:

   **A trailing `(return X)` must land OUTSIDE the dotimes body.** For a find-shape
   loop ending `(return FOUND)` after the scan with `(return NOTFOUND)` after the
   loop, close the dotimes on the `(return FOUND)` line and put `(return NOTFOUND)`
   on its own line after. If you close one paren too few, `(return NOTFOUND)` lands
   *inside* the dotimes body and the function returns NOTFOUND on the first
   non-matching iteration — silently breaking every lookup (hit `generic-binds-for`,
   `lbl-find`, `enumdef-lookup` during R3). The textual-IR signature is a missing
   `inc!`/`br-loop-back` immediately before a spurious `ret`.

A same-shape swap (zero start, unit stride, `inc!` last) expands to byte-identical
IR — no `make update-bootstrap` needed. Loops starting at non-zero, with non-unit
stride, or with `inc!` not last do **not** fit `dotimes`; leave them imperative.
`return` inside a `dotimes` body works (it expands to a `while`), so early-return
find loops convert fine — just mind the gotcha.

## Prefer `with` to `let` followed by `free`

```lisp
(let (n:usize (sv len)
      buf:ptr:ui8 (cast ptr:ui8 (malloc (cast i64 (+ n (cast usize 1))))))
; ...
    (free (cast ptr buf)))
```

is simpler and more reliable as 

```lisp
(with (n:usize (sv len)
       buf:ptr:ui8 (cast ptr:ui8 (malloc (cast i64 (+ n (cast usize 1))))))
; ...
    )
```

## A `let` should never be the only child of a `let` (same for `with`)

Merge the binding lists. Both forms bind **sequentially** — a later binding sees
every earlier one — so a nested level buys nothing and costs indentation:

```lisp
(let (coll-ty:ptr (lit-list2 …))                    ; not
  (let (decl:ptr (lit-list2 gs coll-ty line))
    (let (bindings:ptr (lit-list2 decl alloca line))
      …)))

(let (coll-ty:ptr (lit-list2 …)                     ; but
      decl:ptr (lit-list2 gs coll-ty line)
      bindings:ptr (lit-list2 decl alloca line))
  …)
```

When flattening an existing stack the hazard is the **body**, not the bindings:
every level being collapsed may carry trailing forms after its inner `let`, and
all of them have to survive into the single merged body. Losing them is not a
type error — a `!T` function that falls off the end still compiles.
`read-vector-literal` and `read-hashset-literal` (then two separate functions
in `src/reader.nuc`, now one shared `rd-lit-elems` in `lib/read.nuc`) were
flattened correctly and lost their `(return (ok …))` tails, which surfaced as
`'()' is not an expression` reported against the *caller's* source line.

## Avoid untyped pointers

Passing around untyped pointers and using casts is unsafe and must be reserved as an escape hatch, not standard practice. When using a cast, **always** check whether it's possible to change the design so that all values are well-typed.

## A special-form spelling sweep must also grep for `intern-symbol "…"` synthesis, not just literal text

A tree-wide rewrite of a special-form spelling (the Stage 14 `cast`→`as`/`unsafe/cast` split, UN-3/UN-4/UN-5) can miss sites where the compiler *programmatically* builds an AST node headed by the old spelling via `(intern-symbol "cast")` + `make-cell`, rather than writing `(cast …)` as literal source text. A `grep -n '(cast '` sweep is blind to these — the head symbol only exists as a string argument to `intern-symbol`. Found in UN-5: `fn-make-drop-method` (src/nucleusc.nuc, the cfn env-drop synthesizer) built a `(cast (raw ui8) self)` pointer reinterpret and a `(cast usize 8)` alignment literal this way; both survived the UN-3/UN-4 sweeps undetected and would have died the moment UN-5 retired the bare spelling (every with-bound closure with an owned env synthesizes a drop method through this path). When retiring or renaming a special-form spelling, also grep `intern-symbol "<old-name>"` (and check any other AST-synthesizing helper — lambda lift, closure invoke/drop, defunion arm ctors, type-erasure forwarding methods, per the `defn` synthesizer list above) before declaring the sweep complete.

## Top-level macro expansion happens in the dispatcher's DEFAULT arm — so it is invisible to every prescan

Stage 18 TF-4 gave the top-level dispatcher (`emit-toplevel-forms`' `case hp` in `src/nucleusc.nuc`) a macro path, which it had never had: `toplevel-expand-macro` is called from the `case`'s **default** arm only — where the head is already unknown to the compiler — expands to fixpoint, `desugar-form`s the result, rewrites the list cell in place, and returns 1 so the loop re-dispatches the same cell without advancing. `(do …)` splices its children as separate top-level forms, copying the spine rather than relinking the expansion's own cells (a `quote` template hands out a shared subtree). Two consequences worth knowing before designing around it:

- **Nothing else moved.** Because expansion is attempted only where the old code died, every built-in form still wins its own name, and a program that never wrote a top-level macro call emits the same bytes. This is the property that made the change safe to land inside a phase; do not "simplify" it by expanding before the `case`.
- **The prescans never see the result.** `prescan-defn-signatures`, `prescan-struct-layouts` and the rest run over the form list *before* the loop, so a macro-produced definition is not forward-referenceable, and a macro cannot emit an `extend` together with the methods that satisfy it — the conformance check reads the prescanned method registry, whatever order the `do` splices in. Moving expansion ahead of the prescans means JIT-compiling `defmacro` bodies (and resolving their imports) before any other top-level form: a front-end staging change, deferred as stage18-tooling §T9.7.

The pre-TF-4 note here said top-level sugar had to be a compiler directive (`fn-attr`-shaped: a `g-special-form-set` entry + a `case hp` arm + an `emit-<name>`). That is still the answer when the sugar must be visible to a prescan, or must reuse a built-in head; a `defmacro` is now the answer when neither applies — which is what `deftest` (`lib/test.nuc`) is.

## A diagnostic's notes already live in its MESSAGE — split there, do not re-plumb 688 call sites

`die-at` (662 sites) and `report-at` (26) take a line and a message. Stage 18 TF-5 needed a `Diagnostic` record with a separate `notes` field, and the cheap way in was not to change any of them: **twenty-odd diagnosing sites already build their note into the message** as `(fstr "…" "\n  note: " …)`, and two more are ambient globals sampled at render time (`g-mono-context`, `g-diag-note`). `diag-build` (`src/diagnostics.nuc`) splits on that exact nine-byte marker, so the record gains a real field and the text back-end is the rejoin — i.e. the identity, byte for byte.

That identity is what makes the change gateable, and the gate is not a new test: **172 `run_reject_at` units already assert their exact diagnostic text**, so any drift in the split/rejoin pair fails there. Anything that changes how a diagnostic is assembled should be measured against `make test` first and only then reasoned about.

Two rules that fall out and are easy to get wrong:

- **A note printed AFTER the call is not a field.** Three sites did exactly that (`report-unterminated`, the stray-`)` note in `read-form`, the preprocessor's sysroot advice) because `die-at` is `:noreturn` and there is no "and also" after it. They stage the note first with `diag-stage-note`, which **appends** rather than overwrites — a site that clobbers `g-diag-note` silently drops whatever another site had to say about the same error.
- **One diagnostic is one line** in `--diagnostics=sexp`, because the writer escapes every newline inside a string. That invariant is load-bearing on the reader side: `read-diagnostics` (`lib/test.nuc`) skips any line that is not a diagnostic, which it must, since the `clang -E` a C-header import shells out to writes its own text to the same stream. Do not add a sexp field that can span lines.

A message with no source location (a toolchain message, not one about the user's file) passes `line` -1: the text back-end omits the `path:line: ` prefix, the sexp one writes `(file "")` and `(line -1)`. Absence is spelled, never omitted — a reader that has to ask whether a key is present is a reader that will get it wrong.

## Scanning an LLVM datalayout string for a token requires boundary checks, not a bare substring search

A datalayout is a `-`-separated token list (e.g. `e-p:64:64-...-P1-...`). Extracting a segment like `P<n>` (AVR's program-address-space marker) by searching for the literal substring `"P"` is wrong — it can match inside an unrelated token that merely contains a `P` character elsewhere (or at a different position), not just at a token boundary. `datalayout-prog-as` (src/nucleusc.nuc, added for Stage 14 AVR-6's `prog-as:i32` field on `Target`) scans for a `P` that is *either at the start of the string or immediately preceded by `-`*, then parses the following digits — a token-bounded scan, not `strstr`. Reuse this pattern (or the helper itself) for any future datalayout field extraction (e.g. a future `n8:16:32:64` native-integer-widths scan) rather than re-deriving a bare substring search that happens to pass on today's known triples.

## A "materialize as a first-class value" diagnostic needs a chokepoint audit, not just the obvious one

When gating a language feature that's only unsafe when a *value* (as opposed to a direct call/access) is produced — the Stage 14 AVR-6 example is functions living in AVR's addrspace(1), which cannot be represented as a plain data pointer — there is rarely exactly one emission site. `emit-symbol-ref`'s `TY-FN` branch is the obvious chokepoint (a bare function name used where a value is expected), but AVR-6 found a second, independent path: a lambda-lifted closure boxed into `BoxedFn`/`dyn` reaches vtable construction (`ensure-vtable-for`, `ensure-fnfwd-vtable`) *without* going through `emit-symbol-ref` at all — the vtable itself, not a symbol reference, is what materializes the function as data. Both had to carry the same `avr-reject-fn-value` check. When adding a compile-time guard for "value production of X is unsafe here," grep every place X's *machine representation* is constructed (not just the most direct/obvious call site) before declaring the guard complete — boxing/vtable/closure-lifting machinery is a common second path that bypasses the primary one.

## `g-target-triple` is not swapped for JIT sub-compilation — any single-target compile-time check needs an explicit `in-jit-module` guard

`g-target-triple` is a raw string global set once from `--target=` (or defaulted to the host triple) and read by target-identity predicates like `abi-is-avr`/`abi-is-aarch64` (src/abi.nuc). It is a *different* thing from the `g-target`/`g-host-target` `Target` descriptors: when codegen redirects into a macro/`compile-time`-JIT sub-module (`g-decl-out` swapped away from `g-decl-stream` — this is exactly what `in-jit-module` tests, `src/scope.nuc`), the JIT module's own `target triple`/datalayout IR lines are correctly sourced from `g-host-target` (the JIT always runs on the host process), but `g-target-triple` itself is **never touched** by that swap — it keeps reading whatever the outer `--target=` set, e.g. `"avr"`, even while a macro body's ordinary host-side arithmetic is being compiled to run on the host.

Found in Stage 14 AVR-7: `avr-reject-f64` (src/abi.nuc) checks `abi-is-avr` (itself gated on `g-target-triple`) to reject `f64` when compiling an AVR *program*. Without also checking `(= (in-jit-module) 0)`, the same check would misfire on a `compile-time`/`defmacro` body's ordinary `f64` math while compiling an AVR target program — that host-side JIT sub-compilation still sees `g-target-triple == "avr"`, even though it emits into a host-triple module and runs in-process on the host.

**When adding a compile-time diagnostic (or any target-conditional codegen choice) keyed on `g-target-triple` or a predicate built on it, always AND in `(= (in-jit-module) 0)`** unless the check is genuinely target-triple-driven pure IR-shape logic that's supposed to apply inside JIT modules too (e.g. `ptr-int-ir`, which correctly wants the *active* module's pointer width, not the outer target's). The distinguishing question: does this check describe "what target program will eventually run" (needs the `in-jit-module` guard — it should only fire for the real target module) or "what module is being emitted right now" (does not — `g-host-target`/`g-target` already track that correctly without help)?

## A triple-keyed **toolchain** default must ask whether the build is CROSS, not just what arch the target names

`g-target-triple` answers "what machine will this code run on". It does **not**
answer "is an external tool needed to get there", and a default that shells out
to a *host-installed program* — a link driver, an assembler, an objcopy — is
asking the second question. `compile-and-link`'s riscv64 branch conflated them:
it selected `riscv64-linux-gnu-gcc` on any `riscv64`-prefixed target triple,
which is right when cross-compiling (the Debian cross toolchain carries the
sysroot + crt objects that `clang` would need an explicit `--sysroot` for) and
wrong on riscv64 **hardware**, where the sysroot is `/` and the hosted `clang`
default links with no flag at all. `g-target-triple` defaults to
`LLVMGetDefaultTargetTriple`, so a native riscv64 build reaches the branch with
no `--target=` in sight.

Two things make this class hard to notice:

- **It fails only off-host, so no gate here can see it.** On an x86_64 container
  the guard's condition is structurally constant, so the corrected branch is
  unreachable and the bug's *symptom* is unreachable too. `make riscv-test`
  SKIPping on a container gap is not evidence either way. Reason about the
  predicate, not the test result.
- **A wrong toolchain name can work by accident on the machine you'd first try
  it on.** Debian's *native* gcc package ships the triplet-prefixed spelling
  (`/usr/bin/x86_64-linux-gnu-gcc -> x86_64-linux-gnu-gcc-14` on this
  container), so native Debian riscv64 would have linked fine and "confirmed"
  the default; Fedora/Alpine/Arch riscv64 ship no such binary. A distro-specific
  naming convention that happens to hold on the reference distro is exactly the
  assumption a triple prefix hides.

The fix shape: bind the host arch from `((as ptr:Target g-host-target) triple)`
and gate the cross-tool selection on `(and (target-is-X) (= host-is-X 0))`,
comparing **arch prefixes** rather than whole triples — `riscv64-unknown-linux-gnu`
and `riscv64-linux-gnu` name the same machine, and a `strcmp` would call a native
build cross. Note this is the *complement* of the `in-jit-module` rule above:
there the question was "which module am I emitting right now", here it is "which
machine is running the tool I am about to exec". Both are questions
`g-target-triple` alone cannot answer. AVR needs no such guard — it is never a
host, so its `host-is-avr` is identically 0 and the conjunct would be dead code;
add the guard when the target is one a developer could plausibly *be sitting on*.

The same split belongs in any test lane for such a target: pick cross-vs-native
from `uname -m`, and in the native lane pass **no** `--linker` override, so the
compiler's own guarded default stays the single source of truth instead of being
re-derived in shell (`tests/run-riscv-test.sh` / `run-riscv-abi-test.sh`).

## A cross-emission test must name **both** triples explicitly — the omitted one is the host, and the gate silently becomes a host assertion

The same "a triple is not a host" confusion recurs in the test harness, where it
is easier to miss because the test *passes* on the machine it was written on.

The RV-6 gate (`tests/suite-target.nuc`) compares riscv64 lowering against x86_64
SysV lowering of the same fixture — an anti-leak control proving the riscv
flattening rules did not reach the SysV path. The riscv lane named its triple;
the x86_64 lane ran bare `--emit-llvm` and rode the default target. On x86_64
that is x86_64 and the gate passes, so nothing flagged it for the whole of RV-6.
On riscv64 hardware the default target is riscv64, so the "SysV" lane was
compiled with the riscv rules and the gate reported **correct** riscv lowering as
a leak: `FAIL rv6-x86-unchanged`, dumping `{ float, float }` where it wanted
`<2 x float>`. A green suite on one host was not evidence the gate was sound.

**Rule: in any test that asserts target-specific IR shape, the triple is the
thing under test and must never be ambient.** Pass `--target=` on every lane,
including the one that happens to match your host. `target-init` makes this
airtight — with `--target=` set, `g-target` comes from
`make-target-for-triple g-target-triple-override` and the host descriptor is
never consulted, so both lanes are host-independent by construction. Backend
availability for the extra triple is already gated separately by
`run_target_triple`, so an explicit triple costs nothing.

Deliberately left alone: `run_avr7_struct`'s host lane (asserting
`define i16 @sum(i32 `) genuinely means "AVR versus whatever host this is" —
contrast with the *real* host is its claim, so pinning a triple would change what
it proves. It holds on riscv64 today because a 4-byte FP-free struct takes the
integer convention and lowers to `i32` there too. If riscv-fp-abi.md §8's
integer-convention spelling divergence is ever resolved toward clang's `i64`,
that lane breaks on riscv64 only — the contrast is the point, so fix it then by
asserting "not a plain `ptr`" rather than a literal lowered type.

## A top-level definer's own NAME position is never desugared — the "silent misregistration" bug generalizes across every definer

`desugar` only rewrites binding *positions* it explicitly lists (the `defn` name and param list, `defvar`/`extern`/`declare` names, `defstruct` fields, `let`/`with` binding names — see the `defn` bodies note above); a top-level definer's own name (`defconst`/`defenum`/`defprotocol`/`defmacro`/`defunion`/`deferror`) is not on that list. So a colon-typed spelling on one of these names (`(defconst K:i32 2)`) arrives as a single undesugared `NODE-SYM` whose spelling is *literally* `"K:i32"`, and unless the definer's emitter explicitly rejects it, it registers under that literal, unlookupable key — no diagnostic at the definition, and a disconnected failure (or nothing at all) wherever the name is actually used. Stage 15 W4b found this exact bug independently in `defconst`, `defenum`, `defprotocol`, `defmacro`, `defunion`, and `deferror` — six definers, one root cause. The fix is `reject-colon-in-def-name` (`src/nucleusc.nuc`, beside `split-typed`): call it first, before any other dispatch on the name (including a definer's own CELL/template-head check), in any top-level definer whose name is never legitimately annotated.

The colon-*paren* fused shape (`K:(i32)` → the reader's `fuse-colon-paren` producing the CELL `(K (i32))`) needs a **definer-specific** check instead of a shared one, because `defstruct`/`defprotocol`/`defunion` have a *legitimate* CELL name — a parametric template head (`(Vector T)`, `(Seq E)`, `(Wrap T)`). The distinguishing test: a genuine template's extra elements are always bare symbols (tyvar names); the fused-annotation shape's second element is itself a nested CELL (the read paren-form). So the check is "exactly one extra element, and it's a CELL, not a SYM" — never "any CELL name", which would misfire on every real template. `defconst`/`defenum`/`defmacro`/`deferror` have no template concept at all, so for them any CELL name is unconditionally the fused-annotation mistake.

If a **new** top-level definer is added in the future, give its own name the same treatment from day one — don't wait for a user to trip over the silent-misregistration shape first.

## A C header's type names are NOT visible to `prescan-defn-signatures` by default

Two prescans run per unit, in this order, **before any `(import …)` form is
processed**: `prescan-imported-types` (walks the import tree and registers
imported *Nucleus* struct names) and then `prescan-defn-signatures` (resolves
every `defn` signature's parameter and return types). `prescan-imported-types`
deliberately **skips C-string imports** (`(import-use "stdio.h")`) — reading one
means shelling out to `clang -E`. So a C header type named in a `defn`
**signature** cannot resolve from import-time registration, no matter what the
import registers: the signature was resolved first. A type named only inside a
function **body** is fine (bodies are emitted after the import).

Stage 15 W3a closes this for the cheader path with `cheader-prescan-opaque`
(`src/cheader.nuc`), hooked into `prescan-imported-types`' new NODE-STR branch.
It is a deliberate **name-only** scan (`cheader-scan-opaque-decl`), not a second
parse, and it registers *exactly* the names the real import will define — the tag
of `struct Tag …`, the declarator of `typedef struct [Tag] {…} Name;`. That
equality is load-bearing: the real import then finds those entries and upgrades
them **in place**, emitting the same single `%X = type {…}` it always did. Register
a *different* name (e.g. also the tag of a `typedef struct Tag {…} Name;`) and the
upgrade defines a second LLVM type that no existing program had — the IR is no
longer byte-identical. If you extend the pre-scan, keep it name-for-name with
`c-parse-struct-decl`.

## A C header is preprocessed once per import — `cheader-preprocess` caches by path

`clang -E -x c -include <path> /dev/null` takes no other input, so its output is a
pure function of the path; but a C header import is deliberately **not**
deduplicated (each import may alias under a different prefix), so a header was
re-preprocessed for every `(import-use "<path>")` naming it. `cheader-preprocess`
(`src/cheader.nuc`) caches the text by path, reusing a Node cell as the record
(`s` = path, `car` = buffer, `i` = length) the way the import lists do.

The trap this exposed, worth generalizing: **`emit-c-include` used to end with
`(free buf)`.** Correct while each call owned a fresh buffer; a use-after-free the
moment the buffer is shared. It did not crash — it presented as a **hang**, the
declaration parser looping over garbage — and only on the **second** import of the
same header, so no single-header test could see it. When you make a
previously-per-call resource shared, grep the old owner for `free`.

## Opaque (layout-less) types: `StructDef.opaque`, cleared at the layout chokepoint

A C forward declaration (`struct Foo;`, `typedef struct Foo Foo;`) registers a
`StructDef` whose **name** is known and whose **layout** is not (`opaque:i32` = 1,
Stage 15 W3a). Three rules keep this coherent:

- **`opaque` is cleared in `struct-set-fields`** (`src/abi.nuc`), not at the call
  sites. That is the single chokepoint every field-populating path funnels through
  (`emit-defstruct`, the `.nuch` import, the cheader body parser, the anon
  struct/union memoizer, the closure-env and fatptr builders), so "acquires a
  layout" and "stops being opaque" cannot drift apart.
- **`c-parse-type` must keep returning `ty-ptr` for an opaque tag.** Its
  `lookup-struct` on a `struct Tag` base is reached *only* for a **by-value**
  `struct Tag` in a C parameter/return/field position, and it returned `ty-ptr` for
  an *unregistered* tag. Once opaque tags exist, letting that branch produce a
  `TY-STRUCT` emits `declare void @f(%Tag)` for a `%Tag` that has no definition —
  trading a wrong-ABI pointer for invalid IR. Converting those declarations into a
  skip-with-warning is W3b's validity gate, not something to improvise here.
- **Refuse by-value use at the site, and keep a `type-to-ir` backstop.**
  `reject-opaque-type` / `opaque-sdef-of` live in `src/type-utils.nuc` (not beside
  `register-struct` in `abi.nuc`: `type-to-ir` is in type-utils, and a call from
  there up into abi.nuc is an unresolved cross-import forward reference — the same
  wall SM-5 documents). Six explicit call sites carry a real line
  (`emit-sizeof`, `emit-alloca-form`, `emit-field-get`, `emit-get-intrinsic`,
  `emit-defn` params + return, `emit-defstruct` fields); the `type-to-ir`
  TY-STRUCT/TY-UNION backstop uses the ambient `g-form-line` and catches
  everything else, so an undefined `%Foo` can never reach an IR stream and become
  an LLVM parse error thousands of lines away. Never substitute a size.

## A C struct is opaque at the GLOBAL prescan, so `(array Tag N)` is refused in a `defvar` only

`prescan-defvar-name` resolves a `defvar`'s type **before** any `(import-use
"header.h")` is read, so the only registration under a C tag at that moment is
the layout-less placeholder `cheader-prescan-opaque` puts there — and
`parse-type-from-node`'s array branch calls `reject-opaque-type` on the element.
The result is a diagnostic that reads like a compiler bug because it contradicts
what the same file can do a line later:

```lisp
(defvar bufs:(array __jmp_buf_tag 16))   ; error: array element: '__jmp_buf_tag' is an opaque type
(defvar env:jmp_buf)                     ; fine — a C TYPEDEF, re-resolved by emit-defvar
(defstruct H xs:(array __jmp_buf_tag 4)) ; fine — the layout prescan (mode 3) DEFERS instead
(alloca (array __jmp_buf_tag 16))        ; fine — a body, emitted after the import
(sizeof __jmp_buf_tag)                   ; fine — 200, same reason
```

The rule: **a by-value C aggregate is usable everywhere except a global's own
type.** Storage for one belongs in a frame (`alloca`) or on the heap; if you
need it to outlive a call, keep a global array of *pointers* and let each frame
allocate its own. Stage 16's `repl-protect` does exactly that, and the shape is
better than the static array it replaced — the jump buffer lives in the frame the
`longjmp` returns into, and the stack needs no target-dependent extent
(`design/stage16-ergonomics/c-header-layout.md` §11.2).

## `desugar-typed` needs the enclosing form's line (the interned-symbol line-0 class, again)

`desugar-symbol`/`split-colon-segments` stamp the cells they build with a line
handed in by the caller. `desugar-typed` used to pass `(n line)` from the node
being desugared — but that node is a **colon-typed binding name**, i.e. an
interned `NODE-SYM`, whose line is always 0. Every desugared `(name (ptr T))`
binding cell therefore carried line 0, and every diagnostic raised off a `defn`
parameter, a `defvar`/`extern`/`declare` name, a `defstruct` field, or a
`let`/`with` binding name reported `:0:`. `desugar-typed` / `desugar-params` /
`desugar-let-bindings` now take an `encl:i32` fallback (Stage 15 W3a) filled from
the enclosing form (`(f line)` in `desugar-form`, the binding-list cell in
`desugar-params`), applied with `node-line`.

The sibling half: **`prescan-defn-signatures` resolved a signature's types against
`((ptr:Node name-node) line)` — the defn's own NAME** — which is the same
interned-symbol-line-0 shape one level up. It now borrows the return operand's
line, falling back to the defn form's. When a *registration/prescan* phase raises
a diagnostic, check what node it is blaming: a definer's name is never a usable
line source.

## `MAX-STRUCTS` scales with imported header size, not program size

`MAX-STRUCTS` (`src/compiler-types.nuc`) is a runaway-growth guard on `g-structs`
(a `Vector`, so it is not a preallocation). It used to bound roughly "types this
program defines"; since W3a registers every C header type name it bounds "types
every imported header names". Measured: `SDL2/SDL.h` + `SDL2/SDL_mixer.h` +
`png.h` in one unit needs between 200 and 256 slots — the old 256 was one umbrella
header from breaking. Now 1024.

## A dangling `true` clause is the tell for a `cond` that closed one paren early

`cond` clauses are `test body test body …`. If an extra `)` closes the `cond`
after an earlier clause, the remaining `test`/`body` pairs become **sibling
statements** of the `cond`: the stray `true` is a bare no-op expression (no
warning — `true` is a perfectly good statement), and each remaining body runs
**unconditionally**, right after whichever branch the truncated `cond` took. The
program still compiles, still passes its tests, and is subtly wrong in a way that
does not look like a control-flow bug.

Found in Stage 15 W3b: `emit-c-include`'s top-level two-way dispatch
(`struct`/`union`/`typedef` → the type-declaration parser, else → the
function-declaration parser) had been a fall-through since `6ef16dc Add union
types`, so a function parse ran after *every* type declaration, starting at
whatever whitespace the type parse had stopped on. Symptoms were indirect: a
header-import warning reported the *preceding* declaration's line, and two
consecutive `struct Foo;` forward declarations lost the second. Neither looks
like "the cond is broken".

Two habits that catch it: (1) treat a `true` clause whose body is at a different
paren depth from its siblings as suspect — run a depth counter over the form
rather than eyeballing the closers; (2) when a location or an ordering is "off by
a bit" but the computation that produced it checks out, verify the *caller's*
control flow before re-deriving the computation. In W3b the line arithmetic
(`cheader-line-at`) was correct the whole time; the position handed to it was
produced by a branch that should never have run.

## The C typedef table resolves at RECORD time — which is what makes chains and cycles free

`c-parse-typedef-decl` (`src/cheader.nuc`, Stage 15 W3c) records a non-aggregate
`typedef` into `g-cheader-typedefs` — a `CTypedef` list (name, the
**already-resolved** `Type*`, header file/line, a `provisional` bit) that lives
in **`src/type-utils.nuc`**, not beside its writer: since Stage 16 L5 the table
is read by `parse-type-name` / `type-name-collision` (union-registry.nuc) and
`unknown-type-message` (nucleusc.nuc), all of which are processed before
`(import-use cheader)`. Same cross-import wall the W3a opaque helpers sit behind.
Resolving at the point the `typedef` is parsed — rather than walking the chain at
each use — buys two properties that are easy to lose if someone "simplifies" it
into a lazy walk:

- **A chain costs one lookup.** `off_t` → `__off_t` → `long int` is collapsed
  when `off_t` is recorded, because `__off_t` was recorded first.
- **A cycle is impossible by construction.** A name can only ever resolve
  against entries recorded strictly *before* it (the preprocessed text is
  scanned in order and a C file-scope typedef is visible from its declaration
  onward), so a malformed `typedef foo foo;` records `foo` as unrepresentable
  instead of looping forever. There is no cycle check, and none is needed.

`c-parse-typedef-decl` is reached from `emit-c-include`'s dispatch **only after
`c-parse-struct-decl` declines**, which is what keeps W3a's opaque
registration/upgrade paths untouched: every `typedef struct|union …` shape that
introduces a named aggregate is handled there and can never reach the scalar
path. A record whose `ty` is null means "real C type name, no Nucleus
representation" and is deliberately distinct from an *absent* record.

**Stage 16 L5 added a third state, and it is the one to get right.** A `defn`
signature and a `defvar` type are resolved by prescans that run *before* any
import, so `cheader-prescan-opaque` now runs the real typedef parser too — with
every C struct still opaque. Those records are **provisional**: the real import
overwrites them whatever it concludes (first-wins would freeze
`typedef __sigset_t sigset_t;` as unrepresentable and silently skip every
declaration using it). Two rules follow. The prescan must **decline any specifier
run reaching `struct`/`union`** — `c-parse-type` would parse the body and write a
`%X = type` line, and a prescan has no module stream open. And a **provisional
null must not produce the "cannot represent" diagnostic**: in that window the
compiler cannot tell "no representation" from "not resolved yet", so it falls
back to the pre-L5 `unknown type` wording rather than making a false claim.

Two adjacent parser facts, both found because the table is useless without them:
**`enum` was not a declaration specifier at all** (so `enum Tag e` read `enum` as
the base type and `Tag` as the declarator name — the identical phantom-parameter
shape W3b found for east qualifiers), and **`__extension__` was not consumed at
top level**, which hid glibc's entire `__quad_t` family (`__extension__ typedef
long long int __quad_t;`). When adding a C declaration-specifier keyword, check
both the specifier loop in `c-parse-type` *and* the top-level dispatch in
`emit-c-include`.

**`size_t`/`ssize_t` are intercepted BY NAME in `c-type-to-nucleus`, on
purpose — but at the emission target's width.** Letting `<stddef.h>`'s own
typedef win would make the width follow whatever machine the preprocessor read
headers for, and since Stage 16 C4 that is *usually* the target but falls back
to the host when the target's headers are not installed. The name interception
is the part that must stay; the hardcoded 64 it used to carry did not, and is
now the target's pointer size.

## `clang -E` reads the TARGET's headers, and folds none of their `sizeof`s

Two independent halves, and Stage 16 C4 needed both. `cheader-preprocess`
(`src/cheader.nuc`) passes `--target=<triple>` (and `--sysroot=` when given) to
`clang -E` whenever the emission target is not the host, which decides *which
header text* is read. It does **not** decide how that text's constant
expressions are evaluated: the preprocessor leaves `sizeof` alone, and the
array-extent evaluator folds it itself from `abi-sizeof` over the Nucleus `Type`
the C parser built. So the C type mapping has to be target-correct in its own
right, or `char buf[sizeof(void*) * 4]` is sized for the wrong machine even
though the right header was read. `c-int-type` (`int`, and a C enum, are 16 bits
where a pointer is 2), `target-long-size` (`<= 4`, not `= 4` — AVR's pointer is
2 and its `long` is 4) and the `size_t`/`ssize_t` interception above are the
three that carry it.

**The flags must be EMPTY on a host build, not merely equivalent.** They are
gated on the target triple differing from `((as ptr:Target g-host-target)
triple)`, so an unflagged compile runs the byte-identical command line it always
did. Passing the host's own triple explicitly happens to be safe on Linux and is
not portably safe (Darwin's SDK detection is entangled with the default target),
and "no flags" is a property you can assert; "the same output" is one you have to
re-measure per platform.

**Making the target's headers authoritative makes their ABSENCE reachable.** On
a machine with only the host's libc headers — which is the normal case, and this
container for every triple except AVR — the targeted `clang -E` fails. Refusing
there would retire cross-compiling for every such triple, including every
`--target=` lane in `make test` and `make windows-boot`. So the policy is retry
on the host and **warn**: the pre-C4 behaviour, announced instead of silent. A
header that exists on no search path at all is fatal and located.

**A subprocess's exit status is part of its output.** `read-pipe-output` ignored
`pclose`'s status for the whole of the parser's life, so a `clang -E` that failed
returned its built-in preamble, which parsed as an empty header — every name the
header declared then went missing with nothing pointing at the import. Cache the
failure the same way you cache the text (a null buffer in the same record), or
the pre-scan and the real import each print the diagnosis. This tightening also
surfaces a latent class: **a string import not ending in `.nuc`/`.nuch` routes to
the C-header path**, so `(import "prelude")` had always been a silent no-op.

## An unreachable code path is not a correct one — two cheader defects that only became reachable in W3c

Both were pre-existing and both were invisible for as long as an unfollowed
typedef resolved to `ptr`. The general lesson: when you fix a coercion or
resolution that used to collapse everything to one type, re-audit every consumer
that *never saw the other types*.

- **`c-parse-func-decl` never applied the aggregate C ABI.** It printed the raw
  `type-to-ir` of each parameter and the return, unlike `emit-nuch-declare-import`
  and `emit-defn`, which route through `abi-classify`. Harmless only because
  glibc names every by-value aggregate through a typedef and every typedef was
  `ptr` — so the C-header path had *literally never* emitted a struct by value.
  With chains followed, `div`/`ldiv`/`lldiv`/`fopencookie` appear and a raw
  `%div_t` in a `declare` disagrees with the ABI the call site already lowers.
  Now routed through `abi-classify`/`abi-ret-ir`/`abi-print-param`; for a scalar
  or pointer these reduce to `type-to-ir`, so the text is byte-identical.
- **The cheader path never set `StructDef.emitted`.** `cheader-struct-define` /
  `cheader-adopt-shape` write their `%X = type {…}` line straight to
  `g-type-stream` rather than through `emit-struct-ir-type`, and `emitted` is
  exactly what `pending-union-deps-ready` consults before writing a queued union
  whose field names that struct. SDL's `SDL_WindowShapeParams` (a union with an
  `SDL_Color` member) was therefore deferred on **every** drain and never
  defined, while `%SDL_WindowShapeMode`, which contains it, referenced it —
  `use of undefined type`. If you add a fourth place that writes a struct type
  line directly, set `emitted` there too.

## An import-time warning's volume is a function of what the compiler can currently detect

W3b made every skipped C declaration an always-on stderr warning and justified
it with a measured volume of **zero**. That measurement was an artifact of the
§1.4 defect: while every unfollowed typedef resolved to `ptr`, nothing *could*
be detected. The moment W3c followed the chains, `(import-use "SDL2/SDL.h")`
produced **165** genuinely unrepresentable by-value declarations (149
`long double`, 7 `_Float128`, 6 `SDL_JoystickGUID`, 2 `SDL_GUID`, 1
`_Float16`) — six of them in the REPL's startup banner and six in every `make`
of the compiler itself.

The resolution is a two-tier policy worth reusing for any "we could not import
X" diagnostic:

- **Loud at the point of discovery** when the *compiler* failed (a parse it
  could not do). These are potentially fixable in the compiler and stay
  always-on with W3b's wording and dedup.
- **Recorded, and reported at the point of USE**, when the *language* has no
  equivalent. `g-cheader-skipped` (declared in `src/nucleusc.nuc`'s globals
  block, above `unresolved-name-message`, for ordering) holds a pre-formatted
  `"<header>:<line>: <reason>"` per function name; `unresolved-name-message`
  checks it before the did-you-mean and emits
  `unknown: 'strtold' — its C header declaration was skipped (…)`. This is
  strictly *more* precise than a warning: same header, line and reason, but
  attached to the call site instead of appearing thousands of lines earlier
  with nothing connecting it to the use.

Before assuming "always on costs nothing", ask what the measurement was
*conditioned on*.

## Declaration precedence: suppressing the loser is not enough — the winner must be emitted where the loser was

Stage 15 W3c's rule is "an explicit `(declare …)` beats a C header's
declaration of the same function, in either order". Order-independence comes
from `prescan-explicit-declares` (`src/cheader.nuc`, called from
`emit-toplevel-forms` beside the other prescans, so it runs before *any* import
of that unit), and the header's copy is then never registered and never emitted —
LLVM rejects a second `declare` for the same symbol **even when the two agree**.

The trap: simply dropping the header's copy leaves the name **undefined between
the import and the explicit declare's own position**. Measured —
`examples/cstr-lit-test.nuc` declares `strlen` at line 15, and `lib/arena.nuc`
calls it from inside the prelude import that precedes it, so suppression alone
broke that build with `unknown: strlen`. The fix is to emit the explicit
declaration *at the point of first need*
(`cheader-yield-to-explicit-declare`, `src/nucleusc.nuc`); its own form later
becomes an idempotent no-op because `emit-nuch-declare-import` already returns
early for a registered name. Generalize: whenever a later definition is made to
win over an earlier one in a single-pass compiler, the winner has to be *hoisted*
to the loser's position, not merely preferred.

Two placement notes. **`cheader-yield-to-explicit-declare` lives in
`nucleusc.nuc`, below both `(import-use cheader)` and `(import-use nuch)`,
because cheader.nuc is imported one line above nuch.nuc and therefore cannot
name `emit-nuch-declare-import`** — the ordinal prescan rule again. cheader.nuc
reaches back into it fine, since `prescan-defn-signatures` registers every
nucleusc.nuc signature before the first form of any import is emitted. And
signatures are compared by their **rendered `declare` text** (`c-fn-sig-render`),
never `type-eq`: `type-eq` treats any two `TY-FN` as equal, and the rendering is
what the diagnostic has to show anyway.

## Skipping is a legitimate outcome for an imported C declaration — but only for what is *invalid*, not what is merely *wrong*

`c-decl-skip-reason` (`src/cheader.nuc`, Stage 15 W3b) gates every synthesized
`declare` from a C header: a by-value struct/union with no known layout, a
recorded `void` parameter, an opaque parameter/return type, or an arity over
`C-MAX-PARAMS` are skipped with `<header>:<line>: warning: skipping C
declaration '<name>': <reason>` instead of emitted. This converts "header X
explodes at `failed to parse generated IR` thousands of lines later" into "header
X's function Y was skipped", which is diagnosable and survivable.

Three properties are load-bearing:

- **The gate runs only after the declaration was *recognized* as a function.**
  The `c-parse-func-decl`-returns-0 path stays silent: every typedef, variable,
  `static inline` body and macro remnant in a preprocessed header goes through it
  legitimately, and warning there buries the signal completely.
- **It cannot see a wrong-but-representable declaration, and must not try.** The
  corollary from W3b's own finding: `void f(int const *p)` importing as the
  two-parameter `(i32, ptr)` was invisible to *any* gate, which is why the parse
  fix, not the gate, was the deliverable. (W3b also recorded that the spec's
  "unresolved type names" arm was unimplementable *because* an unfollowed typedef
  resolved to `ptr`. W3c removed that objection at the source — see the typedef
  table note above — so the arm now exists: a by-value parameter or return whose
  base type cannot be resolved marks the declaration through the same
  `g-cheader-unrep` channel. A *pointer* to an unresolvable type is deliberately
  still `ptr`; every C pointer is one machine word.)
- **Warnings are deduplicated by function name.** A C header import is
  deliberately not deduplicated (each import may alias under a different prefix)
  and umbrella headers include each other transitively, so without the dedup
  (`g-cheader-skipped`, a Node-cell string list) one skipped function warns many
  times per build.

Measured volume of the **loud** arms remains **zero** across stdio, stdlib,
string, unistd, fcntl, math, time, sys/stat, pthread, netinet/in, signal, png,
`SDL2/SDL.h` and `SDL2/SDL_mixer.h`. W3c's arm is reported at the point of use
instead (see "An import-time warning's volume…" above) — that measurement was
conditioned on the §1.4 defect and did not survive it.

## C type qualifiers are legal *after* the base type too (`int const *p`)

A C declaration-specifier sequence admits `const`/`volatile`/`restrict`/`_Atomic`
**anywhere**, and each `*` admits its own run of them. `int const *p` and
`const int *p` denote the same type. Nucleus models none of this and emits the
same LLVM type either way, so `c-skip-type-quals` (`src/cheader.nuc`) consumes
and discards a qualifier run at every legal position — after the specifier loop
and after each `*` — rather than representing it.

The failure mode when a position is missed is worth remembering because it is
*not* a parse error: the qualifier token gets consumed as the **declarator name**
and the rest of the declarator (`*p`) starts a phantom **next parameter**. So a
one-parameter function silently imports as a two-parameter one with a fabricated
trailing `ptr`. Only the `void` base spelling produces IR LLVM rejects; every
other base produces a representable, wrong-ABI declaration that nothing
downstream can detect. When extending the C declarator grammar, test the emitted
`declare` line's **arity**, not merely that the header compiled.

## A "no annotation here" null is a *decision point*, not a default

`extract-name-and-type` returns null for **any** node that carries no
`name:type` annotation — which includes every legitimate bare *type* spelling.
A caller that treats that null as "untyped, assume `i32`" silently mistypes
every spelling the grammar deliberately allows. Stage 15's `declare` fix is the
worked example: `emit-nuch-declare-import` (`src/nuch.nuc`) wrote `ty-i32` on
null, so `(declare f (i64 ptr ui32):i64)` emitted `declare i64 @f(i32, i32,
i32)` — wrong for every parameter, and *correct exactly when the signature was
all-`i32`*, which is why it survived years of use including the compiler's own
`(declare repl_print_f64 (ptr):void)` (retired with the C shim in 2026-08-30). Each caller must decide what the null
means for its form and act on it: `emit-fn` dies (`fn: missing :type on param`),
`declare` now parses the node as a **type operand** (`declare-param-type`),
`defn` still defaults. When you add a caller, pick deliberately — and prefer an
error or a parse over a default, because a default is undiagnosable by
construction.

Two corollaries from the same fix:

- **Route an unparsed type operand through `parse-type-name` /
  `parse-type-from-node` and you get a located diagnostic for free**
  (`unknown type: X` / `unable to parse type expression`). Do not hand-roll a
  "known types" check beside them.
- **Desugar erases the name-vs-type distinction in a parameter list.**
  `desugar-params` splits every colon symbol, so an unnamed `ptr:FILE` and a
  named `p:ptr:FILE` both reach the emitter as cells (`(ptr FILE)` /
  `(p (ptr FILE))`). Distinguishing them at emit time would mean asking *what
  the head names* — C's typedef ambiguity, with a keyword list to keep in sync
  with `parse-type-from-node`, and it would silently retype a generated `.nuch`
  for the legal `(defn addone (ptr:i32):i32 …)`. So in a `declare`, an annotated
  element is a **named parameter** and `(declare f (ptr:FILE):void)` means a
  parameter *named* `ptr` of type `FILE`. Bare `ptr` is the unnamed-pointer
  spelling; a typed pointer parameter is named.

## A tree-wide grep for a spelling misses the programs a test writes

Test programs are not all files. The suite writes whole `.nuc` consumers inline
— once as shell heredocs, now as Nucleus string literals in `tests/suite-*.nuc`
— so a `grep -r` over `*.nuc`/`*.nuch` reports the spelling as *source text in a
test*, or, if the grep is scoped to definitions, as nothing at all. Stage 15's
`declare` fix hit exactly this: a scan concluded nothing used `:rest` in a
`declare`, and `make test` then failed five assertions in the `n6` / `sm3` / `s1`
`.nuch` link-and-run consumers, all three of which generate
`(declare printf (fmt:CStr :rest args:i32) :i32)` on the fly. Grep the suite
modules themselves before concluding a spelling is unused — or just treat
`make test` as the authority, which is what it is.

Worth knowing alongside it: **call arity is not checked against a
declaration.** `(declare printf (fmt:CStr):i32)` followed by
`(printf "a=%d b=%d\n" 42 26)` emits
`call i32 @printf(ptr %t0, i32 42, i32 26)` — the call site's own signature
governs codegen, so extra arguments ride through. That is how the three
harness sites call a C variadic without a variadic-`declare` spelling (Nucleus
has none), and it is why the `:rest` marker they used was contributing nothing
but phantom parameters.

## The deferred type queue has a contract: a `%Name = type {…}` line may not name a type that is not already in the buffer

`g-pending-unions` + `pending-union-deps-ready` + `drain-pending-union-irs`
(`src/union-registry.nuc`) exist because a parametric instance can be *stamped*
long before the `defstruct` its fields name has been processed. The contract is
narrow and easy to state: **`sdef-in-module` means "this type's definition is
already in the module currently being assembled", and a type's line enters the
buffer only once every named type it references is there.** Every module
assembly point (batch flush, `emit-compile-time`, the macro JIT, the REPL) drains
first, so a type deferred at one drain lands at a later one. (Stage 16 R4 split
that question out of `StructDef.emitted`, which now means only "this type has a
definition at all" — see "A latch is a claim about a buffer" below.)

**Any path that writes a type line outside the queue must re-establish that
contract itself, and one did not.** `defunion-register` wrote a union's backing
struct `%X = type { i32, %__anon_union_… }` with a bare `fprintf` and set
`emitted = 1`, while the anon payload union it names was `conj`'d onto the queue
one line earlier with `emitted = 0`. When the payload is a scalar (`!i32`,
`!ptr`, `!raw:Node` — every use in the compiler's own source) the union is ready
at the very next drain and the window is empty. When the payload is a **struct**
(`!String`), the union waits for `%String`, which arrives with a later import —
and every module assembled in between carries `%X`'s reference to an undefined
`%__anon_union_…`. That is an LLVM *parse* error inside a `compile-time`/
`defmacro` JIT module, reported against `lib/macros.nuc:11` (the first macro
compiled), which points nowhere near the cause.

Two things to carry forward:

- **The window is a function of when the stamp happens, not of the program.** The
  defect sat latent from the day struct payloads became stampable and only needed
  `(compile-time …)` written *before* the import that defines the payload struct
  to fire. Stage 15 W1a moved every imported file's signature prescan to before
  any emission, which turned an empty window into a build-wide one and broke
  eleven examples at once. When you move *when* a registration happens, audit
  every eager write that registration can reach.
- **Defer only when the eager write would dangle.** The fix queues the backing
  struct exactly when its payload union is present, unemitted, and not
  deps-ready; otherwise it keeps the `fprintf`. That matters for the bootstrap:
  the queued renderer (`emit-pending-struct-ir-type`) produces
  character-identical text, but *position* in the type buffer is observable, so
  unconditionally deferring would have reordered every `%Result.*` line in the
  compiler's own IR for no benefit.

## Front-loading a prescan reorders the type section — and that is the whole `make bootstrap` diff

Stage 15 W1a registers every reachable file's defn signatures before any form is
emitted. Signature resolution *stamps* parametric instances, and a stamp is what
queues the instance's `%Name = type {…}` line — so front-loading the prescan
front-loads those lines. The compiler's own `make bootstrap` diff was **44 lines,
all of them type definitions moving within the type section**; sorting the
type-definition lines in both files made them byte-identical, and zero
`declare`/`define`/string-table/function-body lines differed. LLVM named struct
types are order-independent within a module, so the move is inert.

The technique generalizes and is worth reaching for before assuming a diff is a
regression: **normalize the two `.ll`s by sorting the class of lines you believe
moved, and diff again.** If the normalized files match, the *set* is unchanged
and only order moved; if they do not, you have a real behavioural change. Pair it
with the direct self-consistency check `context/build.md` describes (compile
`src/nucleusc.nuc` with `build/nucleusc`, link that, recompile, diff the two IRs
— they must be identical), which tells you the new compiler is a fixed point
independently of what the committed boot does.

## An import cycle is legal — and the line between "resolves" and "does not" is *emission*

Stage 15 W1d: `do-import` **skips** a re-entry of a path already on `g-importing`
instead of erroring (`note-import-cycle` + `return`, at both the `NODE-SYM` and
the `NODE-STR`-`.nuc`-path branch). The skipped path is deliberately **not**
pushed onto `g-imported` — that list means *finished*, and its
`[start-len, end-len)` slice is what a later prefixed import replays.

The rule that predicts every remaining failure: **a cycle member's body is
emitted before the rest of the file it back-imports**, so anything that file
defines after its own `import` form has not run yet. Therefore:

- **Signatures survive** (W1a registers them graph-wide before any emission), so
  function calls in both directions resolve. This is the whole feature.
- **`(sizeof S)` and `(alloca S)` survive** — measured, and it contradicts what
  the design doc predicted. They lower to a GEP/`alloca` over the LLVM *named*
  type, and LLVM resolves `%S` from the `%S = type {…}` line emitted later in the
  same module. A named struct type may be forward-referenced in textual IR. Do
  not "fix" these; a rejection there is a false diagnostic.
- **Anything reading the compiler's OWN field table or `abi-sizeof` DOES, since
  Stage 15 W9 item 40** — `prescan-struct-layouts` / `prescan-union-layouts`
  register every reachable file's field table before any form is emitted, so
  field get/set/address, struct literals, by-value fields and by-value
  parameters/returns/arguments all work across a cycle. The last of those had
  been a *silent miscompile*: `abi-classify` sized the unlaid-out struct at 0 and
  emitted `define i32 @f(i0 %v.arg)` against a call site passing two `i64`s,
  whose only symptom was an unlocated `failed to parse generated IR`. What is
  left for `reject-cycle-pending-layout` is the one layout a prescan cannot
  settle: an `(array T N)` field whose extent is a macro-expanded expression.
- **Macros, `deferror` ids and `extern` declarations do not** (registered by
  their emitters), and **`prefix/name` aliases do not** (no slice for a skipped
  re-entry). Note the bare `(import foo)` spelling *is* the prefixed one, so a
  cycle written that way always suppresses an alias set; it is harmless only
  because the language's rule is that a cross-file reference needs no
  qualification.
- **`defconst`/`defenum` members and `defvar` globals DO, since Stage 15 W8
  G-0** — `prescan-value-names` registers them on the same whole-graph walk that
  registers signatures, so all three compile, link and return the right value
  across a cycle. This retired two pinning tests
  (`w1d-cycle-defconst-diagnosed`, `w1d-cycle-defenum-diagnosed`) and one clause
  of `cycle-definer-message`'s note. The *scan* behind it
  (`text-defines-name`) is deliberately still broad — it is shared with W1c's
  unreachable-definer note, which needs every definer.

Two implementation notes worth reusing:

- **`abi-classify` (`src/abi.nuc`) is the single chokepoint for by-value struct
  ABI** — `emit-defn`, the `declare` emitter, `emit-call-with-args` and
  `emit-return`/`emit-struct-ret` all funnel through it. One check there covers
  the definition side *and* the call side. Sites with a real node still check
  first (`emit-defn` params/return) so the message gets an exact line rather
  than the ambient `g-form-line`.
- **`StructDef.laid-out`, not `emitted` and not `num-fields`, is "has a
  layout".** `emitted` answered it only while emission was the one thing that
  produced a layout; W9 item 40's prescan lays a struct out and writes no IR, so
  the two questions separated and the bit is set by `struct-set-fields`, the
  single chokepoint every field-populating path funnels through. (`num-fields`
  was never the right test either — a legitimate `(defstruct Empty)` has zero
  fields after a real layout.) `sdef-layout-pending` /
  `reject-cycle-pending-layout` / `reject-cycle-pending-sdef` live in
  `src/type-utils.nuc` beside `reject-opaque-type` and mirror its site list —
  `type-utils` precedes `abi` in the import order, so `abi.nuc` can call them
  but not vice versa.

Everything W1d added is gated on `g-import-cycles != null`, which is why
`make bootstrap` was byte-identical on the first pass and an old-vs-new
`--emit-llvm` sweep over `examples/` + `lib/` was 168/168 identical: a cycle was
a hard error before, so no *compiling* program can reach any of it.

**Fixed by W9 item 40:** the same `i0` miscompile was reachable *without* a
cycle — `(defn f (v:S) …)` textually before `(defstruct S …)` in one file — since
`prescan-struct-names` registered the name and emission filled the layout later.
It is the same defect as the cycle one and it fell to the same fix, which is why
the layout prescan was not scoped to cycles: neither shape is about imports.

## Signature registration is NOT idempotent — a second prescan of one file is a duplicate-overload error

`generic-register-method` (`src/generics.nuc`) appends a `Method` to the named
`Generic` unconditionally: no keying on name+arity, no "same defn node" check, no
identical-registration short-circuit. `generic-add-method` then sets
`finalized = 0` (deliberately — so a later unit's overloads re-mangle an
already-finalized generic). So running `prescan-defn-signatures` twice over the
same forms registers every signature twice and the next `finalize-generics`
raises `duplicate method signature for overloaded '<name>'` against the file's
own definitions.

Consequence for anything that pre-registers a file's signatures ahead of its real
processing (Stage 15 W1a's whole-graph walk is the first such thing): the guard
has to be a **per-path skip**, never a relaxation of the duplicate check — the
duplicate check is what still catches two *different* files defining the same
name+arity. `g-prescan-sigs` (`src/nucleusc.nuc`, beside `g-prescan-visited`)
holds the prescanned paths and `emit-toplevel-forms` samples it against
`g-source-path` before the walk runs. Note the skip must still call
`finalize-generics` at the point `prescan-defn-signatures` would have, or a
generic that gained methods from a `.nuch` `defmethod` import or a REPL
redefinition mangles at a different moment than before.

**But the VALUE half of the same walk is idempotent, and that asymmetry is the
whole design of W8 G-0.** `prescan-value-names` (`src/nucleusc.nuc`, beside
`prescan-defn-signatures`) registers `defvar` / `defconst` / `defenum` names into
`g-globals` through `scope-define`, which **appends** while `scope-lookup` scans
**backwards** — so a second definition of an identical binding is inert and the
emitter's own registration simply wins. G-0 therefore needs *no* per-path skip of
its own (it rides the existing `g-prescan-sigs` guard) and, crucially, relaxes no
duplicate check: two `defvar`s of one name still emit two `@g = global` lines and
LLVM still rejects them. Before assuming a registry needs a dedup guard, check
which of the two shapes it has — `generic-register-method` appends *methods* and
`finalize-generics` then compares them, `scope-define` appends *bindings* and
`scope-lookup` never compares. Only the first is order-sensitive.

(Two things the value pass deliberately does **not** front-load, both because
they are emission-time state rather than a name binding: the `deferror` id table,
whose dense ids are allocated in emission order, and `g-enumdefs`, which `match`
exhaustiveness reads and which is capped at `MAX-ENUMS`.)

**Front-loading a definition makes every "is this name already taken?" check
able to see the definer's OWN registration — so such a check must classify the
Sym precisely, not approximately.** G-0 shipped with exactly this bug and it took
a separate session to find: `name-existing-kind` (`src/nucleusc.nuc`) called any
global `Sym` carrying a `TY-FN` type *a function*, which was harmless while only
`emit-defn` could produce one — and became "`'h' already names a function`" for
`(defvar h:(fn i32)(i32) …)` the moment `prescan-defvar-name` defined that Sym
before `emit-defvar`'s `guard-name-kind` ran. The `defvar` collided with itself.
The fix is the discriminator the rest of the compiler already uses:
**`is-local` 0 + `TY-FN` is a function; `is-local` 1 + `TY-FN` is a
fn-pointer-typed value** — `emit-dispatch`'s "a defn/extern symbol (is-local 0,
TY-FN) is a direct call" is the same two-conjunct test, and every
function-registering path (`emit-defn`, `emit-extern`'s sibling in
`emit-nuch-declare-import`, the C-header path, `finalize-generics`) passes 0
while `emit-defvar`/`prescan-defvar-name` pass 1. Generalize: when you move a
registration earlier, grep for every predicate that *reads* that registry and
ask whether it can now see the form's own entry — an approximate classifier that
was only ever asked about other people's Syms starts being asked about the
caller's.

The reason this one was cheap to fix safely is worth copying too:
`name-existing-kind` has exactly **one** caller (`guard-name-kind`) whose only
effect is `die-at`. So no *compiling* program can observe a change to its return
value — the blast radius is exactly "which programs are rejected", which is what
made a one-conjunct edit provable rather than merely plausible. Check that shape
(one caller, raise-only) before assuming a classifier edit needs a bootstrap
reconverge.

**Front-loading also SPLITS one question into two, and the second one needs its
own state.** Before G-0, "does this name resolve?" and "has its definition been
processed yet?" were the same event — a forward name simply did not resolve.
After it they are independent, and any check that wants the *second* one must
ask for it explicitly; asking resolution produces a check that fires on nothing.
W8 G-4's initializer-ordering diagnostic is the worked example, and its
mechanism costs nothing because **the double registration is already there**:
`prescan-value-names` defines the Sym, `emit-defvar` defines a second one for
the same key, `scope-define` appends and `scope-lookup` scans backwards — so
marking the two differently (`Sym.defvar-state`, DECLARED vs REACHED) makes the
state a *reference* sees flip at exactly the moment the definition is emitted,
with no new registry and no ordering bookkeeping.

Two things about that shape generalize:

- **Put the state on the registry ENTRY, never in a side list of pointers.**
  `scope-define` grows a scope by `arena-alloc` + `memcpy` into a *new* array,
  so a `Sym*` captured before a growth points into the stale buffer — a
  membership test by pointer identity is silently wrong for any unit big enough
  to grow the global scope, i.e. all of them. A field travels with the `memcpy`;
  read it off a *fresh* `scope-lookup`.
- **Let the zero value mean "not my business".** `defvar-state` 0 covers a
  function, an `extern`, a `.nuch`-imported global and a `defconst` member all
  at once, so they are outside the rule by construction instead of by an
  exclusion list the next definer-kind would have to be added to.

And when you add such a field, check the one-caller/raise-only shape above: G-4's
has exactly one reader, on a dying path, which is what made a new `Sym` field
provably unable to move any emitted IR.

Three collaborators of that walk, each a trap on its own:

- **`.nuch` headers must be excluded.** `emit-nuch-import-forms` deliberately
  does *not* run `prescan-defn-signatures`; a header's entries arrive as
  `declare` / `defmethod` / template-`defn` forms with their own registration
  paths, so prescanning one would double-register through a different door.
- **A path already on `g-imported` must be skipped.** The REPL processes one
  import per command, so a later command's walk can reach a file the session
  already loaded and whose signatures are therefore already registered.
- **Namespaces are not optional in a prescan.** `scope-define` qualifies a
  global's key against `g-current-ns`, and `generic-new` snapshots that
  namespace's ir-prefix into `Generic.ir-prefix` for `finalize-generics` to bake
  into the solitary method's `@name`. A walk that prescans a namespaced file
  under the *importer's* namespace registers it under an unlookupable key and
  mangles it under the wrong prefix. Copy `do-import`'s save/restore of
  `g-current-ns`/`g-ns-seen` (start at `user`, apply the file's own leading
  `(ns …)` and `set-ir-prefix`, restore after).

## A `declare` matching a reachable `defn` is a no-op because of one `scope-lookup`

`emit-nuch-declare-import` (`src/nuch.nuc`) opens with
`(when (!= (scope-lookup g-globals fname) null) (return))`. That single line is
what makes `(declare f (i32):i32)` beside — or across a file boundary from — a
real `(defn f (n:i32):i32 …)` a complete no-op rather than a duplicate
registration *and* a duplicate LLVM `declare` (which LLVM rejects even when the
two agree). It is why the `declare`-as-cycle-breaker idiom works, and why Stage
15 W1a needed no new compatible-prototype check: registering every reachable
signature graph-wide makes the early return fire *more* often, not less.

The edge it does not cover, unchanged and untested: the guard keys on the **bare
name** in `g-globals`, and an *overloaded* (mangled) generic has no bare-name
scope entry — so a `declare` naming an overloaded function would still register a
bare `Sym` alongside the generic. Know it before you touch this path.

## The solitary-vs-mangled decision is read at `emit-defn` time — so it must be final before the first `define`

`emit-defn` computes its `@symbol` from `defn-ir-name`, which asks the generic
registry *at that moment* whether the name is mangled; `finalize-generics` makes
that call from the method set registered so far. Under the pre-Stage-15-W1a
ordinal rule a file could therefore be emitted **before** a later import
registered a second method of the same name: the definition went out as the
solitary `@append`, the generic then became mangled, and every call site emitted
afterwards went through `emit-generic-call` and named `@append.ptr.ptr` — a
symbol nothing defines. Minimal repro on the pre-W1a compiler,
`lib/list.nuc`'s concrete `append` plus `lib/vector.nuc`'s `append` template:

```lisp
(import-use "lib/list.nuc")
(import-use vector)
(defn main ():i32
  (let (c:ptr (make-cell null null 0) r:ptr (append c c)) (return 0)))
```

→ `define ptr @append(...)` / `call ptr @append.ptr.ptr(...)`, and the link dies
`use of undefined value '@append.ptr.ptr'`. `examples/rest-defn.nuc` and
`examples/string-test.nuc` escaped it only because every call to the affected
names happened to be emitted *before* the overloading import, inside the defining
library itself — which is exactly why they are the two programs in the tree whose
IR changed by more than type-line order when W1a landed.

W1a removes the failure mode structurally (all reachable signatures are
registered before any form is emitted, so the decision is final). Two things to
keep in mind if you touch this area:

- **A pre/post `--emit-llvm` sweep over `lib/*.nuc` + `examples/*.nuc` is the
  cheap way to find this class**, and it is worth running for any change that
  moves *when* registrations happen. Bucket the results — byte-identical,
  differing-only-in-type-order (sort-normalize, see above), and genuinely
  different — and explain every entry in the third bucket.
- **The mangled name is now observable for any overloaded-anywhere function.** A
  C consumer that linked against a bare `@name` for a function some *other*
  reachable file also defines was relying on the bug; it must use the mangled
  symbol, stop overloading the name, or expose a solitary wrapper.

## The compilation unit's ROOT file is on none of the import lists

`g-prescan-visited`, `g-prescan-sigs` and `g-imported` together record every
`.nuc` file that entered the unit **through an import** — the type prescan's
walk, W1a's signature walk, and import emission. Nothing imports the entry
point, so the root file appears on none of them. `g-source-path` covers it only
while the root is the file currently being emitted; the moment an imported
file's body is being emitted, a membership test built from those three lists
answers "not in this unit" for the entry point. Stage 15 W1c added
`g-unit-entry-path` (set in `emit-toplevel-forms` at `g-toplevel-depth == 1`,
reset in `compiler-init`, diagnostic-only) for exactly this. Any future feature
that asks "is this path part of the unit?" needs the fourth check too.

**Stage 15 W9 item 1 made two of those lists load-bearing, because the root is
not merely *unlisted* — it is REACHABLE.** The compiler auto-prepends
`(import-use prelude)`, and the prelude's own closure is
`prelude → macros, node → arena`, so compiling any of those four files as the
entry point makes the unit import its own root. `emit-toplevel-forms` now
records `g-source-path` on **`g-prescan-sigs`** (the second
`prescan-defn-signatures` was a `duplicate definition of 'arena-init'` blamed at
the file's own line — see the non-idempotency note above) and on
**`g-importing`** (without which `do-import` read and emitted the file a second
time, duplicating every `define`; that half was invisible because the prescan
error fired first). The push is skipped when the path is already on
`g-importing`, because a REPL `(import-use …)` reaches depth 1 *through*
`do-import`, which pushed it and will pop it.

**The interesting half is that a cycle SKIP on the root is wrong.** Pushing the
root onto `g-importing` alone routes the re-entry into W1d's cycle path — which
fixed `arena`/`node` and instantly broke `lib/macros.nuc`, because a cycle
deliberately does not carry macros and `lib/arena.nuc` needs `when`. Here the
skipped file is precisely the one holding what the rest of the chain is about to
use. So `do-import` **hoists** instead: `import-reentry-hoists-root` lets the
re-entry fall through to the ordinary read-and-emit, and the depth-1 loop then
stops because its own path has appeared on `g-imported`. The safety condition is
a one-shot window — `g-root-hoist-ok`, armed just before the depth-1 loop and
cleared at the end of its **first iteration** — since hoisting after the root
has emitted any of its own forms would emit those forms twice. The auto-prelude
import *is* that first iteration, so the window is exactly wide enough and no
wider; a user-written back-import later in the file still takes the cycle skip.
Two consequences worth keeping:

- **The hoist RE-READS the root file**, which is why `(exclude-prelude)` had to
  become a no-op in `emit-toplevel-forms`' dispatch: `strip-exclude-prelude`
  runs only in `main`, so the directive survives into the re-read (and into any
  ordinary import of such a file, which died `unknown top-level form` — W9 item
  5). A directive that belongs to the *unit* must be tolerated wherever a *file*
  is processed.
- **Path identity here is string equality on the spelling**, inherited from
  `g-imported`. A root compiled by an absolute path whose importers resolve a
  relative one is not recognised as the same file. Pre-existing; canonicalising
  would move every path string in every diagnostic.

## `lib/` means "compiles on its own"; a file that touches compiler globals belongs in `src/`

The invariant `make lib-objs` / `make lib-headers` / `make lib-cheaders` assert
is that every `lib/*.nuc` compiles as its own entry file in all three emit
modes. The reader is the worked example of **both** directions of this rule:
it moved out of `lib/` at W9 item 1 because it read and wrote compiler globals
(`g-src`/`g-pos`/`g-line`/`g-source-path`/`g-peek`/`g-interactive`/`g-mono-context`),
and it moved back — as `lib/read.nuc` — at Stage 21 R-1/R-2
(`design/stage21-cleanup/one-reader.md`) once its state became a `Reader`
*value* with no compiler dependency left. What genuinely needs the globals —
`die-at`, `report-at`, the two byte helpers — split out into
`src/diagnostics.nuc` instead, which stays in `src/` for exactly the original
reason; `repl.nuc` / `cheader.nuc` / `format.nuc` are there for the same
reason. Import resolution searches the importing file's own directory first,
so `(import-use read)` / `(import-use diagnostics)` from `src/nucleusc.nuc`
find them wherever they live, and a file's IR is byte-identical across a move
like either of these. If you add a file under `lib/`, compile it standalone
once; the `w9-lib-emit-*` units (`tests/suite-linking.nuc`) will otherwise
find it for you.

**`--emit-nuch` was exempt from the prelude and processed no imports at all**,
which is why nine library files could not produce a header: a `.nuch` exports
signatures and a signature names types (`Node`, `StrView`, `String`,
`(Maybe T)`, `!T`'s `(Result T E)`). `emit-nuch-header` (`src/nuch.nuc`) now
runs `prescan-file-imports` + `prescan-imported-types` for the same reason
`emit-toplevel-forms` does. **`--emit-cheader` keeps the exemption**: it exports
the C-representable subset, which cannot name a prelude type.

Note `make lib-headers` / `make lib-cheaders` write their outputs **into
`lib/`**, over the committed `lib/mathlib.nuch` and `lib/boxlib.nuch` and
leaving ~30 untracked files behind. Regenerate and diff those two rather than
assuming; delete the rest when you are done.

## A C struct the importer cannot lay out is registered OPAQUE — hand-declare and validate, don't field-access

**The example below is stale and kept for the technique, not the diagnosis.**
`struct dirent` and `glob_t` both lay out now (array members landed in Stage 16
L2, function-pointer members in FP-4), so `src/nucleusc.nuc`'s validated
`d_name` byte-offset read is no longer *required* — it is simply not worth
rewriting. What is durable is the shape of the workaround for whatever the
importer cannot represent next (today: an array extent that does not fold, and a
declarator list of mixed pointer depth).

`c-parse-struct-decl` declines such a member, so W3a
registers the whole type layout-less (`StructDef.opaque = 1`) and any field
access on it is refused with the opaque diagnostic. The working shape
when you need such a C API is to `(declare …)` the functions by hand (no
`(import-use "<header>")`, which also avoids a `clang -E` run and the
`MAX-STRUCTS` pressure) and reach the field through a byte offset — but only
with the offset **validated, not trusted**: W1c's `d_name` read (offset 19 on
64-bit glibc/musl) is accepted only when the bytes there are a short
NUL-terminated name with a `.nuc`/`.nuch` suffix, so a platform whose layout
differs degrades to "found nothing" instead of printing garbage into a
diagnostic. POSIX does not fix these layouts and neither does Nucleus have
`offsetof` over a C header type; a self-checking read is the whole answer.

(POSIX dependency in the compiler itself is already established — `popen` /
`pclose` in `src/cheader.nuc` run `clang -E` for every C-header import — so
adding `opendir`/`readdir`/`closedir` beside them changes nothing about which
platforms can host the compiler.)

## Never re-enter the reader from a diagnostic path — scan text instead

Before Stage 21, `read-program` / `desugar` mutated five compiler globals
(`g-src`, `g-pos`, `g-line`, `g-peek`, `g-peek-valid`), and composing a
diagnostic was not a safe moment to do that: the message is being built from
state that belongs to the form being blamed. `lib/read.nuc`'s `Reader` is a
value now, with no ambient state to clobber, but the rule still holds for a
different reason (`text-defines-name`'s own comment, `src/nucleusc.nuc`): a
full read plus `desugar` from a diagnostic path buys nothing a byte scan does
not, and `desugar` can die itself — while the caller is already on a dying
path composing *its own* diagnostic. When a diagnostic wants to know something
about *another file* (W1c's "which file defines this name?"), scan the bytes
instead. A small tokenizer that skips
line comments and string literals removes the two false-positive sources that
matter, and what remains — a definer spelled inside a quasiquoted macro body —
is acceptable precisely because the result is phrased as a `note:` and the
primary error text stays true on its own.

The corollary that makes this affordable: **check that every caller is on a
dying path before spending anything on a diagnostic.** `die-at` (src/diagnostics.nuc)
carries `noreturn`, so a scan reached only from `die-at` call sites runs at most
once per compile — a directory walk plus a file read per candidate is invisible
(a failing fixture compiles in the same 0.135 s as a clean one). The same work
on a speculative or recoverable path would be a real cost. In the REPL `die-at`
unwinds via `repl-throw` rather than `exit`, which is still one run per *failed*
command.

## A per-file scope is cheapest expressed as a *namespace*, not as a visibility filter

Stage 15 W5e made a private definer (`defn-`/`defvar-`/`defconst-`/`defenum-`) in
a file with no `(ns …)` private to that **file** rather than to the shared `user`
namespace. The obvious implementation — keep the bare key and filter candidates
by "which file owns this?" at every lookup — is the expensive one: it needs a
new field on both `Sym` and `Generic`, a visibility test inside `scope-lookup`'s
backwards scan (the compiler's hottest loop), and a *two-tier* scan to get
shadowing right, because a backwards scan returns the most recent match and the
private one is not necessarily it.

Putting the scope in the **key** instead removes all of that. The key is an
ordinary namespace-qualified spelling — `#p1/helper` — so:

- `qualify-name` is **idempotent** on it (interior slash, ns-part ≠ `user`), so
  `scope-define`/`scope-lookup` need one call each and nothing downstream cares;
- `strip-ns-qualifier` recovers the bare name, which is why
  `import-alias-one` — and therefore `unsafe/import-private` — kept working with
  **no change at all**;
- the synthetic namespace's ir-prefix, registered through the existing
  `ns-ir-prefix-set`, flows through `ns-compose`/`mangle-fn-name` unchanged, so
  the solitary and overloaded symbol spellings both fall out
  (`@a_p1__helper`, `@a_p1__helper.i32`);
- shadowing (a file's private name beating a public one elsewhere) is automatic:
  the two are different keys, and the private probe simply runs first.

Two things that make the scheme safe:

- **The synthetic namespace must be unspellable.** `emit-ns` rejects a
  `#`-leading name; that one guard is the whole argument that a synthetic key
  can never collide with a user one. Prefer this to hoping nobody types it.
- **Feature tables must start `null`, and every entry point must short-circuit
  on that.** `g-priv-files` is null until the first private definer, so a unit
  that uses none — this compiler included — runs the identical pre-W5e code path
  and emits identical IR. This is the same shape as `g-ns-prefix-table` and
  `g-fn-attr-table`, and it is what lets a change to `scope-lookup` and
  `generic-lookup` (called on every name in every program) be provably free.

## A namespace canonicalizer is per-REGISTRY, not per-string — and Stage 12 collapsed two of them

Stage 15 W9 item 21. Stage 12 N4 gave the conformance registry one
canonicalizer, `strip-ns-qualifier`, and applied it to *both* halves of its
`(type, protocol)` key. That was right for the type half and wrong for the
protocol half, and the two halves are not interchangeable:

- **A TYPE name is bare-keyed and global.** `register-struct` stores the raw
  head symbol, so `strip-ns-qualifier` is what makes a qualified type reference
  resolve to the same `StructDef` from any namespace. **Do not re-extend this to
  a protocol position** — `strip-ns-qualifier`'s comment now says so.
- **A PROTOCOL name is namespace-keyed**, like a global in `g-globals`:
  `protocol-new` keys on `qualify-name`, and `protocol-canon-name`
  (`src/nucleusc.nuc`, beside `strip-ns-qualifier`) is the single canonicalizer
  every protocol-keyed registry calls — the conformance registry, the
  super-protocol edges, `:where` `Constraint.proto`, and `(dyn P)`'s box type.

Four things about that generalize past protocols:

- **Resolution is qualified-then-bare, and the fallback is load-bearing.**
  `protocol-lookup` probes `<current-ns>/<name>` then the bare spelling — the
  same shape as W5e's private-name probe. Without the fallback a namespaced file
  could not see `Clone`/`Eq`/`Ord`/`Allocator` and every namespaced library
  would be unusable. With it, an *ambiguous* bare reference (two namespaces, no
  bare protocol) correctly resolves to neither.
- **Registration must use an EXACT probe, never the resolver.** This is
  `generic-register-method`/`generic-lookup-exact`'s rule again: a define's key
  is already final, so routing the idempotence check through the
  fallback-bearing resolver makes `(ns dp) (defprotocol Clone …)` see the
  prelude's `Clone` and never register `dp/Clone`.
- **Canonicalize a stored reference where it is WRITTEN, not where it is read.**
  A `:where` constraint is checked long after registration and usually while a
  *different* namespace is current, so `parse-where-constraints` canonicalizes
  at parse time (`prescan-protocols` runs immediately before the same file's
  signature prescan, so its own protocols are registered). The canonicalizer is
  the identity for an unregistered name and idempotent on a canonical one, so a
  reference parsed too early degrades to the raw spelling and re-canonicalizes
  at every later lookup — which is exactly what keeps blanket names (`Any`,
  `Struct`, `Clone`) and `Valid` bare.
- **A memo keyed on a source spelling becomes a TYPE-IDENTITY bug the moment the
  spelling stops being canonical.** `dyn-type` (`src/union-registry.nuc`)
  memoizes `(dyn P)`'s `{data,vtable}` `StructDef` by protocol name; keyed on
  the raw spelling, `(dyn Describe)` inside `(ns dp)` and `(dyn dp/Describe)`
  outside it would build two `StructDef`s, and `type-eq` (sdef pointer identity)
  would call one protocol two incompatible types. It canonicalizes at entry.
  Note where the canonicalizer had to live for that: `union-registry.nuc` is
  imported *before* `generics.nuc`, so it cannot call `protocol-lookup` — but it
  may call *up* into `nucleusc.nuc` (it already up-calls `intern-str` and
  `guard-name-kind`), and `protocol-canon-name` sits well below
  `(import-use generics)` there. Prefer that to a fourth late-binding hook.

**The remaining un-namespaced registry is `g-generics`, and it is a real design
question, not an oversight.** `generic-lookup`/`generic-register-method` key on
the **raw** name, so two namespaces defining the same function name collapse
into one `Generic` mangled under whichever was seen first (`@qa__describe.pDog`
for a method defined in `qb`). Conversely `scope-lookup` qualifies a global key
with **no** bare fallback, which is why a file with an explicit `(ns …)` cannot
reach `default-allocator` and therefore cannot box a value at all. Both are
pre-existing (W9 items 22/23); know which registry answers your question before
assuming a cross-namespace path works.

**Two registries answer a name, not one.** `finalize-generics` binds a *solitary*
generic into `g-globals` and `emit-dispatch` falls through to `scope-lookup` for
it, while an *overloaded* one dispatches through `g-generics` and never touches
the scope. Any change to how a name is keyed must therefore land in **both**
`scope-lookup`/`scope-define` (`src/scope.nuc`) and `generic-lookup`/
`generic-register-method` (`src/generics.nuc`), or the solitary and overloaded
halves of the same feature silently disagree. Note the define/use asymmetry that
falls out: `generic-register-method` must use an **exact** probe
(`generic-lookup-exact`) because its key is already final — routing it through
the private-preferring `generic-lookup` would fold a file's *public* `helper`
into its own *private* `helper`'s generic.

**And the timing rule W1a set still governs.** A private name's key is fixed
during the prescan, which runs before any form is emitted, while
`g-defining-private` is otherwise set only by the top-level dispatch loop around
the emitter. So **every prescan that registers a name must arm the flag itself**
— `prescan-defn-signatures` does (around each `defn-`), and W8 G-0's
`prescan-value-names` does (around each `defvar-`/`defconst-`/`defenum-`). A new
per-definer property that must be known at *registration* time has to be armed in
the prescan too, or it is silently absent for exactly the pass that decides the
key.

The cost of getting that wrong is a **silent wrong answer**, not a diagnostic,
and G-0 found a live instance: before it, a `defconst-` referenced from *earlier
in its own file* resolved to another file's **public** constant of the same
spelling (measured: returned 7 instead of 61, compiled clean), because the
private key did not exist yet when the reader was emitted while the public one
did. A test for a private-name feature must therefore link and run and assert the
*value*; "it compiles" cannot distinguish the two answers.

**A census of the compiler's own source can retire a design hedge outright.**
W5e's spec hedged toward the weaker option because the stronger one "moves IR".
`src/` uses **zero** private definers and `lib/` exactly one (in a demo the
compiler does not import), so no private-definer change can move `make bootstrap`
at all — and the hedge, plus a subtler "only qualify on collision" variant with a
real `finalized`-is-sticky hazard, both evaporated. Count before you hedge; and
count with an anchored pattern (`grep -nE '^[[:space:]]*\(defn- '`), since a
`-o` match of `(defn-` also hits every `(defn-parse-sig …)` call in the tree.

## A per-FILE binding must be recorded before `do-import`'s early returns, not inside the load block

Stage 15 B1 made an import prefix file-scoped
(`design/stage15-stress-test/name-resolution.md` §2.4). The mechanism is the one
`g-current-ns` already uses — save, clear, restore around each imported file —
and the *only* subtlety is **where** the binding is written.

`do-import` reaches its load block through three early returns, and every one of
them leaves the import genuinely *declared in this file* while doing no further
work:

- the `(file, prefix)` dedup — a second file importing the same library under
  the same prefix;
- the already-loaded flatten dedup — `prefix == null` and the file is on
  `g-imported`;
- W1d's **cycle skip** — the partner is mid-emission higher up the stack.

Recording the binding inside the load block therefore drops it in precisely the
cases where a file legally re-declares an import the unit has already processed.
The cycle case is the one with teeth: without the bind, the new "prefix not in
scope here" diagnostic fires for a prefix the file *did* declare, and one failure
gets two contradictory explanations (W1d's `cycle-prefix-message` already answers
it correctly). Generalize as: **a per-file record belongs at the point the form's
subject is known, not at the point the work happens** — dedup and cycle skips are
short-circuits on the *work*, never on the *declaration*.

Three more facts from the same step:

- **`import-list-has` / `import-list-find` compare `(entry s)` by POINTER
  identity**, and the prefixes on `g-import-prefixes` are *not* uniformly
  interned: an explicit prefix comes from a `NODE-SYM` (interned), but a default
  one comes from `import-default-prefix` / `path-import-default-prefix`, which
  return `arena-strdup` / `strndup` buffers. So the existing "prefix is already
  bound to another file" check is content-blind for a defaulted prefix. Any new
  scan over that list must compare by **content**; do not assume the list is
  interned because most of its entries happen to be.
- **The gate belongs in `scope-lookup`'s null-parent branch and nowhere else.**
  The global scope is the last link of the chain, so returning null there is the
  whole answer; a local binding still shadows normally because the gate never
  runs for a parented scope. It short-circuits on a null `g-import-prefixes`, so
  a unit with no prefixed import — every build of this compiler — is provably
  unchanged. (Same shape as `g-priv-files` / `g-ns-prefix-table`.)
- **The REPL needs nothing.** A prefixed import routes through the ordinary
  top-level dispatcher into `do-import`, and the session's environment is simply
  the one nothing ever saves or restores — so bindings accumulate across
  commands, which is what a session wants. `src/repl.nuc` intercepts only
  `import-use`/`import-only` (for the declare-backfill) and those still reach
  `do-import`.

**And the diagnostic is half the deliverable.** A qualifier that no longer
resolves must not fall through to W1c's "not defined anywhere in this compilation
unit": the name *is* defined and the graph *does* reach it, so that message is a
lie of exactly the class W1c exists to remove. A scope rule needs a scope
diagnostic — name the qualifier, where it *is* bound, and what is in scope here —
and it must be ordered **before** the reachability tiers in
`unresolved-name-message`, since those tiers answer a different question and will
happily answer it first.

## A name-resolution rule has TWO entry points: a spelling and a key — and the same string arrives at both

Stage 15 B2a cut protocols over to one canonicaliser (`resolve-spelling`,
`src/nucleusc.nuc`, `design/stage15-stress-test/name-resolution.md` §9.2). The
canonicaliser itself is small and kind-agnostic. **The work — and all of the
risk — is that one lookup function was serving two different questions**, and
splitting them is per-kind and manual.

* A **source spelling** (`(extend Cat dpx/Describe)`, `(dyn dpx/Describe)`) must
  be resolved through the *writing file's* import environment. That is the whole
  fix: a prefixed import binds its prefix and **not** the library's namespace, so
  `dp/Describe` must resolve to nothing even though `dp/Describe` is literally
  the registry key.
* An **already-canonical key** — a stored `Constraint.proto`, a super-protocol
  edge, a `.nuch` replay's name, a `(dyn P)` box's protocol, the name a resolved
  `extend` passes down its own call chain — is read back **in a different file
  from the one that wrote it**, routinely. Resolving it as a reference is a false
  rejection of a correct program.

So `protocol-lookup` is the reference resolver, `protocol-lookup-ns` (the old
body, renamed) is the key lookup, and `protocol-resolve-any` (reference, else
key) serves positions downstream of a gate. Classifying the 13 existing call
sites was hand work: `(protocol-lookup (crec proto))` and `(protocol-lookup
(type-node s))` are the same expression over different provenance, and each
wrong guess is either a false rejection or a silently unclosed hole. **Any
future kind cut over to the canonicaliser needs the identical split and the
identical audit** — and note the split is a property of where the *string* came
from, not of the registry's shape, so it survives any later unification of the
registries.

Three sub-rules that fall out, each of which cost a wrong first design:

- **Resolve once, at the reference, then carry the record.** `emit-extend` used
  to `protocol-canon-name` the spelling and then look the *canonical name* up
  again. Under a scoped resolver that asks the scope question twice and gets two
  answers — the legal `dpx/Describe` canonicalises to `dp/Describe`, which the
  second lookup then refuses. It now calls the resolver once, keeps the
  `?ptr:Protocol`, and passes `(p name)` downward. Prefer this to
  canonicalize-then-look-up anywhere a canonicaliser can *fail*.
- **A memo key must be phase-stable; a permission check belongs where the
  permission is known.** `dyn-type` mints `(dyn P)`'s `StructDef` from a `defn`
  signature during `prescan-defn-signatures` — where `g-file-imports` is empty by
  construction and imported protocols are not yet registered — and again from the
  same signature at emission, where both are populated. An environment-dependent
  key would differ between those two moments and mint **two** `StructDef`s for
  one protocol, and `type-eq` is `StructDef`-pointer identity: exactly the W9
  defect-21 bug. So the box's identity key stays on the environment-free
  `protocol-canon-name-ns`, and the scope question is asked once, at box
  construction, by `dyn-require-protocol`. Identity and admission are different
  questions and only the second one is about what this file may name.
- **Downstream of a gate, do not gate again.** `dyn-method-slot`,
  `emit-dyn-forward` and `derive-closure-conformance` may run in a file that
  never named the protocol (the box was constructed elsewhere). They use the
  permissive `protocol-resolve-any`; the single gate is `emit-box-value`'s.

**Where a file's namespace becomes known is `emit-ns`, and that is the only hook
you need.** B2a's `path → ns` table (`g-file-ns`) is written there rather than at
the end of `do-import`'s load block, and the difference matters: `emit-ns` is
reached from *every* file entry (the root, both `do-import` load blocks, and
`prescan-imported-signatures` via `apply-leading-ns`), and because the W1a
whole-graph prescan runs before any form is emitted, every reachable file's
namespace is recorded before the first import form is *processed*. The
already-loaded and W1d cycle-skip paths — which never enter a load block, and
which B1's report flagged as the hard cases — therefore need no special handling
at all. A path with no record is in `user`, so absence is an answer rather than a
gap.

**And a feature table's null state is still the byte-identical proof.**
`g-ns-declared` is set only by `emit-ns`, so it is 0 for every build of this
compiler and every program in `lib/`; it gates the flattened-namespace probe,
which is what keeps a unit with no namespaces on exactly one registry scan per
bare lookup. Measured: a compiler built from a clean `HEAD` worktree and the
B0+B1+B2a compiler emit `diff`-identical IR for all 182 files in `examples/` +
`lib/`. That whole-tree sweep is the check that catches what `make bootstrap`
cannot — bootstrap only proves the compiler is self-consistent, not that
*programs* are unaffected.

## Splitting a lookup into reference/key: the line is where the STRING came from, and one class of caller has no tell

Stage 15 B2b cut `g-globals` over to the canonicaliser
(`design/stage15-stress-test/name-resolution.md` §9.3) — the same
reference-vs-key split B2a's note above describes for protocols, but at 59 call
sites instead of 13. Three things generalise.

**For a registry whose definers all go through one writer, the line is
syntactically visible.** Every *key* site for `g-globals` is paired with a
`scope-define`: it asks about the key the compiler is about to write, or has just
written (the `.nuch` `declare` replay, the C-header registrar,
`emit-deferror`/`emit-extern` dedup, `cheader-yield-to-explicit-declare`, the
REPL's three redefinition probes — eight in all). Everything else is a reference.
Look for that pairing first; it collapses most of the audit. Protocols had no
equivalent tell, so do not assume the next kind will.

**The residue is the dangerous part, and it is silent.** ~15 sites look up a
string the *compiler itself* wrote — `"printf"`, `"fflush"`,
`"default-allocator"`, `"alloc-handle-alloc"`, `"g-handler-top"`, and the
`"fn"`/`"vfn"`/`"mfn"`/`"cfn"` shadow tests. These are neither a user's spelling
nor a stored key, nothing in the code distinguishes them, and **both
classifications compile and pass every test**. They are references: the question
they ask is "is this reachable from the file being compiled". The only observable
consequence is whether a file with an explicit `(ns …)` can reach a `user`
global, which is why the wrong answer here stays invisible — it had been
invisible since Stage 12, recorded as a comment in `lib/nsdescribe.nuc` rather
than as a bug.

**A `sym-private`-style filter cannot ride along with the thing you delete.**
`inject-import-aliases` filtered the slice it copied on three fields. Two
(`is-local`, a null `ir-name`) meant something else entirely and were the defect;
the third (`sym-private`) was a real visibility rule. Deleting the copy deletes
all three, so the real one has to be re-expressed where the reference is
resolved — and the permission it depended on (`g-import-include-private`) is a
*transient* global set only during the import, so it has to be recorded on the
binding (`ImportBind.private`) at bind time. When you delete a mechanism, sort
its guards into "accidental" and "load-bearing" before you delete, not after.

The trap inside that re-expression: an imported file with no `(ns …)` is in
`user`, so when the *importing* file is also in `user` the two namespaces compare
equal and any "a file may see its own namespace's private names" shortcut fires
first and swallows the private probe. That is the ordinary case for this
compiler's own libraries, not a corner. Make the private probe a fallback of the
whole qualified path, never of its else-branch.

## `g-special-form-set` is a RESERVATION, not the dispatcher

Worth knowing before touching either. `emit-list` (`src/nucleusc.nuc`) and
`node-type-call` (`src/generics.nuc`) dispatch special forms by comparing the
**interned head pointer** against quoted symbols (`(= hp 'unsafe/cast)`); they
never consult `g-special-form-set`. The set has exactly **one** consumer,
`special-form-named` → `name-existing-kind` → `guard-name-kind`, i.e. its whole
job is "a definer may not shadow this name".

The consequence bit Stage 15 B2b: `design/stage14/unsafe-namespace.md` §8.3
described removing the seven `unsafe/*` entries as *"a dispatch change"*.
Measured, it is not — it is a reservation change, and removing them without
replacing the reservation would have made `(defn unsafe/cast …)` legal and
permanently shadowed (the ladder still wins, so the definition would never
fire). `special-form-named` now answers for that roster by resolving the
qualifier and consulting `unsafe-op-named`.

Two related facts from the same step:

- **`unsafe` is a real built-in namespace**, bound as an implicit prefix in every
  file's environment by `resolve-spelling`. Bound *prefixed*, so it is never
  flattened, which is what makes bare `cast`/`ptr+`/`funcall-ptr-*` unresolvable
  as a *consequence* rather than as hard-coded refusals. Six of UN-5's seven
  refusals were therefore deleted — from **both** `emit-list` and
  `node-type-call`, which is the lockstep; deleting from one alone makes the
  non-emitting pass die where codegen no longer does. Their exact messages
  survive as a tier of `unresolved-name-message` (`unsafe-bare-message`), so five
  pinned diagnostics did not move.
- **The seventh does not generalise.** `unsafe-import-private`'s bare spelling is
  a *different string* from the member's bare name (`import-private`), so no
  binding can refuse it and its own top-level arm stays. When a retirement is
  meant to fall out of "the name is not bound", check that the retired spelling
  really is the bound name minus its qualifier.

## Privacy: `Sym` carries it for values, the four other definers now carry their own (B5)

`defn-`/`defvar-`/`defconst-`/`defenum-` set `sym-private` on the `Sym` they
register, and B2b's `scope-frame-find-public` (`src/scope.nuc`) enforces it at a
reference. `defstruct-`/`defunion-`/`defmacro-`/`defprotocol-` register **no
`Sym` at all** (`emit-toplevel-forms`' own comment says so), and until Stage 15
B5 no other registry carried a private flag — so their privacy was accepted and
enforced by nothing. B5 gave `StructDef`, `UnionDef`, `StructTemplate`,
`UnionTemplate`, `MacroDef` and `Protocol` a `priv` + `src-ns` pair and one
shared rule, `binding-visible` (`src/nucleusc.nuc`). Four things about it that
generalise to any future visibility rule:

- **The rule is one function; the *call sites* are per-kind and there are six.**
  Enforcement lives in each kind's **reference** lookup — `lookup-struct`,
  `uniondef-lookup`, `struct-template-lookup`, `union-template-lookup`,
  `find-macro`, `protocol-lookup` — because those are what a source spelling
  actually reaches. Putting the check only in the shared `binding-probe` looks
  equivalent and is not: `parse-type-name` calls `lookup-struct` directly, so
  every `:T` annotation in the language would have gone unguarded. Registration
  and idempotence probes must keep using the **key** lookup
  (`protocol-lookup-exact`), never the filtered one — a define must always find
  its own entry.
- **Capture provenance at EMISSION, never in a prescan.**
  `prescan-struct-names` is reached from `prescan-imported-types`, which does
  **not** apply an imported file's leading `(ns …)` — so `g-current-ns` there is
  the *importer's*. Recording `src-ns` in that prescan wrote the wrong namespace,
  and because the entry was also marked private it then became invisible to
  `emit-defstruct`'s own `lookup-struct`, which registered a **second**
  `StructDef` under the same name; the stale first entry stayed visible to
  everyone and the whole filter silently did nothing. A prescan entry is `priv`
  0, and `binding-visible` returns before consulting `src-ns`, which is what
  makes leaving it blank safe.
- **A registration that early-returns needs an explicit update.**
  `register-struct-template` / `register-union-template` are no-ops once the
  prescan created the entry, so `emit-defstruct`/`emit-defunion` set the
  template's `priv`/`src-ns` by hand in their `NODE-CELL` branch.
- **Gate the whole mechanism on a "does any exist?" flag.** `g-priv-bindings` is
  0 for every program in `src/`, `lib/`, `examples/` and `tests/`, so the six
  filters are provably inert rather than believed to be — the same shape W5e's
  `g-priv-files == null` short-circuit uses.

Scope, unchanged from W5e and worth restating: privacy for these four is
**namespace-level, never file-level**. A type, macro or protocol name is
bare-keyed and globally identified (Stage 12 decision 9), so in the default
`user` namespace `defstruct-` still hides nothing.

## One name-kind priority order: ask for a DIFFERENT kind, not the highest one

Stage 15 B5 unified `name-existing-kind`'s enforcement order with
`emit-dispatch`'s consumption order (name-resolution.md defect #8) into one
table, `build-binding-kinds` (`src/nucleusc.nuc`), whose **row order is the
order**. The trap is what "unify" has to mean.

Picking `emit-dispatch`'s order and having the guard walk it **weakens the
guard**, measurably. Every definer registers its own name in a prescan *before*
its own guard runs, so with `g-generics` first a `(defn Shape …)` written over an
existing `defprotocol Shape` finds the `Generic` its own signature prescan
registered a moment earlier, reports `NK-FUNCTION`, matches what it is about to
define, and never looks at the protocol. (It compiled clean before B5.)

The fix is to change the **question**, not to pick a winner: `guard-name-kind`
asks the table for the first binding whose kind is **not** the one being defined
(`binding-find`'s `skip-nk`). That is order-*independent* for the verdict — the
row order then only chooses which of several conflicting kinds to *name* — which
is precisely what lets one order serve both callers. Two consequences to know:

- A cross-kind clash is now reported at whichever definer is **emitted first**,
  naming the other one's kind. Two long-standing pins moved blame line and noun
  (`w8-fnptr-global-name-collision`, `g0-value-fn-collision-order2`); both still
  assert rejection, and both carry the reason inline. If you see one of these
  "regress", check the verdict before the text.
- `node-type-call` mirrors `emit-dispatch` by calling the **same** `binding-find`
  with a narrower upper bound (it models rows through `BK-GLOBAL`, the ones that
  yield a type). A *window on one call* is the lockstep-safe way to have two
  passes agree on part of an order; a second copy of the list is not.

**A prescan had to move with it.** `prescan-protocols` now runs before
`prescan-struct-names` in `emit-toplevel-forms`. The struct prescan registers a
name-only `StructDef` and does **not** guard, so whichever ran first won every
`defprotocol`/`defstruct` clash — and the struct always ran first, which is why
the clash used to be reported at the *protocol's* line saying "already names a
type". `protocol-register-form` stores its method sigs verbatim and parses them
lazily, so it needs no struct name registered yet. Note the residue: for an
**imported** file the two prescans still run in the old order (pass 1
`prescan-imported-types` → `prescan-struct-names` for the whole graph, then
`prescan-imported-signatures` → `prescan-protocols`).

**A did-you-mean must offer a spelling the file can WRITE.** `closest-known-name`
printed the candidate's raw registry key, and a generic is keyed *bare*, so a
function reachable only as `zx/zfun` was suggested as `zfun` — the spelling that
had just failed. Render through the binding's `src-ns`
(`binding-usable-spelling`), drop a candidate the file cannot reach at all, and
never emit a suggestion equal to the input. The same applies to any future
"helpful alternative" text: a suggestion that does not compile is worse than
none.

## A type spelling is now a REFERENCE — so every place the compiler *writes* one is a synthesis region, and a missing arm is a false rejection

Stage 15 B3′ re-keyed the six type registries on `resolve-spelling`
(`design/stage15-stress-test/name-resolution.md` §9.4), so `(ref dpx/Fox)`
resolves through the writing file's import environment exactly like a global or a
protocol. That is the fix for defects #4/#7 — and it creates a new obligation
that nothing in the tree exercises, because no program in `src/`, `lib/` or
`examples/` uses a namespaced type across a namespace boundary.

**`type-spelling` renders a `Type` back to its CANONICAL name** (`dp/Fox`), and
the compiler re-parses that string in five regions: a template stamp, a
monomorphized body, a protocol-signature `Self` substitution, a stored
conformance argument, and a `.nuch` replay. The file those are re-parsed *in* is
routinely not the file that produced them, so resolving them as references asks
the wrong file and refuses a legal program. The permission is **`g-type-key-ok`**
(`src/nucleusc.nuc`), armed save/set/restore around each region; the five
reference resolvers (`struct-lookup-ref`, `uniondef-lookup-ref`,
`struct-template-lookup-ref`, `union-template-lookup-ref`, `enumdef-lookup-ref`)
take an exact-key fallback **only while it is armed, and only after the reference
walk misses**. Same shape as `g-defvar-soft` and `g-array-ok`: default refuse,
permitted set enumerable by grepping the arm sites.

Three things about it that a future session will otherwise re-learn the hard way:

- **A missing arm is a false rejection with a diagnostic that reads like a user
  error**: `unknown type: gg/Pt — 'gg' is not in scope in this file`, pointing at
  a library's own line or at line 0. Nothing in the test suite reproduces it,
  because it needs a namespaced type crossing a namespace boundary.
  `tests/suite-namespaces.nuc`'s `b3a-ns-type-in-collection` is the one that
  does — a namespaced struct as a `Vector` element, reached through generic
  dispatch, with a cross-namespace `extend` over it. Keep it running.
- **The arm sites are not "the functions that parse a type" but "the functions
  that produce a spelling nobody wrote", and they are found by exercise, not by
  grep.** B3′ shipped with three missing, each adjacent to one that was present:
  `tmpl-conformance-check-one` (the per-instance check of a template-level
  `(extend (Vector T) (Seq T))`, run at *stamp* time — its sibling branch,
  `conf-arg-to-type`, was armed), `generic-instantiate` (the stamped *signature*
  parse — `drain-mono-worklist` armed the stamped *body*), and
  `resolve-param-type-bound` (the shared substitute-and-reparse helper, armed at
  the helper rather than at `method-bound-ret-type` / `subst-param-types-bound`,
  per W2a's rule). The widest was the first: every collection in `lib/` carries a
  template-level `extend`, so **no namespaced type could be a collection element
  at all**.
- **A canonicaliser that can FAIL makes `canonicalize → re-resolve` wrong**, and
  the second half is easy to add later because it looks like a local validity
  check. `emit-extend` computed `typename = (type-canon-name (type-node s))` and
  then re-parsed *`typename`* "to validate single-token subject types eagerly for
  a clean diagnostic"; under a scoped resolver that asks the scope question twice
  and gets two answers, so `(extend gx/Pt P)` canonicalised to `b3ang/Pt` and was
  refused as an unknown type. Validate **the spelling the author wrote** — it is
  also the better diagnostic. This is §9.2's "resolve once, at the reference,
  then carry the record", and it is not protocol-shaped.

## A memo key computed during a prescan may consult only what a prescan has

Stage 15 B6 (`design/stage15-stress-test/name-resolution.md` §9.5) fixed the
`(dyn P)` box's identity — `dyn-type` (`src/union-registry.nuc`) now keys on
`dyn-proto-key` (`src/nucleusc.nuc`), the protocol's canonical name derived from
`resolve-spelling` — and the reusable part is *why* that function consults **no
registry**.

`dyn-type` runs from a `defn` signature during `prescan-defn-signatures` and
again from the same signature at emission. **Both the root file's own signature
prescan and pass 2's per-file walk run before the imported protocols they name
are registered** (`emit-toplevel-forms` runs `prescan-imported-signatures` last;
pass 2's traversal is pre-order). So a key that probes `g-protocols` answers *not
found* at prescan and *found* at emission — two keys, two `StructDef`s, and
`type-eq` is `StructDef`-pointer identity, so one protocol becomes two
incompatible types **inside one program**. That is strictly worse than the bug
being fixed, because the mismatch then shows up as a raw LLVM parse error with no
source location.

What a prescan-time key *may* consult, because they are complete before any
prescan that resolves a name: **`g-file-imports`** (filled by
`prescan-file-imports`) and **`g-file-ns`** (filled for the whole reachable graph
by `prescan-imported-types`' recursion through `apply-leading-ns` → `emit-ns`).
The one registry probe `dyn-proto-key` keeps is `protocol-lookup-exact` on the
**current namespace's** key only — phase-stable for a different and narrower
reason, that a file's own `prescan-protocols` precedes its own
`prescan-defn-signatures` everywhere. Anything wider is unsound here.

Two structural consequences worth keeping:

- **Identity and admission are different questions and must be asked in
  different places.** Once a box stores the protocol's *canonical* name, asking
  "may this file name it?" against the stored name refuses every legal box — a
  canonical `dp/Describe` is not spellable in a consumer that bound only the
  prefix `dpx`. So admission moved to the **annotation site**, where the author's
  spelling still exists: `dyn-annot-record` / `DynAnnot` / `drain-dyn-annots`.
  Box construction now does a key lookup (`dyn-resolve-protocol`, on
  `protocol-resolve-any`) and asks no scope question at all. `dyn-require-protocol`
  is the admission gate and has exactly one caller; keep it that way.
- **A deferred check needs a drain point chosen by what is *loaded*, not by what
  is prescanned.** The `(dyn P)` drain runs at `emit-toplevel-forms` depth 1
  *after* `drain-mono-worklist`, not after the prescans, because a `.nuc`
  imported by **string path** (`(import-prefixed "lib/x.nuc" p)`) is walked by no
  prescan at all — pass 1 and pass 2 both take only the `NODE-SYM` branch — so its
  namespace and its protocols do not exist until emission. Draining earlier
  falsely rejects every `(dyn p/P)` naming such a library. Two skips keep the
  worklist honest and both are greppable: a `g-type-key-ok` synthesis region (no
  file wrote the spelling) and `g-interactive` **with `g-toplevel-depth == 0`**
  (a REPL form typed at the prompt; a REPL `import-use` runs `emit-toplevel-forms`
  at depth 1 and must defer exactly like batch). Completeness is asserted in
  `main` — cursor versus count — rather than argued.

## An erased-slot coercion has TWO sites — `maybe-box-into-slot` is not the chokepoint

`maybe-box-into-slot` (`src/nucleusc.nuc`) reads like the one place a value is
boxed into a `(BoxedFn …)` / `(dyn P)` slot. It is not: it covers `let`/`with`
init and `return`, while the **argument** position has its own pair of blocks
inside `emit-call-with-args` (added by Stage 13 TE-3/TE-6, ~1800 lines earlier).
This is `coerce-int-val`'s lesson in a second subsystem — see that section — and
Stage 15 B6 found the consequence: both sites had the "already a box, pass it
through" arm and neither asked *which* box, so a `(dyn P)` flowed into a
`(dyn Q)` slot.

The argument site is the one that mattered, and the reason generalizes: **the
SysV ABI decomposes a `{data,vtable}` fat pointer into two `i64`s at the call
boundary**, so LLVM never sees a struct-type mismatch there either. A `(dyn P)`
passed to a `(dyn Q)` parameter compiled, linked and *ran*, dispatching against
the wrong vtable. The binding position, where the box is `store`d as an
aggregate, failed at the IR parser instead — loudly, but with no source location.
So the same defect was silent in one position and locationless in the other, and
neither was a diagnostic.

The check is `box-require-same-kind` (`src/nucleusc.nuc`, above
`maybe-box-into-slot`): a `type-eq` on the two canonical box Types, which is box
identity exactly because both come from one memo. Both sites **call** it. If you
add a third position that assigns into a box-typed slot — `set!` and `.set!`
reach neither today, so they neither box nor type-check — give it the same call,
not a copy.

The *dispatch* out of a box splits the same way and along a different seam — see
"`(dyn P)` dispatch was keyed on the CONFORMER COUNT" near the end of this file.

## A provenance field with three writers and one reader tolerates two of them being wrong

Stage 15 B4 gave generics a qualified spelling (`name-resolution.md` §9.6) by
*filtering* a `Generic`'s method set on `Method.src-ns` — R2's ruling is that
`g-generics` stays keyed by the bare name with every namespace's methods merged,
so the qualifier is a filter and not a key. The arm is two lines. What it cost
was that `src-ns` was **not provenance**: it was a diagnostic field
(`duplicate-signature-message`, W5e) that happened to be set on one of its three
write paths.

* `generic-register-method` sets it. That is the path reading suggests is the
  only one.
* `register-generic-template` (`src/generics.nuc`) builds a METHOD-GENERIC with a
  bare `(new Method)` and never called it — so a bounded-generic template had
  `src-ns` null, filtered to *zero* methods, and `p/tmpl` reported "not defined
  anywhere in this compilation unit", the text a genuinely absent name gets.
* `generic-instantiate-in`'s stamp *does* call it, and therefore records
  `g-current-ns` — **the call site's** namespace. The line directly below it
  already says the mangling must use `(gg ir-prefix)`, "the template's defining
  namespace, not the call site's"; the same argument applies to ownership and had
  never been made. Left uncorrected, the second `p/tmpl` call from another
  namespace filters the first stamp out, `generic-find-method-exact`'s memo probe
  in `generic-instantiate-in` misses, and the instance is stamped and emitted
  **twice under one symbol** — a link error with no source location.

Generalize: **when a field starts being read as a decision input, audit every
writer of it, not the canonical one.** A field only ever consumed by a
diagnostic can be wrong on two paths for years without a symptom.

Two smaller notes from the same step. A filtered view is a fresh `Generic` over
the same `Method` pointers, built per reference and **not memoized** — a cache
goes stale the moment a later import calls `generic-add-method`, which exists
precisely because that happens; and the two answers that matter (all methods
match, no methods match) allocate nothing. And nothing downstream reads a
`Generic` by identity — `generic-resolve`, `emit-generic-call` and
`node-type-call` read `name` / `methods` / `mangled` — which is what makes a
view legal at all. Check that before building one for some other registry.

## A merged registry can answer dispatch questions and cannot answer symbol questions

Same registry as the entry above, one layer up, and the natural sequel to it.
R2 keeps one `Generic` per **bare** name with every namespace's methods merged
into it, because that is what an open multimethod wants. `Generic` therefore
carries two fields that are *not* properties of a merged set:

* `ir-prefix` — snapshotted at `generic-alloc` from whichever namespace happened
  to create the generic first;
* `mangled` — one flag for a whole method set, used both as "dispatch through
  the registry" (correct, it is a unit-wide fact) and as "every method's symbol
  takes `.tok` suffixes" (wrong, that is per namespace).

Read off the generic, both give a namespace's function a symbol decided by
*whoever else is in the compilation unit* (W9 item 23). `(ns qb)` importing a
library that happens to define `describe` emitted `@qb__describe.i64` for its
own function and `@qb__describe.i32` for the **other namespace's**, while its
`.nuch` and its C header — written from the library alone, where neither
condition holds — both declared `@qb__describe`. A consumer of either failed to
link. Swapping two import lines renamed every symbol in the object.

The fix is to ask the method: `method-ir-prefix` for the prefix (from
`Method.src-ns`, which the entry above made trustworthy) and a count of the user
methods sharing that prefix for the suffix. Note the two halves of `mangled`
were *already* separated elsewhere and the precedent was there to be found —
`fn-force-generic-mangled` (`src/nucleusc.nuc`) sets `mangled` without
re-mangling, and its comment says why. **When one field answers two questions and
only one of them is a whole-set fact, the split is already latent; find whoever
needed it first rather than adding a second flag.**

Two things worth carrying:

- **Group by the emitted prefix, not the namespace name.** Two namespaces that
  `set-ir-prefix` to the same string genuinely share one symbol space, and that
  is exactly when their same-named methods must be suffixed. The name is a
  proxy; the prefix is the thing.
- **The invariant to assert is an equality, not a literal.** The gate compares
  the symbol a namespace exports compiled *alone* against the same symbol
  compiled *together* with the other namespace. A pair of literal names would
  still pass if a later change moved both in lockstep — and moving both in
  lockstep is precisely the failure.

`src/*.nuc` declares no `(ns …)`, so every prefix in the compiler is empty and
self-compilation cannot witness this class either — the bootstrap stayed a fixed
point and 742 of 1184 functions came out byte-identical (the other 440 differ
only by `@.str.N` renumbering from one added literal). Only four files in the
tree use a namespace at all, and `lib/nsdescribe2.nuc` names its protocol method
`tag-of` *specifically* to avoid tripping this — a rename in a test fixture that
exists to dodge a defect is a bug report; check for those before believing the
corpus. (That one was read as a bug report: its header comment named the
remaining half as "an unrelated and still open function-namespacing gap", which
became W9 item 35 and is now closed. The method keeps its distinct name, but for
the honest reason — it isolates the test to protocol identity.)

## Deferred work must carry the environment it was created in — and a template body's environment is the LIBRARY's

Fourth entry on the same registry, and the one that generalizes past it. Three
records defer a `defn` form to a later drain. Two of them carry the environment
they were created in and say why; the third did not, and the difference was a
live defect (W9 item 43).

| record | drained by | carries |
|---|---|---|
| `DynAnnot` | `drain-dyn-annots` | `ns`, `path`, `imports` |
| `InitJob` | the `@__nucleus_init` drain | `ns`, `path`, `line` |
| `MonoJob` | `drain-mono-worklist` | *nothing* (before item 43) |

`resolve-spelling`'s inputs are exactly `g-current-ns` + `g-file-imports`, plus
`g-source-path` for `priv-key-use` and the file half of a diagnostic. A drain
runs long after the form was queued, so a record that does not restore those
three resolves its body's names in whatever file the drain happens to be in.

**The direction is not the same for all three.** `DynAnnot` and `InitJob` defer a
question whose answer is the **asking** file's — that is why they snapshot
`g-current-ns` at creation. A monomorphized template body is the reverse: it is
the *library's* source text, so its names must resolve as the library's file did.
`MonoJob` restores `Method.src-ns` / `src-file` / `src-imports` from the
**template**, not from `mono-job-here`'s call-site snapshot. Same three globals,
opposite source of truth — decide which one a deferred body is before copying
the pattern.

Two things that made this hard to see, both worth remembering:

- **A merged bare-keyed registry hides an environment bug.** Before item 43 a
  bare *overloaded* name resolved from any namespace (nothing filtered), while a
  *solitary* name or a global went through `globals-lookup-ref`, which has
  filtered since B2b. So a template calling its own namespace's functions worked
  or failed depending on **how many overloads the callee happened to have**.
  `tests/suite-namespaces.nuc`'s `b4-qualified-template` was passing on the strength of
  that accident — delete one overload from its fixture and it fails. When a test
  covers a path with a merged registry on it, check whether it is passing for the
  reason it claims.
- **Fixing the environment also fixes the attribution.** The old drain reported
  `<caller>.nuc:<library line>` — a file/line pair that in the probe program does
  not exist — and reported the *resolution* failure the wrong environment caused
  instead of the real error in the body. A diagnostic naming a line the blamed
  file does not have is the tell for this whole class.

## A key stops being a key the moment the thing it identified is allowed to vary

W9 item 35, and the sequel to the two entries above. `generic-find-method-exact`
looked a method up by `(generic name, param-types, nparams)`. That pair really
did identify a method — but only because `finalize-generics` refused two
same-signature definitions outright. Relaxing that refusal (so two namespaces may
each define `describe (x:i32)`) silently invalidated every caller that had been
relying on it: `defn-ir-name` asked the two-part question while emitting *each*
file, got the first-registered namespace's method both times, and emitted
`define @qa__describe` twice — a duplicate symbol produced by the very change
meant to give the two namespaces two distinct ones.

**When you loosen a uniqueness rule, the audit is not "what did this rule
prevent" but "what has been using it as a key".** Grep for the lookups, not for
the diagnostic.

The split that came out of it is the same one `binding-probe` documents for
every other registry: `generic-find-method-exact-in-ns` (three parts) is the
**definition** side — which method is in front of the emitter — and the two-part
form stays the **reference** side, because a reference asks which method to
*call* and answers that with the visibility filter plus overload resolution. If
you add a discriminator to a lookup, expect to need both forms, not to replace
one with the other.

## A callable name has TWO registries, and a producer that writes one of them is half-registered

Third entry on the same registry, and the one that says what has to be *put in*
it. Every name you can call is written twice: into `g-globals`, which answers
"what symbol does this name have", and into `g-generics`, which answers "which
method of this name matches these argument types". `emit-defn` writes both even
for a **solitary** function — that second write looks redundant, and it is the
only reason a protocol conformance, a drop thunk or a `(dyn P)` vtable can be
resolved at all.

`emit-nuch-declare-import` (`src/nuch.nuc`) wrote only the first, so a function
that arrived through a `.nuch` was half-registered (W9 item 24). Calls worked —
the ordinary path asks `g-globals` — which is exactly why it survived: **the gap
is invisible to the asker that motivated the registry and visible only to the
askers that came later.** Those are the ones that pose the question by name *and
signature*: `method-satisfies-sig` reported a conforming type as non-conforming,
and `dyn-vtable-method-irname` died `no method 'describe' is defined` for a
method that was declared, defined and linkable.

When you add a producer of a callable name, enumerate the registries the
*existing* producers write and match them; do not infer the set from the one
consumer you are currently looking at.

Two consequences of letting methods arrive from another translation unit, both
of which had to be handled before the corpus stayed still:

- **An imported symbol is a fact, not a decision.** `finalize-generics` names
  every method it sees, which is right while every method is one this unit
  emits. `Method.ir-fixed` marks the ones that are not. Without it, adding a
  single local overload of an imported name re-mangles a symbol another object
  file already defines — a link error, and the same hazard
  `fn-force-generic-mangled` describes ("no already-emitted symbol is renamed")
  stated per method instead of by freezing the whole generic, so a local
  overload added afterwards still gets a mangled name of its own.
- **New entries in a merged registry make new PAIRS meet there.** R4's
  duplicate-*definition* check started firing between two `.nuch` headers from
  different namespaces — over definitions neither importing file makes, and over
  two distinct symbols that had always been legal together. A predicate over a
  merged set must say which members it is about; "the same name is already
  present" is not the same claim as "this unit defines it twice".

Note what still blocks the other half. A `declare` returns early when the name
is already bound (`scope-lookup-key g-globals`), and the unit's own signature
prescan runs first — so a local `defn` of an imported name silently discards the
whole header entry, and even a *qualified* `lib/f` call then resolves to the
local function. That is pre-existing, byte-identical before and after item 24,
and filed as its own defect; it is also why the "imported declare + local
definition" pair is unreachable and only the two-header pair above is real.

## The same-kind redefinition question cannot be asked of the binding table

`guard-name-kind` (`src/nucleusc.nuc`) asks the shared table for the first
binding whose kind is **not** the one being defined, and the `skip-nk` section
above explains why: every definer registers its own name in a prescan before its
own guard runs. Stage 15 B4 added R4's complementary rule — *two definitions of
one name reaching one scope* — and the tempting shape, "same walk, drop the
skip", cannot work for exactly that reason: the walk would find the definer's own
prescan entry every time.

So the table supplies the **noun** (`die-redefinition` reads the row) and each
definer supplies the **fact**. There are ten sites and four different tells, and
the four do not rhyme:

| Definer | Tell | Why not the others |
|---|---|---|
| `defstruct` | `StructDef.emitted` | `prescan-struct-names` registers a name-only entry, so existence means nothing |
| `defunion`, `defprotocol`, both templates, `defmacro` | the defining **(file, line)** | these registrars are legitimately re-entered for ONE form — a whole-graph prescan and again per file, a `.nuch` replay — and carry no state flag |
| `defvar` | `Sym.defvar-state == DEFVAR-REACHED` | W8 G-0 front-loads every reachable file's `defvar` names into the same frame; a Sym under the key is the normal state |
| `defconst`, `defenum` member | (file, line) **plus "blame the later one"** | the prescan registers *exactly* the Sym the emitter goes on to register — no state difference at all |

`same-definition-site` is the shared predicate for the (file, line) rows, and it
is sound because `g-source-path` is set per file around every prescan and every
load block. Two traps it encodes:

* **Blame the second definition, not the first.** G-0's prescan registers every
  form's Sym before *any* form is emitted and `scope-lookup-key` scans backwards,
  so while emitting the FIRST `defconst` the probe lands on the SECOND's prescan
  entry — the first cut reported the pair at the earlier line. A hit below this
  form in the same file is skipped; the later form finds the earlier one's
  emitted Sym when it reaches its own check.
* **The REPL is a sequence of compilation units.** `same-definition-site` answers
  "same definition" whenever `g-interactive` is set, so each definer falls back
  to *its own* pre-B4 behaviour — which matters, because four of them used to
  `return` and four used to fall through, and a shared no-op would have made
  `emit-defstruct` re-emit `%T = type {…}`. Verified by diffing a REPL transcript
  against the pre-change compiler, not by reasoning.

**A rule like this finds bugs, so budget for fixing the tree.** `name-resolution.md`
§11.1 predicted one casualty from a scan of `src/` + `lib/`; measured across
`examples/` too it was three, all the same class — two more copies of the `Node`
redefinition §11.7 removed from `lib/list.nuc`, and `examples/defmacro.nuc`
defining `when`/`unless` over the prelude's. That last one is the sharpest
illustration of why the rule is worth having: `find-macro` returns the FIRST
match and the prelude registers first, so **neither definition in that example
had ever been expanded** — the file demonstrated a macro it did not use.

## A "cannot" in a design doc may be a defect report wearing a ruling's clothes

Stage 15 B7 (`name-resolution.md` §9.7) exists because §11.6 — titled *"Why a
facade cannot re-export a type or protocol"* — was read twice as though it
settled something. It settles nothing: it is a measurement, a cause and a plan,
and its own body says *"it is not that re-export is hard for these kinds; it is
that `export` was written as a `g-globals` operation."* B3′ then went and did it
for types and protocols, which falsified the title while the title stayed.

The damage was not the stale heading. `binding-re-register`'s refusal text told
authors a macro *"is identified by a globally-unique bare name, so a re-export
would not change how it resolves (name-resolution.md §11.6)"* — a claim that
section never makes, attached to a citation that appears to authorise it. And
for macros the claim was **circular**: a macro was bare-keyed only because
macros had never been cut over to the canonicaliser, so the unfixed gap was
being quoted as the reason not to fix it. Keying `g-macros` by namespace made
the whole sentence false in an afternoon.

Two habits this argues for:

* **When a diagnostic cites a design section, check the section says it.** A
  citation is load-bearing in a way prose is not — it converts "this is how it
  works today" into "this was decided", and nobody re-derives it afterwards.
* **State the property, not the status quo.** The rows that legitimately refuse
  re-export share something real — they are *not keyed by namespace* (an
  overloaded name is merged across namespaces on purpose; a special form, a
  built-in type name and a `__fnty_N` have no owning namespace at all). That
  reason survives a registry change; "identified by a globally-unique bare name"
  was just a restatement of the gap.

And one specific carry-over for any further cut-over: **B3′ step 2's
`ns-ir-prefix`/`ir-name-token` composition is for names that are IDENTITIES.**
`StructDef.ir-name` needs it because that symbol identifies the type across the
module. A macro's `jit-name` does not: it is a private JIT symbol already made
unique by a counter, so it keeps deriving from the **bare** name, which also
keeps a `/` out of `sanitize-for-ir`'s input. §9.7 predicted the composition and
was wrong. Ask which of the two you have before copying the step.

## A generated name is rewritten for one of TWO reasons — ask which before picking the mapping

`--emit-cheader` rewrites every Nucleus name it exports, because `-` is ordinary
in a Nucleus name and illegal in a C identifier. There are two rules, and using
the wrong one is silent:

- **The linker resolves this name** (a `defn`, a `defvar`): the declaration must
  be a C identifier *and* name the symbol the object defines, which one token
  cannot be. Sanitized spelling **plus** `asm("real-symbol")` —
  `cheader-asm-label`. Sanitizing *alone* turns a header that fails to parse into
  one that parses and fails to **link**, moving the error away from its cause.
- **Nothing links against this name** (struct field, parameter, `defunion` arm,
  enum tag, `#define` constant, a typedef name): plain `sanitize-for-c` —
  `cheader-c-ident`. An `asm` label here is meaningless.

Two traps this shape has already sprung:

- **`sanitize-for-ir` mangles hyphens; `ir-name-token` does not.** `ir-name-token`
  maps only `?`→`_QMARK` / `!`→`_BANG` and passes everything else, hyphens
  included, so a link name keeps them — which is *why* the label is needed.
  `op-name-token`'s fallback is `(sanitize-for-ir (ir-name-token name))`, a
  different answer again. Three similarly-named functions, three alphabets.
- **A verbatim name in one emitter must be sanitized in lockstep with its
  definition in another.** `cheader-array-extent` exports a non-folding
  `(array T N)` length as the bare constant name on the premise that
  `emit-cheader-defconst` exports the matching `#define`; sanitizing either alone
  gives `int32_t xs[MY-LEN];` against `#define MY_LEN 4`.

And the check that actually catches a miss: sweep **all** generated headers for a
stray character rather than re-reading a list of call sites. W9 item 4's recorded
census enumerated six sites and was three short — `defconst` names, `defenum`'s
own tag, parameter names and the inline-`(union …)` members emitted from inside
`type-node-to-c` were all missing from it.

## A prescan that walks imports must derive the path the way `do-import` does

The two whole-graph prescans (`prescan-imported-types`, then
`prescan-imported-signatures`) exist so a name resolves on *reachability* rather
than import order. That guarantee is only as wide as the set of import forms they
walk, and a form they skip silently reverts to order-dependence — surfacing as
`not defined anywhere in this compilation unit` for a name that **is** in the
unit (W9 item 6).

Both passes walked the `NODE-SYM` spelling only, so `(import-use "sub/foo.nuc")`
and `(import-use foo)` named one file and behaved differently. The rule now lives
in one function, `import-form-path`, and mirrors emission: a symbol goes through
`resolve-import`; a `.nuc`/`.nuch` **string is the path verbatim**, because
`do-import`'s `NODE-STR` branch does no search either. If you add an import
spelling, add it there, or it is outside the guarantee.

Three specifics worth keeping:

- **A prescan must not be the one to report a missing file.** It runs from a call
  site with no line; `read-file` would `perror`+exit and lose the diagnostic
  `do-import` gives at the import form's own line. Guard with `file-exists` and
  stay silent.
- **Pass 1 and pass 2 do not agree about `.nuch`, on purpose.** Pass 1 walks
  headers (a header's `defstruct` is pre-registered); pass 2 skips them, because
  `emit-nuch-import-forms` already gives declares/defmethods/templates their own
  registration path and re-running the signature prescan would double-register.
  So a header's *types* resolve early and its *functions and values* do not.
- **"Registered by a prescan" is not "laid out".** Pass 1 registers struct NAMES;
  a signature may name the type before the import, a field access may not. Same
  split W1d records for cycles — do not let a test conflate them.

## An exemption is justified by the DESTINATION's capability, not the source's reputation

Phase F's non-null flow check has exactly one sound exemption on the destination
side: an **elem-less** `ptr` (`void*`) names no pointee and cannot be
dereferenced, so a non-null obligation on it would protect nothing.

A second exemption sat beside it for a year — `CStr` — recorded in
design/stage10/nullability.md §9.1 as "the direct analogue", and it was the
opposite of one. It exempted the **source**, and the destination it fed was a
typed, fully dereferenceable pointer. `(defvar g:ptr:T (as CStr null))`, the
identical local, and `(as ptr:T (getenv "X"))` all compiled clean and segfaulted
(W9 item 7). The justification given — *"a C string is a non-null constant"* — is
a true statement about a string **literal** promoted to a claim about the
**type**. When an exemption's stated reason is a property of some values of a
type, it is not a property of the type.

Two working notes from fixing it:

- **`CStr` is `TY-CSTR`, not `TY-PTR`, so `ptr-pkind` answers PTR-RAW for it and
  any check written as `(= (t kind) TY-PTR)` silently skips it.** Use
  `is-ptr-like` when the question is "does this pointer-shaped value carry a
  contract". The same trap is one `case` arm away in every pointer-kind check.
- **Fixing such a site usually means removing a false claim, not adding an
  assertion.** Fifteen of the seventeen violations were `(as ptr:i8 s)` on a
  C string being walked byte by byte; the honest spelling is `(as raw:i8 s)` —
  identical IR, and `aref`/`unsafe/ptr+` through a `raw` is the documented
  unchecked waiver. Reach for `unsafe/cast` only where the non-null claim is
  actually load-bearing, and add a runtime guard where the value comes from a
  caller (`lib/hash.nuc`'s `Hash` conformance) rather than from an internal
  registry (`src/union-registry.nuc`'s `fnv-str`).

## Tightening a rule? The corpus sweep is not the measurement — stage 2 is

Sweeping `examples/` + `lib/` + `tests/fixtures/` (366 programs) reported **zero**
changed diagnostics for W9 item 7 after one `lib/` fix. The compiler's own source
had **sixteen** violations. `make` does not catch them: stage 1 is built by the
committed `bin/nucleusc`, which predates the new rule. They appear only at
`make bootstrap`'s **stage 2**, where the new compiler compiles the compiler.

So for any change that makes the compiler reject more: run `make bootstrap` (or
just `./build/nucleusc --emit-llvm src/nucleusc.nuc`) before believing a
zero-blast-radius result. Iterating that one command is also the fastest way to
enumerate the sites — it needs no rebuild between fixes, because the rule lives
in the binary and the violations live in the source.

## An explicit conversion form must never reject what the implicit one accepts

`as` exists to write down a conversion the coercion machinery would otherwise
perform silently. So a value that `(let (a:T x) …)` accepts and `(as T x)`
refuses is not a strictness *policy* — it is the explicit form failing at its
only job, and it pushes users to `unsafe/cast` for a conversion that was
provably safe. W9 item 8: `(as i8 5)` was an error while `(let (a:i8 5) …)`
compiled and emitted the identical `trunc i32 5 to i8`.

The cause is generic enough to look for elsewhere: the safe form asked a
question about **types** (`is (int-width dst) < (int-width src)`) where the
coercion path asks it about the **value** (`int-literal-fits`). Whenever the two
paths answer with different predicates they will drift, so route both at the
same one — `Val.is-lit`/`lit-i64` is how the value path carries the answer, and
a constant folder can pass its folded value unconditionally.

Two related traps:

- **`Val.is-lit` is overloaded.** With a `StrView` type it means "unmaterialized
  string literal", not "integer literal". Read it only after the type kind is
  known (in `emit-as` the StrView case has already returned).
- **A relaxation holds the bootstrap fixed point on the first pass**, unlike the
  tightening described in the section above — nothing that compiled compiles
  differently. That makes the corpus IR sweep the strong evidence for a
  permissive change (371 of 372 programs byte-identical, the one difference
  being the new accept fixture) and stage 2 the strong evidence for a
  restrictive one. Know which kind you are making.

## `bool` is not an integer — `is-int-type` is SEMANTIC, `is-int-or-bool` is REPRESENTATION

Stage 16 C1 (design/stage16-ergonomics/bool-type-plan.md) made `bool` its own
`TypeKind` (`TY-BOOL`, singleton `ty-bool`) and took it out of `is-int-type`.
The divorce is source-level only: `type-to-ir` still answers `i1`, so no emitted
IR, ABI classification or generated header moved. `i1` is retired as a *spelling*
(`parse-type-name` names the replacement).

The split is the whole design, and it is the same shape as `is-ptr-like` vs
`is-ptr-repr`:

- **`is-int-type`** answers the *semantic* question — arithmetic, implicit
  widening, untyped-literal adoption. `bool` is absent, which is what makes
  `(+ true true)` an error (it used to be `false`, one-bit wrap) and
  `(let (b:bool 1) …)` / `(let (n:i32 true) …)` type mismatches.
- **`is-int-or-bool`** answers the *representation* question — which instruction
  to emit. `emit-cast`'s five selection gates, `emit-binop-vals`' operand gate
  and `vararg-promote` ask this one. Do not write `(= (t kind) TY-BOOL)` at a new
  site; pick one of the two predicates, and say which question you are asking.

Three consequences worth keeping:

- **`int-width` and `is-unsigned` KEEP their bool arm** (1, unsigned). They are
  representation queries, so `zext` / `icmp u*` / `uitofp` fall out of the
  existing machinery instead of needing a second copy. `is-unsigned` answering
  "signed" for bool is Stage 15 W9 item 31: `(as i32 true)` was **−1** and
  `(< false true)` and `(> true false)` were *both* false. `int-literal-fits`'s
  width-1 special case is **gone** — no integer type has width 1 any more, and
  every caller gates on `is-int-type`.
- **The bool→int widening is ONE function with exactly two callers.**
  `widen-bool-to-int` (`src/abi.nuc`, beside `coerce-int-val`) is called by
  `emit-as` step 5 and by `vararg-promote`, and is deliberately unreachable from
  `coerce-int-val` — an implicit bool→int would make `(let (n:i32 true) …)`
  compile again. `defcast` refuses bool/int pairs for the same reason: a user
  rule for that pair is picked up by `coerce-int-val`'s tail.
- **`unsafe/cast` must stay TOTAL for bool.** `as` names it in every bool
  rejection ("use unsafe/cast"), so all five `emit-cast` gates — int↔int,
  int→ptr, ptr→int, int→float, float→int — take `is-int-or-bool`. Excluding bool
  from any one of them advertises an escape hatch that does not exist.

`true`/`false` are `NODE-SYM` literals that emit `true`/`false` directly and
never reach the integer-literal predicates, so a test written only with the named
spellings exercises none of the widening rules — write one with `(as i32 b)` and
one with `%d` through `printf`.

## A value-collapsed `cond` in return position emits the zero constant, silently

`type-join` (`src/generics.nuc`) answers `ty-void` for two branches whose types
do not reconcile, so a `cond`/`if`/`if-some` in **implicit-return** position
collapses to void — and a non-void function whose body produced a void value
falls off the end and gets its return type's zero emitted for it, with **no
diagnostic**.

Stage 16 C1 hit it: `gcheck-special-form` was
`(if-some (head …) (contains? …) 0)`, a `bool` branch joined with an `i32`
literal branch. While bool was an integer the join widened; the moment it was not,
the whole function compiled to `ret i1 0` and every special form was reported as
an unknown function in a generic body. Nothing in `make`, `make test` or
`./build/nucleusc --emit-llvm src/nucleusc.nuc` said a word — only *running the
stage-2 binary* did (see build.md, "Updating bootstrap artifacts").

Generalize: **any change that narrows what two branch types will join turns
previously-widening joins into silent void collapses.** The slot positions
(`let` init, `set!`, argument, explicit `return`) all diagnose; the branch and
tail positions do not. When you narrow a join rule, build and *run* stage 2.

## A parser's null must not mean both "absent" and "malformed"

`parse-type-from-node` returned null when it could not parse a type expression.
Every caller already read null as *no annotation was written* — the other thing
it means at a type-annotation site — so `(defn f (x:(Vector i32)) …)` with the
import forgotten reported `defn: missing :type on param 'x'`, blaming the one
part of the line that is unambiguously present (W9 item 13). Five caller
positions carried the same wrong message from the one shared return.

The rule: a helper whose result distinguishes "nothing was there" from "what was
there is wrong" must not encode both as the same value. Diagnose the malformed
case *at the parser*, where the offending node and its line are still in hand;
the caller has neither, which is also why the return-type position reported
`:0:`.

Two structural traps in this area:

- **A `die-at` at the end of a `case` is the label-less DEFAULT arm, not a
  fall-through of the arm above it.** `parse-type-from-node`'s trailing "unable
  to parse type expression" reads like the catch-all for a failed parse; it is
  reachable only for a `NodeKind` outside `{NODE-SYM, NODE-CELL}`, so a
  malformed *list* — the common case — flowed past it and off the end of the
  function. Check which arm a terminal raise actually belongs to before trusting
  it to cover anything.
- **`parse-type-name` ends in `die-at`, so it cannot be used as a probe.** When
  a caller needs to ask "is this name a type?" without dying, extract the
  lookup (`builtin-type-name`) and have the resolver call it, rather than
  writing a second copy of the built-in list that will drift. Keep side effects
  like `avr-reject-f64` in the resolver — a probe must answer, not raise.

## `()` is not an empty node — it is NO node, and `(x kind)` on it is a null deref

`read-list` returns null for a zero-element list, so `()` anywhere in a program
arrives as a null `Node*` (W5f). `node-at` says so in its type — it returns
`?ptr:Node` — and nearly every caller launders that with
`(unsafe/cast ptr:Node (node-at form 1))` and then reads `kind` or `s` off it.
Every one of those is a segfault on `()`, which was W9 item 45: twenty-three
shapes across the three modes, from `(defstruct ())` to `(ns ())` to
`(defenum E A () B)`.

**Use the null-safe accessors, which is what they are for.** `lib/node.nuc` has
three: `node-line` (borrows the enclosing line), `node-is-list`, and — since
item 45 — `node-kind`, which answers `NODE-NIL` (−1, deliberately outside
`NodeKind`'s range) for a null node. Write `(= (node-kind x) NODE-SYM)`, never
`(= (x kind) NODE-SYM)`, for anything that came out of `node-at`. Same for the
line in a `die-at` argument: `(node-line x (encl line))`, not `(x line)` — the
argument is evaluated before the call, so a `die-at` whose *line* dereferences
the node crashes on exactly the input it exists to diagnose.

Two things this makes easy to get wrong:

- **The message you need is probably already written.** Almost every position
  that can be spelled `()` already refuses a name of the wrong kind — `ns:
  namespace must be a symbol`, `defenum: value must be symbol`, `import: name
  must be a symbol or string path`. `()` deserves that same message, and
  substituting `node-kind` is what lets the existing test raise it. Reach for a
  new diagnostic only where the position has none (a `defn` name, whose
  fall-through quoted the null as `'(null)'`).
- **A prescan must SKIP, not die.** `prescan-struct-names` and friends already
  ignore every name kind they cannot use; `node-kind` makes a null one more of
  those, and the emitter still diagnoses it in source order. See "A prescan is
  DELIBERATELY permissive" above — and remember its consequence: if the prescan
  stops crashing, a header mode that runs no emitter goes *silent* rather than
  refusing, which item 38 rates as worse than the crash. Fixing a prescan crash
  means re-asking the question in `validate-header-forms` in the same breath.

## An IR type written as a literal in a format string is a target assumption in disguise

`aref`, `aset!` and `unsafe/ptr+` each ended their emission with

```
"  %s = getelementptr inbounds %s, ptr %s, i64 %s\n"
```

That `i64` is not punctuation — it is the claim "the target's pointer-sized
integer is 64 bits", stated somewhere no target audit will grep for. On AVR
(pointer-int `i16`) the annotation names a register the compiler defined as i16
and the LLVM parser refuses the module outright: `'%t1' defined with type 'i16'
but expected 'i64'`. **Any width baked into an emitted-IR string literal —
`i64`, `align 8`, a size, an index type — belongs behind `ptr-int-ir` /
`ptr-int-type` / `abi-sizeof` unless it is genuinely fixed by LLVM** (a struct
field index in a GEP really is always `i32`).

The louder lesson is about where such a rule lives. AVR-1 had already found this
exact bug and fixed it — in `emit-ptr-add` alone, because the auto-emitted
node/arena runtime uses `unsafe/ptr+` and so it stood between AVR and every
program. `aref`/`aset!` are user-facing, no AVR example reached them, and their
identical copies survived for two more stages (W9 item 15). **When a fix is a
*rule* rather than a repair, extract it and convert every asker in the same
change** — here `gep-index-ir`, one function, three callers.

Two things this class does to hide:

- **Half of it parses.** An index *narrower* than the pointer was widened to a
  real i64, which is well-formed, `llc` legalizes it, and it emits 64-bit
  software arithmetic on an 8-bit MCU. A gate that only asks "does the IR
  parse?" is blind to it — assert the absence of the wrong width too, not just
  the presence of valid syntax.
- **A workaround can be committed in an example and keep the suite green.**
  `examples/avr-global-init.nuc` carried `(unsafe/cast i64 …)` on its index,
  with a comment naming the defect, so `make avr-test` passed over a broken
  `aref` for two stages. A cast in an example that exists to satisfy the
  compiler is a bug report; delete it as part of the fix and let the gate run.

Host evidence and target evidence point opposite ways here, and it is the host
that must not move: on LP64 `ptr-int-ir` is `"i64"`, so a correct fix to this
class is **byte-identical everywhere on x86-64** and the corpus sweep showing
zero diffs is the proof the change is confined to the targets it was for.

**Width was only half the rule.** `gep-index-ir` then widened everything with
`sext`, so an unsigned index with its high bit set addressed *backwards* (W9
item 32; fixed 2026-08-14 by asking `is-unsigned`). Extracting a rule into one
home does not make the rule right — it makes the next correction one line. If
you are writing a conversion, the two questions are always **how wide** and
**which sign**, and answering one of them in a shared helper is exactly the
moment the other looks answered too.

## Removing a silent fallback: budget for the casualties to be the COMPILER's bugs

`emit-call-with-args`' coercion loop called `safe-coerce-val` and discarded a
null return, with a comment saying so. Turning that into a `die-at` (W9 item 33)
is five lines, and the interesting part is what the corpus then rejected:
**three programs, none of them a wrong call.** Two were `(dyn P)` method calls
exposing a dispatch defect (item 41, next section) and one was an *example whose
stated purpose was to demonstrate `defcast`*, calling `(show-ptr 0)` under the
comment "defcast fires: i64 → ptr" — it never had, because a bare literal is
`i32` and a rule is keyed on the exact pair (item 42).

So the rule: a silent pass-through does not only hide the *program's* bug, it
hides the *compiler's*, and it hides them in the places you are least likely to
look — a committed example, a green fixture. When you switch one on, read every
new rejection as a possible compiler defect before "fixing" the source, and
budget for the fix to grow: item 41 had to be repaired in the same change,
because leaving it would have made canonical `(dyn P)` code stop compiling.

Two riders:

- **Check the sibling slots before ruling.** The question "should this be an
  error or a new coercion?" is already answered by `let`, `set!` and `return` if
  the same pair reaches them. `(let (a:f64 3) …)` was `let: init type mismatch`,
  so the argument position was the outlier and item 33 is a consistency repair,
  not a new rule. Had `let` accepted it, the fix would have been the coercion.
- **The compiler is a poor witness for a call-site defect.** Its own calls are
  type-correct, so a swallowed failure never had anything to swallow — the
  bootstrap held on the first pass and no `boot/` artifact moved. Self-hosting
  gates what the compiler *does*, never what it *tolerates*.

## `(dyn P)` dispatch was keyed on the CONFORMER COUNT — a solitary method never reaches `emit-generic-call`

Stage 13 TE-6 put the boxed-receiver vtable forwarding inside
`emit-generic-call`. A method with **one** conforming type is not a `Generic` —
it stays a solitary `defn` — so `(m box)` took the ordinary call path and passed
the `{data,vtable}` fat pointer straight to the concrete method (W9 item 41,
fixed 2026-08-14 by hoisting the same three pieces — `dyn-canonical`,
`dyn-method-slot`, `emit-dyn-forward` — into `emit-call-with-args`, where the box
is still a first-class aggregate).

The general form is worth more than the instance: **anything you attach to the
overloaded-call path is invisible to a one-implementation name.** Adding a
second conformer changes which emitter runs. When you add a rule to
`emit-generic-call`, ask what the solitary path does with the same input — and
vice versa, since the two now both forward and must keep agreeing.

- **A receiver-only method cannot witness a fat-pointer ABI bug.** SysV puts the
  box's `data` word in the first integer register, so a callee expecting
  `(ref Self)` reads it correctly and returns the right answer. Give the method
  **one more parameter**: the vtable word takes the register that argument
  wanted, and `(add-k b 5)` computes `100 + <vtable address>`. That is the whole
  design of `tests/fixtures/w9-dyn-solitary.nuc`, and it is the same shape as
  W9 item 32's "keep both addresses mapped" — construct the case where being
  wrong is *observable*, because the natural one is accidentally right.
- **Matching a qualified name against a bare-keyed table needs the qualifier
  CHECKED, not dropped.** A protocol declared inside `(ns …)` stores its sigs
  bare, so `(wx/describe b)` matched no slot. `strip-ns-qualifier`'s own comment
  says not to re-extend it to a resolution position — the way through is to
  compare the qualifier against the *protocol's* namespace first
  (`same-ns-qualifier`) and only then strip. A blanket strip would dispatch an
  unrelated namespace's same-named function through this vtable.

## A guard that compares LOWERED types asks a question the language never asked

`emit-call-with-args` decided whether to coerce an argument with
`(!= (strcmp (type-to-ir (slot type)) (type-to-ir ptype)) 0)`. That is not "are
these the same type", it is "do these print the same in the IR" — and `ptr`,
`ptr:T`, `CStr` and `(fn …)` all print `ptr`. So no pointer-flavour mismatch was
ever checked, and a `CStr` reached a function-pointer parameter (W9 item 34;
fixed 2026-08-14 by asking `type-eq` instead). The rule: **`type-to-ir` is for
emission, `type-eq` is for decisions.** A comparison on lowered forms silently
inherits every distinction the lowering throws away, and pointers throw away the
most.

Two riders, both from the same fix:

- **A widened guard needs an answer, not just a question.** Once `type-eq` let
  the pointer pairs through, `safe-coerce-val` had to say `CStr`↔`ptr` is free
  and `null`-into-a-fn-slot is allowed — which `coerce-int-val` had known since
  item 20. The fix was to delegate to it (`safe-coerce-val`'s final
  `(return null)` became `(return (coerce-int-val v target line))`), not to
  restate the rules. If a position has its own coercion entry point, expect the
  ruling you need to already exist at the shared one.
- **The IR-string guard hid a second distinction: sign.** `i32`/`ui32` print the
  same, so an argument never reached the literal range check every other slot
  performs, and `(take-ui32 -1)` silently passed `4294967295` while
  `(let (a:ui32 -1) …)` had always been an error. When you fix a lowered-form
  comparison, enumerate *every* distinction the lowering erases, not the one in
  the bug report.

**Gate it with a parity assertion, not a list of messages.** The claim these
items make is that the argument position is the one typed slot not asking what
`let` asks. `run_w9_fnslot_arg` compiles each spelling in *both* positions and
requires the verdicts to agree **and** to match the expected one — parity alone
would still hold if both positions regressed to accepting everything. A future
rule change then moves both together or fails loudly, which a hardcoded list of
diagnostics cannot do.


## An idempotence skip needs a discriminator, and the honest one is often PROVENANCE

`nuch-declare-import` skipped a declaration whose name was already bound, for
idempotence — *"already defined (e.g. from include or c-include)"*. A diamond
import genuinely needs that. What it could not distinguish (W9 item 36) was a
re-declaration of the **same** function from a **different** function that
happens to share the name, so a `.nuch` entry naming a function the importing
unit also *defines* was dropped whole — no `g-globals` binding, no LLVM
`declare`, no generic method — and a **qualified** `(lib/helper 3)` silently
called the unit's own `helper`, at whatever type that one had.

**The intuitive discriminator — compare the signatures — is wrong here, and it
passes both of the usual gates.** It survived 396 corpus programs at 0 diffs and
a byte-identical bootstrap. It still broke `w1-declare-cycle-breaker`: W1e's
cross-file `(declare f …)` is a declaration of a function the unit *does*
define, and being a no-op is its entire job. Worse, the pre-existing test that
had *recorded* this defect (`run_w9_nuch_import_order` case 5, written while item
29 was fixed) uses **identical** signatures on both sides — so a signature test
cannot see the case at all.

What actually separates them is where the declaration is written:

* a top-level `declare` in a **`.nuc`** — a forward declaration *of* this unit's
  own function; must stay a no-op;
* an entry in a **`.nuch`** — some *other* unit's exports; a name this unit
  defines is a conflict.

And that holds by construction, not by luck: **`--emit-nuch` never re-exports a
top-level `declare`** (verify before relying on it — one command), so a header
entry can never *be* such a forward declaration. A second question — does this
unit `defn` the name, which only a body can answer — keeps the libc diamond
silent.

Two transferable rules. **When a skip means "this is the same thing", name the
property that makes it the same thing and test that property directly**; a proxy
that merely correlates (here: the signature) will admit the case the proxy cannot
express. And **a green corpus sweep plus a green bootstrap is not sufficient
evidence for a rule change** — neither reaches the generated multi-file fixtures
in `tests/suite-imports.nuc` and `tests/suite-modules.nuc`, which is where
cross-file rulings actually live. Run the
suite before believing a resolution change is inert (see "Tightening a rule? The
corpus sweep is not the measurement — stage 2 is", of which this is the
cross-file half).

**A characterization test is a defect report, not a specification.** Case 5 above
was labelled *"item 36's behaviour, unchanged"* — it existed to pin the status
quo while a neighbouring item was fixed. When the item it names is the one being
fixed, the test is the thing to *invert*, and its comment is the best available
statement of what the fix must achieve. Grep the progress table's item number
before assuming a passing test endorses what it asserts.

## Provenance fields are written at EMISSION, so a non-emitting mode sees null

`StructDef.src-file` / `src-line` are documented as "source file where defined",
and every writer of them is a definition-time writer (`emit-defstruct`,
`emit-defunion`, the closure/anon/dyn-box minters, the C-header parser).
`--emit-cheader` and `--emit-nuch` run the *prescans* and then emit no struct at
all, so in those modes the field was null for **every** type — including the
file's own. Any question of the form "which unit does this come from?" is
therefore unanswerable there until the pre-registration site records it too
(W9 item 37 added it to `prescan-struct-names`, where `prescan-imported-types`
has already swapped `g-source-path` across the file boundary, so an imported type
carries its own file's path with no extra plumbing).

Two things follow. **Probe the field before designing on it** — the whole first
design for item 37 assumed provenance was available and the probe printed
`src-file=(null)` ten times. And **check who reads it before writing it earlier**:
here the only pre-existing consumer (`reject-opaque-type`) reads it solely for
`opaque` StructDefs, which only the C-header parser mints and which already set
it — which is why recording it at pre-registration moved 0 diagnostics across 396
programs. Had a consumer read it for ordinary types, filling it in earlier would
have changed messages.

## A prescan is DELIBERATELY permissive — so a mode that runs prescans and no emitter inherits none of the diagnoses

The sibling of the rule above, and the more dangerous one. Provenance being null
in a non-emitting mode is a *missing answer*; validation being absent is a
*missing refusal*, and the failure mode is a crash or a confident wrong output.

The compiler has two validation layers and the deferral between them is
deliberate, documented, and correct — for `--emit-llvm`:

| prescan | what it tolerates | its own comment |
|---|---|---|
| `defn-params-to-types` / `defn-params-count` | a NULL (`()`) parameter | *"the located diagnostic is emit-defn's job"* |
| `prescan-defn-signatures` | a `defn` of fewer than 4 nodes (skipped silently) | — |
| `prescan-file-imports` | an import that resolves to nothing | *"a missing library is diagnosed by `do-import` … Staying silent here keeps one diagnosis"* |

`--emit-cheader` and `--emit-nuch` run the first layer and never the second, so
**nothing downstream ever asks**. Before W9 item 38 that was three SIGSEGVs with
no output at all (a missing return operand, an empty-list parameter, an
empty-list inline-union member — each a raw `(node-at form N)` deref on a shape
the prescan waved through) and one silent wrong answer (an unresolvable import
exited 0 and printed a header describing a unit the compiler could not see).
`--emit-nuch` was the worse half precisely because it did *not* crash: it
`print-node`s a parameter rather than walking it, so it wrote
`(declare foo ((x i32)))` — a declaration with no return type — for a program
that does not compile, and that file gets committed and linked against.

Four things follow.

**Adding the prescans to a non-emitting mode does not make it strict** — it adds
the layer that defers. Item 26 gave `--emit-cheader` the real prescan sequence
and closed 29 of these; the remainder were structurally out of its reach.

**The refusal scope must be stated, because "refuse whatever the compiler
refuses" is not implementable here.** The line that *is*: a non-emitting mode
refuses every program whose **declarations** the real pipeline refuses. A body
error is out of scope by construction — no body is read — and closing it would
mean compiling the unit twice. Measure the residue rather than implying there is
none: 136 → 133 disagreements over the 396-program corpus, all 133 body errors.

**Never re-copy the message.** Route each check through the chokepoint that owns
it — `die-empty-decl` split out of `extract-name-and-type`'s null arm,
`die-import-not-found` shared with `do-import`'s two call sites, and nine
`require-<head>-form` guards each moved verbatim out of the top of its own
emitter (`emit-defvar`, `emit-defconst`, `emit-defenum`, `emit-defstruct`,
`emit-defunion`, `emit-defmacro`, `emit-defcast`, `emit-extend`, `emit-defn`),
which now call them. Then identical output is a property of the construction. The
corresponding test asserts stderr **equality between the modes**, never a quoted
string — a copied message drifts and a quoted assertion does not notice.
(`emit-deferror` is the one to leave alone: its guard `report-at`s and returns
`!i32` instead of dying, a different contract.)

**Probe the set of POSITIONS that never ask, not the set of bug reports.** This is
the part that cost a rewrite. Item 38 named three crashing fixtures; a fix that
closed exactly those three passed 644 tests, a byte-identical bootstrap, 69/69
headers and a 0-diff 396-program corpus sweep — and was still substantially
wrong. Probing every head the header emitters dispatch on found **ten** crashing
shapes, including a truncated form of five different definers and an inline
aggregate reached through a pointer, an array or a `defvar` type rather than a
struct field (the first walk inspected only the *outermost* head of a type node).
When the defect is "this pass never asks", the corpus cannot scope it: the corpus
only contains shapes somebody already wrote down.

Two skips keep such a walk from being *stricter* than the compiler, which is the
only way it can do harm: a bounded-generic template (its body is checked when a
call site stamps it) and a parametric `defstruct` (its fields are checked at
stamp time). Both are predicates the emitters already skip on. The gate that
proves no over-reach is `make check-headers` — 69/69 unchanged means every real
library still emits an identical `.nuch` *and* `.h`.

## A pre-pass that mirrors an emitter must mirror its SKIPS, not just its walk

When output ordering forces a discovery pass before emission (item 37: the
`#include` lines must precede the first use of what they complete), share the
*rendering* — call the emitter's own `type-node-to-c`, so the answer cannot
drift — but the "is this exported at all?" decisions have to be replicated by
hand. Miss them and the pass discovers dependencies of things that are never
emitted: `lib/vector.h` and `lib/combinators.h`, which spell no `struct`
anywhere, took includes for a parametric `defstruct`'s field and a generic
template's return type. The four that mattered were `defn-is-generic-template`, a
non-`NODE-SYM` name node (parametric head), `cheader-template-instance` and
`cheader-mentions-closure` — plus simply not walking the `-` (private) heads,
which `emit-cheader-header`'s dispatch does not list either.

The tell is quantitative and worth measuring deliberately: the change touched 10
generated headers before the skips and 5 after, and 5 is the number that
independently name a type they do not define. "Roughly the imports" and "exactly
the references" look the same in a passing test suite.

## A generated C header that COMPILES can still be unusable

`clang -fsyntax-only` over a generated header under-reports, because C requires a
complete type only where a value is formed. Before W9 item 37, `lib/strview.h`
passed that check while declaring `_Bool eq_StrView_StrView(struct StrView a,
struct StrView b)` over a tag nothing defines — the declaration parses and no
caller can ever write the call. Only `lib/string-split.h`, which used the type in
a by-value *field*, failed outright.

So test the two separately: parse the header, **and** form a value of every type
it names. The cheap static version of the same question is "which `struct X` does
this file name without a `struct X {` of its own?", which found seven headers
where the compile test found one. The same asymmetry is why item 44 (`!T`
signatures exported as `struct _BANGT`, a tag the emitter never defines) sat in
five committed headers unnoticed.

Item 44 added the converse trap on the *skips* section above: `emit-cheader-declare`
refuses a whole declaration on any ONE of its signature positions, which a
per-type-node pre-pass structurally cannot see — it will happily record a
dependency for the surviving parameters of a declaration that is never emitted.
Ask the refusal question once, of the whole form, and let both callers read the
answer: `cheader-defn-skip-reason` returns a reason *code*, the emitter maps it to
the comment it prints, the pre-pass only tests it against zero. Replicating four
predicates by hand in two places is the drift; one function with two readings is
not.

Stage 18 TF-4 found the two remaining holes in that shape, both from the same
first Nucleus library with a **callback field**. (1) `cheader-niche-no-c` unwrapped
`ptr`/`ref` and nothing else, so a `!T` nested inside a `(fn RET)` — the return of
a function-pointer parameter — was never asked about, and `test-register` exported
`struct _BANGvoid (*f)(void)`. A refusal predicate must look through **every type
constructor that can carry a type**, and the fn-pointer node's shape (`(fn RET)`
alone, or `((fn RET) (P…))` when it has parameters) is exactly the one
`cheader-fn-head-node` already spells for the renderer — use it, do not re-derive
it. (2) `emit-cheader-defstruct` asked *no* representability question at all: a
struct is not a declaration, so it never went through `cheader-defn-skip-reason`,
and it rendered whatever `type-node-to-c-decl` produced. It now refuses the whole
struct, because dropping only the offending field would hand C a layout that
silently disagrees with Nucleus — the same ruling item 44 made for declarations.
The general form: **every emitter that writes a type is a refusal site, and the
`_BANG`/`_QMARK` tag check in `tests/suite-cheader.nuc` is the only thing that finds a missed
one** — `check-headers.sh` does not, because an undefined tag behind a pointer is
legal C.

## `define i64 @f(...)` is not evidence that the return type is a scalar

SysV coerces a small by-value struct into registers, so an 8-byte
`{i32 tag; union}` returns as a plain `i64` in the IR — indistinguishable at a
glance from a genuinely scalar return. W9 item 44's row was filed on exactly that
misreading ("`!ui8` is a niche-encoded scalar, not an aggregate"; the fix was
right, the reason was not). The check that settles it costs one command: declare
the struct shape you believe in from C, link against the committed object, and
print the fields — `struct ResU8 {int32_t tag; uint8_t v;}` reads `tag=0 v=65`,
which no scalar return could produce.

Corollary for header emission: a value being *expressible* in C is not the same
as the emitter having a spelling to emit. `!T` is expressible and still cannot be
declared, because it is a `(Result T Err)` template instance and no typedef is
generated for one.

## A sugar spelling escapes a ruling keyed on the desugared shape

`cheader-template-instance` refuses any type whose `NODE-CELL` head is a
registered union template, and has since Stage 11. `!ui8` is a
`(Result ui8 Err)` — but it reaches the emitter as a `NODE-SYM`, so the cell test
never fires and it fell through to the "assume struct" arm three functions away.
The header ended up with two different answers for two spellings of one type, and
they shipped side by side in `lib/strview-str.h`:
`/* byte-find: uses a defunion-template instance type; not exported */` two lines
above `struct _BANGui8 byte_at(...)`.

When adding a sugar spelling, grep for the predicates that key on the shape it
desugars *from*, not just the ones that build it. The same shape is why W9 items
3 (`usize`) and 25 (`Char`/`Err`) existed: two renderers, one type, two answers.

## Hoisting a registration means splitting its definer, and the split line is "does it write IR?"

Stage 15 W9 item 40 moved struct and union LAYOUTS into the prescans, the way W1a
moved signatures and W8 G-0 moved value names. The shape that made it tractable
is worth copying whenever the next registration is hoisted:

- **Split the definer at the IR boundary, not at the diagnostic boundary.**
  `emit-defstruct` became `defstruct-fill-layout` (parse the fields, call
  `struct-set-fields`) plus four lines that print `%Name = type {…}` and set
  `emitted`. The prescan calls the first half and the emitter calls both, so
  **every type line stays exactly where it always was** — which is what keeps a
  program's IR unmoved and made the corpus sweep a set-equality check rather than
  an argument. Everything the emitter still owns (`guard-name-kind`,
  `check-ir-name-legal`, the redefinition probe, privacy) stayed with it.
- **The shared half needs a `strict` flag, and the permissive branch ABANDONS
  rather than degrades.** A layout must be exact or absent: a provisional one
  gives the enclosing struct a wrong size, which is a miscompile, not a warning.
  So the prescan returns null (leaving `laid-out` 0) on anything it cannot settle
  — a missing `:type`, an opaque C field, an unfoldable array extent — and the
  emitter then asks the same question with its own words and its own line. That
  also means **no diagnostic moved**: the prescan raises none of them.
- **A `ref`-returning parser cannot report "not settled" — use a one-way flag.**
  `parse-type-from-node` returns a non-null `ref:Type` three frames down, so
  `g-array-ok` gained mode 3 ("fold if you can, else arm `g-layout-defer`") and
  `defstruct-fill-layout` reads-and-clears it. Mode 3 also defers on a length
  that folds to something the emitter would *refuse*, so no rejected layout is
  ever registered.
- **The definer's own no-op guard must be re-keyed on the half only IT does.**
  `emit-defunion` returned early whenever a `UnionDef` for the name existed —
  correct while it was the only producer, and "constructors are never emitted"
  the moment a prescan produces one. The new key is `UnionDef.ctors-emitted`,
  exactly as `defstruct` keys on `StructDef.emitted`. Grep for every
  already-registered? early return before hoisting a registration past it; this
  is the same trap `name-existing-kind` fell into for W8 G-0.
- **Layouts want a POST-order walk, and the three passes above them stay
  pre-order.** A field's `(array T N)` extent is a constant expression, so a
  file's layouts need its own and its imports' `defconst`s already registered.
  `prescan-imported-signatures` therefore runs layouts *after* it recurses, and
  `emit-toplevel-forms` runs the root's after the whole-graph walk. Nothing else
  a prescan registers depends on a layout, so nothing pre-order needs is lost.

**Where it stops, and why the line is where it is.** A `defmacro` was the third
thing on item 40's list and it is *not* hoistable by this technique: defining a
macro runs full codegen into a fresh JIT module and materializes it, so
"registering" one IS emitting one — there is no half that writes no IR. The
`.nuch` spelling of a `defunion` was left out for an unrelated reason —
`emit-defunion-import` keyed the registry on the BARE name while `emit-defstruct`
(and every other definition-side probe, per B3′) keys on `qualify-name`, so a
prescan using the canonical key would file a namespaced header's union where its
own importer never looks. **Fixed as W9 item 46 (2026-08-15), and the hoist was
three lines after that, as predicted**: `prescan-union-layouts` now runs in
`prescan-nuch-signatures` beside `prescan-struct-layouts`, and the importer's
skip moved from "a UnionDef exists" to `ctors-emitted` — for the header path that
flag means "the arm `declare`s are in the stream", and keying it wrongly drops
them (link failure) or repeats them (invalid IR), so test a diamond import.

**B3′'s rule needs re-checking at every *second* implementation of a definer, not
just the first.** "A definition-side existence probe holds a KEY" was written
down, obeyed by `emit-defunion`, and stated in a comment directly above the lines
that split key from spelling — *and* the `.nuch` twin of that same definer, one
`case` arm from an `emit-defstruct` that does it correctly, used the source
spelling for both for its whole life. It survived because under `user` the key
and the spelling are the same string, so all 69 generated headers and every test
exercised the path in agreement; only a `(ns …)` header separates them. When a
form has two emitters (`.nuc` and `.nuch`, or emitter and REPL), the invariant
audit is per emitter. And note which half is safe to leave bare: what
`union-ctor-form` builds is *source* re-parsed in the current file, so it takes
the SOURCE spelling and the qualification happens downstream — passing it a key
would be the mirror-image bug.

## A "safe conversion" question has two answers, and only one of them is a chokepoint

W9 items 42/47 (`design/stage15-stress-test/implicit-conversions.md`). The
`defcast` registry was consulted from exactly one function, `safe-coerce-val`,
and exactly two code paths call it — the call-argument loop and `as`. Every
other typed slot (`let`/`with` init, explicit and implicit `return`, `set!`/
`.set!`, `aset!`, struct-literal field, union payload) calls `coerce-int-val`
instead, which knows every *built-in* conversion and nothing about the user's.
A rule was therefore refused **on its own exact registered pair** at seven of
nine positions, and the surface symptom looked like a literal-typing problem
(item 42's original framing) rather than a missing-lookup one.

- **Two coercion functions, and the difference is who they serve.**
  `coerce-int-val` (`src/abi.nuc`) is the chokepoint every typed slot funnels
  through; `safe-coerce-val` (`src/nucleusc.nuc`) is a call-site wrapper that
  short-circuits on equal type *kinds* and then falls through to it. Do not
  "simplify" a slot by routing it through `safe-coerce-val`: that kind-equality
  short-circuit would let a `(ptr Foo)` value initialize a `(ptr Bar)` binding.
  Anything that should apply to **every** implicit position belongs at the tail
  of `coerce-int-val`, after the built-ins, where a `null` return means "the
  caller is about to die anyway" — that placement is what makes such a change
  provably additive (0/365 corpus programs changed IR).
- **Only the FINAL fallthrough means "nothing applies."** `coerce-int-val` has
  earlier `(return null)`s that are deliberate refusals of a specific pair (a
  StrView into an unrelated by-value struct). Extending "no conversion found"
  behaviour must attach to the last line, not to every null return.
- **A note must follow its error, and `die-at` is `noreturn`.** Stage the text in
  a global (`g-diag-note`) that `die-at`/`report-at` render and clear, exactly as
  `g-mono-context` already does. The defvar must sit above the file that *reads*
  it (`nucleusc.nuc:329`, read by `reader.nuc`). Nesting a second `fmt-*` call
  into the `die-at` argument is safe on its own terms — the helpers `alloca`
  per-call buffers, they do NOT share one — but it makes every raising site know
  the note's wording.

**A forward up-call into `nucleusc.nuc` from an earlier-inlined file resolves —
re-measure before believing otherwise.** Two comments in this file (the
`reject-opaque-type` entry) and one in `coerce-int-val` itself state that a call
from an earlier import up into a later one is "an unresolved cross-import
forward reference". That is not what the compiler does now: `union-registry.nuc`
(inlined at `nucleusc.nuc:1038`) up-calls `intern-str` (defined at 3873), and
W9 item 47 up-calls `coerce-via-cast-rule` (~3220) from `abi.nuc` (1036) — both
compiled by the **committed boot compiler** on the first attempt, because the
signature prescan registers a `defn` long before any body emits. The affected
comments predate that prescan. Their *code* is still fine (spelling a `type-eq`
rule inline is correct, just not forced); what is stale is the reason. If an
import-order constraint is the deciding factor in a design, test it with one
call rather than inheriting the claim — this is the third documented case in
this stage of a hand-written ordering note going stale (see also `toplevel.md`'s
cycle table, W9 item 40).

## Compiling a function mid-emission: the worklist answer has an exception, and it is `push-function-state`

"Emitting a function mid-emission needs the worklist, not a direct `emit-defn`"
(above) is the rule for a *program* function: register now, queue the body,
drain when no emission is in progress. Stage 16's `macrolet`
(design/stage16-ergonomics/macrolet.md) is the case that rule cannot serve — a
lexically scoped macro must **exist before the body it scopes over is emitted**,
so there is no later drain to defer to.

The answer is `push-function-state` / `pop-function-state` (`src/scope.nuc`,
deliberately adjacent to `reset-function-state`), which snapshot the per-function
codegen state into an `FnState` and restore it after the nested compilation. The
push **snapshots only** — the nested emission calls `reset-function-state` itself,
and resetting in both places opens a memstream pair nothing ever closes. Three
things generalize:

- **The inventory is larger than `reset-function-state`.** It also needs the
  three ambient argument-register globals (`g-abi-gpr-left` / `g-abi-fpr-left` /
  `g-abi-varargs` — see "Argument-register state is AMBIENT"), because a
  `macrolet` in *argument* position sits mid-argument-walk, plus `g-want-type`
  and `g-form-line`. `g-out` / `g-decl-out` / `g-qq-used` / `g-macro-decls` are
  saved by the body compiler itself. The test that catches a miss here is a call
  with by-value struct arguments of both ABI classes *and* the nested form in an
  argument slot; nothing smaller observes the budget.
- **Adjacency is the anti-drift mechanism.** The pair's only real risk is a
  global added to `reset-function-state` and not to it. Putting all three
  functions in one block makes that visible at the point of the edit; a
  save/restore living next to its *caller* would not.
- **It beats hoisting because of the nested case.** The alternative — a pre-pass
  that compiles every `macrolet`'s macros before its enclosing top-level form
  emits — cannot express `macrolet` *inside a `defmacro` body* (one macro JIT
  module compiled while another is compiling), needs node-identity keying, and
  cannot see a form produced by a macro expansion. Re-entrancy with an explicit
  snapshot was smaller and had no such holes.

## One flag answering two questions: `g-qq-used` and the node constructors

A macro/CT JIT module resolves `@alloc-node` / `@make-cell` / `@intern-symbol`
against the **running compiler**, so it must `declare` them. That was gated on
`g-qq-used` — which `emit-qq-list` sets. But `emit-quote-tree`, reached by a
plain `'x` **and by a quasiquote of an ATOM** (`` `1 ``, `` `foo ``), emits
exactly those calls and never touches the `__cons`/`__append` helpers
`g-qq-used` is actually about. So `` (defmacro one () `1) `` emitted
`call ptr @alloc-node()` into a module that declared nothing, and died in the
IR parser. Latent since macros existed; `macrolet` made it the common case,
because a one-atom body is what a small local macro looks like.

The fix is the general shape: when a flag's name describes a *mechanism*
(`qq`) but its readers ask a *capability* question ("does this module need the
node constructors?"), split it. `g-node-ctor-used` gates the three constructor
declares; `g-qq-used` keeps gating the helper *definitions* and `@malloc`,
which only they need. Both are per-module (saved/reset/restored around each CT
and macro body). The program module is unaffected by either — it *defines* all
three — which is why the whole class is invisible outside a JIT module and why
the fix is IR-inert.

Stage 20 part two (quasiquote levels) added a **second setter**: `emit-qq-tagged`
builds the cells for a level-≥2 `(unquote X)` / `` `X `` without going through
`emit-qq-list`, so it sets `g-qq-used` itself. A new `__cons`/`__append` emission
site anywhere must do the same, or the helper it calls is never defined.

Related, same change: hand-written `declare` lines in a JIT module must go
through `macro-jit-declare-raw`, which shares the `g-macro-decls` dedup set with
`macro-jit-ensure-decl`. A macro body that both quotes *and* calls a node
constructor by name would otherwise emit two `declare`s for one symbol, which
LLVM rejects.

## A null-check is not a kind-check — `Node.s` is null on every non-symbol node

`(defmacro m (5) …)` segfaulted the compiler for its whole life. The `:rest`
scan null-checked its parameter node and then read `(vp s)`, and the `=` beside
it is a **content** compare — so an INT node's null `s` reached
`strcmp(null, ":rest")`. The comment directly above the loop already promised
the located "param must be a symbol" diagnostic that the crash pre-empted; the
guard for `()` (a NULL *node*, W5f) had been added without noticing that a
*non-null node of the wrong kind* is the same hazard one field deeper.

Whenever a walk reads `Node.s`, the guard is `(= (n kind) NODE-SYM)`, not
`(!= n null)`. Same for `Node.i` / `Node.car` / `Node.cdr` against their own
kinds. Found via `macrolet`, fixed once in `macro-parse-params` — the parameter
parser extracted so `defmacro` and `macrolet` share it, which is what made one
edit fix both definers.

## A REPL arm that compiles anything needs `open-module-streams` first

A user `defmacro` typed at `nucleusc -i` aborted the session with
`Fatal error: glibc detected an invalid stdio handle`. Between REPL forms the
module streams (`g-type-stream`/`g-decl-stream`/`g-def-stream`) are **closed**;
`repl-eval-form`'s `defn` and `compile-time` arms open a fresh set first, and the
`defmacro` arm did not — while the macro body compiler opens by flushing two of
them.

The tell that this class hides well: the prelude's own macros load through
`repl-preload-prelude`, a different path, so the REPL could expand `when`,
`dotimes` and `->` perfectly while dying on the first macro a user wrote. When
adding a `repl-eval-form` arm, ask whether the emitter it calls writes to a
module stream — and if so, open one, as its neighbours do.

## A transitive import is an undeclared dependency, and only shows up when the middle is removed

Stage 16 dropped `(import-use node)` from `lib/prelude.nuc`. `lib/node.nuc`
imports `lib/arena.nuc`, which imports `stdio.h`, `stdlib.h` and `string.h` — so
for as long as the prelude carried node, **every program in the tree was handed
`printf` and `malloc` for free**. Twelve examples, seven fixtures and several
inline harness fixtures used one without importing it,
and all nineteen broke the moment the middle of the chain went away.

Nothing about the change touched libc. Expect this shape whenever an import is
removed or a library is split: the diagnostics that appear name symbols with no
apparent relationship to the edit, because the edit deleted a *path*, not a
declaration. Reading the removed library's own imports predicts the whole set.

The same reasoning applies before adding one: an `(import-use x)` added to a
widely-imported library silently widens what every consumer can spell, and the
day it is removed is the day that becomes visible.

## Redirecting an emission stream falsifies every "already emitted" latch

`import-ct` (Stage 16) discards a library's definitions by pointing
`g-def-stream` at a throwaway memstream. The first attempt redirected the
declaration stream too, and `lib/arena.nuc`'s own `defmacro` then JIT'd a
`call @malloc` into a module whose `declare` had been thrown away.

The cause generalizes past that one flag. The compiler keeps a family of
booleans meaning *"this line is in the module, do not write it again"* —
`g-malloc-decl-done`, `g-trap-declared`, `g-boxdrop-emitted`, `g-nuch-registered`,
`g-mono-drained` (and, until Stage 16 R4, `StructDef.emitted`). Every one of them
is a claim about a buffer. Point that buffer somewhere else and the claim is
false, and the symptom lands far away: in a *different* module, at a line nobody
edited.

Two rules that follow:

* **Redirect the narrowest stream that achieves the goal.** Types and declares
  cost nothing at run time, so `import-ct` sends only definitions to the sink and
  every latch stays truthful. A saving that requires lying to a memo is not worth
  taking.
* **Output that belongs to no file must not follow the redirect.** A template
  stamp is re-derived identically by every unit that instantiates it, is memoized
  as emitted by `g-mono-drained`, and the *program* may be what calls it — so
  `drain-mono-worklist` writes to `g-def-stream-program`, which always names the
  module's own stream, rather than to `g-def-stream`, which may be a sink.

## A latch is a claim about a buffer — name the buffer, or the module must stop having two

`StructDef.emitted` meant "this type's `%Name = type {…}` line has been written
**once in this process**". In batch there is one module, so once is right; the
REPL opens a fresh stream trio per prompt entry and frees the buffers, so a type
written into a module that is then discarded — or into an arm that did not copy
its type buffer forward — was marked emitted forever. Stage 16 R4 replaced it
with `emit-epoch` + `in-type-buf` + `in-preamble` on the StructDef and two
functions in `src/type-utils.nuc`: `sdef-in-module` (every read that meant
"already present here") and `sdef-note-emitted` (every write). `emitted` keeps
only "does this type have a definition at all", which is the question the
`defstruct`/`defunion` redefinition diagnostics ask — the same split W9 item 40
made for `laid-out`, and for the same reason.

Four things that generalize, and one that bites:

- **Recording the epoch is not enough; the type needs a way back.** A stale epoch
  only says "re-emit me"; something has to actually do it. Only queued types
  (`g-pending-unions`) have that path, which is why R4 also queues
  `lookup-or-make-anon-struct`'s eager write. **Deferring the write itself is a
  different change and is not IR-neutral** — position within the type section is
  observable, so routing those lines through the drain moves every one of them.
  Queue *and* write eagerly: the drain then finds `sdef-in-module` already true
  and skips.
- **Ad-hoc "copy this forward" sites do not collapse by tidying the call sites.**
  A REPL module used to be assembled as *preamble + this module's own type
  buffer*, which is precisely why the preamble could only be appended to after
  the JIT and why each arm carried its own `strdup`. Making the preamble the
  module's whole type section — absorb *before* assembly, emit no separate type
  buffer — produces byte-identical module text and makes one shared rule
  possible. Look for the structural reason a duplicated step could not be shared
  before assuming the duplication was laziness.
- **A module assembled INSIDE another shares its preamble.** `repl-flush-mono`
  drains into its own module while the entry's module is still open. Once
  "emitted" became per-module, its drain correctly judged the entry's types
  absent and re-emitted them — and the entry's module then defined them twice.
  The fix is to close the entry's type buffer into the preamble *first*
  (`repl-cycle-type-buf`) so both read them from there. Whenever a nested module
  appears, ask which buffers the two share.
- **Not every type line goes to the type buffer.** `fn-make-env-struct` writes
  `%__vfn_env_N` to `g-out` — the *def* stream. (`emit-defstruct` under
  `emit-compile-time` used to write to that module's own type stream; D9 ruled
  that a CT `defstruct` defines a *program* type and moved it.) A per-module
  "carry these forward" mark must know which, or it records a false claim; that
  is what `in-type-buf` is for, and it is deliberately **not** consulted by
  `sdef-in-module`, so outside the REPL `sdef-in-module` is identically `emitted`
  and no batch decision can move.

(Stage 16 R4, design/stage16-ergonomics/repl-libraries.md §3.3.)

## Queueing buys recoverability across EPOCHS, not across BUFFERS — and a CT module shares the batch epoch

The sequel (Stage 16 D9). `sdef-note-emitted sd out` stamps the *current*
`g-module-epoch` whatever `out` is, so a type written into a module that is
assembled **inside** the current epoch — a `compile-time` or macro JIT module,
with its own type buffer — claims to be present in the epoch's real module and
is not. The recovery path R4 built is the pending queue, and it only fires once
`sdef-in-module` goes false, i.e. once the epoch advances. **The REPL advances
it at every prompt entry; batch never does.** So giving `emit-defstruct` a queue
entry makes a `(compile-time (defstruct P …))` recoverable at the prompt and
did nothing at all in batch, where the same program emitted `%P` references with
no `%P = type` line, exited **0**, and died later at the LLVM parser.

Two rules follow. **A type that must appear in two buffers of one epoch has to
be written into the shared one** — queueing cannot move it sideways. That is how
the batch half was actually fixed: `emit-compile-time`'s `defstruct` arm sets
`g-out` to `g-type-stream`, not to the CT module's own `ct-type`. And when you
add a queue entry beside an eager write, state which of the two questions it
answers: "replay me into the next module" (epochs) or "put me where both modules
read from" (buffers). D9 has both, and the queue entry is now the redundant one
— kept as a standing invariant, measured inert, not a live fix.

The queue entry is still worth having and is IR-inert, but only because the two
renderers agree character for character. Prove that before adding one:
`emit-pending-struct-ir-type` (`src/union-registry.nuc`) and `emit-defstruct`
(`src/nucleusc.nuc`) share a header, a `", "` separator and a `" }\n\n"`
terminator; the field **count** is equal because `defstruct-fill-layout`
computes `(- (node-len cc) 2)` from the same node and `struct-set-fields` stores
it as `num-fields`; the field **types** are equal because `struct-set-fields`
stores the very array the eager write prints from; and no padding or repr member
is inserted, because that rule lives in `emit-union-ir-type` and it dispatches
to the plain renderer whenever `is-union` is 0.

## A module-assembly point must flush the shared buffers AT the assembly, not at the top of the function

Same step, and the plainer half. `emit-compile-time` and `compile-macro-body`
each build a JIT module out of the *program's* `g-type-bufp` / `g-decl-bufp`
plus their own. `compile-macro-body` drains and flushes immediately before
copying them; `emit-compile-time` did it at the **top** of the function and then
emitted the whole CT body in between — so every type the body itself stamped
(`?i32` stamps `%Maybe.i32`) reached `g-type-stream` after `g-type-bufp` was
last materialized, and the module referenced a type it did not define.

`open_memstream`'s buffer pointer is only meaningful as of the last flush, so
"I flushed at the start" is a claim about a buffer that the intervening work
invalidates. Put the drain-and-flush next to the `fputs` that reads the buffer,
never at the top of the emitter — the two are separated by hundreds of lines
here, which is exactly why it survived.

Note which gate can see this: a `--emit-llvm` corpus sweep compares **program**
modules and is blind to CT-module IR by construction, so a change to what a
compile-time or macro module contains needs a gate that compiles a program with
such a block and asserts the block's own output.

## A "discard this file" mode is per FILE, and must be set in both directions

The same feature's second defect. `emit-import-forms` bumped a depth counter
around a compile-time-only import and left it alone for ordinary imports, so an
`(import-use vector)` reached *through* a ct-imported library inherited the sink:
`lib/vector.nuc` was imported for real by the program and still had every
definition marked compile-time-only, and the program was refused at its own
`[1 2 3]`.

A mode that answers "does this file's output count?" is a property of the file,
not of the stack that reached it. Set it explicitly on both branches — hand an
ordinary import back the real stream and a zero flag — rather than treating
"unset" as a depth that nesting can only increase.

## `g-imported` means EMITTED — a register-only import may not claim it

`do-import`'s flatten dedup returns early when the path is on `g-imported`, and
the W1d cycle skip deliberately does *not* push there because that list means
*finished*. A compile-time-only import registers a file and emits nothing, so it
records on `g-ct-imported` instead; otherwise a later real `(import-use node)`
was deduplicated away and the program was refused at its own quote — correct in
one import order and silently wrong in the other.

**The order-independent answer came from a walk that already exists.**
`prescan-imported-signatures` runs at depth 1 before any form is emitted and
follows every import form *except* `import-ct`, so the set of paths it visited
**is** "reachable through ordinary imports". `g-real-reachable` snapshots
`g-prescan-sigs` right after it (the import lists are prepend-only, so holding
the head is a genuine snapshot) and `ct-sink-here` asks per file. Before adding a
whole-graph question, check whether one of the existing prescans already answers
it as a side effect of what it walks.

## Relinking a stage IR is the cheapest escape from a stale-boot chicken-and-egg

`context/build.md` documents the 2-stage manual bootstrap for "the source now
uses a feature the committed boot does not have". There is a shorter route
whenever `build/stage2.ll` (or `build/nucleusc.ll`) is newer than the breaking
change and only the *binary* is unusable — which is what an LLVM soname flip
under a built tree leaves behind:

```
clang build/stage2.ll -L/usr/lib/llvm-N/lib -lLLVM-N -ldl -rdynamic -o /tmp/c0
cp /tmp/c0 bin/nucleusc && make
```

No source is elided and no committed artifact is touched (`bin/nucleusc` is
gitignored). Used 2026-08-16, when the container moved from LLVM 22 to 19 while
`boot/nucleusc.ll` predated the symbol-literal commit: the boot binary could not
compile `src/generics.nuc`'s `#{'let 'with …}` and the stage binaries could not
load `libLLVM.so.22.1`, but `build/stage2.ll` had both. **Check `build/*.ll`
before reaching for the 2-stage dance** — and note that a failed `make` truncates
`build/nucleusc.ll` through the shell redirect, so `build/stage2.ll` is usually
the surviving copy.

## Adopting a value-level sugar in `src/` fails only where the boot's silent reading changes DISPATCH

`make` builds `src/` with `bin/nucleusc` — the **boot** compiler — so a spelling
the boot does not implement is not an error there; it is whatever the boot
already made of it. For the Stage 16 value-position annotation (`x:T`,
design/stage16-ergonomics/as-sugar.md) the boot's reading is "discard the
annotation, use `x`", which is silent and *usually harmless*: the ordinary
argument coercion re-widens `n:i64`, a `CStr` parameter absorbs `s:CStr`. It
stops being harmless at exactly one kind of position — an argument whose type
selects an **overload**. Adopting seventeen sites in `src/nucleusc.nuc` built
cleanly for all sixteen `:CStr`/`:i32`/`:i64` ones and died on the single
`(invoke g-include-paths j:usize)`, with `no matching method for overloaded
'invoke' with argument types (ptr:Vector.cstr, i32)`. The symptom therefore reads
as **"the sugar does not work for `usize`"**, and it is really "the boot is
stale, and that was the only adopted site whose meaning the boot could not fake".

The fix is the repo's two-commit dance — the `Boot for …` commits in the log:
refresh `boot/nucleusc.ll` **first**, then adopt. When the adoption is already in
the working tree, `make update-bootstrap` cannot run (its `$(BIN)` dependency is
what fails), so use the relink escape above — a `build/nucleusc` from before the
adoption still implements the sugar, so it can seed the new boot:

```
./build/nucleusc --emit-llvm src/nucleusc.nuc > boot/nucleusc.ll
make boot-binary && make
```

Then `make windows-boot`, which `update-bootstrap` would have run for you — the
Windows boot IRs are committed and must stay in lockstep.

Generalizing past `usize`: before adopting a new spelling in `src/`, ask what the
boot will **silently make of it**, not whether the boot rejects it. A spelling the
boot rejects fails loudly at the first site. A spelling the boot *reinterprets*
fails only where the difference is observable — which makes a stale boot look
like a type-specific bug in the new feature.

## Parameter-list markers are keywords, and `&` is still not free

`:rest` / `:where` / `:optional` / `:repr` (Stage 16,
design/stage16-ergonomics/keyword-markers.md). One predicate answers for all
four — `marker-named (node bare-name)` in `src/nucleusc.nuc`, beside
`print-node` — and callers pass the **bare** word (`"rest"`), never a sigil.
That is what keeps the roster from being re-spelled at each of the fourteen
recognition sites; it also folds in the kind test and the null guard, so
`marker-named` is safe on the NULL node an empty list `()` reads as and on an
INT param whose `Node.s` is null. `marker-any` is the three that terminate a
parameter walk (`:repr` marks a defunion arm chain, never a parameter list);
`marker-spelling` puts a keyword's stripped colon back for a diagnostic that
quotes it.

Four things worth knowing before touching this:

- **A retired `&x` needs a chokepoint per FORM SHAPE, not per marker.**
  `reject-legacy-marker` lives at `desugar-params` (defn/declare/defstruct),
  `macro-parse-params` (defmacro/macrolet), `emit-extend`'s node-3 check, and
  `defunion-strip-repr`. `desugar-params` rather than `emit-defn`'s own scan
  because desugar runs straight off the reader: a `&where` defn no longer
  registers as a template, so the prescan reaches `parse-type-from-node` and
  dies `unknown type: T` first. The other three shapes are not desugared at all.
- **A marker keyword must be tested before any "is this a type?" or "is this a
  symbol?" arm.** `declare-param-type` (`src/nuch.nuc`) reads a `NODE-KEYWORD`
  operand as a *type* (`:i64`), and `macro-parse-params` rejects a non-`NODE-SYM`
  param outright — both would swallow `:rest` and report something unrelated.
- **`&` is NOT freed by this.** `.&` (field-address) is a live special form with
  ~200 uses, and `&` is illegal in any *definition* name anyway
  (`ir-name-illegal-char` / `check-ir-name-legal`). Only the prefix sigil is
  free.
- **`.nuch` is a serialization format for these.** `emit-nuch-defmacro` /
  `emit-nuch-defn` (templates) / `emit-nuch-extend` print marker-bearing forms
  verbatim via `print-node`, which emits `:name` for a `NODE-KEYWORD`. Any
  change to marker spelling must regenerate the committed headers
  (`scripts/check-headers.sh --fix` — it reaches `lib/mapiterlib.nuch`, which
  `$(LIB_NUCHS)` cannot).

**The DECLARATION ATTRIBUTES are the same convention, one position further
along**: `:noreturn` and `:returns-twice`, between a `defn`'s return operand and
its body, and after a `declare`'s return operand. Same three-helper shape —
`decl-attr-kind` / `defn-scan-attrs` / `declare-scan-attrs` beside `marker-any`
— plus `reject-legacy-fn-attr` for the retired bare `noreturn` /
`returns_twice`. Three things there are not obvious:

- **A lone trailing form is the body, never an attribute.** Both scanners guard
  on `(> (node-len form) (+ bs 1))`, so `(defn kw ():Keyword :noreturn)` returns
  the keyword. This is the only reason a keyword-valued one-expression body is
  still writable.
- **`declare-scan-attrs` needs a `min-len`, because a RETURN TYPE is a keyword
  too.** A scan from the end with no floor eats `:i32`. The floor is the entry's
  attribute-free length: 4 for `(declare name (params) :ret)`, 5 for
  `(defmethod "@sym" name (params) :ret)`.
- **A `.nuch` reader existed with no writer for two stages.** `nuch-declare-import`
  read a trailing `noreturn` from the day it was written, and `emit-nuch-declare`
  never printed one — so a `:noreturn` `defn` exported to a header silently lost
  it. When an attribute rides a signature, the export arm is a *separate*
  dispatch site from the import arm; grep both.

## A test unit that dies before its first `echo` is invisible, not failing

A shell test that dies before it prints reports nothing, and the harness that
counts printed verdicts counts nothing either — so a run can say "755 PASS, zero
FAIL" and still be exiting 1. The killer is almost always `out="$(cmd)"` as a
bare assignment, which is fatal under `set -e` when `cmd` fails; use
`out="$(cmd)" || ec=$?`. Found in the old `stdlib-table` unit (Stage 16), where
it had been hiding a genuine regression for the whole of the prelude-split work:
165 libc names had left the no-import set and `docs/stdlib.md` still claimed
them.

**The native suite closed this by construction** (Stage 18 TF-6): a test that
dies is a missing record, and a missing record is a count mismatch against
`--list`, not a silent pass. The lesson still applies to everything in `tests/`
and `scripts/` that is still shell — and to any harness that decides a verdict by
scanning output rather than by counting what it dispatched.

## A conversion keyed on POSITION cannot live in the type-pair chokepoint

`coerce-int-val` is the implicit-coercion chokepoint and the standing rule is to
add conversions there. Stage 16's C default argument promotions are the
exception, and the line is worth stating because it is not "this one is special":
**`coerce-int-val` converts a value toward a declared type, and a variadic
argument has none.** There is no target to pass it. The rule is a property of
*where the argument sits* — past the callee's fixed prefix — and the only code
that knows where the `...` tail begins is the argument walk in
`emit-call-with-args`.

So the test for where a conversion belongs is not "is it a conversion" but **"is
it keyed on a source/target pair, or on a position?"** Two position-keyed rules
now live at that argument walk, and they are the same shape: the Stage 14 NS-3
StrView collapse (a materialized view past the fixed prefix contributes only its
`data` pointer) and `vararg-promote`.

The half that keeps this from being a second code path: a position-keyed rule
should **choose the target and delegate the emission**. `vararg-promote` picks
`i32`/`f64` and then calls `coerce-int-val` to emit the widening, so
`zext`-vs-`sext` — and `i1`'s unsignedness, which is exactly the trap the `i1`
section above records — stays decided in one place. A hand-rolled `sext`/`zext`
at the call site would have been the second place to get it wrong.

Two things such a rule must be tested for, neither of which a positive test
catches:

- **The argument one position too early.** A variadic callee's *fixed* narrow
  parameter must keep its declared type. A rule that fires at `i >= 0` instead
  of `i >= num-params` widens it, and nothing else in the compiler objects.
- **The argument that should not move.** An already-`int`-wide value must gain
  no instruction — a spurious promotion is as wrong as a missing one and costs
  an instruction per call.

And the run alone will not tell you: of the six types `vararg-promote` handles,
**three print correctly under both behaviours** on x86-64, because the backend
materialises a narrow value into a zeroed register. That is the same blindness
the truthiness-test section above records, in a different costume — assert on the
emitted instruction. design/stage16-ergonomics/varargs-promotion.md

## An ELIMINATION at one position is not a coercion — and its two narrowing halves are not symmetric

The section above splits conversions into "keyed on a type pair" (→
`coerce-int-val`) and "keyed on a position" (→ the argument walk). Stage 16's
nil punning is a **third** answer, and the distinction is what keeps it cheap:
a nullable value at a condition site is not converted to `bool`, it is
*eliminated* by the test the author would otherwise have written
(`(!= p null)`, or a `some`-tag compare). So it belongs at the sites that
consume a condition, not at any coercion chokepoint.

Ask which one you have: **a coercion makes the value usable in a slot; an
elimination answers a question about it.** Putting an elimination in
`coerce-int-val` would have made `bool` a universal sink — a `bool` parameter
accepting any pointer, and `(defn g (b:bool))` becoming a dispatch candidate for
every call — for a feature nobody wanted outside condition position. The shape
is the same one `emit-not`/`emit-short-circuit`/`emit-cond`/`emit-while` already
had, six sites each testing `(!= kind TY-BOOL)` inline; one shared
`condition-bool` replaces all six, per the "one shared rule function" rule
above.

**And when you add a shape to `test-true-nonnull`, do not reflexively mirror it
into `test-false-nonnull`.** The two functions look like duals and are not:
they collect what is proven **non-null**, one when the test is true and one when
it is false. A bare symbol proves `m` non-null when true and proves `m` *null*
when false — so the true side gets an arm and the false side gets **nothing**.
The inverted guard still narrows, because `test-false-nonnull`'s existing `not`
arm delegates to `test-true-nonnull`; `(when (not m) (return))` narrows `m` past
the guard through that delegation alone. A mirror arm would have asserted the
opposite of what the test proves.
design/stage16-ergonomics/bool-truthiness.md §"As built"

## A new top-level form has SIX dispatch sites, not one

`deftype` (Stage 16) was implemented as "a registry, a prescan arm, an emit
arm" — and shipped three times with a hole, because the compiler routes
top-level forms through six independent, explicitly-enumerated lists:

1. `prescan-struct-names` (or a sibling prescan) — registers the name.
2. `emit-toplevel`'s `case` in `src/nucleusc.nuc` — the public spelling, and a
   separate arm for the `-`-suffixed private one.
3. **`.nuch` export** — `src/nuch.nuc`'s emit dispatch, one arm per carried head.
4. **`.nuch` import** — `src/nuch.nuc`'s import dispatch, one arm per re-registered head.
5. **`--emit-cheader`** — `src/cheader.nuc`.
6. **The REPL** — `src/repl.nuc` has its own top-level form chain.

Plus `build-special-form-set` (so the name is reserved and cannot be shadowed)
and `text-token-is-definer` (so the "defined nowhere" note can name the file).

**A form missing from any of these is silently dropped, never diagnosed.** The
`.nuch` pair is the sharpest: the header exported `(declare twice ((n Count))
:Count)` naming a `Count` it did not carry, so the *importer* failed on an
unresolvable type with nothing pointing back at the exporter.

The specific wrong inference worth not repeating: reading `lib/hashmap.nuch` and
seeing a literal `(defstruct (Entry K V) …)` looks like proof the format is a
verbatim pass-through. It is not — that form is there because `"defstruct"` has
an arm. **"The format carries X verbatim" is a claim about a dispatch table, not
about the format, and no amount of reading output files can distinguish the
two.** Grep the dispatch.

## `guard-name-kind` cannot see a type-over-type collision

`guard-name-kind name line newk` asks for the first binding whose kind is *not*
`newk`, so it skips every row reporting that noun. `BK-STRUCT`,
`BK-STRUCT-TEMPLATE`, `BK-UNION-TEMPLATE`, `BK-ENUM` and `BK-TYPE-ALIAS` all
report `NK-TYPE` — so **no** collision between two kinds of type is visible to
it, by construction. It catches a type against a function/value/macro/protocol
and nothing else.

The codebase leaves that gap open: `(defenum Pt …)` over a `defstruct Pt` is
accepted today. Whether that is survivable depends on probe order in
`parse-type-name` — the winner is silently whichever it reaches first. A
registry probed **last** (as `deftype`'s is, so an alias can never mask a real
definer) makes the loser *dead on arrival*, so such a registry needs its own
collision check; `type-name-collision` in `src/union-registry.nuc` is the
`deftype` one.

Place such a check **ahead of the same-definition-site early return**, so it
runs on both the prescan call and the emit call: whole-file prescans have
registered everything *above* by the first, everything *below* by the second.
That two-pass trick does not reach registries that register per-form during
emission (`prescan-defenum-names` takes one form, not a form list). See
design/stage16-ergonomics/container-type-sugar.md.

## A depth guard protects one recursion, not one concept

`MAX-TYPE-ALIAS-DEPTH` guarded alias expansion in `parse-type-name` and
`parse-type-from-node`, and a self-referential parametric alias still hung the
compiler forever — because a `defn` parameter reaches `collect-pattern-tyvars`
*first*, and that descent had no guard of its own.

A recursion counter is a property of **each descent**, not of the construct it
protects: it is only as good as its least-guarded caller. When a construct is
expanded at N sites (for type aliases: the concrete parse, the two pattern
walks in `src/generics.nuc`, and `type-node-to-c`), every one of them needs
`when (>= depth CAP) → die`, increment, recurse, decrement. Sharing one
`type-alias-apply` helper does **not** share the guard — the helper returns the
expansion, while the guard has to span the caller's own recursive call.

The symptom is a hang, not a crash, so it does not show up as a failing test
unless something bounds the run: exercise a cycle through *every* path that can
expand, and give the check a `timeout`.

## One marker cannot mean both "in progress" and "done" — split it, don't move it

`prescan-imported-signatures` pushed a path onto `g-prescan-sigs` *before*
reading the file, and `emit-toplevel-forms` reads that same list to decide
whether the file's signatures are already registered. Under the REPL, where a
`die-at` unwinds instead of exiting, a prescan that died left the marker and not
the registration, and the later real import skipped the prescan it never
performed. The obvious repair — move the push to after the prescan — is
**unsound**: the pre-order push is also the walk's cycle breaker, and a cycle
that does not include the unit root (`A → B → C → B`) then recurses forever,
because the root is the only file the walk finds already on the list.

Two markers, not one moved marker: `g-prescan-inflight` is pushed before the
read and popped after (the cycle breaker), `g-prescan-sigs` only once the
prescan actually ran (the claim `sigs-done` reads). Whenever a single list is
serving both "do not re-enter this" and "this is finished", assume the two want
different lifetimes and check every *reader* to see which question it is asking:
`path-in-unit-exact` was asking the first, so it had to be taught to consult the
new list or it would silently start answering a narrower question. (Stage 16 R1,
design/stage16-ergonomics/repl-libraries.md §3.4.)

## `setjmp` in a helper that has returned is UB — pass the body as a callback

The REPL's unwind used to be `repl_try()` → `setjmp` in **its own** frame, with
the caller running the risky work after it returned. Every throw was therefore a
`longjmp` into a dead frame; it appeared to work on glibc/x86-64 and is exactly
the kind of thing a new target or LLVM breaks. The fix is a **protected call** —
`(repl-protect body ctx)` runs `(body ctx)` while its own `_setjmp` frame is live
and returns 0/1 — and it removes a second bug for free: with two sequential
`repl_try` calls around one body, "which call re-armed the buffer?" is invisible
in the source, and the recovery arm had been dead code for a whole stage without
anyone noticing. Keep a depth counter beside the buffer so a throw from a path
**no** protect covers exits with a message instead of jumping somewhere
undefined.

Passing a `defn` as the callback needs no cast, but only if you type the
*parameter*: `body:(fn void)(ptr)` accepts a bare `defn` name as the argument.
`(as ptr some-defn)` is refused (`as: reinterpretation from __fnty_0 to ptr`), so
a `ptr`-typed parameter forces an `unsafe/cast` at every call site. This was a C
shim until 2026-08-30 and is now `src/repl.nuc`; **the compiler compiles no C at
all**, so a build failure mentioning an object file is a stale `Makefile`, not a
missing toolchain.

## A longjmp skips every save/restore on the stack — spell the roster once

`die-at` under the REPL unwinds through `do-import` and `emit-toplevel-forms`
without running one of their `let`-save / `set!`-restore pairs, because every one
of them sits *after* the call that died. Each site is correct in isolation and
none survives the unwind, so the answer is not more save/restore pairs — it is
one `ReplState` snapshot taken at the top of every top-level form and one
`repl-restore` on the unwind path (`src/repl.nuc`). Two things generalize:

- **Registry mutations are not stack saves, and need their own watermark.** The
  registries are append-only, so the watermark is a count (a `Vector`) or a head
  pointer (a prepend-only cons list). A *nested* append needs a nested watermark:
  truncating `g-generics` recovers only the generics a died import **created**,
  while `generic-register-method` also appends to pre-existing ones — hence
  `GenericMark`, which also restores `finalized`/`mangled` because
  `generic-add-method` clears `finalized` as a side effect.
- **Roll back the whole family or none of it.** The three erasure memo tables
  (`g-vtable-table`, `g-boxedfn-table`, `g-dyn-table`) each hand back a
  `StructDef`; keeping an entry whose `StructDef` was just truncated resolves to
  a type no longer in `g-structs`. Where truncation genuinely is not available
  (an `open_memstream`, a pool an already-emitted line references), record the
  registry and the reason in the design doc rather than leaving the gap silent.

**"Once" is now literal (Stage 20 M5).** The roster was still spelled four times
— save and restore, globals and watermarks — with nothing checking the four
agreed. It is two `macmap` tables held by a top-level `macrolet` over both
`defn`s, `(field global)` per row, in `defstruct ReplState`'s own order.
Adding a field means adding one row; `globals-len` is the sole exception,
being a `Scope` field rather than a global. A table is only half the fix,
because a field added with no row still compiles and still leaks that global
between prompts — `scripts/check-repl-roster.py` (unit `repl-roster`) is the
other half, and a new field must go in a table or that unit fails.

## A `case` arm takes exactly one expression — inserting a second silently reparses

Adding a form to the top of an existing `case` arm in the compiler's own source
turns the *next* form into a case LABEL, because `case` reads arms as
(label, one-expression) pairs. The failure surfaces far from the edit and as a
type error on the label, e.g. `= expects integer operands` pointing at the
`case` head. Wrap the arm in `(do …)` when it grows past one form; the same
applies to a `cond` clause body.

## The REPL preamble is a second module buffer, and per-module declare latches are blind to it

`macro-jit-declare-raw` dedups against `g-macro-decls`, a list scoped to the CT
module it is writing. Under the REPL that module is assembled as **preamble +
ct-decl + ct-def**, and the import arm's declare-backfill may already have put
the same line in the preamble — so a second `declare ptr @alloc-node()` lands in
one module and LLVM refuses it with `invalid redefinition of function`. Reproduce
with `(import-use error)` then `(import-use arena)`: `lib/error.nuc` does
`(import-ct node)`, which registers `alloc-node` as a `TY-FN` global, and
`lib/arena.nuc`'s `defmacro new` builds a node.

It predates Stage 16 R2 (the pre-R1 boot binary fails identically) and R2 only
made it reachable, by making both imports succeed on their own. The rule it
generalizes to: a latch scoped to the freshly-opened buffers is a claim about
*part* of the assembled module, so every REPL emission site that has one must
also consult the preamble. Filed as D8 in
design/stage16-ergonomics/repl-libraries.md.

## A short-circuit *before* a comparison discards the comparison, not just its cost

`safe-coerce-val` and `coerce-int-val` (`src/nucleusc.nuc`, `src/abi.nuc`) both
opened with `(when (= sk dk) (return v))`. Two `TY-FN` types have the same kind
whatever their signatures, so **every** typed function-pointer slot accepted any
function — and the call site above it already called `type-eq`, which already
dispatched `TY-FN` to `fn-sig-eq`, which already answered 0. The right answer was
computed and thrown away. Stage 16 FP-1 puts the `TY-FN`/`TY-FN` arm *ahead* of
the identity short-circuit in `coerce-int-val`, and `safe-coerce-val` delegates,
so all four typed slots agree.

Two consequences worth keeping:

- **`fn-sig-eq`/`type-eq` live in `src/abi.nuc`, not `generics.nuc`.** `abi.nuc`
  is imported at `nucleusc.nuc:1195` and `generics.nuc` at `:1217`, so the
  coercion chokepoint could not call forward. Anything a chokepoint needs has to
  be at or before the chokepoint's own import.
- **Use `is-ptr-like`, not `is-ptr-repr`, for the `void *` relaxation.**
  `is-ptr-repr` admits `TY-FN`, which would let a bare `ptr` parameter match a
  `(fn …)` one and reinstate the data-pointer-into-callable conversion
  `unsafe/cast` deliberately owns.

## An indirect call is the same call — give it the same argument path

`emit-funcall-value` (`funcall` and a `TY-FN` value in head position both fold to
it) stopped at `check-call-arity` and printed each argument as raw `type-to-ir`:
no coercion, no diagnostic, no `vararg-promote`, no `abi-classify`. The BoxedFn
call path coerced but did not ABI-lower — the same rule at a second site with a
different subset applied. Stage 16 FP-2 extracted the direct path's per-argument
work into `coerce-call-argument` and both indirect emitters call it, then run
`abi-args-begin` / `abi-arg-frag` / `abi-emit-struct-call`.

**The closure environment pointer is argument zero and spends a GPR**, so it goes
through `abi-arg-frag` like any other. Printing it by hand leaves the register
budget one short for everything after it — which is invisible on x86-64 until an
argument list is long enough to spill.

If you add a third way to call something, it needs `coerce-call-argument` and the
`abi-*` sequence, not a fresh subset of them.

## `struct-walk` is the layout — do not re-derive a size, an offset, or an index

A struct's ABI size, the element list `emit-struct-type-line` prints, each
field's GEP element index and each bit-field's absolute bit position are four
answers to one walk over the field list, and Stage 16 BF-1 made them come from
one function (`src/abi.nuc:struct-walk`). `struct-walk-size`, `struct-tail-pad`,
`field-ir-index` and `field-bit-offset` are one line each on top of it.

They must stay that way because `aligned(N)` pads and bit-field runs both make
**field index ≠ element index**: a run of adjacent bit-fields is ONE opaque
`[k x i8]` element, and a pad is an element of its own. A second implementation
of any of the four disagrees with the GEP that addresses it, and the disagreement
is a wrong offset at run time rather than a compile error.

## `arr-len` 0 means PROVISIONAL, and a flexible array member is -1

`type-to-ir` asserts that a TY-ARRAY with `arr-len` 0 never reaches IR: zero is
the marker `g-array-ok` mode 2 leaves behind when the prescan cannot fold an
extent (`src/nucleusc.nuc`, near `g-array-ok`). So C's flexible array member —
`int f[];`, which really is a zero-extent trailing member — could not reuse it.
It is `(array T -1)`, which prints `[0 x T]` and sizes as 0 (Stage 16 C1a).

If you ever want a real `(array T 0)` in the surface language, the provisional
marker has to move first.

## A compiler-minted field name is a decidable fact, and `struct-field-index` cannot see through one

Two field-name prefixes are minted rather than written, and both are unspellable
as a C or Nucleus identifier, which is what makes "did the compiler mint this?"
answerable with a `strncmp` and no extra state:

- `__bf.N` — C's unnamed bit-fields, `unsigned :3;` and `unsigned :0;` (BF-4).
  `bf-align-contrib` keys the SysV "an unnamed bit-field contributes no
  alignment" rule on it.
- `__anon.N` — C11 anonymous members, and the `(:anon T)` surface (AN-1/AN-2).
  `struct-field-ref` descends through these; **`struct-field-index` does not.**

That last line is the trap. A site that resolves a member with
`struct-field-index` alone silently answers "no such field" for every name an
anonymous member supplies. The four access sites (`_get`, head-position `get`,
`.set!`, `.&`) each fall through their `idx < 0` branch into `struct-field-ref`
for exactly this reason; a fifth would need the same fall-through. The type side
(`node-type-field`, `callable-get-type`) already goes through `struct-field-ref`,
so it needs nothing — but that is also why a site that skips it breaks the
`node-type`↔`emit-node` lockstep in the direction that is hardest to see.

## C leaves bit-field allocation to the psABI, and the targets really disagree

Three rules that cannot be read off the C standard and were each found by
`clang --target=` disagreeing with an implementation that looked right
(design/stage16-ergonomics/c-boundary-defects.md §15.4):

1. **AVR drops the "may not cross a boundary of the declared type" rule
   entirely** (GCC's `PCC_BITFIELD_TYPE_MATTERS` is off there). Only a
   zero-width member still forces a boundary, and there it is a **byte**.
2. **`packed` drops the crossing rule but NOT the zero-width one.**
3. **aarch64 gives every bit-field its declared type's alignment, named or
   unnamed, and keeps a zero-width one's even under `packed`**; the SysV targets
   give an *unnamed* bit-field none.

Any change to bit-field layout has to be re-run against
`s16-bf-layout-cross-target`, and its shapes I, J and K are the ones that tell
these apart — A–H are green under all four wrong combinations.

## `c-parse-type` collapses pointer depth, so a second declarator's base is only recoverable when the first had none

A C declaration shares one specifier run across several declarators — `int a, b;`
in a struct body, `typedef int a, *b;` at top level — and each declarator carries
its own `*` run, its own `[N]` extents and its own bit-field width.
`c-parse-type` consumes the specifiers **and the first declarator's stars**, and
any depth ≥ 1 becomes a bare `ty-ptr` with no pointee. There is therefore nothing
to unwrap: for a later declarator, the base type is available exactly when the
first one was unstarred, and `c-span-has-star` over the span the type parse
consumed is the whole test (Stage 16 CD-1/CD-2). A later *starred* declarator is
`ptr` regardless, so `char *s, *t;` — the common spelling — is exact, and only
the mixed `int *p, q;` is refused.

Do not "recover" the base by re-parsing the specifier run with a truncated `len`:
an inline `struct { … }` base would be parsed twice (a second registration and a
second type line), and a `*` inside an `__attribute__` argument would truncate
the run mid-parse and silently yield a base of `ptr`.

## A declarator LIST needs the first declarator to go through the loop too

`c-parse-struct-decl` handled the declarator after a struct body inline, and
CD-4 had to add the ones after a `,`. Writing that as a *second* implementation
beside the first is the mechanism that produced the bug being fixed — a shape
handled in one place and not the other. `c-struct-decl-declarator`
(`src/cheader.nuc`) is therefore what the first declarator goes through as well,
and the loop is: consume `*`s, call the helper, `,` continues / `;` ends. Same
rule as `binop-result-type` and the array-decay note above: mirroring logic
drifts, mirroring a *call* cannot.

The pre-scan (`cheader-scan-opaque-decl`) still mirrors rather than calls,
because it has no parsed body to anchor on — and the name-for-name rule bites
here in a new place: a **pointer** declarator (`typedef struct { … } A, *Bp;`)
must register a typedef-table entry and **no** `StructDef`, or the opaque entry
shadows the record the real import makes. A *non*-typedef declarator list
(`struct S { … } x, y;`) declares C variables, which the importer does not model
at all; the only correct action is to consume them so the next declaration is
read from the right offset.

## `--emit-cheader` includes the C header a TYPEDEF came from, not the one a TAG came from

The asymmetry is not an oversight and the reason is C's, not Nucleus's. A C
struct reference renders `struct SDL_Rect`, and an incomplete tag is legal behind
a pointer — the header compiles, and only a *by-value* use fails, silently. A C
typedef renders **bare** (`off_t`, because `struct off_t` names nothing), so a
header that names one does not compile at all. Only the second is a hard failure,
and only the second is included today (`cheader-note-c-include`).

Two things make the include correct rather than merely present. **The spelling is
the `(import-use …)` string, not `g-cheader-file`** — that global is rewritten by
every `# N "file"` linemarker, so it names `/usr/include/x86_64-linux-gnu/bits/types.h`,
which is neither portable nor what a consumer would write. `CTypedef.hdr` carries
the import spelling from `g-cheader-import-header` (`src/type-utils.nuc`), which
linemarkers never touch. And **`--emit-cheader` never runs `emit-c-include`** — it
runs the pre-scan only — so the global has to be set at the top of *both*
`emit-c-include` and `cheader-prescan-opaque`, or the header mode sees nulls.

The general form of the argument, worth reusing: the emitter already writes
`#include <stddef.h>` unconditionally because it spells `size_t`. A "should we
include this?" question about a name the emitter *learned* is already answered by
what it does for the names it hardcodes.

## A C typedef anchored on a StructDef needs THREE sites to agree, not two

W3a's rule is that `cheader-scan-opaque-decl` must stay name-for-name with
`c-parse-struct-decl`. Stage 16 CD-3 (`typedef struct Tag { … } Name[N];`) is the
case where the two must *both* stop registering a name: `parse-type-name` probes
the struct registry **before** the C typedef table, so an opaque `StructDef`
named `Name` left behind by the prescan shadows the array typedef the real import
records — and the shadowing is invisible everywhere except the positions the
prescan exists for (a `defn` signature, a `defvar` type).

The third site is the **element** the array wraps. It has to be a `StructDef`
both passes can name, because the prescan resolves the typedef before any body
has been parsed and the import upgrades that same entry in place. The C tag is
that name when there is one. When there is not — an untagged
`typedef struct { … } Name[N];`, whose body the import memoizes by content hash —
neither pass can name the other's answer, so both mint one from the declarator:
`__carr.<typedef name>`, the same `__bf.`/`__anon.` convention (a `.` is
unspellable as a C or Nucleus identifier, so "the compiler minted this" stays
decidable with no extra state).

## A prescan that builds a partial copy of a Type diverges per FIELD, not per bug

`prescan-defn-signatures` and `nuch-defmethod-import` register a `Method` whose
`fn-type` is a **second** `TY-FN` Type for a signature `emit-defn` also builds.
`finalize-generics` binds that one into `g-globals` for a **solitary** name, so
every call emitted *above* the definition — a forward call, or a call from an
earlier file — is arity-checked and default-filled against the prescan's copy,
not `emit-defn`'s. The two copies must therefore agree field by field, and until
Stage 16 they disagreed on three:

- **`has-rest`** was inferred from `(< (defn-params-count params) (node-len
  params))`, which is equally true of an `:optional` list. So an `:optional`
  defn registered `has-rest = 1`, a forward call took the `:rest` folding path
  (`a :rest call needs the node runtime` for a program with no `:rest` in it),
  and the three widening dispatch tiers that gate on `(= (m has-rest) 0)` —
  `generic-resolve-adapt-tier`, `operator-user-resolve`, `valid-resolve-type` —
  skipped every overloaded `:optional` method.
- **`nopt` / `opt-defaults`** were never set at all, so a forward call that
  omitted an optional was refused `expected 2 args, got 1` for a function that
  takes one or two.

`defn-params-has-rest` and `defn-params-set-opt` (`src/generics.nuc`, beside
`defn-params-count`) are the repair, called from both registration sites. The
generalizable half: when you find one wrong field in a registered signature,
**diff the whole Type against the emitter's**, because the registration is a
hand-written subset and every field it forgets is its own silent divergence.

Related, and the reason this is not visible from a call site: `emit-defn`
rebinds the name with the full Type, so the same call one line *below* the
definition is correct. A test for this class must call from above.

## A template's body is checked at STAMP time — so a declaration-time chokepoint is not one for templates

`register-union-template` / `register-struct-template` retain the form and parse
nothing. Every diagnostic that lives in the concrete registrar is therefore
absent for a template until something instantiates it — and a template nothing
instantiates is checked by nobody. `(defunion (Box T) … :repr bogus)` compiled
clean, and so did the **retired** `&repr` spelling, whose whole retirement rests
on `defunion-strip-repr` being one of four chokepoints.

The cheap repair is not a new checker: it is calling the existing one for its
diagnostics and discarding its result. `register-union-template` runs
`defunion-strip-repr` on the arm chain and drops the filtered chain, which
recovers four diagnostics (bogus mode, missing mode, non-symbol mode, the `&repr`
retirement) for one throwaway cons chain per template. Same rule as
`binop-result-type`: mirroring the logic drifts, mirroring a *call* cannot.

What genuinely cannot move earlier is anything needing the arms' **types** —
`union-layout-classify`'s "arms are not nicheable" and "an all-payload-less union
is an enum". Split the checks by that line rather than deferring all of them.

**When you add a diagnostic to a definer that has a template twin, ask which of
the two registrars it lands in**, and whether the answer needs a stamp.

## A prescan that must reach a nested body is a DESCENT, and its filter is the emitter's arm list

`prescan-struct-names` was a flat walk over the unit's top-level form list, so a
type defined inside `(compile-time …)` had no name when `prescan-defn-signatures`
ran and every signature naming it died `unknown type: T` — even though D9's
ruling had already made it a *program* type whose `%T = type` line lands in the
program module. The repair is small for a reason worth remembering: **a nested
body is usually already the shape the walk consumes.** A `compile-time` form's
`cdr` is a cons chain whose cars are forms — identical to the top-level chain —
so the pass recurses into itself with a mode flag rather than growing a second
walk that can drift.

The mode flag is not decoration. **Over-registering is worse than the bug it
fixes**: a name that resolves in a signature with no type line emitted is silent
invalid IR at exit 0, which is the failure shape the whole item existed to
remove. So the descent registers exactly what the nested emitter *defines* —
here `emit-compile-time`'s body loop has an arm for `defstruct` and for nothing
else the pass registers, and `defstruct-`/`defunion`/`deftype`/a nested
`compile-time` are each already an `unknown: <head>` inside a block. Probe that
list, do not read it off the grammar.

Keep the skip in lockstep the way `binop-result-type` does: **one predicate both
sides CALL** (`ct-emits-defstruct`), never two copies of the same `(= h "…")`.
And ask the "and *where* does it write?" question of every sibling pass before
descending it too — the answer split cleanly here: the two TYPE passes descend
(the line is in the program module), the value passes must not (a CT `defvar`'s
`@g = global` and a CT `defn`'s `define` go to the CT module alone, so an earlier
registration converts a clean `unknown:` diagnostic into an undefined-symbol
reference). Verify that by compiling a *backward* reference to each: the ones
that already emit invalid IR are the ones a descent would only spread.

## The `sk == dk` identity return is a chokepoint, not a shortcut

`coerce-int-val` (`src/abi.nuc`) and `safe-coerce-val` (`src/nucleusc.nuc`) each
open their pair-matching with `(when (= sk dk) …)`. That line accepts on the
type's **kind**, and same kind is not same type: every pointer lowers to `ptr`,
so a `(ref (Vector i32))` entered a `(ref (Vector i64))` slot and read its
elements at the wrong stride, silently, at every binding, argument, `set!`,
`.set!`, `return` and `aset!`. FP-1 answered the `TY-FN` half by inserting
`fn-sig-compat` immediately *above* that line; Stage 16 SE-1 guards the line
itself with `slot-type-compat` (FP-1's own predicate, renamed — it was never
fn-specific: it recurses through pointers and ends at `type-eq`).

Three things to carry forward.

- **Only the pointer kinds were silent.** A struct, array or union mismatch was
  already refused — by the *LLVM verifier*, at a synthetic line in generated IR
  (`'%t8' defined with type '%Vector.i32' but expected '%Vector.i64'`). When you
  find a checking hole, sort the pairs into "wrong answer" and "right answer,
  wrong reporter" before pricing the fix; they are the same edit and very
  different arguments.
- **The direction nobody checks.** conventions' rule is "an explicit conversion
  form must never reject what the implicit one accepts". `as` had refused this
  pair since always (`as-ptr-convert` compares pointees), so the *implicit* path
  was the looser one for years. Check both directions when you audit a
  conversion: the rule as stated only catches half of it.
- **`defvar-init-ir` needs the same rule, and got it late.** The constant
  renderer's `(addr-of g)` fold (`defvar-addr-of-ir`) checked `pkind` and never
  the pointee — the sixth instance of the "a SECOND value-into-a-typed-slot
  path" trap above. The fix is the same *call*, guarded to `TY-PTR` destinations
  so a bare `ptr` and a `CStr` keep their own rules.

## A generic's tyvar may come from the WANT — and then the parameter types are not its key

`vector-new-in` is `(defn vector-new-in ((a (ref AllocHandle))) (ref (Vector T)) …)`:
`T` appears only in the return type, so the want channel binds it per call site.
Two things were keyed on the parameter types alone and stopped being keys the
moment `T` could vary — `generic-find-method-exact` (the monomorphizer's memo
probe, and the tier-0 answer in `generic-resolve` and `node-type-call`) and
`mangle-fn-name`. The compiler therefore held exactly **one** `vector-new-in`,
stamped `(Vector i32)` by whichever call site got there first, and all 59 others
silently took it. It was benign only because `(Vector T)` has no `T`-typed field;
the by-value sibling `vector-new-capacity` reserves `n × sizeof T` from the wrong
`T`. The sequel to "a key stops being a key the moment the thing it identified is
allowed to vary", and the reason TC-1's want-arming (G-5) did **not** fix this on
its own: the want decides the binding, and the memo probe runs before the binding
is ever consulted.

The shape of the repair is the reusable part — the reference/definition split,
again:

- **Reference** lookups (`generic-find-method-exact`, and `generic-resolve`'s
  tier-0 loop, which is that function written out inline) must **skip** a stamp
  whose template has an undetermined tyvar, so the caller falls through to tier 1
  and re-binds from the want. Fixing the shared function reaches `node-type-call`
  too, which is the lockstep half — check that it does, or fix it separately.
- **Definition** lookups hold more of the key: `defn-ir-name` takes the return
  type, and the stamp's symbol carries `.$r.<type-mangle-token>`. Mark such a
  stamp `ir-fixed`, or `finalize-generics` re-mangles it from the parameter types
  (dropping the discriminator) and reads its siblings as duplicate definitions of
  one signature.

Two traps found while doing it, both general:

- **A computation with no reader is not "advisory", it is unverified.** The full
  A1 determination fixpoint (params, then propagate through `:where` constraints)
  was built in the template registration and never read; the question's one
  consumer, `method-undetermined-tyvar`, used a params-only approximation of it.
  Harmless while that consumer only fired after a bind had already failed —
  and, the moment a *symbol* depended on the answer, it called `reduce`'s
  constraint-recovered `S` return-only and renamed every `reduce` stamp in the
  corpus. It is now one function, `tyvars-determined`, with one caller.
- **`pattern-determines-tyvar` documents itself as mirroring `unify-tpat` and did
  not expand parametric type aliases.** `(deftype (Vec T) …)` is the third place
  the §3.7 expansion has to happen (`collect-pattern-tyvars` and `unify-tpat` are
  the other two). A "mirrors X" comment is a claim with an expiry date; re-check
  it whenever X grows an arm, and whenever a new caller asks the mirror a
  question no caller asked before.

## A type SPELLING is read by more than the type parser — so spelling sugar belongs in the lexer

`parse-type-name` / `parse-type-from-node` look like the place to add a new type
spelling, because that is where `?T` and `!T` live. They are not, and Stage 16's
`&T`-for-`ref:T` sigil is the worked example.

A colon-chain spelling is consumed by at least four independent readers before
(and instead of) the type parser: `split-colon-segments` / `desugar-symbol` cut
a binding's `name:type`, `rd-fuse-colon-paren` joins an open-segment atom to an
adjacent paren form, `collect-pattern-tyvars` walks a *type pattern* looking for
tyvars, and `unify-tpat` / `pattern-determines-tyvar` mirror it. Add the sugar
at the parser and each of those needs its own arm — and the one that bites is
`collect-pattern-tyvars`, which collects any **unresolvable** symbol as a tyvar:
a bare `&T` in `(Vector &T)` would have been registered as a type *variable*
rather than reported, the same silent class as the `x:ref:Vector:ref:Node`
mis-parse container-type-sugar.md found.

The rule: if the sugar is a pure rewriting of one spelling into another, do it
in `lex-atom` (`expand-ref-sigil`) so every consumer downstream sees the
canonical form and nothing else changes. Two consequences to check when you do:

- **It applies everywhere an atom appears**, including quoted data and value
  position. That is only acceptable when the atom shape was previously an error
  everywhere — check the current source and tests before assuming it is free.
- **A retirement diagnostic that keys on the old spelling is a consumer too.**
  `reject-legacy-marker` reads `&rest`/`&where`/`&optional`/`&repr` as *retired
  markers*, so the sigil must leave exactly those four unexpanded or the
  diagnostic silently stops firing and they fail later as `unknown type: rest`.
  Share the roster (`legacy-marker-tail`) rather than copying it into the lexer.

The mirror of this rule holds for **value**-position sugar, and it points the
other way: do NOT reach for `lex-atom` there. Value position already has a
grammar for `name:Type` — an ascription that lowers to `as` (`emit-symbol-ref`:
`split-typed`, then `as-convert` to the annotation) — so an atom the lexer
rewrites into a colon chain lands *inside* that grammar rather than beside it.
Stage 16's `&x` address-of is the worked example: expanded in the lexer
it becomes `ref:x`, which already parses as "the variable `ref`, cast to type
`x`", and `ref` is a legal *binding* name — a definition may not take it
(name-resolution.md §15) but a `let` or a parameter still may, which is exactly
the position the ambiguity lives in. The right layer is the **reader-macro
table** (`read-macro-table-new` in `lib/read.nuc`, beside `@` → `deref`), which
is matched *before* `rd-atom` and only at a token boundary — so it wraps the
next form in a head instead of minting a spelling. Wrapping in a head the
compiler already matches on costs nothing downstream; a head new to one world
needs that world's arms: Stage 21 PK-1 moved `&x` from `addr-of` to `ref`, and
the value path's reading sites (`emit-list`, `node-type`, `fn-rewrite-captures`,
`defvar-init-ir`, `defvar-check-init-order`, `gcheck-special-form`,
`macrolet-bind`, and the `q:(ref T)` annotation guard in `emit-callable-value`)
each needed a `ref` arm. Note that `def-rmacro` *can* do this from source, since Stage 21 R-1
(`design/stage21-cleanup/one-reader.md`): the reader registers `(def-rmacro "p"
sym)` as it reads it, so a prefix takes effect for the forms after it in its
own file — file-scoped and forward-only, not global — while the REPL keeps one
session table across prompts.

## A check on an emit path counts INSTANTIATIONS, not source sites

`die-at` is `:noreturn`, so a check that has to *enumerate* rather than stop —
an audit flag, a migration driver, a deprecation sweep — is `report-at` plus a
counter that `main` tests before `flush-module-ir`. Two things about the count
are easy to get wrong, and both were measured on Stage 16's
`--strict-selectors` (`design/stage16-ergonomics/dot-forms.md` §2):

- **A generic body is emitted once per instantiation**, so a site inside one is
  reported once per instantiation: `lib/vector.nuc`'s 29 `(_get …)` sites
  produced 629 reports. Dedup on `file:line:name` before believing a total —
  raw 7555 vs. real 6106.
- **A generic this unit never instantiates is never visited at all.** 27 files
  under `src/`+`lib/` reported nothing, `lib/string.nuc` among them. A per-unit
  check is not a tree-wide inventory; `examples/` and `tests/fixtures/` need
  their own runs, and a form inside a quasiquote template is data that no run
  reaches.

The same asymmetry applies to any "how many places do X" question answered from
inside the compiler: it answers about emitted code, and a grep answers about
source text. Neither is the other's sanity check.

## The compiler SYNTHESIZES member accesses — a source migration cannot reach them

`fn-rewrite-captures` builds a member read for every captured variable, and the
env-drop / `__alloc` paths build more; there are twelve such construction sites.
They carry a selector that no grep, and no rewrite driven by source text, will
ever see — the cell is built, not read.

This is why Stage 16's selector migration built `--strict-selectors` before
touching any source: the flag reports what is *emitted*, so it found these,
and a spelling change that had only rewritten source would have broken every
closure in the language the moment the rule flipped. They now go through
`quoted-selector` (`src/nucleusc.nuc`). The same twelve sites bit again when
`.`/`.&` were retired — they synthesize `_get` and `addr-of` now, `_get` rather
than `get` because a synthesized read of a compiler-generated env struct means
*raw field load*, which is what the bypass primitive is for.

The general rule: before changing what a **spelling** means, ask the compiler
which of its own emissions use that spelling. A macro's quasiquote template is
the same hazard one layer up — the template is data, so a form inside it is
reported at the macro's USE site with a gensym receiver, never at the template.

## A macro BODY sees only what precedes it — `lib/macros.nuc` is order-dependent

A macro body is ordinary user-scope code compiled at **definition** time, so it
can only call macros already defined above it in the file. `case` sits above
`when`, and `(when …)` inside its body fails with `unknown: when` — from
`lib/macros.nuc`'s own line number, which reads like a defect in the prelude
rather than in the macro being written. Use `cond` (a special form, always
available) and whatever is defined earlier; do not reorder the file to get a
macro into scope, because the same edit moves every other body's horizon.

This is the same rule that keeps `die-at`/`report-at` out of macro bodies
(`case-clause-hint`, `src/nucleusc.nuc`) — a body is compiled in the user's
scope, not the compiler's. Stage 20 gave it the one thing it was missing:
`(macro-error node "literal")`, a special form that lowers to a call the JIT
module resolves from the compiler binary. A *located* error is available now;
what is still unavailable is a formatted one (the message must be a literal), so
a degenerate case with nothing to say still needs a defensible value rather than
a diagnostic — `(:or)` in `case` is `false`, like `(or)`.

## Member access on a null node in a macro body kills the COMPILER, before any diagnostic

The section above on `()` applies here with the stakes raised: a macro body runs
inside the compiler process, at expansion time, so `(x 'car)` on a null
`(raw Node)` is not a crash in the program being compiled — it is exit 139 from
`nucleusc` itself, with no diagnostic, whatever `macro-error` the next line was
about to raise. And `lib/macros.nuc` cannot reach `node-kind`: the prelude
registers the `Node` type and imports no node runtime, so a body has member
access and nothing else.

So a shape check is a short-circuit chain whose every term is reached past its
own guard, and the order is load-bearing:

```lisp
(when (or (= spec null) (!= (spec 'kind) NODE-CELL)
          (= (spec 'cdr) null) (= ((spec 'cdr) 'car) null))
  (macro-error … ))
```

Swap the last two and `(macmap (x) (1 2))` segfaults. Write the comment — the
ordering reads as arbitrary and a later edit will otherwise "tidy" it. Second
trap in the same breath: `macro-error` on a node with no line reports at line 0,
which `w4a-no-line-zero` exists to catch, so blame a node the user actually
wrote (`macmap` blames the *rows* when the spec is the empty `()`).

## A form whose SHAPE depends on its operand's type cannot be a macro

`try` was a macro in `lib/error.nuc` expanding to a fixed
`(match r ((ok v) v) ((err e) (return (err! e))))`. Stage 17 A1 made `!void`
work — `(Result void Err)` stamps a **payload-less** `ok` arm, because
`defunion-register` now drops a `void` field — and that fixed expansion became an
arity error on every `!void` operand: the arm must be `((ok) (do))` there and
`((ok v) v)` everywhere else. A macro sees `Node`s, never types, so no macro can
choose between them. `try` is now a special form (`emit-try`,
`src/union-emit.nuc`), synthesizing the same match with the arm shape read from
`result-ok-type`.

The general rule: a macro may *contain* type-dependent code, but it may not
**branch on a type** to decide what it expands to. When a form's expansion shape
(not its contents) varies with an operand's type, it belongs beside `match` /
`unwrap` / `make` in the emitter, with the mandatory `node-type` lockstep arm.

**Two mechanics this cost.** (1) A `defmacro` may not shadow a special form
(`'X' already names a special form — a symbol may name only one kind of thing`),
so the library macro and the special form cannot coexist for even one commit.
(2) The compiler's own sources must compile under the **previous** boot, which
has neither the new special form nor the renamed macro. With `src/reader.nuc`
(since deleted; Stage 21 moved the reader to `lib/read.nuc`) holding 19 `try`
sites, the migration is therefore three states, not two: rename
the macro (`try-boot`) and repoint `src/` at it; land the special form and drop
the old macro name; `make update-bootstrap`; then flip `src/` back and delete the
shim. Budget a boot generation for any macro→special-form promotion whose name
`src/` already uses.

## A coercion keyed on the destination KIND fires at typed pointers too

`(ref StrView)` is `TY-PTR`. So the NS-2/NS-3 rule "a `StrView` borrows to a
`char*` by taking `data`", written as `(or (= dk TY-PTR) (= dk TY-CSTR))`, also
fired when the destination was a pointer *to a struct* — including to `StrView`
itself. Passing a `StrView` value (or a string literal) to a `(ref StrView)`
parameter compiled clean, passed the data pointer where a `%StrView*` was
expected, and the callee read `len` out of the string's bytes. A plain
`(defstruct P x:i64 y:i64)` in the same position was correctly rejected — the
lattice rule was punching the hole, not the argument path.

Two things to carry forward when adding a rule to `coerce-int-val`:

- **Test the pointee, not just the kind.** `TY-PTR` covers `ptr`, `raw`, `?ptr`,
  `CStr`-adjacent pointers, *and* every `(ref S)`. A rule that means "byte
  pointer" must say so: `strview-borrow-target` (`src/type-utils.nuc`) admits
  `CStr`, a pointer with no `elem`, or a pointer to an 8-bit integer.
- **Write the negative test with a non-string struct.** The reason this survived
  from Stage 14 to Stage 17 is that nothing in `src/` produced a `StrView` value,
  so the rule was dormant through every bootstrap. Byte-identical bootstrap
  proves a rule is *unreached*, never that it is *right*.

## Prefer the `&` spellings

Since Stage 16, `&` is both the reference-type sigil and the address-of reader
macro, and **the short spellings are preferred in new code**:

| Write | Not |
|---|---|
| `p:&Point` | `p:ptr:Point`, `(p (ref Point))` |
| `):&T` | `):ref:T` |
| `&x` | `(ref x)`, `(addr-of x)` |

`&` inside an atom is the type sigil (`&T` → `ref:T`, chaining as `&&T`, `?&T`,
`&raw:T`); `&` starting a token is `(ref x)`. A field address is the 2-argument
form, `(ref s 'field)` (or `(addr-of s 'field)` until PK-5) — there is no
`&s.field`. `(ref T)` list form is still required where a parameter's type is
parenthesised, e.g. `(v (ref (Vector T)))`.

Since Stage 17, a struct **value** in a binding also reaches a `&T` parameter
with no `&` at all (lvalue-only implicit address-of, borrow-conventions.md
§3.4), so `(strview-byte-len sv)` needs neither a cast nor an address.

Two spellings that do not work and fail as *undefined name*, not as a syntax
error, so the message points at the wrong thing:

- **`&rest`** is read as the variadic parameter marker, never as `addr-of rest`.
  Name the binding something else.
- **`(invoke v 0:usize)`** — the `name:type` sugar needs a *name*, so an index
  literal is `(as usize 0)`. `(invoke v i:usize)` over a binding is fine, which
  is why every existing call site reads as though the literal would work.

## Dispatch happens before coercion, and the tier decides what else moves

An argument rule that only touches `coerce-call-argument` reaches plain
functions and *not* overloaded or protocol methods: `generic-resolve` picks the
method from argument TYPES first and reports "no matching method" before any
coercion runs. Both halves are needed, and they must agree.

Which tier the dispatch half goes in is load-bearing. Stage 17's implicit
address-of was first written into the **tier-2** widen/adapt pass — the one that
already receives argument nodes, so it looked like the natural home. That broke
`parse-test`: `from-str` selects its overload by a phantom first argument
(`(from-str (unsafe/cast i32 0) sv)`), and tier 2 lets *every* argument widen, so
`i32` also matched the `i64` and `f64` overloads and the call became ambiguous.

The rule: put an **exact** adjustment (one that loses no information and cannot
be lossy) in tier 0, as a second pass after the strict one finds nothing — so an
exact overload still wins and no resolving call can become ambiguous. Tier 2 is
only for genuine widening, where every other argument is free to widen too.

**And a third half: `node-type-call` runs its own tier 0.** `generics.nuc` has
two exact-match resolvers — `generic-resolve` (emit) and
`generic-find-method-exact` (via `node-type-call`) — so a dispatch relaxation
added to one leaves the other answering "unknown type" for calls emit resolves
fine. That is invisible until something *reads* the type: `emit-try` sizes its
`ok` arm from `(node-type operand)`, so a `(try (write-str f sv))` on a struct-
value receiver built a one-binder match against `!void`'s payload-less arm. Add
the pass to both; keep the definition-side lookup exact.

## The boot compiler gates what `src/` may use

`make` compiles `src/nucleusc.nuc` with `bin/nucleusc`, the **committed boot
binary** — not with the compiler you just built. So a feature added to the
compiler is unusable in the compiler's own source until `make update-bootstrap`
refreshes `boot/nucleusc.ll` and `bin/nucleusc` from a build that has it.

The failure looks like a type or dispatch error in perfectly good code, and the
same code compiles fine as a standalone program with `./build/nucleusc`. That
divergence — works with `build/nucleusc`, fails under `make` — is the signature.

The sequence is: land the feature (src/ still not using it) → `make` green →
`make update-bootstrap` → now use it. Stage 17's `fstr` needed exactly this, as
`try-boot` did before it.

## Importing the string stack into `src/` collides on protocol method names

`lib/strview-str.nuc` / `lib/string.nuc` bring `char-at`, `byte-at`, `bytes`,
`as-view`, `chars`, `count`, `sub-bytes` into scope as protocol methods. The
compiler has always been free to use those spellings for its own helpers, and
one of them had: `src/reader.nuc`'s `char-at (s:ptr pos:i64)` (the function
survives as `cstr-byte-at`, since Stage 21 R-2 in `src/diagnostics.nuc`).

Once the name is a generic with several methods, a call that previously adapted
(`CStr` argument at a `ptr` parameter) is resolved by exact dispatch instead and
fails with "no matching method". Rename the compiler's helper rather than the
library's — the suffixed-name convention `src/` already follows for
`defn-params-count` and friends. Stage 17 C1 renamed exactly one: `char-at` →
`cstr-byte-at`.


## An emission sink is either an OWNER or an ALIAS — and only owners are values

Stage 17 C3. `g-type-stream`, `g-decl-stream`, `g-def-buf`, `g-entry-stream`,
`g-body-stream` and `g-repl-preamble` own their bytes and are `String` values.
`g-out`, `g-decl-out`, `g-def-stream` and `g-def-stream-program` are re-pointed
at whichever buffer the form being emitted belongs to, so they are `(raw String)`
— null before a module opens, exactly as the `FILE*`s they replaced were.

Three consequences that are not obvious from a call site:

- `(set! g-out g-type-stream)` is now `(set! g-out (addr-of g-type-stream))`.
  Assigning the value would copy the struct and the writes would go nowhere the
  owner can see.
- **Saving an owner around a nested emission is a MOVE.** `push-function-state`
  and the REPL's module-stream snapshot both install fresh buffers, because the
  nested emission calls `reset-function-state` / `open-module-streams`, which
  clear in place. A copy left behind carries a stale length over a buffer the
  nested emission then reallocates.
- **A `String` may not be a `defstruct` field in `src/compiler-types.nuc`.** That
  file is imported before `lib/string.nuc`, so a `%String`-typed field names a
  type the compile-time module's own type section does not carry, and the JIT
  dies with "use of undefined type named 'String'" on the first `compile-time`
  form. A pointer field is `ptr` in IR and carries nothing — park the value in
  the arena (`string-box`) and hold the pointer.

## `emit` stages into ONE shared buffer — use `emit-all` for a whole buffer

`(emit SINK pieces…)` formats into a process-wide `String` and issues one write.
It takes a **mark** (`byte-len` before the pieces are appended) and writes only
the bytes above it before rewinding, so a nested `emit` reached from an
argument's own side effect still works: the inner text goes out first and the
buffer is left as it was found, which is the order `fprintf` gave.

Appending a whole buffer through `emit` would stage every byte a second time, so
the function-body and module buffers go through `emit-all SINK SRC` instead. The
rule: `emit` for formatted pieces, `emit-all` for a buffer you already have.

## A chameleon literal at a phi is a DESTINATION question, not a join question

`emit-string` leaves a string literal unmaterialized: `is-lit=1`, `StrView` type,
`val` is the bare data GEP. `collapse-strlit-cstr` used to retype **every** such
branch to `CStr` before a cond/if/match phi, so the phi stayed a plain pointer.
That is right only when nothing downstream wants a view, and it made
`(if c "i16" "i64")` unable to fill a `StrView` slot.

The fix is not a smarter type join. A join sees only the arms; whether a view is
wanted is a property of the **destination**. `join-strlit-branch` (src/abi.nuc)
takes the same decision against the armed want (`g-want-type`, which `return` and
the implicit tail already set from the return type): collapse when nothing wants
a view, materialize `{ptr,len}` otherwise.

Materialization has to happen **in the branch's own block**, before its `br` —
that is the only block a phi operand may be defined in. Deferring it to the
join's consumer is not an option, which is why this is a hook in each arm
emitter (`emit-cond`, `emit-union-match-arms`, `emit-niche-match-arm`) rather
than one at the phi.

## An aggregate return sized from the VALUE reads past the slot, silently

`emit-struct-ret`'s first-class path spilled `(v 'val)` through an
`alloca (type-to-ir (v 'type))` and then loaded the return type's eightbytes back
out. Hand it a pointer-sized value for a 16-byte return type and it stores 8
bytes and reads 16 — and under **opaque pointers that is not a verifier error**,
because `store ptr %x, ptr %slot` is well-typed whatever `%slot` was allocated
as. The length came from whatever followed on the stack.

Two consequences worth generalizing. The alloca's type is the only remaining
record of a slot's size, so any path that writes and re-reads one must size it
from the **declared** type and refuse a mismatch — `emit-struct-ret` now does
both. And a garbage `usize` is not a crash: it became a `Vector` reserve request,
so the compiler aborted with `vector: out of memory` on *every* input, nowhere
near the defect. Suspect the most recently retyped struct return, not the
allocator.

## A `StrView`-returning function must bootstrap through a compiler that predates the fix

`src/type-utils.nuc`'s `ptr-int-ir` is written with explicit `return`s where its
neighbour `ptr-int-type` uses a nested `if`. That is not style: the boot binary
compiles `src/`, so a source shape is only usable once a *released* boot compiler
handles it. `(return "lit")` from a `StrView` function has worked since C6 step
2; the `if`-join shape works only in compilers built after C6 step 3. Prove the
new shape in `tests/fixtures/`, and move `src/` to it after the next
`make update-bootstrap`, not before.

## A `StrView` borrows to `ptr` SILENTLY — retyping a producer moves 30 consumers with it

`coerce-int-val` lets a materialized `StrView` flow into any `ptr`/`CStr` slot by
taking its `data` field. That is the rule (docs/strings.md), and it is what keeps
literals working at every libc seam — a literal's rodata is NUL-terminated at
`data[len]`. **A view built at runtime is not.** A `String`'s bytes end at `len`
and the next byte is spare `Vector` capacity.

So retyping one producer to `StrView` silently converts every consumer that still
declares `ptr`: no type error fires, and the pointer they get is only accidentally
a C string. Stage 17 C6 opened 32 of these with one change (`type-to-ir`), and the
2,596-artifact snapshot stayed byte-identical because fresh arena pages are zeroed
and `strlen` happened to stop in the right place.

Nothing in the gate set catches this, and no type marks it. What is left of the
boundary is enumerated instead: `scripts/check-cstr.py` (the `cstr-residue` unit
of `make test`) counts `CStr` and the libc string calls per file in `src/` against
`scripts/cstr-allowlist.txt` and fails on any difference either way, so a new one
must be justified deliberately. And prefer `=` on two `StrView`s to `strcmp` —
content comparison needs no NUL at all.

## The aggregate return path runs NO coercion — both its branches need the check

`emit-return` splits: ABI-DIRECT coerces the value against the declared return
type, non-DIRECT calls `emit-struct-ret` and coerces nothing. Inside
`emit-struct-ret` the split happens again, and both halves used to trust the
value they were handed:

- **first-class value** — spilled through an `alloca` sized by the *value's* type,
  then read back at the *return* type's width. Under opaque pointers a narrower
  store is well-typed, so this read past the slot silently.
- **by-pointer** (a struct literal / closure env arrives as a pointer) — read
  `(vv 'val)` as the ADDRESS of the return struct. Any pointer at all satisfied
  that, so `(return (info 'reg0))` on an IR type-name string became a wild
  16-byte load.

Both now refuse a value that is not the declared return type. The generalization,
which has now cost time twice: **`return` has two paths through the coercer, and
the aggregate one is the path that has none.** A fix applied to the DIRECT branch
looks complete and is half a fix.

## IR *text* is a `StrView`; an IR *name* is not — the boundary is identity

Two kinds of string flow through the emitter and they look identical in source:

- **operand text** — `%t42`, `match.end7`, `zeroinitializer`, a rendered
  constant. Written once into a stream and never compared. This is `StrView`
  (`Val.val`, `new-tmp`, every `-lbl`, `type-to-ir`, `gep-index-ir`).
- **a name** — what lands in `Sym.ir-name` or `Method.ir-name`. Interned,
  compared by **pointer identity**, and null-checked for "this has no name".
  `StrView` supports none of the three, which is why these are `Symbol`
  (Stage 17 C7).

Crossings must be an explicit `strview-from-cstr`, never `(as CStr …)` — that
cast is the silent borrow, and a name built by `fstr` is not NUL-terminated.
A name destined for `scope-define` is a `Symbol` — intern the `fstr` result;
do not view the C string. Two sweeps past this line failed in ways nothing typed
catches: a stray `^D` in the emitted module, and a segfault before any output.

## `Val.val` empty means void; `defvar-init-ir` empty means "no constant"

Both fields used to be `null` for those cases. An arena hands back zeroed pages,
so an empty `StrView` arrives for free and needs no separate sentinel — and
neither a void value nor a global initializer can legitimately be the empty
string, so the encoding is unambiguous. Test it with `strview-byte-len`, not by
comparing against `null` (which will not compile) or against `""` (which works
but reads as a content check).

## `strview-from-cstr` is STRICT where `(as CStr …)` was lazy

Retyping a producer to `StrView` turns each bridge into a real call. A
null-tolerant producer — `cheader-c-ident` passes null through, because a
marker parameter (`&optional`, `&rest`) has no name — then reaches `strlen(null)`
at the *binding*, where the old cast only crashed if the value was actually
used, and the guarded call sites downstream never were. Give such a producer its
own view-returning wrapper (`cheader-c-ident-view`) instead of bridging at each
call site: the null contract is then stated once, and cannot be missed at the
next site added.

## What `lib/node.nuc` imports, every AVR program imports — and `f64` is fatal there

`avr-reject-f64` (`src/abi.nuc`) refuses an `f64` **annotation** anywhere in the
translation unit, live or not. `lib/numeric.nuc:39` (`(extend f64 Ord)`) and
`lib/hash.nuc`'s `f64` conformance are both reached from `strview`, so importing
any of `numeric`/`hash`/`strview` into `lib/node.nuc` — or into anything
`lib/node.nuc` imports — makes every macro-using program un-compilable for AVR.
That is why `lib/intern.nuc` imports libc and `lib/fnv.nuc` and nothing else,
and why the fold lives in `fnv` rather than in `hash`. `tests/fixtures/avr2-16bit.nuc`
is the gate; it fails at the *import*, not at a use.

## Two `defn`s of one name in one TU resolve by overload mangling, silently

`lib/node.nuc` and `lib/intern.nuc` each had an `intern-grow`. Different arities,
so nothing errored: every module importing both emitted `@intern_grow.usize` for
one of them, and the generated C header declared `void intern_grow(void);` with
no `asm` alias — unlinkable. Library-internal helpers get a module-specific
prefix (`sym-node-place`, not `intern-raw-insert`); a mangled `@name.type` in
emitted IR for a function you did not overload on purpose is the tell.

## A header laid out behind a pointer must be sized by `sizeof`, not by a literal

`usize` is two bytes on AVR and eight on a host, so `Symbol`'s `[hash][len]`
header cannot be reached with `-8`/`-16`. Declare the header as a struct and
derive the offset from `(sizeof SymHeader)` — the same target-pointer-size
discipline `ptr-int-ir` follows. Narrowing an `i64` fold result to `usize` needs
`unsafe/cast` for the same reason: `as` refuses it where `usize` is 16-bit.

## A non-null-typed field has no "unset" value — zero the struct instead

`Symbol.p` is `(ptr ui8)`, so `(set! (c 's) null)` does not compile: there is no
null `Symbol` to assign. A `Node` that is an `INT` or a `CELL` still has no name,
and the answer is `calloc` plus `symbol-none?`, not a nullable field — the arena
already hands out zeroed nodes, so the invariant was true before it was typed.
Every hand-rolled `cons` in `lib/` and `examples/` had to move from `malloc`.

Where the absent case must be *written* rather than only recognised — a
`ptr:Symbol` out-parameter a parser leaves unset, a `let` initialised before the
parse that fills it — `symbol-none` mints it. `symbol-none?` is the only thing
its bytes are good for; the two ship as a pair.

## A registry PAYLOAD is not a name, however name-shaped the function looks

`binding-probe` takes a spelling and returns a **record** — `MacroDef*`,
`Protocol*`, `Sym*`. Two of its fourteen rows have no record and return the
spelling itself as a payload-free "yes", which makes the whole return read like a
name. It is not one: bridging it with `sym-of` interns a record pointer as a C
string, and the first trivial program segfaults. The tell is that the *caller*
stores the result in `BindingHit.payload` and hands it to `binding-nk`, which
casts it to `ptr:Sym`. Before retyping any `ptr`-returning lookup to `Symbol`,
read what its callers do with the result.

## `?`/`!` mangling is a COMPOSITION — `ir-name-token` first, then the blanket sanitize

`op-name-token`'s fallback is `(sanitize-for-ir (ir-name-token name))`, and the
three cheader paths spell the same order. Drop the inner call and `?`→`_QMARK`
silently degrades to `?`→`_`: every name still emits, every test still passes,
and the only witness is `make bootstrap` reporting `@contains_.pHashSet` against
`@contains_QMARK.pHashSet`. `sanitize-for-ir` cannot do it itself — it is a
blanket map that would rename every hyphenated symbol the compiler defines.

## Anything stored into `Node.s` must come from the INTERNER

A `Symbol` is a pointer to the first byte of `[hash][len][bytes…]`, so a pointer
to anything else — an `@.str.N` constant, an `arena-strndup` result — reads 16
bytes of whatever precedes it and typically SIGBUSes rather than returning
garbage. `emit-quote-tree` is the trap: it *emits IR that constructs a Node*, so
the check is not "does this compile" but "does the emitted call intern". It
calls `@symbol-intern-bytes`, which needs a `macro-jit-declare-raw` at **both**
JIT declare sites (a JIT module only gets `declare`s for functions registered in
the unit being compiled).

## `print-node` is a canonical printer, and `--emit-nuch` is its only consumer

`fprint-node` (`src/nucleusc.nuc`) is what `--emit-nuch` writes macro bodies
with, which makes it a *round-trip* obligation: whatever it prints has to read
back as the same tree. It was not treated as one, and Stage 18 TF-3 found three
ways it silently lost information — a `NODE-CHAR` fell through the `case` and
printed **nothing** (so `lib/io.nuch` exported `println` without its newline,
and any multi-TU build importing that header got a `println` that behaved as
`print`), `c"…"` printed as `"…"` (NS-4's CStr flag lives in `NODE-STR.i`), and
the default byte case did `(emit out (as Char (as ui32 c)))`, widening each
*byte* to a codepoint and re-encoding it as UTF-8 so `"hé"` came back `"hÃ©"`.

**Adding a `NodeKind` means adding a `node-write` arm** (`lib/read.nuc`), and
its default arm must stay unreachable rather than silently drop a node.

Neither `check-headers` nor the IR snapshot catches this class: both compare the
compiler's output against *itself*, so a lossy printer is consistently lossy and
stays green. `print-node` is a wrapper over `lib/read.nuc`'s `node-write`; R-4's
round-trip unit reads the output back.

## The reader is `lib/read.nuc`; the compiler's diagnostics are `src/diagnostics.nuc`

Since Stage 21 R-2 (`design/stage21-cleanup/one-reader.md`) `src/reader.nuc` is
gone and `lib/read.nuc` is the only reader — standalone-compilable, used by the
compiler, `lib/test.nuc` and any program. A reader error reaches a caller as a
`ReadError` value (`code line msg note`, arena-owned strings; `docs/reading.md`
§`ReadResult`), not a `report-at` call: `lib/read.nuc` has no diagnostics
dependency and cannot have one (`context/macros-jit.md`'s "a macro body cannot
call `die-at`/`report-at`" is exactly this same layer, one file over). Adding a
new reader diagnostic is adding a new `msg` wording at the fault site in
`lib/read.nuc`, nothing else. The compiler is the one caller that renders a
`ReadError`, through `read-source-or-report` (`src/nucleusc.nuc`), which calls
`report-at`/`diag-stage-note` (`src/diagnostics.nuc`) with the value's fields.
The general rule this generalizes: a library whose failures carry context
returns its own `E` and registers one `defcast E Err`, never side fields on a
handle — `docs/errors.md`'s two-tier principle (`Err` the code, `(Result T E)`
the payload).

A collection literal reaches the compiler as `(vector-lit e …)` with **no**
gensym element: `emit-collection-lit` mints the hygiene symbol itself, at
emit, so `__gs_N` numbering is emission order and a `--dump-ast` tree carries
none. Nothing may rely on the second element of a `*-lit` cell being anything
but the first element.

## `readdir` order is not an ordering — `lib/file.nuc`'s `read-dir` sorts

`read-dir` returns entries **sorted by name**, and the compiler's
`scan-dir-for-definer` goes through it. Anything that was "first match wins"
over `readdir` was previously decided by the filesystem: the same tree on
another machine, or after a rename, picks a different first match. One
diagnostic in the corpus depended on it (`w9-unknown-type-ctor-unimported`
named `lib/vector.nuch`; it now names `lib/vector.nuc`, which is also what
`resolve-import` would pick). If you add a directory scan, do not re-derive an
order from `readdir` — and if you need first-match-wins to mean something, say
which order in the code.

The `d_name` offset lives in `lib/file.nuc` **once**. Do not re-declare
`opendir`/`readdir`/`closedir` in a second module: the C-header reader registers
`struct dirent` opaque (its `char d_name[256]` is a shape the declaration parser
declines), so the offset is a hardcoded 19, and two copies is two things to be
wrong. It is validated, not trusted — `.` and `..` exist in every POSIX
directory, so `read-dir` fails when they do not appear.

## `str-into` re-evaluates its target once per piece

`(str-into (test-fail-begin) "a: " x)` calls `test-fail-begin` **twice** — the
macro expands to one `string-push-*` per piece, each against the target
expression as written. That is harmless for a plain binding and a live bug for
a target with a side effect: a `begin`-shaped target clears the buffer between
pieces, so all but the last piece disappear.

The same shape bites when a piece READS the buffer the target writes: converting
a skip into a failure (`lib/test.nuc`, `--no-skip`) has to copy the reason out
of the failure buffer *before* beginning the replacement message, or the
message comes out empty with no error anywhere. Bind first, then push.

## `(parse f64 …)` takes a hex float with NO exponent — so an LLVM bit pattern parses

`(parse f64 "0x3FF0000000000000")` returns **4.6e18**, not 1.0. C's *grammar*
requires a hex float's binary exponent, but `strtod` — which `lib/parse.nuc`
delegates to — makes it optional, so LLVM's 16-hex-digit f64 **bit pattern**
parses as an integer-valued hex float and every digit is consumed. There is no
error to notice: `parse` only rejects trailing garbage, and there is none.

Anything reading a `0x`-prefixed float field has to decide which of the two it
is before parsing. `fl-value-bits` (`tests/suite-float.nuc`) branches on the
absence of a `p`/`P`: no exponent means the text *is* the bits, so it goes to
`strview-parse-magnitude` with radix 16 instead.

## `g-def-buf` is the emitted module's own TAIL — which is how a byte offset into it is checkable

`assemble-module-ir` appends `g-def-buf` **last**, after the type section, the
string table, the deferror table and `g-decl-stream`. So the definition buffer is
a suffix of the module text, and an offset recorded into it can be verified
against a `--emit-llvm` dump with no new plumbing: slice the last `byte-len
g-def-buf` bytes off the `.ll` and index straight in. Stage 20 L1's span
verification is exactly that, and L3's will be.

The offsets themselves are a claim about **which** buffer, and `g-out` is not one
buffer — `compile-macro-body` and `emit-compile-time` point it at a module's
private stream, `emit-import-forms` at an `import-ct` sink, the REPL at its
per-entry buffers. `ct-span-recordable` (`src/scope.nuc`) is the guard: `g-out`
must be `g-def-stream-program` *and* that must be `&g-def-buf`. This is the
"a latch is a claim about a buffer" rule above applied to an offset rather than a
boolean, and the failure is quieter — a wrong offset is a plausible number.

Two shapes that recur whenever a mark and a close bracket an emission:

- **Take the mark before the `emit` it measures.** L1's design said
  `program-defn-record` sat one line before `emit g-out "define "`; it sat one
  line after, so the recorded start would have pointed past the define's own
  header. Read the call order, do not take the comment's word for it.
- **Offset 0 is a legitimate offset**, so it cannot double as "no mark". Close
  the span by re-asking the guard, not by testing the start against 0, and make
  the opener return null when it declines so the closer has nothing to write.

## `LLVMSearchForAddressOfSymbol` returns null until `LLVMLoadLibraryPermanently` has run

It searches only the handles `LLVMLoadLibraryPermanently` opened, so without a
one-time `LLVMLoadLibraryPermanently(null)` (null = this process) the search set
is **empty** and every lookup answers "not exported" — measured, not assumed:
with the call removed, `node-at`, `alloc-node`, `intern-symbol`, `desugar-form`
and `printf` all came back 0 from the same binary that exports all five. There is
no error and no diagnostic; the call site just gets a plausible negative.

Two things follow. The lazy `LLVMLoadLibraryPermanently` is not redundant
initialisation and must not be tidied away. And any gate on a process-symbol
lookup has to **assert a positive** — "it returned 0 and nothing crashed" is
exactly what a broken lookup looks like, and for `host-exports?` (Stage 20 L2)
the false negative is also the *safe* direction, so nothing downstream will
complain either.

This is also the reason the pair is used at all instead of
`dlsym(RTLD_DEFAULT, …)`, which is shorter and already linked (`-ldl`,
Makefile): `make windows-boot` cross-emits the compiler's own source to
`x86_64-pc-windows-{gnu,msvc}`, and a POSIX-only extern lands in both IRs. A
declare the host never links is invisible here and fatal there — check
`boot/nucleusc-x86_64-windows-*.ll` before reaching for a libc facility in
compiler code.

## A "reset per body" latch that is never RESTORED cannot carry a per-body result

`g-macro-decls` is created fresh at the top of `compile-macro-body` and
`emit-compile-time` and left there — nothing puts the previous one back. That is
survivable for a dedup set (the worst case is a redundant `declare` in a module
nobody re-enters) and fatal for anything the caller reads afterwards.

Stage 20 L4's mirror roots are read afterwards, and §5.3 said to accumulate them
"alongside the existing `g-macro-decls` latch". Copying the idiom loses them, and
one shape proves it — a `macrolet` compiled **inside** a `defmacro` body:

```lisp
(defmacro outer ()
  (macrolet ((inner (k) `(mk (_+ (base) ~k))))
    (inner 2)))
```

`macrolet-bind` opens a second body midway through the first, so the reset points
the global at the *inner* binding's vector; the calls the inner template then
splices are `outer`'s, and they land nowhere. Measured: with the restore removed
this file fails `Symbols not found: [ mk, base ]` — mode 1 again, in the one
shape a tree of top-level macros never reaches. Save and restore beside the
stream pointers, which that function already does for `g-out`/`g-decl-out`.

The general form: before copying a neighbouring global's lifecycle, ask whether
the neighbour is *read* after the body ends. `g-macro-decls` is not, so its
missing restore is invisible; a latent one, since a nested body does silently
inherit the wrong dedup set.

## A macro body's callees are all emitted BEFORE the body compiles

Stage 20 L4 flushes the compile-time mirror at `expand-macro-call`, and §5.5
gives the reason as "a callee defined between the `defmacro` and its first call
site is only emitted by then". That reason does not hold. A root is recorded by
`macro-jit-ensure-decl`, which needs a `ProgDefn` — and `program-defn-record`
runs at `emit-defn`, so a callee not yet emitted has no `ProgDefn`, gets no
`declare`, and never becomes a root. It is mode 2 (`use of undefined value
'@f'`), with or without the mirror. Flushing at `defmacro` time would therefore
reach exactly the same set.

Expansion time is still the right site, for two reasons the document does not
give: a macro that is defined and never called emits no module at all, and a
`macrolet` compiled mid-`emit-defn` would otherwise try to copy the enclosing
function's span while its `ir-end` is still 0.

## An early return with four reasons cannot become a diagnostic about one of them

`macro-jit-ensure-decl` returns without emitting a `declare` whenever
`program-defn-lookup` answers null, and Stage 20 L5 had to turn **one** of those
reasons — a callee the unit prescanned but has not emitted — into a located
error. The design gave the test as "resolves in `g-globals` to a `TY-FN` `Sym`
with no `ProgDefn`". That is also true of a `defn` defined inside the
`(compile-time …)` block being compiled: `program-defn-record` declines under
`in-jit-module` **by design** (the defn already lives in that module), while the
block's own signature prescan registers it as a global `TY-FN` `Sym` with
`@fname`. Measured — with the extra guard removed, a CT block whose `defn` calls
another `defn` of the same block fails `calls 'ct-inner', which is defined later
in this unit`, a file that compiles and prints 42 with the guard in.

The separators are cheap once enumerated: `is-local` rules out a local and a
function-pointer value, a scan of `g-decl-stream` rules out an extern, a C-header
import and an intrinsic, and the fourth needs a per-body set that did not exist
(`g-ct-module-defns`, fed from the CT prescan *and* from `emit-defn` under
`in-jit-module`, because the prescan's `@fname` and `defn-ir-name`'s mangled
spelling can differ).

The general rule: **before narrowing a guard into a diagnostic, enumerate every
reason the guard fires and write one probe per reason.** A false positive here is
worse than the leak it replaces — the leak was ugly output on a program that was
already broken; the false positive rejects a program that works.

## A JIT module needs the `declare` for a function it NAMES, not only one it calls

`macro-jit-ensure-decl` hung off `emit-call-with-args` alone, so a macro body
that took a program defn's *address* — `(let (f:(fn i32)(i32) twice) (f 21))` —
emitted `store ptr @twice` into a module that declared nothing, and LLVM answered
`use of undefined value '@twice'` for a callee defined **above** the macro. A
call and a value use reach an `@name` by different paths, and only the call path
was instrumented.

`emit-symbol-ref-bound`'s function-materialization branch is the other one, and
it is already marked as the single chokepoint for value uses (AVR-6's
addrspace(1) check sits there for the same reason). Anything that must happen
per reference to a global function — a declare, a link-name record, a target
check — belongs at **both** sites or it has a hole shaped like function
pointers.

## When a reference has no chokepoint, scan the IR the emitter already produced

The entry above fixed a call site and a value site for a *function*. A program
**global** has four — a read (`emit-symbol-ref-bound`'s load), a `set!`, an
`addr-of`, a member GEP — and no one of them is marked as the place a global
becomes a link name. Stage 20 L6 needed a `declare` and a mirror root per
reference, and instrumenting those four would have left a fifth.

So it asks the module's own finished IR instead (`ct-scan-body-globals`, once per
macro/CT body, over `g-entry-stream`/`g-body-stream`/`ct-def`). The text is the
ground truth the mirror's closure walk already trusts, and it cannot have a hole:
whatever route put `@g` into the module put it in the text.

Two mechanics that make it safe: the declares are written to a **side buffer**
and appended afterwards, because `emit` reallocates a `String` and would leave
the `StrView` being scanned dangling; and a name the module *defines* is not a
reference, so a global's own span — which since G-2 shape 4 can hold both
`@g.data = private constant …` and `@g = global ptr @g.data` — is scanned with
"skip what this text defines" on.

## A "reset per flush" latch nests too, if the flush can emit code

`ct-mirror-flush` (Stage 20 L3) reset its worklist globals at entry and never
restored them — the `g-macro-decls` idiom L4 had already found fatal once, and
safe here only while a flush emitted no code. L6 made it emit a `defvar`'s queued
initializer with `emit-node`, which expands macros, and an expansion **flushes**:

```lisp
(defmacro dbl (k) (if (= (s20-t2 3) 6) `(_* ~k 2) `0))
(defvar g-n:i32 (dbl (s20-seed)))      ; the initializer expands a macro
```

The inner flush repoints the vectors and the outer walk resumes on them —
`Symbols not found: [ s20-readn ]`, measured. The fix is the same one L4 reached
for: split the body out and make the entry point a save/restore wrapper. Any
counter the nested call also mints from (`g-ct-init-id`, which names
`@__ct_init_N`) has to be **claimed at mint time**, not when the caller finally
decides to use it, or two live flushes pick the same number.

## The cursor you were told to snapshot may not need reading at all

`design/global-init.md`'s runtime-initializer queue has one persistent cursor,
`g-init-drained`, and the program's `@__nucleus_init` is emitted from whatever it
leaves. Stage 20 L6's design said the compile-time copy should drain from a
*snapshot* of that cursor and restore it afterwards — plausible, and wrong twice:
a snapshot drain emits `set!`s for globals the mirror does not define (an
undefined `@g` in the module), and the restore makes the **next** flush re-emit
the same jobs, running a shared global's initializer a second time.

The filter that is correct selects jobs by the globals *this* module defines
(`InitJob.ir-name` against the mirror's copied set), which a define-exactly-once
set already makes single-shot. The cursor is then never touched, and "the
program still gets its initializers" holds by construction rather than by a
restore someone has to remember. **Before implementing a save/restore of shared
state, check whether the operation needs to read that state at all** — the
version that never touches it cannot be got wrong on a later path.

## A per-invocation object is not an identity — compare the fact, not the handle

`target-init` sets `g-target` to `g-host-target` **only** when no `--target=` was
given; any `--target=`, the host's own triple included, builds a second `Target`
through `make-target-for-triple`. So `g-target != g-host-target` answers "was a
`--target=` flag passed", not "is this a cross-compilation", and Stage 20 §5.9
spelled its refusal that way. Under the object test
`--target=x86_64-pc-linux-gnu` on an x86_64 host — same triple, same datalayout,
same ABI — is refused for nothing.

The test that means what the sentence means is the one `src/cheader.nuc` already
uses for the same question: `g-target-triple` against
`((as ref:Target g-host-target) 'triple)`, two interned `Symbol`s. Reach for the
field the decision actually turns on; a freshly-built handle is never evidence of
difference, and `==` on it is never evidence of sameness.

## A refusal makes the condition behind it observable from outside

Stage 20 §6's gate was "the bootstrap flushes zero compile-time mirror modules",
and through L7 the only way to read it was a throwaway `eprint` in the emitter,
rebuilt twice per measurement. L8 added a refusal on a *different* axis —
cross-compiling a body that needs a mirror — and because a flush is refused
**iff** a flush is required, "this unit mirrors nothing" became an exit code:
`nucleusc --target=riscv64-unknown-linux-gnu --emit-llvm src/nucleusc.nuc`
succeeding says it, and so does every green `make avr-test`.

Worth looking for whenever a phase adds a guard: a condition that used to need
instrumentation may already be reported by some *other* path that refuses on it.
The throwaway is still how you prove the guard itself works — a marker that fires
**5 times under `make test`, in exactly the five units written to exercise the
path**, is what makes the zeroes elsewhere a measurement rather than a broken
`eprint`.

## A swap cannot serve a nested reader — when shared state must stay readable, use a WATERMARK

Stage 20 S1 gave each compile-time module its own string-literal table.
`design/stage20-macros/string-table-per-module.md` prescribed the obvious shape:
save `g-strs` in the "redirect global state" `let` beside `saved-qq-used`,
install a fresh vector, restore. It also carried one documented exception —
`ct-mirror-flush` must keep emitting the **program's** table, because the
`define` spans it copies out of `g-def-buf` name program `@.str` ids.

**The two are incompatible, and the reason generalizes: the exception is
reachable from inside the bracket.** `expand-macro-call` flushes a mirror before
every expansion, a macro body is itself compiled with `emit-node`, and
`ct-mirror-build-init` runs `emit-node` over a program global's initializer — so
a mirror is built while the swapped-in table is live, and "leave that call alone"
then means "give the mirror the CT body's table". Measured on a throwaway build:
`use of undefined value '@.str.29'`. It cannot be patched either, because under
a swap the mirror would need *both* tables and both start at `@.str.0`.

The shape that works keeps one object and records a position in it: each path
notes `(count g-strs)` as a **watermark**, the emitter takes it as a `from`
parameter and writes only the tail, and a truncate drops that tail when the
module is assembled. Every reader keeps seeing the program's ids at all times,
so the nested case is right by construction rather than by a restore.

Two rules:

* **Before writing a save/restore of shared state, ask who else reads it while
  the bracket is open.** If any nested call needs the *original*, a swap has no
  way to hand it over — an ambient global cannot be two things at once. This is
  the sibling of `g-def-stream-program`, which solves the same problem by
  keeping a second name for the real one; a watermark solves it by never taking
  the name away.
* **A watermark degrades better under `die-at`.** A longjmp past a truncate
  leaves the program a few extra rows; a longjmp past a restore leaves the
  program pointing at the *wrong table entirely*.

The call-site census is worth its own line: the design tabulated four
`emit-string-table` callers and the tree has five — `src/repl.nuc` assembles a
REPL entry's own program module and never appeared in a plan written against
`src/nucleusc.nuc`. Grep the whole tree for the function you are about to change
the signature of, not the file the design was written from.

## When no window can separate the two kinds, filter at the CONSUMER — and count every EMITTER of a reference

S1's watermark (above) fixes a leak whose window is *entirely* discardable. Stage
20 S4 is the case where that premise fails: `emit-import-forms` runs the emitter
into a throwaway sink for a compile-time-only import, so the bodies' `@.str`
references are discarded while `intern-string` still appends — but
`emit-toplevel-forms` runs `drain-mono-worklist` at every depth, and a drain
writes to `g-def-stream-program`, the *real* program buffer. So one window
receives discardable and live entries interleaved. A watermark truncating it
dangles a live reference; not truncating is the leak; and with a positional id,
promoting the survivors out of the tail renumbers everything after them.

**The move is to stop tracking provenance and ask the output what it uses.**
Emit what the module references rather than what was interned: scan the assembled
buffers, drop the rest. It closes the class *by construction rather than by
enumeration* — a future path that interns into a discarded stream is covered
without being found first, which matters, because the sweep for the first one is
how the second surfaced. Two preconditions, both cheap to check and both true
here: the emitted name must come from a **stored id** and not a loop counter (so
the table may be sparse and dropping an entry renumbers nothing), and the
consumer must be able to see the module's whole text.

**The trap is the census, and it is not the call-site census.** A derived
referenced-set has to enumerate every *emitter* of a reference, and a table built
from **parallel id vectors has one emitter per vector**. The plan named
`g-deferror-name-sids`; `emit-deferror-table` emits from that one *and*
`g-deferror-msg-sids`, both after the string table and so in none of the scanned
buffers — a filter built to the plan as written emits a module that references
its error messages and defines none of them. `tests/fixtures/s1-sugar-rets.nuc`
was already the witness in the tree. Also: a reserved index-0 placeholder emits
as `ptr null`, so mark from 1 — marking slot 0 holds a genuinely dead constant
alive in every program that uses the feature.

**And re-derive every proxy the filter invalidates.** `emit-string-table` closed
with `(when (> (count g-strs) from) …)` as a stand-in for "this module emitted at
least one row", which was equivalent only while every row in the window *was*
emitted. Once rows can be dropped it must become a latch set by the emit itself,
or a module whose whole window is filtered keeps a separator with nothing above
it. Scan for this class whenever a filter lands between a count and its use.

The gate for a change like this is the one the leak makes available: if the
compiler's own module already had zero of the thing being dropped, the filter is
a **no-op on it**, and `make bootstrap` must stay byte-identical with no boot
convergence. That prediction is also the sharpest correctness test on offer — IR
that moves means the filter is dropping something live.
