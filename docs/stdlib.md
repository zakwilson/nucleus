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
| `strview` | `((data (ptr ui8)) len:usize) -> StrView` | The value constructor: a view over `len` bytes at `data`, borrowed. |
| `strview-from-cstr` | `((cs CStr)) -> StrView` | A `StrView` borrowing `cs`'s bytes, returned **by value** — nothing is allocated and nothing needs freeing. `len` is `strlen(cs)`. The C string must outlive the view. |
| `strview-to-cstr` | `((sv (ref StrView))) -> CStr` | Reinterpret the view's bytes as a `CStr`. **Only sound when the underlying buffer is NUL-terminated at `data[len]`** — guaranteed for views built from C strings and for keyword names, but not for arbitrary sub-slices. |
| `strview-byte-len` | `((sv (ref StrView))) -> usize` | Byte length of the view. |
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
  ; strview-from-cstr returns by value and allocates nothing; the
  ; (ref StrView)-taking helpers are reached through `&`.
  (let (av:StrView (strview-from-cstr "hello")
        bv:StrView (strview-from-cstr "hello")
        cv:StrView (strview-from-cstr "world")
        a:ptr:StrView &av
        b:ptr:StrView &bv
        c:ptr:StrView &cv)
    (printf "len=%llu\n"  (as ui64 (strview-byte-len a)))  ; 5
    (printf "a=b? %d\n"   (strview-eq a b))              ; 1
    (printf "a=c? %d\n"   (strview-eq a c))              ; 0
    (printf "cstr=%s\n"   (strview-to-cstr a)))          ; hello
  (return 0))
```

See `examples/strview-test.nuc` for a complete runnable example.

---

## `Symbol` (`lib/intern.nuc`, Stage 17)

`(import-use intern)` provides an interned name whose identity is a pointer.

```lisp
(defstruct Symbol p:(ptr ui8))
```

One word. The interner allocates `[hash:usize][len:usize][bytes…][NUL]` and the
`Symbol` holds the address of the first **byte**, not of the header — which is
what buys all four properties at once:

- `=` is one `icmp eq ptr`.
- `symbol-len` and `hash` are O(1) loads behind the pointer.
- `symbol-as-view` is `{p, len}` — no allocation.
- `symbol-as-cstr` is free: the bytes are still NUL-terminated, so an FFI seam
  takes a `Symbol` with no copy.

The intern table is open-addressed with linear probing, grows at 3/4 load, and
has no cap. It is not a `HashMap` — a `HashMap`'s keys want to be interned, so
building the interner on one would be circular.

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `symbol-intern` | `((sv (ref StrView))) -> Symbol` | The canonical `Symbol` for these bytes. |
| `symbol-intern` | `(sv:StrView) -> Symbol` | The by-value overload, for a literal or an `fstr` result. |
| `symbol-intern-bytes` | `(src:(ptr ui8) n:usize) -> Symbol` | Same, from a pointer and a length. |
| `symbol-from-cstr` | `((cs CStr)) -> Symbol` | Same, from a C string. |
| `symbol-from-cstr-unchecked` | `((cs CStr)) -> Symbol` | The inverse of `symbol-as-cstr`, for a `Symbol` parked in a pointer-shaped slot. Unchecked: nothing in the type says the pointer came from the interner. |
| `symbol-len` | `(self:Symbol) -> usize` | Byte length, from the header. |
| `symbol-cached-hash` | `(self:Symbol) -> usize` | The hash computed once at intern time. |
| `symbol-as-view` | `(self:Symbol) -> StrView` | Borrowed view; process-lived. |
| `symbol-as-cstr` | `(self:Symbol) -> CStr` | Borrowed C string; no copy. |
| `symbol-is` | `(self:Symbol other:StrView) -> bool` | Same bytes as the view? Cached length, then `memcmp`. |
| `symbol-contains-byte` | `(self:Symbol b:i32) -> bool` | Does the name contain this byte (`:`, `/`)? |
| `symbol-byte-at` | `(self:Symbol i:usize) -> i32` | The `i`th byte, unchecked. Index `len` reads the interner's own NUL. |
| `symbol-none?` | `(self:Symbol) -> bool` | Is this the zero `Symbol` — "no name"? |
| `symbol-none` | `() -> Symbol` | The zero `Symbol` itself, for writing "no name". |
| `symbol-count` | `() -> usize` | How many distinct names are interned. |

A `Symbol` is never *constructed* null: `p` is a non-null pointer type, so there
is no null to assign. A zeroed struct reads back as one, though — an arena `Node`
that is an `INT` or a `CELL` has no name — so a cell is allocated with `calloc`
and tested with `symbol-none?`. Where the absent case has to be *written* rather
than only recognised — an out-parameter a parser leaves unset, a struct field
that means "no annotation" — `symbol-none` mints it.

`=` and `!=` are overloaded for `(Symbol, Symbol)` — pointer identity — and for
`(Symbol, StrView)`, which is `symbol-is`. Interning is what makes those one
predicate. A spelling test is almost always against a **literal**, which has no
interned pointer to compare with, so `(= (n 's) "defstruct")` is the idiom;
interning the literal to get a pointer would cost a hash to save a four-byte
`memcmp`.

`Symbol` conforms to `Eq` (pointer identity), `Hash` (the cached hash), `ToStr`,
`ByteStr`, and `Str` — the last two through `as-view`, so every string method
works on a `Symbol` at no allocation. The conformance *records* and every text
method live in `lib/intern-str.nuc`; `(import-use intern-str)` is what a program
that formats or slices a `Symbol` needs.

`lib/intern.nuc` itself imports nothing but `lib/fnv.nuc` and libc, on purpose:
`lib/node.nuc` delegates the compiler's symbol table to it, and `node` is what
every macro-using program imports. `hash`, `numeric` and `strview` all reach an
`f64` annotation, which AVR rejects outright — importing any of them here would
make every macro-using program un-compilable for an 8-bit target.

See `examples/intern-test.nuc`, and `tests/fixtures/s17-intern-bench.nuc` for the
benchmark against the compiler's own interner.

---

## `Keyword` (`lib/keyword.nuc`, Stage 11; rebased Stage 17)

`(import-use keyword)` provides interned, self-evaluating keyword values. Requires `(import-use strview)`, `(import-use hash)`, `(import-use numeric)`, and `(import-use intern)`.

```lisp
(defstruct Keyword sym:Symbol)
```

A keyword is exactly one interned `Symbol`. Keywords are constructed exclusively by the compiler from `:foo` reader literals, which lower to `(keyword-intern "foo")`. Two keywords with the same spelling share a `Symbol`, so equality is a pointer compare and hashing is a single cached load — no byte walk at either operation.

Before Stage 17 this file carried its own intern pool: a fixed 256-entry array with a linear scan and a `strcmp` per probe, which capped a program's distinct keyword set and aborted past it. Both the cap and the scan are gone.

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `keyword-intern` | `(sv:StrView) -> Keyword` | Look up or insert `sv` and return the canonical `Keyword`. Called implicitly by the compiler for each `:foo` literal; direct calls are valid but unusual. |
| `keyword-name` | `(self:Keyword) -> StrView` | The keyword's name, borrowed (process-lived; do not free). |
| `keyword-symbol` | `(self:Keyword) -> Symbol` | The underlying interned `Symbol`. |

### Protocol conformances

`Keyword` conforms to `Eq` (by value, identity — compares the `Symbol` pointer), `Hash` (by `(ref Self)`, the `Symbol`'s cached hash), and `ToStr`. The first two satisfy the `K: Hash + Eq` requirement for `HashMap` and `HashSet`.

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
  (let (k:Keyword :hello
        nm:StrView (keyword-name k))
    (printf "name=%s\n" (strview-to-cstr &nm))) ; hello
  (return 0))
```

See `examples/keyword-test.nuc` for a HashMap usage example. See [Keyword literals](types.md#keyword-literals----foo) for the full semantics and syntax disambiguation rules.
