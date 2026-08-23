# C default argument promotions at a variadic call

Found while evaluating the C-interop implications of
[bool-truthiness.md](bool-truthiness.md), and fixed on its own because it is a
live miscompile that has nothing to do with `bool`.

## The defect

C applies *default argument promotions* to every argument past a variadic
function's fixed prefix (C17 §6.5.2.2p6): an integer narrower than `int`
promotes to `int`, and `float` promotes to `double`. `emit-call-with-args`
passed the narrow type straight through, so `printf` received operands the
`va_arg` on the other side never reads.

Measured on one five-argument `printf`, Nucleus against the identical C program:

| Argument | Before | C |
|---|---|---|
| `a:i8 65` | `65` | `65` |
| `b:i16 -300` | **`-1940914476`** | `-300` |
| `c:ui8 200` | `200` | `200` |
| `d:f32 2.5` | **`0.000000`** | `2.500000` |
| `e:bool true` | `1` | `1` |
| `f:Char \A` | `65` | `65` |

Two wrong answers. The three correct ones were correct **by luck**: LLVM's
x86-64 lowering materialises a narrow value into a zeroed register
(`xorl %esi,%esi; setg %sil`), which the psABI does not promise and another
target need not do. The `i16` case is the one that shows what the register
actually held: `-1940914476` is `0x8C4FFED4`, whose low half is exactly `-300`
(`0xFED4`) and whose high half is the caller's debris. That half is not stable —
the same program built from a different boot compiler printed `1321270996`,
`0x4EC0FED4`, the identical low half under different garbage.

Emitted before and after, same source:

```
before:  call i32 (ptr, ...) @printf(ptr %t9, i8 %t10, i16 %t11, i8 %t12, float %t13, i1 %t14, i32 %t15)
after:   call i32 (ptr, ...) @printf(ptr %t9, i32 %t10, i32 %t11, i32 %t12, double %t13, i32 %t14, i32 %t15)
clang:   call i32 (ptr, ...) @printf(ptr @.str,  i32 …,   i32 …,   i32 …,   double …,    i32 …,    i32 …)
```

## Why it does not live in `coerce-int-val`

conventions.md's standing rule is **add a new implicit conversion at
`coerce-int-val`, not at the call sites**, and this is the exception that proves
the shape of the rule. `coerce-int-val` converts a value *toward a declared
type*; a variadic argument has no declared type to converge on. The promotion is
a property of the **position**, not of a source/target pair, and the only code
that knows where the `...` tail begins is the argument walk in
`emit-call-with-args`.

That site already carries one rule of exactly this kind — the Stage 14 NS-3
StrView collapse, which passes only a view's `data` pointer past the fixed
prefix — so the promotion sits beside it and reuses `coerce-int-val` to *emit*
the widening once the target is chosen. The rule picks the type; the chokepoint
still performs the conversion, so `zext`-vs-`sext` (and `i1`'s unsignedness) are
decided in one place, not two.

## The rule

`vararg-promote` (`src/nucleusc.nuc`), called once per argument at index
`>= num-params` of a variadic callee:

- `f32` → `f64` (`fpext`). `f64` is already the promoted type, and every float
  *literal* is typed `f64` by `emit-float`, so a literal never moves.
- any integer narrower than C's `int` → `int`, via `coerce-int-val`, which picks
  `zext` for an unsigned source and `sext` for a signed one. `i1` counts as
  unsigned (`is-unsigned` has a `TY-I1` arm), so `true` widens to `1`.
- everything else is untouched — including `Char`, which is `ui32` and therefore
  already `int`-wide, and `usize`/`ssize`, which are pointer-width.

**C's `int`, not Nucleus's.** The promotion target is `i16` where pointers are
two bytes (AVR) and `i32` elsewhere, following the `g-target-ptr-bytes` idiom
`ptr-int-type` already uses. Nucleus's own `int` spelling is a fixed alias for
`i32`, which would be the wrong target on an 8-bit device.

## Blast radius

10 of 149 examples changed IR; **0 changed output**. Every one was a `bool`
printed with `%d` — the case that was already right by luck — so the corpus was
carrying the latent form of the bug in ten places and the wrong-answer forms
(`f32`, `i16`) appeared nowhere in it. Most of each diff is temp renumbering,
since the promotion consumes a `%tN`.

`make bootstrap` converges; 777 tests (was 773); abi/layout/avr/riscv/riscv-abi/
check-headers green.

## Testing note

Three of the six promoted types print correctly under *both* behaviours, so a
run-only test cannot tell the versions apart — the same trap
conventions.md §"A wrong value that only reaches a truthiness test is invisible
to every gate" records for `i1` signedness. `run_s16_vararg_promotion` therefore
asserts on the **instruction** as well as the run, and adds the two negative
cases a position-keyed rule needs: a variadic callee's *fixed* narrow parameter
must stay narrow (a rule applied one argument early would widen it), and an
already-`int`-wide argument must gain no instruction at all.
