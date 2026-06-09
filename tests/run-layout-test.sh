#!/usr/bin/env bash
# Struct-layout verification (Phase E, design/stage8/platform.md q13a/14).
# The shared header tests/layout/structs.h is the single source of truth:
# layout.nuc prints sizeof + per-field offsets from Nucleus's own layout walk,
# layout.c prints the same from the platform C compiler (the oracle). A diff
# means Nucleus's struct layout disagrees with the platform C ABI, which is
# silently catastrophic at the C boundary, so a mismatch is a build failure.
set -uo pipefail
cd "$(dirname "$0")/.."

NUCLEUSC=${NUCLEUSC:-./build/nucleusc}
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cc tests/layout/layout.c -o "$TMP/layout_c" || { echo "FAIL: cc layout.c"; exit 1; }
"$NUCLEUSC" tests/layout/layout.nuc -o "$TMP/layout_nuc" || { echo "FAIL: nucleusc layout.nuc"; exit 1; }

"$TMP/layout_c"   > "$TMP/c.out"   2>&1 || true
"$TMP/layout_nuc" > "$TMP/nuc.out" 2>&1 || true

if diff -u "$TMP/c.out" "$TMP/nuc.out"; then
    echo "PASS  layout (Nucleus struct layout matches platform C ABI)"
    exit 0
else
    echo "FAIL  layout (Nucleus struct layout does not match platform C ABI)"
    exit 1
fi
