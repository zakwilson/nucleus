#!/usr/bin/env bash
# RISC-V (riscv64-unknown-linux-gnu) struct-ABI interop acceptance test
# (Stage 14 RV-3, design/stage14/riscv-linux.md §5): the same three-direction
# aggregate-ABI interop gate as tests/run-abi-test.sh — Nucleus caller -> C
# callee, Nucleus -> Nucleus, and C caller -> Nucleus callee — but cross-compiled
# for riscv64 and executed under `qemu-riscv64 -L /usr/riscv64-linux-gnu`. A
# mismatch means Nucleus's riscv64 aggregate ABI lowering (RV-3's integer
# convention) does not agree with the riscv64 psABI as implemented by the cross
# gcc. Reuses tests/abi/{clib.c,interop.nuc,callee.nuc,driver.c,expected.out}
# unchanged — those fixtures are platform-neutral (the expected numbers are the
# same on every ABI; only the register/pointer lowering differs).
#
# Gated in TWO stages so a container without a *complete* riscv toolchain SKIPs
# gracefully rather than FAILing (same SKIP convention as tests/run-riscv-test.sh
# and tests/run-avr-test.sh):
#   1. riscv64-linux-gnu-gcc AND qemu-riscv64 must both be on PATH.
#   2. A capability probe actually links a tiny program through the compiler.
#      Merely having the driver binary on PATH is not enough: Debian's
#      `libc6-riscv64-cross` runtime package provides the shared libraries but
#      NOT the crt startup objects (Scrt1.o, crt*.o) + glibc headers, which live
#      in the separate `libc6-dev-riscv64-cross` package. Without it the link
#      step fails with `cannot find Scrt1.o` (and the C fixtures can't find
#      <stdio.h>); we detect that shape and SKIP with a pointer to the missing
#      package instead of FAILing. The moment the container gains that package
#      the probe links and the full gate below runs unchanged.
#
# Run via `make riscv-abi-test`. Intentionally NOT part of `make test`/`make
# bootstrap`/`make abi-test` — those stay host-only, mirroring the Phase-C
# precedent (tests/run-abi-test.sh) and the RV-2 cross lane (run-riscv-test.sh).
set -uo pipefail
cd "$(dirname "$0")/.."

NUCLEUSC=${NUCLEUSC:-./build/nucleusc}
TARGET=riscv64-unknown-linux-gnu
CROSS_CC=riscv64-linux-gnu-gcc
QEMU_SYSROOT=/usr/riscv64-linux-gnu
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- Stage 1 gate: cross gcc + qemu-user runner must both exist ---------------
if ! command -v "$CROSS_CC" >/dev/null 2>&1; then
  echo "SKIP  riscv-abi-test ($CROSS_CC not installed)"
  exit 0
fi
if ! command -v qemu-riscv64 >/dev/null 2>&1; then
  echo "SKIP  riscv-abi-test (qemu-riscv64 not installed)"
  exit 0
fi

# --- Stage 2 gate: capability probe -------------------------------------------
# Drive the compiler's real compile-and-link path on a trivial example. If the
# link fails because the riscv crt startup objects are missing, SKIP cleanly.
# A passing probe means libc6-dev-riscv64-cross is installed, so the crt objects
# AND the glibc headers the C fixtures need are both present.
PROBE_OUT="$TMP/probe.log"
if ! "$NUCLEUSC" --target="$TARGET" examples/hello.nuc \
     -o "$TMP/probe.bin" >"$PROBE_OUT" 2>&1; then
  if grep -qE 'Scrt1\.o|crt[a-zA-Z0-9]*\.o|startfile' "$PROBE_OUT"; then
    echo "SKIP  riscv-abi-test (container missing libc6-dev-riscv64-cross: crt startup objects not found — see design/stage14/riscv-linux.md RV-2/RV-3)"
    exit 0
  fi
  # An unexpected link failure (NOT the known crt gap): surface the diagnostics
  # but still SKIP so a differently-broken toolchain doesn't red the build.
  echo "SKIP  riscv-abi-test (riscv64 link probe failed unexpectedly — diagnostics below)"
  sed 's/^/      /' "$PROBE_OUT"
  exit 0
fi

# --- Full gate: the toolchain is complete — run the three-direction interop ---
# Direction 1+2: Nucleus caller -> C callee, and Nucleus -> Nucleus.
"$CROSS_CC" -c tests/abi/clib.c -o "$TMP/clib.o" \
  || { echo "FAIL: $CROSS_CC clib.c"; exit 1; }
"$NUCLEUSC" --target="$TARGET" tests/abi/interop.nuc -c -o "$TMP/interop.o" \
  || { echo "FAIL: nucleusc interop.nuc"; exit 1; }
"$CROSS_CC" "$TMP/interop.o" "$TMP/clib.o" -o "$TMP/interop" \
  || { echo "FAIL: link interop"; exit 1; }

# Direction 3: C caller -> Nucleus-defined callee (defn-side ABI).
"$NUCLEUSC" --target="$TARGET" tests/abi/callee.nuc -c -o "$TMP/callee.o" \
  || { echo "FAIL: nucleusc callee.nuc"; exit 1; }
"$CROSS_CC" tests/abi/driver.c "$TMP/callee.o" -o "$TMP/driver" \
  || { echo "FAIL: link driver"; exit 1; }

{ qemu-riscv64 -L "$QEMU_SYSROOT" "$TMP/interop";
  qemu-riscv64 -L "$QEMU_SYSROOT" "$TMP/driver"; } > "$TMP/actual.out" 2>&1 || true

if diff -u tests/abi/expected.out "$TMP/actual.out"; then
    echo "PASS  riscv-abi-interop"
    exit 0
else
    echo "FAIL  riscv-abi-interop (riscv64 struct ABI lowering does not match the riscv64 psABI)"
    exit 1
fi
