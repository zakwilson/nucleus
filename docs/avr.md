# AVR Microcontroller Targets (`lib/avr.nuc`, Stage 14)

Nucleus cross-compiles freestanding programs for 8-bit AVR microcontrollers.
The compiler, its JIT, and macro expansion always run on the host — there is
no AVR host mode — but `--target=avr` produces a linked `.elf` for a real (or
simulated) AVR part. This doc is a practical guide to that workflow: the
relevant flags, a two-device walkthrough, what the v1 language/library
surface supports and excludes, and the MMIO/ISR idioms. For the full design
rationale see [design/stage14/avr-targets.md](../design/stage14/avr-targets.md).

Two devices anchor the v1 support matrix, chosen to span the two AVR eras:

| | ATtiny1634 | AVR32DD20 |
|---|---|---|
| Core / avr-gcc family | classic tinyAVR, `avr35` | modern AVR-Dx, `avrxmega3` |
| LLVM `-mcpu` | `attiny1634` (named device) | not listed — family `avrxmega3` |
| Flash / SRAM | 16 KB / 1 KB | 32 KB / 4 KB |
| Flash mapped into data space | no (RAM-resident consts) | yes (0x8000–0xFFFF) |

A third device, the ATmega328P, is the pragmatic CI/simulator target:
`simavr` (the container's AVR simulator) can execute it, while neither the
ATtiny1634 nor any AVR-Dx part is in `simavr --list-cores`. The UART and ISR
examples below target it for exactly that reason.

## Flags

The AVR-relevant compiler flags are documented in full in
[Compiler Reference — Compiler Flags](compiler.md#compiler-flags)
(`--target=`, `--mcpu=`, `--mmcu=`, `--linker=`, `--link-arg=`); this section
just orients them for AVR specifically.

- `--target=avr` selects the AVR backend, the AVR datalayout (16-bit
  pointers, byte alignment throughout, program memory in address space 1),
  and the static reloc model.
- `--mcpu=<cpu>` is the **LLVM codegen** CPU/family — `attiny1634` for a
  device LLVM knows by name, `avrxmega3` for the AVR-Dx family core (LLVM 19
  has no per-device AVR-Dx entries; family codegen is ISA-complete, since
  device-specific memory layout comes from the linker, not codegen).
- `--mmcu=<device>` is the **link-line** device name passed to avr-gcc
  (`-mmcu=<device>`), which selects avr-gcc's device-specific linker script
  and startup code. It defaults to the `--mcpu` value, which is sufficient
  when `--mcpu` already names an exact device (`attiny1634`); a family core
  like `avrxmega3` still links without it (a generic family layout), so pass
  `--mmcu=` explicitly whenever you need the device-accurate linker script
  (e.g. `avr32dd20`).
- `--linker=`/`--link-arg=` are general flags, not AVR-specific, but two AVR
  uses are worth knowing: the link driver defaults to `avr-gcc` on any `avr`
  triple (vs. `clang` on hosted triples), and `--link-arg=` is how you apply
  the AVR32DD20 niche-collision flash-reservation recipe (see
  [The v1 profile and its exclusions](#the-v1-profile-and-its-exclusions)
  below).

avr-gcc is the AVR link driver because it owns the device linker scripts,
crt (startup code + interrupt vector table), libgcc (software multiply/
divide/float routines), and avr-libc; the compiler's own job stops at
emitting the object file.

## Two-device walkthrough

`examples/avr-blink.nuc` (ATtiny1634) and `examples/avr-blink-dx.nuc`
(AVR32DD20) are the same program — drive one GPIO pin as an output and
toggle it in a busy-wait loop — written against each device's own register
idiom. Both start with `(exclude-prelude)`: the auto-imported prelude
force-emits an intern/arena runtime that references host-only libc symbols
(`perror`, `malloc`) absent from freestanding avr-libc, so any AVR program
that needs to link must opt out (see
[The v1 profile and its exclusions](#the-v1-profile-and-its-exclusions)).

**ATtiny1634** — `--mcpu` alone suffices, since `attiny1634` already names
the exact device for both codegen and the link line:

```
nucleusc --target=avr --mcpu=attiny1634 examples/avr-blink.nuc -o blink.elf
avr-size blink.elf
#    text    data     bss     dec     hex filename
#     858       0       0     858     35a blink.elf
avr-objdump -d blink.elf | less   # sanity-check the disassembly
avr-objcopy -O ihex blink.elf blink.hex   # optional: Intel-hex for a programmer
```

**AVR32DD20** — codegen uses the family core (`avrxmega3`); the exact device
goes to the link line via `--mmcu` so avr-gcc picks its real linker script
(`device-specs/specs-avr32dd20`) instead of a generic family layout:

```
nucleusc --target=avr --mcpu=avrxmega3 --mmcu=avr32dd20 \
         examples/avr-blink-dx.nuc -o blink-dx.elf
avr-size blink-dx.elf
#    text    data     bss     dec     hex filename
#     890       0       0     890     37a blink-dx.elf
```

Both link to a genuine `ELF … Atmel AVR 8-bit` executable with **zero** data/
bss — a freestanding program that avoids the prelude runtime references no
library symbols beyond libgcc's arithmetic helpers, so its footprint is a
couple hundred bytes of flash, not the kilobytes a pulled-in host runtime
would add. `avr-objcopy -O ihex` (for a device programmer) is left to build
scripts — the compiler's job ends at the `.elf`, deliberately: no `--emit-hex`
flag exists.

The code shapes differ meaningfully between the two devices, which is the
point of having both examples: ATtiny1634 (classic AVR) has no dedicated
bit-set/clear/toggle registers, so `avr-blink.nuc` does a
read-modify-write on `PORTB` via `lib/avr.nuc`'s `reg8-toggle-bit!`.
AVR32DD20 (modern AVR-Dx) exposes dedicated `DIRSET`/`OUTTGL` registers, so
`avr-blink-dx.nuc` writes a 1-bit to `PORTA_OUTTGL` directly — no read
needed, and atomic with respect to other bits.

`examples/avr-uart-hello.nuc` (ATmega328P, polled USART0 TX at 9600 baud)
and `examples/avr-isr.nuc` (ATmega328P, a Timer/Counter1 overflow ISR) round
out the four shipped examples; see
[MMIO/ISR idioms](#mmio-and-isr-idioms) below and `make avr-test`
(see [Testing](#testing)) for how they're built, linked, and — for the UART
example — behaviorally verified under `simavr`.

## The v1 profile and its exclusions

**Supported in v1:**

- Scalars and pointers, including `i8`/`i16`/`ui8`/`ui16`/`i32`/`ui32`/`i64`/
  `ui64`, and `usize`/`ssize` (the target pointer-int width — 16-bit on
  AVR, so `sizeof`/`usize` arithmetic is genuinely 16-bit, not silently
  widened).
- Pointer indexing — `aref`, `aset!` and `unsafe/ptr+` — at the target pointer
  width. The index may be any integer type: one narrower than a pointer is
  widened to 16 bits, one wider (`i32`, `i64`) is narrowed to 16, and `usize`
  is already the right width. No cast is needed at the call site, and none of
  the three emits 64-bit arithmetic on your behalf.
- Structs and unions, passed and returned by value through the AVR aggregate
  ABI convention: **every** struct/union (any size) uses the plain-pointer
  `ABI-MEMORY` convention (no `byval`, since AVR has no such calling-convention
  attribute and no register-sized "eightbyte" chunks to classify into) — see
  [Passing and returning structs by value](structs-unions.md#passing-and-returning-structs-by-value).
  This is self-consistent for Nucleus-to-Nucleus calls; it is not
  byte-for-byte identical to avr-gcc's own register-packing struct-by-value
  ABI (C struct-by-value interop is explicitly deferred — see below).
- `:volatile` MMIO — `(ptr :volatile T)` loads/stores through `deref`/
  `ptr-set!` compile to `load volatile`/`store volatile`; see
  [Volatile qualifier](types.md#volatile-qualifier). This is what `lib/avr.nuc`'s
  register helpers are built on.
- ISRs, via the generic `fn-attr` top-level directive (see
  [MMIO/ISR idioms](#mmio-and-isr-idioms) below and the `fn-attr` row in
  [Top-Level Forms](toplevel.md)).
- `:const` flash-resident globals — `(defvar :const name:type init)` emits an
  LLVM `constant` instead of `global`; see
  [Const globals](types.md#const-globals). On a mapped-flash part
  (AVR32DD20) this keeps a table out of RAM entirely; on classic AVR it still
  lands in flash as `.rodata` but is copied to RAM at startup by the crt (a
  cost, not a correctness issue — see the rodata-placement note below).
- `f32` arithmetic (`__addsf3`-class libcalls, confirmed working).
- `i64` arithmetic (costly — links libgcc's `__muldi3`-class 64-bit software
  routines — but correct).
- Runtime quasiquote, if you accept the cost: the qq cons-cell allocator
  (`__cons`/`__append`) is 16-bit-correct on AVR and only needs `malloc`
  (avr-libc provides it). A quasiquote that constructs *quoted-symbol*
  leaves additionally pulls in the interning/arena runtime (which needs
  `perror`, unavailable freestanding) — the same prelude-exclusion
  constraint every AVR program already has to navigate, not something
  specific to qq.

**Not supported in v1** (each a targeted compile-time diagnostic, never a
silent miscompilation or an opaque LLVM verifier crash — the "raw-first,
diagnose-don't-miscompile" design decision):

- **Function values, boxed closures, and `dyn`.** AVR functions live in
  program memory — LLVM address space 1 — so materializing a function as a
  plain data pointer (rather than calling it directly) is an LLVM verifier
  error on this target. A direct call is unaffected. Using a function as a
  value dies with:

  ```
  cannot use function '<name>' as a value on this target: functions live
  in program memory (address space 1) and cannot be materialized as a data
  pointer -- call it directly instead
  ```

  Constructing a `BoxedFn`/`dyn` value (type erasure) dies similarly:

  ```
  <what> materializes a function as a data pointer, which is unsupported
  on this target: functions live in program memory (address space 1) --
  boxed closures, dyn, and function values are not available on AVR in v1
  ```

  The full fix (emitting `ptr addrspace(1)` throughout the vtable/funcall/
  BoxedFn machinery) is out of v1 scope.
- **`f64`.** AVR has no hardware double; both an explicit `f64`/`double`
  annotation and a bare float literal's default type are rejected at compile
  time:

  ```
  f64 is not supported on AVR by default (8-bit target, no hardware
  double); use f32, or a custom avr-gcc build with the -mdouble=64
  multilib if you need genuine f64
  ```

  See [Built-in Types](types.md#built-in-types). This check applies only to
  code actually emitted for the AVR target module — `f64` arithmetic inside
  a `defmacro`/`compile-time` body always runs on the host and is unaffected
  regardless of `--target=`.
- **avr-gcc's register-packing struct-by-value C interop ABI.** Nucleus's
  own AVR aggregate ABI (above) is internally consistent but does not match
  avr-gcc's C calling convention for structs passed by value; calling a C
  function that takes/returns a struct by value across the FFI boundary on
  AVR is deferred.
- **A `(flash T)` progmem pointer type.** Sketched in the design but
  deliberately deferred: it would need a new pointer qualifier, `LPM`-based
  load lowering, and literal-placement control, and the payoff is
  classic-AVR-only (the mapped-flash Dx parts, like the AVR32DD20, don't
  need it — their flash is already addressable as ordinary data-space
  memory).
- **The AVR32DD20 mapped-flash niche collision**, mitigated by a documented
  link recipe rather than a compiler fix (see next paragraph).

**Rodata placement** differs by device and is worth knowing about even
though it's not a v1 exclusion: on classic AVR (ATtiny1634) a string literal
or other `constant` lands in `.data` — its load address (LMA) is in flash but
its virtual address (VMA) is in RAM, because the crt copies flash→RAM at
startup — an accepted SRAM cost within the 1 KB budget. On a mapped-flash
part (AVR32DD20) the same data lands in a dedicated flash-mapped `.rodata`
with VMA==LMA — genuinely free, zero RAM cost.

**Niche-collision mitigation on mapped-flash parts.** `!T`/`?T` niche
encoding represents an error/none case as `inttoptr(0 − id)` — an address
near the top of the pointer's address space. On the AVR32DD20, flash is
memory-mapped at 0x8000–0xFFFF, so the very top of that range aliases small
error-id encodings. v1 mitigates this by reserving the top 256 bytes of
flash in the link, rather than a niche-layout compiler fix:

```
--link-arg=-Wl,--defsym=__TEXT_REGION_LENGTH__=0x7F00
```

(avrxmega3's linker script gates the text-region length behind
`DEFINED(__TEXT_REGION_LENGTH__)`, so this genuinely shrinks the usable text
region — an artificially small region length correctly fails link with a
`region 'text' overflowed` error, confirming the guard is enforced.) Add
this `--link-arg=` whenever a `!T`/`?T`-using program targets a mapped-flash
device. A future niche-layout engine may remove the need for it.

## MMIO and ISR idioms

`lib/avr.nuc` provides device-agnostic memory-mapped I/O helpers, built
entirely on `(ptr :volatile T)` plus `unsafe/cast` (materializing a raw
hardware address, which the type system cannot hand out safely on its own).
The file is self-contained — it imports nothing and uses only
compiler-builtin special forms — so it works under `(exclude-prelude)`:

| Function | Signature | What it does |
|---|---|---|
| `reg8-read` | `(addr:usize):ui8` | Volatile load of one byte. |
| `reg8-write` | `(addr:usize val:ui8):void` | Volatile store of one byte. |
| `reg16-read` | `(addr:usize):ui16` | Volatile load of a 16-bit register pair. |
| `reg16-write` | `(addr:usize val:ui16):void` | Volatile store of a 16-bit register pair. |
| `bit-mask` | `(bit:ui8):ui8` | `1 << bit` as a `ui8` mask. |
| `reg8-test-bit` | `(addr:usize bit:ui8):ui8` | Nonzero iff `bit` is set. |
| `reg8-set-bit!` | `(addr:usize bit:ui8):void` | Read-modify-write: set one bit. |
| `reg8-clear-bit!` | `(addr:usize bit:ui8):void` | Read-modify-write: clear one bit. |
| `reg8-toggle-bit!` | `(addr:usize bit:ui8):void` | Read-modify-write: toggle one bit. |

The `-set!`/`-clear!`/`-toggle!` helpers are the classic-AVR
read-modify-write idiom (see `avr-blink.nuc`); modern AVR-Dx parts instead
expose dedicated SET/CLR/TGL registers and are typically driven with a
direct `reg8-write` to those (see `avr-blink-dx.nuc`) — both styles are
plain applications of `reg8-write`/`reg8-read`, not separate APIs.

Register **addresses** live in per-device files — `lib/avr/attiny1634.nuc`,
`lib/avr/avr32dd20.nuc`, `lib/avr/atmega328p.nuc` — as `defconst` integers,
each cross-referenced in a comment against the real avr-libc 2.2.1 header it
came from (`iotn1634.h`, `ioavr32dd20.h`, `iom328p.h`), not hand-derived from
datasheets. C header import cannot produce these automatically: avr-libc
declares special function registers (SFRs) as preprocessor macros, not C
declarations, so `--emit-cheader`/`import-use "<header>.h"` sees nothing to
extract. Two address conventions appear, and the files note which applies to
each register: classic I/O-space SFRs (`_SFR_IO8`) need avr-libc's
`__SFR_OFFSET` (`+0x20`) added to get the real data-space address Nucleus's
`deref`/`ptr-set!` reads and writes, while memory-mapped SFRs (`_SFR_MEM`,
all of the AVR32DD20's `PORT_t` struct fields and the ATmega328P's USART0)
are already absolute addresses and need no offset.

**ISRs.** An interrupt handler is an ordinary `defn` named after the
avr-libc vector symbol `__vector_<N>` (N = the device's 0-based vector
number — e.g. TIMER1_OVF is vector 13 on the ATmega328P), carrying the LLVM
`"signal"` string function attribute so the AVR backend emits the interrupt
prologue/epilogue (SREG + clobbered-register save/restore, and `reti`
instead of a plain `ret`). avr-libc's crt installs a vector table with weak
`__vector_N` defaults (each jumping to `__bad_interrupt`); defining the
strong symbol overrides that slot. The attribute comes from the generic
`fn-attr` top-level directive (see [Top-Level Forms](toplevel.md)), and it
**must precede** the `defn` it targets — there is no forward-reference
prescan:

```lisp
(fn-attr __vector_13 "signal")
(defn __vector_13 ():void
  (reg8-toggle-bit! PORTB 0))
```

Use `"interrupt"` instead of `"signal"` for a handler that should run with
global interrupts re-enabled (nested interrupts).

There is **no `defisr` macro** — don't go looking for one. This is a real
architectural constraint, not a missing convenience: this compiler's
top-level dispatch matches literal head symbols (`defn`, `fn-attr`, …)
*before* any macro expansion runs, so a top-level `(defmacro defisr …)`
followed by a call to it fails as an unknown top-level form, even when the
macro would expand to a single `defn`. Building a top-level
macro-expansion pass is well beyond what AVR needed, and baking
AVR-specific vector/attribute logic into a compiler builtin would break the
layering that keeps `fn-attr` a generic, reusable directive. The two
adjacent top-level forms above are the idiom; see `examples/avr-isr.nuc` for
a complete example (Timer/Counter1 overflow on the ATmega328P) and the block
comment in `lib/avr.nuc` for the convention written out in full.

## Testing

`make avr-test` (`tests/run-avr-test.sh`) compiles and links all four AVR
examples through the real `avr-gcc` driver, asserts each stays under a
generous per-example flash/RAM ceiling (a regression gate, not a byte-exact
pin), and runs `avr-uart-hello.nuc` under `simavr -m atmega328p -f 8000000`
as a genuine behavioral check — it asserts the captured output actually
contains the transmitted `Hi!` bytes, not just that the link succeeded.

It is separate from `make test`/`make bootstrap`, which stay host-only: the
freestanding AVR examples have no expected-stdout harness to diff against on
the host. `make avr-test` is gated on `avr-gcc` (the whole script SKIPs
cleanly without it) and, independently, on `simavr` (only the simulator step
SKIPs without it) — the same convention `tests/run-tests.sh`'s
`run_avr3_link`/`run_avr5_isr` gates already use.

The container toolchain this all depends on: `avr-gcc`, `binutils-avr`,
`avr-libc` (≥ 2.2, for AVR-Dx crt/specs support), and `simavr`. See
[context/build.md](../context/build.md) for how the compiler selects
`avr-gcc` as the link driver and the byte-identical-on-hosted-targets
invariant that every AVR-related compiler change preserves.
