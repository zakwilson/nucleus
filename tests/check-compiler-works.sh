#!/usr/bin/env bash
#
# One program, compiled, linked, run, and diffed — in bash, before anything else.
#
# `make test`'s real work is `build/nuctests`, which is a Nucleus program built
# by the compiler under test. When that compiler miscompiles, the suite's
# verdict is worth nothing; when it fails to compile at all, there is no verdict
# to have. This runs first and depends on nothing the compiler built except the
# one binary it is about to check, so a compiler broken badly enough to take the
# suite down with it has already been named here.
#
# Deliberately minimal, and deliberately not a unit of the suite: every line
# added here is a line that can break in the one place a failure has to be
# unambiguous. See design/stage18-tooling/overview.md §T2.1 and §T6.9.
#
# No `set -e`: every status below is handled explicitly, and errexit would kill
# the script before its diagnostic reached stderr.
set -uo pipefail
cd "$(dirname "$0")/.."

NUCLEUSC=${NUCLEUSC:-./build/nucleusc}
SRC=examples/hello.nuc
WANT=tests/expected/hello.out

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL  compiler-works ($*)" >&2; exit 1; }

[ -x "$NUCLEUSC" ] || fail "$NUCLEUSC is missing or not executable"

if ! "$NUCLEUSC" "$SRC" -o "$TMP/hello" >"$TMP/build.err" 2>&1; then
  sed 's/^/    /' "$TMP/build.err" >&2
  fail "$NUCLEUSC could not compile $SRC"
fi

# An exit-0 compile that wrote nothing is the failure a `-o` check catches and
# a status check does not.
[ -x "$TMP/hello" ] || fail "$NUCLEUSC reported success but wrote no binary"

"$TMP/hello" >"$TMP/actual" 2>&1 || fail "the compiled program exited $?"

diff -u "$WANT" "$TMP/actual" >&2 || fail "the program's output is not $WANT"

echo "PASS  compiler-works"
