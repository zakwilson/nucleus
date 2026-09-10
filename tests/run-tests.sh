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

# Stage 13 L8: a public defn whose signature exposes a capturing-closure env
# type (__vfn_env_N) is not C-callable, so --emit-cheader OMITS its prototype
# (writing a comment in its place) and the compiler WARNS at the definition. A
# plain function-pointer-compatible defn is emitted normally. The fixture
# declares a __vfn_env_0 struct by hand to stand in for a synthesized env (real
# envs are created post-prescan, so they cannot appear in source signatures).
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


# --- Dispatch sequence (original top-to-bottom order) ---------------------------

# The `examples/*.nuc` and `tests/repl/*.in` golden-output loops that stood here
# are `tests/nuctests.nuc`'s, since Stage 18 TF-6 category (b). They discover
# their inputs the same way, with `read-dir` in place of the glob.

spawn run_repl_meta_loose

spawn run_abi_subtest

spawn run_layout_subtest


spawn run_closure_cheader

spawn run_box_cheader

spawn run_s1_sugar_rets


spawn run_s1_block


spawn run_w9_dyn_solitary
spawn run_s16_se_template_ref
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


# --- Stage 15 W4e: docs/stdlib.md's availability table is generated ---------
spawn run_stdlib_table
spawn run_headers_generated
spawn run_cstr_residue



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
