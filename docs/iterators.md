# Iterators (`lib/iterator.nuc`, Stage 11)

`(import iterator)` provides the `Iterator` parametric protocol, two concrete
iterator structs, two lazy combinator types, function-object protocols, and
typed reduce functions.

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
`(ref IterType)` to `next` or to `doseq`.

```lisp
(let ((r (ref IntRangeIter)) (alloca IntRangeIter))
  (.set! r start 1)
  (.set! r end 6)
  (doseq (x r)
    (printf "%d\n" x)))   ; prints 1 2 3 4 5
```

## Function-object protocols

These protocols let user-defined types serve as functions passed to `MapIterI64`,
`FilterIterI64`, and `reduce-*`:

| Protocol | Required method | Description |
|----------|----------------|-------------|
| `CallI64` | `callfn:i64 (self:ptr:Self x:i64)` | Unary `i64 → i64` transform. Used as the map / predicate function. |
| `BinaryCallI64` | `foldop:i64 (self:ptr:Self acc:i64 x:i64)` | Binary `(i64, i64) → i64` fold. Used by reduce. |

Define a struct, `extend` it with the protocol, then provide `callfn` or `foldop`:

```lisp
(defstruct SumI64 dummy:i32)
(extend SumI64 BinaryCallI64)
(defn foldop:i64 (self:ptr:SumI64 acc:i64 x:i64)
  (return (+ acc x)))
```

## Lazy combinators

Both are **parametric structs** with type parameters `I` (source iterator type)
and `F` (function-object type). Parametrising on `F` means the concrete `callfn`
is selected at stamp time — there is no runtime vtable.

**`(MapIterI64 I F)`** — applies `callfn` to each element of the source iterator.
`I` must conform to `(Iterator i64)`. `F` must conform to `CallI64`.

**`(FilterIterI64 I F)`** — keeps only elements where `callfn` returns non-zero.
Same constraints as `MapIterI64`.

Fields are stored **by value** inside the struct. Use `memcpy` with `(.& struct field)` to copy a source iterator or function object into a combinator's field (because `alloca` returns a reference, and field assignment requires a reference to the destination):

```lisp
(let ((mi (ref (MapIterI64 I64ArrayIter SquareI64)))
      (alloca (MapIterI64 I64ArrayIter SquareI64)))
  (memcpy (cast ptr (.& mi source)) (cast ptr src) (cast i64 (sizeof I64ArrayIter)))
  (memcpy (cast ptr (.& mi f))      (cast ptr sq)  (cast i64 (sizeof SquareI64)))
  ...)
```

To call `next` on a field stored by value inside a struct, use `(.& self fieldname)` to get a `(ref FieldType)`:

```lisp
(defn (next (Maybe i64)) ((self (ref (MapIterI64 I F))))
  (let ((res (Maybe i64)) (next (.& self source)))
    ...))
```

## Reduce functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `reduce-i64` | `((f (ref G)) init:i64 (it (ref I64ArrayIter)) &where (BinaryCallI64 G)) -> i64` | Fold an `I64ArrayIter` with a `BinaryCallI64` function object `f`. |
| `reduce-map-i64` | `((fold (ref G)) init:i64 (it (ref (MapIterI64 I F))) &where (BinaryCallI64 G)) -> i64` | Fold a `MapIterI64` with a `BinaryCallI64`. |
| `reduce-filter-map-i64` | `((fold (ref G)) init:i64 (it (ref (FilterIterI64 (MapIterI64 I F) P))) &where (BinaryCallI64 G)) -> i64` | Fold a `FilterIterI64` wrapping a `MapIterI64`. |

`G` is inferred at the call site from the concrete type of `fold`. All three
functions iterate until `none` and return the accumulated value.

## End-to-end example

Chain `[1,2,3,4,5]` → square → keep even → sum (= 4 + 16 = 20):

```lisp
(import iterator)

(defstruct SumI64 dummy:i32)
(extend SumI64 BinaryCallI64)
(defn foldop:i64 (self:ptr:SumI64 acc:i64 x:i64) (return (+ acc x)))

(defstruct SquareI64 dummy:i32)
(extend SquareI64 CallI64)
(defn callfn:i64 (self:ptr:SquareI64 x:i64) (return (* x x)))

(defstruct IsEvenI64 dummy:i32)
(extend IsEvenI64 CallI64)
(defn callfn:i64 (self:ptr:IsEvenI64 x:i64)
  (return (cast i64 (= (% x (cast i64 2)) (cast i64 0)))))

(defn main:i32 ()
  (let (arr:ptr:i64 (alloca i64 5))
    (aset! arr 0 (cast i64 1)) (aset! arr 1 (cast i64 2))
    (aset! arr 2 (cast i64 3)) (aset! arr 3 (cast i64 4))
    (aset! arr 4 (cast i64 5))
    (let ((sq (ref SquareI64)) (alloca SquareI64))
    (let ((ev (ref IsEvenI64)) (alloca IsEvenI64))
    (let ((sm (ref SumI64)) (alloca SumI64))
    (let ((src (ref I64ArrayIter)) (alloca I64ArrayIter))
      (.set! src data arr) (.set! src pos (cast usize 0)) (.set! src len (cast usize 5))
      (let ((mi (ref (MapIterI64 I64ArrayIter SquareI64))
            (alloca (MapIterI64 I64ArrayIter SquareI64)))
        (memcpy (cast ptr (.& mi source)) (cast ptr src) (cast i64 (sizeof I64ArrayIter)))
        (memcpy (cast ptr (.& mi f))      (cast ptr sq)  (cast i64 (sizeof SquareI64)))
        (let ((fi (ref (FilterIterI64 (MapIterI64 I64ArrayIter SquareI64) IsEvenI64)))
              (alloca (FilterIterI64 (MapIterI64 I64ArrayIter SquareI64) IsEvenI64)))
          (memcpy (cast ptr (.& fi source)) (cast ptr mi)
                  (cast i64 (sizeof (MapIterI64 I64ArrayIter SquareI64))))
          (memcpy (cast ptr (.& fi pred)) (cast ptr ev) (cast i64 (sizeof IsEvenI64)))
          (printf "sum=%lld\n" (reduce-filter-map-i64 sm (cast i64 0) fi)))))))))
  (return 0))
```

See `examples/iterator-test.nuc` for the complete working example.
