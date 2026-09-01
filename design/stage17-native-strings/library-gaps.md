# Stage 17 — string-library gap register

The dogfooding deliverable. Every entry is a weakness the compiler conversion
exposes or would expose, with the evidence that establishes it and the fix. The
standing rule from [overview.md](overview.md) applies to all of them: **fix the
library, not the call site.**

Status column: **blocker** = a Track B/C phase cannot proceed without it;
**found** = real, fix it when the conversion reaches it; **verify** = suspected,
measurement pending; **accepted** = known and deliberately not fixed in this
stage.

Seeded 2026-08-31 from a survey of `lib/strview.nuc`, `lib/string.nuc`,
`lib/string-split.nuc`, `lib/vector.nuc`, `lib/keyword.nuc` and `docs/strings.md`
against the `src/` inventory in overview.md §1.1. **This register grows during
the stage** — appending to it as the conversion hurts is the point, not a sign
the plan was wrong.

---

## A. Missing layers (the four pillars)

### 1. No value → text conversion — **blocker**
There is no way to render an `i32`, a `usize`, a `Char` or a pointer as text
without `snprintf`. Every one of the compiler's ~650 `fmt-*` calls and 156 `%d`
conversions depends on this not existing.
**Fix:** `ToStr` protocol + `str`/`str-alloc` macros (`lib/fmt.nuc`, phase B1).

### 2. No sink abstraction — **blocker**
The only way to write text is a `FILE*`. `String` cannot be written *into*
generically; there is no `Writer`.
**Fix:** `Writer` protocol, `String`/`CFile`/`File`/`BufWriter`/`StdOut`/`StdErr`
conformers (B1–B3). Note the compiler already *has* this pattern untyped — `g-out`
is swapped between stdout, files and `open_memstream` buffers.

### 3. No IO — **blocker**
No `print`, no file reading or writing, no line input. `lib/` has never had an IO
library; every program uses `stdio.h`.
**Fix:** `lib/io.nuc` (B2), `lib/file.nuc` (B3).

### 4. No interned-identity string type — **blocker**
`Keyword` is the only interned name type and it is a **256-entry fixed array with
a linear scan and a `strcmp` per probe** (`lib/keyword.nuc:74`, `KEYWORD-MAX`
256, overflow aborts). Unusable for a compiler symbol table. This absence is the
sole justification for the standing "the interned substrate stays raw `ptr`"
ruling (overview.md §1.3 item 3).
**Fix:** `Symbol` + an open-addressed intern table (`lib/intern.nuc`, B4);
rebase `Keyword` onto it, retiring the 256 cap and the linear scan.

---

## B. Hot-path defects — the compiler will hit these immediately

### 5. `string-push-str` is O(n) decode + one `conj` **per byte** — **fixed 2026-09-01 (B0)**
`lib/string.nuc:113` fully UTF-8-decodes the incoming view, then calls
`string-push-bytes-raw` (`:88`), which is:

```lisp
(dotimes (i:usize n) (conj v (aref p (as i64 i))))
```

— a bounds/capacity check and a function call for every byte appended. IR
emission is millions of bytes of small appends; this is a throughput cliff, and
it is the single most important finding in this register.

The re-validation is also **redundant by the type's own contract**: a `StrView`
is documented as valid UTF-8, so validating one on append re-proves an invariant
the type already asserts.

**Fixed**, but not as written above. The append is now `reserve` once + one
`memcpy` (`string-push-bytes-raw` delegates to item 6's `vector-extend-raw`).

The re-validation **stayed**, because the premise for dropping it was wrong: a
`StrView` is *not* documented as valid UTF-8 — it is "a length-prefixed byte
slice", and `string-from-view` validates for exactly that reason. `String` is
the UTF-8-guaranteed type, so `string-push-str` is where the guarantee is
enforced. What was added instead is `string-push-str-unchecked`, mirroring the
`string-from-cstr-unchecked` already in this library: the caller asserts
validity, and that is the appending path for bytes the producer already knows
are valid (all of the compiler's IR output). The checked entry point kept its
cost and lost none of its contract.

### 6. `Vector` has no bulk append — **fixed 2026-09-01 (B0)**
`lib/vector.nuc` offers `conj`/`append`/`insert` element-at-a-time and
`reserve`, with no `extend`/`append-slice`/bulk-copy path. Item 5's fix needs one,
and so does anything that builds a buffer from a slice.
**Fixed:** `vector-extend-raw` (from a raw buffer) and `vector-extend` (from
another vector) — reserve once, `memcpy` once. Not spelled `extend`: that is the
protocol-conformance special form, and a symbol may name only one kind of thing.
No trivially-copyable fast path *branch*: the copy is bitwise, which is exactly
what `conj`'s element store already is, so a second path would have no different
behaviour to select. `vector-extend-raw`'s source must not alias the vector's own
buffer — the reserve may reallocate it.

### 7. `strview-from-cstr` heap-allocates a wrapper — **fixed 2026-08-31 (A2)**
It returned `(ptr StrView)` — a `malloc` per conversion, which the caller had to
free. Crossing an FFI seam is the most common operation in a converted compiler,
and it must not allocate. The wrapper was a workaround for a compiler limitation
that no longer exists (overview.md §1.4).
**Fixed:** returns `StrView` by value, allocating nothing. No heap variant kept.

### 8. No `StrView` value constructor — **fixed 2026-09-01 (B0)**
The only ways to build a `StrView` are `strview-from-cstr` (item 7) and an
`alloca` plus two `set!`s, spelled out in `docs/strings.md` §3 as the documented
idiom. Conversion code constructs views constantly.
**Fixed:** `(strview data len)` returns by value. The bare name does not collide
with the `strview` *module* name, so no `strview-from-parts` was needed;
`strview-from-cstr` is now one line over it.

### 9. No `String` → `CStr` bridge — **fixed 2026-09-01 (B0)**
`String` wraps a `Vector ui8` with **no NUL-termination guarantee**, and there is
no function to produce a `char*` from one. `strview-to-cstr` exists but is only
sound on buffers that happen to be NUL-terminated. Every retained FFI seam
(`popen`, `fopen`-replacement paths, the LLVM C API, the linker command line)
needs to hand a built string to C.
**Fixed** exactly as written: `string-as-cstr` reserves `len+1`, writes the NUL
*past* `len` and does not count it, so the String is unchanged for every other
operation and a second call is free. The returned pointer is invalidated by any
subsequent append.

### 10. No byte or char search — **fixed 2026-09-01 (B0)**
`strview-byte-find` takes a `StrView` needle only. The compiler uses `strchr` 37
times and `strstr` 14 times; a single-byte search should not require
materializing a one-byte view.
**Fixed:** `strview-find-byte`, `strview-rfind-byte`, `strview-rfind`,
`strview-find-char`, `strview-rfind-char`, all `(Maybe usize)`. UTF-8 is
self-synchronizing, so the codepoint search is a byte search for the encoding
and needs no boundary check.

One rename came with them: the existing substring search `strview-byte-find`
became **`strview-find`**. Leaving it would have put `strview-byte-find`
(substring) next to `strview-find-byte` (one byte) — two names one character
apart meaning different things, which is a defect to create, not to ship.

---

## C. Stale workarounds — fix the API, do not preserve it

The compiler limitations these three were written around were re-measured on
2026-08-31 and **two of the three are gone** (overview.md §1.4). Under this
stage's standing rule they are corrected, not carried.

### 11. `strview-sub-bytes` returns `!ptr:StrView` — **fixed 2026-08-31 (A2)**
Documented as "v1 limitation … the compiler cannot return a struct payload
through `!T`/`Result`". It can, verified. The heap wrapper was pure cost and a
free-obligation on every caller.
**Fixed:** `!StrView` by value, in `strview-sub-bytes`, the `ByteStr.sub-bytes`
protocol method, and both conformances (`StrView`, `String`).

### 12. `SplitIter`/`LineIter` conform to `(Iterator ptr)` — **fixed 2026-08-31 (A3)**
They yielded a `(ref StrView)` niche-encoded as a bare `ptr` into the iterator's
`cur` slot, decoded by a dedicated `doseq-split` macro, because `(Maybe StrView)`
was said not to stamp in the macro-expansion JIT module.

**The premise was stale.** `(Maybe StrView)` stamps in both a macro body and an
`(Iterator StrView)` conformance (verified 2026-08-31). Both iterators now
`(extend … (Iterator StrView))` and yield `(some seg)` by value; the `cur`
scratch fields, the niche encoding and `doseq-split` are gone, and `doseq-iter`
drives them. No library code was written to preserve the workaround.

Cost of the promotion, and the reason #24 matters: `seg` is now a value, so
every consumer taking `(ref StrView)` needs `(addr-of seg)`. That call-site
change is what exposed #25.

### 13. `!i32` sentinel returns — **fixed 2026-09-01 (B0)**
`string-push-str` and `string-truncate` return `!i32` where `!void` is meant,
"because the compiler does not yet support `!void`". Re-measured: it did not
(`Result.void.Err: arm 'ok' takes a different number of fields`).

**`!void` now works** (phase A1, done). Two changes:

1. **`defunion-register` drops a `void` field** (`src/union-registry.nuc`): a
   `void` field carries no value, so it contributes none, and `(Result void Err)`
   stamps an `ok` arm that is payload-less exactly like `Maybe`'s `none`. That is
   a general rule about `defunion`, not a `Result` special case, and it is the
   whole of the representation change — the layout engine already classifies
   `{payload-less, Err}` as the ordinary tagged struct.
2. **`try` moved from `lib/error.nuc` into the compiler** (`emit-try`,
   `src/union-emit.nuc`, with its `node-type` lockstep arm in
   `src/generics.nuc`). It was a macro expanding to a fixed `((ok v) v)` arm, and
   the ok arm's binder count depends on the operand's *type* — which a macro
   cannot see. It now synthesizes the same match with the arm shape chosen from
   `result-ok-type`.

**Done (B0):** `string-push-str` and `string-truncate` return `!void`, and every
new `lib/fmt.nuc` / `lib/io.nuc` / `lib/file.nuc` signature is to be written that
way from the start.

---

## D. Missing operations the conversion needs

### 14. No `String` concatenation or editing — **found**
No append-`String`-to-`String`, no `insert`, no `replace`, no `+`. `String` can
only be grown one `Char` or one `StrView` at a time.
**Fix:** `string-append` (String and StrView overloads), `string-insert`,
`string-replace`. `str` covers most concatenation needs, so keep this set small
and demand-driven.

### 15. No `split-once` / `splitn` / `rsplit` — **found**
`strview-split` yields all segments or nothing. Path and header handling (which
`src/cheader.nuc` does constantly) wants "split on the first `/`" without
building an iterator.
**Fix:** `split-once` returning a pair of views; `rsplit-once`. `splitn` only if
a caller appears.

### 16. No number-formatting adverbs — **found**
The compiler emits hex (`%04x`, `%02X`) and needs zero-padding. native-io.md §5
sketches adverb wrapper values; the compiler needs at least `hex` and
`pad-left`.
**Fix:** `(hex n)` / `(hex-pad n w)` / `(pad-left v w)` as `ToStr`-conforming
wrapper structs. Not a format DSL — one struct per adverb.

### 17. No string-level case operations — **found**
Case conversion exists on `Char` only (`char-ascii-upper`/`-lower`); there is no
`to-upper`/`to-lower` for a view or string and no case-insensitive compare.
**Fix:** `strview-eq-ignore-case`, `string-to-ascii-upper`/`-lower`. ASCII-only,
matching the `Char` layer's stated scope.

---

## E. Consistency and ergonomics

### 18. Receiver conventions are inconsistent — **found**
`Eq`/`Ord` on `StrView` take it **by value**; `Hash` takes `(ref StrView)`; the
`ByteStr`/`Str` protocol methods take `(ref Self)`. Generic code over these
protocols has to know which is which.
**Fix:** settle on `(ref Self)` for all non-operator methods and document the
operator exception (operators take values so literals dispatch). Decide once,
in B0, before `Symbol` adds a fourth conformer to each protocol.

### 19. By-value `StrView` field access needs `(addr-of sv)` first — **stale, closed 2026-08-31**
stage14/native-strings.md's NS-5 notes record this as a gotcha: a `sv:StrView`
parameter is a `TY-STRUCT`, so `(sv 'data)` was said to fail and every by-value
user had to bind `(let (p:ptr:StrView (addr-of sv)) …)` first.

**Re-measured: it works.** A by-value `StrView` *parameter* and a by-value
`StrView` *local* both accept head-position `(sv 'len)` / `(sv 'data)` directly
(verified against `bin/nucleusc`). Stage 16's dot-forms step 3 replaced the old
literal-symbol routing gate with a **receiver-shaped** one
(`is-member-access-receiver`), which closed this incidentally. Kept in the
register rather than deleted, because a stale gotcha in a design doc costs the
same as a real one — the NS-5 note and `docs/strings.md`'s `((addr-of seg) 'len)`
spelling should both be corrected (the docs were, 2026-08-31).

### 20. `strview-len` and `strview-byte-len` are the same function — **fixed 2026-09-01 (B0)**
Two names, one body (`lib/strview.nuc:60` and `:200`). Harmless today, confusing
in a stage that adds a fourth string type.
**Fixed:** `strview-len` is gone; `strview-byte-len` (the protocol spelling) is
the one name. Three call sites in `examples/` and two in `docs/stdlib.md`.

### 21. `docs/strings.md` examples use the retired bare selector — **found**
Every worked example writes `(sv len)` / `(sv data)`. Stage 16's dot-forms step 3
flipped the selector rule: a bare symbol in selector position is now an ordinary
variable, and these examples fail with *"'len' is undefined here … write
(sv 'len)"* — reproduced against `bin/nucleusc` on 2026-08-31. The library's
documentation does not currently compile.
**Fix:** sweep `docs/strings.md` for bare selectors (and check the other docs
while there).

---

## F. Accepted — not fixed in this stage

### 22. Borrow lifetimes are unchecked — **accepted**
`ByteIter`, `CharIter`, `SplitIter`, `LineIter` and sub-views hold raw pointers
into a source buffer with no compile-time lifetime enforcement. Real, and a
language-design question far larger than this stage. Recorded so the conversion
does not mistake it for something Stage 17 broke.

### 23. A `StrView` at a C variadic call site contributes only `data` — **accepted,
and largely obsoleted**
Passing a `StrView` to `printf`'s `%s` passes the `char*` only, never the
`{data,len}` pair — deliberate, since a carried length would occupy a vararg slot
and shift every later conversion. The conversion removes essentially all variadic
call sites from `src/`, so this stops mattering there; the rule stays documented
for FFI users.


---

## G. Raised by the A2 migration (2026-08-31)

Converting the six `strview-from-cstr` examples produced one finding worth
recording, because the conversion is a preview of the whole stage:

### 24. Every by-value producer meets a by-reference consumer — **fixed 2026-09-01 (lvalue-only implicit address-of)**
`strview-from-cstr`, `strview-sub-bytes` and `strview-trim*` return `StrView`
**by value**, while `strview-len`, `strview-eq`, `strview-hash`, `starts-with?`,
`str-empty?` and every `ByteStr`/`Str` method take `(ref StrView)`. So the
natural code is

```lisp
(let (av:StrView (strview-from-cstr "hello")
      a:ptr:StrView (addr-of av))
  (strview-len a))
```

— a two-line binding for one value, repeated at every site. This is item 18's
receiver inconsistency showing up as concrete friction rather than as a style
observation, and the compiler conversion will hit it thousands of times.

Options, to settle in B0 before `fmt`/`io`/`file` add a third and fourth
conformer to each protocol: (a) by-value overloads for the read-only helpers
(`StrView` is two words — passing it by value is not obviously worse than
passing a pointer, and `Eq`/`Ord` already do); (b) accept the `addr-of` and make
it idiomatic; (c) let head-position member access and plain calls take a struct
value's address implicitly where a `(ref T)` is wanted — the same implicit
address-of that item 19 turned out to already have for *member access*, extended
to argument position. (c) is the one that removes the friction rather than
relocating it, and it is a language change, so it needs deciding early.

**Update (A3):** the `let`-slot half of (c) already exists — TC-3 target-typed
materialization copies a struct *value* into a stack temporary and stores its
address, so `(let (p:ptr:StrView (strview-from-cstr "x")) …)` is correct today
(verified in the IR: `%tc3.mat.N = alloca %StrView` … `store ptr %tc3.mat.N`).
So (c) is not a new mechanism, only its extension to argument position. Note
what that asymmetry cost: the reason it *looked* like argument position already
worked is #25.

**Update (B0):** worked through in
[borrow-conventions.md](borrow-conventions.md). Conclusions that change this
entry:

- **(a) and (b) are not achievable**, and the entry above was wrong to list them
  as symmetric alternatives to (c). The producer side must be by value (the
  alternatives are the `malloc` #7 deleted or the `alloca` dance #8 deleted) and
  the consumer side must be by reference (`ByteStr`/`Str` bind `Self` to *both*
  `StrView` and `String`, and `String` has `Drop`, so a by-value receiver is a
  move on every read-only query). The seam is structural, not a style lapse.
- **(c) unrestricted is unsafe** while `(ref T)` conflates read and write:
  `(string-push-str (string-new) sv)` would append into a temporary and drop it.
  That is #25's class of defect.
- **The safe subset is lvalue-only** implicit address-of, which covers every
  instance of this entry that actually occurs and needs no type-system change.
- Splitting `(ref T)` into read-only and mutable borrows makes full (c) safe and
  is independently justified — mostly by signatures-as-documentation across
  `src/`, not by these `addr-of`s. **Deferred**: §3.4 removes the friction that
  raised it, so it no longer blocks Stage 17 and wants its own stage.

**Fixed (2026-09-01)** by the lvalue-only subset. `Val.lvalue-sym` records the
binding a value was loaded from; `coerce-call-argument` passes that binding's
address; `params-accept-args` is the tier-0 dispatch half, without which every
protocol method (`byte-len`, `sub-bytes`, the whole `ByteStr`/`Str` surface —
most of this entry's real friction) was rejected before coercion could act. The
45 two-line `X__v` / `X` bindings A2's migration created across five examples
collapsed back to one line each, and the four `(print-sv (addr-of seg))` sites
A3 forced are `(print-sv seg)` again.

---

## H. Raised by the A3 migration (2026-08-31)

### 25. A StrView decayed to `.data` at any pointer target — **fixed 2026-08-31 (A3)**
The NS-2/NS-3 borrow rule (`src/abi.nuc`, both the literal and the materialized
arm) fired on `(or (= dk TY-PTR) (= dk TY-CSTR))`. Its intent is "a StrView
borrows to a `char*` for free by taking `data`" — but `(ref StrView)` *is*
`TY-PTR`, so passing a `StrView` **value** to a `(ref StrView)` parameter
compiled clean and passed the data pointer where a `%StrView*` was expected.
The callee then read `len` from the string's own bytes:

```lisp
(defn show ((sv (ref StrView))):void (printf "len=%llu\n" (as ui64 (sv 'len))))
(defn main ():i32 (let (v:StrView (strview-from-cstr "hello")) (show v)) 0)
; before: compiles, rc=0, prints len=1688849864211203
```

A structurally identical `(defstruct P x:i64 y:i64)` was correctly *rejected* —
`safe-coerce-val` returned null and the argument path reported the mismatch. So
this was not a general value→ref hole; it was the string lattice punching one,
and only for the type the whole stage is about to spread through the compiler.
It reached a string literal too: `(show "hello")` had the same shape.

**Fix:** `strview-borrow-target` (`src/type-utils.nuc`) — the borrow now fires
only at a *byte* pointer: `CStr`, a bare `ptr`/`raw`/`?ptr` (no `elem`), or a
pointer to an 8-bit integer, which is `data`'s own type. A typed `ptr:S` target
falls through to the ordinary coercion-failure diagnostic. Both `abi.nuc` arms
call it. Bootstrap stayed byte-identical, so nothing in `src/` relied on the
over-broad rule.

Deliberately *not* fixed by making argument position materialize (#24 option
(c)). An error is the honest answer while that decision is open, it matches how
every non-string struct already behaves, and `(addr-of x)` is a one-token
repair. Revisit under #24 in B0.

### 26. `defstruct` silently accepts a duplicate field name — **fixed 2026-09-01 (B0)**
`(defstruct LineIter buf:(ptr ui8) rem:usize done:bool done:bool)` compiled, and
`--emit-cheader` duly emitted `bool done; bool done;` twice — a header no C
compiler will accept. Caught only because `w9-cheader-committed-header-usable`
compiles a committed header (it was pointed at `SplitIter.cur`, which A3
removed; it now reads `lib/string.h`'s by-value return and by-value parameters,
which test the same completeness property).

Duplicate fields are never intentional; the second one is unreachable by name
and silently inflates the layout. **Fixed** in `defstruct-fill-layout`
(`src/nucleusc.nuc`) rather than `register-struct`: that is where the field names
are interned, so the check is a pointer scan over the names already stored, and
it runs only in the strict pass (the layout prescan abandons rather than dies).
Fixture: `tests/fixtures/s17-dup-struct-field.nuc`.

### 27. A join of two string literals collapses to `CStr` — **found**
`(let (sv:StrView (if c "one" "two")) …)` fails with *"init type mismatch for
'sv': value is CStr, slot is StrView"*. Each arm is an unmaterialized StrView
chameleon; the branch join picks their common type and lands on `CStr` rather
than `StrView`, so a conditional literal cannot fill a `StrView` slot that
either literal alone fills fine.

**Fix:** the join should keep `StrView` when both arms are string literals — the
chameleon already adapts to a `CStr`/`ptr` consumer downstream, so nothing is
lost by joining at the wider type. Belongs with the type-join work
`macro-conditional-casts.md` MC-2 already schedules (join absorption); do it
there rather than adding a second join special case.