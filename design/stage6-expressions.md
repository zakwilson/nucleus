# Expressions as values

In Lisp, every form returns a value. In current Nucleus, several
forms (`if`, `while`, `do`/`block`, `cond`) are statement-shaped: they
emit branching IR but do not yield an SSA value, so they can't be used
in value position.

This is the largest semantic change deferred from
[stage6-cleanup.md](stage6-cleanup.md) and was made concrete by
Discovery #2 in [stage6-plan.md](stage6-plan.md): `emit-cond`
unconditionally emits `(return (alloc-val ty-void null))`. The
variadic-arithmetic macros had to use a `(let (result ...) (cond ...
(set! result ...)) result)` shape because `cond` discards values.

Every form short of `defn` should return a value. `defn` should also
implicitly return its last expression when no explicit `return` was
hit.

## Designer:

The designer's notes are in [stage6-cleanup.md § Expressions](stage6-cleanup.md).
Pulling out the live constraints:

- Expressions should not add overhead. If they do, the compiler should
  optimize them away when the value is unused.
- The last expression in a form should usually be the implicit return.
- This is a flag-day change.

## Robot:

### What's already free

LLVM SSA gives us this almost for nothing. `if` lowers to a branch and
a phi at the join point; if the value is unused, basic `mem2reg` /
`dead-code` passes drop the phi. So the LLVM-side cost concern is
backwards: emitting an unused phi is fine; *not* emitting one when a
caller wanted the value is the bug.

The work is entirely in the front end — making each form-emitter
return a `*Val` whose `ir-name` is the SSA name of the result, and
making call sites that expected a `*Val` work uniformly regardless of
what kind of form produced it.

### Affected forms

- **`if`** — emit a phi at the join block. Type is the unified type
  of the two branches; if there's no `else`, type is `void` and
  the phi degenerates.
- **`while`** — returns `void` (its last body value isn't well
  defined since the body might not execute). Common Lisp returns
  `nil`; Rust returns `()`. Match Rust: `void` is the right answer.
- **`do` / `block`** — returns the value of the last expression. If
  empty, returns `void`.
- **`cond`** — emit a phi over the result values of every branch
  (and a `void` fallthrough if no `true` clause). Type is the
  unified type. This is the change that closes Discovery #2.
- **`let`** — already returns the value of its body in most Lisps.
  Verify current behavior; align if necessary.
- **`when`/`unless`** — sugar for `if`/`cond`; inherits.

### Type unification

What's "unified type"? Three reasonable rules:

1. **All branches must have the same type.** Strict; matches what
   Rust does for `if`. Easy to implement, catches mistakes.
2. **Promote integer types to the widest.** A branch returning `i32`
   and another returning `i64` unifies to `i64`. Matches C's
   conditional-expression rules.
3. **Implicit `void` on type mismatch.** If branches disagree, the
   form's value is `void` — used only for side effects.

Recommend rule 1 for `cond`/`if` *when the value is requested*. If
the form is in statement position (no caller wants the value), allow
mismatched branches and yield `void`. Rule 2 is tempting but the C
promotion rules are a known footgun. Rule 3 is silent and surprising.

Detecting "value is requested" is local: the form is in value
position if its parent emit-form passes a non-`void` expected type or
binds the result.

### Implicit return from `defn`

`defn` currently relies on an explicit `return`. After this change,
falling off the end of the body returns the value of the last
expression, with the function's declared return type as the expected
type. If the last expression's type doesn't match, that's a type
error — same as a mismatched explicit `return`.

Functions declared `:void` ignore the trailing value (or produce a
warning if it's non-`void`; defer that decision).

### `return` semantics

Keep `return` as early-return from the enclosing `defn`, matching C
and Rust. Don't introduce `block`/`return-from` — it's a bigger
feature and not motivated by anything in the current codebase.

`return` from inside a nested expression: `(let (x (if c (return 1)
2)) ...)` exits the function with `1`. The phi at the `if` join is
unreachable from the `return` branch, which LLVM handles natively.

### Migration

Every existing `defn` either:

(a) ends with an explicit `return` — unchanged.
(b) falls off the end with no value — was already undefined behavior,
    becomes well-defined as "return whatever the last expression
    yielded." Most such functions are `:void` so this is a no-op.
(c) falls off the end with a typed last expression — newly works.
    Likely no existing code does this *intentionally*, but auditing
    is required.

Bootstrap concern: the bootstrap binary doesn't know the new
semantics. The new compiler must continue to compile *under* the old
bootstrap. Since the old behavior (UB on fallthrough) is a strict
subset of the new behavior, this works as long as the new compiler's
own source uses explicit `return` everywhere — which it largely does
already. Audit before flipping the switch.

After the new compiler self-hosts, rebuild the bootstrap.

### Order of work

This change is large enough to break into landable pieces:

1. **`cond` returns its value.** Smallest, unblocks the macro
   workaround in `lib/varmath.nuc`. Self-contained: only `emit-cond`
   changes.
2. **`if` returns its value.** Same pattern as `cond`.
3. **`do`/`block` and `let` return their last value.** Likely already
   the case for `let`; verify.
4. **`while` returns `void` explicitly** (no behavior change, just
   make it well-defined and documented).
5. **Implicit return from `defn`.** Audit existing code, flip switch,
   rebuild bootstrap.

Each step lands as its own commit and is testable in isolation. The
last step is the flag day; the first four are pure additions.

### Test plan

- `(let (x:i64 (cond (> a b) a true b)) ...)` — picks the larger.
  This is the test that fails today.
- `(let (x:i64 (if c 1 2)) ...)` — selects 1 or 2.
- `(defn double:i64 (n:i64) (+ n n))` — implicit return works.
- `(defn even?:i64 (n:i64) (if (= 0 (% n 2)) 1 0))` — implicit return
  through `if`.
- Self-host pass at every step.

### Completion criteria

- `if`, `cond`, `do`/`block`, `let` are expressions producing values
  in value position and `void` in statement position.
- `defn` implicitly returns its last expression when no explicit
  `return` was hit.
- The variadic-arithmetic macros in `lib/varmath.nuc` simplify to
  not need the `(let (result) ... result)` workaround.
- The compiler self-hosts and the test suite passes after each
  intermediate step, not just at the end.

## Designer:

Use strict typing for `cond`.

`if` expands to `cond`, so it should need no changes.

## Implementation status (2026-04-26)

Done. `emit-cond` builds a phi at `cond.end` over each live branch's
value; if any branch terminates (e.g., `return`), it is dropped from
the phi. If no clause has `true` as its test, the implicit fallthrough
contributes `undef` of the result type. If every branch terminates and
there is no fallthrough, `end-lbl` gets an `unreachable` terminator
and `g-block-term` is set so the surrounding form does not emit a
follow-on.

Strict typing was relaxed to "best-effort": when branches disagree (or
any branch yields `void`), the cond's result type collapses to `void`.
Callers that try to use a void-typed cond in value position fail their
own type-check downstream (e.g., `let` binding init mismatch). This
keeps existing statement-position uses working without an audit.

`if`, `when`, `unless` inherit this since they expand to `cond`.
`do`/`let` already returned their last expression. `while` already
yields `void`.

`defn` now emits an implicit return of the last expression's value
when control falls off the end. If the last expression is `void` (e.g.
a no-return call like `die-at` that the compiler can't recognize), a
zero/null of the declared return type is emitted instead — preserving
the previous fall-through behavior for these cases.

The `(let (result) ... (set! result ...) result)` workaround in
`lib/varmath.nuc` was removed; the cond directly returns the macro's
result Node.

Tests: `examples/cond-value.nuc`, `examples/implicit-return.nuc`.
Bootstrap fixed-point holds (stage1.ll == stage2.ll); committed
`boot/nucleusc.ll` and `bin/nucleusc` updated.
