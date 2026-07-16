# Stage 14 — Declaration attributes: `:volatile`, `:thread-local`, and the keyword-attribute slot

Storage class specifiers were deferred at Stage 8 (tracked in
stage888-deferred.md until this doc absorbed the item; the overview's
oldest TODO). This doc resolves the deferral by committing to
a **keyword-attribute slot on declarations** — one extensible position that
absorbs the whole family C spreads across storage-class specifiers, type
qualifiers, and `__attribute__((...))`, without minting new definer heads or
growing the type grammar. Deliberately forward-looking rather than YAGNI:
the slot is the design; individual attributes arrive as they earn their way
in.

Committed now: **`:volatile` migrates to the slot** (retiring the postfix
type-qualifier spelling). Reserved with a diagnostic but **not implemented**:
`:thread-local` (blocked on a threading story — see §5). Sketched only:
`:static`, `:align`, `:section`, `:weak`, ISR/function attributes (§6).

---

## 1. Ground truth (verified 2026-07-02 by grep + read)

1. **Most C storage classes already have Nucleus spellings.** File-scope
   `static` = the private definers `defn-`/`defvar-` (internal linkage,
   docs/toplevel.md §Private definers); `extern` exists on both the
   producing (`defvar` default linkage) and consuming (`(extern name:type)`)
   sides; C23 `constexpr` ≈ `defconst`; `register` is dead (LLVM ignores
   it). The only genuine gaps are **function-scope statics** and
   **`thread_local`** — plus the qualifier/attribute family (`volatile`
   already shipped; alignment/section/weak have not).
2. **Volatile today is a postfix type qualifier.** Spellings `(T volatile)`
   and colon-sugared `T:volatile`, parsed by stripping a trailing
   `volatile` symbol in `parse-type-from-node`
   (src/union-registry.nuc:1152-1177, placed before the ptr/fn clauses so
   `(ptr i32 volatile)` ≡ volatile `(ptr i32)`); represented as an
   `is-volatile` flag on a cloned `Type` (`type-with-volatile` —
   src/compiler-types.nuc:196-198; primitive singletons are shared, hence
   the clone); honored by the scalar load/store helpers which emit
   `load volatile` / `store volatile` (src/nucleusc.nuc:5527-5544).
3. **Volatile's semantics are already declaration-shaped, not
   type-shaped.** docs/types.md:102-111: "volatility lives on the storage
   site (variable, struct field, or pointer target), not the value";
   `volatile T` ↔ `T` are assignment-compatible; `type-eq` ignores the
   flag; the qualifier is dropped/added at each access. Stage 8 chose this
   rule deliberately (design/stage8/volatile-plan.md §5). So volatility
   does **not** propagate through the type system — the type-position
   spelling buys nothing that a declaration-position spelling wouldn't.
4. **Every flag on `Type` re-litigates identity judgments.** `is-volatile`
   is excluded from `type-mangle-token` (src/compiler-types.nuc:78 comment)
   but **included** in the union-registry content hash
   (src/union-registry.nuc:28). Each is a considered call, and each future
   storage-class flag added to `Type` would multiply them across mangling,
   hashing, `type-eq`, dispatch, and monomorphization. Evidence for keeping
   further storage metadata **off** `Type`.
5. **Blast radius of a volatile syntax migration ≈ zero.** Grep-verified:
   the only volatile spellings in the tree are examples/volatile.nuc (all
   three forms: field, pointer-target param, let binding) and
   examples/logic.nuc:14 (`defvar trap-zero:i32:volatile`). **Zero uses in
   src/ and lib/**, so bootstrap byte-identity cannot be affected by any
   surface change.
6. **No reader work needed.** `:foo` keyword literals are a distinct node
   kind since Stage 11 cleanup §2 (`NODE-KEYWORD`, name stored in `s` —
   src/nucleusc.nuc:528, 931). A keyword can never be a declared name or a
   type, so a leading keyword in a declaration form is unambiguous.
7. **The declaration parse sites the slot touches** (each paired with its
   `node-type` view — the cross-file lockstep applies): `emit-defvar`
   (src/nucleusc.nuc:6530), `emit-let` (:5087) / `emit-with` (:5162),
   `emit-defstruct` fields (:6707) + `defunion` arms, `defn` param parsing,
   and `extern`/`declare` + the `.nuch` emitters (needed only when
   `:thread-local` lands).

---

## 2. Decision — the slot

**Grammar.** An attribute is a keyword literal appearing **immediately
before the declared name**, zero or more per declaration:

```lisp
(defvar :volatile trap-zero:i32 0)              ; def-forms: between head and name
(let (:volatile x:i32 0  y:i32 1) …)            ; binding lists: binds to the next name (x, not y)
(defstruct Reg flags:i32 (:volatile status:i32)) ; fields: parenthesized field, keyword head
(defn f (a:i32 (:volatile p:ptr:i32)) …)         ; params: parenthesized param, keyword head
```

- **Registry-driven.** The compiler holds a fixed attribute registry. An
  unknown keyword in attribute position is a source error naming the known
  attributes (typo safety — `:volatle` cannot silently no-op). The registry
  records whether an attribute is a flag (`:volatile`) or takes a value
  (`:align 64` — shape reserved, none implemented).
- **Never type identity.** Attributes do not participate in `type-eq`,
  overload resolution, dispatch, monomorphization, or name mangling. They
  qualify the *declaration*, full stop.
- **No colon-sugar spelling.** Colon-chain segments are names and types;
  attributes are not spellable as segments (`x:i32:volatile` dies in AT-3
  with a targeted diagnostic). Matches the existing precedent that sugar
  doesn't cover everything (parenthesized return types are space-separated).

**Positions in v1:** `defvar`/`defvar-`, `let`/`with` bindings,
`defstruct`/`defstruct-` fields, `defunion` arm fields, `defn` params.
Reserved for later attributes: the `defn` head (function attributes, §6),
`extern`/`declare` (`:thread-local`, §5).

---

## 3. `:volatile` — the migration (committed)

Two storage-site kinds exist (ground truth 3), and each gets exactly one
spelling:

1. **Named declarations** (variable, global, field, param):
   `:volatile` in the attribute slot. All loads/stores of that slot are
   volatile. If the slot holds a pointer, the *slot* is volatile (C's
   `T * volatile`), not the pointee.
2. **Pointer targets** — the MMIO case (C's `volatile T *`): the keyword
   moves *inside the pointer constructor*:

   ```lisp
   (defn bump-counter:void ((p (ptr :volatile i32)))
     (ptr-set! p (+ (deref p) 1)))
   (cast (ptr :volatile u8) 37)     ; usable in any type position, incl. casts
   ```

   Also `(raw :volatile T)` / `(ref :volatile T)`. This is the one
   type-position spelling that survives, because a pointer target genuinely
   *is* type-carried information (it must travel with the pointer through
   params and fields). It composes: `T` may itself be `(ptr :volatile U)`.

**Lowering is unchanged.** Both spellings lower to `type-with-volatile`
exactly as the postfix forms do today — attribute-on-declaration applies it
to the binding's type, `(ptr :volatile T)` applies it to the element. The
`is-volatile` representation, the load/store helpers, `type-eq`, and the
hash/mangle judgment calls (ground truth 4) are all untouched. This is a
pure front-end change, verifiable by IR-identity diff on the two example
files.

**Retired spellings** (AT-3): postfix `(T volatile)` list form and the
`volatile` colon segment. Both become targeted errors suggesting the new
spelling (the S4/UN-5 retirement pattern) — a trailing bare `volatile`
symbol in a type list is unambiguous to detect, so the diagnostic is cheap
and precise.

---

## 4. Why the slot and not the alternatives (rejected)

- **Postfix type qualifier extension** (`name:type:static` — the
  stage888-deferred candidate itself). Storage class is not a type
  property: `(ptr (i32 static))` is nonsense the grammar would have to
  reject piecemeal; every new `Type` flag re-litigates the
  mangle/hash/type-eq inclusions (ground truth 4); and there is no natural
  postfix spelling for valued attributes (`(T align 64)`?). Rejected —
  and §3 deliberately walks volatile *off* this shape.
- **Definer-suffix family** (`defvar-tls`, `let-static`). Matches the
  `defn-` privacy precedent but explodes combinatorially: private +
  thread-local = `defvar-tls-`? Every attribute × definer product mints a
  new head. Rejected.
- **`^` metadata sigil** (Clojure). New reader surface when `:foo` keywords
  already parse as a distinct node kind (ground truth 6). Rejected.
- **Wrapper forms** (`(thread-local (defvar …))`). No binding-position
  analogue — `(let ((static (x:i32 0))) …)` nests badly. Rejected.
- **Migrating privacy into the slot** (`:private`). The `defn-` suffix is a
  settled Stage 12 design; moving it is churn with zero expressiveness
  gain. Privacy stays on the definer. Likewise pointer kinds
  (`ptr`/`ref`/`raw`/`?`) stay type constructors — they are ABI- and
  identity-bearing, which is precisely what attributes are defined not to
  be.

---

## 5. `:thread-local` — reserved, not implemented

The user-visible half is genuinely trivial: `thread_local` prefixed onto
the `@name = global` emission line. What makes it out of scope is the
correctness tail plus the missing substrate:

- **Producer/consumer agreement is load-bearing.** TLS uses a different
  access model (different relocations); an `(extern …)` that doesn't know
  the producer is thread-local links fine and reads garbage. So the
  attribute must flow through `extern`, the `.nuch` round-trip, and
  `--emit-cheader` (`_Thread_local`) *in the same change* — a silent-wrong-
  code class, the worst kind.
- **JIT/REPL caveat.** ORC JIT TLS support is historically partial;
  macro-expansion JIT shares the emission path.
- **Nothing can exercise it.** The language has no threading story — no
  spawn primitive, no atomics, no memory model. A pthread-FFI test would be
  testing behavior the language doesn't define.

**Decision:** AT-1 adds `:thread-local` to the registry with a targeted
error ("thread-local storage requires the threading stage — see
design/stage14/attributes.md §5"). The slot design accounts for it, so no
re-design is needed when a threading stage arrives; the semantics above are
the spec it inherits.

---

## 6. Reserved sketches (uncommitted — recorded so the registry has a map)

- **`:static`** — function-scope static: a `let`-position binding backed by
  a fresh internal global instead of frame storage. Lexical visibility
  only; init restricted to constant literals per `defvar` rules (so no
  once-guard is ever needed); exempt from frame-local escape tainting (it
  is not frame storage); never dropped (process lifetime — same territory
  as the arena/no-op-drop global idiom). File-scope static remains
  `defvar-`. Add when a consumer appears.
- **`:align N`**, **`:section "name"`**, **`:weak`** — the `__attribute__`
  family; valued-attribute shapes. AVR's Harvard/rodata-placement work
  (avr-targets.md AVR-6) is the likely first consumer of `:section`.
- **Function attributes** — avr-targets.md AVR-5 plans an `fn-attr`
  directive for `"signal"`/`"interrupt"` ISRs. Candidate unification:
  attributes on the `defn` head (`(defn :fn-attr "signal" tick:void () …)`
  or dedicated `:signal`). Decided in AVR-5, not here; the slot merely
  guarantees a home exists.

---

## 7. Phases

- **AT-1 — the slot + `:volatile` + the reservation.** A shared
  `parse-decl-attrs` helper (leading-keyword scan against the registry),
  wired into `emit-defvar` / `emit-let` / `emit-with` / `emit-defstruct`
  fields / `defunion` arms / `defn` params, with the matching `node-type`
  views (lockstep). The `(ptr :volatile T)` / `(raw …)` / `(ref …)` element
  form in `parse-type-from-node`. Registry: `:volatile` implemented,
  `:thread-local` reserved-with-error, unknown-keyword error. Old spellings
  still accepted (dual acceptance). Additive and byte-identical (ground
  truth 5).

  **Status: DONE (2026-07-16).** `parse-decl-attrs` lives in
  src/union-registry.nuc alongside a new `attrs-normalize-bindings` helper
  for the `let`/`with` prefix-operand shape (`(:volatile x:i32 0 …)` is
  rewritten to the wrapped shape `((:volatile x:i32) 0 …)` before the
  existing binding-list walk runs). The wrapped shape
  (`(:volatile field:type)` — struct/union fields, defn params) folds into
  `extract-name-and-type`/`extract-name-type`, the shared helper every
  field/param already funnels through, so one change covers all those
  sites' lockstep automatically; `node-type-block` (src/generics.nuc) is the
  one `node-type` view needing an explicit mirror. `(ptr :volatile T)` /
  `(raw :volatile T)` / `(ref :volatile T)` added to all three branches of
  `parse-type-from-node`. Verified: old and new spellings emit
  byte-identical LLVM IR on an equivalent test program (module
  header/filename aside); `:bogus` and `:thread-local` die with the
  specified messages in every position; `make test` 178/178; `make
  bootstrap` byte-identical, no `update-bootstrap` (matching ground truth
  5's zero-blast-radius prediction — no volatile spellings exist in
  src/lib). `docs/` and `examples/volatile.nuc`/`logic.nuc` deliberately
  untouched, per AT-2 below.
- **AT-2 — migration + docs.** Rewrite examples/volatile.nuc and
  examples/logic.nuc to the new spellings; verify by emitted-IR identity
  diff. Docs sweep: docs/types.md + docs/builtins.md volatile sections
  rewritten around the slot, docs/toplevel.md (`defvar` row + the
  storage-class deferral note), stage888-deferred.md pointer, overview.md
  TODO close-out.

  **Status: DONE (2026-07-16).** `examples/volatile.nuc`/`logic.nuc`
  rewritten to `:volatile` throughout (attribute-slot on the field/let/
  defvar, `(ptr :volatile i32)` for the pointer-target param); `--emit-llvm`
  output byte-identical before/after on both files (volatile-marker counts
  unchanged: 10 in volatile.nuc, 2 in logic.nuc), and compiled-program
  stdout identical. `docs/types.md`/`docs/builtins.md` volatile sections
  rewritten with the new spelling primary and the old postfix spellings
  noted as still-accepted; `docs/toplevel.md`'s `defvar` row rewritten;
  `design/overview.md`'s TODO item updated to reflect AT-1 done/AT-2 done.
  `design/stage888-deferred.md` needed no edit — the storage-class item was
  already removed from that file during the 2026-07-02 prune once this doc
  absorbed it. `make clean && make` clean, `make test` 178/178 (docs/
  examples only, no compiler source changed, no bootstrap needed).
- **AT-3 — retire the old spellings.** Trailing-`volatile` type lists and
  `volatile` colon segments become targeted hard errors suggesting the new
  spelling. stage1 == stage2 throughout; no re-baseline at any phase.

  **Status: DONE (2026-07-16).** The postfix-stripping clause in
  `parse-type-from-node` (src/union-registry.nuc) that recognized a trailing
  bare `volatile` symbol and called `type-with-volatile` was replaced with a
  `die-at` naming the `:volatile` attribute-slot replacement: `"postfix
  'volatile' is retired: use the ':volatile' attribute (e.g. '(:volatile
  name:T)' for a declaration, or '(ptr :volatile T)' for a pointer target)"`.
  One chokepoint covers both retired spellings: `T:volatile` colon-sugar
  reduces to the identical trailing-symbol list shape via
  `split-colon-segments` before it ever reaches this clause, so no separate
  detection was needed for the two source forms. Two negative fixtures added
  (`tests/fixtures/at3-postfix-volatile.nuc` — `(ptr (i32 volatile))`;
  `tests/fixtures/at3-colon-volatile.nuc` — `x:i32:volatile`), both asserting
  the exact message. `docs/types.md`/`docs/builtins.md`'s "still accepted for
  now" note corrected to "retired: the compiler rejects them". As predicted
  (ground truth 5 — zero volatile spellings in src/lib), the change is
  inert for the compiler's own source: `make clean && make` one-pass,
  `make test` 180/180 (178 baseline + 2 new fixtures), `make bootstrap`
  byte-identical on the first try — no `update-bootstrap`. **AT-1 through
  AT-3 all done — the declaration-attributes workstream is closed out** aside
  from the out-of-scope items (§ Out of scope).

---

## 8. Sequencing

No edges to the CP → MC → LW → SM → S → T backbone (staging.md): the slot
touches declaration-form parsing, not signatures, joins, casts, or
mangling; and with zero volatile spellings in src/lib it is additive-small.
Slots anywhere outside S3's quiet-tree window (AT-2/AT-3 edit examples and
docs). One soft edge outward: **land AT-1 before AVR-4** so the hand-written
MMIO device register files are written in the final `(ptr :volatile T)`
spelling once; AVR-5/AVR-6 may then extend the registry (§6).

## Out of scope

- Implementing `:thread-local` (needs the threading stage: spawn, atomics,
  a memory model — §5)
- `:static` locals, `:align`/`:section`/`:weak`, function attributes
  (reserved sketches only — §6)
- Moving privacy (`defn-`) or pointer kinds (`ptr`/`ref`/`raw`/`?`) into
  the slot (rejected — §4)
- An enforced `(unsafe …)` block or any effect-ish attribute — that
  conversation lives in unsafe-namespace.md
