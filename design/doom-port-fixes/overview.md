# DOOM-port fixes

The nuc-doom port (`/home/zak/code/nuc-doom`, `ISSUES.md`) filed 46 issues
against Nucleus. Eighteen were fixed one commit each on the `doom-bugfixes`
branch before 2026-11-02. This directory holds the design notes for the
remaining 28, whose rulings (2026-11-02) ask for changes rather than "done".
Each fix is still one commit, tagged `(nuc-doom ISSUE-NNN)`, with its record
in [../progress.md](../progress.md).

| Issue | Ruling | Note |
|---|---|---|
| 001 | consult the header index for every imported header; else map an unresolved link symbol to its header | |
| 002 | keep skipped function-like macro names; note the reason in the undefined error | |
| 004 | `:tests` in `build.edn` and `nucleus test`; `:programs` deferred | |
| 005 | stop the root search at a VCS root; flag and variable to override | |
| 006 | import C header variables as externs | |
| 007 | value-Maybe arm for `unwrap-or`/`if-some`/`when-some` | |
| 009 | bit operators become variadic macros over `_bit-*` primitives | |
| 011 | fold `?:` and comparisons in the header constant evaluator | |
| 012 | (done) revisit the Maybe-shaped union layout rule | [../deferred/overview.md](../deferred/overview.md) |
| 013 | carry the pointer kind through a template stamp and its memo key | |
| 015 | canonicalize file paths before the cycle and already-loaded checks | |
| 016 | fold an aggregate `defconst` used as a `defvar` initializer | |
| 017 | fold a constant operator tree, then adapt it as a literal | |
| 018 | `inc!`/`dec!` take a place and an optional amount, as macros over `set!` | |
| 019 | name the shadowing local and the shadowed function | |
| 020 | fix `case`'s stale docs row | |
| 021 | nested places and array elements without `&`; a stdlib slice type | |
| 024 | fold a computed `defconst` at first reference, across a cycle | |
| 025 | an untyped `let` of a struct literal binds a value; `&S` literal joins with `S` siblings as `S` | |
| 026 | `break`, `continue`, `while-some` | |
| 028 | `radix` in `nucleus.fmt`; `bin`/`oct`/`hex` over it | |
| 030 | copy an array literal into an array field at run time | |
| 035 | `nucleus.math`: `min`/`max`/`abs`/`clamp` over `nucleus.numeric` | |
| 036 | `clear!` and `truncate!` on `Vector` and `HashMap` | |
| 037 | `as` accepts exact integer-to-float conversions | |
| 041 | a bare value name defined by two flattened namespaces is an ambiguity error | |
| 043 | a non-tail `(ok)` takes the function's result type | |
| 045 | `derive-edn` field defaults and an absent-keys-keep mode | |
| 046 | any integer index into a collection; a checked narrowing | |

Design notes for the issues that need one are added to this directory and
linked from the table.
