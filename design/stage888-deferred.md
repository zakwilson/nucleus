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

### U4 + A2 — niche layout and `&repr`

`defunion` and the `Result`/`Maybe` templates currently use a
`{tag:i32, payload:union}` representation everywhere. Two related
optimizations are deferred:

- **U4**: a `&repr` annotation letting a `defunion` control its layout
  (e.g. tag in the high bits of a pointer, flag bits in alignment padding).
- **A2**: `(Result (ref T) Err)` folded to a tagged pointer — the
  ERR_PTR niche encoding (ids 1–4095 in the top page, never a valid
  object address). This makes a `!T` ABI-identical to a raw `T*` at the
  C boundary, as `?T` already is.

Both need the same layout-rule engine. Error ids are already capped at
4095 (errors.md §8) to keep the range compatible. Design: errors.md A2,
unions.md U4.

### E4 — coercion-path adoption of `!T`

The reader pipeline was converted to return `!ptr` (E4 done). The
remaining `die-at` sites in the coercion path (`coerce-int-val` /
`coerce-num-val` / `safe-coerce-val` and the `pkind-flow-check` abort in
`emit-*`) were not converted — the cascade runs deeper into the emitter
and is a larger change than the reader. Current behavior: a type mismatch
in the emitter still calls `die-at` and exits (batch) or `repl_throw`s
(REPL). Revisit when the emitter is more modular.

### N2 remaining cold sites (~25)

The first N2 tranche converted all hot emitters, allocators, and the
dispatch spine. Remaining un-converted spots:

- defvar/defconst/inc-dec/addr-of emitters
- gcheck/valid walkers, `repl.nuc`
- field types beyond `InternEntry.node`
- `?i8`-shaped string returns (left raw — `?ptr:i8` reads poorly for
  C-string returns)

None block anything; conversion can proceed incrementally when touching
those paths.

### `errdefer`

Dropped from error handling v1 (errors.md §12). The `defer` + explicit
error-path combination has covered every case so far. Reintroduce if
adoption finds a pattern that genuinely needs it.

### Standalone `signal` (policy hooks without error return)

The arena-OOM shape — a fault site that signals for a repair value and
*continues in place* without returning an error — was omitted from v1
(errors.md §13 Q6). The handler-chain library half is unchanged and
already supports this; the compiler does not emit a check. Re-expose a
`signal` function over the same chain if a use case demands it.

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
