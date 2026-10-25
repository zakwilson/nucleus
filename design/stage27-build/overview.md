# Stage 27 — a build tool

**Status: designed, not built. Q1–Q6 and Q6f–Q6t ruled 2026-10-24 and
2026-10-25 (§7, §8.11). No questions are open.** §8 designs library
dependencies and configuration merging. Facts were checked against
`68eaee1`.

## 1. The brief

Building a Nucleus program outside this repository currently takes this
(the build comment at the top of `../charge.nuc/src/main.nuc`):

```
make -C ../nucleus
../nucleus/build/nucleusc \
    $(printf -- '--cflag=%s ' $(pkg-config --cflags gtk4)) \
    -I ../nucleus/lib src/main.nuc -o charge \
    $(pkg-config --libs gtk4)
```

**The goal:** in a simple project, `nucleus build`, `nucleus run` and
`nucleus run-repl` work in the project directory with no arguments and no
configuration file. A more complex project describes itself in `build.edn`.
The tool can find dependencies from the imports in the sources and write that
file for you.

**Out of scope:** fetching dependencies over the network.

## 2. Facts about Nucleus that decide the choice

These are what make this different from choosing a build system for C.

1. **A compile is the whole program.** Importing a `.nuc` file inlines it
   (`docs/compiler.md`, "Separate compilation and symbol linkage"). One
   `nucleusc` invocation reads the entry file's whole import closure and writes
   one object or binary. A typical project's build graph is one compile edge per
   executable, plus one per C source file if there are any, plus the link.
   Fine-grained graphs are where build backends differ most, and Nucleus doesn't
   produce them.
2. **Splitting a program into one object per file makes it worse.** `-c`
   works, but every object carries a `weak_odr` copy of every library it
   imports, prelude included. A `defvar` with a run-time initializer runs once
   *per object* (the `-c` warning in the same section of `docs/compiler.md`).
   So a backend that assumes "one source, one object, then link" (CMake, Meson,
   Make's implicit rules) has the wrong default for Nucleus.
3. **`run` and `run-repl` happen inside the compiler process.**
   `nucleusc --run` JIT-compiles and calls `main` with no link step. The REPL
   (`-i`) already has the whole build line as meta forms: `cflag`,
   `import-path`, `library-path`, `load-library` and `pkg-config`
   (`src/repl.nuc`, "The build line at the prompt";
   `design/stage21-cleanup/repl-build-line.md`). No external backend can start a
   REPL with a project's configuration applied. Whatever does that is ours.
4. **An uninstalled compiler can't find its own standard library.**
   `try-import-path` (`src/nucleusc.nuc:21412`) searches the source file's
   directory, then `lib/` under the working directory, then `-I`, then
   `$NUCLEUS_LIB`, then `/usr/local/share/nucleus/lib`. Nothing in that list is
   relative to the compiler's own executable. That is the only reason charge
   needs `-I ../nucleus/lib`.
5. **The compiler doesn't report what it read.** It has no depfile output.
   `--resolve` writes a `{:record :file …}` per Nucleus file it read, but it
   does a full compile to get there, and it says nothing about the C headers
   that the `clang -E` behind `(import-use "gtk/gtk.h")` reads.
6. **Compile-time code can read anything.** Macro and compile-time bodies are
   JIT-compiled and can call any C function. If one opens a file, no depfile
   the compiler writes will list it, unless the reading goes through a
   compiler-provided primitive that records it.
7. **We already have the pieces a frontend needs:** an EDN reader with
   `derive-edn` struct codecs (`lib/nucleus/edn.nuc`), process spawning
   (`lib/nucleus/process.nuc`), `--diagnostics=edn`, and pkg-config handling in
   the REPL.
8. **The stdlib `.nuch`/`.h` headers are generated** by `make lib-headers` /
   `make lib-cheaders` and are no longer committed. An installed or uninstalled
   toolchain has to have built them first.

## 3. What every option has in common: the frontend

The backend choice matters less than it first appears, because most of the
work is in a **frontend** that no third-party tool provides:

- **Project discovery.** Find the entry point by convention (`src/main.nuc`,
  or one `.nuc` with a `main`) and name the output after the directory.
- **Import discovery.** Scan the sources' import forms. A Nucleus import
  (`nucleus.vector`) resolves to the stdlib, the project, or a local path
  dependency declared in the config. A C header import (`"gtk/gtk.h"`) is mapped
  to a pkg-config package: list the packages (`pkg-config --list-all`), take
  each one's `--cflags-only-I` directories, and see which of them contain the
  header. Cache the result. The answer can be ambiguous: `gtk/gtk.h` is in both
  `gtk-3.0/` and `gtk-4.0/`. In that case `nucleus build` stops and says to
  run `nucleus init`, which asks, or writes both into `build.edn` with one
  commented out (Q4, §7). A purely textual scan misses imports produced by
  macro expansion. The fallback is to compile with `--diagnostics=edn`, read
  the unresolved-import diagnostic, resolve it, and retry.
- **Configuration.** Read the EDN file, merge it over the conventions, and turn
  the result into flag vectors: `--cflag=`, `-I`, `-L`, `-l`, `--link-arg=`,
  `-O`, `--target=`.
- **`run`/`run-repl`.** Hand those same vectors to `--run` or `-i`, which
  apply them in-process.

A backend only decides what happens between "here are the edges" and "the
outputs are up to date". The options below differ in how that part works and
in how much of the frontend they replace. None of them replaces all of it.

## 4. Options

### 4.1 Ninja as the backend

The frontend writes `build/build.ninja` and runs `ninja -C build`. Ninja is
small and fast, and it has an unusually careful correctness model. It records
each edge's full command line in `.ninja_log` and rebuilds when the command
changes, not only when inputs change. It reads gcc-format depfiles into
`.ninja_deps` (`deps = gcc`), so an import added to a source file is picked up
after one build without regenerating anything. `restat` stops rebuilds early
when an output didn't actually change. `dyndep` handles dependencies that are
only known at build time. A `generator = 1` edge regenerates `build.ninja`
itself when the EDN config changes. It runs edges in parallel, prints compact
progress, and `ninja -t compdb` and `-t graph` come free. Meson, CMake and GN
all use it as their backend, so it is often already installed and it is well
understood. Adopting it would mean we never write an executor, a staleness
check, or a job scheduler.

The costs are mostly a matter of fit. Because of §2.1, the graph Ninja would
schedule is usually one compile and maybe a link. Its speed and parallelism
earn nothing there, and what we would really be using is its bookkeeping: the
command hash and the depfile. To get even that, the compiler has to write a
depfile (§6, P2) that includes the C headers `clang -E` reads. That is the same
prerequisite a bespoke tool has. Ninja adds a runtime dependency to a toolchain
whose build currently needs only clang and LLVM. It isn't installed in this
container. `nucleus run` and `run-repl` can't go through it (§2.3): `run`
becomes "ninja, then exec", and `run-repl` skips Ninja entirely. That gives two
code paths that apply the same configuration and could drift apart. Errors come
from two layers, and Ninja's output wraps the compiler's diagnostics. Vendoring
a C implementation (samurai) into `nucleusc` would remove the install
dependency, but it would undo "the build compiles no C" (`context/build.md`)
for a tool we would only partly use.

### 4.2 Bespoke, top to bottom

`nucleus` reads the config, builds an in-memory graph, checks staleness, and
runs the compiler and linker itself. It is written in Nucleus using
`lib/nucleus/edn`, `process`, collections and `fmt`. The main advantage is
coherence. `build`, `run`, `run-repl` and `test` share one configuration path,
and `run`/`run-repl` call the in-process `--run` and `-i` entry points directly
(§2.3) instead of re-deriving flags. The pkg-config code in `src/repl.nuc`
becomes a library that both the REPL and the build tool use. Diagnostics stay
in the compiler's own format, including `--diagnostics=edn` for the Emacs mode.
The tool also knows things a generic backend can't. It can route compile-time
file reads (§2.6) through a recording primitive so they become dependencies.
It can tell when the stdlib headers (§2.8) need building. Later it could use
`.nuch` interfaces to compile only what changed, if Nucleus ever has real
separate compilation. It adds no dependencies, and the tool exercises EDN,
process and collections, which find bugs in them, as Stage 26's refactoring
tools did for the reader.

The cost is that we own the correctness. A naive mtime check gets several
things wrong: a changed flag with unchanged sources, a header that changed
under `/usr/include`, a compiler that was rebuilt, an output that was only
partly written, and mtimes too coarse to tell two edits apart. The fix is
Ninja's design at a smaller scale. For each output, keep a record of the
command line's hash, the compiler binary's identity, and the read set with
mtimes (falling back to content hashes). Write outputs to a temporary file
and rename them into place. Because of §2.1, the scheduler can be simple:
spawn the independent compile edges (one per executable and C file) in
parallel with `process`, then link. The risk is gradual growth. Each feature
Ninja already has (job limits, interrupting cleanly, a console pool for
`run`, a compilation database for editors) is tempting to add, and one at a
time they add up to a worse Ninja. That needs a written scope and an escape
hatch: §4.6 and §5.

### 4.3 Generated Makefiles

The frontend writes a GNU Makefile and runs `make`. Make is everywhere,
including this container (Ninja isn't). Users can read it and add their own
targets, and `make -j` gives parallelism. The repository's own build is a
Makefile, so it would also fit how we already work.

But Make is the weakest of these backends at the things that matter here. It
doesn't notice a changed command line without stamp-file tricks. A depfile has
to be pulled in with `-include`, and a deleted header breaks the next build
unless the depfile has phony targets for its prerequisites. It quotes paths
with spaces badly, and GNU and BSD make differ. A generated Makefile also
tempts people to edit it, and the next regeneration throws those edits away.
That is how automake ended up shipping unreadable output. Generating a
Makefile is still a reasonable *export* format ("give me something I can
include in my existing Make build"). As the backend `nucleus build` drives, it
gives us Ninja's dependency and none of Ninja's correctness.

### 4.4 CMake (with a Nucleus language module)

CMake allows a new language to be added from outside its source tree:
`CMakeDetermineNucleusCompiler.cmake`, `CMakeNucleusInformation.cmake` and a
test module on `CMAKE_MODULE_PATH`. In return we get a lot. `pkg_check_modules`
and imported targets handle C dependencies. Toolchain files handle
cross-compiling, which matters for the AVR and RISC-V targets. Install rules,
CPack, IDE generators and compile databases come with it, and it generates
Ninja or Make. It is also what C projects that might want to use a Nucleus
library already use.

It fails the brief, though. Even hello-world needs a `CMakeLists.txt`, so
"no configuration" would mean `nucleus` generating CMake input for CMake to
generate Ninja input: three layers. The configuration language is CMake's, not
EDN. CMake's model compiles each source to an object and then links, which is
exactly the shape §2.2 warns against. Making it compile each executable's
import closure as one unit means fighting how CMake wants to work.
`run-repl` gets nothing from it. CMake is also a heavy dependency. Its real
value for us is as **an export target later**: a `NucleusConfig.cmake` so a
CMake project can `find_package` a Nucleus library and its C header. That is a
separate interop item, not the build tool.

### 4.5 Meson

Meson's `dependency('gtk4')` is the best pkg-config integration of any of
these tools, and its configuration language is pleasant. But Meson
intentionally has no way to add a language from outside. Nucleus support would
mean a patch accepted upstream or `custom_target` wrappers, and wrappers throw
away the dependency knowledge that made Meson attractive. Its fixed, non-Turing
configuration language is also a poor match for a language that runs arbitrary
code at compile time. It has the same layering and REPL problems as CMake.

### 4.6 Other models worth taking from

- **Tup** finds dependencies by observing file accesses (FUSE or
  `LD_PRELOAD`), so it would catch compile-time file reads (§2.6) that no
  depfile reports. It needs FUSE, uses its own Tupfile language, and is
  uncommon. The idea is worth keeping: a bespoke tool can get the same result
  by having the compiler record file reads.
- **Bazel / Buck2** offer hermetic builds and remote caching, and Starlark
  rules for a new language are an established pattern (`rules_rust`,
  `rules_zig`). They are far too heavy for a bare `nucleus build`, and they
  want every input declared, which is the opposite of discovery.
- **Zig's `build.zig` / Cargo's conventions** aren't backends. They show the
  two ends of the configuration spectrum. Cargo's convention over
  configuration is the zero-config case in the brief. Zig's build script,
  written in the language itself, is the obvious escape hatch for builds EDN
  can't express. Nucleus could run a `build.nuc` with `--run`, and compile-time
  evaluation means it would cost nothing extra to support.

## 5. Recommendation

*Adopted by Q2 (§7).*

**A bespoke frontend and a minimal bespoke executor, with a Ninja *emitter*
kept as an option.** The frontend has to be ours whichever backend we pick
(§3), and it is most of the work. The executor's graph is one or a few edges
(§2.1). Ninja's real advantage is its correctness bookkeeping, which is small
enough to copy (§4.2), and depending on Ninja would split `run`/`run-repl` from
`build`. If the internal graph is built from Ninja's concepts (rules, edges,
gcc-format dependency records, a command hash per edge), then
`nucleus build --emit-ninja` can be added later. That covers projects with many
C sources, and fitting into someone else's build. It also covers the day
Nucleus has real separate compilation and the graph gets large enough for
Ninja to matter. Make and CMake output are later export targets, not
backends.

## 6. Prerequisites, whichever backend

- **P1. Find the stdlib relative to the compiler.** Add `<exe>/../lib` (a
  checkout's `build/nucleusc`) and `<exe>/../share/nucleus/lib` (an install) to
  `try-import-path`, read from `/proc/self/exe`. That alone removes
  `-I ../nucleus/lib` from charge's command line.
- **P2. A depfile.** `--depfile=<path>` writes a gcc-format file covering
  every `.nuc`/`.nuch` read and every header the C preprocessor read (by
  passing `-MD -MF` to the `clang -E` behind header imports). Ninja, Make and a
  bespoke tool all use it.
- **P3. Recorded compile-time reads.** A file-reading primitive for
  compile-time code that also adds the file to the depfile (§2.6). Direct calls
  to `fopen` stay invisible. The documentation should say so.
- **P4. pkg-config as a library.** Move the logic behind the REPL's
  `pkg-config` meta form out of `src/repl.nuc`, so the build tool and the REPL
  split the output into the same flag vectors.
- **P5. An import scan.** A cheap mode that reads a unit and prints its import
  forms as EDN without compiling. The `--diagnostics=edn` retry loop in §3
  covers imports that macros generate.

## 7. Questions and rulings

- **Q1. One binary or two?** *Ruled 2026-10-24: one binary for now.* `nucleus`
  is a mode of `nucleusc`, so it shares the in-process `--run`/`-i` paths.
  Revisit this once more of the compiler has moved into libraries, because a
  separate `nucleus` that links those libraries would then cost little.
- **Q2. Backend.** *Ruled 2026-10-24: bespoke now.* Build the internal graph
  (rules, edges, dependency records, command hashes) so that it could be
  written out as another backend's build file. No emitter is planned yet.
- **Q3. Config file name.** *Ruled 2026-10-24: `build.edn`*, at the project
  root.
- **Q4. When discovery writes the file.** *Ruled 2026-10-24.* Builds never
  write `build.edn`. When zero-config can't decide something (an ambiguous C
  header, a library it can't find) and there is no `build.edn`, `nucleus build`
  stops and tells the user to run `nucleus init`. Only `nucleus init` writes
  the file.
- **Q5. The escape hatch.** *Ruled 2026-10-24: deferred until something needs
  it.* If `build.edn` starts growing conditionals, variables or anything else
  that edges toward Turing completeness, that is the sign something needs it.
  At that point, add a real escape hatch (such as a `build.nuc` run through
  `--run`) instead of making EDN more expressive.
- **Q6. Other Nucleus libraries.** *Ruled 2026-10-24, in part; §8 is the
  design that follows.* Look for libraries in several places, including where
  C libraries live, and prefer `.nuch` to `.h`. Read a per-user registry from a
  default path or from one given on the command line. Sibling checkouts are
  local overrides in `build-local.edn`, written by `nucleus init-local`, and
  `nucleus init` discourages committing local paths. Prebuilt dependencies are
  designed now, and `nucleus install` is built in this stage. Two dependencies
  providing the same top-level name is an error. A C-choice conflict is an
  error; §8.8 lists the other options that were asked for. The compiler,
  the header format and the build process may all change if that helps the
  build tool. Q6f–Q6t were ruled afterwards (§8.11).

## 8. Libraries: describing, finding and consuming them

The Q6 ruling allows changing the compiler, the `.nuch` format and the build
process. This section uses that.

### 8.1 What a library is today

A Nucleus library has no manifest. It is a **search root**, a directory under
which dotted namespace names are directories. `(import-use gtkw.widgets)`
finds `<root>/gtkw/widgets.nuc`, or `.nuch`
(`design/stage23-namespaces/ambient-namespaces.md` §8,
`import-name-relpath` at `src/nucleusc.nuc:21459`). `resolve-import` tries
`.nuc` on every root before `.nuch` on any. Within each pass, roots are
searched in `try-import-path`'s fixed order (§2.4), and **the first match wins
without a diagnostic**. Link names come from the namespace, so two libraries
that both use `gtkw.*` conflict at link time as well as at import time.

I tried consuming a small library (`mylib.core`, which imports `zlib.h` and
names `z_stream` in a signature) in this container on 2026-10-24. That showed
four gaps:

1. **A `.nuch` doesn't carry its C header imports.** The header was
   `(ns mylib.core)` followed by `(declare zs-avail ((s (ptr z_stream))) :i32)`.
   A consumer that imports only the header fails with
   `mylib/core.nuch:3: error: unknown type: z_stream`. It has to know, from
   somewhere else, to import `zlib.h` itself. `emit-nuch-import-env`
   (`src/nuch.nuc:213`) carries only Nucleus imports, because
   `import-form-path` doesn't answer for a `.h` string.
2. **Link requirements aren't recorded anywhere, even in source mode.**
   Compiling the consumer against the library's *source* still failed at the
   link with `undefined reference to 'zlibVersion'`. `(import-use "zlib.h")`
   says which header to read, not which library to link, and the user has to
   supply `-lz`.
3. **A header-only library's macros can't call the library.** A `defmacro`
   that calls the library's own `twice-of` at expansion time works from
   source. From `.nuch` plus `.o` it fails with
   `JIT session error: Symbols not found: [ mac.m__twice-of ]`, because the JIT
   resolves against the compiler process and the object isn't loaded there.
   The same header's carried `(import-use nucleus.node)` also loads nothing
   (`docs/compiler.md`, "The imports a header carries"). So the macro body's
   `node-int` was unknown until the consumer imported `nucleus.node` itself.
4. **A bare entry file name loses the source-directory search.**
   `nucleusc app.nuc` couldn't find `mylib.core` in `./mylib/`, but
   `nucleusc ./app.nuc` could. The source directory of `app.nuc` is empty, and
   `try-import-path` skips an empty directory instead of treating it as `.`.

And one thing that is better than expected: `-c` over a unit importing fifteen
stdlib libraries (allocator through file) prints no run-time-initializer
warning. So the stdlib copies in a prebuilt library's object don't rerun
initializers (§2.2).

Two facts about the project's own sources matter as well:

- An import is looked for first in **the importing file's own directory**.
  That works for the entry file but fails one level down:
  `src/charge/ui.nuc` importing `charge.model` looks for
  `src/charge/charge/model.nuc`. The build tool always puts the project's
  source roots on the search path.
- **Transitive reliance is user error** (Stage 23 ruling). That is about which
  names a *file* may use. It doesn't excuse a header that can't be read
  without help (gaps 1 and 3), which is the header's own problem.

### 8.2 What a library contributes

Every library has a **name** (its identity for overrides and conflicts), a
**version**, and the **roots** it provides (its top-level namespace
directories). Beyond those, it contributes:

1. **Its interface**: `.nuch` files, `.h` files for C consumers, and possibly
   its source.
2. **Its C requirements**: the headers it reads, and the pkg-config packages
   or plain libraries it links.
3. **Its Nucleus dependencies**, by name.
4. **For prebuilt use**: its object (`libNAME.a`, optionally `.so`) and what
   that object was built with (compiler, header format, target).

Overrides and conflicts are keyed by name; collisions are checked by root.
Two libraries in the resolved set that provide the same root are an error
(ruled), and so is any library other than the stdlib providing `nucleus`. An
override *replaces* a library of the same name, so it isn't a second
provider.

### 8.3 Making `.nuch` self-describing

Proposed changes to the header format. Each fixes a gap from §8.1.

- **H1. Carry C header imports.** `(import-use "zlib.h")` and its siblings are
  written into the header and *load* when it is imported. Fixes gap 1. This
  means a consumer of a prebuilt library also needs that library's `--cflag`s,
  which is why H2 travels with it.
- **H2. Carry C requirements.** `(c-requires {:pkg-config [["zlib"]] :libs []})`
  next to the header's imports. It lists the requirement sets (§8.8) its C
  imports were resolved against, and any plain libraries (`m`, `dl`) that have
  no `.pc` file. Fixes gap 2 for prebuilt use. A consumer can then read any one
  header and know what to apply.
- **H3. Name the library.** `(library gtkw "0.3.0" :build-id "…")` on the
  header's first line. It points at the manifest (§8.4), tells a generated
  `.nuch` from a hand-written one, and carries the header-format version.
- **H4. Load what macros need at compile time.** A header that exports a
  macro carries the imports the macro body reads as loading, compile-time-only
  imports (`require-ct` semantics). The library code the macro calls is
  compiled from the installed source (ruled, §8.7). Fixes gap 3.

The information for H2 has to reach the compiler somehow. Today the build
line splices `$(pkg-config …)` into flags, and the compiler never sees a
package name. Add **`--pkg-config=<pkg>`** and **`--link-lib=<name>`** to
`nucleusc`. These are the batch-mode forms of the REPL's `pkg-config` and
`load-library` meta forms: the compiler applies the cflags and libs itself and
records them in the headers it writes. That also deletes the
`printf -- '--cflag=%s '` idiom from every build line, including charge's.

### 8.3.1 Declaring C needs in `.nuc` source: for, against, alternatives

The question is whether a `.nuc` file may say, in source, which pkg-config
package or plain library a C import comes from. Today only the build line
says that.

**For:**

- **Locality.** The file that imports `gtk/gtk.h` is the one that knows it was
  written against GTK 4. The choice sits beside the import that needs it, not
  in a separate file that can drift away from it.
- **Fewer build files.** Most of what makes `build.edn` necessary for a single
  program is resolving an ambiguous C header or naming a library without a
  `.pc` file. If the source settles those, `nucleus build` stays zero-config
  for many more projects.
- **The file is self-contained.** A file copied into another project, run with
  `nucleusc --run`, or pasted into the REPL still knows what to link. The REPL
  already accepts `(pkg-config …)` as a meta form, so the language would gain
  one spelling for both instead of a REPL-only one.
- **Headers get it for free.** H2 can be written from what the source
  declared, without the build tool passing flags in.
- **Precedent.** MSVC's `#pragma comment(lib, …)`, Rust's
  `#[link(name = …)]`, D's `pragma(lib, …)` and Clang module maps' `link`
  declarations all put this in source, and it's broadly considered convenient.

**Against:**

- **Platforms differ, and the differences end up in source.** Package and
  library names vary by OS and distribution: `-ldl` is needed on older glibc,
  not on musl or newer glibc, and not on Windows. `libjpeg` vs
  `libjpeg-turbo`. A source-level form either can't express that or grows
  conditionals, which is the Turing-completeness creep the Q5 ruling warns
  about, moved into `.nuc` files where no build file can override it.
- **A consumer can't edit a dependency's source.** A directive in a library's
  `.nuc` is a fixed fact for everyone downstream. It becomes overridable only
  if it is a requirement *set* that a build file can narrow (§8.8). At that
  point it's a default, not a directive.
- **The same need gets stated more than once.** Every file importing
  `gtk/gtk.h` either repeats the declaration, and the copies can contradict
  each other, or relies on one file's declaration covering the rest. The
  second is transitive reliance by another name.
- **Cross-compiling.** For a `--target` build, pkg-config has to run against
  the target's sysroot (`PKG_CONFIG_SYSROOT_DIR`, `PKG_CONFIG_LIBDIR`). The
  build tool knows the target. A source form can only work if it delegates to
  the build tool anyway.
- **Scanning can't see all of them.** A form produced by a macro is invisible
  to the import scan in §3, the same problem generated imports have.

**Alternatives:**

- **A. Build files only.** Requirements live in `build.edn`, a library's own
  `build.edn` included. They reach headers through `--pkg-config` and
  `--link-lib` (§8.3). Overrides and platform choices stay in files built for
  them. The cost is a `build.edn` wherever a header is ambiguous, and `init`
  writes that.
- **B. Requirement-set annotations on the import.**
  `(import-use "gtk/gtk.h" :pkg-config ["gtk4"])`. This is not a link
  directive. It is a statement about where the header comes from, and it
  enters resolution (§8.8) as one more set, so build files can narrow it and a
  conflict is an early error like any other. It keeps the locality and the
  zero-config gain. The repetition problem shrinks, because annotations on
  different imports of the same header are simply intersected. It still can't
  express platform conditionals, and it shouldn't.
- **C. A header→package table outside the project.** A built-in table for
  system libraries with no `.pc` file (`math.h` → `m`, `dlfcn.h` → `dl` where
  needed, `pthread.h`), plus an optional user file beside the registry
  (`~/.config/nucleus/c-packages.edn`). This covers the platform-specific
  cases that neither A nor B should handle in source. It complements A and B
  rather than replacing them.
- **D. Free-standing source directives** (`(pkg-config "gtk4")`,
  `(link-lib "m")` at top level, as the REPL has them). Has every argument
  for, and every argument against at full strength.

**Ruled 2026-10-24: B + C on top of A (Q6f).** The import annotation gives
the locality and keeps simple projects zero-config, and it answers most of the
concerns because it's a set that resolution intersects, not a directive. The
table handles system libraries and platform differences. Build files remain
where overrides and anything conditional live. D stays a REPL meta form only.
The annotation is the `(import-use "gtk/gtk.h" :pkg-config ["gtk4"])` form
above, and plain libraries take `:libs ["m"]`. The table ships with the
compiler, and `~/.config/nucleus/c-packages.edn` extends it.

### 8.4 `nucleus install` and the installed layout

`nucleus install` is built in this stage (ruled). Run in a library project,
it builds the library and installs it under a prefix: `/usr/local` by default,
`~/.local` with `--user`, `--prefix=<dir>` otherwise, with `DESTDIR` honored
for packagers. `--target=<triple>` installs a build for another target. The
layout follows C conventions, using Debian's multiarch layout for anything
target-specific. So the library sits where C libraries do, and a C consumer
can use it with no Nucleus tooling:

```
$PREFIX/include/<triple>/gtkw/widgets.nuch   one .nuch and one .h per public
$PREFIX/include/<triple>/gtkw/widgets.h      namespace file
$PREFIX/lib/<triple>/libgtkw.a               plus libgtkw.so when :shared
$PREFIX/lib/<triple>/pkgconfig/gtkw.pc       Requires: gtk4 >= 4.10; Libs: -lgtkw
$PREFIX/lib/<triple>/nucleus/gtkw.edn        the manifest
$PREFIX/share/nucleus/src/gtkw/…             the source: one copy, any target
```

**Installs are per target (ruled).** Headers go under the triple as well as
objects, because a `.nuch` isn't target-neutral. It writes the *folded value*
of C constants in array extents (`nuch-extent-values`, `src/nuch.nuc:244`),
and the C headers it carries (H1) can differ by target. A shared or universal
header option is deferred. **The source is installed by default.** It is
what consumers compile against (Q6s, §8.7), and it's where compile-time code
comes from (ruled, §8.7). `nucleus install --no-source` installs without it,
for a library distributed only in binary form. Such a library can't export
macros that call its own code, and `install` refuses one that does.

The `.pc` file means `pkg-config --cflags --libs gtkw` works for C projects,
and its `Requires:` carries transitive C dependencies, so we don't build a
second mechanism for that. A cross build points pkg-config at
`$PREFIX/lib/<triple>/pkgconfig` with `PKG_CONFIG_LIBDIR` and sets the
sysroot. The manifest is the Nucleus-specific half, written with the
`lib/nucleus/edn` codecs:

```
{:name gtkw :version "0.3.0" :provides [gtkw]
 :build-id "…" :compiler "…" :header-format 1 :target "x86_64-pc-linux-gnu"
 :requires {:nucleus [] :pkg-config [["gtk4 >= 4.10"]] :libs []}
 :objects {:static "libgtkw.a" :shared nil}
 :files [ … every installed path, for nucleus uninstall … ]}
```

Building a library for install turns the `-c` run-time-initializer warning
(§2.2) into an error. An installed object is always linked beside others, so
the warning's single-object-with-C exception never applies.

**The stdlib is installed through `nucleus install` (ruled),** as the library
`nucleus`: `libnucleus.a`, `include/<triple>/nucleus/*.nuch|.h`, `nucleus.pc`,
a manifest, and its source in `share/nucleus/src/nucleus/`. This replaces the
lib half of `make install`, which today copies sources and headers to
`$PREFIX/share/nucleus/lib`. `make install` keeps installing the compiler
binary and then runs `build/nucleusc install` in `lib/`. Things that move with
it:

- `try-import-path`'s fallback `/usr/local/share/nucleus/lib/` and
  `$NUCLEUS_LIB` become the lookup of §8.5. P1, finding the stdlib relative to
  the executable, covers an uninstalled checkout.
- The compile-time library root is captured from wherever `nucleus/core.nuc`
  was found (`ct-lib-root-note`, `src/nucleusc.nuc:21483`). It has to point at
  the installed *source* directory, because compile-time code comes from
  source.
- The stdlib already has the property every other installed library needs to
  have: its compile-time code is part of the compiler process (the
  `-rdynamic` roster), and §8.1 found no run-time initializers in it.

**Programs keep inlining the stdlib from source (ruled 2026-10-24, Q6p,
reversing an earlier ruling the same day).** Linking `libnucleus.a` by default
had three costs. The import path and the compile-time root had to separate
just for the stdlib. `make` had to build an archive per target. Optimized
builds lost LLVM's inlining of the stdlib's `weak_odr` non-template
functions, which would then need LTO to win back. Compiling is fast and the
stdlib source is small, so none of that buys anything. `libnucleus.a` is
still installed, for C consumers and for anyone who opts in, but no Nucleus
build links it unless asked.

### 8.5 Finding a library

For an import whose root the project doesn't provide, the tool looks in these
places in order. Each place answers by library name. The first place that has
the library wins, and the others are not consulted for it. Every place that
holds builds looks only at the build's target triple.

1. **`build-local.edn` overrides** (§8.6).
2. **`build.edn` `:deps`**: by name with an optional version constraint, or by
   a path *inside* the project (a vendored `vendor/gtkw` is fine).
3. **The user registry.** `$XDG_CONFIG_HOME/nucleus/library-paths.edn` (by
   default `~/.config/nucleus/library-paths.edn`), plus each
   `--library-paths=<file>`, which **add** to it (ruled). Entries from later
   files win for the same name. To leave out the default file, use
   `--no-user-registry` on the command line or `:user-registry false` in
   `build-local.edn` (ruled). The second fits a CI checkout or a build that
   has to be reproducible.
   ```
   {:libraries {gtkw "~/src/gtkw"}       ; name → project directory
    :search ["~/src/nucleus-libs"]}      ; directories of library projects
   ```
4. **Installed libraries**, in the places C libraries live:
   - manifests under `~/.local/lib/<triple>/nucleus/`,
     `/usr/local/lib/<triple>/nucleus/` and `/usr/lib/<triple>/nucleus/`;
   - then pkg-config, using `PKG_CONFIG_PATH` and its default path, for a
     `.pc` that names a Nucleus manifest;
   - then include directories (`~/.local/include/<triple>`,
     `/usr/local/include/<triple>`, `/usr/include/<triple>`, then the same
     without the triple) for `<root>/<file>.nuch` or, failing that, `.h`.

   `.nuch` comes first because Nucleus generates both, and the native header
   carries generics, macros, protocols and the H1–H4 information that a C
   header can't (ruled). A `.h`-only hit is used as a plain C library.
5. **The stdlib**, installed like any other library (§8.4), or found
   relative to the executable in a checkout (P1).

The `.nuch`-first rule applies only to finding a *library by name*. **An
import that names a C header explicitly (`(import-use "gtkw/widgets.h")`)
reads that header, even if a `.nuch` sits beside it (ruled).**

Libraries found in places 3–5 are used without any configuration, which keeps
zero-config working. When nothing provides the root, the build stops and tells
the user to run `nucleus init` (Q4). Whenever a library resolves from
`build-local.edn` or the registry, the build prints one line naming where it
came from. Those are the two sources that live outside the repository, so
this is how "works on my machine" gets noticed.

### 8.6 `build-local.edn` and `nucleus init-local`

`build-local.edn` holds per-checkout settings, merged over `build.edn` (§8.9):

```
{:deps {gtkw {:path "../gtkw"}
        cairo-nuc {:version ">= 1.4"}}       ; narrows
 :pkg-config {"gtk/gtk.h" {:unsafe/pkg-config ["gtk4 >= 4.8"]}}  ; widens
 :user-registry false}
```

**Narrowing is the default; widening takes an `unsafe/` key (ruled, Q6q).**
A constraint in `build-local.edn` intersects with everything else, so a local
file can't accept something the project rejected. Sometimes that is too
strict. A distribution may ship gtk 4.8 when the project asks for 4.10, and
the user knows the code doesn't use anything newer. The same key with an
`unsafe/` prefix (`:unsafe/version`, `:unsafe/pkg-config`) *replaces* the
merged constraint for that slot instead of intersecting with it. This
matches the language's existing `unsafe/` spellings (`unsafe/cast`,
`unsafe/import-private`): the escape exists and is easy to grep for. Every
build where one is in effect prints a warning naming it and the file that
set it. **`unsafe/` keys are allowed in every configuration file (ruled,
Q6t):** `build-local.edn`, `build.edn`, and a dependency's own `build.edn`. A
dependency's keys warn in its consumers' builds too, so a library that ships
one is visible to everyone downstream. That is the deterrent, and it's
enforced socially rather than by the tool. A widened
requirement can't apply to a prebuilt dependency compiled against something
else. A dependency the project opted into prebuilt is compiled from source
instead, with a note. One with no source is an error.

It overrides whatever the user registry or system installs would supply, so
a sibling checkout can be used even when user-level and system-level installs
of the same library exist. It's also where a user narrows constraints for one
build, in place of a lock file (ruled: no lock file). It should never be
committed. **`nucleus init-local`** writes it. For each dependency, it looks
for a sibling project (`../*/build.edn` whose `:name` matches) and writes a
path override for every match, listing them. In a git repository it also adds
`build-local.edn` to `.gitignore` and says so.

**`nucleus init`** discourages local paths. It never writes a path outside
the project into `build.edn`. A dependency it could only find as a sibling
goes in by name, with a pointer to `init-local`. A hand-edited `build.edn`
path that leaves the project gets a warning at every build:
`paths outside the project belong in build-local.edn`.

### 8.7 Consuming a prebuilt library

- **Choosing: source when available (ruled 2026-10-25, Q6s).** A library is
  compiled from its installed source, inlined like the stdlib (Q6p), unless
  it has no source (`--no-source`, §8.4) or the project asks for prebuilt
  (`:deps {gtkw {:prebuilt true}}`). Prebuilt needs an install for the build's
  target whose manifest `:compiler` and `:header-format` match. A mismatch
  falls back to source when there is source, and otherwise is an error naming
  the mismatch. That makes cross-module inlining, and the LTO needed to
  recover it, a concern only for the opt-in and source-less cases. It is not
  addressed in this stage.
- **Compile time: from source (ruled).** A macro in the library may call the
  library's own functions while it expands (gap 3), and that code runs in the
  compiler process on the host, whatever the target. The compiler compiles
  what's needed from the installed source into the JIT, the way `import-ct`
  already handles a library's compile-time surface: it registers it and emits
  none of its definitions. That needs nothing new installed, works for every
  target, and costs compile time only for a library whose header exports
  macros. H4 makes the header say so. The stdlib is the exception, because its
  compile-time code is already in the compiler process.
- **Initializers.** The library's own `defvar`s are defined in its object and
  declared in its headers, so they initialize once. The stdlib copies inside
  the object have no run-time initializers (§8.1), and installing makes the
  warning an error (§8.4). So prebuilt use doesn't bring §2.2's problem back.
- **Templates** are exported verbatim and monomorphized in the consumer as
  `weak_odr`. Instances the library's object also contains merge at the link.
- **Static by default.** A program links `libNAME.a` and stays one binary.
  The shared object is optional.

### 8.8 C requirements as sets

**Ruled: requirement sets, resolved automatically where a resolution exists.
If none fits, the build fails early, before any compile.** I looked for a
strong case against sets and didn't find one. The one real cost is below,
along with how the resolution rules contain it.

**The model.** A *requirement* names one C dependency slot (the package a
given header comes from, such as `gtk/gtk.h`) and gives an ordered set of
acceptable alternatives, each a pkg-config package with an optional version
constraint: `["gtk4 >= 4.10" "gtk3 >= 3.24"]`. Requirements come from:
- the project's `build.edn` and `build-local.edn`;
- each dependency's manifest or `build.edn`;
- `.nuch` H2 records;
- import annotations, if §8.3.1's B is adopted.

A prebuilt dependency contributes the one alternative it was compiled against.

**Resolution.**
1. Intersect every requirement on a slot.
2. Drop alternatives that aren't installed for the target.
3. Pick the first remaining alternative in the order the **root project**
   listed it. If the root didn't constrain the slot, use the order of the
   dependency nearest the root, with ties broken by name, never by search
   order.
4. Check the picked packages' own pkg-config `Requires:` against the other
   slots. If that eliminates a pick, try the next alternative.

The search is small and deterministic: the same requirements and the same
installed packages always give the same result. If nothing fits, the error
lists every requirement on the slot and where it came from (§8.9 keeps that
provenance):

```
error: no C package satisfies 'gtk/gtk.h' for x86_64-pc-linux-gnu
  build.edn:4           requires ["gtk3 >= 3.24"]
  ../gtkw/build.edn:6   requires ["gtk4 >= 4.10"]
```

**The cost.** The result depends on what's installed. If a library accepts
gtk3 or gtk4 and the project doesn't care, a machine with only gtk3 builds
against gtk3, and one with both builds against gtk4. That's deterministic,
but it can surprise. Three things contain it. First, ordering comes only from
declarations, never from the filesystem. Second, whenever a pick wasn't the
first alternative of every requirement on its slot, the build prints the
choice and the reason (`gtk/gtk.h → gtk3 (gtk4 not installed)`). Third,
`build-local.edn` can narrow the slot to pin it. That doesn't amount to a
case against sets. The alternative is rejecting a build that a valid
resolution exists for.

### 8.9 Merging the configuration

The live configuration is assembled from several EDN files: `build.edn`,
`build-local.edn`, the user registry files, and each dependency's
`build.edn` or manifest. "Deep-merge the maps" is close, but a uniform deep
merge is wrong in one important place. Requirement sets and version
constraints from `build-local.edn` have to **narrow**, which means
intersecting them, not unioning them or letting the later one replace the
earlier. So the merge has to know what each key means:

| Kind of value | Merge | Examples |
|---|---|---|
| Map | recursive, key by key | `:deps`, `:deps gtkw` |
| Scalar | later file wins | `:main`, `:path`, `:user-registry`, `:opt` |
| Requirement set / version constraint | intersect | `:pkg-config`, `:version` |
| The same under `unsafe/` | replace, with a warning | `:unsafe/pkg-config`, `:unsafe/version` |
| Vector of flags | append (ruled) | `:cflags`, `:link-args` |
| Set of names | union | `:libs` |

The approach (ruled: typed, unless that causes problems) is to **decode each
file into the typed configuration struct first** (`derive-edn`, Stage 22 ED-4), with each value tagged by the
file:line it came from, and **then merge field by field**. Decoding each file
first catches a misspelled key in the file that has it. It also keeps
provenance for errors like §8.8's, which a merge at the level of raw `Node`
trees would lose. And it puts each merge policy on the struct field it
applies to, rather than in a table of key paths.

That needs library support that doesn't exist yet. `Assoc`
(`lib/nucleus/coll.nuc:95`) has `assoc`/`dissoc`/`get`/`keys`/`vals`, and no
merge. `Set` already has in-place `union`/`intersection`, which covers the set
rows. Proposed additions to `nucleus.coll`, in the same in-place style as
`Set`:

- **`(merge self:&M other:&M)`**: assoc every entry of `other` into `self`,
  with the later value winning. A replaced value is dropped when `V` conforms
  to `Drop`.
- **`(merge-with self:&M other:&M f:&F)` `:where ((BinaryFn V V) F)`**: on a
  key in both, store `(apply2 f old new)`. `f` takes both values and owns the
  result. `BinaryFn` (`lib/nucleus/combinators.nuc:46`) already has exactly
  the same-typed-arguments shape.

Both would be standalone generics over `Assoc` plus `Coll (Entry K V)`, so
every map gets them without a protocol change. This follows the same
reasoning that kept `select-keys` standalone (`coll.nuc:92`). A `HashMap`
overload can outrank the generic if iteration through `Assoc` turns out to be
slow. A recursive deep merge isn't a general collection function, because a
typed `HashMap`'s values aren't themselves maps. It belongs to the
configuration struct's own merge, which calls `merge-with` for its map
fields. An untyped `edn-merge-with` over `Node` maps is only needed if some
part of the config has to stay untyped. That is the "unless it causes
problems" case of the ruling, and it's not planned.

### 8.10 Prerequisites added by this section

- **P6.** Treat an empty source directory as `.` in `try-import-path` (gap 4).
- **P7.** `--pkg-config=<pkg>` and `--link-lib=<name>` in `nucleusc`, recorded
  in the headers it writes (§8.3).
- **P8.** Header format H1–H4, with a header-format version in H3.
- **P9.** `merge` and `merge-with` in `nucleus.coll` (§8.9).
- **P10.** The stdlib becomes an installable library: per-target install,
  installed source as the compile-time root, `make install` delegating
  (§8.4).
- **P11.** *Needed only for prebuilt use, which is now the opt-in case
  (Q6s).* A compile-time source root separate from the import path, so a
  prebuilt library can be imported from `.nuch` and linked while its macros'
  callees compile from its installed source (§8.7). `resolve-import` prefers
  `.nuc` on any root over `.nuch` on any root, so with the source directory
  on the import path the library would be inlined instead.
- **P12.** Requirement-set annotations on C header imports
  (`:pkg-config`, `:libs`), and the shipped header→package table with its
  user extension file (§8.3.1).

### 8.11 Sub-questions and rulings

Ruled 2026-10-24:

- **Q6g.** An explicit C header import is never swapped for a `.nuch`.
- **Q6h.** Compile-time code from prebuilt libraries is compiled from the
  installed source.
- **Q6i.** `--library-paths` adds. Skip the default registry with
  `--no-user-registry` or `:user-registry false` in `build-local.edn`.
- **Q6j.** Per-target installs. A shared or universal option is deferred.
- **Q6k.** Requirement sets, resolved before any conflict error. An early
  error if no resolution fits.
- **Q6l.** The stdlib is installed through `nucleus install`.
- **Q6m.** No lock file. `build-local.edn` narrows constraints for a
  particular build.

- **Q6f.** Import annotations (B) and a header→package table (C), on top of
  build files (A). Free-standing directives (D) only in the REPL.
- **Q6n.** `--no-user-registry` / `:user-registry false`.
- **Q6o.** Vector-valued settings such as `:cflags` append.
- **Q6p.** Programs inline the stdlib from source. `libnucleus.a` is
  installed but not linked by default. (Reversed the same day from "link by
  default", because of its costs.)
- **Q6q.** `build-local.edn` narrows by default. `unsafe/`-prefixed keys
  widen, with a warning on every build.
- **Q6t.** `unsafe/` keys are allowed in every configuration file, a
  dependency's included, and always warn. No restriction.
- **Q6r.** The configuration is typed, unless that causes problems.

- **Q6s.** *(2026-10-25)* Third-party libraries default to their installed
  source when it's available. Prebuilt is used when there is no source, or
  when the project sets `:prebuilt true`.

No questions are open.
