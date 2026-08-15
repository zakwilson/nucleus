# Stage 15 Progress — Stress Testing (Doom port findings)

Back to [../progress.md](../progress.md). Stage overview: [overview.md](overview.md).

**All seven original work items (W1–W7) are done**, and the external
regression — the only test that proves that half of the stage achieved its
purpose (`prompt.md` §6) — passed on 2026-08-01: see "The external Doom-port
regression" section near the end of this document for the two findings that
run produced.

**The stage was then reopened, the same day, with two new items.** **W8**
(combined declaration and initialization) and **W9** (defects found while
measuring W8's design) were added by the author's direction; see their sections
at the end of this document. **The W1–W7 record below is unchanged** — the new
scope is additional, not a revision of anything already closed. Both new items
follow directly from findings W1–W7 produced: W8's G-0 is the Doom-port
regression run's `defconst`/`defenum` finding and W8's G-5 is its
`(defvar- g:ptr:T null)` finding, both recorded in that section as top
candidates for a next stage and now assigned within this one. **W8 is now
complete** — all six steps (G-0 through G-5) landed 2026-08-01/2026-08-02, plus
one regression fix in between (the "interlude," between G-3 and G-4).
Acceptance criterion (A) (`compiler-init` eliminated) and (B) (the
no-initializer flip, closing [nullability.md](nullability.md) §1.5's remaining
half) are both met. **W9 was reconciled against `global-init.md` §7 at stage
close**: twenty defects were found across the whole effort; the reconciled
open count was **eighteen**, and items 11 and 12 were then fixed together on
2026-08-02, leaving **sixteen**. Fixing item 12's `w9-dyn-not-protocol`
fixture then exposed **item 21** (`(dyn ns/Proto)` unusable across a
namespace), fixed 2026-08-03 along with two further pre-existing defects it
uncovered but did not fix (items 22, 23 and 24) — **twenty-four found, five
fixed, nineteen open** — see the W9 section below for how the count was
arrived at. Re-measured at the close of the B series (2026-08-09) and moved
again by work done that day and the next; item 4's fix (2026-08-10) measured four
further pre-existing causes of an unparseable C header and filed them as items
25–28, item 8's fix (2026-08-10) split its float counterpart out as item 30,
and item 9's fix (2026-08-10) filed the i1 *signedness* defect beside it as item
31; item 13 fixed 2026-08-10: **thirty-one found, seventeen fixed (item 6 in part),
fourteen open**. That running tally stops there; every count in this paragraph
is a snapshot of the day it was written, and the **current** one lives in the W9
section's own heading — **forty-seven found, forty-seven fixed, none open** as of
2026-08-15 (item 46). Read that heading, not this sentence, and re-probe before
trusting either: this table has gone stale by hand three times, which item 10's
row and the B-series re-measurement both record.

**W4, W2 and W3 are complete** (W2a–d; W3a §1.6 opaque forward-declared C
types; W3b §1.5 C type qualifiers + the `declare` validity gate — `SDL2/SDL.h`
imports, links and runs; W3c §1.4 typedef chains + declaration precedence, the
header ladder closed on all three rungs, plus the `declare`-parameter parsing
fallout it surfaced). **W5 is complete** — W5a/b/c/d/f landed earlier, and
**W5e (`defn-` name isolation) landed 2026-08-01**, decided as Option 1 in its
unconditional form; see the W5 section below. **W1 is complete** — W1a/b/c
were already done; **W1d (mutual-import policy) landed 2026-07-31 as Option 2**
(import cycles are legal), **superseding** the Option 1 decision the same spec
doc had recorded and built earlier the same day — see the W1 section below and
[resolution.md](resolution.md)'s two inline decision boxes, which this
document does not duplicate. W1e stays resolved by obsolescence. **W6's
design document is written** ([nullability.md](nullability.md)); its §3.4
triage item **landed 2026-07-31** — a `null` global initializer into a typed
non-null pointer (`ptr:T` / `(ref T)`) is rejected with the same diagnostic
the identical local gets, closing the `defvar-init-ir`-bypasses-
`pkind-flow-check` hole W5c pinned. Flow typing proper (nullability.md §4
onward) remains design-only, by design — see the W6 section below for what was
measured while closing §3.4 and deliberately left open. **W7 is done** — see
its own section near the end, unchanged since it landed before this closing
pass.

**Gate for W1–W7: `make test` 328 PASS / 0 FAIL; `make bootstrap`
byte-identical on the first pass; `make abi-test` and `make layout-test`
green.** W8 and W9 are unbuilt and not covered by it.

## W2 — `node-type` ↔ `emit` literal-operand lockstep

Spec: [literal-typing.md](literal-typing.md) (with a "W2a as built" addendum
carrying the premise corrections and the full test/doc inventory).

| Chunk | What landed | Status |
|---|---|---|
| **W2a** | `node-type` of a binary operator returned *operand 1's type alone* while emit unified both operands, so the static type and the emitted type disagreed and downstream consumers trusted the wrong one: `(malloc (* 4096 (as i64 (sizeof i32))))` emitted `i64` but typed `i32`, and the argument coercer stacked a bogus `sext i32 <i64 value>` on it; `(> t:ui32 (* 2 cl:ui32))` was rejected as mixed-sign while `(* cl 2)` compiled. The type rule now lives in exactly **one** function, `binop-result-type` (`src/nucleusc.nuc`, immediately above `binop-coerce`), called by `binop-coerce` for the type decision (it keeps only its value-level cast emission) and by `node-type-call` (`src/generics.nuc`) for the propagated type. A binop's result is now the *unified* operand type and is symmetric in operand order. Also fixed the float direction found alongside the two specced repros: an untyped **float** literal now adapts to an `f32` operand (`(* alpha:f32 2.0)` is `f32`, not `double`-then-mis-stored) via a new `node-is-float-literal`; it still adapts only to a *float* operand, never an integer one. Two typed operands of different signedness are **still** rejected — the unification never sign-reinterprets. 4 new checks (the type matrix as a run example, the operand-order IR equivalence, two mixed-sign rejections). | **Done** |
| **W2b** | `defconst` provenance (§3.1) — a named constant now types like the literal it stands for, in both operand orders and on both sides of the lockstep. Carrier: two new `Sym` fields (`const-lit`, `const-lit-i64`) set by `emit-defconst`/`emit-defenum` (and the REPL's `NODE-*` mirror) but deliberately **not** by `deferror` (an `Err` is `is-int-type`-true and must not unify with plain integers); the *value* rides along, not just a flag, so `emit-symbol-ref` can tag the Val `is-lit`/`lit-i64` exactly as `emit-int` does. The single rule stays single: `binop-result-type` gained a `scope` parameter and calls one new predicate `operand-is-int-literal`; the scope is threaded (through `binop-coerce` and `emit-binop-vals`, whose two callers both already had one) rather than shortcut to `g-globals`, because a **local binding shadows the constant** and a shadowed local is not a literal. Also fixed the silent-wrong-answer half: `emit-defconst` hardcoded `ty-i32` while `const-val` carried the full decimal string, so `(defconst BIG 5000000000)` printed `705032704`; constants are now typed at `emit-int`'s LW-4 width, shared as `int-literal-type` and called from all three former copies (`emit-int`, `emit-defconst`, `node-type`'s NODE-INT). Carrying the value arms the existing `coerce-int-val` range check, and a **second, pre-existing narrowing hole** found while fixing it — `defvar-init-ir` hands a decimal string straight to LLVM, which truncates `i32 5000000000` without complaint — is closed for the named *and* inline spellings. `defenum` members get the same treatment (they carry no distinct nominal type, so withholding it would recreate the wart one level over). 5 new checks. | **Done** |
| **W2c** | Doc-only: `defvar` initialized from a `defconst`/`defenum` already works (§3.8); the docs implied "init must be a literal" forbade it. Folded into W2b's doc pass — the `defvar` rows in `docs/toplevel.md`/`docs/builtins.md` now say the restriction is about *expressions* and that a named constant is the preferred spelling for a named bound. | **Done** |
| **W2d** | Float literals in **non-binop** coercion positions (§3.6). The finding was bigger than specced: `coerce-int-val` (`src/abi.nuc` — despite the name, THE implicit-coercion chokepoint for ptr/CStr/StrView/int alike) had **no float case at all**, and its callers disagree on what a null return means. Eight typed-slot positions raised a type error (`let`/`with`, `set!`, `.set!` field store, explicit *and implicit* `return`, struct-literal and array initializers — positional and designated); the ninth, `emit-call-with-args`, treats null as "leave the argument alone" and so **silently miscompiled**, emitting `call float @take(double 2.5)` for `(take 2.5)` and printing `0.000000`. A **third** bug surfaced in the position the brief recorded as already working: LLVM accepts a decimal constant for `float` only when it round-trips exactly, so `(defvar g:f32 1.5)` worked while `(defvar g:f32 3.14)` emitted `@g = global float 3.14` and died at IR-parse time — and a global initializer is a constant, so it cannot be repaired with an `fptrunc`. All fixed at the one chokepoint: `coerce-int-val` gains a float↔float branch (a float **literal** re-renders as a constant at the target width, no instruction; a value gets `fpext`/`fptrunc`), and `coerce-num-val` + `safe-coerce-val` delegate to it instead of carrying copies. New `Val.is-flit`/`lit-f64` (deliberately separate from `is-lit`, which already carries two meanings) plus three renderers — `float-literal-value`, `f32-const-ir`, `float-literal-ir-at`. **Decision: Option A** — a non-literal `f64`→`f32` narrows silently, because `coerce-int-val`'s integer branch five lines up already does exactly that (measured: `(let (b:i64 300000000000 a:i32 b) …)` prints `-647710720` today) and C converts implicitly at every one of these positions. Dispatch is deliberately stricter: `arg-adapts` admits a float *literal* into a narrower float parameter (strictly additive — tier 0 still claims an exact `f64` overload) but never a typed `f64` value. Also removed `-ffast-math` from the compiler's own link line: it set FTZ/DAZ process-wide, folding every denormal literal to zero. 5 new checks, incl. the spec's accept criterion — a float DSP kernel bit-exact with C at `-O0` and `-O2`. | **Done** |

### Test/bootstrap status after W2a/W2b/W2d

`make test` **245/245** (231 → 235 after W2a → 240 after W2b → 245 after W2d);
`make avr-test`, `make abi-test`, `make layout-test` also green. `make bootstrap` stage1 == stage2
byte-identical on the first pass, no `make update-bootstrap` reconverge — as the
spec required: the compiler's own source compiles today, so the fix may only
affect programs that previously errored or mis-emitted.

Two premise corrections worth carrying forward (detail in the spec's addendum):
the predicate is named **`node-is-int-literal`**, not `is-untyped-int-literal`;
and the §1.2/§3.6 repros **do not fail under `--emit-llvm`** (which writes
textual IR without parsing it) — reproducing them needs the compile-and-link
path. The `(as i64 (* 4 (+ lb 1)))` workaround in `name-edit-distance` is now
redundant but deliberately left in place, since the committed boot compiler
predates the fix.

W2b's own premise corrections: the spec's "constants that do not fit `i32` are
stored `i64` today" was **false** (they were stored `ty-i32` and wrapped), and
W4b's rejection of `(defconst K:i32 512)` does leave W2b unconstrained on the
annotated-constant question — confirmed against the compiler, not assumed. The
trap that cost the most time: the variadic operator macros wrap the tail, so
`(* v K)` expands to `(_* v (* K))` and a binop's **second** operand node is a
CELL, not the bare symbol — a predicate over binop operands must macroexpand it,
or the fix silently works in operand-1 position only.

## W3 — C header interop

Spec: [cheader.md](cheader.md) (with a "W3a as built" addendum carrying the
premise corrections, the representation/upgrade design, and the full test
inventory).

| Chunk | What landed | Status |
|---|---|---|
| **W3a** | §1.6 — a C header's `struct Foo;` / `typedef struct Foo Foo;` was **skipped entirely**, so the type never registered and a later `ptr:Foo` died `unknown type: Foo`: C's standard opaque-handle idiom, which made every SDL handle type and `FILE` unusable and forced the Doom port to hand-mirror them. Now registered layout-less (`StructDef.opaque`, cleared in `struct-set-fields` — the single chokepoint every field-populating path funnels through, so "acquires a layout" and "stops being opaque" cannot drift), legal behind a pointer everywhere including a `defn` signature, and refused by value at six sites (`sizeof`, `alloca`, both field-access paths, `defn` parameter + return, `defstruct` field) with the misuse's own line **and** the header:line the type was declared on, recovered from clang -E's linemarkers. A later definition upgrades the entry **in place** through one shared emitter, in all three orderings real headers use (`struct Tag;` then `struct Tag {…};`; then via `typedef struct Tag {…} Name;`, whose body parses anonymously and never registered the tag at all; and a `typedef struct Tag Name;` alias registered while the tag was opaque, linked by a new `StructDef.alias-of`). Two premises corrected: the fix is **not** "one branch" — `c-parse-type` had to be taught to keep returning `ptr` for an opaque tag (its by-value `struct Tag` lookup would otherwise have emitted `declare void @f(%Tag)` for an undefined type, manufacturing more of the §1.5 invalid-IR failure this stage exists to remove), and the spec's own §1.6 probe cannot pass from import-time registration at all, because `prescan-defn-signatures` resolves signatures **before** any import runs and `prescan-imported-types` skips C-string imports by design — so W3a adds a name-only `cheader-prescan-opaque` pass that registers exactly the names the real import will define (which also made a fully-defined `ptr:Mix_Chunk` usable in a signature, not just the opaque `ptr:Mix_Music`). `unknown type:` also gained a location: the prescan resolved a signature against the defn's **name** node (an interned NODE-SYM, line always 0) and `desugar-typed` stamped every desugared binding cell from the same kind of node — both now borrow the enclosing form's line, which gives a real line to every diagnostic raised off a defn parameter, `defvar`/`extern`/`declare` name, `defstruct` field or `let`/`with` binding name. Incidental: `MAX-STRUCTS` 256 → 1024 (measured: three mainstream umbrella headers in one unit need between 200 and 256 slots), and preprocessed header text is now cached by path — 5 clang invocations → 3 for a `hello.nuc` build, ~30% faster than before W3a — which surfaced that `emit-c-include` ended with `(free buf)`, correct with a per-call buffer but a use-after-free (presenting as a *hang*, only on the second import of the same header) once shared. 10 new checks. | **Done** |
| **W3b** | §1.5 — **the finding was not about `void`.** `c-parse-type` accepted C type qualifiers only in *leading* position, so an "east" qualifier (`int const *p`, legal C denoting the same type) terminated the type, its token was eaten as the parameter's **name**, and the following `*p` began a phantom **second** parameter defaulting to `ptr`. `void _mm_clflush(void const *__p)` (reached transitively from `SDL2/SDL.h` via the x86 intrinsics headers) became the IR-invalid `declare void @_mm_clflush(void, ptr)` — but that was the only spelling that failed *loudly*: `int const *p` became `(i32, ptr)`, `double const *p` became `(double, ptr)`, `int const n` became `(i32, ptr)` — representable, silently accepted, wrong arity and wrong ABI, and **no validity gate can catch them**, which is why the parse fix is the primary deliverable and the gate only the safety net. Fixed with `c-skip-type-quals`, called after the declaration-specifier loop and after every `*`; `const`/`volatile`/`restrict`/`__restrict`/`__restrict__`/`_Atomic` are consumed and discarded in every legal position (the emitted type is identical either way). The **gate** (`c-decl-skip-reason`) then runs on every recognized function declaration before registration: it rejects a by-value struct/union with no known layout (a declaration-scoped `g-cheader-unrep` flag set inside `c-parse-type`, cleared again for a function-pointer or array parameter — glibc's `utimensat(…, const struct timespec [2], …)` proved that arm necessary), a recorded `void` parameter, an opaque parameter/return type, and an arity over `C-MAX-PARAMS` (32; the count deliberately increments past capacity so a truncated signature is never registered — the array was 16 and was being written past). A rejected declaration is **skipped with `<header>:<line>: warning: skipping C declaration '<name>': <reason>`**, always on, deduplicated by function name; measured volume is **zero** across stdio/stdlib/string/unistd/fcntl/math/time/sys-stat/pthread/netinet-in/signal/png/SDL.h/SDL_mixer.h. A **third** root cause was found by measuring rather than trusting the committed behaviour: a stray `)` (since `6ef16dc Add union types`) closed the top-level dispatch `cond` after its first clause, leaving `true` a no-op statement and running the function-declaration parse *unconditionally* after every `struct`/`union`/`typedef` — which attributed the next declaration's warning to the **type declaration's** line and silently dropped a second consecutive forward declaration. Premises corrected: the spec's "no unresolved type names" gate arm is not implementable (an unfollowed typedef resolves to `ptr`, which *is* representable — §1.4's job), and "compiler-internal headers must pass the gate" is **false** — 3 of 33 `make lib-cheaders` outputs produce 11 skips, every one a genuine `--emit-cheader` defect (it emits the template type variable `T` as `struct T`). Rung 2 of the header ladder reached: `SDL2/SDL.h` imports with zero warnings, 1663 declarations, links and runs. 3 new checks. | **Done** |
| **W3c** | §1.4 — the finding was **much broader than the spec's framing** ("`off_t`'s typedef chain degrades somewhere"): **no scalar typedef resolved at all.** `c-parse-type` returned `ptr` for every name it did not recognize as a builtin, and `c-type-to-nucleus` hardcoded exactly two (`size_t`, `ssize_t`), so a one-level `typedef int myint;` degraded as thoroughly as `off_t`'s three-level chain — in return types, parameters **and struct fields**: `lseek` imported as `declare ptr @lseek(i32, ptr, i32)` (return *and* offset parameter both wrong), `getline`/`ftello`/`fseeko` likewise, and `%timeval`, `%__fpos_t` and `%Mix_Chunk` all had wrong **layouts**, silently, with every field after the first mistyped one at the wrong offset. Fixed with `c-parse-typedef-decl` + a flat table resolved **at the point each `typedef` is parsed** — so a chain costs one lookup at each use and a cycle is impossible by construction (a name can only resolve against entries recorded strictly before it, so `typedef foo foo;` records unrepresentable rather than looping). Covers scalars at any depth, pointers, function pointers (recognized *before* the declarator fallback, or `typedef int (*h)(int);` parses as a function literally named `int` — W3b's flagged trap), enums, struct aliases. Two neighbouring parser gaps had to go with it: **`enum` was not a declaration specifier at all** (`enum Tag e` read `enum` as the base type and `Tag` as the declarator — the same phantom-parameter shape W3b found for east qualifiers) and **`__extension__` was not consumed** (glibc writes `__extension__ typedef long long int __quad_t;` for every `long long` type). An unfollowable typedef is **never a silent `ptr`** — recorded known-but-unrepresentable, which finally makes W3b's deferred "no unresolved type names" gate arm implementable, and it is now in. **Precedence:** measured, both orders were silent *and disagreed* — *first*-wins, not the spec's "last wins" — so an import above a hand-written `declare` silently discarded the author's. Now the explicit declaration wins in **both** orders (`prescan-explicit-declares`, beside the other prescans so it precedes every import), exactly one `declare` reaches the module, and a mismatch warns with both rendered signatures and both locations. The non-obvious half: *suppressing* the header's copy is not enough — it leaves the name undefined between the import and the declare (`examples/cstr-lit-test.nuc` declares `strlen` at line 15 while `lib/arena.nuc` calls it from inside the preceding prelude import) — so the explicit declaration is **emitted at the point of first need**. Two pre-existing defects surfaced, both unreachable until typedefs resolved: `c-parse-func-decl` never applied the aggregate C ABI (now routed through `abi-classify`, making `div`/`ldiv`/`lldiv`/`fopencookie` correct and every scalar declaration byte-identical), and the cheader path never set `StructDef.emitted`, which `pending-union-deps-ready` consults — so SDL's `SDL_WindowShapeParams` was deferred on every drain and never defined while `%SDL_WindowShapeMode`, which contains it, referenced it. **Warning policy split**, because W3b's zero-volume measurement was itself a consequence of §1.4: with chains followed, `SDL2/SDL.h` reaches **165** genuinely unrepresentable by-value declarations (149 `long double`, 7 `_Float128`, 6 `SDL_JoystickGUID`, 2 `SDL_GUID`, 1 `_Float16`), six of them in the REPL banner and six in every `make` — so W3b's four parse-failure arms stay loud at import (still zero) while "Nucleus has no such type" is recorded and delivered at the point of **use**, carrying the same header:line and reason. Also took W3b's deferred musl item (`struct Tag *f(int);` without `extern`, silently dropped; fallback restricted to the `struct`/`union` tokens exactly as W3b required). Ladder **closed**: rung 1 runnable end-to-end (`examples/cheader-posix.nuc`), rung 2 links and runs (1497 declarations — the 165 that went were wrong-`ptr` ones that would have miscompiled if called), rung 3 with `Mix_Chunk`'s `Uint8`/`Uint32` fields now correct. 3 new checks. | **Done** |
| **W3c fallout** | Surfaced *by* W3c and a precondition for its precedence rule: **`declare`'s parameter list ignored every written type unless the parameter was named**, emitting `i32` instead — `(declare f (i64):i64)` gave `declare i64 @f(i32)`, `(declare f (ptr i64 ui32):i64)` gave `(i32, i32, i32)`. Return types were never affected, and the bare list was correct exactly when the signature was all-`i32`, which is why it survived: `docs/toplevel.md` documents the spelling and the compiler's own `src/nucleusc.nuc:16-17` uses it (`(declare repl_print_f64 (ptr):void)` emitted `declare void @repl_print_f64(i32)` against a `void *` C shim — correct on x86-64 SysV only because a pointer and an `i32` share a register class, and because a call site's own signature governs codegen). Root cause: `emit-nuch-declare-import` defaulted to `ty-i32` whenever `extract-name-and-type` returned null, which it does for *any* unannotated node — i.e. for every bare type spelling. **Interaction with W3c:** a bare-list `declare` that *agreed* with a C header rendered as all-`i32`, so it conflicted with every non-`i32` header signature, warned about a conflict that did not exist, and the corrupted signature won — a live regression in effect, since before W3c the header's correct declaration would have been used. Fixed by parsing an unannotated element as a **type operand** (`declare-param-type`, `src/nuch.nuc`): a keyword through `parse-type-name`, anything else through `parse-type-from-node`, both of which already raise a **located** diagnostic, so an unresolvable spelling is an error at its own line rather than a silent default. An *annotated* element deliberately stays a named parameter (so `(declare f (ptr:FILE):void)` is a parameter named `ptr` of type `FILE`, by value — desugar erases the distinction, and reinterpreting it would need C's typedef-lookup ambiguity and would silently retype a generated `.nuch` for the legal `(defn addone (ptr:i32):i32 …)`); documented and pinned rather than changed. `&rest`/`&optional` are now **refused** in a declaration — none of the machinery exists (`variadic` is hardcoded 0, `has-rest` never set), so the marker was counted as an extra `i32` parameter, and implementing it has two incompatible meanings (Nucleus cons-list vs C varargs). That is the one non-additive part: **three `tests/run-tests.sh` heredocs used it** (`(declare printf (fmt:CStr &rest args:i32) :i32)`) and were relying on the defect — their calls pass 3–6 arguments to what the spelling made a 3-parameter declaration, and call arity is not checked — so they now declare the honest `(declare printf (fmt:CStr):i32)`. A tree-wide grep over `*.nuc`/`*.nuch` cannot see them; the test suite found them. Bootstrap: compiling identical source with the old and new compilers differs by **exactly** the two `repl_print_f*` declarations (6 diff lines, no string-pool renumbering), and all **189** compiling `examples`/`lib`/`fixtures` programs emit byte-identical IR; reconverged with the standard cycle. `run_w3c_precedence` was audited and did **not** encode the defect (it uses the named spelling throughout). 4 new checks. | **Done** |

### Test/bootstrap status after W3a/W3b

`make test` **258/258** (245 → 255 → 258). `make bootstrap` stage1 == stage2
byte-identical on the first pass, no `make update-bootstrap` reconverge.
(W3c took it to **261**, and the W3c-fallout `declare`-parameter fix to
**265/265**; that fix is the only part of W3 that changed the compiler's own
emitted IR and needed a `make update-bootstrap` reconverge — see the addendum in
[cheader.md](cheader.md).)
Because W3 touches shared code, inertness was verified beyond the fixed point:
`make lib-cheaders`, `make lib-headers`, and the emitted LLVM IR of **every**
`lib/*.nuc` and `examples/*.nuc` are byte-identical against a compiler built
from the pre-change tree (`git archive HEAD` + the committed boot compiler).
W3b's `cond` repair was verified the same way, and additionally by diffing the
compiler's **own** `src/nucleusc.nuc` IR emitted by the pre- and post-change
compilers (identical — which is the fixed point stated directly).

### New limitations discovered during W3a/W3b (not fixed here)

* **A top-level declaration whose first token is `struct`/`union` and which is
  not a type declaration is silently dropped** (`struct Tag *f(int);` written
  without `extern` — verified directly). Invisible on glibc, which always writes
  `extern`; **musl deliberately omits it**, so on Alpine this would drop every
  function returning a `struct X *`. The W3b gate does not cover it because
  nothing is synthesized. The fix must be restricted to the `struct`/`union`
  tokens — falling back to the function parse for `typedef` too would parse
  `typedef int (*handler)(int);` as a function literally named `int`.
* **`--emit-cheader` emits a parametric template's type variable as a C type**
  (`void conj(void* self, struct T elem);` in `lib/vector.h`). Same family as
  the hyphenated-identifier defect W3a recorded. It is what makes the spec's
  "compiler-internal headers must pass the gate" check fail; the gate is right
  and `--emit-cheader` is wrong.
* **`Uint8`/`Uint32`-typed struct fields degrade to `ptr`.** `Mix_Chunk.volume`
  (`Uint8`) types as `ptr`, so `(c volume)` fails `return type mismatch` while
  `(c allocated)` (`int`) works. This is §1.4's typedef-chain defect surfacing in
  a *field* rather than a return type — W3c's scope. It is why the SDL_mixer
  fixture reads `allocated`.
* **`--emit-llvm` exiting 0 is not evidence of valid IR** — it writes the
  textual module without parsing it. This is why W3a's "the SDL.h probe exits 0"
  was not the same claim as "the module is valid" (§1.5 was still open at that
  point), and why every W3b claim is verified with `-o` or `llvm-as`.

## W4 — Diagnostics: locations and silent failures

Spec: [diagnostics.md](diagnostics.md). All five chunks done, in order
(W4a→W4b→W4c→W4d→W4e). Full detail, including each chunk's own "as built"
addendum with premise corrections and negative controls, lives in
`diagnostics.md` itself; this is the summary.

| Chunk | What landed | Status |
|---|---|---|
| **W4a** | Every compiler diagnostic now names a real line — the `unknown:`/`undefined:` family, `let`/`with` initializers, retired special-form spellings, `defvar` initializers, `match` arm patterns, `addr-of`/`set!`/`goto`/`export` subjects. Root cause: interned symbol nodes carry line 0 (shared across every occurrence of a spelling), so diagnostics borrow the enclosing form's line via `node-line`, plus an ambient `g-form-line` for the one call site (`emit-symbol-ref`) reached with only the bare operand. Added a did-you-mean (Levenshtein over the name registries, length-gated) and a small hand-written correction table (`bit-not` → "no unary 'bit-not'; write (bit-xor x -1)"). New suite-wide guard: `run_no_line_zero` fails if any fixture's diagnostic contains `:0:`. | **Done** |
| **W4b** | `(defconst K:i32 2)` (and the same shape on every sibling definer) used to register silently under the literal key `"K:i32"`, then die `undefined: K` at line 0 on first use — the worst failure mode in the stage. Decision: **reject**, not accept-as-type (per the spec's own recommendation). `emit-defconst` now rejects a colon-annotated or colon-paren-fused name with `<definer>: takes no type annotation; write (<definer> Name ...)` at the definer's own line. Swept every sibling (`defenum`, `defstruct`, `defprotocol`, `defmacro`, `defunion`, `deferror`, plus the private `-` variants) via a shared `reject-colon-in-def-name` helper — all had the identical bug, always in the annotation half (arity checks were already correct everywhere). Worst individual case found: `defstruct` didn't fail silently *or* cleanly — it produced a misleading `illegal character ':' in generated symbol` at line 0. 9 new fixtures. | **Done** |
| **W4c** | `unterminated list` reported only the innermost unclosed form's *opening* line (the file's premise that it blamed the *outermost* form was itself wrong — corrected in the addendum), which doesn't localize a deeply-nested miscount. Now reports that line **plus** a `note:` naming the first line that opens a new form in column 0 while a form is still open, and how many forms are open there — closing the gap that previously forced the Doom port to use an external Python paren-depth counter. Also diagnosed the "extra `)` inside a `let` binding list" shape by cause (`let: 'NAME' is a body form, not a binding -- an extra ')' probably ended the binding list early`) rather than the misleading downstream `undefined: NAME`; the spec's proposed "odd element count" heuristic for this shape doesn't actually fire (the shape leaves an *even* count), so a different, cause-based check was built instead. 6 new fixtures. | **Done** |
| **W4d** | `case` given its documented-but-wrong nested-clause form died `value is not callable: no invoke method is defined for this type` (naming the mechanism, not the mistake). Fixed at `emit-invoke-with-callee` (the one chokepoint every non-callable call head reaches) with a `case-clause-hint` that recognizes a bare-integer or bound-`_` head and rewrites the message to name the real flat syntax — confirmed **not fixable inside the macro body itself**: a `defmacro` body cannot call `die-at`/`report-at` (only the compiler's own source imports them; the prelude every macro body — including `case` — auto-imports does not). One-armed `if` now says `if requires an else branch; use (when test then…) for a guard` instead of the generic `macro: wrong number of args`; the generic macro-arity messages now name the macro and both counts. 4 new fixtures. No `lib/macros.nuc` changes, so bootstrap was byte-identical on the first pass. | **Done** |
| **W4e** | Two independent sub-parts, both done. **(1) Generated stdlib table:** `docs/stdlib.md`'s "no import needed" availability claims were wrong in both directions (`close`/`dup`/`dup2`/`isspace`/`isdigit` claimed-but-unavailable; ~190 real names undocumented). Replaced the hand-curated table with `scripts/gen-stdlib-table.py`, which probes every candidate name (full transitive enumeration of the prelude's actual header chain — `stdio.h`+`stdlib.h`+`string.h`, not just `string.h` as the spec's ground truth assumed) against `build/nucleusc --emit-llvm`, wired into the suite as `run_stdlib_table` (fails only on a false claim — a name the committed doc claims that no longer probes as available — not on host-legitimate incompleteness, since availability is libc-dependent). **(2) Docs truthfulness:** `docs/special-forms.md`'s `case` table row described a nonexistent nested-clause `switch`/`unreachable` lowering; `lib/macros.nuc:91` is a flat-argument equality-dispatch macro expanding to `cond`. Fixed by *deleting* the row — `case`, like `if`/`when`/`unless`/`dotimes`/`->`, belongs in `docs/macros.md`'s Standard Macros table, which already had the correct entry. The `addr-of` row read as more restrictive than reality (omitted that passing it as a call argument is an allowed borrow, only `return`/longer-lived stores are rejected) — restated positively with the C out-parameter idiom as the worked example, verified by compiling and running a probe (`build/nucleusc`, output `a=41 b=99`) before writing it down. Swept the rest of `docs/special-forms.md` for the same class of error (concrete claims about generated code/accepted syntax) with two-line probes; found nothing else wrong. Also closed a documentation gap the brief's checklist flagged: `docs/toplevel.md`/`docs/errors.md` had the W4b "takes no type annotation" note on `defconst`/`defenum` but not on `defstruct`/`defunion`/`defprotocol`/`defmacro`/`deferror`, despite all seven sharing the identical fix — added the note to the remaining five (re-verified against `build/nucleusc` first, not copied from the design doc). | **Done** |

### Cumulative test/bootstrap status after W4

`make test` check count grew monotonically through the chunk: 211 after W4a →
220 after W4b (+9) → 226 after W4c (+6) → 230 after W4d (+4) → 231 after W4e
(+1, `run_stdlib_table`). Final: **231/231**. `make bootstrap`: stage1 ==
stage2 byte-identical throughout every chunk, no `make update-bootstrap`
reconverge required at any point — expected, since W4 is diagnostics-only
(message text and doc content, never accepted syntax or emitted IR for any
previously-valid program).

### New limitations discovered during W4 (not yet fixed; not this stage's scope to fix here)

* **A `defmacro` body has no access to `die-at`/`report-at`.** Only the
  compiler's own source (`src/nucleusc.nuc`) imports `lib/reader.nuc`; the
  prelude every ordinary program (and every macro body, including
  library-shipped ones like `case`) auto-imports does not. A future
  compile-time-diagnostic facility for macro authors (e.g. exposing
  `report-at` through the prelude, or a dedicated `(macro-error line msg)`
  builtin) would be new scope, not a W4 fix. Found during W4d.
* ~~**`context/build.md`'s parallel-test-suite timing figure (`~8.5s`) is
  stale**~~ — **corrected 2026-08-09.** Measured `~18.8s` here (16-core host),
  predating the AVR/RISC-V gates and the W4a–W4d fixture batches; now `~36s`
  parallel vs `~144s` serial at 463 tests. `build.md` carries the current
  figures and the corrected 4× ratio (it had claimed 7×). Found during W4e's
  generated-table sub-part and left for "whoever next audits `context/build.md`";
  that audit happened alongside W9 item 10's closure, which is the same
  measurement.
* **The literal-left binop mistyping** (`(_+ 1 x)`-shaped code mistypes to the
  literal's default `i32` instead of adapting to the non-literal operand's
  type) is live and was re-confirmed during W4a's incidental-finds pass. This
  is W2's item ([literal-typing.md](literal-typing.md)), not W4's — noted here
  only because W4a's sweep happened to re-trip it.

### Deferred / not applicable within W4

Nothing in W4's own scope was deferred — all five chunks (W4a–W4e) reached
**Done**. (At the time this was written the stage's other five items were all
unstarted; W2 and W3 have since completed, and W5 is partly done — see the
sections above and below, and [overview.md](overview.md) for the planned ordering
`W4→W2→W3→W5→W1`, W6 design-only.)

## W5 — Ergonomic gaps and the union crash

Spec: [ergonomics.md](ergonomics.md). **All six sub-items done.**

| Chunk | What landed | Status |
|---|---|---|
| **W5a** | §4.4 — `"MUS\x1a"` died `unknown escape \x`, forcing the Doom port to poke a four-byte magic number into an `(alloca ui8 N)` byte by byte. Added a `\xHH` arm to `lex-string`'s escape chain (`lib/reader.nuc`), reusing the existing `hex-digit-val` helper; purely additive, and it sits entirely before the `(>= n 4095)` buffer guard and the single-byte `aset!`, so neither moved. **Decision: capped at two hex digits**, taking the spec's recommendation — C's `\x` is greedy, so C's `"\x41BC"` is one overflowing character while here it is the three characters `A`, `B`, `C`. One digit is accepted where unambiguous (`"\xa"` == `"\x0a"`). A `\x` with no hex digit is a located reader error, and the fixture pins the `:6:` line prefix rather than merely scanning for `:0:`. Verified by running, not by reading IR: `"MUS\x1a"` → `4d 55 53 1a`. Premise correction: `ergonomics.md` said reader.nuc "already supports `\a`, `\newline`, `\u{…}`" — those are *char* literals (`lex-char-literal`), a different function; the string escape table was a flat six-entry list, and `docs/` had never documented string-literal escapes at all, so the table in `docs/types.md` is new rather than an edit. 2 new checks. | **Done** |
| **W5b** | §4.3 — no unary `bit-not`, so C's `~x` had to be written `(bit-xor x -1)` by hand. Added as a one-argument macro in `lib/macros.nuc:79` expanding to exactly that, per the repo's "prefer macros over builtins" principle: correct for two's complement at every width, no codegen. W4a's stopgap correction-table entry (`bit-not` → "no unary 'bit-not'; write (bit-xor x -1)") was removed when it landed, as `ergonomics.md` required, and W5b's section was removed from that spec doc. Verified against `build/nucleusc`: `(bit-not 3)` is `-4`. | **Done** |
| **W5c** | §3.7 — a `defvar` global may now be typed `CStr`. `defvar-init-ir`'s string-literal and `null` gates tested a bare `TY-PTR` kind where the standing rule is `is-ptr-like`; both now accept `CStr` and name the offending type on rejection. **Both** literal spellings are accepted, for `ptr` and `CStr` alike — a plain `"…"` was *already* accepted here for `ptr`, and at a global initializer the `StrView`/`CStr` distinction has collapsed (the `@.str.N` rodata is NUL-terminated either way), so accepting only `c"…"` would have invented an asymmetry the value path does not have. **The line-0 half of the finding did not reproduce** — W4 had already fixed it. **The finding was bigger than specced:** making the spelling compile exposed a *segfault*. `emit-binop-vals` fires its strcmp content-comparison whenever either operand is `CStr`/`StrView` — including against the `null` literal — so `(= g null)` emitted `strcmp(ptr %t0, ptr null)`, UB in C and a crash under glibc (measured: exit 139). Pre-existing and not global-specific (a `CStr` *parameter* null-checked with `=` lowered identically — `conventions.md`'s documented "null-check trap"), but W5c promotes it from a compiler-internals hazard to something ordinary user code hits immediately, so it was fixed: the strcmp branch is suppressed when either operand *node* is the symbol `null` and the other is `is-ptr-like`, and the identity gate below was widened to `is-ptr-like` so the escape lands on `icmp eq ptr`. Strictly a bug fix (no correct program can depend on UB) and inert for the compiler's own IR (`boot/nucleusc.ll` has zero `strcmp(ptr %x, ptr null)`). Deliberately out of scope: `(as CStr …)` in an initializer (the general expressions-aren't-literals rule, identical for `(as ptr …)`) and `StrView`-typed globals (needs aggregate constant initializers). 4 new checks. | **Done** |
| **W5d** | §3.9 + §3.10 — array-literal ergonomics. **§3.9 was fixed at the shared chokepoint, not at the array literal**, and the spec's "inserting one load, not new machinery" prediction held exactly: `coerce-int-val` (`src/abi.nuc`) now loads a `ptr:S` into a by-value `S` slot when the pointee's StructDef *is* the target's. The decisive measurement is that the ARGUMENT position already did precisely this (Stage 13 CE-3's by-value normalization in `emit-call-with-args`), so `(take (P 1 2))` compiled while `(let (v:P (P 1 2)) …)` did not — the fix is one rule reaching the other eight typed slots, not a new liberty. Verified byte-for-byte: the 1000-row table compiles to **identical IR** under the bare and `(deref …)` spellings (only the module-ID line differs), 1000 allocas + 1000 loads, linear. `safe-coerce-val` never delegates a ptr→struct pair down, so the argument path cannot even reach the new branch. **§3.10 was narrower than the finding claimed** — `(let (a:ptr:ptr …))` and an *unannotated* binding both already worked, so the wart was the annotated-but-imprecise middle case alone, and it is not ptr-of-ptr-specific (`(array i32 …)` bound to `:ptr` failed identically). Fixed with a deliberately **syntactic** rule (`array-lit-binding-type`, `src/generics.nuc`, called by `emit-let`/`emit-with` and mirrored in `node-type-block` — one rule function, two callers, per the lockstep): an `(array T …)` init refines an elem-less declared pointer to `ptr:T`, keeping the declared pkind and volatility. The general "adopt the init's element type" rule was **rejected on measurement**, not taste: `type-eq` compares pointer elements, so adopting an elem re-routes multimethod dispatch, and a bare `:ptr` also erases the *nullability claim* (`pkind-flow-check` exempts an elem-less target) — there are ~1550 bare `:ptr` bindings in this compiler, 113 of them from `addr-of` alone. **Two pre-existing crashes found on the path this opens** (both confirmed against the pre-W5d binary): `emit-zero-store` emitted `store %P 0` for a struct slot and `store ptr 0` for a `CStr`/`TY-FN` slot, both LLVM parse errors — so a *sparse* `(array S …)`, exactly the shape a generated table with holes has, produced unparseable IR. Fixed with `zeroinitializer` for aggregates and the standing `is-ptr-like` test for pointers (`conventions.md`'s documented TY-PTR-vs-is-ptr-like trap, hit again). Proof of confinement: a per-function normalized diff of the compiler's own IR shows **exactly** the 5 edited functions plus the 1 added one changed, nothing else — the refinement never fires in `src/` (no `(array …)` there). 4 new checks. | **Done** |
| **W5e** | `defn-` name isolation (§2.5), sequenced after W1 (both touch the global-key scheme) and landed 2026-08-01. Decided by **census, not taste**: `src/` contains **zero** private definers of any kind (`defn-`/`defvar-`/`defconst-`/`defenum-`/`defstruct-`/`defunion-`/`defmacro-`/`defprotocol-`), and `lib/` has exactly one `defn-`, not on the compiler's import graph — **the compiler uses no private definer at all**, so no private-definer change can move the bootstrap, which removed the reason to hedge toward a cheaper variant. **Outcome: Option 1, unconditional.** The cheaper "qualify only on collision" alternative was **rejected**: its sole advantage (byte-identical IR) was already free at the unconditional form's cost, and it carries a real hazard — `finalize-generics` stamps an ir-name and sets `finalized = 1`, so a name that looked unique when its generic finalized cannot be renamed when a later file registers a colliding one; unconditional file-qualification is order-independent by construction. Mechanism: the scope lives in the **key**, not a lookup filter — a private definer in a file with no `(ns …)` is keyed under a synthetic per-file namespace, `#p1/helper`. Because that is an ordinary `<ns>/<name>` spelling, `qualify-name` is idempotent on it and `strip-ns-qualifier` recovers the bare name (`import-alias-one`/`unsafe/import-private` needed **no change**), and the synthetic namespace's ir-prefix flows through the existing `ns-compose`/`mangle-fn-name` path. Private-shadows-public fell out of the key scheme rather than being designed in. Sites: `src/compiler-types.nuc:756,767` (`PrivName`/`PrivFile`) and `:670` (`Method.src-file`/`src-ns`/`priv`); `src/nucleusc.nuc:512` (globals), `:3323–3466` (`priv-*` family), `:8804` (`emit-defvar` ir-name), `:10616` (prescan arms `g-defining-private`), `:10797` (`emit-ns` rejects a `#`-leading name), `:12119` (reset); `src/scope.nuc:33,70` (`priv-key-define`/`priv-key-use`, one call each — covers `defn-`/`defvar-`/`defconst-`/`defenum-` at once); `src/generics.nuc:24,30,56,377,417,484,504,700`. Everything short-circuits on `g-priv-files == null`, so a unit with no private definer takes the identical pre-W5e path. **A second, unreported defect fell out of the same census, worse than the one reported, and is fixed by the same mechanism:** `defvar-` collided too — two files with `(defvar- g:i32 …)` emitted two `@g = internal global` lines, `--emit-llvm` exited 0, and the **link** died pointing at raw IR with no source location. New duplicate-definition diagnostic names both files at a real `file:line:`: `duplicate definition of 'helper' — the same parameter types are already defined at a.nuc:1`, with a `note:` stating the rule (a public name must be unique unit-wide; `defn-` scopes a name to its own file in the default `user` namespace; a private pair can only collide inside an **explicit** namespace, and that branch says so precisely). **Premise correction:** ergonomics.md's "the error surfaces in whichever file was written *second*" is **pre-W1 framing** — since W1a it is detected in the prescan and fails in *every* import order; the file it *names* is the one prescanned second (measured by swapping the two `import-use` lines). The "names a function its author has never seen" half was accurate. The spec's implicit framing that this is a `defn-`-only problem was also wrong — see the `defvar-` defect above. Research trap worth recording: `grep -oE '\(defn-'` matches every `(defn-parse-sig …)` *call* in the tree and `-o` truncates the token so a follow-up `grep -v` cannot filter it out; anchor with `grep -nE '^[[:space:]]*\(defn- '`. **Left undone, deliberately:** the REPL still rejects `defn-` outright (pre-existing, top-level dispatch never had the private definers); `compile-time` cannot call a same-file function, private or public (pre-existing, reproduces on the old compiler); `defstruct-`/`defunion-`/`defprotocol-`/`defmacro-` keep *namespace*-level privacy, since they name types and macros, which are bare-keyed and globally identified by design (Stage 12 decision 9 — a qualified type reference must resolve to the same `StructDef` from any namespace) — file-scoping those is a separate, larger question. Tests: `run_w5e_private_isolated`/`run_w5e_still_rejects`, 9 units — positive units **link and run**, asserting an exit status encoding both files' answers (`a*10+b`), because a wrongly-routed call links fine and only shows in the value; 2 pre-existing pins on the old duplicate-definition text updated (`w1-duplicate-rejected`, `w1d-cycle-duplicate-rejected`), both still asserting rejection. 319 → 328 PASS, 0 FAIL. Bootstrap byte-identical on the first pass; sweep of every `examples/`+`lib/` program: 160 byte-identical, 5 differing — all five the private-definer files, every hunk an `internal`-symbol rename (`@helper-add` → `@private_defn_p1__helper-add`). Full account: [ergonomics.md](ergonomics.md)'s W5e "as built" section. | **Done** |
| **W5f** | **The spec's framing was wrong: this was never a union bug.** Unions carry function-pointer members fine — `(union acv:(fn void) i:i32)` and the list form `(union (acv (fn void)()))` compile today and always did; nothing in `src/union-registry.nuc` was at fault. The bisect that settles it: swapping `union`→`struct` in the repro crashes **identically** on the pre-change compiler (independently re-confirmed from the orchestrating session: old compiler exit 139 on *both* forms, new compiler exit 0 on both). The real cause is that **the colon-paren reader fuse cannot express a function-pointer type**: such a type is *two* parenthesised groups, `(fn ret)` + params, and `fuse-colon-paren` absorbed only one — so `acv:(fn void)()` read as the member `(acv (fn void))` **plus a stray `()` member**, and `()` reads as a NULL node, which the member loop dereferenced. The same gap silently mistyped every other binding position: the spelling `docs/types.md` documented, `f:(fn i32) (i32 i32)`, **never worked** (`f` bound as a zero-parameter fn, `(i32 i32)` became a junk extra parameter, dying only at the call site with `call: expected 0 args, got -1`). Fix: `fuse-fn-params` (`lib/reader.nuc`) absorbs an *adjacent* second group after a `(fn …)`-headed colon-paren form and returns the nested canonical `((fn ret) (params))` — composing for free with the colon chain and the lone-colon return fuse. Adjacency is required (a space-separated group is genuinely ambiguous with the next binding), so the docs were corrected rather than the reader made ambiguous. Second half: `()`→NULL is a general segfault trap, so ten raw derefs across `src/nucleusc.nuc` / `src/generics.nuc` / `src/union-registry.nuc` (the two `extract-name-*` chokepoints, `emit-node`, the defstruct field loop, `emit-defn`'s &rest/&optional scan + L8 warning scan + param loop, the four signature-prescan helpers, `defunion-strip-repr`, `emit-defmacro`) now route through the null-safe `node-line` or an explicit guard — every one a confirmed SIGSEGV before, every one a **located** diagnostic after. `--emit-cheader` renders the union as C `union { void* acv; void* ac1; int32_t n; }` (the C-interop invariant holds) and `--emit-nuch` round-trips it to the same `__anon_union_h…` memoization hash. 5 new checks. | **Done** |

### Test/bootstrap status after W5a/W5b/W5c/W5d/W5f

**Measured on the integrated tree, after all five landed together: `make test`
279/279, 0 FAIL; `make bootstrap` stage1 == stage2 byte-identical on the first
pass; `make abi-test` and `make layout-test` green.** Each chunk was developed
independently, so this is the number that matters — the per-chunk counts below
are each relative to that chunk's own base and do not sum.

`make test` **274/274** (264 → 266 with W5a's two checks → 270 with W5c's four:
`examples/cstr-defvar.nuc`, two reject fixtures, and the `w5c-cstr-null-exempt`
carve-out tripwire → 274 with W5d's four: `examples/array-literal-ergonomics.nuc`
and three reject fixtures pinning the boundaries the two relaxations must not
cross). `make bootstrap` stage1 == stage2 byte-identical on the first pass for
all of them, no `make update-bootstrap` reconverge — expected: no compiler source
uses a `\x` escape, `boot/nucleusc.ll` contains zero `strcmp(ptr %x, ptr null)`,
and `src/`+`lib/` contain no `(array …)` literal and no by-value struct slot fed
a pointer, so none of the changes moves the compiler's own IR. W5d verified that
claim directly rather than inferring it: a per-function normalized diff
(`%`-names and `@.str.N` numbers stripped) of `build/nucleusc.ll` before/after
shows exactly `coerce-int-val`, `emit-let`, `emit-with`, `emit-zero-store`,
`node-type-block` changed and `array-lit-binding-type` added — zero collateral
movement across the other 950 functions. The `run_no_line_zero` sweep stays
green.

**W5d timing guard** (landmine: a fix that made each element copy quadratically
would pass every small test and destroy the generated-table use case). A 1000-row
`(array St …)` of a 3-field struct, best of 5 on this host:

| | compile+link | `--emit-llvm` only |
|---|---|---|
| before, `(deref (St …))` spelling | 0.272 s | 0.153 s |
| after, `(deref (St …))` spelling | 0.265 s | 0.151 s |
| after, bare `(St …)` spelling | 0.259 s | 0.146 s |

Unchanged, and the last two rows emit **byte-identical IR** (1000 allocas, 1000
loads — linear).

### W5c ↔ W6 null-safety hole: disjoint, with the carve-out pinned

`defvar`'s global initializer bypasses the null-safety check —
`(defvar g:ptr:Thing null)` compiles clean and segfaults at runtime while the
identical *local* is rejected, because this constant renderer never routes
through `coerce-int-val` and so never runs `pkind-flow-check`. Independently
confirmed from the orchestrating session, not just reported. **W5c neither
widened nor closed it**, verified by measurement: the old gate accepted every
`TY-PTR` regardless of pkind, the new one accepts `TY-PTR ∪ TY-CSTR`, so the
delta is exactly `{TY-CSTR}`, and both repro programs behave identically before
and after. Closing the hole is tracked under W6's §3.4 triage, and it must add
its pkind check to the **ptr path only** — `CStr` is flow-exempt (a null
`char*` is ordinary C). `defvar-init-ir` states that exemption as its own
commented early return rather than letting it ride on `is-ptr-like`, and
`tests/fixtures/w5c-cstr-null-exempt.nuc` (via the new `run_accepts` helper)
fails if a stricter check ever sweeps `CStr` up with `ptr`.

**Closed 2026-07-31** — see [nullability.md](nullability.md) §1.5 *Status*.
`defvar-init-ir`'s `null` branch (`src/nucleusc.nuc:8395`) now calls the *same*
`pkind-flow-check` the local path calls, with the same raw type
`emit-symbol-ref` gives the `null` symbol in value position (source type
`ty-raw`, ctx `"defvar"`), so the global path runs the *same* predicate as the
local path instead of re-deriving it — which is what makes the carve-outs
automatic rather than something to re-implement: `(raw T)`/`?T` are not
`PTR-REF` and return at once; an elem-less bare `ptr` — the `void*` escape
hatch, ~1550 bindings in the compiler's own source — is exempt via the
untyped-destination refinement; `CStr` keeps its own explicit early return
*above* the check (pinned by the W5c tripwire), because `ptr-pkind` answering
`PTR-RAW` for every non-`TY-PTR` kind is an accident of the encoding, not the
policy, and must not be relied on here. The diagnostic body is identical to
the local path's. Tests 300 → 303.

**Measured, and deliberately left open — the no-init spelling.** A
balanced-paren census of every `defvar` form in `src/ lib/ examples/
tests/fixtures/`: **254** forms, **115** with no initializer, of which **53**
declare a non-null element-typed pointer — 20 `ty-*:ref:Type` singletons,
`g-globals:ref:Scope`, and 32 registry tables spelled
`(ref (Vector …))`/`(ref (HashSet …))`/`(ref (HashMap …))`, all in the
compiler's own source, all process-lifetime singletons filled by
`types-init`/`compiler-init` immediately after definition. `emit-defvar`'s
no-init default still emits `global ptr null` for any `is-ptr-like` type, so
**`(defvar g:ptr:Thing)` still produces exactly the IR the fix now rejects for
`(defvar g:ptr:Thing null)`** — an author blocked by the new error can get the
old, unsound behaviour back by deleting the word `null`. Closing that is not a
check but a language question (deferred initialization of a non-null global);
it belongs to W6 proper, and this asymmetry is exactly what the external Doom
port hit 13 times (see "The external Doom-port regression" below).

**Premise correction.** The brief that shaped this fix predicted "a rejection
path cannot move IR", which held for *IR* but not for the *tree*:
`examples/colon-paren-types.nuc:23` terminated a hand-rolled linked list with
`(defvar empty:(ptr Link) null)`, and `make test` failed on it once the fix
landed. `nullability.md` §1.5's "zero compiler churn" measurement had scanned
`src/`+`lib/` only; `examples/` turned out to be a separate gate. Fixed by
moving `Link.next`, the global, and `chain-sum`'s parameter to `(raw Link)` —
the nullable kind the design doc itself prescribes for this idiom — with
runtime output byte-for-byte unchanged.

### New limitations discovered during W5 (not fixed here)

* **A string literal cannot carry an embedded NUL.** `lex-string` decodes
  escapes into a *counted* buffer, but the token stores the result via
  `arena-strndup` as a NUL-terminated `char*` on `Tok.s` and **drops the
  count**; the length is re-derived downstream with `strlen`. So `"x\0y"` and
  `"x\x00y"` are both length 1, truncated at the NUL. This is pre-existing
  behaviour of the token representation, shared with the long-standing `\0`
  escape — `\x` does not introduce it. Fix direction: carry a `len` beside
  `Tok.s`. `examples/hex-escape-test.nuc` pins the current behaviour so a future
  fix is a deliberate, visible change rather than a silent one; documented in
  `docs/types.md`. Found during W5a.
* **`boot/nucleusc.ll` is unbuildable at commit `04c55ec` ("Merge stage14").**
  It carries **two** `@emit-keyword` definitions, the second corrupt (its GEP
  claims `[15 x i8]` but points at a `[5 x i8]` string constant) — evidently a
  bad merge resolution of the generated artifact. `make` fails at `ensure-boot`
  in any fresh checkout of that commit. **The current branch is unaffected**
  (verified: one definition at `HEAD`, and `make` rebuilds cleanly), so this is
  historical, but a clean clone pinned to `04c55ec` cannot bootstrap. Found
  during W5a.

---

## W1 — Whole-unit signature resolution

Spec: [resolution.md](resolution.md) (with a "W1a/W1b as built" addendum at the
bottom carrying the answers to the design's open questions).

| Chunk | What landed | Status |
|---|---|---|
| **W1a + W1b** | Cross-file function references now resolve on **reachability**, not import order — the ordinal rule *"X may reference a function in Y ⟺ Y begins processing before X is emitted"* is retired. Mechanism: a **second** whole-graph prescan pass, `prescan-imported-signatures` (`src/nucleusc.nuc`), walking the same depth-first import graph as `prescan-imported-types` and registering every reachable `.nuc` file's **protocols** and **defn signatures**. Two passes, not one: a signature's types must resolve against the *whole* graph's type names, and a one-pass walk would prescan file F before a sibling G their parent imports after it — the compiler's own `src/generics.nuc` (signatures naming `Method`/`Generic` from the sibling `src/compiler-types.nuc`) would have hit that immediately. Registration is **not idempotent** (possibility (3) of the design's list: `generic-register-method` appends unconditionally and `generic-add-method` clears `finalized`, so a second pass makes every signature a duplicate overload), so `g-prescan-sigs` records each prescanned path and `emit-toplevel-forms` skips its own protocol/signature prescan for it — while still calling `finalize-generics` at exactly the same point, so only *registration* moves earlier. The duplicate-signature check is untouched: two files defining the same name+arity still error. W1b is part of it, not a follow-up: the walk applies each visited file's own leading `(ns …)`/`set-ir-prefix` and restores afterwards, because `scope-define` qualifies a global's key against `g-current-ns` and `generic-new` snapshots the namespace ir-prefix that `finalize-generics` bakes into the solitary method's ir-name. `finalize-generics` needed no register/finalize split — per-file is safe by the same reasoning `generic-add-method`'s own comment records. `.nuch` headers are deliberately excluded from the new pass (their importer never runs `prescan-defn-signatures`; entries arrive as `declare`/`defmethod`/template-`defn` with their own registration paths), as are C-header string imports (reading one shells out to clang) and any path already on `g-imported` (the REPL loads one import per command). | **Done** |
| **W1c** | The unresolved-name diagnostic now distinguishes the three failures W1a left behind, at one chokepoint each: `unresolved-name-message` (`unknown:`/`undefined:`) and — for §2.7's type reachability constraint, which W1 keeps — a new `unknown-type-message` called from `parse-type-name` (`src/union-registry.nuc`). Tier order, unchanged at the top: the **C-header skip note** (W3c) first, then the new **unreachable-file note**, then the did-you-mean, then a plain *"not defined anywhere in this compilation unit"*. The middle tier is the point of the chunk — on failure the compiler scans the `.nuc`/`.nuch` files in exactly the directories `resolve-import` searches (the current source file's directory, `lib/`, each `-I`), skips every file already in the unit (`g-prescan-visited` / `g-prescan-sigs` / `g-imported`, plus the unit's root, which is on none of those lists and gained `g-unit-entry-path` for that reason), and names the first file outside the unit that defines the name: `note: 'y-later' is defined in ./yf.nuc, which no import in this unit reaches`. It suppresses the did-you-mean rather than stacking with it — naming the file is a strictly better answer than guessing a spelling, and the two collide almost never because the scan matches the name *exactly*. Deliberate implementation choices: a **textual** scan of file bytes (re-entering `read-program`/`desugar` from a diagnostic would clobber `g-src`/`g-pos`/`g-line`/`g-source-path`/`g-peek` mid-message for no benefit), skipping line comments and string literals so the two obvious false-positive sources are out; **error path only** — both callers of `unresolved-name-message` and the `unknown type:` raise are `die-at`, which is `noreturn`, so the scan runs at most once per compile and cost is unobservable (a failing fixture compiles in the same 0.135 s as a clean one). Directory enumeration uses hand-declared POSIX `opendir`/`readdir`/`closedir` (the C-header reader registers `struct dirent` as *opaque* — its `char d_name[256]` member defeats the declaration parser — so a field access on it is refused); the `d_name` byte offset is **validated, not trusted**: an entry is used only if the bytes there are a short NUL-terminated name ending `.nuc`/`.nuch`, so a platform with a different layout finds nothing rather than printing garbage. `$NUCLEUS_LIB` and the install prefix are deliberately *not* scanned — a stdlib file is not something the user can fix by editing an import. | **Done** |
| **W1d** | Mutual-import policy — decided twice the same day. First **Option 1** (keep `circular import` a hard error; now-correct advice since W1a made "a common parent imports both, neither imports the other" the recommended, order-independent spelling). Then **SUPERSEDED by the user's choice of Option 2**: import cycles are legal. Both `g-importing` sites in `do-import` (`src/nucleusc.nuc`, the `NODE-STR` `.nuc`-path branch and the `NODE-SYM` branch) now call `note-import-cycle` and `return` instead of `die-at`. The skipped path is deliberately **not** pushed onto `g-imported` — that list means *finished*, and its `[start-len, end-len)` slice is what a later prefixed import replays — so emission is idempotent per path: each file emits once, at first reach. Four things a cycle does not carry, because each exists only once a file has been *emitted* and a cycle member's body is emitted before the rest of its back-import — diagnosed, not supported, all gated on `g-import-cycles != null` so a unit with no cycle takes the identical pre-W1d path: (1) a `defmacro` the partner defines (registers at emission time; no macro prescan exists, and adding one means emitting *and JIT-compiling* the macro body early — its own stage); (2) a `defconst`/`defenum` **member** the partner defines (a name-registration failure, not layout — `text-defines-name` gained a member sweep, since it previously matched only the enum's own name, closing the same blind spot in W1c's unreachable-file note); (3) a struct/union **layout** the partner defines — field access/assignment/address, a struct literal, a by-value field/param/return/arg (`cycle-pending-sdef`/`reject-cycle-pending-layout`/`reject-cycle-pending-sdef`, `src/type-utils.nuc`, mirroring `reject-opaque-type`'s site list); **`(sizeof S)`/`(alloca S)` across a cycle are NOT in this list** — measured to work, since both lower to a GEP/alloca over the LLVM *named* type, resolved from the `%S = type {…}` line LLVM finds later in the same module — the design doc's premise that these fail was wrong; (4) a `prefix/name` alias over a cycle member (the bare `(import foo)` spelling *is* the prefixed one, so a cycle written with it always suppresses an alias set). A **fifth, unspecced coupling was found by measurement, and it was the only silent one**: a by-value struct at an ABI boundary — `abi-classify` sized the unlaid-out struct at 0 and emitted `define i32 @f(i0 %v.arg)` against a call site passing two `i64`s, surfacing only as an unlocated `failed to parse generated IR`; now checked in `abi-classify` itself, the one chokepoint `emit-defn`/`declare`/`emit-call-with-args`/`emit-return` all funnel through. **Also fixed here (pre-existing, reproduces on the committed boot):** `emit-import-prefixed` defaulted **every** `NODE-STR` import's prefix to `"c"` — correct for a C header, wrong for a `.nuc` path — so two Nucleus string-path imports in one file collided on a prefix the author never wrote; a `.nuc`/`.nuch` path now defaults from its **basename** (`path-import-default-prefix`), the same rule the symbol spelling already used. **Also fixed (memory safety, found while lengthening these diagnostics):** `src/format.nuc`'s helpers passed `snprintf`'s return — the length the output *would* have had — straight to `arena-strndup`, which `memcpy`s that many bytes out of a fixed stack buffer; any diagnostic longer than the buffer was a stack over-read. All helpers now clamp through `fmt-take`; string-carrying ones moved 512 → 1024. **Bootstrap prediction held**: `make bootstrap` byte-identical on the first pass (any program that reaches the guard today is already a hard error, so no *compiling* program's emission order can move) — confirmed further with a pre/post `--emit-llvm` sweep over `examples/`+`lib/`, 168 byte-identical, 0 differing. Tests: `run_w1_circular_still_errors` **replaced, not deleted**, by `run_w1d_cycle_accepts` (5 units — both orders, `import-use`, three-file, self-import; each compiles, links, runs, asserting an exit status, and the two orders return *different* values so they cannot pass by shared accident), `run_w1d_cycle_diagnoses` (8 units — one per coupling above, plus duplicate-still-rejected-inside-a-cycle), `run_w1d_path_prefix` (4 units). 303 → 319 PASS, 0 FAIL. **If a future stage wants full cycles**, the macro prescan is still the thing to scope first; the layout couplings would need a separate graph-wide layout prescan, which reorders the type section for every program and so cannot be additive the way W1a's signature prescan was. Full account: [resolution.md](resolution.md)'s W1d section, in particular the SUPERSEDED box. | **Done** |
| **W1e** | `declare` as a forward prototype. | **Resolved by obsolescence, no mechanism built** — the design's shape-3 hazard (`declare` + a reachable `defn` → `duplicate method signature`) does not reproduce, and W1a makes the mechanism that prevents it fire *more* often: `emit-nuch-declare-import` returns early when the name is already in `g-globals`, so a `declare` matching a reachable solitary `defn` is a complete no-op |

### The defect W1a exposed (pre-existing, fixed here)

`defunion-register` (`src/union-registry.nuc`) wrote a union backing struct's
`%X = type { i32, %__anon_union_… }` line **eagerly** while the anon payload union
it names sat on the deferred `g-pending-unions` queue. For a scalar payload the
union lands at the very next drain; for a **struct** payload (`!String`) it waits
for `%String`, which arrives with a later import — and every module assembled in
between (a `compile-time` block, a `defmacro` JIT module) carries the reference
with no definition. Reproduces on the committed boot compiler:

```lisp
(compile-time (printf "ct ran\n"))
(import-use string)
(defn wrap (sv:StrView):!String (return (string-from-view sv)))
(defn main ():i32 (return 0))
```

→ `use of undefined type named '__anon_union_h5cc06870e474e483'`. W1a widens the
dangling window to the whole build (the stamp now happens during the prescan),
which is how eleven examples surfaced it at once. Fixed at the root: the backing
struct is queued instead of written eagerly **exactly when writing it now would
dangle**, so it emits after its payload union, in dependency order; the queued
renderer's text is character-identical, and a scalar/pointer payload keeps the
eager write and its IR position.

### The second defect W1a fixed: a symbol mangled *after* it was emitted

`emit-defn` reads `defn-ir-name` at emission time and `finalize-generics` decides
solitary-vs-mangled from the method set known *then*. Under the ordinal rule a
file could be emitted before a later import registered a second method of the
same name: the definition went out as the solitary `@append` while every call
site emitted afterwards went through generic dispatch and named
`@append.ptr.ptr`. On the committed boot compiler,
`(import-use "lib/list.nuc")` + `(import-use vector)` + a call to `append`
emits `define ptr @append` and `call ptr @append.ptr.ptr`, and the link dies
`use of undefined value`. W1a makes the decision final before the first `define`
is written. This is why `examples/rest-defn.nuc` and `examples/string-test.nuc`
are the only two programs in the tree whose IR changed by more than type-line
order: their symbols are now the correct (mangled) ones.

### Pre- vs post-W1a sweep, every `lib/` and `examples/` program

| Outcome | Count |
|---|---|
| Byte-identical IR | 104 |
| Type-definition **order** only (normalized-identical) | 55 |
| Real IR difference — the late-overload symbol fix | 2 |
| Compiled before, fails now | **0** |
| Failed before, compiles now | 5 (`lib/string.nuc` via the anon-union fix; four W5-era features the committed boot predates) |

### Test/bootstrap status after W1a/W1b

`make test` **293 PASS / 0 FAIL** (279 before; +14 units:
`w1-mutual-order1/2`, `w1-ns-order1/2`, `w1-diamond`, `w1-two-routes`,
`w1-two-higher`, `w1-duplicate-rejected`, `w1-missing-rejected`,
`w1-declare-cycle-breaker`, `w1-declare-plus-import`,
`w1-circular-still-errors`, `w1-deferred-union-payload`,
`w1-late-overload-symbol`). Every positive unit
compiles, **links and runs**, asserting the program's exit status — an exit-0
compile alone would not catch a call routed to the wrong symbol.
`make abi-test` and `make layout-test` both PASS.

**`make bootstrap` was not byte-identical on the first pass**, and unlike every
earlier Stage 15 chunk this one is *expected* to move IR: front-loading the
signature prescan front-loads the first stamp of every parametric instance an
imported file's signatures mention, and a stamp is what queues its
`%Name = type {…}` line. The diff was proven inert before reconverging: 44
changed lines, **all** of them type definitions moving within the type section;
sorting the type-definition lines in both files makes them **byte-identical**, so
the *set* of definitions is unchanged and **zero** `declare`/`define`/string-table
/function-body lines differ. LLVM named struct types are order-independent within
a module (the deferred queue's own header comment says so, and the pre-W1a output
already contained forward references among these very lines). The new compiler is
a fixed point on its own — recompiling `src/nucleusc.nuc` with a binary built from
its own output reproduces that output byte-for-byte — so the `make bootstrap`
diff was purely "stage1 comes from the old boot". Reconverged per
[../../context/build.md](../../context/build.md).

### Test/bootstrap status after W1c

`make test` **297 PASS / 0 FAIL** (293 before; +4 units: `w1c-unreachable-file`,
`w1c-note-advice-works`, `w1c-defined-nowhere`, `w1c-unreachable-type`). The
note unit and its negative control are one pair on purpose: the same sibling
file that produces the note must, once imported, compile **link and run** — the
note has to be advice that works, and the scan must not fire on a definition the
unit already reaches. `make bootstrap` **byte-identical on the first pass**
(W1c touches only error paths and message text, so it cannot move emitted IR);
`make abi-test` and `make layout-test` both PASS. The committed
`boot/nucleusc.ll` is deliberately **not** refreshed — it still bootstraps the
new source, and W1a's reconverge left it current.

### Corrections to the W1c brief

* **`docs/errors.md` is not where these messages are documented.** It covers the
  Stage 10 `!T` / `Err` value-channel error *handling* system. Compiler
  diagnostics live in `docs/compiler.md`; its "Did-you-mean" section became
  "Unresolved names" and now documents all four tiers, with a cross-link from
  the reachability bullet in `docs/toplevel.md`.
* **The uncertainty about fatal callers resolves cleanly.** Both callers of
  `unresolved-name-message` (`emit-symbol-ref`'s value position,
  `emit-dispatch`'s head position) and `parse-type-name`'s `unknown type:` raise
  are `die-at`, which carries `noreturn`. No speculative or recoverable caller
  exists, so no gate on the scan was needed. (In the REPL `die-at` unwinds via
  `repl_throw` instead of `exit`, which is still the error path — one scan per
  failed command, verified interactively.)
* **Pre-existing quirk found, deliberately not fixed here.** A reference to a
  namespaced function by its *unqualified* name reports
  `unknown: thing (did you mean 'thing'?)` — `closest-known-name` searches
  `Generic.name` (the bare spelling) while the scope key is `ns/thing`, so the
  suggestion is the identical text. That is a W4a namespace-suggestion gap, not
  a W1c one; the right message names the *qualified* spelling, which is a
  separate change. Suppressing an identical suggestion alone would be a
  regression — the message would fall through to "not defined anywhere in this
  compilation unit", which is more wrong than the tautology.

## W7 — The bare-symbol selector always means "field name"

**Status: done** (options B + D + E). Spec:
[selector-ambiguity.md](selector-ambiguity.md). **Provenance: the author's own
stress testing of the language, not the Doom port** — this item has no `§`
number in `NUCLEUS-FINDINGS.md`.

Reported from `examples/hashmap-lit-test.nuc`, whose working tree now binds
`k:CStr "foo"` and calls `(m k)`. That fails —
`get: no field 'k' on struct 'HashMap.cstr.i32'` — while `(m "foo")` succeeds.
It was the one failing test in the suite when the work started (296 pass, 1
fail) — the reproducer, not a regression. The suite is now **300 pass, 0 fail**.

* **Root cause is two-part.** `selector-literal-sym` (`nucleusc.nuc:3234`)
  classifies a selector by node kind alone — any `NODE-SYM` is a field name,
  scope and the callee's field set are never consulted — and
  `emit-get-with-callee` (`:3418`) has **no edge from its symbol branch back to
  its value branch**, so once classified the value reading is unreachable even
  when the field reading provably cannot work. Separately,
  `emit-invoke-with-callee` (`:3491`) never falls back to `get`, so
  `(invoke m k)` — the form whose arguments *are* values — cannot serve as the
  escape hatch. The only working spelling today is to obfuscate the selector
  into a compound expression, `(m (as CStr k))`.
* **Blast radii were measured, not estimated.** Two temporary probes were added
  to Branch A and the compiler plus every file in `examples/` was compiled;
  probes then removed and the tree verified back to its original state.
  Scope-first resolution would silently re-interpret **79** sites in the
  compiler's own source (`name` ×27, `line` ×17, `s` ×6, `ty` ×5, …) and turn
  `examples/get-dispatch-test.nuc:29`'s `(= (self key) key)` into infinite
  recursion — the exact hazard `context/conventions.md` says `_get` exists to
  avoid. The `invoke`-symmetric rule costs **26** distinct lines, 23 of them
  mechanical `_get` conversions inside `lib/hashmap.nuc`.
* **`lib/hashmap.nuc:282` is the stdlib's only value-keyed `get`,** which is why
  the principled option is affordable.
* **Marked selectors were evaluated as the end state** (option F, added on
  review). Requiring `'field`/`:field` frees bare symbols to mean variables as
  they do everywhere else — **selector position is the only place in the language
  where a bare symbol is not a variable reference**, which is why the reported
  bug is the rule working as designed rather than a corner case. Measured at
  **~3,800** sites (4,151 emit-time occurrences compiling the compiler, the gap
  being template re-emission), of which **0** are currently quoted, against
  **49** static `_get` uses.
* **Both marks already exist in the reader.** `'sym` is accepted by
  `selector-literal-sym` today. `:foo` lexes to a `NODE-KEYWORD`
  (`lib/reader.nuc:887`) that the compiler already treats as a *compile-time*
  name for type spellings (`type-mangle.nuc:165-174`) and declaration attributes
  (`union-registry.nuc:1174`) — and `(p :x)` is unused in selector position
  today (it lowers to a runtime `keyword-intern` and dies with "no `invoke`
  method"), so the syntax is free to claim. `'field` is the safer claim; `:` is
  the most overloaded character in the language and the type-spelling
  interaction must be checked first. Note `p.x` is **not** available — it lexes
  as a single symbol.
* **The migration is automatable.** `g-source-path` is swapped per
  source-imported file, so a `--warn-bare-selector` mode can emit exact
  `file:line: field` triples for a structural rewriter — the compiler is the only
  thing that knows which `(a b)` forms are field accesses rather than calls.
  Staged accept-both → warn-and-rewrite → flip, the same shape as the Stage 10
  Phase F nullability flip, so no step is both breaking and unverifiable.
* **Recommendation: `invoke`→`get` fallback + "field-first, value fallback" in
  this stage; marked selectors as their own stage.** The zero-risk pair fixes the
  reported bug now and forecloses nothing (the demotion rule is deleted wholesale
  when marked selectors land, and the `invoke` fallback is wanted under them
  too). The `invoke`-symmetric rule is the option to **skip** if marked selectors
  are on the roadmap — it costs 26 lines of churn to buy a rule they immediately
  replace. Counter-consideration recorded: marked selectors reverse Stage 9's
  deliberate migration *to* head-position field access, and `_get` survives
  either way (a user `get` reading its own fields still needs the bypass —
  `(self 'cap)` still dispatches into the same method).

### W7 as built

Three changes in `src/nucleusc.nuc`, plus two new predicates beside
`selector-literal-sym`:

* **B — the demotion** (`emit-get-with-callee`). A bare symbol demotes to a value
  selector when `callee-has-field` is 0 and `selector-shadowed-by-local` is 1.
  `(= sym sel-node)` is the bare-vs-quoted discriminator — `selector-literal-sym`
  returns the node itself for a bare symbol and the *inner* node for `'sym` — so a
  quoted selector is never demoted.
* **`selector-shadowed-by-local` accepts locals only.** Globals would be far too
  broad: every function lives in the global scope, so accepting non-locals would
  demote `(sd name)` the moment any global named `name` existed.
* **The design's proposed extra gate was unnecessary and was dropped.** The spec
  suggested gating the demotion on the local's type actually resolving a `get`, to
  keep a plain-struct typo's diagnostic. Not needed: when Branch B finds no method
  it falls through to `emit-get-intrinsic`, which re-reads the still-symbol
  `sel-node` and reports the same "no field" error on its own.
* **D — the `invoke`→`get` fallback** (`emit-invoke-with-callee`), gated on
  `generic-has-receiver-method` returning 0. **Gating on that probe rather than
  resolving through `generic-resolve-nullable` is load-bearing:** the nullable
  resolver omits tier-2 untyped-literal widening, so putting it on the primary
  path would have silently regressed `(v 3)`. The probe is side-effect-free and
  tolerates a null generic, leaving the ordinary invoke path untouched.
* **E — the diagnostic** (`emit-get-intrinsic`), via `fmt-3s`, fires only when the
  missing field name is a local binding.

**Verification.** `bin/nucleusc` is the pre-change compiler (rebuilt from
`boot/nucleusc.ll`), so emitting IR for every example with both binaries is a
direct A/B: **135 byte-identical, 0 differing, 1 newly compiling**
(`hashmap-lit-test`), 1 failing on both. `make bootstrap` passes. Tests 296/1 →
**300/0**, the three new units being `selector-value` (positive matrix),
`w7-local-not-a-field` (the hint) and `w7-plain-typo` (the hint must not leak onto
an ordinary typo).

**Unrelated pre-existing failure noticed, not fixed:** `examples/comb-shapes.nuc`
fails identically on both compilers with `as: lossy conversion from usize to i32`
at line 36, and has no `tests/expected/` entry so the suite never ran it.

**Known limits, deliberate:** a field name wins over a same-named local
(`(m count)` is the field); globals never demote. `(invoke m count)` is the escape
hatch for both. `_get` is not retired — a user `get` reading its own fields still
needs the bypass, since `(self 'cap)` dispatches back into that same method.

---

## The external Doom-port regression (2026-08-01)

This is `prompt.md` §6's "only test that proves the stage achieved its
purpose" — the ~25,000-line Doom port at `/home/zak/code/nuc-doom-claude`
rebuilt against the finished compiler with its two named workarounds removed:
`src/g_game.nuc`'s load-bearing import ordering (`s_sound` is now imported
**last**, well after `p_map` is expanded inside `p_spec`'s chain, and all five
of the forward references that mandated the old order resolve regardless), and
the `(as ui32 SOME_DEFCONST)` comparison casts across `p_enemy`, `p_map`,
`p_telept`, `r_main`, `r_plane`, `tables` and `video`. Both gates are bit-exact:

```
== test_demo: 182 checks passed, 0 failed ==
ALL 35 TICS BIT-EXACT

== test_demo_monsters: 1654 checks passed, 0 failed ==
ALL 150 TICS BIT-EXACT (WITH MONSTERS, vs the real engine)
```

The port's working tree already carried the 8 files with the workarounds
removed from a prior session; this pass ran the build and demo gates against
the compiler landed here, fixed one stale comment
(`src/g_game.nuc:57-61`, which still said mutual imports were a hard error),
and committed nothing in either repo — the port was not otherwise restructured.

**Two findings came out of the run. Recording both prominently — they are the
stage's most important output after the gates themselves:**

1. **The W6 §3.4 fix broke 13 sites in the port**, all one shape:
   `(defvar- g-X:ptr:T null)`, the lazily-initialized process-lifetime
   singleton idiom (`g-mobjinfo`, `g-weaponinfo`, `g-channels`, `g-spmus`,
   `g-intercepts`, `g-demo-p`, `g-players`, `g-music`, `g-sfx`, `g-tmbbox`,
   `g-heightlist`, `g-sprnames`, `g-states`). Resolved by **deleting the
   redundant ` null`**, a pure deletion that emits identical IR — but only
   because the no-init spelling is still accepted (see "W5c ↔ W6 null-safety
   hole" above). This is the asymmetry that section flags, hit by the first
   external program to meet the fix, 13 times across ~60 files. It is direct
   evidence for prioritizing the deferred-initialization language question in
   W6 proper, ahead of flow typing itself.
2. **`defconst`/`defenum` are still import-order dependent.** W1 covered
   `defn` signatures and protocols only. Verified against the current
   compiler: two sibling files where `ca.nuc` references a `defconst` defined
   in `cb.nuc`, with a common parent importing both — `(import cb) (import
   ca)` runs and returns 42, `(import ca) (import cb)` dies. **The diagnostic
   asserts something false**: `ca.nuc:1: error: undefined: MYK — not defined
   anywhere in this compilation unit`, when `MYK` *is* in the unit and merely
   not yet processed (W1c's unreachable-file note correctly does not fire,
   since `cb.nuc` is reachable — the note's job is a different failure mode).
   This is the constraint that still forces `p_spec` to lead the port's
   import list; the port documents it as `NUCLEUS-FINDINGS.md` §12 and the
   `g_game.nuc` comment block explains it. **Record it as the top candidate
   for the next stage**, alongside the already-listed struct packing
   (`prompt.md` §7, §4.1) and fixed-size array fields (§4.2).

Neither finding is a defect introduced here — (1) is the pre-existing W6 §3.4
hole in a different spelling, recorded as deliberately open; (2) is
`defconst`/`defenum` ordinal registration, which W1's signature-and-protocol
prescan never claimed to cover.

**Both are now assigned, within this stage rather than a future one:** (2) is
**W8's G-0** and (1) is **W8's G-5**. See the W8 section below.

---

## W8 — Combined declaration and initialization *(added 2026-08-01; all six steps G-0 through G-5 done, 2026-08-01/2026-08-02)*

**Spec: [../global-init.md](../global-init.md)** — the source of truth. This
section records the filing and the shape of the item; it does not restate the
design.

**Headline goal: eliminate `compiler-init`, or reduce it to a few genuinely
special cases.** A global that should not be nullable is declared and
initialized in **one** operation, and the startup mechanism is **zero-cost when
unused**: a program with no runtime initializer emits no `@__nucleus_init`, no
`llvm.global_ctors` entry and no synthesized `main`. That is a hard requirement
with a stated reason (microcontroller binary size), not an optimization.

**Why it is in this stage.** It is the answer to the thing W6 §1.5 explicitly
parked. W6 closed `(defvar g:ptr:T null)` and left `(defvar g:ptr:T)` open,
because closing it needs *a way to express deferred initialization of a non-null
global*, which the language does not have. The Doom-port regression run then hit
that asymmetry 13 times in one afternoon, and the compiler's own census found 53
instances of it in `src/`+`lib/`. Both findings above are sub-items of this one.

**Staging** (`global-init.md` §5), **all done**: **G-0** value names resolve on
reachability (prerequisite, and shippable on its own — this is finding (2)
above) → **G-1** constant expressions in `defvar-init-ir` → **G-2** an
`(array T N)` type + constant aggregate initializers → **G-3**
`@__nucleus_init`, emitted only when the queue is non-empty → **G-4** the
ordering diagnostic and the `docs/` rule → **G-5** eliminate `compiler-init`,
then flip (this is finding (1) above). Acceptance criterion (A)
(`compiler-init` eliminated) and (B) (the flip) are both met by G-5.

**What the design measured, in one line each** — the numbers a future
implementer should not re-derive:

* **`compiler-init` is 51 statements** and runs **exactly once per process**
  (`nucleusc.nuc:12507` batch, `repl.nuc:850` REPL, mutually exclusive). **30
  statements become combined declaration+initialization, covering 48 globals**
  (3 constant, 45 runtime); **20 statements are dead** — they restate the
  `defvar` zero default and no per-unit reset is load-bearing; **1 statement is
  the residue**, `(target-init)`, which reads argv and so can never be an
  initializer.
* **The compiler's `defvar` census is 174 forms** (164 `src/`, 10 `lib/`), 114
  with no initializer, of which **53** are non-null element-typed. 51 of those
  53 have exactly one `(set! …)` site in the whole tree.
* **The do-nothing alternative is priced exactly**: re-spelling the 53 as
  `raw:T` costs **249 flow violations across 197 lines and 10 files**, measured
  with a warn-only compiler built in scratch (control run: 0).
* **The external corpus is 20-of-21 static**: of the Doom port's 21 hand-rolled
  `ensure-*` lazy initializers, 9 are constant tables and 11 are fixed-size
  zero-filled buffers; only 1 is genuinely runtime. This justifies shipping the
  static half first. **It is no longer the deciding corpus** — the compiler is —
  and per the author's direction **the port is not to be converted yet**.

**Two premise corrections the design made against its own first draft**, both
by reading `src/`, and both worth carrying forward because they change what has
to be built:

1. **The `g-arena-alloc` migration blocker dissolves.** The first draft called
   it "a fourth bucket no initializer expression can express" — an
   out-parameter-mutated by-value `AllocHandle`. But `AllocHandle` is
   `{kind:i32, data:ptr}` and the arena handle is `{ALLOC-ARENA, null}`: a
   **compile-time constant struct**, reachable by the static half alone, with no
   ordering rule, no value-returning constructor and no placeholder. The arena
   itself is lazily initialized by `arena-alloc` (`lib/arena.nuc:41`), so there
   is no "arena live first" constraint either. The constant form also *fixes* a
   live latent split: `add-include-path`/`add-link-arg` run before
   `compiler-init` and today silently get libc-backed vectors.
2. **A synthesized `main` wrapper is incompatible with zero-cost-when-unused.**
   The rename happens in `emit-defn`, long before the compiler knows whether any
   runtime initializer exists. The requirement therefore *simplifies* the
   per-triple mechanism split rather than complicating it:
   `ctor-mechanism-for-triple` returns `global_ctors` or `none`, and on a triple
   with no working append-only mechanism a non-empty queue is a **located
   error**, never a dead section (which is what AVR's `.init_array` already is —
   emitted, linked, occupying RAM, never executed, no diagnostic).

**A third finding, new to the design and not previously recorded anywhere:**
`g-vtable-table`, `g-boxedfn-table` and `g-dyn-table` are declared
`(ref (Vector …))` — non-null — and are **never initialized at all**, being
lazily built behind a `(when (= g-X null) …)` guard. That is W6 §1.5's
unsoundness in a *third* spelling, and G-5 cannot close the hole without ruling
on it (eager initializer, or honest `raw`).

**One question the design leaves open**, recorded in `global-init.md` §4.6:
whether a global in `section ".ctors"` with avr-gcc's word relocation is walked
by `__do_global_ctors`. If yes, AVR gains an append-only mechanism; if no, AVR
programs with runtime initializers get a located error. Neither answer blocks
G-0 through G-5.

### G-0 through G-5 as built

[../global-init.md](../global-init.md)'s "G-0 as built" through "G-5 as built"
sections (and the interlude, folded into the G-4 commit) are the source of
truth; this table summarizes rather than restates them.

| Chunk | What landed | Status |
|---|---|---|
| **G-0** | Value names resolve on reachability. `prescan-value-names` (`src/nucleusc.nuc:10797`) extends W1a's whole-graph walk to `defvar`/`defconst`/`defenum`, registering the same `Sym` the emitter would, minus the `@g = global` line; two call sites, both under W1a's existing guard, one of which covers the unit's root file and hence the same-file forward reference. All four of `global-init.md` §2.5's probes now resolve in both import orders. **Two premises were corrected, both in the safe direction**: registration here needed no idempotency guard (`scope-lookup` scans backwards, so a second identical definition is inert — unlike a second `generic-register-method` pass, which *would* duplicate), and duplicate `defconst`s across two files were *already* a silent last-wins before this change, unchanged by it, with the real enforcement being LLVM rejecting two `@g = global` lines for one name. **A latent silent-wrong-answer bug was found and fixed**: a `defconst-` referenced from earlier in its own file resolved to *another file's* public constant of the same spelling, compiling clean and returning the wrong number — G-0 fixes it because the prescan arms `g-defining-private` before the reader reaches the reference. **W1d's cycle diagnostic became partly obsolete**: constants, enum members and `defvar`s now work across a cycle, so `cycle-definer-message`'s note was narrowed to what remains unreachable (macros, `deferror` ids, `extern`), and the two units pinning the old behaviour were **replaced**, not deleted. `make bootstrap` moved by 48 type-definition lines (24 relocations) — proven inert the W1a way (zero non-`%Name = type` lines differed, sorting the type lines made the files byte-identical, stage2→stage3 byte-identical) — then reconverged. **W9 defect 6 is closed at the cause** for the two import shapes G-0 covers; the interim W1c-style note was deliberately declined. **Follow-up filed under W1, not W8**: the prescan still does not cover string-path `.nuc` imports or `.nuch` headers, affecting `defn` and value names identically. Tests 328 → 347. | **Done (2026-08-01)** |
| **G-1** | Constant expressions in `defvar-init-ir`. Folds, with no JIT: `+ - * / %` (including unary `-`), `bit-and`/`bit-or`/`bit-xor`/`bit-shl`/`bit-shr`/`bit-not` over integer literals and `defconst`/`defenum` names, `(char "x")`, `(sizeof T)`, and `(as IntT x)` to any depth; at a pointer destination, `(as PtrT x)` — including `(as CStr "…")` — and `(addr-of other-global)`. **Supersedes, rather than contradicts, the W5c entry above**: W5c recorded `(as CStr "…")` in an initializer as out of scope under "the general expressions-aren't-literals rule" — G-1 *is* that rule changing, not an exception carved into it; the W5c entry stands as an accurate record of what W5c decided at the time. Deliberately does **not** fold floats (folding target FP in the compiler process is the `-ffast-math` hazard [../../context/conventions.md](../../context/conventions.md) records, and the only interesting spelling — `(as f32 1.5)` — is already refused in value position), comparisons/`and`/`or` (an `i1` domain the folder does not model), or aggregates (that is G-2). Overflow is **both** fold-then-range-check and reject-at-the-fold, never a silent wrap; division/remainder by zero and a shift outside `[0,64)` are located compile-time errors rather than executed (which would SIGFPE the compiler) or emitted as poison. The inherited checks demonstrably still fire on folded values (`int-literal-fits`, `pkind-flow-check`, and a newly-extracted shared `as-int-narrowing` in `src/type-utils.nuc:397` that `emit-as` now calls instead of duplicating). **One check G-1 had to add that the value path does not need**: `emit-sizeof` lowers to a GEP over the LLVM named type, resolved late, while the fold reads the compiler's field table via `abi-sizeof` — so `cfold-sizeof` also calls `reject-cycle-pending-layout`, without which a cross-cycle `(sizeof S)` would have silently folded to **0**. Cross-compilation verified sound: `(sizeof ptr)` folds to 2 on AVR, 8 on host. Tests 347 → 361. `make bootstrap` byte-identical on the first pass, as predicted — every shape G-1 adds is one that died before it. | **Done (2026-08-02)** |
| **G-2** | `(array T N)` type + constant aggregate initializers, usable in **both** storage positions — a `defvar` type and a `defstruct`/anonymous-struct-or-union field type — which is the same feature the port reports separately as a Major finding (`NUCLEUS-FINDINGS.md` §4.2, "no fixed-size array struct fields"). All five spec shapes landed: the bare type, `zeroinitializer` for no-init, a constant array aggregate, `(defvar g:ptr:T (array T lit…))` → `@g.data` + non-null `@g = global ptr @g.data`, and a constant struct literal; element values route through G-1's existing folder, so `(array i32 (* 2 3) SOME_CONST)` works. **Central decision: an array is a VALUE in storage and DECAYS to `(ref T)` on read** — C's model, forced by the C-interop invariant (`struct { int xs[4]; }` must lay out identically on both sides) rather than chosen by preference; the pre-existing `(array T lit…)` *expression* already allocas and decays, so a non-decaying *type* would give one spelling two meanings, and non-decay would need machinery (by-value copy, ABI classification, a round-trippable spelling) nothing else needs. Arrays are refused everywhere a value copy would be implied — by-value param/return, `let`/`with`, `ptr:(array …)`, generic argument, nested array, `set!`/`.set!` target — each with a located diagnostic naming the `ptr:T` spelling that works. **Containment is one consumed-once permission** (`g-array-ok`), armed by the four permitting sites and read-and-cleared in `parse-type-from-node`, rather than N per-position refusals — nesting (`(array (array i32 2) 3)`, `(Vector (array i32 4))`, …) falls out free for constructors added later, with no per-constructor check. **Three findings**: `abi-class-eightbyte`'s per-field body defaulted every non-struct, non-float field to INTEGER, which is silently wrong for `{float[2]}` (right size, wrong register class — invisible to any size/offset check, caught only by `abi-test`; fixed by extracting `abi-class-type-at` so the array case recurses per element); `type-size` is the **element** size/alignment, not `N*sizeof(T)` — every caller feeds it into an `align N` operand, which must be a power of two, so `abi-sizeof` is the real size, the same split `TY-STRUCT` already has; and a `defvar`'s type resolves **twice** (G-0's prescan, then emission) but macros register only at emission, so a third **provisional** length state was added in which `type-to-ir` dies rather than silently emitting a legal `[0 x i32]` (a flexible array member, which would have been silent). **The spec's own *Verify* clause was self-contradictory**: it demanded both converting `g-arena-alloc` to its constant form and a byte-identical bootstrap, and those cannot both hold — the committed boot compiler cannot parse a constant struct initializer at all, so any in-compiler use of G-2 fails `make` itself before `make bootstrap` can run. **Resolved by splitting**: the array feature shipped byte-identical; the `g-arena-alloc` conversion is deferred as G-2b/G-5 work and was **de-risked, not merely deferred** — reproduced end-to-end (compiled, linked, ran), yielding two facts the follow-up now has: `null` into `AllocHandle.data` passes the Phase-F gate because `data` is the elem-less bare-`ptr` carve-out, and no source reorder is needed, since §2.10's reorder is a *runtime*-ordering requirement (G-3's, not this one's). Struct-packing deferral holds, now **measured** rather than assumed — all six layout shapes and four ABI shapes match the platform C compiler with natural alignment alone; nothing in G-2 wanted an attribute. Tests 361 → 385 (counted with `NUCLEUS_TEST_JOBS=1`; the parallel count wobbles between 383 and 385, W9 item 10). `make bootstrap` byte-identical on the first pass — every G-2 shape is one that died before it. `make abi-test`/`make layout-test` both **extended** for the new type (six array-field layout shapes, four by-value array-field ABI shapes) rather than a parallel mechanism invented. | **Done (2026-08-02)** |
| **G-3** | `@__nucleus_init`, emitted only when the initializer queue is non-empty. A `defvar` initializer G-1/G-2 cannot fold is queued (`InitJob`: form, namespace, source path, line) and drained at `emit-toplevel-forms` depth 1 into a synthesized `void @__nucleus_init()`, registered by `llvm.global_ctors`. **The queue predicate is not a new classifier** — a one-shot `g-defvar-soft` flag armed around one call turns `defvar-init-ir`'s *terminal* "must be a compile-time constant" raise into a `null` return; every other raise inside the renderer still fires, so a malformed *constant* stays an error rather than silently becoming a runtime initializer. `ctor-mechanism-for-triple` answers `global_ctors` (hosted) or `none` (AVR — a non-empty queue is a located error naming the offending `defvar`, never a dead `.init_array` section). **Zero-cost when unused is proven by a two-sided tripwire**: one fixture asserts a constant-only unit using every G-1/G-2 constant shape emits neither `__nucleus_init` nor `global_ctors`, then adds one runtime initializer to the identical unit and asserts both appear, so deleting the feature outright cannot pass either half. `run_g3_library`: a `.nuch`+`.o` multi-TU library with **no Nucleus `main` anywhere**, initialized by its own object's `.init_array` entry and read correctly by the consumer — the case a synthesized entry point provably cannot serve. **One spec hole found and closed**: §4.5 said "run the initializer immediately at the `defvar`" for the REPL, but `(import-use …)` at the REPL reaches the depth-1 drain and appended `global_ctors` into a module ORC then JITed it — and ORC has no initializer entry point, so the imported global read back **0** silently; both REPL routes (direct `defvar`, `import-use`) now JIT-and-call. **A second hole**: the queue record's context fields (`g-current-ns`, `g-source-path`) are not diagnostics-only — they drive `qualify-name` and `priv-key-use`, so without restoring them at drain time a namespaced or `defvar-`-private initializer would fail to *resolve*, not just misreport its location. Two pre-existing defects found, neither fixed here (see the Interlude and W9 items 15/18/19/20 below): a function-pointer-typed `defvar` could not be declared at all, and `aref` emits a hardcoded `i64` GEP index invalid on AVR. Tests 385 → 393; `make bootstrap` byte-identical on the first pass; old-vs-new `--emit-llvm` sweep against a compiler built from HEAD's source: 210 byte-identical, 0 differing, 0 regressed; a second sweep of rejection fixtures' stderr: 113 byte-identical, 4 changed (all new G-3 fixtures). | **Done (2026-08-02)** |
| **Interlude** | The fn-pointer `defvar` regression, fixed. `(defvar g:(fn i32)(i32) null)` died `'g' already names a function`. **Confirmed a G-0 regression**: a compiler built from the pre-G-0 source at `05348b3` in a scratch worktree reaches a different, correct-shaped error and never the name-kind collision. Cause: `name-existing-kind` treated any global `Sym` with a `TY-FN` type as a function; G-0's `prescan-defvar-name` defines that `Sym` before `emit-defvar` runs, so the `defvar` collided with itself. Fixed with an `(= (sym is-local) 0)` conjunct — the same two-conjunct test `emit-dispatch` already used to tell a `defn` from a fn-pointer-typed value. **Two stacked defects, not one**: fixing the collision exposed `defvar-init-ir`'s `null` branch rejecting a function-pointer type via its `is-ptr-like` gate (which deliberately excludes `TY-FN`), needing a third by-name arm — `is-ptr-like` stays unwidened (widening it would make `(= some-fn-ptr some-cstr)` a `strcmp`), matching what W5d's `emit-zero-store` already does for the implicit zero of the same slot. **Does not re-open W6's hole**: `ptr-pkind` answers `PTR-RAW` for every non-`TY-PTR` kind, so a `TY-FN` destination can never be `PTR-REF`, and the wrapper spellings `ptr:(fn …)`/`(ref (fn …))` still reject `null`. Landed in the same commit as G-4 (`aa24eae`, "defvar ordering"), alongside `examples/fnptr-global.nuc` and two reject fixtures (`w8-fnptr-global-name-collision`, `w8-fnptr-null-still-gated`). Unblocked G-5, which needed both fn-pointer hooks among `compiler-init`'s 48 globals. **Three more defects found building the same example, none fixed, folded into the reconciled W9 list below as items 18-20**: `(= h null)` does not compile for a fn-pointer value (`emit-binop-vals`'s null-literal escape and pointer-comparison arm both gate on `is-ptr-like`); `type-size` has no `TY-FN` case, so a fn-pointer slot emits `align 1` (conservative, not a miscompile — `abi-alignof`/`abi-sizeof` are correct); `coerce-int-val` has no `raw`→`TY-FN` case, so `(let (f:(fn i32)(i32) null) …)` still dies though the global now accepts it. Tests 393 → 396. | **Done (2026-08-02)** |
| **G-4** | The ordering diagnostic. A `defvar` initializer that *syntactically* names a global whose `defvar` has not yet been reached is a located error naming both sites; a syntactic cycle falls out of the same check with its own wording. Mechanism: a `defvar-state` field on `Sym` (DECLARED at G-0's prescan, REACHED at emission) — G-0 already registers each name twice and `scope-lookup` scans backwards, so a lookup returns the prescan `Sym` before emission and the emission `Sym` after; the state a reference sees flips at exactly the right instant, for free. **A list of already-emitted `Sym*`s was rejected on a real hazard**: `scope-define` grows the global scope by `arena-alloc` + `memcpy` into a new array, so a captured pointer goes stale and identity membership would be silently wrong for any unit large enough to grow the scope — i.e. all of them; a field travels with the `memcpy` instead. **`(addr-of g)` is not a read** — a global's address is a link-time constant needing no initialization — and the exemption is load-bearing: of `compiler-init`'s 42 `set!` statements, 19 syntactically name `g-arena-alloc`, every one inside `(addr-of …)`; with the exemption, 0 rejections; without it, exactly 8, which are precisely the reorder sites §2.10 already knew about and nothing else. `quote` subtrees are skipped (their contents are data, not references); `quasiquote`'s `~b` unquote is a genuine read and is given up with the rest of its subtree — an admitted false negative, chosen because a false positive would reject a program that compiles today. **Found a live stale claim in `docs/toplevel.md`**, since fixed: it asserted `defvar` initializers "are constants, applied before any code runs, so no reordering can change one" — false the moment G-3 landed, and the exact opposite of the ordering rule this step documents. Tests 396 → 406; `make bootstrap` byte-identical on the first pass (the check only ever raises, writing to no IR stream); old-vs-new sweep: 216 byte-identical, 0 differing, 0 regressed IR; 335 of 338 stderr diagnostics byte-identical across both compilers' rejections, 3 changed (all new rejection fixtures). Landed in the same commit as the Interlude (`aa24eae`). | **Done (2026-08-02)** |
| **G-5** | `compiler-init` eliminated, then the flip. **This is acceptance criterion (A), the stage's headline goal.** `compiler-init` went from 52 statements to zero: 48 globals converted to combined declaration+initialization, 20 dead statements deleted, seven helper functions removed outright (`types-init`, `init-name-sets`, `init-binops`, `init-generics`, `init-blanket`, `init-rmacros`, `compiler-init` itself). **The single survivor is `(target-init)`**, called directly from `main` and `repl-main`, for the two reasons §2.12 predicted: it reads argv (which no load-time initializer can see) and derives five interdependent globals from one call. **The flip landed**: `(defvar g:ptr:T)` with no initializer is now a located error, so `ptr:T` means non-null at a global exactly as it does everywhere else — closing `nullability.md` §1.5's remaining half (acceptance criterion (B)). The **warn stage was built first as a measurement**: 54 sites, all in the compiler's own source, **zero** across `lib/`, `examples/` and `tests/fixtures/` (216 programs clean under the warning), so the flip cost no collateral edits anywhere outside `src/`. **The three lazily-built erasure registries (`g-vtable-table`, `g-boxedfn-table`, `g-dyn-table`) were ruled EAGER**, along with `g-nundo`'s two guards and the `g-include-paths`/`g-link-args` pair — `raw` would have made the nullable type permanent (every read site keeps a null test forever); eager costs three empty Vector headers and deletes eleven guard sites; for the argv-time pair it is a *repair*, not a trade, since they were silently libc-backed for their whole lifetime before `compiler-init` armed the allocator (`context/build.md`'s note about this split is now rewritten). `assert-compiler-arena-backed` runs on all 410 suite compiles, asserting both the constant handle's kind *and* `g-structs`' copied handle — the property that actually matters, since a Vector built before the constant took effect would stay libc-backed even once the global itself reads correctly. **Three premises measured false, all load-bearing**: (1) §2.10's reorder goes *downward*, not up — a constant struct literal needs `AllocHandle`'s layout, not imported until `~:640`, so moving `g-arena-alloc` above the registries at `:144` is impossible, and unnecessary since a constant initializer has no order; (2) a **second**, unpredicted reorder was needed — `build-generics` → `generic-alloc` → `ns-ir-prefix g-current-ns` → `strcmp` on a null pointer, laundered through two calls so G-4's syntactic check could not see it; the old `compiler-init`'s own comment knew about it and the census did not carry the comment forward; (3) the two late-binding hooks **cannot** be constants after all — a constant `@fn` resolves at the `defvar`'s own emission point, and the hooks exist precisely because their callee is in a later import, so the split is 1 constant + 47 runtime, not 3 + 45 as §2.12 A1 counted. **A prerequisite defect fixed at its root**: `as` did not arm the want channel — `emit-as` emitted its operand without setting `g-want-type`, so a return-only-tyvar generic in `as`-operand position (`scope-new`'s `(as (ref (Vector (ref Cleanup))) …)`) resolved against whichever `(Vector T)` instance the unit had stamped *first*; it read correctly for the compiler's whole life only because that call site happened to be first, and the migration's `build-deferror-sids` stamped `(Vector i32)` earlier, retargeting it immediately. **The `unsafe/cast` spelling of the same shape is completely silent** — no diagnostic at all. Bootstrap **deliberately moved and was reconverged**: the standard converge cycle could not run (its first `make` uses the committed `bin/nucleusc`, which predates G-1/G-3 and dies on the migrated source), so C0 (pre-G-5 HEAD) compiled the migrated source to C1, C1 compiled itself byte-identically (a fixed point independent of any committed artefact), then reconverged. Per-function diff: 1024 functions byte-identical, 22 changed (exactly those edited), 9 removed, 14 added, all named; 3 top-level lines removed, 7 added, all named. Sweep: 218 byte-identical, 0 differing, 0 regressed IR; **0** diagnostics changed across 122 rejecting programs. Tests 406 → **410 PASS / 0 FAIL**; `make abi-test`/`make layout-test`/`make avr-test` green. **One unrelated hole found in passing, not fixed here**: a `defvar` may be declared twice in one unit with no diagnostic (W9 item 16). | **Done (2026-08-02)** |

### Test/bootstrap status after G-0/G-1/G-2 *(superseded below — kept as the snapshot at that point)*

`make test` **385 PASS / 0 FAIL** (counted with `NUCLEUS_TEST_JOBS=1` — see W9
item 10 below), `make bootstrap` byte-identical (`PASS: stage1.ll ==
stage2.ll`) on the first pass, `make abi-test` and `make layout-test` green
(both extended with new array shapes). Full account, including every fixture
and the exact `file:line:` each inherited check pins:
[../global-init.md](../global-init.md)'s "G-0 as built", "G-1 as built" and
"G-2 as built" sections.

**Three items G-1 reported but did not fix, added to the W9 list below as
defects 7–9:**

1. A pre-existing soundness gap made visible, not introduced, by G-1:
   `pkind-flow-check` only diagnoses a `TY-PTR` source, so a `CStr` source
   flows into a non-null `(ref T)` unchecked, and `(defvar g:ptr:T (as CStr
   null))` compiles to a null in a non-null slot. The identical *local* is
   **equally** accepted, by this compiler and by the pre-G-1 boot — the
   renderer matches the chokepoint exactly, which is the G-1 contract; the
   carve-out itself is what is wrong, in both positions at once.
2. `emit-as`'s int→int rule ignores the literal value on the `Val`, so
   `(as i8 5)` is refused as lossy even though 5 fits — the same
   over-strictness [../stage14/int-widening.md](../stage14/int-widening.md)'s
   LW-4 fixed elsewhere. A ~3-line shared fix, **deliberately declined**,
   because it changes the value path and would have made G-1's bootstrap diff
   unprovable.
3. `(defvar g:i1 5)` emits `global i1 5`, which LLVM silently truncates to
   `true`, because `int-literal-fits` returns 1 at width ≤ 1. Pre-existing —
   the old boot emits the identical line for the bare literal — G-1 merely
   gives it a second spelling (`(+ 2 3)`).

**A fourth item, orthogonal to G-0/G-1 and found while re-verifying their test
counts, added below as defect 10**: `tests/run-tests.sh` spawns units in
parallel and their stdout can interleave, so a `PASS  <name>` line is
occasionally split across two lines. Measured: three consecutive runs of the
same tree all report 361, but earlier runs reported 346 vs 347 and 360 vs 361
for what was the same tree, and a bare `w1d` token appears alone on output line
314 in one capture. It does not affect FAIL detection (0 FAIL held every time),
but it makes any PASS *count* unreliable by ±1 and could in principle mask a
dropped unit.

**Two items G-2 reported but did not fix, added to the W9 list below as
defects 11–12** (this pair is also [../global-init.md](../global-init.md)
§7's own #7/#8, added there the same day):

1. Three `fmt-s` call sites pass **two** substitutions to a one-argument
   helper: `call: expected %d args, got %d` (~`nucleusc.nuc:4313`), `(dyn
   %s): '%s' is not a declared protocol` (~`:5824`), and `BoxedFn call:
   expected %d args, got %d` (~`:6310`). Exactly the fixed-arity trap
   [../../context/conventions.md](../../context/conventions.md) opens with —
   `snprintf` reads a garbage vararg and the compiler segfaults with no
   output — found by grepping after hitting the identical mistake fresh in
   new G-2 code, where it segfaulted immediately. These are cold diagnostic
   paths a green suite has never executed. Not fixed: the mechanical repair
   (`fmt-i32-i32`/`fmt-2s`) moves the compiler's own IR, so it belongs in a
   change that is already reconverging.
2. A wrong-arity call to a solitary `defn` is not diagnosed at all: `(f 1
   2)` against a one-parameter `(defn f (a:i32):i32 …)` compiles clean and
   emits `call i32 @f(i32 1, i32 2)`. Reproduces on `build/nucleusc` **and**
   the committed `bin/nucleusc`, so pre-existing. Very likely *why* item 1
   above has gone unnoticed — the `call: expected %d args, got %d` check
   exists but the solitary-`defn` path never reaches it. Notable because
   arity overloading is on the port's `NUCLEUS-FINDINGS.md` §7 "things that
   worked well" list: the *overloaded* call path checks arity, the solitary
   path does not.

**A third item, found closing out this stage record rather than by G-2
itself, added below as defect 13:** `parse-type-from-node`'s `die-at "unable
to parse type expression"` is a label-less trailing arm of `case (n kind)` —
reachable only for a `NodeKind` outside `{NODE-SYM, NODE-CELL}`. For an
unrecognized `NODE-CELL` head (e.g. `(nosuch i32)` as a field type) the
`NODE-CELL` arm's `do` block matches no known shape and falls through to a
null value instead of ever reaching that arm, so `(defstruct S (xs (nosuch
i32)))` reports the misleading `defstruct: field 'xs' missing :type` rather
than a diagnostic naming `nosuch`. Empirically confirmed against
`build/nucleusc`; pre-existing.

### Test/bootstrap status after G-3/Interlude/G-4/G-5 — final, W8 complete

**`make test` 410 PASS / 0 FAIL** (`NUCLEUS_TEST_JOBS=1`), climbing
385 → 393 (G-3) → 396 (Interlude) → 406 (G-4) → **410** (G-5). `make bootstrap`
reconverged and passing (G-5 deliberately moved the compiler's own IR — see its
row above for the fixed-point proof; G-3 and G-4 were each byte-identical on
the first pass). `make abi-test`, `make layout-test` and `make avr-test` (AVR:
8/8) all green. Full account, including every fixture and the exact
`file:line:` each check pins: [../global-init.md](../global-init.md)'s "G-3 as
built" through "G-5 as built" sections.

Confirmed independently at this closing pass: every remaining mention of
`compiler-init` in `src/` is a comment explaining its removal (`grep -n
compiler-init src/*.nuc` returns only comment lines), and the flip's
diagnostic is a located two-line message naming both the rule and the `raw`
escape hatch — reproduced by compiling `(defvar g:ptr:i32)` with
`build/nucleusc`.

---

## W9 — Reconciled at stage close: forty-seven defects found, **all forty-seven** now fixed, none open *(added 2026-08-01; extended through G-5's close 2026-08-02; items 21–24 added 2026-08-03; items 10 and 16 closed and item 22 measured closed 2026-08-09; items 1, 5 and 2 fixed 2026-08-09; items 3 and 4 fixed 2026-08-10, the latter adding items 25–28; item 6's string-path half fixed 2026-08-10, splitting its `.nuch` half out as item 29; item 7 fixed 2026-08-10; item 8 fixed 2026-08-10, splitting its float counterpart out as item 30; item 9 fixed 2026-08-10, filing the i1 signedness defect beside it as item 31; item 13 fixed 2026-08-10; item 15 fixed 2026-08-10, filing the index-signedness defect it measured as item 32; items 18 and 19 fixed 2026-08-10; item 20 fixed 2026-08-10, filing the two argument-position holes it measured as items 33 and 34; item 23's symbol half fixed 2026-08-10, splitting its dispatch half out as item 35; item 24 fixed 2026-08-10, filing the header-shadowing defect it measured as item 36; item 25 fixed 2026-08-10, closing the builtin-scalar spelling beside it and filing the two residual causes of its own named headers as items 37 and 38; item 26 fixed 2026-08-10, closing item 27 with the same cause and most of item 38 as a consequence; item 28 fixed 2026-08-10, filing the digit-leading-name defect it measured as item 39; item 29 fixed 2026-08-10, closing item 6's remaining half and filing the order-dependence it measured as SHARED by both spellings as item 40; item 30 fixed 2026-08-14, which supplied its own second asker — `defvar-init-ir`'s float `as` fold, newly reachable *because* the value path started accepting — and closed it in the same change; item 31 fixed 2026-08-14, the first W9 fix to move the bootstrap — one `TY-I1` arm, 24 `sext i1`→`zext i1` sites across the whole corpus and nothing else; item 32 fixed 2026-08-14, which did **not** move the bootstrap although it predicted it would — the compiler indexes exclusively with signed and `usize` values, so its own IR is byte-identical and the whole corpus moved by five lines; item 33 fixed 2026-08-14, whose five lines of diagnostic surfaced two defects that the silence had been hiding — the `(dyn P)` single-conformer bypass, fixed with it as item 41, and an unreachable `defcast` rule that an example had been documenting as working since it was written, filed as item 42; item 34 fixed 2026-08-14, its sibling two lines away in the same loop — the guard now compares TYPES rather than what they lower to and answers through `coerce-int-val`, so the argument position's refusal matrix matches `let`'s row for row, at 0 IR diffs corpus-wide; item 36 fixed 2026-08-14, whose discriminator is WHERE the declaration is written rather than what it says — `--emit-nuch` never re-exports a top-level `declare`, so a `.nuch` entry is never a forward declaration of the importing unit's own function, while W1e's cycle-breaker always is — and which measured the prefixed-import shadowing beside it as item 43; item 37 fixed 2026-08-14, whose ruling went neither of the two ways its own row proposed — the include set is the DEFINING unit of each type the header actually names, by the path convention the Makefile already promises — and which measured the `!T` return-type spelling beside it as item 44; item 44 fixed 2026-08-14, whose recommended ruling survived but on a **different** justification than its row gave — probing showed the payload is a genuine `{i32 tag; union}` a correct C declaration reads fine, so the defect is not "no C spelling exists" but that `!T` is a `(Result T Err)` template instance, which the emitter already declines to export under its spelled-out form, so the fix makes the two spellings of one type agree; items 43 and 35 fixed 2026-08-14 together, being one ruling and one audit — B4's deferred §9.6 bare-reference audit came back clean at every `Method.src-ns` writer, so the filter itself was small and the real work was one layer down: a monomorphized template body was resolved in the CALLER's import environment, which `b4-qualified-template` had been surviving only because its callee happened to be overloaded; item 39 fixed 2026-08-14, which took NEITHER of the two answers its row proposed — the codebase already answers this question, by mangling (`?`→`_QMARK` since SM-1), so a leading digit is mangled too — and whose real scope was the discovery that the transform was applied only at the GLOBAL-symbol layer, leaving `?`/`!` in a parameter, a `let` binding, a `match` binder or a `label` emitting raw and dying the same unattributable way, live rather than latent; item 38 fixed 2026-08-14, whose row called the cause "structural rather than one missing check" and was right, but the structure is one layer up from where it looked: the header modes run the compiler's PRESCAN layer and never its EMISSION layer, and every prescan deliberately defers its diagnosis to emission — so the three crashes and the unresolvable-import residue are one defect with one cause, closed by asking the deferred questions once, from the chokepoints that own their messages, before any output; item 45 fixed 2026-08-14, whose row was right that a segfault is the worst diagnosis of a syntax error and wrong about almost everything else — it is twenty-three shapes rather than four, three of the four crash in a PRESCAN rather than at the chokepoint the row named, and the fix is not a diagnostic at all but a null-safe `node-kind`, because every position already owned the message its own kind test was crashing before it could raise; item 40 fixed 2026-08-15, whose three named kinds turned out to be one hoistable registration, one already-hoisted signature and one thing that is not a registration at all — a struct's field table moves into the prescans by splitting `emit-defstruct` at the line where it starts writing IR, a `defunion` arm CONSTRUCTOR was already reachable below its import (its signature rides `prescan-union-ctors`) and what was missing was the `UnionDef` behind `make`/`match`, and a `defmacro` is a COMPILED function whose registration is its emission, so it is ruled to stay where the emitter is; the fix also closed the non-cycle half of the same defect that `conventions.md` had carried as "latent, still unfixed" since W1d — `(defn f (v:S) …)` textually above `(defstruct S …)` in ONE file emitted `define i32 @f(i0 %v.arg)` — and retired three W1d cycle-pinning tests in favour of positive ones, leaving two residues measured and recorded: an `(array T N)` extent that only a macro can fold, and the `.nuch` spelling of a `defunion`, whose registry key mismatch is filed as item 46; item 42 ruled and closed 2026-08-15, whose recommended answer ("no, implicit conversions do not compose") survived measurement and turned out to already be what the compiler does in all five positions — so the ruling cost no code, and the item's substance was somewhere else entirely: measuring WHERE a rule is consulted showed the registry had two customers out of nine, refusing a rule on its own exact registered pair at `let`/`with` init, both returns, `.set!`, `aset!`, struct-literal fields and union payloads, filed and fixed with it as item 47, plus a near-miss note that makes the ruling distinguishable from the rule never having been registered; item 46 fixed 2026-08-15, the last open item and the cheapest — the registry takes the canonical KEY and `union-ctor-form` takes the SOURCE spelling, a split `emit-defunion` had documented in a comment and `emit-defunion-import` had never honoured, so two `qualify-name` calls closed the type half and the arm constructors needed nothing at all; the follow-on its row predicted then held to the line, item 40's `.nuch` layout residue closing in three lines plus a `ctors-emitted` guard once the two paths agreed on the key. **Item 23's "in part" was retired the same day as stale bookkeeping rather than fixed** — its dispatch half had been split out as item 35 and fixed 2026-08-14, and re-probing confirms two namespaces may each define `describe (x:i32):i32`, that each emits its own symbol, and that a bare call reports ambiguity naming both candidates and their definition sites)*

**The original six are enumerated in [../global-init.md](../global-init.md)
§7. Four more (7–10) were found measuring G-1 and re-verifying G-0/G-1's test
counts, and are recorded here only — they postdate §7's list and are not
folded back into `global-init.md`. Two more (11–12) were found building G-2
and correspond to `global-init.md` §7's own additions #7 and #8** (a matched
pair added there the same day — that numbering is independent of this
table's, since the four G-1-era items above were never folded back into §7
either). **A thirteenth defect was found while closing out the G-0/G-1/G-2
stage record and is recorded here only.** Items 1–13 below are unchanged from
that pass.

**Reconciliation, done at this closing pass.** `global-init.md` §7 kept
growing after item 13 was recorded here: building **G-3** added its own
items #9 (a function-pointer-typed `defvar` could not be declared at all)
and #10 (`aref`'s hardcoded `i64` GEP index), and building **G-5** added its
own #11 (a `defvar` may be declared twice with no diagnostic) and #12 (`as`
did not arm the want channel) — none of which had been folded into this
table. Cross-checking the two lists against each other, plus three more
defects that were never filed in *either* list — documented only inline in
`examples/fnptr-global.nuc`'s comments, found alongside the fn-pointer
interlude and G-4 — gives a union of **twenty** unique items. **Four were fixed
as of that pass** (see the 2026-08-03 extension below for items 21–23): the
fn-pointer `defvar` collision (§7 #9, fixed in the interlude
between G-3 and G-4), the `as` want-channel gap (§7 #12, fixed in G-5), and —
on 2026-08-02, as the matched pair they were filed as — **items 11 and 12**,
the format-helper arity violations and the missing solitary-`defn` call-arity
check. That pass corrected two of the recorded premises (there were **seven**
format violations, not three, and only two of them segfault — the other two
printed a garbage *count*) and **disproved the recorded causal link between
the two items**: defect 11's first site lives on the fn-pointer indirect call
path, which defect 12 does not touch, so it was reachable all along.
The reconciled **open** count after that pass was **sixteen**. Items 14–20
below are that reconciliation: 14/15/16/17 map onto `global-init.md` §7's
#9/#10/#11/#12; 18/19/20 are the three that were never filed anywhere but this
table.

**Extension, 2026-08-03 — items 21–24, and the pattern they illustrate.**
Item 11's fix left behind a fixture (`w9-dyn-not-protocol`) that reached its
diagnostic only by *exploiting* an unrelated bug, and its own header said so
and said what to do if that bug were ever fixed. Fixing it is **item 21**
(`(dyn ns/Proto)` unusable across a namespace, a protocol/conformance key
mismatch dating to Stage 12 N4), settled by a user ruling that protocols are
namespaced entities. Building it surfaced **three more pre-existing defects,
none fixed**: a file with an explicit `(ns …)` cannot box a value at all
(item 22), two namespaces defining the same function name collapse into one
generic (item 23), and `(dyn P)` cannot box a type whose implementation
arrives through a `.nuch` `declare` (item 24, which is not namespace-specific
at all — it reproduces in `user`). Items 21–23 are the *same underlying shape*:
Stage 12 namespaced some registries (`g-globals`) and not others (`g-generics`,
and until now `g-protocols`), so each un-namespaced registry is a latent
cross-namespace defect — which is the useful generalization to carry forward.
Item 24 is the sibling asymmetry rather than the namespace one: **two**
registries answer a name (`g-globals` and `g-generics`), and any path that
consults only one of them has a hole wherever the other is the sole registrar.
Total **twenty-four**, of which **twelve** are fixed (items 1, 2, 3, 5, 10, 11,
12, 14, 16, 17, 21, 22) and **twelve** open.

> **Re-measured 2026-08-09, at the close of the B series.** The counts above
> drifted three times because items were closed by *other* work and the table was
> not re-read. Every open item was re-probed against the current compiler:
> 3, 4, 5, 7, 8, 9, 13, 15, 18, 19, 20, 23 and 24 all still reproduce, verbatim.
> **Item 22 is closed** — not by anyone working on it, but by B2b's `user`
> fallback in `globals-lookup-ref`, which is exactly the missing "bare fallback"
> the item names. **Item 23's symptom changed** and its status did not; see its
> row. Items 1 and 2 were confirmed still broken while running `make lib-objs`
> during B4, and both were **fixed later that day** (see their notes below).
> The lesson is the one the drift itself demonstrates: a defect table
> maintained by hand goes stale silently, and re-probing costs minutes. All are pre-existing and independent of W1–W7; all were
hit while measuring, verifying, or documenting, not synthesized.

| # | Defect | Note |
|---|---|---|
| 1 | **`make lib-objs` / `make lib-headers` / `make lib-cheaders` broken — FIXED 2026-08-09** | `lib/arena.nuc` and `lib/node.nuc` died `duplicate definition of 'arena-init' / 'alloc-node'`; `lib/reader.nuc` died `undefined: stderr`; nine files died under `--emit-nuch`. See the W9-1 note below for the cause, which the recorded hypothesis had half right. **`make lib-so` closed with item 2, the same day** |
| 2 | **Two separately compiled Nucleus objects cannot be linked — FIXED 2026-08-09** | each inlines the whole prelude, so `build/lib/vector.o` and `build/lib/hashmap.o` share duplicate public definitions (`@g-arena`, `@g-intern-table`, `arena-init`, `next.pIntRangeIter`, …) and `ld` refuses. `exclude-prelude` works; a non-freestanding library was unlinkable. **Fixed by giving a definition the unit only carries a COPY of `weak_odr` linkage** — see the W9-2 note below. `make lib-so` is green |
| 3 | **`--emit-cheader` does not export globals — FIXED 2026-08-10** | a `defvar` reached the `.nuch` as `(extern …)` but got no `extern T name;` line in the C header, so a C consumer could reach a library's functions and none of its state. `emit-cheader-header`'s dispatch had no `defvar` arm at all — while **both** `docs/compiler.md`'s flag table and `docs/toplevel.md` already documented the behaviour as present. See the W9-3 note below; the fix turns on the NAME, not the missing arm |
| 4 | **`--emit-cheader` emits hyphenated, invalid C identifiers — FIXED 2026-08-10** | every name a header exports was emitted verbatim except the struct/union *type* name, so fields, parameters, `defunion` arms, enum tags, `#define`s and prototypes were all invalid C. Measured: **13 of the 34 committed `lib/*.h` parsed** under `clang -fsyntax-only`; now **27**. See the W9-4 note below — the recorded cause ("a missed call site") is wrong for the two kinds the linker resolves, and four *other* causes of an unparseable header were measured and filed as items 25–28 |
| 5 | **`(exclude-prelude)` in an *imported* file dies `unknown top-level form` — FIXED 2026-08-09, as a prerequisite of item 1** | rather than being ignored or diagnosed as "must be the first form of the unit". `strip-exclude-prelude` is consulted only for the entry file. Item 1's root hoist **re-reads the root file**, so a root that opts out of the prelude reached this the moment the hoist fired — the directive belongs to the unit, not the file, and `emit-toplevel-forms`' dispatch now ignores it (the ruling the item's own note preferred). This is the only shape that made the fix mandatory rather than merely nice; a hand-written `(exclude-prelude)` library import hit it too |
| 6 | **`undefined: X — not defined anywhere in this compilation unit`** for a name that *is* in the unit, merely unprocessed — **FULLY FIXED 2026-08-10** | **overlaps W8's G-0; not filed twice.** G-0 closed the cause for the two import shapes it covers (plain and `import-use` symbol imports). Of the residue it named, **string-path `.nuc` imports closed first** — both prescan passes looked at `NODE-SYM` only, so `(import-use "lib/foo.nuc")` and `(import-use foo)` named the same file and resolved differently; see the W9-6 note below. The `.nuch` half was filed with a cause as **item 29** and fixed the same day, so every import shape now resolves on reachability |
| 7 | **`pkind-flow-check`'s `CStr` carve-out accepts a null through a non-null `(ref T)` — FIXED 2026-08-10**, found measuring G-1 | only diagnoses a `TY-PTR` source, so `(defvar g:ptr:T (as CStr null))` compiles to a null in a non-null slot — and so does the identical *local*, by this compiler and the pre-G-1 boot alike; the renderer matches the chokepoint exactly, so the carve-out itself is what is wrong, in both positions at once. **Confirmed by segfault** in both positions and in the realistic `getenv` shape. Fixed at the two sites that each carried the premise (`pkind-flow-check`, `as-ptr-convert`); see the W9-7 note below |
| 8 | **`emit-as`'s int→int rule ignores the literal value on the `Val` — FIXED 2026-08-10**, found measuring G-1 | `(as i8 5)` was refused as lossy even though 5 fits — the same over-strictness [../stage14/int-widening.md](../stage14/int-widening.md)'s LW-4 fixed elsewhere; a ~3-line shared fix, declined at the time because it would have made G-1's bootstrap diff unprovable. The recorded shape was right: the rule is one function with two askers, and both now pass their literal knowledge to it. See the W9-8 note below — the estimate held (3 lines of logic), and the reason it is worth fixing is sharper than "over-strict": the *safe* cast was stricter than the *implicit* coercion it exists to make explicit. Filed the float counterpart it does not close as **item 30** |
| 9 | **`(defvar g:i1 5)` emits `global i1 5`, silently truncated to `true` by LLVM — FIXED 2026-08-10**, found measuring G-1 | `int-literal-fits` returns 1 at width ≤ 1; pre-existing — the old boot emits the identical line for the bare literal — G-1 merely gives it a second spelling. The recorded cause was exact, and the recorded *scope* was not: the predicate is shared, so the identical hole sat at every `coerce-int-val` position too, and item 8 had just given it a third caller. See the W9-9 note below. Filed the i1 **signedness** defect the fixture work uncovered as **item 31** |
| 10 | ~~**`tests/run-tests.sh` PASS counts are unreliable by ±1**~~ — **closed 2026-08-09, and it was already closed when this item was written** | parallel unit stdout can interleave, splitting a `PASS  <name>` line across two lines — measured: three consecutive runs of the same tree all reported 361, but earlier runs reported 346 vs 347 and 360 vs 361 for what was the same tree, and a bare `w1d` token appeared alone on output line 314 in one capture; does not affect FAIL detection (0 FAIL held every time) but could in principle mask a dropped unit. **Correction.** Interleaving is impossible by construction: `spawn` (`tests/run-tests.sh`) redirects each unit's *entire* stdout+stderr into its own `$RESULTS_DIR/<id>.out` and the files are replayed in dispatch order after the join, so one unit's output cannot split another's line. That buffering landed in `cb864fa` (2026-07-05, "Parallelize tests") — **a month before this item was recorded on 2026-08-02** — so the ±1 evidence above was gathered against the pre-buffering harness and the item was never re-verified against the current one. Re-measured 2026-08-09 on the 16-core host: three consecutive parallel runs and one serial run of the same tree all report **463 PASS / 0 FAIL**, 35–38 s parallel vs 144 s serial (**4×**, not `build.md`'s stated 7×). The mechanism is the argument, not the sample size — this item's own note records three agreeing runs while the bug was believed live. **Consequence:** `NUCLEUS_TEST_JOBS=1` is no longer needed to count, and the convention of recording every verification with it — followed by every entry in this document from G-2 onward — is cargo. Use the parallel default |
| 11 | **Format-helper arity violations — FIXED 2026-08-02**, found building G-2 | **There were SEVEN, not three.** The recorded three were found by grepping `fmt-s` alone; sweeping *every* helper against its own parameter count found four more. Two directions, two failure modes. **Over-supplied** (format has more conversions than the helper feeds — the [conventions.md](../../context/conventions.md) trap): `call: expected %d args, got %d` (`nucleusc.nuc`), `BoxedFn call: expected %d args, got %d`, `(dyn %s): '%s' is not a declared protocol`, and a **fourth the record did not have** — `extend: '%s' is a protocol, so its supertype '%s' must be a protocol too` (`generics.nuc`). **Under-supplied** (fewer arguments than the helper has parameters, so it read an uninitialized register): `(fmt-sd "%%tc3.mat.%d" g-tmp)` and two `(fmt-2s "ptr %s" x)` in `abi.nuc`. **The recorded symptom is only half right, and the half it gets wrong is load-bearing**: only the two `%s %s` sites segfault (the garbage vararg is dereferenced as a pointer — both confirmed SIGSEGV with no output on the committed `bin/nucleusc`). The two `%d %d` sites do **not** crash — they print a garbage COUNT (`expected 2 args, got 100`; `expected 1 args, got 115`), a *silently misleading diagnostic*, which is worse for a user than a crash. **That also falsifies the recorded link to defect 12**: `call: expected %d args, got %d` lives in `emit-funcall-value`, the fn-pointer *indirect* call path, and has always been reachable — it was firing with a garbage number, not failing to fire. Each of the four diagnostics now has a test that would have crashed or misprinted before the fix (`tests/fixtures/w9-fnptr-arity`, `-boxedfn-arity`, `-dyn-not-protocol`, `-extend-super-not-protocol`); a corrected format string nothing executes is one edit away from regressing. All seven would also have been caught by defect 12's new check — every one is a wrong-arity call to a solitary `defn` |
| 12 | **A wrong-arity call to a solitary `defn` is not diagnosed — FIXED 2026-08-02**, found building G-2 | `(f 1 2)` against a one-parameter `f` emitted `call i32 @f(i32 1, i32 2)`, linked and ran. **The mechanism, precisely**: `emit-dispatch` (`nucleusc.nuc`) routes an overloaded name to `emit-generic-call`, where `generic-resolve` only matches a method at `num-params == nargs`, so a wrong count falls out as *no matching method*; a solitary name goes to `emit-call` → `emit-call-with-args`, which resolves the callee **by name** and never compared the counts at all. Fixed with the [conventions.md](../../context/conventions.md) shape — **one rule function both sides CALL**, not a second copy: `call-arity-ok` / `check-call-arity` (`nucleusc.nuc`, above `emit-funcall-value`) now serve the direct path, the fn-pointer indirect path and the BoxedFn/`dyn` box path, and `emit-call`'s own `&optional` `too few args`/`too many args` pair — which re-derived the band — was deleted rather than left beside it. The rule must NOT gate on `kind == TY-FN`: a box carries its signature on a **TY-STRUCT** Type (`boxedfn-type`), so a kind gate would have silently stopped checking that path. **Rulings on the variable-arity shapes**: `&optional` is a band (`num-params - nopt` … `num-params`), `&rest` is a floor (`num-params - 1`), a C-header `variadic` signature is a floor at its fixed prefix, an overloaded/multimethod/protocol/generic call is untouched (resolution already diagnoses it), and **too few arguments is an error in every shape**. **One carve-out, and it is load-bearing**: a hand-written `declare` is *open-tailed* — Nucleus has no `...` spelling and `&rest` is refused in a declaration, so the documented way to call a C variadic is to declare its fixed parameters and let the extras ride the call site, and **three existing tests already depend on exactly that** (`n6-nuch-link-and-run`, `sm3-import-resolves-mangled`, `s1-nuch-link-and-run`, each writing `(declare printf (fmt:CStr):i32)` and calling it with 3–6 arguments). Carried as `Sym.extern-decl`, set only in `emit-nuch-declare-import`, and **appended at the END of `Sym`** so no existing field's GEP index shifts and the bootstrap diff stays readable. **The check found TWO latent wrong-arity calls in the compiler's own source**, both silent reads of an uninitialized register: `generic-resolve-nullable` called `generic-method-bind` with 5 of its 6 arguments (the callee then read a garbage `arg-nodes` array), and `fn-rewrite-captures`' `.set!` branch built its OUTER `make-cell` without its `line` (every sibling passes it), so a rewritten closure-capture store carried a garbage source line. Zero elsewhere in `lib/`, `examples/` or `tests/fixtures/` — measured with a **warn-only compiler in a scratch worktree**, not by first-error iteration. Tests 410 → **421 PASS / 0 FAIL**; `make bootstrap` **byte-identical on the first pass** (no reconverge needed — the change alters no emitted IR); per-function normalized diff of `build/nucleusc.ll` against a compiler built from HEAD's source: 1050 byte-identical, 10 changed (exactly the ten edited), 0 removed, 2 added (`call-arity-ok`, `check-call-arity`); sweep: 218 byte-identical IR / 0 differing / 0 regressed, plus 123 rejecting programs with 0 diagnostics changed; `make abi-test`/`make layout-test`/`make avr-test` green |
| 13 | **`parse-type-from-node` silently returns null for an unknown cell head — FIXED 2026-08-10** | its `die-at "unable to parse type expression"` is a label-less trailing arm of `case (n kind)`, reachable only for a `NodeKind` outside `{NODE-SYM, NODE-CELL}`; for an unrecognized `NODE-CELL` head (e.g. `(nosuch i32)`) the `NODE-CELL` arm's `do` block matches no shape and falls through to null instead, so `(defstruct S (xs (nosuch i32)))` reports the misleading `defstruct: field 'xs' missing :type` rather than a diagnostic naming `nosuch`. Empirically confirmed against `build/nucleusc`; pre-existing. **The recorded diagnosis was exact and understated the blast radius twice over**: five caller positions shared the null, the everyday trigger is a forgotten `import-use` rather than a typo, and a second mistake class (a doubled annotation) reaches the same fall-through and needs a *different* message. See the W9-13 note below |
| 14 | **Fn-pointer-typed `defvar` could not be declared at all — FIXED 2026-08-02**, found building G-3 | `(defvar g:(fn i32)(i32) null)` died `'g' already names a function`, a G-0 regression in `name-existing-kind` (it classified any `TY-FN`-typed global `Sym` as a function, and G-0's prescan defines that `Sym` before `emit-defvar` runs). Fixed in the interlude between G-3 and G-4 (commit `aa24eae`) with an `(= (sym is-local) 0)` conjunct, the same two-conjunct test `emit-dispatch` already used. `global-init.md` §7 #9 |
| 15 | **`aref` emits a hardcoded `i64` GEP index on every target — FIXED 2026-08-10**, found building G-3 | On AVR (16-bit pointers) a narrower index produces IR the LLVM parser rejects (`'%t3' defined with type 'i32' but expected 'i64'`); does not route through `ptr-int-ir` (AVR-2's fix for exactly this class). Not array-specific — a plain `ptr:ui8` with an `i32` index reproduces it. Reproduces on the committed boot. `global-init.md` §7 #10. **The recorded diagnosis was exact, including the pointer at AVR-2 — and the reason the rule was not already shared is the finding**: AVR-1 had written it correctly *in `emit-ptr-add` only*, leaving `aref` and `aset!` holding their own broken copies. See the W9-15 note below. Filed the index **signedness** defect it measured as **item 32** |
| 16 | **A `defvar` may be declared twice in one unit with no diagnostic**, found in G-5 — **FIXED in B4 (2026-08-09)** | Emitted two `@g = global …` lines that the LLVM parser rejects with an unlocated error far from the cause. `guard-name-kind` compares NK-VALUE against NK-VALUE, finds them equal, and permits it — the same-kind allowance that exists for overloaded `defn` and REPL redefinition, applied where neither justification holds. The diagnosis was right and the scope was narrower than the defect: **every** non-function definer accepted a redefinition silently, with no agreed winner (a second `defstruct`/`defunion`/`defprotocol`/`defmacro`/template kept the FIRST, a second `defconst` kept the SECOND). R4's rule covers all of them; `emit-defvar` reads `Sym.defvar-state` (the same-kind question cannot be posed to the binding table — see name-resolution.md §9.6), and the two justifications the item names are preserved exactly: overloads still collide only on signature, and the REPL is exempt. `global-init.md` §7 #11 |
| 17 | **`as` did not arm the want channel — FIXED in G-5**, found in G-5 | `emit-as` emitted its operand without setting `g-want-type`, so a return-only-tyvar generic in `as`-operand position resolved against whichever instance the unit had stamped first; silent in the `unsafe/cast` spelling, which takes the wrong instance with no diagnostic at all. Proven inert for the whole tree by G-5's old-vs-new sweep (218 byte-identical, 0 differing). `global-init.md` §7 #12 |
| 18 | **`(= h null)` on a function-pointer value does not compile — FIXED 2026-08-10**, found alongside the Interlude/G-4 | `emit-binop-vals`'s null-literal escape and its pointer-comparison arm both gate on `is-ptr-like`, which deliberately excludes `TY-FN`, so the comparison falls through to the numeric path and dies `= expects integer operands`. Pre-existing and general — reproduces identically for a fn-pointer *parameter* or *local*, not just the new global spelling; the explicit `(unsafe/cast ptr h)` reinterpret is the escape hatch. Documented inline in `examples/fnptr-global.nuc`'s header comment (`hook-unset`) before this reconciliation; not previously in either defect list. **The diagnosis was exact and the missing piece was that the convention itself was the defect generator**: `conventions.md` prescribed writing the `is-ptr-like`-plus-`TY-FN` arm out by hand at each site, three sites had done so, and these two never got their copy. See the W9-18 note below |
| 19 | **`type-size` has no `TY-FN` case — FIXED 2026-08-10**, found alongside the Interlude/G-4 | Fell through to the default `(return 1)` arm, so every fn-pointer slot emitted `align 1`. Recorded as "conservative, not a miscompile" — true, and it also cost roughly 7–20× on every fn-pointer load on a strict-alignment target, which the note had not measured (see the W9-19 note below). Fixed by asking `is-ptr-repr` instead of listing `TY-PTR`/`TY-CSTR` as arms and forgetting `TY-FN`; `abi-alignof`/`abi-sizeof` lost their own hand-written copies and fall through to it. Not previously in either defect list |
| 20 | **`coerce-int-val` has no case for `null` → `TY-FN` — FIXED 2026-08-10**, found in G-5 | Filed as `let`-only; it was in fact every position that funnels through the coercion chokepoint — `let`/`with` init, `set!`, a `.set!` field store and an explicit `return` — while `defvar` worked (its own constant-initializer path, given a TY-FN arm by item 14). Fixed with a third literal flag on `Val` (`is-nlit`), because `null` carries the **same type singleton** as a `raw` binding, so no type-directed rule can admit the literal without also making every data pointer callable. The unsafe escape hatch is spellable: `(unsafe/cast ((fn i32)(i32)) p)`. Filing items 33 and 34, which are why the item looked half-working |
| 21 | **`(dyn ns/Proto)` is unusable across a namespace — FIXED 2026-08-03**, found building the defect-11 fixture | `conformance-add`/`-lookup`/`-args` canonicalized their keys with `strip-ns-qualifier` (Stage 12 N4 decision 9) while `protocol-lookup` matched the **raw** spelling, so `(extend Cat dp/Describe)` recorded the conformance under bare `Describe`, `admit-erased-conformance` found it and admitted the box, and `dyn-vtable-method-irname` then reported *"'dp/Describe' is not a declared protocol"* for a protocol that was both declared and conformed to. **The user's ruling picks the direction**: the two registries agree by making conformances keep the qualifier — a protocol is a namespaced entity — **not** by making `protocol-lookup` strip too, which would have made protocol names effectively global. **The crux is that decision 9's strip covered two different questions and only one of them was about types.** Of the nine `strip-ns-qualifier` sites, five are the TYPE half and are **unchanged** (`conformance-lookup`/`-args`/`-add`'s first argument, `verify-conformance-params`'s `typename`, `emit-extend`'s subject and its `(extend (Vector T) …)` template head, plus `union-registry.nuc:289`'s `lookup-struct`) — a qualified type reference still resolves to the same `StructDef` from any namespace, which is decision 9's actual claim. Four are the PROTOCOL half and now resolve through the namespaced registry instead (`conformance-*`'s second argument, `proto-super-add`'s **both** arguments, `verify-conformance-params`'s `proto-name`, `emit-extend`'s protocol). **`emit-extend`'s subject is both**: `(extend Describe Show)` puts a protocol in the type position, so the inheritance branch now resolves the raw spelling through `protocol-lookup` while `typename` keeps the type strip. Mechanism: `protocol-new` keys on `qualify-name` (identity under `user`); `protocol-lookup` probes qualified-then-bare (the same shape as W5e's private-name probe — the bare fallback is what lets a namespaced file still see `Clone`/`Eq`/`Ord`); registration uses an **exact** probe (`protocol-lookup-exact`) for the reason `generic-register-method` does, or `(ns dp) (defprotocol Clone …)` would fold into the prelude's; and one canonicalizer, `protocol-canon-name`, is what every protocol-keyed registry calls. It is placed in `nucleusc.nuc` rather than beside `protocol-lookup` because `union-registry.nuc` — imported *before* `generics.nuc` — needs it: **`dyn-type` must memoize on the canonical name**, or `(dyn Describe)` inside `(ns dp)` and `(dyn dp/Describe)` outside it would build two `StructDef`s and `type-eq` would call one protocol two incompatible types. `&where` constraint names are canonicalized where they are **written** (`parse-where-constraints`), not at each lookup, because a constraint is checked long afterwards under a different `g-current-ns`. **A second, smaller defect surfaced and is fixed with it**: once the two registries agreed, the "is not a declared protocol" message became unreachable — `emit-box-value` asks about *conformance* first, so `(dyn Nope)` reported the misleading `type 'Cat' does not conform to the protocol`. Both askers now CALL one `dyn-require-protocol`, and box construction asks existence first. `tests/fixtures/w9-dyn-not-protocol.nuc` was **re-pointed, not deleted**, exactly as its own header instructed: its `extend` now succeeds (it is the fix) and the `dyn` names an undeclared `dp/Missing`. **Census: no existing program changes** — every `defprotocol` in `src/`, `lib/`, `examples/` and `tests/` is in `user`, where `qualify-name` is the identity. `examples/w9-dyn-ns.nuc` links and runs, asserting the dispatched results `105/207/309`: a qualified reference under a *different* import prefix, a bare reference inside its own namespace, and two namespaces each declaring a `Describe` with one type conforming to both. Tests 421 → **424 PASS / 0 FAIL**; `make bootstrap` **byte-identical on the first pass** (predicted: protocol *method* ir-names come from `Generic.ir-prefix`, which this does not touch); sweep against a compiler built from HEAD's source: **223 byte-identical IR, 0 differing**, and across 133 rejecting programs **0 pre-existing diagnostics moved** — the one REGRESSED and one NEWLY-COMPILES entry are the new fixtures, and the REGRESSED one is the collision the ruling exists to create (the old compiler silently accepted a bare `Describe` with two in scope). `make abi-test`/`make layout-test`/`make avr-test` green. **Three unrelated pre-existing defects found in passing, none fixed — filed as items 22, 23 and 24** |
| 22 | **A file with an explicit `(ns …)` cannot box a value at all**, found building item 21 — **FIXED, measured 2026-08-09** (closed by B2b, not by work on this item) | `emit-box-struct-move` gates on `(scope-lookup scope "default-allocator")`, and `scope-lookup` qualifies a *global* key against `g-current-ns` with **no bare fallback** — so inside `(ns dp)` it probes `dp/default-allocator`, misses, and dies `type-erasure: boxing a value requires (import-use allocator)` however many times the file imports it. Confirmed identical on the committed pre-fix compiler, so it is pre-existing and orthogonal to item 21 (which is why `examples/w9-dyn-ns.nuc` boxes in the consumer, not in the library). The general shape is broader than boxing: any compiler site that resolves a *known* global by name through `scope-lookup` is namespace-sensitive in a way its author did not intend. Note `generic-lookup` is unaffected — it keys on the raw name — which is why ordinary cross-namespace *calls* work and hides how narrow the working path is  **Closed by B2b's cut-over of `g-globals` to the canonicaliser:** `globals-lookup-ref` probes the current namespace's key, then each flattened namespace, then **`user`** — and that last probe is precisely the "bare fallback" this item says is missing. Re-measured: a `(ns …)` library that constructs a `(dyn P)` box compiles, links and runs. |
| 23 | **Two namespaces defining the same function name collapse into one generic — FULLY CLOSED; symbol half FIXED 2026-08-10, dispatch half FIXED 2026-08-14 as item 35**, found building item 21 | `generic-lookup`/`generic-register-method` key on the **raw** name (unlike `scope-define`, which qualifies), so `(ns qa) (defn describe …)` and `(ns qb) (defn describe …)` become one `Generic` named `describe` with two methods — mangled under whichever namespace was seen *first*, emitting `@qa__describe` and `@qa__describe.pDog` for a method defined in `qb`. Confirmed identical on the committed pre-fix compiler. Whether the fix is to namespace the generic registry or to keep it raw and namespace only the mangling is a real design question, not a typo; item 21 deliberately did not touch it, and `lib/nsdescribe2.nuc` names its protocol method `tag-of` rather than `describe` specifically to keep the two concerns separate in the tests  **Re-measured 2026-08-09: the symptom changed, the defect did not.** B4 gave generics a qualified spelling by *filtering* on `Method.src-ns` (R2 keeps one `Generic` per bare name with methods merged), so two namespaces whose `describe`s have **different** signatures now coexist and `qa/describe` / `qb/describe` each reach their own. Two with the **same** signature no longer collapse silently — they are a located `duplicate definition` error naming both files. **Fixed 2026-08-10, the second way: keep the registry raw and namespace the mangling.** The item's own evidence is the symbol, and it was worse than recorded — not only the prefix but the `.tok` suffix was read off the merged generic, so a namespace's exported symbol depended on what else the compilation unit contained *and* on import order. Measured end to end: a `(ns qb)` library that merely imports a `(ns qa)` one defining the same bare name emitted `@qb__describe.i64` for its own function and `@qb__describe.i32` for **qa's**, while its `.nuch` and C header both declared `@qb__describe` — `undefined reference to 'qb__describe'` at link. `method-ir-prefix` + a per-prefix user-method count move both decisions to the method; `Generic.mangled` keeps its other meaning (dispatch through the registry), the split `fn-force-generic-mangled` already relied on. A namespace's symbols are now identical compiled alone or together, in either order. See the note below and `run_w9_ns_symbol_ownership`. **The dispatch half is split out as item 35** — two namespaces still cannot each define `describe (x:i32):i32`, and that is R4/R2, not mangling. **Item 35 fixed 2026-08-14, which closes this row too; the "in part" qualifier it carried until 2026-08-15 was stale bookkeeping, not remaining work.** Re-probed at item 46's close: two namespaces each defining `describe (x:i32):i32` compile and run, `qa/describe` and `qb/describe` each reach their own, the pair emits `@qa__describe` and `@qb__describe`, and a *bare* `(describe 10)` is refused at the ambiguous use — `ambiguous call to 'describe' — two namespaces define it for these argument types`, with a note naming both candidates and their definition sites, which is R2 §8.2's original recommendation and exactly what item 35 adopted. |
| 24 | **`(dyn P)` cannot box a type whose implementation arrives through a `.nuch` `declare` — FIXED 2026-08-10**, found verifying item 21 | `dyn-vtable-method-irname` resolves the protocol method with `generic-lookup`, but `emit-nuch-declare-import` registers a solitary imported function as a **`Sym` in `g-globals` only** — it never creates a `Generic` — so the box site dies `(dyn Describe): no method 'describe' is defined` for a method that is declared, defined and linkable. Confirmed identical in the `user` namespace and on the committed pre-fix compiler, so it is pre-existing and orthogonal to item 21 (which the same probe *passes*: the protocol resolves, and the failure is one check later). Note the `.nuch` round-trip itself is correct — the producer emits `(ns dp)` ahead of the `defprotocol`/`extend`, and the importer re-registers the protocol under `dp/Describe`. The same two-registries-answer-one-name asymmetry `context/conventions.md` records for private names (`scope-lookup` vs `generic-lookup`) is the underlying shape  **Fixed by restoring the invariant rather than by patching the asker.** `emit-defn` writes BOTH registries even for a solitary function, and that second write is the only reason a conformance, a drop thunk or a `(dyn P)` vtable resolves at all; `declare` was the sole producer writing one. It now registers the method too, `ir-fixed` so the producing unit's symbol is never re-mangled. **A second asker was measured and is fixed with it**: `method-satisfies-sig`, so `(extend lib/Fox MyProto)` in a consumer reported a conforming type as non-conforming. Calls were unaffected throughout (they ask `g-globals`), which is what hid it. Two consequences handled: `Method.ir-fixed` (else one local overload renames a symbol another object defines), and R4's duplicate-*definition* check, which began firing between two headers from different namespaces over definitions neither importing file makes — it now asks only about local pairs, leaving item 35 exactly as it was. See the note below and `run_w9_nuch_declare_generic`. **Filing item 36**, the pre-existing shadowing this measured |
| 25 | **A user struct has no complete C tag, so it cannot be used by value from C — FIXED 2026-08-10**, found fixing item 4 | `emit-cheader-defstruct` emitted an ANONYMOUS `typedef struct { … } Name;`, so `struct Name` was a different, never-completed tag. Every by-value use failed: a field (`struct Rec r;` — "field has incomplete type"), and a parameter. Item 3 met the same wall for a `defvar` and worked around it locally (`cheader-by-value-c`, which stripped the `struct ` prefix). Fixed as recorded — emit `typedef struct Name { … } Name;`, applied to `emit-cheader-defunion` too, and `cheader-by-value-c` is gone. **Its "breaks `char.h`, `error.h`, `string-split.h`" attribution was wrong**: those three break for two *other* reasons, one of which (builtin `Char`/`Err` spelled as structs) was closed alongside and one of which (a header naming another library's type without including it) is now **item 37**. Corpus: 340→349 of 375 generated headers compile, 0 regressed. See the W9-25 note below |
| 26 | **An overloaded or operator-named `defn` is exported under a bare name no object defines — FIXED 2026-08-10**, found fixing item 4 | `emit-cheader-declare` derived the symbol as `ns-ir-base fname`, which is the real symbol **only** for a solitary, non-operator function. An overload is mangled per signature and an operator goes through `op-name-token` even when solitary — measured: `lib/string.nuc`'s `=` on `String` links as `@eq.String.String`, and `nm lib/string.o` has **no** bare `=`; `lib/parse.nuc`'s three `from-str` are `from-str.i32.pStrView` &c. So the header both declares a symbol that does not exist and declares it two or three times under one C name. Pre-existing and equally wrong before item 4 (it read `_Bool =(…)`, invalid C, failing at the parser instead of the linker); item 4 makes it explicit by attaching `asm("=")`. The ruling was the first of the two the item offered: each method gets its own C name (the mangled symbol, dots sanitized) and its own `asm` label. The fix is not a derivation but a **question** — `defn-form-mangled-name` reads back what `finalize-generics` decided, and answers null exactly when `ns-ir-base` is right — which required giving the header pass the prescan sequence the `.nuch` emitter has always run. Measured: the committed `lib/*.h` bound **236 symbols, 100 of which no object defines**; now **170, all defined**. `lib/*.h` compiling: 29 → **33 of 34**. The recorded blast radius understated it (`hash`, `drop`, `byte-len`, `as-view` &c. were wrong in seven more headers), and closing it also closed item 27 and most of item 38. See the W9-26 note below |
| 27 | **A template tyvar is exported as a concrete C type — FIXED 2026-08-10 by item 26**, found fixing item 4 | `lib/hashset.h` declared `void set_remove(void* self, struct T elem);` — `T` is the template's type variable, emitted as though it were a struct. **The recorded cause was wrong in an instructive way.** It reads "`defn-is-generic-template` already answers this question for the *whole form*; the gap is that a method on a parametric struct is not itself a generic template" — but that predicate answers correctly, and a method on a parametric struct *is* a template to it (`defn-has-receiver-tyvars`). It was returning 0 for a different reason: `collect-pattern-tyvars` finds a tyvar **only** through `node-template-of`, the struct-template registry, and the header pass had never populated it, so `(HashSet T)` was not a template application and `T` was not a tyvar. One missing prescan, not a missing case. Item 26 ran the prescans; `set-remove` and fourteen others in `hashset.h`/`hashmap.h` now read `/* …: generic template; not exported */`, which is what they are — a template has no symbol until a call site stamps it. Gated by `w9-cheader-symbol-defined` and the corpus assertions beside it |
| 28 | **A C keyword is emitted as an identifier — FIXED 2026-08-10**, found fixing item 4 | `lib/hashset.nuc` defines `union`, a perfectly ordinary Nucleus name, and the header emitted `void union(void* self, void* other);`. `sanitize-for-c` maps illegal *characters* and has no notion of a reserved word, so the name passed through intact and the header did not parse. The same applied to `int`, `return`, `default`, `switch`, `class` and the rest. **Ruled as the item proposed** — rename to `union_` and label it `asm("union")`, exactly as a hyphenated name is handled — with three refinements the corpus forced. (a) **C++'s keywords count too.** The only committed header this defect touched was `lib/allocator.h`, whose `alloc-handle-realloc` takes a parameter named `new`: legal C, fatal C++, and a generated header is routinely read through `extern "C"`. Committed `lib/*.h` parsing as C++ went **32/34 → 33/34** (only `string-split.h`, item 37); as C it stays 33/34, since a C-only table would have left `allocator.h` broken and measured nothing. The iso646 spellings (`and`, `or`, `not`, `xor`) are in the table for the same reason. (b) **A struct tag is an identifier**, so `typedef struct union {…}` fails as surely as the function did; the escape had to go on `type-name-to-c` *and* both definition sites, in the same three-way lockstep B3′ and item 25 each had to repair. (c) **Escape the join, not the fragment.** `Color_default` is already legal, and escaping the fragment would have renamed every prefixed enum constant in the corpus for no reason — `cheader-c-ident-join` tests the finished string, which can still land on a keyword (`and` + `eq`). Everything is one `_` suffix and the existing `cheader-asm-label` comparison picks up the rebinding for free, so no symbol moves: verified end to end by compiling **and linking** a C and a C++ consumer against a nucleusc-built object whose exports are `union`, `xor`, `delete`, a `class` struct passed and returned by value, and fields named `class`/`signed`. Corpus effect measured, not asserted: 362 of 364 headers byte-identical, the two that moved being `lib/allocator.nuc` (`new` → `new_`) and `src/compiler-types.nuc` (fields `template`, `private`); IR 231 identical, 0 differing |
| 29 | **A `.nuch` header's functions and values registered at import time, so they stayed order-dependent — FIXED 2026-08-10**, split out of item 6 (2026-08-10) | A `declare`d function, an `extern` global, a `defconst` or a `defenum` member from a header resolved only if the header was imported *above* the use; otherwise `not defined anywhere in this compilation unit` for a name that is in the unit. Measured against the `.nuc` spelling of the same library, which resolves on reachability (W1a): `declare`/`extern`/`defconst`/`defenum` all failed, and so did a `defmethod` — the item's list of four was one short, because real parity with a `defn` includes each arm of an overload set. **Ruled as the item proposed**: a registration-without-emission pass over header forms (`prescan-nuch-signatures`), armed by the same per-path `g-prescan-sigs` guard `emit-toplevel-forms` already reads, rather than a second implementation of the registrars. The half the item did not anticipate is *where the line between the halves falls*. Hoisting emission too would move every `declare` / `external global` to the top of `g-decl-stream` and change the IR of every module that imports a header — `src/llvm.nuch`, so the compiler's own — so registration moves and emission does not, via a `NUCH-BOTH`/`NUCH-REG`/`NUCH-AFTER` mode on the three importers. That in turn makes "already registered" a per-NAME question, not a per-header one: all three importers have an "already defined → return" skip (two headers declaring one `stderr`; item 36's local definition), so an emit-only pass that assumed the whole header was registered would write `@x = external global` twice and LLVM would reject the module — hence `g-nuch-registered`, keyed on (path, name). Registration-only also means the pass writes no IR, so it needs no stream guard and is correct under `--emit-nuch`/`--emit-cheader`, which return before `open-module-streams`. Measured: IR **231 identical / 0 differing / 0 status changes** across the corpus, `--emit-nuch` 367 identical, `--emit-cheader` 364 identical; the header import now compiles, links and runs identically from either position, and transitively through a `.nuc` library. What did NOT change is the residue, and it is **symmetric with `.nuc`** — see item 40 |
| 30 | **`(as f32 1.5)` is refused although the literal is exactly representable — FIXED 2026-08-14**, split out of item 8 (2026-08-10) | The float counterpart of item 8, and the *only* place the safe cast is still stricter than the implicit coercion for a literal. `emit-as` step 7 rejects every `f64`→`f32` on the two kinds alone, so `(as f32 1.5)` dies `lossy conversion from f64 to f32` while `(let (a:f32 1.5) …)` compiles and emits a plain `float 1.5` constant with no instruction (W2d). [../global-init.md](../global-init.md) records the rejection as expected behaviour, which is why item 8 did not quietly widen into it — this is a **ruling**, not a missed call site. The predicate is already written: `f32-const-ir` computes `(as f64 (unsafe/cast f32 d))`, so "does this literal round-trip exactly" is that comparison, and it is the precise analogue of `int-literal-fits`. The ruling to make is whether `as` accepts only exact round-trips (1.5 yes, 3.14 no — `as` keeps its no-loss promise, and is *stricter* than the implicit path's deliberate Option A rounding) or follows the implicit path wholesale. Recommend the former; ~6 lines either way  **Ruled the recommended way and built as described — and the estimate was right for the rule and wrong for the item.** The three-line predicate is the whole of it, but landing it *created* a second asker inside the same change: with `(as f32 1.5)` legal, `(defvar g:f32 (as f32 1.5))` stopped being an error and became a `@__nucleus_init` store while `(defvar g:f32 1.5)` stayed a constant — the exact divergence `global-init.md`'s "a float `as` fold could only have diverged" clause was written to prevent, arriving from the other direction. See the W9-30 note below |
| 31 | — FIXED 2026-08-14 — **`i1` is treated as a *signed* 1-bit integer, so `true` widens to −1 and `(< false true)` and `(> true false)` are BOTH false**, split out of item 9 (2026-08-10) | Measured, pre-existing, and independent of item 9's fix (the corpus sweep for that fix was IR byte-identical across all 373 programs, this path included). `(as i32 true)` and `(as i64 true)` are **−1**, contradicting [../../docs/types.md](../../docs/types.md)'s own literal table (`true` → `1`) and the `bool`→`_Bool` C mapping, where `(int)true` is 1. The comparison half is worse than surprising, it is **self-contradictory**: `icmp slt i1` reads `true`'s bit as −1, so `false < true` is `0 < -1` = false *and* `true > false` is `-1 > 0` = false — for two distinct values exactly one must hold. **Single cause**: `is-unsigned` (`src/type-utils.nuc:421`) has no `TY-I1` arm and falls through to `(return 0)`, so every consumer picks the signed instruction — `sext` over `zext` at `nucleusc.nuc:3409` and `abi.nuc:973`, and the signed comparison at `nucleusc.nuc:3311`. **The ruling**: `{0, 1}` makes unsigned the only coherent reading of `i1`, and one `TY-I1 (return 1)` arm fixes all three consumers at once — but `is-unsigned` has 22 call sites, including `binop-result-type`'s signedness-match test (`nucleusc.nuc:3124`, `:3304`) and generic parameter matching (`generics.nuc:626`), so unlike item 9 this **will** move the bootstrap and needs its own sweep. The narrower alternative — an `is-bool` test at the two ext sites only — fixes the widening and leaves the comparison, and is not recommended. **Fixed as ruled**: the one `TY-I1 (return 1)` arm. The estimate was right that it moves the bootstrap and wrong about how far it reaches — the whole corpus moved by exactly 24 `sext i1`→`zext i1` sites and nothing else, and the 22 risky call sites cost zero diagnostics. It also caught a *third* consequence the item did not list: a mixed `bool`/`i32` binop had been **accepted**, silently answering `(< true 1)` = true |
| 32 | — FIXED 2026-08-14 — **An unsigned index is SIGN-extended, so `(aref p i)` with `i:ui32 ≥ 2^31` reads backwards from `p`**, split out of item 15 (2026-08-10) | Measured end to end, not inferred: with `i:ui32` at `4294967295`, `(aref (unsafe/ptr+ buf 1) i)` returns `buf[0]` — the index became `-1`. Pre-existing and independent of item 15, whose fix is width-only and byte-identical on the host. Now a **one-line** fix, because item 15 gave the widening a single home (`gep-index-ir`, `nucleusc.nuc`): pick `zext` when `is-unsigned` answers for the index type. It also **costs code size** today — dropping the `unsafe/cast i64` workaround from `examples/avr-global-init.nuc` grew the ATtiny1634 image by 4 bytes, exactly the sign-extension of a `ui8` counter that `zext` would not emit. Two cautions: `is-unsigned` had no TY-I1 arm (**item 31**, fixed 2026-08-14 — it now answers `1` for `i1`, so this caution is discharged), and this changes host IR wherever an unsigned index is used, so unlike item 15 it needs its own sweep and will move the bootstrap  **Fixed as ruled, in the one line predicted — and the second caution was wrong, which is the finding.** It does not move the bootstrap: the compiler's own IR is **byte-identical**, because nothing in it indexes with an unsigned narrow type (signed `i32` and pointer-width `usize` only, and `usize` needs no instruction at all). The whole corpus moved by **five lines**, four of them in the new fixture. The code-size claim was exact — the ATtiny1634 image gave the 4 bytes back, 942 → 938. See the W9-32 note below |
| 33 | — FIXED 2026-08-14 — **A failed argument coercion is silently discarded, so a call may pass an argument of the wrong type with no diagnostic**, found fixing item 20 (2026-08-10) | `emit-call-with-args`' coercion loop (`nucleusc.nuc`) calls `safe-coerce-val` and **ignores a null return** — the comment there says so outright ("no safe conversion exists, the argument is left untouched — preserving the prior pass-through behavior"). So `(f-ptr 7)` against `(defn f-ptr (p:ptr:S) …)` emits `call i32 @f-ptr(i32 7)`, `(f-i32 c)` with `c:CStr` emits `call i32 @f-i32(ptr %t)`, and `(f-i32 1.5)` emits `call i32 @f-i32(double 1.5)` — all accepted, all UB, and `llvm-as` accepts the IR because a call site carries its own signature. Measured identical on the pre-session compiler (5f4989e), so pre-existing. This is the **type** half of item 12, whose arity half was fixed 2026-08-02, and W2d already fixed one *instance* of it (the f32 narrowing miscompile) by adding a coercion rule rather than closing the hole. Overloaded/multimethod calls are unaffected — resolution must match a signature to pick a method, so it rejects earlier and for a different reason; this is the **solitary-`defn`** path only  **Fixed as filed, in five lines: report what the loop was discarding, with the same shape the return site already used (LW-3 calls `coerce-int-val`, checks null, dies with both `type-spelling`s).** Two things the item did not say. Its three examples are all *deliberate* type errors; the case that matters is `(take-f64 3)` — ordinary-looking code, silently miscompiled to `call double @take-f64(i32 3)`, printing `0.000000`. `int`↔`float` is in neither direction of the coercion set, and `(let (a:f64 3) …)` already refused it, so the argument position was the sole outlier and the fix is a *consistency* repair, not a new rule. Second, one line of error surfaced **two further defects** that had been invisible behind the silence: items 41 and 42. Corpus: 233 accepted before and after, 0 status changes, 0 diagnostics moved; the two IR diffs are item 41's fix and the one-line source repair item 42 forced |
| 34 | — FIXED 2026-08-14 — **The argument-coercion guard compares IR type *strings*, so a mismatch between two types that lower to `ptr` is never even checked**, found fixing item 20 (2026-08-10) | The same loop guards on `(!= (strcmp (type-to-ir (slot type)) (type-to-ir ptype)) 0)`. Every pointer flavour lowers to `ptr`, so a `CStr`, a `raw` or a `(ref T)` flowing into a `(fn …)` parameter compares equal, the guard is false, and no coercion is attempted at all — `(take c)` passes a string where a function pointer is expected and the callee calls it. Distinct from item 33 (there the guard fires and the *result* is dropped; here the guard never fires), and it is why item 20 looked half-broken: `(take null)` was never accepted, only unchecked. Note `pkind-flow-check` runs unconditionally just above and does catch the nullability subset, which is why `raw`→`(ref T)` arguments *are* diagnosed — the hole is the type identity, not the contract. **Still open with item 33 fixed (2026-08-14), and now the only silent one left in that loop**: item 33's `die-at` sits *inside* this guard, so every pair the `strcmp` calls equal still reaches the callee unchecked — `(take c)` with a `CStr` into a `(fn …)` parameter is unchanged. The two are one loop and two lines apart, and fixing 33 first was deliberate: it is the half that needs no ruling  **Fixed 2026-08-14, and the ruling turned out to be already written.** The guard now asks `type-eq`, and `safe-coerce-val` answers the pairs that newly reach it by delegating to `coerce-int-val` — the chokepoint every *other* typed slot already funnels through, which knows CStr↔ptr is free, that the literal `null` reaches a fn slot (item 20) and that a data pointer does not. So "what does the argument position accept?" stopped being a separate answer. **The item understated the hole**: as filed, an int literal and a string literal reached a `(fn …)` parameter too — all eight spellings in item 20's refusal matrix were accepted at an argument while `let` refused six. Those two have differing IR strings, so item 33 closed them on its own; the four that lower to `ptr` are item 34's, and the measured split is tabulated in the note below. It also had a second half nobody had filed: two types that lower to the same string but differ in SIGN were never compared either, so `(take-ui32 -1)` passed 4294967295 where `(let (a:ui32 -1) …)` had always been `integer literal -1 does not fit ui32`. Corpus: **0 IR diffs, 0 diagnostic diffs, 0 status changes** over 396 programs, and the bootstrap held on the first pass — replacing a lowered-type comparison with a type-identity one moved nothing that was already correct |
| 35 | **Two namespaces cannot each define one name with the same signature — FIXED 2026-08-14**, split out of item 23 (2026-08-10) | With item 23's symbol half fixed the two definitions no longer *collide* — `@qa__describe` and `@qb__describe` are distinct symbols, and a qualified `qa/describe` filters to its own method. What refuses them is R4's eager same-kind check in `finalize-generics`, whose note still says "a public name must be unique across the whole compilation unit" — true of one flat namespace, and the thing namespaces exist to stop being true. The obstacle is the **bare** reference: one `Generic` per bare name (R2) means `(describe 10)` has two equally good methods and nothing to choose between them. The honest rule is R2 §8.2's own first recommendation, which R4 later overrode — allow the definitions, report ambiguity at the first ambiguous *use*, naming both candidates. That is a ruling change, and it sits on top of the audit B4 explicitly deferred (§9.6: a bare reference currently reaches namespaces the file imported *prefixed*, and filtering it symmetrically "wants its own audit of every `Method` writer first"). Not a typo, not a one-liner, and the diagnostic today is located and names both files — so this is a real limitation with a good error message, not a silent wrong answer. **CORRECTION (2026-08-14, on fixing it).** The row's recommendation held and its cost estimate was right about the audit and wrong about where the work was. The audit B4 deferred came back **clean**: five `(new Method)` sites, two of which never enter a `Generic.methods` vector at all, and of the three that register, `build-generics` leaves `src-ns` null deliberately while the other two were already correct — B4 had fixed the only two writers that were wrong. What the row did not predict is that allowing the pair **rots a key**: once two namespaces may each own one signature, `(name, param-types)` stops identifying a method on the DEFINITION side, and `defn-ir-name` asked exactly that pair — so both files emitted `define @qa__describe` and LLVM rejected the second, a duplicate symbol produced by the change meant to give them two. `generic-find-method-exact-in-ns` adds `src-ns`; a REFERENCE deliberately keeps the two-part lookup. The other correction is to R4's guard: it is now conditional on the emitted **ir-prefix**, not the namespace *name*, for the reason `generic-user-methods-with-prefix` already gives — two namespaces that `set-ir-prefix` to one string genuinely share a symbol space — which states the concrete harm instead of a proxy for it. Full account in [name-resolution.md](name-resolution.md) §9.8 |
| 36 | — FIXED 2026-08-14 — **A `.nuch` `declare` is silently discarded when the importing unit defines the same name, and even a QUALIFIED call to the library's function then reaches the local one**, found fixing item 24 (2026-08-10) | `emit-nuch-declare-import` returns early on `(scope-lookup-key g-globals fname)`, and the unit's own signature prescan has already bound every local `defn` by the time the import form is emitted — so the header entry is dropped whole: no global binding, no LLVM `declare`, no generic method. Measured: a library exporting `helper (x:i32):i32`, a consumer defining `helper (x:i64):i64`, and `(lib2/helper 3)` emits `call i64 @helper` — the **local** function, under a spelling that names the library's. There is no diagnostic, and the two are not even the same type. Byte-identical on the pre-fix compiler, so it is pre-existing and untouched by item 24, whose registration simply inherits the early return. The skip's stated purpose is idempotence ("already defined (e.g. from include or c-include)"), which a diamond import genuinely needs; what it cannot distinguish is a re-declaration of the same function from a *different* function that happens to share the name. Neighbour of item 29 (both are `.nuch` registration order) and of item 33 (both silently accept a wrong-typed call). **Fixed** by asking two questions at the skip instead of none: WHERE the declaration is written, and whether this unit DEFINES the name. The first is the one that does the work — `--emit-nuch` never re-exports a top-level `declare` (measured), so a `.nuch` entry can never be a forward declaration of the importing unit's own function, while a `.nuc` one — W1e's cross-file cycle-breaker, whose entire job is to be a no-op once the prescan reaches the real `defn` — always may be. The second keeps the libc diamond silent: only a `defn` carries a body, so a C header and a `.nuch` both naming `strlen` answer no. A signature comparison was tried first and is **wrong**: the two `w9-declare-cycle-breaker` tests fail under it in the direction that matters, and the existing `w9-nuch-local-definition-still-wins` (which recorded this very defect while item 29 was fixed, signatures IDENTICAL) proves a signature test cannot see the case at all. That test now asserts the error and is renamed `…-reported`. 0 IR diffs / 0 diagnostic diffs / 0 status changes over 396 corpus programs — every one of the ten in-tree skips is a libc re-declaration — bootstrap byte-identical, and the 69 committed headers unchanged |
| 37 | — FIXED 2026-08-14 — **A generated C header names a type from an imported library and emits no `#include` for it**, split out of item 25 (2026-08-10) | `lib/string-split.h` declares `struct StrView cur;` — a real user struct, defined in `lib/prelude.nuc` and typedef'd in `lib/prelude.h`, which `string-split.h` neither includes nor forward-declares, so it fails "field has incomplete type" no matter how the *defining* header spells the type. This is the **whole** residual cause of item 25's `string-split.h`, and the last cheader defect that is not a naming ruling. `--emit-cheader` already knows the import set (`emit-cheader-header` walks the forms), so the mechanism exists; the ruling needed is what to emit — `#include "prelude.h"` presumes a filename and a search path the Nucleus import never had, and a forward declaration (`struct StrView;`) is enough for a pointer but not for the by-value field this actually is. Neighbour of item 26/27/28 only in file, not in kind. **Fixed 2026-08-14.** The ruling the row asked for went the third way: not the import list and not a forward declaration, but *the defining unit of each type the header actually names*, included by the path convention the build itself already uses (`lib/%.h: lib/%.nuc`), so nothing is presumed that the Makefile does not already promise. `type-name-to-c`'s fallthrough is the one place a `struct NAME` reference is spelled, so it records the type's `StructDef.src-file`; a pre-pass over the signature positions runs the same renderer before the preamble is printed, which is what lets the `#include` precede the first use. Two supports were missing and are now in place: `prescan-struct-names` records `src-file`/`src-line` at name pre-registration (the definition-time writers never run in this mode, because `--emit-cheader` emits no struct, so provenance was uniformly null), and the pre-pass replicates the emitters' four "this is not exported" tests — generic template, parametric head, template instance, closure/erased box. That last part is not decoration: without it `lib/vector.h` and `lib/combinators.h`, which spell no `struct` at all, took includes for a parametric field and a template's return type. **Measured**: exactly 5 committed headers change and each gains only `#include` lines (`keyword`, `string-split`, `string`, `strview-str`, `strview`) — precisely the 5 that name a user type they do not define; all 34 lib headers now compile standalone, where `string-split.h` did not; corpus-wide `--emit-llvm` is 0 IR / 0 diagnostic / 0 status diffs over 396 programs, the bootstrap is byte-identical first pass, and the 3 pre-existing `--emit-cheader` crashes are unchanged in count and identity. The C side is asserted by *linking and running* a consumer that copies an imported struct by value, and by stripping the one include line back out and watching the original "field has incomplete type" return |
| 38 | — FIXED 2026-08-14 — **`--emit-cheader` segfaults on a malformed form that every other pipeline diagnoses**, found fixing item 25 (2026-08-10) | *(Item 26 gave the pass the real prescans, so it now reports the compiler's own located diagnostic — byte-identical to `--emit-llvm`'s — for `w5f-empty-defunion-arm.nuc` and for 29 further corpus files that used to get a header for a program that does not compile. **Three fixtures still crash**: `s1-missing-ret.nuc`, `w5f-empty-param.nuc`, `w5f-empty-union-member.nuc`, all of them shapes the prescan accepts and the emitter then dereferences. A separate crash with the same shape — an anonymous struct in a signature, which had segfaulted `--emit-nuch` since it was written — was root-caused and fixed with item 26: `lookup-or-make-anon-struct` wrote IR to a null `g-type-stream`.)* Measured on 4 corpus files (`tests/fixtures/s1-missing-ret.nuc`, `w5f-empty-defunion-arm.nuc`, `w5f-empty-param.nuc`, `w5f-empty-union-member.nuc`), identically on the pre- and post-item-25 compiler, so it is pre-existing and independent. `--emit-llvm` on the same input reports `w5f-empty-param.nuc:7: error: expected a name:type declaration, found the empty list '()'`; `--emit-cheader` dies with SIGSEGV and no output. The cause is structural rather than one missing check: the cheader pass walks the form AST directly and reads `(node-at form N)` positions without the arity/shape validation the real parser performs, so any shape the parser would have rejected is dereferenced as though it were well-formed. A crash is the worst diagnosis of a syntax error the compiler can give, and these fixtures exist *because* the syntax is invalid. *(One further residue measured 2026-08-14 while fixing item 37, on the pre- and post-fix compiler alike: an **unresolvable import** is still not reported. `--emit-llvm` on a unit whose `(import-use foo)` cannot be found exits 1 with `import: cannot find 'foo'`; `--emit-cheader` on the same unit exits **0** and prints a header, silently missing everything the import would have supplied. Same family as the three crashes — the pass reaches a state the real pipeline refuses — but a wrong answer rather than a signal.)* **CORRECTION (2026-08-14, on fixing it).** The row's "structural rather than one missing check" was right, and the structure is one layer up from where the row looked. It is not that the pass "walks the form AST directly … without the arity/shape validation the real parser performs" — the real parser performs none either. The compiler has TWO validation layers, a permissive prescan and a strict emitter, and every prescan **deliberately** defers its diagnosis to the emitter: `defn-params-to-types` says "the located diagnostic is emit-defn's job", `prescan-file-imports` says "a missing library is diagnosed by do-import". The header modes run the first layer and never the second, so nothing downstream ever asked — which makes the three crashes and the import residue **one** defect with one cause, and explains why item 26 (which added the prescans) fixed most of it and could not fix the rest. The ruling the row asked for is the scope: a header mode refuses every program whose DECLARATIONS the real pipeline refuses, not every program it refuses — a body error is out of scope by construction, since no body is read, and closing that would mean running the emitter. Measured, that boundary is 396 corpus programs where `--emit-llvm` and the header modes disagreed on **136** before and **133** after; every one of the 133 is a body-or-other error, every one is `llvm=1 / header=0` (never the reverse), and the three that closed are exactly the three crashes. **The row's count of crashing shapes was also too low, and the corpus is why.** Probing every head the two header emitters dispatch on — rather than the three files that had been reported — found **ten** crashing shapes: a truncated form of `defn`, `defstruct`, `defunion`, `defconst` and `defenum`, plus an inline aggregate reached through a pointer, an array or a `defvar` type rather than a struct field. The first version of this fix closed the three named ones and passed every gate while still leaving seven, which is the argument for probing the *set of positions that never ask* instead of the set of bug reports. The arity half is now nine `require-<head>-form` chokepoints, each moved verbatim out of the top of its own emitter, which now calls it — nine copied messages being nine chances to drift, and drift in this exact emitter is what item 26 fixed. `--emit-nuch` had the same defect in its silent form and is fixed by the same walk: it does not crash — it `print-node`s a parameter rather than walking it — so it exported `(declare foo ((x i32)))`, a declaration with no return type, for a program that does not compile, and a consumer would have linked against it. Also corrected: `docs/compiler.md` claimed "a source that does not compile produces the compiler's ordinary error rather than a header", which overclaimed before this fix and still would after it |
| 39 | — FIXED 2026-08-14 — **A name beginning with a digit compiles all the way to LLVM, which then rejects the module**, found fixing item 28 (2026-08-10) | `(defn 2fast (a:i32):i32 …)` passes every front-end pass — `check-ir-name-legal` tests the character *set* (`[A-Za-z0-9$._-]`) and a digit is in it — and emits `define i32 @2fast(i32 %a.arg)`. LLVM reads `@2` as a numeric global id, so the whole module dies at IR-parse time on `expected '(' in function argument list`, a message that names a line in the *generated IR* and nothing in the user's source. The exit status is 1 and no object is written, so nothing is silently wrong — but the diagnostic is unattributable, which is the guarantee W9 exists to defend. `--emit-cheader` emits `int32_t 2fast(int32_t a);` for the same program, unparseable in C; that is a symptom, not the defect, and fixing it in the header emitter would export a symbol no object can ever define. The fix belongs at the ir-name layer: either reject a digit-leading name with a located error (the same shape `check-ir-name-legal` already produces) or quote it (`@"2fast"`, which LLVM accepts). Latent — no corpus file has such a name. **CORRECTION on fixing: neither proposed answer was right, and the scope was wrong.** The codebase has already ruled on this question. `ir-name-token` exists precisely to spell a Nucleus-legal, LLVM-illegal name (`?`→`_QMARK`, `!`→`_BANG`, SM-1), so `(defn even? …)` compiles and `@even_QMARK` links. A leading digit is the same class — legal in the reader, illegal in LLVM — and rejecting it would have made the language inconsistent with itself for no gain; quoting (`@"2fast"`) preserves the spelling but leaves C unable to name it at all. So: mangle, one leading `_`, in `ir-name-token` with the other two. And measuring first found the row's `defn` framing far too narrow — `ir-name-token` was applied ONLY at the global-symbol and type-name layers, so a **parameter, `let`/`with` binding, `match` binder and `label`/`goto` target went to LLVM verbatim, and that half is not latent**: `?`/`!` are documented as working in a name, so `(defn add? (ok?:i32) …)` emitted `define i32 @add_QMARK(i32 %ok?.arg)` — the function name mangled, the parameter three tokens away from it not. Fixed at the ir-name layer as the row said, in the two places that layer was incomplete: the transform now knows LLVM's first-POSITION rule as well as its character class, and every producer of an LLVM local (`abi.nuc` parameters, six `union-emit.nuc` binders, `emit-let`/`emit-with`/drop-handle, the macro prologue, five `%lbl.` sites) applies it. `sanitize-for-c` is unchanged — the identical C rule belongs on a COMPLETE identifier, so `cheader-escape-leading-digit` sits beside `cheader-escape-reserved` in `cheader-c-ident`, which is why an arm reads `_2Shape_2circle` and not `_2Shape__2circle`. Same `_` on both sides, so the C spelling IS the link symbol and no `asm()` label appears |
| 40 | — **LAYOUT half FIXED 2026-08-15**, macro half RULED — **A macro, a union's arm constructors and a struct's LAYOUT still resolve on import order — in BOTH spellings**, found fixing item 29 (2026-08-10) | Not a header defect: measured identical for `(import-use lib)` reaching `lib.nuc` and reaching `lib.nuch`, which is why item 29 did not absorb it. With the import *below* the use, `(w9r-mac 5)` is `unknown: w9r-mac`, `(W9RSome 3)` is `unknown: W9RSome`, and a struct literal `(W9RBox 3)` reports **`too many initializers for struct 'W9RBox'`** — the worst of the three, because the name resolves and the diagnostic then blames the call. The cause is one sentence: `prescan-struct-names` registers a name-only StructDef and the two prescans register *names*, while fields, arm constructors and macro bodies are emission-time state. It is the same list the W1d cycle table already carries (`docs/toplevel.md`), which is the hint that the fix is shared: a cycle cannot carry them for the same reason an early use cannot. A field-layout prescan is the substantial part (it must resolve field *types*, so it wants pass 1's two-pass shape); the union constructors are `defunion-register` + the ctor declares, and a macro needs the JIT, so those two are rulings about how early each may run. Latent in-tree — every library in the repo is imported above its uses. **Fixed 2026-08-15, and the row's three kinds were three different things.** The struct half is the substantial one and the row's prescription was right — `emit-defstruct` splits at the line where it starts writing IR, so `defstruct-fill-layout` registers the field table and the `%Name = type {…}` line stays where it always was; it wants pass 1's shape only in the sense that it needs every NAME first, so it rides pass 2's existing walk as a POST-order step and reads no file a second time. The union half was smaller than recorded: the arm CONSTRUCTOR already worked below the import (`prescan-union-ctors` hoisted its signature in W1a), and what did not was `make`/`match`/by-value, i.e. the `UnionDef` — so the fix is `defunion-register` in the prescan plus a `ctors-emitted` bit, because `emit-defunion`'s no-op-on-existing-UnionDef guard was keyed on a thing the prescan now produces. The macro half is **ruled, not deferred**: a `defmacro` is not a registration but a compiled function — defining one runs codegen into a fresh JIT module and materializes it — so there is no half of it that writes no IR, and it stays with the emitter. **Two residues, measured:** an `(array T N)` field extent that needs a macro to fold (`(* K 2)`; a plain `defconst` extent folds, cross-file included), which follows from the macro ruling; and the `.nuch` spelling of a `defunion`, which is item 46 rather than this one. **The same fix closed a defect this row does not mention**: `conventions.md` had carried "latent, still unfixed" since W1d for `(defn f (v:S) …)` textually above `(defstruct S …)` in ONE file — the identical `i0` silent miscompile, with no import involved — and it fell to the layout prescan because neither shape is about imports |
| 41 | — FIXED 2026-08-14 — **A `(dyn P)` method call with exactly ONE conforming type bypasses the vtable and calls the concrete method directly**, found fixing item 33 (2026-08-14) | Stage 13 TE-6's forwarding lives in `emit-generic-call`, and a method with one conformer never becomes a Generic — it stays a solitary `defn`, so `(qm b)` on a `(dyn Qq)` emitted `call i32 @qm(i64 %data, i64 %vtable)` against a `define i32 @qm(ptr %self.arg)`. Two conformers dispatch correctly through the vtable, so the defect is *keyed on the conformer count*, which is why no test caught it: the box's data word is the first SysV integer register, so a receiver-only method reads it correctly and returns the right answer. A method with **one more parameter** is what makes it observable — the vtable word occupies the register the second argument wanted, so `(add-k b 5)` computed `100 + <vtable address>`, printing 885001780 for 105. Item 33 surfaced it as a hard error (`argument 1 has type __dyn.Qq, which does not match parameter type ptr:A`) in two corpus programs and one fixture, all of which had been "passing". **Fixed with TE-6's own three pieces** — `dyn-canonical`, `dyn-method-slot`, `emit-dyn-forward` — hoisted into `emit-call-with-args`, where the box is still a first-class aggregate; a callee that *declares* a `(dyn P)` parameter wants the box and is left alone. The qualified spelling needed a second repair: a protocol declared inside `(ns …)` stores its sigs bare, so `(wx/describe b)` matched no slot. `dyn-method-slot` now strips the qualifier **after checking it against the protocol's own namespace**, which is what keeps `strip-ns-qualifier` out of the blind resolution position its own comment warns about. Gated by `tests/fixtures/w9-dyn-solitary.nuc` (the extra-parameter witness) plus the qualified cross-unit case |
| 42 | **A `defcast` rule is unreachable from an integer literal, because the literal is `i32` and the rule is keyed on the exact pair — RULED and closed 2026-08-15**, found fixing item 33 (2026-08-14) | `examples/implicit-cast.nuc` registered `(defcast i64 ptr id_to_ptr)` and called `(show-ptr 0)` under the comment "defcast fires: i64 → ptr via id_to_ptr". It never fired: the literal is `i32`, `lookup-cast-rule i32 ptr` misses, and the pre-fix compiler emitted `call void @show-ptr(i32 0)` — the example documented behaviour it did not have, for as long as it has existed, and only item 33's error revealed it. `(show-ptr (as i64 0))` does fire the rule, which is the one-line source repair made with item 33. The ruling to make is whether implicit conversions **compose**: built-in int widening followed by a user rule. C++ answers no (one user-defined conversion), and that is the recommendation — a `defcast` from a *narrow* type is spellable and explicit, and composing them makes `lookup-cast-rule` order-sensitive. The alternative, and the reason this is filed rather than dismissed, is that `defcast` is documented as "any pair" and a literal is the most natural argument to write. Cheap either way; the cost is the rule, not the code **Ruled 2026-08-15: no, they do not compose — one conversion, built-in or user, never both.** The recommendation survived, and measurement made it cheaper than the row expected: composition was *already* refused in all five positions probed (argument, `as`, `let`/`with` init, explicit and implicit return), so the ruling cost zero lines. Two reasons it is the right answer, in the order they mattered: composition turns "is there a conversion from A to Z" from a lookup into a **path search** over a flat `Vector` scanned in registration order, which nothing in `lookup-cast-rule` is able to rank; and a rule from the narrow type is spellable, so nothing becomes unreachable — the price is one explicit `as`. **What the item was actually worth is the other half of the measurement.** Asking *where* a rule is consulted (rather than *from what*) showed the registry had two customers out of nine — filed and fixed as item 47 — so the reported symptom "unreachable from a literal" was the visible corner of "unreachable from most of the language, literal or not". The ruling's own defect — that "no composition" is indistinguishable from "your rule was never registered", which is exactly how this example survived misdocumented for its whole life — is closed by a near-miss note naming the rule and the spelling that reaches it, wired at the five positions that hold both types. The `as` site is the one whose bare text was actively *wrong*: "use unsafe/cast" discards the safety the `defcast` was written to buy. See the note below, `design/stage15-stress-test/implicit-conversions.md` and `run_w9_defcast_reach` |
| 43 | **A PREFIXED import silently changes what a bare, unqualified call in the importing file resolves to — FIXED 2026-08-14**, found fixing item 36 (2026-08-14) | A file defines `helper (x:i64):i64` and writes `(helper 3)`. Alone, that emits `call i64 @helper` — its own function. Add `(import "nslib.nuch" nx)`, a *prefixed* import of a namespaced library that also exports `helper (x:i32):i32`, and the same unchanged line emits **`call i32 @w36q__helper(i32 3)`** — the library's, reached through a prefix the call never spells. Measured on the pre-item-36 compiler, so it is pre-existing and independent; item 36 does not touch it, because the namespaced case never reaches that skip (the keys differ, which is exactly why the namespaced spelling is the escape route item 36's diagnostic recommends). The cause is the audit B4 explicitly deferred (§9.6, and item 35's row cites it as the obstacle underneath it): a bare reference reaches namespaces the file imported *prefixed*, so the two `helper`s meet in one bare-keyed Generic (R2) and ordinary overload resolution picks the `i32` one for the literal `3`. What makes this a defect in its own right rather than a restatement of item 35 is the direction: item 35 is two definitions being REFUSED with a good located error, this is a definition being silently OVERRULED by an import that binds a prefix. An explicit `(as i64 3)` reaches the local one, which is the tell — nothing is unresolved, the wrong candidate simply scores better. The fix is B4's own recommendation, filtering a bare reference symmetrically with a qualified one; it wants that audit of every `Method` writer first, so it is a ruling with real work under it, not a one-liner. **CORRECTION (2026-08-14, on fixing it).** The row was right that this needed the audit and wrong about what the audit would cost. Filtering the bare path is one early return plus a predicate (`ns-reachable-bare` — `name-ref-key-at`'s three slots stated as a predicate, because a generic is the one registry R2 keys BARE and so has no per-namespace key to withhold), with `g-ns-declared == 0` as the byte-identical hatch every other resolver already has. The work was one layer down and is the finding worth keeping: **a monomorphized template body was resolved in the CALLER's import environment.** `MonoJob` was the one deferred-work record carrying no environment, where `DynAnnot` and `InitJob` both carry theirs for the stated reason that the drain runs later — and unlike those two a stamp's body is the *library's* text, so the restored globals are the template's. `b4-qualified-template` was passing only by accident: delete one of its callee's two overloads and the identical program fails on `HEAD` with `unknown: bz4 — not defined anywhere in this compilation unit`, because a merged bare-keyed generic resolved from anywhere while a solitary name went through `globals-lookup-ref`, which has filtered since B2b. Whether a template could call its own namespace's functions depended on **how many overloads the callee happened to have**. Fixing it also corrected the misattribution — an error in a template body reported `<caller>.nuc:<library line>`, a location that in the test program does not exist. Full account in [name-resolution.md](name-resolution.md) §9.8 |
| 44 | — FIXED 2026-08-14 — **An error-union return type (`!T`) is declared in a C header as `struct _BANGT`, a tag nothing defines, over a value that is not a struct**, found fixing item 37 (2026-08-14) | `(defn strview-byte-at (… i:usize):!ui8)` exports as `struct _BANGui8 strview_byte_at(void* sv, size_t i);`. No header defines `struct _BANGui8`, and no header can: the IR is `define i64 @strview-byte-at(ptr %sv.arg, i64 %i.arg)` — `!ui8` is a **niche-encoded scalar**, not an aggregate. So the declaration is wrong twice over, and the second way is the dangerous one: complete the tag by hand and the ABI is still a struct return where the object returns an integer. **14 declarations across 5 committed headers** carry it (`char.h` 1, `parse.h` 3, `string.h` 6, `strview-str.h` 2, `strview.h` 2). Item 37 does *not* reach it — that fix includes the header of the unit that DEFINES a named type, and a `!T` instance is defined by no unit, which is why the two separate cleanly (`struct-lookup-ref "!ui8"` answers null, so nothing is recorded and no misleading include is emitted). Exactly the shape of two already-fixed defects: `usize` fell through `type-name-to-c`'s "assume struct" arm until item 3, `Char`/`Err` until item 25. `niche-sym-to-c` already handles the POINTER niches (`!ptr:T` / `!ref:T`) and simply has no arm for a scalar payload. The ruling is which answer to give: (a) skip the declaration with a comment, as the defunion-template instance arm already does — honest, and correct given a C caller has no way to test the niche; or (b) emit the real scalar plus a documented predicate for the error case. (a) is the recommendation, since a declaration C trusts and gets wrong is worse than an omission — the rule W9 item 3 already wrote down for `defvar`. **Fixed 2026-08-14 with (a), but the row's own reasoning for it does not survive the probe and is corrected here.** "The value is not a struct" is wrong: `!ui8` *is* `%Result.u8.Err = {i32, union}`, a real aggregate — the `i64` return is nothing more exotic than SysV coercing an 8-byte struct into RAX, and a C declaration of the right shape reads it correctly (measured `tag=0 v=65` against the committed object). What is true, and is the actual defect, is that **`!T` is a `(Result T Err)` template instance wearing a sugar spelling**, and `--emit-cheader` already rules that a template instance is not exported — `lib/strview-str.h` has carried `/* byte-find: uses a defunion-template instance type; not exported */` all along. `!T` slipped past that ruling only because the sugar is a NODE-SYM rather than a `(Result …)` cell, so `niche-sym-to-c` answered null and the "assume struct" fallthrough named a tag the emitter then never defines. So the fix is not a new ruling at all: it makes the two spellings of one type agree, which is exactly the trap items 3 and 25 fixed (a Type-keyed and a name-keyed renderer must give one answer). The danger is real either way and is the reason an omission wins — hand-completing `struct _BANGui8` as `{uint8_t v;}` compiles, links, runs and prints **0** where Nucleus reads **65**. Restoring these declarations means exporting template instances *in general* (`(Result i64 i32)` and `(Maybe T)` want the same typedef machinery), not special-casing the sugar; `docs/errors.md`'s "fully legible and constructible from C" is true of the layout and now says explicitly that the header does not yet write it for you. **Scope**: every signature position, not just returns — a `!T` parameter and a `defvar` of `!T` refuse the declaration too (both measured emitting the bad tag). The pointer niches are deliberately exempt and asserted so: `!ptr:T` / `!ref:T` are niche-encoded in the pointer itself, so the value is a bare `T*`, and the test **links and runs** a C consumer through one rather than reading the header. **Measured**: exactly the 5 committed headers and 14 declarations this row predicted, plus 7 corpus headers of the same class (including `?!i64`, which the `?` sigil reaches for free); 0 IR / 0 diagnostic / 0 status diffs over 396 programs; bootstrap byte-identical first pass; all 34 lib headers still compile standalone; the 3 known `--emit-cheader` crashes unchanged in count and identity. One bonus: hoisting the emitter's four refusals into a single `cheader-defn-skip-reason` — asked once of the whole form — let item 37's include pre-pass ask the same question, which dropped a surplus `#include "lib/keyword.h"` from `examples/dyn-protocol.h`, a header that names no `struct Keyword` at all |
| 45 | — FIXED 2026-08-14 — **The compiler segfaults on a definer whose NAME position is the empty list `()` — four heads, in the REAL pipeline**, found fixing item 38 (2026-08-14) | `(defstruct ())`, `(defunion ())`, `(defenum ())` and `(defprotocol ())` each die with SIGSEGV and no output under plain `--emit-llvm`, not merely in a header mode — which is what separates this from item 38, whose whole subject is a header mode diverging *from* the real pipeline. Measured identically on a compiler built at `447e25f` and on the post-item-38 one, so it is pre-existing and this change neither caused nor touched it. The shape is one the reader produces routinely: `()` in a name position is a NULL node (W5f), the arity guard counts it as present (`(defstruct ())` has `node-len` 2, so `defstruct: missing name` does not fire), and the first thing every one of these definers then does with its name is dereference it. Three sibling heads answer correctly and show what the fix looks like: `(defconst ())` says `defconst: expects name and value`, `(defmacro ())` says `defmacro: expects name, params, and body`, and `(defvar ())` says `expected a name:type declaration, found the empty list '()'` — because `emit-defvar` routes its name through `extract-name-and-type`, whose null arm is exactly this diagnostic. `reject-colon-in-def-name` is the shared chokepoint all four crashers call FIRST on their name node (the W4b sibling sweep put it there), and it takes the head spelling as an argument already, so one null guard there would give all four `<head>: missing name` — the same words their own arity guards already use for the absent case. That it is exactly these four is verified rather than assumed: the function has five callers, and the fifth is `defmacro`, which does not crash only because its own arity guard demands **4** nodes and so fires before the name is ever read. In other words the guard that saves `defmacro` is an accident of its arity, not a check anybody wrote for this — which is the argument for putting the null test at the chokepoint rather than at five call sites. Deliberately **not** fixed with item 38: that item's ruling is about a header mode matching the real pipeline, and this is the real pipeline being wrong, with four distinct crash sites to confirm and its own gates to run. Latent — no corpus file has an empty name — but a segfault is the worst diagnosis of a syntax error the compiler can give, which is the standard item 38 was fixed to. **CORRECTION, on fixing it: the row's census was short by two thirds and its recommended fix was wrong in both directions.** Probing every top-level head rather than the four that had been tried by hand found the same crash in **twenty-three** shapes across the three modes — `(defn () (x:i32):i32 …)`, `(ns ())`, `(import ())`, `(export ())`, `(extern ())`, `(declare ())`, `(defcast () i32 f)`, `(extend () Eq)`, `(defconst () 7)`, `(defmacro () (x) x)`, `(set-ir-prefix ())`, plus non-name positions: an enum member `(defenum E A () B)`, a protocol signature `(defprotocol P ())`, a template head `(defstruct (()) …)`, an `extend` protocol operand. The bare `(head ())` spelling was the *narrowest* probe available: an arity guard catches it at half the heads, so the name position is only reached once the form is long enough, which is why `(defn)` looked fine and `(defn () …)` crashed. On the fix: `reject-colon-in-def-name` was **not** the chokepoint for three of the four — `defstruct` and `defunion` die in `prescan-struct-names` and `defprotocol` in `prescan-protocols`, all three BEFORE any emitter runs, so a guard there alone would have left them crashing — and a guard there is also not what most of the class needed, because **every one of these positions already owned the right message** (`ns: namespace must be a symbol`, `defenum: value must be symbol`, `import: name must be a symbol or string path`) and the kind test that would have fired it was the thing that crashed. See the note below |
| 46 | **A `.nuch` header's `defunion` is registered under the BARE name while every other definition-side probe uses the canonical key — FIXED 2026-08-15**, found fixing item 40 (2026-08-15) | `emit-defunion-import` (`src/nuch.nuc`) calls `uniondef-lookup` and `defunion-register` with `(name-node s)` — the raw spelling — where `emit-defstruct`, reached from the very same header walk one `case` arm away, uses `qualify-name`. Under `user` the two agree and nothing shows; inside `(ns nsu)` they do not, so a header carrying `(ns nsu)` + `(defunion Opt …)` registers `Opt` while its own `prescan-struct-names` registered the backing struct as `nsu/Opt`, and the importer ends up with two StructDefs and a `UnionDef` under a key no reference reaches. **Measured on the committed boot and on the current compiler, identically**: a consumer of such a header dies `match: scrutinee must be a defunion value, a pointer to one, or a defenum integer` on a value the library's own `.nuc` source handles fine — so this is pre-existing and independent of item 40, which merely could not extend the layout prescan over it. The arm constructors are the same story one layer on: `union-ctor-form` builds `Opt-Some` from the bare spelling, so the `declare` names a symbol the library's object (which exports `@nsu__…`) does not define. B3′'s rule is the fix and it is already written down — "a definition-side existence probe holds a KEY" — so this is a spelling correction plus whatever the ctor-declare path needs to follow it. Cheap to verify: the `.nuch` half of item 40's layout hoist is three lines once the key agrees **Fixed 2026-08-15, and both estimates held.** The type half is two `qualify-name` calls, and the reason it is only two is that `emit-defunion` had already written the rule down in a comment — the registry takes the canonical KEY, `union-ctor-form` takes the SOURCE spelling, "because what it builds is source … re-parsed in this same file, where the bare name resolves". `emit-defunion-import` had used the source spelling for both. **The arm constructors needed nothing**: hand `union-ctor-form` the bare spelling as the contract says, and `emit-nuch-declare-import` qualifies the synthesized `declare` under the header's own `(ns …)` exactly as it already did for an ordinary `declare`, emitting `@w9nu__Opt-Some` to match the library's object — the row's "whatever the ctor-declare path needs to follow it" turned out to be nothing, because that path was never the one keying wrongly. The follow-on then held to the line: `prescan-union-layouts` joins `prescan-struct-layouts` in `prescan-nuch-signatures` (item 40's residue), plus one guard change — `emit-defunion-import`'s skip could no longer key on "a UnionDef exists", since the prescan now creates one, so it keys on `ctors-emitted` (here meaning "the arm `declare`s are in the stream"), the identical discriminator item 40 introduced for `emit-defunion`. Getting that guard wrong fails loudly in both directions, which is why the test includes a diamond: too eager drops the declares (link failure), too lax repeats them. Measured additive — 242 corpus programs, 0 IR diffs, 0 new errors, 0 changed error texts — and verified against the committed boot, which fails the namespaced case in both import orders and passes the un-namespaced control, since under `user` the two keys agree and this was invisible. `run_w9_nuch_ns_union`, five checks |
| 47 | **A `defcast` rule is refused on its own exact registered pair at seven of the nine typed slots — FIXED 2026-08-15**, found ruling item 42 (2026-08-15) | The registry is consulted from exactly one function, `safe-coerce-val`, and exactly two paths call it: the call-argument loop in `emit-call-with-args`, and `as`. Every other typed slot calls `coerce-int-val`, which knows every *built-in* conversion and nothing about the user's — so with `(defcast i64 ptr id_to_ptr)` registered, `(let (q:ptr (as i64 9)) …)` died `let: init type mismatch for 'q'`, `(defn mk ():ptr (return (as i64 5)))` died `return type mismatch`, and the same for `with`, implicit return, `.set!`, `aset!`, struct-literal fields and union payloads. Not a literal-typing problem and not item 42: the pair is *exactly* the registered one. Confirmed identical on the committed boot compiler, so it is pre-existing and has been true since Stage 8 registered the first rule; `docs/toplevel.md` described the argument position only ("whenever an arg of `From` is supplied where `To` is expected"), which is why the gap read as the design. **Fixed at the chokepoint rather than the nine call sites**: `coerce-int-val`'s single final fallthrough — the one reached when no built-in applies, as distinct from the earlier `(return null)`s that refuse a *specific* pair — now returns `coerce-via-cast-rule`, so every slot gets it at once and a tenth added later gets it free. Provably additive by construction (the user rule runs only where the caller was about to die, which is also `docs/types.md`'s stated "built-in coercion always wins" order) and by measurement: 0 of 365 corpus programs changed a byte of IR, 0 new errors, 0 changed error texts. `safe-coerce-val`'s inline copy was deleted rather than duplicated, so the argument path is byte-identical. Note what this did NOT do: route the other slots *through* `safe-coerce-val`, whose equal-type-KIND short-circuit would have let a `(ptr Foo)` initialize a `(ptr Bar)` binding. Incidental finding recorded in `conventions.md`: the up-call needed for this crosses the import boundary abi.nuc→nucleusc.nuc, which two comments in that file and one in `coerce-int-val` call an unresolvable forward reference — it compiled on the committed boot compiler first try, the signature prescan having made those notes stale |

**Defect 4, with the precision that says what the fix is.** Independently
confirmed: `(defstruct My-Rec (a-field i32))` + `(defn my-func (x:i32):i32 …)`
emits `int32_t a-field;` and `int32_t my-func(int32_t x);` — while the struct
**type** name is correctly sanitized to `My_Rec`. So `sanitize-for-c` reaches
type names but **not** field names or function names: it is applied at exactly
three sites (`cheader.nuc:1761` `type-name-to-c`, `:1852` `defstruct` type name,
`:2025` `defunion` type name) and at none of the `defstruct` field names
(`:1862`), the `defunion` arm names and `%s_%s` enum tag constants (`:2044`,
`:2056`, `:2066`), or `emit-cheader-declare`'s prototype name (`:1938`, which
routes through `ns-ir-base` for the namespace prefix but never through
`sanitize-for-c`). **The fix is a missed call site, not a missing mechanism.**
It breaks C interop for any hyphenated name, which is most of them.

> **Fixed 2026-08-10; the census above was three sites short and its
> one-line conclusion is wrong for half the surface.** See the W9-4 note below.
> Also missing from it: `defconst` `#define` names, `defenum`'s own tag name and
> its members, function *parameter* names, and the inline `(union …)` member
> names `type-node-to-c` emits. And "a missed call site" holds only for names
> nothing links against — for a `defn` it is a *ruling*, taken by item 3.

### W9 item 46 as fixed *(2026-08-15)* — the rule was already written down, in a comment, one function away

**The fix is two `qualify-name` calls, and the interesting part is why it was
only two.** `emit-defunion` had already stated the contract, in a comment above
the very lines this item is about:

> `defunion-register` is handed the canonical KEY (it registers the backing
> StructDef and the UnionDef under it); `union-ctor-form` below is handed the
> SOURCE spelling, because what it builds is source — a `(defn Shape-circle …
> Shape (make Shape circle …))` form re-parsed in this same file, where the bare
> name resolves.

`emit-defunion-import` used the source spelling for **both**. Under `user` the
two are the same string and nothing shows; inside `(ns nsu)` the header's own
`prescan-struct-names` filed the backing struct as `nsu/Opt` while the UnionDef
went in as `Opt`, so `make` and `match` looked where nothing was. Applying the
comment to the second implementation is the whole type-level fix.

**The arm constructors needed nothing**, which the row had hedged on
("whatever the ctor-declare path needs to follow it"). Hand `union-ctor-form`
the bare spelling as the contract says, and `emit-nuch-declare-import` qualifies
the synthesized `declare` under the header's own `(ns …)` exactly as it already
did for an ordinary one — `declare i64 @w9nu__Opt-Some(i32)`, matching what the
library's object exports. That path was never the one keying wrongly; it was
downstream of the one that was.

**Item 40's `.nuch` residue then closed at the predicted size.**
`prescan-union-layouts` joins `prescan-struct-layouts` in
`prescan-nuch-signatures` — item 40 had to leave it out precisely because the
prescan keyed on `qualify-name` and the importer on the bare name, so enabling
it would have filed one union in two places. One further change was needed and
is the same one item 40 made for `emit-defunion`: the importer's skip could no
longer key on "a UnionDef exists", because the prescan now creates one, so it
keys on `ctors-emitted` — here meaning "the arm `declare`s are already in the
stream". That guard fails loudly in both directions, which is why the test
includes a diamond import: too eager and the declares vanish (link failure), too
lax and they double (invalid IR).

**Worth recording about the shape of this defect.** It survived because the
un-namespaced spelling makes the two keys the same string, so every existing
test and all 69 generated headers exercised the path and agreed. The control in
`run_w9_nuch_ns_union` pins that: a header with no `(ns …)` behaves identically
before and after, which is what keeps the fix a re-keying rather than a rename.
Measured additive across 242 corpus programs (0 IR diffs, 0 new errors, 0 changed
error texts), and verified to fail on the committed boot in both import orders.

**W9 closes here.** Item 23's "in part" was retired the same day as stale
bookkeeping rather than as work: its dispatch half was split out as item 35 and
fixed 2026-08-14, and re-probing confirms the acceptance case runs, the pair
emits distinct symbols, and a bare ambiguous call is refused with both candidates
named. Forty-seven found, forty-seven fixed.

### W9 items 42 and 47 as ruled and fixed *(2026-08-15)* — the ruling was free, and the item's worth was the question it made me ask next

Full write-up: `design/stage15-stress-test/implicit-conversions.md`.

**The ruling cost nothing, which is the first thing worth recording.** Item 42
asked whether a built-in widening may chain into a user `defcast`, recommended
C++'s "no", and budgeted "the cost is the rule, not the code". Measuring first
showed the compiler *already* refuses composition in every position — argument,
`as`, `let`/`with` init, explicit and implicit return. So the ruling confirmed an
invariant instead of imposing one, and the only defensible reasons are the ones
that survive that: composition turns a pair lookup into a **path search** over a
flat `Vector` scanned in registration order, and `lookup-cast-rule` has nothing
with which to rank two derivations; and a rule from the narrow type is spellable,
so the restriction costs one explicit `as` and makes nothing unreachable.

**The item's real content was the question the measurement forced.** To ask "can
an `i32` reach an `i64` rule" you first have to ask "where is the registry
consulted at all", and the answer was: from `safe-coerce-val`, which two of nine
typed slots call. The other seven call `coerce-int-val`, which knows every
built-in conversion and nothing about the user's. So a rule was refused **on its
own exact registered pair** by `let`/`with` init, both returns, `.set!`, `aset!`,
struct-literal fields and union payloads. Item 42's reported symptom —
"unreachable from an integer literal" — was the one corner of that visible from
an argument, the only position where rules worked at all.

That inverts the item. The literal was never the problem; it was the only part of
the problem that a working code path could show.

**The fix is one line at a chokepoint, and the discipline is which one.**
`coerce-int-val`'s *final* fallthrough now returns `coerce-via-cast-rule`. Three
things make that safe rather than merely short: it runs only where the function
already returned `null` — i.e. only where the caller was about to `die-at` — so
nothing that compiled before can change meaning (0 of 365 corpus programs moved a
byte); the earlier `(return null)`s, which refuse a *specific* pair rather than
reporting "no built-in applies", are left alone; and `safe-coerce-val`'s inline
copy was deleted rather than duplicated, so the argument path stays
byte-identical. The tempting simplification — route the other slots *through*
`safe-coerce-val` — is the one to refuse: its equal-type-**kind** short-circuit
would let a `(ptr Foo)` value initialize a `(ptr Bar)` binding.

Nine hand-wired call sites is how the defect was built in the first place. One
chokepoint is why a tenth slot added later inherits the behaviour.

**A ruling nobody can observe is indistinguishable from a bug**, which is the
part item 42 was actually filed for. `examples/implicit-cast.nuc` claimed a cast
fired for its entire existence and never did. So a failure that a rule *almost*
covers now names it:

```
  note: a defcast rule converts i64 to ptr, but implicit conversions do not compose — write (as i64 …) on the operand to reach it
```

Fired only on a near miss — a rule whose `to` is this exact target and whose
`from` is not this source — so one `defcast` in a file does not grow a note on
every unrelated mismatch. The `as` position is where the old text was not merely
silent but wrong: `use unsafe/cast` throws away exactly the safety the `defcast`
was written to buy, with `(as ptr (as i64 0))` available the whole time.

The note rides `g-diag-note`, staged by the diagnosing site and rendered by
`die-at`/`report-at` after the error — the same mechanism `g-mono-context`
already uses, for the same reason: a note must follow its error and `die-at` is
`noreturn`. The alternative (nesting a `fmt-*` call into each `die-at` argument)
is safe on its own terms — I checked, the helpers `alloca` per-call buffers and
do **not** share one — but it makes five different message shapes each know the
note's wording.

**One incidental correction, worth more than the note.** The up-call this needed
crosses `abi.nuc` → `nucleusc.nuc`, which two entries in `conventions.md` and a
comment inside `coerce-int-val` itself call an unresolvable cross-import forward
reference. It compiled on the **committed boot compiler**, first try — as does
`union-registry.nuc`'s existing up-call to `intern-str`. The signature prescan
resolves these; the comments predate it. Their code is still fine, but the reason
given for it is stale, and this is the third hand-written ordering note in this
stage to go that way (see `toplevel.md`'s cycle table under item 40). Test an
import-order constraint with one call before inheriting the claim.

### W9 item 40 as fixed *(2026-08-15)* — three kinds, three different answers, and the split line is "does it write IR?"

**The row named three things that resolve on import order and treated them as
one defect. They are three.** Measured against the committed compiler before
touching anything:

| Below its import | Before | Cause |
|---|---|---|
| `(W9RBox 3 4)` — a struct literal | `struct literal: too many initializers for struct 'W9RBox'` | the prescan registers the NAME; `num-fields` is 0, so every initializer is one too many |
| `(_get b a)` — a field access | `_get: no field 'a' on struct 'W9RBox'` | same table, read the other way |
| `(defn f (v:W9RBox) …)` — by value | **compiles**, `define i32 @f(i0 %b.arg)` | `abi-classify` sizes an unlaid-out struct at 0 — a SILENT miscompile whose only symptom is an unlocated `failed to parse generated IR` |
| `(W9ROpt-W9RSome 3)` — an arm constructor | **works already** | `prescan-union-ctors` hoisted the ctor SIGNATURE in W1a; the row's `(W9RSome 3)` probe measured something else (a bare arm name is not bound — `docs/builtins.md`, one-symbol-one-kind) |
| `(make W9ROpt W9RSome 3)` / `match` | `make: type is not a defunion` | the `UnionDef` itself, which only `emit-defunion` creates |
| `(w9r-mac 5)` — a macro | `unknown: w9r-mac` | there is no registration to hoist; see the ruling below |

So the union half was **smaller** than the row recorded (constructors were never
the problem; the `UnionDef` was), and the struct half was **larger** — it
included a silent wrong-code path the row does not mention.

**The struct half: split the definer at the IR boundary.** `emit-defstruct` did
two things in one statement — parse the field declarations into
`struct-set-fields`, then print `%Name = type { … }` and set `emitted`. The first
half became `defstruct-fill-layout`; the second stayed. `prescan-struct-layouts`
calls the first, the emitter calls both, and **every type line is still written
by the definer, at the same point in the same stream**. That is what made the
change measurable rather than arguable: an old-vs-new `--emit-llvm` sweep over
`examples/` + `lib/` + `tests/fixtures/` (396 files) came back **0 new errors, 0
changed error texts over 160 rejecting fixtures, and 17 files with a diff — every
one of them a `%X = type` line moving within the type section, with the line
multiset identical**. LLVM named types are order-independent within a module, so
that class is inert; it is the same class `conventions.md` records for W1a.

**Why the layout pass is its own sweep, and why it is POST-order.** A field type
resolves against type NAMES, and pass 1 registers every reachable file's names —
so layouts need pass 1 finished and nothing else, and they can run in any order
relative to each other. What they *do* need is `defconst`s: an `(array T N)`
extent is a constant expression. So `prescan-struct-layouts` runs at the end of
`prescan-imported-signatures`' per-file block, **after** the recursion into that
file's imports, while signatures and value names stay pre-order where W1a and G-0
put them. Post-order buys the cross-file case for free — a library whose struct
is sized by a constant it imports lays out correctly — and costs nothing, because
nothing else a prescan registers depends on a layout. No file is read a second
time.

**A layout must be exact or absent, so the permissive branch abandons.** The
prescan diagnoses nothing (`conventions.md`: a prescan defers to the emitter), and
it must also never *guess*: a provisional length or a zero-sized opaque field
would give the enclosing struct wrong offsets, which is a miscompile rather than
a missing message. `defstruct-fill-layout`'s `strict` 0 therefore returns null —
leaving `laid-out` 0 — on a field with no `:type`, a by-value opaque C type, a
cycle-pending layout, or an extent that will not fold; `emit-defstruct` then asks
each question again with its own words and its own line. Reporting "not settled"
from three frames down needed a channel, because `parse-type-from-node` returns a
non-null `ref:Type`: `g-array-ok` gained **mode 3** ("fold if you can, else arm
`g-layout-defer`"), which also defers on a length that folds to something the
emitter would refuse, so no rejected layout is ever registered.

**`emitted` stopped being able to answer "has a layout", and the bit that
replaces it goes on the chokepoint.** `sdef-layout-pending` read
`emitted == 0 && num-fields == 0`, an approximation that was exact only while
emission was the one thing producing a layout (and that misdiagnosed a legitimate
`(defstruct Empty)` even then). `StructDef.laid-out` is set by
`struct-set-fields` — the single point every field-populating path funnels
through, `.nuch` replay and C-header parser included — so no builder can miss it.

**The union half needed the definer's own no-op guard re-keyed.**
`emit-defunion` returned early whenever a `UnionDef` for the name already
existed: correct while it was the only producer, and "the constructors are never
emitted" the moment a prescan produces one. `UnionDef.ctors-emitted` is the new
discriminator, exactly as `defstruct` keys on `StructDef.emitted`. Two smaller
things fell out of registering earlier: `g-defining-private` has to be armed
around the prescan's `defunion-register` (it is now the only chance a `defunion-`
gets to record its privacy), and a colon-annotated name (`U:i32`) has to be
skipped, because registering it reaches `check-ir-name-legal` before
`emit-defunion` reaches `reject-colon-in-def-name` and the wrong message wins —
`w4b-defunion-annotated` caught that within one test run.

**The macro half is a ruling.** A `defmacro` is not a registration. Defining one
resets the function-codegen state, opens fresh CT streams, emits a full function
body and materializes a JIT module — so there is no half of it that writes no IR,
and "hoisting the registration" would mean running an emitter from a prescan, in
modes (`--emit-nuch`, `--emit-cheader`) that deliberately have no streams open at
all. The alternative — defer the JIT to first expansion — moves a macro's
compilation into the middle of an unrelated function's emission, which is the
shape `conventions.md`'s "emitting a function mid-emission needs the worklist"
entry exists to forbid. The residue is small and self-announcing (`unknown: NAME`
at the use, with W1d's cycle note when the definer is in a cycle), and it is now
pinned by `w9-layout-macro-still-needs-import-above` so it reads as a decision
rather than an oversight.

**The defect the row does not mention, closed by the same change.**
`conventions.md` has carried, since W1d, a paragraph headed *"Latent, still
unfixed"*: the `i0` miscompile is reachable with **no import at all** —
`(defn f (v:S) …)` written textually above `(defstruct S …)` in one file. W1d
declined to ungate its cycle check for it. It is the same defect, and it fell to
the layout prescan without a line of its own, because neither shape is about
imports: `prescan-struct-names` registered a name and emission filled the layout
later, in both. `w9-layout-same-file-forward` compiles, links and returns 5 where
the committed compiler says `_get: no field 'p' on struct 'W9LayFwd'`.

**Three W1d pinning tests inverted, and were re-pointed rather than
re-baselined** — the precedent is `w1d-cycle-defconst-diagnosed` (retired by W8
G-0) and `w1d-cycle-prefix` (re-pointed by B2b), both recorded in the same test
function. `w1d-cycle-layout-diagnosed` / `-structlit-` / `-byval-` asserted the
`'S' has no layout at this point` rejection; the replacements assert the ANSWER
(11, 7 and 5), which matters most for the third, whose old failure was silent and
whose old test would have passed on a program that never called the function.
What stays diagnosed across a cycle is what only an EMITTER produces: a macro and
a `deferror` id.

**Two residues, both measured, neither hypothetical.** An `(array T N)` extent
that needs a macro to fold — `(array i32 (* K 2))`, since `*` is a prelude macro
and macros are registered by the emitter — defers to emission and keeps the old
requirement and the old misleading diagnostic; a plain `(array i32 K)` folds,
cross-file `K` included. And a `defunion` reached through a `.nuch` rather than
its `.nuc` source, which is **item 46**: `emit-defunion-import` keys the registry
on the bare name where every other definition-side probe uses `qualify-name`, so
a canonical-key prescan would file a namespaced header's union where its importer
never looks. That mismatch reproduces identically on the committed boot, so it is
a pre-existing defect this work measured, not one it introduced. The `.nuch`
spelling of a `defstruct` **is** covered — a header's `defstruct` reaches the same
`emit-defstruct` — which is why `prescan-nuch-signatures` gained the struct pass
and not the union one.

**Gate.** `make test` 691 PASS / 0 FAIL (six new: `w9-layout-below-use-runs`,
`-byval-classified`, `-same-file-forward`, `-nuch-below-use`,
`-emission-unmoved`, `-macro-still-needs-import-above`; three replaced as
described above). `make abi-test`, `make layout-test`, `make check-headers` (69
generated headers unchanged) green. `make bootstrap` moved and re-converged: the
stage1/stage2 diff was 52 lines, **all of them type definitions**, with an
identical line multiset — the reorder class `conventions.md` documents for W1a —
and after the standard converge cycle `build/nucleusc.ll == build/stage2.ll`
byte-identical.

### W9 item 45 as fixed *(2026-08-14)* — the message was already there; the test that would have raised it was the thing that crashed

**The row's census was short by two thirds.** It named four heads —
`(defstruct ())`, `(defunion ())`, `(defenum ())`, `(defprotocol ())` — because
those are what had been typed by hand. Probing `()` in the name position of
every top-level head, and in the operand positions beside it, found the crash in
**twenty-three** shapes across `--emit-llvm`, `--emit-cheader` and `--emit-nuch`.
The bare `(head ())` spelling the row used is the narrowest probe available:
half the heads have an arity guard that fires on a two-element form, so the name
position is never reached. `(defn)` is diagnosed; `(defn () (x:i32):i32 …)`
segfaults. Same for `defconst`, `defmacro`, `deferror`, `defcast`, `extend`.

**And its recommended fix was wrong in both directions.** The row proposed one
null guard at `reject-colon-in-def-name`, "the shared chokepoint all four
crashers call FIRST on their name node". Three of the four never reach it:
`defstruct` and `defunion` die in `prescan-struct-names` and `defprotocol` in
`prescan-protocols`, all three before any emitter runs — which is also why all
three crashed in the header modes, where no emitter runs at all. That guard was
still needed (it is what refuses five heads at once, in the words their own
arity guards use for an absent name) but on its own it would have fixed one head
of the four.

**The fix the class actually wanted is not a diagnostic.** Reading the twenty-three
sites turned up the same thing at each: *the message was already written.*
`(ns 5)` says `ns: namespace must be a symbol`; `(defenum E A 5 B)` says
`defenum: value must be symbol`; `(import 5)` says `import: name must be a
symbol or string path`; `(extend i32 5)` says `extend: protocol must be a symbol
or (Protocol args...)`. Every one of those is exactly what `()` deserves — and
every one of them is raised by a `(x kind)` test that dereferences the null
first. So the fix is one accessor:

```nucleus
(defconst NODE-NIL -1)
(defn node-kind (n:ptr):i32
  (when (= n null) (return NODE-NIL))
  (return ((as ptr:Node n) kind)))
```

`lib/node.nuc` already had the null-safe `node-line` and `node-is-list` for
exactly this reason; `node-kind` is the third, and `node-at`'s return type has
been `?ptr:Node` — nullable, and saying so — the whole time. Substituting it at
the sites that read a `node-at` result makes each site's own refusal fire, with
no new words to keep consistent and no ordering to re-decide. Where a site was a
PRESCAN rather than an emitter (`prescan-struct-names`, `prescan-file-imports`,
`prescan-defn-signatures`, `prescan-explicit-declares`, `prescan-union-ctors`)
the same substitution makes it *skip*, which is what conventions.md says a
prescan must do — the diagnosis stays with the emitter, at the source order the
author wrote.

Four positions had no message to fall back on and got one: a `defn`/`declare`
name (`defn: missing name` — the legacy-signature diagnostic would have quoted
it as `'(null)'`), a `defprotocol` method signature that is not a list, and the
five heads that route through `reject-colon-in-def-name`. The wording was not
invented: `repl.nuc:283` has said `defn: missing name` for its own unreadable
name since the REPL was written, and `require-defstruct-form` /
`require-defenum-form` say `<head>: missing name` for the name that is absent
rather than empty.

The **REPL** needed no change and got the fix anyway — it shares these emitters
and prescans. At `0dd0e34`, `(defstruct ())` typed at the prompt killed the
session; it now reports and the next expression evaluates.

**The header modes had to be re-asked, or the fix would have made them worse.**
Item 38's standard is that a header mode's *silence* is worse than its crash,
and eleven cells of the probe matrix moved SEGV → exit 0 the moment the prescans
stopped crashing: `--emit-cheader` would have written a header for
`(defstruct ())`. So `validate-header-forms` gained the same questions, routed
through the same owners — `reject-colon-in-def-name` for the five name heads,
`validate-decl-node` for `defvar`/`extern`, and three small extractions
(`require-defconst-name`, `require-defenum-member`, `require-import-name`) that
replace what had been an inline check in one emitter. The `defcast` entry is the
one that reads oddly and is right: it hands the null to `parse-type-from-node`,
the owner of `unable to parse type expression`, rather than repeating the words —
and leaves a non-null operand alone, because resolving a type there would ask a
question the pass has no import environment for.

**Measured, all three modes, 48 probe shapes:** zero crashes, and 44 of the 48
now produce a byte-identical diagnostic in `--emit-llvm`, `--emit-cheader` and
`--emit-nuch`. The four that do not are stated rather than assumed: `deferror`
(two shapes) reports and recovers instead of dying — item 38 excluded it for that
reason and this change keeps the exclusion; `def-rmacro` is a reader directive,
not a declaration a header describes; and `(defn f (x:i32):() (return 0))` is a
*body* type error, out of scope by item 38's ruling. None of the four crashes.

**Corpus: 396 programs, IR=0 DIAG=0 STAT=0, HDR=5 NUCH=4 — and every one of the
nine is the point.** Four fixtures with colon-annotated names —
`w4b-defstruct-annotated`, `w4b-defenum-annotated`, `w4b-defunion-annotated`,
`w4b-defmacro-annotated` — were silently *emitted* as headers before and are
refused now, in the same words `--emit-llvm` uses, because the header validation
routes through `reject-colon-in-def-name` exactly as the emitter does. The fifth
HDR diff is `w4b-defconst-paren`, and it is the one to read twice: the old
compiler emitted **`#define (null) 2`** into the C header — a name it could not
read, printed as the literal string `(null)`, in a file a C compiler is meant to
include. `emit-cheader-defconst` now skips a name that is not a symbol, so the
line is gone. The program is still *accepted* by both header modes (see the
residue below); what changed is that the header it writes is no longer invalid C.

A sixth diff existed briefly and was a real divergence this change introduced:
calling `require-defconst-name` unconditionally answered `(defconst K:(i32) 2)`
with `defconst: name must be symbol` where `--emit-llvm` says `defconst: takes no
type annotation; write (defconst K 2)` — two correct messages for one program,
which is the exact failure item 38 was fixed to prevent. The validator now asks
`defconst` only about a NULL.

**Residue, measured and left.** Two shapes are still accepted by both header
modes that `--emit-llvm` refuses, and both are the boundary item 38 drew rather
than new defects: a colon-annotated `defconst` name, because the message quotes
the constant's VALUE and the validation would have to re-derive it; and
`(export nosuch)`, because whether a re-exported name resolves is a whole-unit
registry question that only the emitter can answer. `export`'s *shape* is
checked, so `(export)` and `(export ())` agree across all three modes.

657 → 685 tests (28 new: 23 load-bearing against a compiler built at `0dd0e34`,
2 labelled controls that already refused there, 2 boundary cases, 1 negative
control), bootstrap byte-identical on the first pass, `make check-headers` 69/69
after regenerating `lib/node.h` and `lib/node.nuch` for the new accessor, abi /
layout / avr all PASS.

### W9 item 38 as fixed *(2026-08-14)* — the compiler has two validation layers, and a header mode runs only the permissive one

The row called the cause "structural rather than one missing check" and was
right. It located the structure one layer too low: *"the cheader pass walks the
form AST directly and reads `(node-at form N)` positions without the arity/shape
validation the real parser performs."* The real parser performs none either.

**What the compiler actually has is two validation layers, and the deferral
between them is deliberate and documented.** `defn-params-to-types` tolerates a
NULL parameter with the comment *"the located diagnostic is emit-defn's job"*;
`defn-params-count` says the same; `prescan-defn-signatures` skips a `defn` of
fewer than four elements without a word; `prescan-file-imports` skips an
unresolvable import with *"a missing library is diagnosed by `do-import`, at the
import form's own line. Staying silent here keeps one diagnosis."* Every one of
those is correct for `--emit-llvm`, where the emitter always runs and owns the
line. **The header modes run the prescan layer and never the emission layer**, so
nothing downstream ever asked.

That is why the row's four symptoms are **one** defect rather than four, and why
item 26 — which gave the pass the real prescans — fixed most of it and
structurally could not fix the rest: it added the layer that defers, not the one
that asks.

**The ruling the row asked for is the scope, and the boundary is real.** A header
mode refuses every program whose **declarations** the real pipeline refuses — not
every program it refuses. A body error is out of scope by construction: no body
is read in this mode, and checking one would mean running the emitter, i.e.
compiling the unit twice. Declarations are exactly what a header describes, so
that is the honest line. Measured over the 396-program corpus, `--emit-llvm` and
the header modes disagreed on **136** programs before and **133** after; all 133
are body-or-other errors, all 133 are `llvm=1 / header=0` and never the reverse,
and the three that closed are precisely the three crashes.

**The three fixtures were the shapes the corpus happened to contain, not the
defect.** The first version of this fix closed those three and passed every gate
— 644 tests, byte-identical bootstrap, 69/69 headers, 0 corpus diffs — and was
still substantially incomplete. Probing *every head the two header emitters
dispatch on*, rather than the three files that had been reported, found **ten**
crashing shapes: a truncated form of each of `defn`, `defstruct`, `defunion`,
`defconst`, `defenum`, and an inline aggregate reached through a pointer, an
array or a `defvar` type rather than a struct field — `(defstruct A (f (ptr
(union a:i32 ()))))` segfaulted because the first walk only inspected the
*outermost* head of a type node. Two silent-accepts came out of the same probe.
The lesson is the ordinary one and it cost a rewrite: when the defect is "this
pass never asks", the measurement is the *set of positions that never ask*, not
the set of bug reports.

**The fix is one walk plus one guard per definer, and every message comes from
the chokepoint that owns it.** `validate-header-forms` runs after the prescans
and *before any output*, so a refused program produces no partial header — what
`--emit-llvm` does with the same input. It asks: does each `import` resolve
(`die-import-not-found`, now shared with `do-import`'s two call sites rather than
a third copy of the words); is each declaration node non-null (`die-empty-decl`,
split out of `extract-name-and-type`'s null arm), recursing through pointer,
array and template heads so an aggregate nested at any depth is reached; and does
each definer satisfy its own arity rule. That last one is nine
`require-<head>-form` functions — each moved *verbatim* out of the top of its own
emitter, which now calls it. That is the part worth keeping: the alternative was
nine copied messages, which is nine chances to drift, and drift in exactly this
emitter is what item 26 fixed (a header declaring symbols no object defines).
Extracting them also turned up a copy nobody was looking for:
`emit-defunion-import`, on the `.nuch` replay path, carried the identical arity
check and message, so `require-defunion-form` has two emitter callers.
`deferror` is deliberately excluded, its check being a recoverable
`report-at`/`err!` rather than a `die-at`; and `emit-defvar`'s two *other* uses of
its message are different questions (a null declaration after attribute
stripping, and trailing junk after the init), so they stay where they are.

Nothing re-derives a diagnostic, which makes "the header mode says exactly what
`--emit-llvm` says" a property of the construction rather than of a string
literal — and the tests assert stderr **equality between the modes**, never a
quoted message, for the same reason.

Two skips keep the walk from being *stricter* than the compiler, which is the one
way it could do harm. A bounded-generic template is skipped, because
`--emit-llvm` only checks its body when a call site stamps it. A parametric
`defstruct` is skipped, because it defines no concrete type and its fields are
checked when it is stamped. Both are the same predicates the emitters already
skip on.

**`--emit-nuch` had the identical defect in its silent form, and it is the worse
half.** It never crashed — `emit-nuch-declare` `print-node`s a parameter rather
than walking it, and `emit-nuch-ret` returns early on a null return node — so on
the same three fixtures it exited **0** and wrote `(declare foo ((x i32)))`, a
declaration with no return type, and `(defstruct Row … (union as-int:i64 ()))`,
re-exporting the malformed member verbatim. A crash is loud; a `.nuch` that
describes a program which does not compile gets committed and linked against.
Same walk, same call site in both header emitters.

**One documentation claim was false in both directions.**
`docs/compiler.md` asserted that "header emission resolves the whole unit's
signatures, so a source that does not compile produces the compiler's ordinary
error rather than a header". That overclaimed before this fix (three shapes
crashed, one exited 0) and would still overclaim after it, because of the body
boundary. It now states the boundary, with both halves shown — including the
case where the header mode succeeds and an ordinary compile fails.

**One thing this probe found is NOT item 38, and is filed rather than folded in.**
`(defstruct ())`, `(defunion ())`, `(defenum ())` and `(defprotocol ())` segfault
under plain `--emit-llvm` — the *real* pipeline, on a compiler built at `447e25f`
and on this one alike. Item 38 is a header mode diverging from the real pipeline;
this is the real pipeline being wrong, with four distinct crash sites and its own
gates. It is **item 45**, with the shared chokepoint (`reject-colon-in-def-name`,
which every one of the four calls first on its name node) recorded there.

**Verification.** 657 tests pass, 0 fail (637 at `447e25f`; 20 new). Twelve of the
thirteen probe cases and all four original symptoms were checked against a
worktree at `447e25f` and fail there — the fixtures exit **139 with empty
stderr**, the unresolvable import exits **0** having printed an 8-line C header
and a `.nuch` declaring a function. Three of the twenty are deliberately *not*
load-bearing and are labelled as controls in the test file: a valid unit with an
inline union and a `&where` template still emits both headers, a body error still
succeeds, and `:(union a:i32 ())` in a return position was already refused
correctly at baseline. Bootstrap byte-identical on the first pass — twice, across
both versions of the fix. `make check-headers` 69/69, the strongest evidence
against over-reach, since every real library still emits an identical `.nuch`
*and* `.h`. `abi-test`, `layout-test`, `avr-test` pass. Corpus of 396 programs
against the baseline compiler: 0 IR, 0 diagnostic, 0 exit-status and 0
generated-C-header differences, with the only `.nuch` differences being the three
fixtures whose malformed header is now refused. **Every `--emit-cheader` /
`--emit-nuch` crash known to this item is gone, and no corpus program crashes in
either header mode.**

### W9 items 43 and 35 as fixed *(2026-08-14)* — the audit came back clean, and the work was one layer down

Taken together because they are one ruling with one audit under it: item 43 is a
definition being silently **overruled** by a prefixed import, item 35 is two
definitions being **refused**, and both sit on B4's deferred §9.6 note that "a
bare generic reference reaches namespaces the file imported PREFIXED … wants its
own audit of every `Method` writer first".

**The audit was the cheap part, and its result is the first finding.** Five
`(new Method)` sites. Two never enter a `Generic.methods` vector at all — a
synthetic `imp-src` in `derive-closure-conformance`, and `with-drop-method`'s
`@__boxedfn_drop` short circuit — so `method-in-ns` can never see them, and they
are out of scope by construction rather than by inspection. Of the three that
register: `build-generics` leaves `src-ns` null *deliberately* (an intrinsic
operator seed belongs to no file, which is why `+` must keep working in a
namespaced file that imports nothing), `generic-register-method` writes
`g-current-ns` at the definition, and `generic-instantiate-in` re-owns the stamp
to the template's. B4 had already corrected the only two writers that were
wrong; no third appeared. §9.6's own rule — *when a field starts being read as
provenance, audit every writer* — had been fully paid.

**So the filter is small.** `generic-lookup-ref`'s bare path returns the generic
filtered by `ns-reachable-bare`: the current namespace, each namespace this file
flattened, `user`. That is `name-ref-key-at`'s three slots stated as a
*predicate* rather than as keys, and it must be a predicate because a generic is
the one registry R2 keys BARE — there is no per-namespace key to withhold, so
the environment is applied to the method SET instead. `g-ns-declared == 0` is the
same byte-identical hatch `globals-lookup-ref` and `name-ref-key-count` already
take, and it is why this compiler and every program in `lib/` are untouched.

**The real work was that a monomorphized template body was resolved in the
CALLER's import environment.** The filter broke `b4-qualified-template`, and the
first question was whether the filter or the test was wrong. Measured against a
`HEAD` worktree, the test was passing **by accident**: its template body calls a
bare `b4-zero` that happens to have two overloads, and a merged bare-keyed
generic resolved from anywhere. Delete one overload and the identical program
fails on `HEAD` with `unknown: bz4 — not defined anywhere in this compilation
unit` — because a *solitary* name, or a global, goes through
`globals-lookup-ref`, which has filtered since B2b. Whether a library's template
could call its own namespace's functions depended on **how many overloads the
callee happened to have**, which is the least principled predicate available.

`MonoJob` was the one deferred-work record carrying no environment. `DynAnnot`
carries `ns`/`path`/`imports` and `InitJob` carries `ns`/`path`/`line`, both with
the same stated reason — the drain runs later — and both were written for
questions whose answer is the *asking* file's. A stamped body is the reverse: it
is the library's text, so the three restored globals are the **template's**,
recovered from `Method.src-ns`/`src-file` plus a new `Method.src-imports`
captured beside them. `drain-mono-worklist` now saves and restores exactly what
`drain-dyn-annots` does. This is the argument `g-emitting-copy` and B4's `src-ns`
re-ownership already make about a stamp's *linkage* and its *namespace*, carried
one layer further into where its names are looked up. It also fixed a
misattribution nobody had filed: an error in a template body was reported at
`<caller>.nuc:<library line>` — in the probe program, a line the caller does not
have — and reported the resolution failure the wrong environment caused instead
of the type error actually in the body.

**Item 35 then costs one guard, one message, and a key that had rotted.** R4's
eager check becomes conditional on `methods-share-symbol-space`, which compares
the emitted **ir-prefix** rather than the namespace *name* — the reason
`generic-user-methods-with-prefix` already gives, that two namespaces which
`set-ir-prefix` to one string genuinely share a symbol space and a pair there
really would emit one `define` twice. Stating the concrete harm instead of a
proxy for it is what lets the guard be relaxed safely.

The rotted key was not predicted by either row and is the finding worth keeping.
Allowing two namespaces to own one signature means `(name, param-types)` stops
identifying a method **on the definition side** — and `defn-ir-name` asked
exactly that pair, so both files emitted `define @qa__describe` and LLVM rejected
the second: a duplicate symbol produced by the change meant to give them two
distinct ones. `generic-find-method-exact-in-ns` adds `src-ns`. A *reference*
keeps the two-part lookup deliberately, because it asks which method to CALL and
answers that with the visibility filter plus overload resolution. The general
shape is §9.6's finding one level up: *when a field starts being read as
identity, audit every key that was unique only because it could not vary.*

**Where the refusal went.** `generic-resolve`'s tier 0 had been silently keeping
the LAST of several exact matches; it now reports the pair, naming both with a
spelling that resolves, at the first ambiguous use. And because item 43 turns a
silently-wrong call into an *unresolved* one, the unqualified-and-unreachable
case needed its own diagnostic tier — "not defined anywhere in this compilation
unit" is a lie about a name defined twice in it.
`generic-in-other-namespace-message` is the generic analogue of B3′'s
`type-in-other-namespace-message`, placed ahead of `unreachable-definer-file` on
the ground that a fact about a definition in *this* unit beats a same-named file
the import graph never reaches. It names both namespaces when two answer, which
is where item 35's "name both candidates" is actually delivered.

**One expected residue measured as working.** A template declared in a `.nuch`
and instantiated from a separately compiled object was assumed to have no
environment to restore. It does: `src-imports` is captured wherever
`src-ns`/`src-file` are, and a header replay reaches `register-generic-template`
through `prescan-nuch-signatures` with the header file's own environment already
filled. Pinned as `w9-template-nuch-separate-compilation` rather than assumed —
it fails on `HEAD` with `unknown: tz-solo`.

**Measurements.** `make bootstrap` byte-identical on the first pass; 637 PASS /
0 FAIL (623 before, so 14 new); `abi-test`, `layout-test`, `avr-test` and
`make check-headers` (69/69) all pass; a `HEAD`-worktree compiler and this one
emit `diff`-identical IR, diagnostics, exit status **and generated C headers**
for all 396 programs in `examples/` + `tests/fixtures/` + `lib/`, with item 38's
three `--emit-cheader` segfaults unchanged in count and identity. One in-tree
diagnostic moved, deliberately: `b5-did-you-mean-not-echo`'s program is item 43's
own shape, so it now reaches the new tier and gets the fact ("defined in
namespace 'b5s'") ahead of a guess. Defect #9 — that the offered spelling is
qualified and is never the one that just failed — is unchanged and is what the
re-pointed test asserts. Full account in
[name-resolution.md](name-resolution.md) §9.8.

### W9 item 39 as fixed *(2026-08-14)* — the codebase had already ruled; the defect was that the ruling was applied in one layer only

The row offered two answers — "reject a digit-leading name with a located error"
or "quote it (`@"2fast"`)" — and the fix took neither, because a third answer was
already in the tree and had been since SM-1. `ir-name-token` exists for exactly
this problem: `?` and `!` are legal in a Nucleus symbol and illegal in an LLVM
identifier, so they are **mangled** (`?`→`_QMARK`, `!`→`_BANG`) and `(defn even?
…)` compiles, links and is documented as working. A leading digit is the same
class of problem — legal in the reader, illegal in LLVM — so it gets the same
answer, in the same function. Rejecting would have left the language inconsistent
with itself (`even?` accepted, `2fast` refused, both Nucleus symbols LLVM cannot
spell); quoting preserves the exact spelling but leaves C unable to name the
symbol as an identifier at all, and would have to be carried at every print site.

**The row's scope was the bigger error.** Probing every position a name can
occupy, rather than the `defn` the row names, found that `ir-name-token` is
applied at the GLOBAL-symbol and type-name layers only:

| position | `?` / `!` | leading digit |
|---|---|---|
| `defn`, `defvar` name | mangled | **raw** |
| `defstruct` / `defunion` type name | mangled | **raw** |
| parameter | **raw** | **raw** |
| `let` / `with` binding | **raw** | **raw** |
| `match` binder | **raw** | **raw** |
| `label` / `goto` target | **raw** | saved by the `lbl.` prefix |
| `defconst`, `defenum`, `deferror` | n/a — compile-time, no IR name |

The `?`/`!` column is not latent the way the row's digit case is. `?` in a name
is documented as working, so this is a live failure a user reaches by following
the docs, and it prints its own indictment:

```
define i32 @add_QMARK(i32 %ok?.arg, i32 %n!.arg) {
```

— the function name mangled, the parameter three tokens away from it not.

**Where the fix went.** The row said "the fix belongs at the ir-name layer",
which was right; the layer just had two holes rather than one.

1. `ir-name-token` now knows LLVM's *first-position* rule (`[%@][-a-zA-Z$._][-a-zA-Z$._0-9]*`
   — the leading character may not be a digit) as well as its character class,
   and prefixes one `_`. The fast path is untouched for every name that starts
   with a letter and has no `?`/`!`, so the bootstrap stays byte-identical.
2. Every producer of an LLVM **local** now applies it: `abi-print-param-to` and
   `abi-emit-param-prologue` (which must agree, being the two spellings of one
   `%<param>.arg`), six `%<binder>.addr.N` sites in `union-emit.nuc`,
   `emit-let` / `emit-with` / the drop-handle slot, the macro prologue, and all
   five producers of `%lbl.<name>` (`emit-label`, `emit-goto`,
   `emit-label-addr`'s `blockaddress`, `emit-goto-ptr`'s `indirectbr` list).
   `scope-define` still keys on the **source** name at every one of them; only
   the emitted slot string carries the escape.

**`sanitize-for-c` is deliberately unchanged.** C has the identical
first-position rule, and the first instinct was to add it to the blanket
character map — but that map is also used on *fragments*. `cheader-c-ident-join`
already documents the right placement for the reserved-word escape ("the escape
belongs on the join, not on either part"), and the same holds here: `2circle`
joined after `_2Shape_` is not at position 0, so escaping it there spells
`_2Shape__2circle` for a name `_2Shape_2circle` already satisfies — and `__` is
reserved to the implementation in C++, which these headers target through
`extern "C"` (item 28's reasoning). So `cheader-escape-leading-digit` sits beside
`cheader-escape-reserved` inside `cheader-c-ident`, the documented chokepoint for
every *complete* identifier the emitter prints.

**Why `_` on both sides.** Using the same escape character for LLVM and for C is
what makes the C spelling and the link symbol agree, so `cheader-asm-label`
correctly emits nothing — the header reads `int32_t _2fast(int32_t _2n);` and
that name *is* the symbol. Choosing differently would have worked too, via an
`asm()` label, but only by inventing a second naming rule to keep in step with
the first. The known cost is the `_QMARK` cost exactly: a user's own `_2fast` now
collides, undiagnosed. `_2fast` is also, pedantically, a file-scope reserved
identifier in C (`_` followed by a digit); no implementation defines one, and
every alternative prefix trades that technicality for a likelier collision.

**A backstop, now unreachable.** `check-ir-name-legal` gained the position test
beside its character test, as a separate predicate (`ir-name-leading-digit`) with
its own message rather than a case inside `ir-name-illegal-char` — reporting a
digit as an "illegal character" would name a character the same message's list of
legal characters contains. `ir-name-token` escapes before emission, so this fires
only if some future path skips the transform, which is the point of a backstop.

**Measured.** Bootstrap byte-identical on the first pass — no name the compiler
defines starts with a digit, and none of its bindings carries `?`/`!`. Corpus of
396 programs: **0 IR, 0 diagnostic, 0 exit-status and 0 generated-header diffs**;
the 3 known `--emit-cheader` segfaults (item 38 residue) unchanged in count and
identity. 69/69 `check-headers`, abi/layout/avr green, 623 PASS / 0 FAIL (was
620). The three new cases were each run against a baseline worktree to confirm
they are load-bearing: both programs die there with the IR-parse error, and the
baseline header carries 14 illegal C identifiers and does not parse.

**The guard runs the programs.** Each case compiles, **links and runs** rather
than checking that the module parses, because parsing is not the claim — the
claim is that a `goto` still reaches its label and a `match` binder still reads
the field it was bound to *after both were renamed*. The header case links and
runs a C consumer against `_2fast` / `_2count` / `_2LIM` / `struct _2Pair` /
`_2Shape_2circle`, which is the only check that can show the C spelling and the
link symbol still agree.

### W9 item 44 as fixed *(2026-08-14)* — the recommended answer was right and the reason given for it was wrong

The row recommended "(a) skip the declaration with a comment", and (a) is what
shipped. But the argument it gave — *"the value is not an aggregate", "no header
can define `struct _BANGui8`"* — does not survive contact with the object file,
and the correction changes what the fix **is**.

`!ui8` is a real aggregate: `%Result.u8.Err = type { i32, %__anon_union… }`. The
`define i64 @strview-byte-at(ptr, i64)` the row cited as proof is nothing more
exotic than SysV coercing an 8-byte struct into RAX. Declared with the right
shape from C, it decodes correctly — measured against the committed object:

```c
struct ResU8 { int32_t tag; uint8_t v; };
struct ResU8 strview_byte_at(void* sv, size_t i) asm("strview-byte-at");
/* prints tag=0 v=65 */
```

So the defect is not "C cannot express this". It is that **`!T` is a
`(Result T Err)` template instance wearing a sugar spelling**, and
`--emit-cheader` has always had a ruling for template instances — refuse, and say
so. `lib/strview-str.h` carries `/* byte-find: uses a defunion-template instance
type; not exported */` two lines above where `byte-at` used to carry the bad tag.
The sugar escaped that ruling for one mechanical reason: `cheader-template-instance`
tests a `NODE-CELL` head against the union-template registry, and `!ui8` arrives
as a `NODE-SYM`. `niche-sym-to-c` answers null for it (it only knows the pointer
niches), and `type-name-to-c`'s "assume struct" fallthrough then names a tag the
emitter never defines.

That reframing is the third instance of one trap: **two renderers for one type
must give one answer.** Item 3 was `usize` (the Type-keyed `type-to-c` said
`size_t`, the name-keyed `type-name-to-c` said `struct usize`), item 25 was
`Char`/`Err`, and this is the same shape one level up — two *spellings* of one
type, `(Result ui8 Err)` and `!ui8`, reaching two different decisions.

**Why an omission still wins even though the layout is expressible.** Because the
tag the header printed invites the wrong guess, and the wrong guess is silent.
Completing `struct _BANGui8` the way its name suggests:

```c
struct _BANGui8 { uint8_t v; };   /* compiles, links, runs */
/* prints 0 — Nucleus reads 65 */
```

A declaration C trusts and gets wrong beats no declaration only if it is right.
This is W9 item 3's ruling for `defvar`, applied one position over. The way to
get these declarations *back* is the general feature the emitter is already
waiting on — a C typedef for a stamped template instance, which `(Result i64 i32)`
and `(Maybe T)` need identically — not a special case for the sugar.

**Scope was wider than the row's title.** The row is written about return types;
a `!T` **parameter** (`w44-takes`) and a `defvar` of `!T` emitted the same tag,
and `ptr:!ui8` emitted `struct _BANGui8*`. All refuse now. `?` comes free — the
predicate keys on the sigil, so `examples/value-maybe.nuc`'s `?!i64` is covered
without naming it.

**The exemption is the load-bearing half.** `!ptr:T` / `!ref:T` are niche-encoded
*in the pointer* (unions.md §6 rule 3), so the whole value is a bare `T*`. Over-
skipping would have silently deleted working declarations, and a grep over the
header cannot tell a kept declaration from a plausible one — so that case is
gated by compiling, linking and **running** a C consumer through
`w44_find` / `w44_show` (`7 9 7`).

**One bonus, and it is item 37's lesson paying off.** `emit-cheader-declare`
refuses a declaration on any *one* of its signature positions, so a type named
only by a refused declaration is not a dependency of the header — but item 37's
include pre-pass asked the question per type *node*, which cannot see a
whole-form refusal. Hoisting all four refusals into one `cheader-defn-skip-reason`
gave both callers the same answer and dropped a surplus `#include "lib/keyword.h"`
from `examples/dyn-protocol.h`, a header that spells no `struct Keyword`
anywhere. The emitter still prints a per-class comment; it just no longer decides
the class twice.

**Measured**: exactly the 5 committed headers / 14 declarations the row
predicted, plus 7 corpus headers of the same class; 0 IR / 0 diagnostic / 0
status diffs over 396 programs; bootstrap byte-identical first pass; all 34 lib
headers still compile standalone; the 3 known `--emit-cheader` crashes unchanged
in count and identity; 620 PASS / 0 FAIL.

*(Two small residues measured while doing this, neither a new defect. The
unreachable-file note picks whichever of `lib/vector.nuc` / `lib/vector.nuch`
readdir yields first — a byte-for-byte corpus diff between two checkouts of the
same commit shows `.nuc` in one and `.nuch` in the other, from directory order
alone. Both are true, so it is cosmetic nondeterminism rather than a wrong
answer, but it will defeat a diff-based test that spans directories. And
`--emit-cheader` accepted `(err ERR-RANGE)` for an `ERR-RANGE` that does not
exist, which `-c` rejects — item 38's family, already recorded.)*

### W9 item 37 as fixed *(2026-08-14)* — the include set is what the header NAMES, and the provenance to compute it was not being recorded

The row proposed two answers and rejected both, correctly. `#include
"prelude.h"` from the import list *"presumes a filename and a search path the
Nucleus import never had"*; a forward declaration *"is enough for a pointer but
not for the by-value field this actually is"*. The third answer is narrower than
the first and stronger than the second: **include the header of the unit that
DEFINES each type this header actually names**, and spell it by the convention
the build already commits to — `lib/%.h: lib/%.nuc`, a generated header beside
its source, which is exactly what a *quoted* include resolves against.

So there is no invented search path. A sibling is named by basename alone
(`#include "prelude.h"` from `lib/string-split.h`), and a defining unit in
another directory keeps the path as the compiler resolved it (`#include
"lib/prelude.h"` from a header generated for `examples/`), which needs a
matching `-I` and says so in the docs rather than guessing.

**The chokepoint made the set exact.** `type-name-to-c`'s fallthrough — the
"assume struct" arm that items 3 and 25 both had to teach about scalars — is the
single place a reference to a user type is spelled. Recording there means the
include set is the set of references the header *emitted*, never the import list.
The difference is not cosmetic: of the 34 `lib` headers, **5** name a type they
do not define, and 5 are what changed.

**Two supports were missing.**

1. `StructDef.src-file` was uniformly **null** in this mode. Every writer of it
   is a *definition-time* writer, and `--emit-cheader` emits no struct — even
   this file's own types were null, so "is it external?" was unanswerable. The
   fix belongs where the row's own §"source file where defined" comment already
   pointed: `prescan-struct-names` now records `src-file`/`src-line` at name
   pre-registration. `prescan-imported-types` already swaps `g-source-path`
   across a file boundary, so an imported type carries its own file's path with
   no further plumbing. The only pre-existing consumer, `reject-opaque-type`,
   reads it solely for `opaque` StructDefs, which only the C-header parser mints
   and which already set it — hence 0 diagnostic diffs corpus-wide.

2. The `#include` must precede the first use, but the recording happens during
   emission. A pre-pass over the signature positions calls the same
   `type-node-to-c`, purely for the side effect, before the preamble is printed.
   It re-reads the positions the emitters read; it does **not** re-implement what
   they do with them, so the worst a drift can cost is a missing or surplus
   include, never a wrong type.

**The pre-pass had to replicate the emitters' skips, and that is where the first
version was wrong.** A rule that scans every signature is over-eager in a way a
compile-test cannot catch: `lib/vector.h` and `lib/combinators.h` gained includes
while spelling **no `struct` at all** — the first from a parametric
`(defstruct (Vector T) …)`'s allocator field, the second from the `String` return
type of a generic template. Both forms are skipped by the emitter at its first
line, so neither names a dependency of the header. Four tests — generic template,
parametric head, template instance, closure/erased box — took the change from 10
headers to 5, i.e. from "the imports, roughly" to "the references, exactly". The
`-` (private) spellings are absent from the scan for the same reason they are
absent from `emit-cheader-header`'s dispatch.

**What the measurements were.** 5 committed headers change and each gains only
`#include` lines; all 34 lib headers compile standalone, where `string-split.h`
did not; 396-program corpus at 0 IR / 0 diagnostic / 0 status diffs; bootstrap
byte-identical first pass; the 3 known `--emit-cheader` crashes unchanged in
count and identity; `make check-headers` green after regeneration. The C side is
asserted by linking and *running* a consumer that copies an imported struct by
value — a grep cannot tell a correct include from a plausible one — and by
stripping that one line back out and watching `field has incomplete type 'struct
Pt'` return, which is the original defect verbatim.

**Two things it deliberately does not cover**, both now documented: a type from a
**C** header gets no include (the consumer already reaches it through whatever it
includes for that header), and an **`!T` return type** still exports as `struct
_BANGT`. The second separates cleanly rather than by luck — `struct-lookup-ref`
answers null for `!ui8`, because no unit defines it, so nothing is recorded and
no misleading include is emitted. It is filed as item 44 with its own
measurement: the IR returns `i64`, so the declaration is wrong about the ABI as
well as about the tag.

### W9 item 36 as fixed *(2026-08-14)* — the discriminator was WHERE the declaration is written, not what it says

The skip is one line, and its comment says what it is for: *"Skip if already
defined (e.g. from include or c-include)."* Idempotence. What it could not
distinguish, in the item's own words, is *"a re-declaration of the same function
from a different function that happens to share the name"* — so a `.nuch` entry
whose name the importing unit also **defines** was dropped whole: no `g-globals`
binding, no LLVM `declare`, no generic method. Measured pre-fix, and the reason
this is a W9 defect rather than a limitation:

```
(import "w36lib.nuch" lib2)          ; library: helper (x:i32):i32
(defn helper (x:i64):i64 …)          ; the unit's own, a different function
(lib2/helper 3)   →  call i64 @helper(i64 %t1)      ; no diagnostic
```

A **qualified** call, naming the library, reaching the unit's own function, at a
type the library's never had, silently.

**The obvious discriminator is wrong, and the test suite is what said so.** The
first implementation compared signatures — arity, parameter types, return type,
structurally, since `type-eq` calls any two `TY-FN` equal (Stage 13 L7). It
passed the 396-program corpus at 0 diffs and passed the bootstrap. It also broke
`w1-declare-cycle-breaker` and `w1-declare-plus-import`, whose own comment had
already written down why: *"EVERY such declare matches a reachable defn —
`emit-nuch-declare-import`'s 'already in g-globals' early return is what keeps
that a no-op instead of a duplicate."* W1e's cross-file cycle-breaker is a
declaration of a function the unit **does** define, and it is entirely correct.

A definition test alone is wrong for the same reason. What separates the two is
**provenance**:

| the declaration is written in | what it can be | ruling |
|---|---|---|
| a `.nuc` file (top-level `declare`) | a forward declaration *of* this unit's function — W1e's cycle-breaker | no-op, unchanged |
| a `.nuch` header | some **other** unit's exports | a name this unit defines is a conflict |

That holds by construction, not by luck: **`--emit-nuch` never re-exports a
top-level `declare`** (measured — a `.nuc` with both a `declare` and a `defn`
exports only the `defn`), so a header entry can never *be* a forward declaration
of the importing unit's own function. The second question — does this unit
define the name — is what keeps the libc diamond silent, since only a `defn`
carries a body and a C-header import has none.

**The same-signature half is the one that proves it.** `run_w9_nuch_import_order`
already contained this exact program, written while item 29 was fixed and
labelled *"item 36's behaviour, unchanged"* — a header declaring
`w9no-add ((a i32) (b i32)) :i32` and a unit defining it with the **identical**
signature. A signature comparison cannot see that case at all; the provenance
test reports it. The test now asserts the error and is renamed
`w9-nuch-local-definition-reported`.

**Measured.** Ten skips fire across the whole corpus — `lseek` ×3, `strlen` ×2,
`strdup`, `strcmp`, `strchr`, `popen`, `pclose` — every one a libc function
declared by both a C header and a `.nuch`, none of them defined by any `defn`,
and (instrumented separately) every one signature-identical. So the accepting
path is untouched by construction and by measurement: **0 IR diffs, 0 diagnostic
diffs, 0 status changes over 396 programs**, `stage1.ll == stage2.ll` first pass,
and the 69 committed `lib/*.nuch` + `lib/*.h` still match.

**The diagnostic names both sites and the way out**, and the way out is verified
rather than asserted — `w9-nuch-namespaced-library-coexists` links and runs it:

```
w36lib.nuch:2: error: declare 'helper': this compilation unit already defines 'helper', at w36use.nuc:3
  note: the header declares helper(i32):i32, the unit has helper(i64):i64. One name is one
  key here, so nothing — not even a qualified call — would reach the header's. Rename one,
  or give the library an (ns ...) so its exports key and link under it.
```

Filed beside it as **item 43**: chasing the namespaced escape route measured
that adding a *prefixed* import silently changes what a **bare** call in the
importing file resolves to. That is B4's deferred §9.6 audit, pre-existing, and
independent of this fix.

### W9 item 34 as fixed *(2026-08-14)* — a guard that compared LOWERED types asked a question the language never asked

`emit-call-with-args`' coercion guard was
`(!= (strcmp (type-to-ir (slot type)) (type-to-ir ptype)) 0)`. Every pointer
flavour lowers to `ptr`, so `CStr`, `raw`, `(ref T)` and `(fn …)` were all the
same string and the coercion below — including item 33's brand-new error — was
never entered for any pair of them. The fix is one word in the guard and one
line in `safe-coerce-val`:

* the guard asks **`type-eq`**, which is the question the rest of the compiler
  asks. It already knows the identities the string comparison was standing in
  for (any two `TY-FN` are equal, and a bare fn equals a `(ref fn)`), so what
  newly arrives below is exactly the pairs that genuinely differ;
* `safe-coerce-val`'s final `(return null)` becomes
  `(return (coerce-int-val v target line))` — the chokepoint every *other* typed
  slot funnels through. It already knew CStr↔ptr is free, that the literal
  `null` reaches a fn slot (item 20) and that a loaded data pointer does not.

**The ruling the item asked for was already written**, in `coerce-int-val`, and
had been since item 20. Nothing new had to be decided about what "the same type"
means once `ptr` has erased the distinction — the argument position simply had
to stop answering it on its own.

**The item understated the hole, and item 20's own matrix is the measurement.**
That matrix ends with "**argument** `(take null)` — 'OK' — still unchecked", and
unchecked turns out to mean *all eight rows*:

| into a `(fn i32)(i32)` slot | argument, as filed | after item 33 | after item 34 | `let`, throughout |
|---|---|---|---|---|
| `null` | OK | OK | OK | OK |
| a `CStr` | **OK** | **OK** | refused | refused |
| a `ptr` | **OK** | **OK** | refused | refused |
| a `raw` | **OK** | **OK** | refused | refused |
| a `(ref T)` | **OK** | **OK** | refused | refused |
| an int literal | **OK** | refused | refused | refused |
| a string literal | **OK** | refused | refused | refused |
| a real fn value | OK | OK | OK | OK |

The two middle columns are the split, measured rather than reasoned: an int
literal and a string literal in a function-pointer parameter are not
pointer-flavour confusions at all (`i32` and `%StrView` against `ptr` — different
IR strings), so the old guard *did* fire for them and item 33's error alone
closed those two rows. The four that lower to `ptr` needed item 34. Item 20's
matrix recorded the whole column as one word, "unchecked", and it was two
defects.

**It had a second half nobody had filed.** Two types that lower to the same
string but differ in **sign** were never compared either, so the literal range
check (LW-4) that every other slot performs was unreachable from an argument:

```lisp
(take-ui32 -1)          ; passed 4294967295, silently
(let (a:ui32 -1) …)     ; integer literal -1 does not fit ui32
```

Now both say the same thing. This is the third time in three items that the
argument position turned out to be the one slot not asking a question the
language had already settled (33: `int`↔`float`; 34: fn slots, then literal
range) — the shared cause is that it had its own coercion entry point rather
than the shared one.

**Evidence.** Corpus (396 programs): **0 IR diffs, 0 diagnostic diffs, 0 status
changes** — every pair that newly reaches `safe-coerce-val` in real code is
answered identically, with no instruction. `make bootstrap` held the fixed point
on the first pass and no `boot/` artifact moved. Tests 602 → **606 PASS / 0
FAIL**; `abi-test`, `layout-test`, `avr-test` (8 units incl. simavr) green. The
gate is a **parity** assertion rather than a list of expected messages: each of
the eight spellings is compiled in an argument and in a `let` and the two
verdicts must agree *and* match the expected one — parity alone would still hold
if both positions regressed to accepting everything.

### W9 item 33 as fixed *(2026-08-14)* — five lines of diagnostic, and the two defects the silence was hiding

**The fix is the shape the return site already had.** `emit-call-with-args`'
coercion loop called `safe-coerce-val` and dropped a null return, with a comment
saying so ("no safe conversion exists, the argument is left untouched —
preserving the prior pass-through behavior"). `emit-return` does the same call
against the declared return type and *reports* it (LW-3: check null, `die-at`
with both `type-spelling`s). Item 33 is that check, in the other position:

```
f-f64: argument 1 has type i32, which does not match parameter type f64
```

**The item's examples understate it.** All three it lists — an int into a `ptr`
parameter, a `CStr` into an `i32`, a float literal into an `i32` — are
deliberate type errors that a reader would expect to be refused. Measured, the
loop was also swallowing this:

```lisp
(defn takes-f64 (x:f64):void (printf "got %f\n" x))
(takes-f64 3)          ; => call void @takes-f64(i32 3)   ; prints 0.000000
```

`int`↔`float` is in the coercion set in **neither** direction, and every other
typed slot already refused it — `(let (a:f64 3) …)` is `let: init type mismatch`.
So the argument position was the sole outlier, and this is a consistency repair
rather than a new rule. That also settles the ruling the item did not pose:
report, do not widen. Making `(take-f64 3)` *work* is a different change
(int-widening.md's territory) and it would have to move `let` with it.

**One line of error surfaced two defects that had been invisible.** This is the
finding, and it generalizes: a silent pass-through does not only hide the
program's bug, it hides the *compiler's*. The corpus sweep found exactly three
programs whose acceptance depended on the silence, and none of them was a wrong
call:

* `tests/fixtures/b6-dyn-box-mismatch-arg.nuc` and `examples/w9-dyn-ns.nuc` were
  both boxed-receiver method calls — **item 41**, a `(dyn P)` dispatch that
  bypasses the vtable whenever the method has one conformer. Fixed with this
  change, because leaving it would have made canonical `(dyn P)` code stop
  compiling. It had been returning the *right answer* by luck, which is why
  nothing caught it; a method with a second parameter reads the box's vtable
  word as that argument, and that is the witness the fixture uses.
* `examples/implicit-cast.nuc` was calling `(show-ptr 0)` under the comment
  "defcast fires: i64 → ptr via id_to_ptr" — **item 42**. It never fired: the
  literal is `i32`, the rule is keyed `i64`, and the emitted call was
  `call void @show-ptr(i32 0)`. An *example whose purpose is to demonstrate the
  feature* had been documenting behaviour it did not have.

**Evidence.** Corpus (393 programs, pre- vs post-): **233 accepted before and
after, 160 rejected before and after, 0 status changes, 0 diagnostics moved.**
The two IR diffs are both accounted for — `w9-dyn-ns.ll` is item 41's vtable
dispatch replacing a direct call (11 lines, one site), `implicit-cast.ll` is the
`(as i64 0)` source repair item 42 forced. `make bootstrap` held the fixed point
on the first pass and no `boot/` artifact moved: the compiler's own calls are
type-correct, so a swallowed failure never had anything to swallow — the same
reason self-compilation never caught this. Tests 592 → **602 PASS / 0 FAIL**;
`abi-test`, `layout-test`, `avr-test` (8 units incl. simavr) green, AVR image
sizes unchanged to the byte.

**What is still silent.** Item 33's `die-at` sits *inside* the `strcmp` guard,
so item 34 — every pair of types that lowers to the same IR string, never
compared at all — is untouched and is now the only silent argument path left.
`(take c)` with a `CStr` into a `(fn …)` parameter still compiles. Fixing 33
first was deliberate: it needed no ruling, and 34 does (what "same type" means
once `ptr` has erased the distinction).

### W9 item 32 as fixed *(2026-08-14)* — the one line, and the prediction it disproved

The fix is the line item 15 made possible, in the single home item 15 gave the
rule (`gep-index-ir`, `src/nucleusc.nuc`): widen by the index type's own
signedness rather than always `sext`.

```
t (if (< iw g-target-ptr-bytes) "sext" "trunc")            ; before
t (if (>= iw g-target-ptr-bytes) "trunc"                   ; after
    (if (= (is-unsigned (idx type)) 0) "sext" "zext"))
```

Reproduced before the change, not inferred: `(aref (unsafe/ptr+ buf 1) i)` with
`i:ui32` at `4294967295` returned `buf[0]` — the emitted `sext i32 %t to i64`
made the index −1. After it, the same program emits `zext` and *faults*, which
is the right answer: four billion elements past a 16-byte buffer is not an
address.

**That is also why the fixture is written the way it is.** A test whose failure
mode is a segfault reports a signal, not a claim. `tests/fixtures/w9-unsigned-
index.nuc` keeps both the correct and the sign-extended address inside a live
allocation — a `ui8` index of 200 against a pointer 60 elements in, so the wrong
answer is `[-56]` and the right one is `[+200]` and both are mapped — so a
regression reads a *wrong value* and returns a code that names the check. It
covers all three callers of `gep-index-ir` (`aref`, `aset!`, `unsafe/ptr+`), a
`ui16` at 40000, a **signed** index at −3 that must still reach backwards, and a
`usize` index that must still emit no instruction at all. Verified to fail on
the pre-fix compiler (exit 1, the first check) and pass after. The `ui32`-at-2^31
case that started the item cannot be written this way, so it is asserted on the
emitted instruction in `run-tests.sh` instead — with the `sext`-for-signed
assertion beside it, since a blanket `zext` would pass every other check here.

**The second caution was wrong, and that is the finding.** The item predicted
this "changes host IR wherever an unsigned index is used, so … will move the
bootstrap". Measured over `examples/` + `tests/fixtures/` + `lib/`, pre- vs
post-fix: **231 IR byte-identical, 2 differing, 160 rejected by both, 0
accept/reject changes, 0 diagnostics moved**. The two that differ are the new
fixture and `examples/avr-global-init.nuc`, and the total movement across the
whole corpus is **five lines, every one of them `sext`→`zext` on an unsigned
index**. The compiler's own IR is **byte-identical** — `make bootstrap` held the
fixed point on the first pass, and no `boot/` artifact needed regenerating.

The reason is worth keeping, because it is the same shape as item 31's and
points the opposite way. Item 31 moved the bootstrap because `i1` is *pervasive*
in the compiler — every comparison produces one. Item 32 does not, because the
compiler indexes exclusively with signed `i32` and with pointer-width `usize`,
and `usize` already matches the pointer so `gep-index-ir` emits nothing for it.
An unsigned *narrow* index is a thing embedded code writes and a compiler does
not. **A fix's blast radius follows the type's idiom, not its call-site count** —
the same 22-call-site `is-unsigned` was read here through exactly one consumer.

The code-size claim in the item was exact. It recorded that dropping the
`unsafe/cast i64` workaround from `examples/avr-global-init.nuc` had *cost* 4
bytes on the ATtiny1634, "exactly the sign-extension of a `ui8` counter that
`zext` would not emit". Measured after: flash **942 → 938**, and the other four
AVR examples unchanged to the byte. The one line in that file's host IR that
moved is the same `ui8` counter — `sext i8 %t2 to i64` → `zext`.

Gates: `make test` 588 → **592 PASS / 0 FAIL** (the fixture plus three IR
assertions); `make bootstrap` PASS on the first pass; `make abi-test`,
`make layout-test`, `make avr-test` all green, the last including the simavr
run. Docs updated where the rule is stated — `docs/builtins.md`'s `aref` row and
`docs/avr.md`'s indexing bullet, which now records the 4 bytes as a reason to
prefer an unsigned counter rather than a hazard to cast around.

**Not covered.** The index rule is now signedness-correct, but it is still
unchecked — nothing diagnoses an index that is out of bounds, and nothing warns
when a `ui32` index is *wider* than the addressable space. Both are the
deliberate `unsafe/`-tier bargain, not residue of this item.

### W9 item 31 as fixed *(2026-08-14)* — one arm, and the sweep the item asked for

The fix is the arm the item ruled for: `TY-I1 (return 1)` in `is-unsigned`
(`src/type-utils.nuc`). `{0, 1}` is the only coherent reading of `i1`, and it is
already the reading `int-literal-fits` special-cases at width 1 (item 9) — the
two now sit together with a comment saying so.

**All three consumers moved at once, as predicted.** `(as i32 true)` and
`(as i64 true)` are `1` instead of `−1`; `(< false true)` and `(> true false)`
are both true instead of both false; and `(unsafe/cast f64 true)` picks `uitofp`.

**The item's caution was right about the bootstrap and wrong about the blast
radius.** It flagged 22 call sites, including `binop-result-type`'s
signedness-match test and generic parameter matching, and warned that this
"**will** move the bootstrap and needs its own sweep." It does move the
bootstrap — `make bootstrap` fails on the first pass by construction and needs
the documented converge cycle (`context/build.md` §"After a codegen change"),
which is the first W9 fix to need it. But the sweep is how the *size* of the
move became a fact rather than a fear:

- 405 programs (`lib/ examples/ tests/fixtures/ src/`), old compiler vs new:
  **226 IR byte-identical, 6 differing, 0 changed accept/reject status**, and
  the one new "compiles" is the new fixture.
- Every changed line in all 6 files, normalized: **24 `sext i1` → `zext i1`,
  and nothing else.** No `icmp` and no `sitofp` moved anywhere in the tree.
- **All 405 diagnostics byte-identical.** The 22 risky call sites cost zero
  moved error messages — no program in the tree mixes `i1` with a signed int
  in a binop, so `binop-result-type` returning null for that pair is
  unobservable here.
- Self-consistency was checked before touching the committed boot artifacts
  (compile `src/` with the new compiler, build that, recompile, diff): identical.
  Post-convergence `stage1.ll == stage2.ll`.

**Why it survived every bootstrap.** The compiler's own IR changed in exactly 6
places — `lex-atom`, `binop-result-type` ×2, `emit-binop-vals` ×2,
`repl-eval-form` — all of the shape `(let (x:i32 <comparison>) …)`, which had
been storing `−1` for true. Every one of their consumers tests `(!= x 0)` or
`(= x 0)`, and `−1` and `1` both satisfy that. So the compiler was *carrying*
the defect in six locals and could not observe it. That is the general shape:
**a wrong value that only ever reaches a truthiness test leaves no trace in any
fixed point.** Only a direct measurement of the value finds it — which is why
the new test asserts on the instruction (`sext i1` absent from the IR) and not
only on the run.

**A third consequence the item did not list.** A mixed `bool`/`i32` binop was
not previously an error — it was *accepted*, widening `true` to `−1` and
answering `(< b:i1 n:i32)` with `−1 < 1` = true, where the right answer is
`1 < 1` = false. With `i1` unsigned it joins the existing
`mixed signed/unsigned operands` diagnostic, so a silent wrong answer became a
located compile-time error asking for an explicit cast. Nothing in the tree
relied on it (0 status changes across 405 programs).

**Two expected-output files encoded the defect** and were corrected, not
worked around: `tests/expected/logic.out` (`(and) = -1`, `and4 all = -1`,
`or3 some = -1`, `or sc = -1`) and `tests/expected/globals-literals.out`
(`null=-1`, `t=-1 f=0`). `examples/logic.nuc:3` documents `(and) => true` in
its own header comment while the baselined output printed `-1`, so the
expectation had been contradicting the example's own documentation.

**Tests.** `tests/fixtures/w9-i1-unsigned.nuc` is self-checking with a distinct
return code per claim (widening ×5, ordering ×6, implicit-into-`i32` ×2,
`uitofp` ×1); it exits 1 on the pre-fix compiler and 0 after. The registered
unit adds the IR assertion the run cannot make on this host: no `sext i1`, no
signed `icmp` on `i1`, no `sitofp i1`.

**Gates.** 588 pass / 0 fail; `abi-test`, `layout-test`, `avr-test` all pass;
bootstrap converged and `stage1.ll == stage2.ll` byte-identical.

**Not covered.** `(as f64 true)` stays refused — `as` rejects int↔float in
either direction (item 30's step 7), independent of signedness. Item 32 (the
sign-extended unsigned GEP index) is the sibling that shares this predicate and
is still open; it now has one fewer caution, since `is-unsigned` answers for
`i1`.

### W9 item 30 as fixed *(2026-08-14)* — closing the value path opened the second asker

The item's diagnosis was exact and its estimate was right about the *rule*:
`as-float-narrowing` + `float-literal-fits` (`src/type-utils.nuc`, beside their
integer twins `as-int-narrowing` / `int-literal-fits`) are six lines between
them, and the predicate really was already written — `f32-const-ir`'s
`(as f64 (unsafe/cast f32 d))` is the round trip, so "exactly representable" is
that value compared against the original.

**The ruling is the stricter of the two the item offered**: `as` admits a float
literal only when it round-trips exactly, so `(as f32 1.5)` compiles and
`(as f32 3.14)` keeps its diagnostic. The argument for it is not symmetry with
the implicit path but the opposite — a literal `as` accepts must be one no
conversion happened to. The implicit path's rounding is W2d's Option A, taken
deliberately and unchanged here; if `as` rounded too, nothing in the language
would say "this conversion is exact", and `unsafe/cast` would be the only
spelling with a meaning. So `as` is now *stricter* than assignment for a float
literal and *equal* to it for an integer one, and that asymmetry is the ruling,
not an oversight.

**The finding is that the fix supplied its own second asker, inside the same
change.** Item 8's fix had to reach two positions because `const-fold-int`
already asked the integer question. The float question had exactly one asker
while the answer was always "no" — and the moment `emit-as` started saying yes,
`(defvar g:f32 (as f32 1.5))` stopped being an error and started being a
**runtime** initializer: G-3's soft-mode fall-through queued it for
`@__nucleus_init` and stored into `@g` at start-up, while `(defvar g:f32 1.5)`
one line above stayed `global float 0x3FF8000000000000`. That is a live
difference on any target whose constructors do not run (`global-init.md` §4.6,
the AVR rule), reached by *fixing* something. `defvar-init-ir`'s `as` branch
gained a float arm in the same change, calling the same `as-float-narrowing`,
so the two positions cannot drift. The generalisable form: **a rule with one
asker because it always refuses acquires its other askers the moment it starts
accepting** — enumerate them when you relax a rule, not when you write it.
`global-init.md`'s "a float `as` fold could only have *diverged* from the value
path" clause predicted this precisely, from the other direction, and is amended
there.

**A duplication fell out on the way.** `emit-as` step 6 hand-wrote
`  %s = fpext float %s to double\n` for the f32→f64 widening — text
`coerce-int-val`'s float branch already emits character for character. The new
step 6 covers all of float→float and delegates the emission to the chokepoint,
which is the shape step 5 had already adopted for integers; the proof that the
two really were identical is that the corpus IR did not move by one byte.
`sk`/`dk` were step 6's only readers and are gone with it.

**What the item does NOT cover, and why that bounds it.** `(as f32 5)` — an
*integer* literal at a float target — is still `lossy conversion from i32 to
f32`, and correctly so: the implicit path refuses it too (`(let (a:f32 5) …)` is
`let: init type mismatch for 'a'`), so `as` is not stricter than the coercion it
makes explicit and there is no asymmetry to close. The item is exactly the
float→float literal, which was the one remaining position where the safe cast
was stricter than the machinery it exists to make explicit.

**One arm the round trip needs.** `=` on floats is `fcmp oeq`, so a NaN literal
fails its own round-trip test; `float-literal-fits` answers NaN before the
comparison. `±inf` needs no arm — it round-trips and compares equal. And the
`-ffast-math` prohibition W2d put on the compiler's own link line now has a
second dependent: this predicate performs target arithmetic in the compiler
process, so FTZ/DAZ would make it call a flushed denormal exactly representable.

**Tests.** `tests/fixtures/w9-as-float-literal-fits.nuc` is self-checking and
RUN, not merely compiled (the risk in a round-trip rule is a wrong *value* — a
literal re-rendered at the wrong width — which an exit-0 compile would not
catch), and its IR assertion is stronger than item 8's: the accepted form must
cost **no instruction at all**, so any `fptrunc` in the fixture fails it. Three
rejects hold the three edges: `-inexact` (a literal that does not round-trip),
`-runtime` (a *value*, where the widths alone still decide), and
`-global-inexact` (the fold path reaching the same verdict with the same
wording).

**Measured.** Tests **586 PASS / 0 FAIL**, five of them new. `make bootstrap`
**byte-identical on the first pass**. Per-function normalized diff of
`build/nucleusc.ll` against a compiler built from HEAD's source: **1193
byte-identical, 2 changed** (exactly `emit-as` and `defvar-init-ir`), 0 removed,
2 added (`float-literal-fits`, `as-float-narrowing`). Corpus sweep over
`lib/`, `examples/`, `tests/fixtures/` and `src/`: **234 byte-identical IR, 0
differing, 0 regressed**, 1 newly-compiles — the new fixture, which is the whole
of the intended change — and across the 173 programs both compilers reject,
**0 diagnostics moved**. `make abi-test` / `make layout-test` / `make avr-test`
green.

### W9 item 18 as fixed *(2026-08-10)* — the convention was the defect generator

The recorded diagnosis was exact: `emit-binop-vals`' null-literal escape and its
pointer-identity arm both gated on `is-ptr-like`, which excludes `TY-FN`, so a
function-pointer comparison fell past both into the numeric path and died
`= expects integer operands`. What the item did not say is **why** those two
sites were missing a rule that three other sites already had.

**`conventions.md` told everyone to write it out by hand.** The standing note
read, verbatim: *"`TY-FN` is NOT in `is-ptr-like`, and it is not going to be —
admit it by name … every site that needs 'lowers to `ptr`' spells it as an extra
arm beside the predicate"*, and then listed the three sites that had complied
(`emit-zero-store`, `type-zero-const-ir`, `defvar-init-ir`). The exclusion is
right — `is-ptr-like` also means "coerces freely with `CStr`" and "`=` lowers to
`strcmp`", neither of which a function pointer may join — but *"write the extra
arm at each site"* is not a convention, it is deferred drift. It produced three
correct copies and two missing ones, which is precisely the shape item 15 found
one day earlier in the GEP index width. Two items, two days, same cause.

**The fix names the rule instead of repeating it.** `is-ptr-repr`
(`src/type-utils.nuc`) = `is-ptr-like` ∪ {`TY-FN`}, documented as *"is this
value one `ptr` register?"*, with the boundary stated in the comment: ask this
one for storage/constant/comparison decisions, ask `is-ptr-like` for coercion
and string decisions. The three storage sites moved onto it (inert), and the two
comparison gates got it for the first time. `is-ptr-like` itself is untouched.

**The asymmetry is the point, so it has a tripwire.** `(= hook cstr)` remains a
diagnostic, because `TY-FN` is still absent from the strcmp branch's operand
check — folding it in, the "obvious" one-line fix, would compile a function's
machine code into a `strcmp`. `tests/fixtures/w9-fnptr-cstr-compare.nuc` fails
the moment someone widens `is-ptr-like`.

| shape | before | after |
|---|---|---|
| `(= hook null)` — global, param, local | `= expects integer operands` | `icmp eq ptr %t, null` |
| `(!= null hook)` — operand order | same error | `icmp ne ptr null, %t` |
| `(= hook twice)` — against a `defn` name | same error | `icmp eq ptr %t, @twice` |
| `(= hook other-hook)` — two slots | same error | `icmp eq ptr %t0, %t1` |
| `(= hook some-cstr)` | `a CStr compares only with a CStr or pointer` | **unchanged, deliberately** |

**The workaround was committed in an example, and removing it is the proof.**
`examples/fnptr-global.nuc`'s `hook-unset` read
`(= (unsafe/cast ptr h) null)` under a comment naming this defect; it is now the
direct spelling, and the example asserts the two identity questions by *value*
(`is twice` flips 1→0 across a reassignment, `= h-zero` likewise). This is the
second consecutive item whose workaround lived in a committed example — worth
noticing as a search strategy, not a coincidence.

**Evidence.** Corpus sweep against the pre-fix compiler over `examples/`,
`tests/fixtures/` and `lib/`: **227 IR byte-identical, 0 differing, 155 rejected
by both with byte-identical stderr, 0 regressions, 0 new acceptances** — the
comparison gates only *accept* what previously died, and the three storage sites
are the same rule under a name. Per-function IR diff of the compiler
(`@.str.N` normalized): **4 changed — the three storage sites plus
`emit-binop-vals` — `is-ptr-repr` added, 1179 identical, and zero top-level
lines added or removed**. `make bootstrap` held the fixed point on the first
pass. Tests 543 → **546 PASS / 0 FAIL**; `avr-test` 8/8, `abi-test`,
`layout-test` green, 69 headers regenerate identically.

**Item 20 is adjacent and still open**, and the fixture says so inline: a local
must be initialized from an existing fn-pointer value, because `coerce-int-val`
has no `raw`→`TY-FN` case, so `(let (f:(fn i32)(i32) null) …)` is still refused.
Different chokepoint, different rule.

### W9 item 29 as fixed *(2026-08-10)* — a header is a file in the graph; only its *registration* may move

**Cause, exactly as recorded.** `prescan-imported-signatures` skipped every
`.nuch` path, so a header's names became known when its import form was reached
rather than when the graph was walked, and a use above the import reported `not
defined anywhere in this compilation unit` for a name that is in the unit. The
`.nuc` spelling of the same library resolved fine (W1a) — the whole defect is
that asymmetry.

**The item's list of four kinds was one short.** Measured `.nuc` against `.nuch`
with the import below the use, one kind at a time: `declare`, `extern`,
`defconst` and `defenum` all failed as recorded, and so did a `defmethod`. A
`defmethod` is one arm of an exported overload set, and `prescan-defn-signatures`
registers every arm of a `.nuc` library's — so parity with a `defn` is five
kinds, not four. It is also the one the item warned about
(`generic-register-method` appends unconditionally, so a repeat is a
duplicate-overload error rather than a no-op), which is presumably why it was
left off the list.

**The ruling was the item's own; the design question it did not pose is where the
line between registration and emission falls.** The obvious reading of
"registration-without-emission pass" is to run the header's importer in the
prescan and mark the path done. That works, and it moves every `declare` /
`external global` line to the top of `g-decl-stream` — including
`src/llvm.nuch`'s, so the compiler's own IR — because emission would then happen
in graph-walk order instead of at the import form. Registration is the half that
must move; emission is the half that must not. Hence a
`NUCH-BOTH`/`NUCH-REG`/`NUCH-AFTER` mode on `nuch-declare-import`,
`nuch-defmethod-import` and `emit-extern`, and the measurement that matters:
**IR 231 identical / 0 differing / 0 new acceptances / 0 new rejections**,
`--emit-nuch` 367 identical, `--emit-cheader` 364 identical, bootstrap
re-converged.

**Splitting the halves makes "already registered" a per-NAME question.** Each of
the three importers has an "already defined → return" skip, and it is load-bearing
in two live cases: two headers declaring one global (the `stderr` shape
`emit-extern`'s own comment names), and a unit that defines the name its header
declares (item 36). So the prescan registers *some* of a header's names and skips
others, and an emit-only pass that assumed the whole header was registered emits
`@x = external global` twice — invalid IR, from the very mechanism meant to keep
the IR unchanged. `g-nuch-registered` records `(path, name)` pairs and the
emit-only path asks per name, falling back to register-and-emit when the answer
is no; both cases are gated (`w9-nuch-shared-global-declared-once`,
`w9-nuch-local-definition-still-wins`).

**A registration-only pass needs no output stream**, which is the second dividend:
`--emit-nuch` and `--emit-cheader` return before `open-module-streams`, and the
convention already recorded for that trap says to guard on the stream. There is
nothing to guard here — the pass writes no IR in any mode — so those two modes get
the fix for free rather than an exemption.

**Verified by linking, not by compiling.** A library exporting a `defconst`, a
`defenum`, a global, a solitary function and a two-arm overload set is consumed
through its generated header with the import written below every use: it compiles,
links against the library's object and prints the same five values as the
import-above spelling, with exactly one `declare` per function and one
`external global` per variable. Transitive reach through a `.nuc` library that
imports the header works too. The old compiler refuses all of it.

**The residue is symmetric, which is why it is item 40 and not a smaller item 29.**
A macro, a `defunion`'s arm constructors and a struct's *layout* still need the
import above the use — measured identical for the `.nuc` and the `.nuch` spelling
of one library, so it is a property of what the prescans register (names), not of
headers. The struct case has the worst diagnostic of the three: the name resolves
against a field-less prescan stub, so a literal reports `too many initializers`.

**Found while measuring, and fixed: `tests/run-tests.sh` could fail a passing
assertion.** The harness runs under `set -o pipefail`, and `grep -q` exits at its
first match — SIGPIPE-ing the `printf` feeding it, whose status pipefail then
adopts. A *matching* assertion therefore reads as false. The race is one-sided (a
genuine non-match never trips it) and only bites once the producer outgrows a
stdio buffer, so it surfaced as a handful of tests failing at random: 186 of 200
identical runs said "no match" for a pattern present in the 54KB of IR
`w1-late-overload-symbol` greps; 0 of 200 with pipefail off. All 282 sites now go
through `qgrep` (`grep "$@" >/dev/null`), which reads its input to the end. Three
consecutive clean suite runs before the item's own tests were added, three after.

### W9 item 28 as fixed *(2026-08-10)* — a legal C identifier is more than a legal sequence of characters

**Cause, exactly as recorded, and the ruling the item proposed.** `sanitize-for-c`
maps every character C forbids in an identifier to `_` and has no notion of a
reserved *word*, so `union`, `signed`, `default` and `class` — all ordinary
Nucleus names — reached the header intact and it did not parse. The item offered
the fix: rename to `union_` and label it `asm("union")`, exactly as a hyphenated
name is already handled. That is what landed. The interesting part was not the
rename; it was the three things the corpus said about *where* the rename belongs.

**C++'s keywords count, and the corpus is what proves it.** A C-only table would
have looked complete and measured nothing: the one committed header this defect
touches is `lib/allocator.h`, whose `alloc-handle-realloc` takes a parameter named
`new`. That is legal C. It is fatal C++, and a generated header is routinely read
through `extern "C"` from C++. Committed `lib/*.h` parsing as C++ went **32/34 →
33/34**, the remaining one being `string-split.h` (item 37); as C the count does
not move at all, which is precisely why the C-only reading of this item would have
closed it while leaving the only real instance broken. `new`, `try`, `template`,
`operator` and `namespace` are all names a Nucleus library plausibly defines —
`try` is a Nucleus form — and the iso646 spellings (`and`, `or`, `not`, `xor`) are
in the table for the same reason.

**A struct tag is an identifier too.** `typedef struct union { … } union_;` fails
as surely as the function declaration did, and the *reference* spelling
(`type-name-to-c`) has to escape identically or the header parses and then names a
type it never defines. That is the same three-site lockstep — `type-name-to-c`,
`emit-cheader-defstruct`, `emit-cheader-defunion` — that B3′ and item 25 each had
to repair, hit for a third time. All three now route through `cheader-c-ident`.

**Escape the join, not the fragment.** An enum member is emitted as `Kind_default`,
which is already a perfectly good identifier; escaping the fragment would have
renamed every prefixed constant in the corpus for no reason. `cheader-c-ident-join`
tests the finished string instead — which can still land on a keyword, since
`and` + `eq` is `and_eq`. This is why 362 of 364 corpus headers are byte-identical
rather than merely "mostly unchanged".

**Verified by linking, not by grepping.** A fixture whose exports are `union`,
`xor`, a global named `delete`, a struct named `class` passed *and returned* by
value, fields named `class` and `signed`, and a parameter named `default` is
compiled by nucleusc, then consumed by a C program and a C++ program that both
compile with `-Wall -Werror`, link against that object, and print the same seven
values. Every `asm("…")` label in the header is checked against `nm` of the object.
Nothing about the symbol moves — only its C spelling.

**Measurements.** IR **231 identical, 0 differing**, 170 rejected identically, 0
new acceptances, 0 new rejections. Headers **362 identical, 2 differing, 0 status
changes**, no regressions: `lib/allocator.nuc` (`new` → `new_`) and
`src/compiler-types.nuc` (fields `template`, `private`). Committed `lib/*.h`: C
33/34 unchanged, C++ 32/34 → 33/34. Tests 571 → **576 PASS / 0 FAIL**;
`check-headers` 69/69 after regenerating `lib/allocator.h`; `make bootstrap` PASS.

**Item 39 was measured on the way and is not fixed.** `(defn 2fast …)` passes
every front-end pass — `check-ir-name-legal` tests the character *set*, and a digit
is in it — and emits `define i32 @2fast(…)`, which LLVM reads as a numeric global
id and rejects at IR-parse time. The exit status is 1 and no object is written, so
nothing is silently wrong, but the message names a line in the generated IR and
nothing in the source. `--emit-cheader` emits `int32_t 2fast(int32_t a);` for the
same program; that is a symptom, and escaping it here would have exported a symbol
no object can ever define. The fix belongs at the ir-name layer, so the item is
filed rather than absorbed.

### W9 item 26 as fixed *(2026-08-10)* — the header emitter was deriving an answer the registry already had

**Cause, exactly as recorded.** `emit-cheader-declare` computed the exported
symbol as `ns-ir-base fname`. That is the symbol only for a **solitary,
non-operator** `defn`. A name carrying two methods is mangled per signature, and
an **operator** name is mangled even when the user writes only one — its generic
always holds the intrinsic seed method beside the user's — so `lib/string.nuc`'s
`=` links as `eq.String.String` and `nm lib/string.o` contains no `=` at all. The
header declared symbols nothing defines, and since `sanitize-for-c` maps every
operator character to `_`, it declared them under the identifier `_`, twice:

```c
_Bool _(struct String a, struct String b) asm("=");
_Bool _(struct String a, struct String b) asm("<");   // conflicting asm label
struct _BANGi32 from_str(int32_t self, void* sv) asm("from-str");
struct _BANGi64 from_str(int64_t self, void* sv) asm("from-str");   // conflicting types
```

**The fix is a question, not a derivation.** `finalize-generics`
(`src/generics.nuc`) makes both decisions and records the result on the `Method`;
`defn-form-mangled-name` reads it back and answers null exactly when `ns-ir-base`
is right. The `.nuch` emitter beside this one has always asked — which is why it
was never wrong, and why `tests/fixtures/s1-newlib.nuc`'s round-trip asserted
`(defmethod "@scale.i32" …)` on the `.nuch` line and `int32_t scale(int32_t x);`
on the C line of the same test.

Asking has a precondition: the registry must be populated. So `emit-cheader-header`
now runs the prescan sequence, and `--emit-cheader` loses its prelude exemption —
whose stated justification ("it exports the C-representable subset, which cannot
name a prelude type in the first place") was already false (`lib/parse.h` declares
the `!i32` Result struct) and was never the reason the prelude is needed here.
`prescan-imported-signatures` is part of it, not an optional extra: **whether a
name is overloaded is a property of the compilation unit**, and a library
typically contributes one `hash`/`drop`/`next` to a name the prelude also defines.
Prescanning the file alone makes all of those look solitary — the same wrong
answer, arrived at more expensively.

**Measured against `nm`, not against a list.** Every `lib/*.nuc`, comparing each
generated header's `asm` labels and unlabelled prototypes with the symbols its
object actually defines:

| | symbols the header binds | not defined by the object |
|---|---|---|
| before | 236 | **100** |
| after | 170 | **0** |

The count falls because 66 of the declarations were templates that have no symbol
at all until a call site stamps them. Committed `lib/*.h` that compile under
`clang -fsyntax-only`: **29 → 33 of 34** (item 4 took it 13 → 27, item 25 → 29).
Only `string-split.h` remains, on item 37.

**Two other items moved, and one did not.**

*Item 27 is closed, and its recorded cause was wrong in an instructive way.* It
reads "`defn-is-generic-template` already answers this question for the whole
form; the gap is that a method on a parametric struct is not itself a generic
template". That predicate answers correctly and such a method *is* a template to
it. It was returning 0 because `collect-pattern-tyvars` recognizes a tyvar **only**
through `node-template-of` — the struct-template registry — which this pass had
never populated, so `(HashSet T)` was not a template application and `T` was not a
tyvar. `hashset.h`'s `void set_remove(void* self, struct T elem);` is now
`/* set-remove: generic template; not exported */`, along with fourteen others.
Same root cause as item 26: the pass was working without the registries.

*Item 38 is mostly closed as a consequence.* 30 corpus files changed status, 29 of
them from "emits a header" to "reports an error" — and all 29 are files
`--emit-llvm` also rejects, with a **byte-identical** diagnostic (checked by
diffing the two pipelines' stderr). Emitting a C header for a program that does
not compile was never a feature. The 30th, `w5f-empty-defunion-arm.nuc`, went from
SIGSEGV to a located message. Three fixtures still crash: `s1-missing-ret.nuc`,
`w5f-empty-param.nuc`, `w5f-empty-union-member.nuc`.

*Item 28 is not fixed*, though its only corpus instance vanished — `union` in
`lib/hashset.nuc` is a template method and is now skipped. A fresh probe confirms
a non-template `(defn union (a:i32 b:i32):i32 …)` still emits
`int32_t union(int32_t a, int32_t b);`. Recorded on the row so a later reader does
not mistake an empty grep for a fix.

**A pre-existing crash found and root-caused on the way.** Turning the prescans on
made `--emit-cheader` segfault on an anonymous struct in a signature — which
`--emit-nuch` had been doing since it was written, on both compilers:

```
$ nucleusc --emit-nuch examples/anon-struct.nuc
Segmentation fault (core dumped)
```

`lookup-or-make-anon-struct` (`src/union-registry.nuc`) is the one **eager** writer
among the anonymous-type constructors — its sibling `lookup-or-make-anon-union`
queues to `g-pending-unions` — and it is reachable from the signature prescan,
which the header modes run with **no module stream open** (`open-module-streams` is
on the compile path only). `fprintf` to a null `FILE*`. Guarded on the stream, the
way the `!T` payload path at the bottom of the same file already does, with
`emitted` left 0 when nothing is written. Both modes now emit for both fixtures.

**Corpus, both compilers, every `.nuc` in `examples/`, `tests/fixtures/`, `lib/`,
`src/`:**

- IR: **231 identical, 0 differing**; 170 rejected identically, 0 rejected
  differently; **0 new acceptances, 0 new rejections**. Header emission returns
  before `open-module-streams`, so nothing here can reach codegen — and the sweep
  says so rather than the argument.
- Headers: 313 identical, 47 differing, 30 status changes (accounted for above).

**Tests: 571 PASS / 0 FAIL** (+5). The five new gates check the exact declarations,
the header's labels against `nm`, a C consumer that calls both overloads and the
operator (`a=70 b=42 eq=1 solo=42`), the absence of an operator-sanitized `_(` in
any committed header, and that `parse.h`/`string.h`/`strview.h`/`keyword.h`
compile. Three existing assertions changed because they had encoded the defect or
a less precise message: `s1-cheader-plain-prototypes` asserted
`int32_t scale(int32_t x);` for an overloaded `scale` (its own `.nuch` half already
asserted `@scale.i32`); `w9-cheader-global-skips-unspellable` now sees the more
specific "defunion-template instance type" reason for `(Maybe i32)`.

One deliberate omission from the sequence: **`prescan-value-names` for this file**.
Nothing here emits a body, and the only thing it changes is
`cheader-array-extent`'s constant fold — a local `(array i32 BUF-LEN)` would export
as `xs[4]` instead of `xs[BUF_LEN]`, losing the symbolic size against the
`#define BUF_LEN` the same header emits. An *imported* constant still folds, which
is right for a name the header cannot `#define`.

### W9 item 25 as fixed *(2026-08-10)* — the cause was right and the blast radius was somebody else's

**The recorded cause reproduced exactly, and the recorded consequence belonged to
two different defects.**

The cause, verbatim from the item and confirmed on a fresh probe:
`emit-cheader-defstruct` emitted `typedef struct { … } Rec;`, while
`type-name-to-c` spells *every* reference to a user type `struct Rec`. Tag and
typedef are different things in C, so nothing ever completed the tag, and every
by-value use of a library's own type failed against the header the compiler
generated for that library — a nested field and a by-value parameter alike:

```
rec.h:14: error: field has incomplete type 'struct Rec'
u.c:2:  error: argument type 'struct Rec' is incomplete
```

The fix is the one word the item predicted — `typedef struct Rec { … } Rec;` —
applied at both producers, since `emit-cheader-defunion` was anonymous for the
same reason and `type-name-to-c` answers `struct NAME` for a union name too. A tag
and a typedef may share a spelling (separate C namespaces), so `Rec` and
`struct Rec` now both name the completed type and no reference site needs a case.
`cheader-by-value-c` — item 3's local workaround, which stripped the `struct `
prefix so a `defvar` could at least be spelled — is deleted, and the one remaining
spelling is correct in both positions. End to end, on a C consumer that nests the
struct, reads the nested field and passes one by value: `sum=107 hold=309`, where
before the same program did not compile.

While there, `emit-cheader-defunion` was switched from bare `ir-name-token` to
`ns-ir-base`. B3′ gave the defstruct emitter and `type-name-to-c` the namespace
prefix and missed this one, so a namespaced union's definition and every reference
to it spelled different C identifiers. Identity under `user`.

**The item's "breaks `char.h`, `error.h`, `string-split.h`" was wrong**, and the
way it was wrong is the reusable part: those three were attributed to this defect
by inspection — they contained `struct X` fields that would not compile — without
checking *which* `X`. Regenerating all 34 committed headers after the fix left all
three still broken, for two causes that are not this one:

| header | actual cause | disposition |
|---|---|---|
| `char.h`, `error.h` | `Char` and `Err` are **builtin scalars**, not structs | fixed here, 2 lines |
| `string-split.h` | `StrView` is a real struct **from another library**, never included | filed as item 37 |

`Char` and `Err` resolve by name in `union-registry.nuc` and lower to `i32`
(verified in the IR: `define i64 @char-utf8-len(i32 %c.arg)`). The *Type*-keyed
renderer `type-to-c` has always answered `uint32_t` / `int32_t` for them; the
*name*-keyed `type-name-to-c` that the cheader pass actually uses had no case for
either, so both fell through its "assume struct" arm. That is the identical trap
its own comment already records for `usize`/`ssize` — the third instance of one
rule living in two functions that must agree, so the fix went next to the second
instance rather than at a call site. `lib/char.h` improves from `struct Char c` to
`uint32_t c`, which is also the first time it was ABI-honest.

**Corpus, measured rather than argued.** Every `.nuc` in `examples/`,
`tests/fixtures/`, `lib/`, `src/`, both compilers:

- IR: **231 identical, 0 differing**; 170 rejected identically, 0 rejected
  differently; 0 new acceptances, 0 new rejections. The change cannot reach codegen
  — `type-name-to-c` and `type-node-to-c` have no caller outside `cheader.nuc` —
  and the sweep says so rather than the reasoning.
- Headers: 287 identical, 114 differing, **0 status changes**. Of the 375 corpus
  files that emit a header, **340 compiled before and 349 after, with none
  regressed**. Item 4 took the committed `lib/*.h` from 13 of 34 to 27; this takes
  it to 29.

The remaining 5 are the three still-open cheader defects: 26 (overloaded and
operator names — `parse.h`, `string.h`, `strview.h`), 27 + 28 (tyvar and C keyword
— `hashset.h`), and the newly split item 37 (`string-split.h`).

**Filed, not fixed: item 38.** The sweep found `--emit-cheader` **segfaults** on 4
malformed fixtures that `--emit-llvm` rejects with a located message. Identical on
both compilers, so pre-existing and unrelated; recorded because a crash is the
worst possible diagnosis of a syntax error and the fixtures exist precisely
because the syntax is invalid.

**Verification.** 566 PASS / 0 FAIL (+5: `w9-cheader-struct-tagged`,
`-builtin-scalar-not-struct`, `-struct-by-value-c-consumer`,
`-no-anonymous-typedef`, `-lib-corpus-compiles`); the first three FAIL on the
pre-fix compiler. Stage 1 == stage 2 on the first pass; `make update-bootstrap`
then `make clean && make && make bootstrap` re-converged. `abi-test`,
`layout-test`, `avr-test` green; `check-headers` 69/69 after regenerating the 12
that drifted; `riscv-test` SKIP (container missing cross-libc). One existing gate
changed on purpose: `w9-cheader-global-lines` asserted `extern CRec rec_val`, the
typedef spelling `cheader-by-value-c` produced, and now asserts
`extern struct CRec rec_val` — the assertion encoded the missing tag as the
expected behaviour.

### W9 item 24 as fixed *(2026-08-10)* — a producer that wrote one of the two registries

**The item named `(dyn P)`; the defect was one registry short, and `(dyn P)` was
one of at least two askers.**

Every callable name in a unit is registered twice: in `g-globals`, which answers
*what symbol does this name have*, and in `g-generics`, which answers *which
method of this name matches these argument types*. `emit-defn` writes both even
for a **solitary** function. That second write looks redundant — a solitary
function needs no dispatch — and it is the only reason a protocol conformance, a
drop thunk or a `(dyn P)` vtable slot can be resolved at all.

`emit-nuch-declare-import` wrote only the first. So a function arriving through
a `.nuch` was half-registered, and every asker that poses the question by name
*and signature* failed on it:

| asker | before | after |
|---|---|---|
| `dyn-vtable-method-irname` | `(dyn dp/Describe): no method 'describe' is defined` | `@__vt.dl__Fox.dl_Describe = { ptr @dl__describe, ptr null }` |
| `method-satisfies-sig` (via `emit-extend`) | `dp/Fox does not implement Show.describe` | conformance recorded |
| an ordinary call | `call i32 @dp__describe(...)` | unchanged |

The third row is why it survived: the path everybody exercises asks `g-globals`,
so the gap is invisible to the asker that motivated the registry and visible
only to the ones that came later. End to end, on a library compiled separately,
its `.nuch` imported, both objects linked:

```
d=309          # after
(dyn w24/Describe): no method 'describe' is defined   # before, same inputs
```

**The fix is the registration, not a fallback at the box site.** Two askers were
already measured and `vtable-drop-irname`/`vtable-invoke-irname` ask the same
way; patching call sites would have left the next one. `emit-nuch-declare-import`
now registers the method with `ir-name` set to the declare's own link name.

Two consequences of letting methods arrive from another translation unit, both
of which had to be handled before the corpus stood still:

* **`Method.ir-fixed`** — the producing unit chose that symbol.
  `finalize-generics` names every method it sees, which is right while every
  method is one this unit emits; with an imported one in the set, adding a single
  local overload re-mangles a symbol another object file already defines. The
  principle is `fn-force-generic-mangled`'s own ("no already-emitted symbol is
  renamed"), stated per method rather than by freezing the whole generic, so a
  local overload added afterwards still gets a mangled name of its own.
  `emit-nuch-defmethod-import` is marked too: it held only by coincidence — a
  re-mangle recomputed the same string — and stopped holding the moment item 23
  made the suffix decision depend on a per-prefix count.
* **R4's duplicate-signature check had to say which pair it is about.** Adding
  entries to a bare-keyed registry makes new *pairs* meet in it, and two `.nuch`
  headers from different namespaces declaring `helper (x:i32):i32` started
  colliding — over definitions neither importing file makes, and over two
  distinct symbols (`@w24na__helper`, `@w24nb__helper`) that had always been
  legal together. The check now requires both sides to be local definitions.
  Item 35 (two *local* definitions in two namespaces) is untouched, and the five
  existing duplicate-definition gates pin that the exclusion did not over-reach.

**Measured in passing and NOT fixed — item 36.** A `declare` returns early when
the name is already bound, and the unit's own prescan binds every local `defn`
first, so a local definition of an imported name discards the header entry
whole. `(lib2/helper 3)` against a library's `helper (i32):i32` and a local
`helper (i64):i64` emits `call i64 @helper` — the local function, under a
spelling that names the library's, with no diagnostic. Byte-identical on the
pre-fix compiler. It is also why the "imported declare + local definition" pair
is unreachable, and why the two-header pair above is the only real one.

**Verification.** Corpus sweep against a compiler built from HEAD's source, over
every `.nuc` in `examples/`, `tests/fixtures/`, `lib/` and `src/`: **234
byte-identical IR, 0 differing, 170 rejected identically, 0 rejected
differently, 0 new acceptances, 0 new rejections.** That covers the 44
hand-written top-level `(declare …)` forms in the tree, which take the same
registration path and are what the compiler's own bootstrap runs on. Stage 1 ==
stage 2 on the first pass; `make bootstrap` **PASS**. Tests **561 PASS / 0
FAIL** (+4). `make abi-test`, `make layout-test`, `make avr-test` green;
`make check-headers` 69/69; `riscv-test` skips on the container's missing
cross-libc. Three of `run_w9_nuch_declare_generic`'s four gates fail on the
pre-fix compiler; the fourth is the two-header regression guard and passes on
both, which is the point of it.

### W9 item 23's symbol half as fixed *(2026-08-10)* — a merged registry asked two questions it cannot answer

The item was re-measured on 2026-08-09 and closed as "a ruling to revisit, not a
bug to fix". That reading was right about the *dispatch* half and wrong about the
half the item's own evidence names. Re-measured again before touching anything:

| probe | before | after |
|---|---|---|
| `(ns qa) describe(i32)` + `(ns qb) describe(i64)`, compiled together | `@qa__describe.i32`, `@qa__describe.i64` | `@qa__describe`, `@qb__describe` |
| the same two files, import order swapped | `@qb__describe.i32`, `@qb__describe.i64` | unchanged |
| each file compiled alone | `@qa__describe`, `@qb__describe` | unchanged |
| `examples/w9-dyn-ns.nuc` (the real one) | `@describe.pdp__Fox` — `dp`'s method with **no prefix at all** | `@dp__describe` |

So a namespace's exported symbol was a function of what else the compilation
unit happened to contain, and of the order it was imported in. The end-to-end
consequence, measured rather than argued: `qblib.nuc` is `(ns qb)` and imports a
`(ns qa)` library that happens to define `describe` too. Its object defines
`@qb__describe.i64` (its own function) and `@qb__describe.i32` (**qa's**, under
qb's prefix). Its `.nuch` says `(declare describe ((x i64)) :i64)` and its C
header says `int64_t qb__describe(int64_t x);` — both correct, both written from
the library alone, and both naming a symbol the object does not define:

```
/usr/bin/ld: cons2.nuc:(.text+0x15): undefined reference to `qb__describe'
```

**Two fields, neither of which is a property of a merged set.** R2 keeps one
`Generic` per bare name with every namespace's methods merged into it
(name-resolution.md §8.2), and mangling read two answers off it:
`Generic.ir-prefix`, snapshotted at `generic-alloc` from whichever namespace
created the generic first; and `Generic.mangled`, one flag doing double duty as
"dispatch through the registry" (a genuine whole-set fact) and "every method's
symbol takes `.tok` suffixes" (not one). The fix asks the method instead —
`method-ir-prefix` reads `Method.src-ns`, which B4 had already made trustworthy
provenance for exactly this registry, and a count of the user methods sharing
that prefix decides the suffix. `mangled` keeps its first meaning only.

The precedent was already in the tree: `fn-force-generic-mangled`
(`src/nucleusc.nuc`) sets `mangled` **without** re-mangling, and its comment
explains that renaming an already-emitted solitary define would be wrong. The
split this item needed had been made once, locally, and not named.

Three sites, one rule: `finalize-generics`' solitary arm, its overloaded arm, and
`generic-instantiate-in`'s stamp — where the existing comment already said "the
template's *defining* namespace, not the call site's" and reached for
`(gg ir-prefix)` to say it, which is the template's namespace only when no other
namespace defines the name. Grouping is by the emitted **prefix**, not the
namespace name: two namespaces that `set-ir-prefix` to the same string share one
symbol space, and that is precisely when they must be suffixed.

**What is deliberately not fixed.** Two namespaces still cannot each define
`describe (x:i32):i32`. With the symbols now distinct that is no longer a
collision — it is R4's eager check, and the bare reference `(describe 10)` is the
real obstacle. Split out as item 35 rather than folded in here, because closing
it means revisiting a ruling and doing the `Method`-writer audit B4 deferred.

**Verification.** Corpus sweep against the pre-fix compiler over
`examples/` + `lib/` + `tests/fixtures/`: **229 identical, 1 differing, 157
rejected identically, 0 new acceptances, 0 new rejections**. The one differing
file is `examples/w9-dyn-ns.nuc` — the row above — whose diff is four lines, all
symbol names, and whose output is unchanged (`105 / 207 / 309`); its library
compiled alone emits `@dp__describe`, which is now what the joint build emits
too. `make bootstrap` holds the fixed point. Per-function diff of the compiler's
own IR: **2 genuinely changed** (`finalize-generics`, `generic-instantiate-in`),
2 new, 742 byte-identical, and 440 differing *only* by `@.str.N` renumbering —
one added literal (`"@%s"`) shifting every later index by one. `make test`
**557 PASS / 0 FAIL** (+5); `abi-test`, `layout-test`, `avr-test` pass, the two
RISC-V gates skip for the container's missing cross-libc as always, and all 69
generated headers still match.

`run_w9_ns_symbol_ownership` pins the invariant as an **equality** — the symbol a
namespace exports compiled alone equals the one it exports compiled together —
plus the absence of a phantom suffix, the `.nuch` link-and-run that failed above,
the C header agreeing with the object, and import-order independence. Four of its
five gates fail on the pre-fix compiler; the fifth (the header) always passed,
and is there so a future change cannot resolve a mismatch by moving the header to
meet a suffixed object.

**Why self-compilation could not catch it, again.** No file in `src/` declares a
namespace, so every prefix in the compiler is empty and the two decisions
coincide. Only four files in the tree use one — and `lib/nsdescribe2.nuc` names
its protocol method `tag-of` rather than `describe` *specifically* to keep this
item out of the tests. A rename in a fixture that exists to dodge a defect is a
bug report; the corpus is only as good as the names in it.

### W9 item 20 as fixed *(2026-08-10)* — the item was half-right, and the other half was two bigger defects

Filed as "`(let (f:(fn i32)(i32) null) …)` dies while the identical `defvar`
spelling compiles". Both halves of that are true; the framing is not. Measured
across every position:

| position | before | after |
|---|---|---|
| `defvar g:(fn …) null` | OK (item 14's constant path) | unchanged |
| `let`/`with` init | `let: init type mismatch` | OK |
| `set!` | `set!: type mismatch` | OK |
| `.set!` field store | `.set!: type mismatch for field` | OK |
| explicit `return null` | `return type mismatch … __fnty_0` | OK |
| **argument** `(take null)` | "OK" | **was unchecked — items 33/34, both fixed 2026-08-14; every other row of this table now reads the same in an argument as in a `let`** |

So it was never `let`-specific: it was every site funnelling through
`coerce-int-val`. And the argument position "worked" for a reason worth more
than the item — it is not checked at all.

**Why a flag and not a type test.** `null` emits `(alloc-val ty-raw "null")`,
and `union-registry` resolves the *type name* `raw` to that same `ty-raw`
singleton. A `raw` binding and the literal are therefore indistinguishable by
type, and the distinction is the entire rule: `null` may land in a function
pointer, an arbitrary data pointer may not (`fn`↔`ptr` is `unsafe/cast`'s job).
Any type-directed gate — `is-ptr-repr src`, the obvious one-liner — admits both
and makes every data pointer silently callable. Hence `Val.is-nlit`, set only by
`emit-symbol-ref`'s `null` arm, read only at the chokepoint. That is exactly the
precedent W2d set when it added `is-flit` rather than overloading `is-lit`, and
its stated reason is item 18's lesson in advance: *"a DELIBERATELY separate flag
… every existing `is-lit` reader would otherwise have to be audited."*
`tests/fixtures/w9-fnptr-null-launder.nuc` is the tripwire; the escape hatch is
spellable, in an extra pair of parens: `(unsafe/cast ((fn i32)(i32)) p)`.

**Items 33 and 34 are the real find.** Chasing "why does `(take null)` work?"
led to `emit-call-with-args`' coercion loop, where two independent holes sit on
adjacent lines. The guard compares IR type *strings*, so any two types that
lower to `ptr` are never checked (item 34); and when the guard does fire,
`safe-coerce-val`'s null return is discarded (item 33) — the loop's own comment
says "no safe conversion exists, the argument is left untouched." Measured
consequences, all accepted silently, all identical on the pre-session compiler
`5f4989e`:

```lisp
(f-ptr 7)     ; => call i32 @f-ptr(i32 7)        param is ptr:S
(f-i32 c)     ; => call i32 @f-i32(ptr %t)       param is i32, c is CStr
(f-i32 1.5)   ; => call i32 @f-i32(double 1.5)   param is i32
(take c)      ; => call i32 @take(ptr %t)        param is (fn i32)(i32)
```

`llvm-as` accepts all of it, because a call site carries its own signature. This
is the **type** half of item 12 (whose *arity* half was fixed 2026-08-02), and
W2d had already fixed one instance of it — the f32-narrowing miscompile — by
adding a coercion *rule* rather than closing the hole that swallows failures.
Overloaded and multimethod calls are unaffected: resolution must match a
signature to pick a method, so it rejects earlier and for a different reason.
This is the solitary-`defn` path only, which is also why self-compilation never
caught it — the compiler's own calls are type-correct, so a swallowed failure
never has anything to swallow.

> **Items 33 and 34 both fixed 2026-08-14, in that order and for a reason.**
> The four measured calls above split exactly along the two defects: item 33
> made the first three raise `argument N has type X, which does not match
> parameter type Y`, and `(take c)` — the pointer pair — kept compiling, because
> item 33's check sits *inside* the `strcmp` guard that item 34 is about. Item
> 34 replaced that guard with `type-eq` and routed the answer through
> `coerce-int-val`. The split between them is sharper than "the guard fires or
> it does not" suggests: `(take-fn 7)` — an *int literal* in a function-pointer
> slot, which item 20's matrix never listed — has differing IR strings, so the
> old guard did fire and item 33 alone closed it. Item 34 is the four spellings
> that lower to `ptr`. The list also understates the
> damage: the case worth fixing was not a deliberate type error but
> `(take-f64 3)`, which printed `0.000000`. See the W9-33 and W9-34 notes below,
> and items 41 and 42, which item 33's error surfaced.

**Evidence.** Corpus sweep against the pre-fix compiler: **229 IR
byte-identical, 0 differing, 156 rejected by both with identical stderr, 0 new
acceptances, 0 new rejections** — purely additive, as expected for a rule that
only admits a spelling that previously raised. Refusal matrix re-measured: `raw`,
`CStr`, `ptr`, an int literal and a string literal into a fn slot are all still
refused, in `let` and in `.set!`. Per-function diff of the compiler: **2 changed
— `coerce-int-val`, `emit-symbol-ref` — 1182 identical**, plus `%Val` gaining its
ninth field. `make bootstrap` held the fixed point. Tests 549 → **552 PASS /
0 FAIL**; `avr-test` 8/8, `abi-test`, `layout-test` green, 69 headers identical.

### W9 item 19 as fixed *(2026-08-10)* — the third site of the same rule, and self-compilation cannot see it

Item 18 named the rule. Item 19 is the site that was still missing it:
`type-size` listed `TY-PTR` and `TY-CSTR` as arms and had no `TY-FN` case, so a
function pointer fell to the default `(return 1)` and every fn-pointer global,
alloca, load and store was emitted `align 1`. The fix is one line — ask
`is-ptr-repr` before the `case` — and it lets `abi-alignof` and `abi-sizeof`
drop the hand-written `TY-FN` arms they had each been given instead. Final
tally on this rule: **five correct copies, three missing ones**.

**The recorded severity was right but incomplete.** "Conservative, not a
miscompile" is true — `align 1` under-promises, and x86-64 tolerates unaligned
access, which is why nothing ever failed. But a strict-alignment backend must
*honour* the claim. Measured, not inferred, on `(defn get-hh ():(fn i32)(i32)
(return hh))`:

| target | before | after |
|---|---|---|
| armv7 `+strict-align` | 4 × `ldrb` + 3 × `orr` | 1 × `ldr` |
| rv64 | 8 × `lbu` + shifts/ors | 1 × `ld` |
| x86-64 | `movq` | `movq` (unchanged) |

So the cost was ~7–20 instructions per fn-pointer load on exactly the targets
the AVR and RISC-V tracks are heading for, and zero on the one target anybody
was measuring. Note the *storage* was never actually misaligned — on both
armv7 and x86-64 the `align 1` global still came out at its natural alignment
(`.p2align 2`; offset 0x28 in `.bss`), because the AsmPrinter raises it. It was
only the load and store instructions that claimed not to know, and that claim
alone is enough to force the byte-wise lowering above.

**The blind spot is the reusable finding.** `src/nucleusc.nuc` contains no
`TY-FN` slot, so the compiler's own IR is **byte-identical** across this fix —
self-compilation, the project's strongest routine check, is structurally
incapable of witnessing this class of defect. Confirmed both ways: the same
source compiled by the pre- and post-fix compilers gives identical IR, and the
`boot/nucleusc.ll` diff contains **zero** `align` changes (its 153/197 line
delta is entirely the three edited function bodies). Any defect confined to a
construct the compiler does not use itself needs a fixture or it is invisible;
that is what `tests/fixtures/w9-fnptr-align.nuc` is for, and its gate asserts
the **invariant** (no `ptr`-valued slot claims `align 1`) rather than a count,
plus the width on a 32-bit target — item 15's rule applied to item 19's operand,
since a slot width hardcoded to 8 would be the same defect one tier over.

**Evidence.** Corpus sweep against the pre-fix compiler over `examples/*.nuc
tests/fixtures/*.nuc lib/*.nuc`: 187 IR byte-identical, **41 differing, 156
rejected by both with byte-identical stderr, 0 new acceptances, 0 new
rejections**. The 41 differing files are checked line by line: **all 139 changed
lines are `align 1` → `align 8` on a `ptr`** — 65 loads, 22 loads-from-global,
16 allocas, 30 stores, 6 globals — with the instruction text otherwise
identical, so nothing but the alignment moved. (The convention note had named
three affected examples; the real number is 41, because closures, `BoxedFn` and
`dyn` all carry `TY-FN` slots, as does most of the string library.) Per-function
diff of the compiler: **3 changed — `type-size`, `abi-alignof`, `abi-sizeof` —
1181 identical, none added or removed**. `make bootstrap` held the fixed point.
Tests 546 → **549 PASS / 0 FAIL**; `avr-test` 8/8, `abi-test`, `layout-test`
green, 69 headers regenerate identically.

**AVR is exempt by construction, not by luck**: `avr-reject-fn-value` (AVR-6)
refuses to materialize a function as a data pointer at all, since AVR functions
live in address space 1 — so a `TY-FN` slot cannot exist on that target, and the
16-bit width this rule now respects is unobservable there. The 32-bit gate uses
`i386` for that reason.

### W9 item 15 as fixed *(2026-08-10)* — the rule was written correctly once, in one of its three homes

An LLVM GEP index carries its own IR type, so the annotation and the register
have to agree, and the width an address computation wants is the target
pointer's. `aref`, `aset!` and `unsafe/ptr+` each decided this for themselves,
and each wrote `i64` into the format string.

**AVR-1 already found and fixed this — in `emit-ptr-add` alone.**
[../stage14/avr-targets.md](../stage14/avr-targets.md) records the diagnosis
exactly ("internally inconsistent … hardcoded the GEP index type and the sext
target to `i64`") and routes that one function through `ptr-int-ir`. It was
found because the auto-emitted node/arena runtime uses `unsafe/ptr+`, so it
stood between AVR and *any* program; `aref` and `aset!` are user-facing and no
AVR example reached them, so their identical copies survived. Item 15 is not a
new discovery so much as the other two thirds of an already-solved problem.

**Two failure modes, and only one of them is loud.**

| index type | AVR before | AVR after |
|---|---|---|
| `usize` (i16) — the natural spelling | `i64 %t1` naming an i16 → **LLVM parse error** | `i16 %t1` |
| `i32` (wider than the pointer) | `i64 %t1` naming an i32 → **LLVM parse error** | `trunc` to i16 |
| `i8` (narrower) | `sext i8 → i64`, then an i64 index | `sext i8 → i16` |

The third row is the quiet one: it parses, `llc` legalizes it, and it emits
64-bit software arithmetic on an 8-bit MCU. A gate that only checks "does the
IR parse" cannot see it, so `run_w9_gep_index_width` asserts both — `llvm-as`
accepts the AVR IR, **and** no instruction line mentions `i64`. Both halves are
tripwires: against the pre-fix compiler the fixture fails the first outright and
shows 6 `i64` instruction lines.

**The workaround was committed in an example, and removing it is the
end-to-end proof.** `examples/avr-global-init.nuc` carried
`(aref g-pattern (unsafe/cast i64 g-step))` with a comment naming this defect —
which is why `make avr-test` had been green over a broken `aref` all along. The
cast is gone; the example links through the real avr-gcc driver and stays in
budget (942 flash / 7 RAM on the ATtiny1634).

**The fix is one function with three callers**, `gep-index-ir`
(`nucleusc.nuc`), placed above `emit-aref` so `union-emit.nuc`'s
`emit-ptr-add` — imported later — can share it. Three duplicated format strings
went away and the interner absorbed the replacement, so the module's string
table shrank by exactly three entries and gained none.

**Host evidence is the strong evidence here**, because this is a
target-conditional change and the host is the direction that must not move:
corpus sweep against the pre-fix compiler over `examples/`, `tests/fixtures/`
and `lib/` — **226 IR byte-identical, 0 differing, 155 rejected by both with
byte-identical stderr, 0 regressions, 0 new acceptances**. Per-function IR diff
of the compiler itself (`@.str.N` normalized): **3 changed — `emit-aref`,
`emit-aset`, `emit-ptr-add` — plus `gep-index-ir` added, 1179 identical**, and
the only top-level lines removed are the three now-unused format strings.
`make bootstrap` held the fixed point on the first pass. Tests 540 → **543 PASS
/ 0 FAIL**; `make avr-test` green on all five examples including the
simavr run; `abi-test`/`layout-test` green; 69 headers regenerate identically.
`riscv-test`/`riscv-abi-test` SKIP (no cross libc in the container, RV-2).

**One defect measured in passing, filed as item 32, not fixed here**: the
widening is `sext` for every index type, so a `ui32` index at or above 2^31
addresses *backwards*. Demonstrated with a running program, not inferred. It is
now a one-line fix precisely because item 15 gave the rule a single home — but
it is a different rule (signedness, not width), it moves host IR, and item 15's
value as evidence rests on the host not moving at all.

> **Fixed 2026-08-14 as the predicted one line, and the host did not move
> either**: 231 IR byte-identical / 2 differing over the same corpus, the
> compiler's own IR byte-identical, `make bootstrap` holding on the first pass.
> The clean separation this paragraph wanted turned out to be free. See the
> W9-32 note above.

### W9 item 13 as fixed *(2026-08-10)* — one null meaning both "absent" and "malformed"

`parse-type-from-node`'s `NODE-CELL` arm is a long chain of shape probes —
`ptr`, `ref`, `fn`, `array`, `struct`, `union`, `Maybe`, `BoxedFn`, `dyn`,
struct templates, union templates. When every probe missed, the `do` block ran
off its end and the function returned null. The `die-at "unable to parse type
expression"` that looks like the fall-through is `case`'s label-less default
arm, reachable only for a `NodeKind` outside `{NODE-SYM, NODE-CELL}` — so a
malformed *list* never reached it.

**The blast radius was understated twice.** The item names `defstruct`, where it
was found. But the null is the shared return of the type parser, and **no
caller can tell it from "no annotation was written"** — which is the other thing
a null means at every one of those call sites. Five positions carried the same
wrong message:

| written | reported before |
|---|---|
| `(defstruct S (xs (nosuch i32)))` | `defstruct: field 'xs' missing :type` |
| `(defn f (x:(nosuch i32)) …)` | `defn: missing :type on param 'x'` |
| `(defvar g:(nosuch i32) 0)` | `defvar: missing :type on 'g'` |
| `(let (a:(nosuch i32) 0) …)` | `let: missing :type on 'a'` |
| `(defn f ():(nosuch i32) …)` | `defn: missing :type on 'f'`, **at `:0:`** |

Every one of them blames the annotation for being absent while it sits in the
source being pointed at.

**The everyday trigger is not a typo — it is a forgotten import.** `(defn f
(x:(Vector i32)) …)` without `(import-use vector)` produced `defn: missing :type
on param 'x'`. That is the single most likely way a user meets this defect, and
the message sends them to inspect the one part of the line that is
unambiguously correct. It now reports:

```
unknown type: Vector — not defined anywhere in this compilation unit
  note: 'Vector' is defined in lib/vector.nuch, which no import in this unit reaches
```

which is W1c's reachability note, arriving here for free because the fix calls
`unknown-type-message` rather than inventing a local string — the same tiered
message `parse-type-name` has given a *bare* unknown type since W1c, now given
to the parametric spelling as well.

**Two mistake classes reach the fall-through, and one message would lie about
one of them.** A doubled annotation desugars to a list whose head is a real
type: `x:i32:i32` is `(i32 i32)`. Routing that through `unknown-type-message`
prints "unknown type: i32 — not defined anywhere in this compilation unit",
which is false, and worse than the message it replaced — *this was measured
after the first version of the fix, not predicted*. Telling the classes apart
needs a lookup that answers without dying, and `parse-type-name` ends in
`die-at`, so it cannot serve as one. Rather than write a second copy of the
built-in name list, the list was **extracted** from `parse-type-name` as
`builtin-type-name` (a pure `name -> ?ptr:Type`), leaving `parse-type-name`
shorter and giving the probe the same list by construction. `avr-reject-f64`
deliberately stayed behind in `parse-type-name`: the probe must not die.
`struct-lookup-ref` covers user types, so `(P i32)` for a `defstruct P` gets the
same message.

**`diagnostics.md` recorded the doubled-annotation message as *correct*** ("a
multi-colon chain that doesn't resolve to a real type is rightly rejected").
The rejection was right and the message was not; that row is amended in place
rather than deleted, since the reasoning it records is what a later reader would
otherwise re-derive.

**The `:0:` half fixed itself, and the gate had a hole.** The return-type
position reported line 0 — the class W4a exists to keep extinct — because the
caller's fallback had no node to blame. Dying at the type node, which has a
line, removes it. `run_no_line_zero` sweeps every `tests/fixtures/*.nuc`, so it
would have caught this the moment a fixture spelled an unparseable type; none
did. `w9-unknown-type-ctor-return.nuc` is now that fixture, and `run_reject`
fails on `:0:` independently of the message text.

**Verification.** Corpus sweep against the pre-item-13 compiler (rebuilt from
`fadee9a`'s committed boot IR, since `bin/nucleusc` had already advanced):
**376 IR byte-identical, 0 differing, 0 new rejections, 0 stderr differences** —
so no caller anywhere in the tree used the null as a soft "not a type" probe,
the one risk that could have made this fix unshippable. The compiler's own IR
moved, as extracting a function must: a per-function diff showed 454 changed,
which is **`@.str.N` renumbering**, not behaviour — normalizing the string
indices collapses it to exactly **2 changed (`parse-type-name`,
`parse-type-from-node`) + 1 added (`builtin-type-name`)**, with 1178 functions
byte-identical. `make bootstrap` held the fixed point on the first pass. Tests
535 → **540 PASS / 0 FAIL**; `abi-test`/`layout-test`/`avr-test` green;
`check-headers` clean (69 headers regenerate identically, which exercises the
`--emit-nuch` / `--emit-cheader` type paths this parser also serves).

### W9 item 9 as fixed *(2026-08-10)* — the comment stated the rule the code never implemented

`int-literal-fits` opened with a width shortcut:

```lisp
(defn int-literal-fits (v:i64 t:raw:Type):i32
  (let (w:i32 (int-width t))
    (when (<= w 1) (return 1))      ; "anything fits i1"
```

while the doc comment three lines above it said the predicate *"accepts the 0/1
idioms"* for i1/bool. The comment described the intended rule; the code
answered "fits" for every value. `(defvar g:i1 5)` reached LLVM as `global i1
5`, which LLVM accepts and silently truncates to `true` — measured end to end:
the program linked, ran, and read the global back as a true.

**The recorded cause was exact and the recorded scope was not.** The item names
the `defvar` spelling, because that is where it was found; but
`int-literal-fits` is the shared LW-4 predicate, so the identical hole sat at
every `coerce-int-val` position at once — `(let (a:i1 5) …)` emitted `trunc i32
5 to i1`, and so did a call argument, a field store, and a `return`. All five
now diagnose, each located and naming the value. A fix applied to
`defvar-init-ir` alone would have passed a global-only fixture and left four
live positions, which is why `w9-i1-local-too-big` exists.

**Item 8 had just given the hole a third caller.** `as-int-narrowing`'s new
literal channel asks `int-literal-fits`, which answered "fits" at width 1 — so
`(as i8 5)`'s relaxation silently relaxed `(as i1 5)` too, one commit earlier.
That is the argument for taking item 9 next rather than in numeric order: the
previous item widened its reach. Both are now closed by the same predicate.

**The rule is a ruling, and the negative fixture is what pins it.** `i1`/`bool`
holds `{0, 1}` — the two values `false` and `true` denote. The tempting
"correct" alternative is to delete the shortcut and let width 1 fall through to
the signed branch below, which computes `[-2^0, 2^0-1]` = `[-1, 0]`: that
accepts `-1` and **rejects `1`**, the value `true` denotes, inverting both
answers. `w9-i1-literal-negative` exists to fail if anyone ever makes that
change. `true`/`false` are `NODE-SYM` literals emitting `true`/`false` directly
and never reach the predicate, so the numeric spelling is the entire surface.

**Verification, and which gate is the strong one.** This is a *tightening*, so
— the complement of item 8 — the corpus sweep is the weak evidence and stage 2
is the strong one: a violating `i1` literal anywhere in the compiler's own
source compiles under the committed boot and is refused by the new logic when
it builds stage 2. `make bootstrap` held the fixed point on the **first** pass,
so the tightening cost zero edits to `src/`. The sweep of `examples/` + `lib/`
+ `tests/fixtures/` against the pre-fix compiler: **373 IR byte-identical, 3
differing — exactly the three new reject fixtures**, and zero pre-existing
programs newly rejected. Tests 530 → **535 PASS / 0 FAIL**;
`abi-test`/`layout-test`/`avr-test` green; `check-headers` clean.

**One defect found next door, measured and filed as item 31, not fixed here**:
`i1` is treated as a *signed* 1-bit integer, so `(as i32 true)` is −1 and
`(< false true)` and `(> true false)` are both false. Same type, adjacent code,
but a different cause (`is-unsigned`'s missing `TY-I1` arm) with 22 call sites
and a bootstrap move — a separate item, not a widening of this one.

### W9 item 8 as fixed *(2026-08-10)* — the safe cast was stricter than the machinery it makes explicit

`as` decided "is this a narrowing" from the two **widths** alone:

```lisp
(defn as-int-narrowing (src:raw:Type dst:raw:Type):i32
  (if (< (int-width dst) (int-width src)) (return 1) (return 0)))
```

So `(as i8 5)` was an error — while the *implicit* coercion at the identical
slot, `(let (a:i8 5) …)`, compiled and emitted `trunc i32 5 to i8`, the very
instruction the explicit spelling was refusing to emit. That is the framing the
recorded item ("over-strict") understates: `as` exists to write down a
conversion the machinery would otherwise perform silently, so a conversion the
machinery performs and `as` refuses is not a strictness *policy*, it is the form
failing at its one job. Narrowing is a property of the **value** wherever the
value is known, and both askers already know it.

**The literal channel, at both askers.** `as-int-narrowing` takes `is-lit`/`lit`
and returns 0 for a literal that `int-literal-fits` in the destination — the
same predicate `coerce-int-val` gates the implicit path with, so the two now
accept exactly the same set of literals rather than merely similar ones.
`emit-as` passes `Val.is-lit`/`lit-i64`; `const-fold-int` passes `1` and the
folded value, unconditionally, because everything that reaches it folded to a
known constant. Passing `is-lit` 0 still asks the widths-only question, which is
what a runtime value wants.

**Three accept shapes, not one.** The value path (`(as i8 5)`), the `defconst`
path (`(as i8 SMALL)` — W2b already tags a constant's `Val` with the literal it
stands for, so this came free and is pinned so it cannot regress), and the
constant-folder path (`(defvar g:i8 (as i8 9))`, which emits `@g = global i8 9`,
a plain constant with no cast expression). The signed/unsigned bounds are pinned
exactly: 127 and -128 into `i8`, 200 into `ui8`, 65535 into `ui16`.

**What still rejects, and why each is the right side of the line.** A narrowing
*value* (`as-lossy.nuc`'s `(as i8 n:i32)`) — the runtime value is unknown, and
this is the distinction the old rule should have drawn. A literal that does not
fit by magnitude (`(as i8 300)`) or **by sign** (`(as ui8 -1)`) — a range test
that compared magnitudes would have wrapped -1 to 255 silently, so it gets its
own fixture. And `g1-as-lossy.nuc`'s `(as i32 5000000000)` in a global, which
still dies at the fold.

The diagnostic is deliberately unchanged. `as: lossy conversion from i32 to i8
-- use unsafe/cast` names the escape hatch, which is what the user of an
explicit cast needs; the implicit path's `integer literal 300 does not fit i8`
names the value, which is what someone who wrote no cast at all needs. Each is
right for its path.

**Not widened into floats, deliberately.** `(as f32 1.5)` is refused by the same
shape one step over, and `1.5` is exactly representable in `f32` — the fix is
~6 lines and the round-trip predicate is already written inside `f32-const-ir`.
It is left alone and filed as **item 30** because `global-init.md` records that
rejection as expected behaviour, so changing it is a ruling rather than a bug
fix, and because `as`'s float answer has a genuine question in it that the
integer answer does not: whether `as` accepts only exact round-trips (keeping
its no-loss promise, and so staying *stricter* than the implicit path's
deliberate Option A rounding of `3.14`) or follows the implicit path wholesale.
This does mean `as` now narrows int literals and not float literals — an
asymmetry this fix introduces and item 30 closes.

**Verification.** `make test` **530 PASS / 0 FAIL** (526 before, +4). The corpus
sweep is the strong evidence here, because the change is purely permissive:
compiling all 372 programs in `examples/` + `lib/` + `tests/fixtures/` with the
pre-change compiler and the new one gives **371 byte-identical IR and 371
byte-identical stderr**, the single difference being the new accept fixture,
which previously did not compile. Nothing that compiled before compiles
differently. `make bootstrap` held the fixed point on the FIRST pass, before
`update-bootstrap` — expected for a relaxation, and it is also the check that
the compiler's own source contained no `as` whose meaning changed. `abi-test` /
`layout-test` / `avr-test` green; `check-headers` clean.

**Files.** `src/type-utils.nuc` (`as-int-narrowing`), `src/nucleusc.nuc`
(`emit-as` step 5, `const-fold-int`'s `as` arm), three new fixtures,
`tests/run-tests.sh` (`run_w9_as_literal_narrowing` + 2 rejects),
`docs/special-forms.md`, `docs/types.md`, `docs/builtins.md`,
`docs/toplevel.md`, `design/stage14/unsafe-namespace.md`, and the reconverged
boot artefacts.

### W9 item 7 as fixed *(2026-08-10)* — a premise about a literal, applied to a type

`pkind-flow-check` fired only when the SOURCE was `TY-PTR`. A `CStr` is
`TY-CSTR`, so `ptr-pkind` answers PTR-RAW for it and it fell out of the check
entirely. Measured, all three compiling clean and then **segfaulting**:

```
(defvar g:ptr:P (as CStr null))          ; @g = global ptr null   → SIGSEGV
(let (p:ptr:P (as CStr null)) …)         ; store ptr null         → SIGSEGV
(let (e:CStr (getenv "UNSET")            ; the realistic shape
      p:ptr:P (as ptr:P e)) …)           ;                        → SIGSEGV
```

**The exemption was justified by a claim that is true of a string LITERAL and
false of the type.** `as-ptr-convert` stated it outright — *"CStr is
ref-compatible (a C string is a non-null constant)"* — and
[nullability.md](../stage10/nullability.md) §9.1 calls it "the direct analogue"
of the elem-less-destination refinement. It is the opposite of that analogue.
The `void*` exemption is sound **because the destination cannot be
dereferenced**, so a non-null obligation on it protects nothing; here the
destination is a typed pointer and is dereferenced on the next line. `getenv`
returns a `CStr` and returns null.

**Two sites, one premise, and the second is why `as` had to change too.** The
chokepoint (`pkind-flow-check`, `TY-PTR` → any `is-ptr-like` source) covers
binding, `set!`, argument, return and — since W6 routed the constant renderer
through the same predicate — the global position. But `as-ptr-convert` held its
own copy: a `sk == TY-CSTR` arm returning the retyped value *before* the flow
rule ran. Deleting that arm needed no replacement, because a CStr names no
pointee and so falls into the elem-less (`void*`) hatch below it — which already
applies the flow rule. One rule, one place.

**The direction is the whole of the surviving carve-out.** A null INTO a `CStr`
slot is ordinary C and stays legal; `tests/fixtures/w5c-cstr-null-exempt.nuc`
pins it and its comment now says which direction it guards.

**Blast radius, measured rather than estimated: 17 sites, all of them the same
shape.** One in `lib/`, sixteen in the compiler's own source — every one a byte
walk or offset over a C string (`(as ptr:i8 name)` for a suffix compare, a prefix
strip, a segment extract). Fifteen of the sixteen became `(as raw:i8 …)`: the
pointer really is contract-free, `aref`/`unsafe/ptr+` through a `raw` is the
documented unchecked waiver, and the emitted IR is identical — so the fix is to
stop *claiming* non-null, not to assert it.

The two that got more than a respelling are the ones where the claim was
load-bearing:

* `lib/hash.nuc`'s `Hash` conformance for `CStr` walked the key's bytes through a
  `ptr:i8`. The key comes from the CALLER — `(assoc m k 1)` with a null `k` used
  to segfault inside the fold — and `hash` has no error channel, so it now
  guards and reports `hash: null CStr`, following `vector-bounds`' precedent for
  exactly this situation. Verified by running it.
* `src/union-registry.nuc`'s `fnv-str` is the same algorithm with three internal
  callers that pass registry names, non-null by construction; it takes the
  respelling with a comment saying why it needs no guard where `lib/hash.nuc`
  does.

**A finding about my own verification, worth recording.** The corpus sweep
(`examples/` + `lib/` + `tests/fixtures/` = 366 programs) went to **zero changed
diagnostics** after the one `lib/` fix — and that was misleading, because it does
not compile `src/`. All sixteen compiler-source violations surfaced only at
`make bootstrap`'s **stage 2**, where the new compiler compiles the compiler;
`make` itself passes, because stage 1 is built by the committed boot binary,
which does not have the new rule. For any change that tightens a rule, the
corpus sweep is not the measurement — stage 2 is.

**Verification.** `make test` **526 PASS / 0 FAIL** (523 before, +3). IR sweep
180 normalized-identical / 0 differing; **185/188 fixtures byte-identical
stderr**, the three differences being the new rejection fixtures, which is the
hole. `make bootstrap` reconverged; `abi-test` / `layout-test` / `avr-test`
green; `check-headers` clean — it caught `lib/hash.{h,nuch}` going stale, its
second real catch.

**Files.** `src/type-utils.nuc` (`pkind-flow-check`), `src/nucleusc.nuc`
(`as-ptr-convert` + 8 respellings), `src/union-registry.nuc` (`fnv-str` + 4),
`src/generics.nuc` (2), `src/nuch.nuc` (1), `lib/hash.nuc` (guard + `stderr`
import), three new fixtures + `w5c-cstr-null-exempt.nuc`'s comment,
`tests/run-tests.sh`, `design/stage10/nullability.md`, `docs/types.md`, and the
reconverged boot artefacts.

### W9 item 6's string-path half as fixed *(2026-08-10)* — one import, two spellings, two answers

`(import-use foo)` and `(import-use "sub/foo.nuc")` name the same file and are
the same import. Both prescan passes — `prescan-imported-types` (types) and
`prescan-imported-signatures` (signatures + G-0's values) — walked the
**`NODE-SYM` spelling only**, so the string spelling registered nothing and every
name in that file resolved on import ORDER. Measured, all four failing before and
passing after, each with the symbol spelling of the identical program as the
control:

| Used before the import | String path, before | Symbol, before |
|---|---|---|
| a `defn` | `unknown: helper` | ok |
| a `defconst` | `undefined: HELP-K` | ok |
| a `prefix/name` | `unknown: helper/helper` | ok |
| a struct in a signature | `unknown type: TyRec` | ok |

**The fix is one rule, not two arms.** `import-form-path` answers the path for
either spelling — a symbol resolves through the search path, a `.nuc`/`.nuch`
string *is* the path — and both passes call it. That is not a new convention:
`do-import`'s own `NODE-STR` branch takes the string verbatim with no search, so
the prescan now derives exactly what emission will use. The comment the old code
left in pass 1 (*"a `.nuc`/`.nuch` string path … is left to the symbol branch's
shape"*) was a restatement of the gap, not a reason for it — unlike pass 2's
`.nuch` skip, which gives one and is item 29.

**A second disagreement between the spellings, found writing the guard and
fixed with it.** The prescan must not call `read-file` on a path that may not
exist — it would `perror`+exit from a call site with no line. Guarding it with
`file-exists` raised the question of what the *existing* diagnostic was, and the
answer was that `do-import`'s string branch could not diagnose a missing file at
all: its `(when (= path null) (die-at …))` tests a value assigned two lines
above as `(nn s)`, so it was **provably dead**, and a missing file fell through
to `read-file`'s unlocated `perror` — while the symbol spelling of the same
mistake says `import: cannot find 'x'` at the import's own line. Same mistake,
same diagnostic now. Pinned by `w9-string-path-missing-file-located`.

**One thing deliberately NOT claimed.** A field *access* before the import still
fails — `_get: no field 'n' on struct 'SpRec'` — because pass 1 registers struct
NAMES, not layouts. Measured identical for the symbol spelling, so it is the
W1d name-vs-layout split, not this item; the test says so and stays off it.

**Verification.** `make test` **523 PASS / 0 FAIL** (520 before, +3). Emitted IR
unmoved: 180 normalized-identical / 0 differing against the pre-change compiler,
and **185/185 rejection fixtures produce byte-identical stderr** — the sweep that
matters here, since the change is to name resolution and to a diagnostic.
`make bootstrap` was byte-identical on the first pass before reconverging (the
compiler's own source uses only the symbol spelling, so nothing about its
emission could move); `abi-test` / `layout-test` / `avr-test` green;
`check-headers` clean.

**Files.** `src/nucleusc.nuc` (`import-form-path`, both prescan passes,
`do-import`'s string branch), `tests/run-tests.sh`
(`run_w9_string_path_prescan`, +3 PASS), `docs/toplevel.md`, and the reconverged
boot artefacts.

**Defect 6 and W8's G-0 — closed at the cause, 2026-08-01.** G-0 fixes the
*cause* rather than the message: value names now resolve on reachability
rather than import order, so the diagnostic stops firing for a `defvar`/
`defconst`/`defenum` name that is in the unit, for both import shapes the new
prescan walks (plain and `import-use` symbol imports). A W1c-style interim
note on the message itself — the smallest-blast-radius fallback, since W1c
established exactly this pattern for exactly this shape of failure — was
**deliberately declined** once the cause-level fix landed the same day. The
message can still fire truthfully for the residual surface G-0 does not walk:
string-path `.nuc` imports and `.nuch` headers, filed as a W1 follow-up rather
than reopening this defect.

**Defects 1 and 2 are directly relevant to W8**, not incidental: they are the
multi-TU mode `global-init.md` §2.4 relies on for its finding that an
initializer list reachable only from the consumer's `main` cannot initialize a
library. Both are fixed as of 2026-08-09, so that mode now works for a library
built from ordinary (non-`exclude-prelude`) sources; the residue W9 item 2's note
records is that a *run-time* initializer in an inlined file runs once per object
rather than once per program.

### W9 item 1 as fixed *(2026-08-09)* — the ROOT file joins the import graph

`make lib-headers`, `make lib-cheaders` and `make lib-objs` all succeed;
`make lib-so` still failed at this point, for **item 2's reasons only** (each
object inlines the whole prelude, so `vector.o` and `combinators.o` both define
`vector-oom`, `next.pIntRangeIter`, …). Nothing here bore on item 2 — it stayed
an architectural question about how the prelude participates in a multi-TU
build, and was **closed later the same day**; see the W9 item 2 note below.

**Cause.** The recorded hypothesis — "the auto-prepended prelude chain imports
the entry file itself, and the entry file is on no dedup list" — is right about
the *mechanism* and incomplete in three ways that each cost a separate fix:

1. **It is two omissions, not one, and the recorded symptom is only the first.**
   The root is absent from `g-prescan-sigs` (so `prescan-imported-signatures`
   re-registered its signatures, and `generic-register-method` appends
   unconditionally → `duplicate definition of 'arena-init'`, blamed at the file's
   own line) **and** from `g-importing` (so `do-import` would then have read and
   emitted the file a *second time*, duplicating every `define`). Only the first
   was visible, because it fires first and aborts. The `g-importing` half is what
   `w9-root-cycle-skip-single-emission` pins.
2. **A cycle skip on the root is wrong, not merely conservative — and that is
   where the design work was.** Pushing the root onto `g-importing` makes the
   re-entry take W1d's existing cycle path, which fixed `arena`/`node` and
   immediately *regressed* `lib/macros.nuc`: skipping macros' body means
   `lib/arena.nuc` never sees `when`. A cycle deliberately does not carry macros
   — but here the "cycle" is one the auto-prelude created, and the skipped file
   is exactly the one holding what the rest of the chain is about to use. The
   resolution is a **hoist**: `do-import` emits the root *there*, at the first
   point the unit reaches it, and the depth-1 loop stops because its own path is
   now on `g-imported`. It is guarded by a one-shot window (`g-root-hoist-ok`,
   armed before the depth-1 loop, cleared after the loop's first iteration),
   because hoisting after the root has emitted any of its own forms would emit
   those forms twice. The auto-prelude import *is* that first iteration, which is
   why the window is exactly wide enough and no wider. Outside it, the ordinary
   cycle skip still applies.
3. **`lib/reader.nuc` was not the same defect at all.** It is not a library: it
   reads and writes `g-src`/`g-pos`/`g-line`/`g-source-path`/`g-peek`/
   `g-interactive`/`g-mono-context`, which `src/nucleusc.nuc` defines — a fact
   `context/build.md` had already recorded. It is now **`src/reader.nuc`**,
   beside `repl.nuc`/`cheader.nuc`/`format.nuc`, which is the same call made for
   the same reason. `lib/` means "compiles on its own"; that is precisely the
   invariant `make lib-objs` asserts, and the new
   `w9-lib-emit-llvm`/`-nuch`/`-cheader` units assert it for every file.

**A fourth defect the record did not have: `make lib-headers` was broken for a
completely different reason, and worse than reported.** The brief cited one file
(`lib/char.nuc`, `(Result T E) template not in scope`); the real count was
**nine**, and the cause is that `--emit-nuch` was *exempted from the prelude*
and `emit-nuch-header` processed no imports at all. A `.nuch` exports
signatures, and a signature names types — so `Node`, `StrView`, `String`,
`(Maybe T)` and `!T`'s `(Result T E)` were all unresolvable. Fixed by dropping
the exemption and giving `emit-nuch-header` the two prescans
`emit-toplevel-forms` runs for the same reason (`prescan-file-imports`,
`prescan-imported-types`). `--emit-cheader` keeps the exemption deliberately: it
exports the C-representable subset, which cannot name a prelude type. The three
committed headers (`lib/mathlib.nuch`, `lib/boxlib.nuch`) regenerate
byte-identically.

**Files.** `src/nucleusc.nuc` (the root push + hoist window + loop exit,
`import-reentry-hoists-root`, the `exclude-prelude` dispatch case, the
`--emit-nuch` prelude), `src/nuch.nuc` (two prescans), `lib/reader.nuc` →
`src/reader.nuc`, `Makefile` (`COMPILER_DEPS`), `tests/run-tests.sh` (five new
units, seven PASS lines).

**Verification.** `make test` **499 PASS / 0 FAIL** (492 before, +7 new lines).
`make bootstrap` reaches its fixed point (`stage1.ll == stage2.ll`) and stage 2
compiles and runs `hello.nuc` — no reconverge needed, since the change moves no
IR for any unit that compiled before. `make abi-test` / `make layout-test` /
`make avr-test` green; `riscv-test` / `riscv-abi-test` SKIP (the container's
known missing `libc6-dev-riscv64-cross`). `resolution-matrix.sh --check`
unchanged (43 cells). **Sweep** against a compiler built from a clean `HEAD`
worktree, over `examples/` + `lib/` + `src/reader.nuc` (182 files): **176
byte-identical, 2 differing, 2 newly compiling (`lib/arena.nuc`,
`lib/node.nuc`), 0 regressed, 2 failing under both.** Both differences are the
*removal* of the double emission and nothing else: `lib/macros.nuc` loses 88
lines, all of them `@.str.N` constants from the second copy of the file, with
its 15 `define`s unchanged and zero added lines; `lib/prelude.nuc` loses exactly
one blank separator line. The two still-failing files are
`examples/comb-shapes.nuc` (`as: lossy conversion from usize to i32`,
pre-existing and unrelated) and `src/reader.nuc` (not a library, by the ruling
above — and no longer built by `make lib-objs`). A second sweep over the 185
rejection fixtures' stderr: **185 identical, 0 changed**.

**Known limit, deliberately not widened.** Path identity throughout the import
machinery is string equality on the *spelling*, so a root compiled by an
absolute path while its importers resolve a relative one is not recognised as
the same file. That is pre-existing (`g-imported` has always keyed this way) and
the fix inherits it rather than introducing it; canonicalising would move every
path string in every diagnostic.

### W9 item 2 as fixed *(2026-08-09)* — a definition the unit does not OWN is `weak_odr`

`make lib-so` builds `build/lib/libnucleus.so` from all 34 library objects, and
two separately compiled Nucleus objects link and share their state. The item's
own framing — "an open architectural question about how the prelude participates
in a multi-TU build" — had the question right; the answer is that **it does not
need to**. A `.nuc` import is *inlined*, so a copy of the prelude in every object
is not a bug to remove but a fact to give the right linkage, which is exactly
C++'s `inline`/template rule.

**The rule, and it is ownership, not privacy or reachability.** One classifier,
`def-linkage` (`src/nucleusc.nuc`), answers for both emitters — `emit-defn`'s
`define` and `emit-defvar`'s `@g = global`, which previously each carried their
own two-branch `internal`-or-not `if`. `internal` when private (unchanged),
`weak_odr` when the unit only carries a **copy**, external otherwise. A copy is:
a form written in a file this unit *imports* (`g-source-path` ≠
`g-unit-entry-path`, by string equality — `do-import` resolves a path afresh per
import form, so the root re-entered through the auto-prelude is an equal but
distinct string), or a **monomorphized stamp**. The linkage word carries its own
trailing space and is one `%s`, so every pre-existing shape is byte-identical.

**A stamp belongs to no file, and the call site's path answers the wrong
question.** `lib/string.nuc` and `lib/combinators.nuc` each stamp
`vector_init.pVector.u8`, both while their own file is the root — so the obvious
"is `g-source-path` the root?" test makes both copies external and they collide
exactly as before. `drain-mono-worklist` arms `g-emitting-copy` around the one
`emit-defn` that emits a stamped body instead. This is the same distinction B4
already had to make for the stamp's *namespace* (`generic-instantiate-in`'s
`(.set! newm src-ns (mm src-ns))`), reached from the other direction.

**`weak_odr`, not `linkonce_odr` — and the difference is not cosmetic.** The two
merge identically at link time and are equally non-interposable, so
`linkonce_odr` was the first choice. It is also **discardable when unreferenced**,
and `clang -O3` deleted every imported function it had fully inlined: the
compiler's own `make bootstrap` died `JIT session error: Symbols not found:
[ alloc-node ]` with `define linkonce_odr ptr @alloc-node()` plainly present in
`stage2.ll`. Macros are JIT-compiled *during* compilation and resolve callees by
name against the running program's dynamic symbol table (`-rdynamic`), so the
optimizer removing a definition is a compile-time failure, and it is reachable
from any user program whose macro calls an imported function — not a
compiler-only accident. The price of `weak_odr` is that an unused imported
function is no longer dead-stripped: `build/nucleusc` grows 812,264 → 820,312
bytes (**+1.0 %**), recoverable with `-ffunction-sections`/`--gc-sections`, which
is a link-flag question rather than a linkage-word one. Recorded in
[conventions.md](../../context/conventions.md).

**One synthesized global is genuinely per-unit and had to go the other way.**
`@nuc_err_names` / `@nuc_err_messages` were emitted `constant` with external
linkage and collided across 11 of the 34 library objects. They cannot be
`weak_odr`: `deferror` ids are assigned per compilation unit, so the *contents*
differ between two objects of one program and merging them would be a real ODR
violation rather than a harmless one. They are now `internal` — every reference
is a GEP emitted into the same module (`union-emit.nuc`, `emit-err-field`), so
nothing outside needs the symbol. Cross-unit id *agreement* is a separate,
pre-existing hole this does not touch.

**Verification.** `make test` **501 PASS / 1 FAIL** (498 before; +3 new lines).
One FAIL at that point, `b3-type-ns-not-in-scope`, was **pre-existing and
unrelated** — reproduced identically on a compiler built from this working tree
with only these edits reverted, which is how every count here was attributed
rather than assumed. It was then diagnosed and fixed too; see the follow-up
below. Final: **504 PASS / 0 FAIL**.

`make bootstrap` **deliberately moved and was reconverged.** Before reconverging,
the new compiler was shown to be a fixed point independent of any committed
artefact (stage2 compiles itself byte-identically), then the whole stage1→stage2
move was characterised: normalizing away the linkage token alone leaves a
**6-line** diff, which is the two `@nuc_err_*` lines gaining `internal`. Nothing
else in 142,000 lines changed. 722 `define`s and 24 globals gained `weak_odr`.

**Sweep** against a compiler built from this tree with the edits reverted, over
`examples/` + `lib/` + `src/nucleusc.nuc` (182 files): **181 normalized-identical,
0 differing, 0 regressed, 0 newly-compiling, 1 failing under both**
(`examples/comb-shapes.nuc`, the same pre-existing `as: lossy conversion` W9-1
recorded). A second sweep over the 185 rejection fixtures' stderr: **185
identical, 0 changed**. `make abi-test` / `make layout-test` / `make avr-test`
green; `resolution-matrix.sh --check` unchanged (43 cells).

**Tests.** `run_w9_multi_object` is deliberately not a "does it link" test — a
linker that kept two *private* copies of `g-arena` would also link, and every
object would then have its own arena and its own intern table. Two objects bump a
shared counter from opposite sides and the third read must be `1 + 2 = 3`, which
is reachable only if the copies merged; a companion assertion confirms both
objects really do carry a weak `arena-init`, without which the first proves
nothing. `w9-linkage-ownership` pins all three answers from one `--emit-llvm`
(root external / imported `weak_odr` / private `internal`). Two existing units
that pinned a linkage word by exact match — `w1-late-overload-symbol` and
`s1-nuch-template-stamps` — were **updated to assert the new word**, not loosened
to accept either: the word is the unit's answer to "do I own this", and a silent
flip back is the multi-object link failure returning.

**Known limit, not fixed here — and the once-guard is a trap, measured.** A
`defvar` whose initializer the compiler cannot fold to a constant is initialized
from its unit's `@__nucleus_init` constructor (G-3). When several objects each
inline the file declaring it, each object's constructor initializes the
now-shared global, so such an initializer runs **once per object**: measured, a
two-object link whose initializer bumps a counter observes **2**, not 1. No file
in `lib/` has one today (zero `llvm.global_ctors` across all 34 library objects),
so this is latent rather than live.

"Then guard it so it runs once" does not work, for a reason that is in the queue
rather than in the guard. **The initializer queue is strictly source order across
the whole unit, and ownership interleaves within it.** Measured, all three legal
and all three accepted by G-4's ordering check: a root-owned `gx-x`; then an
*imported* `gb-y` reading `gx-x`; then a root-owned `gx-z` reading `gb-y`. So:

* **Grouping the shared initializers** (all copies first, then the unit's own)
  reorders them against exactly those cross-ownership reads. `gb-y` would run
  before `gx-x` and silently read 0. This is not an edge case — reading *across*
  the boundary in both directions is the normal shape, which is why the queue is
  one list in source order to begin with.
* **Guarding each contiguous shared run in place** preserves order inside one
  object and breaks it *between* objects. Object B skips the shared run (A
  claimed the flag) but still runs its own initializers in place — and
  `.init_array` order across objects is link-order dependent, which no Nucleus
  rule controls. If B's constructor runs first, B reads a shared global A has not
  written yet. That trades a **leak** (double init: loud enough to find, and a
  no-op for any idempotent initializer) for a **silent use-before-init**, which
  is the failure class this whole work stream exists to remove. Strictly worse.
* **G-4's diagnostic would stop describing run time.** `defvar-check-init-order`
  reasons about *queue* position — "already reached" — to reject a forward read.
  A guard changes run-time order without the check knowing, so the compiler would
  keep accepting programs on a premise that no longer held.

The shape that genuinely gives once-per-program *and* correct order is
per-**variable** lazy initialization — a flag tested at every read — which is
precisely the hand-rolled `ensure-*` pattern [../global-init.md](../global-init.md)
§0 correction 3 measured and set out to remove (21 of them in the Doom port, 20
needing no runtime initialization at all). It is also the problem C++ does not
solve: an `inline` variable gets a guard per variable and its order relative to
other translation units stays unspecified.

**So the rule, not the mechanism, is the place to fix this**, and G-1/G-2 already
made the rule affordable: a constant initializer covers named constants,
`(sizeof T)`, `(as T x)`, addresses, and constant struct/array aggregates, so
most library globals can be written that way — and one that is costs *less*, since
no constructor is emitted at all.

**The diagnostic was then built** (`warn-shared-runtime-inits`), which is the
half of the condition the compiler can actually prove. Two rulings, each with one
reason:

* **Warning, not error.** A single Nucleus object linked against C is supported
  and there the initializer runs exactly once — refusing it would break
  `run_g3_library`, the case §2.4 says nothing else covers.
* **`-c` only.** `-c` is the one flag that says "relocatable object bound for a
  link with other objects". A default build is whole-program and correct by
  construction. `--emit-llvm` says nothing about the eventual link — it is
  equally how a whole program is inspected, and G-4's own cross-file fixtures are
  exactly that shape, so warning there would be a false positive on programs that
  are fine. The compiler cannot see the other half (does another object also
  inline this file?), so it reports the property it can prove and names the fix.

Pinned by `run_w9_shared_init_warning`, whose three *silent* arms carry the
weight: the owning object, `--emit-llvm`, and a whole-program build — the last
asserted **by value** (the initializer runs once, exit 1), so a future change
that silenced the warning by suppressing the constructor would fail here rather
than pass quietly. A fourth arm measures the limit itself by value (two objects,
exit 2), so if it ever becomes 1 the test fails and `docs/compiler.md` is what
needs updating. Separately, `run_w9_lib_standalone` now **gates the invariant for
`lib/`**: no library file may carry a run-time initializer for a global it does
not own, since `make lib-so` links all 34 objects. True today — adding one is now
a test failure rather than a silent double init.

### Follow-up, same day: source out-ranks header — and the first cause recorded for it was wrong

The pre-existing `b3-type-ns-not-in-scope` failure above was recorded as "a
generated `lib/foo.nuch` **shadows** `lib/foo.nuc`, so the fixture imports the
header". **That is false, and it was falsified by reading the code the ruling
would have changed.** `resolve-import` already tries `.nuc` across *every* search
directory before it tries `.nuch` in any of them — measured, not inferred: the
probe emits `define weak_odr i32 @dp__describe`, an inlined definition, so the
import took the source with the header sitting beside it. The user's ruling
(*source out-ranks header*) was therefore **already the behaviour on the import
side**; what needed it was the diagnostic side.

**The real cause.** `path-in-unit` keyed on the exact path spelling, so
`lib/nsdescribe.nuch` was a *different* file from the `lib/nsdescribe.nuc` the
unit imports — hence "outside the unit", hence a legitimate answer for W1c's
unreachable-definer scan (`nuc-source-name` accepts both extensions, correctly).
`unknown-type-message` runs that scan **before** B3′'s
`type-in-other-namespace-message`, so the moment `make lib-headers` had been run,
a truthful and actionable "unknown type: Fox — defined in namespace 'dp' / note:
write 'dpx/Fox' here" was displaced by "defined in lib/nsdescribe.nuch, which no
import in this unit reaches" — naming, as an unreachable file, the very library
the author was already importing.

**The fix is the ruling, applied where it bites.** `import-sibling-path` pairs
the two spellings of one library and `path-in-unit` consults both. Symmetric on
purpose: a unit that imports the `.nuch` must not be told about the `.nuc`
either. The tier ORDER is left alone — the scan is right to precede the namespace
tier for a name genuinely outside the unit; it was the membership test that was
wrong, and fixing the membership test is what keeps this from being a
special-case reshuffle.

**Verified as a regression test, not just as a green suite.**
`run_w9_source_outranks_header` builds the shape from scratch (a `(ns shn)`
library, its generated sibling header, a prefixed importer writing the bare name)
rather than depending on which artefacts happen to sit in `lib/`, and asserts
both halves: the import resolves to the source (an inlined `define`), and the
diagnostic neither names the sibling header nor loses the namespace tier. On the
pre-fix compiler it produces the reachability message; on this one, "defined in
namespace 'shn' / note: write 'shp/W9Rec' here".

**A defect this found in the item-2 work itself.** `run_w9_multi_object`'s
comment claimed `w9side` resolved to the header "because only `$d/inc` has it" —
which the ranking above makes false: the sibling `.nuc` was on the consumer's
search path and won, so main.o inlined it and *nothing crossed the object
boundary*. The unit still passed, because both objects then carried weak copies
and the shared counter still read 3 — a test passing for a reason its author did
not intend. Restructured into `share/` + `side/` + `inc/` so `w9side.nuc` is on
no path the consumer searches, and the cross-object call is now **asserted**
(`nm` must show `U w9-side-bump` in main.o), not assumed.

Fixture-diagnostic sweep after this change: **184 identical, 1 changed** — the
one changed is `b3-type-ns-not-in-scope`, which is the fix. IR sweep re-run: 181
normalized-identical, 0 differing, 0 regressed. `make test` **504 PASS / 0
FAIL**; `make bootstrap` reconverged again and green; `resolution-matrix --check`
unchanged (43 cells).

**Files.** `src/nucleusc.nuc` (`g-emitting-copy`, `def-linkage`, both emitters,
the two `@nuc_err_*` lines, `path-in-unit-exact` / `import-sibling-path` /
`path-in-unit`, `warn-shared-runtime-inits`), `src/generics.nuc`
(`drain-mono-worklist-in`),
`tests/run-tests.sh` (`run_w9_multi_object`, `run_w9_source_outranks_header`,
`run_w9_shared_init_warning`, the `lib/` shared-init gate, +12 PASS lines; two
updated assertions), `docs/compiler.md`, `context/build.md`,
`context/conventions.md`, and the reconverged `bin/nucleusc` / `boot/nucleusc.ll`
/ the two Windows boot IRs.

---

### W9 item 3 as fixed *(2026-08-10)* — a global's C name is not its sanitized name

`--emit-cheader` exports a public `defvar` as `extern T name;`, and a C program
that `#include`s the generated header reads the globals, calls in to mutate one,
and sees the new value. `emit-cheader-header`'s dispatch simply had no `defvar`
arm — while **both** `docs/compiler.md`'s flag table ("`extern` declarations for
`defvar` and `extern` globals") and `docs/toplevel.md` ("visible to C consumers
(`extern T name;`)") already described the behaviour as present. Documented and
unimplemented in two places is worse than undocumented: nobody re-checks a
sentence that reads like a statement of fact.

**The missing arm was the easy half. The design is the NAME.** A global's link
symbol keeps its hyphens — `(defvar tick-count:i64 41)` emits `@tick-count`, and
`nm` shows `D tick-count` — and `tick-count` is not a C identifier. Measured, both
directions:

* sanitizing to `tick_count` produces a header that **parses and then fails to
  link** (`undefined reference to 'tick_count'`);
* `extern int64_t tick_count asm("tick-count");` **reaches the real symbol** (the
  C consumer reads 41).

So a name that needs sanitizing carries an `asm` label, and — deliberately — one
that does not carries none, so a library with C-legal names still gets a fully
portable header and the GCC/Clang extension appears exactly where it is
load-bearing.

**This falsifies W9 item 4's recorded cause**, which says "The fix is a missed
call site, not a missing mechanism" and lists the sites where `sanitize-for-c` is
not called. That holds for **type names, field names, `defunion` arm names and
enum tags** — none of which the linker resolves, which is why sanitizing the
struct *type* name was correct and complete. It does **not** hold for function
names or global names: adding `sanitize-for-c` there would convert a header that
fails to *parse* into one that parses and fails to *link*, moving the error away
from its cause. Item 4 is therefore not a missed call site; it is the same
`asm`-label decision this item just made and proved, applied to `defn`. That
makes it small and mechanical now, but it is a **ruling** (a GCC/Clang extension
in every generated header for a hyphenated library) rather than an oversight, so
it is left for its own item rather than folded in here.

**Two rulings on which globals get a line at all.**

1. **A declaration the C compiler trusts and gets wrong is worse than an
   omission.** `type-node-to-c` answers `void*` for every cell head it does not
   recognise — size-correct for a pointer, silently wrong for anything else, so
   `(defvar m:(Maybe i32) …)` would have declared a pointer-sized object over a
   struct. (The two skips `emit-cheader-declare` already had do not catch it:
   `--emit-cheader` is deliberately exempt from the prelude, so `Maybe` is not a
   registered template here.) `cheader-defvar-type-ok` admits only what that
   function genuinely spells — a plain type name, or a pointer under any of
   `ptr`/`raw`/`ref` — and everything else gets a located `/* … not exported */`
   comment.
2. **By value, a user type's C spelling is the typedef name, not `struct NAME`.**
   `emit-cheader-defstruct` emits an *anonymous* `typedef struct { … } NAME;`, so
   `struct NAME` is a different, incomplete tag: `extern struct SR s;` compiles
   until the first `s.a` and then fails with "incomplete definition of type
   'struct SR'" (measured). Harmless behind a pointer, which is why the
   pre-existing prototype path never noticed. `cheader-by-value-c` strips the
   prefix `type-node-to-c` just added rather than re-deciding builtin-vs-struct,
   so the builtin list stays in one place.

**One pre-existing defect had to be fixed for this item to emit a correct line.**
`type-name-to-c` had no `usize`/`ssize` case, so both fell through its "assume
struct" arm and emitted `struct usize` — a type that does not exist. This was
already recorded in [cheader.md](cheader.md) as a known `--emit-cheader` defect
and **14 of the 34 committed `lib/*.h` carried it**, silently unparsed. Item 3
turned it from latent into load-bearing: `lib/keyword.nuc`'s `g-keyword-count` is
a `usize` **global**, so the choice was to fix the mapping or knowingly emit a
broken `extern`. Now `size_t` / `ptrdiff_t` (these are the types of counts and
indices, which is what usize/ssize are used for, and both are pointer-sized on
every supported target), with `<stddef.h>` added to the generated preamble.

**Regenerated artefacts.** All 34 committed `lib/*.h` change: every one gains the
`<stddef.h>` line, 14 lose `struct usize`, and 5 gain the `extern` global lines
this item is about (`arena.h`, `allocator.h`, `error.h`, `keyword.h`, `node.h`).
They were verified **not stale first** — the committed headers were byte-identical
to what the pre-change compiler generates — so the whole diff is attributable to
this change.

**Verification.** `make test` **515 PASS / 0 FAIL** (510 before, +5). Emitted
*program* IR is untouched, as it must be for a header-only change: 181
normalized-identical, 0 differing; 184/185 fixture diagnostics identical (the one
difference is the W9-2 follow-up's own fix, unchanged here). `make bootstrap`
reconverged; `abi-test` / `layout-test` / `avr-test` green; resolution matrix
unchanged (43 cells).

The tests compile and **run** a C consumer rather than grepping the header —
`grep` cannot tell a correct `asm` label from a broken one. `rec_val.a` is read
through the by-value struct spelling (ruling 2 above would fail there, not at the
header), and the private global is asserted unreachable by a consumer that names
it **failing to compile**, not by its absence from the text.

**Not fixed here, and now measured rather than assumed.** A `defn` whose name is
hyphenated still emits `int32_t ch-get(void);`, so a header for such a library
still does not parse as a whole — that is item 4, whose fix is the `asm` label
above. `raw:T`/`ref:T` widen to `void*` (pre-existing and shared with function
parameters). `!T`/`?T` error types emit `struct _BANGui8`-shaped spellings, the
same family as the `usize` defect but with no obvious C mapping.

**Files.** `src/cheader.nuc` (`emit-cheader-defvar`, `cheader-defvar-type-ok`,
`cheader-by-value-c`, the dispatch arm, `type-name-to-c`'s usize/ssize cases, the
`<stddef.h>` preamble line), `tests/run-tests.sh`
(`run_w9_cheader_globals`, +5 PASS lines), all 34 `lib/*.h`, `docs/compiler.md`,
`docs/toplevel.md`, and the reconverged boot artefacts.

### Follow-up, same day: the committed headers had no gate at all *(2026-08-10)*

Regenerating all 34 `lib/*.h` above made the actual hazard visible: **nothing
checks that a committed generated header still matches the compiler.** Everything
else generated-and-committed in this repo is gated — `boot/*.ll` by `make
bootstrap`'s fixed-point diff, `docs/stdlib.md` by `stdlib-table-generated` — but
the 69 `lib/*.nuch` + `lib/*.h` were not. The build never reads the committed
copies (`make lib-headers` / `make lib-cheaders` overwrite them), so a change to
`src/nuch.nuc` or `src/cheader.nuc` invalidates all of them with **no failure
anywhere**; it surfaces only when a consumer trusts a declaration that no longer
describes the library. That is precisely how the `usize` defect above sat in 14
committed headers unnoticed.

Now gated by `scripts/check-headers.sh` — `make check-headers`, plus the
`headers-generated` unit inside `make test`.

**Byte-exact, unlike `stdlib-table-generated`.** That check is deliberately loose
because availability is host/libc-dependent by construction. Header emission is a
pure function of the source with no host probing, so the same looseness would buy
nothing and hide real drift. Confirmed before committing to exact: all 69
regenerate byte-identically.

**Provenance-driven, not a file list.** Each generated header names its own source
on its first line (`src/nuch.nuc:169`, `src/cheader.nuc:2252`), and the check
reads that. So it covers `lib/mapiterlib.nuch`, whose source is
`tests/fixtures/mapiterlib.nuc` and which no `make` target can reach
(`LIB_NUCHS` is `$(wildcard lib/*.nuc)`); a hand-written header such as
`src/llvm.nuch` is out of scope by construction rather than by an exclusion list
that would go stale; and a newly generated header is picked up with no edit to
the checker.

**Content drift is only one of four failures, and the check found one on its
first run.** `lib/mapiterlib.nuch` recorded an **absolute** source path
(`/home/zak/code/nucleus/tests/fixtures/…`) — the generator echoes the path it was
given, so this is an artefact that regenerates only on the machine that produced
it. Rejecting absolute provenance is not fastidiousness: without it the check
would *pass on the one machine that broke reproducibility and fail on every
other*, which is worse than no check. Fixed by regenerating from the repo root.
The other two: a `lib/*.nuc` with no committed header at all (drift of the header
*set*, which a content diff cannot see), and a header whose recorded source is
gone. All four verified to fire, and the tree restored by regeneration, not git.

**Files.** `scripts/check-headers.sh` (new), `Makefile` (`check-headers`),
`tests/run-tests.sh` (`run_headers_generated`, +1 PASS), `lib/mapiterlib.nuch`
(relative provenance), `docs/compiler.md`, `context/build.md`.

### W9 item 4 as fixed *(2026-08-10)* — two rewrites, chosen by who resolves the name

The defect is one sentence — `-` is ordinary in a Nucleus name and illegal in a C
identifier — and the fix is two rules, not one, because a name is rewritten for
**one of two different reasons**:

* a name the **linker resolves** (`defn`, `defvar`) must be both a C identifier
  *and* the symbol the object defines, which one token cannot be: sanitized
  spelling **plus** an `asm("real-symbol")` label. This is item 3's ruling,
  applied to the rest of the surface;
* a name the linker **never sees** (struct field, function parameter, `defunion`
  arm, enum tag, `#define` from a `defconst`, inline-`(union …)` member) only has
  to parse: plain `sanitize-for-c`.

Two functions carry those rules — `cheader-c-ident` and `cheader-asm-label` — and
`emit-cheader-defvar`'s inline `strcmp`-and-branch from item 3 was **replaced by a
call**, not left beside them.

**The recorded census was three sites short, and the census is how the item was
scoped.** Beyond the six sites its note lists, hyphens also reached `defconst`
`#define` names, `defenum`'s own tag name *and* its members, function **parameter**
names, and the inline-union member names emitted from inside `type-node-to-c`
(not from `emit-cheader-defstruct`, which is why enumerating the `defstruct` path
missed them). Found by sweeping all 181 generated headers for a stray hyphen
rather than by re-reading the list — the sweep is now the test's own assertion.

**One coupling the census could not have shown.** `cheader-array-extent` exports a
non-folding `(array T N)` length as the bare constant NAME, on the explicit
premise that `emit-cheader-defconst` exports the matching `#define`. Sanitizing
one without the other yields `int32_t xs[MY-LEN];` against `#define MY_LEN 4` —
so the two are sanitized together, and the test pins the pair by *indexing with*
`BUF_LEN`, not by grepping for it.

**Verified by compiling and RUNNING a C consumer.** `grep` cannot tell a correct
asm label from one naming a symbol that does not exist — which is exactly the
residue this item leaves (items 26 below). The consumer calls through a label,
reads a global through another, and touches a struct field, an array element
indexed by the `#define`, an inline-union member, a `defunion` arm field, its tag
constant and an enum member; `nm` is the independent witness that the C
identifier and the ELF symbol really are different strings (`T my-bump`, and no
`my_bump`).

**Measured, before and after: 13 → 27 of the 34 committed `lib/*.h` parse** under
`clang -fsyntax-only`. Not 34 — and the remaining seven fail for **four causes,
none of them a hyphen**, each now measured and filed as its own item rather than
folded in here:

| Header(s) | Cause | Filed |
|---|---|---|
| `char.h`, `error.h`, `string-split.h` | `struct Char` is an incomplete tag — the typedef is anonymous | 25 |
| `parse.h`, `string.h`, `strview.h` | an overloaded/operator `defn` is exported under its bare name, which no object defines | 26 |
| `hashset.h` | a template tyvar exported as a concrete type (`struct T elem`) | 27 |
| `hashset.h` | a C **keyword** as a function name (`void union(…)`) | 28 |

Item 26 is worth stating plainly because this item makes it *visible*: the header
now says `_Bool _(…) asm("=")`, and `nm lib/string.o` has no bare `=` — the real
symbol is `eq.String.String`. That declaration was equally false before (it read
`_Bool =(…)`, which merely failed earlier, at the parser). Every one of the four
fails **loudly** at the C consumer, so none is a silent mis-binding.

**Two tests pinned the defect and were updated, not deleted**:
`l8-cheader-emits-fnptr` and `l13-cheader-emits-fnptr` asserted
`plain-fn(int32_t x, int32_t y)` — the broken spelling — and now assert the whole
line including its label.

**Verification.** `make test` **520 PASS / 0 FAIL** (516 before: +4 new, and the
two above went from FAIL to PASS). Emitted *program* IR is untouched, as a
header-only change requires: 181 normalized-identical, 0 differing against the
pre-change compiler (`examples/comb-shapes.nuc` compiles on neither — the
pre-existing `as: lossy conversion` from W9-1). `make bootstrap` reconverged;
`abi-test` / `layout-test` / `avr-test` green. 21 of the 34 `lib/*.h` change —
and the `headers-generated` gate added the day before **caught them**, which is
the first time that check has done its job.

**Files.** `src/cheader.nuc` (`cheader-c-ident`, `cheader-asm-label`, and the
eight emission sites), `tests/run-tests.sh`
(`run_w9_cheader_identifiers`, two updated units), 21 `lib/*.h`,
`docs/compiler.md`, and the reconverged boot artefacts.

---

## B — Name resolution *(added 2026-08-08; B0, B1, B2a, B2b, B5, B3′, B6, B4 and B7 done — every name-keyed kind is on the canonicaliser)*

Full design, measurements and rulings: [name-resolution.md](name-resolution.md).
Staging is B0 (record the matrix) → B1 (file-scoped import environment) → B2
(the canonicaliser, cut over kind by kind: **B2a protocols**, **B2b globals** +
`unsafe` + deleting alias injection) → B3′ (re-key the type registries) → B4
(collision policy) → B5 (the shared binding interface) → B6 (`(dyn P)` identity
vs admission) → B7 (macros, the last bare-keyed kind). **All of B0–B7 are
done**; B4 and then B7 closed it out on 2026-08-09. B7 was added late, when
reviewing B4's leftovers showed that §11.6 — cited by the compiler as the reason
a macro could not be re-exported — is a *defect report with a plan*, not a
ruling, and that the reason it gave was circular.
**B5 landed 2026-08-09 out of order**, because §13.4 upgraded it from
"reconcile the two priority orders" to the interface of §13.3 — which makes it
the *frame* B3′ and B4 fill in rather than a cleanup after them. The A-vs-B
decision (§12) was taken at the B3′ boundary and is recorded in §13.4: **B's
path, with B5 as a shared interface (B+)**; the measured inputs to it are §12.6
(after one kind), §12.7 (after the largest one) and §13.1.

**B0 — the matrix, recorded.** `tests/resolution-matrix.sh` +
`tests/expected/resolution-matrix.baseline`, 43 cells. It is a *recorder*, not a
gate: each cell generates a library and a one-file consumer under a temp dir,
compiles and **links** the probe, and records `ok` / `err` plus the first
diagnostic. Later steps `--check` against the baseline and see exactly which
cells moved. Three genuine regression tests went into `tests/run-tests.sh` for
the cells that are already correct. Re-measuring by machine corrected one §2 row:
the protocol row splits, `extend`/boxing with a bare name is `err` rather than
"falls back", and a `(dyn …)` **annotation** validates nothing in any column —
a tenth defect.

**B1 — an import prefix is file-scoped.** `ImportBind {prefix, path}` in
`src/compiler-types.nuc` plus `g-file-imports`, a
`(Vector (ref ImportBind))` following the `NsPrefixEntry` small-table idiom.
`do-import` records one bind per import form (prefix non-null for
`import-prefixed` / `import` / `unsafe/import-private`, null for the flattening
`import-use` / `import-only`) and saves/clears/restores the table around every
imported file exactly as it already does `g-current-ns` / `g-ns-seen` — that
save/restore *is* the file scoping. `scope-lookup`'s global-scope branch
consults the new `prefix-out-of-scope` gate.

Three implementation facts worth keeping:

* **The bind is recorded before every early return**, not inside the load block.
  `do-import` has three returns that precede the load — the `(file, prefix)`
  dedup, the already-loaded flatten dedup, and W1d's cycle skip — and each one
  leaves the import *declared in this file* while doing no further work. The
  cycle case is the one with teeth: without the bind, B1's diagnostic would
  answer a question `cycle-prefix-message` already answers correctly, and one
  failure would have two contradictory explanations.
* **The gate is deliberately narrow.** It fires only when the qualifier is a
  prefix *another* file in the unit bound. A namespace qualifier still resolves
  (that is defect #3, B2's), and a qualifier naming nothing still falls through
  to the existing unresolved-name tiers. That is why exactly one matrix cell
  moved — `xfile-prefix-leak zx/` `ok` → `err` — and nothing else did.
* **The diagnostic is part of the deliverable.** An unbound qualifier must not
  degrade into W1c's "not defined anywhere in this compilation unit": the name
  *is* defined and the import graph *does* reach it, so that message would be a
  lie of exactly the kind W1c exists to remove. `unbound-prefix-message` names
  the prefix, the file that does bind it, and the prefixes in scope here.

**B2a — one canonicaliser, protocols cut over.** The chunk that fixes the
originally reported defect. `resolve-spelling(spelling) → ref:NameRef`
(`src/nucleusc.nuc`, after B1's import-environment section; `NameRef` and the
`NR-BARE`/`NR-QUALIFIED`/`NR-UNBOUND` tags in `src/compiler-types.nuc`) splits at
the first interior slash and resolves the qualifier through `g-file-imports` and
nothing else. A bound prefix names its library's namespace; an `import-use`d
namespace may also be named by its own name (§8.3 row 1's second clause); the
file's own namespace and `user` are always legal; **anything else resolves to
nothing, even when the raw spelling is itself a registry key** — which is the
fix. The prefix→namespace half B1 left open is `g-file-ns`, written by `emit-ns`.

Protocols route through it: `protocol-lookup` is now the reference resolver,
`protocol-lookup-ns` (the old body, renamed) is the key lookup for stored
canonical names, and `protocol-resolve-any` serves the `(dyn P)` consumers that
sit downstream of the box-construction gate. Registration is untouched — it still
uses `protocol-lookup-exact` with an already-final key.

Four things worth keeping (full versions in [name-resolution.md](name-resolution.md) §9.2):

* **The reference/key split is the real per-kind work.** A canonical name read
  back from a `.nuch`, a `Constraint`, a super-protocol edge or a `(dyn P)` box is
  usually read in a *different file* from the one that wrote it, and B2a's rule is
  that a file cannot name a namespace it did not import. Routing such a key
  through the reference resolver is a false rejection; routing a source spelling
  through the key lookup is the unclosed hole. Thirteen call sites, classified by
  hand.
* **Resolve once, at the reference, then carry the record.** `emit-extend` used
  to canonicalize and then look the canonical name up again — under B2a that asks
  the scope question twice and gets two answers. It now keeps `proto-rec` and
  passes `(p name)` down.
* **`(dyn P)` splits identity from admission.** `dyn-type` mints the box's
  `StructDef` from a signature during `prescan-defn-signatures`, where the import
  environment is empty by construction, and again at emission where it is not — so
  its key must be phase-stable and stays on the environment-free
  `protocol-canon-name-ns`. The scope question is asked once, at box construction,
  by `dyn-require-protocol`. A memo key must be phase-stable; a permission check
  belongs where the permission is known.
* **A fixture that pins a defect becomes unreachable when it is fixed.** The
  matrix's `protocol-dyn-box` row pinned its `extend` at `zn/Zp`, "the one
  spelling that works" — which B2a makes an error. Re-pointing it to `zx/Zp` is
  part of the change; without it the row would have measured the extend's failure
  in all four cells.

**B2b — globals, `unsafe`, and the end of alias injection.** The point of the
whole series: the prefix stops being a post-hoc copy of one registry and becomes
a resolution step. Full as-built in [name-resolution.md](name-resolution.md) §9.3.

* **The split.** `scope-lookup` (`src/scope.nuc`) is now the *reference*
  resolver — local frames match the raw name, and the global frame is handed to
  `globals-lookup-ref` (`src/nucleusc.nuc`), which resolves a qualified spelling
  through `resolve-spelling` and an unqualified one through the current
  namespace, then the flattened set, then `user`. `scope-lookup-key` is the
  pre-B1 body verbatim, for keys. Of 59 call sites: **8 key** (every one paired
  with a `scope-define` — the `.nuch` replay, the C-header registrar,
  `emit-deferror`/`emit-extern` dedup, `cheader-yield-to-explicit-declare`, the
  REPL's three), **49 reference**, **2 deleted**.
* **`inject-import-aliases`, `import-alias-one` and `alias-cinclude-collected`
  are gone** (64 lines), with the C-header collect mode that existed only to
  feed them. §1.1's `is-local`/`ir-name` filter closes **by deletion** — there is
  no slice to filter — so a prefixed `defvar`, `defconst` and enum member all
  resolve. The one filter that was not accidental, `sym-private`, became a
  resolution rule: `ImportBind` carries `private`, `scope-frame-find-public` is
  the filtered scan, and a private prefixed import additionally probes the
  imported file's `#pN/` key space.
* **One gate, not two.** B1's `prefix-out-of-scope` is deleted and
  `unbound-prefix-message` folded into `qualifier-scope-note` as its first tier,
  which removes the disagreement §9.2 measured (protocols resolved through the
  environment while globals still went through B1's narrow prefix gate).
* **`unsafe` is a built-in namespace**, bound as an implicit prefix in every
  file. The seven `unsafe/*` strings left `g-special-form-set`; membership is now
  "resolve the qualifier, then consult the roster". Six of the seven bare
  retirement refusals were deleted from `emit-list` **and** `node-type-call`
  (lockstep) and reproduce their exact messages from a did-you-mean tier.
* **W1d lost a tier.** A `prefix/name` over a cycle member used to be diagnosed
  because injection was suppressed; a prefix now names the *file*, whose
  signatures and namespace the whole-graph prescan already recorded, so it
  resolves. `cycle-prefix-message` / `g-cycle-prefixes` are gone and the probe
  became an acceptance test.
* **A documented gap closed on the way.** `lib/nsdescribe.nuc`'s header recorded
  that a file with an explicit `(ns …)` could not reach `default-allocator` and
  therefore could not construct a `(dyn P)` box. The bare path's `user` fallback
  closes it; measured with a namespaced library that boxes and dispatches.

**B5 — the shared binding interface.** §13.4's recommendation, built. One table
(`build-binding-kinds`, `src/nucleusc.nuc`) with **thirteen rows** — §1's eleven
name-keyed registries plus the two correctly-global name sets — each carrying a
`noun`, the `NK-*` it reports, and three columns that state which shared
concerns it participates in (`collides`, `name-keyed`, `reregisterable`). **The
row order IS the resolution order**, walked by `name-existing-kind`,
`emit-dispatch` and `node-type-call`. Full as-built in
[name-resolution.md](name-resolution.md) §14; five things worth keeping here:

* **Encoding: a kind tag + `case`, deliberately not fn-pointer struct fields.**
  Three open W9 defects live in the fn-pointer path (`(= h null)` does not
  compile for a `TY-FN` value; `type-size` has no `TY-FN` case so a fn-pointer
  slot emits `align 1`; `coerce-int-val` has no `raw`→`TY-FN` case), so a
  vtable-shaped table would have had to fix all three — moving the IR of every
  fn-pointer program — to buy nothing a closed thirteen-row dispatch needs.
* **Unifying the two orders required changing the QUESTION, not picking a
  winner.** Taking `emit-dispatch`'s order directly *weakened* the guard:
  every definer registers its own name in a prescan before its own guard runs,
  so `(defn Shape …)` over an existing `defprotocol Shape` finds the `Generic`
  it just registered, reports `NK-FUNCTION`, matches, and never looks further
  (measured: it compiled clean before B5). `guard-name-kind` now asks for the
  first binding whose kind is **not** the one being defined, which is
  order-*independent* — the table order only chooses which conflicting kind to
  name. Consequence, and the only two test expectations that moved: a cross-kind
  clash is reported at whichever definer is **emitted first**, so
  `w8-fnptr-global-name-collision` and `g0-value-fn-collision-order2` were
  re-pointed (still rejections; different blame line and noun, reasoning inline).
* **`NK-PROTOCOL` needed a prescan reorder as well as a row.**
  `prescan-struct-names` registers a name-only `StructDef` without guarding, so
  it won every `defprotocol`/`defstruct` race — which is exactly why §2.5
  reported the clash at the *protocol's* line saying "a type".
  `prescan-protocols` now runs first (its method sigs are stored verbatim and
  parsed lazily, so it needs no struct name), and both source orders report at
  the `defstruct`'s own line with "already names a protocol".
* **The privacy hypothesis held, and verifying it turned up a third thing.**
  `StructDef`/`UnionDef`/`StructTemplate`/`UnionTemplate`/`MacroDef`/`Protocol`
  had no carrier at all, and the dispatch loop's own comment ("the private flag
  is honored by prescan-protocols") was **false**. The rule is one function
  (`binding-visible`, over `priv` + `src-ns`) called from the six *reference*
  lookups — not from `binding-probe` alone, which would have left
  `parse-type-name`, i.e. every `:T` annotation, unguarded. The third finding:
  provenance must be captured at **emission**, never in `prescan-struct-names`,
  because that prescan is reached from `prescan-imported-types`, which does not
  apply an imported file's leading `(ns …)` — capturing there recorded the
  importer's namespace, and the resulting private-but-wrongly-namespaced entry
  hid itself from `emit-defstruct`'s own `lookup-struct`, which then registered a
  **second** `StructDef` under the same name. Whole mechanism short-circuits on
  `g-priv-bindings`, 0 for every program in the tree.
* **The did-you-mean now renders through `src-ns`.** A candidate is offered in
  the spelling *this file* can write (bare / `prefix/bare` / not at all), never
  as the raw registry key — which is what produced `unknown: zfun (did you mean
  'zfun'?)`, since a generic is keyed bare. Two stated restrictions: the
  qualified form is offered only for `g-globals` and `g-protocols`, the two
  registries where a qualified reference resolves today (B3′/B4 widen it), and a
  private-and-invisible candidate is dropped so the suggester cannot leak a name
  the resolver just hid.

**B3′ — type identity is namespaced (R1, defects #4 and #7).** All six type rows
of B5's table (`g-structs`, `g-uniondefs`, the two template registries,
`g-enumdefs`, `g-fnty`) re-keyed on the canonicaliser. **The planned struct/union-
first split was abandoned after the audit and is the chunk's first finding:**
`parse-type-name` is the single entry for every `:T` spelling in the language and
its cascade consults all six registries in one function, so cutting one over alone
would have left `(ref zzz/Fox)` refused while `(ref zzz/Shape)` still resolved —
defect #4 half-closed with no way to say which half. Five *reference* resolvers
(`struct-lookup-ref` and siblings) share one candidate-key walk; the old bodies
are the *key* lookups; `BK-FNTY` stays bare on purpose (a `__fnty_N` has no source
spelling). `parse-type-name`'s `strip-ns-qualifier` is deleted, the conformance
registry's type half goes through `type-canon-name`, `register-struct` derives
`ir-name`/`ir-prefix` from **the key's own namespace** (never `g-current-ns` — a
stamp or an import runs under someone else's), so `(ns dp) (defstruct Fox …)`
emits `%dp__Fox` and `--emit-cheader` composes the same prefix. `export` is
generalised to the type and protocol rows, but **not** by re-registering: a type's
payload *is* its identity, so a second `StructDef` would make the facade's name a
second type; it is a re-export **alias** table mapping the facade's name to the
same payload (§11.6 corrected in place).

The new mechanism is **`g-type-key-ok`**, a scoped *synthesis-region* permission
on W8 G-3's `g-defvar-soft` shape: `type-spelling` renders a `Type` back to its
canonical name, and the compiler re-parses that string in regions (a template
stamp, a monomorphized body, a `Self` substitution, a stored conformance arg, a
`.nuch` replay) whose file is routinely not the file that produced it. Those are
not call sites to classify but dynamic extents, so the five resolvers take an
exact-key fallback **only while armed**, and only after the reference walk misses.
Zero for every program in the tree that declares no namespace.

**The honest weakness, recorded because it cost three defects.** A permission with
a dynamic extent has no compile-time evidence that its extent is complete, and a
*missing* arm is a false rejection of a legal program with a diagnostic that reads
like a user error. Three arms were missing and all three were found by running a
namespaced type through ordinary idioms, not by reading:
`tmpl-conformance-check-one` (the per-instance check of a template-level
`(extend (Vector T) (Seq T))`, run at stamp time — the widest, since every
collection in `lib/` carries one, so **no namespaced type could be a collection
element**; its sibling branch *was* armed), `generic-instantiate` (the stamped
signature parse — `drain-mono-worklist` armed the stamped *body*), and
`resolve-param-type-bound` (the shared substitute-and-reparse helper, so a
return-only-tyvar generic like `vector-new` resolves against a want). A fourth fix
was not an arm but §9.2's rule reasserting itself: `emit-extend` canonicalized its
subject and then re-parsed the *canonical* name "for a clean diagnostic", which
asks the scope question twice — `(extend gx/Pt P)` canonicalised to `b3ang/Pt` and
was then refused as an unknown type. It validates the authored spelling now.

### Test/bootstrap status after B3′

* `make` clean from `make clean`; `make bootstrap` at its fixed point
  (`stage1.ll == stage2.ll`) with **no reconverge**, stage 2 compiles and runs
  `hello.nuc`; `make abi-test` / `make layout-test` green.
* `NUCLEUS_TEST_JOBS=1 make test` → **463 PASS, 0 FAIL**. Ten of the new ones came
  with the re-keying itself (`b3-two-vectors` — two namespaces each defining
  `Vector`, linked and run so a collapsed identity would read the wrong offsets;
  `b3-two-vectors-distinct`; `b3-two-vectors-field`; `b3-type-bogus-qualifier`;
  `b3-type-ns-not-in-scope`; `b3-type-typo`, which exists to *execute* the cold
  did-you-mean tier; `b3-ns-type-export-surfaces` and
  `b3-ns-type-nuch-link-and-run`; the re-pointed `b5-export-type-facade`). The
  eleventh, **`b3a-ns-type-in-collection`**, pins the three missing arms in one
  linked-and-run program (a namespaced struct as a `Vector` element, reached
  through generic dispatch, with a cross-namespace `extend` over it) — verified to
  *fail* on a compiler built from `HEAD` and to return 20 on this one.
* **IR inertness**, against a compiler built from a clean `HEAD` worktree:
  **182 of 182** files in `examples/`+`lib/` accounted for — 178 emit
  byte-identical IR and 4 are refused by *both* compilers with byte-identical
  stderr and byte-identical partial output. Zero differ, zero regress, zero newly
  compile. (182/182 rather than B5's 181/182 because `HEAD` now contains B2a's
  rewritten `examples/w9-dyn-ns.nuc`, which removes that standing artefact.)
* **Diagnostic sweep**, the half the IR sweep cannot see: all **180**
  `tests/fixtures/*.nuc` produce byte-identical stderr, stdout and exit status
  under both compilers, so no pre-existing diagnostic's text or line moved.
* `tests/resolution-matrix.sh --check` → **unchanged (43 cells)**. `type-annot
  nope/` — the last wrongly-`ok` cell — moved `ok` → `err` with the re-keying
  itself and is already recorded in the committed baseline.

**Open, and measured rather than suspected** (details and both candidate fixes in
§9.4's "What B3′b/B4 inherits"). *(Both closed in B6, 2026-08-09 — see below;
kept here as the snapshot at B3′'s close, with the one measurement B6 corrected
marked inline.)*

* **A `(dyn P)` box's identity is keyed on a spelling-derived name, so a *prefix*
  spelling splits it.** Live in the tree: `examples/w9-dyn-ns.nuc` imports one
  library under two prefixes and emits **two** `{data,vtable}` `StructDef`s for
  one protocol. **(Wrong — B6 measured it: that file imports two *different*
  libraries in namespaces `dp` and `dp2`, so two box types are correct there;
  what was wrong is that they were named after the consumer's prefixes. The
  split needs two files to witness.)** The consequence is a legal program that
  fails — `nucleusc: failed to parse generated IR: '%t25' defined with type
  '%__dyn.dp_Describe' but expected '%__dyn.dpx_Describe'`, with no source
  location. `dyn-type` keys on the environment-free `protocol-canon-name-ns`
  deliberately (§9.2), and that canonicaliser cannot map a prefix to a namespace.
  Fixing it means moving *admission* to the annotation site, where the spelling
  is, which is §9.2's deferred-validation fix and also closes the tenth defect.
* **A `(dyn P)` value is accepted where `(dyn Q)` is required** for genuinely
  different protocols, and is caught only by LLVM's parser. Pre-existing
  (Stage 13 TE-3's box-to-box coercion returns its input untouched),
  namespace-independent, and the reason the split above is not louder. **(B6:
  "only by LLVM's parser" holds for the binding position; in an ARGUMENT position
  the SysV ABI splits the fat pointer into two i64s at the call, so nothing
  catches it and the program runs against the wrong vtable.)**

### B7 — macros, the last bare-keyed kind *(2026-08-09)*

Closes the remainder of defect #1 and corrects §11.6's standing. Full account in
[name-resolution.md](name-resolution.md) §9.7.

* **`g-macros` is keyed by `qualify-name` and `find-macro` is a reference
  resolver** over the same candidate-key walk the six type registries use, with
  `find-macro-exact` as the key lookup. The reference/key audit conventions.md
  demands for every cut-over was unusually cheap here: `find-macro` is the
  registry's only reader, and of its eight call sites exactly **one** holds a key
  — B4's redefinition guard, which had to move to the exact lookup or the
  flattened-namespace walk would report an unrelated namespace's macro as a
  redefinition of this one.
* **The plan's `jit-name` step was wrong, and usefully so.** §9.7 predicted the
  B3′ step-2 `ns-ir-prefix`/`ir-name-token` composition. Measured, a `jit-name`
  is not an identity — it is a private JIT symbol already unique by its `_%d`
  counter — so deriving it from the **bare** name is correct, keeps `/` out of
  `sanitize-for-ir`'s input, and is byte-identical. Before copying B3′ step 2 to
  another registry, ask whether the emitted symbol is an identity or a label.
* **`BK-MACRO` is `reregisterable` 1**, so a facade re-exports a macro through
  the alias table B3′ built, and it expands through the facade's prefix.
* **The refusal message was rewritten, not narrowed.** It claimed the kind "is
  identified by a globally-unique bare name" and cited §11.6 for it. §11.6 says
  no such thing, and for macros the claim was the gap justifying itself. What
  the surviving 0-rows actually share is that they are *not keyed by namespace*:
  an overloaded name because R2 merges it across namespaces on purpose, a special
  form / built-in type name / `__fnty_N` because no namespace owns them.
* **Two namespaces may now each declare a macro of one name** — not a stated
  goal, but the direct consequence, and the case B4's redefinition rule would
  otherwise have turned into a hard error.

### Test/bootstrap status after B7

* `make test` → **492 PASS, 0 FAIL** (485 after B4, so 7 new: six resolution
  rules — prefixed, flattened, namespace-refused, did-you-mean, three macro
  sources at once from inside a namespace, two namespaces one name — plus the
  inverted export pin).
* One pin inverted: `b5-export-macro-refused` → `b7-export-macro-facade`, which
  now **runs** the re-exported macro rather than asserting a refusal. A
  compile-only check would have passed on a macro that resolved but expanded to
  nothing. `b7-export-overload-refused` replaces it as the surviving refusal, and
  it pins the *reason* as well as the verdict.
* `make bootstrap` re-converges; `abi-test`, `layout-test`, `avr-test`,
  `riscv-test`, `riscv-abi-test` all pass; the matrix is unchanged.
* **Byte-identical across the tree** — HEAD-worktree compiler vs the B7 compiler,
  `diff`-identical IR for all 178 compilable files in `examples/` + `lib/`. This
  is inertness *by construction*: no macro anywhere in `src/`, `lib/` or
  `examples/` is declared inside a namespaced file, so every key is
  `qualify-name`'s identity under `user`.
* Known gap, recorded rather than back-filled: `tests/resolution-matrix.sh` has
  no macro row, so the matrix cannot show B7's cells moving. The six new tests
  cover the same ground directly.

### B4 — a qualified spelling for generics, and R4's eager redefinition rule *(2026-08-09)*

Closes defect #5 (generics unqualifiable), the generic half of #1, R2's per-kind
`collides` policy and R4. Full account in [name-resolution.md](name-resolution.md) §9.6.

* **The qualified spelling is a FILTER, not a key.** `generic-lookup-ref`
  (`src/generics.nuc`) resolves `p/name` through `resolve-spelling` and then
  restricts the bare generic's method set to the methods whose `Method.src-ns` is
  the namespace `p` denotes. R2's ruling stands: `g-generics` stays keyed bare
  with every namespace's methods merged, because that is what an open multimethod
  needs. `BK-GENERIC`'s probe arm is the only consumer, so `emit-dispatch`,
  `node-type-call` and `guard-name-kind` inherit it — §14.7's prediction, held.
* **`Method.src-ns` was not provenance, and that was the work.** It had three
  writers and one reader (a W5e diagnostic), so two of them could be wrong
  indefinitely. `register-generic-template` never set it at all — a bounded-generic
  template filtered to zero methods and `p/tmpl` reported "not defined anywhere in
  this compilation unit". And a *stamp* recorded the **call site's** namespace,
  though the line directly below already says the mangling must use the
  template's; uncorrected, the second `p/tmpl` call from another namespace misses
  `generic-find-method-exact`'s memo and the instance is emitted twice under one
  symbol. Both fixed; the generalization is in `context/conventions.md`.
* **`collides`, measured per row.** `BK-ENUM` was a genuine hole — an enum
  registers its *members* and never its own name, so `(defenum Colour …)` plus
  `(defn Colour …)` / `(defvar Colour …)` / `(defmacro Colour …)` all compiled.
  `BK-UNION` was redundant (`BK-STRUCT` answers first for every union) and is 1
  anyway, because the row is where participation is declared. `BK-FNTY` stays 0.
* **R4 is ten definer sites and four different tells** — `emitted` for
  `defstruct`; a defining `(file, line)` for the registrars that are legitimately
  re-entered for one form (`defunion`, `defprotocol`, both templates, `defmacro`);
  `Sym.defvar-state` for `defvar`; `(file, line)` plus a blame-the-later-one rule
  for `defconst` and enum members, whose prescan Sym is indistinguishable from the
  emitter's. The message is one function; the fact is per definer, which is why
  §14.7's "extend the table" could not be the shape. `Protocol`,
  `StructTemplate`, `UnionTemplate` and `EnumDef` gained `src-file`/`src-line`,
  `UnionDef` gained `src-file`, and `MacroDef`'s two existed and had never been
  written — that is what lets the diagnostic name **both** definitions.
* **The REPL is exempt, via one predicate.** `same-definition-site` answers "same
  definition" under `g-interactive`, so each definer falls back to *its own*
  pre-B4 behaviour (four used to `return`, four to fall through). Verified by
  diffing a REPL transcript against the pre-B4 compiler: byte-identical.
* **Three tree casualties, all §11.1's class, all fixed rather than worked
  around.** §11.1 predicted one from a scan of `src/` + `lib/`; `examples/` was
  not in that scan. `examples/list.nuc` and `examples/quasiquote.nuc` each carried
  another copy of the `Node` redefinition §11.7 removed from `lib/list.nuc`, and
  `examples/defmacro.nuc` defined `when`/`unless` over the prelude's — where
  `find-macro`'s first-match scan meant **neither definition in that example had
  ever been expanded**. Renamed to `when1`/`unless1`; output unchanged.

### Test/bootstrap status after B4

* `make test` → **485 PASS, 0 FAIL**, counted with `NUCLEUS_TEST_JOBS=1` (467
  before B4, so 18 new): four for the qualified-generic path — including a bounded
  template stamped twice through a prefix, which is the only shape that reaches
  both provenance holes — two for the `BK-ENUM` hole, ten rows of redefinition
  table, plus a cross-file case and a diamond-import case that must stay legal.
* `make bootstrap` → `stage1.ll == stage2.ll`, and the stage-2 compiler builds and
  runs `hello.nuc`. `abi-test`, `layout-test`, `avr-test`, `riscv-test` and
  `riscv-abi-test` all pass.
* `tests/resolution-matrix.sh --check` → exactly one cell moved,
  `overloaded-fn zx/` err → ok, which is defect #5. Re-recorded.
* **Byte-for-byte inert on emitted IR.** A compiler built from a clean `HEAD`
  worktree and the B4 compiler emit `diff`-identical IR for **all 178** compilable
  files in `examples/` + `lib/`. The four that do not compile fail *identically*
  under both and are the known standalone-compilation artifacts (`lib/reader.nuc`,
  `lib/arena.nuc`, `lib/node.nuc`, `examples/comb-shapes.nuc`). Note this also
  proves the three source fixes above are inert: both compilers were run over the
  *edited* sources.
* One existing pin moved text and kept its verdict:
  `g0-duplicate-global-rejected` asserted LLVM's `redefinition of global
  '@g0-dupg'`, emitted with no source location; the compiler now catches it at
  `emit-defvar` and names both files.

### B6 — identity vs admission for `(dyn P)` *(2026-08-09)*

Closes defects #10 (`protocol-dyn-annot`) and #11 (box identity), i.e. both of
the items above. Full account in [name-resolution.md](name-resolution.md) §9.5.

* **Identity** is now `dyn-proto-key` (`src/nucleusc.nuc`, replacing
  `protocol-canon-name-ns`, which is deleted): the canonical protocol name
  derived from `resolve-spelling` and **no registry**. Consulting no registry is
  the load-bearing property, not an economy — §9.4 said `prescan-file-imports`
  alone makes the canonical key phase-stable, and it does not: the root file's
  `prescan-defn-signatures` runs before `prescan-imported-signatures`, so a
  registry probe answers *not found* at prescan and *found* at emission, which is
  worse than the bug (the two keys then disagree inside one program). The one
  probe that remains is `-exact`, on the current namespace's key only, which is
  phase-stable because a file's own `prescan-protocols` precedes its own
  signature prescan — and it reproduces the old answer for every bare spelling,
  which is why the tree's IR barely moves.
* **Admission** moved to the annotation site as a deferred worklist: `DynAnnot`
  carries `{spelling, path, line, ns, imports}`, `dyn-annot-record` is called
  from `dyn-type`, `drain-dyn-annots` restores the three globals per job and asks
  `dyn-require-protocol` **on the spelling**, as the file that wrote it. Two
  documented skips: a `g-type-key-ok` synthesis region (no file to ask), and a
  REPL form typed at the prompt (`g-interactive` **and** `g-toplevel-depth` 0 —
  the depth test matters, since a REPL `import-use` must defer exactly like
  batch). Completeness is **asserted**: `main` fails as an internal error if the
  cursor has not reached the count.
* The drain runs at `emit-toplevel-forms` depth 1 **after** `drain-mono-worklist`,
  not after the prescans as §9.4 proposed, because a `.nuc` imported by **string
  path** is walked by no prescan at all — its protocols do not exist until
  emission. Same reason §9.2's alternative fix (b), "move the imported signature
  prescan ahead of the root's own", is recorded as the wrong recommendation: no
  reordering of prescans reaches a file no prescan visits.
* Box construction stops asking the scope question (`dyn-resolve-protocol`, a key
  lookup) — it *must*, because a box now stores a canonical name and a canonical
  name is not spellable through a prefix. That is the failure mode §9.4 predicted
  for keying identity on the canonical name without moving admission, and it was
  already reachable at `HEAD`: a library writing `(dyn P)` bare inside its own
  namespace already stored a canonical name, so passing a consumer's value into
  its `(dyn P)` parameter died `'b6dp/Describe' is not a declared protocol`.
* **`box-require-same-kind`** is the `type-eq` the erased-slot coercion never
  had. There are **two** coercion sites, not one: `maybe-box-into-slot`
  (`let`/`with` init, `return`) and a separate pair of blocks in
  `emit-call-with-args` for arguments — `coerce-int-val`'s lesson recurring.
  Both call it.

#### Test/bootstrap status after B6

* `make` clean from `make clean`; `make bootstrap` at its fixed point
  (`stage1.ll == stage2.ll`) with **no reconverge** (the compiler's own source
  spells no `(dyn P)`, so every new mechanism is inert for it); stage 2 compiles
  and runs `hello.nuc`; `make abi-test` / `make layout-test` green.
* `make test` (parallel default) → **467 PASS, 0 FAIL** (463 + 4). The headline
  is `b6-dyn-cross-ns`, which **links and runs** a library that both returns and
  accepts `(dyn Describe)` written bare inside `(ns b6dp)`, consumed as
  `(dyn dpx/Describe)`, and asserts 27 — a compile-only check would pass on two
  box types that never meet. The other three are `b6-dyn-annot-unknown` (the
  tenth defect) and `b6-dyn-box-mismatch-arg` / `-let` (the two coercion sites).
  All four verified to *fail* on a `HEAD`-built compiler; two of them —
  `b6-dyn-annot-unknown` and `b6-dyn-box-mismatch-arg` — compiled, linked **and
  ran** there, which is why they exist.
* **IR inertness**, against a compiler built from the clean `HEAD` tree:
  **181 of 182** files in `examples/`+`lib/` byte-identical on IR, stderr and
  exit code. The 182nd is `examples/w9-dyn-ns.nuc`, whose entire 70-line diff is
  one rename — `%__dyn.dpx_Describe` → `%__dyn.dp_Describe`,
  `%__dyn.dpx2_Describe` → `%__dyn.dp2_Describe`, and the three `@__vt.*` symbols
  that embed those names. That is the fix: a box is named after the protocol it
  erases, not after the prefix that reached it.
* **Diagnostic sweep**: all **180** pre-existing fixtures byte-identical on
  stderr and exit code under both compilers. `b2a-dyn-ns-not-in-scope` is the one
  whose *reason* moved (same rejection, same line, now from the annotation drain
  rather than box construction) and its header was re-pointed inline.
* `tests/resolution-matrix.sh --check` → exactly the **three** predicted cells
  moved: `protocol-dyn-annot` `bare`/`nope/`/`zn/` `ok` → `err`. `zx/` stays
  `ok` and must — it is the one spelling the consumer may legally write, so the
  brief's "all four must move" is corrected to three. The row now matches
  `protocol-dyn-box` cell for cell, which is the real acceptance criterion.
  Re-recorded.

**Open after B6** (§9.5's inherit list): the `import-use`-flattened *bare*
spelling of a namespaced protocol still keys bare and still splits — unlike the
prefix case it is not resolvable from the environment, so closing it needs the
protocol registry to be phase-complete (registering every reachable file's
protocols in pass 1 is the candidate, with `guard-name-kind` ordering as the
risk); a `.nuc` imported by **string path** is walked by no prescan, which is
wider than `(dyn P)`; two files in one namespace can still split if the second is
prescanned first; and `set!`/`.set!` into a box slot reaches neither coercion
site, so it neither boxes nor type-checks.

### Test/bootstrap status after B5

* `make` clean; `make bootstrap` at its fixed point (`stage1.ll == stage2.ll`),
  stage 2 compiles and runs `hello.nuc`; `make abi-test` / `make layout-test`
  green.
* `NUCLEUS_TEST_JOBS=1 make test` → **453 PASS, 0 FAIL** (441 + 12). The twelve:
  three protocol-kind clashes (`b5-protocol-vs-struct`, `-order2`, `-vs-defn` —
  the last did not error at all before B5), four private-definer rejections plus
  two positive controls (a same-namespace file still sees all four, and a `user`
  consumer still reaches the library's public names — run, not just compiled,
  asserting 15), two did-you-mean checks (not an echo, and the suggestion
  actually compiles and runs), and the `export`-a-type refusal.
* **IR inertness**, against a compiler built from a clean `HEAD` worktree:
  **181 of 182** files in `examples/`+`lib/` identical — 177 emit byte-identical
  IR, 4 are refused by *both* compilers with byte-identical stderr and partial
  output (`examples/comb-shapes.nuc`, `lib/arena.nuc`, `lib/node.nuc`,
  `lib/reader.nuc`, all pre-existing). The 182nd is `examples/w9-dyn-ns.nuc`,
  which `HEAD` rejects — B2a's artefact, unchanged.
* `tests/resolution-matrix.sh --check` → **no cell changed status**. Two changed
  message, both defect #9's fix: `plain-fn bare` `(did you mean 'zfun'?)` →
  `'zx/zfun'`, and `defenum-member bare` gaining a `'zx/ZE-B'` suggestion it
  could not previously produce (the candidate key `zn/ZE-B` was compared whole
  and so was never near `ZE-B`). `defvar zg` / `defconst ZK` did not move — at
  two characters they are under `name-suggest-limit`'s floor. Re-recorded.
* Compile-time cost of the table walk, measured rather than assumed: committed
  boot 738 ms vs B5 compiler 723 ms emitting IR for the *same*
  `src/nucleusc.nuc`, best of three.

### Test/bootstrap status after B0/B1/B2a/B2b

* `make` clean; `make bootstrap` at its fixed point (`stage1.ll == stage2.ll`),
  stage 2 compiles and runs `hello.nuc`.
* `NUCLEUS_TEST_JOBS=1 make test` → **441 PASS, 0 FAIL** (438 after B2a, 434
  after B1, 432 before it). B2b's three are `b2b-prefixed-values` (a prefixed
  `defvar` + `defconst` + both enum members, run not just compiled),
  `b2b-prefixed-values-ns-refused` (the defining namespace is out of scope) and
  `b2b-unsafe-reserved` (the qualified `unsafe/` spellings stay reserved after
  leaving the string set). Four existing probes were re-pointed rather than
  re-baselined, each with its reasoning in the harness: `w1-ns-order1/2` and
  `g0-ns-qualified-value`/`-internal-forward` named a namespace they had not
  imported (R3 forbids it — the assertion they measure, prescan order
  independence, is unchanged), `w1d-cycle-prefix-diagnosed` became
  `w1d-cycle-prefix-resolves`, and `b1-prefix-not-visible-cross-file` follows
  the folded diagnostic head.
* B2b re-measured the IR sweep: **181/182** against a clean `HEAD` worktree (the
  182nd is `examples/w9-dyn-ns.nuc`, which `HEAD` rejects — B2a's artefact), and
  **182/182** against B2a's own post-fix IR, which isolates B2b as byte-for-byte
  inert.
* Older counts, for the record. B1's two are `b1-prefix-in-declaring-file` (the fix *scopes* the
  prefix rather than deleting it) and `b1-prefix-not-visible-cross-file` (the
  diagnostic, and that it does not degrade). B2a's four are
  `b2a-extend-ns-not-in-scope`, `b2a-dyn-ns-not-in-scope`,
  `b2a-scope-diagnostic` and `b2a-import-use-binds-namespace` (the last runs and
  checks a value, because what it asserts is that a bare and a namespace-qualified
  spelling land on **one** protocol identity).
* `tests/resolution-matrix.sh --check` → exactly the four predicted cells moved
  (`protocol-extend` and `protocol-dyn-box`, `zx/` err→ok and `zn/` ok→err), and
  nothing else; re-recorded.
* **Byte-for-byte inert on emitted IR**, measured rather than assumed: a compiler
  built from a clean `HEAD` worktree and the working-tree compiler emit
  `diff`-identical IR for all 182 files in `examples/` + `lib/`. The sole
  difference is the exit code on `examples/w9-dyn-ns.nuc`, which the pre-fix
  compiler now rejects because the file was rewritten to the spellings only the
  fix accepts.
* The four `import-prefixed` consumers in the tree — `examples/export-test.nuc`,
  `examples/w9-dyn-ns.nuc`, `examples/import-prefix.nuc`,
  `examples/ns-mangle.nuc` — all still build and run against their expected
  output.
