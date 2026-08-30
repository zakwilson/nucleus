# Closing the C boundary: function pointers, struct values, wide floats, bitfields, packing, anonymous members

[cheader-parser-vs-libclang.md](cheader-parser-vs-libclang.md) §4.1 lists three
"frictions" a libclang binding would hit, and treats them as costs of *that*
binding. They are not. Two of the three are defects in the Nucleus language that
any C library with a callback or a by-value struct hits, and libclang is merely
the first caller loud enough to be counted. The third (§4.1 item 3, bare
`unsigned`) is already staged as C1/C2 and is restated here only for ordering.

Measuring them turned up **two live silent miscompiles** in the same area that
§4 did not see, because §4 measured the *hand-written* binding it built — which
used `unsafe/cast` and `unsafe/funcall-ptr-*` throughout, and so never exercised
the typed path at all. Both are demonstrated below with runnable programs.

**§§6–9 close the rest of the gap.** The four items the surrounding documents
defer — the missing float types, bitfields, `__attribute__((packed))`, and C11
anonymous members — are planned here too, on the standard that Nucleus should be
able to express anything C can. Two of them turned out to be substantially
smaller than their deferrals imply, one is a real but bounded piece of work, and
exactly two things in the whole set are *not* reachable and are named as such in
§10.

Everything here was measured on 2026-08-26 against `build/nucleusc` at `bd4bec1`,
glibc 2.41 / clang 19.1.7, x86_64, with clang as the oracle for every ABI and
layout claim.

---

## 1. The defects

| | defect | §4 name | evidence | status |
|---|---|---|---|---|
| **D1** | The C header importer erases function-pointer types in all four declarator positions | friction 1 | §2.1 | **done** (FP-4) |
| **D2** | `--emit-cheader` erases them too, and writes non-standard C | — | §2.2 | **done** (FP-5) |
| **D3** | Every typed function-pointer slot accepts a signature-mismatched function, silently | — | §2.3 | **done** (FP-1) |
| **D4** | An indirect call checks nothing, coerces nothing, and ABI-lowers nothing | — | §2.4 | **done** (FP-2) |
| **D5** | A struct *value* is not a legal member-access receiver | friction 2 | §2.5 | **done** (SV-1/SV-2) |
| **D6** | Bare `unsigned`/`signed` is not a type; the drop records no reason | friction 3 | = C1/C2 | **done** (C1/C2) |
| **D7** | `__fnty_N` — an internal registry key — is what diagnostics call a function pointer | — | §2.6 | **done** (FP-3) |
| **D8** | No `long double` / `_Float128` / `_Float16`; 156 declarations refused across the standard headers | — | §6 | **done** (FL-1…FL-7) |
| **D9** | No bitfields — the sole remaining blocker on `FILE` | — | §8 | **done** (FR-1, BF-1…BF-4) |
| **D10** | No `__attribute__((packed))`; `epoll_event` imports at 16 bytes where C says 12 | — | §7 | **done** (PK-1/PK-2/PK-3) |
| **D11** | No C11 anonymous members — but the layout half already exists | — | §9 | **done** (AN-1/AN-2, C1a) |

**Phases 1–4 landed 2026-08-26**, and **phase 5 (§6, the float widths) and
phase 6 (§7, packing) with them** — PK-3 on 2026-08-28. **Bitfields (§8, D9) and
anonymous members (§9, D11) landed 2026-08-28 too.** D1–D11 are all closed —
the 111-type census (§16.4) is the acceptance test for the last two. What each
change actually turned out to be, where it diverged from the plan above, and
what it is pinned by, is in §12 (phases 1–4), §13 (the floats), §14 (packing
and alignment), §15 (bitfields) and §16 (anonymous members).

D3 and D4 are the load-bearing discoveries. Nucleus has had a real
function-pointer type since Stage 6 and a signature-equality predicate
(`fn-sig-eq`, `src/generics.nuc:257`) since Stage 16. **Neither is consulted at
any assignment or any call.** So §4.1's complaint — that laundering a callback
through `(unsafe/cast ptr visit)` "loses all arity/type checking at the boundary"
— understates the problem in one direction and overstates it in the other: the
cast loses checking that was never performed, *and* the checking that is missing
is missing for hand-written Nucleus code too, cast or no cast.

---

## 2. Evidence

Method: each case below is a complete program compiled with `build/nucleusc`.
`probe.h` is a five-line header modelling the shapes; the glibc cases use the
real system headers.

### 2.1 D1 — the importer erases function-pointer types

`qsort` and `atexit` — the two most canonical callbacks in C — cannot be called
with a Nucleus function:

```lisp
(import-use "stdlib.h")
(defn cmpi (a:ptr b:ptr):i32 (return 0))
(defn main ():i32 (qsort a 10 4 cmpi) (return 0))
```
```
error: qsort: argument 4 has type __fnty_0, which does not match parameter type ptr
error: atexit: argument 1 has type __fnty_0, which does not match parameter type ptr
```

All four declarator positions collapse, each at its own site:

| position | site | what it does |
|---|---|---|
| parameter — `void (*f)(int)` | `src/cheader.nuc:787` | `c-skip-parens` twice, `(set! ptype ty-ptr)` |
| struct/union member | `src/cheader.nuc:1404` | same, plus it drops the field *name* (the C1 item) |
| typedef — `typedef int (*cb)(int);` | `src/cheader.nuc:1654` | `(set! base ty-ptr)` |
| return — `void (*signal(int, void(*)(int)))(int)` | not modelled | `signal` is skipped outright |

The typedef row matters most, because glibc names most callbacks through one:
`(import-use "…/probe.h")` with `int p_apply_td(pcmp f, int, int)` fails
identically to the inline spelling. `docs/structs-unions.md:101`'s claim that "a
function pointer *behind a typedef* is fine" holds only for whether the enclosing
struct stays representable — the *type* is `ptr` either way, so neither storing a
Nucleus function into such a field nor calling through it works:

```
error: .set!: type mismatch for field 'cb'
error: funcall: first arg must be a function pointer
```

The one place the importer builds a `TY-FN` is `src/cheader.nuc:885`, for the
declared function's own signature. Everything else is `ty-ptr`.

**This is not a type-system gap.** The identical declaration written by hand
type-checks, emits correctly, and needs no cast:

```lisp
(declare qsort2 ((base ptr) (n i64) (sz i64) (cmp (fn i32) (ptr ptr))) :void)
(defn cmpi (a:ptr b:ptr):i32 (return 0))
(defn main ():i32 (qsort2 null 0 4 cmpi) (return 0))
```
```llvm
declare void @qsort2(ptr, i64, i64, ptr)
  call void @qsort2(ptr null, i64 %t0, i64 %t1, ptr @cmpi)
```

The language can say it; the C reader cannot hear it. That is what makes D1 a
drop-in-replacement defect rather than a missing feature.

### 2.2 D2 — the export side erases them too, into non-standard C

`type-to-c` (`src/type-utils.nuc:404`) maps `TY-FN` to `"void*"`. So:

```lisp
(defstruct Hold (cb (fn i32) (i32 i32)) n:i32)
(defn use2 (f:(fn i32)(i32 i32)):i32 (return (funcall f 1 2)))
(defn getf ():(fn i32)(i32 i32) (return null))
```
```c
typedef struct Hold { void* cb; int32_t n; } Hold;
int32_t use2(void* f);
void* getf(void);
```

A C consumer gets no checking, and the header is not standard C: ISO C does not
define conversion between a function pointer and `void *` (only POSIX does, and
only for `dlsym`). A conforming compiler may diagnose every call site. The
correct rendering is `int32_t (*cb)(int32_t, int32_t);` and
`int32_t use2(int32_t (*f)(int32_t, int32_t));`.

### 2.3 D3 — every typed slot takes any signature

`safe-coerce-val` (`src/nucleusc.nuc:3591`) short-circuits at line **3605**:

```lisp
(when (= sk dk) (return v))
```

Both a `(fn i32)(i32 i32)` value and a `(fn i32)()` slot have kind `TY-FN`, so
the value is returned unchanged and no signature is ever compared. The call-site
check above it (`src/nucleusc.nuc:6549`) *does* call `type-eq`, which *does*
dispatch `TY-FN` to `fn-sig-eq` and correctly answers 0 — and then hands the
mismatch to `safe-coerce-val`, which accepts it. The right answer is computed and
discarded.

Demonstrated at all four typed slots — `let` init, `set!`, `.set!` field store,
call argument — with three kinds of mismatch (arity, return type, parameter
type). Two of them produce wrong values with no diagnostic:

```lisp
(defn one (a:i32):i32 (return (* a 10)))            ; one parameter
(defn getd ():f64 (return 2.5))                     ; f64 return
(defn use2 (f:(fn i32)(i32 i32)):i32 (return (funcall f 3 4)))
(defn used (g:(fn i32)()):i32 (return (funcall g)))
(defn main ():i32
  (printf "arity-mismatch = %d\n" (use2 one))
  (printf "ret-mismatch   = %d\n" (used getd))
  (return 0))
```
```
arity-mismatch = 30
ret-mismatch   = -1780842467
```

Both compile clean. The second reads an integer register that a `double`-
returning function never wrote.

### 2.4 D4 — an indirect call checks nothing and lowers nothing

`emit-funcall-value` (`src/nucleusc.nuc:6145`) is the single indirect-call
emitter — `funcall` and a `TY-FN` value in head position both fold to it. After
`check-call-arity` it **never looks at the function type's parameter list
again**. Each argument is printed as `type-to-ir (av type)`: no
`pkind-flow-check`, no `type-eq`, no `safe-coerce-val`, no `vararg-promote`, no
`abi-classify`.

Consequences, each demonstrated:

**(a) Wrong register class, silently.** A direct call refuses this; the indirect
call emits it.

```lisp
(defn addd (a:f64 b:f64):f64 (return (_+ a b)))
(let (f:(fn f64)(f64 f64) addd  i:i32 3)
  (printf "direct   = %f\n" (addd 3.0 4.0))
  (printf "indirect = %f\n" (funcall f i 4.0)))
```
```llvm
  %t3 = call double @addd(double 3.0, double 4.0)
  %t8 = call double %t6(i32 %t7, double 4.0)      ; vs define double @addd(double, double)
```
```
direct   = 7.000000
indirect = 4.000000
```
The direct spelling `(addd i 4.0)` is a compile error
(`argument 1 has type i32, which does not match parameter type f64`).

**(b) The Stage 8 struct ABI is bypassed entirely.** This is the one §4.1's
libclang binding would have hit first — `clang_visitChildren`'s callback takes
*two* by-value `CXCursor`s.

```lisp
(defstruct Pt x:i32 y:i32)
(defn take (v:Pt):i32 (let (p:ptr:Pt (addr-of v)) (return (+ (. p x) (* 100 (. p y))))))
(let (p:ptr:Pt (alloca Pt)  f:(fn i32)(Pt) take)
  (.set! p x 7) (.set! p y 9)
  (printf "direct   = %d\n" (take (deref p)))
  (printf "indirect = %d\n" (funcall f (deref p))))
```
```
direct   = 907
indirect = 7
```
```llvm
  %t4 = call i32 @take(i64 %t3)          ; direct: SysV-coerced, matches the define
  %t3 = call i32 %t0(%Pt %t2)            ; indirect: raw aggregate
```

Larger structs and returns fail the same way: `call i32 %t0(%Big %t2)` where the
define is `ptr byval(%Big) align 8`, and `call %Big %t3()` where the define is
`void (ptr sret(%Big) align 8)`.

**(c) It was already known, and worked around locally.** `src/union-emit.nuc:689`
carries the comment *"Must go through `abi-emit-struct-call` (not
`emit-funcall-value`): the handler defn returns `(Maybe T)` coerced per the
Stage-8 struct ABI, so the call site must coerce to match."* One call site routed
around the defect instead of fixing it — precisely the case AGENTS.md's
"fix the root cause" rule is written for. `abi-emit-struct-call`
(`src/abi.nuc:795`) is the helper the root fix should be built on.

**(d) The `BoxedFn` path is half-fixed.** `src/nucleusc.nuc:8429` *does*
`coerce-int-val` each argument against the slot's declared parameter type — so
(a) does not apply there — but it also prints raw `type-to-ir` per argument, so
(b) does. Two indirect-call emitters, two different subsets of the same rule.

### 2.5 D5 — a struct value is not a member-access receiver

`(. v x)`, head-position `(v x)`, `(_get v x)`, `(.set! v x 1)` and `(.& v x)`
all require a `TY-PTR` whose `elem` is `TY-STRUCT`/`TY-UNION`. A struct *value*
— a by-value parameter, a call result, a `let`-bound struct local — is refused:

```
error: _get: operand must be pointer to struct or union
error: callable value: not callable — no matching get/invoke method and not a pointer-to-struct
```

This is not C-specific: `(defn mine (v:Pt):i32 (return (. v x)))` fails for a
purely Nucleus struct, as does `(. (mk) x)` on a value-returning Nucleus
function. In C, `cursor.kind` on a value is the ordinary spelling, and libclang's
API is *entirely* by-value cursors.

The five sites are `emit-field-get` (`src/nucleusc.nuc:5322`),
`emit-get-intrinsic` (`:5477`), `emit-field-set` (`:6241`), `emit-field-addr`
(`:10101`), and their type-pass partners `node-type-field`
(`src/generics.nuc:4775`) and `callable-get-type` (`:4798`).

**A correction to §4.1 friction 2 while here.** The documented idiom
(`(let (q:ptr:CXCursor (alloca CXCursor)) (ptr-set! q cursor) (. q kind))`) is
one step longer than today's language requires: a `let`-bound struct local is
already an alloca, so `(let (v:PVec (p_make 3 4)) (. (addr-of v) x))` compiles
now, as does the same shape for a by-value parameter. `docs/structs-unions.md:62`
and `docs/collections.md:26`/`:73` teach the longer form and should be corrected
regardless of whether D5 is fixed.

### 2.6 D7 — `__fnty_N` in user diagnostics

`type-spelling` (`src/type-mangle.nuc:104`) answers `TY-FN` with
`fnty-intern`'s `"__fnty_<id>"` — the conformance-registry key, deliberately so.
The argument-mismatch diagnostic (`src/nucleusc.nuc:6560`) prints it verbatim:
`qsort: argument 4 has type __fnty_0, which does not match parameter type ptr`.
`__fnty_0` names nothing the user wrote. `fn-sig-spelling` (`src/nuch.nuc:312`)
already renders a real signature and is used only in one `declare`-conflict
message.

---

## 3. Plan

Ordering is forced: **D3 and D4 must land before D1.** D1 converts a hard error
(`argument 4 has type __fnty_0…`) into a typed value flowing through a slot that
does not check it (D3) into a call that does not lower it (D4). Fixing the C
reader first would trade a compile error for silent stack corruption in exactly
the case that motivated the change — a callback taking by-value structs.

### Phase 1 — make the existing type mean something

**FP-1 — enforce signature compatibility at every typed slot.** In
`safe-coerce-val`, place a `TY-FN`/`TY-FN` arm *above* the `sk == dk`
short-circuit at `src/nucleusc.nuc:3605`; on incompatibility return null, which
every caller already turns into a located diagnostic. One site covers all four
slots, because `let` init, `set!`, `.set!` and the call argument all funnel
through it.

*The one judgment call: what "compatible" means.* Exact `fn-sig-eq` is the
C-faithful answer and would reject `(defn cmpi (a:ptr:i32 b:ptr:i32):i32)`
against `int (*)(const void *, const void *)` — the single most common
comparator shape, which compiles today. **Recommendation: `fn-sig-eq` with two
relaxations, both with in-tree precedent** — pointer *kind* (`ptr`/`raw`/`ref`/
`?T`) is ignored in parameter and return position, as `type-eq` already ignores
it for a bare fn versus a `(ref fn)`; and an elem-less bare `ptr` on either side
matches any `ptr:T`, which is the fn-pointer analogue of C's `void *` and the
same absorption `type-join` performs for a bare `ptr` branch (MC-1). Everything
else — arity, variadicity, return type, differing pointee types, any scalar
mismatch — is refused. This keeps `qsort` ergonomic and refuses §2.3's three
cases.

**FP-2 — give the indirect call the direct call's rules.** In
`emit-funcall-value`, after `check-call-arity`, walk the function type's
parameter list exactly as `emit-call-with-args` does: `pkind-flow-check`,
`type-eq`, `safe-coerce-val` with the located mismatch diagnostic, then
`vararg-promote` past the fixed prefix for a variadic fn type. Then lower through
`abi-classify` / `abi-args-begin` / `abi-classify-arg` / `abi-print-param` and
emit the hidden `sret` operand for an `ABI-MEMORY` return, spelling the call's
signature from the lowered types. `abi-emit-struct-call` (`src/abi.nuc:795`) is
the existing shape; `src/union-emit.nuc:689`'s local workaround is deleted once
it is redundant.

Apply the ABI half to the `BoxedFn` path (`src/nucleusc.nuc:8429`) in the same
change — it is the same rule at a second site, and conventions.md already records
what happens when one rule lives at six sites and drifts at three of them.

Node-type needs no change: a `funcall`'s type is the fn type's declared return
either way, and the `sret` rewrite is emit-only.

**FP-3 — render function-pointer types in diagnostics.** Add a diagnostic-only
`type-display` that answers `TY-FN` through `fn-sig-spelling` and delegates
everything else to `type-spelling`; route the argument, return and slot mismatch
messages through it. `type-spelling` keeps its round-trip contract and its
`__fnty_N` key untouched. Rides with FP-1, whose entire value is a legible
refusal.

### Phase 2 — stop erasing the type at the C boundary

**FP-4 — build real `TY-FN` types in the C importer.** All four positions in
§2.1. Each already *locates* the `(*name)(args)` shape and skips it with
`c-skip-parens`; the change is to parse the inner parameter list with the
`c-parse-type` loop already written for `c-parse-func-decl`, and build the type
with `make-type TY-FN` + `type-set-params` + `.set! ret` — the four lines
`src/cheader.nuc:885` already runs for the function's own signature.

- **Subsumes C1's inline-function-pointer-member repair**, which edits the same
  branch (`:1404`) and additionally has to extract the field *name* it currently
  drops. Do them as one change; separately they would collide.
- **Fail-safe discipline unchanged.** Any inner return or parameter type the
  parser cannot represent keeps today's `ptr` collapse rather than refusing the
  enclosing declaration, and records a skip reason (C2). A `ptr` here is a
  *narrowing* of a legal type, not a wrong layout — the D1 status quo — so it is
  the right fallback, unlike the by-value-member case where `ptr` would corrupt a
  layout.
- **`signal`'s function-returning-function-pointer shape** (`void (*signal(int,
  void(*)(int)))(int)`) is a distinct declarator, currently skipped outright. It
  is worth doing in the same pass — the parse is the same recursion — but it can
  be dropped without affecting anything else here.

**FP-5 — render function-pointer types in `--emit-cheader`.** C's
function-pointer type is a *postfix declarator*, not a prefix type, so
`type-to-c` cannot answer this alone — exactly the problem W8 G-2 hit for
`(array T N)` and solved by pushing `[N]` out to the declarator sites. Add
`type-to-c-decl(t, name)` returning the whole declaration; have `type-to-c`
delegate with an empty name, and move the `TY-ARRAY` special case onto it so
there is one declarator renderer rather than two conventions. The two declarator
sites are `emit-cheader-defstruct` and the function-signature writer.

### Phase 3 — struct values

**SV-1 — make a struct value a legal member-access receiver.** At each of the
five sites in §2.5, when the receiver is `TY-STRUCT`/`TY-UNION` rather than a
pointer to one, materialize it into a fresh alloca with a single store and
continue down the existing GEP path.

- **Reads** (`.`, `_get`, head-position `(v f)`) — allow unconditionally.
- **`.set!` and `.&`** — require an *addressable* receiver, and route through the
  same addressability test `addr-of` already applies. `(.set! v x 1)` on a
  by-value parameter is meaningful (it mutates the local copy, as in C); on a
  temporary it is a store into something about to be discarded, and should stay
  an error — reworded to say *why*, and to name `addr-of`.
- **Lockstep.** `node-type-field` and `callable-get-type` must accept the same
  receivers in the same change, or the type pass and the emitter disagree — the
  cross-file lockstep conventions.md opens with.
- Retires the `(addr-of v)` idiom recorded in conventions.md §"A by-value struct
  parameter needs `(addr-of v)` before field access"; that section gets rewritten,
  not deleted, since `(addr-of v)` remains the spelling for `.set!`/`.&`.

**SV-2 — correct the documented idiom.** `docs/structs-unions.md:62`,
`docs/collections.md:26`/`:73` and §4.1 friction 2 of the sibling document all
teach `alloca` + `ptr-set!` where `addr-of` sufficed even before SV-1. Update
them alongside SV-1's new direct spelling.

### Phase 4 — already staged

**C1 / C2** (bare `unsigned`/`signed`; a recorded reason on every skip path) are
unchanged from cheader-parser-vs-libclang.md §6 and independent of everything
above. They edit the same file as FP-4 — `c-parse-type`'s specifier table and the
skip-recording path — so they should ride with it.

---

## 4. Verification for phases 1–4

- **FP-1/FP-2 are the bootstrap risk, and it is small.** The compiler's own two
  indirect calls (`src/union-registry.nuc:1567`, `src/generics.nuc:5124`) pass
  only pointers and integers and return a pointer, so no ABI lowering changes and
  no signature is currently wrong; the expected result is a byte-identical boot.
  If it is not, the diff *is* the finding.
- **FP-2 needs the four-target matrix**, not just x86_64: `tests/run-abi-test.sh`
  and `run-riscv-abi-test.sh` already encode the per-target struct rules
  (`byval` on SysV, plain pointer on aarch64/riscv64/avr, riscv64's hard-float
  flattening). Add an indirect-call row to each, asserting the *instruction* as
  well as the run — §2.4(a)'s wrong-register-class case prints a plausible number
  on some inputs, so a value assertion alone is not a gate. This is the lesson
  the varargs-promotion item recorded.
- **FP-4 changes the type of imported symbols**, so anything that stored a C
  callback in a `ptr` needs the real type. Blast radius is measurable before
  committing: nothing in `src/` or `lib/` uses `qsort`, `atexit`, `bsearch` or
  `signal`, and the `unsafe/cast ptr` sites in `src/repl.nuc` are JIT addresses,
  not header-derived types. Pre-release rules apply — no back-compat shim beyond
  what the boot needs.
- **FP-5 is gated by `check-headers`**, which already compiles the generated
  headers; add `-Wpedantic` to that unit so the `void*`-to-function-pointer class
  cannot come back silently.
- **SV-1 must not move existing IR.** A receiver that is already a pointer takes
  the identical path; only a previously-refused program gains code. A
  byte-identical boot is the gate.

---

## 5. What phases 1–4 leave, and where it goes

The four items the surrounding documents defer — wide and narrow floats,
bitfields, `packed`, C11 anonymous members — are **not** left here. They are
planned in §§6–9, with the limits that survive named in §10 and the shared
verification story in §11. Sequencing: phases 1–4 are independent of §§6–9 and
should land first, because they are the ones that close live miscompiles.

What genuinely does not change:

- **The libclang recommendation.** Nothing here disturbs it, and §§6–9 sharpen
  it. Two of the three §4.1 frictions turned out to be defects on the Nucleus
  side of the boundary, which a different front end would have inherited
  unchanged — libclang would have handed a correctly-typed callback signature to
  a slot that does not check it and a call that does not lower it. And of the
  four items §§6–9 plan, libclang would have paid for exactly one (`packed`),
  which §7 shows is the cheapest of the four anyway.
- **`_Complex`** — out of scope, with reasons, in §10.


---

## 6. The missing float types (D8)

`long double`, `_Float128` and `_Float16` account for 156 refused declarations
across the standard headers and for one of the nine still-blocked struct types
(`max_align_t`). Both surrounding documents call this "a type-system item" and
stop there. Measured, it is the *smallest* of the four items in §§6–9.

### 6.1 What LLVM already does

Every ABI question answers itself, because LLVM has all three types and knows
their calling conventions. Measured with clang at `-O0`:

| C | LLVM type | scalar parameter/return | `sizeof` |
|---|---|---|---|
| `long double` (x86-64) | `x86_fp80` | `define x86_fp80 @f(x86_fp80)` | 16 |
| `long double` (aarch64, riscv64) | `fp128` | `define fp128 @f(fp128)` | 16 |
| `_Float128` / `__float128` | `fp128` | `define fp128 @f(fp128)` | 16 |
| `_Float16` | `half` | `define half @f(half)` | 2 |

Arithmetic is `fadd`/`fsub`/`fmul`/`fdiv`/`fcmp` on the same types — nothing new.
Conversions are `fpext`/`fptrunc`, which the existing `unsafe/cast` ladder
(`src/nucleusc.nuc:4052`) already spells for the f32↔f64 pair.

**`long double` is target-dependent and that is the one design decision here.**
It is `x86_fp80` on x86-64/i386 Linux, `fp128` on aarch64 and riscv64 (both
measured), and plain `double` on AVR, ARM32 and MSVC. So the Nucleus types must
be the *representations* — `f16`, `f80`, `f128` — and the C spelling
`long double` maps to whichever the target uses. That is exactly the
`ptr-int-type` / `usize` pattern already in the tree, not a new mechanism.

### 6.2 The literal problem, and why it is not a bootstrap problem

LLVM will not accept a decimal literal at these widths:

```
llvm-as: error: floating point constant does not have type 'x86_fp80'
@a = global x86_fp80 1.5
```

The hex forms are accepted: `x86_fp80 0xK3FFFC000000000000000`,
`fp128 0xL00000000000000003FFF000000000000`, `half 0xH3E00`. So the compiler must
render the bits itself, exactly as `f32-const-ir` (`src/nucleusc.nuc:1972`)
already does for `float`.

This looked like the blocker — the compiler is written in Nucleus, and a Nucleus
without `f80` cannot fold an `f80` constant. **It dissolves.** f64→f80 and
f64→f128 are *exact* widenings: every f64 is representable, so the conversion is
sign + exponent rebias (1023 → 16383) + mantissa shift, all integer arithmetic on
the f64 bit pattern the compiler can already extract (`addr-of` + reinterpret +
`fmt-i64`, the `f32-const-ir` idiom verbatim). The compiler never performs f80
arithmetic to compile an f80 program, so there is no chicken-and-egg and no
boot-refresh beyond the ordinary one.

f64→f16 *is* a narrowing and needs round-to-nearest-even plus subnormal and
overflow handling — call it 40 lines, the same shape as the f32 path but written
out in software rather than delegated to a host cast.

### 6.3 Items

- **FL-1 — the three types.** `TY-F16`, `TY-F80`, `TY-F128` through the scalar
  roster. The blast radius is enumerable and small: **21 sites mention `TY-F32`
  tree-wide** — `type-to-ir`, `type-to-c`, `type-size`, `abi-alignof`,
  `is-float-type`, `type-spelling` (×2), the zero-initializer text, the binop
  path, and three REPL result-printing arms. `f80`'s *storage* size is
  target-keyed (16 on x86-64, 12 on i386) the way `ptr-int-type` is;
  `abi-alignof` then falls out of `type-size` with no new arm.

  **The one site that fails silently is the `unsafe/cast` conversion ladder**
  (`src/nucleusc.nuc:4052`): its float→float `cond` has exactly two arms
  (`f32→f64` `fpext`, `f64→f32` `fptrunc`) and a bare `true (do)` fall-through,
  so a width pair it does not name emits **no instruction at all** and passes
  the unconverted value along — the same shape as the `safe-coerce-val` hole in
  §2.3. Five widths means twenty ordered pairs; the arm must be rewritten as a
  width comparison, not extended pair by pair.
- **FL-2 — the constant renderers.** `f80-const-ir` / `f128-const-ir` (exact,
  integer-only) and `f16-const-ir` (software RNE). All three hang off
  `float-literal-ir-at` (`src/nucleusc.nuc:1984`), which is already *the* single
  home for "what text does this literal have at this width".
- **FL-3 — hex-float literals.** `0x1.8p+3` does not lex today
  (`error: undefined: 0x1.8p3`). It is the only way to write a bit-exact f80 or
  f128 value, it is C's own syntax, and it is exact by construction. See §10 for
  why this matters more than it looks.
- **FL-4 — aggregate ABI.** Scalars are free (§6.1); a wide float *inside a
  struct* is not, and the three cases differ. Measured:
  `struct { long double x; }` → `ptr byval(%struct.S1) align 16` (X87 → the whole
  aggregate is MEMORY); `struct { __float128 x; }` → `fp128` (SSE+SSEUP, one
  xmm — forcing MEMORY here would be an ABI mismatch, so the conservative answer
  is *wrong*); `struct { _Float16 x; int y; }` → `i64`, which the existing
  max-merge in `abi-class-eightbyte` already produces once `abi-class-type-at`
  returns an SSE class for `half`. So: one new X87 class that poisons the
  aggregate to MEMORY, and an SSEUP rule so a 16-byte `fp128` stays one
  eightbyte-pair. Re-verify the aarch64 and riscv64 paths separately — both route
  >16-byte aggregates by plain pointer and `fp128` is exactly 16.
- **FL-5 — varargs: change nothing, deliberately.** Measured: `x86_fp80` and
  `half` are both passed **unpromoted** through `...` (`call i32 (ptr, ...) @p(ptr
  @.str, half noundef %3)`). `vararg-promote` (`src/nucleusc.nuc:6358`) keys on
  `TY-F32` specifically and is already correct. Do **not** generalize it to "any
  float narrower than f64" — that is the tempting edit and it would be a
  regression. Worth an explicit negative test, since the varargs-promotion item
  already recorded that half these types print correctly under both behaviours.
- **FL-6 — AVR.** Reject all three at the two finalization points
  `avr-reject-f64` (`src/abi.nuc:124`) already guards.
- **FL-7 — the importer.** Map `long double` to the target's type, `_Float128`
  and `__float128` to `f128`, `_Float16` to `f16`, and delete the 156 skip
  records. `docs/structs-unions.md:249`'s "the unrepresentable set is
  `long double`, `_Float128`, `_Float16`" becomes empty.

  **`max_align_t` is not unblocked by this, and the claim that it was is wrong.**
  Re-measured: clang's `__stddef_max_align_t.h` writes
  `long double __clang_max_align_nonce2 __attribute__((__aligned__(__alignof__(long double))));`
  — a member `__attribute__`, which is PK-2's parsing work and PK-3's alignment
  mechanism, not a float width at all. It comes off the blocked list with
  **PK-3**, and §11's census figure moves with it.

---

## 7. `__attribute__((packed))` (D10)

The one row cheader-parser-vs-libclang.md §2 concedes to libclang outright, and
the cause of the single `sizeof` mismatch in its 101/103 census (`epoll_event`,
16 vs 12).

Measured: `struct __attribute__((packed)) P { char c; int i; short s; };` is
`%struct.P = type <{ i8, i32, i16 }>`, `sizeof` 7, `offsetof(i)` 1, and **every
access is `align 1`**.

- **PK-1 — `StructDef` gains `packed`.** Three consequences, of which the third
  is the one that makes this more than a flag:
  1. `abi-struct-size` / `abi-struct-align` / `abi-class-eightbyte`
     (`src/abi.nuc:192`/`:181`/`:207`) suppress `abi-align-up` per field and give
     the struct alignment 1.
  2. The IR type line prints `<{ … }>`. That line is written at
     **eight sites** — `nucleusc.nuc:13231` and `:7479`, `cheader.nuc:1038` and
     `:1067`, `union-registry.nuc:82`, `:143`, `:164`, `:1079`. This is the same
     shape conventions.md records for the six `declare` emitters, three of which
     had silently drifted; write one helper rather than eight edits.
  3. **`emit-load` and `emit-store` derive `align` from `type-size ty`**
     (`src/nucleusc.nuc:9851`, `:9860`). A packed field must emit `align 1` or the
     IR carries a false alignment promise — a real miscompile on any
     strict-alignment target and under vectorization on x86. The field-access
     path has to tell the load/store emitter the receiver is packed. This is the
     non-obvious half of the item.
- **PK-2 — surface and import.** `(defstruct :packed P …)` follows the existing
  keyword-attribute shape `parse-decl-attrs` (`src/union-registry.nuc:1601`)
  already implements for `:volatile` / `:const`. On the import side the
  `__attribute__` run is currently *skipped* at `c-parse-type` — it must now be
  read for `packed` (and, at the same site, `aligned`).
- **PK-3 — `__attribute__((aligned(N)))`, as its own item.** Measured:
  `struct A { int x; } __attribute__((aligned(16)))` has `sizeof` 16 while its
  LLVM type stays `{ i32 }` — the alignment is **not** in the type. So this is a
  different mechanism from `packed`, not a second flag on it: it needs an
  explicit over-alignment recorded on the StructDef, honoured by `abi-alignof`
  and by every `alloca`/global that allocates one. Include it, but sequence it
  after PK-1 and do not let it hold PK-1 up.

  *(The "not in the type" half of that measurement was read off `-emit-llvm` for
  a declaration with no definition. Re-measured against a definition, clang DOES
  put it in the type — `%struct.A = type { i32, [12 x i8] }` — and it has to:
  LLVM computes `[n x %A]`'s stride and every GEP offset from the element list,
  so an unpadded type would stride 4 where C strides 16. §14.7 records what the
  item turned out to be.)*

---

## 8. Bitfields (D9) — and the shared prerequisite

`FILE` is the marquee casualty (`int _flags2:24;`), and bitfields are pervasive
in kernel and protocol headers.

### 8.1 The prerequisite both this and §9 need

Today's contract is **one Nucleus field = one LLVM member at the same index**:
`emit-field-load` (`src/nucleusc.nuc:5293`) hard-codes
`getelementptr … i32 0, i32 idx` with `idx` straight from `struct-field-index`
(`:5282`, 17 callers tree-wide).

Bitfields break it in one direction — several Nucleus fields share one storage
unit — and anonymous members break it in the other — one member holds a *nested*
struct whose fields are named from the outside, reached by a **two-level GEP**
(measured: `p->hi` on an anonymous member emits GEP-to-member-2 then
GEP-to-field-1). Both are the same broken invariant, so both are fixed once:

- **FR-1 — a resolved field reference.** Replace "field name → `i32` index" at
  the *access* sites with a descriptor: a path of IR member indices, plus an
  optional bit range and signedness. `struct-field-index` keeps its signature for
  the majority of its callers, which only ask whether the field exists; a new
  `struct-field-ref` answers `emit-field-load`, `emit-field-set`,
  `emit-field-addr`, `emit-get-intrinsic` and their `node-type` partners
  (`node-type-field`, `callable-get-type`). **Do this first and alone**: a
  single-element path with no bit range is today's GEP verbatim, so the gate is a
  byte-identical bootstrap with no other change in flight.

### 8.2 Items

Measured lowering for `struct BF { int a:3; unsigned b:5; int c:24; int d; }` —
all three bitfields share one `i32` storage unit at offset 0, `d` at offset 4:

```llvm
; read  p->b        ; write p->b = v            ; read signed p->c
%4 = load i32        %8  = and i32 %5, 31         %4 = load i32
%5 = lshr i32 %4, 3  %9  = shl i32 %8, 3          %5 = ashr i32 %4, 8
%6 = and i32 %5, 31  %10 = and i32 %7, -249
                     %11 = or i32 %10, %9
                     store i32 %11
```

- **BF-1 — layout.** `Field` gains `ir-index`, `bit-offset`, `bit-width`,
  `bf-signed`. The allocator is C's storage-unit rule: a bitfield of declared
  type `T` and width `w` takes the next `w` bits of the current unit unless that
  would cross a `T`-alignment boundary, in which case a new unit starts; a
  zero-width unnamed bitfield forces the next boundary (measured:
  `struct Mix { unsigned x:1; unsigned :0; unsigned y:1; }` is 8 bytes); the
  struct's alignment includes each bitfield's declared `T`.
- **BF-2 — access.** Read = load unit, `lshr`, mask (`shl`-then-`ashr` when
  signed). Write = read-modify-write with the inverted mask. `.&` and `addr-of`
  on a bitfield are **refused** — that is C's own constraint (`&` on a bitfield is
  ill-formed), so it is a faithful diagnostic rather than a Nucleus limitation,
  and it is the one place this feature gets to be simpler than the general case.
- **BF-3 — declaring them.** So Nucleus can *write* a bitfield, not only read
  one: `(defstruct IO flags:i32 (flags2 i32 :bits 24) pad:i8)`, on the same
  keyword-attribute precedent as PK-2.
- **BF-4 — the importer** parses `: width`, including unnamed and zero-width
  members. `FILE` stops being opaque, which is the acceptance test.

**On the layout rules themselves.** C leaves parts of bitfield allocation
implementation-defined; what matters for interop is matching *clang on this
target*, not a reading of the standard. That is what §11's differential test is
for, and it is why this item is bounded despite the reputation.

---

## 9. C11 anonymous members (D11) — the layout half already exists

Both surrounding documents call this the hard one: "an anonymous member's fields
are addressable from the outer struct, and **Nucleus has nothing to lower that
onto**" (cheader-parser-vs-libclang.md §2). **That premise is stale.**

Measured, clang's model is that an anonymous member is an ordinary nested member
with its own type — `%struct.Anon = type { i32, %union.anon, %struct.anon }` —
and outside access is just a two-level GEP. Nucleus has had exactly that since
Stage 10: `lookup-or-make-anon-struct` and `lookup-or-make-anon-union`
(`src/union-registry.nuc:63`, `:107`) memoize anonymous aggregates as
`__anon_struct_h<hex>` types, and **the C parser already calls the first of them**
(`src/cheader.nuc:1445`). The layout, the IR type, the ABI classification and the
by-value passing all work today.

What is missing is only **name lookup through the member** — which is FR-1, which
bitfields need anyway. So this item is two small pieces on top of a prerequisite
that is already being paid for:

- **AN-1 — import.** Build the anonymous member through the existing memoizer and
  give it a compiler-minted member name.
- **AN-2 — lookup.** `struct-field-ref` searches transitively into members whose
  name is compiler-minted, returning the multi-level path. A name reachable
  through two different anonymous members at the same depth is ambiguous and gets
  a located diagnostic — C's own rule. The `defstruct` surface for declaring one
  falls out of the same lookup.

`sigcontext` and `rusage` come off the blocked list here.

---

## 10. Pushback: what is not reachable, and what is not in scope

Three honest limits. None of them blocks the plan; all three would be worse
discovered late.

**1. Decimal literal precision at f80/f128 is out of scope here, and staged
elsewhere.** The compiler folds a decimal float literal through the host's `f64`
(`float-literal-value`), so `(defvar x:f128 1.1)` gets the f64 value of 1.1
*widened exactly* — not the f128-correct 1.1. C does better because its front end
converts the decimal string directly to the destination format. **FL-3's
hex-float literals mitigate this and do not solve it**: `0x1.199999999999Ap+0` is
exact and is the spelling for a bit-precise wide constant, but a user who writes
`1.1` and expects 34 significant digits silently gets 17, and nothing in the
source distinguishes the two cases.

Staged as its own item in
[future/decimal-float-literals.md](../future/decimal-float-literals.md) (DL-1…DL-4):
a correctly-rounded decimal→binary converter with the fixed-width big-integer
support it needs, routed through `float-literal-ir-at` so there is one edit site
— which also retires `f32-const-ir`'s existing decimal→f64→f32 double-rounding.
**Nothing in this plan is blocked on it**: it touches one function, adds no type,
changes no ABI, moves no layout, and can land before or after §6 with no ordering
constraint. It is separate because a *nearly* correctly-rounded converter is
indistinguishable from a correct one until it is not, and that is a poor
passenger on a larger change.

**2. `_Complex` is deliberately out of scope.** It is not a float width — it is a
distinct type constructor with its own ABI class (x86-64 returns
`_Complex double` in xmm0/xmm1, and `_Complex long double` in st0/st1), its own
arithmetic (including the messy multiply/divide rules in C Annex G), and its own
literal syntax. Adding it after FL-1 is much easier than adding it with FL-1.
`stage3c.md` already ranks it low priority and nothing has moved it. `_Imaginary`
is not implemented by any production C compiler and should not be by this one.

**3. `f80` is an x86 type, and naming it in a program pins that program to x86.**
`long double` is `fp128` on aarch64 and riscv64 and `double` on AVR — all
measured. The plan's answer is that `f16`/`f80`/`f128` are *representation*
names and the portable spelling is the C one, mapped per target. That is a
language-surface decision worth taking deliberately rather than discovering when
someone's `f80` program fails to cross-compile.

Two scope notes rather than limits:

- **Bitfield layout follows clang, not the standard.** C leaves parts of it
  implementation-defined; interop means matching the platform compiler. The gate
  is the differential test, not a spec reading.
- **`aligned(N)` is a different mechanism from `packed`** (§7 PK-3) and is
  sequenced after it.

What is *not* on this list is the thing both surrounding documents predicted
would be: none of these four items is blocked on something Nucleus cannot
express. The one that looked like a hard blocker — needing f80 arithmetic in
the compiler to fold an f80 constant — is not one (§6.2), and the one called the
hardest — anonymous members — is mostly already built (§9).

---

## 11. Verification for §§6–9

**The differential layout test is the gate, and it already exists — but it is
host-only, and that is not good enough for these four items.**
`tests/run-layout-test.sh` compiles `tests/layout/layout.c` with the platform
`cc` and `tests/layout/layout.nuc` with `nucleusc`, both over the shared
`tests/layout/structs.h`, and **diffs `sizeof` plus every field offset**. Adding
packed, bitfield and anonymous-member cases to `structs.h` makes clang the oracle
for all of §§7–9 at once. Three additions the existing harness needs:

- **A cross-target oracle**, because bitfield and packing rules are
  target-parameterised and Nucleus already cross-compiles to AVR and riscv64,
  where nothing today checks a layout. `clang --target=<triple> -ffreestanding
  -fsyntax-only` over a generated C file of `_Static_assert`s is a complete
  compile-time oracle for `sizeof`/`offsetof` on every target clang supports —
  no execution, no sysroot, no libclang, no linking. Verified on x86_64,
  aarch64, riscv64 and avr, and verified to *fail* on a wrong assertion. It
  earns its place immediately: `struct BF { int a:3; unsigned b:5; short c:9;
  int d; }` is 8 bytes on x86-64 and is not on AVR, where `int` is 16-bit — and
  `int c:24` is a hard error there rather than a different layout. A host-only
  test would have shipped a wrong AVR bitfield layout silently. This is also
  what retires the libclang argument for bitfield offsets
  ([cheader-parser-vs-libclang.md](cheader-parser-vs-libclang.md) §8.3): clang
  is the oracle either way, and it does not have to be linked in to be one.
- **Bitfields have no `offsetof`,** so offsets alone cannot gate them. The
  fixture must also round-trip *values*: write a pattern through each bitfield
  from C and from Nucleus and compare the raw bytes, which catches a correct
  offset with a wrong shift or a wrong mask.
- **A packed struct needs an access-side assertion, not just a layout one** —
  PK-1's third consequence is invisible to a `sizeof`/offset diff. Assert on the
  emitted `align 1`, the way the varargs-promotion item asserts on the emitted
  instruction rather than only the printed value.

**The census is the acceptance test.** cheader-parser-vs-libclang.md §1 measured
102 of 111 named struct/union bodies laid out. With FP-4 (four types), PK-3
(`max_align_t` — see FL-7 above for why it is here and not with the floats),
BF-4 (`FILE`) and AN-1/AN-2 (`sigcontext`, `rusage`) that becomes **111 of 111**,
and the `sizeof` census 103 of 103 once PK-1 lands (`epoll_event`). Re-run it; a
number short of that names exactly what is left.

**Per target.** `f80` exists only on x86-64/i386; aarch64 and riscv64 get `fp128`
for `long double`; AVR rejects all three. `run-abi-test.sh` and
`run-riscv-abi-test.sh` need a row per type per target, and FL-4's three
aggregate cases are the ones that will actually catch a mistake.

**Bootstrap.** FR-1 must be byte-identical on its own (a one-element path is
today's GEP). FL-1 adds `case` arms that no existing type reaches. PK-1 changes
the struct-type line only for structs that declare `:packed`, of which the
compiler has none. So every item here should converge unchanged, and any item
that does not has found something.

---

## 12. What phases 1–4 turned out to be

Landed 2026-08-26 on `stage16-ergonomics`. Everything below is measured, and each
claim has a test in `tests/run-tests.sh` named in brackets.

### 12.1 Where the plan held

- **FP-1** is `fn-slot-type-compat`/`fn-sig-compat` in `src/abi.nuc`, with the
  check inserted in `coerce-int-val` *before* its `sk == dk` short-circuit and in
  `safe-coerce-val` by delegation, so all four typed slots answer identically.
  Two deliberate relaxations, both load-bearing for real C: pointer *kind* is not
  part of a signature (`ptr:i32` matches `(ref i32)`), and a bare elem-less `ptr`
  is the fn-pointer analogue of `void *`. Without them the `qsort` comparator
  shape stops compiling. `is-ptr-like`, **not** `is-ptr-repr` — the latter admits
  `TY-FN`, which would let a bare `ptr` parameter match a `(fn …)` one and
  reinstate exactly the data-pointer-into-callable conversion `unsafe/cast` owns.
  [`s16-fp1-fnsig-match-accepted`, `s16-fp1-fnsig-mismatch-refused`]
- **FP-2** extracted the call-site argument loop into `coerce-call-argument` and
  gave `emit-funcall-value` and the BoxedFn call path the same treatment the
  direct path had: coercion, diagnostic, `vararg-promote`, and `abi-classify` /
  `abi-args-begin` / `abi-arg-frag` / `abi-emit-struct-call`. The closure
  environment pointer goes through `abi-arg-frag` like any other argument — hand
  printing it would leave the register budget one short for everything after it.
  [`s16-fp2-indirect-call-abi`, `s16-fp2-indirect-vararg-promoted`]
- **FP-3**, **FP-5**, **SV-2**, **C1** are as written.

### 12.2 Where it diverged

- **FP-4 needed `fn-sig-eq`/`type-eq` moved from `generics.nuc` into `abi.nuc`.**
  `coerce-int-val` lives in `abi.nuc`, which is imported at `nucleusc.nuc:1195`;
  `generics.nuc` is imported at `:1217`, so the check could not call forward to
  it. They moved to just after `field-at`, their only dependency.
- **The `signal` shape was worth doing and cost a refactor, not a parser.** The
  tail of `c-parse-func-decl` — attributes, validity gate, explicit-declare
  precedence, registration, ABI-lowered `declare` — became
  `c-finish-fn-decl`, and `c-parse-fnret-decl` reuses it by reading the parameter
  types back off the `TY-FN` that `c-parse-fn-type` built. [`s16-fp4-declarator-positions`]
- **FP-5 could not use `type-to-c-decl(t, name)` as planned.** The `--emit-cheader`
  path is driven by the type **AST**, not by `Type` objects, so it is
  `type-node-to-c-decl(tn, name, line)`. It also required fixing
  `extract-type-node`, which returned only the first element after the binding
  name and so dropped a function pointer's parameter list — the same "legacy
  fn-pointer form is spread across the whole rest" rule `extract-name-type`
  already applies in `nucleusc.nuc`. [`s16-fp5-cheader-declarators`, `s16-fp5-c-consumer`]
- **C1 was not only the bare form.** `long unsigned a;` and `short unsigned a;`
  were broken too — §3 of the sibling document says `long unsigned` works, and it
  does not: the `long` peek only continued on `int`/`double`, so `unsigned` was
  read as the declarator name. C's declaration specifiers are order-independent
  and now all six orders agree with `cc`. A base this parser cannot describe
  (`__int128`, `_BitInt`) deliberately stays in the specifier run, so it reaches
  the unresolved-base path rather than being silently narrowed to `int`.
  [`s16-c1-bare-unsigned`, `s16-c1-signedness-and-functions`]
- **C2 is narrower than "a reason on every skip path", on purpose.** The existing
  comment at `cheader.nuc`'s validity gate argues — correctly — that warning on
  every decline would bury the signal, since every variable and macro remnant in
  a preprocessed header goes through it. `cheader-note-unparsed-decl` records
  only what is unambiguously a prototype: a non-keyword identifier followed by
  `(`, with no `{` body in the span, falling back to the last non-keyword
  identifier for a parenthesised declarator (`int (f)(int);`). Recorded quietly,
  so it surfaces at the use site and nowhere else. Measured: zero records across
  stdio/stdlib/string/signal/time/sys-stat/pthread. [`s16-c2-skip-reason-recorded`]
- **SV-1 splits reads from writes differently than "allow reads unconditionally,
  gate `.set!`/`.&` on addressability".** Reads always *materialize* — a copy into
  a fresh alloca — rather than reaching for the receiver's slot, so `(. v x)` and
  `(v x)` emit the same thing whatever the receiver was. `.set!`/`.&` take the
  slot directly via the receiver *symbol*, which is why a by-value parameter is
  mutable in place as in C, and a temporary is refused. [`s16-sv1-struct-value-receiver`,
  `s16-sv1-lvalue-and-refusals`]

### 12.3 What it bought, measured

- `qsort` and `atexit` take a Nucleus function with no cast. [`s16-fp4-qsort-atexit`]
- `struct sigaction` and `sigevent_t` lay out byte-identically to clang and left
  the opaque roster in `run_l2_libc_layouts` for the layout oracle. Only `FILE`
  remains opaque there, for §8's bitfield reason.
- A C consumer compiled `-std=c11 -Wall -Wextra -Werror` against a generated
  header passes a C function into a Nucleus fn-pointer parameter, calls the
  pointer a Nucleus function returned, and is called back through a struct
  member. None of it compiled before, since ISO C defines no conversion between
  a function pointer and `void *`. [`s16-fp5-c-consumer`]
- `(. cursor kind)` compiles on a by-value struct — parameter, local, or call
  result read in place.

### 12.4 Pinned by

`make test` (all units), `make bootstrap` (stage1.ll == stage2.ll), `make
abi-test`, `make layout-test`, `make check-headers` (69 generated headers
unchanged).

---

## 13. What the float phase turned out to be

Landed 2026-08-26 on `stage16-ergonomics`, right behind phases 1–4. Every claim
below is measured against clang 19.1.7 and has a test in `tests/run-tests.sh`
named in brackets.

### 13.1 Where the plan held

- **FL-1's silent site was the one named.** The `unsafe/cast` float→float ladder
  had two arms and a bare fall-through, so an unnamed width pair emitted no
  instruction at all. It is now a `float-rank` comparison — significand bits,
  the one ordering that is total across all five widths — rather than twenty
  ordered pairs.
- **FL-2 dissolved exactly as §6.2 predicted.** f64→f80 and f64→f128 are integer
  work on the f64 bit pattern; f64→f16 is the same shape as the f32 path written
  out. The renderers live in `type-utils.nuc`, not `nucleusc.nuc`, because
  `type-zero-const-ir` needs them and is imported earlier.
- **FL-4's three aggregate answers are byte-identical to clang**, including the
  one where the conservative answer would have been wrong (`struct { __float128
  x; }` stays one xmm pair). [`s16-fl-aggregate-abi`]
- **FL-5 was a no-op, and is now a test rather than a comment.** `half`, `f80`
  and `fp128` pass through `...` unpromoted; only `f32` widens.
  [`s16-fl-vararg-unpromoted`]

### 13.2 Where it diverged

- **FL-3 is exact, and that took a 128-bit significand.** The item was written as
  "make `0x1.8p+3` lex". Lexing is the small half: rendering it through
  `strtod`'s f64 would have made the hex spelling *no more precise than decimal*
  at f80 and f128, which is the entire reason to have it. `hexfloat-parse`
  accumulates the digits into a 128-bit integer with a sticky bit and
  `hexfloat-fit` rounds that to any of the five formats (round-to-nearest-ties-
  to-even, subnormals, overflow-to-infinity) — all integer arithmetic, so the
  compiler needs no wide float of its own to fold one. 104 constants across the
  five widths match clang exactly. [`s16-fl-constants-vs-clang`]
  - `Val` gained `lit-lex`, the literal's own lexeme, because `coerce-int-val`
    re-renders a literal at the destination width from `lit-f64` — which is only
    as precise as f64. Null on every other Val, so the f64 path is unchanged.
  - **Hex INTEGER literals came with it.** `0xFF` was an undefined symbol before;
    leaving it that way while `0x1p0` worked would have been incoherent, and the
    prefix scan is shared. Octal is deliberately *not* added: `0644` means six
    hundred and forty-four here, and quietly changing that is a worse trade than
    not having the form.
- **§10 limit 3 became a diagnostic rather than a documented caveat.** Naming
  `f80` on aarch64 emitted `x86_fp80`, which no other backend can select — an
  obscure downstream failure where AVR already had a clean refusal. It is now
  one gate, `reject-unavailable-float`, covering both. C's `long double` is
  untouched and stays portable. [`s16-fl-target-availability`]
- **The importer needed an MSVC arm the plan did not list.** `long double` is
  `double` under MSVC even on x86_64 (measured), so that check has to precede the
  architecture check.
- **FL-7 does not unblock `max_align_t`** — see the corrected item in §6.3.

### 13.3 What it cost elsewhere

- **The bootstrap needed a boot refresh, for a reason worth recording.** Making
  `long double` representable changed the compiler's *own* emitted IR: it imports
  `<stdlib.h>`, so `strtold`/`qecvt`/`qfcvt`/`qgcvt` and the `_r` pair now emit
  `declare` lines that the committed boot compiler had skipped. stage1 (from the
  stale boot) and stage2 (from the new compiler) therefore differed by exactly
  those six lines. stage2 == stage3 confirmed the new fixed point before
  `make update-bootstrap` was run. **Any change to what the C importer can
  represent moves the compiler's own declare set** — that is the general rule,
  and it is not obvious from the source.
- **`tests/fixtures/l1-members.h` and the L5 message test changed subject.**
  Both used `long double` as their "a builtin with no Nucleus width" specimen,
  and it stopped being one. The durable subject is `__int128`: deliberately
  unscheduled, and deliberately kept *out* of C1's implicit-`int` specifier rule
  so it reaches the unresolved-base path rather than being narrowed to `int`.

### 13.4 Pinned by

`make test` (857 units), `make bootstrap`, `make abi-test`, `make layout-test`,
`make check-headers`.

---

## 14. What the packing phase turned out to be

PK-1 and PK-2 landed 2026-08-26; PK-3 (`aligned(N)`) is still open, as the item
itself asks. Tests in `tests/run-tests.sh` named in brackets.

### 14.1 Where the plan held

- **All three consequences were the three named.** The layout suppression is one
  substitution — `abi-field-align`, which returns 1 for a packed struct — reused
  by the size walk, the eightbyte classifier and the riscv flattener, so none of
  them grew a packed branch. The type line is one helper,
  `emit-struct-type-line`, replacing six open-coded copies (the plan said eight;
  the other two write a union's `{ repr, pad }` line, which is not a field table
  and so only shares the brackets).
- **The access-side `align 1` was the non-obvious half, as stated.** `emit-load`
  and `emit-store` gained `-at` forms taking the alignment explicitly, because a
  packed field's alignment is a property of *where it sits*, not of its type. The
  two sites that emit a bare `store` with no align clause (a struct-literal field
  and a zero fill) append `, align 1` only when packed, which is what keeps every
  existing program's IR byte-identical.

### 14.2 Where it diverged

- **The anonymous-struct memoizer needed `packed` in its KEY, not applied after
  the lookup.** Two structurally identical bodies, one packed and one not, are
  different types; sharing one StructDef would have been a silent wrong layout
  for whichever arrived second. Same for the union memoizer.
- **`cheader-adopt-shape` had to copy it too.** Sharing a field table is not
  sharing a layout: a `typedef struct { … } __attribute__((packed)) Name;` alias
  printed `{ … }` for a `<{ … }>` type and sized it unpacked until this was
  fixed.
- **The attribute has to be read BEFORE the body is parsed**, because that is
  where the LLVM type line is written — so the trailing position is read by
  looking ahead over the body (`c-trailing-packed`) rather than in declaration
  order.
- **One of the three C positions must be ignored, and finding that out needed the
  oracle.** `typedef struct { … } S __attribute__((packed));` is
  `-Wignored-attributes` in clang and `-Wattributes` in gcc — both ignore it.
  Honouring it would have produced a `sizeof` that disagrees with every C
  compiler on the platform.
- **A pre-existing bug fell out of the same shape.** `typedef struct { … }
  __attribute__((packed)) Name;` was reading `__attribute__` itself as the
  typedef name, so the type registered under that spelling. It predates packing.

### 14.3 The cross-target oracle earned its place on its first run

§11 argued for `clang --target=<t> -ffreestanding -fsyntax-only` over generated
`_Static_assert`s on the grounds that packing rules are target-parameterised and
`run-layout-test.sh` is host-only. It found a real defect immediately, and not
the predicted one: **AVR's `BIGGEST_ALIGNMENT` is 8 bits**, so every type there is
byte-aligned and `struct { int8_t; int32_t; int16_t; }` is 7 bytes, not 12.
Nucleus had been emitting 12 since before packing existed, and no host test could
have seen it. `abi-alignof` now returns 1 on AVR; `make avr-test` is green.

The oracle takes Nucleus's own compile-time `sizeof` out of the emitted IR
(`(defvar s:i64 (sizeof S))` → `@s = global i64 N`), which is what makes it work
for a target whose binaries this host cannot run. [`s16-pk-layout-cross-target`]

### 14.4 What it bought, measured

- `struct epoll_event` imports at 12 bytes, matching `cc` — the single `sizeof`
  mismatch in cheader-parser-vs-libclang.md §1's 103-type census, and the one row
  §2 conceded to libclang outright. [`s16-pk-epoll-event`]
- A C consumer compiled `-Wall -Wextra -Werror` against a generated header
  `_Static_assert`s the same size Nucleus computed. [`s16-pk-cheader-roundtrip`]
- Six shapes agree with clang on five targets. [`s16-pk-layout-cross-target`]

### 14.5 Known limit

`(.& p field)` on a packed struct yields an ordinary `(ref T)`, which carries no
alignment record, so a load through *that* pointer claims the field type's
natural alignment again. C has the same hole — it is what
`-Waddress-of-packed-member` exists for — and closing it needs an alignment on
the pointer type, which is PK-3's mechanism rather than PK-1's.

### 14.6 Pinned by

`make test` (864 units), `make bootstrap` (converged with no boot refresh, so
PK-1/PK-2 are inert for the compiler's own IR), `make abi-test`,
`make layout-test`, `make check-headers`, `make avr-test`.

---

### 14.7 PK-3, `aligned(N)` — landed 2026-08-28

`(defstruct :align 32 CacheLine v:i64)` and `(defstruct Slot c:i8 (:align 16
v:i32))`; both C attribute forms on import in all three positions C honours,
both written back out by `--emit-cheader`. `max_align_t` now lays out, which
takes cheader-parser-vs-libclang.md §1's nine blocked types to eight.

**The plan's central measurement was wrong, and it was the one that priced the
item.** "`struct A { int x; } __attribute__((aligned(16)))` has `sizeof` 16 while
its LLVM type stays `{ i32 }` — the alignment is **not** in the type" was read
off a declaration with no definition, where clang emits no layout at all.
Against a definition it emits `%struct.A = type { i32, [12 x i8] }`, and it has
to: LLVM computes `[n x %A]`'s stride and every GEP's byte offset from the
element list alone, so an unpadded type would stride 4 where C strides 16. So
PK-3 is not "a flag `abi-alignof` consults":

- **A padding machine.** `field-pad-before` is the gap between the offset C
  requires (`abi-field-align`, which now consults the member attribute) and the
  one LLVM's own placement produces (`abi-field-ir-align`, which consults only
  `packed`, because that is all LLVM models). `struct-tail-pad` is the same
  subtraction at the end. Both answer 0 unless something in the struct carries
  an `aligned`, which is what leaves every existing type line byte-identical.
- **An index remap.** A pad is an element, so `getelementptr … i32 0, i32 n`
  needs the *element* index, not the field index. `field-ir-index` is that map,
  applied at the four GEP sites a user or C struct can reach. The off-by-one
  worth recording: the pad before field `i` shifts field `i` **itself**, so the
  count is over `0..i`, not `0..i-1`.
- **Explicit alignment on every slot.** LLVM derives an aggregate's alignment
  from the same element list, so an `alloca`/global of an over-aligned struct
  must state it. `abi-slot-align` only ever raises what the site already printed
  (`type-size`), and `struct-align-suffix` adds a clause only where there was
  none — so no existing line moves. It also fixes a latent FL-4 defect: a struct
  containing an `fp128` needs 16 and was getting the pointer size.

**Three rules that had to be measured rather than assumed**, all against clang:

1. `aligned` only ever RAISES. `struct E { int x; } __attribute__((aligned(2)))`
   stays alignment 4. So the whole rule is a max, not an assignment.
2. On a packed struct the two compose rather than override, in both directions:
   `packed, aligned(4)` on the struct is 8 bytes with the `int` still at offset
   1, while a member `aligned(4)` inside a packed struct puts it back at 4. That
   is why `abi-field-align` is `max(member-attr, packed ? 1 : natural)`.
3. The argument is an integer constant expression, and the form that matters is
   `__alignof__(T)` — the idiom that PINS a member to its natural alignment
   rather than raising it. `max_align_t` is made of two of them, and evaluating
   them is the whole of what unblocked it. An argument that is neither an
   integer nor `__alignof__`/`sizeof` leaves the type opaque rather than
   guessing.

**The cross-target oracle caught the AVR half of the same mistake as PK-1's.**
`aligned(N)` raises an alignment past `BIGGEST_ALIGNMENT` on AVR too, so PK-1's
`(when (abi-is-avr) (return 1))` short-circuit at the top of `abi-alignof` was
discarding it for aggregates. It now sits **below** the struct/union/array arms:
scalars are byte-aligned there, aggregates ask `abi-struct-align`, which honours
the attribute. Found by `struct F { struct A inner; int8_t c; }` disagreeing on
`avr` alone. [`s16-pk3-align-cross-target`]

**One near-miss worth recording.** Adding the member alignments to
`hash-struct-shape` renamed every anonymous C type the importer memoizes — 42
lines of bootstrap diff — because the zero was being folded in for structs that
carry no alignment at all. "No alignment" and "alignment 0" are the same shape;
only a non-zero one belongs in the key.

**Known limit closed, and one still open.** §14.5's `(.& p field)` hole is
unchanged: PK-3 gives a *field* an alignment, not a *pointer type*, so a load
through a taken address still claims the field type's natural alignment. C has
the same hole. What PK-3 does close is the other direction — a field that is
over-aligned is now reachable at the right offset at all.

**Pinned by** `make test` (871 units), `make bootstrap` (converged with no boot
refresh), `make abi-test`, `make layout-test`, `make check-headers`,
`make avr-test`, `make riscv-test`.

---

## 15. What the bitfield phase turned out to be

### 15.1 FR-1 landed exactly as priced

`FieldRef` — owner, field index, type, and a `(psd, pidx)` path with a depth —
replaced the single hard-coded `getelementptr … i32 0, i32 <idx>` at the four
access sites. A one-element path *is* today's GEP, so it converged
byte-identically on its own, which is what §11 asked of it. Everything below is
built on it, and §9 was two more functions on top rather than a feature of its
own.

### 15.2 BF-1 is one walk, and that is the whole design

The plan named four questions a bitfield asks of a struct: its size, the element
list the type line prints, each field's GEP index, and each field's bit
position. The first version answered them in four places and they disagreed
within the hour. `struct-walk` answers all four in a single pass over the fields
and hands back nine outputs; `struct-walk-size`, `struct-tail-pad`,
`field-ir-index` and `field-bit-offset` are one line each on top of it, and
`emit-struct-type-line` reads the same walk per field. A layout cannot drift
from the GEP that addresses it because there is only one of them.

The walk carries a bit cursor and a byte cursor at once. A *run* of adjacent
bitfields is one opaque `[k x i8]` element written by the field that opens it;
the rest of the run adds nothing to the element list. That is why `field-ir-index`
is not the identity even without `aligned(N)`, and why a non-bitfield member —
or a zero-width one — has to close the open run before it can place itself.

### 15.3 BF-2's `iM` window, and the masks with no constants in them

A bitfield access loads exactly the bytes its bits touch, as an `iM` where
`M = 8·ceil((bit%8 + w)/8)`. A power-of-two window would be simpler and would
read past the end of a struct whose last field crosses its declared type's
boundary — reachable in a packed struct, which is exactly where `epoll_event`
and friends live.

The mask is built as `lshr iM -1, (M-w)` rather than printed as a literal, so a
64-bit field never needs a constant the IR printer would have to format, and the
same three lines serve every width from 1 to 64. Sign extension is `shl` then
`ashr`; the unsigned case stops after the `and`.

`.&` refuses a bitfield outright. That is C's own constraint (`&s.bits` is
ill-formed there too), so it is a faithful diagnostic rather than a Nucleus gap.

### 15.4 Three psABI divergences the cross-target oracle found

C leaves bitfield allocation implementation-defined, so **matching the platform
compiler is the specification**, and the platforms do not agree. All three of
these were found by `clang --target=` disagreeing on a shape, not by reading a
spec:

1. **AVR drops the declared-type rule entirely** (GCC's
   `PCC_BITFIELD_TYPE_MATTERS` is off there). `struct { uint32_t a:5; b:5; c:5; }`
   is 2 bytes on AVR and packs straight across byte boundaries. What survives is
   only the zero-width member's boundary, and there it is a **byte**, not the
   declared type: `struct { uint32_t x:1; uint32_t :0; uint32_t y:1; }` is 2 on
   AVR and 8 everywhere else.
2. **`packed` drops the crossing rule but NOT the zero-width one.**
   `packed { uint32_t x:1; uint32_t :0; uint32_t y:1; }` is 5 bytes on x86-64 —
   the `:0` still forces bit 32. The first implementation skipped the whole rule
   under `packed` and got 1.
3. **aarch64 gives every bit-field its declared type's alignment, named or not,
   and keeps the zero-width one's even under `packed`.** The SysV targets give an
   *unnamed* bit-field no alignment at all. `struct { int8_t c; uint32_t :3; }`
   is 2 bytes and alignment 1 on x86-64, 4 and 4 on aarch64. `bf-align-contrib`
   is the one function that holds this, and it is the reason
   `struct-align-suffix` must skip bit-fields when it computes what LLVM would
   have derived: a run's element is `[k x i8]`, which LLVM aligns at 1.

The test shapes are named A–K for a reason: A–H alone cannot tell those four
rules apart. I, J and K are the discriminating ones and were added after the
first three came back green on a wrong implementation. [`s16-bf-layout-cross-target`,
11 shapes × 5 targets]

### 15.5 What it bought

`FILE` is 216 bytes with `_flags` at 0 and `_lock` at 136, matching `cc` exactly
— the marquee blocked type of the 111-type census, and the one
cheader-parser-vs-libclang.md §8.3 held up as the argument for linking libclang
in for offsets. clang is the oracle either way; it does not have to be linked in
to be one.

### 15.6 Two tests retired, and a Makefile root fix

`l1-member-opaque` and `l1-member-fails-safe` asserted that `l1_m_bad_body`
stayed opaque, with a bitfield as its unreadable member. Bitfields are readable
now, so the fixture's subject moved to a multi-declarator member (`int a, b;`) —
still refused, and still on the same line, so the table of pinned line numbers
did not move. `l2-libc-opaque` asserted `FILE` was opaque; it is now
`l2-libc-file-layout`, a positive check of size and two offsets against `cc`.

`make update-bootstrap` left `build/nucleusc.ll` and `build/nucleusc` derived
from the *previous* boot compiler, so the next `make bootstrap` diffed a stale
stage1 against a fresh stage2 and reported a divergence that was really that
staleness. Fixed at the root — the target now drops both artifacts — rather than
written down as a workaround.

### 15.7 Pinned by

`make test` (`s16-bf-layout-cross-target`, `-values`, `-import`, `-file`,
`-cheader-roundtrip`, `-refusals`), `make bootstrap`, `make abi-test`,
`make layout-test`, `make check-headers`, `make avr-test`.

---

## 16. What the anonymous-member phase turned out to be

### 16.1 The premise held: it was two functions on FR-1

§9 predicted that the layout half already existed and only name lookup was
missing. That is what it was.

- **AN-1 — import.** A member declaration that reaches its `;` with no
  declarator and an aggregate type is a C11 anonymous member. It gets a minted
  name, `__anon.N`, in the same shape BF-4 already used for `__bf.N`. Nothing
  else about the import changed: `lookup-or-make-anon-struct` had been building
  the member's type since Stage 10.
- **AN-2 — lookup.** `struct-field-ref` falls through a direct miss into a
  depth-first search over members whose name is minted, prepending one
  `(sd, field-ir-index sd i)` level per step. `field-ref-outer` is that prepend.
  Two hits at any depth is C's own ambiguity, reported by the emit sites, which
  are the ones holding a line.

`__anon.` and `__bf.` are unspellable as C or Nucleus identifiers, which is what
makes "the compiler minted this name" a decidable question with no extra state.

**Two details the shape of the path forced.** A union member sits at offset 0,
so a union level of the chain contributes no GEP at all — `field-ref-outer`
returns its argument unchanged for one, and `member-field-ref` zeroes the depth
of a ref into a union. And `owner` is read for exactly one question — is this
load packed — so a packed level anywhere in the chain has to win it.

### 16.2 The `defstruct` surface, and the one place it is not a superset of C

`(:anon T)` declares an anonymous member of an already-declared type; the name
minted is `__anon.<field index>`, deterministic so the layout prescan and the
emission agree on it. The lookup is the same one the importer's members use, so
nothing else was needed.

C cannot spell this. An anonymous member in C is written by inlining its *body*,
so a member naming a declared type has no standard rendering, and
`--emit-cheader` refuses it with that reason rather than emitting something a C
compiler would reject. This is the only place in §§6–9 where Nucleus admits a
declaration C does not.

`(:anon (struct a:i32 b:i32))` — an inline anonymous struct type, which *is* C's
own spelling — works on the import and codegen side, and is refused on export by
the same rule. **Found and not fixed:** `--emit-cheader` renders any field of an
inline `(struct …)` type as `void*`, member or not, which is a silent wrong
layout for a by-value member. It predates this work and is unrelated to `:anon`
(`(defstruct Outer (pt (struct x:i32 y:i32)) tag:i32)` exports the same way);
the `:anon` refusal keeps it from being reached through the new surface. Fixing
it is a `type-node-to-c-decl` item: render the body inline, as clang does.

### 16.3 C1a rode along, because §11's acceptance test needed it

`cmsghdr` was the last blocked type and the blocker was a flexible array member
— `[]` with no extent. `(array T -1)`, not `(array T 0)`: **zero is already the
prescan's provisional-length marker**, and `type-to-ir` asserts that one never
reaches IR. -1 prints `[0 x T]` and sizes as 0. That collision is the only
non-obvious thing in the whole item, and it cost the ten lines the estimate gave
it plus a fourth argument on `c-array-declarator` so the flexible form is
admitted in member position only.

`l2-layout-unfoldable` asserted `[]` was refused; that row became
`l2-layout-flex-array`, a positive check of the type line and of `sizeof`
against `cc`.

### 16.4 The census closed

All nine of cheader-parser-vs-libclang.md §1's blocked types lay out:
`sigaction`, `sigevent`, `__pthread_cleanup_frame`, `_pthread_cleanup_buffer`
(FP-4), `max_align_t` (PK-3), `_IO_FILE`/`FILE` (BF-4), `sigcontext`, `rusage`
(AN-1/AN-2), `cmsghdr` (C1a). **111 of 111.** `sigcontext` is 256 bytes,
`rusage` 144, `cmsghdr` 16 — all matching `cc`. [`s16-an-census`,
`s16-an-census-sizeof`]

### 16.5 Pinned by

`make test` (`s16-an-import`, `-census`, `-census-sizeof`, `-defstruct`,
`-refusals`, plus `l2-layout-flex-array`), `make bootstrap`, `make abi-test`,
`make layout-test`, `make check-headers`, `make avr-test`.
