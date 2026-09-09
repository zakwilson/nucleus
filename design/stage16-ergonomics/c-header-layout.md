# Stage 16 — What a C header import loses

**Status: Implemented 2026-08-26.** All five staged items (L1–L5) landed, in
the sequence §4 gives (L1 → L2 → L3 → L5 → L4). 834 tests (was 813 at design
time — +20 unit assertions across the new gates, +1 example),
`make bootstrap` converges, `make abi-test` / `make layout-test` /
`make check-headers` (69/69) all green. Every measurement in this document was
taken against `build/nucleusc` on 2026-08-25, before implementation — not
`bin/nucleusc`, which is the committed bootstrap and lags the tree — and
several turned out to need correction once the fix was built; those
corrections are marked in place below rather than silently folded in, since
this document is the record of what was measured and when. See
[docs/structs-unions.md](../../docs/structs-unions.md) (C header struct
ingestion, array members, typedefs, `returns_twice`) and
[examples/setjmp-guard.nuc](../../examples/setjmp-guard.nuc) (§7's worked
example, now a running test) for the user-facing result. **§8 (2026-08-29)
closes three further §6 deferrals — CD-1/CD-2/CD-3, the declarator-grammar
ones.**

**The goal this serves.** Nucleus is a drop-in replacement for C. It must be
usable anywhere C is usable, so it must be possible to obtain **any** required
libc detail from a pure Nucleus program — a layout, a size, a calling
convention, an attribute a call's correctness depends on. Today it is not:
`(import-use "setjmp.h")` gives `struct __jmp_buf_tag` a 24-byte layout where C
says 200, with no error and no warning, and hands the resulting `alloca` to
`setjmp`.

**The cost constraint, in the user's words:** *"If this adds 200 bytes to the
compiler itself, that's trivial. It must not add size to compiled Nucleus
programs that don't actually use it."* §1.1 shows that constraint is **already
met by the existing architecture** and that none of the work below has to invent
a cost story — only preserve one.

**This is not a setjmp document.** `setjmp` is the case that exposed the defect
and it is the worked example in §7, but L1–L3 are general: anything in libc whose
layout passes through a typedef or an opaque tag is imported at the wrong size
today, silently. §1.5 measures how much of libc that is.

---

## 1. Ground truth (verified 2026-08-25 against `build/nucleusc`)

Nucleus already imports real C headers. `(import-use "setjmp.h")` works today:
`emit-c-include` (`src/cheader.nuc:1582`) shells out to
`clang -E -x c -include <path> /dev/null` (`src/cheader.nuc:983`, cached by path
at `:974`) and registers structs, typedefs and externs from the preprocessed
text.

### 1.1 The cost constraint is already met

Two programs, identical but for one import:

```
mkdir -p /tmp/a /tmp/b
printf '(import-use "stdio.h")\n(defn main ():i32 (printf "hi\\n") (return 0))\n' > /tmp/a/prog.nuc
printf '(import-use "stdio.h")\n(import-use "setjmp.h")\n(defn main ():i32 (printf "hi\\n") (return 0))\n' > /tmp/b/prog.nuc
build/nucleusc /tmp/a/prog.nuc -o /tmp/a/prog
build/nucleusc /tmp/b/prog.nuc -o /tmp/b/prog
cmp /tmp/a/prog /tmp/b/prog     # silent
```

Both link to **15848 bytes, byte-identical**. LLVM type definitions are
compile-time only and cost nothing in the object; unused imported functions are
reclaimed at the link by the section-based stripping Stage 16 built
(`ir-sections-on` / `write-ir-section`, `-Wl,--gc-sections`, recorded in
[overview.md](overview.md) under `macrolet`). Importing a header a program does
not use is free today, and every item below leaves that property untouched:
L1–L3 change which `%X = type {…}` lines are written and which `declare` lines
are emitted, neither of which survives to the binary unless called; L4 adds one
LLVM keyword to one `declare`.

> **Methodology note for whoever re-runs this.** The two programs must have the
> same *basename*. A first attempt with `/tmp/c1.nuc` and `/tmp/c2.nuc` differed
> in exactly one byte at offset 13297 — `'1'` versus `'2'` — because the binary
> embeds the source basename. That single byte reads as a cost difference and is
> not one.

### 1.2 The defect

```
printf '(import-use "stdio.h")\n(import-use "setjmp.h")\n(defn main ():i32 (printf "%%d\\n" (sizeof __jmp_buf_tag)) (return 0))\n' > /tmp/sj.nuc
build/nucleusc /tmp/sj.nuc -o /tmp/sj && /tmp/sj      # prints 24
printf '#include <setjmp.h>\n#include <stdio.h>\nint main(){printf("%%zu\\n", sizeof(struct __jmp_buf_tag));}\n' > /tmp/sj.c
clang /tmp/sj.c -o /tmp/sjc && /tmp/sjc               # prints 200
```

```
%__jmp_buf_tag = type { ptr, i32, ptr }     Nucleus: 24 bytes
                                            C:      200 bytes
```

No error, no warning — `(import-use "setjmp.h")` produces **zero** stderr output
today. `(alloca __jmp_buf_tag 1)` handed to `setjmp` smashes 176 bytes of stack.

Isolated with a four-line probe header:

```c
/* /tmp/probe.h */
typedef long probe_arr[8];
typedef struct { unsigned long v[4]; } probe_agg;
struct probe_s { probe_arr a; int b; probe_agg c; };
struct probe_direct { long a[8]; int b; };
```

| member spelling | behaviour |
|---|---|
| `long a[8];` — a **direct** array member | the struct-body parser abandons on `[` (`src/cheader.nuc:1178-1182`) → the type stays opaque → `(sizeof probe_direct)` is a clean located error: `'probe_direct' is an opaque type declared at /tmp/probe.h:4; only pointers to it are valid`. **Fails safe.** |
| `probe_arr a;` — an array **behind a typedef** | the parser never sees `[`; the name resolves to nothing and becomes `ptr` → `%probe_s = type { ptr, i32, ptr }`, **24 bytes against C's 104**. **Fails silently wrong.** |

glibc hides *both* of `jmp_buf`'s large members behind typedefs — `__jmp_buf` is
`typedef long int __jmp_buf[8]`, `__sigset_t` is
`typedef struct { unsigned long int __val[16]; } __sigset_t` — so every field
carrying the size takes the silent path:

```c
struct __jmp_buf_tag {
    __jmp_buf __jmpbuf;          /* -> ptr  (64 bytes lost) */
    int       __mask_was_saved;  /* -> i32  (correct)       */
    __sigset_t __saved_mask;     /* -> ptr  (128 bytes lost)*/
};
```

### 1.3 The rule is already written in the tree, two call sites short

`src/cheader.nuc:583-585`, inside `c-parse-type`:

> *W3c: a BY-VALUE type we could not resolve. The spec's rule for §1.4 is that a
> typedef the parser cannot follow must be an error or a skip, never a silent
> `ptr` — so keep `ptr` in the Type (a TY-STRUCT with no layout would put an
> undefined `%X` in the IR) but mark the enclosing declaration…*

`cheader-mark-unrep` (`src/cheader.nuc:75`) implements exactly that, and
`c-parse-type` already raises it on **every** shape that matters:

| position in `c-parse-type` | shape |
|---|---|
| `:529` | a by-value aggregate whose `{…}` body the parser could not read |
| `:554` | a by-value `struct Tag` whose tag is opaque or unknown |
| `:596` | a by-value `long double` |
| `:599` | a by-value name recorded in the typedef table as unrepresentable |
| `:602` | a by-value name that resolves to nothing at all |

The flag has exactly two consumers, and neither is a struct member:

- **`c-parse-func-decl`** clears it at entry (`:718`), seeds the declaration-level
  verdict from the return type (`:750`), clears it per parameter (`:783`),
  accumulates after the post-parse overrides (`:826-828`), and feeds
  `c-decl-skip-reason` (`:868`), which turns it into a skip.
- **`c-parse-typedef-decl`** save/clears it around its own `c-parse-type` call
  (`:1367-1383`) and records the typedef as known-but-unrepresentable when it
  fires (`:1425`).

**`c-parse-struct-body` does not.** It calls `c-parse-type` at
`src/cheader.nuc:1158`, takes the returned `ptr`, and stores it as the field's
type at `:1187`. That single missing check is the whole of D1.

The user's brief said the rule was "wired only at the by-value parameter/return
boundary". It is wired at *two* boundaries — and the second one,
`c-parse-typedef-decl:1367-1383`, is a literal working template for the
save/clear/check/restore discipline the struct-body loop needs (§3.1).

### 1.4 A second, independent defect: an array typedef does not decay

`jmp_buf` is `typedef struct __jmp_buf_tag jmp_buf[1];` — an **array** typedef.
`c-parse-struct-decl`'s no-body branch reads the declarator identifier at
`src/cheader.nuc:1272` and never looks for a following `[`, so `jmp_buf` is
registered as a plain struct alias of `__jmp_buf_tag` and the `[1]` is discarded.
The emitted declarations (**historical — before L3**; see §7 for the
post-L3/L4 result):

```
declare i32  @setjmp(ptr byval(%jmp_buf) align 8)
declare i32  @__sigsetjmp(ptr, i32)
declare i32  @_setjmp(ptr)
declare void @longjmp(ptr, i32) noreturn
declare void @siglongjmp(ptr byval(%sigjmp_buf) align 8, i32) noreturn
```

C decays an array parameter to a pointer. So `setjmp` and `siglongjmp` have the
wrong **calling convention**, independently of the wrong size — fixing L1 and L2
alone would give them a correct 200-byte `byval` where C passes one word.

Note what the same listing proves: `__sigsetjmp` and `_setjmp`, declared
`struct __jmp_buf_tag __env[1]` with a *syntactic* array declarator, come out
`ptr` correctly. **The decay rule already exists** — `c-parse-func-decl:810-823`
consumes `[N]` after a parameter name, sets `ptype` to `ty-ptr` and clears the
unrep flag, with a comment naming `utimensat` as the case that forced it. It
just cannot see through a typedef, because the typedef table has no array type
to carry.

### 1.5 The survey — how much of libc is affected

**Layout comparison, 15 headers.** For each `%X = type {…}` the importer emits,
`(sizeof X)` from Nucleus against `sizeof` from clang:

| header | comparable structs | wrong |
|---|---|---|
| `stdio.h` | 4 | **3** — `__fpos_t` 24/16, `__fpos64_t` 24/16, `__mbstate_t` 16/8 |
| `setjmp.h` | 3 | **3** — `__jmp_buf_tag`, `jmp_buf`, `sigjmp_buf` all 24/200 |
| `signal.h` | 10 | **3** — `siginfo_t` 24/128, `sigevent_t` 24/64, `_xstate` 24/832 |
| `netinet/in.h` | 18 | **5** — `in6_addr` 8/16, `sockaddr_in6` 24/28, `ipv6_mreq` 16/20, `group_req` 16/136, `group_source_req` 24/264 |
| `pthread.h` | 9 | **3** — `__jmp_buf_tag`, `__cancel_jmp_buf_tag` 16/72, `itimerspec` 16/32 |
| `time.h` | 2 | **1** — `itimerspec` 16/32 |
| `stdlib.h`, `string.h`, `unistd.h`, `fcntl.h`, `sys/stat.h`, `sys/select.h`, `dirent.h`, `termios.h`, `sys/socket.h` | 19 | 0 |
| **total** | **65** | **18 rows, 16 distinct types** |

**Usability classification, 34 named libc types.** Four outcomes: `OK`, `WRONG`
(silently mis-sized), `OPAQUE` (registered, refused at every by-value use with a
located error), `ABSENT` (never registered at all):

| verdict | count | types |
|---|---|---|
| **OK** | 12 | `tm`, `timeval`, `pollfd`, `rlimit`, `iovec`, `addrinfo`, `hostent`, `passwd`, `group`, `winsize`, `div_t`, `msghdr` |
| **WRONG** | 4 | `jmp_buf` 24/200, `siginfo_t` 24/128, `itimerspec` 16/32, `epoll_event` 16/12 |
| **OPAQUE** | 14 | `FILE`, `stat`, `timespec`, `dirent`, `termios`, `fd_set`, `sigaction`, `pthread_attr_t`, `pthread_mutex_t`, `pthread_cond_t`, `utsname`, `rusage`, `statvfs`, `lconv` |
| **ABSENT** | 4 | `fpos_t`, `sigset_t`, `sockaddr`, `sockaddr_in` |

**What blocks a struct body, censused.** Over 30 common headers, 232 distinct
struct/union bodies, deduplicated by type name; a body may carry more than one
shape:

| shape | bodies |
|---|---|
| array member with a **literal** extent (`char sa_data[14]`) | 132 |
| *(parseable today)* | 69 |
| array member with a **constant-expression** extent (`char __ss_padding[(128 - sizeof(unsigned short) - sizeof(unsigned long))]`) | 28 |
| a `#` **linemarker inside the body** | 6 |
| an **anonymous** (unnamed) struct/union member | 2 |
| a **bitfield** | 1 |

**163 of 232 bodies (70 %) contain at least one shape the body parser cannot
read.** Array members are the overwhelming majority, and 132 of the 160 array
bodies need nothing but a literal extent.

**The honest half of the survey.** Most of that 70 % fails *safe*: the body
parser abandons the struct, and the prescan's name-only registration
(`cheader-scan-opaque-decl:1537-1538`) leaves it opaque, so `ptr:X` still works
and every by-value use gets a located error. The **silent** class is narrower and
specific: it is exactly a struct whose member reaches an unparseable body
*indirectly* — through a typedef name, or through a tag that is opaque because
its own body failed. That is 16 types out of 65 comparable, not 163 out of 232.
The user's framing expected worse breadth; the breadth is in *unusability*, and
the silence is in a smaller, sharper set. Both are worth fixing and they are the
same fix.

**Correction: this survey's own oracle undercounts the defect class, because it
compares `sizeof` only.** `SDL_HapticConstant` was 40 bytes under *both* clang
and the broken importer — a size-only check calls that OK — while every field
offset after the first was wrong (4/20/24 against clang's 0/8/16) and the
struct's alignment was 4 where clang says 8. A struct can match on total size
while every member inside it is misplaced. The right oracle is offsets and
alignment, not size alone, and the gates this document specifies in §5
(`run_l2_layout_matrix`, `make layout-test`) do compare them — this correction
is to the survey's methodology, not to the shipped gates.

Two rows in the table above are **not** L1–L4's doing and are called out so
nobody credits the fix with them:

- **`epoll_event` 16/12** — `struct epoll_event { uint32_t; epoll_data_t; } __EPOLL_PACKED;`.
  Both members resolve correctly; Nucleus ignores
  `__attribute__((packed))`. A separate silent-wrong defect (§6).
- **`rusage`** is opaque because of C11 **anonymous union members**
  (`__extension__ union { long ru_maxrss; __syscall_slong_t __ru_maxrss_word; };`),
  not arrays. L2 does not reach it (§6).

**A third defect the census turned up.** `struct timespec` — two scalar fields,
nothing exotic — is `OPAQUE`. The reason is that `clang -E` emits a `#` linemarker
*inside* the body:

```
struct timespec
{
  __time_t tv_sec;
  __syscall_slong_t tv_nsec;
# 31 "/usr/include/x86_64-linux-gnu/bits/types/struct_timespec.h" 3 4
};
```

`c-skip-ws` (`src/cheader.nuc:304`) skips whitespace only, so `#` is read as a
field type, fails, and the struct is abandoned. Isolated:

```c
/* /tmp/lm.h */
struct lm_plain { long a; long b; };
struct lm_marked {
  long a;
#line 100 "lm.h"
  long b;
};
```
→ `%lm_plain = type { i64, i64 }` is emitted; `lm_marked` is opaque.

This matters to the staging because `struct timespec`, `struct stat` (which
contains three of them) and `struct itimerspec` are blocked by the linemarker,
not by arrays — so L2 does not deliver them unless the linemarker is fixed
first. `src/cheader.nuc:37-39` already records that "a linemarker inside a struct
body is not re-read", as a caveat on *provenance*; it is also a parse failure.

### 1.6 What the standard IR-neutrality sweep can and cannot see here

Stage 16's standard bar is: compile all `examples/*.nuc` (152) and `lib/*.nuc`
(34) with `--emit-llvm` on a baseline binary and on the rebuilt one, `diff -rq`
on `.ll` + stdout + stderr + exit code — 186 modules — plus the 96 `--emit-nuch`
/ `--emit-cheader` outputs. It is the right bar for a change that must be
output-neutral. **L1 and L2 are not output-neutral, and the sweep is also
structurally blind to most of what they change.**

Both halves are measured.

**It is blind.** The entire tree's C-header surface is six headers. Counting
every `(import-use "…")` string across `examples/`, `lib/`, `src/` and `tests/`:
`stdio.h` ×236, `stdlib.h` ×56, `string.h` ×30, `unistd.h` ×10, `fcntl.h` ×2,
`ctype.h` ×1, plus `SDL2/SDL.h` ×3 and `SDL2/SDL_mixer.h` ×1 which appear only in
`tests/run-tests.sh`. Between them those six expose **14 comparable struct types**
(§1.5) — nothing from `signal.h`, `netinet/in.h`, `pthread.h`, `setjmp.h` or
`time.h`. A change that made every one of those headers worse would sweep clean.

**It is also not neutral.** Measured by compiling all 186 modules and grepping
the emitted IR: **163 of 186 emit `%__mbstate_t` or `%__fpos_t`.** A plain
`stdio.h` program's type section is:

```
%__anon_struct_he5cf22d31dd608e2 = type { i32, ptr }
%__mbstate_t                     = type { i32, ptr }
%__anon_struct_h8f97946030562cba = type { i64, %__mbstate_t }
%__fpos_t                        = type { i64, %__mbstate_t }
%__fpos64_t                      = type { i64, %__mbstate_t }
```

All five are wrong, and all five are **referenced by nothing but each other** —
`%__fpos_t` and `%__fpos64_t` occur exactly once each in the module, in their own
definitions. Under L1 all five disappear (the bodies now fail to parse, the
prescan leaves the names opaque, no by-value use exists to diagnose). Under L2
they come back correct — and the two `__anon_struct_hXXXX` names **change**,
because an anonymous C struct is memoized by content hash
(`lookup-or-make-anon-struct`), so fixing the content renames the type.

So the acceptance bar for L1 and L2 cannot be "the sweep is clean". It has to be
a **characterized diff**: the sweep's output diff must consist of exactly the
`%X = type` lines for the types named in §1.5, and nothing else — no changed
`declare`, no changed `define`, no changed stderr. §5 states that as a gate.

---

## 2. The defects

| id | one-liner | site |
|---|---|---|
| **D1** | A C struct member whose type the parser cannot represent is stored as `ptr`, silently, though `c-parse-type` already raised the unrepresentable flag for it. | `src/cheader.nuc:1158` + `:1187` (the flag is at `:75`, raised at `:529`/`:554`/`:596`/`:599`/`:602`, consumed only at `:750`/`:826`/`:868` and `:1367-1383`) |
| **D2** | The C body parser has no array member type at all: `[` after a field name abandons the whole struct. | `src/cheader.nuc:1178-1182` |
| **D3** | A `#` linemarker inside a struct body is read as a field type and abandons the struct — `clang -E` puts them there, and `struct timespec` is the casualty. | `src/cheader.nuc:304` (`c-skip-ws`), used at `:1153`/`:1162`/`:1177`; the top-level loop handles `#` correctly at `:1604-1613` |
| **D4** | An array typedef of an aggregate with **no body** (`typedef struct T name[1];` — `T` declared separately) is registered as a plain alias of `T`; the extent is discarded and the parameter is passed `byval` where C decays it to a pointer. | `src/cheader.nuc:1272` (no `[` check); scalar array typedefs take the other branch and are recorded unrepresentable at `:1417-1420` |
| **D4 residue** (**closed 2026-08-29 as CD-3, §8**) | A **with-body** aggregate array typedef, `typedef struct Tag { … } Name[N];` (body and array declarator in the same statement), takes a different branch from D4 above and still discards its extent after L1–L5: `declare i32 @take_ptarr(i64, i64)` where clang says `ptr`. Verified identical on the pre-change binary — L1–L5 do not touch this branch. Occurs **zero** times across the 30 standard headers this document surveys. | `src/cheader.nuc:1467` (`c-parse-struct-decl`), body branch at `:1568-1580`: the typedef name after the body is read with `c-read-ident`, which stops at `[` and never checks for it, so `Name[N]` registers a plain alias `Name`. The no-body branch's `[N]` check that D4/L3 added (once at `:1272`, now drifted with the rest of the function) has no counterpart here. |
| **D5** | Nucleus emits no `returns_twice`, so a `setjmp` call is indistinguishable from any other call to the optimizer. Measured: the compiler's own `build/nucleusc.ll` has **zero** `attributes #N = {…}` groups and **zero** `define … #N`; the only function attribute it emits anywhere is `noreturn`, from two `fprintf` sites. | `src/cheader.nuc:943-947`, `src/nuch.nuc:551-555` (line numbers as built — drifted from the design-time `:951-952`/`:544-545` above) |

D1 is the root cause. D2, D3 and D4 are each independently sufficient to make a
specific real type unusable; D5 is specific to the `setjmp` family.

**One more, recorded but not staged.** `struct __attribute__ ((__may_alias__)) sockaddr`
puts an attribute between `struct` and the tag. `c-parse-struct-decl` and
`cheader-scan-opaque-decl` both read `__attribute__` as the tag and register an
opaque type literally named `__attribute__` (`build/nucleusc` will tell you
`'__attribute__' is an opaque type declared at …`). The real tag survives only
because `emit-c-include`'s third dispatch arm re-parses the declaration through
`c-parse-type`, whose specifier loop *does* consume `__attribute__` (`:478-481`)
— verified: a probe `struct __attribute__((__may_alias__)) at_a { long x; long y; };`
imports correctly at 16 bytes. The cost is a phantom registry entry that
pollutes did-you-mean and the `MAX-STRUCTS` budget, plus the prescan not
registering the tag. One line in each of the two scanners; ride it along with L1.

---

## 3. The shape of the fix

### 3.1 L1 — an unresolvable member makes the struct opaque, not `ptr`

Make `c-parse-struct-body` consult the flag `c-parse-func-decl` already
consults. In the per-field loop, around the `c-parse-type` call at
`src/cheader.nuc:1158`, do exactly what `c-parse-typedef-decl:1367-1383` does:
save the caller's `g-cheader-unrep` / `-why` / `-quiet`, clear, parse the field
type, and if the flag came back set, `bad=1 done=1` — the existing abandon path,
which already leaves `out-end` past the closing `}` so the caller is
positioned correctly. Restore the saved triple on every exit.

**The save/restore is load-bearing, not hygiene.** `c-parse-struct-body` is
reached from two places: the top-level `c-parse-struct-decl:1290`, where there is
no enclosing declaration, and `c-parse-type:520`, where there *is* — a nested
anonymous `struct {…}` inside a parameter or a typedef. In the second case an
earlier parameter's verdict is already accumulated in
`c-parse-func-decl`'s `unrep-why`, and clearing the global without restoring it
would erase it. The correct enclosing verdict is preserved anyway by a different
route: the body parse now returns null, and `c-parse-type:529` marks *"a by-value
struct/union whose body the parser could not read"* on the enclosing
declaration. That is the message the caller should show.

**Where the failure lands.** A struct whose body now fails is registered opaque
by `cheader-prescan-opaque` (`:1559`) — the prescan is name-only and registers
the tag of `struct Tag {…}` (`:1537-1538`) and the declarator of
`typedef struct […] {…} Name;` (`:1531-1536`), which is exactly this set. So
`ptr:X` keeps resolving and every by-value use gets
`'X' is an opaque type declared at <header>:<line>`. Verified in advance: that
is precisely what `struct probe_direct` does today.

**Warning volume: zero new loud warnings.** `c-decl-skip-reason` returns
`unrep-why` *first* (`:695`), ahead of the opaque-parameter arm, and every arm
`c-parse-type` raises for an unresolvable name passes `quiet=1`. So a declaration
lost to L1 goes to `g-cheader-skipped` and is reported at the point of **use**
(`unknown: 'setjmp' — its C header declaration was skipped (…)`), under Stage 15
W3c's two-tier policy, not as import-time noise. Measured for the tier that
*would* be loud: across the 17 headers surveyed, only `stdio.h` (1, `fopencookie`)
and `setjmp.h` (2, `setjmp`/`siglongjmp`) emit any `byval` at all, and
`fopencookie`'s `cookie_io_functions_t` is four function pointers and parses
fine. So L1's entire user-visible regression is: **`setjmp` and `siglongjmp` stop
being declared**, with a located reason, until L3 lands.

That regression is real and should not be hidden. It is also the correct
intermediate state: the alternative is what the tree does today, which is to
declare them with a layout that corrupts the stack.

**Blast radius on the IR:** the five `stdio.h` type lines in §1.6, in 163 of 186
sweep modules. Nothing else, because nothing else references them.

### 3.2 L2 — array members with real extents

The type-system half already exists and needs nothing. `(array T N)` is a real
Nucleus type: `TY-ARRAY`, built by the single constructor `array-type`
(`src/type-utils.nuc:202`), rendered `[N x T]` by `type-to-ir`
(`src/type-utils.nuc:182-194`), sized and aligned by `abi-sizeof`/`abi-alignof`
(`src/abi.nuc:150`, `:166`), and classified for the SysV ABI by
`abi-class-type-at` (`src/abi.nuc:245`) and `rv-flatten-type` (`:311`). A
`defstruct` field may already be one (Stage 15 W8 G-2), and a `.nuch` header
carries such a field through `emit-defstruct` unchanged
(`src/nuch.nuc:778-787`).

> **Correction to the brief.** The cited `cheader-array-field-node`
> (`src/cheader.nuc:2069`) and the field handling at `:2143-2150` are in
> `emit-cheader-defstruct` — the **`--emit-cheader` writer**, Nucleus→C. They are
> not the `.nuch` reader. The `.nuch` claim is nonetheless true, by a different
> route: a `.nuch` `defstruct` reaches the ordinary `emit-defstruct`, so its
> `(array T N)` field goes through `parse-type-from-node`'s array branch
> (`src/union-registry.nuc:1747`) like any other.

So L2 is entirely in the C parser, in three independent pieces:

**L2a — linemarkers (D3).** Give the body loop its own skipper that consumes
whitespace *and* `#`-to-end-of-line runs. It must be a new function, not a change
to `c-skip-ws`: `emit-c-include:1604-1613` depends on seeing `#` at top level to
call `cheader-note-linemarker`, and `cheader-skip-to-semi:1463-1467` does the
same. **Do not record the marker from inside the body loop.**
`cheader-note-linemarker` moves `g-cheader-dpos` forward, and
`c-parse-func-decl` computes its diagnostic line as
`(cheader-line-at buf decl-start)` at the *end* of the declaration (`:878`) —
advancing the origin past `decl-start` mid-declaration makes that arithmetic
count backwards. Skip without recording, which keeps the existing "best effort by
construction" contract at `:37-39` exactly as written.

**L2b — literal extents.** After the field name is read (`:1172`) and before the
`;` check (`:1181`), accept a `[` … `]` run whose contents are a decimal
literal, and set the field type to `(array-type fty N)`. Multi-dimensional
`[a][b]` folds right-to-left into nested `array-type`s. Everything downstream is
already in place. This covers **132 of the 160 array-bearing bodies** in the
census: `sockaddr`, `dirent`, `termios`, `utsname`, `statvfs`, `__sigset_t`,
`in6_addr`, the `pthread_*` unions (whose `char __size[N]` extents the
preprocessor has already reduced to literals), and `__jmp_buf`.

**L2c — constant-expression extents.** 28 bodies need arithmetic, and all of the
non-trivial ones need `sizeof(type)`:
`1024 / (8 * (int) sizeof (__fd_mask))` (`fd_set`),
`(128 - sizeof(unsigned short int) - sizeof(unsigned long int))` (`sockaddr_storage`),
`15 * sizeof(int) - 4 * sizeof(void *) - sizeof(size_t)` (`FILE`).
This is a small recursive-descent integer evaluator over the same buffer:
`+ - * / % << >> ( )`, integer literals, and `sizeof (<type>)` evaluated by
calling `c-parse-type` and then `abi-sizeof`. Two rules:

- **Evaluate for the emission target, never the preprocessing host.** `clang -E`
  preprocesses for the host even under `--target=`; this is the same trap that
  keeps `size_t`/`ssize_t` hardcoded in `c-type-to-nucleus`
  (`context/conventions.md`, "The C typedef table resolves at RECORD time").
  `abi-sizeof` and `target-long-size` (`src/cheader.nuc:1023`) already answer for
  the target, so use them and never `sizeof` from the host.
- **An extent this evaluator cannot fold is not a guess.** Raise
  `cheader-mark-unrep` and let L1 make the struct opaque. That is the whole
  reason L1 sequences first: it gives L2 a safe destination for its residue, so
  L2c can be scoped to what it can actually do and stop.

**What L2 does *not* need:** `g-array-ok`. That gate
(`src/nucleusc.nuc:458`, read at `src/union-registry.nuc:1676-1680`) governs
where the *Nucleus surface syntax* `(array T N)` may be written. The C parser
constructs the `Type` directly through `array-type`, so it never enters
`parse-type-from-node` and the gate is not consulted. The backstop that covers
already-parsed array Types reaching a value position is `reject-array-type`
(`src/type-utils.nuc:248`), which stays the guard. §3.5 returns to this — it is
the one place the merge question has real teeth.

**Expected result on the worked example:**
`%__jmp_buf_tag = type { [8 x i64], i32, %__sigset_t }`, 200 bytes,
`(sizeof __jmp_buf_tag)` → 200.

### 3.3 L3 — array typedefs decay to pointers in parameter position

Two halves, matching the two paths an array typedef takes.

**The scalar path** (`typedef long __jmp_buf[8];`) already reaches
`c-parse-typedef-decl:1417-1420`, which sets `bad=1` and records the name with a
null Type. With L2 in hand, record `(array-type base N)` instead. The comment at
`:1417-1419` states the reason it could not: *"the element type is known, but
this parser has no C array type and a by-value use would silently take the
ELEMENT's ABI"*. That objection is now false — the parser has one.

**The aggregate path** (`typedef struct __jmp_buf_tag jmp_buf[1];`) never reaches
that function: `c-parse-struct-decl`'s no-body branch claims it at `:1259-1288`
and registers `jmp_buf` as an alias StructDef. Add the `[` check after the
declarator read at `:1272`: an array declarator means this is not a struct alias,
it is an array typedef, and it belongs in `g-cheader-typedefs` with an
`(array-type <tag's Type> N)` — which requires the tag's layout, and therefore
requires L2 first, or L1's opaque fallback if the tag never got one.

**Correction: this section is incomplete on the site it names, and following
it literally is a no-op.** `c-parse-struct-decl`'s no-body branch is where
`jmp_buf`'s alias is *registered* as an array typedef, but it is not where
`%jmp_buf = type {…}` gets *emitted* into the IR — a `.nuc` file resolves type
NAMES long before any struct's layout is finalized, and by the time a real
import runs, `jmp_buf` was already provisionally registered by the whole-unit
**prescan** (`cheader-scan-opaque-decl`, which mirrors this exact branch —
D4's own comment there says so: "this scan must stay name-for-name with
`c-parse-struct-decl`, or `struct-upgrade-aliases` emits a `%Bar` the real
import never defines"). The type line itself is written later still, by
`struct-upgrade-aliases`, keyed on the alias link this branch creates, once the
tag's real body has landed. Editing only `c-parse-struct-decl` leaves the
prescan's own copy of the same branch unchanged, the type line still gets
written (or not) by the stale rule, and the change reads as a no-op against
the worked example. **Both sites move together**, or neither does.

**Correction: the §3.2/§4 boundary drawn above is stale — this scalar-array
piece landed in L2, not here.** `__jmp_buf` (`typedef long int __jmp_buf[8]`)
is exactly the scalar path described two paragraphs up, and by §3.2/§4's own
words `__jmp_buf_tag`'s 200-byte layout — L2's own acceptance bar — cannot be
reached without it, since `__jmp_buf_tag`'s first member has type `__jmp_buf`.
The scalar-array-typedef fix could not wait for a nominally-later L3 without
making L2 unable to meet the bar §4 sets for it, so it was implemented as part
of L2. What is left for L3, once L2 lands, is only the **aggregate** path
above and the parameter/return decay call below.

**The decay itself is a call, not a rule.** `array-decay`
(`src/type-utils.nuc:220`) is documented as *"THE decay rule, in one function
that both codegen and the non-emitting type pass CALL (never mirror)"*, with ten
existing call sites listed in `context/conventions.md` ("A decay rule belongs in
ONE function"). The C importer becomes the eleventh: call `array-decay` on each
parameter type and on the return type in `c-parse-func-decl`, immediately after
`c-parse-type` returns, in the same place the syntactic `[N]` override already
sits (`:810-823`). Do **not** re-implement C's decay rule beside the Nucleus one.

Two boundary rules follow from C, and both need stating because `array-decay`
alone does not know which position it is in:

- A C **parameter or return** of array type decays. `array-decay` gives
  `(ref T)`, which lowers to `ptr` — right.
- A C **struct member** of array type does **not** decay. So the member path must
  keep the `TY-ARRAY` and the parameter path must not, which means the call goes
  in `c-parse-func-decl`, never in `c-parse-type`.

**Expected result:** `declare i32 @setjmp(ptr)`,
`declare void @siglongjmp(ptr, i32) noreturn`.

### 3.4 L4 — `returns_twice`

Three findings decide the shape, all measured.

**1. The inline keyword works; no attribute-group machinery is needed.**
Hand-written IR in the shape Nucleus emits — `declare i32 @_setjmp(ptr) returns_twice`
— parses and links under `clang -O0` and `-O2`. That is exactly the `noreturn`
spelling already emitted at `src/cheader.nuc:943-947` and `src/nuch.nuc:551-555`
(line numbers as built; see the D5 row above),
so L4 is one more branch in each of those two `fprintf`s plus a `Sym` flag beside
`Sym.noreturn` (`src/compiler-types.nuc:547-550`, as built).

**2. The attribute must come from a name list, because the header does not carry
it.** `clang -E -x c -include setjmp.h /dev/null | grep -c returns_twice` → **0**.
glibc annotates `longjmp` with `__attribute__((__noreturn__))` and annotates
`setjmp` with nothing but `__nothrow__`; clang supplies `returns_twice` because
`_setjmp`, `__sigsetjmp` and `vfork` are *library builtins*, verified by
compiling calls to all three and reading the emitted attribute groups. So
`c-fn-returns-twice` is the exact mirror of the existing `c-fn-noreturn`
(`src/cheader.nuc:23`), whose comment already says the parser discards
`__attribute__((noreturn))` and recognizes libc's noreturn set by name. The set:
`setjmp`, `_setjmp`, `__sigsetjmp`, `sigsetjmp`, `savectx`, `vfork`, `getcontext`.

**3. What its absence costs, exactly.** Two hand-written modules identical but
for the attribute, through `opt -O2`:

```
without: %r = tail call i32 @_setjmp(ptr nonnull @b)
with:    %r =      call i32 @_setjmp(ptr nonnull @b)
```

Without it LLVM marks the call a **tail call**, licensing frame reuse under a
function whose frame the `longjmp` will return into. LLVM's documented
consequences beyond that (alloca placement, stack coloring, `callsFunctionThatReturnsTwice`)
follow from the same attribute. This is a real, reproducible difference, not a
theoretical one — but it is worth saying plainly that the probe with a
`volatile` local printed the correct answer either way, so the attribute is
hardening, not the whole of correctness.

**The source-level half is already done.** The "locals must survive the jump"
requirement is `volatile`, and Nucleus has it in every position:
`(defvar :volatile x:i32 0)`, `(let (:volatile x:i32 0) …)`,
`(defstruct R (:volatile status:i32))`, `(ptr :volatile T)` —
`docs/types.md:324-340`. Nothing to add.

**Scope note.** `returns_twice` is a property of a *declaration*, and Nucleus has
no way for a user to say it about a `defn`. L4 is deliberately import-side only:
the name list, and a `.nuch` `declare` keyword for symmetry with `noreturn` if
that costs nothing. A Nucleus function that itself returns twice is not a thing
the language can express and is not in scope.
**~~Not in scope.~~ Taken 2026-08-29 — see §10.**

### 3.5 The `deftype` integration question

**The question, as asked:** *"If practical, integrate C typedef handling with the
machinery of Nucleus `deftype`."*

**The recommendation: do not merge the registries. Do share the lookup path and
the diagnostics — and that share is a feature the language is missing anyway.**

#### What the two things are

| | C typedef table | `deftype` |
|---|---|---|
| store | `g-cheader-typedefs`, a `Node` cell list: `s` = interned name, `car` = a resolved `Type*` (`src/cheader.nuc:108-129`) | `g-type-aliases`, `(ref (Vector (ref TypeAlias)))` (`src/nucleusc.nuc:186`); `TypeAlias` at `src/compiler-types.nuc:420` |
| binding | **eager** — resolved once when the `typedef` is parsed | **lazy** — the body `Node` is retained unparsed and re-parsed at each use (`src/union-registry.nuc:363-374`) |
| key | flat, global, unqualified | `qualify-name`d, with `priv` / `src-ns` / `src-file` / `src-line` |
| written by | `c-typedef-record` (`:121`), first-wins and idempotent | `register-type-alias` (`src/union-registry.nuc:1304`), dies on redefinition unless same-site |
| read by | `c-parse-type:564` **only** | `parse-type-name:363`, `parse-type-from-node`, `type-node-to-c:1983`, `nuch` export/import, the REPL |
| exported | never | to `.nuch` (§3.8 of container-type-sugar.md) and expanded in `--emit-cheader` (§3.8a) |
| cycles | impossible **by construction** | needs `MAX-TYPE-ALIAS-DEPTH` (`src/compiler-types.nuc:24`), *per recursion site* |
| parameters | none | `(deftype (Table V) …)`, node substitution |

#### Why the tension does not dissolve

The brief's hypothesis is that the array case exists only because *"the eager path
must produce a `Type*` and there was no array type to point at — and `(array T N)`
now exists."* **That half is exactly right, and it is the finding that makes L2
and L3 cheap** (§3.2, §3.3): `c-typedef-record` can now store a real `Type*` for
`typedef long __jmp_buf[8]` where before it had to store null. But it is not the
whole story, because the eager/lazy split is not an accident to be tidied away.
`src/cheader.nuc:89-99` records the rationale, and each clause is a constraint on
any merge:

1. **There is no `Node` to be lazy with.** The C parser works over a raw text
   buffer, not over a Nucleus AST. Storing a lazy body would mean *synthesizing*
   a type Node (`(array i64 8)`) as a second representation of what
   `c-parse-type` already computed, and re-parsing it at each use — strictly more
   work, and a second place for the two to disagree.
2. **Order semantics are opposite, deliberately.** `deftype` is order-independent
   inside a file ("declaration order inside a file does not matter",
   container-type-sugar.md §3.3). A C file-scope typedef is visible only from its
   declaration onward, and it is precisely that which makes a cycle impossible —
   a name resolves only against entries recorded strictly before it, so a
   malformed `typedef foo foo;` records `foo` as unrepresentable instead of
   looping. Merge the registries and one of the two semantics has to give.
3. **Redefinition policy is opposite.** `c-typedef-record:122` returns early on a
   repeat, because glibc re-declares typedefs constantly through transitive
   includes and the table must not grow without bound.
   `register-type-alias:1349-1353` calls `die-redefinition`. A shared definer
   would need an origin discriminator on the first line of its body, which is the
   merge's cost appearing immediately.
4. **Export semantics are opposite.** A `deftype` is written to `.nuch` and
   expanded in `--emit-cheader`. A C typedef must never be: it is an artifact of
   *this* unit's `import-use`, and the consumer is expected to import the same
   header. A shared registry means the export arm needs a filter.
5. **A recorded-null entry has no `deftype` analogue.** "Known C type name, no
   Nucleus representation" is deliberately distinct from "absent"
   (`src/cheader.nuc:98-102`), and it is what produces the located skip. There is
   no `TypeAlias` shape for it.
6. **Qualification and privacy do not apply.** C names are global and
   unqualified; `TypeAlias` keys are `qualify-name`d and carry `priv`/`src-ns`.

#### The counter-argument, weighed

*"A merged registry would give one answer to 'what does this name mean' instead of
two tables consulted in sequence."* Measured against the code: `parse-type-name`
already consults **five** sources in sequence — `builtin-type-name`,
`fnty-resolve`, `struct-lookup-ref`, `type-alias-lookup-ref`, then
`unknown-type-message` (`src/union-registry.nuc:274-380`). A sixth probe is the
established pattern here, not a new cost. What *is* a real cost is a name that
means something and is consulted by nobody — which is the actual defect, below.

#### The actual defect the question uncovers

A C **struct** name is a Nucleus type name today: `ptr:FILE` and
`(sizeof timeval)` work, because C structs live in `g-structs` and
`parse-type-name` probes it. A C **scalar typedef** is not. Verified:

```
printf '(import-use "unistd.h")\n(defn main ():i32 (let (x:off_t 5) …) (return 0))\n' > /tmp/td.nuc
build/nucleusc /tmp/td.nuc          # error: unknown type: off_t — not defined anywhere in this compilation unit
```
Same for `uint32_t` after `(import-use "stdint.h")`. The typedef table is
**private to the C parser**: `g-cheader-typedefs` has exactly one reader,
`c-parse-type:564`.

So `(defn seek (fd:i32 off:off_t):off_t …)` cannot be written. That is a direct
hit on the stated goal — *any required libc detail must be obtainable from a pure
Nucleus program* — and it is the half of the integration question worth building.

#### L5 — a C typedef is a Nucleus type name (approved 2026-08-25)

1. **Probe the C typedef table from `parse-type-name`**, as a sixth arm placed
   *after* `type-alias-lookup-ref` (`src/union-registry.nuc:363`) so a `deftype`
   can never be masked by an import, and before the `die-at`. Return the stored
   `Type*` directly: **transparent, exactly like `deftype`'s §3.2 semantics** —
   `off_t` and `i64` are `type-eq`, mangle identically, and are one overload. Do
   not teach `type-spelling`.
2. **A recorded-null entry gets its own message.** `unknown-type-message`
   (`src/nucleusc.nuc:3239`) gains an arm: `'__jmp_buf' names a C type this
   compiler cannot represent (<header>:<line>)`, distinct from "not defined
   anywhere in this compilation unit". This is the one place the two registries
   genuinely should share: the C table already distinguishes recorded-null from
   absent, and only the diagnostic consumes that distinction.
3. **`type-name-collision` gains a C-typedef arm.** It currently probes builtins,
   structs, both template registries and enums (`src/union-registry.nuc:1221-1227`).
   Once (1) lands, `(deftype off_t …)` after `(import-use "unistd.h")` is exactly
   the *dead-on-arrival, silently* class §3.4a of container-type-sugar.md exists
   to prevent. One line: `"a C typedef imported from <header>"`.
4. **The `g-array-ok` question, answered in one place.** Once `off_t` resolves,
   so does `jmp_buf` — and after L3 that is a `TY-ARRAY`. `parse-type-name`'s
   probe returns an already-built `Type`, which is precisely the situation
   `reject-array-type` was written for: *"Backstop for the positions
   `parse-type-from-node`'s `g-array-ok` gate cannot see because the Type arrives
   already parsed"* (`src/type-utils.nuc:246-247`). The new probe must consult
   `g-array-ok` itself and refuse a `TY-ARRAY` outside a `defvar`/field position
   with the same message the Nucleus spelling gives, and `reject-array-type` stays
   the backstop. This is the strongest argument *for* the lazy representation —
   a lazy body re-enters the gate for free — and the reason it does not win is
   that a single new probe site is one place to get it right, against six for a
   merge.

   **Correction: "the new probe must consult `g-array-ok` itself" was not
   implementable as written, and this was a live, pre-existing bug independent
   of L5.** `parse-type-from-node` reads-and-clears `g-array-ok` on entry and
   *only then* delegates a bare symbol to `parse-type-name` — so any arm inside
   `parse-type-name`, including the new one, sees 0 regardless of what the
   caller armed. This was already observable before L5 existed:
   `(deftype Buf (array i32 4))` followed by `(defvar env:Buf)` was refused,
   because a bare-name delegation to an alias's body never inherited the
   permission either. The fix threads the permission by *classifying* each
   delegation rather than reading it once at the top: `(ptr (array i32 4))` is
   a genuine nesting and must not inherit (consume-once is for exactly this),
   but a bare name and a transparent alias's body are the same type node under
   another spelling and must — `(set! g-array-ok array-ok)` immediately before
   the delegating call, so `parse-type-name`'s own recursions see the armed
   value without a clear at each one. See `context/conventions.md`, "A
   consume-once permission does not survive a delegation".

The payoff is the worked example in §7: `(defvar env:jmp_buf)` becomes a legal
200-byte storage declaration and `(_setjmp env)` decays it to `ptr` — with no
`deftype`, no shim, and no new syntax.

**Performance note, since (1) puts the table on a hot-ish path.**
`c-typedef-find` is a linear walk comparing `CStr`s, i.e. `strcmp` per entry;
`SDL2/SDL.h` records 469 typedefs. The new probe is only reached for a name that
resolved nowhere else — the path that is about to `die-at` — so the cost is
bounded by one failed lookup per compile. Not worth a hash table now; worth a
sentence so nobody is surprised.

**Correction: this reasoned about the wrong side, and the asymmetry was a live
bug, not a theoretical one.** The argument above is that the *write* — a
repeated, idempotent `c-typedef-record` — is safe to leave unsnapshotted. The
actual hazard is the *read*: `repl-restore` truncates `g-structs` on a rolled-back
form, but a `CTypedef` entry can hold a `Type*` pointing at a StructDef the
truncation just removed. Reproduced pre-fix: import `setjmp.h` (recording
`jmp_buf` against `__jmp_buf_tag`'s Type), let the form fail and roll back, then
`(defvar env:jmp_buf)` — the typedef entry survives the rollback, still pointing
at a `%__jmp_buf_tag` that no longer exists in the module, and
`build/nucleusc` dies with `IR parse error: base element of getelementptr must
be sized`. Unreachable before L5, because nothing outside the C parser itself
ever dereferenced the stored `Type*` across a REPL entry boundary. Fixed by
giving `g-cheader-typedefs` the exact same treatment its neighbour
`cheader-skipped` already had: a new `ReplState.cheader-typedefs` field,
saved on snapshot and restored on rollback, so a form that fails discards
whatever typedefs it recorded along with the structs they pointed at.

---

## 4. Staging

| stage | content | acceptance |
|---|---|---|
| **L1** | §3.1 — an unresolvable struct member abandons the struct (D1), plus the `struct __attribute__(( )) Tag` phantom (§2) | no C struct type reaches the IR with a `ptr` standing in for a member the parser could not resolve; **characterized IR diff** (§5) limited to the five `stdio.h` type lines across 163 modules; `make test` green; `make bootstrap` converges after a boot refresh |
| **L2** | §3.2 — a: linemarkers in bodies (D3); b: literal array extents (D2); c: constant-expression extents | `(sizeof X)` from Nucleus equals `sizeof` from clang for every type in §1.5's tables that L2 claims; the five `stdio.h` lines return at correct sizes; `struct timespec` / `stat` / `dirent` / `termios` / `sockaddr` stop being opaque or absent |
| **L3** | §3.3 — array typedefs decay in parameter and return position (D4) | `declare i32 @setjmp(ptr)`; no `byval` anywhere in `setjmp.h`'s import; `utimensat`'s existing syntactic-decay behaviour unchanged |
| **L4** | §3.4 — `returns_twice` on the setjmp family (D5) | `declare i32 @setjmp(ptr) returns_twice`; `opt -O2` does not mark the call `tail call`; the §7 program runs |
| **L5** | §3.5 — a C typedef is a Nucleus type name | `(defn seek (fd:i32 off:off_t):off_t …)` compiles; `(deftype off_t …)` after the import is refused naming the header; a recorded-null typedef gets its own message; a `TY-ARRAY` typedef is refused outside a `defvar`/field position |

**Sequence: L1 → L2 → L3 → L5 → L4.**

L1 first, alone, because it is pure safety and converts the entire class from
silent corruption to a located error. It is independent of everything below it
and is the only item that could be shipped on its own with a straight face.

L2 second because it is what makes L1's new refusals unnecessary rather than
merely honest, and because L3 needs the array `Type*` L2 produces. Within L2,
**L2a before L2b**: the linemarker fix is three lines and without it L2b does not
deliver `timespec`, `stat` or `itimerspec`, which would make L2's own acceptance
bar unmeetable for the types most worth having.

L3 third because it needs L2 and because it is what un-breaks the two
declarations L1 removes.

L4 last because it is the only setjmp-specific item.

**Correction: "inert for every other header" is false, and it was worth
knowing before landing, not after.** `src/nucleusc.nuc:7` imports `unistd.h`,
and `vfork` is on L4's own by-name list (§3.4) — so L4 changes the *compiler's
own* emitted IR (`declare i32 @vfork() returns_twice`, verified in
`build/nucleusc.ll`) exactly as L1 and L2 do, and needed the same
`make update-bootstrap` + re-convergence they did. "Setjmp-specific" was true
of the *feature*; it was never true of *this by-name list*, which reaches
every header importing any function on it — the by-name lists for `noreturn`
and `returns_twice` in §3.4 are exactly where to check this for any future
addition.

L5 after L3 because its payoff (`jmp_buf` as a declarable type) needs L3's array
typedef, and because it is the one item here that changes the *language surface*
rather than the importer — it should not ride along inside a correctness fix. It
lands before L4 rather than after only because L4's own reason for being last —
it is the sole setjmp-specific item — still holds once L5 is in the sequence.

**The cost of L1 landing alone, stated plainly.** Between L1 and L2 the tree is
in a state where 163 of 186 modules emit five fewer type lines, `setjmp` and
`siglongjmp` are undeclared with a located reason, and a handful of already-wrong
types have moved from wrong to unavailable. That is strictly better than today
and strictly worse than L2. Bundling L1+L2 into one commit would avoid two boot
refreshes and one characterized-diff review; splitting them keeps a pure-safety
change reviewable on its own. The approved staging splits them, and the reason to
keep that is that L1 is the change most likely to be wrong in an unexpected way
(it converts silent success into refusal across every imported header at once)
and it deserves to be bisectable.

---

## 5. Test plan

### The IR sweep is a characterized-diff gate here, not a neutrality gate

§1.6 measured why. Restated as a procedure, for L1 and L2:

1. Build a baseline `nucleusc` **from HEAD's source before the change** — not
   `bin/nucleusc`, which lags and would report the difference between HEAD and
   the committed boot as if it were the change's.
2. Compile all 152 `examples/*.nuc` and 34 `lib/*.nuc` with `--emit-llvm` on both
   binaries, capturing `.ll`, stdout, stderr and exit code.
3. `diff` — and require that **every** hunk is a `%X = type` line for a type
   named in §1.5, or an `%__anon_struct_hXXXX` rename following from one. Any
   changed `declare`, `define`, global or stderr line is a failure.
4. Sweep the 96 header-mode outputs (`--emit-nuch` and `--emit-cheader` over 34
   `lib/` + 14 `src/` modules) and require those **byte-identical** — the C
   *import* path and the C *export* path share `type-to-ir` but not the parser,
   so any movement there is a real defect.

For L3, L4 and L5 the ordinary byte-identical bar applies to steps 2–4, since
none of them changes a struct layout.

**And the sweep is not sufficient, for a reason specific to this work.** The
whole tree imports six C headers (§1.6), exposing 14 comparable struct types out
of the 65 surveyed. A change that broke `signal.h`, `pthread.h` or
`netinet/in.h` outright would sweep clean. This is the same shape as the D9 case
in [repl-libraries.md](repl-libraries.md) §3.3, where the 186-module sweep was
structurally unable to see a CT-module defect and the item needed its own batch
gate — with the difference that there the blind spot was a *stream*, and here it
is *coverage*. Each stage therefore needs a gate that imports headers the tree
does not.

### New gates

| gate | covers |
|---|---|
| **`run_l1_member_opaque`** + `tests/fixtures/l1-members.h` | the four §1.3 shapes as struct members — a typedef-hidden array, a typedef of an unparsable aggregate, an opaque tag by value, a `long double` — each asserting the *located* opaque error naming the fixture header and line, and asserting the type emits **no** `%X = type` line. Pins that failure is safe, not that it happened. |
| **`run_l2_layout_matrix`** + `tests/fixtures/l2-arrays.h` | a matrix of extents: literal, multi-dimensional, macro-expanded, `sizeof`-bearing, and one deliberately unfoldable. Asserts the **exact `%X = type` line** for each, plus `(sizeof X)` against a value the fixture states — and asserts the unfoldable one is opaque. Asserting the emitted layout rather than "it compiled" is the point: every wrong row in §1.5 compiles fine today. |
| **`run_l2_libc_layouts`** | the survey as a test. `(sizeof X)` for a fixed roster drawn from §1.5 — `__jmp_buf_tag`, `timespec`, `itimerspec`, `stat`, `dirent`, `termios`, `fd_set`, `sockaddr`, `in6_addr`, `sigset_t`, `pthread_mutex_t`, `FILE` — compared against a C program compiled in the same harness run. **Compare against clang, never against a hardcoded number**: these are glibc-version- and target-dependent, and a hardcoded 200 becomes a false failure on the first musl or 32-bit run. Skip the unit cleanly if a header is absent. |
| **`run_l3_decay`** | `declare i32 @setjmp(ptr)` and `declare void @siglongjmp(ptr, i32) noreturn` asserted textually; no `byval` in the whole `setjmp.h` import; and a negative — `utimensat`'s `const struct timespec [2]` still decays, proving the syntactic path at `:810-823` was not disturbed. |
| **`run_l4_returns_twice`** | the attribute on the declaration, and `opt -O2` on the emitted module showing `call` rather than `tail call` at the `_setjmp` site. |
| **`examples/setjmp-guard.nuc`** + `tests/expected/setjmp-guard.out` | §7's program, **run**: a value crosses the jump and is printed. libc only — `run-tests.sh` has no per-test link-flag mechanism. |
| **`run_l5_typedef_names`** | `(defn f (x:off_t):off_t …)` compiles and the emitted signature is `i64 (i64)`; `(deftype off_t i64)` after the import is refused naming the header; a fixture typedef (`typedef long double weird_ld_t;` — **corrected subject**, see below) gives the recorded-null message; `(defn g (x:jmp_buf):i32 …)` is refused as storage-not-a-value. |

**Correction: the recorded-null witness above named a subject L2/L3 had
already made representable.** `(let (x:__jmp_buf …))` was proposed as the
recorded-null case, but by the time L5 runs, L2 and L3 have already turned
`__jmp_buf` into `(array i64 8)` — a real Type, not a null entry — so that
program no longer exercises this arm at all; it now gives the ordinary
storage-not-a-value message instead. The gate uses a fixture typedef of a
type this compiler genuinely cannot represent (`long double`) instead. Also
worth stating precisely, since it is easy to get backwards: this message only
fires for a genuinely-final null entry. A **provisional** null — recorded by
the whole-unit prescan before the real import has run, which is what a
`defn` signature or `defvar` type sees — is deliberately indistinguishable
from an absent name at that point, and falls back to the ordinary
`unknown type` message; see [A C typedef is a Nucleus type
name](../../docs/structs-unions.md#a-c-typedef-is-a-nucleus-type-name) for the
worked example (`sigset_t`).

### Harness cautions

- **`qgrep`, never `grep -q`**, and a `grep` matching nothing under `set -e` kills
  the unit mid-way with no FAIL line — `context/conventions.md` records both, and
  Stage 16's own `run_stdlib_table` died silently that way for an unknown period.
  Predict each unit's PASS total and check it.
- **Grep `tests/run-tests.sh` itself** before concluding a spelling is unused: it
  writes several `.nuc` consumers inline with heredocs, and three of the four
  `SDL2/SDL.h` imports in the tree live there.
- `make abi-test`, `make layout-test` and `make check-headers` are all in scope
  for L2: it is the first change to make `abi-classify` see a `TY-ARRAY` that came
  from a C header rather than from `defstruct`.

### Bootstrap

L1 and L2 change the compiler's own emitted IR (it imports `stdio.h`,
`stdlib.h`, `string.h` and `unistd.h`), so each needs `make update-bootstrap` and
a re-convergence, exactly as Stage 15 W3c did for the same reason. `make
bootstrap` byte-identical is the gate *after* the refresh, not before it.

**Correction: this held for L3 and L5, but not for L4.** L3 and L5 converged
with no refresh, as predicted. L4 did not: the same `unistd.h` import gives
`vfork` a `returns_twice` it did not have before, changing the compiler's own
IR (§4's staging correction above), so L4 needed a boot refresh too. Reasoning
about "does this land where the compiler's own six imported headers reach"
(§1.6) is the check to run per item, not an assumption that a
language-surface or setjmp-specific item is automatically exempt.

---

## 6. Out of scope, and why

**Inline function-pointer struct member.** `struct s { void (*f)(int); };`
abandons the struct — a function pointer *behind a typedef* member
(`typedef void (*cb)(int); struct s { cb f; };`) is fine, since the field
collapses to `ptr` before the parenthesized declarator ever has to be read
inline. This blocks `struct sigaction` and `sigevent_t`. Cheap and
well-contained: it is a body-parser addition, not a type-system one — a
function-pointer field is already a Nucleus `ptr`. **Note for whoever takes
it:** the analogous branch in `c-parse-func-decl` (a function-pointer
*parameter*, `src/cheader.nuc:776-786`) deliberately clears the unrep flag in
the same step it collapses the type to `ptr` — *"a pointer-to-function
parameter is a pointer whatever its return/argument types were, so an
aggregate met while parsing them says nothing about this parameter"* — a
struct-body repair must clear it the same way, or an aggregate return/argument
type inside the function-pointer's own signature (met while skipping past it)
leaks into the enclosing struct's verdict and converts a case that already
works today into a new refusal.

**~~With-body aggregate array typedef.~~ Closed 2026-08-29 as CD-3 — see §8.**
`typedef struct Tag { … } Name[N];` (body and array declarator in the same
statement) discarded its extent after L1–L5 — see the D4-residue row in §2.
Deferred here for the combination "silently wrong calling convention, zero
occurrences across the standard headers surveyed"; taken because the *silence*
is the class L1 exists to remove, whatever the occurrence count.

**`Sym.returns-twice` has no reader, and now has a third writer.** *(Revised
2026-08-29 with §10: the original note said "both registration sites", and there
are three — `emit-defn` joined the C importer's by-name list and the `.nuch`
round-trip reader when the attribute became user-settable.)* Nothing **reads**
it: the attribute rides the emitted `define`/`declare` and has no call-site
consequence *in Nucleus*, unlike `noreturn`, which `terminate-after-noreturn`
consumes to end a block. That half is deliberate and survived the change —
there is nothing for Nucleus itself to narrow or refuse on a "this call may
return twice" fact, and LLVM derives the caller-side handling
(`callsFunctionThatReturnsTwice`, alloca placement, stack colouring) from the
attribute on the call itself. Worth a line so a future reader does not go
looking for the reader that isn't there.

**`__attribute__((packed))` and alignment attributes.** `struct epoll_event` is
16 bytes in Nucleus and 12 in C, silently, and neither L1 nor L2 touches it: both
members resolve correctly, and the wrongness is in a layout attribute the parser
discards. This is the same *class* as D1 — a silently wrong layout with no
diagnostic — but a different mechanism, and fixing it means teaching
`StructDef`/`abi-sizeof` about packing, which is a type-system change reaching
`defstruct` too. It should be its own item. Recorded here so the survey is not
read as complete.

**C11 anonymous struct/union members.** `struct rusage`'s
`__extension__ union { long ru_maxrss; …; };` has no declarator, so the
field-name read fails and the struct is abandoned. Two bodies in the 30-header
census. Fails safe. It is a body-parser feature with a name-scoping question
attached (an anonymous member's fields are addressable from the outer struct),
and Nucleus has no equivalent to lower it onto.

**Bitfields.** One body in the census. `design/stage3c.md` already defers
bitfields, `long double` and `_Complex` together, and `design/progress.md` lists
that deferral. Fails safe. Nothing here changes its standing.

**~~Multi-declarator field lines (`int a, b;`) and comma-separated typedef
declarator lists (`typedef int a, *b;`).~~ Closed 2026-08-29 as CD-1 and CD-2 —
see §8.** Both were recorded as known gaps in
`design/stage15-stress-test/cheader.md` ("What blocks the next rung", items 1 and
3), and both failed safe, so neither was a miscompile: this was coverage. L1 did
not make either worse and L2 did not need either. What was left of them after
CD-1/CD-2 is one shape — declarators that disagree in *pointer depth* — and it
still fails safe (§8.2).

**`long double` / `_Float128` / `_Float16`.** 156 declarations correctly refused
across the standard headers, per W3c's measurement. A type-system change, not a
parser one.

**Replacing the hand-rolled parser with libclang.** `design/stage3b-interop.md`
and `stage3c.md` own that question. Every item here is a bounded fix to the
existing parser and none of them makes libclang harder or easier. Worth noting
for whoever revisits those: the census in §1.5 says the parser's *coverage* gap
is concentrated in one shape (array members, 132 of 163 blocked bodies), which is
an argument that the hand-rolled parser is closer to sufficient than the raw 70 %
figure suggests.

> **Evaluated on 2026-08-26, after L1–L5 landed:
> [cheader-parser-vs-libclang.md](cheader-parser-vs-libclang.md) — finish the
> parser.** The prediction in the paragraph above held, and by a wider margin
> than it claimed: re-measuring the same way across 32 headers gives **102 of
> 111** named bodies laid out and **101 of 103** emitted C types matching
> clang's `sizeof`. The nine blocked types are four shapes plus `long double`,
> and **four of the nine fall to one ~15-line repair** — the inline
> function-pointer item below, which is half-built rather than absent (the
> branch at `src/cheader.nuc:1398-1405` already collapses the field to `ptr`; it
> loses the field *name*, because `c-skip-parens` swallows `(*name)` whole). A
> libclang-shaped API was probed end to end from Nucleus and works, so the ABI
> is not the obstacle; the economics are. Two defects this survey could not see
> also turned up — a bare `unsigned`/`signed` is not a type, and that path
> records no skip reason — both staged there.

**~~The rest of `src/repl_shim.c`.~~ Closed 2026-08-30 — see §11.** The shim's
own header comment was the motivating instance — *"jmp_buf is an opaque,
platform-specific type that Nucleus cannot express directly"* — and L1–L4
removed that reason. Both halves went in one item: the `setjmp` half because
L1–L5 made it writable, and the float-printing half because Stage 16 FP-2 made
an indirect call through a typed function pointer ABI-lowered and coercing, so a
`(fn f64)()` value is callable from Nucleus and needs no C wrapper either. The
file is gone; the compiler is pure Nucleus.

**~~A user-declarable `returns_twice` on a Nucleus `defn`.~~ Closed 2026-08-29
— see §10.** §3.4's scope note.

**~~`--emit-cheader` does not `#include` the header a rendered C typedef came
from.~~ Closed 2026-08-29 — see §9.2.** A public signature naming `off_t`
rendered as bare `off_t` with no `#include <unistd.h>` anywhere in the output,
unlike a type borrowed from another *Nucleus* unit, which does get an
`#include` of that unit's generated header (`docs/compiler.md`, "Types a header
borrows from another unit"). The counter-argument recorded here — that a
consumer of the generated header is expected to `#include` the same C header
itself — did not survive being measured against the header the compiler
actually writes: a bare `off_t` is `error: unknown type name`, so the header
did not compile at all.

---

## 7. Worked example: `setjmp` from pure Nucleus

What the four stages together are for. This program is not writable today at any
spelling.

```lisp
(import-use "stdio.h")
(import-use "setjmp.h")

; L5: `jmp_buf` is a C array typedef, so this is 200 bytes of storage, not a
; pointer. Without L5 it must be spelled (array __jmp_buf_tag 1) by hand;
; without L2 the size is 24 and the next line corrupts the stack.
(defvar env:jmp_buf)

(defn risky (n:i32):void
  (when (< n 0) (_longjmp env 1))
  (printf "ok %d\n" n))

(defn main ():i32
  ; L3: `jmp_buf` decays to `ptr` here, as it does in C.
  ; L4: `returns_twice`, so the call is not tail-called and the frame survives.
  (let (:volatile tries:i32 0)
    (if (= (_setjmp env) 0)
      (do (set! tries (+ tries 1)) (risky -1))
      (printf "recovered after %d tries\n" tries)))
  (return 0))
```

Three details that are properties of the *headers*, not of the compiler, and
that the docs should state when this lands:

- **`setjmp` is a macro on glibc.** `/usr/include/setjmp.h:49` is
  `#define setjmp(env) _setjmp (env)` — unconditional. `design/overview.md`
  already records that Nucleus consumes C functions and data structures but not
  its macros, correctly, so a Nucleus program reaches the *function* `setjmp`
  (which is `__sigsetjmp(env, 1)` and saves the signal mask), where C source
  spelling `setjmp(e)` reaches `_setjmp` (which does not). Spell `_setjmp`
  explicitly to get C's behaviour. This is exactly the `Mix_GetError` situation
  W3's spec flagged: not a compiler bug, but a diagnostic the user must be able
  to reach `nm -D` from.
- **`sigsetjmp` is likewise `#define sigsetjmp(env, savemask) __sigsetjmp (env, savemask)`**
  (`/usr/include/setjmp.h:74`); the callable symbol is `__sigsetjmp`.
- **`longjmp` already gets `noreturn`** from the hardcoded list at
  `src/cheader.nuc:23-26`, so `terminate-after-noreturn` (`src/scope.nuc:143`)
  already ends the block after it. L4 adds the matching half on the other side.

---

## 8. As built: CD-1, CD-2, CD-3 — the three declarator shapes

**Status: implemented 2026-08-29** on `stage16-ergonomics`, closing the last
three §6 deferrals that are about the *declarator grammar* rather than about the
type system. `make test` 888 → **894 PASS / 0 FAIL** (+6 assertions, one new
unit `run_cd_declarators` + `tests/fixtures/cd-declarators.h`); `make bootstrap`
converged with **no boot refresh**; `make abi-test`, `make layout-test` and
`make check-headers` (69/69) green.

| id | shape | before | after |
|---|---|---|---|
| **CD-1** | a multi-declarator field line, `int a, b;` | the `,` abandoned the body; the struct went opaque (fails safe) | every declarator becomes a field, with its own stars, extents and bit-field width |
| **CD-2** | a typedef declarator list, `typedef int a, *b;` | only the first declarator was recorded; the rest were unknown names (fails safe) | every declarator is recorded, each with its own pointer depth and extents |
| **CD-3** | a with-body aggregate array typedef, `typedef struct Tag { … } Name[N];` | the extent was discarded and `Name` registered as a plain struct alias — `declare void @f(i64)` where clang says `ptr` (**silently wrong**) | `Name` is an `(array Tag N)` in the typedef table, and decays in parameter position |

### 8.1 Where the filed descriptions were wrong

**"Both fail safe … this is coverage" (§6) understated CD-1's reach.** It is
true of the *mechanism* — an abandoned body is an opaque type, not a wrong one —
but the roster it blocked was not small. Across the 40 standard headers
surveyed, CD-1 unblocks **`struct tcp_info`** (104 bytes, alignment 4, element
list identical to clang's), which glibc writes as
`__u8 tcpi_snd_wscale : 4, tcpi_rcv_wscale : 4;` — a bit-field run split across a
declarator list. Outside libc it unblocks **`SDL_Rect`** (`typedef struct
SDL_Rect { int x, y; int w, h; } SDL_Rect;`), and through it **`SDL_Surface`**
and `SDL_MessageBoxColor` — six new types on `SDL2/SDL.h` alone, and `SDL_Rect`
is arguably the most-used type in that API.

**The `stage15-stress-test/cheader.md` item 3 premise — "each declarator has its
own pointer depth, which a single-declarator parse cannot recover" — is exactly
right, and is the whole design.** `c-parse-type` consumes the specifier run *and*
the first declarator's `*` run, and collapses any depth ≥ 1 into a bare `ptr`
with no pointee — so when the first declarator is starred there is genuinely
nothing left to unwrap for the second. The fix does not try: `c-span-has-star`
asks whether the span `c-parse-type` consumed carries a `*`, and if it does the
base is recorded as lost. A later 0-star declarator then abandons the struct
(CD-1) or is recorded known-but-unrepresentable (CD-2). A later *starred*
declarator is `ptr` regardless, so `char *s, *t;` — the common case — is exact.

**§3.3's "two sites kept name-for-name" correction generalized to CD-3, and
needed a third mechanism.** The prescan (`cheader-scan-opaque-decl`) registered
the declarator of every body-bearing typedef as an opaque `StructDef`, and
`parse-type-name` probes the struct registry *before* the C typedef table — so
leaving that registration in place would have shadowed the array typedef the
import records and made CD-3 a no-op in exactly the positions (`defn` signature,
`defvar` type) the prescan exists for. Both sites now branch on the `[`. What
§3.3 does not cover is the **untagged** form, `typedef struct { … } Name[N];`:
the prescan cannot see an anonymous body's shape, so there is no `StructDef` for
it to anchor the array's element on. Both passes mint one instead —
`__carr.<typedef name>`, in the same shape and for the same reason as `__bf.N`
and `__anon.N` (a `.` is unspellable as a C or Nucleus identifier, which makes
"the compiler minted this" decidable with a `strncmp` and no extra state). The
import adopts the parsed body into that anchor, so `%__carr.cd_anonarr` is a real
defined type and `(defvar u:cd_anonarr)` is `[3 x %__carr.cd_anonarr]`.

### 8.2 What is left, and why it is not a defect

Declarators that **disagree in pointer depth** — `int *p, q;` in a struct body,
`typedef int *a, b;` at top level — are refused, for the reason above. A struct
gets the located opaque error at every by-value use and no `%X = type` line; a
typedef declarator is recorded known-but-unrepresentable, which is the state the
L5 diagnostics already distinguish from "absent". This is the §6 discipline
applied to itself: a shape the parser cannot represent is an error or a skip,
never a silent `ptr`. It is also now the L1 fixture's own witness — see 8.4.

~~Two shapes remain unhandled and were not in scope: a comma-separated
declarator list *after a struct body* (`typedef struct { … } A, B;` — `B` is
silently dropped today, and the shape is a `c-parse-struct-decl` item, not a
`c-parse-typedef-decl` one), and a mixed list of a struct definition and a
variable (`struct S { … } x, y;`).~~ **Both closed 2026-08-29 as CD-4 — §9.1.**

### 8.3 Measurements

- **IR sweep, 186 modules** (152 `examples/*.nuc` + 34 `lib/*.nuc`,
  `--emit-llvm` + stdout + stderr + exit code) against a baseline built from
  `HEAD:src/cheader.nuc`: **zero diff**. So was the 96-output header-mode sweep
  (`--emit-nuch` / `--emit-cheader` over `lib/` + `src/`), and so was
  `build/nucleusc.ll` compiled by each binary. §1.6 argued the sweep is
  *structurally blind* here and it is — the tree's six C headers contain none of
  the three shapes — which is also why no boot refresh was needed, against §5's
  general rule for importer changes (`c-boundary-defects.md` §13). The rule is
  the right default; the check that answers it is "does the shape occur in the
  compiler's own six headers", and here it does not.
- **Census, 40 standard headers**, emitted `%X = type` lines: **895 → 896**, the
  one delta being `%tcp_info`. `declare` sets and stderr were byte-identical for
  every one of the 40 — CD-1's new types are all passed by pointer in libc.
- **`SDL2/SDL.h`: 192 → 198** types (`SDL_Rect`, `SDL_Surface`,
  `SDL_MessageBoxColor` and three anonymous structs); `SDL_mixer.h`, `png.h` and
  `zlib.h` unchanged.
- Every layout above checked against `cc` on the same header: `tcp_info` 104/4,
  `SDL_Rect` 16, `SDL_Surface` 96, and the whole fixture roster.

### 8.4 Where it landed

| file | what |
|---|---|
| `src/cheader.nuc` — `c-span-has-star` (beside `c-span-has-ident`) | the one question both CD-1 and CD-2 ask: did the first declarator's stars consume the base? |
| `src/cheader.nuc` — `c-parse-struct-body` | `more` / `base-ty` / `spec-start`: a `,` continues the declaration instead of abandoning it, and the append path consumes the `,` exactly as it consumed the `;` |
| `src/cheader.nuc` — `c-parse-typedef-decl` | `base0` / `bad0` captured before the first declarator's paths rewrite them, then a declarator loop after the first record |
| `src/cheader.nuc` — `c-parse-struct-decl`, the body branch's typedef-name read | CD-3: an array declarator after the name records a typedef instead of registering a `StructDef` alias, anchored on the tag or on `__carr.<name>` |
| `src/cheader.nuc` — `cheader-scan-opaque-decl`, the body branch | the same branch in the prescan, name-for-name |
| `tests/fixtures/cd-declarators.h`, the `cd*` units in `tests/suite-declarators.nuc` | 6 assertions: exact type lines, `sizeof` vs `cc`, the mixed-pointer refusal, the typedef list's per-declarator lowering, CD-3's storage + decay, and `tcp_info` against `cc` |
| `tests/fixtures/l1-members.h` | **the L1 fixture's witness moved.** Its `c-parse-type:529` row was `typedef struct { int x; int a, b; } l1_multi_t;` — a multi-declarator line, chosen because BF-4 had made the previous witness (a bit-field) representable. CD-1 made *that* one representable in turn, so the row now uses CD-1's own residue, `int *a, b;`. The row guards "an unreadable by-value aggregate body marks the enclosing declaration", not any particular spelling, and it keeps guarding it. |

---

## 9. As built: CD-4 and the C-typedef `#include`

**Status: implemented 2026-08-29** on `stage16-ergonomics`, closing the last two
§6/§8.2 entries that are about what a C header *declaration* introduces and what
the generated header *exports*. `make test` 894 → **902 PASS / 0 FAIL** (+8
assertions across three new units); `make check-headers` 69/69 with **no
regeneration** (no committed header names a C typedef); `make abi-test`,
`make layout-test` and `make avr-test` green; `make bootstrap` converged after
`make update-bootstrap` (the compiler's own IR moved — `src/cheader.nuc`
changed).

### 9.1 CD-4 — a declarator list after a struct body

`typedef struct { … } A, B;` registered `A` and dropped `B` in silence.
`struct S { … } x, y;` left `x, y;` on the floor for the function-declaration
parser to make what it could of. Both are now a **declarator loop**, and every
declarator kind the shape admits is handled:

| declarator | before | after |
|---|---|---|
| a later plain name — `} A, B;` | `B` silently dropped | a second alias `StructDef` over the same shape |
| a pointer declarator — `} A, *Bp;` | `Bp` silently dropped (the ident read stops at `*`) | a typedef-table entry, `ptr` |
| a later array declarator — `} A, B[3];` | silently dropped | CD-3's array typedef, anchored on the tag or the minted `__carr.<name>` |
| a variable list — `} x, y;` | left unconsumed | consumed; the importer models no C variable, so nothing is recorded |
| a function declarator — `} f(void);` | mis-parsed | declined, and left to the caller's skip |

**The whole design is that there is now exactly one implementation.**
`c-struct-decl-declarator` (`src/cheader.nuc`) is what the *first* declarator
goes through as well as every later one — a second copy of the rule for later
declarators is precisely how `B` came to be dropped in the first place, and it
is the shape conventions.md's "a decay rule belongs in ONE function" warns
about. The pre-scan (`cheader-scan-opaque-decl`) mirrors the loop rather than
calling it, because it has no parsed body to anchor on; it stays name-for-name
with the import, which is the W3a/CD-3 rule — a *pointer* declarator registers a
typedef and **no** `StructDef`, or the opaque entry shadows the record the
import makes.

**Measurements.**

- **Occurrence count in the standard headers: zero.** Scanning the preprocessed
  text of 39 common system headers for a declarator run after a `}` containing
  a `,` finds 552 runs and **0** with a comma. §8.2's "not in scope" was right
  about libc; the reason to take it anyway is that a silent drop is the class
  L1 exists to remove, whatever the occurrence count.
- **Third-party is where it lands.** `png.h` writes
  `typedef struct png_image_struct { … } png_image, *png_imagep;`.
  `(defn f (p:png_imagep):i32 …)` was `error: unknown type: png_imagep (did you
  mean 'png_image'?)` and now compiles, with `%png_image` laid out. SDL2 and
  zlib have no instance.
- **Host IR sweep, 187 modules** (152 `examples/*.nuc` + 35 `lib/*.nuc`,
  `--emit-llvm` + stdout + stderr + exit code) against the committed boot
  compiler: **zero diff**. The tree's own headers contain none of these shapes,
  which is also why no host output moved.

### 9.2 The `#include` for a rendered C typedef

§6 recorded this as out of scope with a counter-argument — "a consumer of the
generated header is expected to `#include` the same C header itself" — and the
counter-argument does not survive contact with the artifact. `off_t` renders
**bare**, because `struct off_t` names nothing (the L5 arm in `type-name-to-c`),
so the generated header was:

```c
#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

off_t seek(int32_t fd, off_t off);
```

which is `error: unknown type name 'off_t'`, twice, under `clang -fsyntax-only`.
Not "a consumer must remember something": the header does not compile at all,
and `scripts/check-headers.sh` cannot see it because it only proves the
committed text matches the compiler.

**The decisive argument is that the emitter already accepts the rule.** It
writes `#include <stddef.h>` unconditionally, for exactly one reason — it
renders `usize` as `size_t` and `ssize` as `ptrdiff_t`, and a name it spells
needs the header that defines it. `off_t` → `#include <unistd.h>` is that same
rule applied to a name the emitter *learned* rather than one it hardcodes. So
this is not a new policy; it is the existing policy reaching the dynamic half of
`type-name-to-c`.

**The spelling is the import's, not the linemarker's.** `CTypedef` gained an
`hdr` field carrying the `(import-use "…")` string, set from
`g-cheader-import-header` (`src/type-utils.nuc`, beside the table, for the same
cross-import reason) at the top of `emit-c-include` **and**
`cheader-prescan-opaque` — and, unlike `g-cheader-file`, never rewritten by a
`# N "file"` linemarker. That distinction is the whole point: `off_t` physically
lives in `/usr/include/x86_64-linux-gnu/bits/types.h` behind a feature-test
macro, and `#include "/usr/include/…"` would be both unportable and wrong.
`#include <unistd.h>` is portable, and re-including it is precisely what
reproduces the typedef the compiler read. Angle brackets unless the import
spelled a path (leading `/` or `.`), in which case it is quoted.

`--emit-cheader` runs only the pre-scan, never `emit-c-include`, so the
provisional records are the ones the emitter reads — which is why the global has
to be set in both places.

### 9.3 What is still not included, and why

A **C struct or union tag** rendered `struct SDL_Rect` still produces no
include. An incomplete tag is legal behind a pointer, which is how a C API is
overwhelmingly used, so the header compiles; a *by-value* parameter of one
parses and then cannot be called — the silent asymmetry conventions.md records
under "In C, a typedef is not a tag". It is a real gap and it is deferred, for a
concrete reason: the include would have to come from the `StructDef`, whose
`src-file` is the **linemarker** path (`/usr/include/…`), not an import
spelling. Closing it means a second provenance field on `StructDef` written at
its four registration sites — the same shape as `CTypedef.hdr`, but four writers
instead of one, and `cheader-note-type-file`'s "only a `.nuc`/`.nuch` file" gate
would have to split rather than return. Worth doing when a by-value C struct
appears in a public Nucleus signature; nothing in `lib/` has one today, so it
would move no committed header.

### 9.4 Where it landed

| file | what |
|---|---|
| `src/cheader.nuc` — `c-struct-decl-declarator` (new, above `c-parse-struct-decl`) | CD-4: the one implementation of "record one declarator of a body-bearing declaration", used by the first declarator and every later one |
| `src/cheader.nuc` — `c-parse-struct-decl`, after the body | the declarator loop: stars, then the helper, then `,` continues / `;` ends |
| `src/cheader.nuc` — `cheader-scan-opaque-decl`, the body branch | the same loop in the pre-scan, name-for-name (a pointer declarator records a typedef and no `StructDef`) |
| `src/type-utils.nuc` — `CTypedef.hdr`, `g-cheader-import-header`, `c-typedef-record` | the import spelling a typedef was reached through |
| `src/cheader.nuc` — `cheader-note-c-include`, `cheader-c-include-spelling`, `cheader-emit-c-includes`, `g-cheader-c-includes` | the second include list and its angle-bracket spelling rule |
| `src/cheader.nuc` — `type-name-to-c`, the L5 typedef arm | notes the header before returning the bare name |
| `src/cheader.nuc` — `emit-cheader-header` | resets the list, emits it after `<stddef.h>` and before the borrowed Nucleus units' headers |
| `tests/fixtures/cd4-declarator-list.h`, the `cd4-*` units in `tests/suite-declarators.nuc` | 2 assertions: exact type lines for every declarator of every list (including the array declarator's `[3 x %__carr.cd4_G]` storage), and every `sizeof` against `cc` |
| `tests/run-tests.sh` `run_cheader_c_include` | 2 assertions: the `#include` is present, is the import spelling (never `/usr/include/…`), the declaration is the bare name, the header passes `clang -fsyntax-only`; and a header naming no C typedef gains no include |
| `tests/run-tests.sh` `run_l5_typedef_names` item 8 | its "known gap, recorded rather than asserted" note is now an assertion |

---

## 10. As built: user-declarable declaration attributes (§3.4's scope note, taken 2026-08-29)

`(defn my-setjmp (b:ptr):i32 :returns-twice …)` now says what only the C
importer's by-name list could say before. The item as filed is one attribute;
what landed is the **attribute slot**, because adding a keyword-spelled
`:returns-twice` beside a bare-symbol `noreturn` would have recreated exactly
the two-spellings-for-one-idea state `keyword-markers.md` exists to remove.

### 10.1 Decisions

| | |
|---|---|
| Spelling | `:noreturn` / `:returns-twice` — keywords, per `keyword-markers.md` §1 ("keywords already carry markers elsewhere") |
| `returns_twice` → `returns-twice` | hyphen: the Nucleus spelling of the LLVM token, matching the `Sym` field name |
| Position | `defn`: between the return operand and the body. `declare`: after the return operand. Both accept a **run**, in either order |
| Old spelling | bare `noreturn` / `returns_twice` retired — a located error naming the replacement, the same retirement shape §3 of `keyword-markers.md` used |
| A lone trailing form | always the body, never an attribute — `(defn kw ():Keyword :noreturn)` returns the keyword |

### 10.2 The dispatch sites, enumerated

`container-type-sugar.md`'s warning applies with a different count.
`returns_twice` is not a top-level form, so the six-site list does not transfer;
the honest enumeration is **"every pass that reads or writes a signature"**, and
it is seven:

| # | site | what it does |
|---|---|---|
| 1 | `emit-defn` (`src/nucleusc.nuc`) | consumes the run via `defn-scan-attrs`; body-start shifts past it |
| 2 | `emit-defn`'s `scope-define` | sets `Sym.noreturn` / `Sym.returns-twice` — **solitary names only** (an overloaded method has no `Sym`; pre-existing, unchanged) |
| 3 | `emit-defn`'s `define` line | ` noreturn` / ` returns_twice`, before `emit-fn-attrs-for`'s string attributes |
| 4 | `emit-nuch-declare` / `emit-nuch-defmethod` (`src/nuch.nuc`) | re-emits the run onto the exported entry, via `emit-nuch-fn-attrs` |
| 5 | `nuch-declare-import` | strips the trailing run (`declare-scan-attrs`), sets the `Sym` fields, emits the LLVM attributes |
| 6 | `nuch-defmethod-import` | same, with `min-len` 5 rather than 4 |
| 7 | the generic-template export | verbatim `print-node`, then re-parsed by `emit-defn` at stamp time — free, and only because the run sits inside the form |

Two more that needed **checking and no change**: `--emit-cheader` renders neither
attribute (C's `_Noreturn` / `__attribute__((returns_twice))` are not emitted
today, for `noreturn` either), and the REPL's preamble `declare`s carry neither
(also pre-existing; an attribute-free `declare` is legal IR, and the REPL JIT
runs at -O0). `g-special-form-set` needs nothing — a keyword cannot be a
definition name.

The one site that was **missing before this change**: `emit-nuch-declare` never
carried `noreturn` either, so a `(defn f ():void :noreturn)` exported to a
`.nuch` silently lost it. Fixed for both attributes together.

### 10.3 What the filed description got wrong

**"a `.nuch` `declare` keyword for symmetry with `noreturn` if that costs
nothing"** assumes `noreturn` already round-trips. It does not: `nuch-declare-import`
*reads* a trailing attribute, and nothing *wrote* one, because
`--emit-nuch` never re-exports a top-level `declare` and `emit-nuch-declare`
(the `defn` exporter) did not print it. The reader had no writer.

**The `declare` reader also had to stop being last-token-only.** It examined
exactly the final operand, so two attributes could not be written at all; and
its floor has to be the entry's attribute-free length (4 for `declare`, 5 for
`defmethod`), because a *return type* is a keyword too and a naive scan from the
end would eat it.

### 10.4 The bootstrap cost, and why it was two refreshes

`src/reader.nuc`'s own `die-at` carries the attribute, and `src/` is what the
committed boot compiles — the fourth chicken-and-egg root cause in
`context/build.md`. So the retirement could not land with the sweep in one step:

1. Accept **both** spellings (`decl-attr-kind` falling through to
   `legacy-fn-attr-kind`), sources unchanged. Refresh.
2. Sweep `src/reader.nuc` and `tests/fixtures/s1-sugar-rets.nuc` — the only two
   uses of the bare spelling in the tree — delete the shim, refresh again.

Identical in shape to `keyword-markers.md` §4, and one line of sweep rather than
58 files, because a declaration attribute is rare where a parameter marker is
not.

### 10.5 Still write-only, deliberately

No Nucleus-side consumer was added, and §6's note is revised rather than
retracted. LLVM computes the caller-side consequences (no tail call, alloca
placement, stack colouring) from the attribute on the *call*, which it gets from
the callee's `define`/`declare`; there is nothing for the front end to narrow or
refuse. `:noreturn` remains the only one of the two with a reader
(`terminate-after-noreturn`).

### 10.6 Where it landed

| file | what |
|---|---|
| `src/nucleusc.nuc` — `legacy-fn-attr-kind`, `reject-legacy-fn-attr`, `decl-attr-kind`, `defn-scan-attrs`, `declare-scan-attrs` (new, beside `marker-any`) | the recognizer, the retirement, and the two scan shapes |
| `src/nucleusc.nuc` — `emit-defn` | the run replaces the single-`noreturn` test; `Sym.returns-twice`; ` returns_twice` on the `define` |
| `src/nuch.nuc` — `emit-nuch-fn-attrs`, `emit-nuch-declare`, `emit-nuch-defmethod` | the export half, which did not exist |
| `src/nuch.nuc` — `nuch-declare-import`, `nuch-defmethod-import` | trailing-run strip; attributes emitted additively so a `declare` and its `define` agree |
| `src/reader.nuc` — `die-at` | the sweep |
| `tests/fixtures/s1-sugar-rets.nuc` | the sweep |
| `tests/run-tests.sh` — `run_s16_decl_attrs` | 5 assertions: the `define` (both attributes, both orders, and an unattributed defn gaining none), the `declare` plus `terminate-after-noreturn`, the `.nuch` round-trip solitary **and** overloaded, the two retired spellings, and the lone-trailing-form rule |
| `docs/toplevel.md` — "Declaration attributes" | the user-facing section, plus the `defn`/`declare`/`fn-attr` rows |
| `docs/structs-unions.md` — libc attributes | points at it: the by-name list is only how the attributes are *recovered* from a C header |

---

## 11. As built: retiring `src/repl_shim.c` (2026-08-30)

The last C source file in the tree is gone. `src/repl.nuc` now carries all four
of its functions in Nucleus, and neither the `Makefile` nor `build.ps1` compiles
C any more.

### 11.1 Both halves fell to work that had already landed

* **`repl_protect` / `repl_throw`** needed `jmp_buf`, which is what L1–L5 made
  expressible; `examples/setjmp-guard.nuc` is the worked example §7 predicted.
* **`repl_print_f64` / `repl_print_f32`** needed to *call* a JIT'd nullary thunk
  returning a float. That is FP-2 ([c-boundary-defects.md](c-boundary-defects.md)
  §2.4): an indirect call is now ABI-lowered and coercing, so a parameter typed
  `(fn f64)()` is callable directly and the C wrapper had nothing left to do.
  The call sites in `repl-eval-form` gained one cast each —
  `(unsafe/cast ((fn f64)()) (unsafe/cast ptr addr))` — because `unsafe/cast`
  refuses `i64` straight to a function-pointer type; the `ptr` hop was already
  there.

### 11.2 The one place the C shape did not port, and the better shape it forced

The C shim held a `static jmp_buf repl_jmpbufs[16]`. The Nucleus transcription
`(defvar g-repl-jmpbufs:(array __jmp_buf_tag REPL-MAX-PROTECT))` is **refused**,
and the refusal is correct: a `defvar`'s type is resolved by `prescan-defvar-name`,
which runs before any `(import-use "setjmp.h")` is read, so the only thing
registered under that tag at prescan time is the layout-less placeholder
`cheader-prescan-opaque` puts there (§1.3, W3a), and an array element with no
layout is exactly what `reject-opaque-type` exists to stop. Three neighbouring
spellings are unaffected and show the boundary precisely: `(defvar env:jmp_buf)`
(a C *typedef*, re-resolved by `emit-defvar`), `(alloca (array __jmp_buf_tag 1))`
(a body, emitted after the import) and `(defstruct H xs:(array __jmp_buf_tag 4))`
(the W9-item-40 layout prescan defers instead of refusing).

So each protected frame **allocas its own jump buffer** and publishes the pointer
into a global `(array raw 16)` stack. That is strictly better than the C shim,
and for a reason worth keeping: the buffer now lives in exactly the frame the
`longjmp` returns into, its lifetime is the protection's lifetime rather than the
process's, and the stack needs no target-dependent extent. §3.4's two
load-bearing properties are preserved unchanged — the body is still a callback,
so the `_setjmp` frame is live when the throw fires, and the depth counter still
makes the unarmed case a diagnostic-and-`exit` rather than a jump into a returned
frame.

`_setjmp` (not `setjmp`) and `longjmp` are the pair, matching what C source
spelling `setjmp(e)`/`longjmp(e,1)` actually calls on glibc — §7's first caveat,
now load-bearing in the compiler itself rather than only in an example. The depth
local is `:volatile`, per §7's third.

### 11.3 The staging

Two refreshes were budgeted; **one** was needed, because the natural Nucleus
spellings are already distinct symbols — `@repl-protect` versus `@repl_protect`
— so there was never a duplicate-definition window and never a rename to undo.

1. Add the Nucleus definitions, switch every call site, delete the four
   `(declare …)` lines, leave the shim linked. `make bootstrap` converged on the
   first try (the change is purely additive to the compiler's own source; it
   alters no compilation behaviour), then `make update-bootstrap`.
2. With all three boot IRs no longer naming the shim's symbols, delete
   `src/repl_shim.c` and its nine `Makefile` references, its five in `build.ps1`,
   and the now-unused `CFLAGS`. Nothing in `src/` changed, so the IR did not move
   and `boot/nucleusc.ll` was already the fixed point — no second refresh.

### 11.4 Measurements

* `make test` 913 units, 0 FAIL — unchanged, including all 14 `tests/repl/`
  fixtures (`repl-s16-macrolet`'s `error (recovered)` line and
  `repl-import-error` among them).
* Batch IR sweep, 187 modules (`examples/*.nuc` + `lib/*.nuc`): `--emit-llvm`
  output **and** stderr byte-identical to the pre-change compiler's, exit codes
  equal. The REPL is the only thing that moved.
* A 11-form REPL probe covering `f64`, `f32`, `nan`, `inf`, `%.17g` round-trip
  and two recovered errors: output byte-identical between the old binary and the
  new one.
* `make bootstrap`, `make abi-test`, `make layout-test`, `make check-headers`,
  `make avr-test` all green.
* The compiler's own IR grows by 6 `declare`s (`setjmp`, `__sigsetjmp`,
  `_setjmp`, `longjmp`, `_longjmp`, `siglongjmp`) and 2 types
  (`%__jmp_buf_tag`, `%__sigset_t`) — the ordinary "widening the declare set"
  cost recorded in `context/conventions.md`. 234 struct types, against
  `MAX-STRUCTS` 1024.

### 11.5 One caveat, recorded rather than fixed

The Windows boot IRs are cross-emitted on this Linux host, and `clang -E` cannot
find a Windows sysroot here, so they are built from the **host's** headers — a
warning `make windows-boot` already printed five times and now prints six. Until
now that was inert: every host-header type in the compiler's IR (`%__FILE`,
`%__locale_struct`, …) is only ever used behind a pointer. `repl-protect`'s
`alloca [1 x %__jmp_buf_tag]` is the first host-header **layout** the compiler's
own code depends on, and glibc's 200 bytes is smaller than mingw-w64's `jmp_buf`.

The exposure is one binary deep and does not reach a real Windows build:
`build.ps1` uses the committed boot IR only to link the *first* `bin\nucleusc.exe`,
which it then drives in **batch** mode (`--emit-llvm`) to produce
`build\nucleusc.exe` — and that self-hosted emission preprocesses `setjmp.h` with
the real Windows headers, so the compiler anyone actually uses has the right
size. The undersized `alloca` exists only in a boot binary whose `-i` flag is
never used. Passing `--sysroot` to `make windows-boot` closes it outright.

### 11.6 Where it landed

| file | what |
|---|---|
| `src/repl.nuc` — new header block | `(import-use "setjmp.h")`, `REPL-MAX-PROTECT`, `g-repl-jmpbufs`, `g-repl-depth`, `repl-protect`, `repl-throw`, `repl-print-float-buf`, `repl-print-f64`, `repl-print-f32` |
| `src/repl.nuc` — `repl-eval-form`, `repl-preload-prelude`, `repl-main` | the five call sites, plus the two `(fn f64)()` / `(fn f32)()` casts |
| `src/nucleusc.nuc` | the four `(declare …)` lines deleted; three `repl-throw` call sites |
| `src/reader.nuc` — `die-at` | the fourth `repl-throw` call site |
| `src/repl_shim.c` | **deleted** |
| `Makefile`, `build.ps1` | every shim reference, the compile rule, and `CFLAGS` |
| `docs/structs-unions.md` — libc attributes | the second worked example, and the `(array Tag N)`-in-a-`defvar` boundary |
