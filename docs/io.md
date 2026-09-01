# I/O (`lib/io.nuc`, Stage 17)

`(import-use io)`. The standard streams as [`Writer`](strings.md#writer--an-output-sink)
conformers over raw file descriptors.

Nothing here is `FILE*`-backed. A `FILE` carries a hidden libc buffer, so its
output can reorder against writes issued any other way; a descriptor has no
buffer to disagree about. Explicit buffering is `BufWriter` (`lib/file.nuc`).

---

## §1 — `FdOut`

```lisp
(defstruct FdOut fd:i32)
```

A **borrowed** descriptor. It is never closed — the owning, `Drop`-closed
descriptor is `File` in `lib/file.nuc`.

| Function | Signature | Notes |
|----------|-----------|-------|
| `fd-out` | `(fd:i32):FdOut` | wrap any descriptor |
| `std-out` | `():FdOut` | fd 1 |
| `std-err` | `():FdOut` | fd 2 |
| `fd-write-all` | `(fd:i32 (p (ptr ui8)) n:usize):!void` | loops over short writes |

`FdOut` conforms to `Writer`, so `(write-str o sv)` works and an `FdOut` can be
erased as `(dyn Writer)`.

```lisp
(let (o:FdOut (std-out))
  (write-str o (strview-from-cstr "hello\n")))
```

A short write is ordinary on a pipe, so `fd-write-all` loops until every byte is
gone. A negative return is **not** retried and yields `(err io-write-failed)`:
`EINTR` is only reachable behind a signal handler installed without
`SA_RESTART`, and retrying an unclassified error would spin forever.

---

## §2 — `print`, `println`, `eprint`, `eprintln`

Macros, taking any number of [`ToStr`](strings.md#tostr--a-values-text)
conformers — the same argument shape as [`str`](strings.md#str-into-str-str-alloc).

```lisp
(println "hello " 42 " " 1.5 " " true)     ; hello 42 1.5 true
(print "no newline")
(eprintln "failed at line " n)
(println)                                  ; a bare line
```

| Macro | Stream | Terminator |
|-------|--------|------------|
| `print` | fd 1 | none |
| `println` | fd 1 | `\newline` |
| `eprint` | fd 2 | none |
| `eprintln` | fd 2 | `\newline` |

Each formats into **one shared buffer** and issues **one `write`**, so a line
reaches the descriptor whole rather than a syscall per piece, and the spelling is
allocation-free after the buffer's first growth.

Each expands to the `!void` of its write, so a caller may `try` it; discarding is
the default, as with C's universally-ignored `printf` return.

---

## §3 — `read-line`

```lisp
(read-line):(Maybe String)
```

The next line from standard input **without** its terminator, or `none` at end of
input. A final line with no newline is still returned. An empty line comes back
as a zero-length `String`, not as `none`.

```lisp
(let (go:bool true)
  (while go
    (match (read-line)
      ((some ln) (println "[" (string-as-view ln) "]"))
      ((none)    (set! go false)))))
```

Input is read in 8 KiB chunks; the unbuffered spelling would be a `read` syscall
per byte. The input buffer is stdin's alone and is never shared with `print`'s.

---

## Gotchas and constraints

- **`print`/`println`/`eprint`/`eprintln` are not reentrant.** They share one
  module-global format buffer, so a `ToStr` conformance that itself prints would
  clobber its caller's buffer. No conformance in `lib/` does. Use `str` plus
  `write-str` where reentrancy matters.
- **`FdOut` never closes its descriptor.** Wrapping fd 1 and letting the value go
  out of scope leaves stdout open, which is the point. Use `File` for a
  descriptor you own.
- **These streams are unbuffered.** One `write` per `println`, per `write-str`.
  That is deliberate for diagnostics and wrong for bulk output — reach for
  `BufWriter` there.
- **A read error is reported as end of input.** `read-line` does not distinguish
  a failed `read` from EOF.
