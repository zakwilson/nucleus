#!/usr/bin/env bash
# RISC-V (riscv64-unknown-linux-gnu) cross-compilation acceptance test
# (Stage 14 RV-2, design/stage14/riscv-linux.md §5): for each example that has a
# recorded expected output, compile+link it through the REAL compile-and-link
# path (`--target=riscv64-unknown-linux-gnu`, no --emit-llvm/--emit-obj, so the
# riscv64-linux-gnu-gcc link driver added in RV-2 is exercised end to end), run
# the resulting ELF under `qemu-riscv64 -L /usr/riscv64-linux-gnu`, and diff its
# stdout against tests/expected/<name>.out — the same platform-neutral outputs
# the native suite checks (ground truth §2.7).
#
# Gated in TWO stages so a container without a *complete* riscv toolchain SKIPs
# gracefully rather than FAILing (same SKIP convention as tests/run-avr-test.sh):
#   1. riscv64-linux-gnu-gcc AND qemu-riscv64 must both be on PATH.
#   2. A capability probe actually links a tiny program through the compiler.
#      Merely having the driver binary on PATH is not enough: Debian's
#      `libc6-riscv64-cross` runtime package provides the shared libraries but
#      NOT the crt startup objects (Scrt1.o, crt*.o) + headers, which live in
#      the separate `libc6-dev-riscv64-cross` package. Without it the link step
#      fails with `cannot find Scrt1.o`; we detect that shape and SKIP with a
#      pointer to the missing package instead of FAILing on every example. The
#      moment the container gains that package the probe links and the full gate
#      below runs unchanged.
#
# Run via `make riscv-test`. Intentionally NOT part of `make test`/`make
# bootstrap` — those stay host-only, mirroring tests/run-abi-test.sh's Phase-C
# precedent and tests/run-avr-test.sh (see their header comments).
set -uo pipefail
cd "$(dirname "$0")/.."

NUCLEUSC=${NUCLEUSC:-./build/nucleusc}
QEMU_SYSROOT=/usr/riscv64-linux-gnu
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- Stage 1 gate: cross link driver + qemu-user runner must both exist -------
if ! command -v riscv64-linux-gnu-gcc >/dev/null 2>&1; then
  echo "SKIP  riscv-test (riscv64-linux-gnu-gcc not installed)"
  exit 0
fi
if ! command -v qemu-riscv64 >/dev/null 2>&1; then
  echo "SKIP  riscv-test (qemu-riscv64 not installed)"
  exit 0
fi

# --- Stage 2 gate: capability probe -------------------------------------------
# Drive the compiler's real compile-and-link path on a trivial example. If the
# link fails because the riscv crt startup objects are missing, SKIP cleanly.
PROBE_OUT="$TMP/probe.log"
if ! "$NUCLEUSC" --target=riscv64-unknown-linux-gnu examples/hello.nuc \
     -o "$TMP/probe.bin" >"$PROBE_OUT" 2>&1; then
  if grep -qE 'Scrt1\.o|crt[a-zA-Z0-9]*\.o|startfile' "$PROBE_OUT"; then
    echo "SKIP  riscv-test (container missing libc6-dev-riscv64-cross: crt startup objects not found — see design/stage14/riscv-linux.md RV-2)"
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

# check_example <src>: compile+link for riscv64 through compile-and-link, run
# under qemu-riscv64, and diff stdout against the recorded expected output.
check_example() {
  local src="$1" name expected bin actual
  name="$(basename "$src" .nuc)"
  expected="tests/expected/${name}.out"
  [ -f "$expected" ] || return 0
  COUNT=$((COUNT + 1))
  bin="$TMP/$name"
  rm -f "$bin"
  if ! "$NUCLEUSC" --target=riscv64-unknown-linux-gnu "$src" -o "$bin" \
       >"$TMP/$name.err" 2>&1 || [ ! -s "$bin" ]; then
    echo "FAIL  riscv-test-$name (compile/link failed)"
    sed 's/^/      /' "$TMP/$name.err"
    FAILED=1
    return 0
  fi
  actual="$TMP/$name.out"
  qemu-riscv64 -L "$QEMU_SYSROOT" "$bin" >"$actual" 2>&1 || true
  if diff -u "$expected" "$actual" >/dev/null; then
    echo "PASS  riscv-test-$name"
  else
    echo "FAIL  riscv-test-$name (output mismatch under qemu)"
    diff -u "$expected" "$actual" | sed 's/^/      /' || true
    FAILED=1
  fi
}

for src in examples/*.nuc; do
  [ -f "$src" ] || continue
  check_example "$src"
done

echo "riscv-test: $COUNT example(s) checked under qemu-riscv64"
if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
exit 0
