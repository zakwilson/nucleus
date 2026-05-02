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

exit $fail
