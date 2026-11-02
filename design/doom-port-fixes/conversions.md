# Conversions and indexes (ISSUE-037, 046)

## Exact integer-to-float `as` (037)

`as` accepts an integer to a float type whose significand holds every value
of the source exactly (`int-exact-in-float?`):

- 8- and 16-bit integers go to `f32`.
- Those and 32-bit integers go to `f64`.
- An integer literal goes wherever its value is exact.

`i64`, `usize` and `ui64` to `f64` can round, so they stay `unsafe/cast`. This
keeps `as` to its contract: never lossy.

## Any integer index; `as-checked` (046)

- **Indexes:** `Vector`, `Slice` and the other collections' `invoke`/`set` gain
  `i64` and `i32` overloads. A negative index fails the bounds check as an
  out-of-range one does, so a signed index is as safe as `usize`, and a C
  port's `int` loop counters index directly.
- **`(as-checked T x)`:** an integer conversion that checks the value at run
  time and traps if it doesn't fit. It sits between `as` (provably lossless)
  and `unsafe/cast` (unchecked).
  - Only the comparisons that can fail are emitted: the low bound for a signed
    source going narrower or unsigned, and the high bound for a narrower or
    sign-changing target.
  - A failure prints `nucleus: FILE:LINE: as-checked: the value does not fit
    T` when `printf` is in scope, then calls `llvm.trap`.
  - A literal or non-integer operand goes to `as`'s rules, so
    `(as-checked i32 (count v))` is the spelling for reading a length.
