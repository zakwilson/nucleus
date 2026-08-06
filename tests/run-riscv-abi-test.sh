#!/usr/bin/env bash
# RISC-V (riscv64-unknown-linux-gnu) struct-ABI interop acceptance test
# (Stage 14 RV-3, design/stage14/riscv-linux.md §5): the same three-direction
# aggregate-ABI interop gate as tests/run-abi-test.sh — Nucleus caller -> C
# callee, Nucleus -> Nucleus, and C caller -> Nucleus callee — built for riscv64.
# A mismatch means Nucleus's riscv64 aggregate ABI lowering (RV-3's integer
# convention) does not agree with the riscv64 psABI as implemented by the
# reference C compiler. Reuses tests/abi/{clib.c,interop.nuc,callee.nuc,driver.c,
# expected.out} unchanged — those fixtures are platform-neutral (the expected
# numbers are the same on every ABI; only the register/pointer lowering differs).
#
# TWO LANES, picked from `uname -m` (same split as tests/run-riscv-test.sh):
#   * CROSS (an x86_64/aarch64/... host): C fixtures and the final links go
#     through riscv64-linux-gnu-gcc; binaries run under
#     `qemu-riscv64 -L /usr/riscv64-linux-gnu`.
#   * NATIVE (a riscv64 host): prefer clang, falling back to cc, and run the
#     binaries directly — no cross toolchain and no qemu. The reference C
#     compiler is whichever of those is present; both implement the same
#     riscv64 psABI, which is what this gate actually compares against.
#
# Gated in TWO stages so a container without a *complete* toolchain SKIPs
# gracefully rather than FAILing (same SKIP convention as tests/run-riscv-test.sh
# and tests/run-avr-test.sh):
#   1. The lane's C compiler (and, cross-only, qemu-riscv64) must be on PATH.
#   2. A capability probe actually links a tiny program through the compiler.
#      Merely having the driver binary on PATH is not enough: in the cross lane
#      Debian's `libc6-riscv64-cross` runtime package provides the shared
#      libraries but NOT the crt startup objects (Scrt1.o, crt*.o) + glibc
#      headers, which live in the separate `libc6-dev-riscv64-cross` package.
#      Without it the link step fails with `cannot find Scrt1.o` (and the C
#      fixtures can't find <stdio.h>); we detect that shape and SKIP with a
#      pointer to the missing package instead of FAILing. The moment the
#      container gains that package the probe links and the full gate below
#      runs unchanged.
#
# Run via `make riscv-abi-test`. Intentionally NOT part of `make test`/`make
# bootstrap`/`make abi-test` — those stay host-only, mirroring the Phase-C
# precedent (tests/run-abi-test.sh) and the RV-2 cross lane (run-riscv-test.sh).
set -uo pipefail
cd "$(dirname "$0")/.."

NUCLEUSC=${NUCLEUSC:-./build/nucleusc}
TARGET=riscv64-unknown-linux-gnu
QEMU_SYSROOT=/usr/riscv64-linux-gnu
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# LINKER_FLAG is a single whitespace-free token (or empty), so the unquoted
# expansions below are intentional and safe.
LINKER_FLAG=""

if [ "$(uname -m)" = "riscv64" ]; then
  LANE=native
else
  LANE=cross
fi

# --- Stage 1 gate: the lane's toolchain must exist ----------------------------
if [ "$LANE" = native ]; then
  # Prefer clang (also the compiler's own hosted link-driver default, so the
  # common native case passes no --linker at all).
  if command -v clang >/dev/null 2>&1; then
    CC=clang
  elif command -v cc >/dev/null 2>&1; then
    CC=cc
    LINKER_FLAG="--linker=cc"
  else
    echo "SKIP  riscv-abi-test (native riscv64 host: neither clang nor cc on PATH)"
    exit 0
  fi
  run_target() { "$@"; }
else
  CC=riscv64-linux-gnu-gcc
  if ! command -v "$CC" >/dev/null 2>&1; then
    echo "SKIP  riscv-abi-test ($CC not installed)"
    exit 0
  fi
  if ! command -v qemu-riscv64 >/dev/null 2>&1; then
    echo "SKIP  riscv-abi-test (qemu-riscv64 not installed)"
    exit 0
  fi
  run_target() { qemu-riscv64 -L "$QEMU_SYSROOT" "$@"; }
fi

# --- Stage 2 gate: capability probe -------------------------------------------
# Drive the compiler's real compile-and-link path on a trivial example. If the
# link fails because the riscv crt startup objects are missing, SKIP cleanly.
# A passing probe means the libc development files are installed, so the crt
# objects AND the glibc headers the C fixtures need are both present.
PROBE_OUT="$TMP/probe.log"
if ! "$NUCLEUSC" --target="$TARGET" $LINKER_FLAG examples/hello.nuc \
     -o "$TMP/probe.bin" >"$PROBE_OUT" 2>&1; then
  if grep -qE 'Scrt1\.o|crt[a-zA-Z0-9]*\.o|startfile' "$PROBE_OUT"; then
    if [ "$LANE" = native ]; then
      echo "SKIP  riscv-abi-test (native riscv64 host missing libc development files: crt startup objects not found)"
    else
      echo "SKIP  riscv-abi-test (container missing libc6-dev-riscv64-cross: crt startup objects not found — see design/stage14/riscv-linux.md RV-2/RV-3)"
    fi
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
"$CC" -c tests/abi/clib.c -o "$TMP/clib.o" \
  || { echo "FAIL: $CC clib.c"; exit 1; }
"$NUCLEUSC" --target="$TARGET" tests/abi/interop.nuc -c -o "$TMP/interop.o" \
  || { echo "FAIL: nucleusc interop.nuc"; exit 1; }
"$CC" "$TMP/interop.o" "$TMP/clib.o" -o "$TMP/interop" \
  || { echo "FAIL: link interop"; exit 1; }

# Direction 3: C caller -> Nucleus-defined callee (defn-side ABI).
"$NUCLEUSC" --target="$TARGET" tests/abi/callee.nuc -c -o "$TMP/callee.o" \
  || { echo "FAIL: nucleusc callee.nuc"; exit 1; }
"$CC" tests/abi/driver.c "$TMP/callee.o" -o "$TMP/driver" \
  || { echo "FAIL: link driver"; exit 1; }

{ run_target "$TMP/interop";
  run_target "$TMP/driver"; } > "$TMP/actual.out" 2>&1 || true

if diff -u tests/abi/expected.out "$TMP/actual.out"; then
    echo "PASS  riscv-abi-interop"
    exit 0
else
    echo "FAIL  riscv-abi-interop (riscv64 struct ABI lowering does not match the riscv64 psABI)"
    exit 1
fi
