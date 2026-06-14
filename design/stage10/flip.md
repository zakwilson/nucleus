# Stage 10 — Phase F: the safety flip (implementation plan)

This is the build plan for **Phase F** of [errors-prompt.md](errors-prompt.md)
§"Phase F" — the deferred default-flip from [safety.md](safety.md) §3/§4.6 and
[nullability.md](nullability.md) §6. It is the **largest and only breaking**
item in stage 10. Read errors-prompt.md §"Phase F" for the *what/why*; this file
is the *how*, with the resolved staging and the measured scope.

## Where we are (Stage 1 — landed, converged, byte-identical)

The additive groundwork is done and folded into the boot:

- **`noreturn` attribute (F1)** — `die-at`/`repl_throw`/`exit`/`abort` etc. carry
  the LLVM `noreturn` attribute; a statement-position call terminates its block
  (`terminate-after-noreturn`), so `(when (= x null) (die-at …))` narrows past the
  guard. (This was already present; a null-deref crash in its `(declare …)`
  desugar on empty `()` param lists — `node-at` returns null for `()` — was fixed
  by guarding the trailing-`noreturn` probe at all three sites: `desugar-form`'s
  `declare`, `emit-nuch-declare-import`, and the `defn` body-position-0 check.)
- **`raw` spelling** — bare `raw`, `(raw T)`, and `raw:T` parse to a `TY-PTR`
  with `pkind = PTR-RAW` (today's unchecked/nullable pointer). New `ty-raw`
  singleton. ABI-identical to bare `ptr`.
- **`?ptr:Foo` / `?ref:Foo` spelling** — `parse-type-name` now delegates
  colon-containing strings to `split-colon-segments`, and `parse-type-from-node`
  handles a list head carrying a `?`/`!` prefix (the multi-colon desugar of
  `?ptr:Node` → `(?ptr Node)`). `?X` niche-encodes when `X` is a pointer
  (relabel its kind to `PTR-MAYBE`), else wraps as a niche pointer to the value
  (the historical `?Foo` form — kept identical for value operands, so Stage 1 is
  byte-identical). This means `?ptr:Foo` ≡ today's `?Foo`: both are
  `TY-PTR(elem=Foo, MAYBE)`.
- **CStr refinement** — `pkind-flow-check` treats `TY-CSTR` (string literals / C
  strings) as **ref-compatible**: a string literal is a non-null constant and is
  the overwhelmingly common CStr source, so flagging `"foo"` into a `(ref …)`
  slot would bury the flip under ~1500 false positives. A genuinely nullable C
  string is spelled `raw`, not CStr. (Inert pre-flip; byte-identical.)

`pkind` remains **ignored by `type-eq`, `hash-type`, `type-mangle-token`, and
`type-to-ir`** (nullability.md §9). This is the load-bearing invariant for the
whole flip: **changing a pointer's kind never changes emitted IR or mangling**,
so the boot (which still reads `ptr` as raw) and the flipped self-host emit
byte-identical IR. The flip moves only *compile-time checks*.

## Goal / completion criteria (errors-prompt.md "F done when")

1. `(ptr T)` / bare `ptr` mean **non-null** throughout (what `(ref T)` means).
2. Raw nullable pointers use the `(raw T)` spelling.
3. `?` is uniform `(Maybe T)` (no auto-`ref`-injection): pointer operand →
   niche; value operand → value-Maybe.
4. The compiler compiles itself, `make test` is green, `make bootstrap` is a
   fixed point, and all boot artifacts re-converge.

## Measured scope (instrumented non-fatal flip on self-compile)

With CStr treated as ref-compatible, a non-fatal flip first surfaced **~329
distinct typed sites** (down from ~1835 before the CStr refinement) — but on
inspection **every** one had an **elem-less (`void*`) destination**, not a typed
`(ptr T)`/`(ref T)` slot (N2 had already typed the real pointer slots). The
surplus was `null`/raw flowing into generic `void*` locals/params.

**Resolved outcome (what actually shipped):** a second refinement —
`pkind-flow-check` **exempts an elem-less destination** — landed the flip's teeth
on typed pointers only and made the per-site conversion **unnecessary** (0 batch
churn). A `void*` names no pointee and cannot be deref'd (`aref`/field access
dies first with "operand must be typed pointer"), so a non-null obligation on it
protects nothing; this is the direct analogue of the CStr-is-ref-compatible
refinement. The whole flip therefore reduced to:

1. the 5 parser edits below,
2. the CStr + `void*` flow-check refinements,
3. `addr-of` / `.&` / `alloca` / array-literal / compound-literal now yielding
   `PTR-REF` (a stack/field/binding address is always valid — this is what lets
   the examples' `p:ptr:T (alloca T)` type-check),
4. the `?` re-spelling: **~72 `?Foo` → `?ptr:Foo`** (mechanical; both parse to
   the identical `TY-PTR(elem=Foo, MAYBE)`) plus making `?`'s value-operand
   branch stamp the value-`Maybe`.

No genuinely-nullable typed-pointer slot needed re-spelling to `raw`. (The
`(raw T)` spelling exists and is used for new code / the C edge; the conversion
budget the rest of this section anticipated did not materialize.)

## The parser flip (small, do first)

These five edits make the new compiler *enforce* the flip. The boot still reads
`ptr` as raw, so it keeps compiling the (converted) source to identical IR.

1. `types-init`: `(.set! ty-ptr pkind PTR-REF)` — bare `ptr` is non-null.
2. `parse-type-from-node`, the `(ptr T)` branch: `(.set! pt pkind PTR-REF)`.
3. `node-type-sym` (`(when (= n 'null) …)`): return `ty-raw`, not `ty-ptr` — the
   `null` literal is raw, so it flows into `raw`/`?` slots but not `ref`.
4. The emit-side null (`(alloc-val ty-ptr "null")` in `emit-symbol`/literal):
   `ty-raw`.
5. `?` uniformity — **defer to the final pass** (see below); keep the Stage-1
   `?` behavior (niche-relabel-or-wrap) during the bulk conversion so existing
   `?Foo` keeps working while nullable `:ptr` sites are re-spelled.

## Conversion strategy (the ~329 sites)

**Enumerate first, then batch — do not fix one-at-a-time.** `die-at` aborts at
the first violation, so to see them all, temporarily make `pkind-flow-check` /
`require-derefable` print-and-continue (`fprintf stderr "FLOWVIOL… L%d %s"`)
instead of `die-at`. Build with the boot (it ignores the checks), run
`build/nucleusc --emit-llvm src/nucleusc.nuc 2>viol.err`, and group the
violations by line and `ctx` (`assignment` / `argument` / `return`). Convert in
batches by file and pattern, re-measuring after each batch. Restore the fatal
`die-at` before declaring done.

**Per-site judgment** (the only real work):

- A slot/param/return/field that is **genuinely nullable** (holds a lookup miss,
  a C return, an explicitly-cleared pointer, `null` init) → spell it `raw`
  (`x:raw`, `(raw T)`, `f:raw`), or `?ptr:T` if a checked Maybe is wanted.
- A slot that is **known non-null** but receives a value the checker can't prove
  → narrow at the source (`if-some`/guard) or `(cast ref:T …)` at an audited
  boundary (comment it).
- **C-imported declarations** (`include`/`.nuch`) keep returning nullable
  pointers; convert the *call-site locals* that hold their results to `raw`, or
  launder with `as-ref`. (Do **not** try to retype the C headers wholesale.)
- Keep edits **minimal and local**; prefer `raw` over inventing narrowing where
  the code already assumes success.

**Byte-identity holds throughout** because every `raw`/`ref`/`?` choice lowers to
the same IR `ptr`. After each batch: `make` (boot builds the new self-host),
`build/nucleusc` self-compiles (fewer violations), `make test` green, and
`make bootstrap` (stage1 == stage2) is a fixed point. The bootstrap fixed point
is the proof that no IR changed.

## The `?` uniformity + `?Foo`→`?ptr:Foo` (final mechanical pass)

Once self-compile is clean with the Stage-1 `?`:

1. Re-spell every `?Foo` (value-struct operand) → `?ptr:Foo` in src + lib. Both
   parse to `TY-PTR(elem=Foo, MAYBE)`, so this is byte-identical.
2. Make `?` **uniform**: in `parse-type-name`'s `?` branch and
   `parse-type-from-node`'s `?`-prefix handler, the value-operand else-branch
   stamps the **value-Maybe** template (like `(Maybe Foo)`) instead of wrapping
   as a niche pointer. After step 1 no bare `?Foo` remains, so this is
   byte-identical too.

## Convergence & green-tree discipline

- The clean Stage-1 state is the fallback (`/tmp/stage1-backup/clean-stage1.tgz`).
  Never leave the tree unable to self-compile or with failing tests at a stopping
  point — revert to the last green batch instead.
- Final convergence (build.md): `make clean && make && make update-bootstrap &&
  make clean && make && make bootstrap`, then `make test`. All boot flavors
  (Linux + Windows IRs + `bin/nucleusc`) re-converge in lock-step.

## Out of scope for the flip

- An `unsafe`-namespaced spelling for raw (arrives with namespaces — safety.md §3).
- A2 niche-encoded `!T` / `:repr` (deferred with U4).
- Retyping C headers' pointers to `raw` wholesale (call-site laundering only).
