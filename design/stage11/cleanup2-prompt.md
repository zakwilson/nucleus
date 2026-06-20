# Implementation prompt — Stage 11 Collections second cleanup pass

You are implementing the **Stage 11 collections second cleanup pass** for the
Nucleus self-hosting compiler. The specification is
**`design/stage11/cleanup2.md`** — it is the source of truth, including the
per-item rationale, the resolved decisions table (§3), and the sequencing (§4).
When this prompt and that doc disagree, the doc wins; if you think the design is
wrong, **stop and raise it** rather than silently diverging.

The premise: **associated types are implemented and validated** (A0–A4; the spike
`examples/assoc-iter-return.nuc` proves a protocol method can return a bare
associated type used as a later constraint's conforming variable). This pass spends
that capability and corrects the record that assumed its absence. **No new language
capability is introduced** except one contained compiler change (C2.0).

There are eight items of very different size and risk. Do them in the order in §4
below (mirrors cleanup2.md §4): the zero-risk doc sweep first, then the one
compiler change, then the protocol uplifts, then removals and judgement cleanups.

---

## 1. Required reading (do this first, do not skip)

1. **`design/stage11/cleanup2.md`** — the spec you are implementing (items
   C2.0–C2.8, decisions, sequencing).
2. **`design/stage11/assoc-types.md`** + **`assoc-types-extend.md`** — the
   associated-type machinery you are building on: `&where ((Proto Arg…) Var)`
   recovery, conformance-arg retention, `&where`-on-`extend`. §5 of assoc-types.md
   foresaw the `get`/`keys`/`vals` uplift as "mechanically possible … its own task."
3. **`examples/assoc-iter-return.nuc`** — the **proven pattern** for a value-return
   associated iterator (`mk-iter:It` + `&where ((IterColl It) C) ((Iterator E) It)`,
   driven via `(addr-of it)`). C2.1/C2.2 follow this shape.
4. **`CLAUDE.md`** (repo root) — the workflow rules. Not optional.
5. **`context/local.md`** — the mandatory subagent-delegation workflow and the list
   of available subagents.
6. **`context/build.md`**, **`context/macros-jit.md`**, **`context/repl.md`** —
   build flow, reader/JIT/macro mechanics (C2.0 and the `doseq`/`into` migration),
   REPL guidance.
7. Conventions you'll mirror / touch:
   - `src/nucleusc.nuc` — **`emit-get-with-callee` (~:7394)**, `emit-selector-value`
     (~:7305), `selector-literal-sym` (~:7292), `generic-find-method-exact` (~:4390),
     `generic-resolve` (~:4624), `emit-get-intrinsic`/`emit-computed-field` (C2.0).
   - `lib/coll.nuc` — the `Coll`/`Seq`/`Assoc`/`Set`/`Drop` protocols (C2.1/C2.2/C2.3
     edit the protocol heads; mind the existing "why `get` is `invoke`/why these are
     standalone" comments — those are what C2.7 corrects).
   - `lib/vector.nuc` / `lib/hashset.nuc` / `lib/hashmap.nuc` — the concrete
     conformers; `VecIter`/`HashSetIter`/`HashMapKeyIter`, `iter-init`/`hashset-iter`/
     `hmap-iter-keys`, `hmap-get` (C2.1/C2.2).
   - `lib/macros.nuc` — `doseq`/`into` (the generic-dispatch migration in C2.1).
   - `lib/iterator.nuc` — `UnaryFn`/`FoldFn` (the generic replacements for C2.5).
   - `lib/seq.nuc` — `Call`/`BinaryCall`/`IntIndexable` (removed in C2.5).
   - `examples/callable.nuc` — the only consumer of the C2.5 legacy protocols.

---

## 2. How to work (process — enforced by CLAUDE.md)

- **Delegate; do not implement everything in the orchestrating thread.** Plan the
  split, then dispatch each item (or sub-chunk) to a subagent, each chunk well under
  ~100K tokens:
  - **`systems-impl-engineer`** — the `get`-dispatch compiler change (C2.0) and the
    protocol-head + `doseq`/`into` macro changes (C2.1). Compiler/reader internals.
  - **`focused-task-implementer`** — well-specified library code once shapes are
    pinned (per-type `iter`/`get`/`keys`/`vals` conformances, the `(Entry K V)`
    struct, the `callable.nuc` migration).
  - **`build-test-runner`** — `make test` / `make bootstrap`, reporting results.
    **Run after every item.**
  - **`api-docs-writer`** — the C2.7 doc/comment sweep, C2.8 limitation tables, and
    docs for the new protocol surface.
  - **`Explore`** / **`general-purpose`** — read-only research (call-site audits)
    so file reading stays out of the main thread.
  Ask subagents for **concise summaries**, not file dumps.

- **Keep it green at every step.** After each item, `make test` passes and
  `make bootstrap` is a **byte-identical fixed point**. A bootstrap diff means you
  changed behaviour you didn't intend — investigate before proceeding. The two most
  likely to need a `make update-bootstrap` + re-converge cycle are **C2.0** (the
  `get` dispatch change) and **C2.1** (the protocol-head arity change); confirm the
  IR diff is *only* the intended change (C2.0's should be empty on current source —
  see the byte-identity argument in cleanup2.md C2.0).

- **Update docs and progress as a required closing step:**
  - `docs/` for every changed surface (`get` on `Assoc`, `iter`/`keys`/`vals`,
    the `(Entry K V)` map element, the removal of the legacy protocols).
  - `design/stage11/progress.md` — fold these in as they land; record any new
    limitation discovered.
  - **Self-improving context**: fix root causes; only add a `context/` note for a
    genuinely unfixable environment gotcha.

---

## 3. Verify the ground before you build

The committed `bin/nucleusc` may link a newer libLLVM than the container ships; if
it fails to exec (exit 126/127), rebuild from the committed IR with
`make boot-binary` (or `make ensure-boot`) before anything. Then confirm, with
throwaway `.nuc` files, the two load-bearing premises:

- **C2.0 premise (the blocker is real).** A *generic*, *value-keyed* `get` override
  on a parametric struct is **not** selected today: define a struct with a `get`
  method taking a non-symbol key and observe `(get s key)` falling through to the
  field intrinsic (or erroring), not dispatching to your method. Confirm `_get`
  always does raw field access and `get` is the override-then-intrinsic path. If a
  value-keyed generic `get` *already* dispatches, the C2.0 change is smaller than
  written — **stop and report**.
- **C2.1 premise (the spike pattern holds in a library).** Re-run
  `examples/assoc-iter-return.nuc` (or a reduced copy) so you have the value-return
  associated-iterator pattern working before reshaping `Coll`.

If either no longer holds as cleanup2.md claims, **stop and report**.

---

## 4. What to build (in order)

### C2.7 + C2.8 — doc/comment/limitation-table sweep (zero-risk, do first)
- Change every "impossible / not expressible without associated types" claim to the
  accurate "expressible; lifted (Cn) / deliberately standalone because …". Sites
  (cleanup2.md C2.7 table): `lib/coll.nuc` (the `iter`/`get`/`keys`/`vals`/`select`
  comments), `lib/seq.nuc:9`, `docs/collections.md` (24/58/79),
  `docs/special-forms.md` (~197–218), `docs/builtins.md` (~1251–1272),
  `docs/index.md:115`, `design/stage9/callable-values.md` (148–150),
  `docs/structs-unions.md` (~328); verify `docs/generics.md` stays consistent.
- C2.8: mark **parametric-structs.md Known limitation #3** (parametric-protocol
  `&where` frontier) resolved; sweep `progress.md` for rows listing it as deferred.
- *Accept:* no doc/comment asserts the false premise; no code touched; bootstrap
  trivially byte-identical.

### C2.0 — compiler: generalize `get` dispatch (prerequisite for C2.2a)
- In `emit-get-with-callee`, split on the selector (cleanup2.md C2.0):
  - **Literal-symbol selector** → **unchanged** (symbol→interned ptr; exact-`USER`
    override then field intrinsic). Field access untouched.
  - **Computed/value selector** → emit it as a value, take its real type `kt`,
    resolve a `get` override on `(callee-type, kt)` with a **non-dying generic
    resolve** (binds tyvars + checks `&where`, like `generic-resolve` but returning
    null on miss — add the helper if absent); on hit call it, on miss fall back to
    the existing computed-field intrinsic.
- Must **not** change resolution for any program that compiles today (the compiler
  uses only symbol selectors on its own structs, which define no value-keyed `get`).
- *Accept:* a throwaway `(get s key)` on a struct with a generic value-keyed `get`
  override dispatches to that method, for both a `CStr` and an `i32` key; `make
  bootstrap` byte-identical (IR diff empty); suite green.

### C2.2a — `get:(Maybe V)` on `Assoc`, delete `hmap-get` (depends on C2.0)
- Add `get:(Maybe V)` to the `Assoc` protocol (`V` is already a param — no new
  associated type). Implement it on `HashMap`, called as `(get m key)`.
- **Delete the redundant `hmap-get`** and migrate every call site
  (`docs/collections.md` examples, tests, any lib).
- *Accept:* `(get m k)` returns `(Maybe V)`; `hmap-get` is gone with no dangling
  references; suite green; bootstrap byte-identical.

### C2.1 — `iter` into `Coll` (value-return associated iterator) + `(Entry K V)`
- Reshape `(defprotocol (Coll E) …)` → `(Coll E It)` with `iter:It` (value return).
  **This changes every `(extend … (Coll T))`** — update `Vector`, `HashSet`,
  `HashMap` conformances in lockstep (landmine 3).
- Each conformer provides a value-returning `iter` (spike pattern: `alloca` + set +
  `(deref …)`), wrapping or replacing the fill-in-place `iter-init`/`hashset-iter`/
  `hmap-iter-keys`.
- **`HashMap`'s `Coll` element is a pair (C2.2c):** add `(defstruct (Entry K V)
  key:K val:V)`; `HashMap` conforms `(Coll (Entry K V) HashMapEntryIter)`, `iter`
  yields `Entry` by value.
- **Migrate `doseq`/`into`** to dispatch via the protocol `iter` (generic over any
  `Coll`), `addr-of`-ing the value internally to get the `(ref Iter)` `next` wants.
- *Accept:* `doseq`/`into` work generically over `Vector`, `HashSet`, and `HashMap`
  (pairs); existing iterator tests stay green; bootstrap byte-identical.

### C2.2b — `keys`/`vals` into `Assoc` (associated iterator types)
- Add associated iterator parameter(s) to `Assoc`; lift `keys`/`vals` to protocol
  methods (same machinery as C2.1). Reuses the C2.1 value-return convention.
- *Accept:* `keys`/`vals` resolve through the protocol; suite green; bootstrap
  byte-identical.

### C2.5 — remove the fixed-type function-object / indexable protocols
- Delete `Call` / `BinaryCall` / `IntIndexable` from `lib/seq.nuc`. Migrate
  `examples/callable.nuc` to `UnaryFn`/`FoldFn` (+ a generic indexable for the
  `(v i)` demo) and update `docs/special-forms.md` / `docs/builtins.md` /
  `docs/index.md`. (No compiler-internal use — audit confirmed.)
- **Do not** attempt a variadic `Call`: confirmed impossible (`&rest` is
  macro-level; gated on the stage888 variadic-defn deferral).
- *Accept:* the legacy protocols are gone with no dangling references; the example
  still demonstrates the capability via the generic protocols; suite green.

### C2.3 / C2.4 / C2.6 — judgement cleanups (lowest urgency)
- **C2.3:** `Set.select` stays standalone — correct the comment from "limitation" to
  "choice".
- **C2.4:** reconcile `design/stage11/collections.md` §Seq with the shipped lazy
  iterator combinators (`map`/`reduce`/`filter` are generic `Iterator` combinators,
  not `Call`-taking `Seq` methods); retire the "Call-first, provisional" framing.
- **C2.6:** frame `examples/phantom-tyvar-test.nuc` (and the verbose `MapIterVerbose`
  form) as **legacy/superseded by associated types**, kept only as a
  phantom-recovery regression test — not a recommended pattern.
- *Accept:* docs/comments reflect reality; no behaviour change; suite green.

---

## 5. Landmines (read before writing a line)

1. **C2.0 must be a no-op on current source.** The whole safety argument is that the
   compiler uses only symbol selectors on structs with no value-keyed `get`
   override, so every existing `get` resolves down the identical path. After C2.0,
   the bootstrap IR diff must be **empty**. A non-empty diff means the literal-symbol
   branch changed — fix before proceeding.
2. **Do not touch `_get`.** It is the raw field intrinsic (`emit-field-get`);
   field access on symbol selectors must stay byte-identical. C2.0 only changes the
   **value-selector** branch of `get`.
3. **Adding a protocol parameter is a breaking change to every conformance.**
   `(Coll E)` → `(Coll E It)` (and the `Assoc` keys/vals params) invalidates every
   `(extend …)` until updated. Change the protocol head and **all** conformers in
   the same step, or the suite/bootstrap breaks mid-flight. This is the biggest
   mechanical risk; do `Vector`/`HashSet`/`HashMap` together.
4. **Value-return iterators + `addr-of`.** `next` takes `(ref Self)`; the protocol
   `iter` returns by value, so consumers must `(addr-of (iter coll))` (bind to a
   local first). `doseq`/`into` must do this internally. Follow the spike.
5. **`(Maybe ptr)` is niche-encoded** — pointer element types can't `match`. Keep
   iterated element / `(Maybe E)` types non-pointer (the `Entry` pair is a value
   struct, fine; a map keyed/valued by raw `ptr` would need care).
6. **`.nuch` / cross-unit conformance.** Changing protocol arity affects exported
   conformances and lib headers (assoc-types.md §4.5). If a `.nuch` consumer breaks,
   recompile the producing lib; watch `make lib-headers` is not part of the gate.
7. **Don't reintroduce libc-shadowing method names.** `Drop` is `drop` (not `free`)
   on purpose (M1 finding); keep new method names clear of libc symbols.
8. **`hmap-get` deletion must be total.** Grep every call site (docs examples and
   tests included) before removing, or the suite breaks.

---

## 6. Definition of done

- C2.0–C2.8 implemented per `design/stage11/cleanup2.md`.
- `make test` passes; `make bootstrap` is a **byte-identical fixed point**.
- New examples/tests cover: `(get m key)` on a `CStr`- and an `i32`-keyed map
  (C2.0/C2.2a); `iter`/`doseq`/`into` over `Vector`, `HashSet`, and `HashMap` pairs
  (C2.1/C2.2c); `keys`/`vals` via the protocol (C2.2b); the migrated `callable.nuc`
  (C2.5). Add expected-output fixtures under `tests/expected/`.
- `docs/` updated for `get`-on-`Assoc`, `iter`/`keys`/`vals`, the `(Entry K V)` map
  element, and the legacy-protocol removal; the C2.7 rationale sweep done.
- `design/stage11/progress.md` reflects what landed; `design/overview.md` already
  references `cleanup2.md`.
- Any genuine unfixable environment gotcha noted concisely in the right `context/`
  file (root cause fixed otherwise).

## 7. Explicitly out of scope (do not build)

Variadic `Call` (confirmed impossible — gated on the stage888 variadic-defn
deferral); the M6 `String` work and the string-literal switch (separate doc); any
change to `_get` or to literal-symbol field access; lambdas/closures, `dyn`/
heterogeneous collections, persistent/immutable collections (all still deferred).
Persistent-collection or ordered-map (`Ord`-keyed) variants are not part of this
pass.
