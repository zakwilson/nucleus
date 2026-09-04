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

# Bring the compiler up to date BEFORE dispatch. run_example shells out to
# build.sh, which runs `make` — harmless when the tree is already built, but if
# any src/*.nuc is newer then 161 parallel jobs relink build/nucleusc while the
# other jobs are executing it, and every unit dies with "Text file busy".
[ "$MODE" = run ] && make -s

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
# unit's identity everywhere it matters: `run_example <src>`, `run_fixture <src>`,
# `run_reject <name> ...`. Later arguments are expected diagnostic text — joining
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
    _unit_ran=1
    return 0
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

run_example() {  # <src>
  local src="$1" name expected actual_file build_log
  name="$(basename "$src" .nuc)"
  expected="tests/expected/${name}.out"
  [ -f "$expected" ] || return 0
  # Never let a stale binary from a prior run mask a compile failure: a
  # successful old binary would let the diff pass silently. The compiler writes
  # the binary atomically on success, so removing it first means a missing
  # binary after build.sh unambiguously signals "did not compile".
  rm -f "./build/out/$name"
  build_log="$(mktemp)"
  # Capture build output and check the exit code explicitly. `set -e` would
  # otherwise kill this unit silently on a compile error, leaving an empty
  # result file that the replay loop can flag as failed but cannot explain.
  if ! ./build.sh "$src" >"$build_log" 2>&1; then
    echo "FAIL  $name (compile error)"
    sed 's/^/    /' "$build_log"
    rm -f "$build_log"
    return 0
  fi
  rm -f "$build_log"
  actual_file="$(mktemp)"
  ./build/out/"$name" > "$actual_file" 2>&1 || true
  if diff -u "$expected" "$actual_file" >/dev/null; then
    echo "PASS  $name"
  else
    echo "FAIL  $name"
    diff -u "$expected" "$actual_file" || true
  fi
  rm -f "$actual_file"
}

# REPL session tests: pipe each tests/repl/<name>.in into `nucleusc -i` and
# compare against tests/expected/repl-<name>.out.
run_repl() {  # <src>
  local src="$1" name expected actual_file
  name="$(basename "$src" .in)"
  expected="tests/expected/repl-${name}.out"
  [ -f "$expected" ] || return 0
  actual_file="$(mktemp)"
  ./build/nucleusc -i < "$src" > "$actual_file" 2>&1 || true
  if diff -u "$expected" "$actual_file" >/dev/null; then
    echo "PASS  repl-$name"
  else
    echo "FAIL  repl-$name"
    diff -u "$expected" "$actual_file" || true
  fi
  rm -f "$actual_file"
}

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

# Cross-target emission: each triple in the Phase-B matrix must produce IR
# carrying the matching `target triple` line. Guards against a backend not
# being registered (which makes --emit-llvm reject the triple).
run_target_triple() {  # <triple>
  local triple="$1" tmpfile
  tmpfile="$(mktemp)"
  ./build/nucleusc --target="$triple" --emit-llvm examples/hello.nuc > "$tmpfile" 2>/dev/null || true
  if qgrep "target triple = \"$triple\"" "$tmpfile"; then
    echo "PASS  target-$triple"
  else
    echo "FAIL  target-$triple"
  fi
  rm -f "$tmpfile"
}

# Stage 14 AVR-1: cross-emitting for the AVR MCU target. The compiler must
# register the AVR backend (targets-init-all), emit the AVR datalayout/triple,
# and thread --mcpu into the TargetMachine. The IR-emission gate: the system
# `llc` (AVR backend, verified in AVR-0) must lower a scalar example to an AVR
# object without errors. The llc step is conditional on llc being installed so
# the suite still runs where the AVR toolchain is absent.
run_avr_emit() {  # <cpu>
  local cpu="$1" tmpfile obj
  tmpfile="$(mktemp)"
  ./build/nucleusc --target=avr --mcpu="$cpu" --emit-llvm examples/arith.nuc \
    > "$tmpfile" 2>/dev/null || true
  if qgrep 'target triple = "avr"' "$tmpfile" \
     && qgrep 'target datalayout = "e-P1-p:16:8-' "$tmpfile"; then
    echo "PASS  avr-emit-$cpu"
  else
    echo "FAIL  avr-emit-$cpu (datalayout/triple)"
  fi
  if command -v llc >/dev/null 2>&1; then
    obj="$(mktemp)"
    if llc -mtriple=avr -mcpu="$cpu" -filetype=obj "$tmpfile" -o "$obj" 2>/dev/null \
       && [ -s "$obj" ]; then
      echo "PASS  avr-llc-$cpu"
    else
      echo "FAIL  avr-llc-$cpu (llc rejected emitted IR)"
    fi
    rm -f "$obj"
  fi
  rm -f "$tmpfile"
}

# Stage 14 AVR-2: 16-bit correctness. The design gate is "an AVR-targeted example
# using usize, sizeof, and a union round-trips through llc cleanly." The fixture
# exercises usize/sizeof (ptr-int-ir/ptr-int-type → i16, Task 1) and a tagged
# union round-trip. The load-bearing regression check is the qq-helper fix
# (Task 2): a runtime quasiquote forces emit-qq-helpers, whose Node cell must be
# `malloc(i64 22)` (16 + 3*2) with `align 1` on AVR — not the host 40/align 8.
# llc alone will NOT catch a wrong-but-well-formed malloc size, so we grep the
# emitted IR directly for the 16-bit-derived literals, then round-trip through
# llc for both reference devices (attiny1634 + the avrxmega3 family core).
run_avr2_16bit() {  # <cpu>
  local cpu="$1" tmpfile obj
  tmpfile="$(mktemp)"
  ./build/nucleusc --target=avr --mcpu="$cpu" --emit-llvm tests/fixtures/avr2-16bit.nuc \
    > "$tmpfile" 2>/dev/null || true
  # 16-bit correctness in the emitted text: AVR datalayout, sizeof/usize as i16
  # (ptrtoint to i16), and the qq-helper Node cell as malloc(i64 22) / align 1.
  if qgrep 'target datalayout = "e-P1-p:16:8-' "$tmpfile" \
     && qgrep 'ptrtoint ptr .* to i16' "$tmpfile" \
     && qgrep 'call ptr @malloc(i64 22)' "$tmpfile" \
     && qgrep 'store ptr %a, ptr %p4, align 1' "$tmpfile" \
     && ! qgrep 'call ptr @malloc(i64 40)' "$tmpfile"; then
    echo "PASS  avr2-16bit-$cpu"
  else
    echo "FAIL  avr2-16bit-$cpu (16-bit width / qq-helper malloc size or align)"
  fi
  if command -v llc >/dev/null 2>&1; then
    obj="$(mktemp)"
    if llc -mtriple=avr -mcpu="$cpu" -filetype=obj "$tmpfile" -o "$obj" 2>/dev/null \
       && [ -s "$obj" ]; then
      echo "PASS  avr2-llc-$cpu"
    else
      echo "FAIL  avr2-llc-$cpu (llc rejected emitted IR)"
    fi
    rm -f "$obj"
  fi
  rm -f "$tmpfile"
}

# Stage 15 W9 item 15: a GEP index is sized by the target pointer, not written
# as a literal `i64`. Two assertions, because the old code failed two ways and
# only one of them is a parse error:
#
#   (a) llvm-as must accept the AVR IR. An index at or above the pointer width
#       was passed through unwidened while the annotation still read `i64`, so
#       `getelementptr … i64 %t1` named a register defined as i16 — rejected
#       outright ("'%t1' defined with type 'i16' but expected 'i64'"). This is
#       the half that made `usize`, the natural index type, unusable on AVR.
#
#   (b) No `i64` may appear at all. A NARROWER index was widened to a real i64,
#       which parses fine and would sail past (a) while emitting 64-bit
#       arithmetic on an 8-bit MCU. Grepping for the absence is the only way to
#       see it.
#
# The host arm asserts the annotation FOLLOWS the target rather than having been
# swapped for a different constant: the same fixture must read `i64` there.
run_w9_gep_index_width() {
  local avr_ir host_ir
  avr_ir="$(mktemp)"; host_ir="$(mktemp)"
  ./build/nucleusc --target=avr --mcpu=attiny1634 --emit-llvm \
    tests/fixtures/w9-gep-index-width.nuc > "$avr_ir" 2>/dev/null || true
  ./build/nucleusc --emit-llvm \
    tests/fixtures/w9-gep-index-width.nuc > "$host_ir" 2>/dev/null || true

  if ! llvm-as "$avr_ir" -o /dev/null 2>/dev/null; then
    echo "FAIL  w9-gep-index-width-avr-parses (LLVM rejected the emitted AVR IR)"
    llvm-as "$avr_ir" -o /dev/null 2>&1 | sed 's/^/    /' | head -4
  elif [ "$(grep -c 'getelementptr inbounds i8, ptr %t[0-9]*, i16 ' "$avr_ir")" -eq 6 ]; then
    echo "PASS  w9-gep-index-width-avr-parses"
  else
    echo "FAIL  w9-gep-index-width-avr-parses (expected 6 pointer-sized i16 GEP indices)"
    grep -n 'getelementptr' "$avr_ir" | sed 's/^/    /'
  fi

  # Instruction lines only: the AVR datalayout line names i64 as a legal scalar
  # width, which says nothing about whether any instruction uses one.
  if qgrep '^  .*i64' "$avr_ir"; then
    echo "FAIL  w9-gep-index-width-avr-no-i64 (64-bit index arithmetic on a 16-bit target)"
    grep -n '^  .*i64' "$avr_ir" | sed 's/^/    /' | head -4
  else
    echo "PASS  w9-gep-index-width-avr-no-i64"
  fi

  if [ "$(grep -c 'getelementptr inbounds i8, ptr %t[0-9]*, i64 ' "$host_ir")" -eq 6 ]; then
    echo "PASS  w9-gep-index-width-host"
  else
    echo "FAIL  w9-gep-index-width-host (host GEP index is not pointer-sized i64)"
    grep -n 'getelementptr' "$host_ir" | sed 's/^/    /'
  fi
  rm -f "$avr_ir" "$host_ir"
}

# Stage 15 W9 item 18: comparing a function-pointer value lowers to `icmp … ptr`.
# The exit code carries the assertion — it is the sum of six comparisons across
# all four positions a function pointer occupies (global/param/local, and
# identity against a function symbol and against another slot), so a comparison
# that compiles but answers wrongly fails here rather than passing as "accepted".
# The two greps pin the shapes that cannot be produced by any other lowering:
# identity against a function SYMBOL, and the null literal in LEFT position.
run_w9_fnptr_compare() {
  local ir bin rc
  ir="$(mktemp)"; bin="$(mktemp)"
  ./build/nucleusc --emit-llvm tests/fixtures/w9-fnptr-compare.nuc > "$ir" 2>/dev/null || true

  if ! llvm-as "$ir" -o /dev/null 2>/dev/null; then
    echo "FAIL  w9-fnptr-compare-ir (LLVM rejected the emitted IR)"
    llvm-as "$ir" -o /dev/null 2>&1 | sed 's/^/    /' | head -4
  elif qgrep 'icmp eq ptr %t[0-9]*, @twice' "$ir" \
    && qgrep 'icmp ne ptr null, %t[0-9]*' "$ir"; then
    echo "PASS  w9-fnptr-compare-ir"
  else
    echo "FAIL  w9-fnptr-compare-ir (fn-pointer identity did not lower to icmp on ptr)"
    grep -n 'icmp [a-z]* ptr ' "$ir" | tail -8 | sed 's/^/    /'
  fi

  # `-x ir`: the mktemp path has no .ll suffix for clang to infer the language from.
  if clang -w -x ir "$ir" -o "$bin" 2>/dev/null; then
    "$bin" >/dev/null 2>&1 && rc=0 || rc=$?
    if [ "$rc" -eq 2 ]; then
      echo "PASS  w9-fnptr-compare-run"
    else
      echo "FAIL  w9-fnptr-compare-run (six comparisons summed to $rc, expected 2)"
    fi
  else
    echo "FAIL  w9-fnptr-compare-run (link failed)"
  fi
  rm -f "$ir" "$bin"
}

# Stage 15 W9 item 19: a function-pointer slot is one TARGET pointer wide.
# `type-size` had no TY-FN case, so every fn-pointer global/alloca/load/store
# claimed `align 1` -- free on x86-64, but a strict-alignment backend honours
# the claim and splits the access byte-wise (one `ldr` -> four `ldrb` + three
# `orr` on armv7). The first check is the invariant rather than a count: NO
# `ptr`-valued slot may claim `align 1`. Matching on the *value* type keeps
# `store i1 %x, ptr %y, align 1` (correct: i1 is one byte) out of it.
run_w9_fnptr_align() {
  local ir ir32 bin rc under
  ir="$(mktemp)"; ir32="$(mktemp)"; bin="$(mktemp)"
  ./build/nucleusc --emit-llvm tests/fixtures/w9-fnptr-align.nuc > "$ir" 2>/dev/null || true
  ./build/nucleusc --target=i386-unknown-linux-gnu --emit-llvm \
    tests/fixtures/w9-fnptr-align.nuc > "$ir32" 2>/dev/null || true

  under='(alloca ptr, align 1$|load ptr, ptr [^,]*, align 1$'
  under="$under"'|store ptr [^,]*, ptr [^,]*, align 1$|^@[^ ]* = global ptr .*, align 1$)'
  if ! llvm-as "$ir" -o /dev/null 2>/dev/null; then
    echo "FAIL  w9-fnptr-align-ir (LLVM rejected the emitted IR)"
    llvm-as "$ir" -o /dev/null 2>&1 | sed 's/^/    /' | head -4
  elif [ "$(grep -cE "$under" "$ir")" -ne 0 ]; then
    echo "FAIL  w9-fnptr-align-ir ($(grep -cE "$under" "$ir") ptr slots claim align 1)"
    grep -nE "$under" "$ir" | head -6 | sed 's/^/    /'
  elif qgrep -E '^@fn-global = global ptr null,( section "[^"]*",)? align 8' "$ir" \
    && qgrep '%loc.addr.[0-9]* = alloca ptr, align 8' "$ir" \
    && qgrep '%h.addr = alloca ptr, align 8' "$ir"; then
    echo "PASS  w9-fnptr-align-ir"
  else
    echo "FAIL  w9-fnptr-align-ir (a global/local/param fn-pointer slot is not pointer-aligned)"
    grep -nE '^@fn-global |\.addr[0-9.]* = alloca ptr' "$ir" | head -6 | sed 's/^/    /'
  fi

  # Item 15's rule, on item 19's operand: the width is the TARGET's, not 8.
  if qgrep -E '^@fn-global = global ptr null,( section "[^"]*",)? align 4' "$ir32" \
    && qgrep '%loc.addr.[0-9]* = alloca ptr, align 4' "$ir32"; then
    echo "PASS  w9-fnptr-align-target-width"
  else
    echo "FAIL  w9-fnptr-align-target-width (32-bit target did not use a 4-byte fn-pointer slot)"
    grep -nE '^@fn-global |%loc\.addr' "$ir32" | head -4 | sed 's/^/    /'
  fi

  # `-x ir`: the mktemp path has no .ll suffix for clang to infer the language from.
  if clang -w -x ir "$ir" -o "$bin" 2>/dev/null; then
    "$bin" >/dev/null 2>&1 && rc=0 || rc=$?
    if [ "$rc" -eq 19 ]; then
      echo "PASS  w9-fnptr-align-run"
    else
      echo "FAIL  w9-fnptr-align-run (slots summed to $rc, expected 19)"
    fi
  else
    echo "FAIL  w9-fnptr-align-run (link failed)"
  fi
  rm -f "$ir" "$ir32" "$bin"
}

# Stage 15 W9 item 20: the literal `null` reaches a fn-pointer slot in every
# position, not just `defvar`. The IR check pins that this costs no instruction
# -- the literal is a retype, so the field store is a plain `store ptr null` --
# and the exit code carries the semantics.
run_w9_fnptr_null_init() {
  local ir bin rc
  ir="$(mktemp)"; bin="$(mktemp)"
  ./build/nucleusc --emit-llvm tests/fixtures/w9-fnptr-null-init.nuc > "$ir" 2>/dev/null || true

  if ! llvm-as "$ir" -o /dev/null 2>/dev/null; then
    echo "FAIL  w9-fnptr-null-init-ir (LLVM rejected the emitted IR)"
    llvm-as "$ir" -o /dev/null 2>&1 | sed 's/^/    /' | head -4
  elif qgrep '^@g-hook = global ptr null' "$ir" \
    && qgrep 'store ptr null, ptr %loc.addr' "$ir" \
    && qgrep 'ret ptr null' "$ir"; then
    echo "PASS  w9-fnptr-null-init-ir"
  else
    echo "FAIL  w9-fnptr-null-init-ir (the null literal did not reach a fn slot as a plain null)"
    grep -nE 'store ptr null|ret ptr null|^@g-hook' "$ir" | head -6 | sed 's/^/    /'
  fi

  # `-x ir`: the mktemp path has no .ll suffix for clang to infer the language from.
  if clang -w -x ir "$ir" -o "$bin" 2>/dev/null; then
    "$bin" >/dev/null 2>&1 && rc=0 || rc=$?
    if [ "$rc" -eq 38 ]; then
      echo "PASS  w9-fnptr-null-init-run"
    else
      echo "FAIL  w9-fnptr-null-init-run (slots summed to $rc, expected 38)"
    fi
  else
    echo "FAIL  w9-fnptr-null-init-run (link failed)"
  fi
  rm -f "$ir" "$bin"
}

# Stage 14 AVR-3 (design/stage14/avr-targets.md §5): the link driver + build
# flow. This is the first *end-to-end* AVR gate — a real link, not just IR/llc.
# On an AVR triple the compiler drives `avr-gcc -mmcu=<device>` (not `clang`) and
# produces a linked `.elf`. The fixture is a freestanding MMIO blink with
# `(exclude-prelude)`, so no host-runtime symbols (perror/malloc from the
# intern/arena runtime) are pulled in — a freestanding program is a handful of
# bytes, whereas a pulled-in runtime would fail to link (undefined perror) or
# balloon to kilobytes. avr-size sanity-checks the footprint against that. Gated
# on avr-gcc so the suite still runs where the full AVR toolchain is absent (a
# SKIP keeps the result file non-empty — an empty result is treated as FAIL).
# Covers both reference devices: attiny1634 (mcpu names an exact device, so no
# separate --mmcu) and the AVR-Dx family core avrxmega3 + --mmcu=avr32dd20 (the
# family-codegen + explicit-device link path — also the regression proof that
# --mmcu, not --mcpu, supplies the device name on the AVR link line).
run_avr3_link() {  # <name> <cpu> [<mmcu>]
  local name="$1" cpu="$2" mmcu="${3:-}" elf txt dat
  if ! command -v avr-gcc >/dev/null 2>&1; then
    echo "SKIP  avr3-link-$name (avr-gcc not installed)"
    return 0
  fi
  elf="$(mktemp).elf"
  rm -f "$elf"
  # An actual link (no -c/--emit-llvm): the compiler emits the object and shells
  # out to avr-gcc, producing the final .elf.
  if [ -n "$mmcu" ]; then
    ./build/nucleusc --target=avr --mcpu="$cpu" --mmcu="$mmcu" \
      tests/fixtures/avr3-link.nuc -o "$elf" 2>/dev/null || true
  else
    ./build/nucleusc --target=avr --mcpu="$cpu" \
      tests/fixtures/avr3-link.nuc -o "$elf" 2>/dev/null || true
  fi
  if [ -s "$elf" ] && file "$elf" 2>/dev/null | qgrep 'Atmel AVR 8-bit'; then
    # avr-size Berkeley columns: text data bss. A freestanding blink is tens of
    # bytes of data, not the hundreds/kilobytes a host runtime would add; text is
    # dominated by the device crt/vector table (a few hundred bytes), so a
    # kilobyte-plus text also signals a pulled-in runtime.
    set -- $(avr-size "$elf" | awk 'NR==2 {print $1, $2}')
    txt="${1:-999999}"; dat="${2:-999999}"
    if [ "$dat" -lt 256 ] && [ "$txt" -lt 4096 ]; then
      echo "PASS  avr3-link-$name (text=$txt data=$dat)"
    else
      echo "FAIL  avr3-link-$name (footprint out of freestanding range: text=$txt data=$dat)"
    fi
  else
    echo "FAIL  avr3-link-$name (no linked .elf produced)"
  fi
  rm -f "$elf"
}

# Stage 14 AVR-5 (design/stage14/avr-targets.md §5): ISRs + function attributes.
# The `(fn-attr <name> "signal")` directive attaches the LLVM AVR "signal"
# function attribute to a `defn`; an ISR is that attribute on a `defn` named for
# an avr-libc vector symbol (`__vector_<N>`). The gate is end-to-end: link an
# ISR example for the ATmega328P (the CI-simulatable device, whose vector 13 is
# TIMER1_OVF = __vector_13) and confirm via `avr-objdump -d` that (a) the vector
# table jumps to __vector_13 — the strong symbol overrode avr-libc's weak
# __bad_interrupt default — and (b) the ISR ends in `reti` (the return-from-
# interrupt instruction the "signal" attribute is specifically what causes the
# AVR backend to emit, instead of a plain `ret`). Gated on avr-gcc + avr-objdump
# (a SKIP keeps the result line non-empty, treated as pass-through, not FAIL).
run_avr5_isr() {
  local elf dis
  if ! command -v avr-gcc >/dev/null 2>&1 || ! command -v avr-objdump >/dev/null 2>&1; then
    echo "SKIP  avr5-isr (avr-gcc/avr-objdump not installed)"
    return 0
  fi
  elf="$(mktemp).elf"
  rm -f "$elf"
  ./build/nucleusc --target=avr --mcpu=atmega328p \
    examples/avr-isr.nuc -o "$elf" 2>/dev/null || true
  if [ ! -s "$elf" ] || ! file "$elf" 2>/dev/null | qgrep 'Atmel AVR 8-bit'; then
    echo "FAIL  avr5-isr (no linked .elf produced)"
    rm -f "$elf"
    return 0
  fi
  dis="$(avr-objdump -d "$elf" 2>/dev/null)"
  # (a) the vector table jumps to our handler; (b) the handler ends in reti.
  # The reti check inspects only the __vector_13 function body (from its label to
  # the next blank line) so a stray reti elsewhere can't spoof the result.
  if printf '%s\n' "$dis" | qgrep 'jmp.*<__vector_13>' \
     && printf '%s\n' "$dis" | awk '/<__vector_13>:/{f=1} f&&/\treti/{print;exit}' | qgrep 'reti'; then
    echo "PASS  avr5-isr (vector jump + reti epilogue)"
  else
    echo "FAIL  avr5-isr (missing vector jump to __vector_13 or reti epilogue)"
  fi
  rm -f "$elf"
}

# Stage 14 AVR-6 (design/stage14/avr-targets.md §5): the Harvard function-value
# hazard. On AVR functions live in program memory (addrspace(1)); a function
# materialized as a first-class DATA pointer value is `ptr addrspace(1)` where a
# plain `ptr` is required — an LLVM verifier error. v1 diagnoses at compile time
# rather than emitting IR the backend rejects. The gate is prog-as-keyed (parsed
# from the datalayout `P<n>` — 1 on AVR, 0 on hosts): the SAME fixture that dies
# on AVR must compile cleanly on the host, proving the diagnostic is descriptor-
# keyed. Compiler-only (--emit-llvm), so it runs even without the AVR toolchain.
run_avr6_fnvalue() {
  local avr_err host_ok
  avr_err="$(./build/nucleusc --target=avr --mcpu=attiny1634 --emit-llvm \
    tests/fixtures/avr6-fnvalue.nuc 2>&1 >/dev/null || true)"
  if ./build/nucleusc --emit-llvm tests/fixtures/avr6-fnvalue.nuc >/dev/null 2>&1; then
    host_ok=1
  else
    host_ok=0
  fi
  if printf '%s' "$avr_err" | qgrep -F "cannot use function 'add' as a value on this target" \
     && [ "$host_ok" -eq 1 ]; then
    echo "PASS  avr6-fnvalue-diagnostic"
  else
    echo "FAIL  avr6-fnvalue-diagnostic (AVR must reject; host must accept)"
  fi
}

# Stage 14 AVR-6: the `:const` declaration attribute on a defvar global emits an
# LLVM `constant` (read-only) instead of a mutable `global`; a plain defvar is
# unchanged (so existing programs stay byte-identical). Pure emission, host-only.
run_avr6_const() {
  local ir
  ir="$(./build/nucleusc --emit-llvm tests/fixtures/avr6-const.nuc 2>/dev/null || true)"
  if printf '%s' "$ir" | qgrep '@answer = constant i32 42' \
     && printf '%s' "$ir" | qgrep '@mutable-count = global i32 0'; then
    echo "PASS  avr6-const-global"
  else
    echo "FAIL  avr6-const-global (:const must emit 'constant'; plain defvar must stay 'global')"
  fi
}

# Stage 14 AVR-7 (design/stage14/avr-targets.md §5): the f64 numerics policy. f64
# is unsupported on AVR (8-bit target, no hardware double) — a compile-time error
# naming the -mdouble=64 escape hatch. It is caught at BOTH finalization points:
# an explicit :f64/double annotation (parse-type-name) AND a bare float literal's
# f64 default (emit-float) — a diagnostic at only one site would miss the other.
# The gate is target-keyed like the AVR-6 fn-value one: the SAME fixtures that die
# on AVR must compile cleanly on the host (f64 is fine there). f32 and i64 must
# still compile on AVR. Compiler-only (--emit-llvm), so it runs without the AVR
# toolchain.
run_avr7_f64() {
  local annot_avr lit_avr dbl_avr msg pass
  msg="f64 is not supported on AVR"
  pass=1
  # 1. explicit :f64 annotation — AVR rejects, host accepts.
  annot_avr="$(./build/nucleusc --target=avr --mcpu=attiny1634 --emit-llvm \
    tests/fixtures/avr7-f64-annot.nuc 2>&1 >/dev/null || true)"
  printf '%s' "$annot_avr" | qgrep -F "$msg" || pass=0
  ./build/nucleusc --emit-llvm tests/fixtures/avr7-f64-annot.nuc >/dev/null 2>&1 || pass=0
  # 2. "double" spelling — AVR rejects.
  dbl_avr="$(./build/nucleusc --target=avr --mcpu=attiny1634 --emit-llvm \
    tests/fixtures/avr7-f64-annot.nuc 2>&1 >/dev/null || true)"
  printf '%s' "$dbl_avr" | qgrep -F "$msg" || pass=0
  # 3. bare float literal default (no f64 text) — AVR rejects via emit-float,
  #    host accepts.
  lit_avr="$(./build/nucleusc --target=avr --mcpu=attiny1634 --emit-llvm \
    tests/fixtures/avr7-f64-literal.nuc 2>&1 >/dev/null || true)"
  printf '%s' "$lit_avr" | qgrep -F "$msg" || pass=0
  ./build/nucleusc --emit-llvm tests/fixtures/avr7-f64-literal.nuc >/dev/null 2>&1 || pass=0
  if [ "$pass" -eq 1 ]; then
    echo "PASS  avr7-f64-rejected (annotation + bare literal; host accepts)"
  else
    echo "FAIL  avr7-f64-rejected (AVR must reject :f64 and 1.5; host must accept)"
  fi
  # 4. f32 is allowed on AVR (emits `float`).
  if ./build/nucleusc --target=avr --mcpu=attiny1634 --emit-llvm \
       tests/fixtures/avr7-f32.nuc 2>/dev/null | qgrep 'float'; then
    echo "PASS  avr7-f32-allowed"
  else
    echo "FAIL  avr7-f32-allowed (f32 must compile on AVR)"
  fi
  # 5. i64 is allowed on AVR (emits an i64 multiply; libgcc __muldi3 at link).
  if ./build/nucleusc --target=avr --mcpu=attiny1634 --emit-llvm \
       tests/fixtures/avr7-i64.nuc 2>/dev/null | qgrep 'mul nsw i64'; then
    echo "PASS  avr7-i64-allowed"
  else
    echo "FAIL  avr7-i64-allowed (i64 must compile on AVR)"
  fi
}

# Stage 14 AVR-7: the aggregate ABI. AVR classifies EVERY struct/union (any size)
# as ABI-MEMORY with aarch64-style plain-pointer passing — no byval, bypassing the
# SysV eightbyte model that assumes 8-byte register chunks. The gate is target-
# keyed: the SAME <=16-byte Point struct that a host register-coerces (COERCE1 —
# `@sum(i32 ...)`, `@mk` returns `i32`) must, on AVR, become a plain-pointer MEMORY
# param (`@sum(ptr ...)`) and an sret return, with zero `byval`. When avr-gcc is
# present the fixture is also linked end-to-end (avr-size sanity) to prove llc/
# avr-gcc accept the emitted ABI. Emission part is compiler-only.
run_avr7_struct() {
  local avr_ir host_ir pass
  pass=1
  avr_ir="$(./build/nucleusc --target=avr --mcpu=atmega328p --emit-llvm \
    tests/fixtures/avr7-struct.nuc 2>/dev/null || true)"
  host_ir="$(./build/nucleusc --emit-llvm tests/fixtures/avr7-struct.nuc 2>/dev/null || true)"
  # AVR: plain-pointer MEMORY param, sret return, no byval.
  printf '%s' "$avr_ir" | qgrep 'define i16 @sum(ptr ' || pass=0
  printf '%s' "$avr_ir" | qgrep 'sret(%Point)' || pass=0
  printf '%s' "$avr_ir" | qgrep 'byval' && pass=0
  # Host: the same <=16-byte struct is register-coerced (eightbyte model active),
  # proving the AVR bypass is target-keyed (host param is NOT a plain ptr).
  printf '%s' "$host_ir" | qgrep 'define i16 @sum(i32 ' || pass=0
  if [ "$pass" -eq 1 ]; then
    echo "PASS  avr7-struct-abi (AVR plain-ptr MEMORY + sret; host register-coerced)"
  else
    echo "FAIL  avr7-struct-abi (AVR must use plain-ptr MEMORY/sret, no byval; host register-coerced)"
  fi
  # End-to-end link when the AVR toolchain is present.
  if ! command -v avr-gcc >/dev/null 2>&1; then
    echo "SKIP  avr7-struct-link (avr-gcc not installed)"
    return
  fi
  local elf
  elf="$(mktemp -u).elf"
  ./build/nucleusc --target=avr --mcpu=atmega328p \
    tests/fixtures/avr7-struct.nuc -o "$elf" 2>/dev/null || true
  if [ -f "$elf" ] && avr-size "$elf" >/dev/null 2>&1; then
    echo "PASS  avr7-struct-link"
    rm -f "$elf"
  else
    echo "FAIL  avr7-struct-link (avr-gcc rejected the struct-by-value ABI)"
  fi
}

# Stage 14 RV-1: cross-emitting for the riscv64 Linux target. The compiler must
# register the RISCV backend (targets-init-all), emit the riscv64 datalayout/
# triple, the `target-abi=lp64d` module flag, and thread the +m,+a,+f,+d,+c
# features into the TargetMachine. The load-bearing check is the "features cliff"
# (design/stage14/riscv-linux.md §1.2): with the correct features llc lowers an
# i64 multiply to a hardware `mul` and an f64 add to `fadd.d`; with bare RV64I
# they become `__muldi3`/`__adddf3` soft-float libcalls — a SILENT ABI mismatch
# with riscv64 glibc (lp64d), not an error. The llc step is conditional on llc
# being installed (same guard as the AVR gate) so the suite still runs without it.
run_riscv_emit() {
  local tmpfile asm
  tmpfile="$(mktemp)"
  ./build/nucleusc --target=riscv64-unknown-linux-gnu --emit-llvm \
    tests/fixtures/riscv-features.nuc > "$tmpfile" 2>/dev/null || true
  if qgrep 'target triple = "riscv64-unknown-linux-gnu"' "$tmpfile" \
     && qgrep 'target datalayout = "e-m:e-p:64:64-' "$tmpfile" \
     && qgrep '!"target-abi", !"lp64d"' "$tmpfile"; then
    echo "PASS  riscv-emit"
  else
    echo "FAIL  riscv-emit (datalayout/triple/module-flags)"
  fi
  if command -v llc >/dev/null 2>&1; then
    asm="$(mktemp)"
    # The asm mnemonic column is tab-indented; anchor at line start so a `.globl`
    # of a symbol containing "mul" can't false-match the multiply instruction.
    if llc -mtriple=riscv64 -mattr=+m,+a,+f,+d,+c -filetype=asm "$tmpfile" -o "$asm" 2>/dev/null \
       && qgrep -E '^[[:space:]]*mul[[:space:]]' "$asm" \
       && qgrep 'fadd\.d' "$asm" \
       && ! qgrep '__muldi3' "$asm" \
       && ! qgrep '__adddf3' "$asm"; then
      echo "PASS  riscv-llc-features"
    else
      echo "FAIL  riscv-llc-features (features cliff: libcalls instead of hardware mul/fadd.d)"
    fi
    rm -f "$asm"
  fi
  rm -f "$tmpfile"
}

# Stage 14 RV-6 (design/stage14/riscv-fp-abi.md): the riscv64 lp64d hard-float
# struct ABI — §1's flattening rules and §4's register counting. There is no
# riscv64 hardware in the container (§7), so this is a CROSS-EMISSION gate: each
# expected shape below was derived from
# `clang --target=riscv64-unknown-linux-gnu -O0 -S -emit-llvm` on structurally
# identical C, and is pinned here so the rules cannot silently regress the way
# RV-3's deferral note did. The x86_64 half is the anti-leak control: the same
# structs must still lower as SysV, which is what the byte-identical bootstrap
# would otherwise be the only witness for.
#
# BOTH lanes name their triple explicitly. Letting the SysV lane ride the default
# target made the gate assert "the host is x86_64", so it fired on riscv64
# hardware reporting correct riscv lowering as a leak. A cross-emission gate is
# host-independent by construction; the triple is the thing under test, never an
# ambient. (The x86_64 backend's availability is separately gated by
# run_target_triple x86_64-pc-linux-gnu.)
run_rv6_fp_abi() {
  local rv x86
  rv="$(mktemp)"; x86="$(mktemp)"
  ./build/nucleusc --target=riscv64-unknown-linux-gnu --emit-llvm \
    tests/fixtures/rv6-fp-abi.nuc > "$rv" 2>/dev/null || true
  ./build/nucleusc --target=x86_64-pc-linux-gnu --emit-llvm \
    tests/fixtures/rv6-fp-abi.nuc > "$x86" 2>/dev/null || true

  # §1: one FP real, two FP reals, an array/nested struct that flattens, and
  # rule 3 in both member orders — with the member order preserved in reg0/reg1.
  if qgrep '^define float @f_f1(float %v\.arg)' "$rv" \
     && qgrep '^define { double, double } @f_dd(double %v\.arg\.0, double %v\.arg\.1)' "$rv" \
     && qgrep '^define { float, float } @f_farr2(float %v\.arg\.0, float %v\.arg\.1)' "$rv" \
     && qgrep '^define { float, float } @f_nest(float %v\.arg\.0, float %v\.arg\.1)' "$rv" \
     && qgrep '^define { i32, float } @f_mixed(i32 %v\.arg\.0, float %v\.arg\.1)' "$rv" \
     && qgrep '^define { float, i32 } @f_mixedrev(float %v\.arg\.0, i32 %v\.arg\.1)' "$rv" \
     && qgrep '^define { i64, double } @f_longmix(i64 %v\.arg\.0, double %v\.arg\.1)' "$rv" \
     && qgrep '^define i64 @f_pair(i64 %v\.arg)' "$rv"; then
    echo "PASS  rv6-flatten-rules"
  else
    echo "FAIL  rv6-flatten-rules (riscv64 lp64d flattening, riscv-fp-abi.md §1)"
    grep -E '^define .*@f_' "$rv" | sed 's/^/    /'
  fi

  # §4: the same aggregate flattens while its registers are free and takes the
  # integer convention once they are not — separately for FPRs, GPRs, and the
  # GPR the hidden sret pointer spends before the first argument.
  if qgrep '^define i32 @fpr7_mixed(.*double %g\.arg, i32 %m\.arg\.0, float %m\.arg\.1)' "$rv" \
     && qgrep '^define i32 @fpr8_mixed(.*double %h\.arg, i64 %m\.arg)' "$rv" \
     && qgrep '^define i32 @fpr6_dd(.*double %f\.arg, double %m\.arg\.0, double %m\.arg\.1)' "$rv" \
     && qgrep '^define i32 @fpr7_dd(.*double %g\.arg, i64 %m\.arg\.0, i64 %m\.arg\.1)' "$rv" \
     && qgrep '^define i32 @gpr7_mixed(.*i64 %g\.arg, i32 %m\.arg\.0, float %m\.arg\.1)' "$rv" \
     && qgrep '^define i32 @gpr8_mixed(.*i64 %h\.arg, i64 %m\.arg)' "$rv" \
     && qgrep '^define i32 @gpr8_f1(.*i64 %h\.arg, float %m\.arg)' "$rv" \
     && qgrep '^define i32 @gpr8_dd(.*i64 %h\.arg, double %m\.arg\.0, double %m\.arg\.1)' "$rv" \
     && qgrep '^define void @sret6_mixed(ptr sret(%Big).*i64 %f\.arg, i32 %m\.arg\.0, float %m\.arg\.1)' "$rv" \
     && qgrep '^define void @sret7_mixed(ptr sret(%Big).*i64 %g\.arg, i64 %m\.arg)' "$rv"; then
    echo "PASS  rv6-register-counting"
  else
    echo "FAIL  rv6-register-counting (riscv64 argument register budget, riscv-fp-abi.md §4)"
    grep -E '^define .*@(fpr|gpr|sret)' "$rv" | sed 's/^/    /'
  fi

  # §1: a variadic argument is never flattened and never takes an FPR, so no
  # float/double operand may appear in the printf call.
  local vcall
  vcall="$(grep -F 'call i32 (ptr, ...) @printf' "$rv" | head -1)"
  if [ -n "$vcall" ] \
     && ! printf '%s' "$vcall" | qgrep -E '(float|double) %'; then
    echo "PASS  rv6-variadic-integer-convention"
  else
    echo "FAIL  rv6-variadic-integer-convention (a vararg aggregate was flattened into FP registers)"
    printf '%s\n' "$vcall" | sed 's/^/    /'
  fi

  # Anti-leak control: x86_64 SysV packs {float[2]} into one SSE eightbyte and
  # {i32,f32} into one INTEGER eightbyte — the riscv rules must not reach it.
  if qgrep '^define <2 x float> @f_farr2(<2 x float> %v\.arg)' "$x86" \
     && qgrep '^define <2 x float> @f_nest(<2 x float> %v\.arg)' "$x86" \
     && qgrep '^define i64 @f_mixed(i64 %v\.arg)' "$x86" \
     && qgrep '^define i64 @f_mixedrev(i64 %v\.arg)' "$x86" \
     && qgrep '^define i32 @fpr8_mixed(.*double %h\.arg, i64 %m\.arg)' "$x86"; then
    echo "PASS  rv6-x86-unchanged"
  else
    echo "FAIL  rv6-x86-unchanged (riscv classification leaked into the SysV path)"
    grep -E '^define .*@(f_|fpr8_mixed)' "$x86" | sed 's/^/    /'
  fi
  rm -f "$rv" "$x86"
}

# `long` ABI model (Phase D): C `long` resolves per the target's data model.
# Parse a header with long/long long functions and check the emitted declares.
abs_long_h="$(pwd)/tests/abi/long.h"
# Each check_long writes/reads/removes its OWN probe file (keyed by triple) so
# the four calls are fully decoupled and can run in parallel — concurrent reads
# of a shared probe were fine, but the single trailing rm raced the last checks.
check_long() {  # <triple> <expected-lfn-ir> <expected-llfn-ir>
  local triple="$1" want_l="$2" want_ll="$3"
  local probe; probe="$(pwd)/tests/abi/.long_probe_${triple}.nuc"
  printf '(import-use "%s")\n(defn use () :i64 (return (lfn 1)))\n' "$abs_long_h" > "$probe"
  local tmpfile; tmpfile="$(mktemp)"
  ./build/nucleusc --target="$triple" --emit-llvm "$probe" > "$tmpfile" 2>/dev/null || true
  if qgrep "declare $want_l @lfn(" "$tmpfile" \
     && qgrep "declare $want_ll @llfn(" "$tmpfile"; then
    echo "PASS  long-abi-$triple"
  else
    echo "FAIL  long-abi-$triple (want lfn:$want_l llfn:$want_ll)"
  fi
  rm -f "$tmpfile" "$probe"
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

# Stage 12 N6: .nuch + --emit-cheader namespace round-trip. A library in the
# `geom` namespace exports mangled link names (@geom__area). The .nuch must carry
# (ns geom) so an importer re-resolves geom/area to @geom__area, and the cheader
# must emit the C-legal name `geom__area` — not the Nucleus name `geom/area`.
run_ns6() {
  local ns6_dir ns6_lib
  ns6_dir="$(mktemp -d)"
  ns6_lib="$(pwd)/tests/fixtures/nsgeomlib.nuc"
  ./build/nucleusc --emit-nuch    "$ns6_lib" > "$ns6_dir/lib.nuch"  2>/dev/null || true
  ./build/nucleusc --emit-cheader "$ns6_lib" > "$ns6_dir/lib.h"     2>/dev/null || true
  ./build/nucleusc --emit-llvm    "$ns6_lib" > "$ns6_dir/lib.ll"    2>/dev/null || true

  # 1. The .nuch carries the namespace directive so the importer can re-mangle.
  if qgrep '^(ns geom)' "$ns6_dir/lib.nuch"; then
    echo "PASS  n6-nuch-carries-ns"
  else
    echo "FAIL  n6-nuch-carries-ns"
  fi

  # 2. The cheader emits the C-legal mangled name, never the slash form.
  if qgrep 'geom__area' "$ns6_dir/lib.h" && ! qgrep 'geom/area' "$ns6_dir/lib.h"; then
    echo "PASS  n6-cheader-c-legal"
  else
    echo "FAIL  n6-cheader-c-legal"
  fi

  # 3. Importing the .nuch by path re-resolves geom/area to @geom__area, and the
  #    consumer links against the lib object and runs.
  # The consumer excludes the prelude (the lib object already provides it) so the
  # two objects link without duplicate prelude symbols. It needs only `printf`
  # (declared) and the imported geom symbols, so no prelude operators are used.
  # printf is declared with its FIXED parameter only: Nucleus has no variadic-
  # `declare` spelling, call arity is not checked against a declaration, and the
  # extra arguments ride the call site — which is how the C ABI passes them. (This
  # and the two sibling sites below used to write `(fmt:CStr :rest args:i32)`,
  # which did nothing but add two phantom i32 parameters to the declaration: the
  # calls here pass 3-6 arguments to it. `:rest` in a declaration is now refused.)
  cat > "$ns6_dir/main.nuc" <<EOF
(exclude-prelude)
(import-prefixed "$ns6_dir/lib.nuch" g)
(declare printf (fmt:CStr):i32)
(defn main () :i32
  (printf "area=%d perimeter=%d\n" (g/area 6 7) (g/perimeter 6 7))
  (return 0))
EOF
  ./build/nucleusc --emit-llvm "$ns6_dir/main.nuc" > "$ns6_dir/main.ll" 2>/dev/null || true
  if qgrep 'call i32 @geom__area' "$ns6_dir/main.ll"; then
    echo "PASS  n6-import-resolves-mangled"
  else
    echo "FAIL  n6-import-resolves-mangled"
  fi
  if clang "$ns6_dir/lib.ll" "$ns6_dir/main.ll" -o "$ns6_dir/bin" 2>/dev/null \
     && [ "$("$ns6_dir/bin")" = "area=42 perimeter=26" ]; then
    echo "PASS  n6-nuch-link-and-run"
  else
    echo "FAIL  n6-nuch-link-and-run"
  fi

  # 4. Stage 15 B3′: the same round trip for a namespaced TYPE. R1 gave a type a
  #    namespace, so all three export surfaces have to agree on which name it
  #    carries — the LLVM `%gt__Pt`, the C `typedef … gt__Pt` (two namespaces may
  #    now both define `Pt`, so an unprefixed typedef would collide in any program
  #    including both headers), and the `.nuch`, which carries `(ns gt)` plus the
  #    BARE spelling so the importer re-keys it under `gt/` itself.
  cat > "$ns6_dir/tylib.nuc" <<'EOF'
(ns gt)
(defstruct Pt x:i32 y:i32)
(defn pt-sum ((p (ref Pt))):i32 (return (+ (_get p 'x) (_get p 'y))))
EOF
  ./build/nucleusc --emit-nuch    "$ns6_dir/tylib.nuc" > "$ns6_dir/tylib.nuch" 2>/dev/null || true
  ./build/nucleusc --emit-cheader "$ns6_dir/tylib.nuc" > "$ns6_dir/tylib.h"    2>/dev/null || true
  ./build/nucleusc --emit-llvm    "$ns6_dir/tylib.nuc" > "$ns6_dir/tylib.ll"   2>/dev/null || true
  if qgrep -F '%gt__Pt = type' "$ns6_dir/tylib.ll" \
     && qgrep -F '} gt__Pt;' "$ns6_dir/tylib.h" \
     && qgrep -F '(ns gt)' "$ns6_dir/tylib.nuch" \
     && qgrep -F '(defstruct Pt ' "$ns6_dir/tylib.nuch"; then
    echo "PASS  b3-ns-type-export-surfaces"
  else
    echo "FAIL  b3-ns-type-export-surfaces"
  fi

  # …and the .nuch consumer resolves the type through the prefix it bound, links
  # against the library object and runs. This is the whole re-keying chain end to
  # end: `(ns gt)` in the header re-registers `gt/Pt`, `g/Pt` resolves to it
  # through the import environment, and the call reaches @gt__pt-sum.
  cat > "$ns6_dir/tymain.nuc" <<EOF
(exclude-prelude)
(import-prefixed "$ns6_dir/tylib.nuch" g)
(declare printf (fmt:CStr):i32)
(defn main () :i32
  (let (p:(ref g/Pt) (g/Pt 20 22))
    (printf "sum=%d\n" (g/pt-sum p)))
  (return 0))
EOF
  ./build/nucleusc --emit-llvm "$ns6_dir/tymain.nuc" > "$ns6_dir/tymain.ll" 2>/dev/null || true
  if clang "$ns6_dir/tylib.ll" "$ns6_dir/tymain.ll" -o "$ns6_dir/tybin" 2>/dev/null \
     && [ "$("$ns6_dir/tybin")" = "sum=42" ]; then
    echo "PASS  b3-ns-type-nuch-link-and-run"
  else
    echo "FAIL  b3-ns-type-nuch-link-and-run"
  fi
  rm -rf "$ns6_dir"
}

# Stage 14 SM-3: `?`/`!` symbol mangling survives the export surfaces (.nuch and
# --emit-cheader). A library exports `?`/`!`-named functions; their public link
# names carry the SM-1 mnemonic mangling (`?`→_QMARK, `!`→_BANG). The .nuch must
# round-trip them — solitary names via the shared ns-ir-base derivation, the
# overloaded `?` pair via each method's stored (defmethod "@sym" ...) string — so
# an importer re-derives the exact symbols the lib object defines, and the cheader
# must name those C-legal symbols (never the illegal `full?`). A second fixture
# checks the SM-3 sanitize-for-c fix: `?`/`!` in struct/union TYPE names.
run_sm3() {
  local sm3_dir sm3_lib
  sm3_dir="$(mktemp -d)"
  sm3_lib="$(pwd)/tests/fixtures/sm3-predlib.nuc"
  ./build/nucleusc --emit-nuch    "$sm3_lib" > "$sm3_dir/lib.nuch" 2>/dev/null || true
  ./build/nucleusc --emit-cheader "$sm3_lib" > "$sm3_dir/lib.h"    2>/dev/null || true
  ./build/nucleusc --emit-llvm    "$sm3_lib" > "$sm3_dir/lib.ll"   2>/dev/null || true

  # 1. The .nuch round-trips both name kinds: solitary `?`/`!` as (declare ...) and
  #    the overloaded `?` pair as (defmethod "@even_QMARK.<tok>" ...) carrying the
  #    stored mangled string verbatim.
  if qgrep -F '(declare full? ((n i32)) :i32)' "$sm3_dir/lib.nuch" \
     && qgrep -F '(declare push! ((n i32)) :i32)' "$sm3_dir/lib.nuch" \
     && qgrep -F '(defmethod "@even_QMARK.i32"' "$sm3_dir/lib.nuch" \
     && qgrep -F '(defmethod "@even_QMARK.i64"' "$sm3_dir/lib.nuch"; then
    echo "PASS  sm3-nuch-roundtrip"
  else
    echo "FAIL  sm3-nuch-roundtrip"
  fi

  # 2. The lib object defines the mnemonic-mangled symbols.
  if qgrep -F 'define i32 @full_QMARK' "$sm3_dir/lib.ll" \
     && qgrep -F 'define i32 @push_BANG' "$sm3_dir/lib.ll" \
     && qgrep -F 'define i32 @even_QMARK.i32' "$sm3_dir/lib.ll" \
     && qgrep -F 'define i32 @even_QMARK.i64' "$sm3_dir/lib.ll"; then
    echo "PASS  sm3-lib-symbols"
  else
    echo "FAIL  sm3-lib-symbols"
  fi

  # 3. The cheader names the real C-legal function symbols, never the illegal `full?`.
  if qgrep -F 'full_QMARK(' "$sm3_dir/lib.h" \
     && qgrep -F 'push_BANG(' "$sm3_dir/lib.h" \
     && ! qgrep -F 'full?' "$sm3_dir/lib.h"; then
    echo "PASS  sm3-cheader-fn-legal"
  else
    echo "FAIL  sm3-cheader-fn-legal"
  fi

  # 4. Importing the .nuch re-derives the exact symbols the lib object defines, so a
  #    consumer links and runs. Solitary `full?`/`push!` resolve via ns-ir-base;
  #    overloaded `even?` dispatches to @even_QMARK.i32 / .i64 through the imported
  #    defmethod entries. The consumer excludes the prelude (the lib object already
  #    provides it) so the two objects link without duplicate prelude symbols.
  cat > "$sm3_dir/main.nuc" <<EOF
(exclude-prelude)
(import-use "$sm3_dir/lib.nuch")
(declare printf (fmt:CStr):i32)
(defn main () :i32
  (printf "full=%d push=%d even4=%d even7=%d even6L=%d\n"
    (full? 5) (push! 7) (even? 4) (even? 7) (even? (as i64 6)))
  (return 0))
EOF
  ./build/nucleusc --emit-llvm "$sm3_dir/main.nuc" > "$sm3_dir/main.ll" 2>/dev/null || true
  if qgrep -F 'call i32 @full_QMARK' "$sm3_dir/main.ll" \
     && qgrep -F 'call i32 @push_BANG' "$sm3_dir/main.ll" \
     && qgrep -F 'call i32 @even_QMARK.i32' "$sm3_dir/main.ll" \
     && qgrep -F 'call i32 @even_QMARK.i64' "$sm3_dir/main.ll"; then
    echo "PASS  sm3-import-resolves-mangled"
  else
    echo "FAIL  sm3-import-resolves-mangled"
  fi
  if clang "$sm3_dir/lib.ll" "$sm3_dir/main.ll" -o "$sm3_dir/bin" 2>/dev/null \
     && [ "$("$sm3_dir/bin")" = "full=1 push=8 even4=1 even7=0 even6L=1" ]; then
    echo "PASS  sm3-nuch-link-and-run"
  else
    echo "FAIL  sm3-nuch-link-and-run"
  fi

  # 5. sanitize-for-c maps `?`/`!` in struct/union TYPE names to _QMARK/_BANG (the
  #    SM-3 fix proper), across all three call sites: the defstruct typedef name, the
  #    defunion typedef name, and a `struct <name>` reference in a param.
  ./build/nucleusc --emit-cheader tests/fixtures/sm3-typenames.nuc > "$sm3_dir/types.h" 2>/dev/null || true
  if qgrep -F '} Full_QMARK;' "$sm3_dir/types.h" \
     && qgrep -F '} Push_BANG;' "$sm3_dir/types.h" \
     && qgrep -F '} Shape_QMARK;' "$sm3_dir/types.h" \
     && qgrep -F 'struct Full_QMARK* f' "$sm3_dir/types.h"; then
    echo "PASS  sm3-cheader-typenames"
  else
    echo "FAIL  sm3-cheader-typenames"
  fi
  rm -rf "$sm3_dir"
}

# Single-fixture rejection checks: compiling <fixture> must FAIL with <pattern>
# on stderr. Each is independent (its own nucleusc invocation), so each is its
# own job. qgrep -F is safe for all patterns below (none carry regex metachars).
run_reject() {  # <name> <fixture> <pattern>
  local name="$1" fixture="$2" pattern="$3" err
  err="$(./build/nucleusc --emit-llvm "$fixture" 2>&1 >/dev/null || true)"
  # Stage 15 W4a: a rejection that reports `:0:` is a regression even when the
  # message text is right. Checked here so every existing and future rejection
  # test carries the location guarantee for free.
  if printf '%s' "$err" | qgrep ':0:'; then
    echo "FAIL  $name (diagnostic reports line 0)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | qgrep -F "$pattern"; then
    echo "PASS  $name"
  else
    echo "FAIL  $name"
  fi
}

# Stage 15 W4a: like run_reject, but also pins the diagnostic's LOCATION.
# `loc` is the literal "<path>:<line>: error:" prefix the compiler must print.
# The whole name-resolution family used to report `:0:` because the subject of
# the diagnostic is an interned symbol node with no per-occurrence line; these
# fixtures are what keep the reference's own line in the message.
run_reject_at() {  # <name> <fixture> <loc-prefix> <pattern>
  local name="$1" fixture="$2" loc="$3" pattern="$4" err
  err="$(./build/nucleusc --emit-llvm "$fixture" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep -F "$loc" && printf '%s' "$err" | qgrep -F "$pattern"; then
    echo "PASS  $name"
  else
    echo "FAIL  $name"
    echo "    expected location: $loc"
    echo "    expected message:  $pattern"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi
}

# The inverse of run_reject: a fixture that must COMPILE CLEAN. For pinning a
# deliberate carve-out, where the risk is that a later, stricter check swallows
# a spelling that is supposed to stay legal — run_no_line_zero only sweeps for
# `:0:`, and would not notice a fixture that started failing outright.
run_accepts() {  # <name> <fixture>
  local name="$1" fixture="$2" err
  err="$(./build/nucleusc --emit-llvm "$fixture" 2>&1 >/dev/null || true)"
  if [ -z "$err" ]; then
    echo "PASS  $name"
  else
    echo "FAIL  $name (must compile clean, but the compiler complained)"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi
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

# --- Stage 15 W1: whole-unit signature resolution ----------------------------
# design/stage15-stress-test/resolution.md. A `defn` in ANY reachable file of the
# compilation unit is callable from any other; import order does not affect
# resolution. Each unit below writes its files, compiles+LINKS, runs the program
# and checks its exit status — an exit-0 compile alone would not catch a call
# routed to the wrong symbol.

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

# The shape that actually motivates W1 (resolution.md's corrected repro E): two
# files that depend on each other's functions, each importing what it uses.
# Before W1a this failed in BOTH orders — `mx.nuc:1: unknown: y-later` one way,
# `my.nuc:1: unknown: x-helper` the other — because signature registration was
# purely ordinal. The back-import stays out of it — this is the common-parent
# spelling, which W1d's Option 2 keeps valid and recommended even though a mutual
# `(import …)` pair is now legal too (run_w1d_cycle_accepts, below).
run_w1_mutual() {
  local d
  d="$(mktemp -d)"
  printf '(defn x-uses ():i32 (return (y-later)))\n(defn x-helper ():i32 (return 7))\n' > "$d/w1-mx.nuc"
  printf '(defn y-later ():i32 (return (x-helper)))\n' > "$d/w1-my.nuc"
  printf '(import w1-mx)\n(import w1-my)\n(defn main ():i32 (return (x-uses)))\n' > "$d/w1-m1.nuc"
  printf '(import w1-my)\n(import w1-mx)\n(defn main ():i32 (return (x-uses)))\n' > "$d/w1-m2.nuc"
  w1_run w1-mutual-order1 "$d" "$d/w1-m1.nuc" 7
  w1_run w1-mutual-order2 "$d" "$d/w1-m2.nuc" 7
  rm -rf "$d"
}

# W1b: the same, across namespaces. A defn signature is namespace-qualified —
# scope-define qualifies the key and generic-new snapshots the ir-prefix — so the
# whole-graph prescan must apply each visited file's OWN leading `(ns …)`.
# Prescanning nsa under the importer's namespace would register `a-thing` under
# the wrong key and mangle it under the wrong prefix; before W1a the
# `(import nsa)`-first order failed with `unknown: beta/b-thing`.
#
# Stage 15 B2b re-pointed the SPELLINGS, not the assertion. R3 (name-resolution.md
# §8.3) makes a namespace nameable only through an import that binds it, so
# `w1-nsa` now imports `w1-nsb` to say `w1beta/`, and the two drivers use
# `import-use` (which binds the namespace qualifier — §8.3 row 1) instead of the
# prefixed `import` (which binds `w1-nsa/`, never `w1alpha/`). What the test
# measures is unchanged and still fails without W1a: `a-thing`'s signature must
# be prescan-registered under `w1alpha/a-thing` in BOTH import orders, which
# only happens if the whole-graph prescan applies each visited file's own `(ns)`.
run_w1_ns() {
  local d
  d="$(mktemp -d)"
  printf '(ns w1alpha)\n(import-use w1-nsb)\n(defn a-thing ():i32 (return (w1beta/b-thing)))\n' > "$d/w1-nsa.nuc"
  printf '(ns w1beta)\n(defn b-thing ():i32 (return 42))\n' > "$d/w1-nsb.nuc"
  printf '(import-use w1-nsa)\n(import-use w1-nsb)\n(defn main ():i32 (return (w1alpha/a-thing)))\n' > "$d/w1-nm1.nuc"
  printf '(import-use w1-nsb)\n(import-use w1-nsa)\n(defn main ():i32 (return (w1alpha/a-thing)))\n' > "$d/w1-nm2.nuc"
  w1_run w1-ns-order1 "$d" "$d/w1-nm1.nuc" 42
  w1_run w1-ns-order2 "$d" "$d/w1-nm2.nuc" 42
  rm -rf "$d"
}

# The port's harder graph shapes, all of which worked before W1a and must keep
# working (the walk dedups on resolved path, so a file reached twice is
# prescanned once):
#   diamond      — two importers of one shared leaf;
#   two-routes   — one file reachable both directly and through a chain;
#   two-higher   — a file forward-referencing up into two independent higher
#                  files with no chaining between them.
run_w1_graph_shapes() {
  local d
  d="$(mktemp -d)"
  printf '(defn w1-leaf ():i32 (return 5))\n' > "$d/w1-leaf.nuc"
  printf '(import w1-leaf)\n(defn w1-dl ():i32 (return (w1-leaf)))\n' > "$d/w1-dl.nuc"
  printf '(import w1-leaf)\n(defn w1-dr ():i32 (return (+ (w1-leaf) 1)))\n' > "$d/w1-dr.nuc"
  printf '(import w1-dl)\n(import w1-dr)\n(defn main ():i32 (return (+ (w1-dl) (w1-dr))))\n' > "$d/w1-diamond.nuc"
  w1_run w1-diamond "$d" "$d/w1-diamond.nuc" 11

  # w1-leaf is reachable directly AND through w1-dl; neither route may re-emit it.
  printf '(import w1-dl)\n(import w1-leaf)\n(defn main ():i32 (return (+ (w1-dl) (w1-leaf))))\n' > "$d/w1-routes.nuc"
  w1_run w1-two-routes "$d" "$d/w1-routes.nuc" 10

  printf '(defn w1-hi-a ():i32 (return 3))\n' > "$d/w1-hi-a.nuc"
  printf '(defn w1-hi-b ():i32 (return 4))\n' > "$d/w1-hi-b.nuc"
  printf '(defn w1-low ():i32 (return (* (w1-hi-a) (w1-hi-b))))\n' > "$d/w1-low.nuc"
  printf '(import w1-hi-a)\n(import w1-hi-b)\n(import w1-low)\n(defn main ():i32 (return (w1-low)))\n' > "$d/w1-higher.nuc"
  w1_run w1-two-higher "$d" "$d/w1-higher.nuc" 12
  rm -rf "$d"
}

# The two things W1a must NOT relax. (1) Two files defining the same name+arity
# are still a duplicate — silent last-wins would be a worse regression than the
# bug W1a fixes. (2) A name defined nowhere in the graph is still `unknown:`.
run_w1_still_rejects() {
  local d err
  d="$(mktemp -d)"
  printf '(defn w1-dupe (n:i32):i32 (return n))\n' > "$d/w1-dup-a.nuc"
  printf '(defn w1-dupe (n:i32):i32 (return (+ n 1)))\n' > "$d/w1-dup-b.nuc"
  printf '(import w1-dup-a)\n(import w1-dup-b)\n(defn main ():i32 (return (w1-dupe 1)))\n' > "$d/w1-dup.nuc"
  err="$(./build/nucleusc -I "$d" --emit-llvm "$d/w1-dup.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep "duplicate definition of 'w1-dupe'"; then
    echo "PASS  w1-duplicate-rejected"
  else
    echo "FAIL  w1-duplicate-rejected"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi

  printf '(import w1-dup-a)\n(defn main ():i32 (return (w1-nowhere)))\n' > "$d/w1-missing.nuc"
  err="$(./build/nucleusc -I "$d" --emit-llvm "$d/w1-missing.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep 'unknown: w1-nowhere'; then
    echo "PASS  w1-missing-rejected"
  else
    echo "FAIL  w1-missing-rejected"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi
  rm -rf "$d"
}

# resolution.md W1e: `(declare f …)` as the cross-file cycle-breaker keeps
# working. Once the whole-graph prescan registers every reachable signature,
# EVERY such declare matches a reachable defn — emit-nuch-declare-import's
# "already in g-globals" early return is what keeps that a no-op instead of a
# duplicate, so this is the guard on that interaction.
run_w1_declare_cycle_breaker() {
  local d
  d="$(mktemp -d)"
  printf '(declare w1-a-fn (i32):i32)\n(defn w1-b-fn (n:i32):i32 (if (= n 0) (return 2) (return (w1-a-fn (- n 1)))))\n' > "$d/w1-bf3.nuc"
  printf '(import w1-bf3)\n(defn w1-a-fn (n:i32):i32 (if (= n 0) (return 1) (return (w1-b-fn (- n 1)))))\n' > "$d/w1-af3.nuc"
  printf '(import w1-af3)\n(defn main ():i32 (return (w1-a-fn 3)))\n' > "$d/w1-decl1.nuc"
  w1_run w1-declare-cycle-breaker "$d" "$d/w1-decl1.nuc" 2
  # The declare and a reachable defn of the same name coexisting in one unit.
  printf '(import w1-af3)\n(import w1-bf3)\n(defn main ():i32 (return (w1-a-fn 3)))\n' > "$d/w1-decl2.nuc"
  w1_run w1-declare-plus-import "$d" "$d/w1-decl2.nuc" 2
  rm -rf "$d"
}

# --- Stage 15 W1d: a mutual `(import …)` pair is LEGAL -----------------------
# resolution.md "W1d — mutual imports", Option 2 (chosen 2026-07-31, superseding
# the Option 1 decision recorded the same day). `do-import` skips a re-entry of
# an in-progress path instead of erroring, so a cycle compiles; W1a already
# registers every reachable file's signatures before any emission, so every
# cross-file reference in the cycle resolves.
#
# This block REPLACES `run_w1_circular_still_errors`, which pinned the old hard
# error. That test was doing its job — the policy changed, so the pin moved with
# it. What it guarded (the diagnostic must be located, and relaxing the rule must
# be deliberate) is preserved: the positive cases below compile, LINK and run,
# and each of the four couplings a cycle still cannot satisfy is pinned to a
# located, specific diagnostic.

# Multi-file rejection: write files into <dir>, compile <main>, require <pattern>
# in stderr and no `:0:` — the same location guarantee run_reject gives the
# single-fixture rejections.
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

# --- Stage 15 W9 item 1: the compilation unit's ROOT file joins the import
# identity lists ------------------------------------------------------------
# Nothing imports the entry point, so it used to be on neither `g-prescan-sigs`
# nor `g-importing` — and the auto-prepended prelude reaches back into
# `lib/node.nuc` / `lib/arena.nuc`, so compiling one of those as the entry file
# paid for the omission twice: a second `prescan-defn-signatures` over the file
# (a duplicate-overload error against its OWN definitions), and, past that, a
# second emission of every `define` in it.
#
# The two units below pin the shape with hand-written files, so the guard is
# tested independently of whatever the prelude happens to import. Both roots
# carry an OVERLOADED name — that is what makes the prescan half observable, and
# it is exactly how `lib/arena.nuc` failed. Both fail on the committed boot
# compiler with `duplicate definition of 'dup-fn' … already defined at
# <same file>:<same line>`.

# Assert a program compiles, links, runs with the expected status, AND that its
# module defines every symbol exactly once. The exit status alone would not
# catch a double emission — LLVM would, but only at the link step, and the
# duplicate-signature error fires first and hides it.
w9_run_single_emission() {  # <name> <dir> <main.nuc> <expected-status>
  local name="$1" d="$2" mainsrc="$3" want="$4" dup ll
  w1_run "$name" "$d" "$mainsrc" "$want"
  ll="$d/$name.ll"
  if ! ./build/nucleusc -I "$d" --emit-llvm "$mainsrc" >"$ll" 2>/dev/null; then
    echo "FAIL  $name-single-emission (compile error)"
    return 0
  fi
  # `|| true` on each pipeline: `set -euo pipefail` is in force, and a grep that
  # matches nothing exits 1, which would kill the unit mid-way and lose its
  # second PASS line silently (the harness only flags a result file that is
  # entirely empty).
  dup="$(grep -oE '^define [^@]*@[-A-Za-z0-9_.$]+' "$ll" | sed 's/.*@//' | sort | uniq -d || true)"
  dup="$dup$(grep -oE '^@[-A-Za-z0-9_.$]+ = (global|constant)' "$ll" | sed 's/ =.*//' | sort | uniq -d || true)"
  if [ -z "$dup" ]; then
    echo "PASS  $name-single-emission"
  else
    echo "FAIL  $name-single-emission (emitted twice: $(printf '%s' "$dup" | tr '\n' ' '))"
  fi
}

# The re-entry lands while the root has emitted none of its own forms, so
# `do-import` HOISTS the root: it is emitted there, and the depth-1 loop stops
# because its own path is now on `g-imported`. This is the shape the auto-prelude
# creates for `lib/macros.nuc` / `lib/arena.nuc`, where a plain cycle skip is not
# merely suboptimal — the skipped file holds the macros the rest of the chain is
# about to use. `(exclude-prelude)` is how a hand-written test reaches the same
# window; with the prelude prepended, form 0 is the prelude import.
run_w9_root_hoist() {
  local d
  d="$(mktemp -d)"
  printf '(import-use w9h-main)\n(defn lib-fn ():i32 (return (dup-fn 2 3)))\n' > "$d/w9h-lib.nuc"
  printf '(exclude-prelude)\n(import-use w9h-lib)\n(defn dup-fn (a:i32):i32 (return a))\n(defn dup-fn (a:i32 b:i32):i32 (return (_+ a b)))\n(defn main ():i32 (return (lib-fn)))\n' > "$d/w9h-main.nuc"
  w9_run_single_emission w9-root-hoist "$d" "$d/w9h-main.nuc" 5
  rm -rf "$d"
}

# The same cycle, with one of the root's own definitions emitted BEFORE the
# back-import. Hoisting there would emit that definition a second time, so the
# window is shut and the re-entry takes W1d's ordinary cycle skip instead — which
# must still leave exactly one copy of everything. This is the half that would
# regress if the hoist were widened without the guard.
run_w9_root_cycle_skip() {
  local d
  d="$(mktemp -d)"
  printf '(import-use w9c-main)\n(defn lib-fn ():i32 (return (dup-fn 2 4)))\n' > "$d/w9c-lib.nuc"
  printf '(exclude-prelude)\n(defn dup-fn (a:i32):i32 (return a))\n(defn dup-fn (a:i32 b:i32):i32 (return (_+ a b)))\n(import-use w9c-lib)\n(defn main ():i32 (return (lib-fn)))\n' > "$d/w9c-main.nuc"
  w9_run_single_emission w9-root-cycle-skip "$d" "$d/w9c-main.nuc" 6
  rm -rf "$d"
}

# The real target: `make lib-objs` / `make lib-headers` / `make lib-cheaders`.
# Every file in lib/ must compile ON ITS OWN in all three emit modes — that is
# what makes lib/ a library directory rather than a pile of compiler fragments
# (which is why the reader moved to src/). Four of these files are inside the
# prelude's own import closure (prelude → macros, node → arena), so they are the
# ones the root-reentry bug hit; the rest guard the `--emit-nuch` half, which
# skipped the prelude entirely and so could not resolve `Node`, `StrView`,
# `String`, `(Maybe T)` or the `!T` sugar's `(Result T E)` in an exported
# signature.
run_w9_lib_standalone() {
  local f d bad body ll dup
  d="$(mktemp -d)"

  bad=0; body=""
  for f in lib/*.nuc; do
    ll="$d/$(basename "$f" .nuc).ll"
    if ! ./build/nucleusc --emit-llvm "$f" >"$ll" 2>"$d/err"; then
      bad=1; body="${body}    ${f}"$'\n'"$(sed 's/^/      /' "$d/err")"$'\n'
      continue
    fi
    dup="$(grep -oE '^define [^@]*@[-A-Za-z0-9_.$]+' "$ll" | sed 's/.*@//' | sort | uniq -d || true)"
    if [ -n "$dup" ]; then
      bad=1
      body="${body}    ${f} emitted twice: $(printf '%s' "$dup" | tr '\n' ' ')"$'\n'
    fi
  done
  if [ "$bad" -eq 0 ]; then echo "PASS  w9-lib-emit-llvm"
  else echo "FAIL  w9-lib-emit-llvm"; printf '%s' "$body"; fi

  bad=0; body=""
  for f in lib/*.nuc; do
    if ! ./build/nucleusc --emit-nuch "$f" >/dev/null 2>"$d/err"; then
      bad=1; body="${body}    ${f}"$'\n'"$(sed 's/^/      /' "$d/err")"$'\n'
    fi
  done
  if [ "$bad" -eq 0 ]; then echo "PASS  w9-lib-emit-nuch"
  else echo "FAIL  w9-lib-emit-nuch"; printf '%s' "$body"; fi

  bad=0; body=""
  for f in lib/*.nuc; do
    if ! ./build/nucleusc --emit-cheader "$f" >/dev/null 2>"$d/err"; then
      bad=1; body="${body}    ${f}"$'\n'"$(sed 's/^/      /' "$d/err")"$'\n'
    fi
  done
  if [ "$bad" -eq 0 ]; then echo "PASS  w9-lib-emit-cheader"
  else echo "FAIL  w9-lib-emit-cheader"; printf '%s' "$body"; fi

  # W9 item 2's known limit, gated for lib/ rather than merely documented: no
  # library file may carry a run-time initializer for a global it does not own,
  # because `make lib-so` links all 34 objects and each would run it again on the
  # one shared global. True today (zero constructors across the whole of lib/);
  # this is what makes adding one a test failure instead of a silent double init.
  bad=0; body=""
  for f in lib/*.nuc; do
    if ! ./build/nucleusc -c -o "$d/gate.o" "$f" >/dev/null 2>"$d/err"; then
      continue   # standalone compilation is the loops above's assertion, not this one
    fi
    if qgrep "run-time initializer" "$d/err"; then
      bad=1; body="${body}    ${f}"$'\n'"$(sed 's/^/      /' "$d/err")"$'\n'
    fi
  done
  if [ "$bad" -eq 0 ]; then echo "PASS  w9-lib-no-shared-runtime-init"
  else echo "FAIL  w9-lib-no-shared-runtime-init"; printf '%s' "$body"; fi

  rm -rf "$d"
}

# W9 item 2: two separately compiled Nucleus objects must LINK. A `.nuc` import
# is inlined, so each object carries the whole prelude closure and the two used
# to collide on `arena-init`, `g-arena`, `intern-symbol`, … — `make lib-so` could
# not be built at all. Definitions the unit only carries a COPY of are now
# `weak_odr`; the linker keeps one.
#
# "It links" is the weaker half and cannot be the whole test: a linker that kept
# two private copies of `g-arena` would also link, and every object would then
# have its own arena and its own intern table. So the counter is bumped from BOTH
# objects and read back through the third — 1 + 2 = 3 is reachable only if the
# two objects share one `w9-count`, which is the property that actually matters.
run_w9_multi_object() {
  local d
  d="$(mktemp -d)"; mkdir -p "$d/share" "$d/side" "$d/inc" "$d/main"
  cat > "$d/share/w9share.nuc" <<'EOF'
(defvar w9-count:i32 0)
(defn w9-bump ():void (set! w9-count (+ w9-count 1)))
(defn w9-get ():i32 (return w9-count))
EOF
  cat > "$d/side/w9side.nuc" <<'EOF'
(import w9share)
(defn w9-side-bump ():void (w9-bump) (w9-bump))
EOF
  # The directory split is load-bearing. `w9side.nuc` is on NO search path main
  # uses, so `w9side` can only resolve to the header in $d/inc and the call
  # genuinely crosses the object boundary (asserted by nm below); `w9share.nuc`
  # is on one, so both objects inline it — that is the duplication under test.
  # Putting the two in one directory instead makes `resolve-import` take the
  # source for both (it tries `.nuc` in every directory before any `.nuch`) and
  # the unit quietly stops testing a cross-object call.
  cat > "$d/main/w9main.nuc" <<'EOF'
(import w9share)
(import w9side)
(defn main ():i32
  (w9-bump)
  (w9-side-bump)
  (return (w9-get)))
EOF
  if ! ./build/nucleusc --emit-nuch -I "$d/share" "$d/side/w9side.nuc" > "$d/inc/w9side.nuch" 2>"$d/err" \
     || ! ./build/nucleusc -c -o "$d/side.o" -I "$d/share" "$d/side/w9side.nuc" 2>>"$d/err" \
     || ! ./build/nucleusc -c -o "$d/main.o" -I "$d/inc" -I "$d/share" "$d/main/w9main.nuc" 2>>"$d/err"; then
    echo "FAIL  w9-multi-object-link (compile failed)"; sed 's/^/    /' "$d/err"; rm -rf "$d"; return 0
  fi
  if ! clang "$d/main.o" "$d/side.o" -o "$d/prog" 2>"$d/err"; then
    echo "FAIL  w9-multi-object-link (link failed — the item 2 defect)"
    sed 's/^/    /' "$d/err" | head -8; rm -rf "$d"; return 0
  fi
  set +e; "$d/prog"; local got=$?; set -e
  if [ "$got" = 3 ]; then
    echo "PASS  w9-multi-object-link"
  else
    echo "FAIL  w9-multi-object-link (want 3, got $got — the two objects do not share w9-count)"
  fi

  # Two properties this unit would be hollow without: the imported file really is
  # duplicated in both objects (else there was no collision to fix), and the
  # `w9-side-bump` call really is undefined in main.o (else nothing crosses the
  # object boundary and the shared counter proves only that one object works).
  # Asserted on `w9-bump`, this fixture's OWN inlined import, not on the prelude's
  # `arena-init`: since the Stage 16 split the prelude emits no runtime at all
  # (compile-time-imports.md §4b), and a duplication test must name something the
  # unit under test actually duplicates.
  if [ "$(nm "$d/main.o" "$d/side.o" 2>/dev/null | grep -cE ' [WV] w9-bump$')" = 2 ] \
     && nm "$d/main.o" 2>/dev/null | qgrep -E '^ +U w9-side-bump$'; then
    echo "PASS  w9-multi-object-weak-prelude"
  else
    echo "FAIL  w9-multi-object-weak-prelude (want a weak w9-bump in both, and an undefined w9-side-bump in main.o)"
    nm "$d/main.o" "$d/side.o" 2>/dev/null | grep -E 'w9-bump|w9-side-bump' | sed 's/^/    /'
  fi

  # Ownership is per definition, not per unit: the root's own forms stay
  # external (they are what a library EXPORTS), imported ones are copies, and
  # `internal` still wins for a private definer. One `--emit-llvm` decides all
  # three, so a rule that answered any of them wrongly fails here.
  cat > "$d/main/w9own.nuc" <<'EOF'
(import w9share)
(defn- w9-secret ():i32 (return 9))
(defn w9-own ():i32 (return (+ (w9-get) (w9-secret))))
(defn main ():i32 (return (w9-own)))
EOF
  ./build/nucleusc --emit-llvm -I "$d/share" "$d/main/w9own.nuc" > "$d/own.ll" 2>/dev/null || true
  if qgrep -E '^define i32 @w9-own\(' "$d/own.ll" \
     && qgrep -E '^define weak_odr i32 @w9-get\(' "$d/own.ll" \
     && qgrep -E '^@w9-count = weak_odr global ' "$d/own.ll" \
     && qgrep -E '^define internal i32 @w9own_p[0-9]+__w9-secret\(' "$d/own.ll"; then
    echo "PASS  w9-linkage-ownership"
  else
    echo "FAIL  w9-linkage-ownership (root/imported/private must be external/weak_odr/internal)"
    grep -E '^(define|@w9-count)' "$d/own.ll" | grep -E 'w9-' | sed 's/^/    /'
  fi
  rm -rf "$d"
}

# W9 item 2's known limit, made loud instead of latent. Since imported globals
# are `weak_odr`, N objects that each inline the declaring file share ONE global
# but each still carry a constructor for it, so its run-time initializer runs
# once per object (measured below: 2). The compiler cannot see the other half —
# whether another object also inlines that file — so it warns on the half it can
# prove, and only under `-c`, the one flag that says "relocatable object".
#
# All four arms matter, and three of them are the ones that keep it from being
# noise: the owning object is silent, a whole-program build is silent AND runs
# the initializer exactly once, and `--emit-llvm` is silent because it is equally
# how a whole program is inspected.
run_w9_shared_init_warning() {
  local d out got
  d="$(mktemp -d)"; mkdir -p "$d/share" "$d/side" "$d/inc" "$d/main"
  cat > "$d/share/dshare.nuc" <<'EOF'
(defvar d-calls:i32 0)
(defn d-next ():i32 (set! d-calls (+ d-calls 1)) (return d-calls))
(defvar d-runs:i32 (d-next))
(defn d-calls-get ():i32 (return d-calls))
EOF
  cat > "$d/side/dside.nuc" <<'EOF'
(import dshare)
(defn d-side ():i32 (return (d-calls-get)))
EOF
  cat > "$d/main/dmain.nuc" <<'EOF'
(import dshare)
(import dside)
(defn main ():i32 (return (d-calls-get)))
EOF
  printf '(import dshare)\n(defn main ():i32 (return (d-calls-get)))\n' > "$d/main/dwhole.nuc"
  # dmain.nuc imports dside through the header, so it must exist before the
  # first compile below — not only before the link at the end.
  if ! ./build/nucleusc --emit-nuch -I "$d/share" "$d/side/dside.nuc" > "$d/inc/dside.nuch" 2>"$d/err"; then
    echo "FAIL  w9-shared-init-warns-under-c (--emit-nuch failed)"; sed 's/^/    /' "$d/err"; rm -rf "$d"; return 0
  fi

  out="$(./build/nucleusc -c -o "$d/main.o" -I "$d/inc" -I "$d/share" "$d/main/dmain.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$out" | qgrep -F "dshare.nuc:3: warning: defvar: 'd-runs' has a run-time initializer"; then
    echo "PASS  w9-shared-init-warns-under-c"
  else
    echo "FAIL  w9-shared-init-warns-under-c"; printf '%s\n' "$out" | sed 's/^/    /'
  fi

  out="$(./build/nucleusc -c -o "$d/own.o" -I "$d/share" "$d/share/dshare.nuc" 2>&1 >/dev/null || true)"
  if [ -z "$out" ]; then
    echo "PASS  w9-shared-init-silent-for-owner"
  else
    echo "FAIL  w9-shared-init-silent-for-owner (the object that OWNS the global must be silent)"
    printf '%s\n' "$out" | sed 's/^/    /'
  fi

  out="$(./build/nucleusc --emit-llvm -I "$d/share" "$d/main/dwhole.nuc" 2>&1 >/dev/null || true)"
  if [ -z "$out" ]; then
    echo "PASS  w9-shared-init-silent-under-emit-llvm"
  else
    echo "FAIL  w9-shared-init-silent-under-emit-llvm (says nothing about the eventual link)"
    printf '%s\n' "$out" | sed 's/^/    /'
  fi

  # A whole-program build is silent *and* correct — the initializer runs once.
  # Asserted by value, so a future change that suppressed the constructor to
  # silence the warning would fail here rather than pass quietly.
  out="$(./build/nucleusc -o "$d/whole" -I "$d/share" "$d/main/dwhole.nuc" 2>&1 >/dev/null || true)"
  set +e; "$d/whole"; got=$?; set -e
  if [ -z "$out" ] && [ "$got" = 1 ]; then
    echo "PASS  w9-shared-init-whole-program-runs-once"
  else
    echo "FAIL  w9-shared-init-whole-program-runs-once (want silence and 1, got '$out' / $got)"
  fi

  # And the thing the warning is about, by value: two objects, one shared global,
  # initializer observed running twice. This is the measurement behind the
  # "known limit" in docs/compiler.md — if a future change ever makes it 1, this
  # fails and the doc is what needs updating.
  if ./build/nucleusc -c -o "$d/side.o" -I "$d/share" "$d/side/dside.nuc" 2>/dev/null \
     && clang "$d/main.o" "$d/side.o" -o "$d/dprog" 2>/dev/null; then
    set +e; "$d/dprog"; got=$?; set -e
    if [ "$got" = 2 ]; then
      echo "PASS  w9-shared-init-runs-once-per-object"
    else
      echo "FAIL  w9-shared-init-runs-once-per-object (want 2, got $got)"
    fi
  else
    echo "FAIL  w9-shared-init-runs-once-per-object (build failed)"
  fi
  rm -rf "$d"
}

# W9 item 3: `--emit-cheader` exports a public `defvar` as `extern T name;`. The
# dispatch had no `defvar` arm at all, so a C consumer could reach a library's
# functions and none of its state — while docs/toplevel.md already promised
# "visible to C consumers (`extern T name;`)" and `--emit-nuch` already did the
# Nucleus half.
#
# The load-bearing part is the NAME. A global's link symbol keeps its hyphens
# (`@ch-count`), which is not a C identifier; sanitizing it to `ch_count` yields a
# header that parses and then fails to link, so a name needing sanitization
# carries an `asm("…")` label and one that does not stays plain, portable C.
# Asserted by actually compiling and running a C consumer against the object —
# `grep`ping the header could not tell a correct label from a broken one.
run_w9_cheader_globals() {
  local d out
  d="$(mktemp -d)"
  cat > "$d/clib.nuc" <<'EOF'
(defvar counter:i32 7)
(defvar :const limit:i32 99)
(defvar tick-count:i64 41)
(defvar- hidden:i32 5)
(defstruct CRec (a i32))
(defvar rec-val:CRec)
(defvar m-skip:(Maybe i32) (none))
(defvar arr-skip:(array i32 4))
(defn bump ():i32 (set! counter (+ counter 1)) (return counter))
EOF
  if ! ./build/nucleusc --emit-cheader "$d/clib.nuc" > "$d/clib.h" 2>"$d/err"; then
    echo "FAIL  w9-cheader-globals (--emit-cheader failed)"; sed 's/^/    /' "$d/err"; rm -rf "$d"; return 0
  fi

  if qgrep -xF 'extern int32_t counter;' "$d/clib.h" \
     && qgrep -xF 'extern const int32_t limit;' "$d/clib.h" \
     && qgrep -xF 'extern int64_t tick_count asm("tick-count");' "$d/clib.h" \
     && qgrep -xF 'extern struct CRec rec_val asm("rec-val");' "$d/clib.h" \
     && ! qgrep 'hidden' "$d/clib.h"; then
    echo "PASS  w9-cheader-global-lines"
  else
    echo "FAIL  w9-cheader-global-lines"; grep -nE 'extern|hidden' "$d/clib.h" | sed 's/^/    /'
  fi

  # A declaration the C compiler trusts and gets wrong is worse than an omission:
  # `type-node-to-c` answers `void*` for any cell head it does not know, which
  # would declare a pointer-sized object over a `(Maybe i32)` or an array.
  # `m-skip` names the more specific reason since W9 item 26 gave the pass the
  # union-template registry: `(Maybe i32)` is recognized as a template instance
  # rather than merely unspellable. Either way it is an omission with a comment.
  if qgrep -F '/* m-skip: uses a defunion-template instance type; not exported */' "$d/clib.h" \
     && qgrep -F '/* arr-skip: type has no C spelling here; not exported */' "$d/clib.h"; then
    echo "PASS  w9-cheader-global-skips-unspellable"
  else
    echo "FAIL  w9-cheader-global-skips-unspellable"; grep -n 'skip' "$d/clib.h" | sed 's/^/    /'
  fi

  # The whole point, end to end: a C program that #includes the header reads the
  # globals BY VALUE, calls in to mutate one, and sees the new value — so the
  # asm-labelled declaration and the plain one both reach the real symbol, and
  # `rec_val` proves the by-value struct spelling works the moment `.a` is
  # touched. That spelling was the typedef name until W9 item 25 tagged the
  # struct; `struct CRec` was an incomplete tag then and is the one spelling now.
  cat > "$d/main.c" <<'EOF'
#include <stdio.h>
#include "clib.h"
int main(void) {
    int b = bump();
    printf("%d %d %lld %d %d\n", counter, limit, (long long)tick_count, b, rec_val.a);
    return 0;
}
EOF
  if ./build/nucleusc -c -o "$d/clib.o" "$d/clib.nuc" 2>"$d/err" \
     && clang -Wall -Werror -I "$d" "$d/main.c" "$d/clib.o" -o "$d/cmain" 2>>"$d/err"; then
    out="$("$d/cmain")"
    if [ "$out" = "8 99 41 8 0" ]; then
      echo "PASS  w9-cheader-c-consumer-reads-globals"
    else
      echo "FAIL  w9-cheader-c-consumer-reads-globals (want '8 99 41 8 0', got '$out')"
    fi
  else
    echo "FAIL  w9-cheader-c-consumer-reads-globals (build failed)"; sed 's/^/    /' "$d/err" | head -8
  fi

  # A private global must not be reachable from C at all — asserted by a consumer
  # that names it FAILING to compile, not merely by its absence from the header.
  printf '#include "clib.h"\nint main(void){ return hidden; }\n' > "$d/priv.c"
  if clang -c -o /dev/null -I "$d" "$d/priv.c" 2>/dev/null; then
    echo "FAIL  w9-cheader-private-global-not-exported (a defvar- reached C)"
  else
    echo "PASS  w9-cheader-private-global-not-exported"
  fi

  # usize/ssize map to size_t/ptrdiff_t. Before W9 item 3 they fell through the
  # "assume struct" arm and emitted `struct usize`, which does not exist —
  # 14 of the committed lib/*.h carried it, and a `usize` GLOBAL is what turned
  # a latent defect into a broken `extern` line.
  printf '(defvar kc:usize 3)\n(defn take (n:usize):ssize (return (as ssize n)))\n' > "$d/sz.nuc"
  ./build/nucleusc --emit-cheader "$d/sz.nuc" > "$d/sz.h" 2>/dev/null || true
  if qgrep -xF 'extern size_t kc;' "$d/sz.h" \
     && qgrep -xF 'ptrdiff_t take(size_t n);' "$d/sz.h" \
     && ! qgrep 'struct usize' "$d/sz.h"; then
    echo "PASS  w9-cheader-usize-maps-to-size-t"
  else
    echo "FAIL  w9-cheader-usize-maps-to-size-t"; grep -nE 'kc|take' "$d/sz.h" | sed 's/^/    /'
  fi
  rm -rf "$d"
}

# W9 item 4: no hyphen may reach a generated C header. A Nucleus name is legal
# with `-` in it, C's is not, and `sanitize-for-c` reached the struct/union TYPE
# name only — so every field name, `defunion` arm, enum tag, `#define`, parameter
# and prototype came out as invalid C. Measured before the fix: 13 of the 34
# committed lib/*.h parsed with `clang -fsyntax-only`; after, 27.
#
# The split is the design, and it is item 3's rule applied to the rest of the
# surface. A name the LINKER resolves (a `defn`, a `defvar`) needs both a C
# identifier and the real symbol, which one token cannot be, so it carries an
# `asm("…")` label; a name the linker never sees (fields, arms, tags, `#define`s,
# parameters) is just sanitized. Verified by compiling and RUNNING a C consumer —
# grep cannot tell a correct asm label from one naming a symbol that does not
# exist, which is exactly the residue this item leaves for overloads.
run_w9_cheader_identifiers() {
  local d out
  d="$(mktemp -d)"
  cat > "$d/hlib.nuc" <<'EOF'
(defconst BUF-LEN 4)
(defenum My-Col my-red my-green)
(defstruct My-Rec a-field:i32 xs:(array i32 BUF-LEN) (data (union as-int:i64 as-flt:f64)))
(defunion My-Uni (uni-a x-val:i32) (uni-b p-one:i32 p-two:i32))
(defvar my-count:i64 41)
(defn my-bump (n-arg:i32):i32 (return (+ n-arg 1)))
(defn my-rec-sum (r:ptr:My-Rec):i32 (return (+ (r 'a-field) 100)))
(defn plain (n:i32):i32 (return n))
EOF
  if ! ./build/nucleusc --emit-cheader "$d/hlib.nuc" > "$d/hlib.h" 2>"$d/err"; then
    echo "FAIL  w9-cheader-identifiers (--emit-cheader failed)"; sed 's/^/    /' "$d/err"; rm -rf "$d"; return 0
  fi

  # The whole claim, in one assertion: outside the provenance comment and the
  # asm labels (which MUST keep the real hyphenated symbol), no hyphen survives.
  if [ -z "$(grep -v '^/\* Generated from' "$d/hlib.h" | sed 's/asm("[^"]*")//g' | grep -n '[-]')" ]; then
    echo "PASS  w9-cheader-no-stray-hyphen"
  else
    echo "FAIL  w9-cheader-no-stray-hyphen"
    grep -v '^/\* Generated from' "$d/hlib.h" | sed 's/asm("[^"]*")//g' | grep -n '[-]' | sed 's/^/    /'
  fi

  # A label appears only where it is load-bearing, so a C-legal library still gets
  # a portable header: `plain` has no label, `my-bump` does.
  if qgrep -xF 'int32_t my_bump(int32_t n_arg) asm("my-bump");' "$d/hlib.h" \
     && qgrep -xF 'int32_t plain(int32_t n);' "$d/hlib.h" \
     && qgrep -xF '#define BUF_LEN 4' "$d/hlib.h" \
     && qgrep -F 'int32_t xs[BUF_LEN];' "$d/hlib.h" \
     && qgrep -F 'My_Uni_uni_b = 1' "$d/hlib.h" \
     && qgrep -F 'My_Col_my_green = 1' "$d/hlib.h"; then
    echo "PASS  w9-cheader-label-only-where-needed"
  else
    echo "FAIL  w9-cheader-label-only-where-needed"
    grep -nE 'my_bump|plain|BUF_LEN|uni_b|my_green' "$d/hlib.h" | sed 's/^/    /'
  fi

  # End to end. Every sanitized kind is exercised through a real link: the asm
  # label on a call and on a global read, a struct field, an array extent that
  # must agree with the #define, an inline-union member, a defunion arm field and
  # its tag constant, and an enum member.
  cat > "$d/main.c" <<'EOF'
#include <stdio.h>
#include "hlib.h"
int main(void) {
    My_Rec r; r.a_field = 5; r.xs[BUF_LEN - 1] = 9; r.data.as_int = 7;
    My_Uni u; u.tag = My_Uni_uni_b; u.payload.uni_b.p_two = 3;
    printf("%d %d %lld %d %d %d %lld\n",
           my_bump(1), my_rec_sum(&r), (long long)my_count,
           (int)My_Col_my_green, u.payload.uni_b.p_two, r.xs[BUF_LEN - 1],
           (long long)r.data.as_int);
    return 0;
}
EOF
  if ./build/nucleusc -c -o "$d/hlib.o" "$d/hlib.nuc" 2>"$d/err" \
     && clang -I "$d" "$d/main.c" "$d/hlib.o" -o "$d/hmain" 2>>"$d/err"; then
    out="$("$d/hmain")"
    if [ "$out" = "2 105 41 1 3 9 7" ]; then
      echo "PASS  w9-cheader-c-consumer-hyphenated-names"
    else
      echo "FAIL  w9-cheader-c-consumer-hyphenated-names (want '2 105 41 1 3 9 7', got '$out')"
    fi
  else
    echo "FAIL  w9-cheader-c-consumer-hyphenated-names (build failed)"
    sed 's/^/    /' "$d/err" | head -8
  fi

  # The label must name what the object actually defines — the reason a sanitized
  # name alone is not enough. `nm` is the independent witness that the C-side
  # identifier and the ELF symbol really are different strings.
  if [ -f "$d/hlib.o" ] && nm "$d/hlib.o" | qgrep -E ' T my-bump$' \
     && nm "$d/hlib.o" | qgrep -E ' D my-count$' \
     && ! nm "$d/hlib.o" | qgrep -E ' (T|D) my_bump$'; then
    echo "PASS  w9-cheader-symbols-keep-hyphens"
  else
    echo "FAIL  w9-cheader-symbols-keep-hyphens"
    [ -f "$d/hlib.o" ] && nm "$d/hlib.o" | grep -E 'my.bump|my.count' | sed 's/^/    /'
  fi
  rm -rf "$d"
}

# W9 item 37: a generated C header that NAMES a type another unit defines must
# `#include` that unit's header. `type-name-to-c` spells every reference to a
# user type `struct NAME`, and a tag C never completes is not a usable
# declaration: a by-value FIELD does not compile at all ("field has incomplete
# type" — this is what made the committed `lib/string-split.h` unusable), and a
# by-value PARAMETER parses and then cannot be called, which is worse for being
# silent. A forward declaration would not do; the definition has to arrive.
#
# The include set is the set of references the header actually EMITS, not the
# import list: a type used only inside a function body, or only by a form the
# emitter skips, is not a dependency of the header. Both directions are asserted
# below, because an over-eager rule would have named a header for every import.
run_w9_cheader_imported_types() {
  local d out
  d="$(mktemp -d)"
  cat > "$d/w37base.nuc" <<'EOF'
(defstruct Pt (x i32) (y i32))
(defn pt-make (a:i32 b:i32):Pt
  (let ((p (ref Pt)) (alloca Pt))
    (set! (p 'x) a)
    (set! (p 'y) b)
    (return p)))
EOF
  # Names Pt by value in an exported struct field AND in an exported return type.
  cat > "$d/w37use.nuc" <<'EOF'
(import-use w37base)
(defstruct Seg (a Pt) (b Pt))
(defn seg-make (n:i32):Seg
  (let ((s (ref Seg)) (alloca Seg))
    (set! (s 'a) (pt-make n 1))
    (set! (s 'b) (pt-make n 2))
    (return s)))
EOF
  # Imports the same library and uses Pt only INSIDE a body: nothing it exports
  # mentions the type, so its header depends on nothing.
  cat > "$d/w37quiet.nuc" <<'EOF'
(import-use w37base)
(defn plain (n:i32):i32
  (let ((p (ref Pt)) (alloca Pt))
    (set! (p 'x) n)
    (return (p 'x))))
EOF
  ./build/nucleusc --emit-cheader "$d/w37base.nuc"  > "$d/w37base.h"  2>"$d/err" || true
  ./build/nucleusc --emit-cheader "$d/w37use.nuc"   > "$d/w37use.h"   2>>"$d/err" || true
  ./build/nucleusc --emit-cheader "$d/w37quiet.nuc" > "$d/w37quiet.h" 2>>"$d/err" || true

  # The defining unit is a sibling, so the include is its basename alone — the
  # spelling a quoted include resolves against the including file's own
  # directory, which is where the build writes it (`lib/%.h: lib/%.nuc`).
  if qgrep -xF '#include "w37base.h"' "$d/w37use.h" \
     && ! qgrep -F 'w37base.h' "$d/w37quiet.h"; then
    echo "PASS  w9-cheader-imported-type-included"
  else
    echo "FAIL  w9-cheader-imported-type-included"
    grep -n 'include' "$d/w37use.h" "$d/w37quiet.h" | sed 's/^/    /'
  fi

  # The include is load-bearing, not decorative: the SAME consumer against a
  # header with that one line removed reproduces the original defect verbatim.
  cat > "$d/main.c" <<'EOF'
#include <stdio.h>
#include "w37use.h"
int main(void) {
    Seg s = seg_make(5);
    struct Pt p = s.a;          /* by-value copy of an imported struct */
    printf("%d %d %d\n", p.x, p.y, s.b.y);
    return 0;
}
EOF
  grep -v '#include "w37base.h"' "$d/w37use.h" > "$d/stripped.h"
  sed 's/w37use\.h/stripped.h/' "$d/main.c" > "$d/mainstrip.c"
  out="$(clang -fsyntax-only -I "$d" "$d/mainstrip.c" 2>&1 || true)"
  if printf '%s' "$out" | qgrep -F "field has incomplete type 'struct Pt'"; then
    echo "PASS  w9-cheader-include-is-load-bearing"
  else
    echo "FAIL  w9-cheader-include-is-load-bearing (stripping the include did not break it)"
    printf '%s' "$out" | head -4 | sed 's/^/    /'
  fi

  # End to end, which is the only thing that can tell a correct include from a
  # plausible one: compile both units, link, and read the imported struct by
  # value through the generated header.
  if ./build/nucleusc -c -o "$d/w37base.o" "$d/w37base.nuc" 2>>"$d/err" \
     && ./build/nucleusc -c -o "$d/w37use.o" "$d/w37use.nuc" 2>>"$d/err" \
     && clang -I "$d" "$d/main.c" "$d/w37use.o" "$d/w37base.o" -o "$d/cmain" 2>>"$d/err"; then
    out="$("$d/cmain")"
    if [ "$out" = "5 1 2" ]; then
      echo "PASS  w9-cheader-imported-type-c-consumer"
    else
      echo "FAIL  w9-cheader-imported-type-c-consumer (want '5 1 2', got '$out')"
    fi
  else
    echo "FAIL  w9-cheader-imported-type-c-consumer (build failed)"
    sed 's/^/    /' "$d/err" | head -8
  fi

  # The reported artifact itself: a committed header that names an imported
  # user struct BY VALUE, which only compiles if the generated include chain
  # made that struct complete. Stage 17 A3 removed the `SplitIter.cur` field
  # this used to read, so it now uses lib/string.h's by-value return and
  # by-value parameters. Uses the COMMITTED copies, so this also fails if they
  # are regenerated wrong.
  cat > "$d/libmain.c" <<'EOF'
#include "lib/string.h"
int main(void) {
    String s = string_new();
    struct StrView v = string_as_view(&s);   /* imported struct, by value */
    (void)eq_String_String(s, s);            /* and by-value parameters */
    (void)v;
    return 0;
}
EOF
  if clang -fsyntax-only -I. "$d/libmain.c" 2>"$d/liberr"; then
    echo "PASS  w9-cheader-committed-header-usable"
  else
    echo "FAIL  w9-cheader-committed-header-usable"
    sed 's/^/    /' "$d/liberr" | head -6
  fi
  rm -rf "$d"
}

# W9 item 44. A niche-encoded `!T` / `?T` over a NON-pointer payload was declared
# `struct _BANGui8` — a tag no header defines and none can, because the value is
# not an aggregate (`define i64 @strview-byte-at(ptr, i64)`). The declaration is
# wrong twice and the second way is the dangerous one: a C author who completes
# the tag by hand gets a program that compiles, links, runs and reads the wrong
# value (measured: 0 where Nucleus reads 65). So it is omitted with a comment
# saying why, the ruling W9 item 3 already wrote down for `defvar`.
#
# The POINTER niches must survive: `!ptr:T` really is a `T*`, so over-skipping
# would drop working declarations. That half is asserted by linking and RUNNING a
# C consumer against them, not by reading the header.
run_w9_cheader_niche_types() {
  local d out
  d="$(mktemp -d)"
  cat > "$d/w44niche.nuc" <<'EOF'
(import-use prelude)
(import-use error)
(deferror w44-range "index out of range")
(defstruct W44Pt (x i32) (y i32))
(defvar g-w44-flag:!ui8)
(defn w44-byte (i:i32):!ui8
  (when (< i 0) (return (err w44-range)))
  (return (ok (unsafe/cast ui8 i))))
(defn w44-takes (b:!ui8):i32 0)
(defn w44-find (p:ptr:W44Pt i:i32):!ptr:W44Pt
  (when (!= i 0) (return (err w44-range)))
  (return (ok (as ref:W44Pt p))))
(defn w44-show (r:!ptr:W44Pt):i32
  (match r ((ok q) (return (q 'x))) ((err e) (return -1))))
EOF
  ./build/nucleusc --emit-cheader "$d/w44niche.nuc" > "$d/w44niche.h" 2>"$d/err" || true

  # No `struct _BANG…`/`struct _QMARK…` tag survives anywhere in the header —
  # return position, PARAMETER position (w44-takes) and `defvar` alike, since a
  # niche is no more constructible by a C caller than it is decodable.
  if ! qgrep -E 'struct _(BANG|QMARK)' "$d/w44niche.h" \
     && qgrep -F '/* w44-byte: uses an error-union or option type; not exported */' "$d/w44niche.h" \
     && qgrep -F '/* w44-takes: uses an error-union or option type; not exported */' "$d/w44niche.h" \
     && qgrep -F '/* g-w44-flag: uses an error-union or option type; not exported */' "$d/w44niche.h"; then
    echo "PASS  w9-cheader-niche-scalar-not-declared"
  else
    echo "FAIL  w9-cheader-niche-scalar-not-declared"
    sed 's/^/    /' "$d/w44niche.h" | tail -8
  fi

  # The other side of the ruling: a pointer niche is ABI-identical to a C `T*`
  # (design/stage10/unions.md §6 rule 3), so it stays declared and stays callable.
  # Compiled, linked and RUN — the only check that can tell a kept declaration
  # from a plausible one.
  cat > "$d/main.c" <<'EOF'
#include <stdio.h>
#include "w44niche.h"
int main(void) {
    struct W44Pt pt = {7, 9};
    struct W44Pt* q = (struct W44Pt*)w44_find(&pt, 0);
    printf("%d %d %d\n", q->x, q->y, w44_show(q));
    return 0;
}
EOF
  if ./build/nucleusc -c -o "$d/w44niche.o" "$d/w44niche.nuc" 2>>"$d/err" \
     && clang -I "$d" "$d/main.c" "$d/w44niche.o" -o "$d/cmain" 2>>"$d/err"; then
    out="$("$d/cmain")"
    if [ "$out" = "7 9 7" ]; then
      echo "PASS  w9-cheader-niche-pointer-still-callable"
    else
      echo "FAIL  w9-cheader-niche-pointer-still-callable (want '7 9 7', got '$out')"
    fi
  else
    echo "FAIL  w9-cheader-niche-pointer-still-callable (build failed)"
    sed 's/^/    /' "$d/err" | head -8
  fi

  # W9 item 37 interaction: a type named ONLY by a refused declaration is not a
  # dependency of the header, so no `#include` is emitted for the unit defining
  # it. The emitter refuses the whole declaration on any one signature position,
  # so the include pre-pass has to ask that question of the whole form.
  cat > "$d/w44base.nuc" <<'EOF'
(defstruct W44Only (x i32))
EOF
  cat > "$d/w44only.nuc" <<'EOF'
(import-use prelude)
(import-use error)
(import-use w44base)
(deferror w44-only-bad "bad")
(defn w44-probe (p:ptr:W44Only):!ui8
  (when (< (p 'x) 0) (return (err w44-only-bad)))
  (return (ok (unsafe/cast ui8 1))))
EOF
  ./build/nucleusc --emit-cheader "$d/w44only.nuc" > "$d/w44only.h" 2>>"$d/err" || true
  if ! qgrep -F 'w44base.h' "$d/w44only.h" \
     && ! qgrep -F 'struct W44Only' "$d/w44only.h"; then
    echo "PASS  w9-cheader-niche-refused-decl-adds-no-include"
  else
    echo "FAIL  w9-cheader-niche-refused-decl-adds-no-include"
    sed 's/^/    /' "$d/w44only.h" | head -10
  fi

  # The reported artefact: 14 declarations across 5 committed headers carried the
  # undefined tag. Uses the COMMITTED copies, so this also fails if they are
  # regenerated wrong. `string-from-cstr-unchecked` returns a real `struct String`
  # and must remain — it is the escape route a C caller is meant to take.
  if ! grep -lE 'struct _(BANG|QMARK)[A-Za-z]' lib/*.h > "$d/tags" 2>/dev/null \
     && qgrep -F 'struct String string_from_cstr_unchecked' lib/string.h; then
    echo "PASS  w9-cheader-committed-headers-no-niche-tag"
  else
    echo "FAIL  w9-cheader-committed-headers-no-niche-tag"
    sed 's/^/    /' "$d/tags" | head -6
  fi
  rm -rf "$d"
}

# W9 item 39. LLVM's unquoted identifier has TWO rules — a body character class
# and a first-position rule — and the compiler applied only the first, only to
# global symbols. Both halves of that reached LLVM raw and died at IR-parse time
# on a message naming a line of generated IR and nothing in the user's source:
#
#   define i32 @add_QMARK(i32 %ok?.arg, i32 %n!.arg)
#
# — the function name mangled, the parameter three tokens away from it not. So
# this asserts the two halves separately: every position a name can occupy with a
# leading DIGIT (which no path escaped), and `?`/`!` in the positions inside a
# function body (which the global path escaped and the local one did not). Each is
# compiled, LINKED and RUN, because "the module parses" is not the claim — the
# claim is that a `goto` still reaches its label and a match binder still reads
# the field it was bound to after both were renamed.
run_w9_ir_name_positions() {
  local d out
  d="$(mktemp -d)"
  # Type name, union arm, global, constant, function, parameter, `let` binding,
  # match binder and `label`/`goto` target — every one digit-leading.
  cat > "$d/w39dlib.nuc" <<'EOF'
(defstruct 2Pair a:i32 b:i32)
(defunion 2Shape (2circle r:i32) (2square s:i32))
(defvar 2count:i32 100)
(defconst 2LIM 9)
(defn 2fast (2n:i32):i32
  (let (2acc:i32 0)
    (set! 2acc (* 2n 2))
    2acc))
(defn 2pick (sh:2Shape):i32
  (match sh ((2circle 2v) 2v) ((2square 2w) (* 2w 10))))
(defn 2loop ():i32
  (let (i:i32 0)
    (label 2top)
    (set! i (+ i 1))
    (when (< i 3) (goto 2top))
    i))
EOF
  cat > "$d/w39dig.nuc" <<'EOF'
(import-use "stdio.h")
(import-use w39dlib)
(defn main ():i32
  (let (p:ptr:2Pair (2Pair 3 4))
    (printf "%d %d %d %d %d %d\n"
      (2fast 20) 2count 2LIM (get p 'a) (2pick (make 2Shape 2circle 7)) (2loop)))
  0)
EOF
  if ./build/nucleusc -I "$d" "$d/w39dig.nuc" -o "$d/dig" 2>"$d/err"; then
    out="$("$d/dig")"
    if [ "$out" = "40 100 9 3 7 3" ]; then
      echo "PASS  w9-ir-name-digit-every-position"
    else
      echo "FAIL  w9-ir-name-digit-every-position (want '40 100 9 3 7 3', got '$out')"
    fi
  else
    echo "FAIL  w9-ir-name-digit-every-position (build failed)"
    sed 's/^/    /' "$d/err" | head -8
  fi

  # The other half, and the one that was NOT latent: `?` and `!` are legal in a
  # Nucleus symbol and `(defn even? …)` has worked since SM-1 mangled it to
  # `@even_QMARK` — but the same character in a parameter, a `let` binding, a
  # match binder or a label went to LLVM verbatim.
  cat > "$d/w39chr.nuc" <<'EOF'
(import-use "stdio.h")
(defunion Sh! (circ! r:i32) (sq? s:i32))
(defn add? (ok?:i32 n!:i32):i32
  (let (acc!:i32 0)
    (set! acc! (+ ok? n!))
    acc!))
(defn peek! (sh:Sh!):i32
  (match sh ((circ! v?) v?) ((sq? w!) (* w! 10))))
(defn spin? ():i32
  (let (i!:i32 0)
    (label top!)
    (set! i! (+ i! 1))
    (when (< i! 3) (goto top!))
    i!))
(defn main ():i32
  (printf "%d %d %d\n" (add? 1 20) (peek! (make Sh! circ! 7)) (spin?))
  0)
EOF
  if ./build/nucleusc "$d/w39chr.nuc" -o "$d/chr" 2>>"$d/err"; then
    out="$("$d/chr")"
    if [ "$out" = "21 7 3" ]; then
      echo "PASS  w9-ir-name-body-chars-in-locals"
    else
      echo "FAIL  w9-ir-name-body-chars-in-locals (want '21 7 3', got '$out')"
    fi
  else
    echo "FAIL  w9-ir-name-body-chars-in-locals (build failed)"
    sed 's/^/    /' "$d/err" | head -8
  fi

  # C has the identical first-position rule, so `sanitize-for-c` escapes with the
  # same `_`. That is what makes the C spelling and the link symbol AGREE — hence
  # no `asm()` label — and only linking and running a C consumer can show it: a
  # header whose declarations merely parse would still fail at the linker. The
  # comment line carries this directory's path, so it is dropped before the scan.
  ./build/nucleusc --emit-cheader "$d/w39dlib.nuc" > "$d/w39dlib.h" 2>>"$d/err" || true
  cat > "$d/dmain.c" <<'EOF'
#include <stdio.h>
#include "w39dlib.h"
int main(void) {
    struct _2Pair p = { 3, 4 };
    struct _2Shape c;
    c.tag = _2Shape_2circle;
    c.payload._2circle = 7;
    printf("%d %d %d %d %d %d\n",
           _2fast(20), _2count, _2LIM, p.a, _2pick(c), _2loop());
    return 0;
}
EOF
  if ! grep -v '^/\*' "$d/w39dlib.h" | qgrep -E '\b[0-9]+[A-Za-z_]' \
     && ./build/nucleusc -c -o "$d/w39dlib.o" "$d/w39dlib.nuc" 2>>"$d/err" \
     && clang -I "$d" "$d/dmain.c" "$d/w39dlib.o" -o "$d/cmain" 2>>"$d/err"; then
    out="$("$d/cmain")"
    if [ "$out" = "40 100 9 3 7 3" ]; then
      echo "PASS  w9-ir-name-digit-header-c-callable"
    else
      echo "FAIL  w9-ir-name-digit-header-c-callable (want '40 100 9 3 7 3', got '$out')"
    fi
  else
    echo "FAIL  w9-ir-name-digit-header-c-callable"
    sed 's/^/    /' "$d/w39dlib.h" | tail -8
    sed 's/^/    /' "$d/err" | head -6
  fi
  rm -rf "$d"
}

# W9 item 43 — A PREFIXED IMPORT MUST NOT CHANGE WHAT A BARE CALL MEANS.
#
# A generic is the one registry R2 keys BARE, and B4 filtered only the QUALIFIED
# path through `Method.src-ns`, deferring the bare half (§9.6). So a file that
# defined `w43-helper (x:i64)` and called `(w43-helper 3)` emitted a call to a
# LIBRARY's `w43-helper (x:i32)`, reached through a prefix the call never spells:
# nothing was unresolved, the wrong candidate simply scored better on the literal.
#
# Three cells, and the middle one is the point — the same program, the same line,
# two answers depending only on whether an unrelated import form is present.
run_w9_bare_ref_prefix() {
  local d ir
  d="$(mktemp -d)"
  cat > "$d/w43lib.nuc" <<'EOF'
(ns w43n)
(defn w43-helper (x:i32):i32 (return (+ x 100)))
EOF
  # 1. Alone: the file's own definition, as the baseline.
  cat > "$d/w43alone.nuc" <<'EOF'
(defn w43-helper (x:i64):i32 (return (unsafe/cast i32 (+ x 7))))
(defn main ():i32 (return (w43-helper 3)))
EOF
  # 2. Plus a PREFIXED import of a library that also exports the name. The
  #    unchanged line must still mean the file's own function.
  cat > "$d/w43pfx.nuc" <<'EOF'
(import-prefixed w43lib wx)
(defn w43-helper (x:i64):i32 (return (unsafe/cast i32 (+ x 7))))
(defn main ():i32 (return (w43-helper 3)))
EOF
  # 3. …and the prefix still reaches the library's, so nothing was hidden —
  #    only the unqualified space was left alone.
  cat > "$d/w43qual.nuc" <<'EOF'
(import-prefixed w43lib wx)
(defn w43-helper (x:i64):i32 (return (unsafe/cast i32 (+ x 7))))
(defn main ():i32 (return (wx/w43-helper 3)))
EOF
  # 4. `import-use` FLATTENS, which is R2 §8.2's escape hatch: there the two
  #    overloads genuinely merge and the i32 one wins the literal. Pinned so the
  #    filter cannot quietly grow into a ban on flattened overloading.
  cat > "$d/w43flat.nuc" <<'EOF'
(import-use w43lib)
(defn w43-helper (x:i64):i32 (return (unsafe/cast i32 (+ x 7))))
(defn main ():i32 (return (w43-helper 3)))
EOF
  w1_run w9-bare-ref-alone      "$d" "$d/w43alone.nuc" 10
  w1_run w9-bare-ref-prefix-inert "$d" "$d/w43pfx.nuc"  10
  w1_run w9-bare-ref-qualified  "$d" "$d/w43qual.nuc" 103
  w1_run w9-bare-ref-flattened  "$d" "$d/w43flat.nuc" 103

  # And the emitted call names the file's own symbol, not the library's — the
  # exact artefact the row reports.
  ir="$(./build/nucleusc -I "$d" --emit-llvm "$d/w43pfx.nuc" 2>/dev/null || true)"
  if printf '%s' "$ir" | qgrep -E 'call i32 @w43-helper\(i64 ' \
     && ! printf '%s' "$ir" | qgrep -E 'call .*@w43n__w43-helper\('; then
    echo "PASS  w9-bare-ref-prefix-symbol"
  else
    echo "FAIL  w9-bare-ref-prefix-symbol (bare call reached the prefixed library)"
    printf '%s' "$ir" | grep -E 'w43-helper' | sed 's/^/    /' | head -6
  fi
  rm -rf "$d"
}
spawn run_w9_bare_ref_prefix

# W9 item 43, the half the filter uncovered — A TEMPLATE BODY IS THE LIBRARY'S
# TEXT, so its names resolve in the LIBRARY's environment.
#
# `MonoJob` was the one deferred-work record that did not restore the environment
# it was created in (`DynAnnot` and `InitJob` both do, for the stated reason that
# the drain runs later), so a stamped body was emitted in the environment of
# whichever file happened to instantiate it. On the pre-item-43 compiler this
# program failed with `unknown: w43t-solo — not defined anywhere in this
# compilation unit`, blaming the CALLER's file at the LIBRARY's line — while the
# very same program with a second `w43t-solo` overload compiled, because an
# overloaded name reached the merged bare-keyed generic and a solitary one went
# through the import environment. Correctness by overload count.
#
# The library's namespace is reached from the template body three ways at once —
# a solitary function, a global, and a protocol method — none of which the
# caller's file can name.
run_w9_template_env() {
  local d err got
  d="$(mktemp -d)"
  cat > "$d/w43tlib.nuc" <<'EOF'
(ns w43t)
(defprotocol W43Num (w43t-zero (self:Self):i32))
(defn w43t-zero (x:i32):i32 (return x))
(extend i32 W43Num)
(defn w43t-solo (x:i32):i32 (return (* x 10)))
(defvar w43t-gv:i32 5)
(defn w43t-twice (x:T :where (W43Num T)):i32
  (return (+ (w43t-solo (w43t-zero x)) w43t-gv)))
EOF
  # The caller imports it under a PREFIX, so none of `w43t-solo`, `w43t-gv` or
  # `w43t-zero` is nameable here — only inside the library that wrote them.
  cat > "$d/w43tuse.nuc" <<'EOF'
(import-prefixed w43tlib pg)
(defn main ():i32 (return (pg/w43t-twice 3)))
EOF
  w1_run w9-template-body-library-env "$d" "$d/w43tuse.nuc" 35

  # And a genuine error in a template body is reported against the LIBRARY's
  # file, to go with the library's line — the `job context` note still says which
  # call site asked. Before this the pair was `<caller>.nuc:<library line>`, a
  # location that in this program does not exist (the caller has two lines), and
  # the reported error was the resolution failure the wrong environment caused
  # rather than the type error actually in the body.
  cat > "$d/w43blib.nuc" <<'EOF'
(ns w43b)
(defprotocol W43B (w43b-zero (self:Self):i32))
(defn w43b-zero (x:i32):i32 (return x))
(extend i32 W43B)
(defn w43b-take (x:i32):i32 (return x))
(defn w43b-tw (x:T :where (W43B T)):i32
  (return (+ (w43b-zero x) (w43b-take "not an int"))))
EOF
  cat > "$d/w43buse.nuc" <<'EOF'
(import-prefixed w43blib pg)
(defn main ():i32 (return (pg/w43b-tw 3)))
EOF
  err="$(./build/nucleusc -I "$d" --emit-llvm "$d/w43buse.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep -E 'w43blib\.nuc:7: error:' \
     && printf '%s' "$err" | qgrep -F "does not match parameter type i32" \
     && printf '%s' "$err" | qgrep -F "while instantiating"; then
    echo "PASS  w9-template-error-blames-library"
  else
    echo "FAIL  w9-template-error-blames-library"
    printf '%s\n' "$err" | sed 's/^/    got: /' | head -3
  fi

  # The realistic library shape: the template is declared in a generated `.nuch`
  # and instantiated from a SEPARATELY COMPILED object. `src-imports` is captured
  # wherever `src-ns`/`src-file` are, and a header replay reaches
  # `register-generic-template` with the header file's own environment already
  # filled, so the stamped body resolves `tz-solo`/`tz-zero` in the library's
  # namespace and the two objects link. Pre-item-43 this failed to compile at all.
  cat > "$d/w43ntl.nuc" <<'EOF'
(ns w43z)
(defprotocol W43Z (w43z-zero (self:Self):i32))
(defn w43z-zero (x:i32):i32 (return x))
(extend i32 W43Z)
(defn w43z-solo (x:i32):i32 (return (* x 10)))
(defn w43z-tw (x:T :where (W43Z T)):i32 (return (w43z-solo (w43z-zero x))))
EOF
  cat > "$d/w43ntu.nuc" <<'EOF'
(import w43ntl w43p)
(defn main ():i32 (return (w43p/w43z-tw 3)))
EOF
  ./build/nucleusc --emit-nuch -I "$d" "$d/w43ntl.nuc" > "$d/w43ntl.nuch" 2>/dev/null || true
  # Compile the consumer against the HEADER only (the `.nuc` is moved aside, so
  # `resolve-import` cannot prefer the source), then link the library object.
  mv "$d/w43ntl.nuc" "$d/w43ntl.nuc.src"
  if ./build/nucleusc -c -I "$d" -o "$d/w43ntu.o" "$d/w43ntu.nuc" 2>"$d/nerr" \
     && mv "$d/w43ntl.nuc.src" "$d/w43ntl.nuc" \
     && ./build/nucleusc -c -I "$d" -o "$d/w43ntl.o" "$d/w43ntl.nuc" 2>>"$d/nerr" \
     && clang "$d/w43ntu.o" "$d/w43ntl.o" -o "$d/w43nt" 2>>"$d/nerr"; then
    set +e; "$d/w43nt"; got=$?; set -e
    if [ "$got" = "30" ]; then
      echo "PASS  w9-template-nuch-separate-compilation"
    else
      echo "FAIL  w9-template-nuch-separate-compilation (expected exit 30, got $got)"
    fi
  else
    echo "FAIL  w9-template-nuch-separate-compilation (compile/link error)"
    sed 's/^/    /' "$d/nerr" | head -4
  fi
  rm -rf "$d"
}
spawn run_w9_template_env

# W9 item 35 — TWO NAMESPACES MAY EACH DEFINE ONE NAME WITH ONE SIGNATURE.
#
# R4's eager rule refused the pair with "a public name must be unique across the
# whole compilation unit" — true of one flat namespace, and the thing namespaces
# exist to stop being true. What it was really protecting is the BARE reference,
# so the refusal moves to where the ambiguity is: item 43's filter decides which
# candidates a file can see at all, and `generic-resolve` reports the pair that
# survives. R2 §8.2's own first recommendation, which R4 overrode.
#
# Four cells, one per import environment, plus the rule R4 keeps.
run_w9_two_ns_one_name() {
  local d ir err
  d="$(mktemp -d)"
  cat > "$d/w35qa.nuc" <<'EOF'
(ns w35qa)
(defn w35-desc (x:i32):i32 (return (+ x 1)))
EOF
  cat > "$d/w35qb.nuc" <<'EOF'
(ns w35qb)
(defn w35-desc (x:i32):i32 (return (+ x 2)))
EOF
  # 1. Both prefixed, both calls qualified: two definitions, two symbols, and
  #    each qualified spelling reaches its own.
  cat > "$d/w35both.nuc" <<'EOF'
(import-prefixed w35qa a)
(import-prefixed w35qb b)
(defn main ():i32 (return (+ (a/w35-desc 10) (b/w35-desc 20))))
EOF
  w1_run w9-two-ns-one-name "$d" "$d/w35both.nuc" 33

  ir="$(./build/nucleusc -I "$d" --emit-llvm "$d/w35both.nuc" 2>/dev/null || true)"
  if printf '%s' "$ir" | qgrep -E '^define .*@w35qa__w35-desc\(' \
     && printf '%s' "$ir" | qgrep -E '^define .*@w35qb__w35-desc\('; then
    echo "PASS  w9-two-ns-distinct-symbols"
  else
    echo "FAIL  w9-two-ns-distinct-symbols (the pair did not emit two defines)"
    printf '%s' "$ir" | grep -E 'w35-desc' | sed 's/^/    /' | head -6
  fi

  # 2. Flatten exactly one: the bare call is not ambiguous at all, because only
  #    one candidate is in this file's unqualified space.
  cat > "$d/w35one.nuc" <<'EOF'
(import-use w35qa)
(import-prefixed w35qb b)
(defn main ():i32 (return (w35-desc 10)))
EOF
  w1_run w9-two-ns-bare-picks-flattened "$d" "$d/w35one.nuc" 11

  # 3. Flatten BOTH: now the bare call really does name two functions, and that
  #    is the use R4 was refusing the definitions to prevent. Located, and both
  #    candidates named with a spelling that resolves.
  cat > "$d/w35amb.nuc" <<'EOF'
(import-use w35qa)
(import-use w35qb)
(defn main ():i32 (return (w35-desc 10)))
EOF
  err="$(./build/nucleusc -I "$d" --emit-llvm "$d/w35amb.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep -F "ambiguous call to 'w35-desc'" \
     && printf '%s' "$err" | qgrep -F "'w35qa/w35-desc'" \
     && printf '%s' "$err" | qgrep -F "'w35qb/w35-desc'" \
     && printf '%s' "$err" | qgrep -E 'w35amb\.nuc:3: error:'; then
    echo "PASS  w9-two-ns-ambiguous-use"
  else
    echo "FAIL  w9-two-ns-ambiguous-use"
    printf '%s\n' "$err" | sed 's/^/    got: /' | head -4
  fi

  # 4. Neither flattened: the name is not in the unqualified space, and the
  #    message says where it IS and what to write instead of guessing.
  cat > "$d/w35none.nuc" <<'EOF'
(import-prefixed w35qa a)
(import-prefixed w35qb b)
(defn main ():i32 (return (w35-desc 10)))
EOF
  err="$(./build/nucleusc -I "$d" --emit-llvm "$d/w35none.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep -F "defined in namespaces 'w35qa' and 'w35qb'" \
     && printf '%s' "$err" | qgrep -F "write 'a/w35-desc' or 'b/w35-desc' here"; then
    echo "PASS  w9-two-ns-unqualified-unreachable"
  else
    echo "FAIL  w9-two-ns-unqualified-unreachable"
    printf '%s\n' "$err" | sed 's/^/    got: /' | head -4
  fi

  # 5. And R4's rule survives where its reason does: ONE namespace still may not
  #    define one signature twice, because that pair really would emit a symbol
  #    twice. The test is the emitted PREFIX, not the namespace name, so two
  #    files sharing a namespace are still a duplicate.
  cat > "$d/w35dupa.nuc" <<'EOF'
(ns w35dup)
(defn w35-dup (x:i32):i32 (return x))
EOF
  cat > "$d/w35dupb.nuc" <<'EOF'
(ns w35dup)
(defn w35-dup (x:i32):i32 (return (+ x 1)))
EOF
  cat > "$d/w35dupm.nuc" <<'EOF'
(import-use w35dupa)
(import-use w35dupb)
(defn main ():i32 (return 0))
EOF
  err="$(./build/nucleusc -I "$d" --emit-llvm "$d/w35dupm.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep -F "duplicate definition of 'w35-dup'"; then
    echo "PASS  w9-one-ns-still-refuses-duplicate"
  else
    echo "FAIL  w9-one-ns-still-refuses-duplicate"
    printf '%s\n' "$err" | sed 's/^/    got: /' | head -4
  fi
  rm -rf "$d"
}
spawn run_w9_two_ns_one_name

# W9 item 38 — A HEADER MODE REFUSES THE DECLARATIONS THE REAL PIPELINE REFUSES.
#
# `--emit-cheader` / `--emit-nuch` run the compiler's PRESCAN layer and never its
# EMISSION layer, and every prescan deliberately defers its diagnosis to emission
# (`defn-params-to-types`: "the located diagnostic is emit-defn's job";
# `prescan-file-imports`: "a missing library is diagnosed by do-import"). With no
# emitter downstream nothing ever asked, so three fixtures reached a raw
# `(node-at form N)` dereference and the compiler died with SIGSEGV and no output
# — the worst diagnosis of a syntax error available — while an unresolvable
# import exited 0 and printed a header that silently omitted its every name.
#
# Each case asserts the header mode's stderr is IDENTICAL to `--emit-llvm`'s,
# rather than matching a string quoted here. The fix routes all three modes
# through one chokepoint, and comparing them is what pins that; a copied message
# would drift and a quoted assertion would not notice.
w9_header_agrees() {
  local name file want got_c got_n out_c out_n sc sn
  name="$1"; file="$2"; shift 2
  want="$(./build/nucleusc "$@" --emit-llvm "$file" 2>&1 >/dev/null || true)"
  set +e
  out_c="$(./build/nucleusc "$@" --emit-cheader "$file" 2>/dev/null)"; sc=$?
  out_n="$(./build/nucleusc "$@" --emit-nuch "$file" 2>/dev/null)"; sn=$?
  set -e
  got_c="$(./build/nucleusc "$@" --emit-cheader "$file" 2>&1 >/dev/null || true)"
  got_n="$(./build/nucleusc "$@" --emit-nuch "$file" 2>&1 >/dev/null || true)"
  # Exit 1, not 139: a segfault also produces no stdout, so the status is what
  # separates "refused" from "crashed".
  if [ -n "$want" ] && [ "$got_c" = "$want" ] && [ "$got_n" = "$want" ] \
     && [ -z "$out_c" ] && [ -z "$out_n" ] && [ "$sc" = "1" ] && [ "$sn" = "1" ]; then
    echo "PASS  $name"
  else
    echo "FAIL  $name (cheader exit=$sc nuch exit=$sn)"
    printf '    llvm   : %s\n' "$want"
    printf '    cheader: %s\n' "$got_c"
    printf '    nuch   : %s\n' "$got_n"
  fi
}

run_w9_header_validation() {
  local d hdr nuch
  # The three fixtures that segfaulted. Each is a shape the prescan accepts and
  # the header emitter then dereferenced: a missing return operand, an empty-list
  # parameter, and an empty-list member of an inline union.
  w9_header_agrees w9-cheader-missing-ret       tests/fixtures/s1-missing-ret.nuc
  w9_header_agrees w9-cheader-empty-param       tests/fixtures/w5f-empty-param.nuc
  w9_header_agrees w9-cheader-empty-union-member tests/fixtures/w5f-empty-union-member.nuc

  d="$(mktemp -d)"
  # The residue: an import that names nothing. Not a crash but a wrong ANSWER,
  # which is the worse half — the header described a unit it could not see, and
  # `--emit-nuch`'s copy would have been committed and linked against.
  cat > "$d/w38imp.nuc" <<'EOF'
(import-use w38nosuchlib)
(defn w38-f (x:i32):i32 (return x))
EOF
  w9_header_agrees w9-header-unresolvable-import "$d/w38imp.nuc" -I "$d"

  # The three fixtures were only the shapes the CORPUS happened to contain.
  # Probing every head the two header emitters dispatch on found ten crashing
  # shapes, not three — a truncated form of each definer, and an inline aggregate
  # reached through a pointer, an array or a `defvar` rather than a struct field.
  # Each is the same defect, so each gets the same assertion.
  w38_case() {
    printf '%s\n' "$2" > "$d/w38p.nuc"
    w9_header_agrees "$1" "$d/w38p.nuc" -I "$d"
  }
  w38_case w9-header-truncated-defn      '(defn)'
  w38_case w9-header-truncated-defstruct '(defstruct)'
  w38_case w9-header-truncated-defunion  '(defunion U)'
  w38_case w9-header-truncated-defvar    '(defvar)'
  w38_case w9-header-truncated-defconst  '(defconst K)'
  w38_case w9-header-truncated-defenum   '(defenum)'
  w38_case w9-header-truncated-defmacro  '(defmacro)'
  w38_case w9-header-truncated-defcast   '(defcast)'
  w38_case w9-header-truncated-extend    '(extend)'
  w38_case w9-header-union-under-ptr     '(defstruct A (f (ptr (union a:i32 ()))))'
  w38_case w9-header-union-under-array   '(defstruct A (f (array (union a:i32 ()) 4)))'
  w38_case w9-header-union-in-defvar     '(defvar v:(union a:i32 ()) 0)'
  # Twelve of the thirteen above crash or silently succeed on a compiler built at
  # 447e25f. This one already refused correctly there — it is a CONTROL that the
  # return position stays covered by the walk, not a case this change fixed.
  w38_case w9-header-union-in-ret        '(defn f (x:i32):(union a:i32 ()) (return 0))'

  # NEGATIVE CONTROL, and the point of the whole ruling: the walk must refuse
  # only what --emit-llvm refuses. A valid unit — including a bounded-generic
  # template, whose body --emit-llvm checks only when a call site stamps it, so
  # refusing one here would make the header mode STRICTER than the compiler —
  # still emits both headers.
  cat > "$d/w38ok.nuc" <<'EOF'
(defprotocol W38Z (w38z-zero (self:Self):i32))
(defn w38z-zero (x:i32):i32 (return x))
(extend i32 W38Z)
(defn w38-tw (x:T :where (W38Z T)):i32 (return (+ (w38z-zero x) 1)))
(defstruct W38Box (v (union as-int:i64 as-ptr:ptr)))
(defn w38-plain (b:ptr:W38Box):i64 (return 7))
(defn main ():i32 (return (w38-tw 41)))
EOF
  if ./build/nucleusc -I "$d" --emit-llvm "$d/w38ok.nuc" >/dev/null 2>&1; then
    echo "PASS  w9-header-validation-control-compiles"
  else
    echo "FAIL  w9-header-validation-control-compiles (the negative control must be a VALID program)"
    ./build/nucleusc -I "$d" --emit-llvm "$d/w38ok.nuc" 2>&1 >/dev/null | sed 's/^/    /' | head -3
  fi
  hdr="$(./build/nucleusc -I "$d" --emit-cheader "$d/w38ok.nuc" 2>/dev/null || true)"
  nuch="$(./build/nucleusc -I "$d" --emit-nuch "$d/w38ok.nuc" 2>/dev/null || true)"
  if printf '%s' "$hdr" | qgrep -F "w38_plain" \
     && printf '%s' "$hdr" | qgrep -F "union {" \
     && printf '%s' "$nuch" | qgrep -F "w38-tw" \
     && printf '%s' "$nuch" | qgrep -F "w38-plain"; then
    echo "PASS  w9-header-validation-passes-valid-unit"
  else
    echo "FAIL  w9-header-validation-passes-valid-unit"
    printf '%s\n' "$hdr" | sed 's/^/    h: /' | head -6
    printf '%s\n' "$nuch" | sed 's/^/    n: /' | head -6
  fi

  # And the boundary, asserted rather than assumed: a BODY error is out of scope
  # by construction — no body is read — so the header modes still succeed where
  # --emit-llvm fails. Stating it here is what stops a later reader from taking
  # the residue for a regression.
  cat > "$d/w38body.nuc" <<'EOF'
(defn w38-body (x:i64):i32 (return (as i32 x)))
EOF
  set +e
  ./build/nucleusc -I "$d" --emit-llvm "$d/w38body.nuc" >/dev/null 2>&1; local bl=$?
  ./build/nucleusc -I "$d" --emit-cheader "$d/w38body.nuc" >/dev/null 2>&1; local bc=$?
  set -e
  if [ "$bl" != "0" ] && [ "$bc" = "0" ]; then
    echo "PASS  w9-header-validation-body-error-out-of-scope"
  else
    echo "FAIL  w9-header-validation-body-error-out-of-scope (llvm=$bl cheader=$bc)"
  fi
  rm -rf "$d"
}
spawn run_w9_header_validation

# W9 item 45 — `()` IN A POSITION THAT REQUIRES A NAME.
#
# `()` reads as a NULL node (W5f: read-list returns null for a zero-element
# list), and nearly every top-level definer read `(node-at form N)` and
# dereferenced it. The item was filed for four heads measured by hand; probing
# every top-level head found the same crash in twenty-odd shapes across all three
# modes — the head's own name, an enum member, a protocol signature, an `extend`
# operand, a template head.
#
# The fix is not twenty new messages. Every one of these positions ALREADY owned
# the right diagnostic for a wrong-kind name (`ns: namespace must be a symbol`,
# `defenum: value must be symbol`, `import: name must be a symbol or string
# path`) — the kind test that would have fired it crashed first. `node-kind`
# (lib/node.nuc) answers NODE-NIL for a null node, so each site's own test fires.
#
# Asserted through `w9_header_agrees`, so each case pins BOTH halves at once:
# exit 1 rather than 139 in every mode, and stderr identical across the three.
run_w9_empty_name_position() {
  local d
  d="$(mktemp -d)"
  w45_case() {
    printf '%s\n' "$2" > "$d/w45p.nuc"
    w9_header_agrees "$1" "$d/w45p.nuc" -I "$d"
  }
  # The four heads item 45 was filed for: each died SIGSEGV under plain
  # --emit-llvm, which is what separated it from item 38.
  w45_case w45-empty-name-defstruct    '(defstruct ())'
  w45_case w45-empty-name-defunion     '(defunion () (A i32))'
  w45_case w45-empty-name-defenum      '(defenum ())'
  w45_case w45-empty-name-defprotocol  '(defprotocol ())'
  # The rest of the class, found by probing rather than by report. A bare
  # `(defn)`/`(defvar)` is caught by an arity guard, so the name position is only
  # reached once the form is long enough — which is why these carry a body.
  w45_case w45-empty-name-defn         '(defn () (x:i32):i32 (return x))'
  w45_case w45-empty-name-defvar       '(defvar () 0)'
  w45_case w45-empty-name-defconst     '(defconst () 7)'
  w45_case w45-empty-name-defmacro     '(defmacro () (x) x)'
  w45_case w45-empty-name-defcast      '(defcast () i32 f)'
  w45_case w45-empty-name-extern       '(extern ())'
  w45_case w45-empty-name-declare      '(declare ())'
  w45_case w45-empty-name-export       '(export ())'
  w45_case w45-empty-name-ns           '(ns ())'
  w45_case w45-empty-name-set-ir-prefix '(set-ir-prefix ())'
  w45_case w45-empty-name-import       '(import ())'
  w45_case w45-empty-name-import-use   '(import-use ())'
  # Not the name: an operand, a member, a signature, a template head. Same NULL,
  # same cause, and each already had the message it should give.
  w45_case w45-empty-defcast-target    '(defcast i32 () f)'
  w45_case w45-empty-extend-subject    '(extend () Eq)'
  w45_case w45-empty-extend-protocol   '(extend i32 ())'
  w45_case w45-empty-defenum-member    '(defenum E A () B)'
  w45_case w45-empty-defprotocol-sig   '(defprotocol P ())'
  w45_case w45-empty-defstruct-template '(defstruct (()) (f i32))'
  w45_case w45-empty-defprotocol-template '(defprotocol (()) (m (s:ptr):i32))'
  # CONTROLS. These two already refused correctly at 0dd0e34 — a struct field and
  # a union arm route through `extract-name-and-type` / the arm walk, both of
  # which W5f and the unions work had already made null-safe. They are here to
  # pin that this change did not move them, not as cases it fixed.
  w45_case w45-empty-defstruct-field   '(defstruct S (f i32) ())'
  w45_case w45-empty-defunion-arm      '(defunion U (A i32) ())'

  # THE BOUNDARY, asserted rather than assumed. Two heads are refused by
  # --emit-llvm and stay silent in the header modes, both for reasons item 38
  # recorded: `deferror`'s checks `report-at` and return `!i32` — a recoverable
  # contract the validation deliberately does not join — and `def-rmacro` is a
  # reader directive, not a declaration a header describes. What matters is that
  # neither CRASHES any more. `deferror` did at 0dd0e34 and is load-bearing;
  # `def-rmacro` already refused there and is a control for the head set.
  w45_llvm_refuses() {
    local out st
    printf '%s\n' "$2" > "$d/w45r.nuc"
    set +e
    out="$(./build/nucleusc -I "$d" --emit-llvm "$d/w45r.nuc" 2>&1 >/dev/null)"; st=$?
    set -e
    if [ "$st" = "1" ] && printf '%s' "$out" | qgrep -F "w45r.nuc:1: error:"; then
      echo "PASS  $1"
    else
      echo "FAIL  $1 (exit=$st)"
      printf '%s\n' "$out" | sed 's/^/    /' | head -3
    fi
  }
  w45_llvm_refuses w45-empty-name-deferror   '(deferror () "boom")'
  w45_llvm_refuses w45-empty-name-def-rmacro '(def-rmacro ())'

  # NEGATIVE CONTROL: the same heads, spelled correctly, still compile and still
  # reach both headers. `node-kind` returning NODE-NIL only for a null node is
  # what makes that true by construction, but a guard added at twenty sites is
  # exactly the kind of change that could quietly refuse a valid program.
  cat > "$d/w45ok.nuc" <<'EOF'
(ns w45ns)
(defenum W45E W45A W45B)
(defstruct W45Pt (x i32) (y i32))
(defunion W45U (w45-some v:i32) w45-none)
(defprotocol W45Z (w45z-zero (self:Self):i32))
(defn w45z-zero (x:i32):i32 (return x))
(extend i32 W45Z)
(defconst W45K 7)
(defvar w45-g:i32 0)
(defn w45-add (a:i32 b:i32):i32 (return (+ a b)))
(defn main ():i32 (return (w45-add W45K (w45z-zero 0))))
EOF
  if ./build/nucleusc -I "$d" --emit-llvm "$d/w45ok.nuc" >/dev/null 2>&1 \
     && ./build/nucleusc -I "$d" --emit-cheader "$d/w45ok.nuc" 2>/dev/null | qgrep -F "w45ns__w45_add" \
     && ./build/nucleusc -I "$d" --emit-nuch "$d/w45ok.nuc" 2>/dev/null | qgrep -F "w45-add"; then
    echo "PASS  w45-valid-unit-unaffected"
  else
    echo "FAIL  w45-valid-unit-unaffected"
    ./build/nucleusc -I "$d" --emit-llvm "$d/w45ok.nuc" 2>&1 >/dev/null | sed 's/^/    /' | head -3
  fi
  rm -rf "$d"
}
spawn run_w9_empty_name_position

# SOURCE OUT-RANKS HEADER, asserted on both sides of the ruling. `resolve-import`
# already tries `.nuc` in every directory before any `.nuch`, so an import takes
# the source — but `path-in-unit` keyed on the exact path spelling, so the
# `foo.nuch` generated beside the `foo.nuc` the unit imports counted as a
# DIFFERENT file, outside the unit. The unreachable-file scan then reported the
# library the author is already using as one "no import in this unit reaches",
# and, being an earlier tier, it displaced the diagnostic that was actually true.
# Reproduced in-tree the moment `make lib-headers` had been run (it made
# b3-type-ns-not-in-scope fail); this unit builds the same shape from scratch so
# it does not depend on which artefacts happen to be sitting in lib/.
run_w9_source_outranks_header() {
  local d ir err
  d="$(mktemp -d)"; mkdir -p "$d/l"
  cat > "$d/l/w9sh.nuc" <<'EOF'
(ns shn)
(defstruct W9Rec (n i32))
(defn w9sh-get ((r (ref W9Rec))):i32 (return (_get r 'n)))
EOF
  cat > "$d/w9shuse.nuc" <<'EOF'
(import-prefixed w9sh shp)
(defn w9-take ((r (ref W9Rec))):i32 (return (w9sh-get r)))
(defn main ():i32 (return 0))
EOF
  ./build/nucleusc --emit-nuch -I "$d/l" "$d/l/w9sh.nuc" > "$d/l/w9sh.nuch" 2>/dev/null || true
  if [ ! -s "$d/l/w9sh.nuch" ]; then
    echo "FAIL  w9-source-outranks-header (could not generate the sibling header)"; rm -rf "$d"; return 0
  fi

  # 1. The import takes the SOURCE even with the header beside it: an inlined
  #    definition, not a link-time `declare`.
  printf '(import w9sh)\n(defn main ():i32 (return 0))\n' > "$d/w9shok.nuc"
  ir="$(./build/nucleusc --emit-llvm -I "$d/l" "$d/w9shok.nuc" 2>/dev/null || true)"
  if printf '%s' "$ir" | qgrep -E '^define .*@shn__w9sh-get\(' ; then
    echo "PASS  w9-import-prefers-source"
  else
    echo "FAIL  w9-import-prefers-source (header won, or the symbol moved)"
    printf '%s' "$ir" | grep -E 'w9sh-get' | sed 's/^/    /' | head -4
  fi

  # 2. The diagnostic side of the same ruling: the sibling header must not be
  #    named as an unreachable definer, and the better tier must survive.
  err="$(./build/nucleusc --emit-llvm -I "$d/l" "$d/w9shuse.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep -F "w9sh.nuch"; then
    echo "FAIL  w9-sibling-header-not-unreachable (named the header for a library the unit imports)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | qgrep -F "defined in namespace 'shn'" \
       && printf '%s' "$err" | qgrep -F "note: write 'shp/W9Rec' here"; then
    echo "PASS  w9-sibling-header-not-unreachable"
  else
    echo "FAIL  w9-sibling-header-not-unreachable (expected the namespace tier)"
    printf '%s\n' "$err" | sed 's/^/    /'
  fi
  rm -rf "$d"
}

# Stage 15 W9 item 46: a `.nuch` header's `defunion` inside a namespace. The
# registry takes the canonical KEY and `union-ctor-form` takes the SOURCE
# spelling — the split `emit-defunion` documents and `emit-defunion-import` did
# not honour, so a header carrying `(ns …)` filed its backing struct under the
# key and its UnionDef under the bare name, where no reference looks. The same
# library's `.nuc` source has always worked, so every case here is run BOTH ways
# and the two are required to agree.
run_w9_nuch_ns_union() {
  local d ok v
  d="$(mktemp -d)"; mkdir -p "$d/l" "$d/h"
  cat > "$d/l/w9nu.nuc" <<'EOF'
(ns w9nu)
(defunion Opt (Some x:i32) None)
(defn opt-or (o:Opt d:i32):i32
  (return (match o ((Some x) x) (None d))))
EOF
  ./build/nucleusc --emit-nuch "$d/l/w9nu.nuc" > "$d/h/w9nu.nuch" 2>/dev/null || true
  if [ ! -s "$d/h/w9nu.nuch" ]; then
    echo "FAIL  w9-nuch-ns-union (could not generate the header)"; rm -rf "$d"; return 0
  fi
  ./build/nucleusc -c "$d/l/w9nu.nuc" -o "$d/w9nu.o" >/dev/null 2>&1

  # `make`, `match` and a by-value union parameter, with the import above the
  # uses and below them. Below-use is item 40's `.nuch` residue, which could not
  # be closed until this key agreed.
  cat > "$d/body.txt" <<'EOF'
(import-use "stdio.h")
(defn go ():i32
  (let (a (make w9nu/Opt Some 41)
        b (make w9nu/Opt None))
    (return (+ (w9nu/opt-or a 0) (w9nu/opt-or b 1)))))
(defn main ():i32 (printf "%d\n" (go)) (return 0))
EOF
  { echo '(import-use w9nu)'; cat "$d/body.txt"; } > "$d/above.nuc"
  { cat "$d/body.txt"; echo '(import-use w9nu)'; } > "$d/below.nuc"

  ok=1
  for v in above below; do
    ./build/nucleusc -c -I "$d/h" "$d/$v.nuc" -o "$d/$v.o" 2>"$d/$v.err" || ok=0
    clang "$d/$v.o" "$d/w9nu.o" -o "$d/$v.bin" >/dev/null 2>&1 || ok=0
    [ "$ok" = 1 ] && [ "$("$d/$v.bin")" = "42" ] || ok=0
  done
  if [ "$ok" = 1 ]; then
    echo "PASS  w9-nuch-ns-union-links-and-runs"
  else
    echo "FAIL  w9-nuch-ns-union-links-and-runs"
    for v in above below; do sed "s/^/    $v: /" "$d/$v.err" 2>/dev/null | head -2; done
  fi

  # The same source compiled against the library's `.nuc` rather than its header
  # must produce the same answer — the header is the only thing under test.
  if ./build/nucleusc -I "$d/l" "$d/above.nuc" -o "$d/src.bin" >/dev/null 2>&1 \
     && [ "$("$d/src.bin")" = "42" ]; then
    echo "PASS  w9-nuch-ns-union-agrees-with-source"
  else
    echo "FAIL  w9-nuch-ns-union-agrees-with-source"
  fi

  # The arm constructors are the mangling half: `union-ctor-form` is handed the
  # bare spelling on purpose, and the `declare` it produces must still come out
  # under the namespaced symbol the library's object actually exports. Exactly
  # one declare each — the prescan registers without emitting so this stays 1.
  local ir n
  ir="$(./build/nucleusc --emit-llvm -I "$d/h" "$d/below.nuc" 2>/dev/null || true)"
  n="$(printf '%s\n' "$ir" | grep -cE '^declare .*@w9nu__Opt-(Some|None)\(')"
  if [ "$n" = 2 ] && printf '%s\n' "$ir" | qgrep -F '@w9nu__Opt-Some'; then
    echo "PASS  w9-nuch-ns-union-ctor-symbols"
  else
    echo "FAIL  w9-nuch-ns-union-ctor-symbols (declare count $n)"
    printf '%s\n' "$ir" | grep -E '^declare .*Opt' | sed 's/^/    /' | head -4
  fi

  # A diamond: two headers each importing w9nu, both imported here. The union is
  # registered once and its arm declares emitted once — the guard that used to
  # key on "a UnionDef exists" now keys on `ctors-emitted`, and getting that
  # wrong drops the declares (link failure) or repeats them (invalid IR).
  for m in a b; do
    printf '(ns w9nu%s)\n(import-use w9nu)\n(defn tag-%s ():i32 (return (w9nu/opt-or (make w9nu/Opt Some 1) 0)))\n' "$m" "$m" > "$d/l/w9nu$m.nuc"
    ./build/nucleusc --emit-nuch -I "$d/h" "$d/l/w9nu$m.nuc" > "$d/h/w9nu$m.nuch" 2>/dev/null || true
    ./build/nucleusc -c -I "$d/h" "$d/l/w9nu$m.nuc" -o "$d/w9nu$m.o" >/dev/null 2>&1
  done
  cat > "$d/diamond.nuc" <<'EOF'
(import-use "stdio.h")
(import-use w9nua)
(import-use w9nub)
(defn main ():i32
  (printf "%d\n" (+ (w9nua/tag-a) (w9nub/tag-b)))
  (return 0))
EOF
  if ./build/nucleusc -c -I "$d/h" "$d/diamond.nuc" -o "$d/diamond.o" 2>"$d/dia.err" \
     && clang "$d/diamond.o" "$d/w9nua.o" "$d/w9nub.o" "$d/w9nu.o" -o "$d/diamond.bin" >/dev/null 2>&1 \
     && [ "$("$d/diamond.bin")" = "2" ]; then
    echo "PASS  w9-nuch-ns-union-diamond"
  else
    echo "FAIL  w9-nuch-ns-union-diamond"
    sed 's/^/    /' "$d/dia.err" 2>/dev/null | head -3
  fi

  # A header with no `(ns …)` keys bare on both sides, which is why this was
  # invisible for so long. Pin it so the fix stays a re-keying, not a rename.
  cat > "$d/l/w9nub0.nuc" <<'EOF'
(defunion W9NuBare (W9NuOne x:i32) W9NuZero)
(defn w9nu-bare-or (o:W9NuBare d:i32):i32
  (return (match o ((W9NuOne x) x) (W9NuZero d))))
EOF
  ./build/nucleusc --emit-nuch "$d/l/w9nub0.nuc" > "$d/h/w9nub0.nuch" 2>/dev/null || true
  ./build/nucleusc -c "$d/l/w9nub0.nuc" -o "$d/w9nub0.o" >/dev/null 2>&1
  cat > "$d/bare.nuc" <<'EOF'
(import-use "stdio.h")
(import-use w9nub0)
(defn main ():i32
  (printf "%d\n" (w9nu-bare-or (make W9NuBare W9NuOne 9) 0))
  (return 0))
EOF
  if ./build/nucleusc -c -I "$d/h" "$d/bare.nuc" -o "$d/bare.o" >/dev/null 2>&1 \
     && clang "$d/bare.o" "$d/w9nub0.o" -o "$d/bare.bin" >/dev/null 2>&1 \
     && [ "$("$d/bare.bin")" = "9" ]; then
    echo "PASS  w9-nuch-union-bare-unchanged"
  else
    echo "FAIL  w9-nuch-union-bare-unchanged"
  fi

  rm -rf "$d"
}

# Stage 15 W9 items 42 and 47: where a `defcast` rule is reached, and where the
# conversions stop. 47 is the defect — the registry was consulted from
# `safe-coerce-val`, which only the call-argument and `as` paths call, so a rule
# was invisible at every other typed slot even on the EXACT pair it was
# registered for. 42 is the ruling that survives the fix: implicit conversions do
# not compose, so a bare `i32` literal still does not reach an `i64` rule, and
# the compiler now says so instead of leaving the user to guess.
run_w9_defcast_reach() {
  local d out
  d="$(mktemp -d)"

  # Every typed slot, all on the rule's exact pair, linked and RUN — the
  # baseline compiles none of these past the first one.
  cat > "$d/slots.nuc" <<'EOF'
(import-use "stdio.h")
(defn i2p (x:i64):ptr (return (unsafe/cast ptr x)))
(defcast i64 ptr i2p)
(defstruct Bx p:ptr)
(defn show (p:ptr):i64 (return (unsafe/cast i64 p)))
(defn mk ():ptr (return (as i64 3)))
(defn mk2 ():ptr (as i64 4))
(defn main ():int
  (let (a:i64 (show (as i64 1))
        l:ptr (as i64 2)
        b:ptr:Bx (alloca Bx)
        arr:ptr (alloca ptr 2))
    (set! (b 'p) (as i64 5))
    (set! (aref (as ptr:ptr arr) 0) (as i64 6))
    (printf "%lld %lld %lld %lld %lld %lld\n"
      a (show l) (show (mk)) (show (mk2)) (show (b 'p))
      (show (aref (as ptr:ptr arr) 0))))
  (return 0))
EOF
  if ./build/nucleusc "$d/slots.nuc" -o "$d/slots.bin" 2>"$d/err" \
     && [ "$("$d/slots.bin")" = "1 2 3 4 5 6" ]; then
    echo "PASS  w9-defcast-every-slot"
  else
    echo "FAIL  w9-defcast-every-slot"
    sed 's/^/    /' "$d/err" | head -3
    [ -x "$d/slots.bin" ] && printf '    got: %s\n' "$("$d/slots.bin")"
  fi

  # The ruling: built-in widening does NOT chain into a user rule. A bare
  # literal is i32; the i64 rule stays out of reach, in argument position...
  cat > "$d/nocompose.nuc" <<'EOF'
(defn i2p (x:i64):ptr (return (unsafe/cast ptr x)))
(defcast i64 ptr i2p)
(defn take (p:ptr):void (return))
(defn main ():int (take 0) (return 0))
EOF
  out="$(./build/nucleusc "$d/nocompose.nuc" -o "$d/nocompose.bin" 2>&1 || true)"
  if printf '%s\n' "$out" | qgrep -F 'argument 1 has type i32'; then
    echo "PASS  w9-defcast-no-composition"
  else
    echo "FAIL  w9-defcast-no-composition"
    printf '%s\n' "$out" | sed 's/^/    /' | head -3
  fi

  # ...and the refusal now names the rule that ALMOST applies, with the spelling
  # that reaches it. Without this the ruling is indistinguishable from the rule
  # never having been registered.
  if printf '%s\n' "$out" | qgrep -F 'note: a defcast rule converts i64 to ptr' \
     && printf '%s\n' "$out" | qgrep -F '(as i64'; then
    echo "PASS  w9-defcast-note-names-rule"
  else
    echo "FAIL  w9-defcast-note-names-rule"
    printf '%s\n' "$out" | sed 's/^/    /' | head -3
  fi

  # The `as` position is the one where the bare diagnostic was actively wrong:
  # "use unsafe/cast" throws away the safety the defcast was written to buy.
  cat > "$d/asnote.nuc" <<'EOF'
(defn i2p (x:i64):ptr (return (unsafe/cast ptr x)))
(defcast i64 ptr i2p)
(defn main ():int (let (q:ptr (as ptr 0)) (return 0)))
EOF
  out="$(./build/nucleusc "$d/asnote.nuc" -o "$d/asnote.bin" 2>&1 || true)"
  if printf '%s\n' "$out" | qgrep -F 'note: a defcast rule converts i64 to ptr'; then
    echo "PASS  w9-defcast-note-on-as"
  else
    echo "FAIL  w9-defcast-note-on-as"
    printf '%s\n' "$out" | sed 's/^/    /' | head -3
  fi

  # No rule to that target => no note. Pins the note against firing on every
  # unrelated type mismatch in a file that happens to contain a defcast.
  cat > "$d/nonote.nuc" <<'EOF'
(defn i2p (x:i64):ptr (return (unsafe/cast ptr x)))
(defcast i64 ptr i2p)
(defn take (x:f64):void (return))
(defn main ():int (take (unsafe/cast ptr 0)) (return 0))
EOF
  out="$(./build/nucleusc "$d/nonote.nuc" -o "$d/nonote.bin" 2>&1 || true)"
  if printf '%s\n' "$out" | qgrep -F 'error:' \
     && ! printf '%s\n' "$out" | qgrep -F 'note: a defcast rule'; then
    echo "PASS  w9-defcast-note-only-on-near-miss"
  else
    echo "FAIL  w9-defcast-note-only-on-near-miss"
    printf '%s\n' "$out" | sed 's/^/    /' | head -3
  fi

  # Built-in coercion still wins: a rule may not be registered for a pair the
  # compiler already converts, so "which fires first" can never be observed.
  cat > "$d/shadow.nuc" <<'EOF'
(defn widen (x:i32):i64 (return (as i64 x)))
(defcast i32 i64 widen)
(defn main ():int (return 0))
EOF
  out="$(./build/nucleusc "$d/shadow.nuc" -o "$d/shadow.bin" 2>&1 || true)"
  if printf '%s\n' "$out" | qgrep -F 'handled by built-in coercion'; then
    echo "PASS  w9-defcast-builtin-wins"
  else
    echo "FAIL  w9-defcast-builtin-wins"
    printf '%s\n' "$out" | sed 's/^/    /' | head -3
  fi

  rm -rf "$d"
}

# Stage 15 W9 item 40: a struct's LAYOUT and a `defunion`'s registration resolve
# on REACHABILITY, like their names (W1a), their signatures and their value names
# (W8 G-0). Before this a field access below the import reported "no field 'x' on
# struct 'S'" for a struct that has that field, a literal reported "too many
# initializers", and a by-value parameter compiled to `define … @f(i0 %v.arg)` —
# a SILENT miscompile, which is why every case here links and RUNS rather than
# just compiling. Registration only: the `%Name = type {…}` lines still come from
# `emit-defstruct`, which check 5 pins by comparing the two import orders' IR.
run_w9_layout_reachability() {
  local d ir
  d="$(mktemp -d)"; mkdir -p "$d/l" "$d/h"
  cat > "$d/l/w9lay.nuc" <<'EOF'
(defconst W9LAY-N 3)
(defstruct W9LayBox (a i32) (b i32))
(defstruct W9LayArr (xs (array i32 W9LAY-N)) n:i32)
(defunion W9LayOpt (W9LaySome x:i32) W9LayNone)
(defmacro w9lay-mac (x) `(+ ~x 100))
EOF
  # Every use ABOVE the import: a literal, a field read, a by-value parameter
  # (the silent one), an array-field struct whose extent is a same-file
  # `defconst`, and a union built with `make` and taken apart with `match`.
  cat > "$d/below.nuc" <<'EOF'
(import-use "stdio.h")
(defn w9lay-byval ((v W9LayBox)):i32 (return (+ (_get (addr-of v) 'a) (_get (addr-of v) 'b))))
(defn main ():i32
  (let (bx (W9LayBox 3 4)
        ar:ptr:W9LayArr (alloca W9LayArr)
        u (make W9LayOpt W9LaySome 5))
    (set! (aref (ar 'xs) 2) 6)
    (set! (ar 'n) 7)
    (printf "%d %d %d %d %d\n"
      (_get bx 'a) (w9lay-byval bx) (aref (ar 'xs) 2) (_get ar 'n)
      (match u ((W9LaySome x) x) (W9LayNone 0))))
  (return 0))
(import-use w9lay)
EOF
  sed '$d' "$d/below.nuc" > "$d/above.nuc.body"
  { echo '(import-use w9lay)'; cat "$d/above.nuc.body"; } > "$d/above.nuc"

  if ./build/nucleusc -I "$d/l" "$d/below.nuc" -o "$d/below.bin" 2>"$d/err" \
     && [ "$("$d/below.bin")" = "3 7 6 7 5" ]; then
    echo "PASS  w9-layout-below-use-runs"
  else
    echo "FAIL  w9-layout-below-use-runs"
    sed 's/^/    /' "$d/err" | head -4
    [ -x "$d/below.bin" ] && printf '    got: %s\n' "$("$d/below.bin")"
  fi

  # The by-value parameter, read off the IR rather than the exit status: `i0` is
  # what an unlaid-out struct classified to, and it is the shape LLVM rejects
  # with no source location at all.
  ir="$(./build/nucleusc --emit-llvm -I "$d/l" "$d/below.nuc" 2>/dev/null || true)"
  if printf '%s\n' "$ir" | qgrep -F 'define i32 @w9lay-byval(i64 ' ; then
    echo "PASS  w9-layout-byval-classified"
  else
    echo "FAIL  w9-layout-byval-classified"
    printf '%s\n' "$ir" | grep -F '@w9lay-byval(' | sed 's/^/    /' | head -2
  fi

  # The same shape inside ONE file: `(defn f (v:S))` textually above
  # `(defstruct S …)`. Recorded as latent-and-unfixed since W1d — the layout
  # prescan closes it with the cross-file case, since neither is about imports.
  cat > "$d/fwd.nuc" <<'EOF'
(defn w9lay-fwd ((v W9LayFwd)):i32 (return (+ (_get (addr-of v) 'p) (_get (addr-of v) 'q))))
(defstruct W9LayFwd (p i32) (q i32))
(defn main ():i32 (return (w9lay-fwd (W9LayFwd 2 3))))
EOF
  if ./build/nucleusc "$d/fwd.nuc" -o "$d/fwd.bin" 2>"$d/err"; then
    set +e; "$d/fwd.bin"; got=$?; set -e
    [ "$got" = 5 ] && echo "PASS  w9-layout-same-file-forward" \
                   || echo "FAIL  w9-layout-same-file-forward (expected 5, got $got)"
  else
    echo "FAIL  w9-layout-same-file-forward (compile/link error)"
    sed 's/^/    /' "$d/err" | head -3
  fi

  # A `.nuch` header is a file in the graph like any other: its `defstruct`
  # reaches the very same `emit-defstruct`, so its layout hoists too. The
  # library's source is deliberately out of the include path (an import prefers
  # the `.nuc` when both are there — w9-import-prefers-source).
  ./build/nucleusc --emit-nuch "$d/l/w9lay.nuc" > "$d/h/w9lay.nuch" 2>/dev/null || true
  cat > "$d/hbelow.nuc" <<'EOF'
(import-use "stdio.h")
(defn main ():i32
  (let (bx (W9LayBox 8 9))
    (printf "%d\n" (+ (_get bx 'a) (_get bx 'b))))
  (return 0))
(import-use w9lay)
EOF
  if ./build/nucleusc --emit-llvm -I "$d/h" "$d/hbelow.nuc" >/dev/null 2>"$d/err"; then
    echo "PASS  w9-layout-nuch-below-use"
  else
    echo "FAIL  w9-layout-nuch-below-use"
    sed 's/^/    /' "$d/err" | head -3
  fi

  # Registration moved; EMISSION did not. Each type is DEFINED exactly once — a
  # prescan that wrote a `%Name = type` line of its own would double it, which
  # the LLVM parser rejects — and the two import orders carry the same set of
  # top-level definitions, so nothing was gained or lost by moving the import.
  # (The lines themselves are compared as a SET: their position within the type
  # section is order-dependent and inert, and the string pool renumbers.)
  ./build/nucleusc --emit-llvm -I "$d/l" "$d/above.nuc" > "$d/above.ll" 2>/dev/null || true
  ./build/nucleusc --emit-llvm -I "$d/l" "$d/below.nuc" > "$d/below.ll" 2>/dev/null || true
  if [ "$(grep -c '^%W9LayBox = type ' "$d/below.ll")" = 1 ] \
     && [ "$(grep -c '^%W9LayArr = type ' "$d/below.ll")" = 1 ] \
     && [ "$(grep -c '^%W9LayOpt = type ' "$d/below.ll")" = 1 ] \
     && [ "$(grep -E '^(%[A-Za-z0-9_.]+ = type|define|declare) ' "$d/above.ll" | sort | md5sum)" \
        = "$(grep -E '^(%[A-Za-z0-9_.]+ = type|define|declare) ' "$d/below.ll" | sort | md5sum)" ]; then
    echo "PASS  w9-layout-emission-unmoved"
  else
    echo "FAIL  w9-layout-emission-unmoved"
    grep -n '^%W9Lay' "$d/below.ll" | sed 's/^/    /' | head -6
    diff <(grep -E '^(%[A-Za-z0-9_.]+ = type|define|declare) ' "$d/above.ll" | sort) \
         <(grep -E '^(%[A-Za-z0-9_.]+ = type|define|declare) ' "$d/below.ll" | sort) \
      | sed 's/^/    /' | head -6
  fi

  # The residue, pinned so it is a decision rather than an oversight: a
  # `defmacro` is a COMPILED function, not a registration — `emit-defmacro` runs
  # codegen and materializes a JIT module — so it stays where the emitter is and
  # still needs the import above the use.
  cat > "$d/mac.nuc" <<'EOF'
(defn main ():i32 (return (w9lay-mac 1)))
(import-use w9lay)
EOF
  if ./build/nucleusc --emit-llvm -I "$d/l" "$d/mac.nuc" >/dev/null 2>"$d/err"; then
    echo "FAIL  w9-layout-macro-still-needs-import-above (it compiled)"
  elif qgrep -F "unknown: w9lay-mac" "$d/err"; then
    echo "PASS  w9-layout-macro-still-needs-import-above"
  else
    echo "FAIL  w9-layout-macro-still-needs-import-above (wrong diagnostic)"
    sed 's/^/    /' "$d/err" | head -3
  fi
  rm -rf "$d"
}

# Stage 15 W9 item 29: a `.nuch` header's functions and values resolve on
# REACHABILITY, like the `.nuc` spelling of the same library, not on whether the
# import form happens to sit above the use. Registration is hoisted into the
# whole-graph prescan (`prescan-nuch-signatures`) and emission left where
# `emit-nuch-import-forms` always wrote it, so the same program's IR does not
# move — which is what the third and fourth checks below are for. The library's
# source is deliberately OUT of the include path: with both beside each other an
# import takes the `.nuc` (w9-import-prefers-source), and nothing here would be
# exercising a header at all.
run_w9_nuch_import_order() {
  local d ir err
  d="$(mktemp -d)"; mkdir -p "$d/l" "$d/h"
  cat > "$d/l/w9no.nuc" <<'EOF'
(defconst W9NO-BASE 40)
(defenum W9NoKind w9no-red w9no-green w9no-blue)
(defvar w9no-counter:i32 7)
(defn w9no-add ((a i32) (b i32)):i32 (return (+ a b)))
(defn w9no-two ((a i32)):i32 (return (* a 2)))
(defn w9no-two ((a i64)):i64 (return (* a 2)))
EOF
  ./build/nucleusc --emit-nuch "$d/l/w9no.nuc" > "$d/h/w9no.nuch" 2>/dev/null || true
  if [ ! -s "$d/h/w9no.nuch" ]; then
    echo "FAIL  w9-nuch-import-order (could not generate the header)"; rm -rf "$d"; return 0
  fi
  # One use of every kind a header carries: a `declare`, an `extern`, a
  # `defconst`, a `defenum` member and one arm of an overload set (`defmethod`).
  cat > "$d/body.txt" <<'EOF'
(import-use "stdio.h")
(defn main ():i32
  (printf "%d %d %d %d %d\n" (w9no-add 1 2) W9NO-BASE (as i32 w9no-blue) w9no-counter (w9no-two 21))
  (return 0))
EOF
  { cat "$d/body.txt"; echo '(import-use w9no)'; } > "$d/below.nuc"
  { echo '(import-use w9no)'; cat "$d/body.txt"; } > "$d/above.nuc"

  # 1. The import BELOW every use compiles at all. This is the whole defect: on
  #    the committed boot compiler it is `not defined anywhere in this
  #    compilation unit` for five names that are in the unit.
  if ./build/nucleusc --emit-llvm -I "$d/h" "$d/below.nuc" > "$d/below.ll" 2>"$d/below.err"; then
    echo "PASS  w9-nuch-import-below-use"
  else
    echo "FAIL  w9-nuch-import-below-use"
    sed 's/^/    /' "$d/below.err" | head -4
  fi

  # 2. …and LINKS and RUNS against the library's object, which is the only proof
  #    that the `declare` / `external global` lines were still emitted, exactly
  #    once, under the symbols the library actually exports.
  ./build/nucleusc -c "$d/l/w9no.nuc" -o "$d/w9no.o" >/dev/null 2>&1
  local ok=1
  for v in above below; do
    ./build/nucleusc -c -I "$d/h" "$d/$v.nuc" -o "$d/$v.o" >/dev/null 2>&1 || ok=0
    clang "$d/$v.o" "$d/w9no.o" -o "$d/$v.bin" >/dev/null 2>&1 || ok=0
    [ "$ok" = 1 ] && [ "$("$d/$v.bin")" = "3 40 2 7 42" ] || ok=0
  done
  if [ "$ok" = 1 ]; then
    echo "PASS  w9-nuch-import-order-links-and-runs"
  else
    echo "FAIL  w9-nuch-import-order-links-and-runs"
    for v in above below; do [ -x "$d/$v.bin" ] && printf '    %s: %s\n' "$v" "$("$d/$v.bin" 2>&1)"; done
  fi

  # 3. Emission did not move: one `declare` per function, one `external global`
  #    per variable. The prescan registers without emitting precisely so that
  #    these counts stay 1 — a second copy of either is invalid IR.
  ir="$(cat "$d/below.ll" 2>/dev/null || true)"
  if [ "$(printf '%s\n' "$ir" | grep -c '^declare i32 @w9no-add(i32, i32)$')" = 1 ] \
     && [ "$(printf '%s\n' "$ir" | grep -c '^@w9no-counter = external global i32$')" = 1 ] \
     && [ "$(printf '%s\n' "$ir" | grep -c '^declare i32 @w9no_two\.i32(i32)$')" = 1 ] \
     && [ "$(printf '%s\n' "$ir" | grep -c '^declare i64 @w9no_two\.i64(i64)$')" = 1 ]; then
    echo "PASS  w9-nuch-declares-emitted-once"
  else
    echo "FAIL  w9-nuch-declares-emitted-once"
    printf '%s\n' "$ir" | grep -E '^(declare|@w9no)' | sed 's/^/    /' | head -8
  fi

  # 4. Two headers declaring ONE global. The prescan registers it for whichever
  #    header it reaches first and skips it for the second — so the emit-only
  #    pass must ask per name whether registration happened, not assume it did
  #    for the whole header. Assuming would write `@w9no-shared` twice, which
  #    LLVM rejects. Both declares must still be there.
  printf '(extern (w9no-shared i32))\n(declare w9no-a ((x i32)) :i32)\n' > "$d/h/w9noa.nuch"
  printf '(extern (w9no-shared i32))\n(declare w9no-b ((x i32)) :i32)\n' > "$d/h/w9nob.nuch"
  cat > "$d/two.nuc" <<'EOF'
(import-use "stdio.h")
(defn main ():i32
  (printf "%d %d %d\n" (w9no-a 1) (w9no-b 2) w9no-shared)
  (return 0))
(import-use w9noa)
(import-use w9nob)
EOF
  ir="$(./build/nucleusc --emit-llvm -I "$d/h" "$d/two.nuc" 2>/dev/null || true)"
  if [ "$(printf '%s\n' "$ir" | grep -c '^@w9no-shared = external global i32$')" = 1 ] \
     && [ "$(printf '%s\n' "$ir" | grep -c '^declare i32 @w9no-a(i32)$')" = 1 ] \
     && [ "$(printf '%s\n' "$ir" | grep -c '^declare i32 @w9no-b(i32)$')" = 1 ]; then
    echo "PASS  w9-nuch-shared-global-declared-once"
  else
    echo "FAIL  w9-nuch-shared-global-declared-once"
    printf '%s\n' "$ir" | grep -E '^(declare|@w9no)' | sed 's/^/    /' | head -8
  fi

  # 5. The other half of the same rule, and the case this test was written to
  #    RECORD rather than endorse: when the unit defines the name a header
  #    declares, the header entry used to be dropped whole — one `define`, no
  #    `declare`, and nothing left that reaches the library's function. Item 36
  #    reports it instead. Note the signatures here are IDENTICAL, which is why
  #    the discriminator cannot be a signature comparison: what makes these two
  #    different functions is that one is a header's and one is this unit's.
  cat > "$d/shadow.nuc" <<'EOF'
(import-use w9no)
(defn w9no-add ((a i32) (b i32)):i32 (return (- a b)))
(defn main ():i32 (printf "%d\n" (w9no-add 5 2)) (return 0))
EOF
  err="$(./build/nucleusc --emit-llvm -I "$d/h" "$d/shadow.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep "already defines 'w9no-add'"; then
    echo "PASS  w9-nuch-local-definition-reported"
  else
    echo "FAIL  w9-nuch-local-definition-reported"
    printf '%s\n' "$err" | sed 's/^/    /' | head -6
  fi
  rm -rf "$d"
}

# The headline: two files that import each other, compiled from either end.
# `w1-ca-fn 3` walks a→b→a→b and returns 2; `w1-cb-fn 3` walks b→a→b→a and
# returns 1, so the two orders cannot pass by accident with one shared answer.
# Also covers the flatten spelling (`import-use`, prefix == null), a three-file
# cycle, and a file that imports itself — all four reach the same guard.
run_w1d_cycle_accepts() {
  local d
  d="$(mktemp -d)"
  printf '(import w1-cb)\n(defn w1-ca-fn (n:i32):i32 (if (= n 0) (return 1) (return (w1-cb-fn (- n 1)))))\n' > "$d/w1-ca.nuc"
  printf '(import w1-ca)\n(defn w1-cb-fn (n:i32):i32 (if (= n 0) (return 2) (return (w1-ca-fn (- n 1)))))\n' > "$d/w1-cb.nuc"
  printf '(import w1-ca)\n(defn main ():i32 (return (w1-ca-fn 3)))\n' > "$d/w1-circ1.nuc"
  printf '(import w1-cb)\n(defn main ():i32 (return (w1-cb-fn 3)))\n' > "$d/w1-circ2.nuc"
  w1_run w1d-cycle-order1 "$d" "$d/w1-circ1.nuc" 2
  w1_run w1d-cycle-order2 "$d" "$d/w1-circ2.nuc" 1

  printf '(import-use w1-cub)\n(defn w1-cua ():i32 (return (+ (w1-cub) 1)))\n' > "$d/w1-cua.nuc"
  printf '(import-use w1-cua)\n(defn w1-cub ():i32 (return 5))\n' > "$d/w1-cub.nuc"
  printf '(import-use w1-cua)\n(defn main ():i32 (return (w1-cua)))\n' > "$d/w1-cu.nuc"
  w1_run w1d-cycle-import-use "$d" "$d/w1-cu.nuc" 6

  printf '(import w1-t3b)\n(defn w1-f3a (n:i32):i32 (if (= n 0) (return 1) (return (w1-f3b (- n 1)))))\n' > "$d/w1-t3a.nuc"
  printf '(import w1-t3c)\n(defn w1-f3b (n:i32):i32 (if (= n 0) (return 2) (return (w1-f3c (- n 1)))))\n' > "$d/w1-t3b.nuc"
  printf '(import w1-t3a)\n(defn w1-f3c (n:i32):i32 (if (= n 0) (return 3) (return (w1-f3a (- n 1)))))\n' > "$d/w1-t3c.nuc"
  printf '(import w1-t3a)\n(defn main ():i32 (return (w1-f3a 5)))\n' > "$d/w1-t3.nuc"
  w1_run w1d-cycle-three-file "$d" "$d/w1-t3.nuc" 3

  printf '(import w1-self)\n(defn w1-self-fn ():i32 (return 9))\n' > "$d/w1-self.nuc"
  printf '(import w1-self)\n(defn main ():i32 (return (w1-self-fn)))\n' > "$d/w1-selfm.nuc"
  w1_run w1d-cycle-self-import "$d" "$d/w1-selfm.nuc" 9
  rm -rf "$d"
}

# The couplings a legal cycle cannot satisfy, and the ones it no longer has to.
# Each was emission-time — a cycle member's body is emitted BEFORE the rest of the
# file it back-imports, so anything that file defines after its own `import` had
# not run yet — and each used to fail with a message that blamed the wrong thing:
#   macro/const/enum → "not defined anywhere in this compilation unit" (it is);
#   layout           → "no field 'x' on struct 'S'" (it has that field), or, for
#                      a by-value struct at an ABI boundary, an `i0` aggregate
#                      and an UNLOCATED "failed to parse generated IR";
#   prefix alias     → "not defined anywhere" for a name that is in the unit.
# Three of the five have since been fixed rather than diagnosed (const/enum in
# W8 G-0, prefix aliases in B2b, layouts in W9 item 40) and their cases below
# assert the answer; what stays diagnosed is what a prescan genuinely cannot
# carry, i.e. what only an EMITTER produces: a macro and a `deferror` id.
run_w1d_cycle_diagnoses() {
  local d
  d="$(mktemp -d)"

  # 1. A macro defined by the cycle partner.
  printf '(import w1-mcb)\n(defmacro w1-amac (x) `(+ ,x 100))\n(defn w1-mca ():i32 (return 1))\n' > "$d/w1-mca.nuc"
  printf '(import w1-mca)\n(defn w1-mcb (n:i32):i32 (return (w1-amac n)))\n' > "$d/w1-mcb.nuc"
  printf '(import w1-mca)\n(defn main ():i32 (return (w1-mcb 5)))\n' > "$d/w1-mcm.nuc"
  w1_reject_multi w1d-cycle-macro-diagnosed "$d" "$d/w1-mcm.nuc" \
    "unknown: w1-amac — defined in a file this unit imports circularly"

  # 2. A `deferror` id from the cycle partner. This unit REPLACES
  # `w1d-cycle-defconst-diagnosed` and `w1d-cycle-defenum-diagnosed`, which
  # pinned the same diagnostic for a `defconst` and a `defenum` member. Stage 15
  # W8 G-0 moved value-name registration into the whole-graph prescan, so those
  # two names now RESOLVE across a cycle — the diagnostic they pinned can no
  # longer fire for them, and the positive replacements live in
  # run_g0_cycle_values below (compile + link + run, asserting the value, not
  # just exit 0). What those tests guarded is preserved here and there: a name
  # that a cycle genuinely cannot carry must still be diagnosed with the
  # located, cycle-specific message rather than the misleading "not defined
  # anywhere in this compilation unit", and `deferror` is such a name (its id is
  # allocated by `emit-deferror`, at emission time). `extern` is the other one.
  printf '(import w1-dfb)\n(deferror W1Boom "boom")\n(defn w1-dfa ():i32 (return 1))\n' > "$d/w1-dfa.nuc"
  printf '(import w1-dfa)\n(defn w1-dfb ():i32 (return (as i32 W1Boom)))\n' > "$d/w1-dfb.nuc"
  printf '(import w1-dfa)\n(defn main ():i32 (return (w1-dfb)))\n' > "$d/w1-dfm.nuc"
  w1_reject_multi w1d-cycle-deferror-diagnosed "$d" "$d/w1-dfm.nuc" \
    "undefined: W1Boom — defined in a file this unit imports circularly"

  # 3. The three LAYOUT couplings — a field access, a struct literal and a
  # by-value parameter over a struct the cycle partner defines. These INVERTED in
  # Stage 15 W9 item 40, the same way case 4 below inverted in B2b and the same
  # way `w1d-cycle-defconst-diagnosed` inverted in W8 G-0: the layout prescan
  # registers every reachable file's field tables before any form is emitted, so
  # the "'S' has no layout at this point" rejection these three pinned can no
  # longer fire for them. They are re-pointed rather than re-baselined, and each
  # asserts the ANSWER — the third one especially, since its old failure was a
  # SILENT miscompile (`define … @f(i0 %v.arg)`) that an exit-0 compile of a
  # never-called function would not have caught. `reject-cycle-pending-layout`
  # itself stays: an array field whose length this early pass cannot fold leaves
  # its struct un-laid-out, and that struct is still a cycle's problem.
  printf '(import w1-scb)\n(defstruct W1SC\n  x:i32\n  y:i32)\n(defn w1-sca ():i32 (return 1))\n' > "$d/w1-sca.nuc"
  printf '(import w1-sca)\n(defn w1-scb (p:ptr:W1SC):i32 (set! (p '\''x) 11) (return (p '\''x)))\n' > "$d/w1-scb.nuc"
  printf '(import w1-sca)\n(defn main ():i32 (let (s:ptr:W1SC (alloca W1SC)) (return (w1-scb s))))\n' > "$d/w1-scm.nuc"
  w1_run w1d-cycle-layout-resolves "$d" "$d/w1-scm.nuc" 11

  printf '(import w1-lcb)\n(defstruct W1LC\n  x:i32\n  y:i32)\n(defn w1-lca ():i32 (return 1))\n' > "$d/w1-lca.nuc"
  printf '(import w1-lca)\n(defn w1-lcb ():i32 (let (v:W1LC (W1LC 3 4)) (return (+ (_get (addr-of v) '\''x) (_get (addr-of v) '\''y)))))\n' > "$d/w1-lcb.nuc"
  printf '(import w1-lca)\n(defn main ():i32 (return (w1-lcb)))\n' > "$d/w1-lcm.nuc"
  w1_run w1d-cycle-structlit-resolves "$d" "$d/w1-lcm.nuc" 7

  printf '(import w1-bcb)\n(defstruct W1BC\n  x:i32\n  y:i32\n  z:i32\n  w:i32)\n(defn w1-bca ():i32 (return 1))\n' > "$d/w1-bca.nuc"
  printf '(import w1-bca)\n(defn w1-bcb (v:W1BC):i32 (return (+ (_get (addr-of v) '\''x) (_get (addr-of v) '\''w))))\n' > "$d/w1-bcb.nuc"
  printf '(import w1-bca)\n(defn main ():i32 (let (v:W1BC (W1BC 1 2 3 4)) (return (w1-bcb v))))\n' > "$d/w1-bcm.nuc"
  w1_run w1d-cycle-byval-resolves "$d" "$d/w1-bcm.nuc" 5

  # 4. A `prefix/name` over a cycle member. This one INVERTED in Stage 15 B2b
  # and the probe is re-pointed rather than re-baselined: W1d diagnosed it
  # because a skipped re-entry has no global-scope slice, so
  # `inject-import-aliases` injected no `prefix/name` key and the qualified
  # spelling resolved nowhere. B2b deletes the injection — a prefix names the
  # FILE, the W1a prescan has already registered that file's signatures and
  # `emit-ns` has already recorded its namespace — so the spelling now resolves
  # and the program runs. That removes the third of W1d's three emission-time
  # couplings (macros, layouts, prefix aliases) rather than diagnosing it, and
  # `cycle-prefix-message` went with it. Asserting the ANSWER (6) is what makes
  # this a test of resolution rather than of a diagnostic that no longer exists.
  printf '(import w1-pcb)\n(defn w1-pca (n:i32):i32 (return (+ n 1)))\n' > "$d/w1-pca.nuc"
  printf '(import w1-pca)\n(defn w1-pcb (n:i32):i32 (return (w1-pca/w1-pca n)))\n' > "$d/w1-pcb.nuc"
  printf '(import w1-pca)\n(defn main ():i32 (return (w1-pcb 5)))\n' > "$d/w1-pcm.nuc"
  w1_run w1d-cycle-prefix-resolves "$d" "$d/w1-pcm.nuc" 6

  # And the rule the skip must NOT relax: two files defining the same name+arity
  # are still a duplicate even when they are cycle partners. Silent last-wins
  # here would be a worse regression than the error W1d removed.
  printf '(import w1-dcb)\n(defn w1-dcdup (n:i32):i32 (return n))\n' > "$d/w1-dca.nuc"
  printf '(import w1-dca)\n(defn w1-dcdup (n:i32):i32 (return (+ n 1)))\n' > "$d/w1-dcb.nuc"
  printf '(import w1-dca)\n(defn main ():i32 (return (w1-dcdup 1)))\n' > "$d/w1-dcm.nuc"
  w1_reject_multi w1d-cycle-duplicate-rejected "$d" "$d/w1-dcm.nuc" \
    "duplicate definition of 'w1-dcdup'"
  rm -rf "$d"
}

# Two `.nuc` STRING-path imports in one file. Pre-existing bug (reproduces on the
# committed boot): emit-import-prefixed defaulted EVERY NODE-STR import's prefix
# to `c` — right for a C header, wrong for a Nucleus path — so the second one
# died `prefix 'c' is already bound to '<first path>'`, naming a prefix the
# author never wrote. A `.nuc`/`.nuch` path now defaults from its basename, the
# same rule the symbol spelling uses, so both prefixes work and an explicit
# second operand still wins.
# --- Stage 15 W5e: `defn-` name isolation -----------------------------------
# design/stage15-stress-test/ergonomics.md §W5e. A private definer in a file with
# no `(ns …)` is keyed under that file's implicit namespace, so two files may each
# define a private `helper`. Exit codes, not just "it compiles": a wrongly-routed
# call links fine and returns the OTHER file's answer, which only a value check
# catches. Each unit encodes both files' answers in one exit status.
run_w5e_private_isolated() {
  local d
  d="$(mktemp -d)"
  # 11 and 22; main returns a*10+b so either half being wrong changes the code.
  printf '(defn- w5e-h ():i32 (return 1))\n(defn w5e-a ():i32 (return (w5e-h)))\n' > "$d/w5e-pa.nuc"
  printf '(defn- w5e-h ():i32 (return 2))\n(defn w5e-b ():i32 (return (w5e-h)))\n' > "$d/w5e-pb.nuc"
  printf '(import-use w5e-pa)\n(import-use w5e-pb)\n(defn main ():i32 (return (+ (* 10 (w5e-a)) (w5e-b))))\n' > "$d/w5e-p1.nuc"
  printf '(import-use w5e-pb)\n(import-use w5e-pa)\n(defn main ():i32 (return (+ (* 10 (w5e-a)) (w5e-b))))\n' > "$d/w5e-p2.nuc"
  w1_run w5e-private-defn-order1 "$d" "$d/w5e-p1.nuc" 12
  w1_run w5e-private-defn-order2 "$d" "$d/w5e-p2.nuc" 12

  # `defvar-` is the same class and had a worse symptom: two `@g` definitions in
  # one module, rejected by the LLVM parser with no source location at all.
  printf '(defvar- w5e-g:i32 3)\n(defn w5e-va ():i32 (return w5e-g))\n' > "$d/w5e-va.nuc"
  printf '(defvar- w5e-g:i32 4)\n(defn w5e-vb ():i32 (return w5e-g))\n' > "$d/w5e-vb.nuc"
  printf '(import-use w5e-va)\n(import-use w5e-vb)\n(defn main ():i32 (return (+ (* 10 (w5e-va)) (w5e-vb))))\n' > "$d/w5e-v1.nuc"
  w1_run w5e-private-defvar "$d" "$d/w5e-v1.nuc" 34

  # A file's own private definition shadows a public one of the same name
  # elsewhere — exactly as a namespace-local name shadows an imported one — and
  # the public name is still reachable from everywhere else.
  printf '(defn- w5e-s ():i32 (return 1))\n(defn w5e-sa ():i32 (return (w5e-s)))\n' > "$d/w5e-sa.nuc"
  printf '(defn w5e-s ():i32 (return 9))\n(defn w5e-sc ():i32 (return (w5e-s)))\n' > "$d/w5e-sc.nuc"
  printf '(import-use w5e-sa)\n(import-use w5e-sc)\n(defn main ():i32 (return (+ (* 100 (w5e-sa)) (+ (* 10 (w5e-sc)) (w5e-s)))))\n' > "$d/w5e-s1.nuc"
  printf '(import-use w5e-sc)\n(import-use w5e-sa)\n(defn main ():i32 (return (+ (* 100 (w5e-sa)) (+ (* 10 (w5e-sc)) (w5e-s)))))\n' > "$d/w5e-s2.nuc"
  w1_run w5e-private-shadows-public-order1 "$d" "$d/w5e-s1.nuc" 199
  w1_run w5e-private-shadows-public-order2 "$d" "$d/w5e-s2.nuc" 199

  # Overloaded privates: two files each defining TWO private `w5e-o` methods
  # exercises the mangled path (per-method `@<file>_pN__w5e-o.<tok>`) rather than
  # the solitary one, and would collide on the bare mangled name without W5e.
  printf '(defn- w5e-o (n:i32):i32 (return 1))\n(defn- w5e-o (a:i32 b:i32):i32 (return 2))\n(defn w5e-oa ():i32 (return (+ (w5e-o 0) (w5e-o 0 0))))\n' > "$d/w5e-oa.nuc"
  printf '(defn- w5e-o (n:i32):i32 (return 10))\n(defn- w5e-o (a:i32 b:i32):i32 (return 20))\n(defn w5e-ob ():i32 (return (+ (w5e-o 0) (w5e-o 0 0))))\n' > "$d/w5e-ob.nuc"
  printf '(import-use w5e-oa)\n(import-use w5e-ob)\n(defn main ():i32 (return (+ (w5e-oa) (w5e-ob))))\n' > "$d/w5e-o1.nuc"
  w1_run w5e-private-overloaded "$d" "$d/w5e-o1.nuc" 33
  rm -rf "$d"
}

# What W5e must NOT relax. A PUBLIC name is still unique across the whole unit,
# and `defn-` in an explicit namespace is still private to that namespace — two
# files sharing one `(ns …)` still collide. Both diagnostics must name BOTH
# files and state the rule.
run_w5e_still_rejects() {
  local d err
  d="$(mktemp -d)"
  printf '(defn w5e-pub ():i32 (return 1))\n' > "$d/w5e-ca.nuc"
  printf '(defn w5e-pub ():i32 (return 2))\n' > "$d/w5e-cb.nuc"
  printf '(import-use w5e-ca)\n(import-use w5e-cb)\n(defn main ():i32 (return (w5e-pub)))\n' > "$d/w5e-c1.nuc"
  err="$(./build/nucleusc -I "$d" --emit-llvm "$d/w5e-c1.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep ':0:'; then
    echo "FAIL  w5e-public-collision-rejected (diagnostic reports line 0)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | qgrep -F "duplicate definition of 'w5e-pub'" \
    && printf '%s' "$err" | qgrep -F "$d/w5e-ca.nuc:1" \
    && printf '%s' "$err" | qgrep -F "$d/w5e-cb.nuc:1" \
    && printf '%s' "$err" | qgrep -F 'a public name must be unique'; then
    echo "PASS  w5e-public-collision-rejected"
  else
    echo "FAIL  w5e-public-collision-rejected"
    echo "    expected: both files named, plus the public-uniqueness rule"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi

  printf '(ns w5eg)\n(defn- w5e-nsh ():i32 (return 1))\n(defn w5e-na ():i32 (return (w5e-nsh)))\n' > "$d/w5e-na.nuc"
  printf '(ns w5eg)\n(defn- w5e-nsh ():i32 (return 2))\n(defn w5e-nb ():i32 (return (w5e-nsh)))\n' > "$d/w5e-nb.nuc"
  printf '(import-use w5e-na)\n(import-use w5e-nb)\n(defn main ():i32 (return 0))\n' > "$d/w5e-n1.nuc"
  err="$(./build/nucleusc -I "$d" --emit-llvm "$d/w5e-n1.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep ':0:'; then
    echo "FAIL  w5e-ns-private-collision-rejected (diagnostic reports line 0)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | qgrep -F "duplicate definition of 'w5e-nsh'" \
    && printf '%s' "$err" | qgrep -F "$d/w5e-na.nuc:2" \
    && printf '%s' "$err" | qgrep -F "$d/w5e-nb.nuc:2" \
    && printf '%s' "$err" | qgrep -F "private to its NAMESPACE" \
    && printf '%s' "$err" | qgrep -F "namespace 'w5eg'"; then
    echo "PASS  w5e-ns-private-collision-rejected"
  else
    echo "FAIL  w5e-ns-private-collision-rejected"
    echo "    expected: both files named, plus the per-namespace privacy rule"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi
  rm -rf "$d"
}

run_w1d_path_prefix() {
  local d err
  d="$(mktemp -d)"
  printf '(defn w1-ppa ():i32 (return 3))\n' > "$d/w1-ppa.nuc"
  printf '(defn w1-ppb ():i32 (return 4))\n' > "$d/w1-ppb.nuc"
  printf '(import "%s/w1-ppa.nuc")\n(import "%s/w1-ppb.nuc")\n(defn main ():i32 (return (+ (w1-ppa/w1-ppa) (w1-ppb/w1-ppb))))\n' \
    "$d" "$d" > "$d/w1-pp.nuc"
  w1_run w1d-two-path-imports "$d" "$d/w1-pp.nuc" 7

  printf '(import "%s/w1-ppa.nuc" alpha)\n(defn main ():i32 (return (alpha/w1-ppa)))\n' "$d" > "$d/w1-ppx.nuc"
  w1_run w1d-path-explicit-prefix "$d" "$d/w1-ppx.nuc" 3

  # A C header string path still defaults to `c` — the rule only changed for
  # `.nuc`/`.nuch`.
  printf '(import "stdio.h")\n(defn main ():i32 (c/printf "w1d\\n") (return 0))\n' > "$d/w1-ppc.nuc"
  w1_run w1d-cheader-prefix-unchanged "$d" "$d/w1-ppc.nuc" 0

  # Two different files whose basenames collide is a real conflict, and now
  # reports the prefix the author would actually recognize.
  mkdir -p "$d/sub"
  printf '(defn w1-ppa2 ():i32 (return 5))\n' > "$d/sub/w1-ppa.nuc"
  printf '(import "%s/w1-ppa.nuc")\n(import "%s/sub/w1-ppa.nuc")\n(defn main ():i32 (return 0))\n' \
    "$d" "$d" > "$d/w1-ppdup.nuc"
  err="$(./build/nucleusc --emit-llvm "$d/w1-ppdup.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep -F "import: prefix 'w1-ppa' is already bound to"; then
    echo "PASS  w1d-path-prefix-collision"
  else
    echo "FAIL  w1d-path-prefix-collision"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi
  rm -rf "$d"
}

# The deferral defect W1a exposed, fixed in defunion-register (union-registry.nuc)
# and reproducible on the PRE-W1a compiler: a union backing struct's
# `%X = type { i32, %anon }` line was written eagerly while its anon payload union
# sat on the deferred queue waiting for a struct payload's own type (`%String`,
# defined by a LATER import). Every module assembled in between — here a
# `compile-time` block that precedes the import — carried the reference with no
# definition and died `use of undefined type named '__anon_union_…'`.
run_w1_deferred_union_payload() {
  local d err
  d="$(mktemp -d)"
  cat > "$d/w1-ctdefer.nuc" <<'EOF'
(compile-time (printf "ct ran\n"))
(import-use string)
(defn w1-wrap (sv:StrView):!String (return (string-from-view sv)))
(defn main ():i32 (return 0))
EOF
  err="$(./build/nucleusc --emit-llvm "$d/w1-ctdefer.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep 'undefined type'; then
    echo "FAIL  w1-deferred-union-payload"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  else
    echo "PASS  w1-deferred-union-payload"
  fi
  rm -rf "$d"
}

# The second pre-existing defect W1a fixes, and the one with teeth: a function
# emitted BEFORE a later import overloads its name got the solitary `@name`
# symbol, while every call site after that import went through generic dispatch
# and emitted the mangled `@name.<tok>` — an undefined symbol. `lib/list.nuc`'s
# concrete `append` plus `lib/vector.nuc`'s `append` template is the shape:
# the pre-W1a compiler emits `define ptr @append` and
# `call ptr @append.ptr.ptr`, and the link dies `use of undefined value`.
# Registering every reachable signature before any emission makes the
# solitary-vs-mangled decision final before the first `define` is written.
run_w1_late_overload_symbol() {
  local d ir
  d="$(mktemp -d)"
  cat > "$d/w1-late.nuc" <<'EOF'
(import-use "lib/list.nuc")
(import-use vector)
(import-use node)   ; make-cell is a runtime call since the prelude split
(defn main ():i32
  (let (c:ptr (make-cell null null 0)
        r:ptr (append c c))
    (return 0)))
EOF
  ir="$(./build/nucleusc --emit-llvm "$d/w1-late.nuc" 2>/dev/null || true)"
  # `append` is written in lib/list.nuc, which this unit IMPORTS, so W9 item 2
  # gives it `weak_odr`. The linkage word is matched, not skipped: it is the
  # unit's answer to "do I own this definition", and a silent flip to external
  # would be the multi-object link failure item 2 fixed.
  if printf '%s' "$ir" | qgrep '^define weak_odr ptr @append\.ptr\.ptr(' \
     && ! printf '%s' "$ir" | qgrep -E '^define ([a-z_]+ )?ptr @append\(' ; then
    echo "PASS  w1-late-overload-symbol"
  else
    echo "FAIL  w1-late-overload-symbol (definition and call sites disagree on the mangled name)"
    printf '%s' "$ir" | grep -E '@append' | sed 's/^/    /' | head -6
  fi
  rm -rf "$d"
}

# --- Stage 15 W1c: the unreachable-file note ---------------------------------
# design/stage15-stress-test/resolution.md §W1c. W1a made a name that exists
# anywhere in the unit resolve, so the surviving `unknown:`/`undefined:` cases
# are a typo, a genuinely absent symbol, or §2.7's reachability constraint (the
# name IS defined, in a file no import reaches). The three units below pin one
# tier each, plus the negative control that keeps the scan from firing on a
# reachable definition.

# Tier 2: the name is defined in a sibling .nuc that sits on the -I path and on
# the entry file's own directory, and that nothing imports. The note must name
# THAT file, and the primary error must still be true on its own.
run_w1c_unreachable_file() {
  local d err
  d="$(mktemp -d)"
  printf '(defn w1c-elsewhere ():i32 (return 7))\n' > "$d/w1c-other.nuc"
  printf '(defn main ():i32 (return (w1c-elsewhere)))\n' > "$d/w1c-main.nuc"
  err="$(./build/nucleusc -I "$d" --emit-llvm "$d/w1c-main.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep ':0:'; then
    echo "FAIL  w1c-unreachable-file (diagnostic reports line 0)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | qgrep -F 'unknown: w1c-elsewhere — not defined anywhere in this compilation unit' \
     && printf '%s' "$err" | qgrep -F "note: 'w1c-elsewhere' is defined in $d/w1c-other.nuc, which no import in this unit reaches"; then
    echo "PASS  w1c-unreachable-file"
  else
    echo "FAIL  w1c-unreachable-file"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi

  # Negative control: adding the import makes it compile, link and run — the
  # note must be advice that actually works, and the scan must not fire on a
  # definition the unit already reaches.
  printf '(import w1c-other)\n(defn main ():i32 (return (w1c-elsewhere)))\n' > "$d/w1c-fixed.nuc"
  w1_run w1c-note-advice-works "$d" "$d/w1c-fixed.nuc" 7
  rm -rf "$d"
}

# Tier 4: nothing on the search path defines it. The message must say so
# plainly — the old text was a bare `unknown: <name>`, which after W1a reads as
# "not imported yet" when it now means "not in the unit at all".
run_w1c_defined_nowhere() {
  local d err
  d="$(mktemp -d)"
  printf '(defn main ():i32 (return (w1c-absent-everywhere)))\n' > "$d/w1c-none.nuc"
  err="$(./build/nucleusc -I "$d" --emit-llvm "$d/w1c-none.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep -F 'unknown: w1c-absent-everywhere — not defined anywhere in this compilation unit' \
     && ! printf '%s' "$err" | qgrep 'note:'; then
    echo "PASS  w1c-defined-nowhere"
  else
    echo "FAIL  w1c-defined-nowhere"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi
  rm -rf "$d"
}

# §2.7's TYPE reachability constraint stays a rule; W1c only improves its
# message. A struct named in a signature but defined in an unreached file gets
# the same note, from `parse-type-name`'s `unknown type:` raise.
run_w1c_unreachable_type() {
  local d err
  d="$(mktemp -d)"
  printf '(defstruct W1cWidget (a i32))\n' > "$d/w1c-ty.nuc"
  printf '(defn w1c-take (w:ptr:W1cWidget):i32 (return 0))\n(defn main ():i32 (return 0))\n' > "$d/w1c-tymain.nuc"
  err="$(./build/nucleusc -I "$d" --emit-llvm "$d/w1c-tymain.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep ':0:'; then
    echo "FAIL  w1c-unreachable-type (diagnostic reports line 0)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | qgrep -F 'unknown type: W1cWidget — not defined anywhere in this compilation unit' \
     && printf '%s' "$err" | qgrep -F "note: 'W1cWidget' is defined in $d/w1c-ty.nuc, which no import in this unit reaches"; then
    echo "PASS  w1c-unreachable-type"
  else
    echo "FAIL  w1c-unreachable-type"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi
  rm -rf "$d"
}

# --- Stage 15 W8 G-0: value names resolve on reachability --------------------
# design/global-init.md §5 (G-0) / §2.5. W1a did this for `defn` signatures,
# protocols and type names; `defvar` / `defconst` / `defenum` members were left
# registering at emission time, so a reference to one that had not been emitted
# yet died `undefined: X — not defined anywhere in this compilation unit` for a
# name that IS in the unit. `prescan-value-names` registers them on the same
# whole-graph walk.
#
# Every positive unit compiles, LINKS and RUNS, asserting the program's exit
# status: an exit-0 compile would not catch a value resolved to the wrong
# constant, and the two import orders return the same number, so a wrong answer
# here is only visible in the value.

# The three cross-file probes, in both import orders. `w1_run` compiles+links+
# runs and asserts the exit status.
run_g0_value_order() {
  local d
  d="$(mktemp -d)"

  # defconst: probe 2/3 of global-init.md §2.5. Order 1 worked before G-0;
  # order 2 died. Both must now return 42.
  printf '(defn g0-use-const ():i32 (return G0-MYK))\n' > "$d/g0-ca.nuc"
  printf '(defconst G0-MYK 42)\n' > "$d/g0-cb.nuc"
  printf '(import g0-cb)\n(import g0-ca)\n(defn main ():i32 (return (g0-use-const)))\n' > "$d/g0-c1.nuc"
  printf '(import g0-ca)\n(import g0-cb)\n(defn main ():i32 (return (g0-use-const)))\n' > "$d/g0-c2.nuc"
  w1_run g0-defconst-order1 "$d" "$d/g0-c1.nuc" 42
  w1_run g0-defconst-order2 "$d" "$d/g0-c2.nuc" 42

  # defenum MEMBER: probe 4. GREEN is ordinal 1, so a member resolved to the
  # wrong ordinal (or to the enum's own name) shows up in the exit status.
  printf '(defn g0-use-enum ():i32 (return G0-GREEN))\n' > "$d/g0-ea.nuc"
  printf '(defenum G0Color G0-RED G0-GREEN G0-BLUE)\n' > "$d/g0-eb.nuc"
  printf '(import g0-eb)\n(import g0-ea)\n(defn main ():i32 (return (g0-use-enum)))\n' > "$d/g0-e1.nuc"
  printf '(import g0-ea)\n(import g0-eb)\n(defn main ():i32 (return (g0-use-enum)))\n' > "$d/g0-e2.nuc"
  w1_run g0-defenum-order1 "$d" "$d/g0-e1.nuc" 1
  w1_run g0-defenum-order2 "$d" "$d/g0-e2.nuc" 1

  # defvar: a real global, so this also pins that a `load` emitted BEFORE the
  # `@g = global` line is a legal forward reference, and that a `set!` through
  # the prescan-registered Sym writes the same storage the emitter defines
  # (33 + 4 = 37).
  printf '(defn g0-use-var ():i32 (set! g0-gv (+ g0-gv 4)) (return g0-gv))\n' > "$d/g0-va.nuc"
  printf '(defvar g0-gv:i32 33)\n' > "$d/g0-vb.nuc"
  printf '(import g0-vb)\n(import g0-va)\n(defn main ():i32 (return (g0-use-var)))\n' > "$d/g0-v1.nuc"
  printf '(import g0-va)\n(import g0-vb)\n(defn main ():i32 (return (g0-use-var)))\n' > "$d/g0-v2.nuc"
  w1_run g0-defvar-order1 "$d" "$d/g0-v1.nuc" 37
  w1_run g0-defvar-order2 "$d" "$d/g0-v2.nuc" 37
  rm -rf "$d"
}

# W9 item 6's remaining surface, closed for the STRING-PATH spelling.
# `(import-use foo)` and `(import-use "…/foo.nuc")` name the same file and are
# the same import, but both prescan passes walked NODE-SYM only — so the string
# spelling registered nothing and every name in that file resolved on import
# ORDER, reporting `not defined anywhere in this compilation unit` for a name
# that is in the unit. Both passes now derive the path through one rule
# (`import-form-path`), which is also what `do-import` does with the string.
#
# All four name kinds the two passes cover are exercised, each USED BEFORE the
# import form so an order-dependent resolution cannot pass; and each links and
# runs, since an exit-0 compile would not catch a name bound to the wrong thing.
run_w9_string_path_prescan() {
  local d out
  d="$(mktemp -d)"; mkdir -p "$d/sub"
  cat > "$d/sub/sp.nuc" <<'EOF'
(defconst SP-K 7)
(defenum SpColor sp-red sp-green)
(defstruct SpRec n:i32)
(defvar sp-gv:i32 30)
(defn sp-add (a:i32):i32 (return (+ a SP-K)))
EOF

  # Pass 2 (signatures + values) and pass 1 (type NAMES), all used BEFORE the
  # import: a call, a constant, an enum member, a global, and the struct named in
  # a signature. 5 + 7 = 12, + 30 = 42, + 1 (sp-green) = 43.
  #
  # A field ACCESS before the import is deliberately not here: pass 1 registers
  # struct names, not layouts, so `(_get r '\''n)` fails ahead of the import for the
  # SYMBOL spelling too (measured). That is the W1d name-vs-layout split, not
  # this item — and the claim being pinned is that the two spellings agree.
  cat > "$d/spmain.nuc" <<EOF
(defn sp-use (r:ptr:SpRec):i32
  (return (+ (+ (sp-add 5) sp-gv) sp-green)))
(import-use "$d/sub/sp.nuc")
(defn main ():i32
  (let (r:ref:SpRec (SpRec 2))
    (return (sp-use (as ptr:SpRec r)))))
EOF
  w1_run w9-string-path-use-before-import "$d" "$d/spmain.nuc" 43

  # The point of the fix is that the two spellings agree. Same program, symbol
  # spelling, same answer — a regression in either direction fails here.
  cp "$d/sub/sp.nuc" "$d/sp.nuc"
  cat > "$d/spsym.nuc" <<'EOF'
(defn sp-use (r:ptr:SpRec):i32
  (return (+ (+ (sp-add 5) sp-gv) sp-green)))
(import-use sp)
(defn main ():i32
  (let (r:ref:SpRec (SpRec 2))
    (return (sp-use (as ptr:SpRec r)))))
EOF
  w1_run w9-string-path-matches-symbol-spelling "$d" "$d/spsym.nuc" 43

  # The two spellings must also agree on a MISSING file. The string branch's
  # `(= path null)` test could never fire (the path is the string verbatim), so
  # the error fell through to `read-file`'s unlocated `perror` while the symbol
  # spelling reported `import: cannot find` at the import's own line.
  printf '(import-use "%s/sub/nosuch.nuc")\n(defn main ():i32 (return 0))\n' "$d" > "$d/spbad.nuc"
  out="$(./build/nucleusc --emit-llvm "$d/spbad.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$out" | qgrep 'spbad.nuc:1: error: import: cannot find'; then
    echo "PASS  w9-string-path-missing-file-located"
  else
    echo "FAIL  w9-string-path-missing-file-located (want a located 'import: cannot find')"
    printf '%s\n' "$out" | sed 's/^/    /' | head -3
  fi
  rm -rf "$d"
}

# Stage 15 W9 item 8: the safe cast `as` decided "narrowing" from the two WIDTHS
# alone, so `(as i8 5)` was refused as lossy while the implicit coercion at the
# identical slot accepted it and emitted the very same `trunc i32 5 to i8` — the
# explicit spelling of a conversion was strictly stricter than the machinery it
# exists to make explicit. The fixture is self-checking (it compares every
# binding against the value it must hold and returns a distinct code per
# mismatch), so it is RUN, not merely compiled: the risk in a value-aware range
# test is a wrong value, not a failed compile.
#
# The IR assertion is the "no stricter than implicit" claim stated directly —
# the accepted form must lower to the same one instruction the implicit spelling
# emits, with no cast rule, no helper call and no widened temporary.
run_w9_as_literal_narrowing() {
  local d ir
  d="$(mktemp -d)"
  w1_run w9-as-literal-fits "$d" tests/fixtures/w9-as-literal-fits.nuc 0
  ir="$(./build/nucleusc --emit-llvm tests/fixtures/w9-as-literal-fits.nuc 2>/dev/null || true)"
  if printf '%s' "$ir" | qgrep -F 'trunc i32 5 to i8' \
     && printf '%s' "$ir" | qgrep -F '@w9as-g = global i8 9'; then
    echo "PASS  w9-as-literal-lowers-like-implicit"
  else
    echo "FAIL  w9-as-literal-lowers-like-implicit"
    echo "    want 'trunc i32 5 to i8' (value path) and '@w9as-g = global i8 9' (fold path)"
  fi
  rm -rf "$d"
}

# Stage 15 W9 item 30: the float half of the same rule. `emit-as` decided
# "lossy" from the two KINDS alone, so `(as f32 1.5)` was refused while
# `(let (a:f32 1.5) …)` accepted it and emitted the very same constant with no
# instruction at all. The fixture is self-checking (a distinct exit code per
# mismatch), so it is RUN: the risk in a round-trip test is a wrong value — a
# literal re-rendered at the wrong width — not a failed compile.
#
# The IR assertion is the "no stricter than implicit" claim stated directly, and
# it is stronger here than in the integer case: the accepted form must cost NO
# instruction at all. An `fptrunc` anywhere in the fixture's `main` would mean
# the cast was lowered as a conversion rather than folded to a constant.
run_w9_as_float_literal_narrowing() {
  local d ir
  d="$(mktemp -d)"
  w1_run w9-as-float-literal-fits "$d" tests/fixtures/w9-as-float-literal-fits.nuc 0
  ir="$(./build/nucleusc --emit-llvm tests/fixtures/w9-as-float-literal-fits.nuc 2>/dev/null || true)"
  if printf '%s' "$ir" | qgrep -F 'store float 0x3FF8000000000000' \
     && printf '%s' "$ir" | qgrep -F '@w9asf-g = global float 0x3FF8000000000000' \
     && printf '%s' "$ir" | qgrep -F '@w9asf-gd = global double 3.5' \
     && ! printf '%s' "$ir" | qgrep -F 'fptrunc'; then
    echo "PASS  w9-as-float-literal-lowers-like-implicit"
  else
    echo "FAIL  w9-as-float-literal-lowers-like-implicit"
    echo "    want the folded constant in both positions and NO fptrunc"
    printf '%s' "$ir" | grep -nE 'fptrunc|@w9asf-' | head -6 | sed 's/^/    /'
  fi
  rm -rf "$d"
}

# W9 item 31: bool is unsigned, so every consumer of `is-unsigned` must
# pick the unsigned instruction for it. The run covers the values; the IR
# assertion covers the instruction, and it is the half a run cannot make on
# this host — `sext i1` and `zext i1` differ only in the bit pattern above
# bit 0, and every consumer in the compiler's own source tests `(!= x 0)`,
# which -1 and 1 both satisfy. That is exactly why the defect survived every
# bootstrap until it was measured directly. (The greps name `i1` because that
# is bool's IR type — Stage 16 C1's divorce is source-level only.)
run_w9_bool_unsigned() {
  local d ir
  d="$(mktemp -d)"
  w1_run w9-bool-unsigned "$d" tests/fixtures/w9-bool-unsigned.nuc 0
  ir="$(./build/nucleusc --emit-llvm tests/fixtures/w9-bool-unsigned.nuc 2>/dev/null || true)"
  if ! printf '%s' "$ir" | qgrep -E 'sext i1|icmp s(lt|gt|le|ge) i1|sitofp i1'; then
    echo "PASS  w9-bool-unsigned-picks-unsigned-instructions"
  else
    echo "FAIL  w9-bool-unsigned-picks-unsigned-instructions"
    echo "    a bool operand reached a signed instruction"
    printf '%s' "$ir" | grep -nE 'sext i1|icmp s(lt|gt|le|ge) i1|sitofp i1' | head -6 | sed 's/^/    /'
  fi
  rm -rf "$d"
}

# W9 item 32: `gep-index-ir` widened every index with `sext`, so an unsigned
# index with its high bit set addressed BACKWARDS from the pointer. The fixture
# is the semantic gate — it keeps both the right and the wrong address inside a
# live allocation, so it returns a naming exit code rather than faulting.
#
# The IR assertions cover what a running program cannot. A `ui32` at 2^31 is the
# case the item was filed from and four billion elements is not addressable, so
# it is checked on the instruction; and the `sext` for a SIGNED index must still
# be there, or the fix would be a blanket zext that breaks `(aref p -1)`.
run_w9_unsigned_index() {
  local d ir uir
  d="$(mktemp -d)"
  w1_run w9-unsigned-index "$d" tests/fixtures/w9-unsigned-index.nuc 0

  ir="$(./build/nucleusc --emit-llvm tests/fixtures/w9-unsigned-index.nuc 2>/dev/null || true)"
  if printf '%s' "$ir" | qgrep -E 'sext i(8|16) %[A-Za-z0-9_.]+ to i64'; then
    echo "FAIL  w9-unsigned-index-widens-unsigned-with-zext"
    echo "    an unsigned index was sign-extended to pointer width"
    printf '%s' "$ir" | grep -nE 'sext i(8|16) %[A-Za-z0-9_.]+ to i64' | head -4 | sed 's/^/    /'
  else
    echo "PASS  w9-unsigned-index-widens-unsigned-with-zext"
  fi

  # A signed index still sign-extends: the fix is signedness-directed, not a
  # blanket zext.
  if printf '%s' "$ir" | qgrep -E 'sext i32 %[A-Za-z0-9_.]+ to i64'; then
    echo "PASS  w9-unsigned-index-keeps-sext-for-signed"
  else
    echo "FAIL  w9-unsigned-index-keeps-sext-for-signed"
    echo "    no signed index sign-extended; a blanket zext would break (aref p -1)"
  fi

  # The ui32-at-2^31 case from the item, which only the IR can witness.
  printf '(import prelude)\n(defn f (p:ptr:i32 i:ui32):i32 (return (aref p i)))\n(defn main ():i32 (return 0))\n' > "$d/w9ui32.nuc"
  uir="$(./build/nucleusc --emit-llvm "$d/w9ui32.nuc" 2>/dev/null || true)"
  if printf '%s' "$uir" | qgrep -E 'zext i32 %[A-Za-z0-9_.]+ to i64'; then
    echo "PASS  w9-unsigned-index-ui32"
  else
    echo "FAIL  w9-unsigned-index-ui32"
    echo "    a ui32 index was not zero-extended; at >=2^31 it addresses backwards"
    printf '%s' "$uir" | grep -nE '(s|z)ext i32 %[A-Za-z0-9_.]+ to i64' | head -4 | sed 's/^/    /'
  fi
  rm -rf "$d"
}

# W9 item 33: `emit-call-with-args`' coercion loop discarded `safe-coerce-val`'s
# null return, so an argument no conversion reaches was passed untouched. The
# fixture is the ACCEPTING half — the guard against over-correcting, since the
# failure mode of this fix is refusing a conversion the language performs.
#
# The refusing half is generated here, one program per case: compilation stops
# at the first error, and llvm-as accepts every one of these programs' IR
# because a call site carries its own signature. `(take-f64 3)` is the case that
# was not merely unchecked but wrong on ordinary-looking code: it printed
# 0.000000.
run_w9_arg_coerce() {
  local d out
  d="$(mktemp -d)"
  w1_run w9-arg-coerce "$d" tests/fixtures/w9-arg-coerce.nuc 0

  w9ac_case() {
    local label="$1" body="$2" out
    printf '%b' "$body" > "$d/w9ac.nuc"
    out="$(./build/nucleusc --emit-llvm "$d/w9ac.nuc" 2>&1 >/dev/null || true)"
    if printf '%s' "$out" | qgrep -F 'does not match parameter type'; then
      echo "PASS  $label"
    else
      echo "FAIL  $label"
      echo "    wanted an argument type-mismatch error, got: ${out:-<none>}"
    fi
  }

  w9ac_case w9-arg-coerce-rejects-int-into-ptr \
    '(defstruct W9S a:i32)\n(defn f (p:ptr:W9S):i32 (return 1))\n(defn main ():i32 (return (f 7)))\n'
  w9ac_case w9-arg-coerce-rejects-cstr-into-int \
    '(defn f (x:i32):i32 (return x))\n(defn main ():i32 (let (c:CStr "hi") (return (f c))))\n'
  w9ac_case w9-arg-coerce-rejects-float-into-int \
    '(defn f (x:i32):i32 (return x))\n(defn main ():i32 (return (f 1.5)))\n'
  w9ac_case w9-arg-coerce-rejects-int-into-float \
    '(defn f (x:f64):f64 (return x))\n(defn main ():i32 (f 3)\n  (return 0))\n'

  # The diagnostic locates the CALL and names the callee, the position and both
  # spellings — the last program written above is the int-into-float one.
  out="$(./build/nucleusc --emit-llvm "$d/w9ac.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$out" | qgrep -F 'w9ac.nuc:2: error: f: argument 1 has type i32, which does not match parameter type f64'; then
    echo "PASS  w9-arg-coerce-diagnostic-locates-and-names"
  else
    echo "FAIL  w9-arg-coerce-diagnostic-locates-and-names"
    echo "    got: ${out:-<none>}"
  fi
  rm -rf "$d"
}

# W9 item 41: TE-6's `(dyn P)` vtable forwarding lives in `emit-generic-call`,
# which a method with exactly ONE conformer never reaches — it stays a solitary
# `defn`. The fixture's run is the witness (a method with a second parameter
# receives the box's vtable word in it); the assertions below cover what the run
# cannot: that no call to a protocol method from a box is direct, and that the
# QUALIFIED spelling of a namespaced protocol's method reaches its slot, which
# needs the bare-name match `dyn-method-slot` only makes after checking the
# qualifier against the protocol's own namespace.
run_w9_dyn_solitary() {
  local d ir
  d="$(mktemp -d)"
  w1_run w9-dyn-solitary "$d" tests/fixtures/w9-dyn-solitary.nuc 0

  ir="$(./build/nucleusc --emit-llvm tests/fixtures/w9-dyn-solitary.nuc 2>/dev/null || true)"
  if printf '%s' "$ir" | qgrep -E 'call i32 @(add-k|name-of)\('; then
    echo "FAIL  w9-dyn-solitary-dispatches-indirectly"
    echo "    a boxed receiver reached the concrete method directly"
    printf '%s' "$ir" | grep -nE 'call i32 @(add-k|name-of)\(' | head -4 | sed 's/^/    /'
  else
    echo "PASS  w9-dyn-solitary-dispatches-indirectly"
  fi

  cat > "$d/w41lib.nuc" <<'EOF'
(exclude-prelude)
(ns w41)
(defprotocol Describe (describe ((self (ref Self))) i32))
(defstruct Fox n:i32)
(defn describe ((self (ref Fox))):i32 (return (_get self 'n)))
(extend Fox Describe)
EOF
  # The library excludes the prelude so its object and the consumer's link
  # together — the same separate-compilation shape run_w9_nuch_declare_generic
  # uses, which is also the only way to spell a QUALIFIED call to a method.
  cat > "$d/w41use.nuc" <<EOF
(import-use "stdio.h")
(import-use allocator)
(import "$d/w41lib.nuch" wx)
(defn main ():i32
  (let (b:(dyn wx/Describe) (wx/Fox 309))
    (printf "d=%d\n" (wx/describe b)))
  (return 0))
EOF
  ./build/nucleusc --emit-llvm "$d/w41lib.nuc" > "$d/w41lib.ll"   2>/dev/null || true
  ./build/nucleusc --emit-nuch "$d/w41lib.nuc" > "$d/w41lib.nuch" 2>/dev/null || true
  ./build/nucleusc --emit-llvm "$d/w41use.nuc" > "$d/w41use.ll"   2>/dev/null || true
  ir="$(cat "$d/w41use.ll")"
  # An empty module would pass a purely negative assertion, so require the
  # indirect call to be there as well as the direct one to be gone.
  if printf '%s' "$ir" | qgrep -E '^  %[A-Za-z0-9_.]+ = call i32 %[A-Za-z0-9_.]+\(ptr ' \
     && ! printf '%s' "$ir" | qgrep -F 'call i32 @w41__describe('; then
    echo "PASS  w9-dyn-solitary-qualified-reaches-slot"
  else
    echo "FAIL  w9-dyn-solitary-qualified-reaches-slot"
    echo "    the qualified spelling did not dispatch through the vtable"
  fi
  if clang "$d/w41lib.ll" "$d/w41use.ll" -o "$d/w41bin" 2>/dev/null \
     && [ "$("$d/w41bin")" = "d=309" ]; then
    echo "PASS  w9-dyn-solitary-qualified-runs"
  else
    echo "FAIL  w9-dyn-solitary-qualified-runs"
  fi
  rm -rf "$d"
}

# W9 item 34: the coercion guard compared LOWERED IR type strings, and every
# pointer flavour lowers to `ptr`, so a mismatch between two of them was never
# checked at all — a `CStr` reached a `(fn …)` parameter and the callee called
# it. The item's claim is a PARITY claim: the argument was the one typed slot
# that did not check what `let` checks. So the gate asserts the parity spelling
# by spelling, and the expected verdict beside it — parity alone would still
# hold if both positions regressed to accepting everything.
run_w9_fnslot_arg() {
  local d hdr case src want got_arg got_let ok
  d="$(mktemp -d)"
  w1_run w9-fnslot-arg "$d" tests/fixtures/w9-fnslot-arg.nuc 0

  hdr='(defstruct RS a:i32)
(defn fscb (x:i32):i32 (return (* 2 x)))
(defn take-fn (f:(fn i32)(i32)):i32 (return (funcall f 21)))
'
  ok=1
  # spelling:expected — `null` and a real fn value are the two a fn slot takes.
  for case in 'null:ok' 'c:no' 'p:no' 'r:no' 'rf:no' '7:no' '"s":no' 'g:ok'; do
    src="${case%:*}"
    want="${case##*:}"
    printf '%s(defn main ():i32\n  (let (c:CStr "hi" p:ptr (unsafe/cast ptr c) r:raw (unsafe/cast raw c) rf:ptr:RS (RS 1) g:(fn i32)(i32) fscb)\n    (return (take-fn %s))))\n' "$hdr" "$src" > "$d/fs-arg.nuc"
    printf '%s(defn main ():i32\n  (let (c:CStr "hi" p:ptr (unsafe/cast ptr c) r:raw (unsafe/cast raw c) rf:ptr:RS (RS 1) g:(fn i32)(i32) fscb)\n    (let (f:(fn i32)(i32) %s) (return 0))))\n' "$hdr" "$src" > "$d/fs-let.nuc"
    if ./build/nucleusc --emit-llvm "$d/fs-arg.nuc" >/dev/null 2>&1; then got_arg=ok; else got_arg=no; fi
    if ./build/nucleusc --emit-llvm "$d/fs-let.nuc" >/dev/null 2>&1; then got_let=ok; else got_let=no; fi
    if [ "$got_arg" != "$want" ] || [ "$got_let" != "$want" ]; then
      ok=0
      echo "    $src into a (fn ...) slot: argument=$got_arg let=$got_let, wanted $want"
    fi
  done
  if [ "$ok" = 1 ]; then
    echo "PASS  w9-fnslot-arg-matches-let"
  else
    echo "FAIL  w9-fnslot-arg-matches-let"
  fi

  # Stage 16 FP-3 (design/stage16-ergonomics/c-boundary-defects.md §3): the
  # diagnostic names the fn type as the user WROTE it. It used to print
  # type-spelling's `__fnty_<id>` — the conformance-registry key, which has to
  # stay round-trippable and names nothing in the source. `type-display`
  # (src/abi.nuc) renders the signature; `type-spelling` is unchanged and is
  # still what keys are built from.
  printf '%s(defn main ():i32\n  (let (c:CStr "hi") (return (take-fn c))))\n' "$hdr" > "$d/fs-msg.nuc"
  got_arg="$(./build/nucleusc --emit-llvm "$d/fs-msg.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$got_arg" | qgrep -F "take-fn: argument 1 has type CStr, which does not match parameter type (i32):i32"; then
    echo "PASS  w9-fnslot-arg-diagnostic"
  else
    echo "FAIL  w9-fnslot-arg-diagnostic"
    echo "    got: ${got_arg:-<none>}"
  fi

  # FP-1: a fn-pointer slot now checks the SIGNATURE, not just the kind. Both
  # halves matter — a matching signature must still pass at every typed slot,
  # and each shape of mismatch must be refused with both signatures named.
  printf '%s(defn one-arg (a:i32):i32 (return a))\n(defn wrong-ret (a:i32):i64 (return 1))\n(defn main ():i32\n  (let (ok:(fn i32)(i32) fscb) (return (funcall ok 1))))\n' "$hdr" > "$d/fs-sig-ok.nuc"
  if ./build/nucleusc --emit-llvm "$d/fs-sig-ok.nuc" >/dev/null 2>&1; then
    echo "PASS  s16-fp1-fnsig-match-accepted"
  else
    echo "FAIL  s16-fp1-fnsig-match-accepted"
    ./build/nucleusc --emit-llvm "$d/fs-sig-ok.nuc" 2>&1 >/dev/null | sed 's/^/    /'
  fi

  ok=1
  # spelling:substring the diagnostic must contain. Arity and return type are
  # the two mismatches that silently produced wrong values before FP-1
  # (c-boundary-defects.md §2.3).
  printf '%s(defn wrong-arity (a:i32 b:i32):i32 (return a))\n(defn main ():i32 (return (take-fn wrong-arity)))\n' "$hdr" > "$d/fs-sig-arity.nuc"
  got_arg="$(./build/nucleusc --emit-llvm "$d/fs-sig-arity.nuc" 2>&1 >/dev/null || true)"
  printf '%s' "$got_arg" | qgrep -F "has type (i32, i32):i32, which does not match parameter type (i32):i32" || ok=0
  printf '%s(defn wrong-ret (a:i32):i64 (return 1))\n(defn main ():i32 (return (take-fn wrong-ret)))\n' "$hdr" > "$d/fs-sig-ret.nuc"
  got_arg="$(./build/nucleusc --emit-llvm "$d/fs-sig-ret.nuc" 2>&1 >/dev/null || true)"
  printf '%s' "$got_arg" | qgrep -F "has type (i32):i64, which does not match parameter type (i32):i32" || ok=0
  # The `let` slot reaches the same rule through coerce-int-val and names both.
  printf '%s(defn wrong-arity (a:i32 b:i32):i32 (return a))\n(defn main ():i32\n  (let (f:(fn i32)(i32) wrong-arity) (return 0)))\n' "$hdr" > "$d/fs-sig-let.nuc"
  got_arg="$(./build/nucleusc --emit-llvm "$d/fs-sig-let.nuc" 2>&1 >/dev/null || true)"
  printf '%s' "$got_arg" | qgrep -F "let: init type mismatch for 'f': value is (i32, i32):i32, slot is (i32):i32" || ok=0
  # The two deliberate relaxations: pointer KIND is not part of a signature, and
  # a bare elem-less `ptr` is the fn-pointer analogue of `void *`. Without these
  # the ubiquitous `qsort` comparator shape would stop compiling.
  printf '(declare qs ((cmp (fn i32) (ptr ptr))) :void)\n(defn c1 (a:ptr:i32 b:(ref i32)):i32 (return 0))\n(defn main ():i32 (qs c1) (return 0))\n' > "$d/fs-sig-void.nuc"
  ./build/nucleusc --emit-llvm "$d/fs-sig-void.nuc" >/dev/null 2>&1 || ok=0
  # …but a bare ptr is NOT a wildcard for a function pointer: that would
  # reinstate the data-pointer-into-callable conversion `unsafe/cast` owns.
  printf '(declare qs2 ((cmp (fn i32) ((fn i32)(i32)))) :void)\n(defn c2 (f:ptr):i32 (return 0))\n(defn main ():i32 (qs2 c2) (return 0))\n' > "$d/fs-sig-fnwild.nuc"
  if ./build/nucleusc --emit-llvm "$d/fs-sig-fnwild.nuc" >/dev/null 2>&1; then ok=0; fi
  # …and two different pointee types stay a refusal.
  printf '(defstruct N a:i32)\n(declare qs3 ((cmp (fn i32) (ptr:N))) :void)\n(defn c3 (p:ptr:i32):i32 (return 0))\n(defn main ():i32 (qs3 c3) (return 0))\n' > "$d/fs-sig-elem.nuc"
  if ./build/nucleusc --emit-llvm "$d/fs-sig-elem.nuc" >/dev/null 2>&1; then ok=0; fi
  if [ "$ok" = 1 ]; then
    echo "PASS  s16-fp1-fnsig-mismatch-refused"
  else
    echo "FAIL  s16-fp1-fnsig-mismatch-refused"
  fi

  # The other half of the widened guard: two types that lower to the same IR
  # string but differ in SIGN now reach the literal range check, so an
  # out-of-range literal argument is refused instead of wrapping silently —
  # again exactly what `let` does with it.
  printf '(defn take-ui32 (x:ui32):ui32 (return x))\n(defn main ():i32 (return (as i32 (take-ui32 -1))))\n' > "$d/fs-neg.nuc"
  got_arg="$(./build/nucleusc --emit-llvm "$d/fs-neg.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$got_arg" | qgrep -F 'integer literal -1 does not fit ui32'; then
    echo "PASS  w9-fnslot-arg-samewidth-sign-checked"
  else
    echo "FAIL  w9-fnslot-arg-samewidth-sign-checked"
    echo "    got: ${got_arg:-<none>}"
  fi
  rm -rf "$d"
}

# Stage 16 SE-1/SE-2 (design/stage16-ergonomics/template-ref-equality.md): a
# typed slot checks the TYPE, not only the kind. Four claims, in the order the
# document makes them: the §6.1 shape is refused at every position; the pointee
# rule is general, not template-specific; the two relaxations FP-1 installed
# survive; and two instances of a return-only-tyvar constructor are two symbols.
run_s16_se_template_ref() {
  local d got ok=1
  d="$(mktemp -d)"

  # 1. §6.1, all three positions. Each names both types, so a regression that
  #    refuses for the wrong reason cannot pass.
  printf '(import-use "stdio.h")\n(import-use vector)\n(defn takes ((v (ref (Vector i64)))):i64 (return (invoke v 0)))\n(defn main ():i32\n  (with ((a (ref (Vector i32))) [1 2 3])\n    (printf "%%lld\\n" (takes a)))\n  (return 0))\n' > "$d/tre-arg.nuc"
  got="$(./build/nucleusc --emit-llvm "$d/tre-arg.nuc" 2>&1 >/dev/null || true)"
  printf '%s' "$got" | qgrep -F "argument 1 has type ptr:Vector.i32, which does not match parameter type ptr:Vector.i64" || ok=0
  printf '(import-use "stdio.h")\n(import-use vector)\n(defn main ():i32\n  (with ((a (ref (Vector i32))) [1 2 3])\n    (let (b:(ref (Vector i64)) a) (return 0))))\n' > "$d/tre-let.nuc"
  got="$(./build/nucleusc --emit-llvm "$d/tre-let.nuc" 2>&1 >/dev/null || true)"
  printf '%s' "$got" | qgrep -F "let: init type mismatch for 'b': value is ptr:Vector.i32, slot is ptr:Vector.i64" || ok=0
  printf '(import-use "stdio.h")\n(import-use vector)\n(defn main ():i32\n  (with ((a (ref (Vector i32))) [1 2 3]\n         (b (ref (Vector i64))) [4 5 6])\n    (set! b a) (return 0)))\n' > "$d/tre-set.nuc"
  got="$(./build/nucleusc --emit-llvm "$d/tre-set.nuc" 2>&1 >/dev/null || true)"
  printf '%s' "$got" | qgrep -F "set!: type mismatch for 'b': value is ptr:Vector.i32, slot is ptr:Vector.i64" || ok=0
  if [ "$ok" = 1 ]; then
    echo "PASS  s16-se1-template-ref-refused"
  else
    echo "FAIL  s16-se1-template-ref-refused"
    echo "    got: ${got:-<none>}"
  fi

  # 2. The runtime shape §6.1 measured: a correctly-typed literal reads element
  #    0 as one i64. The defect printed 8589934593 (0x2_00000001) here — two
  #    i32s read at the wrong stride — so the value IS the assertion.
  ok=1
  printf '(import-use "stdio.h")\n(import-use vector)\n(defn takes ((v (ref (Vector i64)))):i64 (return (invoke v 0)))\n(defn main ():i32\n  (with ((a (ref (Vector i64))) [1 2 3])\n    (printf "%%lld\\n" (takes a)))\n  (return 0))\n' > "$d/tre-ok.nuc"
  ./build/nucleusc "$d/tre-ok.nuc" -o "$d/tre-ok" >/dev/null 2>&1 || ok=0
  if [ "$ok" = 1 ]; then
    got="$("$d/tre-ok" 2>&1 || true)"
    [ "$got" = "1" ] || ok=0
  fi
  if [ "$ok" = 1 ]; then
    echo "PASS  s16-se1-template-ref-runtime"
  else
    echo "FAIL  s16-se1-template-ref-runtime"
    echo "    got: ${got:-<none>} (wanted 1)"
  fi

  # 3. The rule is about pointees, not about templates: two plain structs are
  #    the same shape of defect and the same refusal.
  ok=1
  printf '(defstruct SA x:i32)\n(defstruct SB y:i64 z:i64)\n(defn takes (b:(ref SB)):i64 (return (b '\''y)))\n(defn main ():i32\n  (let (a:(ref SA) (SA 7)) (return (as i32 (takes a)))))\n' > "$d/tre-struct.nuc"
  got="$(./build/nucleusc --emit-llvm "$d/tre-struct.nuc" 2>&1 >/dev/null || true)"
  printf '%s' "$got" | qgrep -F "has type ptr:SA, which does not match parameter type ptr:SB" || ok=0
  # …and the two relaxations stay: pointer KIND is not part of the question
  # (pkind-flow-check owns that), and an elem-less bare `ptr` is `void *`.
  printf '(defstruct SA x:i32)\n(defn takes (b:(ref SA)):i32 (return (b '\''x)))\n(defn wild (p:ptr):i32 (return 0))\n(defn main ():i32\n  (let (a:ptr:SA (SA 7) q:ptr (unsafe/cast ptr (SA 1)))\n    (let (r:(ref SA) (unsafe/cast (ref SA) q) w:ptr a)\n      (return (+ (takes a) (+ (wild a) (takes r)))))))\n' > "$d/tre-relax.nuc"
  ./build/nucleusc --emit-llvm "$d/tre-relax.nuc" >/dev/null 2>&1 || ok=0
  # …and the CONSTANT renderer asks the same rule: `defvar` is the second
  # typed-slot path and had the identity hole independently (conventions.md's
  # "a SECOND value-into-a-typed-slot path"). A bare `ptr` global still takes
  # any address, which is what makes the check safe to add.
  printf '(defstruct SA x:i32)\n(defstruct SB y:i64)\n(defvar ga:SA)\n(defvar gp:(ref SB) (addr-of ga))\n(defn main ():i32 (return 0))\n' > "$d/tre-gv.nuc"
  got="$(./build/nucleusc --emit-llvm "$d/tre-gv.nuc" 2>&1 >/dev/null || true)"
  printf '%s' "$got" | qgrep -F "defvar: addr-of: 'ga' has type ptr:SA, which does not match ptr:SB" || ok=0
  printf '(defstruct SA x:i32)\n(defvar ga:SA)\n(defvar gq:ptr (addr-of ga))\n(defvar gr:(ref SA) (addr-of ga))\n(defn main ():i32 (return 0))\n' > "$d/tre-gv-ok.nuc"
  ./build/nucleusc --emit-llvm "$d/tre-gv-ok.nuc" >/dev/null 2>&1 || ok=0
  if [ "$ok" = 1 ]; then
    echo "PASS  s16-se1-pointee-rule-general"
  else
    echo "FAIL  s16-se1-pointee-rule-general"
    echo "    got: ${got:-<none>}"
  fi

  # 4. SE-2: a constructor whose type variable appears only in its return type
  #    is stamped once per instance, under a symbol that says which. Before this
  #    the `.pAllocHandle` key was the whole name, so the first stamp answered
  #    for every later element type — which is what made claim 1 reachable from
  #    ordinary code with no cast in it.
  ok=1
  printf '(import-use "stdio.h")\n(import-use vector)\n(defn main ():i32\n  (let (a:(ref (Vector i32)) (vector-new-in (default-allocator))\n        b:(ref (Vector i64)) (vector-new-in (default-allocator)))\n    (conj a 5) (conj b 7000000000)\n    (let (i:usize 0)\n      (printf "%%d %%lld\\n" (invoke a i) (invoke b i))))\n  (return 0))\n' > "$d/tre-stamp.nuc"
  ./build/nucleusc --emit-llvm "$d/tre-stamp.nuc" > "$d/tre-stamp.ll" 2>/dev/null || ok=0
  qgrep -F '@vector_new_in.pAllocHandle.$r.pVector.i32' "$d/tre-stamp.ll" || ok=0
  qgrep -F '@vector_new_in.pAllocHandle.$r.pVector.i64' "$d/tre-stamp.ll" || ok=0
  ./build/nucleusc "$d/tre-stamp.nuc" -o "$d/tre-stamp" >/dev/null 2>&1 || ok=0
  if [ "$ok" = 1 ]; then
    got="$("$d/tre-stamp" 2>&1 || true)"
    [ "$got" = "5 7000000000" ] || ok=0
  fi
  if [ "$ok" = 1 ]; then
    echo "PASS  s16-se2-want-stamped-instances"
  else
    echo "FAIL  s16-se2-want-stamped-instances"
    echo "    got: ${got:-<none>} (wanted '5 7000000000')"
  fi
  rm -rf "$d"
}

# Stage 16 FP-2 (design/stage16-ergonomics/c-boundary-defects.md §2.4): an
# indirect call goes through the same argument path as a direct one. It used to
# stop at the arity check — no coercion, no diagnostic, no vararg promotion and
# no struct ABI, so a by-value struct argument was handed to the callee as a raw
# aggregate the callee never reads. Asserted on the IR, because the wrong code
# links and can even return the right answer for small structs by luck.
run_s16_fp2_indirect_call() {
  local d ir got ok=1
  d="$(mktemp -d)"
  cat > "$d/fp2.nuc" <<'FP2EOF'
(declare printf (fmt:CStr):i32)
(defstruct Pt x:i64 y:i64)
(defstruct Big a:i64 b:i64 c:i64)
(defn sum-pt (p:Pt):i64
  (let (q:ptr:Pt (addr-of p)) (return (+ (q 'x) (q 'y)))))
(defn make-big (n:i64):Big (return (Big n (+ n 1) (+ n 2))))
(defn addl (a:i64):i64 (return (+ a 1)))
(defn main ():i32
  (let (f:(fn i64)(Pt) sum-pt
        g:(fn Big)(i64) make-big
        h:(fn i64)(i64) addl)
    (printf "%lld\n" (funcall f (Pt 3 4)))
    (let (b:Big (funcall g 10)
          bp:ptr:Big (addr-of b))
      (printf "%lld\n" (bp 'c)))
    (printf "%lld\n" (funcall h 5))
    (return 0)))
FP2EOF
  ir="$(./build/nucleusc --emit-llvm "$d/fp2.nuc" 2>/dev/null || true)"
  # Pt is a two-eightbyte INTEGER struct, so SysV passes it in two registers;
  # Big is over the limit and returns through sret. Both at an indirect site.
  printf '%s' "$ir" | qgrep -E '= call i64 %t[0-9]+\(i64 %t[0-9]+, i64 %t[0-9]+\)' || ok=0
  printf '%s' "$ir" | qgrep -E 'call void %t[0-9]+\(ptr sret\(%Big\) align 8 ' || ok=0
  # The i32 literal widens to the i64 parameter, as it does on the direct path.
  printf '%s' "$ir" | qgrep -E '= call i64 %t[0-9]+\(i64 %t[0-9]+\)$' || ok=0
  if [ "$ok" = 1 ]; then echo "PASS  s16-fp2-indirect-call-abi"; else
    echo "FAIL  s16-fp2-indirect-call-abi"
    printf '%s' "$ir" | grep -E 'call .*%t[0-9]+\(' | sed 's/^/    /'
  fi
  w1_run s16-fp2-indirect-call-runs "$d" "$d/fp2.nuc" 0

  # A variadic fn pointer keeps its `(ptr, ...)` call signature and promotes
  # f32 to double — the promotion is the caller's job and there was nobody
  # doing it here before.
  cat > "$d/va.nuc" <<'VAEOF'
(import-use "stdio.h")
(defn main ():i32
  (let (p printf
        fv:f32 1.5)
    (funcall p "%s %d %.1f\n" "x" 7 fv)
    (return 0)))
VAEOF
  ir="$(./build/nucleusc --emit-llvm "$d/va.nuc" 2>/dev/null || true)"
  if printf '%s' "$ir" | qgrep -E 'call i32 \(ptr, \.\.\.\) %t[0-9]+\(.*double %t[0-9]+\)'; then
    echo "PASS  s16-fp2-indirect-vararg-promoted"
  else
    echo "FAIL  s16-fp2-indirect-vararg-promoted"
    printf '%s' "$ir" | grep -E 'call .*%t[0-9]+\(' | sed 's/^/    /'
  fi

  # And the argument check itself now reaches indirect calls.
  cat > "$d/bad.nuc" <<'BADEOF'
(defn addl (a:i64):i64 (return (+ a 1)))
(defn main ():i32
  (let (h:(fn i64)(i64) addl
        c:CStr "hi")
    (return (as i32 (funcall h c)))))
BADEOF
  got="$(./build/nucleusc --emit-llvm "$d/bad.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$got" | qgrep -F "call: argument 1 has type CStr, which does not match parameter type i64"; then
    echo "PASS  s16-fp2-indirect-arg-diagnostic"
  else
    echo "FAIL  s16-fp2-indirect-arg-diagnostic"
    echo "    got: ${got:-<none>}"
  fi
  rm -rf "$d"
}

# Stage 16 FP-4 (design/stage16-ergonomics/c-boundary-defects.md §2.1): the C
# importer builds a real TY-FN for each of C's four function-pointer declarator
# positions. Every one used to become `ptr`, so `qsort`/`atexit` refused a
# Nucleus function, a struct with such a member came out opaque, and the
# `signal` shape was skipped outright. Paired with FP-1, which is what turns the
# recovered type into a checked one.
run_s16_fp4_cheader_fnptr() {
  local d ir got ok=1
  d="$(mktemp -d)"

  # The headline case, against the real system header: the two most canonical
  # callbacks in C, called with a Nucleus function and no cast.
  cat > "$d/q.nuc" <<'QEOF'
(import-use "stdlib.h")
(defn cmpi (a:ptr b:ptr):i32 (return 0))
(defn bye ():void (return))
(defn main ():i32
  (let (arr:ptr (malloc 40))
    (qsort arr 10 4 cmpi)
    (atexit bye)
    (return 0)))
QEOF
  got="$(./build/nucleusc --emit-llvm "$d/q.nuc" 2>&1 >/dev/null || true)"
  if [ -z "$got" ]; then
    echo "PASS  s16-fp4-qsort-atexit"
  else
    echo "FAIL  s16-fp4-qsort-atexit"
    printf '%s\n' "$got" | sed 's/^/    /' | head -3
  fi

  # All four declarator positions, plus a nested one and `(void)`.
  cat > "$d/t.nuc" <<'TEOF'
(import-use "tests/fixtures/s16-fnptr.h")
(declare printf (fmt:CStr):i32)
(defn cmpv (a:ptr b:ptr):i32 (return 0))
(defn ten (a:i32):i32 (return (* a 10)))
(defn main ():i32
  (let (h:ptr:S16Hold (S16Hold ten 5)
        c:s16_cmp cmpv)
    (printf "member=%d field=%d\n" (funcall (h 'cb) 4) (h 'n))
    (set! (h 'cb) ten)
    (funcall c null null)
    (return 0)))
TEOF
  ir="$(./build/nucleusc --emit-llvm "$d/t.nuc" 2>/dev/null || true)"
  # The member's NAME was dropped before FP-4, which abandoned the struct.
  printf '%s' "$ir" | qgrep -F '%S16Hold = type { ptr, i32 }' || ok=0
  # `void (*s16_signal(int, void (*)(int)))(int)` and `int (*s16_get(void))(int,int)`
  # were skipped entirely; both now register.
  printf '%s' "$ir" | qgrep -F 'declare ptr @s16_signal(i32, ptr)' || ok=0
  printf '%s' "$ir" | qgrep -F 'declare ptr @s16_get()' || ok=0
  printf '%s' "$ir" | qgrep -F 'declare i32 @s16_nest(ptr)' || ok=0
  if [ "$ok" = 1 ]; then echo "PASS  s16-fp4-declarator-positions"; else
    echo "FAIL  s16-fp4-declarator-positions"
    printf '%s' "$ir" | grep -E '@s16_|%S16Hold' | sed 's/^/    /' | head -6
  fi
  w1_run s16-fp4-callbacks-run "$d" "$d/t.nuc" 0

  # The recovered type is a CHECKED type — the point of doing this after FP-1.
  # Each of the four positions refuses a wrong signature by name.
  ok=1
  cat > "$d/bad1.nuc" <<'B1EOF'
(import-use "tests/fixtures/s16-fnptr.h")
(defn one (a:i32):i32 (return a))
(defn main ():i32 (s16_apply_inline one 1 2) (return 0))
B1EOF
  got="$(./build/nucleusc --emit-llvm "$d/bad1.nuc" 2>&1 >/dev/null || true)"
  printf '%s' "$got" | qgrep -F "s16_apply_inline: argument 1 has type (i32):i32, which does not match parameter type (i32, i32):i32" || ok=0
  cat > "$d/bad2.nuc" <<'B2EOF'
(import-use "tests/fixtures/s16-fnptr.h")
(defn one (a:i32):i32 (return a))
(defn main ():i32
  (let (h:ptr:S16Hold (S16Hold one 5))
    (return (funcall (h 'cb) 1 2))))
B2EOF
  got="$(./build/nucleusc --emit-llvm "$d/bad2.nuc" 2>&1 >/dev/null || true)"
  printf '%s' "$got" | qgrep -F "expected 1 args, got 2" || ok=0
  cat > "$d/bad3.nuc" <<'B3EOF'
(import-use "tests/fixtures/s16-fnptr.h")
(defn one (a:i32):i32 (return a))
(defn main ():i32 (let (c:s16_cmp one) (return 0)))
B3EOF
  got="$(./build/nucleusc --emit-llvm "$d/bad3.nuc" 2>&1 >/dev/null || true)"
  printf '%s' "$got" | qgrep -F "let: init type mismatch for 'c'" || ok=0
  if [ "$ok" = 1 ]; then echo "PASS  s16-fp4-recovered-type-is-checked"; else
    echo "FAIL  s16-fp4-recovered-type-is-checked"
  fi
  rm -rf "$d"
}

# Stage 16 FP-5 (design/stage16-ergonomics/c-boundary-defects.md §2.2): the
# export side used to render every function-pointer type as `void*` — which is
# not merely unchecked but not standard C, since ISO C defines no conversion
# between a function pointer and `void *`, so a conforming compiler may diagnose
# every call site. Asserted against a real C consumer built with -Werror, not
# just against the text.
run_s16_fp5_cheader_fnptr() {
  local d ok=1
  d="$(mktemp -d)"
  cat > "$d/lib.nuc" <<'LEOF'
(defstruct Hold (cb (fn i32) (i32 i32)) n:i32)
(defstruct Arr (xs (array i32 4)) k:i32)
(defn addem (a:i32 b:i32):i32 (return (+ a b)))
(defn use2 (f:(fn i32)(i32 i32)):i32 (return (funcall f 1 2)))
(defn getf ():(fn i32)(i32 i32) (return addem))
(defn holdsum (h:ptr:Hold):i32 (return (funcall (h 'cb) (h 'n) (h 'n))))
LEOF
  ./build/nucleusc --emit-cheader "$d/lib.nuc" > "$d/lib.h" 2>"$d/h.err" || true
  qgrep -F -x '    int32_t (*cb)(int32_t, int32_t);' "$d/lib.h" || ok=0
  qgrep -F -x 'int32_t use2(int32_t (*f)(int32_t, int32_t));' "$d/lib.h" || ok=0
  # A function RETURNING a function pointer wraps its own declarator.
  qgrep -F -x 'int32_t (*getf(void))(int32_t, int32_t);' "$d/lib.h" || ok=0
  # The array declarator still comes out of the same renderer unchanged.
  qgrep -F -x '    int32_t xs[4];' "$d/lib.h" || ok=0
  if [ "$ok" = 1 ]; then echo "PASS  s16-fp5-cheader-declarators"; else
    echo "FAIL  s16-fp5-cheader-declarators"
    sed 's/^/    /' "$d/lib.h" | head -20
    sed 's/^/    err: /' "$d/h.err" | head -3
  fi

  if ! command -v cc >/dev/null 2>&1; then
    echo "PASS  s16-fp5-c-consumer (SKIP: no cc)"
  else
    ./build/nucleusc -c "$d/lib.nuc" -o "$d/lib.o" 2>"$d/o.err" || true
    cat > "$d/main.c" <<'CEOF'
#include <stdio.h>
#include "lib.h"
static int times(int a, int b) { return a * b; }
int main(void) {
  Hold h = { times, 6 };
  printf("use2=%d getf=%d hold=%d\n", use2(times), getf()(3, 4), holdsum(&h));
  return 0;
}
CEOF
    if cc -std=c11 -Wall -Wextra -Werror -I"$d" "$d/main.c" "$d/lib.o" -o "$d/cmain" 2>"$d/c.err" \
       && [ "$("$d/cmain")" = "use2=2 getf=7 hold=36" ]; then
      echo "PASS  s16-fp5-c-consumer"
    else
      echo "FAIL  s16-fp5-c-consumer"
      sed 's/^/    /' "$d/c.err" | head -6
      sed 's/^/    /' "$d/o.err" | head -3
    fi
  fi
  rm -rf "$d"
}

# Stage 16 SV-1 (design/stage16-ergonomics/c-boundary-defects.md §2.5): a struct
# VALUE is a member-access receiver. `(get v '\''x)` on a by-value parameter, a call
# result or a struct local all used to be `_get: operand must be pointer to
# struct or union` — not a C-specific gap, but it is what made every by-value C
# API (libclang's cursors, every struct-returning libc call) need an alloca and
# a ptr-set! first.
run_s16_sv1_struct_value_receiver() {
  local d got ok=1
  d="$(mktemp -d)"
  cat > "$d/sv.nuc" <<'SVEOF'
(declare printf (fmt:CStr):i32)
(defstruct Pt x:i64 y:i64)
(defn mk (n:i64):Pt (return (Pt n (* n 2))))
; All three read spellings against a by-value PARAMETER.
(defn sum (p:Pt):i64 (return (+ (get p 'x) (+ (p 'y) (_get p 'x)))))
; And straight off a call result, with no binding at all.
(defn direct ():i64 (return (get (mk 5) 'y)))
(defn main ():i32
  (let (v:Pt (mk 3))
    (printf "%lld %lld %lld %lld\n" (sum v) (direct) (get v 'x) (v 'y))
    ; `.set!` on a by-value local mutates the local copy, as in C.
    (set! (v 'x) 40)
    (printf "%lld %d\n" (get v 'x) (if (= (addr-of v 'y) null) 0 1))
    (return 0)))
SVEOF
  ./build/nucleusc "$d/sv.nuc" -o "$d/sv.bin" 2>"$d/sv.err" || true
  if [ -x "$d/sv.bin" ] && [ "$("$d/sv.bin")" = "12 10 3 6
40 1" ]; then
    echo "PASS  s16-sv1-struct-value-receiver"
  else
    echo "FAIL  s16-sv1-struct-value-receiver"
    sed 's/^/    /' "$d/sv.err" | head -4
    [ -x "$d/sv.bin" ] && "$d/sv.bin" | sed 's/^/    got: /'
  fi

  # The other half: `.set!`/`addr-of` need the receiver's STORAGE, so a temporary
  # stays an error rather than a store into something about to be discarded.
  # This is also what keeps a pointer into that copy from being returned.
  cat > "$d/t1.nuc" <<'T1EOF'
(defstruct Pt x:i64 y:i64)
(defn mk (n:i64):Pt (return (Pt n n)))
(defn main ():i32 (set! ((mk 1) 'x) 5) (return 0))
T1EOF
  got="$(./build/nucleusc --emit-llvm "$d/t1.nuc" 2>&1 >/dev/null || true)"
  printf '%s' "$got" | qgrep -F ".set!: the receiver is a temporary struct value, so it has no address" || ok=0
  cat > "$d/t2.nuc" <<'T2EOF'
(defstruct Pt x:i64 y:i64)
(defn mk (n:i64):Pt (return (Pt n n)))
(defn leak ():ptr:i64 (return (addr-of (mk 1) 'x)))
(defn main ():i32 (return 0))
T2EOF
  got="$(./build/nucleusc --emit-llvm "$d/t2.nuc" 2>&1 >/dev/null || true)"
  printf '%s' "$got" | qgrep -F "addr-of: the receiver is a temporary struct value" || ok=0
  # A non-struct receiver is still refused, and the message now names both
  # legal receivers.
  cat > "$d/t3.nuc" <<'T3EOF'
(defstruct Pt x:i64 y:i64)
(defn main ():i32 (let (k:i64 5) (return (as i32 (_get k 'x)))))
T3EOF
  got="$(./build/nucleusc --emit-llvm "$d/t3.nuc" 2>&1 >/dev/null || true)"
  printf '%s' "$got" | qgrep -F "_get: operand must be a struct or union, or a pointer to one" || ok=0
  # A missing field on a VALUE receiver reports the field, not the receiver —
  # which is only possible if the type pass unwrapped it in lockstep.
  cat > "$d/t4.nuc" <<'T4EOF'
(defstruct Pt x:i64 y:i64)
(defn f (p:Pt):i64 (return (_get p 'zzz)))
(defn main ():i32 (return 0))
T4EOF
  got="$(./build/nucleusc --emit-llvm "$d/t4.nuc" 2>&1 >/dev/null || true)"
  printf '%s' "$got" | qgrep -F "_get: no field 'zzz' on struct 'Pt'" || ok=0
  if [ "$ok" = 1 ]; then echo "PASS  s16-sv1-lvalue-and-refusals"; else
    echo "FAIL  s16-sv1-lvalue-and-refusals"
  fi
  rm -rf "$d"
}

# Stage 16 C1/C2 (design/stage16-ergonomics/cheader-parser-vs-libclang.md §3).
# C1: a bare `unsigned`/`signed` used to make the DECLARATOR name the base type,
# so `unsigned a;` abandoned its struct and `unsigned f(void);` was dropped —
# zero occurrences in glibc, which is why the census missed it, and pervasive in
# third-party headers (libclang's own `clang-c/Index.h` among them). C2: a
# declaration the parser declines is recorded with a reason, so the use site
# says more than "not defined anywhere".
run_s16_c1_bare_unsigned() {
  local d ok=1 got
  d="$(mktemp -d)"

  if ! command -v cc >/dev/null 2>&1; then
    echo "PASS  s16-c1-bare-unsigned (SKIP: no cc to build the oracle against)"
  else
    cat > "$d/o.c" <<'OEOF'
#include <stdio.h>
#include "s16-unsigned.h"
int main(void){
  printf("%zu %zu %zu %zu %zu %zu %zu %zu\n",
    sizeof(struct S16U01), sizeof(struct S16U02), sizeof(struct S16U03),
    sizeof(struct S16U04), sizeof(struct S16U05), sizeof(struct S16U06),
    sizeof(struct S16U07), sizeof(struct S16U08));
  return 0;
}
OEOF
    if ! cc -I tests/fixtures "$d/o.c" -o "$d/o.bin" 2>"$d/o.err"; then
      echo "PASS  s16-c1-bare-unsigned (SKIP: the C oracle does not build)"
    else
      cat > "$d/n.nuc" <<'NEOF'
(import-use "tests/fixtures/s16-unsigned.h")
(declare printf (fmt:CStr):i32)
(defn main ():i32
  (printf "%ld %ld %ld %ld %ld %ld %ld %ld\n"
    (as i64 (sizeof S16U01)) (as i64 (sizeof S16U02)) (as i64 (sizeof S16U03))
    (as i64 (sizeof S16U04)) (as i64 (sizeof S16U05)) (as i64 (sizeof S16U06))
    (as i64 (sizeof S16U07)) (as i64 (sizeof S16U08)))
  (return 0))
NEOF
      ./build/nucleusc "$d/n.nuc" -o "$d/n.bin" 2>"$d/n.err" || true
      if [ -x "$d/n.bin" ] && [ "$("$d/n.bin")" = "$("$d/o.bin")" ]; then
        echo "PASS  s16-c1-bare-unsigned"
      else
        echo "FAIL  s16-c1-bare-unsigned (Nucleus disagrees with cc on size)"
        echo "    cc:      $("$d/o.bin")"
        [ -x "$d/n.bin" ] && echo "    nucleus: $("$d/n.bin")"
        sed 's/^/    /' "$d/n.err" | head -3
      fi
    fi
  fi

  # Signedness, not just size: an out-of-range literal is refused for the
  # unsigned field and accepted for the signed one.
  printf '(import-use "tests/fixtures/s16-unsigned.h")\n(defn main ():i32\n  (let (p:ptr:S16U01 (alloca S16U01)) (set! (p '\''a) -1) (return 0)))\n' > "$d/neg.nuc"
  got="$(./build/nucleusc --emit-llvm "$d/neg.nuc" 2>&1 >/dev/null || true)"
  printf '%s' "$got" | qgrep -F 'integer literal -1 does not fit ui32' || ok=0
  printf '(import-use "tests/fixtures/s16-unsigned.h")\n(defn main ():i32\n  (let (p:ptr:S16U02 (alloca S16U02)) (set! (p '\''a) -1) (return 0)))\n' > "$d/pos.nuc"
  ./build/nucleusc --emit-llvm "$d/pos.nuc" >/dev/null 2>&1 || ok=0
  # The two bare-specifier FUNCTIONS register at all.
  printf '(import-use "tests/fixtures/s16-unsigned.h")\n(defn main ():i32 (s16u_f) (s16u_g 1 2) (return 0))\n' > "$d/fn.nuc"
  ./build/nucleusc --emit-llvm "$d/fn.nuc" 2>/dev/null | qgrep -F 'declare i32 @s16u_f()' || ok=0
  if [ "$ok" = 1 ]; then echo "PASS  s16-c1-signedness-and-functions"; else
    echo "FAIL  s16-c1-signedness-and-functions"
  fi

  # C2: the use site names the header, the line and a reason.
  printf '(import-use "tests/fixtures/s16-unsigned.h")\n(defn main ():i32 (return (s16u_odd 1)))\n' > "$d/c2.nuc"
  got="$(./build/nucleusc --emit-llvm "$d/c2.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$got" | qgrep -E "unknown: 's16u_odd' — its C header declaration was skipped \(.*s16-unsigned\.h:[0-9]+: a declaration shape the C header parser does not recognize\)"; then
    echo "PASS  s16-c2-skip-reason-recorded"
  else
    echo "FAIL  s16-c2-skip-reason-recorded"
    echo "    got: ${got:-<none>}"
  fi
  rm -rf "$d"
}

# W1b's half of G-0: `scope-define` qualifies a global's key against
# `g-current-ns`, so the prescan must apply each visited file's own leading
# `(ns …)`. Prescanning a namespaced file under the IMPORTER's namespace would
# register the value under an unlookupable key — and W5e's synthetic per-file
# private namespace is the same mechanism one level down, so a `defconst-`
# forward-referenced inside its own file must resolve while staying invisible
# outside it.
run_g0_value_scoping() {
  local d err
  d="$(mktemp -d)"
  # The namespaced file's own constant is declared AFTER the function that reads
  # it, so the prescan is what resolves both the bare in-namespace reference and
  # the qualified cross-file one. 55 either way.
  # Stage 15 B2b re-pointed the spellings for R3, exactly as run_w1_ns above:
  # naming `g0alpha/` requires an import that binds it. The forward reference
  # being measured — `g0-ns-get` reads `G0-NSK` declared BELOW it, and a second
  # file reads the same constant across the namespace boundary — is untouched.
  printf '(ns g0alpha)\n(defn g0-ns-get ():i32 (return G0-NSK))\n(defconst G0-NSK 55)\n' > "$d/g0-nsa.nuc"
  printf '(import-use g0-nsa)\n(defn g0-ns-user ():i32 (return g0alpha/G0-NSK))\n' > "$d/g0-nsb.nuc"
  printf '(import-use g0-nsb)\n(import-use g0-nsa)\n(defn main ():i32 (return (g0-ns-user)))\n' > "$d/g0-ns1.nuc"
  printf '(import-use g0-nsb)\n(import-use g0-nsa)\n(defn main ():i32 (return (g0alpha/g0-ns-get)))\n' > "$d/g0-ns2.nuc"
  w1_run g0-ns-qualified-value "$d" "$d/g0-ns1.nuc" 55
  w1_run g0-ns-internal-forward "$d" "$d/g0-ns2.nuc" 55

  # …and the key really is namespace-qualified: the bare spelling must NOT leak
  # into a file outside the namespace. Registering it under the importer's `user`
  # namespace would make this compile, which is the exact W1b failure.
  printf '(import g0-nsa)\n(defn main ():i32 (return G0-NSK))\n' > "$d/g0-ns3.nuc"
  err="$(./build/nucleusc -I "$d" --emit-llvm "$d/g0-ns3.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep 'undefined: G0-NSK'; then
    echo "PASS  g0-ns-value-not-leaked"
  else
    echo "FAIL  g0-ns-value-not-leaked"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi

  # A private constant, forward-referenced from earlier in its OWN file: the
  # prescan must key it under the file's synthetic `#pN/` namespace, exactly as
  # the emitter does, or the reader resolves to nothing — or, worse, to another
  # file's public name of the same spelling. That "worse" is not hypothetical:
  # on the pre-G-0 compiler this program COMPILES CLEAN and returns 7, the other
  # file's PUBLIC constant, because the private key did not exist yet when the
  # reader was emitted. A silent wrong answer, which is why this unit runs the
  # program and checks the value instead of checking that it compiles.
  printf '(defn g0-priv-get ():i32 (return G0-SECRET))\n(defconst- G0-SECRET 61)\n' > "$d/g0-pa.nuc"
  printf '(defconst G0-SECRET 7)\n' > "$d/g0-pb.nuc"
  printf '(import g0-pb)\n(import g0-pa)\n(defn main ():i32 (return (g0-priv-get)))\n' > "$d/g0-p1.nuc"
  w1_run g0-private-const-forward "$d" "$d/g0-p1.nuc" 61

  # …and it stays private: another file may not see it.
  printf '(import g0-pa)\n(defn main ():i32 (return G0-OTHER-SECRET))\n' > "$d/g0-p2.nuc"
  printf '(defconst- G0-OTHER-SECRET 3)\n(defn g0-pc ():i32 (return G0-OTHER-SECRET))\n' > "$d/g0-pc.nuc"
  printf '(import g0-pc)\n(defn main ():i32 (return G0-OTHER-SECRET))\n' > "$d/g0-p3.nuc"
  err="$(./build/nucleusc -I "$d" --emit-llvm "$d/g0-p3.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep 'undefined: G0-OTHER-SECRET'; then
    echo "PASS  g0-private-const-stays-private"
  else
    echo "FAIL  g0-private-const-stays-private"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi
  rm -rf "$d"
}

# The positive replacements for `w1d-cycle-defconst-diagnosed` and
# `w1d-cycle-defenum-diagnosed`, which pinned the OLD behaviour (both were a
# located "defined in a file this unit imports circularly" rejection). G-0
# registers value names before any emission, and the whole-graph walk visits
# both members of a cycle, so those two names now resolve — the rejection they
# pinned cannot fire for them any more. What the old tests guarded is preserved:
# `w1d-cycle-deferror-diagnosed` keeps the diagnostic itself pinned for a name a
# cycle still cannot carry, and these three assert the VALUE, not just exit 0.
run_g0_cycle_values() {
  local d
  d="$(mktemp -d)"
  printf '(import g0-kcb)\n(defconst G0-KA 42)\n(defn g0-kca ():i32 (return 1))\n' > "$d/g0-kca.nuc"
  printf '(import g0-kca)\n(defn g0-kcb ():i32 (return G0-KA))\n' > "$d/g0-kcb.nuc"
  printf '(import g0-kca)\n(defn main ():i32 (return (g0-kcb)))\n' > "$d/g0-kcm.nuc"
  w1_run g0-cycle-defconst "$d" "$d/g0-kcm.nuc" 42

  printf '(import g0-ecb)\n(defenum G0CColor G0C-RED G0C-GREEN G0C-BLUE)\n(defn g0-eca ():i32 (return 1))\n' > "$d/g0-eca.nuc"
  printf '(import g0-eca)\n(defn g0-ecb ():i32 (return G0C-BLUE))\n' > "$d/g0-ecb.nuc"
  printf '(import g0-eca)\n(defn main ():i32 (return (g0-ecb)))\n' > "$d/g0-ecm.nuc"
  w1_run g0-cycle-defenum "$d" "$d/g0-ecm.nuc" 2

  printf '(import g0-vcb)\n(defvar g0-vg:i32 77)\n(defn g0-vca ():i32 (return 1))\n' > "$d/g0-vca.nuc"
  printf '(import g0-vca)\n(defn g0-vcb ():i32 (return g0-vg))\n' > "$d/g0-vcb.nuc"
  printf '(import g0-vca)\n(defn main ():i32 (return (g0-vcb)))\n' > "$d/g0-vcm.nuc"
  w1_run g0-cycle-defvar "$d" "$d/g0-vcm.nuc" 77
  rm -rf "$d"
}

# --- Stage 15 W8 G-1: constant expressions in a global initializer -----------
# design/global-init.md §5 "G-1". The shape matrix (arithmetic, bit ops, sizeof,
# `as`, `(char "x")`, `addr-of`, and a same-file forward constant) is
# examples/g1-const-init.nuc, which prints every folded value — a folder's
# characteristic failure is the WRONG NUMBER, which an exit-0 compile cannot see.
# What is left here is the part that needs more than one file: a constant folded
# from a file the unit has not emitted yet, in both import orders, and a private
# constant that must not be shadowed by another file's public spelling. Both
# read W2b's `const-lit` provenance, which G-0 arms on the whole-graph prescan.
run_g1_fold_cross_file() {
  local d
  d="$(mktemp -d)"

  # g1-xb has NO import of g1-xa: the fold resolves G1XK purely by reachability.
  # Order 2 emits g1-xb's `@g1-xv = global` line before g1-xa is processed at
  # all, so a fold that read only already-emitted state would get nothing.
  printf '(defconst G1XK 7)\n' > "$d/g1-xa.nuc"
  printf '(defvar g1-xv:i32 (* G1XK 6))\n(defn g1-xget ():i32 (return g1-xv))\n' > "$d/g1-xb.nuc"
  printf '(import g1-xa)\n(import g1-xb)\n(defn main ():i32 (return (g1-xget)))\n' > "$d/g1-x1.nuc"
  printf '(import g1-xb)\n(import g1-xa)\n(defn main ():i32 (return (g1-xget)))\n' > "$d/g1-x2.nuc"
  w1_run g1-fold-cross-order1 "$d" "$d/g1-x1.nuc" 42
  w1_run g1-fold-cross-order2 "$d" "$d/g1-x2.nuc" 42

  # W5e's private key, one level down from run_g0_value_scoping's version: the
  # folded initializer sits EARLIER in the file than the `defconst-` it reads,
  # and another file defines the same spelling publicly. 9*5 = 45 is the private
  # constant; 9*7 = 63 would be the public one leaking in.
  printf '(defvar g1-pv:i32 (* G1PK 9))\n(defconst- G1PK 5)\n(defn g1-pget ():i32 (return g1-pv))\n' > "$d/g1-pa.nuc"
  printf '(defconst G1PK 7)\n' > "$d/g1-pb.nuc"
  printf '(import g1-pb)\n(import g1-pa)\n(defn main ():i32 (return (g1-pget)))\n' > "$d/g1-p1.nuc"
  w1_run g1-fold-private-const "$d" "$d/g1-p1.nuc" 45

  # `(addr-of g)` across files, where the target global is defined in a file
  # emitted AFTER the initializer that takes its address: the emitted `@g` is a
  # forward reference LLVM resolves at end of module, and the Sym (and therefore
  # the symbol spelling) comes from G-0's prescan.
  printf '(defvar g1-atgt:i32 88)\n' > "$d/g1-aa.nuc"
  printf '(defvar g1-aptr:ptr:i32 (addr-of g1-atgt))\n(defn g1-aget ():i32 (return (deref g1-aptr)))\n' > "$d/g1-ab.nuc"
  printf '(import g1-ab)\n(import g1-aa)\n(defn main ():i32 (return (g1-aget)))\n' > "$d/g1-a1.nuc"
  w1_run g1-addr-of-cross-file "$d" "$d/g1-a1.nuc" 88
  rm -rf "$d"
}

# --- Stage 15 W8 G-2: the (array T N) type + constant aggregates -------------
# design/global-init.md §5 "G-2". The five shapes' positive matrix is
# examples/g2-array-init.nuc (printed values, so a wrong constant is visible).
# What needs more than one file, or a non-`--emit-llvm` output mode, is here:
# the C header's postfix array declarator (checked by COMPILING the header and
# comparing offsets against Nucleus's own), and the .nuch round-trip.
run_g2_cheader() {
  local d out
  d="$(mktemp -d)"
  cat > "$d/g2h.nuc" <<'G2EOF'
(defconst G2N 3)
(defstruct G2Rec tag:i8 (cells (array i32 4)) (names (array CStr G2N)) mark:i8)
G2EOF
  cat > "$d/g2h.c" <<'G2EOF'
#include <stdio.h>
#include <stddef.h>
#include "g2h.h"
int main(void){ printf("%zu %zu %zu %zu\n", sizeof(G2Rec), offsetof(G2Rec,cells), offsetof(G2Rec,names), offsetof(G2Rec,mark)); return 0; }
G2EOF
  cat > "$d/g2n.nuc" <<'G2EOF'
(import-use "stdio.h")
(defconst G2N 3)
(defstruct G2Rec tag:i8 (cells (array i32 4)) (names (array CStr G2N)) mark:i8)
(defn g2off (base:ptr fld:ptr):i64 (return (- (unsafe/cast i64 fld) (unsafe/cast i64 base))))
(defn main ():i32
  (let (s:ptr:G2Rec (alloca G2Rec))
    (printf "%lld %lld %lld %lld\n" (as i64 (sizeof G2Rec))
      (g2off s (addr-of s 'cells)) (g2off s (addr-of s 'names)) (g2off s (addr-of s 'mark))))
  (return 0))
G2EOF
  if ! ./build/nucleusc --emit-cheader "$d/g2h.nuc" > "$d/g2h.h" 2>"$d/err"; then
    echo "FAIL  g2-cheader-array-field (--emit-cheader failed)"; sed 's/^/    /' "$d/err"; rm -rf "$d"; return 0
  fi
  # The declarator must be postfix C: `int32_t cells[4];`, and a named extent
  # must survive as the name (the header exports `#define G2N 3` beside it).
  if ! qgrep 'int32_t cells\[4\];' "$d/g2h.h" || ! qgrep 'names\[G2N\];' "$d/g2h.h"; then
    echo "FAIL  g2-cheader-array-field (declarator not postfix C)"
    grep -n 'cells\|names' "$d/g2h.h" | sed 's/^/    /'
    rm -rf "$d"; return 0
  fi
  if ! cc -I"$d" "$d/g2h.c" -o "$d/g2c" 2>"$d/err"; then
    echo "FAIL  g2-cheader-array-field (generated header does not compile as C)"; sed 's/^/    /' "$d/err"; rm -rf "$d"; return 0
  fi
  if ! ./build/nucleusc "$d/g2n.nuc" -o "$d/g2nbin" 2>"$d/err"; then
    echo "FAIL  g2-cheader-array-field (nucleus side failed)"; sed 's/^/    /' "$d/err"; rm -rf "$d"; return 0
  fi
  if [ "$("$d/g2c")" = "$("$d/g2nbin")" ]; then
    echo "PASS  g2-cheader-array-field"
  else
    echo "FAIL  g2-cheader-array-field (C and Nucleus disagree on layout)"
    echo "    C:       $("$d/g2c")"
    echo "    Nucleus: $("$d/g2nbin")"
  fi
  rm -rf "$d"
}

# A `.nuch` header must round-trip an array field: emit it, import it back, and
# use the field. `emit-nuch-defstruct` prints the field forms verbatim, so what
# this really pins is that the IMPORT side re-parses `(array T N)` into the same
# layout — the sizeof is compared against the original unit's.
run_g2_nuch() {
  local d
  d="$(mktemp -d)"
  cat > "$d/g2lib.nuc" <<'G2EOF'
(defconst G2K 3)
(defstruct G2Box (slots (array i32 G2K)) n:i32)
; An array-typed global exports as `(extern (g2tab (array i32 4)))`, so the
; IMPORT side's `extern` path has to accept an array type too -- a library that
; emits a header its own consumer cannot read is the failure this pins.
(defvar g2tab:(array i32 4) (array i32 100 200 300 400))
G2EOF
  cat > "$d/g2use.nuc" <<'G2EOF'
(import-use g2lib)
(defn main ():i32
  (let (b:ptr:G2Box (alloca G2Box))
    (set! (aref (b 'slots) 2) 7)
    (set! (b 'n) 9)
    (return (+ (aref (b 'slots) 2) (+ (b 'n) (+ (unsafe/cast i32 (sizeof G2Box)) (aref g2tab 1)))))))
G2EOF
  if ! ./build/nucleusc --emit-nuch "$d/g2lib.nuc" > "$d/g2lib.nuch" 2>"$d/err"; then
    echo "FAIL  g2-nuch-array-field (--emit-nuch failed)"; sed 's/^/    /' "$d/err"; rm -rf "$d"; return 0
  fi
  if ! qgrep '(array i32 G2K)' "$d/g2lib.nuch"; then
    echo "FAIL  g2-nuch-array-field (array field not exported)"; sed 's/^/    /' "$d/g2lib.nuch"; rm -rf "$d"; return 0
  fi
  if ! qgrep '(extern (g2tab (array i32 4)))' "$d/g2lib.nuch"; then
    echo "FAIL  g2-nuch-array-field (array-typed defvar not exported as an extern)"; sed 's/^/    /' "$d/g2lib.nuch"; rm -rf "$d"; return 0
  fi
  # 7 + 9 + sizeof(G2Box) + g2tab[1] = 7 + 9 + 16 + 200 = 232
  w1_run g2-nuch-array-field "$d" "$d/g2use.nuc" 232
  rm -rf "$d"
}

# --- Stage 15 W8 G-3: @__nucleus_init, emitted only when non-empty -----------
# design/global-init.md §5 "G-3". The positive matrix is
# examples/g3-runtime-init.nuc (printed values — a startup initializer's
# characteristic failure is that it never ran, and the slot's zero is
# indistinguishable from a successful compile unless you look at it). What needs
# more than one file, or the IR rather than the program, is here.

# THE GATE (§4.8). A unit with no runtime initializer must emit NOTHING: no
# @__nucleus_init, no llvm.global_ctors, no registration global of any kind.
# The stated reason is microcontroller binary size, so this is a hard
# requirement on the feature rather than a nicety, and it is the property that
# keeps the bootstrap byte-identical through this step.
#
# Deliberately checked against a unit that uses EVERY constant-initializer shape
# G-1/G-2 added, not an empty file: the failure mode this guards against is a
# classifier that quietly routes a foldable initializer down the runtime path,
# which an empty file could never see. tests/run-avr-test.sh carries the same
# assertion for --target=avr, on the target the requirement was stated for.
run_g3_zero_cost() {
  local d ll
  d="$(mktemp -d)"
  cat > "$d/g3zc.nuc" <<'G3EOF'
(defconst G3K 6)
(defstruct G3P x:i32 y:i32)
(defvar g3-lit:i32 41)
(defvar g3-fold:i32 (* G3K 7))
(defvar g3-str:CStr (as CStr "zero-cost"))
(defvar g3-addr:ptr:i32 (addr-of g3-lit))
(defvar g3-arr:(array i32 3) (array i32 1 2 3))
(defvar g3-zeros:(array i32 4))
(defvar g3-struct:G3P (G3P 1 2))
(defvar g3-tabp:ptr:i32 (array i32 9 8 7))
(defn main ():i32 (return (+ g3-lit (+ g3-fold (aref g3-arr 0)))))
G3EOF
  ll="$d/g3zc.ll"
  if ! ./build/nucleusc --emit-llvm "$d/g3zc.nuc" > "$ll" 2>"$d/err"; then
    echo "FAIL  g3-zero-cost (compile failed)"; sed 's/^/    /' "$d/err"; rm -rf "$d"; return 0
  fi
  if qgrep -E '__nucleus_init|global_ctors' "$ll"; then
    echo "FAIL  g3-zero-cost (a constant-only unit emitted startup-constructor machinery)"
    grep -nE '__nucleus_init|global_ctors' "$ll" | sed 's/^/    /'
    rm -rf "$d"; return 0
  fi
  # The complement, in the same function so the two can never drift apart: add
  # ONE runtime initializer to the identical unit and both artefacts must appear.
  # Without this half, deleting the whole feature would still pass the tripwire.
  sed 's|^(defn main|(defvar g3-rt:i32 (g3-call))\n(defn g3-call ():i32 (return 5))\n(defn main|' \
    "$d/g3zc.nuc" > "$d/g3rt.nuc"
  if ! ./build/nucleusc --emit-llvm "$d/g3rt.nuc" > "$d/g3rt.ll" 2>"$d/err"; then
    echo "FAIL  g3-zero-cost (runtime-initializer variant failed to compile)"; sed 's/^/    /' "$d/err"; rm -rf "$d"; return 0
  fi
  if ! qgrep 'define internal void @__nucleus_init()' "$d/g3rt.ll" \
     || ! qgrep '@llvm.global_ctors = appending global' "$d/g3rt.ll"; then
    echo "FAIL  g3-zero-cost (one runtime initializer did NOT produce the machinery)"
    rm -rf "$d"; return 0
  fi
  echo "PASS  g3-zero-cost"
  rm -rf "$d"
}

# The multi-TU case, and the one that justifies llvm.global_ctors over every
# synthetic-entry-point option (§2.4, §4.3): a LIBRARY with no Nucleus `main`,
# exported as `.nuch` + a separately compiled `.o`, whose global is initialized
# by its own object's `.init_array` entry. `main` lives in the consumer's
# translation unit and never calls anything to make this happen.
#
# The library is `(exclude-prelude)` and that is NOT incidental: two separately
# compiled Nucleus objects cannot currently be linked at all, because both carry
# the prelude's globals AND its functions (`arena-init`, `g-arena`, …) with
# external linkage — W9 defect 2, measured again here. §2.4 was measured by the
# same route. Fixing that is not G-3 work; this is the narrowest fixture that
# genuinely exercises the multi-TU path without it.
run_g3_library() {
  local d
  d="$(mktemp -d)"
  mkdir -p "$d/libsrc" "$d/inc"
  # No `main`, no explicit init entry point, and the initializer is a call.
  cat > "$d/libsrc/g3lib.nuc" <<'G3EOF'
(exclude-prelude)
(defvar g3-lib-n:i32 (g3-lib-compute))
(defn g3-lib-compute ():i32 (return 42))
(defn g3-lib-get ():i32 (return g3-lib-n))
G3EOF
  cat > "$d/g3user.nuc" <<'G3EOF'
(import g3lib)
(defn main ():i32
  (when (!= g3-lib-n 42) (return 1))
  (when (!= (g3-lib-get) 42) (return 2))
  (return 0))
G3EOF
  if ! ./build/nucleusc --emit-nuch "$d/libsrc/g3lib.nuc" > "$d/inc/g3lib.nuch" 2>"$d/err"; then
    echo "FAIL  g3-library-nuch (--emit-nuch failed)"; sed 's/^/    /' "$d/err"; rm -rf "$d"; return 0
  fi
  if ! qgrep '(extern (g3-lib-n i32))' "$d/inc/g3lib.nuch"; then
    echo "FAIL  g3-library-nuch (global not exported)"; sed 's/^/    /' "$d/inc/g3lib.nuch"; rm -rf "$d"; return 0
  fi
  if ! ./build/nucleusc -c -o "$d/g3lib.o" "$d/libsrc/g3lib.nuc" 2>"$d/err"; then
    echo "FAIL  g3-library-nuch (library object failed)"; sed 's/^/    /' "$d/err"; rm -rf "$d"; return 0
  fi
  if ! ./build/nucleusc -c -o "$d/g3user.o" -I "$d/inc" "$d/g3user.nuc" 2>"$d/err"; then
    echo "FAIL  g3-library-nuch (consumer object failed)"; sed 's/^/    /' "$d/err"; rm -rf "$d"; return 0
  fi
  if ! clang "$d/g3user.o" "$d/g3lib.o" -o "$d/g3user" 2>"$d/err"; then
    echo "FAIL  g3-library-nuch (link failed)"; sed 's/^/    /' "$d/err"; rm -rf "$d"; return 0
  fi
  set +e; "$d/g3user"; local got=$?; set -e
  if [ "$got" = 0 ]; then
    echo "PASS  g3-library-nuch"
  else
    echo "FAIL  g3-library-nuch (library initializer did not run: exit $got)"
  fi
  rm -rf "$d"
}

# --- Stage 15 W8 G-4: the initializer-ordering diagnostic --------------------
# design/global-init.md §4.2. The rejections are `run_reject_at` fixtures below;
# this unit is the other half — every shape the check must keep ACCEPTING, each
# linked, run, and asserted BY VALUE. "It compiles" cannot tell an initializer
# that ran from one that silently kept its zero, which is the exact failure the
# diagnostic exists to prevent.
run_g4_order() {
  local d err
  d="$(mktemp -d)"

  # 1. Same-file BACKWARD reference — the legal direction, and the one the
  #    forward fixture is the mirror of. 41 + 1 = 42.
  printf '(defn g4-c ():i32 (return 41))\n(defvar g4-b:i32 (g4-c))\n(defvar g4-a:i32 (+ g4-b 1))\n(defn main ():i32 (return g4-a))\n' > "$d/g4-back.nuc"
  w1_run g4-backward-ref "$d" "$d/g4-back.nuc" 42

  # 2. Cross-file, both import orders. This is §4.1 consequence 1 made visible:
  #    the good order links and returns 42, the reversed one is refused. Only a
  #    cross-FILE case can check that the note names the other file's path —
  #    a same-file fixture cannot tell a real lookup from an echo of its own.
  printf '(defn g4-xc ():i32 (return 40))\n(defvar g4-xbase:i32 (g4-xc))\n' > "$d/g4xa.nuc"
  printf '(defvar g4-xderived:i32 (+ g4-xbase 2))\n(defn g4-xget ():i32 (return g4-xderived))\n' > "$d/g4xb.nuc"
  printf '(import g4xa)\n(import g4xb)\n(defn main ():i32 (return (g4-xget)))\n' > "$d/g4-ok.nuc"
  printf '(import g4xb)\n(import g4xa)\n(defn main ():i32 (return (g4-xget)))\n' > "$d/g4-bad.nuc"
  w1_run g4-cross-file-order "$d" "$d/g4-ok.nuc" 42
  err="$(./build/nucleusc -I "$d" --emit-llvm "$d/g4-bad.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep -F "$d/g4xb.nuc:1: error: defvar: the initializer for 'g4-xderived' names global 'g4-xbase'" \
     && printf '%s' "$err" | qgrep -F "note: 'g4-xbase' is declared at $d/g4xa.nuc:2"; then
    echo "PASS  g4-cross-file-both-sites"
  else
    echo "FAIL  g4-cross-file-both-sites (the diagnostic must name both files at real lines)"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi

  # 3. `(addr-of g)` forward, on the RUN-TIME path — the decision this step had
  #    to make, asserted by dereferencing the pointer rather than by compiling.
  w1_run g4-addr-of-forward "$d" tests/fixtures/g4-addr-of-forward.nuc 7

  # 4. The KNOWN GAP, pinned by value: a forward read laundered through a call
  #    is not detected, so the global keeps its zero. Exit 10 is the gap; a
  #    future fix would make it 109 and fail here rather than pass quietly.
  w1_run g4-laundered-gap "$d" tests/fixtures/g4-laundered-call.nuc 10

  rm -rf "$d"
}

# What G-0 must NOT relax. The message it removes is a *false* one — a name that
# genuinely is not in the unit must still say so, W1c's unreachable-file note
# must still fire for a value (it is what makes "not defined anywhere" useful
# rather than merely true), and two files defining one global must still be
# rejected rather than becoming a silent last-wins.
run_g0_still_rejects() {
  local d err
  d="$(mktemp -d)"

  printf '(defn main ():i32 (return g0-absent-everywhere))\n' > "$d/g0-none.nuc"
  err="$(./build/nucleusc -I "$d" --emit-llvm "$d/g0-none.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep -F 'undefined: g0-absent-everywhere — not defined anywhere in this compilation unit' \
     && ! printf '%s' "$err" | qgrep 'note:'; then
    echo "PASS  g0-value-defined-nowhere"
  else
    echo "FAIL  g0-value-defined-nowhere"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi

  # W1c tier 2 for a VALUE: defined in a sibling file nothing imports.
  printf '(defconst G0-UNREACHED 5)\n' > "$d/g0-far.nuc"
  printf '(defn main ():i32 (return G0-UNREACHED))\n' > "$d/g0-farmain.nuc"
  err="$(./build/nucleusc -I "$d" --emit-llvm "$d/g0-farmain.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep ':0:'; then
    echo "FAIL  g0-value-unreachable-file (diagnostic reports line 0)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | qgrep -F 'undefined: G0-UNREACHED — not defined anywhere in this compilation unit' \
     && printf '%s' "$err" | qgrep -F "note: 'G0-UNREACHED' is defined in $d/g0-far.nuc, which no import in this unit reaches"; then
    echo "PASS  g0-value-unreachable-file"
  else
    echo "FAIL  g0-value-unreachable-file"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi

  # Two files, one global name — still rejected, and since Stage 15 B4 (R4) by
  # the compiler rather than by LLVM. Before B4 both `@g0-dupg = global` lines
  # were emitted and the IR parser said `redefinition of global '@g0-dupg'` with
  # no source location at all; `emit-defvar` now reads `Sym.defvar-state` and
  # names BOTH definitions. The verdict is what this test pins — the text moved
  # because the diagnostic got better, not because the rule changed.
  printf '(defvar g0-dupg:i32 1)\n' > "$d/g0-da.nuc"
  printf '(defvar g0-dupg:i32 2)\n' > "$d/g0-db.nuc"
  printf '(import g0-da)\n(import g0-db)\n(defn main ():i32 (return g0-dupg))\n' > "$d/g0-dm.nuc"
  err="$(./build/nucleusc -I "$d" -o "$d/g0-dm.bin" "$d/g0-dm.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep -F "redefinition of 'g0-dupg'" \
     && printf '%s' "$err" | qgrep -F "$d/g0-da.nuc:1" \
     && [ ! -x "$d/g0-dm.bin" ]; then
    echo "PASS  g0-duplicate-global-rejected"
  else
    echo "FAIL  g0-duplicate-global-rejected"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi

  # A value name and a function name still may not collide, in either order —
  # the prescan registers both, so the cross-kind guard fires whichever file is
  # emitted first.
  printf '(defvar g0-collide:i32 1)\n' > "$d/g0-ka.nuc"
  printf '(defn g0-collide ():i32 (return 2))\n' > "$d/g0-kb.nuc"
  printf '(import g0-ka)\n(import g0-kb)\n(defn main ():i32 (return 0))\n' > "$d/g0-km1.nuc"
  printf '(import g0-kb)\n(import g0-ka)\n(defn main ():i32 (return 0))\n' > "$d/g0-km2.nuc"
  # Stage 15 B5: the noun now depends on which definer is emitted first, because
  # the guard asks for the first binding whose kind is NOT the one being defined
  # rather than for the highest-priority binding (name-resolution.md §13.3).
  # order1 emits the `defvar` first and names the function; order2 emits the
  # `defn` first and names the value. Both still refuse, which is the property
  # this pair exists to pin.
  w1_reject_multi g0-value-fn-collision-order1 "$d" "$d/g0-km1.nuc" \
    "'g0-collide' already names a function"
  w1_reject_multi g0-value-fn-collision-order2 "$d" "$d/g0-km2.nuc" \
    "'g0-collide' already names a value"
  rm -rf "$d"
}

# Stage 13 L8: a public defn whose signature exposes a capturing-closure env
# type (__vfn_env_N) is not C-callable, so --emit-cheader OMITS its prototype
# (writing a comment in its place) and the compiler WARNS at the definition. A
# plain function-pointer-compatible defn is emitted normally. The fixture
# declares a __vfn_env_0 struct by hand to stand in for a synthesized env (real
# envs are created post-prescan, so they cannot appear in source signatures).
# Stage 15 W3a: the opaque-misuse diagnostic names the C declaration's own
# header and line ("declared at ./tests/fixtures/cheader-opaque.h:11"). The path
# is host-dependent for a system header, so run_reject_at pins only the message
# prefix; this pins the provenance itself — a nonzero line against the fixture
# header. Recovered from clang -E's `# N "file"` linemarkers, so a regression in
# that tracking shows up here as `:0` rather than silently degrading.
run_w3a_opaque_provenance() {
  local err
  err="$(./build/nucleusc --emit-llvm tests/fixtures/w3a-opaque-sizeof.nuc 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep -E 'declared at [^ ]*tests/fixtures/cheader-opaque\.h:11;'; then
    echo "PASS  w3a-opaque-provenance"
  else
    echo "FAIL  w3a-opaque-provenance"
    echo "    expected: declared at <...>/tests/fixtures/cheader-opaque.h:11;"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi
}

# Stage 15 W3a: SDL2/SDL_mixer.h declares `typedef struct Mix_Music Mix_Music;`
# (opaque — no body in any header) and `typedef struct Mix_Chunk { … } Mix_Chunk;`
# (fully defined) in the same file, so one import exercises both shapes.
# Compile-only: linking would need -lSDL2_mixer and run-tests.sh has no
# per-test link-flag mechanism. SKIPs cleanly where SDL2 headers are absent.
#
# Checks the emitted IR, not just exit 0: the defined struct must get a real
# layout AND a real GEP, and the opaque one must NEVER appear as an LLVM
# aggregate type (it may only ever be a `ptr`).
run_w3a_sdl_mixer() {
  local hdr ir err
  hdr=""
  for d in /usr/include /usr/local/include; do
    [ -f "$d/SDL2/SDL_mixer.h" ] && hdr="$d/SDL2/SDL_mixer.h"
  done
  if [ -z "$hdr" ]; then
    echo "PASS  w3a-sdl-mixer (SKIP: SDL2/SDL_mixer.h not installed)"
    return 0
  fi
  ir="$(mktemp)"
  err="$(./build/nucleusc --emit-llvm tests/fixtures/w3a-sdl-mixer.nuc 2>&1 >"$ir" || true)"
  if [ -n "$err" ]; then
    echo "FAIL  w3a-sdl-mixer (compile error)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif ! qgrep '^%Mix_Chunk = type' "$ir"; then
    echo "FAIL  w3a-sdl-mixer (defined Mix_Chunk has no LLVM layout)"
  elif ! qgrep '^%Mix_Chunk = type { i32, ptr, i32, i8 }$' "$ir"; then
    # W3c: `alen` (Uint32) and `volume` (Uint8) are typedefs of builtin
    # integers. Before the typedef chain was followed they were `ptr`, giving
    # `{ i32, ptr, ptr, ptr }` — a wrong layout, silently.
    echo "FAIL  w3a-sdl-mixer (Mix_Chunk field types did not resolve through their typedefs)"
    grep '^%Mix_Chunk = type' "$ir" | sed 's/^/    got: /'
  elif ! qgrep 'getelementptr inbounds %Mix_Chunk' "$ir"; then
    echo "FAIL  w3a-sdl-mixer (Mix_Chunk field access not emitted)"
  elif ! qgrep 'call void @Mix_FreeMusic(ptr ' "$ir"; then
    echo "FAIL  w3a-sdl-mixer (opaque handle not passed as a plain pointer)"
  elif qgrep '%Mix_Music' "$ir"; then
    echo "FAIL  w3a-sdl-mixer (opaque Mix_Music leaked into IR as an aggregate type)"
  else
    echo "PASS  w3a-sdl-mixer"
  fi
  rm -f "$ir"
}

# Stage 15 W3b: the C type-qualifier matrix (cheader.md §1.5).
#
# A qualifier is legal anywhere in a declaration-specifier sequence and after
# every `*`; the importer used to accept only the LEADING position, so an "east"
# qualifier terminated the type and its token was eaten as the parameter NAME,
# leaving `*p` to start a phantom second parameter that defaulted to `ptr`. Only
# the `void` spelling produced IR LLVM rejects (`declare void @f(void, ptr)`);
# `int const *p` produced the far more dangerous `declare void @f(i32, ptr)` —
# wrong arity, wrong ABI, silently accepted at every stage. No validity gate can
# catch that one, which is why the parse fix is the primary deliverable and this
# test asserts the exact emitted signature rather than merely "it compiled".
#
# Both halves of the matrix are pinned — the previously broken spellings AND the
# previously correct ones — so a future "fix" cannot trade one for the other.
run_w3b_quals() {
  local ir err expected got line name bad
  ir="$(mktemp)"
  err="$(./build/nucleusc --emit-llvm tests/fixtures/w3b-quals.nuc 2>&1 >"$ir" || true)"
  if [ -n "$err" ]; then
    echo "FAIL  w3b-quals (compile error)"
    printf '%s\n' "$err" | sed 's/^/    /'
    rm -f "$ir"
    return 0
  fi
  # The emitted IR must also PARSE: --emit-llvm never reads back what it writes,
  # so exit 0 above proves nothing about validity (this is exactly how the
  # `(void, ptr)` shape survived to the end of a build).
  if ! llvm-as "$ir" -o /dev/null 2>/dev/null; then
    echo "FAIL  w3b-quals (emitted IR does not parse)"
    rm -f "$ir"
    return 0
  fi
  bad=0
  # name<TAB>expected declare line
  while IFS='|' read -r name expected; do
    [ -z "$name" ] && continue
    got="$(grep -E "^declare [^@]*@$name\(" "$ir" || true)"
    if [ "$got" != "$expected" ]; then
      echo "FAIL  w3b-quals ($name)"
      echo "    expected: $expected"
      echo "    got:      ${got:-<no declare emitted>}"
      bad=1
    fi
  done <<'EOF'
w3b_void_const|declare void @w3b_void_const(ptr)
w3b_int_const|declare void @w3b_int_const(ptr)
w3b_int_volatile|declare void @w3b_int_volatile(ptr)
w3b_struct_const|declare void @w3b_struct_const(ptr)
w3b_ulong_const|declare void @w3b_ulong_const(ptr)
w3b_long_const|declare void @w3b_long_const(ptr)
w3b_double_const|declare void @w3b_double_const(ptr)
w3b_int_const_val|declare void @w3b_int_const_val(i32)
w3b_atomic|declare void @w3b_atomic(ptr)
w3b_const_void|declare void @w3b_const_void(ptr)
w3b_char_star_const|declare void @w3b_char_star_const(ptr)
w3b_const_char_star_const|declare void @w3b_const_char_star_const(ptr)
w3b_volatile_int|declare void @w3b_volatile_int(ptr)
w3b_int_restrict|declare void @w3b_int_restrict(ptr)
w3b_no_params|declare void @w3b_no_params()
w3b_variadic|declare void @w3b_variadic(ptr, ...)
w3b_east_restrict|declare void @w3b_east_restrict(ptr)
w3b_ret_int|declare i32 @w3b_ret_int(ptr)
w3b_ret_east|declare ptr @w3b_ret_east()
EOF
  [ "$bad" = 0 ] && echo "PASS  w3b-quals"
  rm -f "$ir"
}

# Stage 15 W3b: the validity gate — a declaration the importer recognizes as a
# function but cannot faithfully describe is SKIPPED with a located warning
# rather than emitted as IR for the LLVM parser to choke on much later.
#
# Asserts all three halves: the representable declaration survives, the three
# unrepresentable ones are absent from the IR, and each warning names the C
# header and the declaration's own line (not the .nuc file that imported it).
run_w3b_skip() {
  local ir err bad line
  ir="$(mktemp)"
  err="$(./build/nucleusc --emit-llvm tests/fixtures/w3b-skip.nuc 2>&1 >"$ir" || true)"
  bad=0
  if ! qgrep '^declare void @w3b_keep(ptr)$' "$ir"; then
    echo "FAIL  w3b-skip (representable declaration was not imported)"
    bad=1
  fi
  for sym in w3b_skip_byval w3b_skip_void w3b_skip_many; do
    if qgrep "@$sym" "$ir"; then
      echo "FAIL  w3b-skip ($sym reached the IR instead of being skipped)"
      bad=1
    fi
  done
  # `<header>:<line>:` — the line is the declaration's own, recovered from
  # clang -E's linemarkers, so an off-by-N in that tracking fails here.
  while IFS='|' read -r line want; do
    [ -z "$line" ] && continue
    if ! printf '%s' "$err" | qgrep -F "w3b-skip.h:$line: warning: skipping C declaration $want"; then
      echo "FAIL  w3b-skip (missing warning at line $line: $want)"
      printf '%s\n' "$err" | sed 's/^/    got: /'
      bad=1
    fi
  done <<'EOF'
20|'w3b_skip_byval': a by-value 'W3bHidden' with no known layout
24|'w3b_skip_void': a 'void' parameter
29|'w3b_skip_many': more than 32 parameters
EOF
  # What survived must still be valid IR.
  if ! llvm-as "$ir" -o /dev/null 2>/dev/null; then
    echo "FAIL  w3b-skip (emitted IR does not parse)"
    bad=1
  fi
  [ "$bad" = 0 ] && echo "PASS  w3b-skip"
  rm -f "$ir"
}

# Stage 15 W3b: the §1.5 accept criterion. `(import-use "SDL2/SDL.h")` reaches
# the x86 intrinsics headers transitively, whose `void _mm_clflush(void const *)`
# imported as `declare void @_mm_clflush(void, ptr)` and killed the entire
# compilation at `failed to parse generated IR`.
#
# Built with `-o` — a REAL link, which is the only thing that parses the module.
# The fixture calls no SDL function, so no -lSDL2 is needed (run-tests.sh has no
# per-test link-flag mechanism). SKIPs cleanly where SDL2 is not installed.
run_w3b_sdl() {
  local hdr out err ir
  hdr=""
  for d in /usr/include /usr/local/include; do
    [ -f "$d/SDL2/SDL.h" ] && hdr="$d/SDL2/SDL.h"
  done
  if [ -z "$hdr" ]; then
    echo "PASS  w3b-sdl (SKIP: SDL2/SDL.h not installed)"
    return 0
  fi
  out="$(mktemp -u)"
  err="$(./build/nucleusc tests/fixtures/w3b-sdl.nuc -o "$out" 2>&1 || true)"
  if [ ! -x "$out" ]; then
    echo "FAIL  w3b-sdl (compile/link failed)"
    printf '%s\n' "$err" | sed 's/^/    /'
    rm -f "$out"
    return 0
  fi
  if [ "$("$out" 2>&1)" != "w3b-sdl ok" ]; then
    echo "FAIL  w3b-sdl (linked binary did not run)"
    rm -f "$out"
    return 0
  fi
  # The intrinsic that used to produce the invalid `(void, ptr)` must now be a
  # single pointer parameter — pinned so the gate cannot silently "fix" this by
  # skipping the declaration instead of parsing it.
  ir="$(mktemp)"
  ./build/nucleusc --emit-llvm tests/fixtures/w3b-sdl.nuc >"$ir" 2>/dev/null || true
  if ! qgrep '^declare void @_mm_clflush(ptr)$' "$ir"; then
    echo "FAIL  w3b-sdl (_mm_clflush not imported as a single pointer parameter)"
    grep -n '_mm_clflush' "$ir" | sed 's/^/    got: /'
  elif [ -n "$err" ]; then
    echo "FAIL  w3b-sdl (unexpected diagnostics)"
    printf '%s\n' "$err" | sed 's/^/    /'
  else
    echo "PASS  w3b-sdl"
  fi
  rm -f "$out" "$ir"
}

# Stage 15 W3c: the C typedef matrix (cheader.md §1.4).
#
# `c-parse-type` used to resolve any name it did not recognize as a builtin to
# `ptr`, so EVERY scalar typedef degraded — `off_t`, SDL's `Uint8`/`Uint32`, even
# a one-level `typedef int myint;`. Only `size_t`/`ssize_t` worked, and only
# because they are hardcoded. The wrong rows all compiled cleanly, so this
# asserts the exact emitted `declare` line, never "it compiled".
run_w3c_typedef() {
  local ir err bad name expected got
  ir="$(mktemp)"
  err="$(./build/nucleusc --emit-llvm tests/fixtures/w3c-typedef.nuc 2>&1 >"$ir" || true)"
  if [ -n "$err" ]; then
    echo "FAIL  w3c-typedef (unexpected diagnostics)"
    printf '%s\n' "$err" | sed 's/^/    /'
    rm -f "$ir"
    return 0
  fi
  if ! llvm-as "$ir" -o /dev/null 2>/dev/null; then
    echo "FAIL  w3c-typedef (emitted IR does not parse)"
    rm -f "$ir"
    return 0
  fi
  bad=0
  while IFS='|' read -r name expected; do
    [ -z "$name" ] && continue
    got="$(grep -E "^declare [^@]*@$name\(" "$ir" || true)"
    if [ "$got" != "$expected" ]; then
      echo "FAIL  w3c-typedef ($name)"
      echo "    expected: $expected"
      echo "    got:      ${got:-<no declare emitted>}"
      bad=1
    fi
  done <<'EOF'
w3c_f_off|declare i64 @w3c_f_off(i32)
w3c_f_off3|declare i64 @w3c_f_off3()
w3c_f_u8|declare i8 @w3c_f_u8()
w3c_f_u32|declare i32 @w3c_f_u32()
w3c_f_i16|declare i16 @w3c_f_i16()
w3c_f_int|declare i32 @w3c_f_int()
w3c_f_f32|declare float @w3c_f_f32()
w3c_f_f64|declare double @w3c_f_f64()
w3c_f_u64|declare i64 @w3c_f_u64()
w3c_f_size|declare i64 @w3c_f_size()
w3c_f_takes|declare i32 @w3c_f_takes(i64, i8, i32, i16)
w3c_f_str|declare ptr @w3c_f_str(ptr, ptr)
w3c_f_handler|declare void @w3c_f_handler(ptr, ptr)
w3c_f_enum|declare i32 @w3c_f_enum(i32)
w3c_f_opaque|declare ptr @w3c_f_opaque(ptr)
w3c_f_pairp|declare i32 @w3c_f_pairp(ptr)
w3c_f_noextern|declare ptr @w3c_f_noextern(i32)
w3c_f_noextern_u|declare ptr @w3c_f_noextern_u(i32)
w3c_f_vec|declare i32 @w3c_f_vec(ptr)
EOF
  # A by-value use of an OPAQUE tag is still unrepresentable and still skipped.
  if qgrep '@w3c_f_opaqv' "$ir"; then
    echo "FAIL  w3c-typedef (by-value opaque parameter reached the IR)"
    bad=1
  fi
  # ... and a *use* of the skipped name says why, naming the header and line —
  # this is where the skip is reported, instead of a warning on every build.
  got="$(printf '(import-use "./tests/fixtures/w3c-typedef.h")\n(defn main ():i32 (return (w3c_f_opaqv null)))\n' > "$ir.use.nuc"; ./build/nucleusc --emit-llvm "$ir.use.nuc" 2>&1 >/dev/null || true)"
  if ! printf '%s' "$got" | qgrep "w3c_f_opaqv' — its C header declaration was skipped (.*w3c-typedef.h:"; then
    echo "FAIL  w3c-typedef (use of a skipped declaration was not diagnosed)"
    printf '%s\n' "$got" | sed 's/^/    got: /'
    bad=1
  fi
  # Struct FIELD types resolve through their typedefs too — the shape W3a
  # recorded as newly observed (Mix_Chunk.volume, a Uint8, typed as ptr).
  if ! qgrep '^%w3c_fields = type { i8, i32, i64, ptr }$' "$ir"; then
    echo "FAIL  w3c-typedef (struct field types did not resolve through typedefs)"
    grep '^%w3c_fields = type' "$ir" | sed 's/^/    got: /'
    bad=1
  fi
  [ "$bad" = 0 ] && echo "PASS  w3c-typedef"
  rm -f "$ir" "$ir.use.nuc"
}

# Stage 15 W3c: declaration precedence (cheader.md §1.4).
#
# An explicit `(declare …)` wins over a header-derived declaration of the same
# function REGARDLESS OF ORDER, and a signature mismatch warns naming both
# sources. Before the rule, both orders were silent and disagreed: the one that
# came first won, so `(import-use "unistd.h")` above a hand-written `lseek`
# quietly replaced the author's correct declaration — the failure §1.4 cost a
# debugging session over.
#
# Both orders are asserted, plus the case where the name is USED between the
# import and the declare (which is why the header's copy cannot simply be
# dropped and the explicit one left to emit at its own position).
run_w3c_precedence() {
  local ir err bad n
  bad=0
  ir="$(mktemp)"
  for n in first second; do
    err="$(./build/nucleusc --emit-llvm "tests/fixtures/w3c-prec-$n.nuc" 2>&1 >"$ir" || true)"
    # Exactly one declaration reaches the IR — LLVM rejects a second `declare`
    # for the same symbol even when the two agree.
    if [ "$(grep -c '^declare .*@lseek(' "$ir")" != "1" ]; then
      echo "FAIL  w3c-precedence ($n: expected exactly one lseek declaration)"
      grep -n '@lseek' "$ir" | sed 's/^/    got: /'
      bad=1
    fi
    # ...and it is the author's, not the header's (i32 whence).
    if ! qgrep '^declare i64 @lseek(i32, i64, i64)$' "$ir"; then
      echo "FAIL  w3c-precedence ($n: the header declaration won)"
      grep -n '@lseek' "$ir" | sed 's/^/    got: /'
      bad=1
    fi
    # The conflict warns, blamed on the .nuc declaration and naming the header.
    if ! printf '%s' "$err" | qgrep "w3c-prec-$n.nuc:.*declaration of 'lseek' as i64 (i32, i64, i64) conflicts with .*unistd.h:.*declares it as i64 (i32, i64, i32); the explicit declaration wins"; then
      echo "FAIL  w3c-precedence ($n: conflict not diagnosed naming both sources)"
      printf '%s\n' "$err" | sed 's/^/    got: /'
      bad=1
    fi
    if ! llvm-as "$ir" -o /dev/null 2>/dev/null; then
      echo "FAIL  w3c-precedence ($n: emitted IR does not parse)"
      bad=1
    fi
  done
  # A use BETWEEN the import and the declare still resolves, against the
  # explicit signature.
  err="$(./build/nucleusc --emit-llvm tests/fixtures/w3c-prec-use.nuc 2>&1 >"$ir" || true)"
  if [ "$(grep -c '^declare .*@strchr(' "$ir")" != "1" ] \
     || ! qgrep '^declare ptr @strchr(ptr, i64)$' "$ir"; then
    echo "FAIL  w3c-precedence (use-before-declare: wrong or duplicated strchr declaration)"
    grep -n '^declare .*@strchr(' "$ir" | sed 's/^/    got: /'
    bad=1
  fi
  if ! qgrep -E 'call ptr @strchr\(ptr [^,]+, i64 ' "$ir"; then
    echo "FAIL  w3c-precedence (use-before-declare: call did not resolve to the explicit signature)"
    bad=1
  fi
  if ! llvm-as "$ir" -o /dev/null 2>/dev/null; then
    echo "FAIL  w3c-precedence (use-before-declare: emitted IR does not parse)"
    bad=1
  fi
  [ "$bad" = 0 ] && echo "PASS  w3c-precedence"
  rm -f "$ir"
}

# Stage 15 W3c fallout: a `declare` parameter list's UNNAMED spelling carries
# types. Every written type was ignored and emitted as `i32`, so the bare list
# was correct exactly when the signature was all-`i32` — including, at the time,
# the compiler's own `(declare repl_print_f64 (ptr):void)`, which declared an
# `i32` parameter against a C shim taking a pointer (shim retired 2026-08-30).
#
# The pairs in the fixture are the same signature written both ways, so the
# assertion is that the two spellings AGREE; a default cannot satisfy both sides
# of a pair whose named half is already correct.
run_w3c_declare_params() {
  local ir err bad name expected got
  ir="$(mktemp)"
  err="$(./build/nucleusc --emit-llvm tests/fixtures/w3c-declare-params.nuc 2>&1 >"$ir" || true)"
  if [ -n "$err" ]; then
    echo "FAIL  w3c-declare-params (unexpected diagnostics)"
    printf '%s\n' "$err" | sed 's/^/    /'
    rm -f "$ir"
    return 0
  fi
  if ! llvm-as "$ir" -o /dev/null 2>/dev/null; then
    echo "FAIL  w3c-declare-params (emitted IR does not parse)"
    rm -f "$ir"
    return 0
  fi
  bad=0
  while IFS='|' read -r name expected; do
    [ -z "$name" ] && continue
    got="$(grep -E "^declare [^@]*@$name\(" "$ir" || true)"
    if [ "$got" != "$expected" ]; then
      echo "FAIL  w3c-declare-params ($name)"
      echo "    expected: $expected"
      echo "    got:      ${got:-<no declare emitted>}"
      bad=1
    fi
  done <<'EOF'
w3d_bare_1|declare i64 @w3d_bare_1(i64)
w3d_named_1|declare i64 @w3d_named_1(i64)
w3d_bare_2|declare i64 @w3d_bare_2(i32, i64)
w3d_named_2|declare i64 @w3d_named_2(i32, i64)
w3d_bare_3|declare i64 @w3d_bare_3(i64, i32)
w3d_named_3|declare i64 @w3d_named_3(i64, i32)
w3d_bare_4|declare void @w3d_bare_4(i8, i8, i16, i16, i32, i64)
w3d_named_4|declare void @w3d_named_4(i8, i8, i16, i16, i32, i64)
w3d_bare_5|declare void @w3d_bare_5(double, float)
w3d_named_5|declare void @w3d_named_5(double, float)
w3d_bare_6|declare i32 @w3d_bare_6(i64, i64, i1, i32)
w3d_named_6|declare i32 @w3d_named_6(i64, i64, i1, i32)
w3d_bare_7|declare i64 @w3d_bare_7(ptr, ptr, i64)
w3d_named_7|declare i64 @w3d_named_7(ptr, ptr, i64)
w3d_mixed|declare void @w3d_mixed(i64, i32, double)
w3d_kw|declare i64 @w3d_kw(i64, double)
w3d_annot|declare void @w3d_annot(i64, i64)
w3d_ptr_named|declare void @w3d_ptr_named(ptr)
EOF
  # A by-value struct in unnamed position takes the platform C ABI, exactly like
  # a named one: {i32, i64} is two INTEGER eightbytes, so both spellings coerce
  # to (i64, i64) — never a raw %W3dPair and never the i32 default.
  got="$(grep -E '^declare void @w3d_bare_8\(' "$ir" || true)"
  if [ "$got" != "declare void @w3d_bare_8(i64, i64, i32)" ] \
     || [ "$(grep -c '^declare void @w3d_named_8(i64, i64, i32)$' "$ir")" != "1" ]; then
    echo "FAIL  w3c-declare-params (by-value struct parameter ABI)"
    grep -E '^declare void @w3d_(bare|named)_8\(' "$ir" | sed 's/^/    got: /'
    bad=1
  fi
  [ "$bad" = 0 ] && echo "PASS  w3c-declare-params"
  rm -f "$ir"
}

# The precedence interaction the parameter defect broke: a bare-list `declare`
# that AGREES with the C header must not warn (it rendered as all-`i32`, so it
# "conflicted" with every non-i32 header signature and the wrong one won), while
# one that genuinely differs must still warn and still win.
run_w3c_declare_header() {
  local ir err bad
  bad=0
  ir="$(mktemp)"

  err="$(./build/nucleusc --emit-llvm tests/fixtures/w3c-declare-header-match.nuc 2>&1 >"$ir" || true)"
  if [ -n "$err" ]; then
    echo "FAIL  w3c-declare-header (a declaration matching the header still diagnosed)"
    printf '%s\n' "$err" | sed 's/^/    got: /'
    bad=1
  fi
  if [ "$(grep -c '^declare .*@lseek(' "$ir")" != "1" ] \
     || ! qgrep '^declare i64 @lseek(i32, i64, i32)$' "$ir"; then
    echo "FAIL  w3c-declare-header (match: wrong or duplicated lseek declaration)"
    grep -n '^declare .*@lseek(' "$ir" | sed 's/^/    got: /'
    bad=1
  fi
  if ! llvm-as "$ir" -o /dev/null 2>/dev/null; then
    echo "FAIL  w3c-declare-header (match: emitted IR does not parse)"
    bad=1
  fi

  err="$(./build/nucleusc --emit-llvm tests/fixtures/w3c-declare-header-conflict.nuc 2>&1 >"$ir" || true)"
  if ! printf '%s' "$err" | qgrep "w3c-declare-header-conflict.nuc:.*declaration of 'lseek' as i64 (i32, i64, i64) conflicts with .*unistd.h:.*declares it as i64 (i32, i64, i32); the explicit declaration wins"; then
    echo "FAIL  w3c-declare-header (conflict: a real mismatch was not diagnosed)"
    printf '%s\n' "$err" | sed 's/^/    got: /'
    bad=1
  fi
  if [ "$(grep -c '^declare .*@lseek(' "$ir")" != "1" ] \
     || ! qgrep '^declare i64 @lseek(i32, i64, i64)$' "$ir"; then
    echo "FAIL  w3c-declare-header (conflict: the explicit declaration did not win)"
    grep -n '^declare .*@lseek(' "$ir" | sed 's/^/    got: /'
    bad=1
  fi

  [ "$bad" = 0 ] && echo "PASS  w3c-declare-header"
  rm -f "$ir"
}

run_closure_cheader() {
  local ch_dir ch_warn
  ch_dir="$(mktemp -d)"
  ./build/nucleusc --emit-cheader tests/fixtures/closure-cheader.nuc > "$ch_dir/lib.h" 2>/dev/null || true
  ch_warn="$(./build/nucleusc --emit-llvm tests/fixtures/closure-cheader.nuc 2>&1 >/dev/null || true)"

  # 1. closure-typed prototype is OMITTED, with the explanatory comment in place.
  if qgrep 'apply-closure: exposes a closure or type-erased box type; not C-callable, omitted' "$ch_dir/lib.h" \
     && ! qgrep 'apply-closure(' "$ch_dir/lib.h"; then
    echo "PASS  l8-cheader-omits-closure"
  else
    echo "FAIL  l8-cheader-omits-closure"
  fi

  # 2. the plain fn-pointer defn IS emitted to the header. W9 item 4: under its
  # sanitized C name, with the asm label that binds it back to `@plain-fn`.
  if qgrep -xF 'int32_t plain_fn(int32_t x, int32_t y) asm("plain-fn");' "$ch_dir/lib.h"; then
    echo "PASS  l8-cheader-emits-fnptr"
  else
    echo "FAIL  l8-cheader-emits-fnptr"
  fi

  # 3. the definition site warns on stderr.
  if printf '%s' "$ch_warn" | qgrep "warning: 'apply-closure' exposes a closure or type-erased box type"; then
    echo "PASS  l8-cheader-warns"
  else
    echo "FAIL  l8-cheader-warns"
  fi
  rm -rf "$ch_dir"
}

# Stage 13 — C header exclusion of BoxedFn/dyn-typed public defns.
# --emit-cheader omits prototypes whose signatures mention (BoxedFn …) or (dyn P)
# (fat pointers with Nucleus-side semantics; no faithful C spelling), emitting a
# comment in place and warning at the definition site. Plain fn-pointer defns are
# still emitted normally.
run_box_cheader() {
  local bch_dir bch_warn
  bch_dir="$(mktemp -d)"
  ./build/nucleusc --emit-cheader tests/fixtures/box-cheader.nuc > "$bch_dir/lib.h" 2>/dev/null || true
  bch_warn="$(./build/nucleusc --emit-llvm tests/fixtures/box-cheader.nuc 2>&1 >/dev/null || true)"

  # 4. BoxedFn-typed prototype is OMITTED, with the explanatory comment in place.
  if qgrep 'make-boxed: exposes a closure or type-erased box type; not C-callable, omitted' "$bch_dir/lib.h" \
     && ! qgrep 'make-boxed(' "$bch_dir/lib.h"; then
    echo "PASS  l13-cheader-omits-boxedfn"
  else
    echo "FAIL  l13-cheader-omits-boxedfn"
  fi

  # 5. dyn-typed prototype is OMITTED, with the explanatory comment in place.
  if qgrep 'use-dyn: exposes a closure or type-erased box type; not C-callable, omitted' "$bch_dir/lib.h" \
     && ! qgrep 'use-dyn(' "$bch_dir/lib.h"; then
    echo "PASS  l13-cheader-omits-dyn"
  else
    echo "FAIL  l13-cheader-omits-dyn"
  fi

  # 6. the plain fn-pointer defn IS emitted to the header. W9 item 4: under its
  # sanitized C name, with the asm label that binds it back to `@plain-fn`.
  if qgrep -xF 'int32_t plain_fn(int32_t x, int32_t y) asm("plain-fn");' "$bch_dir/lib.h"; then
    echo "PASS  l13-cheader-emits-fnptr"
  else
    echo "FAIL  l13-cheader-emits-fnptr"
  fi

  # 7. the definition site warns on stderr (at least one box-typed defn fires).
  if printf '%s' "$bch_warn" | qgrep "warning:.*exposes a closure or type-erased box type"; then
    echo "PASS  l13-cheader-warns"
  else
    echo "FAIL  l13-cheader-warns"
  fi
  rm -rf "$bch_dir"
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

# --- Stage 15 B0: the name-resolution cells that are already CORRECT ----------
# design/stage15-stress-test/name-resolution.md §9 "B0".
#
# The behavioural matrix proper — 43 cells, most of them recording DEFECTS —
# lives in tests/resolution-matrix.sh against
# tests/expected/resolution-matrix.baseline. That harness is a *recorder*: B1/B2
# diff against it to see which cells moved. It is deliberately not run from here,
# because a recorded defect changing is the expected outcome of the next steps,
# not a test failure.
#
# What follows is the opposite half: the handful of spellings that resolve
# correctly today and that B1/B2 must preserve. Each compiles, LINKS and RUNS —
# an exit-0 compile would not catch a call routed to the wrong symbol, which is
# the failure mode a resolver rewrite actually risks.
#
# The third member of the set, the `export` facade path (examples/export-test.nuc
# → lib/nsgfacade.nuc → lib/nsgeom.nuc, reaching `geom/area` through a *third*
# name `g/area`), is already dispatched by the examples/*.nuc loop below against
# tests/expected/export-test.out, so it is not duplicated here.

# `import-use` flattens into the unqualified space: a bare function, global and
# type from the imported file all resolve. §2's whole matrix is about the
# *prefixed* import; this is the path 123 of the tree's 124 imports take, so it
# is the one that must not move.
run_b0_import_use_flatten() {
  local d
  d="$(mktemp -d)"
  cat > "$d/b0-uselib.nuc" <<'EOF'
(defstruct B0Point x:i32)
(defvar b0-base:i32 40)
(defn b0-add (a:i32 b:i32):i32 (return (+ a b)))
EOF
  cat > "$d/b0-use.nuc" <<'EOF'
(import-use b0-uselib)
(defn main ():i32
  (let (p:(ref B0Point) (B0Point 2))
    (return (b0-add b0-base (_get p 'x)))))
EOF
  w1_run b0-import-use-flatten "$d" "$d/b0-use.nuc" 42
  rm -rf "$d"
}

# `import-prefixed` resolves `prefix/fn` for a solitary `defn` — the ONE cell of
# §2's `zx/` column that is `ok` today, and the one every later step has to keep.
# Two shapes, because they reach the alias by different routes: a library with an
# explicit `(ns …)` (the emitted symbol is namespace-mangled) and one without
# (the symbol is bare, and the alias is the only thing the prefix contributes).
run_b0_import_prefixed_fn() {
  local d
  d="$(mktemp -d)"
  cat > "$d/b0-nslib.nuc" <<'EOF'
(ns b0ns)
(defn b0-triple (x:i32):i32 (return (* 3 x)))
EOF
  cat > "$d/b0-pfx-ns.nuc" <<'EOF'
(import-prefixed b0-nslib zp)
(defn main ():i32 (return (zp/b0-triple 14)))
EOF
  w1_run b0-prefixed-fn-namespaced "$d" "$d/b0-pfx-ns.nuc" 42

  cat > "$d/b0-plainlib.nuc" <<'EOF'
(defn b0-double (x:i32):i32 (return (* 2 x)))
EOF
  cat > "$d/b0-pfx-plain.nuc" <<'EOF'
(import-prefixed b0-plainlib q)
(defn main ():i32 (return (q/b0-double 21)))
EOF
  w1_run b0-prefixed-fn-plain "$d" "$d/b0-pfx-plain.nuc" 42
  rm -rf "$d"
}

# --- Stage 15 B1: an import prefix is FILE-scoped ------------------------------
# design/stage15-stress-test/name-resolution.md §2.4, §5.2 B1.
#
# Before B1 a prefix was unit-global: `inject-import-aliases` wrote its
# `prefix/name` key into the one global scope, and `qualify-name` splits on the
# first interior slash, so that key was the same string in every namespace and in
# every file. A prefix declared while compiling file A therefore resolved from
# file B, which never declared it — the `xfile-prefix-leak` row of the recorded
# matrix, which B1 flipped from `ok` to `err`.
#
# Both halves are pinned. The middle file, which DOES declare the prefix, must
# still compile and run: the fix scopes the prefix, it does not delete it. And
# the consumer, which does not, must be rejected by a diagnostic that says the
# qualifier is out of scope — the assertion that carries the weight, because the
# message it replaces is W1c's "not defined anywhere in this compilation unit",
# which for a name that IS in the unit and IS reachable is simply false.
run_b1_prefix_file_scope() {
  local d err
  d="$(mktemp -d)"
  cat > "$d/b1-lib.nuc" <<'EOF'
(ns b1ns)
(defn b1-inc (x:i32):i32 (return (+ x 1)))
EOF
  cat > "$d/b1-mid.nuc" <<'EOF'
(import-prefixed b1-lib zx)
(defn b1-mid-call (x:i32):i32 (return (zx/b1-inc x)))
EOF
  cat > "$d/b1-ok.nuc" <<'EOF'
(import-use b1-mid)
(defn main ():i32 (return (b1-mid-call 41)))
EOF
  w1_run b1-prefix-in-declaring-file "$d" "$d/b1-ok.nuc" 42

  cat > "$d/b1-leak.nuc" <<'EOF'
(import-use b1-mid)
(defn main ():i32 (return (zx/b1-inc 41)))
EOF
  # B2b: B1's own head ("… is not an import prefix in this file") folded into
  # the one `qualifier-scope-message` head, because after B2b a refused
  # qualifier may be a prefix OR a namespace and the gate can no longer be two
  # functions (§9.2's "the two halves now disagree"). The prefix-specific
  # sentence — the one that names the file that DOES bind it — survives as the
  # note's first tier, which is the half that carries the fix.
  err="$(./build/nucleusc -I "$d" --emit-llvm "$d/b1-leak.nuc" 2>&1 >/dev/null || true)"
  if ! printf '%s' "$err" | qgrep -F "unknown: zx/b1-inc — 'zx' is not in scope in this file"; then
    echo "FAIL  b1-prefix-not-visible-cross-file (wrong or missing diagnostic)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif ! printf '%s' "$err" | qgrep -F "note: an import prefix is file-scoped:"; then
    echo "FAIL  b1-prefix-not-visible-cross-file (missing the file-scope note)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | qgrep -F "not defined anywhere in this compilation unit"; then
    echo "FAIL  b1-prefix-not-visible-cross-file (degraded to the reachability message)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | qgrep ':0:'; then
    echo "FAIL  b1-prefix-not-visible-cross-file (diagnostic reports line 0)"
    printf '%s\n' "$err" | sed 's/^/    /'
  else
    echo "PASS  b1-prefix-not-visible-cross-file"
  fi
  rm -rf "$d"
}

# Stage 15 B2a: the rejection of an out-of-scope namespace qualifier must be a
# SCOPE diagnostic. `run_reject_at` above already pins the head and the line; the
# assertion that carries the weight is the note — without it the message says a
# protocol that IS declared and IS reachable is "unknown", full stop, which sends
# the reader looking for a missing definition instead of a wrong spelling. The
# third check is the same anti-degradation guard B1 uses.
run_b2a_scope_diagnostic() {
  local err
  err="$(./build/nucleusc --emit-llvm tests/fixtures/b2a-ns-not-in-scope.nuc 2>&1 >/dev/null || true)"
  if ! printf '%s' "$err" | qgrep -F "note: 'dp' is not in scope in this file"; then
    echo "FAIL  b2a-scope-diagnostic (missing the out-of-scope note)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif ! printf '%s' "$err" | qgrep -F "In scope here: dpx."; then
    echo "FAIL  b2a-scope-diagnostic (note does not list the qualifiers in scope)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | qgrep -F "not defined anywhere in this compilation unit"; then
    echo "FAIL  b2a-scope-diagnostic (degraded to the reachability message)"
    printf '%s\n' "$err" | sed 's/^/    /'
  else
    echo "PASS  b2a-scope-diagnostic"
  fi
}

# Stage 15 B2a, §8.3 row 1: `import-use` flattens a namespaced library AND binds
# the namespace's own name as a qualifier (R2's escape hatch — the remedy for a
# collision must not be "change how you imported"). Both spellings are new: before
# B2a a bare `Describe` reached no protocol at all from `user` (there is no bare
# `Describe` registered), and `dp/Describe` resolved only because nothing checked
# the qualifier against anything. The pair is run, not just compiled, because the
# thing being asserted is that both spellings land on ONE protocol identity — the
# box dispatches `dp`'s `describe` on a `user` type that conformed under the bare
# spelling.
run_b2a_import_use_binds_namespace() {
  local d
  d="$(mktemp -d)"
  cat > "$d/b2a-flat.nuc" <<'EOF'
(import-use allocator)
(import-use nsdescribe)
(defstruct Cat n:i32)
(defn describe ((self (ref Cat))):i32 (return (+ 40 (self 'n))))
; Bare: the flattened set. Qualified by the library's own namespace: R2's hatch.
(extend Cat Describe)
(defn main ():i32
  (let (a:(dyn dp/Describe) (Cat 2))
    (return (describe a))))
EOF
  w1_run b2a-import-use-binds-namespace "$d" "$d/b2a-flat.nuc" 42
  rm -rf "$d"
}

# --- Stage 15 B2b: globals resolve through the import environment -------------
# design/stage15-stress-test/name-resolution.md §9, the B2b row.
#
# §1.1 defect #2: `inject-import-aliases` filtered the slice it copied on
# `is-local` and a null `ir-name` — two fields that mean something else
# entirely. `emit-defvar` sets is-local=1 and `defconst`/`defenum` members carry
# no ir-name, so a prefixed import silently reached functions and nothing else.
# The defect closes by DELETION: there is no slice and no filter, the prefix
# names a file, and the file's namespace composes the key the library already
# registered. All four kinds go through one path, so all four resolve.
#
# The run (not just a compile) is the point: an alias carried the ir-name
# verbatim, so a wrong alias linked to the wrong symbol rather than failing.
# Both enum members are named so both must resolve, even though they carry the
# default 0 and 1: 40 (defvar) + 2 (defconst) + 0 + 1 = 43.
run_b2b_prefixed_values() {
  local d err
  d="$(mktemp -d)"
  cat > "$d/b2b-vlib.nuc" <<'EOF'
(ns b2bns)
(defn b2b-fn (x:i32):i32 (return x))
(defvar b2b-gv:i32 40)
(defconst B2B-K 2)
(defenum B2BE B2B-A B2B-B)
EOF
  cat > "$d/b2b-vuse.nuc" <<'EOF'
(import-prefixed b2b-vlib bv)
(defn main ():i32
  (return (bv/b2b-fn (+ (+ bv/b2b-gv bv/B2B-K)
                        (+ bv/B2B-A bv/B2B-B)))))
EOF
  w1_run b2b-prefixed-values "$d" "$d/b2b-vuse.nuc" 43

  # And the other half of §8.3 row 2, for the kinds that had no qualified
  # spelling at all before B2b: the DEFINING namespace is out of scope, because
  # the consumer asked for `bv`. Before B2b this compiled (defect #3).
  cat > "$d/b2b-vns.nuc" <<'EOF'
(import-prefixed b2b-vlib bv)
(defn main ():i32 (return b2bns/b2b-gv))
EOF
  err="$(./build/nucleusc -I "$d" --emit-llvm "$d/b2b-vns.nuc" 2>&1 >/dev/null || true)"
  if ! printf '%s' "$err" | qgrep -F "undefined: b2bns/b2b-gv — 'b2bns' is not in scope in this file"; then
    echo "FAIL  b2b-prefixed-values-ns-refused (wrong or missing diagnostic)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | qgrep -F "not defined anywhere in this compilation unit"; then
    echo "FAIL  b2b-prefixed-values-ns-refused (degraded to the reachability message)"
    printf '%s\n' "$err" | sed 's/^/    /'
  else
    echo "PASS  b2b-prefixed-values-ns-refused"
  fi
  rm -rf "$d"
}

# --- Dispatch sequence (original top-to-bottom order) ---------------------------

for src in examples/*.nuc; do
  [ -f "$src" ] || continue
  [ -f "tests/expected/$(basename "$src" .nuc).out" ] || continue
  spawn run_example "$src"
done

for src in tests/repl/*.in; do
  [ -f "$src" ] || continue
  [ -f "tests/expected/repl-$(basename "$src" .in).out" ] || continue
  spawn run_repl "$src"
done

spawn run_repl_meta_loose

for triple in \
    x86_64-pc-linux-gnu \
    x86_64-apple-darwin \
    aarch64-apple-darwin \
    aarch64-unknown-linux-gnu \
    arm-unknown-linux-gnueabihf \
    x86_64-pc-windows-msvc \
    x86_64-pc-windows-gnu \
    i386-pc-linux-gnu \
    avr; do
  spawn run_target_triple "$triple"
done

# AVR-1 IR-emission gate: attiny1634 (a listed device) and avrxmega3 (the
# AVR-Dx family core, used for the deviceless AVR32DD20). Both must lower via llc.
spawn run_avr_emit attiny1634
spawn run_avr_emit avrxmega3

# AVR-2 16-bit correctness gate: usize/sizeof width + qq-helper malloc(22)/align 1,
# round-tripped through llc for both reference devices.
spawn run_avr2_16bit attiny1634
spawn run_avr2_16bit avrxmega3

# AVR-3 end-to-end link gate: drive avr-gcc to a linked .elf for both reference
# devices — attiny1634 (mcpu==device) and avr32dd20 (avrxmega3 family core +
# explicit --mmcu). Requires the avr-gcc toolchain (SKIPs otherwise).
spawn run_w9_gep_index_width

spawn run_avr3_link attiny1634 attiny1634
spawn run_avr3_link avr32dd20 avrxmega3 avr32dd20

# AVR-5 ISR gate: link the ISR example for the ATmega328P and confirm (via
# avr-objdump) the vector-table jump to __vector_13 and its `reti` epilogue —
# proof the "signal" function attribute reached the AVR backend.
spawn run_avr5_isr

# AVR-6 Harvard-hazard gates: (1) the function-value diagnostic fires on AVR and
# NOT on the host (prog-as-keyed); (2) `:const` emits an LLVM `constant`; (3)
# `:const` is rejected on a let binding and a struct field (only defvar globals
# have a global-vs-constant storage class); (4) `set!` against a `:const`
# global is rejected at compile time (gap fix — was previously a silent
# `store` into read-only storage, UB, segfault at runtime). Compiler-only —
# no AVR toolchain.
spawn run_avr6_fnvalue
spawn run_avr6_const
spawn run_reject avr6-const-on-let-rejected tests/fixtures/avr6-const-let.nuc \
  "':const' applies only to a defvar global"
spawn run_reject avr6-const-on-field-rejected tests/fixtures/avr6-const-field.nuc \
  "':const' applies only to a defvar global"
spawn run_reject avr6-const-mutate-rejected tests/fixtures/avr6-const-mutate-rejected.nuc \
  "set!: cannot assign to 'answer' -- declared :const"

# AVR-7 numerics + ABI gates: (1) f64 is rejected on AVR at both finalization
# points (explicit :f64/double annotation AND bare float literal default) while
# the same source compiles on the host; f32 and i64 stay allowed on AVR. (2) AVR
# classifies every aggregate as plain-pointer ABI-MEMORY (no byval) + sret return,
# target-keyed against the host's register coercion, and links via avr-gcc.
spawn run_avr7_f64
spawn run_avr7_struct

# RV-1 IR-emission gate: riscv64 datalayout/triple + target-abi=lp64d module flag,
# and the "features cliff" llc round-trip (hardware mul/fadd.d, no soft-float
# libcalls).
spawn run_riscv_emit

# RV-6 gate: the lp64d hard-float struct ABI (flattening rules + register
# counting + the variadic tail), cross-emitted and pinned against clang's own
# lowering, plus the x86_64 anti-leak control.
spawn run_rv6_fp_abi

spawn check_long x86_64-pc-linux-gnu    i64 i64   # LP64
spawn check_long aarch64-apple-darwin   i64 i64   # LP64
spawn check_long i386-pc-linux-gnu      i32 i64   # ILP32
spawn check_long x86_64-pc-windows-msvc i32 i64   # LLP64

spawn run_abi_subtest

spawn run_layout_subtest

spawn run_ns6

spawn run_sm3

# Stage 13 L1: cfn escape analysis. A cfn captures each used local by reference,
# so the closure value inherits the captured referent's frame region. Returning
# it out of that scope would dangle, so compiling the fixture must FAIL with the
# frame-region escape error. (The `examples/closures.nuc` run covers the positive
# cfn case; this proves the escape rejection.)
spawn run_reject closure-escape-rejected tests/fixtures/closure-escape.nuc \
  "address of frame-local storage escapes via return"

# Stage 13 CE-3: moving a struct-VALUE Drop binding into an `mfn` consumes the
# source, so a later use must be rejected as use-after-move — including through
# `addr-of` (the only way to read a struct value's field). Compiling the fixture
# must FAIL with the use-after-move error. (The `examples/ce3-owning-closure.nuc`
# run covers the positive move/drop-once path; this proves the consume.)
spawn run_reject ce3-use-after-move-rejected tests/fixtures/ce3-use-after-move.nuc \
  "use after move: 'r'"

# Stage 14 LW-1/LW-2: an overload set with no i32 candidate (x:i64 / x:ui8)
# called with a bare literal reaches the tier-2 widen/untyped-int-literal
# adaptation pool on both candidates, so the call is genuinely ambiguous.
# Compiling the fixture must FAIL with the widening-ambiguity error. (The
# positive `examples/int-widening.nuc` run covers the unique-widen case; this
# proves the ambiguity accounting still dies.)
spawn run_reject lw-ambiguous-widening-rejected tests/fixtures/lw-ambiguous-widening.nuc \
  "ambiguous overload for 'f' under argument widening"

# Stage 14 LW-4: an out-of-range literal (300 does not fit ui8) must be a
# compile-time error instead of the old silent trunc-and-wrap. Compiling the
# fixture must FAIL with the representability error.
spawn run_reject lw-literal-range-rejected tests/fixtures/lw-literal-range.nuc \
  "integer literal 300 does not fit ui8"

# Stage 14 SM-5: a name containing a character that is legal in a Nucleus
# symbol but illegal in an unquoted LLVM identifier (ir-name-token only maps
# `?`/`!`; the solitary defn path applies no other sanitizing) must be a
# source-level compiler error, not a raw LLVM parse error at link/verify time.
spawn run_reject sm5-illegal-char-rejected tests/fixtures/sm5-illegal-char.nuc \
  "illegal character '%' in generated symbol for 'weird%name'"

# Stage 14 TC-1: a zero-arg return-only-tyvar generic called with no expected
# type (no declared binding → no want) must FAIL with the dedicated diagnostic,
# not the misleading "no matching method".
spawn run_reject tc-cannot-infer-tyvar tests/fixtures/tc-cannot-infer-tyvar.nuc \
  "cannot infer type variable 'T' for 'box-empty'"

spawn run_closure_cheader

spawn run_box_cheader

spawn run_s1_sugar_rets

# 2. A bare-name new-style defn missing its mandatory return operand dies cleanly
#    with the targeted diagnostic (the same message a stale legacy spelling gets
#    in Phase S4), not a crash or a remote type error.
spawn run_reject s1-missing-ret-diagnostic tests/fixtures/s1-missing-ret.nuc \
  "expected return type after the parameter list"

spawn run_s1_block

# Stage 14 defn-signature.md S4 — the legacy `name:ret` return-in-the-name signature
# is retired. A colon-bearing (or list-head) defn / declare / protocol-method /
# generic-template signature must now die with the targeted "legacy 'name:ret'
# syntax is no longer supported" diagnostic, quoting the offending name, at each
# chokepoint (defn-parse-sig, emit-nuch-declare-import, protocol-register-form,
# register-generic-defn).
spawn run_reject s4-legacy-defn-rejected tests/fixtures/s4-legacy-defn.nuc \
  "defn 'foo': legacy 'name:ret' syntax is no longer supported"
spawn run_reject s4-legacy-declare-rejected tests/fixtures/s4-legacy-declare.nuc \
  "declare 'bar': legacy 'name:ret' syntax is no longer supported"
spawn run_reject s4-legacy-proto-rejected tests/fixtures/s4-legacy-proto.nuc \
  "protocol method 'area': legacy 'name:ret' syntax is no longer supported"
spawn run_reject s4-legacy-template-rejected tests/fixtures/s4-legacy-template.nuc \
  "defn 'gmax': legacy 'name:ret' syntax is no longer supported"

spawn run_reject s17-dup-struct-field-rejected tests/fixtures/s17-dup-struct-field.nuc \
  "defstruct: duplicate field 'x'"

spawn run_reject s17-rvalue-addr-of-rejected tests/fixtures/s17-rvalue-addr-of.nuc \
  "show: argument 1 has type StrView, which does not match parameter type ptr:StrView"

# Stage 14 unsafe-namespace.md UN-1 — the `(as TYPE expr)` statically-safe
# conversion form. Its three rejection categories each route to the right tool:
#   lossy/narrowing  -> "use unsafe/cast"
#   raw->ref launder -> mentions "as-ref" (honors pkind-flow-check, which `cast`
#                       bypasses)
#   reinterpretation -> "use unsafe/cast"
spawn run_reject as-lossy-rejected tests/fixtures/as-lossy.nuc \
  "as: lossy conversion from i32 to i8 -- use unsafe/cast"
spawn run_reject as-raw-to-ref-rejected tests/fixtures/as-raw-to-ref.nuc \
  "where non-null ptr:Rec is required -- use as-ref (checked) or unsafe/cast"
spawn run_reject as-reinterpret-rejected tests/fixtures/as-reinterpret.nuc \
  "as: reinterpretation from ptr:Sym to ptr:Rec -- use unsafe/cast"

# Stage 16 as-sugar.md — a value-position `:type` annotation is that same `as`
# cast (`baz:CStr` == `(as CStr baz)`), so the first three pin that it inherits
# `as`'s refusals rather than getting a laxer path of its own; the accept side
# runs as examples/as-sugar.nuc. The first is also the WART being closed: the
# annotation used to be discarded unread, so `x:NoSuchType` compiled silently.
# The fourth holds the excluded spelling: a parenthesised type is claimed by the
# reader's colon-paren fuse in every list context, so it reads as a call and
# must SAY so instead of reporting `unknown: ref`.
spawn run_reject as-sugar-unknown-type tests/fixtures/as-sugar-unknown-type.nuc \
  "unknown type 'NoSuchType' in the annotation 'x:NoSuchType'"
spawn run_reject as-sugar-lossy tests/fixtures/as-sugar-lossy.nuc \
  "as: lossy conversion from i64 to i32 -- use unsafe/cast"
spawn run_reject as-sugar-raw-to-ref tests/fixtures/as-sugar-raw-to-ref.nuc \
  "use as-ref (checked) or unsafe/cast (unchecked assertion)"
spawn run_reject as-sugar-paren tests/fixtures/as-sugar-paren.nuc \
  "'q:(ref ...)' reads as a call here"
#
# Stage 15 W9 item 8 refines the FIRST category only: a narrowing whose operand
# is a literal that provably fits is not lossy. `as-lossy.nuc` above narrows a
# parameter — an unknown runtime value — and so is unaffected, which is the
# distinction being pinned. The accept side RUNS (an exit-0 compile would not
# catch a sign error in the range test); the two rejects hold the boundary at
# magnitude and at sign.
spawn run_w9_as_literal_narrowing
spawn run_reject w9-as-literal-too-big tests/fixtures/w9-as-literal-too-big.nuc \
  "as: lossy conversion from i32 to i8 -- use unsafe/cast"
spawn run_reject w9-as-literal-signed-into-unsigned \
  tests/fixtures/w9-as-literal-signed-into-unsigned.nuc \
  "as: lossy conversion from i32 to ui8 -- use unsafe/cast"

# W9 item 30 does the same for f64->f32, and the two rejects hold the two edges
# the ruling draws. `-inexact` is the VALUE edge: 3.14 is a literal that does not
# round-trip, so admitting it would make `as` round silently. `-runtime` is the
# KNOWLEDGE edge: a parameter is unknown, so the widths alone decide and the
# original rule stands. `-global-inexact` pins that `defvar-init-ir`'s fold
# reaches the same verdict with the same wording — it is a second asker of the
# rule, and a second asker that re-derives is what this stage keeps finding.
spawn run_w9_as_float_literal_narrowing
spawn run_reject w9-as-float-inexact tests/fixtures/w9-as-float-inexact.nuc \
  "as: lossy conversion from f64 to f32 -- use unsafe/cast"
spawn run_reject w9-as-float-runtime tests/fixtures/w9-as-float-runtime.nuc \
  "as: lossy conversion from f64 to f32 -- use unsafe/cast"
spawn run_reject w9-as-float-global-inexact \
  tests/fixtures/w9-as-float-global-inexact.nuc \
  "as: lossy conversion from f64 to f32 -- use unsafe/cast"

spawn run_w9_bool_unsigned
spawn run_w9_unsigned_index
spawn run_w9_arg_coerce
spawn run_w9_dyn_solitary
spawn run_w9_fnslot_arg
spawn run_s16_se_template_ref
spawn run_s16_fp2_indirect_call
spawn run_s16_fp4_cheader_fnptr
spawn run_s16_fp5_cheader_fnptr
spawn run_s16_sv1_struct_value_receiver
spawn run_s16_c1_bare_unsigned

# Stage 16 §6 (design/stage16-ergonomics/c-boundary-defects.md): the three float
# widths C has and Nucleus did not — f16/f80/f128 — plus FL-3's hex literals.
# clang is the oracle throughout, because "the value is right" is not the claim:
# the claim is that the emitted CONSTANT and the emitted SIGNATURE are the ones
# the platform C compiler emits, bit for bit.
run_s16_fl_float_widths() {
  local d
  d="$(mktemp -d)"

  if ! command -v clang >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
    echo "PASS  s16-fl-constants-vs-clang (SKIP: needs clang and python3)"
    echo "PASS  s16-fl-aggregate-abi (SKIP: needs clang)"
    echo "PASS  s16-fl-vararg-unpromoted (SKIP: needs clang)"
  else
    # 1. Every literal at every width, against clang's own constant. Decimal is
    #    asserted only at f16/f32/f64: a decimal literal folds through the host
    #    f64, so at f80/f128 it is deliberately LESS precise than C's answer
    #    (§10 limit 1, staged as design/future/decimal-float-literals.md). Hex
    #    is asserted at all five, which is exactly what FL-3 buys.
    python3 - "$d" <<'PYEOF'
import sys
d = sys.argv[1]
hexl = ["0x1p0", "0x1.8p+3", "-0x1.8p-3", "0x0p0", "-0x0p0",
        "0x1.921fb54442d18469898cc51701b8p+1", "0xabcdefp-20", "-0x1.fp-5",
        "0x1.0000000000001p0", "0x1.00000000000008p0", "0x1.00000000000018p0",
        "0x123456789abcdef0123456789abcdefp0", "0X1.8P1", "0x1p16",
        "0x1p+1024", "0x1p-16445"]
dec = ["1.0", "2.5", "0.5", "3.14", "-0.0", "1e3", "100.0", "0.125"]
kinds = [("f16", "_Float16", "f16"), ("f32", "float", "f"), ("f64", "double", ""),
         ("f80", "long double", "L"), ("f128", "__float128", "q")]
nuc, c = [], []
def row(tag, lit):
    for nk, ct, suf in kinds:
        if tag == "d" and nk in ("f80", "f128"):
            continue
        nm = f"v{len(nuc)}_{nk}"
        nuc.append(f"(defvar {nm}:{nk} {lit})")
        c.append(f"__attribute__((used)) static {ct} {nm} = {lit}{suf};")
for l in hexl: row("h", l)
for l in dec:  row("d", l)
nuc.append("(defn main ():i32 (return 0))")
open(f"{d}/lit.nuc", "w").write("\n".join(nuc) + "\n")
open(f"{d}/lit.c", "w").write("\n".join(c) + "\n")
PYEOF
    ./build/nucleusc --emit-llvm "$d/lit.nuc" 2>"$d/lit.err" | grep -E '^@v' > "$d/lit.nuc.raw" || true
    clang -S -emit-llvm -O0 -w -o - "$d/lit.c" 2>/dev/null | grep -E '^@v' > "$d/lit.c.raw" || true
    if ! [ -s "$d/lit.c.raw" ]; then
      echo "PASS  s16-fl-constants-vs-clang (SKIP: this clang has no _Float16/__float128)"
    else
      python3 - "$d" > "$d/lit.cmp" <<'PYEOF'
import re, struct, sys
d = sys.argv[1]
def load(p):
    out = {}
    for line in open(p):
        m = re.match(r'^@(\w+) = (?:dso_local )?(?:internal )?global (\S+) ([^,]+)', line)
        if not m: continue
        name, ty, val = m.group(1), m.group(2), m.group(3).strip()
        # LLVM prints a float/double constant as a decimal when it round-trips
        # and as the f64 bit pattern otherwise; normalize to the bit pattern.
        if not val.startswith(("0xH", "0xK", "0xL")):
            val = "0x%016X" % struct.unpack("<Q", struct.pack("<d", float.fromhex(val) if val.startswith("0x") and "p" in val.lower() else (struct.unpack("<d", struct.pack("<Q", int(val, 16)))[0] if val.startswith("0x") else float(val))))[0]
        out[name] = (ty, val)
    return out
a, b = load(f"{d}/lit.nuc.raw"), load(f"{d}/lit.c.raw")
bad = 0
for k in sorted(b):
    if k not in a:
        print(f"    {k}: missing from nucleus"); bad += 1
    elif a[k] != b[k]:
        print(f"    {k}: nucleus {a[k]}  clang {b[k]}"); bad += 1
print(f"ROWS {len(b)} BAD {bad}")
PYEOF
      if grep -q " BAD 0$" "$d/lit.cmp" && ! grep -q "^ROWS 0 " "$d/lit.cmp"; then
        echo "PASS  s16-fl-constants-vs-clang ($(sed -n 's/^ROWS \([0-9]*\).*/\1/p' "$d/lit.cmp") constants)"
      else
        echo "FAIL  s16-fl-constants-vs-clang"
        sed 's/^/    /' "$d/lit.err" | head -3
        head -20 "$d/lit.cmp"
      fi
    fi

    # 2. FL-4: the aggregate ABI, which is where the three widths differ from
    #    each other rather than from f64. X87 poisons its aggregate to MEMORY;
    #    a 16-byte fp128 stays ONE eightbyte-pair in xmm (forcing MEMORY there
    #    would be an ABI mismatch, so the conservative answer is the wrong one);
    #    an f16 beside an i32 max-merges into a single INTEGER eightbyte.
    cat > "$d/agg.c" <<'EOF'
struct S1 { long double x; };
struct S2 { __float128 x; };
struct S3 { _Float16 x; int y; };
long double f0(long double a){return a;}
_Float16 f4(_Float16 a){return a;}
__float128 f5(__float128 a){return a;}
struct S1 f1(struct S1 s){return s;}
struct S2 f2(struct S2 s){return s;}
struct S3 f3(struct S3 s){return s;}
EOF
    cat > "$d/agg.nuc" <<'EOF'
(defstruct S1 x:f80)
(defstruct S2 x:f128)
(defstruct S3 x:f16 y:i32)
(defn f0 (a:f80):f80 (return a))
(defn f4 (a:f16):f16 (return a))
(defn f5 (a:f128):f128 (return a))
(defn f1 (s:S1):S1 (return s))
(defn f2 (s:S2):S2 (return s))
(defn f3 (s:S3):S3 (return s))
(defn main ():i32 (return 0))
EOF
    clang -S -emit-llvm -O0 -w -o - "$d/agg.c" 2>/dev/null |
      sed -nE 's/^define dso_local (.*) @(f[0-9])\((.*)\) #.*/\2 \1 \3/p' |
      sed -E 's/ noundef//g; s/%struct\.//g' | sort > "$d/agg.c.sig"
    ./build/nucleusc --emit-llvm "$d/agg.nuc" 2>"$d/agg.err" |
      sed -nE 's/^define (.*) @(f[0-9])\((.*)\) section.*/\2 \1 \3/p' |
      sed -E 's/%[A-Za-z0-9_.]+\.arg//g; s/%[0-9]+//g; s/%//g; s/ +$//' | sort > "$d/agg.nuc.sig"
    sed -E 's/%[0-9]+//g; s/ +$//' "$d/agg.c.sig" > "$d/agg.c.sig2"
    if [ -s "$d/agg.c.sig2" ] && diff -q "$d/agg.nuc.sig" "$d/agg.c.sig2" >/dev/null; then
      echo "PASS  s16-fl-aggregate-abi"
    elif ! [ -s "$d/agg.c.sig2" ]; then
      echo "PASS  s16-fl-aggregate-abi (SKIP: this clang has no __float128)"
    else
      echo "FAIL  s16-fl-aggregate-abi"
      diff "$d/agg.nuc.sig" "$d/agg.c.sig2" | sed 's/^/    /' | head -20
      sed 's/^/    /' "$d/agg.err" | head -3
    fi

    # 3. FL-5: `...` promotes f32 to double and leaves the other four alone —
    #    measured from clang, and the tempting generalization ("promote any
    #    float narrower than f64") would break `half` in exactly this line.
    printf 'int flp(const char *fmt, ...);\n' > "$d/va.h"
    cat > "$d/va.nuc" <<EOF
(import-use "$d/va.h")
(defn g (h:f16 f:f32 ld:f80 q:f128 dd:f64):void (flp "" h f ld q dd))
(defn main ():i32 (return 0))
EOF
    ./build/nucleusc --emit-llvm "$d/va.nuc" 2>"$d/va.err" > "$d/va.ll" || true
    if qgrep -E 'call i32 \(ptr, \.\.\.\) @flp\(ptr [^,]*, half [^,]*, double [^,]*, x86_fp80 [^,]*, fp128 [^,]*, double ' "$d/va.ll"; then
      echo "PASS  s16-fl-vararg-unpromoted"
    else
      echo "FAIL  s16-fl-vararg-unpromoted"
      grep 'call i32' "$d/va.ll" | sed 's/^/    /' | head -3
      sed 's/^/    /' "$d/va.err" | head -3
    fi
  fi

  # 4. FL-6 and §10 limit 3: a width the emission target has no format for is a
  #    located error, not IR no backend can select. C's own `long double` stays
  #    portable — only the representation spelling `f80` is target-bound.
  # Every check here writes to a file first: the compiler EXITS NON-ZERO on the
  # rejections, and under this script's `set -o pipefail` a pipeline into grep
  # would report the compiler's status, not the match.
  local ok=1 t n
  printf '(defn f (x:f80):f80 (return x))\n(defn main ():i32 (return 0))\n' > "$d/w.nuc"
  for t in aarch64-unknown-linux-gnu riscv64-unknown-linux-gnu; do
    ./build/nucleusc --target="$t" --emit-llvm "$d/w.nuc" >/dev/null 2>"$d/w.err" || true
    qgrep -F 'f80 is the x87 80-bit format and exists only on x86' "$d/w.err" || ok=0
  done
  for n in f16 f80 f128; do
    printf '(defn f (x:%s):%s (return x))\n(defn main ():i32 (return 0))\n' "$n" "$n" > "$d/a.nuc"
    ./build/nucleusc --target=avr-unknown-unknown-elf --emit-llvm "$d/a.nuc" >/dev/null 2>"$d/a.err" || true
    qgrep -F "$n is not supported on AVR" "$d/a.err" || ok=0
  done
  ./build/nucleusc --emit-llvm "$d/w.nuc" >/dev/null 2>&1 || ok=0
  # FL-7: `long double` is whatever the target's C compiler makes it.
  printf 'long double ldf(long double x);\n' > "$d/ld.h"
  printf '(import-use "%s/ld.h")\n(defn main ():i32 (return 0))\n' "$d" > "$d/ld.nuc"
  ld_decl() {  # <triple> <expected declare line>
    ./build/nucleusc --target="$1" --emit-llvm "$d/ld.nuc" > "$d/ld.ll" 2>/dev/null || true
    qgrep -F "$2" "$d/ld.ll" || ok=0
  }
  ld_decl aarch64-unknown-linux-gnu 'declare fp128 @ldf(fp128)'
  ld_decl riscv64-unknown-linux-gnu 'declare fp128 @ldf(fp128)'
  ld_decl x86_64-unknown-linux-gnu  'declare x86_fp80 @ldf(x86_fp80)'
  # MSVC keeps it a plain double even on x86_64, which is why the check for it
  # has to precede the architecture check.
  ld_decl x86_64-pc-windows-msvc    'declare double @ldf(double)'
  if [ "$ok" = 1 ]; then echo "PASS  s16-fl-target-availability"; else
    echo "FAIL  s16-fl-target-availability"
  fi

  # 5. FL-3 at run time, and the two shapes that are NOT hex floats: C requires
  #    the binary exponent, so `0x1F` is an integer and `0x1.8` is neither.
  ok=1
  cat > "$d/hx.nuc" <<'EOF'
(import-use "stdio.h")
(defn id80 (x:f80):f80 (return x))
(defn main ():i32
  (let (a:i64 0xDEADBEEF b:i32 0x7F c:ui64 0xFFFFFFFFFFFFFFFF d:i64 -0x10
        e:f64 0x1.8p+3)
    (printf "%ld %d %lu %ld %.4f\n" a b c d e)
    (printf "%.21Lg\n" (id80 0x1.921fb54442d18469p+1)))
  (return 0))
EOF
  ./build/nucleusc "$d/hx.nuc" -o "$d/hx.bin" 2>"$d/hx.err" || true
  if [ -x "$d/hx.bin" ] &&
     [ "$("$d/hx.bin")" = "$(printf '3735928559 127 18446744073709551615 -16 12.0000\n3.1415926535897932383')" ]; then
    echo "PASS  s16-fl3-hex-literals"
  else
    echo "FAIL  s16-fl3-hex-literals"
    sed 's/^/    /' "$d/hx.err" | head -3
    [ -x "$d/hx.bin" ] && "$d/hx.bin" | sed 's/^/    got: /'
  fi
  printf '(defn main ():i32 (let (x:f64 0x1.8) (return 0)))\n' > "$d/noexp.nuc"
  ./build/nucleusc --emit-llvm "$d/noexp.nuc" >/dev/null 2>"$d/noexp.err" || true
  qgrep -F "undefined: 0x1.8" "$d/noexp.err" || ok=0
  if [ "$ok" = 1 ]; then echo "PASS  s16-fl3-exponent-required"; else
    echo "FAIL  s16-fl3-exponent-required"
  fi
  rm -rf "$d"
}
spawn run_s16_fl_float_widths

# Stage 16 §7 (design/stage16-ergonomics/c-boundary-defects.md): packed structs.
# The gate is deliberately three-part, because a `sizeof`/offset diff cannot see
# two of the three consequences: the IR type line has to say `<{ … }>`, and every
# access through a packed field has to say `align 1` or the IR states an
# alignment the layout does not provide — a real miscompile on a
# strict-alignment target and under vectorization on x86.
run_s16_pk_packed() {
  local d ok=1 t nt ct
  d="$(mktemp -d)"

  cat > "$d/xt.nuc" <<'EOF'
(defstruct :packed A c:i8 i:i32 s:i16)
(defstruct B c:i8 i:i32 s:i16)
(defstruct :packed C c:i8 l:i64)
(defstruct D a:i16 (b (array i32 3)) c:i8)
(defstruct :packed E a:i16 (b (array i32 3)) c:i8)
(defstruct F c:i8 inner:A i:i32)
(defvar sA:i64 (sizeof A))
(defvar sB:i64 (sizeof B))
(defvar sC:i64 (sizeof C))
(defvar sD:i64 (sizeof D))
(defvar sE:i64 (sizeof E))
(defvar sF:i64 (sizeof F))
EOF
  cat > "$d/xt.c" <<'EOF'
#include <stdint.h>
struct __attribute__((packed)) A { int8_t c; int32_t i; int16_t s; };
struct B { int8_t c; int32_t i; int16_t s; };
struct __attribute__((packed)) C { int8_t c; int64_t l; };
struct D { int16_t a; int32_t b[3]; int8_t c; };
struct __attribute__((packed)) E { int16_t a; int32_t b[3]; int8_t c; };
struct F { int8_t c; struct A inner; int32_t i; };
EOF

  # 1. THE CROSS-TARGET ORACLE (§11). `clang --target=<t> -ffreestanding
  #    -fsyntax-only` over generated `_Static_assert`s is a complete compile-time
  #    sizeof/offsetof oracle on every target clang supports — no execution, no
  #    sysroot, no linking. It earns its place immediately: it caught AVR's
  #    BIGGEST_ALIGNMENT being 8 bits (every type byte-aligned, so `struct B` is
  #    7 bytes there and not 12), which had been wrong since before packing
  #    existed and which run-layout-test.sh, being host-only, cannot see.
  if ! command -v clang >/dev/null 2>&1; then
    echo "PASS  s16-pk-layout-cross-target (SKIP: no clang)"
  else
    for t in x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu \
             riscv64-unknown-linux-gnu i386-unknown-linux-gnu avr; do
      nt="$t"; [ "$t" = avr ] && nt=avr-unknown-unknown-elf
      ./build/nucleusc --target="$nt" --emit-llvm "$d/xt.nuc" > "$d/xt.ll" 2>/dev/null || true
      { cat "$d/xt.c"
        sed -nE 's/^@s([A-F]) = global i64 ([0-9]+).*/_Static_assert(sizeof(struct \1)==\2,"\1");/p' "$d/xt.ll"
      } > "$d/chk-$t.c"
      # An empty assertion list would pass vacuously; six shapes, six asserts.
      [ "$(grep -c _Static_assert "$d/chk-$t.c")" = 6 ] || ok=0
      clang --target="$t" -ffreestanding -fsyntax-only "$d/chk-$t.c" 2>"$d/chk-$t.err" || ok=0
      grep -q 'error' "$d/chk-$t.err" && ok=0
    done
    if [ "$ok" = 1 ]; then echo "PASS  s16-pk-layout-cross-target (6 shapes x 5 targets)"; else
      echo "FAIL  s16-pk-layout-cross-target"
      grep -h 'error' "$d"/chk-*.err | sed 's/^/    /' | head -10
    fi
  fi

  # 2. The two consequences a layout diff is blind to: the type line and the
  #    access alignment. Asserted on the IR, not on a printed size.
  ok=1
  cat > "$d/ir.nuc" <<'EOF'
(defstruct :packed P c:i8 i:i32)
(defstruct Q c:i8 i:i32)
(defn rd (p:ptr:P):i32 (return (get p 'i)))
(defn wr (p:ptr:P):void (set! (p 'i) 7))
(defn lit ():ptr:P (return (P 1 2)))
(defn rdq (q:ptr:Q):i32 (return (get q 'i)))
EOF
  ./build/nucleusc --emit-llvm "$d/ir.nuc" > "$d/ir.ll" 2>"$d/ir.err" || true
  qgrep -F '%P = type <{ i8, i32 }>' "$d/ir.ll" || ok=0
  qgrep -F '%Q = type { i8, i32 }' "$d/ir.ll" || ok=0
  # Every load/store through a P field says align 1; Q's says align 4.
  [ "$(grep -cE '(load|store) i32[, ].*align 1$' "$d/ir.ll")" -ge 3 ] || ok=0
  qgrep -E 'load i32, ptr %[a-z0-9]+, align 4' "$d/ir.ll" || ok=0
  # ...and nothing through a P field claims more than it has.
  ! qgrep -E 'store i32 2, ptr %[a-z0-9]+$' "$d/ir.ll" || ok=0
  if [ "$ok" = 1 ]; then echo "PASS  s16-pk-access-align"; else
    echo "FAIL  s16-pk-access-align"
    sed 's/^/    /' "$d/ir.err" | head -3
    grep -E '= type|align' "$d/ir.ll" | sed 's/^/    /' | head -12
  fi

  # 3. The values actually round-trip, against the identical C program.
  ok=1
  cat > "$d/run.nuc" <<'EOF'
(import-use "stdio.h")
(defstruct :packed R c:i8 i:i32 s:i16)
(defn main ():i32
  (let (p:ptr:R (alloca R))
    (set! (p 'c) 1) (set! (p 'i) 305419896) (set! (p 's) -3)
    (printf "%ld %d %d %d\n" (sizeof R)
      (as i32 (get p 'c)) (get p 'i) (as i32 (get p 's))))
  (let (r:ptr:R (R 7 8 9))
    (printf "%d %d %d\n" (as i32 (get r 'c)) (get r 'i) (as i32 (get r 's))))
  (return 0))
EOF
  ./build/nucleusc "$d/run.nuc" -o "$d/run.bin" 2>"$d/run.err" || true
  if [ -x "$d/run.bin" ] &&
     [ "$("$d/run.bin")" = "$(printf '7 1 305419896 -3\n7 8 9')" ]; then
    echo "PASS  s16-pk-values"
  else
    echo "FAIL  s16-pk-values"
    sed 's/^/    /' "$d/run.err" | head -3
    [ -x "$d/run.bin" ] && "$d/run.bin" | sed 's/^/    got: /'
  fi

  # 4. PK-2, import side: the two positions C honours, the one it ignores (both
  #    clang and gcc warn `-Wignored-attributes` there, so honouring it would
  #    disagree with every C compiler on the platform), and the alias path — an
  #    alias shares the field table, which is NOT the same as sharing the layout.
  ok=1
  cat > "$d/h.h" <<'EOF'
struct __attribute__((packed)) PK1 { char c; int i; short s; };
struct PK2 { char c; int i; short s; } __attribute__((packed));
typedef struct { char c; int i; } __attribute__((packed)) PK3;
typedef struct { char c; int i; } PK4;
typedef struct { char c; int i; } PK5 __attribute__((packed));
struct __attribute__((__packed__)) PK7 { char c; long l; };
EOF
  cat > "$d/h.nuc" <<EOF
(import-use "stdio.h")
(import-use "$d/h.h")
(defn main ():i32
  (printf "%ld %ld %ld %ld %ld %ld\n" (sizeof PK1) (sizeof PK2) (sizeof PK3)
    (sizeof PK4) (sizeof PK5) (sizeof PK7))
  (return 0))
EOF
  ./build/nucleusc "$d/h.nuc" -o "$d/h.bin" 2>"$d/h.err" || true
  if command -v cc >/dev/null 2>&1; then
    cat > "$d/h.c" <<EOF
#include <stdio.h>
#include "$d/h.h"
int main(void){ printf("%zu %zu %zu %zu %zu %zu\n", sizeof(struct PK1),
  sizeof(struct PK2), sizeof(PK3), sizeof(PK4), sizeof(PK5), sizeof(struct PK7));
  return 0; }
EOF
    cc -w "$d/h.c" -o "$d/h.cbin" 2>/dev/null || ok=0
    [ -x "$d/h.bin" ] && [ -x "$d/h.cbin" ] &&
      [ "$("$d/h.bin")" = "$("$d/h.cbin")" ] || ok=0
    if [ "$ok" = 1 ]; then echo "PASS  s16-pk-import-positions"; else
      echo "FAIL  s16-pk-import-positions"
      sed 's/^/    /' "$d/h.err" | head -3
      [ -x "$d/h.cbin" ] && echo "    cc:      $("$d/h.cbin")"
      [ -x "$d/h.bin" ] && echo "    nucleus: $("$d/h.bin")"
    fi
  else
    echo "PASS  s16-pk-import-positions (SKIP: no cc to build the oracle against)"
  fi

  # 5. PK-2, export side: `--emit-cheader` writes the attribute back out, a C
  #    consumer's own `_Static_assert` agrees, and re-importing the generated
  #    header reproduces the size.
  ok=1
  cat > "$d/x.nuc" <<'EOF'
(defstruct :packed WireHdr tag:i8 len:i32 flags:i16)
(defstruct PlainHdr tag:i8 len:i32 flags:i16)
(defn wire-len (h:ptr:WireHdr):i32 (return (get h 'len)))
EOF
  ./build/nucleusc --emit-cheader "$d/x.nuc" > "$d/x.h" 2>"$d/x.err" || ok=0
  qgrep -F '} __attribute__((packed)) WireHdr;' "$d/x.h" || ok=0
  qgrep -F '} PlainHdr;' "$d/x.h" || ok=0
  if command -v clang >/dev/null 2>&1; then
    cat > "$d/x-c.c" <<EOF
#include "$d/x.h"
_Static_assert(sizeof(WireHdr)==7,"packed");
_Static_assert(sizeof(PlainHdr)==12,"plain");
EOF
    clang -std=gnu11 -Wall -Wextra -Werror -c "$d/x-c.c" -o /dev/null 2>"$d/x-c.err" || ok=0
  fi
  printf '(import-use "%s/x.h")\n(import-use "stdio.h")\n(defn main ():i32 (printf "%%ld %%ld\\n" (sizeof WireHdr) (sizeof PlainHdr)) (return 0))\n' "$d" > "$d/rt.nuc"
  ./build/nucleusc "$d/rt.nuc" -o "$d/rt.bin" 2>"$d/rt.err" || ok=0
  [ -x "$d/rt.bin" ] && [ "$("$d/rt.bin")" = "7 12" ] || ok=0
  if [ "$ok" = 1 ]; then echo "PASS  s16-pk-cheader-roundtrip"; else
    echo "FAIL  s16-pk-cheader-roundtrip"
    sed 's/^/    /' "$d/x.err" "$d/x-c.err" "$d/rt.err" 2>/dev/null | head -6
    grep -E 'Hdr' "$d/x.h" | sed 's/^/    /' | head -6
  fi

  # 6. `epoll_event` — cheader-parser-vs-libclang.md §2 measured this as the one
  #    `sizeof` mismatch in its 103-type census, and the one row it conceded to
  #    libclang outright.
  ok=1
  if command -v cc >/dev/null 2>&1; then
    printf '(import-use "sys/epoll.h")\n(import-use "stdio.h")\n(defn main ():i32 (printf "%%ld\\n" (sizeof epoll_event)) (return 0))\n' > "$d/ep.nuc"
    printf '#include <stdio.h>\n#include <sys/epoll.h>\nint main(void){printf("%%zu\\n",sizeof(struct epoll_event));return 0;}\n' > "$d/ep.c"
    ./build/nucleusc "$d/ep.nuc" -o "$d/ep.bin" 2>"$d/ep.err" || ok=0
    cc -w "$d/ep.c" -o "$d/ep.cbin" 2>/dev/null || ok=0
    if [ "$ok" = 1 ] && [ "$("$d/ep.bin")" = "$("$d/ep.cbin")" ]; then
      echo "PASS  s16-pk-epoll-event ($("$d/ep.bin") bytes, matching cc)"
    else
      echo "FAIL  s16-pk-epoll-event"
      sed 's/^/    /' "$d/ep.err" | head -3
      [ -x "$d/ep.bin" ] && echo "    nucleus: $("$d/ep.bin")"
      [ -x "$d/ep.cbin" ] && echo "    cc:      $("$d/ep.cbin")"
    fi
  else
    echo "PASS  s16-pk-epoll-event (SKIP: no cc)"
  fi

  # 7. An unknown attribute is refused rather than silently ignored.
  printf '(defstruct :squished S x:i32)\n(defn main ():i32 (return 0))\n' > "$d/bad.nuc"
  ./build/nucleusc --emit-llvm "$d/bad.nuc" >/dev/null 2>"$d/bad.err" || true
  if qgrep -F "unknown defstruct attribute ':squished'" "$d/bad.err"; then
    echo "PASS  s16-pk-unknown-attribute-refused"
  else
    echo "FAIL  s16-pk-unknown-attribute-refused"
    sed 's/^/    /' "$d/bad.err" | head -3
  fi
  rm -rf "$d"
}
spawn run_s16_pk_packed

# --- Stage 16 PK-3: `__attribute__((aligned(N)))` -----------------------------
# design/stage16-ergonomics/c-boundary-defects.md §7 PK-3. A DIFFERENT mechanism
# from packing: it raises a struct's or a member's alignment (never lowers it),
# which grows `sizeof` and moves offsets while LLVM's own type models neither —
# so the growth has to be explicit `[k x i8]` elements, and every GEP index past
# one of them shifts. Surface: `(defstruct :align 16 …)` and `(:align 16 x:T)`.
run_s16_pk3_aligned() {
  local d ok=1 t nt
  d="$(mktemp -d)"

  cat > "$d/at.nuc" <<'EOF'
(defstruct :align 16 A x:i32)
(defstruct B c:i8 (:align 16 i:i32))
(defstruct :packed :align 4 C c:i8 i:i32)
(defstruct :packed D c:i8 (:align 4 i:i32))
(defstruct :align 2 E x:i32)
(defstruct F inner:A c:i8)
(defvar sA:i64 (sizeof A))
(defvar sB:i64 (sizeof B))
(defvar sC:i64 (sizeof C))
(defvar sD:i64 (sizeof D))
(defvar sE:i64 (sizeof E))
(defvar sF:i64 (sizeof F))
EOF
  cat > "$d/at.c" <<'EOF'
#include <stdint.h>
struct A { int32_t x; } __attribute__((aligned(16)));
struct B { int8_t c; int32_t i __attribute__((aligned(16))); };
struct __attribute__((packed,aligned(4))) C { int8_t c; int32_t i; };
struct __attribute__((packed)) D { int8_t c; int32_t i __attribute__((aligned(4))); };
struct E { int32_t x; } __attribute__((aligned(2)));
struct F { struct A inner; int8_t c; };
EOF

  # 1. The same cross-target oracle PK-1 introduced. `aligned` is where it earns
  #    its keep twice over: `aligned(2)` on an `int` struct is IGNORED (alignment
  #    only ever rises), and the packed+aligned pair means the two mechanisms
  #    have to compose rather than override.
  if ! command -v clang >/dev/null 2>&1; then
    echo "PASS  s16-pk3-align-cross-target (SKIP: no clang)"
  else
    for t in x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu \
             riscv64-unknown-linux-gnu i386-unknown-linux-gnu avr; do
      nt="$t"; [ "$t" = avr ] && nt=avr-unknown-unknown-elf
      ./build/nucleusc --target="$nt" --emit-llvm "$d/at.nuc" > "$d/at.ll" 2>/dev/null || true
      { cat "$d/at.c"
        sed -nE 's/^@s([A-F]) = global i64 ([0-9]+).*/_Static_assert(sizeof(struct \1)==\2,"\1");/p' "$d/at.ll"
      } > "$d/ck-$t.c"
      [ "$(grep -c _Static_assert "$d/ck-$t.c")" = 6 ] || ok=0
      clang --target="$t" -ffreestanding -fsyntax-only "$d/ck-$t.c" 2>"$d/ck-$t.err" || ok=0
      grep -q 'error' "$d/ck-$t.err" && ok=0
    done
    if [ "$ok" = 1 ]; then echo "PASS  s16-pk3-align-cross-target (6 shapes x 5 targets)"; else
      echo "FAIL  s16-pk3-align-cross-target"
      grep -h 'error' "$d"/ck-*.err | sed 's/^/    /' | head -10
    fi
  fi

  # 2. What a size diff is blind to: the pad elements in the type line, the
  #    `align N` an alloca must state (LLVM derives its own from the element
  #    list, which knows nothing about the attribute), and the GEP index of
  #    every field sitting after a pad.
  ok=1
  cat > "$d/ir.nuc" <<'EOF'
(import-use "stdio.h")
(defstruct :align 16 A x:i32)
(defstruct B c:i8 (:align 16 i:i32))
(defn read-i (p:ptr:B):i32 (return (get p 'i)))
(defn main ():i32
  (let (a:ptr:A (alloca A) b:ptr:B (B 1 7))
    (set! (a 'x) 5)
    (printf "%d %d\n" (get a 'x) (read-i b)))
  (return 0))
EOF
  ./build/nucleusc --emit-llvm "$d/ir.nuc" > "$d/ir.ll" 2>"$d/ir.err" || ok=0
  # Tail pad on the over-aligned struct; inter-field pad on the over-aligned
  # member; the alloca states the alignment LLVM cannot infer; and `i` is
  # element 2, not element 1.
  qgrep -E '^%A = type \{ i32, \[12 x i8\] \}' "$d/ir.ll" || ok=0
  qgrep -E '^%B = type \{ i8, \[[0-9]+ x i8\], i32, \[[0-9]+ x i8\] \}' "$d/ir.ll" || ok=0
  qgrep -E 'alloca %A, align 16' "$d/ir.ll" || ok=0
  qgrep -E 'getelementptr inbounds %B, ptr %[A-Za-z0-9._]+, i32 0, i32 2' "$d/ir.ll" || ok=0
  qgrep -E 'getelementptr inbounds %B, ptr %[A-Za-z0-9._]+, i32 0, i32 1' "$d/ir.ll" && ok=0
  if [ "$ok" = 1 ]; then echo "PASS  s16-pk3-type-line-and-slots"; else
    echo "FAIL  s16-pk3-type-line-and-slots"
    sed 's/^/    /' "$d/ir.err" | head -3
    grep -E '^%[AB] = type|alloca %A|getelementptr inbounds %B' "$d/ir.ll" | sed 's/^/    /' | head -8
  fi

  # 3. The values round-trip, and the member really is where C puts it — the
  #    offset is read back rather than assumed.
  ok=1
  cat > "$d/run.nuc" <<'EOF'
(import-use "stdio.h")
(defstruct B c:i8 (:align 16 i:i32))
(defn main ():i32
  (let (p:ptr:B (B 1 305419896))
    (printf "%ld %ld %d %d\n" (sizeof B)
      (- (unsafe/cast i64 (addr-of p 'i)) (unsafe/cast i64 p))
      (as i32 (get p 'c)) (get p 'i)))
  (return 0))
EOF
  cat > "$d/run.c" <<'EOF'
#include <stdio.h>
#include <stddef.h>
struct B { char c; int i __attribute__((aligned(16))); };
int main(void){ struct B b = {1, 305419896};
  printf("%zu %zu %d %d\n", sizeof(struct B), offsetof(struct B,i), b.c, b.i);
  return 0; }
EOF
  ./build/nucleusc "$d/run.nuc" -o "$d/run.bin" 2>"$d/run.err" || ok=0
  if command -v cc >/dev/null 2>&1; then
    cc -w "$d/run.c" -o "$d/run.cbin" 2>/dev/null || ok=0
    [ -x "$d/run.bin" ] && [ -x "$d/run.cbin" ] &&
      [ "$("$d/run.bin")" = "$("$d/run.cbin")" ] || ok=0
    if [ "$ok" = 1 ]; then echo "PASS  s16-pk3-values"; else
      echo "FAIL  s16-pk3-values"
      sed 's/^/    /' "$d/run.err" | head -3
      [ -x "$d/run.cbin" ] && echo "    cc:      $("$d/run.cbin")"
      [ -x "$d/run.bin" ] && echo "    nucleus: $("$d/run.bin")"
    fi
  else
    echo "PASS  s16-pk3-values (SKIP: no cc)"
  fi

  # 4. Import side: every position C honours, plus the `__alignof__(T)` argument
  #    form — the idiom that PINS a member's alignment rather than raising it,
  #    and the one that matters, since it is what `max_align_t` is made of.
  ok=1
  cat > "$d/h.h" <<'EOF'
struct __attribute__((aligned(16))) AL1 { int x; };
struct AL2 { int x; } __attribute__((aligned(16)));
typedef struct { int x; } __attribute__((aligned(32))) AL3;
struct AL4 { char c; int i __attribute__((aligned(16))); };
struct AL5 { char c; long l __attribute__((__aligned__(__alignof__(long)))); };
struct __attribute__((packed, aligned(4))) AL6 { char c; int i; };
EOF
  cat > "$d/h.nuc" <<EOF
(import-use "stdio.h")
(import-use "$d/h.h")
(defn main ():i32
  (printf "%ld %ld %ld %ld %ld %ld\n" (sizeof AL1) (sizeof AL2) (sizeof AL3)
    (sizeof AL4) (sizeof AL5) (sizeof AL6))
  (return 0))
EOF
  ./build/nucleusc "$d/h.nuc" -o "$d/h.bin" 2>"$d/h.err" || ok=0
  if command -v cc >/dev/null 2>&1; then
    cat > "$d/h.c" <<EOF
#include <stdio.h>
#include "$d/h.h"
int main(void){ printf("%zu %zu %zu %zu %zu %zu\n", sizeof(struct AL1),
  sizeof(struct AL2), sizeof(AL3), sizeof(struct AL4), sizeof(struct AL5),
  sizeof(struct AL6)); return 0; }
EOF
    cc -w "$d/h.c" -o "$d/h.cbin" 2>/dev/null || ok=0
    [ -x "$d/h.bin" ] && [ -x "$d/h.cbin" ] &&
      [ "$("$d/h.bin")" = "$("$d/h.cbin")" ] || ok=0
    if [ "$ok" = 1 ]; then echo "PASS  s16-pk3-import-positions"; else
      echo "FAIL  s16-pk3-import-positions"
      sed 's/^/    /' "$d/h.err" | head -3
      [ -x "$d/h.cbin" ] && echo "    cc:      $("$d/h.cbin")"
      [ -x "$d/h.bin" ] && echo "    nucleus: $("$d/h.bin")"
    fi
  else
    echo "PASS  s16-pk3-import-positions (SKIP: no cc)"
  fi

  # 5. `max_align_t` — cheader-parser-vs-libclang.md §1 listed it among the nine
  #    blocked types, misattributed to `long double`; the actual blocker is the
  #    member `__attribute__((__aligned__(…)))` in clang's own definition.
  ok=1
  if command -v cc >/dev/null 2>&1; then
    printf '(import-use "stddef.h")\n(import-use "stdio.h")\n(defn main ():i32 (printf "%%ld\\n" (sizeof max_align_t)) (return 0))\n' > "$d/ma.nuc"
    printf '#include <stdio.h>\n#include <stddef.h>\nint main(void){printf("%%zu\\n",sizeof(max_align_t));return 0;}\n' > "$d/ma.c"
    ./build/nucleusc "$d/ma.nuc" -o "$d/ma.bin" 2>"$d/ma.err" || ok=0
    cc -w "$d/ma.c" -o "$d/ma.cbin" 2>/dev/null || ok=0
    if [ "$ok" = 1 ] && [ "$("$d/ma.bin")" = "$("$d/ma.cbin")" ]; then
      echo "PASS  s16-pk3-max-align-t ($("$d/ma.bin") bytes, matching cc)"
    else
      echo "FAIL  s16-pk3-max-align-t"
      sed 's/^/    /' "$d/ma.err" | head -3
      [ -x "$d/ma.bin" ] && echo "    nucleus: $("$d/ma.bin")"
      [ -x "$d/ma.cbin" ] && echo "    cc:      $("$d/ma.cbin")"
    fi
  else
    echo "PASS  s16-pk3-max-align-t (SKIP: no cc)"
  fi

  # 6. Export side: both attributes are written back out, at the struct and at
  #    the member, and a C consumer agrees on the sizes they produce.
  ok=1
  cat > "$d/x.nuc" <<'EOF'
(defstruct :align 32 Cache x:i64)
(defstruct Slot c:i8 (:align 16 v:i32))
(defn slot-v (s:ptr:Slot):i32 (return (get s 'v)))
EOF
  ./build/nucleusc --emit-cheader "$d/x.nuc" > "$d/x.h" 2>"$d/x.err" || ok=0
  qgrep -F '} __attribute__((aligned(32))) Cache;' "$d/x.h" || ok=0
  qgrep -F '__attribute__((aligned(16)))' "$d/x.h" || ok=0
  if command -v clang >/dev/null 2>&1; then
    cat > "$d/x-c.c" <<EOF
#include "$d/x.h"
_Static_assert(sizeof(Cache)==32,"cache");
_Static_assert(sizeof(Slot)==32,"slot");
EOF
    clang -std=gnu11 -Wall -Wextra -Werror -c "$d/x-c.c" -o /dev/null 2>"$d/x-c.err" || ok=0
  fi
  if [ "$ok" = 1 ]; then echo "PASS  s16-pk3-cheader-roundtrip"; else
    echo "FAIL  s16-pk3-cheader-roundtrip"
    sed 's/^/    /' "$d/x.err" "$d/x-c.err" 2>/dev/null | head -6
    grep -E 'Cache|Slot|aligned' "$d/x.h" | sed 's/^/    /' | head -6
  fi

  # 7. A non-power-of-two alignment is refused rather than reaching LLVM as an
  #    unparseable `align 3`, and an `aligned(N)` whose N we cannot evaluate
  #    leaves the C type opaque WITH a reason instead of a guessed layout.
  ok=1
  printf '(defstruct :align 3 S x:i32)\n(defn main ():i32 (return 0))\n' > "$d/bad.nuc"
  ./build/nucleusc --emit-llvm "$d/bad.nuc" >/dev/null 2>"$d/bad.err" || true
  qgrep -F "':align 3' must be a power of two" "$d/bad.err" || ok=0
  printf 'struct __attribute__((aligned(NOPE))) UA { int x; };\n' > "$d/ua.h"
  cat > "$d/ua.nuc" <<EOF
(import-use "$d/ua.h")
(defn main ():i32 (return (as i32 (sizeof UA))))
EOF
  ./build/nucleusc --emit-llvm "$d/ua.nuc" >/dev/null 2>"$d/ua.err" || true
  qgrep -F "is an opaque type declared at" "$d/ua.err" || ok=0
  if [ "$ok" = 1 ]; then echo "PASS  s16-pk3-bad-align-refused"; else
    echo "FAIL  s16-pk3-bad-align-refused"
    sed 's/^/    /' "$d/bad.err" "$d/ua.err" 2>/dev/null | head -6
  fi
  rm -rf "$d"
}
spawn run_s16_pk3_aligned

# --- Stage 16 §8: bitfields (BF-1…BF-4) ---------------------------------------
# design/stage16-ergonomics/c-boundary-defects.md §8. `(:bits 24 flags2:i32)` on
# the declaring side, `: 24` on the importing side. Several Nucleus fields share
# one storage unit, which is the invariant FR-1 had to break first — so every
# assertion here is really about `struct-walk` being the one place the layout is
# decided, and about the shift/mask access agreeing with what C compiled.
run_s16_bf_bitfields() {
  local d ok=1 t nt
  d="$(mktemp -d)"

  cat > "$d/bt.nuc" <<'EOF'
(defstruct A (:bits 3 a:i32) (:bits 5 b:ui32) (:bits 24 c:i32) d:i32)
(defstruct B c:i8 (:bits 3 a:i32))
(defstruct C (:bits 1 x:ui32) (:bits 0 z:ui32) (:bits 1 y:ui32))
(defstruct D (:bits 31 a:ui32) (:bits 2 b:ui32))
(defstruct E c:i8 (:bits 40 l:i64))
(defstruct :packed F c:i8 (:bits 3 a:i32) (:bits 30 b:i32))
(defstruct G (:bits 9 s:i16) c:i8 (:bits 20 i:i32))
(defstruct H (:bits 3 a:ui32) (:bits 3 b:ui32))
(defstruct I (:bits 31 a:ui32) (:bits 2 b:ui32) (:bits 31 c:ui32))
(defstruct J c:i8 (:bits 0 z:ui32) d:i8)
(defstruct :packed K (:bits 1 x:ui32) (:bits 0 z:ui32) (:bits 1 y:ui32))
(defvar sA:i64 (sizeof A))
(defvar sB:i64 (sizeof B))
(defvar sC:i64 (sizeof C))
(defvar sD:i64 (sizeof D))
(defvar sE:i64 (sizeof E))
(defvar sF:i64 (sizeof F))
(defvar sG:i64 (sizeof G))
(defvar sH:i64 (sizeof H))
(defvar sI:i64 (sizeof I))
(defvar sJ:i64 (sizeof J))
(defvar sK:i64 (sizeof K))
EOF
  # Fixed-width C types, so the same eight shapes are legal on every target —
  # `int c:24` would be a hard error on AVR, where `int` is 16 bits.
  cat > "$d/bt.c" <<'EOF'
#include <stdint.h>
struct A { int32_t a:3; uint32_t b:5; int32_t c:24; int32_t d; };
struct B { int8_t c; int32_t a:3; };
struct C { uint32_t x:1; uint32_t :0; uint32_t y:1; };
struct D { uint32_t a:31; uint32_t b:2; };
struct E { int8_t c; int64_t l:40; };
struct __attribute__((packed)) F { int8_t c; int32_t a:3; int32_t b:30; };
struct G { int16_t s:9; int8_t c; int32_t i:20; };
struct H { uint32_t a:3; uint32_t b:3; };
struct I { uint32_t a:31; uint32_t b:2; uint32_t c:31; };
struct J { int8_t c; uint32_t :0; int8_t d; };
struct __attribute__((packed)) K { uint32_t x:1; uint32_t :0; uint32_t y:1; };
EOF

  # 1. The allocator, against clang, on every target. The rules it encodes —
  #    "may not cross a boundary of the declared type", "a zero-width member
  #    forces that boundary", "packed drops the crossing rule but not the
  #    zero-width one", "AVR drops the crossing rule and makes zero-width's
  #    boundary a byte" — are exactly the parts C leaves implementation-defined,
  #    so matching the platform compiler IS the specification. I/J/K are the
  #    shapes that tell those four apart; A-H alone cannot.
  if ! command -v clang >/dev/null 2>&1; then
    echo "PASS  s16-bf-layout-cross-target (SKIP: no clang)"
  else
    for t in x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu \
             riscv64-unknown-linux-gnu i386-unknown-linux-gnu avr; do
      nt="$t"; [ "$t" = avr ] && nt=avr-unknown-unknown-elf
      ./build/nucleusc --target="$nt" --emit-llvm "$d/bt.nuc" > "$d/bt.ll" 2>/dev/null || true
      { cat "$d/bt.c"
        sed -nE 's/^@s([A-K]) = global i64 ([0-9]+).*/_Static_assert(sizeof(struct \1)==\2,"\1");/p' "$d/bt.ll"
      } > "$d/bk-$t.c"
      [ "$(grep -c _Static_assert "$d/bk-$t.c")" = 11 ] || ok=0
      clang --target="$t" -ffreestanding -fsyntax-only "$d/bk-$t.c" 2>"$d/bk-$t.err" || ok=0
      grep -q 'error' "$d/bk-$t.err" && ok=0
    done
    if [ "$ok" = 1 ]; then echo "PASS  s16-bf-layout-cross-target (11 shapes x 5 targets)"; else
      echo "FAIL  s16-bf-layout-cross-target"
      grep -h 'error' "$d"/bk-*.err | sed 's/^/    /' | head -10
    fi
  fi

  # 2. The values. A correct offset with a wrong shift or mask is invisible to a
  #    layout diff, which is why §11 asks for this one specifically: write a
  #    pattern through every bitfield and read it back, against the identical C
  #    program. Signed truncation, an unsigned neighbour, a field that crosses a
  #    natural boundary inside a packed struct, and a struct literal.
  ok=1
  cat > "$d/v.nuc" <<'EOF'
(import-use "stdio.h")
(defstruct A (:bits 3 a:i32) (:bits 5 b:ui32) (:bits 24 c:i32) d:i32)
(defstruct :packed F c:i8 (:bits 3 a:i32) (:bits 30 b:i32))
(defn main ():i32
  (let (p:ptr:A (alloca A))
    (set! (p 'a) -3) (set! (p 'b) 21) (set! (p 'c) -100000) (set! (p 'd) 7)
    (printf "%ld %d %d %d %d\n" (sizeof A) (get p 'a) (as i32 (get p 'b)) (get p 'c) (get p 'd)))
  (let (q:ptr:F (alloca F))
    (set! (q 'c) 65) (set! (q 'a) 2) (set! (q 'b) 123456789)
    (printf "%ld %d %d %d\n" (sizeof F) (as i32 (get q 'c)) (get q 'a) (get q 'b)))
  (let (r:ptr:A (A 1 2 3 4))
    (printf "%d %d %d %d\n" (get r 'a) (as i32 (get r 'b)) (get r 'c) (get r 'd)))
  (return 0))
EOF
  cat > "$d/v.c" <<'EOF'
#include <stdio.h>
struct A { int a:3; unsigned b:5; int c:24; int d; };
struct __attribute__((packed)) F { char c; int a:3; int b:30; };
int main(void){
  struct A p; p.a=-3; p.b=21; p.c=-100000; p.d=7;
  printf("%zu %d %d %d %d\n", sizeof(struct A), p.a, p.b, p.c, p.d);
  struct F q; q.c=65; q.a=2; q.b=123456789;
  printf("%zu %d %d %d\n", sizeof(struct F), q.c, q.a, q.b);
  struct A r = {1,2,3,4};
  printf("%d %d %d %d\n", r.a, r.b, r.c, r.d);
  return 0; }
EOF
  ./build/nucleusc "$d/v.nuc" -o "$d/v.bin" 2>"$d/v.err" || ok=0
  if command -v cc >/dev/null 2>&1; then
    cc -w "$d/v.c" -o "$d/v.cbin" 2>/dev/null || ok=0
    [ -x "$d/v.bin" ] && [ -x "$d/v.cbin" ] &&
      [ "$("$d/v.bin")" = "$("$d/v.cbin")" ] || ok=0
    if [ "$ok" = 1 ]; then echo "PASS  s16-bf-values"; else
      echo "FAIL  s16-bf-values"
      sed 's/^/    /' "$d/v.err" | head -3
      [ -x "$d/v.cbin" ] && "$d/v.cbin" | sed 's/^/    cc:      /'
      [ -x "$d/v.bin" ] && "$d/v.bin" | sed 's/^/    nucleus: /'
    fi
  else
    echo "PASS  s16-bf-values (SKIP: no cc)"
  fi

  # 3. BF-4, the importer: `: width`, unnamed members, a zero-width boundary,
  #    and the same declaration reached through a typedef.
  ok=1
  cat > "$d/h.h" <<'EOF'
struct BI1 { int a:3; unsigned b:5; int c:24; int d; };
struct BI2 { unsigned x:1; unsigned :3; unsigned y:1; };
struct BI3 { unsigned x:1; unsigned :0; unsigned y:1; };
typedef struct { char c; int a:3; } BI4;
struct __attribute__((packed)) BI5 { char c; int a:3; int b:30; };
EOF
  cat > "$d/h.nuc" <<EOF
(import-use "stdio.h")
(import-use "$d/h.h")
(defn main ():i32
  (let (p:ptr:BI1 (alloca BI1))
    (set! (p 'a) -3) (set! (p 'b) 21) (set! (p 'c) -100000) (set! (p 'd) 7)
    (printf "%ld %ld %ld %ld %ld %d %d %d %d\n" (sizeof BI1) (sizeof BI2)
      (sizeof BI3) (sizeof BI4) (sizeof BI5)
      (get p 'a) (as i32 (get p 'b)) (get p 'c) (get p 'd)))
  (return 0))
EOF
  ./build/nucleusc "$d/h.nuc" -o "$d/h.bin" 2>"$d/h.err" || ok=0
  if command -v cc >/dev/null 2>&1; then
    cat > "$d/h.c" <<EOF
#include <stdio.h>
#include "$d/h.h"
int main(void){ struct BI1 p; p.a=-3; p.b=21; p.c=-100000; p.d=7;
  printf("%zu %zu %zu %zu %zu %d %d %d %d\n", sizeof(struct BI1),
    sizeof(struct BI2), sizeof(struct BI3), sizeof(BI4), sizeof(struct BI5),
    p.a, p.b, p.c, p.d);
  return 0; }
EOF
    cc -w "$d/h.c" -o "$d/h.cbin" 2>/dev/null || ok=0
    [ -x "$d/h.bin" ] && [ -x "$d/h.cbin" ] &&
      [ "$("$d/h.bin")" = "$("$d/h.cbin")" ] || ok=0
    if [ "$ok" = 1 ]; then echo "PASS  s16-bf-import"; else
      echo "FAIL  s16-bf-import"
      sed 's/^/    /' "$d/h.err" | head -3
      [ -x "$d/h.cbin" ] && echo "    cc:      $("$d/h.cbin")"
      [ -x "$d/h.bin" ] && echo "    nucleus: $("$d/h.bin")"
    fi
  else
    echo "PASS  s16-bf-import (SKIP: no cc)"
  fi

  # 4. `FILE` — the marquee casualty in cheader-parser-vs-libclang.md §1, opaque
  #    for one reason (`int _flags2:24`). Nine blocked types become seven.
  ok=1
  if command -v cc >/dev/null 2>&1; then
    printf '(import-use "stdio.h")\n(defn main ():i32 (printf "%%ld\\n" (sizeof FILE)) (return 0))\n' > "$d/f.nuc"
    printf '#include <stdio.h>\nint main(void){printf("%%zu\\n",sizeof(FILE));return 0;}\n' > "$d/f.c"
    ./build/nucleusc "$d/f.nuc" -o "$d/f.bin" 2>"$d/f.err" || ok=0
    cc -w "$d/f.c" -o "$d/f.cbin" 2>/dev/null || ok=0
    if [ "$ok" = 1 ] && [ "$("$d/f.bin")" = "$("$d/f.cbin")" ]; then
      echo "PASS  s16-bf-file ($("$d/f.bin") bytes, matching cc)"
    else
      echo "FAIL  s16-bf-file"
      sed 's/^/    /' "$d/f.err" | head -3
      [ -x "$d/f.bin" ] && echo "    nucleus: $("$d/f.bin")"
      [ -x "$d/f.cbin" ] && echo "    cc:      $("$d/f.cbin")"
    fi
  else
    echo "PASS  s16-bf-file (SKIP: no cc)"
  fi

  # 5. Export: `--emit-cheader` writes `: w` back out and a C consumer agrees.
  ok=1
  cat > "$d/x.nuc" <<'EOF'
(defstruct Hdr (:bits 4 ver:ui32) (:bits 12 len:ui32) (:bits 16 id:i32) tail:i32)
(defn hdr-ver (h:ptr:Hdr):ui32 (return (get h 'ver)))
EOF
  ./build/nucleusc --emit-cheader "$d/x.nuc" > "$d/x.h" 2>"$d/x.err" || ok=0
  qgrep -E ': 4;' "$d/x.h" || ok=0
  if command -v clang >/dev/null 2>&1; then
    cat > "$d/x-c.c" <<EOF
#include "$d/x.h"
_Static_assert(sizeof(Hdr)==8,"hdr");
EOF
    clang -std=gnu11 -Wall -Wextra -Werror -c "$d/x-c.c" -o /dev/null 2>"$d/x-c.err" || ok=0
  fi
  if [ "$ok" = 1 ]; then echo "PASS  s16-bf-cheader-roundtrip"; else
    echo "FAIL  s16-bf-cheader-roundtrip"
    sed 's/^/    /' "$d/x.err" "$d/x-c.err" 2>/dev/null | head -6
    grep -E 'Hdr|:' "$d/x.h" | sed 's/^/    /' | head -8
  fi

  # 6. The three things a bit-field may not be. A field address is C's own constraint, not
  #    a Nucleus limitation, which is what makes refusing it the faithful
  #    answer rather than a gap.
  ok=1
  printf '(defstruct S (:bits 3 a:i32))\n(defn f (p:ptr:S):ptr (return (addr-of p '\''a)))\n(defn main ():i32 (return 0))\n' > "$d/e1.nuc"
  ./build/nucleusc --emit-llvm "$d/e1.nuc" >/dev/null 2>"$d/e1.err" || true
  qgrep -F "a bit-field has no address" "$d/e1.err" || ok=0
  printf '(defstruct S (:bits 40 a:i32))\n(defn main ():i32 (return 0))\n' > "$d/e2.nuc"
  ./build/nucleusc --emit-llvm "$d/e2.nuc" >/dev/null 2>"$d/e2.err" || true
  qgrep -F "exceeds the 32 bits of its declared type" "$d/e2.err" || ok=0
  printf '(defstruct S (:bits 3 a:f32))\n(defn main ():i32 (return 0))\n' > "$d/e3.nuc"
  ./build/nucleusc --emit-llvm "$d/e3.nuc" >/dev/null 2>"$d/e3.err" || true
  qgrep -F "must have an integer type" "$d/e3.err" || ok=0
  if [ "$ok" = 1 ]; then echo "PASS  s16-bf-refusals"; else
    echo "FAIL  s16-bf-refusals"
    sed 's/^/    /' "$d/e1.err" "$d/e2.err" "$d/e3.err" 2>/dev/null | head -8
  fi
  rm -rf "$d"
}
spawn run_s16_bf_bitfields

# Stage 16 AN-1/AN-2 + C1a — C11 anonymous members, and the flexible array
# member that closes the census with them
# (design/stage16-ergonomics/c-boundary-defects.md §9, §11).
#
# An anonymous member is an ordinary nested member whose OWN names are the ones
# visible from outside, so the whole feature is a transitive lookup over FR-1's
# path. Every check below therefore compares against the identical C program:
# the outside names must resolve to the same bytes clang resolves them to, not
# merely to some consistent bytes of our own.
run_s16_an_anonymous() {
  local d ok=1
  d="$(mktemp -d)"

  # 1. Import. Two levels of minted name (a struct inside an anonymous union
  #    inside a struct), a named member of an anonymous type beside them, and
  #    an anonymous struct that opens a declaration — the three shapes glibc
  #    uses. Values AND sizes, against the same header compiled by cc.
  cat > "$d/a.nuc" <<'EOF'
(import-use "stdio.h")
(import-use "tests/fixtures/s16-anon.h")
(defn main ():i32
  (let (s:ptr:s16_sig (alloca s16_sig))
    (set! (s 'code) 7) (set! (s 'pid) 42) (set! (s 'uid) 99)
    (set! ((addr-of s 'named) 'a) 1) (set! ((addr-of s 'named) 'b) 2)
    (printf "%d %d %d %d %d %d\n" (get s 'code) (get s 'pid) (get s 'uid) (get s 'si_int)
            (get (addr-of s 'named) 'a) (get (addr-of s 'named) 'b)))
  (let (r:ptr:s16_rus (alloca s16_rus))
    (set! (r 'sec) 5) (set! (r 'usec) 6) (set! (r 'maxrss) 8)
    (printf "%ld %ld %d %ld %ld\n" (get r 'sec) (get r 'usec) (get r 'maxrss)
            (sizeof s16_sig) (sizeof s16_rus)))
  (return 0))
EOF
  cat > "$d/a.c" <<'EOF'
#include <stdio.h>
#include "tests/fixtures/s16-anon.h"
int main(void){
  s16_sig s; s.code=7; s.pid=42; s.uid=99; s.named.a=1; s.named.b=2;
  printf("%d %d %d %d %d %d\n", s.code, s.pid, s.uid, s.si_int, s.named.a, s.named.b);
  s16_rus r; r.sec=5; r.usec=6; r.maxrss=8;
  printf("%ld %ld %d %zu %zu\n", r.sec, r.usec, r.maxrss, sizeof(s16_sig), sizeof(s16_rus));
  return 0; }
EOF
  ./build/nucleusc "$d/a.nuc" -o "$d/a.nucbin" 2>"$d/a.err" || ok=0
  [ "$ok" = 1 ] && "$d/a.nucbin" > "$d/a.nucout" 2>&1
  if cc -I. "$d/a.c" -o "$d/a.cbin" 2>>"$d/a.err"; then
    "$d/a.cbin" > "$d/a.cout" 2>&1
    diff "$d/a.cout" "$d/a.nucout" > "$d/a.diff" 2>&1 || ok=0
  else
    ok=0
  fi
  if [ "$ok" = 1 ]; then echo "PASS  s16-an-import ($(cat "$d/a.nucout" | tr '\n' '/'))"; else
    echo "FAIL  s16-an-import"
    sed 's/^/    /' "$d/a.err" 2>/dev/null | head -4
    sed 's/^/    /' "$d/a.diff" 2>/dev/null | head -6
  fi

  # 2. The census (§11) is the acceptance test for §§6-9, and these are the nine
  #    names it listed as blocked. All nine must now emit a `%Name = type` line;
  #    a regression in any one of the four features shows up here by name.
  ok=1
  cat > "$d/n.nuc" <<'EOF'
(import-use "signal.h")
(import-use "pthread.h")
(import-use "sys/resource.h")
(import-use "stdio.h")
(import-use "sys/socket.h")
(import-use "stddef.h")
(defn main ():i32 (return 0))
EOF
  ./build/nucleusc --emit-llvm "$d/n.nuc" > "$d/n.ll" 2>"$d/n.err" || ok=0
  local t missing=""
  for t in sigaction sigevent __pthread_cleanup_frame _pthread_cleanup_buffer \
           sigcontext rusage _IO_FILE cmsghdr max_align_t; do
    qgrep -E "^%$t = type" "$d/n.ll" || { ok=0; missing="$missing $t"; }
  done
  if [ "$ok" = 1 ]; then echo "PASS  s16-an-census (9 of 9 formerly-blocked types lay out)"; else
    echo "FAIL  s16-an-census (still blocked:$missing)"
  fi

  # 3. `sizeof` on the two the anonymous-member work unblocked, against cc.
  #    A layout that is merely PRESENT is the weaker claim; these are the names
  #    §1 of cheader-parser-vs-libclang.md listed, so they are the ones to size.
  ok=1
  cat > "$d/s.nuc" <<'EOF'
(import-use "stdio.h")
(import-use "signal.h")
(import-use "sys/resource.h")
(import-use "sys/socket.h")
(defn main ():i32
  (printf "%ld %ld %ld\n" (sizeof sigcontext) (sizeof rusage) (sizeof cmsghdr))
  (return 0))
EOF
  cat > "$d/s.c" <<'EOF'
#include <stdio.h>
#include <signal.h>
#include <sys/resource.h>
#include <sys/socket.h>
int main(void){ printf("%zu %zu %zu\n", sizeof(struct sigcontext),
  sizeof(struct rusage), sizeof(struct cmsghdr)); return 0; }
EOF
  ./build/nucleusc "$d/s.nuc" -o "$d/s.nucbin" 2>"$d/s.err" || ok=0
  [ "$ok" = 1 ] && "$d/s.nucbin" > "$d/s.nucout" 2>&1
  if cc "$d/s.c" -o "$d/s.cbin" 2>>"$d/s.err"; then
    "$d/s.cbin" > "$d/s.cout" 2>&1
    diff "$d/s.cout" "$d/s.nucout" > "$d/s.diff" 2>&1 || ok=0
  else
    ok=0
  fi
  if [ "$ok" = 1 ]; then echo "PASS  s16-an-census-sizeof ($(cat "$d/s.nucout"), matching cc)"; else
    echo "FAIL  s16-an-census-sizeof"
    sed 's/^/    /' "$d/s.diff" 2>/dev/null | head -6
  fi

  # 4. The `defstruct` surface. `(:anon T)` is the same member the importer
  #    mints, so the same lookup has to reach it — including through `addr-of`,
  #    which is the path a GEP chain gets wrong differently from a load.
  ok=1
  cat > "$d/g.nuc" <<'EOF'
(import-use "stdio.h")
(defstruct Inner a:i32 b:i32)
(defstruct Extra c:i32)
(defstruct Outer tag:i32 (:anon Inner) (:anon Extra) z:i32)
(defn main ():i32
  (let (p:ptr:Outer (alloca Outer))
    (set! (p 'tag) 1) (set! (p 'a) 2) (set! (p 'b) 3) (set! (p 'c) 4) (set! (p 'z) 5)
    (printf "%ld %d %d %d %d %d %d\n" (sizeof Outer)
            (get p 'tag) (get p 'a) (get p 'b) (get p 'c) (get p 'z) (deref (addr-of p 'b))))
  (return 0))
EOF
  ./build/nucleusc "$d/g.nuc" -o "$d/g" 2>"$d/g.err" || ok=0
  [ "$ok" = 1 ] && "$d/g" > "$d/g.out" 2>&1
  qgrep -Fx "20 1 2 3 4 5 3" "$d/g.out" || ok=0
  if [ "$ok" = 1 ]; then echo "PASS  s16-an-defstruct"; else
    echo "FAIL  s16-an-defstruct"
    sed 's/^/    /' "$d/g.err" 2>/dev/null | head -4
    sed 's/^/    got: /' "$d/g.out" 2>/dev/null | head -2
  fi

  # 5. The three refusals. The first is C's own ambiguity rule; the second is
  #    a member that could not contribute a name at all; the third is the one
  #    place the surface is NOT a superset of C — C spells an anonymous member
  #    by inlining its body, so a named type has no rendering on export.
  ok=1
  printf '(defstruct A dup:i32 x:i32)\n(defstruct B dup:i32 y:i32)\n(defstruct C (:anon A) (:anon B))\n(defn f (p:ptr:C):i32 (return (get p '\''dup)))\n(defn main ():i32 (return 0))\n' > "$d/r1.nuc"
  ./build/nucleusc --emit-llvm "$d/r1.nuc" >/dev/null 2>"$d/r1.err" || true
  qgrep -F "more than one anonymous member supplies it" "$d/r1.err" || ok=0
  printf '(defstruct D (:anon i32))\n(defn main ():i32 (return 0))\n' > "$d/r2.nuc"
  ./build/nucleusc --emit-llvm "$d/r2.nuc" >/dev/null 2>"$d/r2.err" || true
  qgrep -F "must be a struct or a union, not i32" "$d/r2.err" || ok=0
  printf '(defstruct A dup:i32)\n(defstruct C (:anon A) z:i32)\n(defn main ():i32 (return 0))\n' > "$d/r3.nuc"
  ./build/nucleusc --emit-cheader "$d/r3.nuc" >/dev/null 2>"$d/r3.err" || true
  qgrep -F "has no standard C spelling" "$d/r3.err" || ok=0
  if [ "$ok" = 1 ]; then echo "PASS  s16-an-refusals"; else
    echo "FAIL  s16-an-refusals"
    sed 's/^/    /' "$d/r1.err" "$d/r2.err" "$d/r3.err" 2>/dev/null | head -8
  fi

  rm -rf "$d"
}
spawn run_s16_an_anonymous

# W9 item 13: an unrecognized list head in type position used to fall out of
# `parse-type-from-node` as null, which every caller reads as "no annotation was
# written". Four positions, one shared fall-through — if a future change patches
# a single caller instead of the predicate, the other three fixtures fail. The
# `-unimported` case is the everyday one (a forgotten `import-use`) and pins
# that the fix reuses `unknown-type-message`'s tiers rather than a local string;
# the `-return` case pins the `:0:` half, which `run_reject` checks on its own.
spawn run_reject w9-unknown-type-ctor-field \
  tests/fixtures/w9-unknown-type-ctor-field.nuc \
  "unknown type: nosuch — not defined anywhere in this compilation unit"
spawn run_reject w9-unknown-type-ctor-param \
  tests/fixtures/w9-unknown-type-ctor-param.nuc \
  "unknown type: nosuch — not defined anywhere in this compilation unit"
spawn run_reject w9-unknown-type-ctor-return \
  tests/fixtures/w9-unknown-type-ctor-return.nuc \
  "unknown type: nosuch — not defined anywhere in this compilation unit"
spawn run_reject w9-unknown-type-ctor-unimported \
  tests/fixtures/w9-unknown-type-ctor-unimported.nuc \
  "'Vector' is defined in lib/vector.nuch, which no import in this unit reaches"
# The other mistake class at the same fall-through: a head that IS a type. One
# message for both would lie about this one.
spawn run_reject w9-type-ctor-doubled-annotation \
  tests/fixtures/w9-type-ctor-doubled-annotation.nuc \
  "'i32' is a type, not a type constructor"

# Stage 14 unsafe-namespace.md UN-2 — `unsafe` is a reserved pseudo-namespace
# (D1): no user code may declare `(ns unsafe)`, which would make `unsafe/foo`
# ambiguous between a reserved op and a real namespace member. (The positive
# `examples/unsafe-spellings.nuc` run — dispatched via the examples/*.nuc loop
# above — covers `as` and the unsafe/cast, unsafe/ptr+, unsafe/funcall-ptr-i32,
# and unsafe/import-private routes.)
spawn run_reject unsafe-ns-reserved-rejected tests/fixtures/unsafe-ns-reserved.nuc \
  "'unsafe' is a reserved namespace name"

# Stage 14 unsafe-namespace.md UN-5 — the bare legacy spellings (`cast`,
# `funcall-ptr-*`, `ptr+`, `unsafe-import-private`) are retired: each dispatch
# site now dies with a targeted error naming its replacement instead of
# silently working as an alias (D6).
spawn run_reject un5-bare-cast-rejected tests/fixtures/un5-bare-cast.nuc \
  "'cast' was split in Stage 14: use 'as' (safe) or 'unsafe/cast' (unchecked)"
spawn run_reject un5-bare-ptr-plus-rejected tests/fixtures/un5-bare-ptr-plus.nuc \
  "'ptr+' was split in Stage 14: use 'unsafe/ptr+'"
spawn run_reject un5-bare-funcall-ptr-rejected tests/fixtures/un5-bare-funcall-ptr.nuc \
  "'funcall-ptr-i32' was split in Stage 14: use 'unsafe/funcall-ptr-i32'"
spawn run_reject un5-bare-import-private-rejected tests/fixtures/un5-bare-import-private.nuc \
  "'unsafe-import-private' was split in Stage 14: use 'unsafe/import-private'"

# Stage 14 attributes.md AT-3 — the old postfix volatile spellings are retired:
# both the list form `(T volatile)` and the colon-sugared `T:volatile` (which
# reduces to the same trailing-symbol shape via split-colon-segments) now die
# with a targeted error naming the `:volatile` attribute-slot replacement,
# instead of silently stripping the trailing symbol and calling
# type-with-volatile as before AT-3.
spawn run_reject at3-postfix-volatile-rejected tests/fixtures/at3-postfix-volatile.nuc \
  "postfix 'volatile' is retired: use the ':volatile' attribute"
spawn run_reject at3-colon-volatile-rejected tests/fixtures/at3-colon-volatile.nuc \
  "postfix 'volatile' is retired: use the ':volatile' attribute"

# --- Stage 15 W5a: `\x` string escapes --------------------------------------
# design/stage15-stress-test/ergonomics.md §W5a. A `\x` escape with no
# following hex digit is a reader error. The pattern includes the `:6:` line
# prefix on purpose: the diagnostic must be attributed to the literal's own
# line, never line 0 (cf. run_no_line_zero).
spawn run_reject w5a-hex-escape-no-digit-rejected tests/fixtures/w5a-hex-escape-no-digit.nuc \
  "w5a-hex-escape-no-digit.nuc:6: error: \\x escape needs at least one hex digit"

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
spawn run_reject_at w2a-mixed-sign tests/fixtures/w2a-mixed-sign.nuc \
  "tests/fixtures/w2a-mixed-sign.nuc:10: error:" \
  "mixed signed/unsigned operands — use explicit cast"
spawn run_reject_at w2a-mixed-sign-cmp tests/fixtures/w2a-mixed-sign-cmp.nuc \
  "tests/fixtures/w2a-mixed-sign-cmp.nuc:11: error:" \
  ">: mixed signed/unsigned operands — use explicit cast"

# --- Stage 15 W2b: a named integer constant behaves like the literal ---------
# design/stage15-stress-test/literal-typing.md section W2b. The positive matrix
# (a defconst against {i32, i64, ui32, ui64} in both operand orders, each line
# paired with the identical inline-literal spelling; the enum-member case; the
# BIG-value case; the vararg path) is examples/defconst-literal-typing.nuc, run
# by the examples/*.nuc loop above. The committed boot compiler FAILS to compile
# that file, which is the teeth.
#
# Here: the negative half. Two properties must survive the fix -- the provenance
# is read through the SCOPE (so a shadowing local is not a literal), and it
# carries the VALUE (so an out-of-range narrowing is rejected rather than
# wrapped, at both the coerce-int-val chokepoint and the global-initializer
# path, and for a named constant exactly as for the literal it names).
spawn run_reject_at w2b-shadow-local tests/fixtures/w2b-shadow-local.nuc \
  "tests/fixtures/w2b-shadow-local.nuc:12: error:" \
  "<: mixed signed/unsigned operands — use explicit cast"
spawn run_reject_at w2b-const-narrow tests/fixtures/w2b-const-narrow.nuc \
  "tests/fixtures/w2b-const-narrow.nuc:10: error:" \
  "integer literal 5000000000 does not fit i32"
spawn run_reject_at w2b-defvar-const-narrow tests/fixtures/w2b-defvar-const-narrow.nuc \
  "tests/fixtures/w2b-defvar-const-narrow.nuc:7: error:" \
  "defvar: constant 'BIG' (5000000000) does not fit i32"
spawn run_reject_at w2b-defvar-lit-narrow tests/fixtures/w2b-defvar-lit-narrow.nuc \
  "tests/fixtures/w2b-defvar-lit-narrow.nuc:5: error:" \
  "defvar: integer literal 5000000000 does not fit i32"

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
spawn run_reject_at w2d-float-into-int tests/fixtures/w2d-float-into-int.nuc \
  "tests/fixtures/w2d-float-into-int.nuc:9: error:" \
  "let: init type mismatch for 'a'"
spawn run_reject_at w2d-mixed-float-int-binop tests/fixtures/w2d-mixed-float-int-binop.nuc \
  "tests/fixtures/w2d-mixed-float-int-binop.nuc:9: error:" \
  "mixed float and non-float operands — use explicit cast"
spawn run_reject_at w2d-dispatch-no-narrow tests/fixtures/w2d-dispatch-no-narrow.nuc \
  "tests/fixtures/w2d-dispatch-no-narrow.nuc:15: error:" \
  "no matching method for overloaded 'tk' with argument types (f64)"

# --- Stage 15 W4a: located diagnostics --------------------------------------
# design/stage15-stress-test/diagnostics.md §W4a. Every entry below reported
# `:0:` before W4a. The location is part of the assertion, not decoration.
spawn run_reject_at w4a-undefined-value tests/fixtures/w4a-undefined-value.nuc \
  "tests/fixtures/w4a-undefined-value.nuc:8: error:" "undefined: missing-thing"
spawn run_reject_at w4a-suggest-spelling tests/fixtures/w4a-suggest-spelling.nuc \
  "tests/fixtures/w4a-suggest-spelling.nuc:6: error:" "unknown: printfx (did you mean 'printf'?)"
spawn run_reject_at w4a-let-null-ref tests/fixtures/w4a-let-null-ref.nuc \
  "tests/fixtures/w4a-let-null-ref.nuc:7: error:" "raw pointer where non-null (ref ...) is required"
spawn run_reject_at w4a-bare-cast-head tests/fixtures/w4a-bare-cast-head.nuc \
  "tests/fixtures/w4a-bare-cast-head.nuc:7: error:" "'cast' was split in Stage 14"

# The two remaining Ground-truth cases (same-file defvar forward reference
# §3.5, `(defvar- g:CStr null)` §3.7) are covered by the sweep rather than a
# pinned message: W5 owns whether those spellings keep failing at all, and
# W4a's contract — a real location — holds either way. defconst-with-
# annotation (§3.2) is now pinned below (W4b decided: reject).
spawn run_no_line_zero
spawn run_w4a_sibling_forward

# --- Stage 15 W4b: defconst annotation rejected + sibling-definer sweep ----
# design/stage15-stress-test/diagnostics.md §W4b. `defconst` never takes a
# type annotation (its value is always ty-i32 from an integer literal), so
# `(defconst K:i32 2)` is rejected at its own line rather than silently
# registering nothing under the literal key "K:i32". The same silent-
# registration bug recurred, unannounced, in every sibling top-level definer
# whose own name is never annotated — each is pinned here too.
spawn run_reject_at w4a-defconst-annotated tests/fixtures/w4a-defconst-annotated.nuc \
  "tests/fixtures/w4a-defconst-annotated.nuc:7: error:" "defconst: takes no type annotation; write (defconst K 2)"
spawn run_reject_at w4b-defconst-paren tests/fixtures/w4b-defconst-paren.nuc \
  "tests/fixtures/w4b-defconst-paren.nuc:7: error:" "defconst: takes no type annotation; write (defconst K 2)"
spawn run_reject_at w4b-defenum-annotated tests/fixtures/w4b-defenum-annotated.nuc \
  "tests/fixtures/w4b-defenum-annotated.nuc:9: error:" "defenum: takes no type annotation; write (defenum E ...)"
spawn run_reject_at w4b-defstruct-annotated tests/fixtures/w4b-defstruct-annotated.nuc \
  "tests/fixtures/w4b-defstruct-annotated.nuc:9: error:" "defstruct: takes no type annotation; write (defstruct S ...)"
spawn run_reject_at w4b-defprotocol-annotated tests/fixtures/w4b-defprotocol-annotated.nuc \
  "tests/fixtures/w4b-defprotocol-annotated.nuc:9: error:" "defprotocol: takes no type annotation; write (defprotocol P ...)"
spawn run_reject_at w4b-defmacro-annotated tests/fixtures/w4b-defmacro-annotated.nuc \
  "tests/fixtures/w4b-defmacro-annotated.nuc:7: error:" "defmacro: takes no type annotation; write (defmacro m ...)"
spawn run_reject_at w4b-defunion-annotated tests/fixtures/w4b-defunion-annotated.nuc \
  "tests/fixtures/w4b-defunion-annotated.nuc:6: error:" "defunion: takes no type annotation; write (defunion U ...)"
spawn run_reject_at w4b-deferror-annotated tests/fixtures/w4b-deferror-annotated.nuc \
  "tests/fixtures/w4b-deferror-annotated.nuc:7: error:" "deferror: takes no type annotation; write (deferror MyErr \"message\")"
# Found (not silent, but wrong location) while sweeping defvar the same way:
# `(defvar x 3)` -- no annotation at all -- already died with the right
# message but at line 0 (name-node is a bare interned NODE-SYM).
spawn run_reject_at w4b-defvar-missing-type tests/fixtures/w4b-defvar-missing-type.nuc \
  "tests/fixtures/w4b-defvar-missing-type.nuc:9: error:" "defvar: missing :type on 'x'"

# --- Stage 15 W5f: an empty list `()` never segfaults ------------------------
# design/stage15-stress-test/ergonomics.md §W5f. `()` reads as a NULL node (an
# empty cons list), and a raw `(n kind)` / `(n line)` on it faults. Each fixture
# below was a confirmed SIGSEGV-with-no-output before W5f; run_reject_at fails on
# a crash too (no message to grep), so these double as segfault regressions.
spawn run_reject_at w5f-empty-union-member tests/fixtures/w5f-empty-union-member.nuc \
  "tests/fixtures/w5f-empty-union-member.nuc:11: error:" \
  "expected a name:type declaration, found the empty list '()'"
spawn run_reject_at w5f-empty-param tests/fixtures/w5f-empty-param.nuc \
  "tests/fixtures/w5f-empty-param.nuc:7: error:" \
  "expected a name:type declaration, found the empty list '()'"
spawn run_reject_at w5f-empty-expr tests/fixtures/w5f-empty-expr.nuc \
  "tests/fixtures/w5f-empty-expr.nuc:6: error:" \
  "'()' is not an expression -- the empty list has no value"
spawn run_reject_at w5f-empty-defunion-arm tests/fixtures/w5f-empty-defunion-arm.nuc \
  "tests/fixtures/w5f-empty-defunion-arm.nuc:4: error:" \
  "defunion: arm cannot be the empty list '()'"

# --- Stage 15 W4c: unterminated forms point at the imbalance -----------------
# design/stage15-stress-test/diagnostics.md §W4c. The reader already reported the
# innermost unclosed form's OPENING line; what it lacked was the second number --
# the first line that opens a new form in column 0 while a form is still open,
# which is where an earlier missing `)` first became observable. Each entry below
# pins BOTH: the `loc` argument carries the primary `path:line: error: message`
# and the `pattern` argument carries the note with the second number, so a
# regression in either half fails the test. (run_reject_at's loc is a literal
# grep -F, so it can pin the message text as well as the location.)
spawn run_reject_at w4c-unterminated-deep tests/fixtures/w4c-unterminated-deep.nuc \
  "tests/fixtures/w4c-unterminated-deep.nuc:12: error: unterminated list" \
  "note: line 23 starts a new form in column 0 while 1 form(s) are still open"
spawn run_reject_at w4c-unterminated-deep-many tests/fixtures/w4c-unterminated-deep-many.nuc \
  "tests/fixtures/w4c-unterminated-deep-many.nuc:12: error: unterminated list" \
  "note: line 18 starts a new form in column 0 while 6 form(s) are still open"
# No column-0 candidate exists (the imbalance is in the file's last form): the
# alternative note must appear, and since the two notes are the arms of one
# if/else, pinning this one also asserts no bogus second number is invented.
spawn run_reject_at w4c-unterminated-last-form tests/fixtures/w4c-unterminated-last-form.nuc \
  "tests/fixtures/w4c-unterminated-last-form.nuc:9: error: unterminated list" \
  "note: end of file reached with 3 form(s) still open"
# A bracket kind other than `(`: depth tracking spans ( [ { #{ , and the note
# names the closer the form is actually waiting for.
spawn run_reject_at w4c-unterminated-bracket tests/fixtures/w4c-unterminated-bracket.nuc \
  "tests/fixtures/w4c-unterminated-bracket.nuc:7: error: unterminated vector literal" \
  "note: line 9 starts a new form in column 0 while 4 form(s) are still open -- a ']' is probably missing"
# The extra-`)`-in-a-let-binding-list shape, both ways it can land: still
# balanced (caught at emit, in emit-let) and no longer balanced (caught by the
# reader at the excess `)`, with the note bounding the search to one form).
spawn run_reject_at w4c-let-extra-paren tests/fixtures/w4c-let-extra-paren.nuc \
  "tests/fixtures/w4c-let-extra-paren.nuc:11: error:" \
  "let: 'b:i32' is a body form, not a binding -- an extra ')' probably ended the binding list early"
spawn run_reject_at w4c-stray-close-paren tests/fixtures/w4c-stray-close-paren.nuc \
  "tests/fixtures/w4c-stray-close-paren.nuc:13: error: unexpected )" \
  "note: the form opened at line 10 is already closed -- look for an extra ')' between lines 10 and 13"

# --- Stage 15 W4d: errors that name the macro instead of the mistake ---------
# design/stage15-stress-test/diagnostics.md §W4d. `case`'s documented-but-wrong
# nested-clause shape used to die with the opaque "value is not callable: no
# `invoke` method is defined for this type" -- naming the mechanism (an int
# literal in call position), not the mistake. Fixed at the one chokepoint every
# non-callable head funnels through (emit-invoke-with-callee), not inside the
# `case` macro body: a macro body is ordinary user-scope Nucleus code and
# `die-at`/`report-at` are only in scope for the compiler's own source, not a
# user program's macro expansions (confirmed empirically -- a `defmacro` body
# calling `die-at` fails `unknown: die-at`).
spawn run_reject_at w4d-case-clause-form tests/fixtures/w4d-case-clause-form.nuc \
  "tests/fixtures/w4d-case-clause-form.nuc:16: error:" \
  "case takes flat value/result pairs, not clauses: (case x 1 \"one\" 2 \"two\" \"other\")"
# examples/case.nuc (the real flat syntax) is covered as a regression by the
# ordinary examples/*.nuc + tests/expected/case.out loop above -- no separate
# fixture needed here.
#
# One-armed `if` used to die with the generic, unlocated-by-name
# `macro: wrong number of args`. `if` is a fixed 3-arg macro
# (test/then/else); there is no one-armed `if`, only `when`/`unless`.
spawn run_reject_at w4d-if-one-armed tests/fixtures/w4d-if-one-armed.nuc \
  "tests/fixtures/w4d-if-one-armed.nuc:11: error:" \
  "if requires an else branch; use (when test then…) for a guard"
# The generic arg-count messages themselves, now naming the macro and both
# counts instead of the bare "macro: wrong number of args" / "macro: not
# enough args".
spawn run_reject_at w4d-macro-too-many-args tests/fixtures/w4d-macro-too-many-args.nuc \
  "tests/fixtures/w4d-macro-too-many-args.nuc:11: error:" \
  "macro 'for': expects 4 args, got 5"
spawn run_reject_at w4d-macro-too-few-args tests/fixtures/w4d-macro-too-few-args.nuc \
  "tests/fixtures/w4d-macro-too-few-args.nuc:12: error:" \
  "macro 'case': expects at least 1 args, got 0"

# --- Stage 15 W3a: opaque forward-declared C types ---------------------------
# design/stage15-stress-test/cheader.md §1.6. `struct Foo;` used to be skipped
# outright, so the type never registered and any later `ptr:Foo` died
# `unknown type: Foo` — C's standard opaque-handle idiom (FILE, SDL_Window,
# Mix_Music) was simply unusable. It now registers layout-less, is legal behind
# a pointer, and every by-value use is refused at its own line naming the header
# declaration. The runnable half is examples/cheader-opaque.nuc (a real
# fopen/fprintf/fgets round trip through `ptr:FILE`, plus forward-declaration-
# then-definition upgrades); the rejections are pinned here.
spawn run_reject_at w3a-opaque-sizeof tests/fixtures/w3a-opaque-sizeof.nuc \
  "tests/fixtures/w3a-opaque-sizeof.nuc:9: error:" \
  "sizeof: 'CHOpaque' is an opaque type declared at "
spawn run_reject_at w3a-opaque-alloca tests/fixtures/w3a-opaque-alloca.nuc \
  "tests/fixtures/w3a-opaque-alloca.nuc:6: error:" \
  "alloca: 'CHOpaque' is an opaque type declared at "
spawn run_reject_at w3a-opaque-field tests/fixtures/w3a-opaque-field.nuc \
  "tests/fixtures/w3a-opaque-field.nuc:7: error:" \
  "field access: 'CHOpaque' is an opaque type declared at "
spawn run_reject_at w3a-opaque-param tests/fixtures/w3a-opaque-param.nuc \
  "tests/fixtures/w3a-opaque-param.nuc:6: error:" \
  "defn parameter: 'CHOpaque' is an opaque type declared at "
spawn run_reject_at w3a-opaque-return tests/fixtures/w3a-opaque-return.nuc \
  "tests/fixtures/w3a-opaque-return.nuc:5: error:" \
  "defn return type: 'CHOpaque' is an opaque type declared at "
# The declaration line inside the message must be a real one — the header:line
# provenance is recovered from clang -E's linemarkers, and a 0 there would be as
# useless as the `:0:` W4a removed from the location prefix.
spawn run_w3a_opaque_provenance
# W3a also gave `unknown type:` a location: resolving a defn signature used to
# blame the defn's NAME node, an interned NODE-SYM whose line is always 0. Both
# halves (parameter, return) are pinned, and both fixtures also feed the
# run_no_line_zero sweep above.
spawn run_reject_at w3a-unknown-type-param tests/fixtures/w3a-unknown-type-param.nuc \
  "tests/fixtures/w3a-unknown-type-param.nuc:6: error:" "unknown type: NoSuchTypeHere"
spawn run_reject_at w3a-unknown-type-return tests/fixtures/w3a-unknown-type-return.nuc \
  "tests/fixtures/w3a-unknown-type-return.nuc:3: error:" "unknown type: AlsoNoSuchType"
# One real third-party header must give BOTH shapes from a single import.
spawn run_w3a_sdl_mixer

# --- Stage 15 W3b: C type qualifiers + the declare validity gate -------------
# design/stage15-stress-test/cheader.md §1.5. Two independent deliverables:
# the PARSE fix (qualifiers are legal after the base type, not only before it —
# `int const *p` was importing as a TWO-parameter function) and the GATE (a
# recognized declaration the importer cannot describe is skipped with a located
# warning instead of emitted as invalid IR). The gate does not subsume the parse
# fix: `(i32, ptr)` passes any reasonable gate, so only the matrix catches it.
spawn run_w3b_quals
spawn run_w3b_skip
spawn run_w3b_sdl

# --- Stage 15 W3c: typedef chains + declaration precedence -------------------
# design/stage15-stress-test/cheader.md §1.4. Two deliverables again: the typedef
# TABLE (an unfollowed typedef resolved to `ptr`, so `off_t`/`Uint8`/`Uint32` and
# every scalar alias silently degraded, in return types, parameters AND struct
# fields) and the PRECEDENCE rule (an explicit `declare` beats a header-derived
# one whichever comes first, and a mismatch warns naming both sources).
spawn run_w3c_typedef
spawn run_w3c_precedence
# W3c fallout: `declare`'s bare (unnamed) parameter spelling ignored every
# written type and emitted `i32`. The matrix pins both spellings against each
# other; the header pair pins the precedence interaction it broke — an explicit
# declaration MATCHING the header must be silent, a differing one must still
# warn and win.
spawn run_w3c_declare_params
spawn run_w3c_declare_header
# A parameter spelling that names no type is a located error, not a default —
# and `:rest`/`:optional` are defn-only (the marker used to be counted as an
# extra i32 parameter, so the declared arity silently disagreed).
spawn run_reject_at w3c-declare-unknown-type tests/fixtures/w3c-declare-unknown-type.nuc \
  "tests/fixtures/w3c-declare-unknown-type.nuc:4: error:" "unknown type: NoSuchDeclParamType"
spawn run_reject_at w3c-declare-rest tests/fixtures/w3c-declare-rest.nuc \
  "tests/fixtures/w3c-declare-rest.nuc:6: error:" \
  "declare: ':rest' is not supported in a declaration"

# --- Stage 15 W4e: docs/stdlib.md's availability table is generated ---------
spawn run_stdlib_table
spawn run_headers_generated
spawn run_cstr_residue

# --- Stage 15 W5c: a `defvar` global may be typed CStr ----------------------
# design/stage15-stress-test/ergonomics.md §W5c (findings §3.7). The positive
# matrix -- both literal spellings (plain "…" and c"…"), explicit `null`, no
# init, `:const`, the private `defvar-`, `set!`, and every global handed to a
# libc function declared `const char *` -- is examples/cstr-defvar.nuc, run by
# the examples/*.nuc loop above against tests/expected/cstr-defvar.out. It is
# checked BY VALUE (strlen/strcmp results, %s output) rather than by exit code,
# because "it compiles" was never the question: the pre-W5c workaround compiled
# too. That example also pins the segfault W5c fixed -- `(= cstr null)` lowered
# to `strcmp(ptr, null)`, undefined behaviour in C and a crash under glibc.
#
# Here: the boundary the widened gate must NOT cross. `defvar-init-ir` now gates
# a string literal and `null` on `is-ptr-like` instead of a bare `TY-PTR` kind,
# which admits `CStr` -- and must still admit nothing else. (The `null` gate also
# admits TY-FN by name since the fn-pointer-global fix below, which is why its
# message names three admissible spellings; a string literal still does not.)
spawn run_reject_at w5c-string-into-int tests/fixtures/w5c-string-into-int.nuc \
  "tests/fixtures/w5c-string-into-int.nuc:5: error:" \
  "defvar: string literal requires ptr or CStr type, not i32"
spawn run_reject_at w5c-null-into-int tests/fixtures/w5c-null-into-int.nuc \
  "tests/fixtures/w5c-null-into-int.nuc:4: error:" \
  "defvar: null requires ptr, CStr or a function-pointer type, not i32"
#
# The carve-out, pinned in the other direction. `CStr` is flow-exempt (a null
# `char*` is ordinary C), and `defvar-init-ir` states that exemption as its own
# early return rather than letting it ride on `is-ptr-like`. W6 (below) has since
# added a `pkind-flow-check` to the `TY-PTR` path beside it; this test is what
# fails if `CStr` ever gets swept up with `ptr`.
spawn run_accepts w5c-cstr-null-exempt tests/fixtures/w5c-cstr-null-exempt.nuc

# --- Stage 15 W6: null into a non-null global -------------------------------
# `defvar-init-ir` is a CONSTANT RENDERER: it never routes through
# `coerce-int-val` (src/abi.nuc), the chokepoint every value-position assignment
# passes for its Phase-F `pkind-flow-check`. So `(defvar g:ptr:Thing null)`
# compiled clean and segfaulted on first use, while the identical local
# `(let (p:ptr:Thing null) …)` was correctly rejected -- one rule living in one
# path and not the other. The fix calls the SAME predicate from the global path
# (source type = `ty-raw`, exactly what `emit-symbol-ref` gives the `null`
# symbol), so the two cannot drift; these tests pin both directions.
#
# Rejections: a TYPED non-null pointer, in both spellings. The location is pinned
# (not just the message) because the init node is the interned symbol `null`,
# whose own line is always 0 -- the diagnostic has to borrow the enclosing
# `defvar` form's line via `node-line`, and a regression there reports `:0:`.
spawn run_reject_at w6-defvar-null-ptr-elem tests/fixtures/w6-defvar-null-ptr-elem.nuc \
  "tests/fixtures/w6-defvar-null-ptr-elem.nuc:11: error:" \
  "defvar: raw pointer where non-null (ref ...) is required"
spawn run_reject_at w6-defvar-null-ref tests/fixtures/w6-defvar-null-ref.nuc \
  "tests/fixtures/w6-defvar-null-ref.nuc:8: error:" \
  "defvar: raw pointer where non-null (ref ...) is required"
#
# Stage 15 W9 item 7: the same rule, for the source kind it never reached. A
# `CStr` is `TY-CSTR`, so `pkind-flow-check`'s `TY-PTR`-only guard let it launder
# a null into a typed non-null slot — global and local alike, since the defvar
# renderer calls the same predicate — and `as-ptr-convert` carried a second copy
# of the premise. Measured before the fix: all three of these compiled clean and
# segfaulted; the corpus contained exactly ONE conversion that this rejects
# (lib/hash.nuc's CStr Hash conformance), now null-guarded.
spawn run_reject_at w9-cstr-into-ref-defvar tests/fixtures/w9-cstr-into-ref-defvar.nuc \
  "tests/fixtures/w9-cstr-into-ref-defvar.nuc:17: error:" \
  "defvar: raw pointer where non-null (ref ...) is required"
spawn run_reject_at w9-cstr-into-ref-let tests/fixtures/w9-cstr-into-ref-let.nuc \
  "tests/fixtures/w9-cstr-into-ref-let.nuc:8: error:" \
  "assignment: raw pointer where non-null (ref ...) is required"
spawn run_reject_at w9-cstr-as-typed-ptr tests/fixtures/w9-cstr-as-typed-ptr.nuc \
  "tests/fixtures/w9-cstr-as-typed-ptr.nuc:16: error:" \
  "as: raw pointer CStr where non-null ptr:W9C7A is required"
# W9 item 18: a function pointer is one `ptr` register, so `=` / `!=` against
# null, against another slot, or against a function symbol is machine identity.
spawn run_w9_fnptr_compare
# ...but it is NOT admitted to the strcmp lowering. This is the tripwire against
# "fixing" item 18 by widening `is-ptr-like` to contain TY-FN, which would turn
# the line below into strcmp(hook, msg) — a function's code read as text.
spawn run_reject_at w9-fnptr-cstr-compare tests/fixtures/w9-fnptr-cstr-compare.nuc \
  "tests/fixtures/w9-fnptr-cstr-compare.nuc:15: error:" \
  "=: a CStr compares only with a CStr or pointer"
# W9 item 19, the storage half of the same sentence: one `ptr` register is one
# TARGET pointer wide, so no fn-pointer slot may claim `align 1`.
spawn run_w9_fnptr_align
# W9 item 20: the literal `null` reaches a fn-pointer slot in every position
# (let init, set!, field store, explicit return), not just `defvar`. The exit
# code is a bitmask of the five "is it unset?" answers plus two round-trips, so
# a slot that compiles but holds the wrong value fails rather than passing.
spawn run_w9_fnptr_null_init
# ...but ONLY the literal. Gating item 20 on `is-ptr-repr` instead of on
# Val.is-nlit would compile the line below and make any data pointer callable.
spawn run_reject_at w9-fnptr-null-launder tests/fixtures/w9-fnptr-null-launder.nuc \
  "tests/fixtures/w9-fnptr-null-launder.nuc:17: error:" \
  "let: init type mismatch for 'f'"
#
# Acceptances: every NULLABLE or contract-free pointer destination stays legal --
# elem-less bare `ptr` (with and without an init), `(raw T)` / `raw:T`, `?ptr:T`,
# and `CStr`. The bare-`ptr` cases are the load-bearing ones: `ptr` is PTR-REF
# since the Phase-F flip, so only `pkind-flow-check`'s untyped-destination
# refinement keeps them compiling, and this compiler's own source has ~1550 such
# bindings -- narrowing that refinement would take the bootstrap with it.
spawn run_accepts w6-defvar-null-accepts tests/fixtures/w6-defvar-null-accepts.nuc

# --- Stage 15 W8: a function-pointer-typed global ---------------------------
# `(defvar h:(fn ret)(params) …)` could not be declared at all. Two stacked
# defects: `name-existing-kind` called any TY-FN-typed global Sym "a function",
# so once G-0's prescan defined that Sym the `defvar` collided with itself; and
# behind it `defvar-init-ir`'s `null` gate tested `is-ptr-like`, which excludes
# TY-FN by design. The positive matrix -- explicit `null`, no init, a runtime
# initializer, `set!`, both call spellings, and reassignment -- is
# examples/fnptr-global.nuc, run by the examples/*.nuc loop above against
# tests/expected/fnptr-global.out and checked BY VALUE: a hook wired to the
# wrong symbol, or an @__nucleus_init that never ran, links and exits 0.
#
# The two boundaries that must hold. First, the null admission is TY-FN-only:
# `ptr:(fn …)` is a pointer TO a function pointer, an ordinary PTR-REF, and W6's
# gate still refuses `null` there. The location is pinned for the same reason
# W6's are -- the init node is the interned symbol `null`, whose own line is 0.
spawn run_reject_at w8-fnptr-null-still-gated tests/fixtures/w8-fnptr-null-still-gated.nuc \
  "tests/fixtures/w8-fnptr-null-still-gated.nuc:12: error:" \
  "defvar: raw pointer where non-null (ref ...) is required"
# Second, the `is-local` conjunct must not silence a real cross-kind collision.
# g0-value-fn-collision-order1/2 pin the plain (i32-typed) shape; this is the
# fn-typed one, i.e. exactly the shape the new conjunct changes the answer for.
#
# Stage 15 B5 re-pointed the LOCATION and the noun, not the verdict. The guard
# now asks the shared binding table for the first binding whose kind is NOT the
# one being defined (name-resolution.md §13.3), so the collision is reported at
# whichever definer is EMITTED first — here the `defn`, naming the
# `defvar` — instead of only at the second one. Before B5 the first definer's
# own guard was silently masked by its own prescan registration, which is the
# same class of hole this chunk exists to close; the pair is still refused, and
# `run_reject_at` still proves no binary is produced.
spawn run_reject_at w8-fnptr-global-name-collision tests/fixtures/w8-fnptr-global-name-collision.nuc \
  "tests/fixtures/w8-fnptr-global-name-collision.nuc:19: error:" \
  "'f' already names a value — a symbol may name only one kind of thing"

# --- Stage 15 W5d: array literal ergonomics ---------------------------------
# design/stage15-stress-test/ergonomics.md §3.9 + §3.10. The positive matrix is
# examples/array-literal-ergonomics.nuc, run by the examples/*.nuc loop above:
# bare struct compound literals as array elements (positional, designated and
# mixed with the old `(deref …)` spelling), the zero-fill of an unspecified
# struct/CStr slot, the same relaxation at the sibling typed slots (local, field,
# aset!, by-value return), and the §3.10 `:ptr` bindings. The committed boot
# compiler FAILS on that file (`array: type mismatch in positional initializer`),
# which is the teeth.
#
# Here: the three boundaries the relaxations must NOT cross.
# 1. §3.9 stays type-directed — a compound literal of a DIFFERENT struct is
#    still a mismatch (the load is gated on the pointee's StructDef).
# 2. The implicit load is a `deref`, so it inherits `deref`'s Stage 10
#    obligation: a `?T` source must be narrowed first, or the sugar would be a
#    nullability hole the explicit spelling does not have.
# 3. §3.10 is SYNTACTIC (an `(array T …)` init and nothing else). A bare `:ptr`
#    is the void*-style erasure hatch; inferring the element type generally
#    would re-route multimethod dispatch across every such binding, so a `:ptr`
#    bound from an `alloca` must stay elem-less.
spawn run_reject_at w5d-array-wrong-struct tests/fixtures/w5d-array-wrong-struct.nuc \
  "tests/fixtures/w5d-array-wrong-struct.nuc:9: error:" \
  "array: type mismatch in positional initializer"
spawn run_reject_at w5d-struct-slot-maybe-null tests/fixtures/w5d-struct-slot-maybe-null.nuc \
  "tests/fixtures/w5d-struct-slot-maybe-null.nuc:12: error:" \
  "assignment: value may be null"
spawn run_reject_at w5d-elemless-not-inferred tests/fixtures/w5d-elemless-not-inferred.nuc \
  "tests/fixtures/w5d-elemless-not-inferred.nuc:13: error:" \
  "aref: operand must be typed pointer"

# --- Stage 15 W1: whole-unit signature resolution ----------------------------
# design/stage15-stress-test/resolution.md. Cross-file function references now
# resolve on reachability, not import order. The two order-pair units are the
# teeth (both fail on the committed boot compiler); the graph-shape and
# still-rejects units are the regressions that matter.
spawn run_w1_mutual
spawn run_w1_ns
spawn run_w1_graph_shapes
spawn run_w1_still_rejects
spawn run_w1_declare_cycle_breaker
spawn run_w1d_cycle_accepts
spawn run_w1d_cycle_diagnoses
spawn run_w1d_path_prefix
spawn run_w1_deferred_union_payload
spawn run_w1_late_overload_symbol
# W9 item 1: the unit's ROOT file is a member of the import graph too.
spawn run_w9_root_hoist
spawn run_w9_root_cycle_skip
spawn run_w9_lib_standalone
spawn run_w9_multi_object
spawn run_w9_source_outranks_header
spawn run_w9_nuch_import_order
spawn run_w9_layout_reachability
spawn run_w9_defcast_reach
spawn run_w9_nuch_ns_union
spawn run_w9_shared_init_warning
spawn run_w9_cheader_globals
spawn run_w9_cheader_identifiers
spawn run_w9_cheader_imported_types
spawn run_w9_cheader_niche_types
spawn run_w9_ir_name_positions
# W1c: the diagnostic surface. The did-you-mean tier it sits above is pinned by
# w4a-suggest-spelling; the note deliberately suppresses that tier (they would
# otherwise offer two diagnoses of one failure), which is why the suggestion
# fixture and w1c-unreachable-file are complementary, not redundant.
spawn run_w1c_unreachable_file
spawn run_w1c_defined_nowhere
spawn run_w1c_unreachable_type

# --- Stage 15 W8 G-0: value names resolve on reachability --------------------
# design/global-init.md §5. The value half of W1: `defvar`/`defconst`/`defenum`
# members register in the whole-graph prescan, so a reference to one no longer
# depends on import order or on position within a file. The order-pair units are
# the teeth (each order-2 unit fails on the committed boot compiler); the
# still-rejects unit is the regression guard, and the same-file forward
# reference is examples/g0-forward-value.nuc.
spawn run_g0_value_order
spawn run_w9_string_path_prescan
spawn run_g0_value_scoping
spawn run_g0_cycle_values
spawn run_g0_still_rejects

# --- Stage 15 W8 G-1: constant expressions in a global initializer -----------
# design/global-init.md §5 "G-1". Positives live in examples/g1-const-init.nuc
# (printed values, so a wrong fold is visible) plus the cross-file unit below.
# The rejections pin that folding did NOT open a hole in the three checks the
# constant renderer already carried: the W2b range gate on the folded value, the
# W6 nullability gate through the new `as` branch, and `emit-as`'s narrowing
# rule — plus the arithmetic faults folding introduces, each of which must be a
# located diagnostic rather than a wrap, a SIGFPE in the compiler, or poison.
spawn run_g1_fold_cross_file
spawn run_reject_at g1-fold-range tests/fixtures/g1-fold-range.nuc \
  "tests/fixtures/g1-fold-range.nuc:5: error:" \
  "defvar: constant expression value 6000000000 does not fit i32"
spawn run_reject_at g1-fold-overflow tests/fixtures/g1-fold-overflow.nuc \
  "tests/fixtures/g1-fold-overflow.nuc:3: error:" \
  "defvar: constant initializer overflows 64-bit signed integer arithmetic"
spawn run_reject_at g1-div-zero tests/fixtures/g1-div-zero.nuc \
  "tests/fixtures/g1-div-zero.nuc:4: error:" \
  "defvar: division by zero in constant initializer"
spawn run_reject_at g1-rem-zero tests/fixtures/g1-rem-zero.nuc \
  "tests/fixtures/g1-rem-zero.nuc:2: error:" \
  "defvar: remainder by zero in constant initializer"
spawn run_reject_at g1-shift-range tests/fixtures/g1-shift-range.nuc \
  "tests/fixtures/g1-shift-range.nuc:3: error:" \
  "defvar: shift amount 64 out of range in constant initializer"
spawn run_reject_at g1-as-lossy tests/fixtures/g1-as-lossy.nuc \
  "tests/fixtures/g1-as-lossy.nuc:5: error:" \
  "as: lossy conversion from i64 to i32 -- use unsafe/cast"
spawn run_reject_at g1-as-null-launder tests/fixtures/g1-as-null-launder.nuc \
  "tests/fixtures/g1-as-null-launder.nuc:7: error:" \
  "defvar: raw pointer where non-null (ref ...) is required"
spawn run_reject_at g1-addr-of-const tests/fixtures/g1-addr-of-const.nuc \
  "tests/fixtures/g1-addr-of-const.nuc:4: error:" \
  "defvar: addr-of: 'G1K' is a compile-time constant and has no address"
spawn run_reject_at g1-not-constant tests/fixtures/g1-not-constant.nuc \
  "tests/fixtures/g1-not-constant.nuc:5: error:" \
  "defvar: init must be a compile-time constant"

# --- Stage 15 W8 G-2: the (array T N) type + constant aggregates -------------
# design/global-init.md §5 "G-2". The five shapes are exercised positively by
# examples/g2-array-init.nuc (run by the examples/*.nuc loop above, printing
# every value), the by-value ABI of an array FIELD by `make abi-test`, and the
# field's size/offset against the platform C compiler by `make layout-test`.
# The rejections below pin the containment rule that makes the decay model
# coherent: an array is STORAGE, legal only as a defvar type or an aggregate's
# field type, and refused — at a real file:line — everywhere a value copy would
# be implied.
spawn run_g2_cheader
spawn run_g2_nuch
spawn run_accepts g2-anon-struct-field tests/fixtures/g2-anon-struct-field.nuc
spawn run_reject_at g2-array-param tests/fixtures/g2-array-param.nuc \
  "tests/fixtures/g2-array-param.nuc:4: error:" \
  "(array T N) is a storage type"
spawn run_reject_at g2-array-return tests/fixtures/g2-array-return.nuc \
  "tests/fixtures/g2-array-return.nuc:3: error:" \
  "(array T N) is a storage type"
spawn run_reject_at g2-array-let tests/fixtures/g2-array-let.nuc \
  "tests/fixtures/g2-array-let.nuc:4: error:" \
  "(array T N) is a storage type"
spawn run_reject_at g2-array-ptr-elem tests/fixtures/g2-array-ptr-elem.nuc \
  "tests/fixtures/g2-array-ptr-elem.nuc:4: error:" \
  "(array T N) is a storage type"
spawn run_reject_at g2-array-nested tests/fixtures/g2-array-nested.nuc \
  "tests/fixtures/g2-array-nested.nuc:3: error:" \
  "(array T N) is a storage type"
spawn run_reject_at g2-array-generic-arg tests/fixtures/g2-array-generic-arg.nuc \
  "tests/fixtures/g2-array-generic-arg.nuc:5: error:" \
  "(array T N) is a storage type"
spawn run_reject_at g2-len-nonconst tests/fixtures/g2-len-nonconst.nuc \
  "tests/fixtures/g2-len-nonconst.nuc:4: error:" \
  "(array T N): length must be a compile-time integer constant"
spawn run_reject_at g2-len-zero tests/fixtures/g2-len-zero.nuc \
  "tests/fixtures/g2-len-zero.nuc:4: error:" \
  "(array T N): length must be positive, got 0"
spawn run_reject_at g2-index-range tests/fixtures/g2-index-range.nuc \
  "tests/fixtures/g2-index-range.nuc:3: error:" \
  "index 5 is out of range for a 3-element array"
spawn run_reject_at g2-index-twice tests/fixtures/g2-index-twice.nuc \
  "tests/fixtures/g2-index-twice.nuc:3: error:" \
  "index 1 specified twice"
spawn run_reject_at g2-too-many tests/fixtures/g2-too-many.nuc \
  "tests/fixtures/g2-too-many.nuc:3: error:" \
  "too many initializers for a 2-element array"
spawn run_reject_at g2-elem-mismatch tests/fixtures/g2-elem-mismatch.nuc \
  "tests/fixtures/g2-elem-mismatch.nuc:3: error:" \
  "array initializer element type i64 does not match the declared element type i32"
spawn run_reject_at g2-elem-range tests/fixtures/g2-elem-range.nuc \
  "tests/fixtures/g2-elem-range.nuc:4: error:" \
  "defvar: constant expression value 6000000000 does not fit i32"
spawn run_reject_at g2-scalar-init tests/fixtures/g2-scalar-init.nuc \
  "tests/fixtures/g2-scalar-init.nuc:2: error:" \
  "slot must be initialized with an (array T ...) literal"
spawn run_reject_at g2-struct-scalar-init tests/fixtures/g2-struct-scalar-init.nuc \
  "tests/fixtures/g2-struct-scalar-init.nuc:5: error:" \
  "a P slot must be initialized with a (P ...) compound literal"
spawn run_reject_at g2-struct-field-twice tests/fixtures/g2-struct-field-twice.nuc \
  "tests/fixtures/g2-struct-field-twice.nuc:3: error:" \
  "defvar: field 'x' specified twice"
spawn run_reject_at g2-struct-no-field tests/fixtures/g2-struct-no-field.nuc \
  "tests/fixtures/g2-struct-no-field.nuc:3: error:" \
  "defvar: no field 'z' on struct 'P'"
spawn run_reject_at g2-field-assign tests/fixtures/g2-field-assign.nuc \
  "tests/fixtures/g2-field-assign.nuc:5: error:" \
  "set!: field 'xs': an (array T N) is storage, not a value"
spawn run_reject_at g2-set-global tests/fixtures/g2-set-global.nuc \
  "tests/fixtures/g2-set-global.nuc:4: error:" \
  "set!: 'g': an (array T N) is storage, not a value"

# --- Stage 15 W8 G-3: @__nucleus_init ----------------------------------------
# design/global-init.md §5 "G-3". The positive matrix is
# examples/g3-runtime-init.nuc (values printed, not merely compiled). The two
# multi-file / IR-level checks are here, and the AVR half — the `none`
# mechanism's located refusal, plus zero-cost measured on the target the
# requirement was stated for — is in tests/run-avr-test.sh.
spawn run_g3_zero_cost
spawn run_g3_library
# The queue predicate is `defvar-init-ir`'s own answer, so a runtime initializer
# inherits every check the constant renderer already applied at the same slot —
# §2.8's `pkind-flow-check` most of all, which is the whole acceptance argument
# for combining declaration with initialization. Pinned at the `defvar`, not at
# some synthesized set! the user never wrote.
spawn run_reject_at g3-init-raw-into-ref tests/fixtures/g3-init-raw-into-ref.nuc \
  "tests/fixtures/g3-init-raw-into-ref.nuc:9: error:" \
  "raw pointer where non-null (ref ...) is required"
spawn run_reject_at g3-init-type-mismatch tests/fixtures/g3-init-type-mismatch.nuc \
  "tests/fixtures/g3-init-type-mismatch.nuc:6: error:" \
  "set!: type mismatch for 'g3-bad'"
# Positions where a runtime initializer has nowhere to run. Each must be a
# located refusal rather than a slot that silently stays zero.
spawn run_reject_at g3-init-in-compile-time tests/fixtures/g3-init-in-compile-time.nuc \
  "tests/fixtures/g3-init-in-compile-time.nuc:6: error:" \
  "a compile-time or macro body cannot have"
spawn run_reject_at g3-init-const-storage tests/fixtures/g3-init-const-storage.nuc \
  "tests/fixtures/g3-init-const-storage.nuc:6: error:" \
  "is :const, so its initializer must be a compile-time constant"

# --- Stage 15 W8 G-4: the initializer-ordering diagnostic --------------------
# design/global-init.md §4.2. The accepting half — including the `(addr-of g)`
# decision and the known laundered-through-a-call gap — is run_g4_order above,
# by VALUE. Here: the refusals, each of which must name BOTH sites at real
# file:line:s. Note the second argument of each pair pins the NOTE's location,
# i.e. the target `defvar`, so one call covers both halves of "name both sites".
spawn run_g4_order
spawn run_reject_at g4-forward-ref tests/fixtures/g4-forward-ref.nuc \
  "tests/fixtures/g4-forward-ref.nuc:12: error: defvar: the initializer for 'g4-fwd-a' names global 'g4-fwd-b', whose own defvar has not been reached yet" \
  "note: 'g4-fwd-b' is declared at tests/fixtures/g4-forward-ref.nuc:13"
spawn run_reject_at g4-init-cycle tests/fixtures/g4-init-cycle.nuc \
  "tests/fixtures/g4-init-cycle.nuc:10: error: defvar: the initializer for 'g4-cyc-a' names global 'g4-cyc-b'" \
  "note: 'g4-cyc-b' is declared at tests/fixtures/g4-init-cycle.nuc:11"
spawn run_reject_at g4-self-ref tests/fixtures/g4-self-ref.nuc \
  "tests/fixtures/g4-self-ref.nuc:6: error: defvar: the initializer for 'g4-self' names 'g4-self' itself" \
  "note: a global's initializer runs at the point its own defvar is reached, so it cannot read the global it is initializing"
# The two carve-outs, pinned as ACCEPTING here as well as by value above: a
# later, stricter walk that swallowed either would break programs that compile
# today (examples/g1-const-init.nuc's forward `(addr-of g-later-target)` is the
# in-tree instance of the first).
spawn run_accepts g4-addr-of-forward-clean tests/fixtures/g4-addr-of-forward.nuc
spawn run_accepts g4-laundered-call-clean tests/fixtures/g4-laundered-call.nuc

# --- Stage 15 W8 G-5: eliminate compiler-init, then flip ---------------------
# design/global-init.md §5 "G-5". The migration itself is verified by the whole
# suite (the compiler that runs every test below IS the migrated compiler), plus
# `assert-compiler-arena-backed`, which main/repl-main call on every invocation.
#
# The FLIP (acceptance criterion (B)): a `defvar` whose type is a non-null typed
# pointer must be initialized. This closes nullability.md §1.5's remaining half
# and makes `ptr:T` mean non-null at a global as it does everywhere else.
spawn run_reject_at g5-noinit-ref tests/fixtures/g5-noinit-ref.nuc \
  "tests/fixtures/g5-noinit-ref.nuc:12: error:" \
  "defvar: 'g5-thing' has a non-null pointer type but no initializer"
# ...and the note that tells you the two ways out, which is the whole reason the
# rule is tolerable at all.
spawn run_reject_at g5-noinit-ref-note tests/fixtures/g5-noinit-ref.nuc \
  "tests/fixtures/g5-noinit-ref.nuc:12: error:" \
  "declare it nullable with \`raw\`"
# The carve-outs the flip must NOT swallow, all four in one fixture: `raw`, `?T`,
# an elem-less bare `ptr` (~1550 of them in this compiler's own source), and
# CStr. These are pkind-flow-check's own exemptions, inherited by calling it
# rather than re-derived — a hand-written `(= (ty pkind) PTR-REF)` here would
# have broken every bare `:ptr` global in the tree.
spawn run_accepts g5-noinit-carve-outs tests/fixtures/g5-noinit-raw-ok.nuc

# --- Stage 15 W5e: `defn-` name isolation -----------------------------------
# design/stage15-stress-test/ergonomics.md §W5e. Sequenced after W1 because it is
# the same key scheme: W1a's whole-graph signature prescan is what makes a
# private name's key final before any form is emitted.
spawn run_w5e_private_isolated
spawn run_w5e_still_rejects
spawn run_reject w5e-ns-hash-reserved tests/fixtures/w5e-ns-hash-reserved.nuc \
  "a namespace name may not begin with '#'"

# --- Stage 15 W7: a bare selector symbol may be a value ---------------------
# design/stage15-stress-test/selector-ambiguity.md. The positive matrix is
# examples/selector-value.nuc, run by the examples/*.nuc loop above against
# tests/expected/selector-value.out: a local key in head position, through
# `get`, and through `invoke` (which now falls back to `get`); a string-literal
# key; an absent key; plain field access with a same-named local in scope; and
# the collision case where the local names a REAL field, which still resolves to
# the field with `invoke` as the escape hatch. Checked by value, not by exit
# code — "it compiles" was never the question for the field-access half.
#
# Since step 3 the selector IS the local: `(p k)` reads `k` as a computed
# selector, and an i32 is not one. The old W7 demotion this pinned is gone --
# there is nothing left to demote when a bare symbol was never a field.
spawn run_reject_at w7-local-not-a-field tests/fixtures/w7-local-not-a-field.nuc \
  "tests/fixtures/w7-local-not-a-field.nuc:9: error:" \
  "computed selector must evaluate to a symbol (ptr)"
# And the hint must not leak onto an ordinary typo — no local named `zz`, so the
# message stays the plain unadorned one.
spawn run_reject_at w7-plain-typo tests/fixtures/w7-plain-typo.nuc \
  "tests/fixtures/w7-plain-typo.nuc:7: error:" \
  "get: no field 'zz' on struct 'Point'"

# --- Stage 15 W9 defects 11 + 12 -----------------------------------------------
# design/stage15-stress-test/progress.md, W9 rows 11 and 12 — a matched pair.
#
# Defect 11: FOUR call sites passed more substitutions than their fixed-arity
# format helper takes (context/conventions.md opens with this trap), so snprintf
# read a garbage vararg. The two `%d %d` sites printed a garbage COUNT rather
# than crashing ("got 100", "got 115"), which is why nobody noticed; the two
# `%s %s` sites dereferenced the garbage and SEGFAULTED the compiler with no
# output at all. All four were cold paths a green suite had never executed, so
# the durable half of the fix is that each now HAS a test: a corrected format
# string nothing runs is one edit away from regressing.
spawn run_reject_at w9-fnptr-arity tests/fixtures/w9-fnptr-arity.nuc \
  "tests/fixtures/w9-fnptr-arity.nuc:12: error:" \
  "call: expected 2 args, got 1"
spawn run_reject_at w9-boxedfn-arity tests/fixtures/w9-boxedfn-arity.nuc \
  "tests/fixtures/w9-boxedfn-arity.nuc:9: error:" \
  "BoxedFn call: expected 1 args, got 2"
# The two that SEGFAULTED before the fix (both substitutions are `%s`).
# w9-dyn-not-protocol was RE-POINTED by defect 21 (see the fixture's own header):
# it used to reach this message by exploiting the protocol/conformance key
# mismatch that defect 21 fixed, and now reaches it the honest way — a `dyn`
# position naming a protocol nothing declared. The `(extend Cat dp/Describe)`
# above it now succeeds, which is the fix.
spawn run_reject_at w9-dyn-not-protocol tests/fixtures/w9-dyn-not-protocol.nuc \
  "tests/fixtures/w9-dyn-not-protocol.nuc:36: error:" \
  "(dyn dp/Missing): 'dp/Missing' is not a declared protocol"
spawn run_reject_at w9-extend-super-not-protocol tests/fixtures/w9-extend-super-not-protocol.nuc \
  "tests/fixtures/w9-extend-super-not-protocol.nuc:11: error:" \
  "extend: 'Describe' is a protocol, so its supertype 'Plain' must be a protocol too"

# Defect 12: a wrong-arity call to a SOLITARY `defn` was not diagnosed at all —
# `(f 1 2)` against a one-parameter `f` emitted `call i32 @f(i32 1, i32 2)`,
# linked and ran. The rule now lives in ONE function (`call-arity-ok` /
# `check-call-arity`, src/nucleusc.nuc) that the direct, indirect and BoxedFn
# paths all CALL, so they cannot drift. Both directions are errors.
spawn run_reject_at w9-call-too-many tests/fixtures/w9-call-too-many.nuc \
  "tests/fixtures/w9-call-too-many.nuc:9: error:" \
  "call to 'f': expected 1 args, got 2"
spawn run_reject_at w9-call-too-few tests/fixtures/w9-call-too-few.nuc \
  "tests/fixtures/w9-call-too-few.nuc:9: error:" \
  "call to 'f': expected 2 args, got 1"
# The legitimately variable arities: `:optional` is a band, `:rest` is a floor.
spawn run_reject_at w9-optional-too-many tests/fixtures/w9-optional-too-many.nuc \
  "tests/fixtures/w9-optional-too-many.nuc:7: error:" \
  "call to 'opt': expected at most 2 args, got 3"
spawn run_reject_at w9-rest-too-few tests/fixtures/w9-rest-too-few.nuc \
  "tests/fixtures/w9-rest-too-few.nuc:7: error:" \
  "call to 'r': expected at least 2 args, got 1"
# A `declare`d signature is OPEN-TAILED: Nucleus has no `...` spelling, so the
# documented way to call a C variadic function is to declare its fixed
# parameters and let the extras ride the call site. This is the carve-out the
# check must not swallow — three tests above (n6/sm3/s1) already depend on it.
spawn run_accepts w9-declare-open-tail tests/fixtures/w9-declare-open-tail.nuc
# ...but the fixed prefix is still asserted, so too FEW is an error.
spawn run_reject_at w9-declare-too-few tests/fixtures/w9-declare-too-few.nuc \
  "tests/fixtures/w9-declare-too-few.nuc:9: error:" \
  "call to 'some-c-fn': expected at least 2 args, got 1"

# --- Stage 15 W9 defect 21: protocols are namespaced entities -------------------
# design/stage15-stress-test/progress.md W9 row 21; the ruling is recorded as a
# dated supersession of Stage 12 decision 9 in design/stage12/namespaces.md.
#
# `(dyn ns/Proto)` was unusable across a namespace: the conformance registry
# stripped the qualifier off BOTH the type and the protocol while
# `protocol-lookup` matched the raw spelling, so `(extend Cat dp/Describe)`
# recorded a fact `(dyn dp/Describe)` could never find. The fix keeps the strip
# for the TYPE half (Stage 12's actual claim — a qualified type reference must
# resolve to the same StructDef from any namespace) and replaces it for the
# PROTOCOL half with resolution through the namespaced protocol registry.
#
# The positive, link-AND-RUN half is examples/w9-dyn-ns.nuc (dispatched by the
# examples/*.nuc loop above against tests/expected/w9-dyn-ns.out): it asserts the
# dispatched RESULTS 105/207/309, not an exit-0 compile. It pins all three halves
# of the ruling at once — a qualified reference resolving cross-namespace under a
# DIFFERENT import prefix, a bare reference inside its own namespace naming the
# same identity, and two namespaces declaring a `Describe` apiece without
# colliding. The committed pre-fix compiler rejects that program outright.
#
# The negative halves: conformance is still checked (and now names the protocol
# by its namespaced identity, so a failure says *which* Describe), and a bare
# reference that names no protocol in scope is still an error rather than
# silently picking one.
spawn run_reject_at w9-ns-proto-nonconform tests/fixtures/w9-ns-proto-nonconform.nuc \
  "tests/fixtures/w9-ns-proto-nonconform.nuc:18: error:" \
  "type 'Bad' does not conform to protocol 'dp/Describe'"
spawn run_reject_at w9-ns-proto-ambiguous tests/fixtures/w9-ns-proto-ambiguous.nuc \
  "tests/fixtures/w9-ns-proto-ambiguous.nuc:17: error:" \
  "extend: unknown protocol 'Describe'"

# --- Stage 15 B0: name resolution — the cells that must NOT move ---------------
# See the header on run_b0_import_use_flatten above. The recording harness for
# the rest of the matrix is tests/resolution-matrix.sh (run separately).
spawn run_b0_import_use_flatten
spawn run_b0_import_prefixed_fn

# --- Stage 15 B1: the cross-file prefix leak, now an error ---------------------
spawn run_b1_prefix_file_scope

# --- Stage 15 B2a: an import prefix DEFINES the spellings in scope -------------
# The originally reported defect. `examples/w9-dyn-ns.nuc` is the positive half
# (it spells `dpx/Describe` / `dpx2/Describe` and asserts the dispatched results
# 105/207/309); these are the negative halves, plus the flatten half of §8.3's
# table, which B2a is the first step to implement at all.
spawn run_reject_at b2a-extend-ns-not-in-scope tests/fixtures/b2a-ns-not-in-scope.nuc \
  "tests/fixtures/b2a-ns-not-in-scope.nuc:25: error:" \
  "extend: unknown protocol 'dp/Describe'"
spawn run_reject_at b2a-dyn-ns-not-in-scope tests/fixtures/b2a-dyn-ns-not-in-scope.nuc \
  "tests/fixtures/b2a-dyn-ns-not-in-scope.nuc:27: error:" \
  "(dyn dp/Describe): 'dp/Describe' is not a declared protocol"
spawn run_b2a_scope_diagnostic
spawn run_b2a_import_use_binds_namespace

# --- Stage 15 B5: the shared binding interface --------------------------------
# design/stage15-stress-test/name-resolution.md §13.3/§13.4. One table with a row
# per name-keyed registry; the row order is the resolution priority order, walked
# by `name-existing-kind`, `emit-dispatch` and `node-type-call` alike.
#
# (1) NK-PROTOCOL is now RETURNED. It was declared, accepted as an input to
# `guard-name-kind`, and unreachable, because `name-existing-kind` never probed
# `g-protocols`. Adding the row is what fixes it — and `prescan-protocols` had to
# move ahead of `prescan-struct-names`, because the struct prescan registers a
# name-only StructDef without guarding and so won every race: before B5 BOTH
# orders below died at the PROTOCOL's line saying "already names a type", and
# the `defn` shape did not error at all.
run_b5_protocol_kind() {
  local d err
  d="$(mktemp -d)"
  cat > "$d/b5-p1.nuc" <<'EOF'
(defprotocol B5Shape
  (b5-area ((self (ref Self))) i32))

(defstruct B5Shape n:i32)

(defn main ():i32 (return 0))
EOF
  cat > "$d/b5-p2.nuc" <<'EOF'
(defstruct B5Shape n:i32)

(defprotocol B5Shape
  (b5-area ((self (ref Self))) i32))

(defn main ():i32 (return 0))
EOF
  cat > "$d/b5-p3.nuc" <<'EOF'
(defprotocol B5Shape
  (b5-area ((self (ref Self))) i32))

(defn B5Shape (x:i32):i32 (return x))

(defn main ():i32 (return 0))
EOF
  # The struct is blamed, at its own line, and the noun is "a protocol".
  w1_reject_at b5-protocol-vs-struct "$d" "$d/b5-p1.nuc" "$d/b5-p1.nuc:4: error:" \
    "'B5Shape' already names a protocol"
  w1_reject_at b5-protocol-vs-struct-order2 "$d" "$d/b5-p2.nuc" "$d/b5-p2.nuc:1: error:" \
    "'B5Shape' already names a protocol"
  # A `defn` over a protocol name compiled clean before B5: the guard asked for
  # the highest-priority binding and found the Generic its own signature prescan
  # had just registered, so it matched NK-FUNCTION and never looked further.
  w1_reject_at b5-protocol-vs-defn "$d" "$d/b5-p3.nuc" "$d/b5-p3.nuc:4: error:" \
    "'B5Shape' already names a protocol"
  rm -rf "$d"
}

# (2) The privacy hole. `defstruct-`, `defunion-`, `defmacro-` and `defprotocol-`
# were accepted spellings whose privacy nothing enforced — they have no `Sym`,
# and before B5 `Sym` was the only carrier of `sym-private`. Measured zero uses
# across src/, lib/ and examples/, so there was no behaviour to preserve and
# nothing exercised them. Privacy here is NAMESPACE-level, per W5e's split (a
# type/macro name is bare-keyed and globally identified, Stage 12 decision 9), so
# each check needs a namespaced library and a consumer outside it — plus the
# positive control that a file INSIDE the namespace still sees all four, and that
# the library's public names are untouched.
run_b5_private_definers() {
  local d err
  d="$(mktemp -d)"
  cat > "$d/b5-plib.nuc" <<'EOF'
(ns b5p)
(defstruct- B5HiddenS n:i32)
(defunion- B5HiddenU (UA n:i32) UB)
(defmacro- b5-hidden-mac (x) x)
(defprotocol- B5HiddenP (b5-hm ((self (ref Self))) i32))
(defstruct B5PublicS n:i32)
(defn b5-lib-ok ():i32 (return 7))
EOF
  # Stage 15 B3′ re-point: these spell the private names THROUGH THE PREFIX.
  # Before B3′ a type name was bare-keyed and globally visible, so a bare
  # `B5HiddenS` reached the library and privacy was the only thing that could
  # refuse it. R1 makes the bare spelling fail for a *scope* reason (the prefix
  # binds `bp/` and nothing else), which would leave these four asserting
  # something they no longer test. Qualified, they still measure privacy: the
  # prefix resolves, the entry is found, and `binding-visible` hides it.
  cat > "$d/b5-cs.nuc" <<'EOF'
(import-prefixed b5-plib bp)
(defn b5-take ((h (ref bp/B5HiddenS))):i32 (return (h 'n)))
(defn main ():i32 (return 0))
EOF
  cat > "$d/b5-cu.nuc" <<'EOF'
(import-prefixed b5-plib bp)
(defn b5-take ((u (raw bp/B5HiddenU))):i32 (return 0))
(defn main ():i32 (return 0))
EOF
  cat > "$d/b5-cm.nuc" <<'EOF'
(import-prefixed b5-plib bp)
(defn main ():i32
  (return (b5-hidden-mac 1)))
EOF
  cat > "$d/b5-cp.nuc" <<'EOF'
(import-prefixed b5-plib bp)
(defstruct B5Cs n:i32)
(extend B5Cs bp/B5HiddenP
  (defn b5-hm ((self (ref B5Cs))):i32 (return 1)))
(defn main ():i32 (return 0))
EOF
  w1_reject_multi b5-private-struct   "$d" "$d/b5-cs.nuc" "unknown type: bp/B5HiddenS"
  w1_reject_multi b5-private-union    "$d" "$d/b5-cu.nuc" "unknown type: bp/B5HiddenU"
  w1_reject_multi b5-private-macro    "$d" "$d/b5-cm.nuc" "unknown: b5-hidden-mac"
  w1_reject_multi b5-private-protocol "$d" "$d/b5-cp.nuc" "extend: unknown protocol 'bp/B5HiddenP'"

  # Positive control. Without it the four rejections above would also pass if the
  # filter simply hid everything: a file INSIDE the namespace still sees the
  # private struct, union and macro, and a `user` consumer still reaches the
  # library's PUBLIC names through the prefix.
  # 1 (private struct field) + 2 (private union sizeof) + 4 (private macro)
  # + 7 (public fn) + 1 (public struct field 6 - 5) = 15.
  cat > "$d/b5-pin.nuc" <<'EOF'
(ns b5p)
(import-use b5-plib)

(defn b5-inside-sum ():i32
  (let (s:(ref B5HiddenS) (B5HiddenS 1)
        usz:i32 (if (> (sizeof B5HiddenU) 0) 2 0)
        m:i32 (b5-hidden-mac 4))
    (return (+ (+ (s 'n) usz) m))))
EOF
  # B3′: the public struct is reached through the prefix here too — the bare
  # spelling was the pre-R1 "types are globally visible" behaviour.
  cat > "$d/b5-pmain.nuc" <<'EOF'
(import-prefixed b5-pin bin)
(import-prefixed b5-plib bp)

(defn main ():i32
  (let (p:(ref bp/B5PublicS) (bp/B5PublicS 6))
    (return (+ (bin/b5-inside-sum) (+ (bp/b5-lib-ok) (- (p 'n) 5))))))
EOF
  w1_run b5-private-visible-inside "$d" "$d/b5-pmain.nuc" 15

  # The protocol's positive control is the DIAGNOSTIC, not a run: from inside the
  # namespace the name resolves, so `extend` gets as far as the conformance check
  # instead of "unknown protocol". (That conformance then fails, but for an
  # unrelated pre-existing reason — an `extend` written inside an explicit
  # `(ns …)` does not conform even for a PUBLIC protocol, reproducible on the
  # committed boot. What this pins is which of the two diagnostics fires.)
  cat > "$d/b5-ppin.nuc" <<'EOF'
(ns b5p)
(import-use b5-plib)

(defstruct B5InS n:i32)
(extend B5InS B5HiddenP
  (defn b5-hm ((self (ref B5InS))):i32 (return 1)))
EOF
  cat > "$d/b5-ppm.nuc" <<'EOF'
(import-prefixed b5-ppin pi)
(defn main ():i32 (return 0))
EOF
  err="$(./build/nucleusc -I "$d" --emit-llvm "$d/b5-ppm.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep -F "extend: unknown protocol"; then
    echo "FAIL  b5-private-protocol-visible-inside (hidden from its own namespace)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | qgrep -F "does not conform to protocol 'b5p/B5HiddenP'"; then
    echo "PASS  b5-private-protocol-visible-inside"
  else
    echo "FAIL  b5-private-protocol-visible-inside"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi
  rm -rf "$d"
}

# (3) Defect #9 — the did-you-mean echoed its input. A candidate reachable only
# as `zx/zfun` was suggested as `zfun`, the very spelling that had just failed
# (`error: unknown: zfun (did you mean 'zfun'?)`). A suggestion is now rendered
# through the interface's `src-ns` column into a spelling THIS file can write,
# and a candidate with no such spelling is not offered at all. The resolution
# matrix pins the `plain-fn bare` cell; this pins that the suggestion is USABLE,
# by compiling and running the program the suggestion asks for.
#
# Stage 15 W9 item 43 re-pointed the first half at the wording rather than at the
# tier. This program is item 43's own shape — a prefixed import plus a bare call
# — so it now reaches `generic-in-other-namespace-message`, which states the fact
# ("defined in namespace 'b5s'") ahead of guessing at a spelling, exactly as
# `type-in-other-namespace-message` has for a type since B3′. What defect #9 is
# actually about is unchanged and is what is asserted: the offered spelling is
# qualified, and it is never the one that just failed.
run_b5_did_you_mean() {
  local d err
  d="$(mktemp -d)"
  cat > "$d/b5-slib.nuc" <<'EOF'
(ns b5s)
(defn b5-suggest (x:i32):i32 (return (+ x 1)))
EOF
  cat > "$d/b5-sbad.nuc" <<'EOF'
(import-prefixed b5-slib sx)
(defn main ():i32 (return (b5-suggest 1)))
EOF
  err="$(./build/nucleusc -I "$d" --emit-llvm "$d/b5-sbad.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep -F "(did you mean 'b5-suggest'?)"; then
    echo "FAIL  b5-did-you-mean-not-echo (suggested the spelling that just failed)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | qgrep -F "sx/b5-suggest"; then
    echo "PASS  b5-did-you-mean-not-echo"
  else
    echo "FAIL  b5-did-you-mean-not-echo"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi

  # And the suggestion is not merely different — it works.
  cat > "$d/b5-sgood.nuc" <<'EOF'
(import-prefixed b5-slib sx)
(defn main ():i32 (return (sx/b5-suggest 41)))
EOF
  w1_run b5-did-you-mean-usable "$d" "$d/b5-sgood.nuc" 42
  rm -rf "$d"
}

# (4) `re-register`, and what it can now do. B5 made `export` explicit about the
# rows it could not re-bind: `g-globals` was the only `reregisterable` row, and
# every other one raised a located diagnostic naming the kind instead of failing
# as "symbol not found". Stage 15 B3′ FLIPPED the type and protocol rows, because
# §11.6's argument becomes load-bearing under R1: once type identity is
# namespaced, a facade that re-exports `geom/area` but cannot re-export `geom/Pt`
# exports a function whose signature names a type the consumer cannot spell.
#
# So the pin is re-pointed rather than re-baselined. The refusal is still
# asserted — for a MACRO, a row that is still not re-exportable and whose
# diagnostic is still the specification of the boundary — and the type case
# became the positive test it now describes: the facade re-exports a type AND a
# function over it, and the consumer names both through the facade's prefix,
# links and runs. The other positive half is examples/export-test.nuc.
run_b5_export_kinds() {
  local d
  d="$(mktemp -d)"
  cat > "$d/b5-elib.nuc" <<'EOF'
(ns b5e)
(defstruct B5ExpS n:i32)
(defn b5-exp-fn ((s (ref B5ExpS))):i32 (return (+ 1 (s 'n))))
(defmacro b5-exp-mac (x) x)
EOF
  cat > "$d/b5-efac.nuc" <<'EOF'
(ns b5facade)
(import-use b5-elib)
(export B5ExpS b5-exp-fn)
EOF
  cat > "$d/b5-emac.nuc" <<'EOF'
(ns b5facade2)
(import-use b5-elib)
(export b5-exp-mac)
EOF
  cat > "$d/b5-eovl.nuc" <<'EOF'
(ns b5ov)
(defn b5-exp-ov (x:i32):i32 (return x))
(defn b5-exp-ov (x:i32 y:i32):i32 (return (+ x y)))
EOF
  cat > "$d/b5-eovfac.nuc" <<'EOF'
(ns b5ovfacade)
(import-use b5-eovl)
(export b5-exp-ov)
EOF
  cat > "$d/b5-eovm.nuc" <<'EOF'
(import-use b5-eovfac)
(defn main ():i32 (return 0))
EOF
  cat > "$d/b5-em.nuc" <<'EOF'
(import-prefixed b5-efac fac)
(defn main ():i32
  (let (v:(ref fac/B5ExpS) (fac/B5ExpS 40))
    (return (fac/b5-exp-fn v))))
EOF
  cat > "$d/b5-emm.nuc" <<'EOF'
(import-prefixed b5-emac fac2)
(defn main ():i32 (return (fac2/b5-exp-mac 41)))
EOF
  # B3′: a facade re-exports a TYPE, and a function whose signature names it.
  # Both are spelled through the facade's prefix in the consumer, which is the
  # whole point — the library's own namespace `b5e` is not in scope here.
  w1_run b5-export-type-facade "$d" "$d/b5-em.nuc" 41
  # Stage 15 B7: a macro re-exports too, and it EXPANDS through the facade's
  # prefix. This pin was inverted — it used to assert the refusal, whose stated
  # reason ("identified by a globally-unique bare name") was circular: a macro
  # was bare-keyed only because macros had never been cut over to the
  # canonicaliser. The run is the point; a compile-only check would pass on a
  # macro that resolved but expanded to nothing.
  w1_run b7-export-macro-facade "$d" "$d/b5-emm.nuc" 41
  # What genuinely stays unexportable, and now for a reason that is true: an
  # OVERLOADED name is deliberately merged across namespaces (§8.2's R2), so it
  # is not keyed by namespace and a re-export would change nothing.
  err="$(./build/nucleusc -I "$d" --emit-llvm "$d/b5-eovm.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep ':0:'; then
    echo "FAIL  b7-export-overload-refused (diagnostic reports line 0)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | qgrep -F "'b5-exp-ov' is a function" \
    && printf '%s' "$err" | qgrep -F "that kind is not keyed by namespace"; then
    echo "PASS  b7-export-overload-refused"
  else
    echo "FAIL  b7-export-overload-refused"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi
  rm -rf "$d"
}

# --- Stage 15 B7: macros resolve through the import environment ---------------
# name-resolution.md §9.7 — the last kind on the bare-keyed path, and the rest of
# defect #1. `g-macros` is now keyed by `qualify-name` and `find-macro` is a
# reference resolver over the same candidate-key walk the six type registries
# use, so a macro obeys §8.3 exactly like every other kind.
#
# Nothing in the tree exercises this: no macro anywhere in `src/`, `lib/` or
# `examples/` is declared inside a namespaced file, which is also why B7 is
# byte-identical for the whole tree.
run_b7_qualified_macro() {
  local d err
  d="$(mktemp -d)"
  cat > "$d/b7-mlib.nuc" <<'EOF'
(ns b7ns)
(defmacro b7-twice (x) `(+ ~x ~x))
EOF
  cat > "$d/b7-mpre.nuc" <<'EOF'
(import-prefixed b7-mlib pm)
(defn main ():i32 (return (pm/b7-twice 21)))
EOF
  w1_run b7-macro-prefixed "$d" "$d/b7-mpre.nuc" 42

  # `import-use` binds both the unqualified name and the library's namespace
  # (§8.3 row 1) — for a macro exactly as for everything else.
  cat > "$d/b7-mflat.nuc" <<'EOF'
(import-use b7-mlib)
(defn main ():i32 (return (+ (b7-twice 20) (b7ns/b7-twice 1))))
EOF
  w1_run b7-macro-flattened "$d" "$d/b7-mflat.nuc" 42

  # R3 for macros: a prefixed import does NOT put the library's own namespace in
  # scope. Before B7 this "worked" for the wrong reason — every macro was one
  # unit-global bare name, so no qualifier resolved and no qualifier was needed.
  cat > "$d/b7-mns.nuc" <<'EOF'
(import-prefixed b7-mlib pm)
(defn main ():i32 (return (b7ns/b7-twice 21)))
EOF
  err="$(./build/nucleusc -I "$d" --emit-llvm "$d/b7-mns.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep -F "unknown: b7ns/b7-twice — 'b7ns' is not in scope in this file"; then
    echo "PASS  b7-macro-ns-refused"
  else
    echo "FAIL  b7-macro-ns-refused (wrong or missing diagnostic)"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi

  # The did-you-mean now offers a macro spelling that COMPILES. Before B7,
  # `binding-usable-spelling` refused to suggest anything for BK-MACRO — it was
  # the last row it refused — because `p/mac` would have failed on the next
  # compile. Cold path, so it needs a test that executes it.
  cat > "$d/b7-mbare.nuc" <<'EOF'
(import-prefixed b7-mlib pm)
(defn main ():i32 (return (b7-twice 21)))
EOF
  err="$(./build/nucleusc -I "$d" --emit-llvm "$d/b7-mbare.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep ':0:'; then
    echo "FAIL  b7-macro-did-you-mean (diagnostic reports line 0)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | qgrep -F "did you mean 'pm/b7-twice'?"; then
    echo "PASS  b7-macro-did-you-mean"
  else
    echo "FAIL  b7-macro-did-you-mean"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi

  # Three macro sources at once from inside a namespace: the prelude's `when`
  # (reached by the walk's final `user` probe — a namespaced file must not lose
  # the prelude), the file's OWN macro (slot 0, the current-namespace key), and
  # another namespace's through a prefix. This is the case a per-kind key walk
  # gets wrong if any one of its three slots is dropped.
  cat > "$d/b7-mmid.nuc" <<'EOF'
(ns b7mid)
(import-prefixed b7-mlib pm)
(defmacro b7-mid-mac (x) `(+ ~x 1))
(defn b7-mid (n:i32):i32
  (let (x:i32 0)
    (when (> n 3) (set! x (b7-mid-mac (pm/b7-twice n))))
    (return x)))
EOF
  cat > "$d/b7-mmm.nuc" <<'EOF'
(import-prefixed b7-mmid md)
(defn main ():i32 (return (md/b7-mid 20)))
EOF
  w1_run b7-macro-three-sources "$d" "$d/b7-mmm.nuc" 41

  # Two namespaces may now each declare a macro of one bare name — the thing a
  # single unit-global key made impossible. Under B4's redefinition rule these
  # would have collided; they are two keys now, and each prefix reaches its own.
  cat > "$d/b7-mlib2.nuc" <<'EOF'
(ns b7ns2)
(defmacro b7-twice (x) `(* ~x 3))
EOF
  cat > "$d/b7-mboth.nuc" <<'EOF'
(import-prefixed b7-mlib pa)
(import-prefixed b7-mlib2 pb)
(defn main ():i32 (return (+ (pa/b7-twice 10) (pb/b7-twice 7))))
EOF
  w1_run b7-macro-two-namespaces "$d" "$d/b7-mboth.nuc" 41
  rm -rf "$d"
}
spawn run_b7_qualified_macro

# --- Stage 15 B3′: type identity is namespaced (R1, defects #4 and #7) --------
# The headline: two namespaces may both define `Vector`, and one unit may use
# both. Before B3′ the type registry was keyed by the BARE name, so the second
# `defstruct Vector` found the first through `lookup-struct` and either silently
# won or filled in the other's StructDef. The test LINKS AND RUNS and checks a
# value, because "it compiles" cannot distinguish two types from one: the two
# `Vector`s here have different field counts, so a collapsed identity would read
# the wrong offsets rather than fail.
run_b3_two_vectors() {
  local d
  d="$(mktemp -d)"
  cat > "$d/b3-veca.nuc" <<'EOF'
(ns va)
(defstruct Vector x:i32 y:i32)
(defn sum-a ((v (ref Vector))):i32 (return (+ (_get v 'x) (_get v 'y))))
EOF
  cat > "$d/b3-vecb.nuc" <<'EOF'
(ns vb)
(defstruct Vector a:i32 b:i32 c:i32)
(defn sum-b ((v (ref Vector))):i32
  (return (+ (_get v 'a) (+ (_get v 'b) (_get v 'c)))))
EOF
  cat > "$d/b3-vmain.nuc" <<'EOF'
(import-prefixed b3-veca va)
(import-prefixed b3-vecb vb)
(defn main ():i32
  (let (p:(ref va/Vector) (va/Vector 1 2)
        q:(ref vb/Vector) (vb/Vector 4 8 16))
    (return (+ (va/sum-a p) (vb/sum-b q)))))
EOF
  w1_run b3-two-vectors "$d" "$d/b3-vmain.nuc" 31

  # And they are two TYPES, not one name with two spellings. `type-eq` is
  # StructDef-pointer identity, so a BY-VALUE slot of one initialized from the
  # other must be refused; the run above already proves the layouts are distinct
  # (2 fields vs 3), and this proves the identities are.
  #
  # A `(ref …)` slot is deliberately NOT used: the compiler does not today check
  # a `(ref A)` value against a `(ref B)` slot or parameter (measured, and true
  # of `HEAD` as well — a pre-existing gap unrelated to R1), so that spelling
  # would have asserted nothing.
  cat > "$d/b3-vmix.nuc" <<'EOF'
(import-prefixed b3-veca va)
(import-prefixed b3-vecb vb)
(defn main ():i32
  (let (q:vb/Vector (va/Vector 1 2))
    (return 0)))
EOF
  w1_reject_multi b3-two-vectors-distinct "$d" "$d/b3-vmix.nuc" "let: init type mismatch for 'q'"
  # The canonical name reaches diagnostics too: a field of the OTHER `Vector` is
  # reported against the namespaced type name, not a bare one.
  cat > "$d/b3-vfield.nuc" <<'EOF'
(import-prefixed b3-veca va)
(defn main ():i32
  (let (p:(ref va/Vector) (va/Vector 1 2))
    (return (_get p 'c))))
EOF
  w1_reject_multi b3-two-vectors-field "$d" "$d/b3-vfield.nuc" "no field 'c' on struct 'va/Vector'"
  rm -rf "$d"
}
spawn run_b3_two_vectors

# Stage 15 B3′a: a namespaced type must survive every SYNTHESIS region — the
# places where the compiler renders a Type back to its CANONICAL spelling
# (`type-spelling`) and re-parses it. Since B3′ a type spelling is a REFERENCE
# resolved through the writing file's import environment, and a synthesized
# spelling was written by no file: `gg/Pt` is not nameable in the consumer, which
# only bound the prefix `gx`. Three regions were unarmed and each refused a legal
# program (`unknown type: gg/Pt — 'gg' is not in scope in this file`):
#
#   * `tmpl-conformance-check-one`  — the per-instance check of a template-level
#     `(extend (Vector T) (Seq T))`, run at STAMP time in the stamping file. This
#     one is the widest: every collection in lib/ carries such an extend, so NO
#     namespaced type could be a collection element.
#   * `generic-instantiate`         — the stamped signature parse, before the body
#     job is queued (`drain-mono-worklist` already armed the body).
#   * `resolve-param-type-bound`    — the shared substitute-and-reparse helper
#     behind `method-bound-ret-type` / `subst-param-types-bound`, which is how a
#     return-only-tyvar generic (`vector-new`) resolves against a want.
#
# It LINKS AND RUNS and checks a value: the failures were compile-time, but a
# wrongly-resolved element type would be a layout bug, which only running finds.
run_b3a_ns_type_generic() {
  local d
  d="$(mktemp -d)"
  cat > "$d/b3a-lib.nuc" <<'EOF'
(ns b3ang)
(defstruct Pt x:i32 y:i32)
(defprotocol Areal (area ((self (ref Self))) i32))
EOF
  cat > "$d/b3a-use.nuc" <<'EOF'
(import-use vector)
(import-prefixed b3a-lib bx)
; The subject is spelled through this file's prefix; `extend` canonicalizes it to
; `b3ang/Pt` and must NOT then re-resolve that canonical name as a reference.
(defn area ((self (ref bx/Pt))):i32 (return (* (_get self 'x) (_get self 'y))))
(extend bx/Pt bx/Areal)
(defn main ():i32
  (with (v:(ref (Vector (ref bx/Pt))) (vector-new))
    (let (a:(ref bx/Pt) (bx/Pt 3 4) b:(ref bx/Pt) (bx/Pt 5 6) t:i32 0)
      (conj v a)
      (conj v b)
      (dotimes (i (unsafe/cast i32 (count v)))
        (set! t (+ t (_get (invoke v (as usize i)) 'x))))
      (return (+ t (area a))))))
EOF
  # 3 + 5 + (3*4) = 20
  w1_run b3a-ns-type-in-collection "$d" "$d/b3a-use.nuc" 20
  rm -rf "$d"
}
spawn run_b3a_ns_type_generic

# Defect #7's other half, and defect #4. `strip-ns-qualifier` used to discard a
# type spelling's qualifier without checking it, so a type was reachable from
# anywhere under any qualifier — including one naming no namespace at all.
spawn run_reject_at b3-type-bogus-qualifier tests/fixtures/b3-type-bogus-qualifier.nuc \
  "tests/fixtures/b3-type-bogus-qualifier.nuc:14: error:" "'nope' is not in scope in this file"
# A bare type name from a prefixed import: the type is defined, its file is
# reachable, the prescan registered it — so the diagnostic must NOT be the
# reachability message (which would send the reader looking for a missing
# definition instead of a wrong spelling). It names the defining namespace AND
# the spelling this file can actually write, and the note is the actionable half.
run_b3_ns_type_diagnostic() {
  local err
  err="$(./build/nucleusc --emit-llvm tests/fixtures/b3-type-ns-not-in-scope.nuc 2>&1 >/dev/null || true)"
  if ! printf '%s' "$err" | qgrep -F "tests/fixtures/b3-type-ns-not-in-scope.nuc:18: error: unknown type: Fox — defined in namespace 'dp'"; then
    echo "FAIL  b3-type-ns-not-in-scope (wrong head or location)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif ! printf '%s' "$err" | qgrep -F "note: write 'dpx/Fox' here"; then
    echo "FAIL  b3-type-ns-not-in-scope (note does not offer the writable spelling)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | qgrep -F "not defined anywhere in this compilation unit"; then
    echo "FAIL  b3-type-ns-not-in-scope (degraded to the reachability message)"
    printf '%s\n' "$err" | sed 's/^/    /'
  else
    echo "PASS  b3-type-ns-not-in-scope"
  fi
}
spawn run_b3_ns_type_diagnostic
# B3′ gave `unknown-type-message` the did-you-mean tier `unresolved-name-message`
# already had. The tier is a COLD error path, so it needs a test that EXECUTES it
# — the first cut called `fmt-3s` with two arguments, which conventions.md's
# fixed-arity rule says is invisible until something runs the line.
spawn run_reject_at b3-type-typo tests/fixtures/b3-type-typo.nuc \
  "tests/fixtures/b3-type-typo.nuc:12: error:" "unknown type: Widgat (did you mean 'Widget'?)"

# --- Stage 15 B2b: globals + the `unsafe` built-in namespace -------------------
spawn run_b2b_prefixed_values
# `unsafe` is a namespace now, not seven strings in the special-form set. The
# positive half (unsafe/cast, unsafe/ptr+, unsafe/funcall-ptr-i32 and
# unsafe/import-private all compiling and RUNNING, the last of them reaching a
# `defn-` through the prefix) is examples/unsafe-spellings.nuc, dispatched by
# the examples loop above; the four `un5-bare-*` rejections above still pin the
# retired bare spellings, which are now refused because the namespace is bound
# PREFIXED and never flattened rather than by a hard-coded arm in the dispatch
# ladder. This is the third half: the qualified spellings stay RESERVED even
# though they left `g-special-form-set`.
spawn run_reject b2b-unsafe-reserved tests/fixtures/b2b-unsafe-reserved.nuc \
  "'unsafe/cast' already names a special form"

# --- Stage 15 B5: the shared binding interface --------------------------------
spawn run_b5_protocol_kind
spawn run_b5_private_definers
spawn run_b5_did_you_mean
spawn run_b5_export_kinds

# --- Stage 15 B6: `(dyn P)` identity vs admission ------------------------------
# The headline. A `(dyn P)` box's IDENTITY is now its protocol's canonical name,
# so a library that writes `(dyn Describe)` bare inside `(ns b6dp)` and a
# consumer that writes `(dyn dpx/Describe)` through its own import prefix land on
# ONE StructDef. Before B6 they were two, and `type-eq` is StructDef-pointer
# identity, so this whole program was unbuildable in both directions:
#
#   * the library's box returned into the consumer's annotation failed at the
#     LLVM parser — `'%t6' defined with type '%__dyn.b6dp_Describe' but expected
#     '%__dyn.dpx_Describe'` — with no source location;
#   * a consumer value passed into the library's `(dyn Describe)` PARAMETER
#     failed at box construction with `(dyn b6dp/Describe): 'b6dp/Describe' is
#     not a declared protocol`, because admission was asked against the box's
#     STORED name and a canonical name is not nameable through a prefix. That is
#     the failure mode name-resolution.md §9.4 predicted for keying identity on
#     the canonical name *without* moving admission, measured here.
#
# It LINKS AND RUNS, and the value is the point: 11 (Fox 7 through the library's
# own vtable) + 16 (Cat 5, a CONSUMER type, dispatched through a vtable the
# library's forwarder loads) = 27. A compile-only check would pass on two box
# types that never meet.
run_b6_dyn_cross_ns() {
  local d
  d="$(mktemp -d)"
  cat > "$d/b6-dlib.nuc" <<'EOF'
(ns b6dp)
(import-use allocator)
(defprotocol Describe (describe ((self (ref Self))) i32))
(defstruct Fox n:i32)
(defn describe ((self (ref Fox))):i32 (return (+ 3 (_get self 'n))))
(extend Fox Describe)
; Both directions across the boundary: a box this file MAKES and a box it TAKES.
(defn make-fox ((n i32)):(dyn Describe) (return (Fox n)))
(defn show ((b (dyn Describe))):i32 (return (+ 1 (describe b))))
EOF
  cat > "$d/b6-duse.nuc" <<'EOF'
(import-use allocator)
(import-prefixed b6-dlib dpx)
(defstruct Cat n:i32)
(defn describe ((self (ref Cat))):i32 (return (+ 10 (_get self 'n))))
(extend Cat dpx/Describe)
(defn main ():i32
  (let (a:(dyn dpx/Describe) (dpx/make-fox 7))
    (return (+ (dpx/show a) (dpx/show (Cat 5))))))
EOF
  w1_run b6-dyn-cross-ns "$d" "$d/b6-duse.nuc" 27
  rm -rf "$d"
}
spawn run_b6_dyn_cross_ns

# Stage 15 W9 item 23. A namespace's emitted symbols must be a property of the
# NAMESPACE, not of whatever else the compilation unit happens to contain.
# R2 (name-resolution.md §8.2) keeps one bare-keyed `Generic` per name with every
# namespace's methods merged into it, and mangling used to ask that generic two
# questions that are per-namespace facts: which prefix (it answered with
# whichever namespace created it first) and whether to suffix at all (it answered
# yes, because the merged set looked overloaded). So `w23b.nuc` — which is
# `(ns w23b)` and merely IMPORTS a library that happens to define `describe` too
# — emitted `@w23b__describe.i64` for its own function and `@w23b__describe.i32`
# for the OTHER namespace's, while its `.nuch` and its C header both declared
# `@w23b__describe`: a consumer of either failed to link with
# `undefined reference to 'w23b__describe'`. Swapping the two import lines
# renamed every symbol.
run_w9_ns_symbol_ownership() {
  local d
  d="$(mktemp -d)"
  cat > "$d/w23a.nuc" <<'EOF'
(ns w23a)
(defn describe (x:i32):i32 (return (+ x 1)))
EOF
  cat > "$d/w23b.nuc" <<EOF
(ns w23b)
(import "$d/w23a.nuc")
(defn describe (x:i64):i64 (return (+ (unsafe/cast i64 (w23a/describe 1)) x)))
EOF
  ./build/nucleusc --emit-llvm  "$d/w23b.nuc" > "$d/w23b.ll"   2>/dev/null || true
  ./build/nucleusc --emit-nuch  "$d/w23b.nuc" > "$d/w23b.nuch" 2>/dev/null || true
  ./build/nucleusc --emit-llvm  "$d/w23a.nuc" > "$d/w23a.ll"   2>/dev/null || true

  # 1. Each definition emits under its OWN namespace. Stated as the invariant
  #    rather than as two literals: the symbol `w23a` exports is the same string
  #    whether or not `w23b` is in the unit. A literal check would still pass if
  #    a future change moved both names somewhere else in lockstep.
  grep -o '@w23a__describe[^ (]*' "$d/w23a.ll" | sort -u > "$d/alone.syms"
  grep -o '@w23a__describe[^ (]*' "$d/w23b.ll" | sort -u > "$d/together.syms"
  if [ -s "$d/alone.syms" ] && cmp -s "$d/alone.syms" "$d/together.syms" \
     && qgrep '^define .*@w23b__describe(' "$d/w23b.ll"; then
    echo "PASS  w9-ns-symbol-ownership"
  else
    echo "FAIL  w9-ns-symbol-ownership"
  fi

  # 2. Neither namespace's method is suffixed: one method from one namespace is
  #    not an overload of anything, however the merged generic looks.
  if ! qgrep -E '^define .*@w23[ab]__describe\.' "$d/w23b.ll"; then
    echo "PASS  w9-ns-no-phantom-overload"
  else
    echo "FAIL  w9-ns-no-phantom-overload"
  fi

  # 3. The export surfaces name a symbol the object actually defines — the
  #    original end-to-end failure. The consumer excludes the prelude (w23b.ll
  #    already provides it) so the two objects link.
  cat > "$d/cons.nuc" <<EOF
(exclude-prelude)
(import "$d/w23b.nuch")
(declare printf (fmt:CStr):i32)
(defn main ():i32
  (printf "d=%lld\n" (w23b/describe 20))
  (return 0))
EOF
  ./build/nucleusc --emit-llvm "$d/cons.nuc" > "$d/cons.ll" 2>/dev/null || true
  if clang "$d/w23b.ll" "$d/cons.ll" -o "$d/bin" 2>/dev/null \
     && [ "$("$d/bin")" = "d=22" ]; then
    echo "PASS  w9-ns-nuch-link-and-run"
  else
    echo "FAIL  w9-ns-nuch-link-and-run"
  fi
  # The header was never the wrong half — it always declared the solitary form;
  # this pins the other side of the equality gate 3 exercises, so a future change
  # cannot "fix" a mismatch by moving the header to meet a suffixed object.
  if ./build/nucleusc --emit-cheader "$d/w23b.nuc" 2>/dev/null \
       | qgrep 'w23b__describe(int64_t'; then
    echo "PASS  w9-ns-cheader-matches-object"
  else
    echo "FAIL  w9-ns-cheader-matches-object"
  fi

  # 4. Import order does not rename anything. Two consumers that import the same
  #    two namespaces in opposite orders must reference the same symbols.
  cat > "$d/ord1.nuc" <<EOF
(import "$d/w23a.nuc")
(import "$d/w23b.nuc")
(defn main ():i32 (return (+ (w23a/describe 1) (unsafe/cast i32 (w23b/describe 2)))))
EOF
  cat > "$d/ord2.nuc" <<EOF
(import "$d/w23b.nuc")
(import "$d/w23a.nuc")
(defn main ():i32 (return (+ (w23a/describe 1) (unsafe/cast i32 (w23b/describe 2)))))
EOF
  ./build/nucleusc --emit-llvm "$d/ord1.nuc" 2>/dev/null \
    | grep -o '@w23[ab]__describe[^ (]*' | sort -u > "$d/ord1.syms"
  ./build/nucleusc --emit-llvm "$d/ord2.nuc" 2>/dev/null \
    | grep -o '@w23[ab]__describe[^ (]*' | sort -u > "$d/ord2.syms"
  if [ "$(wc -l < "$d/ord1.syms")" = "2" ] && cmp -s "$d/ord1.syms" "$d/ord2.syms"; then
    echo "PASS  w9-ns-symbols-order-independent"
  else
    echo "FAIL  w9-ns-symbols-order-independent"
  fi
  rm -rf "$d"
}
spawn run_w9_ns_symbol_ownership

# Stage 15 W9 item 24. Every producer of a callable name registers it in the
# generic registry — `emit-defn` does so even for a SOLITARY function, and that
# is why a protocol method, a drop thunk and a `(dyn P)` vtable can be resolved
# at all. A `.nuch` `declare` was the one exception: it bound the name in
# `g-globals` and nowhere else, so a function arriving through a header was
# invisible to every asker that poses the question by name AND SIGNATURE rather
# than by name alone. `(dyn P)` died `no method 'describe' is defined` for a
# method that is declared, defined and linkable, and `extend` called a
# conforming type non-conforming. Calls were unaffected throughout, which is
# what hid it: the ordinary path asks `g-globals`.
run_w9_nuch_declare_generic() {
  local d
  d="$(mktemp -d)"
  # The library excludes the prelude so its object and the consumer's link
  # together; that is also why its body avoids `+`.
  cat > "$d/w24lib.nuc" <<'EOF'
(exclude-prelude)
(ns w24)
(defprotocol Describe (describe ((self (ref Self))) i32))
(defstruct Fox n:i32)
(defn describe ((self (ref Fox))):i32 (return (_get self 'n)))
(extend Fox Describe)
EOF
  cat > "$d/w24use.nuc" <<EOF
(import-use "stdio.h")
(import-use allocator)
(import "$d/w24lib.nuch" wx)
(defn main ():i32
  (let (b:(dyn wx/Describe) (wx/Fox 309))
    (printf "d=%d\n" (wx/describe b)))
  (return 0))
EOF
  ./build/nucleusc --emit-llvm "$d/w24lib.nuc" > "$d/w24lib.ll"   2>/dev/null || true
  ./build/nucleusc --emit-nuch "$d/w24lib.nuc" > "$d/w24lib.nuch" 2>/dev/null || true
  ./build/nucleusc --emit-llvm "$d/w24use.nuc" > "$d/w24use.ll"   2>/dev/null || true

  # 1. The item's own failure, end to end: box a type whose implementation
  #    arrives through a header, dispatch through the box, link, run.
  if clang "$d/w24lib.ll" "$d/w24use.ll" -o "$d/bin" 2>/dev/null \
     && [ "$("$d/bin")" = "d=309" ]; then
    echo "PASS  w9-nuch-declare-dyn-box"
  else
    echo "FAIL  w9-nuch-declare-dyn-box"
  fi

  # 2. …through the symbol the LIBRARY defines, not merely some symbol that
  #    resolves. Slot 0 of the vtable is what the box calls through.
  if qgrep 'internal constant { ptr, ptr } { ptr @w24__describe,' "$d/w24use.ll"; then
    echo "PASS  w9-nuch-declare-vtable-symbol"
  else
    echo "FAIL  w9-nuch-declare-vtable-symbol"
  fi

  # 3. The other asker: `method-satisfies-sig`, so a consumer's own protocol can
  #    be satisfied by a method it imported.
  cat > "$d/w24ext.nuc" <<EOF
(import "$d/w24lib.nuch" wx)
(defprotocol Show (describe ((self (ref Self))) i32))
(extend wx/Fox Show)
(defn main ():i32 (return 0))
EOF
  if ./build/nucleusc --emit-llvm "$d/w24ext.nuc" > /dev/null 2>&1; then
    echo "PASS  w9-nuch-declare-extend-conforms"
  else
    echo "FAIL  w9-nuch-declare-extend-conforms"
  fi

  # 4. Two headers from different namespaces declaring the same signature are
  #    two distinct symbols, not a collision. They meet in one Generic only
  #    because the registry is bare-keyed (R2), and a duplicate-DEFINITION error
  #    there would be about definitions neither of these files makes. This
  #    worked before item 24 (the two declares never met) and must keep working.
  cat > "$d/w24na.nuc" <<'EOF'
(exclude-prelude)
(ns w24na)
(defn helper (x:i32):i32 (return x))
EOF
  cat > "$d/w24nb.nuc" <<'EOF'
(exclude-prelude)
(ns w24nb)
(defn helper (x:i32):i32 (return x))
EOF
  cat > "$d/w24two.nuc" <<EOF
(import-use "stdio.h")
(import "$d/w24na.nuch")
(import "$d/w24nb.nuch")
(defn main ():i32
  (printf "h=%d\n" (+ (w24na/helper 1) (w24nb/helper 20)))
  (return 0))
EOF
  for n in w24na w24nb; do
    ./build/nucleusc --emit-llvm "$d/$n.nuc" > "$d/$n.ll"   2>/dev/null || true
    ./build/nucleusc --emit-nuch "$d/$n.nuc" > "$d/$n.nuch" 2>/dev/null || true
  done
  ./build/nucleusc --emit-llvm "$d/w24two.nuc" > "$d/w24two.ll" 2>/dev/null || true
  if clang "$d/w24na.ll" "$d/w24nb.ll" "$d/w24two.ll" -o "$d/twobin" 2>/dev/null \
     && [ "$("$d/twobin")" = "h=21" ]; then
    echo "PASS  w9-nuch-declare-two-namespaces"
  else
    echo "FAIL  w9-nuch-declare-two-namespaces"
  fi
  rm -rf "$d"
}
spawn run_w9_nuch_declare_generic

# Stage 15 W9 item 36. `nuch-declare-import` skipped a header entry whose name was
# already bound, for idempotence — a diamond import, or a C header and a `.nuch`
# both naming one libc function. What it could not distinguish was a re-DECLARATION
# of the same function from a different function that happens to share the name, so
# a header entry the importing unit also DEFINES was dropped whole: no global
# binding, no LLVM `declare`, no generic method. Measured pre-fix: `(lib2/helper 3)`
# — a QUALIFIED call, naming the library — emitted `call i64 @helper`, the unit's
# own function, at a type the library's never had, with no diagnostic.
#
# The discriminator is "does this unit DEFINE the name", not "do the signatures
# differ": only a `defn` has a body, so a declaration answers no. Cases 1 and 2
# are the two halves that split on, and 2 is the one a signature comparison would
# have missed.
run_w9_nuch_declare_shadowed() {
  local d
  d="$(mktemp -d)"
  # The library excludes the prelude so its object and each consumer's link
  # together; that is also why its bodies are constants rather than arithmetic.
  cat > "$d/w36lib.nuc" <<'EOF'
(exclude-prelude)
(defn helper (x:i32):i32 (return 10))
(defn only-there (x:i32):i32 (return 4))
EOF
  ./build/nucleusc --emit-nuch "$d/w36lib.nuc" > "$d/w36lib.nuch" 2>/dev/null || true
  ./build/nucleusc --emit-llvm "$d/w36lib.nuc" > "$d/w36lib.ll"   2>/dev/null || true

  # 1. The item's own measured case: the local definition has a DIFFERENT type.
  cat > "$d/w36diff.nuc" <<EOF
(import-use "stdio.h")
(import "$d/w36lib.nuch" lib2)
(defn helper (x:i64):i64 (return (* 1000 x)))
(defn main ():i32 (printf "%d\n" (lib2/helper 3)) (return 0))
EOF
  local out out2
  out2="$(./build/nucleusc --emit-llvm "$d/w36diff.nuc" 2>&1 >/dev/null || true)"
  out="$out2"
  if printf '%s' "$out" | qgrep "already defines 'helper'" \
     && printf '%s' "$out" | qgrep "the header declares helper(i32):i32, the unit has helper(i64):i64"; then
    echo "PASS  w9-nuch-shadowed-declare-reported"
  else
    echo "FAIL  w9-nuch-shadowed-declare-reported"
    printf '%s\n' "$out" | sed 's/^/    /'
  fi

  # 2. The half a signature comparison would miss: same signature, still two
  #    different functions, still nothing that reaches the header's.
  cat > "$d/w36same.nuc" <<EOF
(import-use "stdio.h")
(import "$d/w36lib.nuch" lib2)
(defn helper (x:i32):i32 (return 1000))
(defn main ():i32 (printf "%d\n" (lib2/helper 3)) (return 0))
EOF
  # `|| true` inside the capture: the compiler exits 1 here by design, and under
  # `set -o pipefail` a bare pipeline would hand the `if` that status, not grep's.
  out="$(./build/nucleusc --emit-llvm "$d/w36same.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$out" | qgrep "already defines 'helper'"; then
    echo "PASS  w9-nuch-shadowed-same-signature-reported"
  else
    echo "FAIL  w9-nuch-shadowed-same-signature-reported"
  fi

  # 3. The message is located on the header entry AND names the definition it
  #    collides with — a bare "duplicate" would leave the author with two files
  #    and no line.
  if printf '%s' "$out2" | qgrep "w36lib.nuch:2: error: declare 'helper': this compilation unit already defines 'helper', at .*w36diff.nuc:3"; then
    echo "PASS  w9-nuch-shadowed-both-sites-named"
  else
    echo "FAIL  w9-nuch-shadowed-both-sites-named"
    printf '%s\n' "$out2" | sed 's/^/    /'
  fi

  # 4. ACCEPTING half A: the idempotent re-declaration the skip exists for must
  #    stay silent. `strlen` is declared by BOTH string.h and lib/string.nuch, and
  #    is one of the ten such pairs this repo compiles today.
  cat > "$d/w36dia.nuc" <<'EOF'
(import-use "string.h")
(import-use string)
(defn main ():i32 (return (unsafe/cast i32 (strlen "abc"))))
EOF
  if ./build/nucleusc --emit-llvm "$d/w36dia.nuc" > /dev/null 2>&1; then
    echo "PASS  w9-nuch-redeclare-still-silent"
  else
    echo "FAIL  w9-nuch-redeclare-still-silent"
  fi

  # 5. ACCEPTING half B: a name the unit does NOT define is untouched — the
  #    library's other export still declares, links and runs.
  cat > "$d/w36ok.nuc" <<EOF
(import-use "stdio.h")
(import "$d/w36lib.nuch" lib2)
(defn helper2 (x:i64):i64 (return 1000))
(defn main ():i32 (printf "o=%d\n" (lib2/only-there 3)) (return 0))
EOF
  ./build/nucleusc --emit-llvm "$d/w36ok.nuc" > "$d/w36ok.ll" 2>/dev/null || true
  if clang "$d/w36lib.ll" "$d/w36ok.ll" -o "$d/okbin" 2>/dev/null \
     && [ "$("$d/okbin")" = "o=4" ]; then
    echo "PASS  w9-nuch-unshadowed-declare-runs"
  else
    echo "FAIL  w9-nuch-unshadowed-declare-runs"
  fi

  # 6. The escape route the diagnostic RECOMMENDS has to work, or the note is
  #    bad advice: under an (ns ...) the header's exports key as `w36n/helper` and
  #    link as `@w36n__helper`, so the two functions coexist and both are callable.
  cat > "$d/w36nlib.nuc" <<'EOF'
(exclude-prelude)
(ns w36n)
(defn helper (x:i32):i32 (return 30))
EOF
  cat > "$d/w36nuse.nuc" <<EOF
(import-use "stdio.h")
(import "$d/w36nlib.nuch" nx)
(defn helper (x:i64):i64 (return 3000))
(defn main ():i32
  (printf "n=%d %d\n" (nx/helper 3) (helper (as i64 3)))
  (return 0))
EOF
  ./build/nucleusc --emit-nuch "$d/w36nlib.nuc" > "$d/w36nlib.nuch" 2>/dev/null || true
  ./build/nucleusc --emit-llvm "$d/w36nlib.nuc" > "$d/w36nlib.ll"   2>/dev/null || true
  ./build/nucleusc --emit-llvm "$d/w36nuse.nuc" > "$d/w36nuse.ll"   2>/dev/null || true
  if clang "$d/w36nlib.ll" "$d/w36nuse.ll" -o "$d/nbin" 2>/dev/null \
     && [ "$("$d/nbin")" = "n=30 3000" ]; then
    echo "PASS  w9-nuch-namespaced-library-coexists"
  else
    echo "FAIL  w9-nuch-namespaced-library-coexists"
  fi
  rm -rf "$d"
}
spawn run_w9_nuch_declare_shadowed

# W9 item 25: a generated C header must define a struct TAG, not just a typedef.
# `type-name-to-c` spells every reference to a user type `struct NAME`, so while
# `emit-cheader-defstruct` emitted an anonymous `typedef struct { … } NAME;` the
# tag was never completed and every BY-VALUE use of a library's own type failed —
# a field ("field has incomplete type 'struct Rec'") and a parameter alike.
#
# Measured alongside it, and a SECOND cause of the same broken headers: `Char`
# and `Err` are builtin scalars that lower to `i32`, and this name-keyed renderer
# had no case for either (the Type-keyed `type-to-c` always did), so they were
# emitted as `struct Char` / `struct Err` — the reason tagging alone left
# `lib/char.h` and `lib/error.h` uncompilable.
#
# Asserted by compiling and RUNNING a C consumer that nests the struct, reads the
# nested field and passes one by value: a header that merely parses could still
# disagree about layout, and `sum`/`hold` are wrong if it does.
run_w9_cheader_struct_tag() {
  local d out
  d="$(mktemp -d)"
  cat > "$d/tlib.nuc" <<'EOF'
(defstruct Rec a:i32 b:i32)
(defstruct Holder r:Rec n:i32)
(defunion Shape (circle r:i32) (square s:i32))
(defn rec-sum (r:Rec):i32
  (let (q:ptr:Rec (alloca Rec))
    (set! (deref q) r)
    (return (+ (q 'a) (q 'b)))))
(defn holder-sum (h:(ref Holder)):i32
  (let (q:ptr:Rec (alloca Rec))
    (set! (deref q) (h 'r))
    (return (+ (+ (q 'a) (q 'b)) (h 'n)))))
(defn ch-echo (c:Char):Char (return c))
EOF
  if ! ./build/nucleusc --emit-cheader "$d/tlib.nuc" > "$d/tlib.h" 2>"$d/err"; then
    echo "FAIL  w9-cheader-struct-tag (--emit-cheader failed)"; sed 's/^/    /' "$d/err"; rm -rf "$d"; return 0
  fi

  # Tag and typedef share a spelling — legal C, separate namespaces — so both
  # `Rec` and `struct Rec` name the completed type. A defunion is tagged for the
  # same reason: `type-name-to-c` answers `struct NAME` for a union name too.
  if qgrep -xF 'typedef struct Rec {' "$d/tlib.h" \
     && qgrep -xF 'typedef struct Holder {' "$d/tlib.h" \
     && qgrep -xF 'typedef struct Shape {' "$d/tlib.h"; then
    echo "PASS  w9-cheader-struct-tagged"
  else
    echo "FAIL  w9-cheader-struct-tagged"; grep -n 'typedef struct' "$d/tlib.h" | sed 's/^/    /'
  fi

  # A builtin scalar is not a struct. `Char` lowers to i32 (verified in the IR:
  # `define i64 @char-utf8-len(i32 %c.arg)`), so the C spelling is uint32_t.
  if qgrep -xF 'uint32_t ch_echo(uint32_t c) asm("ch-echo");' "$d/tlib.h" \
     && ! qgrep 'struct Char' "$d/tlib.h"; then
    echo "PASS  w9-cheader-builtin-scalar-not-struct"
  else
    echo "FAIL  w9-cheader-builtin-scalar-not-struct"; grep -n 'ch_echo\|struct Char' "$d/tlib.h" | sed 's/^/    /'
  fi

  cat > "$d/main.c" <<'EOF'
#include <stdio.h>
#include "tlib.h"
int main(void) {
    Holder h;
    h.r.a = 100; h.r.b = 7; h.n = 202;
    struct Rec byval = h.r;
    printf("sum=%d hold=%d ch=%u\n", rec_sum(byval), holder_sum(&h), ch_echo(0x1F600u));
    return 0;
}
EOF
  if ./build/nucleusc -c -o "$d/tlib.o" "$d/tlib.nuc" 2>"$d/err" \
     && clang -Wall -Werror -I "$d" "$d/main.c" "$d/tlib.o" -o "$d/tmain" 2>>"$d/err"; then
    out="$("$d/tmain")"
    if [ "$out" = "sum=107 hold=309 ch=128512" ]; then
      echo "PASS  w9-cheader-struct-by-value-c-consumer"
    else
      echo "FAIL  w9-cheader-struct-by-value-c-consumer (want 'sum=107 hold=309 ch=128512', got '$out')"
    fi
  else
    echo "FAIL  w9-cheader-struct-by-value-c-consumer (build failed)"; sed 's/^/    /' "$d/err" | head -8
  fi

  # The committed corpus is the real regression surface, asserted two ways that
  # do not move when the three still-open cheader defects (26/27/28) are closed.
  # First: no committed header may reintroduce an anonymous typedef, which is the
  # defect itself and is checkable without compiling anything.
  if ! grep -l 'typedef struct {' lib/*.h >/dev/null 2>&1; then
    echo "PASS  w9-cheader-no-anonymous-typedef"
  else
    echo "FAIL  w9-cheader-no-anonymous-typedef"; grep -l 'typedef struct {' lib/*.h | sed 's/^/    /'
  fi

  # Second: the two headers this item takes from broken to compiling. Item 4
  # measured 27 of the 34 lib/*.h parsing; these make it 29.
  local bad=""
  for hdr in char error; do
    printf '#include "%s.h"\nint main(void){return 0;}\n' "$hdr" > "$d/inc.c"
    clang -fsyntax-only -I lib "$d/inc.c" 2>/dev/null || bad="$bad $hdr.h"
  done
  if [ -z "$bad" ]; then
    echo "PASS  w9-cheader-lib-corpus-compiles"
  else
    echo "FAIL  w9-cheader-lib-corpus-compiles (still broken:$bad)"
  fi
  rm -rf "$d"
}
spawn run_w9_cheader_struct_tag

# W9 item 26: the C header must name the symbol each `defn` actually links as.
# `ns-ir-base` is that symbol only for a solitary, non-operator function — an
# overload is mangled per signature, and an operator goes through
# `op-name-token` even when it is the sole user method (its generic always
# carries an intrinsic seed). The header used to derive the solitary form
# unconditionally, so it declared symbols no object defines, twice under one C
# name. The invariant is checked against `nm`, not against a hardcoded list.
run_w9_cheader_overload_symbols() {
  local d out miss sym
  d="$(mktemp -d)"
  cat > "$d/ovlib.nuc" <<'EOF'
(defstruct Pt x:i32 y:i32)
(defn scale (p:(ref Pt) k:i32):i32 (return (* (+ (p 'x) (p 'y)) k)))
(defn scale (a:i32 k:i32):i32 (return (* a k)))
(defn = (a:Pt b:Pt):bool
  (let (la:Pt a lb:Pt b)
    (return (if (and (= ((addr-of la) 'x) ((addr-of lb) 'x))
                     (= ((addr-of la) 'y) ((addr-of lb) 'y))) true false))))
(defn solo (n:i32):i32 (return (+ n 1)))
EOF
  if ! ./build/nucleusc --emit-cheader "$d/ovlib.nuc" > "$d/ovlib.h" 2>"$d/err"; then
    echo "FAIL  w9-cheader-overload-symbols (--emit-cheader failed)"; sed 's/^/    /' "$d/err"; rm -rf "$d"; return 0
  fi

  # Each method gets its own C name and its own label; the solitary one keeps
  # its bare name and needs no label at all.
  if qgrep -xF 'int32_t scale_pPt_i32(void* p, int32_t k) asm("scale.pPt.i32");' "$d/ovlib.h" \
     && qgrep -xF 'int32_t scale_i32_i32(int32_t a, int32_t k) asm("scale.i32.i32");' "$d/ovlib.h" \
     && qgrep -xF 'bool eq_Pt_Pt(struct Pt a, struct Pt b) asm("eq.Pt.Pt");' "$d/ovlib.h" \
     && qgrep -xF 'int32_t solo(int32_t n);' "$d/ovlib.h"; then
    echo "PASS  w9-cheader-overload-distinct-symbols"
  else
    echo "FAIL  w9-cheader-overload-distinct-symbols"; grep -n 'scale\|eq_\|solo' "$d/ovlib.h" | sed 's/^/    /'
  fi

  if ! ./build/nucleusc -c -o "$d/ovlib.o" "$d/ovlib.nuc" 2>"$d/err"; then
    echo "FAIL  w9-cheader-symbol-defined (compile failed)"; sed 's/^/    /' "$d/err" | head -5
  else
    # The invariant, stated against the object rather than against a list: every
    # symbol the header binds to must be one the object defines.
    nm -g --defined-only "$d/ovlib.o" | awk '$2=="T"||$2=="W"{print $3}' | sort -u > "$d/syms"
    miss=""
    for sym in $(grep -oE 'asm\("[^"]+"\)' "$d/ovlib.h" | sed 's/asm("//;s/")//'); do
      qgrep -xF "$sym" "$d/syms" || miss="$miss $sym"
    done
    if [ -z "$miss" ]; then
      echo "PASS  w9-cheader-symbol-defined"
    else
      echo "FAIL  w9-cheader-symbol-defined (header names undefined symbols:$miss)"
    fi

    cat > "$d/main.c" <<'EOF'
#include <stdio.h>
#include "ovlib.h"
int main(void) {
    Pt p = {3, 4};
    Pt q = {3, 4};
    printf("a=%d b=%d eq=%d solo=%d\n",
           scale_pPt_i32(&p, 10), scale_i32_i32(6, 7), (int)eq_Pt_Pt(p, q), solo(41));
    return 0;
}
EOF
    if clang -Wall -Werror -I "$d" "$d/main.c" "$d/ovlib.o" -o "$d/ovmain" 2>"$d/err"; then
      out="$("$d/ovmain")"
      if [ "$out" = "a=70 b=42 eq=1 solo=42" ]; then
        echo "PASS  w9-cheader-overload-c-consumer"
      else
        echo "FAIL  w9-cheader-overload-c-consumer (want 'a=70 b=42 eq=1 solo=42', got '$out')"
      fi
    else
      echo "FAIL  w9-cheader-overload-c-consumer (link failed)"; sed 's/^/    /' "$d/err" | head -8
    fi
  fi

  # The committed corpus. An operator's C name sanitized to `_` is the defect's
  # signature — two of them in one header is what made `string.h`/`strview.h`
  # unparseable — and no header may bind a label C could not have produced.
  if ! qgrep -E '^[A-Za-z_].* _\(' lib/*.h && ! qgrep -E 'asm\("[<>=!+*/%-]+"\)' lib/*.h; then
    echo "PASS  w9-cheader-no-operator-c-name"
  else
    echo "FAIL  w9-cheader-no-operator-c-name"; grep -nE '^[A-Za-z_].* _\(|asm\("[<>=!+*/%-]+"\)' lib/*.h | sed 's/^/    /'
  fi

  # The four headers this item takes from broken to compiling.
  local bad=""
  for hdr in parse string strview keyword; do
    printf '#include "%s.h"\nint main(void){return 0;}\n' "$hdr" > "$d/inc.c"
    clang -fsyntax-only -I lib "$d/inc.c" 2>/dev/null || bad="$bad $hdr.h"
  done
  if [ -z "$bad" ]; then
    echo "PASS  w9-cheader-overload-lib-corpus-compiles"
  else
    echo "FAIL  w9-cheader-overload-lib-corpus-compiles (still broken:$bad)"
  fi
  rm -rf "$d"
}
spawn run_w9_cheader_overload_symbols

# The twenty-eighth defect. `sanitize-for-c` maps illegal *characters*, so a
# Nucleus name that happens to be a C or C++ reserved word — `union`, `signed`,
# `class`, `delete` — reached the header intact and it did not parse. Each is
# renamed with a trailing `_` and re-bound with an asm label, so the symbol is
# unchanged and only the C spelling moves. The fixture puts a keyword in every
# position the emitter produces an identifier for: a function, a parameter, a
# struct field, a struct tag used by value in both parameter and return position,
# a global, and an enum whose members are keywords behind a prefix.
run_w9_cheader_reserved_words() {
  local d out miss sym
  d="$(mktemp -d)"
  cat > "$d/kwlib.nuc" <<'EOF'
(defstruct Box class:i32 signed:i32)
(defstruct class x:i32)
(defenum Kind auto static default)
(defconst SIGNED-LIMIT 7)
(defvar delete:i32 41)
(defn union (a:i32 b:i32):i32 (return (bit-or a b)))
(defn xor (a:i32 default:i32):i32 (return (bit-xor a default)))
(defn plain (b:(ref Box)):i32 (return (+ (b 'class) (b 'signed))))
(defn bump (v:class):class
  (let (l:class v)
    (set! ((addr-of l) 'x) (+ ((addr-of l) 'x) 1))
    (return l)))
EOF
  if ! ./build/nucleusc --emit-cheader "$d/kwlib.nuc" > "$d/kwlib.h" 2>"$d/err"; then
    echo "FAIL  w9-cheader-reserved-words (--emit-cheader failed)"; sed 's/^/    /' "$d/err"; rm -rf "$d"; return 0
  fi

  # The tag and the by-value reference to it must move together, or the header
  # parses and then names a type it never defines.
  if qgrep -xF '    int32_t class_;' "$d/kwlib.h" \
     && qgrep -xF '    int32_t signed_;' "$d/kwlib.h" \
     && qgrep -xF 'typedef struct class_ {' "$d/kwlib.h" \
     && qgrep -xF 'struct class_ bump(struct class_ v);' "$d/kwlib.h" \
     && qgrep -xF 'extern int32_t delete_ asm("delete");' "$d/kwlib.h" \
     && qgrep -xF 'int32_t union_(int32_t a, int32_t b) asm("union");' "$d/kwlib.h" \
     && qgrep -xF 'int32_t xor_(int32_t a, int32_t default_) asm("xor");' "$d/kwlib.h" \
     && qgrep -xF 'int32_t plain(void* b);' "$d/kwlib.h"; then
    echo "PASS  w9-cheader-reserved-escaped"
  else
    echo "FAIL  w9-cheader-reserved-escaped"; sed 's/^/    /' "$d/kwlib.h" | sed -n '7,40p'
  fi

  # A prefixed member is already an identifier; escaping the fragment would
  # rename `Kind_default` for no reason. The escape belongs on the join.
  if qgrep -xF '    Kind_default = 2' "$d/kwlib.h"; then
    echo "PASS  w9-cheader-reserved-join-not-fragment"
  else
    echo "FAIL  w9-cheader-reserved-join-not-fragment"; grep -n 'Kind' "$d/kwlib.h" | sed 's/^/    /'
  fi

  if ! ./build/nucleusc -c -o "$d/kwlib.o" "$d/kwlib.nuc" 2>"$d/err"; then
    echo "FAIL  w9-cheader-reserved-symbol-defined (compile failed)"; sed 's/^/    /' "$d/err" | head -5
  else
    # Renaming the C identifier must not move the symbol.
    nm -g --defined-only "$d/kwlib.o" | awk '$2!="U"{print $3}' | sort -u > "$d/syms"
    miss=""
    for sym in $(grep -oE 'asm\("[^"]+"\)' "$d/kwlib.h" | sed 's/asm("//;s/")//'); do
      qgrep -xF "$sym" "$d/syms" || miss="$miss $sym"
    done
    if [ -z "$miss" ]; then
      echo "PASS  w9-cheader-reserved-symbol-defined"
    else
      echo "FAIL  w9-cheader-reserved-symbol-defined (header names undefined symbols:$miss)"
    fi

    cat > "$d/main.c" <<'EOF'
#include <stdio.h>
#include "kwlib.h"
int main(void) {
    Box b = {3, 4};
    class_ c = {8};
    printf("u=%d x=%d p=%d n=%d k=%d d=%d s=%d\n",
           union_(8, 1), xor_(6, 3), plain(&b), bump(c).x,
           (int)Kind_default, delete_, SIGNED_LIMIT);
    return 0;
}
EOF
    if clang -Wall -Werror -I "$d" "$d/main.c" "$d/kwlib.o" -o "$d/kwmain" 2>"$d/err"; then
      out="$("$d/kwmain")"
      if [ "$out" = "u=9 x=5 p=7 n=9 k=2 d=41 s=7" ]; then
        echo "PASS  w9-cheader-reserved-c-consumer"
      else
        echo "FAIL  w9-cheader-reserved-c-consumer (want 'u=9 x=5 p=7 n=9 k=2 d=41 s=7', got '$out')"
      fi
    else
      echo "FAIL  w9-cheader-reserved-c-consumer (build failed)"; sed 's/^/    /' "$d/err" | head -8
    fi

    # Why the table carries C++'s keywords too: a generated header is routinely
    # read through `extern "C"` from C++, where `class` and `delete` are as fatal
    # as `union` is in C.
    if ! command -v c++ >/dev/null 2>&1; then
      echo "SKIP  w9-cheader-reserved-cxx-consumer (no c++ in PATH)"
    else
      sed 's|#include "kwlib.h"|extern "C" {\n#include "kwlib.h"\n}|' "$d/main.c" > "$d/main.cpp"
      if c++ -Wall -Werror -I "$d" "$d/main.cpp" "$d/kwlib.o" -o "$d/kwmainxx" 2>"$d/err"; then
        out="$("$d/kwmainxx")"
        if [ "$out" = "u=9 x=5 p=7 n=9 k=2 d=41 s=7" ]; then
          echo "PASS  w9-cheader-reserved-cxx-consumer"
        else
          echo "FAIL  w9-cheader-reserved-cxx-consumer (want 'u=9 x=5 p=7 n=9 k=2 d=41 s=7', got '$out')"
        fi
      else
        echo "FAIL  w9-cheader-reserved-cxx-consumer (build failed)"; sed 's/^/    /' "$d/err" | head -8
      fi
    fi
  fi
  rm -rf "$d"
}
spawn run_w9_cheader_reserved_words

# The tenth defect (`protocol-dyn-annot`). An annotation naming a protocol that
# exists nowhere used to compile and fabricate a box type; admission now happens
# at the annotation site, deferred to `drain-dyn-annots`. Nothing in this fixture
# constructs a box, so only the annotation path can reach it.
spawn run_reject_at b6-dyn-annot-unknown tests/fixtures/b6-dyn-annot-unknown.nuc \
  "tests/fixtures/b6-dyn-annot-unknown.nuc:17: error:" \
  "(dyn nope/Wholly-Absent): 'nope/Wholly-Absent' is not a declared protocol"
# The erased-slot coercion's missing identity check, pinned at BOTH of its call
# sites: the argument position (its own blocks in emit-call-with-args) and the
# binding position (maybe-box-into-slot). The argument one is the one that
# mattered — the SysV ABI splits the fat pointer into two i64s at the call, so
# LLVM never saw the mismatch and the program linked and ran against the wrong
# vtable.
spawn run_reject_at b6-dyn-box-mismatch-arg tests/fixtures/b6-dyn-box-mismatch-arg.nuc \
  "tests/fixtures/b6-dyn-box-mismatch-arg.nuc:30: error:" \
  "type mismatch: a (dyn Pp) value cannot be used where (dyn Qq) is required"
spawn run_reject_at b6-dyn-box-mismatch-let tests/fixtures/b6-dyn-box-mismatch-let.nuc \
  "tests/fixtures/b6-dyn-box-mismatch-let.nuc:29: error:" \
  "type mismatch: a (dyn Pp) value cannot be used where (dyn Qq) is required"

# --- Stage 15 B4: generics get a qualified spelling ---------------------------
# name-resolution.md §8.2 (R2) / defect #5. A generic is deliberately NOT re-keyed
# by namespace — one Generic per bare name, methods merged, which is what keeps
# `import-use` of two libraries that each declare a `describe` usable. The
# qualified spelling is recovered from `Method.src-ns` instead, so `pa/name`
# resolves to the bare generic FILTERED to the namespace `pa` denotes.
#
# The filtering is what has to be pinned, not just the lookup: two namespaces
# each define a `b4-desc`, at different arities so both can live in one merged
# method set, and each prefix must reach exactly its own.
run_b4_qualified_generic() {
  local d err
  d="$(mktemp -d)"
  cat > "$d/b4-glib-a.nuc" <<'EOF'
(ns b4a)
(defn b4-desc (x:i32):i32 (return (+ x 100)))
EOF
  cat > "$d/b4-glib-b.nuc" <<'EOF'
(ns b4b)
(defn b4-desc (x:i32 y:i32):i32 (return (+ (+ x y) 20)))
EOF
  cat > "$d/b4-guse.nuc" <<'EOF'
(import-prefixed b4-glib-a pa)
(import-prefixed b4-glib-b pb)
(defn main ():i32 (return (+ (pa/b4-desc 1) (pb/b4-desc 1 2))))
EOF
  w1_run b4-qualified-generic "$d" "$d/b4-guse.nuc" 124

  # The filter is real: `pa/` may not reach the arity `b4b` defined. Before B4
  # this said "unknown: pa/b4-desc" (no qualified spelling at all); a lookup that
  # merely ignored the qualifier would resolve it and return 23.
  cat > "$d/b4-gwrong.nuc" <<'EOF'
(import-prefixed b4-glib-a pa)
(import-prefixed b4-glib-b pb)
(defn main ():i32 (return (pa/b4-desc 1 2)))
EOF
  err="$(./build/nucleusc -I "$d" --emit-llvm "$d/b4-gwrong.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep -F "no matching method for overloaded 'b4-desc' with argument types (i32, i32)"; then
    echo "PASS  b4-qualified-generic-filtered"
  else
    echo "FAIL  b4-qualified-generic-filtered (the qualifier did not restrict the method set)"
    printf '%s\n' "$err" | sed 's/^/    /'
  fi

  # …and R3 still holds for generics: the DEFINING namespace is not in scope in a
  # file that asked for a prefix.
  cat > "$d/b4-gns.nuc" <<'EOF'
(import-prefixed b4-glib-a pa)
(import-prefixed b4-glib-b pb)
(defn main ():i32 (return (b4a/b4-desc 1)))
EOF
  err="$(./build/nucleusc -I "$d" --emit-llvm "$d/b4-gns.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep -F "unknown: b4a/b4-desc — 'b4a' is not in scope in this file"; then
    echo "PASS  b4-qualified-generic-ns-refused"
  else
    echo "FAIL  b4-qualified-generic-ns-refused (wrong or missing diagnostic)"
    printf '%s\n' "$err" | sed 's/^/    /'
  fi
  rm -rf "$d"
}
spawn run_b4_qualified_generic

# A bounded-generic TEMPLATE through a prefix, stamped twice for one concrete
# type. Two things only this shape reaches: `register-generic-template` records
# no provenance of its own (it does not go through `generic-register-method`), so
# before B4 a METHOD-GENERIC filtered to nothing and `pg/b4-twice` did not resolve
# at all; and a stamp is registered under the CALL SITE's namespace, so without
# re-owning it to the template's the second call filters the first stamp out,
# `generic-find-method-exact`'s memo misses, and the instance is emitted twice
# under one symbol. Both are link-time failures, so the run is the check: two i32
# stamps of one instance (3+3, 5+5) plus an i16 one (4+4) = 24.
run_b4_qualified_template() {
  local d
  d="$(mktemp -d)"
  cat > "$d/b4-tlib.nuc" <<'EOF'
(ns b4g)
(defprotocol B4Num (b4-zero (self:Self):i32))
(defn b4-zero (x:i32):i32 (return x))
(defn b4-zero (x:i16):i32 (return (as i32 x)))
(extend i32 B4Num)
(extend i16 B4Num)
(defn b4-twice (x:T :where (B4Num T)):i32
  (return (+ (b4-zero x) (b4-zero x))))
EOF
  cat > "$d/b4-tuse.nuc" <<'EOF'
(import-prefixed b4-tlib pg)
(defn main ():i32
  (let (s:i16 4)
    (return (+ (pg/b4-twice 3) (+ (pg/b4-twice 5) (pg/b4-twice s))))))
EOF
  w1_run b4-qualified-template "$d" "$d/b4-tuse.nuc" 24
  rm -rf "$d"
}
spawn run_b4_qualified_template

# The per-kind collision rule (§8.2's table, §14.2's `collides` column). Of the
# three rows that were 0, only `BK-ENUM` hid a real hole: a `defunion` also
# registers a backing StructDef under the same key so `BK-STRUCT` already
# answered for it, and `__fnty_N` has no source spelling — but an enum registers
# only its MEMBERS, so its own name collided with nothing.
spawn run_reject_at b4-enum-vs-defn tests/fixtures/b4-enum-vs-defn.nuc \
  "tests/fixtures/b4-enum-vs-defn.nuc:13: error:" \
  "'Colour' already names an enumeration — a symbol may name only one kind of thing"
spawn run_reject_at b4-enum-vs-defvar tests/fixtures/b4-enum-vs-defvar.nuc \
  "tests/fixtures/b4-enum-vs-defvar.nuc:6: error:" \
  "'Colour' already names an enumeration — a symbol may name only one kind of thing"

# R4's eager rule (§11.1): two definitions of one name reaching one scope. Every
# kind measured before B4 accepted this silently and with no agreed winner — a
# second defstruct/defunion/defprotocol/defmacro/template kept the FIRST, a
# second defconst kept the SECOND, and a second defvar reached LLVM's own parser
# with no source location. One case per row of §8.2's table, checked as a table
# so a kind that stops reporting is visible as one line.
run_b4_redefinition() {
  local d err name body pat n
  d="$(mktemp -d)"
  cat > "$d/b4r-struct.nuc" <<'EOF'
(defstruct RdS a:i32)
(defstruct RdS b:i32 c:i32)
(defn main ():i32 (return 0))
EOF
  cat > "$d/b4r-union.nuc" <<'EOF'
(defunion RdU (ra x:i32) (rb y:i32))
(defunion RdU (rc x:i32))
(defn main ():i32 (return 0))
EOF
  cat > "$d/b4r-proto.nuc" <<'EOF'
(defprotocol RdP (rm (self:Self):i32))
(defprotocol RdP (rn (self:Self):i32))
(defn main ():i32 (return 0))
EOF
  cat > "$d/b4r-macro.nuc" <<'EOF'
(defmacro rd-m (x) x)
(defmacro rd-m (x) 99)
(defn main ():i32 (return (rd-m 0)))
EOF
  cat > "$d/b4r-enum.nuc" <<'EOF'
(defenum RdE rd-a rd-b)
(defenum RdE rd-c rd-d)
(defn main ():i32 (return 0))
EOF
  cat > "$d/b4r-enum-member.nuc" <<'EOF'
(defenum RdE1 rd-x rd-y)
(defenum RdE2 rd-y rd-z)
(defn main ():i32 (return rd-y))
EOF
  cat > "$d/b4r-tmpl.nuc" <<'EOF'
(defstruct (RdBox T) v:T)
(defstruct (RdBox T) w:T)
(defn main ():i32 (return 0))
EOF
  cat > "$d/b4r-utmpl.nuc" <<'EOF'
(defunion (RdRes T) (rok v:T) (rno))
(defunion (RdRes T) (ryes v:T))
(defn main ():i32 (return 0))
EOF
  cat > "$d/b4r-var.nuc" <<'EOF'
(defvar rd-v:i32 1)
(defvar rd-v:i32 2)
(defn main ():i32 (return rd-v))
EOF
  cat > "$d/b4r-const.nuc" <<'EOF'
(defconst RD-K 1)
(defconst RD-K 2)
(defn main ():i32 (return RD-K))
EOF
  while read -r name pat; do
    [ -n "$name" ] || continue
    err="$(./build/nucleusc -I "$d" --emit-llvm "$d/$name.nuc" 2>&1 >/dev/null || true)"
    if printf '%s' "$err" | qgrep ':0:'; then
      echo "FAIL  $name (diagnostic reports line 0)"
      printf '%s\n' "$err" | sed 's/^/    /'
    elif printf '%s' "$err" | qgrep -F "redefinition of '$pat'" \
      && printf '%s' "$err" | qgrep -F "$d/$name.nuc:2: error:"; then
      echo "PASS  $name"
    else
      echo "FAIL  $name (no located redefinition diagnostic)"
      printf '%s\n' "$err" | sed 's/^/    got: /'
    fi
  done <<'ROWS'
b4r-struct RdS
b4r-union RdU
b4r-proto RdP
b4r-macro rd-m
b4r-enum RdE
b4r-enum-member rd-y
b4r-tmpl RdBox
b4r-utmpl RdRes
b4r-var rd-v
b4r-const RD-K
ROWS

  # The shape R4 was actually written for (§11.1): the two definitions are in two
  # different FILES and neither file can see the other. `lib/prelude.nuc` and
  # `lib/list.nuc` both defining `Node` with different field nullability was this,
  # and the winner was decided by import order. The diagnostic must name the other
  # file, which is the whole reason the definition records carry `src-file`.
  printf '(defstruct RdX n:i32)\n' > "$d/b4r-fa.nuc"
  printf '(defstruct RdX n:i32 m:i32)\n' > "$d/b4r-fb.nuc"
  printf '(import b4r-fa)\n(import b4r-fb)\n(defn main ():i32 (return 0))\n' > "$d/b4r-fm.nuc"
  err="$(./build/nucleusc -I "$d" --emit-llvm "$d/b4r-fm.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep -F "redefinition of 'RdX'" \
     && printf '%s' "$err" | qgrep -F "$d/b4r-fa.nuc:1"; then
    echo "PASS  b4-redefinition-cross-file"
  else
    echo "FAIL  b4-redefinition-cross-file (did not name the other file)"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi

  # Equal values are NOT an exemption. The first external program to meet R4 —
  # the Doom port, 2026-08-15 — collided on seven same-valued `defconst`s in
  # five file pairs, two of them commented as deliberate copies, so this is the
  # shape a future relaxation would be tempted by. Pinned because the rule is
  # about a name having one meaning, not about detecting disagreement: letting
  # equal values through means the compiler decides which collisions matter.
  printf '(defconst RD-EQ 7)\n' > "$d/b4r-eqa.nuc"
  printf '(defconst RD-EQ 7)\n' > "$d/b4r-eqb.nuc"
  printf '(import b4r-eqa)\n(import b4r-eqb)\n(defn main ():i32 (return RD-EQ))\n' > "$d/b4r-eqm.nuc"
  err="$(./build/nucleusc -I "$d" --emit-llvm "$d/b4r-eqm.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep -F "redefinition of 'RD-EQ'" \
     && printf '%s' "$err" | qgrep -F "$d/b4r-eqa.nuc:1"; then
    echo "PASS  b4-redefinition-same-value"
  else
    echo "FAIL  b4-redefinition-same-value (equal values were accepted, or the other file was not named)"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi

  # …and the fix the diagnostic recommends has to work: one owner, reached by
  # `import`. This is the migration the port took, and it is the half of the
  # ruling that makes it liveable rather than merely strict.
  printf '(defconst RD-OWN 7)\n' > "$d/b4r-owna.nuc"
  printf '(import b4r-owna)\n(defn rd-own-b ():i32 (return RD-OWN))\n' > "$d/b4r-ownb.nuc"
  printf '(import b4r-owna)\n(import b4r-ownb)\n(defn main ():i32 (return (+ RD-OWN (rd-own-b))))\n' > "$d/b4r-ownm.nuc"
  w1_run b4-redefinition-same-value-fix "$d" "$d/b4r-ownm.nuc" 14

  # The rule is per compilation unit, so re-importing one file through two paths
  # — the diamond every non-trivial program has — must stay legal. This is what
  # `same-definition-site` protects: the registrars really are re-entered.
  printf '(defstruct RdD n:i32)\n(defunion RdDU (da x:i32) (db))\n(defprotocol RdDP (dm (self:Self):i32))\n(defmacro rd-dm (x) x)\n(defenum RdDE rd-da rd-db)\n(defconst RD-DK 3)\n(defstruct (RdDBox T) v:T)\n' > "$d/b4r-diamond.nuc"
  printf '(import b4r-diamond)\n(defn rd-l ():i32 (return RD-DK))\n' > "$d/b4r-dl.nuc"
  printf '(import b4r-diamond)\n(defn rd-r ():i32 (return rd-da))\n' > "$d/b4r-dr.nuc"
  printf '(import b4r-dl)\n(import b4r-dr)\n(import b4r-diamond)\n(defn main ():i32 (return (+ (rd-l) (rd-r))))\n' > "$d/b4r-dm.nuc"
  w1_run b4-redefinition-diamond-ok "$d" "$d/b4r-dm.nuc" 3
  rm -rf "$d"
}
spawn run_b4_redefinition

# --- Stage 16: macrolet (design/stage16-ergonomics/macrolet.md) -----------------
# Lexically scoped macros. The exit code is a bitmask of FAILED checks, so a
# regression names itself instead of reporting one anonymous wrong number.
run_s16_macrolet() {
  local d
  d="$(mktemp -d)"
  cat > "$d/s16-ml.nuc" <<'EOF'
(defmacro dbl (x) `(_* 2 ~x))

; A binding shadows a global macro for the body and only for the body.
(defn ml-shadow ():i32
  (let (r:i32 0)
    (set! r (dbl 5))
    (macrolet ((dbl (x) `(_* 3 ~x)))
      (set! r (_+ r (dbl 5))))
    (_+ r (dbl 5))))

; Bindings are sequential (like Nucleus `let`, unlike Common Lisp's parallel
; macrolet): `two` sees `one`.
(defn ml-seq ():i32
  (macrolet ((one () `1)
             (two () `(_+ (one) (one))))
    (two)))

; An inner binding shadows an outer one of the same name; the outer is restored
; after the inner body. This is the pop.
(defn ml-nest ():i32
  (macrolet ((m () `10))
    (_+ (macrolet ((m () `100)) (m))
        (m))))

(defn ml-rest ():i32
  (macrolet ((sum3 (a :rest more) `(_+ ~a (_+ ~@more))))
    (sum3 1 2 3)))

; The enclosing function's entry/body streams must survive the nested macro
; compilation — a macrolet inside a loop body is the cheapest proof.
(defn ml-loop ():i32
  (let (acc:i32 0 i:i32 0)
    (while (< i 4)
      (macrolet ((bump () `(set! acc (_+ acc i))))
        (bump))
      (inc! i))
    acc))

(defn main ():i32
  (let (bad:i32 0)
    (when (!= (ml-shadow) 35) (set! bad (_+ bad 1)))
    (when (!= (ml-seq)     2) (set! bad (_+ bad 2)))
    (when (!= (ml-nest)  110) (set! bad (_+ bad 4)))
    (when (!= (ml-rest)    6) (set! bad (_+ bad 8)))
    (when (!= (ml-loop)    6) (set! bad (_+ bad 16)))
    (return bad)))
EOF
  w1_run s16-macrolet "$d" "$d/s16-ml.nuc" 0

  # A macrolet in ARGUMENT position sits mid-argument-walk, so the ambient
  # argument-register budget (g-abi-gpr-left/…) has to survive the nested
  # emission — by-value structs of both ABI classes make that observable.
  # Plus: a macrolet in a `cond` arm, and one inside a generic template body
  # (compiled once per monomorphization, hence the monotonic jit-name counter).
  cat > "$d/s16-ml2.nuc" <<'EOF'
(import-use numeric)
(defstruct Big a:i64 b:i64 c:i64)
(defstruct Pair x:i64 y:i64)

(defn take6 (p:Pair q:Pair b:Big n:i32 m:i32):i64
  (let (pp:ptr:Pair (addr-of p) qq:ptr:Pair (addr-of q) bb:ptr:Big (addr-of b))
    (_+ (_+ (pp 'x) (qq 'y)) (_+ (bb 'c) (as i64 (_+ n m))))))

(defn ml-argpos ():i64
  (let (p:Pair (Pair 1 2) q:Pair (Pair 3 4) b:Big (Big 5 6 7))
    (take6 p q b 10 (macrolet ((twenty () `20)) (twenty)))))

(defn ml-cond (n:i32):i32
  (cond (= n 0) (macrolet ((z () `100)) (z))
        (= n 1) (macrolet ((o (k) `(_* ~k 3))) (o 7))
        true    (macrolet ((d () `(_- 0 1))) (d))))

(defn ml-maxish (a:T b:T :where (Ord T)):T
  (macrolet ((pick (x y) `(if (< ~x ~y) ~y ~x)))
    (pick a b)))

(defn main ():i32
  (let (bad:i32 0)
    (when (!= (ml-argpos) (as i64 42)) (set! bad (_+ bad 1)))
    (when (!= (ml-cond 0) 100) (set! bad (_+ bad 2)))
    (when (!= (ml-cond 1)  21) (set! bad (_+ bad 4)))
    (when (!= (ml-cond 2)  -1) (set! bad (_+ bad 8)))
    (when (!= (ml-maxish 21 9) 21) (set! bad (_+ bad 16)))
    (when (!= (ml-maxish (as i64 50) (as i64 77)) (as i64 77)) (set! bad (_+ bad 32)))
    (return bad)))
EOF
  w1_run s16-macrolet-abi "$d" "$d/s16-ml2.nuc" 0

  # A macrolet inside a `defmacro` BODY: one macro JIT module compiled while
  # another is compiling. The hoist-to-a-pre-pass alternative could not do this;
  # push-function-state can. `(a car)` on the INT node `5` is null, so `pick`
  # expands to its second argument.
  cat > "$d/s16-ml3.nuc" <<'EOF'
(defmacro pick (a b)
  (macrolet ((first-of (x) `(~x 'car)))
    (if (= (first-of a) null) b a)))
(defn main ():i32 (return (pick 5 6)))
EOF
  w1_run s16-macrolet-in-defmacro "$d" "$d/s16-ml3.nuc" 6
  rm -rf "$d"
}
spawn run_s16_macrolet

# Every malformed spelling has a located message, and none of them crashes.
# The special-form row is the load-bearing one: emit-list consults the macro
# table BEFORE special forms, so a binding named `let` would silently take over
# `let` for the whole body if this were not refused.
run_s16_macrolet_refused() {
  local d src err want n
  d="$(mktemp -d)"
  n=0
  while IFS='|' read -r name src want; do
    [ -n "$name" ] || continue
    printf '%s\n' "$src" > "$d/$name.nuc"
    err="$(./build/nucleusc --emit-llvm "$d/$name.nuc" 2>&1 >/dev/null || true)"
    if printf '%s' "$err" | qgrep -F "$want"; then
      echo "PASS  s16-macrolet-refused-$name"
    else
      echo "FAIL  s16-macrolet-refused-$name (wrong or missing diagnostic)"
      printf '%s\n' "$err" | sed 's/^/    got: /'
    fi
  done <<'EOF'
noargs|(defn main ():i32 (macrolet) 0)|macrolet: expects a binding list and at least one body form
nobody|(defn main ():i32 (macrolet ((m () `1))) 0)|macrolet: expects a binding list and at least one body form
badbind|(defn main ():i32 (macrolet (m) 0))|macrolet: binding must be (name (params) body...)
badname|(defn main ():i32 (macrolet ((5 () `1)) 0))|macrolet: macro name must be a symbol
badparams|(defn main ():i32 (macrolet ((m 5 `1)) 0))|macrolet: params must be a list
badparam|(defn main ():i32 (macrolet ((m (5) `1)) 0))|macrolet: param must be a symbol
special|(defn main ():i32 (macrolet ((let (x) `1)) 0))|macrolet: 'let' is a special form and may not be shadowed
restpos|(defn main ():i32 (macrolet ((m (:rest a b) `1)) 0))|macrolet: :rest must be second-to-last param
colon|(defn main ():i32 (macrolet ((m:i32 () `1)) 0))|macrolet: a binding name takes no type annotation; write (m (params) ...)
toplevel|(macrolet ((m () `1)) (m))|unknown top-level form: macrolet
EOF
  rm -rf "$d"
}
spawn run_s16_macrolet_refused

# A macro whose whole expansion is an ATOM. `emit-quote-tree` emits
# @alloc-node / @make-cell / @intern-symbol without ever touching the
# __cons/__append helpers, so gating their `declare`s on the quasiquote-LIST
# flag left the JIT module with "use of undefined value '@alloc-node'". A
# pre-existing defmacro bug (it reproduced on the stage-15 boot compiler);
# found via macrolet, where one-atom bodies are the common case. The non-symbol
# param row is the sibling crash: Node.s is null on an INT node and the :rest
# probe is a content compare, so `(defmacro m (5) …)` segfaulted the compiler.
run_s16_atom_macro() {
  local d err
  d="$(mktemp -d)"
  cat > "$d/s16-atom.nuc" <<'EOF'
(defmacro one () `1)
(defmacro sym-of () `x)
(defmacro quoted () 'y)
(defn main ():i32
  (let (x:i32 40 y:i32 2)
    (macrolet ((two () `2))
      (return (_+ (one) (_+ (two) (_+ (sym-of) (quoted))))))))
EOF
  w1_run s16-atom-macro "$d" "$d/s16-atom.nuc" 45

  printf '(defmacro m (5) `1)\n(defn main ():i32 0)\n' > "$d/s16-badparam.nuc"
  err="$(./build/nucleusc --emit-llvm "$d/s16-badparam.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep -F "defmacro: param must be a symbol"; then
    echo "PASS  s16-defmacro-nonsym-param"
  else
    echo "FAIL  s16-defmacro-nonsym-param (crashed, or wrong diagnostic)"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi
  rm -rf "$d"
}
spawn run_s16_atom_macro

# Stage 16 — keyword elements in container literals, and the error surface around
# them. The success paths live in examples/keyword-lit-test.nuc; what needs a
# fixture is the refusals, which had NO coverage before this item (recorded in
# design/stage16-ergonomics/container-literal-elements.md §1).
#
# The import row is the load-bearing one. `Keyword` is defined in lib/keyword.nuc
# rather than reached transitively from the collection import, so it is the first
# bracket literal whose element type a plausible import set does not supply — the
# diagnostic has to name the file, or the reader's expansion looks like a
# compiler bug to whoever wrote `#{:a :b}`.
run_s16_keyword_literal_refused() {
  local d src err want n
  d="$(mktemp -d)"
  n=0
  while IFS='|' read -r name src want; do
    [ -n "$name" ] || continue
    printf '(import-use "stdio.h")\n(import-use strview)\n(import-use hash)\n(import-use keyword)\n(import-use allocator)\n(import-use coll)\n(import-use iterator)\n(import-use hashset)\n(import-use hashmap)\n(import-use vector)\n%s\n' "$src" > "$d/$name.nuc"
    err="$(./build/nucleusc --emit-llvm "$d/$name.nuc" 2>&1 >/dev/null || true)"
    if printf '%s' "$err" | qgrep -F "$want"; then
      echo "PASS  s16-kwlit-refused-$name"
    else
      echo "FAIL  s16-kwlit-refused-$name (wrong or missing diagnostic)"
      printf '%s\n' "$err" | sed 's/^/    got: /'
    fi
  done <<'EOF'
mix-set|(defn main ():i32 (with ((s (ref (HashSet Keyword))) #{:a "b"}) 0) 0)|set literal: mixed element types
mix-vec|(defn main ():i32 (with ((v (ref (Vector Keyword))) [:a 1]) 0) 0)|vector literal: mixed element types
mix-key|(defn main ():i32 (with ((m (ref (HashMap Keyword i32))) {:a 1 "b" 2}) 0) 0)|map literal: mixed key types
mix-val|(defn main ():i32 (with ((m (ref (HashMap Keyword Keyword))) {:a :x :b 2}) 0) 0)|map literal: mixed value types
mix-sym|(defn main ():i32 (with ((s (ref (HashSet (ref Node)))) #{'a "b"}) 0) 0)|set literal: mixed element types
EOF
  # Element kinds that are still refused at a `(HashSet (ref Node))`. These used
  # to share one blanket "must be scalar literals" message; the collection-literal
  # variables item (collection-literal-variables.md) removed that refusal, so each
  # now fails for its own reason — and the reasons are what the shape check always
  # meant. A quoted LIST or INT is `(raw Node)`, not the `(ref Node)` a quoted
  # symbol lowers to, so nullability refuses it; a bare symbol is a variable
  # reference, which is now admitted as an element and so reports the missing
  # variable instead. Losing the blanket message is the feature; losing the
  # refusals would be the bug, which is what these pin.
  while IFS='|' read -r name src want; do
    [ -n "$name" ] || continue
    printf '(import-use "stdio.h")\n(import-use numeric)\n(import-use node)\n(import-use hash)\n(import-use allocator)\n(import-use coll)\n(import-use iterator)\n(import-use hashset)\n(defn main ():i32 (with ((s (ref (HashSet (ref Node)))) %s) 0) 0)\n' "$src" > "$d/$name.nuc"
    err="$(./build/nucleusc --emit-llvm "$d/$name.nuc" 2>&1 >/dev/null || true)"
    if printf '%s' "$err" | qgrep -F "$want"; then
      echo "PASS  s16-symlit-refused-$name"
    else
      echo "FAIL  s16-symlit-refused-$name (a non-symbol datum was admitted)"
      printf '%s\n' "$err" | sed 's/^/    got: /' | head -3
    fi
  done <<'EOF'
qlist|#{'(a b) '(c d)}|raw pointer where non-null (ref ...) is required
qint|#{'1 '2}|raw pointer where non-null (ref ...) is required
bare|#{a b}|undefined: a
call|#{(f x)}|unknown: f
EOF
  # Without (import-use keyword) the expansion names a type the unit cannot see.
  # The note must point at the file, not merely say the type is unknown.
  printf '(import-use "stdio.h")\n(import-use allocator)\n(import-use coll)\n(import-use iterator)\n(import-use hashset)\n(defn main ():i32 (with ((s (ref (HashSet Keyword))) #{:a :b}) 0) 0)\n' > "$d/noimp.nuc"
  err="$(./build/nucleusc --emit-llvm "$d/noimp.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep -F "unknown type: Keyword" \
     && printf '%s' "$err" | qgrep -F "lib/keyword.nuc"; then
    echo "PASS  s16-kwlit-missing-import-names-file"
  else
    echo "FAIL  s16-kwlit-missing-import-names-file"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi
  rm -rf "$d"
}
spawn run_s16_keyword_literal_refused

# Stage 16 — symbols as first-class values (design/stage16-ergonomics/
# container-literal-elements.md §3.2, "make Node respectable as a value").
#
# Two halves. `hash` over `(ref (ref Node))` in lib/hash.nuc makes symbol-keyed
# sets and maps work at all; the behavioural side is examples/symbol-keys-test.nuc.
# What needs its own fixture is the TYPING change, because it is conditional and
# the condition is the thing that can rot: `emit-quote` types a quoted SYMBOL
# `(ref Node)` (it lowers to `intern-symbol`, whose signature returns `ref:Node`)
# but must leave every other datum `(raw Node)` — `'(a b)` builds cells and `'()`
# IS null. A blanket flip would type null as non-null and the flow checker would
# stop catching it, silently.
#
# This is a node-type<->emit-node lockstep pair (conventions.md): the rule lives
# in `quoted-datum-type` and BOTH sites call it. `make bootstrap` is the gate on
# the pair agreeing; these rows are the gate on the rule itself.
run_s16_symbol_values() {
  local d err ir
  d="$(mktemp -d)"

  # `(import-use node)` because a quote is a RUNTIME call since the prelude split
  # (compile-time-imports.md §4b) — without it `lst.nuc` would fail for the wrong
  # reason and the nullability assertion below would pass vacuously.
  printf '(import-use node)(defn main ():i32 (let (l:(ref Node) (quote a)) (return 0)))\n' > "$d/sym.nuc"
  printf '(import-use node)(defn main ():i32 (let (l:(ref Node) (quote (a b))) (return 0)))\n' > "$d/lst.nuc"
  printf '(import-use node)(defn main ():i32 (let (l:(raw Node) (quote a)) (return 0)))\n' > "$d/raw.nuc"

  # A quoted symbol is non-null: it fits a (ref Node) slot with no cast.
  if ./build/nucleusc --emit-llvm "$d/sym.nuc" >/dev/null 2>&1; then
    echo "PASS  s16-quoted-symbol-is-ref"
  else
    echo "FAIL  s16-quoted-symbol-is-ref"
    ./build/nucleusc --emit-llvm "$d/sym.nuc" 2>&1 >/dev/null | sed 's/^/    /' | head -3
  fi

  # ...and it really is the intern-symbol call, not a laundered raw pointer.
  ir="$(./build/nucleusc --emit-llvm "$d/sym.nuc" 2>/dev/null || true)"
  if printf '%s' "$ir" | qgrep -F 'call ptr @intern-symbol'; then
    echo "PASS  s16-quoted-symbol-lowers-to-intern"
  else
    echo "FAIL  s16-quoted-symbol-lowers-to-intern"
  fi

  # A quoted LIST must stay nullable. If this ever passes, the conditional has
  # been flattened and `'()` is being typed non-null.
  err="$(./build/nucleusc --emit-llvm "$d/lst.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep -F 'raw pointer where non-null'; then
    echo "PASS  s16-quoted-list-stays-raw"
  else
    echo "FAIL  s16-quoted-list-stays-raw (a non-symbol datum was typed non-null)"
    printf '%s\n' "$err" | sed 's/^/    got: /' | head -3
  fi

  # Non-null narrows into a nullable slot, so pre-Stage-16 spellings still build.
  if ./build/nucleusc --emit-llvm "$d/raw.nuc" >/dev/null 2>&1; then
    echo "PASS  s16-quoted-symbol-still-fits-raw"
  else
    echo "FAIL  s16-quoted-symbol-still-fits-raw (the change was not backward compatible)"
  fi
  rm -rf "$d"
}
spawn run_s16_symbol_values

# --- Stage 16: the prelude no longer emits the node runtime -------------------
# design/stage16-ergonomics/compile-time-imports.md §4b. `lib/prelude.nuc` had
# `(import-use node)`, so EVERY program — a `defmacro` was never what pulled it
# in — carried alloc-node / make-cell / intern-symbol / the intern table and the
# arena that backs them: sixteen definitions and 4569 bytes of .text for a
# program that reaches none of it, and an unlinkable one for freestanding AVR.
#
# The prelude now holds only forms that emit no IR (the `Node` TYPE, the macros,
# Clone, Result, Maybe) and the runtime is a library like any other. What makes
# that safe to assert here rather than leave to `make bootstrap` is that the two
# halves fail in opposite directions: too little and a quoting program has no
# `@intern-symbol` to call (a LINK error, unlocated), too much and the saving is
# silently gone with every test still green.
run_s16_prelude_split() {
  local d ir err
  d="$(mktemp -d)"

  printf '(import-use "stdio.h")\n(defn main ():i32 (printf "hi\\n") (return 0))\n' > "$d/plain.nuc"
  printf '(import-use "stdio.h")\n(defmacro twice (x) `(_+ ~x ~x))\n(defn main ():i32 (let (a:i32 21) (printf "%%d\\n" (twice a))) (return 0))\n' > "$d/mac.nuc"
  printf '(defn main ():i32 (let (s:(ref Node) (quote a)) (return 0)))\n' > "$d/quote.nuc"
  printf '(import-use node)\n(defn main ():i32 (let (s:(ref Node) (quote a)) (return 0)))\n' > "$d/quote-ok.nuc"
  printf '(defn takes (:rest xs:i64):i32 (return 0))\n(defn main ():i32 (return (takes 1 2)))\n' > "$d/rest.nuc"
  printf '(defn f ((n (raw Node))):i32 (return (n '\''kind)))\n(defn main ():i32 (return 0))\n' > "$d/type.nuc"

  # 1. The measured case: no node/arena definition survives into a program that
  #    never asked for one. Matched on `define`, not on the symbol — a `declare`
  #    would be free, and it is the emitted BODIES that cost the bytes.
  ir="$(./build/nucleusc --emit-llvm "$d/plain.nuc" 2>/dev/null || true)"
  if ! printf '%s\n' "$ir" | qgrep -E '^define .*@(alloc-node|make-cell|intern-symbol|arena-alloc|arena-init)\('; then
    echo "PASS  s16-prelude-emits-no-node-runtime"
  else
    echo "FAIL  s16-prelude-emits-no-node-runtime"
    printf '%s\n' "$ir" | grep -E '^define .*@(alloc-node|make-cell|intern-symbol|arena-)' | sed 's/^/    /' | head -4
  fi

  # 2. The premise the design note had to correct: defining a macro costs
  #    nothing, because a macro body is JIT'd against the COMPILER's copies. The
  #    two programs must emit the same set of definitions, macro or no macro.
  if [ "$(./build/nucleusc --emit-llvm "$d/plain.nuc" 2>/dev/null | grep -cE '^define ')" \
     = "$(./build/nucleusc --emit-llvm "$d/mac.nuc" 2>/dev/null | grep -cE '^define ')" ]; then
    echo "PASS  s16-defmacro-costs-no-runtime"
  else
    echo "FAIL  s16-defmacro-costs-no-runtime"
    diff <(./build/nucleusc --emit-llvm "$d/plain.nuc" 2>/dev/null | grep -E '^define ') \
         <(./build/nucleusc --emit-llvm "$d/mac.nuc" 2>/dev/null | grep -E '^define ') \
      | sed 's/^/    /' | head -6
  fi

  # 3. …and it still RUNS, which is the half a definition count cannot see: the
  #    macro expands, and its expansion is ordinary arithmetic needing no runtime.
  if ./build/nucleusc "$d/mac.nuc" -o "$d/mac.bin" >/dev/null 2>&1 \
     && [ "$("$d/mac.bin")" = "42" ]; then
    echo "PASS  s16-defmacro-still-expands-without-node"
  else
    echo "FAIL  s16-defmacro-still-expands-without-node"
  fi

  # 4. A quote is a runtime call, so it is refused by NAME rather than left to
  #    fail at link time with no location.
  err="$(./build/nucleusc --emit-llvm "$d/quote.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep -F 'quote needs the node runtime — add (import-use node)'; then
    echo "PASS  s16-quote-demands-node-import"
  else
    echo "FAIL  s16-quote-demands-node-import"
    printf '%s\n' "$err" | sed 's/^/    got: /' | head -3
  fi

  # 5. The same program with the import compiles — the diagnostic names a fix
  #    that works, which is the half a rejection test alone never checks.
  if ./build/nucleusc --emit-llvm "$d/quote-ok.nuc" >/dev/null 2>&1; then
    echo "PASS  s16-quote-import-is-the-fix"
  else
    echo "FAIL  s16-quote-import-is-the-fix"
    ./build/nucleusc --emit-llvm "$d/quote-ok.nuc" 2>&1 >/dev/null | sed 's/^/    /' | head -3
  fi

  # 6. The SECOND emission site, and the one that is easy to miss: a `:rest`
  #    call folds its tail into Node cells at the call site, nowhere near
  #    emit-quote-tree. A check on quote alone leaves this a link error.
  err="$(./build/nucleusc --emit-llvm "$d/rest.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep -F 'a :rest call needs the node runtime'; then
    echo "PASS  s16-rest-call-demands-node-import"
  else
    echo "FAIL  s16-rest-call-demands-node-import"
    printf '%s\n' "$err" | sed 's/^/    got: /' | head -3
  fi

  # 7. What the split must NOT take away: `Node` is a type, the prelude still
  #    registers it, and reading a field off one emits no call at all.
  if ./build/nucleusc --emit-llvm "$d/type.nuc" >/dev/null 2>&1; then
    echo "PASS  s16-node-type-survives-without-runtime"
  else
    echo "FAIL  s16-node-type-survives-without-runtime"
    ./build/nucleusc --emit-llvm "$d/type.nuc" 2>&1 >/dev/null | sed 's/^/    /' | head -3
  fi
  rm -rf "$d"
}
spawn run_s16_prelude_split

# --- Stage 16: (import-ct …) — compile-time-only imports ----------------------
# design/stage16-ergonomics/compile-time-imports.md §4a. The split above is only
# half the answer: `lib/error.nuc`'s `with-handler` calls `node-at` to
# destructure its spec, which is a COMPILE-time use — the macro body is JIT'd
# against the compiler process — but nothing let a file ask for a library's
# compile-time surface alone, so every error-handling program paid for the node
# runtime it never calls.
#
# `import-ct` registers types, signatures, constants and macros and discards the
# definitions. Two properties decide whether it is sound, and neither is visible
# in a program that merely compiles:
#   * the promise is kept — a program that reaches a withheld definition is told
#     so, at the use, instead of failing to link with no location;
#   * compile-time-only is a property of the UNIT, not of one import edge, so a
#     library that only wants the compile-time surface can never take the runtime
#     away from a program that imports the same library for real. Both orders.
run_s16_import_ct() {
  local d ir err
  d="$(mktemp -d)"; mkdir -p "$d/l"

  printf '(import-ct node)\n(defn main ():i32 (return 0))\n' > "$d/plain.nuc"
  printf '(import-ct node)\n(defn main ():i32 (let (s:(ref Node) (quote a)) (return 0)))\n' > "$d/quote.nuc"
  printf '(import-ct node)\n(defn main ():i32 (return (node-len null)))\n' > "$d/call.nuc"
  # Both orders of "a library wants it compile-time, the program wants it for real".
  printf '(import-use error)\n(import-use node)\n(defn main ():i32 (let (s:(ref Node) (quote a)) (return 0)))\n' > "$d/ct-first.nuc"
  printf '(import-use node)\n(import-use error)\n(defn main ():i32 (let (s:(ref Node) (quote a)) (return 0)))\n' > "$d/real-first.nuc"

  # 1. The definitions really are gone: one `define`, for `main`.
  ir="$(./build/nucleusc --emit-llvm "$d/plain.nuc" 2>/dev/null || true)"
  if [ "$(printf '%s\n' "$ir" | grep -cE '^define ')" = 1 ]; then
    echo "PASS  s16-import-ct-emits-no-definitions"
  else
    echo "FAIL  s16-import-ct-emits-no-definitions"
    printf '%s\n' "$ir" | grep -E '^define ' | sed 's/^/    /' | head -6
  fi

  # 2. The promise is kept at the two kinds of use: the compiler-synthesized one
  #    (a quote lowers to @intern-symbol) and the ordinary one (a direct call).
  err="$(./build/nucleusc --emit-llvm "$d/quote.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep -F 'quote needs the node runtime'; then
    echo "PASS  s16-import-ct-quote-refused"
  else
    echo "FAIL  s16-import-ct-quote-refused"
    printf '%s\n' "$err" | sed 's/^/    got: /' | head -3
  fi

  err="$(./build/nucleusc --emit-llvm "$d/call.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep -F 'imported compile-time-only'; then
    echo "PASS  s16-import-ct-call-refused"
  else
    echo "FAIL  s16-import-ct-call-refused"
    printf '%s\n' "$err" | sed 's/^/    got: /' | head -3
  fi

  # 3. …and it is a REFUSAL, not a link error: the message names a location in
  #    the user's file, which is the whole reason the check exists.
  if printf '%s' "$err" | qgrep -F "$d/call.nuc:2:"; then
    echo "PASS  s16-import-ct-refusal-is-located"
  else
    echo "FAIL  s16-import-ct-refusal-is-located"
    printf '%s\n' "$err" | sed 's/^/    got: /' | head -2
  fi

  # 4. Order independence. `lib/error.nuc` does `(import-ct node)`, so a program
  #    that uses error handling AND quotes must get the runtime either way round.
  #    Getting this wrong is silent in one order and a refusal in the other.
  for v in ct-first real-first; do
    ir="$(./build/nucleusc --emit-llvm "$d/$v.nuc" 2>/dev/null || true)"
    if printf '%s\n' "$ir" | qgrep -E '^define .*@intern-symbol\('; then
      echo "PASS  s16-import-ct-real-import-wins-$v"
    else
      echo "FAIL  s16-import-ct-real-import-wins-$v (the ct import withheld a runtime the program imported)"
      ./build/nucleusc --emit-llvm "$d/$v.nuc" 2>&1 >/dev/null | sed 's/^/    /' | head -2
    fi
  done

  # 5. The unit-level rule reaches THROUGH a ct-imported library: `ctlib` is
  #    compile-time-only, but the `vector` it pulls in is one the program itself
  #    imports, so vector must stay real — and, because a template stamp belongs
  #    to no file, `(Vector i32)` must still be instantiated into the program.
  #    Measured before the fix: every vector definition came out ct-only and the
  #    program was refused at its own `[1 2 3]`.
  cat > "$d/l/ctlib.nuc" <<'EOF'
(import-use vector)
(defn ctlib-count ((v (ref (Vector i32)))):usize (return (count v)))
EOF
  cat > "$d/nested.nuc" <<'EOF'
(import-use "stdio.h")
(import-ct ctlib)
(import-use vector)
(defn main ():i32
  (with ((v (ref (Vector i32))) [1 2 3])
    (printf "%d\n" (unsafe/cast i32 (count v))))
  (return 0))
EOF
  if ./build/nucleusc -I "$d/l" "$d/nested.nuc" -o "$d/nested.bin" 2>"$d/nested.err" \
     && [ "$("$d/nested.bin")" = "3" ]; then
    echo "PASS  s16-import-ct-nested-real-import-survives"
  else
    echo "FAIL  s16-import-ct-nested-real-import-survives"
    sed 's/^/    /' "$d/nested.err" | head -3
  fi

  # 6. What `import-ct` is FOR: the compile-time surface is really registered, so
  #    a macro body may call the library's functions. `with-handler` (lib/error)
  #    is the in-tree case — it calls `node-at` under `(import-ct node)` — and it
  #    must still expand in a program carrying no node runtime at all.
  cat > "$d/mac.nuc" <<'EOF'
(import-use "stdio.h")
(import-use error)
(deferror EGone "gone")
(defn probe ((e Err) (ctx ptr)):(Maybe i32) (return (some 7)))
(defn risky (x:i32):!i32 (if (< x 0) (return (err EGone)) (return (ok x))))
(defn main ():i32
  (with-handler (EGone i32 probe null)
    (match (risky -1) ((ok v) (printf "%d\n" v)) ((err e) (printf "unrepaired\n"))))
  (return 0))
EOF
  if ./build/nucleusc "$d/mac.nuc" -o "$d/mac.bin" 2>"$d/mac.err" \
     && [ "$("$d/mac.bin")" = "7" ]; then
    ir="$(./build/nucleusc --emit-llvm "$d/mac.nuc" 2>/dev/null || true)"
    if ! printf '%s\n' "$ir" | qgrep -E '^define .*@(alloc-node|make-cell|intern-symbol|arena-alloc)\('; then
      echo "PASS  s16-import-ct-macro-runs-with-no-runtime"
    else
      echo "FAIL  s16-import-ct-macro-runs-with-no-runtime (the runtime came back)"
      printf '%s\n' "$ir" | grep -E '^define .*@(alloc-node|make-cell|intern-symbol|arena-)' | sed 's/^/    /' | head -4
    fi
  else
    echo "FAIL  s16-import-ct-macro-runs-with-no-runtime (with-handler did not expand or run)"
    sed 's/^/    /' "$d/mac.err" | head -3
  fi

  # 7. Arity, so a typo is a diagnostic rather than a silent no-op.
  printf '(import-ct)\n(defn main ():i32 (return 0))\n' > "$d/bad.nuc"
  err="$(./build/nucleusc --emit-llvm "$d/bad.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | qgrep -F 'import-ct: expected (import-ct name)'; then
    echo "PASS  s16-import-ct-arity"
  else
    echo "FAIL  s16-import-ct-arity"
    printf '%s\n' "$err" | sed 's/^/    got: /' | head -2
  fi
  rm -rf "$d"
}
spawn run_s16_import_ct

# Stage 16, compile-time-imports.md §4d: an imported `defn` the program never
# calls is emitted `weak_odr` and `weak_odr` may not be discarded, so nothing
# removed it — and the string table goes into the program module whole,
# including entries only a macro's JIT module used. Both are reclaimed at the
# LINK now: one section per definition plus `-Wl,--gc-sections`.
#
# The section name is not cosmetic. LLVM keys SHT_NOBITS off the NAME, so a
# `.bss` name with a non-zero initializer is a hard error and a zero one under
# `.data` newly costs file bytes — which is why the prefix is pinned per storage
# class here, in both directions.
run_s16_gc_sections() {
  local d ir nogc
  d="$(mktemp -d)"; mkdir -p "$d/lib"
  cat > "$d/lib/gclib.nuc" <<'EOF'
(defn gc-used (x:i32):i32 (return (+ x 1)))
(defn gc-never-called (x:i32):i32 (return (* x 7)))
EOF
  cat > "$d/main.nuc" <<'EOF'
(import-use "stdio.h")
(import-use gclib)
(defvar gc-zero:i32 0)
(defvar gc-nonzero:i32 5)
(defvar :const gc-ro:i32 9)
(defn main ():i32 (printf "%d\n" (gc-used gc-nonzero)) (return gc-zero))
EOF
  ir="$d/main.ll"
  ./build/nucleusc --emit-llvm -I "$d/lib" "$d/main.nuc" > "$ir" 2>/dev/null || true

  # 1. Every storage class lands under the prefix its content requires, and LLVM
  #    accepts the result (llvm-as is what would reject a .bss/non-zero pairing).
  if llvm-as "$ir" -o /dev/null 2>/dev/null \
     && qgrep -F 'define i32 @main() section ".text.main"' "$ir" \
     && qgrep -F 'define weak_odr i32 @gc-used(i32 %x.arg) section ".text.gc-used"' "$ir" \
     && qgrep -F '@gc-zero = global i32 0, section ".bss.gc-zero"' "$ir" \
     && qgrep -F '@gc-nonzero = global i32 5, section ".data.gc-nonzero"' "$ir" \
     && qgrep -F '@gc-ro = constant i32 9, section ".rodata.gc-ro"' "$ir" \
     && qgrep -E '^@\.str\.0 = private unnamed_addr constant .*, section "\.rodata\.\.str\.0"' "$ir"; then
    echo "PASS  s16-sections-per-definition"
  else
    echo "FAIL  s16-sections-per-definition (a definition is missing its section, or LLVM rejected the IR)"
    llvm-as "$ir" -o /dev/null 2>&1 | sed 's/^/    /' | head -3
    grep -nE '^(define|@gc-|@\.str\.0)' "$ir" | head -8 | sed 's/^/    /'
  fi

  # 2. The section spelling is ELF's. A Mach-O specifier is "SEGMENT,section" and
  #    LLVM rejects a bare name outright; COFF collects with /OPT:REF, not
  #    --gc-sections. Neither target may see one.
  if [ "$(./build/nucleusc --target=x86_64-apple-darwin --emit-llvm -I "$d/lib" \
            "$d/main.nuc" 2>/dev/null | grep -c 'section "')" = 0 ] \
     && [ "$(./build/nucleusc --target=x86_64-pc-windows-msvc --emit-llvm -I "$d/lib" \
            "$d/main.nuc" 2>/dev/null | grep -c 'section "')" = 0 ]; then
    echo "PASS  s16-sections-elf-only"
  else
    echo "FAIL  s16-sections-elf-only (a non-ELF target emitted an ELF section name)"
  fi

  # 3. The half that actually reclaims anything. `gc-never-called` is in the
  #    linked object either way (weak_odr, not discardable); only the link drops
  #    it — and `--link-arg=-Wl,--no-gc-sections` must be able to put it back,
  #    since that is the documented escape hatch.
  nogc="$d/main.nogc"
  if ./build/nucleusc -I "$d/lib" "$d/main.nuc" -o "$d/main.bin" 2>/dev/null \
     && ./build/nucleusc -I "$d/lib" --link-arg=-Wl,--no-gc-sections \
          "$d/main.nuc" -o "$nogc" 2>/dev/null \
     && [ "$("$d/main.bin"; echo "rc=$?")" = "$(printf '6\nrc=0')" ] \
     && ! nm "$d/main.bin" 2>/dev/null | qgrep ' gc-never-called$' \
     && nm "$nogc" 2>/dev/null | qgrep ' gc-never-called$'; then
    echo "PASS  s16-gc-sections-drops-unused-import"
  else
    echo "FAIL  s16-gc-sections-drops-unused-import (an uncalled imported defn survived the link, or --no-gc-sections did not restore it)"
    nm "$d/main.bin" 2>/dev/null | grep 'gc-' | sed 's/^/    linked: /' | head -4
  fi
  rm -rf "$d"
}
spawn run_s16_gc_sections

# Stage 16 (design/stage16-ergonomics/keyword-markers.md): the four parameter-
# list / arm-chain markers are keywords. `:repr` had NO coverage at all before
# this unit — it was documented in docs/structs-unions.md and used by nothing.
run_s16_keyword_markers() {
  local d out
  d="$(mktemp -d)"

  # 1. All four markers, plus the two shapes that could have collided with one:
  #    `:where(Ord T)` with no separating space (the reader's colon-paren fuse
  #    keys on a TRAILING colon, so a keyword must not trigger it), and an
  #    `:optional` default that is itself a keyword VALUE one level down.
  #    `Ord3`/`less3` rather than `Ord`/`less`: lib/numeric.nuc defines those and
  #    `import-use keyword` reaches it, so the obvious names are a redefinition.
  cat > "$d/ok.nuc" <<'EOF'
(import-use "stdio.h")
(import-use node)
(import-use keyword)
(defprotocol Ord3 (less3 (a:Self b:Self):bool))
(defn less3 (a:i32 b:i32):bool (return (< a b)))
(extend i32 Ord3)
(defstruct Point x:i32 y:i32)
(defunion Shape (circle p:(ref Point)) none :repr tagged)
(defn sum (:rest args:i64):i64
  (let (total:i64 0)
    (while (!= args null)
      (set! total (+ total (unsafe/cast i64 ((unsafe/cast ptr:Node args) 'car))))
      (set! args ((unsafe/cast ptr:Node args) 'cdr)))
    total))
(defn maxv (a:T b:T :where (Ord3 T)):T (return (if (less3 a b) b a)))
(defn minv (a:T b:T :where(Ord3 T)):T (return (if (less3 b a) b a)))
(defn kw-default (n:i32 :optional (k:Keyword :fallback)):i32 (return n))
(defn greet (n:i32 :optional (m:i32 7)):i32 (return (+ n m)))
(defmacro twice (x :rest r) `(+ ~x ~x))
(defn main ():i32
  (printf "%ld %d %d %d %d %d\n"
    (sum 1 2 3 4) (maxv 3 9) (minv 3 9) (greet 1) (greet 1 2) (twice 5))
  (return (kw-default 0)))
EOF
  ./build/nucleusc "$d/ok.nuc" -o "$d/ok.bin" 2>"$d/ok.err" || true
  out="$("$d/ok.bin" 2>/dev/null || true)"
  if [ "$out" = "10 9 3 8 3 10" ]; then
    echo "PASS  s16-keyword-markers-accepted"
  else
    echo "FAIL  s16-keyword-markers-accepted (got '$out')"
    sed 's/^/    /' "$d/ok.err" | head -3
  fi

  # 2. Every retired `&x` spelling names its replacement, from the definer that
  #    owns it. Without this each one falls through as an ordinary symbol and
  #    surfaces as `missing :type on param '&rest'` or `unknown type: T`.
  legacy_says() {   # legacy_says <file-body> <expected-substring>
    printf '%s\n' "$1" > "$d/leg.nuc"
    ./build/nucleusc --emit-llvm "$d/leg.nuc" >/dev/null 2>"$d/leg.err"
    qgrep -F "$2" "$d/leg.err"
  }
  if legacy_says '(defn f (a:i32 &rest xs:i64):i64 (return 0))' \
        "'&rest' is no longer a marker -- write ':rest'" \
     && legacy_says '(defn f (n:i32 &optional (m:i32 7)):i32 (return n))' \
        "'&optional' is no longer a marker -- write ':optional'" \
     && legacy_says '(defprotocol Ord (less (a:Self b:Self):bool))
(defn maxv (a:T b:T &where (Ord T)):T (return a))' \
        "'&where' is no longer a marker -- write ':where'" \
     && legacy_says '(defprotocol Show (shout (a:Self):i32))
(defstruct (Box T) v:T)
(extend (Box T) Show &where (Show T))' \
        "'&where' is no longer a marker -- write ':where'" \
     && legacy_says '(defstruct Point x:i32)
(defunion Shape (circle p:(ref Point)) none &repr tagged)' \
        "'&repr' is no longer a marker -- write ':repr'" \
     && legacy_says '(defmacro twice (x &rest r) `(+ ~x ~x))' \
        "'&rest' is no longer a marker -- write ':rest'" \
     && legacy_says '(declare printf (fmt:CStr &rest args:i32) :i32)' \
        "'&rest' is no longer a marker -- write ':rest'"; then
    echo "PASS  s16-keyword-markers-legacy-rejected"
  else
    echo "FAIL  s16-keyword-markers-legacy-rejected (a retired &x spelling did not name its replacement)"
    sed 's/^/    /' "$d/leg.err" | head -3
  fi

  # 3. The keyword spelling did not weaken any rule the symbol spelling enforced.
  refuses() {   # refuses <file-body> <expected-substring>
    printf '%s\n' "$1" > "$d/ref.nuc"
    ./build/nucleusc --emit-llvm "$d/ref.nuc" >/dev/null 2>"$d/ref.err"
    qgrep -F "$2" "$d/ref.err"
  }
  if refuses '(defn f (:rest xs:i64 a:i32):i64 (return 0))' \
        'defn: :rest must be second-to-last param' \
     && refuses '(defn f (a:i32 :optional (m:i32 1) :rest xs:i64):i64 (return 0))' \
        'defn: :optional cannot be combined with :rest' \
     && refuses '(declare printf (fmt:CStr :rest args:i32) :i32)' \
        "declare: ':rest' is not supported in a declaration" \
     && refuses '(defprotocol Ord (less (a:Self b:Self):bool))
(defn maxv (a:T b:T :rest xs:i64 :where (Ord T)):T (return a))' \
        'defn: :rest combined with a generic method is not supported yet' \
     && refuses '(defmacro m (x :rest r y) `~x)' \
        'defmacro: :rest must be second-to-last param'; then
    echo "PASS  s16-keyword-markers-rules-preserved"
  else
    echo "FAIL  s16-keyword-markers-rules-preserved (a marker rule stopped firing under the keyword spelling)"
    sed 's/^/    /' "$d/ref.err" | head -3
  fi

  # 4. `.nuch` is a serialization format: print-node must round-trip a marker
  #    keyword with its colon, or a header exports a form its importer cannot
  #    re-read. Assert on the emitted text AND on a real import of it.
  mkdir -p "$d/lib"
  cat > "$d/lib/mklib.nuc" <<'EOF'
(defprotocol Ord2 (less2 (a:Self b:Self):bool))
(defn less2 (a:i32 b:i32):bool (return (< a b)))
(extend i32 Ord2)
(defn mk-max (a:T b:T :where (Ord2 T)):T (return (if (less2 a b) b a)))
(defmacro mk-first (x :rest r) `~x)
EOF
  ./build/nucleusc --emit-nuch "$d/lib/mklib.nuc" > "$d/lib/mklib.nuch" 2>/dev/null
  cat > "$d/use.nuc" <<'EOF'
(import-use "stdio.h")
(import-use mklib)
(defn main ():i32 (printf "%d\n" (mk-max 4 11)) (return 0))
EOF
  if qgrep -F ':where (Ord2 T)' "$d/lib/mklib.nuch" \
     && qgrep -F '(x :rest r)' "$d/lib/mklib.nuch" \
     && ! qgrep -F '&' "$d/lib/mklib.nuch" \
     && [ "$(./build/nucleusc -I "$d/lib" "$d/use.nuc" -o "$d/use.bin" 2>/dev/null \
             && "$d/use.bin")" = "11" ]; then
    echo "PASS  s16-keyword-markers-nuch-roundtrip"
  else
    echo "FAIL  s16-keyword-markers-nuch-roundtrip (a marker did not survive .nuch export/import)"
    sed 's/^/    /' "$d/lib/mklib.nuch" | head -6
  fi
  rm -rf "$d"
}
spawn run_s16_keyword_markers

# --- Stage 16: the `&` type sigil (design/stage16-ergonomics/ref-sigil.md) ----
# `&T` reads as `ref:T`, expanded in the lexer. `examples/ref-sigil.nuc` covers
# the spellings end to end; this unit covers what an example cannot: that the
# sigil is EXACTLY the `ref:` spelling and not a second type, that it never
# escapes into a `.nuch`, and that the atoms it must NOT claim — `&`-prefixed and the
# four retired `&x` markers — still read the way they did.
run_s16_ref_sigil() {
  local d out
  d="$(mktemp -d)"

  # 1. Sugar, not a second type: both spellings emit byte-identical IR. Written
  #    to the SAME path both times so nothing path-derived can differ.
  cat > "$d/id.nuc" <<'EOF'
(import-use node)
(import-use vector)
(defstruct Pt x:i32 y:i32)
(defn s1 (p:&Pt):i32 (return (+ (p 'x) (p 'y))))
(defn id1 (p:&Pt):&Pt (return p))
(defn dd (pp:&&Pt):i32 (return (s1 (deref pp))))
(defn tot (v:&(Vector &Pt)):i32
  (let (s:i32 0) (dotimes (i (count v)) (set! s (+ s (s1 (v i))))) (return s)))
EOF
  ./build/nucleusc --emit-llvm "$d/id.nuc" > "$d/sigil.ll" 2>"$d/id.err" || true
  sed 's/&/ref:/g' "$d/id.nuc" > "$d/plain.nuc" && mv "$d/plain.nuc" "$d/id.nuc"
  ./build/nucleusc --emit-llvm "$d/id.nuc" > "$d/plain.ll" 2>>"$d/id.err" || true
  if [ -s "$d/sigil.ll" ] && diff -q "$d/sigil.ll" "$d/plain.ll" >/dev/null; then
    echo "PASS  s16-ref-sigil-ir-identical"
  else
    echo "FAIL  s16-ref-sigil-ir-identical (&T did not lower exactly like ref:T)"
    sed 's/^/    /' "$d/id.err" | head -3
  fi

  # 2. The sigil is only a *leading* `&`, so a mid-token `&` (as in `a&b`, and in
  #    the compiler) keeps its name, and the two spellings compose in one file.
  cat > "$d/amp.nuc" <<'EOF'
(import-use "stdio.h")
(defstruct Pt x:i32 y:i32)
(defn bump (p:&Pt):i32
  (let (xp:&i32 (addr-of p 'x))
    (set! (deref xp) (+ (deref xp) 1))
    (return (p 'x))))
(defn main ():i32
  (let (a:Pt (Pt 1 2) ap:&Pt (addr-of a))
    (printf "%d\n" (bump ap))
    (return 0)))
EOF
  ./build/nucleusc "$d/amp.nuc" -o "$d/amp.bin" 2>"$d/amp.err" || true
  out="$("$d/amp.bin" 2>/dev/null || true)"
  if [ "$out" = "2" ]; then
    echo "PASS  s16-ref-sigil-field-address-unclaimed"
  else
    echo "FAIL  s16-ref-sigil-field-address-unclaimed (got '$out')"
    sed 's/^/    /' "$d/amp.err" | head -3
  fi

  # 3. `&T` IS `(ref T)`, so it carries `ref`'s non-null obligation, and the
  #    whitespace near-miss is the same reader error `name: (T)` gets.
  sig_refuses() {   # sig_refuses <file-body> <expected-substring>
    printf '%s\n' "$1" > "$d/rej.nuc"
    ./build/nucleusc --emit-llvm "$d/rej.nuc" >/dev/null 2>"$d/rej.err"
    qgrep -F "$2" "$d/rej.err"
  }
  if sig_refuses '(defstruct Pt x:i32)
(defvar p:&Pt null)' \
        'defvar: raw pointer where non-null (ref ...) is required' \
     && sig_refuses '(defstruct Pt x:i32)
(defn f (p:&Pt):i32 (return 0))
(defn g (q:raw:Pt):i32 (return (f q)))' \
        'argument: raw pointer where non-null (ref ...) is required' \
     && sig_refuses '(defstruct Pt x:i32)
(defn f (p:& Pt):i32 (return 0))' \
        "binding name ends in ':'"; then
    echo "PASS  s16-ref-sigil-rules-preserved"
  else
    echo "FAIL  s16-ref-sigil-rules-preserved (a ref rule stopped firing under the & spelling)"
    sed 's/^/    /' "$d/rej.err" | head -3
  fi

  # 4. A `.nuch` is a serialization format, and the sigil is a *reader* rule —
  #    so a header must carry the canonical `(ref T)` / `:ref:T` spelling and
  #    no `&` at all, or an importer re-reads a form the exporter never meant.
  mkdir -p "$d/lib"
  cat > "$d/lib/siglib.nuc" <<'EOF'
(defstruct Pt x:i32 y:i32)
(defn pt-sum (p:&Pt):i32 (return (+ (p 'x) (p 'y))))
(defn pt-id (p:&Pt):&Pt (return p))
EOF
  ./build/nucleusc --emit-nuch "$d/lib/siglib.nuc" > "$d/lib/siglib.nuch" 2>/dev/null
  cat > "$d/siguse.nuc" <<'EOF'
(import-use "stdio.h")
(import-use siglib)
(defn main ():i32
  (let (a:Pt (Pt 4 5) ap:&Pt (addr-of a))
    (printf "%d\n" (pt-sum (pt-id ap)))
    (return 0)))
EOF
  if qgrep -F '((p (ref Pt)))' "$d/lib/siglib.nuch" \
     && qgrep -F ':ref:Pt' "$d/lib/siglib.nuch" \
     && ! qgrep -F '&' "$d/lib/siglib.nuch" \
     && [ "$(./build/nucleusc -I "$d/lib" "$d/siguse.nuc" -o "$d/siguse.bin" 2>/dev/null \
             && "$d/siguse.bin")" = "9" ]; then
    echo "PASS  s16-ref-sigil-nuch-roundtrip"
  else
    echo "FAIL  s16-ref-sigil-nuch-roundtrip (& leaked into a header, or the import broke)"
    sed 's/^/    /' "$d/lib/siglib.nuch" | head -6
  fi

  # 5. A `&` that starts a token is the address-of reader macro, and it is sugar
  #    in the same strict sense: identical IR to the `(addr-of x)` it stands for.
  #    Same path both times, as in 1.
  cat > "$d/ao.nuc" <<'EOF'
(defstruct Pt x:i32 y:i32)
(defn s1 (p:&Pt):i32 (return (+ (p 'x) (p 'y))))
(defn go ():i32 (let (a:Pt (Pt 1 2)) (return (s1 &a))))
EOF
  ./build/nucleusc --emit-llvm "$d/ao.nuc" > "$d/amp-op.ll" 2>"$d/ao.err" || true
  cat > "$d/ao.nuc" <<'EOF'
(defstruct Pt x:i32 y:i32)
(defn s1 (p:&Pt):i32 (return (+ (p 'x) (p 'y))))
(defn go ():i32 (let (a:Pt (Pt 1 2)) (return (s1 (addr-of a)))))
EOF
  ./build/nucleusc --emit-llvm "$d/ao.nuc" > "$d/named.ll" 2>>"$d/ao.err" || true
  if [ -s "$d/amp-op.ll" ] && diff -q "$d/amp-op.ll" "$d/named.ll" >/dev/null; then
    echo "PASS  s16-ref-sigil-addr-of-ir-identical"
  else
    echo "FAIL  s16-ref-sigil-addr-of-ir-identical (&x did not lower exactly like (addr-of x))"
    sed 's/^/    /' "$d/ao.err" | head -3
  fi

  # 6. The two meanings are split by token position, not by context, so they have
  #    to compose: `(as &Pt &p)` is a type and an operator in one form, and a
  #    standalone `&T` in a type slot — which the reader wrote as `(addr-of T)`
  #    before position was known — must still read as `(ref T)`.
  cat > "$d/both.nuc" <<'EOF'
(import-use "stdio.h")
(defstruct Pt x:i32 y:i32)
(defstruct Holder (link &Pt) (tag i32))
(defn hx (h:&Holder):i32 (return ((h 'link) 'x)))
(defn main ():i32
  (let (a:Pt (Pt 3 4) ap:&Pt &a)
    (printf "%d %d %d\n" ((as &Pt &a) 'x) (unsafe/cast i32 (sizeof &Pt)) ((deref &ap) 'y))
    (return 0)))
EOF
  ./build/nucleusc "$d/both.nuc" -o "$d/both.bin" 2>"$d/both.err" || true
  out="$("$d/both.bin" 2>/dev/null || true)"
  if [ "$out" = "3 8 4" ]; then
    echo "PASS  s16-ref-sigil-both-meanings"
  else
    echo "FAIL  s16-ref-sigil-both-meanings (got '$out')"
    sed 's/^/    /' "$d/both.err" | head -3
  fi
  rm -rf "$d"
}
spawn run_s16_ref_sigil

# name-resolution.md §15: `ptr` was caught by the one-symbol-one-kind rule only
# because it doubles as a standalone type; `ref` and `raw` are constructors that
# no type registry holds, so nothing guarded them. They ride BK-PRIMITIVE now,
# with their own noun. The teeth are the two things that must NOT change: the
# kinds still parse as types, and `ref` stays UNRESOLVABLE as a type name, which
# is what keeps collect-pattern-tyvars' targeted diagnostic firing rather than
# silently taking `ref` for a type argument.
run_s16_pointer_kind_names() {
  local d ok
  d="$(mktemp -d)"
  ok=1
  for n in ref raw ptr; do
    for def in "(defvar $n:i32 5)" "(defn $n ():i32 (return 5))" \
               "(defstruct $n x:i32)" "(defconst $n 5)"; do
      printf '%s\n' "$def" > "$d/k.nuc"
      ./build/nucleusc "$d/k.nuc" -o "$d/k.bin" >/dev/null 2>"$d/k.err" || true
      qgrep -F "a symbol may name only one kind of thing" "$d/k.err" || ok=0
    done
  done
  # The noun is per-name, not per-row: `ref`/`raw` are not types.
  printf '(defvar ref:i32 5)\n' > "$d/k.nuc"
  ./build/nucleusc "$d/k.nuc" -o "$d/k.bin" >/dev/null 2>"$d/k.err" || true
  qgrep -F "'ref' already names a pointer kind" "$d/k.err" || ok=0
  # Unchanged: the kinds are still type syntax…
  cat > "$d/ty.nuc" <<'EOF'
(defstruct Pt x:i32)
(defn f (a:ref:Pt b:raw:Pt c:ptr:Pt):i32 (return (a 'x)))
(defn g (v:(ref Pt) w:(raw Pt)):i32 (return (v 'x)))
EOF
  ./build/nucleusc --emit-llvm "$d/ty.nuc" >/dev/null 2>"$d/ty.err" || ok=0
  # …and `ref` is still not a resolvable type NAME, so a bare one in a template
  # argument is still reported instead of collected as a tyvar.
  cat > "$d/tv.nuc" <<'EOF'
(import-use node)
(import-use vector)
(defn h (v:(Vector ref)):i32 (return 0))
EOF
  ./build/nucleusc --emit-llvm "$d/tv.nuc" >/dev/null 2>"$d/tv.err" || true
  qgrep -F "'ref' is a pointer kind, not a type argument" "$d/tv.err" || ok=0
  if [ "$ok" = 1 ]; then
    echo "PASS  s16-pointer-kind-names-reserved"
  else
    echo "FAIL  s16-pointer-kind-names-reserved"
    sed 's/^/    /' "$d/k.err" "$d/ty.err" "$d/tv.err" 2>/dev/null | head -6
  fi
  rm -rf "$d"
}
spawn run_s16_pointer_kind_names

# dot-forms.md §5 step 3: the selector rule, after the flip. A quoted `'x` is
# the field; a BARE symbol is an ordinary variable reference like anywhere else,
# which is what lets a field name live in a variable with no annotation. The two
# are no longer spellings of one thing, so this pins the difference rather than
# the old identity -- and pins it at every member form, because `.set!`/`addr-of`
# need a LITERAL selector and must say which spelling is missing.
run_s16_selector_rule() {
  local d ok out
  d="$(mktemp -d)"
  ok=1
  # 1. A quoted selector is the field, at every form; a computed one needs no
  #    annotation to be read as a value.
  cat > "$d/sel.nuc" <<'EOF'
(import-use "stdio.h")
(import-use node)
(defstruct Pt x:i32 y:i32)
(defn main ():i32
  (let (p:ptr:Pt (alloca Pt))
    (set! (p 'x) 1)
    (set! (deref (addr-of p 'y)) 2)
    (let (sel:ptr (quote y))
      (printf "%d %d %d %d
" (_get p 'x) (get p 'y) (p 'x) (p sel))))
  (return 0))
EOF
  ./build/nucleusc "$d/sel.nuc" -o "$d/sel.bin" 2>"$d/sel.err" || ok=0
  out="$("$d/sel.bin" 2>/dev/null || true)"
  [ "$out" = "1 2 1 2" ] || ok=0
  if [ "$ok" = 1 ]; then
    echo "PASS  s16-selector-quoted-is-the-field"
  else
    echo "FAIL  s16-selector-quoted-is-the-field (got '$out')"
    sed 's/^/    /' "$d/sel.err" | head -3
  fi
  # 2. A bare symbol is the variable. Unbound, it is refused -- and because the
  #    overwhelmingly likely cause is a missed quote on a real field, the message
  #    names the receiver and the spelling rather than saying "undefined".
  ok=1
  printf '(defstruct Pt x:i32 y:i32)
(defn f (p:&Pt):i32 (return (p x)))
' > "$d/bare.nuc"
  ./build/nucleusc --emit-llvm "$d/bare.nuc" >/dev/null 2>"$d/bare.err" || true
  qgrep -F "write (p 'x)" "$d/bare.err" || ok=0
  # 3. The three fixed-position forms need a literal, and a bare symbol is not
  #    one -- "must be symbol" would describe a bare symbol as failing a test it
  #    appears to pass.
  for form in "(set! (p x) 1)" "(let (q:ptr:i32 (addr-of p x)) 0)" "(let (v:i32 (_get p x)) 0)"; do
    printf '(defstruct Pt x:i32)
(defn f (p:&Pt):i32 %s (return 0))
' "$form" > "$d/lit.nuc"
    ./build/nucleusc --emit-llvm "$d/lit.nuc" >/dev/null 2>"$d/lit.err" || true
    qgrep -F "field name must be a quoted selector -- write 'x" "$d/lit.err" || ok=0
  done
  # 4. A selector that is neither spelling is still refused.
  printf '(defstruct Pt x:i32)
(defn f (p:&Pt):i32 (set! (p 3) 9) (return 0))
' > "$d/bad.nuc"
  ./build/nucleusc --emit-llvm "$d/bad.nuc" >/dev/null 2>"$d/bad.err" || true
  qgrep -F "field name must be a quoted selector" "$d/bad.err" || ok=0
  if [ "$ok" = 1 ]; then
    echo "PASS  s16-selector-bare-is-a-variable"
  else
    echo "FAIL  s16-selector-bare-is-a-variable"
    sed 's/^/    /' "$d/bare.err" "$d/lit.err" "$d/bad.err" 2>/dev/null | head -6
  fi
  rm -rf "$d"
}
spawn run_s16_selector_rule

# dot-forms.md §5 step 4: `.` and `.&` are gone. `.` was `_get` verbatim, so its
# sites become `get` (or `_get` where a user override must be bypassed); `.&`
# becomes an ARITY OVERLOAD on `addr-of` -- 1-arg is a binding's address, 2-arg
# is a field's, and the two cannot collide because a binding address takes a
# bare symbol. Both retired spellings stay RESERVED so the answer is exact
# rather than "undefined function".
run_s16_dot_forms_retired() {
  local d ok out
  d="$(mktemp -d)"
  ok=1
  # 1. The 2-arg addr-of covers every shape `.&` did: a plain field, a nested
  #    one, an array field (which DECAYS to ptr:elem -- a pointer-to-array is
  #    useless), a union member, and a by-value struct receiver.
  cat > "$d/ao.nuc" <<'EOF'
(import-use "stdio.h")
(defstruct Inner a:i32)
(defstruct Outer p:Inner cells:(array i32 3) n:i32)
(defstruct Holder u:(union as-int:i64 as-f:f64))
(defn by-val (o:Outer):i32 (return (deref (addr-of (addr-of o) 'n))))
(defn main ():i32
  (let (o:ptr:Outer (alloca Outer)
        h:ptr:Holder (alloca Holder))
    (set! (deref (addr-of o 'n)) 5)
    (set! (deref (addr-of (addr-of o 'p) 'a)) 6)
    (set! (aref (addr-of o 'cells) 1) 7)
    (set! (deref (addr-of (addr-of h 'u) 'as-int)) 8)
    ; the array field's address is ptr:i32, so it binds to one
    (let (c:ptr:i32 (addr-of o 'cells)
          n:i32 5 q:ptr:i32 (addr-of n))
      (printf "%d %d %d %lld %d %d %d\n"
              (deref (addr-of o 'n)) (deref (addr-of (addr-of o 'p) 'a))
              (aref c 1) (deref (addr-of (addr-of h 'u) 'as-int))
              (by-val (deref o)) (deref q) (aref (addr-of o 'cells) 1))))
  (return 0))
EOF
  ./build/nucleusc "$d/ao.nuc" -o "$d/ao.bin" 2>"$d/ao.err" || ok=0
  out="$("$d/ao.bin" 2>/dev/null || true)"
  [ "$out" = "5 6 7 8 5 5 7" ] || ok=0
  if [ "$ok" = 1 ]; then
    echo "PASS  s16-addr-of-2arg"
  else
    echo "FAIL  s16-addr-of-2arg (got '$out')"
    sed 's/^/    /' "$d/ao.err" | head -3
  fi
  # 2. node-type must split on the same arity the emitter does. Without the
  #    mirror the 2-arg form types as the BINDING's address (ptr:ptr:Outer),
  #    which only shows up where the type is load-bearing -- an argument
  #    position and an annotated binding, not in the value itself.
  ok=1
  cat > "$d/ty.nuc" <<'EOF'
(import-use "stdio.h")
(defstruct Pt x:i32 y:i32)
(defn takes (q:ptr:i32):i32 (return (deref q)))
(defn main ():i32
  (let (p:ptr:Pt (alloca Pt))
    (set! (p 'x) 3)
    (let (q:ptr:i32 (addr-of p 'x))
      (printf "%d %d\n" (takes (addr-of p 'x)) (deref q))))
  (return 0))
EOF
  ./build/nucleusc "$d/ty.nuc" -o "$d/ty.bin" 2>"$d/ty.err" || ok=0
  out="$("$d/ty.bin" 2>/dev/null || true)"
  [ "$out" = "3 3" ] || ok=0
  if [ "$ok" = 1 ]; then
    echo "PASS  s16-addr-of-2arg-node-type"
  else
    echo "FAIL  s16-addr-of-2arg-node-type (got '$out')"
    sed 's/^/    /' "$d/ty.err" | head -3
  fi
  # 3. Both retired spellings answer with the replacement, not "undefined".
  ok=1
  printf '(defstruct Pt x:i32)\n(defn f (p:&Pt):i32 (return (. p (quote x))))\n' > "$d/dot.nuc"
  ./build/nucleusc --emit-llvm "$d/dot.nuc" >/dev/null 2>"$d/dot.err" || true
  qgrep -F "'.' was retired in Stage 16: use 'get'" "$d/dot.err" || ok=0
  printf '(defstruct Pt x:i32)\n(defn f (p:&Pt):ptr:i32 (return (.& p (quote x))))\n' > "$d/amp.nuc"
  ./build/nucleusc --emit-llvm "$d/amp.nuc" >/dev/null 2>"$d/amp.err" || true
  qgrep -F "'.&' was retired in Stage 16: use the 2-argument 'addr-of'" "$d/amp.err" || ok=0
  # Reserved, so a user definition cannot shadow the spelling and silence it.
  printf '(defn . (a:i32):i32 (return a))\n' > "$d/shadow.nuc"
  ./build/nucleusc --emit-llvm "$d/shadow.nuc" >/dev/null 2>"$d/shadow.err" || true
  qgrep -F "already names a special form" "$d/shadow.err" || ok=0
  # 4. addr-of's own diagnostics name the form the user wrote, not `.&`.
  printf '(defstruct Pt x:i32)\n(defn f (p:&Pt):ptr:i32 (return (addr-of p (quote z))))\n' > "$d/nf.nuc"
  ./build/nucleusc --emit-llvm "$d/nf.nuc" >/dev/null 2>"$d/nf.err" || true
  qgrep -F "addr-of: no field 'z' on struct 'Pt'" "$d/nf.err" || ok=0
  printf '(defstruct Pt x:i32)\n(defn f (p:&Pt):ptr:i32 (return (addr-of p (quote x) 1)))\n' > "$d/ar.nuc"
  ./build/nucleusc --emit-llvm "$d/ar.nuc" >/dev/null 2>"$d/ar.err" || true
  qgrep -F "addr-of expects 1 or 2 args" "$d/ar.err" || ok=0
  if [ "$ok" = 1 ]; then
    echo "PASS  s16-dot-forms-retired"
  else
    echo "FAIL  s16-dot-forms-retired"
    sed 's/^/    /' "$d/dot.err" "$d/amp.err" "$d/shadow.err" "$d/nf.err" "$d/ar.err" 2>/dev/null | head -8
  fi
  rm -rf "$d"
}
spawn run_s16_dot_forms_retired

# `set!` takes a PLACE (dot-forms.md §5 step 5). Every place delegates to the
# writer it replaced, so the spellings must emit identical IR -- and the three
# writers are retired, reserved, and answer with the replacement.
run_s16_set_places() {
  local d ok out
  d="$(mktemp -d)"
  ok=1
  # 1. Every place, including a nested member and an array-field element.
  cat > "$d/pl.nuc" <<'EOF'
(import-use "stdio.h")
(defstruct Inner a:i32)
(defstruct Pt x:i32 y:i32 in:Inner cells:(array i32 3))
(defn main ():i32
  (let (p:ptr:Pt (alloca Pt)
        buf:ptr:i32 (alloca i32 4)
        n:i32 0)
    (set! n 7)
    (set! (p 'x) 1)
    (set! (get p 'y) 2)
    (set! (_get p 'y) 3)
    (set! ((addr-of p 'in) 'a) 4)
    (set! (deref (addr-of p 'x)) 5)
    (set! (aref buf 2) 6)
    (set! (aref (addr-of p 'cells) 1) 9)
    (printf "%d %d %d %d %d %d\n"
            n (p 'x) (p 'y) ((addr-of p 'in) 'a) (aref buf 2)
            (aref (addr-of p 'cells) 1)))
  (return 0))
EOF
  ./build/nucleusc "$d/pl.nuc" -o "$d/pl.bin" 2>"$d/pl.err" || ok=0
  out="$("$d/pl.bin" 2>/dev/null || true)"
  [ "$out" = "7 5 3 4 6 9" ] || ok=0
  if [ "$ok" = 1 ]; then
    echo "PASS  s16-set-places"
  else
    echo "FAIL  s16-set-places (got '$out')"
    sed 's/^/    /' "$d/pl.err" | head -3
  fi
  # 2. The three retired writers answer with the replacement, not "undefined",
  #    and stay reserved so a user definition cannot silence the message.
  ok=1
  printf '(defstruct Pt x:i32)\n(defn f (p:&Pt):i32 (.set! p (quote x) 1) (return 0))\n' > "$d/fs.nuc"
  ./build/nucleusc --emit-llvm "$d/fs.nuc" >/dev/null 2>"$d/fs.err" || true
  qgrep -F "'.set!' was retired in Stage 16: set! takes a place" "$d/fs.err" || ok=0
  printf '(defn f (p:ptr:i32):i32 (ptr-set! p 1) (return 0))\n' > "$d/ps.nuc"
  ./build/nucleusc --emit-llvm "$d/ps.nuc" >/dev/null 2>"$d/ps.err" || true
  qgrep -F "'ptr-set!' was retired in Stage 16: set! takes a place" "$d/ps.err" || ok=0
  printf '(defn f (a:ptr:i32):i32 (aset! a 0 1) (return 0))\n' > "$d/as.nuc"
  ./build/nucleusc --emit-llvm "$d/as.nuc" >/dev/null 2>"$d/as.err" || true
  qgrep -F "'aset!' was retired in Stage 16: set! takes a place" "$d/as.err" || ok=0
  printf '(defn aset! (a:i32):i32 (return a))\n' > "$d/sh.nuc"
  ./build/nucleusc --emit-llvm "$d/sh.nuc" >/dev/null 2>"$d/sh.err" || true
  qgrep -F "already names a special form" "$d/sh.err" || ok=0
  # 3. A place that is not assignable is refused by name, and the diagnostics of
  #    the delegated writers say `set!` -- the only spelling left.
  printf '(defn f ():i32 (set! (+ 1 2) 3) (return 0))\n' > "$d/np.nuc"
  ./build/nucleusc --emit-llvm "$d/np.nuc" >/dev/null 2>"$d/np.err" || true
  qgrep -F "set!: not an assignable place" "$d/np.err" || ok=0
  # `()` reads as a null node; the place judgement has to precede any deref.
  printf '(defn f ():i32 (set! () 3) (return 0))\n' > "$d/nil.nuc"
  ./build/nucleusc --emit-llvm "$d/nil.nuc" >/dev/null 2>"$d/nil.err" || true
  qgrep -F "set!: not an assignable place" "$d/nil.err" || ok=0
  printf '(defstruct Pt x:i32)\n(defn f (p:&Pt):i32 (set! (p (quote zzz)) 1) (return 0))\n' > "$d/nf2.nuc"
  ./build/nucleusc --emit-llvm "$d/nf2.nuc" >/dev/null 2>"$d/nf2.err" || true
  qgrep -F "set!: no field 'zzz' on struct 'Pt'" "$d/nf2.err" || ok=0
  if [ "$ok" = 1 ]; then
    echo "PASS  s16-set-writers-retired"
  else
    echo "FAIL  s16-set-writers-retired"
    sed 's/^/    /' "$d/fs.err" "$d/ps.err" "$d/as.err" "$d/sh.err" "$d/np.err" "$d/nil.err" "$d/nf2.err" 2>/dev/null | head -10
  fi
  # 4. A closure body's member place: the receiver sits in head position, which
  #    fn-capture-walk used to skip -- `.set!` walked its receiver explicitly.
  ok=1
  cat > "$d/cap.nuc" <<'EOF'
(import-use "stdio.h")
(defn main ():i32
  (let (total:i32 0)
    (let (f (vfn (d:i32):i32 (set! total (+ total d)) (return total)))
      (printf "%d\n" (+ (invoke f 2) (invoke f 3)))))
  (return 0))
EOF
  ./build/nucleusc "$d/cap.nuc" -o "$d/cap.bin" 2>"$d/cap.err" || ok=0
  out="$("$d/cap.bin" 2>/dev/null || true)"
  [ "$out" = "7" ] || ok=0
  if [ "$ok" = 1 ]; then
    echo "PASS  s16-set-place-in-closure"
  else
    echo "FAIL  s16-set-place-in-closure (got '$out')"
    sed 's/^/    /' "$d/cap.err" | head -3
  fi
  rm -rf "$d"
}
spawn run_s16_set_places

# The `set` generic (dot-forms.md §3 "Extensibility", §5 step 6): a member place
# whose key is COMPUTED dispatches to a user `set` method on (recv, key, value),
# reusing the multimethod machinery rather than a second extension protocol.
run_s16_set_generic() {
  local d ok out
  d="$(mktemp -d)"
  ok=1
  # 1. Vector and HashMap are writable through the place form, in both spellings.
  cat > "$d/w.nuc" <<'EOF'
(import-use "stdio.h")
(import-use vector)
(import-use hashmap)
(defn main ():i32
  (with ((v (ref (Vector i32))) (alloca (Vector i32)))
    (vector-init v) (conj v 10) (conj v 20) (conj v 30)
    (let (i:usize (as usize 1))
      (set! (v i) 99)
      (printf "%d %d %d\n" (v (as usize 0)) (v i) (v (as usize 2)))))
  (with ((m (ref (HashMap CStr i32))) (alloca (HashMap CStr i32)))
    (hashmap-init m)
    (let (k:CStr "a")
      (set! (m k) 1)
      (set! (get m k) 7)
      (match (get m k) ((some x) (printf "%d %lld\n" x (count m)))
                       (none (printf "none\n")))))
  (return 0))
EOF
  ./build/nucleusc "$d/w.nuc" -o "$d/w.bin" 2>"$d/w.err" || ok=0
  out="$("$d/w.bin" 2>/dev/null || true)"
  [ "$out" = "10 99 30
7 1" ] || ok=0
  if [ "$ok" = 1 ]; then
    echo "PASS  s16-set-generic-collections"
  else
    echo "FAIL  s16-set-generic-collections (got '$out')"
    sed 's/^/    /' "$d/w.err" | head -3
  fi
  # 2. A LITERAL selector is always the field, even on a receiver that has a `set`
  #    method -- otherwise a collection could no longer write its own fields, the
  #    write side of the `_get` recursion trap. And the method's return type is
  #    the place's type, which is the node-type mirror.
  ok=1
  cat > "$d/lit.nuc" <<'EOF'
(import-use "stdio.h")
(defstruct Box n:i32 hits:i32)
(defn set ((self (ref Box)) (k i32) (x i32)):i32
  (set! (self 'hits) (+ (_get self 'hits) 1))   ; literal selector: a field write
  (set! (self 'n) (+ (_get self 'n) x))
  (return (_get self 'n)))
(defn main ():i32
  (let (b:ptr:Box (alloca Box) k:i32 0)
    (set! (b 'n) 1) (set! (b 'hits) 0)
    (let (r:i32 (set! (b k) 10))                ; computed key: the set generic
      (printf "%d %d %d\n" r (_get b 'n) (_get b 'hits))))
  (return 0))
EOF
  ./build/nucleusc "$d/lit.nuc" -o "$d/lit.bin" 2>"$d/lit.err" || ok=0
  out="$("$d/lit.bin" 2>/dev/null || true)"
  [ "$out" = "11 11 1" ] || ok=0
  if [ "$ok" = 1 ]; then
    echo "PASS  s16-set-generic-literal-is-the-field"
  else
    echo "FAIL  s16-set-generic-literal-is-the-field (got '$out')"
    sed 's/^/    /' "$d/lit.err" | head -3
  fi
  # 3. A computed key on a READABLE collection with no `set` method says so; the
  #    field path would answer with a missing-quote note about a non-field.
  ok=1
  cat > "$d/no.nuc" <<'EOF'
(defstruct Ro n:i32)
(defn invoke ((self (ref Ro)) i:i32):i32 (return (+ (_get self 'n) i)))
(defn main ():i32
  (let (r:ref:Ro (alloca Ro) k:i32 0)
    (set! (r k) 5))
  (return 0))
EOF
  ./build/nucleusc --emit-llvm "$d/no.nuc" >/dev/null 2>"$d/no.err" || true
  qgrep -F "has no \`set\` method" "$d/no.err" || ok=0
  if [ "$ok" = 1 ]; then
    echo "PASS  s16-set-generic-missing-method"
  else
    echo "FAIL  s16-set-generic-missing-method"
    sed 's/^/    /' "$d/no.err" | head -3
  fi
  rm -rf "$d"
}
spawn run_s16_set_generic

# `tyname-resolvable` (src/generics.nuc) decides whether a symbol in a stamped
# method's type pattern names a CONCRETE type or a free type variable. Read as a
# tyvar, a concrete arg makes the stamp look like an unmonomorphized template,
# so emit-defn skips its define while the call site still names its ir-name --
# an undefined symbol that only LLVM's parser catches. It had drifted from
# parse-type-name three times (__fnty_N, ptr:X, and `Char`), so this pins the
# whole builtin set rather than the one name that was missing.
run_builtin_tyname_resolvable() {
  local d ok=1 T V
  d="$(mktemp -d)"
  for T in Char usize ssize i32 ui8 f64 bool ptr CStr Err raw; do
    case "$T" in
      Char) V='\a' ;;
      bool) V='true' ;;
      ptr|CStr|raw) V='null' ;;
      f64)  V='1.0' ;;
      Err)  V='' ;;
      *)    V='1' ;;
    esac
    # `raw` is a pointer KIND, not spellable as a bare element type; the point
    # of listing it is that tyname-resolvable must still answer for it.
    [ "$T" = "raw" ] && continue
    cat > "$d/t.nuc" <<EOF
(import-use vector)
(defn main ():i32
  (with ((v (ref (Vector $T))) (alloca (Vector $T)))
    (vector-init v))
  (return 0))
EOF
    if ! ./build/nucleusc --emit-llvm "$d/t.nuc" > "$d/t.ll" 2>"$d/t.err"; then
      echo "    (Vector $T): compile failed: $(head -1 "$d/t.err")"
      ok=0
      continue
    fi
    # The failure is a CALL with no define and no declare -- LLVM's own parser is
    # the only thing that catches it, so check for it directly.
    local rx='@[A-Za-z0-9_.$-]+'
    local missing
    missing="$(comm -23 \
      <(grep -oE "call [^@]*$rx" "$d/t.ll" | grep -oE "$rx" | sort -u) \
      <(cat <(grep -oE "^define [^@]*$rx" "$d/t.ll") <(grep -oE "^declare [^@]*$rx" "$d/t.ll") \
        | grep -oE "$rx" | sort -u) | tr '\n' ' ')"
    if [ -n "$missing" ]; then
      echo "    (Vector $T): undefined after stamping: $missing"
      ok=0
    fi
  done
  if [ "$ok" = 1 ]; then
    echo "PASS  builtin-tyname-resolvable"
  else
    echo "FAIL  builtin-tyname-resolvable"
  fi
  rm -rf "$d"
}
spawn run_builtin_tyname_resolvable

# keyword-markers.md §7, follow-up 1: the two signature-registration sites
# inferred `has-rest` from `(< (defn-params-count …) (node-len …))`, which is
# equally true of an `:optional` list — so every `:optional` defn registered
# has-rest = 1. `finalize-generics` binds that Type for a SOLITARY name, so a
# call above the definition took the `:rest` path; and the widening dispatch
# tiers gate on `(= (m has-rest) 0)`, so an overloaded one never resolved.
# The two sites are the signature prescan (src/nucleusc.nuc) and the `.nuch`
# `defmethod` importer (src/nuch.nuc); both are asserted below.
run_s16_optional_has_rest() {
  local d bad out
  d="$(mktemp -d)"
  mkdir -p "$d/lib" "$d/use"
  bad=0

  # 1. Solitary, called from ABOVE its definition, optional omitted. This is the
  #    prescan Type verbatim — before the fix it reported
  #    `a :rest call needs the node runtime` for a defn with no `:rest` in it.
  cat > "$d/fwd.nuc" <<'EOF'
(import-use "stdio.h")
(defn caller ():i64 (return (early 1)))
(defn early (a:i32 :optional (b:i64 5)):i64 (return b))
(defn main ():i32 (printf "%ld\n" (caller)) (return 0))
EOF
  ./build/nucleusc "$d/fwd.nuc" -o "$d/fwd.bin" 2>"$d/fwd.err" || true
  out="$("$d/fwd.bin" 2>/dev/null || true)"
  if [ "$out" != "5" ]; then
    echo "FAIL  s16-optional-forward-call (got '$out')"
    sed 's/^/    /' "$d/fwd.err" | head -3
    bad=1
  fi

  # 2. Overloaded, so the call resolves through the generic registry rather than
  #    the scope binding; the literal `3` needs widening to i64, which lands it
  #    in the adapt tier — the one gated on has-rest.
  cat > "$d/ov.nuc" <<'EOF'
(import-use "stdio.h")
(defn pick (a:CStr :optional (b:i64 7)):i64 (return b))
(defn pick (a:i32):i64 (return (as i64 a)))
(defn main ():i32 (printf "%ld %ld\n" (pick "x" 3) (pick 5)) (return 0))
EOF
  ./build/nucleusc "$d/ov.nuc" -o "$d/ov.bin" 2>"$d/ov.err" || true
  out="$("$d/ov.bin" 2>/dev/null || true)"
  if [ "$out" != "3 5" ]; then
    echo "FAIL  s16-optional-overload-widen (got '$out')"
    sed 's/^/    /' "$d/ov.err" | head -3
    bad=1
  fi

  # 3. The second site: the same overload set arriving as `.nuch` `defmethod`
  #    entries. (A SOLITARY `:optional` defn exports a `(declare …)` its own
  #    importer refuses — `declare-param-type` rejects the marker outright — so
  #    the overloaded shape is the only round-trip there is; see
  #    c-header-layout.md §10.)
  #    `resolve-import` tries `.nuc` in every directory before any `.nuch`, so
  #    the source must live where nothing searches or the test silently
  #    exercises it instead (conventions.md, `qgrep` section).
  mkdir -p "$d/src"
  cat > "$d/src/optlib.nuc" <<'EOF'
(defn pick (a:CStr :optional (b:i64 7)):i64 (return b))
(defn pick (a:i32):i64 (return (as i64 a)))
EOF
  ./build/nucleusc --emit-nuch "$d/src/optlib.nuc" > "$d/lib/optlib.nuch" 2>/dev/null
  cat > "$d/use/u.nuc" <<'EOF'
(import-use "stdio.h")
(import-use optlib)
(defn main ():i32 (printf "%ld\n" (pick "x" 3)) (return 0))
EOF
  ./build/nucleusc -I "$d/lib" --emit-llvm "$d/use/u.nuc" > "$d/u.ll" 2>"$d/u.err" || true
  if ! qgrep -F 'declare i64 @pick.cstr.i64(ptr, i64)' "$d/u.ll"; then
    echo "FAIL  s16-optional-nuch-defmethod"
    sed 's/^/    /' "$d/u.err" | head -3
    bad=1
  fi

  # 4. The rule the fix must not lose: a real `:rest` defn still registers
  #    has-rest at the prescan, so a forward call folds its tail into a node list.
  cat > "$d/rest.nuc" <<'EOF'
(import-use "stdio.h")
(import-use node)
(defn caller ():i64 (return (sum 1 2 3 4)))
(defn sum (:rest args:i64):i64
  (let (total:i64 0)
    (while (!= args null)
      (set! total (+ total (unsafe/cast i64 ((unsafe/cast ptr:Node args) 'car))))
      (set! args ((unsafe/cast ptr:Node args) 'cdr)))
    total))
(defn main ():i32 (printf "%ld\n" (caller)) (return 0))
EOF
  ./build/nucleusc "$d/rest.nuc" -o "$d/rest.bin" 2>"$d/rest.err" || true
  out="$("$d/rest.bin" 2>/dev/null || true)"
  if [ "$out" != "10" ]; then
    echo "FAIL  s16-rest-still-folds (got '$out')"
    sed 's/^/    /' "$d/rest.err" | head -3
    bad=1
  fi

  [ "$bad" = 0 ] && echo "PASS  s16-optional-has-rest"
  rm -rf "$d"
}
spawn run_s16_optional_has_rest

# keyword-markers.md §7, follow-up 2: a parametric union's arms are parsed at
# STAMP time, so a never-instantiated `(defunion (Box T) … :repr …)` validated
# nothing — a bogus mode, a mode-less marker and the retired `&repr` were all
# silently accepted. The mode is decidable without stamping, so
# `register-union-template` now runs the real stripper for its diagnostics.
run_s16_template_repr() {
  local d bad
  d="$(mktemp -d)"
  bad=0
  trepr_says() {   # trepr_says <arm-chain-tail> <expected-substring>
    printf '(defunion (Box T) (some v:T) none %s)\n(defn main ():i32 (return 0))\n' "$1" \
      > "$d/t.nuc"
    ./build/nucleusc --emit-llvm "$d/t.nuc" >/dev/null 2>"$d/t.err"
    qgrep -F "$2" "$d/t.err"
  }
  if ! trepr_says ':repr bogus' 'defunion: :repr mode must be `tagged` or `niche`'; then
    echo "FAIL  s16-template-repr-mode (a bogus mode on an uninstantiated template was accepted)"
    bad=1
  fi
  if ! trepr_says ':repr' 'defunion: :repr needs a mode (tagged or niche)'; then
    echo "FAIL  s16-template-repr-missing-mode"
    bad=1
  fi
  if ! trepr_says '&repr tagged' "'&repr' is no longer a marker -- write ':repr'"; then
    echo "FAIL  s16-template-repr-legacy (the retired spelling was accepted on a template)"
    bad=1
  fi
  # And a VALID uninstantiated template still compiles — the check must diagnose,
  # not stamp.
  cat > "$d/ok.nuc" <<'EOF'
(defunion (Box T) (some v:T) none :repr tagged)
(defn main ():i32 (return 0))
EOF
  if ! ./build/nucleusc --emit-llvm "$d/ok.nuc" >/dev/null 2>"$d/ok.err"; then
    echo "FAIL  s16-template-repr-valid-accepted"
    sed 's/^/    /' "$d/ok.err" | head -3
    bad=1
  fi
  [ "$bad" = 0 ] && echo "PASS  s16-template-repr"
  rm -rf "$d"
}
spawn run_s16_template_repr

# Stage 16 — `bool` is its own type, not a 1-bit integer.
# design/stage16-ergonomics/bool-type-plan.md (Part 1 of bool-truthiness.md).
# These replace the four `w9-i1-*literal*` fixtures, which pinned the {0,1}
# range rule this item deletes: a bool slot no longer takes ANY integer, so
# there is no range left to check. The headline defect is `(+ true true)`,
# which used to evaluate to `false` by one-bit wraparound.
run_s16_bool_type() {
  local d ir out
  d="$(mktemp -d)"

  refuses_bool() {   # refuses_bool <file-body> <expected-substring>
    printf '%s\n' "$1" > "$d/ref.nuc"
    ./build/nucleusc --emit-llvm "$d/ref.nuc" >/dev/null 2>"$d/ref.err"
    qgrep -F "$2" "$d/ref.err"
  }

  # 1. No implicit coercion, in either direction — the {0,1} rule's replacement.
  if refuses_bool '(defvar g:bool 1)
(defn main ():i32 (return 0))' \
        'defvar: integer literal incompatible with type bool' \
     && refuses_bool '(defn main ():i32 (let (b:bool 1) (return 0)))' \
        "let: init type mismatch for 'b'" \
     && refuses_bool '(defn main ():i32 (let (n:i32 true) (return 0)))' \
        "let: init type mismatch for 'n'" \
     && refuses_bool '(defn main ():i32 (let (b:bool (as bool 1)) (return 0)))' \
        'as: lossy conversion from i32 to bool -- use unsafe/cast'; then
    echo "PASS  s16-bool-no-implicit-coercion"
  else
    echo "FAIL  s16-bool-no-implicit-coercion (an integer still flowed to or from a bool slot)"
    sed 's/^/    /' "$d/ref.err" | head -3
  fi

  # 2. Arithmetic refuses a bool operand, and a comparison refuses a MIXED pair.
  #    All six comparisons on two bools stay legal (w9-bool-unsigned covers them).
  if refuses_bool '(defn main ():i32 (let (b:bool (+ true true)) (return 0)))' \
        '_+ does not apply to bool' \
     && refuses_bool '(defn main ():i32 (let (b:bool (bit-and true true)) (return 0)))' \
        'bit-and does not apply to bool' \
     && refuses_bool '(defn main ():i32 (let (b:bool (= true 1)) (return 0)))' \
        '=: mixed bool and non-bool operands'; then
    echo "PASS  s16-bool-not-an-integer-operand"
  else
    echo "FAIL  s16-bool-not-an-integer-operand (an arithmetic or mixed-operand form was accepted)"
    sed 's/^/    /' "$d/ref.err" | head -3
  fi

  # 3. `i1` is retired as a spelling, in every type position, and names bool.
  if refuses_bool '(defn main ():i32 (let (b:i1 true) (return 0)))' \
        'i1 is no longer a type — use bool' \
     && refuses_bool '(defn f (a:i1):i32 (return 0))
(defn main ():i32 (return 0))' \
        'i1 is no longer a type — use bool' \
     && refuses_bool '(defn f ():i1 (return true))
(defn main ():i32 (return 0))' \
        'i1 is no longer a type — use bool'; then
    echo "PASS  s16-bool-i1-spelling-retired"
  else
    echo "FAIL  s16-bool-i1-spelling-retired (i1 was accepted, or did not name its replacement)"
    sed 's/^/    /' "$d/ref.err" | head -3
  fi

  # 4. The accepting half. `(as i32 b)` is the sanctioned widening (zext, since
  #    bool is unsigned), and a bool global must hold the value that was WRITTEN
  #    — the assertion a run cannot make, since `global i1 false` for a written
  #    `true` still exits 0 through every check below.
  cat > "$d/ok.nuc" <<'EOF'
(import-use "stdio.h")
(defvar s16b-t:bool true)
(defvar s16b-f:bool false)
(defn main ():i32
  (printf "%d %d\n" (as i32 s16b-t) (as i32 s16b-f))
  (return 0))
EOF
  ir="$(./build/nucleusc --emit-llvm "$d/ok.nuc" 2>"$d/ok.err" || true)"
  ./build/nucleusc "$d/ok.nuc" -o "$d/ok.bin" 2>>"$d/ok.err" || true
  out=""
  # Never a bare `cmd && assign` here: under `set -e` a false test kills the
  # unit before its first echo, which the replay shows as silence, not FAIL.
  if [ -x "$d/ok.bin" ]; then out="$("$d/ok.bin" 2>/dev/null || true)"; fi
  if [ "$out" = "1 0" ] \
     && printf '%s' "$ir" | qgrep -F '@s16b-t = global i1 true' \
     && printf '%s' "$ir" | qgrep -F '@s16b-f = global i1 false' \
     && printf '%s' "$ir" | qgrep -F 'zext i1'; then
    echo "PASS  s16-bool-widens-to-int"
  else
    echo "FAIL  s16-bool-widens-to-int (got '$out')"
    sed 's/^/    /' "$d/ok.err" | head -3
    printf '%s' "$ir" | grep -nE '@s16b-|zext i1' | head -4 | sed 's/^/    /' || true
  fi

  # 5. `as` names `unsafe/cast` in every bool rejection, so the hatch has to be
  #    TOTAL: all five instruction-selection gates must admit a bool operand, or
  #    the diagnostic above advertises a conversion that cannot be written.
  cat > "$d/uc.nuc" <<'EOF'
(import-use "stdio.h")
(defn main ():i32
  (let (b:bool (unsafe/cast bool 1)
        z:bool (unsafe/cast bool 0)
        n:i32  (unsafe/cast i32 true)
        f:f64  (unsafe/cast f64 true)
        w:i64  (unsafe/cast i64 false))
    (printf "%d %d %d %.1f %ld\n" (as i32 b) (as i32 z) n f w))
  (return 0))
EOF
  ./build/nucleusc "$d/uc.nuc" -o "$d/uc.bin" 2>"$d/uc.err" || true
  out=""
  if [ -x "$d/uc.bin" ]; then out="$("$d/uc.bin" 2>/dev/null || true)"; fi
  if [ "$out" = "1 0 1 1.0 0" ]; then
    echo "PASS  s16-bool-unsafe-cast-is-total"
  else
    echo "FAIL  s16-bool-unsafe-cast-is-total (got '$out')"
    sed 's/^/    /' "$d/uc.err" | head -3
  fi

  # 6. The two permanent, user-visible spellings of the type: the mangle token in
  #    an overload's link name, and the C rendering in a generated header. Both
  #    read `i1` before this item; a header consumer sees whichever ships.
  cat > "$d/cs.nuc" <<'EOF'
(defn f (a:bool):i32 (return (as i32 a)))
(defn f (a:i32):i32 (return a))
(defn g (b:bool):bool (return (not b)))
EOF
  ./build/nucleusc --emit-llvm    "$d/cs.nuc" > "$d/cs.ll" 2>"$d/cs.err" || true
  ./build/nucleusc --emit-cheader "$d/cs.nuc" > "$d/cs.h"  2>>"$d/cs.err" || true
  if qgrep -F 'define i32 @f.bool(i1 %a.arg)' "$d/cs.ll" \
     && qgrep -xF 'int32_t f_bool(bool a) asm("f.bool");' "$d/cs.h" \
     && qgrep -xF 'bool g(bool b);' "$d/cs.h" \
     && qgrep -xF '#include <stdbool.h>' "$d/cs.h"; then
    echo "PASS  s16-bool-mangle-and-c-spelling"
  else
    echo "FAIL  s16-bool-mangle-and-c-spelling"
    grep -n 'f_bool\|f\.bool\|g(' "$d/cs.h" | head -4 | sed 's/^/    /' || true
  fi
  rm -rf "$d"
}
spawn run_s16_bool_type

# Stage 16 — nil punning at condition position (Part 2 of bool-truthiness.md,
# Recommendation items 3/4/5). A nullable value IS a condition at the six sites
# `cond`/`while`/`not`/`_and`/`_or` (everything else is a macro over `cond`),
# and nowhere else: this is an elimination rule, not a coercion, so a `bool`
# slot still refuses a pointer. `(when n:i32 …)` stays an error — the design
# drops "all primitive values are true" and leaves zero-is-false open, and both
# decisions depend on that refusal standing.
run_s16_bool_truthiness() {
  local d ir out
  d="$(mktemp -d)"

  refuses_cond() {   # refuses_cond <file-body> <expected-substring>
    printf '%s\n' "$1" > "$d/ref.nuc"
    ./build/nucleusc --emit-llvm "$d/ref.nuc" >/dev/null 2>"$d/ref.err"
    qgrep -F "$2" "$d/ref.err"
  }

  # 1. The feature: all six sites, for each of the four nullable types. Each
  #    probe returns a bitmask so one number pins every site at once —
  #    1 cond, 2 not, 4 _and (lhs AND rhs), 8 _or (lhs OR rhs), 16 while.
  cat > "$d/ok.nuc" <<'EOF'
(import-use "stdio.h")
(import-use arena)

(defstruct Pt x:i32)

(defn probe-raw (p:(raw Pt) q:(raw Pt)):i32
  (let (n:i32 0)
    (when p (set! n (+ n 1)))
    (when (not p) (set! n (+ n 2)))
    (when (and p q) (set! n (+ n 4)))
    (when (or p q) (set! n (+ n 8)))
    (let (c:(raw Pt) p)
      (while c (set! n (+ n 16)) (set! c null)))
    (return n)))

(defn probe-cstr (p:CStr q:CStr):i32
  (let (n:i32 0)
    (when p (set! n (+ n 1)))
    (when (not p) (set! n (+ n 2)))
    (when (and p q) (set! n (+ n 4)))
    (when (or p q) (set! n (+ n 8)))
    (let (c:CStr p)
      (while c (set! n (+ n 16)) (set! c null)))
    (return n)))

(defn probe-maybe-ptr (p:?ptr:Pt q:?ptr:Pt):i32
  (let (n:i32 0)
    (when p (set! n (+ n 1)))
    (when (not p) (set! n (+ n 2)))
    (when (and p q) (set! n (+ n 4)))
    (when (or p q) (set! n (+ n 8)))
    (let (c:?ptr:Pt p)
      (while c (set! n (+ n 16)) (set! c null)))
    (return n)))

(defn probe-maybe-val (p:(Maybe i64) q:(Maybe i64)):i32
  (let (n:i32 0)
    (when p (set! n (+ n 1)))
    (when (not p) (set! n (+ n 2)))
    (when (and p q) (set! n (+ n 4)))
    (when (or p q) (set! n (+ n 8)))
    (let (c:(Maybe i64) p)
      (while c (set! n (+ n 16)) (set! c (make (Maybe i64) none))))
    (return n)))

(defn main ():i32
  (let (a:(ref Pt) (new Pt)
        b:(ref Pt) (new Pt)
        s:CStr c"x"
        t:CStr c"y"
        nc:CStr (as CStr null)
        sm:(Maybe i64) (make (Maybe i64) some 5)
        nm:(Maybe i64) (make (Maybe i64) none))
    (printf "raw %d %d %d %d\n"
      (probe-raw (as (raw Pt) a) (as (raw Pt) b))
      (probe-raw (as (raw Pt) a) null)
      (probe-raw null (as (raw Pt) b))
      (probe-raw null null))
    (printf "cstr %d %d %d %d\n"
      (probe-cstr s t) (probe-cstr s nc) (probe-cstr nc t) (probe-cstr nc nc))
    (printf "mptr %d %d %d %d\n"
      (probe-maybe-ptr (as-ref a) (as-ref b))
      (probe-maybe-ptr (as-ref a) null)
      (probe-maybe-ptr null (as-ref b))
      (probe-maybe-ptr null null))
    (printf "mval %d %d %d %d\n"
      (probe-maybe-val sm sm) (probe-maybe-val sm nm)
      (probe-maybe-val nm sm) (probe-maybe-val nm nm)))
  (return 0))
EOF
  ir="$(./build/nucleusc --emit-llvm "$d/ok.nuc" 2>"$d/ok.err" || true)"
  ./build/nucleusc "$d/ok.nuc" -o "$d/ok.bin" 2>>"$d/ok.err" || true
  out=""
  if [ -x "$d/ok.bin" ]; then out="$("$d/ok.bin" 2>/dev/null || true)"; fi
  # A truthiness test is exactly the shape a run cannot audit (conventions.md,
  # "A wrong value that only reaches a truthiness test is invisible to every
  # gate"), so also pin the two eliminations at the instruction level: a pointer
  # test is `icmp ne ptr`, a value-Maybe test reads the tag word.
  if [ "$out" = "raw 29 25 10 2
cstr 29 25 10 2
mptr 29 25 10 2
mval 29 25 10 2" ] \
     && printf '%s' "$ir" | qgrep -F 'icmp ne ptr' \
     && printf '%s' "$ir" | qgrep -E 'extractvalue %Maybe\.i64 %[a-z0-9.]+, 0'; then
    echo "PASS  s16-truthiness-six-sites"
  else
    echo "FAIL  s16-truthiness-six-sites (got '$out')"
    sed 's/^/    /' "$d/ok.err" | head -4
  fi

  # 2. The narrowing half (item 4). test-true-nonnull matches node SHAPES, so
  #    the bare symbol needed its own arm — without it the condition compiles
  #    and the BODY fails, i.e. the sugar would break exactly the case that
  #    motivates it. All four shapes that reach that arm are here.
  cat > "$d/nw.nuc" <<'EOF'
(import-use "stdio.h")
(import-use arena)

(defstruct Pt x:i32)

(defn f-when (m:?ptr:Pt):i32
  (when m (return (m 'x)))
  (return -1))

(defn f-and (m:?ptr:Pt):i32
  (when (and m (> (m 'x) 0)) (return (m 'x)))
  (return -1))

(defn f-guard (m:?ptr:Pt):i32
  (when (not m) (return -1))
  (return (m 'x)))

(defn f-while (m:?ptr:Pt):i32
  (let (n:i32 -1)
    (while m
      (set! n (m 'x))
      (return n))
    (return n)))

(defn main ():i32
  (let (a:(ref Pt) (new Pt))
    (set! (a 'x) 7)
    (printf "%d %d %d %d %d %d %d %d\n"
      (f-when (as-ref a))  (f-when null)
      (f-and (as-ref a))   (f-and null)
      (f-guard (as-ref a)) (f-guard null)
      (f-while (as-ref a)) (f-while null)))
  (return 0))
EOF
  ./build/nucleusc "$d/nw.nuc" -o "$d/nw.bin" 2>"$d/nw.err" || true
  out=""
  if [ -x "$d/nw.bin" ]; then out="$("$d/nw.bin" 2>/dev/null || true)"; fi
  if [ "$out" = "7 -1 7 -1 7 -1 7 -1" ]; then
    echo "PASS  s16-truthiness-narrows-bare-symbol"
  else
    echo "FAIL  s16-truthiness-narrows-bare-symbol (got '$out')"
    sed 's/^/    /' "$d/nw.err" | head -4
  fi

  # 3. The refusals that must STAY refusals. `(when n:i32 …)` is what keeps
  #    both zero-is-false and all-numbers-true revisable; the non-null pointer
  #    is item 5 — the test is a constant, so say so and name the fix.
  if refuses_cond '(defn main ():i32 (let (n:i32 3) (when n (return 1))) (return 0))' \
        'cond: condition must be bool, not i32' \
     && refuses_cond '(defn main ():i32 (let (n:i32 3) (while n (dec! n))) (return 0))' \
        'while: condition must be bool, not i32' \
     && refuses_cond '(defn main ():i32 (let (n:i32 3) (when (not n) (return 1))) (return 0))' \
        'not: condition must be bool, not i32' \
     && refuses_cond '(defn main ():i32 (let (n:i32 3) (when (and n (> n 0)) (return 1))) (return 0))' \
        'and: condition must be bool, not i32' \
     && refuses_cond '(defn main ():i32 (let (n:i32 3) (when (or n (> n 0)) (return 1))) (return 0))' \
        'or: condition must be bool, not i32' \
     && refuses_cond '(defn main ():i32 (let (f:f64 1.0) (when f (return 1))) (return 0))' \
        'cond: condition must be bool, not f64'; then
    echo "PASS  s16-truthiness-numbers-stay-refused"
  else
    echo "FAIL  s16-truthiness-numbers-stay-refused (a non-bool scalar was accepted as a condition)"
    sed 's/^/    /' "$d/ref.err" | head -3
  fi

  # 4. Item 5 plus the two types nil punning deliberately does not reach: a
  #    Result is neither true nor false, and a non-null pointer's test is a
  #    constant. Both name their own way out.
  if refuses_cond '(defstruct Pt x:i32)
(defn f (p:(ref Pt)):i32 (when p (return 1)) (return 0))
(defn main ():i32 (return 0))' \
        'ptr:Pt is non-null, so this test is always true' \
     && refuses_cond '(defn f (p:ptr):i32 (when p (return 1)) (return 0))
(defn main ():i32 (return 0))' \
        'ptr is non-null, so this test is always true' \
     && refuses_cond '(defstruct Pt x:i32)
(deferror Boom "boom")
(defn g ():!ptr:Pt (return (err Boom)))
(defn f ():i32 (let (r:!ptr:Pt (g)) (when r (return 1))) (return 0))
(defn main ():i32 (return 0))' \
        'a Result (!T) is neither true nor false'; then
    echo "PASS  s16-truthiness-nonnull-and-result-refused"
  else
    echo "FAIL  s16-truthiness-nonnull-and-result-refused"
    sed 's/^/    /' "$d/ref.err" | head -3
  fi

  # 5. It is an ELIMINATION RULE, NOT A COERCION: `coerce-int-val` is untouched,
  #    so `bool` did not become a universal sink. If any of these ever compiles,
  #    truthiness has leaked into the coercion set and overload resolution is
  #    next (bool-truthiness.md, "Do it at condition position").
  if refuses_cond '(defstruct Pt x:i32)
(defn f (b:bool):i32 (return 0))
(defn g (p:(raw Pt)):i32 (return (f p)))
(defn main ():i32 (return 0))' \
        'f: argument 1 has type ptr:Pt, which does not match parameter type bool' \
     && refuses_cond '(defstruct Pt x:i32)
(defn g (p:(raw Pt)):i32 (let (b:bool p) (return 0)))
(defn main ():i32 (return 0))' \
        "let: init type mismatch for 'b'" \
     && refuses_cond '(defstruct Pt x:i32)
(defstruct S flag:bool)
(defn g (p:(raw Pt)):i32 (let (s:(ref S) (alloca S)) (set! (s '\''flag) p)) (return 0))
(defn main ():i32 (return 0))' \
        "set!: type mismatch for field 'flag': value is ptr:Pt, field is bool"; then
    echo "PASS  s16-truthiness-is-not-a-coercion"
  else
    echo "FAIL  s16-truthiness-is-not-a-coercion (a pointer reached a bool slot)"
    sed 's/^/    /' "$d/ref.err" | head -3
  fi
  rm -rf "$d"
}
spawn run_s16_bool_truthiness

# Stage 16 — variables (and any typed expression) as collection-literal elements.
# The readers used to expand `[…]` themselves, so an element had to be a scalar
# literal; the expansion moved to emit-collection-lit, which is the first phase
# where an element has a type.
# design/stage16-ergonomics/collection-literal-variables.md
run_s16_literal_variables() {
  local d out err
  d="$(mktemp -d)"
  local PRE='(import-use "stdio.h")
(import-use vector)
(import-use hashset)
(import-use hashmap)'

  # 1. The feature: enum members, a defconst, a local, and a call, in all three
  #    literal kinds. Every one of these was a hard error before this item.
  cat > "$d/ok.nuc" <<EOF
$PRE
(defenum BK BK-GLOBAL BK-PROTOCOL BK-GENERIC BK-MACRO)
(defconst LIMIT 40)
(defn twice (x:i32):i32 (return (* 2 x)))
(defn main ():i32
  (let (kind:i32 BK-MACRO other:i32 7)
    (with ((s (ref (HashSet i32))) #{BK-GLOBAL BK-PROTOCOL other (twice 9)})
      (printf "set=%d %d %d %d\n" (unsafe/cast i32 (count s))
        (unsafe/cast i32 (contains? s BK-GLOBAL)) (unsafe/cast i32 (contains? s 18))
        (unsafe/cast i32 (contains? s kind))))
    (with ((v (ref (Vector i32))) [LIMIT other])
      (printf "vec=%d %d\n" (invoke v 0) (invoke v 1)))
    (with ((m (ref (HashMap i32 i32))) {BK-GLOBAL other BK-MACRO LIMIT})
      (printf "map=%d\n" (unsafe/cast i32 (count m)))))
  (return 0))
EOF
  ./build/nucleusc "$d/ok.nuc" -o "$d/ok.bin" 2>"$d/ok.err" || true
  out="$("$d/ok.bin" 2>/dev/null || true)"
  if [ "$out" = "set=4 1 1 0
vec=40 7
map=2" ]; then
    echo "PASS  s16-litvar-accepted"
  else
    echo "FAIL  s16-litvar-accepted"
    sed 's/^/    /' "$d/ok.err" | head -3; printf '%s\n' "$out" | sed 's/^/    got: /'
  fi

  # 2. Target-first, and the soundness regression it closes. Before this item
  #    `(ref (Vector i64))` bound to a literal-built (Vector i32) with no error
  #    and `(invoke v 0)` read two i32 elements back as one i64 — 8589934593.
  cat > "$d/want.nuc" <<EOF
$PRE
(defn main ():i32
  (with ((v (ref (Vector i64))) [1 2 3])
    (printf "want=%lld %d\n" (invoke v 0) (unsafe/cast i32 (count v))))
  (return 0))
EOF
  ./build/nucleusc "$d/want.nuc" -o "$d/want.bin" 2>/dev/null || true
  out="$("$d/want.bin" 2>/dev/null || true)"
  if [ "$out" = "want=1 3" ]; then
    echo "PASS  s16-litvar-target-wins"
  else
    echo "FAIL  s16-litvar-target-wins (expected 'want=1 3', a wrong element type reads 8589934593)"
    printf '%s\n' "$out" | sed 's/^/    got: /'
  fi
  # …and it must stamp only the wanted instance, not build i32 and reinterpret.
  if ./build/nucleusc --emit-llvm "$d/want.nuc" 2>/dev/null | qgrep -F 'Vector.i32'; then
    echo "FAIL  s16-litvar-target-stamps-once (a stray Vector.i32 was built)"
  else
    echo "PASS  s16-litvar-target-stamps-once"
  fi

  # 3. A numeric literal ADAPTS to a value element, exactly as `(conj v 1)` on a
  #    (Vector i64) already does; a value is never narrowed to suit a literal.
  cat > "$d/adapt.nuc" <<EOF
$PRE
(defn main ():i32
  (let (n:i64 5000000000)
    (with ((v (ref (Vector i64))) [n 1 2])
      (printf "adapt=%lld %lld\n" (invoke v 0) (invoke v 1))))
  (return 0))
EOF
  ./build/nucleusc "$d/adapt.nuc" -o "$d/adapt.bin" 2>/dev/null || true
  out="$("$d/adapt.bin" 2>/dev/null || true)"
  if [ "$out" = "adapt=5000000000 1" ]; then
    echo "PASS  s16-litvar-literal-adapts"
  else
    echo "FAIL  s16-litvar-literal-adapts"; printf '%s\n' "$out" | sed 's/^/    got: /'
  fi

  # 4. Elements evaluate left to right, which only became observable once an
  #    element could be a call.
  cat > "$d/order.nuc" <<EOF
$PRE
(defvar seq:i32 0)
(defn tick (tag:i32):i32 (printf "%d" tag) (set! seq (+ seq 1)) (return tag))
(defn main ():i32
  (with ((v (ref (Vector i32))) [(tick 1) (tick 2) (tick 3)])
    (printf "|%d\n" (unsafe/cast i32 (count v))))
  (return 0))
EOF
  ./build/nucleusc "$d/order.nuc" -o "$d/order.bin" 2>/dev/null || true
  out="$("$d/order.bin" 2>/dev/null || true)"
  if [ "$out" = "123|3" ]; then
    echo "PASS  s16-litvar-eval-order"
  else
    echo "FAIL  s16-litvar-eval-order (expected '123|3')"; printf '%s\n' "$out" | sed 's/^/    got: /'
  fi

  # 5. An empty literal is legal exactly when a target supplies the element type;
  #    with no target it keeps the message naming the constructor.
  cat > "$d/empty.nuc" <<EOF
$PRE
(defn main ():i32
  (with ((v (ref (Vector i32))) [])
    (printf "empty=%d\n" (unsafe/cast i32 (count v))))
  (return 0))
EOF
  ./build/nucleusc "$d/empty.nuc" -o "$d/empty.bin" 2>/dev/null || true
  out="$("$d/empty.bin" 2>/dev/null || true)"
  if [ "$out" = "empty=0" ]; then
    echo "PASS  s16-litvar-empty-with-target"
  else
    echo "FAIL  s16-litvar-empty-with-target"; printf '%s\n' "$out" | sed 's/^/    got: /'
  fi

  # 6. Refusals. Each names the literal and, where two types clash, both of them.
  local name src want
  while IFS='|' read -r name src want; do
    [ -n "$name" ] || continue
    printf '%s\n%s\n' "$PRE" "$src" > "$d/$name.nuc"
    err="$(./build/nucleusc --emit-llvm "$d/$name.nuc" 2>&1 >/dev/null || true)"
    if printf '%s' "$err" | qgrep -F "$want"; then
      echo "PASS  s16-litvar-refused-$name"
    else
      echo "FAIL  s16-litvar-refused-$name"
      printf '%s\n' "$err" | sed 's/^/    got: /' | head -2
    fi
  done <<'EOF'
mixed-values|(defn main ():i32 (let (a:i32 1 b:i64 2) (let (v [a b]) (return 0))))|vector literal: mixed element types -- 'i32' and 'i64'
int-float|(defn main ():i32 (let (v [1 2.5]) (return 0)))|vector literal: mixed element types
int-string|(defn main ():i32 (let (v ["a" 1]) (return 0)))|vector literal: mixed element types
empty-no-target|(defn main ():i32 (let (v []) (return 0)))|empty vector literal: use (vector-new)
narrow-value|(defn main ():i32 (let (n:i64 5) (with ((v (ref (Vector i32))) [n 1]) (return 0))))|no matching method for overloaded 'conj'
unspellable|(defstruct P x:i32) (defn main ():i32 (let (p:(ref P) (alloca P)) (let (v [p p]) (return 0))))|cannot infer an element type from a value of type 'ptr:P'
shadow-head|(defn vector-lit (x:i32):i32 (return x)) (defn main ():i32 (return 0))|already names a special form
EOF
  rm -rf "$d"
}
spawn run_s16_literal_variables

# C's default argument promotions at a variadic call position (C17 6.5.2.2p6).
# Before this fix `emit-call-with-args` passed the narrow type straight through,
# so `(printf "%d %f" x:i16 y:f32)` emitted `i16`/`float` operands where clang
# emits `i32`/`double`. Two of the five cases were live wrong answers; the other
# three were right only because LLVM's x86-64 lowering happens to zero the
# register, which is why unit 2 asserts on the INSTRUCTION and not just the run.
# design/stage16-ergonomics/varargs-promotion.md
run_s16_vararg_promotion() {
  local d out ir
  d="$(mktemp -d)"

  # 1. The run: every promoted type, against the answers C gives for the
  #    identical program. i16 printed 1321270996 and f32 printed 0.000000.
  cat > "$d/run.nuc" <<'EOF'
(import-use "stdio.h")
(defn main ():i32
  (let (a:i8 65 b:i16 -300 c:ui8 200 d:f32 2.5 e:bool true f:Char \A)
    (printf "%d %d %u %f %d %d\n" a b c d e f))
  (return 0))
EOF
  ./build/nucleusc "$d/run.nuc" -o "$d/run.bin" 2>"$d/run.err" || true
  out="$("$d/run.bin" 2>/dev/null || true)"
  if [ "$out" = "65 -300 200 2.500000 1 65" ]; then
    echo "PASS  s16-vararg-promotion-run"
  else
    echo "FAIL  s16-vararg-promotion-run"
    sed 's/^/    /' "$d/run.err" | head -3; printf '%s\n' "$out" | sed 's/^/    got: /'
  fi

  # 2. The instruction. `bool`/`i8`/`ui8` print correctly under BOTH behaviours,
  #    so the run above cannot distinguish them — only the IR can.
  ./build/nucleusc "$d/run.nuc" --emit-llvm > "$d/run.ll" 2>/dev/null || true
  ir="$(grep 'call i32 (ptr, ...) @printf' "$d/run.ll" | head -1)"
  if printf '%s\n' "$ir" | qgrep 'i32 %.*, i32 %.*, i32 %.*, double %.*, i32 %.*, i32 %' &&
     ! printf '%s\n' "$ir" | qgrep -E '(i1|i8|i16|float) %'; then
    echo "PASS  s16-vararg-promotion-ir"
  else
    echo "FAIL  s16-vararg-promotion-ir"
    printf '%s\n' "$ir" | sed 's/^/    got: /'
  fi

  # 3. Only the `...` tail promotes. A variadic callee's FIXED narrow parameter
  #    keeps its declared type — the promotion is a property of the position,
  #    not of the type, so a rule applied one argument too early would widen it.
  cat > "$d/fix.h" <<'EOF'
int narrowfix(signed char tag, ...);
EOF
  cat > "$d/fix.nuc" <<EOF
(import-use "$d/fix.h")
(defn go (a:i8 b:i8 c:f32):i32 (return (narrowfix a b c)))
EOF
  ./build/nucleusc "$d/fix.nuc" --emit-llvm > "$d/fix.ll" 2>"$d/fix.err" || true
  if qgrep 'call i32 (i8, ...) @narrowfix(i8 %.*, i32 %.*, double %' "$d/fix.ll"; then
    echo "PASS  s16-vararg-promotion-fixed-param-untouched"
  else
    echo "FAIL  s16-vararg-promotion-fixed-param-untouched"
    sed 's/^/    /' "$d/fix.err" | head -3
    grep 'narrowfix' "$d/fix.ll" | sed 's/^/    got: /'
  fi

  # 4. Nothing already `int`-wide or wider is touched — a spurious promotion
  #    would be as wrong as a missing one, and costs an instruction per call.
  cat > "$d/wide.nuc" <<'EOF'
(import-use "stdio.h")
(defn main ():i32
  (let (a:i32 1 b:i64 2 c:f64 3.5 d:ui32 4)
    (printf "%d %ld %f %u\n" a b c d))
  (return 0))
EOF
  ./build/nucleusc "$d/wide.nuc" --emit-llvm > "$d/wide.ll" 2>/dev/null || true
  ir="$(grep 'call i32 (ptr, ...) @printf' "$d/wide.ll" | head -1)"
  if printf '%s\n' "$ir" | qgrep 'i32 %.*, i64 %.*, double %.*, i32 %'; then
    echo "PASS  s16-vararg-promotion-no-spurious-widening"
  else
    echo "FAIL  s16-vararg-promotion-no-spurious-widening"
    printf '%s\n' "$ir" | sed 's/^/    got: /'
  fi

  rm -rf "$d"
}
spawn run_s16_vararg_promotion

# --- Stage 16 type aliases (design/stage16-ergonomics/container-type-sugar.md) ---
run_s16_type_aliases() {
  local d out
  d="$(mktemp -d)"
  mkdir -p "$d/lib"

  refuses_alias() {
    printf '%s\n' "$1" > "$d/ref.nuc"
    ./build/nucleusc --emit-llvm "$d/ref.nuc" >/dev/null 2>"$d/ref.err"
    qgrep -F "$2" "$d/ref.err"
  }

  # 1. An alias works in every declaration position, and composes with the
  #    colon sugar (§3.9 — a single-token type name needs no fuse at all).
  cat > "$d/all.nuc" <<'EOF'
(import-use "stdio.h")
(import-use hashset)
(import-use coll)
(deftype NameSet (ref (HashSet CStr)))
(deftype Count i64)
(defstruct Reg names:NameSet)
(defvar gv:Count 7)
(defn size (s:NameSet):Count (return (as Count (count s))))
(defn main ():i32
  (with (s:NameSet (alloca (HashSet CStr)))
    (hashset-init s)
    (conj s (as CStr "a"))
    (conj s (as CStr "b"))
    (let (t:NameSet s)
      (printf "%ld %ld\n" (size t) gv)))
  (return 0))
EOF
  ./build/nucleusc "$d/all.nuc" -o "$d/all.bin" 2>"$d/all.err" || true
  out="$("$d/all.bin" 2>/dev/null || true)"
  if [ "$out" = "2 7" ]; then
    echo "PASS  s16-deftype-every-position"
  else
    echo "FAIL  s16-deftype-every-position"
    sed 's/^/    /' "$d/all.err" | head -3; printf '%s\n' "$out" | sed 's/^/    got: /'
  fi

  # 2. Transparency (§3.2) is the load-bearing claim: an alias is a second
  #    SPELLING, not a second type, so the IR must be identical to the
  #    spelled-out program. This is also what keeps the bootstrap byte-identical
  #    until a source file adopts one.
  cat > "$d/alias.nuc" <<'EOF'
(import-use hashmap)
(import-use coll)
(deftype SymTab (ref (HashMap CStr i32)))
(defn tally (m:SymTab):i64 (return (as i64 (count m))))
EOF
  cat > "$d/plain.nuc" <<'EOF'
(import-use hashmap)
(import-use coll)
(defn tally (m:(ref (HashMap CStr i32))):i64 (return (as i64 (count m))))
EOF
  ./build/nucleusc --emit-llvm "$d/alias.nuc" 2>/dev/null \
    | grep -v '^; ModuleID\|^source_filename' > "$d/alias.ll" || true
  ./build/nucleusc --emit-llvm "$d/plain.nuc" 2>/dev/null \
    | grep -v '^; ModuleID\|^source_filename' > "$d/plain.ll" || true
  if [ -s "$d/alias.ll" ] && cmp -s "$d/alias.ll" "$d/plain.ll"; then
    echo "PASS  s16-deftype-transparent-ir"
  else
    echo "FAIL  s16-deftype-transparent-ir (an alias changed the emitted IR)"
    diff "$d/alias.ll" "$d/plain.ll" 2>/dev/null | head -6 | sed 's/^/    /'
  fi

  # 3. Composition (§3.3): the ?/! sigils, pointer-kind chains, template
  #    arguments, alias-of-alias, and a forward reference all route through the
  #    two resolution sites without their own code.
  cat > "$d/comp.nuc" <<'EOF'
(import-use "stdio.h")
(import-use vector)
(defstruct Pt x:i32 y:i32)
(deftype P Pt)
(deftype PRef (ref P))
(deftype Later i32)
(defn viaq (v:?PRef):i32 (if-some (p v) (return (p 'x)) (return -1)))
(defn chain (v:ref:P):i32 (return (v 'y)))
(defn intmpl (v:(ref (Vector Later))):i32 (return 0))
(defn fwd (n:Later):i32 (return n))
(defn main ():i32
  (with (p:PRef (alloca Pt))
    (set! (p 'x) 3) (set! (p 'y) 4)
    (printf "%d %d %d\n" (viaq p) (chain p) (fwd 5)))
  (return 0))
EOF
  ./build/nucleusc "$d/comp.nuc" -o "$d/comp.bin" 2>"$d/comp.err" || true
  out="$("$d/comp.bin" 2>/dev/null || true)"
  if [ "$out" = "3 4 5" ]; then
    echo "PASS  s16-deftype-composes"
  else
    echo "FAIL  s16-deftype-composes"
    sed 's/^/    /' "$d/comp.err" | head -3; printf '%s\n' "$out" | sed 's/^/    got: /'
  fi

  # 4. A colliding alias would be DEAD, not merely ambiguous — parse-type-name
  #    probes aliases last — so every collision is refused rather than silently
  #    ignored (§3.4 / type-name-collision). Both orders, since the check runs
  #    on the prescan pass and again on the emit pass.
  if refuses_alias '(defstruct Pt x:i32)
(deftype Pt i32)' "already names a type" \
     && refuses_alias '(import-use vector)
(deftype Vector i32)' "already names a struct template" \
     && refuses_alias '(defenum E A B)
(deftype E i32)' "already names an enumeration" \
     && refuses_alias '(deftype i32 i64)' "already names a built-in type" \
     && refuses_alias '(deftype Q i32)
(defstruct Q a:i32)' "already names a type" \
     && refuses_alias '(defn Q ():i32 (return 0))
(deftype Q i32)' "a symbol may name only one kind of thing" \
     && refuses_alias '(deftype Q i32)
(deftype Q i64)' "redefinition of 'Q'"; then
    echo "PASS  s16-deftype-collisions-refused"
  else
    echo "FAIL  s16-deftype-collisions-refused (a colliding alias was accepted)"
    sed 's/^/    /' "$d/ref.err" | head -3
  fi

  # 5. Malformed forms, and the §3.6 cycle guard (a recursive body would not
  #    otherwise terminate).
  if refuses_alias '(deftype Q)' 'deftype: expects a name and one type' \
     && refuses_alias '(deftype Q i32 i64)' 'deftype: expects a name and one type' \
     && refuses_alias '(deftype Q:i32 i64)' 'deftype: takes no type annotation' \
     && refuses_alias '(deftype () i32)' 'deftype: alias name must be a symbol' \
     && refuses_alias '(deftype (Tbl) i32)' 'deftype: parameter list required' \
     && refuses_alias '(deftype (Tbl 3) i32)' 'deftype: each type parameter must be a symbol' \
     && refuses_alias '(deftype A B)
(deftype B A)
(defn f (x:A):i32 (return 0))' 'expands into a cycle'; then
    echo "PASS  s16-deftype-malformed-refused"
  else
    echo "FAIL  s16-deftype-malformed-refused"
    sed 's/^/    /' "$d/ref.err" | head -3
  fi

  # 6. `.nuch` round-trip. The header must CARRY the alias — an exported defn
  #    may name it in its signature, and the importer resolves that spelling in
  #    its own unit. (This is the one part of the design that needed code: the
  #    export and import dispatches are both explicit form lists.)
  cat > "$d/lib/alib.nuc" <<'EOF'
(deftype Count i64)
(defn twice (n:Count):Count (return (* n 2)))
EOF
  ./build/nucleusc --emit-nuch "$d/lib/alib.nuc" > "$d/lib/alib.nuch" 2>/dev/null
  cat > "$d/use.nuc" <<'EOF'
(import-use "stdio.h")
(import-use alib)
(defn main ():i32 (printf "%ld\n" (twice 21)) (return 0))
EOF
  if qgrep -F '(deftype Count i64)' "$d/lib/alib.nuch" \
     && [ "$(./build/nucleusc -I "$d/lib" "$d/use.nuc" -o "$d/use.bin" 2>/dev/null \
             && "$d/use.bin")" = "42" ]; then
    echo "PASS  s16-deftype-nuch-roundtrip"
  else
    echo "FAIL  s16-deftype-nuch-roundtrip (an alias did not survive .nuch export/import)"
    sed 's/^/    /' "$d/lib/alib.nuch" | head -4
  fi

  # 7. `deftype-`. Privacy here is NAMESPACE-level, as it is for the other four
  #    private type definers (see run_b5_private_definers), so the check needs a
  #    namespaced library and a consumer outside it — spelling the name through
  #    the prefix, so a refusal measures privacy and not just scope. Plus the
  #    positive control that a file INSIDE the namespace still sees it, and that
  #    the header does not carry it.
  cat > "$d/lib/tplib.nuc" <<'EOF'
(ns t16p)
(deftype- T16Hidden i64)
(deftype T16Public i64)
(defn- t16-inside (n:T16Hidden):T16Hidden (return (* n 3)))
(defn t16-pub (n:T16Public):T16Public (return (t16-inside n)))
EOF
  cat > "$d/tp-out.nuc" <<'EOF'
(import-prefixed tplib tp)
(defn t16-take (n:tp/T16Hidden):i64 (return n))
(defn main ():i32 (return 0))
EOF
  cat > "$d/tp-pub.nuc" <<'EOF'
(import-prefixed tplib tp)
(defn t16-take (n:tp/T16Public):i64 (return n))
(defn main ():i32 (return 0))
EOF
  ./build/nucleusc -I "$d/lib" --emit-nuch "$d/lib/tplib.nuc" > "$d/lib/tplib.nuch" 2>/dev/null
  ./build/nucleusc -I "$d/lib" --emit-llvm "$d/tp-out.nuc" >/dev/null 2>"$d/tp-out.err" || true
  ./build/nucleusc -I "$d/lib" --emit-llvm "$d/tp-pub.nuc" >/dev/null 2>"$d/tp-pub.err" || true
  if qgrep -F 'T16Hidden' "$d/tp-out.err" \
     && [ ! -s "$d/tp-pub.err" ] \
     && ! qgrep -F 'T16Hidden' "$d/lib/tplib.nuch" \
     && qgrep -F 'T16Public' "$d/lib/tplib.nuch"; then
    echo "PASS  s16-deftype-private-namespaced"
  else
    echo "FAIL  s16-deftype-private-namespaced (a deftype- alias leaked, or deftype stopped exporting)"
    sed 's/^/    out: /' "$d/tp-out.err" | head -2
    sed 's/^/    pub: /' "$d/tp-pub.err" | head -2
    sed 's/^/    hdr: /' "$d/lib/tplib.nuch" | head -4
  fi

  # 8. The C header must show the alias's BODY. It has no C spelling of its own,
  #    and `type-node-to-c` resolved names by spelling — so the alias name leaked
  #    out as `struct Count`, naming nothing the header defines. Asserted against
  #    the spelled-out program, which is the only definition of "right" here.
  cat > "$d/chA.nuc" <<'EOF'
(defstruct Pt x:i32 y:i32)
(deftype Count i64)
(deftype PtRef (ref Pt))
(defn twice (n:Count):Count (return (* n 2)))
(defn getx (p:PtRef):i32 (return (p 'x)))
EOF
  cat > "$d/chB.nuc" <<'EOF'
(defstruct Pt x:i32 y:i32)
(defn twice (n:i64):i64 (return (* n 2)))
(defn getx (p:(ref Pt)):i32 (return (p 'x)))
EOF
  ./build/nucleusc --emit-cheader "$d/chA.nuc" 2>/dev/null | grep -v '^/\* Generated' > "$d/chA.h" || true
  ./build/nucleusc --emit-cheader "$d/chB.nuc" 2>/dev/null | grep -v '^/\* Generated' > "$d/chB.h" || true
  if [ -s "$d/chA.h" ] && cmp -s "$d/chA.h" "$d/chB.h"; then
    echo "PASS  s16-deftype-cheader-expands"
  else
    echo "FAIL  s16-deftype-cheader-expands (an alias name leaked into the C header)"
    diff "$d/chA.h" "$d/chB.h" 2>/dev/null | head -6 | sed 's/^/    /'
  fi

  # 9. The REPL has its own top-level form chain; without an arm there `deftype`
  #    was `unknown: deftype` and every later use of the name failed too.
  out="$(printf '(deftype C i64)\n(defn d (n:C):C (return (* n 2)))\n(d 21)\n' \
         | ./build/nucleusc -i 2>&1 | tr -d '\n')"
  case "$out" in
    *42*) echo "PASS  s16-deftype-repl" ;;
    *)    echo "FAIL  s16-deftype-repl"
          printf '%s\n' "$out" | sed 's/^/    got: /' ;;
  esac

  rm -rf "$d"
}
spawn run_s16_type_aliases

# CT-D (container-type-sugar.md §1.2): a colon chain absorbs its whole tail as
# one type, so a chain that tries to nest a pointer kind overshoots the
# template's arity. The surplus symbols used to be collected as tyvars, which
# reclassified a concrete defn as an uninstantiable template — emit-defn skipped
# its define and NOTHING was reported; the only symptom was an error at the call
# site naming a function the module no longer contained.
run_s16_chain_nesting() {
  local d out ir
  d="$(mktemp -d)"

  refuses_chain() {
    printf '(import-use vector)\n(import-use hashmap)\n(import-use node)\n%s\n(defn main ():i32 (return 0))\n' "$1" > "$d/c.nuc"
    ./build/nucleusc --emit-llvm "$d/c.nuc" >/dev/null 2>"$d/c.err"
    qgrep -F "$2" "$d/c.err" && qgrep -F "c.nuc:4:" "$d/c.err"
  }

  # 1. The three silent rows of §1.2, each located and each naming the template.
  #    Bare `ref` is the trigger: `ptr` and `raw` are types (tyname-resolvable),
  #    so they overshoot into the arity check below instead.
  if refuses_chain '(defn f (x:ref:Vector:ref:Node):i32 (return 21))' \
       "Vector: 'ref' is a pointer kind" \
     && refuses_chain '(defn f (x:ref:HashMap:CStr:ref:Vector:i32):i32 (return 21))' \
       "HashMap: 'ref' is a pointer kind" \
     && refuses_chain '(defn f (x:ref:HashMap:ref:Vector:i32:i32):i32 (return 21))' \
       "HashMap: 'ref' is a pointer kind"; then
    echo "PASS  s16-chain-nested-ref-refused"
  else
    echo "FAIL  s16-chain-nested-ref-refused"
    sed 's/^/    /' "$d/c.err" | head -3
  fi

  # 2. The general net behind that one case: any over-long argument list in a
  #    type pattern is an arity error, matching what the concrete path already
  #    said for `ref:Vector:ptr:i8` before it could reach the template stamp.
  if refuses_chain '(defn f (x:ref:Vector:ptr:i8):i32 (return 21))' \
       "Vector: wrong number of type arguments for defstruct template (2 given)" \
     && refuses_chain '(defn f (x:ref:(Vector i32 CStr)):i32 (return 21))' \
       "Vector: wrong number of type arguments for defstruct template (2 given)"; then
    echo "PASS  s16-chain-arity-refused"
  else
    echo "FAIL  s16-chain-arity-refused"
    sed 's/^/    /' "$d/c.err" | head -3
  fi

  # 3. The guards must not cost the spellings docs/types.md now advertises, and
  #    a genuine tyvar must still be a tyvar. Asserted as a `define` per
  #    function, because a missing define IS the §1.2 bug — the original failure
  #    compiled a module with zero of them and said nothing.
  cat > "$d/ok.nuc" <<'EOF'
(import-use "stdio.h")
(import-use vector)
(import-use hashmap)
(import-use node)
(import-use coll)
(defn ca (x:ref:HashMap:CStr:i32):i32 (return 1))
(defn cb (x:ref:Vector:i32):i32 (return 2))
(defn cc (x:ref:(Vector (ref Node))):i32 (return 3))
(defn cd (x:ref:(HashMap CStr i32)):i32 (return 4))
(defn ce (x:ref:Vector:ptr):i32 (return 5))
(defn tyv (v:(ref (Vector T))):i64 (return (as i64 (count v))))
(defn main ():i32
  (with (v:(ref (Vector i32)) (alloca (Vector i32)))
    (vector-init v)
    (conj v 9)
    (printf "%d %ld\n" (cb v) (tyv v)))
  (return 0))
EOF
  ir="$(./build/nucleusc --emit-llvm "$d/ok.nuc" 2>"$d/ok.err" || true)"
  ./build/nucleusc "$d/ok.nuc" -o "$d/ok.bin" 2>>"$d/ok.err" || true
  out="$("$d/ok.bin" 2>/dev/null || true)"
  ndef="$(printf '%s' "$ir" | grep -cE '^define i32 @c[abcde]\(' || true)"
  if [ "$ndef" = "5" ] && [ "$out" = "2 1" ]; then
    echo "PASS  s16-chain-working-spellings"
  else
    echo "FAIL  s16-chain-working-spellings (defines: $ndef of 5)"
    sed 's/^/    /' "$d/ok.err" | head -4; printf '%s\n' "$out" | sed 's/^/    got: /'
  fi

  # 4. The fuse and the list form are two spellings of one type, not two types:
  #    assert it as IR equality rather than as a claim (the §3.11 convention).
  printf '(import-use hashmap)\n(import-use coll)\n(defn t (m:ref:(HashMap CStr i32)):i64 (return (as i64 (count m))))\n' > "$d/fuse.nuc"
  printf '(import-use hashmap)\n(import-use coll)\n(defn t (m:(ref (HashMap CStr i32))):i64 (return (as i64 (count m))))\n' > "$d/list.nuc"
  for f in fuse list; do
    ./build/nucleusc --emit-llvm "$d/$f.nuc" 2>/dev/null \
      | grep -v '^; ModuleID\|^source_filename' > "$d/$f.ll" || true
  done
  if [ -s "$d/fuse.ll" ] && cmp -s "$d/fuse.ll" "$d/list.ll"; then
    echo "PASS  s16-chain-fuse-transparent-ir"
  else
    echo "FAIL  s16-chain-fuse-transparent-ir"
    diff "$d/fuse.ll" "$d/list.ll" 2>/dev/null | head -6 | sed 's/^/    /'
  fi

  rm -rf "$d"
}
spawn run_s16_chain_nesting

# CT-B phase 2 (container-type-sugar.md §3.7): `(deftype (Vec T) …)`. The alias
# is applied by substituting the argument NODES into its body and parsing the
# result, so — exactly as for the plain form — no Type ever carries the alias
# name. The load-bearing site is the method receiver: an unexpanded `(Vec T)`
# matches no template and no pointer wrapper, so `T` would never be collected as
# a tyvar and the template would be misread as concrete.
run_s16_parametric_aliases() {
  local d out
  d="$(mktemp -d)"
  mkdir -p "$d/lib"

  refuses_p() {
    printf '%s\n' "$1" > "$d/p.nuc"
    ./build/nucleusc --emit-llvm "$d/p.nuc" >/dev/null 2>"$d/p.err"
    qgrep -F "$2" "$d/p.err"
  }

  # 1. Every declaration position, plus a colon-spelled body (`(Ref T) ref:T`),
  #    which substitutes segment-wise rather than by node.
  cat > "$d/all.nuc" <<'EOF'
(import-use "stdio.h")
(import-use vector)
(import-use hashmap)
(import-use coll)
(deftype (Vec T) (ref (Vector T)))
(deftype (Table V) (ref (HashMap CStr V)))
(deftype (Ref T) ref:T)
(defstruct Pt x:i32 y:i32)
(defstruct Reg items:(Vec i32) names:(Table i32))
(defn total (v:(Vec i32)):i64 (return (as i64 (count v))))
(defn look (m:(Table i32)):i64 (return (as i64 (count m))))
(defn getx (p:(Ref Pt)):i32 (return (p 'x)))
(defn main ():i32
  (with (v:(Vec i32) (alloca (Vector i32))
         m:(Table i32) (alloca (HashMap CStr i32))
         p:(Ref Pt) (alloca Pt))
    (vector-init v) (hashmap-init m)
    (conj v 4) (conj v 5)
    (assoc m "a" 1)
    (set! (p 'x) 9)
    (printf "%ld %ld %d\n" (total v) (look m) (getx p)))
  (return 0))
EOF
  ./build/nucleusc "$d/all.nuc" -o "$d/all.bin" 2>"$d/all.err" || true
  out="$("$d/all.bin" 2>/dev/null || true)"
  if [ "$out" = "2 1 9" ]; then
    echo "PASS  s16-deftype-parametric-every-position"
  else
    echo "FAIL  s16-deftype-parametric-every-position"
    sed 's/^/    /' "$d/all.err" | head -3; printf '%s\n' "$out" | sed 's/^/    got: /'
  fi

  # 2. §3.7's stated hard case: a generic template whose RECEIVER is an alias
  #    application, instantiated at two element types. This is the one that
  #    needed collect-pattern-tyvars and unify-tpat taught about aliases.
  cat > "$d/recv.nuc" <<'EOF'
(import-use "stdio.h")
(import-use vector)
(import-use coll)
(deftype (Vec T) (ref (Vector T)))
(defn second (v:(Vec T)):T (return (invoke v (as usize 1))))
(defn main ():i32
  (with (a:(Vec i32) (alloca (Vector i32))
         b:(Vec CStr) (alloca (Vector CStr)))
    (vector-init a) (vector-init b)
    (conj a 10) (conj a 20)
    (conj b "x") (conj b "y")
    (printf "%d %s\n" (second a) (second b)))
  (return 0))
EOF
  ./build/nucleusc "$d/recv.nuc" -o "$d/recv.bin" 2>"$d/recv.err" || true
  out="$("$d/recv.bin" 2>/dev/null || true)"
  if [ "$out" = "20 y" ]; then
    echo "PASS  s16-deftype-parametric-receiver"
  else
    echo "FAIL  s16-deftype-parametric-receiver"
    sed 's/^/    /' "$d/recv.err" | head -3; printf '%s\n' "$out" | sed 's/^/    got: /'
  fi

  # 3. Transparency, asserted as IR equality against the spelled-out program —
  #    including the generic `t3`, whose stamped instance must mangle from the
  #    expansion and not from the alias name.
  cat > "$d/alias.nuc" <<'EOF'
(import-use vector)
(import-use hashmap)
(import-use coll)
(deftype (Vec T) (ref (Vector T)))
(deftype (Table V) (ref (HashMap CStr V)))
(defn t1 (v:(Vec i32)):i64 (return (as i64 (count v))))
(defn t2 (m:(Table i32)):i64 (return (as i64 (count m))))
(defn t3 (v:(Vec T)):i64 (return (as i64 (count v))))
(defn use ():i64 (return (t3 (unsafe/cast (ref (Vector CStr)) null))))
EOF
  cat > "$d/plain.nuc" <<'EOF'
(import-use vector)
(import-use hashmap)
(import-use coll)
(defn t1 (v:(ref (Vector i32))):i64 (return (as i64 (count v))))
(defn t2 (m:(ref (HashMap CStr i32))):i64 (return (as i64 (count m))))
(defn t3 (v:(ref (Vector T))):i64 (return (as i64 (count v))))
(defn use ():i64 (return (t3 (unsafe/cast (ref (Vector CStr)) null))))
EOF
  for f in alias plain; do
    ./build/nucleusc --emit-llvm "$d/$f.nuc" 2>/dev/null \
      | grep -v '^; ModuleID\|^source_filename' > "$d/$f.ll" || true
  done
  if [ -s "$d/alias.ll" ] && cmp -s "$d/alias.ll" "$d/plain.ll"; then
    echo "PASS  s16-deftype-parametric-transparent-ir"
  else
    echo "FAIL  s16-deftype-parametric-transparent-ir"
    diff "$d/alias.ll" "$d/plain.ll" 2>/dev/null | head -6 | sed 's/^/    /'
  fi

  # 4. Arity in both directions, a bare application, and the colon-body limit.
  #    A cycle must be caught on the PATTERN path too: the depth guard in
  #    parse-type-from-node does not cover collect-pattern-tyvars, which reaches
  #    a defn parameter first and looped forever until it got its own.
  if refuses_p '(import-use vector)
(deftype (Vec T) (ref (Vector T)))
(defn f (v:(Vec i32 CStr)):i32 (return 0))' 'Vec: wrong number of type arguments for type alias (2 given)' \
     && refuses_p '(import-use hashmap)
(deftype (Table K V) (ref (HashMap K V)))
(defn f (m:(Table CStr)):i32 (return 0))' 'Table: wrong number of type arguments for type alias (1 given)' \
     && refuses_p '(import-use vector)
(deftype (Vec T) (ref (Vector T)))
(defn f (v:Vec):i32 (return 0))' "type alias 'Vec' takes 1 type arguments" \
     && refuses_p '(import-use node)
(deftype (Ref T) ref:T)
(defn f (v:(Ref (ref Node))):i32 (return 0))' 'must be a single token' \
     && refuses_p '(deftype (A T) (A T))
(defn f (v:(A i32)):i32 (return 0))' 'expands into a cycle' \
     && refuses_p '(deftype (A T) (B T))
(deftype (B T) (A T))
(defn f (v:(A i32)):i32 (return 0))' 'expands into a cycle'; then
    echo "PASS  s16-deftype-parametric-refusals"
  else
    echo "FAIL  s16-deftype-parametric-refusals"
    sed 's/^/    /' "$d/p.err" | head -3
  fi

  # 5. A parametric alias crosses a `.nuch` and a real object-file link: the
  #    header must carry the `deftype` itself, since the `declare` beside it
  #    spells its parameters in terms of the alias.
  cat > "$d/lib/plib.nuc" <<'EOF'
(import-use vector)
(import-use coll)
(deftype (Vec T) (ref (Vector T)))
(defn plen (v:(Vec i32)):i64 (return (as i64 (count v))))
EOF
  cat > "$d/use.nuc" <<EOF
(import-use "stdio.h")
(import-use vector)
(import-use coll)
(import-use "$d/lib/plib.nuch")
(defn main ():i32
  (with (v:(ref (Vector i32)) (alloca (Vector i32)))
    (vector-init v) (conj v 1) (conj v 2) (conj v 3)
    (printf "%ld\n" (plen v)))
  (return 0))
EOF
  ./build/nucleusc --emit-nuch "$d/lib/plib.nuc" > "$d/lib/plib.nuch" 2>"$d/nuch.err" || true
  ./build/nucleusc -c "$d/lib/plib.nuc" -o "$d/plib.o" 2>>"$d/nuch.err" || true
  ./build/nucleusc "$d/use.nuc" -o "$d/use.bin" --link-arg="$d/plib.o" 2>>"$d/nuch.err" || true
  out="$("$d/use.bin" 2>/dev/null || true)"
  if [ "$out" = "3" ] && qgrep -F '(deftype (Vec T) (ref (Vector T)))' "$d/lib/plib.nuch"; then
    echo "PASS  s16-deftype-parametric-nuch-roundtrip"
  else
    echo "FAIL  s16-deftype-parametric-nuch-roundtrip"
    sed 's/^/    /' "$d/nuch.err" | head -3; printf '%s\n' "$out" | sed 's/^/    got: /'
  fi

  # 6. The C header has no spelling for an alias, parametric or not, so it must
  #    show the expansion — asserted against the spelled-out program's header.
  cat > "$d/chA.nuc" <<'EOF'
(import-use vector)
(import-use coll)
(deftype (Vec T) (ref (Vector T)))
(defn plen (v:(Vec i32)):i64 (return (as i64 (count v))))
EOF
  cat > "$d/chB.nuc" <<'EOF'
(import-use vector)
(import-use coll)
(defn plen (v:(ref (Vector i32))):i64 (return (as i64 (count v))))
EOF
  for f in chA chB; do
    ./build/nucleusc --emit-cheader "$d/$f.nuc" 2>/dev/null | grep -v '^/\* Generated from' > "$d/$f.h" || true
  done
  if [ -s "$d/chA.h" ] && cmp -s "$d/chA.h" "$d/chB.h"; then
    echo "PASS  s16-deftype-parametric-cheader-expands"
  else
    echo "FAIL  s16-deftype-parametric-cheader-expands"
    diff "$d/chA.h" "$d/chB.h" 2>/dev/null | head -6 | sed 's/^/    /'
  fi

  # 7. The REPL's own form chain, as for the plain alias.
  out="$(printf '(deftype (Pair T) (ptr T))\n(defn takes (p:(Pair i32)):i32 (return (aref p 0)))\n(let (a:ptr:i32 (array i32 41 42)) (takes a))\n' \
         | ./build/nucleusc -i 2>&1 | tr -d '\n')"
  case "$out" in
    *41*) echo "PASS  s16-deftype-parametric-repl" ;;
    *)    echo "FAIL  s16-deftype-parametric-repl"
          printf '%s\n' "$out" | sed 's/^/    got: /' ;;
  esac

  rm -rf "$d"
}
spawn run_s16_parametric_aliases

# Stage 16 D9 (design/stage16-ergonomics/repl-libraries.md §3.3): a type is
# recoverable across modules only if it is queued or absorbed. The batch-visible
# half is a missing flush — `emit-compile-time` materialized `g-type-bufp` at its
# TOP and copied it into the CT module at assembly, so any type the CT body
# itself stamped was written to the stream after the buffer was last read and
# never reached the module. `compile-macro-body` has always re-drained; this is
# that same pair of lines.
run_s16_d9_ct_types() {
  local d n dup
  d="$(mktemp -d)"

  # 1. A `?i32` whose `%Maybe.i32` is stamped INSIDE the compile-time body.
  #    Pre-D9: `IR parse error: Cannot allocate unsized type %Maybe.i32`. This is
  #    a batch failure, not a REPL one — the design note framed it as REPL-only.
  cat > "$d/d9-ct-stamp.nuc" <<'EOF'
(import-use "stdio.h")
(compile-time
  (defn d9-ct-maybe (n:i32):?i32 (some n))
  (match (d9-ct-maybe 7)
    ((some v) (printf "d9 ct some %d\n" v))
    (none (printf "d9 ct none\n"))))
(defn main ():i32 (return 0))
EOF
  ./build/nucleusc --emit-llvm "$d/d9-ct-stamp.nuc" > "$d/d9-ct-stamp.ll" 2> "$d/ct.err" || true
  if qgrep -F 'd9 ct some 7' "$d/ct.err" && ! qgrep -F 'IR parse error' "$d/ct.err"; then
    echo "PASS  s16-d9-ct-body-stamp"
  else
    echo "FAIL  s16-d9-ct-body-stamp"
    sed 's/^/    got: /' "$d/ct.err" | head -4
  fi

  # 2. The drain that fixes (1) writes into the PROGRAM's type buffer, and the
  #    final drain runs over the same queue — so the line must arrive exactly
  #    once. A count, not a presence test: a double-emit is what a re-drain
  #    gets wrong, and LLVM rejects the module rather than picking one.
  n="$(grep -c '^%Maybe\.i32 = type' "$d/d9-ct-stamp.ll" 2>/dev/null || true)"
  if [ "$n" = "1" ]; then
    echo "PASS  s16-d9-ct-type-once"
  else
    echo "FAIL  s16-d9-ct-type-once"
    echo "    got: %Maybe.i32 defined $n times"
  fi

  # 3. `emit-defstruct` now queues every StructDef it writes, so the shared
  #    drain sees types whose line is already in the buffer. `sdef-in-module` is
  #    what keeps that inert; assert it by counting, over a program with several
  #    structs, that no type is defined twice.
  ./build/nucleusc --emit-llvm examples/struct.nuc > "$d/struct.ll" 2>/dev/null || true
  dup="$(grep -oE '^%[^ ]+ = type' "$d/struct.ll" | sort | uniq -d | head -3 || true)"
  if [ -s "$d/struct.ll" ] && [ -z "$dup" ]; then
    echo "PASS  s16-d9-no-duplicate-type-lines"
  else
    echo "FAIL  s16-d9-no-duplicate-type-lines"
    printf '%s\n' "$dup" | sed 's/^/    dup: /'
  fi

  # 4. The ruling: a `defstruct` inside a `compile-time` body defines a PROGRAM
  #    type, so its line goes to the module's own type buffer rather than the CT
  #    module's. Pre-D9 this exited **0** from `--emit-llvm` with three `%D9P`
  #    references and no `%D9P = type` line, and died only at `-o`. Three
  #    assertions in one, because each catches a different way to get it wrong:
  #    the count is 1 (0 = the old bug; 2 = written to both buffers), the binary
  #    links, and it computes. The CT module's own copy is checked by the absence
  #    of `IR parse error` — LLVM refuses a duplicate `%X = type` outright, so a
  #    module that parses contains the line exactly once.
  cat > "$d/d9-ct-struct.nuc" <<'EOF'
(import-use "stdio.h")
(compile-time (defstruct D9P x:i32 y:i32))
(defn d9-sum (a:i32 b:i32):i32
  (let (q:ptr:D9P (as ptr:D9P (alloca D9P)))
    (set! (q 'x) a) (set! (q 'y) b) (return (+ (q 'x) (q 'y)))))
(defn main ():i32 (printf "%d\n" (d9-sum 3 4)) (return 0))
EOF
  ./build/nucleusc --emit-llvm "$d/d9-ct-struct.nuc" > "$d/d9-ct-struct.ll" 2> "$d/cs.err" || true
  n="$(grep -c '^%D9P = type' "$d/d9-ct-struct.ll" 2>/dev/null || true)"
  ./build/nucleusc "$d/d9-ct-struct.nuc" -o "$d/d9-ct-struct.bin" >> "$d/cs.err" 2>&1 || true
  out="$("$d/d9-ct-struct.bin" 2>/dev/null || true)"
  if [ "$n" = "1" ] && [ "$out" = "7" ] && ! qgrep -F 'IR parse error' "$d/cs.err"; then
    echo "PASS  s16-d9-ct-defstruct-is-program-type"
  else
    echo "FAIL  s16-d9-ct-defstruct-is-program-type"
    echo "    got: %D9P = type x$n, ran '$out'"
    sed 's/^/    /' "$d/cs.err" | head -3
  fi

  # 5. D9 residue: the same type named in a SIGNATURE. This failed EARLIER than
  #    (4) — before any emission — because `prescan-struct-names` was a flat walk
  #    over the top-level form list and never descended into a `compile-time`
  #    body, so `prescan-defn-signatures` could not resolve the name. The
  #    by-value `defn` is placed BEFORE the block deliberately: it needs the
  #    LAYOUT, not just the name, and an unlaid-out struct is sized 0 rather than
  #    diagnosed (`define i32 @f(i0 %p.arg)`) — so the assertion is on the
  #    lowered parameter type as well as on the value.
  cat > "$d/d9-ct-sig.nuc" <<'EOF'
(import-use "stdio.h")
(defn d9-byval (p:D9V):i32 (return (+ (p 'x) (p 'y))))
(compile-time (defstruct D9V x:i32 y:i32))
(defn d9-byref (p:(ref D9V)):i32 (return (* (p 'x) (p 'y))))
(defn main ():i32
  (let (q:D9V (D9V 3 4))
    (printf "%d %d\n" (d9-byval q) (d9-byref (as ref:D9V (addr-of q)))))
  (return 0))
EOF
  ./build/nucleusc --emit-llvm "$d/d9-ct-sig.nuc" > "$d/d9-ct-sig.ll" 2> "$d/sig.err" || true
  ./build/nucleusc "$d/d9-ct-sig.nuc" -o "$d/d9-ct-sig.bin" >> "$d/sig.err" 2>&1 || true
  out="$("$d/d9-ct-sig.bin" 2>/dev/null || true)"
  if [ "$out" = "7 12" ] && qgrep -F 'define i32 @d9-byval(i64 ' "$d/d9-ct-sig.ll"; then
    echo "PASS  s16-d9-ct-type-in-signature"
  else
    echo "FAIL  s16-d9-ct-type-in-signature"
    echo "    got: ran '$out'"
    grep -E '^define i32 @d9-byval' "$d/d9-ct-sig.ll" | sed 's/^/    /' | head -1
    sed 's/^/    /' "$d/sig.err" | head -3
  fi

  # 6. The same, one level in: `emit-compile-time` runs its own defn-signature
  #    prescan BEFORE its body-form loop, so a `defn` in the block naming a
  #    `defstruct` in the same block hit the identical ordering.
  cat > "$d/d9-ct-inner.nuc" <<'EOF'
(import-use "stdio.h")
(compile-time
  (defstruct D9Q x:i32 y:i32)
  (defn d9-ct-sum (p:(ref D9Q)):i32 (return (+ (p 'x) (p 'y))))
  (let (q:ptr:D9Q (as ptr:D9Q (alloca D9Q)))
    (set! (q 'x) 5) (set! (q 'y) 6)
    (printf "d9 ct inner %d\n" (d9-ct-sum (as ref:D9Q q)))))
(defn main ():i32 (return 0))
EOF
  ./build/nucleusc --emit-llvm "$d/d9-ct-inner.nuc" > /dev/null 2> "$d/in.err" || true
  if qgrep -F 'd9 ct inner 11' "$d/in.err" && ! qgrep -F 'IR parse error' "$d/in.err"; then
    echo "PASS  s16-d9-ct-type-in-ct-signature"
  else
    echo "FAIL  s16-d9-ct-type-in-ct-signature"
    sed 's/^/    got: /' "$d/in.err" | head -3
  fi

  # 7. The descent mirrors `emit-compile-time`'s SKIPS, not just its walk. That
  #    loop has an arm for `defstruct` and for nothing else this prescan
  #    registers, so a name it would never define must stay UNKNOWN — registering
  #    one resolves the signature, writes no `%Name = type` line, and exits 0 on
  #    invalid IR, which is strictly worse than the diagnostic. Each of these is
  #    already rejected as an unknown call inside the block; the assertion is
  #    that the SIGNATURE is refused too.
  local skipped=0 head_kw
  for head_kw in 'defstruct- D9K x:i32' 'defunion D9K (a x:i32) (b)' 'deftype D9K i32'; do
    cat > "$d/d9-skip.nuc" <<EOF
(compile-time ($head_kw))
(defn d9-skip (p:(ref D9K)):i32 (return 0))
(defn main ():i32 (return 0))
EOF
    ./build/nucleusc --emit-llvm "$d/d9-skip.nuc" > /dev/null 2> "$d/skip.err" || true
    qgrep -F 'unknown type: D9K' "$d/skip.err" || skipped=1
  done
  cat > "$d/d9-skip.nuc" <<'EOF'
(compile-time (compile-time (defstruct D9K x:i32)))
(defn d9-skip (p:(ref D9K)):i32 (return 0))
(defn main ():i32 (return 0))
EOF
  ./build/nucleusc --emit-llvm "$d/d9-skip.nuc" > /dev/null 2> "$d/skip.err" || true
  qgrep -F 'unknown type: D9K' "$d/skip.err" || skipped=1
  if [ "$skipped" = "0" ]; then
    echo "PASS  s16-d9-ct-descent-mirrors-skips"
  else
    echo "FAIL  s16-d9-ct-descent-mirrors-skips"
    sed 's/^/    got: /' "$d/skip.err" | head -3
  fi

  rm -rf "$d"
}
spawn run_s16_d9_ct_types


# ==============================================================================
# Stage 16 L1-L5 — what a C header import loses
# (design/stage16-ergonomics/c-header-layout.md §5)
#
# The standard 186-module IR sweep is structurally blind here: the whole tree
# imports six C headers, between them exposing 14 of the 65 comparable struct
# types the §1.5 survey measured. A change that broke signal.h, pthread.h or
# netinet/in.h outright would sweep clean. Every unit below therefore imports
# headers (or fixtures) the tree does not, and asserts the *emitted layout* —
# never "it compiled". Every wrong row in §1.5 compiles fine today.
# ==============================================================================

# L1 (§1.3/§3.1): a struct member whose type `c-parse-type` could not represent
# makes the struct OPAQUE, not `ptr`. The point is that failure is SAFE — a
# located error and no `%X = type` line — because the pre-L1 behaviour was a
# silently wrong layout that compiled, linked and ran.
run_l1_member_opaque() {
  local d bad name line got
  d="$(mktemp -d)"
  bad=0

  # 1. Each of the five raise sites in `c-parse-type`, driven through a struct
  #    MEMBER (the position L1 added), must name this fixture and the enclosing
  #    struct's own line. `sizeof` on an opaque type is fatal, so one per compile.
  while IFS='|' read -r name line; do
    [ -z "$name" ] && continue
    printf '(import-use "stdio.h")\n(import-use "tests/fixtures/l1-members.h")\n(defn main ():i32 (printf "%%ld\\n" (sizeof %s)) (return 0))\n' \
      "$name" > "$d/p.nuc"
    ./build/nucleusc --emit-llvm "$d/p.nuc" >/dev/null 2>"$d/p.err" || true
    if ! qgrep -E "'$name' is an opaque type declared at [^ ]*tests/fixtures/l1-members\.h:$line;" "$d/p.err"; then
      echo "FAIL  l1-member-opaque ($name: expected a located error at l1-members.h:$line)"
      sed 's/^/    got: /' "$d/p.err" | head -2
      bad=1
    fi
  done <<'EOF'
l1_m_wide_int|27
l1_m_unrep_typedef|33
l1_m_opaque_tag|37
l1_m_unknown_tag|40
l1_m_bad_body|46
EOF
  [ "$bad" = 0 ] && echo "PASS  l1-member-opaque"

  # 2. The safe half. Importing the header and using all five ONLY behind a
  #    pointer must be silent, must emit no `%X = type` line for any of them
  #    (an aggregate LLVM type with a guessed body is exactly what L1 removes),
  #    and must produce IR that PARSES — `--emit-llvm` never reads back what it
  #    writes, so exit 0 proves nothing about validity.
  cat > "$d/safe.nuc" <<'EOF'
(import-use "stdio.h")
(import-use "tests/fixtures/l1-members.h")
(defn t1 (p:ptr:l1_m_wide_int):i32 (return 0))
(defn t2 (p:ptr:l1_m_unrep_typedef):i32 (return 0))
(defn t3 (p:ptr:l1_m_opaque_tag):i32 (return 0))
(defn t4 (p:ptr:l1_m_unknown_tag):i32 (return 0))
(defn t5 (p:ptr:l1_m_bad_body):i32 (return 0))
(defn main ():i32 (return 0))
EOF
  ./build/nucleusc --emit-llvm "$d/safe.nuc" > "$d/safe.ll" 2>"$d/safe.err" || true
  bad=0
  if [ -s "$d/safe.err" ]; then
    echo "FAIL  l1-member-fails-safe (import of an opaque-membered header is not silent)"
    sed 's/^/    got: /' "$d/safe.err" | head -3
    bad=1
  fi
  for name in l1_m_wide_int l1_m_unrep_typedef l1_m_opaque_tag l1_m_unknown_tag l1_m_bad_body; do
    if qgrep -E "^%$name = type" "$d/safe.ll"; then
      echo "FAIL  l1-member-fails-safe ($name got an LLVM layout it has no basis for)"
      { grep -E "^%$name = type" "$d/safe.ll" || true; } | sed 's/^/    got: /'
      bad=1
    fi
  done
  # An opaque type behind a pointer stays usable: this is the "fails safe, not
  # unusable" half, and the reason `ptr:FILE` still works.
  for n in 1 2 3 4 5; do
    if ! qgrep -E "^define i32 @t$n\(ptr " "$d/safe.ll"; then
      echo "FAIL  l1-member-fails-safe (t$n: a pointer to an opaque C type was refused)"
      bad=1
    fi
  done
  if ! llvm-as "$d/safe.ll" -o /dev/null 2>/dev/null; then
    echo "FAIL  l1-member-fails-safe (emitted IR does not parse)"
    bad=1
  fi
  [ "$bad" = 0 ] && echo "PASS  l1-member-fails-safe"

  # 3. The positive controls, so a future "fix" cannot pass (1) and (2) by
  #    making every C struct opaque. `l1_ok_hidden_array` is the row §1.2
  #    measured as the SILENT-wrong case and the §5 gate table still describes
  #    as opaque: L2 gave `c-typedef-record` a real `(array T N)` to store, so
  #    it is now representable and must carry the extent.
  ./build/nucleusc --emit-llvm "$d/safe.nuc" 2>/dev/null > "$d/ctl.ll" || true
  bad=0
  while IFS='|' read -r name got; do
    [ -z "$name" ] && continue
    if ! qgrep -F -x "$got" "$d/ctl.ll"; then
      echo "FAIL  l1-member-controls ($name)"
      echo "    expected: $got"
      { grep -E "^%$name = type" "$d/ctl.ll" || true; } | sed 's/^/    got:      /'
      bad=1
    fi
  done <<'EOF'
l1_ok_plain|%l1_ok_plain = type { i32, i32 }
l1_ok_hidden_array|%l1_ok_hidden_array = type { [4 x i32], i32 }
EOF
  [ "$bad" = 0 ] && echo "PASS  l1-member-controls"

  rm -rf "$d"
}
spawn run_l1_member_opaque

# L2 (§1.5/§3.2): the array-extent matrix. `tests/fixtures/l2-arrays.h` states
# the expected layout for every row; this asserts the exact `%X = type` line and
# `(sizeof X)` against it, and cross-checks the sizes against clang compiled from
# the SAME header. Asserting the emitted layout rather than the exit code is the
# whole point of the gate.
run_l2_layout_matrix() {
  local d bad name want line
  d="$(mktemp -d)"

  cat > "$d/m.nuc" <<'EOF'
(import-use "stdio.h")
(import-use "tests/fixtures/l2-arrays.h")
(defn main ():i32
  (printf "l2_lit %lld\n" (as i64 (sizeof l2_lit)))
  (printf "l2_multi %lld\n" (as i64 (sizeof l2_multi)))
  (printf "l2_macro %lld\n" (as i64 (sizeof l2_macro)))
  (printf "l2_sizeof %lld\n" (as i64 (sizeof l2_sizeof)))
  (printf "l2_shift %lld\n" (as i64 (sizeof l2_shift)))
  (printf "l2_chararr %lld\n" (as i64 (sizeof l2_chararr)))
  (return 0))
EOF
  ./build/nucleusc --emit-llvm "$d/m.nuc" > "$d/m.ll" 2>"$d/m.err" || true

  # 1. The exact type line for every foldable row. `int`/`short`/`char`
  #    throughout, so these hold on any target with a 4-byte int.
  bad=0
  if [ -s "$d/m.err" ]; then
    echo "FAIL  l2-layout-types (import produced diagnostics)"
    sed 's/^/    got: /' "$d/m.err" | head -3
    bad=1
  fi
  while IFS='|' read -r name want; do
    [ -z "$name" ] && continue
    if ! qgrep -F -x "$want" "$d/m.ll"; then
      echo "FAIL  l2-layout-types ($name)"
      echo "    expected: $want"
      { grep -E "^%$name = type" "$d/m.ll" || true; } | sed 's/^/    got:      /'
      bad=1
    fi
  done <<'EOF'
l2_lit|%l2_lit = type { [4 x i32], i32 }
l2_multi|%l2_multi = type { [2 x [3 x i32]], i32 }
l2_macro|%l2_macro = type { [6 x i8], i32 }
l2_sizeof|%l2_sizeof = type { [24 x i8], i32 }
l2_shift|%l2_shift = type { [8 x i8], i16 }
l2_chararr|%l2_chararr = type { i16, [14 x i8] }
EOF
  if ! llvm-as "$d/m.ll" -o /dev/null 2>/dev/null; then
    echo "FAIL  l2-layout-types (emitted IR does not parse)"
    bad=1
  fi
  [ "$bad" = 0 ] && echo "PASS  l2-layout-types"

  # 2. `sizeof` against the value the fixture states — and against clang built
  #    from the same header, so the numbers are checked and not merely restated.
  bad=0
  ./build/nucleusc "$d/m.nuc" -o "$d/m.bin" 2>>"$d/m.err" || true
  if [ ! -x "$d/m.bin" ]; then
    echo "FAIL  l2-layout-sizeof (compile/link failed)"
    sed 's/^/    /' "$d/m.err" | head -3
    bad=1
  else
    "$d/m.bin" > "$d/m.out" 2>&1 || true
    cat > "$d/want.out" <<'EOF'
l2_lit 20
l2_multi 28
l2_macro 12
l2_sizeof 28
l2_shift 10
l2_chararr 16
EOF
    if ! diff -u "$d/want.out" "$d/m.out" > "$d/sz.diff" 2>&1; then
      echo "FAIL  l2-layout-sizeof (against the sizes tests/fixtures/l2-arrays.h states)"
      sed 's/^/    /' "$d/sz.diff" | head -12
      bad=1
    fi
    if command -v cc >/dev/null 2>&1; then
      cat > "$d/m.c" <<'EOF'
#include <stdio.h>
#include "tests/fixtures/l2-arrays.h"
int main(void){
  printf("l2_lit %zu\n", sizeof(struct l2_lit));
  printf("l2_multi %zu\n", sizeof(struct l2_multi));
  printf("l2_macro %zu\n", sizeof(struct l2_macro));
  printf("l2_sizeof %zu\n", sizeof(struct l2_sizeof));
  printf("l2_shift %zu\n", sizeof(struct l2_shift));
  printf("l2_chararr %zu\n", sizeof(struct l2_chararr));
  return 0;
}
EOF
      if cc -I. "$d/m.c" -o "$d/m.coracle" 2>"$d/cc.err"; then
        "$d/m.coracle" > "$d/c.out" 2>&1 || true
        if ! diff -u "$d/c.out" "$d/m.out" > "$d/cc.diff" 2>&1; then
          echo "FAIL  l2-layout-sizeof (Nucleus disagrees with clang on the same header)"
          sed 's/^/    /' "$d/cc.diff" | head -12
          bad=1
        fi
      fi
    fi
  fi
  [ "$bad" = 0 ] && echo "PASS  l2-layout-sizeof"

  # 3. An extent the evaluator cannot fold abandons the struct and leaves the
  #    name OPAQUE (L1), rather than guessing a count. Two shapes: a name (an
  #    enum constant — the evaluator resolves no names) and a zero extent. `[]`
  #    used to be a third; Stage 16 C1a made it a flexible array member, which
  #    is checked positively below instead.
  bad=0
  while IFS='|' read -r name line; do
    [ -z "$name" ] && continue
    printf '(import-use "stdio.h")\n(import-use "tests/fixtures/l2-arrays.h")\n(defn main ():i32 (printf "%%ld\\n" (sizeof %s)) (return 0))\n' \
      "$name" > "$d/u.nuc"
    ./build/nucleusc --emit-llvm "$d/u.nuc" > "$d/u.ll" 2>"$d/u.err" || true
    if ! qgrep -E "'$name' is an opaque type declared at [^ ]*tests/fixtures/l2-arrays\.h:$line;" "$d/u.err"; then
      echo "FAIL  l2-layout-unfoldable ($name: expected a located error at l2-arrays.h:$line)"
      sed 's/^/    got: /' "$d/u.err" | head -2
      bad=1
    fi
    if qgrep -E "^%$name = type" "$d/u.ll"; then
      echo "FAIL  l2-layout-unfoldable ($name got a layout from an extent that does not fold)"
      bad=1
    fi
  done <<'EOF'
l2_unfoldable_enum|56
l2_unfoldable_zero|62
EOF
  [ "$bad" = 0 ] && echo "PASS  l2-layout-unfoldable"

  # 3b. Stage 16 C1a: `int f[];` is C99's flexible array member — a trailing
  #     member that contributes no bytes. It must lay out, size like clang's,
  #     and print `[0 x …]` rather than reuse the prescan's provisional 0.
  bad=0
  printf '(import-use "stdio.h")\n(import-use "tests/fixtures/l2-arrays.h")\n(defn main ():i32 (printf "%%ld\\n" (sizeof l2_unfoldable_flex)) (return 0))\n' \
    > "$d/fx.nuc"
  ./build/nucleusc --emit-llvm "$d/fx.nuc" > "$d/fx.ll" 2>"$d/fx.err" || bad=1
  qgrep -E '^%l2_unfoldable_flex = type \{ i32, \[0 x i32\] \}' "$d/fx.ll" || bad=1
  ./build/nucleusc "$d/fx.nuc" -o "$d/fx" 2>>"$d/fx.err" || bad=1
  [ "$bad" = 0 ] && "$d/fx" > "$d/fx.out" 2>&1
  cat > "$d/fx.c" <<'EOF'
#include <stdio.h>
#include "tests/fixtures/l2-arrays.h"
int main(void){ printf("%zu\n", sizeof(struct l2_unfoldable_flex)); return 0; }
EOF
  if cc -I. "$d/fx.c" -o "$d/fx.coracle" 2>/dev/null; then
    "$d/fx.coracle" > "$d/fx.cout" 2>&1
    diff "$d/fx.cout" "$d/fx.out" >/dev/null 2>&1 || bad=1
  fi
  if [ "$bad" = 0 ]; then echo "PASS  l2-layout-flex-array"; else
    echo "FAIL  l2-layout-flex-array"
    sed 's/^/    /' "$d/fx.err" 2>/dev/null | head -4
    grep -E '^%l2_unfoldable_flex' "$d/fx.ll" | sed 's/^/    got: /' | head -2
  fi

  rm -rf "$d"
}
spawn run_l2_layout_matrix

# L2 (§1.5): the survey as a test — the roster of real libc types the §1.5 table
# names, compared against a C program compiled in the SAME harness run.
#
# Never against a hardcoded number: these are glibc-version- and
# target-dependent, and a hardcoded 200 becomes a false failure on the first musl
# or 32-bit run. The oracle is also the SKIP gate — if it does not compile, a
# header (or a glibc-specific spelling) is absent and the unit skips cleanly.
#
# Field OFFSETS and ALIGNMENT, not just `sizeof` totals: L1 measured
# `SDL_HapticConstant` at 40 bytes under both clang and the broken importer while
# every field offset after the first was wrong. A size-only oracle calls that OK.
run_l2_libc_layouts() {
  local d bad name file line
  d="$(mktemp -d)"

  if ! command -v cc >/dev/null 2>&1; then
    echo "PASS  l2-libc-layouts (SKIP: no cc to build the oracle against)"
    echo "PASS  l2-libc-opaque (SKIP: no cc to build the oracle against)"
    rm -rf "$d"
    return 0
  fi

  cat > "$d/o.c" <<'EOF'
#include <stddef.h>
#include <stdio.h>
#include <setjmp.h>
#include <time.h>
#include <sys/stat.h>
#include <dirent.h>
#include <termios.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <signal.h>
#include <pthread.h>
/* Referenced so a libc that does not spell these fails the ORACLE build and the
   unit SKIPs, rather than the Nucleus side failing alone against a libc whose
   types simply have other names. */
static const size_t glibc_spellings[] = { sizeof(struct __jmp_buf_tag), sizeof(__sigset_t) };
int main(void){
  (void)glibc_spellings;
  printf("__jmp_buf_tag size=%zu align=%zu __jmpbuf=%zu __mask_was_saved=%zu __saved_mask=%zu\n",
    sizeof(struct __jmp_buf_tag), _Alignof(struct __jmp_buf_tag),
    offsetof(struct __jmp_buf_tag, __jmpbuf), offsetof(struct __jmp_buf_tag, __mask_was_saved),
    offsetof(struct __jmp_buf_tag, __saved_mask));
  printf("timespec size=%zu align=%zu tv_sec=%zu tv_nsec=%zu\n",
    sizeof(struct timespec), _Alignof(struct timespec),
    offsetof(struct timespec, tv_sec), offsetof(struct timespec, tv_nsec));
  printf("itimerspec size=%zu align=%zu it_interval=%zu it_value=%zu\n",
    sizeof(struct itimerspec), _Alignof(struct itimerspec),
    offsetof(struct itimerspec, it_interval), offsetof(struct itimerspec, it_value));
  printf("stat size=%zu align=%zu st_dev=%zu st_ino=%zu st_mode=%zu st_uid=%zu st_size=%zu st_mtim=%zu\n",
    sizeof(struct stat), _Alignof(struct stat),
    offsetof(struct stat, st_dev), offsetof(struct stat, st_ino), offsetof(struct stat, st_mode),
    offsetof(struct stat, st_uid), offsetof(struct stat, st_size), offsetof(struct stat, st_mtim));
  printf("dirent size=%zu align=%zu d_ino=%zu d_off=%zu d_reclen=%zu d_type=%zu d_name=%zu\n",
    sizeof(struct dirent), _Alignof(struct dirent),
    offsetof(struct dirent, d_ino), offsetof(struct dirent, d_off), offsetof(struct dirent, d_reclen),
    offsetof(struct dirent, d_type), offsetof(struct dirent, d_name));
  printf("termios size=%zu align=%zu c_iflag=%zu c_oflag=%zu c_cflag=%zu c_lflag=%zu c_line=%zu c_cc=%zu c_ispeed=%zu c_ospeed=%zu\n",
    sizeof(struct termios), _Alignof(struct termios),
    offsetof(struct termios, c_iflag), offsetof(struct termios, c_oflag), offsetof(struct termios, c_cflag),
    offsetof(struct termios, c_lflag), offsetof(struct termios, c_line), offsetof(struct termios, c_cc),
    offsetof(struct termios, c_ispeed), offsetof(struct termios, c_ospeed));
  printf("fd_set size=%zu align=%zu\n", sizeof(fd_set), _Alignof(fd_set));
  printf("sockaddr size=%zu align=%zu sa_family=%zu sa_data=%zu\n",
    sizeof(struct sockaddr), _Alignof(struct sockaddr),
    offsetof(struct sockaddr, sa_family), offsetof(struct sockaddr, sa_data));
  printf("in6_addr size=%zu align=%zu __in6_u=%zu\n",
    sizeof(struct in6_addr), _Alignof(struct in6_addr), offsetof(struct in6_addr, __in6_u));
  printf("sigset_t size=%zu align=%zu\n", sizeof(sigset_t), _Alignof(sigset_t));
  printf("pthread_mutex_t size=%zu align=%zu\n", sizeof(pthread_mutex_t), _Alignof(pthread_mutex_t));
  /* Stage 16 FP-4: both were opaque until the importer built a real type for
     their inline function-pointer members. */
  printf("sigaction size=%zu align=%zu sa_mask=%zu sa_flags=%zu sa_restorer=%zu\n",
    sizeof(struct sigaction), _Alignof(struct sigaction),
    offsetof(struct sigaction, sa_mask), offsetof(struct sigaction, sa_flags),
    offsetof(struct sigaction, sa_restorer));
  printf("sigevent_t size=%zu align=%zu sigev_signo=%zu sigev_notify=%zu\n",
    sizeof(sigevent_t), _Alignof(sigevent_t),
    offsetof(sigevent_t, sigev_signo), offsetof(sigevent_t, sigev_notify));
  return 0;
}
EOF
  if ! cc "$d/o.c" -o "$d/o.bin" 2>"$d/o.err"; then
    echo "PASS  l2-libc-layouts (SKIP: the C oracle does not build — a header or a glibc spelling is absent)"
    echo "PASS  l2-libc-opaque (SKIP: the C oracle does not build — a header or a glibc spelling is absent)"
    rm -rf "$d"
    return 0
  fi
  "$d/o.bin" > "$d/c.out" 2>&1 || true

  # `sizeof T` alone would not see a wrong offset, so every type with reachable
  # members prints all of them. Alignment is read off a probe struct — Nucleus
  # has no `alignof`, and `offsetof(struct {i8; T;}, v)` IS the alignment.
  #
  # `sigset_t` is `typedef __sigset_t sigset_t;`, a typedef of a typedef, and its
  # alignment probe names `__sigset_t`: the L5 typedef table is consulted in
  # value positions but a `defstruct` FIELD type is resolved by the prescan,
  # where every C struct is still opaque, so `v:sigset_t` there is refused. The
  # size below is still `(sizeof sigset_t)` — the subject under test.
  cat > "$d/l.nuc" <<'EOF'
(import-use "stdio.h")
(import-use "setjmp.h")
(import-use "time.h")
(import-use "sys/stat.h")
(import-use "dirent.h")
(import-use "termios.h")
(import-use "sys/select.h")
(import-use "sys/socket.h")
(import-use "netinet/in.h")
(import-use "signal.h")
(import-use "pthread.h")

(defstruct AP1 pad:i8 v:__jmp_buf_tag)
(defstruct AP2 pad:i8 v:timespec)
(defstruct AP3 pad:i8 v:itimerspec)
(defstruct AP4 pad:i8 v:stat)
(defstruct AP5 pad:i8 v:dirent)
(defstruct AP6 pad:i8 v:termios)
(defstruct AP7 pad:i8 v:fd_set)
(defstruct AP8 pad:i8 v:sockaddr)
(defstruct AP9 pad:i8 v:in6_addr)
(defstruct AP10 pad:i8 v:__sigset_t)
(defstruct AP11 pad:i8 v:pthread_mutex_t)
(defstruct AP12 pad:i8 v:sigaction)
(defstruct AP13 pad:i8 v:sigevent_t)

(defn off (base:ptr fld:ptr):i64 (return (- (unsafe/cast i64 fld) (unsafe/cast i64 base))))

(defn main ():i32
  (let (s:ptr:__jmp_buf_tag (alloca __jmp_buf_tag) a:ptr:AP1 (alloca AP1))
    (printf "__jmp_buf_tag size=%lld align=%lld __jmpbuf=%lld __mask_was_saved=%lld __saved_mask=%lld\n"
      (as i64 (sizeof __jmp_buf_tag)) (off a (addr-of a 'v))
      (off s (addr-of s '__jmpbuf)) (off s (addr-of s '__mask_was_saved)) (off s (addr-of s '__saved_mask))))
  (let (s:ptr:timespec (alloca timespec) a:ptr:AP2 (alloca AP2))
    (printf "timespec size=%lld align=%lld tv_sec=%lld tv_nsec=%lld\n"
      (as i64 (sizeof timespec)) (off a (addr-of a 'v)) (off s (addr-of s 'tv_sec)) (off s (addr-of s 'tv_nsec))))
  (let (s:ptr:itimerspec (alloca itimerspec) a:ptr:AP3 (alloca AP3))
    (printf "itimerspec size=%lld align=%lld it_interval=%lld it_value=%lld\n"
      (as i64 (sizeof itimerspec)) (off a (addr-of a 'v)) (off s (addr-of s 'it_interval)) (off s (addr-of s 'it_value))))
  (let (s:ptr:stat (alloca stat) a:ptr:AP4 (alloca AP4))
    (printf "stat size=%lld align=%lld st_dev=%lld st_ino=%lld st_mode=%lld st_uid=%lld st_size=%lld st_mtim=%lld\n"
      (as i64 (sizeof stat)) (off a (addr-of a 'v)) (off s (addr-of s 'st_dev)) (off s (addr-of s 'st_ino))
      (off s (addr-of s 'st_mode)) (off s (addr-of s 'st_uid)) (off s (addr-of s 'st_size)) (off s (addr-of s 'st_mtim))))
  (let (s:ptr:dirent (alloca dirent) a:ptr:AP5 (alloca AP5))
    (printf "dirent size=%lld align=%lld d_ino=%lld d_off=%lld d_reclen=%lld d_type=%lld d_name=%lld\n"
      (as i64 (sizeof dirent)) (off a (addr-of a 'v)) (off s (addr-of s 'd_ino)) (off s (addr-of s 'd_off))
      (off s (addr-of s 'd_reclen)) (off s (addr-of s 'd_type)) (off s (addr-of s 'd_name))))
  (let (s:ptr:termios (alloca termios) a:ptr:AP6 (alloca AP6))
    (printf "termios size=%lld align=%lld c_iflag=%lld c_oflag=%lld c_cflag=%lld c_lflag=%lld c_line=%lld c_cc=%lld c_ispeed=%lld c_ospeed=%lld\n"
      (as i64 (sizeof termios)) (off a (addr-of a 'v)) (off s (addr-of s 'c_iflag)) (off s (addr-of s 'c_oflag))
      (off s (addr-of s 'c_cflag)) (off s (addr-of s 'c_lflag)) (off s (addr-of s 'c_line)) (off s (addr-of s 'c_cc))
      (off s (addr-of s 'c_ispeed)) (off s (addr-of s 'c_ospeed))))
  (let (a:ptr:AP7 (alloca AP7))
    (printf "fd_set size=%lld align=%lld\n" (as i64 (sizeof fd_set)) (off a (addr-of a 'v))))
  (let (s:ptr:sockaddr (alloca sockaddr) a:ptr:AP8 (alloca AP8))
    (printf "sockaddr size=%lld align=%lld sa_family=%lld sa_data=%lld\n"
      (as i64 (sizeof sockaddr)) (off a (addr-of a 'v)) (off s (addr-of s 'sa_family)) (off s (addr-of s 'sa_data))))
  (let (s:ptr:in6_addr (alloca in6_addr) a:ptr:AP9 (alloca AP9))
    (printf "in6_addr size=%lld align=%lld __in6_u=%lld\n"
      (as i64 (sizeof in6_addr)) (off a (addr-of a 'v)) (off s (addr-of s '__in6_u))))
  (let (a:ptr:AP10 (alloca AP10))
    (printf "sigset_t size=%lld align=%lld\n" (as i64 (sizeof sigset_t)) (off a (addr-of a 'v))))
  (let (a:ptr:AP11 (alloca AP11))
    (printf "pthread_mutex_t size=%lld align=%lld\n" (as i64 (sizeof pthread_mutex_t)) (off a (addr-of a 'v))))
  (let (s:ptr:sigaction (alloca sigaction) a:ptr:AP12 (alloca AP12))
    (printf "sigaction size=%lld align=%lld sa_mask=%lld sa_flags=%lld sa_restorer=%lld\n"
      (as i64 (sizeof sigaction)) (off a (addr-of a 'v)) (off s (addr-of s 'sa_mask))
      (off s (addr-of s 'sa_flags)) (off s (addr-of s 'sa_restorer))))
  (let (s:ptr:sigevent_t (alloca sigevent_t) a:ptr:AP13 (alloca AP13))
    (printf "sigevent_t size=%lld align=%lld sigev_signo=%lld sigev_notify=%lld\n"
      (as i64 (sizeof sigevent_t)) (off a (addr-of a 'v)) (off s (addr-of s 'sigev_signo))
      (off s (addr-of s 'sigev_notify))))
  (return 0))
EOF
  bad=0
  ./build/nucleusc "$d/l.nuc" -o "$d/l.bin" 2>"$d/l.err" || true
  if [ ! -x "$d/l.bin" ]; then
    echo "FAIL  l2-libc-layouts (compile/link failed)"
    sed 's/^/    /' "$d/l.err" | head -5
    bad=1
  else
    "$d/l.bin" > "$d/n.out" 2>&1 || true
    if ! diff -u "$d/c.out" "$d/n.out" > "$d/l.diff" 2>&1; then
      echo "FAIL  l2-libc-layouts (Nucleus disagrees with clang on size, offset or alignment)"
      sed 's/^/    /' "$d/l.diff" | head -20
      bad=1
    fi
  fi
  [ "$bad" = 0 ] && echo "PASS  l2-libc-layouts"

  # `FILE` was the last of §1.5's rows still opaque after L1/L2, and it was
  # opaque for one reason — `int _flags2:24`. BF-4 gave that a real layout, so
  # the assertion flips from "still fails safe" to "agrees with cc", which is
  # the only claim worth making about the type stdio hands every program.
  bad=0
  if command -v cc >/dev/null 2>&1; then
    printf '#include <stdio.h>\n#include <stddef.h>\nint main(void){printf("%%zu %%zu %%zu\\n",sizeof(FILE),offsetof(FILE,_flags),offsetof(FILE,_lock));return 0;}\n' > "$d/f.c"
    cat > "$d/f.nuc" <<'NUCEOF'
(import-use "stdio.h")
(defn main ():i32
  (let (f:ptr:FILE (alloca FILE))
    (printf "%ld %ld %ld\n" (sizeof FILE)
      (- (unsafe/cast i64 (addr-of f '_flags)) (unsafe/cast i64 f))
      (- (unsafe/cast i64 (addr-of f '_lock)) (unsafe/cast i64 f))))
  (return 0))
NUCEOF
    cc -w "$d/f.c" -o "$d/f.cbin" 2>/dev/null || bad=1
    ./build/nucleusc "$d/f.nuc" -o "$d/f.bin" 2>"$d/f.err" || bad=1
    if [ "$bad" = 0 ] && [ "$("$d/f.bin")" = "$("$d/f.cbin")" ]; then
      echo "PASS  l2-libc-file-layout ($("$d/f.bin"), matching cc)"
    else
      echo "FAIL  l2-libc-file-layout"
      sed 's/^/    /' "$d/f.err" | head -3
      [ -x "$d/f.cbin" ] && echo "    cc:      $("$d/f.cbin")"
      [ -x "$d/f.bin" ] && echo "    nucleus: $("$d/f.bin")"
    fi
  else
    echo "PASS  l2-libc-file-layout (SKIP: no cc)"
  fi

  rm -rf "$d"
}
spawn run_l2_libc_layouts

# L3 (§1.4/§3.3): an array typedef decays to a pointer in parameter position, as
# it does in C. `jmp_buf` is `typedef struct __jmp_buf_tag jmp_buf[1];`, so
# before L3 `setjmp` and `siglongjmp` had the wrong CALLING CONVENTION — passed
# `byval(%jmp_buf)` where C passes one word — independently of the wrong size.
run_l3_decay() {
  local d bad want got
  d="$(mktemp -d)"

  printf '(import-use "setjmp.h")\n(defn main ():i32 (return 0))\n' > "$d/sj.nuc"
  ./build/nucleusc --emit-llvm "$d/sj.nuc" > "$d/sj.ll" 2>"$d/sj.err" || true

  bad=0
  if [ -s "$d/sj.err" ]; then
    echo "FAIL  l3-setjmp-decay (importing setjmp.h is not silent)"
    sed 's/^/    got: /' "$d/sj.err" | head -3
    bad=1
  fi
  # The declare lines, textually. `setjmp` and `__sigsetjmp` carry L4's
  # `returns_twice`; `longjmp`/`siglongjmp` carry `noreturn` from the hardcoded
  # list at src/cheader.nuc:23-26. `_longjmp` is on neither list, which is the
  # tell that the attribute comes from a roster and not from the spelling.
  while IFS='|' read -r want; do
    [ -z "$want" ] && continue
    if ! qgrep -F -x "$want" "$d/sj.ll"; then
      echo "FAIL  l3-setjmp-decay"
      echo "    expected: $want"
      { grep -F "@${want##*@}" "$d/sj.ll" || true; } | sed 's/^/    got:      /' | head -2
      bad=1
    fi
  done <<'EOF'
declare i32 @setjmp(ptr) returns_twice
declare i32 @__sigsetjmp(ptr, i32) returns_twice
declare i32 @_setjmp(ptr) returns_twice
declare void @longjmp(ptr, i32) noreturn
declare void @_longjmp(ptr, i32)
declare void @siglongjmp(ptr, i32) noreturn
EOF
  # Not one `byval` anywhere in the whole import: a 200-byte `byval(%jmp_buf)`
  # is a *correct layout* passed by the wrong convention, which no layout gate
  # would catch.
  if qgrep -F 'byval' "$d/sj.ll"; then
    echo "FAIL  l3-setjmp-decay (byval survives somewhere in the setjmp.h import)"
    { grep -n 'byval' "$d/sj.ll" || true; } | sed 's/^/    got: /' | head -3
    bad=1
  fi
  if ! llvm-as "$d/sj.ll" -o /dev/null 2>/dev/null; then
    echo "FAIL  l3-setjmp-decay (emitted IR does not parse)"
    bad=1
  fi
  [ "$bad" = 0 ] && echo "PASS  l3-setjmp-decay"

  # The negative: the pre-existing SYNTACTIC decay path
  # (`c-parse-func-decl:810-823`, which consumes `[N]` after a parameter NAME)
  # must be undisturbed. `utimensat`'s `const struct timespec times[2]` is the
  # case that forced it, and it is named in that code's own comment.
  bad=0
  printf '(import-use "sys/stat.h")\n(defn main ():i32 (return 0))\n' > "$d/ut.nuc"
  ./build/nucleusc --emit-llvm "$d/ut.nuc" > "$d/ut.ll" 2>/dev/null || true
  while IFS='|' read -r want; do
    [ -z "$want" ] && continue
    if ! qgrep -F -x "$want" "$d/ut.ll"; then
      echo "FAIL  l3-syntactic-decay"
      echo "    expected: $want"
      { grep -F "@${want##*@}" "$d/ut.ll" || true; } | sed 's/^/    got:      /' | head -2
      bad=1
    fi
  done <<'EOF'
declare i32 @utimensat(i32, ptr, ptr, i32)
declare i32 @futimens(i32, ptr)
EOF
  [ "$bad" = 0 ] && echo "PASS  l3-syntactic-decay"

  rm -rf "$d"
}
spawn run_l3_decay

# L4 (§3.4): `returns_twice`. Without it a `setjmp` call is indistinguishable
# from any other call to the optimizer, which may tail-call it and destroy the
# very frame the jump has to return into. Before L4 the compiler emitted no
# function attribute anywhere except `noreturn`.
run_l4_returns_twice() {
  local d bad want got
  d="$(mktemp -d)"

  bad=0
  printf '(import-use "setjmp.h")\n(defn main ():i32 (return 0))\n' > "$d/sj.nuc"
  ./build/nucleusc --emit-llvm "$d/sj.nuc" > "$d/sj.ll" 2>/dev/null || true
  for want in 'declare i32 @setjmp(ptr) returns_twice' \
              'declare i32 @__sigsetjmp(ptr, i32) returns_twice' \
              'declare i32 @_setjmp(ptr) returns_twice'; do
    if ! qgrep -F -x "$want" "$d/sj.ll"; then
      echo "FAIL  l4-returns-twice-declares"
      echo "    expected: $want"
      bad=1
    fi
  done
  # `vfork` is the only in-tree witness of L4 outside a fixture, and it lives in
  # an example's OUTPUT rather than in setjmp.h — so it also pins that the
  # attribute follows a roster of names and not the `setjmp` spelling.
  ./build/nucleusc --emit-llvm examples/cheader-posix.nuc > "$d/px.ll" 2>/dev/null || true
  if ! qgrep -F -x 'declare i32 @vfork() returns_twice' "$d/px.ll"; then
    echo "FAIL  l4-returns-twice-declares (vfork, from examples/cheader-posix.nuc)"
    { grep -n '@vfork' "$d/px.ll" || true; } | sed 's/^/    got: /' | head -2
    bad=1
  fi
  [ "$bad" = 0 ] && echo "PASS  l4-returns-twice-declares"

  # The attribute is only worth having if it changes what the optimizer does.
  # `_setjmp` SPECIFICALLY: `@setjmp` resolves to `__sigsetjmp` and is a
  # different call site (§7). The negative control — the same module with the
  # attribute stripped — is what makes this an assertion rather than a
  # coincidence: LLVM emits `tail call` there.
  if ! command -v opt >/dev/null 2>&1; then
    echo 'PASS  l4-no-tail-call (SKIP: llvm opt not on PATH)'
    rm -rf "$d"
    return 0
  fi
  bad=0
  ./build/nucleusc --emit-llvm examples/setjmp-guard.nuc > "$d/g.ll" 2>/dev/null || true
  if ! opt -O2 -S "$d/g.ll" -o "$d/g.opt.ll" 2>"$d/opt.err"; then
    echo "FAIL  l4-no-tail-call (opt -O2 rejected the emitted module)"
    sed 's/^/    /' "$d/opt.err" | head -3
    bad=1
  else
    got="$(grep -E '@_setjmp\(' "$d/g.opt.ll" | grep -v '^declare' || true)"
    case "$got" in
      *"tail call"*)
        echo "FAIL  l4-no-tail-call (opt -O2 tail-called _setjmp)"
        printf '%s\n' "$got" | sed 's/^/    got: /'
        bad=1 ;;
      *"call i32 @_setjmp("*) ;;
      *)
        echo "FAIL  l4-no-tail-call (no _setjmp call site survived -O2)"
        printf '%s\n' "$got" | sed 's/^/    got: /'
        bad=1 ;;
    esac
    # Negative control: strip the attribute and the same pipeline tail-calls it.
    sed 's/ returns_twice$//' "$d/g.ll" > "$d/g.nort.ll"
    opt -O2 -S "$d/g.nort.ll" -o "$d/g.nort.opt.ll" 2>/dev/null || true
    if [ -f "$d/g.nort.opt.ll" ] && ! qgrep -E 'tail call i32 @_setjmp\(' "$d/g.nort.opt.ll"; then
      echo "FAIL  l4-no-tail-call (control: -O2 does NOT tail-call _setjmp without the attribute,"
      echo "                       so the positive assertion above proves nothing)"
      bad=1
    fi
  fi
  [ "$bad" = 0 ] && echo "PASS  l4-no-tail-call"

  rm -rf "$d"
}
spawn run_l4_returns_twice

# c-header-layout.md §3.4's scope note, taken: `returns_twice` is now
# user-declarable on a Nucleus `defn`, spelled `:returns-twice`. The whole set of
# declaration attributes moved to the keyword spelling every other marker
# already uses (keyword-markers.md), so `noreturn` became `:noreturn` and both
# bare spellings are retired.
run_s16_decl_attrs() {
  local d bad out
  d="$(mktemp -d)"
  mkdir -p "$d/lib" "$d/use"
  bad=0

  # 1. The `define`. Both attributes, in either order, and both on one function.
  cat > "$d/def.nuc" <<'EOF'
(import-use "stdio.h")
(import-use "stdlib.h")
(defn sj (b:ptr):i32 :returns-twice (return 0))
(defn boom (m:CStr):void :noreturn (printf "%s\n" m) (exit 3))
(defn both (m:CStr):void :noreturn :returns-twice (printf "%s\n" m) (exit 3))
(defn plain (x:i32):i32 (return x))
(defn main ():i32 (printf "%d\n" (sj null)) (return 0))
EOF
  ./build/nucleusc --emit-llvm "$d/def.nuc" > "$d/def.ll" 2>"$d/def.err" || true
  for want in 'define i32 @sj(ptr %b.arg) returns_twice' \
              'define void @boom(ptr %m.arg) noreturn' \
              'define void @both(ptr %m.arg) noreturn returns_twice'; do
    if ! qgrep -F "$want" "$d/def.ll"; then
      echo "FAIL  s16-decl-attrs-define"
      echo "    expected: $want"
      bad=1
    fi
  done
  # A function with no attribute must gain none — and the module must link.
  if qgrep -E '^define i32 @plain\(i32 %x.arg\) (noreturn|returns_twice)' "$d/def.ll"; then
    echo "FAIL  s16-decl-attrs-define (an unattributed defn gained an attribute)"
    bad=1
  fi
  ./build/nucleusc "$d/def.nuc" -o "$d/def.bin" 2>>"$d/def.err" || true
  out="$("$d/def.bin" 2>/dev/null || true)"
  if [ "$out" != "0" ]; then
    echo "FAIL  s16-decl-attrs-define (module did not link/run: got '$out')"
    sed 's/^/    /' "$d/def.err" | head -3
    bad=1
  fi

  # 2. A top-level `(declare … :noreturn)` still drives `terminate-after-noreturn`
  #    (the one Nucleus-side consumer), and `:returns-twice` rides the declare.
  cat > "$d/dec.nuc" <<'EOF'
(declare my_abort ():void :noreturn)
(declare my_sj (b:ptr):i32 :returns-twice)
(defn main ():i32 (my_abort) (return 0))
EOF
  ./build/nucleusc --emit-llvm "$d/dec.nuc" > "$d/dec.ll" 2>"$d/dec.err" || true
  for want in 'declare void @my_abort() noreturn' \
              'declare i32 @my_sj(ptr) returns_twice'; do
    if ! qgrep -F -x "$want" "$d/dec.ll"; then
      echo "FAIL  s16-decl-attrs-declare"
      echo "    expected: $want"
      bad=1
    fi
  done
  if ! qgrep -E '^  unreachable' "$d/dec.ll"; then
    echo "FAIL  s16-decl-attrs-declare (a :noreturn call no longer terminates its block)"
    bad=1
  fi

  # 3. `.nuch` round-trip, solitary AND overloaded — the exporter and the two
  #    importers are three separate dispatch sites, and a missing one is silent.
  #    `resolve-import` tries `.nuc` everywhere before any `.nuch`, so the source
  #    must sit outside every search directory or the header is never read.
  mkdir -p "$d/src"
  cat > "$d/src/atlib.nuc" <<'EOF'
(import-use "stdio.h")
(import-use "stdlib.h")
(defn sj (b:ptr):i32 :returns-twice (return 0))
(defn sj (b:ptr n:i32):i32 :returns-twice (return n))
(defn nope (m:CStr):void :noreturn (printf "%s\n" m) (exit 3))
EOF
  ./build/nucleusc --emit-nuch "$d/src/atlib.nuc" > "$d/lib/atlib.nuch" 2>/dev/null
  cat > "$d/use/u.nuc" <<'EOF'
(import-use "stdio.h")
(import-use atlib)
(defn main ():i32 (printf "%d\n" (sj null)) (nope "bye") (return 0))
EOF
  ./build/nucleusc -I "$d/lib" --emit-llvm "$d/use/u.nuc" > "$d/u.ll" 2>"$d/u.err" || true
  if ! qgrep -F '(declare nope ((m CStr)) :void :noreturn)' "$d/lib/atlib.nuch" \
     || ! qgrep -F ':i32 :returns-twice)' "$d/lib/atlib.nuch"; then
    echo "FAIL  s16-decl-attrs-nuch-export"
    sed 's/^/    /' "$d/lib/atlib.nuch" | head -5
    bad=1
  fi
  for want in 'declare i32 @sj.ptr(ptr) returns_twice' \
              'declare i32 @sj.ptr.i32(ptr, i32) returns_twice' \
              'declare void @nope(ptr) noreturn'; do
    if ! qgrep -F -x "$want" "$d/u.ll"; then
      echo "FAIL  s16-decl-attrs-nuch-import"
      echo "    expected: $want"
      sed 's/^/    /' "$d/u.err" | head -3
      bad=1
    fi
  done

  # 4. The retired bare spellings each name their replacement. Without this they
  #    fall through as ordinary symbols — a body expression, or (in a declare)
  #    a phantom trailing operand — and fail somewhere unrelated.
  attr_says() {   # attr_says <file-body> <expected-substring>
    printf '%s\n' "$1" > "$d/leg.nuc"
    ./build/nucleusc --emit-llvm "$d/leg.nuc" >/dev/null 2>"$d/leg.err"
    qgrep -F "$2" "$d/leg.err"
  }
  if attr_says '(defn f (m:CStr):void noreturn (while (= 0 0) 0))' \
        "'noreturn' is no longer a declaration attribute -- write ':noreturn'" \
     && attr_says '(declare foo ():void noreturn)
(defn main ():i32 (return 0))' \
        "'noreturn' is no longer a declaration attribute -- write ':noreturn'" \
     && attr_says '(declare foo ():i32 returns_twice)
(defn main ():i32 (return 0))' \
        "'returns_twice' is no longer a declaration attribute -- write ':returns-twice'"; then
    :
  else
    echo "FAIL  s16-decl-attrs-legacy-rejected"
    sed 's/^/    /' "$d/leg.err" | head -3
    bad=1
  fi

  # 5. A LONE trailing form is the body, never an attribute — otherwise a
  #    keyword-returning one-expression body would be silently eaten.
  cat > "$d/kw.nuc" <<'EOF'
(import-use "stdio.h")
(import-use keyword)
(defn kw ():Keyword :noreturn)
(defn main ():i32 (printf "%d\n" (if (= (kw) :noreturn) 1 0)) (return 0))
EOF
  ./build/nucleusc --emit-llvm "$d/kw.nuc" > "$d/kw.ll" 2>"$d/kw.err" || true
  ./build/nucleusc "$d/kw.nuc" -o "$d/kw.bin" 2>>"$d/kw.err" || true
  out="$("$d/kw.bin" 2>/dev/null || true)"
  if qgrep -E '@kw\(.*\) noreturn' "$d/kw.ll" || [ "$out" != "1" ]; then
    echo "FAIL  s16-decl-attrs-lone-body (a one-expression keyword body was read as an attribute)"
    sed 's/^/    /' "$d/kw.err" | head -3
    bad=1
  fi

  [ "$bad" = 0 ] && echo "PASS  s16-decl-attrs"
  rm -rf "$d"
}
spawn run_s16_decl_attrs

# L5 (§3.5): a C typedef is a Nucleus type NAME, resolved by a sixth probe in
# `parse-type-name` placed after `type-alias-lookup-ref` (so a `deftype` can
# never be masked by an import) and returning the stored `Type*` directly —
# TRANSPARENT, exactly like `deftype`.
run_l5_typedef_names() {
  local d bad out got n
  d="$(mktemp -d)"
  mkdir -p "$d/lib"

  # 1. `off_t` in a signature. The load-bearing half is that the signature
  #    prescan runs BEFORE any import, so this needs `cheader-scan-typedef` and
  #    not just the import-time table. The emitted signature is `i64 (i64)`:
  #    transparency, asserted as IR rather than as "it compiled".
  bad=0
  printf '(import-use "sys/types.h")\n(defn f (x:off_t):off_t (return (+ x 1)))\n' > "$d/sig.nuc"
  ./build/nucleusc --emit-llvm "$d/sig.nuc" > "$d/sig.ll" 2>"$d/sig.err" || true
  if ! qgrep -E '^define i64 @f\(i64 ' "$d/sig.ll"; then
    echo "FAIL  l5-typedef-signature (expected 'define i64 @f(i64 …)')"
    { grep -E '^define .*@f\(' "$d/sig.ll" || true; } | sed 's/^/    got: /' | head -2
    sed 's/^/    err: /' "$d/sig.err" | head -2
    bad=1
  fi
  [ "$bad" = 0 ] && echo "PASS  l5-typedef-signature"

  # 2. Transparency's sharpest evidence: `off_t` and `i64` are `type-eq`, mangle
  #    identically, and are therefore ONE overload — the pair collides as a
  #    duplicate definition rather than resolving as two.
  bad=0
  printf '(import-use "sys/types.h")\n(defn f (x:off_t):off_t (return x))\n(defn f (x:i64):i64 (return x))\n' > "$d/ov.nuc"
  ./build/nucleusc --emit-llvm "$d/ov.nuc" >/dev/null 2>"$d/ov.err" || true
  if ! qgrep -F "duplicate definition of 'f'" "$d/ov.err"; then
    echo "FAIL  l5-typedef-transparent (off_t and i64 did not collide as one overload)"
    sed 's/^/    got: /' "$d/ov.err" | head -2
    bad=1
  fi
  [ "$bad" = 0 ] && echo "PASS  l5-typedef-transparent"

  # 3. `type-name-collision` gains a C-typedef arm: a `deftype` over an imported
  #    typedef name would be dead on arrival, so it is refused NAMING the header.
  bad=0
  printf '(import-use "sys/types.h")\n(deftype off_t i64)\n(defn f (x:off_t):off_t (return x))\n' > "$d/dt.nuc"
  ./build/nucleusc --emit-llvm "$d/dt.nuc" >/dev/null 2>"$d/dt.err" || true
  if ! qgrep -E "deftype: 'off_t' already names a C typedef imported from [^ ]*types\.h" "$d/dt.err"; then
    echo "FAIL  l5-deftype-collision (expected a refusal naming the header)"
    sed 's/^/    got: /' "$d/dt.err" | head -2
    bad=1
  fi
  [ "$bad" = 0 ] && echo "PASS  l5-deftype-collision"

  # 4. A recorded-NULL entry gets its own message, distinct from "not defined
  #    anywhere in this compilation unit" — the C table is the one registry that
  #    tells "declared, and we have no type for it" from "absent".
  #
  #    §5's stated subject for this row is stale: it names
  #    `(let (x:__jmp_buf …))`, but after L2/L3 `__jmp_buf` is REPRESENTABLE (an
  #    `(array i64 8)`) and that program now gives the storage-type message
  #    instead. `long double` was the replacement and is stale in turn — Stage 16
  #    FL-7 made it f80/f128 per target. `__int128` is the durable subject:
  #    deliberately unscheduled, and deliberately kept out of C1's implicit-int
  #    rule so it reaches this path rather than being narrowed.
  bad=0
  printf 'typedef __int128 l5_wi_t;\n' > "$d/l5.h"
  printf '(import-use "%s/l5.h")\n(defn f ():i32 (let (x:l5_wi_t 0) (return 0)))\n' "$d" > "$d/nl.nuc"
  ./build/nucleusc --emit-llvm "$d/nl.nuc" >/dev/null 2>"$d/nl.err" || true
  if ! qgrep -E "'l5_wi_t' names a C type this compiler cannot represent \([^ ]*l5\.h:1\)" "$d/nl.err"; then
    echo "FAIL  l5-unrepresentable-message"
    sed 's/^/    got: /' "$d/nl.err" | head -2
    bad=1
  fi
  [ "$bad" = 0 ] && echo "PASS  l5-unrepresentable-message"

  # 5. `jmp_buf` after L3 is a `TY-ARRAY`, so the probe has to answer the
  #    `g-array-ok` question: legal as `defvar` STORAGE (200 bytes, the §7
  #    program's first line), refused as a parameter with the same message the
  #    Nucleus `(array T N)` spelling gives. The size is compared against clang,
  #    never against a hardcoded 200.
  bad=0
  printf '(import-use "setjmp.h")\n(defn g (x:jmp_buf):i32 (return 0))\n' > "$d/jp.nuc"
  ./build/nucleusc --emit-llvm "$d/jp.nuc" >/dev/null 2>"$d/jp.err" || true
  if ! qgrep -F '(array T N) is a storage type' "$d/jp.err"; then
    echo "FAIL  l5-array-typedef-storage (jmp_buf was not refused as a parameter)"
    sed 's/^/    got: /' "$d/jp.err" | head -2
    bad=1
  fi
  printf '(import-use "stdio.h")\n(import-use "setjmp.h")\n(defvar env:jmp_buf)\n(defn main ():i32 (printf "%%lld\\n" (as i64 (sizeof jmp_buf))) (return 0))\n' > "$d/jv.nuc"
  ./build/nucleusc "$d/jv.nuc" -o "$d/jv.bin" 2>"$d/jv.err" || true
  if [ ! -x "$d/jv.bin" ]; then
    echo "FAIL  l5-array-typedef-storage ((defvar env:jmp_buf) did not compile)"
    sed 's/^/    /' "$d/jv.err" | head -3
    bad=1
  elif command -v cc >/dev/null 2>&1; then
    printf '#include <stdio.h>\n#include <setjmp.h>\nint main(void){printf("%%zu\\n", sizeof(jmp_buf));return 0;}\n' > "$d/jv.c"
    if cc "$d/jv.c" -o "$d/jv.coracle" 2>/dev/null; then
      got="$("$d/jv.bin" 2>&1 || true)"
      out="$("$d/jv.coracle" 2>&1 || true)"
      if [ "$got" != "$out" ]; then
        echo "FAIL  l5-array-typedef-storage (sizeof jmp_buf: Nucleus $got, clang $out)"
        bad=1
      fi
    fi
  fi
  [ "$bad" = 0 ] && echo "PASS  l5-array-typedef-storage"

  # 6. The same `g-array-ok` question on the Nucleus side of the fence. Obstacle
  #    (1) of L5 — `parse-type-from-node` read-and-CLEARS the permission before
  #    delegating a bare name to `parse-type-name` — is why a `deftype` array
  #    alias was refused at `defvar` before L5. This is a strict widening, so it
  #    needs its own pin, together with the position where it must still refuse.
  bad=0
  cat > "$d/da.nuc" <<'EOF'
(import-use "stdio.h")
(deftype Buf (array i32 4))
(defstruct Holder b:Buf n:i32)
(defvar gbuf:Buf)
(defn main ():i32 (printf "%lld %lld\n" (as i64 (sizeof Buf)) (as i64 (sizeof Holder))) (return 0))
EOF
  ./build/nucleusc "$d/da.nuc" -o "$d/da.bin" 2>"$d/da.err" || true
  out="$("$d/da.bin" 2>/dev/null || true)"
  if [ "$out" != "16 20" ]; then
    echo "FAIL  l5-deftype-array-storage (expected '16 20', got '$out')"
    sed 's/^/    /' "$d/da.err" | head -3
    bad=1
  fi
  printf '(deftype Buf (array i32 4))\n(defn f (x:Buf):i32 (return 0))\n' > "$d/dp.nuc"
  ./build/nucleusc --emit-llvm "$d/dp.nuc" >/dev/null 2>"$d/dp.err" || true
  if ! qgrep -F '(array T N) is a storage type' "$d/dp.err"; then
    echo "FAIL  l5-deftype-array-storage (an array alias was accepted as a parameter)"
    sed 's/^/    got: /' "$d/dp.err" | head -2
    bad=1
  fi
  [ "$bad" = 0 ] && echo "PASS  l5-deftype-array-storage"

  # 7. REPL rollback. Once a C typedef is a user-visible type name, a half-loaded
  #    header leaving one behind is a real defect and not untidiness: the entry
  #    can hold a `Type` over a StructDef `repl-restore` has just truncated out
  #    of `g-structs`, and the next module emits `[1 x %RLTag]` with no `%RLTag`
  #    definition. `ReplState` gained a `cheader-typedefs` watermark for it.
  #
  #    The half-load is staged as ONE form — a `.nuc` import whose own C import
  #    succeeds and whose next form dies — because the REPL snapshots per form.
  bad=0
  cat > "$d/lib/hdr.h" <<'EOF'
typedef long rl_scalar_t;
struct RLTag { long a; long b; };
typedef struct RLTag rl_arr_t[1];
EOF
  cat > "$d/lib/half.nuc" <<EOF
(import-use "$d/lib/hdr.h")
(defn rl-broken ():i32 (return (rl-no-such-function 1)))
EOF
  out="$(printf '(import-use "%s/lib/half.nuc")\n(defvar rv:rl_scalar_t)\n(defvar ra:rl_arr_t)\n(defn rl-alive ():i32 (return 7))\n(rl-alive)\n' "$d" \
        | ./build/nucleusc -i 2>&1 || true)"
  # Both names must be gone, the session must survive, and nothing may reach
  # LLVM: an entry that outlived the rollback shows up as an IR parse error
  # about an unsized type, not as a diagnostic.
  for n in rl_scalar_t rl_arr_t; do
    if ! printf '%s' "$out" | qgrep -F "unknown type: $n"; then
      echo "FAIL  l5-repl-rollback ($n survived a half-loaded import)"
      printf '%s\n' "$out" | sed 's/^/    got: /' | head -8
      bad=1
    fi
  done
  if printf '%s' "$out" | qgrep -E 'IR parse error|must be sized'; then
    echo "FAIL  l5-repl-rollback (a stale typedef reached LLVM)"
    printf '%s\n' "$out" | sed 's/^/    got: /' | head -8
    bad=1
  fi
  if ! printf '%s' "$out" | qgrep -F '7'; then
    echo "FAIL  l5-repl-rollback (the session did not survive the failed import)"
    printf '%s\n' "$out" | sed 's/^/    got: /' | head -8
    bad=1
  fi
  # Positive control: the SAME header, imported successfully, does resolve both
  # names — otherwise (7) would pass on a REPL that never learned them at all.
  out="$(printf '(import-use "%s/lib/hdr.h")\n(defvar rv2:rl_scalar_t)\n(defvar ra2:rl_arr_t)\n(defn rl-alive2 ():i32 (return 9))\n(rl-alive2)\n' "$d" \
        | ./build/nucleusc -i 2>&1 || true)"
  if printf '%s' "$out" | qgrep -F 'unknown type:'; then
    echo "FAIL  l5-repl-rollback (control: a SUCCESSFUL import does not resolve the names either)"
    printf '%s\n' "$out" | sed 's/^/    got: /' | head -8
    bad=1
  fi
  [ "$bad" = 0 ] && echo "PASS  l5-repl-rollback"

  # 8. `type-name-to-c` used to render any unmapped name `struct %s`, so
  #    `--emit-cheader` emitted `struct off_t f(struct off_t x);`. A C typedef
  #    name renders verbatim — and, since Stage 16, with an `#include` of the
  #    header the import named, which is what makes the result compile
  #    (asserted in full by run_cheader_c_include).
  bad=0
  printf '(import-use "sys/types.h")\n(defn f (x:off_t):off_t (return (+ x 1)))\n' > "$d/ch.nuc"
  ./build/nucleusc --emit-cheader "$d/ch.nuc" > "$d/ch.h" 2>"$d/ch.err" || true
  if ! qgrep -F -x '#include <sys/types.h>' "$d/ch.h"; then
    echo "FAIL  l5-cheader-typedef (no #include for the header off_t came from)"
    sed 's/^/    got: /' "$d/ch.h" | head -6
    bad=1
  fi
  if ! qgrep -F -x 'off_t f(off_t x);' "$d/ch.h"; then
    echo "FAIL  l5-cheader-typedef (expected 'off_t f(off_t x);')"
    { grep -F ' f(' "$d/ch.h" || true; } | sed 's/^/    got: /' | head -2
    sed 's/^/    err: /' "$d/ch.err" | head -2
    bad=1
  fi
  [ "$bad" = 0 ] && echo "PASS  l5-cheader-typedef"

  rm -rf "$d"
}
spawn run_l5_typedef_names

# Stage 16 CD-1/CD-2/CD-3 (c-header-layout.md §8): the three C declarator shapes
# the parser used to drop — a multi-declarator field line, a typedef declarator
# list, and a with-body aggregate array typedef.
#
# The oracle is the exact `%X = type` line (which IS the field offsets, not
# merely the size) plus `sizeof` against `cc` built from the same header, the
# methodology run_l2_layout_matrix established. Every wrong row in §1.5's survey
# compiles fine, so an exit-code or size-only check sees nothing.
run_cd_declarators() {
  local d bad
  d="$(mktemp -d)"

  cat > "$d/m.nuc" <<'EOF'
(import-use "stdio.h")
(import-use "tests/fixtures/cd-declarators.h")
(defvar tv:cd_tagarr)
(defvar av:cd_anonarr)
(defn f_ta (x:cd_ta):i32 (return x))
(defn f_tb (x:cd_tb):i32 (return 0))
(defn f_tc (x:cd_tc):i32 (return 0))
(defn main ():i32
  (printf "cd_plain %lld\n" (as i64 (sizeof cd_plain)))
  (printf "cd_ptrs %lld\n" (as i64 (sizeof cd_ptrs)))
  (printf "cd_arrays %lld\n" (as i64 (sizeof cd_arrays)))
  (printf "cd_bits %lld\n" (as i64 (sizeof cd_bits)))
  (printf "cd_three %lld\n" (as i64 (sizeof cd_three)))
  (printf "cd_td %lld\n" (as i64 (sizeof cd_td)))
  (printf "cd_tagarr %lld\n" (as i64 (sizeof cd_tagarr)))
  (printf "cd_anonarr %lld\n" (as i64 (sizeof cd_anonarr)))
  (return 0))
EOF
  ./build/nucleusc --emit-llvm "$d/m.nuc" > "$d/m.ll" 2>"$d/m.err" || true

  # 1. CD-1: the exact layout of every multi-declarator field line. Each
  #    declarator's own stars (`cd_ptrs`), own extents (`cd_arrays`), own
  #    bit-field width (`cd_bits` — the `tcp_info` shape).
  bad=0
  if [ -s "$d/m.err" ]; then
    echo "FAIL  cd1-multi-declarator-types (import produced diagnostics)"
    sed 's/^/    got: /' "$d/m.err" | head -3
    bad=1
  fi
  while IFS='|' read -r name want; do
    [ -z "$name" ] && continue
    if ! qgrep -F -x "$want" "$d/m.ll"; then
      echo "FAIL  cd1-multi-declarator-types ($name)"
      echo "    expected: $want"
      { grep -E "^%$name = type" "$d/m.ll" || true; } | sed 's/^/    got:      /'
      bad=1
    fi
  done <<'EOF'
cd_plain|%cd_plain = type { i32, i32 }
cd_ptrs|%cd_ptrs = type { ptr, ptr, i32 }
cd_arrays|%cd_arrays = type { i32, [3 x i32] }
cd_bits|%cd_bits = type { [1 x i8], i32 }
cd_three|%cd_three = type { i16, i16, i16, i32 }
EOF
  if ! llvm-as "$d/m.ll" -o /dev/null 2>/dev/null; then
    echo "FAIL  cd1-multi-declarator-types (emitted IR does not parse)"
    bad=1
  fi
  [ "$bad" = 0 ] && echo "PASS  cd1-multi-declarator-types"

  # 2. Every size in the program above against `cc` on the same header.
  bad=0
  ./build/nucleusc "$d/m.nuc" -o "$d/m.bin" 2>>"$d/m.err" || true
  if [ ! -x "$d/m.bin" ]; then
    echo "FAIL  cd-sizeof-vs-cc (compile/link failed)"
    sed 's/^/    /' "$d/m.err" | head -4
    bad=1
  elif ! command -v cc >/dev/null 2>&1; then
    # Skip only the oracle comparison — the assertions below it are on the
    # emitted IR and stay in force, or the unit reports a false clean.
    echo "PASS  cd-sizeof-vs-cc (SKIP: no cc to build the oracle against)"
    bad=2
  else
    "$d/m.bin" > "$d/m.out" 2>&1 || true
    cat > "$d/m.c" <<'EOF'
#include <stdio.h>
#include "tests/fixtures/cd-declarators.h"
int main(void){
  printf("cd_plain %zu\n", sizeof(struct cd_plain));
  printf("cd_ptrs %zu\n", sizeof(struct cd_ptrs));
  printf("cd_arrays %zu\n", sizeof(struct cd_arrays));
  printf("cd_bits %zu\n", sizeof(struct cd_bits));
  printf("cd_three %zu\n", sizeof(struct cd_three));
  printf("cd_td %zu\n", sizeof(cd_td));
  printf("cd_tagarr %zu\n", sizeof(cd_tagarr));
  printf("cd_anonarr %zu\n", sizeof(cd_anonarr));
  return 0;
}
EOF
    if cc -I. "$d/m.c" -o "$d/m.coracle" 2>"$d/cc.err"; then
      "$d/m.coracle" > "$d/c.out" 2>&1 || true
      if ! diff -u "$d/c.out" "$d/m.out" > "$d/cc.diff" 2>&1; then
        echo "FAIL  cd-sizeof-vs-cc (Nucleus disagrees with cc on the same header)"
        sed 's/^/    /' "$d/cc.diff" | head -14
        bad=1
      fi
    else
      echo "FAIL  cd-sizeof-vs-cc (the C oracle does not build)"
      sed 's/^/    /' "$d/cc.err" | head -4
      bad=1
    fi
  fi
  [ "$bad" = 0 ] && echo "PASS  cd-sizeof-vs-cc"

  # 3. CD-1's residue fails SAFE: declarators that disagree in pointer depth
  #    leave the struct opaque with a located error and NO `%X = type` line.
  #    Guessing `q`'s type from `*p` is exactly the silent class L1 removed.
  bad=0
  printf '(import-use "stdio.h")\n(import-use "tests/fixtures/cd-declarators.h")\n(defn main ():i32 (printf "%%lld\\n" (as i64 (sizeof cd_mixed_ptr))) (return 0))\n' \
    > "$d/u.nuc"
  ./build/nucleusc --emit-llvm "$d/u.nuc" > "$d/u.ll" 2>"$d/u.err" || true
  if ! qgrep -E "'cd_mixed_ptr' is an opaque type declared at [^ ]*tests/fixtures/cd-declarators\.h:47;" "$d/u.err"; then
    echo "FAIL  cd1-mixed-pointer-refused (expected a located error at cd-declarators.h:47)"
    sed 's/^/    got: /' "$d/u.err" | head -2
    bad=1
  fi
  if qgrep -E '^%cd_mixed_ptr = type' "$d/u.ll"; then
    echo "FAIL  cd1-mixed-pointer-refused (got a layout it has no basis for)"
    bad=1
  fi
  [ "$bad" = 0 ] && echo "PASS  cd1-mixed-pointer-refused"

  # 4. CD-2: `typedef int cd_ta, *cd_tb;` — every declarator is recorded, each
  #    with its own pointer depth and extents, not just the first.
  bad=0
  qgrep -E '^define i32 @f_ta\(i32 ' "$d/m.ll" || bad=1
  qgrep -E '^define i32 @f_tb\(ptr ' "$d/m.ll" || bad=1
  qgrep -E '^define i32 @f_tc\(i64 ' "$d/m.ll" || bad=1
  if [ "$bad" = 0 ]; then echo "PASS  cd2-typedef-list"; else
    echo "FAIL  cd2-typedef-list (a later declarator lost its own type)"
    grep -E '^define i32 @f_t' "$d/m.ll" | sed 's/^/    got: /'
  fi

  # 5. CD-3: `typedef struct Tag { … } Name[N];`. The storage carries the
  #    extent, and the parameter DECAYS — before this it was `declare void
  #    @cd_take_tagarr(i64)`, a wrong calling convention with no diagnostic.
  bad=0
  qgrep -F -x '@tv = global [2 x %cd_tag] zeroinitializer, section ".bss.tv", align 8' "$d/m.ll" || bad=1
  qgrep -F -x '@av = global [3 x %__carr.cd_anonarr] zeroinitializer, section ".bss.av", align 8' "$d/m.ll" || bad=1
  qgrep -F -x 'declare void @cd_take_tagarr(ptr)' "$d/m.ll" || bad=1
  qgrep -F -x 'declare void @cd_take_anonarr(ptr)' "$d/m.ll" || bad=1
  if [ "$bad" = 0 ]; then echo "PASS  cd3-array-typedef-body"; else
    echo "FAIL  cd3-array-typedef-body"
    grep -E '^@tv|^@av|^declare void @cd_take' "$d/m.ll" | sed 's/^/    got: /'
  fi

  # 6. The real-header witness. `struct tcp_info` splits a bit-field run across
  #    a declarator list (`tcpi_snd_wscale : 4, tcpi_rcv_wscale : 4`) and was the
  #    one glibc type across the 40 standard headers surveyed that CD-1 unblocks.
  bad=0
  cat > "$d/t.c" <<'EOF'
#include <netinet/tcp.h>
#include <stdio.h>
struct tcpi_align { char pad; struct tcp_info v; };
int main(void){ printf("tcp_info %zu %zu\n", sizeof(struct tcp_info),
                       __builtin_offsetof(struct tcpi_align, v)); return 0; }
EOF
  if ! cc "$d/t.c" -o "$d/t.coracle" 2>/dev/null; then
    echo "PASS  cd-libc-tcp-info (SKIP: the C oracle does not build — no netinet/tcp.h)"
  else
    "$d/t.coracle" > "$d/t.cout" 2>&1 || true
    cat > "$d/t.nuc" <<'EOF'
(import-use "stdio.h")
(import-use "netinet/tcp.h")
(defstruct TAlign pad:i8 v:tcp_info)
(defn main ():i32
  (let (a:ptr:TAlign (alloca TAlign))
    (printf "tcp_info %lld %lld\n" (as i64 (sizeof tcp_info))
      (- (unsafe/cast i64 (addr-of a 'v)) (unsafe/cast i64 a))))
  (return 0))
EOF
    ./build/nucleusc "$d/t.nuc" -o "$d/t.bin" 2>"$d/t.err" || bad=1
    if [ "$bad" = 0 ]; then
      "$d/t.bin" > "$d/t.out" 2>&1 || true
      diff -u "$d/t.cout" "$d/t.out" > "$d/t.diff" 2>&1 || bad=1
    fi
    if [ "$bad" = 0 ]; then echo "PASS  cd-libc-tcp-info ($(cat "$d/t.out"), matching cc)"; else
      echo "FAIL  cd-libc-tcp-info (size/alignment against cc)"
      sed 's/^/    /' "$d/t.err" 2>/dev/null | head -3
      sed 's/^/    /' "$d/t.diff" 2>/dev/null | head -6
    fi
  fi

  rm -rf "$d"
}
spawn run_cd_declarators

# Stage 16 CD-4 (c-header-layout.md §8.2): a declarator LIST after a struct or
# union body. `typedef struct { … } A, B;` registered A and dropped B in
# silence; `struct S { … } x, y;` left `x, y;` for the function-declaration
# parser to make what it could of.
#
# Same oracle as run_cd_declarators: the exact `%X = type` line, plus `sizeof`
# against `cc` built from the same header.
run_cd4_declarator_list() {
  local d bad
  d="$(mktemp -d)"

  cat > "$d/m.nuc" <<'EOF'
(import-use "stdio.h")
(import-use "tests/fixtures/cd4-declarator-list.h")
(defvar gv:cd4_G)
(defn f_ep (p:cd4_Ep):i32 (return 0))
(defn main ():i32
  (printf "cd4_A %lld\n" (as i64 (sizeof cd4_A)))
  (printf "cd4_B %lld\n" (as i64 (sizeof cd4_B)))
  (printf "cd4_C %lld\n" (as i64 (sizeof cd4_C)))
  (printf "cd4_D %lld\n" (as i64 (sizeof cd4_D)))
  (printf "cd4_E %lld\n" (as i64 (sizeof cd4_E)))
  (printf "cd4_F %lld\n" (as i64 (sizeof cd4_F)))
  (printf "cd4_G %lld\n" (as i64 (sizeof cd4_G)))
  (printf "cd4_U %lld\n" (as i64 (sizeof cd4_U)))
  (printf "cd4_V %lld\n" (as i64 (sizeof cd4_V)))
  (printf "cd4_S %lld\n" (as i64 (sizeof cd4_S)))
  (printf "cd4_after %lld\n" (as i64 (sizeof cd4_after)))
  (return 0))
EOF
  ./build/nucleusc --emit-llvm "$d/m.nuc" > "$d/m.ll" 2>"$d/m.err" || true

  # 1. Every declarator of every list is a real type, with the body's layout.
  #    `cd4_B`/`cd4_D`/`cd4_V` are the ones that did not exist at all before;
  #    `cd4_Ep` is a pointer declarator (a typedef-table entry, NOT a second
  #    StructDef, or it shadows the record); `cd4_G` is an array declarator in a
  #    LATER position, anchored on the minted `__carr.` element like CD-3's.
  bad=0
  if [ -s "$d/m.err" ]; then
    echo "FAIL  cd4-declarator-list (import produced diagnostics)"
    sed 's/^/    got: /' "$d/m.err" | head -3
    bad=1
  fi
  while IFS='|' read -r name want; do
    [ -z "$name" ] && continue
    if ! qgrep -F -x "$want" "$d/m.ll"; then
      echo "FAIL  cd4-declarator-list ($name)"
      echo "    expected: $want"
      { grep -E "^%$name = type" "$d/m.ll" || true; } | sed 's/^/    got:      /'
      bad=1
    fi
  done <<'EOF'
cd4_A|%cd4_A = type { i32, i32 }
cd4_B|%cd4_B = type { i32, i32 }
cd4_C|%cd4_C = type { i32, i32 }
cd4_D|%cd4_D = type { i32, i32 }
cd4_U|%cd4_U = type { i32 }
cd4_V|%cd4_V = type { i32 }
cd4_S|%cd4_S = type { i32, i64 }
cd4_after|%cd4_after = type { i32 }
EOF
  # The array declarator's storage, and that `gv` really is 3 elements.
  if ! qgrep -F 'global [3 x %__carr.cd4_G] zeroinitializer' "$d/m.ll"; then
    echo "FAIL  cd4-declarator-list (cd4_G is not [3 x __carr.cd4_G])"
    { grep -F '@gv =' "$d/m.ll" || true; } | sed 's/^/    got: /'
    bad=1
  fi
  if ! llvm-as "$d/m.ll" -o /dev/null 2>/dev/null; then
    echo "FAIL  cd4-declarator-list (emitted IR does not parse)"
    bad=1
  fi
  [ "$bad" = 0 ] && echo "PASS  cd4-declarator-list"

  # 2. Every size against `cc` on the same header.
  bad=0
  ./build/nucleusc "$d/m.nuc" -o "$d/m.bin" 2>>"$d/m.err" || true
  if [ ! -x "$d/m.bin" ]; then
    echo "FAIL  cd4-sizeof-vs-cc (compile/link failed)"
    sed 's/^/    /' "$d/m.err" | head -4
    bad=1
  elif ! command -v cc >/dev/null 2>&1; then
    echo "PASS  cd4-sizeof-vs-cc (SKIP: no cc to build the oracle against)"
    bad=2
  else
    "$d/m.bin" > "$d/m.out" 2>&1 || true
    cat > "$d/m.c" <<'EOF'
#include <stdio.h>
#include "tests/fixtures/cd4-declarator-list.h"
int main(void){
  printf("cd4_A %zu\ncd4_B %zu\ncd4_C %zu\ncd4_D %zu\ncd4_E %zu\ncd4_F %zu\n"
         "cd4_G %zu\ncd4_U %zu\ncd4_V %zu\ncd4_S %zu\ncd4_after %zu\n",
    sizeof(cd4_A), sizeof(cd4_B), sizeof(cd4_C), sizeof(cd4_D), sizeof(cd4_E),
    sizeof(cd4_F), sizeof(cd4_G), sizeof(cd4_U), sizeof(cd4_V),
    sizeof(struct cd4_S), sizeof(struct cd4_after));
  return 0;
}
EOF
    if cc -I. "$d/m.c" -o "$d/m.coracle" 2>"$d/cc.err"; then
      "$d/m.coracle" > "$d/c.out" 2>&1 || true
      if ! diff -u "$d/c.out" "$d/m.out" > "$d/cc.diff" 2>&1; then
        echo "FAIL  cd4-sizeof-vs-cc (Nucleus disagrees with cc on the same header)"
        sed 's/^/    /' "$d/cc.diff" | head -14
        bad=1
      fi
    else
      echo "FAIL  cd4-sizeof-vs-cc (the C oracle does not build)"
      sed 's/^/    /' "$d/cc.err" | head -4
      bad=1
    fi
  fi
  [ "$bad" = 0 ] && echo "PASS  cd4-sizeof-vs-cc"

  rm -rf "$d"
}
spawn run_cd4_declarator_list

# Stage 16 C4 (cheader-parser-vs-libclang.md §6): `clang -E` reads the EMISSION
# target's headers. Before this it read the host's under every `--target=`, so
# an AVR build of `(import-use "string.h")` declared glibc's `strlen` returning
# `i64` — on a machine whose `size_t` is 16 bits and whose libc does not have
# half those symbols.
#
# Both lanes name their triple where it matters: the AVR lane is the claim, and
# the host lane is the CONTRAST (an unflagged host build must be unchanged),
# which is the one case conventions.md leaves host-relative on purpose.
run_c4_target_headers() {
  local d bad host avr
  d="$(mktemp -d)"
  printf '(exclude-prelude)\n(import-use "string.h")\n(defn main ():i32 (return 0))\n' \
    > "$d/s.nuc"

  # The host lane. No `--target=`, so no flags are added at all — this is the
  # byte-for-byte pre-C4 path.
  bad=0
  ./build/nucleusc --emit-llvm "$d/s.nuc" > "$d/host.ll" 2>"$d/host.err" || true
  if ! qgrep -E '^declare i(32|64) @strlen\(ptr\)$' "$d/host.ll"; then
    echo "FAIL  c4-host-headers-unchanged (no host-width strlen)"
    { grep -F '@strlen' "$d/host.ll" || true; } | sed 's/^/    got: /' | head -2
    bad=1
  fi
  if [ -s "$d/host.err" ]; then
    echo "FAIL  c4-host-headers-unchanged (a host build must print nothing)"
    sed 's/^/    got: /' "$d/host.err" | head -3
    bad=1
  fi
  [ "$bad" = 0 ] && echo "PASS  c4-host-headers-unchanged"

  # The AVR lane, gated on the target's headers actually being installed —
  # without avr-libc there is nothing for clang to read and the fallback below
  # is the correct outcome, not a failure.
  if ! clang -E --target=avr -x c -include string.h /dev/null >/dev/null 2>&1; then
    echo "PASS  c4-avr-target-headers (SKIP: no avr-libc headers for clang to read)"
  else
    bad=0
    ./build/nucleusc --target=avr --mcpu=atmega328p --emit-llvm "$d/s.nuc" \
      > "$d/avr.ll" 2>"$d/avr.err" || true
    # avr-libc's size_t is 16 bits, so every `size_t` in the declarations is
    # `i16`. The host's is 64 — this is the whole measurement.
    while IFS='|' read -r what want; do
      [ -z "$what" ] && continue
      if ! qgrep -F -x "$want" "$d/avr.ll"; then
        echo "FAIL  c4-avr-target-headers ($what)"
        echo "    expected: $want"
        { grep -E "@$what\(" "$d/avr.ll" || true; } | sed 's/^/    got:      /' | head -2
        bad=1
      fi
    done <<'EOF'
strlen|declare i16 @strlen(ptr)
memcpy|declare ptr @memcpy(ptr, ptr, i16)
EOF
    # A glibc-only symbol proves the HOST header is not what was read.
    if qgrep -F '@__memcmpeq' "$d/avr.ll"; then
      echo "FAIL  c4-avr-target-headers (glibc's __memcmpeq present: host headers were read)"
      bad=1
    fi
    if [ -s "$d/avr.err" ]; then
      echo "FAIL  c4-avr-target-headers (unexpected diagnostics)"
      sed 's/^/    got: /' "$d/avr.err" | head -3
      bad=1
    fi
    [ "$bad" = 0 ] && echo "PASS  c4-avr-target-headers"
  fi

  # A target whose headers are NOT installed must keep working — refusing would
  # retire cross-compiling for every triple without a local sysroot, which is
  # how every target lane in this suite runs. It falls back to the host text and
  # says so; the warning is the contract, not the fallback being silent.
  bad=0
  ./build/nucleusc --target=i386-pc-linux-gnu --emit-llvm "$d/s.nuc" \
    > "$d/i386.ll" 2>"$d/i386.err" || true
  if clang -E --target=i386-pc-linux-gnu -x c -include string.h /dev/null >/dev/null 2>&1; then
    echo "PASS  c4-missing-sysroot-falls-back (SKIP: i386 headers ARE installed here)"
  else
    if ! qgrep -F 'could not be preprocessed for target' "$d/i386.err"; then
      echo "FAIL  c4-missing-sysroot-falls-back (no warning about the fallback)"
      sed 's/^/    got: /' "$d/i386.err" | head -3
      bad=1
    fi
    if ! qgrep -F 'target triple = "i386-pc-linux-gnu"' "$d/i386.ll"; then
      echo "FAIL  c4-missing-sysroot-falls-back (the compile did not survive)"
      bad=1
    fi
    [ "$bad" = 0 ] && echo "PASS  c4-missing-sysroot-falls-back"
  fi

  # A header that exists on NO search path is fatal and located — it used to be
  # swallowed whole, leaving every name it declares unresolvable with nothing
  # pointing at the import.
  bad=0
  printf '(import-use "no-such-header-c4.h")\n(defn main ():i32 (return 0))\n' \
    > "$d/miss.nuc"
  ./build/nucleusc --emit-llvm "$d/miss.nuc" > "$d/miss.ll" 2>"$d/miss.err" && bad=1
  if [ "$bad" = 1 ]; then
    echo "FAIL  c4-missing-header-is-fatal (compile succeeded)"
  elif ! qgrep -E "miss\.nuc:1: error: c-include: failed to preprocess 'no-such-header-c4\.h'" "$d/miss.err"; then
    echo "FAIL  c4-missing-header-is-fatal (no located diagnostic)"
    sed 's/^/    got: /' "$d/miss.err" | head -4
    bad=1
  fi
  [ "$bad" = 0 ] && echo "PASS  c4-missing-header-is-fatal"

  rm -rf "$d"
}
spawn run_c4_target_headers

# Stage 16 (c-header-layout.md §6, the `--emit-cheader` item): a public
# signature naming a C typedef renders the name BARE — `struct off_t` names
# nothing — so the generated header did not compile at all until it also
# carried the `#include` the name came from. This is the rule the preamble
# already applies to `size_t` with `<stddef.h>`.
run_cheader_c_include() {
  local d bad
  d="$(mktemp -d)"
  printf '(import-use "unistd.h")\n(defn seek (fd:i32 off:off_t):off_t (return off))\n' \
    > "$d/o.nuc"
  ./build/nucleusc --emit-cheader "$d/o.nuc" > "$d/o.h" 2>"$d/o.err" || true

  bad=0
  if ! qgrep -F -x '#include <unistd.h>' "$d/o.h"; then
    echo "FAIL  cheader-c-typedef-include (no #include for the header off_t came from)"
    sed 's/^/    got: /' "$d/o.h" | head -8
    bad=1
  fi
  # The include is the IMPORT spelling, never the /usr/include file a
  # linemarker names — only the former is portable.
  if qgrep -F '/usr/include' "$d/o.h"; then
    echo "FAIL  cheader-c-typedef-include (included an absolute system path)"
    { grep -F '/usr/include' "$d/o.h" || true; } | sed 's/^/    got: /' | head -2
    bad=1
  fi
  if ! qgrep -F -x 'off_t seek(int32_t fd, off_t off);' "$d/o.h"; then
    echo "FAIL  cheader-c-typedef-include (declaration is not the bare typedef name)"
    { grep -F ' seek(' "$d/o.h" || true; } | sed 's/^/    got: /' | head -2
    bad=1
  fi
  # The point of the include: the header now compiles on its own.
  if command -v clang >/dev/null 2>&1; then
    if ! clang -fsyntax-only -Wno-pragma-once-outside-header -x c "$d/o.h" 2>"$d/o.cerr"; then
      echo "FAIL  cheader-c-typedef-include (generated header does not compile)"
      sed 's/^/    /' "$d/o.cerr" | head -4
      bad=1
    fi
  fi
  [ "$bad" = 0 ] && echo "PASS  cheader-c-typedef-include"

  # A header naming NO C typedef gains no include — the list is the types the
  # header actually names, as it is on the Nucleus side.
  bad=0
  printf '(import-use "unistd.h")\n(defn plain (x:i32):i32 (return x))\n' > "$d/p.nuc"
  ./build/nucleusc --emit-cheader "$d/p.nuc" > "$d/p.h" 2>/dev/null || true
  if qgrep -F '#include <unistd.h>' "$d/p.h"; then
    echo "FAIL  cheader-c-include-only-when-named (included an unused C header)"
    bad=1
  fi
  [ "$bad" = 0 ] && echo "PASS  cheader-c-include-only-when-named"

  rm -rf "$d"
}
spawn run_cheader_c_include

# Stage 17: object-like `#define`s imported as untyped integer constants
# (design/stage17-native-strings/platform-constants.md). tests/layout/macros.h
# is the admission table; the POSIX half asserts the values are the ones the C
# compiler itself sees, which is the property the deleted hardcoded table in
# lib/file.nuc could not have.
run_platform_constants() {
  local d bad want got pre
  d="$(mktemp -d)"

  bad=0
  printf '(import-use "tests/layout/macros.h")\n(import-use io)\n(defn main ():i32 (print MP_PUB " " MP_SHIFT " " MP_XOR " " MP_AND " " MP_NEG " " MP_MAX "\\n") (return 0))\n' \
    > "$d/adm.nuc"
  if ! ./build/nucleusc "$d/adm.nuc" -o "$d/adm" 2>"$d/adm.err"; then
    echo "FAIL  s17-cmacro-admitted (compile error)"
    sed 's/^/    /' "$d/adm.err" | head -4
    bad=1
  else
    got="$("$d/adm")"
    # MP_PUB folds THROUGH the private _MP_BASE: 010 | 0x20.
    want="40 16 255 60 -3 9223372036854775807"
    if [ "$got" != "$want" ]; then
      echo "FAIL  s17-cmacro-admitted (wrong values)"
      echo "    expected: $want"
      echo "    got:      $got"
      bad=1
    fi
  fi
  [ "$bad" = 0 ] && echo "PASS  s17-cmacro-admitted"

  # Everything that is not an integer constant expression, plus the reserved
  # name, stays out. `MP_OVER` is the decimal-overflow guard.
  bad=0
  for n in _MP_BASE MP_FN MP_STR MP_FLOAT MP_LOGIC MP_OVER; do
    printf '(import-use "tests/layout/macros.h")\n(import-use io)\n(defn main ():i32 (print %s "\\n") (return 0))\n' \
      "$n" > "$d/rej.nuc"
    if ./build/nucleusc "$d/rej.nuc" -o "$d/rej" 2>/dev/null; then
      echo "FAIL  s17-cmacro-refused ($n was registered)"
      bad=1
    fi
  done
  # A clang predefine is not the header's macro and must not be registered.
  pre="$(clang -E -dM -x c /dev/null 2>/dev/null \
         | sed -n 's/^#define \([A-Za-z][A-Za-z0-9_]*\) .*/\1/p' | head -1)"
  if [ -n "$pre" ]; then
    printf '(import-use "tests/layout/macros.h")\n(import-use io)\n(defn main ():i32 (print %s "\\n") (return 0))\n' \
      "$pre" > "$d/pre.nuc"
    if ./build/nucleusc "$d/pre.nuc" -o "$d/pre" 2>/dev/null; then
      echo "FAIL  s17-cmacro-refused (clang predefine '$pre' was registered)"
      bad=1
    fi
  fi
  [ "$bad" = 0 ] && echo "PASS  s17-cmacro-refused"

  # `unsafe/import-private` is the documented way past the leading-underscore rule.
  bad=0
  printf '(unsafe/import-private "tests/layout/macros.h" m)\n(import-use io)\n(defn main ():i32 (print _MP_BASE "\\n") (return 0))\n' \
    > "$d/priv.nuc"
  if ! ./build/nucleusc "$d/priv.nuc" -o "$d/priv" 2>"$d/priv.err"; then
    echo "FAIL  s17-cmacro-private (compile error)"
    sed 's/^/    /' "$d/priv.err" | head -4
    bad=1
  elif [ "$("$d/priv")" != "8" ]; then
    echo "FAIL  s17-cmacro-private (expected 8, got $("$d/priv"))"
    bad=1
  fi
  [ "$bad" = 0 ] && echo "PASS  s17-cmacro-private"

  # The portability property: the values are whatever THIS platform's headers
  # say, so the reference is the C compiler, never a table written here.
  bad=0
  cat > "$d/ref.c" <<'REFEOF'
#include <fcntl.h>
#include <stdio.h>
#include <time.h>
int main(void) {
  printf("%d %d %d %d %d %d %ld\n", O_RDONLY, O_WRONLY, O_CREAT, O_TRUNC,
         O_APPEND, SEEK_SET, (long)CLOCKS_PER_SEC);
  return 0;
}
REFEOF
  printf '(import-use "fcntl.h")\n(import-use "stdio.h")\n(import-use "time.h")\n(import-use io)\n(defn main ():i32 (print O_RDONLY " " O_WRONLY " " O_CREAT " " O_TRUNC " " O_APPEND " " SEEK_SET " " CLOCKS_PER_SEC "\\n") (return 0))\n' \
    > "$d/posix.nuc"
  if ! clang "$d/ref.c" -o "$d/ref" 2>/dev/null; then
    echo "PASS  s17-cmacro-posix (SKIP: no clang to produce a reference)"
  elif ! ./build/nucleusc "$d/posix.nuc" -o "$d/posix" 2>"$d/posix.err"; then
    echo "FAIL  s17-cmacro-posix (compile error)"
    sed 's/^/    /' "$d/posix.err" | head -4
    bad=1
  else
    want="$("$d/ref")"
    got="$("$d/posix")"
    if [ "$got" != "$want" ]; then
      echo "FAIL  s17-cmacro-posix (does not match the C compiler)"
      echo "    cc:  $want"
      echo "    nuc: $got"
      bad=1
    fi
    [ "$bad" = 0 ] && echo "PASS  s17-cmacro-posix"
  fi

  rm -rf "$d"
}
spawn run_platform_constants

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
