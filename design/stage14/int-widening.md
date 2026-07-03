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

Factor the emit-side resolution so `node-type-call` runs the same tiers —
ideally both callers share one resolver (with a non-dying variant for the
type-model context, which must return null rather than die on ambiguity).
LW-1 and LW-2 are **one change** for lockstep purposes; the bootstrap
fixed point is the enforcement gate.

### LW-3 — coerce explicit `return` (fixes Gap B)

`emit-return` runs `coerce-int-val` against the declared return type,
matching the implicit end-of-body path (7093). On failure: a *source-level*
error naming the function and types — never again the raw LLVM parse error.

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

### LW-5 — vestigial-cast sweep + docs

- Delete cast-on-literal forms across src/ (~319), lib/ (~450), examples/
  (~222): most are removable *today* (plain paths), the `usize` cluster in
  lib/ becomes removable after LW-1. Per-file, bisectable; since an
  explicit `(cast i64 0)` and the implicit coercion emit the same
  instruction, each file's removal is verifiable by **emitted-IR identity
  diff** (the CStr-migration technique). Casts remain valid — stragglers
  break nothing.
- New test: `examples/int-widening.nuc` — castless collections ops
  (`conj`/`(v i)`/HashMap), castless explicit returns, a big-literal
  runtime check printing `5000000000`; negative tests for the ambiguity
  error and the new range errors (compile-error fixtures, if the harness
  grows support; otherwise assert via `build.sh` stderr in the test
  script).
- docs/types.md: a "widening and literals" section stating the actual
  rules (literals adapt to any int where they fit; typed values widen
  same-sign; exact beats widened; ambiguity is an error). Fix the
  strview example's vestigial casts while touching it.

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
