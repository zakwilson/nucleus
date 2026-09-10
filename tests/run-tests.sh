#!/usr/bin/env bash
# Stage 18 TF-6 is complete: this file holds no units. All 966 verdicts are
# `tests/suite-*.nuc`, run by `build/nuctests`. What remains here is the mode
# and dispatch machinery, which TF-7 replaces with the trust anchor (§T6.9).
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
# The unit's NAME is the function plus its FIRST argument, which was the unit's
# identity everywhere it mattered — one body run over several corpora. Later
# arguments were expected diagnostic text, which joining in would have put error
# messages, spaces and parens into a name that has to survive a command line.
# Names must be unique or `--unit` cannot address them, which is checked here
# rather than left for a driver to discover.
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
