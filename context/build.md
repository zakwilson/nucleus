## Nucleus build flow

- `make` compiles `src/nucleusc.nuc` using the committed bootstrap binary `bin/nucleusc`, producing `build/nucleusc` (the self-hosted compiler).
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
