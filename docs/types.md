# Type System

## Type Syntax and Desugar

Types are attached to names with `:` syntax: `name:type` (e.g., `x:i32`, `main:int`). A desugar pass runs before compilation, splitting colon-typed symbols in binding positions into canonical list form:

- `foo:int` → `(foo int)` — name and type as separate symbols
- `node:&Node` → `(node (ref Node))` — a non-null pointer to Node; `&` is sugar for `ref:` (see [Pointer kinds](#pointer-kinds-t-t-and-ptr-t))
- `pp:&&Node` → `(pp (ref (ref Node)))` — pointer-to-pointer-to-Node
- `node:ptr:Node` → `(node (ptr Node))` — an *unchecked* pointer to Node

A typed pointer is normally `&T` (non-null) or `?&T` (nullable, checked). `(ptr T)` is the unchecked pointer, and `(ptr ptr T)` chains. Bare `ptr` (with no element) is the opaque, unchecked `void*` — the type of `null` and of an imported C pointer.

Because bare `ptr` erases the element type, operations that need one (`aref`, `deref`, `unsafe/ptr+`, a `set!` place, field access) reject it. The one place the element type is recovered automatically is an **`(array T …)` initializer**: `(let (a:ptr (array i32 1 2 3)) (aref a 1))` binds `a` as `ptr:i32`, because the element type is spelled in the initializer itself. This is deliberately limited to that syntactic form — a bare `:ptr` bound from anything else (a function result, `alloca`, `&x`) stays elem-less, since erasing the element type is exactly what a `void*` annotation is for. Where you want the element type from any other initializer, either spell it (`a:ptr:i32`) or omit the annotation entirely (a bare binding name adopts the initializer's full type).

In inline type positions (the type argument of `as`/`unsafe/cast`, `sizeof`, `alloca`), either the canonical list form or the colon sugar works: `(unsafe/cast (ptr Node) x)` and `(unsafe/cast ptr:Node x)` are equivalent.

**In value position, `name:type` is an `as` cast.** `baz:CStr` means `(as CStr baz)` — so the same annotation spelling declares a type in a binding position, *names* a type in a type position, and *converts* in a value position, chosen by where it appears:

```nucleus
(let (a:i32 0                  ; declaration — a is an i32
      b:i64 x:i64)             ; declaration of b; x:i64 is a cast of x
  (take-cstr s:CStr)           ; cast — (as CStr s)
  (set! (aref p (as i64 i)) v))      ; ptr:… inside `as` is a TYPE, not a cast
```

In a binding list the two readings alternate, as above: the name slot declares, the initializer slot casts.

The conversion is exactly `as` (see [Implicit Type Coercion](#implicit-type-coercion) and the `as` form): widening is free, a narrowing or a reinterpretation is refused and routed to `unsafe/cast`, the pointer-kind flow rule applies (`p:ref:T` on an unchecked `ptr` is a laundering error, not a silent promotion), and a `defcast` rule extends the set. There is deliberately **no** sugar for `unsafe/cast`: the short spelling is the safe one.

Three limits follow from the spelling rather than the rule:

- **It attaches to a name.** A computed operand has nowhere to hang the colon — `(f x):CStr` lexes `:CStr` as a keyword — so spell those `(as CStr (f x))`.
- **A parenthesised type is not a cast.** `q:(ref Rec)` in value position is claimed by the colon-paren fuse below and reads as the *call* `(q (ref Rec))`; the compiler says so. Give the type a name with [`deftype`](#type-aliases--deftype) and the annotation works: `q:RecRef`.
- **`null`, `true`, `false` and `none` take no annotation** — they are matched by name before the split, so `null:ptr:T` is an undefined name. Write `(as ptr:T null)`.

An annotation whose type does not exist is an error (`unknown type 'Foo' in the annotation 'x:Foo'`); it is not ignored.

Selector position used to be a special case here — `(m k)` named a *field* and `(m k:CStr)` was the annotation hatch that forced the value reading. Stage 16 retired both: a **quoted** `(m 'k)` is the field and a bare `(m k)` is the ordinary variable, so the annotation means in selector position exactly what it means anywhere else. See [callable values](special-forms.md#callable-values-non-function-call-position).

**Colon-paren binding sugar.** A binding's type may also be a parenthesised form written directly after the colon, with no space: `name:(ref (Vector T))`, `v:(ptr u8)`, `f:(fn i32)(i32 i32)`. The reader fuses an atom whose final chain segment is **open** and that is *immediately* followed by `(` into the canonical list node `(name <paren-form>)`. So `v:(ref (Vector i32))` is exactly `(v (ref (Vector i32)))`, in both parameter lists and `let` bindings. A segment is open at the start of the atom and after each `:`, and a run of the `?`/`!` sigils keeps it open; any other character closes it. So `x:`, `x:?`, `x:!`, `?`, `?!`, `ptr:` and `x:&?` (which is `x:ref:?`) fuse, while `foo?`, `push!`, `!=` and `x:foo?` do not — their last segment closed before the sigil — and a mid-colon symbol such as `foo:i32` is unaffected. The very next character must be `(` (no whitespace).

**The fuse fires per atom, wherever an atom is read** — not only for the elements of a list. A reader-macro operand fuses (`&?(V)` reads as `(ref (? (V)))`, `&ptr:(V)` as `(ref (ptr (V)))`, `'x:(T)` as `(quote (x (T)))`, `~x:(T)` as `(unquote (x (T)))`), an element of a `[…]`/`{…}`/`#{…}` literal fuses (`[x:(T)]` is `(vector-lit (x (T)))`), and a top-level `foo:(bar)` is one form. The synthesized node carries the atom's own line.

**Sigil-paren forms.** A trailing sigil run is a segment of its own, so the `?`/`!` sigils compose with a parenthesised type the way `ref:` does: `x:?(Vector i32)` reads as `(x (? (Vector i32)))`, `x:!(V)` as `(x (! (V)))`, `?!(V)` as `(?! (V))`, `x:&?(V)` as `(x (ref (? (V))))`, and a bare `?(V)` as `(? (V))`; in return position `):?(V)` reads as `(? (V))`. (`x:?&(V)` is `x:?ref:` and reads as `(x (?ref (V)))`, as before.) The reader is type-ignorant here exactly as it is for `ref` — `(? X)` is a shape — and the type parser gives it its meaning: **a bare-sigil head is the canonical list form of the sigil**, so `(? X)` is exactly `?X`, `(! X)` is `!X`, `(?! X)` is `?!X`, and `X` may be any type form. It takes exactly one operand (`(? A B)` and `(?)` are refused: `'?' takes one type -- (? T)`). Because the list form is the canonical node, `--emit-nuch` prints an exported `x:?(Vector i32)` parameter as `(x (? (Vector i32)))`, which re-reads to itself. Every position accepts it — parameter, return, `let`/`with`, `defstruct` field, `deftype`, `defvar`, `sizeof`, `alloca`, `as`, a protocol signature, a lambda, a template argument (`(Vector ?(Vector i32))`).

**Sigil near-miss.** A sigil binds tight, like `:`. `? (Vector i32)` written with a space is a bare `?` atom followed by a dangling list, and the bare atom is refused wherever it reaches the type parser: `a type sigil must be attached to its type -- write ?T or ?(T ...) with no space` (naming the sigil as written — `!`, `?!`), at the line of the form that holds it.

**Function-pointer types take a second, adjacent group.** A function pointer type is *two* parenthesised groups — `(fn ret)` and its parameter list — so the colon-paren fuse absorbs one more group when the first is `(fn …)`-headed **and the next character is `(` with no space**: `f:(fn i32)(i32 i32)` reads as `(f ((fn i32) (i32 i32)))`, and `acv:(fn void)()` (the zero-parameter case) as `(acv ((fn void) ()))`. Adjacency is required, exactly as for the first group — a *space*-separated second group is genuinely ambiguous with the next binding in the enclosing list (in `(f:(fn i32) (i32 i32) a:i32)` nothing distinguishes the parameter list from a `(name type)` binding), so it is not absorbed and `f` would be typed as a zero-parameter function pointer. `name:(fn ret)` with no following group is a *zero-parameter* function pointer, which is well-defined and useful (C's `ret (*)(void)`); it is only a mistake when you meant to give it parameters.

The corollary, since absorption is driven purely by adjacency: **put a space between a `(fn ret)` type and a parenthesised initializer.** `(let (f:(fn i32) (choose)) …)` binds `f` to the result of `(choose)`; written without the space, `(choose)` is absorbed as the type's parameter list and the binding list is left with an odd element count (a located `let: binding list must be even`). This is the same discipline the first group already requires — an adjacent `(` after a trailing colon always belongs to the type.

**Colon-chain fuse.** A colon chain ending in a paren also works: `name:k1:…:kN:(T …)` reads as `(name (k1 (… (kN (T …)))))`. The first segment is the binding name; each remaining segment wraps the paren form right-to-left as a unary constructor application — e.g. `v:ref:(Vector i32)` → `(v (ref (Vector i32)))`, `p:ptr:ptr:(fn i32)` → `(p (ptr (ptr (fn i32))))`. (The reader does not validate that segments are pointer-kind constructors — `a:Foo:(T)` fuses to `(a (Foo (T)))` and the type parser rejects the unknown segment naturally. An empty interior segment `a::(T)` is a reader error.) This applies to a parametric *return* type on a `defn` name too: `make-vec:ref:(Vector ptr)` reads as `(make-vec (ref (Vector ptr)))`. Either the colon-chain sugar or the canonical list form works in every binding position.

**Container types in a chain, and where the chain stops.** A pointer-kind segment absorbs its *whole* remaining tail as one type, so a template application needs no parens at all when every type argument is a single token: `m:ref:HashMap:CStr:i32` is `(m (ref (HashMap CStr i32)))`, and `v:ref:Vector:i32` is `(v (ref (Vector i32)))`.

That flat absorption is also the limit. **A type argument may not itself be a chain**, because nothing in a flat tail says where one argument ends and the next begins. Parenthesise the inner type instead:

```lisp
v:ref:(Vector (ref Node))                  ; correct
v:ref:Vector:ref:Node                      ; error
m:ref:(HashMap CStr (ref (Vector i32)))    ; correct
m:ref:HashMap:CStr:ref:Vector:i32          ; error
```

Both mistakes are reported at the declaration. A pointer kind in argument position names itself — `Vector: 'ref' is a pointer kind, not a type argument -- a colon chain cannot nest, so parenthesize the inner type: ref:(Vector (ref X))`. A chain that merely overshoots the template's arity reports `Vector: wrong number of type arguments for defstruct template (2 given)`; `v:ref:Vector:ptr:i8` lands here rather than in the message above because bare `ptr` *is* a type (the opaque `void*`) and is consumed as an argument, where bare `ref` is not a type at all.

For a container type you write more than once, prefer naming it with [`deftype`](#type-aliases--deftype) — `v:ref:NodeVec`, or `v:NodeVec` with the pointer kind inside the alias. An alias removes the type expression from the declaration rather than compressing its punctuation, and a single-token type name needs no fuse at all.

**Return-position lone-colon fuse.** A bare `:` immediately before `(` fuses to the paren form itself, with no name, so a parenthesised return type in `fn`/`defn`/lambda position may be written `):(T …)`. Thus `(fn (x:i32):(ref T) …)` reads as `(fn (x:i32) (ref T) …)`, and a keyword whose body is open, followed by `(`, fuses too (`:ptr:(Vector T)` → `(ptr (Vector T))`, `:?(Vector T)` → `(? (Vector T))`). This makes parenthesised returns use the same colon discipline as scalar returns — no space-separated exception is required.

**Whitespace near-miss.** Adjacency remains **required**: the sigil binds tight (matching `:keyword` lexing; fusing across whitespace could rewrite quoted data at a distance). If a binding name ends in `:` but is *not* adjacent to `(` — e.g. `x: (ptr Node)` — the compiler reports a clear fatal error: `binding name ends in ':' (<atom>) -- write name:(Type) with no space, or (name Type)`. Write `name:(Type …)` with no space, or the canonical list form `(name Type …)`. A trailing-colon symbol in value or quoted positions stays legal.

**Quoted-data caveat.** The fuse fires syntactically, whether or not the form is quoted — so `'(foo:(bar))` reads as `'((foo (bar)))`, and the quote's own operand is no exception: `'foo:(bar)` is `(quote (foo (bar)))`. Authors of quoted data (or data that will be `read` at runtime) should space the paren: `'(foo: (bar))` or `'(foo (bar))`.

Desugar operates on binding positions in `defn`, `defvar`, `defstruct`, `extern`, `declare`, and `let`. Expression bodies are not desugared; typed symbols in value position (e.g., from macro expansion) are handled by the compiler directly.

Both the sugared `:` syntax and the canonical list form are accepted in all binding positions. Macros that manipulate types can work with the canonical list form; macros that don't care about types can use the `:` sugar and it will be desugared before compilation.

**Multi-binding `let`.** A single `let` accepts any number of name/init pairs in one flat binding list — both `:` sugar and list forms compose freely in the same binding list:

```lisp
(let ((a (ref AllocHandle)) (alloca AllocHandle)
      (v (ref (Vector i32))) (alloca (Vector i32))
      n:i32 7)
  ...)
```

The bindings are established in order (left to right); each init expression may reference names introduced earlier in the same list.

Macro output is desugared before compilation, so macro-generated code can use either form.

## Namespaced type names

**A `defstruct`, `defunion`, `defenum` or struct/union template defined inside `(ns n)` is keyed `n/Type`**, exactly like a `defn` or `defvar` declared there — see [`ns`](toplevel.md) and [What an import brings into scope](toplevel.md#what-an-import-brings-into-scope). Two namespaces may each define a type of the same name; they are two distinct types. Type identity (what `type-eq` checks for a struct or union) compares the underlying `StructDef`/`UnionDef` by pointer, so `(ns a) (defstruct Vector …)` and `(ns b) (defstruct Vector …)` are unrelated even when their field lists happen to match: distinct layouts, distinct field-access diagnostics (`no field 'c' on struct 'a/Vector'`), and distinct protocol conformances — extending `a/Vector` does not extend `b/Vector`.

A type reference resolves through the writing file's own import environment exactly like any other name, per the table in [What an import brings into scope](toplevel.md#what-an-import-brings-into-scope): `(import-prefixed lib p)` makes the type spellable as `p/Type` and (as every import does) by its full name `<lib-namespace>/Type`; `(import-use lib)` makes it spellable both bare and as `<lib-namespace>/Type`; `(require lib)` makes it spellable as `<lib-namespace>/Type` only; a file's own `(ns n)` makes it spellable both bare and as `n/Type`. The prelude, every un-namespaced library, and every C-header type are always reachable bare — they live in `user`, which every namespaced file can still see unqualified.

A qualifier that names no namespace in scope is refused rather than silently resolved — a mistyped or bogus prefix used to resolve to whatever type had that bare name, from any namespace, which is no longer true:

```lisp
(defstruct Cat n:i32)
(defn take ((c (ref nope/Cat))):i32 (return (_get c 'n)))
```

```
demo.nuc:2: error: unknown type: nope/Cat — 'nope' is not in scope in this file
  note: 'nope' is neither an import prefix this file binds nor a namespace its
  imports load — (require …) a library to reach its namespace by its full name.
  This file has no import qualifiers in scope.
```

A **bare** reference to a type that genuinely is defined in the compilation unit, but under a namespace this file never imported, gets a diagnostic that names the defining namespace rather than claiming the type does not exist anywhere — and, when this file has bound some prefix that reaches that namespace, a note offering the spelling it can actually write:

```
main.nuc:18: error: unknown type: Fox — defined in namespace 'dp'
  note: write 'dpx/Fox' here
```

If the file has bound nothing for that namespace, the message ends `— defined in namespace 'dp', which this file does not import` instead of offering a spelling. The same check fires in head position too, so a bare struct constructor (`(Fox 9)`) for a type in an unimported namespace gets the identical answer — this is not only an annotation-position rule.

**A parametric spelling gets the same answers.** `(Vector i32)`, `(Result i64 i32)` and any other `(Template Arg …)` type resolve their head through the same ladder, so an unimported template names the file that defines it:

```
demo.nuc:1: error: unknown type: Vector — not defined anywhere in this compilation unit
  note: 'Vector' is defined in lib/nucleus/vector.nuch, which no import in this unit reaches
```

Writing a type where a type *constructor* belongs is a distinct error, since the head is a real type. The usual way to reach it is a doubled annotation — `x:i32:i32` means `(i32 i32)`:

```
demo.nuc:1: error: 'i32' is a type, not a type constructor -- (i32 ...) is not a type; a doubled annotation like x:T:T desugars to exactly this
```

**The emitted LLVM type name composes the namespace's IR prefix**, the same `<prefix>__<name>` composition a namespaced function or global already uses: a type declared in `(ns dp)` emits `%dp__Fox`, overridable with [`set-ir-prefix`](toplevel.md) exactly as for functions. A mangled overload token composes the same name, so an overloaded method on `dp/Fox` appears as `@f.dp__Fox` in a symbol. In the default `user` namespace nothing changes — `%Fox`, byte-identical to before namespaces existed. A core library's type composes the reserved `nuc_` prefix with no separator (`%nuc_String`), and so does every mangled token that names it (`@f.pnuc_String`); see [The core libraries](toplevel.md#the-core-libraries-nucleus).

`--emit-cheader` composes the same prefix into the emitted C `typedef` name, for the same collision reason: two namespaces' `Pt` would otherwise both emit `typedef struct {…} Pt;`, and a program that includes both headers would fail to compile. A struct declared in `(ns gt)` emits `} gt__Pt;` in place of `} Pt;`; a `user`-namespace struct's header is unaffected. See [`--emit-cheader`](compiler.md#compiler-flags).

## Type aliases — `deftype`

`(deftype Name Type)` gives a type a second **spelling**. It is not a new type:
the alias and the type it names are the same type everywhere — same identity
under `type-eq`, same stamped instance, same mangled name, and *one* overload
for dispatch, not two. A program written with aliases emits byte-identical IR
to the same program with the types spelled out.

```lisp
(deftype SymTab  (ref (HashMap CStr i32)))
(deftype NameSet (ref (HashSet CStr)))
(deftype Count   i64)
```

The point is the use sites. A one-token type name is what the colon annotation
is best at, so an alias replaces the whole wrapper in every declaration
position — parameter, return, `defstruct` field, `defvar` name, `let`, `with`:

```lisp
(defstruct Reg tbl:SymTab names:NameSet)
(defvar g-special-form-set:NameSet (build-special-form-set))
(defn tally (m:SymTab):Count (return (as Count (count m))))
(defn main ():i32
  (with (m:SymTab (alloca (HashMap CStr i32)))
    (hashmap-init m)
    (printf "%ld\n" (tally m)))
  (return 0))
```

The body is an ordinary type expression, so the colon-paren sugar works inside
it and an alias may name another alias:

```lisp
(deftype IntVec ref:(Vector i32))    ; colon-paren sugar in the body
(deftype Tally  Count)               ; alias of an alias
```

Everything else composes without special cases — the `?`/`!` sigils (`?PtRef`),
pointer-kind chains (`ref:P`), template arguments (`(ref (Vector Count))`), and
a **forward reference** (the body is re-parsed on use, so an alias may be
declared below the signature that names it). The body is also checked where it
is written, after every file's types are known, so `(deftype A (Vector Nope))` is
`unknown type: Nope` at its line even if nothing uses `A`; whether an
`(array T N)` body is storage is decided at each use.

**`deftype-`** is the private variant, like `defstruct-`/`defunion-`. Privacy is
per *namespace*: a private alias is invisible to a consumer outside the
namespace that declared it, and is not written into the `.nuch` header. A public
`deftype` **is** written to the header, because an exported signature may name
it.

**A colliding alias is refused**, not silently ignored. An alias name that
already names a built-in type, a struct, a struct or union template, an
enumeration, or a **C typedef an import brought in** would never resolve — type
names are probed before aliases — so it is a hard error in either declaration
order:

```
demo.nuc:2: error: deftype: 'Pt' already names a type — an alias of an existing type name would never resolve
demo.nuc:2: error: deftype: 'off_t' already names a C typedef imported from /usr/include/unistd.h — an alias of an existing type name would never resolve
```

See [A C typedef is a Nucleus type name](structs-unions.md#a-c-typedef-is-a-nucleus-type-name)
for the reverse direction — a C typedef is itself usable as a type name with no
`deftype` at all, transparently, the same way an alias's body is.

Both are types in a **generic pattern** too: `(defn f ((v (ref (Vector PtRef))))
…)` is a plain function over `(Vector &Pt)`, not a template whose argument is a
type variable named `PtRef` (see [Generics](generics.md#bounded-generic-defn)).

An alias that expands into a cycle (`(deftype A B)` + `(deftype B A)`) is
refused when it is used.

### Parametric aliases

An alias may take type parameters, spelled exactly as a `defstruct` template's:

```lisp
(deftype (Vec T)   (ref (Vector T)))
(deftype (Table V) (ref (HashMap CStr V)))

(defn size (m:(Table i32)):i64 (return (as i64 (count m))))
```

Applying one substitutes the argument types into the body and parses the result,
so `(Vec CStr)` **is** `(ref (Vector CStr))` — a parametric alias is exactly as
transparent as a plain one, with the same byte-identical IR. Because the
expansion happens before type variables are collected, an application also works
as a **generic method's receiver**, where the argument is still a free tyvar:

```lisp
(defn first-of (v:(Vec T)):T (return (invoke v (as usize 0))))
```

Three rules follow from the substitution being positional:

- The argument count must match the declaration — `(Vec i32 CStr)` reports
  `Vec: wrong number of type arguments for type alias (2 given)`.
- A parametric alias must be applied. Using the bare name reports
  `type alias 'Vec' takes 1 type arguments`.
- A parameter spelled inside a **colon chain** in the body substitutes
  segment-wise, so its argument has to be one token: `(deftype (Ref T) ref:T)`
  accepts `(Ref Pt)` but not `(Ref (ref Node))`, since a chain segment has
  nowhere to put a paren form. Write the body in list form — `(ref T)` — where
  an argument may be compound.

**An alias's body is its file's text.** A library's alias names that
library's types however it is imported. With `(deftype (Two T) (struct a:T
b:&Pt))` in `(ns shapes)`, a consumer's `(sh/Two Pt)` has an `a` that is the
consumer's own `Pt` (arguments stay the caller's) and a `b` that points at
`shapes/Pt`. A mistake in the body is reported at the library's line: at the
definition for a source library, and at the first use for a header's alias, with a
`while reading type alias 'shapes/Two' (requested at …)` note. See [A template
is read as the file that wrote it](toplevel.md#a-template-is-read-as-the-file-that-wrote-it).
This includes a generic method's receiver pattern (`(defn f (b:&(sh/PBox T)) …)`),
where the body is matched rather than parsed. `PBox`'s `Box` is still `shapes/Box`
there, even in a file that defines a `Box` of its own.

**Not a newtype.** An alias creates no distinct identity, so it cannot be used
to give an existing type separate dispatch or to prevent implicit conversion
between the two spellings. The same holds for protocol conformance:
`(extend Money P)` over `(deftype Money i32)` conforms `i32` (see
[Protocols](generics.md#protocols-defprotocol-and-extend)).

## Pointer kinds: `&T`, `?&T`, and `(ptr T)`

Typed pointers carry a compile-time **kind**; all of them lower to the same IR
`ptr` and are ABI-identical to a C `T*` (see `design/stage10/nullability.md` and
`design/stage21-cleanup/ptr-is-unchecked.md`). The name says whether a pointer
is checked: `&`/`ref` is non-null, `?` is checked, and `ptr` in any form is
unchecked.

| Surface | Meaning | Deref | Null? |
|---|---|---|---|
| `&T` ≡ `(ref T)` ≡ `ref:T` | **non-null** — always a valid `T` | always safe | no |
| `?&T` ≡ `(Maybe (ref T))` | **nullable, checked** — may be none | **compile error** until narrowed | yes |
| `(ptr T)` ≡ `ptr:T` | **unchecked** — the C-boundary escape | allowed (your problem) | yes |
| bare `ptr` | **untyped, unchecked** — C's `void*`, the type of `null` and of an imported C `T*` | no pointee | yes |

Unchecked pointers are unsafe, so write `&T` or `?&T` wherever you can, and keep
`(ptr T)` for code where the unchecked form saves real structure. The compiler's
own source follows that rule (the census is in the design doc above).

`raw` was the unchecked kind's old name. It is retired: `raw`, `(raw T)` and
`raw:T` are refused with `'raw' was retired: write ptr for an untyped pointer,
(ptr T) for a typed unchecked one`. A pointer to `void` is refused too —
`(ptr void)`, `&void` and `?&void` say `void has no pointee: write ptr for an
untyped pointer`.

**A diagnostic spells the kind.** Every message names a pointer type as `&T`
(non-null), `?&T` (nullable-checked), `(ptr T)` (unchecked), `!&T` (a niche `!`
pointer) or bare `ptr`, nesting as written (`&&T`, `&(ptr T)`) — so `argument 1
has type (ptr Pt), which does not match parameter type &Pt`. The REPL's
`type-of` prints the same spelling. A stamped template instance is printed as
its source application, `&(Vector i32)`, from the arguments its stamp recorded;
the prelude's `(Maybe T)` and `(Result T Err)` print as `?T` and `!T`. A stamp
keeps the pointer kind of whichever spelling stamped it first, so `(Vector &Pt)`
and `(Vector (ptr Pt))` print as the one that came first.

**`&T` is sugar for `ref:T`.** The reader expands a `&` that begins a type
chain segment into `ref:`, so `&T` and `ref:T` are the same spelling — same
type, same non-null obligations, byte-identical IR. It composes with everything
the colon chain composes with:

```lisp
(defn shift (p:&Point d:i32):&Point …)   ; param and return
(defstruct Holder (link &Point))         ; field, list form
(let (v:&(Vector &Point) …) …)           ; colon-paren fuse, template argument
pp:&&Point   q:?&Point   r:&ptr:Point    ; ref:ref:T, ?ref:T, ref:ptr:T
```

The sigil is only a `&` at the *start* of a segment — offset 0, after a `:`,
after another `&`, or after a `?`/`!` prefix. An interior `&` is an ordinary
symbol character, so a `&` inside a token keeps its name, and the retired
`&rest`/`&where`/`&optional`/
`&repr` markers still report their keyword replacements rather than reading as
types. In an expression they are ordinary address-of, so `&rest` takes the
address of a local named `rest`.

A `&` that starts a whole **token** is the address-of reader macro instead —
`&x` is `(ref x)`, see [Special forms](special-forms.md). The two are split
by position in the token, not by context: the sigil is always preceded by
something (`p:&T`, `?&T`, `):&T`), so only the standalone spelling is shared.
There the reader writes `(ref X)` before anyone knows the position, and that is
one node with one meaning per world: in a type slot `(ref T)` is the non-null
pointer, which is why `(sizeof &Pt)`, `(link &Point)` and `(Vector &Point)`
above are types; in a value slot `(ref x)` is the address-of, whose type is
`(ref (type-of x))`. Since the node is the canonical one, `--emit-nuch` prints
`(ref T)` for a standalone `&T` in an exported signature — no spelling leaks
into a header. The older value-form head `addr-of` is retired (Stage 21 PK-5b)
and reserved: `(addr-of x)`, `(addr-of p 'f)` and `(addr-of T)` in a type slot
are all refused with one targeted error — see [Special forms](special-forms.md).

Only a **non-null** destination adds obligations: an unchecked (`ptr`,
`(ptr T)`, `CStr`) or `?T` value may not flow into a `&T` slot (binding,
`set!`, field/element store, argument, return). Narrow a `?&T` first; launder an
unchecked pointer with `(as-ref p)`, which gives a `?&T` to narrow; or assert
with `(unsafe/cast &T p)`. `as` refuses the conversion and names those two
routes (see [Implicit Type Coercion](#implicit-type-coercion)). Widening
(`&T`→`(ptr T)`, `&T`→`?&T`, `(ptr T)`↔`?&T`, anything→`ptr`) is always
allowed, and `null` flows into any nullable slot. `none` is the null `?T`
literal. Stack addresses are non-null by construction: `&x`, `(ref p 'f)` (the
2-argument arity), `(alloca T)`, `(array T …)`, and a `(S …)` compound literal
all yield `&T`.

**A global declared non-null must be initialized.** `(defvar g:&T)` with no
initializer is a compile-time error: with no initializer the slot takes the
type's zero, which for a pointer is `null` — exactly the value the type says it
can never hold. The rule is the same one every other position enforces, and it
applies at a global only because there is now a way to write the initializer
(see [Run-time initializers](toplevel.md#run-time-initializers)).

```lisp
(defvar g:&Thing)                 ; error: non-null pointer type but no initializer
(defvar g:&Thing (make-thing))    ; fine — the run-time initializer runs before main
(defvar g:?&Thing)                ; fine — a Maybe pointer may be none
(defvar g:ptr:Thing)              ; fine — an unchecked pointer is nullable
(defvar g:ptr)                    ; fine — bare `ptr` is nullable
(defvar g:CStr)                   ; fine — CStr is not a typed pointer kind
```

A `CStr` *source* carries no non-null contract, so it may **not** flow into a
non-null slot — `(defvar g:&T (as CStr null))` and `(as &i8 (getenv "X"))` are
both errors, for the same reason an unchecked pointer is. Use `as-ref` and
narrow, or `unsafe/cast` to assert.

**Uniform `?` (Maybe)**: `?T` ≡ `(Maybe T)` with no
auto-`ref` injection. For a **pointer** operand it niche-encodes
(`?&T` ≡ `(Maybe (ref T))`, one pointer, `null` = none; `?ptr:T` and `?ptr`
are the same niche); for a
**value** operand (`?i64`, `?SomeStruct`) it stamps the two-arm `{tag, T}` value
union from the prelude template. One spelling, two layouts. The value `(Maybe T)` is
built with `make` / target typing (bare `none` / `(some v)` resolve against a
`(Maybe T)` return, typed binding, `make` field or parameter) and eliminated with `match`
(`((some v) …)` / `(none …)`). The pointer relabels (`some`/`none`/`as-ref`
where no value `(Maybe T)` is wanted, `if-some`/`when-some`/`unwrap`/`unwrap-or`) stay
pointer-only. `?!T` ≡ `(Maybe (Result T Err))` is the value-Maybe-over-Result
sugar (a fallible result that may be absent). Over a parenthesised type the
sigil is written attached — `?(Vector i32)`, `?!(Vector i32)` — which reads as
the list form `(? (Vector i32))` / `(?! (Vector i32))`, the canonical node
(see [Sigil-paren forms](#type-syntax-and-desugar)).

**A nullable value is a condition.** `ptr`, `(ptr T)`, `CStr`, `?T` and a value
`(Maybe T)` may be written bare at a condition site — `(when m …)` means
`(when (!= m null) …)` — while `&T` may not, because a non-null pointer's test
is a constant. For the same reason `(= p null)` and `(!= p null)` on a `&T` are
refused: `=: &T is non-null, so comparing it with null is constant`. See
[Condition position](special-forms.md#condition-position-a-nullable-value-is-a-condition).

**Flow narrowing**: inside a region dominated by a successful non-null test, a
`?&T` binding (a local or a global) reads as `&T`. The compiler's own guard idioms are
the mechanism — `(when (= m null) (return …))`, `(if (!= m null) … …)`,
`(and (!= m null) (m field))`, and the bare `(when m …)` above all narrow, as do
`if-some`/`when-some`/`unwrap`. An unchecked `(ptr T)` does **not** narrow: its
deref is already allowed, and turning it into `&T` is `as-ref` plus a narrow.
A reassignment kills the narrow (sticky across joins); loop bodies drop narrows
established outside the loop for any binding the body assigns; `label` kills
all narrows (unknown predecessors). A narrowed global reads as `&T` only to the
end of the function that tested it. Kind mismatches at a `cond`/`if` join meet
conservatively (unchecked beats `Maybe` beats `ref`).

> **⚠ Sharp edge — branch *element* types must match.** The conservative meet
> above reconciles the pointer *kind*, but the branch **element** types must
> still be `type-eq`. Two pointer branches with *different element types* —
> e.g. `(ptr Node)` (the type of an `ast-first` read) versus a `ptr:i8` — do
> **not** unify; the `cond`/`if` collapses to `void`. That then fails
> wherever a value was expected (`let`/`set!` `init type mismatch`; a macro
> body returns `null`). Make the branches agree — usually `(as ptr <branch>)`
> the odd one (`ptr` ↔ `(ptr Node)` is a no-op reinterpret — exactly the
> pointer-contract weakening `as` accepts). This bites most
> often in macros and AST-walking code; see the "Sharp edge" section in
> [macros.md](macros.md).

## Volatile qualifier

Volatility is declared through the **keyword-attribute slot**: a leading
`:volatile` keyword immediately before the declared name of a variable,
global, struct/union field, or `defn` param. For a pointer *target* (C's
`volatile T *`, the MMIO case), the keyword instead moves inside the pointer
constructor — `(ptr :volatile T)` / `(ref :volatile T)`
— since pointee volatility must travel with the pointer through params and
fields. Loads and stores of a value held at a volatile-qualified storage site
are emitted as `load volatile` / `store volatile` in LLVM IR; the compiler
will not elide, reorder, or coalesce them. Examples:

- `(defvar :volatile trap-zero:i32 0)` — volatile global
- `(let (:volatile x:i32 0) ...)` — volatile local (binds to the immediately following name only)
- `(defstruct R flags:i32 (:volatile status:i32))` — volatile field (parenthesized, keyword head)
- `(defn bump-counter ((p (ptr :volatile i32))):void ...)` — pointer to volatile `i32`; deref and a `(deref p)` place store through `p` are volatile

Volatility lives on the storage site, not the value: `volatile T` and `T` are assignment-compatible, and the qualifier is dropped/added at the access. Bare `ptr` (no element) cannot be made volatile — volatility attaches to the pointee, not to opaque pointers. Attributes never participate in type identity, overload resolution, dispatch, monomorphization, or name mangling — see [stage14/attributes.md](../design/stage14/attributes.md) for the full attribute-slot design.

> The older postfix spellings (`(T volatile)` list form, `T:volatile` colon segment) are retired: the compiler rejects them with a targeted error naming the `:volatile` attribute-slot spelling above.

The **struct** attributes use the same two slots but are properties of the type
rather than of a binding. `:packed` and `:align N` go before the struct name or
heading a field cell; `:bits W` and `:anon` head a field cell only. See
[Packed structs](structs-unions.md#packed-structs--defstruct-packed),
[Over-aligned structs and fields](structs-unions.md#over-aligned-structs-and-fields--align-n),
[Bit-fields](structs-unions.md#bit-fields--bits-w-namet) and
[Anonymous members](structs-unions.md#anonymous-members--anon-t).

## Const globals

A read-only global is a [`defconst`](toplevel.md#constants). An aggregate
constant such as `(defconst TABLE (array ui8 1 2 4 8))` is emitted as an LLVM
`constant` rather than a mutable `global`, so it lands in read-only data. On a
target with separate program and data memory (AVR), that keeps it out of RAM.
Every write to a constant, whether to the whole name, a field or an element, is
a compile-time error.

`:const` survives as a declaration attribute only on an `extern`:
`(extern :const (TABLE (array ui8 4)))` declares that another unit's global is
read-only, and writes to it are refused the same way. On a field, parameter or
binding, `:const` is an error (`':const' applies only to an extern, not a
field, parameter, or binding -- a read-only global is a defconst`), and
`(defvar :const …)` was retired in favour of `defconst`.

The check covers the write syntax only; it is not an aliasing analysis.
`&TABLE` is an ordinary writable pointer (see the hole noted under
[Constants](toplevel.md#constants)).

## Built-in Types

| Name | Description | C Equivalent |
|------|-------------|--------------|
| `int` / `i32` | 32-bit signed integer | `int32_t` |
| `bool` | Boolean truth value (`true`/`false`); emitted as `i1` in IR, but `i1` is not a valid source spelling — naming it is a located error | `bool` |
| `i8` | 8-bit signed integer | `int8_t` / `char` |
| `i16` | 16-bit signed integer | `int16_t` |
| `i64` | 64-bit signed integer | `int64_t` |
| `ui8` | 8-bit unsigned integer | `uint8_t` |
| `ui16` | 16-bit unsigned integer | `uint16_t` |
| `ui32` | 32-bit unsigned integer | `uint32_t` |
| `ui64` | 64-bit unsigned integer | `uint64_t` |
| `f16` | IEEE-754 binary16 | `_Float16` |
| `f32` / `float` | IEEE-754 binary32 | `float` |
| `f64` / `double` | IEEE-754 binary64 | `double` |
| `f80` | x87 80-bit extended (x86 only) | `long double` on x86 |
| `f128` | IEEE-754 binary128 | `_Float128` / `__float128` |
| `usize` | Unsigned pointer-sized integer (resolves to `i32` on ILP32 targets, `i64` on LP64) | `size_t` |
| `ssize` | Signed pointer-sized integer (resolves to `i32` on ILP32 targets, `i64` on LP64) | `ssize_t` / `ptrdiff_t` |
| `ptr` | Opaque pointer | `void*` |
| `(array T N)` | Fixed-size array of N `T`; storage only, decays to `(ref T)` on read (see [Fixed-size arrays](#fixed-size-arrays--array-t-n)) | `T x[N]` |
| `CStr` | C-style (null-terminated) string | `char*` |
| `Char` | A 32-bit Unicode scalar value (codepoint) | `uint32_t` |
| `void` | No value | `void` |

Pointer size and the target are not hardcoded as `i64`/`8` throughout codegen: a target descriptor (`g-target-triple`, `g-target-ptr-bytes`, defaulting to `x86_64-pc-linux-gnu` / 8 bytes) drives the emitted `target triple`, pointer/`CStr` type sizes and alignments, and the width of `sizeof` (a pointer-sized `size_t`). To target a 32-bit or 16-bit platform, set `g-target-ptr-bytes` to 4 or 2 respectively. (The macro/`compile-time` JIT still targets the host.)

**`usize` and `ssize`** are the portable index and length types for pointer-sized arithmetic. They resolve to the target's pointer-width integer at compile time: `i32` on ILP32 (4-byte pointer) targets and `i64` on LP64 (8-byte pointer) targets. `usize` is unsigned; `ssize` is signed. They are valid in any type position and are handled correctly by `sizeof`, type mangling, `type-eq`, and arithmetic operators. Use `usize` for lengths, counts, and non-negative offsets; use `ssize` for signed differences or offsets that may be negative. Both participate in the standard numeric promotions and are mangled distinctly (e.g. `usize`, `ssize`) in method symbols and stamped struct names.

**A bare `"…"` string literal has static type `StrView`**, not `CStr` — a borrowed `{data:(ptr ui8), len:usize}` view over the literal's rodata storage (see [Strings](strings.md) for the full `StrView` API). `StrView` is a library struct, but its bare type is promoted into the prelude, so it is available everywhere without an import; its methods and protocol conformances still require `(import-use nucleus.strview)`. A literal's backing storage is always NUL-terminated at `data[len]` (the same rodata global `CStr` literals always used), so a `StrView` value coerces to `CStr`/`ptr` **for free** (no IR) at any assignment, call argument, `as`/`unsafe/cast`, or return boundary, by taking `data` — this is what keeps every existing `:CStr`/`:ptr`-typed function, `printf`/libc call, and `strcmp`-style `=`/`!=` comparison working with a string literal unchanged. Only when a literal flows into a genuinely `StrView`-typed slot does it materialize the two-word `{data,len}` struct. In overloaded (`defn`/multimethod) dispatch, a `StrView`-typed argument adapts to a `CStr` parameter but *not* to a bare `ptr` parameter, reproducing the resolution a `CStr` literal produced before this type existed. A materialized `StrView` passed to a C variadic parameter (e.g. `printf`'s `%s`) contributes only its `data` pointer, never the two-word struct; a *fixed* (non-variadic) `StrView` by-value parameter is unaffected and still receives the full two-eightbyte struct per the platform ABI (`examples/strview-vararg-test.nuc`).

`CStr` is the C-interop `char*` type — the FFI boundary type a `:CStr`-typed parameter, field, or return expects. It lowers to `ptr` (same ABI) and flows into any `ptr`-typed C function with no cast, but it is a **distinct type for operator dispatch**: `=` / `!=` on two `CStr` (or a `CStr`/`ptr`/`StrView` mix) do a `strcmp`-style **content** comparison (so equal text compares equal across distinct buffers), whereas `=` on two raw `ptr` is pointer identity. **Comparing against the `null` literal is the one exception: `(= s null)` / `(!= s null)` on a `CStr` is a pointer-identity test, not a content comparison** — `strcmp(s, NULL)` is undefined behaviour in C, so a null check is always a null check. This makes the ordinary `(if (= s null) …)` guard safe on a `CStr` parameter, local, field, or global. (A `StrView` is a two-word struct and can never be null; compare its `data` field if you need that.) `CStr` conforms to the `Eq` protocol (`lib/nucleus/numeric.nuc`), so it works in an `Eq`-bounded generic; it is not `Ord` (no ordering — out of scope here, along with Unicode). Only `=` / `!=` are defined; other operators on `CStr` are an error. A `CStr` and a `ptr` are freely interconvertible with `as` (no IR) and coerce automatically in value positions (assignment, return, field/array store). (Multimethod dispatch treats `CStr` as distinct — overload on `CStr` explicitly, or `as` to `ptr`.) `strcmp` must be declared, which the prelude's `(import-use "string.h")` provides. To bind an `Eq`-bounded generic at `StrView` from a literal, `(import-use nucleus.strview)` must be in scope; otherwise `as` the literal to `CStr` explicitly. Example: `examples/cstr.nuc`.

A **global** of `CStr` type may be initialized with a string literal directly (`(defvar g-name:CStr "doom")`) or with the explicit `(as CStr "doom")` spelling — both emit the same `@g-name = global ptr @.str.N` line. `(as CStr …)` in an initializer works because a `defvar` init is a constant *expression*, not merely a literal; see [Global initializers](toplevel.md#global-initializers). A `StrView` global takes a plain string literal too (`(defvar g-name:StrView "doom")`), as does a `StrView` field or element of a constant aggregate: the constant is the literal's rodata pointer and byte length.

A `c"…"` literal — a `c` glued directly onto the opening quote, with no whitespace — is an explicit `CStr` literal: the bare `char*` GEP, no `{data,len}` view header, and no target-typing. It is the direct "I mean `char*`" spelling for FFI/format-string hot spots; the free `StrView`→`CStr` coercion above already covers the same cases, so `c"…"` is ergonomic, not required. A space keeps the tokens apart (`c "foo"` is the symbol `c` followed by an ordinary `StrView` literal); only the glued, lowercase-`c` form is the literal. See [Strings](strings.md) §3 and `examples/cstr-lit-test.nuc`.

**`Char`** is a single Unicode scalar value — a codepoint in `0..=0x10FFFF` excluding the UTF-16 surrogate range `0xD800..=0xDFFF` (Rust's `char` model; "character" means codepoint, not grapheme cluster). It is a **built-in distinct 32-bit scalar over `ui32`**, the same kind of distinct scalar `CStr` is: it lowers to IR `i32` (C `uint32_t`, size 4) and participates in the integer operators, but it is its own type for dispatch. `=` / `!=` on two `Char` compare codepoints (`(= \a \a)` is true, `(= \a \b)` is false), and a `Char`-vs-int overload is distinguishable. A same-width `as` (or `unsafe/cast`) between `Char` and `ui32`/`i32` is a no-op reinterpret (`(as ui32 \A)` is `65`). Because `Char` is distinct, two *typed* operands of different kind do **not** silently unify: `(= \a (as ui32 65))` is a compile error (`operand type mismatch`) — convert one side explicitly with `as`. An untyped integer literal still adapts to a `Char` operand, so `(= \a 97)` is allowed. Write a `Char` value with a [char literal](#char-literals--a) (below) or, equivalently, the `(char "x")` form. (The `Char` UTF-8 encode/decode and classification library is a separate task.)

Float literals: `1.5`, `-0.25`, `1e10`, `1.5e-3`, `.5`, and C's hex form `0x1.921fb54442d18p+1`. Special values use Scheme syntax: `+inf.0`, `-inf.0`, `+nan.0`. Float arithmetic uses `+ - * / %` and comparisons use `= != < <= > >=` (LLVM `fadd`/`fcmp`).

Integer literals are decimal or C hex: `255` and `0xFF` are the same value, and `0x` accepts either case in the prefix and the digits. There is no octal form — a leading zero is not significant, so `0644` is six hundred and forty-four.

### The wide float widths, and which targets have them

`f16`, `f80` and `f128` exist alongside `f32`/`f64`, and each is the format C
names on the same target: `_Float16`, x87 80-bit extended, and IEEE binary128.
Constants, struct layout, and the by-value calling convention all match the
platform C compiler bit for bit, including the three cases where the aggregate
ABI differs from the scalar one (a struct holding a `long double` goes through
memory; a struct holding one `__float128` stays in a single xmm pair; an `f16`
beside an `i32` merges into one integer eightbyte).

**A width is refused on a target that has no format for it**, rather than
emitting IR the backend cannot select. AVR has none of the three; `f80` is an
x87 format and exists only on x86. The portable spelling is C's: `long double`
imported from a header is `f80` on x86, `f128` on aarch64 and riscv64, and
`f64` under MSVC and on AVR — so a header-driven program cross-compiles while
one that names `f80` directly is pinned to x86, which is the intended trade.

**Write a wide constant in hex.** A decimal float literal is folded through a
host `double`, so `(let (x:f128 1.1) …)` gets the `f64` value of 1.1 widened
exactly — seventeen significant digits, not thirty-four. The hex form is exact
by construction and carries the full significand at every width:
`0x1.921fb54442d18469898cc51701b8p+1`. C requires the binary exponent, and so
does this: `0x1.8` is not a float literal (nor an integer — it is an error), and
`0x18` is an integer.

**A float literal is untyped: it adapts to whatever float width the position wants**, and only falls back to `f64` when nothing asks for anything else. That covers both a binop operand — with `alpha:f32`, `(* alpha 2.0)` and `(* 2.0 alpha)` are both `f32`, in either order — and every *typed target* position: `(let (a:f32 0.1) …)`, `with`, `(set! a 0.1)`, `(set! (p 'x) 0.1)`, `(return 0.1)` from an `f32` function (explicit or implicit), an `f32` field in a struct literal, an `f32` element in an `(array f32 …)`, an `f32` argument at a call, and an `f32` `defvar` initializer. None of these need an `(unsafe/cast f32 …)` wrapper, and the literal is rounded to single precision at compile time — no conversion instruction is emitted.

A bare float literal with no target is `f64`, so `(let (b 0.1) …)` and `(let (b:f64 0.1) …)` are both `f64`; adaptation never makes an unrequested `f32`. Two *typed* float operands of different width widen to the wider (`f32 * f64` is `f64`). Mixing float and integer operands without an explicit `unsafe/cast` is a compile error — a float literal adapts only to a *float* target, never to an integer one (`(let (a:i32 1.5) …)` is rejected).

A `f64` **value** (not a literal) narrows into an `f32` target implicitly and silently, with an `fptrunc`, the same way an `i64` value narrows into an `i32` slot; the explicit `(as f32 d)` spelling still refuses it as lossy and routes you to `(unsafe/cast f32 d)`. A float **literal** is different: `(as f32 1.5)` is accepted, because 1.5 is exactly representable in single precision, and it emits the same constant the implicit spelling emits — while `(as f32 3.14)` is still refused, because that literal does not survive the round trip. See [Implicit Type Coercion](#implicit-type-coercion) below for the full rule.

**`f64` is unsupported when `--target=avr`**: AVR has no hardware double, so `f64`/`double` is a compile-time error, whether written as an explicit type annotation or reached only through a bare float literal's default type (`(let (x 1.5) …)` is rejected even with no `f64` text in the source). The error names the `-mdouble=64` avr-gcc multilib escape hatch for a custom AVR build with software double support. `f32` *types* are unaffected, and `i64` remains fully supported (arithmetic links libgcc's software routines, e.g. `__muldi3`). **A float *literal* is rejected on AVR even in an `f32` position** (`(let (a:f32 1.5) …)`), because the check fires when the literal is emitted, before its target width is known; this predates the W2d literal adaptation — `(unsafe/cast f32 1.5)` was rejected at the same point — so an AVR program currently cannot spell a floating-point constant at all. Lifting it is AVR work, not literal-typing work. This check applies only to the AVR target module itself — compile-time/macro code always runs on the host regardless of `--target=`, so ordinary `f64` arithmetic inside a `defmacro`/`compile-time` body compiling *for* an AVR program is unaffected.

## Fixed-size arrays — `(array T N)`

`(array T N)` is a fixed-size array of `N` values of `T`, laid out inline exactly
as C's `T x[N]`. `N` is a compile-time constant *expression* — a literal, a
`defconst` / `defenum` name, or arithmetic over them — evaluated by the same
folder a [global initializer](toplevel.md#global-initializers) uses.

It is a **storage** type, so it is valid in exactly these positions:

* a `defvar` type — `(defvar g-table:(array i32 256))`
* a field of an aggregate — a `defstruct` field, or a member of an anonymous
  `(struct …)` / `(union …)`
* `(sizeof (array T N))`
* `(alloca (array T N))`, which reserves `N` slots of frame storage

**Reading an array decays it to a pointer**, exactly as in C: the value of an
array-typed global, field, or `alloca` is the address of element 0, typed
`(ref T)`. Nothing is loaded and nothing is copied.

```lisp
(defstruct Row tag:i8 (cells (array i32 4)) mark:i8)   ; C: struct { int8_t tag; int32_t cells[4]; int8_t mark; }

(defn row-first ((r (ref Row))):i32
  (aref (r 'cells) 0))         ; (r 'cells) is ptr:i32 — a GEP, no load

(defn scratch ():i32
  (let (buf:ptr:i32 (alloca (array i32 64)))   ; 64 slots of frame storage
    (set! (aref buf 0) 1)
    (aref buf 0)))
```

Because it decays, an array is **refused** wherever a whole-array *value* would
have to exist — a by-value parameter or return, a `let` / `with` binding type, a
pointer element (`ptr:(array T N)`), a generic type argument, a nested array
(`(array (array T M) N)`), and as the target of a `set!` place. Each is a
compile-time error naming the `ptr:T` spelling that works. C has the same
restrictions for the same reason.

Layout, size and alignment match the platform C ABI: `sizeof` is
`N * sizeof(T)`, alignment is `T`'s, and a struct containing an array field
classifies for by-value passing element by element — so `struct { float v[2]; }`
travels in an SSE register, as C does it. This is gated by `make layout-test`
and `make abi-test`.

`--emit-cheader` renders an array field with C's postfix declarator
(`int32_t cells[4];`), keeping a named extent symbolic when the header also
exports the constant. `--emit-nuch` round-trips `(array T N)` unchanged, for both
a field and an array-typed global (exported as `(extern (g (array i32 3)))`).

An `(array T N)` global's initializer must be a **compile-time constant** — an
`(array T …)` literal, or nothing at all (`zeroinitializer`). There is no
run-time route for one, because an array binding names storage that `set!`
cannot target, so there is no assignment a startup initializer could perform;
the pointer form (`(defvar g:ptr:T (make-table))`) is what to declare when the
table has to be built at run time. For the constant grammar, see
[Global initializers](toplevel.md#global-initializers); for the array
**literal** used in expression position, see
[Special Forms](special-forms.md).

## Function Pointer Types

Function pointer types are written as `(fn:rettype (param-types...))` in sugared form, or `((fn rettype) (param-types...))` in desugared/canonical form.

In parameter, `let`-binding, struct-field and union-member positions, either the
canonical list form or the colon-paren sugar works — the reader fuses an
open-segment name (`f:`, `f:ptr:`) immediately followed by `(`, then absorbs
the adjacent parameter-list group (see *Colon-paren binding sugar* above). **Both parenthesised
groups must be adjacent — `f:(fn i32)(i32 i32)`, not `f:(fn i32) (i32 i32)`**; a
space-separated second group is a separate element of the enclosing list, which
leaves `f` typed as a *zero-parameter* function pointer.
The parameters never go inside the head: `(fn i32 (i32))` or `(fn i32 i64)` is
refused as `fn type: '(fn i32 (i32))' has an extra operand`.

```lisp
; canonical list form
(defn apply ((f (fn i32) (i32 i32)) a:i32 b:i32):i32
  (return (funcall f a b)))

; colon-paren sugar — equivalent
(defn apply (f:(fn i32)(i32 i32) a:i32 b:i32):i32
  (return (funcall f a b)))
```

In `let` bindings, the binding name is also a list (or its colon-paren sugar):

```lisp
(let ((f (fn i32) (i32 i32)) some-function)   ; list form
  (funcall f 1 2))

(let (f:(fn i32)(i32 i32) some-function)      ; colon-paren sugar
  (funcall f 1 2))
```

A `defn` function name used in value position decays to a function pointer, matching C semantics:

```lisp
(defn add (a:i32 b:i32):i32 (return (+ a b)))
(apply add 3 4)  ; passes add as a function pointer
```

### Signatures are checked, in both directions

**Every typed function-pointer slot compares signatures**, not just kinds — a
`let`/`with` init, a `set!` place, a `return`, and a call
argument all refuse a function whose parameter list or return type does not
match, and the diagnostic prints both signatures as written:

```
take-fn: argument 1 has type (i32, i32):i32, which does not match parameter type (i32):i32
let: init type mismatch for 'f': value is (i32, i32):i32, slot is (i32):i32
```

Two relaxations, both matching C:

- **Pointer *kind* is not part of a signature.** `ptr:i32` and `(ref i32)`
  are interchangeable in a parameter or return position, so the
  `qsort` comparator shape (`(fn i32) (ptr ptr))` accepts
  `(defn cmp (a:ptr:i32 b:(ref i32)):i32 …)`.
- **A bare elem-less `ptr` is the function-pointer analogue of `void *`.** It
  matches any pointer in the same position, in either direction. It is *not* a
  wildcard for a function-pointer parameter: turning a data pointer into
  something callable stays `unsafe/cast`'s job.

**Calling through a pointer is the same call.** `(funcall f …)` and a
function-pointer value in head position go through the identical argument path a
direct call does — literal widening, `f32`→`double` promotion for a variadic
tail, the by-value struct ABI (`byval` / `sret` / register coercion), and the
same argument diagnostics.

### At the C boundary

A C function-pointer type imports as a real `(fn ret)(params)` in all four of C's
declarator positions — parameter, struct or union member, `typedef`, and the
function-returning-function-pointer shape (`void (*signal(int, void (*)(int)))(int)`).
So a callback API takes a Nucleus function directly:

```lisp
(import-use "stdlib.h")
(defn cmpi (a:ptr b:ptr):i32 (return 0))
(defn main ():i32 (qsort arr 10 4 cmpi) (return 0))   ; no cast
```

`--emit-cheader` writes the C declarator back out, since C's function-pointer
type is postfix and has no prefix spelling:

```c
typedef struct Hold { int32_t (*cb)(int32_t, int32_t); int32_t n; } Hold;
int32_t use2(int32_t (*f)(int32_t, int32_t));
int32_t (*getf(void))(int32_t, int32_t);
```

If a C declarator's inner types are ones the header parser cannot describe, the
type narrows to a plain `ptr` rather than being mis-stated, and the enclosing
declaration is still imported.

### Function-pointer globals

A `defvar` may be typed with a function-pointer type — the *hook* shape, where a
slot is declared once and filled in later:

```lisp
(defvar g-hook:(fn i32)(i32) null)   ; declared unwired
(defvar g-zero:(fn i32)(i32))        ; identical: the implicit zero is null
(defvar g-init:(fn i32)() (pick))    ; run-time initializer: filled at startup

(defn main ():i32
  (set! g-hook add1)                 ; assign any matching function
  (return (g-hook 41)))              ; call through it — funcall also works
```

**A function pointer is nullable and carries no non-null contract.** The pointer
kinds (`&`/`?&`/`ptr`) apply to data pointers, not to `(fn ret)(params)`, so `null` is
a fn pointer's ordinary "not wired yet" value — the same status `CStr` and
bare `ptr` have. Note the distinction from the *wrapper* spellings:
`&(fn ret)(params)` and `ptr:(fn ret)(params)` are pointers **to** a function
pointer; the first is non-null like any other `&T` and rejects a `null`
initializer.

`null` initializes or assigns a function-pointer slot in **every** position — a
`defvar`, a `let`/`with` binding, a `set!` place and an explicit
`return` — and costs no instruction, since both sides are one `ptr` register:

```lisp
(defvar g-hook:(fn i32)(i32) null)
(defn no-hook ():(fn i32)(i32) (return null))
(defn main ():i32
  (let (loc:(fn i32)(i32) null
        h:ptr:Hooks (alloca Hooks))
    (set! (h 'before) null)
    (set! loc add1)
    (set! loc null)                  ; and back again
    (return 0)))
```

Only the **literal** does this. A `ptr`/`(ptr T)`/`CStr` *value* is refused, because
turning an arbitrary data pointer into something callable is `unsafe/cast`'s job
— spell the function type in an extra pair of parentheses so it is a single
form:

```lisp
(let (f:(fn i32)(i32) (unsafe/cast ((fn i32)(i32)) some-pointer)) …)
```

A hook filled by a [run-time initializer](toplevel.md#run-time-initializers) is
subject to the ordering rule like any other global, and calling *through* a hook
counts as reading it: `(defvar g-v:i32 (g-late 3))` above `(defvar g-late:(fn
i32)(i32) …)` is refused with both sites named, since `g-late` would still be
`null` when `g-v`'s initializer ran.

**Function pointers compare by identity.** `=` and `!=` on a function pointer
are machine identity — the same `icmp` a plain pointer gets — in every position
(global, parameter, local) and against any of: the `null` literal, another
function-pointer value, or a `defn` name used as a value.

```lisp
(if (= g-hook null) …)      ; not wired yet
(if (!= g-hook null) …)
(if (= g-hook add1) …)      ; still the default hook?
(if (= g-hook g-other) …)   ; two slots pointing at the same function
```

A function pointer is deliberately **not** admitted to the `CStr` content
comparison: `(= g-hook some-cstr)` is a compile error rather than a `strcmp` of
a function's machine code. Ordering (`<`, `<=`, …) is permitted and compares
addresses, as it does for data pointers.

A function-pointer slot is one target pointer wide, like any other pointer: a
global, a local, a parameter and a struct field each get the target's pointer
alignment (`align 8` on x86-64, `align 4` on a 32-bit target), and it is the
*target*'s width, not the host's.

## Implicit Type Coercion

The following conversions are applied automatically in assignment contexts (`let`, every `set!` place, implicit and explicit `return`) **and at function call sites** (both direct calls and `funcall`). This is exactly the safe set `as` (see [Special Forms](special-forms.md#special-forms)) also accepts when written explicitly, plus `as`'s own pointer-contract-weakening allowance; `unsafe/cast` accepts this same set **and** everything lossy or contract-manufacturing besides (narrowing, `float`↔`int`, `ptr`↔`int`, `fn`↔`ptr`, element-retyping pointers, and laundering an unchecked or nullable pointer into a non-null slot):

- **Pointer ↔ pointer, when the pointees agree**: identity, no IR. Two things are *not* part of the question and so never block it — the pointer **kind** — `(ref Node)`, `?&Node` and `ptr:Node` are one type to *this* question, and nullability is judged separately by the non-null contract, which still refuses an unchecked or `?` source into a `&T` slot (see [Pointer kinds](#pointer-kinds-t-t-and-ptr-t)) — and an **elem-less bare `ptr`**, which is `void *` and matches any pointer in either direction. Everything else must match: `ptr:i32` into a `ptr:Node` slot, or `(ref (Vector i32))` into a `(ref (Vector i64))` slot, is a compile-time error naming both types.

  ```
  let: init type mismatch for 'b': value is &(Vector i32), slot is &(Vector i64)
  takes: argument 1 has type &SA, which does not match parameter type &SB
  ```

  This is the same rule at every typed slot — `let`/`with` init, every `set!` place, `return`, a call argument, and a `defvar`'s `&g` initializer. Retyping a pointer's element is what `unsafe/cast` is for.
- **`StrView` → `CStr` / `ptr`**: takes the view's `data` field — no IR for an unmaterialized string literal (whose value already *is* `data`), one `extractvalue` for a general `StrView` value. Trusts that the buffer is NUL-terminated at `data[len]`, always true for a literal but not guaranteed for an arbitrary sub-slice (see [Strings — Gotchas and constraints](strings.md)).
- **`ptr:S` → by-value `S`** (`S` a struct): one `load` of the pointee — the implicit form of `(deref p)`. This is what lets a `(S …)` compound literal, which is alloca-backed and evaluates to `(ref S)`, be written directly wherever a by-value `S` is expected: an element of an `(array S …)`, a struct-typed field in another struct literal, a `let`/`with` binding declared `:S`, an element or pointee place store, and an implicit or explicit `return` from an `S`-returning function. Argument positions have always accepted it. The element type must match exactly (a compound literal of a *different* struct is still a type mismatch), and because the conversion is a `deref` it carries `deref`'s obligation: a `?T` source must be narrowed first. The explicit `(deref (S …))` spelling remains valid and emits byte-identical IR.
- **Integer ↔ integer**:
  - Same width, different sign (e.g. `i32` ↔ `ui32`): reinterpret, no IR.
  - Widening: `sext` for signed source, `zext` for unsigned source.
  - Narrowing: `trunc` — **except** that a narrowing of an integer *literal*
    whose value does not fit the target type is a **compile-time error**
    (`integer literal 300 does not fit ui8`), never a silent wrap. This applies
    only to literals with a known value (`(take8 300)`, `(let (b:i8 200) …)`,
    `(< u:ui8 300)`); narrowing a typed *value* still truncates (its runtime
    value is unknown). To deliberately wrap a literal, cast it explicitly with
    `unsafe/cast`: `(unsafe/cast i8 200)` is `-56`.
    A literal that *does* fit is not lossy, so the explicit `as` spelling
    accepts it too — `(as i8 5)` and `(let (a:i8 5) …)` are the same conversion
    and emit the same IR. Only the narrowing of a *value* is outside `as`'s
    safe set. The float narrowing below follows the same rule, with a stricter
    notion of "fits" — see there.
- **`bool` takes none of the conversions above, in either direction.** `bool`
  is not an integer kind (`is-int-type` excludes it), so this chokepoint never
  fires for it: an integer literal or value assigned to a `bool` slot
  (`(defvar g:bool 1)`, `(let (b:bool n:i32) …)`) is a **type mismatch**, not a
  narrowing, and a `bool` value into an `i32` slot is refused the same way.
  `true`/`false` are the only legal `bool` literals — `0` and `1` are not
  numeric spellings of them. Both directions still have an explicit escape:
  `(as i32 b)` is a safe `zext` (`bool` is unsigned, so `(as i32 true)` is `1`,
  matching the `bool` → `_Bool` C mapping), and `(unsafe/cast bool n)` narrows
  back, lossily. `bool` is the one exception to this section's opening claim
  that `as` accepts exactly the implicit safe set: `(as i32 b)` compiles while
  `(let (n:i32 b) …)` does not, because `bool`→`int` widening is reached only
  through `as`'s own dedicated path, never through this chokepoint. `bool`
  still orders correctly under the comparison operators — `(< false true)` is
  true, `(> true false)` is false — because comparison is unified binop typing
  (see below), not this coercion rule.
- **Float ↔ float**:
  - Widening `f32` → `f64`: `fpext`.
  - Narrowing `f64` → `f32`: `fptrunc` for a *value*, and for a float **literal**
    no instruction at all — the literal is re-rendered as a single-precision
    constant at compile time. So `(let (a:f32 0.1) …)`, `(set! a 0.1)`,
    `(return 0.1)` from an `f32` function, `(P 0.1 0.2)` into `f32` fields,
    `(array f32 0.1)`, `(set! (p 'x) 0.1)` and `(take 0.1)` against
    `(defn take (x:f32) …)` all work with the bare literal — no
    `(unsafe/cast f32 0.1)` wrapper. The narrowing of a *value* is silent, the
    same way a narrowing integer assignment is silent (see the `trunc` bullet
    above); unlike the integer case there is no range check, because float
    overflow saturates to `±inf` by IEEE rule rather than wrapping.
    The explicit `as` spelling accepts a literal narrowing only when the literal
    is **exactly representable** at the target width — `(as f32 1.5)` and
    `(as f32 -0.25)` compile and emit the same constant the implicit spelling
    emits, `(as f32 3.14)` is `lossy conversion from f64 to f32`. The implicit
    path has no such condition: it rounds. That is the one place the two
    deliberately differ, and it is what `as` means.
  - Rounding is decimal → `f64` → `f32` (two roundings), which is exactly what
    the explicit `(unsafe/cast f32 3.14)` spelling has always done. In practice
    this agrees with C's `3.14f` for essentially every constant, and `f32`
    arithmetic is otherwise bit-exact with C `float`.
- **User-registered**: any pair declared with `(defcast From To conv-fn)` (see [Top-level forms](toplevel.md)). The compiler emits a call to `conv-fn`. A rule applies at **every** implicit position — call argument, `let`/`with` init, explicit and implicit `return`, every `set!` place, struct-literal field, union payload, and `as` — not just at call sites. Built-in coercion always wins; `defcast` cannot shadow `sext`/`zext`/`fpext`, and registering a rule for a pair the compiler already converts is rejected outright.

  A rule is looked up on the **exact** pair, and **implicit conversions do not compose** — one conversion, built-in or user, never both. A bare integer literal is `i32`, so a rule registered `i64 → ptr` is not reached by `(take 0)`; write `(take (as i64 0))`, or register the rule from `i32` instead. When a conversion fails and a rule reaches that same target from another type, the compiler names it:

  ```
  a.nuc:5: error: show-ptr: argument 1 has type i32, which does not match parameter type ptr
    note: a defcast rule converts i64 to ptr, but implicit conversions do not compose — write (as i64 …) on the operand to reach it
  ```

  See [implicit-conversions.md](../design/stage15-stress-test/implicit-conversions.md) for why composition is refused.

**Outside this set, a call argument is a compile-time error**, named and located
the way every other typed slot's mismatch is: `f: argument 1 has type i32, which
does not match parameter type f64`. `int`↔`float` is *not* in the set in either
direction, so `(take 3)` against `(defn take (x:f64) …)` is refused rather than
converted — the same refusal `(let (a:f64 3) …)` gives, and the reason to write
`3.0`. (Until Stage 15 a failed argument conversion was discarded silently and
the argument passed untouched: that call emitted `call double @take(i32 3)` and
printed `0.000000`. LLVM accepts such a module, because a call site carries its
own signature and is never checked against the callee's definition.)

The check is on the **types**, not on what they lower to. That distinction is
the whole of it for pointers, since `ptr`, `ptr:T`, `CStr` and `(fn …)` are one
`ptr` register apiece: the pointer family stays freely interconvertible as the
bullets above say, and `fn` ↔ `ptr` stays `unsafe/cast`'s job — so a `CStr`, a
`(ptr T)`, a `(ref T)`, an int literal or a string literal in a `(fn …)` parameter
is refused, exactly as it is in a `let`, a `set!` and a `return`. The literal
`null` is the one spelling a function-pointer slot takes, in every position.
(Until Stage 15 the argument position compared *lowered* types, so all of those
compared equal to a function pointer, nothing was checked, and the callee called
whatever arrived.) Nullability is checked separately, before the type identity,
and reports the unchecked/`?T`-into-`&T` case in its own words.

**Binary operators unify their two operands** by exactly one rule, and the
result type is that unified type (a comparison always yields `bool`). The rule is
**symmetric in operand order** — `(* 2 x)` and `(* x 2)` type identically:

- An **untyped literal adapts to the other operand's type**: an integer literal
  to any integer *or* float operand (`(+ x:i64 1)`, `(* 2 u:ui32)`,
  `(* d:f64 2)`), a float literal to any *float* operand
  (`(* alpha:f32 2.0)` is `f32`, not `f64`). Two untyped literals fall back to
  `i32`, or `i64` when either value does not fit.
- A name bound by **`defconst` or a `defenum` member counts as that literal** —
  naming a constant does not change how it types. `(defconst K 512)` then
  `(<= ans:ui32 K)` behaves exactly as `(<= ans:ui32 512)`, in either operand
  order. A *local* binding that shadows the constant is an ordinary typed
  value, not a literal.
- **Two typed operands of the same kind widen** to the wider one:
  `(+ i32-value i64-value)` is `i64`, `(+ f32-value f64-value)` is `f64`.
- Everything else is a compile error at the operator: a float operand against an
  integer operand (`float and non-float operands`), mixed-sign integers such as
  `i32 + ui32` (`mixed signed/unsigned operands`), a typed `Char` against a
  typed non-`Char` integer (`operand type mismatch`), and `bool` refused
  outright — `+ - * / % bit-*` reject a `bool` operand even against another
  `bool` (`_+ does not apply to bool`), and reject a mixed `bool`/non-`bool`
  pair (`_+: mixed bool and non-bool operands`); only the six comparisons
  accept `bool` operands. Fix the integer/float cases with an explicit
  `(as ...)` (widening / same-width sign reinterpret) or `(unsafe/cast ...)`
  (narrowing, `float`↔`int`) on the binop side — the compiler will not
  sign-reinterpret or truncate a *typed* value for you.

Only a literal adapts freely; a typed value still obeys the coercion rules above.

Explicit `(unsafe/cast ...)` is also still required for cross-kind conversions: `int ↔ ptr`, `int ↔ float`, and `ptr ↔ float` — none of these are in `as`'s safe set.

`f64 → f32` is a special case: the **implicit** coercion at a typed slot performs
it (silently for a value, exactly as an `i64 → i32` assignment does), but the
**explicit** `(as f32 d)` still refuses it as lossy and routes you to
`(unsafe/cast f32 d)`. For a *value* that asymmetry is not float-specific —
`(as i32 n:i64)` is refused for the same reason while `(let (a:i32 n) …)`
truncates — and is a standing question about implicit narrowing in general.
For a *literal* the two agree, and integers and floats agree with each other:
`(as i8 5)` and `(as f32 1.5)` are both accepted, because the value is known and
the conversion is therefore lossless.

The float rule is stricter than the integer one in one respect, and
deliberately so. `as` admits a float literal only when it round-trips
**exactly**, so `(as f32 3.14)` is still `lossy conversion from f64 to f32`
even though `(let (a:f32 3.14) …)` compiles — the implicit path rounds to the
nearest single silently, which is what an assignment does everywhere, and `as`
is the spelling that promises it did not lose anything. Write
`(unsafe/cast f32 3.14)` when the rounding is what you want.

**Multimethod dispatch is stricter than assignment.** A float *literal* adapts
to a narrower float parameter when selecting an overload (`(over 0.1)` picks
`(defn over (x:f32) …)`), but a typed `f64` *value* does not — dispatch never
narrows a runtime value to choose which function runs. Cast at the call, or add
the overload. This mirrors the integer rule, where a typed `i64` value likewise
only ever dispatches to an `i64`-or-wider parameter.

### Variadic arguments: C's default argument promotions

An argument past a **variadic** callee's fixed prefix has no declared parameter
type to convert toward, so it takes C's default argument promotions instead
(C17 §6.5.2.2p6) — the rule `va_arg` on the other side assumes:

- an integer narrower than C's `int` widens to `int`: `zext` for an unsigned
  source (`bool` among them, so `true` arrives as `1`), `sext` for a signed
  one;
- `f32` widens to `f64`;
- everything already `int`-wide or wider is untouched, including `Char` (a
  `ui32`) and `usize`/`ssize` (pointer-width).

So `(printf "%d %f\n" n:i16 x:f32)` passes an `i32` and a `double`, exactly as
the equivalent C does. The target is the **target's** C `int` — 16-bit on AVR,
32-bit elsewhere — not Nucleus's `int` spelling, which is a fixed alias for
`i32`.

A variadic callee's **fixed** parameters are ordinary typed slots and take the
rules above; only the `...` tail is promoted. A materialized `StrView` in the
tail contributes just its `data` pointer — see [Strings](strings.md).

### Condition position is an elimination, not a coercion

A nullable value — `ptr`, `(ptr T)`, `CStr`, `?T`, or a value `(Maybe T)` — is accepted
directly as a condition at the six condition sites and eliminated to `bool`
there. That rule is **not** part of the coercion set above, and `bool` is not a
universal sink: a `bool` parameter, `defstruct` field, `let`/`with` slot,
`set!` target or `return` still refuses a pointer, and `(defn g (b:bool))` does
not become a dispatch candidate for every call.

```lisp
(defn g (b:bool):i32 …)
(when p …)      ; fine — p is a condition
(g p)           ; error: argument 1 has type (ptr Pt), which does not match
                ;        parameter type bool
(let (b:bool p) …)   ; error: let: init type mismatch for 'b'
```

The full rule, including what stays a type error and why, is in
[Condition position](special-forms.md#condition-position-a-nullable-value-is-a-condition).

## Literal Values

| Name | Type | C Equivalent |
|------|------|--------------|
| `null` | ptr | `NULL` |
| `true` | `bool` | `1` / `true` |
| `false` | `bool` | `0` / `false` |
| `"…"` string literal | `StrView` | `"…"` (a `char*`/`{ptr,len}` view — see above) |
| `c"…"` string literal | `CStr` | `"…"` (bare `char*`, no view header) |
| `\a`, `\newline`, `\u{1F600}` char literal | `Char` | `(uint32_t)U'…'` |

**Integer literals** carry their full value (lexed as up to a 64-bit magnitude:
signed `i64` down to `-2^63`, unsigned up to `2^64-1`; a literal outside that
range is a positioned reader error). An integer literal has no intrinsic type —
it *adapts* to whatever integer (or float) type its context needs, wherever the
value fits: it passes to a wider or narrower parameter, `let`/field slot, or
binop operand as long as it is representable there (see *Implicit Type
Coercion*). When a literal's type is not otherwise constrained, it emits as
`i32` if it fits and `i64` otherwise, so `(take64 5000000000)` yields
`5000000000` (not a 32-bit wrap) while an out-of-range use like
`(take-i32 5000000000)` is a compile-time error. (Typed *values*, unlike
literals, only widen same-sign — see the coercion rules above.)

The same width rule and the same range check apply to a **named** constant. An
unannotated `defconst` is typed by its value, not fixed at `i32`: `(defconst BIG
5000000000)` is `i64`, so `(let (x:i64 BIG) …)` yields `5000000000`, while
`(let (x:i32 BIG) …)` and `(defvar g:i32 BIG)` are compile-time errors rather
than a silent 32-bit wrap. Enum members are always small enough to be `i32`.

`bool` is not a destination for an integer literal at all — it takes no part in
this adaptation. `true` and `false` are `bool`'s own literals, and `0`/`1` are
**not** numeric spellings of them: `(defvar g:bool 1)` is a type mismatch, the
same as any other integer literal assigned to a non-integer slot (see the
`bool` bullet under *Implicit Type Coercion* above).

## String literal escapes — `\n`, `\xHH`

Inside a `"…"` (or `c"…"`) string literal, a backslash introduces an escape.
The complete set:

| Escape | Byte | Notes |
|--------|------|-------|
| `\n` | 0x0A | newline |
| `\t` | 0x09 | tab |
| `\r` | 0x0D | carriage return |
| `\0` | 0x00 | NUL — but see the truncation note below |
| `\\` | 0x5C | a literal backslash |
| `\"` | 0x22 | a literal double quote |
| `\xHH` | 0x00–0xFF | a raw byte as **one or two** hex digits, either case |
| `\uXXXX` | 1–3 bytes | the UTF-8 encoding of a codepoint, as **exactly four** hex digits (EDN's and Java's spelling); a surrogate `D800`–`DFFF` is refused |

Any other character after a backslash is a positioned reader error
(`unknown escape \<c>`); a `\x` with no following hex digit is likewise an
error (`\x escape needs at least one hex digit`).

**`\x` is capped at two hex digits — this is a deliberate difference from C.**
C's `\x` is *greedy*: it consumes every following hex digit, so C's `"\x41BC"`
is a single character whose value overflows. Nucleus stops after two digits, so
`"\x41BC"` is the three characters `A`, `B`, `C` (0x41, then the ordinary
literal characters `B` and `C`). Two digits express every byte, so the cap costs
nothing in practice and removes C's run-on footgun. One digit is accepted where
unambiguous — `"\xa"` and `"\x0a"` are the same byte.

```lisp
"MUS\x1a"        ; four bytes: 'M' 'U' 'S' 0x1A
"\x1b[0m"        ; an ANSI reset sequence
"\xff\xFF"       ; two 0xFF bytes — hex digits are case-insensitive
"\x41BC"         ; three characters: 'A' 'B' 'C'  (NOT one, as in C)
```

Note the `\x` spelling means something different in the two literal contexts:
inside a string, `"\x41"` is the escape for byte 0x41, while the standalone
*char literal* `\x` is the single printable character `x` (codepoint 120) — char
literals use `\u{…}` for a hex codepoint, as described in the next section.

**A string literal may carry an embedded NUL.** The reader decodes escapes into
a counted buffer and the token keeps the count, so both `"x\0y"` and `"x\x00y"`
are length 3. The bytes are also NUL-terminated, so a literal passed to a `CStr`
seam still reads as a C string — it just stops at the embedded NUL there, which
is C's rule, not the literal's.

## Char literals — `\a`

A **char literal** is a backslash followed by one of three forms, evaluating to a self-evaluating `Char` value (a Unicode scalar). The leading `\` collides with neither keywords (leading `:`) nor strings (`"`), so it is unambiguous:

| Form | Meaning | Example |
|------|---------|---------|
| `\a` | A single printable codepoint — the character after the backslash | `\A` → 65, `\x` → 120, `\(` → 40 |
| `\name` | A named control code | `\newline` (0x0A), `\return` (0x0D), `\tab` (0x09), `\space` (0x20), `\nul` (0x00), `\escape` (0x1B), `\backspace` (0x08), `\delete` (0x7F) |
| `\u{HEX}` | An explicit codepoint as hex digits between braces | `\u{41}` → 65, `\u{1F600}` → 😀 (128512) |
| `\uXXXX` | A codepoint as exactly four hex digits — EDN's spelling, Basic Multilingual Plane only | `\u0041` → 65, `\u00e9` → é |

The `\u{…}` and `\uXXXX` forms are validated at read time: a value above `0x10FFFF`, a UTF-16 surrogate (`0xD800..=0xDFFF`), an empty or non-hex body, or an unknown `\name` is a reader error (`invalid-codepoint` / `unknown named char literal`). A lone printable form is exactly the byte after the backslash, so a single-character spelling like `\u` (no brace) is the letter `u`, not a malformed escape.

```lisp
(printf "%u\n" (as ui32 \A))            ; 65
(printf "%u\n" (as ui32 \newline))      ; 10
(printf "%u\n" (as ui32 \u{1F600}))     ; 128512
(printf "%d\n" (if (= \a \a) 1 0))      ; 1
```

The `(char "x")` special form is equivalent sugar for the single-byte case: `(char "x")` and `\x` both produce the `Char` with codepoint 120. See `examples/char-test.nuc`.

## Keyword literals — `:foo`

**Keywords** are interned, self-evaluating names written as a colon followed by a non-empty identifier: `:foo`, `:http-method`, `:ok`. A keyword literal evaluates to a canonical `Keyword` value; two keyword literals with the same spelling are identical (`(= :foo :foo)` is `true`; `(= :foo :bar)` is `false`). `!=` follows the same identity semantics.

A `Keyword` has static type `Keyword` and conforms to both `Hash` and `Eq`, making it a natural key type for `HashMap` and member type for `HashSet`.

**Requires `(import-use nucleus.keyword)`** — and transitively `(import-use nucleus.strview)`, `(import-use nucleus.hash)`, and `(import-use nucleus.numeric)`. Without the import the compiler emits `undefined: keyword-intern`. See [Keywords and StrView](stdlib.md#strview-libstrviewnuc) for the full API.

```lisp
(import-use "stdio.h")
(import-use nucleus.strview)
(import-use nucleus.hash)
(import-use nucleus.keyword)
(import-use nucleus.allocator)
(import-use nucleus.coll)
(import-use nucleus.iterator)
(import-use nucleus.hashmap)

(defn main ():i32
  ; Self-evaluation.
  (let (k:Keyword :foo)
    (printf "self-eval=%d\n" (if (= k :foo) 1 0)))    ; 1

  ; Identity equality.
  (printf "foo=foo? %d\n" (if (= :foo :foo) 1 0))     ; 1
  (printf "foo=bar? %d\n" (if (= :foo :bar) 1 0))     ; 0

  ; Keywords as HashMap keys.
  (with ((m (ref (HashMap Keyword i32))) (alloca (HashMap Keyword i32)))
    (hashmap-init m)
    (assoc m :a 1)
    (assoc m :b 2)
    (match (hmap-get m :a)
      ((some v) (printf "a=%d\n" v))                   ; a=1
      (none     (printf "absent\n"))))
  (return 0))
```

**Syntax disambiguation.** The keyword reader rule fires only when the entire atom starts with `:` and has a non-empty remainder. It does **not** interfere with:

- **Colon-chain type syntax** (`ptr:i8`, `ref:Foo`) — the colon is interior, not leading.
- **Colon-paren binding sugar** (`name:(ref T)`) — the colon is trailing on the name token; the paren that follows is read as a type expression.
- A bare `:` by itself remains a plain symbol.

The [`&` type sigil](#pointer-kinds-t-t-and-ptr-t) *does* apply inside a
keyword's name, which is what makes the keyword-led return spelling `):&T` work
(the body `&T` expands to `ref:T` exactly as the bare symbol would). The
consequence to know: a keyword **value** written `:&x` reads as `:ref:x`.

**No intern pool limit.** Since Stage 17 a keyword is one interned `Symbol` (`lib/nucleus/intern.nuc`), whose table is open-addressed and grows. The old fixed 256-entry pool, and the abort past it, are gone.

## Symbols

A symbol is a `Node*` with `kind = NODE-SYM` and `s` pointing to its spelling. Symbols are **interned**: any two symbols with the same spelling are the same `Node*`, so identity is comparable with plain `=`.

```lisp
(= 'foo 'foo)              ; true — both forms read to the same Node*
(let (h (head form))
  (= h 'defn))             ; true iff the head symbol of `form` spells "defn"
```

The interning is global to the process. The reader interns at lex time, and `quote` of a symbol calls `intern-symbol` at runtime so a quoted symbol and a reader-produced symbol with the same spelling are bit-identical pointers. The canonical-node table lives in `lib/nucleus/node.nuc` (the interned bytes themselves in `lib/nucleus/intern.nuc`), which a program that writes a quote imports with `(import-use nucleus.node)` — the prelude registers the `Node` *type* but no longer emits the runtime (see [The node runtime is a library](toplevel.md#the-node-runtime-is-a-library)). Beyond the import, user code never has to touch the table directly.

`gensym` deliberately bypasses the intern table — `(gensym)` always returns a fresh unique `Node*` whose spelling (e.g. `__gs_0`) does not collide with anything else, so it is safe in hygienic macros.

Symbol identity replaces `strcmp` for matching known spellings. Prefer `(= h 'defn)` over `(= (strcmp (get h 's) "defn") 0)`.
