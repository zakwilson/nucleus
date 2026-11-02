# Loops and places (ISSUE-009, 018, 021, 026)

## Operators that became macros (009, 018)

- **009 (bit operators):** `bit-and`, `bit-or` and `bit-xor` are variadic macros
  in `lib/nucleus/macros.nuc`, folding over the binary primitives
  `_bit-and`/`_bit-or`/`_bit-xor`. Their identities are -1, 0 and 0, so a call
  with no arguments still has a value. `bit-not` expands to `_bit-xor` with -1.
  - The compiler keeps only the `_bit-*` binops, and the constant folder
    (`cfold-op-code`) knows only those.
  - Prelude-free code (AVR examples) spells `_bit-*` directly.
- **018 (`inc!`/`dec!`):** these are macros over `set!`, so they take any place
  `set!` takes, with an optional amount. The special form, its closure-rewrite
  branch and its `resolve.nuc` case are gone.
  - `__step!` evaluates a computed index once. It hoists the first non-trivial
    index on the place's base chain into a gensym `let`, then re-expands.
- **Bootstrap:** the prelude defining macros named like old special forms
  needs a boot that lets it.
  - The "Boot for ISSUE-009/018/026" commit adds `_bit-*` beside the old
    binops, lets `guard-name-kind` admit those five names as macros, and adds
    `while`'s `:step`.
  - Its boot builds the following commits.

## `break`, `continue`, `while-some`, `:step` (026)

- **`(while test :step e body…)`:** `e` runs after the body and after each
  `continue`, in its own block. `for` and `dotimes` expand to it, so
  `continue` in them still advances the counter.
- **Loop stack:** `g-loop-stack` (in `FnState`, reset per function and saved
  around a closure body) holds a `LoopFrame` per open `while`: break label,
  continue label and the scope the loop opened in.
- **`emit-loop-jump`:** runs the cleanups of every scope between the jump and
  that frame, then branches. A closure body starts with an empty stack, so
  `break` there is refused, not lowered to a jump out of another function.
- **`while-some`:** a macro over `(while true (if-some … (do body…) (break)))`.

## Places without `&` (021)

`emit-lvalue-receiver` accepts, besides a binding:

- **Storage places:** an `aref`, or a field of a storage place, of struct or
  union type. It is emitted as `(ref place)`.
  - `place-value-type` recurses through `aref` and field places, because
    `node-type` answers null for an `aref` of a global array and for template
    method calls such as `(&s i)`.
- **Field places over a call:** when the base is a list whose `node-type` is
  null, the base is emitted once and the field's address taken from the
  result. A temporary struct value as the base is refused: it has no address.

`(Slice T)` (`lib/nucleus/slice.nuc`) is a pointer and a length whose
`invoke` returns `&T`. That gives C's `&a[i]` a bounds-checked spelling, and
`(Vector T)` can't do it because a vector's elements move when it grows.
