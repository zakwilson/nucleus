# Native strings and IO — retiring C stdio as the default

**Status: future (post-Stage-14).** Companion to
[stage14/native-strings.md](../stage14/native-strings.md), which flipped the
literal type to `StrView` but explicitly rejected excising `CStr` from the
compiler because the compiler's string traffic ultimately feeds libc calls —
`fprintf`/`snprintf`/`fopen`/`fgets` all want a NUL-terminated `char*`. That
rejection was right for Stage 14, and this doc is the other half of the plan:
give Nucleus a native, idiomatic string-conversion and IO library so that the
libc calls themselves go away, and `CStr` retreats to the FFI boundary where it
belongs. Users can still choose C libraries when appropriate; the native
library becomes the default.

Scope discipline: this doc covers the four core pillars (a to-string protocol,
a Clojure-style `str`, terminal IO, file IO with `Drop`-managed handles),
their highly-complementary additions, and whatever else replacing `CStr` in
the compiler concretely requires. It is **not** a survey of everything a
string/IO library could do.

## Non-goals

- **No format-string mini-language.** `printf`'s `"%d of %s"` DSL is replaced
  by ordinary value juxtaposition — `(str n " of " name)` — plus small
  formatting-adverb wrapper values (§6) for the rare width/radix cases. A
  format DSL can be a later macro built *on* this layer; it is not the layer.
- **No locale, grapheme clusters, normalization, or UTF-16.** Same line
  Stage 11 drew: `Char` is a scalar codepoint, strings are UTF-8 bytes.
- **No async/nonblocking IO, no sockets, no path-manipulation library.**
  Blocking read/write on files and the three standard streams only.
- **Not a `CStr` deletion.** `CStr` remains the permanent FFI `char*` type
  (native-strings.md §2). What ends is its use as the compiler's *working*
  string type and stdio as the compiler's IO mechanism.
- **The interned-symbol substrate is untouched.** native-strings.md §1.2's
  constraint stands: `Node.s`, scope keys, and struct-field names are
  identity-compared interned `ptr`s and must stay that way. "Native strings in
  the compiler" means the *IO and text-assembly* paths go native, not that
  identity-`=` pointers get retyped.

---

## 1. The four pillars

### 1.1 `Writer` — the sink protocol (substrate for everything else)

```lisp
(defprotocol Writer
  (write-str:!usize ((self (ref Self)) (s StrView))))
```

The protocol's method count is pinned by a dependency: `Fmt` (below) holds a
type-erased `(dyn Writer)`, and Stage 13's `(dyn P)` v1 supports
**single-method protocols only**. Expanding `(dyn P)` to arbitrary protocols
is designed separately ([dyn-arbitrary-protocols.md](dyn-arbitrary-protocols.md));
this doc works in either world, with one shape decision hanging on it:

- **Option A — today's `dyn` (single-method).** `Writer` is exactly the one
  method above. `flush`, `close`, and byte-oriented writes are concrete
  functions on the concrete types (`File`, `BufWriter`), not protocol
  methods — nothing in the *formatting* path needs them, so the protocol
  stays `dyn`-compatible as-is. The cost lands on holders of an erased
  writer: code that has only a `(dyn Writer)` cannot flush it and must
  either hold the concrete type where flushing matters or lean on `Drop`
  (§3 item 1 is the live instance).
- **Option B — after `(dyn P)` expansion.** `Writer` gains a second method,
  `(flush:!usize ((self (ref Self))))` (no-op conformances for
  `String`/`StdOut`/`StdErr`; the real one on `BufWriter`), so a
  `(dyn Writer)` can be flushed generically and the compiler's emission
  driver can hold *only* the erased writer. `close` and binary writes stay
  concrete either way (closing is ownership, not sinking).

Option A is not a throwaway: B is a strict superset (one added method +
no-op conformances), so shipping A first and widening to B when the `dyn`
expansion lands is a small additive migration, not a redesign. If the
expansion lands first, start at B.

Contract:

- `s` is valid UTF-8 (the standing `StrView` contract). `Writer` is a *text*
  sink; raw binary output is a `File`-level function (§1.5), not a `Writer`
  method.
- All-or-error: the conformance loops internally on short writes; a returned
  count always equals `(s len)`. Returns `!usize` rather than `!void` only
  because `!void` is unsupported (the standing `string-push-str` precedent).

Conformers:

| Type | Behavior |
|---|---|
| `String` | Append via the validating push; infallible in practice (OOM aborts). Replaces `open_memstream`. |
| `File` | Loop over `write(2)` on the wrapped fd. |
| `BufWriter` | Copy into an owned buffer; spill to the wrapped `File` when full. |
| `StdOut` / `StdErr` | Zero-field structs writing to fd 1 / fd 2 (§1.4). |

Precedent inside the compiler: emission already treats its output as a
swappable sink — `g-out` is a `FILE*` redirected between stdout, real files,
and `open_memstream` string streams (`src/scope.nuc:144`, `src/nuch.nuc:359`).
`Writer` is that exact pattern, typed and libc-free.

**`Fmt`** is a thin concrete struct wrapping a `(dyn Writer)` fat pointer.
`ToStr` methods take `(ref Fmt)` rather than the erased writer directly so
that width/precision/alternate-form options can be added to `Fmt` later
without re-signaturing every conformance in the tree (Rust's
`fmt::Formatter`-over-`&mut dyn Write` split, for the same reason). v1 `Fmt`
carries nothing but the writer and forwards `write-str`. Cost: one indirect
call per write — on the formatting path only; a direct `(write-str f "…")` on
a concrete `File`/`String` stays monomorphized.

### 1.2 `ToStr` — the value → text protocol

```lisp
(defprotocol ToStr
  (to-str:!usize ((self (ref Self)) (f (ref Fmt)))))
```

Named for symmetry with the existing `FromStr` (docs/strings.md §7); together
they are the round trip. A conformance *writes* its representation into the
sink — it does not return an allocated string, so building a diagnostic or an
IR line performs no intermediate allocations per value.

Semantics are Clojure-`str`-like, human-readable: a `StrView` writes its bytes
(no quotes), a `Char` writes its UTF-8 encoding, integers write decimal. A
reader-round-trip `repr` (quoted strings, escaped chars) is explicitly out of
scope; if ever needed it is a second protocol, not a mode.

v1 conformances (the closed set needed for the compiler + examples):

- **Integers** — `i8`…`i64`, `ui8`…`ui64`, `usize`/`ssize`, `i1` (as `0`/`1`):
  native divmod-into-stack-buffer, no `snprintf`.
- **Floats** — `f32`/`f64`: v1 may delegate to `snprintf` *internally*
  (shortest-round-trip float printing is a real algorithm — Ryu/Grisu — and
  not worth blocking on). `snprintf` formats into caller memory and touches no
  `FILE*` stream, so the interface stays native and the stdio-stream
  dependency still drops to zero; swapping in a native float printer later is
  invisible.
- **`Char`**, **`StrView`**, **`String`**, **`CStr`** (bytes up to the NUL —
  needed while compiler internals still traffic in interned `ptr`s).
- **`Keyword`** (writes `:name`) — complementary but nearly free and
  immediately useful in diagnostics.

### 1.3 `str` — Clojure-style concatenation

```lisp
(str "expected " n " args, got " m)   ; → String
```

A **macro**, not a function: heterogeneous per-argument types make this
compile-time dispatch by construction (each argument gets its own
monomorphized `to-str` call — no varargs, no boxing, in keeping with the
"macros over runtime overhead" design principle). Expansion shape:

```lisp
(let (s:String (string-new))
  ; one Fmt over s's Writer conformance, then per argument:
  (to-str (addr-of arg0) f) …
  s)
```

- `(str)` → empty `String`. String-typed arguments pass through as content
  (their `ToStr` writes bytes). No `nil` case — Nucleus has no `nil`; a
  `(Maybe T)` argument is the caller's job to unwrap.
- **`str-alloc`** — same macro with an explicit `(ref AllocHandle)` first
  argument (`string-new-alloc` precedent). This is not optional polish: the
  compiler's `fmt-*` helpers are **arena-backed** (`src/format.nuc`,
  `arena-strndup` after `snprintf`), and their replacement must be able to
  build process-lifetime diagnostic strings on the arena with a no-op drop —
  the established allocator idiom.

`print`/`println` (§1.4) reuse the same per-argument expansion aimed at a
stream writer directly — **no intermediate `String`** is built to print.

### 1.4 Terminal IO

```lisp
(print "checking " path " … ")     ; no newline
(println "ok")                     ; trailing newline
(eprint …) (eprintln …)            ; same, to stderr
```

- `StdOut`/`StdErr` are zero-field structs conforming to `Writer` over file
  descriptors 1 and 2 — **not** `FILE*`, so no hidden C-side buffer to
  interleave with. They are unbuffered; a program that prints in bulk wraps
  explicitly (`BufWriter` over a `File` on fd 1). Hidden global buffering (the
  thing C stdio does, with its atexit-flush surprises) is deliberately not
  replicated; buffering is a visible, owned value.
- **Error policy:** `print`/`println` return `void` and abort with a
  diagnostic on write failure (Rust's `println!` panic policy). Threading
  `!T` through every log line is ergonomic poison; code that must handle
  stream errors uses the `Writer` layer directly.
- **`read-line`** — read one line from fd 0, for the REPL (replaces `fgets`).
  Desired shape is `(read-line):(Maybe String)` (`none` = EOF), but
  `(Maybe String)` embeds a struct in the anon union — the known
  `(Maybe StrView)` JIT/matchability limitation class. v1 shape that works
  today: `(read-line (out (ref String))):!i32` returning 1 = line read,
  0 = EOF; revisit when Maybe-struct payloads land (§5).

### 1.5 File IO

```lisp
(defstruct File fd:i32)
```

Raw file descriptors (`open`/`read`/`write`/`close`), not `FILE*` — the whole
point is to stop routing through C's stream layer; buffering becomes an
explicit native value. Both boot platforms provide the fd layer (POSIX
`open`/`read`/`write`/`close`; the Windows CRT's `_open`/`_read`/`_write`/
`_close` — the windows-gnu/msvc boot targets bind whichever spelling the CRT
exports).

- **Constructors** (separate functions, not a mode-flag argument — avoids
  both a flags mini-language and a `keyword`-import dependency in the file
  library):

  | Function | Meaning |
  |---|---|
  | `file-open-read (path StrView) → !File` | existing file, read-only |
  | `file-create (path StrView) → !File` | write, create-or-truncate |
  | `file-open-append (path StrView) → !File` | write, create-or-append |

  Errors via `deferror`: `file-not-found`, `permission-denied`,
  `file-io-error` (mapped from `errno`; everything unrecognized is
  `file-io-error`). Note the path parameter is `StrView`; the conversion to
  the `char*` that `open(2)` needs is internal (literals borrow for free per
  native-strings.md; non-literal paths NUL-terminate into a stack buffer).

- **`Drop` closes the fd.** `(with (f:File (try (file-open-read p))) …)` is
  the idiomatic shape — handle cleanup is scope-driven, no `fclose` to
  forget. `file-close` also exists for explicit early close (disarms the
  drop via the standing `move`/disarm machinery).
- **Reading:** `(file-read-to-string (f (ref File))):!String` — the whole
  remaining content, UTF-8-validated (`invalid-utf8` reuses the string-errors
  code); `file-read-to-vec … :!(Vector ui8)` is the non-text escape hatch;
  `(file-read (f …) (buf (ptr ui8)) (cap usize)):!usize` is the low-level
  loop primitive under both.
- **Writing:** the `Writer` conformance (§1.1) for text;
  `(file-write-bytes …)` for raw bytes.
- **`BufWriter`** — owns a `File` (moved in) plus a byte buffer;
  conforms to `Writer`; `Drop` = flush + close the owned `File`;
  `(buf-flush …)` for explicit flushing. This is the load-bearing type for
  the compiler: IR emission is millions of small writes, and `fprintf`'s
  competitiveness is entirely its `FILE` buffer. An unbuffered fd writer
  would turn each into a syscall; `BufWriter` restores parity (§4's
  performance gate).

---

## 2. Library split

Three layers, matching the suggestion that the conversion protocol belongs
with the existing string stack:

| Library | Contents | Imports |
|---|---|---|
| `lib/fmt.nuc` — joins the string stack as a new leaf | `Writer`, `Fmt`, `ToStr`, scalar/`Char`/`StrView`/`String`/`CStr` conformances, `str`/`str-alloc` | `string` (needs `String` as the sink conformer) |
| `lib/io.nuc` | `StdOut`/`StdErr` + conformances, `print`/`println`/`eprint`/`eprintln`, `read-line` | `fmt` |
| `lib/file.nuc` | `File`, constructors, read functions, `file-write-bytes`, `BufWriter` | `fmt`, `error` |

Layering rationale: `fmt` must sit *above* `string` (the `String`-as-`Writer`
conformance) and *below* both IO libraries (they format into their writers).
The `strview-str` leaf-conformance precedent (docs/strings.md §4) covers any
circularity that shows up in practice. Nothing new enters the prelude —
`StrView` is already there, and `print` being import-gated is consistent with
every other library facility. (If examples chafe, promoting `io` to the
prelude is a one-line decision later.)

---

## 3. What replacing `CStr` in the compiler requires

The compiler's stdio surface, inventoried, with its native replacement:

1. **IR/cheader/nuch emission** — thousands of `fprintf g-out` sites, with
   `g-out` swapped between stdout, output files, and four `open_memstream`
   string streams (`g-entry-stream`, `g-body-stream`, `g-decl-stream`,
   `g-type-stream`). Replacement: `g-out` becomes a `(dyn Writer)` (or a
   small concrete union of `BufWriter`/`String` sinks if the indirect call
   shows up in profiles); the memstreams become `String` sinks — deleting the
   `open_memstream`/manual-`free` dance outright. The existing sink-swapping
   discipline transfers unchanged. One wrinkle tracks the §1.1 option split:
   under **Option A** a `(dyn Writer)` `g-out` cannot be flushed through the
   protocol, so the driver keeps a concrete handle on the final `BufWriter`
   (or scopes it so `Drop` flushes) — workable, mildly asymmetric; under
   **Option B** the erased writer flushes generically and the driver holds
   nothing concrete.
2. **Diagnostics** — `fprintf stderr` sites plus the arena-backed `fmt-*`
   helper family (`src/format.nuc`). Replacement: `eprintln` for direct
   reports; `str-alloc` on the arena for built-and-stored messages. This
   **deletes `format.nuc`'s fixed-arity helper zoo** (`fmt-2s-i`,
   `fmt-3s`, …) and with it the documented format-helper-arity segfault trap
   (conventions.md) — arity is checked by macro expansion instead of trusted
   at a varargs boundary.
3. **Source loading** — the `fopen`/`fseek`/`ftell`/`fread` ladder →
   `file-read-to-string`. (The reader indexes bytes; it gets `data`/`len`
   from the `String` and never re-scans for length.)
4. **REPL** — `fgets` → `read-line`; its `open_memstream` uses → `String`
   sinks.
5. **Boundary conversions that remain `CStr` forever:** `argv`/`getenv` in;
   the LLVM C API (`src/llvm.nuch`) and the linker command line out;
   `strview-from-cstr`/borrow-to-`CStr` at the edges. Also unaffected:
   non-stdio libc (`malloc`/`memcpy`/`strcmp`/…) — this effort targets the
   stream layer, not libc wholesale.
6. **Explicitly out of bounds:** the interned-symbol substrate (see
   Non-goals). Interned names may remain NUL-terminated arena bytes
   indefinitely; only their *printing* changes (the `CStr` `ToStr`
   conformance covers them).

**Gates for the compiler conversion.** Byte-identical *bootstrap* cannot be
the gate — replacing every emission call rewrites the compiler's own IR
wholesale. The correct gate is one level up: **emitted-output identity** — for
every source file in the tree, the IR text (and cheader/nuch text) produced by
the converted compiler must be byte-identical to what the unconverted compiler
produces. That plus the normal fixed-point bootstrap and `make test`
constitute correctness. The second gate is **throughput parity**: self-compile
wall time within noise of the `fprintf` baseline (this is what `BufWriter`
exists for).

---

## 4. Prerequisites — compiler limitations this design leans on

In dependency order; the first is the only hard blocker for the core API
shapes:

1. **Struct payloads through `!T`/`Result`** — today "the struct fields
   arrive as zero when unwrapped via `match`" (docs/strings.md §3 v1
   limitation; the reason `strview-sub-bytes` returns `!ptr:StrView`).
   `file-open-* → !File` and `file-read-to-string → !String` need this fixed
   at the root — the heap-wrapper workaround must not calcify into this API.
2. **`!void`** — `write-str`/`to-str` return `!usize` until it exists;
   cosmetic, shapes are otherwise final.
3. **`(Maybe Struct)` payloads (anon-union embedding + JIT)** — blocks the
   desired `read-line → (Maybe String)` shape; a working v1 signature exists
   (§1.4), so this is an upgrade, not a blocker.
4. **`(dyn P)` arbitrary-protocol expansion**
   ([dyn-arbitrary-protocols.md](dyn-arbitrary-protocols.md)) — not a
   blocker either way: §1.1's Option A works on today's single-method
   `dyn`, and Option B (flushable `Writer`) is a small additive widening if
   the expansion lands. Recorded so nobody "improves" `Writer` with `flush`
   *before* the expansion exists — that would silently make `Fmt`'s erased
   writer unconstructible.

## 5. Complementary additions (bounded)

- **Formatting-adverb wrappers** instead of a format DSL: small value types
  conforming to `ToStr` — `(hex n)`, `(pad-left v width)`, f64 precision
  wrapper. Each is an ordinary struct + conformance; the set stays small and
  grows by need. (The compiler needs at most `hex`.)
- **`Vector`/`HashMap` `ToStr` conformances** — debug convenience
  (`[1 2 3]`-style); parametric `extend`, cheap once `ToStr` exists.
- **`file-size` / seek** — the compiler's only seek use is the
  size-before-read ladder, which `file-read-to-string`'s read loop obsoletes;
  add real seek functions only when a consumer appears.
- **A `Reader` protocol** — v1 keeps reading concrete (functions on
  `File`/stdin). A single-method `read-bytes` protocol is the obvious future
  symmetric move (a richer multi-method one under §1.1's Option B world);
  deferred until something needs to abstract over sources.

## 6. Open questions

- **Error payloads:** `deferror` errors are bare ids — no carried `errno`
  detail. Fine for the compiler (diagnose-and-exit), lossy for library users.
  Depends on whether error values ever grow payloads (stage-10 tail work).
- **`Fmt` options:** stays empty until the first adverb that genuinely needs
  sink-side state (padding needs count-written); adverbs that can compute
  into a stack buffer first may keep `Fmt` empty forever.
- **Naming:** `fmt`/`io`/`file` library names and `ToStr`/`to-str` are
  proposals; `docs/generics.md` uses `Show` in a `&where` example — that
  example should be updated to a real protocol once one exists rather than
  constraining the name choice here.

## 7. Sequencing

After the Stage 14 backbone completes (this doc assumes NS-1…NS-6 and the
type-safety retypes are history). Build order is the dependency order:
`fmt` → `io` → `file` (each landable independently, additive, byte-identical
for the bootstrap since the compiler doesn't use them yet) → compiler
adoption last, as its own staged effort per surface (emission, diagnostics,
source loading, REPL), each surface gated on emitted-output identity + tests
+ throughput parity (§3). NS-5-style selective `StrView` adoption inside the
compiler continues independently and only helps — every `ptr`→`StrView`
seam it converts is one fewer `CStr` crossing when the IO flip arrives. The
`(dyn P)` expansion ([dyn-arbitrary-protocols.md](dyn-arbitrary-protocols.md))
is likewise an independent track with no ordering edge: land it first and
`fmt` starts at §1.1 Option B; land it later and `Writer` widens A→B in one
additive pass.
