# Finish the hand-rolled C parser, or switch to libclang?

**Recommendation: finish the hand-rolled parser.** Not because libclang is the
wrong architecture — it is a better one on paper — but because the residue it
would clear is now measured at **nine types out of one hundred eleven**, four of
which fall to a single ~15-line repair, while libclang's cost is dominated by
work that the residue does not touch. The parser is not 70 % of the way there,
which is what [c-header-layout.md](c-header-layout.md) §1.5 measured *before*
L1–L5; it is 92 % of the way there, and the remaining 8 % is enumerable by name.

> **Followed, and finished — 2026-08-28.** All nine are closed:
> [c-boundary-defects.md](c-boundary-defects.md) §12 (FP-4, four types), §14.7
> (PK-3, `max_align_t`), §15 (BF-1…BF-4, `FILE`), §16 (AN-1/AN-2, `sigcontext`
> and `rusage`; C1a, `cmsghdr`). The census is **111 of 111**, and the sizes
> match `cc` for every one. libclang stays a live option under §6's stated
> trigger, but the residue that motivated the question no longer exists.

Everything below was measured on 2026-08-26 against `build/nucleusc` at
`bd4bec1`, on glibc 2.41 / clang 19.1.7. Method is stated per measurement so it
can be re-run when either side moves.

---

## 1. Where the parser stands after L1–L5

**Method.** For each of 32 common system headers: preprocess with `clang -E`,
extract every `struct`/`union` body with a name (tag, or typedef declarator),
deduplicate by name across headers, and ask whether the compiler emits a
`%Name = type {…}` line for it in a program that does nothing but
`(import-use "<header>")`.

| | count |
|---|---|
| distinct named struct/union bodies | **111** |
| laid out (a `%Name = type` line is emitted) | **102** |
| blocked (registered opaque, `ptr:X` only) | **9** |

**The layout is not merely present, it is right.** Separately, for each of the
103 C types the same 32 headers cause to be emitted, `(sizeof T)` from Nucleus
against `sizeof` from clang:

| | count |
|---|---|
| **match** | **101** |
| mismatch | **1** — `epoll_event`, 16 vs 12 (`__attribute__((packed))`, §2) |
| no C oracle to compare against | 1 — `__locale_struct` (no exported spelling) |

Size alone is the weaker oracle — c-header-layout.md §1.5 records its own
correction on exactly this point, that `SDL_HapticConstant` matched on size while
every field after the first sat at the wrong offset. Offsets and alignment are
checked by `make layout-test` and `run_l2_layout_matrix`, which are green. The
101/103 figure is a second, broader net cast over the same water, not the
primary gate.

**The nine, by name and by cause:**

| type | header | blocked by |
|---|---|---|
All nine are **DONE** as of 2026-08-28; the "blocked by" column is what each one
was blocked by, and the item that closed it.

| type | header | was blocked by | closed by |
|---|---|---|---|
| ~~`sigaction`~~ | signal.h | inline function-pointer member (inside its named union) | FP-4 (§12) |
| ~~`sigevent`~~ | signal.h | inline function-pointer member | FP-4 (§12) |
| ~~`__pthread_cleanup_frame`~~ | pthread.h | inline function-pointer member | FP-4 (§12) |
| ~~`_pthread_cleanup_buffer`~~ | pthread.h | inline function-pointer member | FP-4 (§12) |
| ~~`sigcontext`~~ | signal.h | C11 anonymous union member | AN-1/AN-2 (§16) |
| ~~`rusage`~~ | sys/resource.h | C11 anonymous union member | AN-1/AN-2 (§16) |
| ~~`_IO_FILE` (`FILE`)~~ | stdio.h | **bitfield** — `int _flags2:24;` | BF-1…BF-4 (§15) |
| ~~`cmsghdr`~~ | sys/socket.h | flexible array member — `unsigned char __cmsg_data[];` | C1a (§16.3) |
| ~~`max_align_t`~~ | stddef | ~~`long double`~~ — **misattributed**; the blocker was a member `__attribute__((__aligned__(…)))` | PK-3 (§14.7) |

Section references are to [c-boundary-defects.md](c-boundary-defects.md).

Four shapes, plus one type-system item. `long double` was the same deferral
`design/stage3c.md` and `design/progress.md` already carried, and libclang would
not have moved it: the missing thing was a Nucleus type, not a parse. **Closed
2026-08-26** — c-boundary-defects.md §13, FL-1…FL-7.

Note what is *not* on this list. `stat`, `timespec`, `termios`, `dirent`,
`utsname`, `statvfs`, `fd_set`, `sockaddr_storage`, the `pthread_*` opaque
unions, `siginfo_t`, `itimerspec`, `jmp_buf`, `ucontext_t`, `msghdr`,
`sockaddr_in6` — every one of these was `WRONG` or `OPAQUE` in the §1.5 census
and every one now lays out correctly. `FILE` is the only marquee type still
opaque, and it is opaque for a reason (`_flags2:24`) that is one item, not a
class.

---

## 2. What each remaining item costs, and whether libclang would fix it

| item | blocks | mechanism | est. cost | libclang fixes it? |
|---|---|---|---|---|
| ~~**inline function-pointer member**~~ **DONE** (FP-4) | 4 of 9 | the branch already exists (`src/cheader.nuc:1398-1405`) and already collapses the field to `ptr` — it just calls `c-skip-parens` over `(*name)` without extracting `name`, so the following `c-read-ident` fails; and it does not clear `g-cheader-unrep` the way the parameter-position twin at `:776-786` does | **~15 lines**, one site | yes, incidentally |
| ~~**C11 anonymous member**~~ **DONE** (AN-1/AN-2) | 2 of 9 | body-parser feature plus a name-scoping question — an anonymous member's fields are addressable from the outer struct, and Nucleus has nothing to lower that onto | **medium**; the parse is small, the *language* question is the work | parse yes, language question no |
| ~~**bitfield**~~ **DONE** (BF-1…BF-4) | 1 of 9 (`FILE`) | no Nucleus type; a partial answer (correct total size and correct offsets for the non-bitfield members, bitfields inaccessible) is reachable, a complete one is a type-system item | **medium**, or **large** if done completely | gives the layout; does **not** give Nucleus a bitfield type |
| ~~**flexible array member**~~ **DONE** (C1a) | 1 of 9 | `[]` with no extent — a zero-extent trailing member. **`(array T 0)` could not be reused:** 0 is the prescan's provisional-length marker, so a flexible member is `(array T -1)` (c-boundary-defects.md §16.3) | **~10 lines**, and it was | yes, incidentally |
| ~~**`__attribute__((packed))`**~~ **DONE** (PK-1/PK-2) | 0 of 9, but 1 silent wrong size | was: `StructDef`/`abi-sizeof` must learn packing — reaches `defstruct` too | **medium**, type-system-adjacent | was: **yes, and cleanly** — libclang's strongest single case, and it was done without one (c-boundary-defects.md §14) |
| **bare `unsigned` / `signed`** (§3) | 0 of 9 in glibc; blocks third-party headers | declaration-specifier table gap | **~5 lines** | yes, incidentally |
| **with-body aggregate array typedef** | 0 occurrences surveyed | `c-parse-struct-decl:1467` reads the post-body name with `c-read-ident`, which stops at `[` | **~10 lines** | yes, incidentally |
| **multi-declarator field line** (`int a, b;`) | 0 of 9 in glibc | declarator loop | **~20 lines** | yes, incidentally |
| ~~**`long double` / `_Float128` / `_Float16`**~~ **DONE** (FL-1…FL-7) | 0 of 9 | was: no Nucleus type | type-system item | **no** — and it was done without one |

Adding up the parser-only rows: the four cheap ones are **~50 lines total** and
between them close inline function pointers (4 types, including `sigaction` — the
most-wanted name on the list), flexible arrays, third-party `unsigned`, and the
D4 residue. That is one focused session, not a project.

The genuinely hard rows — anonymous members, bitfields, packing — are hard
*because of the type system*, and libclang only pays for one of the three
(packing) outright.

**Outcome (2026-08-28).** Every row that blocked a census type is closed, and
the estimates held except for the one marked hardest. Anonymous members were
priced "medium; the parse is small, the *language* question is the work" — but
the language question had already been paid for by FR-1, which bitfields needed
anyway, so AN-1/AN-2 came to two functions and a fall-through
(c-boundary-defects.md §16.1). Bitfields were the expensive item, and not for
the reason given: the type was straightforward, and the cost was that C leaves
allocation implementation-defined and the three targets Nucleus supports
genuinely disagree (§15.4). Three rows remain open and block nothing measured:
bare `unsigned`/`signed`, the with-body aggregate array typedef, and the
multi-declarator field line.

---

## 3. Two defects this evaluation turned up that §6 does not list

Both found while probing whether Nucleus could bind libclang at all, which is
itself the point: the tail of C's declaration grammar keeps producing these.

**A bare `unsigned` or `signed` is not a type.** `unsigned x;` as a struct member
abandons the struct; `unsigned f(void);` is dropped entirely. `unsigned int`
works, `unsigned char/short/long` work, `long unsigned` works — only the bare
form fails.

```
struct T01 { unsigned a; int b; };   → opaque   (clang: 8)
struct T02 { signed a;   int b; };   → opaque   (clang: 8)
struct T03 { unsigned char a; int b; };  → 8 ✓
```

Zero occurrences in the glibc headers surveyed — they are written pedantically —
which is exactly why the census never saw it. It is common in third-party
headers, and **libclang's own `clang-c/Index.h` is one of them**: `CXString` is
`{ const void *data; unsigned private_flags; }` and most of the API returns bare
`unsigned`. The dev headers are not installed in this container, so that last
claim is from the published API rather than a local read; the *shape* is verified
locally (§4.1's probe reproduces it).

**The diagnostic for it is the weak one.** The declaration is dropped without
being recorded in `g-cheader-skipped`, so the use site says
`unknown: 'f_bare' — not defined anywhere in this compilation unit` rather than
Stage 15 W3c's `… its C header declaration was skipped (<reason>)`. A user has no
thread to pull. Whatever else is done here, that path should record a reason —
the two-tier warning policy is only as good as its coverage.

**The inline function-pointer branch is half-built, not absent.** §6 describes
this item as "a body-parser addition". It is smaller than that: the branch is
there and already does the type collapse; it drops the field *name* on the floor.
`int (*f)(int)`, `void (*f)(int)` and `struct S (*f)(int)` all fail identically,
and a typedef'd `cb f;` works — consistent with the name being the loss, not the
type.

---

## 4. What switching to libclang would actually involve

### 4.1 Feasibility is proven, with three frictions

I built a header modelling libclang's actual calling conventions — `CXCursor`
(32-byte by-value struct with an array member), `CXString` (16-byte by-value
return), and `clang_visitChildren`'s callback taking *two* by-value cursors —
implemented it in C, and drove it from Nucleus. It works:

```
root kind=2
  field xdata=0 name=alpha parent-kind=2
  field xdata=1 name=beta  parent-kind=2
  field xdata=2 name=gamma parent-kind=2
visited=3
```

By-value struct arguments, by-value struct returns, and a **Nucleus function used
as a C callback receiving by-value structs** all work through the Stage 8 SysV
ABI. There is no ABI blocker. The frictions:

1. **The callback must be laundered.** A function-pointer *parameter* collapses
   to `ptr` (`c-parse-func-decl:776-786`), so passing a Nucleus function requires
   `(unsafe/cast ptr visit)` and loses all arity/type checking at the boundary —
   in the one place a mistake is a silent stack corruption.
   *Fixed — [c-boundary-defects.md](c-boundary-defects.md) FP-1/FP-4: the
   importer builds a real `TY-FN` and every typed slot now compares signatures.*
2. **Every field read of a by-value cursor needs an alloca-and-store.**
   `(. cursor kind)` is an error; the documented idiom is
   `(let (q:ptr:CXCursor (alloca CXCursor)) (ptr-set! q cursor) (. q kind))`.
   libclang's API is *entirely* by-value cursors, so a real binding pays this on
   every access.
   *Fixed — SV-1: `(. cursor kind)` compiles. Note the idiom quoted here was
   already one step longer than the language required; `(addr-of cursor)`
   sufficed.*
3. **The bare-`unsigned` gap of §3 must be fixed first**, or `clang-c/Index.h`
   cannot be imported at all. (Avoidable: hand-write the binding as ~200 explicit
   `declare` forms and import no C header. That trades the parser dependency for
   a hand-maintained API surface that silently rots across libclang versions —
   which is worse, not better, because nothing checks it.)
   *Staged as C1.*

### 4.2 What it costs

**The dependency is smaller than it looks.** `bin/nucleusc` already links
`libLLVM.so.19.1` (129 MB) and already shells out to `clang` for both
preprocessing (`src/cheader.nuc:977`) and linking. libclang is +38 MB against
that, and the compiler is *already* pinned to an LLVM major version. The usual
"don't add a heavyweight dependency" argument mostly does not apply here —
which is the strongest thing that can be said for the libclang side.

What remains is packaging friction, and it is real: this container has
`libclang-19.so.1` but **no `clang-c/` headers and no unversioned `.so`
symlink**. Linking needs the `-dev` package or `dlopen` with a version search;
either way the compiler acquires a second version-stamped LLVM coupling and a
new failure mode for users who have clang but not libclang-dev.

**Performance is a wash, possibly a small win.** Timed, three runs each:

| | wall |
|---|---|
| `nucleusc` on a no-header program | 195 ms |
| `nucleusc` on `(import-use "stdio.h")` | 298 ms |
| `clang -E -x c -include stdio.h /dev/null` alone | 101 ms |
| `clang -fsyntax-only` (proxy for a full parse) | 108 ms |

The hand-rolled parse is **free to the resolution of this measurement** — the
entire 103 ms delta is the `clang -E` subprocess the compiler already pays. A
full clang parse costs ~2 % more than preprocessing on a header this size, and
libclang would run in-process with no fork. Perf argues for neither side.

**The replaceable surface is ~1,314 lines.** `src/cheader.nuc` is 3,085 lines,
but lines 2044–3085 are `--emit-cheader`, the Nucleus→C *writer*, which libclang
has nothing to do with. A libclang binding — cursor visiting, kind dispatch, type
mapping, `CXString` lifetime management, diagnostics, plus the alloca dance at
every access — is plausibly 600–1,000 lines of Nucleus. **This is not a
line-count win.** It is a correctness-per-line win, and only on the shapes it
covers.

**And it is bootstrap-visible.** Every header the compiler's own source imports
would be re-read by a different front end, so the emitted IR moves and the boot
has to reconverge — the same characterized-diff exercise §1.6 and §5 of
c-header-layout.md specify, but over the whole surface at once rather than five
type lines.

### 4.3 What it buys that the hand-rolled parser cannot get cheaply

Three things, honestly stated:

- **`clang_Type_getSizeOf` / `getAlignOf` / `getOffsetOf`.** Packing,
  `aligned`, `may_alias`, bitfield placement — every layout attribute, correct,
  for free, forever. This is the one row in §2's table that libclang wins
  outright, and it also retires the entire *class* that `epoll_event` represents
  rather than one instance.
- **Target-correct headers.** `src/cheader.nuc:977` runs
  `clang -E -x c -include <h> /dev/null` with **no `--target` and no
  `-isysroot`**, so a cross-compile reads host headers. libclang takes the same
  argument vector as the driver, so passing the target through is natural rather
  than a retrofit. This matters to the AVR and RISC-V tracks
  (`design/stage14/avr-targets.md`, `riscv-linux.md`) — though note the AVR
  examples today import `lib/avr.nuc`, not C headers, so nothing currently
  exercises it.
- **Immunity to the §3 class.** No more declaration-specifier surprises, ever.

### 4.4 What it does not buy

- ~~`long double` / `_Float128` / `_Float16`~~ — was 156 correctly-refused
  declarations and a **type-system** item on either path. Done 2026-08-26 as
  `f80`/`f128`/`f16` (c-boundary-defects.md §13), which is the shape of the
  point: libclang would not have moved it either way.
- Bitfields *as a Nucleus surface* — libclang tells you where the bits are; it
  does not tell Nucleus how to spell a field that occupies 24 of them.
- Anonymous-member name scoping — same: a language design question, not a parse.
- The `--emit-cheader` writer, ~1,000 lines, untouched either way.
- The `clang` **binary** dependency, which stays regardless.

So of the three genuinely hard items in §2, libclang pays for **one**.

---

## 5. The asymmetries that decide it

1. **The residue is enumerable, and the census that motivated the rewrite is
   stale.** 70 % blocked justified re-architecting. 8 % blocked, by name, with
   four of nine falling to one small repair, does not.
2. **The expensive items are on the wrong side of the boundary.** Bitfields and
   anonymous members are hard because Nucleus has no way to *express* them. A
   better front end hands you a correct answer to a question the language cannot
   yet ask.
3. **Nucleus's own layout engine is already validated.** 101 of 103 C types match
   clang's `sizeof`, and `make layout-test` compares offsets and alignment.
   `abi.nuc` is not the weak link; the reader is. Replacing the reader to obtain
   layout facts the emitter already computes correctly buys packing and nothing
   else.
4. **Failure is already safe, and that is load-bearing.** Since W3b an
   unrepresentable declaration is skipped with a located reason, and since L1 an
   unreadable body goes opaque rather than mis-sized. A parser gap costs a named
   missing symbol, not a corrupted stack. This is what makes "close the gaps as
   they surface" a viable long-term posture instead of a slow leak — and §3's
   bare-`unsigned` finding is the exception that proves it needs one repair.
5. **The one thing worth having is separable.** Packing and target-correct
   headers are the real prizes. Packing can be had by teaching `StructDef` about
   it — needed for `defstruct` anyway, so it is not wasted work. Target headers
   are a flag on the `clang -E` line the compiler already builds, plus a sysroot
   question that libclang would not answer either.

---

## 6. Recommendation and staging

**Finish the parser. Take the cheap items now, the type-system items on their own
merits, and leave libclang as a live option with a stated trigger.**

- **C1 — the ~50-line tranche.** Inline function-pointer members (extract the
  name in the existing branch; clear `g-cheader-unrep` the way `:776-786` does,
  or an aggregate met inside the function pointer's own signature leaks into the
  enclosing struct's verdict and converts a working case into a refusal); bare
  `unsigned`/`signed`; flexible array members; the with-body aggregate array
  typedef. Unblocks `sigaction`, `sigevent`, both pthread cleanup structs,
  `cmsghdr`, and third-party headers generally. Highest value per line in the
  whole document.
  **Partly done.** Function-pointer members landed as FP-4 and flexible array
  members as C1a (c-boundary-defects.md §12, §16.3) — between them every census
  type this row named. Bare `unsigned`/`signed` and the with-body aggregate
  array typedef are still open; neither blocks a measured type.
- **C2 — record a reason on every skip path.** §3's second finding. Small, and it
  is what makes "fail safe" mean "fail *legibly*". Should ride with C1.
- **C3 — `__attribute__((packed))`.** Its own item, as §6 says, because it is a
  `StructDef`/`abi-sizeof` change that reaches `defstruct`. Retires the
  `epoll_event` class and is the one thing libclang would otherwise be bought
  for.
- **C4 — target-correct preprocessing.** Pass `--target=` / `-isysroot` into the
  `clang -E` invocation at `src/cheader.nuc:977` when compiling for a non-host
  target. Independent of everything else here, and a prerequisite for the AVR and
  RISC-V tracks whichever front end reads the headers.
- **Defer** anonymous members and bitfields with the existing `long double`
  deferral. They fail safe; `FILE` staying opaque costs a `ptr:FILE` handle,
  which every real user of `FILE` wanted anyway.

## 7. When this answer flips

Re-open the question if any of these becomes true:

- **A target's headers become the point.** If Nucleus starts importing C headers
  for AVR/RISC-V rather than using native `lib/avr.nuc` definitions, target-aware
  parsing stops being a nicety. libclang makes it a parameter; the current design
  makes it a retrofit.
- **Bitfields or anonymous members get a Nucleus surface.** Once the language can
  *express* them, the remaining cost is parsing — and that is the half libclang
  is good at. Deciding to implement either is the moment to re-price this.
- **A third §3-class defect appears in a header someone actually needs.** Two is
  a tail. Four would be a pattern, and a pattern in the declaration-specifier
  grammar is the argument this document could not make today.
- **C++ headers come into scope.** Not on any roadmap, and the hand-rolled parser
  would not be extended to them under any circumstances.

Until then: the parser is 92 % of the way there, the next 4 % is fifty lines, and
what is left after that is not a parsing problem.

---

## 8. The re-price: trigger 2 fired, and the answer holds

**2026-08-26.** [c-boundary-defects.md](c-boundary-defects.md) §§6–9 decides to
implement bitfields *and* anonymous members *and* `packed` *and* the wide float
types. That is §7's second trigger, verbatim, so this is a re-price and not a
restatement.

**The answer does not flip. It gets stronger — and one of §5's arguments has to
be withdrawn to say so honestly.**

### 8.1 What was wrong in §2 and §5

§2 priced anonymous members as "the parse is small, the *language* question is
the work", and §5.2 generalised that: "bitfields and anonymous members are hard
because Nucleus has no way to *express* them. A better front end hands you a
correct answer to a question the language cannot yet ask."

**For anonymous members that premise is stale**, and it was stale when written.
Measured: clang's model of a C11 anonymous member is an ordinary nested member
with its own type (`%struct.Anon = type { i32, %union.anon, %struct.anon }`),
read from outside by a two-level GEP. Nucleus has had exactly that since Stage
10 — `lookup-or-make-anon-struct` / `lookup-or-make-anon-union`
(`src/union-registry.nuc:63`, `:107`) — and `src/cheader.nuc:1445` **already
calls the first of them**. The layout, the IR type, the ABI classification and
by-value passing all work today. The only missing piece is name lookup *through*
the member. There was no language question; there was a lookup function.

So trigger 2's logic — "once the language can express them, the remaining cost is
parsing, and that is the half libclang is good at" — does not apply to the item
it was written for. And for bitfields it applies only halfway (§8.3).

### 8.2 The measurement that decides it

Count what §§6–9 actually consists of, by where the code goes:

| item | in `cheader.nuc` | everywhere else |
|---|---|---|
| wide floats | FL-7 (a specifier-table entry) | FL-1…FL-6: type roster, constant renderers, hex literals, X87/SSEUP classes, varargs, AVR gate |
| `packed` | PK-2 (read one attribute) | PK-1, PK-3: `StructDef`, layout, eight IR-type sites, load/store alignment |
| bitfields | BF-4 (parse `: width`) | FR-1, BF-1…BF-3: field-reference descriptor, storage-unit allocator, shift/mask lowering, `defstruct` surface |
| anon members | AN-1 (call the existing memoizer) | AN-2: transitive lookup + ambiguity rule |

**Four of roughly fifteen items are parser work.** libclang replaces those four
and none of the other eleven. §4.2 measured the replaceable surface at 1,314 of
`cheader.nuc`'s 3,085 lines; §§6–9 adds substantial work to the compiler and
almost none to that 1,314.

The reason is structural, and it is the argument this section exists to make:
**every one of these features has a Nucleus-native side that no C front end can
serve.** `defstruct` must be able to declare a bitfield and a packed struct
(BF-3, PK-2), and `--emit-cheader` must be able to *write* both back out as C. A
Nucleus-declared packed struct has no clang cursor to interrogate. So the layout
algorithms — bitfield storage-unit allocation, packing, over-alignment — must be
implemented in `abi.nuc` regardless of which front end reads the headers.

That moves libclang's value from §2's "pays for one of the three hard items"
down to **"pays for the import half of items that must be implemented anyway"**,
and it takes `packed` — the one row §2 conceded outright — down with it, because
`abi-struct-size` has to learn packing for `defstruct` either way.

### 8.3 Where libclang genuinely would still help, and the cheaper way to get it

One point survives, and it is a real one. Bitfield allocation is
target-parameterised and only partly specified by the standard;
`clang_Cursor_isBitField` / `clang_getFieldDeclBitWidth` /
`clang_Cursor_getOffsetOfField` would hand over the answer, correct on every
target, forever. §4.3's strongest claim, restated for the item that now matters
most.

**And the existing gate cannot check it.** `tests/run-layout-test.sh` compiles
`layout.c` with the platform `cc` and *runs* both binaries, so it validates the
**host only**. Bitfield and packing rules differ per target, and Nucleus already
cross-compiles to AVR and riscv64.

The cheap way to get the property without the dependency:
**`clang --target=<triple> -ffreestanding -fsyntax-only` over a generated C file
of `_Static_assert`s.** No execution, no sysroot, no libclang, no linking — a
pure compile-time oracle for `sizeof`, `offsetof` and any layout predicate, on
every target clang supports. Verified here on x86_64, aarch64, riscv64 and avr,
including that a wrong assertion is a hard failure:

```
o2.c:3:16: error: static assertion failed due to requirement 'sizeof(struct BF) == 8'
```

It immediately paid for itself. The same bitfield struct

```c
struct BF { int a:3; unsigned b:5; short c:9; int d; };
```

is 8 bytes on x86-64 and **not** 8 on AVR, where `int` is 16-bit — and
`int c:24` is not merely laid out differently there, it is a hard error
(`width of bit-field 'c' (24 bits) exceeds the width of its type (16 bits)`).
A host-only differential test would have shipped a wrong AVR bitfield layout in
silence.

So the honest form of libclang's remaining advantage is: *clang* should be the
layout oracle, which it already is — the argument is for widening the existing
differential test to every target, not for linking a second LLVM library into
the compiler. That is a test-harness change, and it belongs in
c-boundary-defects.md §11 regardless of which front end wins.

### 8.4 What did not change

§4.2's costs stand unaltered: this container still has `libclang-19.so.1` with
no `clang-c/` headers and no unversioned symlink; the binding would still be
600–1,000 lines of Nucleus and is still not a line-count win; and it is still
bootstrap-visible across the whole header surface at once. Against that, §§6–9's
verdict is that the parser work remaining is four small items, three of which
(`: width`, one attribute, one existing call) are near-trivial.

**Recommendation unchanged: finish the parser.** The trigger fired, the price was
recomputed, and the item that was supposed to argue for libclang turned out to
be nine-tenths built already. §7's other three triggers stand as written; the
second is now retired, and what should replace it is narrower:

- **Re-open if a third *target* acquires a layout rule Nucleus gets wrong.** Not
  "bitfields exist" but "the hand-written allocator disagrees with clang on a
  target we ship", which §8.3's cross-target oracle now makes a measurable event
  rather than a judgement call.
