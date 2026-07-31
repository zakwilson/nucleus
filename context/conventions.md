# Conventions

## Design documents

When a feature in a design document gets implemented, add a **Status:** note but preserve the original design discussion and commentary. The design reasoning is a valuable record of how decisions were made and remains useful context for future work even after implementation.

## Format helpers are fixed-arity (`src/format.nuc`)

`fmt-s` takes **exactly one** `%s` argument; `fmt-i32` exactly one `%d`/`%ld`, etc. They are plain functions, not variadic. Passing a format string with more conversions than the helper's parameter count makes `snprintf` read a garbage vararg and typically **segfaults the compiler** (no error — just a crash with empty output). For multiple substitutions use the dedicated variants: `fmt-2s` (two strings), `fmt-sd` (string + int), `fmt-i32-i32` (two ints), `fmt-2s-i` (two strings + int). If you need a new shape, add a helper in `src/format.nuc` rather than overloading an existing one.

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
