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
| `case` | `(case form v1 r1 v2 r2 ... default)` | `(cond (= form v1) r1 (= form v2) r2 ... true default)`. A value may be `(:or v ...)`, matching any one of the listed values: `(case x (:or a b) r d)` → `(cond (or (= x a) (= x b)) r true d)`. |
| `when` | `(when condition body...)` | `(cond condition (do body...))` |
| `unless` | `(unless condition body...)` | `(cond (not condition) (do body...))` |
| `zero?` | `(zero? x)` | `(= x 0)` |
| `null?` | `(null? x)` | `(= x null)` |
| `bit-not` | `(bit-not x)` | `(bit-xor x -1)` — unary bitwise complement, correct at any width in two's complement |
| `for` | `(for (var:type init) test step body)` | `(let (var:type init) (while test body step))` |
| `dotimes` | `(dotimes (var n) body...)` | `(let (var (* n 0)) (while (< var n) body... (inc! var)))` — the index takes the count's type unless `var` is annotated (`i:i32`) |
| `doseq` | `(doseq (var coll-expr IterType) body...)` | Iterate a **collection** conforming to `(Coll E It)`: calls `(iter coll-expr)` to get a fresh `IterType` by value, binds it to a typed local, and drives `(next &it)` each step, binding each element to `var`. `IterType` must be named explicitly because `let` bindings have no type inference and `&` requires a named local (not an rvalue). `IterType` examples: `(VecIter i32)`, `(HashSetIter i32)`, `(HashMapEntryIter CStr i32)`. See [Iterators](iterators.md). |
| `doseq-iter` | `(doseq-iter (var iter-ref) body...)` | Iterate a **bare iterator reference**: calls `(next iter-ref)` each step, binding each element to `var`. Use for types that conform to `(Iterator E)` but are not a `Coll` — e.g. `IntRangeIter`, `MapIter`, `FilterIter`, `HashMapKeyIter`. `iter-ref` must be a `(ref IterType)` already materialised by the caller. |
| `into` | `(into dest-coll src-coll IterType)` | Drain a **collection** `src-coll` into `dest-coll`: calls `(iter src-coll)` to get a fresh `IterType` by value, then `(conj dest-coll elem)` for each element. `IterType` is the associated iterator type of `src-coll`. |
| `into-iter` | `(into-iter dest-coll iter-ref)` | Drain a **bare iterator reference** `iter-ref` into `dest-coll`: calls `(next iter-ref)` each step and `(conj dest-coll elem)` for each element. The pre-Coll form, kept for pure iterators that have no `iter`. |
| `->` | `(-> x form ...)` | Threads `x` through each form. If a form contains `_`, the value replaces `_`; otherwise inserts as first arg (thread-first). Bare symbols wrap as `(sym value)`, and so does any other bare step: `(-> v 0)` is `(0 v)`, not indexing — write `(-> v (_ 0))`. `_` is only special inside `->`. |
| `macmap` | `(macmap ((param ...) template) (row ...))` | Expands `template` once per row, binding the parameters to the row, and splices the results in sequence. See [`macmap`](#macmap--one-template-over-a-table-of-rows) below. |
| `macfoldr` | `(macfoldr op unit a b c)` | `(op a (op b c))` — right-nested fold over a variadic argument list. No args → `unit`; one arg → that arg. See [`macfoldl`/`macfoldr`](#macfoldl--macfoldr--a-template-over-a-variadic-argument-list). |
| `macfoldl` | `(macfoldl op unit a b c)` | `(op (op a b) c)` — the left-nested counterpart. |

The binding list of `dotimes`, `doseq` and `doseq-iter` must have exactly the
shape shown, with a symbol first. Anything else is refused at the call's line —
`dotimes: the first argument must be (var count)`, `doseq: the first argument
must be (var coll IterType)`, `doseq-iter: the first argument must be (var
iter-ref)` — and a two-element `doseq` binding, `(doseq (x it) …)`, adds a note
pointing at `doseq-iter`.

Two notes on the `:type` annotation inside these expansions. `for` and `dotimes`
splice the annotated loop variable into the body, so `(dotimes (i:i32 n) (foo
i:i32))` writes the annotation twice: the first is the binding's declaration, the
second is a [value-position cast](types.md#type-syntax-and-desugar) — an identity
one, since it names the variable's own type, so it emits no instruction. It is no
longer decoration, though: an annotation there that names a *different* type
converts (or is refused, if the conversion is unsafe). And `->` finds its hole by
matching the bare symbol `_`, so an annotated hole (`_:ptr:Node`) is not
recognised as one — cast the threaded value in a form of its own instead.

`case` is multi-way equality dispatch: it compares `form` against each value `vi` with `=` and yields the first matching result `ri`. The final unpaired argument is the **required** default. Because `=` is overloadable, `case` works over any type with an equality (integers, enum constants, symbols, C strings). `form` is re-evaluated per comparison, so it should be side-effect free.

A value may be written `(:or v ...)`, which matches any one of the listed values and so lets arms that share a result collapse into one:

```lisp
(case (tt 'kind)
  (:or TY-PTR TY-FN TY-CSTR) "ptr"
  (:or TY-CHAR TY-ERR)       "i32"
  (type-ir-name tt))
```

The **keyword head is what marks the list** — a plain parenthesised value stays an ordinary expression, evaluated and compared like any other, so `(case x (f y) r d)` still calls `f`. That is why the marker exists at all: the values people group are overwhelmingly bare enum constants (`TY-STRUCT`, `NODE-SYM`), which are indistinguishable from a call's head, so nothing about the elements themselves can decide it ([case-alternatives.md](../design/stage16-ergonomics/case-alternatives.md)). Alternatives are ordinary expressions, each compared with the same `=`; `form` is re-evaluated once per alternative, and an empty `(:or)` is false, matching no value.

`(import-use arena)` additionally provides `(new T)` — allocate one zeroed `T` from the arena, typed `(ref T)` (non-null: `arena-alloc` aborts on exhaustion rather than returning null). It expands to `(unsafe/cast &T (arena-alloc (sizeof T)))`, collapsing the cast + `sizeof` boilerplate for the common "allocate a single struct" case. `arena-alloc` returns an unchecked bare `ptr`, and `as` refuses to make that non-null, so the macro asserts it with `unsafe/cast` — true because `arena-alloc` aborts rather than return null. It is **not** in the prelude (it depends on `arena-alloc`), so it requires an explicit `(import-use arena)`.

## Variadic Arithmetic

`+ - * /` are macros that expand to nested binary primitive calls. They live in `lib/macros.nuc` and are available in every program via the auto-imported prelude. The binary primitives `_+ _- _* _/` are the actual binops; the macros exist to break the expansion cycle.

| Form            | Expansion                                              |
|-----------------|--------------------------------------------------------|
| `(+)`           | `0`                                                    |
| `(+ x)`         | `x`                                                    |
| `(+ a b)`       | `(_+ a b)`                                             |
| `(+ a b c ...)` | `(macfoldr _+ 0 a b c ...)` → `(_+ a (_+ b c ...))` — right-fold |
| `(*)`           | `1`                                                    |
| `(* a b)`       | `(_* a b)`                                             |
| `(* a b c ...)` | `(macfoldr _* 1 a b c ...)` — right-fold               |
| `(-)`           | `0`                                                    |
| `(- x)`         | `(_- 0 x)` — unary negation                            |
| `(- a b)`       | `(_- a b)`                                             |
| `(- a b c ...)` | `(macfoldl _- 0 a b c ...)` → `(_- (_- a b) c ...)` — left-fold |
| `(/ x)`         | `(_/ 1 x)` — integer reciprocal                        |
| `(/ a b)`       | `(_/ a b)`                                             |
| `(/ a b c ...)` | `(macfoldl _/ 1 a b c ...)` — left-fold                |

The 0-, 1- and 2-ary arms are spelled out in each operator rather than left to
the fold, because 94% of the operator calls in a real program are binary and a
spelled-out arm costs one expansion where delegating costs two. Tree-wide that
is the difference between 6,066 macro expansions and 3,282
([design/stage20-macros/overview.md](../design/stage20-macros/overview.md) §3.1).
The resulting form is identical either way.

## Variadic Logical Operators

`and`/`or` are macros that expand to nested binary short-circuit primitive calls, mirroring the `_+`/`+` split above. They live in `lib/macros.nuc` and are available in every program via the auto-imported prelude. The binary primitives `_and`/`_or` are the actual short-circuit forms; the macros exist to make the logical operators variadic.

| Form              | Expansion                                            |
|-------------------|------------------------------------------------------|
| `(and)`           | `true`                                               |
| `(and x)`         | `x` — **unchecked** (no condition check)             |
| `(and a b)`       | `(_and a b)`                                         |
| `(and a b c ...)` | `(macfoldr _and true a b c ...)` → `(_and a (_and b c ...))` — right-fold |
| `(or)`            | `false`                                              |
| `(or x)`          | `x` — **unchecked** (no condition check)             |
| `(or a b)`        | `(_or a b)`                                          |
| `(or a b c ...)`  | `(macfoldr _or false a b c ...)` — right-fold        |

The binary `_and`/`_or` eliminate both operands to `bool` at each condition site (not just `bool` itself — a nullable `ptr`/`(ptr T)`/`CStr`/`?T` or a value `Maybe` is punned too, and a non-null `&T` or a `!T` gets its own diagnostic; see [Condition position](types.md#condition-position-is-an-elimination-not-a-coercion)) and short-circuit left-to-right (`_and` stops at the first false, `_or` at the first true). Because the macro right-nests, each operand in an N-ary chain narrows under all prior ones (cumulative narrowing — a later `(m field)` typechecks after an earlier `(!= m null)`). See the [`and`/`or`/`_and`/`_or`](special-forms.md#special-forms) rows for the full short-circuit and narrowing semantics.

## `macfoldl` / `macfoldr` — a template over a variadic argument list

```
(macfoldr OP UNIT ARG ...)   ; (OP a (OP b c))  — right-nested
(macfoldl OP UNIT ARG ...)   ; (OP (OP a b) c)  — left-nested
```

With no arguments the result is `UNIT`; with one, that argument, untouched. `OP`
is spliced into head position, so it may be any callable spelling — a primitive
such as `_+`, an ordinary function, or another macro.

These are the generalisation of the six operators above, and the way to make a
new operator variadic without copying their shape:

```lisp
(defn int-max (a:i32 b:i32):i32 (if (< a b) b a))
(defmacro maxn (a :rest more) `(macfoldl int-max ~a ~@more))

(maxn 3)            ; 3
(maxn 3 9 4 12 1)   ; 12
```

Note that this *is* a fold written inside a macro body, and it works: `~@more`
splices a list the macro already holds. A `macmap` there is a nested quasiquote,
which also works — see [Nesting levels](#nesting-levels).

Both are ordinary macros in `lib/macros.nuc`, available through the prelude.
They are defined before everything else in that file, so their own bodies use
only `cond` — nothing defined below them is callable from them yet.

**Nesting direction is a semantic choice, not a style one.** `and`/`or` fold
right so that each operand narrows under all the operands before it (cumulative
narrowing — see [Condition position](types.md#condition-position-is-an-elimination-not-a-coercion)),
and `-`/`/` fold left because they are not associative.

## `macmap` — one template over a table of rows

Expand one template once per row of a literal table, and splice the results in
sequence. It is the applied form of [`macrolet`](#macrolet--lexically-scoped-macros):
where `macrolet` binds a template to a name you then call, `macmap` supplies the
arguments too, for the common case where the name has exactly one use.

```
(macmap ((PARAM ...) TEMPLATE) (ROW ...))
```

```lisp
(macmap ((tok) `(when (!= (text-token-is text start e ~tok) 0) (return 1)))
  ("defn" "defmacro" "defvar" "defconst"))
```

**A one-parameter template takes each row whole**, so a row may be any
expression — including a parenthesised one. **A multi-parameter template
destructures** the row, which must then be a list of that many elements:

```lisp
(macmap ((res ret) `(when (= test ~res) (return ~ret)))
  (((+ 2 2) "four!") ("dammit" "curses!") (null 0)))
```

**Rules.**

* **The template is an ordinary quasiquote**, compiled exactly as a `macrolet`
  body is — `~param` splices a row element, `gensym` is available, and names in
  the expansion resolve at the call site. There is no hygiene, as everywhere else
  in this macro system.
* **`:rest` works** in the parameter list, under the same "second-to-last"
  rule as `defmacro`.
* **The results are spliced in order**, so a template may expand to a statement
  — one that `return`s, `set!`s or breaks out of a loop — and not only to a value.
  That is what `macmap` is for; a table of *values* is better served by `case`
  with `(:or …)`, a `#{…}` set membership test, or an array and a loop.
* **An empty table expands to `(do)`** and emits nothing.
* **The table may be computed** rather than written out, by marking it `~`. See
  [`~e` — a computed macro argument](#e--a-computed-macro-argument).
* **Top-level position works**, so a `macmap` may generate a family of
  definitions. The pre-scan limit on any macro-produced definition applies
  unchanged: they are not forward-referenceable, and the family cannot include
  an `extend` with its methods. See
  [Macros in top-level position](#macros-in-top-level-position).
* **A `macmap` inside a `defmacro` or `macrolet` body is a nested quasiquote**,
  and is compiled as one — the inner `~param` belongs to the inner template. See
  [Nesting levels](#nesting-levels). To share one table across several templates
  the older idiom is still the better one, because it keeps the table in one
  place: pass the template *in* as a parameter, which is not nesting at all — a
  received node is spliced, not walked, so its unquotes survive:

  ```lisp
  (defmacro over-fields (spec)
    `(macmap ~spec ((source-path g-source-path) (src g-src) (pos g-pos))))

  (over-fields ((f g) `(set! (st '~f) ~g)))
  (over-fields ((f g) `(set! ~g (st '~f))))
  ```

* **Diagnostics name `macmap`**, not the `macrolet` it lowers to, via
  [`macro-error`](#macro-error--a-macro-rejecting-its-own-call-site). A row
  whose length disagrees with the parameter count reports at **that row's** own
  line (`macmap: this row's length does not match the template's parameter
  list`); a row that is not a list under a multi-parameter template, and a first
  argument that is not `((param …) template)`, report likewise.

## `~e` — a computed macro argument

A macro's arguments are source text, so a table like `macmap`'s is normally
written out. Prefixing an argument with `~` instead says **evaluate this now**:
the compiler compiles `e` into its compile-time JIT, runs it, and substitutes the
node it returns as if you had typed that node.

```lisp
(defn build-rows ():(ptr Node) (return `((a 1) (b 2) (c 3))))

(macmap ((name arity) `(defn ~name ():i32 (return ~arity))) ~(build-rows))
```

This is the same `~` a macro body already has — "evaluate now" — one level
further out, and it serves every macro at once: `macfoldr`, `case` and the
variadic operators take a computed argument with no change of their own.

**Rules.**

* **`e` must evaluate to a node** — a pointer to `Node` of any kind, which is
  what a quasiquote, `quote`, or a `:&Node`-returning `defn` yields. Anything
  else is refused at the argument's own line:

  ```
  probe.nuc:2: error: the computed argument '~5' must evaluate to &Node, not i32
  ```

* **Only at the top level of a macro argument.** `~` anywhere else — nested
  inside an argument's subforms, a function call's argument, a `defn` body, top
  level — is still `unquote outside quasiquote`. The rule is one sentence on
  purpose.
* **It is one argument, not many.** `~(rows)` passes the whole list as a single
  argument, so a template that wants *N* arguments still has to be given *N* —
  that is what [`~@e`](#e--a-computed-argument-list) is for. Arity is counted
  after the substitution, so `macro 'two': expects 2 args, got 1` is about what
  the macro received.
* **`e` obeys [what a macro body may call](#what-a-macro-body-may-call)** — it
  *is* a macro body, an anonymous one with no parameters. It may call your own
  `defn`s and read your globals, its callees must be defined above the call, and
  under `--target=` a body needing your own code is refused. The diagnostics name
  the argument rather than a macro, because the mistake is at the call:

  ```
  probe.nuc:3: error: the computed argument '~(rows)' calls 'rows', which is defined later in this unit
    note: a computed macro argument may only call functions defined above it — move 'rows' above the call
  ```

* **A `macrolet` binding gets this too**, since both definers compile a body the
  same way.

## `~@e` — a computed argument *list*

`~e` is one argument. `~@e` evaluates `e` the same way and splices the list it
returns in as **separate arguments**, which is what a `:rest` macro wants:

```lisp
(defn nums ():(ptr Node) (return `(1 2 3 4)))

(defn main ():i32 (return (macfoldr _+ 0 ~@(nums))))   ; => 10
```

`macfoldr` sees four arguments, not one list — exactly as if `1 2 3 4` had been
typed. `macfoldl`, the variadic operators, `case` and any `:rest` macro of your
own take it with no change of their own, and it may be mixed with `~` and with
ordinary arguments in one call.

Everything under [`~e`](#e--a-computed-macro-argument) applies unchanged: the
same evaluation, the same "top level of a macro argument only" boundary (`~@`
anywhere else stays `unquote-splice outside quasiquote`), the same rules about
what `e` may call. Two things are its own:

* **The result must be a list** — or null, which splices *nothing*. A node that
  is not a list is refused at the argument's line, and so is a list with a dotted
  tail:

  ```
  probe.nuc:4: error: the computed argument '~@(atom)' must evaluate to a list of nodes
    note: `~@` splices its result in as N arguments, so it must evaluate to a list — `~` substitutes a single node
  ```

* **An empty splice contributes zero arguments**, so a fixed-arity macro then
  reports the count it really got (`macro 'one': expects 1 args, got 0`) rather
  than receiving one empty argument.

## `macro-error` — a macro rejecting its own call site

```
(macro-error NODE MESSAGE)
```

Report `MESSAGE` at `NODE`'s line and abort the expansion, with the same
formatting as any other compiler diagnostic. The point is *where* it lands: at
the call site the macro is objecting to, not at the macro's own definition and
not against whatever the expansion happened to lower to.

```lisp
(defmacro only-ints (x)
  (when (!= (x 'kind) NODE-INT)
    (macro-error x "only-ints: the argument must be an integer literal"))
  `(printf "%d\n" ~x))

(only-ints "nope")
; error: only-ints: the argument must be an integer literal   ← at line of "nope"
```

**Rules.**

* **Only inside a `defmacro`, `macrolet` or `compile-time` body.** Elsewhere it
  is refused (`macro-error: only available inside a defmacro, macrolet or
  compile-time body`) rather than emitted as a call a program could not link.
* **The message is any string value** — a literal, a `StrView`, or a `String`
  (read through its view). Anything else is refused:
  `macro-error: the message must be a string (a StrView or a String), not i32`.
  The prelude brings no string runtime, so a literal is what a macro can say
  with no imports; to *format* one, import the pieces the body calls, exactly
  as a program would:

  ```lisp
  (import-use fmt)    ; str — any ToStr piece: text, integers, Char, bool
  (import-use read)   ; node-str — a node's source text

  (defmacro only-ints (x)
    (when (!= (x 'kind) NODE-INT)
      (let (t:String (node-str x))
        (macro-error x (str "only-ints: got " (string-as-view &t) ", not an integer"))))
    x)

  (only-ints (+ 1 2))
  ; error: only-ints: got (+ 1 2), not an integer
  ```

  A symbol's name is a `ToStr` piece once `intern-str` is imported —
  `(str "m: '" (x 's) "' is reserved")`. `node-str` returns a `String`, which is
  not itself a piece (a by-value `String` would be a move), so pass its
  `string-as-view`. The message is rendered before the expansion is abandoned,
  so a `String` the body built needs no lifetime care.
* **`NODE` is any Node-pointer expression** — ordinarily one of the macro's own
  parameters, or a piece reached through `ast-at`/`ast-first`, which is what
  carries the user's line. A node with no line of its own — a symbol (symbols
  are interned, so no occurrence has a line) or `null` — reports at the line of
  the call being expanded.
* **A message may carry notes.** `\n  note: ` inside the message starts one, as
  in any other diagnostic, and `--diagnostics=sexp` lists it under `notes`.
* **It aborts the expansion**, so nothing after it in the macro body runs. In the
  REPL it returns to the prompt rather than ending the session.
* **Check the shape before you walk it.** `ast-at`/`ast-first` answer `null`
  rather than faulting, and `ast-len` answers 0 for anything that is not a list,
  so `(< (ast-len x) 2)` is the guard — but a *field* read is unchecked, and
  `(x 'kind)` on a null node is a null dereference. Test in a short-circuit
  `or` whose every term is reached only past its own guard, then destructure:

  ```lisp
  (when (or (= spec null) (!= (spec 'kind) NODE-LIST) (!= (ast-len spec) 2))
    (macro-error spec "m: the first argument must be (a b)"))
  ```

  The prelude's `dotimes`, `doseq`, `doseq-iter` and `macmap` guard their
  user-written lists this way, so `(doseq item v (VecIter i32) …)` — the binding
  list unparenthesised — is `doseq: the first argument must be (var coll
  IterType)` at the call's line. A guard is what says *what* was wrong; the
  fault boundary below only says *that* the body crashed.

## When a macro body crashes

A macro body — and a `~e` argument, a `compile-time` block, and the program
globals a macro body reads — runs inside the compiler process. A null
dereference or a stack overflow there is caught: the compiler reports it at the
call's line and exits 1, instead of dying with `SIGSEGV`:

```
t.nuc:7: error: macro 'boom': crashed while expanding
t.nuc:3: error: the computed argument '~(let ...)': crashed while evaluating
t.nuc:3: error: compile-time block: crashed while running
```

The handler (`SIGSEGV` and `SIGBUS`, on its own stack so a runaway recursion
is reported too) is installed only while that code runs, and the previous one
is restored after it. A crash anywhere else in the compiler is not caught.

**In the REPL a crash ends the session**, with the same diagnostic and exit
status 1. The fault may have struck halfway through an allocation, so there is
no known-good state to return to the prompt in. A `macro-error` still returns to
the prompt.

**A null element in the expansion is refused at the call.** Null means *absent*
(`()` is a node), so no source text can put one in a form, and a body that
unquotes a null value — `` `(inc! ~z) `` with `z` null — would hand every consumer
of that form an element it cannot read. The expansion is checked when the macro
returns, and the error names the macro, the position and the list's head:

```
t.nuc:4: error: macro 'bump': the expansion has an empty element at position 1 of (inc! …) -- a value unquoted into it was null
```

An empty `:rest` list is `()`, so passing one on — `(str)` hands its empty
`parts` to `macmap` — is an empty list, not an absent element. In the REPL this
refusal returns to the prompt.

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
    (macrolet ((take (f) `(set! total (+ total (get p '~f)))))
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

* **A binding is not a definer**: `macrolet` may appear wherever an expression
  may, *and* at top level, where its body is a sequence of top-level forms
  rather than a `do` — so the bindings can be used by the definitions they
  scope. The bindings still exist for the body and nowhere else.
* **In expression position the body is a `do`.** Its value is the last form's,
  it introduces no new variable scope, and `let`/`defer` inside it behave as
  they would inside a `do`. At top level there is no `do`: each body form is
  dispatched as a top-level form of its own, so a body of `defn`s is a body of
  `defn`s. A top-level body that expands to no form at all is refused, as any
  top-level macro call with nothing to define is.
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
  `macroexpand` from outside the body. Reader macros (`def-rmacro`) are an
  unrelated mechanism — registered by the reader itself as it reads the file,
  file-scoped and forward-only, with no `macrolet`-style body scope at all.
  See [Reading s-expressions](reading.md#def-rmacro).

A `macrolet` body is compiled and JIT'd exactly as a `defmacro` body is, so it
has the same compile-time requirements — the `Node` type, which the prelude
provides, and the node constructors, which its JIT module resolves against the
compiler process (so neither body needs `(import-use node)`). It works anywhere an expression does,
including inside a loop, inside a `cond` arm, in argument position, inside a
generic template body (compiled once per monomorphization), and inside a
`defmacro` body.

## Macros in top-level position

A macro call can stand where a definition stands, and expands into one:

```lisp
(defmacro defpair (name a b)
  `(defstruct ~name (fst ~a) (snd ~b)))

(defpair IntPair i32 i32)     ; a top-level form
```

Note the list form `(fst ~a)` rather than `fst:~a`: a colon chain is one symbol
token, so an unquote inside it is not seen. This is the same rule
[typed bindings](types.md) follow anywhere a type is computed. The other order
does not help either: `~name:(T)` reads as `(unquote (name (T)))` — the
colon-paren fuse fires on the unquote's operand like on any atom — which
evaluates `(name (T))` as a call at expansion time, so the list form
`(~name (T))` remains the template idiom.

The built-in top-level forms win their own names — expansion is tried only for a
head the compiler does not recognise, so a macro can never change what `defn`
means. An expansion to `(do …)` **splices**: each child is dispatched as a
top-level form of its own, which is how one call defines several things.

```lisp
(defmacro defcounter (name reset)
  `(do (defvar (~name i64) 0)
       (defn ~reset ():void (set! ~name 0))))

(defcounter hits reset-hits)
```

Expansion is re-dispatched, so a macro may expand into another macro call.

[`macrolet`](#macrolet--lexically-scoped-macros) and
[`macmap`](#macmap--one-template-over-a-table-of-rows) stand here too. A
top-level `macrolet` splices its body as top-level forms, so its bindings are in
scope for the definitions it wraps — which is how one table can drive two
functions that must not drift apart:

```lisp
(macrolet ((over-cursor (spec) `(macmap ~spec ((line g-line) (col g-col)))))
  (defn cursor-save (c:&Cursor):void
    (over-cursor ((f g) `(set! (c '~f) ~g))))
  (defn cursor-load (c:&Cursor):void
    (over-cursor ((f g) `(set! ~g (c '~f))))))
```

See [`examples/macmap.nuc`](../examples/macmap.nuc), and `src/repl.nuc`, where
this shape holds the 54-row REPL session roster.

Two limits follow from *when* the expansion happens — during the dispatch loop,
after the pre-scans have already walked the file:

- The macro must be **defined before the call**, in file order. There is no
  pre-scan for macro definitions, so `(import-use …)` for a library's macros
  belongs at the top of the file, where it already is.
- A definition that only a macro produces is invisible to the pre-scans, so it
  is not forward-referenceable: a `defn` produced by an expansion on line 90
  cannot be called from a `defn` written on line 10. Ordinary definition order
  applies to it, not the file-wide visibility the pre-scans give hand-written
  ones. For the same reason a macro cannot produce an `extend` together with
  the methods that satisfy it — the conformance check reads the pre-scanned
  method registry, which the spliced `defn`s are not in, whichever order they
  are spliced in. Write the `extend` by hand, or have the macro produce only
  the methods.

## What a macro body may call

A macro body runs inside the compiler, so a name in it has to mean something
before your program exists. The rule:

> A name in a macro body means what it means in the program — **except** for the
> compile-time runtime, which is the compiler's.

The compile-time runtime is the set a macro body shares with the compiler *by
necessity*, because the compiler allocates, interns and reads the nodes the macro
returns. Concretely, a call resolves to the compiler's own copy when **both** of
these hold: the callee's defining file is under the library root this compilation
resolved `lib/prelude.nuc` through, **and** the compiler binary exports that
symbol. `alloc-node`, `node-int`, `intern-symbol` and the list API
(`node-first`, `node-rest`, `node-at`, `node-len`, `node-list-new`, `node-push`,
`node-extend`) are this set.

Everything else — your own `defn`s, and a `lib/` module the compiler does not
itself link — resolves to **your** definition, which the compiler JIT-compiles on
demand into a private *compile-time mirror* module. So:

```lisp
(defn double (n:i32):i32 (_* n 2))
(defmacro twice (x) `(_+ ~x ~x))          ; needs nothing
(defmacro four () (mk-int (as i64 (double 2))))   ; calls your `double`
```

Five consequences worth knowing:

- **A macro body may call a helper, and that helper may recurse.** A macro that
  names *itself* in head position is still a macro call, but a tree walk written
  as an ordinary recursive `defn` and called from the body works.
- **A callee must be defined above the macro**, in file order — the same rule the
  macro itself follows. A `defn` written below the `defmacro` is not yet emitted
  when the body is compiled, and the compiler says so:

  ```
  probe.nuc:1: error: macro 'probe' calls 'helper', which is defined later in this unit
    note: a macro body may only call functions defined above it — move 'helper' above the macro
  ```

  A `(compile-time …)` block gets the same message naming the block. A callee
  whose definition the compiler recorded no IR span for gets its own error
  rather than a link failure.
- **A macro body may read your program's globals**, directly or through a helper,
  and a global whose initializer is not a compile-time constant has already run
  its initializer by the time the body sees it:

  ```lisp
  (defn seed ():i32 (return 21))
  (defvar g-limit:i32 (_* (seed) 2))          ; a run-time initializer
  (defmacro capped (x) (if (= g-limit 42) `(min ~x 42) `~x))
  ```

  The global is one copy, shared by every macro in the compilation, and writing
  to it from a macro body is visible to the next one. It is *not* the same
  storage your program uses at run time — the compiler's copy lives in the JIT —
  so a compile-time write does not survive into the built program, and the
  program's own startup initialization happens as usual.
- **A name of yours that collides with one of the compiler's** — a `defn` or a
  `defvar` global — now means *yours*. It used to mean the compiler's, silently,
  and with a mismatched signature that crashed the compiler. The compiler warns
  once per collision; see [`--warn-ct-shadow`](compiler.md#compiler-flags).
- **Under `--target=`, a body that needs your own code is refused.** See below.

### ⚠ Sharp edge: cross-compiling a macro body

A macro body runs *here*, in the compiler's own process. Your program's
definitions, though, were lowered for the machine `--target=` names — different
register classes, different struct conventions, a different pointer size — so the
compiler cannot run them. When a body would need one, it says so rather than
running wrong-ABI code:

```
probe.nuc:3: error: macro 'xt' needs the program's own 'xt-helper' at compile time,
  and the program is lowered for 'avr' while a macro body runs on the host,
  'x86_64-pc-linux-gnu'
  note: when cross-compiling, a compile-time body may call only the compiler's own
  library — move 'xt-helper' there, or compute the value without it
```

Only that case is refused. A body calling nothing but the compile-time runtime —
which is every macro in `lib/`, and so every macro the AVR and RISC-V examples
use — cross-compiles exactly as before.

### ⚠ Sharp edge: which `lib/` counts as the compiler's

The first condition is a **path prefix** against the directory *this compilation*
resolved `lib/prelude.nuc` through, and the import search has five steps — the
source file's directory, `lib/` relative to the **current directory**, each `-I`,
`$NUCLEUS_LIB`, then the installed `/usr/local/share/nucleus/lib/`. A development
build finds its library at step 2; an installed one at step 5. Five consequences:

1. **A cwd-relative `lib/` can capture the root.** Run a program from a directory
   that has its own `lib/prelude.nuc` and *that* becomes the root, so every module
   beside it counts as compile-time runtime. A project with its own `lib/node.nuc`
   then gets the **compiler's** `node-at` at compile time. This one is not warned
   about: in a checkout of the compiler the cwd-relative `lib/` genuinely *is* the
   compiler's, and the two cases are indistinguishable from the path alone.
2. **Inside a compiler checkout the root is that checkout's `lib/`**, which is not
   what an installed compiler gives. A test that pins this behaviour has to name
   the root rather than inherit the current directory.
3. **Editing a `lib/` file changes nothing until the compiler is rebuilt.** The
   second condition asks the *running* binary, so a modified `lib/node.nuc` still
   binds to the compiler's old `node-at` at compile time. At compile time, library
   code is the compiler's build of it.
4. **`-I` and `$NUCLEUS_LIB` can name a library the compiler was not built from.**
   The root is then that one while the second condition still answers from the
   running binary, so the two can disagree about what a module contains. Nothing
   unsafe follows — a symbol either exists in the compiler or it does not — but
   `-I` over the standard library is unsupported for compile-time purposes.
5. **The comparison is on path spelling.** A symlinked or `..`-containing path may
   not prefix-match a root it is genuinely under. The failure direction is safe: a
   spelling mismatch makes the module *yours*, which mirrors — slower and more
   isolated, never a wrong function.

A program that suppresses the automatic prelude has no root at all, so every one
of its `defn`s is its own. That is the safe direction and needs no special case.

## Nesting levels

A backtick opens a level; `~` and `~@` close one. **Only a level-1 unquote is
code.** Deeper, an unquote is data — rebuilt with its level lowered by one — so
an inner template's `~param` survives the outer expansion and fires at the inner
one. This is what lets a macro write a macro.

| form, seen at level L | L = 1 | L > 1 |
|---|---|---|
| `` `X `` | data, and X is walked at L+1 | data, X walked at L+1 |
| `~X`, form position | **evaluate X** (must yield a `Node*`) | data, X walked at L−1 |
| `~@X`, list element | **splice X's value** | data element, X walked at L−1 |
| `~@X`, form position | `error: unquote-splice outside list` | data, X walked at L−1 |
| anything else | walked unchanged | walked unchanged |

A quasiquote reached *through* an unquote is a fresh outermost one and starts at
level 1 again.

```lisp
(defmacro def-adder (name k)
  `(defmacro ~name (v) `(+ ~v ~'~k)))

(def-adder add5 5)
(add5 100)                ; 105
```

`~name` is level 1 and fires now. `~v` is level 2, so it is data here and
belongs to `add5`.

**`~'~x` is how an outer argument reaches an inner template**, and is the
spelling to learn. The outer `~x` yields the node the caller passed, `'` makes
the inner template hold it as a literal, and the inner `~` reads it back.
`~@'~xs` is its splicing counterpart, for a `:rest` list. A bare `~~x` lowers
correctly too, but it means *evaluate `x` at the inner expansion*, where the
outer macro's parameters no longer exist — so it is almost never what you want.
The bare `~` that reads an outer value is a mistake the levels make visible:

```lisp
`(defmacro ~name (v) `(+ ~v ~k))      ; `k` is add5's, and add5 has no `k`
```

An unquote with no enclosing quasiquote is an error (`unquote outside
quasiquote`). Inside a plain `quote` it is ordinary data: `'(a ~b)` is a
two-element list.

**A level-1 operand that is not node-typed is refused at its own line.** The
same rule as a [computed macro argument](#e--a-computed-macro-argument) — `~` and `~@`
substitute source, so the operand must be a pointer to `Node`, which is what a
quasiquote, `quote`, [`node-int`](#interpolating-a-computed-number), or a
`:&Node`-returning `defn` yields:

```
probe.nuc:3: error: the unquote operand '~n' must evaluate to &Node, not i32
  note: `~` substitutes its value as source, so it must evaluate to a node — what a quasiquote, `quote`, `node-int` or a ':&Node' function yields
```

`~@` gets the same message with its own marker (`'~@n'`) and note (`` `~@`
splices its value in as source ``).

**A macro body's own value is held to the same rule**, whether or not an
unquote is what produced it — `(defmacro m () 5)` is
`macro 'm' must evaluate to &Node, not i32`, at the body form's line.

### Interpolating a computed number

`~n` where `n` is an `i32` is the mistake the rule above exists to catch, so
interpolating a number a macro *computed* needs a node for it. `(import-use
node)` supplies one:

```lisp
(import-use node)

(defmacro double ()
  (let (n:i32 21)
    `(_* ~(node-int n) 2)))       ; => 42
```

`node-int` takes an `i64` (an `i32` widens at the call) and yields a fresh
`NODE-INT` with no line, so diagnostics about it fall back to the enclosing
form's line — the same treatment `node-line` gives any synthesized node. It is
the natural way to write the producer for a spliced argument list:

```lisp
(defn range-nodes ():?&Node
  (let (acc:?&Node null
        i:i64 4)
    (while (> i 0)
      (set! acc (node-cons (node-int i) acc 0))
      (set! i (- i 1)))
    (return acc)))

(defn main ():i32 (return (macfoldr _+ 0 ~@(range-nodes))))   ; => 10
```

## A form is a collection

A list `Node` is a **header over an array of elements** — `elems`, with `len` of
`cap` used — rather than a chain of cons cells, so it has an identity of its own.
Three things follow.

**`()` is a value, not `null`.** The empty list is a length-0 `NODE-LIST`, so
`'(a () b)` really has three elements and the middle one is a list you can ask
`count` of. `null` keeps exactly one meaning — *absent* — which is what an
out-of-range `node-at` or a missing operand answers. The rule when walking a
form is therefore **never compare a list to `null` to mean "empty"; ask
`node-len`** (or `ast-len` in a macro body). `node-empty?` answers yes to both,
and is what a definer asks to refuse `()` where a name belongs.

**`Node` conforms to `Coll` and `Seq`.** A form answers the same protocol
surface a `Vector` does, with `(ref Node)` as the element type:

```lisp
(import-use node)
(import-use coll)
(import-use iterator)

(let (xs:&Node (unsafe/cast &Node `(10 20 30))
      i1:usize 1)
  (count xs)              ; 3
  (xs i1)                 ; the node `20` — Seq's `invoke`
  (xs 'kind)              ; NODE-LIST — a field, not an index
  (conj xs (node-int 40))
  (insert xs i1 (node-int 15))
  (doseq (e xs NodeIter)
    (printf " %ld" (e 'i))))
```

`(xs i)` indexes and `(xs 'kind)` reads a field because a **literal selector
that names a field wins over the index method** — see
[Callable values](special-forms.md#callable-values-non-function-call-position).
`iter` yields a `NodeIter`, which is a *view*: the list must outlive it.
`examples/node-coll.nuc` runs the whole surface, `into` both ways included.

**`node-rest` is an O(1) view that copies before it diverges.** It shares the
parent's array (`cap` 0) and reallocates on its first push, so appending to a
rest cannot overwrite the element after it in the parent.

The builders are `node-list-new` / `node-push` / `node-extend` /
`node-list-done` (the last is the identity — a builder *is* a finished list),
with `node-cons` and the fixed-arity `node-list1`…`node-list5` over them, and
`node-set-at` / `node-splice-at` for in-place edits. All of them come from
`(import-use node)`.

## The type of a quoted form

`'x` yields a `Node*`, but **which** pointer type depends on what was quoted:

| Quoted | Type | Why |
|---|---|---|
| a symbol — `'foo` | `(ref Node)` | Lowers to `intern-symbol`, whose signature returns `ref:Node`. One canonical node per spelling, so the value is non-null *and* an identity. |
| anything else — `'(a b)`, `'1`, `'()` | `(ptr Node)` | Built by `node-list-new`/`node-push`/`alloc-node`. `'()` is a length-0 list, **not** null — see [A form is a collection](#a-form-is-a-collection). |

The distinction is load-bearing, not cosmetic: because `'foo` is non-null and
interned, symbols work directly as collection elements and keys — see
[Symbols as keys](collections.md#symbols-as-keys). A quoted symbol still fits a
`(ptr Node)` slot (non-null widens into unchecked), so nothing written before
this rule needs changing.

`quasiquote` stays `(ptr Node)` throughout: an unquote can inject any *node*,
including a null one, so its result type is expansion-dependent.

**In ordinary code a quote is a run-time call**, so a program that writes one
needs `(import-use node)` — the prelude registers the `Node` type but no longer
emits the constructors. Inside a `defmacro`/`macrolet`/`compile-time` body it
needs nothing: that body is a JIT module resolved against the compiler process.
See [The node runtime is a library](toplevel.md#the-node-runtime-is-a-library).

## Macros and pass-through arguments

Macro parameters are typed `&Node` — the macro sees AST. An argument is never
null: the arity is checked before expansion and an empty `:rest` list is `()`.
So a parameter binds to any `&Node` slot, a test like `(when p …)` is refused
as always true, and a macro can walk the argument's structure **without
casting**. Read a list with the `ast-*` special forms — `(ast-len p)`,
`(ast-at p 1)`, `(ast-first p)`, `(ast-rest p)` — each of which yields
`(ptr Node)` (an `i32` for `ast-len`), because a read past the end is null, and
so chains:
`(ast-first (ast-at p 1))`. Use `(p 'kind)` / `(p 's)` / `(p 'i)` / `(p 'line)`
for the `Node` fields; the selector is **quoted**, because a bare symbol in that
position is an ordinary variable reference (see
[Member access](special-forms.md#member-access)).

Why special forms rather than calls to `node-at`/`node-len`: a macro body is
compiled from *your* program's prelude but is handed the *running compiler's*
nodes, so a body that reads the layout directly would break the moment the two
disagree. An `ast-*` form is lowered by whichever compiler is running, so it
always matches that compiler's own `Node`
(design/stage21-cleanup/ast-as-collection.md §8.2).

When the macro splices a parameter into its expansion via `~param`, the
resulting form is compiled as if the user had written that expression directly
at the call site, so the *value* type the parameter evaluates to in the
expansion is whatever the user wrote — `i32`, `ptr:i8`, `f64`, `Foo`, etc.

This means a single macro can take, inspect, and splice arguments of different
value types — there is no value-level `T` to keep consistent across calls;
only the AST representation is uniform.

```lisp
; Pick a printf format from the literal kind, then splice the original
; expression in. The macro inspects (get x 'kind) at expansion time; the
; spliced ~x is compiled at the call site with whatever type it has.
(defmacro tprint (x)
  (cond (= (get x 'kind) NODE-INT) `(printf "%d\n" ~x)
        (= (get x 'kind) NODE-STR) `(printf "%s\n" ~x)
        (= (get x 'kind) NODE-FLOAT) `(printf "%f\n" ~x)
        true                    `(printf "%p\n" ~x)))

(tprint 42)        ; → (printf "%d\n" 42)        — i32 at the call site
(tprint "hi")      ; → (printf "%s\n" "hi")      — ptr:i8 at the call site
(tprint 3.14)      ; → (printf "%f\n" 3.14)      — f64 at the call site
(tprint some-ptr)  ; → (printf "%p\n" some-ptr)  — ptr at the call site
```

Inside the macro `x` is `&Node`; the spliced `~x` carries no type
constraint into the expansion. The host compiler types the resulting form
using its normal rules.

### ⚠ Sharp edge: `cond`/`if` branches of genuinely different element types collapse to void

A `cond`/`if` is a *value* expression whose result type is the **join** of its
branches. Two pointer branches with different *element* types — `(ptr Node)`
vs `ptr:i32`, or two different struct types — do not unify, and the whole
expression collapses to `void`. That failure then surfaces as:

- a `let`/`with`/`set!`/`return` reporting a type mismatch whose value names
  the branches: `value is either CStr (line 7) or String (line 8)`, or
  `value is void (the branch at line 6 has no value)` when one branch has no
  value (a symbol branch carries no line, so it shows its type alone), and
- a macro whose entire body is such a `cond` reporting
  `macro '<name>' must evaluate to &Node, not void`, at the body form's
  own line.

This is a genuine type error; there's no shortcut but making the branches
agree on element type.

(The unlocated `macro '<name>': returned null` this used to surface as is now
reachable only from a macro whose value is node-*typed* and null at run time —
a body ending in `'()`, say — never from a type mistake.)

Mixing a **typed** pointer branch (`(ptr Node)`, `&Foo`, `?&Foo`, ...)
with a **bare, elem-less** `ptr` branch is *not* a collapse case — the join
absorbs the bare side into the typed side's element type, producing
`(ptr ElemType)`, with no cast required. This matters constantly in macro
bodies: quasiquote (`` `(...) ``), `(gensym)`, the `null` literal, an `ast-*`
read and a macro parameter all join freely:

```lisp
; joins to (ptr Node) automatically — no cast needed
(let (rest (if (= (n 'kind) NODE-LIST) (ast-rest n) null)) ...)

; A variadic-operator macro: the single-arg branch returns the element node,
; the others are quasiquoted forms — both join to (ptr Node).
(defmacro * (:rest args)
  (cond (= (ast-len args) 0)
          `1
        (= (ast-len args) 1)
          (ast-at args 0)
        true
          `(_* ~(ast-at args 0)
                (* ~@(ast-rest args)))))
```

Pointer *kind* (unchecked, `?`, `&`) is never itself a source of collapse —
kinds meet (unchecked ⊔ anything = unchecked) rather than needing to match.
Only a genuine element-type mismatch collapses the join to `void`.

Separately: a `(ptr Node)` value flows freely into a bare `:ptr` or a `?&Node`
local, but a non-null `&Node` parameter, `return`, or binding still **rejects**
it (`unchecked pointer where non-null (ref ...) is required`). Launder with
`(as-ref …)` and narrow, or bind to a `?&Node` and narrow, when an `ast-*` read
meets a `&Node` slot.
