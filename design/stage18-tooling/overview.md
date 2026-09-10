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

#### As built (2026-09-04)

`tests/nuctest.nuc`, ~300 lines, built by `make nuctest` to `build/nuctest`.
Flags are as specified: `--jobs N`, `--filter <glob>`, `--shuffle <seed>`,
`--list`.

**All three gates pass**, at 525 units:

| Gate | Result |
| --- | --- |
| Byte-identical replay | 970 lines, identical to the shell harness's full run |
| Three shuffled seeds | 1, 7, 12345 — all 525 pass, *and* all byte-identical |
| Wall-clock at `--jobs 16` | 63.8s vs the shell harness's 62.0s — **+3.0%** |

Five things the sketch did not say:

1. **Unit results go to stdout, the runner's summary to stderr.** A summary line
   on stdout would have made the byte-identity gate unmeetable by construction,
   and the split is the honest one anyway: the replay is the suite's output, the
   summary is the runner talking about itself.

2. **Shuffling permutes *dispatch*; replay is always in manifest order.** The
   gate only asked that a shuffled run pass, but replaying canonically costs
   nothing and upgrades it: a shuffled run is byte-identical to an unshuffled
   one, so a seed that breaks the suite produces a *diff*, not just a red exit
   code. `--list` honours `--shuffle` so the order is inspectable — otherwise a
   shuffle is unobservable and a no-op shuffle would pass its own gate. (Checked:
   0, 0 and 2 fixed points across the three seeds.)

3. **The unit list is generated, not stored.** `nuctest` runs
   `tests/run-tests.sh --list` and turns each line into a unit. A checked-in
   manifest would be a second place for a unit to exist and a third state to get
   wrong; `--list` is the interface, and TF-6 keeps it as bodies move.

4. **`lib/process.nuc` needed a new capability, and pipes were the wrong
   primitive.** A pipe holds 64 KiB, so a pool of children capturing through
   pipes deadlocks: a child that fills its pipe never exits, and a parent in
   `wait-any` is draining nobody. Added `command-stdout-path` and
   `command-stderr-to-stdout`; see stage19-process/overview.md §9. This is the
   dogfooding the stage was justified on, arriving on schedule.

5. **The `--unit` shim cost 27% until a `basename` fork was removed.** First
   measurement was +37%, and cutting the walk short after the matching unit
   (nothing later can change its verdict) only reached +27%. Profiling the
   walk found the real cause: the top-level dispatch loops called
   `$(basename …)` once per example and per REPL fixture — ~180 forks, 335ms,
   on *every* invocation, which a 525-unit driver pays 525 times. Parameter
   expansion instead: 335ms → 43ms, and the gate went from +27% to **+3.0%**.
   The shell harness got the same speedup for free, so the baseline moved too.

That last one is the phase's real lesson. The 10% target looked like it was
about the runner, and the runner was never the problem: the shim was, and the
shim was slow for a reason that had nothing to do with which language it was
written in. **A shell harness pays a fork where a program pays a function call,
and at 525 units that difference is the entire budget.**

`make test` is unchanged and still runs the shell harness. At this phase both
run the identical 525 units, so running both would double the wall clock for no
extra coverage — §T8.7's dual-run ruling is about native *tests* against shell
*tests*, which starts at TF-6. `make nuctest` runs the new one.

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

#### As built (2026-09-04)

`lib/read.nuc`, 792 lines. `read-all` for whole text, a `Reader`/`read-one`
pair for one form at a time (and for the error line, which the `!` channel
cannot carry), `node-write`/`node-str` for the canonical text, `node-eq` for
structural equality. Documented in `docs/reading.md`, with
`examples/read-sexp.nuc` as the worked example.

**The gate needed an instrument, so the compiler gained `--dump-ast`**: the
reader's output, before `desugar` and before the prelude is prepended, one
top-level form per line. There was no other way to see what `src/reader.nuc`
produced — it is compiler internals and stays there (14 compiler globals,
including the reader-macro table and three REPL/diagnostic ones). `readdump`
(`tests/readdump.nuc`) prints `lib/read.nuc`'s answer in the same format, so
parity is a `diff`.

**Result — 429 files, zero disagreements:**

| Corpus | Identical | Rejected | Compiler can't parse |
| --- | --- | --- | --- |
| `tests/fixtures/` | 220 | 0 | 6 (the reader-error fixtures) |
| `examples/` | 156 | 7 | 0 |
| `lib/` | 42 | 0 | 0 |
| `src/` | 12 | 3 | 0 |

Pinned as four `run_reader_parity` units, so this is a standing gate rather than
a one-time measurement.

##### The scope deviation, stated

The gate as written implies full parity, and full parity is not achievable:
`def-rmacro` extends the *compiler's* reader-macro table at compile time, so no
library reader can agree with it on source that uses one. Given that, the line
was drawn at what a **data** reader owes its callers. Excluded:

- **Collection literals** `[…]`, `{…}`, `#{…}` — the desugaring infers an
  element *type* from the elements (`lit-elem-kind`, `lit-type-node`). That is
  type inference living in a reader; it belongs to the compiler. ~140 lines not
  duplicated.
- **User reader macros** — compiler state, as above. The six built-ins (`'`,
  `` ` ``, `~`, `~@`, `@`, `&`) are implemented, because they are part of the
  written language rather than a per-compilation registration.

Everything else is implemented rather than waved off, including the two pieces
of Nucleus surface sugar a data reader has no use for — `&T` → `ref:T`, and the
`name:(Type)` colon-paren fuse with its `(fn ret)(params)` second group. They
are ~110 lines and they are what takes the corpus from 175 files to 429: without
them, 44 fixtures would parse into a *silently different* tree. That is the
distinction that decided the line — **a construct that would be silently
mis-parsed must be implemented; one that can be positively rejected may be
excluded.** The ten excluded files fail with `read-collection-literal` and a
line number, and `run_reader_parity` fails if a rejection ever has another
cause, so the exclusion cannot quietly grow.

##### Three bugs in the compiler's printer, found by the gate

`fprint-node` is what `--emit-nuch` writes macro bodies with. Every difference
the parity sweep reported turned out to be the *compiler* losing information,
not the new reader:

1. **`println` and `eprintln` were exported without their newline.** A
   `NODE-CHAR` fell through to the default case and printed *nothing*, so
   `lib/io.nuch` carried `(str-into b parts )` where the source has
   `(str-into b parts \newline)`. Any multi-TU build importing the header got a
   `println` that behaved as `print`. Fixed by printing `\u{…}`; the IR snapshot
   re-take below is exactly this.
2. **`c"…"` printed as `"…"`.** NS-4's CStr flag lives in `NODE-STR.i` and the
   printer ignored it, so the literal read back as a different one.
3. **Non-ASCII string literals were mojibake.** The default byte case did
   `(emit out (as Char (as ui32 c)))`, widening each *byte* to a codepoint and
   re-encoding it as UTF-8: `"hé"` printed back as `"hÃ©"`. Fixed by emitting a
   one-byte `StrView`.

None was reachable from any committed header, which is why 85 generated headers
had been green over three of these bugs. A second implementation found all three
in an afternoon — the argument §T2 makes for a native suite, arriving one phase
before the suite exists.

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

#### TF-4 as landed (2026-09-04)

`lib/test.nuc` (376 lines), `docs/testing.md`, and `examples/self-test.nuc` with
`tests/expected/self-test.out` — a suite whose last test fails on purpose, so the
recorded output is the failure record's own regression test. The completion
condition is met: the example imports `test` and nothing from `src/`.

Shipped: `deftest`; the eleven `check-*` predicates (the six of §T1.2, plus
`check-eq-int`, the two negations, and `check` as the escape hatch); §T4.3's
`ir-define` / `check-in-define` / `check-not-in-define`; `fail!` for writing new
assertions; `test-main` answering `--list` / `--run <name>` / all; and one
s-expression record per test on stdout, with the message escaped so it reads back.

Two compiler changes the phase turned out to require, both general rather than
test-specific:

1. **`(source-file)` / `(source-line)`.** A `deftest` must record where it is
   written, and a macro cannot ask. Both resolve at the *call* site inside an
   expansion, which is the property that makes them useful and is also what a
   diagnostic macro will want in TF-5. Emitted as a literal — a `StrView` and an
   integer — so they cost nothing.
2. **Macro calls in top-level position.** `deftest` is a macro that must stand
   where `defvar` stands, and the dispatch loop had no macro path at all: the
   head was matched against the built-in forms and anything else died with
   `unknown top-level form`. Expansion is now attempted **only in that default
   arm**, so a built-in form still wins its own name and no existing program can
   change meaning; a `(do …)` expansion splices, and the rewritten cell is
   re-dispatched rather than advanced past, so an expansion may itself be a macro
   call. `toplevel-expand-macro` in `src/nucleusc.nuc`.

The known limit of (2) is that expansion happens in the dispatch loop, *after*
the pre-scans have walked the file: a macro-produced definition is not in the
signature registry, so it is not forward-referenceable, and a macro cannot
produce an `extend` together with the methods that satisfy it. Fixing that means
a macro-expansion pass ahead of the pre-scans, which in turn means `defmacro`
bodies (and the imports they need) are JIT-compiled before any other top-level
form is processed — a front-end restructuring, not a patch. Documented in
`docs/macros.md`; deferred as T9.7.

One trap worth the line: `str-into` re-evaluates its target once per piece
(`lib/fmt.nuc` says so), and `test-fail-begin` *clears* the buffer, so the
obvious `(str-into (test-fail-begin) ~@parts)` kept only the last piece. `fail!`
binds the buffer first. Every assertion in the module went through that macro, so
the bug was invisible until a test actually failed — which is why
`examples/self-test.nuc` has one that always does.

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

#### TF-5 as landed (2026-09-05)

`Diagnostic` (`src/reader.nuc`) — `severity`, `path`, `line`, `message`, `notes`
— built once by `diag-emit` and rendered by whichever back-end `--diagnostics`
selected. `die-at` and `report-at` construct one; so do the five **located**
warnings, which had each been spelling `path ":" line ": warning: "` by hand.

**The split is where the structure comes from, and it cost no call sites.**
Twenty-odd diagnosing sites already build their notes into the message as
`(fstr "…" "\n  note: " …)`, and two more (`g-mono-context`,
`g-diag-note`) are ambient. `diag-build` splits on that exact marker, so `notes`
is a real field without any of the 688 call sites changing. The text back-end
rejoins — which makes it the identity, and the gate for that is not a new test
but the 172 existing reject units, every one of which asserts its exact
diagnostic text. All 965 stayed green on the first run.

Two things the phase had to decide:

- **A note printed *after* the call is not a field.** Three sites did that
  (`report-unterminated`, the stray-`)` note, the preprocessor's sysroot
  advice), because `die-at` is noreturn and there is no "and also". They now
  stage the note first; `diag-stage-note` **appends** rather than overwriting,
  which is what lets two sites contribute to one diagnostic.
- **One diagnostic is one line**, because every newline inside a string is
  escaped. That is what lets `read-diagnostics` skip a line that is not a
  diagnostic — and it has to skip, because the `clang -E` a C-header import
  shells out to writes its own text to the same stream. A location-less
  toolchain message spells the absence as `(file "")` and `(line -1)` rather
  than omitting the fields, so a reader never asks whether a key is present.

The test side is `read-diagnostics` + `check-error-at` / `check-warning-at` /
`check-note-at` / `check-no-errors` in `lib/test.nuc`, over `lib/read.nuc`.
`examples/self-test.nuc` gained a `diagnostics` test that reads a blob
containing an error at `a.nuc:12`, a line of tool output, and a warning at
`b.nuc:3` — and asserts the pairing that §T4.2 says two greps cannot: the same
blob satisfies "an error at a.nuc:12" and "a message containing `second ns`"
separately, and `check-error-at` rejects the pair. `run_diagnostics_sexp` is the
compiler-side gate: the exact form for an error, a note as a field, one line per
diagnostic, a warning structured too, a `"` in a field surviving a `readdump`
round trip, and `--diagnostics=text` being the default.

Not converted: `cheader-preprocess-failed` re-runs `clang -E` with stderr
attached so the user sees clang's own "file not found". That is another
program's diagnostic, not this compiler's, and wrapping it would claim a
structure it does not have.

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

#### TF-6 category (a) as landed (2026-09-05)

`tests/manifest/diagnostics.sexp` (168 rows) and `tests/nuctests.nuc`, which
reads it and registers one test per row. The 168 `run_reject_at` / `run_reject`
/ `run_accepts` units are gone from `tests/run-tests.sh` — 826 lines — and the
three helpers with them.

**The table is the point, not the port.** Every one of those units said the
same thing about a different fixture, so the shell version was repeated control
flow and the native version is a `while` loop over `tests/manifest`. A row is

```lisp
(reject NAME (file F) [(line N)] (message M)... [(note M)...])
(accept NAME (file F))
```

and with a `(line …)` present, `(message …)` and `(note …)` are matched against
**one** `Diagnostic` record rather than grepped independently out of one stderr
blob.

**Three rows were wrong, and the record found all three** — §T4.2's hole
closing in practice. `w9-unknown-type-ctor-unimported` and `g5-noinit-ref-note`
asserted text that lives on a **note**; `w5a-hex-escape-no-digit-rejected` had
the `path:line: error: ` prefix baked into its pattern, which stopped being
part of the message the moment the message became a field. All three are now
strictly more precise than the units they replaced.

**Retirement followed §T6.6's rule**: three consecutive green runs of the
native table, one of them a full `--run`-per-name shuffle, then delete.
`make test` runs both suites — 798 shell + 168 native = the same 966 verdicts
as before, no unit lost. The suite's stdout stays a pure record stream; the
human summary is made in the Makefile rather than by polluting it.

The 62 rationale comments that introduced **only** retired units moved into the
manifest verbatim as `;` blocks. The rest introduce surviving units and stayed;
six that referred to the retired helpers by name were reworded.

Two library changes the phase required, both general. `TestCase` gained a
`data:raw` and its `run` takes a `ptr`, which is what lets a table row and a
`deftest` be the same kind of test — a `deftest` ignores both. And
`check-note-anywhere`, so an unpinned `(note …)` cannot silently assert
nothing.

**One crash worth recording:** `row-text` guarded with
`(= (n 'kind) NODE-CELL)` rather than by kind, and `Node.s` is null on an INT,
so reading a row's `(line N)` segfaulted. `diag-text` in `lib/test.nuc` had the
identical shape and was fixed with it.

`check_long`'s four units are counted in this category's 172 by §T6.6's table
but are a target-triple ABI probe with IR greps, not a diagnostic assertion.
They stay in the shell suite and belong to category (c).

#### TF-6 category (b) as landed (2026-09-05)

The `examples/*.nuc` and `tests/repl/*.in` golden-output loops now live in
`tests/nuctests.nuc`: 155 example tests and 16 REPL tests, discovered by walking
the directory rather than listed. That is deliberate — a table would have made
"add an example" a two-file edit, and the shell glob did not.

**Three library gaps the port hit, all fixed in the library** (§T3 named the
first two as missing surface):

- **`read-dir` / `dir-count` / `dir-name` / `make-dir` / `dir-exists?`
  (`lib/file.nuc`).** `DirEntries` is one buffer of NUL-terminated names plus
  their offsets — `Command`'s shape, for `Command`'s reason: `Vector`'s drop
  frees its array without dropping elements, so a `(Vector String)` leaks every
  name. Entries come back **sorted**, because `readdir` order differs between
  machines and a test corpus walked twice must register the same order. The
  `d_name` offset is validated rather than trusted: `.` and `..` exist in every
  POSIX directory, so their absence means the offset is wrong on this platform
  and `read-dir` fails instead of returning bytes read out of `d_ino`.
- **`command-stdin-path` (`lib/process.nuc`).** A REPL test *is* a file piped
  into `nucleusc -i`; there was no `< file`.
- **`command-stderr-to-stdout` now applies under capture.** It had been honoured
  only on the file-redirect path, silently doing nothing when `capture` was on.
  A golden file records `2>&1` — one stream, one interleaving — and two
  separately drained pipes cannot reproduce one. The child now dups the stdout
  pipe onto fd 2 and the parent closes the unused err pipe.

**One compiler crash, fixed at the root.** `(return (err e))` in a function
returning `!void` segfaulted the compiler:

```lisp
(defn f (e:Err):!void (return (err e)))
```

`union-target-rewrite` sent every plain `err` at an `!T` site through
`__err-handled`, and `emit-err-handled` dereferences the `ok` payload type to
build the `(Maybe T)` a handler repairs with. `!void`'s `ok` arm has no payload,
so that type is null. The negotiation is meaningless there — there is no value
for a handler to supply — so `err` in a `!void` is now `err!`, and
`emit-err-handled` keeps a guard that says so rather than dereferencing null.
`(err! E)` and `try` were always fine; only the plain `err` spelling reached it.

**One deduplication.** `src/nucleusc.nuc` had its own `opendir`/`readdir`/
`closedir` declares and its own `DIRENT-D-NAME-OFFSET`; it now calls
`lib/file.nuc`'s `read-dir`, which it reaches transitively already. The offset
and its platform caveat exist once. `scan-dir-for-definer` inherits sorted
order, which changed exactly one diagnostic in the whole corpus:
`w9-unknown-type-ctor-unimported` now names `lib/vector.nuc` where it named
`lib/vector.nuch`. That is the better answer — `.nuc` out-ranks `.nuch` in
`resolve-import`, so the note names the file the author would actually import —
and it was previously decided by filesystem order, which is to say not decided.

**`check-golden`** (`lib/test.nuc`) reports the first differing line and its
number. `check-eq` would have shown two truncated blobs; a golden file is long
enough that "they differ" is not an answer.

**Retirement**: three green runs, one a full `--run`-per-name shuffle, then the
two loops and their two helpers were deleted. `make test` is 627 shell + 339
native = the same 966 verdicts. The native suite is self-sufficient — it makes
`build/out` itself rather than depending on a shell script having run first.

`run_repl_meta_loose` stays: it is the three meta forms a golden diff cannot
hold, which makes it a bespoke unit and category (c)'s problem.

#### TF-6 category (c), first batch (2026-09-05)

Category (c) is 182 shell functions and 10,560 body lines, so it lands in
batches with the support layer built first.

**The layer.** Most bespoke units embed a program, compile it, and grep the
result — `run_s16_bool_type` alone has a local `refuses_bool` that
reimplements `run_reject`. So `tests/nuctests.nuc` gained `compile-source` /
`compile-path` (returning a `Compiled` record: `ok?`, `ir`, `raw`, `diags`),
`check-source-rejects`, `check-source-accepts`, `source-ir`, `source-cheader`,
`build-run-source` and `check-source-exit`; `lib/test.nuc` gained per-test
scratch files (`test-scratch`, `test-write-file`) under
`build/out/nt/<test-name>`, so `--run` reproduces exactly what the full run
wrote and no two tests collide. Category (a) was rerouted through
`compile-path`, deleting its own `compile-fixture`.

**Embedded fixtures read, because a string literal may span lines.** That was
not obvious and is what makes ruling 3 (§T8.3) practical: an embedded program
is a heredoc, not a wall of `\n`. Only `"` and `\` need escaping.

**First batch, 5 shell functions → 20 tests** in `tests/suite-s16.nuc` (a
separate module `tests/nuctests.nuc` imports, so the suite file does not become
one enormous file): `run_s16_bool_type` (6), `run_s16_macrolet_refused` (10),
`run_s16_atom_macro` (2), `run_s16_template_repr` and
`run_s16_pointer_kind_names`. Every name is the one the shell unit printed, so
nothing in the corpus is renamed. `make test` is 607 shell + 359 native = 966.

**Remaining: 170 shell functions, 10,339 body lines** (counting every
`run_*()` in the file, §T7's trust-anchor units included). The `run_s16_*`
family is the largest cluster, and it is the one this layer was shaped by.

#### TF-6 category (c), second batch (2026-09-05)

**5 shell functions → 35 tests**, 792 shell lines retired:
`run_s16_bool_truthiness` (5), `run_s16_literal_variables` (13),
`run_s16_vararg_promotion` (4), `run_s16_type_aliases` (9),
`run_s16_chain_nesting` (4). `make test` is 572 shell + 394 native = 966 —
unchanged, as it must be.

**Four more helpers, each demanded by a unit rather than anticipated.** The
first batch's units were all single-file; these are not.

| Helper | The unit that needed it |
| --- | --- |
| `compile-path-in dir path` | `deftype-` privacy: a namespaced library and a consumer *outside* it. |
| `emit-for-file dir flag path` | `--emit-nuch`, whose output is the artifact under test. |
| `build-run-file dir path` | the `.nuch` round-trip: build a second unit against the exported header. |
| `repl-session text` | `deftype` in the REPL, which has its own top-level form chain. |
| `line-with hay needle` | a claim about ONE instruction — `i8 %` is in every module, so a module-wide search cannot make it. |

`compile-path` and `build-run-source` are now one-liners over the `dir`-taking
versions, and an empty `dir` adds no `-I`.

**Two shell comparisons became stronger assertions, not weaker ones.**

- The shell compared IR and C-header *files* after `grep -v`-ing out
  `; ModuleID`, `source_filename` and the `/* Generated from` banner, because
  the two programs lived at different paths. `compile-source` writes every
  fixture to the same `t.nuc`, so those lines are already equal and
  `check-golden` compares the whole artifact — banner included.
- `refuses_chain` grepped stderr for the message and again for `c.nuc:4:`.
  `check-error-at` requires both of the same diagnostic, which is category (a)'s
  upgrade applied to a bespoke unit.

**Remaining: 165 shell functions, 9,583 body lines**, of which the `run_s16_*`
family is 27 functions and 3,057 lines.

#### TF-6 category (c), third batch (2026-09-05)

**4 shell functions → 21 tests**, 679 shell lines retired:
`run_s16_parametric_aliases` (7), `run_s16_d9_ct_types` (7),
`run_s16_ref_sigil` (6), `run_s16_decl_attrs` (1). `make test` is 551 shell +
415 native = 966.

Three more helpers, again each demanded by a unit: `compile-object` (a real
object-file link, not a reparse — the parametric alias has to survive one),
`test-scratch-sub` in `lib/test.nuc`, and the `extra` argument on
`build-run-file` that carries `--link-arg=`. Plus `count-lines-with-prefix` and
`duplicate-type-name`, because D9's claim is that a type line is emitted
**once**: a presence test cannot catch the double emit a re-drain produces, and
LLVM rejects the module rather than picking one.

**`run_s16_decl_attrs` stays one test, and gets better for it.** It was one
shell unit with five internal checks, accumulated into `bad=1` and reported at
the end — the hand-rolled `ok=1 … || ok=0` accumulator §T4 named as the reason
the `!void` shape exists. As a `deftest` the first failure ends the test and
says which of the five it was.

**The oracle cluster is deferred, and now named.** `run_s16_fl_float_widths`,
`run_s16_pk_packed`, `run_s16_pk3_aligned`, `run_s16_bf_bitfields`,
`run_s16_an_anonymous`, `run_s16_c1_bare_unsigned` and `run_l5_typedef_names`
assert Nucleus's layout *against clang's*, and two of them generate their
fixtures and compare their results in embedded Python. They need two things the
framework does not have: a way to run the host C compiler, and a way to record
a SKIP — `command -v clang` is a real precondition, not a formality. That is a
design decision, not a port, and it belongs beside §T9's deferred list.

**Remaining: 161 shell functions, 8,936 body lines**, of which `run_s16_*` is
23 functions and 2,410 lines.

#### TF-6 category (c), fourth batch (2026-09-05)

**4 shell functions → 30 tests**, 492 shell lines retired: `run_b4_redefinition`
(14), `run_s16_import_ct` (9), `run_s16_keyword_markers` (4),
`run_s16_macrolet` (3). `make test` is 521 shell + 445 native = 966.

**A second suite module, `tests/suite-modules.nuc`**, for what a *unit
boundary* does to a name — R4 redefinition now, the `run_w9_nuch_*` and
namespace family next. `tests/suite-s16.nuc` was getting long, and the split
that matters is by subject rather than by batch.

One helper: `check-file-exit dir path want`, with `check-source-exit` becoming
a wrapper on it. That is the shell's `w1_run`, which several surviving units
still use.

**Ten near-identical units became ten `deftest`s over one helper, not a
table.** Category (a)'s rule is that a *fixture* corpus is data; here each
program is three lines written in the test, and the ten differ in the definer
being redefined — which is the thing a reader is looking for. What they share is
the assertion, `check-redefines`, and that is where the upgrade lives: the shell
grepped stderr for `redefinition of 'X'` and separately for `<file>:2: error:`,
where `check-error-at` requires both of the *same* diagnostic.

**Remaining: 157 shell functions, 8,444 body lines**, of which `run_s16_*` is
20 functions and 2,050 lines.

#### TF-6 category (c), fifth batch (2026-09-05)

**5 shell functions → 30 tests**, 593 shell lines retired:
`run_w9_layout_reachability` (6), `run_w9_defcast_reach` (6),
`run_w9_two_ns_one_name` (6), `run_b5_private_definers` (6),
`run_w9_fnslot_arg` (6). All five are unit-boundary units, so all five went to
`tests/suite-modules.nuc`. `make test` is 491 shell + 475 native = 966.

**The measurement that should drive the rest of the plan.** Counting body lines
with a heredoc-aware scanner (the naive `^}` scan stops early on any unit that
embeds C, which is most of the deferred ones), what is left is:

| | functions | body lines |
| --- | --- | --- |
| Oracle-free | 101 | 3,982 |
| Needs `clang`/`cc`/`python3` | 51 | 4,617 |

**Half the remaining work looked blocked on one missing capability** — running
the host C compiler, and recording a SKIP when it is absent.

**That was overstated, and the correction is worth more than the claim.** clang
is already a *hard dependency* of this project: `src/nucleusc.nuc:18681` uses it
as the default linker driver, and the `Makefile` links the compiler with it at
four sites. "Is clang present" is therefore not a conditional any test needs to
express — if it is absent, nothing built. What is genuinely conditional is
narrower: whether a particular clang's target has `_Float16`/`__float128`. The
corrected split of the 152 remaining functions is 101 oracle-free / 3,982 lines,
41 clang-bound but unblocked / 4,142 lines, and **one** unit with a real
oracle — `run_s16_fl_float_widths`, 206 lines of embedded Python, staged
separately in [float-width-oracle.md](float-width-oracle.md).

Four helpers this batch, all in `tests/nuctests.nuc`: `check-file-rejects`
(with `check-source-rejects` becoming a wrapper), `source-compiles?` — a table
of accept/reject spellings asks only that, and neither `check-source-rejects`
nor `check-source-accepts` can carry the two halves of one row — and
`check-same-decl-set` with `count-exact-lines`, because the "moving the import
did not move emission" claim compares two modules as a SET: position within the
type section is order-dependent and inert, and the string pool renumbers, so
the artifacts themselves cannot be compared.

**Two shell greps became field assertions.** `w9-defcast-note-names-rule`
grepped stderr for `note: a defcast rule converts …`; `check-note-anywhere`
makes "it is a note" a field rather than a prefix in the text. And
`w9-two-ns-ambiguous-use` grepped for the message and separately for
`w35amb.nuc:3: error:`, where `check-error-at` requires both of one diagnostic.

**Remaining: 152 shell functions, 8,599 body lines** by the corrected count —
101 oracle-free functions / 3,982 lines of it portable today.

#### Skip as a third verdict (2026-09-05)

A test whose *subject* is not present to be tested is not a pass, and the shell
suite has been printing `PASS  name (SKIP: reason)` — a line that reconciles
into the PASS count and disappears from every summary that matters. `lib/test.nuc`
now has three verdicts.

- `(skip! parts…)` ends the test as skipped, with a **required** reason,
  rendered by the same `str-into` machine as `fail!`. A skip nobody can read is
  attrition nobody can audit; that is the whole argument for requiring it.
- The record is `(status skip) (message "…")` — a field, not a prefix inside a
  pass message, so `lib/read.nuc` reads it back and a collector counts it.
- `--no-skip` turns every skip into a failure, message `skipped: <reason>`. It
  is a **policy flag, not a mode**, so it composes with `--list` and `--run`;
  `make run-nuctests NUCTESTS_ARGS=--no-skip` is the release-check spelling.
- `make test` prints every skip line and ends `N passed, M failed, K skipped`.

`test-run-one` returns the status rather than a bool, and `test-main` counts
only `TEST-FAIL` toward its exit code — so a default run exits 0 with skips in
it, and a `--no-skip` run does not. `examples/self-test.nuc` gained
`this-one-skips-on-purpose` beside the deliberate failure, so the golden output
shows both records.

One implementation note that cost a debugging pass: the skip reason lives in the
failure buffer, and `test-fail-begin` clears it, so the strict-mode conversion
must **copy the reason out before** it begins writing the replacement message.
`str-into` re-evaluates its target once per piece, which makes the aliasing
easy to write and invisible until the message comes out empty.

#### TF-6 category (c), the float-width oracle (2026-09-06)

**1 shell function → 6 tests**, 206 shell lines retired: the whole of
`run_s16_fl_float_widths`, into a third suite module `tests/suite-float.nuc`.
`make test` is 485 shell + 481 native = 966. The fifth batch's "one unit with a
real oracle" row is now zero, and what remains is 100% mechanical port.

This was the unit staged separately in
[float-width-oracle.md](float-width-oracle.md), because its port was a
**rewrite of two Python programs** — a fixture generator and an IR-constant
comparator — rather than a translation of shell text-munging. That document now
carries the measurement, the one work item the port raises, and how each of the
three staged gaps actually resolved. In short: the float arithmetic came out
smaller than Python, as predicted; the *line parsing* came out 20× larger,
which was not; and the only library change proposed is a pair of byte-level
ASCII classifiers beside `strview-is-ascii-ws`, which is left for review rather
than smuggled in.

Two helpers, both in `tests/nuctests.nuc`: `cc-emit-llvm` — clang's own IR for
a C file, the oracle half of any unit that compares the two compilers — and
`compile-path-for`, `compile-path` under `--target=`. They are separate from
`compile-path-in` on purpose: a `-I` search path is about this project's
sources and a triple is about the machine they are emitted for, and no unit
wants both.

**Two assertions got stronger.** FL-5 was five `[^,]*` wildcards in a `grep -E`;
it is now an exact comparison of the vararg call's type sequence. And the ABI
unit's six `sed -E` substitutions became one normaliser shared with FL-5, so
`%struct.S1` and `%S1` are the same claim in one place rather than in two
pipelines that had to be kept in step by eye.

**The Makefile did not depend on the suite modules.** `$(NUCTESTS)` listed
`tests/nuctests.nuc` and `lib/*.nuc` but not `tests/suite-*.nuc`, so an edit to
`suite-s16.nuc` or `suite-modules.nuc` did not rebuild the runner — a silently
stale binary, which is how the first full run of this batch reported two
spurious skips. Fixed at the root with `$(wildcard tests/suite-*.nuc)`.

#### TF-6 category (c), the C layout units (2026-09-09)

**4 shell functions → 25 tests**, 804 body lines retired (847 lines of the file,
counting the four rationale headers, the `spawn` lines and the blanks between):
`run_s16_pk_packed` (7), `run_s16_pk3_aligned` (7), `run_s16_bf_bitfields` (6),
`run_s16_an_anonymous` (5) — the four largest bodies left in the suite, into a
fourth suite module `tests/suite-layout.nuc`. `tests/run-tests.sh` is 10,576 →
9,729 lines and 151 → 147 functions. `make test` is 460 shell + 506 native =
966.

**They were large because the same oracle was spelled out three times.** Each of
the three layout units generated one `_Static_assert` per struct from `@sX =
global i64 N` lines with its own `sed -nE`, ran it under five targets with its
own loop, and guarded vacuity with its own `grep -c`. That is now one
`check-sizes-cross-target`, and the other two recurring shapes are one function
each: `check-agrees-with-cc` (one Nucleus program and one C program printing the
same list, each built by its own compiler) and `check-cheader-roundtrip` (a
generated header compiled by a strict C consumer, then read back). 123 lines of
shared machinery stand behind 455 lines of tests, and most of those 455 are the
embedded programs themselves — the same bytes the heredocs held.

**The clang/`cc` split, made properly.** The shell skipped four units on
`command -v clang`; clang is a hard dependency, as the fifth batch's correction
established, so those are now plain failures. `cc` genuinely is optional — nothing in the
build needs it — so the ten units whose oracle is the platform compiler open
with `(try (require-cc))`. That is `skip!`'s second real consumer, and it was
verified both ways: with `have-cc?` pointed at a name that does not exist the
units report `(status skip)` at exit 0 and `(status fail)` with message
`skipped: no cc to build the oracle against` under `--no-skip`.

**Five assertions got stronger, and none got weaker.**

- `s16-pk-access-align` counted `grep -cE '(load|store) i32[, ].*align 1$' >= 3`
  over the whole module and then asserted a negative regex to cover the case the
  count could not see. Each access is now asserted inside the function it
  belongs to (`check-in-define`), so the claim names which access it means.
- `s16-pk3-type-line-and-slots` matched the pad sizes as `[0-9]+`; the type line
  is now exact — `%B = type { i8, [12 x i8], i32, [12 x i8] }`.
- `s16-bf-cheader-roundtrip` asked for `: 4;` anywhere in the header, which any
  four-bit field in any struct satisfies. It now pins all three bit-field lines.
- `s16-an-refusals`' `--emit-cheader` case was a stderr grep; `check-emit-rejects`
  makes it a comparison against a `Diagnostic` record, which is category (a)'s
  upgrade applied to the one refusal an `--emit-llvm` run cannot reach.
- The cross-target oracle now requires `nucleusc` to **succeed** on each target.
  The shell wrote `|| true` and leaned entirely on the assert count, so a target
  that stopped emitting at all would have been caught only by the vacuity guard,
  with no message saying why.

**Verified by breaking it**, three ways, each reverted by editing the source
back: dropping `__attribute__((packed))` from the C side of the PK-1 table
reported `x86_64-unknown-linux-gnu: … static assertion failed … 'sizeof(struct
A) == 7' … expression evaluates to '12 == 7'`; unpacking `P` failed the type
line, and unpacking it with the type line adjusted failed
`in @rd: expected a line matching "*load i32, ptr %*, align 1"` with the whole
function body printed; and the `cc` probe above.

**One helper moved rather than being duplicated.** `fl-upto`, suite-float's
"prefix before the first byte b", is wanted by the size-assert parser too. It is
now `view-upto-byte` in `tests/nuctests.nuc` — the suite modules are one
compilation unit, so a helper left in a sibling would have been reachable by
accident, which is not the same as being shared on purpose.

**One trap worth carrying forward.** A test that writes a header and a C
consumer of it side by side must `#include` the header by **base name**. A
quoted include resolves from the including file's own directory, and the path
`test-write-file` returns is relative to the project root — which is right for
`import-use`, and wrong for `#include`. Written up in `docs/testing.md`.

#### TF-6 category (c), what a `.nuch` carries (2026-09-09)

**4 shell functions → 20 tests**, 430 body lines retired (484 lines of the
file): `run_w9_nuch_ns_union` (5), `run_w9_nuch_import_order` (5),
`run_w9_nuch_declare_generic` (4), `run_w9_nuch_declare_shadowed` (6), into
`tests/suite-modules.nuc`, whose subject they already are.
`tests/run-tests.sh` is 9,729 → 9,246 lines and 147 → 143 functions.
`make test` is 440 shell + 526 native = 966.

**The capability this batch needed is `link-run`.** A unit that compiles a
library and its consumer *together* proves nothing about the library's header —
the compiler has seen the source either way. Compiling the two separately and
linking makes the **linker** resolve the symbol, so the claim becomes "the
header promised the name the library actually exports", and a wrong answer is an
undefined reference rather than a silently different program. `link-run` takes a
space-separated list of `.o` or `.ll` paths, links with clang, runs the result
and returns stdout. Verified by breaking it: dropping the library's object from
the link reported `undefined reference to 'w9no-add'` and
`undefined reference to 'w9no-counter'` — exactly the names the header carries.

**Four hand-rolled library setups became one.** Each unit built the same thing:
source under `l/`, generated header under `h/`, object beside them, with the
source deliberately outside the include path (`resolve-import` tries `.nuc` in
every search directory before any `.nuch`, so a header next to its source is
never read). That is now `NuchLib` plus `nuch-lib` and `nuch-link-run` — write,
emit, compile, then "compile this consumer against the header and link it
against the library" as one call.

**One assertion was a misattribution, and the record found it.**
`w9-nuch-shadowed-declare-reported` grepped stderr for two strings; the second —
`the header declares helper(i32):i32, the unit has helper(i64):i64` — is a
**note**, not the error's message. Two independent greps over one blob cannot
tell those apart, which is the defect §T4.2 named and category (a) found three
instances of. It is now `check-error-anywhere` for the error and
`check-note-anywhere` for the note. `w9-nuch-shadowed-both-sites-named` was one
regex spanning the `file:line: error:` prefix *and* the message; `check-error-at`
pins the header's path and line 2 as fields, and a second check requires the
message to name the defining site. Breaking the line number to 3 prints the
whole diagnostic record, notes included, where the shell printed a failed match.

Four helpers in `tests/nuctests.nuc`: `link-run`, `compile-object-in`
(`compile-object` under `-I`), `write-into` (a file in a *subdirectory* of the
scratch tree, which `test-write-file` cannot reach) and `emit-into` (an emitted
artifact written where the next compile can read it).

**Two of the four had their `spawn` line ~3,000 lines from the body** — the trap
`context/build.md` records — so the deletion took body and `spawn` as separate
ranges. One surviving unit's comment named `run_w9_nuch_declare_generic` and was
reworded to name the suite module instead.

**One thing not to repeat.** The deletion script also collapsed runs of blank
lines, which reached two pre-existing four-blank separators elsewhere in the
file and turned a clean deletion diff into unrelated churn. Both were put back;
the rule is now in `context/build.md`.

#### TF-6 category (c), what a `.h` carries (2026-09-09)

**7 shell functions → 32 tests**, 662 body lines retired (754 lines of the
file): `run_w9_cheader_globals` (5), `run_w9_cheader_identifiers` (4),
`run_w9_cheader_imported_types` (4), `run_w9_cheader_niche_types` (4),
`run_w9_cheader_struct_tag` (5), `run_w9_cheader_overload_symbols` (5) and
`run_w9_cheader_reserved_words` (5), into a fifth suite module
`tests/suite-cheader.nuc`. `tests/run-tests.sh` is 9,246 → 8,492 lines and
143 → 136 functions. `make test` is 408 shell + 558 native = 966.

The successor to the previous batch, one step further out: a `.nuch` is read by
`nucleusc`, a `.h` by a C compiler, and the argument for testing them is the
same. Reading the header is never the claim. A header that merely parses can
still bind an `asm` label to a symbol no object defines, or agree about names
and disagree about layout — so all seven units end in a C consumer that is
compiled, linked against the real object, and run.

**Seven hand-rolled setups became one.** Every unit wrote a library, emitted its
header, compiled its object and built a consumer beside them; that is `CLib`
plus `c-lib` and `c-lib-run`. `c-header` is the variant for a unit whose claim
is that a declaration was *refused*, where there may be no symbol to link at all.

**`cc-link-run` is `link-run` generalised and made strict.** It takes `.c`
alongside `.o`/`.ll` — clang takes any of them — adds `-I` for the scratch
directory, and compiles with `-Wall -Werror`, which three of the seven shell
units did not. `link-run` is now that with no include directory, and
`driver-link-run` underneath takes the driver, so `cxx-link-run` is one line:
the C++ consumer is the reason the reserved-word table carries C++'s keywords,
since a generated header is routinely read behind `extern "C"` where `class` and
`delete` are as fatal as `union` is in C.

**`nm-defined` is the witness a consumer cannot be.** Grep over a header cannot
tell a correct label from one naming a symbol that does not exist, and running a
consumer only proves the labels it happens to call. `check-labels-defined`
states the invariant against the object — *every* label the header binds must be
a symbol the object defines — rather than against a hardcoded list, which is the
only form that outlasts a change to the mangling. Two units did this by hand
with `nm | awk | sort -u` and a shell loop, and disagreed on the filter (`T`/`W`
in one, `!= U` in the other).

**Two assertions got stronger, none weaker.** The operator check was
`! qgrep -E 'asm\("[<>=!+*/%-]+"\)'`, a character class that has to be kept in
step with the operator set; it is now "every label in every committed `lib/*.h`
contains at least one ASCII letter", which is the actual claim — an operator's
name is all punctuation — and needs no maintenance. And
`w9-cheader-private-global-not-exported` discarded the compiler's stderr and
asserted only that the consumer failed, so a consumer that failed for an
unrelated reason passed it; it now requires the diagnostic to name `hidden`.

**Verified by breaking it**, five ways, each reverted by editing the source
back. Dropping the label-stripping from `check-no-stray-hyphen` reported
``hyphen survives into C: extern int64_t my_count asm("my-count")`` — proof the
line loop runs at all. Inverting the operator predicate reported
`lib/allocator.h binds the operator label alloc-handle-alloc`, proof the corpus
scan finds labels rather than passing on an empty set. Inverting
`check-labels-defined` reported `the header binds scale.pPt.i32, which the
object does not define` with the real symbol list attached. Searching the corpus
for `typedef` instead of `typedef struct {` named `lib/allocator.h`, and adding
a nonexistent stem to the corpus compile named `lib/nosuchheader.h`. The skip
path was checked by running with `c++` hidden from `PATH`:
`(status skip) (message "no c++ to build the C++ consumer with")`.

Four helpers in `tests/nuctests.nuc`: `cc-link-run`/`cxx-link-run` over a shared
`driver-link-run`, `cc-syntax-only-in` (the include-path form, for a claim whose
expected answer is "it does not compile"), `nm-defined`, and `have-program?`,
which `have-cc?` and the new `have-cxx?` are now one line each on top of.

**The heredoc trap, hit exactly as recorded, and the 966 invariant caught the
consequence.** A naive `^}$` scan for a function's end stopped at the C `main`'s
closing brace inside a heredoc and reported the seven bodies as 389 lines when
they are 662. `context/build.md` already warned about this; the fix is the
heredoc-aware scan it prescribes. But the *same* truncated ranges were also used
to enumerate what each unit asserts, so one verdict at the tail of the niche
unit — `w9-cheader-committed-headers-no-niche-tag`, a corpus scan for the
`struct _BANG…` tag across `lib/*.h` — was never ported, and the deletion
retired 32 verdicts against 31 new tests. `make test` came back 408 + 557 = 965
and named the gap immediately. Enumerate a unit's verdicts from the same ranges
the deletion will use, and count before believing the port is complete. Four of
the seven had their `spawn` line ~3,600 lines from the body, so body and `spawn`
went as separate ranges.

#### TF-6 category (c), what a C header import loses (2026-09-09)

**6 shell functions → 21 tests**, 797 body lines retired (856 lines of the file,
including the family's own section banner): `run_l1_member_opaque` (3),
`run_l2_layout_matrix` (4), `run_l2_libc_layouts` (2), `run_l3_decay` (2),
`run_l4_returns_twice` (2) and `run_l5_typedef_names` (8), into a sixth suite
module `tests/suite-cimport.nuc`. `tests/run-tests.sh` is 8,492 → 7,637 lines
and 136 → 130 functions. `make test` is 387 shell + 579 native = 966.

The whole L1-L5 family, which is why it is one batch: it is contiguous in the
file, it has a single shared claim — importing a C header must either produce
the layout C produces or fail SAFELY — and it is the largest body left. The
three biggest remaining functions were all in it.

**A dead verdict, found by counting.** `run_l2_libc_layouts` names three
verdicts but emits only two: `l2-libc-opaque` appears in the two early-return
skip paths and nowhere else, so on any machine with a working `cc` it is never
reported. There was nothing to port — the assertion it once named is gone — so
the batch retires 21 live verdicts and adds 21. Worth stating because the static
count (32 `echo "PASS` lines across the family) and the live count disagree, and
only the live one reconciles against 966.

**Seven assertions got stronger, none weaker.** Every located diagnostic the
shell matched with a path wildcard is now exact text including the resolved
header path: `[^ ]*l1-members\.h:27` became
`declared at ./tests/fixtures/l1-members.h:27; only pointers to it are valid`,
and the same for the `l2-arrays.h` rows and for `l5-unrepresentable-message`'s
own generated header. Two L5 refusals moved from a stderr grep to
`check-error-at`, which pins the file and line as *fields* — the duplicate
definition at line 3, the `deftype` collision at line 2. `l5-repl-rollback`
asserted the session survived with `qgrep -F '7'`, which any line containing a 7
satisfies; it is now the exact line `nuc>   7`, and its positive control — which
previously only checked that no "unknown type:" appeared — gained the matching
`nuc>   9`. And three units ran their `cc` cross-check inside
`if command -v cc`, silently passing with no oracle at all when it was absent;
they now open with `(try (require-cc))`, so an absent `cc` is a visible skip
rather than a green tick over an assertion that never ran.

**Two capabilities.** `check-ir-parses` runs `llvm-as`, because `--emit-llvm`
never reads back what it writes and exit 0 says only that the compiler produced
text. `opt-o2` runs `opt -O2 -S`, the only way to ask whether `returns_twice`
changes what the optimizer does; the L4 unit keeps the shell's negative control,
which is what makes it an assertion — "`-O2` did not tail-call `_setjmp`" is
also true of an `-O2` that tail-calls nothing, so the same module with the
attribute stripped must tail-call it. That control doubles as the proof that the
stripping helper works.

**One limit raised, not absorbed.** The reader caps a string literal at 4095
decoded bytes (a fixed buffer in `src/reader.nuc`), and the libc survey's
Nucleus program is 4490 — the error is `string literal too long`. It is split
into two literals at the declarations/`main` boundary with a comment saying why.
Moving it to `tests/fixtures/*.nuc` would have been worse: a new `.nuc` there is
an IR-snapshot input and would force a re-take. Raising the cap is a change to
the reader and belongs to review, not to a test port; recorded in
`context/build.md`.

**Verified by breaking it**, three ways, each reverted by editing the source
back. Changing one opaque row's declared line from 37 to 38 printed the whole
diagnostic record against the expectation. Adding 1 to one field offset in the
libc program reported `line 2 differs / want "timespec … tv_nsec=8" / got
"… tv_nsec=9"` — which is also the proof the 13-line oracle is comparing live
glibc data rather than two empty outputs. Feeding `check-ir-parses` a module
with `ret i32 zzz` reported `llvm-as: …: error: expected value token`.

The family's section banner went with it, and its one durable point moved into
the module header: the IR sweep over the tree's own modules is structurally
blind here, since the whole tree imports six C headers exposing 14 of the 65
struct types the survey measured, so a change that broke `signal.h` or
`netinet/in.h` outright would sweep clean. One surviving comment that named
`run_l2_layout_matrix` for its methodology was reworded to name the module.

#### TF-6 category (c), the C declarator shapes a header parser drops (2026-09-09)

**2 shell functions → 8 tests**, 289 body lines retired (307 lines of the file,
including both section banners): `run_cd_declarators` (6) and
`run_cd4_declarator_list` (2), into a seventh suite module
`tests/suite-declarators.nuc`. `tests/run-tests.sh` is 7,637 → 7,330 lines and
130 → 128 functions. `make test` is 379 shell + 587 native = 966.

The pair goes together because it is one claim in two halves: a C declaration is
shared specifiers plus a *list* of declarators, and each declarator carries its
own pointer depth, extents and bit-field width. CD-1/2/3 is the list inside a
declaration; CD-4 is the list after an aggregate body. The retired L family's
own comment already named this pair as sharing its methodology.

**Five assertions got stronger, none weaker.** The three CD-2 signatures were
prefix regexes — `^define i32 @f_ta\(i32 ` says nothing about the rest of the
line — and are now the whole `define` line including the section. CD-4's array
storage was the substring `global [3 x %__carr.cd4_G] zeroinitializer`, now the
whole `@gv = …, align 8` line. `cd1-mixed-pointer-refused` matched its located
error with the path wildcard `[^ ]*cd-declarators\.h:47`; it now goes through
`check-opaque-at`, which pins the resolved path, the line, the message and the
absence of any `%cd_mixed_ptr = type`. Both "the import was silent" checks were
`[ -s "$d/m.err" ]` on a file the shell also appended link errors to later in
the same unit; they are `check-empty` over the compile's own stderr, so a
warning trips them and nothing else can.

**Four assertions the shell's comments claimed but never made.** CD-4's table
covered 8 of the 11 types; `cd4_E`, `cd4_F` and the minted `%__carr.cd4_G`
element are now rows, which is what says an array declarator in a later position
anchors on the *body* rather than on a placeholder. The comment on `cd4_Ep` said
a pointer declarator must be a typedef-table entry "NOT a second StructDef, or
it shadows the record", and asserted neither half: `%cd4_Ep = type` must now be
absent and `@f_ep` must take a `ptr`. CD-3 gained `%cd_tag` and
`%__carr.cd_anonarr` for the same reason its globals were already pinned.

**The `tcp_info` witness asks three questions instead of one.** It was size plus
the struct's own alignment, read as the offset of a `tcp_info` after a `char`.
Both totals are unchanged by a bit-field run that consumed the wrong storage, so
the unit now also prints the offsets on either side of the run —
`tcpi_options` at 5 and `tcpi_rto` at 8 — from both compilers. Member offsets on
an imported C struct work on the Nucleus side, which is what makes the stronger
oracle available at all.

**Two skips replace two green ticks.** Both `sizeof`-vs-`cc` units ran their
oracle inside `if command -v cc` and echoed `PASS … (SKIP: …)` when it was
absent; they now open with `(try (require-cc))`. The `tcp_info` unit probed for
`netinet/tcp.h` by trying to build its C oracle and echoing PASS on failure; it
now syntax-checks the probe with clang — a hard dependency, so the probe never
skips for its own reasons — and skips visibly when the header is not there.

**Verified by breaking it**, four ways, each reverted by editing the source
back. Widening `%cd_bits` to `[2 x i8]` failed the type table. Moving the opaque
row's declared line from 48 to 47 printed the real diagnostic beside the
expectation. Inverting the `%cd4_Ep` absence to a presence check failed, which is
how a negative assertion is shown to be about something. Adding 1 to the
`tcpi_rto` offset on the Nucleus side reported `line 3 differs / want
"tcpi_rto 8" / got "tcpi_rto 9"` — also the proof that both compilers really
ran.

**Raised, not absorbed: 59 dangling `run_*` names in `design/`.** Four batches of
this migration have retired shell functions that the Stage 15 and Stage 16 design
documents still name as the live gate, in "where the gate lives" tables. This
batch retargeted its own two rows and the three fixture headers whose opening
comment named a retired function (`cd-declarators.h`, and `l1-members.h` /
`l2-arrays.h` from the previous batch). The remaining sweep is mechanical —
compare every `run_[a-z0-9_]*` in `design/` against the functions still defined
in `tests/run-tests.sh` — but it spans documents this work has no other reason to
touch, so it belongs to review as one cleanup at the end of TF-6, not to a test
port.

#### TF-6 category (c), a mangled name on every export surface (2026-09-09)

**3 shell functions → 17 tests**, 270 body lines retired (303 lines of the file,
including three section banners and two distant `spawn` lines): `run_ns6` (6),
`run_sm3` (6) and `run_w9_ns_symbol_ownership` (5), into an eighth suite module
`tests/suite-exports.nuc`. `tests/run-tests.sh` is 7,330 → 7,027 lines and
128 → 125 functions. `make test` is 362 shell + 604 native = 966.

The three go together because they are one claim in three spellings: a public
name the compiler mangles — by namespace (`geom/area` → `geom__area`), by `?`
or `!` (`full?` → `full_QMARK`), or by which namespace OWNS it — must be the
same symbol on all three export surfaces, and a separately compiled consumer
must link against the object and run. They also share one machine, which is why
the port shrinks them: write a library, emit `.ll`/`.nuch`/`.h`, write a
consumer, emit its IR, link the two objects, compare stdout. That is `Exports` +
`Consumer` + `link-two` — three helpers replacing three hand-rolled copies that
had drifted apart in their `import` spellings and in what they bothered to
check.

**Every emit in all three units was `2>/dev/null || true`.** A failed emit left
an empty file, the greps then failed, and the unit reported a missing symbol —
never the compiler error that caused it. `emit-for-file` fails with the
diagnostic. The same held at the other end: `clang … 2>/dev/null && [ "$(bin)"
= "…" ]` reported one FAIL for a link error and a wrong answer alike, where
`link-run` prints clang's output and `check-eq` prints want against got.

**Ten assertions got stronger, none weaker.** The header checks were unanchored
substrings — `qgrep 'geom__area'` matches `geom__areaX` — and are now exact
declaration lines. `n6-cheader-c-legal` gained the object side, since a header
name is only right if something defines it. `n6-nuch-carries-ns` asserted
`(ns geom)` alone and now also both `(declare …)` lines, which carry the BARE
spelling the importer re-keys. `n6-import-resolves-mangled` checked `area` and
not `perimeter`, and now pins both numbered call lines. `sm3-lib-symbols` and
`sm3-nuch-roundtrip` moved from `-F` substrings to whole lines.
`w9-ns-symbol-ownership` gained the `weak_odr` linkage of the imported
definition, which is what lets two objects that each inline it link at all.

**Three assertions the surfaces demanded and nobody made.** `.` is no more a C
identifier character than `?` is, so an overloaded `?` method needs *two* right
answers in the header — the sanitized spelling and the real symbol on an `asm`
label. `sm3-cheader-fn-legal` checked neither for the pair; it now pins
`int32_t even_QMARK_i32(int32_t x) asm("even_QMARK.i32");` and its `i64` twin.
The same gap existed for the namespaced type: `b3-ns-type-export-surfaces`
checked the typedef and never the function, and now pins
`int32_t gt__pt_sum(struct gt__Pt* p) asm("gt__pt-sum");`, where the C name and
the link name are different strings that both have to be right. And
`sm3-cheader-typenames` checked four spellings of the mapping but not the union
tag enum, so `enum Shape_QMARK_tag` and both arm constants are rows now.

**One capability.** `ir-symbols` + `check-same-symbols` replace
`grep -o … | sort -u` into two files and `cmp`. The comparison is mutual
containment rather than a sort, so it does not depend on where in each module a
symbol first appears, and it prints both sets when they differ. The shell's
argument for comparing sets rather than asserting literals is preserved
verbatim, because it is right: what the unit claims is that a namespace's symbol
is the same string whether or not another namespace shares the compilation unit.

**A discovery, from a diagnostic that was already good.** An unprefixed
`(import "path")` binds the library under the FILE STEM, not under the `(ns …)`
the file declares. The shell's fixtures worked only because their names and
namespaces happened to agree; naming them `w23o-w23a.nuc` broke `w23a/describe`
with `'w23a' is not in scope in this file`, and the note listed the stem. The
same holds for a generated `.nuch` a consumer imports bare, which is why
`export-surfaces` names its artifacts after the library. Recorded in
`context/build.md`; the coupling is now stated in the module beside the fixture
it constrains.

**Verified by breaking it**, five ways, each reverted by editing the source
back: a `geom__area` → `geom_area` header spelling; dropping the `asm` label
from an overloaded declaration; one wrong digit in the linked program's expected
output; asking for a symbol base neither module defines, which fires the
non-empty guard; and comparing the two modules on the base `@w23`, whose sets
genuinely differ — `alone: @w23a__describe / together: @w23a__describe
@w23b__describe`, which is the set comparison itself working rather than its
guard.

#### TF-6 category (c), what two objects owe each other (2026-09-09)

**3 shell functions → 12 tests**, 214 body lines retired (251 lines of the file,
including the three rationale headers and three distant `spawn` lines):
`run_w9_lib_standalone` (4), `run_w9_multi_object` (3) and
`run_w9_shared_init_warning` (5), into a ninth suite module
`tests/suite-linking.nuc`. `tests/run-tests.sh` is 7,027 → 6,776 lines and
125 → 122 functions. `make test` is 350 shell + 616 native = 966.

The three go together because a `.nuc` import is INLINED, and every consequence
of that is a question about two objects rather than one: which of the duplicated
copies the linker keeps, which definitions a unit owns and exports, and the one
thing the compiler cannot decide alone — a run-time initializer on a global the
unit does not own, which every importing object runs again on the one shared
global. `lib/` is the corpus all three are about: `make lib-so` links all 43
objects.

**A regex over `nm` became the whole symbol table.** The shell asked two
questions of `run_w9_multi_object`'s objects — is `w9-bump` weak in both, is
`w9-side-bump` undefined in main.o — with `grep -cE ' [WV] w9-bump$'` and
`qgrep -E '^ +U w9-side-bump$'`. Both objects have five symbols and four; the
unit now pins every one of them, so it also states that `w9-count` is a single
weak *object* (`V`) rather than two private ones, that `w9-get` is a copy too,
and that `main` and `w9-side-bump` are the only strong definitions either object
carries. `nm-typed` normalizes `nm` to `<type> <name>` lines and `check-line-set`
compares them as a set — `nm` sorts by value, and every symbol in a relocatable
object has value 0, so order is not a property to assert.

**The shell's own argument, tested, turned out to be sharper than the shell's
test.** Its comment says a linker that kept two private copies would also link,
so the counter is read back through a third call and 1 + 2 = 3 is "reachable
only if the two objects share one `w9-count`". Making the global `defvar-`
disproves that: the program still prints 3, because the one weak `w9-bump` that
survived carries its own file's copy with it, and all three bumps reach that
one. The symbol table catches it exactly — `V w9-count` becomes
`b w9share_p1__w9-count`. The value and the symbol table are complementary, not
redundant, and the ported comment now says which one answers which question.

**Two search directories became one.** The shell used `-I inc -I share` with the
generated `.nuch` in a third directory. What is load-bearing is only that
`w9side.nuc` is NOT on the search path — `resolve-import` tries `.nuc` in every
search directory before any `.nuch`, so the source would win and the call would
stop crossing the object boundary. Putting the `.nuch` beside the shared source
says exactly that with one `-I`, and `-I` takes one directory at a time
(`nucleusc.nuc:18859`), so the helpers need no list.

**Diagnostics instead of stderr greps.** All five arms of the initializer family
are about what the compiler said: `qgrep -F "dshare.nuc:3: warning: defvar: …"`
for the one that warns, `[ -z "$out" ]` for the three that must not. Under
`--diagnostics=sexp` these become `check-warning-at` against one record —
severity, file and line matched together — and `check-silent`, which reports the
diagnostics it found rather than an empty-string comparison. `check-no-errors`
is not that claim: a *warning* is what three of these units assert the absence
of.

**One assertion the shell skipped, and one it could not make.** Its `-c` loop
over `lib/` did `continue` when a file would not compile at all, on the grounds
that standalone compilation is the other loops' assertion; the emit loops do
gate that, so this one now requires the object too. And `w9-linkage-ownership`
read `define internal …` out of the IR, which is a word, not a property: the
unit now also compiles the object and pins its five linkable names, so the
private definer's absence from the symbol table is what says `internal` meant
something. The `_pN` counter stays a glob — N is the 1-based creation order of
files that own private names (`nucleusc.nuc:5323`), so it moves when an
unrelated file gains a `defn-`.

**Shared infra, deduplicated.** Four functions in `tests/nuctests.nuc` repeated
the same fifteen lines of "run a prepared command and read the result", and
three more repeated "run the binary just built". Extracted as `compiled-run`,
`run-stdout` and `run-exit`, which is what made `emit-checked`, `object-checked`
and `build-checked` eight lines each rather than another three copies;
`driver-link` split from `driver-link-run` for the same reason, since a program
whose answer is an exit status links identically to one whose answer is stdout.

**Verified by breaking it**, seven ways, each reverted by editing the source
back: feeding the duplicate-`define` scanner a module concatenated with itself
(`lib/allocator.nuc defines @arena-init twice`); the `defvar-` above; writing
`w9side.nuc` onto the search path, which turns `U w9-side-bump` into a weak
inlined copy; `defn-` → `defn` on the private definer; a compile-time
initializer for `d-runs`, which fails all three of the units that measure it;
pointing the owner-silence unit at the importing file; and a temporary
`lib/zz-share.nuc` + `lib/zz-user.nuc` pair carrying a real shared initializer,
plus a `lib/zz-broken.nuc` whose exported signature names an unresolvable type.
That last one corrected a wrong first attempt: a file whose *body* calls an
undefined function passes `--emit-nuch` and `--emit-cheader`, because neither
mode compiles bodies — the perturbation has to be in the signature.

#### TF-6 category (c), the declarations a header mode must refuse (2026-09-09)

**2 shell functions and their shared helper → 48 tests**, 212 body lines retired
(250 lines of the file, including the two rationale headers and two distant
`spawn` lines): `run_w9_header_validation` (20) and
`run_w9_empty_name_position` (28), into a tenth suite module
`tests/suite-refusals.nuc`. `tests/run-tests.sh` is 6,776 → 6,526 lines and
122 → 120 functions. `make test` is 302 shell + 664 native = 966.

The two go together because they are one defect counted twice. Both header modes
run the compiler's PRESCAN layer and never its EMISSION layer, and every prescan
defers its diagnosis to emission; with no emitter downstream, nothing asked, and
a truncated definer or a `()` in a name position reached a raw `(node-at form N)`
dereference. W9 item 38 found it through the header modes, item 45 through
`--emit-llvm`, and the fix is the same walk. They also shared one shell helper —
`w9_header_agrees`, which is why retiring one without the other was not possible.

**The three-way agreement became a comparison of records, not of stderr blobs.**
The shell captured each mode's stderr and required the three strings equal. Under
`--diagnostics=sexp` the same claim is `diag-list-text` over three `(Vector
Diagnostic)`s — severity, file, line and message per record — and each unit also
pins the located message itself through `check-error-at`, which the string
comparison could not do: three modes agreeing on a *wrong* message passed. That
is 44 messages now stated in the suite rather than deferred to whatever the
compiler happens to say.

**`Compiled` gained `exit`.** `ok?` is `success?`, which cannot tell 1 from 139,
and the whole of item 38 is that a segfault also produces no output — so
"refused" and "crashed" were indistinguishable to a helper reading `ok?`. The
field is `exit-code`, which spells a signalled child 128+signal, and the two
header modes are required to exit exactly 1.

**Two boundaries, asserted rather than assumed.** A BODY error is out of scope by
construction (no body is read), so `--emit-llvm` refuses
`(defn w38-body (x:i64):i32 (return (as i32 x)))` and both header modes still
succeed; `deferror` and `def-rmacro` are refused by `--emit-llvm` and rightly
silent in the header modes. The shell asserted only the `--emit-llvm` half of
each and left the rest to a comment. `check-probe-llvm-only` asserts both halves,
so a crash in either mode is still a failure.

**The two negative controls became whole artifacts.** `w38ok.nuc` was checked
with four `qgrep -F` substrings and `w45ok.nuc` with two; both headers of both are
now pinned line by line. That is what makes the template visible as the one
declaration the two surfaces disagree about, and each is right: a `.nuch`
consumer can stamp `w38-tw` from the body it carries, and C has nothing to stamp
it into, so the C header says `/* w38-tw: generic template; not exported */`.
Reading the C spelling of the inline union is likewise the only way to see the
walk descended into it rather than skipping a field it could not name.

**Verified by breaking it**, seven ways, each reverted by editing the source
back: a message with one letter changed (`defn: bad form` → `bad forms`); a
fixture's pinned line 7 → 8; one character off a generated C header line
(`} W38Box;`); routing `deferror` through the refusal helper rather than the
boundary one, which fails on `--emit-cheader exited 0, not 1`; the required exit
1 → 2; the stdout-must-be-empty check inverted to `check-non-empty`; and the
three-way comparison itself inverted, which fails every unit with both lists
printed. An eighth attempt was invalid and is worth recording: a file carrying a
signature error *and* a body error does not make the modes disagree, because the
signature error aborts before the body is reached.

#### TF-6 category (c), what an identifier may be in generated IR (2026-09-09)

**1 shell function → 3 tests**, 114 body lines retired (130 lines of the file,
including its rationale header and one distant `spawn` line):
`run_w9_ir_name_positions`, into an eleventh suite module
`tests/suite-ir-names.nuc`. `tests/run-tests.sh` is 6,526 → 6,396 lines and
120 → 119 functions. `make test` is 299 shell + 667 native = 966.

W9 item 39: LLVM's unquoted identifier has two rules — a body character class
and a first-position rule — and the compiler applied only the first, only to
global symbols. The failure was at IR-parse time, on a line of generated IR the
user never wrote.

**The shell asserted only that the programs printed the right numbers.** It
never read the IR, so it could say the escape happened but not what it was. Each
unit now pins the escaped name in every position it occupies — type, union arm,
global, function, parameter, `let` binding, match binder and `label`/`goto`
target — as whole IR lines. The `.addr.N` serial is a scope counter, so it stays
a glob; everything around it is exact.

**`check-ir-parses` is the assertion the item is actually about.** `--emit-llvm`
never reads back what it writes, so exiting 0 says nothing about whether the
module is valid — and being invalid was the bug. Handing the module to `llvm-as`
states it directly. Confirmed as the live gate by editing `_QMARK` back to `?`
in an emitted module: `llvm-as` reproduces the item's own quoted error,
`define i32 @add_QMARK(i32 %ok?.arg, i32 %n!.arg)`, at that column.

**A regex sweep became the header, line by line.** The C-callable unit asserted
`! grep -v '^/\*' … | qgrep -E '\b[0-9]+[A-Za-z_]'` — no digit-leading
identifier anywhere — which passes on a header that declares nothing at all. The
unit now pins each declaration, `#define _2LIM 9` included, plus the six symbols
`nm` finds in the object as a set, plus the absence of any `asm` label. That
last is the actual ruling: C's first-position rule is identical, so
`sanitize-for-c` escapes with the same `_`, the C spelling and the link symbol
agree, and no label is needed. The consumer also builds under `-Wall -Werror`
now, where the shell ran plain `clang`.

**One helper moved rather than being copied.** `CLib` and its `c-lib` /
`c-lib-run` / `c-consumer-run` machine — write a library, emit its header beside
it, compile its object, link a C consumer against it — lived in
`tests/suite-cheader.nuc` and now has a second caller, so its 82 lines moved to
the shared layer in `tests/nuctests.nuc` and are documented in `docs/testing.md`.
A pure move; no behaviour changed.

**Verified by breaking it**, six ways in the source, each reverted by editing it
back: the `@_2count` global asserted in its unescaped spelling; `%ok_QMARK.arg`
/ `%n_BANG.arg` asserted as `%ok.arg` / `%n.arg`; the `%_2acc.addr.*` glob with
its escape removed; `check-not-contains "asm("` inverted; one symbol dropped
from the `nm` set, which fails on the count; and one digit changed in a
program's expected output.

#### TF-6 category (c), what a place is (2026-09-09)

**3 shell functions → 9 tests**, 263 body lines retired (281 lines of the file,
including three rationale headers and three `spawn` lines):
`run_s16_dot_forms_retired` (3), `run_s16_set_places` (3) and
`run_s16_set_generic` (3), into the existing `tests/suite-s16.nuc` rather than a
new module — the Stage 16 language surface is where they belong.
`tests/run-tests.sh` is 6,396 → 6,115 lines and 119 → 116 functions. `make test`
is 290 shell + 676 native = 966.

The three are one ruling read three ways (dot-forms.md §5 steps 4-6): `.` and
`.&` are gone, `set!` takes a place, and a computed key dispatches through the
`set` generic. Every retired spelling stays RESERVED, so the answer is the
replacement rather than "undefined function" and no user definition can shadow
it into silence.

**The claim the shell's own header made and its body never tested.** "Every
place delegates to the writer it replaced, so the spellings must emit identical
IR" — and then the unit only checked that a program printed the right numbers,
which four different code paths could equally do. `s16-set-places` now compiles
one function four ways (`(set! (p 'y) 2)`, `(set! (get p 'y) 2)`,
`(set! (_get p 'y) 2)`, `(set! (deref (addr-of p 'y)) 2)`) and compares the
modules whole: `compile-source` writes every fixture to the same `t.nuc`, so
`; ModuleID` and `source_filename` already agree and `check-golden` can rule on
the artifacts rather than on filtered ones. All four are byte-identical.

**Twelve `qgrep -F`s over stderr became twelve located diagnostics.** Each of
the retirement messages, the two reserved-name refusals, the two
not-an-assignable-place refusals, the two missing-field refusals and the
missing-`set`-method refusal is now one `check-error-at` against one record, so
the message and its line must come from the same diagnostic. `()` in a place
position keeps its own row: it reads as a null node, so the place judgement has
to precede any dereference of it.

**One accumulator per function became one assertion per claim.** Each shell unit
threaded an `ok=1` variable through three to seven probes and printed a single
FAIL naming none of them, dumping up to ten lines of concatenated stderr. Nine
units now fail at the assertion that failed, with the wanted and got values.

**Verified by breaking it**, nine ways — one per unit — each reverted by editing
the source back: a retirement message with `2-argument` changed to `3-argument`;
a pinned line 2 → 3; one digit changed in each of the five programs' expected
output; a pinned line 5 → 4 on the missing-method refusal; and one of the four
place spellings given a different constant, where `check-golden` names the
differing IR line and both store instructions.

#### TF-6 category (c), what the target decides, not the compiler (2026-09-10)

**3 shell functions → 12 tests**, 289 body lines retired (304 lines of the file,
including three rationale headers and three `spawn` lines):
`run_c4_target_headers` (4), `run_platform_constants` (4) and `run_rv6_fp_abi`
(4), into a new twelfth module `tests/suite-target.nuc` (363 lines).
`tests/run-tests.sh` is 6,115 → 5,811 lines and 116 → 113 functions. `make test`
is 278 shell + 688 native = 966.

Three stages, one subject. What `size_t` is in a declaration (Stage 16 C4), what
`O_CREAT` equals (Stage 17 platform constants) and how a struct of two floats is
passed (Stage 14 RV-6) are all the target's to answer, and each was once
answered by something written into the compiler instead: the host's headers
under every `--target=`, a hardcoded constant table in `lib/file.nuc`, and the
SysV classifier for every machine.

**So no oracle is a number quoted in the test.** The C4 lane reads the widths
back out of the emitted module (avr's `size_t` is `i16` where the host's is
`i64`, with glibc's `__memcmpeq` as the independent witness that the host's text
was *not* read after all). The constants lane compares against a C program clang
builds from the same headers — `printf` of the seven macros, `-Wall -Werror` —
so the reference is the C compiler rather than this container. The RV-6 lane
names both triples explicitly and pins shapes derived from
`clang --target=riscv64-unknown-linux-gnu` on structurally identical C.

**A skip is a verdict about the environment, not a hole.** Two units decide
which lane they are by asking `clang -E --target=<t> -include string.h` whether
the target's headers are reachable: `c4-avr-target-headers` skips without them,
and `c4-missing-sysroot-falls-back` skips *with* them, because a fallback cannot
be observed on a triple that needs no fallback. Here avr's are installed and
i386's are not, so both run. The shell hardcoded the same assumption and would
simply have failed on a container where it did not hold.

**Two `2>/dev/null`s hid two diagnostics.** The riscv64 lane emits C4's fallback
warning (no riscv sysroot here) and the shell discarded stderr wholesale, which
also discarded any error. `rv6-ir` uses `check-no-errors` rather than
`check-silent`: *which* triple lacks a sysroot is a property of the container,
but an error would be a property of the compiler either way.

**Nineteen `grep -E`s over `define` lines became nineteen whole lines.** The
shell matched `^define .*@f_pair` and the like, so an argument list that changed
shape while keeping its name passed. The 8 flattening shapes, 10
register-counting shapes and 8 x86 anti-leak shapes are now exact `check-line`
assertions including the `section` attribute — the shell checked five of the x86
lines, and a leak in any of the other three would have gone unseen. The variadic
tail asked that no `float`/`double` appear anywhere in the `printf` call, which a
call that lost its arguments also satisfies; `check-match` on the whole call now
pins the five operand types in order, leaving only the SSA serials to `*`.

**Six refusals that "the compile failed" became six located `undefined:`s.** The
reserved `_MP_BASE`, the function-like `MP_FN`, the string `MP_STR`, the float
`MP_FLOAT`, the logical `MP_LOGIC` and the decimal-overflow `MP_OVER` each now
name the line that used them, so an unrelated error cannot stand in for the
refusal. The clang-predefine case reads the first letter-initial `#define` out of
`clang -E -dM` rather than naming one, since which it is is the platform's
business (`linux` here) — and a leading-underscore predefine would be refused by
the underscore rule instead, testing nothing.

**Verified by breaking it**, twelve ways — one per unit — each reverted by
editing the source back: `strlen` → `strlenx`; avr's `i16` → the host's `i64`;
the fallback warning's `HOST` → `host`; a pinned line 1 → 2; one digit in the
admitted-macro output; `MP_FN` → the admitted `MP_PUB` (which produces no
diagnostic at all); `8` → `9` for the private macro; `O_CREAT` → `O_EXCL` in the
C reference alone, where the printed 64 vs 128 shows the oracle really is read
from clang; `f_pair`'s `i64` → `i32`; `fpr7_dd`'s integer-convention pair → the
x86 double pair; one variadic `i64` → `double`; and `f_farr2`'s x86
`<2 x float>` → the riscv flattened pair.

#### TF-6 category (c), when a name may be used before its file is (2026-09-10)

**13 shell functions → 33 tests**, 318 body lines retired (462 lines of the
file, including five rationale headers, two section banners and thirteen
`spawn` lines): `run_w1_mutual` (2), `run_w1_ns` (2), `run_w1_graph_shapes` (3),
`run_w1_still_rejects` (2), `run_w1_declare_cycle_breaker` (2),
`run_w1d_cycle_accepts` (5), `run_w1d_cycle_diagnoses` (7),
`run_w1d_path_prefix` (4), `run_w1_deferred_union_payload` (1),
`run_w1_late_overload_symbol` (1), `run_w1c_unreachable_file` (2),
`run_w1c_defined_nowhere` (1) and `run_w1c_unreachable_type` (1), into a new
thirteenth module `tests/suite-imports.nuc` (773 lines).
`tests/run-tests.sh` is 5,811 → 5,348 lines and 113 → 100 functions. `make test`
is 245 shell + 721 native = 966.

The three sub-families are one walk. W1a registers every REACHABLE file's
signatures, protocols and type names before emitting anything, so a cross-file
reference stopped depending on import order; W1d then made a mutual import pair
legal, because once that prescan exists a cycle has nothing left to break; W1c
is what survives, since with order gone an unresolved name is a typo, a
genuinely absent symbol, or §2.7's reachability constraint. `w1_run` itself
stays in the shell — forty other functions call it — so only the W1 units and
their banner went.

**A vacuous test, found by running its fixture.** `run_w1_deferred_union_payload`
writes a program whose first line is `(compile-time (printf "ct ran\n"))`, and
`printf` left the prelude in the split: the compile dies at line 1 with
`unknown: printf` and never reaches the `(import-use string)` whose deferred
union payload is the entire subject. The shell asks only whether stderr contains
`undefined type`, so a different error every time reads as PASS. The native unit
uses `(compile-time (+ 1 1))` — same structure, no prelude dependency — and
asserts the real property: the compile is silent and the module parses, since
`use of undefined type named '__anon_union_…'` is the LLVM parser's own message
and `check-ir-parses` is what asks it. The perturbation restores the shell's
line verbatim and the unit fails on the `unknown: printf` the shell passed over.

**A dangling `Either` in a diagnostic, fixed rather than pinned.**
`cycle-definer-message` (`src/nucleusc.nuc`) built its note as
`"… back-imports. Either " + import-cycle-advice()`, producing "Either break
the cycle -- …" with no `or` — the "Either …, or …" scaffolding belongs to
`cycle-layout-message`, which has a second alternative to offer (use a pointer)
where a macro has none. It now reads "The fix is to break the cycle -- …",
keeping the advice text in one place. Nothing pinned it because the shell
grepped the message and never read the note.

**Three claims the shell's own comments made and its bodies never tested.** The
graph-shape comment says the walk dedups on resolved path so a file reached
twice is prescanned once — asserted only through an exit status, which a doubled
emission does not change; `duplicate-define-name` now states it over the whole
module. The W1b comment says prescanning under the importer's namespace would
"mangle it under the wrong prefix" — and checked only that the program returned
42; both `@w1alpha__a-thing` and `@w1beta__b-thing` define lines are pinned now,
in both import orders. And the W1e comment names
`emit-nuch-declare-import`'s "already in g-globals" early return as the thing
under test — so the module must carry the `define` and no `declare` beside it,
which is now asserted.

**The by-value cycle case pins the signature, not just the answer.** Its old
failure was a silent miscompile: with no layout the ABI classifier saw a
zero-sized aggregate and emitted `define … @w1-bcb(i0 %v.arg)`. Pinning
`(i64 %v.arg.0, i64 %v.arg.1)` — two SysV INTEGER eightbytes — says the layout
prescan ran, where the exit status only says the call happened to work.

**Nine stderr greps became nine located records.** Both duplicate-definition
refusals now name the blamed definer AND the file:line of the other one, which
the message carries and `qgrep -F "duplicate definition of 'w1-dupe'"` discarded;
the cycle macro and `deferror` refusals pin the note that names both cycle
members, which is what proves the compiler identified the cycle rather than
guessing; the path-prefix collision pins the binding already in force; and both
W1c notes pin the unreachable definer's path as a field. `w1c-defined-nowhere`'s
"and no note" is a search of the rendered diagnostic list rather than of stderr,
so a note attached to any diagnostic fails it.

**Verified by breaking it**, thirty-three ways — one per unit — each reverted by
editing the source back: eleven expected exit statuses moved by one; the
namespace prefix changed to a name nothing mangles to; four pinned diagnostic
lines moved; two negative assertions inverted; the `%W1SC` type widened; the
by-value signature narrowed to `i32`; one variadic-shaped call operand retyped;
the `w1d` stdout changed to `w1e`; and the `compile-time` line restored to the
shell's own.

#### TF-6 category (c), what a global is worth before `main` runs (2026-09-10)

**10 shell functions → 32 tests**, 409 body lines retired (555 lines of the
file, including six section banners and ten `spawn` lines): `run_g0_value_order`
(6), `run_g0_value_scoping` (5), `run_g0_cycle_values` (3),
`run_g0_still_rejects` (5), `run_g1_fold_cross_file` (4), `run_g2_cheader` (1),
`run_g2_nuch` (1), `run_g3_zero_cost` (1), `run_g3_library` (1) and
`run_g4_order` (5), into a new fourteenth module `tests/suite-globals.nuc`
(797 lines). `tests/run-tests.sh` is 5,348 → 4,793 lines and 100 → 90
functions. `make test` is 213 shell + 753 native = 966.

One question in five steps (global-init.md). G-0 registers `defvar` /
`defconst` / `defenum` names on the same whole-graph walk that already carried
signatures, so a value resolves on reachability rather than emission order; G-1
folds a constant initializer; G-2 adds `(array T N)` and constant aggregates;
G-3 runs what cannot be folded from `@__nucleus_init`, and only when there is
something to run; G-4 diagnoses the one thing none of that fixes — an
initializer reading a global whose own initializer has not run.

**The oracle is a VALUE almost everywhere**, and that is the family's own
argument: a global resolved to the wrong constant links and runs, and an
initializer that never ran leaves a zero indistinguishable from success unless
something reads it. The shell already knew this and every positive unit ran the
program; what the port adds is the artifact wherever the claim is about the
artifact rather than the answer.

**The zero-cost gate was half a test.** §4.8 requires a unit with no runtime
initializer to emit *nothing* — no `@__nucleus_init`, no `llvm.global_ctors` —
and the shell asserted exactly that absence, which is equally true of a module
that emitted nothing at all. The unit now pins all nine constant-initializer
shapes as emitted globals, `.bss` versus `.data` included, since a
runtime-initialized global also lands in `.bss` and the section is what
separates "folded to zeros" from "left for the initializer". The complement adds
one runtime initializer and requires those same nine to be **unchanged** beside
the new `@g3-rt = global i32 0` — which is what says the classifier moved one
initializer rather than the file.

**The library test could see only the effect.** `g3-library-nuch` links a
`.nuch`-exported library object into a consumer whose `main` never calls
anything, and asserted the program's exit status. The mechanism is in the
object: `nm` must show `__nucleus_init` as a **local** symbol (each object runs
its own), `g3-lib-n` as a `.bss` definition, and the two functions as the only
external definitions — four rows, compared as a set. (The section the linker
actually emits here is `.ctors`, not the `.init_array` the shell's comment
names; that is LLVM/linker territory, so the unit pins `llvm.global_ctors` and
the symbol table instead of a section name.)

**A suggestion nobody was reading.** `g0-ns-value-not-leaked` greps for
`undefined: G0-NSK`; the message is `undefined: G0-NSK (did you mean
'g0-nsa/G0-NSK'?)`, and the parenthetical — the spelling that would actually
work — is the whole point of the diagnostic. Likewise the duplicate-global note
carries the two ways out (rename, or namespace it and import prefixed) and the
G-4 note carries the ordering rule plus the cycle caveat; all three are pinned
now.

**The collision pair distinguishes the two orders for the first time.** Stage 15
B5 made the noun depend on which definer is emitted first, and the **blamed
file** moves with it — order1 blames the `defvar` while naming the function,
order2 the reverse. `w1_reject_multi` matches a message with no location, so the
shell could see only half of the property its own comment describes.

**Verified by breaking it**, thirty-two ways — one per unit — each reverted by
editing the source back: seventeen expected exit statuses moved; the two
collision nouns swapped with each other; four pinned diagnostic locations moved;
one negative assertion inverted; the did-you-mean spelling changed to the
namespace it is not; `weak_odr` dropped from a cross-file global; the C header's
named extent replaced by its value; the exported array `extern` narrowed to a
pointer; `.bss` changed to `.data` on the folded zeros; and
`__nucleus_init`'s symbol type raised from local to global.

#### TF-6 category (c), what a conversion costs at a width boundary (2026-09-10)

**5 shell functions → 16 tests**, 117 body lines retired (193 lines of the file,
including five section banners, the two `spawn` banners and five `spawn` lines):
`run_w9_as_literal_narrowing` (2), `run_w9_as_float_literal_narrowing` (2),
`run_w9_bool_unsigned` (2), `run_w9_unsigned_index` (4) and `run_w9_arg_coerce`
(6), into a new fifteenth module `tests/suite-conversions.nuc` (217 lines).
`tests/run-tests.sh` is 4,793 → 4,600 lines and 90 → 85 functions. `make test`
is 197 shell + 769 native = 966.

One question at five boundaries (Stage 15 W9 items 8, 30, 31, 32, 33): when a
value changes width or signedness, what may the compiler do silently, and what
must it emit? Items 8 and 30 settle that `as` may never be STRICTER than the
implicit coercion at the same slot — the explicit spelling of a conversion was
refusing `(as i8 5)` as lossy while `(let (a:i8 5) …)` accepted it and emitted
the very same `trunc i32 5 to i8`. Item 31 makes bool unsigned so every consumer
of `is-unsigned` agrees; item 32 widens a GEP index by its own signedness; item
33 stops a call argument that no conversion reaches from being passed untouched.

**The rule is a COMPARISON, and the shell asserted one side of it.** Items 8 and
30 are stated as "no stricter than implicit", but `run_w9_as_literal_narrowing`
only checked that the `as` spelling emits `trunc i32 5 to i8` — true of any
lowering at all, and silent on the spelling it is supposed to be compared
against. Both units now emit the implicit form beside it and require the same
instruction: `(let (a:i8 5) …)` gives the identical `trunc i32 5 to i8`, and
`(let (a:f32 1.5) …)` the identical `store float 0x3FF8000000000000` with no
`fptrunc` — so the sentence the item settled is the sentence the test reads.

**The bool gate was the g3-zero-cost shape again.** `run_w9_bool_unsigned` asked
only that no SIGNED instruction reached a bool — no `sext i1`, no `icmp s*`, no
`sitofp i1` — which a module that emitted nothing satisfies equally well. What
item 31 actually fixed is which instruction gets picked, so the unsigned ones are
now pinned by presence: `zext i1` at both widths and both values, all four
`icmp u*` orderings, `uitofp i1`, and the computed-bool `zext i1 %t… to i32`.
That is the half a run on this host cannot witness — `sext i1` and `zext i1`
differ only above bit 0, and every consumer tests `(!= x 0)`, which -1 and 1 both
satisfy, which is exactly why the defect survived every bootstrap until it was
measured on the instruction. The same absence-only shape was in
`run_w9_unsigned_index`, and the `zext i8` / `zext i16` that replaced the `sext`
are pinned beside its absence for the same reason.

**The refusing complement was already native and is left where it is.**
`w9-as-literal-too-big`, `w9-as-literal-signed-into-unsigned`,
`w9-as-float-inexact`, `-runtime` and `-global-inexact` are rows of
`tests/manifest/diagnostics.sexp`, so this module owns the accepting side and the
artifact only. The two retired `spawn` banners carried the reasoning for those
five rows — the integer pair holding the boundary at magnitude and at sign, the
float trio holding the VALUE edge, the KNOWLEDGE edge and the second asker that
re-derives — and no manifest row carried it. It moved into the manifest above
those rows rather than being deleted with the banners.

**Verified by breaking it**, sixteen ways — one per unit — each reverted by
editing the source back: six expected exit statuses moved; the two implicit-half
instructions changed to ones the compiler does not emit; a `check-not-match` on
`fptrunc` inverted; `icmp ult i1` changed to `icmp slt i1` and `zext i8` to
`zext i24` (the two presence assertions the shell did not make); `sext i32`
swapped with `zext i32` in both index units; three refusal needles changed to a
message the compiler does not print; the pinned diagnostic line moved; and one
refused call made LEGAL, which the unit reports as "expected a rejection …, but
it compiled".

#### TF-6 category (c), what a function pointer is worth (2026-09-10)

**6 shell functions → 17 tests**, 308 body lines retired (366 lines of the file,
including six section banners, three `spawn` banners and six `spawn` lines):
`run_w9_fnptr_compare` (2), `run_w9_fnptr_align` (3), `run_w9_fnptr_null_init`
(2), `run_s16_fp2_indirect_call` (4), `run_s16_fp4_cheader_fnptr` (4) and
`run_s16_fp5_cheader_fnptr` (2), into a new sixteenth module
`tests/suite-fnptr.nuc` (295 lines). `tests/run-tests.sh` is 4,600 → 4,234 lines
and 85 → 79 functions. `make test` is 180 shell + 786 native = 966.

Six claims about one value, from two stages. W9 items 18, 19 and 20 settle what a
function pointer IS to the compiler — it compares as a pointer, it occupies one
TARGET pointer's width, and `null` reaches it in every position. Stage 16 FP-2,
FP-4 and FP-5 settle what it is at the C boundary — an indirect call goes through
the same argument path as a direct one, the C importer recovers a real TY-FN from
all four declarator positions, and the export side renders a real declarator
rather than `void*`, which is not merely unchecked but not standard C.

**A skip was being reported as a pass.** `run_s16_fp5_cheader_fnptr` ends with
`echo "PASS s16-fp5-c-consumer (SKIP: no cc)"` — on a machine without a C
compiler, the unit that exists to prove the generated header satisfies a real
conforming consumer counted as green. The native suite has a third verdict, so it
is a `skip!` with a reason now, and `--no-skip` can refuse it: a release check
that cannot accept an unproven header can say so.

**Two units bundled several claims behind one `ok=` accumulator**, which is the
hand-rolled pattern `lib/test.nuc` exists to replace: whichever grep failed first
was the only one the FAIL line named, and the rest went unreported.
`s16-fp4-recovered-type-is-checked` is three separate refusals — a wrong callback
signature by name, an arity mismatch through a struct member, and a typedef'd
`s16_cmp` slot — and `s16-fp2-indirect-call-abi` is three ABI shapes. As `try`-
shaped assertions each names itself; the perturbation that moved only the MIDDLE
refusal is what shows the difference.

**Verified by breaking it**, seventeen ways — one per unit — each reverted by
editing the source back: five expected exit statuses moved; a function symbol,
an `sret` struct name, a `declare` return type and a C declarator changed to
shapes the compiler does not emit; the `align 1` invariant inverted from
`check-not-match` to `check-match`; the 32-bit target's slot width changed back
to the host's; `ret ptr null` changed to `ret ptr undef`; the vararg promotion
changed from `double` to `float`; two diagnostic needles retargeted; the C
consumer's expected answer changed by one; and `qsort` given a callback of the
wrong signature, which the silent-compile unit reports as `qsort: argument 4 has
type ():void, which does not match parameter type`.

#### TF-6 category (c), which C declaration wins (2026-09-10)

**9 shell functions → 9 tests**, 389 body lines retired (508 lines of the file,
including the per-function banners, two `spawn` section banners and nine `spawn`
lines): `run_w3a_opaque_provenance`, `run_w3a_sdl_mixer`, `run_w3b_quals`,
`run_w3b_skip`, `run_w3b_sdl`, `run_w3c_typedef`, `run_w3c_precedence`,
`run_w3c_declare_params` and `run_w3c_declare_header`, into a new seventeenth
module `tests/suite-cdecl.nuc` (297 lines). `tests/run-tests.sh` is 4,234 →
3,726 lines and 79 → 70 functions. `make test` is 171 shell + 795 native = 966.

Stage 15 W3a, W3b and W3c are one question in three parts: which C declaration
the importer believes, and which one it refuses to guess at. W3a settles that an
undefined tag is opaque and that saying so names the C header's own line. W3b
settles that a qualifier is legal in every position C allows, and that a
declaration recognized as a function but not faithfully describable is SKIPPED
with a located warning. W3c settles that a typedef resolves to what it names and
that an explicit `(declare …)` beats a header-derived one in either order.

**The one-to-one mapping is exact here** — nine functions, nine units — because
each shell function was already a single subject. What changed is inside them:
seven used `ok=1 … || ok=0` accumulators over 19, 19 and 18 `grep` rows, so a
failure named only the function, never the row. As `try`-shaped `check-line`
assertions each row names itself, and each pins a WHOLE `declare` line rather
than a substring, so a wrong parameter type fails in the row that carries it.

**Two skips were being reported as passes.** `run_w3a_sdl_mixer` and
`run_w3b_sdl` both printed `PASS … (SKIP: SDL2 not installed)`. These are the
§1.5 accept criterion — importing a real system header transitively reaching the
x86 intrinsics headers, where `void _mm_clflush(void const *)` once imported as
`declare void @_mm_clflush(void, ptr)` and killed the compilation at `failed to
parse generated IR`. A machine without SDL2 counted that as green. They are
`skip!` with a reason now, so `--no-skip` can refuse them.

**Pinning the location caught an error the shell could not have.** The
precedence conflict warning is at line 6 of the conflict fixture; I first wrote
5, copied from the sibling `w3c-prec-first` fixture, and the unit failed
immediately. The shell's `grep` carried no location at all, so it would have
accepted the same warning raised anywhere in the file. The conflicting header's
own path and line ARE host-dependent, so that message is pinned as its two
stable halves rather than as the middle.

**A pre-existing defect fixed by the deletion itself.** Lines 1474-1479 were a
Stage 13 L8 banner orphaned from `run_closure_cheader` — the W3a block had been
inserted between them, and `run_closure_cheader` had no banner of its own.
Removing the block reunites them.

**Verified by breaking it**, nine ways — one per unit — each reverted by editing
the source back. Six restore the actual pre-fix shapes: `{ i32, ptr, ptr, ptr }`
for `Mix_Chunk` (the typedef'd `Uint8`/`Uint32` fields degraded to `ptr`),
`@w3b_int_const(i32, ptr)` (the east qualifier eaten as a parameter name),
`@_mm_clflush(void, ptr)` (the IR LLVM rejects), `declare ptr @w3c_f_u8()` (every
scalar typedef resolving to `ptr`), `@lseek(i32, i64, i32)` (the header winning
over the explicit declaration) and `@w3d_bare_5(i32, i32)` (a bare parameter list
emitted as all-`i32`). The other three move the opaque-provenance line, the
by-value skip warning's line, and the matching-header `declare`.

#### TF-6 category (c), a machine that is not the host (2026-09-10)

**12 shell functions → 36 tests**, 300 body lines retired (479 lines of the
file, including the per-function banners, the nine-triple `for` loop and
seventeen `spawn` lines): `run_target_triple` (9), `run_avr_emit` (4),
`run_avr2_16bit` (4), `run_w9_gep_index_width` (3), `run_avr3_link` (2),
`run_avr5_isr`, `run_avr6_fnvalue`, `run_avr6_const`, `run_avr7_f64` (3),
`run_avr7_struct` (2), `run_riscv_emit` (2) and `check_long` (4), into
`tests/suite-target.nuc`, which grows 362 → 1,078 lines.
`tests/run-tests.sh` is 3,726 → 3,247 lines and 70 → 59 functions. `make test`
is 135 shell + 831 native = 966.

Not a new module: §T6.6's "what the target decides, not the compiler" is this
question, and `riscv-emit` and RV-6's struct ABI are plainly the same subject.
`check_long` lands here as category (a) said it would (§"TF-6 category (a) as
landed") — a target-triple ABI probe with IR greps, not a diagnostic row.

**The shell asked the module header; the header is what a broken compiler gets
right.** `run_target_triple` grepped for `target triple = "<t>"` — a string the
compiler was handed. Every defect in this lane emitted that line correctly and
then went on emitting for the host: a 64-bit GEP index on an 8-bit MCU, a Node
cell sized 40 for a 16-bit pointer, a SysV eightbyte classification on a part
with no register to hold one, soft-float libcalls against a hard-float ABI. So
each triple unit now (a) compares its datalayout against **clang's own answer
for that triple**, from the same LLVM the compiler links against, and (b)
requires the target's pointer width on **all six** GEP indices of W9 item 15's
fixture. The fixture is freestanding, so silence is a real assertion too.

**The RV-1 gate was testing llc, not the compiler.** `run_riscv_emit` passed
`llc -mattr=+m,+a,+f,+d,+c` on the command line and then asked whether the
output had a hardware `mul` — which asks whether llc can lower the IR when told
the features, not whether the features ever reached the compiler's own
TargetMachine. `riscv-llc-features` disassembles the object `nucleusc -c`
produced, and keeps the bare-RV64I llc run as the control that shows the two
answers differ at all.

**A case the shell claimed and never ran.** `run_avr7_f64`'s step 2 is commented
"`double` spelling — AVR rejects" and re-runs step 1's command on step 1's
fixture. `f64` and `double` are separate branches of one test in
`src/union-registry.nuc:368`, and the `double` branch had never been compiled
for AVR. It is a real case now, against source written into the scratch
directory rather than a new `tests/fixtures/*.nuc` (which would force an IR
snapshot re-take).

**Three assertions got stronger because the native form could carry them.**
`avr-objdump -f` reports `architecture: avr:35` for attiny1634 and `avr:103` for
the avrxmega3-family avr32dd20 — so pinning it is what says `--mmcu`, not
`--mcpu`, supplied the device name at link; the shell asked `file` whether the
ELF was "Atmel AVR 8-bit", which is the same answer for both. `avr3-link-*` pins
`data = 0` exactly rather than "under 256", which is the prelude-free floor the
fixture exists for. And `w9-gep-index-width-avr-parses` builds its own negative:
the emitted module with `, i16 %` rewritten to `, i64 %` is the historical
defect verbatim, and llvm-as must refuse it with `but expected 'i16'`.

**Two skips are now real**, in the sense that they were already conditional:
`run_avr_emit`'s llc arm and `run_avr3_link`'s toolchain arm printed nothing and
`SKIP` respectively, so the shell's PASS count varied by host with no record of
why. Every toolchain-gated unit is a `skip!` with a reason.

**Library gaps filled rather than worked around** (§T6.6's rule):
`count-matching-lines` — `check-match` answers "at least one", which cannot tell
six pointer-sized indices from one and five left behind; `check-ir-rejects`, the
complement of `check-ir-parses`; and `replace-all`, so a unit can build the
module that is wrong in exactly one respect. All three in `tests/nuctests.nuc`,
which is not an IR-snapshot input.

**Raised, not fixed:** `--target=avr` still emits `align 8` on 16-bit pointer
slots (`design/stage888-deferred.md`). It is a codegen change, and the units
that would gate it are the ones being ported here.

**Verified by breaking it**, thirty-five ways covering all thirty-six units —
the two `avr2-16bit-*` share one helper and fail together — each reverted by
editing the source back, never with git. Nine pointer widths moved off the
target's, four `long` models swapped, two `llc` triples made unresolvable, the
qq-helper's `malloc(i64 22)` restored to the host's 40, the `i64`-absence
inverted, six GEP indices asked for as five, the two link units given each
other's device family, `__vector_13` moved to 12, the fn-value diagnostic's line
moved by one, `constant` changed back to `global`, the `double` case's parameter
changed to `f32` so AVR accepts it, `float` to `double`, `mul nsw i64` to i32,
the AVR struct parameter changed to the host's `i32`, `lp64d` to `lp64`, and the
riscv multiply's operands changed by one register.

#### TF-6 category (c), what a namespace does to a name (2026-09-10)

**16 shell functions → 33 tests**, 563 body lines retired (827 lines of the
file, including the per-function banners and the twenty-one `spawn` lines):
`run_b0_import_use_flatten`, `run_b0_import_prefixed_fn` (2),
`run_b1_prefix_file_scope` (2), `run_b2a_scope_diagnostic`,
`run_b2a_import_use_binds_namespace`, `run_b2b_prefixed_values` (2),
`run_b3_two_vectors` (3), `run_b3a_ns_type_generic`,
`run_b3_ns_type_diagnostic`, `run_b4_qualified_generic` (3),
`run_b4_qualified_template`, `run_b5_protocol_kind` (3),
`run_b5_did_you_mean` (2), `run_b5_export_kinds` (3), `run_b6_dyn_cross_ns` and
`run_b7_qualified_macro` (6), into a new `tests/suite-namespaces.nuc` (776
lines). `tests/run-tests.sh` is 3,247 → 2,420 lines and 59 → 43 functions.
`make test` is 102 shell + 864 native = 966.

A new module rather than an addition to `suite-modules.nuc` or
`suite-imports.nuc`: those two ask what a *unit boundary* does to a name (the
redefinition rule) and *when* a name may be used (order and reachability). This
one asks which spellings reach which definition given a file's imports — R1,
R2 and R3 of `name-resolution.md` §8, one cell per kind of binding.

**The shell checked the note and never the diagnostic it hangs off.**
`run_b2a_scope_diagnostic` grepped stderr for `note: 'dp' is not in scope in
this file` and `In scope here: dpx.` — both notes. The error itself is
`extend: unknown protocol 'dp/Describe'` at line 25, and neither its text nor
its location was asserted at all, so any diagnostic anywhere in the run could
have supplied the notes. `check-error-at` plus `check-note-at` match one record.

**A needle that dropped the discriminating half.** `b3-two-vectors-distinct`
exists to show `va/Vector` and `vb/Vector` are two type identities, and the
shell asserted `let: init type mismatch for 'q'` — the prefix of the message
that stops one character before the type names. The full message is `value is
ptr:va/Vector, slot is vb/Vector`, and it is pinned now: the perturbation that
rewrites `slot is vb/Vector` to `slot is va/Vector` is exactly the collapse the
unit is about, and the shell's needle would not have noticed it.

**The wrong file was being blamed and nobody could see it.**
`b7-export-overload-refused` compiles a consumer, and the error is raised
against the *facade*'s `export` line (`b5-eovfac.nuc:3`), which is correct and
is the useful half — the consumer did nothing wrong. A grep over the whole
stderr blob cannot tell that from an error on the consumer.

**Three claims the comments made and the assertions did not.** Each is now
checked, and each is what separates a pair of units that otherwise agree:
`b0-prefixed-fn-namespaced` and `-plain` both return 42, and the difference
between them — `@b0ns__b0-triple` against a bare `@b0-double` — lives only in
the module; `b6-dyn-cross-ns` says the box identity is the canonical
`%__dyn.b6dp_Describe` and that the prefix spelling produced no second box
type; and `b4-qualified-template` counts **one** `@b4g__b4_twice.i32` for two
i32 call sites, which is the memo claim, and finds it under the template's
namespace rather than the call site's.

**One library gap filled**: `check-no-diag-containing`, in
`tests/nuctests.nuc`. Five of these refusals carry an anti-degradation guard —
the message must not fall back to "not defined anywhere in this compilation
unit", which for a name that is defined and reachable is false — and a
`qgrep` for its absence over stderr was the only way to write it before.

**Verified by breaking it**, thirty-three ways, one per unit, each reverted by
editing the source back, never with git. Twelve expected exit values moved by
one, two emitted symbols misspelled, one stamp count asked for as two, the box
identity asked for under the prefix spelling, four `In scope here:` lists
changed, three blamed lines moved, two suggested spellings altered, the type
mismatch's slot type collapsed onto the value's, the field owner swapped, the
overload refusal's blame moved from the facade to the consumer, and the
`binds 'zx' to` note's prefix renamed.

**Carried forward, not resolved:** the mechanical sweep of dangling `run_*`
names in `design/` now also covers `examples/w9-dyn-ns.nuc:56`, which names
`run_b6_dyn_cross_ns` in a comment. A comment-only edit to an example emits
byte-identical IR, so the sweep forces no snapshot re-take.

#### TF-6 category (c), the shape of the import graph (2026-09-10)

**6 shell functions and one shared helper → 17 tests**, 214 body lines retired
(307 lines of the file, including the per-function banners, two `spawn` section
banners and six `spawn` lines): `run_w9_root_hoist` (2), `run_w9_root_cycle_skip`
(2), `run_w9_source_outranks_header` (2), `run_w9_string_path_prescan` (3),
`run_w5e_private_isolated` (6), `run_w5e_still_rejects` (2) and
`w9_run_single_emission`, into `tests/suite-imports.nuc`, which grows 773 →
1,178 lines. `tests/run-tests.sh` is 2,420 → 2,113 lines and 43 → 37 functions.
`make test` is 85 shell + 881 native = 966.

Not a new module: §T6.6's "when a name may be used before its file is" is this
question. W9 item 1 is about the root file's membership in the graph, item 6
about a string-path import joining the same prescan, and W5e about the key a
private name gets — all three are the same walk.

**The two root-graph units asserted nothing that told them apart.** The hoist
and the ordinary cycle skip emit the SAME four definitions; the shell checked an
exit status and "no symbol defined twice", and both units satisfy both claims.
Their exit codes differ only because the two fixtures compute `2+3` and `2+4` —
arithmetic, not mechanism. What separates the paths is WHEN the root's own forms
are written: a hoisted root is emitted at the re-entry, so `main` precedes the
library's `lib-fn`; a shut window takes the skip, so `lib-fn` precedes `main`.
`check-order` pins it, and swapping the two arguments is what the perturbation
does — each unit then fails, which is the proof the old pair could not offer.

**The duplicate check was a pipeline that had to be guarded against its own
success.** `w9_run_single_emission` greps `define` lines, sorts and takes
`uniq -d`, with `|| true` on each pipeline — and the shell's own comment records
why: under `set -euo pipefail` a grep that matches nothing exits 1, "which would
kill the unit mid-way and lose its second PASS line silently (the harness only
flags a result file that is entirely empty)". The native form is
`duplicate-define-name`, which already existed and is used by `w1-diamond` and
`w1-two-routes` a few hundred lines above in the same file, plus a presence
anchor so an empty module cannot satisfy a duplicate check.

**Two refusals could not tell which file was blamed.** `w5e-public-collision-
rejected` and `w5e-ns-private-collision-rejected` grepped the whole stderr blob
for the two file paths independently, so a diagnostic blaming either file passed.
The compiler blames the SECOND file at its own line and names the first inside
the message; both are pinned as one record now, with the note that states the
rule — which is the only thing distinguishing the public refusal from the
namespace-private one, since the heads are identical in shape.

**Library gap filled**: `check-order`, in `tests/nuctests.nuc`.

**Verified by breaking it**, seventeen ways, one per unit, each reverted by
editing the source back, never with git. Nine expected exit values moved by one,
the two emission orders swapped, an emitted symbol misspelled, a suggested
spelling changed, an `import: cannot find` head reworded, and the two collision
messages pointed at the blamed file instead of the earlier one.

#### TF-6 category (c), what a prefix must not change (2026-09-10)

**3 shell functions → 12 tests**, 192 body lines retired (234 lines of the file,
including the per-function banners and three `spawn` lines):
`run_w9_bare_ref_prefix` (5), `run_w9_template_env` (3) and
`run_w9_dyn_solitary` (4), into `tests/suite-namespaces.nuc`, which grows 776 →
1,067 lines. `tests/run-tests.sh` is 2,113 → 1,879 lines and 37 → 34 functions.
`make test` is 73 shell + 893 native = 966.

Not a new module: these are W9 items 41 and 43, and all three are the same
question §T6.6's namespace suite already asks — which spellings reach which
definition. Item 43 is the bare half of the rule B4 implemented for the
qualified half, and item 41 is a protocol method's slot reached through a
qualifier.

**A purely negative assertion, in a function that knew better.**
`w9-dyn-solitary-dispatches-indirectly` asserted only that no direct call to
`add-k` or `name-of` appears — which an empty module satisfies. Twenty lines
below it, the sibling unit `w9-dyn-solitary-qualified-reaches-slot` carries the
comment "An empty module would pass a purely negative assertion, so require the
indirect call to be there as well as the direct one to be gone", and does. The
hazard was known and applied to one of the two. The native unit requires the
three boxed dispatches by COUNT before refusing the direct ones.

**Three substrings, one diagnostic never established.**
`w9-template-error-blames-library` grepped stderr for a location, a message
fragment and the words "while instantiating", with nothing tying them to one
record — and never checked the `requested at <caller>:2` half at all, which is
the only part naming the instantiation site and the entire reason the note
exists. That is what makes the error usable: the blamed line is the library's,
so without it the reader has no way back to the call that asked. Pinned as one
record now, note included.

**A `mv` replaced by the mechanism that exists for it.** The `.nuch`
separate-compilation unit moved the library source aside mid-test so
`resolve-import` could not prefer it over the header. `test-scratch-sub` exists
for exactly this — its own comment says so — so the source sits in `l/`, the
header in `h/`, and only `h/` is a search directory for the consumer.

**Verified by breaking it**, twelve ways, one per unit, each reverted by editing
the source back, never with git. Six expected values moved — one of them to
103, which is the defect itself, a bare call reaching the prefixed library — the
emitted call's operand width changed to the library's, the template error's
blame moved to the caller, the boxed-dispatch count asked for as four, the
direct-call refusal inverted, and the printed answer changed by one.

#### TF-6 category (c), what a literal element and a selector may be (2026-09-10)

**3 shell functions → 16 tests**, 204 lines of the file retired (including the
per-function banners and three `spawn` lines): `run_s16_keyword_literal_refused`
(10), `run_s16_symbol_values` (4) and `run_s16_selector_rule` (2), into
`tests/suite-s16.nuc`, which grows 2,049 → 2,276 lines. `tests/run-tests.sh` is
1,879 → 1,675 lines and 34 → 31 functions. `make test` is 57 shell + 909
native = 966.

No new module: `suite-s16.nuc` already owns what a place is, and a selector is
a place's field name. The literal half belongs beside it because the refusals
are the same shape — a form that looks like data and is resolved as a type or a
variable.

**Nine claims under two verdicts.** `run_s16_selector_rule` is the
`ok=1 … || ok=0` accumulator pattern again: two `echo PASS` lines cover a
runtime output comparison, a bare-symbol diagnostic, three fixed-position forms
and a non-symbol selector. Any one of the nine failing lost the same single
verdict, so the report could not say which. Six units now, one claim each.

**The same needle for three different diagnostics.** The three fixed-position
forms were checked with one identical string,
`field name must be a quoted selector -- write 'x`. The compiler prefixes each
with its own form — `.set!:`, `addr-of:`, `_get:` — and the whole point of
those forms sharing a rule is that the reader is told which one they hit; three
diagnostics all saying `.set!` would have passed. Each is pinned with its
prefix now.

**A needle that stopped before the discriminating half.** The mixed-literal
refusals grepped for `set literal: mixed element types`, which cannot tell one
mixture from another. Three of the five messages go on to name the two
conflicting types (`-- 'Keyword' and 'StrView'`) and two do not; the three are
pinned in full and the two are recorded in `design/stage888-deferred.md`, so
the inconsistency has somewhere to land rather than being frozen by a needle
that never looked.

**A blob grep over a ten-line preamble.** Every refusal here compiled a source
with a ten- or eight-line import header and grepped the whole stderr; a
diagnostic raised anywhere in the preamble satisfied it. All sixteen pin the
line. `s16-kwlit-missing-import-names-file` was two independent greps — the
head and the path `lib/keyword.nuc` — which a note belonging to some other
diagnostic satisfied; it is one record with its note now.

**Verified by breaking it**, sixteen ways, one per unit, each reverted by
editing the source back, never with git. Five mixed-literal messages reworded,
four element-refusal heads changed, the intern call misspelled, the quoted-list
nullability refusal inverted, the printed field values changed, and the four
selector prefixes swapped between forms. The nullable-slot unit needed its
SLOT retyped rather than its datum — `(quote 1)` is also `(raw Node)`, so
changing the datum asserted nothing; `(raw Node)` → `(raw i32)` is what
contradicts the claim.

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

**T9.7 Top-level macro expansion before the pre-scans.** TF-4 added expansion in
the dispatch loop, which is enough for `deftest` and for any macro that defines
things nothing else forward-references. Moving it ahead of the pre-scans would
make a macro-produced `defn` visible file-wide and let a macro produce an
`extend` with its methods — but it requires `defmacro` bodies, and the imports
they resolve against, to be processed before any other top-level form. That is a
front-end staging change, and nothing in the suite needs it.
