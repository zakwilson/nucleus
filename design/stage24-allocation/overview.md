# Stage 24 — allocation and initialization

**Status: designed 2026-10-07; Q1–Q6 ruled 2026-10-07 (§10), every one as
recommended.** Built so far: `conforms?` (CQ-1…CQ-4,
[conformance-query.md](conformance-query.md)) and keyword-free union
construction, which freed `make`. AL-0 is next. Q5 and Q6 are to be revisited
after use ([deferred/overview.md](../deferred/overview.md)).
The brief's "stack" allocator is named `FixedBuffer` (ruled 2026-10-07): it is a
bump allocator over any borrowed buffer, and only the `frame-buffer` macro puts
that buffer in a frame (§4.2).

## 1. The brief

1. There is a protocol for allocators but none for creating objects. Each
   standard collection has its own prefixed constructors (`string-new`,
   `hashmap-new`, …). Allocation and initialization should both be protocols.
2. Allocating and initializing an object, with an allocator and optionally a
   value, should take one call.
3. Nothing extends the `Allocator` protocol.
4. Heap, stack and arena allocators should be available out of the box. (The
   "stack" allocator became `FixedBuffer`, §4.2.)
5. Allocators should extend `Drop`. What happens when an allocator is dropped
   while objects allocated from it are still alive? Should that be handled
   automatically, or left to the programmer as a contract?

## 2. Ground truth (measured 2026-10-07)

Probes ran against `bin/nucleusc` at `26ae536`. The probe sources are not kept.
Each probe is described where it is used.

### 2.1 `Allocator` is inert

`lib/nucleus/allocator.nuc` declares `Allocator`, with methods
`alloc`/`realloc`/`free` over `&Self`. No `extend` of it exists in `lib/`,
`src/`, `examples/` or `tests/`. Collections dispatch through `AllocHandle`
instead. That is a `{kind:i32 data:ptr}` struct with two kinds, `ALLOC-LIBC`
and `ALLOC-ARENA`. Three `alloc-handle-*` functions branch on `kind`. `data` is
null for both kinds.

The file's header comment gives three reasons it could not use a static
conformance. They have aged differently:

| Stage 11 reason | Now |
|---|---|
| `funcall-ptr-*` cannot call a 3+-argument function pointer, so a hand-built vtable is impossible | **Stale.** A struct field typed `(fn ptr)(ptr usize usize)` is called with three arguments and returns correctly. |
| A method named `free`/`realloc` shadows the libc symbol for the whole unit | **Still true, and wider than documented.** A user file that defines `(defn free (self:&Heap p size align):void …)` breaks the *library's* libc call: `lib/nucleus/allocator.nuc:125: error: call to 'free': expected 4 args, got 1`. With `realloc` defined, the same failure appears at `:116`. |
| Such a conformance cannot be imported | Follows from the row above. |
| *(implied)* Collections need dynamic dispatch, and protocols are static | Still true. `(dyn P)` boxes only single-method protocols (the `num-sigs` gate in `dyn-vtable-method-irname-in`). `Allocator` has three methods. |

With the methods renamed (`allocate`/`deallocate`), a user `Heap` struct
conforms to `Allocator` and to `Drop`. Calls work alongside a libc `free` in the
same unit, and a `with`-bound `Heap` runs its `drop` at scope exit. The protocol
is blocked by its method names, not by the language.

### 2.2 The arena is a process singleton, not a type

`lib/nucleus/arena.nuc` is three globals (`g-arena`, `g-arena-used`,
`g-arena-cap`) and `arena-alloc`. Consequences:

- **There is exactly one arena.** `arena-allocator` builds a handle with
  `data = null` because there is no instance for it to point at.
- **It cannot be released or reset.** No function frees or rewinds it.
- **`arena-grow` loses the previous block.** It overwrites `g-arena` with the
  new block and keeps no pointer to the old one. Old pointers stay valid, as its
  comment says, but the old block can never be freed.
- **`align` is ignored.** Sizes are rounded to 8 bytes. A request for 16-byte
  alignment can get an address that is only 8-byte aligned. The libc arm also
  ignores `align`, which is harmless up to `malloc`'s 16 bytes.
- `(new T)` in the same file is an arena-only macro. It has 74 uses in `src/`
  and `lib/`.

### 2.3 There is no allocator over frame or fixed storage

Frame storage reaches collections only as an `alloca`'d header, such as
`(with (v:&(Vector i32) (alloca (Vector i32))) (vector-init v) …)`, and the
buffer still comes from the heap. The Stage 21 frame-escape analysis
([stage21-cleanup/frame-storage-escape.md](../stage21-cleanup/frame-storage-escape.md))
already refuses to let frame addresses escape into globals.

### 2.4 Construction is a separate family per type

| Type | Constructors |
|---|---|
| `Vector` | `vector-init`, `-init-alloc`, `-init-capacity`, `vector-new`, `-new-alloc`, `-new-capacity`, `-new-in` (7) |
| `HashMap` | `hashmap-init`, `-init-alloc`, `hashmap-new`, `-new-alloc`, `-new-in` (5) |
| `HashSet` | same shape as `HashMap` (5) |
| `String` | `string-new`, `-new-alloc`, `string-with-capacity`, `string-from-view`, `string-from-cstr[-unchecked]` |

The suffixes encode three separate choices in the function name:

- `-init` versus `-new`: where the struct itself lives (a caller slot or a
  returned value).
- `-in`: whether the struct itself comes from the allocator.
- `-alloc`: whether the buffers come from an explicit allocator.

Every new collection must repeat the whole set. The compiler is the main user,
with about 134 `vector-new-in` sites and 45 `string-new` sites. Separately,
`docs/collections.md:211` still says Vector has no value constructor, which
stopped being true when `vector-new` landed.

### 2.5 What the language already supports for a protocol-based design

| Probe | Result |
|---|---|
| An in-place protocol `(initialize (self:&Self a:&AllocHandle):void)`, conformed by `(Vector T)` and a plain struct, plus a macro `(create T a)` that expands to allocate, then `initialize`, then return the pointer | **Works.** `(create (Vector i32) (default-allocator))` and `(create Pt …)` both run. |
| Two protocols with one method name at different arities: `(construct self a)` and `(construct self a v)` in `(ConstructFrom V)` | **Works**, both through a direct call and through a `:where ((ConstructFrom V) T)` generic. |
| The same generic called with a string literal for `v` | `V` binds to `StrView`, not `CStr` (`constraint 'ConstructFrom' parameter mismatch: expected StrView, found CStr`). A literal therefore initializes a `String` through `(InitFrom StrView)`, which is the conformance `String` should have anyway. |
| A protocol method with no `self`, such as `(default ():Self)` | **Refused** at `extend` (`Pt does not implement Default.default`), even though the method exists. |
| A generic whose type variable appears only in the return type, `(defn create (a) T :where ((Construct T)))` | **Refused** (`unknown type: T`). The want channel binds `T` only when the return type is a template such as `(Vector T)`. |
| `make` as a library name | **Taken** when measured. It was the `defunion` arm-construction special form; union construction has since become `(Shape rect …)`, freeing it. |
| **A user function named `init`** | **Breaks the core `for` and `dotimes` macros.** The error is `lib/nucleus/macros.nuc:180: error: macro 'for' calls 'init', which is defined later in this unit`, even when `init` is defined *above* its use. `step`, `test` and `body`, the macro's other parameter names, cause no error. |

So creation protocols need no new compiler feature as long as the type is
written explicitly in the call. A value-returning construction form that infers
`T` needs either the type as an argument or a compiler form.

## 3. The model: placement, storage and initialization are separate choices

Creating an object involves three independent choices. The current names
combine them:

- **Placement.** Where the object's own bytes live: a binding (the frame),
  inside another object, or memory from an allocator.
- **Storage.** Where the buffers the object owns live. This is the allocator the
  object stores and frees through.
- **Initialization.** Turning those bytes into a valid `T`, optionally from a
  value.

Under the proposal, initialization is a protocol (`Init`, §5). Storage is the
allocator argument to `init`. Placement is chosen by which form is used (§6):
`new` places the object through an allocator, `make` places it in a binding. A
new collection writes one `init` method per kind of source value and gets every
placement for free.

## 4. Allocators

### 4.1 The protocol

```lisp
(defprotocol Allocator
  (allocate   (self:&Self size:usize align:usize) ?&ui8)
  (reallocate (self:&Self (p ?&ui8) old:usize new:usize align:usize) ?&ui8)
  (deallocate (self:&Self (p ?&ui8) size:usize align:usize):void)
  (handle     (self:&Self):Alloc))
```

- **Rename the methods.** The new names avoid the libc collision (§2.1) without
  waiting on a compiler fix. They also read better next to `drop`. The
  collision itself is still a bug and is recorded in §9 AL-0b.
- **`align` is honored.** Every built-in allocator must return memory with the
  requested alignment. It is no longer advisory.
- **`handle`** returns the type-erased value a collection stores (§4.3). This
  lets constructors take any concrete allocator (`&Arena`, `&FixedBuffer`, `heap`) and
  convert it themselves. The language has no implicit conversion that would do
  this at the call site.
- **Every allocator also extends `Drop`** (§8).

### 4.2 The three built-in allocators

| Allocator | State | `deallocate` | `drop` |
|---|---|---|---|
| **`Heap`** (libc) | None. One process-wide instance, `heap`. | `free` | No-op |
| **`Arena`** | A chain of blocks, current offset, and a parent allocator for the blocks (default `heap`) | No-op, or a rewind when `p` is the most recent allocation | Frees every block |
| **`FixedBuffer`** | A borrowed byte buffer (pointer and length) and an offset | Pops when `p` is the top allocation; otherwise a no-op | No-op (the buffer's owner releases it) |

The arena also gets `arena-reset`, which rewinds to the first block and keeps
the blocks. The compiler's process-lifetime arena becomes one global `Arena`
value, `g-arena`. The existing `g-arena-alloc` handle and 377 `arena-alloc`
calls then point at it. This fixes the lost-block leak (§2.2) as a side effect.

**`FixedBuffer` has nothing to do with the stack.** It bump-allocates from a
buffer it borrows, and the buffer can live anywhere: the current frame, a global
array (a target with no heap, such as AVR), a block from `heap` reused across
calls, a block from an `Arena` (giving a region that can pop), or memory from C
or `mmap`. `(fixed-buffer p len)` takes any pointer and length.

The frame case needs a macro, because a function cannot `alloca` memory in its
caller's frame. `frame-buffer` reserves the buffer in the scope that expands it:

```lisp
(with (s (frame-buffer 4096))             ; macro: alloca 4096 bytes here, plus a FixedBuffer header
  (let (v (new (Vector i32) s)) …))
```

Whoever owns the buffer frees it, so `FixedBuffer`'s drop is a no-op. When the
buffer is full, `allocate` returns null, as the protocol contract already
allows, and a collection follows its existing OOM path (Q5). The frame-escape
analysis covers a `frame-buffer`'s address the same way it covers any other
frame address; a `FixedBuffer` over a global or heap buffer may outlive the
function that made it.

### 4.3 The stored handle: dynamic dispatch

A collection stores one allocator value and does not know its concrete type.
There are three ways to provide that:

- **(a) Extend the tagged handle (recommended now).** `AllocHandle` is renamed
  `Alloc` and gets the kinds `HEAP`, `ARENA`, `FIXED` and `CUSTOM`. `data`
  points at the allocator instance. The `CUSTOM` kind points at
  `{instance, allocate-fn, reallocate-fn, deallocate-fn}`, a hand-built vtable,
  which §2.1 showed is callable now. `Alloc` itself extends `Allocator`, so a
  collection calls `(allocate (self 'alloc) n align)`. No compiler work is
  needed, and users can still write their own allocators through `CUSTOM`.
- **(b) Use `(dyn Allocator)`.** This is the long-term answer, but it needs two
  things the language does not have yet:
  - multi-method `dyn`, designed in
    [future/dyn-arbitrary-protocols.md](../future/dyn-arbitrary-protocols.md)
    as DP-0…DP-4;
  - a borrowing `dyn`. Today a `(dyn P)` box moves its value to the libc heap
    and drops it along with the box. For an allocator, that would split an
    `Arena`'s state into a copy, and dropping a `Vector` would then drop its
    arena. A collection needs Rust's `&dyn` shape: `data` points at an existing
    instance, there is no box, and there is no drop slot.

  Both pieces fit in 16 bytes, the same size as today's `AllocHandle`. If every
  conversion goes through `handle` (§4.1), replacing (a) with (b) later changes
  one type definition and no call sites.
- **(c) Make the allocator a type parameter, as in `(Vector T A)`.** Stage 11
  rejected this because the parameter spreads into every signature that
  mentions a collection. Nothing has changed that.

## 5. Initialization protocols

```lisp
(defprotocol Init
  (init (self:&Self a:Alloc):void))

(defprotocol (InitFrom V)
  (init (self:&Self a:Alloc v:V):void))

(defprotocol (TryInitFrom V)
  (init (self:&Self a:Alloc v:V):!void))
```

- **One method name, `init`.** §2.5 showed that protocols sharing a method name
  at different arities work. Prerequisite: AL-0a must fix the `for` macro first,
  because today a function named `init` breaks it.
- **`a` is the storage allocator** (§3). A type that owns no buffers ignores
  `a`.
- **Omitting the allocator.** One generic in the library supplies the default:
  `(init x)` becomes `(init x (handle heap))` for any `Init` type. Q6 covers the
  alternative of a dynamically scoped current allocator.
- **The fallible variant.** Some sources are partial, for example `String` from
  bytes that may not be valid UTF-8. A protocol's signature cannot have an
  optional `!`, so a fallible source conforms to `TryInitFrom` instead of
  `InitFrom`. `new` and `make` return `!` exactly when the selected `init` does.
- **Capacity is not a source.** `(Vector T)` from a `usize` would read as "a
  vector containing this number." Capacity stays a `reserve` call after
  initialization. A `:capacity` option on `new`/`make` could come later, but it
  is outside this stage.
- **Conformances shipped in this stage:**
  - `Vector`, `HashMap`, `HashSet`, `String`: `Init`;
  - `Vector`: `(InitFrom (Vector T))` (copy) and the `[...]` literal;
  - `String`: `(InitFrom StrView)`, `(InitFrom &String)`,
    `(TryInitFrom (Vector ui8))`.

## 6. Creating an object in one call

There are two forms, split the way Go splits `new` and `make`, by placement:

```lisp
(new T a args…)   ; → &T  — placed in memory from allocator a; storage also from a
(make T a args…)  ; → T   — returned by value into the binding; storage from a
(make T)          ; storage from heap
```

Both expand to the same steps:

1. Get bytes of `T`'s size and alignment: from `allocate` for `new`, or from a
   frame slot for `make`.
2. Call `(init p (handle a) args…)` when `T` conforms to `Init`, `InitFrom` or
   `TryInitFrom`.
3. If `T` conforms to none of them, fall back. A plain struct is built from
   `args` like a struct literal, `(new Pt a 1 2)`. With no arguments it is
   zero-filled. This keeps one spelling for every type, and replaces today's
   `(new Scope)` with `(new Scope g-arena)`.

```lisp
(with (v (make (Vector i32) heap))  …)                  ; header in the frame, buffer on the heap; drop at exit
(let  (s (new String g-arena "prelude"))  …)            ; header and buffer in the arena; nothing to drop
(with (buf (frame-buffer 1024)
       k  (make String buf "key"))  …)                  ; reverse drop order: k, then buf
```

**Why these are compiler forms.** A library macro can produce steps 1 and 2.
Step 3 needs to ask whether `T` conforms to `Init`, and a macro has no way to
ask that today. [conformance-query.md](conformance-query.md) describes what a
`(conforms? T P)` form would take. With it, `new` could be a library macro. Two other routes are closed by §2.5: a library `make` would collide
with the special form, and a value-returning generic cannot infer `T` from its
return type. So `make` grows from union arms to all types. The cases do not
overlap: for a union `T`, the second operand is an arm name; for anything else,
it is an allocator. `new` becomes a compiler form beside it. The arena macro
`new` in `lib/nucleus/arena.nuc` is retired in AL-4.

**Update, 2026-10-07: `conforms?` is built.** The paragraph above is kept as
written when it was not. A library macro can now do step 3, so `new` can be a
macro in `lib/` rather than a compiler form. A macro also takes `T` as an
operand, so the return-type inference problem does not arise for either form.
The one obstacle left was the name `make`, which belonged to the union special
form. **Resolved the same day:** union construction became keyword-free,
`(Shape rect 3.0 4.0)` and `((Result i64 Err) ok 5)`, the way Rust, Swift, Ada
and Nim write it. `make` is now an ordinary name, free for a library macro.

## 7. Retiring the prefixed constructors

| Today | After |
|---|---|
| `(vector-init v)` | `(init v)` |
| `(vector-init-alloc v a)` | `(init v a)` |
| `(vector-new)` / `(vector-new-alloc a)` | `(make (Vector T))` / `(make (Vector T) a)` |
| `(vector-new-in a)` | `(new (Vector T) a)` |
| `(vector-init-capacity v n)` / `(vector-new-capacity n)` | `init` / `make`, then `(reserve v n)` |
| `(string-new)` / `(string-with-capacity n)` | `(make String)`, then `reserve` |
| `(string-from-view sv)` | `(make String heap sv)` (fallible through `TryInitFrom`, as today's `!String` is) |
| `hashmap-*` / `hashset-*` | Same as the `vector-*` rows |
| `default-allocator` / `libc-allocator` / `arena-allocator` | `heap` / `heap` / an `Arena` value |
| `alloc-handle-alloc` etc. | `allocate` / `reallocate` / `deallocate` on `Alloc` |

Per the pre-release rule, the old names are deleted rather than deprecated. They
stay only as boot shims for as long as `boot/nucleusc.ll` still calls them.

## 8. Dropping an allocator

### 8.1 What `drop` releases

`drop` releases **the allocator's own resources and nothing else**. What that
means for live objects depends on the allocator:

| Allocator | After `drop`, objects allocated from it are… |
|---|---|
| `Heap` | **Still valid.** The heap is the process. `Heap` has no state to lose, and `heap` is a global that is never dropped. A `Heap` going out of scope is not an event. |
| `Arena` | **Dangling.** Releasing the blocks all at once is the reason to use an arena. |
| `FixedBuffer` | **Dangling** once the buffer's owner releases it (for `frame-buffer`, when the frame ends), not because of the drop. The drop is a no-op. |

So the answer to "could the objects continue to exist" is: yes for the heap, and
no for allocators that own memory. Making it yes for an arena would mean
reference-counting its blocks, which is a garbage collector by another name. It
would also give up the reason to choose an arena.

### 8.2 The three ways it goes wrong

1. **A dangling object.** The object outlives its arena or fixed buffer.
2. **A dangling handle.** An object outlives its allocator and later calls
   `drop`, which calls `deallocate` through `Alloc.data`, which points at the
   dead allocator. This is use-after-free even when the bytes were heap bytes.
   For example, a tracking allocator wrapped around the heap would be read after
   it is gone. The stateless `heap` avoids this only because its `data` is
   static.
3. **A leaked foreign resource.** An object placed in an arena owns something
   the arena does not hold, such as a `Vector` whose buffer was allocated from
   `heap`, or an open file. Freeing the arena's blocks wholesale never runs that
   object's `drop`, so the outside resource leaks.

### 8.3 The options

- **A. Contract.** An allocator must outlive every object allocated from it and
  every object that stores its handle. Breaking this is a bug. This is the rule
  in Zig, C++ `pmr` and Rust's `bumpalo`. It costs nothing at run time.
- **B. Automatic finalization.** `new` into an arena records `T`'s `drop` when
  `T` conforms to `Drop`. That is a static decision, so plain data costs nothing
  extra. `drop` on the arena then runs the recorded drops in reverse order
  before freeing the blocks (like Rust's `typed_arena`). This fixes failure
  mode 3 but has costs:
  - it adds a per-object list to the arena;
  - it turns an O(1) release into O(n);
  - it creates a double drop. `with` takes ownership of any binding whose type
    conforms to `Drop`, so `(with (v (new (Vector i32) g-arena)) …)` would drop
    `v` at scope exit and again when the arena is dropped. The library's drops
    tolerate this because they null their fields. User drops are not required
    to.
- **C. Checked contract.** An allocator that expects every allocation to be
  freed counts outstanding allocations in a checked build. When it is dropped
  with a non-zero count, it reports the leak. `FixedBuffer` gets this almost for free.
  A `Tracking` wrapper could add it to any parent allocator, like Zig's
  `GeneralPurposeAllocator`. It does not apply to `Arena`, because abandoning
  objects there is the normal case.
- **D. Static checking.** `with` already drops bindings in reverse order. So
  `(with (a (make Arena)) (v (make (Vector i32) a)) …)` drops `v` before `a`
  with no extra work. Catching the case where `v` escapes would require the
  escape analysis to treat "allocated from `a`" as a borrow of `a`. That is a
  lifetime system, and it is out of scope here.

### 8.4 Recommendation: a contract, checked where checking is cheap

- **A is the rule.**
- **D comes free** from `with`'s drop order. The docs should show allocators
  bound first in the same `with` as the objects that use them.
- **C ships for `FixedBuffer`** in AL-1. A `Tracking` allocator comes later as AL-6.
- **B is not the default.** If AL-6 adds it, it should be a separate type,
  `FinalizingArena`, whose `new` returns a reference that `with` does not take
  ownership of. That needs a non-owning return marker, which does not exist
  today. Mixing finalization into the default `Arena` would charge every arena
  user for the cost and the double-drop risk, to fix a leak that only appears
  when owning objects are placed in an arena.

## 9. Phases

- **AL-0a. Fix the `init`/`for` collision (§2.5).** The `for` macro reports a
  call to `init` where its body only unquotes a parameter named `init`, and it
  reports that `init` is defined later when it is defined earlier. Find the
  cause in macro-body compilation, not by renaming the parameter. Add a
  regression test that defines a user `init` and uses `for` and `dotimes`.
- **AL-0b. Make a user method named after a libc function overload it instead of
  replacing it (§2.1).** The library should not need this once the allocator
  methods are renamed, but it is still a bug. User code hits it with `free`,
  `remove` and `realloc`. `docs/collections.md` already works around
  `set-remove` for this reason.
- **AL-1. Allocators.** Rename the protocol methods and add `handle`. Honor
  alignment. Add `Heap` (with `heap`), `Arena` (with `arena-reset`, a block
  chain, and a parent allocator), `FixedBuffer` (with `fixed-buffer`, the `frame-buffer` macro,
  and a checked outstanding count), and `Alloc` with the `HEAP`/`ARENA`/`FIXED`/
  `CUSTOM` kinds. Every allocator extends `Allocator` and `Drop`. The compiler's
  arena becomes the global `Arena` `g-arena`. Existing call sites change only by
  the rename.
- **AL-2. `Init`, `InitFrom` and `TryInitFrom`,** plus conformances for the four
  collections and the default-allocator generic.
- **AL-3. `new` and `make` (§6),** as library macros over `conforms?` (Q2).
  Union construction no longer uses the name. Tests cover a plain struct, each kind of `init`, a `!` from
  `TryInitFrom`, and `with` drop order with an allocator bound in the same form.
- **AL-4. Sweep the codebase.** Remove the prefixed constructors from `lib/`,
  `src/`, `examples/` and `tests/` (§7), and the arena `new` macro. Boot shims
  stay until the boot is refreshed. Confirm that the compiler's globals such as
  `g-structs` still initialize the same way. Update the docs: `allocators.md`,
  `collections.md` (including the stale §2.4 line) and `strings.md`.
- **AL-5 (gated on DP and a borrowing `dyn`).** Change `Alloc` to
  `(dyn &Allocator)` and retire the `CUSTOM` kind.
- **AL-6 (optional).** The `Tracking` allocator. Q1 ruled out
  `FinalizingArena`.

## 10. Questions for a ruling

**Ruled 2026-10-07:**

| | Ruling |
|---|---|
| Q1 | A contract plus cheap checks (§8.4). No automatic finalization. |
| Q2 | `new` (placed, `&T`) and `make` (by value), as library macros over `conforms?`. |
| Q3 | `allocate`/`reallocate`/`deallocate`. |
| Q4 | The extended tagged `Alloc` now; `(dyn &Allocator)` later (AL-5). |
| Q5 | A full `FixedBuffer` returns null. Revisit after some use (deferred). |
| Q6 | The fixed global `heap` for now. Revisit after some use (deferred). |
| Name | The brief's "stack" allocator is `FixedBuffer`, with `fixed-buffer` and the `frame-buffer` macro (§4.2). |

The questions as they were put:

- **Q1. Dropping an allocator with live objects.** Contract plus cheap checks,
  as recommended in §8.4, or automatic finalization (B)?
- **Q2. Names.** `new` (placed through an allocator, returns `&T`) and `make`
  (by value, generalized from unions), as recommended? Or one form with a
  placement keyword? And, now that `conforms?` is built and `make` is free:
  library macros (recommended, since `conforms?` makes them possible and keeps
  the compiler smaller) or compiler forms?
- **Q3. Method names.** `allocate`/`reallocate`/`deallocate`, as recommended, or
  fix AL-0b first and keep `alloc`/`realloc`/`free`?
- **Q4. The handle.** The extended tagged `Alloc` now and `dyn` later, as
  recommended, or no allocator work until DP and a borrowing `dyn` exist?
- **Q5. A full `Stack`.** Return null, as recommended, or fall back to a parent
  allocator?
- **Q6. The default allocator.** The fixed global `heap`, as recommended? The
  alternative is an implicit, dynamically scoped current allocator, like Odin's
  `context.allocator`, which a `(with-allocator a …)` form would rebind. That
  makes "everything in this call tree uses the arena" a one-line change. It
  costs a hidden parameter or a thread-local, and makes it unclear at the call
  site which allocator a call uses.
