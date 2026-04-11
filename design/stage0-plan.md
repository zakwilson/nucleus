# Nucleus stage-0 compiler

## Context

Nucleus is a new systems programming language (Lisp syntax, LLVM target, C replacement) defined in `overview.md`. The project is a clean slate. `initial.md` specifies a concrete target program that the initial implementation must compile and run to the exact expected output:

```
(include stdio)

(defn main:int ()
  (let (i:int 1
        j:int 2)
    (while (< i 5)
      (printf "i = %d j = %d\n" i j)
      (inc! i)
      (set! j (* 2 i))))
  (return 0))
```

Expected stdout: four lines `i = 1 j = 2` ... `i = 4 j = 8`.

This plan builds a stage-0 compiler sufficient for that program and nothing more. Stage-0 is **throwaway scaffolding** that will be deleted once Nucleus can self-host.

## Decisions

- **Host language:** C (single `src/nucleusc.c`)
- **LLVM interface:** emit textual `.ll` to stdout, shell out to `clang foo.ll -o foo`
- **`(include stdio)`:** hardcoded declaration table (just `printf`)
- **Container:** `clang`, `llvm`, and `lld` added to `/home/node/claude-container/Dockerfile`; rebuild required before implementation.

## Project layout

```
nucleus/
├── src/nucleusc.c          single-file stage-0 compiler (~800–1200 LOC)
├── Makefile                builds build/nucleusc; `make test` target
├── build.sh                driver: .nuc → nucleusc → .ll → clang → binary
├── examples/hello.nuc      verbatim target program from design/initial.md
├── tests/run-tests.sh      runs each example, diffs against expected
├── tests/expected/hello.out  the 4 expected output lines
├── design/stage0-plan.md   this file
└── .gitignore              build/, *.ll, /hello
```

## Stage-0 compiler architecture

**Memory.** Single bump-arena (`arena_alloc`, `arena_strdup`, `arena_printf`). No `free`. Leak on exit.

**Lexer.** Tokens: `LPAREN`, `RPAREN`, `INT`, `STRING`, `SYMBOL`, `EOF`. Each token carries a `line` for error messages. **The tokenizer does not split `name:type`** — it's one `SYMBOL` token; the colon is split out later by the code consuming a typed binder. This makes `<`, `*`, `inc!`, `set!`, `i:int`, `main:int` all ordinary symbols.

**Reader → AST.** Tagged-union `Node { kind, line, i | s | list{items,len} }`. Lists store children as a flat `Node**`. No separate typed IR.

**Symbol table.** Lexically nested scopes (global → function → let). `Sym { name, type, ir_name, is_local }`. Types: `TY_VOID`, `TY_I32`, `TY_I8PTR`, `TY_VARARGS_FN` with return + fixed params + variadic flag. `int` → `i32`.

**Special forms:** `include`, `defn`, `let`, `while`, `set!`, `inc!`, `return`. Body sequences (for `defn`/`let`/`while`) are implicit `do` — the codegen emits each expression in order.

**Builtin operators** (special-cased at the call-head dispatch before function lookup): `<` → `icmp slt i32`, `*` → `mul nsw i32`. That's all stage-0 needs.

**Deferred (explicitly NOT in stage-0):** macros, pointers, structs, arrays, floats, unsigned, `if`, user-defined function calls, multiple functions, diagnostics beyond `error at line N`, optimization, debug info, real header parsing.

## LLVM IR codegen — key details

- **Mutable locals = alloca + load/store.** `inc!`/`set!` mutate `i` and `j`, so they live in `alloca` slots, not SSA values. Every read emits `load`, every write emits `store`. No phi nodes anywhere. Standard clang-frontend approach.
- **All allocas in the entry block.** Codegen keeps a separate "entry block" pointer; alloca emissions are buffered there, everything else goes to the current block. Preserves the LLVM `mem2reg` invariant even though stage-0 runs no passes.
- **SSA naming:** per-function monotonic `%t0, %t1, …` for temporaries; named slots `%i.addr`, `%j.addr` for allocas; semantic block labels `entry`, `while.cond`, `while.body`, `while.end` (suffixed with a counter to allow future nesting).
- **`int` = `i32`.** Matches `%d` in `printf`, matches C `int` on x86-64 Linux, avoids casts.
- **String literals.** Collected into a module-level table, emitted as `@.str.N = private unnamed_addr constant [L x i8] c"...\00"`. **The length `L` must be computed by the emitter as `strlen(decoded) + 1` — never hand-counted.** Escape decoding: `\n`→`\0A`, `\t`→`\09`, `\\`→`\5C`, `\"`→`\22`, other non-printables→`\HH`.
- **`(include stdio)`** appends `declare i32 @printf(i8*, ...)` to the module preamble and installs a `printf` symbol with `variadic=true`.
- **Variadic call site** must include the functional type: `call i32 (i8*, ...) @printf(i8* %fmt, i32 %a, i32 %b)`. Forgetting the `i32 (i8*, ...)` is an LLVM parse error. Return value of `printf` is named-and-dropped.
- **`while` layout:**
  ```
  br label %while.cond
  while.cond:
    %c = load i32, i32* %i.addr
    %t = icmp slt i32 %c, 5        ; slt, NOT sle — off-by-one risk
    br i1 %t, label %while.body, label %while.end
  while.body:
    ...body...
    br label %while.cond
  while.end:
    ...
  ```
- **`(< i 5)`** feeds `icmp slt` directly into `br i1` — no `zext` needed since `<` only appears in condition position in stage-0.
- **`inc! i`** → `load`, `add nsw i32 _, 1`, `store`. Special-cased; we don't have generic `+` yet.
- **`(return 0)`** → `ret i32 0`. Codegen tracks `current_block.terminated` to avoid double-terminators once more forms are added.

### Hand-traced target IR

Hand-verified against the expected output by simulating 5 iterations (loop exits when `i=5`). Temporary numbering is illustrative — any consistent numbering works.

```llvm
@.str.0 = private unnamed_addr constant [15 x i8] c"i = %d j = %d\0A\00", align 1

declare i32 @printf(i8*, ...)

define i32 @main() {
entry:
  %i.addr = alloca i32, align 4
  %j.addr = alloca i32, align 4
  store i32 1, i32* %i.addr, align 4
  store i32 2, i32* %j.addr, align 4
  br label %while.cond

while.cond:
  %t0 = load i32, i32* %i.addr, align 4
  %t1 = icmp slt i32 %t0, 5
  br i1 %t1, label %while.body, label %while.end

while.body:
  %t2 = load i32, i32* %i.addr, align 4
  %t3 = load i32, i32* %j.addr, align 4
  %t4 = getelementptr inbounds [15 x i8], [15 x i8]* @.str.0, i64 0, i64 0
  %t5 = call i32 (i8*, ...) @printf(i8* %t4, i32 %t2, i32 %t3)
  %t6 = load i32, i32* %i.addr, align 4
  %t7 = add nsw i32 %t6, 1
  store i32 %t7, i32* %i.addr, align 4
  %t8 = load i32, i32* %i.addr, align 4
  %t9 = mul nsw i32 2, %t8
  store i32 %t9, i32* %j.addr, align 4
  br label %while.cond

while.end:
  ret i32 0
}
```

String length: `i = %d j = %d\n` is 14 decoded bytes + NUL = **`[15 x i8]`**.

## Build driver

`build.sh` takes a `.nuc` file, runs `make` to build `build/nucleusc`, pipes source through the compiler to produce `<base>.ll`, then runs `clang <base>.ll -o <base>`. Compiler writes IR to **stdout**, errors to **stderr**, exits non-zero on failure. `clang` acts as the linker; libc is picked up automatically so `printf` just works.

## Testing

`tests/run-tests.sh` iterates `examples/*.nuc`, builds each, runs the binary, diffs stdout against `tests/expected/<name>.out`. Plain `diff -u`, no framework. `make test` is the entry point.

Optional smoke check: `clang -S file.ll -o /dev/null` to verify the IR parses before running.

## Files to create / modify

| Path | Purpose |
|---|---|
| `/home/node/claude-container/Dockerfile` | **Done.** `clang`, `llvm`, `lld` added; rebuild required. |
| `src/nucleusc.c` | Stage-0 compiler: arena, lexer, reader, symbol table, codegen, main. |
| `Makefile` | Builds `build/nucleusc` with gcc; `make test` target. |
| `build.sh` | Driver: `.nuc` → `.ll` → executable. |
| `examples/hello.nuc` | Target program copied verbatim from `design/initial.md`. |
| `tests/run-tests.sh` | Test runner. |
| `tests/expected/hello.out` | Four expected output lines. |
| `design/overview.md` | Add pointer to `stage0-plan.md`. |
| `context/local.md` | Note that LLVM/clang was added to the container. |
| `.gitignore` | `build/`, `*.ll`, `*.o`, `/hello`. |

## Implementation order

Each step ends in a runnable state.

1. **Dockerfile + rebuild.** Add `clang llvm lld` to apt install list. User rebuilds container. Verify `clang --version` works.
2. **Skeleton.** `Makefile` + `nucleusc.c` that reads a file and prints it. Verifies build setup.
3. **Arena + lexer.** Dump tokens for `hello.nuc` as a sanity check.
4. **Reader.** Dump the AST back out as s-expressions to verify round-trip.
5. **Minimal codegen.** Hardcode `(defn main:int () (return 0))` end-to-end: `build.sh examples/empty.nuc` produces a binary that exits 0. **First "it runs" milestone.**
6. **`include stdio` + string table + bare `(printf "hello\n")`.** First runtime output.
7. **`let` with alloca/store; locals referenced inside `printf`.** Variable interpolation.
8. **`<` + `while` block plumbing.** Without `inc!` this loops forever — useful, confirms the branch.
9. **`inc!`, `*`, `set!`.** Full target program matches expected output.
10. **Wire `tests/run-tests.sh`**, add `hello.out`, `make test` green.
11. **Update `design/overview.md`** to link this plan; note LLVM addition in `context/local.md`.

## Verification

End-to-end success criteria, all of which must hold before considering stage-0 done:

1. `make` builds `build/nucleusc` with no warnings under `-Wall -Wextra -Wpedantic`.
2. `./build.sh examples/hello.nuc` exits 0 and produces `hello.ll` + `hello`.
3. `./hello` prints exactly:
   ```
   i = 1 j = 2
   i = 2 j = 4
   i = 3 j = 6
   i = 4 j = 8
   ```
4. `make test` reports `PASS hello`.
5. `clang -S hello.ll -o /dev/null` succeeds (IR is well-formed).
6. `design/overview.md` references this file.

## Risks / gotchas flagged up front

- **Off-by-one:** use `icmp slt`, not `sle`. Easy way to produce 5 lines instead of 4.
- **String length:** the `[L x i8]` size must be computed from the decoded string + NUL by the emitter. Do not hand-count.
- **Variadic call site:** the `i32 (i8*, ...)` functional type between `call` and `@printf` is required; omitting it is an LLVM parse error.
- **Entry-block alloca discipline:** even though stage-0 runs no passes, keep allocas in `entry` so `mem2reg` works for free later.
- **Double terminators:** assert `!current_block->terminated` before every emission. Stage-0 won't trip it, but it catches bugs the moment `if`/nested `while` arrive.
