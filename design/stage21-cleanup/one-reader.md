# Stage 21 — One reader: `lib/read.nuc` is the reader

**Status:** designed 2026-09-16, **built 2026-09-18**. Every file:line in §1 was
re-verified against the tree on 2026-09-16, before R-1 landed; §9's "As built"
records where the built tree diverged. Milestones are **R-1 … R-4**; §8
sequences them against item 1's PK-1 … PK-6, and §2 records the two premises of
the brief that verification corrected.

**Goal.** One reader. `lib/read.nuc` already is a reader with a `Reader` object,
standalone-compilable, used by `lib/test.nuc`, `tests/nuctests.nuc` and
programs; `src/reader.nuc` is a second one, 1,260 lines, whose only structural
reason to exist is that its state lives in five compiler globals. The four
`reader-parity-*` units are the only thing coupling them, and every reader
change since Stage 18 has been written twice (pointer-kind-spellings.md §1.5:
"every reader change below has a twin there"). This item makes the library
reader the compiler's reader, moves the compiler's diagnostics layer out of the
reader file rather than out of `src/`, and deletes the twin.

---

## 1. Ground truth (verified 2026-09-16 against the tree)

### 1.1 The two files

`src/reader.nuc`, 1,260 lines, by section:

| Section | Lines | Notes |
| --- | --- | --- |
| byte helpers `cstr-byte-at`/`text-byte-at` | `:21`, `:26` | byte access over `ptr`/`StrView`; 205 callers outside the file (`src/cheader.nuc` 141, `nucleusc.nuc` 48, `type-utils.nuc` 10, `repl.nuc` 6) |
| **diagnostics** | `:29–192` | `Diagnostic` `:41`, `g-diag-sexp` `:51`, `diag-stage-note` `:56`, `diag-emit` `:154`, `diag-error` `:167`, `die-at` `:173`, `report-at` `:191`. Call sites outside the file: `(die-at ` 686, `(report-at ` 5, `(diag-emit ` 8, `(diag-stage-note ` 9 |
| W4c bracket tracking | `:218–246` | `reader-open-bracket`, `reader-close-bracket`, `report-unterminated`; one-byte lookbehind `:222` |
| char primitives, `lex-string` | `:252–342` | `lex-string` `:290` reads into a **4096-byte alloca** and refuses at 4095 (`:333`) |
| char literals | `:357–446` | `hex-digit-val` `:357` (one external caller, `src/type-utils.nuc:549`), `lex-char-literal` `:371` |
| float/hex classify, sigil, legacy marker | `:448–597` | `ref-sigil-seg-next` `:540`, `expand-ref-sigil` `:545`, `at-legacy-marker` `:580` |
| `lex-int-value`, `lex-atom` | `:598`, `:618` | |
| `next-tok` | `:704` | reader-macro longest-prefix scan over `g-rmacros` `:771–801` |
| `peek-tok`/`eat-tok` | `:830–839` | the one-token lookahead |
| **`lit-*` emit helpers** | `:864–943` | `lit-sym`, `lit-list2/3`, `lit-ref`, `lit-alloca`, `lit-is-quoted-sym`, `lit-elem-kind`, `lit-type-node`; every caller is in `src/nucleusc.nuc:12161–12315` (`collection-lit-value-type-node`, `collection-lit-elem-type`, `emit-collection-lit`) |
| collection-literal reading | `:953–994` | `read-lit-elems` `:953`; `read-vector-literal` `:975`, `read-hashset-literal` `:981`, `read-hashmap-literal` `:988` |
| `read-form` | `:996` | |
| colon-paren fuse | `:1094–1200` | `is-fn-type-form`, `fuse-fn-params` `:1122`, `fuse-colon-paren` `:1129` |
| `read-list`, `read-program`, `read-program-or-die` | `:1202`, `:1220`, `:1257` | |

True reader code (everything but diagnostics, byte helpers and `lit-*`) ≈ 990
lines.

`lib/read.nuc`, 800 lines: nine `deferror`s `:32–40`; `Reader` `:46` (`src pos
line err-line`), `reader` `:52`, `reader-error-line` `:62`; primitives and atom
classification `:65–262` (`rd-hex-val` `:98`, `rd-hex-kind` `:157`,
`rd-float-atom?` `:196`, `rd-int-value` `:237`); sigil and legacy marker
`:264–322` (`rd-seg-next` `:264`, `rd-legacy-marker?` `:271`, `rd-expand-sigil`
`:280`, `rd-at-legacy-marker` `:310`); `rd-string` `:336` into an unbounded
`String`; `rd-char` `:386`; `rd-atom` `:446`; the fixed six reader macros
`rd-macro-name` `:487` (`&` → `"addr-of"` `:494`); fuse `:503–584`
(`rd-fuse-colon-paren` `:527`, adjacency `(rd-peek self)=='('` `:534`);
`rd-list` `:586` (fuse call `:599`); `rd-form` `:606` (collection-literal
refusal `:619–627`); `reader-eof?` `:671`, `read-one` `:677`, `read-all` `:682`;
`sexp-write-string` `:739`, `node-write` `:746`, `node-str` `:779`, `node-eq`
`:786`. Imports `error strview string fmt vector intern node` (`:24–30`).
Consumers: `lib/test.nuc:27,416,554`, `tests/nuctests.nuc:26,1613`,
`tests/readdump.nuc:13`, `examples/read-sexp.nuc:11`; none in `src/`.

### 1.2 The compiler reader's state — the TF-3 ruling's "14 globals"

| Global | Where | What it is |
| --- | --- | --- |
| `g-src` `g-pos` `g-line` `g-peek` `g-peek-valid` | `src/nucleusc.nuc:24–29` | **reader state**. Saved/set/restored by hand at four import sites — `prescan-imported-types` `:17118/17139/17155`, `prescan-imported-signatures` `:17729/17746/17784`, `do-import` `:18899/18914/18926` and `:19029/19050/19066` — set by batch `main` `:20054–20056`, by `repl-preload-prelude` (`src/repl.nuc:1889–1907`, over the literal `"(import-use prelude)"`) and `repl-main` `:1937–1940`; snapshotted by five `ReplState` rows `:1762–1766`; `g-peek-valid` cleared on read error `:1882`, `:1960` |
| `g-paren-depth` `g-form-open-line` `g-col0-open-line` `g-col0-open-depth` | `:43–54` | **reader-internal**: no reader outside `src/reader.nuc`; reset in `read-program` `:1227–1230`. The machinery needs a depth counter, the first top-level open line, the first column-0 open (line, depth) and `src[pos-1]` |
| `g-rmacros` | `:564`, built by `build-rmacros` `:19302` | the reader-macro table; `register-rmacro` `:19286/19294`; extended by `emit-def-rmacro` `:17794`; read by `repl-classify` `src/repl.nuc:161–163` and the `n-rmacros` roster row `:1811` |
| `g-diag-sexp` `g-diag-note` `g-mono-context` `g-interactive` | `reader.nuc:51`, `nucleusc.nuc:374`, `:364`, `:670` | the **diagnostics layer's**, with `g-arena-alloc` and `g-source-path` `:22` (compiler-wide, ~60 sites) |

Five reader, four reader-internal, one table, four diagnostics. A `Reader`
object absorbs the first nine; nothing about the last four is the reader's.

`text-defines-name` (`nucleusc.nuc:3205`) is a *textual* scan because
"re-entering `read-program` from a diagnostic path would clobber g-src / g-pos
/ g-line …" (`:3197–3199`) — a third cost of the global state, noted, not in
scope.

### 1.3 Who reads text

Entry points from outside `src/reader.nuc`: `read-program` — REPL only
(`repl-protect-preload` `repl.nuc:1876`, `repl-main` `:1941`; on `err` they
reset `g-peek-valid` because `report-at` already printed at the fault site);
`read-program-or-die` — the four import sites (`:17146`, `:17753`, `:18921`,
`:19057`) and `main` `:20058`, each `(desugar (read-program-or-die))`;
`hex-digit-val`; `cstr-byte-at`/`text-byte-at`; the diagnostics functions.
`read-form`, `peek-tok`, `eat-tok`, `next-tok`, `read-list` have no external
callers (two comment mentions, `nucleusc.nuc:1824`, `:2195`).

The REPL never reads one form at a time: `repl-read-input` (`repl.nuc:521–577`)
accumulates lines until its own string/comment-aware paren count balances, then
reads the whole buffer. Macros never read text: no `read-*` call in
`lib/macros.nuc` or `lib/node.nuc`; a CT module declares only `nucleus_gensym`
(`nucleusc.nuc:16208`). So text is read at exactly three kinds of site — batch
`main`, the import/prescan sites, the REPL — and always a whole buffer.

### 1.4 `def-rmacro` never worked in a file — because it registers at emit time

`read-program` consumes the whole file before any form is emitted, and the
table is extended by the *emitter* (`emit-def-rmacro` `:17794` →
`register-rmacro`), so a `def-rmacro` in file F can affect only files a *later*
`import` in F reads — which the two prescans already read with the old table —
or a later REPL input. `context/conventions.md:6046–6048` records exactly this
("a `def-rmacro` never affects its own file"). No lib, example or fixture uses
it; its only test is a refusal (`tests/suite-refusals.nuc:403`,
`(def-rmacro ())`). Dispatched in three walks: `nucleusc.nuc:18423`,
`src/nuch.nuc:761`, `src/repl.nuc:928`; reserved in `g-special-form-set`
`:19577`. Documented in `docs/toplevel.md:26`, `docs/builtins.md:121`,
`docs/macros.md:398`, `docs/compiler.md:333,431`, `docs/reading.md:87`.

The defect is *where* registration happens, not the feature. Both top-level
loops are already form-by-form (`read-program` `reader.nuc:1220–1252`,
`read-all` `lib/read.nuc:682–697`), and the prefix scan runs at a token
boundary before `lex-atom` (`next-tok` `:771–801`, longest prefix wins). A
reader that registers `(def-rmacro "p" sym)` *as it reads it* — the readtable
is the reader's, as in every Lisp — makes the form work for the rest of its
file with no emitter involvement at all. The first draft of this document
retired the form; R-1 now fixes it this way (~40 lines, all in the reader).

### 1.5 Allocation and interning are already shared

Both readers build nodes with `alloc-node`/`make-cell` (`lib/node.nuc:9/12`) and
`intern-node` (`:156`, table `g-intern-table` `:123`); symbols through
`symbol-intern`/`symbol-intern-bytes` (`lib/intern.nuc:203/210/178`), which
**copies** the bytes (`intern-alloc-bytes` `:138–148`): `lib/read.nuc:478`
`(intern-node (rd-expand-sigil tv))`, `src/reader.nuc:1060` `(intern-node (t
's))`. A symbol from either reader is the same singleton, so `(= head 'ptr)`
identity holds across them. Compiler-private: `Tok` (`src/compiler-types.nuc:554`,
one `arena-alloc` per token via `alloc-tok` `nucleusc.nuc:1099`) and `RMacro`
(`:1126`). Two comments claim the reader keeps `Node.s` pointers into the source
text (`nucleusc.nuc:16511–16512`, `repl.nuc:576`) — false since interning copies;
the import sites already `(free src)` (`:17153`, `:19061`). The reader is native
code compiled from the prelude's `Node` (`lib/prelude.nuc:27`); the compilation
it performs need not have `Node` registered when it runs (the prelude is
prepended *after* reading, `:20092` → `prepend-prelude-import` `:19931`).

### 1.6 Collection literals: the TF-3 premise is stale

`[1 2 3]` reads as `(vector-lit __gs_N 1 2 3)`, `{:a 1}` as `(hashmap-lit
__gs_N :a 1)`, `#{1 2}` as `(hashset-lit __gs_N 1 2)` (`reader.nuc:975–994`);
the gensym is `nucleus_gensym` (`nucleusc.nuc:1112`, bumps `g-gensym-id`
`:543`). **It is minted after the elements are read**: each reader `try`s
`read-lit-elems` first and calls `nucleus_gensym` while building the head cell,
so for nested literals the inner literal's gensym has the lower number —
post-order, left to right. Since Stage 16 (`collection-literal-variables.md`;
comment `reader.nuc:854–861`) the element-type inference runs at emit:
`lit-elem-kind`/`lit-type-node` are called only from `collection-lit-elem-type`
(`nucleusc.nuc:12184/12197`) inside `emit-collection-lit` (`:12251`),
dispatched by head in `emit-list` (`:12381–12387`); `node-type-call` treats the
heads as unmodelled (`src/generics.nuc:5201–5203`); the heads are reserved
(`:19557`). What the reader still owns is syntax: bracket matching, the element
list, the map odd-count check (`:990`). The one entanglement is the gensym,
minted at read time "so its counter order — and therefore the emitted IR — is
unchanged" (`:860`); `emit-collection-lit` relies on it (`:12254`, "the reader
always puts the gensym here"). `desugar` (`:16641`) walks binding positions only
and by design not expression bodies (`:16637–16640`), so nothing there sees a
literal. `--dump-ast` prints reader output before desugar (`:20062–20068`);
`--emit-nuch` prints macro bodies with `print-node` (`src/nuch.nuc:97/124/135`),
so a body containing `[…]` exports as `(vector-lit __gs_N …)` — no committed
`.nuch` contains one (grepped).

### 1.7 The error model, and what `Err` does not carry

Compiler: every fault site calls `report-at` — `path:line: error: msg` plus any
staged note — and returns `(err! parse-error)` (`reader.nuc:19`). The messages:

| Message | Site | Pinned |
| --- | --- | --- |
| `unterminated list` + note `line N starts a new form in column 0 while K form(s) are still open -- a ')' is probably missing before line N` / `end of file reached with K form(s) still open` | `:1208`, `:242–245` | `tests/manifest/diagnostics.sexp:311–323` |
| `unterminated vector/map/set literal` + the same notes with `']'`/`'}'` | `:961` | `:327–329` |
| `unexpected )` + note `the form opened at line N is already closed -- look for an extra ')' between lines N and M` | `:1016–1020` | `:336–338` |
| `\x escape needs at least one hex digit` | `:321` | `:211–212` |
| `unterminated string literal` `:297`; `unknown escape \c` `:331`; `string literal too long` `:334`; `unterminated char literal` `:376`; the `\u{…}` family `:387–410`; `unknown named char literal '\…'` `:440`; `integer literal out of range` `:652/:675`; `map literal: odd number of elements` `:991`; `unexpected ]`/`}` `:1003/:1006`; `unexpected end of input` `:1070`; `empty segment in colon-chain '…' -- write name:k1:(Type) with no '::'` `:1163` | | not pinned; the reader-error fixtures' stderr is in the IR snapshot (§1.8) |

`lib/read.nuc`: a code plus `err-line`. **`Err` is an id with no payload**
(`docs/errors.md:10`, "a distinct builtin scalar type represented as `i32`") —
by design: it is C-legible as an enum, and it is what lets `!ptr:T` be one
pointer under the ERR_PTR niche (`errors.md:133–137`; `read-one`'s own
`!raw:Node` is exactly that layout). So the variable parts — the escape char,
the named-char spelling, the colon-chain text, the W4c line and depth numbers —
cannot ride `Err`. Nothing reads the W4c globals after a failure; the machinery
is reader-internal.

**They can ride `(Result T E)`, today, with no compiler change.** Probed
2026-09-16 (`scratchpad …/errpayload/probe1.nuc`, `probe2.nuc`; both become
R-4 units): with `(defstruct ReadError code:Err line:i32 msg:CStr)` and
`(defcast ReadError Err read-error-code)` —

| Shape | Result |
| --- | --- |
| `(defn p (n:i32):(Result i32 ReadError) … (return (err (ReadError read-bad-escape 4 c"…"))))` — bare `err`, `err!` and `ok` in return position of a custom-`E` function | target-type against the return type; `docs/errors.md:58–61`'s "use `make`" for custom `E` is stale |
| `(match (p -1) ((err e) (printf "%d %s" (e 'line) (e 'msg))))` | binds the struct; every field reachable |
| `try` in a caller whose return is the same `(Result i32 ReadError)` | propagates the whole value — line and message survive the frame |
| `try` in a `!i32` / `!void` caller | propagates as `Err` **through the `defcast`**: `try` expands to `(return (err! e))` (`src/union-emit.nuc:1753–1757`) and the union-payload slot consults the cast rule, exactly as `docs/types.md:807` says every implicit position does |

The language already has the two tiers: `Err` is the code tier (an id, a C
enum, a pointer niche, zero cost) and `(Result T E)` with a user `E` is the
payload tier, with `defcast` as the bridge between them — Rust's `From`-driven
`?` mapped onto the conversion machinery Nucleus already has. What is missing is
only the sentence in `docs/errors.md` that says so.

### 1.8 Layering and the gates in place

`src/nucleusc.nuc` imports `compiler-types` `:14`, `arena` `:974`, `node` `:980`
(→ `intern`), `vector` `:1006`, `strfmt` `:1017` (→ `string strview fmt io file
intern-str`, `src/strfmt.nuc:25–33`), then `reader` `:1159`, whose header
comment `:1151–1157` says it lives in `src/` *because* it reads compiler
globals. `lib/read.nuc`'s closure is inside the compiler's before `:1159`.
`Makefile:72` `COMPILER_DEPS` is `src/*.nuc lib/*.nuc`; `lib-objs` `:273`
compiles every `lib/*.nuc` standalone; `build/readdump` `:107–110`.
`scripts/stage17/ir-snapshot.sh` snapshots `--emit-llvm`/`--emit-cheader`/
`--emit-nuch` **and their stderr** for every `tests/fixtures`, `examples`,
`lib` file plus two Windows cross-emits per `lib` file; `src/nucleusc.nuc` is
deliberately not an input (`:51–54`) — `make bootstrap` covers it. Imports inline
into the importer's unit, so `lib/read.nuc` is inside the emitted IR of
`lib/test.nuc`, `examples/read-sexp.nuc` and `examples/self-test.nuc`.
`reader-parity-over` (`tests/suite-audits.nuc:284–314`, units `:316–329`) diffs
`--dump-ast` against `readdump` per file and fails on any rejection whose
stderr lacks "collection literals". `node-write` duplicates `fprint-node`
(`nucleusc.nuc:1174`) escape for escape; 21 `print-node`/`fprint-node` call
sites in `src/nuch.nuc` (16) and `src/repl.nuc` (5). `context/macros-jit.md:16`:
a macro body cannot call `die-at`/`report-at` because they live in
`src/reader.nuc`. Prior rulings: Stage 3 planned `lib/reader.nuc`
(`design/stage3-libraries.md:103`); Stage 6 moved it to `src/` as "strongly tied
to compiler internals" (`stage6-libs.md:77`); Stage 18 TF-3 kept two
(`stage18-tooling/overview.md:941–965`) on the two grounds §1.4 and §1.6 show
stale. `scripts/check-repl-roster.py` requires every `ReplState` field but
`globals-len` to be exactly one roster row.

---

## 2. Verdict

It is not necessary for two readers to exist. What kept them apart, in order:
a **structural habit** — reader state in five globals, saved and restored by
hand at every nested read, where a `Reader` object is the ordinary answer and
`lib/read.nuc` already is one; a **premise false since Stage 16** — type
inference in the reader (§1.6); a **feature registered in the wrong place** —
`def-rmacro` extends the table from the emitter, after the file is read, so it
never affected its own file (§1.4; the fix is to register while reading, and
it is part of R-1); and a **misreading of the error model** — that because
`Err` carries no payload, a library reader could not return a located, formatted
message. It can: the payload tier is `(Result T E)` with a user `E`, and
`defcast` bridges it into `!T` callers (§1.7, probed). §2.1 records why that,
and not a fatter `Err` or side fields on the `Reader`, is the design. One
compiler limitation shapes the split without blocking it: macro bodies cannot
call the diagnostics layer (`context/macros-jit.md:16`), so that layer stays in
`src/` and moves out of the reader *file*, not with the reader.

**End state.** One reader, `lib/read.nuc`, ≈950 lines, standalone-compilable,
used by the compiler, by `lib/test.nuc` and by programs; `src/reader.nuc`
deleted; the diagnostics layer in a new `src/diagnostics.nuc` (moved, not
rewritten); the reader-macro table a `Reader` field (`RMacro` and its builder
move into `lib/read.nuc`; `def-rmacro` registers at read time and works);
`Tok`, `alloc-tok`, `emit-def-rmacro`, `g-rmacros`, `g-src`, `g-pos`,
`g-line`, `g-peek`, `g-peek-valid`, the four W4c globals and five `ReplState`
rows gone; net ≈ −850 lines.

### 2.1 The error value: why `ReadError`, not side fields and not a fatter `Err`

The reader must hand its caller a line, a message with variable parts, and
sometimes a note. Three ways to do that were weighed; the first draft of this
document chose the first, and the probe in §1.7 retired it.

**A. Side fields on the `Reader`** — `err-msg`/`err-note` beside the existing
`err-line`, read back through accessors after a failure. This is `errno` with
an object instead of a global, and it is Zig's design (`std.zig.Ast` collects
errors into a list the caller inspects) — a pedigree, but Zig has no other
channel and Nucleus does. Its costs are the shape it forces on everything
around it: the context dies at the first `try` (a caller two frames up gets
`read-bad-escape` and no line unless the `Reader` is threaded up with it); the
API had to be reshaped to reach the fields (`read-all` split into `read-forms`
over a caller-owned `Reader`, which then needs a `drop` for the owned
`String`s); and every library with a rich error reinvents the same three
fields with no shared shape. A workaround, with nothing in the language that
needed working around.

**B. A payload in `Err` itself** — `{id, detail}` or `{id, line, msg}`. This
spends the two properties `Err` was built for: C sees an `int32_t` enum
(`errors.md:126–142`), and `!ptr:T` is a single pointer under the ERR_PTR niche
(`:133`) — a fat `Err` cannot live in a pointer's top page, so every `!ptr:T`
in the tree becomes a tagged struct and every C signature over one changes. It
also makes payload ownership every `match` arm's problem, since a message that
is not static must be owned by someone. `deferror` would grow fields to give
the payload structure. All of that buys a tier the language already has under
another name.

**C. A typed error value through the existing template** —
`(Result raw:Node ReadError)`, with

```lisp
(defstruct ReadError code:Err line:i32 msg:StrView note:StrView)
(defcast ReadError Err read-error-code)      ; (e 'code)
```

`msg`/`note` are arena-allocated like the nodes they describe, so
`docs/reading.md:47`'s rule stands unchanged — nothing here is owned, nothing
is dropped. `code` keeps the nine classes a program `match`es on. A caller that
returns `(Result … ReadError)` keeps the whole value through `try`; a caller
that returns `!T` gets the class code through the `defcast`, automatically, at
the `(return (err! e))` `try` expands to; the compiler's shim reads
`line`/`msg`/`note` off the value and renders them. No `read-forms`, no `drop`,
no accessors, no compiler change: everything in §1.7's table compiles today.

The principle, which is the language's and not this document's: **`Err` is
the code tier and `(Result T E)` is the payload tier; `defcast` is the bridge.**
A library whose failures carry context returns its own `E` and registers one
cast to `Err`. `docs/errors.md` should say this in so many words (§7), because
its current guidance — `make` for custom `E`, no mention of `try` across the
cast — is what made the first draft reach for side fields.

**Two premises the research brief got wrong, corrected here.** (1) The IR
snapshot never contained `build/nucleusc.ll`, and because imports inline, the
artifacts that legitimately move are those of `lib/read.nuc` and its three
importers (§1.8), not `lib/read.nuc`'s alone — §6 states the exact exception
list. (2) `read-all` keeps its `Reader` private (`docs/reading.md:44`) — which
the side-field draft had to work around and the typed error value does not.

---

## 3. R-1 — the library reader grows to the compiler's feature set

Still standalone; every message the compiler prints today reproduced verbatim.

**Collection literals** (~40 lines). `[…]` → `(vector-lit e…)`, `{…}` →
`(hashmap-lit k v …)`, `#{…}` → `(hashset-lit e…)` — **no gensym element**.
Elements are read through `rd-form` with no fuse, as `read-lit-elems` reads
them through `read-form` today (`:965`). The map odd-count refusal;
`unterminated vector/map/set literal` with the W4c note naming `']'`/`'}'`;
`unexpected ]`/`}` at form position. The refusal at `rd-form:619–627` and
`read-collection-literal` go; the odd-count case takes its place as
`read-map-odd`, and `read-bad-rmacro` joins for the five `def-rmacro`
refusals (below), so the codes are ten and a program can still `match` on
every class the reader refuses.

**W4c tracking as `Reader` fields** (~50 lines): `paren-depth`,
`form-open-line`, `col0-open-line`, `col0-open-depth`; the lookbehind is
`(rd-at self (- pos 1))`. Maintained where the compiler's `next-tok` maintains
them — at each bracket the reader consumes — and reproducing the three pinned
note texts exactly, including the "`)` at negative depth" distinction
(`:1009–1016`) that decides whether `unexpected )` carries a note.

**The error value** (~40 lines): `read-one` and `read-all` return
`(Result raw:Node ReadError)` instead of `!raw:Node`, with

```lisp
(defstruct ReadError code:Err line:i32 msg:StrView note:StrView)
(defn read-error-code (e:ReadError):Err (return (e 'code)))
(defcast ReadError Err read-error-code)
```

(§2.1). Every fault site returns `(err (ReadError code line msg note))` with
`msg` worded exactly as `src/reader.nuc` words it today (table in §1.7) and
`note` empty unless the site stages one (W4c, `unexpected )`). The strings are
built into the **arena** — the reader's allocator for everything it returns —
so `docs/reading.md:47` stays true: nothing is owned, nothing is dropped, and a
`Reader` needs no `drop`. `err-line` and `reader-error-line` go: the line is in
the value. `string literal too long` is not among the messages: the library
already reads into a `String` (`:336`), and the cap goes with the alloca
(below). The ten `deferror` codes stay as the `code` field's vocabulary — a
program still `match`es `(e 'code)` against them, and `lib/read.nuch` exports
the struct, the cast and the codes together.

**`read-all` is unchanged in shape** — it still builds and discards its own
`Reader` — because the value it returns now carries everything a caller needs.
(The first draft split it into `read-forms` over a caller-owned `Reader` to
reach side fields; §2.1 says why that is gone.) Consumers that `match` on the
error today (`lib/test.nuc:27,416,554`, `tests/nuctests.nuc:26,1613`) read `(e
'code)` where they read `e`; a consumer that `try`s into a `!T` function needs
no edit — the cast does it.

**Reader macros: the table is the `Reader`'s, and `def-rmacro` registers at
read time.** `Reader` gains `macros:ref:(Vector RMacro)` (`RMacro` =
`prefix:StrView wrap:Symbol`, moved from `nucleusc.nuc:19286–19313`); `reader
src` seeds a fresh arena table with the six built-ins (the `&` row is `"ref"`
by the time this lands — PK-1, §8), and `reader-with-macros src table` shares a
caller-owned one. `rd-macro-name`/`rd-macro-len` (`lib/read.nuc:487–499`)
become the longest-prefix scan `next-tok` does today (`reader.nuc:771–801`),
over the field. `read-one` — not `rd-form` — recognises a top-level
`(def-rmacro "p" sym)` after reading it and calls `rd-register-macro` before
returning it, so the next form read through the same `Reader` sees the prefix;
`read-all` loops over `read-one`. The form stays in the output list (round-trip
printing, `--dump-ast`); the three emitter arms (§1.4) become no-ops behind the
reserved head (`g-special-form-set` `:19577` keeps it so the head cannot be
shadowed) and `emit-def-rmacro` goes.

*Scope.* File-scoped and forward-only: a `Reader` is built per file
(`read-source-or-report`, R-2), so a `def-rmacro` affects the forms after it in
its own file, not an importer, an import, or a header. Today's accidental
cross-file effect (§1.4) was order-dependent and unreachable through the
prescans, so nothing loses it; exporting a reader macro across files is a
separate feature, not designed here. The REPL owns a session table
(`repl-rmacros`, seeded once) and builds each input's `Reader` with
`reader-with-macros`, so a `def-rmacro` at the prompt persists to the next
input exactly as it does today; `repl-classify` (`src/repl.nuc:161–163`) and
the `n-rmacros` rollback row (`:1811`, truncate on rollback) read that table,
so `(kind-of "'")` (`tests/repl/meta-introspection.in`) is unchanged and
`ReplState` loses five rows, not six.

*Refusals*, all `ReadError`s at the form's line, the first three reproducing
`emit-def-rmacro`'s texts verbatim so `suite-refusals.nuc:403` is unchanged:
`def-rmacro: expects (def-rmacro "prefix" symbol)`; `… prefix must be a
string`; `… wrap symbol must be a symbol`; **new** — `def-rmacro: 'p' is
already a reader macro` (the six built-ins included), and `def-rmacro: prefix
must not begin with a byte that can start an atom` — the emit-time version had
no guard, so `(def-rmacro "my" w)` silently read `myvar` as `(w var)` and
`(def-rmacro "<" w)` broke `<=`; the test is the lexer's own atom-start
predicate, which also refuses the `?`/`!`/`&` sigils, digits, signs, `#`, and
the delimiters. One `deferror` for all five: `read-bad-rmacro`.

**The string-literal cap goes with the alloca.** No other 4095 on a string path
exists in `src/` (grepped: the remaining hits are the `deferror` id cap and
`:align`), and `Symbol` carries its own length. R-1's gate is the probe, not the
grep: a program with a >4095-byte literal compiles, prints it, and exports it
through `--emit-nuch` and `--dump-ast`. If it does, the deferred item "String
literal limit" (`design/deferred/overview.md:175`) closes with this item; if
something else caps it, record where.

**`hex-digit-val`**: its one external caller (`src/type-utils.nuc:549`) switches
to `rd-hex-val` (`lib/read.nuc:98`, same contract: 0–15 or −1).

**No token layer.** The character-level design is kept; the fuse's adjacency
test stays `(rd-peek self)=='('` with no peek gate — the compiler's
`g-peek-valid` gate (`:1131`) exists only because its reader has lookahead. PK-2's
later change — gate on an open final segment, move the call from `rd-list:599`
into `rd-form` — is then made in this one file (§8).

**Line attribution** already agrees (spine-cell rule `read-program:1241–1246` ≡
`read-all:687–692`; a string blames its opening line in both). `--dump-ast`
prints no lines, so the gate for it is `make test`'s pinned reader rows and
`run_no_line_zero`.

---

## 4. R-2 — the compiler adopts it

In order:

**(a) Split `src/reader.nuc`.** Diagnostics `:29–192` → `src/diagnostics.nuc`,
imported at `:1159` where `reader` was, code unchanged (`Diagnostic`,
`g-diag-sexp`, `diag-*`, `die-at`, `report-at`); the `error` import and the
`parse-error` deferror go with it only if a caller still needs them (the reader
no longer does). `lit-*` `:864–943` → beside `emit-collection-lit` in
`src/nucleusc.nuc`. `cstr-byte-at`/`text-byte-at` → a `src/` home the
implementer picks (they are byte access over `ptr`, 205 callers, not `lib/`).

**(b) `(import-use read)` at `:1159`**, replacing the header comment
`:1151–1157` with one line saying why the diagnostics stay in `src/`.

**(c) One shim, ~30 lines, in `src/`.** `read-source-or-report
(text:StrView):!raw:Node` calls `read-all` and `match`es: on `(err e)` it
renders the value through the diagnostics layer — `(when (not (str-empty? (e
'note))) (diag-stage-note (e 'note)))`, `(report-at (e 'line) (e 'msg))` — so
every message in §1.7 prints as it does today, then returns `(err!
parse-error)` as `read-program-or-die`'s callers expect. On `(ok forms)` it
runs **`mint-collection-gensyms`**: a
walk over the tree that inserts a fresh `nucleus_gensym` node as the second
element of every `vector-lit`/`hashmap-lit`/`hashset-lit` cell, **post-order,
left to right** — elements first, then the literal — which is the order the
reader mints today (§1.6). Same order, same counter, same point in the
compilation (immediately after each buffer is read, before anything in that
buffer is emitted or expanded), so every program's IR, the compiler's own
included, is byte-identical and this milestone needs no boot refresh. The walk
must not descend into a `quote`d form differently from the reader — the reader
minted inside quoted data too, so the walk mints everywhere. A batch wrapper
`read-source-or-die` keeps `read-program-or-die`'s `exit 1`. `main`'s `src` is
a `ptr` from `read-file` (`:16513`); the shim views it with `strview-from-cstr`,
and the reader's NUL-is-end rule (`lib/read.nuc:68–69`) matches the compiler's
sentinel.

**(d) Replace the read sites.** The five `read-program-or-die` sites and the two
REPL `read-program` sites call the shim. At the four import sites the
save/set/restore of the five reader globals goes; the other four saved globals
(`g-source-path`, `g-current-ns`, `g-ns-seen`, `g-file-imports`) stay — they
are not reader state. A nested read is now a `Reader` in the callee's frame.
The REPL builds a `Reader` over its balanced buffer with `reader-with-macros`
and its session table (`repl-rmacros`, the moved `g-rmacros`) and on error
resets nothing; `repl-preload-prelude` loses its five-line save/restore
(`:1889–1907`); `ReplState` loses **five** rows — `src pos line peek
peek-valid` (`:1762–1766`); `n-rmacros` (`:1811`) stays and snapshots the
session table — and `scripts/check-repl-roster.py` passes because the struct
and the roster move together.

**(e) Delete** `src/reader.nuc`, `Tok`, `alloc-tok`, `emit-def-rmacro`,
`g-rmacros` (`RMacro`, `build-rmacros` and `register-rmacro` move to
`lib/read.nuc` as the table's seed and `rd-register-macro`), `g-src`, `g-pos`,
`g-line`, `g-peek`, `g-peek-valid`, the four W4c globals and their comment
block (`:31–54`). Fix the two "pointers into the source" comments
(`:16511–16512`, `repl.nuc:576`) and `emit-collection-lit`'s "the reader always
puts the gensym here" (`:12254` — the shim does, until PK-5). The
`text-defines-name` rationale (`:3197–3199`) is now false; reword the comment,
leave the scan.

**(f) `--dump-ast` stays**, printing what the shim returned — gensyms included —
so its output is byte-identical to today's over the whole corpus, which is what
makes it the R-4 instrument. **Immediately before PK-5's boot refresh**
(pointer-kind-spellings.md §9 step 2), `mint-collection-gensyms` is deleted and
`emit-collection-lit` mints the gensym itself at `:12254`. The deletion cannot
be fixed-point-preserving — the boot mints at read time, the new compiler at
emit time, so `stage1.ll` and `stage2.ll` differ in `__gs_N` numbering and
nothing else — which is why it goes *before* the refresh, not after: the gate
for that one commit is Stage 20 S1's (normalise `__gs_N`, diff, require
identity), and the refresh that follows absorbs the renumbering together with
`(ref x)`. Deleting it after the refresh would leave the bootstrap diverged until
the next one. The ten collection-literal files' `--dump-ast` baseline is retaken
at that commit, losing the `__gs_N` element.

---

## 5. R-3 — one printer (separable)

`fprint-node` (`nucleusc.nuc:1174–1222`) and `node-write` (`lib/read.nuc:746`)
are the same function twice, escape for escape; the three Stage 18 printer
bugs (`stage18-tooling/overview.md:967–984`) were each fixed in both. Either
`fprint-node` becomes a wrapper — `node-write` into a `String`, `emit` it — or
the 21 call sites in `src/nuch.nuc`/`src/repl.nuc` and the `--dump-ast` loop
(`:20065`) move to `node-write`, and `fprint-node`/`print-node` go. The three
bugs are then pinned by R-4's round-trip unit rather than by a second
implementation. Gate: `scripts/check-headers.sh` byte-identical — the printer's
output is committed in `lib/*.nuch`.

---

## 6. R-4 — gates and tests

1. **The corpus gate.** `--dump-ast` over every `.nuc` in `tests/fixtures`,
   `examples`, `lib`, `src`, captured with the pre-R compiler (stdout and
   stderr) and diffed after R-2: byte-identical, including the ten
   collection-literal files the library reader used to reject and the six
   reader-error fixtures' stderr.
2. **`ir-snapshot.sh snapshot` before, `verify` after.** Every artifact
   byte-identical except those whose unit *contains* `lib/read.nuc`: its own
   `.ll`/`.nuch`/`.h`/`.win-*.ll` (the code changed; `.nuch` because `Reader`
   gained fields), and the `.ll` of `lib/test.nuc`, `examples/read-sexp.nuc`,
   `examples/self-test.nuc`. Any other difference is a bug. The compiler's own
   IR moves because its reader code moved; what must not move is what it
   *emits*, which is the snapshot's whole point.
3. **`make bootstrap`** converges with no boot refresh (§4c is the argument).
4. **`make test`** — every pinned reader diagnostic in
   `tests/manifest/diagnostics.sexp` (rows 211–212, 311–338) unchanged;
   `run_no_line_zero`; `tests/repl/meta-introspection.in`.
5. **Retire the parity machinery.** The four `reader-parity-*` units,
   `reader-parity-over`, `dump-ast`/`read-dump` (`suite-audits.nuc:263–330`),
   `tests/readdump.nuc` and the `READDUMP` target (`Makefile:104–110`) go,
   replaced by one unit `reader-printer-roundtrip` over the same corpus:
   `read-all` → `node-write` → `read-all` → `node-eq`, the shape
   `examples/read-sexp.nuc:59–65` already has, in-process (no spawn).
6. **New units**, in `tests/suite-s21.nuc` (PK-6 creates it; create it here if
   R lands first): a >4095-byte string literal compiles and prints (the R-1
   probe, pinned); **`s21-def-rmacro`** — a file with `(def-rmacro "$" w)`
   reads `$x` after it as `(w x)` and `$x` *before* it as the symbol `$x`
   (forward-only, pinned), through `--dump-ast` and through a program's
   `read-all`; a second file in the same compilation is unaffected
   (file-scoped); `(def-rmacro "~" w)` → `already a reader macro`,
   `(def-rmacro "my" w)` → `must not begin with a byte that can start an
   atom`, `(def-rmacro ())` (`suite-refusals.nuc:403`) unchanged; a
   `tests/repl/` case defines at one prompt and uses at the next;
   `[…]`/`{…}`/`#{…}` read by a *program* through `read-all` into
   `(vector-lit …)` with no gensym; **`s21-typed-error-propagation`** — §1.7's
   two probes as one unit: a custom-`E` function's bare `err`/`err!`/`ok`
   target-type, `match` binds the struct, `try` keeps the value into a same-`E`
   caller and converts through the `defcast` into `!i32` and `!void` callers;
   **`s21-read-error-value`** — a program reading `"(a \\q)"` gets `code`
   `read-bad-escape`, the line, and the message `unknown escape \q` off the
   value, and a `!void` wrapper that `try`s it returns `read-bad-escape`; a
   nested-import syntax error reports at the
   imported file's line and path, and the importer's diagnostics after it are
   still attributed to the importer (the stack-scoped `Reader` replacing the
   save/restore); `unexpected )` at top level carries its note and inside an
   unclosed `[…]` does not.
7. **`make lib-objs`** still builds `lib/read.nuc` standalone.

---

## 7. Docs, landing with the code

| File | Change |
| --- | --- |
| `docs/reading.md` | collection literals now read (the table gains a row; "What it does not read" goes, and with it the parity paragraph `:91–94`); `read-one`/`read-all` return `(Result raw:Node ReadError)` — the struct, its arena-owned strings, the `defcast` to `Err`, `match` on `(e 'code)`, `try` into a `!T` caller; `reader-error-line` gone; `def-rmacro` read here — file-scoped, forward-only, the two new refusals; ten codes with `read-map-odd` and `read-bad-rmacro` |
| `docs/errors.md:51–61` | state the two tiers and the bridge (§2.1): a custom `E` is constructed with bare `ok`/`err`/`err!` in return position (the "use `make`" sentence is stale — probed), `match` binds it, and `try` propagates it into a `!T` caller through a `defcast E Err` rule; `lib/read.nuc`'s `ReadError` as the worked example |
| `docs/toplevel.md:26`, `docs/builtins.md:121` | the `def-rmacro` row gains scope (its own file, forms after it; the REPL session) and the prefix rule; the built-in list says `ref`, not `addr-of` |
| `docs/macros.md:398`, `docs/compiler.md:333,431`, `docs/builtins.md:38` | still true; `compiler.md:431`'s "a reader directive" now literally so |
| `context/conventions.md:6046–6048` | "`def-rmacro` cannot do this from source" is false after R-1 — replace with one sentence: it can, file-scoped, because the reader registers it |
| `docs/compiler.md` flag table | has no `--dump-ast` row today (the flag is documented only in `reading.md:58`); add one: the reader's tree before `desugar` and the prelude, one form per line |
| `docs/compiler.md:335` | "The reader rejects `#<...>` syntax with a clear error" is false in both readers (`#<ptr` reads as a symbol); delete the sentence |
| `docs/testing.md` | parity units → the round-trip unit; `readdump` gone |
| `context/conventions.md:6534` section | replace with one paragraph: the reader is `lib/read.nuc`; the compiler's diagnostics live in `src/diagnostics.nuc`; a reader error reaches the compiler as a `ReadError` value (`code line msg note`, arena-owned strings) and is rendered by `read-source-or-report` — a new reader diagnostic is a new `msg` wording in `lib/read.nuc`, not a `report-at`; a library whose failures carry context returns its own `E` and one `defcast E Err`, never side fields. In the `print-node` section (`:6510–6531`) the "second implementation" sentences become "the round-trip unit reads the output back" |
| `context/macros-jit.md:16` | `src/reader.nuc` → `src/diagnostics.nuc` |
| `context/build.md:4–5,24` | the reader bullet is history (rewrite to "diagnostics in `src/diagnostics.nuc`; the reader is `lib/read.nuc`"); the 4095-byte cap bullet goes — no `docs/*.md` states the cap (grepped), so the docs need no row for its removal |
| `design/stage18-tooling/overview.md` §T6.3 | an **Update** line after "As built": both grounds for two readers were stale; one reader since Stage 21 (this document) |
| `design/deferred/overview.md:175` | "String literal limit" → `done.md`, if R-1's probe confirms the cap was only the reader's |
| `design/stage21-cleanup/pointer-kind-spellings.md` §8 | `s21-matrix-compiles` no longer needs its source split under a 4095-byte cap |

---

## 8. Sequencing against item 1

**Order: PK-1 → R-1, R-2 (R-3 optional) → PK-2, PK-3, PK-4a → delete
`mint-collection-gensyms` → boot refresh → PK-5 (sweep script and retirement)
→ PK-4b, PK-6.**

- **PK-1 first.** It is a one-line reader change (`"addr-of"` → `"ref"` in
  both tables) plus the value-path arms, and it stops the header leak (H4) now;
  not worth holding behind R.
- **R before PK-2.** PK-2 is structural in the reader — the open-segment gate,
  the segment split, moving the fuse call from list reading into form reading —
  and would be written twice and then ported. Once, in the unified reader, is
  the whole point of the remark that "there may be cause to stage that first".
- **R before the boot refresh.** R is fixed-point-preserving on its own (the
  gensym walk, §4c), so it does not need the refresh PK-5 needs; landing it
  before means the walk can be deleted as the last commit before that refresh
  (§4f) and the one refresh absorbs the gensym renumbering too.
- **The R-4 corpus gate pays twice.** `--dump-ast` identity over the corpus is
  exactly the instrument PK-2 wants afterwards (its §4 promises zero in-tree
  spelling changes meaning); build it first.

**What would reverse the decision.** If R-2 stalls — the REPL or the import
paths turn out to hold reader state this research did not find — PK-2 proceeds
in both readers with the twin edits pointer-kind-spellings.md §4 already
specifies, and R lands after PK-5 instead, absorbing the port.

Every step ends with `make test` and `make bootstrap`.

---

## 9. Gates

* R-2: `--dump-ast` over the whole corpus byte-identical (stdout and stderr)
  against the pre-R capture; `ir-snapshot.sh verify` clean except the four
  units named in §6.2; `make bootstrap` byte-identical with no boot refresh;
  `make test` green, the pinned reader rows unchanged.
* R-1: `make lib-objs` builds `lib/read.nuc` alone; the >4095-byte literal
  probe passes end to end (compile, print, `--emit-nuch`, `--dump-ast`).
* R-3: `scripts/check-headers.sh` byte-identical; `reader-printer-roundtrip`
  green over the corpus.
* `grep -rn "def-rmacro" src` hits only the three no-op arms and the
  special-form roster; `lib/read.nuc` owns it; `grep -rn "g-src\b\|g-peek\|g-rmacros\|alloc-tok"
  src` empty; `src/reader.nuc` absent from the tree and from `git ls-files`.
* `context/conventions.md` has no "second reader" section and
  `context/macros-jit.md:16` names `src/diagnostics.nuc`.

---

## 10. As built (2026-09-18)

Corrections to the design above, found while landing R-1 … R-4. Facts only.

* **`ReadResult`, not `(Result raw:Node ReadError)`.** §2.1's probe was on
  `(defstruct ReadError code:Err line:i32 msg:CStr)`, not the shipped
  `StrView`-carrying struct, and did not stamp the template over a `raw`
  payload. A template stamp re-spells every pointer kind as `ptr:`
  (`type-spelling`), so `(Result raw:Node ReadError)`'s `ok` arm refuses
  `null`. Shipped as a hand-written `(defunion ReadResult (ok v:raw:Node)
  (err e:ReadError))`, which `try`/`match`/`unwrap` treat as a Result because
  `result-union-of` is structural, not template-instance-only. Filed as its
  own deferred item: `design/deferred/overview.md`, "A template stamp loses
  the pointer kind".
* **`coerce-via-cast-rule` passed a struct first-class instead of byval.**
  §1.7's probe (a 16-byte `ReadError` shape) was a false positive: a 16-byte
  struct survived the bug by register coincidence, and the shipped 40-byte
  `ReadError` segfaulted through the same `defcast E Err` path `try` uses to
  reach a `!T` caller. Fixed to go through `abi-arg-frag`/`abi-emit-struct-call`
  like every other call, not scoped to the reader.
* **Shim signature is `read-source-or-report (text:StrView (table (ref
  (Vector RMacro)))):!raw:Node`**, not the one-argument form §4c sketches —
  the REPL's session table has to reach it on every call.
* **`read-file` returns a `String`** (`src/nucleusc.nuc:16517`), not the `ptr`
  §4c's `strview-from-cstr` step assumed; the shim views it with
  `string-as-view`.
* **`w45-empty-name-def-rmacro` (`tests/suite-refusals.nuc`) re-pointed**,
  not left unchanged as §6.6 assumed: registration is now a read-time syntax
  matter, so a malformed `def-rmacro` is refused alike by `--emit-cheader`/
  `--emit-nuch` too, not only `--emit-llvm`.
* **The atom-start rule as built**: a prefix may begin only with one of the
  eight bytes no atom starts with — `` $ ' , @ ^ ` | ~ `` — rather than an
  enumerated blocklist; every other first byte (letters, digits, signs,
  `?`/`!`/`&`/`#`/`:`/`.`, an operator character, a delimiter, or an empty
  string) is refused.
* **§6.6's "the importer's diagnostics after it are still attributed to the
  importer" is unobservable in batch** — the first reader error exits the
  process, so there is no "after it" to observe. The REPL shape is what R-4's
  `s21-read-error-value` unit pins instead. Landing this also fixed a
  pre-existing bug the design did not anticipate: a syntax error inside an
  *imported* file used to kill the whole REPL session; `read-source-or-die`
  now `repl-throw`s when interactive, exactly like `die-at`, so the session
  recovers, a retry re-reports the same diagnostic, and an unrelated import
  afterward still works.
* **`check-golden-in` (`tests/nuctests.nuc`) removed** along with its only
  caller, the retired `reader-parity-over`.
* **PK-1 had not landed when R started.** The `&` reader-macro row is still
  `"addr-of"`, in one place now (`read-macro-table-new`, `lib/read.nuc`)
  instead of two.
* **Snapshot gates re-baselined** at the end of R-4:
  `scripts/stage21/dump-ast-corpus.sh snapshot --force` → 457 inputs (6
  rejected), 1371 artifacts; `scripts/stage17/ir-snapshot.sh snapshot --force`
  → 439 inputs, 2720 artifacts; both `verify` PASS. Before the re-take the
  only differences from the prior baseline were the R-edited sources and
  exactly the ten `lib/read.nuc`-containing IR artifacts §6.2 predicts.
  `scripts/stage21/dump-ast-corpus.sh` is new — the §6.1 corpus gate, and also
  PK-2's instrument.
* **`make test`: 1048 passed** (was 1046) — the reader-parity/`readdump`
  retirement and the four new `suite-s21.nuc` units roughly offset.
  `make bootstrap` byte-identical throughout; no boot refresh needed.
