# Stage 18 — tooling

Two pieces of work on how the compiler is *used* and how it is *checked*, rather
than on what it compiles.

| Piece | Sections | State |
| --- | --- | --- |
| Restoring the REPL introspection layer | §1–§5 | **Done 2026-09-03** (R0–R7) |
| A native test framework | §T1–§T9 | **Decided 2026-09-04** — plan in §T6, rulings in §T8 |

---

# Part one — restoring the REPL introspection layer

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

---

# Part two — a native test framework

**Status: decided 2026-09-04.** The recommendation was accepted and the seven
open questions were ruled on, so this is a plan now. §T1–§T3 are measurements
taken against the tree on 2026-09-03; §T4 asks what typed values buy over text;
§T5 sets out the seven options; §T6 is **the plan**, TF-1 through TF-7; §T8
records the rulings and what each one costs; §T9 is what was deliberately put
off. §T5 is kept as written because it is the argument for §T6, not a menu.

**Step 0 is already done.** `lib/process.nuc` shipped as
[Stage 19](../stage19-process/overview.md) on 2026-09-04, which is why this plan
starts at a runner rather than at a syscall.

**Why this is worth doing.** Not to delete shell for its own sake. 14,337 lines
that work are not, by themselves, a problem worth a stage. Two reasons that are:

1. **It is the dogfooding that finds what the language is missing.** Stage 17
   swept the compiler's C strings into native ones, and the deliverable was never
   the sweep — it was the string library that had to become good enough to
   survive it. A test framework is the same exercise aimed at a different gap:
   process control, the filesystem, text matching. §T3 lists what is absent, and
   the right reading of that list is not *blockers*. It is **the specification
   for the next three library modules**, each of which the language owes its
   users whether or not a single test ever moves. A systems language that cannot
   start a process and wait for it is missing a capability, not a convenience.
2. **A language shipping in 2026 is expected to have a testing story, and "write
   a shell script" is not one.** The compiler's 955 tests are the proving ground,
   not the product. The product is something a person writing a Nucleus program
   can reach for: a way to declare a test, a vocabulary of assertions, discovery,
   a runner that reports. That reframes the target — not an internal harness that
   happens to be written in Nucleus, but a **public, documented facility whose
   first and hardest consumer is the compiler's own suite.**

Line count is therefore a proxy, not the objective. §T1 measures it anyway,
because it is what separates the options that are real from the one that only
looks like progress.

## T1. Ground truth (verified 2026-09-03 against the tree)

The testing surface is ten scripts, 15,268 lines of shell plus 627 of Python:

| Script | Lines | What it is |
| --- | --- | --- |
| `tests/run-tests.sh` | 14,337 | `make test`. The whole suite. |
| `scripts/gen-stdlib-table.py` | 486 | Generator, not a test. |
| `tests/resolution-matrix.sh` | 288 | A *recorder*, not a test: prints a baseline to diff. |
| `tests/run-avr-test.sh` | 159 | Cross-toolchain, gated on `avr-gcc`/`simavr`. |
| `tests/run-riscv-test.sh` | 148 | Cross-toolchain, gated on qemu. |
| `scripts/check-headers.sh` | 143 | Source-tree audit. |
| `scripts/check-cstr.py` | 141 | Source-tree audit. |
| `tests/run-riscv-abi-test.sh` | 132 | Cross-toolchain. |
| `tests/run-abi-test.sh` | 34 | Host C-ABI interop. |
| `tests/run-layout-test.sh` | 27 | Host struct-layout check. |

Only the first is worth attacking. **`run-tests.sh` is 90% of the problem and
every other script is either a generator, an audit, or gated on a toolchain the
runner cannot assume exists.** §T7 argues those 1,558 lines should stay shell
permanently, which makes the addressable target 14,337 — not 15,895.

### T1.1 What `run-tests.sh` is actually made of

It reports **955 tests** (955 PASS, 0 FAIL, 0 SKIP on this host, 2026-09-03).

- 183 function definitions; **10,632 lines live inside them** (74% of the file).
- 347 `spawn` calls across **176 distinct targets**, plus three loops that
  dispatch one unit per file over `examples/*.nuc` (161), `tests/repl/*.in` (16)
  and `tests/fixtures/*.nuc`.
- **172 of the 347 spawns are one-line calls to four declarative drivers**:
  `run_reject_at` (118), `run_reject` (43), `run_accepts` (7), `check_long` (4).
  With the three loops, that is roughly 350 tests — more than a third — driven by
  under 200 lines of shell.
- The remaining ~171 targets are bespoke units, and they hold the other ~10,400
  lines.

The corollary matters more than the totals: **the declarative third is already
cheap, and the expensive part is the part that is genuinely procedural.** A
typical bespoke unit writes two or three source files, emits IR, greps the IR,
links with `clang`, runs the binary, compares stdout, and reads symbol
visibility out of `nm`. That is a program, not a table row.

### T1.2 The assertion vocabulary is narrow

552 `qgrep` call sites — 305 `-F` (fixed string), 76 `-E`, 34 `-xF` (whole-line
exact), the rest bare BRE — plus 171 `[ "$x" = ... ]` equalities, 30 `[ -z ]`,
23 `[ -s ]`, 17 `[ -n ]`, 14 `diff -u`, 7 `cmp -s`. **Six predicates cover
essentially everything:** contains-substring, contains-whole-line,
equals-string, matches-with-wildcards, files-identical, output-empty/non-empty.

The 76 `-E` sites look like the hard case and are not. Only 14 use alternation.
The rest are literal IR text with a wildcard standing in for a
compiler-generated SSA name:

```
'sext i32 %[A-Za-z0-9_.]+ to i64'
'store i32 2, ptr %[a-z0-9]+$'
'call void %t[0-9]+\(ptr sret\(%Big\) align 8 '
'getelementptr inbounds %B, ptr %[A-Za-z0-9._]+, i32 0, i32 2'
```

That is FileCheck's job description, not a regex engine's. A matcher with `*`
(any run of non-newline bytes), `^`/`$` anchors and alternation covers all 76.

### T1.3 Fixtures, tools, and time

- **588 fixtures are written inline** — 292 `<<'EOF'` heredocs and 296
  `printf … >` — against 223 that live on disk in `tests/fixtures/`. 93 of the
  292 heredocs (32%) contain a `"`, which matters for §T8's embed-or-file
  question.
- 168 `mktemp` calls: each unit owns a scratch directory.
- External tools invoked as part of assertions: `clang` 102, `nm` 21,
  `objdump` 6, `python3` 6, `sort` 18, `cmp` 16, `awk` 5. (`sed` appears 469
  times and is almost entirely `sed 's/^/    /'` indenting failure output.)
- 46 `SKIP` sites, all guarding an absent toolchain.
- **59s wall-clock at `NUCLEUS_TEST_JOBS=16`; 317s serial. 5.4×.** Concurrency
  is not a nice-to-have; a serial replacement is a five-minute `make test`.

## T2. What a replacement may not lose

Seven properties, in descending order of how easy they are to lose by accident.

1. **Trustworthiness under a broken compiler.** `run-tests.sh` is interpreted by
   `bash`; a native runner is *compiled by the compiler under test*. When that
   compiler miscompiles, the runner's verdict is worth nothing — and when it
   fails to compile at all, there is no verdict. This is the one property no
   amount of engineering recovers, and it caps how much may move. §T6 answers it
   with a permanent shell trust anchor rather than pretending it away.
2. **Concurrency**, per §T1.3's 5.4×.
3. **Deterministic output.** The current harness buffers each unit's output and
   replays in dispatch order, so a parallel run is byte-identical to a serial
   one. Any replacement must too, or every failure becomes a diff against noise.
4. **Failure output that explains itself.** A `FAIL` prints the expected
   location, the expected message and the actual output, indented. 599 `FAIL`
   sites against 455 `PASS` sites is not asymmetry by accident — the failure
   branch carries the diagnostics.
5. **Per-unit isolation.** 168 scratch directories; units must not see each
   other's files.
6. **Graceful skip.** 46 sites degrade to `SKIP` when a toolchain is missing, so
   a bare container still runs the suite.
7. **The ability to shell out at all.** For the ABI and target tests, `clang`,
   `nm` and `objdump` *are* the assertion. A framework that cannot invoke them
   cannot express those tests at any price.

## T3. What the runtime is missing — which is the other half of the deliverable

Verified by grep across `lib/` (40 modules) and `src/`. Read this as a work list
the language wants anyway, not as an obstacle course between here and a runner:

- **No process API anywhere in `lib/`.** `popen`/`pclose` exist only as raw
  declares in `src/cheader.nuc:15-16`, feeding `read-pipe-output`; `system` is
  called at two sites. There is no `fork`, `execv`, `posix_spawn` or `waitpid`
  in the tree. Everything in §T5 except option E needs it — but the sharper point
  is that **a self-hosted systems language with no way to run a program is
  incomplete on its own terms.** The compiler itself reaches around the gap with
  raw declares; every user program would have to do the same.
  **This is no longer a dependency inside this plan.** It is
  [Stage 19](../stage19-process/overview.md), staged ahead of this part and
  independent of its outcome, because the dependency runs one way: the test
  framework needs process control, process control does not need the test
  framework.
- **No filesystem beyond open/read/write/close.** `lib/file.nuc` exposes 15
  entry points and none of them is `mkdir`, `mkdtemp`, `unlink`, `rmdir` or
  `stat`. Directory enumeration exists exactly once, as raw `opendir`/`readdir`/
  `closedir` declares at `src/nucleusc.nuc:2815-2817`, with a hand-validated
  `DIRENT-D-NAME-OFFSET` of 19 — because the C-header reader registers
  `struct dirent` as opaque.
- **No threads.** Not a problem: bash's own parallelism is process-level, and the
  real work is already in child processes (`nucleusc`, `clang`, the built
  binary). The harness is a scheduler, and `fork`+`waitpid` is the right shape.
- **No regex** — and per §T1.2, none is needed. `strview-find`,
  `strview-contains`, `strview-starts-with`, `strview-ends-with`,
  `strview-lines`, `strview-split`, `strview-trim` and `strview-eq` already
  cover the 475 `-F`/`-xF`/bare sites outright.
- **No s-expression reader outside the compiler.** `Node`/`NodeKind` live in
  `lib/prelude.nuc` and are auto-imported into every program; `lib/node.nuc`
  operates on them. The only text→`Node` parser is `src/reader.nuc`. The
  language hands every program the AST type and no way to build one from text —
  see §T4.6, where this is what blocks the structured-boundary option.
- **No structured diagnostic.** `die-at` renders and exits (§T4.2, 662 call
  sites). Wanted by the REPL and by any future LSP independently of testing.

**One thing got cheaper this stage — and the discount is not total.** Stage 17's
C-macro constant import (`80d0f61`) means `O_*`, `S_*`, `WNOHANG` and friends now
come from the real headers on the host, which was the ugliest part of the cost a
week ago. **Corrected 2026-09-04:** the import admits *object-like* `#define`s
only (`src/cheader.nuc:2787`), so `WIFEXITED`, `WEXITSTATUS`, `WIFSIGNALED` and
`WTERMSIG` do not come across. `lib/process.nuc` needs exactly one piece of
hardcoded platform knowledge after all — the wait-status layout — which
[Stage 19](../stage19-process/overview.md) §2.4 puts behind a typed `ExitStatus`
rather than at every call site. The rest of the discount stands.

**And the list is shorter than a general-purpose runtime would need**, because
the test suite is a demanding but narrow consumer: spawn/wait/capture,
mkdtemp/mkdir/unlink/rmdir/readdir, and a glob matcher. That is the useful
property of picking this as the dogfooding target — it is large enough to put a
new module under real load (955 tests, 5.4× concurrent, 168 scratch directories)
and small enough that the module's shape is decided by evidence rather than by
guessing at what users might want. The stage-17 rule applies unchanged: when the
port hits a weakness, **fix the library, do not work around it in the caller.**

## T4. Typed values versus text — what the assertions are actually about

A shell test can only see text, so every assertion in `run-tests.sh` is a
substring probe against a rendered artifact. A native test could see typed
values. The question is how much of the suite that would actually improve, and
the answer is not uniform: **for some artifacts text is an accident of the
process boundary, and for others text is the contract.** Census of all 843
assertion sites, by what the assertion is *about* rather than by which predicate
it uses:

| Subject | Sites | Share | Is text the contract? |
| --- | ---: | ---: | --- |
| Compiler diagnostics | 250 | 29.7% | **No** — rendered from structure the compiler had and threw away |
| Emitted IR text | 209 | 24.8% | **Yes** — LLVM consumes the text |
| Program stdout / exit status | 138 | 16.4% | **Yes** — the program prints bytes |
| Harness bookkeeping (`$ok`/`$bad`) | 111 | 13.2% | **Not an assertion at all** |
| Generated C header | 90 | 10.7% | **No** — and the compiler can already parse it back |
| Generated `.nuch` interface | 28 | 3.3% | **No** — it is Nucleus source |
| External tool output (`nm`/`objdump`/`file`) | 17 | 2.0% | **Yes** — a foreign tool's text |

### T4.1 The shape of the weakness: 89% of comparisons are substring probes

562 substring probes against 72 whole-value comparisons (21 `diff`/`cmp`, 51
string equalities). A substring probe cannot say *and nothing else*, and it
cannot say *in this function*. Two consequences are measurable rather than
theoretical:

- **63 IR probes are module-scoped.** `qgrep -F 'call i32 @even_QMARK.i32'
  "$d/main.ll"` asserts the call exists *somewhere in the module*. If it is
  emitted in the wrong function the test still passes. Nothing in the suite
  scopes an assertion to a function — the idiom does not exist in the file, and
  the one unit that needed it (`run-tests.sh:486`) hand-rolled an `awk` range.
- **105 negative assertions (`! qgrep`) are vacuous-on-drift.** "This symbol must
  not appear" passes the moment the pattern stops matching for an unrelated
  reason — a mangling change, a spacing change, a renamed helper. A negative
  substring probe over rendered text has no way to distinguish *absent* from
  *spelled differently*, and 105 sites carry that risk today.

### T4.2 Diagnostics: the clearest win, and it needs a compiler change

`die-at` (`src/reader.nuc:33`, **662 call sites**) and `report-at` (`:61`, 26
sites) take a line and a message, render `path:line: error: msg` plus optional
`note:` lines to stderr, and — in the fatal case — `exit 1`. **The compiler has
the structure at the call site and destroys it on the way out.** There is no
diagnostic record type anywhere in `src/`.

The cost of that shows up in the suite's own driver. `run_reject_at`, the single
most-used unit in the file at 118 uses, is:

```sh
err="$(./build/nucleusc --emit-llvm "$fixture" 2>&1 >/dev/null || true)"
if printf '%s' "$err" | qgrep -F "$loc" && printf '%s' "$err" | qgrep -F "$pattern"; then
```

Two independent greps over one blob. **Nothing checks that the location and the
message belong to the same diagnostic** — and this is not a hypothetical, because
notes carry locations too (`note: 'g4-xbase' is declared at …/g4xa.nuc:2`), so a
note supplying the expected location while the error says something else at a
different place satisfies both probes. A `Diagnostic` record with `severity`,
`path`, `line`, `message` and `notes` makes the assertion one field comparison
against one value, and the hole closes by construction.

That record is worth building for reasons that have nothing to do with tests: it
is what the REPL wants instead of catching `repl-throw` after the text has
already been printed, and it is the precondition for ever speaking LSP. **It is a
compiler improvement the test framework happens to force** — the same shape as
the §T3 argument about `lib/process.nuc`.

### T4.3 IR: text is the contract, but the *matcher* should be structured

24.8% of assertions read emitted IR, and the tempting conclusion — assert against
an IR data structure instead — is wrong on inspection. `emit` is a macro
(`src/strfmt.nuc:119`) that formats directly into a `String` buffer and flushes
it to a sink; **there is no IR instruction or module type in the compiler**, and
there should not be one built for the benefit of tests. The artifact under test
is a text file that `clang` consumes. Text is the contract.

But they are not all the same thing. Split the 195 of them made with `qgrep`
(the rest are emptiness and equality checks) by the decision each encodes:

| What the IR probe is really asserting | Sites |
| --- | ---: |
| Signature — ABI class, linkage, mangled name (`^define …`) | 76 |
| Instruction body — a codegen decision | 44 |
| Global linkage / section / alignment | 16 |
| Struct layout (`%T = type <{ … }>`) | 14 |
| Literal contract (`target triple`, `datalayout`) | 7 |
| Other IR text | 38 |

Only the 7 literal-contract probes are asserting about the text *as text*. The
other 202 are asserting about a decision — which register class, which linkage,
which field order — that happens to be observable only in the rendering. For
those, the useful native structure is not an IR AST but **a scoped matcher**: a
`lib/test.nuc` that splits a `.ll` module into its `define` blocks and lets an
assertion name the function it applies to. That is a hundred lines, it retires
the 63 module-scoped probes of §T4.1, and it does not require the compiler to
grow a data structure it has no other use for.

### T4.4 Generated interfaces: parse them back with the compiler's own readers

118 sites (90 C header + 28 `.nuch`) grep text the compiler just wrote —
`qgrep -F '} gt__Pt;' "$d/tylib.h"`, `qgrep -F '(defstruct Pt ' "$d/tylib.nuch"`.
Both artifacts have a parser in this tree already:

- `.nuch` is **Nucleus source**, read by `src/reader.nuc` and consumed by
  `src/nuch.nuc` on import.
- `.h` is C, read by `src/cheader.nuc`'s `c-parse-func-decl` /
  `c-parse-struct-decl` / `c-parse-typedef-decl`.

So the strongest available assertion for an emitted interface is a round trip:
*emit it, read it back with the reader that consumes it, and assert on the
declarations that registered.* That tests the property the artifact actually has
to satisfy — a consumer can parse it and gets the right decls — where the grep
tests only that a byte sequence appears somewhere in the file.

### T4.5 The 111 that are not assertions

`$ok`/`$bad`/`$pass` accumulators: 111 of the 172 string equalities exist purely
because bash has no result type and no exception. Every multi-step unit hand-rolls
`ok=1 … || ok=0 … if [ "$ok" = 1 ]`. Nucleus has `!T`, `try` and `err!` — this
category does not get rewritten, it **disappears**, and with it a class of bug the
shell makes easy and invisible (forgetting one `|| ok=0` makes a step
unconditionally pass).

### T4.6 The gap this exposes: `Node` is public, but nothing outside the compiler can build one from text

`Node` and `NodeKind` are defined in `lib/prelude.nuc` — auto-imported into every
Nucleus program — and `lib/node.nuc` gives 11 list operations over them. But the
only text→`Node` reader in the tree is `src/reader.nuc`, which is compiler
internals. **The language ships the AST type universally and ships no way to
parse one**, so any structured-data-across-the-process-boundary scheme (§T5
option G) and the `.nuch` half of §T4.4 both need a `lib/read.nuc` that does not
exist. It belongs on the §T3 list, and like the others it is a capability the
language wants for its own sake: it is the same module a config reader, a
serializer, or a user's own macro tooling would call.

### T4.7 Verdict

The 843 sites divide three ways, and the split is lopsided enough to be a
finding rather than a summary:

- **368 become typed comparisons** — 250 diagnostics (needs a `Diagnostic`
  record, §T4.2) and 118 generated interfaces (needs no new machinery at all,
  §T4.4). Every one of them is a substring probe today.
- **111 disappear** — the bookkeeping of §T4.5, replaced by `!T` propagation.
- **364 stay text** — 209 IR, 138 program output, 17 external tool. Here the
  upgrade is §T4.3's scoped matcher, not a type.

So a native suite is meaningfully better on 57% of its assertions and no better
on the rest. The distinguishing question is not "could this be typed?" but
**"who consumes this artifact?"** When the consumer is `clang`, a shell, or a
human reading stdout, text is the contract, and the honest gain is a matcher that
can scope and a runner that can propagate — not a type.

## T5. The options

### A. Leave it in shell
**Buys:** nothing new; keeps property T2.1 for free.
**Costs:** the status quo — 14,337 lines nobody wants to edit, a `qgrep` whose
header comment documents a 186-in-200 SIGPIPE race that had to be discovered
empirically, and no dogfooding of the language on its own largest tool.
**Cannot:** deliver either thing this stage is for. The language stays unable to
start a process, and a user asking "how do I test Nucleus code?" is still told to
write bash.
**Verdict:** rejected on the goal, not on the measurement. It remains the
baseline every option's *output* is diffed against (§T6.2) — that is a different
job from being a candidate.

### B. Extract the declarative tests to manifests, keep bash
Move the reject/accept/example/repl tables into data files; keep the shell.
**Costs:** essentially none.
**Buys:** essentially nothing. §T1.1 measured it: those ~350 tests already cost
under 200 lines. Removing them removes ~1.4% of the file and leaves all 10,400
lines of bespoke unit exactly where they are.
**Cannot:** exercise one line of Nucleus. It adds no library, forces no
capability into existence, and ships no facility a user could call. It is a data
re-spelling.
**Verdict:** rejected twice over — on measurement, and on being the one option
that scores zero against both reasons in the preamble. This is the option that
*looks* like progress.

### C. Full native runner
`lib/process.nuc` + `lib/fs.nuc` + `lib/test.nuc` + `tests/runner.nuc`, with all
176 units ported to Nucleus.
**Buys:** both goals in full. Three library modules the language is missing
anyway (§T3), a documented `lib/test.nuc` a user can call, and the whole 14,337
lines become Nucleus — assertions on typed values instead of on the text of
someone else's stdout. It is by a wide margin the largest Nucleus program that is
not the compiler, so it exercises the library the way the stage-17 sweep
exercised strings.
**Costs:** three new lib modules (~600–900 lines), a runner (~400), and a
port of 10,632 lines of body logic — the last being the real number, and it is
not mechanical.
**Cannot:** satisfy T2.1 alone.
**Verdict:** the destination. Its first two-thirds — the modules and the
facility — are worth building even if the port stalls halfway, which is what
makes the staging in §T6 safe rather than merely optimistic.

### D. Declarative s-expression manifest + a small native driver
Tests become data the compiler's own reader parses.
**Buys:** the reader already exists, so the manifest costs nothing to parse, and
it is the same reader the language uses — no second syntax to specify.
**Costs:** the escape hatch. §T1.1's ~171 bespoke units are procedural: write
lib, emit, grep, link, run, read `nm`. Expressing those declaratively means the
manifest grows conditionals, sequencing and variables.
**Verdict:** rejected as a whole-suite strategy — it ends as a second, worse
programming language. Correct *within* option C for the ~350 tests option B
identified, where the data really is a table.

### E. In-process compiler tests
Skip the subprocess entirely: link the compiler as a library, call `emit-*`
directly, assert against the IR string in memory, and reset between tests with
the machinery the REPL already has — `ReplState` (`src/repl.nuc:1686`),
`repl-snapshot` (`:1772`), `repl-restore` (`:1842`).
**Buys:** speed of a different order — no fork, no `clang`, no linking, no
filesystem. And assertions can interrogate the type registry directly instead of
grepping for its shadow in the IR, which is strictly better evidence.
**Costs and cannot:** it does not test the CLI, the driver, linking, or whether
the emitted program *runs*. Worse, the isolation is not a fresh world:
`repl-restore` truncates registries to watermarks and restores ~60 globals, which
is right for rolling back one bad form at a prompt and is **not** proof of
independence across 955 tests. A test that mutates a global outside the
watermark set silently contaminates every test after it, and the failure
presents as order-dependent flakiness — the worst bug class a test suite can
have.
It also scores worst on the stage's own terms: it is the one option that reaches
its speed by **routing around** the capabilities §T3 says the language needs. No
process API is exercised because no process is started.
**Verdict:** a genuinely attractive *separate track* for the emit-and-inspect
units, viable only once something else can cross-check it. Not a replacement, and
not a first step.

### F. Staged hybrid — replace the harness, keep the bodies
A native runner owns dispatch, the job pool, scratch directories, output
buffering, ordered replay and the summary. Each unit body stays a shell snippet,
invoked through one `sh -c`. Bodies then migrate to Nucleus by category,
independently.
**Buys:** needs only process-spawn and wait — not the filesystem surface, not the
matcher — so it lands on the smallest possible slice of §T3, and it lands on the
part the language most needs. `lib/process.nuc` exists on day one and is
immediately carrying 955 units at 16-way concurrency, which is a far harder test
of a process API than any unit test written for it would be. Every subsequent
migration is then incremental and separately verifiable.
**Costs:** the shell doesn't shrink until phase two; for a while there are two
things to understand instead of one.
**Verdict:** the first step option C needs — and, on its own, the step that
delivers the most missing capability per line written.

### G. Structured output across the process boundary
The subprocess boundary is what flattens everything to text, so move structure
*across* it rather than giving it up: the compiler gains a machine-readable
diagnostic mode emitting one s-expression per diagnostic, the runner reads it
back with `lib/read.nuc` into `Node`s (§T4.6), and assertions compare fields.
Generated `.nuch` and `.h` get the same treatment for free via §T4.4's round
trip.
**Buys:** §T4.7's 368 typed comparisons — 44% of all assertions — while keeping
every property of §T2: still a subprocess, still isolated, still concurrent,
still able to report on a compiler that crashed. It is option E's evidence
quality without option E's isolation hazard.
**Costs:** a `Diagnostic` record and an emitter in the compiler; `lib/read.nuc`;
and a second output format to keep working, which is a real maintenance surface
rather than a free win.
**Cannot:** help the 364 sites where text is the contract (§T4.3).
**Verdict:** not a standalone option — it is the assertion-quality half of C,
and the reason C is worth more than "the same tests, in Nucleus". Its two
prerequisites are both capabilities the language wants anyway, which is the
pattern this whole stage keeps running into.

## T6. The plan

**F → C with G folded in, E as a separate track, and a permanent shell trust
anchor.** Step 0 — `lib/process.nuc` — is [Stage 19](../stage19-process/overview.md),
done 2026-09-04.

### T6.0 Shape

The runner is **its own binary** (§T8.1), and it is generic: it knows how to run
*units*, not how to test a compiler. A unit is a name plus a command plus a
scratch directory. That single abstraction covers both halves of the migration —
a shell body invoked as `sh -c`, and a native test invoked as
`<suite> --run <name>` — so the runner does not change when the bodies do.

```
build/nuctest  ──spawns──▶  tests/run-tests.sh --unit <name>     (shell, retiring)
               ──spawns──▶  build/nuctests --run <name>          (native, growing)
```

Each unit is **one process**, which is what makes per-unit isolation (§T2.5) and
order independence (§T8.6) properties of the architecture rather than promises.
The suite binary reports each unit's result as an s-expression on stdout
(§T8.5), which the runner reads with `lib/read.nuc` — the same reader that will
read the compiler's structured diagnostics in TF-5.

### T6.1 TF-1 — make the shell suite addressable

`tests/run-tests.sh` gains `--list` and `--unit <name>`: the harness (dispatch,
job pool, buffering, replay) separates from the 176 unit functions, and any one
unit runs alone. Pure shell work, and the enabler for everything after it.

*Gate:* every listed unit run alone, concatenated in dispatch order, is
**byte-identical** to today's full run.

That gate is worth more than it looks. Running each unit in a fresh process *is*
the order-independence audit of the existing suite: a unit that only passes after
some other unit has run will fail here, and §T8.6 makes that a bug rather than a
curiosity. Expect this phase to find some.

#### As built (2026-09-04)

`spawn` is the only dispatch point in the file, so the whole of `--list` and
`--unit` lives inside it and **no unit function changed**. The count is 525
spawned units, not the 176 named functions §T6 estimated: the three per-file
loops (`examples/*.nuc`, `tests/fixtures/*.nuc`, and the reject tables) spawn one
unit per file, and those are what a runner has to address.

Three deltas from the sketch:

1. **Names are `function:first-argument`, not function-plus-all-arguments.** The
   first argument is already each unit's identity — `run_example <src>`,
   `run_fixture <src>`, `run_reject <name> <fixture> <pattern>`. Later arguments
   are *expected diagnostic text*, so joining them in produced names like
   `run_reject_at:g2-array-nested:…:(array T N) is a storage type` — 100+ bytes
   of error message, parens and spaces, in a token that has to survive a command
   line. First-argument-only yields 525 unique names, longest 49 bytes, none
   containing whitespace or a shell metacharacter. `spawn` rejects a duplicate
   name outright rather than leaving a driver to discover an unaddressable unit.

2. **`--unit` does not build.** The `make -s` at the top of the file exists to
   stop 161 parallel jobs relinking `build/nucleusc` while others execute it; 525
   concurrent `--unit` invocations would reintroduce exactly that race. The
   runner builds once, before dispatch. This is the one thing a human invoking
   `--unit` by hand has to know, so the usage comment says it.

3. **`--unit` backgrounds the unit and waits, rather than calling it.** A unit
   that dies mid-way has to leave the same partial output it would leave in the
   pool. Calling it in the current shell under `|| true` would disable `set -e`
   for the whole function body, so a unit that would have aborted would instead
   run on — different output, and the gate would not have caught it because
   nothing currently aborts.

*Gate: passed.* All 525 units run alone, concatenated in dispatch order, are
byte-identical to the full parallel run — 959 `PASS`, 0 `FAIL`. The only
differing line is `make`'s build banner, which `--unit` deliberately does not
emit.

**The order-independence audit found nothing.** Every unit passes in a fresh
process. This contradicts the expectation two paragraphs up, and the reason is
the invariant the harness header already claimed: each unit owns its own
`mktemp` space. That claim now has a test behind it, which is the part that was
missing — and TF-2's `--shuffle` inherits a suite already known to be clean, so
a future shuffle failure is a real regression rather than pre-existing debt.

### T6.2 TF-2 — `build/nuctest`, the runner

A bounded job pool over Stage 19's `spawn` and `wait-any`; a scratch directory
per unit, owned by the runner rather than by each body; captured stdout and
stderr per unit; replay in dispatch order; the summary. Flags: `--jobs N`,
`--filter <pat>`, `--shuffle <seed>`, `--list`.

Units come from a manifest naming each unit and its command. For now every
command is `tests/run-tests.sh --unit <name>`.

*Gates:* output byte-identical to `run-tests.sh`'s full run; the suite still
passes under `--shuffle` with three different seeds; wall-clock within 10% of the
shell harness's 59s at `--jobs 16`.

### T6.3 TF-3 — `lib/read.nuc`

An s-expression reader over `StrView` producing `Node`, in `lib/`. The language
already hands every program `Node` and `NodeKind` through `lib/prelude.nuc` and
ships no way to build one from text (§T4.6); `src/reader.nuc` is compiler
internals and stays there.

Needed by TF-4 (the result protocol) and TF-5 (diagnostics), and owed to the
language independently of both — it is the module a config reader, a serializer,
or a user's own macro tooling would call.

*Gate:* round-trips every `.nuc` file in `tests/fixtures/` against
`src/reader.nuc`'s parse of the same file, compared structurally.

### T6.4 TF-4 — `lib/test.nuc`, `deftest`, and the suite protocol

- **`deftest`** (§T8.2) registers a named test into a table the suite walks,
  capturing its source file and line so a failure can point at itself.
- **Assertions**: the six predicates of §T1.2 — contains-substring,
  contains-whole-line, equals-string, matches-with-wildcards, files-identical,
  output-empty/non-empty — plus §T4.3's scoped IR matcher, which splits a `.ll`
  module into its `define` blocks so an assertion can name the function it
  applies to. Glob, not regex (§T8.4).
- **Failure propagation is `!T`**, which is what deletes §T4.5's 111 `$ok`/`$bad`
  accumulators rather than translating them.
- **Failure rendering lives here**, so §T2.4 is one implementation instead of
  599.
- **The suite binary** supports `--list` and `--run <name>` and emits one
  s-expression result record per unit.

*Completion condition, not a nicety:* this phase is done when `lib/test.nuc` is
documented in `docs/` **and** an `examples/` program declares and runs its own
tests without touching the compiler's harness. A module only the compiler suite
can use is a private harness with a public name.

### T6.5 TF-5 — structured diagnostics from `nucleusc` (option G)

A `Diagnostic` record behind `die-at` and `report-at` (662 and 26 call sites), a
`--diagnostics=sexp` output mode, and the runner reading it back with
`lib/read.nuc`. Assertions then compare fields.

**Before TF-6, not after.** TF-6's first and largest category is the 172
reject/accept spawns, and those are precisely the §T4.2 diagnostic assertions.
Migrating them first would bake 250 substring probes into the native suite and
pay to port them a second time. It also closes `run_reject_at`'s hole: today two
independent greps over one blob never check that the location and the message
came from the same diagnostic, and `note:` lines carry locations.

Wanted by the REPL and by any future LSP regardless of testing.

### T6.6 TF-6 — migrate the bodies, retiring each category as it lands

In descending order of reuse:

| # | Category | Units | Notes |
| --- | --- | ---: | --- |
| a | `run_reject_at` / `run_reject` / `run_accepts` / `check_long` | 172 | A table, driven by TF-5's structured diagnostics. This is where option D's manifest is right. |
| b | `examples/*.nuc` and `tests/repl/*.in` loops | 177 | Golden-output comparison; mechanical. |
| c | Bespoke units, largest first | ~171 | The seven largest are over 200 lines each. |

**Retirement is per category, not at the end** (§T8.7). A category's shell units
are deleted once its native counterparts have returned identical verdicts on
three consecutive green full runs, one of them shuffled. Until then `make test`
runs both — which is the point of dual-running: after TF-6 begins, the two are
different implementations and their agreement is evidence.

Every weakness the port hits is a library defect to fix, not a body to contort
around it — the rule that made Stage 17 produce a string library rather than a
pile of workarounds, and Stage 19 produce three conventions entries.

### T6.7 TF-7 — the end state

`make test` runs the trust anchor and then `build/nuctest`. The shell that
remains is §T7's 1,558 lines, which the framework *invokes* rather than replaces
— including `check-headers.sh` and `check-cstr.py`, which are units of the suite
today and stay units of it.

### T6.8 TF-E — the in-process track, separate

Option E, after TF-2 and only while TF-6's versions still exist to cross-check
against. Convert only the pure emit-and-inspect-IR units. The order matters:
E's contamination hazard — `repl-restore` truncates registries to watermarks
rather than rebuilding the world — is invisible without a second implementation
to disagree with it.

### T6.9 Permanent — the trust anchor

A short shell script that compiles one program, runs it, and diffs the output,
run *before* the native runner. It is the answer to §T2.1: when the compiler is
broken badly enough that the native runner will not build, something that does
not depend on the compiler has already said so. Ruling §T8.1 makes this sharper,
not softer — a separate runner binary is one more thing the broken compiler has
to build before it can report anything.

Keeping it is not a hedge; it is the reason the rest is allowed to move.

## T7. What stays outside the framework regardless

1,558 lines of shell and Python, for reasons that are not inertia. **Outside the
framework means not rewritten, not unrun** — `check-headers.sh` and
`check-cstr.py` are units of the suite today and stay units of it, spawned by the
runner like any other command (§T2.7):

- **The trust anchor** (§T6.9) — by construction.
- **`run-avr-test.sh`, `run-riscv-test.sh`, `run-riscv-abi-test.sh`,
  `run-abi-test.sh`, `run-layout-test.sh`** — they gate on external toolchains,
  run outside `make test`, and their assertion *is* an external tool's output.
  Rewriting them buys a different spelling of the same `spawn`.
- **`resolution-matrix.sh`** — its own header says it is a recorder, not a test.
- **`check-headers.sh`, `check-cstr.py`, `gen-stdlib-table.py`** — source-tree
  audits and a generator. Not tests, and not this stage's problem.

## T8. Decisions (ruled 2026-09-04)

Seven questions, seven rulings, each with what it buys and what it costs.

### T8.1 The runner is its own binary

`build/nuctest`, not a `nucleusc --test` mode.

**Buys:** the compiler's surface stays clean, and the §T2.1 dependency becomes
visible instead of implicit — a separate binary that the compiler under test must
build is a thing you can *see* failing to build. It also keeps the runner
generic: it runs units, and nothing in it knows what a compiler is.

**Costs:** a user with a `tests/` directory has to have `nuctest` on hand, so it
ships alongside `nucleusc` and `make install` grows a line. And it is one more
artifact between a broken compiler and a verdict, which is precisely what §T6.9's
trust anchor exists to cover.

### T8.2 Tests are declared with a `deftest` macro

Not a name convention over plain `defn`.

**Buys:** the registration table, and with it `--list`, `--filter` and
`--shuffle` for free; and the test's own source file and line, captured at the
macro, so a failure points at itself without the assertion having to be told
where it is.

**Costs:** language surface — one more macro in `lib/`, and a name that is now
spoken for.

### T8.3 Fixtures may be embedded or on disk, and the rule is written down

Both, chosen per fixture rather than by policy. The rule:

| Put it on disk when | Embed it when |
| --- | --- |
| it contains a `"` | it is short and single-use |
| more than one test uses it | it reads better beside its assertion |
| it is more than ~20 lines | — |

The `"` clause is the live one: 93 of the 292 heredocs in `run-tests.sh` contain
a quote, and escaped Nucleus inside a Nucleus string literal is unreadable. That
is a language gap, not a fixture policy — §T9.1.

### T8.4 `matches` is a glob

`*`, `?`, `^`/`$` anchors and alternation. §T1.2 measured that this covers all 76
`qgrep -E` sites, only 14 of which use alternation at all; the rest are literal
IR text with a wildcard standing in for a compiler-generated SSA name.

**Costs:** a pattern that genuinely needs a regex has no home. §T9.2 keeps that
door open, and §T4.3's function scoping is the larger win anyway and is
independent of this choice.

### T8.5 Structured data crosses process boundaries as s-expressions

Both uses: the suite's per-unit result records, and `nucleusc`'s
`--diagnostics=sexp`.

**Buys:** no new format to specify, and `lib/read.nuc` (TF-3) reads both — a
module the language owes its users regardless (§T4.6). The reader is the
language's own, so the data is legible to every Nucleus program without a parser.

**Costs:** tools that are not this compiler cannot read it without one. §T9.3.

**The sharper half of this, unchanged from the question:** the `Diagnostic`
record *replaces* `die-at`'s rendering rather than sitting beside it — one
formatter, two back-ends. Two renderers for one diagnostic is how the text and
the structure drift apart.

### T8.6 Order independence is a requirement

Not a hope. Every unit runs in its own process (§T6.0), the runner takes
`--shuffle <seed>`, and a shuffled run is part of the gate at TF-2 and at every
category's retirement in TF-6.

**Costs:** units that share expensive setup cannot amortise it, and TF-1 will
find existing units that quietly depend on order. Both are worth paying: the
failure mode order-dependence produces is intermittent, and intermittent is the
worst thing a test suite can be. §T9.4 leaves room for explicit dependencies if a
real case turns up — *explicit*, declared and enforced, never incidental.

### T8.7 `make test` runs both until the native runner is stable

Then the redundant shell is retired and `make test` is the trust anchor plus
`build/nuctest`.

"Stable" is per category, not global: a category's shell units are deleted once
its native counterparts have returned identical verdicts on three consecutive
green full runs, one of them shuffled (§T6.6).

**Costs:** the dual-run period roughly doubles the 59s. That is the price of the
cross-check, and it is only real during TF-6 — before then the two runs are the
same tests twice, and after each category retires the shell side shrinks.

---

## T9. Deferred

Written down so they are choices rather than omissions.

**T9.1 A raw string literal.** §T8.3 sends any fixture containing a `"` to disk
because escaping Nucleus inside Nucleus is unreadable — 93 of 292 heredocs. A raw
or heredoc-style literal would make that a preference instead of a rule. This is
a language feature with users beyond testing (embedded JSON, shell snippets,
generated C), so it belongs in its own stage.

**T9.2 A richer matcher.** Regex, or something structural over IR. §T8.4 says
glob covers every site measured today; the note is that "today" is doing work in
that sentence. Revisit when a real pattern cannot be expressed, not before.

**T9.3 Other structured formats.** JSON, EDN, or anything else the suite protocol
and `--diagnostics` might also speak. The decision to defer is cheap to reverse
because §T8.5 puts one renderer behind the `Diagnostic` record: a second back-end
is a back-end, not a redesign.

**T9.4 Explicit test dependencies.** §T8.6 rules out *incidental* ordering, not
declared ordering. If a genuine case appears — a fixture that costs minutes to
build and is read by twenty tests — the answer is a declared dependency the
runner can schedule and verify, not a silent reliance on dispatch order.

**T9.5 A worker-pool protocol.** TF-2 spawns one process per unit, which is 955
`fork`+`exec` pairs for the compiler's suite. If that shows up in the wall-clock
gate, the fix is to spawn one suite process per worker and feed it test names.
Deferred because it trades isolation for speed, and §T8.6 just made isolation a
requirement.

**T9.6 A `nucleusc --test` convenience mode.** §T8.1 chose a separate binary and
that is the architecture; a mode that shells out to `nuctest` could still be
added later as a convenience. It would be a wrapper, not a second
implementation.
