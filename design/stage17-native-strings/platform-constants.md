# Platform constants: admitting object-like `#define`s from a C header

Status: **in Stage 17**, raised by
[library-gaps.md](library-gaps.md) #28. Blocks nothing else in Stage 17; blocked
`lib/file.nuc` being portable, which was not an acceptable end state.

---

## 1. The problem

`(import-use "fcntl.h")` brings in C *declarations*. It deliberately does not
bring in C **macros** (design/overview.md), so this fails:

```lisp
(import-use "fcntl.h")
(open path O_RDONLY 0)     ; error: undefined: O_RDONLY
```

Every POSIX flag a program needs is an object-like macro. `lib/file.nuc`
therefore spells them out:

```lisp
(defconst O-RDONLY 0)
(defconst O-WRONLY 1)
(defconst O-CREAT 64)      ; 0100
(defconst O-TRUNC 512)     ; 01000
(defconst O-APPEND 1024)   ; 02000
```

Those are the **Linux/glibc** values. Darwin's are different — `O_CREAT` is
`0x200`, `O_TRUNC` `0x400`, `O_APPEND` `0x8` — so the library opens the wrong
kind of file descriptor on macOS, silently, with no diagnostic. A standard
library that is correct on one kernel and wrong on another is a defect, not a
platform limitation.

It is not one library's problem either. The same wall has already been hit at:

| Constant | Where | Worked around as |
|---|---|---|
| `O_RDONLY` … `O_APPEND`, `0644` | `lib/file.nuc`, `examples/cheader-posix.nuc` | hardcoded Linux values |
| `EINTR` | `lib/io.nuc` | not handled at all; the retry loop was dropped |
| `CLOCKS_PER_SEC` | `tests/fixtures/s17-intern-bench.nuc` | hardcoded 1000000 |
| `SEEK_SET`, `SEEK_END` | `examples/cheader-posix.nuc` | hardcoded |

and it will be hit again by every future binding — `errno` values, `S_IF*`,
`PROT_*`/`MAP_*`, `SIG*`, `INT_MAX`, `EOF`, `stdin`/`stdout` on platforms where
they are macros.

## 2. Why the ruling was right and is now wrong

"Nucleus consumes C functions and data structures but deliberately not C macros"
is a good rule about **function-like** macros and about token-paste/stringize
trickery: those are a preprocessor language, not a C interface, and importing
them would mean implementing that language. It was never a good rule about

```c
#define O_CREAT 0100
```

which is a named integer constant that happens to be spelled with `#define`
because C had no other way to spell one in 1975. Nucleus already imports the
other three ways C names an integer constant — `enum` members, `const int`
objects, and array extents — so the exclusion is not principled, it is an
artifact of where the parser stopped.

## 3. The fix

**Admit object-like macros whose replacement list is an integer constant
expression.** Nothing else: no function-like macros, no string macros, no
partial token sequences.

The two pieces this needs already exist.

**Getting the definitions.** `src/cheader.nuc` already shells out once per
header (`cheader-run-cpp`, `clang -E%s -x c -include <hdr> /dev/null`). Adding
`-dM` makes clang dump every macro that survives preprocessing, one
`#define NAME body` per line. Cross-compilation is already handled: the
`--target=`/`--sysroot=` flags in `cheader-cc-target-flags` are on that command
line, so the values come from the **emission target's** headers, which is
exactly the correctness property the hardcoded table cannot have.

**Evaluating the bodies.** `src/cheader.nuc` already carries a C
constant-expression evaluator — the `c-cexpr-*` family, built for array extents
(`c-header-layout.md` §3.2). It folds literals, casts, `sizeof`, and the
arithmetic and bitwise operators, and it **clears `ok` on anything it cannot
fold**, which is precisely the admission test wanted here: a body that does not
fold is not a constant and is skipped.

So the pass is: for each `#define NAME body` line where `NAME` is followed by a
space (not `(` — that is function-like), run the body through the existing
evaluator; on success, register `NAME` as a `defconst`-equivalent.

### 3.1 Decisions

- **Names are registered verbatim** (ruling). C spells these `O_CREAT`; that is
  the name Nucleus gets. `(import-use "…")` already does this for functions and
  types, so no new rule is needed, and an underscore-to-hyphen translation would
  make `O_CREAT` and `O-CREAT` two spellings of one thing.
- **A leading `_` means private** (ruling): such a macro is *not* registered
  unless the import is `(unsafe/import-private …)`. That is exactly the
  identifier space C reserves for the implementation, and it removes most of the
  volume.

  `sym-private` cannot carry this rule. `globals-lookup-ref` resolves an
  unqualified name through `scope-frame-find`, which does **not** filter
  private symbols, and then returns early whenever `g-ns-declared` is 0 — the
  case for every file in this tree. Only the flattened-namespace path reaches
  `scope-frame-find-public`. So the rule is enforced where the name is *created*:
  a `_`-prefixed macro is skipped at registration unless
  `g-import-include-private` is set. It is still marked `sym-private` when it is
  registered, so the namespace path agrees with the registration path.
- **Private macros still fold.** They are kept in the fold table even when they
  are not registered, because public macros are defined in terms of them:
  `F_GETOWN` is `__F_GETOWN`, `S_IRWXU` is `(__S_IREAD|__S_IWRITE|__S_IEXEC)`.
  Dropping them from the table would silently lose the public names too.
- **Ordering.** Registration happens during the same import that reads the
  header, after the declaration pass — a body may cast through a typedef
  (`CLOCKS_PER_SEC` is `((__clock_t) 1000000)`) that only the declaration pass
  records.
- **Type.** An admitted macro is an untyped integer literal, the same thing
  `defconst` produces (`is-const` + `const-val` + `const-lit` + `const-lit-i64`,
  type from `int-literal-type`), so it widens at a use site the way a literal
  does. `O_CREAT` meeting an `i32` parameter and `INT64_MAX` meeting an `i64`
  one both work.
- **`-dM`, in a second `clang` run.** `-dD` would be one process, but it changes
  the text the existing declaration parser walks — every `#define` line becomes
  something that parser has to skip, for no gain. `-dM` leaves that parser
  untouched. The cost is one extra run per *distinct* header, cached alongside
  the existing preprocessed text.
- **Compiler predefines are subtracted.** `-dM` dumps clang's own predefined
  macros as well as the header's, so `-include fcntl.h` yields 739 names of
  which 398 are predefines — `linux`, `unix`, `__GNUC__`. Registering `linux`
  and `unix` as global integer constants from any C import is namespace
  vandalism. A baseline run (`clang -dM -E -x c /dev/null`, once per process)
  gives the predefined set, which is subtracted before registration. Predefines
  stay in the *fold* table for the same reason private macros do.

  Measured after both filters: `fcntl.h` 98 candidate names, `stdio.h` 15,
  `time.h` 15, `unistd.h` 18, `sys/stat.h` 35 — small enough that eager
  registration into the linear `g-globals` frame is not a concern.

### 3.2 What stays out

Function-like macros (`#define MAX(a,b) …`), string and token-sequence macros,
and anything whose body references another macro that itself did not fold. Those
remain what they are today: not importable, and a program that needs one writes
a `defconst` or a shim.

A body must fold **and consume itself entirely**: `#define M_PI 3.14159…` folds
its leading `3` and then stops at the `.`, so the trailing-text check is what
keeps `M_PI` from being registered as `3`.

## 4. Implementation

All in `src/cheader.nuc`, plus the deletion in `lib/file.nuc`.

1. **`cheader-preprocess-mode (header-path dump-macros out-len)`** — the
   existing `cheader-preprocess` body with `" -dM"` appended to the clang flags
   when `dump-macros` is 1, and the cache record's unused `line` field carrying
   the mode so the two texts for one header do not collide.
   `cheader-preprocess` becomes a one-line call. The host-fallback *warning* is
   suppressed in macro mode: the plain run already printed it.
2. **Bitwise levels.** `c-cexpr-bitand` → `c-cexpr-bitxor` → `c-cexpr-bitor`
   above `c-cexpr-shift`, each refusing the doubled form (`&&`, `||`) so a
   logical operator is not silently read as a bitwise one.
3. **`c-cexpr-top`** dispatches: `c-cexpr-shift` normally, `c-cexpr-bitor` while
   folding macros. `c-array-extent` keeps entering at `c-cexpr-shift`, so no
   struct that was opaque suddenly lays out and no emitted byte moves.
4. **Identifier resolution** in `c-cexpr-primary`, gated on the same
   folding flag: an identifier that names an already-folded macro is its value.
   Gated because `-E` output has macros already expanded, so an identifier in an
   array extent is an enum member or a `const` object — resolving it against a
   same-named macro would be a wrong answer, not a better one.
5. **The fold pass** parses the `-dM` text into a `(Vector (ref CMacro))`,
   skipping function-like macros, then iterates to a fixed point: each round
   folds every not-yet-folded body, and stops when a round folds nothing. The
   `-dM` replacement lists are **unexpanded**, which is why the fixed point is
   needed at all.
6. **Registration** walks the folded set, skipping predefines, `_`-prefixed
   names (unless private), and any name `g-globals` already has.
7. **Decimal overflow clears `ok`** in `c-cexpr-number`: a base-10 literal that
   does not fit `i64` is not a value. Hex and octal are bit patterns and keep
   wrapping, so `0xffffffffffffffffU` is `-1`. Array extents are unaffected —
   an overflowed extent already failed the 1…`INT32_MAX` clamp.

## 5. `lib/file.nuc`

The `defconst` block goes, and `file-open-flags`/`file-create`/`file-open-append`
use `O_RDONLY`/`O_WRONLY`/`O_CREAT`/`O_TRUNC`/`O_APPEND` from the target's own
`fcntl.h`. `0644` is a literal, not a macro, in every libc — it stays a literal,
spelled `420` with the octal in a comment as before.

`docs/io.md`'s Linux-only constraint and library-gaps #28 both retire with it.

## 6. As built (2026-09-03)

The plan above is what landed, in `src/cheader.nuc`
(`cheader-preprocess-mode`, `c-cexpr-bitand`/`-bitxor`/`-bitor`/`-top`,
`CMacro` + `cheader-macro-scan`/`-fold`/`-register`, `cheader-import-macros`).
Three things worth recording beyond it:

- **The whole 2,624-artifact IR snapshot is byte-identical.** On this host the
  imported `O_RDONLY`/`O_CREAT`/… equal the values `lib/file.nuc` had hardcoded,
  so nothing moved but the source of the numbers. Only the `--emit-cheader` and
  `.nuch` echo artifacts of the four edited sources changed, each by exactly the
  deleted `defconst` lines; the snapshot was re-baselined for that (recorded in
  `design/progress.md`). No `.ll` differed.
- **A latent library bug surfaced.** `hashset-new-in` spelled its allocation
  `(as (ref (HashSet T)) …)`; `as` refuses to reinterpret the allocator handle's
  `ptr:ui8`, so the function had never instantiated in this tree — every
  `(HashSet …)` in it comes from a by-value `#{…}` literal. Fixed to
  `unsafe/cast`, which is what `hashmap-new-in` already used.
- **The gate is `tests/layout/macros.h` plus four units** in
  `tests/run-tests.sh`. The header is the admission table itself: composition
  through a private macro, each operator, `i64`-max, and the six shapes that must
  stay out. The POSIX unit's expected values come from running `clang` at test
  time, never from a table written here — the portability property is the point,
  and a hardcoded expectation would be the very defect this replaces.

Not taken: `EINTR` now resolves, but `lib/io.nuc` still does not retry on it.
Adding the loop is a behaviour change, not a portability one.
