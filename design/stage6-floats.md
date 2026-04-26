# Floating point types

Nucleus currently has no floating-point type. The `TypeKind` enum
(`src/nucleusc.nuc:31`) lists only `TY-VOID`, the integer kinds (`TY-I1`
through `TY-UI64`), `TY-PTR`, `TY-FN`, and `TY-STRUCT`. There is no
reader path for `1.5`, no codegen for floating arithmetic, and no
printer branch. C interop is also affected: `long double`,
`_Complex`, and any header that uses `float` / `double` cannot be
imported without manual workarounds.

This was discovered as Discovery #1 during stage 6 implementation
(see [stage6-plan.md](stage6-plan.md)). Because adding floats touches
the type system, the reader, codegen, the printer, and C header
parsing, it gets its own design pass rather than a single bullet in the
cleanup plan.

## Robot:

### Scope

Two distinct float types, matching C:

- `f32` — IEEE-754 binary32, LLVM `float`. C `float`.
- `f64` — IEEE-754 binary64, LLVM `double`. C `double`.

`long double` is x86-extended (80-bit) on Linux, IEEE quad on some
platforms, and double-precision on others. It's poorly portable and
genuinely rare in modern code; defer to stage 3c.
[stage3c.md](stage3c.md) already lists `long double` as blocked on
this work.

`_Complex float` / `_Complex double` should also stay in stage 3c and
remain skipped by the C header parser.

### Type system changes

Add to `TypeKind` (`src/nucleusc.nuc:31`):

```
TY-F32 TY-F64
```

`make-type` already handles fixed-shape kinds; the float variants need
no new fields. `is-int-type` already returns 0 for non-integer kinds —
verify this still holds, or split into `is-int-type` vs.
`is-numeric-type` if codegen needs the latter for the new arithmetic
ops.

`type->ir-name`, `type->c-name`, and `type->size-bytes` (around
`src/nucleusc.nuc:386`/`418`/`435`) gain branches:

| kind   | LLVM IR name | C name   | size |
|--------|--------------|----------|------|
| TY-F32 | `float`      | `float`  | 4    |
| TY-F64 | `double`     | `double` | 8    |

Type-name registration: add `f32` and `f64` to whatever table maps
source-level type symbols to `Type*` (alongside `i32`, `i64`, etc.).

### Reader

Extend the numeric tokenizer. The existing path reads an optional `-`
followed by digits and produces `NODE-INT`. The float path is "saw a
`.` or an `e`/`E` with sign while reading a numeric token."

Recognize, in order of precedence:

- `[+-]?[0-9]+\.[0-9]+([eE][+-]?[0-9]+)?` — `1.5`, `-0.25`, `1.5e-3`
- `[+-]?[0-9]+[eE][+-]?[0-9]+` — `1e10`, `-2E+5`
- `[+-]?\.[0-9]+([eE][+-]?[0-9]+)?` — `.5`, `-.25e3`

Reuse `strtod` from libc to parse the literal. Add a new node kind
`NODE-FLOAT` whose payload is a `f64`. Float literals are always read
as `f64` — narrowing to `f32` happens at use sites via the existing
type-context machinery (the same way `1` is read as untyped and gets
coerced to whatever `i32`/`i64` is needed). If the use site requires
`f32` and the literal won't round-trip, that is a diagnostic — same as
integer overflow at a typed slot.

A trailing `f` suffix (`1.5f`) explicitly types the literal as `f32`.
Defer this until needed; without it, all float literals are `f64`.

### Codegen

LLVM provides `fadd`, `fsub`, `fmul`, `fdiv`, `frem`, and float
comparisons (`fcmp olt`, `oeq`, etc., where `o` means "ordered" — NaN
is false). The integer arithmetic builtins in
`src/nucleusc.nuc` need a float branch keyed off the operand type.

Promotion rules (one operand is float, the other is int): promote the
int to the float type. Don't promote silently across float widths —
require an explicit `(cast f64 x)` to go from `f32` to `f64`. Mixed-
width float arithmetic is rare and the explicit cast keeps the rule
simple.

Float literal lowering: emit as LLVM `double 1.5e+00` (or the
hex-literal form for exact-bits, `double 0x...`); LLVM's IR parser
accepts both. Use the hex form whenever `%.17g` round-tripping is in
doubt — float printing is famously fragile.

### Printer

`print-node` (`src/nucleusc.nuc:322`) gains a `NODE-FLOAT` branch.
Use `%.17g` for `f64` and `%.9g` for `f32` — the standard shortest-
round-trip widths. Check that the printed form contains a `.` or `e`;
if not (e.g. `%.17g` of `1.0` prints as `1`), append `.0` so the
result is read back as a float, not an int.

The REPL value printer (step 2 of stage6-plan) dispatches on the
top-level expression's static type and uses the same formatter for
`TY-F32` / `TY-F64` results.

### Special values

- `NaN` — `(/ 0.0 0.0)`. Print as `+nan.0` (Scheme convention) or
  `nan` (C convention). Recommend `+nan.0` because it's reader-
  unambiguous; reserve `nan` as a symbol.
- `+Inf`, `-Inf` — print as `+inf.0` / `-inf.0`. Same reasoning.
- `-0.0` — printed as `-0.0`, distinct from `0.0`.

The reader should accept all three special tokens and produce
`NODE-FLOAT` values via `strtod` (which already recognizes them).
Reject the unprefixed `nan`/`inf` to keep them as ordinary symbols.

### C header parsing

The cheader path (`src/nucleusc.nuc` around `2208–~2400`) currently
maps unsupported types to `ptr` or skips the declaration. Add cases:

- `float` → `TY-F32`
- `double` → `TY-F64`
- `long double` — still skip; flagged in stage 3c.

Function declarations with float parameters or return types should now
produce correct cheaders. Test by importing `<math.h>` (`sin`, `cos`,
`sqrt`) and calling them.

### Bootstrap

The bootstrap binary (`bin/nucleusc`) doesn't know about floats. The
new compiler that does must be built without using float literals in
its own source (the compiler is integer-only today and stays that way
during transition). Once the new compiler self-hosts, rebuild the
bootstrap.

This is the same shape of bootstrap update as past type additions
(unsigned integers in stage 3b). No bootstrap-specific design work
required.

### Test plan

- Reader: `1.5`, `-0.25`, `1e10`, `1.5e-3`, `.5`, `-.25`,
  `+inf.0`, `-inf.0`, `+nan.0` all parse to `NODE-FLOAT`.
- Round-trip: `(read (print 1.5))` yields a node `eq?` to `1.5`
  (note: NaN is not `eq?` to itself; test separately).
- Arithmetic: `(+ 1.5 2.5)` → `4.0`. Mixed `(+ 1 2.5)` → `3.5`
  (int promoted). Comparison `(< 1.0 2.0)` → true. Division by zero
  yields `+inf.0`, not a trap.
- C interop: `(import math)` makes `(sin 0.0)` return `0.0`; `(cos 0.0)`
  returns `1.0`; `(sqrt 2.0)` returns `1.41421356...`.
- Self-host: compiler still builds with the new types in place but
  unused.

### Completion criteria

- `f32` and `f64` are first-class types alongside the integer types.
- Float literals can be read, printed, and round-tripped.
- All five basic arithmetic ops and the six comparisons work on floats.
- `<math.h>` can be imported and its functions called.
- The compiler self-hosts and the test suite passes.

## Designer:

Use Scheme-style representations for special values.

## Status

Implemented. `examples/floats.nuc` exercises basic literal forms,
arithmetic, comparisons, int↔float casts, f64↔f32 narrow/widen, and
the special tokens `+inf.0`/`-inf.0`/`+nan.0`. Bootstrap fixed-point
holds; `bin/nucleusc` and `boot/nucleusc.ll` updated.

Notes from implementation:

- Float literals are stored as the source lexeme on `Node.s` (no
  changes to the `Node` struct, so the macro layer's view of `Node`
  is unchanged). Codegen normalizes the lexeme to LLVM IR's required
  form (digit, `.`, fractional digit, optional exponent) before
  emitting `double <lit>`.
- Special tokens emit hex bit-patterns: `0x7FF0000000000000` (+Inf),
  `0xFFF0000000000000` (-Inf), `0x7FF8000000000000` (qNaN).
- The compiler source itself doesn't use float types; it just
  manipulates the lexeme as a string. The bootstrap thus needs no
  float support — it just sees a new `NODE-FLOAT` kind it ignores
  for non-float code paths.
- REPL value printing for `f32`/`f64` results goes through
  `repl_print_f32` / `repl_print_f64` in `src/repl_shim.c` so the
  formatting (`%.9g` / `%.17g` with `.0`-suffix fixup) lives in C
  rather than in the compiler.
- Mixed int+float arithmetic is a compile error rather than auto-
  promoting; the design doc considered both and chose explicit
  casts. This matches the integer signed/unsigned rule.
- Deferred (per design): `1.5f` suffix for explicit f32 literals.
  Not yet needed because all use sites that want f32 can `(cast f32
  …)`.
