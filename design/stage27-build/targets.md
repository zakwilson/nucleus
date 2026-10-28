# Building for several targets

**Status: proposed 2026-10-28; Q1–Q5 ruled the same day (§5); MT-1 … MT-6 built 2026-10-28, uncommitted (§8).**

## 1. The request

The user noted that a project builds for one target at a time. Modern projects
support several, and a release build usually produces one build per
supported target.

## 2. What exists

- **One target per project.** `build.edn` has a single `:target` (a triple
  string), and `--target=TRIPLE` overrides it (`tool-target`,
  `src/build-tool.nuc`). The compiler's own target options, `--mcpu=`,
  `--mmcu=`, `--sysroot=` and `--linker=`, aren't reachable from the tool,
  so an AVR or cross-Linux project can't be described in `build.edn` at all.
- **Outputs don't depend on the target.** The program is `build/<name>`.
  Objects go to `build/obj/` and a library's headers and archive to
  `build/include/` and `build/lib/`, whatever the target. Building a second
  target overwrites the first. Switching back and forth rebuilds everything,
  because `--target=` is part of each edge's command hash ("command
  changed").
- **C requirements are resolved against the host.** `tool-resolve` asks the
  host's `pkg-config`. The header index reads the include path from a host
  `clang -E -v` (`lib/nucleus/build/index.nuc`). The overview already noted
  that a cross build must point `pkg-config` at the target
  (`PKG_CONFIG_LIBDIR`, `PKG_CONFIG_SYSROOT_DIR`, overview.md §8.3.1).
  plan.md BT-6 and BT-9 deferred this.
- **Installs and lookup are already per target.** `nucleus install
  --target=` writes the multiarch layout (`$PREFIX/lib/<triple>/…`,
  `$PREFIX/include/<triple>/…`, overview.md §8.4). Finding an installed
  library compares multiarch names (`tool-installed-libs`). This half needs
  only to be called once per target.
- **The compiler supports five backends:** X86, AArch64, ARM, AVR and RISCV
  (docs/compiler.md, `--target=`). Compile-time code always runs on the
  host. A macro that calls the program's own code is refused under a
  cross target.
- **`run`, `run-repl` and `repl` never check that the target can run here.**
  They pass `--target=` to an in-process JIT session, which only makes sense
  for the host.
- **Source can't branch on the target.** No form gives Nucleus code the
  triple at compile time. Only a C header's `#if`s see it.

## 3. How others do it

- **Cargo** keeps the host build in `target/<profile>/` and a `--target`
  build in `target/<triple>/<profile>/`. `--target` can be given several
  times. `[target.<triple>]` tables in its config set the `linker` and a
  `runner` (an emulator such as `qemu-aarch64`) per target, and
  `[target.'cfg(windows)'.dependencies]` makes a dependency conditional.
- **Zig's** `build.zig` is code, and a release build is a loop over target
  queries, one install step per target.
- **Go** sets the target with `GOOS`/`GOARCH`. Release tools such as
  goreleaser read a target matrix from a file and build each.
- **Meson and CMake** use one build directory per cross file or toolchain
  file, and a script drives the matrix.

The shared pattern is: a target is a named bundle of settings, every target
gets its own output directory, and one command builds the whole set.

## 4. Proposal

### 4.1 Named targets

`build.edn` gains `:targets`, a map from a name to that target's settings.
Every target needs a `:triple`.

```clojure
{:name "blink"
 :targets {linux-x64   {:triple "x86_64-pc-linux-gnu"}
           linux-arm64 {:triple "aarch64-linux-gnu"
                        :sysroot "/usr/aarch64-linux-gnu"
                        :runner ["qemu-aarch64" "-L" "/usr/aarch64-linux-gnu"]}
           uno         {:triple "avr" :mcpu "atmega328p" :mmcu "atmega328p"
                        :c-sources ["src/avr/vectors.c"]}}
 :default-target linux-x64}
```

A target needs a name, not just a triple, because two builds can share a
triple and differ in everything else. AVR shows this: two boards are the
same `avr` triple with different `:mcpu` values. `:target` goes away
(pre-release), and `:default-target` takes its place.

### 4.2 What a target sets

- **New keys, valid only inside a target:** `:triple`, `:mcpu`, `:mmcu`,
  `:sysroot`, `:linker`, `:runner`. Each maps to the compiler option of the
  same name. `:sysroot` also becomes the sysroot of the link and of
  `pkg-config` (§4.6), and `:runner` is used by `run` (§4.8).
- **Existing keys that may also appear inside a target:** `:opt`,
  `:cflags`, `:link-args`, `:libs`, `:c-sources`, `:pkg-config`, `:deps`,
  `:shared`.
- **Merge rule:** a target's settings merge over the top level by
  overview.md §8.9's per-field rules, so the common settings are written
  once. Flag vectors append, `:libs` unions, maps merge by key, scalars
  replace, and a requirement set for a header the top level already names
  narrows. A target can still name a package for a header the top level
  doesn't mention. `build-local.edn` can carry a
  `:targets` map too, which merges into the same target by name. That is
  where a machine-specific `:sysroot` belongs.
- **Not settable per target:** `:name`, `:kind`, `:version`, `:entry`,
  `:source-root`, `:out-dir` and `:provides`. The decoder refuses any of
  them inside a target, naming the key.

### 4.3 Choosing what to build

- **`nucleus build`** builds the default target: `:default-target` if it is
  set, otherwise the host (the triple-less build that exists today).
- **`--target=NAME`** builds a named target. `--target=TRIPLE` still works
  for an unnamed one-off build, with no settings beyond the top level. A
  name is looked up first, and a value that names no target is taken as a
  triple (built: the `-` test was dropped, since `avr` is a whole triple).
- **`--target=` may be repeated**, and **`--all-targets`** builds every
  target in `:targets`. `build`, `clean` and `install` accept both.
- **`run`, `run-repl` and `repl` take one target.**

### 4.4 Output layout

The default target keeps today's paths: `build/<name>`, `build/obj/`,
`build/include/`, `build/lib/`. A named target writes under
`build/<target>/`, with the same layout inside it: `build/uno/blink`,
`build/uno/obj/…`. So `nucleus build && ./build/app` keeps working, and
every target's outputs coexist. This is Cargo's split.

When `:default-target` names a target, that target uses `build/<target>/`
like the others, and `build/<name>` doesn't exist. The alternative, that
the default always gets `build/`, would make the same target's path depend
on whether it is the default. Q3 ruled it out.

### 4.5 One graph, one log

`--all-targets` adds every target's edges to one `Graph`, so `-j` schedules
across targets, and the slowest target sets the wall time rather than the
total. The build log is keyed by output path, and the paths no longer
collide, so one log serves every target. Switching targets rebuilds nothing.

### 4.6 C requirements per target

Resolution runs once per target. Two things in it change:

- **`pkg-config` runs with the target's environment.** With a `:sysroot`,
  `PKG_CONFIG_SYSROOT_DIR` is the sysroot, and `PKG_CONFIG_LIBDIR` is
  `<sysroot>/usr/lib/<multiarch>/pkgconfig:<sysroot>/usr/lib/pkgconfig:<sysroot>/usr/share/pkgconfig`.
  Without a sysroot, a cross target uses the host's `pkg-config`, with
  `PKG_CONFIG_LIBDIR` set to the target's multiarch directories under `/usr`
  (Debian's cross layout). The host target is unchanged.
- **The header index asks the target's `clang`:** `clang --target=T
  [--sysroot=S] -E -v`. Choosing "installed for the target", which BT-6
  left open, then follows.

A target with no C requirements never runs either. An AVR or bare-metal
target usually has none.

### 4.7 Dependencies

`:deps` merges per target like any map, so a dependency can be specific to
one target. Lookup (§8.5) already filters by multiarch name, and installed
libraries are found per target. A dependency compiled from source is
compiled once per target, into that target's directory.

### 4.8 `run`, `run-repl` and `repl`

- **`run` for the host** is unchanged.
- **`run` for another target** builds it and runs the binary through the
  target's `:runner`. With no runner, it is refused, naming the target and
  saying that `:runner` sets one.
- **`run-repl` and `repl` are refused for any target that isn't the host.**
  Their JIT runs on the host. (A target whose triple is the host's counts
  as the host.)

### 4.9 `install`

`nucleus install --all-targets` installs every target's tree under its
multiarch directories. The source is installed once. One manifest is
written per target, as today. Two named targets with the same multiarch
name, such as two AVR boards, would install over each other, so `install`
refuses that and names both.

### 4.10 When one target fails

`--all-targets` stops scheduling new edges at the first failure, as one
build does today, and reports which target failed. A missing cross
toolchain is caught before any compile runs: a `:linker` or `:runner` that
isn't on `PATH`, or a `:sysroot` that doesn't exist. The error names the
target and the missing tool. Partial release builds are not useful, so
there is no keep-going mode for now.

## 5. Rulings (2026-10-28)

- **Q1. Named targets (§4.1), not a vector of triples.** Ruled: named.
- **Q2. What a plain `nucleus build` builds.** Ruled: the default target,
  which is `:default-target` if it is set, and otherwise the machine
  building it (the host). `--all-targets` builds the whole set.
- **Q3. Where outputs go.** Ruled: a named target always writes
  `build/<target>/`, including when it is `:default-target`. The host
  build keeps `build/`.
- **Q4. Branching on the target in source.** Deferred, and recorded in
  deferred/overview.md. The user pointed at Clojure's reader conditionals
  (`#?(:clj … :cljs …)`) as a mechanism Nucleus may want to imitate.
  Until then, per-target `:c-sources` and `:deps` split a project by whole
  files.
- **Q5. Release profiles.** Deferred, and recorded in deferred/overview.md.
  `-O0` and `-O3` builds of one target still share outputs.

## 6. Not in this design

- packaging release artifacts (archives or checksums per target);
- universal (multi-architecture) binaries and shared headers across targets,
  which overview.md §8.4 already deferred;
- predicate matching such as Cargo's `cfg(windows)`, so one setting can
  cover all Linux targets (named targets come first, and a `:when` predicate
  can be added later);
- a Windows host. Cross-compiling to Windows triples resolves in LLVM, but
  the stdlib's process and file modules are POSIX-only.

## 7. Phases

- **MT-1. Config.** `:targets`, `:default-target`, the target-only keys and
  their refusals, merge over the top level and from `build-local.edn`, and
  removing `:target`. The tool passes `--mcpu=`, `--mmcu=`, `--sysroot=` and
  `--linker=` through. *Tests:* decode and merge units; an AVR target that
  builds to `build/uno/` with the `nucprobe` pattern from
  `suite-target.nuc`.
- **MT-2. Layout and selection.** A per-target out dir, repeated
  `--target=` and `--all-targets`, one graph, one log. *Tests:* two targets
  built together, then each rebuilt alone with nothing stale; `clean
  --all-targets`.
- **MT-3. C requirements per target.** `pkg-config` environment from
  `:sysroot`, a target-aware header index, and the toolchain preflight
  (§4.10). *Tests:* a fake sysroot with a `.pc` file the host lacks, which
  resolves only for the target that names it.
- **MT-4. Dependencies per target.** Per-target `:deps` and per-target
  source builds of dependencies. *Tests:* a dependency used by one target
  only.
- **MT-5. `run` and the REPLs.** `:runner`, and the refusals for `run-repl`
  and `repl`. *Tests:* a runner script that records its arguments; the
  refusal messages.
- **MT-6. `install --all-targets`.** The multiarch collision refusal.
  *Tests:* two targets installed under one prefix, then each found by a
  consumer.

The gate for each phase is the usual one: `make test` with the new units, a
`make bootstrap` fixed point, and docs/build.md updated.

## 8. Built (2026-10-28)

- **MT-1.** `BuildConfig` lost `:target` and gained the target-only keys,
  `:default-target` and `:targets` (a `TargetConfig` per name, each holding a
  `BuildConfig`). One decoder, `config-decode-map`, serves a file's top level
  and a target's body. `config-misplaced` refuses a key in the wrong scope.
  `config-merge` merges targets by name. The chosen target's settings merge
  over the project's in `tool-select-target`, so everything downstream reads
  one effective config. `tool-flags` passes `--mcpu=` and `--sysroot=`, and
  when linking `--mmcu=`, `--linker=` and `--link-arg=--sysroot=`. A JIT
  session (`run`, `run-repl`, `repl` on the host) gets none of the target
  flags, since `nucleusc --run` refuses `--target=`. C sources get clang's
  spelling: `-mmcu=` on AVR, `-march=` on x86, otherwise `-mcpu=`.
- **MT-2.** Each target's outputs, log and seeds live in `build/<target>/`.
  `Edge` gained `log`, and `exec-graph` keeps one `LogSet` entry per log it
  meets, so one graph spans targets and each keeps its own log. That way
  cleaning one target never marks another stale. `tool-missing-retry` takes
  a target's edge range.
- **MT-3.**
  - **pkg-config's environment** is set in the process around each target's
    resolution and graph construction (`tool-env-push`/`pop`). It is also
    set per edge through `Edge.env`, which is in the command hash, because
    edges from several targets run at once. The environment goes out as
    pairs of a name and a value.
  - **The header index** is reloaded when the triple or sysroot changes.
    `header-index-load` takes them, and the cache file is named by a hash of
    its pkg-config key.
- **MT-4** needed no code beyond the merge. A target's `:deps` reach
  `tool-discover` through the effective config. A dependency's own
  `build.edn` targets aren't consulted, because target names belong to the
  project that declares them.
- **MT-5.** A target with a `:runner` always runs built. That includes a
  host target, so a runner such as `valgrind` works there. A relative runner
  path resolves against the project.
- **MT-6.** `install --all-targets` builds every target in one graph, then
  installs each. `uninstall` also accepts `--all-targets`.
  `uninstall NAME --target=` stays a triple.
- **Tests** (`tests/suite-build.nuc`): `mt1-targets-config`,
  `mt2-all-targets-one-graph`, `mt3-sysroot-pkg-config`, `mt4-target-deps`,
  `mt5-runner-and-refusals`, `mt6-install-all-targets`. AVR is the cross
  target throughout, because the container has `avr-gcc` but no riscv64 C
  runtime files (`Scrt1.o`), so a riscv64 link can't be tested here. The
  runner is a script that records its arguments.
