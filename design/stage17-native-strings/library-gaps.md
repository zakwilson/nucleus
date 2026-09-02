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
**Fixed 2026-09-01 (B4).** `Keyword` is now one `Symbol` and nothing else — one
word instead of three, no `id` counter, no cap. `=` on both is `icmp eq ptr`,
verified in the emitted IR.

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

### 27. A join of two string literals collapses to `CStr` — **fixed (C6)**
`(let (sv:StrView (if c "one" "two")) …)` failed with *"init type mismatch for
'sv': value is CStr, slot is StrView"*. Each arm is an unmaterialized StrView
chameleon; `collapse-strlit-cstr` retyped every literal branch to `CStr`
unconditionally so the phi would stay a plain pointer, and a conditional literal
therefore could not fill a `StrView` slot that either literal alone fills fine.

The severity was worse than the diagnostic suggested. In a `StrView`-**returning**
function the same collapse compiled silently and miscompiled: the phi carried a
bare data pointer, and the aggregate-return path then spilled it through an
`alloca ptr` and read two eightbytes back out. Under opaque pointers that is not
a verifier error — the length came from whatever eight bytes followed on the
stack. `(defn ptr-int-ir ():StrView (if (= b 2) "i16" (if (= b 4) "i32" "i64")))`
produced a view with a garbage length, which reached `str-into` as a reserve
request and aborted the compiler with `vector: out of memory` on every input.

**Fixed** by `join-strlit-branch` (src/abi.nuc), which takes the same decision
target-typed: collapse when nothing downstream wants a view, materialize
`{ptr,len}` in the branch's own block when the join is known to feed a `StrView`
slot. The armed want (`g-want-type`, which `return` and the implicit tail already
set from the return type) is the signal; `emit-cond`, the defunion match arms and
the niche match arms all route through it. Materialization has to happen in the
branch, not at the join's consumer, because that is the only block a phi operand
may be defined in.

Two backstops landed with it, because the miscompile needed both the collapse and
a silent mis-size to become garbage: `emit-struct-ret` now materializes a
chameleon itself (so neither return path can reach the aggregate ABI with one),
and it refuses outright when the value it is handed is not the declared return
type. Regression test: `tests/fixtures/s17-strview-literal-join.nuc`.

This did **not** need the `macro-conditional-casts.md` MC-2 join absorption it was
originally filed against: the type join is not where the information is. A join
sees only the arms; whether a view is wanted is a property of the destination.
### 28. Nucleus cannot see a C preprocessor macro, so `open(2)`'s flags are hardcoded — **deferred to [future/platform-constants.md](../future/platform-constants.md)**
`(import-use "fcntl.h")` brings in C *declarations*, deliberately not C macros
(design/overview.md), so `O_RDONLY`/`O_CREAT`/`O_TRUNC`/`O_APPEND` do not
resolve. `lib/file.nuc` spells them out as `defconst`s — the **Linux/glibc**
values. Darwin's differ (`O_CREAT` is 0x200 there, `O_TRUNC` 0x400, `O_APPEND`
0x8), so `lib/file.nuc` is Linux-only as written. `examples/cheader-posix.nuc`
already had the same hardcoded block for the same reason.

Not fixable in the library: the value is a property of the target platform, and
Nucleus has no platform conditional and no per-target constant table.

**A Linux-only file library is not an acceptable end state**, so this is
deferred with a named fix rather than merely recorded: teach the C header import
to admit object-like `#define`s whose replacement list is an integer constant
expression. Both halves already exist — `cheader-run-cpp` already shells out to
`clang -E` with the emission target's `--target=`/`--sysroot=` flags, so `-dM`
yields the *target's* values; and `c-cexpr-*` (built for array extents) already
folds C constant expressions and already fails closed on anything it cannot
fold, which is exactly the admission test. Full design, including the volume and
name-mangling decisions, in
[future/platform-constants.md](../future/platform-constants.md).

Out of scope for Stage 17: it is a change to the C header importer, not to the
string stack, and the compiler this stage converts builds on Linux. Until it
lands, `lib/file.nuc` states the limitation in its header, in `docs/io.md`, and
here. The same wall has already been hit by `EINTR` (`lib/io.nuc`, which
therefore does not retry) and `CLOCKS_PER_SEC` (the B4 benchmark), so this is a
recurring tax, not one library's problem.

### 29. `node-type` did not mirror the new tier-0 dispatch pass — **fixed 2026-09-01 (B3)**
`(try (write-str f sv))` failed with *"match: arm 'ok' binder count does not
match its field count"* whenever `f` was a struct **value** binding rather than
an already-`(ref T)` parameter. `emit-try` sizes its `ok` arm from
`(node-type operand)`, and `node-type-call`'s tier 0 was still
`generic-find-method-exact` — `params-type-eq` only — so the lvalue implicit
address-of that `generic-resolve` gained in
[borrow-conventions.md](borrow-conventions.md) §3.4 was invisible to it. The
call typed as unknown, `try-ok-nfields` fell back to its 1-field default, and the
generated `match` was one binder wide against `!void`'s payload-less arm.

**Fixed** with `generic-find-method-accepting` (`src/generics.nuc`), the
call-side companion to `generic-find-method-exact`, run as node-type-call's
tier-0 second pass exactly as `generic-resolve` runs `params-accept-args`. Kept
separate from `generic-find-method-exact` because that one also answers the
*definition*-side question, where `(name, param-types)` must stay an exact key.

This is the `node-type`↔`emit-node` lockstep (context/conventions.md) charging
for a change made on one side only. Bootstrap stayed byte-identical: nothing in
`src/` yet calls a method with a struct-value receiver.

### 30. `strview-hash` folded through a closure, one indirect call per byte — **fixed 2026-09-01 (B4)**
Found by B4's benchmark, which is why the benchmark was in the plan. `Symbol`
interning ran **8x slower** than the compiler's own `intern-symbol` over the
same corpus. The cost was not the table: `strview-hash` was

```lisp
(reduce (vfn (h:i64 b:ui8):i64 (fnv1a-byte h (as i64 b))) SEED (addr-of it))
```

— a `reduce` over a `ByteIter`, so every byte cost an indirect call through the
closure and a `(Maybe ui8)` construction and match. Hashing is on the hot path of
every interned name, every `HashMap` probe and every `StrView` key compare, so
the fold spelling was being paid across the whole library.

**Fixed** with a direct byte loop in `lib/strview.nuc` — same FNV-1a, same
results, no iterator. 8x → 1.4x at -O0, and at -O3 (how the compiler is actually
built) `symbol-intern` is ~1.5x **faster** than `intern-symbol`.

The general finding, worth keeping: a fold over an `Iterator` is a fine default
and the wrong tool inside a primitive that everything else calls. Check the
others (`strview-eq`, the `ByteStr` defaults) before the C-track conversion puts
them under compiler-scale load.

### 31. No unchecked truncate for a scratch buffer — **fixed 2026-09-01 (C2)**
`emit`'s buffer is process-wide and rewinds on every use, to a mark the caller
took from `byte-len` before appending. `string-truncate` is the wrong tool for
that: it validates that the offset is not mid-codepoint and returns `!void`,
and the caller can act on neither — the mark is a boundary by construction, and
the rewind happens in a `:void` function on the hottest path in the compiler.

**Fixed** with `string-truncate-unchecked`, which is what `string-clear` already
was for the mark-zero case. It only ever shrinks, so it cannot expose
uninitialised bytes.

The general shape, since it will recur: a `String` used as a reusable buffer
wants the O(1), non-failing halves of the mutation API — `string-clear` and this
— and the validating ones are for a `String` being built as a value.

## I. Raised by the C6 conversion (2026-09-01)

### 32. There is no nullable string — **fixed 2026-09-01 (C6): `(Maybe StrView)`, and the Stage 11 note that said it would not work is stale**
`die-at`/`report-at` now take a `StrView` (C6 step 2), and 293 of their 688 call
sites moved to `fstr` for free. 26 did not: they pass the result of a *message
builder* — `unknown-type-message`, `with-qualifier-note`,
`qualifier-scope-message`, `cycle-layout-message` and their kin — and those
builders return **null** to mean "no note applies":

```lisp
(defn with-qualifier-note (head:ptr spelling:ptr):ptr
  (let (note:ptr (qualifier-scope-note spelling))
    (when (= note null) (return head))
    …))
```

A `StrView` is a struct and has no null, and `?StrView` does not spell anything —
`?T` is a *nullable pointer*. The honest type is `(Maybe StrView)`, which exists,
but which [stage11](../stage11) recorded as failing in a JIT module, and `die-at`
runs inside the macro/CT JIT.

**Measured, then fixed.** `(Maybe StrView)` was re-tested in both a
`compile-time` body and a `defmacro` body: both construct, `match` and print
correctly, so the Stage 11 caveat no longer holds — record that, because it is
the second Stage 11 string limitation §1.4 found stale and the list should not
keep being cited as current.

The eight nullable builders (`retired-form-message`, `unsafe-bare-message`,
`qualifier-scope-message`, `qualifier-scope-note`, `cheader-skip-note`,
`cycle-definer-message`, `generic-in-other-namespace-message`,
`type-in-other-namespace-message`, plus `case-clause-hint`) now return
`(Maybe StrView)`; the ten that always produce a message return `StrView`; and
the staging wrappers are gone.

**Two things that cost time and generalize.** `if-some` is the *nullable-pointer*
form and refuses a `(Maybe T)` over a struct — "value must be (Maybe (ref ...))
— launder a raw pointer with (as-ref ...)". The general form is `match`. Worth a
docs line, because the name reads as if it covered both.

And `(return "literal")` from a `StrView` function emitted
`store %StrView <bare ptr>`, which LLVM rejects with **no source location at
all**. `emit-return` runs the coercion that materializes the chameleon literal
into `{ptr,len}` only on the ABI-DIRECT branch; a struct return skipped it.
Fixed in `emit-return`, with `tests/fixtures/s17-strview-literal-return.nuc`.
The general shape: every typed slot that coerces has to be enumerated, and
`return` has *two* paths through it — a fix applied to one of them looks
complete and is half a fix.

### 33. A materialized `StrView` borrows to `ptr`/`CStr` silently, and an `fstr` view has no NUL — **fixed 2026-09-01 (C6): 32 live sites, and `--strict-cstr` now counts the class**

`coerce-int-val` lets a `StrView` **value** flow into any `ptr`/`CStr` slot by
taking its `data` field (docs/strings.md, "Coercing a `StrView` to `CStr`/`ptr`
… always takes just `data`, unconditionally"). That is sound for a string
literal, whose backing rodata is NUL-terminated at `data[len]`. It is not sound
for anything `fstr` built: a `String`'s bytes end at `len` and the byte after is
whatever the `Vector`'s spare capacity holds.

So the moment C6 made `type-to-ir` return `StrView`, **32 sites in the compiler
began handing a non-NUL-terminated pointer to a consumer that would `strlen` it**
— `emit-load`/`emit-store` and their `-at` forms, `abi-ret-ir`, `abi-eightbyte-ir`,
`rv-flat-add`, `emit-match-clauses`, two REPL `ret-ir` locals, and three
`(strcmp (ptr-int-ir) "i32")` calls. Every one compiled without a diagnostic, and
the 2,596-artifact snapshot stayed byte-identical — the arena's fresh pages are
zeroed, so `strlen` stopped in the right place *by luck*. Nothing in the gate set
could have caught it.

**Fixed** by converting all 32 consumers (`AbiInfo.reg0`/`reg1` and
`RvFlat.ir0`/`ir1` are `StrView` fields now — an IR type string's honest type),
and the three `strcmp`s became `StrView` `=`, which is content comparison and
needs no NUL at all.

**The lasting change is the detection.** `--strict-cstr` now reports the borrow
itself (`strict-cstr-check-borrow`, hooked at the one coercion branch that emits
it), because it is the one residual class no *type* marks: the borrow is what the
language accepts, so a type error never fires and grep has nothing to match. The
count is a C6/C7 progress number beside `string-as-cstr` — it must be 0 at C8,
and holding it at 0 is what makes the rest of the substrate conversion safe to
attempt.

Deliberately **not** fixed by making `fstr` NUL-terminate its buffer. That would
have made all 32 sites correct and left the rule "a `StrView` is a C string"
silently false for every view a user builds — hiding the class instead of
retiring it.

---

### 34. `strview-starts-with` / `-ends-with` cannot take a literal prefix — **fixed 2026-09-02 (C6)**

Both take `(ref StrView)`. Address-of is lvalue-only, and a string literal is
not an lvalue, so `(strview-starts-with (addr-of sv) "avr")` does not compile
and the prefix has to be a named local at every call site. That is the whole of
what these predicates are for: of the 44 `strncmp` sites C6 converted, the
prefix was a literal in 42.

The fix is `strview-has-prefix` / `strview-has-suffix`, by value, delegating to
the by-reference forms. Deliberately additive rather than a change of the
existing signatures: a `(ref StrView)` receiver is right when the caller already
holds one, and the by-reference form is what the by-value one calls.

This is the same receiver-convention question §2.3 of
[borrow-conventions.md](borrow-conventions.md) records, arriving at a concrete
site: the answer is not "pick one convention", it is that a by-value convenience
belongs beside a by-reference primitive whenever a *literal* is a plausible
argument.

---

### 35. `(parse i64 …)` reported overflow as success — **fixed 2026-09-02 (C6)**

`(parse i64 "99999999999999999999")` returned `(ok 9223372036854775807)`. The
conformance delegated to `strtoll` and checked only that the end pointer had
consumed every byte — which it had. `strtoll` clamps to `LLONG_MAX` and reports
the overflow *only* through `errno`, which nothing here read. The source comment
asserted the opposite ("Detects overflow by checking that strtoll consumed all
bytes"), so the defect was documented as a feature.

`i32` was accidentally safe: its explicit range check rejected the clamped
`LLONG_MAX`.

The fix replaces the libc delegation with `strview-parse-magnitude`, a digit
walk that tests the limit *before* each multiply, and it lives in
`lib/strview.nuc` rather than `lib/parse.nuc` because it is a view operation —
`FromStr` is the protocol layer above it, and the compiler's reader needs the
primitive without the protocol. `parse-int-error` moved to `lib/string-errors.nuc`
with it. This also deletes a `malloc`/`memcpy`/`free` per parse and the
leading-whitespace special case (a space is simply not a digit).

Three things came with it. `(parse ui64 …)` now exists — the range above `i64`
had no conformance at all. `strview-parse-magnitude` takes a **radix**, which
`FromStr` cannot express (the protocol is keyed only on the target type), and
that is what let the compiler's reader adopt it for `0x` literals. And the
reader's `__errno_location` declaration — the one glibc/musl-specific `declare`
in `src/` — is gone with the errno dance, along with two `alloca i8` token
buffers and their "integer literal too long" limits.

`examples/parse-test.nuc` gained five cases (i64 overflow, i64 one past max,
ui64 max, ui64 overflow, ui64 negative) so the defect cannot return silently.

---

### 36. No `strview-take-bytes` beside `strview-drop-bytes` — **fixed 2026-09-02 (C7-3)**

`strview-drop-bytes` existed; its counterpart did not, so a caller that had
already found a split point had to spell the prefix as `(strview (sv 'data) n)`
— reaching for the raw constructor and the `data` field to express a slice the
library was one function short of.

The site was `fuse-colon-paren` in `src/reader.nuc`, converted in C7-3 from a
`memcpy` into a stack buffer to a native scan over the token's bytes. It splits
a symbol at a colon index a `strview-find-byte` just returned, and needs both
halves.

`strview-take-bytes` carries the same contract as `strview-drop-bytes`: the
caller already knows the split point is a character boundary, typically because
a scan for a delimiter returned it. That is why neither is spelled `take`/`drop`
without the `-bytes` suffix — the char-indexed forms would have to decode.

---

### 37. `symbol-intern` could not take a literal — **fixed 2026-09-02 (C7-4a)**

The primitive is `((sv (ref StrView)))`, and `addr-of` is lvalue-only, so
`(symbol-intern "Any")` and `(symbol-intern (fstr ns "/" bare))` did not compile
at all. C7-4a mints a name from a literal or a freshly formatted view at dozens
of sites, so every one of them would have had to bind a `let` first.

The fix is the by-value overload beside the by-reference primitive — the same
shape, for the same reason, as gap #34's `strview-has-prefix`.

The deeper answer is a **string-literal → `Symbol` coercion**, which would let
`(symbol-intern "Any")` be written `"Any"` wherever a `Symbol` is expected and
delete every explicit intern this step introduced. It wants the literal interned
at *compile* time, into the emitted module's data rather than at first use, so it
is a code-generation change and not a library one. Deferred; noted here because
C7-4a is the evidence that the site count justifies it.

---

### 38. The zero `Symbol` could be recognised but not written — **fixed 2026-09-02 (C7-4a)**

C7-3b added `symbol-none?` for "this node has no name" and left the writing side
to `calloc` — which works for a cell allocated all at once, and not at all for
the two shapes C7-4a is full of: an out-parameter a parser leaves unset when the
name carries no `:type`, and a `let` binding initialised before the parse that
fills it. `Symbol.p` is a non-null pointer type, so there is no null to assign.

`symbol-none` mints it with `memset`. Its bytes may never be read; recognising it
with `symbol-none?` is the only thing it is good for, which is why the two ship
as a pair.

---

### 39. `(= sv null)` silently strcmp'd a view's `data` — **fixed 2026-09-02 (C7-4b)**

The `=`/`!=` lowering admits a `StrView` operand and content-compares it with
`strcmp` on the extracted `data` word. W5c had already closed the same trap for
`CStr` — comparing against the `null` literal is an identity test and must not
reach `strcmp`, which segfaults under glibc — but it deliberately restricted the
escape to a partner that is one `ptr` register, on the reasoning that "a
`StrView` is a 16-byte struct and can never be null, so `(= sv null)` is left
exactly as it was."

That reasoning was right about the type and wrong about the consequence. Being
unable to *be* null did not stop `(= sv null)` from being *written* — C7-4b
retyped `Sym.ir-name` from `CStr` to `StrView` and one surviving null guard,
`(!= (sym 'ir-name) null)` in `repl-note-globals-decls`, kept compiling and
started emitting `strcmp(%data, null)`. Every REPL test failed; nothing else did.

`--strict-cstr` did not see it. Its borrow check fires where a `StrView` reaches
a `CStr` parameter, and this borrow happens inside the operator's own lowering,
which synthesises the call as text. The census counted the `strcmp` (as it counts
all of them) without knowing one operand was a view.

The fix is a type error, not a lowering: comparing a `StrView` with `null` names
`str-empty?` in its diagnostic. A view cannot be null, so no correct program can
ask the question, and the empty view is what every site meant.

### 40. A string literal inside a collection literal was a `CStr` — **fixed 2026-09-02 (C7-5)**

`"…"` is a `StrView` everywhere in the language except one place: inside `[…]`,
`#{…}` and `{…}`, where `lit-type-node` gave kind 3 the element type `CStr`.
The comment there recorded the deferral honestly — "`node-type` types a NODE-STR
as StrView (NS-3), so asking it here would silently retype every existing
`["a" "b"]`" — and Stage 17 is where that retype belongs.

The cost of leaving it was not cosmetic. C7-5 turned the C header parser's
identifiers into `Symbol`s, and the natural membership test became
`(contains? #{"const" …} (symbol-as-view tok))` — a `StrView` argument to a
`HashSet CStr`, which is a **silent borrow** (§33), inside the collection's own
monomorphized `=`/`hash` where the census cannot see it. Three of them landed in
`src/cheader.nuc` before `--strict-cstr` caught them at the call boundary.

Kind 3 is `StrView` now. Two consequences fell out of the flip:

- The element type of `#{…}` reaches the *whole* set/map, so a `(HashMap CStr V)`
  built from a literal is now a `(HashMap StrView V)`. Every such literal in the
  compiler is a fixed table (operator mnemonics, LLVM float opcodes, the C
  specifier keywords, the special-form and primitive-type name sets), and each
  now binds through an explicitly typed local — the shape a `want` arms, which
  means the same source compiles under the old boot compiler and the new one.
  That is what let a language-level element-type change land with no bootstrap
  shim at all.
- `examples/as-sugar.nuc` demonstrates the `x:Type` cast in argument position on
  a set membership test; it keeps the cast and adds the view conversion the set
  now wants.

### 41. `StrView`'s `Hash` conformance was not where `CStr`'s is — **fixed 2026-09-02 (C7-5)**

`(extend CStr Hash)` lives in `lib/hash.nuc`, which every hash container imports,
so a `CStr`-keyed `#{…}` works on the collection import alone. `StrView`'s lived
in `lib/strview.nuc`, so the moment §40 made `#{"a" "b"}` a `HashSet StrView` the
same session failed with *no matching method for overloaded 'hash'* — a REPL
session that had imported `hashset` and nothing else.

The conformance moved to `lib/hash.nuc`, beside `CStr`'s and directly on
`fnv1a-bytes` (which `hash.nuc` already imports); `strview-hash` stays in
`lib/strview.nuc` as the public helper. Giving the collections an
`(import-use strview)` instead would also have worked and was rejected: it drags
`char` and `error` into every unit with a container, which reorders the import
bookkeeping a REPL test asserts on.

`Eq` could **not** follow it. `(extend CStr Eq)` is code-free — the builtin `=`
on two `CStr` lowers to `strcmp` and satisfies the protocol — but a struct type
conforms only through real methods, and `StrView`'s need `strview-eq`, which
lives in `lib/strview.nuc` (which imports `numeric`, so the dependency cannot
run the other way). `(extend StrView Eq)` therefore stays put. It is not needed
for a container: the monomorphized key compare resolves `=` through the
compiler's own `StrView` lowering, the same way it does for `CStr`.
