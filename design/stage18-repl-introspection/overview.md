# Stage 18 — restoring the REPL introspection layer

**Goal.** Make the REPL meta-forms table in
[docs/compiler.md](../../docs/compiler.md#repl-meta-forms) true. All sixteen
documented forms — `defined?`, `kind-of`, `type-of`, `dir`, `doc`, `apropos`,
`complete`, `imports`, `casts`, `expansion-of`, `last-error`, `time`, `locate`,
`forget`/`reset!`, `trace`/`untrace` — are implemented, tested and reachable from
a `nucleusc -i` session and from `docs/emacs.md`'s keybindings.

This is not a new feature. It is a **restoration**, and the stage exists because
of how it went missing.

---

## 1. Ground truth (verified 2026-09-03 against the tree)

### 1.1 What happened

The introspection layer was built on **2026-05-08** in `f97bb47` "Add
introspection functions for the REPL" — 542 lines into `src/repl.nuc`, 72 into
`src/nucleusc.nuc`, 11 into `lib/reader.nuc`, and the documentation that still
describes it. `ad34838` (2026-05-10) improved the signatures and docstrings. The
code is present in the tree at `c5d973d` (2026-05-28) and **absent** at
`f909024` "Add multimethods, generics, protocols" (2026-06-07).

**No commit removes it.** `git log -S kind-of -- src/repl.nuc` reports only the
two additions; the history around 2026-05-28 → 2026-06-08 carries replayed
duplicates of the same commits (`f97bb47`/`45746cf`, `854eb68`/`7bfb63d`,
`4ac7488`/`c5d973d`), and the line that reached `HEAD` is the one that never had
the 542 lines. The work was dropped by a rebase, not deleted by a decision.

Three consequences, all of which held for fifteen months:

- **The docs never noticed.** They were written against a working
  implementation and outlived it. `docs/compiler.md` §REPL meta forms,
  `docs/builtins.md`, `docs/toplevel.md` and `docs/emacs.md` — which binds
  `C-c C-t` to `type-of` and `C-c C-d` to `kind-of`+`type-of`+`locate` — all
  describe forms that error with *"unknown: type-of — not defined anywhere in
  this compilation unit"*.
- **The struct fields survived.** `Sym.docstring`, `Sym.trace-tracker`,
  `Sym.trace-saved`, `Sym.src-file`/`src-line`, `MacroDef.docstring`,
  `MacroDef.param-names` are all still declared. `docstring` and `trace-saved`
  have **zero readers**, which Stage 17 C8 found and flagged without knowing why.
- **No gate could see it.** The IR snapshot compares emitted output, `make test`
  never exercised a meta form, and the bootstrap only cares that the compiler
  compiles itself. A feature can vanish from a self-hosted compiler without
  moving a single byte of its output.

**The lasting fix is the last point, and it is a gate, not code** (§5.3): a
documented REPL form with no test is a form that can disappear silently. The
stage adds one test per form.

### 1.2 What survives, and what has to be rebuilt

| Piece | Status today | Work |
|---|---|---|
| `@<name>.tgt` thunk indirection | **Survives** — `emit-fn-thunk`, `jit-thunk-module`, `update-fn-tgt`, `rewrite-first-fname` all in `src/repl.nuc` | none |
| `emit-fn-trace-shim`, `jit-trace-module` | **Gone** | port from `c5d973d` |
| `repl-error`, the JSON error path | **Survives** | hook `last-error` into it |
| `macroexpand` / `-1` / `-all` dispatch | **Survives** (`src/repl.nuc:517`) — the only meta forms the REPL still answers | extend the chain |
| Registries (`g-macros`, `g-rmacros`, `g-structs`, `g-cast-rules`, `g-globals`, `g-imported`) | **Survive**, now `Vector`s reached with `count`/`invoke` | rewrite the walks |
| `find-macro`, `lookup-struct`, `scope-lookup`, `macroexpand-all-form`, `fprint-node`, `open-module-streams`, `reset-function-state`, `emit-node` | **Survive** | none |
| `repl-type-to-nuc` | **Gone**, but `type-spelling` (`src/type-mangle.nuc:107`) now covers every non-`TY-FN` kind | thin wrapper: `TY-FN` renders a signature, everything else delegates |
| `Sym.src-file` / `src-line` | Declared, **never written** for a `defn`/`defvar`/`defconst` | populate at registration |
| `MacroDef.src-file` / `src-line` | **Written** (`src/nucleusc.nuc:15036`, `15286`) | none |
| `StructDef.src-file` / `src-line` | **Written** (cheader, union-registry) | none |
| `Type` parameter names | **Gone.** `Type.param-names` became `(params (raw (Vector (ref Field))))` and `Field.name` is left null — its comment records the removal as "dead storage… the REPL renders positional `pN`" | §2.1 |
| `MacroDef.param-names` | Declared `ptr`, **never written** | §2.1 |
| `Sym.docstring`, `MacroDef.docstring` | Declared, **never written**, and nothing captures a leading body string | §2.2 |
| `g-last-error-msg` / `-line` | **Gone** | re-add |

The `Type.param-names` row is the one that bites: `Field.name` was emptied
*because* the introspection layer that read it was already gone, and its comment
cites the REPL's positional fallback as justification. Restoring the reader is
what makes the field load-bearing again.

---

## 2. Decisions

### 2.1 Parameter names are captured, not faked

`docs/compiler.md` promises that `type-of` on a `defn` prints "the full
signature `(fn ret name0:t0 name1:t1 …)` **with the original parameter names**",
with positional `pN` as the fallback "for function-pointer types and other
sources that don't preserve names". Rendering `pN` everywhere would satisfy the
letter of the fallback and none of the promise.

So `emit-defn` populates `Field.name` for each parameter as it builds the
`TY-FN`, and `defmacro` populates `MacroDef.param-names`. Both are captured at
the one site that has the source spelling in hand. `pN` stays the honest fallback
for a function-pointer type, a `declare`d extern, and a C header import — sources
that genuinely never had names.

**This is the only change in the stage that touches non-REPL code paths**, so it
is phase R2 on its own and gated by the IR snapshot: populating a name field must
not move a byte of emitted output.

### 2.2 Docstrings are captured from the body, per the documented rule

`docs/toplevel.md` says a `defn`/`defmacro` whose body's first form is a string
literal has that string as its docstring — **including** the guard that a body
whose *only* form is a string literal returns that string instead. The rule was
already stated exactly right; nothing implemented it. `doc` and `apropos` are
the readers, so the capture lands with them (phase R4).

The literal is **left in the body**, not stripped. It is already an inert first
statement, and removing it would move emitted IR for every `defn` in the tree
that has one — a snapshot diff bought for nothing, since the docstring only has
to be *recorded*.

### 2.3 `type-of` discards its IR, and that stays a deliberate leak

The reference routes `type-of` through `emit-node` against a scratch scope, then
closes and frees the module streams without handing them to LLVM — the type is
the only thing wanted, and committing the IR would define symbols the session did
not ask for. That is right and is preserved. What changed underneath is that the
streams are `String`s now, not `open_memstream` `FILE*`s (Stage 17 C3), so the
teardown is a `drop`, not four `fclose`/`free` pairs.

The saved/restored `g-qq-used` in the reference is a real hazard and is kept:
`emit-node` on a quasiquoting form sets it, and leaving it set makes the *next*
real module emit quasiquote helpers it does not use.

### 2.4 `forget` renames rather than deletes, and the REPL already has a better tool

The reference implements `forget` by setting the registry entry's name to `""`
so lookups miss it. That was the only option in May. The REPL has had
`repl-snapshot`/`repl-restore` since — `ReplState` records `n-structs`,
`n-macros`, `n-cast-rules` and truncates on error recovery.

`forget` still renames, and deliberately: rollback truncates to a **count**, so
it can only undo the most recent definitions, while `forget` names an arbitrary
one. But the rename now writes `symbol-none` rather than `""` — `Sym.name` is a
`Symbol` (Stage 17 C7-4a) and `symbol-none?` is the "no name" test the type
already has, so a forgotten entry is recognisably absent rather than
accidentally matching another empty string.

### 2.5 `trace` keeps its documented caveat

Redefining a traced function silently disables tracing: the redef path overwrites
`@<name>.tgt` with the new impl directly. The reference documented this rather
than fixing it, `docs/compiler.md` documents it today, and this stage does not
change it — the fix is a redef-path check that belongs with a redefinition
change, not a restoration.

---

## 3. Phases

**R0 — the dispatcher and the forms that need no new data.** `repl-handle-builtin`
returning 0/1, hooked into `repl-eval-form` beside the surviving `macroexpand`
chain; `repl-meta-sym-arg`; `repl-type-to-nuc` over `type-spelling`;
`repl-classify`. Forms: `defined?`, `kind-of`, `type-of`, `imports`, `casts`,
`expansion-of`. Every one reads data the tree already has.

**R1 — the name walk.** `repl-walk-names` over the four registries, and
`repl-visit-name`'s three modes. Forms: `dir`, `complete`. Signature rendering
uses positional `pN` until R2 lands, which is the documented fallback, so R1 is
correct on its own.

**R2 — parameter-name capture.** `Field.name` from `emit-defn`,
`MacroDef.param-names` from `defmacro`. §2.1. **IR-snapshot gated**: no emitted
byte may move.

**R3 — `Sym.src-file`/`src-line` and `locate`.** Populate at global registration;
`locate` searches syms, macros, structs in that order.

**R4 — docstrings, `doc` and `apropos`.** §2.2's capture rule, then the two
readers, then `repl-print-docstring`.

**R5 — session state: `last-error` and `time`.** `g-last-error-msg`/`-line` set
from `repl-error`; `time` stays a branch inside `repl-eval-form` rather than in
`repl-handle-builtin`, because it recurses into the evaluator and same-function
recursion sidesteps the forward-declaration problem.

**R6 — `forget`/`reset!` and `trace`/`untrace`.** The registry rename (§2.4),
then `emit-fn-trace-shim` + `jit-trace-module` ported forward onto the surviving
thunk machinery.

**R7 — tests, docs, close-out.** §5.3's per-form test, the `docs/emacs.md`
keybindings verified end to end, and the two dead fields either alive or gone.

---

## 3.1 As built (done 2026-09-03)

All sixteen forms restored, all phases landed, all gates green: **951 tests**
(949 + the two new units), IR snapshot **byte-identical across 2,624 artifacts at
every phase**, `make bootstrap` converged.

Five things came out differently from the plan above.

**`kind-of` and `defined?` accept a string, and the original did not.** The docs
list `rmacro` as an answer, and a reader macro is keyed by its *prefix* — `'`
cannot be written bare, because the reader consumes it. The 2026-05 code carried
a comment saying "use the literal prefix string with `kind-of`" beside a
`repl-meta-sym-arg` that rejected everything but `NODE-SYM`, so the documented
answer was unreachable in the implementation that documented it. Both spellings
are accepted now, and `docs/compiler.md`/`docs/builtins.md` say so.

**The trace shim is ABI-lowered; the original's was not.** `emit-fn-trace-shim`
printed one `type-to-ir` per parameter. That is the exact defect the surviving
`emit-fn-thunk`'s comment records having fixed for the thunk — an aggregate
parameter gets the wrong lowering and names a `%Struct` the module never defined.
The port builds its parameter list through `abi-print-param-to`, the way the
thunk does, and `(trace f)` on a struct-taking function works.

**`Sym.trace-saved` was retyped back to `ptr`.** Stage 14 had made it a `StrView`
with a comment claiming it saved `ir-name` — a description of a field with no
readers. It holds the impl address `untrace` restores.

**The docstring literal is recorded, not stripped** (§2.2), and `docs/toplevel.md`
turned out to state the capture rule — single-string guard included — exactly
right already.

**`doc` had no table row** in `docs/compiler.md` or `docs/builtins.md`, only
prose references from `defn`'s docstring rule. It has one now. `docs/emacs.md`'s
`M-.` row said `(locate 'sym)` while its own prose four paragraphs later said a
quoted argument is rejected; the prose was right.

---

## 4. What this deletes

- The four-file documentation lie.
- `Sym.docstring` and `Sym.trace-saved` as dead storage — both gain readers.
- The `Field.name`-is-dead-storage comment in `src/compiler-types.nuc`, which
  documents a conclusion drawn from the absence this stage reverses.

---

## 5. Gates

### 5.1 Emitted-output identity
`./scripts/stage17/ir-snapshot.sh verify` byte-identical across all 2,624
artifacts, at every phase. The REPL is not on the batch-compilation path, so R0,
R1 and R3–R6 must not move a byte. **R2 is the phase to watch**: it writes a
field during type construction, and the snapshot is what proves the field is
inert to emission.

### 5.2 Bootstrap fixed point
`make bootstrap` converges. R2 changes what `emit-defn` stores, so a
`make update-bootstrap` cycle may be needed there and nowhere else.

### 5.3 One test per documented form — the gate that was missing
`tests/run-tests.sh` gains a REPL-driven unit per meta form, each feeding a
session on stdin and asserting on the output. This is the gate whose absence let
the layer vanish in the first place, so it is the stage's most important
deliverable after the code: sixteen forms, sixteen assertions, and a form that
regresses fails the suite instead of waiting fifteen months for someone to type
it at a prompt.

### 5.4 The editor path
`docs/emacs.md`'s `C-c C-t` (`type-of`) and `C-c C-d`
(`kind-of` + `type-of` + `locate`) exercised against a live session, since those
three forms have a consumer that composes them.
