# The build tool and its libraries

`nucleus` builds a project: it reads `build.edn`, works out what each step
reads, and reruns only the steps whose inputs changed. It is the compiler under
another name. `main` looks at `argv[0]`, and a program called `nucleus` runs the
tool, so `build/nucleus` and `$PREFIX/bin/nucleus` are symlinks to `nucleusc`.
Every `nucleusc` invocation keeps its meaning.

The libraries under `lib/nucleus/build/` hold the tool's logic and what it
shares with the compiler's C requirements and the REPL's `pkg-config` meta
form. The design is in `design/stage27-build/`.

## Commands

```
nucleus build     [-j N] [-O0..-O3] [--target=TRIPLE]
nucleus run       [same options] [-- ARGS...]
nucleus run-repl  [same options] [--repl-format=text|json] [-- ARGS...]
nucleus repl      [same options] [--repl-format=text|json]
nucleus clean
nucleus init
nucleus init-local
nucleus install   [--prefix=DIR | --user] [--no-source] [--target=TRIPLE]
nucleus uninstall [NAME] [--prefix=DIR | --user] [--target=TRIPLE]
```

Every command also takes `--library-paths=FILE` (repeatable) and
`--no-user-registry` (see [Dependencies](#dependencies)), and
`--diagnostics=text|edn`.

With `--diagnostics=edn`, every compile the command runs writes its
diagnostics as EDN maps ([Structured diagnostics](compiler.md#structured-diagnostics)).
The tool's own errors, warnings and notes use the same maps. A `build.edn`
error, for example, gives its `:file` and `:line`. Progress lines such as
`nucleus: building …` stay text, so a reader picks out the diagnostics as the
lines that start with `{:severity`. The flag doesn't count as a change to a
step's command, so switching it rebuilds nothing.

| Command | What it does |
|---------|--------------|
| `build` | Brings `build/<name>` up to date, or for a library its headers, objects and archive (see [Library projects](#library-projects)). Prints `nucleus: building <output> (<reason>)` for each step it runs, or `nucleus: <name> is up to date`. |
| `run` | Compiles and runs the program in this process (`nucleusc --run`), passing what follows `--`. Its exit status is the program's. A project with `:c-sources` is built and the binary run instead, because a C object can't join a JIT session. |
| `run-repl` | Runs the program with a REPL beside it: `nucleusc -i ENTRY -- ARGS` with the project's flags. `main` runs on its own thread, and the prompt starts in the entry file's namespace. The prompt can read and set the program's globals and redefine its functions while it runs. At the end of input it waits for `main` and exits with its status. Like `repl`, it refuses a project with `:c-sources`, whose objects can't join a JIT session. See [Running a program at the prompt](compiler.md#running-a-program-at-the-prompt). |
| `repl` | Starts `nucleusc -i` with the project's flags, and imports and runs nothing. The REPL applies the C requirements of the entry file's import closure, as a build would, and loads their libraries. Import a header or one of the project's files at the prompt. Both `repl` and `run-repl` pass `--repl-format=` to the compiler, so `--repl-format=json` gives one JSON object per REPL error, as `nucleusc -i` does. |
| `init` | Writes `build.edn`, recording each choice the conventions couldn't make (see [Choosing C packages](#choosing-c-packages)). Refused if a `build.edn` already exists. |
| `init-local` | Writes `build-local.edn`, pointing each library the project needs at a sibling checkout that provides it (see [`nucleus init-local`](#nucleus-init-local)). |
| `clean` | Removes what the tool wrote: the outputs, their temporaries and depfiles, the log, then every directory under `build/` that this leaves empty, and `build/` itself. |
| `install` | Builds a library and installs it (see [Installing a library](#installing-a-library)). |
| `uninstall` | Removes an installed library: this project's, or `NAME`'s. |

`-j N` (or `-jN`) caps the steps run at once. The default is the number of
online processors. `-O` and `--target=` override `:opt` and `:target`.

The project root is the nearest directory at or above the current one that has
a `build.edn`. Without one anywhere, the current directory is the project, with
no configuration.

## Conventions

With no `build.edn`, or one that doesn't say otherwise:

- The source root is `src/` if it exists, otherwise the project root. It goes
  on `-I`, so `(import-use helper)` finds `src/helper.nuc`.
- The entry file is `src/main.nuc` if it exists. Otherwise it is the only
  `.nuc` file in the source root that defines `main`. With none, or with
  several, the build stops:

  ```
  nucleus: error: no main file: src has no src/main.nuc and no .nuc file that defines main
    note: name the entry file with :entry in build.edn
  ```
- The program is named after the project directory and written to
  `build/<name>`.

`:entry`, `:source-root` and `:name` override these. An override is used as
given: an `:entry` that doesn't exist is an error, not a reason to search.

### Example: a GTK program

A small GTK 4 program laid out as `charge.nuc/src/main.nuc`, importing
`gtk/gtk.h` and three stdlib libraries, used to carry its build in a comment:

```clojure
; make -C ../nucleus
; ../nucleus/build/nucleusc \
;     $(printf -- '--cflag=%s ' $(pkg-config --cflags gtk4)) \
;     -I ../nucleus/lib src/main.nuc -o charge \
;     $(pkg-config --libs gtk4)
```

With the compiler installed (`make install` in the checkout), each line of it
has a replacement:

- **`-I ../nucleus/lib`** isn't needed. An installed compiler finds the
  standard library beside itself, and so does `../nucleus/build/nucleus`
  run from the checkout.
- **The `pkg-config` calls** come from the import. The header index finds the
  package that provides `gtk/gtk.h`, and the build applies its flags and
  links its libraries. When both GTK 3 and GTK 4 development files are
  installed, two packages provide the header and the build stops, naming
  both. Say which one in the import, which keeps the choice beside the code:

  ```clojure
  (import-use "gtk/gtk.h" :pkg-config ["gtk4"])
  ```

  `nucleus init` writes the same choice into `build.edn` instead.
- **`src/main.nuc -o charge`** is the convention: `src/main.nuc` is the entry,
  and the program is `build/<project directory>`, `build/charge.nuc` here.
  A `build.edn` of `{:name "charge"}` names it `build/charge`.

The comment can then go, and from the project root:

```
nucleus build        # build/charge
nucleus run          # compile and run in-process
nucleus run-repl     # run it, with a prompt in its namespace beside the window
nucleus repl         # a REPL with GTK's flags and libraries; (import-use "gtk/gtk.h") at the prompt
```

Other files in `src/` are compiled only when an import reaches them.

## `build.edn`

One EDN map. Every key is optional.

| Key | Value | Meaning |
|-----|-------|---------|
| `:name` | string | The program's or library's name; the directory's name by default, and required for a library |
| `:kind` | `:program` or `:library` | `:program` by default |
| `:version` | string | The project's version; required for a library |
| `:provides` | vector of symbols or strings | A library's top-level namespaces; derived by default |
| `:shared` | `true` or `false` | A library also builds `lib<name>.so` |
| `:deps` | map | Libraries by name, below |
| `:user-registry` | `true` or `false` | `false` skips the default `library-paths.edn` |
| `:entry` | string | The entry file, relative to the project root |
| `:source-root` | string | The directory put on `-I`; `src` or the root by default |
| `:out-dir` | string | Where outputs go; `build` by default |
| `:target` | string | A target triple, as `--target=` |
| `:opt` | 0–3 | The optimization level, as `-O` |
| `:cflags` | vector of strings | Passed to clang, for C header imports and for `:c-sources` |
| `:link-args` | vector of strings | Passed to the link |
| `:libs` | vector or set of strings | Libraries to link, as `--link-lib=` |
| `:c-sources` | vector of strings | C files compiled to `build/obj/` and linked in |
| `:pkg-config` | map | Requirement sets for C headers, below |

```clojure
{:name "calc"
 :cflags ["-Icsrc"]
 :c-sources ["csrc/add.c"]
 :libs #{"m"}
 :pkg-config {"zlib.h" ["zlib >= 1.2"]
              "fake.h" {:unsafe/pkg-config ["fake4"]}}}
```

A misspelled key, or a value of the wrong kind, is an error at its line:

```
build.edn:2: error: unknown key :bogus (expected one of :name :kind :version :entry :source-root :out-dir :target :opt :cflags :link-args :libs :c-sources :pkg-config :provides :shared :deps :user-registry)
```

### Requirement sets

A `:pkg-config` entry maps a header to the packages that may provide it, in
the same form as an import annotation (see
[C requirements on an import](compiler.md#c-requirements-on-an-import)). The
compiler intersects it with the annotations on that header in the source, so
the config can narrow a choice but can't contradict the code. It also covers an
import that has no annotation.

`{:unsafe/pkg-config [...]}` replaces every other requirement on the header,
annotations included. The tool warns each time:

```
nucleus: warning: build.edn:1: :unsafe/pkg-config replaces every other requirement on "fake.h"
```

A path in `build.edn` that leaves the project (`:entry`, `:source-root`,
`:out-dir` or a `:c-sources` file that is absolute or climbs out with `..`)
warns at every build, because the file is committed and the path won't exist
in another checkout:

```
nucleus: warning: build.edn:1: :out-dir '../out' is outside the project
  note: a local path belongs in build-local.edn
```

### `build-local.edn`

Read after `build.edn`, from the same directory, and merged into it. It holds
what shouldn't be committed. The merge:

- a string, number or boolean replaces the earlier value, and so does a
  `:provides` vector;
- `:cflags`, `:link-args` and `:c-sources` append;
- `:libs` is a union;
- a `:pkg-config` set is added beside the earlier ones, so both apply;
- an `:unsafe/pkg-config` set first drops the earlier sets on its header;
- `:deps` merges by name: `:path` and `:prebuilt` replace, a `:version`
  joins the earlier constraints (all of them have to hold), and an
  `:unsafe/version` replaces them, with a warning.

## Choosing C packages

Before anything compiles, the tool lists the C headers that the entry file's
import closure reads (a library's: every public file's) (`nucleusc --list-imports`), gathers every requirement set
on each one, and picks one package per header. The picks reach the compiler as
`--pkg-config=` flags.

A header's sets come from, most binding first:

1. `:pkg-config` in `build.edn` and `build-local.edn`;
2. annotations in the project's own files;
3. annotations in its dependencies, including headers' carried imports.

Only a header that none of these names uses one of:

4. the [header table](#the-header-table-libnucleusc-packagesedn);
5. the header index: the packages whose include directories hold the header.

The sets on a header are intersected. Alternatives that aren't installed
(`pkg-config --exists`, with every constraint on that package) are dropped. The
pick is the first remaining alternative in the order of the most binding set.
Among dependencies, the file that sorts first wins, so the order never comes
from the filesystem. Then each pick's `Requires:` is checked against the other
headers: a pick that requires a package another header's sets name but didn't
pick is a clash, and the next alternative is tried. The same requirements and
the same installed packages always give the same picks.

A pick that wasn't every set's first choice is reported with the reason:

```
nucleus: note: 'fx/fx.h' uses fxb (fxa is ruled out by src/other.nuc:1)
nucleus: note: 'fx/fx.h' uses fxb (fxa is not installed in a version the requirements accept)
```

When nothing fits, the build stops before any compile and lists every set and
where it came from:

```
nucleus: error: no C package satisfies 'fx/fx.h': no package is in every set
  note: build.edn:1 requires ["fxb"]
  note: src/main.nuc:1 requires ["fxa"]
```

### When the conventions can't decide

A header that only the index answers, and that several installed packages
provide, is ambiguous. The build stops:

```
nucleus: error: 'fx/fx.h' is provided by several packages: fxa, fxb
  note: run `nucleus init` to write the choice to build.edn
```

`nucleus init` writes the choice, keeping the first alternative by name and
commenting out the rest:

```clojure
; Written by `nucleus init`. Commit it; a local path belongs in build-local.edn.
{:pkg-config
 {"fx/fx.h" ["fxa"
   ;"fxb"
   ]}}
```

With a `build.edn` already present, the note shows the entry to add instead.

### The header index

A header is looked up only if clang's own include path (`clang -E -v`) and the
`-I` directories in `:cflags` don't find it, so `stdio.h` never needs a
package. The index holds each package's `--cflags-only-I` directories and its
`Requires:`. A package that reaches the header only through another candidate
it requires is left out: gtk4's flags include glib's directory, but `glib.h`
belongs to `glib-2.0`.

The index is cached in `$XDG_CACHE_HOME/nucleus/pkg-index.edn`. The cache is
keyed by `PKG_CONFIG_PATH`, `PKG_CONFIG_LIBDIR` (or pkg-config's built-in path)
and `PKG_CONFIG_SYSROOT_DIR`, and it is rebuilt when any `.pc` file on that
path is added, removed or changed.

## What is rebuilt

The build is a graph of steps. Each step runs one command that writes one
file: one `clang -c` for each `:c-sources` file, then one `nucleusc` that
compiles the entry file and links it with the objects. A library's graph is in
[Library projects](#library-projects).

A step reruns when:

- its output is missing;
- its command changed — any argument, or the directory it runs in;
- the compiler changed (a hash of the `nucleusc` executable);
- a file it read last time is gone, or its contents changed.

The read set comes from the step's depfile (`nucleusc --depfile=`, `clang
-MD`): every source, header and `.nuch` the compile opened, and every file a
macro read with `read-file-tracked`. A file whose mtime or size changed is
hashed again. If the contents are unchanged, the record takes the new mtime
and the step doesn't rerun, so touching a file rebuilds nothing.

The records are in `build/.nucleus-log.edn`, one EDN map per output. A step
writes its output to `<output>.tmp` and renames it only when the command
succeeds, so a failed or interrupted step never leaves a partial output.

## Dependencies

An import whose root nothing on `-I` provides, such as `(import-use gtkw.core)`,
names a library. So does an entry in `:deps`:

```clojure
{:deps {gtkw {:version ">= 0.3"}
        cairo-nuc {:path "vendor/cairo-nuc"}
        fz {:prebuilt true}}}
```

| Key | Value | Meaning |
|-----|-------|---------|
| `:path` | string | A project directory, relative to the project root. Committed in `build.edn` it should stay inside the project (a vendored copy). A sibling checkout belongs in `build-local.edn`. |
| `:version` | constraint | `">= 0.3"`, compared as pkg-config compares versions |
| `:unsafe/version` | constraint | Replaces every other constraint on the library, with a warning |
| `:prebuilt` | `true` or `false` | Link an install's archive instead of compiling its source |

The tool finds a library in the first of these places that has it, and doesn't
look further for that library:

1. a `:path` in `build-local.edn`;
2. a `:path` in `build.edn`;
3. the user registry: `$XDG_CONFIG_HOME/nucleus/library-paths.edn`, then
   each `--library-paths=` file. A later file's entry wins. `--no-user-registry`
   or `:user-registry false` leaves out the default file;
4. installed libraries: the manifests under `~/.local/lib/<multiarch>/nucleus/`,
   `/usr/local/lib/<multiarch>/nucleus/` and `/usr/lib/<multiarch>/nucleus/`;
   then a `.pc` file whose `nucleus_manifest` variable names one; then a
   `<root>/<file>.nuch` under `~/.local/include`, `/usr/local/include` or
   `/usr/include` (with the multiarch name, then without), linking the
   `lib<name>.a` that its `library` line names, if one is installed beside it;
5. the stdlib, which the compiler finds itself.

A registry file names project directories:

```clojure
{:libraries {gtkw "~/src/gtkw"}       ; a name and its project
 :search ["~/src/nucleus-libs"]}      ; every project directly inside
```

A `:deps` entry is looked up by name. An import is looked up by its root: the
library that provides `gtkw`, by its `:provides` or, if it has none, by its
source directories. A library from a project directory brings its own
`build.edn` with it:

- its `:deps`, resolved the same way (a name the project resolved first keeps
  the project's answer);
- its `:pkg-config` sets, which bind like its annotations;
- its `:cflags` (an `-I` relative to its directory) and `:libs`.

Its `build-local.edn` is ignored. A library with `:c-sources` gets a warning,
because a consumer doesn't build them yet.

A library is compiled from its source. That is the project's source directory,
or an install's `share/nucleus/src/`, which goes on `-I`. It is used prebuilt
when it has no source, or with `:prebuilt true`: its installed `.nuch`
directory goes on `-I`, and its archive is linked. Prebuilt use needs a
manifest whose `:compiler` is this compiler and whose `:header-format` is 1.
Otherwise the library is compiled from source with a note, or, if it has no
source, the build stops:

```
nucleus: note: fz is compiled from source: its object was built by another compiler
```

The manifest's `:target` must also be the build's target. An `unsafe/`
widening the object can't satisfy also puts a prebuilt library back on
source. Its headers record the package each C header was compiled against.
When the build picks another package for one of them, the library is
compiled from source and the resolution runs again:

```
nucleus: note: gw is compiled from source: its object was compiled against fxb, and 'fx/fx.h' uses fxa here
```

A prebuilt library's macros run in the compiler, which can't load its object.
So for a prebuilt library whose headers export a macro, the tool passes
`--ct-source=ROOT=<its share/nucleus/src>` for each root it provides. The
compiler then reads the source for compile time while the program links the
archive (see [A library's source for compile time](toplevel.md#a-librarys-source-for-compile-time-its-object-for-the-program)),
and a macro that calls the library's own functions works.

The archive is in the program's read set, so a reinstalled library relinks it.

A library found through `build-local.edn` or the registry is named on every
build. Both live outside the repository, so this is where "works on my
machine" shows:

```
nucleus: note: using gtkw from ../gtkw (build-local.edn)
```

What stops the build:

```
nucleus: error: src/main.nuc:1: no library provides 'gtkw', for (import gtkw.core)
  note: name it in :deps in build.edn, or run `nucleus init-local` to use a sibling checkout
nucleus: error: two libraries provide 'gtkw': gw-a (srch/a) and gw-b (srch/b)
nucleus: error: bad (vendor/bad) provides the root nucleus, which only the stdlib may
nucleus: error: build.edn:1: gtkw 0.1 from build-local.edn does not satisfy '>= 0.2'
```

Two libraries in the build that provide the same root are an error, whether
both come from one place, or from `:deps` and an import. So is any library
other than the stdlib that provides `nucleus`. `unsafe/` keys are allowed in a
dependency's `build.edn`, and they warn in every build that uses it. A
dependency's `:unsafe/pkg-config` replaces the sets at its own rank and below,
never its consumer's. The project's own annotations and config still narrow it.

### Imports a macro generates

`--list-imports` reads import forms without expanding macros, so it misses an
import that a macro generates. Each compile the tool runs gets
`--missing-imports=<file>`. A compile that can't find an import writes it there
and exits quietly. The tool then looks for the library. If it finds one, it
builds the project again from the start, and it records the import in
`build/.nucleus-imports.edn` so that later builds look for it up front. If no
library provides the import, the tool reports the compiler's error at the
import's line.

### `nucleus init-local`

`init-local` lists the libraries the project needs: its `:deps`, and the roots
of imports nothing on `-I` provides. For each, it looks for a sibling project
(`../*/build.edn`) that has that name or provides that root, and writes a path
override for every match:

```
nucleus: wrote build-local.edn
  gtkw uses ../gtkw
  added build-local.edn to .gitignore
```

```clojure
; Written by `nucleus init-local`: paths on this machine. Don't commit it.
{:deps {"gtkw" {:path "../gtkw"}}}
```

In a git repository it adds `build-local.edn` to `.gitignore` if it isn't
there. It refuses to overwrite an existing `build-local.edn`, and prints the
entries to add instead.

## Library projects

A `build.edn` with `:kind :library` describes a library:

```clojure
{:kind :library :name "fz" :version "1.0" :libs ["m"]}
```

It provides the namespaces under `:provides`. By default these are the
source root's top-level directories that hold a `.nuc` file, and the stems of
its top-level `.nuc` files. A `:provides` name must be top-level (`gtkw`, not
`gtkw/extra`), and must have a `gtkw.nuc` or `.nuc` files under `gtkw/`. Every
`.nuc` file under a provided namespace is public. Building compiles each one
three times:

| Output | Command |
|--------|---------|
| `build/obj/fz__core.o` | `nucleusc -c --strict-initializers` |
| `build/include/fz/core.nuch` | `nucleusc --emit-nuch --library=fz@1.0 --build-id=ID` |
| `build/include/fz/core.h` | `nucleusc --emit-cheader` |

`build/lib/libfz.a` (`ar rcs`) then archives every object, `:c-sources`
objects included. With `:shared true`, `build/lib/libfz.so` (`clang -shared`)
links them against the picked packages' libraries and `:libs`.

Each object is compiled on its own. Definitions from a file it imports are
emitted weak, so the objects archive together and a C program links them.
That is why a library build is always strict about run-time initializers: a
`defvar` whose initializer runs at load time, in a file another file imports,
is an error rather than `-c`'s warning, since every object that imports it
would run it again:

```
src/fy/conf.nuc:4: error: defvar: 'g-greet' has a run-time initializer, and this object only imports the file that declares it -- …
```

The build id that the headers carry is a hash of the compiler, the name and
version, the flags, and every public file's path and contents. It does not
depend on where the checkout is, and the header's comment names the source
relative to the project root. `run` and `run-repl` refuse a library; `repl` doesn't.

## Installing a library

`nucleus install` builds the library, then copies it under a prefix:
`/usr/local` by default, `~/.local` with `--user`, or `--prefix=DIR`. When
`DESTDIR` is set, every file is written under `$DESTDIR`, but the paths
recorded in the `.pc` file and the manifest don't include it. The layout puts
everything target-specific under the target's multiarch name (the triple
without its vendor, `x86_64-linux-gnu`):

```
$PREFIX/include/x86_64-linux-gnu/fz/core.nuch   one .nuch and one .h per public file
$PREFIX/include/x86_64-linux-gnu/fz/core.h
$PREFIX/lib/x86_64-linux-gnu/libfz.a            and libfz.so with :shared
$PREFIX/lib/x86_64-linux-gnu/pkgconfig/fz.pc
$PREFIX/lib/x86_64-linux-gnu/nucleus/fz.edn     the manifest
$PREFIX/share/nucleus/src/fz/core.nuc           the source, for any target
```

Each `.edn` file under a provided root is data the library reads, so it is
installed beside the sources too.

The target is `--target=`, then `:target`, then the host. A C program uses the
library through pkg-config, with no Nucleus tooling:

```
prefix=/usr/local
libdir=${prefix}/lib/x86_64-linux-gnu
includedir=${prefix}/include/x86_64-linux-gnu
nucleus_manifest=${libdir}/nucleus/fz.edn

Name: fz
Description: The Nucleus library fz
Version: 1.0
Cflags: -I${includedir}
Libs: -L${libdir} -lfz -lm
```

`Requires:` lists the packages that the headers' `c-requires` forms record,
and `Libs:` adds their plain libraries. The C names are the mangled ones, so
`fz.core`'s `fz-answer` is `fz_core__fz_answer()` (see
[compiler.md](compiler.md)).

The manifest is the Nucleus half:

```clojure
{:name "fz" :version "1.0"
 :provides ["fz"]
 :build-id "ee3c38190fc6f85d" :compiler "2d9d8058e9622968" :header-format 1 :target "x86_64-pc-linux-gnu"
 :requires {:nucleus ["nucleus"] :pkg-config [] :libs ["m"]}
 :objects {:static "libfz.a" :shared nil}
 :files ["/usr/local/include/x86_64-linux-gnu/fz/core.nuch"
         …
         "/usr/local/lib/x86_64-linux-gnu/nucleus/fz.edn"]}
```

`:requires :nucleus` lists the roots of the Nucleus namespaces that the
library imports from elsewhere. `:files` is every installed path, the manifest
included. A reinstall first removes the files the previous manifest lists.

`--no-source` leaves out `share/nucleus/src/`. A library installed this way
is always used prebuilt. Its macros still work if their expansion code runs
only the stdlib, as a quasiquote template or a call to `node-int` does.
`--no-source` refuses a library with a macro whose expansion code calls one of
the library's own functions or reads one of its `defvar`s, because a consumer
compiles those from source. The header's `macro-calls` lines record what each
macro calls, and the error names the macro and its callees:

```
nucleus: error: --no-source: fz/m/mac.nuc's macro fz-seven calls fz.m.mac/fz-n, and without fz's source a consumer can't compile it
```

A callee counts as the library's own when its namespace root is one of the
library's `:provides`, or when it's in a file without an `ns`. Code that the
expansion emits into the consumer's program isn't counted, because the
consumer links it from the object.

`nucleus uninstall` reads the manifest for the same prefix and target, removes
every file it lists, and then removes the directories that leaves empty, up to
the prefix. Run in a library project it removes that library. `nucleus
uninstall NAME` removes `NAME` from anywhere.

### The standard library

The standard library is the library `nucleus`, declared by `lib/build.edn`
with `:source-root "."` and `:provides [nucleus]`, so the test fixtures beside
`lib/nucleus/` aren't part of it. `make install` installs `nucleusc` and the
`nucleus` symlink into `$PREFIX/bin`, then runs `nucleus install
--prefix=$PREFIX` in `lib/`. `make uninstall` runs the installed `nucleus
uninstall nucleus` and then removes the binary. Both honour `PREFIX` and
`DESTDIR`:

```
make install PREFIX=$HOME/opt/nucleus
```

An installed compiler finds the sources in `$PREFIX/share/nucleus/src/`
beside itself, for any prefix, with no `-I` and no `$NUCLEUS_LIB` (see
[Where an import is found](toplevel.md#where-an-import-is-found)). Programs
still compile the standard library from those sources. `libnucleus.a`,
`nucleus.pc` and the headers are for C programs:

```c
#include <nucleus/fnv.h>   /* nuc_fnv1a_bytes(…) */
```

```
cc app.c $(pkg-config --cflags --libs nucleus)
```

A hyphenated Nucleus name reaches C through a `NUC_ASM` label, which works
under both GCC and clang (see [compiler.md](compiler.md#hyphenated-names-in-a-c-header)).
`make lib-objs` and `make lib-so` still build the library in the tree.

## `nucleus.build.resolve` (`lib/nucleus/build/resolve.nuc`)

The resolution above, as a library. pkg-config is reached only through the two
functions passed in, so a test can pass fakes.

| Function | Signature |
|----------|-----------|
| `c-requests` | `():CRequests` — an empty request; `Drop` |
| `c-require` | `(rq:&CRequests header:StrView file:StrView line:i32 rank:i32 unsafe:bool):void` — start a set |
| `c-require-spec` | `(rq:&CRequests spec:StrView):void` — add an alternative to the last set |
| `resolution` | `():Resolution`; `Drop` |
| `resolve-c` | `(rq:&CRequests installed:(fn bool)(&(Vector StrView)) requires:(fn void)(StrView &(Vector StrView)) out:&Resolution):bool` — false with `out.error` set when nothing fits |
| `resolved-pkg` | `(res:&Resolution header:StrView):StrView` — `""` when the header has no pick |
| `spec-name` | `(spec:StrView):StrView` — `"gtk4 >= 4.10"` → `"gtk4"` |

```lisp
; rank is RANK-CONFIG, RANK-ROOT, RANK-DEP, RANK-TABLE or RANK-INDEX
(defstruct Pick header:StrView pkg:StrView)
(defstruct Resolution
  picks:(Vector Pick)       ; one per decided header
  notes:(Vector StrView)    ; "'h' uses p (why)"
  ambiguous:(Vector Pick)   ; one per alternative of each undecided header
  error:String)
```

`installed` gets a package name followed by every constrained spec of it.
`requires` adds the package's direct requires to its vector.

## `nucleus.build.index` (`lib/nucleus/build/index.nuc`)

| Function | Signature |
|----------|-----------|
| `header-index` | `():HeaderIndex` — empty; `Drop` |
| `header-index-load` | `(idx:&HeaderIndex):void` — from the cache, or built with pkg-config and cached |
| `index-providers` | `(idx:&HeaderIndex header:StrView extra:&(Vector StrView) out:&(Vector StrView)):void` — the packages that provide `header`, by name; none when the system or a directory in `extra` finds it |
| `index-requires` | `(idx:&HeaderIndex name:StrView out:&(Vector StrView)):bool` — a package's direct requires; false if the index doesn't know it |

## `nucleus.build.lookup` (`lib/nucleus/build/lookup.nuc`)

What a library is, wherever it was found, and the places [Dependencies](#dependencies) searches.

```lisp
; tier is TIER-LOCAL, TIER-CONFIG, TIER-REGISTRY or TIER-INSTALLED
(defstruct Library
  name:StrView version:StrView
  roots:&(Vector StrView)    ; the namespaces it provides
  dir:StrView                ; a project's directory; "" for an install
  source:StrView             ; the directory to put on -I; "" when it has no source
  include:StrView archive:StrView compiler:StrView header-format:i64   ; an install's
  config:?&BuildConfig       ; a project's build.edn
  tier:i32 where:StrView)
(defstruct RegEntry name:StrView dir:StrView file:StrView)   ; name "" for a :search hit
```

| Function | Signature |
|----------|-----------|
| `library-new` | `():Library` — empty |
| `library-provides?` | `(l:&Library root:StrView):bool` |
| `library-from-project` | `(dir:StrView label:StrView tier:i32 where:StrView out:&Library err:&String):bool` — from `dir/build.edn` alone; `label` names that file in messages |
| `library-from-manifest` | `(path:StrView out:&Library err:&String):bool` — an installed manifest; the prefix and multiarch name come from its path |
| `derive-roots` | `(source-root:StrView out:&(Vector StrView)):void` — the top-level directories holding a `.nuc`, and the top-level `.nuc` stems, sorted |
| `nuc-files-under` | `(dir:StrView cut:usize out:&(Vector StrView)):void` — every `.nuc` below `dir`, less `cut` bytes, skipping hidden names |
| `registry-load` | `(path:StrView into:&(Vector RegEntry) err:&String):bool` — one `library-paths.edn`, `~` and relative paths resolved |
| `installed-manifests` | `(home:StrView multiarch:StrView out:&(Vector StrView)):void` — per-user, then local, then system |
| `pkg-config-manifest` | `(name:StrView):StrView` — the `nucleus_manifest` variable of `name.pc`, or `""` |
| `include-dirs` | `(home:StrView multiarch:StrView out:&(Vector StrView)):void` |
| `nuch-library-name` | `(path:StrView):StrView` — the NAME of a header's `(library NAME …)` line |
| `config-load` | `(path:StrView label:StrView c:&BuildConfig err:&String):bool` |

## `nucleus.build.version` (`lib/nucleus/build/version.nuc`)

Versions and version constraints, compared the way pkg-config compares them.
A Nucleus library's version and a C package's version then never disagree
about which one is newer.

| Function | Signature |
|----------|-----------|
| `version-cmp` | `(a:StrView b:StrView):i32` — negative, 0 or positive, as `a` is older than, the same as, or newer than `b` |
| `version-constraint-parse` | `(text:StrView):!VersionConstraint` — `">= 4.10"`, `"= 1.2"`, `"< 2"`; `""` is no constraint |
| `version-satisfies?` | `(v:StrView c:&VersionConstraint):bool` |

```lisp
(defstruct VersionConstraint op:i32 version:StrView)
; op is one of VER-ANY VER-LT VER-LE VER-EQ VER-NE VER-GE VER-GT
```

### How versions compare

`version-cmp` is a port of pkgconf's comparison, which is RPM's `rpmvercmp`:

- A version is a run of segments. Each segment is all digits or all letters,
  and any other byte separates segments.
- Numeric segments compare as numbers, with leading zeros ignored.
- Alphabetic segments compare as bytes.
- A numeric segment is newer than an alphabetic one.
- `~` sorts before everything, even the end of the string, so `1.0~rc1` is
  older than `1.0`.
- When one version runs out of segments, the longer one is newer.
- Two versions that are equal ignoring ASCII case are equal.

The suite checks 17 pairs against `pkg-config --exists` itself
(`bt1-version-agrees-with-pkg-config`).

### Constraints

A constraint is an operator and a version, with optional spaces between them.
A bare version (`"4.10"`), an operator alone (`">="`) and two versions
(`">= 4 5"`) are refused with `(err version-constraint-invalid)`, as
pkg-config refuses them. A bare version is refused because it would leave open
whether `=` or `>=` was meant.

`version` borrows the parsed text, so the text must outlive the constraint.

## `nucleus.build.pkg` (`lib/nucleus/build/pkg.nuc`)

`pkg-config` as a library. The compiler's `--pkg-config=`, the import
annotations, and the REPL's `pkg-config` meta form all use these functions, so
they split pkg-config's output the same way.

| Function | Signature |
|----------|-----------|
| `pkg-flags` | `():PkgFlags` — four empty vectors; `Drop` |
| `pkg-config-query` | `(pkgs:&(Vector Symbol) into:&PkgFlags):String` — `--cflags` and `--libs` into `into`; `""` on success, else the message to report |
| `pkg-config-exists?` | `(specs:&(Vector StrView)):bool` — `pkg-config --exists`, with specs such as `"gtk4 >= 4.10"` |
| `pkg-config-run` | `(args:&(Vector StrView) out:&String errs:&String):i32` — one child, its exit status, -1 if it didn't start |
| `pkg-config-requires` | `(name:StrView out:&(Vector StrView)):void` — the names in `Requires:` and `Requires.private:`, without constraints |
| `pkg-config-words` | `(out:&String into:&(Vector Symbol)):void` — split output on whitespace; `\` escapes the next byte |

```lisp
(defstruct PkgFlags
  cflags:(Vector Symbol)     ; every --cflags word
  lib-dirs:(Vector Symbol)   ; -L, without the prefix
  libs:(Vector Symbol)       ; -l, without the prefix
  other:(Vector Symbol))     ; the rest of --libs: -pthread, -Wl,…
```

`pkg-config-query` runs both children before it adds anything, so a failure
leaves `into` as it was. The message is pkg-config's own first line of
diagnosis, such as `pkg-config: Package fake3 was not found in the pkg-config
search path.`. If pkg-config can't be run, the message is `pkg-config: not
found`.

`other` holds the flags that a batch link passes on and that a JIT can't use.

Constraints go to pkg-config itself (`--exists "gtk4 >= 4.10"`), so the answer
is the one the installed packages give. `nucleus.build.version` is for the
versions pkg-config doesn't know about.

## The header table (`lib/nucleus/c-packages.edn`)

An EDN map from a C header to the requirements of an unannotated import of
it:

```
{"math.h" {:libs ["m"]}
 "zlib.h" {:pkg-config ["zlib"]}}
```

`$XDG_CONFIG_HOME/nucleus/c-packages.edn` is read after it and replaces its
entries header by header. See
[The header table](compiler.md#the-header-table).
