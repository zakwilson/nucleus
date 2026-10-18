#!/usr/bin/env bash
#
# Stage 26 RF-0 replay harness (design/stage26-refactoring/overview.md §6.2):
# run two refactoring commands over two exports of the same tree and require
# identical files and identical refusal sites (path:line; wording is ignored).
#
#   scripts/stage26/replay.sh --rev REV --files 'PATHS-OR-GLOBS' [--exclude 'PATHS-OR-GLOBS']
#       (--refusals X | --refusals-a X --refusals-b Y) --a 'CMD A' --b 'CMD B'
#
# Each command runs with its tree as cwd and the expanded file list appended as
# arguments. Globs are bash globs with globstar, expanded in C collation.
# Extractors: list-api-sweep, ptr-sweep, sugar-sweep, nucleus. Exit 0 = PASS.
#
# The three Python originals, at the tree each ran on (the parent of the commit
# that added it). Replace --b with the Nucleus port; the script itself must be
# the current one (absolute path), since the old tree may predate it. A port
# runs under `nucleusc --run`, every path absolute, with -I $PWD/lib: each side's
# cwd is the old tree, which has no lib/nucleus/ to shadow it.
#
#   # list-api-sweep.py, added in b6e454b2 (ast-as-collection step 1), ported
#   # and deleted in RF-3b. tests/fixtures is out: five w4c-* fixtures are
#   # malformed on purpose and crash its parser.
#   git show 95df57b7:scripts/stage21/list-api-sweep.py > /tmp/list-api-sweep.py
#   scripts/stage26/replay.sh --rev e1952ea3 \
#     --files 'src/*.nuc lib/*.nuc examples/*.nuc tests/*.nuc' \
#     --refusals-a list-api-sweep --refusals-b nucleus \
#     --a "python3 /tmp/list-api-sweep.py --apply" \
#     --b "$PWD/build/nucleusc -I $PWD/lib --run $PWD/scripts/stage26/list-api-sweep.nuc -- --apply"
#
#   # ptr-sweep.py, added in 6910d81d (ptr-is-unchecked BP-2), ported and
#   # deleted in RF-5. The excluded fixture is the one hit file the commit left
#   # as written.
#   git show 6910d81d:scripts/stage21/ptr-sweep.py > /tmp/ptr-sweep.py
#   scripts/stage26/replay.sh --rev 294e4ac2 \
#     --files 'src/*.nuc lib/**/*.nuc examples/*.nuc tests/**/*.nuc tests/repl/*.in' \
#     --exclude 'tests/fixtures/s21-pk2-fuse-open-segment.nuc' \
#     --refusals-a ptr-sweep --refusals-b nucleus \
#     --a "python3 /tmp/ptr-sweep.py --in-strings" \
#     --b "$PWD/build/nucleusc -I $PWD/lib --run $PWD/scripts/stage26/ptr-sweep.nuc -- --apply --in-strings"
#
#   # sugar-sweep.py, added in a5651b4d (PK-5a): all rules, less four spelling
#   # examples. The RF-6 port covers R3-R5 (Q6), so --a runs only those.
#   scripts/stage26/replay.sh --rev 0fc4fa9e \
#     --files 'src/*.nuc lib/**/*.nuc examples/*.nuc' \
#     --exclude 'examples/ptr.nuc examples/ref-sigil.nuc examples/colon-paren-types.nuc examples/errptr.nuc' \
#     --refusals-a sugar-sweep --refusals-b nucleus \
#     --a "python3 $PWD/scripts/stage21/sugar-sweep.py --rules R3,R4,R5" \
#     --b "$PWD/build/nucleusc -I $PWD/lib --run $PWD/scripts/stage26/sugar-sweep.nuc -- --apply"

set -euo pipefail
export LC_ALL=C PYTHONDONTWRITEBYTECODE=1

usage() {
    sed -n '7,12p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
}

die() { echo "replay: $*" >&2; exit 2; }

rev="" files="" exclude="" ref_a="" ref_b="" cmd_a="" cmd_b=""
while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || { [ "$1" = -h ] || [ "$1" = --help ] && usage; die "$1 needs a value"; }
    case "$1" in
        --rev) rev="$2" ;;
        --files) files="$2" ;;
        --exclude) exclude="$2" ;;
        --refusals) ref_a="$2"; ref_b="$2" ;;
        --refusals-a) ref_a="$2" ;;
        --refusals-b) ref_b="$2" ;;
        --a) cmd_a="$2" ;;
        --b) cmd_b="$2" ;;
        *) die "unknown option: $1" ;;
    esac
    shift 2
done
[ -n "$rev" ] && [ -n "$files" ] && [ -n "$cmd_a" ] && [ -n "$cmd_b" ] || usage
[ -n "$ref_a" ] && [ -n "$ref_b" ] || die "--refusals (or --refusals-a and --refusals-b) is required"
for x in "$ref_a" "$ref_b"; do
    case "$x" in list-api-sweep|ptr-sweep|sugar-sweep|nucleus) ;; *) die "unknown extractor: $x" ;; esac
done

repo=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
git -C "$repo" rev-parse -q --verify "$rev^{commit}" >/dev/null || die "not a commit: $rev"

work=$(mktemp -d "${TMPDIR:-/tmp}/replay.XXXXXX")
keep=0
trap '[ "$keep" = 1 ] || rm -rf "$work"' EXIT

# --- extractors: side output on stdin -> path:line lines ---------------------

# A Python extractor also requires the script's closing line, so a crash or the
# wrong extractor cannot pass as "no refusals".
extract() {
    case "$1" in
        list-api-sweep) awk '
            /^[0-9]+ site\(s\) need hand conversion:$/ { on = 1; next }
            on && match($0, /^  [^ ]+:[0-9]+  /) { print substr($0, 3, RLENGTH - 4) }
            /^total [0-9]+$/ { seen = 1 }
            END { exit !seen }' ;;
        sugar-sweep) awk '
            /^[0-9]+ refused:$/ { on = 1; next }
            on && match($0, /^  [^ ]+:[0-9]+  /) { print substr($0, 3, RLENGTH - 4) }
            /^[0-9]+ sites rewritten$/ { seen = 1 }
            END { exit !seen }' ;;
        ptr-sweep) awk '/^[0-9]+ sites$/ { seen = 1 } END { exit !seen }' ;;
        nucleus) awk '
            match($0, /^[^:]+:[0-9]+:[0-9]+: [^:]+: /) {
                split($0, f, ":")
                rule = substr(f[4], 2)
                if (rule != "error" && rule != "warning" && rule != "note") print f[1] ":" f[2]
            }' ;;
    esac
}

# Strip the side's own tree prefix and a leading ./ so A and B compare.
normalize() {
    awk -v r1="$1/" -v r2="$2/" '
        index($0, r1) == 1 { $0 = substr($0, length(r1) + 1) }
        index($0, r2) == 1 { $0 = substr($0, length(r2) + 1) }
        { sub(/^\.\//, "") } 1' | sort -u
}

# --- export, expand, run ------------------------------------------------------

expand() {  # $1 = tree; prints the file list, one per line
    (
        cd "$1"
        shopt -s globstar nullglob
        set -f; local pats=($files) xpats=($exclude); set +f
        declare -A seen=() skip=()
        local p m
        for p in "${xpats[@]}"; do
            m=($p)
            [ ${#m[@]} -gt 0 ] && [ -e "${m[0]}" ] || die "--exclude '$p' matches nothing at $rev"
            for f in "${m[@]}"; do skip[$f]=1; done
        done
        for p in "${pats[@]}"; do
            m=($p)
            [ ${#m[@]} -gt 0 ] && [ -e "${m[0]}" ] || die "--files '$p' matches nothing at $rev"
            for f in "${m[@]}"; do
                [ -f "$f" ] && [ -z "${skip[$f]:-}" ] && [ -z "${seen[$f]:-}" ] || continue
                seen[$f]=1
                printf '%s\n' "$f"
            done
        done
    )
}

declare -A status=() changed=()
nfiles=0
for side in a b; do
    tree="$work/$side"
    mkdir "$tree"
    git -C "$repo" archive "$rev" | tar -x -C "$tree"
    expand "$tree" > "$work/$side.files"
    mapfile -t list < "$work/$side.files"
    [ ${#list[@]} -gt 0 ] || die "--files expands to no regular files at $rev"
    nfiles=${#list[@]}
    (cd "$tree" && sha1sum -- "${list[@]}") > "$work/$side.before"
    if [ "$side" = a ]; then cmd="$cmd_a"; ex="$ref_a"; else cmd="$cmd_b"; ex="$ref_b"; fi
    set +e
    (cd "$tree" && bash -c "$cmd \"\$@\"" "replay-$side" "${list[@]}") \
        > "$work/$side.stdout" 2> "$work/$side.stderr"
    status[$side]=$?
    cat "$work/$side.stdout" "$work/$side.stderr" | extract "$ex" > "$work/$side.raw-refusals"
    ex_status=$?
    set -e
    [ "$ex_status" = 0 ] || status[$side]="${status[$side]}, and the $ex extractor did not recognize its output"
    normalize "$tree" "$(cd "$tree" && pwd -P)" < "$work/$side.raw-refusals" > "$work/$side.refusals"
    changed[$side]=$( (cd "$tree" && sha1sum --quiet -c "$work/$side.before" 2>/dev/null) | grep -c ': FAILED' || true)
done
cmp -s "$work/a.files" "$work/b.files" || die "file lists differ between the two exports (impossible?)"

# --- compare ------------------------------------------------------------------

fails=()
echo "rev $rev: $nfiles files"
for side in a b; do
    n=$(wc -l < "$work/$side.refusals")
    echo "  $side: exit ${status[$side]}; changed ${changed[$side]} of $nfiles listed files; $n refusal sites"
    [ "${status[$side]}" = 0 ] || fails+=("command $side: exit ${status[$side]} (see $work/$side.stderr)")
done

if ! (cd "$work" && diff -ru a b) > "$work/files.diff"; then
    lines=$(wc -l < "$work/files.diff")
    fails+=("files differ: $lines diff lines in $work/files.diff")
    echo; echo "--- files (first 60 of $lines diff lines):"
    head -n 60 "$work/files.diff"
fi

comm -23 "$work/a.refusals" "$work/b.refusals" > "$work/refusals-only-a"
comm -13 "$work/a.refusals" "$work/b.refusals" > "$work/refusals-only-b"
for side in a b; do
    f="$work/refusals-only-$side"
    n=$(wc -l < "$f")
    [ "$n" = 0 ] && continue
    fails+=("$n refusal sites only in $side ($f)")
    echo; echo "--- refusals only in $side ($n):"
    head -n 40 "$f"
    [ "$n" -le 40 ] || echo "  ... $((n - 40)) more in $f"
done

echo
if [ ${#fails[@]} = 0 ]; then
    echo PASS
    exit 0
fi
keep=1
echo FAIL
for f in "${fails[@]}"; do echo "  - $f"; done
echo "  trees and outputs kept in $work (a/, b/, {a,b}.stdout, {a,b}.stderr)"
exit 1
