#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

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

# spawn <func> [args...] — run one test unit in the background, then block
# until a job slot frees if the pool is full. Per-unit stdout+stderr is
# captured to a numbered result file; ordering is recovered from UNIT_NAMES.
spawn() {
  local id="_$_seq"
  _seq=$((_seq + 1))
  UNIT_NAMES+=("$id")
  "$@" >"$RESULTS_DIR/${id}.out" 2>&1 &
  _job_count=$((_job_count + 1))
  while [ "$_job_count" -ge "$NUCLEUS_TEST_JOBS" ]; do
    wait -n || true
    _job_count=$((_job_count - 1))
  done
}

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

# Cross-target emission: each triple in the Phase-B matrix must produce IR
# carrying the matching `target triple` line. Guards against a backend not
# being registered (which makes --emit-llvm reject the triple).
run_target_triple() {  # <triple>
  local triple="$1" tmpfile
  tmpfile="$(mktemp)"
  ./build/nucleusc --target="$triple" --emit-llvm examples/hello.nuc > "$tmpfile" 2>/dev/null || true
  if grep -q "target triple = \"$triple\"" "$tmpfile"; then
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
  if grep -q 'target triple = "avr"' "$tmpfile" \
     && grep -q 'target datalayout = "e-P1-p:16:8-' "$tmpfile"; then
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
  if grep -q 'target datalayout = "e-P1-p:16:8-' "$tmpfile" \
     && grep -q 'ptrtoint ptr .* to i16' "$tmpfile" \
     && grep -q 'call ptr @malloc(i64 22)' "$tmpfile" \
     && grep -q 'store ptr %a, ptr %p4, align 1' "$tmpfile" \
     && ! grep -q 'call ptr @malloc(i64 40)' "$tmpfile"; then
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
  if grep -q '^  .*i64' "$avr_ir"; then
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
  elif grep -q 'icmp eq ptr %t[0-9]*, @twice' "$ir" \
    && grep -q 'icmp ne ptr null, %t[0-9]*' "$ir"; then
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
  elif grep -q '^@fn-global = global ptr null, align 8' "$ir" \
    && grep -q '%loc.addr.[0-9]* = alloca ptr, align 8' "$ir" \
    && grep -q '%h.addr = alloca ptr, align 8' "$ir"; then
    echo "PASS  w9-fnptr-align-ir"
  else
    echo "FAIL  w9-fnptr-align-ir (a global/local/param fn-pointer slot is not pointer-aligned)"
    grep -nE '^@fn-global |\.addr[0-9.]* = alloca ptr' "$ir" | head -6 | sed 's/^/    /'
  fi

  # Item 15's rule, on item 19's operand: the width is the TARGET's, not 8.
  if grep -q '^@fn-global = global ptr null, align 4' "$ir32" \
    && grep -q '%loc.addr.[0-9]* = alloca ptr, align 4' "$ir32"; then
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
  elif grep -q '^@g-hook = global ptr null' "$ir" \
    && grep -q 'store ptr null, ptr %loc.addr' "$ir" \
    && grep -q 'ret ptr null' "$ir"; then
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
  if [ -s "$elf" ] && file "$elf" 2>/dev/null | grep -q 'Atmel AVR 8-bit'; then
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
  if [ ! -s "$elf" ] || ! file "$elf" 2>/dev/null | grep -q 'Atmel AVR 8-bit'; then
    echo "FAIL  avr5-isr (no linked .elf produced)"
    rm -f "$elf"
    return 0
  fi
  dis="$(avr-objdump -d "$elf" 2>/dev/null)"
  # (a) the vector table jumps to our handler; (b) the handler ends in reti.
  # The reti check inspects only the __vector_13 function body (from its label to
  # the next blank line) so a stray reti elsewhere can't spoof the result.
  if printf '%s\n' "$dis" | grep -q 'jmp.*<__vector_13>' \
     && printf '%s\n' "$dis" | awk '/<__vector_13>:/{f=1} f&&/\treti/{print;exit}' | grep -q 'reti'; then
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
  if printf '%s' "$avr_err" | grep -qF "cannot use function 'add' as a value on this target" \
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
  if printf '%s' "$ir" | grep -q '@answer = constant i32 42' \
     && printf '%s' "$ir" | grep -q '@mutable-count = global i32 0'; then
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
  printf '%s' "$annot_avr" | grep -qF "$msg" || pass=0
  ./build/nucleusc --emit-llvm tests/fixtures/avr7-f64-annot.nuc >/dev/null 2>&1 || pass=0
  # 2. "double" spelling — AVR rejects.
  dbl_avr="$(./build/nucleusc --target=avr --mcpu=attiny1634 --emit-llvm \
    tests/fixtures/avr7-f64-annot.nuc 2>&1 >/dev/null || true)"
  printf '%s' "$dbl_avr" | grep -qF "$msg" || pass=0
  # 3. bare float literal default (no f64 text) — AVR rejects via emit-float,
  #    host accepts.
  lit_avr="$(./build/nucleusc --target=avr --mcpu=attiny1634 --emit-llvm \
    tests/fixtures/avr7-f64-literal.nuc 2>&1 >/dev/null || true)"
  printf '%s' "$lit_avr" | grep -qF "$msg" || pass=0
  ./build/nucleusc --emit-llvm tests/fixtures/avr7-f64-literal.nuc >/dev/null 2>&1 || pass=0
  if [ "$pass" -eq 1 ]; then
    echo "PASS  avr7-f64-rejected (annotation + bare literal; host accepts)"
  else
    echo "FAIL  avr7-f64-rejected (AVR must reject :f64 and 1.5; host must accept)"
  fi
  # 4. f32 is allowed on AVR (emits `float`).
  if ./build/nucleusc --target=avr --mcpu=attiny1634 --emit-llvm \
       tests/fixtures/avr7-f32.nuc 2>/dev/null | grep -q 'float'; then
    echo "PASS  avr7-f32-allowed"
  else
    echo "FAIL  avr7-f32-allowed (f32 must compile on AVR)"
  fi
  # 5. i64 is allowed on AVR (emits an i64 multiply; libgcc __muldi3 at link).
  if ./build/nucleusc --target=avr --mcpu=attiny1634 --emit-llvm \
       tests/fixtures/avr7-i64.nuc 2>/dev/null | grep -q 'mul nsw i64'; then
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
  printf '%s' "$avr_ir" | grep -q 'define i16 @sum(ptr ' || pass=0
  printf '%s' "$avr_ir" | grep -q 'sret(%Point)' || pass=0
  printf '%s' "$avr_ir" | grep -q 'byval' && pass=0
  # Host: the same <=16-byte struct is register-coerced (eightbyte model active),
  # proving the AVR bypass is target-keyed (host param is NOT a plain ptr).
  printf '%s' "$host_ir" | grep -q 'define i16 @sum(i32 ' || pass=0
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
  if grep -q 'target triple = "riscv64-unknown-linux-gnu"' "$tmpfile" \
     && grep -q 'target datalayout = "e-m:e-p:64:64-' "$tmpfile" \
     && grep -q '!"target-abi", !"lp64d"' "$tmpfile"; then
    echo "PASS  riscv-emit"
  else
    echo "FAIL  riscv-emit (datalayout/triple/module-flags)"
  fi
  if command -v llc >/dev/null 2>&1; then
    asm="$(mktemp)"
    # The asm mnemonic column is tab-indented; anchor at line start so a `.globl`
    # of a symbol containing "mul" can't false-match the multiply instruction.
    if llc -mtriple=riscv64 -mattr=+m,+a,+f,+d,+c -filetype=asm "$tmpfile" -o "$asm" 2>/dev/null \
       && grep -qE '^[[:space:]]*mul[[:space:]]' "$asm" \
       && grep -q 'fadd\.d' "$asm" \
       && ! grep -q '__muldi3' "$asm" \
       && ! grep -q '__adddf3' "$asm"; then
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
  if grep -q '^define float @f_f1(float %v\.arg)' "$rv" \
     && grep -q '^define { double, double } @f_dd(double %v\.arg\.0, double %v\.arg\.1)' "$rv" \
     && grep -q '^define { float, float } @f_farr2(float %v\.arg\.0, float %v\.arg\.1)' "$rv" \
     && grep -q '^define { float, float } @f_nest(float %v\.arg\.0, float %v\.arg\.1)' "$rv" \
     && grep -q '^define { i32, float } @f_mixed(i32 %v\.arg\.0, float %v\.arg\.1)' "$rv" \
     && grep -q '^define { float, i32 } @f_mixedrev(float %v\.arg\.0, i32 %v\.arg\.1)' "$rv" \
     && grep -q '^define { i64, double } @f_longmix(i64 %v\.arg\.0, double %v\.arg\.1)' "$rv" \
     && grep -q '^define i64 @f_pair(i64 %v\.arg)' "$rv"; then
    echo "PASS  rv6-flatten-rules"
  else
    echo "FAIL  rv6-flatten-rules (riscv64 lp64d flattening, riscv-fp-abi.md §1)"
    grep -E '^define .*@f_' "$rv" | sed 's/^/    /'
  fi

  # §4: the same aggregate flattens while its registers are free and takes the
  # integer convention once they are not — separately for FPRs, GPRs, and the
  # GPR the hidden sret pointer spends before the first argument.
  if grep -q '^define i32 @fpr7_mixed(.*double %g\.arg, i32 %m\.arg\.0, float %m\.arg\.1)' "$rv" \
     && grep -q '^define i32 @fpr8_mixed(.*double %h\.arg, i64 %m\.arg)' "$rv" \
     && grep -q '^define i32 @fpr6_dd(.*double %f\.arg, double %m\.arg\.0, double %m\.arg\.1)' "$rv" \
     && grep -q '^define i32 @fpr7_dd(.*double %g\.arg, i64 %m\.arg\.0, i64 %m\.arg\.1)' "$rv" \
     && grep -q '^define i32 @gpr7_mixed(.*i64 %g\.arg, i32 %m\.arg\.0, float %m\.arg\.1)' "$rv" \
     && grep -q '^define i32 @gpr8_mixed(.*i64 %h\.arg, i64 %m\.arg)' "$rv" \
     && grep -q '^define i32 @gpr8_f1(.*i64 %h\.arg, float %m\.arg)' "$rv" \
     && grep -q '^define i32 @gpr8_dd(.*i64 %h\.arg, double %m\.arg\.0, double %m\.arg\.1)' "$rv" \
     && grep -q '^define void @sret6_mixed(ptr sret(%Big).*i64 %f\.arg, i32 %m\.arg\.0, float %m\.arg\.1)' "$rv" \
     && grep -q '^define void @sret7_mixed(ptr sret(%Big).*i64 %g\.arg, i64 %m\.arg)' "$rv"; then
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
     && ! printf '%s' "$vcall" | grep -qE '(float|double) %'; then
    echo "PASS  rv6-variadic-integer-convention"
  else
    echo "FAIL  rv6-variadic-integer-convention (a vararg aggregate was flattened into FP registers)"
    printf '%s\n' "$vcall" | sed 's/^/    /'
  fi

  # Anti-leak control: x86_64 SysV packs {float[2]} into one SSE eightbyte and
  # {i32,f32} into one INTEGER eightbyte — the riscv rules must not reach it.
  if grep -q '^define <2 x float> @f_farr2(<2 x float> %v\.arg)' "$x86" \
     && grep -q '^define <2 x float> @f_nest(<2 x float> %v\.arg)' "$x86" \
     && grep -q '^define i64 @f_mixed(i64 %v\.arg)' "$x86" \
     && grep -q '^define i64 @f_mixedrev(i64 %v\.arg)' "$x86" \
     && grep -q '^define i32 @fpr8_mixed(.*double %h\.arg, i64 %m\.arg)' "$x86"; then
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
  if grep -q "declare $want_l @lfn(" "$tmpfile" \
     && grep -q "declare $want_ll @llfn(" "$tmpfile"; then
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
  if grep -q '^(ns geom)' "$ns6_dir/lib.nuch"; then
    echo "PASS  n6-nuch-carries-ns"
  else
    echo "FAIL  n6-nuch-carries-ns"
  fi

  # 2. The cheader emits the C-legal mangled name, never the slash form.
  if grep -q 'geom__area' "$ns6_dir/lib.h" && ! grep -q 'geom/area' "$ns6_dir/lib.h"; then
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
  # and the two sibling sites below used to write `(fmt:CStr &rest args:i32)`,
  # which did nothing but add two phantom i32 parameters to the declaration: the
  # calls here pass 3-6 arguments to it. `&rest` in a declaration is now refused.)
  cat > "$ns6_dir/main.nuc" <<EOF
(exclude-prelude)
(import-prefixed "$ns6_dir/lib.nuch" g)
(declare printf (fmt:CStr):i32)
(defn main () :i32
  (printf "area=%d perimeter=%d\n" (g/area 6 7) (g/perimeter 6 7))
  (return 0))
EOF
  ./build/nucleusc --emit-llvm "$ns6_dir/main.nuc" > "$ns6_dir/main.ll" 2>/dev/null || true
  if grep -q 'call i32 @geom__area' "$ns6_dir/main.ll"; then
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
(defn pt-sum ((p (ref Pt))):i32 (return (+ (_get p x) (_get p y))))
EOF
  ./build/nucleusc --emit-nuch    "$ns6_dir/tylib.nuc" > "$ns6_dir/tylib.nuch" 2>/dev/null || true
  ./build/nucleusc --emit-cheader "$ns6_dir/tylib.nuc" > "$ns6_dir/tylib.h"    2>/dev/null || true
  ./build/nucleusc --emit-llvm    "$ns6_dir/tylib.nuc" > "$ns6_dir/tylib.ll"   2>/dev/null || true
  if grep -qF '%gt__Pt = type' "$ns6_dir/tylib.ll" \
     && grep -qF '} gt__Pt;' "$ns6_dir/tylib.h" \
     && grep -qF '(ns gt)' "$ns6_dir/tylib.nuch" \
     && grep -qF '(defstruct Pt ' "$ns6_dir/tylib.nuch"; then
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
  if grep -qF '(declare full? ((n i32)) :i32)' "$sm3_dir/lib.nuch" \
     && grep -qF '(declare push! ((n i32)) :i32)' "$sm3_dir/lib.nuch" \
     && grep -qF '(defmethod "@even_QMARK.i32"' "$sm3_dir/lib.nuch" \
     && grep -qF '(defmethod "@even_QMARK.i64"' "$sm3_dir/lib.nuch"; then
    echo "PASS  sm3-nuch-roundtrip"
  else
    echo "FAIL  sm3-nuch-roundtrip"
  fi

  # 2. The lib object defines the mnemonic-mangled symbols.
  if grep -qF 'define i32 @full_QMARK' "$sm3_dir/lib.ll" \
     && grep -qF 'define i32 @push_BANG' "$sm3_dir/lib.ll" \
     && grep -qF 'define i32 @even_QMARK.i32' "$sm3_dir/lib.ll" \
     && grep -qF 'define i32 @even_QMARK.i64' "$sm3_dir/lib.ll"; then
    echo "PASS  sm3-lib-symbols"
  else
    echo "FAIL  sm3-lib-symbols"
  fi

  # 3. The cheader names the real C-legal function symbols, never the illegal `full?`.
  if grep -qF 'full_QMARK(' "$sm3_dir/lib.h" \
     && grep -qF 'push_BANG(' "$sm3_dir/lib.h" \
     && ! grep -qF 'full?' "$sm3_dir/lib.h"; then
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
  if grep -qF 'call i32 @full_QMARK' "$sm3_dir/main.ll" \
     && grep -qF 'call i32 @push_BANG' "$sm3_dir/main.ll" \
     && grep -qF 'call i32 @even_QMARK.i32' "$sm3_dir/main.ll" \
     && grep -qF 'call i32 @even_QMARK.i64' "$sm3_dir/main.ll"; then
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
  if grep -qF '} Full_QMARK;' "$sm3_dir/types.h" \
     && grep -qF '} Push_BANG;' "$sm3_dir/types.h" \
     && grep -qF '} Shape_QMARK;' "$sm3_dir/types.h" \
     && grep -qF 'struct Full_QMARK* f' "$sm3_dir/types.h"; then
    echo "PASS  sm3-cheader-typenames"
  else
    echo "FAIL  sm3-cheader-typenames"
  fi
  rm -rf "$sm3_dir"
}

# Single-fixture rejection checks: compiling <fixture> must FAIL with <pattern>
# on stderr. Each is independent (its own nucleusc invocation), so each is its
# own job. grep -qF is safe for all patterns below (none carry regex metachars).
run_reject() {  # <name> <fixture> <pattern>
  local name="$1" fixture="$2" pattern="$3" err
  err="$(./build/nucleusc --emit-llvm "$fixture" 2>&1 >/dev/null || true)"
  # Stage 15 W4a: a rejection that reports `:0:` is a regression even when the
  # message text is right. Checked here so every existing and future rejection
  # test carries the location guarantee for free.
  if printf '%s' "$err" | grep -q ':0:'; then
    echo "FAIL  $name (diagnostic reports line 0)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | grep -qF "$pattern"; then
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
  if printf '%s' "$err" | grep -qF "$loc" && printf '%s' "$err" | grep -qF "$pattern"; then
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
    if printf '%s' "$err" | grep -q ':0:'; then
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
  if printf '%s' "$err" | grep -q ':0:'; then
    echo "FAIL  w4a-sibling-forward (diagnostic reports line 0)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif [ -z "$err" ] || printf '%s' "$err" | grep -q 'w4a-sib-x.nuc:2:'; then
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
  if printf '%s' "$err" | grep -q "duplicate definition of 'w1-dupe'"; then
    echo "PASS  w1-duplicate-rejected"
  else
    echo "FAIL  w1-duplicate-rejected"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi

  printf '(import w1-dup-a)\n(defn main ():i32 (return (w1-nowhere)))\n' > "$d/w1-missing.nuc"
  err="$(./build/nucleusc -I "$d" --emit-llvm "$d/w1-missing.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | grep -q 'unknown: w1-nowhere'; then
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
  if printf '%s' "$err" | grep -q ':0:'; then
    echo "FAIL  $name (diagnostic reports line 0)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | grep -qF "$loc" && printf '%s' "$err" | grep -qF "$pattern"; then
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
  if printf '%s' "$err" | grep -q ':0:'; then
    echo "FAIL  $name (diagnostic reports line 0)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | grep -qF "$pattern"; then
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
    if grep -q "run-time initializer" "$d/err"; then
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

  # Two properties this unit would be hollow without: the prelude closure really
  # is duplicated in both objects (else there was no collision to fix), and the
  # `w9-side-bump` call really is undefined in main.o (else nothing crosses the
  # object boundary and the shared counter proves only that one object works).
  if [ "$(nm "$d/main.o" "$d/side.o" 2>/dev/null | grep -cE ' [WV] arena-init$')" = 2 ] \
     && nm "$d/main.o" 2>/dev/null | grep -qE '^ +U w9-side-bump$'; then
    echo "PASS  w9-multi-object-weak-prelude"
  else
    echo "FAIL  w9-multi-object-weak-prelude (want a weak arena-init in both, and an undefined w9-side-bump in main.o)"
    nm "$d/main.o" "$d/side.o" 2>/dev/null | grep -E 'arena-init|w9-side-bump' | sed 's/^/    /'
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
  if grep -qE '^define i32 @w9-own\(' "$d/own.ll" \
     && grep -qE '^define weak_odr i32 @w9-get\(' "$d/own.ll" \
     && grep -qE '^@w9-count = weak_odr global ' "$d/own.ll" \
     && grep -qE '^define internal i32 @w9own_p[0-9]+__w9-secret\(' "$d/own.ll"; then
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
  if printf '%s' "$out" | grep -qF "dshare.nuc:3: warning: defvar: 'd-runs' has a run-time initializer"; then
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

  if grep -qxF 'extern int32_t counter;' "$d/clib.h" \
     && grep -qxF 'extern const int32_t limit;' "$d/clib.h" \
     && grep -qxF 'extern int64_t tick_count asm("tick-count");' "$d/clib.h" \
     && grep -qxF 'extern struct CRec rec_val asm("rec-val");' "$d/clib.h" \
     && ! grep -q 'hidden' "$d/clib.h"; then
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
  if grep -qF '/* m-skip: uses a defunion-template instance type; not exported */' "$d/clib.h" \
     && grep -qF '/* arr-skip: type has no C spelling here; not exported */' "$d/clib.h"; then
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
  if grep -qxF 'extern size_t kc;' "$d/sz.h" \
     && grep -qxF 'ptrdiff_t take(size_t n);' "$d/sz.h" \
     && ! grep -q 'struct usize' "$d/sz.h"; then
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
(defn my-rec-sum (r:ptr:My-Rec):i32 (return (+ (r a-field) 100)))
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
  if grep -qxF 'int32_t my_bump(int32_t n_arg) asm("my-bump");' "$d/hlib.h" \
     && grep -qxF 'int32_t plain(int32_t n);' "$d/hlib.h" \
     && grep -qxF '#define BUF_LEN 4' "$d/hlib.h" \
     && grep -qF 'int32_t xs[BUF_LEN];' "$d/hlib.h" \
     && grep -qF 'My_Uni_uni_b = 1' "$d/hlib.h" \
     && grep -qF 'My_Col_my_green = 1' "$d/hlib.h"; then
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
  if [ -f "$d/hlib.o" ] && nm "$d/hlib.o" | grep -qE ' T my-bump$' \
     && nm "$d/hlib.o" | grep -qE ' D my-count$' \
     && ! nm "$d/hlib.o" | grep -qE ' (T|D) my_bump$'; then
    echo "PASS  w9-cheader-symbols-keep-hyphens"
  else
    echo "FAIL  w9-cheader-symbols-keep-hyphens"
    [ -f "$d/hlib.o" ] && nm "$d/hlib.o" | grep -E 'my.bump|my.count' | sed 's/^/    /'
  fi
  rm -rf "$d"
}

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
(defn w9sh-get ((r (ref W9Rec))):i32 (return (_get r n)))
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
  if printf '%s' "$ir" | grep -qE '^define .*@shn__w9sh-get\(' ; then
    echo "PASS  w9-import-prefers-source"
  else
    echo "FAIL  w9-import-prefers-source (header won, or the symbol moved)"
    printf '%s' "$ir" | grep -E 'w9sh-get' | sed 's/^/    /' | head -4
  fi

  # 2. The diagnostic side of the same ruling: the sibling header must not be
  #    named as an unreachable definer, and the better tier must survive.
  err="$(./build/nucleusc --emit-llvm -I "$d/l" "$d/w9shuse.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | grep -qF "w9sh.nuch"; then
    echo "FAIL  w9-sibling-header-not-unreachable (named the header for a library the unit imports)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | grep -qF "defined in namespace 'shn'" \
       && printf '%s' "$err" | grep -qF "note: write 'shp/W9Rec' here"; then
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

# The couplings a legal cycle still cannot satisfy. Each is emission-time — a
# cycle member's body is emitted BEFORE the rest of the file it back-imports, so
# anything that file defines after its own `import` has not run yet. Every one
# of these used to fail with a message that blamed the wrong thing:
#   macro/const/enum → "not defined anywhere in this compilation unit" (it is);
#   layout           → "no field 'x' on struct 'S'" (it has that field), or, for
#                      a by-value struct at an ABI boundary, an `i0` aggregate
#                      and an UNLOCATED "failed to parse generated IR";
#   prefix alias     → "not defined anywhere" for a name that is in the unit.
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

  # 3a. A field access on a struct the partner has not laid out yet.
  printf '(import w1-scb)\n(defstruct W1SC\n  x:i32\n  y:i32)\n(defn w1-sca ():i32 (return 1))\n' > "$d/w1-sca.nuc"
  printf '(import w1-sca)\n(defn w1-scb (p:ptr:W1SC):i32 (.set! p x 11) (return (p x)))\n' > "$d/w1-scb.nuc"
  printf '(import w1-sca)\n(defn main ():i32 (return 0))\n' > "$d/w1-scm.nuc"
  w1_reject_multi w1d-cycle-layout-diagnosed "$d" "$d/w1-scm.nuc" \
    "field assignment: 'W1SC' has no layout at this point"

  # 3b. A struct literal — nfields is 0, so every initializer looked like one
  # too many.
  printf '(import w1-lcb)\n(defstruct W1LC\n  x:i32\n  y:i32)\n(defn w1-lca ():i32 (return 1))\n' > "$d/w1-lca.nuc"
  printf '(import w1-lca)\n(defn w1-lcb ():i32 (let (v:W1LC (W1LC 1 2)) (return 0)))\n' > "$d/w1-lcb.nuc"
  printf '(import w1-lca)\n(defn main ():i32 (return 0))\n' > "$d/w1-lcm.nuc"
  w1_reject_multi w1d-cycle-structlit-diagnosed "$d" "$d/w1-lcm.nuc" \
    "struct literal: 'W1LC' has no layout at this point"

  # 3c. The silent one: a by-value struct parameter. abi-classify sized the
  # unlaid-out struct at 0 and emitted `define … @f(i0 %v.arg)` against a call
  # site that passed two i64s. The only symptom was an unlocated LLVM parse
  # error thousands of lines away.
  printf '(import w1-bcb)\n(defstruct W1BC\n  x:i32\n  y:i32\n  z:i32\n  w:i32)\n(defn w1-bca ():i32 (return 1))\n' > "$d/w1-bca.nuc"
  printf '(import w1-bca)\n(defn w1-bcb (v:W1BC):i32 (return 7))\n' > "$d/w1-bcb.nuc"
  printf '(import w1-bca)\n(defn main ():i32 (return 0))\n' > "$d/w1-bcm.nuc"
  w1_reject_multi w1d-cycle-byval-diagnosed "$d" "$d/w1-bcm.nuc" \
    "defn parameter: 'W1BC' has no layout at this point"

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
  if printf '%s' "$err" | grep -q ':0:'; then
    echo "FAIL  w5e-public-collision-rejected (diagnostic reports line 0)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | grep -qF "duplicate definition of 'w5e-pub'" \
    && printf '%s' "$err" | grep -qF "$d/w5e-ca.nuc:1" \
    && printf '%s' "$err" | grep -qF "$d/w5e-cb.nuc:1" \
    && printf '%s' "$err" | grep -qF 'a public name must be unique'; then
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
  if printf '%s' "$err" | grep -q ':0:'; then
    echo "FAIL  w5e-ns-private-collision-rejected (diagnostic reports line 0)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | grep -qF "duplicate definition of 'w5e-nsh'" \
    && printf '%s' "$err" | grep -qF "$d/w5e-na.nuc:2" \
    && printf '%s' "$err" | grep -qF "$d/w5e-nb.nuc:2" \
    && printf '%s' "$err" | grep -qF "private to its NAMESPACE" \
    && printf '%s' "$err" | grep -qF "namespace 'w5eg'"; then
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
  if printf '%s' "$err" | grep -qF "import: prefix 'w1-ppa' is already bound to"; then
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
  if printf '%s' "$err" | grep -q 'undefined type'; then
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
  if printf '%s' "$ir" | grep -q '^define weak_odr ptr @append\.ptr\.ptr(' \
     && ! printf '%s' "$ir" | grep -qE '^define ([a-z_]+ )?ptr @append\(' ; then
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
  if printf '%s' "$err" | grep -q ':0:'; then
    echo "FAIL  w1c-unreachable-file (diagnostic reports line 0)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | grep -qF 'unknown: w1c-elsewhere — not defined anywhere in this compilation unit' \
     && printf '%s' "$err" | grep -qF "note: 'w1c-elsewhere' is defined in $d/w1c-other.nuc, which no import in this unit reaches"; then
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
  if printf '%s' "$err" | grep -qF 'unknown: w1c-absent-everywhere — not defined anywhere in this compilation unit' \
     && ! printf '%s' "$err" | grep -q 'note:'; then
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
  if printf '%s' "$err" | grep -q ':0:'; then
    echo "FAIL  w1c-unreachable-type (diagnostic reports line 0)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | grep -qF 'unknown type: W1cWidget — not defined anywhere in this compilation unit' \
     && printf '%s' "$err" | grep -qF "note: 'W1cWidget' is defined in $d/w1c-ty.nuc, which no import in this unit reaches"; then
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
  # struct names, not layouts, so `(_get r n)` fails ahead of the import for the
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
  if printf '%s' "$out" | grep -q 'spbad.nuc:1: error: import: cannot find'; then
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
  if printf '%s' "$ir" | grep -qF 'trunc i32 5 to i8' \
     && printf '%s' "$ir" | grep -qF '@w9as-g = global i8 9'; then
    echo "PASS  w9-as-literal-lowers-like-implicit"
  else
    echo "FAIL  w9-as-literal-lowers-like-implicit"
    echo "    want 'trunc i32 5 to i8' (value path) and '@w9as-g = global i8 9' (fold path)"
  fi
  rm -rf "$d"
}

# W9 item 9: `i1`/bool holds {0, 1}, and both numeric spellings must survive
# the range check that now rejects everything else. The IR assertion is the
# half a run cannot make: an initializer wrongly emitted as `global i1 true`
# for the written `1` would still exit 0.
run_w9_i1_literal_range() {
  local d ir
  d="$(mktemp -d)"
  w1_run w9-i1-literal-fits "$d" tests/fixtures/w9-i1-literal-fits.nuc 0
  ir="$(./build/nucleusc --emit-llvm tests/fixtures/w9-i1-literal-fits.nuc 2>/dev/null || true)"
  if printf '%s' "$ir" | grep -qF '@w9i1-one = global i1 1' \
     && printf '%s' "$ir" | grep -qF '@w9i1-zero = global i1 0'; then
    echo "PASS  w9-i1-literal-emits-written-value"
  else
    echo "FAIL  w9-i1-literal-emits-written-value"
    echo "    want '@w9i1-one = global i1 1' and '@w9i1-zero = global i1 0'"
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
  if printf '%s' "$err" | grep -q 'undefined: G0-NSK'; then
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
  if printf '%s' "$err" | grep -q 'undefined: G0-OTHER-SECRET'; then
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
      (g2off s (.& s cells)) (g2off s (.& s names)) (g2off s (.& s mark))))
  (return 0))
G2EOF
  if ! ./build/nucleusc --emit-cheader "$d/g2h.nuc" > "$d/g2h.h" 2>"$d/err"; then
    echo "FAIL  g2-cheader-array-field (--emit-cheader failed)"; sed 's/^/    /' "$d/err"; rm -rf "$d"; return 0
  fi
  # The declarator must be postfix C: `int32_t cells[4];`, and a named extent
  # must survive as the name (the header exports `#define G2N 3` beside it).
  if ! grep -q 'int32_t cells\[4\];' "$d/g2h.h" || ! grep -q 'names\[G2N\];' "$d/g2h.h"; then
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
    (aset! (b slots) 2 7)
    (.set! b n 9)
    (return (+ (aref (b slots) 2) (+ (b n) (+ (unsafe/cast i32 (sizeof G2Box)) (aref g2tab 1)))))))
G2EOF
  if ! ./build/nucleusc --emit-nuch "$d/g2lib.nuc" > "$d/g2lib.nuch" 2>"$d/err"; then
    echo "FAIL  g2-nuch-array-field (--emit-nuch failed)"; sed 's/^/    /' "$d/err"; rm -rf "$d"; return 0
  fi
  if ! grep -q '(array i32 G2K)' "$d/g2lib.nuch"; then
    echo "FAIL  g2-nuch-array-field (array field not exported)"; sed 's/^/    /' "$d/g2lib.nuch"; rm -rf "$d"; return 0
  fi
  if ! grep -q '(extern (g2tab (array i32 4)))' "$d/g2lib.nuch"; then
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
  if grep -qE '__nucleus_init|global_ctors' "$ll"; then
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
  if ! grep -q 'define internal void @__nucleus_init()' "$d/g3rt.ll" \
     || ! grep -q '@llvm.global_ctors = appending global' "$d/g3rt.ll"; then
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
  if ! grep -q '(extern (g3-lib-n i32))' "$d/inc/g3lib.nuch"; then
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
  if printf '%s' "$err" | grep -qF "$d/g4xb.nuc:1: error: defvar: the initializer for 'g4-xderived' names global 'g4-xbase'" \
     && printf '%s' "$err" | grep -qF "note: 'g4-xbase' is declared at $d/g4xa.nuc:2"; then
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
  if printf '%s' "$err" | grep -qF 'undefined: g0-absent-everywhere — not defined anywhere in this compilation unit' \
     && ! printf '%s' "$err" | grep -q 'note:'; then
    echo "PASS  g0-value-defined-nowhere"
  else
    echo "FAIL  g0-value-defined-nowhere"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi

  # W1c tier 2 for a VALUE: defined in a sibling file nothing imports.
  printf '(defconst G0-UNREACHED 5)\n' > "$d/g0-far.nuc"
  printf '(defn main ():i32 (return G0-UNREACHED))\n' > "$d/g0-farmain.nuc"
  err="$(./build/nucleusc -I "$d" --emit-llvm "$d/g0-farmain.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | grep -q ':0:'; then
    echo "FAIL  g0-value-unreachable-file (diagnostic reports line 0)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | grep -qF 'undefined: G0-UNREACHED — not defined anywhere in this compilation unit' \
     && printf '%s' "$err" | grep -qF "note: 'G0-UNREACHED' is defined in $d/g0-far.nuc, which no import in this unit reaches"; then
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
  if printf '%s' "$err" | grep -qF "redefinition of 'g0-dupg'" \
     && printf '%s' "$err" | grep -qF "$d/g0-da.nuc:1" \
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
  if printf '%s' "$err" | grep -qE 'declared at [^ ]*tests/fixtures/cheader-opaque\.h:11;'; then
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
  elif ! grep -q '^%Mix_Chunk = type' "$ir"; then
    echo "FAIL  w3a-sdl-mixer (defined Mix_Chunk has no LLVM layout)"
  elif ! grep -q '^%Mix_Chunk = type { i32, ptr, i32, i8 }$' "$ir"; then
    # W3c: `alen` (Uint32) and `volume` (Uint8) are typedefs of builtin
    # integers. Before the typedef chain was followed they were `ptr`, giving
    # `{ i32, ptr, ptr, ptr }` — a wrong layout, silently.
    echo "FAIL  w3a-sdl-mixer (Mix_Chunk field types did not resolve through their typedefs)"
    grep '^%Mix_Chunk = type' "$ir" | sed 's/^/    got: /'
  elif ! grep -q 'getelementptr inbounds %Mix_Chunk' "$ir"; then
    echo "FAIL  w3a-sdl-mixer (Mix_Chunk field access not emitted)"
  elif ! grep -q 'call void @Mix_FreeMusic(ptr ' "$ir"; then
    echo "FAIL  w3a-sdl-mixer (opaque handle not passed as a plain pointer)"
  elif grep -q '%Mix_Music' "$ir"; then
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
  if ! grep -q '^declare void @w3b_keep(ptr)$' "$ir"; then
    echo "FAIL  w3b-skip (representable declaration was not imported)"
    bad=1
  fi
  for sym in w3b_skip_byval w3b_skip_void w3b_skip_many; do
    if grep -q "@$sym" "$ir"; then
      echo "FAIL  w3b-skip ($sym reached the IR instead of being skipped)"
      bad=1
    fi
  done
  # `<header>:<line>:` — the line is the declaration's own, recovered from
  # clang -E's linemarkers, so an off-by-N in that tracking fails here.
  while IFS='|' read -r line want; do
    [ -z "$line" ] && continue
    if ! printf '%s' "$err" | grep -qF "w3b-skip.h:$line: warning: skipping C declaration $want"; then
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
  if ! grep -q '^declare void @_mm_clflush(ptr)$' "$ir"; then
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
EOF
  # A by-value use of an array typedef has no Nucleus representation: skipped,
  # never given the element type's ABI.
  if grep -q '@w3c_f_vec' "$ir"; then
    echo "FAIL  w3c-typedef (by-value array typedef reached the IR)"
    bad=1
  fi
  # ... and a *use* of the skipped name says why, naming the header and line —
  # this is where the skip is reported, instead of a warning on every build.
  got="$(printf '(import-use "./tests/fixtures/w3c-typedef.h")\n(defn main ():i32 (return (w3c_f_vec null)))\n' > "$ir.use.nuc"; ./build/nucleusc --emit-llvm "$ir.use.nuc" 2>&1 >/dev/null || true)"
  if ! printf '%s' "$got" | grep -q "w3c_f_vec' — its C header declaration was skipped (.*w3c-typedef.h:"; then
    echo "FAIL  w3c-typedef (use of a skipped declaration was not diagnosed)"
    printf '%s\n' "$got" | sed 's/^/    got: /'
    bad=1
  fi
  # Struct FIELD types resolve through their typedefs too — the shape W3a
  # recorded as newly observed (Mix_Chunk.volume, a Uint8, typed as ptr).
  if ! grep -q '^%w3c_fields = type { i8, i32, i64, ptr }$' "$ir"; then
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
    if ! grep -q '^declare i64 @lseek(i32, i64, i64)$' "$ir"; then
      echo "FAIL  w3c-precedence ($n: the header declaration won)"
      grep -n '@lseek' "$ir" | sed 's/^/    got: /'
      bad=1
    fi
    # The conflict warns, blamed on the .nuc declaration and naming the header.
    if ! printf '%s' "$err" | grep -q "w3c-prec-$n.nuc:.*declaration of 'lseek' as i64 (i32, i64, i64) conflicts with .*unistd.h:.*declares it as i64 (i32, i64, i32); the explicit declaration wins"; then
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
     || ! grep -q '^declare ptr @strchr(ptr, i64)$' "$ir"; then
    echo "FAIL  w3c-precedence (use-before-declare: wrong or duplicated strchr declaration)"
    grep -n '^declare .*@strchr(' "$ir" | sed 's/^/    got: /'
    bad=1
  fi
  if ! grep -qE 'call ptr @strchr\(ptr [^,]+, i64 ' "$ir"; then
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
# was correct exactly when the signature was all-`i32` — including the compiler's
# own `(declare repl_print_f64 (ptr):void)`, which declared an `i32` parameter
# against a C shim taking a pointer.
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
     || ! grep -q '^declare i64 @lseek(i32, i64, i32)$' "$ir"; then
    echo "FAIL  w3c-declare-header (match: wrong or duplicated lseek declaration)"
    grep -n '^declare .*@lseek(' "$ir" | sed 's/^/    got: /'
    bad=1
  fi
  if ! llvm-as "$ir" -o /dev/null 2>/dev/null; then
    echo "FAIL  w3c-declare-header (match: emitted IR does not parse)"
    bad=1
  fi

  err="$(./build/nucleusc --emit-llvm tests/fixtures/w3c-declare-header-conflict.nuc 2>&1 >"$ir" || true)"
  if ! printf '%s' "$err" | grep -q "w3c-declare-header-conflict.nuc:.*declaration of 'lseek' as i64 (i32, i64, i64) conflicts with .*unistd.h:.*declares it as i64 (i32, i64, i32); the explicit declaration wins"; then
    echo "FAIL  w3c-declare-header (conflict: a real mismatch was not diagnosed)"
    printf '%s\n' "$err" | sed 's/^/    got: /'
    bad=1
  fi
  if [ "$(grep -c '^declare .*@lseek(' "$ir")" != "1" ] \
     || ! grep -q '^declare i64 @lseek(i32, i64, i64)$' "$ir"; then
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
  if grep -q 'apply-closure: exposes a closure or type-erased box type; not C-callable, omitted' "$ch_dir/lib.h" \
     && ! grep -q 'apply-closure(' "$ch_dir/lib.h"; then
    echo "PASS  l8-cheader-omits-closure"
  else
    echo "FAIL  l8-cheader-omits-closure"
  fi

  # 2. the plain fn-pointer defn IS emitted to the header. W9 item 4: under its
  # sanitized C name, with the asm label that binds it back to `@plain-fn`.
  if grep -qxF 'int32_t plain_fn(int32_t x, int32_t y) asm("plain-fn");' "$ch_dir/lib.h"; then
    echo "PASS  l8-cheader-emits-fnptr"
  else
    echo "FAIL  l8-cheader-emits-fnptr"
  fi

  # 3. the definition site warns on stderr.
  if printf '%s' "$ch_warn" | grep -q "warning: 'apply-closure' exposes a closure or type-erased box type"; then
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
  if grep -q 'make-boxed: exposes a closure or type-erased box type; not C-callable, omitted' "$bch_dir/lib.h" \
     && ! grep -q 'make-boxed(' "$bch_dir/lib.h"; then
    echo "PASS  l13-cheader-omits-boxedfn"
  else
    echo "FAIL  l13-cheader-omits-boxedfn"
  fi

  # 5. dyn-typed prototype is OMITTED, with the explanatory comment in place.
  if grep -q 'use-dyn: exposes a closure or type-erased box type; not C-callable, omitted' "$bch_dir/lib.h" \
     && ! grep -q 'use-dyn(' "$bch_dir/lib.h"; then
    echo "PASS  l13-cheader-omits-dyn"
  else
    echo "FAIL  l13-cheader-omits-dyn"
  fi

  # 6. the plain fn-pointer defn IS emitted to the header. W9 item 4: under its
  # sanitized C name, with the asm label that binds it back to `@plain-fn`.
  if grep -qxF 'int32_t plain_fn(int32_t x, int32_t y) asm("plain-fn");' "$bch_dir/lib.h"; then
    echo "PASS  l13-cheader-emits-fnptr"
  else
    echo "FAIL  l13-cheader-emits-fnptr"
  fi

  # 7. the definition site warns on stderr (at least one box-typed defn fires).
  if printf '%s' "$bch_warn" | grep -q "warning:.*exposes a closure or type-erased box type"; then
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
  if grep -qF 'define ptr @lookup(' "$s1_sugar_ll" \
     && grep -qF 'define i64 @checked(' "$s1_sugar_ll" \
     && grep -qF 'define ptr @maybe-pt(' "$s1_sugar_ll" \
     && grep -qF 'define void @spin(ptr %m.arg) noreturn {' "$s1_sugar_ll"; then
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
  if grep -qF '(declare twice ((x i32)) :i32)' "$s1_dir/lib.nuch" \
     && grep -qF '(defmethod "@scale.i32" scale ((x i32)) :i32)' "$s1_dir/lib.nuch" \
     && grep -qF '(defn gmax ((a T) (b T) &where (Ord T)) :T' "$s1_dir/lib.nuch"; then
    echo "PASS  s1-nuch-export-shapes"
  else
    echo "FAIL  s1-nuch-export-shapes"
  fi

  # 3b. The cheader names the plain new-style prototypes correctly — and names an
  #     overloaded one the way the .nuch above already did (W9 item 26). The old
  #     `int32_t scale(int32_t x);` asserted a symbol the object never defines:
  #     `scale` is overloaded, so its methods are `@scale.i32` / `@scale.i64`.
  if grep -qF 'int32_t twice(int32_t x);' "$s1_dir/lib.h" \
     && grep -qF 'int32_t add3(int32_t a, int32_t b, int32_t c);' "$s1_dir/lib.h" \
     && grep -qF 'int32_t scale_i32(int32_t x) asm("scale.i32");' "$s1_dir/lib.h" \
     && grep -qF 'int64_t scale_i64(int64_t x) asm("scale.i64");' "$s1_dir/lib.h"; then
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
  if grep -qF 'define weak_odr i32 @gmax.i32.i32(' "$s1_dir/tmain.ll" \
     && grep -qF 'define weak_odr i64 @gmax.i64.i64(' "$s1_dir/tmain.ll" \
     && grep -qF 'call i32 @gmax.i32.i32(' "$s1_dir/tmain.ll"; then
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
  local out ec
  out="$(python3 scripts/gen-stdlib-table.py --check 2>&1)"
  ec=$?
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
    (return (b0-add b0-base (_get p x)))))
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
  if ! printf '%s' "$err" | grep -qF "unknown: zx/b1-inc — 'zx' is not in scope in this file"; then
    echo "FAIL  b1-prefix-not-visible-cross-file (wrong or missing diagnostic)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif ! printf '%s' "$err" | grep -qF "note: an import prefix is file-scoped:"; then
    echo "FAIL  b1-prefix-not-visible-cross-file (missing the file-scope note)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | grep -qF "not defined anywhere in this compilation unit"; then
    echo "FAIL  b1-prefix-not-visible-cross-file (degraded to the reachability message)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | grep -q ':0:'; then
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
  if ! printf '%s' "$err" | grep -qF "note: 'dp' is not in scope in this file"; then
    echo "FAIL  b2a-scope-diagnostic (missing the out-of-scope note)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif ! printf '%s' "$err" | grep -qF "In scope here: dpx."; then
    echo "FAIL  b2a-scope-diagnostic (note does not list the qualifiers in scope)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | grep -qF "not defined anywhere in this compilation unit"; then
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
(defn describe ((self (ref Cat))):i32 (return (+ 40 (self n))))
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
  if ! printf '%s' "$err" | grep -qF "undefined: b2bns/b2b-gv — 'b2bns' is not in scope in this file"; then
    echo "FAIL  b2b-prefixed-values-ns-refused (wrong or missing diagnostic)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | grep -qF "not defined anywhere in this compilation unit"; then
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

# W9 item 9: the width-1 arm of `int-literal-fits`. `i1` is a bool over {0, 1},
# so 5 and -1 are both out of range — the negative case is what pins the rule,
# since reading i1 as a 1-bit two's complement integer gives [-1, 0] and would
# invert both answers. The local fixture pins that the fix landed in the shared
# predicate rather than in `defvar-init-ir` alone.
spawn run_w9_i1_literal_range
spawn run_reject w9-i1-literal-too-big tests/fixtures/w9-i1-literal-too-big.nuc \
  "defvar: integer literal 5 does not fit i1"
spawn run_reject w9-i1-literal-negative tests/fixtures/w9-i1-literal-negative.nuc \
  "defvar: integer literal -1 does not fit i1"
spawn run_reject w9-i1-local-too-big tests/fixtures/w9-i1-local-too-big.nuc \
  "integer literal 5 does not fit i1"

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
  "tests/fixtures/w4a-suggest-spelling.nuc:4: error:" "unknown: printfx (did you mean 'printf'?)"
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
  "tests/fixtures/w3a-opaque-sizeof.nuc:8: error:" \
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
# and `&rest`/`&optional` are defn-only (the marker used to be counted as an
# extra i32 parameter, so the declared arity silently disagreed).
spawn run_reject_at w3c-declare-unknown-type tests/fixtures/w3c-declare-unknown-type.nuc \
  "tests/fixtures/w3c-declare-unknown-type.nuc:4: error:" "unknown type: NoSuchDeclParamType"
spawn run_reject_at w3c-declare-rest tests/fixtures/w3c-declare-rest.nuc \
  "tests/fixtures/w3c-declare-rest.nuc:6: error:" \
  "declare: '&rest' is not supported in a declaration"

# --- Stage 15 W4e: docs/stdlib.md's availability table is generated ---------
spawn run_stdlib_table
spawn run_headers_generated

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
  "tests/fixtures/w5d-elemless-not-inferred.nuc:11: error:" \
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
spawn run_w9_shared_init_warning
spawn run_w9_cheader_globals
spawn run_w9_cheader_identifiers
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
  ".set!: field 'xs': an (array T N) is storage, not a value"
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
# Here: the boundary the demotion must NOT cross. The selector falls back to a
# value reading only when the callee provably has no such field AND the name is
# a local; a genuine miss must still be reported.
spawn run_reject_at w7-local-not-a-field tests/fixtures/w7-local-not-a-field.nuc \
  "tests/fixtures/w7-local-not-a-field.nuc:8: error:" \
  "and 'k' is a local binding here, but a bare symbol in selector position always names a field"
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
# The legitimately variable arities: `&optional` is a band, `&rest` is a floor.
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
(defn b5-take ((h (ref bp/B5HiddenS))):i32 (return (h n)))
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
    (return (+ (+ (s n) usz) m))))
EOF
  # B3′: the public struct is reached through the prefix here too — the bare
  # spelling was the pre-R1 "types are globally visible" behaviour.
  cat > "$d/b5-pmain.nuc" <<'EOF'
(import-prefixed b5-pin bin)
(import-prefixed b5-plib bp)

(defn main ():i32
  (let (p:(ref bp/B5PublicS) (bp/B5PublicS 6))
    (return (+ (bin/b5-inside-sum) (+ (bp/b5-lib-ok) (- (p n) 5))))))
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
  if printf '%s' "$err" | grep -qF "extend: unknown protocol"; then
    echo "FAIL  b5-private-protocol-visible-inside (hidden from its own namespace)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | grep -qF "does not conform to protocol 'b5p/B5HiddenP'"; then
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
  if printf '%s' "$err" | grep -qF "(did you mean 'b5-suggest'?)"; then
    echo "FAIL  b5-did-you-mean-not-echo (suggested the spelling that just failed)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | grep -qF "(did you mean 'sx/b5-suggest'?)"; then
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
(defn b5-exp-fn ((s (ref B5ExpS))):i32 (return (+ 1 (s n))))
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
  if printf '%s' "$err" | grep -q ':0:'; then
    echo "FAIL  b7-export-overload-refused (diagnostic reports line 0)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | grep -qF "'b5-exp-ov' is a function" \
    && printf '%s' "$err" | grep -qF "that kind is not keyed by namespace"; then
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
  if printf '%s' "$err" | grep -qF "unknown: b7ns/b7-twice — 'b7ns' is not in scope in this file"; then
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
  if printf '%s' "$err" | grep -q ':0:'; then
    echo "FAIL  b7-macro-did-you-mean (diagnostic reports line 0)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | grep -qF "did you mean 'pm/b7-twice'?"; then
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
(defn sum-a ((v (ref Vector))):i32 (return (+ (_get v x) (_get v y))))
EOF
  cat > "$d/b3-vecb.nuc" <<'EOF'
(ns vb)
(defstruct Vector a:i32 b:i32 c:i32)
(defn sum-b ((v (ref Vector))):i32
  (return (+ (_get v a) (+ (_get v b) (_get v c)))))
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
    (return (_get p c))))
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
(defn area ((self (ref bx/Pt))):i32 (return (* (_get self x) (_get self y))))
(extend bx/Pt bx/Areal)
(defn main ():i32
  (with (v:(ref (Vector (ref bx/Pt))) (vector-new))
    (let (a:(ref bx/Pt) (bx/Pt 3 4) b:(ref bx/Pt) (bx/Pt 5 6) t:i32 0)
      (conj v a)
      (conj v b)
      (dotimes (i (unsafe/cast i32 (count v)))
        (set! t (+ t (_get (invoke v (as usize i)) x))))
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
  if ! printf '%s' "$err" | grep -qF "tests/fixtures/b3-type-ns-not-in-scope.nuc:18: error: unknown type: Fox — defined in namespace 'dp'"; then
    echo "FAIL  b3-type-ns-not-in-scope (wrong head or location)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif ! printf '%s' "$err" | grep -qF "note: write 'dpx/Fox' here"; then
    echo "FAIL  b3-type-ns-not-in-scope (note does not offer the writable spelling)"
    printf '%s\n' "$err" | sed 's/^/    /'
  elif printf '%s' "$err" | grep -qF "not defined anywhere in this compilation unit"; then
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
(defn describe ((self (ref Fox))):i32 (return (+ 3 (_get self n))))
(extend Fox Describe)
; Both directions across the boundary: a box this file MAKES and a box it TAKES.
(defn make-fox ((n i32)):(dyn Describe) (return (Fox n)))
(defn show ((b (dyn Describe))):i32 (return (+ 1 (describe b))))
EOF
  cat > "$d/b6-duse.nuc" <<'EOF'
(import-use allocator)
(import-prefixed b6-dlib dpx)
(defstruct Cat n:i32)
(defn describe ((self (ref Cat))):i32 (return (+ 10 (_get self n))))
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
     && grep -q '^define .*@w23b__describe(' "$d/w23b.ll"; then
    echo "PASS  w9-ns-symbol-ownership"
  else
    echo "FAIL  w9-ns-symbol-ownership"
  fi

  # 2. Neither namespace's method is suffixed: one method from one namespace is
  #    not an overload of anything, however the merged generic looks.
  if ! grep -qE '^define .*@w23[ab]__describe\.' "$d/w23b.ll"; then
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
       | grep -q 'w23b__describe(int64_t'; then
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
(defn describe ((self (ref Fox))):i32 (return (_get self n)))
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
  if grep -q 'internal constant { ptr, ptr } { ptr @w24__describe,' "$d/w24use.ll"; then
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
    (ptr-set! q r)
    (return (+ (q a) (q b)))))
(defn holder-sum (h:(ref Holder)):i32
  (let (q:ptr:Rec (alloca Rec))
    (ptr-set! q (h r))
    (return (+ (+ (q a) (q b)) (h n)))))
(defn ch-echo (c:Char):Char (return c))
EOF
  if ! ./build/nucleusc --emit-cheader "$d/tlib.nuc" > "$d/tlib.h" 2>"$d/err"; then
    echo "FAIL  w9-cheader-struct-tag (--emit-cheader failed)"; sed 's/^/    /' "$d/err"; rm -rf "$d"; return 0
  fi

  # Tag and typedef share a spelling — legal C, separate namespaces — so both
  # `Rec` and `struct Rec` name the completed type. A defunion is tagged for the
  # same reason: `type-name-to-c` answers `struct NAME` for a union name too.
  if grep -qxF 'typedef struct Rec {' "$d/tlib.h" \
     && grep -qxF 'typedef struct Holder {' "$d/tlib.h" \
     && grep -qxF 'typedef struct Shape {' "$d/tlib.h"; then
    echo "PASS  w9-cheader-struct-tagged"
  else
    echo "FAIL  w9-cheader-struct-tagged"; grep -n 'typedef struct' "$d/tlib.h" | sed 's/^/    /'
  fi

  # A builtin scalar is not a struct. `Char` lowers to i32 (verified in the IR:
  # `define i64 @char-utf8-len(i32 %c.arg)`), so the C spelling is uint32_t.
  if grep -qxF 'uint32_t ch_echo(uint32_t c) asm("ch-echo");' "$d/tlib.h" \
     && ! grep -q 'struct Char' "$d/tlib.h"; then
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
(defn scale (p:(ref Pt) k:i32):i32 (return (* (+ (p x) (p y)) k)))
(defn scale (a:i32 k:i32):i32 (return (* a k)))
(defn = (a:Pt b:Pt):i1
  (let (la:Pt a lb:Pt b)
    (return (if (and (= ((addr-of la) x) ((addr-of lb) x))
                     (= ((addr-of la) y) ((addr-of lb) y))) true false))))
(defn solo (n:i32):i32 (return (+ n 1)))
EOF
  if ! ./build/nucleusc --emit-cheader "$d/ovlib.nuc" > "$d/ovlib.h" 2>"$d/err"; then
    echo "FAIL  w9-cheader-overload-symbols (--emit-cheader failed)"; sed 's/^/    /' "$d/err"; rm -rf "$d"; return 0
  fi

  # Each method gets its own C name and its own label; the solitary one keeps
  # its bare name and needs no label at all.
  if grep -qxF 'int32_t scale_pPt_i32(void* p, int32_t k) asm("scale.pPt.i32");' "$d/ovlib.h" \
     && grep -qxF 'int32_t scale_i32_i32(int32_t a, int32_t k) asm("scale.i32.i32");' "$d/ovlib.h" \
     && grep -qxF '_Bool eq_Pt_Pt(struct Pt a, struct Pt b) asm("eq.Pt.Pt");' "$d/ovlib.h" \
     && grep -qxF 'int32_t solo(int32_t n);' "$d/ovlib.h"; then
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
      grep -qxF "$sym" "$d/syms" || miss="$miss $sym"
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
  if ! grep -qE '^[A-Za-z_].* _\(' lib/*.h && ! grep -qE 'asm\("[<>=!+*/%-]+"\)' lib/*.h; then
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
  if printf '%s' "$err" | grep -qF "no matching method for overloaded 'b4-desc' with argument types (i32, i32)"; then
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
  if printf '%s' "$err" | grep -qF "unknown: b4a/b4-desc — 'b4a' is not in scope in this file"; then
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
(defn b4-twice (x:T &where (B4Num T)):i32
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
    if printf '%s' "$err" | grep -q ':0:'; then
      echo "FAIL  $name (diagnostic reports line 0)"
      printf '%s\n' "$err" | sed 's/^/    /'
    elif printf '%s' "$err" | grep -qF "redefinition of '$pat'" \
      && printf '%s' "$err" | grep -qF "$d/$name.nuc:2: error:"; then
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
  if printf '%s' "$err" | grep -qF "redefinition of 'RdX'" \
     && printf '%s' "$err" | grep -qF "$d/b4r-fa.nuc:1"; then
    echo "PASS  b4-redefinition-cross-file"
  else
    echo "FAIL  b4-redefinition-cross-file (did not name the other file)"
    printf '%s\n' "$err" | sed 's/^/    got: /'
  fi

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
  if grep -q '^FAIL' "$out" || [ ! -s "$out" ]; then
    fail=1
  fi
done

exit $fail
