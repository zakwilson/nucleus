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
run_w1_ns() {
  local d
  d="$(mktemp -d)"
  printf '(ns w1alpha)\n(defn a-thing ():i32 (return (w1beta/b-thing)))\n' > "$d/w1-nsa.nuc"
  printf '(ns w1beta)\n(defn b-thing ():i32 (return 42))\n' > "$d/w1-nsb.nuc"
  printf '(import w1-nsa)\n(import w1-nsb)\n(defn main ():i32 (return (w1alpha/a-thing)))\n' > "$d/w1-nm1.nuc"
  printf '(import w1-nsb)\n(import w1-nsa)\n(defn main ():i32 (return (w1alpha/a-thing)))\n' > "$d/w1-nm2.nuc"
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

  # 4. A `prefix/name` over a cycle member. The skipped re-entry has no
  # global-scope slice, so no aliases were injected; the bare name works.
  printf '(import w1-pcb)\n(defn w1-pca (n:i32):i32 (return (+ n 1)))\n' > "$d/w1-pca.nuc"
  printf '(import w1-pca)\n(defn w1-pcb (n:i32):i32 (return (w1-pca/w1-pca n)))\n' > "$d/w1-pcb.nuc"
  printf '(import w1-pca)\n(defn main ():i32 (return (w1-pcb 5)))\n' > "$d/w1-pcm.nuc"
  w1_reject_multi w1d-cycle-prefix-diagnosed "$d" "$d/w1-pcm.nuc" \
    "the prefix 'w1-pca' has no aliases here"

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
  if printf '%s' "$ir" | grep -q '^define ptr @append\.ptr\.ptr(' \
     && ! printf '%s' "$ir" | grep -qE '^define ptr @append\(' ; then
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
  printf '(ns g0alpha)\n(defn g0-ns-get ():i32 (return G0-NSK))\n(defconst G0-NSK 55)\n' > "$d/g0-nsa.nuc"
  printf '(defn g0-ns-user ():i32 (return g0alpha/G0-NSK))\n' > "$d/g0-nsb.nuc"
  printf '(import g0-nsb)\n(import g0-nsa)\n(defn main ():i32 (return (g0-ns-user)))\n' > "$d/g0-ns1.nuc"
  printf '(import g0-nsb)\n(import g0-nsa)\n(defn main ():i32 (return (g0alpha/g0-ns-get)))\n' > "$d/g0-ns2.nuc"
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

  # Two files, one global name. Both `@g0-dupg = global` lines are still
  # emitted, so this is still rejected — the prescan registering the name twice
  # must not turn it into a silent last-wins.
  printf '(defvar g0-dupg:i32 1)\n' > "$d/g0-da.nuc"
  printf '(defvar g0-dupg:i32 2)\n' > "$d/g0-db.nuc"
  printf '(import g0-da)\n(import g0-db)\n(defn main ():i32 (return g0-dupg))\n' > "$d/g0-dm.nuc"
  err="$(./build/nucleusc -I "$d" -o "$d/g0-dm.bin" "$d/g0-dm.nuc" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | grep -qF "redefinition of global '@g0-dupg'" && [ ! -x "$d/g0-dm.bin" ]; then
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
  w1_reject_multi g0-value-fn-collision-order1 "$d" "$d/g0-km1.nuc" \
    "'g0-collide' already names a function"
  w1_reject_multi g0-value-fn-collision-order2 "$d" "$d/g0-km2.nuc" \
    "'g0-collide' already names a function"
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

  # 2. the plain fn-pointer defn IS emitted to the header.
  if grep -q 'plain-fn(int32_t x, int32_t y)' "$ch_dir/lib.h"; then
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

  # 6. the plain fn-pointer defn IS emitted to the header.
  if grep -q 'plain-fn(int32_t x, int32_t y)' "$bch_dir/lib.h"; then
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

  # 3b. The cheader names the plain new-style prototypes correctly.
  if grep -qF 'int32_t twice(int32_t x);' "$s1_dir/lib.h" \
     && grep -qF 'int32_t add3(int32_t a, int32_t b, int32_t c);' "$s1_dir/lib.h" \
     && grep -qF 'int32_t scale(int32_t x);' "$s1_dir/lib.h"; then
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
  ./build/nucleusc --emit-llvm "$s1_dir/tmain.nuc" > "$s1_dir/tmain.ll" 2>/dev/null || true
  if grep -qF 'define i32 @gmax.i32.i32(' "$s1_dir/tmain.ll" \
     && grep -qF 'define i64 @gmax.i64.i64(' "$s1_dir/tmain.ll" \
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
spawn run_reject_at w8-fnptr-global-name-collision tests/fixtures/w8-fnptr-global-name-collision.nuc \
  "tests/fixtures/w8-fnptr-global-name-collision.nuc:15: error:" \
  "'f' already names a function — a symbol may name only one kind of thing"

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
  "tests/fixtures/w9-ns-proto-nonconform.nuc:11: error:" \
  "type 'Bad' does not conform to protocol 'dp/Describe'"
spawn run_reject_at w9-ns-proto-ambiguous tests/fixtures/w9-ns-proto-ambiguous.nuc \
  "tests/fixtures/w9-ns-proto-ambiguous.nuc:17: error:" \
  "extend: unknown protocol 'Describe'"

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
