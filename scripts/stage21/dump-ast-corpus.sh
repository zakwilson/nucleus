#!/usr/bin/env bash
#
# Stage 21 one-reader.md §6.1 corpus gate, and PK-2's instrument: `--dump-ast`
# (stdout, stderr, exit code) over every `.nuc`, byte-identical before/after.
#
#   scripts/stage21/dump-ast-corpus.sh snapshot        # pre-change compiler
#   make && scripts/stage21/dump-ast-corpus.sh verify  # after
#
# No normalization. `snapshot` over an existing directory refuses without
# --force; record every re-take in design/progress.md.

set -euo pipefail
cd "$(dirname "$0")/../.."

NUCLEUSC="${NUCLEUSC:-./build/nucleusc}"
SNAP="${SNAP:-build/dump-ast-snapshot}"

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

# `src/nucleusc.nuc` IS an input here, unlike ir-snapshot.sh: --dump-ast stops
# after the reader, so the compiler's own source is just the largest test file.
inputs() {
  find tests/fixtures examples lib src -name '*.nuc' | sort
}

# The source path is resolved from the cwd (the repo root, set above), so no
# -I or -o is needed. `timeout` guards the gate against a reader that loops.
dump_one() {  # <src> <destdir>
  local src="$1" dst="$2" rc
  mkdir -p "$dst/$(dirname "$src")"
  rc=0
  timeout 30 "$NUCLEUSC" --dump-ast "$src" \
    > "$dst/$src.out" 2> "$dst/$src.err" || rc=$?
  echo "$rc" > "$dst/$src.rc"
}

if [ "$mode" = "snapshot" ]; then
  rm -rf "$SNAP"
  mkdir -p "$SNAP"
  n=0
  rejected=0
  while read -r src; do
    [ -f "$src" ] || continue
    dump_one "$src" "$SNAP"
    n=$((n + 1))
    [ "$(cat "$SNAP/$src.rc")" = 0 ] || rejected=$((rejected + 1))
  done < <(inputs)
  echo "snapshot: $n inputs ($rejected rejected), $(find "$SNAP" -type f | wc -l) artifacts in $SNAP"
  exit 0
fi

if [ ! -d "$SNAP" ]; then
  echo "ERROR: no snapshot at $SNAP -- run \`$0 snapshot\` first" >&2
  exit 2
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

while read -r src; do
  [ -f "$src" ] || continue
  dump_one "$src" "$tmp"
done < <(inputs)

bad=0
checked=0
while read -r want; do
  name="${want#"$SNAP"/}"
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
done < <(find "$SNAP" -type f | sort)

# An input added since the snapshot is not a regression, but it is unverified;
# say so rather than pass silently.
while read -r got; do
  name="${got#"$tmp"/}"
  [ -f "$SNAP/$name" ] || echo "NEW      $name (this build has it, snapshot does not)"
done < <(find "$tmp" -type f | sort)

echo "checked $checked artifact(s)"
if [ "$bad" != 0 ]; then
  echo "FAIL: $bad artifact(s) differ from the snapshot"
  exit 1
fi
echo "PASS: --dump-ast output is byte-identical to the snapshot"
