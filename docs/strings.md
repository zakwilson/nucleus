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
(as ui32 \A)     ; → 65
(as Char 65)     ; → \A
```

`as` between `Char` and `ui32` is a same-width reinterpret (no IR instruction).

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

These functions use the `char-is-*` prefix without a `?` suffix. That is now a naming convention, not a restriction: `?` and `!` are legal in any Nucleus name and are mangled (`?` → `_QMARK`, `!` → `_BANG`) wherever a name becomes an LLVM identifier — see [`?`/`!` in names](generics.md#polymorphism-overloaded-defn-multimethods).

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

The bare struct type is registered in the prelude, so `StrView` is available as a type in every compilation unit without any import. The functions and protocol conformances below still require `(import-use strview)`.

**A bare `"…"` string literal's static type is `StrView`** (not `CStr`). Nothing about *writing* a literal changes; what changes is what type-checking and codegen see it as. Emission stays target-aware: at a `ptr`/`CStr`-typed consumer (a `printf`/libc argument, `strcmp`, `=`/`!=`, a `:CStr`/`:ptr` parameter or slot) the literal collapses to the same bare pointer it always emitted, with no extra IR — no `{data,len}` struct is built. Only when a literal flows into a genuinely `StrView`-typed `let`, field, or parameter does it materialize the two-word view. This is sound because a literal's backing rodata global is always NUL-terminated at `data[len]`, exactly the guarantee `CStr` literals always relied on.

In overloaded (`defn`/multimethod) dispatch, a `StrView`-typed argument adapts to a `CStr`-typed parameter but *not* to a bare `ptr`-typed parameter — this reproduces the dispatch a `CStr` literal produced before this type existed. To bind a bounded generic (e.g. an `Eq`-bounded parameter) at `StrView` from a literal, `(import-use strview)` must be in scope so `StrView`'s protocol conformances are registered; otherwise `as` the literal to `CStr` explicitly (see `examples/cstr.nuc`). `CStr` itself is unchanged by this: it remains the dedicated FFI `char*` type, still distinct for dispatch, with only `=`/`!=` defined — no existing `:CStr`/`:ptr`-typed signature was retyped, only the literal's own inferred type and its emission changed.

**Escapes inside a literal** — `\n`, `\t`, `\r`, `\0`, `\\`, `\"`, and `\xHH`
(a raw byte, **capped at two hex digits**, unlike C's greedy `\x`) — are decoded
by the reader and apply identically to `"…"` and `c"…"`. See
[Types — String literal escapes](types.md#string-literal-escapes--n-xhh) for
the full table, the two-digit rationale, and the embedded-NUL limitation.

**`c"…"` — the explicit `CStr` literal.** A `c` glued directly onto the opening quote, with no whitespace between them, spells an explicit `CStr` literal instead of a `StrView` one: the bare `char*` GEP, no `{data,len}` view header, and no target-aware materialization. It is the direct "I mean `char*`" spelling for FFI/format-string hot spots and an honest marker at the call site — purely ergonomic, not required, since a plain `"…"` literal already coerces to `CStr`/`ptr` for free (above). A space keeps the two apart as ordinary tokens (`c "foo"` is the symbol `c` followed by a `StrView` literal); only the glued form `c"foo"` is the `CStr` literal, and only a lowercase `c` triggers it.

```lisp
(declare strlen (s:CStr) :usize)
(printf "%s\n" c"hello")             ; bare char*, no view header
(printf "%d\n" (unsafe/cast i32 (strlen c"hello")))
```

See `examples/cstr-lit-test.nuc` for the full contract, including that a plain `"…"` literal still free-coerces into the same `CStr`-typed extern with no regression.

### Construction

| Function | Signature | Description |
|----------|-----------|-------------|
| `strview` | `(data:(ptr ui8) len:usize) → StrView` | The value constructor — a view over `len` bytes at `data`, borrowed. |
| `strview-from-cstr` | `(cs:CStr) → StrView` | A `StrView` borrowing the CStr's bytes (no copy), returned **by value** — nothing is allocated and nothing needs freeing. The bytes are borrowed from `cs`, which must outlive the view. |
| `strview-to-cstr` | `(sv:(ref StrView)) → CStr` | Reinterpret `data` as a CStr. Only sound when the buffer is NUL-terminated at `data[len]` (i.e., built from a CStr or the keyword intern arena). |

```lisp
(let (sv:StrView (strview some-ptr some-len)) ...)
```

Manual construction via a struct literal is still valid, and was the only way before Stage 17 B0:
```lisp
(let ((sv (ref StrView)) (alloca StrView))
  (set! (sv 'data) some-ptr)
  (set! (sv 'len) some-len)
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
  (doseq-iter (b (addr-of it))
    (printf "%d\n" b)))
```

### Number scanning

| Function | Signature | Description |
|----------|-----------|-------------|
| `strview-parse-magnitude` | `(sv:StrView radix:i32 limit:ui64) → !ui64` | All of `sv` as an unsigned value in `radix` (2–36, digits `0-9a-zA-Z`, case-insensitive). `parse-int-error` on empty, on a byte that is not a digit of that radix, or on a magnitude above `limit`. |
| `strview-parse-sign` | `(sv:StrView out-start:ptr:usize) → i32` | 1 when `sv` begins with `-`, else 0; stores the index of the first digit (1 after a `+` or `-`, else 0). |

These are the primitives under `(parse T …)` (§7), public because two things
`FromStr` cannot express are sometimes needed: a **radix** (the protocol is keyed
only on the target type) and an explicit **limit** — which is what lets a caller
try a signed width and then retry the same digits unsigned. The limit is tested
before each multiply, so no wraparound is involved.

### Sub-slice

| Function | Signature | Description |
|----------|-----------|-------------|
| `strview-sub-bytes` | `(sv:(ref StrView) start:usize end:usize) → !StrView` | O(1) sub-slice `[start, end)`, returned **by value**. Its `data` borrows the parent's buffer; nothing is allocated. |
| `strview-take-bytes` | `(sv:StrView n:usize) → StrView` | The first `n` bytes, **unchecked**. |
| `strview-drop-bytes` | `(sv:StrView start:usize) → StrView` | The bytes from `start` on, **unchecked**. |

Errors:
- `str-index-out-of-bounds` — `start > end` or `end > len`
- `invalid-char-boundary` — `start` or `end` falls on a UTF-8 continuation byte (pattern `10xxxxxx`)

The unchecked pair carries the contract in its name: `-bytes` means the caller
already knows the index is a character boundary, which is what a scan that just
returned a delimiter position gives you. `strview-sub-bytes` is the one to reach
for otherwise; it validates both ends and returns a `!StrView`.

### Search and pattern matching

| Function | Signature | Description |
|----------|-----------|-------------|
| `strview-find` | `(sv:(ref StrView) needle:(ref StrView)) → (Maybe usize)` | First byte index of `needle` in `sv`, or `none`. Empty needle returns `(some 0)`. |
| `strview-rfind` | `(sv:(ref StrView) needle:(ref StrView)) → (Maybe usize)` | Last byte index of `needle`, or `none`. Empty needle returns `(some len)`. |
| `strview-find-byte` | `(sv:(ref StrView) b:ui8) → (Maybe usize)` | First index of byte `b`, or `none`. |
| `strview-rfind-byte` | `(sv:(ref StrView) b:ui8) → (Maybe usize)` | Last index of byte `b`, or `none`. |
| `strview-find-char` | `(sv:(ref StrView) c:Char) → (Maybe usize)` | First byte index at which `c` is encoded, or `none`. |
| `strview-rfind-char` | `(sv:(ref StrView) c:Char) → (Maybe usize)` | Last byte index at which `c` is encoded, or `none`. |
| `strview-starts-with` | `(sv:(ref StrView) prefix:(ref StrView)) → bool` | True if `sv` begins with `prefix` (byte-level). |
| `strview-ends-with` | `(sv:(ref StrView) suffix:(ref StrView)) → bool` | True if `sv` ends with `suffix` (byte-level). |
| `strview-contains-str` | `(sv:(ref StrView) needle:(ref StrView)) → bool` | True if `needle` appears anywhere in `sv`. |
| `strview-has-prefix` | `(sv:StrView prefix:StrView) → bool` | By-value `strview-starts-with`. |
| `strview-has-suffix` | `(sv:StrView suffix:StrView) → bool` | By-value `strview-ends-with`. |
| `strview-contains` | `(sv:StrView needle:StrView) → bool` | By-value `strview-contains-str`. |

**Use the by-value forms with a literal.** Address-of is lvalue-only and a string
literal is not an lvalue, so `(strview-starts-with (addr-of sv) "avr")` does not
compile — the three by-reference predicates require the pattern to be a named
local. `(strview-has-prefix sv "avr")` is the same test with the literal written
where it reads. The by-reference forms remain the right choice when the caller
already holds a `(ref StrView)`; the by-value ones delegate to them.

Returning `(Maybe usize)` is not an error — "not found" is a legitimate result, not a failure.

The codepoint searches work byte-wise: UTF-8 is self-synchronizing, so a byte-level search for a character's encoding can never match inside another character and needs no boundary check.

`strview-find` was named `strview-byte-find` before Stage 17 B0; it was renamed so it could not be misread as the single-byte `strview-find-byte` beside it.

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
| `Eq` | Byte equality: same length and identical bytes. Takes `StrView` by value. Comparing a view with `null` is a compile error — a view is never null; test the empty view with `str-empty?`. |
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
  (sub-bytes:!StrView ((self (ref Self)) start:usize end:usize))
  ((byte-find (Maybe usize)) ((self (ref Self)) (needle (ref StrView)))))
```

| Method | Description |
|--------|-------------|
| `byte-len` | Byte length. O(1) for `StrView`/`String`. |
| `byte-at` | i-th byte, O(1). Errors `str-index-out-of-bounds` when `i ≥ byte-len`. |
| `bytes` | Fresh byte iterator by value (associated type `ByteI`). Drive with `(addr-of it)` + `next`. |
| `as-view` | Borrow entire content as a `StrView` (two-word value, no copy). The bridge to all StrView helpers. |
| `sub-bytes` | Sub-slice `[start, end)` as a borrowed `!StrView` (by value). See §3 for error conditions. |
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
| `string-as-cstr` | `(self:(ref String)) → CStr` | NUL-terminated view for an FFI seam. Writes the NUL *past* `len` without counting it, so the `String` is otherwise unchanged and repeated calls are free. Invalidated by any later append. |

### Mutation

| Function | Signature | Description |
|----------|-----------|-------------|
| `string-push-char` | `(self:(ref String) c:Char) → void` | Append a single `Char`. Always valid UTF-8 by construction. |
| `string-push-str` | `(self:(ref String) s:(ref StrView)) → !void` | Append a `StrView`'s bytes, validating UTF-8 first. Errors `invalid-utf8`. |
| `string-push-str-unchecked` | `(self:(ref String) s:(ref StrView)) → void` | Append a `StrView`'s bytes with no UTF-8 check. The caller asserts validity. |
| `string-pop-char` | `(self:(ref String)) → (Maybe Char)` | Remove and return the last codepoint, or `none` if empty. |
| `string-clear` | `(self:(ref String)) → void` | Set `len` to 0 (retain capacity). |
| `string-truncate` | `(self:(ref String) byte-len:usize) → !void` | Truncate to `byte-len` bytes. Errors `str-index-out-of-bounds` if `byte-len > len`; errors `invalid-char-boundary` if `byte-len` falls mid-codepoint. |
| `string-truncate-unchecked` | `(self:(ref String) byte-len:usize) → void` | Rewind to a length the caller already knows is a codepoint boundary — typically a mark taken from `byte-len` before appending. Only ever shrinks; a `byte-len` at or past the current length does nothing. Use it for a `String` kept as a reusable scratch buffer, where the checked form's validation and `!void` are both dead weight; use `string-truncate` for a `String` being built as a value. |
| `string-reserve` | `(self:(ref String) extra:usize) → void` | Ensure at least `extra` additional bytes of capacity beyond current length. |
| `string-shrink-to-fit` | `(self:(ref String)) → void` | Shrink capacity to match `len`. Reallocates or frees if `len = 0`. |

`string-push-str` validates because `String` is the UTF-8-guaranteed type and `StrView` is a byte slice; `string-push-str-unchecked` is the path for bytes whose producer already knows they are valid, mirroring `string-from-cstr-unchecked`. Both append with a single `memcpy`.

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

(defn main ():i32
  (with (s:String (string-new))
    (string-push-char (addr-of s) \H)
    (string-push-char (addr-of s) \i)
    (let (sv:StrView (string-as-view (addr-of s)))
      (printf "%.*s\n" (unsafe/cast i32 (sv 'len)) (sv 'data))))
  0)
```

---

## §6 — Split, lines, and trim

`(import-use string-split)` — requires `(import-use strview)` (transitively satisfied).

Lazy splitting with no allocation — iterators hold raw pointers into the source `StrView`. The source must remain alive for the iterator's lifetime.

### `strview-split`

```lisp
(defn strview-split ((sv (ref StrView)) (sep (ref StrView))):SplitIter)
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
(defn strview-lines ((sv (ref StrView))):LineIter)
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
        (printf "%.*s\n" (unsafe/cast i32 (seg 'len)) (seg 'data))))))
```

### `Iterator` conformance (Stage 13 R1, Stage 17 A3)

`SplitIter` and `LineIter` conform to `(Iterator StrView)`, so `reduce` /
`doseq-iter` / `match` drive them directly and `next` yields
`(Maybe StrView)` — each segment by value:

```lisp
(let (it:SplitIter (strview-split sv sep))
  (doseq-iter (seg (addr-of it))
    (printf "%.*s\n" (unsafe/cast i32 (seg 'len)) (seg 'data))))
```

Before Stage 17 A3 they conformed to `(Iterator ptr)`, yielding a pointer into
a `cur` scratch field, because `(Maybe StrView)` was believed uncompilable in
the macro-expansion JIT module. It compiles; the scratch field, the niche
encoding and the `doseq-split` macro that decoded it are all gone. `seg` is now
a value, so a function taking `(ref StrView)` needs `(addr-of seg)`.

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
| `ui64` | `!ui64` | `(import-use parse)` |
| `f64` | `!f64` | `(import-use parse)` |

### `parse` macro

```lisp
(defmacro parse (ty sv)
  `(from-str (unsafe/cast ~ty 0) ~sv))
```

`(parse T sv)` expands to `(from-str (unsafe/cast T 0) sv)`. The `(unsafe/cast T 0)` provides a phantom zero value of the target type to select the right conformer — `unsafe/cast` is required here (not `as`) because `T` may bind to a float type, and `int`→`float` is never in `as`'s safe set even for a representable literal like `0`.

```lisp
(parse i32 sv)   ; → !i32
(parse i64 sv)   ; → !i64
(parse ui64 sv)  ; → !ui64
(parse f64 sv)   ; → !f64
```

### Parsing semantics

All four conformances are **strict**:
- Empty input, or a sign with no digits → error
- Leading whitespace → error (unlike libc `strtol`, which skips it). No special
  case is needed for this: a space is not a digit.
- All bytes must be consumed; trailing non-numeric characters → error
- Overflow → `parse-int-error`, at every width. The integer conformances walk the
  digits through `strview-parse-magnitude` (§3) rather than delegating to libc,
  and the range that admits `-9223372036854775808` correctly rejects
  `+9223372036854775808`.
- `ui64` refuses a leading `-` rather than wrapping it: the point of the unsigned
  conformance is the range above `i64`, where a negative is a user error and not
  a bit pattern.
- `f64`: delegates to `strtod`; zero bytes consumed → `parse-float-error`;
  trailing garbage → `parse-float-error`

Before Stage 17, `(parse i64 "99999999999999999999")` returned
`(ok 9223372036854775807)`: `strtoll` clamps and reports the overflow only
through `errno`, which the consumed-bytes check cannot see.

```lisp
(import-use parse)

(defn main ():i32
  (let ((sv (ref StrView)) (alloca StrView))
    (set! (sv 'data) (as ptr:ui8 (as ptr "42")))
    (set! (sv 'len) 2)
    (match (parse i32 sv)
      ((ok n)  (printf "parsed: %d\n" n))
      ((err e) (printf "error: %s\n" (err-name e)))))
  0)
```

---

## §8 — Error codes

All string-related error codes (defined in `lib/string-errors.nuc`, except
`parse-float-error` in `lib/parse.nuc`):

| Error code | Message | Raised by |
|------------|---------|-----------|
| `str-index-out-of-bounds` | `"string index out of bounds"` | `byte-at`, `char-at`, `sub-bytes`, `string-truncate` |
| `invalid-char-boundary` | `"byte offset is not a UTF-8 codepoint boundary"` | `sub-bytes`, `string-truncate` |
| `invalid-utf8` | `"bytes are not valid UTF-8"` | `string-from-cstr`, `string-from-view`, `string-push-str` |
| `invalid-codepoint` | `"value is not a Unicode scalar value"` | `char-from-u32` |
| `parse-int-error` | `"invalid integer"` | `strview-parse-magnitude`, and so `(parse i32 …)` / `(parse i64 …)` / `(parse ui64 …)` |
| `parse-float-error` | `"invalid float"` | `(parse f64 …)` |
| `io-write-failed` | `"write failed"` | `write-str` on a `CFile`/`FdOut`/`File`, `file-close` |
| `io-open-failed` | `"cannot open file"` | `file-open-read`, `file-create`, `file-open-append` |
| `io-read-failed` | `"read failed"` | `file-read-to-string` |

All of these conform to the `Err` type and are usable with `(err-name e)`, `try`, `with-handler`, and `match`. See [Error handling](errors.md).

---

## §9 — Formatting (`lib/fmt.nuc`, Stage 17)

`(import-use fmt)`. Two protocols and three macros; there is **no format
string**. Arity and argument types are settled at macro expansion, so a
mismatch is a compile error rather than a runtime misread.

### `Writer` — an output sink

```lisp
(defprotocol Writer
  (write-str ((self (ref Self)) s:StrView):!void))
```

Single-method, so it can be erased as `(dyn Writer)` and stored in a global.
`s` is by value — it is not `Self`, so the `(ref StrView)` convention of
[§4](#4--bytestr-and-str-protocols) does not reach it, and a literal or a
producer's result can be the argument directly.

| Conformer | Behaviour |
|-----------|-----------|
| `String` | appends (unchecked — the bytes came from a `ToStr` or a literal) |
| `CFile` | `fwrite` to a C `FILE*`; `(err io-write-failed)` on a short write |

`(cfile f)` wraps a `FILE*`. It exists so a stream global can become a
`(dyn Writer)` before its `fprintf` call sites convert; new code should not
target it.

### `ToStr` — a value's text

```lisp
(defprotocol ToStr
  (to-str ((self Self) (out (ref String))):!void))
```

The receiver is **by value**, which is what lets a literal be an argument:
`(to-str 42 out)` works, where a `(ref Self)` receiver would make the literal
an rvalue with no address to take. Conformers: `i64`, `i32`, `usize`, `ui64`,
`StrView`, `CStr`, `Char`, `bool`, `f64`, `f32`.

`String` deliberately does **not** conform — by value would be a move. Write it
through `(string-as-view s)`, which is O(1).

Integers are formatted natively (`string-push-i64` / `string-push-u64`, also
public). Floats delegate to `snprintf` — `%.17g` for `f64`, `%.9g` for `f32` —
permanently and deliberately; shortest-round-trip float printing is a separate
algorithm and the interface is native either way.

### `str-into`, `str`, `str-alloc`

```lisp
(str-into out "expected " n " args, got " m)   ; append into an existing String
(str      "expected " n " args, got " m)       ; build a new String
(str-alloc h "expected " n " args, got " m)    ; …over an explicit AllocHandle
```

Each argument is expanded to a `(to-str <arg> out)` call, so any `ToStr`
conformer may appear in any position and the pieces are heterogeneous by
construction. `out` is evaluated once per piece, so it must be a plain binding.
Zero arguments and one argument both expand.

```lisp
(let (s:String (str "x=" 42 " y=" 1.5 " ok=" true))
  (printf "%s\n" (string-as-cstr &s)))          ; x=42 y=1.5 ok=true
```

See `examples/fmt-test.nuc`.

---

## Gotchas and constraints

- **`?` in function names.** Classification functions use `char-is-ascii` etc. without a `?` suffix. This is a convention of this library only — `?` and `!` are legal in every name position and are mangled to `_QMARK`/`_BANG` in the emitted symbol (see [`?`/`!` in names](generics.md#polymorphism-overloaded-defn-multimethods)).
- **`string-as-cstr` writes into the String.** It appends a NUL *past* `len` (reserving if needed) without counting it, so the String is unchanged for every other operation and repeated calls are free — but the returned `CStr` is invalidated by any subsequent append.
- **`sub-bytes` and `strview-from-cstr` return by value.** Both returned heap-allocated `ptr:StrView` wrappers before Stage 17 A2, when returning a struct payload through `!T` was believed impossible; it is not. Neither allocates now, and neither needs freeing. Their `data` still borrows the source buffer, which must outlive the view.
- **`SplitIter`/`LineIter` yield segments by value.** They conform to `(Iterator StrView)` since Stage 17 A3, so `doseq-iter` binds each segment as a `StrView` value — pass `(addr-of seg)` to anything taking `(ref StrView)`. The `*-iter-done`/`*-iter-next` pair is still available.
- **`string-new-alloc` takes `(ref AllocHandle)`.** It copies the handle in; the caller retains ownership of the original.
- **`CharIter` is lossless but substitutes U+FFFD.** Invalid UTF-8 bytes are never skipped silently — iteration always advances by at least one byte. Invalid bytes produce U+FFFD (the Unicode replacement character) as the yield value rather than an error, so iterating over a `CharIter` always terminates without an error path.
- **Borrow lifetimes are unchecked.** `ByteIter`, `CharIter`, `SplitIter`, `LineIter`, and sub-views returned by `strview-sub-bytes` all hold raw pointers into their source buffer. There is no compile-time lifetime enforcement — the caller is responsible for keeping the source alive.
- **A materialized `StrView` at a C variadic call site contributes only its `data` pointer.** Passing a `StrView` value (not a fixed parameter) to a variadic function such as `printf` (`%s`) passes just the `char*`, never the `{data,len}` pair as two variadic slots — otherwise the carried length would occupy an extra vararg slot and shift every later argument's conversion. A *fixed* (non-variadic) `StrView` by-value parameter is unaffected and still receives the full two-eightbyte struct per the platform ABI. See `examples/strview-vararg-test.nuc`.
- **Coercing a `StrView` to `CStr`/`ptr` (implicitly, or via `as`/`unsafe/cast`) always takes just `data`, unconditionally** — the same trust `strview-to-cstr` above requires: sound only when the view's buffer is actually NUL-terminated at `data[len]`. A string literal and a view built from a `CStr` satisfy this; an arbitrary sub-slice from `strview-sub-bytes` may not.
- **String literals meeting at a branch decide by their destination, not by each other.** `(if c "one" "two")` yields `CStr` — the two literals collapse to bare pointers so the phi stays pointer-shaped — *unless* the branch is known to feed a `StrView` slot (an explicit or implicit `return` from a `StrView` function, or any position whose target type is armed), in which case each arm materializes its own `{data,len}` and the phi carries the view. The same rule covers `cond` and `match` arms. Where no target type is in view — a `let` with no declared type, say — the result is still `CStr`; spell the binding `sv:StrView` to get a view.
- **A string literal inside a collection literal is a `StrView`.** `#{"a" "b"}` is a `(HashSet StrView)` and `{"foo" 42}` a `(HashMap StrView i32)` — the same type `"…"` has everywhere else. A container declared `(HashSet CStr)` is unaffected: the literal still free-coerces at `insert`/`contains?`, so only the *inferred* element type changed. `StrView`'s `Hash` conformance is in `lib/hash.nuc` beside `CStr`'s, so a string-keyed container needs no import beyond the collection's.
- **A quoted `c"…"` inside a macro `quasiquote` does not carry its `CStr` marker.** Quoting deliberately does not preserve the flag through expansion, so a quoted `c"…"` reads back as a plain `StrView` literal at the macro's output site. Write the `c"…"` literal directly in code (outside a quasiquote) when the explicit `CStr` spelling matters.
