#!/usr/bin/env bash
#
# Stage 17's primary gate: byte-identical COMPILER OUTPUT
# (design/stage17-native-strings/migration-tooling.md §1).
#
# Byte-identical bootstrap cannot work for this stage — every emission call site
# is being rewritten, so the compiler's own IR necessarily moves. What must not
# move is the text the compiler *writes*, and that is a stronger property: it
# covers the 928-site emission surface directly rather than by proxy.
#
#   scripts/stage17/ir-snapshot.sh snapshot   # from the pre-conversion compiler
#   … convert a batch …
#   make && scripts/stage17/ir-snapshot.sh verify
#
# No normalization, no whitespace tolerance, no allowlist. A diff is a
# regression until proven otherwise; the whole value of the gate is that it
# admits no judgement.
#
# Re-baselining is deliberately a separate word (`snapshot` over an existing
# directory refuses unless --force), so "the gate was re-baselined" can never be
# a silent event. Record every re-take in design/progress.md with the reason.

set -euo pipefail
cd "$(dirname "$0")/../.."

NUCLEUSC="${NUCLEUSC:-./build/nucleusc}"
SNAP="${SNAP:-build/snapshot}"

mode="${1:-}"
force=0
[ "${2:-}" = "--force" ] && force=1

if [ "$mode" != "snapshot" ] && [ "$mode" != "verify" ]; then
  echo "usage: $0 {snapshot|verify} [--force]" >&2
  exit 2
fi
if [ ! -x "$NUCLEUSC" ]; then
  echo "ERROR: $NUCLEUSC not found -- run \`make\` first" >&2
  exit 2
fi
if [ "$mode" = "snapshot" ] && [ -d "$SNAP" ] && [ "$force" = 0 ]; then
  echo "ERROR: $SNAP already exists. Re-baselining is not a silent event:" >&2
  echo "       pass --force, and record the reason in design/progress.md." >&2
  exit 2
fi

# The corpus: everything the tree can compile. A source the compiler REFUSES is
# still in it — the refusal text is emitted output too, and a conversion that
# changes a diagnostic is exactly what this must catch.
#
# `src/nucleusc.nuc` is deliberately NOT an input. It is the source being
# converted, so its emitted IR moves with every batch by construction and could
# only be re-baselined, not verified. `make bootstrap` covers the same ground
# better, as a fixed point: stage1.ll == stage2.ll.
inputs() {
  ls tests/fixtures/*.nuc examples/*.nuc lib/*.nuc 2>/dev/null
}

# Three emissions per input, because all three are text the compiler writes and
# all three are being converted. Plus cross-emitted Windows IRs: a cross-target
# emission difference is a real class of bug a host-only snapshot cannot see.
emit_all() {  # <src> <destdir>
  local src="$1" dst="$2" base
  base="$(echo "$src" | tr '/' '_')"
  mkdir -p "$dst"
  "$NUCLEUSC" --emit-llvm     "$src" > "$dst/$base.ll"    2> "$dst/$base.ll.err"    || true
  "$NUCLEUSC" --emit-cheader  "$src" > "$dst/$base.h"     2> "$dst/$base.h.err"     || true
  "$NUCLEUSC" --emit-nuch     "$src" > "$dst/$base.nuch"  2> "$dst/$base.nuch.err"  || true
}

emit_windows() {  # <destdir>
  local dst="$1" src base
  for src in lib/*.nuc; do
    base="$(echo "$src" | tr '/' '_')"
    "$NUCLEUSC" --target=x86_64-pc-windows-gnu  --emit-llvm "$src" \
        > "$dst/$base.win-gnu.ll"  2>/dev/null || true
    "$NUCLEUSC" --target=x86_64-pc-windows-msvc --emit-llvm "$src" \
        > "$dst/$base.win-msvc.ll" 2>/dev/null || true
  done
}

if [ "$mode" = "snapshot" ]; then
  rm -rf "$SNAP"
  mkdir -p "$SNAP"
  n=0
  while read -r src; do
    [ -f "$src" ] || continue
    emit_all "$src" "$SNAP"
    n=$((n + 1))
  done < <(inputs)
  emit_windows "$SNAP"
  echo "snapshot: $n inputs, $(ls "$SNAP" | wc -l) artifacts in $SNAP"
  exit 0
fi

if [ ! -d "$SNAP" ]; then
  echo "ERROR: no snapshot at $SNAP -- run \`$0 snapshot\` first" >&2
  exit 2
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

bad=0
checked=0
while read -r src; do
  [ -f "$src" ] || continue
  emit_all "$src" "$tmp"
done < <(inputs)
emit_windows "$tmp"

for want in "$SNAP"/*; do
  name="$(basename "$want")"
  got="$tmp/$name"
  checked=$((checked + 1))
  if [ ! -f "$got" ]; then
    echo "MISSING  $name (snapshot has it, this build does not)"
    bad=$((bad + 1))
    continue
  fi
  if ! cmp -s "$want" "$got"; then
    # `cmp`/`diff` exit non-zero on a difference, which is the expected case
    # here; without the guards `set -e` + `pipefail` kills the run before it
    # reports anything.
    off="$(cmp "$want" "$got" 2>&1 | head -1 || true)"
    echo "DIFFERS  $name"
    echo "         $off"
    { diff -u "$want" "$got" | head -12 | sed 's/^/         /'; } || true
    bad=$((bad + 1))
  fi
done

echo "checked $checked artifact(s)"
if [ "$bad" != 0 ]; then
  echo "FAIL: $bad artifact(s) differ from the snapshot"
  exit 1
fi
echo "PASS: emitted output is byte-identical to the snapshot"
