# Strings (`lib/char.nuc`, `lib/strview.nuc`, `lib/string.nuc`, Stage 11)

`(import-use string)` provides the full string stack: the `Char` scalar, the `StrView` borrowed slice, the `String` owning type, UTF-8 encode/decode, split, lines, trim, and `parse`. Individual sub-libraries may be imported when only part of the stack is needed; see the import list at the end of each section.

---

## §1 — The `Char` scalar

`Char` is a built-in 32-bit Unicode scalar value (a single codepoint, not a grapheme cluster). It is a **distinct type** from `ui32`: the two share the same IR representation (`i32`) but are not interchangeable under `type-eq`. Operators like `=` and `!=` dispatch to `Char`-specific overloads when both operands are `Char`, and a `ui32` argument does not silently satisfy a `Char` parameter.

### Char literals

| Form | Value |
|------|-------|
| `\a` | the character `a` (any printable ASCII character) |
| `\newline` | U+000A LINE FEED |
| `\tab` | U+0009 HORIZONTAL TAB |
| `\return` | U+000D CARRIAGE RETURN |
| `\null` | U+0000 NULL |
| `\space` | U+0020 SPACE |
| `\u{41}` | U+0041 `A` (hexadecimal codepoint, 1–6 hex digits) |
| `\u{1F600}` | U+1F600 GRINNING FACE (emoji, requires 4 UTF-8 bytes) |

The `\u{…}` form validates that the value is a Unicode scalar value: it must be ≤ U+10FFFF and must not be a surrogate (U+D800–U+DFFF). Reader errors are emitted for invalid codepoints.

### Conversion

```lisp
(cast ui32 \A)     ; → 65
(cast Char 65)     ; → \A
```

`cast` between `Char` and `ui32` is a same-width reinterpret (no IR instruction).

### Equality

```lisp
(= \a \a)   ; → 1
(= \a \b)   ; → 0
```

`=` and `!=` on `Char` compare codepoint values. A `Char` and a `ui32` are not `=`-comparable by default (distinct types, distinct dispatch).

---

## §2 — `Char` functions (`lib/char.nuc`)

`(import-use char)` — requires `(import-use error)` and `(import-use string-errors)` (transitively satisfied).

### `DecodeResult`

```lisp
(defstruct DecodeResult
  ch:Char
  nbytes:usize
  ok:i32)
```

Returned by `char-decode-utf8`. `ch` and `nbytes` are valid only when `ok = 1`. On error, `nbytes = 1` so callers can skip one byte and retry.

### UTF-8 encode/decode

| Function | Signature | Description |
|----------|-----------|-------------|
| `char-utf8-len` | `(c:Char) → usize` | Number of UTF-8 bytes needed to encode `c` (1–4). Does not re-validate `c`. |
| `char-encode-utf8` | `(c:Char buf:(ptr ui8)) → usize` | Encode `c` into `buf` (caller provides ≥ 4 bytes). Returns bytes written (1–4). No NUL added. |
| `char-decode-utf8` | `(p:(ptr ui8) len:usize) → DecodeResult` | Decode one codepoint from `p[0..len)`. Validates continuation bytes, overlong encodings, and surrogates. On success, `ok=1`. On error, `ok=0` and `nbytes=1` (skip-one-byte convention). |

### Conversion

| Function | Signature | Description |
|----------|-----------|-------------|
| `char-to-u32` | `(c:Char) → ui32` | Reinterpret `Char` as its codepoint value. No-op at IR level. |
| `char-from-u32` | `(n:ui32) → !Char` | Construct a `Char` from a raw codepoint. Errors `invalid-codepoint` if `n > 0x10FFFF` or `n` is a surrogate. |

### Classification (ASCII-only, no `?` suffix)

The `?` character is invalid in LLVM IR identifiers for non-generic `defn` names, so these functions use the `char-is-*` prefix without a `?` suffix.

| Function | Signature | Returns 1 when… |
|----------|-----------|----------------|
| `char-is-ascii` | `(c:Char) → i32` | codepoint is U+0000–U+007F |
| `char-is-digit` | `(c:Char) → i32` | c is ASCII `'0'`–`'9'` |
| `char-is-alpha` | `(c:Char) → i32` | c is ASCII `'a'`–`'z'` or `'A'`–`'Z'` |
| `char-is-alnum` | `(c:Char) → i32` | c is `char-is-digit` or `char-is-alpha` |
| `char-is-whitespace` | `(c:Char) → i32` | c is space, tab, LF, CR, FF, or VT |

All functions are **total**: non-ASCII input returns 0.

### Case conversion (ASCII-only, total)

| Function | Signature | Description |
|----------|-----------|-------------|
| `char-ascii-upper` | `(c:Char) → Char` | Convert `'a'`–`'z'` → `'A'`–`'Z'`. Non-lowercase and non-ASCII codepoints returned unchanged. |
| `char-ascii-lower` | `(c:Char) → Char` | Convert `'A'`–`'Z'` → `'a'`–`'z'`. Non-uppercase and non-ASCII codepoints returned unchanged. |

---

## §3 — `StrView` — borrowed byte/char substrate

`(import-use strview)` — also requires `(import-use hash)` and `(import-use numeric)` (transitively satisfied). For `ByteStr`/`Str` protocol conformances, use `(import-use strview-str)` instead.

`StrView` is a non-owning, immutable, length-prefixed byte slice. It borrows its bytes — copying a `StrView` copies two words; there is no `Drop` conformance and nothing is freed.

```lisp
(defstruct StrView
  data:(ptr ui8)
  len:usize)
```

`data` points to the first byte of the underlying buffer. `len` is authoritative; the buffer need not be NUL-terminated (except when created via `strview-from-cstr`, in which case `strview-to-cstr` is sound).

### Construction

| Function | Signature | Description |
|----------|-----------|-------------|
| `strview-from-cstr` | `(cs:CStr) → ptr:StrView` | Heap-allocate a `StrView` that borrows the CStr's bytes (no copy). Caller owns the `ptr:StrView` wrapper and must free it; the bytes are borrowed from `cs`. |
| `strview-to-cstr` | `(sv:(ref StrView)) → CStr` | Reinterpret `data` as a CStr. Only sound when the buffer is NUL-terminated at `data[len]` (i.e., built from a CStr or the keyword intern arena). |

Manual construction via a struct literal is also valid:
```lisp
(let ((sv (ref StrView)) (alloca StrView))
  (.set! sv data some-ptr)
  (.set! sv len  some-len)
  ...)
```

### Read operations

| Function | Signature | Description |
|----------|-----------|-------------|
| `strview-byte-len` | `(sv:(ref StrView)) → usize` | O(1) byte length. |
| `strview-byte-at` | `(sv:(ref StrView) i:usize) → !ui8` | O(1) byte access. Errors `str-index-out-of-bounds` when `i ≥ len`. |
| `strview-char-count` | `(sv:(ref StrView)) → usize` | O(n) codepoint count (counts non-continuation lead bytes). |
| `strview-char-at` | `(sv:(ref StrView) i:usize) → !Char` | O(n) nth codepoint (0-indexed). Errors `str-index-out-of-bounds` when `i ≥ char-count`. Invalid bytes return U+FFFD. |
| `strview-empty` | `(sv:(ref StrView)) → i32` | 1 when `len = 0`, else 0. |

### Iterators

Both iterators are returned **by value** and alias the StrView's buffer. They must not outlive the StrView that produced them. Drive with `(addr-of it)` + `next`.

| Function | Return type | Description |
|----------|-------------|-------------|
| `strview-bytes` | `ByteIter` | Forward iterator over raw bytes (`(Iterator ui8)` conformance). |
| `strview-chars` | `CharIter` | Forward iterator over UTF-8 codepoints (`(Iterator Char)` conformance). Invalid bytes yield U+FFFD (no error path); iteration always terminates. |

```lisp
(let (it:ByteIter (strview-bytes sv))
  (while-let ((some b) (next (addr-of it)))
    (printf "%d\n" (cast i32 b))))
```

### Sub-slice

| Function | Signature | Description |
|----------|-----------|-------------|
| `strview-sub-bytes` | `(sv:(ref StrView) start:usize end:usize) → !ptr:StrView` | O(1) sub-slice `[start, end)`. Returns a heap-allocated `ptr:StrView` whose `data` borrows the parent's buffer. Caller must free the wrapper (not the data). |

**v1 limitation.** `sub-bytes` returns `!ptr:StrView` rather than `!StrView` because the compiler cannot return a struct payload through `!T`/`Result` (the struct fields arrive as zero when unwrapped via `match`). The heap-allocated wrapper is the workaround.

Errors:
- `str-index-out-of-bounds` — `start > end` or `end > len`
- `invalid-char-boundary` — `start` or `end` falls on a UTF-8 continuation byte (pattern `10xxxxxx`)

### Search and pattern matching

| Function | Signature | Description |
|----------|-----------|-------------|
| `strview-byte-find` | `(sv:(ref StrView) needle:(ref StrView)) → (Maybe usize)` | First byte index of `needle` in `sv`, or `none`. Empty needle returns `(some 0)`. |
| `strview-starts-with` | `(sv:(ref StrView) prefix:(ref StrView)) → i32` | 1 if `sv` begins with `prefix` (byte-level), else 0. |
| `strview-ends-with` | `(sv:(ref StrView) suffix:(ref StrView)) → i32` | 1 if `sv` ends with `suffix` (byte-level), else 0. |
| `strview-contains-str` | `(sv:(ref StrView) needle:(ref StrView)) → i32` | 1 if `needle` appears anywhere in `sv`, else 0. |

`byte-find` returning `(Maybe usize)` is not an error — "not found" is a legitimate result, not a failure.

### Trim

| Function | Signature | Description |
|----------|-----------|-------------|
| `strview-trim` | `(sv:(ref StrView)) → StrView` | Remove leading and trailing ASCII whitespace (space, tab, LF, CR). Returns a borrowed sub-view (no allocation). |
| `strview-trim-start` | `(sv:(ref StrView)) → StrView` | Remove leading ASCII whitespace only. |
| `strview-trim-end` | `(sv:(ref StrView)) → StrView` | Remove trailing ASCII whitespace only. |

All three return a `StrView` by value that borrows the same underlying bytes. No allocation occurs.

### Conformances

| Protocol | Notes |
|----------|-------|
| `Eq` | Byte equality: same length and identical bytes. Takes `StrView` by value. |
| `Ord` | Byte-lexicographic: `memcmp` on `min(a.len, b.len)` bytes; shorter is less-than on tie. |
| `Hash` | FNV-1a over exactly `len` bytes (handles embedded NULs). Receiver `(ref StrView)`. |
| `ByteStr ByteIter` | Via `(import-use strview-str)` (separate import to avoid circular dependency). |
| `Str CharIter` | Via `(import-use strview-str)`. |

---

## §4 — `ByteStr` and `Str` protocols

`(import-use string-protocols)` — also requires `(import-use strview)` and `(import-use iterator)` (transitively satisfied).

Two read-only protocol layers define the public string surface.

### `(ByteStr ByteI)` — byte substrate

`ByteI` is the conformer's byte-iterator type, which must itself conform to `(Iterator ui8)`.

```lisp
(defprotocol (ByteStr ByteI)
  (byte-len:usize        ((self (ref Self))))
  (byte-at:!ui8          ((self (ref Self)) i:usize))
  (bytes:ByteI           ((self (ref Self))))
  (as-view:StrView       ((self (ref Self))))
  (sub-bytes:!ptr:StrView ((self (ref Self)) start:usize end:usize))
  ((byte-find (Maybe usize)) ((self (ref Self)) (needle (ref StrView)))))
```

| Method | Description |
|--------|-------------|
| `byte-len` | Byte length. O(1) for `StrView`/`String`. |
| `byte-at` | i-th byte, O(1). Errors `str-index-out-of-bounds` when `i ≥ byte-len`. |
| `bytes` | Fresh byte iterator by value (associated type `ByteI`). Drive with `(addr-of it)` + `next`. |
| `as-view` | Borrow entire content as a `StrView` (two-word value, no copy). The bridge to all StrView helpers. |
| `sub-bytes` | Sub-slice `[start, end)` as a borrowed `!ptr:StrView`. See §3 for error conditions and the v1 limitation. |
| `byte-find` | First byte index of a substring, or `none`. |

### `(Str CharI)` — codepoint layer

`CharI` is the conformer's char-iterator type, which must conform to `(Iterator Char)`. `Str` extends `Eq` — every type conforming to `Str` must also conform to `Eq` (content comparison).

```lisp
(defprotocol (Str CharI)
  (char-count:usize    ((self (ref Self))))
  (str-empty?:i32      ((self (ref Self))))
  (char-at:!Char       ((self (ref Self)) i:usize))
  (chars:CharI         ((self (ref Self))))
  (starts-with?:i32    ((self (ref Self)) (prefix (ref StrView))))
  (ends-with?:i32      ((self (ref Self)) (suffix (ref StrView))))
  (contains-str?:i32   ((self (ref Self)) (needle (ref StrView)))))
```

| Method | Description |
|--------|-------------|
| `char-count` | O(n) codepoint count. Never an unqualified `count` (byte vs. codepoint ambiguity). |
| `str-empty?` | 1 when `byte-len = 0`, else 0. Cheap: no codepoint walk. |
| `char-at` | nth codepoint, O(n). Errors `str-index-out-of-bounds` when `i ≥ char-count`. |
| `chars` | Fresh char iterator by value (associated type `CharI`). Drive with `(addr-of it)` + `next`. |
| `starts-with?` | 1 when self begins with the given `StrView` prefix (byte-level). |
| `ends-with?` | 1 when self ends with the given `StrView` suffix (byte-level). |
| `contains-str?` | 1 when self contains the given `StrView` needle. |

### Conformers

| Type | `ByteStr ByteI` | `Str CharI` | Import |
|------|-----------------|-------------|--------|
| `StrView` | `(ByteStr ByteIter)` | `(Str CharIter)` | `(import-use strview-str)` |
| `String` | `(ByteStr ByteIter)` | `(Str CharIter)` | `(import-use string)` |

**Circular-import note.** `string-protocols.nuc` imports `strview` (for `StrView` in method signatures). Therefore `strview.nuc` cannot import `string-protocols` — a circular dependency. The conformances for `StrView` live in the separate `lib/strview-str.nuc`, which imports both at the leaf level. Use `(import-use strview-str)` to get `ByteStr`/`Str` on `StrView`.

---

## §5 — `String` — owning type

`(import-use string)` — also requires `(import-use vector)`, `(import-use strview-str)`, `(import-use char)`, `(import-use string-protocols)`, and `(import-use hash)` (all transitively satisfied).

`String` owns a heap byte buffer and releases it at `with`-scope exit. All reading is delegated through a zero-copy `string-as-view` bridge to `StrView`.

```lisp
(defstruct String bytes:(Vector ui8))
```

### Construction

| Function | Signature | Description |
|----------|-----------|-------------|
| `string-new` | `() → String` | Empty `String` with the default (libc) allocator. |
| `string-new-alloc` | `(a:(ref AllocHandle)) → String` | Empty `String` with an explicit allocator handle (copied in). |
| `string-with-capacity` | `(n:usize) → String` | Empty `String` (libc allocator) pre-reserving `n` bytes. |

### Validating constructors

| Function | Signature | Description |
|----------|-----------|-------------|
| `string-from-cstr` | `(cs:CStr) → !String` | Copy a CStr's bytes into a new `String`, validating UTF-8. Errors `invalid-utf8`. |
| `string-from-view` | `(sv:(ref StrView)) → !String` | Copy a StrView's bytes into a new `String`, validating UTF-8. Errors `invalid-utf8`. |
| `string-from-cstr-unchecked` | `(cs:CStr) → String` | Copy a CStr's bytes without validation. Caller must ensure valid UTF-8. |

### Bridge

| Function | Signature | Description |
|----------|-----------|-------------|
| `string-as-view` | `(self:(ref String)) → StrView` | Zero-copy `StrView` over the current contents. The view borrows the `String`'s buffer and must not outlive it. |

### Mutation

| Function | Signature | Description |
|----------|-----------|-------------|
| `string-push-char` | `(self:(ref String) c:Char) → void` | Append a single `Char`. Always valid UTF-8 by construction. |
| `string-push-str` | `(self:(ref String) s:(ref StrView)) → !i32` | Append a `StrView`'s bytes, validating UTF-8 first. Returns `(ok 0)` on success. Errors `invalid-utf8`. |
| `string-pop-char` | `(self:(ref String)) → (Maybe Char)` | Remove and return the last codepoint, or `none` if empty. |
| `string-clear` | `(self:(ref String)) → void` | Set `len` to 0 (retain capacity). |
| `string-truncate` | `(self:(ref String) byte-len:usize) → !i32` | Truncate to `byte-len` bytes. Returns `(ok 0)` on success. Errors `str-index-out-of-bounds` if `byte-len > len`; errors `invalid-char-boundary` if `byte-len` falls mid-codepoint. |
| `string-reserve` | `(self:(ref String) extra:usize) → void` | Ensure at least `extra` additional bytes of capacity beyond current length. |
| `string-shrink-to-fit` | `(self:(ref String)) → void` | Shrink capacity to match `len`. Reallocates or frees if `len = 0`. |

**v1 limitation.** `string-push-str` and `string-truncate` return `!i32` rather than `!void` — the compiler does not yet support `!void` as a result type. `0` means success.

### Conformances

| Protocol | Notes |
|----------|-------|
| `Drop` | Frees the wrapped `Vector ui8` buffer at `with`-scope exit. `drop` takes `(ptr String)`. |
| `ByteStr ByteIter` | All methods delegate through `string-as-view`. |
| `Str CharIter` | All methods delegate through `string-as-view`. |
| `Eq` | Byte-content equality via StrView comparison. Takes `String` by value. |
| `Ord` | Byte-lexicographic ordering via StrView comparison. Takes `String` by value. |
| `Hash` | FNV-1a via `strview-hash`. Receiver `(ref String)`. |

`String` conforms to both `Hash` and `Eq`, making it a valid key for `HashMap`/`HashSet`. See `examples/string-test.nuc` for a worked example.

### Example

```lisp
(import-use string)
(import-use vector)

(defn main:i32 ()
  (with (s:String (string-new))
    (string-push-char (addr-of s) \H)
    (string-push-char (addr-of s) \i)
    (let (sv:StrView (string-as-view (addr-of s)))
      (printf "%.*s\n" (cast i32 (sv len)) (sv data))))
  0)
```

---

## §6 — Split, lines, and trim

`(import-use string-split)` — requires `(import-use strview)` (transitively satisfied).

Lazy splitting with no allocation — iterators hold raw pointers into the source `StrView`. The source must remain alive for the iterator's lifetime.

### `strview-split`

```lisp
(defn strview-split:SplitIter ((sv (ref StrView)) (sep (ref StrView))))
```

Constructs a `SplitIter` that lazily splits `sv` on byte-level separator `sep`.

**`SplitIter` API:**

| Function | Signature | Description |
|----------|-----------|-------------|
| `split-iter-done` | `(it:(ref SplitIter)) → i32` | 1 when no more segments remain. |
| `split-iter-next` | `(it:(ref SplitIter)) → StrView` | Advance and return the next segment. Precondition: `done = 0`. |

Iteration yields all segments, including empty ones. An empty input yields one empty segment. An empty separator treats the whole remaining buffer as a single segment.

### `strview-lines`

```lisp
(defn strview-lines:LineIter ((sv (ref StrView))))
```

Constructs a `LineIter` that splits `sv` on `\n`, stripping any trailing `\r` from each line (handles `\r\n` line endings).

**`LineIter` API:**

| Function | Signature | Description |
|----------|-----------|-------------|
| `lines-iter-done` | `(it:(ref LineIter)) → i32` | 1 when no more lines remain. |
| `lines-iter-next` | `(it:(ref LineIter)) → StrView` | Advance and return the next line (without its trailing newline). Precondition: `done = 0`. |

### Iterator loop pattern

```lisp
(let (sep:StrView ...)
  (let (it:SplitIter (strview-split sv (addr-of sep)))
    (while (not (split-iter-done (addr-of it)))
      (let (seg:StrView (split-iter-next (addr-of it)))
        (printf "%.*s\n" (cast i32 ((addr-of seg) len)) ((addr-of seg) data))))))
```

### `Iterator` conformance and `doseq-split` (Stage 13 R1)

`SplitIter` and `LineIter` also conform to `(Iterator i64)`, so `reduce` /
`doseq-iter` can drive them. They cannot conform to `(Iterator StrView)`
directly — `(Maybe StrView)` embeds a struct in the anonymous union, which the
macro-expansion JIT module cannot resolve — and a niche `(Maybe ptr)` is not
matchable. Instead `next` stores each segment in the iterator's `cur` slot and
yields a `(ref StrView)` into it **cast to `i64`** (a tagged, matchable Maybe).
The `(doseq-split (var iter-ref) body)` macro hides the decode, binding `var` to
a `(ref StrView)` borrowing `cur` (valid until the next step):

```lisp
(let (it:SplitIter (strview-split sv sep))
  (doseq-split (seg (addr-of it))
    (printf "%.*s\n" (cast i32 (seg len)) (seg data))))
```

The done-flag API (`split-iter-done`/`split-iter-next`, `lines-iter-done`/
`lines-iter-next`) is retained and yields identical segments. See
[Iterators](iterators.md#more-concrete-iterators-stage-13-r1) and
`examples/split-iter-test.nuc`.

**C-string byte/char folds.** `(cstr-bytes cs)` / `(cstr-chars cs)` return a
`ByteIter` / `CharIter` over a `CStr` (NUL excluded), so a `CStr` can be byte- or
char-folded with `reduce` like a `String` (which folds via `string-as-view` +
`strview-bytes`/`strview-chars`). See `examples/cstr-fold-test.nuc`.

### Trim

Trim functions live in `lib/strview.nuc` (available via `(import-use strview)`):

| Function | Signature | Description |
|----------|-----------|-------------|
| `strview-trim` | `(sv:(ref StrView)) → StrView` | Remove leading and trailing ASCII whitespace (space, tab, LF, CR). Returns a borrowed sub-view. |
| `strview-trim-start` | `(sv:(ref StrView)) → StrView` | Remove leading ASCII whitespace only. |
| `strview-trim-end` | `(sv:(ref StrView)) → StrView` | Remove trailing ASCII whitespace only. |

All three return a `StrView` by value that borrows the same underlying bytes. No allocation occurs.

---

## §7 — `FromStr` and `parse`

`(import-use parse)` — requires `(import-use strview)` (transitively satisfied).

### `FromStr R` protocol

```lisp
(defprotocol (FromStr R)
  (from-str:R ((self Self) (sv (ref StrView)))))
```

`R` is the return-type parameter (a phantom-type pattern). The `(self Self)` first argument is a phantom value used only for dispatch — callers do not pass a meaningful value.

| Conformer | `R` | Import |
|-----------|-----|--------|
| `i32` | `!i32` | `(import-use parse)` |
| `i64` | `!i64` | `(import-use parse)` |
| `f64` | `!f64` | `(import-use parse)` |

### `parse` macro

```lisp
(defmacro parse (ty sv)
  `(from-str (cast ~ty 0) ~sv))
```

`(parse T sv)` expands to `(from-str (cast T 0) sv)`. The `(cast T 0)` provides a phantom zero value of the target type to select the right conformer.

```lisp
(parse i32 sv)   ; → !i32
(parse i64 sv)   ; → !i64
(parse f64 sv)   ; → !f64
```

### Parsing semantics

All three conformances are **strict**:
- Empty input → error
- Leading whitespace → error (unlike libc `strtol`, which skips whitespace)
- All bytes must be consumed; trailing non-numeric characters → error
- `i32` overflow → `parse-int-error` (range checked against `[-2147483648, 2147483647]`)
- `i64` overflow → `parse-int-error` (detected by `strtoll` + consumed-bytes check)
- `f64`: delegates to `strtod`; zero bytes consumed → `parse-float-error`; trailing garbage → `parse-float-error`

```lisp
(import-use parse)

(defn main:i32 ()
  (let ((sv (ref StrView)) (alloca StrView))
    (.set! sv data (cast ptr:ui8 (cast ptr "42"))
    (.set! sv len  (cast usize 2))
    (match (parse i32 sv)
      ((ok n)  (printf "parsed: %d\n" n))
      ((err e) (printf "error: %s\n" (err-name e)))))
  0)
```

---

## §8 — Error codes

All string-related error codes (defined in `lib/string-errors.nuc` and `lib/parse.nuc`):

| Error code | Message | Raised by |
|------------|---------|-----------|
| `str-index-out-of-bounds` | `"string index out of bounds"` | `byte-at`, `char-at`, `sub-bytes`, `string-truncate` |
| `invalid-char-boundary` | `"byte offset is not a UTF-8 codepoint boundary"` | `sub-bytes`, `string-truncate` |
| `invalid-utf8` | `"bytes are not valid UTF-8"` | `string-from-cstr`, `string-from-view`, `string-push-str` |
| `invalid-codepoint` | `"value is not a Unicode scalar value"` | `char-from-u32` |
| `parse-int-error` | `"invalid integer"` | `(parse i32 …)`, `(parse i64 …)` |
| `parse-float-error` | `"invalid float"` | `(parse f64 …)` |

All of these conform to the `Err` type and are usable with `(err-name e)`, `try`, `with-handler`, and `match`. See [Error handling](errors.md).

---

## Gotchas and constraints

- **`?` in function names.** Classification functions use `char-is-ascii` etc. without a `?` suffix — `?` is invalid in LLVM IR identifiers for non-generic `defn` names. The `?` suffix is only valid in protocol method names, where the generics machinery sanitizes it.
- **`string-push-str` and `string-truncate` return `!i32`.** The compiler does not yet support `!void`. Check for `(ok 0)` / `(err e)` or use `try` to propagate.
- **`sub-bytes` returns `!ptr:StrView`.** The caller owns the `ptr:StrView` wrapper and must `free` it. The bytes are borrowed from the source StrView; do not free `data`.
- **`SplitIter`/`LineIter` are not `Iterator StrView`.** The `(Maybe StrView)` union type cannot be compiled in JIT macro modules. They instead conform to `(Iterator i64)`, yielding each segment as a `(ref StrView)` cast to `i64`; the `doseq-split` macro decodes it. The `*-iter-done`/`*-iter-next` pair is still available.
- **`string-new-alloc` takes `(ref AllocHandle)`.** It copies the handle in; the caller retains ownership of the original.
- **`CharIter` is lossless but substitutes U+FFFD.** Invalid UTF-8 bytes are never skipped silently — iteration always advances by at least one byte. Invalid bytes produce U+FFFD (the Unicode replacement character) as the yield value rather than an error, so iterating over a `CharIter` always terminates without an error path.
- **Borrow lifetimes are unchecked.** `ByteIter`, `CharIter`, `SplitIter`, `LineIter`, and sub-views returned by `strview-sub-bytes` all hold raw pointers into their source buffer. There is no compile-time lifetime enforcement — the caller is responsible for keeping the source alive.
