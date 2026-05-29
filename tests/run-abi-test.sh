#!/usr/bin/env bash
# Struct-ABI interop acceptance test: build the Nucleus caller against a C
# callee compiled by the system cc, run it, and diff against the all-C
# reference output. A mismatch means Nucleus's aggregate ABI lowering does
# not agree with the platform C ABI.
#
# This is the acceptance gate for Phase C (see design/stage8/platform.md).
# Run via `make abi-test`. It is intentionally NOT part of `make test` until
# Phase C lands, so the main build stays green in the meantime.
set -uo pipefail
cd "$(dirname "$0")/.."

NUCLEUSC=${NUCLEUSC:-./build/nucleusc}
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Direction 1+2: Nucleus caller -> C callee, and Nucleus -> Nucleus.
cc -c tests/abi/clib.c -o "$TMP/clib.o" || { echo "FAIL: cc clib.c"; exit 1; }
"$NUCLEUSC" tests/abi/interop.nuc -c -o "$TMP/interop.o" || { echo "FAIL: nucleusc interop.nuc"; exit 1; }
cc "$TMP/interop.o" "$TMP/clib.o" -o "$TMP/interop" || { echo "FAIL: link interop"; exit 1; }

# Direction 3: C caller -> Nucleus-defined callee (defn-side ABI).
"$NUCLEUSC" tests/abi/callee.nuc -c -o "$TMP/callee.o" || { echo "FAIL: nucleusc callee.nuc"; exit 1; }
cc tests/abi/driver.c "$TMP/callee.o" -o "$TMP/driver" || { echo "FAIL: link driver"; exit 1; }

{ "$TMP/interop"; "$TMP/driver"; } > "$TMP/actual.out" 2>&1 || true

if diff -u tests/abi/expected.out "$TMP/actual.out"; then
    echo "PASS  abi-interop"
    exit 0
else
    echo "FAIL  abi-interop (struct ABI lowering does not match platform C ABI)"
    exit 1
fi
