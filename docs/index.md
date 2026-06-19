# Nucleus Language Reference

Nucleus is a compiled systems programming language with Lisp-style syntax, a strong static type system, and zero-cost abstractions. It compiles directly to native code via LLVM with a C-compatible ABI.

## Core principles

- **Lisp syntax, systems semantics**: parenthesized S-expression syntax; semantics close to C with explicit memory management and no GC
- **C interop first**: imports C headers directly (`include`, `import`), exports C-legible types and functions (`.nuch` headers, `--emit-cheader`)
- **Zero-cost generics**: multimethods, protocols, and bounded generics resolved entirely at compile time — no vtables, no runtime dispatch objects
- **Explicit nullability**: `(ptr T)` / `(ref T)` are non-null by default; nullable pointers are `?T` or `(raw T)`, explicit at each declaration

## Quick start

```
nucleusc hello.nuc -o hello && ./hello
```

Source files contain top-level forms (`defn`, `defvar`, `defstruct`, etc.). A `main:i32 ()` function is the entry point. The interactive REPL is available via `nucleusc -i`.

## Hello, world

```lisp
(include stdio)

(defn main:i32 ()
  (printf "Hello, world!\n")
  0)
```

## Key syntax

**Functions** — return type follows the function name; parameter types follow each parameter name:
```lisp
(defn add:i32 (a:i32 b:i32)
  (+ a b))
```

**Variables** — `let` for locals, `defvar` for globals:
```lisp
(let (x:i32 42)
  (printf "%d\n" x))
```

**Structs** — defined with `defstruct`, constructed as compound literals:
```lisp
(defstruct Point x:i32 y:i32)
(let (p:ptr:Point (Point (x 10) (y 20)))
  (printf "%d %d\n" (p x) (p y)))
```

**Pointers** — non-null by default, with explicit nullable variants:
```lisp
(defn takes-point ((p ref:Point)) ...)  ; p is always a valid Point
(defvar nullable:?ptr:Point)            ; may be none
```

**Generics** — use protocols and bounded `defn`:
```lisp
(import numeric)
(defn maxv:T (a:T b:T &where (Ord T))
  (if (< a b) b a))
(maxv 3 9)    ; → 9 (stamps @maxv.i32.i32)
(maxv 2.5 1.5) ; → 2.5 (stamps @maxv.f64.f64)
```

**Errors** — fallible functions return `!T` (= `(Result T Err)`):
```lisp
(deferror not-found "item not found")
(defn lookup:!i32 (key:i32)
  (when (= key 0) (return (err not-found)))
  (return (ok key)))
(match (lookup 42)
  ((ok v)  (printf "found: %d\n" v))
  ((err e) (printf "error: %s\n" (err-name e))))
```

## Reference sections

| Document | Contents |
|----------|----------|
| [Compiler](compiler.md) | Flags (`-O`, `--emit-llvm`, `--target`, …), REPL, `.nuch` header format |
| [Top-level forms](toplevel.md) | `defn`, `defvar`, `defstruct`, `defunion`, `defprotocol`, `import`, `defmacro`, … |
| [Types](types.md) | Built-in types, pointer kinds (`ptr`/`ref`/`raw`/`?T`), volatile, function pointer types, coercions, literals, keyword literals (`:foo`), symbols |
| [Structs and unions](structs-unions.md) | Anonymous structs, passing by value, `defunion`, `match`, niche layout, parametric struct templates |
| [Special forms](special-forms.md) | Control flow, memory ops, `with`/`move`/`defer`, binary operators, callable values (`get`/`invoke`) |
| [Macros](macros.md) | Standard macros (`if`, `when`, `for`, `dotimes`, `->`), variadic arithmetic, writing macros |
| [Generics](generics.md) | Multimethods, `defprotocol`/`extend`, parametric protocols, bounded `&where` generics |
| [Error handling](errors.md) | `deferror`, `!T`, `try`/`unwrap`, `with-handler`, `signal` |
| [Standard library](stdlib.md) | Pre-declared libc bindings (stdio, stdlib, string, ctype, unistd); `StrView` byte-slice substrate (`lib/strview.nuc`); `Keyword` interned names (`lib/keyword.nuc`) |
| [Allocators](allocators.md) | `Allocator` protocol, `AllocHandle`, libc/arena backends (`lib/allocator.nuc`) |
| [Iterators](iterators.md) | `Iterator` protocol, concrete iterators, lazy combinators, reduce (`lib/iterator.nuc`) |
| [Collections](collections.md) | Core collection protocols (`Coll`/`Seq`/`Assoc`/`Set`/`Drop`), `Hash`, `Vector`, `HashMap`, `HashSet` (`lib/coll.nuc`, `lib/hash.nuc`, `lib/vector.nuc`, `lib/hashmap.nuc`, `lib/hashset.nuc`) |

## Standard library overview

The prelude (`lib/prelude.nuc`) is auto-imported into every program and provides:
- The `Node` struct and `NODE-*` enum (for macro AST manipulation)
- All standard macros (`if`, `when`, `unless`, `for`, `dotimes`, `->`, `case`, etc.)
- `(include string)` declarations for `strlen`, `strcmp`, `memcpy`, etc.

Additional libraries available via `import`:
- `(import macros)` — standard macros (already in prelude)
- `(import numeric)` — `Eq`, `Ord`, `Num` protocols for operators
- `(import error)` — `try`, `with-handler`, `signal`, `err-find-handler`
- `(import arena)` — arena allocator + `(new T)` convenience macro
- `(import allocator)` — `Allocator` protocol and `AllocHandle`
- `(import iterator)` — `Iterator` protocol and concrete iterators
- `(import coll)` — core collection protocols (`Coll`, `Seq`, `Assoc`, `Set`, `Drop`)
- `(import strview)` — `StrView` immutable byte-slice substrate (`Hash`+`Eq` conformances)
- `(import keyword)` — `Keyword` interned self-evaluating names, usable as `HashMap`/`HashSet` keys
- `(import hash)` — `Hash` protocol with `i32`/`i64`/`usize`/`CStr` conformances (FNV-1a)
- `(import vector)` — `Vector T` dynamic array and `VecIter T`
- `(import hashmap)` — `HashMap K V` and `HashMapKeyIter K V`
- `(import hashset)` — `HashSet T` and `HashSetIter T`
- `(import seq)` — `IntIndexable`, `Call` protocols

Use `(exclude-prelude)` as the first form in a file to suppress the auto-import and compile against the bare language.
