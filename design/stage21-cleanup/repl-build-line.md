# Stage 21 — The REPL's build line: flags, search paths and libraries at the prompt

**Status:** designed 2026-09-21, **built the same day** (RC-0 … RC-6; §12 "As
built"). Every file:line in §1 was verified
against the tree that day; every REPL transcript in §1 was taken from
`build/nucleusc` rebuilt at `ac1730e` plus the uncommitted item-3 tree, and
the JIT claim in §1.3 from a C probe against the container's LLVM 19.1.7. §9
has the gates and §10 the sequencing (independent of items 1–3, no boot
refresh).

**Goal.** A C library that item 3 made importable in a batch build is usable
from a REPL session too, without restarting the session and without editing
the command line an editor launches the REPL with. Item 3 gave the batch
compiler `--cflag=<arg>`; the REPL inherits it from argv and nothing else. Four
things are missing, and they compound: a session cannot add a preprocessor
flag, a Nucleus import directory or a shared library after it has started; the
one spelling that *is* on the command line for libraries, `-l<lib>`, is
silently ignored under `-i` (the REPL never links, and nothing loads); and a
header import that failed for want of a flag is cached as a failure, so even a
flag that could be added would not rescue it. Editors launch the REPL from one
global argument list (`nucleus-repl-program-args`, `editor/nucleus-repl.el:29`)
— the exact place a per-project GTK build line does not belong. The fix is four
meta forms mirroring four flags, one cache invalidation, and a REPL meaning for
`-l`/`-L`. Found by walking the GTK demo's REPL story after item 3 landed; one
prerequisite bug fell out of the first probe (§1.4).

---

## 1. Ground truth (verified 2026-09-21)

### 1.1 What reaches the REPL from argv, and when

`main` (`src/nucleusc.nuc:19918`) parses the whole command line, then
dispatches to `repl-main` (`:20001`, `src/repl.nuc:1886`) before anything
batch-only runs. Of the flags a C library needs:

| Flag | Feeds | Under `-i` |
| --- | --- | --- |
| `--cflag=<arg>` (`:19975`) | `g-cflags` (`:627`), read by `cheader-cpp-command` at every preprocessor run (`src/cheader.nuc:1415`) | works: the five libc preloads and every prompt-time `(import-use "x.h")` go through the one builder (item 3 §1.5) |
| `-I<dir>` (`:19979`) | `g-include-paths` (`:930`), read at resolution time by `try-import-path` (`:18737`) and the definer scan (`:3308`) | works, and — because it is read at resolution time, not parse time — a prompt-time append would work too |
| `-l<lib>` / `-L<dir>` (`:19989`) | `g-link-args` (`:624`), verbatim, consumed by the link step only (`:19816`) | **silently nothing** |
| `--link-arg=<arg>` (`:19973`) | the same vector | silently nothing |

There is no prompt-time spelling for any of them. The meta forms
(`repl-handle-builtin`, `src/repl.nuc:321–515`) answer sixteen heads —
`defined?`, `kind-of`, `type-of`, `dir`, `doc`, `apropos`, `complete`,
`locate`, `trace`, `untrace`, `forget`/`reset!`, `last-error`, `imports`,
`casts`, `expansion-of` — and every one interrogates state; none sets it.
`repl-meta-sym-arg` (`:175`) accepts a symbol or a string for the one-argument
forms; `repl-error` (`:103`) renders an error as text or, under
`--repl-format=json`, as one JSON object, which is what an editor parses.

### 1.2 The caches that assume flags are fixed

Item 3 kept `--cflag=`s out of the preprocess cache key
(`cheader-preprocess-mode`, `src/cheader.nuc:1506`; the comment at `:1510`:
"they are fixed for the whole process") and left the macro baseline
(`cheader-macro-baseline-load`, `:2922`) behind a one-shot latch
(`g-cmacro-baseline-ready`, `:2923`). Both are correct for a batch compile and
both are wrong the moment a flag can change mid-process. The cache is the
sharper of the two, because a **failure is cached** (`:1542–1547`: "Cached as a
null buffer like any other answer … the diagnosis should be printed once"):

```
nuc> (import-use "nucprobe.h")
  note: clang -E -x c -include nucprobe.h /dev/null
<built-in>:1:10: fatal error: 'nucprobe.h' file not found
<repl>:1: error: c-include: failed to preprocess 'nucprobe.h'
  error: error (recovered)
nuc> (import-use "nucprobe.h")
<repl>:1: error: c-include: failed to preprocess 'nucprobe.h'
  error: error (recovered)
```

The second attempt does not run clang at all — no `note:`, no clang diagnosis.
So even with a prompt-time `(cflag "-I…")` in hand, the retry would be served
the first attempt's null buffer. The REPL's snapshot/restore (`ReplState`,
`src/repl.nuc:1668`) rolls back `g-imported` and the header registries a
failed import touched, but the preprocess cache is deliberately not in the
roster: under fixed flags a cached answer is idempotent, which is the premise
this item removes.

The baseline latch has the quieter consequence: it is loaded during
`repl-include-all-libc` (`src/repl.nuc:1640`, via `cheader-import-macros`,
`src/cheader.nuc:2941`) at startup, under the startup flags. A `-D` added at
the prompt afterwards is not in the baseline, so on the next header import the
define would be *admitted* as a header constant — the opposite of what item 3
established for a command-line `-D` (`s21-cflag-verbatim`).

### 1.3 How a C function resolves in the JIT, and what `-l` would have to do

`jit-ensure-init` (`src/nucleusc.nuc:15098`) attaches no generator of its own;
LLJIT links the `<Process Symbols>` JITDylib last
([repl-jit-symbol-precedence.md](../stage16-ergonomics/repl-jit-symbol-precedence.md)
§2), and that dylib reflects the **process's dynamic symbol scope**: the
`-rdynamic` compiler binary, its `DT_NEEDED` libraries, and anything `dlopen`ed
`RTLD_GLOBAL`. A C library the compiler was not linked against is therefore
invisible to every module the session JITs:

```
$ nucleusc -i --cflag=-I$PWD/inc -L$PWD -lnucprobe
nuc> (import-use "nucprobe.h")
  imported nucprobe.h
nuc> (nuc_probe_answer)
JIT session error: Symbols not found: [ nuc_probe_answer ]
  error: JIT lookup error: Failed to materialize symbols: { (main, { __repl_eval_0 }) }
```

(`libnucprobe.so` is one function returning 41.) The header parsed and the call
type-checked; the `-L`/`-l` on the command line changed nothing. The same
session with the library in the process scope answers:

```
$ LD_PRELOAD=$PWD/libnucprobe.so nucleusc -i --cflag=-I$PWD/inc
nuc> (import-use "nucprobe.h")
  imported nucprobe.h
nuc> (nuc_probe_answer)
  41
```

So the mechanism is the process scope, and what is missing is a load. The
compiler already declares the call that does it: `LLVMLoadLibraryPermanently`
(`src/llvm.nuch:45`; `sys::DynamicLibrary::LoadLibraryPermanently`, a
`dlopen(path, RTLD_LAZY|RTLD_GLOBAL)` on POSIX), and calls it with `null` in
`host-exports?` (`src/nucleusc.nuc:1371`) to open the process handle. glibc
adds an `RTLD_GLOBAL` object to the main namespace's search list, which is the
list `dlsym` walks for the process handle, so a library loaded this way is
found by the same lookup that found `printf`. Pinned directly, not by the
`LD_PRELOAD` proxy: a C probe against the container's LLVM 19.1.7
(`scratchpad/load_probe.c`, `LLVMOrcCreateLLJIT` with a null builder and no
generator, exactly `jit-ensure-init`'s shape) adds a module calling
`nuc_probe_answer`, loads, and adds another:

```
JIT session error: Symbols not found: [ nuc_probe_answer ]
[before] lookup failed: Failed to materialize symbols: { (main, { uses_it_before }) }
LLVMLoadLibraryPermanently(…/libnucprobe.so) -> ok
[after] uses_it -> 41
LLVMLoadLibraryPermanently(no-such) -> FAILED (boolean only)
```

Three facts from it: the load is sufficient (no generator, no re-creation of
the JIT); a module that **failed** to materialize before the load does not
poison the session for the one added after it, which is the call-load-call
order a user at the prompt will actually produce; and the C API answers a
boolean — `dlerror()`'s text is discarded, and the tree keeps POSIX-only
externs out of the compiler
([macro-call-linking.md](../stage20-macros/macro-call-linking.md) §5.2), so a
failed load can say what was tried, not why it failed. And `host-exports?`
memoises its answers (`g-host-export-names`/`-answers`, `:559–560`), so a
negative answer taken before a load is stale after it.

### 1.4 A void expression at the prompt is never called

Found on the first probe, before any library was involved. The expression arm
of `repl-eval-form` emits `__repl_eval_N`, JITs it, looks it up, and then
dispatches on the result kind to call-and-print (`src/repl.nuc:1180–1209`).
The `TY-VOID` arm is `(do)` (`:1206–1207`) and so is the fall-through
(`:1208–1209`) — the function is **defined, JITed and never called**:

```
nuc> (defvar counter:i32 0)
  defined
nuc> (defn bump ():void (set! counter (+ counter 1)) (return))
  defined
nuc> (bump)
nuc> (bump)
nuc> counter
  0
```

`(sayhi)` with a `printf` inside prints nothing; `(dotimes (i 2) (printf
"hi\n"))` prints nothing. Every value-returning kind is called (`(set! gx 42)`
in `tests/repl/globals.in` yields `42` and runs), which is why no golden pins
this and why it survived. The fall-through arm also covers every kind the
return-emitting `cond` (`:1104–1139`) lowers to `ret void` — a struct-valued
or `String`-valued expression is emitted, JITed and skipped the same way. The
helper exists: `funcall-void` is what `repl-run-init-fn` uses to run a global
initializer (`:610`). This is a prerequisite rather than a side finding
because `gtk_init`, `gtk_window_present`, `gtk_widget_set_size_request` and
most of GTK's surface return `void`; a session that could load GTK and then
silently skipped every such call would look broken in a way that has nothing
to do with loading.

### 1.5 The editor's launch line

`M-x run-nucleus` runs `nucleusc -i --repl-format=json` from
`nucleus-repl-program-args`, a `defcustom` (`editor/nucleus-repl.el:29`,
`docs/emacs.md:47–52`). A per-project build line — GTK is a dozen `-I`s from
`pkg-config --cflags gtk4`, plus its `--libs` — would have to be a
`.dir-locals.el` override of that variable, re-spelled from `pkg-config`'s
output by hand, and is still fixed for the life of the session. The forms this
item adds are typed at the prompt or kept in a scratch buffer and sent with
`C-c C-k`; the argument list stays global.

### 1.6 Where the pieces already are

- The meta-form dispatcher is one `when`-chain ending in `(return 0)`
  (`src/repl.nuc:515`); a new form is one more `when` above it.
- Every flag vector is arena-backed and built by `@__nucleus_init` (G-5;
  `src/nucleusc.nuc:19901–19916`), so a prompt-time `conj` needs no lazy guard.
- The library `Vector` truncation the REPL already uses (`repl-vec-truncate`,
  `src/repl.nuc:1747`) is what emptying the `host-exports?` memo needs.
- `lib/file.nuc`'s `read-dir` (`:245`; already in the compiler's unit through
  `src/strfmt.nuc:32`) is a directory test; `file-exists`
  (`src/nucleusc.nuc:18711`) is a file test.
- `repl-session` (`tests/nuctests.nuc:1065`) drives a session from a file;
  `command-env` (`lib/process.nuc:129`) sets one child environment binding;
  `cflag-stand-in` / `cflag-include` (`tests/suite-target.nuc:163–181`) build
  item 3's header tree.

---

## 2. Verdict — four meta forms mirroring four flags, and `-l` means load

**Each flag a C library needs gets a meta form of the same name and the same
one-argument-per-entry discipline; with arguments a form adds, with none it
reports what is in force; `-l<lib>`/`-L<dir>` under `-i` load into the
session; a flag change empties the preprocess cache and re-arms the baseline.**

| Flag | Form | Feeds | Takes effect |
| --- | --- | --- | --- |
| `--cflag=<arg>` | `(cflag "<arg>" …)` | `g-cflags` | the next header read (§4) |
| `-I<dir>` | `(import-path "<dir>" …)` | `g-include-paths` | the next import (§5) |
| `-L<dir>` | `(library-path "<dir>" …)` | `g-library-paths` (new) | the next `load-library` (§6) |
| `-l<lib>` | `(load-library "<lib>" …)` | the process, via `LLVMLoadLibraryPermanently` | the next module the session JITs (§6) |
| — | `(pkg-config "<pkg>" …)` | all four, from `pkg-config`'s output | optional, §7 |

Names follow the flags and the docs' own nouns — `docs/compiler.md:21` calls
`-I` "the import search path", the linker calls `-L` the library search path —
so a user who knows the batch line can guess the prompt form, and `(dir)`,
`(doc cflag)` need no new vocabulary. An argument is a string, or a bare symbol
where the reader will take it (`repl-meta-sym-arg`'s rule, `:171–174`); a form
validates every argument before applying any, so a bad third argument adds
nothing (atomic, like a failed import). The flag vectors and the loaded
libraries are **session configuration, outside `ReplState`**: a failed import
must not un-set the flag typed before it, and a `longjmp` never skips a meta
form (the forms do not throw). Nothing here reaches batch: a `(cflag …)` in a
source file is an unknown call, as every meta form is, and `main`'s parser is
untouched.

Rejected, each for a reason a later reader may want to re-weigh:

1. **Environment variables at the prompt** — `CPATH` reaches the child clang
   and `LD_LIBRARY_PATH` reaches `dlopen`; a `(setenv …)` would work today. It
   is invisible in a transcript, has item 3 §1.4's shadowing hazard with no
   flag order to reason about, and `LD_LIBRARY_PATH` set after process start
   is not consulted by glibc's loader at all (it is read once, at startup).
2. **A startup file** (`.nucleusrc` in the working directory, evaluated before
   the prompt) — solves the editor case completely and is the `.envrc` /
   `.dir-locals.el` shape, with the same "a checkout runs code because you
   opened it" problem those two mitigate with a trust prompt. The editor's
   send-buffer already does what a startup file would, with the user's finger
   on it. Recorded as the natural follow-up once a `(load "file")` form exists
   (not decided here, below).
3. **`--load=<file>` / `-l` as a load-file flag** — a command-line flag is the
   thing §1.5 says is inconvenient, and `-l` already means library.
4. **A `DynamicLibrarySearchGenerator` for the library, attached to the main
   dylib** — the exact shape repl-jit-symbol-precedence.md §2 deleted: a
   generator on main *defines* what it resolves there, and every later module
   defining that name is a duplicate. The process scope is where LLJIT already
   looks; loading into it is the whole change.
5. **Re-keying the preprocess cache on the flags** — correct, and more
   machinery than the fact warrants: at the prompt a header is imported at most
   once (`g-imported` dedups), so the cache's only REPL job is the
   prescan/real-pass pair inside one import, which is after any flag change.
   Emptying it is a one-line invariant; a key is a data structure.
6. **One `(config :cflag … :lib …)` form** — a keyword grammar for four
   independent lists is a parser where four heads will do, and the flag names
   already carry the meaning.
7. **Forwarding `-I` to clang** — item 3 §1.4, proven, unchanged.

Not decided here: **`(load "file.nuc")`**, evaluating a file's forms as if
typed (meta forms included). It is `repl-protect-preload`'s shape over a file
(`src/repl.nuc:1865`) and is what a non-Emacs editor would use for a
per-project setup file; it is a general REPL feature, not a library one, and
this item does not need it. Also not decided: **`--cc=<cmd>`**, item 3 §2's
open note, which a `(cc "…")` form would mirror if it existed.

---

## 3. RC-0 — a void expression at the prompt runs

`src/repl.nuc`, the call-and-print `cond` (`:1180–1209`): the `TY-VOID` arm
and the fall-through arm both call `(funcall-void (unsafe/cast ptr addr))`
when the eval function was defined `void` (`ret-ir`, `:1141`, is in scope);
neither prints anything, as now. The wide floats (`F16`/`F80`/`F128`) keep
their arm as it is: their eval function returns the value (FL-1: "only the
printing side has no helper"), and calling an `f80`-returning function through
a void pointer would leave the value on the x87 stack for the caller to never
pop — so they stay unprinted *and* uncalled until a print helper lands, which
is FL-1's open edge, not this one. One `tests/repl/s21-void-runs.in` golden:
the §1.4 transcript with `counter` answering `2`, and a void `defn` whose
`printf` line appears. Independent of everything below and of items 1–3; may
land as its own commit.

## 4. RC-1 — `(cflag …)`, and the caches learn that flags move

`src/repl.nuc`, one arm in `repl-handle-builtin`:

- `(cflag "<arg>" …)` — each argument, validated (string or symbol, non-empty:
  `cflag: argument must be a string`, `cflag: empty argument`, both through
  `repl-error` at the form's line), is `add-cflag`ed verbatim in order, then
  reported one per line as `  cflag: <arg>`. Then `cheader-flags-changed` is
  called once. `(cflag)` prints the flags in force, one per line, indented two
  spaces, `  (none)` when empty — `(imports)`' shape (`:490–498`).

`src/cheader.nuc`, beside the cache:

- `cheader-flags-changed` — `(set! g-cheader-cache null)` and
  `(set! g-cmacro-baseline-ready 0)`. The parked buffers (`g-cheader-bufs`,
  `src/nucleusc.nuc:631`) are process-lifetime and untouched, which is what
  makes dropping the records safe; the baseline *set* is not cleared — a name
  predefined under the old flags is still one to subtract, and the rebuild on
  the next import adds what the new flags predefine. The key comment at
  `:1510` becomes: fixed for a batch process; at the prompt `(cflag …)` empties
  the cache instead of joining the key.

Nothing else. `cheader-cpp-command` and `-display` already read the vector at
every run, so the `note:` for a failure after a `(cflag …)` shows the flag at
item 3's position (item 3 §4), and the `-dM` run and the rebuilt baseline go
through the one builder. A header already imported is not re-read by a later
flag — `g-imported` dedups it as before — and the docs say so (§8).

## 5. RC-2 — `(import-path …)`

One arm: `(import-path "<dir>" …)` — each argument validated as above and, in
addition, as a directory (`read-dir` succeeds; else `import-path: no such
directory '<dir>'`, the form adds nothing), then `add-include-path`ed and
reported `  import path: <dir>`. A relative path is relative to the session's
working directory, as `-I`'s is. `(import-path)` lists. No cache to touch:
`try-import-path` and the definer scan read the vector at resolution time
(§1.1), and a resolution that failed died and was rolled back, recording
nothing. The batch `-I` keeps its no-check behaviour — the check is a
prompt-time courtesy, where the alternative is a typo discovered three forms
later as `cannot find`.

## 6. RC-3 — `(library-path …)`, `(load-library …)`, and `-l`/`-L` under `-i`

`src/nucleusc.nuc`, beside `g-link-args` (G-5 shape, arena-backed):

- `g-library-paths:&(Vector Symbol)` — directories `-L` names, in order.
- `g-loaded-libraries:&(Vector Symbol)` — the spelling each successful load
  opened, in order.

`src/repl.nuc`:

- `repl-library-file (name)` — the file name for a `-l`-style name: a name
  containing `/` or `.` is verbatim (`libgtk-4.so.1`, `/opt/x/libfoo.so`);
  otherwise `lib<name><suffix>`, suffix `.so`, or `.dylib` when the host triple
  (`g-host-target`) names Darwin, or `.dll` when it names Windows.
- `repl-load-library (name line)` — with the file name in hand: if it contains
  `/`, open exactly that; else try `<dir>/<file>` for each `g-library-paths`
  entry in order, opening the first that `file-exists`, and failing those pass
  the bare file name to `LLVMLoadLibraryPermanently`, which is the loader's own
  search (`LD_LIBRARY_PATH`, `ld.so.cache`, the system directories). A spelling
  already in `g-loaded-libraries` answers `  <file> already loaded` and does
  nothing (`dlopen` would refcount; the report is the point, as it is for
  `already imported`). Success records the spelling opened and reports
  `  loaded <spelling>`. Failure is `load-library: cannot load '<name>' (tried
  <a>, <b>, …)` through `repl-error` — the list of what was tried, because
  §1.3's boolean is all the C API gives. After any successful load the
  `host-exports?` memo is truncated to zero (`repl-vec-truncate` on both
  vectors; `g-host-lib-loaded` stays set) so its answers describe the process
  as it now is.
- `(load-library "<lib>" …)` — validates every argument, then loads each in
  order; a load that fails stops the form there (the ones before it stay
  loaded — a load is not un-doable, so the report says which succeeded).
  `(load-library)` lists `g-loaded-libraries`.
- `(library-path "<dir>" …)` — as `import-path`, into `g-library-paths`,
  reported `  library path: <dir>`; `(library-path)` lists.
- `repl-load-link-args` — called from `repl-main` after `target-init` (the
  suffix needs the host triple) and before `repl-include-all-libc`: two passes
  over `g-link-args`, every `-L<dir>` entry first (into `g-library-paths`, in
  argv order, the way `ld` collects all `-L` before any `-l`), then every
  `-l<lib>` entry through `repl-load-library`. A failure here is fatal — the
  message and exit 1, which is what a batch link with the same `-l` does — so
  a wrong `-l` in an editor's argument list is a visible dead buffer rather
  than a session that fails at the first call. Every other entry of the vector
  (`--link-arg=` values, a `--link-arg=-Wl,…`) is ignored, as it is today; the
  REPL never links, and `--linker=` is ignored the same way. A `--link-arg=-lfoo`
  is indistinguishable from `-lfoo` in the vector and loads; that is the right
  reading of it.

What the JIT sees: nothing changes in `jit-ensure-init`. A module JITed after
the load resolves the library's names through the `<Process Symbols>` dylib
exactly as §1.3's probe did; a session `defn` of the same
name still wins (main is searched first), which is the precedence
repl-jit-symbol-precedence.md chose and this item keeps.

## 7. RC-4 — `(pkg-config …)` (optional; composes RC-1 and RC-3)

The batch idiom is `$(addprefix --cflag=,$(shell pkg-config --cflags gtk4))`
(`docs/compiler.md:693`); the prompt has no shell. `(pkg-config "<pkg>" …)`
runs `pkg-config --cflags <pkgs>` and `pkg-config --libs <pkgs>` as two
captured children (`command`/`spawn`/`process-capture`, the way
`cheader-capture` runs clang, `src/cheader.nuc:1448`), splits each output on
whitespace honouring a backslash-escaped space — pkg-config prints a path with
a space as `with\ space` (probed with pkgconf 2.x in the container) and a
trailing space after the last word — and routes: every `--cflags` word becomes
one `(cflag …)` argument verbatim (`-I…`, `-D…`, `-pthread`, and the two words
of `-isystem <dir>` as two flags, which is what the argv needs); of the
`--libs` words, `-L<dir>` → `library-path`, `-l<lib>` → `load-library`, and
anything else (`-pthread`, `-Wl,…`, `-framework X`, `-rpath …`) is skipped and
named once: `  skipped: -pthread` — the REPL has nothing to link. Ordering is
the batch order: all cflags, then all `-L`, then the `-l`s. A non-zero exit
from either child is `pkg-config: <first line of its stderr>` (`Package 'gtk4'
was not found in the pkg-config search path` is the line that matters) through
`repl-error`, before anything is applied; the child not spawning at all is
`pkg-config: not found`. A library that fails to load after the flags were
applied stops there as `load-library` does — the flags are valid and stay.
`PKG_CONFIG_PATH` is the child's environment, inherited, as `CPATH` is for
clang; unlike `CPATH` it is the documented way to point pkg-config at a `.pc`
directory, and the docs say so.

Optional because RC-1 and RC-3 are complete without it; it is the form a GTK
user will actually type, so it is designed here rather than deferred.

---

## 8. RC-5 — tests, RC-6 — docs

### 8.1 Tests

In `tests/suite-target.nuc` beside `s21-cflag-*` (the search-path units live
together), except RC-0's golden. Helpers: `cflag-stand-in`/`cflag-include`
for the header tree; a `repl-session-with` beside `repl-session`
(`tests/nuctests.nuc:1065`) taking up to three extra arguments (empty = none,
`cflag-emit`'s convention) and one environment binding (`command-env`); the
scratch `.so` is one C file built with `cc -shared -fPIC`, spawned as
`cc-run-file` (`tests/nuctests.nuc:1003`) spawns `cc`.

| Unit | Claim |
| --- | --- |
| `s21-void-runs` (golden, `tests/repl/`) | §1.4's transcript: `counter` answers `2`; a void `defn`'s `printf` line appears; a value-returning form still prints its value. |
| `s21-repl-cflag` | The stand-in tree. `(import-use "gtk/gtk.h")` fails with the C4 error and a `note:` with no `-I`; `(cflag "-I<inc>")` reports it; the **same import retried** answers `imported gtk/gtk.h` — the §1.2 cache bug as a regression unit, since without `cheader-flags-changed` the retry is served the null buffer — and a following `(gtk_label_new "hi")` type-checks (its JIT lookup fails, as any stand-in with no library must; the unit asserts the import, not the call). Then `(import-use "no-such-s21.h")` prints a `note:` carrying `-I<inc>` at item 3's position. `(cflag)` lists the one flag. |
| `s21-repl-cflag-define` | `(cflag "-DNUC_CF_ON=1")` at the prompt, then `(import-use "cf.h")` (item 3's gated header): `NUC_CF_CONST` evaluates to `42` and `NUC_CF_ON` is `undefined:` — the baseline was re-armed and rebuilt under the new flag. Without RC-1's re-arm the second assertion fails (the define is admitted). |
| `s21-repl-import-path` | A scratch `zz.nuc` defining `zz-answer`. `(import-use zz)` → `cannot find 'zz'`; `(import-path "<dir>")` reports; `(import-use zz)` → `imported zz`; `(zz-answer)` → `7`. `(import-path "<dir>/nope")` → `no such directory`, and `(import-path)` still lists one entry. |
| `s21-repl-load-library` | The probe `.so` and its header. `(cflag "-I<inc>")`, `(import-use "nucprobe.h")`, `(nuc_probe_answer)` → `JIT lookup error` (`Symbols not found`); `(load-library "<dir>/libnucprobe.so")` → `loaded …`; `(nuc_probe_answer)` → `41`; `(load-library "<dir>/libnucprobe.so")` → `already loaded`. Then the name form: `(library-path "<dir>")`, `(load-library "nucprobe")` → `already loaded` under the spelling `<dir>/libnucprobe.so` (the search found the same file). `(load-library "no-such-lib-s21")` → `cannot load 'no-such-lib-s21' (tried <dir>/libno-such-lib-s21.so, libno-such-lib-s21.so)`, and the next form still evaluates. |
| `s21-repl-argv-libs` | `repl-session-with "-L<dir>" "-lnucprobe" "--cflag=-I<inc>"`: `(import-use "nucprobe.h")` then `(nuc_probe_answer)` → `41` with no prompt-time form — the §1.3 transcript's first half, now answering. A second session with `-lno-such-lib-s21` exits 1 with the `cannot load` message and no `nuc>` after it. |
| `s21-repl-pkg-config` (RC-4) | A scratch `nucprobe.pc` (`Cflags: -I<inc> -I"<dir with space>" -DNUC_PC=1`, `Libs: -L<dir> -lnucprobe -pthread`) with `PKG_CONFIG_PATH` set through `command-env`. `(pkg-config "nucprobe")` reports three cflags (the escaped space arrives as one argument), one library path, one load, `skipped: -pthread`; `(import-use "nucprobe.h")` and `(nuc_probe_answer)` → `41`; `NUC_PC` is `undefined:` (baseline). `(pkg-config "no-such-pkg-s21")` → `pkg-config: Package 'no-such-pkg-s21' was not found …` and nothing applied (`(cflag)` unchanged). `skip!` when `pkg-config` is not on the path. |

### 8.2 Docs

- `docs/compiler.md`: the REPL meta-forms table (`:349–369`) gains five rows
  in the table's voice; the flags table's `-l<lib>` / `-L<dir>` row (`:12`)
  gains "under `-i`, loaded into the session — see [Using a C library at the
  prompt]"; `--link-arg=` (`:31`) gains "ignored under `-i`"; the sentence
  "All libc functions … are pre-loaded" (`:341`) gains its other half — any
  other C library needs its header imported and its shared object loaded; a
  new subsection **"Using a C library at the prompt"** in the REPL section: the
  four forms and `pkg-config` as one transcript against GTK, the "flags are
  session configuration, a failed import does not roll them back" rule, "a
  header already imported is not re-read", and one sentence each on
  `LD_LIBRARY_PATH` (read at process start; `library-path` is the prompt-time
  equivalent) and `PKG_CONFIG_PATH` (inherited). "C headers outside the
  default search path" (`:668`) gets a cross-reference.
- `docs/builtins.md:30`'s abridged flag table: the `-l`/`-L` clause.
- `docs/emacs.md` "Starting the REPL": the argument list is global on purpose;
  per-project flags are forms, kept in a scratch buffer and sent with
  `C-c C-k`.
- `context/repl.md` "Practical notes": one bullet — a library outside the
  compiler's link line needs `(load-library …)` before its first call, and the
  four forms are how a heredoc session gets its build line.
- [repl-libraries.md](../stage16-ergonomics/repl-libraries.md) §3.4's roster
  note: the flag vectors and loaded libraries join the "deliberately not rolled
  back" list, with the reason (§2).

---

## 9. Gates

- `make` and `make test` green; the §8.1 units pass, each also run singly.
- **`make bootstrap` converges with no boot refresh**: the changes are
  `defvar`s, `defn`s, `when` arms and one `cond` arm in `src/`, no new
  spelling, so the boot compiler builds the tree as it stands.
- **Batch neutrality**: `scripts/stage17/ir-snapshot.sh verify` clean.
  `main`'s parser is untouched and every new function is reached from
  `repl-main` or `repl-handle-builtin` only, so no batch artifact can move;
  the run is the proof rather than the argument.
- The REPL goldens (`tests/expected/repl-*.out`) unchanged **except** where
  RC-0 makes a previously skipped void expression run; every changed
  transcript is read line by line before it is accepted, since each changed
  line is a side effect the session used to drop.
- `scripts/check-repl-roster.py` clean — `ReplState` does not change; the new
  globals are outside it by design, and the roster script would flag them only
  if they were fields.
- Item 3's `s21-cflag-*` units and the C4 units unchanged: the batch `note:`
  and the batch cache path are what they were.
- The end-to-end probe from §1.3, by hand: `nucleusc -i`, then `(cflag …)`,
  `(load-library …)`, `(import-use "nucprobe.h")`, `(nuc_probe_answer)` → `41`
  in one session with no flag on the command line; and on the host with
  `gtk4.pc`, `(pkg-config "gtk4")`, `(import-use "gtk/gtk.h")`, `(gtk_init)`
  — a void call, RC-0's — recorded in progress.md.

## 10. Sequencing

Independent of items 1–3 and of the boot. **RC-0 first** (its own commit if
convenient; it is a bug fix with a golden). RC-1, RC-2 and RC-3 are
independent of each other; RC-3 before RC-1 makes the §1.3 probe answerable
end to end earliest, RC-1 before RC-3 makes the header half testable earliest
— either order. RC-4 after RC-1 and RC-3. RC-5's units land with the unit they
pin; RC-6 last. No `make update-bootstrap` anywhere.

## 11. What this does not promise

- **A GTK main loop owns the prompt.** `(g_application_run app 0 null)` blocks
  the REPL until the last window closes; that is what the call does, and a
  session is one thread. Building the widgets and presenting a window without
  entering the loop is what the prompt is for.
- **No unloading.** `LLVMLoadLibraryPermanently` is permanent; `forget` does
  not apply to a library, and a session that needs a different build of one
  restarts.
- **A loaded library shares the compiler's process.** A crash inside it is a
  crash of the session, with no fault boundary — the same hazard the
  `doseq`-segfault rough edge records for a macro body, one tier out.
- **`--warn-ct-shadow`'s wording widens.** `host-exports?` answers for the
  process, so after `(load-library "gtk-4")` a session `(defn gtk_init …)`
  draws the warning whose text says "the compiler binary also exports" — a true
  collision, a stale noun. Not reworded here; recorded.
- **Prompt-time flags are the session's.** They do not become a batch build
  line; the docs' `make` idiom is still the way a program is built.
- **A header imported before a flag change is not re-read.** `(cflag …)` then
  `(import-use "x.h")` for an `x.h` already imported answers `already
  imported`; the flag applies to headers not yet read. Restart to re-read.
- **What the C API withholds.** A failed load names what was tried; the reason
  (`dlerror`) is not available through `LLVMLoadLibraryPermanently`, and the
  compiler stays free of POSIX-only externs. `LD_DEBUG=libs` on the host is the
  next step when the list of paths tried is not enough.

---

## 12. As built (2026-09-21)

Landed the same day, RC-0 … RC-6 as designed. Three source files:
`src/repl.nuc` (+~290 — RC-0's two `funcall-void` calls; five arms in
`repl-handle-builtin`; one "build line at the prompt" section before
`repl-main`: `repl-build-args` (validate all, then collect),
`repl-list-symbols`, `repl-apply-cflags`, `repl-apply-dirs`,
`repl-library-file`, `repl-library-loaded?`, `repl-library-load`,
`repl-load-library`, `repl-apply-libs`, `repl-load-link-args`,
`repl-pkg-config-run` / `-words` / `-failure`, `repl-pkg-config`; the
`repl-load-link-args` call after `target-init`), `src/nucleusc.nuc` (the two
vectors beside `g-link-args`), `src/cheader.nuc` (`cheader-flags-changed` and
the cache-key comment). `main`'s parser and `ReplState` untouched. Five details
the plan left open were settled by the building:

- **The directory test is `dir-exists?`** (`lib/file.nuc:272`, "opendir
  succeeds"), not `read-dir`: the latter also validates the dirent layout, and
  would refuse every directory on a platform with a different `d_name` offset.
- **`pkg-config: not found` also covers exit 127 with empty stderr.**
  `lib/process.nuc`'s `spawn` succeeds whenever `fork` does; an exec that fails
  is `_exit 127` with nothing said, so mapping only a spawn error to "not
  found" would have printed `pkg-config: exited 127` for the one case §7 names.
- **Message layering.** `repl-library-load` returns the bare `cannot load
  '<name>' (tried …)` text or `""`; the meta form prefixes `load-library: `
  through `repl-error`, the argv route prefixes `error: -l<lib>: ` through
  `eprint` and exits 1 — no double prefix on the fatal line.
- **`(load-library "m")` fails and `(load-library "libm.so.6")` loads**: on
  glibc the development symlinks `libm.so`/`libc.so` are linker scripts, which
  `dlopen` refuses. The loader's honest answer, not a bug; the docs say to name
  the soname for those (a name containing `.` is verbatim).
- **The container's `pkg-config` (freedesktop 1.8.1) prints the missing-package
  line unquoted** — `Package x was not found in the pkg-config search path.` —
  where pkgconf writes `Package 'x' …`; §8.1's quoted form was pkgconf's. The
  unit asserts the unquoted tail.

**Tests.** `tests/nuctests.nuc`: `repl-session-with (a b c env-k env-v text)`
— three argv words and one environment binding, empty = none — with
`repl-session` delegating to it. `tests/suite-target.nuc` after
`s21-cflag-empty-refused`: `probe-library` (builds `libnucprobe.so` and
`pinc/nucprobe.h` in the unit's scratch dir with `cc -shared -fPIC`, behind
`require-cc`) and the six units `s21-repl-cflag`, `s21-repl-cflag-define`,
`s21-repl-import-path`, `s21-repl-load-library`, `s21-repl-argv-libs`,
`s21-repl-pkg-config` (`skip!` without `pkg-config`), asserting on
multi-line needles where order is the claim; `tests/repl/s21-void-runs.in` +
`tests/expected/repl-s21-void-runs.out` (`2`, `hello from void`, `after` then
`6`). +7, not §8.1's "seven units plus the golden": the table's seventh row *is*
the golden.

**Docs** as §8.2, with two corrections found while reconciling against the
build: the illustrative GTK transcript shows `loaded libgtk-4.so` with no
`library path:` line — a distribution's `gtk4.pc` names no `-L`, and when a
`.pc` does, the load reports the path it found — and the linker-script note
above. `design/stage16-ergonomics/repl-libraries.md` §3.4's roster note names
the four vectors as deliberately outside `ReplState`.

**Gates.** `make test` **1079 passed, 0 failed, 0 skipped** (1072 + 7). `make
bootstrap`: `PASS: stage1.ll == stage2.ll`, `PASS: bootstrap complete` — no
boot refresh. `scripts/check-repl-roster.py`: clean (49 rows). `make
check-headers`: 87/87. Batch neutrality measured, not argued: no snapshot
baseline existed, so the implementing pass built a pre-change compiler from a
scratch copy with its hunks reversed, took the snapshot with it, and verified
with `build/nucleusc` — `checked 2780 artifact(s)  PASS: emitted output is
byte-identical`; the only `src/` edits after that were comment trims. The §9
end-to-end probe answers `41` in one flag-free session (`s21-repl-load-library`
is that probe); the GTK half is still the host's to run — with RC-0, `(gtk_init)`
now runs. Under `--repl-format=json` every new error is one JSON object
(`{"file":"<repl>","line":1,"message":"cflag: argument must be a string"}`).
