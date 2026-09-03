# Stage 18 — tooling

Two pieces of work on how the compiler is *used* and how it is *checked*, rather
than on what it compiles.

| Piece | Sections | State |
| --- | --- | --- |
| Restoring the REPL introspection layer | §1–§5 | **Done 2026-09-03** (R0–R7) |
| A native test framework | §T1–§T7 | **Options only — undecided** |

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

**Status: options, not a plan.** Nothing here is decided. §T1–§T3 are
measurements taken against the tree on 2026-09-03; §T4 sets out six options
against those measurements; §T5 recommends one and says why the other five lose.
A decision turns §T5 into phases.

**Goal, stated as a question.** Testing Nucleus is 15,895 lines of shell and
Python. The compiler is self-hosted and the language now has strings,
collections, iterators, error handling and namespaces — so how much of that
15,895 should be Nucleus, and what is the honest cost of moving it?

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
runner cannot assume exists.** §T6 argues those 1,558 lines should stay shell
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
  292 heredocs (32%) contain a `"`, which matters for §T7's embed-or-file
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
   amount of engineering recovers, and it caps how much may move. §T5 answers it
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

## T3. What the runtime is missing today

Verified by grep across `lib/` (40 modules) and `src/`:

- **No process API anywhere in `lib/`.** `popen`/`pclose` exist only as raw
  declares in `src/cheader.nuc:15-16`, feeding `read-pipe-output`; `system` is
  called at two sites. There is no `fork`, `execv`, `posix_spawn` or `waitpid`
  in the tree. **This is the blocking gap** — everything in §T4 except option E
  needs it.
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

**One thing got cheaper this stage.** Stage 17's C-macro constant import
(`80d0f61`) means `O_*`, `S_*`, `WNOHANG` and friends now come from the real
headers on the host. A `lib/process.nuc` and `lib/fs.nuc` written today need no
hardcoded per-OS constant table — which was the ugliest part of the cost a week
ago, and is now zero.

## T4. The options

### A. Leave it in shell
**Buys:** nothing new; keeps property T2.1 for free.
**Costs:** the status quo — 14,337 lines nobody wants to edit, a `qgrep` whose
header comment documents a 186-in-200 SIGPIPE race that had to be discovered
empirically, and no dogfooding of the language on its own largest tool.
**Verdict:** the baseline every other option must beat, not a straw man.

### B. Extract the declarative tests to manifests, keep bash
Move the reject/accept/example/repl tables into data files; keep the shell.
**Costs:** essentially none.
**Buys:** essentially nothing. §T1.1 measured it: those ~350 tests already cost
under 200 lines. Removing them removes ~1.4% of the file and leaves all 10,400
lines of bespoke unit exactly where they are.
**Verdict:** rejected on measurement. This is the option that *looks* like
progress.

### C. Full native runner
`lib/process.nuc` + `lib/fs.nuc` + `lib/test.nuc` + `tests/runner.nuc`, with all
176 units ported to Nucleus.
**Buys:** the whole 14,337 lines become Nucleus. Assertions operate on typed
values instead of on the text of someone else's stdout. It is by a wide margin
the largest Nucleus program that is not the compiler, so it exercises the
library the way the stage-17 sweep exercised strings.
**Costs:** three new lib modules (~600–900 lines), a runner (~400), and a
port of 10,632 lines of body logic — the last being the real number, and it is
not mechanical.
**Cannot:** satisfy T2.1 alone.
**Verdict:** the right destination, the wrong first step.

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
**Verdict:** a genuinely attractive *separate track* for the emit-and-inspect
units, viable only once something else can cross-check it. Not a replacement.

### F. Staged hybrid — replace the harness, keep the bodies
A native runner owns dispatch, the job pool, scratch directories, output
buffering, ordered replay and the summary. Each unit body stays a shell snippet,
invoked through one `sh -c`. Bodies then migrate to Nucleus by category,
independently.
**Buys:** needs only process-spawn and wait — not the filesystem surface, not the
matcher — so it lands on the smallest possible slice of §T3. Every subsequent
migration is incremental and separately verifiable, and the runner is exercised
by the full suite from day one.
**Costs:** the shell doesn't shrink until phase two; for a while there are two
things to understand instead of one.
**Verdict:** the first step option C needs.

## T5. Recommendation

**F, then C, with E as a separate track and a permanent shell trust anchor.**
Ordered so that each step is gated by the step before it:

1. **F1 — `lib/process.nuc` and a native dispatcher.** Spawn, wait, capture
   stdout/stderr; a bounded job pool; per-unit result buffering; replay in
   dispatch order. Bodies still run as `sh -c`.
   *Gate:* on a green tree, the native runner's output is **byte-identical** to
   `run-tests.sh`'s. §T2.3 makes this checkable, which is why it comes first.
2. **F2 — `lib/fs.nuc`.** `mkdtemp`, `mkdir`, `unlink`, `rmdir`, `readdir`.
   Per §T3 this needs no constant table now. Retires the 168 `mktemp` calls and
   lets the runner own scratch-directory lifetime instead of each unit.
3. **C1 — `lib/test.nuc`.** The six predicates of §T1.2 and nothing else, with
   the matcher a wildcard glob rather than a regex engine (§T1.2's 76 patterns
   need `*`, anchors and alternation). Failure rendering lives here, so §T2.4 is
   one implementation instead of 599.
4. **C2 — migrate bodies by category, highest reuse first:** the 172
   reject/accept spawns (option D's manifest is right *here*), then the 177
   example and REPL units, then the bespoke units in descending size — the seven
   largest are over 200 lines each.
5. **E — separate track, after F1.** Convert only the pure
   emit-and-inspect-IR units, and only while the C2 versions still exist to
   cross-check against. The order matters: E's contamination hazard is invisible
   without a second implementation to disagree with it.
6. **Permanent — the trust anchor.** A short shell script that compiles one
   program, runs it, and diffs the output, run *before* the native runner. It is
   the answer to §T2.1: when the compiler is broken badly enough that the native
   runner will not build, something that does not depend on the compiler has
   already said so. Keeping it is not a hedge; it is the reason the rest is
   allowed to move.

The dependency worth stating plainly: **steps 1–4 are all downstream of
`lib/process.nuc`.** Nothing about a native test framework is possible until
Nucleus can start a process and wait for it, and today it cannot.

## T6. What stays outside the framework regardless

1,558 lines of shell and Python, for reasons that are not inertia:

- **The trust anchor** (§T5.6) — by construction.
- **`run-avr-test.sh`, `run-riscv-test.sh`, `run-riscv-abi-test.sh`,
  `run-abi-test.sh`, `run-layout-test.sh`** — they gate on external toolchains,
  run outside `make test`, and their assertion *is* an external tool's output.
  Rewriting them buys a different spelling of the same `spawn`.
- **`resolution-matrix.sh`** — its own header says it is a recorder, not a test.
- **`check-headers.sh`, `check-cstr.py`, `gen-stdlib-table.py`** — source-tree
  audits and a generator. Not tests, and not this stage's problem.

## T7. Open decisions

1. **Where does the runner live?** Its own `build/` binary, or a `nucleusc
   --test` mode? A separate binary keeps the compiler's surface clean and makes
   the T2.1 dependency explicit; a mode shares the reader for free.
2. **Fixtures: embed or file?** Nucleus string literals span raw newlines
   (verified), so embedding works — except that 93 of the 292 heredocs contain a
   `"` and would need escaping, and escaped Nucleus inside Nucleus is unreadable.
   Recommend moving the 588 inline fixtures onto disk beside the existing 223.
3. **Glob or regex for `matches`?** §T1.2 says glob suffices for all 76 sites.
   Regex is more general and is a much larger thing to own.
4. **Is order-independence a stated property or a hope?** If E is ever adopted
   the answer must be "stated", which means the runner shuffles dispatch order
   under a flag and the suite still passes. Cheap to build in at F1; expensive to
   retrofit.
5. **Does `make test` become the native runner, or gain it alongside?** Running
   both until C2 completes doubles the 59s. Running only the native one loses the
   cross-check that makes the migration safe.
