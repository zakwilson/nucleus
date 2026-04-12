# Self-host the Nucleus compiler

## Context

Today the Nucleus compiler is a 962-line C program (`src/nucleusc.c`) that compiles exactly one program (`examples/hello.nuc`) and was built as explicitly-throwaway stage-0 scaffolding. The design (`design/stage0-plan.md`) calls it out as such: "will be deleted once Nucleus can self-host."

The user's goal is to replace this C compiler with a Nucleus compiler written in Nucleus, **as soon as possible**. "As soon as possible" is the load-bearing constraint — it pushes us toward the minimum viable self-host, not toward a polished language.

**What "self-hosted" means here:** the Nucleus compiler is written in Nucleus; a previous-generation compiler binary compiles it; the resulting binary can then compile its own source and produce a byte-identical binary (the standard fixed-point test).

## Approach: minimum viable subset, grown in C, ported once

Two-phase strategy:

1. **Grow stage-0 (C) into "stage-0.5"** — a compiler still written in C, but supporting enough of Nucleus to express a compiler. Do *not* try to make it pretty or feature-complete. Add only what the port actually needs.
2. **Port `nucleusc` to Nucleus** as `src/nucleusc.nuc`. Compile it with stage-0.5. That binary is **stage-1**. Use stage-1 to compile `nucleusc.nuc` again → **stage-2**. Require `stage-1 == stage-2` byte-for-byte.

Macros, reader macros, the compile-time eval, the REPL, and the runtime-compiler library are all **deferred until after self-host**. They are the design's killer features but they are not required to get to a fixed point, and attempting them before self-host multiplies the C code we're about to throw away.

Textual LLVM IR stays as the backend. No LLVM C API, no optimization passes, no debug info. The stage-0 strategy (shell out to `clang file.ll -o file`) is kept verbatim.

The C compiler is **preserved in tree** as the bootstrap seed until we have a committed stage-1 binary or a trusted mirror. Deleting `src/nucleusc.c` is a later cleanup, not part of this work.

## Phase 1 — Grow the C compiler to a self-host-capable subset

Each step below must end in a runnable, test-passing state. Add tests in `examples/` + `tests/expected/` alongside every feature; `make test` stays green throughout.

**The target spec for phase 1 is: "compile `src/nucleusc.nuc`."** That's the only feature gate that matters. If a feature isn't needed to express the compiler, don't add it. If one turns out to be needed mid-port, come back and add it.

Ordered work, grouped by what unblocks what:

1. **Multi-function + parameters + recursion.** `(defn name:ret (x:int y:ptr) …)`, named parameter allocas, user calls via the existing dispatch. Today `emit_defn` hard-rejects non-empty param lists (`src/nucleusc.c:840`); this is the first blocker.
2. **Control flow: `if` / `else`, early `return`, `cond`.** `if` is the only missing structured form; `while` already exists. Reuse `g_block_term` discipline from `emit_while`.
3. **Integer ops + comparisons.** `+ - * / %`, `= != < <= > >=`, `and or not` (short-circuit for `and`/`or`), bitwise `bit-and bit-or bit-xor bit-shl bit-shr`. Today only `<` and `*` exist (`src/nucleusc.c:577`, `:589`).
4. **Types beyond `int`.** `i8`, `i16`, `i32`, `i64`, `ptr`, `void`, `bool`. Integer sign-extension / truncation on narrowing. Extend `parse_type_name` (`src/nucleusc.c:360`) and `type_to_ir` (`:349`).
5. **Pointers.** `(ptr T)` type, `(deref p)`, `(ptr-set! p v)`, `(ptr+ p n)` for byte/element offsets (map to `getelementptr`). Address-of for locals.
6. **Structs.** `(defstruct Node (kind:int) (line:int) (i:i64) (s:ptr) …)`, field access `(. n kind)` → `getelementptr` + `load`, field set `(set! (. n kind) …)`. This is the biggest single feature; the AST uses structs heavily, so there is no porting without it.
7. **Arrays / indexing.** Fixed-size local and global arrays, `(aref a i)`, `(aset! a i v)`. Needed for the lexer's `buf[n++]` pattern (`src/nucleusc.c:171`) and scope/symbol arrays.
8. **Enums / integer constants.** `(defconst TOK_LPAREN 0)` or `(defenum TokKind LPAREN RPAREN INT …)`. Needed for every tagged-union discriminator.
9. **Global variables.** `(defvar g_pos:i64 0)`, `(defvar g_src:ptr null)`. Today globals are implicit and hidden inside the C file; Nucleus needs them first-class.
10. **Character literals + string indexing.** `\a` or `(char "a")` — whatever syntax we choose. `(aref s i)` for `str[i]`.
11. **`include` for libc functions we actually call.** Extend `emit_include` (`src/nucleusc.c:807`) beyond the hard-coded `stdio` / `printf` case. The port needs: `malloc`, `free`, `realloc`, `memcpy`, `memset`, `memcmp`, `strlen`, `strcmp`, `strchr`, `strndup`, `fopen`, `fclose`, `fread`, `fwrite`, `fseek`, `ftell`, `fputc`, `fputs`, `fprintf`, `vsnprintf`, `isspace`, `isdigit`, `exit`, `perror`. Each needs a declared function type; most are not variadic.
12. **Variadic *call sites* only.** The port needs to call `fprintf`, `snprintf`, etc., but does **not** need to define variadic Nucleus functions. The existing variadic call-site machinery (`src/nucleusc.c:624`) already handles this; generalize it past the single hard-coded `printf` entry.
13. **`sizeof` and type casts.** `(sizeof T)` → compile-time constant; `(cast T expr)` → `trunc`/`zext`/`sext`/`bitcast`/`ptrtoint`/`inttoptr` depending on kinds.

The C compiler is allowed to grow in this phase — no aesthetic budget. Arena allocator, buffered entry/body emission, and the `emit_node` dispatch stay as-is; everything else gets bolted on.

Optional but probably worth it before phase 2:
- **`do` / sequencing as an explicit form.** Today body sequences are implicit (`src/nucleusc.c:846`, `:702`, `:726`). Making it explicit simplifies the port.
- **One-line comments.** Already supported in the lexer (`;`, `src/nucleusc.c:135`) — good.
- **Better diagnostics.** Not required; skip.

## Phase 2 — Port the compiler to Nucleus

Create `src/nucleusc.nuc` as a direct, line-for-line transliteration of `src/nucleusc.c`. The shape of the C code is already close to a Lisp: the arena, the lexer state machine, the reader, the scope chain, the `emit_*` functions, the `emit_node` dispatch. Port in the same order the C file is laid out, because each later section depends on earlier ones:

1. Arena allocator (`arena_alloc`, `arena_strdup`, `arena_printf`) — paved over libc `malloc`.
2. Error reporting (`die_at`) — uses `fprintf` + `exit`.
3. Lexer (`lex_string`, `lex_atom`, `next_tok`) — mutates globals; `inc!` and `set!` already exist.
4. Reader (`read_form`, `read_list`, `read_program`) — recursive; needs the growable `Node**` array.
5. Types, `split_typed`, `parse_type_name`.
6. Symbol table (`scope_new`, `scope_define`, `scope_lookup`) — nested linked list of flat arrays.
7. String literal interning.
8. Codegen buffers (`entry_emit`, `body_emit`) — per-function buffered emission.
9. All the `emit_*` functions, in dependency order: literals → symbols → builtins → call → special forms → `emit_list` dispatch → `emit_node`.
10. Top-level: `emit_include`, `emit_defn`, `emit_string_table`.
11. `main`: read file, parse, emit module prelude, string table, declares, defines.

Porting discipline: **no refactoring during the port**. The port's only goal is to produce a Nucleus program that stage-0.5 can compile and that behaves identically on `examples/hello.nuc`. Clean-up lives in a post-self-host pass when the C source is already gone. Keep variable names and function names identical where possible, so a `diff src/nucleusc.c src/nucleusc.nuc` remains legible.

## Phase 3 — Bootstrap fixed-point verification

1. Build stage-0.5: `make` → `build/nucleusc` (still a C binary).
2. Compile the Nucleus source with it: `./build/nucleusc src/nucleusc.nuc > stage1.ll && clang stage1.ll -o build/nucleusc-stage1`.
3. Compile the Nucleus source with stage-1: `./build/nucleusc-stage1 src/nucleusc.nuc > stage2.ll && clang stage2.ll -o build/nucleusc-stage2`.
4. Require **`diff stage1.ll stage2.ll`** to be empty. (Comparing `.ll` is more meaningful than comparing binaries — clang timestamps/paths drift through the linker.)
5. Require `./build/nucleusc-stage2 examples/hello.nuc` followed by `clang hello.ll -o hello && ./hello` to produce the existing expected output (`tests/expected/hello.out`).
6. Require `make test` (with the stage-1 binary swapped in) to pass every test added during phase 1.

Steps 4 and 5 are the actual self-host gate. Step 4 is the fixed-point test. Step 5 confirms the self-hosted compiler still does what the stage-0 compiler did.

Wire this up as `make bootstrap` in the Makefile so it's reproducible, not a one-time ritual.

## Non-goals for this work (explicitly deferred)

- Macros, reader macros, user-defined reader macros.
- Compile-time `eval-when`, runtime-loadable compiler library, REPL.
- Floats, unsigned types with distinct semantics, generic arithmetic.
- LLVM optimization passes, debug info, multi-target, cross-compilation.
- Optimizing the compiler (speed, memory) — the stage-0 arena leak-on-exit model is fine.
- Deleting `src/nucleusc.c`. That's a follow-up after stage-1 is trusted.
- Pretty diagnostics beyond `file:line: error: …`.

Each of these is valuable; none of them are on the critical path to a fixed point.

## Critical files

| Path | Role |
|---|---|
| `src/nucleusc.c` | Stage-0 compiler. Grows through phase 1, then frozen, then eventually deleted. |
| `src/nucleusc.nuc` | **New.** The self-hosted compiler. Written in phase 2 as a direct port of the C file. |
| `Makefile` | Add `bootstrap` target covering the three-stage build + diff. |
| `build.sh` | Unchanged in spirit; may need to dispatch to the C or Nucleus compiler depending on which binary exists. |
| `examples/*.nuc` | New tests added per feature in phase 1. Each feature gets one tiny example. |
| `tests/run-tests.sh` | Unchanged mechanism; new entries. |
| `design/stage0-plan.md` | Leave alone — it documents historic stage-0. |
| `design/self-host-plan.md` | **New.** This plan, promoted into the repo once approved, so it's versioned alongside the code. |
| `design/overview.md` | Add a pointer to the self-host plan. |

## Verification (end-to-end, what "done" looks like)

1. `make` builds `build/nucleusc` from C with no warnings under `-Wall -Wextra -Wpedantic`.
2. `make test` passes every example (old + all new phase-1 examples).
3. `make bootstrap` runs the three-stage build and asserts `diff stage1.ll stage2.ll` is empty.
4. Stage-2 binary compiles `examples/hello.nuc` and the produced executable prints the exact 4-line output in `tests/expected/hello.out`.
5. `clang -S` on any emitted `.ll` succeeds (IR is well-formed).
6. `design/overview.md` links to `design/self-host-plan.md`.

Once 1–6 hold, Nucleus is self-hosted and the C compiler is dead weight kept only as a bootstrap seed.
