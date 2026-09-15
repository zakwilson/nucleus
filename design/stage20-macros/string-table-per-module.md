# The string-literal table, one per module

**Status: S1, S2 and S3 done; S4 open.** Phases `S1`–`S4`. Promoted out of
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

**S4 — the compile-time-only import's sink.** *Open, found by S1's sweep.* The
last three dead constants in the tree come from `emit-import-forms`' throwaway
`sink`, not from a CT module; §6.5 has the mechanism and why a watermark there
is not the same one-liner. *Gate:* the corpus claim §7 could not make yet — no
program module defines an `@.str` nothing references — promoted into
`tests/suite-audits.nuc` with no allowlist.

**Documentation:** [stage888-deferred.md](../stage888-deferred.md)'s entry
becomes a pointer here; [overview.md](overview.md) and
[progress.md](../progress.md) gain the phase.

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
