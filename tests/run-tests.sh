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
