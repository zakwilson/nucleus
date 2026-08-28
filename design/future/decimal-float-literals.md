# Correctly-rounded decimal float literals

**Status: staged, not scheduled.** Split out of
[stage16-ergonomics/c-boundary-defects.md](../stage16-ergonomics/c-boundary-defects.md)
§10 limit 1, which plans `f16`/`f80`/`f128` but cannot make a *decimal* literal
correct at those widths without this. Nothing in that plan is blocked on this
item; this is the difference between "the wide float types exist and interoperate"
and "a decimal literal means at f128 what it means in C".

---

## 1. The defect

The compiler evaluates every decimal float literal through the host's `f64`:
`float-literal-value` (`src/nucleusc.nuc`) returns an `f64`, and
`float-literal-ir-at` renders that `f64` at the destination width. For `f32` this
is the documented double-rounding already recorded in
[stage15-stress-test/literal-typing.md](../stage15-stress-test/literal-typing.md)
§W2d, and it is harmless in practice because decimal → f64 → f32 differs from
decimal → f32 only on a vanishingly rare set of inputs.

At `f80` and `f128` it is not harmless, because the intermediate is *narrower
than the destination*:

```lisp
(defvar x:f128 1.1)   ; gets the f128 value of (f64)1.1, not the f128 value of 1.1
```

f64 carries 53 significant bits; f128 carries 113. So `x` is exact to about 17
decimal digits and then carries the f64 rounding error, zero-extended, for the
remaining 17. C's front end converts the decimal string to the destination format
directly, so `long double x = 1.1L;` is correct to all 34 digits. This is a
silent wrong-value divergence, not a diagnostic.

`f80` has the same shape with 64 significant bits against f64's 53.

## 2. What the c-boundary plan does instead, and why it is not enough

FL-3 in that plan adds C's hex-float literal syntax (`0x1.199999999999Ap+0`),
which is **exact by construction** — the digits *are* the significand, so no
conversion is performed and no rounding can occur. That is the right escape
hatch and it is genuinely sufficient for the cases that motivated the wide float
types in the first place (matching a C constant, writing a bit-pattern, defining
a target epsilon).

It is not sufficient as an answer to "Nucleus can do anything C can do", for one
reason: **a reader cannot tell by looking whether a decimal literal is exact.**
`(defvar e:f128 2.718281828459045235360287471352662)` compiles, looks correct,
and is wrong from digit 18. Nothing warns. Requiring hex for correctness means
the natural spelling is the wrong one, which is the shape of defect this project
has repeatedly refused elsewhere (the discarded value-position type annotation,
the unchecked function-pointer slot).

## 3. The work

This is a self-contained numeric routine, not a compiler-architecture change.
One function, one home, one caller: `float-literal-value` gains a width
parameter, or is replaced by a `decimal-to-binary(lexeme, format)` that
`float-literal-ir-at` calls directly.

- **DL-1 — the converter.** Correctly-rounded decimal → binary at f16/f32/f64/
  f80/f128, round-to-nearest-even, with subnormals, overflow to ±inf and
  underflow to ±0. The standard implementable approach is big-integer
  scaled-quotient (compute `significand × 10^exp` as an exact rational in
  arbitrary precision, then round once to the destination format) with a
  fast path for the common case where the value fits exactly in the destination.
  Correctness is the whole point, so the fast path must be *provably* exact or
  absent — a fast path that is usually right is worse than none.
- **DL-2 — the big-integer support it needs.** The compiler has no bignum. The
  converter needs multiply-by-small, shift, and compare on a few hundred bits;
  that is a bounded fixed-width helper, not a general bignum library, and it
  should be written as one (a fixed `[N x u64]` with the three operations) so it
  cannot grow into a dependency.
- **DL-3 — retire the f64 intermediate everywhere.** Once DL-1 exists,
  `f32-const-ir`'s decimal → f64 → f32 double-rounding is also fixed for free by
  routing through it, closing the W2d note. `float-literal-ir-at` remains the
  single home for "what text does this literal have at this width", so there is
  exactly one edit site.
- **DL-4 — the test.** Differential against the platform C compiler, which is the
  same oracle every other layout and ABI claim in this project uses: emit a C
  file of `_Static_assert`s comparing the bit patterns of the same literal at
  each width, and compare against what Nucleus renders. The interesting inputs
  are the known hard cases for decimal conversion (halfway values, the shortest
  round-trip digits for each format, values just under and over the subnormal
  boundary), not round numbers.

## 4. Why it is not scheduled

- **Nothing depends on it.** Every C interop use of `f80`/`f128` involves either
  a value computed at run time or a constant that can be written in hex. The
  wide float types are fully usable without it.
- **It is off the critical path of everything else.** It touches one function and
  its callers, adds no type, changes no ABI, and moves no layout. It can land at
  any time, before or after the rest of the float work, with no ordering
  constraint in either direction.
- **The cost is concentrated in getting it exactly right**, which is a poor fit
  for riding along with a larger change. A decimal converter that is *nearly*
  correctly rounded is indistinguishable from a correct one until it is not, and
  the failure is a silently wrong constant — the same class of defect it exists
  to remove.

## 5. Until then

Document the limitation at the point of use, not in a footnote: the `f80`/`f128`
sections of `docs/types.md` should say that a decimal literal is evaluated at
`f64` precision and then widened exactly, name the hex-float spelling as the way
to write a bit-precise value, and give a worked example of the difference. A
diagnostic is *not* the answer here — the compiler cannot tell an intentionally
short decimal from a truncated one, so warning on every wide-float decimal
literal would fire on almost all correct code.
