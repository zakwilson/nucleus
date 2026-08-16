# Nucleus Standard Library Bindings

C standard library functions callable without any explicit `(import-use ...)`
in your own program. Nothing is "registered at compiler startup" — `lib/
prelude.nuc` (auto-imported into every program unless it starts with
`(exclude-prelude)`) directly `(import-use "string.h")`s, and transitively,
via `(import-use node)` -> `lib/node.nuc` -> `lib/arena.nuc`, also
`(import-use "stdio.h")` and `(import-use "stdlib.h")`. Each is an ordinary C
header import (`context/build.md`'s "Import system": `clang -E -x c -include
<hdr> /dev/null`, parsed the same way as any `(import "foo.h")` you write
yourself), so **the available set is exactly whatever your build host's C
library exposes through those three headers — host- and libc-dependent**
(glibc and musl differ; see `context/build.md`'s musl note), not a fixed list.

The table below is therefore **generated, not hand-curated**: `scripts/
gen-stdlib-table.py` compiles a one-line probe for each candidate name against
`build/nucleusc` and keeps only the ones that actually resolve. Regenerate it
after a toolchain/libc change (or whenever you doubt it) with:

```
python3 scripts/gen-stdlib-table.py
```

`make test` (via the `stdlib-table-generated` check) fails if a name below no
longer resolves on the host running the suite; see the script's module
docstring for the exact (deliberately host-tolerant) pass/fail rule.

<!-- BEGIN GENERATED: availability (scripts/gen-stdlib-table.py) -->

## stdlib

| Function | Signature | C Header |
|----------|-----------|----------|
| `alloca` | `(i64) -> ptr` | `<stdlib.h>` |

## string

| Function | Signature | C Header |
|----------|-----------|----------|
| `bcmp` | `(ptr, ptr, i64) -> i32` | `<string.h>` |
| `bcopy` | `(ptr, ptr, i64) -> void` | `<string.h>` |
| `bzero` | `(ptr, i64) -> void` | `<string.h>` |
| `explicit_bzero` | `(ptr, i64) -> void` | `<string.h>` |
| `ffs` | `(i32) -> i32` | `<string.h>` |
| `ffsl` | `(i64) -> i32` | `<string.h>` |
| `ffsll` | `(i64) -> i32` | `<string.h>` |
| `index` | `(ptr, i32) -> ptr` | `<string.h>` |
| `memccpy` | `(ptr, ptr, i32, i64) -> ptr` | `<string.h>` |
| `memchr` | `(ptr, i32, i64) -> ptr` | `<string.h>` |
| `memcmp` | `(ptr, ptr, i64) -> i32` | `<string.h>` |
| `memcpy` | `(ptr, ptr, i64) -> ptr` | `<string.h>` |
| `memmem` | `(ptr, i64, ptr, i64) -> ptr` | `<string.h>` |
| `memmove` | `(ptr, ptr, i64) -> ptr` | `<string.h>` |
| `mempcpy` | `(ptr, ptr, i64) -> ptr` | `<string.h>` |
| `memset` | `(ptr, i32, i64) -> ptr` | `<string.h>` |
| `rindex` | `(ptr, i32) -> ptr` | `<string.h>` |
| `stpcpy` | `(ptr, ptr) -> ptr` | `<string.h>` |
| `stpncpy` | `(ptr, ptr, i64) -> ptr` | `<string.h>` |
| `strcasecmp` | `(ptr, ptr) -> i32` | `<string.h>` |
| `strcasecmp_l` | `(ptr, ptr, ptr) -> i32` | `<string.h>` |
| `strcasestr` | `(ptr, ptr) -> ptr` | `<string.h>` |
| `strcat` | `(ptr, ptr) -> ptr` | `<string.h>` |
| `strchr` | `(ptr, i32) -> ptr` | `<string.h>` |
| `strchrnul` | `(ptr, i32) -> ptr` | `<string.h>` |
| `strcmp` | `(ptr, ptr) -> i32` | `<string.h>` |
| `strcoll` | `(ptr, ptr) -> i32` | `<string.h>` |
| `strcoll_l` | `(ptr, ptr, ptr) -> i32` | `<string.h>` |
| `strcpy` | `(ptr, ptr) -> ptr` | `<string.h>` |
| `strcspn` | `(ptr, ptr) -> i64` | `<string.h>` |
| `strdup` | `(ptr) -> ptr` | `<string.h>` |
| `strerror` | `(i32) -> ptr` | `<string.h>` |
| `strerror_l` | `(i32, ptr) -> ptr` | `<string.h>` |
| `strerror_r` | `(i32, ptr, i64) -> i32` | `<string.h>` |
| `strlcat` | `(ptr, ptr, i64) -> i64` | `<string.h>` |
| `strlcpy` | `(ptr, ptr, i64) -> i64` | `<string.h>` |
| `strlen` | `(ptr) -> i64` | `<string.h>` |
| `strncasecmp` | `(ptr, ptr, i64) -> i32` | `<string.h>` |
| `strncasecmp_l` | `(ptr, ptr, i64, ptr) -> i32` | `<string.h>` |
| `strncat` | `(ptr, ptr, i64) -> ptr` | `<string.h>` |
| `strncmp` | `(ptr, ptr, i64) -> i32` | `<string.h>` |
| `strncpy` | `(ptr, ptr, i64) -> ptr` | `<string.h>` |
| `strndup` | `(ptr, i64) -> ptr` | `<string.h>` |
| `strnlen` | `(ptr, i64) -> i64` | `<string.h>` |
| `strpbrk` | `(ptr, ptr) -> ptr` | `<string.h>` |
| `strrchr` | `(ptr, i32) -> ptr` | `<string.h>` |
| `strsep` | `(ptr, ptr) -> ptr` | `<string.h>` |
| `strsignal` | `(i32) -> ptr` | `<string.h>` |
| `strspn` | `(ptr, ptr) -> i64` | `<string.h>` |
| `strstr` | `(ptr, ptr) -> ptr` | `<string.h>` |
| `strtok` | `(ptr, ptr) -> ptr` | `<string.h>` |
| `strtok_r` | `(ptr, ptr, ptr) -> ptr` | `<string.h>` |
| `strxfrm` | `(ptr, ptr, i64) -> i64` | `<string.h>` |
| `strxfrm_l` | `(ptr, ptr, i64, ptr) -> i64` | `<string.h>` |

<!-- END GENERATED -->



---

## `StrView` (`lib/strview.nuc`, Stage 11)

`(import-use strview)` provides an immutable, non-owning, length-prefixed UTF-8 byte slice. `StrView` is the shared substrate underneath `Keyword` and `String`. It deliberately has no ownership, growth, mutation, or UTF-8/codepoint layer — those belong to `String`. For a full reference covering `Char`, `StrView`, `String`, split, lines, trim, and parse, see [Strings](strings.md).

```lisp
(defstruct StrView
  data:(ptr ui8)
  len:usize)
```

`data` points to the first byte of the underlying buffer. `len` is authoritative; the buffer is **not** NUL-terminated (except when built from a C string, in which case `strview-to-cstr` is sound). Copying a `StrView` copies two words and borrows the bytes — it frees nothing. There is no `Drop` conformance.

The bare struct type is registered in the prelude and so is available everywhere without an import; the functions and conformances below still require `(import-use strview)` (plus `(import-use hash)` and `(import-use numeric)`, both transitively needed for `Hash`/`Eq`).

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

(defn main ():i32
  (let (a:ptr:StrView (strview-from-cstr "hello")
        b:ptr:StrView (strview-from-cstr "hello")
        c:ptr:StrView (strview-from-cstr "world"))
    (printf "len=%llu\n"  (as ui64 (strview-len a)))  ; 5
    (printf "a=b? %d\n"   (strview-eq a b))              ; 1
    (printf "a=c? %d\n"   (strview-eq a c))              ; 0
    (printf "cstr=%s\n"   (strview-to-cstr a))           ; hello
    (free (as ptr a)) (free (as ptr b)) (free (as ptr c)))
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

(defn main ():i32
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
