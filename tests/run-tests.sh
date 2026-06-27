#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
for src in examples/*.nuc; do
    name="$(basename "$src" .nuc)"
    expected="tests/expected/${name}.out"
    [ -f "$expected" ] || continue

    ./build.sh "$src" >/dev/null 2>&1
    actual_file="$(mktemp)"
    ./build/out/"$name" > "$actual_file" 2>&1 || true

    if diff -u "$expected" "$actual_file" >/dev/null; then
        echo "PASS  $name"
    else
        echo "FAIL  $name"
        diff -u "$expected" "$actual_file" || true
        fail=1
    fi
    rm -f "$actual_file"
done

# REPL session tests: pipe each tests/repl/<name>.in into `nucleusc -i` and
# compare against tests/expected/repl-<name>.out.
for src in tests/repl/*.in; do
    [ -f "$src" ] || continue
    name="$(basename "$src" .in)"
    expected="tests/expected/repl-${name}.out"
    [ -f "$expected" ] || continue

    actual_file="$(mktemp)"
    ./build/nucleusc -i < "$src" > "$actual_file" 2>&1 || true

    if diff -u "$expected" "$actual_file" >/dev/null; then
        echo "PASS  repl-$name"
    else
        echo "FAIL  repl-$name"
        diff -u "$expected" "$actual_file" || true
        fail=1
    fi
    rm -f "$actual_file"
done

# Cross-target emission: each triple in the Phase-B matrix must produce IR
# carrying the matching `target triple` line. Guards against a backend not
# being registered (which makes --target reject the triple).
for triple in \
    x86_64-pc-linux-gnu \
    x86_64-apple-darwin \
    aarch64-apple-darwin \
    aarch64-unknown-linux-gnu \
    arm-unknown-linux-gnueabihf \
    x86_64-pc-windows-msvc \
    x86_64-pc-windows-gnu \
    i386-pc-linux-gnu; do
    ir="$(./build/nucleusc --target="$triple" --emit-llvm examples/hello.nuc 2>/dev/null || true)"
    if printf '%s' "$ir" | grep -q "target triple = \"$triple\""; then
        echo "PASS  target-$triple"
    else
        echo "FAIL  target-$triple"
        fail=1
    fi
done

# `long` ABI model (Phase D): C `long` resolves per the target's data model.
# Parse a header with long/long long functions and check the emitted declares.
abs_long_h="$(pwd)/tests/abi/long.h"
printf '(import-use "%s")\n(defn use:i64 () (return (lfn 1)))\n' "$abs_long_h" > "$(pwd)/tests/abi/.long_probe.nuc"
check_long() {  # <triple> <expected-lfn-ir> <expected-llfn-ir>
    local triple="$1" want_l="$2" want_ll="$3"
    local ir; ir="$(./build/nucleusc --target="$triple" --emit-llvm tests/abi/.long_probe.nuc 2>/dev/null || true)"
    if printf '%s' "$ir" | grep -q "declare $want_l @lfn(" \
       && printf '%s' "$ir" | grep -q "declare $want_ll @llfn("; then
        echo "PASS  long-abi-$triple"
    else
        echo "FAIL  long-abi-$triple (want lfn:$want_l llfn:$want_ll)"
        fail=1
    fi
}
check_long x86_64-pc-linux-gnu    i64 i64   # LP64
check_long aarch64-apple-darwin   i64 i64   # LP64
check_long i386-pc-linux-gnu      i32 i64   # ILP32
check_long x86_64-pc-windows-msvc i32 i64   # LLP64
rm -f tests/abi/.long_probe.nuc

# Struct ABI interop: Nucleus<->C aggregate passing/returning must match the
# platform C ABI (Phase C). A mismatch is silently catastrophic, so it gates.
if NUCLEUSC=./build/nucleusc ./tests/run-abi-test.sh; then
    :
else
    fail=1
fi

# Struct layout: Nucleus's sizeof/field-offset computation must match the
# platform C ABI for the question-14 corpus (Phase E). Also silently
# catastrophic at the C boundary, so it gates.
if NUCLEUSC=./build/nucleusc ./tests/run-layout-test.sh; then
    :
else
    fail=1
fi

# Stage 12 N6: .nuch + --emit-cheader namespace round-trip. A library in the
# `geom` namespace exports mangled link names (@geom__area). The .nuch must carry
# (ns geom) so an importer re-resolves geom/area to @geom__area, and the cheader
# must emit the C-legal name `geom__area` — not the Nucleus name `geom/area`.
ns6_dir="$(mktemp -d)"
ns6_lib="$(pwd)/tests/fixtures/nsgeomlib.nuc"
./build/nucleusc --emit-nuch    "$ns6_lib" > "$ns6_dir/lib.nuch"  2>/dev/null || true
./build/nucleusc --emit-cheader "$ns6_lib" > "$ns6_dir/lib.h"     2>/dev/null || true
./build/nucleusc --emit-llvm    "$ns6_lib" > "$ns6_dir/lib.ll"    2>/dev/null || true

# 1. The .nuch carries the namespace directive so the importer can re-mangle.
if grep -q '^(ns geom)' "$ns6_dir/lib.nuch"; then
    echo "PASS  n6-nuch-carries-ns"
else
    echo "FAIL  n6-nuch-carries-ns"; fail=1
fi

# 2. The cheader emits the C-legal mangled name, never the slash form.
if grep -q 'geom__area' "$ns6_dir/lib.h" && ! grep -q 'geom/area' "$ns6_dir/lib.h"; then
    echo "PASS  n6-cheader-c-legal"
else
    echo "FAIL  n6-cheader-c-legal"; fail=1
fi

# 3. Importing the .nuch by path re-resolves geom/area to @geom__area, and the
#    consumer links against the lib object and runs.
# The consumer excludes the prelude (the lib object already provides it) so the
# two objects link without duplicate prelude symbols. It needs only `printf`
# (declared) and the imported geom symbols, so no prelude operators are used.
cat > "$ns6_dir/main.nuc" <<EOF
(exclude-prelude)
(import-prefixed "$ns6_dir/lib.nuch" g)
(declare printf:i32 (fmt:CStr &rest args:i32))
(defn main:i32 ()
  (printf "area=%d perimeter=%d\n" (g/area 6 7) (g/perimeter 6 7))
  (return 0))
EOF
./build/nucleusc --emit-llvm "$ns6_dir/main.nuc" > "$ns6_dir/main.ll" 2>/dev/null || true
if grep -q 'call i32 @geom__area' "$ns6_dir/main.ll"; then
    echo "PASS  n6-import-resolves-mangled"
else
    echo "FAIL  n6-import-resolves-mangled"; fail=1
fi
if clang "$ns6_dir/lib.ll" "$ns6_dir/main.ll" -o "$ns6_dir/bin" 2>/dev/null \
   && [ "$("$ns6_dir/bin")" = "area=42 perimeter=26" ]; then
    echo "PASS  n6-nuch-link-and-run"
else
    echo "FAIL  n6-nuch-link-and-run"; fail=1
fi
rm -rf "$ns6_dir"

# Stage 13 L1: cfn escape analysis. A cfn captures each used local by reference,
# so the closure value inherits the captured referent's frame region. Returning
# it out of that scope would dangle, so compiling the fixture must FAIL with the
# frame-region escape error. (The `examples/closures.nuc` run covers the positive
# cfn case; this proves the escape rejection.)
esc_err="$(./build/nucleusc --emit-llvm tests/fixtures/closure-escape.nuc 2>&1 >/dev/null || true)"
if printf '%s' "$esc_err" \
   | grep -q "address of frame-local storage escapes via return"; then
    echo "PASS  closure-escape-rejected"
else
    echo "FAIL  closure-escape-rejected"; fail=1
fi

# Stage 13 CE-3: moving a struct-VALUE Drop binding into an `mfn` consumes the
# source, so a later use must be rejected as use-after-move — including through
# `addr-of` (the only way to read a struct value's field). Compiling the fixture
# must FAIL with the use-after-move error. (The `examples/ce3-owning-closure.nuc`
# run covers the positive move/drop-once path; this proves the consume.)
uam_err="$(./build/nucleusc --emit-llvm tests/fixtures/ce3-use-after-move.nuc 2>&1 >/dev/null || true)"
if printf '%s' "$uam_err" | grep -q "use after move: 'r'"; then
    echo "PASS  ce3-use-after-move-rejected"
else
    echo "FAIL  ce3-use-after-move-rejected"; fail=1
fi

# Stage 13 L8: a public defn whose signature exposes a capturing-closure env
# type (__vfn_env_N) is not C-callable, so --emit-cheader OMITS its prototype
# (writing a comment in its place) and the compiler WARNS at the definition. A
# plain function-pointer-compatible defn is emitted normally. The fixture
# declares a __vfn_env_0 struct by hand to stand in for a synthesized env (real
# envs are created post-prescan, so they cannot appear in source signatures).
ch_dir="$(mktemp -d)"
./build/nucleusc --emit-cheader tests/fixtures/closure-cheader.nuc > "$ch_dir/lib.h" 2>/dev/null || true
ch_warn="$(./build/nucleusc --emit-llvm tests/fixtures/closure-cheader.nuc 2>&1 >/dev/null || true)"

# 1. closure-typed prototype is OMITTED, with the explanatory comment in place.
if grep -q 'apply-closure: exposes a closure or type-erased box type; not C-callable, omitted' "$ch_dir/lib.h" \
   && ! grep -q 'apply-closure(' "$ch_dir/lib.h"; then
    echo "PASS  l8-cheader-omits-closure"
else
    echo "FAIL  l8-cheader-omits-closure"; fail=1
fi

# 2. the plain fn-pointer defn IS emitted to the header.
if grep -q 'plain-fn(int32_t x, int32_t y)' "$ch_dir/lib.h"; then
    echo "PASS  l8-cheader-emits-fnptr"
else
    echo "FAIL  l8-cheader-emits-fnptr"; fail=1
fi

# 3. the definition site warns on stderr.
if printf '%s' "$ch_warn" | grep -q "warning: 'apply-closure' exposes a closure or type-erased box type"; then
    echo "PASS  l8-cheader-warns"
else
    echo "FAIL  l8-cheader-warns"; fail=1
fi
rm -rf "$ch_dir"

# Stage 13 — C header exclusion of BoxedFn/dyn-typed public defns.
# --emit-cheader omits prototypes whose signatures mention (BoxedFn …) or (dyn P)
# (fat pointers with Nucleus-side semantics; no faithful C spelling), emitting a
# comment in place and warning at the definition site. Plain fn-pointer defns are
# still emitted normally.
bch_dir="$(mktemp -d)"
./build/nucleusc --emit-cheader tests/fixtures/box-cheader.nuc > "$bch_dir/lib.h" 2>/dev/null || true
bch_warn="$(./build/nucleusc --emit-llvm tests/fixtures/box-cheader.nuc 2>&1 >/dev/null || true)"

# 4. BoxedFn-typed prototype is OMITTED, with the explanatory comment in place.
if grep -q 'make-boxed: exposes a closure or type-erased box type; not C-callable, omitted' "$bch_dir/lib.h" \
   && ! grep -q 'make-boxed(' "$bch_dir/lib.h"; then
    echo "PASS  l13-cheader-omits-boxedfn"
else
    echo "FAIL  l13-cheader-omits-boxedfn"; fail=1
fi

# 5. dyn-typed prototype is OMITTED, with the explanatory comment in place.
if grep -q 'use-dyn: exposes a closure or type-erased box type; not C-callable, omitted' "$bch_dir/lib.h" \
   && ! grep -q 'use-dyn(' "$bch_dir/lib.h"; then
    echo "PASS  l13-cheader-omits-dyn"
else
    echo "FAIL  l13-cheader-omits-dyn"; fail=1
fi

# 6. the plain fn-pointer defn IS emitted to the header.
if grep -q 'plain-fn(int32_t x, int32_t y)' "$bch_dir/lib.h"; then
    echo "PASS  l13-cheader-emits-fnptr"
else
    echo "FAIL  l13-cheader-emits-fnptr"; fail=1
fi

# 7. the definition site warns on stderr (at least one box-typed defn fires).
if printf '%s' "$bch_warn" | grep -q "warning:.*exposes a closure or type-erased box type"; then
    echo "PASS  l13-cheader-warns"
else
    echo "FAIL  l13-cheader-warns"; fail=1
fi
rm -rf "$bch_dir"

exit $fail
