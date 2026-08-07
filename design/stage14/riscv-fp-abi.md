# RV-6 — riscv64 lp64d hard-float struct flattening

Closes the FP-flattening gap RV-3 deferred (`riscv-linux.md` §RV-3 and its
CORRECTION block). Found by running `make abi-test` **natively on riscv64
hardware** for the first time: `mixed_get` (8.5 → 7.0), `farr2_make`
(1.50,2.25 → 2.25,0.00), `farr2_sum` (3.75 → 2.25).

## 1. The rules being implemented

riscv64 lp64d (XLEN=64, FLEN=64), hardware floating-point calling convention.
An aggregate is first **flattened**: nested structs and arrays are expanded into
their scalar members recursively. A **union is never flattened** (psABI). If the
flattened member list has exactly one or two entries, these apply in order:

1. one FP real (≤ FLEN) → passed as that FP scalar, if 1 FPR is available
2. two FP reals (each ≤ FLEN) → two FP scalars, if 2 FPRs are available
3. one FP real + one integer (≤ XLEN), **either order** → FP in an FPR and the
   integer in a GPR, if 1 FPR *and* 1 GPR are available

Anything else — 3+ members, a union, an over-wide member, or **insufficient
registers** — falls back to RV-3's integer convention (≤ 2×XLEN in GPRs, larger
by reference). Returns use the same rules against a0/a1/fa0/fa1, which are
always available, so **return classification never depends on the register
state**.

Variadic arguments are passed per the *integer* convention regardless of type —
no FP registers, no flattening.

Register budget: 8 GPRs (a0-a7) and 8 FPRs (fa0-fa7) for arguments.

## 2. Why this is mostly a classification change

`AbiInfo`'s COERCE1/COERCE2 carry **arbitrary IR type strings** in `reg0`/`reg1`
— x86_64's SSE path already emits `double` and `<2 x float>` through them. So
"pass this struct in fa0+fa1" is already expressible: COERCE2 with
`reg0="float", reg1="float"` lowers to `define {float,float} @f(float, float)`,
and LLVM's RISC-V backend assigns fa0/fa1 by its own CC. The emitter needs no
new kind.

Worked shapes:

| C type | flattened | AbiInfo | LLVM |
|---|---|---|---|
| `struct {float f;}` | 1 FP | COERCE1 `float` | `float` |
| `struct {double a,b;}` | 2 FP | COERCE2 `double`,`double` | `{double,double}` |
| `struct {float v[2];}` | 2 FP (array flattens) | COERCE2 `float`,`float` | `{float,float}` |
| `struct {int32 i; float f;}` | int+FP | COERCE2 `i32`,`float` | `{i32,float}` |
| `struct {float f; int32 i;}` | FP+int | COERCE2 `float`,`i32` | `{float,i32}` |

Note `{float v[2]}` is **two separate FPRs** on riscv64, where x86_64 SysV packs
it into one SSE eightbyte as `<2 x float>`. Same source struct, different
lowering — which is exactly why this cannot reuse `abi-class-eightbyte`.

## 3. The one structural blocker: hardcoded offset 8

The COERCE2 reconstruction assumes reg1's bytes live at **offset 8** (the second
SysV eightbyte) and emits `getelementptr i8, ptr %slot, i64 8` at **five**
sites:

- `abi-emit-param-prologue` (store the incoming reg1 into the slot)
- `emit-struct-ret`, by-pointer COERCE2 path
- `emit-struct-ret`, first-class COERCE2 path
- `abi-arg-frag` (load reg1 for a call argument)
- `abi-emit-struct-call` (store the returned reg1 into the slot)

A flattened member is at its **field offset** — 4 for `{i32,f32}` and
`{float[2]}`, not 8. So `AbiInfo` gains `off1:i32`, set to 8 on every existing
path (byte-identical) and to the member offset on a flattened riscv aggregate.
All five sites read `(ii off1)`.

This is the whole reason a "just classify differently" patch would silently
corrupt the second member.

## 4. Register counting

`abi-classify` is **pure** today and is called for returns, parameters and
arguments alike — and is called *twice* for the same entity at three sites
(`abi-emit-param-prologue` 394/395, `abi-arg-frag` 521/522,
`nucleusc.nuc` 915/916). A consuming classifier would double-count there, so
the split is:

- **`abi-classify (t)`** — unchanged signature, pure. Classifies as if all
  registers are available. Correct for returns and for every non-riscv target.
- **`abi-classify-arg (t)`** — consults and decrements the ambient state, then
  returns the same AbiInfo shape. On a non-riscv target it tail-calls
  `abi-classify` and touches nothing (byte-identical).

Ambient state, beside `g-form-line` (`src/nucleusc.nuc`): `g-abi-gpr-left`,
`g-abi-fpr-left`, `g-abi-varargs`. The invariant every caller must honour:

> **Every walk over a function's parameter or argument list calls
> `abi-args-begin` first, then `abi-classify-arg` once per element in
> declaration order** — and `abi-args-varargs` when it crosses into the
> variadic tail.

Two walks over the same signature (a `define`'s parameter list and its
prologue loop are separate loops) each reset and re-derive independently; they
agree because they see the same types in the same order.

The three duplicated `abi-classify` calls collapse to one first — they are
redundant today and become wrong under consumption.

Consumption per classified argument (riscv only):
- ABI-DIRECT integer/pointer ≤ XLEN → 1 GPR
- ABI-DIRECT FP scalar ≤ FLEN → 1 FPR if available, else 1 GPR
- flattened rule 1 → 1 FPR; rule 2 → 2 FPRs; rule 3 → 1 FPR + 1 GPR
- integer-convention COERCE1 → 1 GPR; COERCE2 → 2 GPRs
- ABI-MEMORY → 1 GPR (the pointer)
- anything with no registers left → stack; the counters floor at 0

**CORRECTION (RV-6c, measured against clang).** The table above is missing one
debit: **an ABI-MEMORY *return* spends a GPR before the first argument is
classified**, because its hidden `sret` pointer is passed in a0. clang's
`RISCVABIInfo::computeInfo` starts the argument walk from `NumArgGPRs - 1`
when the return is indirect, for exactly this reason. The omission is not
academic — it is the difference between

```c
struct Big sret7_mixed(long a,…,long g, struct Mixed m);   /* sret + 7 longs */
```

lowering `m` as `i64` (clang, and now Nucleus: sret + 7 = 8 GPRs spent, so
rule 3 cannot take its GPR) and as `{i32,float}` (what the table as written
predicts, since 8 − 7 = 1 GPR appears to remain). `abi-args-begin` therefore
takes the return's `AbiInfo` — null when the caller does not have it — and
starts from 7 rather than 8 for an ABI-MEMORY return.

One clang rule is deliberately **not** implemented: a variadic argument whose
alignment is `2 × XLEN` consumes an aligned even/odd GPR *pair*
(`NeededArgGPRs = 2 + (ArgGPRsLeft % 2)`). No Nucleus type has 16-byte
alignment — there is no `i128` and struct alignment maxes out at 8 — so the
condition is unreachable. It becomes live the day a 16-byte-aligned scalar or
aggregate exists.

## 5. Call-site inventory

Walks that must adopt `abi-args-begin` + `abi-classify-arg`:

| site | what it walks |
|---|---|
| `nucleusc.nuc` `emit-defn` signature loop (`abi-print-param`) | `define` parameters |
| `nucleusc.nuc` `emit-defn` prologue loop (`abi-emit-param-prologue`) | same params, second walk |
| `nucleusc.nuc` `macro-jit-ensure-decl` (ProgDefn declare) | captured signature |
| `nucleusc.nuc` `emit-call-with-args` (`abi-arg-frag`) | call arguments |
| `nuch.nuc` `emit-nuch-declare-import` | `.nuch` declare params |
| `cheader.nuc` C declare emitter | C header declare params |
| `repl.nuc` `repl-declare-union-ctors` | REPL arm-constructor params |

**RV-6c note:** the original table listed `nucleusc.nuc:10927` and the
`emit-defn` signature loop as separate rows; they are the same loop, so there
are **seven** walks, not eight. Locate them by function name — the line numbers
were stale before this section was implemented.

Return positions (`abi-ret-ir`, `g-fn-ret-abi`, `abi-emit-struct-call`'s info,
`repl-declare-union-ctors`' `ret-info`, `emit-nuch-declare-import`'s `ret-info`,
the cheader declare's `ret-info`, `macro-jit-ensure-decl`'s `ret-info`, and
`emit-call-with-args`' own return classification) keep plain `abi-classify` —
returns always have their registers. `emit-call-with-args` **hoisted** its
return classification above the argument loop (RV-6c) so `abi-args-begin` can be
told about the `sret` GPR; the value is reused verbatim at the call emission
below, so the return is still classified exactly once.

## 6. Staging

- **RV-6a** — `off1` on AbiInfo + the five GEP sites read it. Inert on its own
  (every path still sets 8). Gate: `make bootstrap` byte-identical.
  **Status: Done** (2026-08-06). `AbiInfo.off1` added (`compiler-types.nuc`),
  initialised to 8 in `abi-classify`'s prologue — the sole allocator, so no path
  can leave it unset — and all five sites GEP by it. `make bootstrap`
  byte-identical, `make abi-test` PASS.
- **RV-6b** — `abi-riscv-flatten` + the classification branch, with full
  register availability assumed. Fixes the three failing fixtures. Gate:
  cross-emitted riscv64 IR shows the table in §2; hosted IR byte-identical.
  **Status: Done** (2026-08-06). `RvFlat` (`compiler-types.nuc`) +
  `rv-flat-add` / `rv-flatten-type` / `abi-riscv-fp-classify` (`src/abi.nuc`),
  tried in `abi-classify` ahead of RV-3's integer path and gated on
  `abi-is-riscv`. Verified **against clang's own RISCVABIInfo** rather than
  against the spec alone: a header-free reference C file covering every rule was
  lowered with `clang --target=riscv64-unknown-linux-gnu -emit-llvm` and
  compared to the same shapes in Nucleus. Nine of ten agree exactly —
  `f_f1` `float`, `f_d1` `double`, `f_dd` `{double,double}`, `f_farr2`
  `{float,float}`, `f_nest` `{float,float}` (nested struct flattens),
  `f_mixed` `{i32,float}`, `f_mixedrev` `{float,i32}` (order preserved),
  `f_longmix` `{i64,double}`, `f_pair` `i64`. x86_64 lowering of the identical
  structs stays SysV (`<2 x float>`, `i64` for `Mixed`), `make bootstrap`
  byte-identical, `make test` 424/424, `make abi-test` PASS.
- **RV-6c** — the ambient state, `abi-classify-arg`, and the §5 call sites.
  Gate: a fixture that exhausts the FP registers agrees with C.
  **Status: Done** (2026-08-07). `g-abi-gpr-left` / `g-abi-fpr-left` /
  `g-abi-varargs` beside `g-form-line` (`src/nucleusc.nuc`), with the invariant
  stated at the declaration. `abi-classify` is now a wrapper over
  **`abi-classify-avail (t gpr fpr)`** (the former body) and stays pure;
  **`abi-classify-arg`** consults the counters, classifies, and debits through
  **`abi-rv-consume`**, and on a non-riscv target tail-calls `abi-classify` and
  touches nothing. `abi-args-begin` / `abi-args-varargs` / `abi-take-regs`
  complete the set, all in `src/abi.nuc`.

  Three details worth keeping:

  - **The variadic tail needed no separate code path.** "Integer convention, no
    flattening, no FP registers" falls out of classifying with an FP
    availability of **0**, because every rule in §1 needs at least one FPR.
    `abi-classify-arg` computes `eff-fpr` once and passes it to both the
    classifier and the consumer, so a vararg float cannot be charged an FPR the
    classifier already refused it.
  - **The register cost is read from the decision, not re-derived.** `AbiInfo`
    gained `rvfp` (0 none / 1 / 2 / 3 = which §1 rule fired), set by
    `abi-riscv-fp-classify` — which now *returns* that rule code rather than a
    bare 1. The alternative, inferring FP-ness by `strcmp`-ing `reg0`/`reg1`
    against `"float"`/`"double"`, would have been a second copy of the rule
    (conventions.md's "mirror a call, not the logic").
  - **The double-`abi-classify` collapse came first**, as planned: three sites
    (`abi-emit-param-prologue`, `abi-arg-frag`, the ProgDefn declare emitter in
    `nucleusc.nuc`) classified twice to get `info` and `kind`. A grep confirmed
    there were no others. `abi-arg-frag`'s unmaterialized-StrView early return
    is charged explicitly as one pointer (`(abi-classify-arg ty-ptr)`, result
    discarded) — classifying the StrView type there would have charged two
    GPRs for a fragment that passes one.

  Verified: `make bootstrap` byte-identical, `make test` 428/428 (424 prior +
  RV-6d's 4), `make abi-test` PASS, and a fresh clang comparison covering the
  §2 table plus FPR exhaustion, GPR exhaustion, the sret debit and a variadic
  call — every classification decision agrees (see §8 for the three
  integer-convention *spellings* that still differ). The emitted riscv64 module
  also round-trips through `llc -mtriple=riscv64 -mattr=+m,+a,+f,+d,+c`.
- **RV-6d** — docs + a permanent fixture pinning the gap so §1's rules cannot
  silently regress the way RV-3's deferral note did. **Status: Done**
  (2026-08-07). `tests/fixtures/rv6-fp-abi.nuc` + `run_rv6_fp_abi`
  (`tests/run-tests.sh`) cross-emit the fixture for riscv64 **and** x86_64 and
  assert four groups: `rv6-flatten-rules` (§1's five shapes plus the
  no-FP control), `rv6-register-counting` (FPR/GPR exhaustion and its
  one-register-either-side controls, plus the sret debit),
  `rv6-variadic-integer-convention` (no `float`/`double` operand may appear in
  the variadic call), and `rv6-x86-unchanged` (the same structs still lower as
  SysV — the anti-leak control). Every expected string was taken from clang's
  own output for structurally identical C. `docs/compiler.md` and
  `docs/structs-unions.md` no longer describe riscv64 as integer-convention-only.

## 8. Finding: a 12-byte integer aggregate diverges (RV-3 path, pre-existing)

The clang comparison surfaced one mismatch that is **not** RV-6 scope and was
present before this work: `struct {float a,b,c;}` (12 bytes, 3 members, so
correctly ineligible for flattening under both implementations) lowers as
`[2 x i64]` in clang and `{i64, i32}` in Nucleus. The generalisation is any
aggregate whose size is not a multiple of 8 and which takes the integer
convention: `abi-eightbyte-ir` narrows the tail eightbyte to its exact width
(`i32` here), which is right for x86_64 SysV and is what clang does *not* do on
riscv64.

The two are probably interoperable — both put the data in a0/a1 and the callee
reads the same bytes — and the existing corpus cannot tell, because every
integer aggregate in `tests/abi/` is 8, 16, or >16 bytes with **no 12-byte
case**. It is untested either way, so it is recorded here rather than
"fixed" blind: aligning it is a riscv-only narrowing suppression in
`abi-classify`, and it needs a hardware run to confirm which spelling is
actually required.

**RV-6c widened the observation to three sizes, and it is the same one rule.**
The clang comparison run for RV-6c covered aggregates that reach the integer
convention at 4, 8 and 16 bytes:

| bytes | example | clang | Nucleus |
|---|---|---|---|
| 4 | `struct {float f;}` past FPR exhaustion, or as a vararg | `i64` | `i32` |
| 8 | `struct {int a,b;}` | `i64` | `i64` |
| 12 | `struct {float a,b,c;}` | `[2 x i64]` | `{i64, i32}` |
| 16 | `struct {double a,b;}` past FPR exhaustion, or as a vararg | `[2 x i64]` | `{i64, i64}` |

Only the 8-byte case agrees. The generalisation is that on riscv64 clang
coerces an integer-convention aggregate to **whole XLEN units** — one `i64`, or
`[N x i64]` — while `abi-eightbyte-ir` narrows each eightbyte to its exact
width and `AbiKind` splits two eightbytes into two separate parameters. Both are
right for x86_64 SysV; neither matches clang on riscv64 except by coincidence at
exactly 8 bytes.

The 4-byte and 16-byte rows are **newly reachable** because of RV-6c: before
register counting, an FP-bearing aggregate never fell back to the integer
convention, so only integer-only aggregates (the 8- and 12-byte rows) could get
here. Nothing regressed — the rule is unchanged — but the population it applies
to grew. Still out of scope for the same reason as before: no test in either
direction, and the fix (suppress the narrowing and emit `[N x i64]` on riscv)
needs a hardware run to confirm it is required rather than merely
clang-shaped. `tests/fixtures/rv6-fp-abi.nuc` pins the current spelling, so a
deliberate change to it will show up as a fixture edit rather than silently.

## 7. Verification constraint

There is **no riscv64 hardware in the development container**. RV-6a/b/c can be
verified here only by (a) hosted byte-identical bootstrap, and (b) inspecting
cross-emitted `--target=riscv64-unknown-linux-gnu --emit-llvm` IR against the
§2 table and against what `riscv64-linux-gnu-gcc -S` does with the same C. The
execution gate (`make abi-test` natively, or `make riscv-abi-test` under qemu
once the container gains `libc6-dev-riscv64-cross`) must be run by the user on
the riscv64 machine. Do not report this closed on cross-emission evidence alone.

### Finding: the anti-leak control was itself host-dependent

Running `make test` on the riscv64 machine produced `FAIL rv6-x86-unchanged` —
a **test bug, not an ABI bug**. `run_rv6_fp_abi`'s SysV lane ran bare
`--emit-llvm` and rode the default target, so on riscv64 hardware it compiled the
fixture with the riscv rules and then reported correct riscv lowering
(`{ float, float }`, two flattened operands) as a leak against its `<2 x float>`
expectation. Every line in the failure dump is the riscv lowering this stage
deliberately introduced.

Fixed by naming `--target=x86_64-pc-linux-gnu` on that lane. The generalized rule
is in `context/conventions.md`: in a cross-emission gate the triple is the thing
under test and must never be ambient on *any* lane, including the one matching
the author's host. This is the same "a triple is not a host" error as the RV-2
link-driver guard, one layer out — and it is the more dangerous spelling, because
the gate passes on the machine it was written on and so looks verified.

Note what this does **not** tell us: the failure was raised by a `grep` against
cross-emitted IR, so it is still not execution evidence. The `make abi-test`
gate above remains open.
