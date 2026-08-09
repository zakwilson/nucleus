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
arrived at.

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

## W9 — Reconciled at stage close: twenty-four defects found, six now fixed, eighteen open *(added 2026-08-01; extended through G-5's close 2026-08-02; items 21–24 added 2026-08-03; item 16 fixed in B4 2026-08-09; reported except where marked FIXED)*

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
Total **twenty-four**, of which **five** are fixed (items 11, 12, 14, 17, 21)
and **nineteen** open. All are pre-existing and independent of W1–W7; all were
hit while measuring, verifying, or documenting, not synthesized.

| # | Defect | Note |
|---|---|---|
| 1 | **`make lib-objs` / `make lib-so` broken**, reproducing on the committed boot compiler | `lib/arena.nuc` and `lib/node.nuc` die `duplicate definition of 'arena-init' / 'alloc-node'` (the auto-prepended prelude chain imports the entry file itself, and the entry file is on no dedup list); `lib/reader.nuc` dies `undefined: stderr` |
| 2 | **Two separately compiled Nucleus objects cannot be linked** | each inlines the whole prelude, so `build/lib/vector.o` and `build/lib/hashmap.o` share **7** duplicate public global definitions (`@g-arena`, `@g-intern-table`, …) and `ld` refuses. `exclude-prelude` works; a non-freestanding library is currently unlinkable |
| 3 | **`--emit-cheader` does not export globals** | a `defvar` reaches the `.nuch` as `(extern …)` but gets no `extern T name;` line in the C header, so a C consumer cannot reach it |
| 4 | **`--emit-cheader` emits hyphenated, invalid C identifiers** | see the precision note below |
| 5 | **`(exclude-prelude)` in an *imported* file dies `unknown top-level form`** | rather than being ignored or diagnosed as "must be the first form of the unit". `strip-exclude-prelude` (`nucleusc.nuc:12375`) is consulted only for the entry file |
| 6 | **`undefined: X — not defined anywhere in this compilation unit`** for a name that *is* in the unit, merely unprocessed | **overlaps W8's G-0; not filed twice.** G-0 has since closed the cause for the two import shapes it covers (plain and `import-use` symbol imports); the residual surface is string-path `.nuc` imports and `.nuch` headers, filed under W1 |
| 7 | **`pkind-flow-check`'s `CStr` carve-out accepts a null through a non-null `(ref T)`**, found measuring G-1 | only diagnoses a `TY-PTR` source, so `(defvar g:ptr:T (as CStr null))` compiles to a null in a non-null slot — and so does the identical *local*, by this compiler and the pre-G-1 boot alike; the renderer matches the chokepoint exactly, so the carve-out itself is what is wrong, in both positions at once |
| 8 | **`emit-as`'s int→int rule ignores the literal value on the `Val`**, found measuring G-1 | `(as i8 5)` is refused as lossy even though 5 fits — the same over-strictness [../stage14/int-widening.md](../stage14/int-widening.md)'s LW-4 fixed elsewhere; a ~3-line shared fix, declined here because it would have made G-1's bootstrap diff unprovable |
| 9 | **`(defvar g:i1 5)` emits `global i1 5`, silently truncated to `true` by LLVM**, found measuring G-1 | `int-literal-fits` returns 1 at width ≤ 1; pre-existing — the old boot emits the identical line for the bare literal — G-1 merely gives it a second spelling |
| 10 | ~~**`tests/run-tests.sh` PASS counts are unreliable by ±1**~~ — **closed 2026-08-09, and it was already closed when this item was written** | parallel unit stdout can interleave, splitting a `PASS  <name>` line across two lines — measured: three consecutive runs of the same tree all reported 361, but earlier runs reported 346 vs 347 and 360 vs 361 for what was the same tree, and a bare `w1d` token appeared alone on output line 314 in one capture; does not affect FAIL detection (0 FAIL held every time) but could in principle mask a dropped unit. **Correction.** Interleaving is impossible by construction: `spawn` (`tests/run-tests.sh`) redirects each unit's *entire* stdout+stderr into its own `$RESULTS_DIR/<id>.out` and the files are replayed in dispatch order after the join, so one unit's output cannot split another's line. That buffering landed in `cb864fa` (2026-07-05, "Parallelize tests") — **a month before this item was recorded on 2026-08-02** — so the ±1 evidence above was gathered against the pre-buffering harness and the item was never re-verified against the current one. Re-measured 2026-08-09 on the 16-core host: three consecutive parallel runs and one serial run of the same tree all report **463 PASS / 0 FAIL**, 35–38 s parallel vs 144 s serial (**4×**, not `build.md`'s stated 7×). The mechanism is the argument, not the sample size — this item's own note records three agreeing runs while the bug was believed live. **Consequence:** `NUCLEUS_TEST_JOBS=1` is no longer needed to count, and the convention of recording every verification with it — followed by every entry in this document from G-2 onward — is cargo. Use the parallel default |
| 11 | **Format-helper arity violations — FIXED 2026-08-02**, found building G-2 | **There were SEVEN, not three.** The recorded three were found by grepping `fmt-s` alone; sweeping *every* helper against its own parameter count found four more. Two directions, two failure modes. **Over-supplied** (format has more conversions than the helper feeds — the [conventions.md](../../context/conventions.md) trap): `call: expected %d args, got %d` (`nucleusc.nuc`), `BoxedFn call: expected %d args, got %d`, `(dyn %s): '%s' is not a declared protocol`, and a **fourth the record did not have** — `extend: '%s' is a protocol, so its supertype '%s' must be a protocol too` (`generics.nuc`). **Under-supplied** (fewer arguments than the helper has parameters, so it read an uninitialized register): `(fmt-sd "%%tc3.mat.%d" g-tmp)` and two `(fmt-2s "ptr %s" x)` in `abi.nuc`. **The recorded symptom is only half right, and the half it gets wrong is load-bearing**: only the two `%s %s` sites segfault (the garbage vararg is dereferenced as a pointer — both confirmed SIGSEGV with no output on the committed `bin/nucleusc`). The two `%d %d` sites do **not** crash — they print a garbage COUNT (`expected 2 args, got 100`; `expected 1 args, got 115`), a *silently misleading diagnostic*, which is worse for a user than a crash. **That also falsifies the recorded link to defect 12**: `call: expected %d args, got %d` lives in `emit-funcall-value`, the fn-pointer *indirect* call path, and has always been reachable — it was firing with a garbage number, not failing to fire. Each of the four diagnostics now has a test that would have crashed or misprinted before the fix (`tests/fixtures/w9-fnptr-arity`, `-boxedfn-arity`, `-dyn-not-protocol`, `-extend-super-not-protocol`); a corrected format string nothing executes is one edit away from regressing. All seven would also have been caught by defect 12's new check — every one is a wrong-arity call to a solitary `defn` |
| 12 | **A wrong-arity call to a solitary `defn` is not diagnosed — FIXED 2026-08-02**, found building G-2 | `(f 1 2)` against a one-parameter `f` emitted `call i32 @f(i32 1, i32 2)`, linked and ran. **The mechanism, precisely**: `emit-dispatch` (`nucleusc.nuc`) routes an overloaded name to `emit-generic-call`, where `generic-resolve` only matches a method at `num-params == nargs`, so a wrong count falls out as *no matching method*; a solitary name goes to `emit-call` → `emit-call-with-args`, which resolves the callee **by name** and never compared the counts at all. Fixed with the [conventions.md](../../context/conventions.md) shape — **one rule function both sides CALL**, not a second copy: `call-arity-ok` / `check-call-arity` (`nucleusc.nuc`, above `emit-funcall-value`) now serve the direct path, the fn-pointer indirect path and the BoxedFn/`dyn` box path, and `emit-call`'s own `&optional` `too few args`/`too many args` pair — which re-derived the band — was deleted rather than left beside it. The rule must NOT gate on `kind == TY-FN`: a box carries its signature on a **TY-STRUCT** Type (`boxedfn-type`), so a kind gate would have silently stopped checking that path. **Rulings on the variable-arity shapes**: `&optional` is a band (`num-params - nopt` … `num-params`), `&rest` is a floor (`num-params - 1`), a C-header `variadic` signature is a floor at its fixed prefix, an overloaded/multimethod/protocol/generic call is untouched (resolution already diagnoses it), and **too few arguments is an error in every shape**. **One carve-out, and it is load-bearing**: a hand-written `declare` is *open-tailed* — Nucleus has no `...` spelling and `&rest` is refused in a declaration, so the documented way to call a C variadic is to declare its fixed parameters and let the extras ride the call site, and **three existing tests already depend on exactly that** (`n6-nuch-link-and-run`, `sm3-import-resolves-mangled`, `s1-nuch-link-and-run`, each writing `(declare printf (fmt:CStr):i32)` and calling it with 3–6 arguments). Carried as `Sym.extern-decl`, set only in `emit-nuch-declare-import`, and **appended at the END of `Sym`** so no existing field's GEP index shifts and the bootstrap diff stays readable. **The check found TWO latent wrong-arity calls in the compiler's own source**, both silent reads of an uninitialized register: `generic-resolve-nullable` called `generic-method-bind` with 5 of its 6 arguments (the callee then read a garbage `arg-nodes` array), and `fn-rewrite-captures`' `.set!` branch built its OUTER `make-cell` without its `line` (every sibling passes it), so a rewritten closure-capture store carried a garbage source line. Zero elsewhere in `lib/`, `examples/` or `tests/fixtures/` — measured with a **warn-only compiler in a scratch worktree**, not by first-error iteration. Tests 410 → **421 PASS / 0 FAIL**; `make bootstrap` **byte-identical on the first pass** (no reconverge needed — the change alters no emitted IR); per-function normalized diff of `build/nucleusc.ll` against a compiler built from HEAD's source: 1050 byte-identical, 10 changed (exactly the ten edited), 0 removed, 2 added (`call-arity-ok`, `check-call-arity`); sweep: 218 byte-identical IR / 0 differing / 0 regressed, plus 123 rejecting programs with 0 diagnostics changed; `make abi-test`/`make layout-test`/`make avr-test` green |
| 13 | **`parse-type-from-node` silently returns null for an unknown cell head** | its `die-at "unable to parse type expression"` is a label-less trailing arm of `case (n kind)`, reachable only for a `NodeKind` outside `{NODE-SYM, NODE-CELL}`; for an unrecognized `NODE-CELL` head (e.g. `(nosuch i32)`) the `NODE-CELL` arm's `do` block matches no shape and falls through to null instead, so `(defstruct S (xs (nosuch i32)))` reports the misleading `defstruct: field 'xs' missing :type` rather than a diagnostic naming `nosuch`. Empirically confirmed against `build/nucleusc`; pre-existing |
| 14 | **Fn-pointer-typed `defvar` could not be declared at all — FIXED 2026-08-02**, found building G-3 | `(defvar g:(fn i32)(i32) null)` died `'g' already names a function`, a G-0 regression in `name-existing-kind` (it classified any `TY-FN`-typed global `Sym` as a function, and G-0's prescan defines that `Sym` before `emit-defvar` runs). Fixed in the interlude between G-3 and G-4 (commit `aa24eae`) with an `(= (sym is-local) 0)` conjunct, the same two-conjunct test `emit-dispatch` already used. `global-init.md` §7 #9 |
| 15 | **`aref` emits a hardcoded `i64` GEP index on every target**, found building G-3 | On AVR (16-bit pointers) a narrower index produces IR the LLVM parser rejects (`'%t3' defined with type 'i32' but expected 'i64'`); does not route through `ptr-int-ir` (AVR-2's fix for exactly this class). Not array-specific — a plain `ptr:ui8` with an `i32` index reproduces it. Reproduces on the committed boot. `global-init.md` §7 #10 |
| 16 | **A `defvar` may be declared twice in one unit with no diagnostic**, found in G-5 — **FIXED in B4 (2026-08-09)** | Emitted two `@g = global …` lines that the LLVM parser rejects with an unlocated error far from the cause. `guard-name-kind` compares NK-VALUE against NK-VALUE, finds them equal, and permits it — the same-kind allowance that exists for overloaded `defn` and REPL redefinition, applied where neither justification holds. The diagnosis was right and the scope was narrower than the defect: **every** non-function definer accepted a redefinition silently, with no agreed winner (a second `defstruct`/`defunion`/`defprotocol`/`defmacro`/template kept the FIRST, a second `defconst` kept the SECOND). R4's rule covers all of them; `emit-defvar` reads `Sym.defvar-state` (the same-kind question cannot be posed to the binding table — see name-resolution.md §9.6), and the two justifications the item names are preserved exactly: overloads still collide only on signature, and the REPL is exempt. `global-init.md` §7 #11 |
| 17 | **`as` did not arm the want channel — FIXED in G-5**, found in G-5 | `emit-as` emitted its operand without setting `g-want-type`, so a return-only-tyvar generic in `as`-operand position resolved against whichever instance the unit had stamped first; silent in the `unsafe/cast` spelling, which takes the wrong instance with no diagnostic at all. Proven inert for the whole tree by G-5's old-vs-new sweep (218 byte-identical, 0 differing). `global-init.md` §7 #12 |
| 18 | **`(= h null)` on a function-pointer value does not compile**, found alongside the Interlude/G-4 | `emit-binop-vals`'s null-literal escape and its pointer-comparison arm both gate on `is-ptr-like`, which deliberately excludes `TY-FN`, so the comparison falls through to the numeric path and dies `= expects integer operands`. Pre-existing and general — reproduces identically for a fn-pointer *parameter* or *local*, not just the new global spelling; the explicit `(unsafe/cast ptr h)` reinterpret is the escape hatch. Documented inline in `examples/fnptr-global.nuc`'s header comment (`hook-unset`) before this reconciliation; not previously in either defect list |
| 19 | **`type-size` has no `TY-FN` case**, found alongside the Interlude/G-4 | Falls through to the default `(return 1)` arm (`type-utils.nuc:359-360`), so every fn-pointer slot emits `align 1` — conservative, not a miscompile, since `abi-alignof`/`abi-sizeof` already answer correctly and struct layout is unaffected. Confirmed: `build/nucleusc --emit-llvm` on `(defvar hh:(fn i32)(i32) null)` emits `@hh = global ptr null, align 1`. Not previously in either defect list |
| 20 | **`coerce-int-val` has no `raw`→`TY-FN` case**, found in G-5 | `(let (f:(fn i32)(i32) null) …)` still dies `let: init type mismatch for 'f'` (confirmed against `build/nucleusc`) though the identical spelling at a `defvar` now compiles cleanly since the Interlude. Not previously in either defect list |
| 21 | **`(dyn ns/Proto)` is unusable across a namespace — FIXED 2026-08-03**, found building the defect-11 fixture | `conformance-add`/`-lookup`/`-args` canonicalized their keys with `strip-ns-qualifier` (Stage 12 N4 decision 9) while `protocol-lookup` matched the **raw** spelling, so `(extend Cat dp/Describe)` recorded the conformance under bare `Describe`, `admit-erased-conformance` found it and admitted the box, and `dyn-vtable-method-irname` then reported *"'dp/Describe' is not a declared protocol"* for a protocol that was both declared and conformed to. **The user's ruling picks the direction**: the two registries agree by making conformances keep the qualifier — a protocol is a namespaced entity — **not** by making `protocol-lookup` strip too, which would have made protocol names effectively global. **The crux is that decision 9's strip covered two different questions and only one of them was about types.** Of the nine `strip-ns-qualifier` sites, five are the TYPE half and are **unchanged** (`conformance-lookup`/`-args`/`-add`'s first argument, `verify-conformance-params`'s `typename`, `emit-extend`'s subject and its `(extend (Vector T) …)` template head, plus `union-registry.nuc:289`'s `lookup-struct`) — a qualified type reference still resolves to the same `StructDef` from any namespace, which is decision 9's actual claim. Four are the PROTOCOL half and now resolve through the namespaced registry instead (`conformance-*`'s second argument, `proto-super-add`'s **both** arguments, `verify-conformance-params`'s `proto-name`, `emit-extend`'s protocol). **`emit-extend`'s subject is both**: `(extend Describe Show)` puts a protocol in the type position, so the inheritance branch now resolves the raw spelling through `protocol-lookup` while `typename` keeps the type strip. Mechanism: `protocol-new` keys on `qualify-name` (identity under `user`); `protocol-lookup` probes qualified-then-bare (the same shape as W5e's private-name probe — the bare fallback is what lets a namespaced file still see `Clone`/`Eq`/`Ord`); registration uses an **exact** probe (`protocol-lookup-exact`) for the reason `generic-register-method` does, or `(ns dp) (defprotocol Clone …)` would fold into the prelude's; and one canonicalizer, `protocol-canon-name`, is what every protocol-keyed registry calls. It is placed in `nucleusc.nuc` rather than beside `protocol-lookup` because `union-registry.nuc` — imported *before* `generics.nuc` — needs it: **`dyn-type` must memoize on the canonical name**, or `(dyn Describe)` inside `(ns dp)` and `(dyn dp/Describe)` outside it would build two `StructDef`s and `type-eq` would call one protocol two incompatible types. `&where` constraint names are canonicalized where they are **written** (`parse-where-constraints`), not at each lookup, because a constraint is checked long afterwards under a different `g-current-ns`. **A second, smaller defect surfaced and is fixed with it**: once the two registries agreed, the "is not a declared protocol" message became unreachable — `emit-box-value` asks about *conformance* first, so `(dyn Nope)` reported the misleading `type 'Cat' does not conform to the protocol`. Both askers now CALL one `dyn-require-protocol`, and box construction asks existence first. `tests/fixtures/w9-dyn-not-protocol.nuc` was **re-pointed, not deleted**, exactly as its own header instructed: its `extend` now succeeds (it is the fix) and the `dyn` names an undeclared `dp/Missing`. **Census: no existing program changes** — every `defprotocol` in `src/`, `lib/`, `examples/` and `tests/` is in `user`, where `qualify-name` is the identity. `examples/w9-dyn-ns.nuc` links and runs, asserting the dispatched results `105/207/309`: a qualified reference under a *different* import prefix, a bare reference inside its own namespace, and two namespaces each declaring a `Describe` with one type conforming to both. Tests 421 → **424 PASS / 0 FAIL**; `make bootstrap` **byte-identical on the first pass** (predicted: protocol *method* ir-names come from `Generic.ir-prefix`, which this does not touch); sweep against a compiler built from HEAD's source: **223 byte-identical IR, 0 differing**, and across 133 rejecting programs **0 pre-existing diagnostics moved** — the one REGRESSED and one NEWLY-COMPILES entry are the new fixtures, and the REGRESSED one is the collision the ruling exists to create (the old compiler silently accepted a bare `Describe` with two in scope). `make abi-test`/`make layout-test`/`make avr-test` green. **Three unrelated pre-existing defects found in passing, none fixed — filed as items 22, 23 and 24** |
| 22 | **A file with an explicit `(ns …)` cannot box a value at all**, found building item 21 | `emit-box-struct-move` gates on `(scope-lookup scope "default-allocator")`, and `scope-lookup` qualifies a *global* key against `g-current-ns` with **no bare fallback** — so inside `(ns dp)` it probes `dp/default-allocator`, misses, and dies `type-erasure: boxing a value requires (import-use allocator)` however many times the file imports it. Confirmed identical on the committed pre-fix compiler, so it is pre-existing and orthogonal to item 21 (which is why `examples/w9-dyn-ns.nuc` boxes in the consumer, not in the library). The general shape is broader than boxing: any compiler site that resolves a *known* global by name through `scope-lookup` is namespace-sensitive in a way its author did not intend. Note `generic-lookup` is unaffected — it keys on the raw name — which is why ordinary cross-namespace *calls* work and hides how narrow the working path is |
| 23 | **Two namespaces defining the same function name collapse into one generic**, found building item 21 | `generic-lookup`/`generic-register-method` key on the **raw** name (unlike `scope-define`, which qualifies), so `(ns qa) (defn describe …)` and `(ns qb) (defn describe …)` become one `Generic` named `describe` with two methods — mangled under whichever namespace was seen *first*, emitting `@qa__describe` and `@qa__describe.pDog` for a method defined in `qb`. Confirmed identical on the committed pre-fix compiler. Whether the fix is to namespace the generic registry or to keep it raw and namespace only the mangling is a real design question, not a typo; item 21 deliberately did not touch it, and `lib/nsdescribe2.nuc` names its protocol method `tag-of` rather than `describe` specifically to keep the two concerns separate in the tests |
| 24 | **`(dyn P)` cannot box a type whose implementation arrives through a `.nuch` `declare`**, found verifying item 21 | `dyn-vtable-method-irname` resolves the protocol method with `generic-lookup`, but `emit-nuch-declare-import` registers a solitary imported function as a **`Sym` in `g-globals` only** — it never creates a `Generic` — so the box site dies `(dyn Describe): no method 'describe' is defined` for a method that is declared, defined and linkable. Confirmed identical in the `user` namespace and on the committed pre-fix compiler, so it is pre-existing and orthogonal to item 21 (which the same probe *passes*: the protocol resolves, and the failure is one check later). Note the `.nuch` round-trip itself is correct — the producer emits `(ns dp)` ahead of the `defprotocol`/`extend`, and the importer re-registers the protocol under `dp/Describe`. The same two-registries-answer-one-name asymmetry `context/conventions.md` records for private names (`scope-lookup` vs `generic-lookup`) is the underlying shape |

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
library.

---

## B — Name resolution *(added 2026-08-08; B0, B1, B2a, B2b, B5, B3′, B6 and B4 done — the series is complete)*

Full design, measurements and rulings: [name-resolution.md](name-resolution.md).
Staging is B0 (record the matrix) → B1 (file-scoped import environment) → B2
(the canonicaliser, cut over kind by kind: **B2a protocols**, **B2b globals** +
`unsafe` + deleting alias injection) → B3′ (re-key the type registries) → B4
(collision policy) → B5 (the shared binding interface) → B6 (`(dyn P)` identity
vs admission). **All of B0–B6 are done**, B4 last (2026-08-09).
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
