# Deferred

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
  the generated header (`cheader-template-instance`, src/cheader.nuc:829,
  emits a `/* not exported */` comment). Fix requires a naming convention
  for instances (e.g. `nuc_Result_Config_Err`). Blocked on no exported
  surface having adopted `!T` yet; revisit when it does (errors.md §11.7).

## Stage 10 safety / error-handling deferrals

### `errdefer`

Dropped from error handling v1 (errors.md §12). The `defer` + explicit
error-path combination has covered every case so far. Reintroduce if
adoption finds a pattern that genuinely needs it.

### Handler repair over niche pointers

In E3, a `with-handler` whose repair type is a niche-encoded `(ref X)`
(i.e. `(Maybe (ref X))` is a plain `ptr`, not a struct) is not supported
by the handler-invocation path (`emit-handler-call`,
src/union-emit.nuc:615, 828, 871). V1 handler repair types must be value
types (structs / scalars). The original blocker — `(Maybe (ref X))` not
being a proper layout instance — was lifted when U4/C4's niche layout
engine landed (stage10/progress.md), so this is now unblocked; the
handler path itself has just not been extended.

### `die-at` hook

The C3 panic-tier hook fires only on unwrap failure
(`emit-unwrap-result` / `emit-unwrap-niche-errptr` consult the
`'unhandled-error` handler chain); a bare `die-at` abort does not. So a
REPL/test harness binding `'unhandled-error` sees unwrap failures but
not direct `die-at` aborts. Recorded as-built in errors.md's C3 block;
wire the `die-at` path through the hook if a consumer ever needs it.

## Strings / Unicode (Stage 11 `string.md` deferrals)

### UTF-16 encode/decode on `Char`

An earlier `string.md` draft listed UTF-16 alongside UTF-8 on the `Char`
protocol. Deferred (Q-utf16): Nucleus is a UTF-8 language and there is no
concrete consumer (no Windows wide-API interop story). Reintroduce a
`char-encode-utf16` / `char-decode-utf16` pair only when a real consumer
appears; the surrogate-pair logic is well-understood and self-contained.

### Full Unicode case mapping / folding

`string.md` ships **ASCII-only** `upcase`/`downcase` (and `char-ascii-upper`/
`char-ascii-lower`) in its first pass (Q-case). Full Unicode case mapping and
case folding are deferred: they need the Unicode case tables (multi-codepoint
expansions like `ß → SS`, locale-sensitive rules like Turkish dotless-i), which
is a data-table + algorithm effort disproportionate to the first string release.
`collections.md` already flagged `upcase`/`downcase` as "Unicode/locale-fraught."
Grapheme-cluster segmentation and NFC/NFD normalization belong to the same future
Unicode-tables library.

### Seq

I really want strings to be Seq, or to add another protocol. It should be
possible to `doseq` a string. (Today it takes an explicit iterator binding
plus `doseq-iter` + `addr-of` ceremony: bind `(chars sv)` or `(bytes sv)`,
then `(doseq-iter (c (addr-of it)) …)` — see examples/strview-read-test.nuc.)
