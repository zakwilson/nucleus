#!/usr/bin/env bash
# AVR v1 acceptance test (Stage 14 AVR-8, design/stage14/avr-targets.md §5):
# for each of the four AVR examples (already individually hand-verified in
# AVR-3/4/5) — compile+link via the real avr-gcc link driver, then assert
# avr-size stays within a generous per-device flash/RAM budget. Also runs the
# UART example under simavr as the behavioral smoke test: the only one of the
# four devices AVR-0 ground-verified against a real simulator core.
#
# Gated on avr-gcc (SKIP gracefully, same convention as tests/run-tests.sh's
# run_avr3_link/run_avr5_isr) so a container without the AVR toolchain doesn't
# fail the whole script — just skips. The simulator step has its own,
# independent simavr gate.
#
# Run via `make avr-test`. Intentionally NOT part of `make test`/`make
# bootstrap` — those remain host-only, mirroring tests/run-abi-test.sh's
# Phase-C precedent (see its header comment).
set -uo pipefail
cd "$(dirname "$0")/.."

NUCLEUSC=${NUCLEUSC:-./build/nucleusc}
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if ! command -v avr-gcc >/dev/null 2>&1; then
  echo "SKIP  avr-test (avr-gcc not installed)"
  exit 0
fi

FAILED=0

# Generous flash/RAM ceilings. All four known-good examples link to 858-1070
# bytes text / 0 bytes data+bss (design/stage14/avr-targets.md AVR-3/4/5
# entries). This is a ceiling, not an exact byte match, so the gate isn't
# brittle to harmless future size shifts but still catches a real regression
# (e.g. a pulled-in host runtime, which would balloon to kilobytes).
FLASH_CEILING=4096
RAM_CEILING=512

# check_example <name> <nuc-file> <cpu> [<mmcu>]
# Compiles+links via the AVR-3 link driver, then asserts avr-size stays under
# budget. Echoes the produced .elf path on stdout for callers that need it
# (the simulator step below); PASS/FAIL/diagnostics go to stderr so they
# don't get captured by that echo.
check_example() {
  local name="$1" src="$2" cpu="$3" mmcu="${4:-}" elf rc txt dat bss flash ram
  elf="$TMP/$name.elf"
  if [ -n "$mmcu" ]; then
    "$NUCLEUSC" --target=avr --mcpu="$cpu" --mmcu="$mmcu" "$src" -o "$elf" \
      >"$TMP/$name.err" 2>&1
  else
    "$NUCLEUSC" --target=avr --mcpu="$cpu" "$src" -o "$elf" \
      >"$TMP/$name.err" 2>&1
  fi
  rc=$?
  if [ "$rc" -ne 0 ] || [ ! -s "$elf" ]; then
    echo "FAIL  avr-test-$name (compile/link failed, exit=$rc)" >&2
    sed 's/^/      /' "$TMP/$name.err" >&2
    FAILED=1
    return 1
  fi
  set -- $(avr-size "$elf" | awk 'NR==2 {print $1, $2, $3}')
  txt="${1:-999999}"; dat="${2:-999999}"; bss="${3:-999999}"
  flash=$((txt + dat))
  ram=$((dat + bss))
  if [ "$flash" -le "$FLASH_CEILING" ] && [ "$ram" -le "$RAM_CEILING" ]; then
    echo "PASS  avr-test-$name (flash=$flash ram=$ram text=$txt data=$dat bss=$bss)" >&2
  else
    echo "FAIL  avr-test-$name (over budget: flash=$flash/$FLASH_CEILING ram=$ram/$RAM_CEILING)" >&2
    FAILED=1
    return 1
  fi
  echo "$elf"
  return 0
}

check_example blink       examples/avr-blink.nuc        attiny1634 >"$TMP/blink.elfpath"
check_example blink-dx    examples/avr-blink-dx.nuc     avrxmega3  avr32dd20 >"$TMP/blink-dx.elfpath"
check_example uart-hello  examples/avr-uart-hello.nuc   atmega328p >"$TMP/uart-hello.elfpath"
check_example isr         examples/avr-isr.nuc          atmega328p >"$TMP/isr.elfpath"
check_example global-init examples/avr-global-init.nuc  attiny1634 >"$TMP/global-init.elfpath"

# --- Stage 15 W8 G-3: global initializers on a `none`-mechanism target -------
# design/global-init.md §4.6/§4.8. Two halves, and both matter:
#
#  (a) ZERO COST. examples/avr-global-init.nuc (linked + budgeted above) has
#      only CONSTANT initializers, so the queue is empty and the emitted IR must
#      contain no `@__nucleus_init` and no `llvm.global_ctors` — not a dead one,
#      not an empty one, none. This is the microcontroller half of the tripwire
#      in tests/run-tests.sh; it is asserted on the target the requirement was
#      stated for, not only on the host.
#
#  (b) LOUD REFUSAL. tests/fixtures/avr-runtime-init.nuc asks for a run-time
#      initializer. AVR has no verified append-only startup mechanism (§2.6:
#      LLVM's `.init_array` lands in RAM, avr-libc walks an empty `.ctors`), so
#      this must be a located error naming the offending `defvar` — never a
#      constructor that is emitted, linked, occupies RAM and never runs.
#
# Both use --emit-llvm rather than a link, because what is asserted is the IR's
# content and the diagnostic, neither of which needs avr-gcc. They still sit
# here rather than in run-tests.sh because they are --target=avr behaviour.
ZC_LL="$TMP/avr-global-init.ll"
if ! "$NUCLEUSC" --target=avr --mcpu=attiny1634 --emit-llvm examples/avr-global-init.nuc \
     >"$ZC_LL" 2>"$TMP/zc.err"; then
  echo "FAIL  avr-test-g3-zero-cost (compile failed)"
  sed 's/^/      /' "$TMP/zc.err"
  FAILED=1
elif grep -qE '__nucleus_init|global_ctors' "$ZC_LL"; then
  echo "FAIL  avr-test-g3-zero-cost (constant-only unit emitted startup-constructor machinery)"
  grep -nE '__nucleus_init|global_ctors' "$ZC_LL" | sed 's/^/      /'
  FAILED=1
else
  echo "PASS  avr-test-g3-zero-cost (no @__nucleus_init, no llvm.global_ctors)"
fi

RT_ERR="$TMP/avr-runtime-init.err"
if "$NUCLEUSC" --target=avr --mcpu=attiny1634 --emit-llvm tests/fixtures/avr-runtime-init.nuc \
     >/dev/null 2>"$RT_ERR"; then
  echo "FAIL  avr-test-g3-no-mechanism (a run-time initializer was accepted for avr)"
  FAILED=1
elif ! grep -q "tests/fixtures/avr-runtime-init.nuc:18: error:" "$RT_ERR" \
     || ! grep -q "'g-seed' needs a run-time initializer" "$RT_ERR" \
     || ! grep -q "has no startup-constructor mechanism" "$RT_ERR"; then
  echo "FAIL  avr-test-g3-no-mechanism (wrong diagnostic or wrong location)"
  sed 's/^/      /' "$RT_ERR"
  FAILED=1
else
  echo "PASS  avr-test-g3-no-mechanism (located error naming the offending defvar)"
fi

# Simulator smoke test: the real behavioral gate. Run the UART example under
# simavr -m atmega328p (the device AVR-0 ground-verified against simavr's
# core list) for a bounded time and confirm the observed output actually
# contains the transmitted bytes ("Hi!\n" = 72,105,33,10, per
# examples/avr-uart-hello.nuc). The firmware's main loop runs forever, so
# `timeout` cutting it off (exit 124) is expected and not a failure — only
# the captured output content is asserted.
UART_ELF="$(cat "$TMP/uart-hello.elfpath" 2>/dev/null)"
if [ ! -s "$UART_ELF" ]; then
  echo "SKIP  avr-test-sim-uart-hello (uart-hello.elf was not built — see avr-test-uart-hello above)"
elif ! command -v simavr >/dev/null 2>&1; then
  echo "SKIP  avr-test-sim-uart-hello (simavr not installed)"
else
  SIM_OUT="$TMP/sim.out"
  timeout 3 simavr -m atmega328p -f 8000000 "$UART_ELF" >"$SIM_OUT" 2>&1
  if grep -aq 'Hi!' "$SIM_OUT"; then
    echo "PASS  avr-test-sim-uart-hello (observed transmitted 'Hi!' bytes under simavr)"
  else
    echo "FAIL  avr-test-sim-uart-hello (no 'Hi!' bytes observed in simavr output)"
    sed 's/^/      /' "$SIM_OUT"
    FAILED=1
  fi
fi

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
exit 0
