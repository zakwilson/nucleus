# Stage 15 Progress — Stress Testing (Doom port findings)

Back to [../progress.md](../progress.md). Stage overview: [overview.md](overview.md).

**W4 and W2 are complete** (W2a/W2b/W2c/W2d all landed). **W3a is done**
(§1.6, opaque forward-declared C types) and **W3b is done** (§1.5, C type
qualifiers + the `declare` validity gate — `SDL2/SDL.h` now imports, links and
runs) and **W3c is done** (§1.4, typedef chains + declaration precedence — the
header ladder is closed and all three rungs are reached, plus a follow-up fix to
`declare`'s unnamed parameter parse that W3c's precedence rule surfaced), so
**all of W3 is complete**. **W5 is nearly done** — W5a, W5b, W5c, W5d and W5f
landed; only W5e remains (it is sequenced after W1). **W1a + W1b + W1c are done**
(whole-unit signature resolution, and the diagnostic surface that goes with it —
see the W1 section below); W1e is resolved by obsolescence, so **W1d (mutual-import
policy) is the only W1 chunk still open**, and it is a decision rather than a
defect. **W6's design document is written**
([nullability.md](nullability.md)) — no code or docs exist for the
not-started items yet beyond their spec docs ([resolution.md](resolution.md),
[literal-typing.md](literal-typing.md), [cheader.md](cheader.md),
[ergonomics.md](ergonomics.md), [nullability.md](nullability.md)).

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
* **`context/build.md`'s parallel-test-suite timing figure (`~8.5s`) is
  stale** — measured baseline is now `~18.8s` (16-core host), predating the
  AVR/RISC-V gates and the W4a–W4d fixture batches. Found during W4e's
  generated-table sub-part; left uncorrected there and here, since it's
  session-continuity material outside this stage's `docs/`-truthfulness scope
  — flagged for whoever next audits `context/build.md`.
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

Spec: [ergonomics.md](ergonomics.md). Partly done; the remaining sub-items are
independent and are the stage's parallel fan-out (see
[prompt.md](prompt.md) §4).

| Chunk | What landed | Status |
|---|---|---|
| **W5a** | §4.4 — `"MUS\x1a"` died `unknown escape \x`, forcing the Doom port to poke a four-byte magic number into an `(alloca ui8 N)` byte by byte. Added a `\xHH` arm to `lex-string`'s escape chain (`lib/reader.nuc`), reusing the existing `hex-digit-val` helper; purely additive, and it sits entirely before the `(>= n 4095)` buffer guard and the single-byte `aset!`, so neither moved. **Decision: capped at two hex digits**, taking the spec's recommendation — C's `\x` is greedy, so C's `"\x41BC"` is one overflowing character while here it is the three characters `A`, `B`, `C`. One digit is accepted where unambiguous (`"\xa"` == `"\x0a"`). A `\x` with no hex digit is a located reader error, and the fixture pins the `:6:` line prefix rather than merely scanning for `:0:`. Verified by running, not by reading IR: `"MUS\x1a"` → `4d 55 53 1a`. Premise correction: `ergonomics.md` said reader.nuc "already supports `\a`, `\newline`, `\u{…}`" — those are *char* literals (`lex-char-literal`), a different function; the string escape table was a flat six-entry list, and `docs/` had never documented string-literal escapes at all, so the table in `docs/types.md` is new rather than an edit. 2 new checks. | **Done** |
| **W5b** | §4.3 — no unary `bit-not`, so C's `~x` had to be written `(bit-xor x -1)` by hand. Added as a one-argument macro in `lib/macros.nuc:79` expanding to exactly that, per the repo's "prefer macros over builtins" principle: correct for two's complement at every width, no codegen. W4a's stopgap correction-table entry (`bit-not` → "no unary 'bit-not'; write (bit-xor x -1)") was removed when it landed, as `ergonomics.md` required, and W5b's section was removed from that spec doc. Verified against `build/nucleusc`: `(bit-not 3)` is `-4`. | **Done** |
| **W5c** | §3.7 — a `defvar` global may now be typed `CStr`. `defvar-init-ir`'s string-literal and `null` gates tested a bare `TY-PTR` kind where the standing rule is `is-ptr-like`; both now accept `CStr` and name the offending type on rejection. **Both** literal spellings are accepted, for `ptr` and `CStr` alike — a plain `"…"` was *already* accepted here for `ptr`, and at a global initializer the `StrView`/`CStr` distinction has collapsed (the `@.str.N` rodata is NUL-terminated either way), so accepting only `c"…"` would have invented an asymmetry the value path does not have. **The line-0 half of the finding did not reproduce** — W4 had already fixed it. **The finding was bigger than specced:** making the spelling compile exposed a *segfault*. `emit-binop-vals` fires its strcmp content-comparison whenever either operand is `CStr`/`StrView` — including against the `null` literal — so `(= g null)` emitted `strcmp(ptr %t0, ptr null)`, UB in C and a crash under glibc (measured: exit 139). Pre-existing and not global-specific (a `CStr` *parameter* null-checked with `=` lowered identically — `conventions.md`'s documented "null-check trap"), but W5c promotes it from a compiler-internals hazard to something ordinary user code hits immediately, so it was fixed: the strcmp branch is suppressed when either operand *node* is the symbol `null` and the other is `is-ptr-like`, and the identity gate below was widened to `is-ptr-like` so the escape lands on `icmp eq ptr`. Strictly a bug fix (no correct program can depend on UB) and inert for the compiler's own IR (`boot/nucleusc.ll` has zero `strcmp(ptr %x, ptr null)`). Deliberately out of scope: `(as CStr …)` in an initializer (the general expressions-aren't-literals rule, identical for `(as ptr …)`) and `StrView`-typed globals (needs aggregate constant initializers). 4 new checks. | **Done** |
| **W5d** | §3.9 + §3.10 — array-literal ergonomics. **§3.9 was fixed at the shared chokepoint, not at the array literal**, and the spec's "inserting one load, not new machinery" prediction held exactly: `coerce-int-val` (`src/abi.nuc`) now loads a `ptr:S` into a by-value `S` slot when the pointee's StructDef *is* the target's. The decisive measurement is that the ARGUMENT position already did precisely this (Stage 13 CE-3's by-value normalization in `emit-call-with-args`), so `(take (P 1 2))` compiled while `(let (v:P (P 1 2)) …)` did not — the fix is one rule reaching the other eight typed slots, not a new liberty. Verified byte-for-byte: the 1000-row table compiles to **identical IR** under the bare and `(deref …)` spellings (only the module-ID line differs), 1000 allocas + 1000 loads, linear. `safe-coerce-val` never delegates a ptr→struct pair down, so the argument path cannot even reach the new branch. **§3.10 was narrower than the finding claimed** — `(let (a:ptr:ptr …))` and an *unannotated* binding both already worked, so the wart was the annotated-but-imprecise middle case alone, and it is not ptr-of-ptr-specific (`(array i32 …)` bound to `:ptr` failed identically). Fixed with a deliberately **syntactic** rule (`array-lit-binding-type`, `src/generics.nuc`, called by `emit-let`/`emit-with` and mirrored in `node-type-block` — one rule function, two callers, per the lockstep): an `(array T …)` init refines an elem-less declared pointer to `ptr:T`, keeping the declared pkind and volatility. The general "adopt the init's element type" rule was **rejected on measurement**, not taste: `type-eq` compares pointer elements, so adopting an elem re-routes multimethod dispatch, and a bare `:ptr` also erases the *nullability claim* (`pkind-flow-check` exempts an elem-less target) — there are ~1550 bare `:ptr` bindings in this compiler, 113 of them from `addr-of` alone. **Two pre-existing crashes found on the path this opens** (both confirmed against the pre-W5d binary): `emit-zero-store` emitted `store %P 0` for a struct slot and `store ptr 0` for a `CStr`/`TY-FN` slot, both LLVM parse errors — so a *sparse* `(array S …)`, exactly the shape a generated table with holes has, produced unparseable IR. Fixed with `zeroinitializer` for aggregates and the standing `is-ptr-like` test for pointers (`conventions.md`'s documented TY-PTR-vs-is-ptr-like trap, hit again). Proof of confinement: a per-function normalized diff of the compiler's own IR shows **exactly** the 5 edited functions plus the 1 added one changed, nothing else — the refinement never fires in `src/` (no `(array …)` there). 4 new checks. | **Done** |
| **W5e** | `defn-` name isolation (§2.5) — a design decision, sequenced after W1 because it touches the same global-key scheme. | Not started |
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
| **W1d** | Mutual-import policy (keep `circular import` a hard error vs. allow cycles). | Not started — decision pending; the current hard error is pinned by a test so relaxing it stays deliberate |
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

## W7 — The bare-symbol selector always means "field name" (design only)

**Status: designed, not implemented.** Spec:
[selector-ambiguity.md](selector-ambiguity.md).

Reported from `examples/hashmap-lit-test.nuc`, whose working tree now binds
`k:CStr "foo"` and calls `(m k)`. That fails —
`get: no field 'k' on struct 'HashMap.cstr.i32'` — while `(m "foo")` succeeds.
**This is the one failing test in the suite** (296 pass, 1 fail); it is the
reproducer, not a regression.

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
