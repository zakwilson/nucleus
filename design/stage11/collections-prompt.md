# Implementation prompt — Stage 11 Collections

You are implementing **Stage 11 Collections** for the Nucleus self-hosting
compiler. The full specification is **`design/stage11/collections.md`** — it is
the source of truth. This prompt tells you how to approach the work, what order
to build it in, where the landmines are, and what "done" means. When this prompt
and the design doc disagree, the design doc wins; if you think the design is
wrong, stop and raise it rather than silently diverging.

---

## 1. Required reading (do this first, do not skip)

1. **`design/stage11/collections.md`** — the spec you are implementing.
2. **`design/stage11/parametric-structs.md`** and
   **`design/stage11/progress.md`** — the prerequisite machinery (now **done**,
   T0–T6). Everything in collections is built on this. Pay special attention to
   the *"Known limitations"* sections; several of them will shape how you write
   the collection code (see §5 below).
3. **`CLAUDE.md`** (repo root) — the workflow rules you must follow. They are not
   optional.
4. **`context/local.md`** — the mandatory subagent-delegation workflow and the
   list of available subagents.
5. **`context/build.md`**, **`context/macros-jit.md`**, **`context/repl.md`** —
   build flow, macro/JIT and reader-macro mechanics (you need this for the
   literal sugar), and REPL usage guidance.
6. Skim the existing conventions you'll mirror:
   - `lib/seq.nuc` — the `Call`/`Seq` function-object protocols (the `Call`-first
     argument convention you must keep, pre-lambda).
   - `lib/arena.nuc` — the existing bump allocator; it becomes the second
     `Allocator` conformance.
   - `lib/boxlib.nuc` / `examples/parametric.nuc` — the **working** patterns for
     parametric struct templates, methods, construction, and parametric-protocol
     conformance. Copy these patterns; don't reinvent them.
   - `docs/builtins.md` §"Parametric struct templates" / §"Parametric protocols".

---

## 2. How to work (process — enforced by CLAUDE.md)

This is a **large, multi-phase task**. Per `CLAUDE.md` and `context/local.md`:

- **Delegate. Do not implement the whole thing in the orchestrating thread.**
  Plan the split first, then dispatch each milestone (or sub-chunk) to a
  subagent, keeping each chunk well under ~100K tokens of context:
  - **`systems-impl-engineer`** — compiler-side changes (reader-macro literals,
    any emitter/typing work, the `String` literal switch).
  - **`focused-task-implementer`** — well-specified library code (each protocol,
    `Vector`, `HashSet`/`HashMap`, allocator conformances) once the shape is
    pinned down.
  - **`build-test-runner`** — running `make test` / `make bootstrap` and
    reporting results.
  - **`api-docs-writer`** — updating `docs/` and the progress tables.
  - **`Explore`** / **`general-purpose`** — read-only codebase research so file
    reading stays out of the main thread.
  Ask subagents for **concise summaries**, not file dumps. Reserve the main
  thread for planning and integration.

- **Keep it green at every step.** After each milestone, the compiler must still
  compile itself and pass the suite: `make test` passes and `make bootstrap` is a
  **byte-identical fixed point**. Because the registries/libraries are inert
  until used, every milestone *before compiler adoption* (§4, M1–M6) must keep
  the bootstrap byte-identical — a diff there means you changed compiler
  behaviour you didn't mean to. Only the compiler-adoption milestone (M8)
  intentionally changes compiler output; re-converge the bootstrap there.

- **Update the docs and progress as a required closing step**, not an
  afterthought:
  - Language docs in `docs/` (new protocols, the collection types, iterators,
    `doseq`, the literal sugar, the allocator protocol).
  - `design/stage11/progress.md` — add a collections table mirroring the existing
    parametric-structs table (Task / Description / Status / Key functions·files),
    and flip the Stage 11 row in `design/progress.md` from "Design only" once
    real work lands.
  - **Self-improving context**: if you hit a non-obvious environment/build/
    dependency gotcha, **fix the root cause** and, only if it can't be fixed, add
    a concise note to the right `context/` file. Don't document workarounds for
    things you can fix.

---

## 3. Verify the ground before you build

Everything is gated on the prerequisites. Before writing collection code, write
a tiny throwaway `.nuc` and confirm, end to end, that on this tree you can:

- spell `usize` / `ssize` in any type position;
- define `(defstruct (Vector T) data:(ptr T) len:usize cap:usize)`, stamp
  `(Vector i32)` in type position, and access fields;
- define a method `(defn count:usize (self:(ref (Vector T))) ...)` and have it
  monomorphize per concrete receiver;
- construct via the explicit form `((Vector i32) ...)`;
- define `(defprotocol (Seq E) ...)` and `(extend (Vector T) (Seq T))` with a
  stamp-time conformance check;
- drop a `with`-bound struct via the Stage 10 `Drop` protocol.

If any of these don't work as the prereq progress claims, **stop and report** —
do not work around a broken prerequisite.

---

## 4. What to build (milestones)

Follow the staging in `collections.md` §Staging (step 1, prerequisites, is
already done). Each milestone is a keep-green checkpoint. The protocols are
**core** (prelude-level, auto-available); the concrete types are **opt-in
libraries** (a program that never needs a `HashSet` shouldn't pay for it); `Hash`
is its own lib. Place files under `lib/` following existing conventions.

**M1 — Allocator protocol + default + arena conformance.**
- `Allocator` protocol (`alloc`/`realloc`/`free`) exactly as specified in
  `collections.md` §Memory model.
- A **default global allocator** over libc `malloc`/`realloc`/`free` behind the
  protocol, backing the no-allocator convenience constructors.
- An `Allocator` conformance for the existing `lib/arena.nuc` (bump: `free` is a
  no-op).
- Plumbing decision is already made: the allocator handle is a **stored field**
  on every owning collection; `conj`/`assoc`/`Drop` use the handle the
  collection was built with. Do **not** add the `(Vector T A)` type-parameter
  form — that's the deferred escape hatch.
- *Accept:* both allocators conform; a struct can store a handle and alloc/free
  through it; `make test` green, bootstrap byte-identical.

**M2 — Iteration: `Iterator` protocol, `into`, `doseq`, lazy `map`/`filter`/`reduce`.**
- `(defprotocol Iterator (next:(Maybe E) (self:(ref Self))))`; `none` ends the
  scan; `next` mutates the cursor. Single-threaded forward cursor only.
- `map`/`filter` return a **new lazy iterator** (a small struct wrapping source
  iterator + the `Call`); `reduce` drives an iterator to a value. **`Call`-first
  signatures** (pre-lambda) — see `lib/seq.nuc`.
- `into` materializes an iterator into a concrete collection
  (`(into (Vector i32) some-iter)`); it is required (lazy pipelines become owned
  data through it, and it's the reader-macro target).
- `doseq` macro: `(doseq (x coll) …)` expands to a `next`/`match`/loop over
  `(iter coll)`, terminating on `none`.
- *Accept:* a chained `map`→`filter`→`reduce` over a hand-rolled iterator works
  with no intermediate allocation; `doseq` iterates for side effects.

**M3 — `Vector` + capacity ops, `Coll`/`Seq` conformance, `Drop`.**
- Dynamically-sized, owns its buffer through its stored allocator; amortized
  doubling on growth. Implement the **recommended scope**: automatic growth +
  `reserve` / `capacity` / `with-capacity`. (Not the full unsafe `set-len!`/raw
  `data` surface.)
- Conform to `Coll` (`count`/`conj`/`iter`/`empty?`) and `Seq` (`map`/`reduce`/
  `filter`/`append`/`prepend`/`insert`/`get`/`find`/`contains?`). `conj`/
  `append`/`prepend`/`insert` **mutate in place**.
- Conform to **`Drop`**: frees the buffer (and drops owning elements first, per
  the existing union/`Drop` nesting rule) on scope exit.
- Mind `Seq.get` (index access via `invoke`, integer arg) vs the field `get`
  (symbol selector) — they coexist by argument-type dispatch; see §Seq in the
  spec.
- *Accept:* `with`-bound vector frees on scope exit; escape analysis still
  blocks return/store-out without `move`; growth, capacity ops, and both `get`
  forms behave.

**M4 — `HashSet` / `HashMap` on `Hash`, with `Coll`/`Set`/`Assoc` conformance.**
- `Hash` lib: `(defprotocol Hash (hash:usize (self:(ref Self))))` plus built-in
  conformances for the scalar types and `CStr` (the compiler already has
  `intern-hash` / `hash-struct-shape` to model these on). Keys/members require
  `Hash` **and** `Eq`.
- `HashMap` (`Assoc`: `get`/`assoc`/`dissoc`/`keys`/`vals`/`select-keys`) and
  `HashSet` (`Set`: `union`/`difference`/`intersection`/`select`/`contains?`).
  Set algebra **mutates the receiver**; `keys`/`vals` are lazy iterators. Both
  own their bucket array through the stored allocator and conform to `Coll` +
  `Drop`.
- Recall **`Coll` extends `Eq`** (structural compare — what lets a collection be
  a key/member alongside `Hash`).
- *Accept:* O(1) membership/get/insert/delete behave; collisions handled;
  iteration via `iter`/`keys`/`vals`; `Drop` frees buckets.

**M5 — Reader-macro literals `[…]` / `{…}` / `#{…}`.**
- Compiler/reader change (`systems-impl-engineer`; reader-macro infra exists from
  Stage 2 — see `context/macros-jit.md`, `lib/reader.nuc`). Expand to the
  explicit constructor over the **inferred** element type, building with the
  **default allocator**:
  - `[1 2 3]` → `((Vector i32) 1 2 3)`
  - `{"foo" 42 "bar" 7}` → `((HashMap CStr i32) "foo" 42 "bar" 7)`
  - `#{"dog" "cat"}` → `((HashSet CStr) "dog" "cat")`
- Inference uses the real scalar names (`i32`/`i64`/`f64`/`CStr`/…). **Mixed
  element types are an error** (`[1 2.0 3]` does not widen). **Empty literals
  `[]`/`{}`/`#{}` are errors** (element type uninferable) — the diagnostic points
  at the explicit constructor.
- *Accept:* literals compile to the right stamped constructors; mixed/empty
  literals produce clear errors.

**M6 — `String` (its own design doc first) + the literal switch.**
- `String` is **its own design doc** per the spec. **Write
  `design/stage11/string.md` first** (UTF-8, memory-safe, plausibly `Vector u8`;
  exposes **byte and codepoint iterators** rather than blanket-`extend Seq`,
  because UTF-8 indexing is not O(1); `upcase`/`downcase` deferred into that doc).
  Note it in `design/overview.md` and the progress tables. Get the design right
  before implementing.
- The **`CStr` → `String` string-literal switch is the riskiest piece** — the
  compiler uses `CStr` heavily. It comes **last**, after collections are stable,
  as part of compiler adoption.

**M7/M8 — Compiler adoption (end of stage).**
- Only once the types/protocols are rock-solid, adopt them in the compiler (the
  standard dogfooding step). This is a bootstrap cycle: the collections are
  written in Nucleus, used by the compiler, which compiles them. Sequence with
  care; the `String` literal switch is the final, riskiest move.
- *Accept:* compiler self-compiles using the new collections; **re-converge
  `make bootstrap` to a byte-identical fixed point**; full suite green.

---

## 5. Known landmines (read before you write a line of library code)

These come straight from the parametric-structs *Known limitations* and the
collections spec — they will bite if you forget them:

1. **Colon binding sugar with a parenthesized RHS does not tokenize.** A param
   spelled `name:(ref (Vector T))` is broken. **Use the list binding form:**
   `(name (ref (Vector T)))`. This is a pre-existing tokenizer limitation and you
   will hit it constantly in collection method signatures.
2. **`declare` with a parametric return type** needs the list-form name node:
   `(declare (vector_new (Vector i32)) (...))`.
3. **No `&where` bound on a parametric protocol** (`&where ((Seq E) Self)`) — the
   associated-types frontier is deferred. You get conformance via **`extend`
   + stamp-time checking + ordinary overload resolution** of the protocol methods
   on a conforming instance. Follow the working pattern in
   `examples/parametric.nuc`; do **not** try to write associated-type bounds.
4. **Parametric protocols bind the element at `extend`**: `(extend (Vector T)
   (Seq T))` binds `E := T`. The element type is supplied, never derived from
   `Self`.
5. **These collections are mutable / in-place / STL-spirit** — not Clojure
   persistent. `conj`/`assoc`/`append`/`prepend`/set-algebra **mutate the
   receiver**. The Clojure names are borrowed; the semantics are not.
6. **Ownership & `Drop`/escape** (Stage 10): every owning collection conforms to
   `Drop`; the existing escape/taint analysis blocks an owned collection from
   escaping by return/store-out without `move`; nested owners drop elements
   before the buffer.
7. **`Call`-first, pre-lambda.** `map`/`reduce`/`filter`/`find`/`select` take a
   `Call` function object first (`lib/seq.nuc`). These signatures are provisional
   until closures land (stage999) — that's expected, don't try to add lambdas.
8. **Index/size type is `usize`** (target-pointer-sized unsigned); `ssize` is the
   signed companion. `get`-by-index and `insert` take `usize`.

---

## 6. Definition of done

- All milestones M1–M8 implemented per `design/stage11/collections.md`.
- `make test` passes; `make bootstrap` is a **byte-identical fixed point** after
  compiler adoption.
- New examples and tests cover: each protocol, `Vector`, `HashSet`, `HashMap`,
  iterators + `into` + `doseq`, lazy `map`/`filter`/`reduce`, the literal sugar
  (including the mixed/empty error cases), allocator choice (default + arena),
  and `Drop`/scope-exit freeing. Add expected-output fixtures under
  `tests/expected/` as the existing tests do.
- `docs/` updated for every new public surface (protocols, types, iterators,
  `doseq`, literals, allocators, `String`).
- `design/stage11/string.md` written and referenced from `design/overview.md`.
- `design/stage11/progress.md` has a completed collections table; the Stage 11
  row in `design/progress.md` reflects reality; the "Deferred" entries for
  map/reduce/filter and Vectors/hashes are updated.
- Any genuine, unfixable environment gotcha noted concisely in the right
  `context/` file (root cause fixed otherwise).

## 7. Explicitly out of scope (deferred — do not build)

Subsequence/slice ops (`match?`, `subseq`), `BiIterator`/`prev`, persistent
/immutable collections + Clojure-style concurrency, heterogeneous collections
(need `dyn`, stage999), lambdas/closures (stage999), the `(Vector T A)`
allocator-type-parameter form, and the maximal unsafe `Vector` surface
(`set-len!`/raw `data`/`resize`).
