# Special Forms and Operators

## Special Forms

`do`, `let`, and `cond` are *expressions*: each yields the value of its
last evaluated sub-expression. For `cond`, every live branch must
produce the same type, otherwise the form's value is `void` (which is
fine for statement position but rejects use in value position). If a
`cond` has no `true` final clause, the implicit fallthrough contributes
`undef` of the result type. `if` (which expands to `cond`) inherits
this behavior. `while` is statement-shaped: it always yields `void`.

`defn` implicitly returns its last expression's value when control
reaches the end of the body without an explicit `return`. The last
expression's type must match the declared return type; if the last
expression yields `void` (e.g., a side-effect or no-return call like
`die-at`), a default zero/null of the return type is emitted.

| Name | Description | C Equivalent |
|------|-------------|--------------|
| `do` | Sequence multiple expressions; yields the last | `{ ... }` block |
| `let` | Bind local variables; yields the body's last expression | local variable declaration |
| `with` | Like `let`, but **owns** any binding whose init is a libc allocator (`malloc`/`calloc`/`realloc`/`strdup`, possibly through `cast`) or whose declared type conforms to the `Drop` protocol. Owned bindings are released at scope exit (libc → `free`; Drop → statically dispatched `(drop b)`, null-guarded) in reverse binding order, on fall-through and on early `return`. The compiler verifies at compile time that an owned resource does not **escape** the scope — see [Pointer lifecycle](#pointer-lifecycle-escape-analysis). Use `(move b)` to transfer ownership out. | `let` + scoped `free` / RAII |
| `cond` | Multi-way conditional; yields the matched branch's value (strict-typed across branches) | `if` / `else if` / `else` chain |
| `case` | Integer-keyed dispatch; lowers to LLVM `switch`. Each clause is `(KEY body...)` where KEY is an integer literal, a list of integer literals, or the symbol `_` (default). With no `_` clause, an unmatched scrutinee hits `unreachable` (UB). Yields the matched branch's value (strict-typed across branches), like `cond`. | `switch` / `default:` |
| `match` | Eliminate a `defunion` value (or a `defenum` integer) by arm, with exhaustiveness checking. See [Unions and tagged sums](structs-unions.md#unions-and-tagged-sums). | `switch` on the tag |
| `make` | Construct a `defunion` value by arm: `(make Type arm args...)` — the explicit-instance spelling required for template instances, e.g. `(make (Result i64 i32) ok v)`. | designated initializer |
| `while` | Loop; yields `void` | `while` |
| `set!` | Assign to a variable; yields the assigned value | `x = val` |
| `inc!` | Increment a variable by 1 (or by an optional delta). Yields the new value. | `x++` / `x += n` |
| `dec!` | Decrement a variable by 1 (or by an optional delta). Yields the new value. | `x--` / `x -= n` |
| `label` | Declare a function-scoped label. Forward and backward gotos both resolve. Duplicate declarations of the same name are allowed — the last one in textual order is the canonical target. | label: |
| `goto` | Unconditional jump to a label declared anywhere in the current function. | `goto label` |
| `label-addr` | Yields a `ptr` to a label (for computed gotos). | `&&label` (GCC) |
| `goto-ptr` | Indirect branch to a label address. The IR lists every label declared in the current function as a possible destination. | `goto *p` (GCC) |
| `return` | Return from function | `return` |
| `not` | Logical negation | `!x` |
| `and` | **Variadic prelude macro** (same split as `_+`/`+`) that right-folds to the binary `_and` primitive: `(and)`→`true`, `(and x)`→`x`, `(and a b c…)`→`(_and a (and b c…))`. For ≥2 args each operand is i1-checked and evaluated left-to-right, stopping at the first false; cumulative narrowing is preserved across the chain (a later `(m field)` typechecks after an earlier `(!= m null)`). The 1-arg form returns `x` **unchecked** — no i1 check, matching CL/`+` variadic semantics (the i1 check fires only inside the ≥2-arg binary lowering). Fold table: [Variadic logical operators](macros.md#variadic-logical-operators). | `&&` (N-ary) |
| `or` | **Variadic prelude macro** that right-folds to the binary `_or` primitive: `(or)`→`false`, `(or x)`→`x`, `(or a b c…)`→`(_or a (or b c…))`. For ≥2 args each operand is i1-checked and evaluated left-to-right, stopping at the first true; cumulative narrowing is preserved. The 1-arg form returns `x` **unchecked**. Fold table: [Variadic logical operators](macros.md#variadic-logical-operators). | `\|\|` (N-ary) |
| `_and` | Binary short-circuit logical AND primitive — the underscore-prefixed form behind the `and` macro (same split as `_+` behind `+`). Both operands are i1-checked; the RHS is evaluated, and narrows under the LHS, only when the LHS is true. Usable directly for hand-written binary short-circuit. | `&&` |
| `_or` | Binary short-circuit logical OR primitive — the underscore-prefixed form behind the `or` macro. Both operands are i1-checked; the RHS is evaluated, and narrows under the LHS, only when the LHS is false. Usable directly for hand-written binary short-circuit. | `\|\|` |
| `cast` | Type cast | `(type)x` |
| `addr-of` | Take address of a variable. The address of **frame-local storage** (a `let`/`with` value binding or a by-value parameter) is escape-tracked so it cannot be returned — see [Pointer lifecycle](#pointer-lifecycle-escape-analysis); the address of a global or of a reference/pointer binding is not. | `&x` |
| `deref` | Dereference a pointer (reader sugar: `@p` → `(deref p)`) | `*p` |
| `ptr-set!` | Write through a pointer; yields the stored value | `*p = val` |
| `ptr+` | Pointer arithmetic | `p + n` |
| `.` | Struct field access; equivalent to head position `(s field)` and lowers to the `_get` primitive for a plain struct. | `s.field` |
| `_get` | Low-level struct field read (compiler-internal primitive; bypasses any user `get` override). Prefer head position `(s field)` in ordinary code; use `_get` only where head position would dispatch wrongly (a user `get` method reading its own field, or a struct held in a special-form-named variable). | `s.field` |
| `.set!` | Struct field assignment; yields the stored value | `s.field = val` |
| `get` | Member access / field read: `(get s 'field)` ≡ `(s field)`; for a plain struct this lowers to the `_get` primitive (zero-overhead), overridable per type. See [Callable values](#callable-values-non-function-call-position) | `s.field` |
| `invoke` | General call on a value: `(invoke s 3)` ≡ `(s 3)`; user-defined (`Seq`/`Call`) | `s(3)` / `s[3]` |
| `sizeof` | Size of a type | `sizeof(T)` |
| `alloca` | Stack-allocate memory | `alloca()` / VLA |
| `char` | Character literal | `'c'` |
| `aref` | Array element access | `arr[i]` |
| `aset!` | Array element assignment; yields the stored value | `arr[i] = val` |
| `(StructName init...)` | Compound struct literal. Each `init` is either `(field val)` for a designated initializer or a bare value for a positional one (positional inits fill the next field that has not been designated). Unspecified fields are zero-initialized. Yields `ptr:StructName`, alloca-backed (stack lifetime is the enclosing function). Defining a function with the same name as a struct is a compile-time error (the function would shadow the constructor). | `(struct S){.f = v, ...}` |
| `array` | `(array ElemType init...)` — array compound literal. Each `init` is either `(index val)` (designated) or a bare value (positional). Length is implicit: `max(positional-count, max-designated-index + 1)`. Unspecified slots are zero-initialized. Yields `ptr:ElemType`, alloca-backed. | `(T[]){1, 2, [3] = 99}` |
| `quote` | Yields its argument as a `Node*` (reader sugar: `'x` → `(quote x)`). Quoted symbols are interned — see [Symbols](types.md#symbols). | — |
| `quasiquote` | Like `quote` but `~expr` splices a runtime value and `~@list` splices a list (reader: `` `x ``, `~x`, `~@x`) | — |
| `compile-time` | Execute body forms at compile time via LLVM JIT; output goes to stderr | — |
| `funcall` | Call a typed function pointer: `(funcall fn args...)`. The function pointer must have a `TY-FN` type with known return type and parameter types. | `fn(args...)` |
| `funcall-void` | Call a function pointer with no arguments and no return value | `fn()` |
| `funcall-ptr-1` | Call a `ptr` function pointer with one `ptr` argument, returning `ptr` | `fn(arg)` |
| `funcall-ptr-i32` | Call a `ptr` function pointer with no arguments, returning `i32` | `((int(*)())fn)()` |
| `funcall-ptr-i64` | Call a `ptr` function pointer with no arguments, returning `i64` | `((long(*)())fn)()` |
| `funcall-ptr-ptr` | Call a `ptr` function pointer with no arguments, returning `ptr` | `((void*(*)())fn)()` |
| `gensym` | Return a fresh unique symbol `Node*` (e.g. `__gs_0`); for use in macro bodies to avoid variable capture | — |
| `some` | `(some r)` — wrap a non-null `(ref T)` as `?T` / `(Maybe (ref T))`. Pure relabel, no IR. | — |
| `as-ref` | `(as-ref p)` — launder a raw pointer into `?T` (null stays none). Pure relabel, no IR; narrow before use. | — |
| `unwrap` | `(unwrap m)` — the `(ref T)` inside a `?T`, or trap (`llvm.trap`) if none. The one runtime branch nullability costs, paid only where written. | `assert(p); p` |
| `unwrap-or` | `(unwrap-or m default)` — the `(ref T)` inside, or `default` (evaluated only on the none path; must itself be `(ref ...)`-compatible). | `p ? p : d` |
| `if-some` | `(if-some (x m) then else)` — if `m` is non-null, bind `x:(ref T)` in `then`; else evaluate `else`. Desugars to `cond`, so its value/typing rules match `if`. | `if ((x = m)) … else …` |
| `when-some` | `(when-some (x m) body…)` — one-armed `if-some`. | `if ((x = m)) { … }` |
| `move` | `(move b)` — transfer ownership of a `with`-owned binding out: disarms its scope-exit cleanup, yields the value with its escape taint cleared, and marks `b` consumed (later uses are "use after move"; reassignment revives it). | — |
| `defer` | `(defer expr)` — register `expr` as an ad-hoc cleanup on the enclosing binding scope (nearest `let`/`with`/function body), re-emitted at every exit path in reverse registration order. Lexical, not dynamic: it runs at scope exit whether or not control reached the `defer` site. | `goto cleanup` discipline |
| `fn` | `(fn (params):ret body…)` — an **anonymous function**. The body may reference its own parameters and top-level names (`defconst` / global `defvar` / another `defn`), but **not** any enclosing runtime local (a `let`/`with` binding or a by-value parameter); doing so is a compile error directing the author to `vfn`/`mfn`/`cfn`. The form is lambda-lifted to a fresh top-level function and its value is that function's pointer, so a non-capturing `fn` is a true function pointer with no environment and no runtime overhead — usable inline, storable in a variable, passable as an argument, and C-callable (e.g. a `qsort` comparator). The trailing `:ret` is the return type, matching the `(x:i32):i32` convention; a parenthesised return type (`(ref T)`) uses the space-separated list form. A local binding named `fn` shadows this keyword. (Stage 13 — see [lambda.md](../design/stage13/lambda.md).) | function pointer / non-capturing lambda |
| `vfn` | `(vfn (params):ret body…)` — a **clone-capture closure**. Like `fn` but it *captures* the enclosing runtime locals its body references, by **clone** (the source survives untouched). Each capture must conform to `Clone` (see [generics.md](generics.md)): a POD / `Drop`-free capture is a bitwise value copy (no allocation; the closure owns nothing and is not `Drop`); an owning (`Drop`) capture is deep-cloned via its hand-written `clone`, and the closure then owns the copy and conforms to `Drop` with a synthesized field-wise cleanup. A `Drop` capture with no `Clone` is rejected, directing the author to `mfn`. The closure lowers to an anonymous by-value struct (one field per capture) plus a synthesized `invoke` method of the lambda's arity, so it is **callable with ordinary call syntax** — `(c arg…)` routes to `invoke` via the callable-values rule, no new call form needed. A non-capturing `vfn` folds to a bare `fn` pointer (zero overhead). The trailing `:ret` and parenthesised-return-type rule match `fn`; a local named `vfn` shadows this keyword. (Stage 13 — see [lambda.md](../design/stage13/lambda.md).) | clone-capture closure (by-value, owning iff a capture is `Drop`) |
| `mfn` | `(mfn (params):ret body…)` — a **move-capture closure**. Like `fn` but it *captures* the enclosing runtime locals its body references, by **move** (the source is consumed). An owned capture (a `with`-owned binding) is routed through the `move` sink: its scope-exit cleanup is disarmed, the value is yielded with escape taint cleared, and the binding is marked consumed (later uses are "use after move"); the closure owns the moved resource and conforms to `Drop` with a synthesized field-wise cleanup (same synthesis as `vfn`). A POD capture (a `let` binding or by-value parameter) is a bitwise copy — move == copy when there is no cleanup to disarm. Because the move transfers ownership and clears taint, an `mfn` created inside a `with` may be **returned/moved out** of that scope: the disarmed source no longer frees the resource, so the return is sound (this is the form that exports an owned value out of a `with` scope). No allocator; travels by value. The closure lowers to an anonymous by-value struct (one field per capture) plus a synthesized `invoke` method, callable with ordinary call syntax; a non-capturing `mfn` folds to a bare `fn` pointer. The trailing `:ret` and parenthesised-return-type rule match `fn`; a local named `mfn` shadows this keyword. (Stage 13 — see [lambda.md](../design/stage13/lambda.md).) | move-capture closure (by-value, owning; consumes `with`-owned sources) |
| `cfn` | `(cfn alloc (params):ret body…)` — a **reference-capture closure**. Like `fn` but it *captures* the enclosing runtime locals its body references, by **reference** (the referents are borrowed, not owned). The bare first operand `alloc` is a `(ref AllocHandle)` (see [allocators.md](allocators.md)) — an argument, not part of the params/return group; when it is itself a call (`(default-allocator)`) the parentheses are call parentheses. The environment is an anonymous struct of **pointers** into the captured storage (one `(ptr T)` field per capture), preceded by a stored `AllocHandle`; the env's own storage is allocated through `alloc` (a heap block), and the closure conforms to `Drop` with a synthesized `drop` that frees the env block via the stored handle (mirroring how a collection frees its buffer). The closure lowers to that env struct plus a synthesized `invoke` method, callable with ordinary call syntax; in the body a value use of a capture reads through the stored pointer (`(deref (. self cap)`) and `(addr-of cap)` is the stored pointer itself (`(. self cap)`). The closure value **inherits the region of each captured reference** (see [Pointer lifecycle](#pointer-lifecycle-escape-analysis)): returning (or otherwise escaping) it past a captured `with`-owned or frame-local referent's scope is rejected at the existing escape sinks, while a `cfn` capturing only caller-owned `(ref …)` parameters or globals may be returned freely. To export a *value* computed from a captured reference, copy or `deref` it in the body so the result is a value, not a tainted reference. A non-capturing `cfn` folds to a bare `fn` pointer (the `alloc` operand is dropped). The trailing `:ret` and parenthesised-return-type rule match `fn`; a local named `cfn` shadows this keyword. (Stage 13 — see [lambda.md](../design/stage13/lambda.md).) | reference-capture closure (struct of pointers + stored `AllocHandle`, escape-checked) |

**Closures and `invoke` lowering.** Each capturing closure (`vfn`/`mfn`/`cfn`)
lowers to an anonymous struct holding its captured state plus a synthesized
**`invoke`** method of the closure's natural arity. Because callable-values
routes `(c arg…)` to `invoke` on the mere *existence* of an `invoke` method (see
[Callable values](#callable-values-non-function-call-position) below), a closure
is callable with ordinary call syntax and needs no fixed protocol and no arity
ceiling — arity is whatever `invoke` declares, routed by the callee's type. A
non-capturing `fn`/`vfn`/`mfn`/`cfn` folds to a bare function pointer, and a
function-pointer head folds to an indirect call as usual. Conformance to a
function protocol (`UnaryFn`/`FoldFn`) is never pre-declared on a closure; it is
derived structurally on demand at the use site (see
[Generics](generics.md#structural-function-protocol-conformance-closures)).
Stage 13 detail: [lambda.md](../design/stage13/lambda.md).

**Naming a closure (`let`/`with` env-type inference).** A capturing closure's
environment type is anonymous and compiler-minted, so it cannot be *spelled* in a
binding's `:type`. A **bare-symbol** `let`/`with` binding with **no** type
annotation therefore **infers** its type from the closure value's environment
type, so a closure can be bound to a name and then called, `with`-dropped, or
passed by name to a generic combinator — not only passed inline:

```
(let (f (cfn h (x:i32):i32 (return (+ x mult))))   ; type inferred — no :type
  (f 1))                                            ; named closure call
(with (g (cfn h (x:i32):i32 …))                     ; owning env drops at with-exit
  (g 2))                                             ; via the with-drop-method path
(let (acc (vfn (a:i32 x:i32):i32 …))                ; named operand, type-keyed
  (reduce acc 0 it))                                 ; conformance — same as inline
```

The inference fires **only** on a bare symbol with no annotation (the case that
previously errored "missing `:type`"); typed and destructuring bindings are
unchanged, and no other type is inferred beyond what the init value already
exposes. A `with`-bound closure that owns its environment (a `cfn`, or a
`vfn`/`mfn` over a `Drop` capture) drops it at scope exit through the ordinary
`with`-binding `Drop` path.

**Storable closures.** When a closure needs to be placed in a `Vector`, a
struct field, or returned from a `defn`, use `(BoxedFn (params…) ret)` — a
spellable, fixed-size, owning fat-pointer type that erases the concrete env.
The boxing coercion is automatic at assignment into a `BoxedFn`-typed slot and
costs a heap allocation (process-default libc allocator); dispatch is via an
indirect vtable call. See [Type erasure](generics.md#type-erasure-boxedfn-and-dyn-protocol) in `docs/generics.md`.

**Mutable capture (`set!`/`inc!`/`dec!` on a captured name).** A closure body
may **mutate** a captured name with `set!`, `inc!`, or `dec!`. The rewrite
depends on the closure's capture mode:

- **`vfn`/`mfn` (by-value capture):** the env field holds the value. `(set! c v)`
  rewrites to `(.set! self c v)` (field store); `(inc! c)` / `(dec! c)` expand to
  the read-modify-write equivalent `(.set! self c (op (. self c) 1))`. The mutation
  lands in the env field and **persists across successive calls** to the same
  closure instance (since `invoke` receives `self` as a `(ref Env)` — a mutable
  reference). The outer binding is unaffected (it was copied/moved into the env at
  closure creation).

- **`cfn` (by-reference capture):** the env field holds a *pointer* into the outer
  binding's storage. `(set! c v)` rewrites to `(ptr-set! (. self c) v)` — a store
  through the captured pointer. `(inc! c)` / `(dec! c)` become `(ptr-set! (. self c)
  (op (deref (. self c)) 1))`. The **outer binding sees the mutation** after each
  call, as with any by-reference write-back. The existing L1 store-sink safety
  checks are preserved.

A `set!`/`inc!`/`dec!` whose target is a **closure-local binding** (a `let`
inside the closure body, or a closure parameter) is not a capture and is rewritten
as an ordinary local assignment, unchanged.

**Owning-closure export and struct-value `with` drop (CE-3).** A `with`-bound
value of any type that conforms to `Drop` — including struct-value bindings, not
only `ptr`-typed ones — drops correctly at scope exit. An `mfn` may capture a
struct-value `Drop` binding by move: the source binding's cleanup is disarmed at
closure-creation time, the closure owns the moved resource, and the resource drops
at the closure's eventual scope exit with no double-free; a later reference to the
consumed source binding (via symbol or `addr-of`) is a compile error ("use after
move"). The by-value struct ABI copies struct bytes correctly so owning env structs
round-trip through returns and `with`-bindings without corruption. See
`examples/ce3-owning-closure.nuc`.

**Returning a closure across a function boundary** requires `BoxedFn` as the
return type: the anonymous env type (`__vfn_env_N`) cannot be spelled in a
return-type position, but `(BoxedFn (params…) ret)` can. Declare the `defn`'s
return type as `(BoxedFn …)` and return the closure expression with an explicit
`(BoxedFn …)` target annotation; the boxing coercion fires automatically and
the fat pointer is returned by value. Within a function body, closure values can
be created inside a `with`, moved out of it, held in a `let`/`with` binding
(CE-1), and used as local operands with no boxing overhead. See
[Type erasure](generics.md#type-erasure-boxedfn-and-dyn-protocol) and
`examples/boxedfn.nuc`.

## Pointer lifecycle: escape analysis

The compiler tracks pointer provenance (its **taint**) at compile time and
rejects pointers that would outlive the storage they point into. This is a
**pointer-provenance** check, separate from ownership: **ownership / `Drop` /
cleanup is a `with`-only concern** (it determines what code runs at scope exit —
`free`/`drop`), while the **escape check applies to all frame-local storage** and
runs no code. `let` confers no ownership and runs no drop; it is a plain binding
that is nonetheless subject to the escape check, because the frame it lives in is
reclaimed at function return. Two storage classes feed the same machinery (see
`design/stage10/lifecycle.md` and `design/stage13/lambda.md` §"Lifetime and escape
analysis"):

1. **`with`-owned resources** — a `with` binding whose init is a libc allocator,
   or whose declared type conforms to `Drop`, is an **owning binding**: its
   resource is released at scope exit, so any pointer still aliasing it
   afterwards would dangle. (Concern: ownership/cleanup.)
2. **Frame-local storage** — taking the address of a plain `let`/`with` value
   binding or a **by-value parameter** (all of which live in a stack frame
   alloca) yields a pointer into the frame, which is reclaimed when the function
   returns. (Concern: pointer provenance only — `let` runs **no** drop and
   confers **no** ownership; this is purely a use-after-free check.)

Both share one mechanism:

- Taint follows pointer **identity**: binding a tainted value (`let`/`with`/
  `set!`), `cast`, `ptr+`, `.&`, `addr-of`, and control-flow joins keep it.
  Copying the pointee **value** out (`deref`, field loads) clears it — so
  `(return (deref p))` and `(return (p count))` are fine.
- `addr-of` (and `.&` through it) is the **frame-local taint source**. It does
  **not** taint:
  - the address of a **global** (`defvar`/`defconst`) — it outlives any frame;
  - the address of a **reference/pointer parameter** or any pointer-typed local
    — the slot holds a pointer whose pointee is caller-owned, so a value
    *loaded out of* it may legitimately be returned (the existing untracked
    imprecision boundary). So `(.& v field)` through a `(ref T)` parameter
    still returns fine.
- **Escape sinks** (compile errors on tainted operands):
  - **`return`** rejects *any* tainted value — both a `with`-owned alias and a
    pointer into frame-local storage. This is the function-frame boundary, and
    it catches the classic `(return (addr-of x))` / `return &local` bug.
  - **Stores into longer-lived memory** (`set!` to an outer binding;
    `aset!`/`.set!`/`ptr-set!` into memory not owned by the same or an inner
    `with`) reject **`with`-owned** taint only. A frame-local pointer stored
    into other frame memory is an intra-frame borrow; full nested-region store
    precision is deferred, so the first cut enforces the frame boundary at
    `return`. Manually calling `free`/`drop` on an owning binding is a
    double-free error.
- **`(move b)`** is the sanctioned way out of a `with` scope: it disarms the
  cleanup, clears the taint, and consumes the binding.
- Passing a tainted value as a **function argument** is allowed — downward flow
  is a borrow (the callee retaining the pointer is the same residual risk as C),
  and pointers loaded *out of* a resource are not tracked — the two documented
  imprecision boundaries of the cheap, intraprocedural tier.

```lisp
(defn bad:ptr ()
  (let (x:i32 5)
    (return (addr-of x))))        ; ERROR: address of frame-local 'x' escapes via return

(defn point-x:ref:i32 ((p (ref Point)))
  (return (.& p x)))              ; OK: pointee is caller-owned (ref parameter)
```

The `Drop` protocol is an ordinary Stage 9 protocol; conforming makes a type
`with`-manageable with zero dispatch overhead:

```lisp
(defprotocol Drop
  (drop:void (self:ptr:Self)))
(defn drop:void (self:ptr:Res) ...)   ; concrete method
(extend Res Drop)                      ; checked, code-free conformance
(with (r:ptr:Res (make-res)) ...)      ; (drop r) fires at scope exit
```

## Binary Operators

| Name | Description | C Equivalent |
|------|-------------|--------------|
| `+` | Addition | `a + b` |
| `-` | Subtraction | `a - b` |
| `*` | Multiplication | `a * b` |
| `/` | Division (signed: `sdiv`, unsigned: `udiv`) | `a / b` |
| `%` | Remainder (signed: `srem`, unsigned: `urem`) | `a % b` |
| `bit-and` | Bitwise AND | `a & b` |
| `bit-or` | Bitwise OR | `a \| b` |
| `bit-xor` | Bitwise XOR | `a ^ b` |
| `bit-shl` | Shift left | `a << b` |
| `bit-shr` | Shift right (signed: arithmetic `ashr`, unsigned: logical `lshr`) | `a >> b` |
| `=` | Equal | `a == b` |
| `!=` | Not equal | `a != b` |
| `<` | Less than (signed: `slt`, unsigned: `ult`) | `a < b` |
| `<=` | Less or equal (signed: `sle`, unsigned: `ule`) | `a <= b` |
| `>` | Greater than (signed: `sgt`, unsigned: `ugt`) | `a > b` |
| `>=` | Greater or equal (signed: `sge`, unsigned: `uge`) | `a >= b` |

Operators are **ordinary generic functions**. Each built-in operator is a generic; when the operands are built-in numerics (or pointers, for comparisons) the resolver selects the built-in method, which emits its inline instruction (`add nsw`, `icmp slt`, …) directly — a **front-end peephole**, not an LLVM pass — so there is no `call` and the IR is byte-identical to a non-polymorphic compiler even at `-O0`.

**Mixed operands now resolve**: an untyped integer literal adapts to the other operand's type (`(+ x 1)` with `x:i64`), and a narrower integer/float widens to the wider (`(+ i32 i64)`, `(+ f32 f64)`). Genuinely mismatched operands (e.g. two different typed pointers in arithmetic, or mixed signedness) are still rejected.

**User operator overloading.** Because operators are generics, a type becomes "addable"/"comparable" by defining a method. The variadic `+ - * /` macros fold to the binary primitives `_+ _- _* _/`, so arithmetic is overloaded on those names; the comparison operators are overloaded directly:

```lisp
(defstruct V2 x:i32 y:i32)
(defn _+:ptr:V2 (a:ptr:V2 b:ptr:V2) …)   ; (+ u v) now dispatches here
(defn =:i1     (a:ptr:V2 b:ptr:V2) …)    ; (= u v) dispatches here
```

A user operator method is emitted under a mangled symbol (`@add.pV2.pV2`, `@eq.pV2.pV2` — the symbols `+`/`=` are mapped to IR-safe mnemonics). A call with operand types that match no user method falls back to the built-in inline peephole.

The **standard numeric protocols** live in `lib/numeric.nuc`: `Eq` (`= !=`), `Ord` (`< <= > >=`, a superset of `Eq` via `(extend Ord Eq)`), and `Num` (`_+ _- _* _/`). Built-in numeric types conform automatically (their intrinsic operators satisfy the requirements); a user type conforms by defining the methods and asserting `(extend ptr:MyType Ord)`. See [Bounded generic `defn`](generics.md#bounded-generic-defn).

## Callable values (non-function call position)

A **non-function value in head position**, `(s arg…)`, is no longer an error — it
routes **`invoke → get → _get`** by the callee's *type*:

| precedence | condition on the callee type | desugars to | meaning |
|---|---|---|---|
| 1 | has an `invoke` method | `(invoke s arg…)` | indexing / general call (arg is a **value**) |
| 2 | has a custom `get` method | `(get s arg)` | value-keyed or symbol member access |
| 3 | otherwise (plain struct) | `(get s 'field)` → `_get` | raw field access (single literal symbol) |

Because **`invoke` takes precedence**, a type that defines `invoke` indexes/applies
its argument as a *value* — so `(v idx)` evaluates the local `idx` and indexes,
rather than reading a field named `idx`. The consequence is that such a type can no
longer use the callable form for field access: read its fields with `_get`/`.field`
(`(_get v len)`), not `(v len)`. A **plain struct** (no `invoke`, no custom `get`)
still treats a single literal-symbol argument as a field selector via the raw `_get`
intrinsic, so `(p x)` ≡ `(_get p x)` is unchanged and zero-overhead.

**`get` — member access (the `Struct` default).** Every struct conforms to the
built-in `Struct` blanket protocol, whose `get` is supplied by an **intrinsic**: a
literal selector const-folds to a static `getelementptr`+`load`, **identical to the
`_get` primitive and zero-overhead**. So `(c rad)` ≡ `(get c 'rad)` ≡ `(_get c rad)`.
Head position `(c rad)` is the idiomatic spelling; `_get` is the escape hatch (it
reads the field directly, skipping any user `get` override — so a user `get` method
uses `_get` for its own fields to avoid recursing into itself).

```lisp
(defstruct Point x:i32 y:i32)
(p x)          ; ≡ (. p x) — a plain field load
```

The intrinsic is **overridable**: a concrete user `get` method for a type sits at
tier 0 and out-ranks the blanket intrinsic, so it owns *all* member access on that
type. A user `get` takes the selector as an interned symbol (`ptr`):

```lisp
(defn get:i32 (self:ptr:Temp sel:ptr)
  (if (= sel 'f) (return …) (return (. self c))))   ; (t f) and (t c) both route here
```

**Value-keyed `get` (computed selectors).** Dispatch splits on the selector kind.
A literal-symbol selector takes the member-access path above (the selector value
is always an interned symbol `ptr`). A **computed/value selector** — an `i32`, a
`CStr`, or any non-symbol value — instead resolves the `get` generic on the
selector's *actual* type, so a parametric `get` override can index by a real key:

```lisp
(defstruct (Bag K V) key:K val:V has:i32)
(defn (get (Maybe V)) ((self (ref (Bag K V))) key:K) …)   ; value-keyed lookup
(get bag "hello")    ; CStr selector → the (Bag K V) get method, returns (Maybe V)
(get bag 42)         ; i32  selector → the same method
(get bag 'val)       ; symbol selector → field access, returns the raw V field
```

The value-keyed override is found even when it is a parametric (generic) method:
the resolver binds the method's type variables and checks its `&where` constraints
before selecting it. If no `get` method matches the selector's type, the call
falls back to the struct intrinsic (a `ptr`-typed computed selector takes the
homogeneous computed-field branch; any other type is an error). This is how a
`Bag`-style type answers `(m key)` by value while plain structs keep zero-overhead
symbol field access. (Note: this value-keyed `get` path applies only to types that
do **not** define `invoke` — `invoke` outranks `get`. A `HashMap`, whose lookup is
exposed through `get`, has no `invoke`; a `Vector`, whose indexing is `invoke`, is
indexed by call and must read its fields with `_get`.)

**`invoke` — indexing / general call (highest precedence).** A type "becomes
callable" by defining `invoke` methods; there is **no** built-in default. Once a
type has an `invoke` method, *every* `(s arg…)` on that type routes to `invoke`,
with the argument(s) taken as values — so the callee can no longer be used for
field access by call. Dispatch is ordinary multimethod resolution on the whole
argument tuple:

```lisp
(defstruct Vec data:ptr:i32 len:i32)
(defn invoke:i32 (self:ptr:Vec i:i32) (return (aref (_get self data) i)))
(v 3)          ; ⇒ (invoke v 3) → element access (literal index)
(let (idx:i32 1) (v idx))   ; ⇒ (invoke v idx) → indexes; NOT a field named idx
(_get v len)   ; field access — `(v len)` would mis-route to invoke
```

For parametric function-object conformance use `(UnaryFn Arg Ret)` and
`(FoldFn Acc Elem)` from `lib/iterator.nuc`
(see [Generics](generics.md#associated-type-bounds-where-protocol-arg--var)).
See `examples/callable.nuc` for a full demonstration.

**Computed selector (`get` only).** An *explicit* `(get callee expr)` whose
selector is a compound expression (not a bare/quoted symbol) reads a field chosen
at runtime: the selector is compared by pointer identity against the struct's
interned field symbols. Restricted to **homogeneous** structs (all fields one
type) so the result type is well-defined; a heterogeneous struct is a clear error.

**Arbitrary-expression and function-pointer heads.** The head need not be a
symbol: `((mk-vec) 3)` and `(@p 3)` emit the head once and route the same way. A
head whose value is a **function pointer** folds to an indirect call, so
`(f a b)` works for a local/global fn-pointer variable `f` and the explicit
`funcall`/`funcall-ptr-*` forms are now compiler-internal (still accepted).

Everything resolves at compile time to a static GEP+load, a direct `call` to a
resolved method, or an indirect `call` through a fn-pointer — no dispatch object,
no vtable. `get`/`invoke` overloads export through the existing
`defmethod`/`defprotocol`/`extend` machinery; there is no new `.nuch` form.
