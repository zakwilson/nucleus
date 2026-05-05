#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: build.sh <file.nuc>" >&2
    exit 2
fi

root="$(cd "$(dirname "$0")" && pwd)"
src="$1"
base="$(basename "$src" .nuc)"
out_dir="$root/build/out"
mkdir -p "$out_dir"
bin="$out_dir/${base}"

make -s -C "$root"
"$root/build/nucleusc" "$src" -o "$bin"
echo "built: $bin"
