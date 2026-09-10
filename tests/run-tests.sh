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
# unit's identity everywhere it matters: `run_target_triple <triple>`,
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
  # together — the same separate-compilation shape the `.nuch` units in
  # tests/suite-modules.nuc use, which is also the only way to spell a
  # QUALIFIED call to a method.
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
# design/global-init.md §4.2. The rejections are rows of tests/manifest/diagnostics.sexp;
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
# is host-dependent for a system header, so the manifest row pins only the message
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
# SCOPE diagnostic. The manifest row already pins the head and the line; the
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

# The `examples/*.nuc` and `tests/repl/*.in` golden-output loops that stood here
# are `tests/nuctests.nuc`'s, since Stage 18 TF-6 category (b). They discover
# their inputs the same way, with `read-dir` in place of the glob.

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

spawn check_long x86_64-pc-linux-gnu    i64 i64   # LP64
spawn check_long aarch64-apple-darwin   i64 i64   # LP64
spawn check_long i386-pc-linux-gnu      i32 i64   # ILP32
spawn check_long x86_64-pc-windows-msvc i32 i64   # LLP64

spawn run_abi_subtest

spawn run_layout_subtest


spawn run_closure_cheader

spawn run_box_cheader

spawn run_s1_sugar_rets


spawn run_s1_block


#
# Stage 15 W9 item 8 refines the FIRST category only: a narrowing whose operand
# is a literal that provably fits is not lossy. `as-lossy.nuc` above narrows a
# parameter — an unknown runtime value — and so is unaffected, which is the
# distinction being pinned. The accept side RUNS (an exit-0 compile would not
# catch a sign error in the range test); the two rejects hold the boundary at
# magnitude and at sign.
spawn run_w9_as_literal_narrowing

# W9 item 30 does the same for f64->f32, and the two rejects hold the two edges
# the ruling draws. `-inexact` is the VALUE edge: 3.14 is a literal that does not
# round-trip, so admitting it would make `as` round silently. `-runtime` is the
# KNOWLEDGE edge: a parameter is unknown, so the widths alone decide and the
# original rule stands. `-global-inexact` pins that `defvar-init-ir`'s fold
# reaches the same verdict with the same wording — it is a second asker of the
# rule, and a second asker that re-derives is what this stage keeps finding.
spawn run_w9_as_float_literal_narrowing

spawn run_w9_bool_unsigned
spawn run_w9_unsigned_index
spawn run_w9_arg_coerce
spawn run_w9_dyn_solitary
spawn run_s16_se_template_ref
spawn run_s16_fp2_indirect_call
spawn run_s16_fp4_cheader_fnptr
spawn run_s16_fp5_cheader_fnptr
spawn run_s16_sv1_struct_value_receiver
spawn run_s16_c1_bare_unsigned


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


# The declaration line inside the message must be a real one — the header:line
# provenance is recovered from clang -E's linemarkers, and a 0 there would be as
# useless as the `:0:` W4a removed from the location prefix.
spawn run_w3a_opaque_provenance
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

# --- Stage 15 W4e: docs/stdlib.md's availability table is generated ---------
spawn run_stdlib_table
spawn run_headers_generated
spawn run_cstr_residue


# W9 item 18: a function pointer is one `ptr` register, so `=` / `!=` against
# null, against another slot, or against a function symbol is machine identity.
spawn run_w9_fnptr_compare
# W9 item 19, the storage half of the same sentence: one `ptr` register is one
# TARGET pointer wide, so no fn-pointer slot may claim `align 1`.
spawn run_w9_fnptr_align
# W9 item 20: the literal `null` reaches a fn-pointer slot in every position
# (let init, set!, field store, explicit return), not just `defvar`. The exit
# code is a bitmask of the five "is it unset?" answers plus two round-trips, so
# a slot that compiles but holds the wrong value fails rather than passing.
spawn run_w9_fnptr_null_init


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
spawn run_w9_source_outranks_header
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

# --- Stage 15 W8 G-3: @__nucleus_init ----------------------------------------
# design/global-init.md §5 "G-3". The positive matrix is
# examples/g3-runtime-init.nuc (values printed, not merely compiled). The two
# multi-file / IR-level checks are here, and the AVR half — the `none`
# mechanism's located refusal, plus zero-cost measured on the target the
# requirement was stated for — is in tests/run-avr-test.sh.
spawn run_g3_zero_cost
spawn run_g3_library

# --- Stage 15 W8 G-4: the initializer-ordering diagnostic --------------------
# design/global-init.md §4.2. The accepting half — including the `(addr-of g)`
# decision and the known laundered-through-a-call gap — is run_g4_order above,
# by VALUE. Here: the refusals, each of which must name BOTH sites at real
# file:line:s. Note the second argument of each pair pins the NOTE's location,
# i.e. the target `defvar`, so one call covers both halves of "name both sites".
spawn run_g4_order


# --- Stage 15 W5e: `defn-` name isolation -----------------------------------
# design/stage15-stress-test/ergonomics.md §W5e. Sequenced after W1 because it is
# the same key scheme: W1a's whole-graph signature prescan is what makes a
# private name's key final before any form is emitted.
spawn run_w5e_private_isolated
spawn run_w5e_still_rejects


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

# --- Stage 15 B2b: globals + the `unsafe` built-in namespace -------------------
spawn run_b2b_prefixed_values

# --- Stage 15 B5: the shared binding interface --------------------------------
spawn run_b5_protocol_kind
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
