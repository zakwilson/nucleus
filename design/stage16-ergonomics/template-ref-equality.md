# Same kind is not same type: closing the template-ref equality hole

`(ref (Vector i32))` binds to a `(ref (Vector i64))` slot, passes as that
parameter, and is stored into that field, with no error anywhere. Filed as
[collection-literal-variables.md](collection-literal-variables.md) §6.1 and
deferred there to its own document; this is it.

**Status: done, 2026-08-29.** Landed as two items, SE-1 (the rule) and SE-2 (the
defect SE-1 exposed). 912 tests (was 908), boot refreshed, 185/187 modules of the
IR sweep byte-identical.

**Conclusion up front: it is D3's chokepoint, and the fix is one call inserted at
the line FP-1 already wrote around.** `fn-slot-type-compat` was never
fn-specific — it recurses through pointers and ends at `type-eq`, which is
exactly the general slot rule — and FP-1 reached it only for `TY-FN` pairs. What
made this item real work is not the rule but its **blast radius**: 61 sites, 60
of them one idiom in the compiler's own source, and all 60 are one *second*
defect that the tightening turns from silent into fatal.

---

## 1. The defect, measured

```lisp
(import-use vector)
(defn takes ((v (ref (Vector i64)))):i64 (return (invoke v 0)))
(defn main ():i32
  (with ((a (ref (Vector i32))) [1 2 3])
    (printf "%lld\n" (takes a)))
  (return 0))
```

```
8589934593
```

`0x2_00000001` — elements 1 and 2 read back as one `i64`. It compiled clean, and
`let`, `set!` and a `.set!` field store accepted the same pair.

**It is not about templates.** Two hand-written structs are the identical
defect:

```lisp
(defstruct A (x i32))
(defstruct B (y i64) (z i64))
(defn takes (b:(ref B)):i64 (return (b y)))
…
  (let (a:(ref A) (unsafe/cast (ref A) (malloc 16)))
    (.set! a x 7)
    (let (p:(ref B) a)            ; accepted
      (printf "%lld\n" (takes a)) ; accepted
      (printf "%lld\n" (p y))))
```

prints `7` twice. §6.1 found it through a stamped instance because that is where
two same-shaped pointers with different pointees arise without anyone writing a
cast; the hole itself is *every* typed pointer slot.

**`as` has refused this the whole time.** `as-convert` routes a pointer pair to
`as-ptr-convert`, which compares pointees and dies `as: reinterpretation from …
to … -- use unsafe/cast`. So the implicit path was *looser* than the explicit
one — the exact inversion conventions.md's "an explicit conversion form must
never reject what the implicit one accepts" exists to prevent, running in the
direction nobody checks.

### 1.1 Which kinds are silent, and which are merely ugly

The short-circuit is on `kind`, so it waves through every same-kind pair — but
only the pointer-shaped ones are *silent*:

| pair | before | why |
|---|---|---|
| `TY-PTR`/`TY-PTR` | silent wrong value | every pointer lowers to `ptr`; LLVM sees nothing |
| `TY-FN`/`TY-FN` | closed by FP-1 | same reason; c-boundary-defects.md §2.3 |
| `TY-STRUCT`/`TY-STRUCT` | LLVM verifier error | named struct types are nominal in textual IR |
| `TY-ARRAY`, `TY-UNION` | LLVM verifier error | same |
| `TY-ERR` and the scalars | not a hole | `type-eq` already answers for them |

Measured for the struct row, from the by-value sibling of the same constructor
collision §5 is about:

```
nucleusc: failed to parse generated IR: …:979:21: error: '%t8' defined with type
'%Vector.i32 = type { ptr, i64, i64, %AllocHandle }' but expected
'%Vector.i64 = type { ptr, i64, i64, %AllocHandle }'
  store %Vector.i64 %t8, ptr %b.addr.5, align 8
```

That is a real refusal, at a line number in a file the user did not write. So
the aggregate kinds were never a *miscompile*; they were a diagnostic outsourced
to LLVM. Both get the same rule, for the same reason FP-3 gave the fn-pointer
message a `type-display`: the compiler should say it.

## 2. Is it D3's chokepoint? Yes — the same line, one arm lower

`coerce-int-val` (`src/abi.nuc`) is the single implicit-coercion chokepoint for
every typed slot; `safe-coerce-val` (`src/nucleusc.nuc`) is the argument
position's entry to it. Both carry the same short-circuit:

```lisp
; Same kind — identity
(when (= sk dk) (return v))
```

FP-1 inserted `fn-sig-compat` *immediately above* that line in both functions,
because "two function pointers are the same KIND and are not thereby the same
type". The sentence is true with `pointer` substituted for `function pointer`,
and the line was left standing for it. The right answer was even being computed
at the call site and thrown away in the same way D3 describes: `coerce-call-argument`
consults `type-eq` first and only calls `safe-coerce-val` when it answers 0 — so
every arrival at that short-circuit is already a known mismatch.

**One correction to the shared-cause claim, and it is not a small one.** There is
a *third* site, and it is not a coercion path at all: `defvar-addr-of-ir`
(`src/nucleusc.nuc`), the constant renderer's `(addr-of g)` fold. A global
initializer is a constant and cannot be built by emitting instructions, so it
re-derives the typed-slot rules by hand — conventions.md's "a SECOND
value-into-a-typed-slot path", now on its sixth bite. It checked `pkind` and
never the pointee, so `(defvar p:(ref B) (addr-of a))` on an `A` global was
silently a reinterpretation. Fixed here, by the same *call*.

## 3. Blast radius — measured, not estimated

Method: the intended predicate was installed at both short-circuits as a
**probe** — report to stderr, then accept exactly as before — and the tree was
compiled with it. So the number below is the set of sites that rely on the
laxness, not the set that would break for any reason.

| corpus | sites |
|---|---|
| `src/` (self-compilation) | **60** |
| `lib/` (34 modules) | **0** |
| `examples/` (153 modules) | **1** |

Every one of the 60 is `TY-PTR`/`TY-PTR`, and every one is the same call:

```
ptr:Vector.i32 -> ptr:Vector.pCleanup     (src/scope.nuc:22)
ptr:Vector.i32 -> ptr:Vector.pField       (src/abi.nuc:229)
ptr:Vector.i32 -> ptr:Vector.pGeneric     (src/generics.nuc:236)
…40 distinct element types, 59 × (vector-new-in …) + 1 defvar initializer
```

The one in `examples/` is unrelated and is a genuine mistake the laxness hid:
`examples/colon-paren-types.nuc:70` declares a lambda `:ptr:(ptr i32)` and
returns `(unsafe/cast (ptr i32) null)` — one indirection short. Corrected to
`(unsafe/cast ptr:(ptr i32) null)`, which is IR-neutral (a `null` constant either
way) and is what the surrounding comment says the line demonstrates.

## 4. SE-1 — the rule

`fn-slot-type-compat` is renamed **`slot-type-compat`** (`src/abi.nuc`) and the
identity return in both chokepoints is guarded by it:

```lisp
(when (= sk dk)
  (if (!= (slot-type-compat src target) 0) (return v) (return null)))
```

No body changed. The function already was the general rule; FP-1 just never
asked it a non-`TY-FN` question. A null return is what every typed slot already
turns into its own diagnostic, so all four positions report in their own words
and name both types:

```
let: init type mismatch for 'b': value is ptr:Vector.i32, slot is ptr:Vector.i64
set!: type mismatch for 'b': value is ptr:Vector.i32, slot is ptr:Vector.i64
.set!: type mismatch for field 'p': value is ptr:FA, field is ptr:FB
takes: argument 1 has type ptr:Vector.i32, which does not match parameter type ptr:Vector.i64
return type mismatch — returned value of type ptr:Vector.i32 does not match declared return type ptr:Vector.i64
defvar: addr-of: 'ga' has type ptr:SA, which does not match ptr:SB
```

**What counts as the same type**, i.e. what `slot-type-compat` accepts, all of it
pre-existing and all of it load-bearing:

- **Identity** — `type-eq`: same `StructDef` for a struct or union, same pointee
  for a pointer, same length *and* element for an array, and `fn-sig-eq` for a
  function pointer.
- **The `void *` rule** — an elem-less bare `ptr` matches any pointer-like in
  either direction. This is what keeps the ~1550 bare `:ptr` bindings in this
  compiler's own source compiling, and it is why the check was safe to add to
  the constant renderer too.
- **Pointer kind is not part of the question** — `ptr` / `(ref T)` / `(raw T)` /
  `?T` compare by pointee. `pkind-flow-check` owns the nullability contract and
  runs *before* this line, unchanged.
- **The `TY-FN` relaxations** stay above it: `fn-sig-compat` is looser than
  `fn-sig-eq` in exactly the two ways C is (FP-1), and that arm is untouched.

Deliberately still allowed to convert, unchanged: `CStr`↔`ptr` (free, no IR),
`StrView`'s borrows, `null` into a `(fn …)` slot, int↔int and float↔float, the
`ptr`→by-value-struct load, and any registered `defcast`. Every one of those is a
*different* source and destination kind and so never reached the short-circuit.

## 5. SE-2 — the defect SE-1 exposed

All 60 `src/` sites are one root cause, and it is not in the coercion path.

`vector-new-in` is `(defn vector-new-in ((a (ref AllocHandle))) (ref (Vector T)) …)`:
its type variable appears **only in the return type**. Two things are keyed on
the parameter types alone, and neither is a key any more once `T` can vary:

- `generic-find-method-exact` — the memo probe `generic-instantiate-in` opens
  with, and the tier-0 answer `generic-resolve` and `node-type-call` give.
- `mangle-fn-name` — `@vector_new_in.pAllocHandle`, with no room for `T`.

So the compiler contained exactly **one** `vector-new-in`, stamped by whichever
call site got there first — `build-deferror-sids` (`src/nucleusc.nuc:1024`),
which spells `(unsafe/cast (ref (Vector i32)) …)` — and every one of the other 59
sites was handed that `(Vector i32)` instance regardless of what it asked for.
This is conventions.md's "a key stops being a key the moment the thing it
identified is allowed to vary", one registry further along.

Three things are worth recording about it.

**It was benign, by layout accident only.** `(Vector T)` has no `T`-typed
field — `data` is `(raw ui8)`, `len`/`cap` are `usize`, `alloc` is an
`AllocHandle` — so `(sizeof (Vector T))` is `T`-independent and
`vector-init-alloc` writes nothing that depends on `T`. Add one inline
`T`-typed slot to `Vector` (a small-buffer optimisation, say) and all 59 sites
allocate the `i32`-sized struct. The sibling constructor `vector-new-capacity`
is *not* benign for the same collision — it reserves `n × sizeof T` from the
stamped `T` — and is caught only because it returns by value and so trips the
LLVM verifier (§1.1).

**G-5's note on this is now stale and is superseded here.** `emit-as`'s comment
says `scope-new` "read correctly for the compiler's whole life only because that
call site *was* the first `vector-new-in` emitted". Measured on this tree: it was
not first, `build-deferror-sids` was, and `scope-new` had been taking a
`(Vector i32)`. Arming `as`'s want (G-5) was right and necessary, and it could
not fix this: the want decides the *binding*, and the memo probe runs before the
binding is ever consulted.

**The fix is a three-part split, not a new name scheme.** The discriminator is
the **bound return type**, applied only when the template has a tyvar the
parameters do not determine (`method-undetermined-tyvar`), so every other
template keeps its symbol and its memo untouched:

- `generic-instantiate-in` computes `disc` before the probe and keys the memo on
  `(argtypes, disc)` via `generic-find-want-stamp`; the stamp's symbol gains
  `.$r.<token>` (`$` is legal in an LLVM identifier and `type-mangle-token`
  never emits one, so it cannot be read as a parameter token).
- `generic-find-method-exact` (the **reference** side, and the tier-0 loop in
  `generic-resolve`, which is that function written out) **skips** such stamps:
  the argument tuple does not identify one, so the caller must fall through to
  tier 1 and re-bind from the want. That one change reaches `node-type-call` too,
  which is the `node-type`↔`emit-node` lockstep half.
- `defn-ir-name` gains a `ret` parameter, because it is the **definition** side —
  it names the definition in front of the emitter, and for a want-stamped
  instance that is the sibling whose return type matches. Same shape as W9 item
  35's `generic-find-method-exact-in-ns` split, one field further.

A discriminated stamp is marked `ir-fixed`, which says "this symbol is already
decided" — true of it for the same reason it is true of an imported method.
Without it `finalize-generics` re-mangles from the parameter types (dropping the
`.$r.`) and reads the siblings as duplicate definitions of one signature.

### 5.1 Two things SE-2 turned up on the way

**`method-undetermined-tyvar` was a params-only approximation of a fixpoint that
exists ten lines away.** The full A1 determination — seed from parameter
patterns, then propagate through each `:where` constraint whose conforming
variable is already determined — was computed inline in the template
registration and *never read*: the array was built and the `let` body was a
comment. That was harmless while the question had one consumer that only fires
after a bind has already failed. SE-2 gave it a consumer that decides a symbol,
and the approximation immediately called `reduce`'s `S` (recovered from
`((Iterator S) I)`) return-only and renamed every `reduce` stamp in the corpus.
The fixpoint is now `tyvars-determined`, called by `method-undetermined-tyvar`;
the dead copy is gone. Generalize as: **a computation with no reader is not
"advisory", it is unverified** — and the first real reader will find out how.

**`pattern-determines-tyvar` did not expand parametric type aliases, though it
claims to mirror `unify-tpat`, which does.** `(deftype (Vec T) (ref (Vector T)))`
plus `(defn first-of (v:(Vec T)):T …)` reads as having an undetermined `T`.
`collect-pattern-tyvars` and `unify-tpat` both expand first (§3.7); this third
copy did not, and nothing had ever asked it a question where the difference
showed. Fixed, which took the corpus diff from three modules to two.

## 6. What this does *not* do

- **`!T` error unions are not tightened.** `type-eq` has no `TY-ERR` arm, so its
  default answers 1 and two different error unions still compare equal — meaning
  `slot-type-compat` cannot refuse them either. Not reachable in the corpus (zero
  probe hits) and a different question: `TY-ERR`'s identity is a payload plus an
  error set, and deciding what "same" means there is its own item.
- **No new pass, no new type-equality relation.** Everything here calls
  `type-eq` or `slot-type-compat`. If a future rule needs to distinguish two
  stamped instances more finely than "same `StructDef`", it belongs in `type-eq`,
  not in a second predicate beside it.
- **The 40 near-identical `vector_new_in` stamps are not deduplicated.** They
  cost the compiler's own IR +2020 lines (+1.15 %) and are all `weak_odr`, so the
  linker folds nothing but `--gc-sections` keeps them all. Two instances differ
  in the `vector_init_alloc.<T>` they call, so they are not textually identical
  in general and cannot be merged by inspection; an identical-body merge pass is
  a real optimisation and a separate one.
- **`unsafe/cast` is untouched.** It is the spelling for a deliberate
  reinterpretation and remains the escape hatch for every pair this now refuses.
- **The pointer laxness is not replaced by a subtyping rule.** There is no
  upcast, no variance, no "A is a prefix of B". Two pointees are the same type or
  they are not.

## 7. Staging

Two items, landed together because the first cannot self-compile without the
second:

- **SE-1** — `slot-type-compat`, the guard at both short-circuits, and the same
  call in `defvar-addr-of-ir`.
- **SE-2** — the stamp identity: memo, symbol, reference-side skip, definition-side
  `ret`, and the two corrections in §5.1.

There is no half-way point worth shipping. Guarding the chokepoint alone breaks
self-compilation at 60 sites; fixing the stamp identity alone changes 41 symbols
and closes nothing.

## 8. Verification

- `make test` — **912 PASS, 0 FAIL** (was 908; four new assertions below).
- `make bootstrap` — converges. The compiler's own IR moved (41 new stamp
  symbols), so `make update-bootstrap` was run and the new fixed point confirmed
  by a fresh `make bootstrap` afterwards.
- `make abi-test`, `make layout-test`, `make check-headers` (69 committed headers
  unchanged), `make avr-test` — all green.
- **IR sweep**, `examples/` + `lib/` = 187 modules, `--emit-llvm`, comparing
  `.ll` + stdout + stderr + exit code against the pre-change compiler:
  **185 byte-identical**. The two that differ are
  `examples/constructors.nuc` (10 hunks) and `examples/g5-arena-backed.nuc`
  (2 hunks), and **every hunk is a `.$r.<ret token>` rename** of a
  return-only-tyvar constructor stamp — `vector_new`, `vector_new_alloc`,
  `vector_new_in`, `hashmap_new`, `hashset_new`. No instruction, no type and no
  order changed anywhere in the corpus.
- **Header-mode sweep**, both modes over the same 187 modules
  (`--emit-nuch` + `--emit-cheader`, 374 outputs): **byte-identical**, exit codes
  included. A stamped instance is not exported, so header mode cannot see this
  change; the sweep says so rather than assuming it.

New assertions (`tests/run-tests.sh`, `run_s16_se_template_ref`):

- `s16-se1-template-ref-refused` — §6.1's shape refused at argument, `let` and
  `set!`, each diagnostic naming both types.
- `s16-se1-template-ref-runtime` — the corrected program prints `1`. The defect
  printed `8589934593` here, so the *value* is the assertion.
- `s16-se1-pointee-rule-general` — two plain structs are the same refusal; the
  bare-`ptr` wildcard and the pkind relaxation still compile; and the constant
  renderer refuses `(defvar p:(ref SB) (addr-of ga))` while still accepting
  `ptr` and `(ref SA)`.
- `s16-se2-want-stamped-instances` — two `vector-new-in` with different element
  types in one unit emit two `.$r.`-suffixed symbols and read back `5 7000000000`.

### Residual risk

The `$` in a stamp symbol is exercised on ELF (including the `.text.<sym>`
section names, which `s16-sections-per-definition` and `make avr-test` cover) and
is legal in an LLVM identifier on every object format, but no Windows or Mach-O
link of a program containing one has been run here. The Windows boot IRs were
regenerated and contain them.
