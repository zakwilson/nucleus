# Stage 17 — Native strings in the compiler

**Goal.** Every string the compiler handles for its own purposes becomes a
Nucleus native string (`StrView` / `String` / `Symbol`). `CStr` and the libc
string/stdio surface survive **only** at declared C-interop seams — the LLVM C
API, `argv`/`getenv`, `popen`ing `clang -E`, the linker command line, and the
`extern` declarations in `src/llvm.nuch`.

**This is dogfooding, and the dogfooding is the point.** The compiler is the
largest Nucleus program in existence, and it is the only one that has never used
the string library. Every place the conversion is awkward is a defect report
against `lib/strview.nuc` / `lib/string.nuc` and the compiler features they lean
on. The standing rule for this stage:

> **When a conversion is awkward, fix the library or the compiler. Do not work
> around it in `src/`.** A workaround in the compiler hides the finding, which is
> the deliverable.

The findings register is [library-gaps.md](library-gaps.md); the mechanical
apparatus is [migration-tooling.md](migration-tooling.md). This document is the
plan.

This stage executes and supersedes [future/native-io.md](../future/native-io.md),
which designed the library half in detail and deferred the compiler half. That
document's four pillars (`Writer`, `ToStr`, `str`, IO) are adopted essentially as
written; what changes is the scope ruling (§1.3) and the prerequisite list
(§1.4), both of which have moved since it was drafted.

---

## 1. Ground truth (verified 2026-08-31 against the tree)

### 1.1 The inventory — what "C strings in the compiler" actually is

`src/` is 40,712 lines across 14 files with ~4,285 string literals. Its C-string
traffic:

| Surface | Sites | Where | Native replacement |
|---|---:|---|---|
| `fprintf` / `fputs` / `fputc` / `fwrite` to a `FILE*` | **928** | nucleusc 492, union-emit 202, repl 102, abi 79, nuch 21, cheader 13, reader 10, union-registry 6, compiler-types 2, scope 1 | `Writer` + `write` / `str` |
| `printf` to stdout | 88 | cheader 39, nuch 29, rest | `print` / `println` |
| `open_memstream` string sinks | 20 | scope 2, repl 5, nucleusc 13 | `String` as a `Writer` |
| `fmt-*` arena-sprintf helpers | **~650** | 9 fixed-arity shapes in `src/format.nuc` | `str` / `str-alloc` |
| `fopen`/`fread`/`fseek`/`ftell`/`fclose` source ladder | 3/4/3/3/55 | nucleusc, cheader, repl | `file-read-to-string` |
| `fgets` | 1 | repl | `read-line` |
| `fflush` / `setvbuf` | 22 / 1 | stream discipline | `Writer` flush / `BufWriter` |
| `strcmp` / `strncmp` | 201 / 42 | content compares, prefix tests | `=` on `StrView` / `starts-with?` |
| `strlen` | 86 | length recovery on `ptr` | carried `.len` — deleted, not replaced |
| `strchr` / `strstr` | 37 / 14 | scanning | `find-byte` / `byte-find` (§gaps 8) |
| `strdup` / `arena-strndup` | 12 / — | copies | `String` / `str-alloc` |
| `strtol` | 6 | numeric parse | `(parse i64 sv)` |
| `snprintf` / `sprintf` | 36 / 1 | inside `format.nuc` + float printing | deleted, except the float path (§2.6) |
| `CStr` type mentions | **881** | nucleusc 412, generics 154, compiler-types 85, cheader 56, type-utils 40, union-registry 35, abi 30, nuch 20, scope 13, repl 12, type-mangle 11, union-emit 9, reader 4 | `StrView` / `String` / `Symbol`, or retained at an FFI seam |
| interned-`ptr` substrate | ~237 `intern*` references | `Node.s`, scope keys, struct-field names | `Symbol` (§2.4) |
| `popen`/`pclose` | 5 | `clang -E`, linker | **stays `CStr`** |

Two observations that shape the plan.

**The mass is emission, and emission is one function call repeated 928 times.**
It is the most mechanical surface in the tree and the one where a script pays
(migration-tooling.md §2). It is also where byte-for-byte output identity is
checkable, because the output *is* the artifact.

**The `%` escaping tax is real and disappears.** The compiler writes LLVM IR,
whose local names are `%name`, through `printf` format strings — so the source is
littered with `%%v`, `%%p5`, `%%fp`. Every one of those is a latent bug (a
dropped `%` produces a silently malformed conversion). Value juxtaposition has no
escaping layer, so the conversion deletes an entire class of hazard rather than
porting it.

### 1.2 What the string stack has today

`Char`, `StrView` (borrowed `{data,len}`, prelude-registered since NS-1),
`String` (owning, `Vector ui8`), the `ByteStr`/`Str` protocols, `SplitIter`/
`LineIter`, `FromStr`/`parse`, and the string error codes. Full API in
[docs/strings.md](../../docs/strings.md).

What it does **not** have, and the compiler needs on day one: any way to turn a
non-string value into text; any sink abstraction; any IO; any interned-identity
type; a `String`→`CStr` bridge; byte/char search primitives beyond substring
find. That list is [library-gaps.md](library-gaps.md) — 20 items, of which 8 are
outright blockers for the conversion.

### 1.3 Three prior rulings this stage overturns, and one it keeps

[stage14/native-strings.md](../stage14/native-strings.md) §1.2 and
[future/native-io.md](../future/native-io.md) "Non-goals" between them rule out
most of what this stage does. Each ruling was correct **for its stage** and is
re-decided here on new information, not overridden by fiat:

1. **"Adopting native strings does not mean rewriting the compiler in them."**
   *Correct for Stage 14*, where the deliverable was a byte-identical literal
   flip and the library had no `Writer`/`ToStr`. Overturned here: the rewrite
   *is* the deliverable, and byte-identical bootstrap is replaced by a stronger
   gate (§5.1).

2. **"The compiler is glued to libc; those need a `char*`, not a `{ptr,len}`."**
   True as a statement about libc and false as a constraint: the compiler is glued
   to libc *because nothing else exists*. native-io.md is the plan to make
   something else exist; this stage builds it.

3. **"The interned-symbol substrate is untouched — `Node.s`, scope keys and
   struct-field names are identity-compared `ptr`s and must stay that way."**
   This is the ruling that matters, and it is the one this stage most directly
   overturns. The requirement it protects is real and non-negotiable: O(1)
   identity comparison, no `strcmp`. But *"therefore keep it a raw `char*`"* is
   precisely the work-around-the-weakness move this stage forbids. The weakness
   is that **the native string stack has no interned-identity type**. The fix is
   to add one (§2.4), not to exempt the substrate. Note that `lib/keyword.nuc`
   already proves the shape and already fails at compiler scale — a 256-entry
   linear scan with a `strcmp` per probe.

4. **Kept, unchanged: `CStr` is not retired.** It remains the permanent FFI
   `char*` type. The stage's success condition is that `CStr` appears *only*
   where a C ABI demands it — not that it stops existing.

### 1.4 Prerequisites re-measured — two of the three blockers are already gone

native-io.md §4 listed four compiler limitations its API shapes leaned on. Three
were re-tested against `bin/nucleusc` on 2026-08-31:

| Prerequisite | native-io.md status | **Measured 2026-08-31** |
|---|---|---|
| Struct payloads through `!T`/`Result` | "hard blocker" | **Works.** `(defn mk (…):!StrView … (ok sv))` + `match` returns correct fields; same for `!String`. |
| `(Maybe Struct)` payloads | "blocks `read-line`'s desired shape" | **Works** in an AOT compile: `(Maybe StrView)` constructs, returns and `match`es correctly. JIT/CT-module behaviour is **unverified** and is an A-track check. |
| `!void` | "cosmetic; shapes otherwise final" | **Still broken.** `(defn f (…):!void … (ok))` → `error: Result.void.Err: arm 'ok' takes a different number of fields`. Real work, phase A1. |
| `(dyn P)` arbitrary protocols | "not a blocker either way" | Unchanged. `Writer` ships single-method (Option A); widening is additive. |

**Consequence, and it is a large one.** Three of the string library's documented
"v1 limitations" are workarounds for a limitation that no longer exists:
`strview-sub-bytes` returning `!ptr:StrView` (a heap wrapper), `strview-from-cstr`
returning `(ptr StrView)`, and `SplitIter`/`LineIter` conforming to
`(Iterator ptr)` with the `doseq-split` decode macro. Under this stage's standing
rule these are **retired, not preserved** — see library-gaps.md items 4, 5, 6.
A stale workaround that calcifies into an API is exactly what dogfooding is for.

---

## 2. Decisions

### 2.1 The replacement lattice

Every C-string-shaped value in `src/` resolves to exactly one of five
destinations. The conversion is a decision procedure, not a judgement call:

| Today | Question | Becomes |
|---|---|---|
| `ptr` / `CStr` compared with `=` for **sameness** | identity? | **`Symbol`** (§2.4) — one word, `=` is pointer identity, O(1) length and view |
| `ptr` / `CStr` compared with `=` for **content**, borrowed | owns its bytes? no | **`StrView`** |
| `ptr` from `arena-strndup` / `strdup` / `fmt-*`, stored | owns its bytes? yes | **`String`**, or `str-alloc`-on-arena for process-lifetime text |
| `FILE*` sink | — | **`(dyn Writer)`** (`BufWriter` / `String` / `StdOut` / `StdErr`) |
| argument to / result from a C declaration | is the callee C? | **stays `CStr`** |

The middle three are content types and interconvert freely. `Symbol` is the only
new type, and it exists precisely so the identity column has a native answer.

### 2.2 The library is built first, complete, and used by nothing

`lib/fmt.nuc`, `lib/io.nuc`, `lib/file.nuc`, `lib/intern.nuc` land as additive,
independently tested libraries with the compiler still on libc. Each is
byte-identical for the bootstrap by construction (nothing in `src/` imports them
yet) and gated on examples + tests alone. This keeps the two halves of the stage
from failing each other: a conversion batch that breaks is a conversion bug, not
a library bug, because the library was green before the batch started.

### 2.3 The conversion is per-surface, incremental, and dual-path

A big-bang emission flip is unreviewable and unbisectable. Instead a `CFile`
type conforming to `Writer` wraps a `FILE*`, so `g-out` can become a
`(dyn Writer)` **before** any call site converts, and each `fprintf` site is
flipped to `write`/`str` independently against a byte-identical output gate. The
`FILE*` backing is removed last, when the final call site is gone
(migration-tooling.md §4).

### 2.4 `Symbol` — the interned-identity type, with a length header behind the pointer

```lisp
(defstruct Symbol p:(ptr ui8))     ; one word; points at the interned BYTES
```

Representation: the interner allocates `[len:usize][bytes…][NUL]` in the intern
arena and the `Symbol` holds the address of the first *byte*, not the header.
That choice buys all four properties the substrate needs at once:

- **`=` is pointer identity** — one `icmp eq ptr`, the same instruction the
  compiler emits today. The hot path does not regress, and the migration is
  IR-neutral for every identity comparison.
- **Length is O(1)** — a load at `p[-8]`. This deletes the 86 `strlen` calls on
  interned names rather than reimplementing them.
- **`as-view` is O(1) and allocation-free** — `{p, p[-8]}`.
- **`as-cstr` is free** — the bytes are still NUL-terminated, so every remaining
  FFI seam takes `Symbol` with no copy and no conversion.

`Symbol` conforms to `Eq` (identity), `Hash` (cached in the header alongside the
length), `ByteStr`/`Str` (via `as-view`), and `ToStr`. `lib/intern.nuc` provides
an open-addressed table, not `lib/keyword.nuc`'s linear scan; `Keyword` is then
rebased onto it (library-gaps.md item 14), which retires the 256-entry cap.

**Naming.** `Symbol` sits uncomfortably close to the compiler's own `Sym` struct
(`src/compiler-types.nuc:563`), which is a *binding* record, not a name. Confirm
no registration collision before A-track; `Name` is the fallback spelling.

### 2.5 No format-string DSL

Carried unchanged from native-io.md's non-goals. `(str "expected " n " args, got "
m)` replaces `"expected %d args, got %d"`. This is what deletes `src/format.nuc`'s
fixed-arity helper zoo **and** the format-helper-arity segfault trap documented in
`context/conventions.md` — arity becomes a macro-expansion fact instead of a
varargs-boundary hope. The 650 `fmt-*` call sites are the single largest
ergonomic win in the stage.

### 2.6 Float printing delegates to `snprintf`, permanently and deliberately

IR float constants are emitted through `"%.9g"` / `"%.17g"`. Shortest-round-trip
float printing is a real algorithm (Ryu/Grisu) and is not this stage's problem.
The `f32`/`f64` `ToStr` conformances format into a caller-provided stack buffer
via `snprintf`, which touches no `FILE*`: the interface is native, the stdio
dependency still goes to zero, and the emitted bytes are identical by
construction. Swapping in a native float printer later is invisible.

### 2.7 What stays `CStr`, enumerated

The residual list is closed and is enforced by a tripwire (§5.5), not by
vigilance:

- `src/llvm.nuch` — the LLVM C API, whole.
- `argv` / `getenv` / `exit` / `system`-adjacent entry points.
- `popen("clang -E …")` / `pclose` in `src/cheader.nuc`, and the linker command
  line.
- Any `declare`d C function's parameters and returns.
- `lib/*.nuch` C-header surfaces and `--emit-cheader` output *content* (which is
  C source text — produced as a native `String`, written natively; only the
  `char*`s it names are C).

#### 2.7a The same list for `lib/` (swept 2026-09-03)

§5.5's tripwire covers `src/` only, so `lib/` was never enumerated and drifted:
`join`'s separator, `keyword-intern`'s argument, `bool`'s `ToStr`, the node
interner's table key and a dead `arena-strdup` were all still C-shaped after the
stage closed. What is left is closed and is one of four kinds:

1. **The lattice's own doors.** `symbol-as-cstr` / `symbol-from-cstr[-unchecked]`,
   `string-as-cstr` / `string-from-cstr[-unchecked]`, `strview-from-cstr` /
   `strview-to-cstr`, and `cstr-bytes` / `cstr-chars`. Every one names `cstr` in
   its own name; that is the point of them.
2. **Calls with no native implementation.** `strtod` (`lib/parse.nuc`) and
   `snprintf` (`lib/fmt.nuc`'s float printer, §2.6) — both with native
   interfaces, both permanent by decision.
3. **The `CStr` conformances** — `ToStr` (`fmt`), `Hash` (`hash`), `Eq`
   (`numeric`). They exist so a `char*` that arrived *from C* can be formatted,
   hashed and compared. A Nucleus program should reach for `StrView`, which the
   library's own usage examples now show.
4. **Compiler-emitted ABI, which is not a source-level API.** `intern-symbol`
   (the `'foo` lowering) and `err-find-handler`'s repair-type `token` (with its
   `strcmp` fallback for separate compilation). Both are called from hand-written
   IR in `src/`, so making either take a `StrView` means hand-lowering a
   by-value struct argument per target — a real change, deliberately not made
   here, and now said so at both sites.

Not in the list, because it is not `lib/`: `examples/` still opens ~55 views with
`(strview-from-cstr "literal")`, a round trip through `strlen` that a literal has
not needed since the Stage 14 NS-3 flip made it a `StrView`. Some of those sites
are deliberate coverage of the conversion API; most are habit.

---

## 3. Phases

Four tracks. A and B are additive and parallel-safe; C is strictly serialized
(one refresh window at a time, per staging discipline); D is built alongside A/B
and is a hard dependency of C.

### Track A — compiler prerequisites

**A1 — `!void`. Done 2026-08-31.** Two changes, and the second was not in the
plan:

1. **`defunion-register` drops a `void` field** (`src/union-registry.nuc`). A
   `void` field carries no value, so it contributes none — a general `defunion`
   rule, not a `Result` special case. `(Result void Err)` then stamps a
   payload-less `ok` arm exactly like `Maybe`'s `none`, `(ok)` constructs it,
   `((ok) …)` matches it, and the layout engine already classifies
   `{payload-less, Err}` as the ordinary tagged `{i32 tag, Err}` struct. That is
   the entire representation change.
2. **`try` moved out of `lib/error.nuc` and into the compiler** — `emit-try`
   (`src/union-emit.nuc`) plus its `node-type` lockstep arm (`src/generics.nuc`),
   reserved in `g-special-form-set`. It had been a macro expanding to a fixed
   `((ok v) v)` arm, and **the ok arm's binder count depends on the operand's
   type, which a macro cannot see**: `!void` needs `((ok) (do))` and `!T` needs
   `((ok v) v)`. `emit-try` synthesizes the same match, choosing the arm shape
   from `result-ok-type`. This also removes `try` from the set of things
   `(import-use error)` gates.

Bootstrap needed a one-generation shim: a `defmacro` may not shadow a special
form, so `lib/error.nuc` cannot keep a `try` macro — but `src/reader.nuc` has 19
`try` sites and had to compile under the *previous* boot, which has neither. The
macro was renamed `try-boot` and `src/reader.nuc` repointed at it for exactly one
`make update-bootstrap`, then both were removed.

*Gate met:* 936 tests (was 935), `make bootstrap` byte-identical fixed point,
`examples/result-void.nuc` + `tests/expected/result-void.out` covering `(ok)`,
`((ok) …)`, `try` on `!void` inside `!void` and inside `!T`, and both err paths.
Docs: `docs/errors.md` gained a `!void` section, `docs/special-forms.md` a `try`
row, and the `try`-needs-`(import-use error)` claim was corrected in two files.

*Found in passing:* `lib/macros.nuch` was already stale in the committed tree
(a `strcmp`→`=` simplification had landed in `lib/macros.nuc` without
regenerating the header), so `make test` was failing `headers-generated` before
this work started. Regenerated.

**A2 — retire the stale `!T`-struct workarounds. Done 2026-08-31.**
Struct-through-`!T` works (§1.4); the API shapes that assumed otherwise did not.
`strview-from-cstr` → `StrView` by value (no `malloc`), `strview-sub-bytes` →
`!StrView` by value, and the `ByteStr.sub-bytes` protocol method plus both
conformances (`StrView`, `String`) with it. Six examples migrated; `docs/strings.md`
and `docs/stdlib.md` corrected. *Gate met:* 936 tests, `make bootstrap`
byte-identical, all six examples byte-identical against their committed
`tests/expected/*.out`.

*Raised by the migration:* every by-value producer meets a by-reference
consumer, so the natural call site is now a two-line
`(let (av:StrView … a:ptr:StrView (addr-of av)) …)`. That is item 18's receiver
inconsistency as concrete friction, and the compiler conversion will hit it
thousands of times — logged as library-gaps.md #24, to settle in B0 before
`fmt`/`io`/`file` add more conformers to each protocol.

**A3 — `(Maybe Struct)` in JIT/CT modules. Done 2026-08-31.** The premise was
stale: `(Maybe StrView)` stamps in the macro-expansion JIT module, in a macro
body and in an `(Iterator StrView)` conformance alike. Nothing needed fixing at
the anon-union stamp.

`SplitIter` and `LineIter` are `(Iterator StrView)`; the `cur` scratch fields,
the niche encoding and `doseq-split` are deleted, and `doseq-iter` drives both.
Six examples and two docs sections migrated.

The promotion turned every segment into a value at its call sites, and that
found two defects, both in the register:

- **#25 — a `StrView` decayed to `.data` at *any* pointer target**, so passing
  one to a `(ref StrView)` parameter compiled clean and passed garbage. The
  NS-2/NS-3 borrow rule tested `dk == TY-PTR`, and `(ref StrView)` is `TY-PTR`.
  Now gated on `strview-borrow-target` (`src/type-utils.nuc`): `CStr`, bare
  `ptr`, or a pointer to an 8-bit integer. Bootstrap stayed byte-identical.
- **#26 — `defstruct` silently accepts a duplicate field name**, and
  `--emit-cheader` emits it twice. Found via the committed-header test; fix
  deferred to B0.

This is the shape the stage is for: dogfooding a retype found a silent
miscompile in the exact type the whole conversion depends on, before any
compiler surface was converted.

**A4 — `(dyn P)` multi-method (optional, no ordering edge).** If
[future/dyn-arbitrary-protocols.md](../future/dyn-arbitrary-protocols.md) lands,
`Writer` starts at Option B (`flush` in the protocol). Otherwise Option A ships
and widens additively later. Do **not** add `flush` to `Writer` before the
expansion exists — that makes `Fmt`'s erased writer unconstructible.

### Track B — the library

**B0 — string-stack gap closure. Blockers done 2026-09-01.** The items in
[library-gaps.md](library-gaps.md), each with a fixture. The ones marked
*blocker* gate B1–B3; the rest land opportunistically as the conversion finds
them (and the register is appended to as it does — that is the deliverable).

Every blocker that is not itself B1–B4 is closed: #5 (`string-push-str`'s
per-byte `conj`), #6 (`vector-extend-raw`/`vector-extend`), #8 (the `strview`
value constructor), #9 (`string-as-cstr`), #10 (`strview-find-byte`/`-rfind-byte`/
`-rfind`/`-find-char`/`-rfind-char`), plus #13 (`!void` re-signatures), #20
(`strview-len` retired) and #26 (duplicate `defstruct` field now rejected).
`examples/string-b0-test.nuc` and `tests/fixtures/s17-dup-struct-field.nuc`
cover them. Two rulings changed on contact:

- **#5's re-validation stays.** The register claimed a `StrView` is documented
  as valid UTF-8; it is not — it is a byte slice, which is why
  `string-from-view` validates. `String` is the UTF-8-guaranteed type, so the
  check belongs exactly where it was. `string-push-str-unchecked` was added
  beside it instead, mirroring `string-from-cstr-unchecked`, and *that* is what
  the emission path will use. The cliff was the per-byte `conj`, not the scan.
- **#10 forced a rename.** `strview-byte-find` (substring) → `strview-find`, so
  it does not sit one character away from `strview-find-byte` meaning something
  else.

Remaining, non-blocking: #14–#17 (String editing, `split-once`/`splitn`/`rsplit`,
number-formatting adverbs, case operations) land with the surfaces that need
them; #18/#24 (the receiver convention) is settled — see
[borrow-conventions.md](borrow-conventions.md).

**B1 — `lib/fmt.nuc` — done 2026-09-01.** `Writer` (single-method `write-str`),
`ToStr`, conformances for `i64`/`i32`/`usize`/`ui64`, `f32`/`f64` (§2.6),
`Char`, `bool`, `StrView`, `CStr`, and the `str-into` / `str` / `str-alloc`
macros. `String` and `CFile` as the two `Writer` conformers.

Three deviations from the plan above, each recorded in the file header:

- **`Fmt` is not built.** A formatter holding an erased writer would box through
  `(dyn Writer)` once per formatted piece, and neither shape that actually
  occurs wants it: a diagnostic builds a `String` with `str` and writes it once,
  and IR emission writes literal chunks straight to the sink with `write-str`.
  Add it when a call site asks.
- **`String` does not conform to `ToStr`, and `Symbol`/`Keyword` cannot yet.**
  `ToStr`'s receiver is `Self` **by value**, which is what lets `(to-str 42 out)`
  work — a `(ref Self)` receiver makes a literal an rvalue with no address to
  take, and every other conformer is small and POD. `String` has `Drop`, so by
  value would be a *move*; it is written through `(string-as-view s)`, which is
  O(1). `Symbol` and `Keyword` land with B4, which is where `Symbol` is defined.
- **`Writer`'s byte argument is by value**, not `(ref StrView)`. It is not
  `Self`, so the cross-conformer constraint of borrow-conventions.md §2 does not
  reach it, and two words in two registers lets a literal or a producer's result
  be the argument with no binding to take the address of.

`str-into` recurses one piece at a time (the shape `+` and `-` in
`lib/macros.nuc` use) rather than building the call list with `make-cell`: each
piece needs *wrapping* in a `(to-str … out)` call, which `~@` cannot do, and a
`defn` helper cannot be called from a macro body — `node` is `import-ct`'d, so
`make-cell`/`intern-symbol` exist only inside the JIT'd expander.

`examples/fmt-test.nuc`. 941 tests, `make bootstrap` byte-identical.

**B2 — `lib/io.nuc` — done 2026-09-01.** The standard streams as `Writer`s over
raw descriptors, `print`/`println`/`eprint`/`eprintln`, `read-line`. Not
`FILE*`-backed: no hidden C buffer to interleave with the compiler's own output.

Two deviations from the plan above:

- **One `FdOut` type with an `fd` field**, not separate `StdOut`/`StdErr`. The
  two would have identical conformances differing only in a constant, and
  `(dyn Writer)` erases them to the same thing. `(std-out)` / `(std-err)` are
  constructors. `FdOut` is *borrowed* and never closed — the owning,
  `Drop`-closed descriptor is B3's `File`.
- **`print` and friends share one module-global format buffer**, cleared per
  call, so a line is one `write` and the spelling is allocation-free after the
  first growth. The cost is that they are **not reentrant**; nothing in `lib/`
  formats by printing. Each expands to the `!void` of its write, so a caller may
  `try` it and discarding is the default.

`EINTR` is not retried: it is only reachable behind a handler installed without
`SA_RESTART`, and retrying an unclassified error would spin. Short writes *are*
looped over, which is not defensive — that is ordinary on a pipe.

`read-line` is tested by `tests/fixtures/s17-read-line.nuc` with piped input
rather than by an example: an example inherits the harness's stdin and would
block on a terminal. `examples/io-test.nuc` covers everything else.

**B3 — `lib/file.nuc` — done 2026-09-01.** `File` (fd, `Drop`-closed),
`file-open-read`/`file-create`/`file-open-append`, `file-read-to-string`,
`file-write-bytes`, `BufWriter` (owns a `File`, `Drop` = flush + close).
`BufWriter` is load-bearing: IR emission is millions of small writes and
`fprintf`'s only real advantage is its `FILE` buffer.

`File` and `BufWriter` both conform to `Writer`. `BufWriter` sends anything at
least a bufferful straight to the descriptor — staging it would be a memcpy that
buys no syscall. `file-close` / `buf-writer-close` exist beside the `Drop` path
because `close` can fail late and `Drop` returns `void`, so a program that must
know the bytes reached disk needs a form that reports.

Two findings, both registered:

- **#28, not fixable here.** `open(2)`'s flags are C preprocessor macros, which
  Nucleus deliberately does not import, so `O_RDONLY`/`O_CREAT`/`O_TRUNC`/
  `O_APPEND` are spelled out as Linux/glibc `defconst`s and `lib/file.nuc` is
  Linux-only as written. The real fix is a target-keyed constants module or
  object-like `#define` evaluation in the header import; neither is B3's job.
- **#29, fixed.** `(try (write-str f sv))` mis-sized its `ok` arm whenever `f`
  was a struct *value* binding: `node-type-call`'s tier 0 was still exact-match
  only, so the lvalue implicit address-of was invisible to the type side while
  emit resolved it fine. `generic-find-method-accepting` mirrors
  `generic-resolve`'s tier-0 second pass. The `node-type`↔`emit-node` lockstep
  charging for a one-sided change.

**B4 — `lib/intern.nuc` — done 2026-09-01.** `Symbol` (§2.4), the
open-addressed intern table, conformances, and the `Keyword` rebase, with the
benchmark the plan asked for.

The layout is as designed — `[hash][len][bytes][NUL]` with the `Symbol` holding
the address of the first *byte* — and it delivers all four properties: `=` emits
one `icmp eq ptr` (verified in the IR), `symbol-len`/`hash` are loads behind the
pointer, `symbol-as-view` allocates nothing, and `symbol-as-cstr` is free.
Conformances: `Eq`, `Hash`, `ToStr`, `ByteStr`, `Str`. No name collision with
the compiler's `Sym` — the `Name` fallback was not needed.

`Keyword` is now **one `Symbol` and nothing else**: one word instead of three,
no `id` counter, and `lib/keyword.nuc`'s 256-entry fixed array with a `strcmp`
per probe is gone (#4).

**The benchmark earned its place.** `tests/fixtures/s17-intern-bench.nuc` timed
`symbol-intern` at **8x slower** than the compiler's own `intern-symbol` over
the same corpus — a stage-level failure by the plan's own standard. The table
was not the cause: `strview-hash` folded through `reduce` over a `ByteIter`, so
every byte cost an indirect call through a closure plus a `(Maybe ui8)`
construction and match (#30). With a direct byte loop, and at -O3 (how the
compiler is actually built), `symbol-intern` is ~1.5x **faster** than
`intern-symbol`. The finding generalizes: an `Iterator` fold is a fine default
and the wrong tool inside a primitive everything else calls.

### Track C — the conversion, surface by surface

Each phase: convert, gate on emitted-output identity + tests + bootstrap, land,
then the next. Ordering is by mechanical-ness (safest first) and by how much each
phase de-risks the next.

**C1 — diagnostics and the death of `src/format.nuc` — done 2026-09-01.**
All **636** `fmt-*` call sites → `fstr`; the nine helpers and `fmt-take` are
deleted (`format.nuc` 258 → 198 lines, now only the identifier layer). The
**39** non-REPL `fprintf stderr` sites → `eprint`. *Why first:* diagnostics are
not in the IR output, so the output-identity gate is free here, while the `str`
machinery gets exercised across 636 real call sites before anything
load-bearing depends on it.

**`fstr`, not `str-alloc` directly** (`src/strfmt.nuc`). It is `str-alloc` on
the compiler's arena handed back as a bare `ptr`, and both halves of that are
deliberate. The arena gives the process lifetime `arena-strndup` gave, so no
call site changes how it stores the result. The bare `ptr` — rather than the
honest `CStr` — is because a branch join of a `CStr` arm and a `ptr` arm
collapses to void, and `(if c base (fstr …))` is a shape that occurs. Two
compiler-local conformances go with it and are scheduled for deletion in C6–C7:
`ToStr` on bare `ptr` (the compiler's strings still are one; the specifier
census over all 636 sites found no `%p`, so a `%s` argument was a C string by
construction), and a `Hex` value type for the `%016lX`/`%04lX`/`%016lx` float
bit patterns.

**The rewriter is `scripts/stage17/rewrite-fmt.py`**, paren-aware as
[migration-tooling.md](migration-tooling.md) §2 requires, with a `--stderr` mode
for the `fprintf` half. It refused **zero** sites: the specifier census came
back `%s`=781, `%d`=141, `%ld`=18, `%%`=17, `%016lX`=9, `%04lX`=4, `%016lx`=2,
`%c`=1, all of which the table models. It is not fully transitive in one pass —
a `fmt-*` nested inside another's argument list is consumed as source text — so
it is run to a fixed point (three passes here).

Three findings:

- **The boot compiler gates the source.** `fstr` needs the lvalue implicit
  address-of, so `src/` could not use it until `make update-bootstrap` refreshed
  `boot/nucleusc.ll` and `bin/nucleusc`. One shim generation, exactly as
  `try-boot` needed.
- **One name collision, and only one.** Importing the string stack early brings
  `char-at` into scope, which the reader had defined for `(ptr, i64)`. Renamed
  to `cstr-byte-at` (284 uses) — the suffixed-name convention `src/` already
  follows for `defn-params-count` and friends.
- **Two `%s` arguments were typed `ptr:Node`** — `Node.car` holding a path
  string. `%s` read them as bytes without complaint; `to-str` will not, so both
  now carry an explicit `(as ptr …)`. The type system found a place the format
  string was lying.

`sanitize-for-ir`/`sanitize-for-c`/`ir-name-token`/`ir-name-append`/
`ir-name-illegal-char`/`ir-name-leading-digit` stay as they are, on
`arena-alloc` and byte loops. They never used `snprintf`, so none of C1's hazard
applies to them, and `ir-name-token`'s pointer-unchanged fast path is an
identity contract that a rewrite to `String` would have to preserve
deliberately. That belongs with the substrate conversion (C6–C7), not here.

Self-compile time is unchanged (1.29s before and after). 945 tests,
`make bootstrap` byte-identical. Deferred to their own phases as planned: the 69
`printf`-to-stdout sites (C2 — converting them before the IR stream would
reorder against a block-buffered `stdout`) and the REPL's 44 `fprintf stderr`
sites (C5).

**C2 — IR emission. Done 2026-09-01.** All **848** sites, in five gated batches.
The sinks did **not** become `(dyn Writer)` and there was no `CFile` dual path:
the call-site conversion and the sink retype are separable, and doing them
separately meant one change to `emit-flush` instead of touching every site twice.

The output shape is `(emit S …)`, not the `(write S (str …))` the tooling doc
sketched — `str` allocates and drops a `String`, and this is the compiler's
hottest output path. `emit` formats into one process-wide buffer and issues one
`fwrite`; `emit-flush` takes a **mark** (`byte-len` before the pieces are
appended) and writes only the bytes above it before rewinding, which makes one
shared buffer safe when an argument's own side effect emits — the inner text
goes out first and the buffer is left as found, the order `fprintf` gave.

Zero refusals from the script. The four hand conversions are the shapes a format
string can express and it cannot reach: `src/cheader.nuc`'s skip-reason
`macrolet`, which takes the *format string itself* as a macro argument so the
literal to split is not at the call site; two `fwrite`s of a byte range, now
`strview` pieces; and the REPL's `#<ptr %p>`, which is `"0x"` plus `hex … 0`
because glibc's `%p` is minimal-width lowercase hex.

**C3 — memstream sinks. Done 2026-09-01.** All twelve, and `open_memstream` — a
glibc/musl-only function — is gone from `src/`, with every `bufp`/`sizep` pair,
35 `free`s, 35 `fclose`s and 14 `fflush`es. Owning buffers are `String` values;
the aliases (`g-out`, `g-decl-out`, `g-def-stream`, `g-def-stream-program`) stay
pointers, `(raw String)`, null before a module opens exactly as the `FILE*`s
were. `emit-flush` overloads on the sink rather than erasing it, so the dispatch
is static and boxes nothing, and `emit-all` appends a whole buffer without
staging it a second time.

Four defects the types surfaced, each in progress.md: a `String` cannot be a
`FnState` field (compiler-types.nuc is imported before lib/string.nuc, so the CT
module's type section lacks `%String`); `push-function-state` was always a move;
the REPL's stream snapshot was aliasing a buffer `open-module-streams` clears in
place; and "is a module open" was the null-ness of `g-type-stream`.

**C4 — source loading. Done 2026-09-01.** `read-file`, `file-defines-name` and
`file-exists` → `file-open-read` + `file-read-to-string`; no `fopen` remains in
`src/`. `lib/file.nuc`'s Linux-only `defconst` block does not reach here —
`O_RDONLY` is 0 everywhere and only the create/append flags differ. The reader
still takes a NUL-terminated `ptr`; handing it a `StrView` is C6's job, since it
is the substrate question, not the file question.

**C5 — the REPL. Done 2026-09-01.** Its 101 write sites went with C2 (they had to:
`emit-string-table` cannot take a `(ref String)` sink while one of its callers
still writes `fprintf` into a memstream), its memstreams with C3, and
`repl-read-input` now reads with `read-line` into a `String` — the hand-grown
`malloc`/`realloc` buffer and the per-line 4 KB scratch allocation are gone.
`read-line` strips the terminator, so the newline is pushed back: the accumulated
text is source, and the newline both ends a `;` comment and is what every
reported line number counts. `setvbuf`/`fflush` on `stdout` **stay** — they order
the JIT'd program's stdio, not the compiler's, so no `BufWriter` discipline
replaces them.

**C6 — comparison and scanning. Done 2026-09-01.** 201 `strcmp` → `=` on `StrView`/`Symbol`; 42
`strncmp` → `starts-with?`; 37 `strchr` + 14 `strstr` → `find-byte`/`byte-find`;
86 `strlen` deleted against carried lengths; 12 `strdup` → `String`; 6 `strtol` →
`(parse i64 …)`. This phase is where the `ptr`→`StrView` retypes actually land,
and where `context/conventions.md`'s identity-vs-content trap is live at every
site: **the decision procedure is §2.1's first row.** A value that is compared for
sameness goes to `Symbol`, never to `StrView`.

**C7 — the interned substrate. Done 2026-09-02, in five steps.** `Node.s`, `intern-str`/`intern-symbol`,
scope keys, struct-field names, `Sym.ir-name`, `Method.ir-name` → `Symbol`.
Highest-risk phase and deliberately last: it changes a type that `lib/node.nuc`
exports, that the prelude registers, and that the macro JIT resolves against the
compiler process — so the macro ABI moves with it. The header-behind-the-pointer
representation (§2.4) keeps every identity comparison emitting the same
instruction, which is what makes the IR diff reviewable at all.

**C8 — close-out. Done 2026-09-02.** `--strict-cstr`'s census went **678 → 63**
emitted sites before the tool itself was deleted, and the tripwire that replaces
it is hard: `scripts/check-cstr.py` counts `CStr` plus 27 libc string/stdio
entry points per file in `src/` and fails on any difference from
`scripts/cstr-allowlist.txt` **in either direction**, so a new libc call cannot
appear silently and a conversion cannot leave the list describing a compiler that
no longer exists. It runs as the `cstr-residue` unit of `make test`. The
allowlist is **3 entries / 22 sites**, every one audited against §2.7: `opendir`'s
path and `readdir`'s `d_name`, `getenv`, `argv`, five LLVM-C message strings, two
`symbol-from-cstr-unchecked` casts, and one `(= hp 'strdup)` that matches a *name*
rather than calling the function.

Deleted with the phase: `--strict-cstr` and `src/strict-cstr.nuc` (a scaffold the
allowlist supersedes — it counted a synthesized `CStr` the source could not show,
which is what it was for, and that job is over), `scripts/stage17/cstr-seams.txt`,
the `make strict-cstr` target, `fcstr` and the `ptr` `ToStr` conformance (the last
two together forced every remaining `ptr`-as-string local to declare itself, which
is how the tail of the census was found rather than grepped for).

Two changes fell out of the audit: `symbol-from-cstr-unchecked` — the inverse of
`symbol-as-cstr`, for a `Symbol` parked in a pointer-shaped slot, needed because
`unsafe/cast` cannot make a struct from a pointer — and the literal-join fix in
`join-strlit-branch`
([library-gaps.md §42](library-gaps.md#42-string-literals-meeting-at-a-branch-collapsed-to-cstr--fixed-2026-09-02-c8)).

Docs: `context/conventions.md`'s lattice section is rewritten for four types with
a pick-by-need table, and its `Node.s`-must-stay-`ptr` rule is marked superseded
by the `Symbol` rule. `docs/strings.md` gains the pick-by-need table, §10
(`Symbol`) and §11 (writing strings out); `fmt` is §9 from C1, and `io`/`file`
are [docs/io.md](../../docs/io.md), cross-referenced rather than duplicated.

**Found, not fixed:** `doc`, `apropos` and `kind-of` are documented
(`docs/toplevel.md`, `docs/compiler.md`, `docs/builtins.md`, `docs/emacs.md`) and
exist nowhere in the tree; the `docstring` fields on `Sym` and `MacroDef` are
dead storage. They were retyped to `Symbol` with honest comments rather than
deleted — deciding between building the feature and cutting the docs is outside
this stage.

### Track D — tooling

Detailed in [migration-tooling.md](migration-tooling.md). Four artifacts, all
built before C1 starts:

1. **`make ir-snapshot` / `make ir-verify`** — the emitted-output identity
   harness. The gate that replaces byte-identical bootstrap.
2. **The `fprintf` rewriter** — a script that mechanically converts
   `(fprintf S "fmt" args…)` to `(write S (str …))`, handling `%%` unescaping and
   the conversion-to-argument split. Aims for ~90% of the 928 sites; the residue
   is hand-converted and is itself a finding (what shapes defeated it).
3. **`--strict-cstr`** — a temporary compiler flag that reports every production
   or consumption of a `CStr`/`ptr`-as-string outside a declared FFI seam. Direct
   precedent: Stage 16's `--strict-selectors`, which enumerated 7,254 sites and
   turned an unregexable migration into a compiler-guided one — and found a class
   of site (compiler-synthesized member access) that no source sweep could reach.
   Expect the same here: the compiler *synthesizes* strings, and grep cannot see
   an `(intern-symbol "…")`. **Done** — `src/strict-cstr.nuc`, the seam list at
   `scripts/stage17/cstr-seams.txt`, `make strict-cstr`; baseline 4,568 sites,
   and the same expectation held (a `CStr` inside `invoke.pVector.StrView.usize`
   is in no source file). Deleted at C8.
4. **`make bench-selfcompile`** — wall-time and allocation counters for the
   throughput gate.

---

## 4. What this deletes

Worth stating explicitly, because it is the argument for the stage beyond
dogfooding:

- `src/format.nuc`'s nine fixed-arity helpers **and** the documented
  format-helper-arity segfault trap (a mismatch segfaults the compiler; arity
  becomes a macro-expansion check).
- Every `%%` in the tree, and the class of malformed-conversion bug it invites.
- 86 `strlen` calls on values whose length was already known.
- The `open_memstream` out-parameter dance and its manual `free`s (20 sites).
- The `fmt-take`/`snprintf`-truncation clamp — `String` grows, so there is no
  512-byte buffer to overrun and no clamp to remember.
- `lib/keyword.nuc`'s 256-entry linear scan.
- Three string-library API workarounds for compiler limitations that no longer
  exist (§1.4).

---

## 5. Gates

### 5.1 Emitted-output identity — the primary gate

Byte-identical bootstrap is **impossible** for this stage: replacing every
emission call rewrites the compiler's own IR wholesale. The correct gate is one
level up. For every file in `tests/fixtures/`, `examples/`, `lib/` and `src/`,
the **text the compiler produces** — LLVM IR, `--emit-cheader` output, `.nuch`
output — must be byte-identical before and after each conversion batch. The
compiler changes; what it writes must not.

This is strictly stronger than the bootstrap gate for this class of change and
strictly weaker for others, so it does not replace the others:

### 5.2 Bootstrap fixed point
`make bootstrap` (stage1 == stage2) after every phase. Refresh windows are
serialized — never two in flight.

### 5.3 Test suite
`make test` (~919), plus `abi-test`, `layout-test`, `check-headers`, `avr-test`,
`riscv-test`.

### 5.4 Throughput parity
Self-compile wall time within noise of the `fprintf` baseline, measured per
phase, not once at the end. `BufWriter` exists for this; a phase that regresses
throughput is not done. `Symbol`'s intern-table probe cost (B4) is measured
separately because it is on a hotter path than emission.

### 5.5 Residual-`CStr` tripwire
A test that greps `src/` for `CStr`, the libc string functions and the stdio
functions, and fails on any occurrence outside the §2.7 allowlist. Advisory from
C1 (so the count is visibly monotonic downward), hard at C8. The allowlist is
per-file-and-symbol, so a new libc call cannot be added silently.

**Built at C8** as `scripts/check-cstr.py` + `scripts/cstr-allowlist.txt`, run by
the `cstr-residue` unit of `make test`. It compares counts in **both** directions,
which the spec above did not say and which is the half that matters over time: a
one-directional check lets the allowlist keep asserting a seam that no longer
exists, and the next reader trusts it. `;` comments, `"…"` literals and `\c` char
literals are stripped first — nearly every remaining textual mention of `strcmp`
or `fprintf` in `src/` is prose about what replaced it, and an emitted `@printf(`
is IR the compiler *writes*, not a call it makes.

---

## 6. Sequencing and dependency edges

```
A1 (!void) ─┐
A2 (!T shapes) ─┼─► B0 ─► B1 (fmt) ─► B2 (io) ─► B3 (file) ─┐
A3 (Maybe/JIT) ─┘                    B4 (intern) ────────────┤
                                                             ▼
D1..D4 (tooling) ──────────────────────────────────► C1 ─► C2 ─► C3 ─► C4 ─► C5 ─► C6 ─► C7 ─► C8
```

- **A1 → B1 (hard).** `Writer.write-str` and `ToStr.to-str` return `!void`, or
  they ship with the `!i32` sentinel and re-signature the whole tree later.
- **B1 → C1 (hard).** `str` must exist before `fmt-*` can die.
- **B3 → C2 (hard).** `BufWriter` must exist before `g-out` can stop being a
  `FILE*` without a throughput cliff.
- **B4 → C7 (hard).** `Symbol` before the substrate moves.
- **D1 → C1 (hard).** No conversion batch lands without the output-identity gate.
- **D3 (`--strict-cstr`) → C6/C8 (hard).** C6's completeness is an enumeration
  claim, and grep cannot make it. C8's close-out is the same claim, tightened.
- **A4 → B1 (soft).** Decides `Writer` Option A vs B; A→B is additive.
- **C1 before C2 (soft but strongly preferred).** Exercises `str` at scale where
  the output-identity gate is free.
- **C7 last (hard).** Macro-ABI risk; every other phase should be green first so
  a bootstrap failure in C7 has exactly one candidate cause.

---

## 7. Risks

| Risk | Why it bites | Mitigation |
|---|---|---|
| **Throughput regression on emission** | 928 sites × millions of calls; unbuffered fd writes are a syscall each | `BufWriter` from B3; §5.4 measured per phase, not at the end |
| **`Symbol` regresses the hot path** | `Node.s` comparison is the compiler's innermost loop | Header-behind-pointer keeps `=` a single `icmp`; B4 benchmark gates the type before C7 |
| **Macro-ABI break in C7** | `lib/node.nuc` is prelude-registered and JIT-resolved against the compiler process | C7 last; `Symbol` is pointer-sized so the `Node` layout does not move; `make bootstrap` plus the macro fixtures |
| **The `%%` unescape is wrong somewhere** | A silent one-character error in generated IR | Output-identity gate catches it per batch; that is what the gate is *for* |
| **Bootstrap chicken-and-egg** | `src/` may only use features the *old* boot compiler supports | Standard `make update-bootstrap` discipline; A-track features land and are boot-refreshed before C uses them |
| **Two refresh windows collide** | Stage-15/16 tail work may still be in flight | Serialize; check `stage16-ergonomics/deferred.md` before starting |
| **The gap register grows without bound** | Dogfooding always finds more | library-gaps.md distinguishes *blocker* from *found*; only blockers gate phases, the rest are logged and triaged |

---

## 8. Alternatives considered and rejected

- **Keep the interned substrate as raw `ptr` (the standing Stage 14/native-io
  ruling).** Rejected §1.3: it leaves the largest single class of C strings in the
  compiler untouched and hides the real finding, which is that the string stack
  has no interned type. `Symbol` costs one library file and keeps the identity
  semantics exactly.
- **`Symbol` as a `usize` id into a table.** One word and identity-cheap, but
  every byte access becomes a table indirection and every FFI seam becomes a copy.
  The header-behind-the-pointer form is the same width with O(1) bytes and a free
  `CStr`.
- **Big-bang emission conversion.** Rejected §2.3: unreviewable, unbisectable,
  and it makes the output-identity gate a single pass/fail at the end instead of
  928 individually attributable ones.
- **A `format`-style DSL macro instead of `str`.** Rejected in native-io.md and
  again here: the format string is the thing being deleted. A DSL can be built on
  `ToStr` later by anyone who wants one.
- **Native float printing (Ryu) in this stage.** Rejected §2.6: a real algorithm,
  orthogonal, and delegating keeps the emitted bytes identical by construction.
- **Byte-identical bootstrap as the gate.** Impossible for this change (§5.1);
  emitted-output identity is the correct, and stronger, substitute.
- **Converting `src/` file-by-file instead of surface-by-surface.** Tempting
  (files are natural batches) but wrong: a file mixes emission, diagnostics and
  comparison, so a file-batch mixes three different gates and three different
  failure modes. Surfaces are converted whole; files are the batching *within* a
  surface.

---

One line: *build the missing native layer (`fmt`/`io`/`file`/`intern`) to
completion, then convert the compiler surface by surface behind an
emitted-output-identity gate — and every time it hurts, fix the library, because
that is the deliverable.*
