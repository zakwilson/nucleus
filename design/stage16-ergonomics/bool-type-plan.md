# Implementation plan — `bool` as a dedicated type

Executes **Part 1** of [bool-truthiness.md](bool-truthiness.md): the divorce of
`bool` from the integers. Part 2 (nil punning at condition sites) is a separate
item and is **not** in scope here.

## The rulings this plan takes

The design document leaves a handful of details to implementation. Settled here,
once, so the chunks below cannot diverge:

| Question | Ruling | Why |
|---|---|---|
| Kind name | `TY-I1` → **`TY-BOOL`**, `ty-i1` → **`ty-bool`** | Mechanical rename; the kind is no longer named after an integer width |
| `is-int-type` | TY-BOOL **removed** | This is the semantic "is an integer" question — the whole point of the divorce |
| `int-width` / `is-unsigned` | TY-BOOL **kept** (1, unsigned) | These are *representation* queries that drive instruction selection (`zext` vs `sext`, `icmp u*` vs `s*`). Keeping them is what lets `(as i32 b)` and `(unsafe/cast bool n)` reuse the existing widening machinery instead of hand-rolling a second one. Preserves the Stage 15 W9 item 31 fix and its test |
| `int-literal-fits` | the `w <= 1` special case **deleted** | No integer type has width 1 any more; every caller gates on `is-int-type`, so the arm is dead. This is the "removes a rule" the design promises |
| New predicate | `is-bool-type` in `src/type-utils.nuc` | One name for the question, so no site re-spells `(= (t kind) TY-BOOL)` |
| New predicate | `is-int-or-bool` in `src/type-utils.nuc` | The *representation* family: what `unsafe/cast` and the binop operand gate ask. Named separately from `is-int-type` for the same reason `is-ptr-repr` is named separately from `is-ptr-like` |
| Arithmetic on bool | **error** — `+ - * / % bit-*` refuse a bool operand | The point of the item. `(+ true true)` was `false` |
| Comparison on bool | **all six** (`= != < <= > >=`) keep working | Preserves W9 item 31 and its `w9-i1-unsigned` fixture; `false < true` is the only reading under which the two values are ordered at all. Mixing a bool with a non-bool operand is a diagnosed error, not a coercion |
| `(as i32 b)` | legal, `zext` | Design states it explicitly |
| `(as bool n)` | **lossy** — "use unsafe/cast" | Keeps the existing message shape; `unsafe/cast` remains the escape hatch, so `emit-cast` must grow a bool arm or the hatch it names does not exist |
| Implicit coercion | bool ↔ anything: **none** | `coerce-int-val` needs no bool arm; `(let (b:bool 1) …)` becomes `type mismatch`, which is the `{0,1}` rule going away |
| The bool→int widening | one function, `widen-bool-to-int`, beside `coerce-int-val` in `src/abi.nuc` | It has **two** explicit askers — `emit-as` step 5 and `vararg-promote` — and neither may reach it through the implicit chokepoint, or `(let (n:i32 true) …)` would compile. Mirroring the `zext` at both sites is the shape `as-int-narrowing` already exists to prevent |
| `type-spelling` | `"i1"` → `"bool"` | Round-trips: `builtin-type-name` already maps `bool`. Drives diagnostics **and** `--emit-nuch` output |
| `type-mangle-token` | `"i1"` → `"bool"` | The design's one flipped recommendation (§"The one recommendation that flips") — no external consumers, and the token is permanent, user-visible C-header text |
| `type-to-c` | `_Bool` → `bool` | The generated preamble already `#include`s `<stdbool.h>` (verified: every `lib/*.h` line 3) |
| `i1` spelling | **retired**, with a located diagnostic naming `bool` | Not left as a deprecated alias — the point is that the language no longer has a 1-bit integer |
| `zeroext` | **out of scope** | The design ranks it "cheap insurance, not a fire" and it is absent from the Part-1 recommendation. Noted in progress.md as still open |
| `_Bool` in memory as `i8` | **out of scope** | Design: "recommend leaving it" — no observed defect, and it is a codegen change with a bootstrap re-converge behind it |

## Bootstrap staging: one commit, not two

`&rest`→`:rest` needed dual-accept → refresh → retire because the old boot could
not *read* the new spelling. That does not apply here, and the reason is worth
stating because it is the thing most likely to be got wrong:

- **`bool` is already a spelling the committed boot accepts** — `builtin-type-name`
  maps it to `ty-i1` today (`src/union-registry.nuc:258`).
- **`true`/`false` are already literals of that type** (`src/nucleusc.nuc:3241`).
- Under the *old* boot, a `bool`-returning predicate is an `i1`-returning
  predicate, which is exactly what it was.

So the new `src/`+`lib/` sources compile under the old boot **provided they do
not depend on new semantics**. The constraint that falls out, and that every
sweep chunk must respect:

> Every edited site must be valid under **both** the old rules (bool is an
> integer) and the new rules (bool is not). `(!= (pred x) 0)` must become a bare
> `(pred x)` or `(= (pred x) false)` — never something that only the new
> compiler accepts, and never something only the old one accepts.

Standard converge cycle afterwards
(`make clean && make && make update-bootstrap && make clean && make && make bootstrap`).

## Chunks

Each is scoped to fit well under 100K tokens of context and is dispatched one at
a time.

### C1 — core divorce (compiler semantics)

`src/compiler-types.nuc`, `src/type-utils.nuc`, `src/type-mangle.nuc`,
`src/union-registry.nuc`, `src/nucleusc.nuc`, `src/union-emit.nuc`,
`src/generics.nuc`, `src/abi.nuc`, `src/cheader.nuc`, `src/repl.nuc`.

1. Rename `TY-I1` → `TY-BOOL` and `ty-i1` → `ty-bool` everywhere.
2. `is-int-type`: drop the arm. Add `is-bool-type` and `is-int-or-bool`.
3. `int-literal-fits`: delete the `w <= 1` case and its comment.
4. `emit-binop-vals`: bool operands are comparison-only; mixed bool/non-bool is
   a diagnosed error; the integer operand gate becomes `is-int-or-bool`.
5. `emit-as`: bool→int is a safe widening (`zext`); int/float→bool is lossy;
   bool↔float is a reinterpretation.
6. `emit-cast` (`unsafe/cast`): the instruction-selection gates become
   `is-int-or-bool` so bool↔int stays spellable.
7. `type-spelling`, `type-mangle-token`, `type-to-c` token changes.
8. `builtin-type-name`: retire `i1`, diagnose it by name.
9. `vararg-promote` (`src/nucleusc.nuc:6207`) gates on `is-int-type`, so a bool
   vararg would **stop** being promoted to `int` and `(printf "%d" b)` would
   regress — the exact case [varargs-promotion.md](varargs-promotion.md) has just
   fixed, and the one its ten changed-IR examples all were. Gate becomes
   `is-int-or-bool`, widening delegated to `widen-bool-to-int`.
10. Anything the recon turns up that is keyed on the kind and would silently
   change answer (`type-eq`, ABI classification, `sizeof`, REPL result printing,
   the `node-type` arms in `src/generics.nuc` that must stay in lockstep with
   their `emit-node` twins).

11. Sweep `:i1` → `:bool` in `src/*.nuc` and `lib/*.nuc` — **in this chunk**, not
   a later one. Retiring the spelling in step 8 means the new compiler cannot
   compile a source that still spells `i1`, and `src/`+`lib/` *is* the compiler's
   own translation unit. `make` would still pass (the old boot accepts both), and
   the failure would surface one step later as a self-compile error.

**Gate:** `make` succeeds under the committed boot, **and** the freshly built
`build/nucleusc` can compile `src/nucleusc.nuc`.

### C2 — the rest of the tree

`:i1` → `:bool` across `examples/` and `tests/fixtures/`, plus the `(!= … 0)`
call sites the retype invalidates. Regenerate `lib/*.nuch` and `lib/*.h` with
`scripts/check-headers.sh --fix`.

The four `w9-i1-*literal*` fixtures pin the `{0,1}` range rule this item
**deletes** — they and their `run_w9_i1_literal_range` unit are replaced by a
unit pinning the new rule (`(defvar g:bool 1)` is a type error;
`(defvar g:bool true)` is not). `w9-i1-unsigned` survives unchanged in substance.

### C3 — predicate retyping

The design's item 2: the `i32`-returning first-party predicates become
`bool`-returning. `lib/` first (public stdlib surface, and the half that makes
Part 2 possible at all), then `src/`. Callers that consume the result
arithmetically rather than as a condition are converted with an explicit
`(as i32 …)`, never silently.

### C4 — converge and verify

`make`, `make test`, `make bootstrap`, `make check-headers`, `make abi-test`,
`make layout-test`, `make avr-test`, boot refresh.

### C5 — documentation

## What C1 turned up that the plan did not anticipate

**A silent miscompile that only *running* stage 2 could catch.**
`gcheck-special-form` was `(if-some (head …) (contains? …) 0)` — a bool branch
joined with an `i32` literal. The moment bool left the integer family,
`type-join` collapsed that join to **void**, the function fell off the end, and
the compiler emitted `ret i1 0` **with no diagnostic at all**. Every special form
was then reported as an unknown function inside a generic body. `make`,
`make test` and `build/nucleusc --emit-llvm src/nucleusc.nuc` were all clean,
because stage 1 is built by the old boot and so was correct; only building the
stage-2 binary and *running* it surfaced anything.

This is conventions.md's "a wrong value that only reaches a truthiness test is
invisible to every gate" wearing a different hat, and it generalises past this
item: **a non-void function whose return-position `cond` collapses to void emits
the type's zero constant instead of being diagnosed.** That hole is pre-existing
and has nothing to do with `bool` — the divorce merely created a join that
collapses. Left unfixed here deliberately; it is its own item.

**The `emit-cast` gates went total, not selective.** The plan asked for the five
`unsafe/cast` instruction-selection gates to be reasoned one at a time. They
were, and the answer was all five — including int↔ptr, where `ptrtoint ptr … to
i1` is meaningless. The argument that decided it: `as` routes every rejected bool
pair to `unsafe/cast` **by name**, so excluding bool from any gate advertises a
hatch that does not exist. `unsafe/cast i1 p` did the meaningless thing
yesterday too, so this adds no hazard it did not already have.

**`defcast` had to widen its refusal.** It already refused user cast rules for
int↔int pairs because the built-ins cover them. A `bool→i32` rule would be
picked up by `coerce-int-val`'s defcast tail — which is to say a user could
silently reinstate the implicit conversion this item exists to remove. Refused
on the same grounds.

**The breakage a spelling grep cannot find, and it is the general lesson of this
item.** Every chunk hit sites that broke with **no `i1` anywhere in them** — an
expression of bool type flowing into a declared `i32` slot, bridged until now by
the implicit coercion the divorce removes. `src/reader.nuc:394` and five siblings
were the first batch; `examples/comb-storage.nuc:28` —
`(fn (x:i32):i32 (< x 5))`, a lambda declaring an `i32` return over a comparison
body — was the second, and it is in a corpus the `src/`-only measurement never
looked at.

So the `:i1`-annotation count in the work-list below is a **floor, not an
estimate**. The population that actually has to change is "every place a bool
value reaches an integer slot", and the only instrument that finds it is
re-running the compiler over the corpus. `./build/nucleusc --emit-llvm
src/nucleusc.nuc` needs no rebuild between fixes and is the fast loop; the
external Doom port (context/build.md) is the only gate that reaches a corpus this
repo did not write, and it is where the remaining members of this class will be.

**Four functions retyped beyond the annotation sweep**, because each returns a
now-bool expression verbatim: `c-fn-noreturn`, `gcheck-special-form`, and both
`contains?` implementations. The line was held there on purpose — cascading into
`special-form-named` / `primitive-type-named` is C3's job, and one
`(if … (return 1) (return 0))` adapter stops the cascade.

## Measured work-list

Counted against the tree at `136ac49` plus the uncommitted varargs-promotion
work. Two things here were **not** in the evaluation's estimate and are worth
recording before they are fixed, because both are the divorce biting somewhere
the design did not look:

**Six slots already rely on the implicit bool→int coercion this item removes.**
They bind an `i1`-valued expression into an `:i32` slot and are broken by the
divorce independently of any `:i1` annotation or predicate retyping:
`src/reader.nuc:394` (`neg`), `src/repl.nuc:421` (`is-all`),
`src/nucleusc.nuc:3619/3620` (`a-num`/`b-num`), `src/nucleusc.nuc:3768/3769`
(`av-cstr`/`bv-cstr`). Each retypes to `:bool`, and each *use* has to be checked
too — `(!= x 0)` on one of them is valid under the old rules and invalid under
the new, which is the both-rules constraint above biting for real rather than in
principle.

**There are two spelling tables, not one.** `type-to-c` (`src/type-utils.nuc:280`)
is the one the evaluation names; `type-name-to-c` (`src/cheader.nuc:1929`) is a
second, *name*-keyed table carrying its own `"i1"` and `"bool"` rows, under a
comment warning that a missing row "does not fail loudly". A change to one
without the other is silent.

Site counts, for the chunks that have to sweep them:

| Where | Count |
|---|---|
| `:i1` in `src/*.nuc` (locals + one `defn` return, `src/generics.nuc:2521`) | 20 |
| `:i1` in `lib/*.nuc` | 22 across 8 files |
| `:i1` in `lib/*.nuch` (generated) | 22 across 7 files |
| `_Bool` in `lib/*.h` (generated) | 14 across 3 files |
| `:i1` in `examples/` | 15 live + 8 in comments |
| `:i1` in `tests/fixtures/` | 4 files live, plus the 4 `w9-i1-*literal*` fixtures that pin the deleted rule |
| `i1` assertions in `tests/run-tests.sh` | 3 reject-message strings, 4 IR greps, 4 inline heredoc fixtures |
| `i1` in `docs/` | 32 across 7 files |

`tests/expected/` is **clean** — no `.out` file mentions `i1` or `bool`. Every
`i1`-bearing expectation lives in `tests/run-tests.sh` itself.

All 35 `lib/*.nuch` and all `lib/*.h` are generated (`scripts/check-headers.sh`
byte-diffs them, wired into `make test`); the only hand-written `.nuch` in the
tree is `src/llvm.nuch`, which contains no `i1`. `--emit-nuch` prints return
types from the **source node verbatim** (`src/nuch.nuc:38/50/81`), not through
`type-spelling`, so editing the `.nuc` sources is sufficient and the headers
follow.

Two generated headers are a trap of their own: `lib/hashset.nuch:11` and
`lib/vector.nuch:17` export a generic template's **whole body**, so
`contains?`'s `(return 1)` / `result:i32` — an integer returned from an
already-`:i1` function — is mirrored verbatim into committed header text.

`docs/types.md` (delete the `{0,1}` range rule; document `bool` as its own type),
`docs/builtins.md`, `docs/toplevel.md`, `docs/compiler.md`,
`design/progress.md`, and this stage's `overview.md`.
