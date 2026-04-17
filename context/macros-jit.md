## defmacro

- `(defmacro name (params...) body...)` defines a compile-time macro. The body runs in the JIT and receives unevaluated `Node*` arguments; the returned `Node*` is re-emitted at the call site.
- Macro JIT function signature: `ptr @__macro_<sanitized_name>(ptr %__args.arg)` where `%__args.arg` is a `Node*[]` pointer.
- Macro names are sanitized before use as IR identifiers: hyphens, `!`, `?`, etc. are replaced with `_`. This is required because LLVM IR identifiers can only contain `[A-Za-z0-9_.]`.
- `(gensym)` inside a macro body returns a fresh `__gs_N` symbol `Node*` for manual hygiene. `nucleus_gensym` is defined as a `defn` in `nucleusc.nuc` and exported from the self-hosted binary via `-rdynamic`.
- `(funcall-ptr-1 fn arg)` calls a `ptr` function pointer with one `ptr` argument, returning `ptr`. Used by the self-hosted compiler's `emit-macro-expand` to call macro JIT functions.
- `&rest` variadic parameters: `(defmacro name (a b &rest rest) ...)` — `&rest` must be second-to-last in the param list. The last param receives a cons list of remaining args. `MacroDef.variadic` flags variadic macros; `emit-macro-expand` builds the rest list in reverse order with `make-cell`.
- The `->` threading macro uses `_` as a positional placeholder inside forms. `_` is only special within `->` — it's an ordinary symbol elsewhere. If no `_` appears in a form, thread-first (insert after head). Implementation rebuilds the form using quasiquote reverse-and-rebuild (not `make-cell`) so it works at JIT time.
- Macros that reference `*Node`, `NODE-CELL`, `NODE-SYM` etc. (like `->` and `dotimes`) can only be used in programs that define the Node type — currently just the compiler itself. Simple macros (like `if`, `when`) work in any program.
- Note: gensym'd symbols cannot be used as typed `let` binding names with the `~sym:type` quasiquote syntax — the reader parses `sym:type` as a single token. Workaround: use gensym-free macros where possible, or use `~sym` only in value position.
- The C `Node` struct uses separate fields (not a union) to match the LLVM/Nucleus `{ i32, i32, i64, ptr, ptr, ptr }` 40-byte layout. This is required for JIT-created nodes to be readable by the C bootstrap.

## compile-time JIT

- The `(compile-time body…)` form links `libLLVM-19` via the LLVM ORC LLJIT C API.
- A single LLJIT instance is shared across all `compile-time` blocks in one compilation run (lazy init on first use).
- Each `compile-time` block generates a uniquely-named entry function `@__compile_time_main_N` to avoid symbol collisions.
- CT printf output goes to stderr (via a `dup`/`dup2` redirect) so it doesn't corrupt the IR emitted to stdout.
- The `llvm-19-dev` package must be installed in the container for the LLVM C API headers; `llvm-config` provides the right `--cflags`/`--ldflags`/`--libs`.
