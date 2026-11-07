#!/usr/bin/env bash
# C calling Nucleus variadics, and va_list crossing in both directions, on each
# class of list (design/lua-bugfixes/variadic-functions.md §5) at -O0 and -O2.
# Freestanding, so needs no target libc: only clang, lld and qemu-user. A target
# without its emulator is skipped; x86-64 always runs.
set -u
NUCLEUSC=${NUCLEUSC:-build/nucleusc}
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
command -v ld.lld >/dev/null || { echo "SKIP  varargs-cross (no ld.lld)"; exit 0; }
status=0

run() { # triple runner extra-cflags
  local t=$1 runner=$2 extra=$3 o ir
  command -v "${runner:-true}" >/dev/null || { echo "SKIP  $t (no $runner)"; return; }
  ir=$WORK/$t.ll
  "$NUCLEUSC" --target="$t" --emit-llvm "$HERE/fixtures/varargs-cross.nuc" 2>/dev/null > "$WORK/all.ll" || {
    echo "FAIL  $t: nucleusc"; status=1; return; }
  # Only the fixture's functions: the prelude's objects want a libc this link lacks.
  { grep -E '^(target|declare.*(llvm|c_list))' "$WORK/all.ll"
    sed -n -E '/^define.*@(n_list|n_sum|n_copy)\(/,/^}/p' "$WORK/all.ll"; } > "$ir"
  for o in 0 2; do
    clang --target="$t" -O$o -w -c "$ir" -o "$WORK/$t.o" &&
    clang --target="$t" -O$o $extra -ffreestanding -fno-stack-protector -nostdlib -static \
      -fuse-ld=lld -w "$HERE/fixtures/varargs-cross.c" "$WORK/$t.o" -o "$WORK/$t.bin" || {
      echo "FAIL  $t -O$o: build"; status=1; continue; }
    $runner "$WORK/$t.bin"
    rc=$?
    if [ $rc = 0 ]; then echo "PASS  $t -O$o"; else echo "FAIL  $t -O$o: case $rc"; status=1; fi
  done
}

run x86_64-linux-gnu "" ""
run aarch64-linux-gnu qemu-aarch64 ""
run riscv64-linux-gnu qemu-riscv64 "-march=rv64gc -mabi=lp64d"
exit $status
