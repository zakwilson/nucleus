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

## `coerce-int-val` is THE coercion chokepoint — and one caller reads a null return as "do nothing"

Despite the name, `coerce-int-val` (`src/abi.nuc`) is not integer-specific: it
is the single implicit-coercion chokepoint for `ptr`/`CStr`/`StrView`, integers,
and (since Stage 15 W2d) floats. Everything that assigns a value into a *typed
slot* routes through it — `let`/`with` init, `set!`, `.set!` field store,
explicit and implicit `return`, struct-literal and array initializers (positional
**and** designated are separate call sites), union-variant construction — plus
`coerce-num-val` (binops) and `safe-coerce-val` (call arguments) which delegate
to it. **Add a new implicit conversion here, not at the call sites.**

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
bitten **three** times, each found while working on something else:

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
CELL return (e.g. `(defn constantly ((v V) &where (Ord V)) (BoxedFn (V) V) …)`)
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

## `?`/`!` in names map to `_QMARK`/`_BANG` in emitted symbols

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
(src/abi.nuc) — the sole StructDef allocator (`repl-register-node`, the anon-struct/
union, fatptr/boxedfn/dyn, and closure-env builders all route through it), so setting
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

`lib/reader.nuc` `read-form` handles `TOK-SYMBOL` as
`(return (ok (intern-symbol (t s))))`: every occurrence of a spelling anywhere
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
  `run_no_line_zero` in `tests/run-tests.sh` (compiles every fixture, fails on
  any `:0:`) plus a `:0:` check inside `run_reject` itself.
- **Never `(.set! sym line …)`.** The write is observed by every *other*
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

Bracket balance is tracked in `next-tok` (`reader-open-bracket` /
`reader-close-bracket`, `lib/reader.nuc`) as each bracket **token** is produced,
covering `(`/`)`, `[`/`]`, `{`/`}`, `#{`/`}`. Two properties are load-bearing:
the depth is **not clamped at zero** (a negative depth is exactly "this closer
has no matching opener", which is what distinguishes a stray top-level `)` from
a `)` inside an unclosed `[…]`), and because it counts tokens rather than
characters it is immune to a bracket inside a string literal or comment — unlike
a naive external paren counter. The four globals (`g-paren-depth`,
`g-form-open-line`, `g-col0-open-line`, `g-col0-open-depth`, declared in
`src/nucleusc.nuc` beside `g-peek`) are reset at the top of **`read-program`**,
not save/restored at the three import sites that save `g-src`/`g-pos`/`g-line`:
`read-program` is the single whole-file read entry (batch, import, REPL) and
reads never interleave, because an import is processed during *emission*, after
the importing file's own read has completed.

Column-0 detection needs no column counter: at the moment a bracket token is
produced `g-pos` still points at the bracket, so `g-src[g-pos-1] == '\n'` is
exactly "this bracket is the first character on its line". Prefer that
lookbehind to threading a column through `next-char` — one fewer invariant a
future lexer path can forget. (Verified: idiomatic Nucleus has **zero** column-0
`(` at nonzero depth across `src/`, `lib/`, `examples/`, `tests/`, which is what
makes "a column-0 `(` while a form is open" a reliable imbalance signal.)

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
spellings at lex time, so `(. fn-node s)` is the canonical string) and stored field
names are interned at build time via `intern-str` (interns the spelling, returns the
canonical string pointer). The three field-access paths — `.` (`emit-field-get`),
the `get` intrinsic (`emit-get-intrinsic`), and the non-emitting type pass
(`node-type-field`) — all route through `struct-field-index`, so they cannot drift.

There are exactly **two** places that populate a StructDef's `field-names`:
`emit-defstruct` (the normal path, incl. `.nuch` imports) and `repl-register-node`
(the REPL's hand-built `Node`). **Both must intern each name** (`(intern-str fname)`).
A raw string literal would `strcmp`-equal a selector but **not** be pointer-identical,
so the field would silently look absent (`-1` ⇒ "no field" / null type). If you add a
third StructDef builder, intern its field names too. The `make bootstrap` fixed point
does **not** exercise the REPL path — the `repl-redefinition` test does (its `*`/`-`/`if`
macros do `(. (cast ptr:Node args) cdr)` at expansion time), so keep `make test` green,
not just `make bootstrap`, when touching field interning.

**Field TYPES drift too — `repl-register-node` must mirror `lib/prelude.nuc`'s `defstruct Node`.**
The same lockstep that applies to field *names* applies to field *types*: every field-type
slot `repl-register-node` writes must match the canonical `defstruct Node` in
`lib/prelude.nuc` (and `lib/list.nuc`). When `car`/`cdr` were retyped `ptr`→`(raw Node)`
for macro ergonomics, `repl-register-node` was missed and kept assigning bare `ty-ptr`.
The symptom is subtle: a macro that reads `(p car)` once and binds it works (bare `ptr`
flows into a `(raw Node)` slot), but a macro that **chains** without a cast — e.g.
`((spec cdr) car)` in `dotimes` (lib/macros.nuc) — dies in `emit-get-intrinsic`
(src/nucleusc.nuc:~2056, "callable value: not callable — no matching get/invoke method
and not a pointer-to-struct") because `(spec cdr)` returns an untyped `ptr` (elem=null),
so `ek` resolves to `TY-VOID` and the `TY-STRUCT`/`TY-UNION` gate fails. This fires the
moment the REPL JITs any new-ergonomics macro, so `nucleusc -i` dies at startup inside
`repl-preload-macros` and `(import-use macros)` dies interactively even with the preload
removed — the failure is independent of *when* the macro library loads. Build the typed
slot with the same pattern the macro emitter uses (src/nucleusc.nuc, `make-type TY-PTR`
+ `elem` = `(parse-type-name "Node" 0)` + `pkind PTR-RAW`); `parse-type-name` succeeds
because `register-struct "Node"` already ran earlier in the same function.

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
- **Guard before a `kind`/`s` test in a marker scan.** `&rest`/`&optional`/
  `&where`/`&repr` scans run over the raw element list before any validation, so
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
(`fuse-colon-paren`, `lib/reader.nuc`) — which absorbs *one* paren form after a
trailing-colon atom — cannot express a function-pointer type by itself.
`fuse-fn-params` (added in W5f, called from `fuse-colon-paren` right after the
first `read-form`) absorbs a **second, immediately-adjacent** group when the
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

## The string-type lattice: `ptr` / `CStr` / `StrView` — gate pointer ABI on `is-ptr-like`, not `TY-PTR`

There are three string-carrying types. `TY-PTR` (bare pointer, identity `=`) and
`TY-CSTR` (C-string, content `=`) are both single-word, ABI-identical to `ptr`.
`StrView` (the `"…"` literal type since NS-3, Stage 14) is a 16-byte
`{data:(ptr ui8), len:usize}` borrowed-view struct — **not** pointer-ABI. A plain
string literal is `StrView`, not `CStr`; the `c"…"` literal (NS-4) and any
`:CStr`-typed FFI parameter/return are `CStr`. The interned-symbol substrate
(`Node.s`, scope keys, struct-field names) stays `ptr` — never retype it (below).

`TY-CSTR` lowers to `ptr` in IR and is a plain `char*` at the ABI. It is a
*distinct kind* only so `=` / `!=` dispatch to a `strcmp` content comparison
(`emit-binop-vals`) instead of pointer identity. **Everywhere else it must behave
exactly like `TY-PTR`:** `type-to-ir` → `ptr`, `type-size` → 8, zero-init →
`null`, `cast` to/from `ptr` is a no-op, and it must never be `inttoptr`'d (it is
already a pointer). A bare `(= (. t kind) TY-PTR)` ABI check therefore *misses*
`CStr` — use the `is-ptr-like` predicate ({`TY-PTR`, `TY-CSTR`}; `TY-FN`
deliberately excluded, `StrView` is a struct not a pointer). This bit the
`&rest` arg-folding (`emit-call-with-args`), which `inttoptr`'d any non-`TY-PTR`
arg and produced invalid `inttoptr ptr→ptr` for a `CStr` rest arg. When adding a
new pointer/integer ABI decision, branch on `is-ptr-like`.

This trap has now been hit **three** times: the `&rest` folding above, W5c's
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

**`TY-FN` is NOT in `is-ptr-like`, and it is not going to be — admit it by name.**
The exclusion is deliberate and load-bearing (`is-ptr-like` also gates the free
`ptr`↔`CStr` value coercion and the `=`/`!=` strcmp lowering, neither of which a
function pointer should join), so every site that needs "lowers to `ptr`" in the
*storage/constant* sense spells it as an extra arm beside the predicate:
`emit-zero-store` has `(when (= (ft kind) TY-FN) (set! zero "null"))` next to its
`is-ptr-like` line, `type-zero-const-ir` has the same, and W8's fn-pointer-global
fix added the third — `defvar-init-ir`'s `null` gate. Widening `is-ptr-like`
itself to "fix" the next one would silently make `(= some-fn-ptr some-cstr)` a
`strcmp`. Note that `abi-alignof`/`abi-sizeof` already answer `g-target-ptr-bytes`
for `TY-FN` while **`type-size` does not** — it falls through to `1`, so every
fn-pointer global/local/field slot is emitted `align 1`. Valid but conservative
IR; if you fix it, know that it moves the IR of every fn-pointer-slot program
(`examples/fnptr.nuc`, `fn-ptr-union.nuc`, `l7-probe.nuc`) though not the
compiler's own, which contains no `TY-FN` slot.

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
`Method.ir-name` stay `ptr` because *they* are null-checked; the same danger
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
is the symbol `null` and the other operand is `is-ptr-like`, emitting the
`icmp eq ptr` identity test instead. `strcmp(x, NULL)` is undefined behaviour
in C and segfaulted under glibc, so no correct program could depend on the old
lowering; the fix is strictly a bug fix. Consequence for the paragraph above:
`(when (= irn null) …)` in a `CStr`-typed parameter's body is now **safe**, and
a null-check alone is no longer a reason to keep a value `ptr`. This was found
while making a `CStr`-typed `defvar` spellable — `(defvar g:CStr null)` would
otherwise have compiled into a global whose only natural use crashed.

**What remains a trap is the identity-vs-content half**, which is unchanged:
retyping a value `ptr`→`CStr` still turns every `=`/`!=` against *another
string* into a content comparison, so an identity-substrate value (`Node.s`,
struct-field names, any interned pointer compared for sameness) must still stay
`ptr`. Audit for `(= a b)` where both sides are strings and sameness — not
equal text — is the question.

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

## Member access is head position `(s field)`; `_get` is the bypass primitive

The `.` field-access special form was renamed **`_get`** (compiler-internal
primitive; `emit-field-get`) and ordinary code uses **head position `(s field)`**
instead (the callable-values `get` path: Struct-blanket intrinsic, byte-identical
GEP+load). `.set!` is unchanged (writes stay `(.set! s f v)`). Two non-obvious
hazards — both bit the `.`→head-position migration and are why `_get` still exists:

- **A user `get` method must read its own fields with `_get`, not head position.**
  `(self field)` inside a `(defn get … (self:ptr:T sel))` dispatches back into that
  same `get` method → infinite recursion → segfault. Use `(_get self field)` (direct,
  bypasses the override). Head position respects user `get` overrides; `_get` skips them.
- **A struct held in a variable named like a special form or macro collides.**
  `(cond field)` parses as the `cond` special form (special forms/macros are
  dispatched before scope lookup). Fix by renaming the variable (preferred) or using
  `(_get cond field)`. **Functions don't collide** — a local shadows them in scope
  lookup, so `(localvar field)` is member access even if a function shares the name.
  The migration script special-cases reserved-named *direct* heads (`(. cond f)` →
  `(_get cond f)`); a reserved-named **`->` base** (`(-> cond … (. type))`) is not
  caught and must be renamed.

**A bare selector falls back to a value when the callee has no such field (W7).**
`(s field)` still names a field whenever `s`'s type *has* that field — that rule
is unchanged and is why the two hazards above still bite. But when the callee
provably has no such field and the symbol is a **local** binding, the selector is
demoted to a value, so `(m k)` on a `(HashMap CStr i32)` looks up by `k` instead
of dying with "no field 'k'". Two things this does **not** do, both deliberate:
a **field name wins** over a same-named local (`(m count)` is `HashMap`'s `count`
field), and **globals never demote** (every function is in the global scope, so
demoting on globals would re-interpret `(sd name)` the moment a global `name`
existed). For both, `(invoke m count)` is the always-a-value escape hatch —
`invoke` now falls back to `get` when no `invoke` method accepts the receiver.
The demotion cannot change code that compiled before: any such site resolves its
field, so the gate is false there (verified by A/B-diffing emitted IR for every
example against the pre-change compiler — 135 byte-identical, 0 differing).

The `->` macro (`lib/macros.nuc`) was extended to substitute `_` in **head**
position (it scans the whole form, not just args), so a threaded value can land in
call position: `(-> s (_ field))` ⇒ `(s field)`. The migration rewrites a 1-arg
`->`-step `(. field)` to `(_ field)` and a normal `(. s field)` to `(s field)`.

## A by-value struct parameter needs `(addr-of v)` before field access

Head-position `(v field)` and `_get` both require a **pointer-to-struct**
receiver: `emit-field-get` (`src/nucleusc.nuc:2172`) gates on `pt.kind == TY-PTR`
with a `TY-STRUCT`/`TY-UNION` elem, and the callable `get` path raises "callable
value: not callable — no matching get/invoke method and not a pointer-to-struct"
otherwise. A function parameter typed `v:StrView` (by value) is a `TY-STRUCT`,
not a `TY-PTR` — so `(v data)` / `(_get v data)` both fail at emit time. The
`(ref StrView)` spelling works because it is already a pointer. For a by-value
struct param, bind a pointer once and access through it:

```lisp
(defn intern-string (sv:StrView):i32
  (let (p:ptr:StrView (addr-of sv) ...)
    (.set! sl bytes (arena-strndup (cast ptr (p data)) (cast i64 (p len))))))
```

The `=` conformance (`lib/strview.nuc:152`) and `examples/comb-order.nuc:30`
(`((addr-of sv) len)`) use the same `addr-of`-then-access shape. A `let`-bound
struct local is already an alloca (addressable directly); only **by-value
parameters** need the explicit `addr-of`. (NS-5 adoption.)

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
  body; `abi-print-param` is now the `g-out` wrapper over it). Any future
  emitter writing to a stream other than `g-out` needs the `-to` spelling —
  redirecting `g-out` around a declare is not the idiom.

**A fourth site is still broken and is a different bug**: `jit-thunk-module`
(`src/repl.nuc`) emits its thunk `define` with raw `type-to-ir` **and** into a
module carrying no `%Name = type {…}` line, so a by-value struct in the REPL
dies at `use of undefined type named 'Pt'` before any declare matters. By-value
structs therefore do not work in the REPL at all today — which is also why the
two REPL fixes above are correct-by-construction but cannot be exercised yet.

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
`tests/fixtures/rv6-fp-abi.nuc` + `run_rv6_fp_abi` pin permanently, together
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

## Avoid untyped pointers

Passing around untyped pointers and using casts is unsafe and must be reserved as an escape hatch, not standard practice. When using a cast, **always** check whether it's possible to change the design so that all values are well-typed.

## A special-form spelling sweep must also grep for `intern-symbol "…"` synthesis, not just literal text

A tree-wide rewrite of a special-form spelling (the Stage 14 `cast`→`as`/`unsafe/cast` split, UN-3/UN-4/UN-5) can miss sites where the compiler *programmatically* builds an AST node headed by the old spelling via `(intern-symbol "cast")` + `make-cell`, rather than writing `(cast …)` as literal source text. A `grep -n '(cast '` sweep is blind to these — the head symbol only exists as a string argument to `intern-symbol`. Found in UN-5: `fn-make-drop-method` (src/nucleusc.nuc, the cfn env-drop synthesizer) built a `(cast (raw ui8) self)` pointer reinterpret and a `(cast usize 8)` alignment literal this way; both survived the UN-3/UN-4 sweeps undetected and would have died the moment UN-5 retired the bare spelling (every with-bound closure with an owned env synthesizes a drop method through this path). When retiring or renaming a special-form spelling, also grep `intern-symbol "<old-name>"` (and check any other AST-synthesizing helper — lambda lift, closure invoke/drop, defunion arm ctors, type-erasure forwarding methods, per the `defn` synthesizer list above) before declaring the sweep complete.

## Top-level dispatch does not expand user macros — new top-level sugar needs a compiler directive, not a `defmacro`

The top-level form dispatcher (the `case hp` block in `src/nucleusc.nuc`, the same `case` that routes `defn`/`defvar`/`fn-attr`/`set-ir-prefix`/… by literal head symbol) runs *before* macro expansion. Macro expansion only happens for forms nested inside a function or macro body (the CT/macro-JIT path). So a `defmacro` invoked directly at the top level is never expanded — the dispatcher sees an unrecognized head symbol and dies `unknown top-level form`, even for a macro whose body expands to a single, otherwise-ordinary `defn`. There is no forward-reference/prescan step that could make this work either; top-level forms are processed strictly in source order.

Confirmed twice independently during Stage 14 AVR-5 (design/stage14/avr-targets.md §5): the design's original sketch of a `(defisr <vector> …body)` macro wrapping a `fn-attr` call plus a `defn` turned out not to be implementable for this reason, and a second, separate verification pass reproduced the identical failure on a minimal test macro. **If a future task wants to add top-level definitional sugar (multiple forms generated from one user-facing spelling), the answer is a new compiler-recognized directive** — add a literal head symbol to `g-special-form-set` + a `case hp` arm + an `emit-<name>` function, the same shape as `fn-attr`/`set-ir-prefix`/`export` — **not** a `defmacro`. Don't rediscover this by trying the macro route first.

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
`typedef` into `g-cheader-typedefs` as a Node cell (`s` = name, `car` = the
**already-resolved** `Type*`). Resolving at the point the `typedef` is parsed —
rather than walking the chain at each use — buys two properties that are easy to
lose if someone "simplifies" it into a lazy walk:

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
path. A record whose `car` is null means "real C type name, no Nucleus
representation" and is deliberately distinct from an *absent* record.

Two adjacent parser facts, both found because the table is useless without them:
**`enum` was not a declaration specifier at all** (so `enum Tag e` read `enum` as
the base type and `Tag` as the declarator name — the identical phantom-parameter
shape W3b found for east qualifiers), and **`__extension__` was not consumed at
top level**, which hid glibc's entire `__quad_t` family (`__extension__ typedef
long long int __quad_t;`). When adding a C declaration-specifier keyword, check
both the specifier loop in `c-parse-type` *and* the top-level dispatch in
`emit-c-include`.

**`size_t`/`ssize_t` stay hardcoded in `c-type-to-nucleus`, on purpose.**
`clang -E` preprocesses for the *host* even under `--target=`, so letting
`<stddef.h>`'s own typedef win would make `size_t`'s width follow the
preprocessing host rather than the emission target.

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
`(declare repl_print_f64 (ptr):void)`. Each caller must decide what the null
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

## A tree-wide grep for a spelling must include `tests/run-tests.sh` heredocs

Test programs are not all files. `tests/run-tests.sh` writes several `.nuc`
consumers inline with `cat > … <<EOF`, so a `grep -r` over `*.nuc`/`*.nuch` —
however careful — reports zero uses of a construct that three tests depend on.
Stage 15's `declare` fix hit exactly this: a scan concluded nothing used
`&rest` in a `declare`, and `make test` then failed five assertions in the
`n6` / `sm3` / `s1` `.nuch` link-and-run consumers, all three of which generate
`(declare printf (fmt:CStr &rest args:i32) :i32)` from a heredoc. Grep
`tests/run-tests.sh` itself (and any other harness that generates sources)
before concluding a spelling is unused — or just treat `make test` as the
authority, which is what it is.

Worth knowing alongside it: **call arity is not checked against a
declaration.** `(declare printf (fmt:CStr):i32)` followed by
`(printf "a=%d b=%d\n" 42 26)` emits
`call i32 @printf(ptr %t0, i32 42, i32 26)` — the call site's own signature
governs codegen, so extra arguments ride through. That is how the three
harness sites call a C variadic without a variadic-`declare` spelling (Nucleus
has none), and it is why the `&rest` marker they used was contributing nothing
but phantom parameters.

## The deferred type queue has a contract: a `%Name = type {…}` line may not name a type that is not already in the buffer

`g-pending-unions` + `pending-union-deps-ready` + `drain-pending-union-irs`
(`src/union-registry.nuc`) exist because a parametric instance can be *stamped*
long before the `defstruct` its fields name has been processed. The contract is
narrow and easy to state: **`StructDef.emitted` means "this type's definition is
already in the module currently being assembled", and a type's line enters the
shared buffer only once every named type it references is there.** Every module
assembly point (batch flush, `emit-compile-time`, the macro JIT, the REPL) drains
first, so a type deferred at one drain lands at a later one.

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
- **Anything reading the compiler's OWN field table or `abi-sizeof` does not.**
  That is field get/set/address, struct literals, a by-value field of another
  struct, and by-value parameters/returns/arguments. The last was a *silent
  miscompile*: `abi-classify` sized the unlaid-out struct at 0 and emitted
  `define i32 @f(i0 %v.arg)` against a call site passing two `i64`s, whose only
  symptom was an unlocated `failed to parse generated IR`.
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
- **`emitted == 0`, not `num-fields == 0`, is "has no layout".** A legitimate
  `(defstruct Empty)` has zero fields *after* emission; only `emitted`
  distinguishes it from a name-only pre-registration. `sdef-layout-pending` /
  `reject-cycle-pending-layout` / `reject-cycle-pending-sdef` live in
  `src/type-utils.nuc` beside `reject-opaque-type` and mirror its site list —
  `type-utils` precedes `abi` in the import order, so `abi.nuc` can call them
  but not vice versa.

Everything W1d added is gated on `g-import-cycles != null`, which is why
`make bootstrap` was byte-identical on the first pass and an old-vs-new
`--emit-llvm` sweep over `examples/` + `lib/` was 168/168 identical: a cycle was
a hard error before, so no *compiling* program can reach any of it.

**Latent, still unfixed:** the same `i0` miscompile is reachable *without* a
cycle — `(defn f (v:S) …)` textually before `(defstruct S …)` in one file — since
`prescan-struct-names` registers the name and emission fills the layout later.
W1d deliberately did not ungate the check for it (the bootstrap risk is real and
the shape is not what W1d was scoped for).

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

## A C struct with an array member is registered OPAQUE — hand-declare and validate, don't field-access

`c-parse-struct-decl` declines a `char d_name[256]`-shaped member, so W3a
registers the whole type layout-less (`StructDef.opaque = 1`) and any field
access on it is refused with the opaque diagnostic. This is not exotic: it hits
`struct dirent` and, for a different reason (function-pointer members),
`glob_t` — i.e. both obvious routes to directory enumeration. The working shape
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

`read-program` / `desugar` mutate `g-src`, `g-pos`, `g-line`, `g-source-path`,
`g-peek` and `g-peek-valid`. Composing a diagnostic is not a safe moment to do
that: the message is being built from state that belongs to the form being
blamed. When a diagnostic wants to know something about *another file* (W1c's
"which file defines this name?"), scan the bytes. A small tokenizer that skips
line comments and string literals removes the two false-positive sources that
matter, and what remains — a definer spelled inside a quasiquoted macro body —
is acceptable precisely because the result is phrased as a `note:` and the
primary error text stays true on its own.

The corollary that makes this affordable: **check that every caller is on a
dying path before spending anything on a diagnostic.** `die-at` (lib/reader.nuc)
carries `noreturn`, so a scan reached only from `die-at` call sites runs at most
once per compile — a directory walk plus a file read per candidate is invisible
(a failing fixture compiles in the same 0.135 s as a clean one). The same work
on a speculative or recoverable path would be a real cost. In the REPL `die-at`
unwinds via `repl_throw` rather than `exit`, which is still one run per *failed*
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
  super-protocol edges, `&where` `Constraint.proto`, and `(dyn P)`'s box type.

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
  A `&where` constraint is checked long after registration and usually while a
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
