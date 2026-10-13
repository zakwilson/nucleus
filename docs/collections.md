# Collections (`lib/nucleus/coll.nuc`, `lib/nucleus/hash.nuc`, `lib/nucleus/vector.nuc`, `lib/nucleus/hashmap.nuc`, `lib/nucleus/hashset.nuc`, Stage 11)

`(import-use nucleus.coll)` provides the core collection protocols (`Coll`, `Seq`, `Assoc`, `Set`, `Drop`) that every owning collection conforms to. The concrete types (`Vector`, `HashMap`, `HashSet`, and the AST's own `Node`) are separate libraries and must be imported individually.

These collections are **mutable and in-place** in the STL spirit — `conj`, `assoc`, and the set-algebra operations mutate the receiver. They own heap memory through a stored `Alloc` and free it via `Drop` at `with`-scope exit. See [Allocators](allocators.md) for the allocator protocol and handle type.

## Core protocols (`lib/nucleus/coll.nuc`)

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

`It` is the associated iterator type parameter (C2.1). `iter` returns an `It` by value using the alloca + set + `(deref …)` convention. Because `let` bindings require an explicit type and `&` only takes the address of a named local (not an rvalue), callers must bind the returned iterator to a typed local before driving `next`:

```lisp
(let (it:(VecIter i32) (iter v))
  (match (next &it) ...))
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
| `set` | Index assignment: `(set! (s i) x)` routes to `set`. The write side of `invoke`; panics on out-of-bounds rather than growing, so a typo cannot silently extend the collection. Not a `Seq` member — `Vector` defines it directly. |
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
| `set` | The same write, under the name the place form dispatches on: `(set! (m k) v)` and `(set! (get m k) v)` both call it. Not an `Assoc` member — `HashMap` defines it directly, as `assoc`. |
| `dissoc` | Remove the entry for `key`, mutating in place. No-op if absent. |
| `get` | Look up `key`; returns `(some v)` on a hit, `none` on a miss. |
| `keys` | Returns a fresh key iterator by value. The return type is the associated iterator type `Ki`, which must conform to `(Iterator K)`. |
| `vals` | Returns a fresh value iterator by value. The return type is the associated iterator type `Vi`, which must conform to `(Iterator V)`. |

`Ki` and `Vi` are associated iterator type parameters (C2.2b). Like `Coll`'s `iter:It`, `keys` and `vals` use the alloca + set + `(deref …)` convention and return iterators by value. Callers must bind the result to a typed local before driving `next`:

```lisp
(let (kit:(HashMapKeyIter CStr i32) (keys m))
  (doseq-iter (k &kit)
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

Every owning collection conforms to `Drop` so a `with`-bound value frees its buffer at scope exit, in reverse binding order. See [Special forms](special-forms.md) for `with`/`move`/`defer` semantics.

`Drop` is declared in `lib/nucleus/coll.nuc` so every owning collection library can `(import-use nucleus.coll)` and extend it.

---

## `Hash` protocol (`lib/nucleus/hash.nuc`)

`(import-use nucleus.hash)` is required by `hashmap` and `hashset`. A key type or set-member type must conform to both `Hash` and `Eq`.

```lisp
(defprotocol Hash
  (hash:usize ((self (ref Self)))))
```

`hash` takes `(ref Self)` so a large key is not copied; the receiver is loaded through the reference. The `hash` call idiom in generic collection code is:

```lisp
(let (k:K key)
  (let (h:usize (hash &k)) ...))
```

**Built-in conformances** (FNV-1a, 64-bit):

| Type | Library | Coverage |
|------|---------|----------|
| `i32` | `lib/nucleus/hash.nuc` | Folds 4 bytes of the value. |
| `i64` | `lib/nucleus/hash.nuc` | Folds 8 bytes. |
| `usize` | `lib/nucleus/hash.nuc` | Folds 8 bytes (high bytes are zero on 32-bit targets). |
| `f64` | `lib/nucleus/hash.nuc` | Folds the 8-byte bit pattern, with `-0.0` normalised to `+0.0`. |
| `f32` | `lib/nucleus/hash.nuc` | Folds the 4-byte bit pattern, with `-0.0` normalised to `+0.0`. |
| `(ref Node)` | `lib/nucleus/hash.nuc` | A symbol. Folds the canonical node pointer — `intern-symbol` gives one node per spelling, so pointer identity is symbol identity. |
| `CStr` | `lib/nucleus/hash.nuc` | Folds each character byte up to (not including) the NUL terminator. |
| `StrView` | `lib/nucleus/hash.nuc` | FNV-1a fold over exactly `len` bytes (handles embedded NULs). Beside `CStr`'s rather than in `lib/nucleus/strview.nuc`, so a string-literal collection works on the collection import alone. |
| `Keyword` | `lib/nucleus/keyword.nuc` | Returns the hash cached at intern time — O(1), no byte walk. |
| `Symbol` | `lib/nucleus/intern-str.nuc` | Returns the hash cached at intern time — O(1), no byte walk. |

Unlike `numeric.nuc`'s code-free operator conformances, these are real method bodies because there is no built-in `hash` operator.

The fold itself lives in `lib/nucleus/fnv.nuc` (`fnv1a-byte`, `fnv1a-int`, `fnv1a-bytes`), which `lib/nucleus/hash.nuc` imports. It is a separate module so that `lib/nucleus/intern.nuc` can use the fold without importing `hash` — whose `f64` conformance is rejected on AVR, and which the compiler's symbol table therefore cannot depend on.

### Symbols as keys

`'foo` is an interned symbol: `intern-symbol` keeps one canonical `Node` per spelling, so pointer identity is symbol identity, `=` already compared correctly, and Stage 16 supplied the missing `hash`. A quoted symbol types `(ref Node)` (see [the quote table](macros.md#the-type-of-a-quoted-form)), so it drops straight into a collection with no cast — the `Node` *type* comes from `lib/nucleus/core.nuc`, but `'foo` calls `intern-symbol` at run time, so symbol keys need `(import-use nucleus.node)` — exactly as `:foo` needs `keyword` (see [The node runtime is a library](toplevel.md#the-node-runtime-is-a-library)).

```lisp
(with ((s (ref (HashSet (ref Node)))) #{'alpha 'beta})
  (printf "%d\n" (contains? s 'alpha)))            ; 1
```

**Look a symbol key up with `(invoke m 'k)`, never `(m 'k)`.** In head position a selector is resolved as a *field name* first, and quoting does not exempt it — `(m 'count)` reads `HashMap`'s `count` field and returns a **wrong answer rather than an error**. `invoke` is the always-a-value escape hatch. This is the general head-position rule (see [Gotchas](#gotchas-and-constraints)); symbol keys just make it easy to hit.

Choose between the two key types by what the key *is*: `Keyword` for a name that is data (a config key, a tag), `(ref Node)` for a name that is program text you are already holding as AST. `Keyword`'s hash is a cached load; a symbol's is a pointer fold.

**Floats as keys** hash their bit pattern rather than their value, so the two IEEE-754 cases where bits and equality disagree matter. `0.0` and `-0.0` are `=` but differ in bits, so zero is normalised — they dedupe to one entry and either spelling finds it. `NaN` needs no special case: it is `=` to nothing, itself included, so a `NaN` key can never be found again whatever it hashes to. Prefer an exact-valued key (a scaled integer) where you need lookups to be reliable.

**Keywords as ergonomic map/set keys.** `Keyword` conforms to both `Hash` and `Eq`, making it the idiomatic lightweight key type when keys are known names rather than arbitrary strings. Because equality is identity (intern `id` compare) and hashing is a single cached load, keyword-keyed maps are faster than `CStr`-keyed ones (no `strcmp`, no byte walk):

```lisp
(import-use "stdio.h")
(import-use nucleus.strview) (import-use nucleus.hash) (import-use nucleus.keyword)
(import-use nucleus.allocator) (import-use nucleus.coll) (import-use nucleus.iterator) (import-use nucleus.hashmap)

(defn main ():i32
  (with ((m (ref (HashMap Keyword i32))) (alloca (HashMap Keyword i32)))
    (init m)
    (assoc m :width 1920)
    (assoc m :height 1080)
    (match (get m :width)
      ((some v) (printf "width=%d\n" v))   ; width=1920
      (none     (printf "absent\n"))))
  (return 0))
```

See [Keyword literals](types.md#keyword-literals----foo) in the Types reference for the full semantics and the `(import-use nucleus.keyword)` requirement.

**Conforming a user type:** extend `Hash` and provide the `hash` method:

```lisp
(extend MyType Hash)
(defn hash ((self (ref MyType))):usize
  ...)
```

---

## `Vector T` (`lib/nucleus/vector.nuc`)

`(import-use nucleus.vector)` provides a dynamically-sized, heap-backed mutable sequence. Append is O(1) amortized (capacity doubles); indexed access and `insert` are O(1) and O(n) respectively. Conforms to `(Coll T (VecIter T))`, `(Seq T)`, and `Drop`.

### Construction

**`make` and `new`** (`(import-use nucleus.create)`, see [allocators.md](allocators.md#creating-an-object-in-one-call-new-and-make)) take the type as an operand, so they need no annotation: `(make (Vector i32) heap)` is an empty vector by value, `(make (Vector i32) heap [1 2 3])` one filled from a literal, `(make (Vector i32) a v)` a copy of `v` (`(InitFrom (Vector T))`), and `(new (Vector i32) a)` a vector whose header also comes from `a`. `Vector` conforms to `Init`, so `(init v a)` initializes in place and `(init v)` uses `heap`.

`(make (Vector i32))` is `(make (Vector i32) heap)`. Without `nucleus.create`, initialize in place:

```lisp
(with ((v (ref (Vector i32))) (alloca (Vector i32)))
  (init v)                 ; empty, on the heap
  (conj v 10) (conj v 20) (conj v 30)
  ...)                     ; (drop v) fires here, freeing the buffer

(let (w:&(Vector i64) (alloca (Vector i64)))   ; a slot, not yet usable
  (init w (handle g-arena))                    ; any Alloc
  (reserve w 64)                               ; capacity: initialize, then reserve
  ...)
```

| Init | Signature | Description |
|------|-----------|-------------|
| `init` | `(v:&(Vector T)):void` | Empty, on the heap (`nucleus.allocator`'s one-argument `init`). |
| `init` | `(v:&(Vector T) a:Alloc):void` | Empty, storing and allocating through `a`. |
| `init` | `(v:&(Vector T) a:Alloc src:&(Vector T)):void` | A copy of `src` (also by value). |

An owning collection may not escape by `return` without `move`; `new` places it in an allocator and returns an escapable `&(Vector T)`.

### Operations

```lisp
; Coll T
(count:usize    ((self (ref (Vector T)))))
(conj:void      ((self (ref (Vector T))) elem:T))
(empty?:i32     ((self (ref (Vector T)))))

; Seq T
(invoke:T       ((self (ref (Vector T))) i:usize))   ; called as (v i)
(set:void       ((self (ref (Vector T))) i:usize elem:T)) ; (set! (v i) x)
(append:void    ((self (ref (Vector T))) elem:T))
(contains?:i32  ((self (ref (Vector T))) elem:T))
(insert:void    ((self (ref (Vector T))) i:usize elem:T))
(remove-at:void ((self (ref (Vector T))) i:usize))

; Capacity
(capacity:usize ((self (ref (Vector T)))))
(reserve:void   ((self (ref (Vector T))) n:usize))
```

Bulk append (free functions, not protocol methods):

| Function | Signature | Description |
|----------|-----------|-------------|
| `vector-extend-raw` | `((self (ref (Vector T))) (p (ptr T)) n:usize) -> void` | Append `n` elements read from `p`: reserve once, `memcpy` once. `p` must not point into this vector's own buffer — the reserve may reallocate it. |
| `vector-extend` | `((self (ref (Vector T))) (other (ref (Vector T)))) -> void` | Append every element of `other`, which is left unchanged. |

Both are a single bulk copy rather than `conj` in a loop, which costs a bounds test, a capacity test and a call per element. The copy is bitwise — exactly what `conj`'s element store already is — so there is no narrower requirement on `T`. They are not spelled `extend`: that is the protocol-conformance form, and a symbol may name only one kind of thing.

`conj` and `append` are equivalent for `Vector` (both append at the back). `insert` with `i == len` is equivalent to `append`; `i > len` panics. `remove-at` deletes the element at index `i`, shifting `(i, len)` left by one; `i >= len` panics.

**Integer literals widen automatically.** A bare integer literal passed as an element, index, or key argument adapts to the method's concrete type without a cast — `(conj v 3)` and `(v 0)` on a `(Vector i64)` widen `3`/`0` to `i64`/`usize` respectively, exactly as plain functions already do. Some examples below still spell the explicit `(as usize 1)` form; both compile identically. (An untyped literal only *widens* — an already-typed value of a wider or wrong-sign type still needs an explicit `as`/`unsafe/cast`, and a call ambiguous between two integer overloads is an error.)

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

`doseq` calls `(iter v)` internally to obtain a fresh `VecIter i32` by value, binds it to a typed local, and drives `(next &it)` per step. The internal helper `iter-init` (fills a caller-allocated `VecIter`) is still available but is not the recommended surface for new code.

See [Iterators](iterators.md) for `doseq` / `doseq-iter` and the `Iterator` protocol.

### Full example

```lisp
(import-use "stdio.h")
(import-use nucleus.allocator)
(import-use nucleus.coll)
(import-use nucleus.iterator)
(import-use nucleus.vector)

(defn main ():i32
  (with ((v (ref (Vector i32))) (alloca (Vector i32)))
    (init v)
    (conj v 10) (conj v 20) (conj v 30)
    (printf "count=%llu\n" (as ui64 (count v)))     ; count=3
    (printf "get[1]=%d\n"  (v (as usize 1)))        ; get[1]=20
    (insert v (as usize 1) 15)
    (printf "after insert: %d\n" (v (as usize 1)))  ; 15
    (doseq (x v (VecIter i32)) (printf "elem=%d\n" x)))  ; 10 15 20 30
  (return 0))
```

---

## `HashMap K V` (`lib/nucleus/hashmap.nuc`)

`(import-use nucleus.hashmap)` provides an open-addressing hash map with linear probing and tombstone deletion. O(1) average `assoc`/`dissoc`/`get`. Conforms to `(Assoc K V (HashMapKeyIter K V) (HashMapValIter K V))`, `(Coll (Entry K V) (HashMapEntryIter K V))`, and `Drop`. Keys must conform to `Hash` and `Eq`.

**Implementation:** three parallel byte arrays (keys, vals, states). Capacity is always a power of two; a 75% load factor triggers doubling. Tombstone entries are skipped during lookup and dropped on resize.

### Construction

```lisp
(with ((m (ref (HashMap CStr i32))) (alloca (HashMap CStr i32)))
  (init m)
  (assoc m "one" 1)
  (assoc m "two" 2)
  ...)   ; (drop m) fires here
```

| Init | Signature | Description |
|------|-----------|-------------|
| `init` | `(m:&(HashMap K V)):void` | Empty, on the heap, initial capacity 8. |
| `init` | `(m:&(HashMap K V) a:Alloc):void` | Empty, storing and allocating through `a` (e.g. `(handle g-arena)`), initial capacity 8. |

`HashMap` conforms to `Init`, so `(make (HashMap K V))` is an empty map by value and `(make (HashMap K V) a {k v …})` fills one from a literal ([allocators.md](allocators.md#creating-an-object-in-one-call-new-and-make)).

### Operations

```lisp
; Assoc K V (HashMapKeyIter K V) (HashMapValIter K V)
(assoc:void        ((self (ref (HashMap K V))) key:K val:V))
(set:void          ((self (ref (HashMap K V))) key:K val:V))  ; (set! (m k) v)
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
  (printf "key=%s val=%d\n" (&e key) (&e val)))
```

`doseq` calls `(iter m)` to get a fresh `HashMapEntryIter` by value, binds it to a typed local, and drives `(next &it)`. Each element `e` is yielded by value; use `&e` to access its fields.

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
  (doseq-iter (k &kit)
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
  (doseq-iter (v &vit)
    (printf "val=%d\n" v)))
```

The lower-level fill helper `hmap-iter-vals` is still available but is not the recommended surface.

Iteration order is hash-dependent and unspecified for both `keys` and `vals`.

### Full example

```lisp
(import-use "stdio.h")
(import-use nucleus.allocator)
(import-use nucleus.coll)
(import-use nucleus.iterator)
(import-use nucleus.hash)
(import-use nucleus.hashmap)

(defn main ():i32
  (with ((m (ref (HashMap CStr i32))) (alloca (HashMap CStr i32)))
    (init m)
    (assoc m "one" 1) (assoc m "two" 2) (assoc m "three" 3)
    (printf "count=%llu\n" (as ui64 (count m)))  ; 3
    (match (get m "two")
      ((some v) (printf "two=%d\n" v))             ; two=2
      (none     (printf "absent\n")))
    (dissoc m "one")
    (printf "count=%llu\n" (as ui64 (count m)))) ; 2
  (return 0))
```

---

## `HashSet T` (`lib/nucleus/hashset.nuc`)

`(import-use nucleus.hashset)` provides an open-addressing hash set with linear probing. O(1) average `insert`/`contains?`/`set-remove`. Conforms to `(Coll T (HashSetIter T))`, `(Set T)`, and `Drop`. Members must conform to `Hash` and `Eq`.

**Implementation:** two parallel byte arrays (keys buffer and state buffer). Same open-addressing layout as `HashMap`; same 75% load-factor doubling policy.

### Construction

```lisp
(with ((s (ref (HashSet CStr))) (alloca (HashSet CStr)))
  (init s)
  (insert s "dog") (insert s "cat")
  ...)   ; (drop s) fires here
```

| Init | Signature | Description |
|------|-----------|-------------|
| `init` | `(s:&(HashSet T)):void` | Empty, on the heap, initial capacity 8. |
| `init` | `(s:&(HashSet T) a:Alloc):void` | Empty, storing and allocating through `a` (e.g. `(handle g-arena)`), initial capacity 8. |

`HashSet` conforms to `Init`, so `(make (HashSet T))` is an empty set by value and `(make (HashSet T) a #{x …})` fills one from a literal ([allocators.md](allocators.md#creating-an-object-in-one-call-new-and-make)).

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

`insert` is a no-op if the element is already present. The set-algebra methods mutate `self` in place.

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

`doseq` calls `(iter s)` to get a fresh `HashSetIter i32` by value and drives `(next &it)` per step. The internal helper `hashset-iter` (fills a caller-allocated `HashSetIter`) is still available but is not the recommended surface for new code.

Iteration order is hash-dependent and unspecified.

### Full example

```lisp
(import-use "stdio.h")
(import-use nucleus.allocator)
(import-use nucleus.coll)
(import-use nucleus.iterator)
(import-use nucleus.hash)
(import-use nucleus.hashset)

(defn main ():i32
  ; Basic membership
  (with ((s (ref (HashSet CStr))) (alloca (HashSet CStr)))
    (init s)
    (insert s "dog") (insert s "cat") (insert s "fish")
    (printf "contains dog: %d\n"  (contains? s "dog"))   ; 1
    (printf "contains bird: %d\n" (contains? s "bird"))  ; 0
    (set-remove s "cat")
    (printf "contains cat: %d\n"  (contains? s "cat")))  ; 0

  ; Set algebra (i32 elements)
  (with ((a (ref (HashSet i32))) (alloca (HashSet i32)))
    (init a)
    (insert a 1) (insert a 2) (insert a 3) (insert a 4)
    (with ((b (ref (HashSet i32))) (alloca (HashSet i32)))
      (init b)
      (insert b 3) (insert b 4) (insert b 5) (insert b 6)
      (union a b)
      (printf "union count: %llu\n" (as ui64 (count a))))) ; 6
  (return 0))
```

---

## `Node` (`lib/nucleus/node.nuc`)

`(import-use nucleus.node)` provides the compiler's own AST type. A list `Node` is a
header over an array of element pointers — the same shape as a `Vector` — so it
conforms to `(Coll (ref Node) NodeIter)` and `(Seq (ref Node))`. A form read
from source is an ordinary collection: `count`, `(xs i)`, `conj`, `append`,
`insert`, `contains?`, `doseq` and `into` all work on it.

```lisp
(import-use nucleus.node)
(import-use nucleus.coll)
(import-use nucleus.iterator)

(let (xs:&Node (unsafe/cast &Node `(10 20 30))
      i:usize 1)
  (count xs)             ; 3
  ((xs i) 'i)            ; 20 — index, then read a field of the element
  (xs 'kind)             ; NODE-LIST — a selector naming a field wins over `invoke`
  (conj xs (node-int 40))
  (doseq (e xs NodeIter)
    (printf " %ld" (e 'i))))
```

The element type is `(ref Node)`, not `(ptr Node)`: `iter` yields non-null
references, so `next` can answer `none` at the end. `NodeIter` borrows the
list's array and must not outlive it.

Two differences from the other collections:

- **`(xs 'kind)` is a field read, not an index.** A quoted selector naming a
  field of the receiver takes precedence over the `Seq` `invoke` method, so the
  struct fields (`kind`, `line`, `i`, `s`, `len`) stay reachable on a type that
  is also indexable. See [Callable values](special-forms.md#callable-values-non-function-call-position).
- **`Node` does not conform to `Drop`.** Nodes live in the compiler's arena and
  are freed wholesale, so a `Node` is never `with`-bound.

`Node` is not a *replacement* for `Vector`: it stores `(ptr Node)` elements
only, it grows through `node-push` rather than a generic element store, and it
has no parametric element type. It is a collection so that macro and tooling
code can treat a form the way it treats any other sequence. See
[Macros](macros.md#a-form-is-a-collection) for the macro-body spelling
(`ast-first` / `ast-rest` / `ast-at` / `ast-len`), which differs because a macro
body is compiled against the *program's* prelude but handed the *compiler's*
nodes.

---

## Literal sugar (`[…]`, `{…}`, `#{…}`)

A bracket literal is a **`Const`**: a read-only `{data, len}` view over a table
the compiler lays out. Commas are whitespace, so `{:a 1, :b 2}` is `{:a 1 :b 2}`.

| Literal | Type | Table |
|---|---|---|
| `[e1 e2 …]` | `(ConstVec E)` | source order |
| `#{e1 e2 …}` | `(ConstSet E)` | sorted, no duplicates |
| `{k1 v1 k2 v2 …}` | `(ConstMap K V)` | `(Entry K V)` sorted by key, keys distinct |

The three templates live in `lib/nucleus/const.nuc`. A literal needs
`nucleus.const` in the file's import closure, which every collection import
brings; **calling a method on one** (`count`, `contains?`, `get`, `iter`, `(v i)`)
needs `(import-use nucleus.const)` in the file itself, and the no-match error
says so. `(Const C)` names the type for a collection `C`: by the shape protocol
`C` conforms to, `(Const (HashMap K V))` is `(ConstMap K V)`, `(Const (HashSet
E))` is `(ConstSet E)`, `(Const (Vector E))` is `(ConstVec E)`, and a user type
conforming to `Assoc`, `Set` or `Seq` (checked in that order) gets the matching
one. A generic function may take `(Const (Vector T))` and friends.

```lisp
(import-use nucleus.const)

(defn delimiter? (c:i32):bool
  (return (contains? #{40 41 91 93 123 125 59 34} c)))   ; a sorted [8 x i32] table

(defn mean (xs:(Const (Vector f64))):f64
  (let (s:f64 0.0)
    (doseq (x xs (ConstIter f64)) (set! s (+ s x)))
    (return (/ s (unsafe/cast f64 (count xs))))))

(mean [1 2 4.5])                                         ; 2.5: the table is f64
```

A literal of constants costs no allocation, `init` or `drop`: it is a private
constant global and a two-word header. A `Const` has `count`, `empty?`, `iter`
(a `ConstIter`), `contains?`, and per shape `(v i)`, or `get`/`(m k)`/`keys`/`vals`.
It has no mutating method: `(conj s 3)` on a `ConstSet` is a no-match error with
the note `a Const collection is read-only -- build one with (make (HashSet i32) heap ...)`.

**Order and duplicates.** Sets and maps iterate in ascending order, and that
order is reliable. Constant tables are sorted at compile time, in this order:

| Type | Order | Duplicates |
|---|---|---|
| `i8`…`i64`, `ssize` | signed | equal values |
| `ui8`…`ui64`, `usize`, `bool`, `Char` | unsigned | equal values |
| `f32`, `f64` | numeric | `0.0` and `-0.0` are one value, as under `=` |
| `StrView` | bytes, then length | equal bytes |
| `CStr` | bytes to the NUL | equal bytes |

A duplicate set member or map key among constants is a compile-time error
(`duplicate key "a" in a map literal`). The order is `const-cmp`, reached through
the `nucleus.coll/ConstOrd` protocol; `StrView`'s lives in `nucleus.strview`,
`Char`'s in `nucleus.char` and `f64`'s in `nucleus.numeric`, so a set or map
literal of those needs that import (the error names it). `const.nuc` itself
never reaches `f64`, so literals work on AVR (`examples/avr-const.nuc`).

**Non-constant elements.** Elements may be any typed expression — a variable, a
`defenum` member, a call — evaluated left to right, keys before values. A literal
with a non-constant element is filled in a frame array, and a set or map is then
sealed at run time by `const-seal`: sorted, duplicates dropped, a later map key
winning. The header points into the frame, so it carries the frame's escape
taint: returning it, or storing it anywhere that outlives the frame, is refused
(see [Pointer lifecycle](special-forms.md#pointer-lifecycle-escape-analysis)).
Quoted symbols and keywords always take this path, ordered by identity, so
`(contains? #{'let 'do} head)` is an identity lookup with no allocation.
A struct element needs a `const-cmp` overload and `(extend T ConstOrd)`.

**The want decides what is built.**

| Where the literal is | Result |
|---|---|
| no declared type (an untyped `let`, a `contains?` operand) | `(Const C)`, `C` inferred from the elements |
| declared `(Const C)` (a binding, a parameter, a return) | that type; the elements adapt to it |
| declared `(Vector E)`, `(HashSet E)`, `(HashMap K V)` by value | a heap collection, built by one `init` from the `Const` |
| declared `(ref C)` (`with ((v (ref (Vector i32))) [1 2 3])`) | the same, in a stack header |
| a call argument whose parameter is a `Const` of the literal's shape | that parameter's type |
| `defconst NAME <literal>` | a constant table; `NAME` holds the header |
| a `defvar` of a `Const` type | a constant table, or, with a run-time element, a global array filled and sealed at startup |

```lisp
(let (v:(Vector i64) [1 2 3])                  ; a heap vector; drop it, or bind with `with`
  (conj &v 4))
(with ((s (ref (HashSet StrView))) #{"a" "b"})  ; a heap set, dropped at scope exit
  (conj s "c"))
(defconst KEYWORDS #{"if" "else" "while"})       ; a sorted table of StrView
(make (Vector i64) heap [1 2 3])                 ; make/new from a literal: one init
```

For a call argument the parameter supplies the want. For an overloaded or
generic callee, the other arguments' types bind its type variables first, and
the want comes from the one candidate whose parameter there is a `Const` of the
literal's bracket shape: `(contains? #{1 2 3} x)` at `x:i64` lays out `i64`s,
and overloads on `(Const (Vector i32))` and `(Const (HashSet i32))` are told
apart by `[…]` versus `#{…}`. A call never allocates for a literal: passing one
to a `(Vector i64)` or `&(Vector i64)` parameter is an error naming
`(make (Vector i64) heap …)`.

**Element-type inference.** With no want, the type comes from the elements, in
two tiers. An **integer or float literal adapts** to whatever the other elements
settle on — `[1 n]` at `n:i64` is a `(ConstVec i64)`. Everything else is
**fixed and must agree**: a string literal is `StrView` (a `c"…"` is `CStr`), a
keyword `Keyword`, a quoted symbol `(ref Node)`, and any other expression its
own type. With only adaptable literals the defaults are `i32` and `f64`. Under a
want each element is checked as a call argument would be, so a value is never
narrowed to suit the collection: `[n 1]` at a `(Vector i32)` with `n:i64` is
`vector literal: element n (i64) does not fit i32`, and `300` in a
`(Const (HashSet ui8))` is `integer literal 300 does not fit ui8`.

**A keyword literal needs `(import-use nucleus.keyword)`.** `Keyword` is defined
in `lib/nucleus/keyword.nuc`, which the collection imports do not reach. Keywords
are the idiomatic key type when keys are known names.

```lisp
(with ((m (ref (HashMap Keyword i32))) {:width 640 :height 480})
  (match (m :width) ((some w) (printf "%d\n" w)) (none (printf "?\n"))))
```

**Errors.** Each of these is a compile-time error:

- **An empty literal with no declared type** (`[]`, `{}`, `#{}`) — nothing to
  infer from; the message names `make`. With a declared type an empty literal
  is the empty `Const`, or an empty collection.
- **Mixed element types** without a want (`[1 2.0 3]`, `[a b]` at `a:i32
  b:i64`) — types do not widen against each other.
- **An element that does not fit the want**, as above.
- **A duplicate** constant member or key, as above.
- **An odd map element count** (`{"a" 1 "b"}`).
- **A frame-backed literal escaping**, as above. `(defvar g:&(Vector i32) [1 2
  3])` is refused for the same reason; `(defvar g:(Vector i32) [1 2 3])` copies
  the header out and owns the heap buffer.

A bare `a` in a literal is a **variable reference**, as everywhere else. A
symbol element is written `'a`; `'(a b)` and `'1` are `(ptr Node)`, not
`(ref Node)`, and are refused in a `(ref Node)` collection.

Success paths live in `examples/{vector,hashmap,hashset,keyword}-lit-test.nuc`
and `tests/suite-const.nuc`; the refusals are the `cl3-*` rows of
`tests/manifest/diagnostics.edn` and the `s16-*lit-refused-*` units in
`tests/suite-s16.nuc`.

---

## Gotchas and constraints

**Parametric method parameter syntax.** A parameter or return type written as a parenthesised form may use either the list binding form `(self (ref (Vector T)))` or the colon-paren sugar `self:(ref (Vector T))` (and the chain form `self:ref:(Vector T)`); they are equivalent. A plain-symbol colon chain tokenises correctly: `count:usize`, `self:ptr:Self`.

**`usize` literals.** There is no dedicated `usize` literal token; a bare integer literal widens automatically to `usize` wherever a target type is known (call arguments, assignment, comparisons — see above). Where no target type is available, force it explicitly with `(as usize N)`.

**`(Maybe V)` element types.** `(Maybe ptr)` is niche-encoded as a nullable pointer and cannot be used with `match`. Use value types (`i32`, `i64`, `CStr`) as the value type `V` in `HashMap` and the element type in `(Maybe T)` returns.

**No zero value.** A collection stores an `Alloc`, which cannot be null, so `(defvar g:(Vector i32))` and a struct literal that leaves a collection field unset are refused. Give a global an initializer (`(make (Vector i32))`, or a literal) and initialize a slot with `init`; see [allocators.md](allocators.md#the-zero-value).

**Owning collections and scope.** Owning collections store their allocator handle by value and must not escape their `with` binding by return or store-out. `Drop` fires at scope exit; a double-drop is a no-op (the pointer is nulled). The `move` form (when available) transfers ownership.

**`HashMap` `conj` takes an `Entry`, not a raw value.** `(conj m e)` inserts the `(Entry K V)` pair `e` into the map. Use `assoc` directly when key and value are already separate.
