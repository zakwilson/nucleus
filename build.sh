#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: build.sh <file.nuc>" >&2
    exit 2
fi

root="$(cd "$(dirname "$0")" && pwd)"
src="$1"
base="$(basename "$src" .nuc)"
ll="${base}.ll"
bin="${base}"

make -s -C "$root" build/nucleusc
"$root/build/nucleusc" "$src" > "$ll"
clang "$ll" -o "$bin"
echo "built: $bin"
