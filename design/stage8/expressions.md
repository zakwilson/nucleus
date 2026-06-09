# Expressions and statements

## Implement

* ~~`inc!` and `dec!` (note: add `dec!`) should return the updated value, as should `set!`. `inc!` and `dec!` should probably be implemented in terms of `set!`, and should take an optional value defaulting to 1.~~ **Done.** `set!`, `.set!`, `aset!`, `ptr-set!` now yield the stored value. `inc!`/`dec!` are special forms that accept an optional delta (default 1) and yield the new value.
* ~~`case`, as a macro unless there's a performance reason to make it a special form~~ **Done** as a special form lowering to LLVM `switch`. Scheme semantics, integer keys only, no default clause (unmatched = UB).
* ~~`goto` both with a global `label` and a scoped `letlabel`~~ **Done** with a single function-scope `label`. Forward + backward jumps. Duplicate decls allowed (last wins). Computed gotos via `label-addr` / `goto-ptr`.

## Excluded - these are not a good fit for Nucleus

* Ternary operator - infix isn't sexp-friendly and `if` is only a couple chars more
* Comma operator - `do` is the Nucleus way
* Post increment - users can define a function or macro if they want

## Deferred

* Looping constructs with in-body modifiers like `break` / `continue` probably aren't necessary, and could be implemented as macros if they are.



#### Robot

### `inc!` / `dec!` / `set!` returning a value
1. Should the value be returned for *all* `set!` targets (locals, struct fields,
   array elements, deref'd pointers), or just locals?
2. `inc!` / `dec!` "in terms of `set!`" — lowered to `(set! x (+ x n))` at
   macro-expansion time, or kept as a special form that internally calls the
   `set!` codegen? The former is cleaner but evaluates the lvalue twice
   (problematic for `(inc! (get-field s 'x))`).
3. Are these currently special forms or already macros?

### `case`
1. Which semantics:
   - C-style `switch` with fallthrough and `break`?
   - Scheme-style `case` (each clause is a list of literals, no fallthrough,
     returns a value)?
   - Something else?
2. If lowered as a macro, target chained `cond`, or a real jump table for
   performance?

### `goto` / `label` / `letlabel`
1. Scoping: is `label` function-scoped (visible anywhere in the function body,
   like C) and `letlabel` block-scoped (only within the `letlabel` form)? Or is
   `label` truly file-global (jump across functions)?
2. Forward gotos as well as backward?
3. Interaction with `let` / stack-allocated state — handle skipping
   initializers (the C footgun)?
4. Compose with existing `for` / `while` macros, or strictly an escape hatch?
5. Computed gotos / jump tables (mentioned in stage8-list.md) in scope or
   deferred?
   
#### Designer

### inc!/dec!

1. Return the value for all targets
2. I suppose the efficiency advantage goes to the special form.
3. inc! is a special form defined in the compiler as emit-inc

### `case`

1. Scheme semantics
2. Performance is the goal here, or cond would be sufficient

### `goto`

1. Let's condense it to a single function-scope `label` for now.
2. Forward and backward
3. People using 'goto' in 2026 and beyond should know the risks. Don't forbid stupid mistakes. I might move this to an `unsafe` namespace in the future.
4. Keep the implementation simple and do what the user says.
5. In scope

#### Robot

  case — Scheme case matches on literal datums (ints, symbols, chars), with each clause holding a list of
   values plus an optional else. For a performance-driven special form, LLVM's switch instruction is
  integer-only. So:
  1. Restrict match keys to integer literals (and char/enum values that lower to ints)? Or also accept
  symbols/strings (which would force fallback codegen and undermine the perf goal)?
  2. Confirm syntax: (case expr ((1 2 3) ...) ((4) ...) (else ...)) — list of literals per clause, else
  as the catch-all?

  goto — surface syntax:
  1. (label foo) to declare a label in the function body, (goto foo) to jump — sound right?
  2. For computed gotos: label-as-value primitive — (label-addr foo) returning ptr, and (goto-ptr p) to
  jump? Or different naming?
  3. Are duplicate label names within a function an error, or last-wins?

  Once those are nailed I can implement. The inc!/dec!/set! piece is fully unblocked.
  
#### Designer

### `case`

1. Restrict it for now. Users who aren't optimizing can use `cond`.
2. That syntax comes close, but a bare value should be allowed to match a single value instead of requiring a single-element list. `_` should represent the default match.


### `goto`

1. Yes, `(label foo)` and `(goto foo)` within the same function body.
2. `label-addr` and `goto-ptr` are fine.
3. Last wins. Making label collisions an error could break composing macros that use labels. It's dangerous to compose macros with labels, but that's no reason to forbid it.

----

#### Designer

## Implement: 

* ~~Designated initializers with `(name val)` or `(index val)` syntax~~ **Done.** `(name val)` for struct fields, `(index val)` for array slots. Mix freely with bare positional values within a single literal.
* ~~Compound literals~~ **Done.** Structs: `(StructName init...)` overloads the struct name; yields `ptr:StructName`, alloca-backed. Arrays: `(array ElemType init...)`; length implicit from inits; unspecified slots zero-init.
