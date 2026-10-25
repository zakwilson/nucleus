# I/O (`lib/nucleus/io.nuc`, `lib/nucleus/file.nuc`, Stage 17)

`(import-use nucleus.io)` for the standard streams, `(import-use nucleus.file)` for files. Both
expose their sinks as [`Writer`](strings.md#writer--an-output-sink) conformers
over raw file descriptors.

Nothing here is `FILE*`-backed. A `FILE` carries a hidden libc buffer, so its
output can reorder against writes issued any other way; a descriptor has no
buffer to disagree about. Explicit buffering is `BufWriter` (`lib/nucleus/file.nuc`).

---

## §1 — `FdOut`

```lisp
(defstruct FdOut fd:i32)
```

A **borrowed** descriptor. It is never closed — the owning, `Drop`-closed
descriptor is `File` in `lib/nucleus/file.nuc`.

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

## §4 — `File` (`lib/nucleus/file.nuc`)

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

## §4b — Directories (`lib/nucleus/file.nuc`)

| Function | Signature |
|----------|-----------|
| `read-dir` | `(path:StrView):!DirEntries` — every entry but `.` and `..`, sorted by name |
| `dir-count` | `((self (ref DirEntries))):usize` |
| `dir-name` | `((self (ref DirEntries)) i:usize):StrView` |
| `dir-is-dir?` | `((self (ref DirEntries)) i:usize):bool` — entry `i` is a directory; a symlink never is |
| `walk-dir` | `(root:StrView):!DirEntries` — every non-directory below `root`, recursively, as `root/…` paths |
| `glob-files` | `(pat:StrView):!DirEntries` — the non-directories matching the path glob `pat` |
| `path-glob-match` | `(pat:&StrView path:&StrView):bool` — the path glob (below) |
| `glob-match` | `(pat:&StrView s:&StrView):bool` — the text glob: `*` any run of bytes, `/` included, `?` any one byte |
| `make-dir` | `(path:StrView):!void` — one level, mode 0755 |
| `dir-exists?` | `(path:StrView):bool` |

```lisp
(with (d (try (read-dir "examples")))
  (let (i:usize 0)
    (while (< i (dir-count d))
      (println (dir-name d i))
      (set! i (+ i 1)))))
```

`DirEntries` owns one buffer of NUL-terminated names plus their offsets, so a
`dir-name` view is valid while the `DirEntries` is alive. It is `Drop`.

**Sorted, not `readdir` order.** `readdir` hands back whatever order the
filesystem keeps, which differs between machines and between two runs after a
rename. Sorting here is what makes "walk this directory" reproducible; a caller
that wants raw order does not exist yet.

`make-dir` is **idempotent**: an existing directory is success. It makes one
level, not a path — there is no `mkdir -p`.

### Walking and globs

```lisp
(with (d (try (glob-files "lib/**/*.nuc")))
  (let (i:usize 0)
    (while (< i (dir-count d))
      (println (dir-name d i))       ; lib/nucleus/allocator.nuc, …
      (set! i (+ i 1)))))
```

`walk-dir` and `glob-files` return a `DirEntries` whose names are whole paths.
**The order is bytewise over the whole path**, which is what `LC_ALL=C sort`
and a C-locale shell glob give: `a-b.nuc` and `a.nuc` come before `a/x.nuc`.
Within a directory a subdirectory sorts as its name plus `/`, which is how
a depth-first walk produces that order without sorting at the end.

Neither lists a directory, so an empty directory contributes nothing. A
symlink is listed as an entry and is never entered, so a link cycle cannot
loop. That holds on a filesystem that does not report entry types
(`DT_UNKNOWN`) too: there `read-dir` asks `readlink` before it tries to open
the entry as a directory.
`walk-dir` lists hidden (`.`) names. A walk that cannot read a directory
fails with that directory's error rather than skipping it.

**The path glob** is bash's, with `globstar` on:

- `*` matches any run of bytes and `?` any one byte, both within one
  `/`-separated component.
- A component that is exactly `**` matches any number of whole components,
  so `lib/**/*.nuc` matches `lib/a.nuc` and `lib/x/y/a.nuc`. A trailing `**`
  needs at least one, so `lib/**` matches what is below `lib`, not `lib`
  itself. Elsewhere `**` is just two `*`s.
- A component's leading `.` is matched only by a literal `.`, so `*` and
  `**` never reach `.git/…`; `.*/x` does.
- There are no `[…]` classes and no escapes.

`glob-files` starts its walk at the pattern's leading literal components
(`lib` for `lib/**/*.nuc`) and does not enter hidden directories unless the
pattern spells a leading `.`. A start that does not exist matches nothing,
which is not an error. A pattern with no `*` or `?` names one path, and
matches it when it is a readable non-directory.

`glob-match` is the **text** glob, the one the test framework's
`check-match` uses on lines: there `*` crosses `/`. Use `path-glob-match`
for paths.

`read-dir` fails with `dir-layout-unknown` when the platform's `struct dirent`
is not the layout it reads names at. It knows because `.` and `..` exist in
every POSIX directory, so their absence means the offset is wrong — which is
the difference between failing and returning names read out of the middle of
`d_ino`.

---

## §4c — Metadata, paths and the environment (`lib/nucleus/file.nuc`)

| Function | Signature |
|----------|-----------|
| `file-stat` | `(path:StrView):!FileStat` — follows a symlink; `(err io-stat-failed)` when `stat` fails |
| `file-exists?` | `(path:StrView):bool` — anything `stat` can see, directories included |
| `rename-file` | `(from:StrView to:StrView):!void` — `rename(2)`: atomic within one filesystem, replaces `to` |
| `remove-file` | `(path:StrView):!void` — a file or an empty directory |
| `real-path` | `(path:StrView):!String` — absolute, with symlinks, `.` and `..` resolved; the path must exist |
| `exe-path` | `():!String` — the running executable (`/proc/self/exe`) |
| `env-var` | `(name:StrView):?StrView` — none when unset **or empty** |
| `xdg-config-home` | `():!String` — `$XDG_CONFIG_HOME`, else `$HOME/.config` |
| `xdg-cache-home` | `():!String` — `$XDG_CACHE_HOME`, else `$HOME/.cache` |
| `xdg-dir` | `(var:StrView fallback:StrView):!String` — the general form: `$var`, else `$HOME/<fallback>` |

```lisp
(defconst FILE-KIND-OTHER 0)
(defconst FILE-KIND-REG 1)
(defconst FILE-KIND-DIR 2)
(defstruct FileStat mtime-ns:i64 size:i64 kind:i32)
```

`mtime-ns` is nanoseconds since the epoch (`st_mtim`), so two writes within
one second still compare as different. A build tool's staleness check needs
that.

A relative `$XDG_CONFIG_HOME` is ignored, as the XDG base directory
specification says, and the `$HOME` fallback is used. With `$HOME` unset as
well, the result is `(err io-path-failed)`.

The failures are `io-stat-failed`, `io-rename-failed`, `io-remove-failed` and
`io-path-failed`.

### Tracked reads

| Function | Signature |
|----------|-----------|
| `read-file-tracked` | `(path:StrView):!String` — `file-read-to-string`, with `path` recorded first |
| `track-read` | `(path:StrView):void` — record a path without reading it |
| `tracked-reads` | `():StrView` — every recorded path, each followed by a NUL byte, in order |

A macro or `(compile-time …)` body that reads a file through
`read-file-tracked` puts that file in the compiler's `--depfile=` output, so a
build reruns when the file changes. See
[Reading files at compile time](macros.md#reading-files-at-compile-time). The
path is recorded even when the read fails, because a file that appears later
changes the output too. In an ordinary program the record is just a buffer,
allocated on the first call.

---

## §5 — `BufWriter` (`lib/nucleus/file.nuc`)

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
      (drop &line)))
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
- **`open(2)`'s flags come from the target's own `<fcntl.h>`.** `file-create`
  and friends name `O_WRONLY`/`O_CREAT`/`O_TRUNC`/`O_APPEND`, which the C header
  import folds and registers under their C names
  ([Integer constants from a C header](compiler.md#integer-constants-from-a-c-header)),
  so the values follow `--target=`. They were hardcoded Linux/glibc numbers
  until Stage 17, which opened the wrong kind of descriptor on Darwin with no
  diagnostic.
- **`Drop` cannot report a failed final write.** Letting a `BufWriter` fall out
  of scope still flushes, but the result is unobservable. Call
  `buf-writer-close` where it matters.
