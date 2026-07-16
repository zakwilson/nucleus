# Stage 14 — Integer literal widening: close the residual gaps

Calls like `(char-at sv 1)` and `(arena-alloc 16)` were reported as requiring
casts on integer-literal arguments, where implicit widening was expected. This
doc pins down exactly which positions still require casts, and designs their
removal. It is the integer complement to [type-safety.md](type-safety.md)'s
pointer-cast retirement: that doc retires ~3,674 pointer casts; the tree also
carries **~991 `(cast <int-type> <literal>)` forms**, most of them vestigial.

**Premise correction (ground-verified 2026-07-02, current `build/nucleusc`):
the reported sites already compile bare.** The Stage-7 implicit-cast work
landed and covers far more than remembered — in-tree proof:
src/nucleusc.nuc:827-829 calls `(char-at lex 0)` bare, two lines above a
vestigial `(cast i64 0)`. What remains is a short list of genuine gaps, two of
which are **silent-wrong-code bugs**, plus the bulk vestigial-cast cleanup.

---

## 1. Ground truth (all verified by compiling repros, 2026-07-02)

### 1.1 What already works bare — no cast needed today

| Position | Repro | Path |
|---|---|---|
| plain defn, `i64` param | `(arena-alloc 16)` | `safe-coerce-val` |
| plain defn, `usize`/`ui8` param | `(takeu 16)`, `(take8 104)` | same |
| C extern | `(malloc 40)` | same (declare → `emit-call`) |
| protocol multimethod | `(char-at sv 1)` — `i:usize` | tier-2 `arg-adapts` |
| `let` init, declared type | `(let (n:usize 16) …)` | `coerce-int-val` |
| `defvar` global init | `(defvar g:i64 16)` | `defvar-init-ir` (target-typed) |
| mixed arith with literal | `(+ u 1)`, `(< u 6)` (`u:usize`) | `binop-coerce` |
| typed-var widening at call | `n:i32` → `(arena-alloc n)` | tier-2 (same-sign widen) |
| nested expression arg | `(arena-alloc (+ 8 8))` | i32 result widens |
| field store / `aset!` | `(.set! sv len 1)`, `(aset! buf 0 104)` | `coerce-int-val` |
| `case` arms vs `usize` scrutinee | `(case u 5 1 6 2 0)` | binop path |
| lambda call | `((fn (n:i64):i64 n) 16)` | call path |

Machinery (surveyed): `coerce-int-val` (src/abi.nuc:428-467, the
assignment-shaped coercer — same-width sign reinterpret, else trunc/sext/zext),
`safe-coerce-val` (src/nucleusc.nuc:1390-1409, call sites at 2727-2730, plus
the `defcast` registry), `coerce-num-val` (1344-1364), `binop-coerce`
(1466-1506; an untyped literal adopts the other operand's type), and the
generic-resolution **tier-2** widen/literal adaptation — `arg-adapts`
(src/generics.nuc:383-397; a literal adapts to any int type, a typed value
only same-sign-widens) applied at generics.nuc:436-453 with ambiguity
accounting. The ambiguity diagnostic works: overloads `(f x:i32)`/`(f x:i64)`
called with a literal die `ambiguous overload for 'f' under argument widening`
(generics.nuc:451-452; verified). Exact match always beats widening. No
width-only overload sets exist in the tree today.

### 1.2 Gap A — template-tier methods never adapt (the real reported pain)

Methods whose receiver is a **parametric-struct template** get no adaptation
at all — verified on `(Vector i64)`:

```lisp
(conj v 3)      ; error: no matching method for overloaded 'conj'
(v 0)           ; error: no matching method for overloaded 'invoke'
```

Both compile with `(cast i64 3)` / `(cast usize 0)`. Note `invoke`'s failing
param is `i:usize` — **not a tyvar**; the whole method is simply resolved
through the template tier (`generic-binds-for`/`unify-tpat`, exact-only),
and the tier-2 adaptation loop never considers template candidates. This is
the entire stamped collections API — `conj`, `insert`, `invoke`/`(v i)`,
HashMap `get`/`put` with integer keys — which is precisely where literal
indices and elements are ubiquitous (`(cast usize 0)` ×70 and `(cast usize
1)` ×86 in lib/ alone). The reported `char-at`/`arena-alloc` friction is
almost certainly a memory of this class (or of a pre-Stage-7 checkout).

### 1.3 Gap B — explicit `return` doesn't coerce

`(return 0)` in an `:i64` function emits `ret i32 0`, which surfaces as a
raw **LLVM parse error** (`value doesn't match function result type 'i64'`)
— not even a source-level diagnostic. Verified. The *implicit* end-of-body
return does coerce (`coerce-int-val last-val ret`, src/nucleusc.nuc:7093);
`emit-return` (5017-5056) never does. Known gap since Stage 7
(design/stage7/implicit-cast.md:212-216).

### 1.4 Gap C — silent wrong code from default-i32 literal emission

`emit-int` stamps every literal `ty-i32` (src/nucleusc.nuc:801-802) even
though the node retains the full value (`Node.i:i64`, lib/prelude.nuc:16;
lexed via `strtol`, lib/reader.nuc:312). Coercion then operates on the
already-wrong constant. Verified consequences:

- `(take64 5000000000)` compiles, links, **runs, and prints `705032704`**
  (the i32 wrap, then `sext i32 5000000000 to i64` in the IR).
- `(take8 300)` silently emits `trunc i32 300 to i8` (= 44). There is **no
  representability check anywhere** (the only literal check is
  kind-compatibility in `defvar-init-ir`).
- The lexer has no overflow check (`strtol` clamp is silent) and no
  `strtoull` path, so `ui64`-scale literals are unrepresentable.

### 1.5 Gap D — the type model doesn't know about widening (lockstep hole)

`node-type-call` (src/generics.nuc:3235-3279) resolves overloaded generics
with `generic-find-method-exact` + `generic-binds-for` only — it never runs
the tier-2 adaptation that emit runs. A widened generic call therefore types
as null. Benign today (the documented node-type escape hatch), but it means
the static model cannot type any widened call, and per the
conventions.md node-type↔emit lockstep rule, Gap A's fix **must** land in
both files together.

### 1.6 Deliberate strictness that stays

Mixed-**sign** binops between two *typed* values (`(+ i32-var usize-var)`)
error (`binop-coerce` returns null at 1497 → `"%s operand type mismatch"`).
Literals adapt to either side, so this only bites variable/variable mixes —
a genuine correctness guard, kept as-is (§3 non-goals).

## 2. Non-goals

- No implicit **narrowing** of typed values, no mixed-sign variable binops,
  no implicit int↔float for variables — existing strictness stands.
- No literal suffix syntax and no `(i64 5)` scalar-constructor form (§6).
- No change to "exact match beats widening" or to the ambiguity error.
- Widening rules for *typed values* stay same-sign-only (`arg-adapts`
  as-is); this doc extends **where** the existing rules apply, not what
  they permit.

## 3. Design — phases

### LW-1 — extend adaptation to the template tier (fixes Gap A)

**Status: DONE (2026-07-03).** Implemented in `src/generics.nuc`. A shared,
side-effect-free `generic-resolve-adapt-tier` runs the tier-2 pool for both the
emit path (`generic-resolve`, dies on ambiguity, monomorphizes a template winner)
and the type-model path (`node-type-call`, returns null). Template candidates are
matched by `generic-method-bind-adapt` (bind tyvars from the receiver/exact args,
then `arg-adapts` each remaining param against its tyvar-substituted type;
adaptation never binds a tyvar). One subtlety not in the original design: a
template's own **stamped instance** (created the first time a widened call resolves)
is a METHOD-USER that *also* adapts, so it would spuriously read as a second
candidate → false `ambiguous overload` on the *next* widened call. Fixed with a
`Method.origin-template` marker (set by `generic-instantiate`); the tier-2 USER
pool skips stamped instances (the template alone covers every widened call, and
tier-0 still resolves exact-typed calls to the stamped instance). `(conj v 3)` /
`(insert v 1 7)` / `(v 0)` on a `(Vector i64)` now compile with no casts. Byte
count of the compiler's own IR was a bootstrap fixed point directly (the compiler
source casts every affected site, so the new resolution is inert during
self-compilation); the vestigial casts stay until LW-5. `operator-user-resolve`
was checked: it only ever scans METHOD-USER methods and has no METHOD-GENERIC
(template) tier at all — template operators are unreachable through it today, so
adding widening there would be dead code. Left untouched (see §3 note below).

In generic resolution, template candidates join the adaptation tier: unify
the receiver and exactly-matching args via `unify-tpat` to bind tyvars
(unchanged), then for each remaining param apply `arg-adapts` against the
tyvar-substituted param type — a literal adapts to a bound-tyvar type or a
concrete param (`i:usize`) exactly as it does for plain methods. Two rules:

- **Adaptation never binds a tyvar.** `(conj v 3)` on `(Vector i64)` binds
  `T=i64` from the receiver, then `3` adapts to it; a bare-template call
  where only a literal could determine `T` keeps today's behavior (literal
  binds `T=i32` via exact unify).
- **Same ambiguity accounting** (`wn>1` → the existing
  `ambiguous overload … under argument widening` death), now counting
  template and plain candidates together; exact/tier-1 matches still win
  outright.

`operator-user-resolve` gets the same treatment if template operators are
reachable there (confirm during implementation).

### LW-2 — mirror in `node-type-call` (fixes Gap D; lands with LW-1)

**Status: DONE (2026-07-03), landed atomically with LW-1.** `node-type-call`'s
mangled-generic branch now builds an `arg-nodes` array (needed for literal
detection) and, after the exact + `generic-binds-for` tiers, calls the shared
`generic-resolve-adapt-tier` with a non-dying mode: a unique USER match returns
`(m ret-type)`, a unique template match returns `method-bound-ret-type` (the
tyvar-substituted return, extracted from `generic-binds-for` so the exact and
adapted template paths compute the return type identically), and
ambiguity/no-match returns null (the escape hatch — `node-type` never dies). The
substituted-return helper is *side-effect-free*: unlike the emit path it never
instantiates, so the type-model context stays a pure probe. Verified that
`node-type-call` types a widened `(conj v 3)` as `void` (the resolved template's
return) rather than the previous null. Note: the value-keyed `(v i)` invoke path
node-types through `callable-invoke-type`, a *separate* mirror that remains at the
exact tier (returns null → escape hatch, non-divergent) — the design's Gap D and
this milestone scope LW-2 to `node-type-call`; extending `callable-invoke-type`
is deferred (it becomes load-bearing only once LW-5 removes the `(cast usize i)`
casts at `(v i)` sites in the compiler's own source).

Factor the emit-side resolution so `node-type-call` runs the same tiers —
ideally both callers share one resolver (with a non-dying variant for the
type-model context, which must return null rather than die on ambiguity).
LW-1 and LW-2 are **one change** for lockstep purposes; the bootstrap
fixed point is the enforcement gate.

### LW-3 — coerce explicit `return` (fixes Gap B)

`emit-return` runs `coerce-int-val` against the declared return type,
matching the implicit end-of-body path (7093). On failure: a *source-level*
error naming the function and types — never again the raw LLVM parse error.

**Status: DONE (2026-07-03).** Implemented in `emit-return`
(src/nucleusc.nuc): right before the final `ret`/`emit-struct-ret` dispatch,
the scalar branch (only reached when `g-fn-ret-abi` is null or `ABI-DIRECT`
— `abi-classify` assigns every other kind to `TY-STRUCT`/`TY-UNION`, so this
branch never carries an aggregate return type) now coerces the returned
`Val` against `g-fn-ret-type` via `coerce-int-val`, guarded on
`g-fn-ret-type != null` (some contexts leave it null; behavior there is
unchanged — `v`'s own type is used uncoerced as before). On coercion
failure (`coerce-int-val` returns null) a source-level `die-at` fires at the
call's line, naming both types via `type-spelling`
(`"return type mismatch — returned value of type %s does not match
declared return type %s"`) — adapted from the implicit path's phrasing;
`fname` isn't available inside `emit-return` (unlike `emit-defn`) so the
function name is omitted rather than threading new global state through
just for this message. Verified independent of `pkind-flow-check`: the
existing `(ref T)`-nullability guard a few lines above (line ~5075-5076)
only fires on pointer-kind destinations, and `coerce-int-val`'s own
internal `pkind-flow-check` call (for a `TY-PTR` target) is a same-args
no-op re-check once the earlier guard has already passed without dying —
purely int/CStr coercion is orthogonal. `(defn f:i64 () (return 0))` now
compiles and runs printing `0` (previously an LLVM parse error); a genuine
mismatch (e.g. `(return 1.5)` in an `:i64`-declared fn) now dies cleanly at
the source line ("return type mismatch — returned value of type f64 does
not match declared return type i64") instead of an LLVM parse error. The
new string literals shifted the compiler's string pool (unrelated
constants renumbered) — required the standard `make update-bootstrap` +
`make clean && make` reconverge (conventions.md); `make bootstrap` is a
byte-identical fixed point afterward, and all 140 `make test` cases pass.

### LW-4 — truthful literals: range checks + wide emission (fixes Gap C)

- **Representability check**: wherever a literal adapts/coerces and the
  node's value is known (`node-is-int-literal`, src/nucleusc.nuc:1326-1333;
  value on `Node.i`), an out-of-range value is a compile-time error
  (`integer literal 300 does not fit ui8`) instead of a silent trunc/wrap.
- **Out-of-i32-range literals emit at i64** (`emit-int` consults the
  value), so `(take64 5000000000)` produces 5000000000; such a literal in a
  genuinely 32-bit context now errors instead of wrapping. In-range
  literals keep the existing emit-then-coerce path — this keeps the change
  near-byte-identical (audit the tree for out-of-range literals during
  implementation; expected none).
- **Lexer**: check `strtol` overflow (errno) and add a `strtoull` path so
  `ui64`-scale literals lex correctly; oversized literals get a reader
  error with position, per the reader's `!T` error discipline.

**Status: DONE (2026-07-03).** Implemented as a Val-tagged single chokepoint
plus the lexer path:

- **`Val` carries the literal** (`is-lit:i32`, `lit-i64:i64` in
  compiler-types.nuc). `emit-int` is the *only* setter; every non-literal Val
  is `is-lit=0` (arena zero-init). Because every narrowing coercion of a literal
  routes a literal-tagged Val through `coerce-int-val` — let/defvar init, field
  store, `aset!`, explicit/implicit `return`, union-variant construction,
  plain/generic/protocol call args (via `safe-coerce-val`), and binop literal
  adoption (via `coerce-num-val`) — the representability check lives in exactly
  **one** place: the int→int branch of `coerce-int-val` (abi.nuc). A tagged Val
  whose `lit-i64` is not representable in the target dies with
  `integer literal N does not fit <type>` (`type-spelling`). Typed *values* are
  untouched (they carry `is-lit=0`; their runtime value is unknown), so the
  narrowing non-goal holds automatically. The shared predicate is
  `int-literal-fits:i32(v:i64 t:ptr)` (type-utils.nuc): i1 and 64-bit-wide
  targets always fit (the latter holds any i64 bit pattern); narrower targets
  check the exact signed/unsigned range, with bounds built from `bit-shl` (never
  a >i32 decimal literal, so the predicate is a bootstrap fixed point).
- **`emit-int` truthful width**: emits `i32` when the value fits (the majority),
  else `i64`. `node-type`'s NODE-INT branch (generics.nuc) mirrors this
  exactly (the emit/node-type lockstep); `gcheck`/`valid-walk` are independent
  def-time walkers that never feed emit, so they were left at `ty-i32`.
- **Lexer** (`lex-atom`, reader.nuc): `strtol` is run with errno cleared and
  checked for `ERANGE` (34); a non-negative overflow retries via `strtoull`
  (ui64/usize scale — bits stored into the signed `i64` field, `%ld` + LLVM
  two's-complement wrap reproduce the value), and a negative overflow or a value
  above `u64` is a positioned `report-at` + `(err! parse-error)`. `errno` is
  reached via a hand-declared `__errno_location` (the header macro is not
  surfaced by the clang-based header reader); `strtoull` comes from the global
  `(import-use "stdlib.h")`.
- **Latent bug fixed**: the FNV hash constants (`-3750763034362895579`,
  `1099511628211`) were silently i32-truncated by the old `emit-int` — hashing
  "worked" only because it was self-consistently wrong. LW-4's wide emission
  makes them correct; `examples/cstr-fold-test.out` was updated to the real
  FNV-1a of "hello, world" (`1702823495152329533`, verified independently).
  `examples/types.nuc` deliberately demoed a silent i8 wrap (`(let (byte:i8
  200))`); it now uses an explicit `(cast i8 200)` (the allowed narrowing
  escape hatch), preserving `byte = -56`.
- **Bootstrap**: NOT byte-identical (Val grew → `sizeof Val` renumbers; new
  error strings shift the pool; corrected FNV constants renumber temps and
  change the union-shape hash embedded in `%__anon_union_h…` names). The
  standard reconverge took **two** `update-bootstrap` rounds because the
  corrected internal FNV constant must propagate one extra generation into the
  boot binary that computes the union names. All 140 tests pass afterward.
  `(take64 5000000000)`→`5000000000`, `(take8 300)`→range error, and
  `ui64`-scale literals (`2^63`, `u64max`) lex correctly; `u64max+1` errors.

### LW-5 — vestigial-cast sweep + docs

**Status: DONE (2026-07-15).** All batches complete — test/doc slice, src/,
lib/ (both the macro-free files and the 6 `defmacro`-containing files), and
examples/. See the per-batch write-ups below for counts, verification, and
the three documented failure classes. `examples/int-widening.nuc` was
added: castless `conj`/`insert`/`(v i)` invoke on `(Vector i64)` (LW-1/LW-2),
a castless explicit `(return 5)` from an `:i64` function (LW-3), and
`(take64 5000000000)` printing the untruncated value (LW-4) — expected output
`tests/expected/int-widening.out`. Two negative fixtures were added following
the `closure-escape-rejected`/`ce3-use-after-move-rejected` idiom in
`tests/run-tests.sh`: `tests/fixtures/lw-ambiguous-widening.nuc` (an overload
set with **no exact-i32 candidate** — `x:i64`/`x:ui8` — called with a bare
literal; both candidates reach the tier-2 adaptation pool, so the call is
genuinely ambiguous and dies `ambiguous overload for 'f' under argument
widening`; note the `(f x:i32)`/`(f x:i64)` shape sketched earlier in this doc
is *not* ambiguous — a literal exact-matches the `i32` candidate at tier 0 and
tier 0 always wins, so the negative fixture needs two candidates that both
require widening) and `tests/fixtures/lw-literal-range.nuc` (`(take8 300)` →
`integer literal 300 does not fit ui8`). `docs/types.md`'s "Implicit Type
Coercion" and "Literal Values" sections (written during LW-4) were checked
against LW-1 through LW-4's actual behavior and found already accurate — no
edit needed. The "fix the strview example's vestigial casts" note was
checked: the Keyword/StrView example in `docs/types.md` (~line 251-281) has
no cast at all, and `examples/strview-test.nuc`'s casts are unrelated
(`cast ptr` for `free`, `cast ui64` widening a return value to match a
`printf` format spec) — neither is a vestigial int-literal cast LW-1-4 made
removable, so nothing applied there. 143 tests pass; `make bootstrap` holds
(no `src`/`lib` changes in this slice).

**Status: src/ batch DONE (2026-07-15).** Swept all `(cast TYPE N)` forms in
`src/` where `TYPE` is one of `i8 i16 i32 i64 ui8 ui16 ui32 ui64 usize ssize`
and `N` is a bare (optionally negative) integer literal, via a per-file
`perl -pi -e 's/\(cast (i8|i16|i32|i64|ui8|ui16|ui32|ui64|usize|ssize)
(-?[0-9]+)\)/$2/g'` pass, in groups of 2-3 files with `make && make test`
(174/174) after each group. Final per-file counts (removed / originally
present, re-grepped at sweep start):

| File | Removed | Kept (special-cased) |
|---|---:|---:|
| src/nucleusc.nuc | 97 | 12 |
| src/cheader.nuc | 69 | 6 |
| src/repl.nuc | 49 | 10 |
| src/format.nuc | 31 | 8 |
| src/union-registry.nuc | 16 | 10 |
| src/generics.nuc | 14 | 1 |
| src/union-emit.nuc | 14 | 0 |
| src/abi.nuc | 3 | 0 |
| src/type-utils.nuc | 2 | 1 |
| src/scope.nuc | 1 | 0 |
| **Total** | **296** | **48** |

**Verification:** `make bootstrap` holds the byte-identical fixed point
(stage1.ll == stage2.ll); `make test` 174/174 throughout; the strong check —
a full `build/nucleusc.ll` diff against a pre-sweep snapshot — is **exactly
zero** after special-casing (below). All 48 kept sites still match the
`(cast TYPE N)` literal pattern textually but were deliberately restored
because removing them was not actually inert; two distinct failure classes
surfaced, both bisected via the `sext iN … to iM` shape in the emitted IR:

1. **A real `node-type`/emit lockstep gap (compile-time failures, not just
   IR drift).** An intrinsic binop (`+`/`-`/`*`) whose *first* operand is a
   bare literal and second operand is a differently-typed (wider,
   non-literal) expression gets its *static* type computed by
   `node-type-call`'s intrinsic-operator branch (src/generics.nuc, "best-effort:
   the first operand's type") — i.e. the literal's own naive `i32`, ignoring
   the second operand entirely. At *emission* the binop correctly widens (the
   real `Val` ends up `i64`), but when that binop's result is itself consumed
   by an outer coercion (a further call argument, or nested inside another
   comparison), the outer site trusts the wrong claimed static type and emits
   a second, invalid `sext i32 → i64` on a value that is already `i64` — a
   malformed-IR `clang` parse error (`'%tN' defined with type 'i64' but
   expected 'i32'`), not a silent bug. Hit at `(- 0 half)`
   (src/type-utils.nuc:275, `int-literal-fits` — ironically the LW-4 literal-
   representability predicate itself), `(* 2 (ptr-bytes))` /
   `(* 2 (sizeof Val))` (generics.nuc, nucleusc.nuc, union-registry.nuc — the
   `argtypes`/`fnm`/`fty`/`bfn`/`bft`/`pair`/`args` two-pointer scratch-buffer
   idiom, 15 sites total), and `(- 2048 apos)` / `(- 512 sp)`
   (nucleusc.nuc, the `abi-arg-frag`/signature-string builders). Fix applied:
   restore just the one literal's cast at each such site (least invasive; this
   sweep's scope is mechanical, not a `node-type-call` redesign — the gap
   itself is a good LW-6-shaped follow-up: teach the intrinsic-operator
   best-effort branch to consult *both* operands, not just the first).
2. **Harmless but non-zero IR drift (compiles and runs fine, diff not
   literally zero).** Two sub-cases, both confirmed semantics-preserving via
   SSA-name-normalized diffing (strip `%tN`/`.addr.N`/`@.str.N`, per
   conventions.md's byte-identical-gate note) before deciding to restore:
   (a) a bare literal used as a non-final positional argument to a multi-arg
   call (`snprintf`/`fread`/`fwrite` size arguments in `format.nuc`'s `fmt-*`
   helpers, `cheader.nuc`, `repl.nuc`, `nucleusc.nuc`'s `read-file`/
   `rewrite-first-fname`/`emit-c-include`/JIT-error-message sites) gets its
   width-coercion **emitted later** (deferred to just before the call) than
   an explicit `(cast i64 N)` wrapper does (emitted eagerly at parse
   position) — same final call operands and values, just reordered relative
   to sibling pure loads; (b) a `(* LIT LIT)` two-bare-literal multiply
   (`(* 16 8)`, `(* 64 8)`, `(* 6 8)` in cheader.nuc/repl.nuc struct-field
   scratch-buffer sizing) collapses from 3 instructions (`sext`, `sext`,
   `mul i64`) to 2 (`mul i32`, `sext`) — mathematically identical for these
   small in-range constants, just fewer instructions. Both are true
   simplifications/reorderings with zero behavioral difference (confirmed:
   `make test` never caught either — they were only visible in the literal
   `nucleusc.ll` diff), but were restored anyway to hit an exact zero-diff
   strong check rather than argue the point. One doubly-nested case
   (`(cast i8 (cast i64 48))` in `nucleusc.nuc`'s float-literal formatter)
   is the single-pass-regex residue this doc's method warned about implicitly
   but didn't call out: the first pass only collapses the *inner* cast,
   exposing the *outer* one as a newly-bare `(cast i8 48)` textually
   matching the target pattern on a second look — caught by re-grepping the
   whole tree after the sweep, not assumed clean from a single pass.

An incidental accident during this session: a stray `rm -f scratch.nuc`
(bundled into an unrelated cleanup command) deleted an **untracked** scratch
file that predated this session and was unrelated to the sweep; it is not
recoverable via git (never staged). Flagged here for the record, not a
sweep-methodology issue.

**Status: lib/ batch 2 (macro-free files) DONE (2026-07-15).** Swept the 12
`lib/` files containing **no `defmacro` forms** (deliberately excluded to
avoid the quasiquote string-pool refresh complication) with the same
per-file `perl -pi -e 's/\(cast (i8|i16|i32|i64|ui8|ui16|ui32|ui64|usize|
ssize) (-?[0-9]+)\)/$2/g'` sweep, `make clean && make && make test` after
each file (174/174 throughout — a full clean rebuild, not incremental
`make`, was required: `Makefile`'s `COMPILER_DEPS` list only tracks a
curated subset of `lib/` files for `build/nucleusc`'s rebuild trigger, and
is missing `lib/vector.nuc`, `lib/hash.nuc`, `lib/hashset.nuc`,
`lib/hashmap.nuc`, `lib/iterator.nuc`, `lib/list.nuc` — all six are
transitively imported into the compiler's own compilation, so an
incremental `make` after editing any of them silently reused a stale
binary; only a forced clean rebuild caught the one real regression below
and produced a trustworthy diff). Final per-file counts (re-grepped at
sweep start — see the file list below for why these differ from the
originally-scoped estimate):

| File | Removed | Kept (special-cased) |
|---|---:|---:|
| lib/char.nuc | 76 | 0 |
| lib/hashmap.nuc | 69 | 0 |
| lib/hashset.nuc | 61 | 0 |
| lib/reader.nuc | 54 | 0 |
| lib/strview.nuc | 39 | 0 |
| lib/vector.nuc | 25 | 1 |
| lib/string.nuc | 18 | 0 |
| lib/node.nuc | 7 | 0 |
| lib/keyword.nuc | 5 | 0 |
| lib/hash.nuc | 3 | 0 |
| lib/iterator.nuc | 1 | 0 |
| lib/list.nuc | 1 | 0 |
| **Total** | **359** | **1** |

(Counts at sweep start were lower than the batch's original scoping scan
for `char.nuc`/`reader.nuc`/`strview.nuc`/`string.nuc` — expected drift
between scoping and execution, not a discrepancy; re-grepped per-file
immediately before editing, per the batch's own instructions.)

**Verification:** `make bootstrap` holds the byte-identical fixed point
(stage1.ll == stage2.ll); `make test` 174/174 after every file; the strong
check — a full `build/nucleusc.ll` diff against a pre-sweep snapshot — is
**exactly zero** after the one special-cased site below. One site hit the
same class-1 failure src/ batch 1 documented (a bare literal branch of a
value-position `if` joined against a differently-typed non-literal
sibling branch defeats the static type model): `lib/vector.nuc`'s
`vector-grow` computed `new-cap:usize` from `(if (= (_get v cap) 0) 4 (*
(_get v cap) 2))` — the `4` branch's naive `i32` node-type couldn't join
against the `(* (_get v cap) 2)` branch's `usize` node-type, so the
`let`'s declared-type check for `new-cap` died (`let: init type mismatch
for 'new-cap'`) the moment a real clean rebuild exercised the change (the
first clean-rebuild attempt in this batch surfaced it; earlier
same-session incremental `make` runs had masked it per the `COMPILER_DEPS`
gap above). Fixed by restoring just that one cast (`(cast usize 4)`); the
sibling `2` literal in the same expression needed no cast (its branch's
node-type is read from the multiplication's first operand, which is
already `usize`). Re-verified zero-diff after the fix.

**Status: lib/ defmacro-containing files DONE (2026-07-15).** Swept the 6
files excluded from batch 2: `lib/arena.nuc`, `lib/combinators.nuc`,
`lib/error.nuc`, `lib/macros.nuc`, `lib/parse.nuc`, `lib/string-split.nuc`.
Same per-file `perl -pi -e` sweep, verified per group with `make clean &&
make && make test` (174/174 throughout).

| File | Removed | Kept |
|---|---:|---:|
| lib/parse.nuc | 22 | 0 |
| lib/string-split.nuc | 10 | 0 |
| lib/arena.nuc | 7 | 0 |
| lib/combinators.nuc | 4 | 0 |
| lib/macros.nuc | 4 | 0 |
| lib/error.nuc | 1 | 0 |
| **Total** | **48** | **0** |

**The "quasiquote string-pool refresh complication"** that excluded these
files from batch 2 turned out to be real but narrow, and confined to
exactly one file: `lib/macros.nuc`'s four sites (`doseq`, `doseq-iter`,
`into`, `into-iter`) are not ordinary function bodies — they are the literal
`` `(cast i32 0)` `` inside each macro's own quasiquote *expansion template*
(the done-flag init `(let ((~done-sym i32) (cast i32 0)) ...)`). Removing
one of these changes what code the macro emits at **every** call site
tree-wide (these four macros are used throughout src/, lib/, and examples/),
not just locally to the file — a materially larger blast radius than the
other 47 sites, which all sit in ordinary function bodies. Investigated by
snapshotting `build/nucleusc.ll` before the `lib/macros.nuc` edit and diffing
after: the change was a clean, fully-explained removal of exactly 8 rodata
constants (`@.str.N = ... c"cast\00"` ×4, `c"i32\00"` ×4 — one pair per
macro, the string literals the quasiquote-building code no longer references
to construct a `cast`/`i32` node) with **zero** other IR change — no SSA
renumbering, no function-body differences. `make bootstrap` held the
byte-identical fixed point on the **first** attempt; no `update-bootstrap`
reconverge was needed (the string-pool shift was real but self-contained,
not the kind that cascades into a divergent fixed point). All 6 files: no
sites required restoring — every cast in this batch was genuinely vestigial.

**Status: examples/ DONE (2026-07-15).** Swept all `.nuc` files under
`examples/` with cast-on-literal sites (34 files, re-grepped at sweep start:
231 sites — the doc's original ~222 estimate, expected drift). Grouped 5-6
files per pass; verified with `make test` after each group (`examples/` is
not part of `$(BIN)`'s dependency list, so no `make clean && make` was
needed between groups — only the six lib/ files above required full
rebuilds). One file, `examples/types.nuc`, was excluded from the sweep
entirely: its sole site, `(cast i8 200)`, is LW-4's own documented
narrowing-escape-hatch demo (200 doesn't fit signed i8; removing the cast
would now be a compile-time range error, not a vestigial no-op) — confirmed
by a pre-sweep scan of every `(cast TYPE N)` site in scope against its
target type's representable range, which found this as the only
out-of-range site tree-wide.

| File | Removed | Kept |
|---|---:|---:|
| char-utf8-test.nuc | 40 | 0 |
| strview-read-test.nuc | 20 | 0 |
| handlers.nuc | 19 | 0 |
| allocator-test.nuc | 13 | 0 |
| errors.nuc | 13 | 0 |
| comb-shapes.nuc | 11 | 0 |
| value-maybe.nuc | 11 | 0 |
| errptr.nuc | 10 | 0 |
| iterator-test.nuc | 9 | 1 |
| split-iter-test.nuc | 7 | 2 |
| implicit-return.nuc | 5 | 1 |
| listiter-test.nuc | 4 | 1 |
| cond-value.nuc | 4 | 0 |
| cstr-fold-test.nuc | 3 | 1 |
| defn-newstyle.nuc | 4 | 0 |
| signal.nuc | 5 | 1 |
| string-protocols-test.nuc | 4 | 0 |
| vector-lit-test.nuc | 4 | 0 |
| string-test.nuc | 6 | 0 |
| unions.nuc | 6 | 0 |
| vector-test.nuc | 6 | 0 |
| unsafe-spellings.nuc | 2 | 1 |
| string-split-test.nuc | 2 | 0 |
| assoc-iter-return.nuc | 1 | 0 |
| assoc-types.nuc | 1 | 0 |
| callable.nuc | 1 | 0 |
| constructors.nuc | 1 | 0 |
| implicit-cast.nuc | 1 | 0 |
| list.nuc | 1 | 0 |
| parametric.nuc | 3 | 0 |
| phantom-tyvar-test.nuc | 3 | 0 |
| rest-defn.nuc | 0 | 1 |
| unsigned.nuc | 1 | 0 |
| types.nuc (excluded, see above) | 0 | 1 |
| **Total** | **221** | **10** |

**Verification:** every example with a `tests/expected/*.out` fixture (32 of
34) was covered by `make test`; the one without a fixture
(`examples/comb-shapes.nuc`) was checked by direct compile+run. After the
full sweep, every `examples/*.nuc` file (not just the swept ones) was
compiled directly with `build/nucleusc` as a blast-radius check: all compile
cleanly except two **pre-existing, unrelated** failures confirmed
independent of this sweep — `comb-shapes.nuc` (a documented HEAD
compile-time-JIT failure from the S3 defn-signature migration, `design/
progress.md` line ~502, reproduced identically with the untouched OLD boot
compiling the untouched original file) and `thread-macros.nuc` (a library-
style file with no `main`, fails to *link*, not compile — untouched by this
sweep, no fixture). `make bootstrap` holds the byte-identical fixed point
throughout (examples/ isn't part of the compiler's own build, so this was
never at risk, but was re-checked at the end regardless).

**Ten sites were restored**, surfacing two failure classes beyond the one
src/ batch 1 and lib/ batch 2 already documented (the "first operand's type"
binop mistype and the if-branch join mistype) — both are the **same root
cause** (a value-position join or a binop's static type trusting a bare
literal's naive `i32` over a wider, non-literal sibling) manifesting through
chokepoints the earlier batches hadn't exercised:

1. **`match` arms join the same way `if`/`cond` branches do** (confirmed:
   `type-join` is the single shared site, per conventions.md — this is not
   a new mechanism, just a manifestation the earlier batches didn't hit).
   `examples/signal.nuc`'s `grow` matched `(signal ...)` (a built-in
   returning `(Maybe i64)`) with arms `((some sz) sz)` and `(none 0)`; the
   bare `0` in the `none` arm mistyped the whole match as `i32` while the
   `some` arm (bound from a real `i64`) was correctly typed — silently
   wrong output (`granted: 0` instead of `16`) rather than a compile error,
   because the fallback-path value (0) happens to be numerically identical
   whether truncated or not, masking the bug in 3 of the 4 printed lines.
   Only the one branch caught by a differing runtime value (`granted`)
   exposed it. Bisected by restoring one candidate cast at a time (a nearby
   `(* (deref ...) 2)` looked equally suspicious but was **not** the cause —
   `_*`'s first operand is the typed `deref` value, so the "first operand's
   type" rule types it correctly as `i64`; restoring only the `(none (cast
   i64 0))` site fixed the output, confirming the match-arm join, not the
   multiply, was the actual defect). Fix: restored just that one cast.
2. **A protocol/generic-function constraint check doesn't consult tier-2
   widening adaptation at all** — a distinct chokepoint from LW-1/LW-2's
   fix, which scoped specifically to template-tier *method* resolution
   (`generic-resolve-adapt-tier`), not standalone `&where`-constrained
   *functions* like `reduce ((f (ref F)) (acc Acc) (it (ref I)) &where
   ((FoldFn Acc T) F) ...)`. Calling `reduce` with a bare-literal
   accumulator against a conformance whose `Acc` is `i64` (e.g. `(extend
   ByteSum (FoldFn i64 ui8))`) now dies at compile time: `constraint
   'FoldFn' parameter mismatch: expected i32, found i64` — the checker
   compares the literal's naive `i32` against the conformance's declared
   `i64` and rejects instead of adapting. Hit in five call sites across four
   files (`examples/cstr-fold-test.nuc`, `iterator-test.nuc`,
   `listiter-test.nuc`, `rest-defn.nuc`, `split-iter-test.nuc` ×2) — every
   `reduce` call in the tree whose `FoldFn` conformance uses `Acc=i64` and
   whose accumulator argument was a literal that fits `i32` (a literal
   already outside `i32`'s range, like `lib/strview.nuc:107`'s FNV basis
   constant, is unaffected — it emits truthfully at `i64` per LW-4 with no
   ambiguity to adapt). Fix: restored the accumulator's cast at each site;
   the underlying gap (teach the constraint checker the same tier-2
   adaptation LW-1/LW-2 gave method resolution) is a further LW-6-shaped
   follow-up, out of scope for this mechanical sweep.

Both classes were flagged here as LW-6-shaped follow-ups — see LW-6 below,
which fixes both.

**Grand total across all LW-5 batches:** 924 vestigial `(cast TYPE N)` forms
removed (test/doc slice's fixture additions aside), 59 kept as deliberate
narrowing casts or genuine gap workarounds — close to the doc's original
~991 estimate (counts drifted between scoping and execution throughout, as
expected and noted per-batch). The tree-wide sweep is complete; remaining
`(cast TYPE N)` sites are either legitimate narrowing (out-of-range
literals) or mark one of the two failure classes LW-6 below fixes.

### LW-6 — close the type-join and `&where`-constraint literal-widening gaps

**Status: DONE (2026-07-15).** Both failure classes LW-5 surfaced (§3.5
above) are root-caused and fixed, not just worked around with restored
casts.

**Class 1 — `type-join` (src/generics.nuc) collapses any two differently-
kinded types to `void`, not just structurally incompatible ones.** Ground
truth: `type-join` is called from `emit-cond`, `emit-match-clauses` (`match`
over tagged unions, including `defenum` via delegation), and
`emit-niche-match-arm` (niche `Maybe`/`Result` match, and transitively
`if-some`/`when-some`/`unwrap-or`'s non-niche path via their own `cond`/
union-eliminator lowering). None of the three sites' surrounding code
distinguished "two genuinely incompatible types" (a real error) from "a bare
int literal vs. a differently-widthed typed sibling" (should widen, exactly
like `binop-coerce` already does for `+`/`-`/`*`) — both collapsed to `void`,
silently discarding the phi (`(alloc-val ty-void null)`, no LLVM `phi`
emitted at all). Traced via `examples/signal.nuc`'s `(match (signal ...)
((some sz) sz) (none 0))`: `type-join(i64, i32)` (the `some` arm's real i64
vs. the `none` arm's naive-i32 literal) hit the `void` fallback, and the
enclosing `grow`'s return coercion silently treated the resulting null-`val`
Val as `0` — masked in 3 of 4 test lines because the fallback value
genuinely is `0`, exposed only where a real payload (`16`) was expected.
`lib/vector.nuc`'s `vector-grow` (LW-5 batch 2's restored `(cast usize 4)`)
is the same bug through `emit-cond` (an `if`, which `type-join`s just the
same) — there it surfaced as a compile-time `let: init type mismatch`
instead, since the joined value flowed into a declared-type check rather
than a return.

Fix: `type-join` gained two new `i32` params, `result-lit`/`bty-lit` (whether
the `Val` that produced each side was `Val.is-lit`, LW-4's literal tag).
When both sides are `is-int-type` and not `type-eq`: exactly one side
literal → adopt the other (typed) side's type, no coercion instruction
needed (a literal's emitted operand is a bare decimal constant, valid LLVM
IR at any integer width — only the phi's declared type changes); both sides
literal → adopt the wider kind; neither literal (two genuinely different
*typed* values) → unchanged, still collapses to `void` (int-widening.md §3's
non-goal: no implicit widening between typed values stands). The three call
sites (`emit-cond`, `emit-match-clauses`, `emit-niche-match-arm`) each thread
a running `result-lit` local (`emit-niche-match-arm`'s is a `ltbox` — an
out-param box, since its two arms are separate function calls, mirroring the
existing `rtbox`/`ttbox` pattern) computed as `result-lit AND this-arm-lit`
after every join — true only while every branch folded in so far was itself
a literal. Verified: `examples/signal.nuc`'s `(none 0)` and `lib/vector.nuc`'s
`(if (= cap 0) 4 (* cap 2))` both compile castless with correct output
(the `vector.nuc` fix needed the standard two-stage bootstrap dance —
`make update-bootstrap` with the cast still in place so the OLD boot's own
un-fixed `type-join` could compile the fix, then remove the cast and
rebuild from the new boot — since the OLD boot's compiled-in `type-join` was
still the buggy one and died on the now-cast-free source under its own
old semantics, the same class of gcheck bootstrap gotcha conventions.md
documents).

**Class 2 — a `&where` constraint check doesn't consult tier-2 widening at
all.** Root cause is one step upstream of where the error message (`recover-
one-constraint`, generics.nuc) fires: `generic-method-bind`'s tier-1 exact
unification (`unify-tpat`) eagerly binds a bare-tyvar parameter (`reduce`'s
`acc:Acc`) from its argument's *naive* type — for a literal, that's `i32`
regardless of what the type should really be — before the `&where` clause's
associated-type recovery (`recover-assoc-into`) ever gets a chance to
determine the same tyvar from a real conformance (`(extend ByteSum (FoldFn
i64 ui8))`). By the time recovery runs, `Acc` is already (wrongly) bound to
`i32`, so recovery takes its "CONSTRAIN" path instead of "RECOVER" and dies
comparing the wrong-already-bound `i32` against the conformance's real
`i64` — `constraint 'FoldFn' parameter mismatch: expected i32, found i64`.
Fix: `generic-method-bind` gained an `arg-nodes` parameter (the call-site
argument nodes, threaded from every caller that has them —
`generic-resolve`'s tier-1 loop and `valid-resolve-type`; the two callers
with no real call site, `generic-binds-for`'s signature-only probe and
`abstract-call-via-generic`'s A2 body-check, pass `null`). Per argument, if
its param pattern is a bare, still-*unbound* declared tyvar (checked via the
same `tyvar-index-of` lookup `unify-tpat` itself uses) and
`node-is-int-literal` says the argument is a literal, the binding is
*deferred* — collected but not unified — until after `recover-assoc-into`
runs; only if the tyvar is *still* unbound post-recovery does the deferred
literal fall back to today's naive binding (the pre-fix behavior, unchanged
whenever there's no conformance to recover from). The "still unbound at
this point in the pass" check is required, not optional: an earlier
non-deferred argument in the *same* pass (e.g. `conj`'s receiver `(self (ref
(Vector T)))`, a compound pattern processed immediately, binding `T` before
the bare-tyvar `elem:T` argument is even considered) can already have bound
the tyvar — deferring unconditionally in that case silently skipped
`elem`'s unification entirely, letting tier-1 wrongly "succeed" and then
tier-2 (`generic-resolve-adapt-tier`) *also* independently stamp the same
template, producing `invalid redefinition of function 'conj.pVector.i64.i64'`
(caught by `make test` on the first attempt; fixed by adding the unbound
check before deferring). **Lockstep**: `node-type-call`'s own path to the
same constraint check (`generic-binds-for`, called with `line=0` — hence the
`file:0:` in the original error, a probe with no real call-site line) needed
the identical `arg-nodes` threading, or the *type-model* probe dies on the
exact same widened call before emission ever runs (`node-type-call` is
invoked as part of ordinary expression evaluation, not just diagnostics, so
this wasn't optional). Verified: all five `reduce` call sites LW-5 had to
cast (`cstr-fold-test.nuc`, `iterator-test.nuc`, `listiter-test.nuc`,
`rest-defn.nuc`, `split-iter-test.nuc` ×2) now compile with a bare literal
accumulator and produce byte-identical output to the cast version.

**Verification (both fixes together):** `make clean && make && make test`
174/174 after each edit; `make bootstrap` holds the byte-identical fixed
point (a real logic change, not the LW-5 sweep's mechanical no-op, so
byte-identity here means the compiler's own source doesn't exercise either
gap anywhere — true for both, confirmed by the fixed point holding without
needing `update-bootstrap` for the `type-join`/`generic-method-bind` source
edits themselves, only for the one downstream `lib/vector.nuc` cast
removal). A full compile-only pass over every `examples/*.nuc` file (the
LW-5 blast-radius check, re-run) found no new failures beyond the two
already-documented pre-existing ones (`comb-shapes.nuc`, `thread-macros.nuc`,
both unrelated to this work).

## 4. Verification and bootstrap convergence

LW-1/LW-2 land together and must hold the bootstrap fixed point (the
lockstep gate); the compiler source itself contains casts at the affected
sites, so IR is expected unchanged until LW-5 removes them —
`build/nucleusc.ll` before/after diff per phase, standard reconverging
refresh when the string pool shifts. LW-3 and LW-4's in-range behavior are
expected byte-identical on the tree (no bare wrong-width explicit returns
or out-of-range literals should exist — the audit is part of the phase).
`make test` + `make bootstrap` after each phase; LW-5 per-file IR-identity
diffs.

## 5. Alternatives considered and rejected

- **Literal suffixes (`5u64`) or `(i64 5)` constructor forms.** New syntax
  surface to solve a problem adaptation already solves; the survey found
  zero demand (`(cast T N)` is the universal spelling today, and it
  disappears with LW-1/LW-5).
- **Go-style untyped-constant literals** (literal stays typeless until a
  consumer types it). Structurally cleaner but a much larger type-system
  change threading expected types through every emit path; the existing
  probe-based adaptation plus LW-4's value-aware emission achieves the
  same user-visible result.
- **Preferring the narrowest candidate instead of erroring on widening
  ambiguity.** Silent resolution changes under overload-set growth; the
  explicit error is cheap since width-only overload sets don't exist.
- **Coercing mixed-sign variable binops.** C's usual-arithmetic-conversion
  wraparound bugs are the thing the current strictness deliberately
  rejects; literals already adapt, so the ergonomic cost is low.

## 6. Sequencing and relationship to other stage-14 work

Touches generic resolution (src/generics.nuc) and the call/return emit
paths — none of the surfaces the CP (done)/MC/S/T backbone edits, and none
of the target plumbing the AVR/RISC-V track edits. Constraints: LW-1+LW-2
atomic; the LW-5 sweep is tree-wide, so keep it out of defn-signature S3's
quiet-tree window (and run it per-file regardless). Landing LW-1 before
type-safety 14.3 is mildly preferable: 14.3 retypes elem-less `:ptr`
signatures and its adjacent int params to `usize`/typed forms, and every
such retyping today would mint new cast-on-literal sites at stamped call
sites. Order within this work: **LW-1+LW-2 → LW-3 → LW-4 → LW-5**, gates
after each.
