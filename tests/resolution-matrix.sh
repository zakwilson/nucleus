#!/usr/bin/env bash
# Name-resolution probe matrix — design/stage15-stress-test/name-resolution.md §2.
#
# WHAT THIS IS. B0 of the name-resolution work. It is NOT a correctness test: it
# is a *recorder*. Each cell compiles a generated one-file consumer against a
# generated library and records whether the reference resolved (`ok`) or not
# (`err`, with the first diagnostic). The point is that B1/B2 can diff their
# results against tests/expected/resolution-matrix.baseline and see exactly
# which cells moved — and which did not.
#
# The library lives in namespace `zn` and every consumer imports it as
#   (import-prefixed zzlib zx)
# so the four spellings under test are: bare, `zn/` (the defining namespace),
# `zx/` (the prefix the consumer actually asked for) and `nope/` (a qualifier
# naming nothing at all).
#
# WHAT *SHOULD* HAPPEN (§8.3's table, R3): only the `zx/` column should be `ok`.
# An import prefix binds the library's public names under `p/` and nothing else,
# so the defining namespace `zn/` should be out of scope, a bare name should not
# reach a prefixed import, and `nope/` should be a hard error naming the
# prefixes that are in scope.
#
# WHAT ACTUALLY HAPPENS (recorded in the baseline, explained in §1.1/§2):
#   * `import-prefixed` is not a resolution mechanism. It copies the imported
#     slice of `g-globals` under a second key `zx/<name>`, filtered by
#     `is-local` and `ir-name` — two fields that mean something else — so it
#     silently skips every `defvar` (is-local 1), `defconst` and `defenum`
#     member (ir-name null). Nothing else is keyed by `g-globals` at all, so
#     types, protocols, generics, macros and templates have no `zx/` spelling.
#   * A qualifier on a TYPE is never validated: `strip-ns-qualifier` discards
#     everything before the first interior slash, so `nope/Zs` resolves (§2.2).
#   * Overloaded functions are keyed bare with no `qualify-name`, so once a
#     `defn` gains a second overload it becomes unqualifiable (§2.3).
#   * A prefix is unit-global, not file-scoped: one declared in file A is
#     visible in file B (§2.4) — the `xfile-prefix-leak` row.
#   * `import-only` filters nothing — `emit-import-only` calls `do-import` with
#     a null prefix, i.e. a full flatten, and the symbol list is a comment
#     (§11.2) — the two `import-only-unlisted-*` rows.
#
# Do not "fix" a cell here. B0 records; B1/B2 change. When a later step moves a
# cell, re-run with --baseline and commit the new table as part of that step.
#
# Usage:
#   tests/resolution-matrix.sh                  print the table
#   tests/resolution-matrix.sh --baseline FILE  print it and write it to FILE
#   tests/resolution-matrix.sh --check FILE     diff against FILE; exit 1 on any
#                                               difference, printing only the
#                                               cells that moved
set -euo pipefail
cd "$(dirname "$0")/.."

mode="print"
target=""
case "${1:-}" in
  "")         ;;
  --baseline) mode="baseline"; target="${2:-}" ;;
  --check)    mode="check";    target="${2:-}" ;;
  *) echo "usage: $0 [--baseline <file> | --check <file>]" >&2; exit 2 ;;
esac
if [ "$mode" != "print" ] && [ -z "$target" ]; then
  echo "$1 requires a file argument" >&2
  exit 2
fi

d="$(mktemp -d)"
results="$(mktemp)"
# Probe binaries land in build/out/ (build.sh's fixed output dir), so they are
# removed by name as each probe finishes; the trap is the belt-and-braces for an
# interrupted run. Nothing may survive in examples/ or lib/ — a stray probe
# there is picked up by `make test`.
cleanup() { rm -rf "$d"; rm -f "$results"; rm -f build/out/zzp-*; }
trap cleanup EXIT

# --- the library under test ---------------------------------------------------
# Namespace `zn`, one definer per name kind the matrix probes.
cat > "$d/zzlib.nuc" <<'EOF'
(ns zn)

(defprotocol Zp (zmeth ((self (ref Self))) i32))

(defstruct Zs n:i32)

(defn zfun (x:i32):i32 (return (+ x 1)))

; Two overloads, so `zov` is a Generic rather than a solitary g-globals Sym.
(defn zov (x:i32):i32 (return (+ x 10)))
(defn zov (x:i64):i32 (return 20))

(defconst ZK 7)
(defvar zg:i32 3)
(defenum ZE ZE-A ZE-B)
EOF

# §2.4: a middle file that declares the prefix `zx`. The consumer below imports
# only this file and never declares the prefix itself.
cat > "$d/zzmid.nuc" <<'EOF'
(import-prefixed zzlib zx)
(defn zzmid-call (x:i32):i32 (return (zx/zfun x)))
EOF

# §11.2: a plain (namespace-less) library for the import-only filter probes.
cat > "$d/zzonly.nuc" <<'EOF'
(defstruct OnlyS m:i32)
(defn only-a (x:i32):i32 (return x))
(defn only-b (x:i32):i32 (return (+ x 1)))
EOF

# --- probe driver -------------------------------------------------------------
# probe <row> <spelling-label> <source>
# Compiles and LINKS the source as its own program. `ok` means build.sh
# succeeded; `err` carries the first diagnostic, with the (random) temp path
# stripped so the table is stable across runs.
probe() {
  local row="$1" spelling="$2" src="$3"
  local name status msg log
  name="zzp-$(printf '%s' "${row}-${spelling}" | tr -c 'a-zA-Z0-9-' '-')"
  printf '%s' "$src" > "$d/$name.nuc"
  log="$d/$name.log"
  rm -f "build/out/$name"
  if ./build.sh "$d/$name.nuc" >"$log" 2>&1; then
    status="ok"
    msg=""
  else
    status="err"
    # Prefer the compiler's own located diagnostic; fall back to the first
    # non-empty line (a link failure has no `error:` prefix).
    msg="$(sed -n 's/^.*: error: //p' "$log" | head -1)"
    if [ -z "$msg" ]; then
      msg="$(grep -v '^LLVM:' "$log" | grep -m1 . || true)"
    fi
    msg="${msg//$d\//}"
  fi
  rm -f "build/out/$name"
  printf '%-26s %-6s %-4s %s\n' "$row" "$spelling" "$status" "\"$msg\"" >> "$results"
}

# probe_spellings <row> <template-with-@Q@>
# Runs one row against all four spellings. `@Q@` is replaced by the qualifier
# ("" for bare, "zn/", "zx/", "nope/").
probe_spellings() {
  local row="$1" tmpl="$2" label q
  for label in bare zn/ zx/ nope/; do
    if [ "$label" = "bare" ]; then q=""; else q="$label"; fi
    probe "$row" "$label" "${tmpl//@Q@/$q}"
  done
}

# --- the §2 matrix ------------------------------------------------------------

# A type in an annotation. Only the annotation's spelling varies.
probe_spellings type-annot '(import-prefixed zzlib zx)
(defn zzp-f ((x (ref @Q@Zs))):i32 (return (_get x n)))
(defn main ():i32 (return 0))
'

# A struct constructor in value position. Only the constructor head varies; the
# binding annotation is held at the spelling row 1 records as `ok`.
#
# Stage 15 B3′ RE-POINTED that annotation from bare `Zs` to `zx/Zs`. It was bare
# because before B3′ a type name was bare-keyed and globally visible, so bare was
# "the one spelling that works" — and R1 makes it an error, which would have made
# all four cells here measure the ANNOTATION's failure instead of the
# constructor's. Same class as B2a's `protocol-dyn-box` re-point: a fixture that
# holds a control at the spelling a defect permits becomes unreachable when the
# defect is fixed, and the re-point is part of the change, not a re-baseline.
probe_spellings struct-ctor '(import-prefixed zzlib zx)
(defn main ():i32
  (let (s:(ref zx/Zs) (@Q@Zs 4))
    (return (_get s n))))
'

# A solitary defn.
probe_spellings plain-fn '(import-prefixed zzlib zx)
(defn main ():i32 (return (@Q@zfun 1)))
'

# The same shape once the name has two overloads (§2.3).
probe_spellings overloaded-fn '(import-prefixed zzlib zx)
(defn main ():i32 (return (@Q@zov 1)))
'

probe_spellings defvar '(import-prefixed zzlib zx)
(defn main ():i32 (return @Q@zg))
'

probe_spellings defconst '(import-prefixed zzlib zx)
(defn main ():i32 (return @Q@ZK))
'

probe_spellings defenum-member '(import-prefixed zzlib zx)
(defn main ():i32 (return @Q@ZE-B))
'

# A protocol named by `extend`. The conforming type is local so the row probes
# the protocol spelling alone.
probe_spellings protocol-extend '(import-prefixed zzlib zx)
(defstruct Cs n:i32)
(defn zmeth ((self (ref Cs))):i32 (return (_get self n)))
(extend Cs @Q@Zp)
(defn main ():i32 (return 0))
'

# The same protocol named by `(dyn …)`, in an ANNOTATION only. Nothing here
# forces a registry probe: `dyn-type` deliberately does not validate at
# type-parse time (it may run during a prescan, before the protocol's own file
# has registered it — src/nucleusc.nuc, `dyn-require-protocol`'s header), so a
# `(dyn nope/Zp)` parameter fabricates a `%__dyn.nope_Zp` box type and compiles.
# Recorded as its own row because it is the reason §2's single "protocol" row
# was ambiguous: the annotation and the box answer different questions.
probe_spellings protocol-dyn-annot '(import-prefixed zzlib zx)
(defn zzp-use ((box (dyn @Q@Zp))):i32 (return 0))
(defn main ():i32 (return 0))
'

# Boxing a value, which is where `dyn-require-protocol` actually runs. The
# `extend` is pinned at the one spelling that works, so only the `dyn` spelling
# varies — and B2a MOVED which spelling that is. Before B2a the only spelling
# `extend` accepted was the library's own namespace (`zn/`); after it, that is
# precisely the spelling a prefixed import does not bind, and the prefix the
# consumer asked for (`zx/`) is the one that works. Re-pointing the pin is a
# deliberate part of the cut-over, not a re-baseline: a fixture that pins a
# defect becomes unreachable when the defect is fixed.
probe_spellings protocol-dyn-box '(import-use allocator)
(import-prefixed zzlib zx)
(defstruct Cs n:i32)
(defn zmeth ((self (ref Cs))):i32 (return (_get self n)))
(extend Cs zx/Zp)
(defn main ():i32
  (let (b:(dyn @Q@Zp) (Cs 5))
    (return (zmeth b))))
'

# --- extra rows ---------------------------------------------------------------

# §2.4 — the cross-file prefix leak. This file imports zzmid (which declares the
# prefix) with `import-use` and never declares `zx` itself.
probe xfile-prefix-leak zx/ '(import-use zzmid)
(defn main ():i32 (return (zx/zfun 1)))
'

# §11.2 — `import-only` filters nothing: an unlisted function...
probe import-only-unlisted-fn bare '(import-only zzonly only-a)
(defn main ():i32 (return (only-b 1)))
'

# ...and an unlisted type both still resolve.
probe import-only-unlisted-type bare '(import-only zzonly only-a)
(defn zzp-g ((x (ref OnlyS))):i32 (return (_get x m)))
(defn main ():i32 (return 0))
'

# --- report -------------------------------------------------------------------
# Sorted so the table is independent of probe execution order.
sorted="$(LC_ALL=C sort "$results")"

case "$mode" in
  print)
    printf '%s\n' "$sorted"
    ;;
  baseline)
    printf '%s\n' "$sorted" > "$target"
    printf '%s\n' "$sorted"
    echo "wrote baseline: $target" >&2
    ;;
  check)
    if [ ! -f "$target" ]; then
      echo "no such baseline: $target" >&2
      exit 2
    fi
    if diff -q "$target" <(printf '%s\n' "$sorted") >/dev/null; then
      echo "resolution-matrix: unchanged ($(printf '%s\n' "$sorted" | wc -l) cells)"
      exit 0
    fi
    echo "resolution-matrix: CHANGED vs $target" >&2
    diff "$target" <(printf '%s\n' "$sorted") \
      | sed -n -e 's/^< /  baseline: /p' -e 's/^> /  current : /p' >&2
    exit 1
    ;;
esac
