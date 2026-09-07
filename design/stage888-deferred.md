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

## Variadic declare

  A declare is open-tailed — floor at num-params, no ceiling. A uniform exact rule compiled and self-hosted fine and a parser-aware sweep reported zero affected
  sites, but three suite heredocs write (declare printf (fmt:CStr):i32) and call it with 3–6 arguments, docs/toplevel.md documents that idiom, and src/nuch.nuc's
  own diagnostic actively recommends it. So a declare is a prototype the user asserts, and Nucleus has no ... spelling.

  The agent stated the cost plainly rather than burying it: a .nuch-imported Nucleus defn is also open-tailed, so cross-module calls with too many arguments stay
  undiagnosed. An explicit variadic marker for declare would make the open tail opt-in — that's the natural follow-up.

  One implementation note that generalizes: the rule must not gate on kind == TY-FN, because a BoxedFn/(dyn P) handle carries its arity on a TY-STRUCT type. A
  kind gate would have silently stopped checking that path.
  
## Possible bugs

~~`as` rejects float literals that round, but an implicit cast may be allowed. Investigate surprising behaviors.~~ **Resolved 2026-08-14** as W9 item 30 — see
design/stage15-stress-test/progress.md. `as` now admits a float literal that round-trips exactly, so `(as f32 1.5)` matches what `(let (a:f32 1.5) …)` already
accepted. One asymmetry survives on purpose: the implicit path still *rounds* `3.14` silently (W2d Option A) where `as` refuses it, because if `as` rounded too
then nothing in the language would mean "this conversion is exact".


## Flow-sensitive typing

Stage15 added some capabilities, and a later stage should examine expanding them.

## Symbols for struct field access

Bare symbols as arguments *may* be struct field names or *may* be variables. The
ambiguity is undesirable. **Being addressed** in Stage 16 — see
[stage16-ergonomics/dot-forms.md](stage16-ergonomics/dot-forms.md): the quoted
selector (`(get p 'x)`) becomes the only literal spelling, so a bare symbol in
selector position goes back to being an ordinary variable reference and
`(get p sel)` needs no annotation.

### What survives that fix: field iteration over a heterogeneous struct

Making the *spelling* regular does not make the operation total. A computed
selector lowers to a `select` chain over the field indices
(`emit-computed-field`), and that chain has one result type — so it is gated on
the struct being **homogeneous**:

```
get: computed field access requires a homogeneous struct, but 'Node' has fields of differing types
```

That gate is not a spelling problem and no selector syntax removes it: iterating
`Node`'s fields by symbol has no type to return. The options, none taken:

- a sum-typed result (`(get p sel)` returning a union over the field types),
  which makes every computed read a `match`;
- generated per-struct accessors, i.e. reflection over a struct's field table
  as compile-time data;
- restricting computed access to a declared homogeneous *subset* of fields.

Until one is chosen, computed field access stays what it is today: correct, and
available only where every field has the same type.

## Struct packing
 
 remains deferred — it wants a layout-attribute
  design that overlaps [stage14/attributes.md](../stage14/attributes.md)'s
  reserved-but-unimplemented `:align`/`:section` slots. Still the top
  layout-design candidate for the next stage.

## Type reachability
  
  a struct type named in a unit's signatures
  must still be defined in a reachable file. W1 removed the *order*
  constraint, not the reachability constraint, and that did not change.
  
This could make trouble using libraries with headers only, no source.


## Compiler types

### (raw T) should (maybe) be ?T

* c-type-to-nucleus
* c-typedef-find
* cdecl-site-find

## Pointer-kind spellings: make the sugar general, or ban the ambiguous half

Raised 2026-09-07, after the `&`/`@` adoption sweep across `src/`, `lib/` and
`examples/` (see [progress.md](progress.md) and
[stage16-ergonomics/ref-sigil.md](stage16-ergonomics/ref-sigil.md) §5/§6).

The `&` sigil is split by position **inside the token**: `p:&T` is the lexer
rewrite to `ref:` and leaves no trace, while a standalone `&T` is the address-of
reader macro and reaches the parser as `(addr-of T)`. In a type slot that node is
accepted (`parse-type-from-node`, `node-is-ptr-wrapper`, and since 2026-09-06
`type-node-to-c`), so it compiles and emits identical IR — but `--emit-nuch`
prints `defprotocol` and generic-template forms **verbatim**, so the odd spelling
lands in a committed header. `a15f38e` wrote 2,469 of them into `src/` before
anyone noticed; the sweep that removed them is convention, not a rule the
compiler enforces.

Two coherent end-states, and they point opposite ways:

- **Make it general.** `&T` should be legal and canonical in every type slot,
  round-tripping through `--emit-nuch` as `&T` or `(ref T)`. The reader cannot
  decide by position, so the node has to *remember it was written `&`* — a
  distinct head both the type path and the value path accept, printed back as
  the source spelling. Cost is the usual reach list: the `node-type`↔`emit-node`
  lockstep, `gcheck`'s value-path wrapper test, and `fn-rewrite-captures`.
  §6 costed the wrapping-with-`addr-of` alternative at zero value-side changes
  precisely by *not* doing this; that trade should be re-priced now that the
  spelling has 3,000 uses rather than none.
- **Ban the ambiguous half.** Make a standalone `&T` in a type slot a
  diagnostic naming `ref:T` / `(ref T)`, so the convention is mechanical instead
  of a thing a sweep has to re-derive. Cheap — one arm in
  `parse-type-from-node` — but it retires `(sizeof &Pt)`, `(as &Pt q)`,
  `(link &Pt)` and `(Vector &Pt)`, which §"Where the two meet" blesses and
  `examples/ref-sigil.nuc` plus `s16-ref-sigil-both-meanings` exercise.

The general principle worth settling first: **a spelling whose meaning depends
on where the reader happens to be should not be silently accepted.** Today three
spellings of the same pointer kind (`ptr:T`, `ref:T`, `&T`) differ in nothing
the type system can see, yet differed for a year in what `--emit-cheader`
printed (`T*` vs `void*` — fixed 2026-09-06) and still differ in what
`--emit-nuch` prints. `raw:T` is the remaining case: it widens to `void*` in a C
header deliberately, which is defensible for a nullable pointer and is still a
header whose fidelity depends on which synonym the author typed.
