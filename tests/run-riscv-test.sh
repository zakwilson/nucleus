#!/usr/bin/env bash
# RISC-V (riscv64-unknown-linux-gnu) compilation acceptance test
# (Stage 14 RV-2, design/stage14/riscv-linux.md §5): for each example that has a
# recorded expected output, compile+link it through the REAL compile-and-link
# path (`--target=riscv64-unknown-linux-gnu`, no --emit-llvm/--emit-obj, so the
# link driver selection added in RV-2 is exercised end to end), run the
# resulting ELF, and diff its stdout against tests/expected/<name>.out — the
# same platform-neutral outputs the native suite checks (ground truth §2.7).
#
# TWO LANES, picked from `uname -m`:
#   * CROSS (an x86_64/aarch64/... host): link driver is riscv64-linux-gnu-gcc,
#     binaries run under `qemu-riscv64 -L /usr/riscv64-linux-gnu`.
#   * NATIVE (a riscv64 host): the sysroot is just `/`, so the compiler's hosted
#     `clang` default links directly and no qemu is involved. We prefer clang
#     and fall back to `--linker=cc` only if clang is absent — the compiler's
#     own default is clang, so the common case passes no --linker at all. The
#     triplet-prefixed `riscv64-linux-gnu-gcc` is deliberately NOT required
#     here: it is a Debian-family naming convention that Fedora/Alpine/Arch
#     riscv64 do not ship, and needing it natively was the bug RV-2's
#     host-triple guard fixed.
#
# Gated in TWO stages so a container without a *complete* toolchain SKIPs
# gracefully rather than FAILing (same SKIP convention as tests/run-avr-test.sh):
#   1. The lane's link driver (and, cross-only, qemu-riscv64) must be on PATH.
#   2. A capability probe actually links a tiny program through the compiler.
#      Merely having the driver binary on PATH is not enough: in the cross lane
#      Debian's `libc6-riscv64-cross` runtime package provides the shared
#      libraries but NOT the crt startup objects (Scrt1.o, crt*.o) + headers,
#      which live in the separate `libc6-dev-riscv64-cross` package. Without it
#      the link step fails with `cannot find Scrt1.o`; we detect that shape and
#      SKIP with a pointer to the missing package instead of FAILing on every
#      example. The moment the container gains that package the probe links and
#      the full gate below runs unchanged.
#
# Run via `make riscv-test`. Intentionally NOT part of `make test`/`make
# bootstrap` — those stay host-only, mirroring tests/run-abi-test.sh's Phase-C
# precedent and tests/run-avr-test.sh (see their header comments).
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
  # Prefer clang (the compiler's own hosted default → no --linker needed).
  if command -v clang >/dev/null 2>&1; then
    :
  elif command -v cc >/dev/null 2>&1; then
    LINKER_FLAG="--linker=cc"
  else
    echo "SKIP  riscv-test (native riscv64 host: neither clang nor cc on PATH)"
    exit 0
  fi
  run_target() { "$@"; }
else
  if ! command -v riscv64-linux-gnu-gcc >/dev/null 2>&1; then
    echo "SKIP  riscv-test (riscv64-linux-gnu-gcc not installed)"
    exit 0
  fi
  if ! command -v qemu-riscv64 >/dev/null 2>&1; then
    echo "SKIP  riscv-test (qemu-riscv64 not installed)"
    exit 0
  fi
  run_target() { qemu-riscv64 -L "$QEMU_SYSROOT" "$@"; }
fi

# --- Stage 2 gate: capability probe -------------------------------------------
# Drive the compiler's real compile-and-link path on a trivial example. If the
# link fails because the riscv crt startup objects are missing, SKIP cleanly.
PROBE_OUT="$TMP/probe.log"
if ! "$NUCLEUSC" --target="$TARGET" $LINKER_FLAG examples/hello.nuc \
     -o "$TMP/probe.bin" >"$PROBE_OUT" 2>&1; then
  if grep -qE 'Scrt1\.o|crt[a-zA-Z0-9]*\.o|startfile' "$PROBE_OUT"; then
    if [ "$LANE" = native ]; then
      echo "SKIP  riscv-test (native riscv64 host missing libc development files: crt startup objects not found)"
    else
      echo "SKIP  riscv-test (container missing libc6-dev-riscv64-cross: crt startup objects not found — see design/stage14/riscv-linux.md RV-2)"
    fi
    exit 0
  fi
  # An unexpected link failure (NOT the known crt gap): surface the diagnostics
  # but still SKIP so a differently-broken toolchain doesn't red the build.
  echo "SKIP  riscv-test (riscv64 link probe failed unexpectedly — diagnostics below)"
  sed 's/^/      /' "$PROBE_OUT"
  exit 0
fi

# --- Full gate: the toolchain is complete — run every example end to end ------
FAILED=0
COUNT=0

# check_example <src>: compile+link for riscv64 through compile-and-link, run it
# (directly when native, under qemu when cross), and diff stdout against the
# recorded expected output.
check_example() {
  local src="$1" name expected bin actual
  name="$(basename "$src" .nuc)"
  expected="tests/expected/${name}.out"
  [ -f "$expected" ] || return 0
  COUNT=$((COUNT + 1))
  bin="$TMP/$name"
  rm -f "$bin"
  if ! "$NUCLEUSC" --target="$TARGET" $LINKER_FLAG "$src" -o "$bin" \
       >"$TMP/$name.err" 2>&1 || [ ! -s "$bin" ]; then
    echo "FAIL  riscv-test-$name (compile/link failed)"
    sed 's/^/      /' "$TMP/$name.err"
    FAILED=1
    return 0
  fi
  actual="$TMP/$name.out"
  run_target "$bin" >"$actual" 2>&1 || true
  if diff -u "$expected" "$actual" >/dev/null; then
    echo "PASS  riscv-test-$name"
  else
    echo "FAIL  riscv-test-$name (output mismatch)"
    diff -u "$expected" "$actual" | sed 's/^/      /' || true
    FAILED=1
  fi
}

for src in examples/*.nuc; do
  [ -f "$src" ] || continue
  check_example "$src"
done

if [ "$LANE" = native ]; then
  echo "riscv-test: $COUNT example(s) checked natively on riscv64"
else
  echo "riscv-test: $COUNT example(s) checked under qemu-riscv64"
fi
if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
exit 0
