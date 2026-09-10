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

# The three meta forms a golden diff cannot hold: `dir` lists every library name
# (so any lib change rewrites it), `imports` names the prelude's own import set,
# and `time` prints a measured duration. Asserted by substring instead — the
# other thirteen are pinned exactly by tests/repl/meta-introspection.in.
#
# Together these are design/stage18-tooling §5.3: the layer they
# cover was documented, implemented, and silently lost to a rebase in 2026-06
# because no test named any of it.
run_repl_meta_loose() {
  local out fails=""
  out="$(printf '%s\n' \
    '(defn zzq (n:i32):i32 (return n))' \
    '(dir)' \
    '(imports)' \
    '(time (zzq 1))' \
    | ./build/nucleusc -i 2>&1)" || true
  # dir renders a defn as its signature, in defn spelling.
  case "$out" in *"(zzq (n:i32):i32)"*) ;; *) fails="$fails dir" ;; esac
  # imports lists resolved paths, one per line.
  case "$out" in *"lib/prelude.nuc"*) ;; *) fails="$fails imports" ;; esac
  # time evaluates the form AND reports a duration.
  case "$out" in *"; elapsed: "*) ;; *) fails="$fails time-elapsed" ;; esac
  case "$out" in *"  1"*) ;; *) fails="$fails time-value" ;; esac
  if [ -z "$fails" ]; then
    echo "PASS  repl-meta-loose"
  else
    echo "FAIL  repl-meta-loose ($fails)"
    printf '%s\n' "$out" | sed 's/^/    /'
  fi
}

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

# Stage 15 W4a / findings §2.1: the sibling forward reference across two
# imported files. Making it COMPILE is W1's job; W4a's contract is only that the
# failure names the referencing line in the referencing file instead of `:0:`.
# Asserted as "an error mentioning the referencing file, and no `:0:` anywhere",
# so this keeps passing once W1 removes the error entirely.
run_w4a_sibling_forward() {
  local d err
  d="$(mktemp -d)"
  printf '(defn x-uses ():i32\n  (return (y-later)))\n' > "$d/w4a-sib-x.nuc"
  printf '(defn y-later ():i32\n  (return 7))\n' > "$d/w4a-sib-y.nuc"
  printf '(import w4a-sib-x)\n(import w4a-sib-y)\n(defn main ():i32\n  (return (x-uses)))\n' > "$d/w4a-sib-main.nuc"
  err="$(./build/nucleusc -I "$d" --emit-llvm "$d/w4a-sib-main.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep ':0:'; then
    echo "FAIL  w4a-sibling-forward (diagnostic reports line 0)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif [ -z "$err" ] || printf '%s' "$err" | qgrep 'w4a-sib-x.nuc:2:'; then
    echo "PASS  w4a-sibling-forward"
  else
    echo "FAIL  w4a-sibling-forward"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi
  rm -rf "$d"
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

# 1. The ?/! sugar returns (:!ptr:T, :!i32, :?ptr:T) and a trailing `noreturn`
#    parse in the new position, and the define carries the LLVM noreturn attr.
run_s1_sugar_rets() {
  local s1_sugar_ll; s1_sugar_ll="$(mktemp)"
  ./build/nucleusc --emit-llvm tests/fixtures/s1-sugar-rets.nuc > "$s1_sugar_ll" 2>/dev/null || true
  if qgrep -F 'define ptr @lookup(' "$s1_sugar_ll" \
     && qgrep -F 'define i64 @checked(' "$s1_sugar_ll" \
     && qgrep -F 'define ptr @maybe-pt(' "$s1_sugar_ll" \
     && qgrep -E '^define void @spin\(ptr %m\.arg\) noreturn( |$)' "$s1_sugar_ll"; then
    echo "PASS  s1-sugar-rets-and-noreturn"
  else
    echo "FAIL  s1-sugar-rets-and-noreturn"
  fi
  rm -f "$s1_sugar_ll"
}

# 3. Cross-unit: an entirely new-style library round-trips through .nuch and links
#    with a consumer. Plain solitary defns export as (declare …); the overloaded
#    pair as (defmethod …); the bounded-generic template verbatim (new-style).
run_s1_block() {
  local s1_dir s1_lib
  s1_dir="$(mktemp -d)"
  s1_lib="$(pwd)/tests/fixtures/s1-newlib.nuc"
  ./build/nucleusc --emit-nuch    "$s1_lib" > "$s1_dir/lib.nuch" 2>/dev/null || true
  ./build/nucleusc --emit-cheader "$s1_lib" > "$s1_dir/lib.h"    2>/dev/null || true
  ./build/nucleusc --emit-llvm    "$s1_lib" > "$s1_dir/lib.ll"   2>/dev/null || true

  # 3a. The .nuch (S3) emits solitary/overloaded defns in the new-style signature
  #     `NAME (params) :ret` its declare/defmethod readers consume, and exports the
  #     generic template verbatim (also new style).
  if qgrep -F '(declare twice ((x i32)) :i32)' "$s1_dir/lib.nuch" \
     && qgrep -F '(defmethod "@scale.i32" scale ((x i32)) :i32)' "$s1_dir/lib.nuch" \
     && qgrep -F '(defn gmax ((a T) (b T) :where (Ord T)) :T' "$s1_dir/lib.nuch"; then
    echo "PASS  s1-nuch-export-shapes"
  else
    echo "FAIL  s1-nuch-export-shapes"
  fi

  # 3b. The cheader names the plain new-style prototypes correctly — and names an
  #     overloaded one the way the .nuch above already did (W9 item 26). The old
  #     `int32_t scale(int32_t x);` asserted a symbol the object never defines:
  #     `scale` is overloaded, so its methods are `@scale.i32` / `@scale.i64`.
  if qgrep -F 'int32_t twice(int32_t x);' "$s1_dir/lib.h" \
     && qgrep -F 'int32_t add3(int32_t a, int32_t b, int32_t c);' "$s1_dir/lib.h" \
     && qgrep -F 'int32_t scale_i32(int32_t x) asm("scale.i32");' "$s1_dir/lib.h" \
     && qgrep -F 'int64_t scale_i64(int64_t x) asm("scale.i64");' "$s1_dir/lib.h"; then
    echo "PASS  s1-cheader-plain-prototypes"
  else
    echo "FAIL  s1-cheader-plain-prototypes"
  fi

  # 3c. A consumer imports the .nuch, resolves the plain + overloaded symbols, links
  #     against the lib object, and runs. (exclude-prelude so the two objects link
  #     without duplicate prelude symbols; no template call, so no stamping.)
  cat > "$s1_dir/main.nuc" <<EOF
(exclude-prelude)
(import-use "$s1_dir/lib.nuch")
(declare printf (fmt:CStr):i32)
(defn main () :i32
  (printf "twice=%d add3=%d scale32=%d scale64=%ld\n"
    (twice 21) (add3 1 2 3) (scale 4) (scale (as i64 5)))
  (return 0))
EOF
  ./build/nucleusc --emit-llvm "$s1_dir/main.nuc" > "$s1_dir/main.ll" 2>/dev/null || true
  if clang "$s1_dir/lib.ll" "$s1_dir/main.ll" -o "$s1_dir/bin" 2>/dev/null \
     && [ "$("$s1_dir/bin")" = "twice=42 add3=6 scale32=40 scale64=500" ]; then
    echo "PASS  s1-nuch-link-and-run"
  else
    echo "FAIL  s1-nuch-link-and-run"
  fi

  # 3d. Importing the .nuch re-registers the new-style template so a consumer stamps
  #     it at its call sites (proves register-generic-defn + the stamper handle a
  #     new-style tyvar return arriving verbatim). Emit-only: the template body uses
  #     `if` (a prelude macro), so the consumer keeps the prelude.
  cat > "$s1_dir/tmain.nuc" <<EOF
(import-use "$s1_dir/lib.nuch")
(import-use "stdio.h")
(defn main () :i32
  (printf "gmax32=%d gmax64=%ld\n" (gmax 8 3) (gmax (as i64 4) (as i64 9)))
  (return 0))
EOF
  # W9 item 2: a stamp belongs to no file — any unit that instantiates the same
  # template at the same types re-derives the identical body under the identical
  # symbol — so it is `weak_odr`, which is what lets two objects that both
  # use `(gmax i32 i32)` link. Asserted here rather than matched loosely.
  ./build/nucleusc --emit-llvm "$s1_dir/tmain.nuc" > "$s1_dir/tmain.ll" 2>/dev/null || true
  if qgrep -F 'define weak_odr i32 @gmax.i32.i32(' "$s1_dir/tmain.ll" \
     && qgrep -F 'define weak_odr i64 @gmax.i64.i64(' "$s1_dir/tmain.ll" \
     && qgrep -F 'call i32 @gmax.i32.i32(' "$s1_dir/tmain.ll"; then
    echo "PASS  s1-nuch-template-stamps"
  else
    echo "FAIL  s1-nuch-template-stamps"
  fi
  rm -rf "$s1_dir"
}

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
run_w2a_order_identical() {
  local d a b
  d="$(mktemp -d)"
  ./build/nucleusc --emit-llvm tests/fixtures/w2a-order-lit-first.nuc \
    > "$d/first.ll" 2>"$d/first.err" || true
  ./build/nucleusc --emit-llvm tests/fixtures/w2a-order-lit-second.nuc \
    > "$d/second.ll" 2>"$d/second.err" || true
  if [ -s "$d/first.err" ] || [ -s "$d/second.err" ]; then
    echo "FAIL  w2a-operand-order-identical (compile error)"
    sed 's/^/    /' "$d/first.err" "$d/second.err"
    rm -rf "$d"
    return 0
  fi
  for f in first second; do
    grep -v -e '^; ModuleID' -e '^source_filename' "$d/$f.ll" \
      | awk '
          function ncommas(s,   i, c) {
            c = 0
            for (i = 1; i <= length(s); i++) if (substr(s, i, 1) == ",") c++
            return c
          }
          {
            line = $0
            if (line ~ /^  %[A-Za-z0-9_.]+ = (add|mul|and|or|xor|fadd|fmul)[ ]/ \
                && ncommas(line) == 1) {
              ci = index(line, ", ")
              head = substr(line, 1, ci - 1)
              b = substr(line, ci + 2)
              si = 0
              for (i = length(head); i > 0; i--) {
                if (substr(head, i, 1) == " ") { si = i; break }
              }
              a = substr(head, si + 1)
              if (a > b) { t = a; a = b; b = t }
              line = substr(head, 1, si) a ", " b
            }
            print line
          }' > "$d/$f.norm"
  done
  if diff -u "$d/first.norm" "$d/second.norm" >/dev/null; then
    echo "PASS  w2a-operand-order-identical"
  else
    echo "FAIL  w2a-operand-order-identical"
    diff -u "$d/first.norm" "$d/second.norm" | sed 's/^/    /' || true
  fi
  rm -rf "$d"
}

# Stage 15 W2d accept criterion (design/stage15-stress-test/literal-typing.md):
# a `float`-typed DSP kernel written with bare float literals — no
# `(unsafe/cast f32 …)` anywhere — must produce output identical to the
# equivalent C program, compared as exact 32-bit patterns and not just as
# rounded decimals. The two sources are checked in side by side
# (tests/fixtures/w2d-dsp-biquad.{nuc,c}) so the comparison is reproducible.
#
# The Nucleus side goes through the real compile-and-link path (`-o`), not
# `--emit-llvm`: `--emit-llvm` never parses the IR it writes, so it cannot catch
# an invalid float constant (`float 3.14`) or a type-mismatched call operand.
# The C side is built with -ffp-contract=off; see the fixture's header.
run_w2d_dsp_bitexact() {
  local d
  d="$(mktemp -d)"
  if ! ./build/nucleusc tests/fixtures/w2d-dsp-biquad.nuc -o "$d/nuc" >"$d/nuc.log" 2>&1; then
    echo "FAIL  w2d-dsp-bitexact (nucleus compile error)"
    sed 's/^/    /' "$d/nuc.log"
    rm -rf "$d"
    return 0
  fi
  if ! clang -O2 -ffp-contract=off -o "$d/c" tests/fixtures/w2d-dsp-biquad.c >"$d/c.log" 2>&1; then
    echo "FAIL  w2d-dsp-bitexact (C reference compile error)"
    sed 's/^/    /' "$d/c.log"
    rm -rf "$d"
    return 0
  fi
  "$d/nuc" > "$d/nuc.out" 2>&1 || true
  "$d/c"   > "$d/c.out"   2>&1 || true
  if diff -u "$d/c.out" "$d/nuc.out" >/dev/null; then
    echo "PASS  w2d-dsp-bitexact"
  else
    echo "FAIL  w2d-dsp-bitexact (float kernel does not match C bit-for-bit)"
    diff -u "$d/c.out" "$d/nuc.out" | sed 's/^/    /' || true
  fi
  rm -rf "$d"
}


# --- Dispatch sequence (original top-to-bottom order) ---------------------------

# The `examples/*.nuc` and `tests/repl/*.in` golden-output loops that stood here
# are `tests/nuctests.nuc`'s, since Stage 18 TF-6 category (b). They discover
# their inputs the same way, with `read-dir` in place of the glob.

spawn run_repl_meta_loose

spawn run_abi_subtest

spawn run_layout_subtest


spawn run_s1_sugar_rets


spawn run_s1_block


# --- Stage 15 W2a: binop literal typing -------------------------------------
# design/stage15-stress-test/literal-typing.md §W2a. A binop's statically
# inferred type now equals the type it emits, because both halves call one
# shared rule (`binop-result-type`, src/nucleusc.nuc). The positive matrix
# ({literal-first, literal-second, both-typed, both-literal} x {i32, i64, ui32,
# ui64} x {arith, comparison}, plus the f32 float-literal case and the two
# original repros) is examples/binop-literal-typing.nuc, run by the
# examples/*.nuc loop above against tests/expected/binop-literal-typing.out --
# result types are observed via multimethod dispatch, so a wrong unification
# prints a wrong type name instead of hiding in the IR.
#
# Here: the operand-order equivalence, and the negative half. Unifying operand
# types must NOT silently sign-reinterpret two TYPED operands of different
# signedness -- only an untyped literal adapts -- so the mixed-sign diagnostic
# has to survive the fix, in both the arithmetic and comparison forms.
spawn run_w2a_order_identical


# --- Stage 15 W2d: float literals adapt to an f32 target ---------------------
# design/stage15-stress-test/literal-typing.md section W2d. The positive matrix
# (every position that used to reject an f32 target -- let/with init, set!,
# .set!, explicit and implicit return, struct-literal and array initializers,
# call arguments, the defvar global initializer -- checked by VALUE, plus the
# f64 lanes that must stay f64) is examples/float-literal-typing.nuc, run by the
# examples/*.nuc loop above. The bit-exactness accept criterion is
# run_w2d_dsp_bitexact.
#
# Here: the three boundaries the fix must NOT cross. A float literal adapts to a
# float target only (not an integer slot, not an integer binop operand), and
# multimethod dispatch admits a float literal but never a typed f64 value.
spawn run_w2d_dsp_bitexact


# The two remaining Ground-truth cases (same-file defvar forward reference
# §3.5, `(defvar- g:CStr null)` §3.7) are covered by the sweep rather than a
# pinned message: W5 owns whether those spellings keep failing at all, and
# W4a's contract — a real location — holds either way. defconst-with-
# annotation (§3.2) is now pinned below (W4b decided: reject).
spawn run_no_line_zero
spawn run_w4a_sibling_forward


# --- Stage 15 W4e: docs/stdlib.md's availability table is generated ---------
spawn run_stdlib_table
spawn run_headers_generated
spawn run_cstr_residue


# Stage 17 B2: `read-line` over a buffered fd 0. Not an example — an example
# inherits the harness's stdin and would block on a terminal — so the input is
# piped here. The last line deliberately has no terminator, and the blank line
# must come back as a zero-length String rather than being skipped.
run_s17_read_line() {
  local bin actual
  bin="./build/out/s17-read-line"
  rm -f "$bin"
  if ! ./build/nucleusc tests/fixtures/s17-read-line.nuc -o "$bin" 2>&1; then
    echo "FAIL  s17-read-line (compile error)"
    return 0
  fi
  actual="$(printf 'alpha\nbeta\n\nno-newline' | "$bin" 2>&1 || true)"
  if [ "$actual" = "1: [alpha] len=5
2: [beta] len=4
3: [] len=0
4: [no-newline] len=10
eof" ]; then
    echo "PASS  s17-read-line"
  else
    echo "FAIL  s17-read-line"
    printf '%s\n' "$actual" | sed 's/^/    got: /'
  fi
}
spawn run_s17_read_line

# Stage 17 C6: a bare string literal returned from a `StrView` function. The
# struct-return path skipped the coercion that materializes the chameleon
# literal, so LLVM rejected `store %StrView <bare ptr>` with no source location.
run_s17_strview_literal_return() {
  local bin actual
  bin="./build/out/s17-strview-literal-return"
  rm -f "$bin"
  if ! ./build/nucleusc tests/fixtures/s17-strview-literal-return.nuc -o "$bin" 2>&1; then
    echo "FAIL  s17-strview-literal-return (compile error)"
    return 0
  fi
  actual="$("$bin" 2>&1 || true)"
  if [ "$actual" = "$(cat tests/expected/s17-strview-literal-return.out)" ]; then
    echo "PASS  s17-strview-literal-return"
  else
    echo "FAIL  s17-strview-literal-return"
    printf '%s\n' "$actual" | sed 's/^/    got: /'
  fi
}
spawn run_s17_strview_literal_return

# Stage 17 C6: string literals meeting at a cond/if/match phi in a StrView slot.
# The unconditional collapse to CStr made the phi carry bare data pointers, and
# the aggregate return then read a length off the end of a pointer-sized slot.
run_s17_strview_literal_join() {
  local bin actual
  bin="./build/out/s17-strview-literal-join"
  rm -f "$bin"
  if ! ./build/nucleusc tests/fixtures/s17-strview-literal-join.nuc -o "$bin" 2>&1; then
    echo "FAIL  s17-strview-literal-join (compile error)"
    return 0
  fi
  actual="$("$bin" 2>&1 || true)"
  if [ "$actual" = "$(cat tests/expected/s17-strview-literal-join.out)" ]; then
    echo "PASS  s17-strview-literal-join"
  else
    echo "FAIL  s17-strview-literal-join"
    printf '%s\n' "$actual" | sed 's/^/    got: /'
  fi
}
spawn run_s17_strview_literal_join

# Stage 17 C7-4b: the null-check trap one level down. A `StrView` is a 16-byte
# struct that is never null, so `(= sv null)` fell into the CStr strcmp lowering
# and compared its `.data` against NULL — a SIGSEGV, silently. It is a type
# error now, and the diagnostic names the predicate the author meant.
run_s17_strview_null_compare_rejected() {
  local d out
  d="$(mktemp -d)"
  printf '(defn main ():i32\n  (let (sv:StrView "abc")\n    (when (!= sv null) (return 1))\n    (return 0)))\n' > "$d/s17nsv.nuc"
  out="$(./build/nucleusc --emit-llvm "$d/s17nsv.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$out" | qgrep -F 's17nsv.nuc:3: error: !=: a StrView is never null'; then
    echo "PASS  s17-strview-null-compare-rejected"
  else
    echo "FAIL  s17-strview-null-compare-rejected"
    echo "    got: ${out:-<none>}"
  fi
  rm -rf "$d"
}
spawn run_s17_strview_null_compare_rejected

# Stage 19: lib/process.nuc. One unit per phase gate — P1 status decoding, P2
# capture (including the both-pipes-overflow case that deadlocks a sequential
# drain), P3 the job-pool primitives.
run_s19_process_status() {
  local bin actual
  bin="./build/out/s19-process-status"
  rm -f "$bin"
  if ! ./build/nucleusc tests/fixtures/s19-process-status.nuc -o "$bin" 2>&1; then
    echo "FAIL  s19-process-status (compile error)"
    return 0
  fi
  actual="$("$bin" 2>&1 || true)"
  if [ "$actual" = "zero 0
three 3
killed 137
noexec 127
signal 15" ]; then
    echo "PASS  s19-process-status"
  else
    echo "FAIL  s19-process-status"
    printf '%s\n' "$actual" | sed 's/^/    got: /'
  fi
}
spawn run_s19_process_status

run_s19_process_capture() {
  local bin actual
  bin="./build/out/s19-process-capture"
  rm -f "$bin"
  if ! ./build/nucleusc tests/fixtures/s19-process-capture.nuc -o "$bin" 2>&1; then
    echo "FAIL  s19-process-capture (compile error)"
    return 0
  fi
  # The timeout IS the assertion for the overflow case: a sequential drain hangs.
  actual="$(timeout 60 "$bin" 2>&1 || true)"
  if [ "$actual" = "code 3
out to-stdout
err to-stderr
big-out 1288895 big-err 1288895 code 0
arg a b \"c\" \$d
env new=yes home=/s19-overridden" ]; then
    echo "PASS  s19-process-capture"
  else
    echo "FAIL  s19-process-capture"
    printf '%s\n' "$actual" | sed 's/^/    got: /'
  fi
}
spawn run_s19_process_capture

run_s19_process_pool() {
  local bin actual
  bin="./build/out/s19-process-pool"
  rm -f "$bin"
  if ! ./build/nucleusc tests/fixtures/s19-process-pool.nuc -o "$bin" 2>&1; then
    echo "FAIL  s19-process-pool (compile error)"
    return 0
  fi
  actual="$(timeout 60 "$bin" 2>&1 || true)"
  if [ "$actual" = "try-wait: still running
reaped 2
reaped 3
reaped 1
killed: signal 9" ]; then
    echo "PASS  s19-process-pool"
  else
    echo "FAIL  s19-process-pool"
    printf '%s\n' "$actual" | sed 's/^/    got: /'
  fi
}
spawn run_s19_process_pool

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
