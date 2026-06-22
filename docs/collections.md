# Collections (`lib/coll.nuc`, `lib/hash.nuc`, `lib/vector.nuc`, `lib/hashmap.nuc`, `lib/hashset.nuc`, Stage 11)

`(import-use coll)` provides the core collection protocols (`Coll`, `Seq`, `Assoc`, `Set`, `Drop`) that every owning collection conforms to. The concrete types (`Vector`, `HashMap`, `HashSet`) are separate libraries and must be imported individually.

These collections are **mutable and in-place** in the STL spirit — `conj`, `assoc`, and the set-algebra operations mutate the receiver. They own heap memory through a stored `AllocHandle` and free it via `Drop` at `with`-scope exit. See [Allocators](allocators.md) for the allocator protocol and handle type.

## Core protocols (`lib/coll.nuc`)

### `(Coll E It)` — minimum every collection implements

```lisp
(defprotocol (Coll E It)
  (count:usize  ((self (ref Self))))
  (conj:void    ((self (ref Self)) elem:E))
  (empty?:i32   ((self (ref Self))))
  (iter:It      ((self (ref Self)))))
```

| Method | Description |
|--------|-------------|
| `count` | Number of live elements. |
| `conj` | Add an element in the collection's natural way, mutating in place. For a vector this is append; for a set this is insert; for a map this takes an `(Entry K V)` pair. |
| `empty?` | Returns `1` when `count = 0`, else `0`. |
| `iter` | Returns a fresh iterator over the collection's elements **by value**. The return type is the associated iterator type `It`, which must conform to `(Iterator E)`. |

`It` is the associated iterator type parameter (C2.1). `iter` returns an `It` by value using the alloca + set + `(deref …)` convention. Because `let` bindings require an explicit type and `addr-of` only takes the address of a named local (not an rvalue), callers must bind the returned iterator to a typed local before driving `next`:

```lisp
(let (it:(VecIter i32) (iter v))
  (match (next (addr-of it)) ...))
```

In practice, `doseq` handles this automatically — see [Macros](macros.md) for the `(doseq (var coll IterType) …)` form. The fill-in-place helpers (`iter-init`, `hashset-iter`, `hmap-iter-entries`) remain available as internal helpers that the value-returning `iter` methods wrap; the documented protocol surface is value-return only.

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

### `(Assoc K V Ki Vi)` — associative key/value maps

```lisp
(defprotocol (Assoc K V Ki Vi)
  (assoc:void        ((self (ref Self)) key:K val:V))
  (dissoc:void       ((self (ref Self)) key:K))
  ((get (Maybe V))   ((self (ref Self)) key:K))
  (keys:Ki           ((self (ref Self))))
  (vals:Vi           ((self (ref Self)))))
```

| Method | Description |
|--------|-------------|
| `assoc` | Insert or overwrite the value for `key`, mutating in place. |
| `dissoc` | Remove the entry for `key`, mutating in place. No-op if absent. |
| `get` | Look up `key`; returns `(some v)` on a hit, `none` on a miss. |
| `keys` | Returns a fresh key iterator by value. The return type is the associated iterator type `Ki`, which must conform to `(Iterator K)`. |
| `vals` | Returns a fresh value iterator by value. The return type is the associated iterator type `Vi`, which must conform to `(Iterator V)`. |

`Ki` and `Vi` are associated iterator type parameters (C2.2b). Like `Coll`'s `iter:It`, `keys` and `vals` use the alloca + set + `(deref …)` convention and return iterators by value. Callers must bind the result to a typed local before driving `next`:

```lisp
(let (kit:(HashMapKeyIter CStr i32) (keys m))
  (doseq-iter (k (addr-of kit))
    (printf "key=%s\n" k)))
```

In practice, iterate keys or values using `doseq-iter` on the bound result, or use the value-returning `keys`/`vals` result with `into`. Call `(get m key)` and match on the result for single-key lookup:

```lisp
(match (get m "one")
  ((some v) (printf "got %d\n" v))
  (none     (printf "absent\n")))
```

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

`select` (filter to a new set) is deliberately not in the protocol. It produces a Self-derived new collection that has low value as a generic bound; it is kept standalone by design, not because it is inexpressible (C2.3, `design/stage11/cleanup2.md`).

### `Drop` — lifecycle protocol for owning collections

```lisp
(defprotocol Drop
  (drop:void (self:ptr:Self)))
```

Every owning collection conforms to `Drop` so a `with`-bound value frees its buffer at scope exit, in reverse binding order. The method is named `drop` (not `free`) so it does not shadow libc `@free`. See [Special forms](special-forms.md) for `with`/`move`/`defer` semantics.

`Drop` is declared in `lib/coll.nuc` so every owning collection library can `(import-use coll)` and extend it.

---

## `Hash` protocol (`lib/hash.nuc`)

`(import-use hash)` is required by `hashmap` and `hashset`. A key type or set-member type must conform to both `Hash` and `Eq`.

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

| Type | Library | Coverage |
|------|---------|----------|
| `i32` | `lib/hash.nuc` | Folds 4 bytes of the value. |
| `i64` | `lib/hash.nuc` | Folds 8 bytes. |
| `usize` | `lib/hash.nuc` | Folds 8 bytes (high bytes are zero on 32-bit targets). |
| `CStr` | `lib/hash.nuc` | Folds each character byte up to (not including) the NUL terminator. |
| `StrView` | `lib/strview.nuc` | FNV-1a fold over exactly `len` bytes (handles embedded NULs). |
| `Keyword` | `lib/keyword.nuc` | Returns the hash cached at intern time — O(1), no byte walk. |

Unlike `numeric.nuc`'s code-free operator conformances, these are real method bodies because there is no built-in `hash` operator.

**Keywords as ergonomic map/set keys.** `Keyword` conforms to both `Hash` and `Eq`, making it the idiomatic lightweight key type when keys are known names rather than arbitrary strings. Because equality is identity (intern `id` compare) and hashing is a single cached load, keyword-keyed maps are faster than `CStr`-keyed ones (no `strcmp`, no byte walk):

```lisp
(import-use "stdio.h")
(import-use strview) (import-use hash) (import-use keyword)
(import-use allocator) (import-use coll) (import-use iterator) (import-use hashmap)

(defn main:i32 ()
  (with ((m (ref (HashMap Keyword i32))) (alloca (HashMap Keyword i32)))
    (hashmap-init m)
    (assoc m :width 1920)
    (assoc m :height 1080)
    (match (get m :width)
      ((some v) (printf "width=%d\n" v))   ; width=1920
      (none     (printf "absent\n"))))
  (return 0))
```

See [Keyword literals](types.md#keyword-literals----foo) in the Types reference for the full semantics and the `(import-use keyword)` requirement.

**Conforming a user type:** extend `Hash` and provide the `hash` method:

```lisp
(extend MyType Hash)
(defn hash:usize ((self (ref MyType)))
  ...)
```

---

## `Vector T` (`lib/vector.nuc`)

`(import-use vector)` provides a dynamically-sized, heap-backed mutable sequence. Append is O(1) amortized (capacity doubles); indexed access and `insert` are O(1) and O(n) respectively. Conforms to `(Coll T (VecIter T))`, `(Seq T)`, and `Drop`.

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

`VecIter T` conforms to `(Iterator T)`. It borrows the vector's buffer — it must not outlive the `Vector`. Because `Vector T` conforms to `(Coll T (VecIter T))`, the idiomatic iteration form is `doseq` with the `IterType` argument:

```lisp
(doseq (x v (VecIter i32))
  (printf "elem=%d\n" x))
```

`doseq` calls `(iter v)` internally to obtain a fresh `VecIter i32` by value, binds it to a typed local, and drives `(next (addr-of it))` per step. The internal helper `iter-init` (fills a caller-allocated `VecIter`) is still available but is not the recommended surface for new code.

See [Iterators](iterators.md) for `doseq` / `doseq-iter` and the `Iterator` protocol.

### Full example

```lisp
(import-use "stdio.h")
(import-use allocator)
(import-use coll)
(import-use iterator)
(import-use vector)

(defn main:i32 ()
  (with ((v (ref (Vector i32))) (alloca (Vector i32)))
    (vector-init v)
    (conj v 10) (conj v 20) (conj v 30)
    (printf "count=%llu\n" (cast ui64 (count v)))     ; count=3
    (printf "get[1]=%d\n"  (v (cast usize 1)))        ; get[1]=20
    (insert v (cast usize 1) 15)
    (printf "after insert: %d\n" (v (cast usize 1)))  ; 15
    (doseq (x v (VecIter i32)) (printf "elem=%d\n" x)))  ; 10 15 20 30
  (return 0))
```

---

## `HashMap K V` (`lib/hashmap.nuc`)

`(import-use hashmap)` provides an open-addressing hash map with linear probing and tombstone deletion. O(1) average `assoc`/`dissoc`/`get`. Conforms to `(Assoc K V (HashMapKeyIter K V) (HashMapValIter K V))`, `(Coll (Entry K V) (HashMapEntryIter K V))`, and `Drop`. Keys must conform to `Hash` and `Eq`.

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
| `hashmap-init-alloc` | `((m (ref (HashMap K V))) (a (ref AllocHandle))) -> void` | Initialise empty with an explicit allocator (e.g. an arena), initial capacity 8. |

### Operations

```lisp
; Assoc K V (HashMapKeyIter K V) (HashMapValIter K V)
(assoc:void        ((self (ref (HashMap K V))) key:K val:V))
(dissoc:void       ((self (ref (HashMap K V))) key:K))
((get (Maybe V))   ((self (ref (HashMap K V))) key:K))
(keys:(HashMapKeyIter K V)  ((self (ref (HashMap K V)))))
(vals:(HashMapValIter K V)  ((self (ref (HashMap K V)))))

; Coll (Entry K V) (HashMapEntryIter K V)
(conj:void    ((self (ref (HashMap K V))) elem:(Entry K V)))
(iter:(HashMapEntryIter K V) ((self (ref (HashMap K V)))))

; count / empty?
(count:usize  ((self (ref (HashMap K V)))))
(empty?:i32   ((self (ref (HashMap K V)))))
```

`get` returns `(Maybe V)`. Match on the result to distinguish hit from miss:

```lisp
(match (get m "one")
  ((some v) (printf "got %d\n" v))
  (none     (printf "absent\n")))
```

`conj` on a `HashMap` takes an `(Entry K V)` value and inserts its `key`/`val` pair — equivalent to `(assoc m e.key e.val)`.

### `(Entry K V)` — key/value pair element type

```lisp
(defstruct (Entry K V)
  key:K
  val:V)
```

`Entry K V` is a plain value struct. It is the element type `E` of `HashMap`'s `(Coll E It)` conformance. `iter` over a `HashMap` yields `Entry` values, so `doseq`, `into`, and `reduce` work uniformly over a map's entries.

### Entry iteration with `HashMapEntryIter K V`

```lisp
(defstruct (HashMapEntryIter K V)
  kbuf:ptr
  vbuf:ptr
  sbuf:ptr
  pos:usize
  cap:usize)
```

`HashMapEntryIter K V` conforms to `(Iterator (Entry K V))`. It borrows the map's key, value, and state buffers and must not outlive the `HashMap`. The idiomatic form uses `doseq` with the `IterType` argument (C2.1):

```lisp
(doseq (e m (HashMapEntryIter CStr i32))
  (printf "key=%s val=%d\n" ((addr-of e) key) ((addr-of e) val)))
```

`doseq` calls `(iter m)` to get a fresh `HashMapEntryIter` by value, binds it to a typed local, and drives `(next (addr-of it))`. Each element `e` is yielded by value; use `(addr-of e)` to access its fields.

Iteration order is hash-dependent and unspecified.

### Key iteration with `HashMapKeyIter K V`

```lisp
(defstruct (HashMapKeyIter K V)
  kbuf:ptr
  sbuf:ptr
  pos:usize
  cap:usize)
```

`HashMapKeyIter K V` conforms to `(Iterator K)`. It is returned by value from the `Assoc` protocol method `keys`. The idiomatic form binds the result to a typed local then drives it with `doseq-iter`:

```lisp
(let (kit:(HashMapKeyIter CStr i32) (keys m))
  (doseq-iter (k (addr-of kit))
    (printf "key=%s\n" k)))
```

The lower-level fill helper `hmap-iter-keys` (fills a caller-allocated `HashMapKeyIter` in place) is still available but is not the recommended surface for new code.

### Value iteration with `HashMapValIter K V`

```lisp
(defstruct (HashMapValIter K V)
  vbuf:ptr
  sbuf:ptr
  pos:usize
  cap:usize)
```

`HashMapValIter K V` conforms to `(Iterator V)`. It is returned by value from the `Assoc` protocol method `vals`:

```lisp
(let (vit:(HashMapValIter CStr i32) (vals m))
  (doseq-iter (v (addr-of vit))
    (printf "val=%d\n" v)))
```

The lower-level fill helper `hmap-iter-vals` is still available but is not the recommended surface.

Iteration order is hash-dependent and unspecified for both `keys` and `vals`.

### Full example

```lisp
(import-use "stdio.h")
(import-use allocator)
(import-use coll)
(import-use iterator)
(import-use hash)
(import-use hashmap)

(defn main:i32 ()
  (with ((m (ref (HashMap CStr i32))) (alloca (HashMap CStr i32)))
    (hashmap-init m)
    (assoc m "one" 1) (assoc m "two" 2) (assoc m "three" 3)
    (printf "count=%llu\n" (cast ui64 (count m)))  ; 3
    (match (get m "two")
      ((some v) (printf "two=%d\n" v))             ; two=2
      (none     (printf "absent\n")))
    (dissoc m "one")
    (printf "count=%llu\n" (cast ui64 (count m)))) ; 2
  (return 0))
```

---

## `HashSet T` (`lib/hashset.nuc`)

`(import-use hashset)` provides an open-addressing hash set with linear probing. O(1) average `insert`/`contains?`/`set-remove`. Conforms to `(Coll T (HashSetIter T))`, `(Set T)`, and `Drop`. Members must conform to `Hash` and `Eq`.

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
| `hashset-init-alloc` | `((s (ref (HashSet T))) (a (ref AllocHandle))) -> void` | Initialise empty with an explicit allocator (e.g. an arena), initial capacity 8. |

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

`HashSetIter T` conforms to `(Iterator T)`. It borrows the set's buffers and must not outlive the `HashSet`. Because `HashSet T` conforms to `(Coll T (HashSetIter T))`, the idiomatic iteration form is `doseq` with the `IterType` argument:

```lisp
(doseq (x s (HashSetIter i32))
  (printf "member=%d\n" x))
```

`doseq` calls `(iter s)` to get a fresh `HashSetIter i32` by value and drives `(next (addr-of it))` per step. The internal helper `hashset-iter` (fills a caller-allocated `HashSetIter`) is still available but is not the recommended surface for new code.

Iteration order is hash-dependent and unspecified.

### Full example

```lisp
(import-use "stdio.h")
(import-use allocator)
(import-use coll)
(import-use iterator)
(import-use hash)
(import-use hashset)

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
  (match (get m "foo")
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

**`HashMap` `conj` takes an `Entry`, not a raw value.** `(conj m e)` inserts the `(Entry K V)` pair `e` into the map. Use `assoc` directly when key and value are already separate.

**`HashSet` uses `set-remove`, not `remove`.** The name `remove` is libc's file-removal function; shadowing it would break `(import-use "stdio.h")` consumers that use `remove` in the same unit.
