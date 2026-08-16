# Macros

## Macros belong to a namespace

A macro belongs to the namespace of the file that declares it, and is spelled
like every other kind — see [What an import brings into scope](toplevel.md#what-an-import-brings-into-scope):
bare inside its own namespace, `p/name` through a prefix a file bound, bare or
`ns/name` through `import-use`. A prefixed import does **not** put the library's
own namespace in scope, and a macro reachable only through a prefix is offered
as `p/name` by the did-you-mean rather than as a bare name that would fail again.

Two consequences:

* **Two namespaces may each declare a macro of the same name.** They are two
  macros; each prefix reaches its own.
* **A facade may re-export a macro** (`(export p/my-macro)`), and it expands
  through the facade's prefix in the consumer.

Within one namespace a name may be defined once — a second `defmacro` of the
same name is an error naming both definitions, rather than the older behaviour
where the first definition silently won and the second was unreachable.

The prelude is flattened into every file, so `when`, `unless`, `dotimes` and the
rest below are always available unqualified, including from inside a file with
its own `(ns …)`.

## Standard Macros (`lib/macros.nuc`)

Defined via `defmacro`. The compiler auto-imports `lib/prelude.nuc` (which defines the `Node` struct, the `NODE-*` enum, and `(import-use macros)`) into every program, so all of these are available without an explicit `(import-use macros)`. **Defining or using a macro costs a program nothing**: a macro body becomes its own JIT module and resolves the node constructors against the compiler process, so no runtime is emitted for it. To opt out — e.g. when a source file should compile against the bare language with no macros, no `Node` type, and no `string` libc declarations — make `(exclude-prelude)` the first form in the file.

| Name | Signature | Expands To |
|------|-----------|------------|
| `if` | `(if test then else)` | `(cond test then true else)` |
| `case` | `(case form v1 r1 v2 r2 ... default)` | `(cond (= form v1) r1 (= form v2) r2 ... true default)` |
| `when` | `(when condition body...)` | `(cond condition (do body...))` |
| `unless` | `(unless condition body...)` | `(cond (not condition) (do body...))` |
| `zero?` | `(zero? x)` | `(= x 0)` |
| `null?` | `(null? x)` | `(= x null)` |
| `bit-not` | `(bit-not x)` | `(bit-xor x -1)` — unary bitwise complement, correct at any width in two's complement |
| `for` | `(for (var:type init) test step body)` | `(let (var:type init) (while test body step))` |
| `dotimes` | `(dotimes (var:type n) body)` | `(let (var:type 0) (while (< var n) body (inc! var)))` |
| `doseq` | `(doseq (var coll-expr IterType) body...)` | Iterate a **collection** conforming to `(Coll E It)`: calls `(iter coll-expr)` to get a fresh `IterType` by value, binds it to a typed local, and drives `(next (addr-of it))` each step, binding each element to `var`. `IterType` must be named explicitly because `let` bindings have no type inference and `addr-of` requires a named local (not an rvalue). `IterType` examples: `(VecIter i32)`, `(HashSetIter i32)`, `(HashMapEntryIter CStr i32)`. See [Iterators](iterators.md). |
| `doseq-iter` | `(doseq-iter (var iter-ref) body...)` | Iterate a **bare iterator reference**: calls `(next iter-ref)` each step, binding each element to `var`. Use for types that conform to `(Iterator E)` but are not a `Coll` — e.g. `IntRangeIter`, `MapIter`, `FilterIter`, `HashMapKeyIter`. `iter-ref` must be a `(ref IterType)` already materialised by the caller. |
| `into` | `(into dest-coll src-coll IterType)` | Drain a **collection** `src-coll` into `dest-coll`: calls `(iter src-coll)` to get a fresh `IterType` by value, then `(conj dest-coll elem)` for each element. `IterType` is the associated iterator type of `src-coll`. |
| `into-iter` | `(into-iter dest-coll iter-ref)` | Drain a **bare iterator reference** `iter-ref` into `dest-coll`: calls `(next iter-ref)` each step and `(conj dest-coll elem)` for each element. The pre-Coll form, kept for pure iterators that have no `iter`. |
| `->` | `(-> x form ...)` | Threads `x` through each form. If a form contains `_`, the value replaces `_`; otherwise inserts as first arg (thread-first). Bare symbols wrap as `(sym value)`. `_` is only special inside `->`. |

`case` is multi-way equality dispatch: it compares `form` against each value `vi` with `=` and yields the first matching result `ri`. The final unpaired argument is the **required** default. Because `=` is overloadable, `case` works over any type with an equality (integers, enum constants, symbols, C strings). `form` is re-evaluated per comparison, so it should be side-effect free.

`(import-use arena)` additionally provides `(new T)` — allocate one zeroed `T` from the arena, typed `(ref T)` (non-null: `arena-alloc` aborts on exhaustion rather than returning null). It expands to `(as (ref T) (arena-alloc (sizeof T)))`, collapsing the `as` + `sizeof` boilerplate for the common "allocate a single struct" case (`arena-alloc` returns bare `ptr`; retyping it to a non-null `(ref T)` is exactly the elem-less-`ptr` `void*` hatch `as` accepts). It is **not** in the prelude (it depends on `arena-alloc`), so it requires an explicit `(import-use arena)`.

## Variadic Arithmetic

`+ - * /` are macros that expand to nested binary primitive calls. They live in `lib/macros.nuc` and are available in every program via the auto-imported prelude. The binary primitives `_+ _- _* _/` are the actual binops; the macros exist to break the expansion cycle.

| Form          | Expansion                                       |
|---------------|-------------------------------------------------|
| `(+)`         | `0`                                             |
| `(+ x)`       | `x`                                             |
| `(+ a b ...)` | `(_+ a (+ b ...))` — right-fold                |
| `(*)`         | `1`                                             |
| `(* a b ...)` | `(_* a (* b ...))` — right-fold                |
| `(- x)`       | `(_- 0 x)` — unary negation                    |
| `(- a b)`     | `(_- a b)`                                     |
| `(- a b ...)` | `(- (_- a b) ...)` — left-fold                 |
| `(/ x)`       | `(_/ 1 x)` — integer reciprocal                |
| `(/ a b ...)` | `(/ (_/ a b) ...)` — left-fold                 |

## Variadic Logical Operators

`and`/`or` are macros that expand to nested binary short-circuit primitive calls, mirroring the `_+`/`+` split above. They live in `lib/macros.nuc` and are available in every program via the auto-imported prelude. The binary primitives `_and`/`_or` are the actual short-circuit forms; the macros exist to make the logical operators variadic.

| Form          | Expansion                                       |
|---------------|-------------------------------------------------|
| `(and)`       | `true`                                          |
| `(and x)`     | `x` — **unchecked** (no i1 check)              |
| `(and a b ...)` | `(_and a (and b ...))` — right-fold          |
| `(or)`        | `false`                                         |
| `(or x)`      | `x` — **unchecked** (no i1 check)              |
| `(or a b ...)` | `(_or a (or b ...))` — right-fold             |

The binary `_and`/`_or` i1-check both operands and short-circuit left-to-right (`_and` stops at the first false, `_or` at the first true). Because the macro right-nests, each operand in an N-ary chain narrows under all prior ones (cumulative narrowing — a later `(m field)` typechecks after an earlier `(!= m null)`). See the [`and`/`or`/`_and`/`_or`](special-forms.md#special-forms) rows for the full short-circuit and narrowing semantics.

## `macrolet` — lexically scoped macros

`let`, but for macros. A `macrolet` binding exists for the body of the form and
nowhere else, which is what makes a deliberately capturing macro — the reliable
way to abstract a repeated pattern inside one function — affordable: the name
never reaches the global namespace.

```
(macrolet (BINDING BINDING ...) BODY-FORM ...)

BINDING ::= (NAME (PARAM ...) MACRO-BODY-FORM ...)
```

```lisp
(defn point-sum ((p (ref Point))):i32
  (let (total:i32 0)
    (macrolet ((take (f) `(set! total (+ total (. p ~f)))))
      (take x)
      (take y))
    total))
```

`take` names `total` and `p` — locals of the enclosing function. There is no
hygiene, exactly as with `defmacro`: names in the expansion resolve at the call
site, which is the point. `gensym` is available in a `macrolet` body for the
cases that want a fresh name instead.

The full example is [`examples/macrolet.nuc`](../examples/macrolet.nuc).

**Rules.**

* **A binding is an expression form**, not a definer: `macrolet` may appear
  wherever an expression may, and a top-level `(macrolet …)` is refused with
  `unknown top-level form: macrolet`.
* **The body is a `do`.** Its value is the last form's, it introduces no new
  variable scope, and `let`/`defer` inside it behave as they would inside a `do`.
* **Bindings are sequential**, like Nucleus `let` — a later binding's body sees
  an earlier one. (Common Lisp's `macrolet` is parallel; Nucleus follows its own
  `let` instead.) A binding is also visible inside its own body, matching
  `defmacro`.
* **A binding shadows** a global macro, function or local of the same spelling
  in head position, for the body only; an inner `macrolet` shadows an outer one
  and the outer is restored afterwards.
* **A binding may not shadow a special form.** The macro table is consulted
  before special forms, so a binding named `let` would take over `let` for the
  whole body; it is refused instead
  (`macrolet: 'let' is a special form and may not be shadowed`).
* **`:rest` works** exactly as in `defmacro` — the parameter list is parsed by
  the same code, and the same "second-to-last param" rule applies.
* **The binding name takes no type annotation**, like every other definer name.
* Bindings are not exported, not namespace-qualified, and not visible to
  `macroexpand` from outside the body. Reader macros (`def-rmacro`) remain
  global.

A `macrolet` body is compiled and JIT'd exactly as a `defmacro` body is, so it
has the same compile-time requirements — the `Node` type, which the prelude
provides, and the node constructors, which its JIT module resolves against the
compiler process (so neither body needs `(import-use node)`). It works anywhere an expression does,
including inside a loop, inside a `cond` arm, in argument position, inside a
generic template body (compiled once per monomorphization), and inside a
`defmacro` body.

## The type of a quoted form

`'x` yields a `Node*`, but **which** pointer type depends on what was quoted:

| Quoted | Type | Why |
|---|---|---|
| a symbol — `'foo` | `(ref Node)` | Lowers to `intern-symbol`, whose signature returns `ref:Node`. One canonical node per spelling, so the value is non-null *and* an identity. |
| anything else — `'(a b)`, `'1`, `'()` | `(raw Node)` | Built by `make-cell`/`alloc-node`, and `'()` **is** null. |

The distinction is load-bearing, not cosmetic: because `'foo` is non-null and
interned, symbols work directly as collection elements and keys — see
[Symbols as keys](collections.md#symbols-as-keys). A quoted symbol still fits a
`(raw Node)` slot (non-null narrows into nullable), so nothing written before
this rule needs changing.

`quasiquote` stays `(raw Node)` throughout: an unquote can inject any value, so
its result type is expansion-dependent.

**In ordinary code a quote is a run-time call**, so a program that writes one
needs `(import-use node)` — the prelude registers the `Node` type but no longer
emits the constructors. Inside a `defmacro`/`macrolet`/`compile-time` body it
needs nothing: that body is a JIT module resolved against the compiler process.
See [The node runtime is a library](toplevel.md#the-node-runtime-is-a-library).

## Macros and pass-through arguments

Macro parameters are typed `(raw Node)` — the macro sees AST. Because the
parameter is a typed (nullable, unchecked) pointer to `Node`, a macro can walk
the argument's structure with member access **without casting**: `(p car)`,
`(p cdr)`, and chains such as `((p cdr) car)` type-check directly — `car`/`cdr`
are themselves `(raw Node)`, so they chain. Use `(p kind)` / `(p s)` / `(p i)`
/ `(p line)` for the other `Node` fields. (Historically these required
`((cast ptr:Node p) car)` because `car`/`cdr` were untyped `ptr`; that cast is
now redundant. If written today it would be `((as ptr:Node p) car)` — bare
`cast` is a Stage 14 hard error — but there's no need to write it at all:
`ptr`↔`(raw Node)` is a no-op reinterpret the compiler already performs.)

When the macro splices a parameter into its expansion via `~param`, the
resulting form is compiled as if the user had written that expression directly
at the call site, so the *value* type the parameter evaluates to in the
expansion is whatever the user wrote — `i32`, `ptr:i8`, `f64`, `Foo`, etc.

This means a single macro can take, inspect, and splice arguments of different
value types — there is no value-level `T` to keep consistent across calls;
only the AST representation is uniform.

```lisp
; Pick a printf format from the literal kind, then splice the original
; expression in. The macro inspects (. x kind) at expansion time; the
; spliced ~x is compiled at the call site with whatever type it has.
(defmacro tprint (x)
  (cond (= (. x kind) NODE-INT) `(printf "%d\n" ~x)
        (= (. x kind) NODE-STR) `(printf "%s\n" ~x)
        (= (. x kind) NODE-FLOAT) `(printf "%f\n" ~x)
        true                    `(printf "%p\n" ~x)))

(tprint 42)        ; → (printf "%d\n" 42)        — i32 at the call site
(tprint "hi")      ; → (printf "%s\n" "hi")      — ptr:i8 at the call site
(tprint 3.14)      ; → (printf "%f\n" 3.14)      — f64 at the call site
(tprint some-ptr)  ; → (printf "%p\n" some-ptr)  — ptr at the call site
```

Inside the macro `x` is `(raw Node)`; the spliced `~x` carries no type
constraint into the expansion. The host compiler types the resulting form
using its normal rules.

### ⚠ Sharp edge: `cond`/`if` branches of genuinely different element types collapse to void

A `cond`/`if` is a *value* expression whose result type is the **join** of its
branches. Two pointer branches with different *element* types — `(raw Node)`
vs `i32`, or two different struct types — do not unify, and the whole
expression collapses to `void`. That failure then surfaces as:

- a `let`/`set!` reporting `init type mismatch` / a type error, and
- a macro whose entire body is such a `cond` **silently returns `null`**,
  surfacing later as `macro '<name>': returned null`.

This is a genuine type error; there's no shortcut but making the branches
agree on element type.

Mixing a **typed** pointer branch (`(raw Node)`, `ptr:Foo`, `ref:Foo`, ...)
with a **bare, elem-less** `ptr` branch is *not* a collapse case — the join
absorbs the bare side into the typed side's element type, producing
`(raw ElemType)`, with no cast required. This matters constantly in macro
bodies: quasiquote (`` `(...) ``), `(gensym)`, and the `null` literal are all
bare `ptr`, so they join freely with a `(raw Node)` branch such as `car`/`cdr`
or a macro parameter:

```lisp
; joins to (raw Node) automatically — no cast needed
(let (rest (if (= (n kind) NODE-CELL) (n cdr) null)) ...)

; A variadic-operator macro: the single-arg branch returns the element node,
; the others are quasiquoted forms — both join to (raw Node).
(defmacro * (:rest args)
  (cond (= args null)
          `1
        (= (args cdr) null)
          (args car)
        true
          `(_* ~(args car)
                (* ~@(args cdr)))))
```

Pointer *kind* (`raw` vs. `ref`) is never itself a source of collapse —
kinds meet (`raw` ⊔ anything = `raw`) rather than needing to match. Only a
genuine element-type mismatch collapses the join to `void`.

Separately: a `(raw Node)` value flows freely into a bare `:ptr` local (exempt
— bare `ptr` is `void*` and carries no contract), but a **typed** non-null
`(ptr T)`/`(ref T)` parameter, `return`, or binding still **rejects** a raw
(nullable) value (`raw pointer where non-null (ref ...) is required`). Bind
node values to `:ptr` locals, or narrow first, when they meet other pointer
types.
