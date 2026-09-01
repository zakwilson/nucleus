# Platform constants: admitting object-like `#define`s from a C header

Status: **deferred out of Stage 17**, raised by
[stage17-native-strings/library-gaps.md](../stage17-native-strings/library-gaps.md)
#28. Blocks nothing in Stage 17; blocks `lib/file.nuc` being portable, which is
not an acceptable end state.

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

### 3.1 Design decisions the implementation must make

- **Name mangling.** C spells these `O_CREAT`; Nucleus spells constants
  `O-CREAT`. Registering the C name verbatim is the honest choice (it is what
  `(import-use "…")` does for functions and types already) and needs no new
  rule. Do **not** invent an underscore-to-hyphen translation — that would make
  `O_CREAT` and `O-CREAT` two spellings of one thing.
- **Volume.** `-dM` on `<stdio.h>` dumps ~400 macros, most of them internal
  (`__GLIBC__`, `__x86_64__`, feature-test flags). Registering all of them
  pollutes the global namespace with names a program could plausibly want. Two
  candidate policies: register everything and rely on the one-symbol-one-kind
  shadowing rule to report collisions, or skip names beginning with `_`, which
  is exactly the identifier space C reserves for the implementation. **Prefer
  the latter**; it removes the great majority and is a rule with a reason.
- **Ordering.** Macro definitions must register before any form that references
  them, i.e. during the same import that reads the header, alongside the
  function declarations.
- **Type.** An admitted macro is an untyped integer literal, the same thing
  `defconst` produces, so it widens at a call the way a literal does. It must
  **not** be given a fixed width — `O_CREAT` meeting an `i32` parameter and
  `INT64_MAX` meeting an `i64` one both have to work.
- **The `-dM` run is a second `clang` invocation** unless `-dD` is used instead
  (which emits macros *and* the preprocessed text, in order). `-dD` is one
  process instead of two and keeps the definitions positioned relative to the
  declarations; measure before choosing, since `-dD` changes the text the
  existing parser walks.

### 3.2 What stays out

Function-like macros (`#define MAX(a,b) …`), string and token-sequence macros,
and anything whose body references another macro that itself did not fold. Those
remain what they are today: not importable, and a program that needs one writes
a `defconst` or a shim.

## 4. Until then

`lib/file.nuc` stays Linux-only and **says so** — in its header, in
`docs/io.md`'s constraints, and in the register. That is a knowingly-scoped
limitation with a named fix, not an oversight. The moment this lands, the
`defconst` block in `lib/file.nuc` is deleted and the `open` flags come from the
target's own `fcntl.h`.
