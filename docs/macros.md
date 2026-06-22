# Macros

## Standard Macros (`lib/macros.nuc`)

Defined via `defmacro`. The compiler auto-imports `lib/prelude.nuc` (which defines the `Node` struct, the `NODE-*` enum, and `(import-use macros)`) into every program, so all of these are available without an explicit `(import-use macros)`. To opt out — e.g. when a source file should compile against the bare language with no macros, no `Node` type, and no `string` libc declarations — make `(exclude-prelude)` the first form in the file.

| Name | Signature | Expands To |
|------|-----------|------------|
| `if` | `(if test then else)` | `(cond test then true else)` |
| `case` | `(case form v1 r1 v2 r2 ... default)` | `(cond (= form v1) r1 (= form v2) r2 ... true default)` |
| `when` | `(when condition body...)` | `(cond condition (do body...))` |
| `unless` | `(unless condition body...)` | `(cond (not condition) (do body...))` |
| `zero?` | `(zero? x)` | `(= x 0)` |
| `null?` | `(null? x)` | `(= x null)` |
| `for` | `(for (var:type init) test step body)` | `(let (var:type init) (while test body step))` |
| `dotimes` | `(dotimes (var:type n) body)` | `(let (var:type 0) (while (< var n) body (inc! var)))` |
| `doseq` | `(doseq (var coll-expr IterType) body...)` | Iterate a **collection** conforming to `(Coll E It)`: calls `(iter coll-expr)` to get a fresh `IterType` by value, binds it to a typed local, and drives `(next (addr-of it))` each step, binding each element to `var`. `IterType` must be named explicitly because `let` bindings have no type inference and `addr-of` requires a named local (not an rvalue). `IterType` examples: `(VecIter i32)`, `(HashSetIter i32)`, `(HashMapEntryIter CStr i32)`. See [Iterators](iterators.md). |
| `doseq-iter` | `(doseq-iter (var iter-ref) body...)` | Iterate a **bare iterator reference**: calls `(next iter-ref)` each step, binding each element to `var`. Use for types that conform to `(Iterator E)` but are not a `Coll` — e.g. `IntRangeIter`, `MapIter`, `FilterIter`, `HashMapKeyIter`. `iter-ref` must be a `(ref IterType)` already materialised by the caller. |
| `into` | `(into dest-coll src-coll IterType)` | Drain a **collection** `src-coll` into `dest-coll`: calls `(iter src-coll)` to get a fresh `IterType` by value, then `(conj dest-coll elem)` for each element. `IterType` is the associated iterator type of `src-coll`. |
| `into-iter` | `(into-iter dest-coll iter-ref)` | Drain a **bare iterator reference** `iter-ref` into `dest-coll`: calls `(next iter-ref)` each step and `(conj dest-coll elem)` for each element. The pre-Coll form, kept for pure iterators that have no `iter`. |
| `->` | `(-> x form ...)` | Threads `x` through each form. If a form contains `_`, the value replaces `_`; otherwise inserts as first arg (thread-first). Bare symbols wrap as `(sym value)`. `_` is only special inside `->`. |

`case` is multi-way equality dispatch: it compares `form` against each value `vi` with `=` and yields the first matching result `ri`. The final unpaired argument is the **required** default. Because `=` is overloadable, `case` works over any type with an equality (integers, enum constants, symbols, C strings). `form` is re-evaluated per comparison, so it should be side-effect free.

`(import-use arena)` additionally provides `(new T)` — allocate one zeroed `T` from the arena, typed `(ref T)` (non-null: `arena-alloc` aborts on exhaustion rather than returning null). It expands to `(cast (ref T) (arena-alloc (sizeof T)))`, collapsing the cast + `sizeof` boilerplate for the common "allocate a single struct" case. It is **not** in the prelude (it depends on `arena-alloc`), so it requires an explicit `(import-use arena)`.

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

## Macros and pass-through arguments

Macro parameters are typed `ptr:Node` — the macro sees AST. When the macro
splices a parameter into its expansion via `~param`, the resulting form is
compiled as if the user had written that expression directly at the call site,
so the *value* type the parameter evaluates to in the expansion is whatever
the user wrote — `i32`, `ptr:i8`, `f64`, `Foo`, etc.

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

Inside the macro `x` is `ptr:Node`; the spliced `~x` carries no type
constraint into the expansion. The host compiler types the resulting form
using its normal rules.
