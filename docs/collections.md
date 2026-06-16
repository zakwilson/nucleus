# Collections (`lib/coll.nuc`, `lib/hash.nuc`, `lib/vector.nuc`, `lib/hashmap.nuc`, `lib/hashset.nuc`, Stage 11)

`(import coll)` provides the core collection protocols (`Coll`, `Seq`, `Assoc`, `Set`, `Drop`) that every owning collection conforms to. The concrete types (`Vector`, `HashMap`, `HashSet`) are separate libraries and must be imported individually.

These collections are **mutable and in-place** in the STL spirit — `conj`, `assoc`, and the set-algebra operations mutate the receiver. They own heap memory through a stored `AllocHandle` and free it via `Drop` at `with`-scope exit. See [Allocators](allocators.md) for the allocator protocol and handle type.

## Core protocols (`lib/coll.nuc`)

### `(Coll E)` — minimum every collection implements

```lisp
(defprotocol (Coll E)
  (count:usize ((self (ref Self))))
  (conj:void   ((self (ref Self)) elem:E))
  (empty?:i32  ((self (ref Self)))))
```

| Method | Description |
|--------|-------------|
| `count` | Number of live elements. |
| `conj` | Add an element in the collection's natural way, mutating in place. For a vector this is append; for a set this is insert. |
| `empty?` | Returns `1` when `count = 0`, else `0`. |

`iter` is intentionally absent from the protocol: it returns an iterator type derived from `Self` (an associated type), which the parametric protocol machinery cannot express. Each concrete type provides its own `iter`-style initializer function.

### `(Seq E)` — ordered, index-addressable sequences

```lisp
(defprotocol (Seq E)
  (invoke:E      ((self (ref Self)) i:usize))
  (append:void   ((self (ref Self)) elem:E))
  (contains?:i32 ((self (ref Self)) elem:E))
  (insert:void   ((self (ref Self)) i:usize elem:E)))
```

| Method | Description |
|--------|-------------|
| `invoke` | Index access: `(s i)` routes to `invoke` and returns the element at index `i`. Panics on out-of-bounds. |
| `append` | Add at the back, mutating in place. |
| `contains?` | Linear membership test using `=` on `E`. Returns `1` if found, `0` otherwise. |
| `insert` | Insert at index `i`, shifting `[i, len)` right by one, mutating in place. |

**Why `invoke`, not `get`:** the head symbol `get` is reserved by the compiler for struct field access (`(s 'field)`). The callable-values dispatch routes an integer index `(s i)` to `invoke` instead, keeping field access and index access distinct. See [Special forms](special-forms.md) for the callable-values dispatch rules.

### `(Assoc K V)` — associative key/value maps

```lisp
(defprotocol (Assoc K V)
  (assoc:void  ((self (ref Self)) key:K val:V))
  (dissoc:void ((self (ref Self)) key:K)))
```

| Method | Description |
|--------|-------------|
| `assoc` | Insert or overwrite the value for `key`, mutating in place. |
| `dissoc` | Remove the entry for `key`, mutating in place. No-op if absent. |

`hmap-get` (key → `(Maybe V)`), key iteration, and `select-keys` are standalone functions rather than protocol methods because their result types depend on the concrete map type and cannot be expressed in the protocol.

### `(Set E)` — sets of unique members

```lisp
(defprotocol (Set E)
  (union:void        ((self (ref Self)) (other (ref Self))))
  (difference:void   ((self (ref Self)) (other (ref Self))))
  (intersection:void ((self (ref Self)) (other (ref Self))))
  (contains?:i32     ((self (ref Self)) elem:E)))
```

All four methods take `(ref Self)` receivers. The algebra methods (`union`, `difference`, `intersection`) **mutate `self` in place**:

| Method | Effect |
|--------|--------|
| `union` | Adds every member of `other` into `self`. |
| `difference` | Removes from `self` every member also in `other`. |
| `intersection` | Keeps in `self` only members also in `other`. |
| `contains?` | Returns `1` if `elem` is a member, else `0`. |

`select` (filter to a new set) is not in the protocol because it produces a Self-derived result type.

### `Drop` — lifecycle protocol for owning collections

```lisp
(defprotocol Drop
  (drop:void (self:ptr:Self)))
```

Every owning collection conforms to `Drop` so a `with`-bound value frees its buffer at scope exit, in reverse binding order. The method is named `drop` (not `free`) so it does not shadow libc `@free`. See [Special forms](special-forms.md) for `with`/`move`/`defer` semantics.

`Drop` is declared in `lib/coll.nuc` so every owning collection library can `(import coll)` and extend it.

---

## `Hash` protocol (`lib/hash.nuc`)

`(import hash)` is required by `hashmap` and `hashset`. A key type or set-member type must conform to both `Hash` and `Eq`.

```lisp
(defprotocol Hash
  (hash:usize ((self (ref Self)))))
```

`hash` takes `(ref Self)` so a large key is not copied; the receiver is loaded through the reference. The `hash` call idiom in generic collection code is:

```lisp
(let (k:K key)
  (let (h:usize (hash (addr-of k))) ...))
```

**Built-in conformances** (FNV-1a, 64-bit):

| Type | Coverage |
|------|----------|
| `i32` | Folds 4 bytes of the value. |
| `i64` | Folds 8 bytes. |
| `usize` | Folds 8 bytes (high bytes are zero on 32-bit targets). |
| `CStr` | Folds each character byte up to (not including) the NUL terminator. |

Unlike `numeric.nuc`'s code-free operator conformances, these are real method bodies because there is no built-in `hash` operator.

**Conforming a user type:** extend `Hash` and provide the `hash` method:

```lisp
(extend MyType Hash)
(defn hash:usize ((self (ref MyType)))
  ...)
```

---

## `Vector T` (`lib/vector.nuc`)

`(import vector)` provides a dynamically-sized, heap-backed mutable sequence. Append is O(1) amortized (capacity doubles); indexed access and `insert` are O(1) and O(n) respectively. Conforms to `(Coll T)`, `(Seq T)`, and `Drop`.

### Construction

Vectors are initialised in place — there is no value constructor because a zero-argument call has no argument from which to infer `T`, and returning an owning collection by value does not compose with `with`/`Drop`. The canonical idiom:

```lisp
(with ((v (ref (Vector i32))) (alloca (Vector i32)))
  (vector-init v)          ; empty, default (libc) allocator
  (conj v 10) (conj v 20) (conj v 30)
  ...)                     ; (drop v) fires here, freeing the buffer
```

| Constructor | Signature | Description |
|-------------|-----------|-------------|
| `vector-init` | `((v (ref (Vector T)))) -> void` | Initialise empty with the default libc allocator. |
| `vector-init-capacity` | `((v (ref (Vector T))) n:usize) -> void` | Initialise empty with at least `n` slots pre-reserved. |
| `vector-init-alloc` | `((v (ref (Vector T))) (a (ref AllocHandle))) -> void` | Initialise empty with an explicit allocator. |

### Operations

```lisp
; Coll T
(count:usize    ((self (ref (Vector T)))))
(conj:void      ((self (ref (Vector T))) elem:T))
(empty?:i32     ((self (ref (Vector T)))))

; Seq T
(invoke:T       ((self (ref (Vector T))) i:usize))   ; called as (v i)
(append:void    ((self (ref (Vector T))) elem:T))
(contains?:i32  ((self (ref (Vector T))) elem:T))
(insert:void    ((self (ref (Vector T))) i:usize elem:T))

; Capacity
(capacity:usize ((self (ref (Vector T)))))
(reserve:void   ((self (ref (Vector T))) n:usize))
```

`conj` and `append` are equivalent for `Vector` (both append at the back). `insert` with `i == len` is equivalent to `append`; `i > len` panics.

### Iteration with `VecIter T`

```lisp
(defstruct (VecIter T)
  data:ptr
  pos:usize
  len:usize)
```

`VecIter T` conforms to `(Iterator T)`. It borrows the vector's buffer — it must not outlive the `Vector`. Use `iter-init` to fill a caller-allocated `VecIter`, then drive it with `doseq`:

```lisp
(let ((it (ref (VecIter i32))) (alloca (VecIter i32)))
  (iter-init it v)
  (doseq (x it)
    (printf "elem=%d\n" x)))
```

See [Iterators](iterators.md) for `doseq` and the `Iterator` protocol.

### Full example

```lisp
(include stdio)
(import allocator)
(import coll)
(import iterator)
(import vector)

(defn main:i32 ()
  (with ((v (ref (Vector i32))) (alloca (Vector i32)))
    (vector-init v)
    (conj v 10) (conj v 20) (conj v 30)
    (printf "count=%llu\n" (cast ui64 (count v)))     ; count=3
    (printf "get[1]=%d\n"  (v (cast usize 1)))        ; get[1]=20
    (insert v (cast usize 1) 15)
    (printf "after insert: %d\n" (v (cast usize 1)))  ; 15
    (let ((it (ref (VecIter i32))) (alloca (VecIter i32)))
      (iter-init it v)
      (doseq (x it) (printf "elem=%d\n" x))))         ; 10 15 20 30
  (return 0))
```

---

## `HashMap K V` (`lib/hashmap.nuc`)

`(import hashmap)` provides an open-addressing hash map with linear probing and tombstone deletion. O(1) average `assoc`/`dissoc`/`hmap-get`. Conforms to `(Assoc K V)` and `Drop`. Keys must conform to `Hash` and `Eq`.

`HashMap` does **not** conform to `(Coll T)` because `conj` is ambiguous for a key/value map — inserting a single element requires both a key and a value.

**Implementation:** three parallel byte arrays (keys, vals, states). Capacity is always a power of two; a 75% load factor triggers doubling. Tombstone entries are skipped during lookup and dropped on resize.

### Construction

```lisp
(with ((m (ref (HashMap CStr i32))) (alloca (HashMap CStr i32)))
  (hashmap-init m)
  (assoc m "one" 1)
  (assoc m "two" 2)
  ...)   ; (drop m) fires here
```

| Constructor | Signature | Description |
|-------------|-----------|-------------|
| `hashmap-init` | `((m (ref (HashMap K V)))) -> void` | Initialise empty with the default libc allocator, initial capacity 8. |

### Operations

```lisp
; Assoc K V
(assoc:void   ((self (ref (HashMap K V))) key:K val:V))
(dissoc:void  ((self (ref (HashMap K V))) key:K))

; Standalone (result types derived from V)
((hmap-get (Maybe V)) ((self (ref (HashMap K V))) key:K))

; Standalone count / empty?
(count:usize  ((self (ref (HashMap K V)))))
(empty?:i32   ((self (ref (HashMap K V)))))
```

`hmap-get` returns `(Maybe V)`. Match on the result to distinguish hit from miss:

```lisp
(match (hmap-get m "one")
  ((some v) (printf "got %d\n" v))
  (none     (printf "absent\n")))
```

### Key iteration with `HashMapKeyIter K V`

```lisp
(defstruct (HashMapKeyIter K V)
  kbuf:ptr
  sbuf:ptr
  pos:usize
  cap:usize)
```

`HashMapKeyIter K V` conforms to `(Iterator K)`. It borrows the map's key and state buffers and must not outlive the `HashMap`. Use `hmap-iter-keys` to fill a caller-allocated iterator:

```lisp
(let ((it (ref (HashMapKeyIter CStr i32))) (alloca (HashMapKeyIter CStr i32)))
  (hmap-iter-keys it m)
  (doseq (k it)
    (printf "key=%s\n" k)))
```

Iteration order is hash-dependent and unspecified.

### Full example

```lisp
(include stdio)
(import allocator)
(import coll)
(import iterator)
(import hash)
(import hashmap)

(defn main:i32 ()
  (with ((m (ref (HashMap CStr i32))) (alloca (HashMap CStr i32)))
    (hashmap-init m)
    (assoc m "one" 1) (assoc m "two" 2) (assoc m "three" 3)
    (printf "count=%llu\n" (cast ui64 (count m)))  ; 3
    (match (hmap-get m "two")
      ((some v) (printf "two=%d\n" v))             ; two=2
      (none     (printf "absent\n")))
    (dissoc m "one")
    (printf "count=%llu\n" (cast ui64 (count m)))) ; 2
  (return 0))
```

---

## `HashSet T` (`lib/hashset.nuc`)

`(import hashset)` provides an open-addressing hash set with linear probing. O(1) average `insert`/`contains?`/`set-remove`. Conforms to `(Coll T)`, `(Set T)`, and `Drop`. Members must conform to `Hash` and `Eq`.

**Implementation:** two parallel byte arrays (keys buffer and state buffer). Same open-addressing layout as `HashMap`; same 75% load-factor doubling policy.

### Construction

```lisp
(with ((s (ref (HashSet CStr))) (alloca (HashSet CStr)))
  (hashset-init s)
  (insert s "dog") (insert s "cat")
  ...)   ; (drop s) fires here
```

| Constructor | Signature | Description |
|-------------|-----------|-------------|
| `hashset-init` | `((s (ref (HashSet T)))) -> void` | Initialise empty with the default libc allocator, initial capacity 8. |

### Operations

```lisp
; Set T
(insert:void       ((self (ref (HashSet T))) elem:T))
(contains?:i32     ((self (ref (HashSet T))) elem:T))
(set-remove:void   ((self (ref (HashSet T))) elem:T))
(union:void        ((self (ref (HashSet T))) (other (ref (HashSet T)))))
(difference:void   ((self (ref (HashSet T))) (other (ref (HashSet T)))))
(intersection:void ((self (ref (HashSet T))) (other (ref (HashSet T)))))

; Coll T (conj == insert)
(conj:void   ((self (ref (HashSet T))) elem:T))
(count:usize ((self (ref (HashSet T)))))
(empty?:i32  ((self (ref (HashSet T)))))
```

`insert` is a no-op if the element is already present. `set-remove` is named that (not `remove`) to avoid shadowing libc `remove`. The set-algebra methods mutate `self` in place.

### Iteration with `HashSetIter T`

```lisp
(defstruct (HashSetIter T)
  kbuf:ptr
  sbuf:ptr
  pos:usize
  cap:usize)
```

`HashSetIter T` conforms to `(Iterator T)`. It borrows the set's buffers and must not outlive the `HashSet`. Use `hashset-iter` to fill a caller-allocated iterator:

```lisp
(let ((it (ref (HashSetIter i32))) (alloca (HashSetIter i32)))
  (hashset-iter it s)
  (doseq (x it)
    (printf "member=%d\n" x)))
```

Iteration order is hash-dependent and unspecified.

### Full example

```lisp
(include stdio)
(import allocator)
(import coll)
(import iterator)
(import hash)
(import hashset)

(defn main:i32 ()
  ; Basic membership
  (with ((s (ref (HashSet CStr))) (alloca (HashSet CStr)))
    (hashset-init s)
    (insert s "dog") (insert s "cat") (insert s "fish")
    (printf "contains dog: %d\n"  (contains? s "dog"))   ; 1
    (printf "contains bird: %d\n" (contains? s "bird"))  ; 0
    (set-remove s "cat")
    (printf "contains cat: %d\n"  (contains? s "cat")))  ; 0

  ; Set algebra (i32 elements)
  (with ((a (ref (HashSet i32))) (alloca (HashSet i32)))
    (hashset-init a)
    (insert a 1) (insert a 2) (insert a 3) (insert a 4)
    (with ((b (ref (HashSet i32))) (alloca (HashSet i32)))
      (hashset-init b)
      (insert b 3) (insert b 4) (insert b 5) (insert b 6)
      (union a b)
      (printf "union count: %llu\n" (cast ui64 (count a))))) ; 6
  (return 0))
```

---

## Literal sugar (`[…]`, `{…}`, `#{…}`)

The reader provides bracket literals that construct and initialise a collection
from scalar elements. Each expands, in the reader, to a `let` that
stack-allocates the (stamped) collection, runs its in-place init constructor
with the **default (libc) allocator**, `conj`/`assoc`-es every element, and
yields the `(ref Coll)`. Placed as the right-hand side of a `with` binding, the
outer `with` fires `Drop` at scope exit because every collection conforms to
`Drop`.

| Literal | Expands to | Element type |
|---|---|---|
| `[e1 e2 …]` | `(Vector E)` + `vector-init` + `conj` | inferred from elements |
| `{k1 v1 k2 v2 …}` | `(HashMap K V)` + `hashmap-init` + `assoc` | keys infer `K`, values infer `V` |
| `#{e1 e2 …}` | `(HashSet E)` + `hashset-init` + `conj` | inferred from elements |

```lisp
(with ((v (ref (Vector i32))) [1 2 3])
  (printf "%d\n" (v (cast usize 0))))            ; 1

(with ((m (ref (HashMap CStr i32))) {"foo" 42 "bar" 7})
  (match (hmap-get m "foo")
    ((some x) (printf "%d\n" x))                  ; 42
    (none     (printf "absent\n"))))

(with ((s (ref (HashSet CStr))) #{"a" "b" "c"})
  (printf "%d\n" (contains? s "a")))             ; 1
```

The example expands `[1 2 3]` to roughly:

```lisp
(let ((__gs_N (ref (Vector i32))) (alloca (Vector i32)))
  (vector-init __gs_N)
  (conj __gs_N 1) (conj __gs_N 2) (conj __gs_N 3)
  __gs_N)
```

**Element-type inference.** Element types are inferred from the literal's scalar
elements: an integer literal infers `i32`, a float literal `f64`, a string
literal `CStr`. All elements of a vector or set must share a kind; a map's keys
must agree and its values must agree (keys and values are independent). Integers
always infer `i32` — there is no magnitude-based `i64` promotion, because the
compiler types every integer literal as `i32` and has no native `i64` integer
literal. For an `i64` (or other non-default-typed) collection, use the explicit
`(alloca (Vector T))` + `vector-init` idiom and `(cast T …)` the elements.

**Errors.** Each of these is a compile-time reader error:

- **Empty literal** (`[]`, `{}`, `#{}`) — the element type cannot be inferred; use
  the explicit `(alloca (Coll T))` + init idiom.
- **Mixed element kinds** (`[1 2.0 3]`) — element kinds do not widen.
- **Non-scalar elements** (`[foo (g x)]`) — only int, float, and string literals
  are permitted.
- **Odd map element count** (`{"a" 1 "b"}`) — keys and values must pair up.

Only success-path literals appear in the test suite's example programs; the error
paths are reader diagnostics (compile-time `error:` messages), not runtime output.

---

## Gotchas and constraints

**Parametric method parameter syntax.** A parameter or return type written as a parenthesised form must use the list binding form: `(self (ref (Vector T)))`, never `self:(ref (Vector T))`. A plain-symbol colon chain tokenises correctly: `count:usize`, `self:ptr:Self`.

**`usize` literals.** There is no `usize` literal; always write `(cast usize N)` for index and length values.

**`(Maybe V)` element types.** `(Maybe ptr)` is niche-encoded as a nullable pointer and cannot be used with `match`. Use value types (`i32`, `i64`, `CStr`) as the value type `V` in `HashMap` and the element type in `(Maybe T)` returns.

**Owning collections and scope.** Owning collections store their allocator handle by value and must not escape their `with` binding by return or store-out. `Drop` fires at scope exit; a double-drop is a no-op (the pointer is nulled). The `move` form (when available) transfers ownership.

**`HashMap` does not conform to `Coll`.** `conj` is not defined for `HashMap` because inserting one element requires both a key and a value — the `Coll E` element type would be ambiguous. Use `assoc` directly.

**`HashSet` uses `set-remove`, not `remove`.** The name `remove` is libc's file-removal function; shadowing it would break `(include stdio)` consumers that use `remove` in the same unit.
