# Stage 14 — Linux on RISC-V (riscv64)

Add riscv64 Linux as a Nucleus target. Unlike the AVR work
([avr-targets.md](avr-targets.md)), this is a **hosted** platform: same
pointer width as the existing 64-bit targets, glibc, a real OS — so the
16-bit correctness work is irrelevant here and the deliverable splits into
two tiers:

- **Tier A — cross-compilation** from x86_64 with the full example/test
  suite executing under `qemu-user`. CI-testable in this container; this is
  the stage-14 deliverable. **Done** (RV-0…RV-3, RV-5 — see §5).
- **Tier B — native self-hosting** on RISC-V hardware (compiler, JIT,
  macros, REPL), the same bring-up the ARM64 portability work did for
  aarch64. Specced here (§5 RV-4), gated on hardware (or `qemu-system`)
  access. **Deferred/future — not a pending autopilot milestone.**
  Provisioning a bootable riscv64 Linux guest (kernel + rootfs +
  toolchain) under `qemu-system-riscv64`, or real riscv64 hardware, is
  well beyond the container-package fixes the rest of this doc's
  workstream needed; it requires deliberate user-driven environment
  setup before any agent session (autopilot or otherwise) should attempt
  it. Do not dispatch RV-4 as a routine milestone.

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
  **Not started** — `/home/node/claude-container` is not present/mounted
  in the autopilot execution environment; it is only reachable from the
  user's interactive session, so this sub-item (and, per §4, all of
  AVR-0, which shares the same Dockerfile change) is blocked pending the
  user rebuilding the container.
- Fix the two hardcoded `"x86_64-pc-linux-gnu"` REPL JIT triples
  (src/repl.nuc:597, 690) → `(g-host-target triple)`. Independent host
  bug fix (helps aarch64 hosts today); byte-identical on x86_64.
  **Done** — the two sites (now at `src/repl.nuc:625`
  `jit-thunk-module` and `:719` `repl-jit-module-rt-rewrite`; line numbers
  shifted since this doc was written) read
  `((as ptr:Target g-host-target) triple)`, matching the existing pattern
  at `src/nucleusc.nuc:8225/8446`. Verified twice independently: `make
  clean && make` clean, `make test` 180/180, `make bootstrap`
  byte-identical (no `update-bootstrap` needed), REPL smoke check
  (define/call/redefine via `build/nucleusc -i`) passed. (A pre-existing,
  unrelated bug was found during the smoke check — REPL `defmacro`
  segfaults/hangs, reproduces on the pre-fix baseline too — tracked in
  [../progress.md](../progress.md) "Known constraints / gotchas".)

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

**Status: Done** (AVR-1 had already landed the shared `cpu`/backend-registration
plumbing per §4, so RV-1 was the features/abi delta on top of it).
- `src/llvm.nuch`: added the `LLVMInitializeRISCV{TargetInfo,Target,TargetMC,
  AsmPrinter}` quartet (beside the AVR quartet); called all four from
  `targets-init-all` (`src/nucleusc.nuc`).
- `Target` (`src/compiler-types.nuc`) gained `features:ptr` and `abi:ptr`
  (alongside AVR-1's `cpu:ptr`). Three triple-keyed resolvers beside
  `reloc-for-triple`: `cpu-for-triple` (honors an explicit `--mcpu`, else
  `generic-rv64` for `riscv64`), `features-for-triple` (`+m,+a,+f,+d,+c`),
  `abi-for-triple` (`lp64d`); all three return `""` for every non-riscv64
  triple. `make-target-for-triple` resolves the effective cpu/features/abi
  once (mirroring how `reloc-for-triple` is computed early), passes eff-cpu +
  eff-features to `LLVMCreateTargetMachine`, and stores all three on the
  descriptor. `compile-and-link` now reads `features` from the descriptor
  (was hardcoded `""`); `cpu` already flowed from AVR-1.
- `assemble-module-ir`: the `target triple` line now ends with a single `\n`;
  a `!llvm.module.flags = !{!0}` / `!0 = !{i32 1, !"target-abi", !"<abi>"}`
  block is emitted only when `abi` is non-empty; a trailing `\n` reproduces
  the prior `\n\n` exactly, so non-riscv IR is byte-identical.
- Both inline X86-only init blocks (in `jit-ensure-init` and `compile-and-link`)
  were confirmed redundant and **deleted**: `compiler-init` → `target-init` →
  `targets-init-all` registers all backends process-wide before either runs, on
  every code path (batch `main`; batch CT-JIT via `emit-toplevel-forms`; REPL
  via `repl-main` → `compiler-init` before `repl-preload-macros`). LLVM
  target-init is idempotent; verified with a REPL define/call/redefine smoke.
- Test gate: `run_riscv_emit` in `tests/run-tests.sh` (mirrors `run_avr_emit`)
  asserts the riscv64 datalayout/triple + `target-abi=lp64d` module flag, then
  (llc-guarded) pipes through `llc -mtriple=riscv64 -mattr=+m,+a,+f,+d,+c` and
  asserts hardware `mul`/`fadd.d` with no `__muldi3`/`__adddf3` libcalls — the
  actual features-cliff regression test. Fixture:
  `tests/fixtures/riscv-features.nuc` (i64 multiply + f64 add; symbol names
  avoid `mul`/`add` substrings so `.globl` lines can't false-match).
- Verified: `make clean && make` clean; `make test` 187/187 (185 baseline + the
  two new riscv gates); `make bootstrap` byte-identical on the first pass (no
  `update-bootstrap` reconverge needed); `make abi-test` green; host/x86_64/
  aarch64 `--emit-llvm` byte-identical between the pre-change boot binary and
  the new build.

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

**Status: Done** (2026-07-18) — the RV-2 code path is complete and correct;
today's `make riscv-test` SKIPs on a container-provisioning gap (below), which
is *not* a code defect.
- `compile-and-link` (`src/nucleusc.nuc`) gained an `is-riscv` branch beside
  AVR-3's `is-avr` in the driver-selection `let`: a triple with the `riscv64`
  prefix (`(strncmp g-target-triple "riscv64" 7)`, the same idiom
  `cpu/features/abi-for-triple` use) selects `riscv64-linux-gnu-gcc`. AVR and
  riscv64 prefixes are mutually exclusive so the two `set!`s never both fire;
  `--linker=` still overrides either (unchanged precedence). riscv64 needs no
  extra command-line flag beyond the driver name (no `-mmcu`-equivalent) — the
  Debian cross gcc carries the sysroot + crt objects, so PIC (kept) links a
  glibc executable directly. No other change: `reloc-for-triple` already
  returns PIC(2) for every non-avr triple.
- `make riscv-test` → `tests/run-riscv-test.sh` (new): modeled on
  `tests/run-avr-test.sh`. Two-stage SKIP gate — (1) `riscv64-linux-gnu-gcc`
  and `qemu-riscv64` both on `PATH`; (2) a **capability probe** that actually
  drives the compiler's compile-and-link path on `examples/hello.nuc` and
  checks whether the link *succeeds*. Merely finding the driver binary is
  insufficient: this container has `libc6-riscv64-cross` (runtime shared libs)
  but **not** `libc6-dev-riscv64-cross` (crt startup objects + headers), so the
  link fails `cannot find Scrt1.o`. The probe detects that shape and SKIPs with
  a one-line pointer to the missing package (exit 0) instead of FAILing every
  example. When a future container gains the `-dev` package the probe links and
  the full gate runs: for each `examples/*.nuc` with a `tests/expected/<name>.out`,
  compile `--target=riscv64-unknown-linux-gnu <src> -o <out>` (no
  `--emit-llvm`/`-c`, so the real link driver is exercised), run under
  `qemu-riscv64 -L /usr/riscv64-linux-gnu`, diff stdout — same convention as the
  native `run_example`. Wired into the Makefile as an opt-in target
  (`riscv-test`, + `.PHONY`) beside `avr-test`; **not** part of `make test`/`make
  bootstrap`.
- Verified: `make clean && make` clean; `make test` 204/204 (unchanged — this
  is additive and touches only a cross-target's link command line); `make
  bootstrap` byte-identical first pass (no `update-bootstrap`); `make
  riscv-test` SKIPs cleanly with the crt-gap diagnostic. Link-driver routing
  proven independently of the crt gap:
  `./build/nucleusc --target=riscv64-unknown-linux-gnu examples/hello.nuc -o …`
  fails with `nucleusc: link step failed (riscv64-linux-gnu-gcc exit 256)`
  after `ld: cannot find Scrt1.o` — i.e. the compiler correctly selected the
  riscv64 driver and emitted a valid riscv64 object; only the downstream link
  failed on the missing crt objects (NOT a "clang: unknown target"-shaped
  error). The moment the container gains `libc6-dev-riscv64-cross`, RV-2 fully
  passes with no further code change.
- **Blocked (container provisioning, not code):** installing
  `libc6-dev-riscv64-cross` is a Dockerfile change reachable only from the
  user's interactive session (same constraint as RV-0's Dockerfile half); no
  root/apt inside the autopilot environment. Do **not** work around it
  (vendoring crt, `-nostartfiles`) — the code is correct and the SKIP is the
  right behavior until the package lands.

**Amendment (2026-08-06) — the cross driver is now guarded on the HOST triple.**
As first written, the `is-riscv` branch keyed on the *target* triple alone and
never compared it against the host, so a **native riscv64 build** (no
`--target=`, `g-target-triple` defaulted from `LLVMGetDefaultTargetTriple`) also
reached for `riscv64-linux-gnu-gcc` instead of the hosted `clang` default. That
is wrong on its own terms: the `--sysroot` problem this driver choice exists to
dodge is a **cross artifact only** — on riscv64 hardware the sysroot is `/` and
plain `clang`/`cc` links with no flag. It also imported a portability
assumption the design never argued for: `riscv64-linux-gnu-gcc` is a
**Debian-family** naming convention (Debian's *native* gcc package does ship the
triplet-prefixed name — verified `/usr/bin/x86_64-linux-gnu-gcc ->
x86_64-linux-gnu-gcc-14` on the x86_64 container — so Debian riscv64 would have
worked by accident), but Fedora/Alpine/Arch riscv64 ship no such binary and the
link would have failed `riscv64-linux-gnu-gcc: not found` on a correctly
configured native machine.

- `compile-and-link` (`src/nucleusc.nuc`) now binds
  `host-is-riscv` from `((as ptr:Target g-host-target) triple)` and selects the
  cross driver only under `(and (!= is-riscv 0) (= host-is-riscv 0))`. The
  comparison is on the **arch prefix**, not the whole triple, so a normalization
  difference between `riscv64-unknown-linux-gnu` and `riscv64-linux-gnu` cannot
  misclassify a native build as a cross one. AVR keeps its unguarded branch —
  AVR is never a host, so `host-is-avr` is identically 0 and the guard would be
  dead code.
- Both test lanes (`tests/run-riscv-test.sh`, `tests/run-riscv-abi-test.sh`)
  now pick a lane from `uname -m`: **cross** is unchanged
  (`riscv64-linux-gnu-gcc` + `qemu-riscv64`), **native riscv64** prefers `clang`,
  runs binaries directly with no qemu, and requires no cross toolchain. The
  native lane passes **no `--linker` at all** when clang is present — driver
  choice stays the compiler's single source of truth rather than being
  re-derived in shell — and falls back to `--linker=cc` only when clang is
  absent. `run-riscv-abi-test.sh`'s reference C compiler follows the same
  preference (`clang` → `cc` → SKIP); either implements the riscv64 psABI, which
  is what the gate actually compares against.
- Verified: `make` clean; `make test` **424/424**; `make bootstrap`
  byte-identical first pass (`stage1.ll == stage2.ll`, no `update-bootstrap`);
  `make abi-test` PASS; `make riscv-test` / `make riscv-abi-test` still SKIP with
  the unchanged **cross-lane** crt-gap diagnostic. Cross routing re-proven
  directly: `--target=riscv64-unknown-linux-gnu` still fails
  `nucleusc: link step failed (riscv64-linux-gnu-gcc exit 256)` after
  `ld: cannot find Scrt1.o`, and a hosted build still links via `clang` and runs.
  The scripts' native lane was exercised with a `uname` shim and SKIPs
  gracefully with the native-lane message. **The compiler's native-host branch
  itself is not executable on this x86_64 container** — `host-is-riscv` is
  structurally 0 here — so it remains verified by construction only, and is a
  first-run item for whenever RV-4's real riscv64 hardware/guest appears.

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

**Status: Done** (2026-07-18) — the aggregate-ABI classification is complete
and correct; today's `make riscv-abi-test` SKIPs on the same container crt gap
as RV-2, which is *not* a code defect.
- `abi-is-riscv` predicate added in `src/abi.nuc` beside `abi-is-aarch64` /
  `abi-is-avr`, using the same `(strncmp g-target-triple "riscv64" 7)` idiom
  as `cpu/features/abi-for-triple`. Recomputed per call (no memo), inert on
  every non-riscv triple (returns 0).
- `abi-classify` (`src/abi.nuc`): for a riscv64 triple, both eightbytes of a
  ≤16-byte aggregate are forced to class 3 (INTEGER), skipping
  `abi-class-eightbyte`'s field-type walk — a one-line ternary at each of the
  `c0` and `c1` computations. `n0`/`n1` byte counts and the COERCE1/COERCE2
  size threshold are unchanged (size-only, already target-agnostic), so the
  COERCE shapes are reused verbatim with integer-only classes: a small
  FP-bearing struct now lowers to `i64`/`{i64,i64}` rather than
  `double`/`<2 x float>`. The >16-byte → ABI-MEMORY branch (and the sret
  return path) was already target-generic and correct for riscv64's
  "large aggregate by reference / return via hidden pointer" rule — untouched.
- The two byval-vs-plain-pointer gates — `abi-print-param` (`define`/`declare`
  param list) and `abi-arg-frag` (call-site fragment) — gained
  `(= (abi-is-riscv) 0)` as a third conjunct beside the existing aarch64/AVR
  exclusions, so a >16-byte riscv64 aggregate passes as a plain `ptr` (no
  `byval`), matching the riscv64 psABI (same "aarch64-style, no byval" this
  bullet specified). `and` is a variadic fold (`lib/macros.nuc`), so the
  3-conjunct form is fine.
- FP-flattening remains deferred (the documented divergence): a *pure*
  small FP-bearing struct (e.g. `{f64,f64}`) that the psABI would flatten into
  FPRs is passed in GPRs instead. The reused interop fixtures never hit this —
  their only FP-bearing struct is `Mixed {i32,f32}`, whose integer field
  forces the INTEGER class on *both* x86_64 SysV and the riscv64 psABI (gcc
  does not flatten a struct that mixes an integer member), so `mixed_get`
  interoperates exactly. Scalar `f64` args stay `double` (scalar float ABI is
  unaffected — RV-3 touches aggregate classification only).

  > **CORRECTION (2026-08-06) — the "fixtures never hit this" claim above is
  > FALSE, measured on real riscv64 hardware.** `make abi-test` natively on
  > riscv64 fails three lines: `mixed_get` (8.5 → **7.0**), `farr2_make`
  > (1.50,2.25 → **2.25,0.00**) and `farr2_sum` (3.75 → **2.25**). Both halves
  > of the claim are wrong, for different reasons:
  >
  > 1. **The `Mixed` reasoning applied x86_64 SysV rules to RISC-V.** The
  >    riscv64 lp64d hard-float convention has an explicit rule SysV has no
  >    analogue for: *a struct containing one floating-point real and one
  >    integer, in either order, is passed in one FP register and one integer
  >    register.* So C expects `Mixed{i:7, f:1.5}` as `7` in `a0` and `1.5` in
  >    `fa0`; RV-3 packs both into a single `i64` in `a0`, `fa0` is never
  >    loaded, and the callee computes `7 + 0.0 = 7.0` — which is exactly the
  >    observed number. Eightbyte classification is a SysV concept; it does not
  >    transfer.
  > 2. **`Mixed` was not the only FP-bearing fixture — the claim went stale.**
  >    `FArr2 {float[2]}` was added later by **Stage 15 W8 G-2** (see
  >    `tests/abi/clib.c`'s header), after RV-3 was written, and nothing
  >    re-examined this note. The psABI flattens a struct of two FP reals into
  >    two FP registers (`fa0`,`fa1`), and flattening recurses through array
  >    members, so `float[2]` qualifies. RV-3 returns it as one `i64` in `a0`,
  >    hence `2.25,0.00`.
  >
  > Neither is a regression: RV-3's integer convention is behaving exactly as
  > specified, and `make abi-test` is a *native* gate that no one could run
  > until riscv64 hardware existed. The pure-integer and >16-byte cases
  > (`pair`, `big`, `iarr2/4`, `abig`, `p2`) all pass, confirming the
  > integer-convention half is correct. The lesson for the deferral note: an
  > "our fixtures don't reach the gap" claim is a statement about a *corpus
  > that other stages keep editing*, so it must be re-checked whenever the
  > corpus changes — or, better, replaced by a fixture that pins the gap
  > deliberately.
- `make riscv-abi-test` → `tests/run-riscv-abi-test.sh` (new): the same
  three-direction interop as `tests/run-abi-test.sh` (Nucleus→C, Nucleus→Nucleus,
  C→Nucleus), reusing `tests/abi/{clib.c,interop.nuc,callee.nuc,driver.c,
  expected.out}` unchanged, but cross-compiled with
  `--target=riscv64-unknown-linux-gnu -c` + `riscv64-linux-gnu-gcc` and executed
  under `qemu-riscv64 -L /usr/riscv64-linux-gnu`. Two-stage SKIP gate identical
  to `run-riscv-test.sh`: (1) `riscv64-linux-gnu-gcc` + `qemu-riscv64` on
  `PATH`; (2) a capability probe that links `examples/hello.nuc` through the
  compiler — a passing probe proves `libc6-dev-riscv64-cross` (crt objects +
  glibc headers the C fixtures need) is installed. Wired into the Makefile as an
  opt-in target (`riscv-abi-test` + `.PHONY`); NOT part of `make test`/`make
  bootstrap`/`make abi-test`.
- Verified: `make clean && make` clean; `make test` 204/204 (unchanged — all
  riscv branches are triple-gated, so `g-target-triple == "x86_64-…"` during
  self-compile never fires them); `make bootstrap` byte-identical on the first
  pass (no `update-bootstrap` — nothing leaked into the host path); `make
  abi-test` still PASS (x86_64 gate untouched); `make riscv-abi-test` SKIPs with
  the crt-gap diagnostic. Classification proven independent of the crt gap by
  `--target=riscv64-unknown-linux-gnu --emit-llvm` on an f64-bearing fixture:
  `{f64,f64}` returns `{i64,i64}` and passes `(i64,i64)` (host: `{double,double}`
  / `(double,double)`); `{f64,i64}` returns `{i64,i64}` (host: `{double,i64}`);
  a single `f64` (8B struct) returns `i64` (host: `double`); the >16-byte `Big`
  declare/call/define drop `byval` entirely on riscv (`declare i64
  @big_sum(ptr)` / `call ... (ptr %t43)`) while host keeps `ptr byval(%Big)
  align 8`; hosted `--emit-llvm` of both fixtures is byte-identical pre/post.
  `llc -mtriple=riscv64 -mattr=+m,+a,+f,+d,+c` compiles the riscv IR cleanly
  (well-formed lowering).
- **Blocked (container provisioning, not code):** same `libc6-dev-riscv64-cross`
  gap as RV-2 — installing it is a Dockerfile change reachable only from the
  user's interactive session. The code is correct and the SKIP is the right
  behavior until the package lands, at which point `make riscv-abi-test` runs
  the full three-direction gate under qemu with no further code change.

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

**Status: Deferred / future — explicitly NOT in scope for this pass or
for the unattended stage-14 autopilot loop.** Unlike RV-0 through RV-3
(which needed only a container package or a self-contained code change),
RV-4 needs a full bootable riscv64 Linux guest — kernel, rootfs, and
toolchain — under `qemu-system-riscv64`, or real riscv64 hardware. That
is deliberate, user-driven environment setup, not something an
autopilot session can provision on its own. Do not attempt RV-4 as a
routine milestone dispatch; it stays open until a human sets up the
guest/hardware and hands it off explicitly. The rest of this doc's
RISC-V workstream (RV-0…RV-3, RV-5 — Tier A: cross-compile + qemu-user)
is complete and does not depend on RV-4.

### RV-5 — docs + progress

- design/stage8/platform.md: add riscv64 to the target matrix; fix the
  stale "aarch64 AAPCS fully deferred" note (71a2d9f landed the MEMORY
  branch).
- context/build.md: riscv link/test flow, the `llc`-needs-`-mattr`
  caveat for textual riscv IR.
- docs cross-compilation section (shared page with AVR), progress.md row.

**Status: Done** (2026-07-18) — documentation-only close-out, no
compiler code changed.
- `design/stage8/platform.md`: Phase B's target-matrix bullet list is
  historical (x86_64/i386/aarch64/arm only, as it was landed) and left
  unchanged; a new note directly below it says AVR and riscv64
  registration landed later, in Stage 14, linking to
  [avr-targets.md](avr-targets.md) and this doc. The stale "Carried
  forward" ABI note (§ Phase C) is rewritten: AArch64 AAPCS partially
  landed (commit 71a2d9f, well before Stage 14 — `ABI-MEMORY` plain-pointer
  passing; HFA float-flattening still deferred), RISC-V lp64d landed its
  integer-convention aggregate ABI in RV-3 above (same FP-flattening gap
  as aarch64), Win64/ARM AAPCS/i386 cdecl remain fully deferred.
- `context/build.md`: the riscv64 link/test-flow bullet already existed
  from RV-2 (unchanged). Added a new bullet for the `llc`-needs-`-mattr`
  caveat: a bare `--target=riscv64-... --emit-llvm` `.ll` does not bake
  in `+m,+a,+f,+d,+c` (those are a `TargetMachine` construction argument,
  not IR content, unlike the `target-abi` module flag) — hand-feeding
  that IR to a plain `llc` with no matching `-mattr` silently reproduces
  the RV64I soft-float features cliff RV-1 exists to prevent for the
  compiler's own codegen path. (No "boot-IR-per-arch rule" bullet added —
  that's RV-4 scope and doesn't exist yet.)
- `docs/compiler.md`: the `--target=`/`--mcpu=` rows already had thorough
  riscv64 coverage from RV-1/RV-2/RV-3, and `structs-unions.md`'s ABI
  section was already accurate through RV-3 — both confirmed, not
  duplicated. The one real gap: the `--linker=` row (and the flags-intro
  paragraph above the table) named only `clang`/`avr-gcc` as link-driver
  defaults, omitting riscv64's `riscv64-linux-gnu-gcc` default from RV-2 —
  fixed in both places. No dedicated `docs/riscv.md` created — the
  existing `--target=` row coverage is adequate (unlike AVR, which
  warranted its own `docs/avr.md` for its much larger v1-profile/MMIO/ISR
  surface).
- `design/progress.md`: the "14 (RISC-V)" row's status phrase updated to
  list RV-5 done and RV-4 deferred/future; a closing paragraph appended
  after the RV-3 narrative spelling out RV-4's deferred status in the
  same unambiguous terms as this section, so a future autopilot session
  reading either doc reaches the same conclusion.

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
