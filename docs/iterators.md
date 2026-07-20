# Iterators (`lib/iterator.nuc`, Stage 11)

`(import-use iterator)` provides the `Iterator` parametric protocol, two concrete
iterator structs, function-object protocols, generic lazy combinators, and a
generic `reduce`.

## The `Iterator` protocol

```lisp
(defprotocol (Iterator E)
  ((next (Maybe E)) ((self (ref Self)))))
```

`E` is the element type. A conforming type provides a `next` method that
advances the iterator and returns `(some v)` for the next element or `none`
when exhausted. `next` takes `(ref Self)` because it mutates the iterator's
position. Use `(Maybe i32)` or `(Maybe i64)` (not `(Maybe ptr)`) as the element
type — `(Maybe ptr)` is niche-encoded as a nullable pointer and cannot be used
with `match`.

## Concrete iterators

| Type | Fields | Description |
|------|--------|-------------|
| `IntRangeIter` | `start:i32 end:i32` | Iterates `i32` values in `[start, end)`. Element type `i32`. |
| `I64ArrayIter` | `data:ptr:i64 pos:usize len:usize` | Iterates `i64` elements from a flat array. Element type `i64`. |

Both conform to `(Iterator i32)` / `(Iterator i64)` respectively.

**Constructing an iterator:** use `alloca` and `.set!` the fields, then pass a
`(ref IterType)` to `next` or to `doseq-iter`.

```lisp
(let ((r (ref IntRangeIter)) (alloca IntRangeIter))
  (.set! r start 1)
  (.set! r end 6)
  (doseq-iter (x r)
    (printf "%d\n" x)))   ; prints 1 2 3 4 5
```

**`doseq` vs `doseq-iter`.** Use `(doseq (var coll IterType) body...)` when the thing you are iterating is a **collection** conforming to `(Coll E It)` — `doseq` calls `(iter coll)` to get a fresh iterator by value. Use `(doseq-iter (var iter-ref) body...)` when you already hold a **bare iterator reference** — a `(ref IterType)` for a type that conforms to `(Iterator E)` but is not itself a `Coll` (e.g. `IntRangeIter`, `MapIter`, `FilterIter`, `HashMapKeyIter`). `doseq-iter` calls `(next iter-ref)` directly without going through `iter`. See [Macros](macros.md) for full signatures and the rationale for the explicit `IterType` argument.

## More concrete iterators (Stage 13 R1)

These conformers let `reduce` / `doseq-iter` reach cons-cell lists, C strings,
and string segments. `(Maybe StrView)` and other struct-payload Maybes fail to
compile in the macro-expansion JIT module (see [strings](strings.md) and
`context/build.md`), so an iterator whose logical element is a pointer or a
struct instead yields it as a **niche-encoded `(Maybe ptr)`** — a bare nullable
pointer, the same representation `?T` uses. `match`/`reduce`/`doseq-iter` all
accept it directly (representation-transparent elimination — see
[Unions and tagged sums](structs-unions.md#unions-and-tagged-sums)), and the
consumer recovers the concrete pointer type with a single `as` (bare `ptr` →
typed pointer is `as`'s elem-less-`ptr` "void*" hatch).

| Type (lib) | Conforms to | `next` yields | Recover with |
|------------|-------------|---------------|--------------|
| `ByteIter` (`strview`) | `(Iterator ui8)` | each byte | — (scalar) |
| `CharIter` (`strview`) | `(Iterator Char)` | each UTF-8 codepoint | — (scalar) |
| `ListIter` (`list`) | `(Iterator ptr)` | each cons element as a bare `Node*` | `(as ptr:Node e)` |
| `SplitIter` (`string-split`) | `(Iterator ptr)` | each segment as a `(ref StrView)` into the iterator's `cur` slot, yielded as a bare `ptr` | `(as ptr:StrView e)` |
| `LineIter` (`string-split`) | `(Iterator ptr)` | each line (same encoding as `SplitIter`) | `(as ptr:StrView e)` |

**Cons-cell lists — `ListIter`.** `(list-iter lst)` returns a `ListIter` by
value positioned at the head of a cons-cell list (`null` = empty). Drive it with
`doseq-iter` or `reduce`; each element arrives as a bare `Node*` pointer.

```lisp
(let (it:ListIter (list-iter lst))
  (doseq-iter (x (addr-of it))
    (printf "%lld\n" ((as ptr:Node x) i))))
```

**C strings and Strings — byte/char folds.** `(cstr-bytes cs)` / `(cstr-chars cs)`
(`lib/strview.nuc`) return a `ByteIter` / `CharIter` over a `CStr` (the NUL is
excluded). A `String` folds via `string-as-view` + `strview-bytes`/`strview-chars`.
This lets the FNV byte hash be written as a `reduce` over the byte iterator that
matches `strview-hash` exactly. See `examples/cstr-fold-test.nuc`.

**Lazy string splitting — `SplitIter` / `LineIter`.** These conform to
`(Iterator ptr)` (previously a done-flag-only API). The `(doseq-split (var iter-ref) body)`
macro (`lib/string-split.nuc`) hides the decode, binding `var` to a
`(ref StrView)` borrowing the iterator's `cur` slot (valid until the next step):

```lisp
(let (it:SplitIter (strview-split sv sep))
  (doseq-split (seg (addr-of it))
    (print-sv seg)))
```

The done-flag API (`split-iter-done`/`split-iter-next`, `lines-iter-done`/
`lines-iter-next`) is retained and yields identical segments. See
`examples/listiter-test.nuc`, `examples/split-iter-test.nuc`.

## Function-object protocols

These protocols let user-defined struct types serve as functions passed to
`MapIter`, `FilterIter`, and `reduce`. They replace the old `CallI64` /
`BinaryCallI64` protocols with generic versions.

| Protocol | Required method | Description |
|----------|----------------|-------------|
| `(UnaryFn Arg Ret)` | `(apply Ret) ((self (ref Self)) (x Arg))` | Maps one value to another: `Arg → Ret`. Used as the transform for `MapIter` and the predicate for `FilterIter`. |
| `(FoldFn Acc Elem)` | `(fold Acc) ((self (ref Self)) (acc Acc) (x Elem))` | Binary fold: `(Acc, Elem) → Acc`. Used by `reduce`. |

Define a struct and `extend` it with the desired protocol:

```lisp
; A fold function: sum two i64 values.
(defstruct SumI64 dummy:i32)
(extend SumI64 (FoldFn i64 i64))
(defn fold ((self (ref SumI64)) acc:i64 x:i64):i64
  (return (+ acc x)))

; A map function: square an i64.
(defstruct SquareI64 dummy:i32)
(extend SquareI64 (UnaryFn i64 i64))
(defn apply ((self (ref SquareI64)) x:i64):i64
  (return (* x x)))
```

## Lazy combinators

Both are **parametric structs** with type parameters `I` (source iterator type)
and `F` (function-object type). The concrete method is selected at stamp time —
there is no runtime vtable.

**`(MapIter I F)`** — applies `F`'s `apply` to each element yielded by `I`. `I`
must conform to `(Iterator S)` for some element type `S`; `F` must conform to
`(UnaryFn S E)`. The result element type `E` is recovered at stamp time from
`F`'s `UnaryFn` conformance. `(MapIter I F)` itself conforms to `(Iterator E)`.

**`(FilterIter I F)`** — keeps only elements for which `F`'s `apply` returns
non-zero (truthy). `I` must conform to `(Iterator S)`; `F` must conform to
`(UnaryFn S i32)`. The element type is unchanged: `(FilterIter I F)` conforms
to `(Iterator S)`.

Both combinators conform to `Iterator` via `extend` with a `&where` clause —
see [Conforming combinators: `&where` on `extend`](generics.md#conforming-combinators-where-on-extend).
This means they are first-class `Iterator` values and can be nested or passed to
any generic function bounded on `Iterator`.

Fields are stored **by value** inside the struct. Use `memcpy` with
`(.& struct field)` to copy a source iterator or function object into a
combinator's field:

```lisp
(let ((mi (ref (MapIter I64ArrayIter SquareI64)))
      (alloca (MapIter I64ArrayIter SquareI64)))
  (memcpy (as ptr (.& mi source)) (as ptr src) (sizeof I64ArrayIter))
  (memcpy (as ptr (.& mi f))      (as ptr sq)  (sizeof SquareI64))
  ...)
```

To call `next` on a field stored by value inside a struct, use
`(.& self fieldname)` to get a `(ref FieldType)`:

```lisp
(defn next ((self (ref (MapIter I F)))
                        &where ((Iterator S) I)
                               ((UnaryFn S E) F)) (Maybe E)
  (let ((res (Maybe S)) (next (.& self source)))
    ...))
```

## `reduce`

```lisp
(defn reduce ((g (ref G)) (init Acc) (it (ref I))
                  &where ((Iterator S) I)
                         ((FoldFn Acc S) G)):Acc
  ...)
```

Folds `it` left-to-right, starting from `init`, by calling `(fold g acc elem)`
for each element. `G` is the fold-function type, bounded by `(FoldFn Acc S)`.
`S` is the iterator's element type, recovered from `I`'s `Iterator` conformance
at the call site. Returns the final accumulated value `Acc`.

Because `MapIter` and `FilterIter` conform to `Iterator`, `reduce` can consume
them directly:

```lisp
(reduce sm 0 fi)   ; fi: any (ref (Iterator i64))-conforming type
```

## End-to-end example

Chain `[1,2,3,4,5]` → square → keep even → sum (= 4 + 16 = 20):

```lisp
(import-use "stdio.h")
(import-use iterator)

(defstruct SumI64 dummy:i32)
(extend SumI64 (FoldFn i64 i64))
(defn fold ((self (ref SumI64)) acc:i64 x:i64):i64 (return (+ acc x)))

(defstruct SquareI64 dummy:i32)
(extend SquareI64 (UnaryFn i64 i64))
(defn apply ((self (ref SquareI64)) x:i64):i64 (return (* x x)))

(defstruct IsEvenI64 dummy:i32)
(extend IsEvenI64 (UnaryFn i64 i32))
(defn apply ((self (ref IsEvenI64)) x:i64):i32
  (return (as i32 (= (% x 2) 0))))

(defn main ():i32
  (let (arr:ptr:i64 (alloca i64 5))
    (aset! arr 0 1) (aset! arr 1 2)
    (aset! arr 2 3) (aset! arr 3 4)
    (aset! arr 4 5)
    (let ((sq  (ref SquareI64)) (alloca SquareI64))
    (let ((ev  (ref IsEvenI64)) (alloca IsEvenI64))
    (let ((sm  (ref SumI64))    (alloca SumI64))
    (let ((src (ref I64ArrayIter)) (alloca I64ArrayIter))
      (.set! src data arr) (.set! src pos 0) (.set! src len 5)
      (let ((mi (ref (MapIter I64ArrayIter SquareI64)))
            (alloca (MapIter I64ArrayIter SquareI64)))
        (memcpy (as ptr (.& mi source)) (as ptr src) (sizeof I64ArrayIter))
        (memcpy (as ptr (.& mi f))      (as ptr sq)  (sizeof SquareI64))
        (let ((fi (ref (FilterIter (MapIter I64ArrayIter SquareI64) IsEvenI64)))
              (alloca (FilterIter (MapIter I64ArrayIter SquareI64) IsEvenI64)))
          (memcpy (as ptr (.& fi source)) (as ptr mi)
                  (sizeof (MapIter I64ArrayIter SquareI64)))
          (memcpy (as ptr (.& fi pred)) (as ptr ev) (sizeof IsEvenI64))
          (printf "sum=%lld\n" (reduce sm 0 fi)))))))))
  (return 0))
```

See `examples/iterator-test.nuc` for the complete working example.
