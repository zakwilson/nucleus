# Stage 14 — Native string literals + selective compiler adoption

Today `"…"` is a `CStr`: a NUL-terminated `[N x i8]` rodata global whose address
(`ty-cstr`, ABI-identical to `ptr`) is the literal's value. This doc designs the
switch to a **native, length-carrying borrowed view** as the literal type, and the
migration path for the compiler's own sources — which traffic in `CStr`/`ptr`
throughout — to survive that switch and, selectively, to benefit from it.

This is the largest breaking change in Stage 14: it retypes ~2,700 string literals
in `src/` alone. The design's whole job is to make that flip **byte-identical for
the compiler's bootstrap** (only `lib/`/`examples/` IR moves) and to reject the
folklore that "adopting native strings" means rewriting the compiler in the new
type. It does not.

---

## 1. Ground truth (verified 2026-07-03 against the tree)

### 1.1 The view type is `StrView`, and `String` is correctly *not* the answer

`StrView` (docs/strings.md §3, lib/strview.nuc:106) is the borrowed slice:

```lisp
(defstruct StrView (data (ptr ui8)) (len usize))
```

Two words, 16 bytes, **by value, no `Drop`** — copying a `StrView` copies the
`{ptr,len}` pair and frees nothing (the bytes are borrowed). `abi-classify`
(src/abi.nuc:138) covers it as two INTEGER eightbytes → passed in two GPRs,
returned in `rax:rdx`; it is the cheap DIRECT-ish case, and the string library
already returns it by value pervasively (`strview-trim` et al.). String literals
are static rodata, so the **owning** `String` (`{bytes:(Vector ui8)}`, has `Drop`,
lib/string.nuc) is the wrong literal type — nothing is allocated or freed. The
task's instinct ("`String` is presumably wrong") is correct; `StrView` is right.

### 1.2 Premise correction — "adopt native strings inside the compiler" is *mostly the wrong move*

Folklore reading: rewrite the compiler to use `StrView` instead of `CStr`
everywhere. Ground truth: **`StrView` is referenced in zero `src/` files today**
(grep-verified) — the compiler is 100% `ptr`/`CStr` internally — and that is
partly *correct and must stay*:

- The compiler's string substrate is **interned, NUL-terminated `ptr`** whose
  `=`/`!=` is **pointer identity** (the `Node.s` symbol path; struct-field
  interning matches selectors by `=` pointer identity — conventions.md
  "Struct field names are interned"). `StrView`'s `Eq` is **byte content**
  (docs/strings.md §3 Conformances). Retyping an identity-compared `ptr` to
  `StrView` silently converts identity comparisons to `strcmp` — this is exactly
  the `Node.s` retype trap in conventions.md ("never retype a field/param that is
  compared for pointer identity"), generalized. So the interning tables,
  `scope-define`/`scope-lookup` keys, and `Node.s` **cannot** become `StrView`.
- The compiler is glued to libc: `fprintf`/`snprintf`/`strcmp`/`strlen`/`fputc`
  (src/format.nuc is *all* NUL-terminated `ptr` into `snprintf`). These need a
  `char*`, not a `{ptr,len}`.

Therefore the design is **not** a rewrite. It is (a) flip the *literal type*, (b)
make the flip transparent to the existing `ptr`/`CStr`/libc code via a free
coercion, and (c) adopt `StrView` **selectively** where a carried length removes a
`strlen`/re-scan — never wholesale.

### 1.3 The literal path today (reader → node → type → IR)

- **Reader**: `TOK-STRING` → `NODE-STR` with the bytes in `Node.s`
  (lib/reader.nuc:745-750). No length is stored; `emit-string` recomputes it with
  `strlen`, so a literal cannot carry an embedded NUL through the normal path.
- **Type**: `node-type` returns `ty-cstr` for `NODE-STR` at **three** sites in
  src/generics.nuc — **1555, 1831, 3286** (the `node-type`↔`emit-node` lockstep
  surface, conventions.md).
- **Emit** (`emit-string`, src/nucleusc.nuc:874-882): `intern-string` appends a
  `StrLit` to the `g-strs` registry and returns an id; emits
  `getelementptr … [N x i8], ptr @.str.<id>, i64 0, i64 0` and returns
  `(alloc-val ty-cstr tmp)`.
- **Table** (`emit-string-table`, src/nucleusc.nuc:7652): writes each
  `@.str.<id> = private unnamed_addr constant [N+1 x i8] c"…\00", align 1` — **already
  NUL-terminated** (the `\00` and `+1` length). This is load-bearing: §2.

### 1.4 `intern-string` does not dedup — literal "interning" ≠ symbol interning

`intern-string` (src/scope.nuc:98) *appends* a fresh `StrLit` every call
(`id = count g-strs`) — no content dedup. It is a per-literal emission table, not a
symbol-interning table. The real interner is `intern-str`/`intern-symbol` (pointer
identity, dedup), which backs `Node.s` and struct-field names. So "what does
interning mean once literals are views?" has a clean answer: **nothing changes** —
symbol interning stays `ptr`-identity; the `g-strs` table stays a per-literal rodata
emitter (now optionally emitting a view header, §2). The two were never the same
mechanism.

### 1.5 `StrView` is import-gated — the literal type must reach the prelude

`StrView` lives in lib/strview.nuc behind `(import-use strview)`, which pulls
`hash`, `numeric`, `char`, `iterator`, `string-errors`. String literals appear in
**every** compile — the prelude, the reader, macros.nuc, and the compiler's own
bootstrap — most of which do not (and must not) import that stack. So `StrView`
**as spelled today cannot be the literal type**: the type would be unregistered in
almost every unit. The bare *struct* (`{(ptr ui8), usize}`) has **no** dependency —
only its *methods* do. The literal needs the 16-byte layout, not the method stack.
Resolution in NS-1: promote the bare `defstruct StrView` into the prelude
(auto-imported everywhere, like `Node`/`Maybe`/`Result` already are —
lib/prelude.nuc:13-63), leaving every method in lib/strview.nuc as `extend`/`defn`
on the now-prelude-registered type.

### 1.6 The FFI floor: libc genuinely needs NUL-terminated `char*`

`printf`/`snprintf`/`fopen`/the LLVM C API (src/llvm.nuch) and every C extern take
`char*`. A `{ptr,len}` cannot be handed to them. But §1.3 already gives the escape:
**the backing `@.str.<id>` global is NUL-terminated**, so a `StrView` literal's
`data` field *is* a valid `char*` — `strview-to-cstr`'s soundness precondition
("NUL-terminated at `data[len]`") holds for literals by construction. Borrow-to-CStr
is O(1) and free. This is the hinge of the whole coexistence story (§2).

### 1.7 `(Maybe StrView)` still fails in the macro/CT JIT — real, bounded

Stage 13 R1 (docs/strings.md §6, iterators): `(Maybe StrView)` cannot be stamped in
the macro-expansion JIT module (embeds a struct in the anon union; verified still
live). Impact on this design: **literals in macro *output* are unaffected** — they
are `NODE-STR` (the reader's `Node`, re-emitted at the call site where they type
normally), not `StrView` *values* at JIT time. The constraint only bites a macro
whose *runtime* body constructs a `(Maybe StrView)` — which nothing does. NS-3 must
still verify the prelude `StrView` struct is visible to the CT/macro JIT module (it
should be, since prelude types are, exactly like `Node` — macros-jit.md), and must
not make any macro's runtime body traffic in `(Maybe StrView)`.

### 1.8 Scale and chokepoints

- ~2,700 `"…"` literals in `src/` (5,422 `"` / 2), ~99 explicit `CStr` mentions,
  73 `:CStr`/`(ref CStr)` typed params/fields across 10 files. The literals are the
  mass; the `CStr` annotations are the FFI seams.
- Chokepoints that see literals as values: **format helpers** (src/format.nuc, all
  `snprintf`), the `fprintf`/`fputc` IR-emission sites (thousands), **`=`/`!=`
  vs. a `ptr`** content comparisons (`(= name "i32")` — the `is-ptr-like`
  mixed-operand strcmp rule, conventions.md), type-name string tables
  (union-registry.nuc, type-mangle.nuc), and diagnostic message construction. None
  of these *want* a `StrView` — they want the `char*`. §2's coercion keeps them
  byte-identical.

---

## 2. Decisions

- **Literal type = `StrView`** (the bare struct, promoted to the prelude). A `"…"`
  value is a two-word borrowed view over a static, hidden-NUL-terminated rodata
  global. Static data, no allocator, no `Drop`.

- **Hidden NUL, free borrow-to-CStr/ptr.** The `@.str.<id>` backing global keeps its
  trailing `\00` (unchanged from today). A `StrView` literal therefore coerces
  **freely, in value position, to `CStr` and `ptr`** by taking `data` — sound
  because the buffer is NUL-terminated at `data[len]`. This mirrors today's
  `CStr`↔`ptr` free coercion (conventions.md "CStr is ABI-identical to ptr") and is
  the mechanism that keeps every libc/format/`fprintf` site working unchanged.

- **Target-aware emission = byte-identity.** `emit-string` becomes target-typed:
  when the consumer's expected type is `ptr`/`CStr` (the overwhelming compiler case —
  every `fprintf`, `fmt-*` arg, `strcmp`, `= "lit"` position), it emits **only the
  GEP** and returns a `ptr`/`CStr` `Val` — *textually identical to today's IR*. Only
  when the target is `StrView` (or absent/inferred) does it materialize the
  `{gep, i64 len}` struct. Precedent: the collection-literal target-typing scope.
  This is what makes the compiler's own bootstrap byte-identical across the flip
  (the CStr-migration IR-diff technique, conventions.md).

- **`=`/`!=` mixed `StrView`/`ptr`/`CStr` → `strcmp`.** Extend the `is-ptr-like`
  mixed-operand rule (`emit-binop-vals`) so a `StrView` operand against a
  `ptr`/`CStr`/`StrView` fires the content comparison — keeping `(= name "i32")`
  exactly as it lowers today. **Two plain `ptr` stay `icmp` identity** (the `Node.s`
  path is untouched — no field is retyped, only the literal changed kind).

- **`CStr` stays as the FFI type.** It is not retired. The free borrow makes an
  explicit conversion optional; NS-4 adds a `c"…"` literal (→ raw `CStr`, no view
  header, no target-typing needed) purely as an ergonomic direct spelling for
  FFI/format-string hot spots and as the honest "I mean a `char*`" marker. Runtime
  bridges `strview-from-cstr`/`strview-to-cstr` are unchanged.

- **Compiler-internal adoption is selective and `ptr`-substrate-preserving.** The
  interned-symbol substrate (`Node.s`, scope keys, struct-field names, all
  identity-`=` paths) **stays `ptr`**. `StrView` is adopted only where a carried
  length removes a `strlen`/re-scan and identity is not at stake (reader token
  slices, diagnostic spans, IR-fragment builders). Never a blanket retype.

- **Interning is unchanged** (§1.4): symbol interning stays `ptr`-identity dedup;
  the `g-strs` table stays a per-literal rodata emitter. Optional literal-header
  dedup is an orthogonal size optimization, explicitly out of scope for v1.

---

## 3. Design — phases

### NS-1 — promote the `StrView` struct into the prelude (substrate, additive)

Move the bare `(defstruct StrView (data (ptr ui8)) (len usize))` from
lib/strview.nuc into lib/prelude.nuc (beside `Node`/`Maybe`), so the type is
registered in every compile including the reader/macros/bootstrap. lib/strview.nuc
keeps every method (`extend`/`defn`) and drops only the `defstruct` (the type is now
pre-registered; `(import-use strview)` still yields the full API). No literal types
as `StrView` yet — this phase only makes the type *available*.

- **Scope**: one struct moved; field names `data`/`len` interned via the normal
  `emit-defstruct` path (conventions.md field-interning — automatic here). Verify no
  file re-`defstruct`s `StrView`.
- **Gate**: **byte-identical bootstrap** — a bare 2-field `defstruct` adds no entries
  to the `g-strs` literal table and no `"…"` to the string pool, so the compiler's IR
  is unchanged; `make test` (every `(import-use strview)` client still compiles). If
  the prelude edit shifts the pool (it should not), standard one-refresh reconverge.
- **Refresh**: none expected.

### NS-2 — dormant emission + coexistence coercions (inert substrate)

Build everything the flip needs, **with the literal still typed `CStr`** (feature
inert, TE-1/TE-2 "inert substrate" precedent):

- `emit-string` gains a target-typed struct-materialization path
  (`{ getelementptr … , i64 len }` for a `StrView` target) beside today's bare-GEP
  path — but the default target stays `CStr`, so nothing changes yet.
- `StrView`→`CStr`/`ptr` free value coercion (extract `data`) added to the value
  coercer (`coerce-val`/`safe-coerce-val` region, near the `abi.nuc:443`
  `CStr`↔`ptr` no-op). For a *literal* `StrView` the coercion collapses to the bare
  GEP (no `extractvalue`); for a general `StrView` value it is one `extractvalue`.
- `emit-binop-vals` mixed-operand rule extended to admit `StrView` on the strcmp
  path (dormant until a `StrView` operand exists).
- `node-type` for a `StrView`-typed context wired through the three lockstep sites
  (still returning `ty-cstr` for `NODE-STR` until NS-3 flips them).
- **Scope**: additive codegen/coercion; no type flip.
- **Gate**: **byte-identical bootstrap** (all new paths dormant), `make test`.
- **Refresh**: none.

### NS-3 — the flip: `NODE-STR` types as `StrView` (breaking change)

Flip the literal type in lockstep across `emit-string` (src/nucleusc.nuc:874) and the
**three** `node-type` `NODE-STR` sites (src/generics.nuc:1555/1831/3286) — the
conventions.md `node-type`↔`emit-node` lockstep is the enforcement gate. `emit-string`
becomes target-aware (§2): `ptr`/`CStr` target → bare GEP + `ptr`/`CStr` `Val`
(identical IR); `StrView`/inferred target → materialized `{ptr,len}` `Val`.

The load-bearing claim: **the compiler's own literals all sit in `ptr`/`CStr`
context** — `fprintf`/`fmt-*` args, `strcmp`, `= "lit"`, `:ptr`/`:CStr`
params/returns/stores — so they emit the bare GEP and the bootstrap IR is unchanged.
`lib/` and `examples/` IR *does* move (literals bound to `StrView` slots, string
methods) — covered by `make test` output diffs, not the bootstrap.

- **Audit** (part of the phase, mirrors LW-4's "expected none"): find compiler
  literals in *type-inference* position — a bare `(let (x "…") …)` with no annotation
  and no `ptr`/`CStr` consumer would now infer `x:StrView` and could shift IR. Expected
  count low; fix by annotating (`x:CStr`) or by the consumer's target type. This audit
  *is* the byte-identity proof.
- **JIT check** (§1.7): confirm the prelude `StrView` struct resolves in the CT/macro
  JIT module (like `Node`), and that no macro runtime body is pushed into
  `(Maybe StrView)`.
- **Scope**: the type flip + emit target-awareness; **no signature retyping** (that is
  NS-5) — NS-3 touches only the literal's kind and the coercion layer.
- **Gate**: **byte-identical bootstrap** on `build/nucleusc.ll` (before/after diff,
  the CStr-migration technique) is the primary gate; `make test` for lib/examples.
- **Refresh**: **one reconverging refresh** if any string-pool shift survives the
  audit (`make update-bootstrap` → `make clean && make` → `make bootstrap`).

### NS-4 — FFI coexistence surface: `c"…"` and the CStr contract

- **`c"…"` literal**: reader recognizes a `c` prefix on a string token (no such form
  exists today, lib/reader.nuc) → a `CStr`-typed literal that emits the bare GEP with
  no view header and no target-typing — the direct spelling for FFI/format hot spots
  and the explicit "I mean `char*`" marker. Purely additive; `"…"`'s free borrow
  already covers the same cases, so `c"…"` is ergonomic, not required. (Alternative
  considered: a `(cstr sv)` value primitive instead of a literal form — rejected as it
  reads worse at the ~thousands of `fprintf` sites; `c"…"` is one token.)
- **Contract doc**: `CStr` is the FFI/`char*` type; `"…"` (StrView) borrows to it for
  free via the hidden NUL; `strview-from-cstr`/`strview-to-cstr` are the runtime
  bridges for non-literal data. `printf`-family varargs still take the borrowed
  `data` (a `%s` on a `StrView`'s `data` is a `char*` — unchanged).
- **Scope**: one reader form + the contract. May fold into NS-3 if landed together;
  kept separate for the decision record.
- **Gate**: byte-identical for the compiler (no compiler source needs `c"…"`
  initially — the flip already keeps it green); example exercising literal→`printf`,
  literal→extern C, `c"…"`→extern.
- **Refresh**: none (additive).

**Status: done (2026-07-04).** Mechanism = reuse `Node.i` (i64, previously
unused for `NODE-STR`) as a boolean CStr discriminant (`0` = `StrView` default,
`1` = explicit `c"…"`) — no new `NodeKind`, so no new dispatch sites, and
dormant for every existing literal. Reader (`lib/reader.nuc`): `next-tok`
detects `c` (99) immediately followed by `"` (34) via one-char lookahead,
consumes both, lexes the body as a plain literal, flags the token `i=1`; the
`TOK-STRING`→`NODE-STR` conversion copies `(t i)` into `NODE-STR.i`. The three
`node-type` `NODE-STR` lockstep sites (`src/generics.nuc`) branch `i≠0` →
`ty-cstr` else `(strview-type)`; `emit-string` (`src/nucleusc.nuc`)
short-circuits `i≠0` to the bare-GEP `CStr` Val regardless of the ambient
target, ahead of the NS-3 chameleon logic. Gate met: purely additive/dormant
(no compiler source uses `c"…"`), so `make bootstrap` is byte-identical on the
first try with no `update-bootstrap` refresh. `examples/cstr-lit-test.nuc`
exercises `c"…"`→`printf %s`, `c"…"`→`extern strlen(char*)`, and plain `"…"`→the
same extern (free coerce, no regression). 154/154 tests. Not carried: quoted
`c"…"` (`emit-quote-tree` intentionally does not store `Node.i` for `NODE-STR`,
keeping quoted plain strings byte-identical). Docs/conventions reconciliation is
NS-6.

### NS-5 — selective compiler-internal adoption (opt-in, bounded, per-site)

Move chosen `ptr` string sites to `StrView` **only where a carried length removes a
`strlen`/re-scan and identity is not at stake**. Candidate seams: reader token
slicing (already has offset+len), diagnostic span text, IR-fragment builders that
currently `strlen` then copy. **Explicitly excluded** (identity substrate, §1.2):
`Node.s`, `scope-define`/`scope-lookup` keys, struct-field names, any `=`-identity
`ptr`. Each site is IR-diff-verified per the CStr-migration method; several batches
may reconverge.

- **Scope**: a bounded, enumerated site list — *not* a tree sweep. Each site edits
  signature lines (param `ptr`→`(ref StrView)` / `StrView`), so this is the same
  surface as defn-signature S3 and type-safety 14.3 (see edges).
- **Gate**: per-batch IR diff + `make test` + `make bootstrap`.
- **Refresh**: per batch as the pool shifts (never overlapping another item's window).

**Status: first NS-5 batch done (2026-07-05).** Two parallel-function migrations
rather than in-place signature retypes (both keep the old `ptr` function intact
and add a StrView-native `-sv` sibling, flipping only literal callers — see the
gotcha below). (1) `intern-string` (`src/scope.nuc:98`) gained
`intern-string-sv (sv:StrView):i32` beside it; the 2 literal callers
(`src/union-emit.nuc:84` and `:214`, both the `"nucleus: unwrap on error %s: %s\n"`
diagnostic-format literal) now call `intern-string-sv "…"` with no `strlen`. The
other 8 callers pass a `ptr` from `Node.s`/arena/`token` (no upstream length) and
stay on `intern-string`. (2) `register-rmacro` (`src/nucleusc.nuc:9343`) gained
`register-rmacro-sv (prefix:StrView wrap-sym:ptr):void`; `init-rmacros`'s 5
literal callers (`:9353-9357`) now pass `"~@"`/`"~"`/`"'"`/`` "`" ``/`"@"` directly
— the literal's carried `.len` replaces the `strlen`. `RMacro.prefix` audit: the
sole consumer (`lib/reader.nuc:429-434`) reads `prefix-len` and indexes
`prefix` byte-by-byte via `char-at` — never pointer-identity-compared, safe.

**Gotcha — by-value StrView field access needs `(addr-of sv)` first.** A
function parameter typed `sv:StrView` (by value) is a `TY-STRUCT`, not a
`TY-PTR`; neither head-position `(sv data)` nor `_get` work (both require a
pointer-to-struct receiver, per `emit-field-get` at `src/nucleusc.nuc:2172` and
the callable `get` path — error: "callable value: not callable — no matching
get/invoke method and not a pointer-to-struct"). The pattern (proven in
`examples/comb-order.nuc:30` and the `=` conformance at `lib/strview.nuc:152`)
is to bind `(p:ptr:StrView (addr-of sv))` once, then head-position `(p data)` /
`(p len)` through the pointer. This is the value-typed analogue of the existing
`(ref StrView)` access pattern; a `(ref StrView)` param is already a pointer and
needs no `addr-of`.

**Gotcha — a signature retype breaks ptr callers that the survey missed.**
`register-rmacro`'s task brief named "all 5 callers" (`init-rmacros`), but a 6th
caller exists: the `def-rmacro` handler (`src/nucleusc.nuc:8548`) passes
`(prefix-node s)` — an interned `Node.s` ptr (identity substrate, no carried
length). An in-place signature **retype** (`ptr`→`StrView`) breaks that caller.
The correct resolution is **polymorphic overloading** (see conventions.md
"Prefer overloads over name variants"): define a second `register-rmacro`
overload `(prefix:StrView wrap-sym:CStr)` alongside the original
`(prefix:ptr wrap-sym:ptr)`, so literal callers dispatch to the StrView overload
and `def-rmacro`'s ptr callers dispatch to the original. A distinct
`register-rmacro-sv` name was the first attempt but is now folded into the
overload — same for `intern-string-sv`→`intern-string`. **Lesson**: a survey that
finds "all callers are literals" must grep for the function name across the
*whole* tree (`src/` + `lib/`), not just the call sites the brief enumerated; and
when a function has mixed caller types, overload rather than fork the name.

**Dispatch adaptation gotcha.** In multimethod dispatch (`arg-adapts`), a
`StrView` argument adapts to a `CStr` parameter but **not** to a bare `ptr`
parameter. The first attempt at the `register-rmacro (prefix:StrView wrap-sym:ptr)`
overload failed because `"unquote-splice"` (a `StrView` literal) could not adapt
to the bare `ptr` second parameter — the compiler reported `"no matching method
for overloaded 'register-rmacro' with given argument types"` (no type detail).
Typing the second parameter `CStr` instead admits the `StrView` literal via
dispatch adaptation. To make this class of error self-diagnosing,
`generic-resolve`'s "no matching method" diagnostic (`src/generics.nuc:494`) now
prints the caller's argument types via `arg-type-spellings` — e.g. `"no matching
method for overloaded 'register-rmacro' with argument types (StrView, StrView)"`.

**Gate.** IR diff (`build/nucleusc.ll` before/after, temp names normalized):
the intended hunks — the new `@intern-string` overload (StrView→arena-strndup),
2 `@strlen` removals at the flipped `intern-string` sites (literal len `32` baked
as a constant via `insertvalue`), the `@register-rmacro` overload and 5 call-site
dispatch changes in `init-rmacros` (lens `2`/`1`/`1`/`1`/`1` baked in), and the
associated `%StrView` allocas / `insertvalue` / arg-shape changes. No `strcmp`→`icmp`
regressions. `@strlen` count 47→45 (the 2 intern-string flips; `register-rmacro`'s
`strlen` instruction remains for the retained `def-rmacro` ptr path — 5 runtime
invocations eliminated, 1 IR instruction kept). `make test`: 166/166. `make bootstrap`:
stage1.ll == stage2.ll, byte-identical fixed point.

### NS-6 — interning reconciliation, docs, conventions

- Document (§1.4) that literal "interning" (`g-strs`) and symbol interning
  (`intern-str`, `ptr`-identity) are distinct and *both unchanged*; `StrView` literal
  identity is its backing global; content dedup is out of scope for v1.
- **conventions.md**: new note — a `StrView` literal coerces freely to `CStr`/`ptr`
  (hidden NUL); `=`/`!=` mixed `StrView`/`ptr` is `strcmp`; **generalize the `Node.s`
  rule** — never retype an identity-`=` `ptr` to `StrView` (content `=`), the NS-5
  exclusion list.
- **docs/strings.md**: `"…"` now yields `StrView` (not `CStr`); the hidden-NUL/CStr
  borrow; `c"…"` for raw `CStr`. **docs/types.md**: the literal-type change and the
  `StrView`↔`CStr`↔`ptr` coercion lattice. **docs/toplevel.md** if it names the
  literal type.
- **Scope/Gate**: docs + one conventions note; no IR. Byte-identical.

**Status: done (2026-07-05).** The `conventions.md` "CStr is ABI-identical to
`ptr`" section was retitled and rewritten as **"The string-type lattice: `ptr` /
`CStr` / `StrView`"** — it now opens by naming all three types (`ptr` identity,
`CStr` content-`=` single-word, `StrView` 16-byte borrowed-view struct, the `"…"`
literal's type since NS-3) and states the interned-`ptr` substrate stays `ptr`.
Three additions: (1) a **free `StrView`→`CStr`/`ptr` coercion** paragraph (the
hidden-NUL hinge — a literal's `data[len]` is `\00`, so `data` *is* a sound
`char*`, no IR for a chameleon, one `extractvalue` for a materialized view; the
`strview-to-cstr` trust contract is the same shape); (2) the **mixed-operand
rule** extended — `=`/`!=` fire `strcmp` when either operand is `CStr` *or*
`StrView`, with a `StrView` operand contributing its `.data` to the `strcmp`; (3)
the **`Node.s` trap generalized** — never retype an identity-`=` `ptr` to `CStr`
*or* `StrView`, naming the NS-5 exclusion list (`Node.s`, scope keys,
struct-field names). The dispatch asymmetry note now records that a `StrView`
argument adapts to a `CStr` parameter but not a bare `ptr` parameter. The
interning distinction (§1.4 above) stands as written: `g-strs` is a per-literal
rodata emitter (content-keyed by table position), symbol interning (`intern-str`)
is `ptr`-identity dedup — the two were never the same mechanism, and NS-3/NS-5
changed neither. `docs/strings.md` §3 and `docs/types.md` (the literal-type
paragraph, the coercion-lattice row, and the `"…"`/`c"…"` literal-type table)
were already written during NS-3/NS-4 and required no further edit. `docs/toplevel.md`
does not name the literal's type (it says "string literal" without specifying
`StrView`/`CStr`, and the `defvar` storage note "storage type must be `ptr`"
remains correct — the `defvar`-init path emits a GEP ptr regardless of the
literal's inferred type), so no change was needed there. Gate: docs + one
conventions note only; no IR, no code, byte-identical by construction.

---

## 4. Verification and bootstrap convergence

- NS-1/NS-2 are additive/dormant → **byte-identical bootstrap**, no refresh.
- **NS-3 is the pivot**: its correctness proof *is* the `build/nucleusc.ll`
  before/after diff (the compiler's literals must all stay in `ptr`/`CStr` context and
  emit the bare GEP). A non-empty compiler-IR diff = a literal that reached an
  inference/`StrView` position → fix by annotation or consumer target type, exactly the
  CStr-migration regression signature (a `< strcmp` / `> insertvalue` hunk). `make
  bootstrap` (stage1==stage2) alone does **not** catch a mass literal-type shift (both
  stages share it) — the IR diff does. One reconverging refresh if the pool shifts.
- lib/examples IR moves (real, intended) ride `make test` output diffs.
- Never two refresh windows in flight (staging.md): NS-3's refresh must not overlap
  S3's quiet-tree window or a type-safety 14.x refresh, and NS-5's per-batch refreshes
  are serialized against the rest of the backbone.

## 5. Alternatives considered and rejected

- **Rewrite the compiler in `StrView`** (the folklore reading of "adopt native
  strings"). Rejected §1.2: breaks the interned-`ptr` identity substrate (`StrView`
  `Eq` is content), and fights libc at every `fprintf`/`snprintf` for no correctness
  gain. Selective adoption (NS-5) captures the real wins.
- **A brand-new builtin view type (`TY-STRVIEW`)** distinct from `StrView`. Avoids
  entangling the prelude with a lib layout, but forks the type — a literal would not be
  usable with the string API without a cast. Promoting the *bare struct* (NS-1) gives
  the same prelude availability and keeps one type.
- **Keep `"…"` = `CStr`; add `s"…"`/`v"…"` for views.** Minimal blast radius, but
  leaves the ergonomic default the unsafe C string forever and never delivers
  length-carrying literals as the norm — the inverse of the intended move. `c"…"` for
  the *rarer* FFI direction (NS-4) is the right asymmetry.
- **`String` (owning) literals.** Wrong for static data — allocation/`Drop` for rodata
  (§1.1).
- **Materialize every literal as a `{ptr,len}` struct unconditionally** (no
  target-aware emit). Correct but **not byte-identical** — every compiler `fprintf`
  arg becomes `insertvalue`+`extractvalue` instead of a bare GEP, forcing a whole-tree
  reconverge for zero behavior change. Target-aware emission (§2) is the difference
  between a byte-identical flip and a tree-wide churn.
- **Literal-header content dedup in `g-strs`.** Orthogonal size optimization; out of
  scope for v1 (§2, §1.4).

## 6. Dependency edges and backbone slot

Backbone (staging.md): **CP (done) → MC → LW → SM → S → T(14.x) → UN**, one refresh at
a time.

- **MC → NS-3 (hard).** NS-3's free `StrView`↔`ptr` coercion introduces a new
  mixed-branch join class — a value-position `(if c "a" some-ptr)` joins `StrView`/`ptr`
  and would `collapse-to-void` (conventions.md pointer-join rule). MC-1's
  join-absorption must exist first (and should absorb `StrView`↔`ptr` alongside
  bare↔`(raw Node)`), or NS-3 manufactures new join-collapse failures — the same edge
  MC has to 14.3.
- **NS-3 → T/14.3 (hard).** type-safety 14.x retypes registry/field/param slots; any
  string-carrying param it wants to move to `StrView` needs literals to *already* be
  `StrView` (so callers pass `"…"` bare). So **NS-3 lands before 14.x retypes string
  params** — the same "land the enabling type change before the retyping pass" shape as
  LW-1 → 14.3.
- **S → NS-5 (hard).** NS-5 edits signature lines (param `ptr`→`StrView`), the same
  lines as defn-signature S3's mechanical rewrite and 14.3's annotation pass. NS-5 runs
  **after S** (final signature syntax written once) and **out of S3's quiet-tree
  window**. NS-5's string-param retyping may be folded into 14.x or run as a distinct
  sibling pass immediately after.
- **NS → UN-4 (hard, tail).** NS-4's `c"…"` and any explicit `StrView`↔`CStr` cast
  spellings must align with unsafe-namespace's cast split; NS's casts land **before
  UN-4's sweep** (with MC-3/LW-5/14.x's cast-deletion work), so UN-4 renames them once.
- **CP-1 (soft).** NS-5 signature retypings use terse spellings; the list form
  `(x (ref StrView))` is safe regardless, but CP-1's chain fuse lets `x:ref:StrView`
  be used safely too.
- **LW / SM (none).** Orthogonal — int widening and symbol naming share no lines with
  the string-literal type; free order.

**Proposed slot.** NS is a **backbone item, not a small-band one** — NS-3 is a pivotal
breaking change. Split across the backbone:

1. **NS-1 + NS-2** pull forward into the small-item band **after MC** (join-absorption
   present), interleaved with LW/SM — they are additive/dormant and byte-identical, so
   they cost no refresh window.
2. **NS-3 (+ NS-4)**: the flip in its **own discrete refresh window**, slotted **after
   S** (so it does not compete with S3's quiet tree and the literal flip touches no
   signatures) and **before T/14.x** begins retyping string params (so 14.x can target
   `StrView`). Net position: **a new backbone step between S and T.**
3. **NS-5 + NS-6**: tail work, folded into or immediately after **T's** retyping, with
   NS's cast spellings feeding **UN-4** before the bare-spelling hard-error close-out.

One line: *promote the view type (dormant, free), flip the literal with a
target-aware, byte-identical emit and a free CStr borrow, then adopt selectively where
length pays — never touching the interned-`ptr` identity substrate.*
