# Implementation prompt — Stage 11 Collections cleanup

You are implementing the **Stage 11 collections cleanup** for the Nucleus
self-hosting compiler. The specification is **`design/stage11/cleanup.md`** — it
is the source of truth, including the per-item findings, root causes, and the
keyword/string overlap decision. When this prompt and that doc disagree, the doc
wins; if you think the design is wrong, **stop and raise it** rather than silently
diverging.

There are four items of very different size. Do them in the order in §4 (cheapest
and most isolated first). Three are small/medium and self-contained; one (4b) is a
**design doc only**, not an implementation.

---

## 1. Required reading (do this first, do not skip)

1. **`design/stage11/cleanup.md`** — the spec you are implementing.
2. **`CLAUDE.md`** (repo root) — the workflow rules. Not optional.
3. **`context/local.md`** — the mandatory subagent-delegation workflow and the
   list of available subagents.
4. **`context/build.md`**, **`context/macros-jit.md`**, **`context/repl.md`** —
   build flow, reader/JIT mechanics (needed for items 1 and 2), REPL guidance.
5. **`design/stage11/progress.md`** — the parametric-structs *Known limitations*
   (especially #1 colon-paren sugar, #3 parametric-protocol `&where`) and the
   collections M2/M4 limitations. Item 4 lives squarely in this territory.
6. **`design/stage11/string.md`** — the selected String design ("thin wrapper over
   a byte vector"). Item 2's shared `StrView` substrate must be built so M6 String
   reuses it. Read it before touching keyword.
7. Conventions you'll mirror:
   - `lib/reader.nuc` — `is-sym-char`, `lex-atom`, `next-tok`, and the existing
     reader-macro literal handling (items 1 and 2 are reader work).
   - `src/nucleusc.nuc` — `split-typed`, `extract-name-and-type`, `emit-let`,
     `register-generic-defn`, and the monomorphiser / tyvar-recovery path (item 4).
   - `lib/hash.nuc` — `fnv1a-byte` / `fnv1a-int` and the `CStr` Hash conformance:
     the **existing byte-fold** the `StrView` substrate must reuse, not duplicate.
   - `lib/allocator.nuc` — the single-self-contained-file convention the `StrView`
     substrate should follow.
   - `examples/parametric.nuc` / `lib/boxlib.nuc` — the working parametric-struct
     and parametric-protocol patterns.

---

## 2. How to work (process — enforced by CLAUDE.md)

- **Delegate; do not implement everything in the orchestrating thread.** Plan the
  split, then dispatch each item (or sub-chunk) to a subagent, each chunk well
  under ~100K tokens:
  - **`systems-impl-engineer`** — the reader sugar (item 1), the keyword reader +
    self-eval + `StrView` substrate (item 2), and the monomorphiser tyvar-recovery
    fix (item 4a). These are compiler/reader internals.
  - **`focused-task-implementer`** — well-specified library code once shapes are
    pinned (the `StrView` ops, keyword `Hash`/`Eq` conformances, the flattened
    example).
  - **`build-test-runner`** — `make test` / `make bootstrap`, reporting results.
  - **`api-docs-writer`** — `docs/` and the progress tables.
  - **`Explore`** / **`general-purpose`** — read-only research so file reading
    stays out of the main thread.
  Ask subagents for **concise summaries**, not file dumps.

- **Keep it green at every step.** After each item, `make test` passes and
  `make bootstrap` is a **byte-identical fixed point**. Items 1–4 are all meant to
  keep the bootstrap byte-identical: the reader sugar is additive, keyword/StrView
  are inert until used, and item 4a must not change compiler output on any program
  that compiles today. A bootstrap diff means you changed behaviour you didn't
  mean to — investigate before proceeding. (The reader change in item 1 and the
  monomorphiser change in 4a are the two most likely to need a `make
  update-bootstrap` + re-converge cycle; confirm the diff is *only* the intended
  change.)

- **Update docs and progress as a required closing step:**
  - `docs/` for every new public surface (the binding sugar, keyword literals + the
    `StrView` substrate; a one-line note that the list binding form composes in a
    multi-binding `let`; the item-4a behaviour change).
  - `design/stage11/progress.md` — fold these into the collections progress as they
    land; record any new limitations discovered.
  - **Self-improving context**: fix root causes; only add a `context/` note for a
    genuinely unfixable environment gotcha.

---

## 3. Verify the ground before you build

The findings in `cleanup.md` were taken on a boot-rebuilt `bin/nucleusc`. On this
host the committed `bin/nucleusc` links a newer libLLVM than the container ships;
if it fails to exec (exit 126/127), rebuild it from the committed IR with
`make boot-binary` (or `make ensure-boot`) before doing anything. Then re-confirm,
with throwaway `.nuc` files, the two load-bearing findings:

- A single flat `let` with multiple list-form bindings compiles and runs (item 3
  premise) — so you only flatten the example, you do **not** change `let`.
- `(defstruct (Two I F S E) a:I b:F)` + a method using phantom `S` reproduces the
  crash (item 4a) — so you have a minimal repro before touching the monomorphiser.

If either no longer reproduces as `cleanup.md` claims, **stop and report**.

---

## 4. What to build (in order)

### Item 3 — flatten `iterator-test.nuc` (trivial, do first)
- Collapse the nested `let`s in `examples/iterator-test.nuc` into one flat
  multi-binding `let`. Output and the `.out` fixture are unchanged.
- Add a one-line docs note that the list binding form `(name type)` composes in a
  multi-binding `let`.
- *Accept:* byte-identical program output; bootstrap byte-identical.

### Item 1 — colon-paren binding sugar (small)
- In the reader, when an atom token ends in `:` and is **immediately** (no
  whitespace) followed by `(`, fuse them into the list node `(name <paren-form>)`
  — the exact form `extract-name-and-type` already accepts. Make it work in every
  binding position the list form already works (defn name, params, `let`/`with`
  bindings, defstruct fields, defvar).
- Additive: no current source writes a trailing-colon atom adjacent to a paren.
- *Accept:* `v:(ref (Vector i32))` in a param and in a `let` binding compile
  identically to their list-form spellings; `make bootstrap` byte-identical.

### Item 4a — fix phantom/positional tyvar recovery (medium, isolated)
- Diagnose why a multi-param struct template whose **trailing type params are not
  used in any field** fails method monomorphisation (`unknown type: S`) and
  segfaults in the reduced case. Fix the recovery so all declared type params are
  bound from the concrete receiver's positional type args, phantom or not.
- **Minimum bar:** the segfault becomes a **clean diagnostic**. **Target:** a
  verbose generic `MapIter` that threads explicit `S`/`E` params compiles,
  monomorphises, and runs.
- Must **not** change compiler output for any program that compiles today —
  re-converge `make bootstrap` and confirm the diff is empty (the fix only affects
  templates that previously errored/crashed).
- *Accept:* the `(Two I F S E)` repro no longer segfaults; a generic element-typed
  `MapIter`/`FilterIter` over non-pointer elements works end to end; bootstrap
  byte-identical; suite green.

### Item 2 — keyword type on a shared `StrView` substrate (medium)
Build the shared substrate **first**, then keyword on top. Follow the overlap
decision in `cleanup.md` §2 exactly.

- **`lib/strview.nuc`** — a self-contained lib (like `lib/allocator.nuc`) exposing
  an immutable, length-prefixed UTF-8 byte slice `StrView { data:(ptr u8),
  len:usize }` with: `len`, byte `=` (Eq via `memcmp`), byte `hash` (Hash —
  **reuse `lib/hash.nuc`'s `fnv1a-byte`**, do not duplicate the fold), and a
  `CStr` bridge (to/from). Keep the full `Char`/UTF-8 codepoint layer **out** —
  that belongs to M6 String's doc.
- **Keyword** — reader recognises a leading-colon token as a keyword literal;
  representation is an **interned** handle over a `StrView` (identity eq + cached
  hash); `:foo` self-evaluates; `Hash` + `Eq` conformances so it is a usable
  `HashMap` key. The intern pool is keyword-specific. Do **not** make keyword
  owned/growable.
- M6 String must be able to import `lib/strview.nuc` and reuse its byte/eq/hash
  layer — verify the substrate is genuinely reusable (don't bake keyword-only
  assumptions into it).
- *Accept:* `:foo` self-evaluates; `(= :foo :foo)` true / `(= :foo :bar)` false;
  a keyword works as a `HashMap` key; `lib/strview.nuc` is a separate importable
  lib with no keyword-specific coupling; keyword/StrView are inert until used so
  the bootstrap is byte-identical.

### Item 4b — associated types (DESIGN DOC ONLY, do last)
- Write **`design/stage11/assoc-types.md`**: the surface syntax for a protocol
  exposing an associated type (so `(Iterator E)` derives `E` and combinators stop
  needing phantom params), and the stamping / conformance-checking changes it
  implies. Reference parametric-structs *Known limitations #3* and the item-4a
  findings. Note it in `design/overview.md`.
- **Do not implement.** This is a forward-looking design artifact.
- *Accept:* the doc exists, is referenced from `design/overview.md`, and is
  concrete enough to be the next implementation prompt's source of truth.

---

## 5. Landmines (read before writing a line)

1. **Colon-paren sugar does not tokenise *until you implement item 1*.** While
   writing the keyword/StrView library signatures (item 2), use the **list binding
   form** `(self (ref StrView))`, never `self:(ref StrView)` — unless you've
   already landed item 1, in which case dogfood it.
2. **`&where` constraints must be `(Protocol Var)` with plain symbols.** Do not try
   to bound a generic on a parametric protocol (that's 4b, design only).
3. **`(Maybe ptr)` is niche-encoded** — pointer element types can't `match`. Keep
   generic-iterator element types non-pointer (item 4a verification).
4. **Reuse, don't duplicate, the byte fold.** Keyword/StrView hashing goes through
   `lib/hash.nuc`'s `fnv1a-byte`; the `CStr` conformance is the model.
5. **Reader changes shift nothing in current source but must re-converge the
   bootstrap.** After items 1 and 4a especially, run the bootstrap fixed-point and
   confirm the IR diff is exactly the intended change (often empty).
6. **Keyword scope discipline.** Bytes-in / identity / hash / eq / print only. No
   ownership, growth, mutation, or `Char`/codepoint surface — those are M6 String.

---

## 6. Definition of done

- Items 1, 2, 3, 4a implemented per `design/stage11/cleanup.md`; item 4b delivered
  as `design/stage11/assoc-types.md` (design only).
- `make test` passes; `make bootstrap` is a **byte-identical fixed point**.
- New examples/tests cover: the binding sugar (item 1), keyword literals + equality
  + use as a `HashMap` key + the `StrView` substrate (item 2), the flattened
  iterator example (item 3), and a generic element-typed iterator combinator
  (item 4a). Add expected-output fixtures under `tests/expected/`.
- `docs/` updated for the binding sugar, keyword/`StrView`, the multi-binding-`let`
  note, and the item-4a behaviour.
- `design/stage11/progress.md` reflects what landed; `design/overview.md`
  references `design/stage11/assoc-types.md`.
- Any genuine unfixable environment gotcha noted concisely in the right `context/`
  file (root cause fixed otherwise).

## 7. Explicitly out of scope (do not build)

Associated-types *implementation* (4b is design only); any change to `let`
(item 3 is a no-op example flatten); ownership/growth/mutation or the full
`Char`/UTF-8 codepoint layer on keyword (those are M6 String); `&where` bounds on
parametric protocols; lambdas/closures (stage999).
