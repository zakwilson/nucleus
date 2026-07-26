# W3 — C header interop

**Findings:** §1.6 (opaque forward-declared types never register), §1.5 (platform
intrinsics headers mis-parse into invalid IR), §1.4 (`import-use "unistd.h"`
corrupts an unrelated hand-declared signature).

**Goal:** `(import-use "some/real/header.h")` works for a mainstream C library.
Today it does not, for three independent reasons, and the practical consequence is
severe: the Doom port hand-`declare`s **every** SDL2, SDL2_mixer, libpng and POSIX
function it uses, and hand-mirrors every opaque type. That is ~200 lines of
boilerplate the language exists to avoid.

`design/overview.md` states the goal directly — *"C interop — include C libraries
and call C functions with no overhead"*, *"a drop-in replacement for C … must be
able to use any C library's functions and data structures"*. W3 is the gap between
that and reality, and it is the finding most likely to be the **first** thing a
new user hits.

---

## Ground truth

The C declaration parser is `src/cheader.nuc` (~1072 lines). It is hand-rolled,
not clang-based, though `import-use` of a header does shell out to
`clang -E -x c -include <path> /dev/null` to preprocess.

### §1.6 — the opaque-type gap is one branch

`src/cheader.nuc:558-560`:

```lisp
; Expect '{' for a definition (forward decls/uses fall back to skip).
(when (or (>= pos len) (!= (char-at buf pos) 123))
  (ptr-set! out-end pos) (return 0))
```

A `struct Foo;` with no body is **skipped entirely**, so the type never registers
and a later `ptr:Foo` dies `unknown type: Foo`. This is C's standard
opaque-handle idiom — `typedef struct SDL_Window SDL_Window;` — so every SDL
handle type is unusable.

The fix is small and local: **register an opaque `StructDef` (name only, no
fields, size/align unknown) instead of returning 0.** The registry already
supports a name-only registration — `register-struct` is called with just a name
by `prescan-struct-names` (`src/nucleusc.nuc:8936`) and fields are filled in
later. An opaque type must then be usable exactly as far as C allows:

* `ptr:Foo` — legal, and that is all anyone needs for a handle.
* `(sizeof Foo)`, field access, by-value parameters/returns, `alloca` — must be a
  **clean diagnostic** ("`Foo` is an opaque type declared at header.h:12; only
  pointers to it are valid"), never a crash and never a silently-wrong size.

If a later definition with a body arrives for the same tag, it must upgrade the
opaque entry in place rather than colliding — the typedef-alias path at
`src/cheader.nuc:570-585` already shares shapes between a tag and its typedef
name, so follow that model.

### §1.5 — intrinsics headers produce invalid IR

`(import-use "SDL2/SDL.h")` transitively reaches a platform-intrinsics header via
`SDL_cpuinfo.h`, which the parser turns into
`declare void @_mm_clflush(void, ptr)` — invalid IR, caught only at the very end
of compilation as `failed to parse generated IR`. Reproduces from a two-line
probe; not driver- or version-specific.

Two things are wrong and they should be fixed separately:

1. **The parse is wrong.** A `void` parameter in a non-empty parameter list is
   never valid C. Whatever produces `(void, ptr)` is mis-associating a type.
   Find it, fix it.
2. **The failure mode is wrong.** A declaration the parser cannot represent should
   be **skipped with a warning naming the header and line**, not emitted as
   invalid IR to be discovered by the LLVM parser thousands of lines later. This
   is the more important half: it converts an entire class of "header X explodes"
   into "header X's function Y was skipped", which is survivable and diagnosable.

Prefer a conservative validity gate on every synthesized `declare`: no `void`
among multiple params, no unresolved type names, params and return type all
representable. Anything failing the gate is skipped with a warning. Compiler-
internal headers must still pass the gate, so run the gate against `make
lib-cheaders` output as a check.

### §1.4 — a header import corrupts unrelated signatures

`(import-use "unistd.h")` makes `close` resolve, and then a correctly
hand-`declare`d `lseek` elsewhere in the same unit starts failing:
`return type mismatch — returned value of type ptr does not match declared return
type i64`. The real header's `off_t` typedef chain is misparsed to `ptr`.

Two defects again:

1. **`off_t` resolves to `ptr`.** Trace the typedef chain
   (`off_t` → `__off_t` → `long int`) and find where it degrades. A typedef to a
   builtin integer type must resolve to that integer type; a typedef the parser
   cannot follow must be an **error or a skip**, never a silent `ptr`.
2. **A header import silently overrides a hand-`declare`.** That is the more
   dangerous half: the user wrote an explicit, correct declaration and the header
   quietly replaced it. Decide the precedence rule, document it, and diagnose the
   conflict. Recommended: **an explicit `declare` wins over a header-derived one,
   and a mismatch warns**, naming both sources. Silent last-wins is how §1.4 cost
   a debugging session.

---

## Design notes

### Scope discipline

W3 is **not** "replace the hand-rolled parser with libclang". That is a much
larger project and may be the right long-term answer
(`design/stage3b-interop.md` and `stage3c.md` are the existing interop design
docs — read them and note whether this work changes their conclusions). W3's bar
is:

> A mainstream C library header can be `import-use`d, its opaque handle types are
> usable as pointers, and anything the parser cannot represent is skipped with a
> located warning instead of breaking the build.

"Skipped with a warning" is a legitimate destination. A user who gets 95% of a
header plus three named warnings is in vastly better shape than one who gets
`failed to parse generated IR`.

### Target headers for verification

Pick a ladder, cheapest first, and record which rung is reached:

1. `<unistd.h>` / `<fcntl.h>` — the §1.4 case; small, typedef-heavy.
2. `SDL2/SDL.h` — the §1.5 case; the umbrella-header stress test, and the one
   the port actually needs.
3. `SDL2/SDL_mixer.h` — smaller, and exercises §1.6 hard (`Mix_Music`,
   `Mix_Chunk` are opaque; `Mix_Chunk` the port had to model field-for-field).

Note the port's own related discovery, which is **not** a compiler bug and should
not be chased: several `Mix_*` "functions" are preprocessor macros with no symbol
to link (`Mix_GetError` is `#define`d to `SDL_GetError`). `design/overview.md`
already says Nucleus consumes C functions and data structures **but not its
macros**. Header import will never surface those, correctly. Make sure the
resulting diagnostic for a missing symbol is clear enough that a user reaches for
`nm -D` rather than assuming the importer failed.

---

## Verified repro (as of this doc)

The port's `src/sdl.nuc` header comment records the full worked investigation
with verified byte offsets — read it (`/home/zak/code/nuc-doom-claude/src/sdl.nuc`,
lines 1-175) rather than re-deriving. For §1.6 specifically, two lines suffice:

```lisp
(import-use "SDL2/SDL.h")
(defn f (w:ptr:SDL_Window):i32 (return 0))
```
→ `unknown type: SDL_Window`

---

## Accept criteria

* **§1.6:** opaque forward-declared struct types register and are usable as
  `ptr:T`. Misuse (by-value, `sizeof`, field access) gives a located diagnostic
  naming the header and line. A later full definition upgrades the entry.
* **§1.5:** `(import-use "SDL2/SDL.h")` no longer produces invalid IR. Either the
  intrinsics declarations parse correctly, or they are skipped with a warning
  naming the header and line. The two-line probe above compiles.
* **§1.4:** `off_t` and its typedef chain resolve to an integer type. A
  header-derived declaration conflicting with an explicit `declare` warns and the
  explicit one wins; the precedence rule is documented.
* At least rung 1 and rung 3 of the header ladder work end to end, with a runnable
  test that calls a real function through an imported header. Record how far up
  the ladder you got and what blocks the next rung.
* `make test` green; `make bootstrap` byte-identical (the compiler's own
  `lib-cheaders` path must be unaffected — verify explicitly, since W3 touches
  shared code).
* `docs/` documents opaque types, the skip-with-warning policy, and the
  declaration-precedence rule. Note in `design/stage3b-interop.md` /
  `stage3c.md` whether W3 changes their conclusions.
