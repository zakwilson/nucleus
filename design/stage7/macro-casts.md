# Macro args casting

#### Designer

Macros are currently absolutely filled with `(cast ptr:Node foo)`. That's painfully verbose. Does the existing implicit cast feature allow eliminating most of these?

#### Robot

No — implicit cast can't help here. Member access (`(. p field)`),
`(ptr+ p k)`, `(deref p)`, etc. all need the element type *at compile
time* to compute offsets. The cleanup pass for stage-7 explicitly kept
those casts for that reason. `defcast ptr ptr:Node` doesn't help either:
even if a coercion fired, it would only fire when a `ptr:Node` is
*expected*, and `(. x car)` doesn't expect a particular pointee — it
demands one.

But the casts are eliminable, just from a different angle: the casts
exist because `emit-defmacro` (`src/nucleusc.nuc:3123`) binds every
macro parameter as raw `ty-ptr`. If we bind them as `ptr:Node` instead,
`(. x car)` works directly with no cast. Same for the `&rest` tail (a
linked list of `Node` cells) and the macro return value (the JIT ABI
already stores it as `ret ptr`, but the language-level type can be
`ptr:Node`).

Concretely:

1. `scope-define fn-scope pname ty-ptr ...` (line 3123) → use a
   `ptr:Node` Type. Same for the `&rest` binding.
2. The body's last-value check at line 3133 already requires `TY-PTR`;
   keep that, just expect the typed variant. emit-return already coerces
   `ptr:Node` ↔ `ptr` for the IR-level `ret ptr`.
3. Quasiquote builders (`build-cell`, etc.) return `ptr`; either retype
   them to `ptr:Node` or rely on the existing `ptr` → `ptr:Node`
   widening at assignment positions (it already works — that's how
   `let (n:ptr:Node (malloc ...))` compiles).
4. Bulk strip `(cast ptr:Node ...)` from `lib/macros.nuc`, the
   compiler's own AST-walking code that runs in macro context, and any
   user macros under `examples/`.

Risks:

- User code that explicitly types a macro param as `:ptr` (raw) and
  relies on it not being `ptr:Node`. I don't think any such code
  exists today — macro params are untyped at the source level — but
  worth a grep before flipping the default.
- Macros that pass an argument through to a function taking `ptr` of a
  *different* element type (e.g. `ptr:i8`). With `ptr:Node` as the
  param type, the call site would need an explicit cast where today no
  cast is needed because the param is raw `ptr`. Probably rare; the
  argument is almost always an AST fragment.
- The compiler's AST-walking helpers (`fprint-node`, `parse-type-from-node`,
  `node-len`, etc.) take `:ptr` not `:ptr:Node` for historical reasons,
  so call sites inside macros that pass a node *out* to a helper still
  work without any cast (widening `ptr:Node` → `ptr` is identity).

Scope: this is a small, mostly mechanical change. Proposed as one
commit: retype macro params + `&rest`, drop redundant casts in
`lib/macros.nuc` and any in-tree user macros, verify bootstrap fixed
point + tests. The numbers from the stage-7 cleanup pass suggest the
diff in `lib/macros.nuc` and friends will be substantial; the compiler
source itself only benefits where its AST walks happen to live inside
a `defmacro`, which is rare.


#### Designer

Nucleus is only used for its own compiler right now. Breaking user code is not a concern. Changing the signatures of helper functions is acceptable. Add documentation and an example of a macro passing through an argument of a different type.

#### Robot — implementation notes

Landed. Highlights:

- **`emit-defmacro`** now binds every macro parameter (and the `&rest`
  list) as `ptr:Node` rather than raw `ty-ptr`. The struct lookup for
  `Node` is done at the top of each macro compile (cheap; macros are
  rare). `(. p car)`, `(. p cdr)`, `(. p kind)`, `(. p s)` work
  directly on params with no cast.
- **`Node` struct fields** `car` and `cdr` retyped from `:ptr` to
  `:ptr:Node` in `lib/prelude.nuc`. This makes chained access
  (`(. (. p cdr) car)`) cast-free as well. Field offsets are
  unchanged — both old and new are 8-byte pointers — so the LLVM
  IR layout is identical.
- **`emit-cond`** previously decided result types with raw pointer
  identity (`(!= bty result-type)`). After the struct change, two
  branches of the same `cond` could legitimately produce
  `ptr:Node` and `ptr` (or two freshly-allocated `ptr:Node` Type
  wrappers). That tripped the variadic-math macros, which mix
  `(. args car)` (now `ptr:Node`) and `` `1 `` (raw `ptr`) across
  branches. Switched to `type-eq`, which already treats ptr↔ptr as
  equal regardless of element. `type-to-ir` for both is `"ptr"` so
  the phi IR is unchanged.
- **`repl-register-node`** updated to register `Node`'s `car`/`cdr`
  fields as `ptr:Node` to match the source-level struct, so REPL
  macro compilation sees the same field types.
- **Helper signatures** in `lib/node.nuc` retyped to use `ptr:Node`
  where natural: `alloc-node`, `make-cell`, `intern-symbol`,
  `node-at`, `node-len`, `node-is-list`. Callers passing raw `ptr`
  still work — same-kind ptr↔ptr is identity-coerce on both call-site
  args and return values.
- **`lib/macros.nuc`** stripped: every `(cast ptr:Node …)` is gone,
  and the few `:ptr` local bindings inside `dotimes` and `->` are
  now `:ptr:Node`. ~30 casts removed; readability is dramatically
  better.
- **Bootstrap binary** (`bin/nucleusc`) regenerated from the new
  source; bootstrap fixed-point holds (`make bootstrap` passes).
- **Test added.** `examples/macro-passthrough.nuc` plus its expected
  output exercises a `tprint` macro that dispatches on
  `(. x kind)` at expansion time and splices `~x` into a `printf`
  with a kind-specific format string. This is the “different value
  types through one macro” case the designer asked for: at the call
  site `~x` is variously `i32`, `ptr:i8`, `f64`, or raw `ptr`. The
  macro never has to think about the runtime type.
- **Docs.** `docs/builtins.md` `defmacro` row notes the `ptr:Node`
  param typing; a new section *Macros and pass-through arguments*
  shows the `tprint` example and explains why splicing a `ptr:Node`
  param into a quasiquote does not constrain the value type at the
  call site.

All 33 tests pass.

Patterns intentionally not touched in this commit:

- The compiler source itself (`src/nucleusc.nuc`) still has many
  `(cast ptr:Node …)` calls in non-macro AST-walking code. Those
  are reachable from regular `defn`s and would need a separate
  parameter-retyping pass; out of scope here.
- `lib/list.nuc`'s standalone `Node` struct (parallel definition for
  generic list usage) was left alone — it's used by `examples/list.nuc`,
  not by the compiler's macro system.
