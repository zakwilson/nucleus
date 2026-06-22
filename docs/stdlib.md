# Nucleus Standard Library Bindings

Pre-declared C standard library functions, available without `extern`. These are registered at compiler startup, so no `(import-use ...)` is needed to call them.

## stdio

| Function | Signature | C Header |
|----------|-----------|----------|
| `printf` | `(ptr, ...) -> i32` | `<stdio.h>` |
| `fprintf` | `(ptr, ptr, ...) -> i32` | `<stdio.h>` |
| `snprintf` | `(ptr, i64, ptr, ...) -> i32` | `<stdio.h>` |
| `fputc` | `(i32, ptr) -> i32` | `<stdio.h>` |
| `fputs` | `(ptr, ptr) -> i32` | `<stdio.h>` |
| `fopen` | `(ptr, ptr) -> ptr` | `<stdio.h>` |
| `fclose` | `(ptr) -> i32` | `<stdio.h>` |
| `fread` | `(ptr, i64, i64, ptr) -> i64` | `<stdio.h>` |
| `fwrite` | `(ptr, i64, i64, ptr) -> i64` | `<stdio.h>` |
| `fseek` | `(ptr, i64, i32) -> i32` | `<stdio.h>` |
| `ftell` | `(ptr) -> i64` | `<stdio.h>` |
| `rewind` | `(ptr) -> void` | `<stdio.h>` |
| `perror` | `(ptr) -> void` | `<stdio.h>` |
| `open_memstream` | `(ptr, ptr) -> ptr` | `<stdio.h>` |
| `fflush` | `(ptr) -> i32` | `<stdio.h>` |
| `fgets` | `(ptr, i32, ptr) -> ptr` | `<stdio.h>` |

## stdlib

| Function | Signature | C Header |
|----------|-----------|----------|
| `malloc` | `(i64) -> ptr` | `<stdlib.h>` |
| `realloc` | `(ptr, i64) -> ptr` | `<stdlib.h>` |
| `free` | `(ptr) -> void` | `<stdlib.h>` |
| `exit` | `(i32) -> void` | `<stdlib.h>` |
| `strtol` | `(ptr, ptr, i32) -> i64` | `<stdlib.h>` |

## string

| Function | Signature | C Header |
|----------|-----------|----------|
| `memcpy` | `(ptr, ptr, i64) -> ptr` | `<string.h>` |
| `memset` | `(ptr, i32, i64) -> ptr` | `<string.h>` |
| `memcmp` | `(ptr, ptr, i64) -> i32` | `<string.h>` |
| `strlen` | `(ptr) -> i64` | `<string.h>` |
| `strcmp` | `(ptr, ptr) -> i32` | `<string.h>` |
| `strncmp` | `(ptr, ptr, i64) -> i32` | `<string.h>` |
| `strchr` | `(ptr, i32) -> ptr` | `<string.h>` |
| `strndup` | `(ptr, i64) -> ptr` | `<string.h>` |

## ctype

| Function | Signature | C Header |
|----------|-----------|----------|
| `isspace` | `(i32) -> i32` | `<ctype.h>` |
| `isdigit` | `(i32) -> i32` | `<ctype.h>` |

## unistd

| Function | Signature | C Header |
|----------|-----------|----------|
| `dup` | `(i32) -> i32` | `<unistd.h>` |
| `dup2` | `(i32, i32) -> i32` | `<unistd.h>` |
| `close` | `(i32) -> i32` | `<unistd.h>` |

---

## `StrView` (`lib/strview.nuc`, Stage 11)

`(import-use strview)` provides an immutable, non-owning, length-prefixed UTF-8 byte slice. `StrView` is the shared substrate underneath `Keyword` and `String`. It deliberately has no ownership, growth, mutation, or UTF-8/codepoint layer — those belong to `String`. For a full reference covering `Char`, `StrView`, `String`, split, lines, trim, and parse, see [Strings](strings.md).

```lisp
(defstruct StrView
  data:(ptr ui8)
  len:usize)
```

`data` points to the first byte of the underlying buffer. `len` is authoritative; the buffer is **not** NUL-terminated (except when built from a C string, in which case `strview-to-cstr` is sound). Copying a `StrView` copies two words and borrows the bytes — it frees nothing. There is no `Drop` conformance.

Also requires `(import-use hash)` and `(import-use numeric)` (both transitively needed for `Hash`/`Eq` conformances).

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `strview-from-cstr` | `((cs CStr)) -> (ptr StrView)` | Heap-allocate a `StrView` that borrows `cs`'s bytes. `len` is `strlen(cs)`. The caller owns the returned pointer (free with libc `free`). The C string must outlive the view. |
| `strview-to-cstr` | `((sv (ref StrView))) -> CStr` | Reinterpret the view's bytes as a `CStr`. **Only sound when the underlying buffer is NUL-terminated at `data[len]`** — guaranteed for views built from C strings and for keyword names, but not for arbitrary sub-slices. |
| `strview-len` | `((sv (ref StrView))) -> usize` | Byte length of the view. |
| `strview-eq` | `((a (ref StrView)) (b (ref StrView))) -> i32` | Returns `1` if both views have equal length and identical bytes (`memcmp`), `0` otherwise. |
| `strview-hash` | `((sv (ref StrView))) -> usize` | FNV-1a fold over exactly `len` bytes (same algorithm and offset basis as `lib/hash.nuc`'s scalar/`CStr` conformances). Handles embedded NULs. |

### Protocol conformances

`StrView` conforms to `Hash` (by `(ref Self)`) and `Eq` (by value). The `Eq` conformance uses `strview-eq` internally; `=` and `!=` on two `StrView` values are content equality (same bytes), not pointer identity.

### Example

```lisp
(import-use "stdio.h")
(import-use "stdlib.h")
(import-use strview)
(import-use hash)

(defn main:i32 ()
  (let (a:ptr:StrView (strview-from-cstr "hello")
        b:ptr:StrView (strview-from-cstr "hello")
        c:ptr:StrView (strview-from-cstr "world"))
    (printf "len=%llu\n"  (cast ui64 (strview-len a)))  ; 5
    (printf "a=b? %d\n"   (strview-eq a b))              ; 1
    (printf "a=c? %d\n"   (strview-eq a c))              ; 0
    (printf "cstr=%s\n"   (strview-to-cstr a))           ; hello
    (free (cast ptr a)) (free (cast ptr b)) (free (cast ptr c)))
  (return 0))
```

See `examples/strview-test.nuc` for a complete runnable example.

---

## `Keyword` (`lib/keyword.nuc`, Stage 11)

`(import-use keyword)` provides interned, self-evaluating keyword values. Requires `(import-use strview)`, `(import-use hash)`, and `(import-use numeric)`.

```lisp
(defstruct Keyword
  name:(ptr StrView)
  id:usize
  cached-hash:usize)
```

Keywords are constructed exclusively by the compiler from `:foo` reader literals, which lower to `(keyword-intern "foo")`. Two keywords with the same spelling share an `id`; equality is an integer compare and hashing is a single cached load — no byte walk at either operation.

The intern pool is a fixed-size global array (capacity 256). It is lazily initialised on first use. Overflow aborts with a diagnostic message and `exit(1)`.

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `keyword-intern` | `((cs CStr)) -> Keyword` | Look up or insert `cs` in the intern pool and return the canonical `Keyword`. Called implicitly by the compiler for each `:foo` literal; direct calls are valid but unusual. |
| `keyword-name` | `((self (ref Keyword))) -> ref:StrView` | Return the keyword's name as a borrowed `StrView` (process-lived; do not free). |

### Protocol conformances

`Keyword` conforms to `Eq` (by value, identity — compares `id`) and `Hash` (by `(ref Self)`, returns `cached-hash`). These conformances satisfy the `K: Hash + Eq` requirement for `HashMap` and `HashSet`.

### Usage

Keywords are written as `:identifier` in source. The compiler requires `(import-use keyword)` (plus its transitive imports) at the use site; without it the compiler errors with `undefined: keyword-intern`.

```lisp
(import-use "stdio.h")
(import-use strview)
(import-use hash)
(import-use keyword)

(defn main:i32 ()
  ; Self-evaluation and identity equality.
  (printf "foo=foo? %d\n" (if (= :foo :foo) 1 0))   ; 1
  (printf "foo=bar? %d\n" (if (= :foo :bar) 1 0))   ; 0
  (printf "foo!=bar? %d\n" (if (!= :foo :bar) 1 0)) ; 1

  ; Inspect the keyword name.
  (let (k:Keyword :hello)
    (printf "name=%s\n" (strview-to-cstr (keyword-name (addr-of k))))) ; hello
  (return 0))
```

See `examples/keyword-test.nuc` for a HashMap usage example. See [Keyword literals](types.md#keyword-literals----foo) for the full semantics and syntax disambiguation rules.
