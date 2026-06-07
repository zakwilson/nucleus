# Conventions

## Design documents

When a feature in a design document gets implemented, add a **Status:** note but preserve the original design discussion and commentary. The design reasoning is a valuable record of how decisions were made and remains useful context for future work even after implementation.

## Format helpers are fixed-arity (`src/format.nuc`)

`fmt-s` takes **exactly one** `%s` argument; `fmt-i32` exactly one `%d`/`%ld`, etc. They are plain functions, not variadic. Passing a format string with more conversions than the helper's parameter count makes `snprintf` read a garbage vararg and typically **segfaults the compiler** (no error — just a crash with empty output). For multiple substitutions use the dedicated variants: `fmt-2s` (two strings), `fmt-sd` (string + int), `fmt-i32-i32` (two ints), `fmt-2s-i` (two strings + int). If you need a new shape, add a helper in `src/format.nuc` rather than overloading an existing one.

## `node-type` mirrors `emit-node` (keep them in lockstep)

`emit-node` (src/nucleusc.nuc) sets the type a node propagates to its parent from
`node-type(n, scope)` (Stage 9 rung 3) whenever that returns non-null. So the
non-emitting type pass and codegen share **one typing rule per node kind**. If you
add a new special form to `emit-list`, or change the result type any `emit-*`
function returns, **update the matching branch in `node-type` (and its helpers
`node-type-call` / `node-type-block` / `node-type-field` / …) in the same change**.
The `make bootstrap` fixed-point test enforces this: a divergence makes the
compiler emit different IR than it consumes and `stage1.ll != stage2.ll`. A form
that `node-type` deliberately does not model returns null (codegen then keeps its
own type) — that's the escape hatch for control-flow/expansion-dependent results
(`cond`, macros, `quasiquote`), not a license to skip updating modelled forms.

## `defn` bodies are not desugared (colon-symbols survive)

`desugar` only rewrites **binding positions** of known forms: the `defn` name and
param list, `defvar`/`extern`/`declare` names, `defstruct` fields, and `let`/`with`
binding *names*. A `defn`'s **body is left untouched**, so a colon-typed symbol in
the body (`r:T`, `x:ptr:Node`, `(cast i32 …)`) stays a single `NODE-SYM` —
`split-typed`/`extract-name-and-type` parse it lazily in value position. So an AST
transform that walks a `defn` form sees the *desugared* shapes in the signature
(`(a T)`, `(maxv T)`) but the *raw colon* shapes in the body (`r:T`). The Stage 9
generic monomorphizer (`subst-tyvars-node`) therefore substitutes at the
colon-*segment* level (like `subst-self-node` for protocols), not by matching
standalone symbol nodes — that handles both shapes uniformly.

## Emitting a function mid-emission needs the worklist, not a direct `emit-defn`

`emit-defn` calls `reset-function-state`, clobbering the per-function streams
(`g-entry-stream`/`g-body-stream`). So you cannot synthesize and emit a new
function while another function's body is being emitted. The generic
monomorphizer (rung 4) handles this by *registering* the stamped method
immediately (so the active call site can name its `@name.<tok>…` symbol) but
*queuing the body* on `g-mono-worklist`, drained by `drain-mono-worklist` at the
end of `emit-toplevel-forms` when no function emission is in progress. LLVM
textual IR allows forward references to functions defined later in the module, so
the call emitted earlier links fine. Reuse this pattern for any future
"emit-a-function-on-demand-from-a-call-site" feature.

## `TY-TYVAR` is a check-only type — never let it reach codegen

The `TY-TYVAR` type kind exists solely for the Stage 9 rung-4 **A2** def-time check
of bounded-generic bodies (`gcheck`/`check-generic-templates`): it types a
parameter declared as an abstract type variable so the checker can verify only the
constraints' protocol methods are used. Generic templates emit code *only after
monomorphization* (every type concrete), so `TY-TYVAR` must never flow into
`emit-*`, `type-to-ir`, `type-size`, or `type-mangle-token`. The `node-type`↔`emit`
lockstep is not at risk because the abstract scope exists only inside the A2 walk;
during real emission no scope binding is `TY-TYVAR`. If you add a new place that
manufactures or stores types, keep `TY-TYVAR` confined to the checker.

## `?`/`!` in user function names break LLVM symbols

A solitary/overloaded `defn` named `lt?` is emitted as `@lt?` / `@lt?.i32.i32`,
which is **invalid LLVM IR** (`?` is not in the unquoted-identifier charset; it
would need `@"lt?"`). The compiler does not currently quote symbols, so user
*function* names should stick to `[A-Za-z0-9$._-]`. (`set!`/`inc!`/`lt?`-style
names are fine for special forms and macros, which never become `@`-symbols.)

## C interop invariant

All Nucleus types must be representable in C. This is a core design requirement — Nucleus is a drop-in replacement for C, and any function or data structure defined in Nucleus must be consumable from C. If you encounter or are asked to create a type that cannot be represented as a C struct/function/enum (e.g. closures with hidden captured environments, tagged unions requiring runtime support), flag it as a design violation before proceeding.
