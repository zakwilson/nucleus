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

---

## W3a as built (§1.6 — opaque forward-declared types)

**Status: done.** `make test` 255 PASS / 0 FAIL (was 245); `make bootstrap`
byte-identical without a boot reconverge; `make lib-cheaders`, `make lib-headers`
and the emitted IR of every `lib/*.nuc` and `examples/*.nuc` byte-identical
against a compiler built from the pre-change tree.

W3b (the §1.5 validity gate) and W3c (§1.4 typedef chains + declaration
precedence) are untouched and remain open.

### Representation

`StructDef` gained two slots (`src/compiler-types.nuc`):

* **`opaque:i32`** — 1 means *the name is known, the layout is not*. Set only by
  the cheader path. Cleared in **`struct-set-fields`** (`src/abi.nuc`), the single
  chokepoint every field-populating path funnels through (`emit-defstruct`, the
  `.nuch` import, the cheader body parser, the anon-struct/union memoizer, the
  closure-env and fatptr builders) — so "acquires a layout" and "stops being
  opaque" cannot drift apart.
* **`alias-of (raw StructDef)`** — for a C `typedef struct Tag Name;`, the `Tag`
  entry. `lookup-struct` is keyed by name, so an alias must be its own StructDef;
  this link is the only thing connecting the two, and it is what lets a later
  `struct Tag { … }` upgrade an alias registered while the tag was still opaque.

An opaque entry is deliberately **not** the same state as a name-only
pre-registration by `prescan-struct-names`: the latter's layout arrives later in
the same unit, and nothing may reference it by value before it does.

### Upgrade paths

Three, all routed through one emitter (`cheader-struct-define` /
`cheader-adopt-shape`, `src/cheader.nuc`) so an upgraded tag is
indistinguishable in the IR from one whose body came first — exactly one
`%Tag = type { … }` line, or one `g-pending-unions` entry for a union:

1. `struct Tag;` … `struct Tag { … };` — `c-parse-struct-body`'s
   already-registered branch used to `return existing` untouched (which would
   have pinned the tag opaque forever); it now fills the existing StructDef in
   place, keeping the pointer identity every `ptr:Tag` Type already handed out
   depends on.
2. `typedef struct Tag { … } Name;` after a `struct Tag;` — this shape parses its
   body **anonymously** and never registers `Tag` at all, so the tag is adopted
   from the anon shape explicitly.
3. `typedef struct Tag Name;` where `Name` was forward-declared — the alias
   registration path upgrades an existing opaque entry instead of skipping it
   (`(when (= (lookup-struct tname) null) …)` previously meant "already known,
   leave alone").

### Diagnostics

`reject-opaque-type` + `opaque-sdef-of` live in **`src/type-utils.nuc`**, not
beside `register-struct` in `abi.nuc`: `type-to-ir` is in type-utils and a call
from there up into abi.nuc would be an unresolved cross-import forward reference
(the wall SM-5 documents). Message shape:

```
<path>:<line>: error: sizeof: 'CHOpaque' is an opaque type declared at ./foo.h:11; only pointers to it are valid
```

Six explicit call sites, each with a node in hand so the location is exact:
`emit-sizeof`, `emit-alloca-form`, `emit-field-get` and `emit-get-intrinsic`
(beside the existing `union-field-guard` — the same guard slot), `emit-defn`'s
parameter loop and return type, and `emit-defstruct`'s field loop. Plus a
**backstop in `type-to-ir`'s TY-STRUCT/TY-UNION branch** using the ambient
`g-form-line`, so no path can put an undefined `%Foo` into an IR stream and turn
a source-level mistake into an LLVM parse error thousands of lines later. All 149
`type-to-ir` call sites are IR emission (no describe-only caller), so the backstop
cannot fire during a probe.

The header:line provenance comes from clang -E's `# N "file"` linemarkers, which
the top-level scan loop now records (`cheader-note-linemarker` /
`cheader-line-at`, best-effort by construction and never used to make a
decision). Before this, a cheader StructDef recorded `g-source-path` — the `.nuc`
file that did the importing — and line 0.

### Premises in the brief/spec that proved wrong

1. **"The fix is small and local: one branch."** It is not, for two reasons the
   spec did not anticipate:

   * **`c-parse-type` had to be taught to *ignore* opaque tags.** Its
     `struct Tag` lookup is reached only for a **by-value** `struct Tag` in a
     parameter, return, or field position, and it returns `ty-ptr` for an
     *unregistered* tag. Registering opaque types without guarding it would have
     turned those into `TY-STRUCT` and emitted `declare void @f(%Tag)` for an
     undefined `%Tag` — trading today's wrong-ABI pointer for invalid IR, i.e.
     manufacturing more of the §1.5 failure this stage exists to remove.
     Converting those into a skip-with-warning is W3b's job; W3a preserves the
     status quo exactly.
   * **The spec's own §1.6 probe cannot pass from import-time registration
     alone.** `(defn f (w:ptr:SDL_Window):i32 …)` resolves its types in
     `prescan-defn-signatures`, which runs **before any import is processed**, and
     `prescan-imported-types` deliberately skips C-string imports ("no Nucleus
     types; reading would invoke clang"). So a C header type in a **signature**
     was unresolvable independently of opaque registration. W3a adds
     `cheader-prescan-opaque` — a name-only scan (`cheader-scan-opaque-decl`)
     hooked into `prescan-imported-types` — that registers exactly the names the
     real import will define, so the real import then upgrades the same entries
     and emits the same single type definition. This also fixed the neighbouring
     asymmetry (`ptr:Mix_Music` resolving in a signature while the fully-defined
     `ptr:Mix_Chunk` did not).

2. **"`unknown type:` currently reports `:0:` … W4a did not reach this one."**
   True, and the root cause is one level up from the raise: `prescan-defn-signatures`
   resolved a signature's types against `((ptr:Node name-node) line)` — the defn's
   **name**, an interned NODE-SYM whose line is always 0 — and `desugar-typed`
   stamped every desugared binding cell with `(n line)` from the same kind of
   interned symbol. Fixed at both: the prescan borrows the return operand's line
   (falling back to the defn form's), and `desugar-typed` / `desugar-params` /
   `desugar-let-bindings` now take an `encl` fallback line from the enclosing
   form. That last change gives a real line to *every* diagnostic raised off a
   defn parameter, `defvar`/`extern`/`declare` name, `defstruct` field, or
   `let`/`with` binding name — the parameter case now reports the parameter
   **list's** line rather than the defn's.

3. **"`SDL2/SDL.h` does not import cleanly — it dies in the §1.5 invalid-IR
   path."** Both halves were true, but they are sequenced: the *old* compiler
   never reached §1.5 for the spec's two-line probe, because it died first at
   `unknown type: SDL_Window` (`:0:`). §1.6 is now fixed for it — the probe's
   `--emit-llvm` exits 0 — and it fails at the §1.5 defect only when the IR is
   actually parsed (`nucleusc … -o out` → `declare void @_mm_clflush(void, ptr)`,
   "void type only allowed for function results"). **`--emit-llvm` never parses
   the IR**, so exit 0 there is not evidence of a valid module; W3b's gate is
   unchanged and still needed. `SDL2/SDL_mixer.h` remains the clean §1.6 vehicle.

4. **`MAX-STRUCTS` (256) is now reachable.** It was a per-program-types bound;
   opaque registration makes the registry scale with *header* size instead.
   Measured: `SDL.h` + `SDL_mixer.h` + `png.h` in one unit needs **between 200 and
   256** slots (fails at 200, passes at 256) — one more umbrella header would have
   broken it. Raised to 1024; `g-structs` is a `Vector`, so the constant is only a
   runaway-growth guard, not a preallocation.

### Incidental fix: preprocessed-header caching (and a latent double-free-shaped bug)

`clang -E -x c -include <path> /dev/null` is a pure function of the path, but a C
header import is deliberately **not** deduplicated (each import may alias under a
different prefix), so a header was preprocessed once per `(import-use …)` naming
it — and W3a's name pre-scan would have added one more. `cheader-preprocess` now
caches the text by path: a `hello.nuc` build went from **5 clang invocations to
3**, and is ~30% faster end to end than before W3a rather than ~40% slower.

Sharing the buffer surfaced that `emit-c-include` ended with **`(free buf)`**.
With a fresh buffer per call that was correct; with a shared one it left every
later reader walking freed memory, which presented as a *hang* (the parser
looping over garbage), not a crash — and only on the **second** import of the
same header, i.e. not in any single-header test. Removed; the cache owns the
buffer, and since nothing ever freed the buffers that outlive the parse anyway,
total allocation strictly went down.

### Tests

* `examples/cheader-opaque.nuc` + `tests/expected/cheader-opaque.out` +
  `tests/fixtures/cheader-opaque.h` — the **runnable** half: a real
  `tmpfile`/`fprintf`/`fseek`/`fgets`/`fclose` round trip through `ptr:FILE`
  (including a `defn` whose parameter is `ptr:FILE`), a never-defined tag and a
  typedef alias of one used as pointers, and all three upgrade orderings.
* `tests/fixtures/w3a-opaque-{sizeof,alloca,field,param,return}.nuc` — pinned with
  `run_reject_at`, so the message text **and** the `<path>:<line>:` prefix are
  both asserted. They use the fixture header's `CHOpaque`, not `FILE`:
  whether `FILE` is opaque depends on the host libc's `struct _IO_FILE` body, and
  a rejection test must not.
* `run_w3a_opaque_provenance` — pins the `declared at <header>:11` half (the path
  is host-dependent for a system header, so `run_reject_at` cannot).
* `run_w3a_sdl_mixer` — compile-only (linking needs `-lSDL2_mixer`;
  `run-tests.sh` has no per-test link-flag mechanism), SKIPs cleanly without the
  SDL2 headers. Asserts the **emitted IR**: `%Mix_Chunk` has a real layout and a
  real GEP, the opaque handle is passed as a plain `ptr`, and `%Mix_Music` never
  appears as an LLVM aggregate type.
* `tests/fixtures/w3a-unknown-type-{param,return}.nuc` — the located
  `unknown type:`; also feed the `run_no_line_zero` sweep.

### Header ladder reached

* **Rung 1** (`<unistd.h>`, `<fcntl.h>`): imports cleanly; the §1.4 `off_t`
  defect is untouched (W3c).
* **Rung 3** (`SDL2/SDL_mixer.h`): opaque `Mix_Music` and fully-defined
  `Mix_Chunk` both usable from one import, in signature position — the accept
  criterion for §1.6.
* **Rung 2** (`SDL2/SDL.h`): §1.6 no longer blocks it (`ptr:SDL_Window` resolves);
  blocked on **§1.5** only.

### Newly observed, not fixed here

* **`Uint8`/`Uint32`-typed fields degrade to `ptr`.** `Mix_Chunk.volume`
  (`Uint8`) types as `ptr`, so `(c volume)` fails a `return type mismatch` while
  `(c allocated)` (`int`) works. This is §1.4's typedef-chain defect showing up in
  a *field* rather than a return type; W3c should cover it. It is why the
  SDL_mixer fixture reads `allocated`.
* A `struct Tag *fn(…);` at header top level still registers only the tag and
  skips the function (pre-existing); the tag being registered opaque is new and
  makes `ptr:Tag` usable, which is a strict improvement.
