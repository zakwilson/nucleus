# Stage 8 candidates: C features not yet possible in Nucleus

A survey of things that work in C today but are not yet expressible (or are
incomplete) in Nucleus as of stage 7. Not a plan — a backlog to draw from
when scoping stage 8 and beyond. Cross-references existing design docs
where they exist (notably `stage3c.md` for C interop gaps and
`stage999-future.md` for Lisp-ward features).

## Type system / data

- **Unions** — skipped entirely by the C header parser; no `defunion` form.
  C libraries exposing union types in their API (`SDL_Event`,
  `pthread_mutexattr_t`) cannot be used directly. See `stage3c.md`.
- **Bit-fields** — `int flags : 3;` not parsed; no shift/mask field access
  generated. See `stage3c.md`.
- **Anonymous / nested structs** — anonymous inner structs skipped; named
  nested structs only partially handled. See `stage3c.md`.
- **Packed structs / alignment attributes** — no
  `__attribute__((packed))` or `__attribute__((aligned(N)))`.
- **`long double`** (80-bit on x86-64 Linux) — no support; blocked on
  broader float work historically, now blocked on need.
- **`_Complex float` / `_Complex double`** — skipped by the header parser.
- **`const` / `volatile` / `restrict` qualifiers** — stripped during
  parsing. No `volatile` semantics, which matters for MMIO and
  signal-handler-visible state.
- **C enums with explicit values from headers** — not imported. Nucleus
  has `defenum` for its own code, but `enum { A=0, B=1, ... }` declared
  in a `.h` does not come across.
- **Function pointer fields in C structs** — mapped to opaque `ptr`;
  signature information is lost even though `TY-FN` could carry it.
- **Typedef aliases** — collapsed at parse time; opaque-handle names
  (`typedef struct Foo *FooRef`) lose their documentation value.

## Expressions / statements

- **C-style `for` with arbitrary init/test/step** — only the macro form
  exists. No `break` / `continue`.
- **`switch` / `case` / fallthrough / `goto` / labels** — none; only
  `cond`. Jump tables and computed gotos are not expressible.
- **Compound literals** (`(struct S){.x = 1}`) — none.
- **Designated initializers** (`{.field = val}`) — none.
- **Ternary `?:`** — only via `cond` / `if`. Works, but no operator-shaped
  form for tight expressions.
- **Pre/post increment as expressions** — `inc!` is statement-only;
  no `i++` that yields a value.
- **Comma operator** — none (use `do`, which is fine but not interchangeable
  inside `for`-style headers).

## Globals / storage

- ~~**`set!` on globals**~~ — works in both batch and REPL. See
  `design/stage8/globals.md`.
- ~~**`defvar` with non-integer-literal initializers**~~ — integer,
  float, string, `null`, `true`/`false`, `(char "x")`, and `defconst`
  names are accepted in initializer position. Array / struct compound
  literals remain expression-only.
- **Storage class specifiers** — no `static` (file-local linkage), no
  `register`, no `thread_local` / `_Thread_local`. Deferred; see
  `design/stage888-deferred.md`.
- ~~**Extern variables in Nucleus-defined modules**~~ — `defvar` is
  externally linkable from C and from other Nucleus modules. The
  producing side of `--emit-cheader` and `--emit-nuch` re-exports
  globals as `extern` declarations.

## C interop boundaries

- **`static inline` functions from headers** — body skipped, declaration
  not emitted. Headers that expose important functionality only as
  `static inline` (common in modern libc and helper headers) require
  hand-written wrappers. See `stage3c.md`.
- **Function-like C macros expanding to compound literals or statement
  expressions** — `clang -E` expands them, but the Nucleus parser can't
  consume the result. Manual wrappers required.
- **Variadic functions defined in Nucleus** — can call C variadics
  (`printf`), but cannot `defn` a variadic function using `va_list` /
  `va_start` / `va_arg`. `&rest` is macro-level, not C ABI.
- **`&rest` functions are not C-callable** — fixed at the ABI boundary;
  rest args are built as a `Node*` cons list at the call site.

## Platform / ABI

- **32-bit targets** — `size_t` is hardcoded `i64`, pointer size 8 bytes,
  target triple `x86_64-pc-linux-gnu`. See `stage3c.md`.
- **macOS / Windows** — untested; header layouts and ABI conventions
  differ.
- **Struct ABI verification** — Nucleus struct definitions are not checked
  against the C ABI layout for the same name. Layout on non-x86-64
  platforms has not been tested.

## Optimization (functional gap, not feature gap)

- **LLVM middle-end optimizer not run** — `nucleusc` parses its IR and
  goes straight to `LLVMTargetMachineEmitToFile`. Missing passes
  include `mem2reg`, LICM, GVN, instcombine, the loop unroller, and
  `LoopVectorize` / `SLPVectorize`. Net effect: `nucleusc -O3` is
  closer to `clang -O0` than to `clang -O3`. See `stage999-future.md`
  for the full breakdown.
- **Fast-math flags not emitted** on `fadd` / `fmul` / `fdiv`, so FP
  reductions can't vectorize even if the middle end were running.

## Misc

- **Inline assembly** (`__asm__` / `asm volatile`) — none.
- **`_Generic`** — none. AST-inspecting macros cover some cases (see the
  `tprint` example in `docs/builtins.md`), but there is no value-typed
  dispatch primitive.
- **Lexical closures / lambdas** — none. Tracked in
  `stage999-future.md`; also absent from C itself, but a stated
  Nucleus goal.
