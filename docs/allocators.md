# Allocators (`lib/nucleus/allocator.nuc`)

Collections own their buffers through an **allocator**, so the same `Vector`,
`String` or `HashMap` can live on the heap, in an arena, or in a fixed buffer,
and always frees through the allocator that built it.
`(import-use nucleus.allocator)` brings in the protocol, the stored handle
`Alloc`, and the four built-in allocators. `Drop` comes from
`(import-use nucleus.coll)`.

## The `Allocator` protocol

```lisp
(defprotocol Allocator
  (allocate   (self:&Self size:usize align:usize) ?&ui8)
  (reallocate (self:&Self (p ?&ui8) old:usize new:usize align:usize) ?&ui8)
  (deallocate (self:&Self (p ?&ui8) size:usize align:usize):void)
  (handle     (self:&Self):Alloc))
```

The contract:

- **Null is failure.** `allocate` and `reallocate` return null when they cannot
  satisfy the request. A failed `reallocate` leaves `p` valid.
- **`align` is honored.** It must be a power of two (0 reads as 1). Every
  built-in allocator returns memory aligned to it, and returns null for an
  alignment that is not a power of two.
- **Sizes are the caller's to remember.** `deallocate` and `reallocate` take the
  size `p` was allocated with. `Arena` and `FixedBuffer` use it to recognise the
  most recent allocation.
- **`deallocate` of null is a no-op**, as `free` is in C. `reallocate` of null
  is an `allocate`.
- **`handle` converts the allocator to an `Alloc`** (below), which is what a
  collection stores.

Every built-in allocator also conforms to `Drop`.

A literal size passed to a method adapts to `usize` when the allocator is
written as an address (`(allocate &heap 64 16)`, or a `&Arena` binding). With a
by-value receiver, `(allocate heap 64 16)`, the call is refused with a note
saying so.

## `Heap` and `heap`

`Heap` is libc `malloc`/`realloc`/`free`. It has no state, and the global
`heap` is the one instance a program needs. Its `drop` does nothing.

Alignments up to two words (16 bytes on 64-bit targets) are what `malloc`
already guarantees. A larger alignment over-allocates and keeps `malloc`'s own
pointer in the word before the returned one, so `deallocate` must be given the
same `align` as `allocate`.

```lisp
(let ((p ?&ui8) (allocate &heap 4096 64))   ; 64-byte aligned
  …
  (deallocate &heap p 4096 64))
```

## `Arena`

An arena bump-allocates from a chain of blocks that it gets from a **parent
allocator**, and frees them all at once.

```lisp
(defstruct Arena first:?&ArenaBlock cur:?&ArenaBlock off:usize block-size:usize parent:Alloc)
(arena-in (parent Alloc) (block-size usize)) -> Arena
```

- **A zero-filled `Arena` is an empty arena over the heap**, so
  `(defvar a:Arena)` needs no initializer. `(arena-in (handle &heap) 0)` is the
  same value written out.
- **Memory is zero-filled**, including the tail a `reallocate` adds.
- **Blocks.** The first allocation makes the first block. With `block-size` 0,
  blocks start at 8192 words (64 KiB on 64-bit) and double up to 256 times
  that (16 MiB). A non-zero `block-size` is every block's minimum. A request
  bigger than a block gets a block of its own.
- **`deallocate`** rewinds the bump pointer when `p` is the most recent
  allocation, and otherwise does nothing. So does `reallocate` when it shrinks.
  It grows the most recent allocation in place when the block has room, and
  otherwise copies into a new allocation and abandons the old one.
- **`(arena-reset a)`** rewinds to the first block and keeps every block, so the
  next round of allocations reuses them.
- **`drop`** returns every block to the parent. The arena is then empty and can
  be used again. Objects allocated from it are dangling.

## `FixedBuffer`

A `FixedBuffer` bump-allocates from a buffer it **borrows**: the current frame,
a global array, a block from `heap` or an `Arena`, or memory from C.

```lisp
(defstruct FixedBuffer buf:ptr len:usize off:usize live:usize)
(fixed-buffer (p ptr) (len usize)) -> FixedBuffer
(frame-buffer N)                    ; macro: N bytes of the expanding frame
```

- **Full returns null.** A collection then follows its out-of-memory path.
- **`deallocate` pops** when `p` is the most recent allocation (its end is the
  bump pointer), and otherwise does nothing. A sequence of frees in reverse
  order pops each, unless alignment padding sits between two allocations.
  `reallocate` grows or shrinks the most recent allocation in place.
- **`drop` does not release the buffer**; its owner does. It checks the count of
  live allocations instead, and prints
  `FixedBuffer: dropped with N live allocation(s)` to stderr when it is not
  zero. The count is kept in every build, at one add per call: the language has
  no checked-build mode to confine it to.
- **`frame-buffer`** is a macro because a function cannot reserve memory in its
  caller's frame. `N` must be a constant. The buffer dies with the frame, and
  the frame-escape analysis covers its address like any other frame address.

Bind the buffer first and the objects that use it after it, in the same `with`:
`with` drops in reverse order, so the objects are gone before the buffer is
checked.

```lisp
(with (s (frame-buffer 4096)
       h:Alloc (handle s)
       v:(Vector i32) (make (Vector i32) h))
  (dotimes (i:i32 100) (conj &v i)))       ; v dropped, then s: no leak report
```

## `Tracking`

A `Tracking` allocator forwards every call to a **parent allocator** and counts
what is outstanding, so a leak shows up when it is dropped (like Zig's
`GeneralPurposeAllocator`). It works over any parent: the heap, an `Arena`, a
`FixedBuffer`, or another `Tracking`.

```lisp
(defstruct Tracking parent:Alloc live:usize bytes:usize)
(make Tracking)       ; over the heap; a zero-filled Tracking is the same
(make Tracking a)     ; over allocator a (Tracking conforms to Init)
```

- **`live` and `bytes`** are the outstanding allocations and their total size.
  Read them as fields, `(t 'live)`. A failed `allocate` is not counted, and a
  `reallocate` moves `bytes` by the difference.
- **Over-freeing is reported.** A `deallocate` (or `reallocate`) that would take
  more than is outstanding prints
  `Tracking: deallocate of N byte(s) with L live allocation(s) of B byte(s)` to
  stderr and is not passed to the parent, which may not own the block. That
  catches a double free once everything else is freed, and a size larger than
  what was allocated. It cannot tell which block was meant: there is no record
  per allocation.
- **`drop` does not drop the parent**, which it only borrows. It prints
  `Tracking: dropped with L live allocation(s) of B byte(s)` when `live` is not
  zero. The count is kept in every build, as for `FixedBuffer`.
- **`(handle t)` is an `ALLOC-TRACKING` handle**, so any collection can store it.

Bind the tracker first, as with any allocator. Placed under an `Arena`, it checks
that the arena's `drop` returns every block:

```lisp
(with (t  (make Tracking)
       v  (make (Vector i32) t [1 2 3])
       s  (make String t "tracked"))
  …)                                        ; s, v, then t: no report

(with (t (make Tracking))
  (let (ar:Arena (arena-in (handle &t) 0))
    …
    (drop &ar)))                            ; t then sees 0 live
```

## The stored handle: `Alloc`

A collection stores one allocator value without knowing its type. That value is
an `Alloc`, a tagged handle:

```lisp
(defenum AllocKind ALLOC-HEAP ALLOC-ARENA ALLOC-FIXED ALLOC-CUSTOM ALLOC-TRACKING)
(defstruct Alloc kind:i32 data:ptr)
```

| Kind | `data` points at | Made by |
|---|---|---|
| `ALLOC-HEAP` | nothing (null) | `(handle &heap)`; also a zero-filled `Alloc` |
| `ALLOC-ARENA` | the `Arena` | `(handle a)` |
| `ALLOC-FIXED` | the `FixedBuffer` | `(handle f)` |
| `ALLOC-TRACKING` | the `Tracking` | `(handle t)` |
| `ALLOC-CUSTOM` | a `CustomAlloc` table | `(custom-alloc &table)` |

`Alloc` conforms to `Allocator` itself, so a collection calls
`(allocate (ref self 'alloc) n 8)` and the handle dispatches on its kind.
`(handle h)` of an `Alloc` is a copy. `Alloc` does not conform to `Drop`: it
borrows the allocator and never releases it.

**A handle borrows.** The allocator must outlive every object that stores its
handle (design/stage24-allocation/overview.md §8). The heap handle is the one
that can never dangle.

### A user allocator: `ALLOC-CUSTOM`

Any type can conform to `Allocator`. To be stored in a collection, it returns
an `ALLOC-CUSTOM` handle over a table of plain functions:

```lisp
(defstruct CustomAlloc
  instance:ptr
  allocate-fn:(fn ?&ui8)(ptr usize usize)
  reallocate-fn:(fn ?&ui8)(ptr ?&ui8 usize usize usize)
  deallocate-fn:(fn void)(ptr ?&ui8 usize usize))
```

Each function receives `instance` first. The table must outlive the handles
made from it; keeping it in the allocator itself does that:

```lisp
(defstruct Counting allocs:i32 vt:CustomAlloc)

(defn counting-allocate (inst:ptr size:usize align:usize) ?&ui8
  (let (c:&Counting (unsafe/cast &Counting inst))
    (set! (c 'allocs) (+ (c 'allocs) 1))
    (return (allocate &heap size align))))
; … counting-reallocate, counting-deallocate likewise

(extend Counting Allocator)
(defn allocate (self:&Counting size:usize align:usize) ?&ui8
  (return (counting-allocate self size align)))
; … reallocate, deallocate
(defn handle (self:&Counting):Alloc
  (set! (self 'vt) (CustomAlloc self counting-allocate counting-reallocate
                                counting-deallocate))
  (return (custom-alloc (ref self 'vt))))
```

The method names do not collide with libc: a unit that defines them still calls
`malloc` and `free` as usual.

### Code the compiler generates

A `cfn` closure environment allocates through `alloc-allocate`,
`alloc-reallocate` and `alloc-deallocate`, the plain functions behind `Alloc`'s
methods, because a generic has no single symbol to call. A boxed value (a
`BoxedFn` or `(dyn P)` payload) always comes from the heap, through
`heap-allocate`; either needs `(import-use nucleus.allocator)`.

## Initialization: `Init`, `InitFrom`, `TryInitFrom`

An object that owns storage is set up by one method name, `init`, whose second
argument is the allocator the object stores and frees through. The protocols
are in `nucleus.allocator`:

```lisp
(defprotocol Init               (init (self:&Self a:Alloc):void))
(defprotocol (InitFrom V)       (init (self:&Self a:Alloc v:V):void))
(defprotocol (TryInitFrom V)    (init (self:&Self a:Alloc v:V):!void))
```

- `Init` is the empty object. `(InitFrom V)` initializes from a source value of
  type `V`. `(TryInitFrom V)` is for a source that can be refused, and returns
  `!void`.
- `InitFrom` and `TryInitFrom` both extend `Init`, so a type conforming to
  either must also conform to `Init`, and `(conforms? T Init)` is the one
  question that tells an initialized type from a plain struct.
- **Omitting the allocator.** `(init x)` is `(init x (handle heap))` for any
  `Init` type. One generic supplies it.
- **Capacity is not a source.** Initialize, then call `reserve`.
- A type conforms to a parametric protocol at most once
  ([generics.md](generics.md#parametric-protocols)), so a second source of the
  same kind is an extra `init` overload rather than a conformance. `new` and
  `make` reach it all the same, but `conforms?` does not report it.

| Type | Conforms to | Other `init` sources |
|---|---|---|
| `(Vector T)` | `Init`, `(InitFrom (Vector T))` (a copy) | `&(Vector T)` (a copy); a `[…]` literal through `new`/`make` |
| `(HashMap K V)` | `Init` | a `{…}` literal through `new`/`make` |
| `(HashSet T)` | `Init` | a `#{…}` literal through `new`/`make` |
| `String` | `Init`, `(InitFrom StrView)`, `(TryInitFrom (Vector ui8))` | `&String` (a copy), `&(Vector ui8)` (strict) |

`String` from a `StrView` is lossy: each byte that does not decode as UTF-8
becomes U+FFFD. This means a string literal never makes the result fallible. From
bytes in a `Vector ui8` it is strict, and returns `invalid-utf8`. `init` is
also how a user type takes part:

```lisp
(defstruct Counter n:i32 a:Alloc)
(extend Counter Init)
(defn init (self:&Counter a:Alloc):void
  (set! (self 'n) 0)
  (set! (self 'a) a))
```

A collection or `String` is set up by `init`. In place, initialize a zero
literal or a slot; in one call, use `make` or `new` (below):

```lisp
(let (s:String (String))      ; a zero String, not yet usable
  (init &s)                   ; now empty, on the heap
  …)
(with (v:&(Vector i32) (alloca (Vector i32)))
  (init v (handle g-arena))   ; any Alloc value
  …)
```

## Creating an object in one call: `new` and `make`

`(import-use nucleus.create)` adds two macros:

```lisp
(new T a args…)    ; → &T: T's own bytes come from allocator a
(make T a args…)   ; → T by value, in the caller's frame; storage it owns comes from a
(make T)           ; (make T heap)
```

Both do the same steps:

1. Get bytes of `T`'s size and alignment. `new` calls `allocate` on `a`,
   zero-fills the bytes, and exits with `new: out of memory` on failure. `make`
   uses a frame slot.
2. If `T` conforms to `Init`, call `(init p (handle a) args…)`. With no args
   this is `Init`. With one, it is whichever `init` overload the value's type
   selects. A `[…]`, `#{…}` or `{…}` literal argument becomes `init` followed by
   one `conj` (or `assoc`) per element, because initializing from the literal's
   temporary would leak its buffer.
3. Otherwise, build `T` like a struct literal, `(new Pt a 1 2)`, or zero-fill it
   when there are no args. A union works the same way, `(make Shape heap rect 1.0 2.0)`.

**The result is `!` exactly when the selected `init` returns `!void`.** That is
`!&T` for `new` and `!T` for `make`. On the error path `new` gives its bytes
back to `a` before returning the error, so a refused `new` leaks nothing.

```lisp
(with (v  (make (Vector i32) heap [1 2 3])        ; header in the frame, buffer on the heap
       w  (make (Vector i32) heap v))             ; a copy
  …)
(let (s (new String g-arena "prelude")) …)        ; header and buffer in the arena
(with (buf (frame-buffer 1024)
       k   (make String buf "key"))               ; dropped in reverse: k, then buf
  …)
(match (make String heap bytes)                   ; bytes:(Vector ui8) → !String
  ((ok s) …)
  ((err e) …))
```

**The allocator operand** is any expression `handle` accepts: an allocator
binding or global, which is passed by address implicitly (`heap`, `g-arena`, a
`FixedBuffer` local, an `Alloc` value), or a pointer to one (`&ar`, a `&Arena`
parameter). It is evaluated once. The object stores `(handle a)`, a handle that
points back at the allocator, so the allocator must outlive the object. That is
the reason `with` drops in reverse order. A call result such as
`(new T (frame-buffer 64))` is refused, because a handle cannot point into a
temporary.

What `new` and `make` refuse:

| Misuse | Diagnostic |
|---|---|
| `(new T)` | `new: name the allocator, as in (new T heap)` |
| two or more values for an `Init` type | `new/make: an Init type takes one value after the allocator` |
| a value no `init` accepts | the ordinary `no matching method for overloaded 'init'` with one note per candidate |
| an operand that is not an allocator | `no matching method for overloaded 'handle'` |

`new` and `make` are macros, so a program that loads `nucleus.create` cannot also
define a function named `new` or `make`. A prefixed import does not avoid this.
For the same reason no `lib/nucleus` module imports `nucleus.create`: each one
initializes with `init` instead, so loading a library never claims the names.
Their templates call `nucleus.allocator/init`, so a program's own function named
`init` does not interfere with them.

`alignof` (a special form, like `sizeof`) gives the alignment the size and
alignment steps use.

## The process arena (`lib/nucleus/arena.nuc`)

`(import-use nucleus.arena)` adds one process-lifetime `Arena`, `g-arena`, that
nothing drops. The compiler and the node runtime allocate from it.

| Name | Signature | Use |
|---|---|---|
| `g-arena` | `Arena` | zero-initialized; the first allocation makes a block |
| `arena-alloc` | `(n:i64) -> ptr` | `n` zeroed, 8-byte-aligned bytes from `g-arena`; never null (exits on failure) |
| `arena-bytes` | `(src:ptr n:i64) -> ptr` | `n` bytes copied into `g-arena` |

`g-arena` is an ordinary allocator: `(handle g-arena)` is its handle, and
`(new T g-arena)` places one `T` in it. A handle on `g-arena` can also be a
constant, so it is valid before any initializer runs:
`(defvar my-alloc:Alloc (Alloc ALLOC-ARENA &g-arena))`. A global built by
`new`, such as `(defvar g-names:&(Vector Symbol) (new (Vector Symbol) g-arena))`,
is set up by the program's startup initializer like any other call.

Example: `examples/allocator-test.nuc`.
