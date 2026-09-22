# Stage 21 — C header include paths: `--cflag=<arg>` reaches `clang -E`

**Status:** designed 2026-09-19, **built the same day** (CF-1 … CF-4; §10 "As
built"). Every file:line in §1 was verified against the tree before the change.
§7 has the gates and §8 the sequencing (independent of items 1 and 2, no boot
refresh).

**Goal.** A C header that lives outside clang's default search path can be
imported. Today `(import-use "gtk/gtk.h")` is fatal on every machine with GTK 4
installed, because the compiler's `clang -E` invocation carries no include
directory at all and has no flag that could add one — the `-I` a user reaches
for is the Nucleus import path and never reaches clang. The fix is one
repeatable flag, `--cflag=<arg>`, appended verbatim to the preprocessor
command, mirroring what `--link-arg=<arg>` already is for the link step.
Found through a GTK 4 demo beside the checkout (`../charge.nuc/src/main.nuc`),
whose header comment already states the cause and hand-`declare`s eleven GTK
entry points instead. Not on `deferred/overview.md`; this is one of the edges
"nobody wrote down".

---

## 1. Ground truth (verified 2026-09-19)

### 1.1 The invocation

`cheader-cpp-command` (`src/cheader.nuc:1399–1415`) builds the argv for every
header read — the declaration pass, the Stage 17 `-dM` macro pass, and the
no-header predefine baseline (`cheader-macro-baseline-load`, `:2911`, which
passes `(symbol-none)` as the header):

```
clang -E [-dM] [--target=<t>] [--sysroot=<p>] -x c [-include <header>] /dev/null
```

The only user-controlled operands are `--target=` and `--sysroot=`
(`cheader-cc-target?`, `:1391`). Nothing else on the compiler's command line
reaches this argv. `cheader-cpp-display` (`:1419–1431`) renders the same
command as text for the failure `note:` (`cheader-preprocess-failed`,
`:1478–1487`, which re-runs the command with stderr attached so clang's own
`file not found` is the diagnosis). `cheader-capture` (`:1438`) spawns it
through `lib/process.nuc`, whose child inherits the parent's environment
(`command-env`, `lib/process.nuc:126`) and whose stderr is captured and
dropped.

The preprocessed-text cache (`cheader-preprocess-mode`, `:1496–1547`) is keyed
on header path and `-dM` mode only (`:1500`). Under `--target=`, a failed
target read falls back to a host read of the same header (`:1518–1530`) with
the C4 warning.

### 1.2 What `-I` is

`nucleusc -I<dir>` (`src/nucleusc.nuc:19969–19978`) appends to
`g-include-paths` (`:927`), which is read in exactly two places: module
resolution for `(import foo)` / `(import-use foo)` — `name.nuc` / `name.nuch`
under each directory (`:18733`) — and the unresolved-name definer scan
(`:3305`). It is never passed to clang. `--link-arg=<arg>` (`:19967`) appends
to `g-link-args` (`:624`), consumed only by the link step (`:19813`); bare
`-l`/`-L` route through the same vector (`:19979`). Any other `-`-led argument
is `unknown flag:` (`:19983`). The usage line is `:19996`.

### 1.3 The reproduction

A stand-in header tree (`inc/gtk/gtk.h` including `<glib/glib.h>`, the nested
include being the point) and a three-line program that calls
`gtk_label_new`:

| Build line | Result |
| --- | --- |
| `nucleusc prog.nuc` | `note: clang -E -x c -include gtk/gtk.h /dev/null` / `fatal error: 'gtk/gtk.h' file not found` / `prog.nuc:1: error: c-include: failed to preprocess 'gtk/gtk.h'` |
| `nucleusc -I inc prog.nuc` | identical — `-I` changes nothing |
| `(import-use "/abs/inc/gtk/gtk.h")` | clang opens *that* file, then `'glib/glib.h' file not found` at its first `#include`; an absolute path cannot stand in for a search path |
| `CPATH=inc nucleusc prog.nuc` | compiles; `declare ptr @gtk_label_new(ptr)` emitted |

The last row is why this is a design and not a bug report: the environment
already reaches clang, so the *mechanism* is proven, and what is missing is a
spelling on the compiler's own command line. GTK 4's headers are spread over
`/usr/include/gtk-4.0`, `/usr/include/glib-2.0`,
`/usr/lib/<multiarch>/glib-2.0/include`, `/usr/include/pango-1.0` and more —
the reason `pkg-config --cflags gtk4` exists — so the real case is the
stand-in's shape with a dozen directories.

### 1.4 Why `-I` must not simply be forwarded

The obvious repair — hand every `-I` to clang as well — is a trap, and the
tree already contains the bait. `lib/` holds 44 generated C headers
(`--emit-cheader` output committed beside each library), among them
`lib/string.h`, `lib/error.h`, `lib/io.h`, `lib/file.h` and `lib/process.h`.
A clang `-I` directory is searched **before** the system directories, so:

```
$ clang -E -x c -I lib -include string.h /dev/null | grep -m1 'string.h"'
# 1 "lib/string.h" 1
```

The prelude's `(import-use "string.h")` (`lib/prelude.nuc:17`) would read the
C header *of `lib/string.nuc`* instead of libc's on every build that passes
`-I lib` — which is every out-of-tree program, including the demo's own build
line (`-I ../nucleus/lib`). The two searches must stay distinct: a Nucleus
module directory is exactly the kind of directory that contains C headers
named after Nucleus modules. (`CPATH` has the same hazard, which is a second
reason not to document the environment as the answer.)

### 1.5 Where a preprocessor flag has to show

Every place §1.1 names, or the flag is a half-truth somewhere:

- the argv (`cheader-cpp-command`) — both `with-target` states, since the
  directories are the user's, not the target's, and the host fallback would
  otherwise fail on the very header the user pointed at;
- the display (`cheader-cpp-display`) — the `note:` line is what a user
  copies to reproduce a failure, so it must show the flags that were passed;
- the `-dM` run and the predefine baseline — one builder serves all three,
  so a `-D` given this way lands in the baseline and is *subtracted*, not
  admitted as a header constant (`:2922–2924`), which is the right reading of
  a command-line define;
- the REPL — argv is parsed before `repl-main` (`:19992`), and the five
  libc preloads (`src/repl.nuc:1643–1647`) and every prompt-time
  `(import-use "x.h")` go through the same path, so `nucleusc -i --cflag=…`
  needs nothing extra;
- `--emit-nuch` / `--emit-cheader` — both run the import prescans, so the flag
  applies there too. A `.nuch` carries no C-header import of its own (none of
  the 44 committed headers does), so a *consumer* of a `.nuch` never needs the
  producer's flags; a generated `.h` that `#include`s the borrowed C header
  leaves the include path to the C consumer's build, as it should.

The cache needs no change: flags are fixed for the life of the process, so
path + mode remains a complete key. Say so at the key, or the next reader
adds them.

---

## 2. Verdict — one verbatim flag, and the four shapes it beats

**`--cflag=<arg>`: pass one verbatim argument to the `clang -E` that reads C
header imports. Repeatable; only the preprocessor consults it.** The name is
what `pkg-config` calls these (`--cflags`) and what every C build system
calls the variable; the `--name=value` shape and the one-argument-per-flag
rule are `--link-arg=`'s (`docs/compiler.md:30`), and the "only the
preprocessor" sentence is `--sysroot=`'s (`:28`). The pkg-config idiom is a
prefix, in `make` (`$(addprefix --cflag=,$(shell pkg-config --cflags gtk4))`)
or a shell loop; §6 documents it once.

Rejected, each for a reason a later reader may want to re-weigh:

1. **Forward `-I` to both.** §1.4: `-I lib` would make the prelude read
   `lib/string.h`. Proven, not argued.
2. **`--cflags="<string>"`, split on whitespace.** The argv form of this
   command exists because a `--sysroot` with a space in it was a quoting bug
   in the command-string version (`src/cheader.nuc:1396–1398`); a flag that
   re-splits on space reintroduces the class of bug C4 removed. One flag, one
   argument, no parsing — the same discipline `--link-arg=` keeps.
3. **Document `CPATH`.** It works today (§1.3), and stays mentioned as a fact.
   But a build line should say what it does; an environment variable is
   invisible in a Makefile rule, leaks into every other clang the shell runs,
   and has the §1.4 shadowing hazard with no flag-order to reason about.
4. **Bare-forward `-D`, `-isystem`, `-pthread` … as `-l`/`-L` are.** Every
   bare forward is a spelling the Nucleus CLI can never use for itself, the
   list is open-ended, and `--cflag=` carries all of them. `-l`/`-L` are
   grandfathered, not a precedent.

Not decided here: a `--cc=<cmd>` to replace the hardcoded `"clang"`
(`:1400`), the preprocessor twin of `--linker=`. Nothing needs it; recorded
so the hardcode is known to be one.

---

## 3. CF-1 — the flag and its plumbing

`src/nucleusc.nuc`:

- `(defvar g-cflags:&(Vector Symbol) (vector-new-in &g-arena-alloc))` beside
  `g-link-args` (`:624`), built by `@__nucleus_init` like its neighbours
  (G-5: no lazy guard, arena-backed from the first push).
- `add-cflag` beside `add-link-arg` (`:19909`).
- One `cond` arm beside `--link-arg=` (`:19967`):
  `(strview-has-prefix argview "--cflag=")` → `(add-cflag (symbol-intern
  (strview-drop-bytes argview 8)))`. An empty value (`--cflag=`) is refused
  with `--cflag= requires an argument`, as `-o` and `-I` refuse theirs;
  `clang` would otherwise receive an empty argv entry and diagnose something
  unrelated.
- The usage line (`:19996`) gains `[--cflag=<arg>]` after `[--sysroot=<path>]`.

`src/cheader.nuc`, `cheader-cpp-command` (`:1399`): after the
`with-target` block and before `-x c`, append each entry of `g-cflags` with
`command-arg`. The position is cosmetic to clang and deliberate for the
display — `clang -E [--target] [--sysroot] <cflags> -x c -include H /dev/null`
reads as "toolchain, then the user's flags, then the header". Both
`with-target` states get them (§1.5).

Nothing else moves. The cache key stays path + mode, with one line at `:1500`
saying why the flags are not in it.

## 4. CF-2 — the display and the note

`cheader-cpp-display` (`:1419`) appends the same entries, space-separated, at
the same position. The display is text for a human, so an argument containing
a space prints as-is — the note is a reproduction aid, not a shell line, and
`--sysroot=` already prints its path unquoted. `cheader-preprocess-failed`
needs no change: it builds through `cheader-cpp-command` and so carries the
flags to its stderr-attached re-run for free — which is the point of the
single builder, and a unit pins it (§5).

## 5. CF-3 — tests

In `tests/suite-target.nuc`, beside `c4-missing-header-is-fatal` (`:131`) —
the search-path units live where the C4 units do. Helpers already exist for
every step: `test-scratch-sub` / `test-write-file` (`lib/test.nuc:599`, `:607`)
for the header tree, `compile-path` (`tests/nuctests.nuc:208`) and
`build-run-file` (`:1032`, which takes one extra argument) for the builds,
`check-line` / `check-error-at` / `check-note-at` for the assertions.

| Unit | Claim |
| --- | --- |
| `s21-cflag-include-dir` | The §1.3 stand-in: `inc/gtk/gtk.h` including `<glib/glib.h>`; `--cflag=-I<inc>` compiles and the IR carries `declare ptr @gtk_label_new(ptr)` and `declare void @g_object_unref(ptr)`. The same source without the flag fails with the C4 error at line 1 — the pair, in one unit, so the flag is shown to be *the* difference. |
| `s21-cflag-in-note` | With `--cflag=-I<inc>` and a header that exists nowhere, the failure `note:` reads `clang -E -I<inc> -x c -include missing.h /dev/null` — the display carries the flag, at that position. |
| `s21-cflag-verbatim` | `--cflag=-DNUC_CF_ON=1` gates a declaration and an object-like `#define` under `#ifdef NUC_CF_ON` in a scratch header: with the flag the function is declared and the constant is admitted (Stage 17, through the `-dM` run — proving that run carries the flags too); without it neither exists and the program is refused. And `NUC_CF_ON` itself is **not** admitted as a constant — it is in the baseline (§1.5). |
| `s21-dash-i-not-forwarded` | A scratch directory holding a `string.h` that declares only `nuc_shadow_marker`, passed as `-I <dir>`: a program calling `strlen` still declares `@strlen` and never `@nuc_shadow_marker`. The §1.4 hazard as a regression unit. |
| `s21-cflag-empty-refused` | `--cflag=` exits 2 with `--cflag= requires an argument`. |

The REPL needs no unit of its own: argv parsing precedes `repl-main`, and
`repl-session` (`tests/nuctests.nuc:1065`) takes no extra arguments; if one is
wanted later it is a `repl-session-with` and a scratch header, and the claim it
would pin is already CF-1's plumbing, not REPL code.

## 6. CF-4 — docs

- `docs/compiler.md`: a `--cflag=<arg>` row after `--sysroot=<path>` (`:28`),
  in that row's voice — "one verbatim argument to the `clang -E` that reads a
  C header import; repeatable; only the preprocessor consults it; `-I` is the
  Nucleus import path and is *not* forwarded, so a directory of `.nuc` modules
  (which may carry generated `.h` files named after them) never shadows a
  system header". A new subsection **"C headers outside the default search
  path"** beside "C headers under `--target=`" (`:630`): the GTK case, the
  `make` idiom, the `note:` a user sees without the flag, one sentence that
  `CPATH` also reaches clang and why the flag is preferred.
- `docs/builtins.md:30` carries an abridged copy of the flag table; add the
  row there too so the two tables do not disagree on what exists.
- `context/local.md`'s toolchain paragraph ("`clang -E` is also shelled out
  per C header") gains half a sentence naming the flag.

---

## 7. Gates

- `make` and `make test` green; the five §5 units pass.
- **`make bootstrap` converges with no refresh**: the compiler's own build
  passes no `--cflag`, so its `clang -E` argv is byte-for-byte what it was and
  every header read is unchanged. `build/nucleusc.ll` byte-identical is the
  assertion, not the hope — `ir-snapshot.sh verify` clean.
- The pre-existing C4 units (`c4-missing-sysroot-falls-back` `:111`,
  `c4-missing-header-is-fatal` `:131`) unchanged: the flag-free display string
  they pin does not move.
- `--emit-nuch` / `--emit-cheader` on a file whose import needs the flag
  succeed with it and fail with the C4 error without it — one run each,
  recorded in progress.md rather than a unit, since the claim is CF-1's and
  the modes share the path.

## 8. Sequencing

Independent of items 1 and 2, both built. No new spelling enters `src/` (a
`defvar`, a `cond` arm, two loops), so the boot compiler builds the tree as it
stands and no `make update-bootstrap` is involved. Lands whenever; nothing
waits on it.

## 9. What the flag does not promise

The gate is the **search path**, not GTK. With the flag, `clang -E` reads
`gtk/gtk.h` and several hundred headers behind it; what the declaration
parser then makes of them — GObject's function-like macros, `G_GNUC_*`
attributes, `_Float128`-class types, opaque `GtkWidget *` everywhere — is
Stage 16 C2's business (a declaration it cannot represent is skipped with a
recorded reason and diagnosed at first use, `docs/compiler.md:130`), and the
first thing to probe once CF-1 lands, on a machine that has `gtk4.pc`. This
container does not. The demo keeps its hand `declare`s until that probe says
they can go; when they do, its `(deftype GtkWidget ptr)` lines go with them,
since the header's `typedef struct _GtkWidget GtkWidget` is the opaque type the
importer already knows how to make.

---

## 10. As built (2026-09-19)

Landed as designed; the diff is a `defvar`, a `defn`, a `cond` arm, the usage
line, two loops and one comment at the cache key. Two details the plan left
open were settled by the smoke run before the units were written:

- **The empty value** is refused by byte length (`<= 8`, the prefix itself),
  the way `-I` decides between its two spellings, so `--cflag=` exits 2 with
  `--cflag= requires an argument` before `--diagnostics=sexp` is even seen —
  which is why the unit reads the message from the raw stream.
- **The `-D` claim held in every part** without further plumbing: the gated
  declaration and the gated `#define` both appear with `--cflag=-DNUC_CF_ON=1`
  (the `-dM` run goes through the one builder), the constant folds
  (`add nsw i32 42, %t0`), and `NUC_CF_ON` itself is `undefined:` — it is in
  the predefine baseline, which also goes through the one builder.

**Gates.** `make test`: **1070 passed, 0 failed, 0 skipped** (1065 + the five
§5 units, each also run singly with `--run`, plus the two neighbouring C4 units
unchanged). `make bootstrap`: `stage1.ll == stage2.ll`, `hello` runs — the
compiler's own build passes no `--cflag`, so its argv and every header it
reads are what they were. The `-I`-shadow unit was checked to bite: with the
same scratch `string.h` reaching clang through `CPATH` instead, the compile
fails `unknown: strlen`, which is the failure the unit exists to catch.
Header modes with the stand-in and the flag: `--emit-nuch` exports
`(declare make-label ((text CStr)) :ptr)`, `--emit-cheader` exports
`void* make_label(const char* text)`. REPL: `nucleusc -i --cflag=-I<inc>`
then `(import-use "gtk/gtk.h")` answers `imported gtk/gtk.h` (the call that
follows fails at JIT symbol lookup, as any stand-in with no library behind it
must).

**One finding, pre-existing and recorded rather than fixed.** The §7 gate
"header modes fail with the C4 error without the flag" is false, and was false
before this item: `--emit-nuch` and `--emit-cheader` on a file whose C header
cannot be preprocessed print the `note:` and clang's `file not found` to
stderr, then **exit 0 and emit a header without that import's names**. The
`die-at` (`c-include: failed to preprocess`, `src/cheader.nuc:2963`) is on the
emit-time import path, which the header modes never reach; they run the
prescans only, and the W3a name pre-scan (`:2766`) tolerates a null buffer.
`--emit-llvm` on the same file exits 1 with the located error. Listed in
[overview.md](overview.md) under candidate rough edges; the fix is the prescan
refusing what the emitter refuses, which is "What a header mode checks"
(`docs/compiler.md`) extended to imports.

**The first GTK probe (same day, on the host).** With the flag, the demo's
build got past clang and into the declaration parser, and stopped at
`nucleusc: too many structs` — `MAX-STRUCTS` (`src/compiler-types.nuc`), the
runaway-growth guard on `g-structs`, was 1024, sized in Stage 15 W3a against
SDL's umbrella header (~256 slots). `gtk/gtk.h` brings GLib, GObject, GIO, GDK,
Pango, Cairo and HarfBuzz with it, and every C struct, opaque forward
declaration and typedef alias takes a slot. Raised to 16384: the guard is a
comparison on a `Vector`'s count, nothing preallocates against it, and no
other cap sits on the import path (a C `enum` is typed `int` with no registry,
a C `union` registers through the same `register-struct`, typedefs are an
uncapped list; `C-MAX-PARAMS` 32 skips a declaration rather than dying). A
synthetic 6,000-type / 6,000-function header compiles in 0.9 s, so the linear
`lookup-struct` scan is not the next wall. `s21-thousands-of-c-structs`
(`tests/suite-cimport.nuc`) registers 4,000 and uses the last of each shape.
`make test` 1071/0/0; `make bootstrap` converged (the constant only feeds a
comparison; no boot refresh). GTK's headers were not available in the
container, so what the parser makes of them past this point is still the
host's probe to run.

**The second GTK probe (same day).** Past the cap, the demo's build reported
`unknown: 'gtk_application_new' — its C header declaration was skipped
(gtkapplication.h:73: a by-value parameter or return of unknown type
'GApplicationFlags')`. Not reproducible here at first — the container's Debian
GLib 2.84 stream compiled the demo clean, and upstream 2.86.0's `gioenums.h`
and `gmacros.h` are code-identical to it — so the host's exact preprocessed
stream was dumped into the shared tree and re-read through `-include`. The
host's GLib (a 2.86 revision) writes every flags enum as
`typedef enum { … } __attribute__((flag_enum)) GApplicationFlags;` — 70 such
typedefs in one `gtk/gtk.h` stream. The enum branch of `c-parse-type`
(`src/cheader.nuc`, the `is-enum` block) skipped the braces and the qualifiers
but never the attribute run, so `c-parse-typedef-decl` read `__attribute__` as
the declarator, recorded a phantom typedef of that name, and never recorded the
real one; every function taking such an enum by value was then skipped. The
struct branch had consumed the same run since Stage 16 PK-2. **Fix:** one
`c-skip-attributes` after `cheader-skip-braces` in the enum branch — both the
L5 prescan and the real pass funnel through `c-parse-typedef-decl`, so one site
covers both. `s21-enum-trailing-attribute` (`tests/suite-declarators.nuc`) pins
the GLib shape, a doubled run, `const` and `*` after the run, and a plain
typedef, each through a by-value use. Against the host's byte-exact stream the
demo now compiles with 13,233 declarations imported and every call resolved.
`make test` 1072/0/0; `make bootstrap` converged. `docs/structs-unions.md`'s
C-typedef section says so.

What the demo needed once the header parsed (the answer to "the type error on
line 45"): `GtkWidget` is now the opaque struct, not a `deftype` alias for
`ptr`, so `window:GtkWidget` is refused as a by-value opaque and the fix is
`ptr:GtkWidget` with no cast; `app:ptr:GtkApplication` likewise; the hand
`defconst` for `G_APPLICATION_DEFAULT_FLAGS` stays (enumerators are not
imported — overview.md rough edges); and `g_signal_connect_data`'s `GCallback`
parameter is a real `():void` function-pointer type (Stage 16 FP-4), so the
`(ptr, ptr):void` handler needs `(unsafe/cast GCallback on-activate)` — C's
`G_CALLBACK()` made explicit; `as` correctly refuses it as a reinterpretation.
Every `GtkWindow*`/`GtkWidget*`/`GApplication*` parameter is bare `ptr` at the
boundary (every C pointer is, `docs/structs-unions.md`), so the GObject cast
macros have nothing to do.

The demo's third wall (2026-09-20) is not this document's: with a combo box
added it segfaulted the compiler, and the cause is a mis-shaped `doseq` call —
`(doseq item v (VecIter i32) …)` — dereferencing null inside the JIT'd macro
body, unguarded by the macro and unfenced by the compiler. Recorded in the
stage overview's rough edges; it reproduces with no C import at all.
