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
    ./"$name" > "$actual_file" || true

    if diff -u "$expected" "$actual_file" >/dev/null; then
        echo "PASS  $name"
    else
        echo "FAIL  $name"
        diff -u "$expected" "$actual_file" || true
        fail=1
    fi
    rm -f "$actual_file"
done
exit $fail
