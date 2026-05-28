# Deferred

## Storage class specifiers

C has `static`, `register`, `thread_local` / `_Thread_local`. Nucleus
has none of these. Deferred from stage 8 globals work — `set!`,
`defvar` literal expansion, and producing-side `extern` cover the
common cases without needing syntax for storage classes.

When added, candidate spellings would mirror the type qualifier shape
used by `volatile` — e.g. `name:type:static` or `(name (type static))`
as a postfix tag on the storage site. None of this is committed.

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
