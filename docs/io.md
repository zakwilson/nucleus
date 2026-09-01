# I/O (`lib/io.nuc`, `lib/file.nuc`, Stage 17)

`(import-use io)` for the standard streams, `(import-use file)` for files. Both
expose their sinks as [`Writer`](strings.md#writer--an-output-sink) conformers
over raw file descriptors.

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

## §4 — `File` (`lib/file.nuc`)

```lisp
(defstruct File fd:i32)
```

An **owning** descriptor: `Drop` closes it, so a `with`-bound `File` needs no
explicit close. Every constructor returns `!File`.

| Function | Signature |
|----------|-----------|
| `file-open-read` | `((path (ref StrView))):!File` |
| `file-create` | `((path (ref StrView))):!File` — `O_WRONLY\|O_CREAT\|O_TRUNC`, mode 0644 |
| `file-open-append` | `((path (ref StrView))):!File` — `O_WRONLY\|O_CREAT\|O_APPEND`, mode 0644 |
| `file-open-flags` | `((path (ref StrView)) flags:i32 mode:i32):!File` |
| `file-close` | `((self (ref File))):!void` |
| `file-write-bytes` | `((self (ref File)) (p (ptr ui8)) n:usize):!void` |
| `file-read-to-string` | `((self (ref File))):!String` |

`File` conforms to `Writer`.

A failed `open` is `(err io-open-failed)`; a failed `read` is
`(err io-read-failed)`. A `read` returning 0 is end of file, not an error.

`file-read-to-string` reads **bytes** and does not validate UTF-8 — the compiler
reads source files whose encoding is the program's problem to diagnose, not the
reader's to refuse.

The path is copied, because `open(2)` wants a NUL-terminated string and a
`StrView` is not one. The copy is unchecked: a path is bytes, not necessarily
UTF-8.

`file-close` exists beside the `Drop` path because `close` can fail late (a
deferred write error on NFS) and `Drop` returns `void`. It sets the descriptor to
-1, so a later `Drop` does not close a number some other `open` has since been
handed.

```lisp
(defn slurp ((path (ref StrView))):!String
  (with (f (try (file-open-read path)))
    (return (file-read-to-string f))))
```

---

## §5 — `BufWriter` (`lib/file.nuc`)

```lisp
(defstruct BufWriter out:File buf:String)
```

A `File` plus a 64 KiB staging buffer. This is what makes bulk output viable
without a `FILE`: IR emission is millions of small writes, and a `FILE`'s buffer
was the only thing `fprintf` had that a bare descriptor does not.

| Function | Signature |
|----------|-----------|
| `buf-writer` | `(f:File):BufWriter` — takes ownership of the `File` |
| `flush` | `((self (ref BufWriter))):!void` |
| `buf-writer-close` | `((self (ref BufWriter))):!void` — flush, then close |

`BufWriter` conforms to `Writer` and to `Drop` (flush + close). A `write-str` of
at least a bufferful goes straight to the descriptor rather than being staged —
the memcpy would buy no syscall.

```lisp
(with (bw (buf-writer (try (file-create path))))
  (dotimes (i n)
    (let (line:String (str "line " i \newline))
      (try (write-str bw (string-as-view line)))
      (drop (addr-of line))))
  (return (buf-writer-close bw)))
```

See `examples/file-test.nuc`.

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
- **`lib/file.nuc` is Linux-only as written, and that is a known defect.**
  `open(2)`'s flags are C preprocessor macros, which Nucleus does not yet
  import, so they are spelled out with Linux/glibc values; Darwin's differ, so
  the wrong descriptor is opened there with no diagnostic. The fix is to admit
  object-like `#define`s from the C header import, which gets the *target's*
  values — designed in `design/future/platform-constants.md`, not yet built.
- **`Drop` cannot report a failed final write.** Letting a `BufWriter` fall out
  of scope still flushes, but the result is unobservable. Call
  `buf-writer-close` where it matters.
