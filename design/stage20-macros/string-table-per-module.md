# The string-literal table, one per module

**Status: done.** Phases `S1`–`S4`, all landed 2026-09-15. Promoted out of
[stage888-deferred.md](../stage888-deferred.md) on 2026-09-15, where it was
recorded as measurement without a fix.

---

## 1. The defect

`g-strs` (`src/nucleusc.nuc:225`) is a single global vector, and
`emit-string-table` (`:16377`) writes **all** of it into whichever module is
being assembled. A macro body's quasiquote interns its symbol spellings into the
same table the program module emits, so those constants are emitted into the
program and never referenced by it.

Measured 2026-09-11: a hello-world-sized program carries **92 dead `@.str`
constants** before its first line of code — `_+`, `+`, `_*`, `cond`, `let`,
`while`, `match`, `macrolet` and the rest of `lib/prelude.nuc`'s macro bodies.

It is not only the prelude. Stage 20 M5's two `macrolet` bindings in
`src/repl.nuc` — a 54-row table, twice — put **125 dead constants** into
`build/nucleusc.ll` on their own. A table-driven refactor is the shape that pays
most, so the cost lands on the idiom the compiler is being pushed toward.

The second-order cost is the one that bites development: adding a macro to
`lib/macros.nuc` renumbers every string after it in every program, which is why
a change to the prelude can never be byte-identical.

## 2. Why the fix is small

Two properties, both checked before planning rather than assumed:

* **There is no interning cache to invalidate.** `intern-string`
  (`src/scope.nuc:167`) appends unconditionally and returns the new element's
  position — identical strings already get distinct ids. So the table is pure
  append-only state, and swapping the vector needs no companion map reset.
* **The save/restore slot already exists.** Every compile-time module path
  already brackets a "redirect global state" block that saves and restores
  `g-qq-used`, `g-out`, `g-decl-out` and friends (`:15639`, `:16024`). `g-strs`
  belongs in exactly those `let`s, beside `saved-qq-used`.

## 3. The exception that makes this more than a find-and-replace

**`ct-mirror-flush` must keep emitting the program's table.** It copies program
`define` spans out of `g-def-buf` into the mirror module, and those spans
reference program `@.str.N` ids. Its `emit-string-table` call (`:15455`) is
there for that reason; giving the mirror module a fresh table would leave every
copied span pointing at a constant that is no longer in it.

So of the four `emit-string-table` callers, three take a fresh table and one
does not:

| site | module | fresh table? |
|---|---|---|
| `:15850` | a `(compile-time …)` block | yes |
| `:16215` | a macro/CT body (`compile-macro-body`, `ct-eval-node`) | yes |
| `:19677` | `assemble-module-ir`, the program | yes — this is the one that stops carrying the others' strings |
| `:15455` | `ct-mirror-flush`'s mirror | **no** — copied spans reference program ids |

Private `unnamed_addr` constants are module-local, so a CT module's `@.str.0`
and the program's `@.str.0` do not collide even while both are in the JIT.

## 4. The gate is the interesting part

This moves bytes in every program in the tree, including the compiler's own IR.
`make bootstrap` diffs `build/nucleusc.ll` (emitted by the *old* `bin/nucleusc`)
against `build/stage2.ll` (emitted by the new compiler), so it reports a
divergence **by construction** until the boot binary is converged
([context/build.md](../../context/build.md), "After a codegen change").

Self-consistency can be established without touching committed artifacts, and
that is what S1 is gated on: compile `src/nucleusc.nuc` with `build/nucleusc`,
build that IR into a stage2 binary, recompile with it, and diff the two IRs.
Codegen is deterministic, so they must be identical.

Converging the committed boot is a separate step with a separate authorisation,
because `make update-bootstrap` rewrites `boot/nucleusc.ll` **and** invokes
`windows-boot`, overwriting the two committed Windows boot IRs. The deferred
entry asked for its own gate and its own commit for exactly this reason.

## 5. Phases

**S1 — the swap. DONE 2026-09-15, see §6.** `g-strs` saved, replaced with a
fresh vector, and restored in the CT module paths; `ct-mirror-flush` left alone,
with a one-line comment saying why. *Gate:* self-consistency by the direct
method above; `make test` green; and the measurement repeated — dead-constant
count for hello-world (92 before) and the `build/nucleusc.ll` delta. **Built as
a watermark rather than a swap — §6.1 is the correction and why the swap does
not survive its own §3.**

**S2 — converge. DONE 2026-09-15.** `make clean && make && make update-bootstrap
&& make clean && make && make bootstrap`, run under explicit authorisation. The
cycle passed first time: `PASS: stage1.ll == stage2.ll` at the new fixed point,
`PASS: bootstrap complete`, `make test` 1044/0/0. `boot/nucleusc.ll` and both
Windows boot IRs were rewritten in lock-step, as `update-bootstrap` intends —
the divergence §4 predicted was staleness and nothing else.

**S3 — pin it. DONE 2026-09-15, see §7.** A tree-wide assertion in
`tests/suite-audits.nuc`, which is where invariants of this shape already live:
a program that uses no string literals of its own emits no string table. Without
it the regression is invisible — the symptom is bytes nobody reads.

**S4 — the compile-time-only import's sink. DONE 2026-09-15, see §9.** Found by
S1's sweep. The last dead constants in the tree come from `emit-import-forms`'
throwaway `sink`, not from a CT module; §6.5 has the mechanism and why a
watermark there is not the same one-liner. *Gate:* the corpus claim §7 could not
make yet — no program module defines an `@.str` nothing references — promoted
into `tests/suite-audits.nuc` with no allowlist. **§8's plan held; §9.1 is the
one row it was missing.**

**Documentation:** [stage888-deferred.md](../stage888-deferred.md)'s entry
becomes a pointer here; [overview.md](overview.md) and
[progress.md](../progress.md) gain the phase.

---

## 8. S4 — the plan

### 8.1 Why neither of S1's two tools transfers

S1 has a watermark and the deferred entry had a swap, and **the sink window
defeats both for the same reason**: it is not a window in which all interning is
discardable. `emit-toplevel-forms` runs `drain-mono-worklist` at every depth and
a drain writes to `g-def-stream-program` — the real buffer, deliberately
distinct from `g-def-stream` precisely so a stamp survives an `import-ct`
(`src/nucleusc.nuc:296`). So inside one window the table receives two kinds of
string, interleaved, and a positional id cannot tell them apart: truncating
takes live stamp references with it, and keeping is today's leak.

Promoting the survivors out of the tail is not open either — an id *is* a
position, so moving one renumbers everything after it.

### 8.2 The fix: emit what is referenced, not what was interned

Filter at the point of emission instead of tracking provenance. `emit-string-table`
already writes `@.str.<sl 'id>` from the stored id rather than from the loop
counter, so **the table may be sparse**: dropping an entry renumbers nothing,
and a gap is not a thing LLVM can object to.

The referenced set is fully determined by state that exists when
`assemble-module-ir` runs:

* `g-type-stream`, `g-decl-stream`, `g-def-buf` — scan for `@.str.<digits>`;
* `g-deferror-name-sids` — read the ids directly. **This one is not optional and
  not in the buffers:** `emit-deferror-table` (`:16428`) emits `ptr @.str.<sid>`
  *after* the string table, so a scan of the buffers alone would drop every
  deferror name.

Scan the ids, not the texts, wherever a vector of ids already exists; parse the
full integer run when scanning text, so `@.str.1` does not match `@.str.10`.

### 8.3 Why this is the right shape and not a bigger hammer

It closes the leak **by construction rather than by enumeration** — any future
path that interns into a discarded stream is covered without being found first,
which matters because S1's own sweep is how this one surfaced. It also retires
the allowlist §7 needed, making the honest tree-wide claim available to S3's
test.

Scope it to the program module (`assemble-module-ir`), and consider the REPL's
per-entry module (`src/repl.nuc:1465`) and the mirror
(`ct-mirror-emit-module`) separately: both take the whole table today, and the
mirror's correctness rests on the spans it copies, so it gets the same treatment
only if the scan covers exactly the text it emits.

### 8.4 The gate, and a prediction worth checking first

S1 left `build/nucleusc.ll` with **zero** dead constants, so if this fix is
correct it should change the compiler's own IR **not at all** — no renumbering,
nothing to drop. **`make bootstrap` is therefore expected to stay
byte-identical, and S4 should need no boot convergence.**

That is a prediction, and it is the first thing to check: if the compiler's IR
*does* move, either S1's measurement was wrong or the filter is dropping
something live. Either way, stop and report rather than converging.

*Gate:* `make bootstrap` byte-identical; `make test`; the three known leaks
(`"arena malloc"`, `"arena grow"`, `"intern: out of memory\n"`) gone; and the
corpus claim §7 could not make — no program module in `tests/fixtures/` or
`examples/` defines an `@.str` nothing references — promoted into
`tests/suite-audits.nuc` with no allowlist.

---

## 6. S1 as built

### 6.1 The correction: a watermark, not a swap

**§3's exception does not survive being written as a swap, and the reason is
that `ct-mirror-flush` NESTS inside the very bodies the swap brackets.**
`expand-macro-call` flushes a mirror before every macro expansion, and a macro
body is itself compiled with `emit-node` — so a macro whose body *calls* another
macro that in turn calls a program defn builds a mirror module while the outer
body's table is the live one. "Leave the call alone" then means "emit the CT
body's table", which is exactly the thing §3 says must not happen. A second path
does the same from the other side: `ct-mirror-build-init` runs `emit-node` over
a program global's initializer, so the mirror's own `initir` interns into
whichever table is live while it is built.

Measured, not argued. With the mirror given a compile-time body's watermark —
the swap's behaviour, simulated on a throwaway build — this eight-line program
fails:

```lisp
(import-use io)
(defn s20-msg ():i32 (print "program-side string\n") (return 7))
(defmacro inner () (if (= (s20-msg) 7) `7 `0))
(defmacro outer () (if (= (inner) 7) `1 `0))
(defn main ():i32 (return (outer)))
```

```
nest.nuc:9: compile-time: IR parse error: <compile-time>:601:47:
  error: use of undefined value '@.str.29'
```

The swap cannot be patched into correctness either, because under it the mirror
would need *both* tables and both start at `@.str.0`.

So `g-strs` is never redirected. Each compile-time module path records
`(count g-strs)` as a **watermark** in the same "redirect global state" `let`
the plan named, its body interns into the shared table as before, the module
emits only `[base, end)`, and `strs-truncate-to` drops that tail once the module
is assembled. The program's own ids are unmoved — they are all below `base` —
and every reader of the table keeps seeing the program's ids at all times, so
the nested flush is correct by construction rather than by a restore someone has
to remember. A `die-at` that unwinds past a truncate now leaves the program a
few dead constants instead of leaving it without its table.

### 6.2 The call sites, corrected

`emit-string-table` takes the watermark as a third parameter, `from`.

| site | module | `from` |
|---|---|---|
| `nucleusc.nuc` `emit-compile-time` | a `(compile-time …)` block | `ct-str-base` |
| `nucleusc.nuc` `compile-macro-body` | a macro/CT body (`defmacro`, `macrolet`, `ct-eval-node`) | `macro-str-base` |
| `nucleusc.nuc` `assemble-module-ir` | the program | `0` |
| `nucleusc.nuc` `ct-mirror-emit-module` | the CT mirror | `0` — copied spans name program ids |
| `repl.nuc` `repl-jit-module-rt-rewrite` | a REPL entry's program module | `0` |

**§3's table has four rows and the tree has five call sites.** The fifth is the
REPL's, which the plan does not describe: it assembles the *entry's own program
module*, whose `g-def-buf` names every id the session has interned, so it takes
the whole table. Two swaps, not "three CT module paths" — `assemble-module-ir`
is the site that stops carrying the others' strings and needs no watermark of
its own.

`strs-truncate-to` lives beside `intern-string` in `src/scope.nuc`, and is the
`repl-vec-truncate` idiom: the table is append-only, so dropping the tail is a
true rollback.

### 6.3 The gate

**Self-consistency, byte-identical.** `src/nucleusc.nuc` compiled with
`build/nucleusc`, that IR linked into a stage-2 binary, `src/nucleusc.nuc`
recompiled with it: the two `.ll`s are identical.

**`make test` 1044/0/0** (1043 before S3's unit).

**`make bootstrap` diverges by construction**, as §4 said it would, and the diff
is *only* string-table renumbering — `@.str.10147` against `@.str.6236` and
nothing else. S2 is where it closes.

### 6.4 The measurement, repeated

| subject | before | after |
|---|---|---|
| `(defn main ():i32 0)` — `@.str` constants | 106, all dead | **0** |
| hello-world over `lib/io.nuc` | 215 defined / 186 dead | 30 defined / **1** dead |
| `build/nucleusc.ll` — `@.str` constants | 10,147 | **6,237** |
| `build/nucleusc.ll` — dead constants | 3,911 | **0** |
| `build/nucleusc.ll` — bytes | 13,937,163 | 13,531,960 (−405,203, −2.9%) |
| `build/nucleusc.ll` — lines | 341,714 | 337,939 |

The 2026-09-11 baseline of 92 is now 106 on the same shape of program: the
prelude gained macros between the measurement and the fix, which is the
second-order cost §1 describes, showing up on schedule.

**`src/repl.nuc`'s two `macrolet` tables.** Counting dead constants whose text
is one of the 114 spellings those tables name gives **145 before, 0 after** —
the §1 estimate of 125 was low because several spellings (`set!`, `i32`,
`count`) are minted by other macro bodies too, and all of those are gone as
well. The compiler's live constant count is unchanged at 6,236 → 6,237, the one
addition being `vector-bounds`' `"remove-at"` literal from the new `Vector`
stamp `strs-truncate-to` instantiates.

### 6.5 What is left, and why it is not S1's

Sweeping all 229 programs in `tests/fixtures/` and `examples/` leaves **three**
dead constants in the tree, all library text and all from one remaining source:
`"arena malloc"`, `"arena grow"` (`lib/arena.nuc`) and
`"intern: out of memory\n"` (`lib/intern.nuc`).

They are not a macro-body leak. `emit-import-forms` points `g-def-stream` and
`g-out` at a throwaway `sink` for a compile-time-only import, and the emitter
runs unchanged into it — so the bodies' `@.str` *references* are discarded while
`intern-string` still appends to the table. Same defect, third mechanism, and
not covered by §3.

**It is not a one-line watermark.** `emit-toplevel-forms` runs
`drain-mono-worklist` at the end of *every* depth, and a drain writes to
`g-def-stream-program` — the real program buffer — so a stamp emitted inside the
sink window can legitimately reference a string interned inside it. Truncating
that window would dangle it. Recorded here as the follow-up (`S4`) rather than
taken on the back of S1.

---

## 7. S3 as built

`string-table-per-module` in `tests/suite-audits.nuc`, in that file's own
Nucleus style rather than as a script — the claim needs no text processing a
`check-not-contains` cannot do.

Two halves, because the file's standing rule is that a sweep which swept nothing
passes every assertion it never made:

* A program with no string literal of its own — its own `defmacro`, a `dotimes`,
  a `when`, and the expansion of all three — must emit no `@.str` at all.
* A one-literal control must emit exactly `@.str.0`. Without it the first half
  is equally satisfied by a compiler that emits no string table ever.

**It fails against the old compiler**: the committed `bin/nucleusc` puts **107**
`@.str` constants into that literal-free program.

A corpus walk was considered and rejected. The honest tree-wide form of the
claim is "no program module defines an `@.str` nothing references", and §6.5's
three ct-import residues mean that form needs an allowlist today — a second
thing to keep in step, for a claim the two programs above already pin exactly.
It becomes available once `S4` lands.

---

## 9. S4 as built

`emit-string-table` gained a fourth parameter, `refd`, a nullable `(Vector i32)`
of per-id marks. `assemble-module-ir` builds one and passes it; the other four
call sites pass `null`, which means "the whole `[from, end)` window". The table
is keyed on `(sl 'id)`, so dropping an entry renumbers nothing and the sparse
result is a module LLVM has no opinion about, exactly as §8.2 predicted.

### 9.1 The correction: the deferror table has TWO id vectors, not one

§8.2 names `g-deferror-name-sids` as the set that is "not optional and not in
the buffers". It is half of it. `emit-deferror-table` emits **two** arrays —
`@nuc_err_names` from `g-deferror-name-sids` and `@nuc_err_messages` from
`g-deferror-msg-sids` (`src/nucleusc.nuc:16438`) — and both are written *after*
the string table, so neither vector's ids appear in any scanned buffer. A filter
built to §8.2 as literally written emits a module that references its error
*messages* and defines none of them.

`tests/fixtures/s1-sugar-rets.nuc` is the witness that was already in the tree:
its `@.str.3`/`@.str.5` are the two error names and its `@.str.4`/`@.str.6` the
two messages, and all four are referenced by nothing but those two arrays.

The generalisation is the census rule S1 already met once: **a derived
referenced-set must enumerate every emitter of a reference, and a table built
from parallel id vectors has one emitter per vector.** §8's own table of call
sites was right; the row it was short is inside a single function.

Two smaller things the plan does not mention, both of which the code needs:

* **Index 0 of the deferror vectors is a reserved "no error" placeholder**,
  emitted as `ptr null`. The marking loop starts at 1 — marking slot 0 would
  hold `@.str.0` alive in every program that defines an error, for a reference
  that is never emitted.
* **The trailing blank line stopped being a function of the count.**
  `emit-string-table` closed with `(when (> (count g-strs) from) …)`, which was
  equivalent to "this module emitted at least one constant" only while every id
  in the window was emitted. It is now a latch set by the emit itself. The
  witness is a two-line program, `(import-ct intern)` over a bare `main`: its
  whole table is the sink's residue, and without the latch the module would keep
  a separator with nothing above it.

### 9.2 What the filter covers, and what deliberately still does not

Only `assemble-module-ir` filters. The other two program-shaped modules keep the
whole table, and the reason is the same for both: the scan would not cover the
text they emit.

| site | module | filtered? |
|---|---|---|
| `nucleusc.nuc` `assemble-module-ir` | the program | **yes** — its text is exactly `g-type-stream` + `g-decl-stream` + `g-def-buf` + the deferror table |
| `nucleusc.nuc` `ct-mirror-emit-module` | the CT mirror | no — assembled from four further buffers (`mdecl`, `mdef`, `initir`, plus `emit-qq-helpers`' output) |
| `repl.nuc` `repl-jit-module-rt-rewrite` | a REPL entry's program module | no — the REPL preamble is a second module buffer a `g-def-buf` scan cannot see |
| `nucleusc.nuc` `emit-compile-time` | a `(compile-time …)` block | no — watermark only |
| `nucleusc.nuc` `compile-macro-body` | a macro/CT body | no — watermark only |

Both unfiltered program-shaped modules are JIT-only and never reach a file, so
the residue costs bytes in a module that is parsed once and never written.
Filtering either is a separate question about whether its scan can be made to
cover its own text, not a loose end in this one.

### 9.3 The gate

**§8.4's prediction held exactly.** `build/nucleusc.ll` had zero dead constants
after S1, so the filter is a no-op on the compiler's own module: **`make
bootstrap` byte-identical, `PASS: stage1.ll == stage2.ll`, with no boot
convergence and no committed artifact touched.** The compiler's own table went
6,237 → 6,238 constants, the one addition being `vector-bounds`' `"set"` literal
from the `(Vector i32)` stamp the marks vector instantiates — a live constant,
and the same shape of addition S1's truncate made.

**The tree-wide sweep, with its reach proof.** 392 `.nuc` files in
`tests/fixtures/` and `examples/` compiled with `--emit-llvm`: **229 emitted a
module** (the population §6.5 measured) and 163 refused, which is the count
`context/conventions.md` records for this tree's deliberate refusal fixtures.
Over those 229 modules: **3,494 `@.str` constants defined of which 72 were dead,
against 3,422 defined and 0 dead after** — 72 removed, spread over 41 of the 229
modules. §6.5's "three dead constants" is three distinct *texts*; the population
was 72 instances.

**The live set is provably untouched.** Per-file `defined − dead` is identical
in both sweeps for all 229 modules, and a line-level diff of old-vs-new IR over
the same 229 finds that **every** differing line is a removed
`@.str.N = private unnamed_addr constant …` definition. Nothing was renumbered,
no instruction moved, and no separator drifted.

**Compile-time cost is not measurable.** The scan is one pass over the assembled
module's three buffers, ~13 MB for the compiler's own. `src/nucleusc.nuc` →
`--emit-llvm`, three runs each: 7.75 / 7.83 / 8.08 s before, 7.92 / 7.92 / 8.05 s
after — a ~0.07 s mean delta on an 7.9 s compile, inside the spread of the runs
themselves. An early return when the table is empty keeps a literal-free program
off the walk entirely.

### 9.4 S4's test

`string-table-live-tests-fixtures` and `string-table-live-examples` in
`tests/suite-audits.nuc`, beside S3's `string-table-per-module`, which stays: the
two synthesized programs pin the claim exactly and cheaply, and these two make it
tree-wide **with no allowlist**.

The walk is `w4a-no-line-zero`'s — discover the directory, compile each file,
skip what refuses — and it counts the modules *emitted* rather than the files
seen, because a refusal fixture produces no module and says nothing about this.
Per directory rather than one unit over both, following the file's own
`reader-parity-*` convention: the suite shards by unit, and one combined unit
made its shard the critical path at 101 s where the next was 55 s.

Each module's IR is walked once for `@.str.` tokens: bit 1 marks an id defined at
the head of a line, bit 2 marks it named anywhere else, and a surviving bare
bit 1 is the failure. Line-initial is what makes a definition decidable —
a newline cannot occur inside a constant's own `c"…"` bytes, so a token at the
head of a line is never another constant's content.

**It fails against the pre-S4 compiler**, run over a symlinked tree so nothing in
the repository moved: `tests/fixtures/s1-sugar-rets.nuc: 3 @.str constant(s)
defined and referenced nowhere, first @.str.0`.

`make test` **1046/0/0** (1044 + these two). The two units cost 37 s and 46 s of
serial work; under the suite's 16-way sharding the wall-clock goes **83.8 s →
98.9 s** (+18%), measured A/B against a baseline binary built from a copy of
`tests/` with the two units removed.
