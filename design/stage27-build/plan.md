# Stage 27 — build plan

**Status: BT-0 … BT-11 built 2026-10-25, uncommitted.**
Each built phase ends with a *Built* note that records where the build
departed from the plan. This plans the design in
[overview.md](overview.md): Q1–Q6 and Q6f–Q6t, all ruled. Section references
(§N) are to that document. §1 lists the defaults this plan takes where the
design doesn't decide. Each can be overturned before its phase starts.

## 1. Defaults taken by this plan

- **D-ENTRY. `nucleus` is a symlink to `nucleusc`, and the mode is chosen by
  `argv[0]`'s basename.** Q1 rules one binary. `make` creates
  `build/nucleus`, and the install creates `$PREFIX/bin/nucleus`. Every
  `nucleusc` invocation keeps its current meaning.
- **D-LIBCODE. The tool's logic lives in `lib/nucleus/build/`**
  (`nucleus.build.config`, `.graph`, `.exec`, `.resolve`, `.pkg`, `.install`,
  `.version`). Only argument handling and the in-process `--run`/`-i` hand-off
  live in `src/`. The logic can then be tested as ordinary Nucleus, and it
  becomes the first candidate when Q1 is revisited "after more of the
  compiler is moved into libraries".
- **D-STATE. Outputs and state go in `build/` under the project root**
  (`:out-dir` overrides it). The executable is `build/<name>`. The per-output
  record is `build/.nucleus-log.edn`: one EDN map per output, holding the
  command hash, the compiler's identity and the read set.
- **D-CONV. Zero-config conventions.**
  - The entry file is `src/main.nuc` if it exists, otherwise the only `.nuc`
    file in `src/` or the root that defines `main`.
  - The source root is `src/` if it exists, otherwise the project root.
  - The output is named after the project directory.
  - A library project always needs a `build.edn` with `:kind :library`,
    `:name` and `:version`.
  - `build.edn` can override each convention: `:entry` (a path relative to
    the project root), `:source-root` and `:name`. An override is used as
    given, with no fallback search. An `:entry` that doesn't exist is an
    error, not a reason to try the conventions. (Confirmed 2026-10-25, with
    the overrides added.)
- **D-STANDALONE. `nucleusc` honors import annotations on its own.** Without
  the build tool, it intersects the annotations in its own import closure and
  applies the first alternative that is installed. The build tool resolves the
  whole dependency graph (§8.8) and passes the decided packages with
  `--pkg-config=`. A passed package outside some annotation's set is an early
  error.
- **D-VERCMP. Versions use pkg-config's semantics.** A C constraint is checked
  by asking pkg-config (`--exists "gtk4 >= 4.10"`). Nucleus library versions
  are compared by a port of the same algorithm (`nucleus.build.version`), so
  the two never disagree.
- **D-STALE. Staleness checks mtime and size first, then a content hash
  (`nucleus.fnv`) when they changed.** Touching a file doesn't cause a
  rebuild. The compiler's identity is a hash of its own executable, computed
  once per run.
- **D-CACHE. The header→package index is cached** in
  `$XDG_CACHE_HOME/nucleus/pkg-index.edn`. It is keyed by the pkg-config
  search path and rebuilt when any `.pc` file on it changes.
- **D-LINUX. The install layout and lookup paths are Linux multiarch only.**
  Other platforms' layouts are out of scope (§7).

## 2. Phases

| Phase | Delivers | Needs |
|---|---|---|
| **BT-0** | Compiler lookup fixes: P1 (finds stdlib relative to its executable), P6 (empty source dir means `.`) | — |
| **BT-1** | Library support: `merge`/`merge-with` (P9), file metadata/rename/remove/exe path, XDG helpers, `nucleus.build.version` | — |
| **BT-2** | Compiler dependency reporting: `--depfile` (P2), recorded compile-time reads (P3), `--list-imports` (P5) | BT-0 |
| **BT-3** | C requirements in the compiler: `nucleus.build.pkg` (P4), `--pkg-config`/`--link-lib` (P7), import annotations and the header→package table (P12) | BT-1 |
| **BT-4** | Header format v1: H1–H4 (P8) | BT-3 |
| **BT-5** | `nucleus` core: config, merge, conventions, graph, executor, `build`/`run`/`run-repl`/`clean` | BT-1, BT-2, BT-3 |
| **BT-6** | Discovery, requirement-set resolution, `nucleus init` | BT-5 |
| **BT-7** | Library projects, `nucleus install`/`uninstall` | BT-4, BT-6 |
| **BT-8** | Dependencies and lookup: §8.5 order, registry, `build-local.edn`, `init-local`, collisions, `unsafe/` | BT-7 |
| **BT-9** | The stdlib through `nucleus install`; `make install` delegates (P10) | BT-7 |
| **BT-10** | Prebuilt opt-in: `:prebuilt`, `--no-source`, compile-time source root (P11) | BT-8 |
| **BT-11** | Consolidated docs, context files, the charge walkthrough | all |

BT-0 through BT-4 are compiler and library work, and each is useful on its own.
BT-3 already removes the `$(pkg-config …)` splicing from charge's build line.
BT-5 is the first phase a user runs `nucleus` in. BT-9 and BT-8 can run in
parallel after BT-7.

**Gates for every phase:**
- `make test` passes, with the new units added;
- `make bootstrap` reaches the fixed point;
- for a phase that changes compiler output, the IR corpus is byte-identical
  for programs that don't use the new feature;
- the docs for that phase are updated (CLAUDE.md), and `progress.md` gets an
  entry.

## 3. Phase detail

### BT-0 — compiler lookup fixes

- **P1.** Read `/proc/self/exe` once and add `<exe-dir>/../lib`, for a
  checkout's `build/nucleusc`, to `try-import-path` (`src/nucleusc.nuc:21412`),
  ahead of `$NUCLEUS_LIB`. The installed location changes in BT-9. Until then,
  the existing `/usr/local/share/nucleus/lib/` fallback stays.
- **P6.** Treat an empty `source-file-dir` as `.`, so `nucleusc app.nuc` finds
  `./mylib/core.nuc` the way `./app.nuc` already does (§8.1 gap 4).
- **Tests:** compile a fixture from a scratch directory outside the tree,
  with no `-I`, using `build/nucleusc` by absolute path. Also check the
  gap-4 repro.
- **Built.** `exe-prefix` is `<exe-dir>/..`. `try-import-path` tries
  `<prefix>/lib/` and then `<prefix>/share/nucleus/lib/` (the installed
  layout, so BT-9 needs no lookup change), then `$NUCLEUS_LIB`. `make install`
  no longer prints its `NUCLEUS_LIB` note. Units: `bt0-stdlib-beside-compiler`,
  `bt0-bare-filename-searches-cwd`.

### BT-1 — library support

- **`merge` and `merge-with`** in `nucleus.coll`, as standalone generics over
  `Assoc` + `Coll (Entry K V)` (§8.9). `merge-with` takes
  `:where ((BinaryFn V V) F)`, and a replaced value is dropped when `V`
  conforms to `Drop`. Add a `HashMap` overload only if measurement shows it's
  needed.
- **File functions** in `nucleus.file`: `file-stat` (mtime in nanoseconds,
  size, kind), `rename-file` (for atomic replace), `remove-file`,
  `real-path`, `exe-path`.
- **`xdg-config-home`/`xdg-cache-home`** with their `$HOME` fallbacks.
  `nucleus.process` already has `spawn`, `wait-any` and `run`, which is
  enough for the executor.
- **`nucleus.build.version`**: parse and compare versions, and parse a
  constraint (`>= 4.10`, `= 1.2`, `< 2`) and test a version against it. Its
  tests run the same pairs through `pkg-config --exists` and check that the
  answers agree.
- **Docs:** `docs/collections.md`, `docs/io.md`.
- **Built**, with two departures:
  - `merge`/`merge-with` live in `nucleus.combinators`, beside the other
    generics over `Coll`. A replaced value is not dropped: neither map type
    owns its elements, so dropping one would free what the caller still
    holds.
  - `nucleus.file` also gained `file-exists?`, `xdg-dir` (only an absolute
    value wins, as the XDG spec says) and the tracked-read primitive below.
  Units: `bt1-version-agrees-with-pkg-config` (17 pairs),
  `bt1-version-constraints`, `bt1-file-metadata`, `bt1-xdg-dirs`, and the
  `comb-merge` example.

### BT-2 — dependency reporting

- **`--depfile=<path>`** writes a gcc-format depfile: the output, then every
  `.nuc`/`.nuch` the compile read, then every header the C preprocessor read.
  Get the last part by adding `-MD -MF <tmp>` to the `clang -E` in
  `cheader-cpp-command` and merging its output in. Write to a temporary file
  and rename it into place.
- **P3: a recorded read primitive** for compile-time code, which adds its
  path to the depfile. The docs say plainly that a direct `fopen` from a
  macro isn't tracked.
- **`--list-imports`** reads a unit without compiling it and prints one EDN
  map per import form, with the line number, the head and the
  path-or-header. It follows the import forms it can see, not macro output.
  §3's `--diagnostics=edn` retry loop covers macro output.
- **Tests:** golden depfiles for a unit with a nested import, a `.nuch`
  import and a C header import. A macro that reads a file through the
  primitive shows up in the depfile.
- **Built**, with these departures:
  - P3 is the library function `read-file-tracked` in `nucleus.file`, not a
    special form. A macro calls it through the JIT, so it records into the
    compiler's own buffer.
  - `--list-imports` is transitive: it follows every resolved Nucleus import
    and prints the root's forms first. From BT-3 on, it also prints
    annotations.
  - No depfile is written when the compile fails.
  - `--run` refuses `--depfile=`.
  Code: `src/deps.nuc`. Units: `bt2-depfile-lists-reads`,
  `bt2-depfile-not-written-on-error`, `bt2-list-imports`.

### BT-3 — C requirements in the compiler

- **`nucleus.build.pkg`** (P4). Move the logic behind the REPL's `pkg-config`
  meta form out of `src/repl.nuc`: running pkg-config, splitting
  `--cflags`/`--libs` into the four vectors, and skipping `-pthread`. The meta
  form then calls the library. The existing `s21-repl-pkg-config` unit must
  still pass unchanged.
- **`--pkg-config=<pkg>` and `--link-lib=<name>`** (P7) apply the same split
  in batch mode and record what was applied, for BT-4.
- **Import annotations** (P12): `(import-use "gtk/gtk.h" :pkg-config ["gtk4"
  "gtk3"] :libs ["m"])`. Parse them on every C-header import head, and refuse
  them on a Nucleus import. Then apply D-STANDALONE.
- **The header→package table** ships as an EDN file next to the stdlib
  (`math.h` → `:libs ["m"]`, `dlfcn.h`, `pthread.h`, and other system
  libraries with no `.pc`). `$XDG_CONFIG_HOME/nucleus/c-packages.edn`
  extends it, and later entries win.
- **Tests:** use the `nucprobe` fixture pattern from `suite-target.nuc`, with
  `PKG_CONFIG_LIBDIR` pointing at scratch `.pc` files so system packages can't
  leak in. Cover:
  - an annotated import that links with no flags;
  - two annotations that intersect;
  - a passed `--pkg-config` outside the set (early error);
  - a `math.h` program that links `-lm` from the table.
- **Built**, with these departures and decisions:
  - **When an early error fires.** Once any `--pkg-config=` is passed, every
    annotated header must have one of its alternatives among the passed
    packages. Otherwise the compile stops with an error before it reads the
    unit.
  - **Picking with no passed packages.** The compiler picks the first
    alternative in the intersection that `pkg-config --exists` accepts. A
    pick that isn't the first alternative prints a note.
  - **Table entries.**
    - A table `:pkg-config` entry is advisory. It applies only to an
      unannotated header, and it is skipped silently when the package isn't
      installed.
    - A table `:libs` entry always applies.
  - **`dlfcn.h` and `pthread.h` are not in the table.** glibc 2.34+ puts
    both in libc, and there is no unversioned `libdl.so` for the JIT to load.
  - **Linking `-l` names.** They go through `g-creq-libs`, both from
    annotations and from a `.pc` file's `--libs`.
    - A batch link appends them.
    - `--run` and `-i` load them leniently. `libm.so` is a linker script that
      `dlopen` refuses, and libm is already in the process.
  - **The REPL.** It strips and validates annotations, but doesn't apply them
    yet.
  - **The pre-walk.** Annotations are resolved by walking the unit's import
    closure before the compile starts. On `src/nucleusc.nuc`, the walk costs
    about 0.08 s.
  Code: `src/creqs.nuc`, `lib/nucleus/build/pkg.nuc`,
  `lib/nucleus/c-packages.edn`. Units: `bt3-annotation-applies-package`,
  `bt3-annotations-intersect`, `bt3-passed-package-checked`,
  `bt3-annotation-refusals`, `bt3-table-links-libm`, `bt3-user-table`,
  `bt3-list-imports-annotations`.

### BT-4 — header format v1

- **H1.** `emit-nuch-import-env` (`src/nuch.nuc:213`) writes C-header imports,
  annotations included, and they *load* when the header is imported.
- **H2.** `(c-requires {:pkg-config [...] :libs [...]})`, from what BT-3
  applied.
- **H3.** `(library NAME "VERSION" :build-id "…" :header-format 1)`, written
  when `--library=<name>@<version>` is passed. The build tool passes it from
  BT-7 on. A header without one is format 0, as now.
- **H4.** A header that exports a macro writes the imports its body reads as
  compile-time loading imports. Fully fixing gap 3 also needs the macro's
  callees compiled from source. That is BT-10's P11. In source mode, which is
  the default (Q6s), gap 3 doesn't occur.
- **Tests:** §8.1's gap 1 (`unknown type: z_stream`) and gap 2 (link needs
  `-lz`), reproduced as units that now pass, plus gap 3's `node-int` half. Run
  `make lib-headers` and `make lib-cheaders` again, and their consumers in
  the suite must still pass.
- **Built**, with these departures:
  - **The `library` line follows `(ns …)`** instead of being the first line.
    An importer's prescan honors `ns` only as a header's first form, so a
    `library` line ahead of it made every `declare` register unmangled.
  - **H1 narrows the annotation.** A carried C import is annotated with the
    package this build applied for that header (`:pkg-config ["fakez >= 1.0"]`),
    not with the source's alternatives. That pins a prebuilt object's choice,
    and the existing intersection then reports a consumer that rules it out.
    The annotation carries the slot's version constraint when there is
    exactly one, and the bare name otherwise.
  - **H2's `:pkg-config` is a flat vector of applied package names**, not the
    requirement sets of overview.md §8.3 (`[["zlib"]]`). The sets travel on the
    H1 annotations. `:libs` lists only plain libraries (from `:libs`, the
    table and `--link-lib=`), not a `.pc` file's own `-l`s. A consumer applies
    `c-requires` in the closure walk, before the compile, and the header
    import itself ignores it.
  - **H3's `:build-id`** comes from a separate `--build-id=` flag. The build
    tool decides what it identifies (BT-7).
  - **H4 writes `(require-ct LIB)`** for every carried non-`user`, non-prelude
    Nucleus import when the header exports any `defmacro`. It doesn't analyse
    which libraries the macro bodies call. In a header, `require-ct` now loads,
    through `emit-require-ct`.
  Units: `bt4-header-records-c-imports`, `bt4-header-loads-c-import` (gap 1),
  `bt4-header-links-c-requirements` (gap 2, with a real `libfakez.a`),
  `bt4-macro-loads-at-compile-time` (gap 3's `node-int` half),
  `bt4-header-format-refusals`.

### BT-5 — `nucleus` core

- **The `argv[0]` dispatch** (D-ENTRY), with subcommands `build`, `run`,
  `run-repl` and `clean`, and options `-j N`, `-O…`, `--target=`,
  `--library-paths=` (BT-8) and `--no-user-registry` (BT-8).
- **The configuration** (`nucleus.build.config`): a typed `BuildConfig` with
  `derive-edn` codecs. Every value is decoded with its file:line. Each file is
  decoded first, then the files are merged field by field using §8.9's table:
  maps recurse, scalars replace, requirements intersect, `unsafe/` keys
  replace with a warning, flag vectors append, and name sets union.
  Misspelled keys are errors in the file that has them.
- **Conventions** (D-CONV), and the project's source root on `-I` (§8.1).
- **The graph** (`nucleus.build.graph`): rules, edges, commands and
  dependency records. It is backend-neutral (Q2), and nothing emits it yet.
  The edges are one compile per executable, one per C source file, and the
  link.
- **The executor** (`nucleus.build.exec`):
  - staleness by D-STALE against `.nucleus-log.edn` and each edge's depfile;
  - a rebuild whenever the command hash or the compiler identity changes;
  - outputs written to a temporary file and renamed;
  - parallel edges through `spawn`/`wait-any`, up to `-j`;
  - on interrupt, killing the children and leaving no partial output.
- **`run`** builds and then hands the same flag vectors to the in-process
  `--run` path. **`run-repl`** hands them to `-i`. Neither re-derives the
  flags.
- **When zero-config can't decide** (an unannotated ambiguous header before
  BT-6, an unknown library root) and there is no `build.edn`, stop and say to
  run `nucleus init` (Q4).
- **Tests** (a new `tests/suite-build.nuc` with fixture projects under
  `tests/fixtures/build/`):
  - a zero-config project builds and runs;
  - a second `build` runs nothing;
  - changing `-O` rebuilds;
  - touching a source without changing it doesn't rebuild;
  - editing an imported file does rebuild;
  - `build-local.edn` `:cflags` append;
  - an `unsafe/` key warns;
  - a project with no main file gets a clear error.
- **Built**, with these departures:
  - **The config is decoded by hand**, not with `derive-edn`. The codecs need
    a tagged map with every field present, and they drop the line of each
    value, which every error here must name. `BuildConfig` holds a `Loc` per
    setting and per requirement set.
  - **Requirement sets are kept side by side in the merge**, not intersected
    there. They reach the compiler as `--c-require=[FILE LINE HEADER SPEC…]`,
    which intersects them with the annotations as it already intersects
    annotations. `:unsafe/pkg-config` becomes `--c-require-unsafe=`, which
    sets the header's annotations aside.
  - **The graph has one `nucleusc` edge that compiles and links**, after one
    `clang -c` edge per C file. A separate link edge waits for a project with
    more than one Nucleus object (BT-7). The C edges get `:cflags`, not the
    picked packages' cflags. Only `nucleusc`'s identity is tracked; a new
    clang is seen only through the command.
  - **`:c-sources` is a new key**, so that C edges exist to schedule.
  - **No interrupt handler.** `signal` is a Nucleus special form, not the libc
    call. Output to `.tmp` plus rename already leaves no partial output, and
    Ctrl-C reaches the children through the process group.
  - **`run` compiles in-process** with `--run`, without building first. A
    project with `:c-sources` is built and its binary run, because the JIT
    can't load a C object. `run-repl` passes `--c-requirements-of=<entry>`,
    a new flag, so `-i` resolves the closure's requirements as a compile does.
  - **The "run `nucleus init`" stop is BT-6.** Nothing detects an ambiguous
    header yet. `:kind :library` is refused until BT-7.
    `--library-paths=` and `--no-user-registry` are BT-8's.
  - **Fixtures are written into scratch** by the units, as BT-0 … BT-4's are,
    not committed under `tests/fixtures/build/`.
  - The default `-j` is `sysconf(_SC_NPROCESSORS_ONLN)`, reached with
    `unsafe/import-private`: the C importer counts POSIX's `_SC_*` names as
    private (compiler.md "What is skipped").
  Units: `bt5-zero-config-and-staleness`, `bt5-config-merge`,
  `bt5-unsafe-key-warns`, `bt5-refusals`, `bt5-run-c-sources-and-clean`.

### BT-6 — discovery and `nucleus init`

- **The header index:** for each package from `pkg-config --list-all`, its
  `--cflags-only-I` directories and the headers under them. Cached by
  D-CACHE.
- **Requirement-set resolution** (§8.8) in `nucleus.build.resolve`. Intersect
  each slot's sets, drop alternatives that aren't installed for the target,
  pick by the root project's order (then the nearest dependency, then by
  name), and check the picks' `Requires:` against the other slots, trying the
  next alternative if one fails. Print a note when a pick wasn't everyone's
  first choice. When nothing fits, give §8.8's error with provenance before
  any compile runs.
- **Discovery:** `--list-imports` over the closure. The `--diagnostics=edn`
  retry loop covers imports generated by macros.
- **`nucleus init`** writes `build.edn`. It records ambiguity choices, never
  writes a path outside the project, and points at `init-local` (BT-8) for
  siblings. Any later build with a `build.edn` path that leaves the project
  warns.
- **Tests:** two scratch `.pc` packages that both provide `fx/fx.h`. Cover:
  - ambiguous with no `build.edn` → the init message;
  - `init` writes one alternative and comments out the other;
  - an intersection that leaves exactly one package → builds without
    `init`;
  - an empty intersection → the early error with both sources named;
  - a pick that wasn't anyone's first choice → the note;
  - the same inputs twice → the same pick.
- **Built**, with these departures and decisions:
  - **The index holds directories, not headers.** For each package it stores
    the `--cflags-only-I` directories and its `Requires:` /
    `Requires.private:`. A lookup tests `<dir>/<header>`. The result is the
    same, the cache stays small, and a lookup never runs pkg-config. A header
    that clang's own include path (`clang -E -v`) or a `:cflags` `-I` finds is
    never looked up, so `stdio.h` is never a choice. A candidate that reaches
    the header only through another candidate it requires is dropped
    (gtk4 → glib.h).
  - **Ranks stand in for "nearest the root".** The order is: the config,
    then annotations in files under the project root, then other files'
    annotations (sorted by file), then the table, then the index. With no
    dependency graph until BT-8, "a dependency nearer the root" can't be told
    apart from any other dependency yet.
  - **A `Requires:` clash** is a pick that requires a package which another
    header's sets name but didn't pick. The search is depth-first over the
    headers in name order.
  - **No target check.** Resolution asks the host's pkg-config. Choosing
    "installed for the target" waits for the per-target work (BT-9).
  - **The `--diagnostics=edn` retry loop is not built.** A C import that a
    macro generates is still invisible to `--list-imports`, so only the
    compiler's own standalone resolution sees it. The loop moves to BT-8,
    where finding libraries needs it too.
  - **`init` refuses to overwrite a `build.edn`**, and doesn't edit one. A
    build that has a `build.edn` and meets an ambiguous header prints the
    entry to add instead. `init` keeps the first alternative by name. With
    no dependencies yet, there is nothing to send to `init-local`.
  - **Resolution runs on every `build`, `run` and `run-repl`**: one
    `--list-imports` (about 30 ms) and one `pkg-config --exists` per header.
    A warm no-op build against 268 packages takes 0.11 s. A cold index build
    takes about 2 s. The picks become `--pkg-config=` flags, so a change in
    what is installed changes the command and rebuilds. The compiler still
    checks the picks against the annotations (D-STANDALONE).
  - **A `:c-sources` path that leaves the project** is warned about without a
    line number, because the decoded vector carries none.
  Units: `bt6-requires-steer-the-pick` (the resolver with fake pkg-config),
  `bt6-ambiguous-header-and-init`, `bt6-intersection-picks`,
  `bt6-empty-intersection`, `bt6-single-provider-and-local-paths`.

### BT-7 — library projects and `nucleus install`

- **Library projects:** a `build.edn` with `:kind :library`, `:name`,
  `:version` and optionally `:provides`. If `:provides` is left out, it is
  derived from the top-level namespace directories under the source roots.
  Building a library compiles each public namespace file. It produces one
  `.nuch` and one `.h` per file (with `--library=`), the archive (and `.so`
  when `:shared`), and a build id.
- **`nucleus install`**, laid out as in §8.4:
  - options `--prefix`, `--user`, `DESTDIR` and `--target`;
  - per-target headers, archive, `.pc` file and manifest;
  - the source in `share/nucleus/src/<root>/`;
  - the manifest's `:files` list, used by `nucleus uninstall`.
- **Strict initializers:** installing turns the `-c` run-time-initializer
  warning into an error (§8.4).
- **Tests:** install a fixture library into a scratch prefix and check the
  tree. `pkg-config --cflags --libs` against the installed `.pc` must work.
  A C program compiles against the installed `.h` and links. `uninstall`
  leaves the prefix empty. An initializer the warning would flag fails the
  install.
- **Built**, with these departures and decisions:
  - **Every `.nuc` file under a provided root is public.** Nothing marks a
    file private yet. A derived `:provides` also takes the stems of the
    source root's top-level `.nuc` files (`src/fw.nuc` provides `fw`).
    `:provides` names must be top-level.
  - **The graph, per public file:** a `-c` object, a `.nuch`
    (`--library=NAME@VERSION --build-id=`) and a `.h`, each with its own
    depfile. Then `ar rcs` over every object, `:c-sources` included, and
    with `:shared` a `clang -shared` that links the picks' `pkg-config --libs`
    and `:libs`. The header modes now honor `-o`.
  - **Every library build is strict** (`--strict-initializers`, a new
    compiler flag), not only an install. So installing never rebuilds, and
    the error shows up at the first `build`.
  - **The build id** hashes the compiler id, the name and version, the
    flags except the source root's path, and each public file's path and
    contents. Library sources are passed relative to the project root, so
    neither the id nor a header's comment names the checkout. The executor
    now resolves a depfile's relative paths against the step's directory.
  - **Requirements over several files:** `--list-imports` runs once per
    public file, and the records are deduplicated by file, line and name.
    The same pass collects `:requires :nucleus`: the roots of Nucleus
    imports that the library doesn't provide. With no `:deps` until BT-8,
    these are roots, not library names.
  - **The `.pc` and the manifest** are written at install time, since both
    name the prefix. `Requires:` and the manifest's `:pkg-config` and
    `:libs` come from the built headers' `c-requires` lines, plus `:libs`.
    Manifest values are strings (`:name "fz"`, not `fz`), and `:files` holds
    absolute paths without `DESTDIR`.
  - **`<triple>` in the layout is the multiarch name**: the triple without
    its vendor (`x86_64-pc-linux-gnu` → `x86_64-linux-gnu`). The manifest's
    `:target` keeps the full triple. `--target=` picks the directory, but
    as in BT-6 nothing yet asks a target's pkg-config.
  - **`--no-source` refuses any header that exports a `defmacro`**, not
    only macros that call their own library. Telling them apart needs the
    callee analysis H4 also skipped. Deferred to the end of the stage
    (user, 2026-10-25), and listed under BT-11.
  - **A reinstall** removes the previous manifest's files first.
    **`uninstall`** takes the project's name, or `nucleus uninstall NAME`
    anywhere. It removes the listed files, then each directory that leaves
    empty, up to but not including the prefix.
  - `run` and `run-repl` refuse a library. `clean` now prunes every
    directory it empties under `:out-dir`.
  Units: `bt7-install-and-uninstall` (the tree, the `.pc` through
  `pkg-config`, a C consumer, reinstall, uninstall to an empty prefix),
  `bt7-strict-initializers`, `bt7-shared-destdir-and-refusals`.

### BT-8 — dependencies and lookup

- **`:deps` resolution in §8.5's order:**
  1. `build-local.edn`;
  2. `build.edn` (by name, or a path inside the project);
  3. the user registry, that is `library-paths.edn` plus every
     `--library-paths=`, skipped by `--no-user-registry` or
     `:user-registry false`;
  4. installed libraries: manifests, then `.pc` files that name a manifest,
     then include directories with `.nuch` before `.h`;
  5. the stdlib.

  Explicit `.h` imports are never swapped for a `.nuch` (Q6g).
- **Collisions and recursion.** Dependencies are resolved recursively, keyed
  by name. Two providers of one root are an error, and so is anything other
  than the stdlib providing `nucleus`. Requirement sets from every dependency
  feed into BT-6's resolver.
- **Provenance and `unsafe/`.** Print one line whenever a library resolves
  from `build-local.edn` or the registry. `unsafe/` keys are allowed in every
  file, a dependency's included, and always warn (Q6t).
- **`nucleus init-local`:** find sibling `../*/build.edn` files whose `:name`
  matches a dependency, write overrides into `build-local.edn`, and add it to
  `.gitignore` in a git repository.
- **Tests:**
  - each lookup tier wins over the ones after it;
  - `--no-user-registry` skips the default file;
  - two libraries providing `gtkw` → error;
  - a library providing `nucleus` → error;
  - a dependency's `unsafe/` key warns in the consumer's build;
  - `init-local` finds a sibling and updates `.gitignore`;
  - a transitive C requirement from a dependency narrows the consumer's pick.
- **Built**, with these departures and decisions:
  - **Lookup is by name for `:deps` and by root for an import.** An import
    that `--list-imports` reports with `:path nil` names a root. The tool
    finds a library providing it, puts that library's directory on `-I`, and
    lists again until nothing new turns up. A `:deps` entry is looked up by
    name. Within one place, two names providing one root are an error, like
    two in the build. `nucleus` named in `:deps` is skipped: the compiler's
    own stdlib is the one it reads, and BT-9 decides what an installed one
    changes.
  - **The first place that has a library wins**, even when its version
    doesn't satisfy a constraint. A mismatch is an error naming both, not a
    reason to look further.
  - **The macro-import retry is a new `--missing-imports=<file>` flag**, not
    a parse of `--diagnostics=edn`. A compile that can't find an import
    writes `{:name :file :line}` there and exits 3 without the error. The
    tool then builds the whole project again from the start, because the new
    library may bring C requirements and `:deps`. It records the import in
    `build/.nucleus-imports.edn` so that the next build starts with it. `run`
    without `:c-sources`, and `run-repl`, compile in-process and get no
    retry.
  - **A dependency's `unsafe/` set is rank-scoped.** It replaces the sets at
    its own rank and below, never its consumer's (`slot-used`): a
    dependency can't widen what the project asked for.
  - **The include tier uses `.nuch` hits only.** It links the archive that
    the header's `library` line names, if one is installed beside it, and
    checks nothing else. A `.h`-only hit isn't used, because a Nucleus
    import can't resolve to a C header.
  - **A dependency's `build.edn` contributes** its `:deps`, its `:pkg-config`
    sets (at `RANK-DEP`), its `:cflags` (with an `-I` joined to its
    directory) and its `:libs`. Its `:c-sources` only warn, since nothing
    builds them for a consumer yet. Its `build-local.edn` is ignored.
  - **Prebuilt use** checks the manifest's `:compiler` against this binary's
    hash and `:header-format` against 1. The archive is linked with
    `--link-arg=`, and the compiler's depfile now lists every file-valued
    `--link-arg`, so a reinstalled archive relinks the program.
  - **A program's roots are derived too** (`derive-roots`, now in
    `nucleus.build.lookup`), so a dependency that provides `helper` collides
    with `src/helper.nuc`.
  - **`init-local`** looks for the `:deps` names and the roots nothing
    provides. It refuses to overwrite a `build-local.edn` and prints the
    entries instead, and it adds the file to `.gitignore` when a `.git` is
    at or above the project.
  - The registry's `:libraries` must name the library its directory holds.
    Relative registry paths are relative to the registry file. The
    suite's environment now sets `HOME` too.
  Units: `bt8-lookup-order-and-init-local`,
  `bt8-collisions-and-dependency-unsafe-keys`,
  `bt8-dependency-c-requirement-narrows`, `bt8-macro-generated-import`,
  `bt8-dependency-unsafe-is-scoped`.

### BT-9 — the stdlib through `nucleus install`

- Give `lib/` a `build.edn` that declares the library `nucleus`. `make
  install` installs the compiler binary and the `nucleus` symlink, then runs
  `build/nucleusc install` in `lib/`. `make uninstall` delegates the same
  way.
- `try-import-path`'s last fallback moves to
  `$PREFIX/share/nucleus/src/`, and the compile-time library root
  (`ct-lib-root-note`) captures the installed source directory. Programs
  keep inlining the stdlib (Q6p), and `libnucleus.a` is installed for C
  consumers and opt-in use. `make lib-so` and `lib-objs` stay as the
  in-tree builds.
- `$NUCLEUS_LIB` keeps working as an extra search directory.
- **Tests:** install into a scratch prefix, then compile a program from an
  unrelated directory with the installed compiler and no `-I`. A C program
  links the installed `libnucleus.a` using `nucleus.pc`.
- **Built**, with these departures and decisions:
  - **`lib/build.edn` has `:source-root "."` and `:provides [nucleus]`**, so
    the test fixtures in `lib/*.nuc` stay out. All 52 files under
    `lib/nucleus/` compile with `--strict-initializers`, the AVR register
    files included. `tool-join` treats `"."` as the root itself.
  - **The unit's root under a second spelling is the root.** Built as a
    library, `nucleus/core.nuc` is re-entered by the auto-prelude through
    `-I`, as `<abs>/nucleus/core.nuc`. The compiler compared paths by
    spelling and defined everything twice. `resolve-import` now maps a hit
    to the root's own spelling when the basenames match and `realpath`
    agrees (`entry-spelling`).
  - **A library's `.edn` files under a provided root are installed** beside
    its sources. Every compile reads `nucleus/c-packages.edn` through the
    import search.
  - **The compiled-in fallback stays `/usr/local/share/nucleus/src/`**, not
    `$PREFIX/…`. The step beside the executable already finds any prefix's
    install, so compiling `PREFIX` in would add a build parameter and reach
    nothing new. `ct-lib-root-note` needed no change: it takes the
    directory `nucleus/core.nuc` was found under, which is now
    `share/nucleus/src`.
  - **Generated C headers label through `NUC_ASM`.** The C test, built with
    `cc`, which is GCC here, found that GCC writes an asm label into its
    assembly verbatim, where a hyphen must be quoted, while clang takes the
    label as the symbol. A header that needs a label defines `NUC_ASM` per
    compiler.
  - `make uninstall` runs the installed `nucleus`. `make install` builds the
    stdlib in `lib/build/`, which `.gitignore` already covers.

### BT-10 — prebuilt opt-in

- **Opting in:** `:deps {gtkw {:prebuilt true}}`, or a library installed
  with `--no-source`. Its manifest must match the build's `:target`,
  `:compiler` and `:header-format`. Otherwise fall back to source, with a
  note, or fail naming the mismatch if there is no source. An `unsafe/`
  widening that the prebuilt object can't satisfy also forces source (§8.6).
- **P11:** a compile-time source root separate from the import path
  (`--ct-source=<root>=<dir>`). The library is then imported from `.nuch` and
  linked, while its macros' callees are compiled from source into the JIT
  through the `import-ct` path (Q6h).
- **Refusing source-less macros:** `install --no-source` refuses a library
  whose headers export macros that call its own code.
- **Tests:**
  - §8.1 gap 3 in full: the macro calling `twice-of` works against the
    prebuilt library;
  - a mismatched compiler identity falls back to source;
  - `--no-source` together with a macro that calls library code → install
    refused;
  - a prebuilt library's `defvar` initializes once.
- **Built**, with these departures and decisions:
  - **`--ct-source` imports the source instead of the `.nuch`.** The plan
    read the header and also compiled the source for the JIT. One unit can't
    hold both, because the header's `declare`s and the source's `defn`s are
    the same names. Instead, an import under `ROOT` resolves to `DIR`'s
    `.nuc` and is imported compile-time-only, like `import-ct`. Its
    functions and `defvar`s are written to the program as `declare` and
    `external global`, and the object supplies them. Its own imports are
    compile-time-only unless the program imports them for real. The import
    graph's prescan skips it, as it skips `import-ct`.
  - **`import-ct`'s definitions are kept, not discarded** (`g-ct-def-buf`),
    and their spans are recorded with a buffer flag. The macro mirror copies
    one as it copies a program function. That is what gap 3 needed, and it
    also lifts the old rule that `import-ct` only worked for a library the
    compiler links.
  - **The tool passes `--ct-source`** only for a prebuilt library that has
    source and whose installed headers contain a `defmacro`. A library
    without macros is read from its `.nuch`. `--list-imports` doesn't get the
    flag, so C requirement discovery still sees the headers' recorded picks.
  - **The `unsafe/` rule is checked after resolution.** Each prebuilt
    header's C import records the package its object was compiled against.
    If the resolution picks another one, the library is forced to source with
    a note, and the dispatch reruns (`TOOL-RETRY`). With no source, the build
    stops with the same reason.
  - **The target check compares multiarch names**: the manifest's `:target`
    against the build's. Only a manifest found through a `.pc` file can
    differ, because the installed tier is already per target.
  - **The `--no-source` refusal is unchanged**: it still refuses any macro.
    Narrowing it to macros that call the library's own code is BT-11, at the
    user's request.
  - `run-repl` with a prebuilt macro library is untested: the REPL doesn't
    load archives.

### BT-11 — documentation and close-out

- **`docs/build.md`:** the commands, conventions, `build.edn` and
  `build-local.edn` reference, lookup order, requirement sets, `unsafe/`
  keys and the install layout. Update `docs/compiler.md` for the new flags
  and the header format, and `docs/index.md`.
- **Context files:** `context/build.md` for the `nucleus` symlink and the new
  `make install`.
- **Revisit `--no-source`** (deferred from BT-7 by the user, 2026-10-25). It
  refuses any library whose headers export a `defmacro`. §8.4 asks it to
  refuse only one whose macros call the library's own code.
- **Charge:** a walkthrough taking `../charge.nuc` from its four-line build
  comment to `nucleus build`. Applying it to that project is the user's call,
  because it lives outside this repository.
- **Built**, with these departures and decisions:
  - **The walkthrough is a section of `docs/build.md`** ("Example: a GTK
    program"), not a separate document. It has not been applied to
    `../charge.nuc`, and gtk4 isn't installed in the container.
  - **The §6 fixtures are units.** `bt11-charge-shaped-build-run-repl` uses a
    fake `fgtk` C library with a `.pc` file. `bt11-two-libraries-install-and-override`
    covers install, prefix resolution and the `init-local` override.
  - **A REPL bug found on the way, and fixed.** Importing a file whose
    `defvar` holds a collection literal failed with an undefined
    `@nuc_init…`. The cause was that the initializer ran inside the import's
    own module, before the stamp it called existed. The bug was already at
    HEAD. Initializers now run from a module of their own, after the
    import's declares are in the preamble (`src/repl.nuc`, G-3).
  - **`--no-source` refuses only a macro that runs the library's own code**
    (option B, ruled by the user 2026-10-25). The other options were to keep
    refusing any macro, or to install the source of just the files the macros
    reach. A library compile already compiles every `defmacro`, and its
    `ct-roots` are what the macro calls minus what the host provides.
    `ProgDefn` and `ProgGlobal` now record their namespace and source name.
    The `.nuch` gets `(macro-calls M [ns/name …])` for each root not from the
    stdlib. Install refuses when a name's root is in `:provides`, or when the
    name is bare, meaning a file without `ns`. A dependency's callee is
    allowed, because its own source is installed. Only direct roots are
    checked, since nothing the library depends on can call back into it. The
    tool still passes `--ct-source` for any prebuilt `defmacro`, which is
    harmless.

## 4. Testing

Every build-tool unit runs in a scratch directory with its environment
pinned:

- `PKG_CONFIG_LIBDIR` set to scratch `.pc` files, so installed system
  packages don't change results;
- `XDG_CONFIG_HOME`, `XDG_CACHE_HOME` and `HOME` set to scratch directories;
- installs go to `--prefix` under scratch.

C fixture libraries are built the way `probe-library` already builds
`libnucprobe.so`. pkg-config is required, and its units skip with a message
when it's missing, as `s21-repl-pkg-config` does. The container has pkgconf
1.8.1, and Arch uses pkgconf too.

## 5. Risks

- **The boot compiler.** `lib/nucleus/build/` becomes part of `nucleusc`, so
  it is compiled by `bin/nucleusc`. Anything it uses that the committed boot
  compiler doesn't support needs a boot refresh first (`context/build.md`,
  bootstrap convergence). Each phase should stay inside what the boot
  compiler already compiles.
- **The REPL hand-off.** `run-repl` applying configuration in-process depends
  on the REPL's build-line state (`src/repl.nuc`, "The build line at the
  prompt"). BT-3's move of the pkg-config logic is where that state gets a
  library-level API. If it doesn't fit, `run-repl` falls back to issuing the
  meta forms as REPL input, which works but is clumsier.
- **pkg-config output.** pkgconf and freedesktop pkg-config differ in edge
  cases (ordering, `--list-all` format). BT-6's index parses defensively and
  is tested against pkgconf only.
- **Header-format churn.** H1 makes every header that imports a C header
  load that header for its consumers too. This is correct, but the
  consumer's compile then pays for `clang -E` on those headers, which it
  didn't before.

## 6. Done means

`../charge.nuc` (or a fixture shaped like it: one GTK-style annotated import
and three stdlib imports) builds with `nucleus build`, runs with
`nucleus run`, and opens a configured REPL with `nucleus run-repl`, all with
no `build.edn` and no flags. A two-library fixture installs, resolves from
the prefix, and is overridden by a sibling through `init-local`. The suite
passes, and the bootstrap reaches its fixed point.

## 7. Not in this plan

These are deferred by a ruling or left out of scope:
- fetching dependencies over the network;
- a Ninja or other backend emitter (Q2 shapes the graph for one);
- the `build.nuc` escape hatch (Q5);
- revisiting the one-binary decision (Q1);
- shared or universal installs (Q6j);
- LTO;
- non-Linux install layouts;
- a `nucleus test` subcommand, which wasn't discussed and would be a small
  follow-on over `nucleus.test`.
