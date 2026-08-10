#!/usr/bin/env bash
#
# Verify that every committed generated header under lib/ still matches what the
# current compiler emits (Stage 15 W9 item 3 follow-up).
#
# lib/*.nuch and lib/*.h are generated artifacts that are also committed, so a
# change to src/nuch.nuc or src/cheader.nuc silently invalidates them: the build
# never reads the committed copies (`make lib-headers` / `make lib-cheaders`
# overwrite them), so nothing notices until someone consumes a header that no
# longer describes the library. Everything else generated-and-committed in this
# repo is already gated -- boot/*.ll by `make bootstrap`, docs/stdlib.md by the
# `stdlib-table-generated` unit -- and these were the gap.
#
# Byte-exact, unlike the stdlib table's deliberately loose check: header emission
# is a pure function of the source (no host or libc probing), so any difference
# at all is real drift. Verified at the time of writing: all 69 committed headers
# regenerate byte-identically.
#
# The three failures this catches, in the order checked:
#   1. a lib/*.nuc with no committed .h or .nuch  -- a header that was never added
#   2. a committed header whose source is gone, or recorded as an absolute path
#      -- an artifact that cannot be regenerated on another checkout
#   3. a committed header that differs from a fresh emission -- ordinary drift
#
# Generated files are identified by the provenance line the generators themselves
# write (src/nuch.nuc:169, src/cheader.nuc:2252), not by an exclusion list, so a
# hand-written header such as src/llvm.nuch is out of scope by construction and a
# newly generated one is picked up with no edit here.
#
# Usage: scripts/check-headers.sh [--fix]
#   (no args)  report drift, exit 1 if any
#   --fix      rewrite the drifted headers in place
#
# `--fix` rather than `make lib-headers lib-cheaders` because those targets are
# driven by `$(wildcard lib/*.nuc)` and so cannot regenerate lib/mapiterlib.nuch,
# whose source is tests/fixtures/mapiterlib.nuc.

set -euo pipefail
cd "$(dirname "$0")/.."

NUCLEUSC="${NUCLEUSC:-./build/nucleusc}"
FIX=0
if [ "${1:-}" = "--fix" ]; then
  FIX=1
elif [ -n "${1:-}" ]; then
  echo "usage: $0 [--fix]" >&2
  exit 2
fi

if [ ! -x "$NUCLEUSC" ]; then
  echo "ERROR: $NUCLEUSC not found -- run \`make\` first" >&2
  exit 2
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

bad=0
fixed=0
checked=0
root="$(pwd)"

report() { echo "$*"; bad=1; }

# 1. Coverage: a new lib/*.nuc whose headers were never generated is drift of the
#    header *set*, which a content-only diff cannot see.
for src in lib/*.nuc; do
  base="${src%.nuc}"
  for ext in h nuch; do
    [ -f "$base.$ext" ] || report "MISSING  $base.$ext (no committed header for $src)"
  done
done

# 2 + 3. Provenance and content, for both header flavours.
for hdr in lib/*.h lib/*.nuch; do
  [ -f "$hdr" ] || continue
  case "$hdr" in
    *.h)    marker='s|^/\* Generated from \(.*\) by nucleusc --emit-cheader \*/$|\1|p'
            flag=--emit-cheader ;;
    *.nuch) marker='s|^; \.nuch header for \(.*\)$|\1|p'
            flag=--emit-nuch ;;
  esac

  src="$(sed -n "$marker" "$hdr" | head -1)"
  if [ -z "$src" ]; then
    # No provenance line: hand-maintained, not ours to check.
    continue
  fi

  # An absolute path names a directory layout, not a file in this repo: the
  # header regenerates only on the machine that produced it. Recorded verbatim
  # from the command line, so this means "someone ran the generator with an
  # absolute path", and the fix is to re-run it from the repo root.
  if [ "${src#/}" != "$src" ]; then
    if [ "${src#"$root"/}" != "$src" ] && [ "$FIX" -eq 1 ]; then
      src="${src#"$root"/}"
    else
      report "ABSOLUTE $hdr records '$src' -- not reproducible on another checkout"
      continue
    fi
  fi

  if [ ! -f "$src" ]; then
    report "ORPHAN   $hdr was generated from '$src', which no longer exists"
    continue
  fi

  checked=$((checked + 1))
  fresh="$tmp/fresh"
  if ! "$NUCLEUSC" "$flag" "$src" > "$fresh" 2>"$tmp/err"; then
    report "ERROR    $hdr: \`$NUCLEUSC $flag $src\` failed"
    sed 's/^/         /' "$tmp/err"
    continue
  fi

  if cmp -s "$fresh" "$hdr"; then
    continue
  fi
  if [ "$FIX" -eq 1 ]; then
    cp "$fresh" "$hdr"
    echo "regenerated $hdr"
    fixed=$((fixed + 1))
  else
    report "STALE    $hdr differs from \`$NUCLEUSC $flag $src\`"
  fi
done

if [ "$FIX" -eq 1 ]; then
  if [ "$bad" -ne 0 ]; then
    echo "regenerated $fixed header(s); the problems above need a source change, not a re-emit" >&2
    exit 1
  fi
  echo "checked $checked generated header(s); regenerated $fixed"
  exit 0
fi

if [ "$bad" -ne 0 ]; then
  echo "run \`scripts/check-headers.sh --fix\` to regenerate (or \`make lib-headers lib-cheaders\`" >&2
  echo "for the lib/*.nuc-sourced ones) and commit the result" >&2
  exit 1
fi

echo "checked $checked generated header(s); all match the current compiler"
