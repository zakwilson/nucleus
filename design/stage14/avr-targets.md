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
- **Niche collision on mapped-flash parts** (ground truth §2.6): on the
  AVR32DD20, `err E` encodings 0xFFFF−E alias real flash-mapped addresses.
  v1 mitigation: reserve the top 256 bytes of flash in the link (a one-line
  linker-script/`--link-arg` adjustment in the device build script) and
  document the constraint. Revisit if a niche-layout engine lands (stage10
  C4).

### AVR-7 — ABI + numerics policy

- `abi-classify` (src/abi.nuc): add an `abi-is-avr` branch classifying **all
  aggregates as `ABI-MEMORY` with aarch64-style plain-pointer passing** —
  self-consistent for Nucleus↔Nucleus calls, bypassing the SysV eightbyte
  machinery entirely. avr-gcc's register-packing struct ABI (C parity for
  struct-by-value interop) is explicitly deferred; scalar/pointer C interop
  is unaffected (ground truth §2.7).
- `f64` on AVR: compile-time error with a message naming the `-mdouble=64`
  multilib escape hatch (revisit when ground-verified against the container's
  avr-gcc). `f32` allowed. `i64` allowed (costly but correct via libgcc).
- Runtime quasiquote on AVR: allowed once AVR-2 makes it correct (it drags in
  `malloc`, which avr-libc provides), but documented as
  budget-inappropriate; no diagnostic.

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
