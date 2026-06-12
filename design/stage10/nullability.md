# Stage 10 — Nullability & safe pointers

Give Nucleus non-null pointers and explicit, checked nullability, at zero
mandatory runtime cost and full C-ABI compatibility. See [safety.md](safety.md)
for the umbrella and resolved decisions.

## 1. Three pointer flavors on one IR type

Every flavor lowers to IR `ptr` and is ABI-identical to a C `T*`. The
distinctions are compile-time contracts only.

| Surface | Meaning | Deref | Null? | Role |
|---|---|---|---|---|
| `(ptr T)`, bare `ptr` | **raw** — unchecked, today's behavior | allowed (your problem) | yes | C boundary, `unsafe`-named code |
| `(ref T)` | **non-null** — a valid instance of `T` | always safe | no | the safe default to *opt into* |
| `(Maybe (ref T))`, `?T` | **nullable-checked** — may be none | **forbidden** until narrowed | yes (`null` = none) | explicit nullability |

The asymmetry is deliberate: `raw` deref is unchecked because you waived the
check; `ref` deref is safe because the type guarantees it; `Maybe` deref is a
compile error because you must narrow first. `(Maybe (ref T))` is **niche-encoded**
as the bare pointer with `null` meaning none — no discriminant, no space cost,
and it *is* a `T*` to C.

> **Scope.** Stage 10 covers nullability of **pointers** only (the niche-encoded
> case). `(Maybe T)` over a non-pointer payload needs a discriminant
> (`{has:i1, val:T}`) and is left to the future sum-types feature
> ([../stage999-future.md](../stage999-future.md)).

## 2. Representation

`Type` (src/nucleusc.nuc:67) already gives typed pointers a fresh node with
`elem` set (`parse-type-from-node`, :745–757); only bare `ptr` is the shared
`ty-ptr` singleton (:716). So a pointer **kind** can be added without disturbing
the singleton:

- add a tri-state field to `Type`, e.g. `pkind ∈ { PTR-RAW, PTR-REF, PTR-MAYBE }`
  (default `PTR-RAW` so every existing typed pointer keeps today's meaning);
- `(ref T)` → `TY-PTR` with `pkind = PTR-REF`, `elem = T`;
- `(Maybe (ref T))` / `?T` → `TY-PTR` with `pkind = PTR-MAYBE`, `elem = T`.

`type-to-ir` / `type-to-cheader` (src/nucleusc.nuc:520+) are unchanged — all
three emit `ptr` / `T*`. `type-size` is unchanged. The kind participates only in
type-checking (`coerce-int-val` at :657, deref/field rules, signatures).

## 3. Surface forms

Construction and the **only** sanctioned transitions out of `Maybe`:

| Form | Meaning |
|---|---|
| `(ref T)` | non-null pointer type |
| `?T` → `(Maybe (ref T))` | reader sugar for the nullable type |
| `none` | the null `(Maybe (ref T))` |
| `(some p)` | wrap a `(ref T)` as `(Maybe (ref T))` — no IR |
| `(if-some (x m) then else)` | if `m` is non-null, bind `x:(ref T)` in `then`; else `else` |
| `(when-some (x m) body…)` | one-armed `if-some` |
| `(unwrap m)` → `(ref T)` | trap (abort/`die`) if `m` is null; the one runtime branch, only where used |
| `(unwrap-or m default)` → `(ref T)` | `default:(ref T)` if `m` is null |
| `(as-ref raw)` → `(Maybe (ref T))` | launder a raw `(ptr T)` from C: null stays none |

`some`/`none`/`as-ref` are pure relabelings (no IR); `if-some`/`unwrap`/
`unwrap-or` lower to a single null-compare branch. Naming is a low-stakes default
(`ref` could be `ptr!`; `Maybe` could be `Option`/`opt`) — overridable by the
designer.

## 4. Flow narrowing — the compiler's own idioms *are* the mechanism

A `Maybe` value cannot be deref'd directly, but the existing guard idioms narrow
it to `(ref T)`. In `node-type`, track per-scope **narrowed facts**: inside a
region dominated by a successful non-null test, a `Maybe` binding reads as
`(ref T)`.

```
(let (m:?Node (as-ref (lookup k)))
  (when (= m null) (return -1))   ; null arm exits…
  (m kind))                       ; …so here m is narrowed to (ref Node): deref OK
```

```
(if-some (n m)                    ; explicit form, same effect
  (n kind)
  -1)
```

This is what makes the migration (§6) tractable: the compiler is full of
`(when (= x null) (return …))` / `(when (!= x null) …)` guards (e.g.
`scope-lookup`, `node-at` callers). Once such a binding is typed `?T`, those
guards keep working **unchanged** as narrowing points — no rewrite, only the
signature changes. Narrowing is intraprocedural; across function boundaries the
*declared* type carries nullability (§5).

## 5. Boundaries

- **Function signatures / struct fields** are where nullability is *declared*: a
  `(ref T)` parameter requires the caller to pass non-null; a `?T` parameter
  accepts none; likewise returns and fields. This is the contract the
  intraprocedural narrowing relies on.
- **C interop.** `include`/`import`ed C declarations keep raw `(ptr T)` returns
  and params (today's behavior, fully compatible). To enter the safe world,
  launder: `(if-some (p (as-ref (c_call))) …)` or `(unwrap (as-ref …))`. A direct
  `(cast (ref T) raw)` is the unchecked promise "I know this is valid" — allowed,
  but it is the audited boundary and belongs in `unsafe`-named code.
- **Allocators.** `malloc` and friends can fail, so a safe allocator wrapper
  returns `?(ref T)` (e.g. `new` could yield `(ref T)` only via an arena that
  aborts on exhaustion, or `?T` from a fallible `try-new`). Exact policy decided
  alongside the `Drop` work in [lifecycle.md](lifecycle.md).

## 6. Migration — opt-in `(ref T)`, flip later

Per the resolved decision (safety.md §3), `(ptr T)` is **unchanged** for the
whole transition; the bootstrap stays byte-identical until code is deliberately
converted.

| Phase | Content | Bootstrap |
|---|---|---|
| **N1** | Add `PTR-REF`/`PTR-MAYBE` kinds, the §3 forms, deref/assign checks, and §4 narrowing. `(ptr T)` raw as today. Checker engages only for `ref`/`Maybe`. | byte-identical |
| **N2** | Convert the compiler to `(ref T)` where pointers are known-non-null and `?T` where they're guarded; measure friction. Each converted function leans on its existing null-guards for narrowing. | byte-identical per-step |
| **(later)** | **The flip:** reinterpret `(ptr T)` as `(ref T)` and retire raw to an `unsafe`-named spelling (e.g. `(raw T)` / `unsafe:ptr`). Decided with N2 data — whether to flip the default or simply keep `ref` as the blessed form. | breaking; temporary shims per AGENTS.md |

The checks engage *only* on `ref`/`Maybe` types in N1/N2, so adoption is
strictly incremental: an unconverted file sees no new errors.

## 7. Type-check rules (N1)

- **Deref / field / index** (`deref`, `(p field)`, `get`/`aref` on a pointer):
  - `PTR-REF` → allowed, result typed normally.
  - `PTR-RAW` → allowed (unchecked, as today).
  - `PTR-MAYBE` → **error** *"value may be null; narrow with `if-some`/`unwrap`
    or guard before use"* — unless narrowed (§4).
- **Assignment / coercion** (`coerce-int-val`, `let`/`with`/`set!` init,
  argument passing, return):
  - `null` / `none` into `PTR-REF` → **error**.
  - `(ref T)` into `?T` slot → OK (implicit `some`, no IR).
  - `?T` into `(ref T)` slot → **error** (must `unwrap`/narrow).
  - `(ptr T)` raw into `(ref T)` → **error** without `cast`/`as-ref` (the C
    boundary is explicit).
  - `(ref T)` into `(ptr T)` raw → OK (widening to unchecked is always safe).
- **Elem compatibility** between `ref`/`Maybe`/`raw` of the same `T` follows the
  existing pointer rules; only the kind adds obligations.

## 8. Why this satisfies the three asks

1. *Explicit nullability* — `?T` / `(Maybe (ref T))`, with deref forbidden until
   narrowed.
2. *Safe pointers by default* — `(ref T)` guarantees a valid instance and is the
   form you opt into (and, after the flip, the default), manipulated only through
   checked facilities.
3. *Raw remains, as the edge case* — `(ptr T)` / bare `ptr` / `cast` keep working
   and become the thing you reach for at the C boundary and in `unsafe`-named
   code, not the default.

All three at zero runtime cost (one branch per explicit narrow) and zero ABI
change.

## 9. Implementation status (landed 2026-06-12)

N1 is fully implemented; `make test` and `make bootstrap` pass. N2 (converting
the compiler) has not started; the flip remains deferred.

- **Representation (§2)** — `pkind` (`PTR-RAW`/`PTR-REF`/`PTR-MAYBE`) on
  `Type`, default raw. Deliberately ignored by `type-eq`/`hash-type`/
  `type-mangle-token` (like `is-volatile`), so dispatch, monomorphization, and
  emitted IR are unaffected; shared `Type`s are never mutated
  (`type-as-pkind` clones, identity when the kind already matches). `?T`
  parses in `parse-type-name`; `(ref T)` / `(Maybe (ref T))` in
  `parse-type-from-node`; `(Maybe T)` over a non-pointer is rejected with a
  pointer to the future sum-types work.
- **Surface forms (§3)** — all seven. `none` is an elem-less Maybe singleton
  that coerces into any `?T` slot exactly as `null` coerces into `(ptr T)`;
  `some`/`as-ref` are pure relabels (no IR); `unwrap` is a null test +
  `llvm.trap` (declared lazily); `unwrap-or` evaluates its default only on the
  none path; `if-some`/`when-some` bind the Maybe and desugar to `cond`, so
  the synthesized `(!= x null)` test *is* the narrowing point and `cond`'s
  phi/typing/fall-through rules apply unchanged.
- **Narrowing (§4)** — per-`Sym` narrowed view (`ntype`) plus a global undo
  stack. Established by `cond` tests in both polarities (with `and`/`or`/`not`
  decomposition), failed-guard accumulation across later `cond` pairs and past
  the form when guard bodies terminate, the rhs of `and`/`or`, `while`
  conditions, and known-non-null `set!`/init. Killed by reassignment (sticky
  across joins via `kstamp`), by a loop-body prescan for textual `set!` (with
  an emit-time backstop for macro-synthesized assignments), and wholesale at
  `label`. Reads go through `sym-effective-type`, shared by codegen and
  `node-type`, so the two cannot drift.
- **Checks (§5, §7)** — deref/field/index/store gates on un-narrowed Maybe
  (`require-derefable`) at `deref`, `aref`/`aset!`, `ptr-set!`, `.`/`get`/
  `.set!`/`.&`; flow gates (`pkind-flow-check`) on assignment/init, call
  arguments, and explicit + implicit returns; widening always allowed;
  `(cast ref:T x)` is the audited assertion at the C boundary. `cond` joins
  meet kinds conservatively (raw over Maybe over ref).
- **N2 (§6)** — open. No compiler code converted yet; the checks engage only
  on `ref`/`Maybe` spellings, so unconverted code sees no new errors.

[examples/maybe.nuc](../../examples/maybe.nuc) exercises the full surface in
the test suite.
