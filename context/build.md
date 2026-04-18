## Nucleus build flow

- `make` compiles `src/nucleusc.nuc` using the committed bootstrap binary `bin/nucleusc`, producing `build/nucleusc` (the self-hosted compiler). The build also compiles `src/repl_shim.c` (setjmp/longjmp wrapper for REPL error recovery) and links it with the compiler.
- `bin/nucleusc` is a pre-built ELF binary committed to the repo. `boot/nucleusc.ll` is the corresponding LLVM IR.
- If `bin/nucleusc` is missing or broken, rebuild it: `make boot-binary` (compiles `boot/nucleusc.ll` with clang).
- `./build.sh examples/foo.nuc` runs `make`, then compiles the source file with `build/nucleusc`. Compile-time output goes to **stderr**; IR to **stdout**.
- `make test` runs `tests/run-tests.sh`, which diffs each example's **runtime** output against `tests/expected/<name>.out`. Compile-time stderr is ignored by the test harness.
- `make bootstrap` does the fixed-point test: stage1.ll == stage2.ll.
- The compiler emits **opaque-pointer** LLVM IR (`ptr`, not `i8*`/`i32*`) and hardcodes `target triple = "x86_64-pc-linux-gnu"`. If the dev environment ever moves off x86_64 Linux the triple will need updating.
- The self-hosted compiler and its bootstrap artifacts are linked with `-lLLVM-19 -ldl`. The Makefile uses `llvm-config` for flags.

## Updating bootstrap artifacts

Run `make update-bootstrap` **only at a stable milestone**:
- All tests must pass (`make test`)
- Bootstrap fixed-point must hold (`make bootstrap`)
- The compiler must be in a usable, non-broken state

This updates both `boot/nucleusc.ll` (IR) and `bin/nucleusc` (binary) from the current `build/nucleusc`. Never update them with failing tests or mid-feature work.

## Import system

- `(import name)` resolves `name.nuc` or `name.nuch` by searching: (1) directory of the importing source file, (2) `lib/` relative to cwd. `.nuc` is tried first.
- Source imports (`.nuc`) are source inlines — the imported file's forms are read, parsed, and processed into the current compilation's IR streams.
- Header imports (`.nuch`) emit LLVM `declare` for functions (resolved at link time from `.o` files), and process `defstruct`, `defconst`, `defenum`, and `defmacro` normally.
- Duplicate imports (same resolved path) are silently skipped.
- Circular imports are detected and produce an error.
- Reader state (`g-src`, `g-pos`, `g-line`, `g-source-path`, `g-peek`, `g-peek-valid`) is saved/restored around each import.
- New libc functions (e.g. `getenv`, `realpath`) cannot be used in compiler source until the bootstrap binary is updated, because the bootstrap compiler's libc table won't know them. Use workarounds with existing libc functions, then add the proper versions after `make update-bootstrap`.

## .nuch headers and library compilation

- `nucleusc --emit-nuch file.nuc` outputs a `.nuch` header (S-expression declarations) instead of LLVM IR.
- `make lib-headers` generates `.nuch` for all `lib/*.nuc` files.
- `make lib-objs` compiles all `lib/*.nuc` to `.o` via `nucleusc` → `llc -filetype=obj -relocation-model=pic`.
- `make lib` does both headers and objects.
- Only self-contained libraries (e.g. `mathlib.nuc`) can be compiled to standalone `.o` files. Libraries that reference external globals (e.g. `arena.nuc` needs `g-arena`) are designed for source inlining via `import` and cannot be compiled independently.
- To use a header-only import: generate `lib/foo.nuch` and `build/lib/foo.o`, then programs using `(import foo)` will find the `.nuch` and emit `declare` statements. Link the program's `.ll` against `foo.o` with clang.
