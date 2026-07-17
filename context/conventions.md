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
