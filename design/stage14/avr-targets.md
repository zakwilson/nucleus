# Stage 14 — AVR microcontroller targets

Nucleus has promised microcontroller targets since Stage 8 ("Targets could
later include 32-bit machines, microcontrollers" — stage8/platform.md; "Out of
scope until later: … microcontrollers (no libc)"), and Stage 9 restated it
("Nucleus must be able to target other platforms, including microcontrollers"
— stage9/cleanup.md). This doc investigates what that actually requires for
8-bit AVR parts and designs the work. **Cross-compilation only**: the compiler,
its JIT, and macro expansion keep running on the host — the existing
`g-target`/`g-host-target` split (stage8/platform.md Phases A–B) is exactly the
architecture this needs, and it is already in place.

Two reference devices, chosen to span the two AVR eras:

| | ATtiny1634 | AVR32DD20 |
|---|---|---|
| Core / avr-gcc family | classic tinyAVR, `avr35` | modern AVR-Dx, `avrxmega3` |
| LLVM 19 `-mcpu` | `attiny1634` (listed) | **not listed** → family `avrxmega3` |
| Flash / SRAM | 16 KB / **1 KB** | 32 KB / 4 KB |
| Flash mapped into data space | no (needs LPM/progmem) | **yes** (0x8000–0xFFFF) |
| Hardware multiplier | no | yes |
| crt/specs source | stock avr-libc | avr-libc ≥ 2.2 or Microchip DFP |

The ATtiny1634 stresses the constrained/Harvard end (consts-in-RAM cost, no
MUL); the AVR32DD20 stresses the toolchain-support end (no LLVM device entry,
newer libc requirement) but its mapped flash dissolves the progmem problem.

---

## 1. Ground truth — toolchain (verified 2026-07-02, container LLVM 19.1.7)

1. **The AVR backend is already built into the system LLVM** (`llvm-config
   --targets-built` includes `AVR`; it is an official backend since LLVM 12,
   so any distro LLVM has it). `llc -mtriple=avr -mcpu=attiny1634
   -filetype=obj` produces a valid `ELF 32-bit … Atmel AVR 8-bit` relocatable
   — verified end to end from clang-emitted IR.
2. **Device coverage**: LLVM 19 knows 351 AVR CPUs including `attiny1634`
   (family `avr35`), but **no AVR-Dx/Ex devices at all**. The AVR32DD20
   compiles with `-mcpu=avrxmega3`, its family core — ISA-correct, since
   codegen only needs family features (MUL, MOVW, memory-mapped flash);
   device-specific memory layout comes from the *linker* (device linker
   script + crt), not codegen.
3. **Datalayout** (same string for every AVR cpu):
   `e-P1-p:16:8-i8:8-i16:8-i32:8-i64:8-f32:8-f64:8-n8-a:8` — 16-bit pointers,
   **every ABI alignment is 1 byte**, and **program memory is address space
   1** (`P1`). `LLVMPointerSize` on it returns 2, so the existing descriptor
   derivation works unchanged.
4. **Functions live in addrspace(1)** — verified: `@g = global ptr @f` is an
   IR *verifier error* on AVR (`'@f' defined with type 'ptr addrspace(1)' but
   expected 'ptr'`). Direct calls are unaffected; any code that treats a
   function as a *value* (stores it through a plain `ptr`) does not verify.
5. **Const data defaults to addrspace 0 = RAM**: clang places `const char
   msg[]` as an AS0 `constant`, which the crt copies from flash to SRAM at
   startup on classic AVR. On `avrxmega3` parts the linker places rodata in
   flash-mapped data space, so it costs no RAM.
6. **Wide arithmetic and floats lower to libgcc libcalls** — verified:
   `__mulhi3`, `__divmodhi4`, `__muldi3`, `__addsf3`. Linking therefore
   requires AVR libgcc, i.e. an installed `avr-gcc` toolchain, which also
   provides the device crt (`crt<mcu>.o`, interrupt vector table with weak
   `__vector_N` defaults, `__do_copy_data`/`__do_clear_bss`), device linker
   scripts, and avr-libc. **None of this is in the container** (Debian ships
   `gcc-avr`, `avr-libc`, `binutils-avr`; versions to be verified at rebuild
   — AVR-Dx crt/specs need avr-libc ≥ 2.2 or a Microchip Device Family Pack
   via `-B`).
7. **`double` mismatch**: clang's AVR `double` is 32-bit (avr-gcc
   compatible). Nucleus `f64` is LLVM `double` = genuine IEEE 64-bit, lowered
   to `__adddf3`-style libcalls whose libgcc implementation is only 64-bit
   when avr-gcc's `-mdouble=64` multilib is present. `f32` is safe
   (`__addsf3` verified); `f64` is at-risk.
8. `qemu-system-avr` emulates ATmega328P/2560-class boards (not attiny1634 or
   Dx parts); simavr's device list needs checking. Simulator choice is an
   AVR-0 ground-verify item.

## 2. Ground truth — compiler (surveyed 2026-07-02)

1. **Target descriptor**: `Target{triple, datalayout, ptr-size, ptr-align}`
   (src/compiler-types.nuc:486-490). `make-target-for-triple`
   (src/nucleusc.nuc:8939-8961) derives triple/datalayout/pointer-size from
   LLVM via `LLVMCreateTargetMachine(target, triple, "", "", …)` — **empty
   CPU/features, no way to pass one**, and `ptr-align := ptr-size` (AVR wants
   1). The same empty-CPU call is made again in `compile-and-link`
   (src/nucleusc.nuc:9226), with **Reloc hardcoded to PIC(2)** — wrong for
   AVR (static).
2. **Backend registration**: `targets-init-all` (src/nucleusc.nuc:8923-8935)
   registers X86/AArch64/ARM via the `LLVMInitialize<Arch>{TargetInfo,Target,
   TargetMC,AsmPrinter}` quartet declared in src/llvm.nuch:2-13. AVR is one
   more quartet — a single registration point.
3. **`ptr-int-ir`/`ptr-int-type` are binary 32-vs-64**
   (src/type-utils.nuc:105-110): `i32` if `g-target-ptr-bytes==4` else `i64`.
   At 2 bytes they wrongly answer `i64`. These are the canonical
   size_t/intptr helpers behind `usize`/`ssize`, `sizeof` results, and niche
   encoding — **the single most pervasive 16-bit correctness bug**.
   `type-size`/`int-width` (src/type-utils.nuc:118-196) are otherwise
   descriptor-driven and fine.
4. **`emit-qq-helpers` hardcodes a 64-bit Node into the *target* module**
   (src/nucleusc.nuc:9118-9156, flushed to the output streams at 9260-9261
   when `g-qq-used`): `{i32,i32,i64,ptr,ptr,ptr}`, `malloc(i64 40)`,
   `align 8`. Already flagged as the 32-bit blocker (stage9/cleanup.md:44).
   The separate host copy (7340-7344) is correct as-is.
5. **`sizeof` and regular struct field offsets are target-correct**:
   `emit-sizeof` emits `getelementptr %Ty, ptr null, i32 1` + `ptrtoint`,
   constant-folded by LLVM against the output module's datalayout
   (src/nucleusc.nuc:2259-2271); field access is named-type GEP. But **union
   member offsets are hand-computed** (src/union-emit.nuc:90 etc.) from
   `abi-sizeof`/`abi-alignof` (src/abi.nuc:23-87), which assume *natural*
   alignment — AVR aligns everything at 1, so hand-computed union layouts
   would be over-padded relative to avr-gcc's C layout (self-consistent, but
   a C-parity divergence).
6. **Niche `?T`/`!T` encoding** (src/union-emit.nuc:495-562): `err E` →
   `inttoptr(0 − E)`, i.e. the top of the data address space. Width follows
   `ptr-int-ir` (correct once #3 is fixed). The "top page is never a valid
   pointer" assumption **holds on classic AVR** (ATtiny1634 data space ends
   at 0x04FF) but **fails on mapped-flash parts**: on the AVR32DD20, flash
   occupies 0x8000–0xFFFF in data space, so a `(ref T)` into the last flash
   bytes aliases small error ids. Needs a reservation strategy (§5 AVR-6).
7. **ABI**: `abi-classify` returns `ABI-DIRECT` immediately for every
   non-aggregate (src/abi.nuc:145-147) — **scalar/pointer-only programs
   bypass ABI classification entirely**. The only target key is
   `abi-is-aarch64` (strstr on the triple); an AVR branch slots in the same
   way.
8. **Emitted programs have zero implicit libc dependencies**: prelude
   structs/macros/templates are inert until used; `malloc`/`free` appear only
   for quasiquote/boxed closures, `printf`+`@llvm.trap` only in `unwrap`
   error paths, error tables only when a `deferror` exists
   (src/nucleusc.nuc:7637-7659). No `main`/`_start` synthesis — the user's
   `(defn main …)` is a plain `define @main`, called by the platform crt
   (avr-libc's crt does exactly this). **A blink-shaped program references no
   runtime symbols at all**, prelude included; `(exclude-prelude)` is not
   even needed.
9. **Link flow**: the compiler emits the object itself
   (`LLVMTargetMachineEmitToFile`, src/nucleusc.nuc:9201-9256) then shells
   out to **hardcoded `clang`** with `-l`/`-L` pass-through only; `-c` stops
   after the object; `--emit-llvm` bypasses everything. No linker choice, no
   `-mmcu`, no linker script, no objcopy hooks.
10. **MCU-relevant surface present**: `volatile` is landed (`(T volatile)` /
    `T:volatile`, volatile load/store with correct align,
    src/nucleusc.nuc:5500-5546); `i8/i16/ui8/ui16` are first-class;
    literal default is `i32` (legalized by the backend; costs code size, not
    correctness). **Missing**: inline asm — none; address spaces — none;
    function attributes/calling conventions from source — none (so
    `signal`/`interrupt` ISR attributes are unexpressible); `defvar` is
    always a mutable `global` — no `constant` emission, no section/alignment
    control (src/nucleusc.nuc:6500-6535).
11. **Host/target hygiene is clean**: batch output layout always flows from
    `g-target`; JIT/CT/macro modules always use `g-host-target`; no compiler
    path computes a target size/offset with the host descriptor. The two
    contaminations are exactly #3 and #4.

## 3. Scope and non-goals

**v1 target profile** (what "AVR support" means at the end of this work):
freestanding programs using scalars, pointers, structs/unions, `volatile`
MMIO, ISRs, static globals, stack locals, and direct calls — compiled to a
linked `.elf` (and `.hex` via script) for both reference devices. Collections
work against a static-buffer arena allocator if wanted (the libc allocator's
`malloc` exists in avr-libc but is discouraged at 1–4 KB of SRAM).

**Out of scope for v1** (each with the enforcement noted in §5): running the
compiler/JIT/REPL on AVR (never a goal); runtime quasiquote (needs heap; the
qq-helper fix in AVR-2 is for *correctness*, not encouragement); function
values / boxed closures / `dyn` (addrspace(1), diagnostic in AVR-6); `f64`
(diagnostic or documented multilib requirement); C struct-by-value interop on
AVR (avr-gcc register-packing ABI deferred); a progmem type system (`(flash
T)` — sketched in AVR-6, deferred; mapped-flash parts don't need it);
`import-only` tree-shaking (stage999-future.md:97 — unnecessary, lazy
emission already yields zero-dep programs).

## 4. Decisions

- **Family `-mcpu` is the device model for codegen; the linker owns the
  device.** No device tables in the compiler. `attiny1634` passes straight
  through to LLVM; `avr32dd20` compiles as `avrxmega3` and the device name
  goes to `avr-gcc -mmcu=` at link.
- **avr-gcc is the link driver on AVR triples** (as clang is on hosted
  triples). It knows the device linker scripts, crt, libgcc, and avr-libc.
  lld's AVR support is not mature enough to replace that stack.
- **Raw-first, diagnose-don't-miscompile**: every v1 gap that cannot be made
  correct cheaply (function values, `f64`) becomes a targeted compile-time
  error on AVR targets rather than a verifier crash or silent wrong code.
- **All changes keyed on the descriptor/triple** so every hosted target's
  output is byte-identical — same invariant as Stage 8 Phase C.

## 5. Design — phases

### AVR-0 — toolchain + ground-verify spike

Add `gcc-avr`, `avr-libc`, `binutils-avr` (and `simavr` or
`qemu-system-misc`) to the container Dockerfile (/home/node/claude-container)
and rebuild. Verify: avr-libc version ≥ 2.2 (else document the Microchip DFP
`-B` flow for the DD part); link the already-verified spike object into an
`.elf` for both devices with `avr-gcc -mmcu=`; `avr-objcopy -O ihex`; pick
the simulator (check simavr's device list for attiny1634; qemu-system-avr
covers only mega parts — an atmega328p smoke target may be the pragmatic
CI device). Everything below assumes this landed.

**Status: DONE (2026-07-16).** Container rebuilt with the AVR toolchain
(installed via Arch `pacman`, not Debian `apt`, since this container is Arch):
`avr-gcc` 14.2.0, `binutils-avr` 2.43.50, `avr-libc` 2.2.1, `simavr` 1.6;
`clang`/`llc` are LLVM 19.1.7 with the `avr` target registered. **avr-libc
version 2.2.1 ≥ 2.2 — the Microchip DFP `-B` fallback is *not* needed.** The
spike (a header-free freestanding C program exercising a `const`/rodata table,
a `noinline` function call, and a 16-bit multiply + non-power-of-two divide;
`/tmp/.../scratchpad/spike.c` during the spike) was driven through the
ground-truth path — `clang --target=avr -Oz -S -emit-llvm` (emits the expected
`e-P1-p:16:8-…` datalayout / `avr` triple) → `llc -mtriple=avr -mcpu=<cpu>
-filetype=obj` → `avr-gcc -mmcu=<device>` → `avr-objcopy -O ihex` — for **all
three** devices, each producing a valid `ELF … Atmel AVR 8-bit` executable and
an Intel-hex file:
- **ATtiny1634** (`-mcpu=attiny1634` / `-mmcu=attiny1634`): links, ihex OK,
  `avr-size` 334 text / 10 data / 2 bss. `avr-objdump` confirms a genuine
  `call … <compute>` (ground-truth item 4 — plain calls unaffected by the
  addrspace(1) function-value hazard) and that **both `__mulhi3` *and*
  `__udivmodhi4` libgcc symbols are linked in** (item 6 — no hardware
  multiplier on this part, so the multiply is a real libcall). The `const
  table` lands in **`.data` (RAM)**, i.e. crt-copied from flash at startup —
  the classic-AVR consts-in-RAM cost of item 5, confirmed.
- **AVR32DD20**: codegen via family `-mcpu=avrxmega3` (LLVM has no Dx device
  entry, as predicted), linked with **`-mmcu=avr32dd20`** — **avr-gcc knows the
  exact device** (`device-specs/specs-avr32dd20` present, alongside
  `avr16dd20`/`avr64dd20`), so **no `-B` DFP flow and no family-mmcu fallback
  were required**. Links, ihex OK, `avr-size` 364 text / 2 data / 2 bss. On
  this mapped-flash part the same `const table` lands in **`.rodata` (flash
  data-space, addr 0x8164) costing zero RAM** — `.data` shrank 10→2 bytes vs
  the ATtiny — the modern-AVR half of the item-5 split, confirmed.
- **ATmega328P** (`-mcpu=atmega328p` / `-mmcu=atmega328p`): the pragmatic
  simulator target. Links, ihex OK, `avr-size` 316 / 10 / 2. Has a hardware
  multiplier so only `__udivmodhi4` is pulled in (multiply inlined).

**Simulator: `simavr` on ATmega328P.** `simavr --list-cores` does **not**
include `attiny1634` (nor any AVR-Dx part), and **`qemu-system-avr` is not
installed** in the container — so, exactly as the doc anticipated, ATmega328P
is the pragmatic sim device. `simavr -m atmega328p spike-m328.elf` ran the
program and **exited cleanly (code 0, not a 10s timeout)**: the spike ends with
`cli; sleep` (interrupts-off SLEEP), which simavr treats as a permanent-sleep
deadlock and quits gracefully; `avr-objdump` of `main` shows the full expected
sequence `call <compute>` → volatile `sts 0x010A/0x010B, …` (store of the
result to `g_sink`) → `cli` → `sleep`, so the clean exit proves execution
reached the end of `main`. (This `simavr` build prints no explicit sleep-quit
message; exit-0-vs-timeout is the observable.) The `.hex` also loads and runs.

**Gaps / deviations from the plan:** (1) container is Arch, so the toolchain
came from `pacman`, not the Dockerfile `apt` line the plan names — the
Dockerfile at `/home/node/claude-container` is not reachable from this
execution environment (the standing blocker noted in the RV-0 progress row);
the packages are nonetheless present and verified. (2) `attiny1634` has no
simulator here (simavr lacks it, qemu-system-avr absent) — ATmega328P is the
CI smoke device, as the doc suggested; running the *reference* devices needs
hardware or a DFP-aware simulator, deferred to AVR-8. (3) No blockers hit: the
Dx part needed neither the DFP `-B` flow nor an `avrxmega3` link fallback.
Nothing in AVR-0 was left open; **AVR-1** (backend registration + `--mcpu`/
reloc plumbing in the Nucleus compiler) is the next milestone and is untouched
by this spike (no `src/`/`lib/` changes — pure toolchain verification).

### AVR-1 — backend registration + CPU/reloc plumbing

- src/llvm.nuch: declare the `LLVMInitializeAVR{TargetInfo,Target,TargetMC,
  AsmPrinter}` quartet; add the four calls to `targets-init-all`
  (src/nucleusc.nuc:8923).
- New flag `--mcpu=<cpu>` → `Target` gains `cpu:ptr` (empty for host
  targets), threaded into **both** `LLVMCreateTargetMachine` calls (8947 and
  9226). Features string stays empty for now.
- Reloc model: static (0) when the triple starts with `avr`, PIC otherwise —
  keyed default, no new flag.
- `ptr-align`: derive from the datalayout (`LLVMABIAlignmentOfType` on `ptr`,
  or `LLVMPreferredAlignmentOfType`) instead of `:= ptr-size`. x86-64/aarch64
  answer 8 either way — byte-identical on hosted targets.
- Gate: `--target=avr --mcpu=attiny1634 --emit-llvm` on a scalar example
  emits the AVR datalayout/triple and `llc` accepts it.

**Status: DONE (2026-07-16).** Backend registration + `--mcpu`/reloc/ptr-align
plumbing landed, all keyed on the triple/descriptor so hosted targets are
byte-identical. Files touched:
- `src/llvm.nuch`: declared the `LLVMInitializeAVR{TargetInfo,Target,TargetMC,
  AsmPrinter}` quartet (after the ARM quartet) plus three datalayout-query APIs
  (`LLVMABIAlignmentOfType`, `LLVMInt8Type`, `LLVMPointerType`) for the
  ptr-align derivation.
- `src/nucleusc.nuc`: added the four `LLVMInitializeAVR*` calls to
  `targets-init-all`; new `--mcpu=<cpu>` flag → `g-mcpu-override` global,
  parsed beside `--target=`; new `reloc-for-triple` helper (Static(0) when the
  triple starts with `avr`, PIC(2) otherwise); `make-target-for-triple` gained
  a `cpu` param, keys reloc off the triple, and now derives `ptr-align` from
  `LLVMABIAlignmentOfType` on a `ptr` type (x86-64/aarch64 still answer 8, AVR
  answers 1) rather than `:= ptr-size`; `target-init` passes the mcpu string
  (host `""`, cross-target the `--mcpu` value — normalized in a value position
  to avoid a mixed `StrView`/`ptr` `if`-join collapsing to void); the
  `compile-and-link` `LLVMCreateTargetMachine` threads `(g-target cpu)` and the
  keyed reloc.
- `src/compiler-types.nuc`: `Target` struct gained `cpu:ptr` (empty for host
  targets; never null/compared, so `ptr` not `CStr`).

**One codegen fix was required to meet the gate** and is worth recording,
because it revises a ground-truth assumption. Ground truth §2.8 claimed a
minimal program references *zero* runtime symbols; that is now **stale** — every
program (even `(defn main ():i32 (return 0))`, unless it `(exclude-prelude)`s,
which also strips the arithmetic operators) force-emits the arena/intern/node
runtime from `lib/node.nuc`. That runtime uses `unsafe/ptr+`, and `emit-ptr-add`
(src/union-emit.nuc) was internally inconsistent: it decided whether to
sign-extend the offset by comparing `(type-size offset) < g-target-ptr-bytes`
but **hardcoded** the GEP index type and the sext target to `i64`. On any
non-8-byte target those disagree — on AVR an i32 offset is *not* `< 2`, so the
sext was skipped, yet the GEP index was still annotated `i64` with the i32
value: malformed IR that `llc` rejects. Fixed by routing both the coercion and
the annotation through `ptr-int-ir`/`ptr-int-type` (sext if the offset is
narrower than ptr-int, trunc if wider). This is byte-identical on hosted targets
(ptr-int is `i64` there, reproducing the historical `sext i32 -> i64` + `i64`
GEP; the trunc branch is dead until AVR-2 makes `ptr-int-ir` ternary). Note the
GEP index still uses the *current binary* `ptr-int-ir` (i64 on AVR), so AVR
pointer arithmetic is emitted at i64 width — valid, `llc` legalizes it, but the
i16 optimization remains **AVR-2's** job (bullet 1); AVR-2 flipping `ptr-int-ir`
to i16 is exactly what activates the new trunc branch.

**Gate verification.** `--target=avr --mcpu=attiny1634 --emit-llvm examples/
arith.nuc` emits `target datalayout = "e-P1-p:16:8-…"` / `target triple =
"avr"`; piping through `llc -mtriple=avr -mcpu=attiny1634 -filetype=obj`
produces a valid `ELF 32-bit … Atmel AVR 8-bit` relocatable. Same for the
AVR-Dx family core `--mcpu=avrxmega3` (the deviceless AVR32DD20 path). Hosted
byte-identical proven two ways: `make bootstrap` (stage1.ll == stage2.ll) and an
old-boot-vs-new `--emit-llvm` diff on `ptr+`-heavy examples (array/comb-storage/
hello) — empty. `make test` 185/185 (180 baseline + 5 new AVR gates:
`target-avr`, `avr-emit-{attiny1634,avrxmega3}`, `avr-llc-{…}` — the llc step is
conditional on `command -v llc`), `make abi-test` PASS. No `update-bootstrap`
needed. **Object-file/link for AVR (`compile-and-link`) is wired but not gated
here** — this phase is IR-emission-only; the avr-gcc link driver is AVR-3.

### AVR-2 — 16-bit correctness

- **`ptr-int-ir`/`ptr-int-type`** (src/type-utils.nuc:105-110): ternary —
  2→`i16`, 4→`i32`, else `i64`. Mechanical; audit the (few) other direct
  `g-target-ptr-bytes` comparisons for the same binary assumption.
- **`emit-qq-helpers` target copy** (src/nucleusc.nuc:9118-9156): compute the
  Node struct string, malloc size, and store alignments from the descriptor
  (ptr-size/ptr-align + the fixed i32/i32/i64 header). For 8-byte targets the
  computed strings must reproduce today's bytes exactly (size 40, `align 8`)
  — byte-identity is the gate. This also closes the long-standing 32-bit
  blocker (stage9/cleanup.md:44).
- **Alignment model**: decide between (a) accepting the natural-alignment
  hand tables (unions over-padded vs avr-gcc but self-consistent — document
  as a C-parity caveat) and (b) adding an align table / datalayout query to
  `abi-alignof`. Recommendation: (a) for v1 with the caveat recorded;
  struct-by-value C interop is out of scope anyway (§3), and named-struct
  GEPs are already datalayout-correct.
- Gate: bootstrap byte-identical on x86-64; an AVR-targeted example using
  `usize`, `sizeof`, and a union round-trips through `llc` cleanly.

### AVR-3 — link driver + build flow

- `compile-and-link` (src/nucleusc.nuc:9201-9256): key the link command on
  the triple — AVR: `avr-gcc -mmcu=<mcu> <obj> -o <out>` — and add two
  general flags that all targets get: `--linker=<cmd>` (override the driver)
  and `--link-arg=<arg>` (verbatim pass-through, generalizing the existing
  `-l`/`-L` collection). New flag `--mmcu=<device>` supplies the device name
  for the AVR link line (defaults to the `--mcpu` value when that names a
  device, as with `attiny1634`; required separately when `--mcpu` is a
  family, as with `avrxmega3` + `avr32dd20`).
- `.hex` generation (`avr-objcopy -O ihex`) stays in build scripts — the
  compiler's job ends at the `.elf` ("worse is better": no objcopy hook).
- Entry point needs nothing: avr-libc's crt calls `@main` (ground truth §2.8).
- Gate: one command produces a linked `.elf` for each reference device;
  `avr-size` shows a blink program in tens of bytes of data, not hundreds.

**Status: DONE (2026-07-17).** Link-driver + build-flow plumbing landed;
hosted output byte-identical (`make bootstrap` stage1==stage2 first pass — this
change only touches `compile-and-link`'s command line and the argv parser, not
emitted IR). Files touched:
- `src/nucleusc.nuc`: two new override globals `g-linker-override` /
  `g-mmcu-override` beside `g-mcpu-override`; three new prefix-matched argv flags
  in `main` — `--mmcu=<device>` → `g-mmcu-override`, `--linker=<cmd>` →
  `g-linker-override`, `--link-arg=<arg>` routed through the existing
  `add-link-arg`/`g-link-args` mechanism (no second list); `compile-and-link`
  keys the link command on the triple — the driver defaults to `clang` (hosted)
  / `avr-gcc` (AVR triple, `strncmp … "avr" 3`), `--linker=` overrides either
  regardless of triple, and on an AVR triple a `-mmcu=<device>` flag is inserted
  (device := `--mmcu`, else `--mcpu`). The usage string lists the three flags.
- The StrView/ptr join-collapse gotcha (context/conventions.md) was avoided by
  the same value-position idiom `target-init` uses for `--mcpu`: `driver:ptr` is
  initialised to the StrView literal `"clang"` and overridden via statement-form
  `set!`, never a mixed `StrView`/`ptr` value-position `if`.
- **No `.hex`/objcopy hook** (deferred to build scripts, per the "worse is
  better" decision above); no codegen change — this is link-step-only.

**Gate verification.** New fixture `tests/fixtures/avr3-link.nuc` — a
freestanding MMIO blink with `(exclude-prelude)` (so the always-force-emitted
intern/arena/node runtime, which references host-only `perror`/`malloc` and
would fail to link against avr-libc — the AVR-1 correction to ground truth §2.8
— is not emitted; only compiler-builtin special forms/binops are used) plus a
direct `next-pattern` call (the addrspace(1)-safe path, ground truth §1.4). One
compiler command links it to a real `ELF … Atmel AVR 8-bit` executable for both
reference devices: **ATtiny1634** (`--mcpu=attiny1634`, mcpu==device, no
separate `--mmcu`) → `avr-size` **278 text / 0 data / 0 bss**; **AVR32DD20**
(`--mcpu=avrxmega3 --mmcu=avr32dd20`, family codegen + explicit device) → **310
text / 0 data / 0 bss** — a freestanding handful of bytes, not the kilobytes a
pulled-in runtime would add; `avr-objdump` confirms a genuine `call
<next-pattern>`. New harness gate `run_avr3_link` (a real link, not `llc`),
conditional on `avr-gcc` (SKIPs otherwise, keeping its result line non-empty).
`make test` 193/193 (191 baseline + 2 AVR-3), `make abi-test` PASS. Verified the
`--mmcu` value reaches the link line and overrides `--mcpu` (a bogus
`--mmcu=no-such-device-xyz` is rejected by avr-gcc even with a valid `--mcpu`),
and that `--linker=<bogus>` invokes that driver name and fails. Note: avr-gcc
happens to accept `-mmcu=avrxmega3` (an architecture name) so the family case
without `--mmcu` still links (generic xmega3 layout, no device linker script) —
the explicit `--mmcu=avr32dd20` is what selects the device-accurate
`specs-avr32dd20`.

### AVR-4 — MMIO, device definitions, examples

- `lib/avr.nuc`: MMIO idiom on the landed `volatile` support — `reg8`/
  `reg16` read/write helpers over `(cast … addr)` + volatile load/store, and
  bit-set/clear macros.
- Device register files `lib/avr/attiny1634.nuc`, `lib/avr/avr32dd20.nuc`
  (`defconst` addresses — compile-time ints, perfect fit). Hand-written for
  the two reference devices; **`<avr/io.h>` C-header import cannot work**
  (SFRs are macros, not declarations — the header parser sees nothing).
  Future: generate from Microchip ATDF packs; out of scope here.
- `examples/avr-blink.nuc` (+ a UART hello for the simulator device). These
  cannot run under `make test` (host-executed diff harness); they get a
  separate `make avr-test` (AVR-8).

### AVR-5 — ISRs + function attributes

- New top-level directive `(fn-attr <name> "<attr>" …)` attaching LLVM string
  function attributes to a `defn` (house-style precedent: `set-ir-prefix`).
  Emission: an attribute group on the `define`. This is deliberately generic
  (later: `noinline`, `section`, `used`).
- ISRs use LLVM's `"signal"`/`"interrupt"` AVR function attributes (what
  clang lowers `__attribute__((signal)))` to). avr-libc's crt provides the
  vector table with weak `__vector_N` defaults; defining the strong symbol
  overrides — so an ISR is just `(defn __vector_13 () …)` + `(fn-attr
  __vector_13 "signal")`. In the default `user` namespace the name emits
  verbatim, so no ir-name plumbing is needed.
- `lib/avr.nuc` gains `(defisr <vector-number-or-name> …body)` wrapping both.
- Gate: an ISR-using example links, and `avr-objdump -d` shows the vector
  jump and `reti` epilogue.

**Status: DONE (2026-07-17).** The generic `(fn-attr <name> "<attr>" …)`
directive landed, hosted output byte-identical (`make bootstrap` stage1==stage2
first pass — the change is purely additive: a new struct, a new lazily-built
table, a new directive, and one `emit-defn` split whose emitted bytes are
unchanged when no `fn-attr` entry matches). Files touched:
- `src/compiler-types.nuc`: new `FnAttrEntry {name:ptr attr:ptr}` element-struct
  (the §14.5 batch-2 small-table idiom; `name` identity-compared, `attr` only
  printed, both interned so both stay `ptr`).
- `src/nucleusc.nuc`: new `g-fn-attr-table (raw (Vector (ref FnAttrEntry)))`
  global (reset to null in compiler-init, mirroring `g-ns-prefix-table`);
  `fn-attr-add` / `emit-fn-attrs-for` helpers (beside `ns-ir-prefix-set/-get`);
  `emit-fn-attr` directive (beside `emit-set-ir-prefix`, its house-style
  precedent) with a `'fn-attr` arm in the top-level `case hp` dispatch and
  `"fn-attr"` added to `g-special-form-set` (reserved — a defn/defvar cannot
  shadow it); and the `emit-defn` `define`-line suffix, where the historical
  `") noreturn {\n"` / `") {\n"` fprintf was split so a keyword attr (`noreturn`)
  and any string attrs (`emit-fn-attrs-for`) can coexist on one line — verified
  `define void @f() noreturn "signal" {`, `define void @g() noreturn {` (byte-
  identical), and `define i32 @main() {` (no-attr, unchanged).
- `lib/avr/atmega328p.nuc`: added the Timer/Counter1 registers
  (TIMSK1/TCCR1B/TCNT1 + TOIE1/CS10/CS11/CS12) the ISR example configures.
- `examples/avr-isr.nuc`: a TIMER1_OVF ISR (`__vector_13` on the ATmega328P).

**`defisr` decision.** The design sketched `(defisr <vector> …body)` "wrapping
both" as a `lib/avr.nuc` macro. That is **not** provided, because this compiler
does **not expand user macros in top-level position**: the top-level dispatch
matches literal head symbols (`defn`, `fn-attr`, …) *before* any macro expansion,
so a top-level `(defmacro defisr …)` call fails as an unknown top-level form —
verified empirically, and true even for a macro expanding to a *single* `defn`,
let alone the two sibling forms an ISR needs. Rather than build a whole top-level
macro-expansion pass (well beyond AVR-5) or bake AVR-specific `__vector_N`/
`"signal"` logic into a compiler builtin (against the design's layering, which
keeps `fn-attr` generic and `defisr` a lib convenience), the ISR idiom is the two
adjacent top-level forms directly — `(fn-attr __vector_N "signal")` then
`(defn __vector_N ():void …)`, `fn-attr` **first** (consumed at emit-defn time;
no forward-reference prescan for the table). This is documented as the convention
in a block comment in `lib/avr.nuc` and demonstrated in `examples/avr-isr.nuc`.

**Gate verification.** `--target=avr --mcpu=atmega328p --emit-llvm
examples/avr-isr.nuc` emits `define void @__vector_13() "signal" {`. Linking with
the AVR-3 `avr-gcc` driver produces a valid `ELF … Atmel AVR 8-bit` executable
(908 text / 0 data / 0 bss). `avr-objdump -d`: the `__vectors` table slot 13
(byte 0x34 = 13×4) is `jmp 0x2d4 <__vector_13>` — the strong symbol overrode
avr-libc's weak `__bad_interrupt` default — and `<__vector_13>` opens with the
interrupt prologue (`push r0` / `in r0, 0x3f` / SREG save + clobbered-reg saves)
and closes with `out 0x3f, r0` (SREG restore) + `reti`, the return-from-interrupt
instruction the `"signal"` attribute is specifically what causes the AVR backend
to emit (a plain `defn` would end in `ret`). New harness gate `run_avr5_isr`
(link + objdump, gated on avr-gcc/avr-objdump, SKIPs otherwise). `make test`
194/194 (193 baseline + avr5-isr), `make bootstrap` byte-identical, `make
abi-test` PASS.

### AVR-6 — Harvard hazards

- **Function values**: `Target` gains `prog-as:i32` parsed from the
  datalayout's `P<n>` (0 when absent). v1: a targeted compile-time error when
  a function is used as a *value* (not a direct call) and `prog-as ≠ 0` —
  covering `fn`-as-value, `funcall` sources, BoxedFn/`dyn` construction. The
  full fix (emit `ptr addrspace(1)` for function-pointer-typed values and
  audit every vtable/funcall path) is specced as a follow-on; v1 must not
  emit IR the verifier rejects (ground truth §1.4).
- **Rodata placement**: strings are already emitted as `constant`
  (src/nucleusc.nuc:7621-7635). Empirically verify where they land on
  `avrxmega3` (expected: flash-mapped `.rodata`, zero RAM) vs classic AVR
  (RAM copy — *accepted* for v1 within the 1 KB budget, documented). A
  `(flash T)` pointer qualifier (addrspace(1) data + LPM loads) is the real
  classic-AVR fix; sketch only, deferred — the modern parts don't need it.
- **Const globals**: extend `defvar` with a const form (e.g. `(defvar-const
  …)` or a `&const` marker — decide at implementation) emitting `constant`
  instead of `global`. Benefits every target; on mapped-flash parts it keeps
  tables out of RAM entirely.
  **Status: DONE (2026-07-17), including a follow-up gap fix.** Landed as
  `(defvar :const name:type init)` via the AT-1 attribute registry
  (`DECL-ATTR-CONST`). The original landing emitted `constant` storage
  correctly but did not reject `set!` against a `:const` global at compile
  time — `(set! a-const-global v)` still type-checked and emitted an ordinary
  `store` into read-only storage (UB, segfaults at runtime on the host). Fixed
  by adding a distinct `readonly-global:i32` flag on `Sym`
  (`src/compiler-types.nuc`) — kept separate from `is-const`/`const-val`,
  which is the unrelated `defconst` compile-time-substituted-value mechanism
  and would have misrouted ordinary reads through its inline-substitution
  branch. `emit-defvar` sets the flag post-`scope-define` when
  `DECL-ATTR-CONST` is set; `emit-set` now `die-at`s
  (`"set!: cannot assign to '%s' -- declared :const"`) when the flag is set,
  before the RHS is emitted. See `tests/fixtures/avr6-const-mutate-rejected.nuc`.
- **Niche collision on mapped-flash parts** (ground truth §2.6): on the
  AVR32DD20, `err E` encodings 0xFFFF−E alias real flash-mapped addresses.
  v1 mitigation: reserve the top 256 bytes of flash in the link (a one-line
  linker-script/`--link-arg` adjustment in the device build script) and
  document the constraint. Revisit if a niche-layout engine lands (stage10
  C4).

### AVR-7 — ABI + numerics policy

**Status: DONE (Stage 14 AVR-7).** All three sub-items landed; `make bootstrap`
byte-identical on the first pass, `make test` (204) and `make abi-test` green.

- `abi-classify` (src/abi.nuc): add an `abi-is-avr` branch classifying **all
  aggregates as `ABI-MEMORY` with aarch64-style plain-pointer passing** —
  self-consistent for Nucleus↔Nucleus calls, bypassing the SysV eightbyte
  machinery entirely. avr-gcc's register-packing struct ABI (C parity for
  struct-by-value interop) is explicitly deferred; scalar/pointer C interop
  is unaffected (ground truth §2.7).
  *Implemented:* `abi-is-avr` (strncmp-`avr`-prefix, mirroring `abi-is-aarch64`)
  routes every aggregate (any size) to `ABI-MEMORY` right after size/align are
  computed, before the `sz > 16` eightbyte gate. The two MEMORY emission
  branches (`abi-print-param`, `abi-arg-frag`) fold AVR into the aarch64
  plain-pointer path (`(and (= (abi-is-aarch64) 0) (= (abi-is-avr) 0))` gates
  `byval`). `abi-emit-param-prologue`, `emit-struct-ret`, and the callee `sret`
  return-parameter emission are already architecture-neutral (verified) — no
  change. Gate: a ≤16-byte `Point` that a host register-coerces (COERCE1) becomes
  a plain-pointer MEMORY param + `sret` return on AVR (zero `byval`), links via
  avr-gcc (`tests/fixtures/avr7-struct.nuc`, `run_avr7_struct`).
- `f64` on AVR: compile-time error with a message naming the `-mdouble=64`
  multilib escape hatch (revisit when ground-verified against the container's
  avr-gcc). `f32` allowed. `i64` allowed (costly but correct via libgcc).
  *Implemented:* rejected at **both** finalization points (a single-site check
  would miss one) via a shared `avr-reject-f64` helper (src/abi.nuc): an explicit
  `:f64`/`double` annotation in `parse-type-name` (union-registry.nuc), and a
  bare float literal's f64 default in `emit-float` (nucleusc.nuc, since a literal
  never touches `parse-type-name`). Guarded by `in-jit-module == 0` so a macro/CT
  body's compile-time f64 (runs on the host, never emitted into the AVR program)
  is unaffected. `f32`/`i64` confirmed compiling on AVR; `i64` multiply links
  libgcc `__muldi3` into a working `.elf` (ground-verified). Inert on hosted
  targets (byte-identical). Gates: `run_avr7_f64`,
  `tests/fixtures/avr7-{f64-annot,f64-literal,f32,i64}.nuc`.
  *Note (deferred):* the separate C-header type resolver (cheader.nuc's
  `double`→ty-f64) is left unguarded — it is the explicitly-deferred struct/C-ABI
  interop surface, and such an f64-returning C function is uncallable on AVR
  anyway; every Nucleus-source path to f64 (annotations, literals, Nucleus-written
  `declare`/`extern` signatures) is covered.
- Runtime quasiquote on AVR: allowed once AVR-2 makes it correct (it drags in
  `malloc`, which avr-libc provides), but documented as
  budget-inappropriate; no diagnostic.
  *Verified:* qq codegen is correct on AVR (AVR-2's 16-bit fix; `__cons`/`__append`
  emit `malloc(i64 22)` — the 16-bit cell size); no compiler diagnostic blocks it.
  qq's list-cell allocator uses only `malloc` (avr-libc-provided). Caveat for the
  docs-writer: a qq that constructs *quoted-symbol* leaves also pulls in the
  interning/arena runtime (`intern-hash`/`arena-alloc`/`alloc-node`/…), which
  references `perror` (absent from freestanding avr-libc), so such a program fails
  at **link** — the same prelude-runtime-on-AVR constraint the examples already
  side-step with `(exclude-prelude)`, orthogonal to qq itself and unchanged by
  AVR-7. No code added.

### AVR-8 — tests, docs, progress

- `make avr-test`: for each AVR example — compile, link, `avr-size` budget
  assertions (flash/RAM ceilings per device); simulator smoke test (UART
  hello, captured output) for whichever device AVR-0 ground-verified.
  Bootstrap/`make test` remain host-only and untouched.
- `docs/avr.md` (or `docs/cross-compilation.md` §AVR): flags, the two-device
  walkthrough, the v1 profile and its exclusions, the MMIO/ISR idioms.
- design/progress.md row + context/build.md note (AVR link flow, container
  toolchain).

## 6. Verification and bootstrap convergence

Every phase is keyed on triple/descriptor, so hosted-target output must stay
**byte-identical**; the refactors with any risk (ptr-int-ir ternary,
qq-helper parameterization, ptr-align derivation) get the standard
before/after IR diff on `build/nucleusc.ll`. Compiler-source changes shift
the string pool as usual, so each landed phase ends with the standard
reconverging refresh (`make clean && make && make update-bootstrap && make
clean && make && make bootstrap`) plus `make test` and `make abi-test`. New
AVR-side gates are per-phase above; the cumulative definition of done is the
v1 profile (§3) demonstrated on both reference devices — blink on the
ATtiny1634, blink + UART on the AVR32DD20 — with `.elf` size recorded.

## 7. Rejected alternatives

- **A C backend / compiling via avr-gcc.** No C emission exists and it
  contradicts the LLVM-native principle; the LLVM AVR backend is verified
  working in this container.
- **Waiting for LLVM to add AVR-Dx device entries.** Family `-mcpu` is
  ISA-complete; device knowledge (memory map, crt, vectors) belongs to the
  linker stack, which has it today.
- **lld as the AVR linker.** Device linker scripts, crt objects, and libgcc
  ship with binutils-avr/avr-libc and are what every AVR project validates
  against; lld's AVR port is not there.
- **A progmem/addrspace type system in v1.** Large type-system surface
  (pointer qualifier, load lowering, literal placement) whose payoff is
  classic-AVR-only; the modern mapped-flash parts sidestep it. Deferred with
  a sketch (AVR-6), not abandoned.
- **Synthesizing our own crt/vector table.** avr-libc's crt + weak
  `__vector_N` override is standard and battle-tested; emitting our own buys
  nothing and adds a divergence to maintain.
- **`import-only` tree-shaking as a prerequisite** (stage999-future.md:97).
  Ground truth §2.8: emission is already lazy to the point that minimal
  programs reference zero runtime symbols; dead-code concerns are handled by
  `-ffunction-sections`-style linker GC later if ever needed.

## 8. Sequencing and relationship to other stage-14 work

Independent of [type-safety.md](type-safety.md),
[defn-signature.md](defn-signature.md),
[macro-conditional-casts.md](macro-conditional-casts.md), and
[colon-paren-types.md](colon-paren-types.md) — this touches target/link
plumbing and emission width helpers, not the type-annotation surfaces those
docs edit. Critical path: **AVR-0 → AVR-1 → AVR-2 → AVR-3** (after which a
blink `.elf` exists); AVR-4/AVR-5 parallel after AVR-3; AVR-6/AVR-7 harden;
AVR-8 closes. The AVR-2 `ptr-int-ir`/qq-helper fixes are worth landing even
if the rest stalls — they are the 32-bit-target blockers too.
