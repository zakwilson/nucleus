# Cleanup from compiler refactor

The compiler refactor has revealed some ergonomic problems in the collections library.

## HashSet

This code is fucking ridiculous in its verbosity, and any developer not brain-damaged from years of writing Java would need half a bottle of whisky to deal with it:

```lisp
(defvar g-special-form-set:ptr)

(defn init-name-sets:void ()
  ; --- special-form-named set (72 members) ---
  (set! g-special-form-set (malloc (sizeof (HashSet CStr))))
  (hashset-init (cast (ref (HashSet CStr)) g-special-form-set))
  (insert (cast (ref (HashSet CStr)) g-special-form-set) (cast CStr "let"))
  (insert (cast (ref (HashSet CStr)) g-special-form-set) (cast CStr "with"))
  ; etc...
  )

(defn special-form-named:i32 (name:ptr)
  (return (contains? (cast (ref (HashSet CStr)) g-special-form-set) (cast CStr name))))
```

Both of these should be possible:

```lisp
(defvar g-special-form-set:ref:HashSet
  #{"let" "with"
  ; etc...
  })
```

```lisp
(defvar g-special-form-set:ref:HashSet)

(defn init-name-sets:void ()
  (set! g-special-form-set (HashSet CStr))
  (insert g-special-form-set "let")
  (insert g-special-form-set "with")
  ; etc...
  )
```

And one of these

```lisp
(defn special-form-named:i32 (name:Cstr)
  (return (contains? g-special-form-set name)))
```

```lisp
(defn special-form-named:i32 (name:ref:Cstr)
  (return (contains? g-special-form-set @name)))
```

```lisp
(defn special-form-named:i32 (name:ref:Cstr)
  (return (contains? g-special-form-set name)))
```

## Casts generally

Casts should be rare. Types should be appropriate for their typical use cases. Instead we have a bunch of wrappers full of casts such as

```lisp
(defn vec-push:void (v:ptr item:ptr)
  (conj (cast (ref (Vector ptr)) v) item))

(defn vec-len:i32 (v:ptr)
  (return (cast i32 (count (cast (ref (Vector ptr)) v)))))

(defn vec-get:ptr (v:ptr i:i32)
  (return (invoke (cast (ref (Vector ptr)) v) (cast usize i))))
```

---

## Resolution / plan (2026-06-20)

Root cause: the refactor typed every global as untyped `:ptr` and re-cast at each
use, added redundant `(cast CStr "lit")` (string literals are already `CStr`,
`src/nucleusc.nuc:3305`), and constructed via malloc-and-leak. `ref`/`ptr`/`CStr`
all lower to the same machine `ptr`, so stripping those casts is **IR-identical →
byte-identical-bootstrap-safe**. Three steps, each verified `make bootstrap`
(empty diff) + `make test` (102) + `make abi-test`:

### Step A — Tier 0: retype + de-cast (do regardless)

- Type globals `:(ref (Vector ptr))` / `:(ref (HashSet CStr))`, not `:ptr`.
- Type predicate params `CStr`; drop redundant `(cast CStr …)` on literals.
- Drop the `vec-*` wrappers; call sites use `conj`/`count`/`invoke` directly on
  the typed globals. (Index reads stay `(invoke v i)` until Step C lands.)
- Net: the only casts left are unavoidable `usize`↔`i32` index boundaries and one
  raw→ref at construction (removed by Step B).

### Step B — allocator-based construction (process-lifetime = arena)

The arena allocator (`ALLOC-ARENA`, `lib/allocator.nuc`) already has a no-op
`free`, so `drop` through it is a structural no-op — the correct model for
process-lifetime globals, and the faithful match for the original arena-backed
`Vec`. Resolves the Drop/lifetime "mismatch" cleanly.

- Add the library gap: `hashset-init-alloc` / `hashmap-init-alloc` (mirroring the
  existing `vector-init-alloc`), and heap `*-new-alloc` constructors that allocate
  the struct via the handle and return a typed `ref`.
- The compiler holds one shared arena `AllocHandle`; every compiler collection
  (globals + per-statement scratch) is constructed against it. No malloc, no leak,
  no per-use cast.

### Step C — `(v i)` routes to `invoke` (language fix)

`emit-callable-value` (`src/nucleusc.nuc:7594`) currently routes a single
literal-symbol arg to `get`. Change the default routing to **`invoke` → `get` →
`_get`**: if the callee type has a matching `invoke` method, route there; else a
custom `get`; else raw `_get` (field, literal-symbol only). Plain structs (no
invoke, no custom get) still reach `_get` → IR-identical for the bulk of the
compiler.

- Breaking consequence (accepted): `(coll-var fieldname)` field access on a type
  that *has* `invoke` no longer works via callable syntax — rewrite those to
  `_get`/`.field`. Purging them from the source is also what keeps the bootstrap
  byte-identical (no form routes differently under old vs new dispatch). Known
  site: the `vec-pop` helper's `(vp len)`.
- The compiler keeps explicit `(invoke v i)` (no `(v i)` adoption) so no boot shim
  is needed; the language now supports `(v i)` for everyone.

### Explicitly out (per direction)

Global collection literals / pre-main static-init (pre-main `#{…}` assigned to a
global directly). Use `into` + a constructor with the right allocator + a stack
literal instead — and that is exactly what the `init-name-sets` refactor below does.

---

## Implementation outcome — Steps A+B (2026-06-20)

Done. `make`, `make bootstrap` (byte-identical `stage1.ll == stage2.ll`),
`make test` (102/102), `make abi-test` all green. No `boot/` change.

Delivered:
- `vec-push`/`vec-len`/`vec-get`/`vec-pop` wrappers **deleted**. Use sites call
  `conj`/`count`/`invoke` directly on typed `(ref (Vector ptr))` globals/locals;
  `narrow-restore`'s pop reads/shrinks `len` via the raw `(_get VEC len)`
  intrinsic + `(.set! VEC len …)`.
- Globals `g-pending-unions` / `g-lbl-tbl` / `g-nundo` / `g-macro-decls` /
  `g-program-defns` / `g-mono-worklist` retyped `(ref (Vector ptr))`; the two
  name-kind sets retyped `(ref (HashSet CStr))`. Predicate params typed `CStr`,
  bodies cast-free (`(contains? g-set name)`); 3 call sites add one `(cast CStr
  name)`. Phi-builder scratch (`vals`/`preds`) typed `(ref (Vector ptr))`;
  narrowing-fact scratch (`scfacts`/`acc`/`tfacts`/`after`/`wfacts`) stay `:ptr`
  (only ever passed to helpers — zero casts there).
- Index/`usize` boundary: each Vec-walking loop counter is `usize` (no scattered
  casts); the lone `i32` cursors that aren't pure loop indices keep one boundary
  cast — `g-mono-drained` (`(< g-mono-drained (cast i32 (count …)))` +
  `(invoke … (cast usize g-mono-drained))`) and the narrow `mark` (`narrow-mark`
  returns `(cast i32 (count g-nundo))`, `narrow-restore` compares `(cast i32
  (_get g-nundo len))`).
- Step B: `(defvar g-arena-alloc:AllocHandle)` + `(arena-allocator (addr-of
  g-arena-alloc))` as the **first** statement in `compiler-init` (and REPL's).
  Library gap filled: `hashset-init-alloc` (`lib/hashset.nuc`) and
  `hashmap-init-alloc` (`lib/hashmap.nuc`), mirroring `vector-init-alloc`. Each
  compiler set/vector is arena-allocated (one raw→ref cast at construction).

### Hard bootstrap constraint discovered (load-bearing — read before Step C/D)

`make-vec` could NOT be retyped to the plan's `make-vec:ref:(Vector ptr)`, and
the four Vec-receiving helpers (`test-true-nonnull`, `test-false-nonnull`,
`narrow-names`, `emit-niche-match-arm`) could NOT take `(ref (Vector ptr))`
**parameters**, under the "don't touch `boot/`" rule.

Root cause: `prescan-defn-signatures` resolves every `defn`'s **signature**
(param + return types) over the whole unit *before* the per-form emission loop
runs — so a `(Vector ptr)` named in any signature is **stamped at prescan**,
queuing `%Vector.ptr = type { …, %AllocHandle }` on the pending-IR queue *before*
`(import vector)`/`allocator` emits `%AllocHandle`. The auto-prepended
`(import prelude)` is processed first; its `+`/`-`/… `defmacro`s each assemble a
JIT module that drains the pending queue (`drain-pending-union-irs`, see the
`(drain-pending-union-irs)` just before the macro-JIT assembly), emitting
`%Vector.ptr` into a module where `%AllocHandle` is still undefined → LLVM
"use of undefined type named 'AllocHandle'". A `(ref (Vector ptr))` *defvar*
does NOT trigger this (a ref lowers to an opaque `ptr`, never stamping the
pointee), and a *body* use stamps during emission (after the imports). Only a
**signature** occurrence stamps early.

Fixes that keep the unmodified boot happy AND byte-identical:
- `make-vec` returns `:ptr` (body-only `(Vector ptr)` use → stamped post-import);
  callers add one `(cast (ref (Vector ptr)) (make-vec))` at each construction.
- The four helpers keep `:ptr` params and cast once internally (callers pass
  `(cast ptr local)` where the local is typed).

A proper compiler-side fix (defer draining a stamped type whose struct field
dependencies aren't yet emitted) is real but is a **two-stage boot-refresh
change** — out of scope here (cannot land without rebuilding `boot/`). If Step C
needs concrete-typed collection signatures, sequence it as: (1) land the
deferral fix as its own byte-identical change + `make update-bootstrap`, then
(2) the concrete retype. The dependency-ordering note is also relevant to any
future parametric type embedding an imported struct used in a signature.

---

## Decision — accept the two-stage boot refresh (2026-06-20)

Accepted: take the boot refresh and finish the remaining work. Sequence:

1. **Stage 1 — deferral fix (dormant, byte-identical).** Make
   `drain-pending-union-irs` skip a stamped type whose named-type field
   dependencies aren't yet emitted *into the current module*, leaving it queued
   for a later drain (after the imports that define those deps). For the current
   source (`make-vec:ptr`, no `(Vector ptr)` in any signature) nothing is ever
   deferred, so emitted IR is unchanged → `make bootstrap` stays byte-identical.
   Verify (`make bootstrap` empty diff + `make test` 102 + `make abi-test`), then
   `make update-bootstrap` to bake the fix into `bin/nucleusc` + `boot/*.ll`.
2. **Stage 2 — retype `make-vec`.** With the fix in boot, retype
   `make-vec:ref:(Vector ptr)` and give the four Vec-param helpers
   (`test-true-nonnull`, `test-false-nonnull`, `narrow-names`,
   `emit-niche-match-arm`) `(ref (Vector ptr))` params; drop the workaround
   `(cast (ref (Vector ptr)) (make-vec))` / `(cast ptr local)` at call sites.
   `ref`/`ptr` lower identically → byte-identical against the refreshed boot.
3. **Step C — `(v i)` routes `invoke → get → _get`** (see plan above). Verify
   byte-identical bootstrap; final `make update-bootstrap`.

---

## Implementation outcome — Stages 1+2 (2026-06-20)

Done. Stage 1 baked into boot (`make update-bootstrap`, incl. Windows IRs);
Stage 2 applied and verified against the refreshed boot. No second
`update-bootstrap` after Stage 2 (deferred to the final Step-C boot refresh).

### Stage 1 — drain deferral (dormant, byte-identical)

Key finding on emitted-tracking granularity: the `emitted` flag is **global**,
but it is set *exactly* when a StructDef's `%Name = type {…}` line is written into
the **single shared** `g-type-bufp` buffer — and *every* module (batch output,
compile-time JIT, macro-JIT, REPL) concatenates that same buffer. So
`dep.emitted == 1` is precisely "the dependency's definition is present in the
module currently being assembled." No per-module emitted set is needed; the one
shared buffer plus the global flag already give per-module-correct semantics. The
real failure mode was **ordering within `g-type-bufp`**: a signature-stamped
`%Vector.ptr = type { …, %AllocHandle }` drained ahead of `%AllocHandle`'s
definition.

- New helper `pending-union-deps-ready:i32 (sd)` — returns 0 if any field whose
  kind is `TY-STRUCT`/`TY-UNION` (the only kinds that lower to a `%Name`
  reference; `TY-PTR` fields lower to opaque `ptr`, no named dep) has a `sdef`
  whose `emitted == 0` (or a null `sdef`); else 1.
- `drain-pending-union-irs` now emits a queued entry only when
  `pending-union-deps-ready` is non-zero; otherwise it skips it (entries are never
  removed, so it is retried on the next drain — after the import that defines the
  dependency has emitted it). Single-pass per drain (not a fixpoint) to preserve
  today's emission order exactly.
- Dormancy proof: `make bootstrap` was byte-identical **before** the boot refresh
  — i.e. the *old* boot binary (no deferral) and the *new* compiler (with it) emit
  identical IR, so the deferral never fires on the then-current source
  (`make-vec:ptr`). After `make update-bootstrap` + `make clean && make &&
  make bootstrap`, it reconverges byte-identically.

### Stage 2 — retype make-vec + four helpers

- `make-vec` returns `(ref (Vector ptr))` (dropped the trailing `(cast ptr v)`);
  the four helpers take `(ref (Vector ptr))` Vec params; the workaround
  `(cast (ref (Vector ptr)) (make-vec))` (16 sites), `(cast ptr vals/preds)`
  (2 sites), and the helpers' internal `(cast (ref (Vector ptr)) …)` casts are all
  gone. The five narrow-scratch locals (`scfacts`/`acc`/`after`/`tfacts`/`wfacts`)
  retyped `(ref (Vector ptr))`.
- **Spelling gotcha (load-bearing for any future parametric signature):** the
  colon-sugar form `name:ref:(Vector ptr)` does **not** parse for a defn
  name/param. The reader's `fuse-colon-paren` fuses `make-vec:ref:` + `(Vector
  ptr)` into the cell `(make-vec:ref (Vector ptr))`, and `extract-name-and-type`'s
  NODE-CELL branch takes the car (`make-vec:ref`) verbatim as the name **without
  re-splitting its colon** — so the function registers under the wrong name
  (`make-vec:ref`) and the `ref` wrapper is lost (→ "unknown: make-vec" at every
  call site). Use the **list form** instead: `(make-vec (ref (Vector ptr)))` for
  the return, `(out (ref (Vector ptr)))` for a param. This matches the existing
  parametric `defvar` spelling `(g-pending-unions (ref (Vector ptr)))` and routes
  through the working NODE-CELL path in `extract-name-and-type`.
- Validated end-to-end: `make` builds clean (the retyped signatures stamp
  `(Vector ptr)` at prescan; the prelude macro-JIT no longer errors on undefined
  `%AllocHandle`), and the output IR orders `%AllocHandle` before `%Vector.ptr`.
  `make bootstrap` byte-identical against the refreshed boot, `make test` 102/102,
  `make abi-test` green.

---

## Implementation outcome — Step C (2026-06-20)

Done. `(v i)` now routes `invoke → get → _get`. Final `make update-bootstrap`
(incl. Windows IRs) baked the routing change into boot; `make clean && make &&
make bootstrap` reconverges byte-identically. `make test` 102/102, `make abi-test`
green.

---

## Implementation outcome — `into` + `#{…}` for name-sets (2026-06-20)

Done. The two long `insert`-run blocks in `init-name-sets` replaced by single
`(into g-set #{ … } (HashSetIter CStr))` calls:

- `g-special-form-set`: 72 inserts → one `into` + 72-element `#{…}` literal.
- `g-primitive-type-set`: 19 inserts → one `into` + 19-element `#{…}` literal.

The arena allocation + `hashset-init-alloc` lines are unchanged (the destination
remains arena-backed / process-lifetime). The `#{…}` literal builds a throwaway
stack/libc-backed temp set; `into` copies elements into the arena destination; the
temp's one-time startup leak is irrelevant.

This is the in-function endorsed alternative to global collection literals (which are
still out — see "Explicitly out" above). The pattern is identical to what the
user verified manually: `(into dst #{"let" "with" "do"} (HashSetIter CStr))` against
a `(ref (HashSet CStr))`. Byte-identical bootstrap confirmed (`stage1.ll == stage2.ll`),
102/102 tests, `make abi-test` green. No `make update-bootstrap` needed (no change to
the generated IR — the compiler's name-set construction is identical in behavior).

---

### The routing change

`emit-callable-value` (and its type-pass mirror `callable-value-type`) now decide
by the **callee type**, not by the argument shape:

1. callee type has an `invoke` method → `emit-invoke-with-callee` (the arg is a
   **value**, so `(v idx)` evaluates `idx` and indexes);
2. else (single arg) callee type has a *custom* `get` method → `emit-get-with-callee`;
3. else (single literal-symbol arg) the raw `_get` field intrinsic.

New side-effect-free predicate `generic-has-receiver-method:i32 (g ct)`: scans the
generic `g`'s methods and returns 1 on the first whose **first parameter** accepts
`ct` — a METHOD-USER receiver `type-eq` `ct`, or a METHOD-GENERIC receiver pattern
that `unify-tpat` (the same structural unifier `generic-method-bind` uses) binds
against `ct` over the receiver alone (no args, scratch bound array → no side
effects). "Has invoke" = `(generic-has-receiver-method (generic-lookup "invoke")
ct)`; "has custom get" = the same against the `"get"` generic. The `get` *intrinsic*
is **not** a registered method, so an empty `get` generic correctly reports "no
custom get" and a plain struct lands on `_get` with byte-identical IR.

### Byte-identical: the purge was broader than narrow-restore

The compiler's own direct uses were already clean (`narrow-restore` reads `(_get
g-nundo len)`; the only other Vector-typed callable read, `(vp s)`/`(vp line)`, is
on a `ptr:Node` — Node has no `invoke`, so it stays `_get`). But two **library**
method bodies that the compiler stamps still used the callable field-read form on a
type that *has* `invoke`, and would have flipped to `invoke`:

- `lib/vector.nuc` — every `(self len)`/`(self cap)`/`(self data)` / `(v cap)` /
  `(v data)` inside the `(ref (Vector T))`-receiver methods (`count`, `conj`,
  `empty?`, `invoke`, `contains?`, `insert`, `capacity`, `reserve`, `vector-grow`,
  `drop`, `iter-init`) → rewritten to `(_get … field)`. (`VecIter T`'s `next`/its
  own reads are untouched — `VecIter` has no `invoke`.)
- `lib/string.nuc` — every `(v len)`/`(v data)`/`(v cap)` where `v:(ref (Vector
  ui8))` (`string-as-view`, `string-push-char`, `string-pop-char`,
  `string-truncate`, `string-reserve`, `string-shrink-to-fit`) → `(_get v …)`.

Only `Vector` defines `invoke`; HashMap/HashSet/Iterator/VecIter do not, so their
`(self field)` reads still route to `_get` (byte-identical). With these two libs
purged, `make bootstrap` was byte-identical on the first try.

### Example / test

`examples/callable.nuc` rewritten to the new contract: `Vec` (which has `invoke`)
reads its fields with `_get`, and `main` adds `(let (idx:i32 1) (v idx))` to
demonstrate that a **local index symbol** now indexes via `invoke` (prints
`vidx=20`, element 1) rather than mis-resolving to a field named `idx`. `Point`
(plain struct → `_get`) and `Temp` (custom `get` override → tier 2) still behave as
before. `tests/expected/callable.out` updated for the `v1`→`vidx` label; test count
stays 102.
