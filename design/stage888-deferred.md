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
- **`--emit-cheader` skips template-instance signatures** — exported
  functions whose return/param types include a stamped template instance
  (e.g. `(Result Config Err)` from `!Config`) are silently omitted from
  the generated header. Fix requires a naming convention for instances
  (e.g. `nuc_Result_Config_Err`). Blocked on no exported surface having
  adopted `!T` yet; revisit when it does (errors.md §11.7).

## Stage 10 safety / error-handling deferrals

### `errdefer`

Dropped from error handling v1 (errors.md §12). The `defer` + explicit
error-path combination has covered every case so far. Reintroduce if
adoption finds a pattern that genuinely needs it.

### Handler repair over niche pointers

In E3, a `with-handler` whose repair type is a niche-encoded `(ref X)`
(i.e. `(Maybe (ref X))` is a plain `ptr`, not a struct) is not supported
by the `abi-emit-struct-call` path used for handler invocation. V1
handler repair types must be value types (structs / scalars). Lift this
once `(Maybe (ref X))` is a proper layout instance (U4).

### `unsafe` lexical block

Raw ops (`(raw T)`, bare `ptr`, `cast`, `ptr+`, unchecked `aref`/`aset!`,
`funcall-ptr-*`) are currently confined by naming convention only — no
compiler-enforced `(unsafe …)` boundary. A first-class enforced block is
left as a future option once the checks have proven out and the raw-op
cluster sites are known. Arrives alongside namespaces / the `unsafe/`
namespace (safety.md §1, flip.md "Out of scope").

### `die-at` hook

One implementation-vs-plan deviation it flagged and documented accurately: the cleanup-prompt described C3's panic hook as firing on both die-at and unwrap-on-err. The actual implementation only hooks unwrap (in emit-unwrap-result / emit-unwrap-niche-errptr) — there's no hook on the bare die-at path. This is recorded as-built in the errors.md C3 block rather than papered over.

One thing worth your attention: that C3 deviation means the panic-tier hook is narrower than the prompt's spec — a REPL/test harness binding 'unhandled-error will see unwrap failures but not direct die-at aborts. If you intended die-at to also consult the hook, that's a code gap, not a docs gap. Want me to look into wiring the die-at path too, or is the unwrap-only scope the intended final state?
