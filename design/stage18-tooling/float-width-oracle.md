# The float-width tests, in Nucleus

**Staged 2026-09-05.** A TF-6 category (c) work item, carved out of the batch
plan because it is the one shell unit whose port is not a port: it is a
rewrite of two Python programs into Nucleus, and the language may not have
what they need.

## Why it is separate

`run_s16_fl_float_widths` (`tests/run-tests.sh`, 206 lines) is the only unit in
the whole suite that embeds `python3` as an **oracle** — Python computing an
answer the assertion depends on, rather than Python being the subject under
test. (`run_stdlib_table` and `run_cstr_residue` name `python3` too, but they
*invoke* `scripts/check-cstr.py`, which §T7 keeps outside the framework on
purpose.)

Every other deferred unit is a mechanical port: shell text-munging becomes
`lib/strview.nuc` calls, and the assertion shape is already in `lib/test.nuc`.
This one is not, and estimating it alongside four ordinary units would hide
that.

## What the unit asserts today

Five test names, of which only the first is Python-bound:

| name | oracle | what it pins |
| --- | --- | --- |
| `s16-fl-constants-vs-clang` | clang + **python3** | 120 float literals at five widths, each against clang's own emitted constant |
| `s16-fl-aggregate-abi` | clang | FL-4: `long double`/`__float128`/`_Float16` in aggregates, signature for signature |
| `s16-fl-vararg-unpromoted` | — | FL-5: `...` promotes f32 and leaves the other four alone |
| `s16-fl-target-availability` | — | FL-6: an unavailable width is a located error; `long double` follows the target's C ABI |
| `s16-fl3-hex-literals`, `s16-fl3-exponent-required` | — | hex float literals at run time; `0x1.8` with no exponent is not a float |

The last three are ordinary ports. The work is in the first two.

### The two Python programs

**The generator** builds a matched pair of fixtures: 16 hex literals × 5 widths
plus 8 decimal literals × 3 widths, emitted twice — once as
`(defvar v7_f80:f80 0x1.8p-3)` and once as
`__attribute__((used)) static long double v7_f80 = 0x1.8p-3L;`. Decimal is
asserted only at f16/f32/f64 on purpose: a decimal literal folds through the
host f64, so at f80/f128 Nucleus is *deliberately* less precise than C
(§10 limit 1, `design/future/decimal-float-literals.md`).

**The comparator** reads `@name = … global <ty> <val>` out of both `.ll` files
and compares, after normalising the value — because LLVM prints an f32/f64
constant as a decimal when it round-trips and as a hex bit pattern when it does
not, so the two compilers can agree on the value and disagree on the spelling.
`0xH…`/`0xK…`/`0xL…` (half, x86_fp80, fp128) are already bit patterns and pass
through; everything else is parsed to an f64 and reprinted as its 16-digit
pattern.

## The rewrite

The comparator is the interesting half, and it is smaller in Nucleus than it
looks in Python, because the compiler already contains both halves of the
normalisation:

- **decimal or C-hex text → f64**: `parse-float` (`lib/parse.nuc`) delegates to
  `strtod`, which is C99 and so accepts `0x1.8p+3` as well as `3.14`. Python
  needed two branches (`float.fromhex` vs `float`); Nucleus needs none.
- **f64 → its 64 bits**: the `addr-of` + `unsafe/cast ptr:i64` + `deref`
  idiom, which is `f64-bits` in `src/type-utils.nuc:349` — Nucleus has no
  bitcast operator and this is the established spelling of one.
- **`0xNNNNNNNNNNNNNNNN` text → f64**: parse 16 hex digits, then the same
  idiom in reverse. `rd-hex-val` (`lib/read.nuc:98`) is the digit table.

The generator is two nested loops over two tables and `str-into`; the fixture
tables are data, which is category (a)'s rule and already how
`tests/suite-s16.nuc` holds its corpora.

`s16-fl-aggregate-abi` needs no oracle logic, only normalisation: strip
` noundef`, `%struct.`, and SSA names from both compilers' `define` lines and
compare the sets. The shell does it with four `sed -E` substitutions.

## Known gaps — raise these, do not paper over them

Three are visible before the work starts:

1. **Padded hex formatting is compiler-internal.** `hexu` lives in
   `src/strfmt.nuc:137`, not in `lib/fmt.nuc`, so a test cannot call it. The
   comparator needs `%016X` and `rd-write-hex` (`lib/read.nuc:720`) is neither
   padded nor public.
2. **No `replace` on `StrView`/`String`.** The ABI unit's four `sed`
   substitutions have no library equivalent; they can be written as a
   token-filtering pass instead, which may or may not be smaller.
3. **`_Float16`/`__float128` are a genuine feature probe.** clang is a hard
   dependency of this project already — `src/nucleusc.nuc:18681` uses it as the
   default linker driver and the `Makefile` links with it — so "is clang here"
   is *not* a conditional. "Does this clang's target have `_Float16`" is, and
   the shell handles it by printing `PASS … (SKIP: …)`, which is a lie in the
   record. This unit is the first real consumer of `skip!`, landed 2026-09-05.

## The instruction

**Raise difficulties and substantial code-size increases as work items for
review rather than absorbing them.** Specifically:

- If a gap above (or one not listed) turns out to want a **library addition** —
  a padded-hex formatter in `lib/fmt.nuc`, a `replace`, a float-bits helper —
  that is a work item to be written down and put up for review, not a thing to
  inline into the test file. Stage 17's rule stands: *do not work around
  weaknesses; improve the string library instead* — and "improve" means the
  addition is designed and reviewed, not smuggled.
- If the Nucleus version of either program comes out **substantially larger**
  than the Python — the working guess is that the comparator should come out
  *smaller* and the generator about even — that is a finding about the
  language, not a cost of the port. Report the line counts and what drove the
  difference.
- If any assertion **cannot be expressed** without new machinery, stop and say
  so with the specific assertion. Do not weaken it to fit; a float test that
  compares fewer bits than the shell version is worse than no port.

The retirement protocol is unchanged: port, two green native runs (one a
`--run`-per-name shuffle), delete the shell function *and its `spawn` line as
separate ranges*, all gates, reconcile the verdict total, then commit.
