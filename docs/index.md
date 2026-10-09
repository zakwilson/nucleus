# Nucleus Language Reference

Nucleus is a compiled systems programming language with Lisp-style syntax, a strong static type system, and zero-cost abstractions. It compiles directly to native code via LLVM with a C-compatible ABI.

## Core principles

- **Lisp syntax, systems semantics**: parenthesized S-expression syntax; semantics close to C with explicit memory management and no GC
- **C interop first**: imports C headers directly (`import-use`, `import`), exports C-legible types and functions (`.nuch` headers, `--emit-cheader`)
- **Zero-cost generics**: multimethods, protocols, and bounded generics resolved entirely at compile time — no vtables, no runtime dispatch objects
- **Explicit nullability**: `&T` is non-null, `?&T` is nullable and must be narrowed before use, and `(ptr T)` is the explicit, unchecked escape — the kind is visible at each declaration

## Quick start

```
nucleusc hello.nuc -o hello && ./hello
```

Source files contain top-level forms (`defn`, `defvar`, `defstruct`, etc.). A `main:i32 ()` function is the entry point. The interactive REPL is available via `nucleusc -i`.

## Hello, world

```lisp
(import-use "stdio.h")

(defn main ():i32
  (printf "Hello, world!\n")
  0)
```

## Key syntax

**Functions** — return type follows the function name; parameter types follow each parameter name:
```lisp
(defn add (a:i32 b:i32):i32
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
  (printf "%d %d\n" (p 'x) (p 'y)))
```

**Pointers** — non-null by default, with explicit nullable variants:
```lisp
(defn takes-point ((p ref:Point)) ...)  ; p is always a valid Point
(defvar nullable:?ptr:Point)            ; may be none
```

**Generics** — use protocols and bounded `defn`:
```lisp
(import-use nucleus.numeric)
(defn maxv (a:T b:T :where (Ord T)):T
  (if (< a b) b a))
(maxv 3 9)    ; → 9 (stamps @maxv.i32.i32)
(maxv 2.5 1.5) ; → 2.5 (stamps @maxv.f64.f64)
```

**Markers are keywords** — the four positional markers a definition form can
carry are `:rest`, `:optional` ([`defn`](builtins.md#defn) / [`defmacro`](macros.md)),
`:where` ([bounded generics](generics.md#bounded-generic-defn) and
[`extend`](generics.md#conforming-combinators-where-on-extend)) and `:repr`
([union layout](structs-unions.md#niche-layout-and-repr-stage-10-c4)), matching
the declaration attributes `:const` and `:volatile`. They were once spelled
`&rest` / `&optional` / `&where` / `&repr`; in a parameter list the ampersand
forms are now a compile-time error naming their replacement. In an expression
they are ordinary address-of: `&rest` is `(ref rest)`.

**Errors** — fallible functions return `!T` (= `(Result T Err)`):
```lisp
(deferror not-found "item not found")
(defn lookup (key:i32):!i32
  (when (= key 0) (return (err not-found)))
  (return (ok key)))
(match (lookup 42)
  ((ok v)  (printf "found: %d\n" v))
  ((err e) (printf "error: %s\n" (err-name e))))
```

## Reference sections

| Document | Contents |
|----------|----------|
| [Compiler](compiler.md) | Flags (`-O`, `--emit-llvm`, `--target`, …), diagnostics (locations, unresolved names, did-you-mean), REPL, `.nuch` header format |
| [Top-level forms](toplevel.md) | `defn`, `defvar`, `defstruct`, `defunion`, `defprotocol`, `import`, `defmacro`, … |
| [Types](types.md) | Built-in types, pointer kinds (`&T`/`?&T`/`(ptr T)`), volatile, function pointer types, coercions, literals, keyword literals (`:foo`), symbols |
| [Structs and unions](structs-unions.md) | Anonymous structs, passing by value, `defunion`, `match`, niche layout, parametric struct templates, C header struct/array ingestion, opaque types, C typedefs as type names |
| [Special forms](special-forms.md) | Control flow, memory ops, `with`/`move`/`defer`, binary operators, callable values (`get`/`invoke`) |
| [Macros](macros.md) | Standard macros (`if`, `when`, `for`, `dotimes`, `->`), variadic arithmetic, writing macros |
| [Generics](generics.md) | Multimethods, `defprotocol`/`extend`, parametric protocols, bounded `:where` generics |
| [Error handling](errors.md) | `deferror`, `!T`, `try`/`unwrap`, `with-handler`, `signal` |
| [Standard library](stdlib.md) | Pre-declared libc bindings (stdio, stdlib, string, ctype, unistd); `StrView` byte-slice substrate (`lib/nucleus/strview.nuc`); `Symbol` interned identity (`lib/nucleus/intern.nuc`); `Keyword` interned names (`lib/nucleus/keyword.nuc`) |
| [Allocators](allocators.md) | `Allocator` protocol, the `Alloc` handle, `Heap`/`Arena`/`FixedBuffer`/`Tracking` (`lib/nucleus/allocator.nuc`); `Init`/`InitFrom`/`TryInitFrom` and the `new`/`make` macros (`lib/nucleus/create.nuc`) |
| [Iterators](iterators.md) | `Iterator` protocol, concrete iterators, lazy combinators, reduce (`lib/nucleus/iterator.nuc`) |
| [Collections](collections.md) | Core collection protocols (`Coll`/`Seq`/`Assoc`/`Set`/`Drop`), `Hash`, `Vector`, `HashMap`, `HashSet` (`lib/nucleus/coll.nuc`, `lib/nucleus/hash.nuc`, `lib/nucleus/vector.nuc`, `lib/nucleus/hashmap.nuc`, `lib/nucleus/hashset.nuc`) |
| [Strings](strings.md) | `Char` scalar, `StrView` borrowed slice, `String` owning type, UTF-8 encode/decode, `ByteStr`/`Str` protocols, split, lines, trim, `FromStr`/`parse`, `Writer`/`ToStr`/`str` formatting, and which of `StrView`/`String`/`Symbol`/`CStr` to reach for (`lib/nucleus/char.nuc`, `lib/nucleus/strview.nuc`, `lib/nucleus/string.nuc`, `lib/nucleus/parse.nuc`, `lib/nucleus/string-split.nuc`, `lib/nucleus/fmt.nuc`) |
| [Processes](process.md) | Starting other programs: `Command` as an argv (never a shell command line), `run`, `spawn`/`wait-any` for a job pool, typed `ExitStatus` (`lib/nucleus/process.nuc`) |
| [Reading s-expressions](reading.md) | Text to `Node` at runtime: `read-all`, the `Reader`/`read-one` pair, `node-write`/`node-eq`; agrees with the compiler's own reader; EDN mode (`lib/nucleus/read.nuc`) |
| [EDN](edn.md) | EDN data as a typed view over the reader's `Node`: `edn-parse`, `edn-kind` and accessors, `edn-write`, range-checked `edn-read` conversions, the `EdnCodec` protocol over collections, and `derive-edn` struct codecs (`lib/nucleus/edn.nuc`) |
| [Testing](testing.md) | Declaring tests with `deftest`, the `check-*` assertions, scoped IR matching, `fail!`, and the EDN result records a suite prints (`lib/nucleus/test.nuc`) |
| [I/O](io.md) | Standard streams and files as `Writer`s over raw descriptors: `FdOut`, `print`/`println`/`eprint`/`eprintln`, `read-line`, `File`, `BufWriter` (`lib/nucleus/io.nuc`, `lib/nucleus/file.nuc`) |
| [AVR targets](avr.md) | Cross-compiling to 8-bit AVR microcontrollers: flags, a two-device walkthrough, the v1 profile and its exclusions, MMIO/ISR idioms (`lib/nucleus/avr.nuc`, `lib/nucleus/avr/*.nuc`) |

## Standard library overview

The standard libraries live in `lib/nucleus/`, each in namespace `nucleus.<file>`
(see [The core libraries](toplevel.md#the-core-libraries-nucleus)). The prelude,
`nucleus.core` (`lib/nucleus/core.nuc`), is auto-imported into every program and provides:
- The `Node` struct and `NODE-*` enum (for macro AST manipulation)
- All standard macros (`if`, `when`, `unless`, `for`, `dotimes`, `->`, `case`, etc.)
- `(import-use "string.h")` declarations for `strlen`, `strcmp`, `memcpy`, etc.

Every one of those emits no IR, so a prelude-only program emits exactly one
definition: its own `main`. The node/arena **runtime** is not in the prelude — a
program that quotes, calls a `:rest` function, or writes `printf`/`malloc` imports
what it uses. See [The node runtime is a library](toplevel.md#the-node-runtime-is-a-library).

Additional libraries available via `import-use`:
- `(import-use nucleus.macros)` — standard macros (already in prelude)
- `(import-use nucleus.numeric)` — `Eq`, `Ord`, `Num` protocols for operators
- `(import-use nucleus.error)` — `try`, `with-handler`, `signal`, `err-find-handler`
- `(import-use nucleus.node)` — `alloc-node`, `node-int`, `intern-symbol`, the list API and `Node`'s `Coll`/`Seq` conformances: the runtime behind `'sym`, `` `(…) `` and a `:rest` call
- `(import-use nucleus.arena)` — the process arena `g-arena` and `arena-alloc`
- `(import-use nucleus.create)` — the `new` and `make` macros: an object in one call, from any allocator
- `(import-use nucleus.allocator)` — `Allocator` protocol, `Alloc`, `Heap`/`heap`, `Arena`, `FixedBuffer`, `Tracking`
- `(import-use nucleus.iterator)` — `Iterator` protocol and concrete iterators
- `(import-use nucleus.coll)` — core collection protocols (`Coll`, `Seq`, `Assoc`, `Set`, `Drop`)
- `(import-use nucleus.strview)` — `StrView` immutable byte-slice substrate (`Hash`+`Eq` conformances)
- `(import-use nucleus.strview-str)` — `ByteStr`/`Str` protocol conformances for `StrView` (separate to avoid circular imports)
- `(import-use nucleus.keyword)` — `Keyword` interned self-evaluating names, usable as `HashMap`/`HashSet` keys
- `(import-use nucleus.intern)` — `Symbol` interned identity and its table (libc + `fnv` only, so `node` can depend on it)
- `(import-use nucleus.intern-str)` — `Eq`/`Hash`/`ToStr`/`ByteStr`/`Str` conformances for `Symbol`
- `(import-use nucleus.fnv)` — the FNV-1a fold (`fnv1a-byte`, `fnv1a-int`, `fnv1a-bytes`)
- `(import-use nucleus.hash)` — `Hash` protocol with `i32`/`i64`/`usize`/`CStr` conformances (FNV-1a)
- `(import-use nucleus.vector)` — `Vector T` dynamic array and `VecIter T`
- `(import-use nucleus.hashmap)` — `HashMap K V` and `HashMapKeyIter K V`
- `(import-use nucleus.hashset)` — `HashSet T` and `HashSetIter T`
- `(import-use nucleus.char)` — `Char` UTF-8 encode/decode, classification, case conversion (`lib/nucleus/char.nuc`)
- `(import-use nucleus.string-errors)` — the six string/parse error codes as `deferror` symbols
- `(import-use nucleus.string-protocols)` — `ByteStr ByteI` and `Str CharI` read-only protocol shapes
- `(import-use nucleus.string)` — `String` owning type: constructors, mutation, conformances (`lib/nucleus/string.nuc`)
- `(import-use nucleus.string-split)` — `SplitIter`/`LineIter` for `strview-split`/`strview-lines` (`lib/nucleus/string-split.nuc`)
- `(import-use nucleus.read)` — the s-expression reader: text to `Node`, and back (`lib/nucleus/read.nuc`)
- `(import-use nucleus.edn)` — EDN data over the reader's `Node` tree, and codecs for scalars, collections and derived structs (`lib/nucleus/edn.nuc`)
- `(import-use nucleus.parse)` — `FromStr R` protocol and `parse` macro for `i32`/`i64`/`f64` (`lib/nucleus/parse.nuc`)
- `(import-use nucleus.seq)` — empty placeholder; `IntIndexable`, `Call`, and `BinaryCall` were removed in C2.5 (use `UnaryFn`/`FoldFn` from `(import-use nucleus.iterator)`)

Use `(exclude-prelude)` as the first form in a file to suppress the auto-import and compile against the bare language.
