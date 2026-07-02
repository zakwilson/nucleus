# Stage 14 — Linux on RISC-V (riscv64)

Add riscv64 Linux as a Nucleus target. Unlike the AVR work
([avr-targets.md](avr-targets.md)), this is a **hosted** platform: same
pointer width as the existing 64-bit targets, glibc, a real OS — so the
16-bit correctness work is irrelevant here and the deliverable splits into
two tiers:

- **Tier A — cross-compilation** from x86_64 with the full example/test
  suite executing under `qemu-user`. CI-testable in this container; this is
  the stage-14 deliverable.
- **Tier B — native self-hosting** on RISC-V hardware (compiler, JIT,
  macros, REPL), the same bring-up the ARM64 portability work did for
  aarch64. Specced here, gated on hardware (or `qemu-system`) access.

Scope is **RV64GC / lp64d** (the `riscv64-unknown-linux-gnu` glibc baseline
— what Debian's official riscv64 port ships). rv32/ilp32, the vector
extension, and non-Linux RISC-V are out of scope.

---

## 1. Ground truth — toolchain (verified 2026-07-02, container LLVM 19.1.7)

1. **The RISCV backend is built into the system LLVM** (`llvm-config
   --targets-built`). Datalayout for riscv64-linux:
   `e-m:e-p:64:64-i64:64-i128:128-n32:64-S128` — 8-byte pointers, so
   `ptr-int-ir`, `usize`, `type-size`, and the qq helpers are **already
   correct** for this target as-is.
2. **The features cliff (verified, the load-bearing finding):** LLVM with
   empty CPU/features — exactly what both `LLVMCreateTargetMachine` call
   sites pass today — codegens **bare RV64I**: `i64` multiply becomes a
   `__muldi3` libcall and `double` args pass in *integer* registers
   (soft-float ABI). With `-mattr=+m,+a,+f,+d,+c -target-abi=lp64d` the same
   IR produces `mul a0,a0,a1` and `fadd.d fa0,fa0,fa1`. The failure mode is
   **silent ABI incompatibility with riscv64 glibc (lp64d)**, not an error.
3. **How clang pins this**: per-function attributes
   (`"target-cpu"="generic-rv64"`, `"target-features"="+m,+a,+f,+d,+c,…"`)
   plus the module flag `!{i32 1, !"target-abi", !"lp64d"}`. Nucleus emits
   neither attributes nor module flags today. `llc` errors loudly if the
   `lp64d` flag is present without `+d` — a useful tripwire.
4. **Container gaps**: no `riscv64-linux-gnu-gcc`, no riscv sysroot, no
   `qemu-riscv64`. Debian ships `gcc-riscv64-linux-gnu` (pulls
   `libc6-riscv64-cross`) and `qemu-user` — Dockerfile additions like the
   AVR toolchain (avr-targets.md AVR-0).

## 2. Ground truth — compiler (surveyed 2026-07-02)

1. **Registration**: `targets-init-all` (src/nucleusc.nuc:8923-8935)
   registers X86/AArch64/ARM only; src/llvm.nuch:2-13 declares only those
   quartets. Two *inline* X86-only init blocks also exist —
   `compile-and-link` (9203-9206) and `jit-ensure-init` (7122-7125). Since
   registration is global process state and `targets-init-all` runs at
   startup, those inline blocks should be redundant — **verify at
   implementation** and either delete them or extend them; the safe action
   is adding the `LLVMInitializeRISCV*` quartet to `targets-init-all`.
2. **CPU/features hardcoded empty** at both `LLVMCreateTargetMachine` sites
   (src/nucleusc.nuc:8947, 9226) — the direct cause of ground truth §1.2.
   Reloc PIC(2) is *correct* for riscv64-linux (unlike AVR) — keep.
3. **No module flags anywhere**: `assemble-module-ir` emits only
   ModuleID/source_filename/datalayout/triple (src/nucleusc.nuc:9176-9199).
   The `target-abi` flag belongs right after the `target triple` line
   (9183). The JIT/CT module headers (7374, 7595) need it only for a native
   riscv64 host (Tier B).
4. **Hardcoded host triples in the REPL JIT** — `src/repl.nuc:597`
   (`jit-thunk-module`) and `src/repl.nuc:690` (`repl-jit-module-rt-rewrite`)
   emit the literal string `"x86_64-pc-linux-gnu"` instead of
   `(g-host-target triple)` like the CT/macro paths do. **This is a live bug
   for any non-x86 host today (aarch64 included)** — fix independently of
   RISC-V.
5. **ABI**: `abi-is-aarch64` (src/abi.nuc:18-19, `strstr` on the triple,
   recomputed per call — no memo cache, so a third key needs no invalidation
   care) branches only the `ABI-MEMORY` path: plain `ptr` instead of
   `byval` (194-205 param, 355-360 call site; landed in commit 71a2d9f "Fix
   ARM64 ABI"). The ≤16-byte eightbyte classification is x86_64 SysV applied
   unchanged — real AAPCS64 (HFA) was deferred, and LP64D would be the same
   kind of follow-on (§5 RV-3).
6. **Bootstrap for a new host arch**: `boot/nucleusc.ll` embeds
   `x86_64-pc-linux-gnu`; the `boot-binary` rule (Makefile:92-93) passes no
   `-target` — it relies on the embedded triple. There is **no non-x86 Linux
   boot IR and no documented new-host bring-up recipe**; the closest
   template is `make windows-boot` (Makefile:121-131), which cross-emits
   boot IRs with `--target=… --emit-llvm` from the current compiler, wired
   into `update-bootstrap` so all boot flavors stay in lock-step.
7. **`make abi-test`** (tests/run-abi-test.sh) compiles C with the **host
   `cc`** and **executes natively** — the riscv variant needs the cross gcc
   and `qemu-riscv64`. The main test harness diffs *runtime* output, so it
   can run cross the same way; the recent portability fixes (null-pointer
   printing, temp files) already made expected outputs platform-neutral.
8. **`target-long-size`** (src/cheader.nuc:421) keys LLP64 on
   `strstr "windows"`; riscv64 falls through to LP64 = 8 — already correct.
9. **Stage 8 promised exactly this shape**: platform.md notes any target in
   `llvm-config --targets-built` works once registered, and non-x86_64
   aggregate ABIs "plug in behind `abi-classify` keyed on `g-target`,
   deferred until host-testable" — `qemu-user` is what makes riscv64
   host-testable. (platform.md still lists aarch64 AAPCS as fully deferred;
   71a2d9f partially landed it — fix the stale note in RV-5.)

## 3. Decisions

- **RV64GC/lp64d only**: CPU `generic-rv64`, features `+m,+a,+f,+d,+c`.
  These become per-triple defaults in the target descriptor, not flags the
  user must remember (a `--features=` override can exist, but the default
  must be correct — ground truth §1.2's failure is silent).
- **ABI pinned in the module, features in the TargetMachine.** The
  `"target-abi"="lp64d"` module flag goes into the batch output (survives
  `--emit-llvm`, and `llc` errors loudly on flag-without-`+d` rather than
  miscompiling). Features go through the `LLVMCreateTargetMachine` features
  parameter for the in-compiler object path. Textual-IR consumers that
  bypass the compiler (`llc`-based flows like `make lib-objs`) must pass
  `-mattr` — accepted; if that bites, the fallback is clang-style
  per-`define` attribute groups (riscv-only, so hosted targets stay
  byte-identical either way).
- **Integer calling convention for aggregates in v1** (RV-3): ≤ 2×XLEN in
  GPR coercion, larger by reference. The psABI's hard-float FP-flattening
  for small FP-bearing structs requires stateful (register-counting)
  classification à la clang — deferred, exactly like the aarch64 HFA gap,
  and gated behind `make abi-test` like everything else in abi.nuc.
- **qemu-user is the execution substrate for Tier A** — full test suite,
  not just emission checks.
- **Byte-identical on all existing targets throughout**: the module flag
  and features are emitted only for riscv triples; descriptor/plumbing
  refactors must not perturb hosted-target IR.

## 4. Shared plumbing with the AVR work

[avr-targets.md](avr-targets.md) AVR-1/AVR-3 and this doc's RV-1/RV-2 touch
the same seams: `Target` gaining `cpu` (AVR) + `features`/`abi` (RISC-V),
both `LLVMCreateTargetMachine` sites, backend registration, and the
triple-keyed link driver with `--linker=`/`--link-arg=`. **Whichever
workstream lands first implements the shared plumbing**; the second becomes
a small delta. If neither is scheduled first explicitly, land the plumbing
with RV-1 — it is smaller (no new pointer-width class) and immediately
CI-verifiable end-to-end under qemu.

## 5. Design — phases

### RV-0 — container + host-portability fix

- Dockerfile: `gcc-riscv64-linux-gnu`, `qemu-user`; rebuild. Verify
  `qemu-riscv64 -L /usr/riscv64-linux-gnu` runs a cross-compiled C hello.
- Fix the two hardcoded `"x86_64-pc-linux-gnu"` REPL JIT triples
  (src/repl.nuc:597, 690) → `(g-host-target triple)`. Independent host
  bug fix (helps aarch64 hosts today); byte-identical on x86_64.

### RV-1 — registration + features/ABI plumbing

- src/llvm.nuch: declare the `LLVMInitializeRISCV{TargetInfo,Target,
  TargetMC,AsmPrinter}` quartet; add to `targets-init-all`; audit the two
  inline X86-only init blocks (ground truth §2.1) — delete if redundant.
- `Target` gains `cpu`, `features`, `abi` (empty for existing triples;
  `generic-rv64` / `+m,+a,+f,+d,+c` / `lp64d` when the triple starts with
  `riscv64`). Thread cpu/features into both `LLVMCreateTargetMachine`
  calls. (Shared plumbing — see §4.)
- `assemble-module-ir`: after the `target triple` line (nucleusc.nuc:9183),
  emit `!llvm.module.flags` with `target-abi` when the descriptor's `abi`
  is non-empty.
- Gate: `--target=riscv64-unknown-linux-gnu --emit-llvm` output runs
  through `llc -mattr=+m,+a,+f,+d,+c` producing `fadd.d`/`mul` (no
  libcalls); existing-target IR byte-identical (no flag, no features).

### RV-2 — cross link + qemu test lanes

- `compile-and-link`: triple-keyed link driver (shared with AVR-3) —
  riscv64-linux triples link via `riscv64-linux-gnu-gcc` (or `clang
  --target=… --sysroot=…`; pick whichever the container verifies first).
  PIC stays.
- `make riscv-test`: run the standard example suite cross-compiled and
  executed under `qemu-riscv64 -L /usr/riscv64-linux-gnu`, diffing the
  same `tests/expected/` outputs (already platform-neutral, ground truth
  §2.7).
- Gate: full example suite green under qemu.

### RV-3 — aggregate ABI (integer convention)

- `abi-is-riscv` predicate beside `abi-is-aarch64`; classification branch
  in `abi-classify`: aggregates ≤ 16 bytes → coerce to `i64`/`[2 x i64]`
  (reusing the COERCE1/COERCE2 shapes with integer-only classes); > 16
  bytes → indirect plain `ptr` (aarch64-style, no `byval`); returns > 16
  bytes → `sret`. This *is* the psABI's varargs convention, so varargs
  come along for free.
- FP-flattening (small FP-bearing structs in FPRs) deferred with the
  aarch64 HFA gap — documented divergence for by-value FP-struct C
  interop only; scalar/pointer interop is exact.
- `make riscv-abi-test`: the abi-test harness with cross `cc` + qemu
  execution.
- Gate: riscv abi-test green; existing `make abi-test` untouched.

### RV-4 — Tier B: native self-hosting (hardware/qemu-system gated)

- `make riscv-boot` modeled on `windows-boot`: cross-emit
  `boot/nucleusc-riscv64-linux-gnu.ll` from the current compiler; wire
  into `update-bootstrap` so all boot flavors regenerate together.
- Makefile: select the boot IR per host arch (`uname -m`; x86_64 keeps
  `boot/nucleusc.ll`) in `boot-binary`/`ensure-boot` — this is the missing
  new-host bring-up recipe (ground truth §2.6) and benefits aarch64 too.
- Native verification on hardware or `qemu-system-riscv64`: `make && make
  test && make bootstrap`, REPL + macro JIT (ORC/LLJIT on riscv64 ELF uses
  JITLink — expected to work on LLVM 19, **verify empirically**;
  repl_shim.c is portable setjmp/longjmp).
- JIT module headers (7374, 7595) already use `(g-host-target triple)`;
  with RV-0's repl.nuc fix the native REPL path is triple-clean. Whether
  the JIT modules also need the `target-abi` flag natively — verify on
  hardware (LLJIT applies host defaults; the tripwire from ground truth
  §1.3 will say loudly).

### RV-5 — docs + progress

- design/stage8/platform.md: add riscv64 to the target matrix; fix the
  stale "aarch64 AAPCS fully deferred" note (71a2d9f landed the MEMORY
  branch).
- context/build.md: riscv link/test flow, boot-IR-per-arch rule, the
  `llc`-needs-`-mattr` caveat for textual riscv IR.
- docs cross-compilation section (shared page with AVR), progress.md row.

## 6. Verification and bootstrap convergence

Existing-target byte-identity is the invariant for every phase: module
flag, features, and ABI branches are all keyed on riscv triples, so
`build/nucleusc.ll` must not change until source edits themselves shift the
string pool (standard reconverging refresh per landed phase). New gates:
RV-1's llc round-trip, RV-2's qemu example suite, RV-3's qemu abi-test.
Tier B's definition of done is the ARM64-parity bar: native `make`, `make
test`, `make bootstrap` fixed point on a riscv64 host.

## 7. Rejected alternatives

- **Relying on default features** ("it links, ship it") — ground truth
  §1.2: the default is bare RV64I with a *silently wrong* float ABI. The
  entire design exists because this fails quietly.
- **Per-function attribute groups as the primary features mechanism**
  (clang-style). More emission churn on every `define`; the TM features
  param + module flag cover the in-tree object path and ABI pinning with
  two localized changes. Kept as the fallback if `llc`-based textual-IR
  flows prove too error-prone.
- **Full LP64D FP-flattening in v1.** Requires register-counting
  classification state (clang tracks GPR/FPR availability during
  classification); the aarch64 precedent already accepts this gap, and
  `abi-test` scopes what's claimed.
- **Waiting for hardware.** `qemu-user` exercises the full test suite for
  Tier A; only Tier B (JIT/REPL) genuinely needs a native environment.
- **rv32.** No mainstream distro userland; `ptr-int-ir` already handles
  4-byte pointers if it's ever wanted; nothing in this design precludes it.
- **A separate riscv Makefile/build script.** The per-arch boot-IR
  selection folds into the existing `boot-binary` rule and fixes the
  undocumented aarch64 bring-up story at the same time.

## 8. Sequencing and relationship to other stage-14 work

Independent of the CP/MC/S/T backbone ([staging.md](staging.md)) — this
touches target plumbing, abi.nuc, and the Makefile, not the
type-annotation surfaces. It joins **AVR on the parallel hardware track**,
sharing the §4 plumbing: recommended order within the track is **RV-0 →
RV-1 → RV-2** (giving the track a CI-verifiable hosted target early), then
AVR-1..3 as a delta on the shared plumbing, then RV-3/AVR-4+ as they
schedule. RV-0's repl.nuc fix and RV-4's per-arch boot selection are
worth landing regardless of RISC-V ambition — they close real gaps for
aarch64 hosts today.
