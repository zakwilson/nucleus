# Struct and array literals (ISSUE-025, 030)

## An untyped `let` of a struct literal (025)

- **The literal:** a compound literal `(S …)` is an `&S` (a temporary's
  address), so `(let (p (S 1 2)) …)` bound a pointer to a temporary. An untyped
  binding whose init is a struct literal (`arg-struct-literal?`) now binds the
  value `S`. `node-type-block` applies the same rule, for the lockstep.
- **A `cond` mixing literals and values:** a `cond` mixing `&S` literals with
  `S` values used to collapse to void. Its branches now join under the want
  that `cond-literal-join-want` finds:
  - The outer want, if it is a struct type.
  - Otherwise `S`, when some branch is syntactically an `S` literal (a
    `BK-STRUCT` binding found by `binding-find`, typed through `type-for-sdef`)
    and every typed sibling is a type-equal `S` value.
  - `node-type` doesn't model struct literals, so this check is syntactic.

## Array literal into an array field (030)

A struct literal's array field takes an array literal, which is copied in at
run time. `emit-array-lit-n` pads it to the field's length with zeros. It
refuses more initializers than the field holds ("array: too many initializers
for a N-element array field"), and a positional mismatch names the field.
