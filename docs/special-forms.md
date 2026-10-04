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

An explicit `(return expr)` coerces `expr` against the declared return type
the same way (see [Implicit Type Coercion](types.md#implicit-type-coercion));
a value that cannot be coerced (e.g. returning a `f64` from an `:i64`
function) is a compile-time error naming both types, not a raw LLVM-level
failure.

| Name | Description | C Equivalent |
|------|-------------|--------------|
| `do` | Sequence multiple expressions; yields the last | `{ ... }` block |
| `macrolet` | Bind macros over a body: `(macrolet ((name (params) body...) ...) body-form...)`. The bindings exist for the body and nowhere else, so a deliberately capturing macro need not become a global `defmacro`. In expression position the body emits as a `do` (same value, no new variable scope); at top level each body form is dispatched as a top-level form of its own, so the bindings scope the definitions they wrap. Bindings are **sequential** like Nucleus `let` — a later binding's body sees an earlier one — and a binding is visible inside its own body, like `defmacro`. A binding shadows a global macro/function/local of the same spelling in head position, and an inner `macrolet` shadows an outer one; it may **not** shadow a special form (the macro table is consulted first, so this is refused rather than allowed). `:rest` works as in `defmacro`. See [macrolet](macros.md#macrolet--lexically-scoped-macros). | Common Lisp `macrolet` |
| `let` | Bind local variables; yields the body's last expression | local variable declaration |
| `with` | Like `let`, but **owns** any binding whose init is a libc allocator (`malloc`/`calloc`/`realloc`/`strdup`, possibly through `as`) or whose declared type conforms to the `Drop` protocol. Owned bindings are released at scope exit (libc → `free`; Drop → statically dispatched `(drop b)`, null-guarded) in reverse binding order, on fall-through and on early `return`. The compiler verifies at compile time that an owned resource does not **escape** the scope — see [Pointer lifecycle](#pointer-lifecycle-escape-analysis). Use `(move b)` to transfer ownership out. | `let` + scoped `free` / RAII |
| `cond` | Multi-way conditional; yields the matched branch's value (strict-typed across branches). The test is `bool`, or a nullable value eliminated to one — see [Condition position](#condition-position-a-nullable-value-is-a-condition). | `if` / `else if` / `else` chain |
| `match` | Eliminate a `defunion` value (or a `defenum` integer) by arm, with exhaustiveness checking. See [Unions and tagged sums](structs-unions.md#unions-and-tagged-sums). | `switch` on the tag |
| `make` | Construct a `defunion` value by arm: `(make Type arm args...)` — the explicit-instance spelling required for template instances, e.g. `(make (Result i64 i32) ok v)`. | designated initializer |
| `while` | Loop; yields `void`. Same condition rule as `cond` — see [Condition position](#condition-position-a-nullable-value-is-a-condition). | `while` |
| `set!` | Assign to a **place**: `(set! x v)` a name, `(set! (p 'field) v)` a member, `(set! (deref p) v)` a pointee, `(set! (aref a i) v)` an element. The name place yields the assigned value; every other place yields `void` (it is a statement, as in C). The three punctuation writers it replaced — `.set!`, `ptr-set!`, `aset!` — were retired in Stage 16 ([dot-forms.md](../design/stage16-ergonomics/dot-forms.md) §3). A member place whose key is **computed** dispatches to a user `set` method — see the `set` row. | `x = val` / `s.f = val` / `*p = val` / `a[i] = val` |
| `inc!` | Increment a variable by 1 (or by an optional delta). Yields the new value. | `x++` / `x += n` |
| `dec!` | Decrement a variable by 1 (or by an optional delta). Yields the new value. | `x--` / `x -= n` |
| `label` | Declare a function-scoped label. Forward and backward gotos both resolve. Duplicate declarations of the same name are allowed — the last one in textual order is the canonical target. | label: |
| `goto` | Unconditional jump to a label declared anywhere in the current function. | `goto label` |
| `label-addr` | Yields a `ptr` to a label (for computed gotos). | `&&label` (GCC) |
| `goto-ptr` | Indirect branch to a label address. The IR lists every label declared in the current function as a possible destination. | `goto *p` (GCC) |
| `return` | Return from function | `return` |
| `not` | Logical negation. The operand is a condition — see [Condition position](#condition-position-a-nullable-value-is-a-condition) — so `(not p)` on a `ptr`/`(ptr T)`/`CStr`/`?T` is a null test. | `!x` |
| `and` | **Variadic prelude macro** (same split as `_+`/`+`) that right-folds to the binary `_and` primitive: `(and)`→`true`, `(and x)`→`x`, `(and a b c…)`→`(_and a (and b c…))`. For ≥2 args each operand is a [condition](#condition-position-a-nullable-value-is-a-condition) evaluated left-to-right, stopping at the first false; cumulative narrowing is preserved across the chain (a later `(m 'field)` typechecks after an earlier `(!= m null)`). The 1-arg form returns `x` **unchecked** — no condition check, matching CL/`+` variadic semantics (the check fires only inside the ≥2-arg binary lowering). Fold table: [Variadic logical operators](macros.md#variadic-logical-operators). | `&&` (N-ary) |
| `or` | **Variadic prelude macro** that right-folds to the binary `_or` primitive: `(or)`→`false`, `(or x)`→`x`, `(or a b c…)`→`(_or a (or b c…))`. For ≥2 args each operand is a [condition](#condition-position-a-nullable-value-is-a-condition) evaluated left-to-right, stopping at the first true; cumulative narrowing is preserved. The 1-arg form returns `x` **unchecked**. Fold table: [Variadic logical operators](macros.md#variadic-logical-operators). | `\|\|` (N-ary) |
| `_and` | Binary short-circuit logical AND primitive — the underscore-prefixed form behind the `and` macro (same split as `_+` behind `+`). Both operands are [conditions](#condition-position-a-nullable-value-is-a-condition); the RHS is evaluated, and narrows under the LHS, only when the LHS is true. Usable directly for hand-written binary short-circuit. | `&&` |
| `_or` | Binary short-circuit logical OR primitive — the underscore-prefixed form behind the `or` macro. Both operands are [conditions](#condition-position-a-nullable-value-is-a-condition); the RHS is evaluated, and narrows under the LHS, only when the LHS is false. Usable directly for hand-written binary short-circuit. | `\|\|` |
| `cast` | **Retired in Stage 14** — bare `cast` is now a targeted hard error: `'cast' was split in Stage 14: use 'as' (safe) or 'unsafe/cast' (unchecked)`. Use `as` (below) for statically-safe conversions, `unsafe/cast` (below) for anything lossy or contract-manufacturing. | — |
| `as` | **Statically-safe** conversion — `(as TYPE expr)`, same shape as `unsafe/cast`. Accepts the *non-lossy* part of what the implicit-coercion machinery accepts in an assignment position (identity, int widening, same-width sign reinterpret, `f32`→`f64`, user `defcast` rules, `CStr`↔pointer, the elem-less-`ptr` `void*` hatch) **plus** pure pointer-contract weakening (`&T`→`(ptr T)`/`?&T`; a typed pointer → elem-less bare `ptr`) **plus** a narrowing whose operand is a *literal* the target can hold exactly — an integer that fits (`(as i8 5)`, `(as ui8 200)`, and the same through a `defconst` name) or a float that round-trips (`(as f32 1.5)`, `(as f32 -0.25)`) — which is lossless and so lowers to exactly what the implicit spelling `(let (a:i8 5) …)` / `(let (a:f32 1.5) …)` emits. Refuses everything lossy or contract-manufacturing — narrowing/truncation of a **value** (integer *and* `f64`→`f32`), a literal that does *not* fit (`(as i8 300)`, `(as ui8 -1)`) or does *not* round-trip (`(as f32 3.14)`), `float`→`int`, `ptr`↔`int`, `fn`↔`ptr`, element-retyping `ptr`↔`ptr` (each routed to `unsafe/cast`) — note that an implicit coercion at a typed slot narrows a *value* silently (integers and floats alike) and rounds a float *literal* silently, so `as` stays deliberately stricter than assignment there — and, unlike `unsafe/cast`, **honors the nullability flow check**: an unchecked or nullable pointer into a non-null `&T` slot is rejected (routed to `as-ref` for a runtime-checked launder, or `unsafe/cast` for an unchecked assertion). Use `as` for conversions you can prove correct; reach for `unsafe/cast` only when the compiler refuses. **`as` also names a type for inference**: its target type is supplied as the expected type of its operand, exactly as a `let`/`with` binding annotation, a `set!` place or a `return` does — so a generic whose type variable appears only in its return type resolves against it (`(as (ref (Vector i32)) (vector-new-in a))`). | `static_cast`-ish |
| `unsafe/cast` | **Unchecked** type reinterpretation — `(unsafe/cast TYPE expr)`. Today's (pre-Stage-14) `cast`, verbatim: same-kind reinterpret, `ptr`↔`ptr` (any/all element retyping, including unchecked→`&T` laundering with **no** nullability check), `CStr`↔`ptr`, `fn`↔`ptr`, int narrowing/widening, same-width sign reinterpret, `float`↔`float` (`fpext`/`fptrunc`), `int`↔`float` (`sitofp`/`uitofp`/`fptosi`/`fptoui`). Its only "check" is that the kind pair appears in the conversion ladder — no range check, no null check — with one refusal: a capturing closure (`vfn`/`mfn`/`cfn`) never converts to a function-pointer type, since its code takes the closure's environment as a hidden first argument and no caller would supply it (`as` refuses the same pair with the same message). Pass a non-capturing `fn` and route the state through the callback's user-data argument instead. A strict superset of `as`'s accepted set, so it never blocks a migration; reach for it only when `as` refuses. | `(type)x` |
| `ref` | Take address of a variable. `&x` reads as `(ref x)` when the `&` starts a token — a `&` inside one is the [`&T` type sigil](types.md#pointer-kinds-t-t-and-ptr-t) — so `ref` is one head in both worlds: `(ref T)` in a type slot is the non-null pointer type, `(ref x)` in a value slot is the address-of, and the type of `(ref x)` is `(ref (type-of x))`. The older spelling `addr-of` is **retired** (Stage 21 PK-5b; see its row below). The address of **frame-local storage** (a `let`/`with` value binding or a by-value parameter) is escape-tracked, but only at the two actual escape sinks: `return` and a store into longer-lived memory. **Passing it as a call argument is allowed** — downward flow into a callee is a borrow, so the ordinary C out-parameter idiom works with no cast or workaround: `(defn set-both (out-a:ptr:i32):void (set! (deref out-a) 41)) (let (a:i32 0) (set-both &a) ...)` compiles and, after the call, `a` holds the written value. See [Pointer lifecycle](#pointer-lifecycle-escape-analysis) for the full escape-sink list; the address of a global or of a reference/pointer binding is never tainted. **Implicit at an argument position (Stage 17).** A struct **value** read out of a binding, passed where the parameter wants a pointer to exactly that struct, takes the binding's address automatically — `(show v)` with `v:P` and `(show p:&P)` means `(show &v)` and emits the identical call. This is **lvalue-only**: only a binding qualifies, so a call result (`(show (mk))`) is still the ordinary argument-type error, because `(ref T)` does not distinguish a read borrow from a write one and a mutating callee would otherwise write into a temporary the caller cannot see. An exact overload always wins over the adjustment. See [borrow-conventions.md](../design/stage17-native-strings/borrow-conventions.md). **Two arities.** `(ref x)` / `&x` is a binding's address, above; `(ref s 'field)` is a field's — the spelling that replaced `.&` in Stage 16 ([dot-forms.md](../design/stage16-ergonomics/dot-forms.md) §3). They cannot collide, since a binding address takes a bare symbol and a field address a receiver plus a **quoted** selector; a bare symbol in that second slot is refused, not read as a variable. An `(array T N)` field's address **decays** to `ptr:T` — a pointer-to-array is only usable where an array type is refused. A bit-field has no address (C's own rule), and the receiver needs storage, so a temporary struct value is refused. | `&x` / `&s.field` |
| `deref` | Dereference a pointer (reader sugar: `@p` → `(deref p)`) | `*p` |
| `ptr-set!` | **Retired in Stage 16** — a targeted hard error: `'ptr-set!' was retired in Stage 16: set! takes a place`. Write `(set! (deref p) v)`. | — |
| `ptr+` | **Retired in Stage 14** — bare `ptr+` is now a targeted hard error: `'ptr+' was split in Stage 14: use 'unsafe/ptr+'`. | — |
| `unsafe/ptr+` | Pointer arithmetic on a **typed** pointer; manufactures a new pointer at an unchecked offset (no bounds check). | `p + n` |
| `.` | **Retired in Stage 16** — a targeted hard error: `'.' was retired in Stage 16: use 'get'`. Write `(get s 'field)`, or head position `(s 'field)`. The spelling stays reserved so the message cannot be shadowed. | — |
| `.&` | **Retired in Stage 16** — a targeted hard error: `'.&' was retired in Stage 16: use the 2-argument 'ref'`. Write `(ref s 'field)`. | — |
| `addr-of` | **Retired in Stage 21** (PK-5b) — a targeted hard error in every position, the type slot included: `'addr-of' was retired: write &x, or (ref x) / (ref p 'field)`. The spelling stays reserved so the message cannot be shadowed. | — |
| `_get` | Low-level struct field read (compiler-internal primitive; bypasses any user `get` override). Prefer head position `(s 'field)` in ordinary code; use `_get` only where head position would dispatch wrongly (a user `get` method reading its own field, or a struct held in a special-form-named variable). The field name is **quoted** at every member form (`_get`, `ref`, `get`, head position, a member place); a bare symbol there is an ordinary variable reference, i.e. a [computed selector](#computed-selector-get-only). | `s.field` |
| `.set!` | **Retired in Stage 16** — a targeted hard error: `'.set!' was retired in Stage 16: set! takes a place`. Write `(set! (s 'field) v)`. | — |
| `get` | Member access / field read: `(get s 'field)` ≡ `(s 'field)`; for a plain struct this lowers to the `_get` primitive (zero-overhead), overridable per type. See [Callable values](#callable-values-non-function-call-position) | `s.field` |
| `set` | **Generic**, the write side of `get`/`invoke`: a member place with a **computed** key, `(set! (m k) v)` or `(set! (get m k) v)`, is the call `(set m k v)` when the receiver's type has a `set` method. A **literal** selector is always the field, so a type with a `set` method can still write its own fields — the write side of the `_get` recursion trap. `Vector` and `HashMap` both define one. | `m[k] = v` |
| `invoke` | General call on a value: `(invoke s 3)` ≡ `(s 3)`; user-defined (`Seq`/`Call`) | `s(3)` / `s[3]` |
| `sizeof` | Size of a type | `sizeof(T)` |
| `source-file` | `(source-file)` — the path of the file being compiled, as a `StrView` literal. Inside a macro expansion it names the **calling** file, which is what a diagnostic or a test registration wants. | `__FILE__` |
| `source-line` | `(source-line)` — the line the form is written on, as an integer literal. Inside a macro expansion it is the **call site**'s line, not a line of the macro. | `__LINE__` |
| `alloca` | Stack-allocate memory | `alloca()` / VLA |
| `char` | Character literal | `'c'` |
| `aref` | Array element access | `arr[i]` |
| `aset!` | **Retired in Stage 16** — a targeted hard error: `'aset!' was retired in Stage 16: set! takes a place`. Write `(set! (aref a i) v)`. | — |
| `(StructName init...)` | Compound struct literal. Each `init` is either `(field val)` for a designated initializer or a value for a positional one (positional inits fill the next field that has not been designated). A two-element `(name x)` is designated only when `name` is a field of the struct, so `(S &a)`, `(S (f x))` and `(S (Inner 1))` are positional values; a field name wins over a function of the same name (bind the call first to pass it positionally), and a `name` that names nothing is reported as a missing field. A `(some v)`/`none`/`(ok v)`/`(err e)` init constructs against the field's type. Unspecified fields are zero-initialized. Yields `ptr:StructName`, alloca-backed (stack lifetime is the enclosing function). Defining a function with the same name as a struct is a compile-time error (the function would shadow the constructor). | `(struct S){.f = v, ...}` |
| `array` | `(array ElemType init...)` — array compound literal. Each `init` is either `(index val)` (designated) or a bare value (positional). Length is implicit: `max(positional-count, max-designated-index + 1)`. Unspecified slots are zero-initialized (including struct and `CStr` element types). Yields `ptr:ElemType`, alloca-backed. When `ElemType` is a struct, an element may be written as a bare `(ElemType …)` compound literal — it is loaded into the slot, so the older `(deref (ElemType …))` spelling is no longer required (both are accepted and emit the same IR). A binding annotated with the bare, elem-less `:ptr` takes `ptr:ElemType` from the literal, so `(aref a i)` works without a cast. **Not to be confused with the `(array T N)` *type*** ([Fixed-size arrays](types.md#fixed-size-arrays--array-t-n)): the two are told apart by position, and `(array i32 4)` means a one-element array holding `4` here but a four-element array type in a type annotation. | `(T[]){1, 2, [3] = 99}` |
| `quote` | Yields its argument as a `Node*` (reader sugar: `'x` → `(quote x)`). Quoted symbols are interned — see [Symbols](types.md#symbols). | — |
| `quasiquote` | Like `quote` but `~expr` splices a runtime value and `~@list` splices a list (reader: `` `x ``, `~x`, `~@x`). Nests: a backtick raises the level and an unquote lowers it, so only a level-1 unquote is code — see [Nesting levels](macros.md#nesting-levels) | — |
| `ast-first` `ast-rest` `ast-at` `ast-len` | Read a list `Node`: the first element, the elements after the first, element *i*, the element count. **This is the spelling a macro body uses** — each is lowered by whichever compiler is running, so a body reaches that compiler's own `Node` layout across a relayout (design/stage21-cleanup/ast-as-collection.md §8.2). Ordinary code calls `node-first`/`node-rest`/`node-at`/`node-len` from `(import-use nucleus.node)` instead, or treats the list as a [collection](collections.md). | — |
| `compile-time` | Execute body forms at compile time via LLVM JIT; output goes to stderr. A `defstruct` in the body defines a **program** type, not a compile-time-private one: its definition is emitted into the program module and the type is usable by ordinary code — in a *body*, in a *signature*, by value or by reference, anywhere in the unit including **above** the block, and at a later REPL entry. `defstruct` is the only definer the body registers for the program this way: a `defvar`, `defconst`, `defenum` or `defn` in a `compile-time` body belongs to the compile-time module, and naming one from ordinary code is an error. | — |
| `funcall` | Call a typed function pointer: `(funcall fn args...)`. The function pointer must have a `TY-FN` type with known return type and parameter types. | `fn(args...)` |
| `funcall-void` | Call a function pointer with no arguments and no return value | `fn()` |
| `funcall-ptr-1` `funcall-ptr-i32` `funcall-ptr-i64` `funcall-ptr-ptr` | **Retired in Stage 14** — each bare spelling is now a targeted hard error: `'funcall-ptr-1' was split in Stage 14: use 'unsafe/funcall-ptr-1'` (and the `-i32`/`-i64`/`-ptr` siblings analogously). | — |
| `unsafe/funcall-ptr-1` | Call a `ptr` function pointer with one `ptr` argument, returning `ptr` — a call signature asserted with no arity/type check against the actual callee | `fn(arg)` |
| `unsafe/funcall-ptr-i32` | Call a `ptr` function pointer with no arguments, returning `i32` | `((int(*)())fn)()` |
| `unsafe/funcall-ptr-i64` | Call a `ptr` function pointer with no arguments, returning `i64` | `((long(*)())fn)()` |
| `unsafe/funcall-ptr-ptr` | Call a `ptr` function pointer with no arguments, returning `ptr` | `((void*(*)())fn)()` |
| `unsafe-import-private` | **Retired in Stage 14** — bare `unsafe-import-private` is now a targeted hard error: `'unsafe-import-private' was split in Stage 14: use 'unsafe/import-private'`. | — |
| `unsafe/import-private` | Prefix-qualified import that also reaches a library's private (`defn-`/`defvar-`/etc.) symbols: `(unsafe/import-private lib prefix sym...)`. See [Top-level forms](toplevel.md#top-level-forms). | — |
| `gensym` | Return a fresh unique symbol `Node*` (e.g. `__gs_0`); for use in macro bodies to avoid variable capture | — |
| `macro-error` | `(macro-error node message)` — report `message` at `node`'s line and abort the expansion. Only inside a `defmacro`/`macrolet`/`compile-time` body; the message is a literal, a `StrView` or a `String` (so a body that imports `fmt` can build one with `str`). See [Macros](macros.md#macro-error--a-macro-rejecting-its-own-call-site). | — |
| `struct-fields` | `(struct-fields t)` — the fields of struct type `t` as `((name type) …)`, in declaration order. Macro bodies only. See [Macros](macros.md#struct-fields-and-type-name--a-structs-shape-at-expansion-time). | — |
| `type-name` | `(type-name t)` — struct `t`'s qualified name as a symbol (`geom/Point`, `user/Point`). Macro bodies only. | — |
| `some` | `(some r)` — wrap a non-null `(ref T)` as `?T` / `(Maybe (ref T))`. Pure relabel, no IR. | — |
| `as-ref` | `(as-ref p)` — launder an unchecked pointer (`(ptr T)`) into `?&T` (null stays none). Pure relabel, no IR; narrow before use. | — |
| `unwrap` | `(unwrap m)` — the `(ref T)` inside a `?T`, or trap (`llvm.trap`) if none. The one runtime branch nullability costs, paid only where written. | `assert(p); p` |
| `unwrap-or` | `(unwrap-or m default)` — the `(ref T)` inside, or `default` (evaluated only on the none path; must itself be `(ref ...)`-compatible). | `p ? p : d` |
| `try` | `(try r)` — propagate a `!T`: yields the `ok` payload, or re-returns the error via `err!` from the enclosing `!T` function. Lowers to that `match`. A special form, not a macro, because the `ok` arm's binder count depends on the operand's type — a `!void` operand's `ok` arm is payload-less and `try` then yields nothing. See [Error handling](errors.md#void--a-result-with-no-ok-payload). | `?` operator |
| `if-some` | `(if-some (x m) then else)` — if `m` is non-null, bind `x:(ref T)` in `then`; else evaluate `else`. Desugars to `cond`, so its value/typing rules match `if`. | `if ((x = m)) … else …` |
| `when-some` | `(when-some (x m) body…)` — one-armed `if-some`. | `if ((x = m)) { … }` |
| `move` | `(move b)` — transfer ownership of a `with`-owned binding out: disarms its scope-exit cleanup, yields the value with its escape taint cleared, and marks `b` consumed (later uses are "use after move"; reassignment revives it). | — |
| `defer` | `(defer expr)` — register `expr` as an ad-hoc cleanup on the enclosing binding scope (nearest `let`/`with`/function body), re-emitted at every exit path in reverse registration order. Lexical, not dynamic: it runs at scope exit whether or not control reached the `defer` site. | `goto cleanup` discipline |
| `fn` | `(fn (params):ret body…)` — an **anonymous function**. The body may reference its own parameters and top-level names (`defconst` / global `defvar` / another `defn`), but **not** any enclosing runtime local (a `let`/`with` binding or a by-value parameter); doing so is a compile error directing the author to `vfn`/`mfn`/`cfn`. The form is lambda-lifted to a fresh top-level function and its value is that function's pointer, so a non-capturing `fn` is a true function pointer with no environment and no runtime overhead — usable inline, storable in a variable, passable as an argument, and C-callable (e.g. a `qsort` comparator). The trailing `:ret` is the return type, matching the `(x:i32):i32` convention and meaning exactly what it means on a `defn`, pointer kind included (`:ptr:T` and `:?&T` may return `null`; `:&T` may not); a parenthesised return type (`(ref T)`) uses the space-separated list form. A local binding named `fn` shadows this keyword. (Stage 13 — see [lambda.md](../design/stage13/lambda.md).) | function pointer / non-capturing lambda |
| `vfn` | `(vfn (params):ret body…)` — a **clone-capture closure**. Like `fn` but it *captures* the enclosing runtime locals its body references, by **clone** (the source survives untouched). Each capture must conform to `Clone` (see [generics.md](generics.md)): a POD / `Drop`-free capture is a bitwise value copy (no allocation; the closure owns nothing and is not `Drop`); an owning (`Drop`) capture is deep-cloned via its hand-written `clone`, and the closure then owns the copy and conforms to `Drop` with a synthesized field-wise cleanup. A `Drop` capture with no `Clone` is rejected, directing the author to `mfn`. The closure lowers to an anonymous by-value struct (one field per capture) plus a synthesized `invoke` method of the lambda's arity, so it is **callable with ordinary call syntax** — `(c arg…)` routes to `invoke` via the callable-values rule, no new call form needed. A non-capturing `vfn` folds to a bare `fn` pointer (zero overhead). The trailing `:ret` and parenthesised-return-type rule match `fn`; a local named `vfn` shadows this keyword. (Stage 13 — see [lambda.md](../design/stage13/lambda.md).) | clone-capture closure (by-value, owning iff a capture is `Drop`) |
| `mfn` | `(mfn (params):ret body…)` — a **move-capture closure**. Like `fn` but it *captures* the enclosing runtime locals its body references, by **move** (the source is consumed). An owned capture (a `with`-owned binding) is routed through the `move` sink: its scope-exit cleanup is disarmed, the value is yielded with escape taint cleared, and the binding is marked consumed (later uses are "use after move"); the closure owns the moved resource and conforms to `Drop` with a synthesized field-wise cleanup (same synthesis as `vfn`). A POD capture (a `let` binding or by-value parameter) is a bitwise copy — move == copy when there is no cleanup to disarm. Because the move transfers ownership and clears taint, an `mfn` created inside a `with` may be **returned/moved out** of that scope: the disarmed source no longer frees the resource, so the return is sound (this is the form that exports an owned value out of a `with` scope). No allocator; travels by value. The closure lowers to an anonymous by-value struct (one field per capture) plus a synthesized `invoke` method, callable with ordinary call syntax; a non-capturing `mfn` folds to a bare `fn` pointer. The trailing `:ret` and parenthesised-return-type rule match `fn`; a local named `mfn` shadows this keyword. (Stage 13 — see [lambda.md](../design/stage13/lambda.md).) | move-capture closure (by-value, owning; consumes `with`-owned sources) |
| `cfn` | `(cfn alloc (params):ret body…)` — a **reference-capture closure**. Like `fn` but it *captures* the enclosing runtime locals its body references, by **reference** (the referents are borrowed, not owned). The bare first operand `alloc` is a `(ref AllocHandle)` (see [allocators.md](allocators.md)) — an argument, not part of the params/return group; when it is itself a call (`(default-allocator)`) the parentheses are call parentheses. The environment is an anonymous struct of **pointers** into the captured storage (one `(ptr T)` field per capture), preceded by a stored `AllocHandle`; the env's own storage is allocated through `alloc` (a heap block), and the closure conforms to `Drop` with a synthesized `drop` that frees the env block via the stored handle (mirroring how a collection frees its buffer). The closure lowers to that env struct plus a synthesized `invoke` method, callable with ordinary call syntax; in the body a value use of a capture reads through the stored pointer (`(deref (_get self 'cap)`) and `&cap` is the stored pointer itself (`(_get self 'cap)`). The closure value **inherits the region of each captured reference** (see [Pointer lifecycle](#pointer-lifecycle-escape-analysis)): returning (or otherwise escaping) it past a captured `with`-owned or frame-local referent's scope is rejected at the existing escape sinks, while a `cfn` capturing only caller-owned `(ref …)` parameters or globals may be returned freely. To export a *value* computed from a captured reference, copy or `deref` it in the body so the result is a value, not a tainted reference. A non-capturing `cfn` folds to a bare `fn` pointer (the `alloc` operand is dropped). The trailing `:ret` and parenthesised-return-type rule match `fn`; a local named `cfn` shadows this keyword. (Stage 13 — see [lambda.md](../design/stage13/lambda.md).) | reference-capture closure (struct of pointers + stored `AllocHandle`, escape-checked) |

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
  rewrites to `(set! (self 'c) v)` (field store); `(inc! c)` / `(dec! c)` expand to
  the read-modify-write equivalent `(set! (self 'c) (op (_get self 'c) 1))`. The mutation
  lands in the env field and **persists across successive calls** to the same
  closure instance (since `invoke` receives `self` as a `(ref Env)` — a mutable
  reference). The outer binding is unaffected (it was copied/moved into the env at
  closure creation).

- **`cfn` (by-reference capture):** the env field holds a *pointer* into the outer
  binding's storage. `(set! c v)` rewrites to `(set! (deref (_get self 'c)) v)` — a store
  through the captured pointer. `(inc! c)` / `(dec! c)` become `(set! (deref (_get self 'c))
  (op (deref (_get self 'c)) 1))`. The **outer binding sees the mutation** after each
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
consumed source binding (via symbol or `&`) is a compile error ("use after
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

## Condition position: a nullable value is a condition

There are exactly **six** condition sites in the language — the `cond` test, the
`while` condition, the `not` operand, and each operand of `_and` / `_or`.
Everything else that reads like a conditional (`if`, `when`, `unless`, `case`,
`if-some`, `when-some`, and the variadic `and` / `or`) is a macro over those, so
whatever holds here holds everywhere.

At those six sites a **nullable** value is accepted directly and eliminated to
`bool`:

| Condition type | True when | Lowers to |
|---|---|---|
| `bool` | it is `true` | unchanged |
| `(ptr T)` / bare `ptr` | non-null | `icmp ne ptr … null` |
| `CStr` | non-null | `icmp ne ptr … null` |
| `?T` / `(Maybe (ref T))` | present | `icmp ne ptr … null` |
| `(Maybe T)`, `T` a non-pointer | the `some` arm | tag compare |

```lisp
(when m (m 'kind))         ; same as (when (!= m null) (m 'kind))
(while cur (walk cur))
(when (not p) (return -1))
(and m (> (m 'x) 0))       ; the rhs still narrows under the lhs
```

Narrowing follows the sugar: a bare `m` in a condition proves `m` non-null
exactly where `(!= m null)` would, so a `?T` binding reads as `(ref T)` inside
the taken branch, inside an `_and`'s right operand, and after a terminating
`(when (not m) …)` guard.

**Everything else stays a type error**, and deliberately so:

- **Numbers and other scalars.** `(when n:i32 …)` is `cond: condition must be
  bool, not i32 -- compare explicitly`. Nucleus always knows the type, so a
  numeric condition is a constant no reader intends; refusing it also keeps the
  meaning of `(when n …)` free for a later decision.
- **A non-null pointer.** `&T` is non-null by type, so `(when p …)` on a
  `p:&Node` is a test whose answer is already known. It reports
  `cond: &Node is non-null, so this test is always true -- spell the value ?T
  if it can be null`. Writing the test out as `(= p null)` or `(!= p null)` is
  refused the same way.
- **`!T` / `Result`.** Neither true nor false: `a Result (!T) is neither true
  nor false -- eliminate it with match, try or unwrap`.
- **`(dyn P)`, `BoxedFn`, `StrView`, structs.** A fat pointer has two halves and
  a string view is not a pointer; none of them has a defensible truth value.

This is an **elimination rule at condition position, not an implicit
coercion** — see [Implicit Type Coercion](types.md#implicit-type-coercion). A
`bool` parameter, field, or `let` slot still refuses a pointer.

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
   returns. So does every form that **produces** a fresh stack slot and hands
   back its address: `(alloca T)`, a struct compound literal `(S …)`, an array
   literal `(array T …)`, and a collection literal `[…]`/`#{…}`/`{…}` (whose
   `(ref (Vector T))` is a stack header — only the elements are on the heap).
   (Concern: pointer provenance only — `let` runs **no** drop and confers
   **no** ownership; this is purely a use-after-free check.)

Both share one mechanism:

- Taint follows pointer **identity**: binding a tainted value (`let`/`with`/
  `set!`), `as`/`unsafe/cast`, `unsafe/ptr+`, `ref`, and control-flow
  joins keep it (a join of frame addresses stays a frame address; one
  `with`-owned contributor makes the whole join `with`-owned).
  Copying the pointee **value** out (`deref`, field loads) clears it — so
  `(return (deref p))` and `(return (p count))` are fine. The same holds for
  the implicit load into a **by-value struct slot**: frame taint is a property
  of an address, so `(defn make ():Pt (Pt 1 2))`, `(defvar g:Pt (Pt 1 2))` and
  `(defvar opts:(Vector i32) [1 2 3])` are all fine — the struct (and, for a
  `Vector`, the ownership of its heap buffer) is copied out of the frame slot,
  and the taint is **discharged** at that store rather than carried.
- `ref` (`&x`) and the slot producers above (`alloca`, the literals) are the
  **frame-local taint sources**. `ref` does **not** taint:
  - the address of a **global** (`defvar`/`defconst`) — it outlives any frame;
  - the address of a **reference/pointer parameter** or any pointer-typed local
    — the slot holds a pointer whose pointee is caller-owned, so a value
    *loaded out of* it may legitimately be returned (the existing untracked
    imprecision boundary). So `(ref v 'field)` through a `(ref T)` parameter
    still returns fine.
- **Escape sinks** (compile errors on tainted operands):
  - **`return`** (explicit, and the implicit fall-off value of a non-`void`
    function) rejects *any* tainted value — both a `with`-owned alias and a
    pointer into frame-local storage. This is the function-frame boundary, and
    it catches the classic `(return &x)` / `return &local` bug, and with the
    slot producers `(return (alloca T))`, `(defn f ():&Pt (Pt 1 2))` and
    `(defn f ():&(Vector i32) [1 2 3])`. A `void` function's last form is not
    a sink — nothing leaves it.
  - **A `defvar` initializer.** A run-time initializer executes in the
    program's startup function, whose frame is gone before `main`, so a frame
    address stored into the global there is refused — `(defvar g:&Box (alloca
    Box))` and `(defvar opts:&(Vector i32) [1 2 3])` both die with
    `defvar: the initializer of 'opts' is the address of frame-local storage`.
    Store the value itself (`(defvar opts:(Vector i32) […])`, then `&opts` at
    the use sites) or place it with an allocator (`vector-new-in`).
  - **Stores into longer-lived memory** (`set!` to an outer binding;
    a `set!` place (member, element, or pointee) into memory not owned by the same or an inner
    `with`) reject **`with`-owned** taint only. A frame-local pointer stored
    into other frame memory — or into a global from an ordinary function, the
    scoped push/pop shape `with-handler` uses — is an intra-frame borrow; full
    nested-region store precision is deferred, so the frame boundary is
    enforced at `return` and at the initializer function only. Manually
    calling `free`/`drop` on an owning binding is a double-free error.
- **`(move b)`** is the sanctioned way out of a `with` scope: it disarms the
  cleanup, clears the taint, and consumes the binding.
- Passing a tainted value as a **function argument** is allowed — downward flow
  is a borrow (the callee retaining the pointer is the same residual risk as C),
  and pointers loaded *out of* a resource are not tracked — the two documented
  imprecision boundaries of the cheap, intraprocedural tier.

```lisp
(defn bad ():ptr
  (let (x:i32 5)
    (return &x)))        ; ERROR: address of frame-local 'x' escapes via return

(defn point-x ((p (ref Point))):ref:i32
  (return (ref p 'x)))              ; OK: pointee is caller-owned (ref parameter)
```

The `Drop` protocol is an ordinary Stage 9 protocol; conforming makes a type
`with`-manageable with zero dispatch overhead:

```lisp
(defprotocol Drop
  (drop:void (self:ptr:Self)))
(defn drop (self:ptr:Res):void ...)   ; concrete method
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

There is no unary bitwise complement operator; `bit-not` (`lib/nucleus/macros.nuc`) is a one-argument macro over `bit-xor` instead — see [Standard Macros](macros.md#standard-macros-libmacrosnuc).

**Mixed operands now resolve**: an untyped integer literal adapts to the other operand's numeric type (`(+ x 1)` with `x:i64`), an untyped *float* literal adapts to the other operand's float width (`(* alpha 2.0)` with `alpha:f32` is `f32`), and a narrower typed integer/float widens to the wider (`(+ i32 i64)`, `(+ f32 f64)`). The same literal adaptation applies outside binops, at any typed target — `(let (a:f32 0.1) …)`, an `f32` argument, an `f32` `return`; see [Types](types.md#built-in-types). A name bound by `defconst` or a `defenum` member counts as the literal it stands for, so `(<= ans:ui32 K)` with `(defconst K 512)` resolves exactly as `(<= ans:ui32 512)` does (a local binding that *shadows* the constant is an ordinary typed value). Genuinely mismatched operands (e.g. two different typed pointers in arithmetic, or mixed signedness of two typed values) are still rejected.

The rule is **symmetric in operand order** and the operator's *result type* is the unified operand type (a comparison is always `bool`), so `(* 2 x)` and `(* x 2)` are interchangeable — same type, same behaviour, same IR up to the operands' printed order. One shared rule decides this for both codegen and the compiler's static type pass, so an expression can never be inferred at one type and emitted at another. See [types.md](types.md#implicit-type-coercion) for the full unification table.

**User operator overloading.** Because operators are generics, a type becomes "addable"/"comparable" by defining a method. The variadic `+ - * /` macros fold to the binary primitives `_+ _- _* _/`, so arithmetic is overloaded on those names; the comparison operators are overloaded directly:

```lisp
(defstruct V2 x:i32 y:i32)
(defn _+ (a:ptr:V2 b:ptr:V2):ptr:V2 …)   ; (+ u v) now dispatches here
(defn = (a:ptr:V2 b:ptr:V2):bool …)  ; (= u v) dispatches here
```

A user operator method is emitted under a mangled symbol (`@add.pV2.pV2`, `@eq.pV2.pV2` — the symbols `+`/`=` are mapped to IR-safe mnemonics). A call with operand types that match no user method falls back to the built-in inline peephole.

**A struct literal compares by value.** A `(S …)` literal is a value, so a comparison with one — this is the rule for every comparison operator, `= != < <= > >=` — never compares its address. When no user method takes the operands as written, both are read as `S`: the literal as its struct, and a non-null `&S` on the other side loaded through. The by-value method (`(defn = (a:S b:S):bool …)`) then answers, and with none the comparison is refused. A `?&S` or `(ptr S)` operand is not read through, since it may be null; narrow it first. An arithmetic or bit operator reads a literal operand the same way; such a call was always an error before, so nothing that compiled changes. `=` on two references, neither a literal, is still pointer identity: `(= p q)` asks whether `p` and `q` are the same struct. A method written for the operands as written (`(defn = (a:&S b:&S):bool …)`) still wins over the by-value reading. A struct has no `=` unless its author defines one; the compiler does not derive one ([Derived structural equality](../design/deferred/overview.md#derived-structural-equality)).

**An operator that no method answers** is refused in the `no matching method` family, naming the protocol that the operand type does not conform to:

```
t.nuc:9: error: no matching method for '=': Pt does not conform to Eq
  note: a struct literal compares by value, never by address
  note: define (defn = (a:Pt b:Pt):bool …) to give Pt '='; to conform to Eq, define its methods and assert (extend Pt Eq) after (import-use nucleus.numeric)
```

`= !=` name `Eq`, `< <= > >=` name `Ord` and `_+ _- _* _/` name `Num`. `%` (integers or floats) and the bit operators (integers) belong to no protocol, so the message names what they take instead. When the operands have two different types, both are listed: `no matching method for '=' with operand types (Pt, i32)`. That form has no protocol clause when `Pt` already has its `=`, because the pairing is what fails.

The **standard numeric protocols** live in `lib/nucleus/numeric.nuc`: `Eq` (`= !=`), `Ord` (`< <= > >=`, a superset of `Eq` via `(extend Ord Eq)`), and `Num` (`_+ _- _* _/`). Built-in numeric types conform automatically (their intrinsic operators satisfy the requirements); a user type conforms by defining the methods and asserting `(extend &MyType Ord)` — any pointer spelling of the subject (`(ref MyType)`, `ptr:MyType`, `?&MyType`, …) is the same conformance ([pointer subjects](generics.md#protocols-defprotocol-and-extend)). See [Bounded generic `defn`](generics.md#bounded-generic-defn).

## Callable values (non-function call position)

A **non-function value in head position**, `(s arg…)`, is no longer an error — it
routes **`invoke → get → _get`** by the callee's *type*:

| precedence | condition on the callee type | desugars to | meaning |
|---|---|---|---|
| 1 | the argument is a **quoted symbol naming a field** of the callee's struct | `(get s 'field)` | field access |
| 2 | has an `invoke` method | `(invoke s arg…)` | indexing / general call (arg is a **value**) |
| 3 | has a custom `get` method | `(get s arg)` | value-keyed or symbol member access |
| 4 | otherwise (plain struct) | `(get s 'field)` → `_get` | raw field access (**quoted** symbol; any other selector is computed) |

Row 1 is what lets one type have both: `Node` conforms to `Seq`, so `(xs i)`
indexes an AST list while `(xs 'kind)` still reads its `kind` field. It fires only
on a **literal** quoted symbol that the receiver really has a field for; a selector
that names no field falls through, so a type whose `invoke` takes a symbol is
unaffected. Otherwise **`invoke` takes precedence**, and a type that defines it
indexes/applies its argument as a *value* — `(v idx)` evaluates the local `idx` and
indexes, rather than reading a field named `idx`. A **plain struct** (no `invoke`,
no custom `get`) takes a quoted-symbol argument as a field selector via the raw
`_get` intrinsic, so `(p 'x)` ≡ `(_get p 'x)` and is zero-overhead.

**`invoke` sees the callee's type exactly.** `Vector`'s `invoke` takes `&(Vector T)`, so a by-value `(Vector i32)` binding in head position does not index: write `(&v i)`. Since it would otherwise fall through to computed field access and fail there, the error says that instead: `'(Vector i32)' is indexed through invoke, which takes &(Vector i32), not a value -- write (&v ...)`.

**A field name is quoted; a bare symbol is a variable.** `(p 'x)` reads the field
`x`; `(p x)` evaluates `x` like a symbol anywhere else and uses the result as a
[computed selector](#computed-selector-get-only). Nothing about selector position
is special any more, which is the whole point: a field name held in a variable
needs no annotation, no `invoke`, and no escape hatch.

```lisp
(with ((m (ref (HashMap CStr i32))) {"foo" 42}
       k:CStr "foo")
  (m k))         ; ⇒ (get m <value of k>) → (some 42)

(let (p:ptr:Point (alloca Point) sel:ptr 'y)
  (p 'x)         ; the field `x`
  (p sel))       ; the field `sel` names, chosen at runtime
```

The rule holds for a **name that collides with a real field**, in either
direction: `(m 'count)` is `HashMap`'s `count` field and `(m count)` is the entry
under the local `count`, with no precedence question to resolve. It holds for
globals as well as locals, which the old demotion could not — every function
lives in the global scope, so a rule that consulted the scope would have
re-interpreted `(sd name)` the moment any global named `name` existed.

The two fixed-position member forms — `_get` and the 2-argument
`ref` — instead require a **literal** selector, since they are the
spellings that name a field statically.
A bare symbol there is refused outright rather than read as a variable:

```
(set! (p x) 1)   ; error: set!: field name must be a quoted selector -- write 'x
```

The same missed quote in head position is caught when the name is unbound, which
is overwhelmingly what a missed quote looks like:

```
(p x)           ; error: get: 'x' is undefined here, and a bare symbol in selector
                ;        position is an ordinary variable -- write (p 'x)
```

Before Stage 16 a bare symbol in selector position named a field and the quoted
spelling was an accepted synonym; `(m count:CStr)` was the annotation hatch that
forced the value reading. Both are gone —
see [dot-forms.md](../design/stage16-ergonomics/dot-forms.md) for the migration.

**`get` — member access (the `Struct` default).** Every struct conforms to the
built-in `Struct` blanket protocol, whose `get` is supplied by an **intrinsic**: a
literal selector const-folds to a static `getelementptr`+`load`, **identical to the
`_get` primitive and zero-overhead**. So `(c 'rad)` ≡ `(get c 'rad)` ≡ `(_get c 'rad)`.
Head position `(c 'rad)` is the idiomatic spelling; `_get` is the escape hatch (it
reads the field directly, skipping any user `get` override — so a user `get` method
uses `_get` for its own fields to avoid recursing into itself).

```lisp
(defstruct Point x:i32 y:i32)
(p 'x)         ; ≡ (get p 'x) — a plain field load
```

The intrinsic is **overridable**: a concrete user `get` method for a type sits at
tier 0 and out-ranks the blanket intrinsic, so it owns *all* member access on that
type. A user `get` takes the selector as an interned symbol (`ptr`):

```lisp
(defn get (self:ptr:Temp sel:ptr):i32
  (if (= sel 'f) (return …) (return (_get self 'c))))  ; (t 'f) and (t 'c) both route here
```

**Value-keyed `get` (computed selectors).** Dispatch splits on the selector kind.
A **quoted-symbol** selector takes the member-access path above (the selector
value is always an interned symbol `ptr`). Anything else is an expression —
including a bare symbol, which is an ordinary variable reference. A
**computed/value selector** — an `i32`, a
`CStr`, a `StrView` (e.g. a string literal), or any non-symbol value — instead
resolves the `get` generic on the selector's *actual* type, so a parametric `get`
override can index by a real key. A string-literal selector resolves against a
`(Bag K V)` whose `K` is `StrView` directly; if resolution instead finds only a
`CStr`-keyed method (the common case — collection literals still infer `CStr`
element/key types), the literal retries once collapsed to `CStr`:

```lisp
(defstruct (Bag K V) key:K val:V has:i32)
(defn get ((self (ref (Bag K V))) key:K) (Maybe V) …)   ; value-keyed lookup
(get bag "hello")    ; StrView literal selector (retries as CStr) → the (Bag K V) get method, returns (Maybe V)
(get bag 42)         ; i32  selector → the same method
(get bag 'val)       ; symbol selector → field access, returns the raw V field
```

The value-keyed override is found even when it is a parametric (generic) method:
the resolver binds the method's type variables and checks its `:where` constraints
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
(defn invoke (self:ptr:Vec i:i32):i32 (return (aref (_get self 'data) i)))
(v 3)          ; ⇒ (invoke v 3) → element access (literal index)
(let (idx:i32 1) (v idx))   ; ⇒ (invoke v idx) → indexes; NOT a field named idx
(_get v 'len)   ; field access — `(v 'len)` would mis-route to invoke
```

**`invoke` falls back to `get`.** If no `invoke` method accepts the receiver, a
one-argument `(invoke callee arg)` retries the resolution against the `get`
generic. That is how a `HashMap` — which exposes its lookup as `get` and has no
`invoke` at all — answers `(invoke m k)`. It is no longer needed to *force* the
value reading, since a bare symbol already is one:

```lisp
(m 'count)          ; the `count` FIELD — quote it to mean the name
(m count)           ; the value under the key in `count`
```

For parametric function-object conformance use `(UnaryFn Arg Ret)` and
`(FoldFn Acc Elem)` from `lib/nucleus/iterator.nuc`
(see [Generics](generics.md#associated-type-bounds-where-protocol-arg--var)).
See `examples/callable.nuc` for a full demonstration, and
`examples/selector-value.nuc` for the member-access matrix.

**Computed selector (`get` only).** An *explicit* `(get callee expr)` whose
selector is anything but a quoted symbol — a bare symbol included — reads a field
chosen at runtime: the selector is compared by pointer identity against the struct's
interned field symbols. Restricted to **homogeneous** structs (all fields one
type) so the result type is well-defined; a heterogeneous struct is a clear error.

**Arbitrary-expression and function-pointer heads.** The head need not be a
symbol: `((mk-vec) 3)` and `(@p 3)` emit the head once and route the same way. A
head whose value is a **function pointer** folds to an indirect call, so
`(f a b)` works for a local/global fn-pointer variable `f` and the explicit
`funcall`/`unsafe/funcall-ptr-*` forms are now compiler-internal (still
accepted; the bare `funcall-ptr-*` spellings were retired in Stage 14 — see
the Special Forms table above).

Everything resolves at compile time to a static GEP+load, a direct `call` to a
resolved method, or an indirect `call` through a fn-pointer — no dispatch object,
no vtable. `get`/`invoke` overloads export through the existing
`defmethod`/`defprotocol`/`extend` machinery; there is no new `.nuch` form.
