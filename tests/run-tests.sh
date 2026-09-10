#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# --- Modes ----------------------------------------------------------------------
# TF-1 (design/stage18-tooling/overview.md §T6.1): the suite is addressable, so
# a runner outside this file can drive one unit at a time.
#
#   (no args)       run everything and replay in dispatch order — as before
#   --list          print unit names in dispatch order; run nothing
#   --unit <name>   run exactly that unit; exit 1 if it failed
#
# `spawn` is the only dispatch point in the file, so mode selection lives
# entirely inside it and no unit had to change.
#
# `--unit` does NOT build: it is the per-unit entry point for a driver that has
# already built once, and 955 concurrent `make`s would reintroduce the race the
# `make -s` below exists to prevent. Build first when invoking it by hand.
MODE=run
WANT=
case "${1:-}" in
  --list) MODE=list ;;
  --unit)
    MODE=unit
    WANT="${2:-}"
    if [ -z "$WANT" ]; then
      echo "usage: $0 --unit <name>   (see $0 --list)" >&2
      exit 2
    fi ;;
  "") ;;
  *)
    echo "usage: $0 [--list | --unit <name>]" >&2
    exit 2 ;;
esac

# Bring the compiler up to date BEFORE dispatch. Several units shell out to
# build.sh, which runs `make` — harmless when the tree is already built, but if
# any src/*.nuc is newer then parallel jobs relink build/nucleusc while the
# other jobs are executing it, and every unit dies with "Text file busy".
[ "$MODE" = run ] && make -s test-tools

# --- Parallel dispatch ----------------------------------------------------------
# Test groups run concurrently as independent background jobs, bounded by
# NUCLEUS_TEST_JOBS (default $(nproc)). Each job buffers its PASS/FAIL line(s)
# — and any diff body — to a per-job file under $RESULTS_DIR; once all jobs
# join, the files are replayed in dispatch order so the printed output matches
# the serial script byte-for-byte (identical when all pass; same FAIL set on
# failure). The live job count is capped with `wait -n` (bash >= 4.3). Plain
# bash + coreutils only; no GNU parallel dependency.
NUCLEUS_TEST_JOBS="${NUCLEUS_TEST_JOBS:-$(nproc)}"
RESULTS_DIR="$(mktemp -d)"
trap 'rm -rf "$RESULTS_DIR"' EXIT
UNIT_NAMES=()
_seq=0
_job_count=0
_unit_ran=0
_unit_fail=0
declare -A _unit_seen=()

# spawn <func> [args...] — run one test unit in the background, then block
# until a job slot frees if the pool is full. Per-unit stdout+stderr is
# captured to a numbered result file; ordering is recovered from UNIT_NAMES.
#
# The unit's NAME is the function plus its FIRST argument, which is already the
# unit's identity everywhere it matters: `run_reader_parity <dir>`,
# `w1_reject_multi <name> ...`. Later arguments are expected diagnostic text — joining
# those in would put error messages, spaces and parens into a name that has to
# survive a command line. Names must be unique or `--unit` cannot address them,
# which is checked here rather than left for a driver to discover.
spawn() {
  local id name
  name="$1"
  [ $# -gt 1 ] && name="$name:$2"
  if [ -n "${_unit_seen[$name]+set}" ]; then
    echo "run-tests.sh: duplicate unit name '$name' — --unit cannot address it" >&2
    exit 2
  fi
  _unit_seen[$name]=1

  case "$MODE" in
    list)
      printf '%s\n' "$name"
      return 0 ;;
    unit)
      [ "$name" = "$WANT" ] || return 0 ;;
  esac

  id="_$_seq"
  _seq=$((_seq + 1))
  UNIT_NAMES+=("$id")

  # One unit, run alone. Backgrounded and waited rather than called directly:
  # a unit that dies mid-way must leave the same partial output it would leave
  # in the pool, and `set -e` inside it must behave the same way. Calling it in
  # this shell under `|| true` would disable errexit for the whole body.
  if [ "$MODE" = unit ]; then
    "$@" >"$RESULTS_DIR/${id}.out" 2>&1 &
    wait "$!" || true
    cat "$RESULTS_DIR/${id}.out"
    if qgrep '^FAIL' "$RESULTS_DIR/${id}.out" || [ ! -s "$RESULTS_DIR/${id}.out" ]; then
      _unit_fail=1
    fi
    # Nothing after this unit can change its verdict, and a driver pays this
    # script's parse-and-glob cost once per unit -- so stop here rather than
    # walking the remaining dispatch calls.
    exit "$_unit_fail"
  fi

  "$@" >"$RESULTS_DIR/${id}.out" 2>&1 &
  _job_count=$((_job_count + 1))
  while [ "$_job_count" -ge "$NUCLEUS_TEST_JOBS" ]; do
    wait -n || true
    _job_count=$((_job_count - 1))
  done
}

# qgrep — `grep -q` that does not race with the process feeding it.
#
# `grep -q` exits at its FIRST match, closing the pipe on the producer; under
# `set -o pipefail` (line 2) the producer's SIGPIPE becomes the pipeline's exit
# status, so an assertion that MATCHED reads as false. The race is one-sided —
# a genuine non-match never trips it, because grep then reads its input to the
# end — which is why it surfaced as a handful of tests failing at random rather
# than as a consistent wrong answer. Measured on the 54KB of IR
# `w1-late-overload-symbol` greps: 186 of 200 identical runs reported "no
# match" for a pattern that is present; 0 of 200 with pipefail off.
#
# Reading the input to completion and discarding the output removes the race and
# keeps pipefail's real value (a producer that CRASHES still fails the
# assertion, because grep then matches nothing). The exit status is grep's own.
qgrep() { grep "$@" >/dev/null; }

# --- Per-group unit functions ---------------------------------------------------
# Each unit is self-contained: it owns its own mktemp space, compiles, checks,
# and echoes its PASS/FAIL line(s) to stdout. A unit is treated as the atomic
# parallel grain — intra-unit steps that depend on each other (write lib →
# emit → grep → link → run) stay serial within the unit.


# Struct ABI interop: Nucleus<->C aggregate passing/returning must match the
# platform C ABI (Phase C). A mismatch is silently catastrophic, so it gates.
run_abi_subtest() {
  NUCLEUSC=./build/nucleusc ./tests/run-abi-test.sh
}

# Struct layout: Nucleus's sizeof/field-offset computation must match the
# platform C ABI for the question-14 corpus (Phase E). Also silently
# catastrophic at the C boundary, so it gates.
run_layout_subtest() {
  NUCLEUSC=./build/nucleusc ./tests/run-layout-test.sh
}

# Stage 15 W4a accept criterion: NO compiler diagnostic may report line 0.
# Every tests/fixtures/*.nuc is a potential error producer, so compile them all
# and fail if any stderr carries a `:0:` location. This is the check that stops
# the class from regrowing: a new diagnostic raised from a context that has lost
# the node (the interned-symbol case, or a registration/inference phase) trips
# it here rather than reaching a user.
run_no_line_zero() {
  local f err bad body=""
  bad=0
  for f in tests/fixtures/*.nuc; do
    err="$(./build/nucleusc --emit-llvm "$f" 2>&1 >/dev/null || true)"
    if printf '%s' "$err" | qgrep ':0:'; then
      bad=1
      body="${body}    ${f}"$'\n'
      body="${body}$(printf '%s' "$err" | grep ':0:' | sed 's/^/      /')"$'\n'
    fi
  done
  if [ "$bad" -eq 0 ]; then
    echo "PASS  w4a-no-line-zero"
  else
    echo "FAIL  w4a-no-line-zero (a diagnostic reported line 0)"
    printf '%s' "$body"
  fi
}


# --- Multi-file programs: the shared compile+link+run helper -----------------
# A caller writes its files into one directory, compiles+LINKS and runs the
# program, and checks its exit status — an exit-0 compile alone would not catch
# a call routed to the wrong symbol. Stage 15 W1, which this was written for,
# now lives in tests/suite-imports.nuc.

# Compile+link+run one multi-file program and assert its exit status.
#   w1_run <name> <dir> <main.nuc> <expected-status>
w1_run() {
  local name="$1" d="$2" mainsrc="$3" want="$4" err got
  err="$(./build/nucleusc -I "$d" -o "$d/$name.bin" "$mainsrc" 2>&1 >/dev/null || true)"
  if [ ! -x "$d/$name.bin" ]; then
    echo "FAIL  $name (compile/link error)"
    printf '%s\n' "$err" | sed 's/^/    /'
    return 0
  fi
  set +e; "$d/$name.bin"; got=$?; set -e
  if [ "$got" = "$want" ]; then
    echo "PASS  $name"
  else
    echo "FAIL  $name (expected exit $want, got $got)"
  fi
}

# Multi-file rejection: write files into <dir>, compile <main>, require <pattern>
# in stderr and no `:0:` — the same location guarantee tests/manifest/diagnostics.sexp
# gives the single-fixture rejections.
# The same, with a location prefix as well as a message — for a multi-file unit
# where the fixture path is a mktemp dir and cannot be spelled in a literal.
# Stage 15 B5 added it: which of two definers is BLAMED is half of what the
# protocol-kind tests assert, and a pattern-only check cannot see it.
w1_reject_at() {  # <name> <dir> <main.nuc> <loc-prefix> <pattern>
  local name="$1" d="$2" mainsrc="$3" loc="$4" pattern="$5" err
  err="$(./build/nucleusc -I "$d" --emit-llvm "$mainsrc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep ':0:'; then
    echo "FAIL  $name (diagnostic reports line 0)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | qgrep -F "$loc" && printf '%s' "$err" | qgrep -F "$pattern"; then
    echo "PASS  $name"
  else
    echo "FAIL  $name"
    echo "    expected location: $loc"
    echo "    expected message:  $pattern"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi
}

w1_reject_multi() {  # <name> <dir> <main.nuc> <pattern>
  local name="$1" d="$2" mainsrc="$3" pattern="$4" err
  err="$(./build/nucleusc -I "$d" --emit-llvm "$mainsrc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep ':0:'; then
    echo "FAIL  $name (diagnostic reports line 0)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | qgrep -F "$pattern"; then
    echo "PASS  $name"
  else
    echo "FAIL  $name"
    echo "    expected: $pattern"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi
}
# Stage 14 defn-signature.md S1 — the new `(defn NAME (params):ret body…)` style.
# As of Phase S4 it is the ONLY accepted style; the legacy `(defn name:ret
# (params) …)` spelling is now a hard error (negative checks below). The
# `examples/defn-newstyle.nuc` run (byte-checked above) covers the in-process
# happy path: keyword / list-form / colon-chain / tyvar returns, :void, a
# new-style defprotocol + extend, and generic stamping. These checks cover the
# remaining surfaces — the ?/! sugars + `noreturn` in the new ret position, the
# missing-ret diagnostic, and the cross-unit .nuch / cheader round-trip.


# Stage 15 W4e (design/stage15-stress-test/diagnostics.md §W4e): docs/stdlib.md's
# availability tables are GENERATED by probing build/nucleusc
# (scripts/gen-stdlib-table.py), not hand-curated. The doc used to claim
# close/dup2/dup (unistd) and isspace/isdigit (ctype) were pre-declared -- all
# five die `unknown: <name>` -- while getenv/remove/fopen/fwrite/fclose/
# snprintf/strncmp/strstr/memcmp/strcasecmp (undocumented) all silently
# resolve. Root cause: nothing is "registered at startup" -- lib/prelude.nuc
# (import-use "string.h")s directly, and transitively, via (import-use node) ->
# lib/node.nuc -> lib/arena.nuc, also (import-use "stdio.h")/(import-use
# "stdlib.h") -- ctype.h/unistd.h are simply never in that chain.
#
# Host-dependence design (deliberately NOT a byte-exact diff): availability is
# host/libc-dependent by construction (glibc vs musl, context/build.md's musl
# note), so requiring an exact match against the committed doc would fail
# spuriously on a different host. The check instead fails ONLY if a name the
# COMMITTED doc claims as available no longer probes as available on THIS
# host -- the actual finding (a false claim) -- and passes (with an
# informational note, never a failure) if this host merely finds additional or
# fewer available names than committed. See
# scripts/gen-stdlib-table.py's `check_against_committed` for the exact rule.
run_stdlib_table() {
  # `|| ec=$?`, for the reason spelled out on run_headers_generated below: a
  # bare assignment from a failing command substitution is fatal under this
  # script's `set -e`, so the unit died before its FAIL line and the harness
  # saw only an empty result file. That is how the prelude split's 165 dropped
  # libc names sat undetected behind a "zero FAIL" run.
  local out ec=0
  out="$(python3 scripts/gen-stdlib-table.py --check 2>&1)" || ec=$?
  if [ "$ec" -eq 0 ]; then
    echo "PASS  stdlib-table-generated"
  else
    echo "FAIL  stdlib-table-generated"
  fi
  printf '%s\n' "$out" | sed 's/^/    /'
}

# The other generated-and-committed artifacts: lib/*.nuch and lib/*.h. Nothing in
# the build reads the committed copies -- `make lib-headers` / `make lib-cheaders`
# overwrite them -- so a change to src/nuch.nuc or src/cheader.nuc leaves them
# describing a library that no longer exists, with no failure anywhere. This is
# the gate; scripts/check-headers.sh's header explains the four failure classes.
#
# Byte-exact, unlike stdlib-table-generated above: header emission is a pure
# function of the source, with no host probing, so any difference is real drift.
run_headers_generated() {
  # `|| ec=$?` rather than a bare assignment then `$?`: under this script's
  # `set -e` a failing command substitution in an assignment kills the unit
  # outright, which would report the failure as an empty result file and lose
  # the list of drifted headers.
  local out ec=0
  out="$(NUCLEUSC=./build/nucleusc ./scripts/check-headers.sh 2>&1)" || ec=$?
  if [ "$ec" -eq 0 ]; then
    echo "PASS  headers-generated"
  else
    echo "FAIL  headers-generated"
    printf '%s\n' "$out" | sed 's/^/    /'
  fi
}

# Stage 17 C8: the compiler's strings are StrView/String/Symbol, and what is left
# of CStr and libc's str* family in src/ is the FFI boundary itself -- enumerated
# per file and per token in scripts/cstr-allowlist.txt. Fails in BOTH directions:
# a new C-string site cannot appear silently, and a conversion that removes one
# cannot leave the list describing a compiler that no longer exists.
run_cstr_residue() {
  local out ec=0
  out="$(python3 scripts/check-cstr.py 2>&1)" || ec=$?
  if [ "$ec" -eq 0 ]; then
    echo "PASS  cstr-residue"
  else
    echo "FAIL  cstr-residue"
    printf '%s\n' "$out" | sed 's/^/    /'
  fi
}

# Stage 15 W2a: `(* 2 cl)` and `(* cl 2)` must be indistinguishable. The two
# fixtures differ only in the operands of a `*` whose right-hand side is a ui32
# global; before W2a the literal-first spelling typed the product i32 (operand
# 1's type alone) and died "mixed signed/unsigned operands" while the
# literal-second spelling compiled.
#
# "Identical IR" cannot mean byte-identical text: the emitter preserves source
# operand order, so `mul i32 2, %t2` vs `mul i32 %t2, 2` is an unavoidable and
# meaningless difference (and the module header carries the file path). Both are
# normalized away below -- the module header, and the operand order *within*
# genuinely commutative instructions only. Everything that carries typing
# information -- the IR types, the opcodes (`mul` vs `mul nsw`, `udiv` vs
# `sdiv`, `icmp ugt` vs `icmp sgt`), the instruction sequence, and the operand
# order of NON-commutative instructions such as icmp -- is compared verbatim.


# --- Dispatch sequence (original top-to-bottom order) ---------------------------

# The `examples/*.nuc` and `tests/repl/*.in` golden-output loops that stood here
# are `tests/nuctests.nuc`'s, since Stage 18 TF-6 category (b). They discover
# their inputs the same way, with `read-dir` in place of the glob.


spawn run_abi_subtest

spawn run_layout_subtest


# The two remaining Ground-truth cases (same-file defvar forward reference
# §3.5, `(defvar- g:CStr null)` §3.7) are covered by the sweep rather than a
# pinned message: W5 owns whether those spellings keep failing at all, and
# W4a's contract — a real location — holds either way. defconst-with-
# annotation (§3.2) is now pinned below (W4b decided: reject).
spawn run_no_line_zero


# --- Stage 15 W4e: docs/stdlib.md's availability table is generated ---------
spawn run_stdlib_table
spawn run_headers_generated
spawn run_cstr_residue


# --- Stage 18 TF-3: lib/read.nuc agrees with src/reader.nuc ---------------------
# Both readers print the same canonical text, so a tree difference is a diff.
# Collection literals (`[…]`, `{…}`, `#{…}`) are lib/read.nuc's one documented
# exclusion -- their desugaring infers an element type, which is compiler work.
# A rejection for any OTHER reason is a failure, so the exclusion cannot quietly
# grow. Files the compiler itself cannot parse are the reader-error fixtures.
run_reader_parity() {  # <dir>
  local dir="$1"
  local name="reader-parity-${1//\//-}"
  local ok=0 rej=0 skip=0 bad=0 d f
  d="$(mktemp -d)"
  : > "$d/detail"
  for f in "$dir"/*.nuc; do
    [ -f "$f" ] || continue
    if ! ./build/nucleusc --dump-ast "$f" > "$d/a" 2>/dev/null; then
      skip=$((skip + 1))
      continue
    fi
    if ! ./build/readdump "$f" > "$d/b" 2>"$d/err"; then
      if qgrep 'collection literals' "$d/err"; then
        rej=$((rej + 1))
      else
        bad=$((bad + 1))
        [ "$bad" -le 3 ] && echo "    $f: $(head -1 "$d/err")" >> "$d/detail"
      fi
      continue
    fi
    if diff -q "$d/a" "$d/b" >/dev/null; then
      ok=$((ok + 1))
    else
      bad=$((bad + 1))
      if [ "$bad" -le 3 ]; then
        echo "    $f: lib/read.nuc disagrees with nucleusc --dump-ast" >> "$d/detail"
        diff "$d/a" "$d/b" | head -4 | sed 's/^/      /' >> "$d/detail"
      fi
    fi
  done
  if [ "$bad" -eq 0 ]; then
    echo "PASS  $name ($ok identical, $rej collection-literal, $skip unparseable)"
  else
    echo "FAIL  $name ($bad disagreements)"
    cat "$d/detail"
  fi
  rm -rf "$d"
}

spawn run_reader_parity tests/fixtures
spawn run_reader_parity examples
spawn run_reader_parity lib
spawn run_reader_parity src

# --- Stage 18 TF-5: --diagnostics=sexp ------------------------------------------
# The structured back-end must carry exactly what the text one prints, and carry
# it as FIELDS -- one form per diagnostic, notes as a `notes` operand rather than
# as trailing lines. Two independent greps over one stderr blob cannot tell a
# location on a note from a location on the error; a field comparison can.
#
# The text back-end's byte-identity is not asserted here: the IR snapshot's
# `.ll.err` artifacts compare every fixture's diagnostic text byte for byte.
run_diagnostics_sexp() {
  local d out
  d="$(mktemp -d)"
  local ok=1

  # 1. An error: one form, on one line, with the same location the text mode
  #    printed and an empty `notes`.
  cat > "$d/e1.nuc" <<'EOF'
(defstruct Pt x:i32 y:i32)
(defn f ((p (ref Pt))):i32 (return (p 'z)))
(defn main ():i32 (return 0))
EOF
  out="$(./build/nucleusc --diagnostics=sexp --emit-llvm "$d/e1.nuc" 2>&1 >/dev/null || true)"
  if [ "$out" != "(diagnostic (severity error) (file \"$d/e1.nuc\") (line 2) (message \"get: no field 'z' on struct 'Pt'\") (notes))" ]; then
    ok=0; echo "    error form: $out"
  fi

  # 2. A note is a FIELD. The text mode prints it as a `  note: ` line, which is
  #    where it lives inside the message today -- the split is the whole point.
  out="$(./build/nucleusc --diagnostics=sexp --emit-llvm tests/fixtures/g5-noinit-ref.nuc 2>&1 >/dev/null || true)"
  if ! printf '%s' "$out" | qgrep -F '(notes "give it an initializer, or declare it nullable'; then
    ok=0; echo "    note field: $out"
  fi
  if [ "$(printf '%s\n' "$out" | wc -l)" != "1" ]; then
    ok=0; echo "    a diagnostic must be ONE line, got $(printf '%s\n' "$out" | wc -l)"
  fi

  # 3. Warnings are diagnostics too -- a mode that structured only errors would
  #    hand a reader a stream it cannot parse.
  cat > "$d/w1.nuc" <<'EOF'
(ns alpha)
(ns beta)
(defn main ():i32 (return 0))
EOF
  out="$(./build/nucleusc --diagnostics=sexp --emit-llvm "$d/w1.nuc" 2>&1 >/dev/null || true)"
  if ! printf '%s' "$out" | qgrep -F '(severity warning)'; then
    ok=0; echo "    warning form: $out"
  fi

  # 4. A field carrying a `"` survives the round trip. The path is the reachable
  #    one -- a filename may hold any byte -- and it exercises the same escaper
  #    every field uses. `readdump` reprints the canonical form, so the check is
  #    that lib/read.nuc read back the bytes the compiler wrote.
  printf '(defn main ():i32 (return (nope 1)))\n' > "$d/a\"b.nuc"
  ./build/nucleusc --diagnostics=sexp --emit-llvm "$d/a\"b.nuc" 2>"$d/q1.sexp" >/dev/null || true
  if ! qgrep -F 'a\"b.nuc' "$d/q1.sexp"; then
    ok=0; echo "    a quote in a field was not escaped: $(cat "$d/q1.sexp")"
  fi
  if ! ./build/readdump "$d/q1.sexp" > "$d/q1.ast" 2>"$d/q1.err"; then
    ok=0; echo "    lib/read.nuc could not read it: $(head -1 "$d/q1.err")"
  elif ! diff -q "$d/q1.sexp" "$d/q1.ast" >/dev/null; then
    ok=0; echo "    round trip changed the form"; diff "$d/q1.sexp" "$d/q1.ast" | head -4 | sed 's/^/      /'
  fi

  # 5. `--diagnostics=text` is the default, and naming it explicitly is a no-op.
  local a b
  a="$(./build/nucleusc --emit-llvm "$d/e1.nuc" 2>&1 >/dev/null || true)"
  b="$(./build/nucleusc --diagnostics=text --emit-llvm "$d/e1.nuc" 2>&1 >/dev/null || true)"
  if [ "$a" != "$b" ]; then
    ok=0; echo "    --diagnostics=text is not the default"
  fi

  if [ "$ok" = 1 ]; then echo "PASS  s18-diagnostics-sexp"; else echo "FAIL  s18-diagnostics-sexp"; fi
  rm -rf "$d"
}
spawn run_diagnostics_sexp

# --- Single-mode exits ----------------------------------------------------------
if [ "$MODE" = list ]; then
  exit 0
fi
if [ "$MODE" = unit ]; then
  if [ "$_unit_ran" != 1 ]; then
    echo "run-tests.sh: no such unit '$WANT'   (see $0 --list)" >&2
    exit 2
  fi
  exit "$_unit_fail"
fi

# --- Join + replay --------------------------------------------------------------
# Wait for all remaining jobs (ignore per-job exit codes — PASS/FAIL is decided
# by scanning buffered output, since `set -e` does not propagate across `&`).
# Then cat each result file in dispatch order, flagging global fail on any FAIL
# line or any unit that died before emitting output.
wait || true
fail=0
for id in "${UNIT_NAMES[@]}"; do
  out="$RESULTS_DIR/${id}.out"
  cat "$out"
  if qgrep '^FAIL' "$out" || [ ! -s "$out" ]; then
    fail=1
  fi
done

exit $fail
