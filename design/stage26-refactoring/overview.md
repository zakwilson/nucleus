# Stage 26 — Nucleus refactors Nucleus

**Status: designed 2026-10-15; Q1–Q8 ruled 2026-10-15 (§7). RF-0 and RF-1 built 2026-10-15; RF-2 … RF-8 built 2026-10-16 (§8). Stage complete pending the user's review. Open: RF-6's one IR-snapshot difference (deviation 1) and RF-7's resolution questions.**
Measured against `0653a19`.

## 1. The brief

Agents keep writing Python scripts to refactor Nucleus. Nucleus is
homoiconic, so it should be the best tool for rewriting its own source:
match forms and symbols, not text. This stage finds what stops it and plans
the fixes.

**The goal:** the next sweep like the ones in §2 is a Nucleus program, no
longer than the Python version would have been. It reads source with the
real reader and passes the same gates.

**Out of scope:** a formatter (§4.1 makes one possible), an LSP, and
cross-file rename until RF-7 lands. **The target is Nucleus source and
headers (`.nuc`, `.nuch`) only.** Documentation is Markdown, not Nucleus or
EDN, and editing it with whatever tool fits is fine.

## 2. The evidence: what the Python scripts did

| Script | Lines | Job | What it needed that Nucleus lacks |
|---|---|---|---|
| `scripts/stage17/rewrite-fmt.py` | 326 | Stage 17 C1: 636 `fmt-*` sites → `fstr`, `fprintf` → `eprint`/`emit` | Bracket-aware splitting that also understands strings; leaves untouched text alone; a refusal list; "run it to a fixed point", because a nested call is consumed as text |
| `scripts/stage21/sugar-sweep.py` | 739 | Stage 21 PK-5a, rules R1–R8: adopt `&`/`?`/`!` sugar | Telling `(ref X)` from `&X`; knowing which operand positions are types; quote/quasiquote/unquote context; refusing any form with a comment inside it |
| `scripts/stage21/list-api-sweep.py` | 282 | Stage 21 item 6: `'car`/`'cdr`/`make-cell` → node API | "Span-preserving — untouched text stays byte-identical"; arguments spliced back in as their original text; refusing `set!` of a cell |
| `scripts/stage21/ptr-sweep.py` | 142 | Stage 21 item 7 BP-2: `ptr:T` chain segment → `&T` | Chain segments *inside* an atom; programs embedded in test string literals (`--in-strings`) |
| `scripts/stage21/raw-sweep.py` | 77 | BP-4: `raw` → `ptr` | Same as ptr-sweep, plus rewriting comments |
| `design/stage20-macros/census.py`, `nested-qq-scan.py` | 229 | Stage 20 analysis | Reading without desugaring: "reader macros stay as atoms" |

The non-rewriting checkers (`check-cstr.py`, `check-repl-roster.py`,
`gen-stdlib-table.py`) would also benefit, but they are not the target.

Every rewriter built its own reader, its own string/comment splitter and its
own dry-run, histogram and refusal machinery. Three rules recur across them,
and the design keeps all three:

1. **Untouched text stays byte-identical.**
2. **Refuse, never guess.** A shape no rule covers is reported, and the
   refusal list is part of the output.
3. **Dry run first.**

## 3. Ground truth (verified 2026-10-15)

### 3.1 What a `Node` can record

`Node` (`lib/nucleus/core.nuc:31`) is `kind line i s elems len cap`. Every
`Reader` tracks a byte offset (`pos`), but `rd-node` never stores it. A node
has a line number at most: no column, no start, no end.

**Symbols have no per-occurrence node.** `rd-atom` returns
`(intern-node (rd-expand-sigil tv))` (`lib/nucleus/read.nuc:664`), so every
occurrence of `foo` in a program shares one `Node`. The comment there says it
directly: symbols "carry no per-occurrence line". A source position therefore
cannot be stored on a symbol node. Of all the facts here, this one shapes the
design most (§4.1). List, integer, string, char and keyword nodes are
allocated fresh for each occurrence.

### 3.2 What the reader discards or rewrites

| Source | Reader output | Where | Lost |
|---|---|---|---|
| whitespace, `,`, `; comment` | skipped | `rd-skip-ws` :235 | all of it |
| `#_ form` | read and dropped | `rd-skip-discard` :839 | the form |
| `'x` `` `x `` `~x` `~@x` `@x` `&x` | `(quote x)` … `(ref x)` | macro table :114, `rd-form` :980 | the prefix spelling: `&x` and `(ref x)` read identically |
| `x:&T` (mid-atom `&`) | the symbol `x:ref:T` | `rd-expand-sigil` :395 | the `&` spelling |
| `name:(T)`, `f:(fn i32)(i32)` | `(name (T))`, `(f ((fn i32) (i32)))` | `rd-fuse-colon-paren` :774, `rd-fuse-fn-params` :753 | two source forms become one tree |
| `0x1F` | `NODE-INT` 31 | `rd-int-node` :598 | radix and digits (float text **is** kept) |
| `"a\n\""` | decoded bytes | `rd-string` :466 | the escape spellings, and therefore the offsets inside the literal |
| `[a b]` `{…}` `#{…}` | `(vector-lit a b)` …, marked in `i` | `rd-lit-cell` :889 | nothing, because the mark survives |

`node-write` (:1113) prints canonical text on one line. `dump-ast-corpus.sh`
(`scripts/stage21/`) round-trips the **tree** (read → print → read), not the
text.

### 3.3 What a form position means is compiler knowledge

The chain splitter is `split-colon-segments` (`src/nucleusc.nuc:19148`). It
runs in `desugar`, after sigil expansion, so it never sees `&`. The reader's
colon-paren fuse has a second splitter of its own. Which operand of `defn`,
`let`, `defstruct` and so on is a binding name or a type is spread through
`desugar-form` (:19265) and `node-type`/`emit-node`. `sugar-sweep.py` rebuilt
that table by hand, because nothing in `lib/` exposes it.
[../deferred/compiler-api-surface.md](../deferred/compiler-api-surface.md)
covers the general problem of reaching compiler internals from a library.

### 3.4 What a throwaway script costs today

- **No way to run a file.** `-i` is the only mode that doesn't link a binary
  (`src/nucleusc.nuc:22361`). A tool means compile, link and run, or piping
  the file into the REPL.
- **No regex.** Glob matching exists but is private to the test framework
  (`glob-match`, `lib/nucleus/test.nuc:151`). `read-dir` lists one directory
  level only.
- **No argument parsing.** `test-main` (`lib/nucleus/test.nuc:689`) walks
  `argv` by hand.
- **No pattern matching over forms.** `match` works on unions. A form test is
  hand-written `node-kind`/`node-len`/symbol comparisons.

## 4. Design

### 4.1 A syntax tree read by the one reader

Stage 21 item 2 settled that there is one reader. So a lossless tree is a
**mode** of `lib/nucleus/read.nuc`, as EDN is, not a second parser. In this
mode the reader also builds a source-shaped `Syn` tree. It is arena-allocated
like `Node`, and each `Syn` points at the `Node` the ordinary read produced
for its span:

```lisp
(defenum SynKind SYN-ATOM SYN-STR SYN-CHAR SYN-LIST SYN-VEC SYN-MAP SYN-SET
                 SYN-PREFIX SYN-TAGGED SYN-FUSE)

(defstruct Syn
  kind:i32
  start:usize end:usize   ; byte span; surrounding whitespace and comments excluded
  line:i32 col:i32
  node:?&Node             ; what read-one returns for this span
  parent:?&Syn
  kids:…)                 ; source-shaped children, stored as Node stores elems

(defstruct SynFile
  src:StrView
  forms:…                 ; top-level &Syn
  comments:…              ; spans of every `;` comment
  discards:…)             ; spans of every `#_ form`, the `#_` included
```

`(read-syntax-all src)` returns a `SynFile` or the reader's `ReadError`.

**Whitespace and comments need no tree representation.** The source is kept,
and every edit (§4.3) replaces a span. Whatever lies between spans is
whitespace or comments, and it survives because nothing touches it. The
`comments` and `discards` lists exist so a tool can ask "is there a comment
inside this form?", which is `sugar-sweep.py`'s refusal, and so a later
formatter has what it needs.

**How it is built.** `rd-form` opens a frame after `rd-skip-discard` and
closes it on return, recording `start`/`end` and attaching the frame to its
parent. In syntax mode, `rd-skip-ws` and `rd-skip-discard` record their
spans. When the mode is off, the cost is one test of a reader field per form,
and the gate measures it (§6).

**How `Syn` children line up with `Node` children:**

| Source | `Syn` | `Syn.node` and the index rule |
|---|---|---|
| `(a b)` | `SYN-LIST`, kids `a b` | `(a b)`; kid *i* ↔ elem *i* |
| `[a b]` | `SYN-VEC`, kids `a b` | `(vector-lit a b)`; kid *i* ↔ elem *i+1* (same for map, set, tagged) |
| `'x`, `&x`, … | `SYN-PREFIX`, kid `x`; prefix text = the `open` bytes from `start` (§8 RF-1) | `(quote x)`; kid 0 ↔ elem 1 |
| `x:(T)` | `SYN-FUSE`, kids `x:` (atom) and `(T)` (list) | `(x (T))`; elem 0 has no span of its own |
| `x:&T`, `0x1F` | `SYN-ATOM`; raw text is the span | the interned symbol `x:ref:T`; `NODE-INT` 31 |
| `"a\n"` | `SYN-STR` | the decoded `NODE-STR` |

A symbol's position lives on its `Syn`, never on the shared `Node`, so
interning is untouched.

### 4.2 Chain segments as data

`(chain-segments text)` splits a raw atom (`x:ptr:T`, `?&Node`, `x:&(…`)
into segments. Each segment carries its span within the atom and its sigil
run. It runs the reader's segment state machine (`rd-seg-next`), and RF-2
makes **one splitter**: `split-colon-segments` and the colon-paren fuse both
call it. A rewrite like `ptr:` → `&` becomes a span edit on a segment instead
of a regex.

### 4.3 Edits

```lisp
(edits-new):Edits
(edit-replace e:&Edits s:&Syn text:StrView)
(edit-span e:&Edits start:usize end:usize text:StrView)
(edits-apply src:StrView e:&Edits):!String   ; refuses overlapping edits, naming both
```

This is the low-level layer, and everything else is built on it.

### 4.4 Rewrite rules

```lisp
(defrewrite list-api
  (rule (~x 'car)              `(node-first ~x))
  (rule (~x 'cdr)              `(node-rest ~x))
  (rule (make-cell ~a null ~l) `(node-list1 ~a ~l))
  (rule (make-cell ~a (make-cell ~b null ~l2) ~l)
        `(node-list2 ~a ~b ~l)
        :when (same-text? l l2))
  (rule (set! (~x 'car) ~v) :refuse "builds a list in place; convert by hand"))
```

- **A rule is `(rule PATTERN TEMPLATE [:when GUARD])`** or
  `(rule PATTERN :refuse REASON [:when GUARD])`. The positions are fixed and
  the options are keyword markers, as with `:rest`/`:optional`. There is no
  infix separator. Rules are tried in order, and the first match wins.
- **Holes use quasiquote spelling.** In a pattern, `~x` binds one form and
  `~@xs` binds the rest of a list. Every other symbol matches by interned
  identity.
- **A template is a quasiquote.** The reader reads it when the tool
  compiles, so a malformed template is a compile error. A template that
  unquotes a name the pattern never bound is refused when `defrewrite`
  expands. `~x` splices a hole. Any other unquoted expression is evaluated
  and must yield a `Node`, which is printed (§4.4.1).
- **Patterns match the tree as read, not the source spelling.** The pattern
  is itself read by the reader, so `&x` and `(ref x)` in a pattern are the
  same `Node`. A pattern can't express that difference, and pretending it
  could would be a trap. Spelling is tested explicitly in a guard, where a
  hole's name is a plain variable bound to its `Syn`: `(spelled? x "&")`,
  `(prefix-form? self)`, `(chain-segments x)`. R3,
  "`(ref X)` → `&X`, but not when it is already `&X`", is a guard, not a
  pattern.
- **A hole binds a `Syn`.** It is spliced back as that subtree's
  **already-rewritten source text**, comments and layout included. A hole
  whose node has no span of its own (`SYN-FUSE` elem 0) is refused if a
  template uses it. In v1, a hole whose text spans several lines is refused
  unless the rule says `:multiline`. Its own line breaks survive, but its
  indentation was written for its old position. Re-indenting it is a
  formatter's job, which is out of scope (§1).
- **Rules apply bottom-up in one pass.** A subtree's text is computed before
  its parent's, so nested matches compose. `rewrite-fmt.py`'s
  run-to-fixed-point note no longer applies, and two edits from one rule set
  can't overlap.
- **Context guards:** `(in-quote? self)`, `(in-quasiquote? self)`,
  `(in-unquote? self)`, `(has-comment? self)`, `(slot-kind self)` (RF-6).

`defrewrite` expands to a matcher function per rule plus a table. It is an
ordinary macro over `Node`, written against the `ast-*` forms.

> **As built (RF-3b, 2026-10-16):** v1 templates unquote holes only, and
> computed text goes through a new `:emit` rule kind. `:reindent` and
> `:flag` were added, and edits nest. See §8 RF-3b, "Deviations".

#### 4.4.1 Printing a template in the preferred spelling

A template has been read, so its spelling is gone: `&~x` and `(ref ~x)` are
the same tree. `node-write` would print the long form for both. Template
output instead goes through `node-write-sugared`, which prints each form in
its **preferred spelling**: `(ref X)` as `&X`, `(quote x)` as `'x`, the
other reader macros likewise, and the colon-chain and `?`/`!` type sugar
where the form is a type. Output follows house style, whatever the rule
author typed.

**A sugared spelling is used only if it reads back to the same tree.**
Otherwise the printer falls back to the long form. This case is real:
`(ref rest)` printed as `&rest` reads back as the retired `&rest` marker,
which `rd-legacy-marker?` (`lib/nucleus/read.nuc:390`) deliberately leaves
as a symbol. The check is a re-read plus `node-eq` on the printed fragment,
which is affordable in a tool and needs no list of exceptions to keep up to
date.

The same printer serves `macroexpand` output and a later formatter.
`node-write` stays canonical, because the corpus gate and `--dump-ast`
depend on its output.

### 4.5 Driver and running a tool

`lib/nucleus/refactor.nuc` provides `(refactor-main argc argv rules)`. That
covers the shared skeleton every script rewrote:

- `--dry-run` is the default. It prints a per-rule histogram, the refusals
  (`file:line:col: rule: reason`) and the files that would change.
  `--apply` rewrites in place.
- File, directory and glob arguments use a recursive walk, with
  `glob-match` moved from `lib/nucleus/test.nuc` into
  `lib/nucleus/file.nuc` (Q8).
- `--in-strings` applies the rules to programs inside string literals (§4.6).
- Exit status is nonzero when there are refusals under `--strict`.

`nucleusc --run tool.nuc -- args…` compiles the unit into the JIT and calls
`main`, with no link step. The REPL already JITs imported libraries and
calls into them, so this should be mostly plumbing. RF-4 first measures
startup (Q4).

### 4.6 Programs inside string literals

`(syn-string-source s)` takes a `SYN-STR` and returns its decoded text plus
an offset map from decoded to raw bytes. Rules run over that text with the
same reader. Edits are mapped back through the map, and inserted text is
re-escaped (`"` becomes `\"`). A string that does not read as a program is
skipped and counted, not refused.

### 4.7 What positions mean: from the compiler

**RF-6 is syntactic and comes first.** The operand roles of each built-in
form (binder list, parameter list, return type, type operand, body, name)
move out of `desugar-form` into a table in `lib/`. `desugar` consumes that
table, so there is one source of truth, and the change is gated
byte-identical. `(slot-kind s)` reads the same table. A call to a user macro
has unknown operand roles, so it is `SLOT-UNKNOWN`, and a rule that needs a
slot refuses there.

**RF-7 is resolution, and it starts as an investigation.** The question is
what each symbol occurrence resolves to (namespace, shadowing, hygiene tag).
One opening: list nodes are per occurrence, so the compiler could report an
occurrence as (list node, index), and a table from list `Node` to `Syn`,
built during the syntax read, maps that back to a span. Two things make it
harder:

- `desugar` and macroexpansion rebuild lists, which loses that identity.
- Exposing the answer touches
  [compiler-api-surface.md](../deferred/compiler-api-surface.md).

The deliverable is a findings section here, not code.

### 4.8 Bootstrap

A migration that changes the reader can stop the tool's own source from
compiling midway. Build the tool **before** the breaking change and keep the
binary. This is what Python gave for free. Rules that match on spelling
guards are unaffected by a change in what the reader produces. RF-8
documents this in `context/build.md`.

## 5. Phases

| Phase | Work | Gate |
|---|---|---|
| RF-0 | Replay harness: run a Python script and its Nucleus port over the same tree and compare | harness reports identical files and the same refusal set |
| RF-1 | Syntax mode: `Syn`, `SynFile`, comment and discard spans (§4.1) | §6.1; bootstrap byte-identical; ordinary read time within noise |
| RF-2 | `chain-segments`; one splitter for reader, desugar and tools (§4.2) | bootstrap byte-identical; IR snapshot unchanged |
| RF-3 | Edits, `defrewrite`, `node-write-sugared`, driver, dir walk and glob (§4.3–4.5) | §6.1's printer check; port `list-api-sweep.py`; replay identical |
| RF-4 | `nucleusc --run` | startup measured; unit test |
| RF-5 | Programs inside strings (§4.6) | port `ptr-sweep.py` with `--in-strings`; replay identical |
| RF-6 | Shared slot table; `slot-kind` (§4.7) | bootstrap byte-identical; port R3–R5 of `sugar-sweep.py`; replay identical, refusals included |
| RF-7 | Resolution investigation (§4.7) | findings written here |
| RF-8 | `docs/refactoring.md`; `context/refactoring.md` and its line in `AGENTS.md` (Q7); bootstrap note in `context/build.md` | — |

## 6. Gates

### 6.1 The syntax-mode corpus gate

This extends `dump-ast-corpus.sh`. For every corpus input:

- `read-syntax-all` succeeds exactly when `read-all` succeeds.
- Each `Syn.node` is `node-eq` to what the ordinary read produced.
- Spans nest and are ordered, and every byte of the source is inside exactly
  one of: a span, a comment, a discard, or whitespace.
- Applying no edits reproduces the input byte for byte.
- From RF-3: `node-write-sugared` of every form reads back `node-eq` to it.

### 6.2 Replay

A ported tool is accepted when, run on the tree its Python original ran on
(the parent of the commit that added the script), it writes the same files
and refuses the same sites. Refusal wording may differ. It must also be no
longer than the script it replaces. Which scripts get ported is decided by
Q6: only those that test a capability of the library.

### 6.3 The standing gates

`make bootstrap` byte-identical (a reader mode that is not armed must be
inert), `make test`, and `ir-snapshot.sh verify`.

## 7. Rulings (2026-10-15)

All eight were ruled on 2026-10-15. Each answer is recorded with the reason
or condition attached to it.

**Q1 — Where do spans live?** In a **mode** of the one reader that builds
the `Syn` tree (§4.1). `Node` is untouched, as is every `.nuch` that names
it. Rejected: `start`/`end` fields on `Node`, which would need per-occurrence
symbol nodes, an audit of pointer comparisons on symbol nodes, and a bigger
`Node`. Also rejected: a side table keyed by list `Node`, whose identity
breaks when a tool rebuilds a list.

**Q2 — Read tree or source spelling?** The **read tree, with spelling
guards** (§4.4). A pattern goes through the same reader, so it cannot carry
spelling.

**Q3 — Templates?** **Quasiquote**, printed by `node-write-sugared` with the
read-back fallback (§4.4.1). String templates were the first draft and were
dropped: they had no read-time check, holes were found by scanning text, and
a literal `~` was ambiguous. The accepted cost is that the author cannot
pick the output spelling: `(ref ~x)` prints as `&x`. A long-form escape such
as `(:long ~form)` can be added if it is ever needed.

**Q4 — How does a tool run?** **`nucleusc --run`**, ruled as "good for now".
A Makefile rule that builds `build/tools/X` is the alternative to revisit if
it stops being good enough.

**Q5 — Where do tools live?** One-off tools go in `scripts/stageN/*.nuc`.
The library is `lib/nucleus/refactor.nuc`.

**Q6 — Python scripts.** A script is deleted once its Nucleus port passes
replay (§6.2); git keeps the history. **A script is not ported without
cause.** One is ported when it is a good test of the refactor library's
capabilities. That is the role of the three ports in §5: `list-api-sweep.py`
tests spans, holes and templates (RF-3); `ptr-sweep.py` tests chain segments
and programs inside strings (RF-5); R3–R5 of `sugar-sweep.py` test
`slot-kind` and the spelling guards (RF-6). Ports of only part of
`sugar-sweep.py` do not delete it. No other script is ported unless a new
capability needs a test.

**Q7 — Agent guidance.** Add `context/refactoring.md`: when to reach for
`defrewrite`, a worked example, and the refusal discipline. **It recommends
the library only for rewriting `.nuc` and `.nuch` files** (ruled
2026-10-15), never Markdown, EDN or other text. Note it in
`AGENTS.md`'s context list (`CLAUDE.md` is a symlink to it). Both land in
RF-8, once there is a library to point to. Until then, the file would send
agents to tools that do not exist yet.

**Q8 — Glob and directory walking.** Move `glob-match` from
`lib/nucleus/test.nuc` into `lib/nucleus/file.nuc`, and add a recursive walk
there. The test framework imports it from its new home. This is part of
RF-3.

## 8. As built

### RF-0 — replay harness (built 2026-10-15)

`scripts/stage26/replay.sh` exports a revision twice with `git archive`,
runs side A in one export and side B in the other over the same files, and
compares the written files byte for byte and the refusal sites as
`path:line` (wording ignored).
Options: `--rev`, `--files`, `--exclude`, `--a`, `--b`, and `--refusals`
(or `--refusals-a`/`--refusals-b`) naming an extractor: `list-api-sweep`,
`ptr-sweep`, `sugar-sweep`, or `nucleus` (`path:line:col: rule: reason`). A
nonzero exit on either side fails, and so does output an extractor does not
recognize. Temporary directories are kept on failure.

Each port's original run, for §6.2:

| Script | Added in | Ran on | Files and flags |
|---|---|---|---|
| `list-api-sweep.py` | b6e454b2 | e1952ea3 | `src/*.nuc lib/*.nuc examples/*.nuc tests/*.nuc`, `--apply` |
| `ptr-sweep.py` | 6910d81d | 294e4ac2 | `src/*.nuc lib/**/*.nuc examples/*.nuc tests/**/*.nuc tests/repl/*.in`, excluding `tests/fixtures/s21-pk2-fuse-open-segment.nuc`; `--in-strings` |
| `sugar-sweep.py` | a5651b4d | 0fc4fa9e | `src/*.nuc lib/**/*.nuc examples/*.nuc`, excluding `examples/{ptr,ref-sigil,colon-paren-types,errptr}.nuc` |

Self-tests (the script against itself) pass: list-api 247 files, 21 changed,
71 refusals; ptr 519 files, 77 changed, 0 refusals; sugar 223 files, 134
changed, 2 refusals. Deliberate differences fail.

**For the ports.**

- `sugar-sweep.py` as it stands no longer reproduces its original run: on
  0fc4fa9e it makes 5,019 rewrites with 2 refusals, against the commit's
  4,985 with 20. RF-6 compares against the current script with
  `--rules R3,R4,R5` (3,788 rewrites, 2 refusals); some general refusals
  ignore `--rules`.
- `ptr-sweep.py` never refuses, so any refusal by its port shows as "only in
  B" and fails replay.
- Whether `lib/node.nuc` was in `list-api-sweep.py`'s original file set is
  uncertain; the glob above includes it.

### RF-1 — syntax mode (built 2026-10-15)

**What exists.**

- `lib/nucleus/syntax.nuc` (`nucleus.syntax`, about 220 lines) holds the types
  (`SynKind`, `Syn`, `SynSpan`, `SynFile`, `SynBuilder`), the builder
  primitives the reader calls, and the queries: `syn-text`, `syn-slice`,
  `syn-prefix`, `syn-has-comment?`, `syn-has-discard?`, `syn-kid-for-elem`,
  `syn-elem-index` and `syn-kid-for-node`.
- `lib/nucleus/read.nuc` gains the `Reader` field `syn:?&SynBuilder`, the
  hooks, and the entry points `read-syntax-all`, `reader-syntax`,
  `read-syntax-one` and `reader-syn-file`, with the results `SynFileResult`
  and `SynResult`. These are hand-written `defunion`s, after the
  `ReadResult` precedent.
- `scripts/stage26/syn-corpus.nuc` is the gate tool.
- `tests/suite-refactor.nuc` holds six units, `rf1-*`.
- `docs/reading.md` has a new "Syntax mode" section.

**Where the types live, and why.** The types live in their own file, which
`read.nuc` imports. The reader needs the builder's type for its field, and
the hooks call the builder primitives, so the import runs from `read` to
`syntax`. The reverse direction would need an import cycle or an untyped
field. A separate file keeps `read.nuc`'s change to hooks and entry points
(+144/−12 lines). The cost is that a tool imports both `nucleus.read` and
`nucleus.syntax`. The compiler imports `read.nuc`, so `syntax.nuc` is
compiled into it either way. No `src/` name collides with a `syn-`/`Syn`
name.

**How it is built.**

- `rd-form` tests `(self 'syn)` once per form, after `rd-skip-discard`. In
  syntax mode it calls `rd-syn-form`. That function classifies the form with
  `rd-form`'s own dispatch tests, in the same order (`rd-syn-kind`), opens a
  frame, and re-enters `rd-form` for the body. A one-shot `framed` flag on
  the builder tells that re-entry not to open a second frame.
- On close, a frame records its end and node and attaches to its parent, or
  to `forms` at the top level.
- A fuse's atom and a tagged literal's tag are read without a frame of their
  own. `rd-syn-head-kid` adds each as kid 0 when its frame closes. The atom
  is read again, alone, to get its node, since the fused tree has no elem for
  it.
- `rd-skip-ws` records each comment.
- `#_` goes through `rd-discard-form`. It records the span, and while the
  discarded form is read it points the builder's current frame at a `sink`
  Syn, so the dropped form's frames reach neither its parent's kids nor
  `forms`.
- `read-all-with-macros`'s loop body became `rd-read-into`, which
  `read-syntax-one` shares, so the two entry points build the spine with one
  piece of code.

**Deviations from §4.1, with reasons.**

1. *`Syn` has an `open` field*: the length of the opening delimiter or the
   prefix spelling. The §4.1 table said "prefix text = `start` to kid start".
   That is wrong whenever whitespace, a comment or a discard separates the
   prefix from its operand: `' x` reads as `(quote x)`. Re-matching the
   macro table at query time is wrong too, because a longer prefix
   registered later in the file could match. **I corrected that table cell
   in §4.1.** The same field gives the gate a container's delimiter bytes.
2. *A tagged literal's tag is a kid* (an atom), so the "kid *i* ↔ elem
   *i+1*" rule holds for `SYN-TAGGED` as the table says. Without it, the
   value would have been kid 0.
3. *Fuse correspondence is identity, not position.* The table covers only
   `x:(T)`. A chain (`x:ptr:(T)` → `(x (ptr (T)))`) and the fn-params fuse
   (`f:(fn i32)(i32)` → `(f ((fn i32) (i32)))`) put the list kids under
   wrappers the fuse made, which have no span. A lone `:` returns the list
   itself, so the fuse's node is its kid's node. Every list kid of a fuse is
   a fresh node, so identity is unambiguous. `syn-kid-for-node` finds a kid
   under a wrapper, and `syn-kid-for-elem` answers a lone-`:` fuse through
   its list kid.
4. *A fuse's atom kid has a node*: the atom read on its own (`x:`). That node
   is not in the tree, and `syn-elem-index` gives -1 for it. With it, the
   gate's re-read check holds for every `Syn` without an exception.
5. *`SynFile` carries `tree`*, the list `read-all` returns. That is what
   makes "the same tree" checkable by identity, form by form.
6. *`kids` is `(Vector &Syn)` over the arena*, not a `Node`-style
   `elems`/`len`/`cap` array. It needs no cast and no growth code of its
   own. The arena reallocates in place at the top.
7. *`syn-has-discard?`* was added beside `syn-has-comment?`. A discarded form
   inside a span is lost by a template rewrite just as a comment is.
8. *§6.1's "applying no edits reproduces the input" is not checked yet.*
   There is no edit layer until RF-3.
9. *§6.1's "exactly one of" is refined.* Comment and discard spans nest: a
   comment inside a discarded form is recorded too, and `#_ #_ a b` records
   two discards, one inside the other. A container also owns its delimiter
   bytes. The rule the gate implements: every byte is (a) inside a comment
   or discard span; or (b) inside an atom, string or char `Syn`; or (c)
   inside the `open` bytes at its innermost container's start, or that
   container's closing bracket (`)`, `]`, `}`); or (d) whitespace (C
   `isspace`) or a comma. In addition, kids lie in order and without overlap
   between their container's `open` bytes and its closer. Each delimiter is
   the right byte for its kind. Comment spans run from `;` to a newline or
   to EOF, and discard spans start with `#_`.

**The ordinary path, measured.** Two hooks were rewritten after measuring:

- **The `rd-form` split was real.** The first build split `rd-form` into a
  wrapper that tested the field and an `rd-form-here` body. On
  `--dump-ast src/nucleusc.nuc` that cost about 2 ms: a median of 36.4 ms
  against 34.6 ms, with startup equal at 16.1 ms on an empty file. A
  variant with HEAD's `rd-form` restored measured 34.6 against 34.1 ms. The
  cost was the extra call, and the `ReadResult` copy, on every form; the
  field test itself was not. Re-entering `rd-form` with the `framed` flag
  keeps the body inline and removed that cost.
- **The comment hook moved out of the loop.** `rd-skip-ws`'s `;` loop at
  first carried a span-start binding and a call after it. A variant without
  the hook timed level with the base (34.9 vs 35.1 ms), and the final build
  without it about 1 ms slower. The ordinary loop is now HEAD's own text,
  and syntax mode scans with its own copy (`rd-syn-comment`).

What remains is below the instrument. An in-process benchmark of `read-all`
over `src/nucleusc.nuc`, 40 reads per process, built `-O3` against each
library, gives a median of 425 ms for HEAD's library and 432 ms for this one
(+1.6%). Reverting all four hooks together gives 427 ms. Reverting any one
of them alone gives 431–433 ms, and removing the per-form test alone gives
441 ms, slower than keeping it. At this scale, code placement moves the
numbers more than the work done does. The container has no `perf` to count
instructions.

The RF-1 gate, "ordinary read time within noise", was judged met on
2026-10-16. Reverting every hook recovers only 5 of the 7 ms, and no single
hook accounts for any of it. If `perf` becomes available, count instructions
on both builds to confirm.

**Gates (all in the build copy).**

| Gate | Result |
|---|---|
| `make` / `make bootstrap` | pass; stage1 == stage2 |
| `make test` | 1469 passed, 5 failed. The 5 are the known `suite-target` datalayout failures under Debian LLVM, the same set as the baseline's 1463/5. The 6 new units pass. |
| `scripts/check-headers.sh` | clean (95 headers). `syntax.h` and `syntax.nuch` are new; `read.h` and `read.nuch` were regenerated. |
| `dump-ast-corpus.sh`, snapshot by HEAD's compiler, verified by the new one | PASS: 1809 artifacts byte-identical (603 inputs, 7 rejected by both) |
| `ir-snapshot.sh`, the same, over the same tree | PASS: 3286 artifacts byte-identical. The compiler writes the same text, and only the reader inside it changed. |
| `syn-corpus` over 652 files (`.nuc` in `tests/fixtures`, `examples`, `lib`, `src`, plus every `.nuch` in `lib` and `src`) | 0 failures: 652/652 agree with `read-all` (7 refused by both, with the same code, line and message); 371,535 Syns correspond to their nodes and nest; 2,295,906 gap bytes accounted for; 371,532 texts read back as their node; 3 skipped: `$s21-x` in `tests/fixtures/s21-def-rmacro.nuc`, a `def-rmacro` prefix, and the two lists around it. 2.3 s. |
| `--dump-ast src/nucleusc.nuc`, interleaved with HEAD's compiler | 5 runs: median 35.6 ms (HEAD 34.3). 21 runs: 34.9 ms (HEAD 34.3), +1.7%. Minimums 33.9 and 33.3 ms. Startup alone is 16 ms for both, so the read and print take about 18 ms. The residual, and what it is, are discussed above. |

The gate tool was shown to fail. Each of eight one-line breakages, made in
the build copy only, was caught by the expected check: span end +1, column
+1, the tag kid dropped, comment recording dropped, discard recording
dropped, a prefix `open` of 0, the vector elem offset changed to 0, and a
char classified as a string. The units were shown to fail under a column
+1 and under syntax-mode errors reported one line late.

**For RF-2 (`chain-segments`).** The reader's fuse splits on `:` itself
(`rd-fuse-colon-paren`), and `rd-open-segment?` runs `rd-seg-next`. A
fuse's `Syn` keeps the raw atom as kid 0, `x:ptr:` with the trailing colon,
which is the text `chain-segments` will take. Keep the fused tree's shape,
or the identity rule in deviation 3 must be revisited:

- one wrapper list per chain segment, innermost around the paren form;
- the name as elem 0 for a symbol;
- no name for a keyword;
- the paren form returned bare for a lone `:`.

**For RF-3 (matcher, edits).**

- A hole binds a `Syn`. Walk a pattern against `(s 'node)` with
  `syn-kid-for-elem`. It returns null exactly where §4.4 says to refuse a
  hole: a literal's or prefix's head, a fuse's name, a fuse wrapper.
- Symbols are interned, so never look a kid up by node identity except
  inside a fuse, where `syn-kid-for-node` is safe.
- `syn-prefix` is the `spelled?` guard's input.
- `syn-has-comment?` and `syn-has-discard?` answer by binary search over the
  sorted spans.
- A `Syn`'s `line`/`col` are what a refusal prints.
- A `Syn` from a discarded form is not reachable, so a rule can never match
  inside `#_`.

### RF-2 — chain segments (built 2026-10-16)

**What exists.** `lib/nucleus/read.nuc` gains a "Colon chains" section:

- `ChainSeg` (`start body end colon`): byte offsets into the chain's text.
  `[start, body)` is the sigil run, `[body, end)` the body, and `colon` says
  a `:` follows at `end`.
- `chain-seg-at text at` is **the one splitter**. A segment runs from `at`
  over its `?`/`!`/`&` bytes, then to the next `:` or the end. `chain-seg-next`
  and `chain-seg-text` step and slice. They allocate nothing.
- `Chain` (`text keyword segs`) and `chain-segments text` are the tool
  view, arena-allocated like `Syn`. The queries are `chain-seg`,
  `chain-sigils`, `chain-body` and `chain-open?`.
- `tests/suite-refactor.nuc` gains six units, `rf2-*`. `docs/reading.md`
  gains "Colon chains" under "Syntax mode".

Everything that split a chain now steps `chain-seg-at`:

| Site | Before | Now |
|---|---|---|
| `rd-expand-sigil` (`&` → `ref:`) | two loops over `rd-seg-next` | `rd-has-ref-sigil?`, then one segment walk that rewrites each sigil `&` |
| `rd-open-segment?` (the fuse gate) | a loop over `rd-seg-next` | walk to the last segment; open when its body is empty |
| `rd-fuse-colon-paren` | `strview-find-byte` on `:` | segment walk over the trailing-colon-stripped body |
| `split-colon-segments` (`src/nucleusc.nuc`, desugar) | its own byte loop | segment walk |
| `spelling-as-key` (`src/union-registry.nuc`) | a copy of that byte loop | segment walk |
| `count-pattern-nodes` (`src/generics.nuc`) | counted `:` bytes | counts segments |

`rd-seg-next` is deleted. Its state machine and `chain-seg-at` agree. State 1
is "at a segment start, in its sigil run", so `?`, `!` and `&` keep it. A
body byte moves to 0, where those three are body bytes. `:` always returns
to 1. So the machine ends in 1 exactly when the last segment's body is
empty, and a sigil `&` is one inside a sigil run. Segment boundaries are the
`:` bytes in both, so the colon-only splitters fall out unchanged.

**Where it lives, and why.** In `read.nuc`, not `syntax.nuc`. The reader and
the compiler both call the splitter. The compiler imports `nucleus.read` and
not `nucleus.syntax`, and `syntax.nuc` cannot import `read.nuc` (§8 RF-1).
The compiler is one LLVM module built `-O3`, so the hot-path callers are no
further from it than before. `split-colon-segments` stays in `src/`, because
its trailing-colon refusal is a `die-at`. So the `:1387` note ("depend only
on `split-colon-segments` … via the whole-unit prescan") still holds.

**Deviations from §4.2, with reasons.**

1. *The reader's own callers run on expanded text, and tools on raw text.*
   The fuse, `rd-open-segment?` and `split-colon-segments` see the interned
   symbol, where `&` is already `ref:`. A tool sees `syn-text`. One splitter
   serves both, because the boundaries are the `:` bytes either way. A sigil
   `&` expands to `ref:`, which ends with a colon, so openness is the same
   on both texts too.
2. *`keyword` is a flag, and no segment is labelled "name".* A raw keyword's
   leading `:` separates nothing, so its segments start at byte 1. Whether
   segment 0 of a symbol is a binding name depends on the position, so it
   is left to the caller. The fuse's rule is the one in RF-1's note: the name
   is elem 0 for a symbol, and a keyword has none.
3. *The split is lexical.* `chain-segments` reports the `&` of a retired
   `&rest` as a sigil. The reader's exception for those four markers stays
   in `rd-expand-sigil`.
4. *Not converted:* `split-typed` (it cuts at the first `:` only, into a
   name and a type) and `qq-name-type-leaf`. That function's sigil set adds
   `*`, so routing it through `chain-seg-at` would change what it skips.

**Gates (all in the build copy).**

| Gate | Result |
|---|---|
| `make` / `make bootstrap` | pass; stage1 == stage2 |
| `make test` | 1475 passed, 5 failed. The 5 are the same `suite-target` datalayout set as RF-1's 1469/5. The 6 new units pass. |
| `scripts/check-headers.sh` | clean (95 headers); `read.h` and `read.nuch` regenerated and copied back |
| `ir-snapshot.sh`, snapshot by RF-1's compiler over the new tree, verified by the new one | PASS: 3286 artifacts byte-identical (545 inputs) |
| `dump-ast-corpus.sh`, the same | PASS: 1809 artifacts byte-identical (603 inputs, 7 rejected by both) |
| `syn-corpus` over the same 652 files (603 `.nuc` + 49 `.nuch`) | 0 failures; 652/652 agree with `read-all` (7 refused by both); 371,986 Syns correspond and nest; 371,983 read back; 3 skipped (the `def-rmacro` case). The counts grew with the edited sources. |
| `--dump-ast src/nucleusc.nuc`, 21 runs interleaved with RF-1's compiler, twice | medians 34.8 vs 35.6 ms and 35.7 vs 35.8 ms (new vs RF-1); minimums 33.8 vs 34.4 ms. No cost. |

The units were shown to fail. With `&` dropped from `chain-sigil?`, four
units fail: `rf1-read-all-unchanged` (the expansion), `rf2-chain-sigils`,
`rf2-chain-trailing` and `rf2-chain-spans`. With a keyword's segments
started at byte 0, `rf2-chain-keyword` fails. `rf2-chain-agrees-with-reader`
cannot catch a splitter bug, because both of its sides now run the same code.
It guards the tool view (`chain-segments`, `chain-open?`) against the
reader's own calls.

**For RF-3.**

- A fuse `Syn`'s kid 0 text ends in its trailing `:`. `chain-segments`
  gives it an empty, open last segment (`x:ptr:` has three segments). The
  `(…)` kid fills that slot.
- `x:?(T)` and `x:&(T)` end in a sigil-only segment instead. The paren form
  is wrapped by that sigil (`(? (T))`, `(ref (T))`). The `&` case shows as
  `ref` only in the node, because the fuse runs on expanded text.
- A lone `:` is two empty segments, and the fuse returns the list bare.

**For RF-5 (`ptr-sweep` port).** `ptr:` → `&` is one span edit per segment
whose body is exactly `ptr` and whose `colon` is set. The edit replaces
`[atom start + body, atom start + end + 1)` with `&`. That keeps the sigil
run: `?ptr:T` → `?&T`, `ptr:ptr:T` → `&&T`, `x:ptr:ptr` → `x:&ptr`.
`ptr-sweep.py` also required the byte after the colon to be one of
`[A-Za-z_(?!&*]`. In a fuse atom that byte is outside the atom, the `(` of
kid 1. `rf2-chain-spans` does this edit by hand. Atoms inside string
literals (§4.6) need the same split over the decoded text. It is purely
lexical, so it works there unchanged.

### RF-3a — edits, sugared printer, glob and walk (built 2026-10-16)

RF-3 is split in two. RF-3a builds the layers under the rules. RF-3b builds
`defrewrite`, `refactor-main` and the `list-api-sweep.py` port on top of them.

**What exists.**

- **Edits**, in a new `lib/nucleus/refactor.nuc` (`nucleus.refactor`):
  `edits-new`, `edit-span`, `edit-replace`, `edits-apply`, as in §4.3. Also
  `edits-apply-range`, `edits-drop-within` and `edits-count`, which are
  described under "For RF-3b" below. An `Edits` copies every replacement
  into one `String`, keeps the `(Vector Edit)` of offsets into it, and is
  `Drop`. It is sorted (a stable merge sort, by start and then end) and
  checked when first applied. It is not checked again against a text of the
  same length until an edit is added.
  The overlap rule: two edits overlap when they share a byte, when an
  insertion lies strictly inside a replacement, or when two insertions are at
  the same byte. Edits that touch are fine. An insertion where a replacement
  starts comes first. A refusal names both edits:
  `edit at 2:3 [5,10) overlaps the edit at 2:4 [6,9)`.
- **`node-write-sugared`** (§4.4.1), in `lib/nucleus/read.nuc` after
  `node-write`. It also comes as `node-write-sugared-with` (any reader-macro
  table) and `node-str-sugared`. Prefix forms, the three collection literals,
  tagged literals, `ref:` chain segments as `&` (`x:&T`), and named or
  printable chars are printed sugared. Each sugared form is re-read on its
  own and compared with `node-eq`. If it differs, the long text is printed
  instead, reusing the inner text already written, so a deep tree is not
  printed twice per level. `node-write` is unchanged.
- **`glob-match` moved** from `lib/nucleus/test.nuc` to `lib/nucleus/file.nuc`,
  unchanged. The test framework reaches it by its existing import of
  `nucleus.file`.
- **The walk and the path glob**, in `file.nuc`. `walk-dir root` lists every
  non-directory below `root`. `glob-files pat` walks from the pattern's
  literal prefix. `path-glob-match` is bash `globstar` matching. To support
  them, `read-dir` now records each entry's kind (`DirEntries` `kinds`, read
  from `d_type` at offset 18), and `dir-is-dir?` answers it. `DT_UNKNOWN` is
  resolved with `readlink` and then `opendir`, because `opendir` alone follows
  a link and the walk would enter a cycle.
- `tests/suite-refactor.nuc` gains ten units, `rf3-*`.
  `scripts/stage26/syn-corpus.nuc` gains the edit and printer checks (§6.1).
  The docs are `docs/refactoring.md` (new: edits, printer pointer, files),
  `docs/reading.md` (the sugared printer), `docs/io.md` ("Walking and globs")
  and `docs/testing.md` (where `glob-match` lives now).

**Decisions and deviations, with reasons.**

1. *`edits-apply` returns `EditsResult`, not `!String`.* An `Err` is a code
   and cannot name two spans. `(defunion EditsResult (ok v:String) (err
   e:EditError))` has `Result`'s arms, as `ReadResult` does. `EditError`
   carries `code`, `msg` and both `SynSpan`s, and has a `defcast` to `Err`,
   so `try` in a `!T` function still works. The codes are `edit-overlap` and
   `edit-out-of-range`.
2. *The printer lives in `read.nuc`.* It is the reader's inverse, and its
   read-back check needs only the reader and the macro table. The compiler
   imports `nucleus.read` but not `nucleus.refactor`, so a sugared
   `macroexpand` (§4.4.1's other client) can call it without pulling in the
   tool library. It is in the same lockstep with the reader as `node-write`.
3. *No position-dependent type sugar.* `x:(T)` for `(x (T))` and `?(T)` for
   `(? (T))` would turn a call into a type wherever the tree is a value, and
   which it is depends on the slot. The printer cannot know that until
   `slot-kind` exists (RF-6). The chain sugar it does use (`x:ref:T` →
   `x:&T`) reads back the same in any position.
4. *`glob-match` stays the text glob*, where `*` crosses `/`. `check-match`
   matches lines of IR and output, not paths. Paths get a separate
   `path-glob-match`, so neither caller's meaning changes.
5. *`**` follows bash `globstar`:* a whole `**` component matches zero or
   more components. A trailing `**` needs at least one, so `lib/**` does not
   list `lib` itself, which is never a file anyway. `*`, `?` and `**` never
   match a hidden component's leading `.`. `glob-files` does not enter
   hidden directories unless the pattern spells a leading `.`, but
   `walk-dir` lists everything. There are no `[…]` classes and no escapes,
   because none of the ported scripts' file sets uses them. `replay.sh`
   expands with `globstar` too. Matched that way at `294e4ac2`, `ptr-sweep`'s
   set is 519 files, its recorded self-test count. Without `globstar` it is
   454.
6. *Order is bytewise over the whole path*, as `LC_ALL=C sort` gives. A
   subdirectory sorts as its name plus `/`, so a preorder walk over
   `read-dir`'s sorted entries produces that order without a final sort.
   (`a-b.nuc` comes before `a/x.nuc`, because `-` < `/`.) Symlinks are listed
   and never entered.

**Gates (all in the build copy).**

| Gate | Result |
|---|---|
| `make` / `make bootstrap` | pass; stage1 == stage2 |
| `make test` | 1485 passed, 5 failed: RF-2's 1475 plus the ten `rf3-*` units. The 5 are the known `suite-target` datalayout set. |
| `scripts/check-headers.sh` | clean (97 headers); `file`, `read` and `test` `.h`/`.nuch` regenerated and copied back, along with the new `refactor.h`/`refactor.nuch` |
| `ir-snapshot.sh`, snapshot by RF-2's compiler over the new tree, verified by the new one | PASS: 3286 artifacts byte-identical (545 inputs) |
| `dump-ast-corpus.sh`, the same | PASS: 1812 artifacts byte-identical (604 inputs, 7 rejected by both) |
| `syn-corpus` over the same 652 files | 0 failures. 652/652 agree with `read-all` (7 refused by both); 374,538 Syns; 374,535 read back. **New:** 645 files reproduced by no edits; 239,283 leaf-for-itself replacements reproduce every file whole and each of its 16,758 forms through `edits-apply-range`; 238,206 inserted spaces give the independently built spaced text, which reads back `node-eq`; 8,379 form-plus-kid overlaps refused naming both; 8,379 top-level forms printed sugared read back `node-eq` and are fixed points; 645 files with every form replaced by its sugared text read back `node-eq`, comments intact. Of 17,945 prefix and literal sites, 0 printed long; of 6,139 `ref:` atoms, 6 printed long (bare `ref:Pt`, `ref:Rec`). About 6 s. |

The edit and printer checks were each shown to fail, in a scratch copy:

| Breakage | Caught by |
|---|---|
| apply drops the last byte | noedit (645), edits (18,048); 3 units |
| sort comparator inverted | edits (18,046); 3 units |
| range search skips the first edit | edits (9,023, all from the insertion check); units |
| no overlap check | 13 overlap failures, then the tool runs out of memory on a negative slice; the unit crashes |
| overlap names one edit twice | 8,379 overlap failures; `rf3-edit-overlap` |
| atom sugar not read back | 4 sugared, 3 rewrite failures; `rf3-sugared-atoms` |
| sugared list drops its separators | 8,011 sugared, 644 rewrite failures; 2 units |
| trailing `**` matches zero components | `rf3-glob-match` |
| walk ignores the directory-as-`name/` order | `rf3-walk` |
| path `*` crosses `/` | `rf3-glob-match`, `rf3-walk` |
| `DT_UNKNOWN` resolved without `readlink` | `rf3-walk-links` |

Two things learned from these breakages. First, identity edits cannot catch
a skipped edit, because the skipped text equals its replacement. The
insertion check is what catches it. Second, a broken library file is in the
corpus itself, so counts move slightly under a breakage.

**For RF-3b.**

- **Bottom-up composition.** To rewrite a matched form, take each hole's
  text with `edits-apply-range src e (hole 'start) (hole 'end)`. That gives
  the hole's subtree already rewritten, with comments and layout. Then
  `edits-drop-within e (form 'start) (form 'end)` and `edit-replace` the
  form. After that, no two edits from one pass can overlap, so an overlap
  refusal from `edits-apply` means a driver bug. `rf3-edit-syn-compose` does
  exactly this.
- **A refusal must leave the subtree as written.** Bottom-up order has
  already rewritten the refused form's descendants, so the refusal has to
  call `edits-drop-within` over the span it keeps. `list-api-sweep.py`
  refuses `(set! (X 'car) v)` and covers only the *place* `(X 'car)`. The
  place's inner `(y 'cdr)` would be rewritten first bottom-up, so drop
  within the place's span. The script's later passes are also covered by
  this rule, so the place's subtree is never rewritten at all.
- **Template text.** Print unquoted `Node`s with `node-write-sugared-with`
  and the reader table the tool reads with. Use the hole text from
  `edits-apply-range` verbatim, and single spaces between template
  elements.
- **What the port has to match** (`scripts/stage21/list-api-sweep.py`):
  - The script runs to a fixed point but reports problems only from the
    first pass. Bottom-up gives the fixed point in one pass.
  - When it flattens a `make-cell` chain, it keeps the source gap in front
    of each element. A gap that contains a line break becomes that many
    newlines plus the outer form's column + 2 in spaces. A template with
    single spaces will differ from the replay on every multi-line chain.
    The rule needs a layout-preserving hole join, or the replay gate has to
    allow for this. The script's column is 0-based in code points, while
    `syn-col` is 1-based in bytes. They differ only after a non-ASCII byte
    earlier on the same line.
  - It unwraps `(as raw:Node (make-cell …))` and `(as ptr (make-cell …))`
    inside a chain. It flattens at most 5 elements (`node-list1`…`5`).
    It flattens only while every cell's line argument has the *same text*
    (a guard compares text, not trees). A tail with one element becomes
    `node-cons`, and a tail with more is refused ("make-cell chain onto a
    tail").
  - Its selector match is textual, `'car` spelled with the quote. A tree
    pattern also matches `(quote car)`. Use `spelled?` if the replay shows
    a difference.
  - Output: `%-32s %3d rewritten` per file, then `path:line  what` with
    `what` collapsed to one line and cut at 90 characters, then `total N`.
    A `Syn`'s `line` gives the line.
  - Its file set is `src/*.nuc lib/*.nuc examples/*.nuc tests/*.nuc`.
    `glob-files` takes those patterns directly. A single `*` component
    does not cross `/`, so `glob-files` matches only the top directory, but
    it still walks the subtree below the literal prefix to find them.

### RF-3b — defrewrite, driver, list-api port (built 2026-10-16)

**What exists.** All of it is in `lib/nucleus/refactor.nuc`. User docs are in
`docs/refactoring.md` ("Rewrite rules", "A rewrite tool").

- `(defrewrite NAME RULE…)` defines `(NAME)`, which returns a `&Rules`. It
  works in a compiled program. Each rule's pattern and template become
  quoted data, and each guard or `:emit` becomes a non-capturing
  `(fn ((m &RwMatch)) …)` that binds every hole to its `&Syn` (a `~@` hole
  to a `&(Vector &Syn)`), `self`, and `out`. The macro checks patterns and
  templates when it expands and reports errors at the rule's line: a hole
  that is not a symbol, `~self`/`~out` used as a hole, a hole bound twice,
  `~@` not last, a template unquoting a non-hole or an unbound name, `~`/`~@`
  of the wrong kind, `~@` outside a list, a malformed option.
- The rule kinds are template, `:refuse REASON` and `:emit EXPR`. The
  options are `:when`, `:multiline`, `:reindent` and `:flag REASON`.
- `rewrite-source rules src` runs one bottom-up pass and returns
  `(ok Rewrite)` (text, reports in source order, a rewrite count) or the
  read error.
- Guard helpers: `src-text`, `same-text?`, `prefix-form?`, `spelled?`,
  `has-comment?`, `has-discard?`, `operand-of?`, `in-quote?`,
  `in-quasiquote?`, `in-unquote?`.
- `:emit` builder: `rw-put`, `rw-put-syn`, `rw-put-gap`, `rw-form-col`,
  `rw-col`.
- Edits: `edits-apply-outermost`.
- Driver: `refactor-main`.
- `scripts/stage26/list-api-sweep.nuc` is **94 lines**. The Python it
  replaces had 282. `scripts/stage21/list-api-sweep.py` is deleted (Q6). Its
  last content is `95df57b7:scripts/stage21/list-api-sweep.py`, and
  `replay.sh`'s header now extracts it from there.
- **How replay's `--b` runs a port:** build it first
  (`build/nucleusc scripts/stage26/list-api-sweep.nuc -o build/list-api-sweep`).
  `--b` is the binary's **absolute path** plus the flags, because replay
  runs each command with the exported old tree as its cwd. RF-4's
  `nucleusc --run` will replace the build step.

**Deviations from §4.4/§4.5, with reasons.**

1. **Edits nest, and text is read through `edits-apply-outermost`. RF-3a's
   recipe drops the edits inside a form, then replaces it.** That recipe
   breaks when a hole lies inside a form that an earlier rule already
   rewrote. A `node-list2` over a cell whose inner cell was rewritten is
   one case. The hole's range then straddles the inner edit, and
   `edits-apply-range` refuses it. Keeping the inner edits and applying
   only the outermost one in any range gives each hole its current text
   with no straddle. The final `edits-apply-outermost` over the whole file
   applies the outer edits. A refusal still drops the edits within its
   form, which keeps that form as written.
2. **`:emit EXPR` and a small output builder.** list-api has two needs that
   a template cannot express. Its output's arity depends on the data
   (`node-list1`…`5`), and every operand must keep the source gap in front
   of it (§8 RF-3a, "What the port has to match"). Allowing arbitrary
   unquotes in templates would have meant evaluating code that yields
   `Node`s. Those `Node`s carry no layout, so that option would still have
   lost the gaps. `:emit` writes text through `rw-put-gap`/`rw-put-syn`,
   and the comment-drop check still applies. Template rules unquote holes
   only (v1). Any other unquote is refused at expansion and points to
   `:emit`.
3. **`:multiline` splices verbatim, as §4.4 says. `:reindent` is new.** It
   moves continuation lines by the hole's column change, except lines that
   start inside a string literal and empty lines. The Python moved inner
   chains verbatim and re-indented chains it flattened, so the port needs
   both.
4. **`:flag REASON` (rewrite and report).** The Python *reported* 22 chains
   as "make-cell chain onto a tail". Its later fixed-point passes then
   rewrote those chains anyway, into nested `node-cons`. Replay therefore
   needs the rewrite *and* the reported site. The driver prints a flag as
   `… (rewritten; check it)`, and `--strict` counts it.
5. **`operand-of? s head i`.** This is a positional guard until RF-6's
   `slot-kind`. Python refused the *place* `(X 'car)` of a `set!` and still
   rewrote the value, so `(~x 'car) :refuse … :when (operand-of? self 'set!
   1)` is the right granularity. A `(set! (~x 'car) ~v)` pattern would have
   refused the whole form.
6. **Automatic refusals.** The pass refuses a rewrite whose output would
   lose a comment or a `#_` form inside the matched form. Its test is
   whether every comment or discard span lies in a source range the output
   copied. It also refuses **any** pattern hole with no source span, not
   only a hole the template uses. The reason is that a guard or `:emit` can
   use any hole, and a null `Syn` there crashes. This check runs before the
   guard.
7. **The multi-line test reads a hole's current text, not its source.** If
   an inner rewrite collapses a hole onto one line, the outer rule may use
   it.
8. **`defrewrite` defines a function, not a global table.** This follows
   the house rule against global collection literals. Guard helpers read
   the pass through an ambient `g-rw`, which is saved and restored around
   `rewrite-source`, because a guard sees only `Syn`s.
9. **Driver.** In `path:line:col: NAME: reason`, `NAME` is the rule set's
   name. The per-rule histogram is in the summary, and rules there are
   numbered and shown by pattern. A directory argument takes only `.nuc`
   and `.nuch` files. A glob takes whatever it matches. An argument that
   matches nothing is a failure. Exit codes: 0, 1 (an I/O failure, an
   unmatched argument, or `--strict` with any report), 2 (usage).
   `--in-strings` exits 2 with "not built yet (Stage 26 RF-5)".

**What the port taught.**

- **No fixed point and no textual matching were needed.** The selector
  pattern `(~x 'car)` also matches `(quote car)`, and the corpus has none.
  No chain contains a comment or a non-ASCII byte, and no selector hole
  spans lines.
- **The same-line-text condition on chain cells is unexercised.** Deleting
  it from the port still PASSes replay. It is kept because the Python
  states it.
- **Library gaps a second port will hit.** `((ref s 'kids) i)` and a test
  of a form's textual head (`kid` and `call?` in the port) are each
  rewritten per tool. They are candidates for `syn-kid`/`syn-call?`.
  `:emit` code reaches into `kids` for gap boundaries.
- **Not usable at the REPL yet, for reasons outside RF-3b.**
  (a) A macro that expands to a top-level `defn` fails at the REPL with
  "unknown: defn". That is already true at `base` for any such macro, so
  `defrewrite` inherits it. (b) Since RF-1…RF-3a, `(import-use
  nucleus.read)` followed by `(import-use nucleus.file)` fails at the REPL
  ("undefined: __gs_61" at `file.nuc:267`; with `nucleus.syntax` first, it
  fails with "unknown: let"). `(import-use nucleus.refactor)` alone imports.
  `base` imports read and then file cleanly. Neither failure affects
  compiled programs.

**Gates (in the build copy).**

| Gate | Result |
|---|---|
| `make` / `make bootstrap` | pass; stage1 == stage2 |
| `make test` | 1494 passed, 5 failed: RF-3a's 1485 plus nine `rf3b-*` units; the 5 are the known `suite-target` datalayout set |
| `scripts/check-headers.sh` | clean (97 headers); `refactor.h`/`.nuch` regenerated and copied back |
| `ir-snapshot.sh`, snapshot by RF-3a's compiler, verified by the new one | PASS: 3286 artifacts byte-identical (545 inputs) |
| `dump-ast-corpus.sh`, the same | PASS: 1812 artifacts byte-identical (604 inputs, 7 rejected by both) |
| `syn-corpus`, same command | 0 failures over 654 files. This is the same file set as RF-3a's tree today; RF-3a's 652 was counted before its own headers were added. 654 agree with `read-all`, 384,538 Syns |
| replay, the header's command at `e1952ea3` | **PASS**: 247 files, both changed 21, 71 refusal sites each (the port prints 50 refusals and 22 flags on 71 distinct lines) |

Each unit and the replay were shown to fail under a deliberate breakage, in
scratch copies:

| Breakage | Caught by |
|---|---|
| `~@` binds from one element too late | `rf3b-match-holes` |
| hole text through `edits-apply-range` (nested edits refused) | `rf3b-compose`, `rf3b-refusal` |
| `spelled?` ignores which prefix | `rf3b-guards` |
| refusal keeps inner rewrites | `rf3b-refusal` |
| no-span check off | `rf3b-no-span` (the unit crashes on the null `Syn`) |
| multi-line hole spliced without `:multiline` | `rf3b-multiline` |
| unbound template hole not checked | `rf3b-expand-errors` |
| `in-quasiquote?` true inside an unquote | `rf3b-quote-context` |
| comment-drop check off | `rf3b-match-holes` |
| `rw-put-gap` ignores the indent | `rf3b-emit-gaps` |
| port flattens at most 4 cells | replay FAIL: 57 diff lines, 3 refusal sites only in b |

**For RF-4.** `nucleusc --run` has to run `defrewrite` tools. If `--run`
goes through the REPL's per-form JIT path, it hits the top-level `defn` from
macro expansion problem described above. Run it whole-unit, as a compiled
program is. Replay's `--b` then becomes
`"$PWD/build/nucleusc --run $PWD/scripts/stage26/list-api-sweep.nuc -- --apply"`.

**For RF-5.** `refactor-main` reserves `--in-strings`. `rewrite-source`
over a decoded string needs the offset map to place its edits and to map
report line and column back to the file.

**For RF-6.** `operand-of?` is the stopgap that `slot-kind` replaces. The
`ptr-sweep` port will need `:emit` or `:reindent` wherever it changes the
width of a form whose continuation lines follow it.

### RF-4 — `nucleusc --run` (built 2026-10-16)

**First, the REPL regression from RF-3b (b).** `(import-use nucleus.read)`
then `(import-use nucleus.file)` failed at the prompt with "undefined:
__gs_61" at `file.nuc:267`, and with `nucleus.syntax` first, "unknown: let".

*Root cause: a latent JIT bug that Stage 26 code exposed.*

- Any import that reaches `nucleus.node` gives the session its own copy of
  `lib/nucleus/node.nuc` and `lib/nucleus/intern.nuc`. `read`, `syntax` and
  `refactor` all reach it. That copy includes their globals, the node
  intern table and the `Symbol` table.
- The JIT's main dylib is searched before `<Process Symbols>`. So a macro
  JIT module first materialised after the import binds `intern-symbol` to
  the session's copy, and its symbols come from a second table.
- The compiler compares symbols by pointer, which gives two symptoms. A
  special-form head is not recognised ("unknown: let"). And a binder minted
  by the host's `nucleus_gensym` does not match its reference: `str` passes
  it through `str-into`'s nested quasiquote (`` `(to-str ~p ~'~out) ``
  inside `macmap`), whose per-expansion body re-interns it through the
  session's table ("undefined: __gs_N").
- This is the residual that
  [repl-jit-symbol-precedence.md](../stage16-ergonomics/repl-jit-symbol-precedence.md)
  §5 recorded and pinned in `tests/repl/host-runtime.in` (step 6).
- Stage 26 only reached it. RF-3a's `dir-resolve-kind` is the first `str`
  in `file.nuc`. At `base`, `(import-use nucleus.read)` followed by any
  `defn` that uses `str` fails the same way ("undefined: __gs_51"). With
  `base`'s `read.nuc` swapped into the new tree, read then file still fails,
  so `syntax.nuc` is not the cause.

*Fix: in the REPL, a `lib/` global that the compiler binary defines is the
compiler's.* `emit-global-def` emits `@g = external global T` and queues no
initializer when `repl-host-global?` holds. Its four conditions are:

1. the session is interactive;
2. the definition is not inside a JIT module;
3. the defining file is under `g-ct-lib-root`;
4. `host-exports?` finds its IR name.

This is L6's provenance rule for a macro body's globals
([macro-call-linking.md](../stage20-macros/macro-call-linking.md) §3.2: one
arena, one intern table), extended to the session. The `ProgGlobal` record is
still made, so `repl-backfill-progglobal-decls` declares the global to later
modules.

*Why globals and not functions.* §5's three candidates are register-and-declare
for the node runtime, a JITDylib for macro modules, and host-pinned aliases.
All three make the *code* single. What has to be single is the *state*: the
session's `intern-symbol` returns the compiler's node once the table it reads
is the compiler's. Sharing only globals has three advantages:

- the session's own function definitions still win (`context/repl.md`);
- no seventh ABI-lowered `declare` emitter is needed;
- one rule covers every host-linked `lib/` global, with no list to maintain.

The globals it reaches today are `g-arena` and `heap`; the six intern-table
globals; `io.nuc`'s output buffer `g-io-buf` and input buffer `g-in-*`; and
`error.nuc`'s `g-handler-top`. The cost is the assumption L4 and L6 already
make: a session running a `lib/` that changed one of those globals' layout
shares state with a compiler built from the old one.

*Measured.*

- Each `lib/nucleus` module was imported in a fresh session, both alone and
  after `nucleus.read`.
  - With RF-3b's compiler, four imports fail after `read`: `edn`, `file`,
    `refactor` and `test`.
  - Now only `test` fails, both alone and after `read`. It fails the same way
    at `base` ("use of undefined value '@nuc_err_messages'"). That failure is
    pre-existing and was not investigated.
- `tests/repl/host-runtime.in` step 6 now answers 111. Its fixture said it
  would be updated rather than deleted.
- The new `tests/repl/rf4-host-state.in` imports `read`, then `file`, calls a
  `str`-using `defn`, and expands a `cond` macro. It and `host-runtime` fail
  on RF-3b's compiler and pass on this one.
- The rule needs `g-interactive`, so batch output cannot move. The IR and
  `--dump-ast` snapshots confirm it.

*Not this cause.* A macro that expands to a top-level `defn` still fails at
the prompt ("unknown: defn"), with or without `node` imported. That failure
is in the REPL's per-form dispatch, and it stays open. `--run` does not go
through that path.

**What exists.**

- **`--run`.** `nucleusc --run FILE [-- ARGS…]` compiles the unit as `-o`
  does: `emit-toplevel-forms` over the whole unit, the prelude, then
  `assemble-module-ir`. `flush-module-ir`'s third arm then calls
  `run-module` instead of `compile-and-link`, and exits with what it
  returns.
- **`run-module`** builds the module in five steps:
  1. parses the module, using `output-module`;
  2. applies `-ffast-math` and `-O`;
  3. moves the constructors out (`run-take-ctors`);
  4. creates an LLJIT of its own, whose backend level comes from
     `output-target-machine`;
  5. adds the module and loads `-l` libraries (`repl-load-link-args`).

  It then calls each constructor and `main`.
- **Split out of `compile-and-link`:** `output-module` (parse, diagnostic
  handler) and `output-target-machine` (the `-o` TargetMachine, with
  `-march=native`). `compile-and-link` calls both and is otherwise unchanged.
- **Refused with exit 2:** `--run` together with `-i`, `--emit-llvm`, `-c`,
  `-o`, a header mode, `--dump-ast` or `--target=`; `--` without `--run`;
  `--run` with no file.
- **Units:** `rf4-run-argv-status` and `rf4-run-refusals` in
  `tests/suite-refactor.nuc`.
- **Docs:**
  - `docs/compiler.md`: the flag row, and a new "Running a program without
    linking" section;
  - `docs/refactoring.md`: running a tool;
  - `docs/index.md`;
  - `replay.sh`'s header and `list-api-sweep.nuc`'s usage line.

**Decisions, with reasons.**

1. **A JIT session of its own.** The compile-time LLJIT's main dylib already
   holds the macro modules, plus the mirror copies that L4 and L6 make of
   program functions and globals (`weak_odr`). Adding the program there would
   be a duplicate definition wherever a macro had called into it. A second
   `LLVMOrcCreateLLJIT` is cheap next to compiling.
2. **Constructors are moved out of the module.** ORC's C API runs no
   `llvm.global_ctors` ([global-init.md](../global-init.md) §2.9). The
   driver does not emit a different init function. `run-take-ctors` renames
   each registered constructor to an external `__nucleus_run_ctor_N`, in
   priority order (stable), and deletes the registration. The emitter is
   untouched, so `--run` runs the IR that `-o` would link.
3. **`argv`.** `argv[0]` is the source path as given, and the words after
   `--` follow it. A fresh array is used, because the argv vector the
   compiler was given is not the program's. A nullary `main` is called
   through the same `(fn i32)(i32 ptr)` pointer, as the C runtime does.
   A `void` `main` gives status 0.
4. **The compiler exits with `main`'s value.** `exit` runs atexit and
   flushes stdio, as a returning binary does. A program's own `exit` exits
   directly.
5. **The prompt's library chatter is gated to `-i`.** `repl-library-load`
   printed `  loaded X` to stderr. Under `--run`, stderr belongs to the
   program.
6. **Import resolution is unchanged.** It searches the source directory,
   then `lib/` under the cwd, then `-I`. Replay runs each side with an old
   tree as cwd, so `--b` adds `-I $PWD/lib`. None of the three replay
   revisions (`e1952ea3`, `294e4ac2`, `0fc4fa9e`) has a `lib/nucleus/`, so
   nothing shadows the new library.
7. **The three ORC error prints are one helper (`run-check`).** That leaves
   one new C-string site, the `LLVMErrorRef` message, which is a real FFI
   seam. `scripts/cstr-allowlist.txt` went from 18 to 19 for
   `nucleusc.nuc`.

**Startup, measured (Q4).** All times are wall-clock medians, taken in the
container against LLVM 23.

- *Trivial*: a 7-line program that imports `nucleus.io`, prints its argv,
  and has one run-time initializer.
- *list-api*: `scripts/stage26/list-api-sweep.nuc`, a dry run over
  `e1952ea3`'s 247 files, with that tree as cwd.

| | trivial | list-api |
|---|---|---|
| `--run` (`-O0`) | **568 ms** | **2146 ms** |
| `-o` build (`-O0`) + run the binary | 622 + 4 = 626 ms | 1468 + 707 = 2175 ms |
| `--run -O1` / `-O2` | — / 874 ms | 3570 / 3867 ms |
| `-o -O2` build + run | — | 3765 + 175 = 3940 ms |
| `--emit-llvm` alone (the front end) | 513 ms | 1057 ms |

Where `--run`'s time goes, from timestamps at each phase. These were taken in
a scratch build only, and no timing code is in the tree:

| phase | trivial | list-api |
|---|---|---|
| front end (read, prelude and imports, emit) | 430 | 910–970 |
| parse the IR into a module | 7 | 41 |
| JIT codegen, `CodeGenOpt::None` (LLJIT default `Default`) | 40 (145) | 275 (760) |
| `main` at `-O0` (at `-O2`) | 0 | 670 (150) |
| middle-end pipeline at `-O2` | — | 1340 |

- **`--run` costs what build-then-run costs.** It is slightly faster than
  build-then-run, because JIT codegen at `None` is cheaper than writing an
  object file and spawning `clang`.
- **The front end is most of startup.** An `(exclude-prelude)` program
  compiles in 20 ms and the prelude alone in 140 ms. Each C header import
  spawns a `clang -E` of about 35 ms; `nucleus.io` needs three, and the prelude
  needs one. The rest is compiling the imported library closure. A refactor
  tool pays about one second before it reads its first file.
- **`-O` default: `-O0`, with the JIT backend following `-O`.** LLJIT's own
  default is `CodeGenOpt::Default` at every level. A `JITTargetMachineBuilder`
  made from `output-target-machine`, the TargetMachine `-o` uses, gives
  `None` at `-O0`, which is 3× faster to JIT here. `-O1` and `-O2` cost
  1.4–1.7 s of optimisation to save about 0.5 s of run on the list-api
  workload. For a one-shot tool that is a loss. Pass `-O2` for a long run.
  The default is the same as `-o`'s, so it needs no flag of its own.

**Gates (in the build copy).**

| Gate | Result |
|---|---|
| `make` / `make bootstrap` | pass; stage1 == stage2 |
| `make test` | 1497 passed, 5 failed: RF-3b's 1494 plus `rf4-run-argv-status`, `rf4-run-refusals` and `repl-rf4-host-state`. The 5 are the known `suite-target` datalayout set. `cstr-residue` needed its allowlist bumped by the one FFI seam (decision 7). |
| `scripts/check-headers.sh` | clean (97 headers); no `lib/` header changed in RF-4 |
| `ir-snapshot.sh`, snapshot by RF-3b's compiler, verified by the new one | PASS: 3286 artifacts byte-identical (545 inputs). The REPL fix needs `-i`, so batch output did not move. |
| `dump-ast-corpus.sh`, the same | PASS: 1812 artifacts byte-identical (604 inputs, 7 rejected by both) |
| replay, `replay.sh`'s header command, `--b` under `--run` | **PASS**: 247 files, 21 changed on each side, 71 refusal sites each |
| REPL regression test | `repl-rf4-host-state` and `repl-host-runtime` fail on RF-3b's compiler, as do both `rf4-run-*` units (no `--run`), and pass on this one |

The `--run` units were shown to fail under three breakages, each made in a
scratch copy:

| Breakage | Caught by |
|---|---|
| constructors not called | `rf4-run-argv-status` (status 4, not 46) |
| `argv` taken one word late | `rf4-run-argv-status` |
| `main`'s value dropped | both units |

**For RF-5.**

- The `ptr-sweep` port's `--b` follows the list-api form:
  `"$PWD/build/nucleusc -I $PWD/lib --run $PWD/scripts/stage26/ptr-sweep.nuc -- --in-strings"`.
  `294e4ac2` has no `lib/nucleus/`, so nothing shadows the library.
- A tool's startup is its front end: compiling `nucleus.refactor` and
  everything it imports, about a second. If a later port is run many times
  in a loop, two remedies are available. One is the Makefile
  `build/tools/X` rule that Q4 named as the alternative. The other is
  caching `clang -E` output across processes. Neither is needed for one
  replay.
- `defrewrite` still cannot be used at the prompt ("unknown: defn", the
  REPL's top-level dispatch). `(import-use nucleus.refactor)` itself now
  imports cleanly after any other library.

### RF-5 — programs inside strings, ptr-sweep port (built 2026-10-16)

**What exists.**

- **`lib/nucleus/read.nuc`**, a new "A string literal as source" section:
  - `StrSource` (`text map`) and `syn-string-source f s`: a `SYN-STR`'s
    value, decoded, and for each value byte the file offset that spells it
    (an escape's `\`), plus one entry for the closing quote.
  - `str-source-at`, `str-source-split?` (an offset inside the bytes one
    `\uXXXX` decodes to) and `str-source-escape` (`"`, `\` and NUL escaped;
    every other byte, line breaks included, kept).
  - `rd-string-escape`: `rd-string`'s escape decoding, moved into a function
    of its own. `syn-string-source` decodes through it, so the map cannot
    disagree with the reader about an escape.
  - `read-syntax-fragment src starts-in-string`, described under deviation 2.
- **`lib/nucleus/syntax.nuc`:** `SynFile` gains `fragment` and
  `ends-in-string`, and `SynBuilder` gains `recover`.
- **`lib/nucleus/refactor.nuc`:**
  - `rewrite-source-in-strings`. `Rewrite` gains `strings`, `fragments` and
    `skipped`.
  - The guards `in-string?` and `src-slice`.
  - `edits-outermost`.
  - `refactor-main --in-strings`, which RF-3b reserved.
  - The pass is split into `rw-init` and `rw-run-pass`, so a string's pass is
    the same code as a file's.
- **`scripts/stage26/ptr-sweep.nuc`, 86 lines.** The Python it replaces had
  142. `scripts/stage21/ptr-sweep.py` is deleted (Q6). Its last content is
  `6910d81d:scripts/stage21/ptr-sweep.py`, and `replay.sh`'s header extracts
  it from there. `scripts/stage21/raw-sweep.py` imported `split` from it, so
  that function is copied into `raw-sweep.py`, which stays runnable.
- **Units:** five `rf5-*` units in `tests/suite-refactor.nuc`.
- **Docs:** `docs/refactoring.md` ("Programs inside string literals", the
  driver's flags and exit status), `docs/reading.md` ("String literals as
  source") and `docs/index.md`.

**How it works.** In `rw-visit`, a `SYN-STR` with `--in-strings` gets a pass
of its own. That pass runs after the string's kids (it has none) and before
the rules are tried on the string itself.

1. The string's value is read with `read-syntax-fragment`.
2. A nested `Rewriter` runs the same rules over it at `depth` + 1, with its
   own `Edits`, its own reports and the same `Rules`, so hit counts
   accumulate.
3. The nested edits that `edits-apply-outermost` would apply
   (`edits-outermost`) are mapped through the `StrSource` onto the file's
   `Edits`. Their text is escaped.
4. The nested reports are moved to the file position of their `Syn`. The line
   is the string's line plus the line breaks up to the mapped offset, and the
   column is `syn-col` there.

Strings inside that program get the same treatment in turn, so the mapping
composes one level at a time. A rewrite of the enclosing form sees the
string's edits as nested edits, and a refusal of it drops them, by RF-3b's
rules.

**Deviations from §4.6, with reasons.**

1. **Escapes are mapped per outermost edit, not per byte of its text.** The
   replacement text is escaped whole. So a hole copied from the value comes
   back with every byte as itself: a `\n`, `\t` or `\x41` the source used
   where no escape was needed becomes the byte it decodes to. `"`, `\` and
   NUL stay escaped. Keeping those spellings would mean tracking which output
   bytes were copied from where. `ptr-sweep` never meets this, because the
   Python refused an operand containing `\` or `"`.
2. **A string that does not read whole is read as a fragment, not skipped.**
   §4.6 says to skip it. Replay showed four of the Python's rewrites in three
   files sit in pieces of programs that tests assemble with `str`. Examples
   are `"(defn f (p:ptr:Pt):i32 "` and `"\")\n(defn main …"`. So
   `read-syntax-fragment`:
   - skips a closer with no opener;
   - keeps a form the text ends inside, a list or a string, in `forms` with a
     null `node` and the kids it had read;
   - with `starts-in-string`, starts reading past the first unescaped `"`.

   `rw-visit-kids` passes the flag on: when a string literal ends inside a
   string (`"(import-use \""`), the next string literal in the same form
   starts inside one. Any other read error still skips the string and counts
   it. Over the replay tree, 13,453 strings read whole, 1,632 as fragments,
   and 35 were skipped. Each of the three mechanisms is needed: without any
   one of them, replay fails (table below).
3. **A file that does not read no longer fails the run.** It is reported as
   `path:line:1: error: …` and counted in the summary. The exit status is 1
   only with `--strict`. RF-3b counted it as an I/O failure, but its own
   deviation 9 lists exit 1 for I/O failures only. The ptr-sweep set
   includes eight fixtures that are malformed on purpose (`w4c-*`,
   `w5a-hex-escape-no-digit`, `w5e-ns-hash-reserved`, the REPL's
   `s21-def-rmacro.in`). The Python treated them as text and rewrote nothing
   in them, and the port leaves them as written. The `nucleus` extractor
   ignores `error` lines, so they are not refusal sites.
4. **The guards `in-string?` and `src-slice`.** The Python rewrote
   `(ptr X)` → `&X` only inside strings. Its regex also looked at the byte
   before a match and the byte after it, which can lie outside the `Syn`: the
   `(` after a fuse's `ptr:`, or the byte before an atom.
5. **Refusals the string pass makes itself:** "a rewrite inside the string
   splits an escape" and "the rewrites inside the string cross each other".
   The second would be a driver bug. Either refusal is reported at the string
   and keeps the string as written.

**What the port taught.**

- **The Python is textual, so the port needs a few byte tests.** Its `ptr:`
  regex required the byte before the segment to be whitespace or one of
  `(:?!&'`~@[{`, or a line start. The raw text of a string chunk starts with
  its `"`, so a `ptr:` first in a string was never rewritten.
  `"ptr:Pt"` in `suite-s21.nuc` stays, and replay fails without that test.
  These are spelling guards on `src-slice`, which §4.4 anticipated.
- **Exercised, by deleting each condition and re-running:**
  - the byte before the segment, and the never-first-in-a-string case of it;
  - the byte after the segment;
  - for `(ptr X)`: the single space after `ptr`, the byte before the `(`, and
    `in-string?`.

  **Not exercised:** `(ptr X)`'s operand conditions (no `"`, `\`,
  whitespace, parens or `;` in an atom operand; not a keyword). They are kept
  because the Python states them.
- **Python cases with no instance in the corpus**, where the port reads the
  tree:
  - a `ptr:` in a comment inside a string program, which the Python
    rewrote and the port does not;
  - a `ptr:` after an escape such as `\n`, where the Python saw the `n`;
  - a `ptr:` inside a `#_` form.

  The replay shows none of them.
- **Counts differ by design.** The Python counted regex matches, and the port
  counts rewritten forms. Both are 1,215 on this tree.
- **Library gaps for later ports.** A form-level rule rewrites a sub-atom
  span by re-emitting the whole atom through `:emit`. A segment-level
  edit helper (`rw-put-seg`, or rules over chain segments) would shorten
  that. A test of the byte before or after a `Syn` is common in textual
  originals, so `src-slice` may want named wrappers.

**Gates (in the build copy).**

| Gate | Result |
|---|---|
| `make` / `make bootstrap` | pass; stage1 == stage2 |
| `make test` | 1502 passed, 5 failed: RF-4's 1497 plus the five `rf5-*` units. The 5 are the known `suite-target` datalayout set. |
| `scripts/check-headers.sh` | clean (97 headers); `read`, `syntax` and `refactor` `.h`/`.nuch` regenerated and copied back |
| `ir-snapshot.sh`, snapshot by RF-4's compiler over the new tree, verified by the new one | PASS: 3286 artifacts byte-identical (545 inputs) |
| `dump-ast-corpus.sh`, the same | PASS: 1812 artifacts byte-identical (604 inputs, 7 rejected by both) |
| `syn-corpus` over 654 files | 0 failures; 654 agree with `read-all` (7 refused by both); 387,640 Syns; 387,637 read back; 647 files reproduced by no edits |
| ptr-sweep replay, `replay.sh`'s header command at `294e4ac2`, `--b` under `--run` | **PASS**: 519 files, 77 changed on each side, 0 refusal sites each. The port is 86 lines, against 142. |
| list-api replay, the header's command at `e1952ea3` | **PASS**: 247 files, 21 changed on each side, 71 refusal sites each |

Each unit, and the replay, was shown to fail under a deliberate breakage, in
scratch copies:

| Breakage | Caught by |
|---|---|
| the map records the byte after a spelling, not its start | `rf5-string-source`, `-escape`, `-reports`, `-skipped` |
| NUL not escaped | `rf5-string-source` |
| `str-source-split?` always false | `rf5-string-source` |
| mapped edit text not escaped | `rf5-in-strings-escape`, `-skipped` |
| reports keep the value's line and column | `rf5-in-strings-reports` |
| no carry between string pieces | `rf5-in-strings-skipped`; replay: 1 file differs |
| a form the text ends inside abandoned, not kept | `rf5-fragment-read`; replay: 2 files differ |
| a stray closer ends the fragment | `rf5-in-strings-skipped`, `rf5-fragment-read`; replay: 1 file differs |
| fragments skipped (whole programs only, as §4.6 said) | replay: 3 files differ |
| port: no test of the byte before a segment | replay FAIL (`"ptr:Pt"` rewritten) |
| port: no test of the byte after a segment | replay: 1 file differs |
| port: `(ptr X)` without `in-string?`, the space test, or the byte before | replay: 9, 6 and 6 files differ |

**For RF-6.**

- `sugar-sweep.py` has comment rules (`--comments`). The library never
  rewrites comments, so R3–R5 should be checked for any rule that touches one
  before the replay is run.
- `in-string?` and fragments are general, so R3–R5 can run with
  `--in-strings` if the original did. Expect deviation 1's re-spelling
  wherever a hole carries an escape.
- `slot-kind` on a `Syn` inside a fragment meets a parent with a null node.
  The guards here treat that parent as matching nothing (`node-at` on null is
  safe), and `slot-kind` must do the same.
- An RF-6 rule over a fragment's incomplete form never fires, because rules
  are not tried on a null node. A sweep whose sites sit in the head of an
  unfinished form (`"(defn f (p:&T"`) reaches only that form's complete kids.

### RF-6 — slot table, slot-kind, sugar R3–R5 port (built 2026-10-16)

**What exists.**

- **`lib/nucleus/slots.nuc` (`nucleus.slots`), the slot table.**
  - `SlotKind`, an enum of 23 slots: `SLOT-UNKNOWN`, `TOP`, `HEAD`, `VALUE`,
    `PLACE`, `INLINE`, `NAME`, `BINDER`, `FIELD`, `ATTR`, `BINDINGS`,
    `PARAMS`, `DECL-PARAMS`, `OPTIONAL`, `RETURN`, `TYPE`, `TYPES`, `SIG`,
    `ARM`, `CLAUSE`, `PATTERN`, `QUOTED`, `TEMPLATE`.
  - One row per built-in head, `FormSlots` (`a b c rest attrs desugar`):
    the slots of elems 1–3, the slot of every later elem, whether leading
    keywords are attributes, and whether the compiler's `desugar` splits the
    form. `form-slots-of` is a single `cond`; a head with no row is a call,
    `SLOT-UNKNOWN` throughout.
  - The shape inside a slot (`slot-in-type`, `-binder`, `-bindings`,
    `-params`, `-decl-params`, `-arm`): what elem `i` of a type, a binder
    list, a parameter list, … is.
  - Public: `slot-of-elem own n i` (the one question: the slot of elem `i`
    of list `n` whose own slot is `own`), `slots-desugared? n`, `form-slots`,
    `form-slots-of`, `slot-head`, `slot-name`.
  - It imports only `strview`, `intern` and `node`, which the compiler
    already imports, so `src/nucleusc.nuc` and `nucleus.refactor` both import
    it with no cycle and no bootstrap step.
- **`desugar-form` consumes it** (`src/nucleusc.nuc`). It returns a form
  whose row is not `desugar` unchanged; otherwise it asks `slot-of-elem
  SLOT-TOP` of each operand and `desugar-slot` dispatches on the answer:
  `BINDER` → `desugar-typed`, `FIELD` → the legacy-marker check then
  `desugar-typed`, `PARAMS` → `desugar-params`, `DECL-PARAMS` →
  `declare-params-checked`, `BINDINGS` → `desugar-let-bindings`, `TOP` (an
  `INLINE` operand at top level) → `desugar-form`. The per-head rebuilds are
  gone; the names of the forms desugar knows now live only in
  the table.
- **`(slot-kind s)`** in `lib/nucleus/refactor.nuc`: the parent's own slot,
  recursively, then `slot-of-elem` at `syn-elem-index`. A parent with a null
  node (a fragment's unfinished form) gives `SLOT-UNKNOWN`. A fuse's atom
  has its fuse's slot; a fuse's list kid, which may sit under chain wrappers,
  is found by node identity (`rw-slot-path`). The root is `SLOT-TOP`.
  `operand-of?` stays, for a macro's operands, which have no slot.
- **`scripts/stage26/list-api-sweep.nuc`'s** two `set!` refusals now ask
  `(= (slot-kind self) SLOT-PLACE)`, which also covers `inc!`/`dec!`.
- **`scripts/stage26/sugar-sweep.nuc`, 94 lines (64 without comments and
  blanks).** `scripts/stage21/sugar-sweep.py` is 739 lines; trimmed to R3–R5
  and the skeleton they need (`$S/sugar-r345.py`, checked to reproduce R3–R5's
  output exactly) it is 652. The `.py` stays: the port covers three of its
  eight rules (Q6).
- **Units:** six `rf6-*` in `tests/suite-refactor.nuc`: `slot-definers`,
  `slot-code` and `slot-types` print the slot of every Syn in a source
  covering each built-in form's slots; `slot-fragment` the null-node parent;
  `slot-guard` a `defrewrite` that rewrites in `SLOT-TYPE` and refuses in a
  call; `desugar-rows` the `desugar` flags.
- **Docs:** `docs/refactoring.md` ("Operand slots", the guard table),
  `docs/index.md`; `context/conventions.md` ("Adding a special form: give it
  a row in the slot table").

**The survey: who decides roles today.**

| Where | What it knows |
|---|---|
| `desugar-form` (before RF-6) | binder/param positions of the 12 desugared heads; now the table |
| `emit-list` and the `emit-*` arms | every form's operands, implicitly, by what each emitter reads |
| `qq-binder-slot`, `qq-binder-stride`, `qq-report-binders`, `qq-ret-index` (`src/nucleusc.nuc`, quasiquote hygiene) | binder positions of the binding forms and definers, **including the library macros** `dotimes`, `doseq`, `doseq-iter`, `for`; `extend`'s method defs at elem ≥ 3; a `):Ret` at elem 3 of `extern` |
| `gcheck` (`src/generics.nuc`) and `GCHECK-SPECIAL-FORMS` | closure params at 1, body from 3; which heads are not calls |
| `SPECIAL-FORM-NAMES` | which heads may not be shadowed |
| `declare-param-named?` (`src/nuch.nuc`) | a `declare` param is named iff annotated; else it is a type |
| `parse-decl-attrs` | `extern`/`defvar` take leading attribute keywords |
| `sugar-sweep.py` `child_roles` | its own hand-built table, below |

Only `desugar-form` moved. The qq tables answer a different question (which
template symbols are binders, for hygiene) and know macros the table cannot
(a macro's operand roles are not written down anywhere), so merging them is
not syntactic; RF-7's resolution work is where they meet.

**Where the table and `sugar-sweep.py` disagree**, the table following the
compiler:

1. **`make`**: the Python's `TYPE_OPERAND_HEADS` includes it; it is a library
   macro, so its operands are `SLOT-UNKNOWN` and R4 refuses there.
2. **`cfn`**: the Python reads it as `fn` (params at 1). It is
   `(cfn alloc (params) ret body…)` (`emit-cfn`), params at 2.
3. **The legacy fn-pointer triple `(name (fn R) (P…))`**: the Python reads
   elem 2 as a type `T`; the compiler reads it as a list of parameter types,
   `SLOT-TYPES`. `(f (fn R) (ptr i32))` is two parameters, so R4 must not
   fire there; the table's R4 neither rewrites nor refuses.
4. **`declare` params**: the Python treats `declare` as `defn` (each param a
   binder); the compiler reads a bare param as its type (`SLOT-DECL-PARAMS`).
5. **The `defn` name**: `V` in the Python, `SLOT-BINDER` in the table
   (desugar splits it). R5 cares only about an atom that starts `ref:`/`ptr:`,
   which no `defn` name does.
6. **Coverage**: the Python has no `-` private definers and no `defconst`,
   `deferror`, `defenum`, `if-some`/`when-some`, `set!`/`inc!`/`dec!`,
   `alignof`, `array`, `type-token`; they all fall to `V` there.
7. **Long-form `(quote x)`**: the Python's `Q` comes from the `'` prefix
   only; the table's `quote` row covers both. The corpus's one long form
   (`lib/test.nuc:88`, `(quote ~name)`) is inside a template, so no site
   differs.
8. **`extern` after its binder**: `V` in the Python, `SLOT-UNKNOWN` in the
   table; `qq-ret-index` says a `):Ret` may sit at elem 3, a shape the
   table does not model.

None of 1–8 changes a site in the replay tree (the replay is identical), so
each is a correctness claim about the table, pinned by the units rather than
by replay.

**Deviations, with reasons.**

1. **`desugar` now splits the binder after attributes** (`(defvar :volatile
   trap-zero:i32 0)` in `examples/logic.nuc`), for `defvar` and `extern`. The old code split elem 1 only,
   so an attribute left the binder sugared and every consumer had to split it
   again; the table's `attrs` flag makes the binder the first non-keyword for
   desugar as for `slot-kind`. The IR snapshot shows exactly one artefact
   change, `examples/logic.nuc`'s `.nuch`: `(extern :volatile
   trap-zero:i32)` → `(extern :volatile (trap-zero i32))`, the spelling
   every other generated `.nuch` binder already has. Both spellings compile
   to the same IR (checked with RF-5's and RF-6's compilers). The `.ll`
   artefacts are all byte-identical, as are bootstrap and `--dump-ast`.
   This is the one place the byte-identical gate was not met, and it was
   accepted rather than reproduced: reproducing it would have meant encoding
   the defect beside the table. The orchestrating session accepted it on
   2026-10-16, pending the user's review.
2. **Dropped length checks**: the old `defn` arm desugared only a form of
   ≥ 3 elems and `extern` only one of exactly 2. Now a shorter `defn` has its
   name split too and still reaches its emitter; the suite, rejection
   fixtures included, passes unchanged.
3. **`SLOT-INLINE`** is a table-only slot: an operand of `do` /
   `compile-time` is `SLOT-TOP` when the form is, otherwise `SLOT-VALUE`.
   `slot-kind` never returns it.
4. **Library additions:** `nucleus.slots` (new) and `slot-kind` /
   `rw-slot-path` in `nucleus.refactor`. No change to `defrewrite`,
   `spelled?`, `prefix-form?` or `chain-segments` was needed.

**What the port taught.**

- **A quasiquote template overrides slots, both ways.** The Python treats a
  template as code for R3 and R5 and skips R4 there; the port's `role`
  checks `in-quote?` then `in-quasiquote?` before `slot-kind`. Removing the
  `in-quasiquote?` override rewrites `(~h (ptr Handler))` in
  `lib/error.nuc` and fails replay.
- **Exercised, by weakening each condition and re-running replay:**

  | Weakening | Replay |
  |---|---|
  | `slot-kind` replaced by `SLOT-VALUE` | FAIL: 52 R4 refusals' sites rewritten, the 2 binder refusals lost |
  | no `in-quasiquote?` override | FAIL: a template rewritten |
  | R3 in any role (no pattern/name exclusion) | FAIL: `(circle (ref r))` patterns in `examples/unions.nuc` rewritten |
  | R4 in any non-value role | FAIL: templates rewritten |

  **Not exercised** (replay still PASSes with the condition removed): the
  `in-quote?` override (slot-kind already answers `SLOT-QUOTED`), the
  `FIELD` refusal, the fuse-atom rest check, the `&`-sigil and
  later-segment-sigil checks, the keyword-operand check, R5's skip set,
  R4's value refusal, and R3's splice, marker and literal refusals (zero
  sites). They are kept because the Python states them; the unit
  `rf6-slot-guard` pins the refusal mechanism itself.
- **Counts agree rule by rule**: R3 1,036, R4 52, R5 2,700 (3,788) in both.
  The 2 refusal sites are R5 binders, `ref:StrView` let names at
  `src/nucleusc.nuc:2589` and `:2647` of `0fc4fa9e`.
- **The tree removes most of the Python.** 545 lines of the trimmed Python
  rebuild a tree, quote state and roles that `read-syntax`, `in-quote?` and
  `slot-kind` give; what remains is the rules and five spelling helpers.

**Gates (in the build copy).**

| Gate | Result |
|---|---|
| `make` / `make bootstrap` | pass; stage1.ll == stage2.ll |
| `make test` | 1508 passed, 5 failed: RF-5's 1502 plus the six `rf6-*` units. The 5 are the known `suite-target` datalayout set. |
| `scripts/check-headers.sh` | clean (99 headers); `slots.h`/`.nuch` added, `refactor.h`/`.nuch` regenerated, copied back |
| `ir-snapshot.sh`, snapshot by RF-5's compiler over the final tree, verified by RF-6's | 3285 of 3286 artifacts (545 inputs) byte-identical; the one difference is `examples_logic.nuc.nuch`, deviation 1 |
| `dump-ast-corpus.sh`, the same | PASS: 1815 artifacts byte-identical (605 inputs, 7 rejected by both) |
| `syn-corpus` | 0 failures over 656 files (654 + `slots.nuc`/`.nuch`); 389,163 Syns |
| sugar replay at `0fc4fa9e` (`replay.sh` header; `--a` with `--rules R3,R4,R5`, `--b` under `--run`) | **PASS**: 223 files, 128 changed on each side, 2 refusal sites each |
| list-api replay at `e1952ea3`, `--a` from `95df57b7` with `--apply` | **PASS**: 247 files, 21 changed, 71 refusal sites each |
| ptr replay at `294e4ac2`, `--a` from `6910d81d` with `--in-strings` | **PASS**: 519 files, 77 changed, 0 refusal sites each |

Each unit fails under a deliberate breakage, made in a scratch copy:

| Breakage | Caught by |
|---|---|
| `declare`'s params `SLOT-PARAMS`, not `DECL-PARAMS` | `rf6-slot-definers` |
| `set!`'s target `SLOT-VALUE`, not `PLACE` | `rf6-slot-code` |
| `BoxedFn`'s parameter list `SLOT-TYPE`, not `TYPES` | `rf6-slot-types` |
| a null-node parent answers `SLOT-VALUE` | `rf6-slot-fragment` |
| a fuse's wrapped list kid not found (`rw-slot-path` ignored) | `rf6-slot-types` |
| a call's operands `SLOT-VALUE`, not `UNKNOWN` | `rf6-slot-guard`, `rf6-slot-code` |
| `compile-time` without a row | `rf6-desugar-rows`, `rf6-slot-code` |

**For RF-7.**

- The qq hygiene tables (`qq-binder-slot` and friends) are the second
  per-head table. They are keyed on binders, not slots, and include library
  macros. If resolution needs "is this occurrence a binder", the slot table
  answers it for built-ins; for macros only expansion does, which is RF-7's
  identity problem (desugar and expansion rebuild lists).
- `desugar-form` now rebuilds a list only when some operand changed, as
  before, but through `node-push` into a fresh list: list identity is lost
  for exactly the desugared top-level forms. A (list node, index) report from
  the compiler must map through that.

**For RF-8.**

- `docs/refactoring.md` has the slot vocabulary; `context/refactoring.md`
  should say that a rule caring about position asks `slot-kind`, and that a
  macro call is `SLOT-UNKNOWN` by design.
- `nucleus.slots` is in the compiler's import closure, so a change to it is a
  compiler change: bootstrap, IR snapshot.

### RF-7 — resolution findings (2026-10-16)

The question (§4.7): what does each symbol occurrence resolve to, and can a
tool get that answer from the compiler and map it back to a `Syn`? Citations
are to the tree at RF-6. Measurements were taken in a scratch copy with
temporary instrumentation; none of it is in the tree.

**Correction to the brief.** The `#hN/` hygiene tags no longer exist. AN-4
deleted them, along with `g-hyg-envs`
([ambient-namespaces.md](../stage23-namespaces/ambient-namespaces.md) "AN-4 as
built"). A template data symbol that resolves is now minted as its
definition's full name, `ns/bare` (`qq-full-name`, `src/nucleusc.nuc:13536`).
`NameEnv` (`src/compiler-types.nuc:1314`: ns, path, imports) is still the
per-file environment that a template's text is read in (`name-env-enter`,
`src/union-registry.nuc:1909`).

#### 1. Where names resolve, and what each needs

**There is no resolution pass.** Names are resolved during emission and
again in `node-type` (the lockstep). Each kind of name is resolved by a
different function, and each reads global state that changes as emission
runs.

| Name | Resolved by | Needs |
|---|---|---|
| local (value position) | `emit-symbol-ref` (:4179) → `scope-lookup` (`src/scope.nuc:153`): local frames newest-first by raw name, then the global frame | the `Scope` chain at that point, which exists only while emission is running; `split-typed` for `x:T` in value position |
| local binder | `scope-define` (`scope.nuc:28`), from about 37 sites (`emit-let`, `emit-fn`, params, `match` arms, `with`, `if-some`…) | the emitter's knowledge of where binders sit; `refuse-qualified-binder` |
| head symbol | `emit-list` (:14670): `find-macro` **first** (the `macrolet` stack, then the registry), then special forms, then `binding-find` over the rows of `build-binding-kinds` (:13274): generic, global, protocol, struct, … | everything below; quirks: a macro name beats a local in head position, a generic outranks a local, and a local named `fn`/`vfn`/`mfn`/`cfn` disables that special form (:14809) |
| global | `globals-lookup-ref` (:5723) → `resolve-spelling` (:5653); types walk `name-ref-key-at` (:5812) | `NameEnv` plus the import edges (closure), `g-ns-declared`, privacy keys (`#pN`, `unsafe/import-private`), and registries completed by the whole-graph prescan. Order: own ns → flattened imports → core tier → `user` |
| overload / method | `generic-lookup-ref` gives the set; `emit-generic-call` (:13127) picks the method by **argument types**, once per generic instance | type checking |
| field | `(x 'f)`: the selector is matched by symbol identity in the receiver's `StructDef` (`struct-field-index`, :6546) | the receiver's type |
| union arm | by spelling (`union-arm-index`, `src/union-registry.nuc:1063`; `arm-spelling` strips a qualifier that resolves) | the target union type |
| template symbol (hygiene) | `qq-resolve` (:13804) when the `defmacro` is compiled; it walks the template's own read lists **with (list, index) in hand**; binder slots come from `qq-binder-slot` (:13666) | the macro file's `NameEnv`; `--report-qq-resolution` already prints a per-site record of each decision |

Order-free global resolution means one spelling, in one file, of one kind
resolves the same way everywhere in that file, except where a local shadows
it or overloads are involved. Locals, overload selection and fields depend on
the program point or on types, so only emission can answer them.

#### 2. List identity from reader to resolution

| Stage | Identity |
|---|---|
| reader | one list per occurrence; symbols interned (§3.1) |
| prescans | **re-read** each import (pass 1 `:19501`, pass 2 `:20161`). They register from their own trees. Emission uses `do-import`'s read (`:21379`, `:21504`) or the root's (`:22529`), so a `Syn` table must come from those reads |
| `desugar-form` (:19285) | copies a top-level form only when a binder changes; elem *i* ↔ elem *i*; `x:T` becomes a fresh `(x T)`, whose name is chain segment 0 of the atom |
| `desugar` (:19273), the forms walker | **always rebuilds the spine of a list of ≥ 3 elements.** Its "unchanged" test compares with `(node-rest n)`, and `node-rest` (`lib/nucleus/node.nuc:107`) allocates a fresh view on every call. Measured: all 28,565 emission-path expansions in the self-compile came back from `desugar` as a different list. A defect: it costs identity and a copy, and gains nothing |
| macro expansion | arguments are passed by pointer (`expand-macro-call` :12866), so `~x` keeps x's identity. Template lists are fresh (line 0, then `stamp-macro-lines`, which already treats line ≠ 0 as "a user argument"). A **bare-symbol argument moved into a template list loses its occurrence**. `ct-subst-args` rebuilds the call when it contains `~e` |
| side expansions | `node-type`, the literal tests and `const-fold-int` re-expand (`macroexpand-form` :4247…, `src/generics.nuc:3844`, `:4181`) into trees of their own; 230 extra expansions in the self-compile |
| generic instance | `monomorphize-form` (`src/generics.nuc:3343`) deep-copies the body through `subst-tyvars-node` (`src/type-mangle.nuc:198`), once per instance; a changed symbol becomes a **non-interned** node. A body that is never instantiated is never resolved |
| other | `__make`/`__niche-ctor` rewrites, collection literals, `defconst` copies |

**Measured.** A scratch compiler records the lists every emitting read
produced. At each `emit-list` it classifies the unique list by where it came
from, and at each emission-path expansion it classifies the symbols in the
expansion's fresh lists by how often the name occurs in the call's arguments.

| | self-compile | 182 examples + stage26 tools (closures summed) |
|---|---|---|
| unique lists dispatched | 145,140 | 368,089 |
| — the reader's own | 48.3% (38.8% excluding macro calls) | 72.6% (62.3%) |
| — macro template lists | 25.1% | 6.8% |
| — expansion head, copied by `desugar` | 19.7% | 12.3% |
| — generic instance copies | 5.2% | 5.6% |
| — `desugar-form`, other | 1.7% | 2.7% |
| symbol elems in reader lists | 49.4% (41.2%) | 73.6% (65.1%) |
| emission-path expansions | 28,565 | 45,324 |
| reader subtrees passed through intact | 30,782 | 67,092 |
| fresh-list symbols: name absent from args (template, gensym, minted) | 68.7% | 60.6% |
| — name once in args (attributable) | 20.8% | 25.2% |
| — name more than once in args | 10.5% | 14.2% |

The read side, measured with a census tool over the `Syn` trees
(`slot-kind` per atom; 191,604 symbol atoms in `src/`, `lib/nucleus/` and
`examples/`):

- **48.1% lie inside a library-macro call** (`when`, `if`, `+`, `dotimes`,
  `str`, …), at any depth.
- 19.3% are `SLOT-UNKNOWN` call operands. Syntax cannot tell a function call
  from a macro call.
- 9.1% are typed atoms. A binder's name is a sub-atom span.
- Only **0.23%** share their spelling with a sibling in the same list.

#### 3. Tracing expansions back to source

- **A passed-through subtree keeps its identity.** A list argument that a
  template splices in is the caller's own node.
- **A template symbol is answered where the template is written.** `qq-resolve`
  sees it at (template list, index) in the macro's file, so a reference
  report can record it there. In the expansion it is either a full name, which
  describes its own resolution, or a bare `__gs_N`/template local. Neither has
  a span in the caller, and neither should.
- **A bare symbol moved from the arguments has no identity left.** It can be
  traced back only by name. The trace is sound when the name occurs once among
  the call's arguments and is not one of the macro's bare template literals,
  which `qq-resolve` can list. Otherwise it is ambiguous. One case defeats the
  rule: a body that interns a symbol by computation, which is rare.
  Per-occurrence proxy nodes would make the trace exact, but the
  compiler and macros compare symbol *nodes* by pointer (`(= hp 'let)`,
  `->`'s `'_` test), so proxies change behaviour. This is Q1's rejection
  again.

#### 4. Candidate designs

**(a) A provenance side table kept through copies.** It records fresh → origin
at the three places that copy:

- `desugar-form`: positional;
- `subst-tyvars-node`: structural;
- expansion: pass-through, plus the by-name rule of §3.

It is small and local to each copier, and it is not a design on its own: it
is what lets (b) attribute events in the 27–51% of dispatched lists that are
not the reader's.

**(b) A resolution query in the compiler.** Two forms:

- *(b1) a linked API* that a tool calls on a `SynFile`. Every name it would
  call is a `src/` export, which
  [compiler-api-surface.md](../deferred/compiler-api-surface.md) forbids until
  its policy question D is answered. It would also need the compiler's
  emission state inside the tool's process.
- *(b2) a report mode*, `nucleusc --resolve FILE`. The compiler compiles the
  unit as `--emit-llvm` does and writes one EDN record per occurrence: file
  and byte span, role (binder, ref, head, type, field, arm, macro), and
  target (a local binder's span, or a key plus its definition's span). The
  tool reads it with `nucleus.edn` and joins it on spans with its own
  `SynFile`. Both sides use the one reader, so the spans agree.
  `--diagnostics=edn` and `--report-qq-resolution` are the precedent. The
  boundary is a data format, so nothing in `lib/` links to compiler symbols.

  To build it, the compiler reads in syntax mode for the emitting reads only
  (inert otherwise, as RF-1 measured). An occurrence is (list, index), mapped
  through `syn-kid-for-elem`. Two ways to capture it at a lookup:

  - thread (list, index) into the chokepoints. There are 47
    `(emit-node (node-at x i) …)` sites, about 65 `scope-lookup` sites and
    about 37 `scope-define` sites.
  - a stack of the forms being emitted, with each event attributed by
    searching the top form's subtree. The 0.23% sibling-duplicate rate bounds
    the ambiguity. Events inside `node-type`, `gcheck` and `const-fold` must
    be suppressed, because emission later resolves the same names in the right
    frame.

  Definition spans need the defining form; a `Sym` keeps only
  `src-file`/`src-line` (`sym-record-src`, `scope.nuc:74`).

**(c) A resolver in the tool, without the compiler.**

- *Locals* follow the slot table plus binder rules for macros.
  `qq-binder-slot` already knows `dotimes`, `doseq`, `doseq-iter` and `for`,
  and could move to `lib/` as RF-6 moved the slot table. But half of all
  occurrences sit inside macro calls. A macro's operand roles are written down
  nowhere (RF-6), and syntax cannot tell a call from a macro. So (c) is
  correct only when it hard-codes each library macro and refuses at every
  other macro call.
- *Globals* need `resolve-spelling` and a definitions index of the import
  closure (namespaces, privacy keys, core tier, `user` last). That is a second
  prescan, with the drift RF-6 just removed.
- *Overloads and fields* need types, so (c) cannot resolve them.

**(d) A per-file name dictionary.** Global resolution is order-free per
(file, spelling, kind). The compiler could therefore dump, per file, each
spelling to its key per kind, which is far smaller than per-occurrence data.
The tool then separates local from global lexically, as in (c). This
inherits (c)'s macro problem for locals, so it is a complement to (b2), not a
replacement.

| Refactor | (a)+(b2) | (c) | (d) + tool lexical scoping |
|---|---|---|---|
| rename local | yes; refuses an ambiguous trace | only outside unknown macros | as (c) |
| find references (one unit) | yes, including template sites; uncompiled code listed | locals only | globals by spelling; no overloads |
| rename global across namespaces | yes per unit; qualifiers kept (`p/foo` edits `foo`); `.nuch` regenerated, never edited | no | mostly; misses where a local shadows inside a macro |
| move a definition between namespaces | needs each file's spelling of the new key (`binding-usable-spelling` :13398 already computes it), plus privacy and overload checks; deferred | no | no |
| what none of them reach | uninstantiated generics, code under `#_` or in `.nuch` text, programs inside string literals (RF-5 is syntactic only), other units unless their roots are compiled too, and a field's role as an EDN key (`derive-edn`) | | |

#### 5. Recommendation

**(b2) with (a), at report granularity, with (c)'s lexical rules not built.**
A report keeps the compiler the only resolver and needs no answer to the API
policy. Its spans join with the tool's `Syn` without either side sharing
memory. A tool needs about one second of front end per unit (RF-4).

| Phase | Work | Gate |
|---|---|---|
| RR-0 | `desugar` compares against the rest it was given (or walks by index), so an unchanged expansion keeps its identity | bootstrap byte-identical; IR snapshot unchanged; the probe shows 0 copied expansions |
| RR-1 | `--resolve`: emitting reads in syntax mode, a list→`Syn` table, **definitions only** (each definer's name span → key) | every top-level definer in the corpus mapped; ordinary builds inert (IR snapshot) |
| RR-2 | reference events on reader lists (locals, globals, heads, types, fields), with suppression inside `node-type`; a coverage line (attributed / ambiguous / no span) | a coverage census over the corpus; every event's spelling equals the name segment of its `Syn` |
| RR-3 | (a) through desugar, instances and expansions, with qq-time events for template sites | coverage rises by the measured classes; ambiguity reported, never guessed |
| RR-4 | `nucleus.refactor` reads the report; `rename-local` | **semantic no-op**: rename, then recompile, gives IR equal modulo the renamed `%name`s; rename and back is the identity |
| RR-5 | rename a global within a set of roots; refuse when an occurrence of the spelling has no record | as RR-4, modulo the link name |

Deferred: moving definitions, renaming a field or one member of an overload
set, cross-unit renames without explicit roots, and rewriting programs inside
strings by resolution.

**Scope judgement.** No sweep in §2 needed resolution. Stage 26's goal is
met by syntax, slots and spelling guards. **RR-1…RR-5 should be a stage of
their own**, after RF-8 closes this one. RR-0 is a small, output-neutral
correction of a defect found here, and can land in Stage 26 if the user
wants it.

**Open questions for the user.**

1. Is a compiler *report* mode an acceptable boundary, with an EDN format
   that is unstable and versioned? Or should resolution wait for
   compiler-api-surface.md's policy question D?
2. How should an occurrence be captured: threaded (list, index), which is
   exact and a broad diff, or a form stack with attribution, which is a small
   diff and has bounded ambiguity? The recommendation is to prototype the
   stack in RR-2 and thread only the sites it fails at.
3. When a textual occurrence of the spelling has no record (uncompiled
   code), should a rename refuse? The recommendation is yes.
4. What is a "unit" for a global rename: the roots the caller names, or a
   fixed set (`src/nucleusc.nuc`, `examples/*`, the suites)?
5. Should RR-0 land in Stage 26?
6. Should a later macro facility let a macro declare its operand roles, so
   that (c) and `slot-kind` see past it? The recommendation is to defer it
   and let the report answer instead.

**Rulings (user, 2026-10-18).**

1. A compiler report mode with an unstable EDN format is acceptable for now.
2. Prototype the form stack in RR-2.
3. A rename refuses when an occurrence of the spelling has no record.
4. A global rename's unit is the set of roots the caller names.
5. RR-0 lands in Stage 26. RR-1 … RR-5 stay a later stage.
6. Operand-role declarations for macros are deferred.

### RF-8 — docs and agent context (built 2026-10-16)

- **`docs/refactoring.md`** was checked against `refactor.nuc`, `slots.nuc`,
  `syntax.nuc` and `read.nuc`. Every example ran under `nucleusc --run` and
  matched the text. Fixes:
  - `--dry-run` is now documented;
  - the guard-table headings were reworded;
  - the slot entry points that had no docs (`slot-of-elem`,
    `slots-desugared?`, `form-slots`, `form-slots-of`, `slot-head`) are
    documented;
  - a "refuse rather than guess" paragraph was added.
- **`context/refactoring.md`** is new. Per Q7 it covers `.nuc` and `.nuch`
  only, and it says Markdown, EDN and other text are edited with ordinary
  tools. It covers:
  - when to write a tool;
  - running a tool: a dry run, then `--apply`;
  - the refusal discipline: `:refuse`, `:flag`, `--strict`;
  - spelling guards;
  - `slot-kind`, where a macro call is `SLOT-UNKNOWN` by design;
  - `--in-strings`;
  - where tools live;
  - `replay.sh`.
- **`AGENTS.md`** now lists it.
- **`context/build.md`** gained "Tools and the bootstrap":
  - build a tool to a binary before a migration that breaks the reader
    (§4.8);
  - `slots.nuc` and `syntax.nuc` are in the compiler's import closure,
    `syntax.nuc` through `read.nuc`;
  - only `nucleus.refactor` lies outside it.
- No code changed.
