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

---

## W3b as built (§1.5 — type qualifiers and the `declare` validity gate)

**Status: done.** `make test` 258 PASS / 0 FAIL (was 255); `make bootstrap`
byte-identical without a boot reconverge; `make lib-cheaders` output and the
emitted IR of every `lib/*.nuc` and `examples/*.nuc` byte-identical against a
compiler built from the pre-change tree.

`(import-use "SDL2/SDL.h")` now imports cleanly: the spec's two-line probe
compiles, **links, and runs** (`tests/fixtures/w3b-sdl.nuc`, built with `-o` —
see the note on `--emit-llvm` below). W3c (§1.4) remains open.

### What the finding actually was: east qualifiers, not `void`

The spec framed §1.5 as a `void` problem ("a `void` parameter in a non-empty
parameter list is never valid C — whatever produces `(void, ptr)` is
mis-associating a type"). The `void` spelling is only the visible tip.

`c-parse-type` accepted C type qualifiers in **leading** position only. A
qualifier *after* the base type ("east const", which C permits and which
denotes exactly the same type) terminated the type; the qualifier token was then
consumed as the parameter's **name**, leaving the following `*p` to begin a
phantom **second** parameter that defaulted to `ptr`. Measured on a minimal
header, exact emitted IR, before the fix:

| C declaration | emitted |
|---|---|
| `void _mm_clflush(void const *__p);` (the real SDL case, `emmintrin.h`) | `declare void @_mm_clflush(void, ptr)` |
| `void f(int const *p);` | `declare void @f(i32, ptr)` |
| `void f(int volatile *p);` | `declare void @f(i32, ptr)` |
| `void f(struct Op const *p);` | `declare void @f(ptr, ptr)` |
| `void f(unsigned long const *p);` | `declare void @f(i64, ptr)` |
| `void f(double const *p);` | `declare void @f(double, ptr)` |
| `void f(int const n);` — no pointer at all | `declare void @f(i32, ptr)` |

**Only the `void` row is invalid IR.** Every other row is *representable but
wrong* — wrong arity, wrong ABI, accepted silently at every stage, with no
diagnostic anywhere. `int const *p` becoming a two-parameter function is a
miscompile waiting for the first call.

The consequence for the design is the one worth carrying forward: **a validity
gate cannot catch this class.** `(i32, ptr)` passes any reasonable gate. The
parse fix is therefore the primary deliverable and the gate is the safety net
for what remains — not the other way round, and the gate is emphatically not a
substitute.

The fix is `c-skip-type-quals` (`src/cheader.nuc`), called at two points in
`c-parse-type`: once after the declaration-specifier loop exits (covering every
base kind — builtin, typedef name, `struct Tag`) and once after each `*`.
`const`, `volatile`, `restrict`, `__restrict`, `__restrict__` and `_Atomic` are
consumed and discarded rather than modelled: Nucleus has no qualifier concept and
the emitted LLVM type is identical either way, so representing them would buy
nothing. `tests/fixtures/w3b-quals.h` pins the whole matrix — the previously
broken spellings **and** the previously correct ones (`const void *p`,
`char * const p`, `int * restrict p`, `void f(void)`, `f(const char *, ...)`), so
a future "fix" cannot trade one for the other.

### The third root cause: a stray `)` made the top-level dispatch fall through

Found while verifying that the gate's warnings really are located. In
`emit-c-include`'s top-level scan loop, the two-way dispatch

```lisp
(cond
  (or (= tok "union") (or (= tok "struct") (= tok "typedef")))  <type declaration>
  true                                                          <function declaration>)
```

was not a `cond` at all: one extra `)` at the end of the first clause closed the
`cond`, leaving `true` as a bare no-op statement and the function-declaration
parse running **unconditionally**. Present since `6ef16dc Add union types`.

Two consequences, both real:

* **Provenance.** After every top-level `struct`/`union`/`typedef`, a function
  parse ran *in the same iteration*, starting at whatever whitespace the type
  parse had stopped on — so the next declaration's `decl-start` pointed at the
  newline **before** it, and W3b's skip warning named the type declaration's line
  instead of the function's. This is invisible wherever `clang -E` happens to
  emit a fresh linemarker (which is why it does not reproduce on a header with
  comments between the declarations, and why it took a synthetic header to see).
* **Dropped declarations.** Two forward declarations in a row (`struct Foo;`
  then `struct Bar;`) — the second was consumed by the stray function parse's
  not-a-function fallback and never registered by the import. (Masked in
  practice, because W3a's name pre-scan registers it separately.)

Fixed by re-nesting the `true` clause inside the `cond`. Verified inert for
everything else: the emitted IR of every `lib/*.nuc` and `examples/*.nuc`, and
the compiler's own `src/nucleusc.nuc` IR, are byte-identical across the change.

**Lesson worth keeping:** a dangling `true` at the end of a `cond` is a syntactic
tell. It is dead code as a statement, so it never appears deliberately — grep for
`cond` clauses whose guard is `true` but whose body sits at the wrong paren
depth when a dispatch "works but is subtly off by one".

### The gate

`c-decl-skip-reason` (`src/cheader.nuc`) runs on every recognized function
declaration, immediately before registration and IR emission, and returns the
reason it cannot be described or null. Four arms:

1. **A by-value struct/union with no known layout** — an opaque tag, an
   unregistered tag, or a body the parser abandoned. Signalled by
   `g-cheader-unrep`, a declaration-scoped flag set inside `c-parse-type` (a
   global rather than an out parameter: `c-parse-type` has six call sites across
   three parse paths and only the function-declaration path acts on it). It is
   cleared at `c-parse-func-decl` entry so a nested struct-body parse cannot leak
   a flag from an earlier declaration, and again before each parameter; the
   parameter loop then clears it a third time after the two overrides that make
   an aggregate irrelevant — a **function-pointer** parameter (a pointer whatever
   its argument types were) and an **array** parameter (which decays to a pointer
   in C; glibc's `utimensat(int, const char *, const struct timespec [2], int)`
   is the case that proved this arm must exist).
2. **A `void` parameter.** `void` is legal only as the whole (empty) parameter
   list, which is consumed before any parameter is recorded — so a *recorded*
   void parameter is always a mis-parse, and it is the exact IR LLVM rejects.
   This arm is now unreachable through the qualifier path it was written for; it
   stays as the backstop for any future mis-parse of the same shape.
3. **An opaque parameter or return type.**
4. **More than `C-MAX-PARAMS` (32) parameters.** The array is a fixed arena
   block; the count deliberately keeps incrementing past capacity so the gate
   sees the real arity and skips, instead of registering a truncated signature.
   (Before W3b the array was 16 entries and `num-params` was incremented past it,
   so `type-set-params` read off the end.)

A skipped declaration is still **consumed** — `out-end` is already past its
semicolon and `c-parse-func-decl` returns 1 — so the caller does not rescan it.
The skip happens *before* the collect-mode push, because aliasing a name that was
never registered would produce a dangling `prefix/name`.

The gate sits **after** successful recognition, deliberately. The "this is not a
function declaration at all" path (`c-parse-func-decl` returning 0) stays silent:
every typedef, variable, `static inline` body and macro remnant in a preprocessed
header goes through it legitimately, and warning there would bury the signal
entirely.

**What the gate deliberately does not do.** The spec suggested gating on
"unresolved type names". That is not detectable here and would be wrong if it
were: `c-parse-type` resolves an unfollowed typedef to `ptr` (§1.4 — `off_t`,
SDL's `Uint32`), which is *representable*, so such a gate would skip a large
fraction of every real header. §1.4 must be fixed at the source (follow the
chain), not papered over by the gate. The corollary is that the gate cannot see a
**wrong but representable** declaration at all — `declare ptr @SDL_CreateWindow(ptr, i32, i32, i32, i32, ptr)`
(that last `ptr` is a `Uint32`) passes it today.

### Warning policy

`<header>:<line>: warning: skipping C declaration '<name>': <reason>` on stderr —
the header and the declaration's own line (from the W3a linemarker machinery,
reused rather than rebuilt), never the `.nuc` file that imported it.

* **Always on**, no flag. A silently missing declaration is exactly the failure
  mode §1.4 cost a debugging session over.
* **Deduplicated by function name** (`g-cheader-skipped`, a Node-cell string list
  — the same shape as the import lists and the preprocessed-text cache). A C
  header import is deliberately *not* deduplicated (each import may alias under a
  different prefix) and umbrella headers include each other transitively, so
  without this a single skipped function warns many times per build. The dedup is
  global rather than per-header: two different headers each declaring an
  unrepresentable `foo` warn once between them, which is the right trade at this
  volume.
* **Measured volume: zero.** `<stdio.h>`, `<stdlib.h>`, `<string.h>`,
  `<unistd.h>`, `<fcntl.h>`, `<math.h>`, `<time.h>`, `<sys/stat.h>`,
  `<pthread.h>`, `<netinet/in.h>`, `<signal.h>`, `png.h`, `SDL2/SDL.h` and
  `SDL2/SDL_mixer.h` each import with **no** warnings. The "wall of noise on
  every build" risk did not materialise, so no verbosity flag was added; if a
  future header does produce a wall, the dedup list is the place to add a cap.

### Running the gate against `make lib-cheaders` — it does *not* pass

The spec requires this self-check and states the compiler's own headers must pass
it. **They do not, and the gate is right.** Re-importing each generated
`lib/*.h`, 3 of 33 produce 11 skip warnings: `hashmap.h` (3), `hashset.h` (3),
`vector.h` (5). Every one is the same shape —

```c
void conj(void* self, struct T elem);       /* lib/vector.h:17 */
```

`--emit-cheader` is emitting the **type variable** `T` of the parametric template
`(Vector T)` as a C type `struct T`. There is no such type and cannot be; a
by-value parameter of it is not describable in C at all, so skipping it is
correct. This is a pre-existing `--emit-cheader` defect, in the same family as the
one W3a recorded (the same files emit `void vector-init(void* v);` — hyphens are
not C identifiers, and those declarations are silently unparsed, which is why the
`struct usize`-returning ones never even reach the gate). Not fixed here; it is
`--emit-cheader`'s bug, not the importer's, and fixing it means deciding what a
C header for an un-stamped template should say at all.

The important half of the check did pass: `make lib-cheaders`'s output is
**byte-identical** before and after W3b, so nothing about the generated headers
changed.

### `--emit-llvm` is not a validity check (restating W3a's finding, because it bit again)

`--emit-llvm` never parses the IR it writes. Every claim in this section about
valid IR was verified with `-o` (a real link) or `llvm-as`, never with an exit
code from `--emit-llvm`. Both new fixture tests run `llvm-as` over the emitted
module for exactly this reason, and `run_w3b_sdl` builds with `-o` and *runs* the
resulting binary.

### Tests

* **`run_w3b_quals`** + `tests/fixtures/w3b-quals.{h,nuc}` — the whole qualifier
  matrix, asserting the **exact `declare` line** for all 19 spellings (arity and
  types), plus `llvm-as` over the module. Asserting the signature rather than
  "it compiled" is the point: the silent rows compile fine.
* **`run_w3b_skip`** + `tests/fixtures/w3b-skip.{h,nuc}` — the gate. The one
  representable declaration in the header must survive *and be callable*; the
  three unrepresentable ones must be absent from the IR; each must warn at its
  own line (20 / 24 / 29 in the fixture header), which is also the regression
  guard for the `cond` fall-through above.
* **`run_w3b_sdl`** + `tests/fixtures/w3b-sdl.nuc` — the §1.5 accept criterion,
  the spec's own two-line probe plus a `main`. Built with `-o`, run, and
  `_mm_clflush` pinned as `declare void @_mm_clflush(ptr)` so a future change
  cannot "fix" it by having the gate skip the declaration instead of parsing it.
  SKIPs cleanly without SDL2 installed. No link flags are needed: the fixture
  declares SDL functions without calling any, and `run-tests.sh` has no per-test
  link-flag mechanism.

### Header ladder reached

* **Rung 1** (`<unistd.h>`, `<fcntl.h>`) — clean; §1.4 untouched (W3c).
* **Rung 2** (`SDL2/SDL.h`) — **reached.** Imports with zero warnings, 1663
  declarations, and the result links and runs. This was the rung W3a left
  blocked.
* **Rung 3** (`SDL2/SDL_mixer.h`) — clean since W3a.

### Newly observed, not fixed here

* **A top-level declaration whose first token is `struct`/`union` and which is
  *not* a type declaration is silently dropped.** `struct Tag *f(int);` written
  without `extern` never reaches `c-parse-func-decl` — the top-level dispatch
  routes it to the type parser, which registers the tag and gives up. Verified
  directly (`declare` emitted for `extern struct StTag *st_extern(int)`, nothing
  for `struct StTag *st_no_extern(int)`). Invisible on glibc, which always writes
  `extern`; **musl deliberately omits it** (see the musl note in `context/build.md`),
  so on Alpine this would silently drop every function returning a `struct X *`.
  The W3b gate does not cover it because nothing is synthesized — there is no
  `declare` to reject. Fixing it means falling back to the function parse when
  the type parse declines, which must be restricted to the `struct`/`union`
  tokens: doing it for `typedef` as well would parse `typedef int (*handler)(int);`
  as a function literally named `int`. Left for W3c or a follow-up.
* **`SDL_CreateWindow`'s `Uint32 flags` parameter imports as `ptr`** — §1.4
  showing up in yet another position (W3a already recorded the field case,
  `Mix_Chunk.volume`). Representable, so the gate passes it; W3c's to fix.

### Premises in the spec and the W3b brief that proved wrong

1. **"§1.5 is a `void` problem."** It is a qualifier-position problem; `void` is
   one of eight spellings and the only one that fails loudly. See the matrix
   above.
2. **"Current state, measured today after W3a: still `failed to parse generated
   IR`."** Stale by the time W3b was picked up: the qualifier fix and the whole
   gate were already committed alongside W3a in `4dddcb5`, and `SDL2/SDL.h`
   already imported cleanly. What was genuinely missing was the verification and
   its regression tests (the fixture files `w3b-quals.{h,nuc}` were committed but
   `run_w3b_quals` did not exist — nothing in the suite referenced them), the
   docs, and this section. The third root cause (the `cond` fall-through) was
   found only by measuring the committed behaviour rather than trusting it.
3. **"Compiler-internal headers must still pass the gate."** They do not, and
   the gate is correct to reject them — see the `lib-cheaders` section above.
4. **"A conservative gate: … no unresolved type names."** Not implementable as
   stated, and undesirable: an unfollowed typedef currently resolves to `ptr`,
   which is representable. See "What the gate deliberately does not do".

### Does this strengthen the case for libclang (`design/stage3c.md`)?

Marginally, and the note there was updated. W3b's defects were all
*hand-rolled-parser* defects — a qualifier position the grammar forgot, a
dispatch that fell through, a fixed parameter array — and each was a few lines to
fix once located. What is *not* cheap by hand is the part W3c inherits: following
typedef chains through a real system header. That, not qualifier handling, is the
argument for a real C front end.

---

## W3c as built (§1.4 — typedef chains and declaration precedence)

**Status: done. W3 is closed.** `make test` 261 PASS / 0 FAIL (was 258);
`make bootstrap` byte-identical after a boot reconverge (this change alters the
compiler's own emitted IR — every C header it imports now yields correctly typed
declarations); `--emit-nuch` and `--emit-cheader` output for all 33 `lib/*.nuc`
byte-identical to the pre-W3c compiler, with the identical set of pre-existing
`--emit-nuch` failures.

### The finding is broader than the spec framed it

The spec says "`off_t`'s typedef chain degrades somewhere". It does not degrade
somewhere — **no scalar typedef resolved at all.** `c-parse-type` resolved every
name it did not recognize as a builtin to `ptr`, and `c-type-to-nucleus`
hardcoded exactly two names (`size_t`, `ssize_t`). So a one-level
`typedef int myint;` degraded just as thoroughly as `off_t`'s three-level chain,
and it degraded in return types, parameters **and struct fields** alike:

| declaration | before | after |
|---|---|---|
| `off_t lseek(int, off_t, int)` | `declare ptr @lseek(i32, ptr, i32)` | `declare i64 @lseek(i32, i64, i32)` |
| `ssize_t getline(char**, size_t*, FILE*)` | `declare ptr @getline(ptr, ptr, ptr)` | `declare i64 @getline(ptr, ptr, ptr)` |
| `off_t ftello(FILE*)` | `declare ptr @ftello(ptr)` | `declare i64 @ftello(ptr)` |
| `int fseeko(FILE*, off_t, int)` | `declare i32 @fseeko(ptr, ptr, i32)` | `declare i32 @fseeko(ptr, i64, i32)` |
| `uint16_t __bswap_16(uint16_t)` | `declare ptr @__bswap_16(ptr)` | `declare i16 @__bswap_16(i16)` |
| `struct timeval { time_t; suseconds_t; }` | `%timeval = type { ptr, ptr }` | `%timeval = type { i64, i64 }` |
| `Mix_Chunk { int; Uint8*; Uint32; Uint8; }` | `{ i32, ptr, ptr, ptr }` | `{ i32, ptr, i32, i8 }` |

The struct rows are the worst of it: a wrong *layout*, accepted silently, with
every field after the first mistyped one at the wrong offset.

### The typedef table

`typedef <type> <name>;` for a non-aggregate is parsed by **`c-parse-typedef-decl`**
(`src/cheader.nuc`), reached from `emit-c-include`'s top-level dispatch only after
`c-parse-struct-decl` has declined — so every `typedef struct|union …` shape stays
on W3a's opaque-registration/upgrade path untouched. The record is a Node cell
(`s` = name, `car` = the resolved `Type*`) on `g-cheader-typedefs`; lookup is a
list walk from `c-parse-type`'s base-name resolution, after `c-type-to-nucleus`
and before the struct registry.

**Resolution happens once, at the point the `typedef` is parsed**, and the table
stores the *resolved* type. Two properties fall out of that and are worth
keeping: a chain (`off_t` → `__off_t` → `long int`) costs one lookup at each use
rather than a walk, and **a cycle is impossible by construction** — a name can
only resolve against entries recorded strictly before it, so a malformed
`typedef foo foo;` records `foo` as unrepresentable instead of looping.

Shapes, each resolved or explicitly refused:

| shape | result |
|---|---|
| `typedef long int __off_t;` … `typedef __off_t off_t;` (any depth) | the builtin type |
| `typedef char *string_t;` / `typedef struct Foo *FooPtr;` | `ptr` |
| `typedef int (*handler)(int);` | `ptr` — recognized *before* the declarator fallback, or `int` would be read as the declarator and the line parsed as a function literally named `int` (the trap W3b flagged) |
| `typedef enum { A, B } E;` / `enum Tag` / `enum { … }` as a specifier | `i32` |
| `typedef struct|union …` | unchanged — W3a's path |
| `typedef int v4[4];` | recorded as **known-but-unrepresentable** (null type) |
| a name never declared | absent from the table |

The last two rows are the "never a silent `ptr`" half. A recorded-but-null entry
and an absent one are deliberately distinct — the messages differ, and only the
recorded form proves the name was declared at all.

`size_t`/`ssize_t` **stay hardcoded** in `c-type-to-nucleus`, checked before the
table. `<stddef.h>`'s own typedef would now resolve them identically on this
host, but the hardcode is target-independent (`clang -E` preprocesses for the
*host* even under `--target=`), so removing it would make `size_t` silently
depend on the preprocessing host rather than the emission target. It is a
one-line change if that ever becomes the preferred trade.

Two neighbouring parser gaps were fixed because the table is useless without
them: **`enum` was not a declaration specifier at all** (so `enum Tag e` read
`enum` as the base type and `Tag` as the declarator name, exactly the phantom-
parameter shape W3b found for east qualifiers), and **`__extension__` was not
consumed at top level** (glibc writes `__extension__ typedef long long int
__quad_t;` for every `long long` type it defines, so the whole `__quad_t` family
and everything typedef'd from it stayed unresolved).

### The gate arm W3b could not implement now exists

W3b recorded that the spec's proposed *"no unresolved type names"* arm was not
implementable, because an unfollowed typedef resolved to `ptr` — representable,
so the arm would have skipped a large fraction of every real header. **W3c
removes that objection at the source, and the arm is now in.** A by-value
parameter or return whose base type cannot be resolved marks the declaration
through the same `g-cheader-unrep` channel W3b built. A *pointer* to an
unresolvable type is deliberately not marked: every C pointer is one machine
word, so `ptr` is right.

`c-decl-skip-reason`'s first argument changed from W3b's boolean to the
accumulated **reason string**, so one arm covers both W3b's layout-less
aggregates and W3c's unresolvable names while still naming the offending type
(`a by-value 'W3bHidden' with no known layout`, `a by-value 'long double'
(no Nucleus type is that wide)`). `c-parse-func-decl` keeps the *first* reason it
sees, because a later parameter can raise the flag and then have it cleared by
the function-pointer/array override, which would otherwise leave a stale message
attached to an earlier parameter's verdict.

### Warning policy: W3b's measurement changed, so the policy split

W3b made every skip an always-on stderr warning and justified it with a measured
volume of **zero**. That measurement was a consequence of the §1.4 defect: with
every unfollowed typedef resolving to `ptr`, nothing *could* be detected. Once
the chain is followed, the standard headers contain **165** genuinely
unrepresentable by-value declarations reachable from `(import-use "SDL2/SDL.h")`:

| reason | count |
|---|---|
| `long double` (`<math.h>`, `<stdlib.h>`) | 149 |
| `_Float128` (glibc `mathcalls-helper-functions.h`) | 7 |
| `SDL_JoystickGUID` (a typedef of `SDL_GUID`) | 6 |
| `SDL_GUID` (`struct { Uint8 data[16]; }` — an array field the body parser rejects) | 2 |
| `_Float16` (a clang intrinsics-header remnant) | 1 |

Every one is a true positive; every one is irrelevant to a build that never calls
the function. Six of them landed in the **REPL's startup banner** (it preloads
`<stdlib.h>`) and six more in every `make` of the compiler itself. That is the
"bury the signal" failure W3b's own policy was written to avoid, so the policy
now has two tiers:

* **loud, at import time** — the importer could not *parse* what the header said:
  a layout-less by-value aggregate, a `void` parameter, an opaque type, an
  over-long parameter list. W3b's four arms, its wording, its dedup, its
  always-on rule, unchanged. Still measures zero across the standard headers.
* **quiet, reported at the point of use** — the declaration parsed correctly and
  names a type Nucleus has no equivalent for. Recorded in `g-cheader-skipped`
  (moved to `src/nucleusc.nuc`'s globals block, above `unresolved-name-message`,
  so the *use*-site diagnostic can read it) and delivered by
  `unresolved-name-message`:

  ```
  prog.nuc:12: error: unknown: 'strtold' — its C header declaration was skipped
  (/usr/include/stdlib.h:127: a by-value 'long double' (no Nucleus type is that wide))
  ```

Neither tier is silent. The second is strictly *more* precise than a warning: it
carries the same header, line and reason, and it arrives at the call site instead
of thousands of lines earlier with nothing connecting it to the use.

### Declaration precedence

**Rule: an explicit `(declare …)` wins over a header-derived declaration of the
same function, whichever comes first in the file; a signature mismatch warns
naming both sources.**

Measured before the rule, both orders were silent **and they disagreed** — *first*
wins, not "last wins" as the spec supposed:

```
(declare lseek …) then (import-use "unistd.h")  ->  the author's declaration; header dropped
(import-use "unistd.h") then (declare lseek …)  ->  the header's; the AUTHOR's dropped
```

The second is the dangerous one either way, and it is what §1.4 describes.

Order-independence needs the explicit names known *before* any import runs, so
**`prescan-explicit-declares`** collects them from each unit's top-level forms in
`emit-toplevel-forms`, beside the other prescans — per unit, not just the
outermost, so a source-imported library's declares also outrank a header import
that follows them. A header declaration whose name is on that list is never
registered and never emitted, so exactly one `declare` reaches the module (LLVM
rejects a second for the same symbol *even when the two agree*), and it is the
author's.

**Dropping the header's copy is not enough, and that is the part worth
recording.** Suppression alone leaves the name undefined between the import and
the declare's own position. Measured: `examples/cstr-lit-test.nuc` declares
`strlen` at line 15, and `lib/arena.nuc` calls it from inside the prelude import
that precedes it — suppression alone broke that build with `unknown: strlen`. So
the explicit declaration is **emitted at the point of first need**
(`cheader-yield-to-explicit-declare`, `src/nucleusc.nuc`), and its own form later
becomes an idempotent no-op because `emit-nuch-declare-import` already returns
early for an already-registered name.

The conflict message is blamed on the `.nuc` declaration — the actionable
location — and names the header:

```
prog.nuc:2: warning: declaration of 'lseek' as i64 (i32, i64, i64) conflicts with
/usr/include/unistd.h:339, which declares it as i64 (i32, i64, i32);
the explicit declaration wins
```

Signatures are compared by their **rendered `declare` form** (`c-fn-sig-render`),
not by `type-eq`: `type-eq` treats any two `TY-FN` as equal, and the rendering is
what the user needs to see anyway. Deduplicated on the declaration site, since a
C header import is deliberately not deduplicated.

Scope limit, documented rather than fixed: a `declare` arriving from an imported
`.nuch` is not on the prescan list (its forms are read during emission, too late
to precede a C import) and keeps the older first-wins behaviour. Likewise a
prefixed C import (`(import "h.h" c)`) whose aliased name is explicitly declared
*later* in the unit will not get its `c/name` alias, because the alias pass runs
at the import.

### Two defects found while verifying, both pre-existing

1. **`c-parse-func-decl` never applied the aggregate C ABI.** It printed the raw
   `type-to-ir` of each parameter and the return. This had never mattered because
   glibc names every by-value aggregate through a typedef, and an unfollowed
   typedef was `ptr` — so the C-header path had literally never emitted a struct
   by value. With the chain followed, `div`/`ldiv`/`lldiv`/`fopencookie` appear,
   and `%div_t` in a `declare` would disagree with the ABI the *call site*
   already lowers through `abi-classify`. Now routed through
   `abi-classify`/`abi-ret-ir`/`abi-print-param` like `emit-nuch-declare-import`:
   `declare i64 @div(i32, i32)`, `declare { i64, i64 } @ldiv(i64, i64)`,
   `ptr byval(%cookie_io_functions_t) align 8`. For every scalar/pointer
   declaration `abi-classify` is `ABI-DIRECT` and both helpers reduce to
   `type-to-ir`, so the emitted text is byte-identical to the former loop.

2. **The cheader path never set `StructDef.emitted`.** `cheader-struct-define` /
   `cheader-adopt-shape` write their `%X = type {…}` line straight to
   `g-type-stream` rather than through `emit-struct-ir-type`, so the flag stayed
   0 — and `pending-union-deps-ready` consults exactly that flag before writing a
   queued union whose field names the struct. Latent until W3c: SDL's
   `SDL_WindowShapeParams` (a union with an `SDL_Color` member) was deferred on
   every drain once `SDL_Color` became a real `TY-STRUCT`, so `%SDL_WindowShapeParams`
   was never defined while `%SDL_WindowShapeMode`, which contains it, referenced
   it — `use of undefined type`. Both helpers now set the flag.

### Incidental: the musl `struct Tag *f(int);` gap (W3b's "not fixed here")

Taken, because the typedef parser made it cheap and safe. A top-level declaration
whose first token is `struct`/`union` and which is a *function* was routed to the
type parser, which registered the tag and declined — after which it was silently
dropped, invisible to the gate because nothing was synthesized. The dispatch now
falls through `c-parse-struct-decl` → `c-parse-typedef-decl` → `c-parse-func-decl`,
with the last step **restricted to the `struct`/`union` tokens** exactly as W3b
required: `typedef` has its own parser one step earlier and must never reach the
function parser, or `typedef int (*h)(int);` becomes a function named `int`.
Inert on glibc (which always writes `extern`) — verified by a byte-identical IR
diff across every `lib/*.nuc` and `examples/*.nuc`.

### Tests

* **`run_w3c_typedef`** + `tests/fixtures/w3c-typedef.{h,nuc}` — the typedef
  matrix, asserting the **exact `declare` line** for 18 functions (one-level,
  two-level and three-level chains; `unsigned char`/`unsigned int`/`short`/
  `float`/`double`/`unsigned long long`; pointer, `const`-pointer and
  pointer-to-typedef; function-pointer typedefs; tagged and anonymous enums; an
  opaque-struct typedef; the no-`extern` `struct Tag *f(int)` shape), plus the
  emitted **struct layout** `%w3c_fields = type { i8, i32, i64, ptr }`, plus that
  a by-value array typedef is absent from the IR and that *using* it produces the
  located use-site diagnostic. Asserting signatures rather than "it compiled" is
  the point: every wrong row compiled fine before.
* **`run_w3c_precedence`** + `tests/fixtures/w3c-prec-{first,second,use}.nuc` —
  the rule in **both orders**, asserting that exactly one `lseek` declaration
  reaches the IR, that it is the author's, that the conflict warns naming both
  sources, and that the module parses. The third fixture pins the
  use-*between*-import-and-declare case that makes early emission necessary, with
  a deliberately differing signature so the emitted `declare` proves which
  declaration won.
* **`examples/cheader-posix.nuc`** + `tests/expected/cheader-posix.out` — the
  spec's required **runnable** test: `open`/`write`/`lseek`/`read`/`close`
  through `<fcntl.h>`/`<unistd.h>` against a temp file, with no hand-written
  `declare` anywhere, and `lseek`'s `off_t` used as an integer on both the
  argument and the return side (`size`, `size+1`, `pos`). libc only —
  `run-tests.sh` has no per-test link-flag mechanism.
* **`run_w3a_sdl_mixer`** extended — `%Mix_Chunk = type { i32, ptr, i32, i8 }` is
  now pinned, and the fixture reads the `Uint8 volume` and `Uint32 alen` fields
  W3a recorded as degrading to `ptr`. That was W3a's "newly observed, not fixed
  here" item; it is the rung-3 accept test for the typedef chain reaching a
  *field*.
* **`run_w3b_skip`**'s expected text updated: the message now names the offending
  type (`a by-value 'W3bHidden' with no known layout`) instead of a generic
  sentence. Strictly more specific, not weaker.

### Header ladder — closed

* **Rung 1** (`<unistd.h>`, `<fcntl.h>`) — **reached, end to end and runnable.**
  `examples/cheader-posix.nuc` compiles, links and runs against a temp file
  entirely through header imports. This is the rung W3a and W3b both left blocked
  on §1.4.
* **Rung 2** (`SDL2/SDL.h`) — **reached**, unchanged from W3b: imports with zero
  loud warnings, links, runs. 1497 declarations (was 1663): the 165 that
  disappeared are the unrepresentable by-value declarations enumerated above,
  which previously imported as wrong-`ptr` signatures that would have miscompiled
  if called. One went from wrong to right rather than being dropped.
* **Rung 3** (`SDL2/SDL_mixer.h`) — **reached**, and the `Mix_Chunk` field defect
  that W3a recorded as blocking it is fixed.

**What blocks the next rung.** There is no next rung in the spec's ladder; the
remaining known gaps, in the order a real port would hit them, are:

1. **Array fields in a struct body** (`struct { Uint8 data[16]; }`). The body
   parser abandons the whole struct on `[`, so the type stays opaque and every
   by-value use of it is skipped. This is what makes `SDL_GUID` and its six
   `SDL_JoystickGUID` functions unavailable, and it is the single highest-value
   remaining item: it is also why `FILE` is opaque. Bitfields and
   multi-declarator field lines (`int a, b;`) are the same branch.
2. **`long double` / `_Float128` / `_Float16`** have no Nucleus type. 156 skipped
   declarations, all correctly refused. Fixing this is a *type-system* change, not
   a parser one.
3. A **comma-separated typedef declarator list** (`typedef int a, *b;`) records
   only the first declarator; each declarator has its own pointer depth, which a
   single-declarator parse cannot recover. Vanishingly rare in real headers; the
   rest stay unknown, which the by-value gate reports rather than mis-typing.

### Premises in the spec and the W3c brief that proved wrong

1. **"`off_t`'s typedef chain degrades *somewhere*."** No scalar typedef resolved
   at all, including a one-level `typedef int myint;`. The brief's own
   re-measurement caught this and was right.
2. **"Silent last-wins is how §1.4 cost a debugging session."** It is silent
   *first*-wins. The consequence the spec describes is real and unchanged — with
   the import first, the header replaces the author's declaration — but the
   mechanism is the opposite of the one stated, and the fix has to be
   order-independent rather than an ordering tweak.
3. **"Recommended: an explicit `declare` wins … and a mismatch warns."** Correct,
   but incomplete in a way that only shows up on contact: simply *suppressing* the
   header's copy breaks any use of the name between the import and the declare.
   The rule needs the explicit declaration emitted early, not merely preferred.
4. **The brief's "Match W3b's warning policy (always on, stderr, deduplicated)
   unless you have a reason to differ."** There is a reason, and it is the same
   measurement W3b used to justify always-on: the volume went from 0 to 165 the
   moment typedefs resolved. Split into two tiers (above); W3b's arms keep its
   policy verbatim.
5. **"Fixing typedefs should fix [`Mix_Chunk.volume`]."** True, and it also fixed
   a class the brief did not anticipate — struct *layouts*. `%timeval`,
   `%__fpos_t` and `%Mix_Chunk` were all wrong, not merely awkward to read.
6. **Not in the brief at all:** the C-header `declare` emitter had no ABI
   lowering, and the cheader path never set `StructDef.emitted`. Both were
   pre-existing and both became reachable only once typedefs resolved.

---

## Addendum to W3c: unnamed `declare` parameters carry types

**Status: done.** `make test` 265 PASS / 0 FAIL (was 261; +4 new checks);
`make bootstrap` byte-identical after a boot reconverge; a clean rebuild from the
committed boot IR reproduces it.

Surfaced by W3c, and a *precondition* for W3c's precedence rule being useful.

### The defect

`declare`'s parameter list ignored every written type unless the parameter was
named, emitting `i32` instead. Measured before the fix:

| written | emitted |
|---|---|
| `(declare f1 (i64):i64)` | `declare i64 @f1(i32)` |
| `(declare f2 (i32 i64):i64)` | `declare i64 @f2(i32, i32)` |
| `(declare f4 (f64 i64):i64)` | `declare i64 @f4(i32, i32)` |
| `(declare f5 (ptr i64 ui32):i64)` | `declare i64 @f5(i32, i32, i32)` |
| `(declare f6 (a:i32 b:i64 c:i32):i64)` | `declare i64 @f6(i32, i64, i32)` ← named: correct |

Return types were never affected. The bare list was correct exactly when the
signature was all-`i32`, which is why it survived: `docs/toplevel.md` documents
the form, and the compiler's own source uses it, but only for `ptr`.

`emit-nuch-declare-import` (`src/nuch.nuc`) asked `extract-name-and-type` for
each parameter and, on null, wrote `ty-i32`. Null is what that function returns
for *any* node with no `name:type` annotation — i.e. for every bare type
spelling. The default silently absorbed them all.

**It reached the compiler's own source.** `src/nucleusc.nuc:16-17` declare
`repl_print_f64`/`repl_print_f32` as `(ptr)`; both emitted
`declare void @repl_print_f64(i32)` against a `src/repl_shim.c` shim taking
`void *`. It worked only because x86-64 SysV passes a pointer and an `i32` in the
same register, and because a call site's own signature (`call void
@repl_print_f64(ptr %t)`) is what governs codegen — the *declaration* was simply
a lie, and would not have survived a target where the two differ.

### Why W3c made it urgent

W3c's rule is "an explicit `(declare …)` beats a header-derived declaration, and
a mismatch warns". With the defect, a bare-list declaration that **agreed** with
the header rendered as all-`i32`, so it *conflicted* with every non-`i32` header
signature — and the wrong signature won:

```
(import-use "unistd.h")
(declare lseek (i32 i64 i32):i64)
  -> warning: declaration of 'lseek' as i64 (i32, i32, i32) conflicts with
     /usr/include/unistd.h:339, which declares it as i64 (i32, i64, i32);
     the explicit declaration wins
```

The declaration is character-for-character the header's. Before W3c the header's
correct declaration would simply have been used, so this was a live regression in
effect — precedence handed the win to a signature the defect had corrupted.

### The rule, and what was deliberately *not* changed

**An element of a `declare` parameter list that carries no `name:type`
annotation is a type operand** (`declare-param-type`, `src/nuch.nuc`,
immediately above `emit-nuch-declare-import`): a keyword (`:i64`) resolves
through `parse-type-name`, anything else through `parse-type-from-node`. Both
already raise a **located** `unknown type: …` / `unable to parse type
expression`, so an unresolvable spelling is an error at its own line rather than
a silent `i32`. There is no fallback: defaulting is the defect.

**An element that *is* annotated stays a named parameter**, exactly as in a
`defn`. This leaves one residual ambiguity, and it is a decision, not an
oversight: `(declare f (ptr:FILE):void)` reads as a parameter *named* `ptr` of
type `FILE` — by value — not as a pointer to `FILE`. It reads that way today and
read that way before this change (measured: `(declare g1 (ptr:Thing):void)`
emitted `declare void @g1(i64)`, a coerced by-value `Thing`, both before and
after). Resolving it the other way is possible but costly and was refused:

* Desugar erases the distinction. `ptr:FILE` and a genuinely named `p:ptr:FILE`
  both arrive at the emitter as cells (`(ptr FILE)` / `(p (ptr FILE))`), so the
  only way to tell a type from a name is to ask **what the head names** — C's
  typedef ambiguity, imported wholesale, with a keyword list to keep in sync with
  `parse-type-from-node`.
* It would break `.nuch` round-trip. `--emit-nuch` prints a solitary `defn`'s
  parameters verbatim, and a parameter *named* `ptr`/`ref`/`raw` is legal today
  (`(defn addone (ptr:i32):i32 …)` compiles). A grammar that reinterpreted the
  generated `(declare addone (ptr:i32) :i32)` would silently retype it.
* It would make `declare` and `defn` disagree on a shared grammar the docs say
  is the same.

The spelling for an unnamed pointer parameter is therefore the bare `ptr` (what
the compiler's own source uses); a *typed* pointer parameter is named
(`p:ptr:FILE`). `docs/toplevel.md` states this explicitly, and
`tests/fixtures/w3c-declare-params.nuc` pins both readings so a future change to
either is deliberate.

### `&rest` / `&optional` in a declaration are now refused

The marker is a bare symbol, so it hit the new path and had to be decided. None
of the machinery a declaration would need exists: `variadic` is hardcoded 0 in
`emit-nuch-declare-import` and `has-rest` is never set, so the marker was simply
counted as an extra `i32` parameter —
`(declare myfn (a:i32 &rest xs:ptr):i32)` emitted
`declare i32 @myfn(i32, i32, ptr)`, two phantom parameters and no rest folding at
any call site. Implementing it properly has two *incompatible* meanings (Nucleus'
cons-list `&rest`, which is what round-trip fidelity wants, versus C varargs,
which is what an FFI author wants), so it is refused with a located diagnostic
instead of being guessed.

This is the one place the change was not purely additive. **Three heredocs in
`tests/run-tests.sh` used the spelling** (`(declare printf (fmt:CStr &rest
args:i32) :i32)`, in the `n6` / `sm3` / `s1` `.nuch` link-and-run consumers) and
were relying on the defect: their calls pass 3–6 arguments to what the spelling
made a 3-parameter declaration. Call arity is *not* checked against a
declaration, so the marker contributed nothing but two phantom parameters. They
now declare `(declare printf (fmt:CStr):i32)` — the honest fixed prefix — and the
extra arguments ride the call site, which is how the C ABI passes them anyway.
The tests assert namespace mangling and `.nuch` round-trip; nothing they measure
changed.

### Bootstrap: the diff is exactly the two declarations

Isolated by compiling **the same source** with the old and new compilers
(`build/nucleusc.ll` is emitted by the committed boot, `build/stage2.ll` by the
newly built compiler):

```
4018,4019c4018,4019
< declare void @repl_print_f64(i32)
< declare void @repl_print_f32(i32)
---
> declare void @repl_print_f64(ptr)
> declare void @repl_print_f32(ptr)
```

Six diff lines, nothing else, no string-pool renumbering (a `declare` line's
type text does not touch the pool). Corroborated across the corpus: for all
**189** `examples/*.nuc`, `lib/*.nuc` and `tests/fixtures/*.nuc` that compile,
old and new emit **byte-identical** IR — no program in the tree used the bare
spelling. All 33 `lib/*.nuch` regenerate byte-identically and still import.

The compiler's *own* IR additionally carries the compiled form of the edit
itself, as any self-hosted change does (conventions.md, "The byte-identical gate
… is `make bootstrap`"): normalizing SSA temps and `@.str` indices out of a
with-fix/without-fix build leaves changes in exactly two functions —
`@declare-param-type` (new) and `@emit-nuch-declare-import` — plus four new
`@.str` message constants and the renumbering they cause from `@.str.2520`
onward. Reconverged with the standard cycle
(`make clean && make && make update-bootstrap && make clean && make && make
bootstrap`).

### Tests

* **`run_w3c_declare_params`** + `tests/fixtures/w3c-declare-params.nuc` — the
  matrix, as **pairs**: each signature written both ways, with the exact
  `declare` line asserted for both members. The pair is the invariant, so a
  default cannot pass a row whose named half is already correct. Covers every
  integer width and signedness, both floats, `usize`/`ssize`/`bool`/`Char`,
  `ptr`/`CStr`, a mixed named-and-bare list, a keyword operand, a by-value struct
  in unnamed position (`{i32, i64}` → two INTEGER eightbytes → `(i64, i64)`,
  identical to the named spelling), and the `ptr:W3dPair` reading above.
* **`run_w3c_declare_header`** + `w3c-declare-header-{match,conflict}.nuc` — the
  precedence interaction: a bare-list declaration **matching** `<unistd.h>`'s
  `lseek` emits exactly one correct `declare` and **no diagnostic at all**; one
  that genuinely differs still warns naming both sources and still wins.
  Silencing the false conflict must not silence the real one.
* **`w3c-declare-unknown-type.nuc`** / **`w3c-declare-rest.nuc`** — rejections,
  through `run_reject_at`, so both the message *and* its location are pinned (and
  both fixtures feed the `run_no_line_zero` sweep).

`run_w3c_precedence` and its three fixtures were audited and **did not encode the
defect**: they spell every parameter `fd:i32 off:i64 whence:i64`, the named form,
which was always correct. Their expected conflict is a genuine one (`whence` as
`i64` where the header says `i32`), and it still warns.

### Premises in the brief that proved wrong

1. **"Nothing legitimate depends on the current leniency."** Not stated outright,
   but implied by the instruction to check. Three `tests/run-tests.sh` heredocs
   did — via `&rest`, not via a bare type. A tree-wide grep over `*.nuc`/`*.nuch`
   misses them: the declarations are **generated by shell heredocs** inside the
   test harness. The test suite, not the grep, is what found them.
2. **"Confirm the IR diff is exactly those declarations … and nothing else."**
   True of the *codegen change* (proved by compiling identical source with both
   compilers), but not of `boot/nucleusc.ll`, which also contains the compiled
   form of the source edit. The two measurements answer different questions and
   both are reported above.
