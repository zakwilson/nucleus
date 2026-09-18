# Allocators (`lib/allocator.nuc`, Stage 11)

The collection library owns and frees memory through an **allocator** rather than
a bare `malloc`, so a collection can be built against libc, an arena, or a future
allocator and still free with the same backend that built it. `(import-use allocator)`
brings in the protocol, the handle type, the backends, and a default.

## The `Allocator` protocol

The documented contract (Zig-shaped). `align` is part of the contract even where
a backend ignores it. The byte type is `(raw ui8)` (= C `unsigned char *`):

```lisp
(defprotocol Allocator
  (alloc   (self:&Self size:usize align:usize) (raw ui8))
  (realloc (self:&Self (p (raw ui8)) old:usize new:usize align:usize) (raw ui8))
  (free    (self:&Self (p (raw ui8)) size:usize align:usize):void))
```

A method's return type follows its parameter list — `(raw ui8)` as a list, or
attached as `):void` / `):(raw ui8)`; `(p (raw ui8))` and `p:(raw ui8)` are the
same parameter.

## Runtime dispatch: `AllocHandle`

A collection stores **one** allocator handle field and dispatches through it
without knowing the concrete backend — the design's "stored field" plumbing. The
protocol system is static-only (no vtables) and `unsafe/funcall-ptr-*` cannot call a
3+-arg function pointer, so dispatch is a **tagged handle**, not a vtable:

```lisp
(defenum AllocKind ALLOC-LIBC ALLOC-ARENA)
(defstruct AllocHandle kind:i32 data:ptr)
```

| Helper | Signature | Behaviour |
|--------|-----------|-----------|
| `alloc-handle-alloc` | `((h (ref AllocHandle)) size:usize align:usize) -> (raw ui8)` | libc `malloc`, or `arena-alloc`; `kind` selects |
| `alloc-handle-realloc` | `((h (ref AllocHandle)) (p (raw ui8)) old:usize new:usize align:usize) -> (raw ui8)` | libc `realloc`, or arena fresh-alloc + `memcpy` of `min(old,new)` |
| `alloc-handle-free` | `((h (ref AllocHandle)) (p (raw ui8)) size:usize align:usize) -> void` | libc `free`, or no-op for the arena |

## Default and constructors

| Function | Signature | Use |
|----------|-----------|-----|
| `default-allocator` | `() -> (ref AllocHandle)` | the process-global libc handle; backs convenience constructors that omit an allocator |
| `libc-allocator` | `((h (ref AllocHandle))) -> (ref AllocHandle)` | initialise a caller-owned slot as a libc handle |
| `arena-allocator` | `((h (ref AllocHandle))) -> (ref AllocHandle)` | initialise a caller-owned slot as an arena handle (state lives in `lib/arena.nuc`'s globals) |

A collection stores the `AllocHandle` by value; use `(addr-of coll 'alloc-field)` to get
a `(ref AllocHandle)` into it for the helpers. Example: `examples/allocator-test.nuc`.

**Why no static `(extend MyAlloc Allocator)` in the library.** A generic method
literally named `free`/`realloc`/`malloc` shadows the libc symbol of that name for
the whole compilation unit (this is why `Drop` uses `drop`), and such a
conformance currently cannot be `import`ed at all — the imported file's transitive
`(import-use "stdlib.h")` re-declares the libc symbol before the importing generics
finalize. A conformance defined *directly* in the consuming unit does compile.
See `design/stage11/progress.md` (M1) for the details and the deferred compiler fix.
