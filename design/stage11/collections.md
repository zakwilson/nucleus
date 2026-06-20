# Collection types

#### Designer

Nucleus needs reasonable default collection types and protocols defining the
common operations on them. The concrete types should be **libraries** — many
programs won't need, say, a `HashSet`. The protocols should be **core**.

These collections are **mutable and low-overhead, in the STL spirit** — not
Clojure's persistent/immutable structures. Operations like `conj` and `assoc`
**mutate in place**; that is the whole point of this first group of collections,
and it is what gives them their efficiency. (A persistent/immutable collection
family with a Clojure-style concurrency story is conceivable as a far-future
stage; it is explicitly *not* Stage 11.)

The compiler itself should adopt these — as in prior stages, dogfooding the new
feature in the compiler is a **near-end-of-stage step**, after the types and
protocols are stable, not the opening move.

#### Robot — design notes

This design is gated on machinery that does not exist yet; see **Prerequisites**.
The collection *types* are parametric structs; the *transforms* are lazy over an
iterator protocol; the *memory* is explicitly owned and freed through an allocator
protocol plus `with`/`Drop`. Where this doc borrowed Clojure names (`conj`,
`assoc`, `into`, `doseq`) the **semantics are mutable/eager-or-lazy as specified
below**, not persistent.

## Prerequisites (must land first)

1. **Parametric structs** — `(Vector T)`, `(HashMap K V)`, `(HashSet T)` are
   generic structs. Designed in **[parametric-structs.md](parametric-structs.md)**.
   This is the critical path; nothing below compiles without it.
2. **Parametric protocols** — `Coll`/`Seq`/`Assoc` range over an element/key/value
   type, so they need an element parameter bound at `extend`
   (`(extend (Vector T) (Seq T))`). Scoped in parametric-structs.md §5.
3. **`usize` / `ssize` builtin scalars** — the pointer-sized index/length type
   (below) is not yet spellable in `.nuc` source. parametric-structs.md §8.
4. **`Hash` protocol** — `HashSet`/`HashMap` cannot exist without it (see Protocols).

## Memory model

These collections **own heap memory** (a `Vector` owns its element buffer, a
`HashMap` owns its bucket array), so two things are mandatory:

- **`Drop` conformance.** Every owning collection conforms to the Stage 10 `Drop`
  protocol so a `with`-bound collection frees its buffer on scope exit, and the
  Stage 10 escape/taint analysis already prevents an owned collection from escaping
  by return or store-out without a `move`. Nesting (a `Vector` of owning elements)
  drops elements before the buffer, per the existing union/`Drop` rule.
- **An allocator protocol** — explicit allocator choice with a sensible default,
  roughly Zig-shaped:

  ```lisp
  (defprotocol Allocator
    (alloc:(raw u8)   (self:(ref Self) size:usize align:usize))
    (realloc:(raw u8) (self:(ref Self) p:(raw u8) old:usize new:usize align:usize))
    (free:void        (self:(ref Self) p:(raw u8) size:usize align:usize)))
  ```

  - **Explicit choice.** Constructors take an allocator: `(vector-new alloc)`,
    `(vector-with-capacity alloc n)`. The collection stores the allocator handle so
    `conj`/`assoc`/`Drop` use the same one that built it.
  - **A default.** A global default allocator (libc `malloc`/`realloc`/`free` behind
    the protocol) backs convenience constructors that omit the allocator
    (`(vector-new)`), so the common case doesn't make the user think about it. The
    existing `lib/arena.nuc` is a ready second implementation (arena/bump: `free` is
    a no-op, the whole arena is released at once).
  - **Plumbing (decided): stored field.** The allocator handle is a stored field on
    every owning collection (one pointer, negligible against a heap buffer);
    `conj`/`assoc`/`Drop` use the handle the collection was built with. The
    type-parameter form `(Vector T A)` (zero-overhead, monomorphized per allocator)
    is the escape hatch if that pointer ever matters — not v1.

## Index and size type

`count`, lengths, and integer indices are **`usize`** (target-pointer-sized
unsigned; `ssize` is the signed companion — see Prerequisites 3). `get`-by-index and
`insert` take `usize`.

## Protocols (core)

```
Coll   — count, conj, iter, empty?     (extends Eq)
Seq    — map, reduce, filter, append, prepend, insert, get, find, contains?
Assoc  — get, assoc, dissoc, keys, vals, select-keys
Set    — union, difference, intersection, select, contains?
Str    — (its own doc; see below)
Hash   — hash    (its own lib; required by HashSet/HashMap)
```

All foreseeable collections extend `Coll`. **`Coll` extends `Eq`** — collections
compare structurally, which is also what lets a collection be a `HashMap` key or
`HashSet` member (together with `Hash`).

### Coll

Shipped as `(Coll E It)` — element type `E` and associated iterator type `It` (C2.1). `It` must conform to `(Iterator E)`.

- `count` → `usize`
- `conj` — add a value in the way most natural/efficient for the collection
  (append for vector, insert for set/map), **mutating in place** (Clojure's name,
  not its persistence).
- `iter` → `It` by value — associated iterator type, returned using the alloca+set+deref convention (C2.1).
- `empty?` → `i32` (1 if empty, 0 otherwise).

### Seq

- `map` / `reduce` / `filter` — **lazy Iterator combinators** (see Iteration and
  §Functions as arguments). They are **not** `Seq` protocol methods; they live in
  `lib/iterator.nuc` and take a `UnaryFn`/`FoldFn` function-object as first argument.
- `append` / `prepend` — mutating add at the back / front.
- `insert` (index) / `get` (index) — `usize` index.
- `find` — first element satisfying a predicate function-object, as `(Maybe E)`.
- `contains?` — membership of one element, `bool`.

`get` here is **index access**: `(s i)` with an integer routes to `invoke`
(callable-values.md), distinct from `(s 'field)` symbol-selector member access
which routes to the `get` field generic. The two coexist because dispatch is by
argument type; this doc's `Seq.get`/`Assoc.get` are the `invoke`/key-access methods,
not the field `get`.

### Assoc

- `get` (key) → `(Maybe V)` — in protocol as of C2.2a.
- `assoc` (key val) — insert/overwrite, **mutating**.
- `dissoc` (key) — remove, mutating.
- `keys` / `vals` → associated iterator types `Ki` / `Vi` returned by value — in protocol as of C2.2b (`(Assoc K V Ki Vi)`).
- `select-keys` (keys) → a new map restricted to the given keys — not in protocol (standalone, deferred).

### Set

- `union` / `difference` / `intersection` — set algebra, **mutating the receiver**
  (the in-place, efficient form is the primitive for the `HashSet` this stage adds).
  A fresh-result variant, if wanted later, is just `iter` + `into`.
- `select` (a predicate function-object) — the subset of members satisfying the
  predicate (filter on a set). Standalone; not a `Set` protocol method (see §Set
  above and C2.3 in `design/stage11/cleanup2.md`).
- `contains?` (value) — membership, `bool`. (This subsumes the earlier "`get`
  (value)": a set's fundamental query is membership, so it is `contains?`, not
  `get`.)

### Hash (its own lib)

Required by `HashSet`/`HashMap`. A type is hashable by providing `hash`:

```lisp
(defprotocol Hash
  (hash:usize (self:(ref Self))))
```

Built-in conformances for the scalar types and `CStr` ship with the lib (the
compiler already has `intern-hash`/`hash-struct-shape` to model these on). Keys and
set members must conform to `Hash` **and** `Eq`.

### Str

`String` is **its own design doc** (see Types → String). Indexing a UTF-8 string is
*not* O(1) random access, so `Str` does **not** simply `extend Seq`; it exposes
byte and codepoint iterators instead. `upcase`/`downcase` are Unicode/locale-fraught
and are deferred into that doc rather than treated as trivial core ops.

## Iteration (lazy transforms)

`map`/`reduce`/`filter` are **lazy over iterators**, not eager
collection-returning operations. This is the zero-overhead choice: chained
transforms compose with no intermediate allocation, and nothing needs an owner/
`Drop` until you materialize.

```lisp
(defprotocol Iterator
  (next:(Maybe E) (self:(ref Self))))
```

- **`next` returns `(Maybe E)` and mutates the iterator.** `none` means the scan is
  complete. (Value `(Maybe T)` over non-pointer `E` already exists — Stage 10 E2.)
- **Not concurrency-safe.** A single-threaded forward cursor; sharing one across
  threads is out of scope here.
- **`map`/`filter`** wrap an iterator in a new lazy iterator (`MapIter`/`FilterIter`,
  a small struct holding the source iterator + the function object); **`reduce`**
  drives an iterator to a value.
- **`into`** materializes an iterator into a concrete collection —
  `(into (Vector i32) some-iter)` — and is therefore **required** (it is how lazy
  pipelines become owned data). `into` is also the target of the reader-macro
  literals.
- **`doseq`** — a macro that drives an iterator for side effects:
  `(doseq (x coll) …)` expands to a `next`/`match`/loop over `(iter coll)`,
  terminating on `none`. The eager counterpart to `for`/`dotimes` for collections.

Bidirectional iteration (`prev`) is **deferred**: it only makes sense for
doubly-linked/random-access sources and wants a separate `BiIterator` protocol. Not
in Stage 11.

## Functions as arguments

`map`/`reduce`/`filter` are implemented as generic lazy iterator combinators
(`MapIter`/`FilterIter`/`reduce` in `lib/iterator.nuc`), not as `Seq` protocol
methods. They take a function-object argument conforming to `(UnaryFn Arg Ret)` or
`(FoldFn Acc Elem)` — the element-generic replacements for the old fixed-type `Call`
protocol. The `Call`/`BinaryCall` protocols in `lib/seq.nuc` were legacy
fixed-`ptr`-typed variants and have been removed (C2.5, `design/stage11/cleanup2.md`).
Lambdas/closures remain deferred (stage999); function objects are the current idiom.

## Types (libraries)

Collections contain values of a **homogeneous** type. Heterogeneous collections are
deferred until `dyn` (stage999).

The types get **reader-macro** sugar. The macro infers the element type from the
literal's elements and expands to the explicit constructor form
(`((T-instance) …)`, parametric-structs.md §6):

```
[1 2 3]            -> ((Vector i32) 1 2 3)
{"foo" 42 "bar" 7} -> ((HashMap CStr i32) "foo" 42 "bar" 7)
#{"dog" "cat"}     -> ((HashSet CStr) "dog" "cat")
```

- **Element-type inference** uses the language's real scalar names (`i32`/`i64`/
  `f64`/`CStr`/…), not `'int`. **Mixed-element literals are an error**: `[1 2.0 3]`
  does not widen — write `[1.0 2.0 3.0]` or construct explicitly.
- **Empty literals.** `[]` / `{}` / `#{}` are errors — the element type can't be
  inferred. Use the explicit constructor: `(vector-new)` / `((Vector i32))`.
- These literals build with the **default allocator**; an explicit-allocator
  collection uses the constructor directly.

### Vector

Dynamically-sized sequence, like C++ STL `vector`. O(1) `get`/append/prepend
(amortized for append via capacity doubling), O(n) `insert`. Owns its buffer
through the allocator.

**Capacity operations.** The ideal is that the user never thinks about capacity, but
this is a systems language and the built-in vector should cover demanding uses.
Options (pick a subset):

- **Minimal (recommended baseline):** automatic growth only (amortized doubling);
  no user-facing capacity surface. Covers most code.
- **STL-like (recommended to also ship):** `capacity`, `reserve n`,
  `shrink-to-fit` — opt-in control for hot paths and known-size builds.
- **Maximal:** the above plus `with-capacity` constructor, `resize`, raw
  `set-len!`/`data` access for unsafe bulk fills.

Recommend **Minimal + `reserve`/`capacity`/`with-capacity`**: zero-think by default,
escape hatch for the cases that need it, without the full unsafe surface.

### HashSet

O(1) `contains?`/`insert`/delete. Elements conform to `Hash` + `Eq`.

### HashMap

O(1) `get`/`assoc`/delete. Keys conform to `Hash` + `Eq`.

### String

Split into its own design doc (Stage 11 or later). Requirements captured here:

- C strings (`CStr`) were enough to bootstrap and must stay for interop, but are not
  a reasonable default in 2026.
- `String` is **UTF-8 and memory-safe**, plausibly built on `Vector` (`Vector u8`).
- Indexing is **not** O(1) random access over codepoints, so `String` exposes
  **byte and codepoint iterators** rather than pretending to be a random-access
  `Seq`. (This is why `Str` does not blanket-`extend Seq`.)
- Switching **string literals** to `String` should come *after* collections are
  stable — the compiler uses `CStr` heavily and that migration is part of the
  end-of-stage compiler-adoption step, not the start.

## Compiler adoption (end-of-stage)

Once the types and protocols are stable, adopt them in the compiler — the standard
late-stage dogfooding step. Sequence with care: the collections are written in
Nucleus, used by the compiler, which compiles them (a bootstrap cycle), so
parametric structs, `Drop`, and the allocator protocol must be rock-solid first.
The `CStr` → `String` literal switch is the riskiest piece and comes last.

## Staging

1. **Prerequisites:** parametric structs (its own doc), `usize`/`ssize` scalars,
   parametric protocols, `Hash` lib.
2. **Allocator protocol** + default (libc) + arena conformance.
3. **`Iterator`** protocol, `into`, `doseq`; lazy `map`/`filter`/`reduce`.
4. **`Vector`** (+ chosen capacity ops), `Coll`/`Seq` conformance, `Drop`.
5. **`HashSet` / `HashMap`** on `Hash`, `Coll`/`Set`/`Assoc` conformance.
6. **Reader-macro literals** `[…]` / `{…}` / `#{…}` → constructors.
7. **`String`** (own doc) and the literal switch.
8. **Compiler adoption.**

## Deferred

- Subsequence features (`match?` subsequence search, `subseq`/slice) — entangle with
  the deferred bounds-checked-slices work; out of Stage 11.
- `BiIterator` / `prev`.
- Persistent/immutable collections + Clojure-style concurrency — far-future stage.
- Heterogeneous collections — need `dyn` (stage999).
- Lambdas/closures — `map`/`filter` use function-object protocols (`UnaryFn`/`FoldFn`) until then (stage999).
</content>
