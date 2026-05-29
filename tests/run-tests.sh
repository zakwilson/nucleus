#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
for src in examples/*.nuc; do
    name="$(basename "$src" .nuc)"
    expected="tests/expected/${name}.out"
    [ -f "$expected" ] || continue

    ./build.sh "$src" >/dev/null 2>&1
    actual_file="$(mktemp)"
    ./build/out/"$name" > "$actual_file" 2>&1 || true

    if diff -u "$expected" "$actual_file" >/dev/null; then
        echo "PASS  $name"
    else
        echo "FAIL  $name"
        diff -u "$expected" "$actual_file" || true
        fail=1
    fi
    rm -f "$actual_file"
done

# REPL session tests: pipe each tests/repl/<name>.in into `nucleusc -i` and
# compare against tests/expected/repl-<name>.out.
for src in tests/repl/*.in; do
    [ -f "$src" ] || continue
    name="$(basename "$src" .in)"
    expected="tests/expected/repl-${name}.out"
    [ -f "$expected" ] || continue

    actual_file="$(mktemp)"
    ./build/nucleusc -i < "$src" > "$actual_file" 2>&1 || true

    if diff -u "$expected" "$actual_file" >/dev/null; then
        echo "PASS  repl-$name"
    else
        echo "FAIL  repl-$name"
        diff -u "$expected" "$actual_file" || true
        fail=1
    fi
    rm -f "$actual_file"
done

# Cross-target emission: each triple in the Phase-B matrix must produce IR
# carrying the matching `target triple` line. Guards against a backend not
# being registered (which makes --target reject the triple).
for triple in \
    x86_64-pc-linux-gnu \
    x86_64-apple-darwin \
    aarch64-apple-darwin \
    aarch64-unknown-linux-gnu \
    arm-unknown-linux-gnueabihf \
    x86_64-pc-windows-msvc \
    x86_64-pc-windows-gnu \
    i386-pc-linux-gnu; do
    ir="$(./build/nucleusc --target="$triple" --emit-llvm examples/hello.nuc 2>/dev/null || true)"
    if printf '%s' "$ir" | grep -q "target triple = \"$triple\""; then
        echo "PASS  target-$triple"
    else
        echo "FAIL  target-$triple"
        fail=1
    fi
done

# Struct ABI interop: Nucleus<->C aggregate passing/returning must match the
# platform C ABI (Phase C). A mismatch is silently catastrophic, so it gates.
if NUCLEUSC=./build/nucleusc ./tests/run-abi-test.sh; then
    :
else
    fail=1
fi

exit $fail
