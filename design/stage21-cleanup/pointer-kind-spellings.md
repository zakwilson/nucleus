# Stage 21 — Pointer-kind and type-sigil spellings: make the sugar general

**Status:** designed 2026-09-16; **PK-1 built 2026-09-18** (after item 2, so
the reader edit is the one `&` row in `lib/read.nuc`'s `read-macro-table-new`
and there is no twin; `.ll` artifacts that *contain* the reader — `lib/read.nuc`,
`lib/test.nuc` and their importers — move by that one string constant, which §9
step 1's "no `.ll` differs" did not foresee; the value-path reach list needed one
site §3 missed, `emit-callable-value`'s `q:(ref T)` annotation guard, which
`(cb &x)` now reaches; see progress.md). **PK-2 built 2026-09-18**, made once in
`lib/read.nuc` (the only reader since item 2): `rd-open-segment?` is the gate,
the split strips one trailing `:`, and the call moved from `rd-list` into
`rd-form` (`rd-atom-form`); `dump-ast-corpus.sh verify` moved no input but
`lib/read.nuc` itself, confirming §1.5's census. **PK-3 and PK-4a built
2026-09-18** (§5, §6a; the near-miss and the line-0 discipline reached five
emitters and three `node-type` mirrors, not `emit-alloca-form` alone — `as`,
`cast`, `sizeof` and `array` passed the interned atom's line too; `tyname-resolvable`
still does not consult `deftype` aliases or C typedefs, so a bare alias name in a
template argument is the same fake-tyvar shape as H5, out of this item's scope —
see progress.md). **§9 step 2 done 2026-09-18**: `mint-collection-gensyms`
deleted (one-reader.md §4f, §10), the `__gs_N`-normalised identity gate held
with `ir-snapshot.sh` moving nothing, and `make update-bootstrap` taken —
`boot/nucleusc.ll` and both Windows boot IRs now read `(ref x)`, `(ref p 'f)`
and the sigil-paren forms, so PK-5 may rewrite `src/`; the step-2
`build/nucleusc.ll` is PK-5a's byte-identical baseline (progress.md, "Boot
refresh for Stage 21"). **PK-5a built 2026-09-18**: `scripts/stage21/sugar-sweep.py`
swept 134 files to a fixed point (4,985 rewrites, 18 refusals); the compiler's
`.ll` is byte-identical modulo the two prescribed local renames (a local's name
is its alloca's name — §7's "byte-identical" holds only after the rename is
undone in the text), every other `.ll` byte-identical, 47 `.nuch` + 18 `.h`
spelling-only. Four refusal classes §7 did not name — a sigil over a **type
variable** (`?E` is a bare symbol; `subst-tyvars-sym` walks colon segments),
`(Maybe (raw T))` (value-Maybe ≠ `?raw:T`), a paren operand in an **exported**
slot (the cheader classifiers read a `(Maybe …)`/`(Result …)` head, not a
`(? X)`/`(! X)` cell — §5's "walkers need no change" was one face), and an
`extend` subject — are in §7. **PK-5b built 2026-09-18**: the four cell-building
sites mint `ref`; every `addr-of` reading arm is gone (`emit-list`, `node-type`,
`fn-rewrite-captures`, `defvar-init-ir`, `defvar-check-init-order`,
`gcheck-special-form`); `emit-addr-of`/`node-type-addr-of`/`defvar-addr-of-ir`
are `emit-ref`/`node-type-ref`/`defvar-ref-ir` and their nouns say `ref`;
`retired-form-message` has the row, and — beyond §7's list — `gcheck`'s
unknown-function site consults it too, since a generic body reaches `gcheck`
before `emit-list` (`.&` had the same hole); `tests/` was swept with the
script's new `--rules R1,R2` plus a string-literal pass for embedded programs;
`ir-snapshot.sh` moved exactly one `.err`, `dump-ast-corpus.sh` only edited
inputs (progress.md). **PK-4b built 2026-09-19** (§6 "as built"): `sigil-split`
in `src/generics.nuc` is the one reader of every sigil spelling and eight
walkers consult it, not the four §6 named; the unifier peels a `TY-PTR` by
**shape**, not by `PTR-MAYBE` (a template stamp loses the pointer kind, so the
recorded origin argument is whichever pointer kind stamped first); the
substituter strips the sigil run per colon segment; the cheader classifiers
read the cell, which also exported the `?&T` *parameter* and *return*
positions the symbol form had been rendering `void*`; the paren-operand
refusal is lifted from the sweep and the two sites swept, byte-identical; the
tyvar refusal **stays** — not for the substituter now, but because the boot
compiler that builds `nucleusc` predates PK-4b and compiles the five `lib/`
files those 14 sites live in (`lib/iterator.nuc:41: unknown type: E` on the
first attempt) — lift at the next boot refresh. PK-6's remaining docs rows are not built. Every claim in
§1 was reproduced against `build/nucleusc` on 2026-09-16 (probe generator and
full run kept beside this document's research pass; the 437-row matrix is
summarised in §1.1). Milestones are **PK-1 … PK-6**; §9 sequences them across
the boot refresh.

**Goal.** A type spelling must mean the same thing in every slot, and the node
the reader produces for it must be one the type path, the value path and the
printer all agree on — so that a header written by `--emit-nuch` re-reads to the
same node. Today three spellings of one pointer kind (`ptr:T`, `ref:T`, `&T`)
emit identical IR and differ only in the *node*, and only for the standalone
`&T`; and the paren forms of the `?`/`!` sigils (`?(Vector i32)`, `!(Vector i32)`)
parse in no position at all. The fix is not to teach every consumer the odd node
— that is what six `addr-of` arms in the type path already are — but to stop
producing it, and to let the reader's one fuse rule cover every sigil.

This closes the deferred item "Pointer-kind spellings: make the sugar general, or
ban the ambiguous half" ([deferred/done.md](../deferred/done.md)), on the
**general** side: §2 says why the ban lost.

---

## 1. Ground truth (verified 2026-09-16 against the tree)

### 1.1 The spelling × position matrix

19 spellings — atoms `&Pt ?Pt ?&Pt &?Pt !i32 ?!i32 &&Pt ptr:Pt raw:Pt` and paren
forms `&(V) ?(V) !(V) ?!(V) ?&(V) &?(V) &&(V) ptr:(V) raw:(V) ?ptr:(V)` with
`V = Vector i32` — in 23 positions: `let` colon/list, `defn` param colon/list,
`defn` return `):S` and `) S`, `defvar`, `defstruct` field colon/list, `defunion`
arm colon/list, `defprotocol` param/return, lambda param/return, `as`, `sizeof`,
`alloca`, template argument in `let` / `sizeof` / generic `defn`, `deftype`,
`with`. 437 rows; 92 fail.

| Spelling class | Node the reader gives | Result |
| --- | --- | --- |
| every atom form; `&(V)`, `?&(V)`, `&&(V)`, `ptr:(V)`, `raw:(V)`, `?ptr:(V)` | attached: the lexer rewrites `&`→`ref:`, the atom ends in `:`, the fuse fires. Standalone `&Pt` / `&(V)`: `(addr-of Pt)` / `(addr-of (V))` | **23/23**, except the 8 rows in the table below |
| **`?(V)`, `!(V)`, `?!(V)`, `&?(V)`** | `x:?(V)` → `x:? (V)`; `x:&?(V)` → `x:ref:? (V)`; `(as &?(V) v)` → `(as (addr-of ?) (V) v)`; `):?(V)` → keyword `:?` then `(V)` | **fail in 21/23** — every position but the two `defprotocol` slots, whose signatures are not parsed until an `extend` |

The failing class fails in one of five ways, all consequences of the atom `x:?`
not ending in `:` so the fuse never fires and the paren form dangles as a
sibling: `let: binding list must be even` (`let`/`with`); `unknown type:  — not
defined anywhere in this compilation unit` (an **empty** name — the type node is
the bare atom `?`, `resolve-type-name` strips the prefix and looks up `""`; at
`alloca` it is reported at **line 0**, because `emit-alloca-form`
`src/nucleusc.nuc:6585` passes the interned atom's own line); `as expects 2
args` / `sizeof expects 1 arg` (the dangling form is an extra argument); `Vector:
wrong number of type arguments for defstruct template (2 given)`; `deftype:
expects a name and one type`.

The 8 rows outside that class are three pre-existing defects, not spelling:

| Rows | Symptom | Disposition |
| --- | --- | --- |
| `?&Pt`, `raw:Pt`, `?&(V)`, `raw:(V)`, `?ptr:(V)` at lambda return | `return: raw pointer where non-null (ref ...) is required` — a lambda's declared return type loses its pointer kind; `defn` with the same signature is fine | side finding, [overview.md](overview.md) |
| `?Pt` in a `defunion` arm (both forms) | `use of undefined type named 'Maybe.Pt'` in the compile-time module | side finding |
| `?&Pt` as a generic-`defn` template argument | `cannot infer type variable '?ref:Pt'` — §1.4 | **in scope: PK-4** |

### 1.2 What the reader produces (REPL `'(…)`)

| Written | Read as | Why |
| --- | --- | --- |
| `x:?(V)` | `x:? (V)` | atom `x:?` does not end in `:` |
| `x:&?(V)` | `x:ref:? (V)` | lexer rewrote `&`; still no trailing `:` |
| `(as &?(V) v)` | `(as (addr-of ?) (V) v)` | `&` at a token boundary is the reader macro; its operand is read with a bare `(read-form)` (`src/reader.nuc:1023`), which never fuses |
| `(f (x:i32):?(V) …)` | `(f (x:i32) :? (V) …)` | keyword `:?` |
| `x:?&(V)` | `(x (?ref (V)))` | `?&`→`?ref:` ends in `:`; fuses; `parse-type-from-node`'s sigil-head arm strips the `?` |
| `(Vector &Pt)`, `&&Pt` | `(Vector (addr-of Pt))`, `(addr-of (addr-of Pt))` | standalone `&` |

### 1.3 The header leak (H4)

`--emit-nuch` prints `addr-of` from **every** emitter, not only the verbatim
ones: `src/nuch.nuc` passes each param/field/type node through `print-node`
(`src/nucleusc.nuc:1224`), which reconstructs no reader macro. Measured on one
module: `(defprotocol P (m ((self (addr-of Self)) (q (addr-of Pt))) :i32))`,
`(defn first-pt ((v (ref (Vector T))) (q (addr-of Pt))) :i32 …)` (generic
template, verbatim), `(declare plain ((q (addr-of Pt))) :i64)`, `(deftype PtRef
(addr-of Pt))`, `(defstruct H (link (addr-of Pt)))`; only the attached spelling
(`gq:&Pt`) came out as `(ref Pt)`. The header re-imports because the type path
accepts `addr-of` in six places — `src/union-registry.nuc:2103`,
`src/generics.nuc:1323`, `src/cheader.nuc:3436`, `:3727`, `:3796`, `:3966` — and
"every consumer must learn `addr-of`" is the failure mode this design removes.
The committed `lib/*.nuch` carry 24 `addr-of` lines, all value-position in
verbatim bodies (e.g. `lib/hashset.nuch:9` `(hash (addr-of k))`, from
`lib/hashset.nuc:165` `(hash &k)`), zero in a type slot.

### 1.4 The generic-pattern soundness hole (H5), and its second face

`tyname-resolvable` (`src/generics.nuc:1254`) strips only `ptr:`/`ref:`/`raw:`
(`:1283–1287`), never `?`/`!`. So in a struct-template argument of a generic
`defn` pattern, `?Pt`, `?&Pt` (= `?ref:Pt`), `?ptr:Pt`, `!i32`, `?!i32` are all
**collected as type variables** (`collect-pattern-tyvars` `:1355`; a bare-symbol
argument is a tyvar iff unresolvable, `:1400`). `--emit-llvm` then emits no
`define` for `(defn f-qpt (v:(ref (Vector ?Pt))):usize …)` — it is silently a
template (probed: `f-qpt`, `f-qrefpt`, `f-qptrpt`, `f-bangi32` absent; `f-refpt`,
`f-ptrpt`, `f-rawpt`, `f-canon` present). A colon-free sigil symbol then "works"
at a call because `unify-tpat`'s NODE-SYM arm (`:1459`) binds the fake tyvar to
whatever arrives: **`(Vector i32)` is accepted where `(Vector ?Pt)` was
declared** — probed, stamps `f_qpt.pVector.i32`, runs, prints 1. A colon-bearing
one (`?ref:Pt`) never binds (the arm binds colon-free symbols only, `:1459`) →
`cannot infer type variable '?ref:Pt' for 'probe'`. `&Pt`, `&?Pt`, `&&Pt`,
`ptr:Pt`, `raw:Pt`, `(Maybe Pt)` are treated as concrete.

The same predicate answers a **second** question: `value-annot-type`
(`:4684`) gates the value-position annotation cast on it, so `q:?&Pt` in value
position is refused `unknown type '?ref:Pt' in the annotation 'q:?ref:Pt'`
while `(as ?&Pt q)` and `q:raw:Pt` both work (probed). One fix (PK-4a) closes
both faces.

A `(? X)` cell today: `parse-type-from-node`'s sigil-head arm (`:1849–1874`)
strips one char to head `""` → `unknown type:  —`; `collect-pattern-tyvars`
finds neither template nor wrapper and returns without descending;
`unify-tpat` falls to the concrete parse (`:1498`) and dies. `(?ref X)` /
`(?ptr X)` cells are not wrappers for the collector or unifier either (they
parse concretely only), which is why `?&(V)` passes the matrix.

### 1.5 Where the pieces live

**Reader** `src/reader.nuc`: `next-tok` `:704` — legacy-marker check `:768–770`,
reader-macro longest-prefix match `:771–801` (→ TOK-RMACRO, **before**
`lex-atom` `:824`, only at a token boundary); `lex-atom` `:618` (keyword `:692`
/ symbol `:698` tails call `expand-ref-sigil` `:545`, whose state machine is
`ref-sigil-seg-next` `:540`); `peek-char` `:252` (raw byte at `g-pos`);
`peek-tok`/`eat-tok` `:830–839`; `read-form` `:996` (rmacro operand via a bare
`(read-form)` `:1023`; symbol → `intern-node` `:1059`; keyword `:1064`);
`read-list` `:1202` calls `fuse-colon-paren` `:1213` — the **only** caller;
`read-lit-elems` `:953` and `read-program` `:1220` do not; `fuse-colon-paren`
`:1129` (gates `:1131–1138`; `fuse-fn-params` `:1122`; CP-2a `:1145`; CP-1 split
`:1151–1174`, empty-segment error `:1162`; fold `:1183–1199`). **The library
reader `lib/read.nuc` mirrors all of it** — `rd-seg-next` `:264`,
`rd-expand-sigil` `:280`, `rd-macro-name` `:487` (`&` → `"addr-of"` at `:494`),
`rd-fuse-colon-paren` `:527`, called only from `rd-list` `:599` — and
`tests/suite-audits.nuc:284` (`reader-parity-over`, four units `:316–329`)
requires the two readers to agree over `tests/fixtures`, `examples`, `lib` and
`src`. The research brief's reach list omitted this file; every reader change
below had a twin there — history since Stage 21 R-2 deleted `src/reader.nuc`
and made `lib/read.nuc` the compiler's only reader
([one-reader.md](one-reader.md)); PK-1's `&` → `ref` reader-macro-table edit is
now one line, in `read-macro-table-new`.

**Type parser** `src/union-registry.nuc`: `parse-type-name` `:307` →
`resolve-type-name` `:312`, arms in order `?!` `:319`, `?` `:333` (pointer
operand → PTR-MAYBE relabel via `type-as-pkind` `src/type-utils.nuc:1126`, else
value-`Maybe` stamp), `!` `:348`, colon → `split-colon-segments`
(`src/nucleusc.nuc:16533`) + `parse-type-from-node` `:361`, builtin `:375`,
struct/union `:391`, alias `:404`, C typedef `:429`, `unknown-type-message`
`:441`. `parse-type-from-node` `:1817`: SYM `:1835/:1841`; CELL sigil-head arm
`:1849–1874` (strips ONE char, rebuilds `(rest-head . cdr)`, recurses, applies
Maybe/Result); struct template `:2037`; union template `:2047`; `ptr` `:2052`;
`raw` `:2078`; `ref`-or-`addr-of` `:2103`; `Maybe` `:2129`; fall-through
`:2266–2277`.

**Generics** `src/generics.nuc`: `tyname-resolvable` `:1254`;
`wrapper-inner-pattern` `:1294`; `node-is-ptr-wrapper` `:1314` (heads
`ptr/raw/ref/addr-of` `:1322`); `collect-pattern-tyvars` `:1355`; `unify-tpat`
`:1442`; `gcheck-special-form` `:2671` (set `:2672–`, consulted by `gcheck`
`:2821` and `valid-walk` `:3097`); `gcheck`'s type-spelling deferral for a
`ref`/`raw`/`ptr` head `:2765`; `value-annot-type` `:4684`;
`node-type-addr-of` `:4865` (arity split `:4866`; 2-arg →
`node-type-field-addr` `:4844`); `node-type` `:5128`, `addr-of` arm `:5240`.

**Value path** `src/nucleusc.nuc` (C = compares the head, B = builds a cell):
`emit-addr-of` `:6714` (2-arg → `emit-field-addr` `:11054`, whose diagnostic
nouns are the literal `"addr-of"` at `:11057–11088`); `fn-rewrite-captures`
`:8030` C (string compare `h == "addr-of"`, len 2) and `:8045` B;
`fn-make-drop-method` `:8432` B; `fn-emit-env-value` `:9471`, `:9539` B;
`emit-list` `:12413` C; `defvar-init-ir` `:13490` C (1-arg →
`defvar-addr-of-ir` `:12952`); `defvar-check-init-order` `:13707` C;
`build-rmacros` `:19313` (`&` → `addr-of`); `build-special-form-set` `:19548`
roster. Dispatch order in `emit-list` `:12326`: non-symbol head → callable value
`:12347`; macro table `:12355`; the static special-form chain `:12358–12490`,
matched on the interned symbol **before** any scope lookup (only `fn`/`vfn`/
`mfn`/`cfn` `:12447–12475` carry a `scope-lookup` guard); `emit-dispatch`
`:12491` last. `node-type` mirrors the chain — the `node-type`↔`emit-node`
lockstep (`context/conventions.md`). The name `ref` is **already reserved**
against every top-level definer: `pointer-kind-named` `:12546` answers
`binding-probe`'s BK-PRIMITIVE row (`:11902`), so `(defn ref …)` and `(defmacro
ref …)` die today with `'ref' already names a pointer kind` (probed); the one
guard that consults only `special-form-named` is `macrolet-bind` `:16322`, which
accepts `(macrolet ((ref …)) …)` today (probed, rc 0). Locals are unguarded
(`(let (ref:i32 1) …)` is legal; `(ref 2)` on it is `value is not callable`).
The `match` `(ref name)` binder (`src/union-emit.nuc:1003`, `examples/unions.nuc:34`)
already gives the head `ref` a pattern-position meaning — a reference to a
place — consistent with everything below.

**Printing**: `print-node`/`fprint-node` `src/nucleusc.nuc:1174–1224`, structural.
`src/nuch.nuc` prints whole forms verbatim for `defmacro` `:96`, generic-template
`defn` `:122–126`, `defprotocol` `:134`, `defcast` `:155`, `defunion` `:224`,
`deferror`/`deftype` `:236`, and each type node for the rest (`defstruct` `:25`,
`emit-nuch-ret` `:38`, `declare` `:71`, `defenum` `:89`, `defmethod` `:103`,
`extend` `:146`, `extern` `:162`).

**Census.** `(addr-of ` heads: src 154 (144 one-arg, 8 two-arg, 2 nested), lib
153 (33/95, e.g. `(addr-of s 'alloc)` in exported bodies), examples 65 (7/55),
tests 3,675 (3,156/510 — dominated by embedded fixture strings in
`tests/nuctests.nuc`, `suite-s16.nuc`, `suite-modules.nuc`, `suite-target.nuc`).
`tests/manifest/diagnostics.sexp` pins the noun at 6 rows (`defvar: addr-of:
'G1K' is a compile-time constant…`, `s17-rvalue-addr-of-rejected`). Locals named
`ref`: 2 (`src/nucleusc.nuc:2672`, `:2730`); `ptr`: 0; `raw`: 21. Spellings
whose reading PK-2 changes: `?(`/`!(`/`:?(`/`?!(` before a paren — 1 hit, a
comment (`examples/comb-storage.nuc:26`); `~sym:(` 0; a reader-macro operand
`'x:(`/`~x:(`/`@x:(` 0; top-level `x:(` 0; inside `[…]`/`{…}` 0. Docs mention
`addr-of` in 18 `docs/*.md` files (§8).

---

## 2. Principle, and why the ban lost

The deferred item offered two end-states. **Ban the ambiguous half** — refuse a
standalone `&T` in a type slot — is one arm in `parse-type-from-node`, but it
retires `(sizeof &Pt)`, `(as &Pt q)`, `(link &Pt)`, `(Vector &Pt)`, which
ref-sigil.md §6 blesses and `s16-ref-sigil-both-meanings` pins; it leaves
`?(V)`/`!(V)` unparseable, since those are a *different* defect (§1.1) the ban
does not touch; and it leaves H5 open. It is a convention enforced by a
diagnostic, not a spelling made honest.

**Make it general** was costed in the deferral as "the node has to remember it
was written `&`" — a new head both paths accept, printed back as the source
spelling. That over-states it. The type path already *has* a canonical head for
the non-null pointer, `ref`, and the value path already has a form whose result
type is `(ref (type-of x))`. They differ only in the *name* the reader macro
writes. Give the reader macro the type path's name and the two worlds agree on
one node with no new head at all: `(ref X)` is the pointer type in a type slot
and the address-of in a value slot, and the type of `(ref x)` is `(ref (type-of
x))` — the invariant this buys. The cost is the value path's reach list (PK-1),
which is the same list the deferral priced; the saving is six type-path arms and
a header format that no longer depends on which synonym the author typed.

The two rules still partition `&` by position **inside the token** (ref-sigil.md
§2/§6): a `&` beginning a token is the reader macro, a `&` inside one is the
lexer rewrite. Nothing about that changes; they simply agree on the name now.

---

## 3. PK-1 — `&` is `ref`, in both worlds

`build-rmacros` (`src/nucleusc.nuc:19313`) registers `&` → `ref` instead of
`addr-of`; `lib/read.nuc:494` (`rd-macro-name`) does the same, or the parity
units fail. `(ref X)` in a type slot is already the canonical non-null pointer
(`src/union-registry.nuc:2103`), so `(sizeof &Pt)`, `(Vector &Pt)`, `(link
&Pt)`, `(deftype P &Pt)` and a `defprotocol`'s `&Self` all become the node they
always meant, and every emitter in `src/nuch.nuc` prints `(ref Pt)` with **no
change**. In value position `(ref x)` is the address-of form and `(ref p 'f)`
the field-address form — the same node `emit-addr-of`/`node-type-addr-of`
already emit, under the head the result's type is spelled with. The lexer's
mid-token `&` → `ref:` rewrite is unchanged. `docs/toplevel.md:26`'s built-in
reader-macro list says `&` (ref).

**Head position.** `ref` joins the static special-form chain, matched before
scope lookup like every other special form. A local named `ref` — `src/` has
two, `(let (ref:StrView …))` at `:2672` and `:2730` — keeps working as a value
and stops being callable in head position, exactly the standing policy for a
local named `addr-of` (name-resolution.md §15: scope is decided by definers, not
bindings; locals are not newly guarded). Rename the two in the PK-5 sweep. No
change to `build-special-form-set` (`:19548`): `ref` is already reserved through
`pointer-kind-named` (§1.5), and adding it to the special-form roster would make
one symbol answer two rows of the binding-kind table. The one guard that does
need widening is `macrolet-bind` (`:16322`): it consults `special-form-named`
only, and a `(macrolet ((ref …)) …)` would shadow the new form because the macro
table is consulted before the chain (`:12355`) — add `pointer-kind-named` beside
it.

**Value-path reach list** — every C site gains a `ref` arm; `addr-of` stays
accepted until PK-5:

| Site | Change |
| --- | --- |
| `emit-list` `src/nucleusc.nuc:12413` | `(when (= hp 'ref) (return (emit-addr-of n scope)))` beside the `addr-of` arm |
| `node-type` `src/generics.nuc:5240` | the lockstep twin: `'ref` → `node-type-addr-of` |
| `fn-rewrite-captures` `:8030` | match `"ref"` as well as `"addr-of"`. **Mandatory for the fixed point**: a captured `&local` in `src/` or `lib/` now reads as `(ref local)`, and a closure that misses the rewrite compiles differently under the new reader than under the boot's — `make bootstrap` diverges |
| `defvar-init-ir` `:13490` | `(ref g)` with one argument → `defvar-addr-of-ir` (the `(defvar q:&Pt &g)` shape) |
| `defvar-check-init-order` `:13707` | do not walk under `ref`, as under `addr-of`/`quote`/`quasiquote` — an address is not a read |
| `gcheck-special-form` `src/generics.nuc:2672` | add `'ref`, for `valid-walk` `:3097`. In `gcheck` itself the `ref`-head deferral at `:2765` answers first and returns null without walking children — inert for an address-of, whose operands are a binding name and a quoted selector, never a call. `valid-walk` has no such deferral, so a *type-spelling* `(ref (Vector T))` under `cast`/`sizeof` in a `Valid`-bounded body now reaches `node-type`'s new arm (a non-symbol target → null, unmodelled) where it previously fell to the genuine-call path; confirm on the tree's `Valid` bodies that this is a strict improvement, not a change |
| `macrolet-bind` `:16322` | refuse a binding named by `pointer-kind-named` too (above) |
| `retired-form-message` `:3535` | the `.&` row names `(ref p 'field)` |

The four cell-**building** sites (`:8045`, `:8432`, `:9471`, `:9539`) keep
building `addr-of` until PK-5 — they are read back by the same emitter either
way, and leaving them is what keeps PK-1's `.ll` byte-identical (§9).

**Type-path arms removed** — nothing produces `(addr-of T)` any more, and
neither `src/` nor `lib/*.nuch` holds one in a type slot: `src/union-registry.nuc:2103`
drops the `addr-of` alternative; `src/generics.nuc:1323`; `src/cheader.nuc:3436`,
`:3727`, `:3796`, `:3966`. A literal `(addr-of T)` in a type slot then falls to
the ordinary fall-through diagnostic (`:2266–2277`, `unknown type: addr-of`)
until PK-5 gives it the retirement message.

**The headers move in this milestone, not in PK-5.** The 24 value-position
`addr-of` lines in `lib/*.nuch` come from two source spellings: `(addr-of s
'alloc)` written out, which stays until the sweep, and `&k`, which the new reader
prints as `(ref k)` immediately (`lib/hashset.nuc:165`, `hashmap`, `combinators`).
`make test`'s `headers-generated` unit (`scripts/check-headers.sh`, byte-exact)
therefore requires `scripts/check-headers.sh --fix` as part of PK-1. That is
safe: the build never reads the committed headers (§9), and the only compiler
that reads them at all — `build/nucleusc`, in tests — is the one that just
learned `(ref k)`.

---

## 4. PK-2 — the fuse gates on an open segment, and lives in `read-form`

**Gate.** Replace `fuse-colon-paren`'s "spelling ends in `:`" test
(`src/reader.nuc:1137`) with "the spelling's final chain segment is **open**",
computed by running `ref-sigil-seg-next` (`:540`) over the spelling from its
initial open state: `:` opens, `?`/`!` keep the state, anything else closes (`&`
never reaches here — the lexer rewrote it to `ref:`, and the interior `&` of
`.&` or a retired `&rest` closes or is closed). So `x:`, `?`, `?!`, `x:?`,
`ptr:`, `x:ref:?`, the lone `:` and a keyword body `?` all fuse when immediately
followed by `(`; `foo?`, `push!`, `!=`, `x:foo?` do not — their last segment
closed before the sigil. The `peek-char == 40` adjacency gate (`:1138`) and the
`g-peek-valid` gate are unchanged.

**Split.** The segment split (`:1151–1174`) treats a trailing sigil run as a
segment of its own: strip one trailing `:` if present, then split on `:`. The
CP-1 fold and CP-2a's lone-`:` case are unchanged.

| Written | Reads as |
| --- | --- |
| `?(V)` | `(? (V))` |
| `x:?(V)` / `x:!(V)` / `?!(V)` | `(x (? (V)))` / `(x (! (V)))` / `(?! (V))` |
| `):?(V)` (keyword body `?`) | `(? (V))` — the return-position form |
| `x:&?(V)` = `x:ref:?` | `(x (ref (? (V))))` |
| `x:?&(V)` = `x:?ref:` | `(x (?ref (V)))` — unchanged |
| `x:(V)`, `x:ref:(V)`, `:(V)` | unchanged |

The reader stays type-ignorant: it does not know `?` means `Maybe`, exactly as
CP-1 does not know `ref` is a pointer kind. `(? (V))` is a shape; PK-3 gives it
a meaning and the type parser rejects a `(foo? (V))`-like accident naturally.

**Placement.** Move the one call from `read-list` (`:1213`) into `read-form`,
immediately after an atom node is produced (`:1060` for a symbol, `:1069` for a
keyword), passing the token's own line rather than the enclosing list's (only
diagnostics and the synthesized cells' `line` fields read it; no emitted byte
does). At that point `g-peek-valid` is 0 (`eat-tok` cleared it) and `g-pos` is
just past the atom, so the adjacency test is exactly the one `read-list` made.
`fuse-fn-params`' second group and the paren form itself are read through
`read-form` → `read-list`, whose elements now fuse in `read-form` — the same
elements `read-list` fused before. Three consequences, none of which touches an
in-tree spelling (§1.5 census):

1. A **reader-macro operand** fuses: `&?(V)` → `(ref (? (V)))`, `&ptr:(V)` →
   `(ref (ptr (V)))`, `'x:(T)` → `(quote (x (T)))`, `~x:(T)` → `(unquote (x
   (T)))`. The last is *not* a fix for the quasiquote-template limitation
   (`(unquote (x (T)))` evaluates `(x (T))` as a call at expansion time); the
   list form `(~x (T))` remains the template idiom, and `docs/macros.md`'s note
   changes only in what it says the spelling reads as.
2. A **literal element** fuses: `[x:(T)]`. Zero in-tree.
3. A **top-level atom** fuses: `foo:(bar)` at top level is one form. Zero
   in-tree; today it is a bare-symbol top-level error followed by a list.

Quoted data gets no new *kind* of rule: the fuse has always been syntactic and
quote-blind (`'(foo:(bar))` fuses today, types.md "Quoted-data caveat"); what
changes is that a reader macro's operand is read under the same rule as a list
element. `lib/read.nuc` mirrors both halves (`rd-fuse-colon-paren` `:527`, the
call moving from `rd-list` `:599` into `rd-form` `:606`).

**Why `?` is not expanded in the lexer the way `&` is** (`?T` → `Maybe:T`).
Three reasons, each the type parser's business: `!T` has an implicit second
argument (`Err`) no chain segment can spell; `?` would rewrite every
`?x`-prefixed symbol in quoted data, where `&` only ever meant one thing; and
`?` over a pointer operand must niche-encode with no `Maybe` template present
(freestanding/AVR), which the lexer cannot know. `&` was expandable because
`ref:` is a pure one-argument prefix with no meaning beyond `(ref T)`.

---

## 5. PK-3 — a bare-sigil head is the canonical list form of a sigil-paren type

Generalise `parse-type-from-node`'s sigil-head arm (`src/union-registry.nuc:1849`):
strip one sigil from the head; if the remaining head is **empty**, the operand
is the sole remaining element — `(? X)` parses X; more than one element, or
none, is `'?' takes one type — (? T)` (and the same for `!`); otherwise rebuild
`(rest-head . cdr)` as today (`(?ref X)` → `(ref X)`). Recursion handles `(?! X)`
→ `(! X)` → X, reproducing `resolve-type-name`'s `?!` composition (a value-Maybe
over a `Result`, `:319`). `(? X)`, `(! X)`, `(?! X)`, `(?ref X)` all print
structurally and re-read to themselves — the round-trip property: a `defn`
parameter written `x:?(Vector i32)` exports as `(x (? (Vector i32)))`, which is a
space-separated list the reader takes as-is. The cheader source-node walkers
(`cheader-mentions-closure`, `cheader-niche-no-c`) see a `(? X)` cell as they see
a `(?ptr X)` cell today — they do not descend through a sigil head — so no
change there.

**Near-miss diagnostic.** In `resolve-type-name`, a name that is empty after
stripping its sigils (a bare `?`/`!`/`?!` atom — `? (Vector i32)` written with a
space, or a `?` reaching the parser some other way) dies with `a type sigil must
be attached to its type — write ?T or ?(T …) with no space`, naming the sigil as
written, at the **caller's** line. `emit-alloca-form` (`src/nucleusc.nuc:6585`)
passes the interned atom's own line (0) — it becomes `(node-line tn (cc 'line))`,
the discipline `context/conventions.md` ("Symbol nodes are interned singletons —
they have no line") already states. This is CP-3's near-miss rule applied to
the sigils.

---

## 6. PK-4 — sigil nodes are wrappers to the generic-pattern walkers

Two steps, specified separately so (a) — the bug fix — lands even if (b) needs
iteration. (b) is in scope of this item (it is the last type slot a sigil could
not reach) but may be sequenced after PK-5 (§9).

**PK-4a — resolvability.** `tyname-resolvable` (`src/generics.nuc:1254`) strips
a leading run of `?`/`!` and re-enters itself on the remainder, ahead of its
existing `ptr:`/`ref:`/`raw:` logic (so `?ref:Pt` → `ref:Pt` → `Pt`). A sigil
over a concrete type is then concrete: `?Pt`, `!i32`, `?ref:Pt` are no longer
collected, `unify-tpat`'s NODE-SYM arm parses them concretely (`:1467`) and
checks with `type-eq`, and `(Vector i32)` passed where `(Vector ?Pt)` was
declared is a type error instead of a stamp — the H5 regression test. The second
face closes with the same edit: `value-annot-type` (`:4684`) now answers yes for
`q:?&Pt`, so the value-position annotation cast works as `(as ?&Pt q)` does. A
sigil over an **unresolvable** name is still a tyvar candidate but must not be
collected under its sigil-bearing spelling: until (b), `collect-pattern-tyvars`
(`:1400`) refuses it with a located message (`Vector: '?T' — a type sigil over a
type variable is not supported in a generic pattern yet; write the concrete
type`), the shape CT-D's `'ref' is a pointer kind` diagnostic (`:1395`) already
takes. Refusing is right because collecting `T` while the unifier still sees
`?T` would fail at the *call* with `unknown type: T`.

**PK-4b — one helper, three shapes.** Introduce `sigil-split` (node → the sigil
run as a `StrView`, and the operand node) normalising `?X` (symbol, run
stripped; a remaining colon chain goes through `split-colon-segments` first so
`?ref:T` is seen as `(?ref T)`), `(? X)` (cell, PK-3's form) and `(?ref X)` /
`(?ptr X)` (glued head → `(ref X)`), and returning an empty run for anything
else. The same helper should also recognise the list spellings `(Maybe X)` and
`(Result X Err)` as `?`/`!`, and the walkers must consult it **ahead of** the
template arm (`:1484`) — otherwise the pattern slot becomes the one place `?T`
and `(Maybe T)` differ, which is the principle §2 states, and `(Maybe (ref T))`
against a niche-encoded PTR-MAYBE argument would keep failing in the template
arm, which knows only stamped instances. Then:

* `collect-pattern-tyvars` descends into the operand (a template-argument
  symbol `?T` collects `T`; a cell `(? (Vector T))` recurses on the operand).
* `unify-tpat` unifies the operand against the **unwrapped** concrete type: for
  `?`, a PTR-MAYBE pointer unwraps to the same pointer relabelled PTR-REF
  (`type-as-pkind`), and a stamped `Maybe` instance unwraps to its type argument
  (`origin-args`, as the template arm `:1484` reads them); for `!`, a stamped
  `Result` whose second argument is `Err` unwraps to its first; anything else is
  a unification failure with the ordinary message.

That is what makes `(Vector ?T)`, `!T` and `?(Vector T)` legal in a generic
pattern with `T` a tyvar. Out of its scope, recorded in [overview.md](overview.md):
receiver-inferred collection stops at a wrapper *inside* a template argument
(`(Vector (ref T))` needs an explicit `:where (Any T)`; probed), and the colon
form `(Vector ref:T)` is collected under the spelling `ref:T`, which the
unifier never binds — the same collect-but-never-bind shape as H5, on the
pointer prefixes rather than the sigils.

**PK-4b as built (2026-09-19).** The helper is as specified — `sigil-split`
(`src/generics.nuc`, beside `node-template-of`) reads the five spellings and
returns the run and the operand; `(Result X E)` is a sigil only when `E` is
literally `Err`, and a multi-character run is unwrapped one sigil at a time,
outer to inner, by `sigil-unwrap-type`. Five claims above were one step off:

1. **The `?` unwrap of a pointer cannot require `PTR-MAYBE`.** A template
   stamp's name is `type-mangle-token`'s, which spells every pointer kind
   `pPt`, so `(Vector &Pt)`, `(Vector ?&Pt)` and `(Vector raw:Pt)` are **one**
   stamp `Vector.pPt` whose `origin-args[0]` is whichever pointer type stamped
   first. A strict `PTR-MAYBE` test would make `(n-q &w)` succeed or fail by
   declaration order. The unwrap is by **shape**: any `TY-PTR` peels to the same
   pointer relabelled `PTR-REF` (`type-eq` already ignores the kind for the same
   reason); a non-pointer must be a stamped `Maybe`/`Result` instance, checked
   through the new `UnionDef.origin-template` / `origin-args` / `origin-nargs`
   (mirroring `StructDef`, set in `union-template-stamp-types-in`) — for `!`,
   `origin-args[1]` must `type-eq` `ty-err`.
2. **Eight walkers, not four.** Beyond `collect-pattern-tyvars`,
   `collect-constraint-arg-tyvars`, `unify-tpat` and the substituter,
   `pattern-determines-tyvar`, `node-mentions-tyvar`,
   `node-mentions-tyvar-named` and `method-has-nested-tyvar` each mirror the
   collector's notion of "mentions a tyvar", and each had to peel the sigil or
   the collected `T` was found by one walker and lost by the next: a protocol
   parameter `?E` "not determined" at the `extend` (`node-mentions-tyvar-named`),
   a `T` bound only under a sigil judged return-only (`pattern-determines-tyvar`
   feeds `tyvars-determined`), a receiver-inferred `x:?T` method sent to the
   flat abstract interface check (`method-has-nested-tyvar`).
   `cheader-defvar-type-ok` was a ninth: a `defvar` of `?&Pt` reached "type
   has no C spelling" before the classifiers ran.
3. **The substituter** (`subst-tyvar-segment` in `src/type-mangle.nuc`) is the
   segment rule stated in §2: strip the leading sigil run, look the remainder
   up, re-prefix the run to the binding's spelling — `?E` → `?i32`, `?ptr:E` →
   `?ptr:Pt`, and `?E` with `E = ?Pt` → `?Maybe.Pt` (the stamped union's name,
   which the type parser reads back). In a `defprotocol` signature, a
   parametric struct's fields and a parametric union's arm alike.
4. **"The symbol form renders `Pt*`" held for a struct field only.** A `q:?&Pt`
   parameter or return desugars to the glued-head cell `(?ref Pt)`, which
   `type-node-to-c` did not read and rendered `void*` — every `?&T` parameter
   and return in the tree's headers (`lib/node.h`'s `node_at`, three example
   headers, six fixture headers) moved to the niche spelling when the
   classifiers learned the cell. `(Maybe &Pt)` in a signature had been refused as a
   *template instance*; it is exported now. The three `!`-spellings over a
   struct operand are one "uses an error-union or option type" comment and no
   `void*`; a pointer to a value niche (`&?(Vector i32)`) is refused for its
   pointee, as `ptr:!ui8` already was.
5. **The tyvar re-sweep is boot-gated, not language-gated.** The 14 `lib/`
   sites compile under `build/nucleusc`, but `make` builds `nucleusc` with the
   committed boot, which compiles `lib/coll`, `iterator`, `vector`, `hashmap`
   and `hashset` and has no PK-4b (`lib/iterator.nuc:41: error: unknown type:
   E`). Per the gate the sites were restored by hand, the tyvar refusal stays
   in `sugar-sweep.py` with the reason rewritten, and the next boot refresh
   lifts it (`context/build.md`, "the boot compiler gates what src/ may use").
   The paren-operand refusal is lifted: `lib/test.nuc:410` and
   `lib/hashmap.nuc:472` are swept, `build/nucleusc.ll` byte-identical.

Out of scope, confirmed by probe against the built compiler: a `defunion`
template other than `Maybe`/`Result` inside a template argument
(`(Vector (Either T))`) does not collect `T` — `node-template-of` knows struct
templates; a pointer wrapper inside a template argument (`(Vector &T)`,
`(Vector ref:T)`, `(Vector ?&T)`) fails `unknown type: T` under both compilers;
and a `:where` constraint's *own* argument is recovered only when it is a bare
tyvar (`recover-one-constraint` parses any other arg concretely), so
`((Peek ?E) S)` is not a recovery — while `(extend (Wrap I) (Iterator ?E)
:where ((Iterator E) I))`, where `?E` is the protocol application's argument,
now determines `E` (unit `s21-pk4b-extend-sigil-arg`).

---

## 7. PK-5 — retire `addr-of`, after the boot refresh

Once the boot compiler understands value-position `ref` (§9 step 2), in two
sub-steps with different gates:

**PK-5a, the sweep — a script, `scripts/stage21/sugar-sweep.py`.** One
paren-aware rewriter does two jobs in one pass, because they are the same pass
over the same files: it retires `addr-of` and it adopts the sugar this design
makes general. It reuses `scripts/stage17/rewrite-fmt.py`'s scanner
(`skip_atom`/`split_call` — string- and comment-aware, escaped quotes) and its
discipline: **refuse rather than guess**, print a per-rule histogram and a
refusal list, `--dry-run`, idempotent. It is kept in the tree, not run once and
deleted, because the brief is "most sites, not every site" — a shape it refuses
is hand-swept or left, and a later author can rerun it.

Rules, in the order applied to each form. Every rule is meaning-preserving
**at the node level** after PK-1–PK-3 (`&X` *is* `(ref X)`, `?X` *is* `(Maybe X)`
in a type slot), which is what lets the gate be mechanical:

| # | Matches | Rewrites to | Scope |
| --- | --- | --- | --- |
| R1 | `(addr-of X)`, one operand | `&X` (`&~x` for an `(unquote x)` operand) | everywhere |
| R2 | `(addr-of p 'f)`, two operands | `(ref p 'f)` | everywhere |
| R3 | `(ref X)`, one operand, `X` not a keyword (`(ref :volatile T)` stays) | `&X` — `&Pt`, `&(Vector i32)`, `&&Pt` | everywhere **except** a `match` arm's pattern (an ancestor three lists up has head `match`), where `(ref name)` is the binder and stays for readability |
| R4 | `(ptr X)`, one operand, `X` a symbol or list, not a keyword | `&X` (`(ptr T)` ≡ `(ref T)` since the Phase F flip) | type slots only |
| R5 | a standalone symbol token `ref:T…` / `ptr:T…` (the token *starts* with the prefix — a name segment ahead of it means a binding, already the attached form) | `&T…` — `(as ref:Type x)` → `(as &Type x)`, the 2,361 cast operands the 2026-09-07 sweep had to undo | everywhere |
| R6 | `(Maybe X)` | `?X` / `?(…)` — `(Maybe (ref T))` → `?&T`, `(Maybe (Vector i32))` → `?(Vector i32)` | type slots only |
| R7 | `(Result X Err)` — second operand exactly `Err` | `!X` / `!(…)`; `(Maybe (Result X Err))` → `?!X` | type slots only |
| R8 | a binding pair `(name T)` whose `T` R3/R4/R6/R7 rewrote to a sigil form and whose `name` is a plain symbol | the attached `name:&T`, `name:?X`, `name:&(Vector i32)`, `name:?(…)` | binding positions |

"Type slot" is what the script can see syntactically: the operand of `as`,
`unsafe/cast`, `sizeof`, `alloca`, `deftype`'s body, `make`'s first argument;
the second element of a binding pair in a `let`/`with` binding list, a `defn`/
`fn` parameter list, a `defstruct`/`defunion` arm field list; the return form
after a parameter list; and, recursively, everything inside a type slot (so a
template argument is one). A `(Maybe X)` anywhere else — a value position the
script cannot classify — is refused and listed, not rewritten. R1–R3 and R5
need no slot classification because `&X` and `(ref X)` are one node in every
position after PK-1; that is the property PK-1 was built to give.

Not touched: `tests/` (fixture strings pin spellings on purpose; they get R1 and
R2 only, since `addr-of` is retired — the ~3.7K hits are `(addr-of ` → `(ref `
and `&x` by the same two rules); `examples/ptr.nuc`, `ref-sigil.nuc`,
`colon-paren-types.nuc`, `errptr.nuc` and the new `type-sugar.nuc`, each of
which exists to show one spelling (the 2026-09-06 sweep's exclusion list,
extended by one); the fn-pointer triple `(name (fn ret) (params))` (head `fn` is
in no rule); and `docs/` (PK-6 sweeps prose by hand). Rename the two
`ref:StrView` locals by hand.

**Gate, in two parts.** The compiler: `build/nucleusc.ll` byte-identical against
the step-2 build, the proof the 2026-09-07 sweep used (ref-sigil.md §5). The
tree: `scripts/stage17/ir-snapshot.sh snapshot` taken on the step-2 compiler
before the sweep, `verify` after — every program, library and example `.ll`
byte-identical, which is stronger than "compiles": a rewrite that changed a
*type* would change the IR of everything importing it. The one class of
artifact the snapshot will report is `.nuch` **text**: a header prints the node,
so `(m (Maybe i32))` printed `(m (Maybe i32))` and `m:?i32` prints `m:?i32`. Those
diffs are expected and are confined to signature spellings; the proof they are
only spellings is the `.ll` identity of every importer of that header, which the
same `verify` run establishes. Record the diff count in progress.md as the
2026-09-06 sweep did.

**As built (2026-09-18).** The table held; the script's slot classifier is a
role walk (value / type / binder list / param list / arm / signature / pattern /
return / quote / quasiquote / match arm / name / type list) rather than a
head-only test, because a `defn` parameter list, a `:where` clause, an
attribute keyword at a binder slot and the two-group function-pointer type
`x:(fn ret)(params)` all put a type where the table's "second element of a
binding pair" does not look. R8 also attaches a return type after a parameter
list (`(params) T` → `(params):T`, 50 sites), which the table did not say and
the `.nuch` printer already does. Under `quasiquote` only R1/R2/R3/R5 fire
(templates are data until spliced; a `(Maybe X)` there is not a type slot);
under `quote` nothing does. Five refusal classes beyond "a `(Maybe X)` the
script cannot classify", each proved on the compiler, not assumed:

| refused | why the rewrite would not be meaning-preserving |
| --- | --- |
| R6/R7 whose operand is a **type variable** of the enclosing template/protocol/`:where` (`(Maybe E)`, 14 sites) | `?E` is one bare symbol; `subst-tyvars-sym` substitutes by colon **segment**, so `?E` is never substituted while `(Maybe E)`, `?&E` and `?(Vector E)` are |
| R6 over **`(raw T)`** | `(Maybe (raw T))` is a value-Maybe; `?raw:T` is the niche-encoded nullable pointer |
| R6/R7 with a **paren operand in an exported slot** (a public `defn`/`declare`/`defprotocol` signature, a field; 2 sites) | `cheader-template-instance` / `cheader-niche-no-c` key on the `(Maybe …)`/`(Result …)` head and do not read a `(? X)`/`(! X)` cell, so `!(Vector D)` exported `void* read_diagnostics(...)` — an ABI-wrong C declaration; local slots (`let`, `as`, `sizeof`, …) are fine |
| R5 on an **`extend` subject** (`(extend ptr:Cents Ord)`, 2 sites) | `extend` reads a cell subject as a template application; `&Cents` is `(ref Cents)` |
| R1/R2/R4/R6/R7 under **`quote`**; a comment **inside** the form | quoted data is a literal; a comment would be lost or moved by the reprint |

Two of the design's gate claims were one step off. (1) "byte-identical against
the step-2 build" holds only modulo the two `ref:StrView` → `tree:StrView`
renames this section prescribes — a local's name is its `alloca`'s name
(`%tree.addr.15`), so the compiler's `.ll` differs by exactly the six lines
that spell it; undoing the rename in the text restores identity. (2) The
snapshot's `.h` artifacts move too, not only `.nuch`: a `(Maybe i32)` in a
public signature was refused by `cheader-template-instance` (a cell whose head
is a union template) and its `?i32` successor by `cheader-niche-no-c` (a
sigil-led symbol with no C spelling), so the *reason* text in the "not
exported" comment changes (18 headers, "defunion-template instance" →
"error-union or option type") with no declaration moved — the two
classifiers agree on *what* is exported, which is the gate, and differ on
*why*. And the `.nuch` diffs are not confined to
signatures: a template or macro body prints verbatim, so its `&x`/`?T`
spellings are in the header text as well.

**PK-5b, the retirement.** The four cell-building sites (`:8045`, `:8432`,
`:9471`, `:9539`) build `ref`; the diagnostic nouns that say `addr-of`
(`emit-field-addr`'s `require-derefable`/`die-nonliteral-selector`/
`union-field-guard` calls `:11057–11088`, `defvar-addr-of-ir`'s `:12952–12987`,
and the `tests/manifest/diagnostics.sexp` rows that pin them) become `ref`; the
`addr-of` arms leave `emit-list`, `node-type`, `fn-rewrite-captures`,
`defvar-init-ir`, `defvar-check-init-order` and `gcheck-special-form`;
`retired-form-message` (`:3531`) gains `'addr-of' was retired: write &x, or (ref
x) / (ref p 'field)` beside the `.&` row, and `parse-type-from-node`'s
fall-through (`:2266`) consults it before `unknown-type-message`, so `(addr-of
T)` in a type slot gets the same answer; `addr-of` **stays** in
`build-special-form-set` (`:19548`) as `.&` and `cast` do — reserved, so the
message can never be shadowed; `lib/*.nuch` are regenerated (their remaining
`addr-of` lines become `ref`); the test units whose names say `addr-of`
(`s16-ref-sigil-addr-of-ir-identical`, `s16-addr-of-2arg`,
`s16-addr-of-2arg-node-type`) are renamed, their content kept (`&x` vs `(ref x)`
IR-identical). Gate: `make test`, `make bootstrap`; the `.ll` diff against PK-5a
is confined to string constants and the removed arms.

**Why retire rather than alias.** An alias means every future head-match site
must know two names — which is precisely the failure the type path just paid for
six times. Retiring also removes the last node the printer could emit that the
reader would not produce.

---

## 8. PK-6 — tests, example, docs

**Golden example** `examples/type-sugar.nuc` (+ `tests/expected/type-sugar.out`):
the §1.1 matrix, every row compiling and running — the sigil-paren class in
every position it failed in, plus a `defprotocol`/`extend` pair using `&Self`
and `?(Vector i32)`, a `deftype`, a list-form field `(link &Pt)`, and `(as &Pt
&p)` / `(sizeof &Pt)` from the existing `both-meanings` unit.

**Units** in a new `tests/suite-s21.nuc`, `import-use`d from `tests/nuctests.nuc`
(`:28–44` is the roster; a suite module is one compilation unit with it):

| Unit | Asserts |
| --- | --- |
| `s21-matrix-compiles` | the matrix source (embedded — no split needed; the 4095-byte literal cap is gone, Stage 21 R-1) compiles clean |
| `s21-nuch-roundtrip` | a module with a `defprotocol` using `&Self` / `?(Vector i32)`, a generic template with `(Vector ?Pt)` and `&Pt`, a `deftype`, `(link &Pt)`, an `extern`: `--emit-nuch` contains no `addr-of`, contains `(ref Pt)` and `(? (Vector i32))`; import it back from a `test-scratch-sub` and call through |
| `s21-ir-identical` | `?(V)`/`&(V)`/`&x` vs `(Maybe (V))`/`(ref (V))`/`(ref x)` — `check-golden` over the whole `.ll` |
| `s21-diagnostics` | `? (Vector i32)` with a space → the PK-3 message at the form's line (also at `alloca`, not line 0); `(? A B)`; `(Vector ?Pt)` declared and `(Vector i32)` passed → a type error, not silent acceptance (H5); after PK-5, `(addr-of x)` → the retirement message |
| `s21-value-annotation` | `q:?&Pt` in value position compiles and equals `(as ?&Pt q)` |
| `s21-match-ref-binder` | the `match` `(ref name)` binder still aliases in place (`examples/unions.nuc:34`'s shape) |
| `s21-macrolet-ref-refused` | `(macrolet ((ref …)) …)` is refused by name |

`s16-ref-sigil-*` (`tests/suite-s16.nuc:1278–1383`) stay as they are through
PK-1 (their fixtures still pass) and are renamed/re-spelled in PK-5.

**Docs, landing with the code they describe:**

| File | Change |
| --- | --- |
| `docs/types.md` §Type Syntax (`:41–68`) | the open-segment rule; `?(…)`/`!(…)`/`?!(…)`/`&?(…)`; reader-macro operands and literal elements fuse; the move to `read-form` |
| `docs/types.md` §Pointer kinds (`:254–284`) | `&T` is `(ref T)` everywhere; the "`(addr-of T)` is a legal, strange way" paragraph goes; `&x` is `(ref x)` |
| `docs/special-forms.md` (`:51`, `:57`, and the ~10 other mentions) | address-of is `&x` / `(ref x)` / `(ref p 'f)`; `addr-of` retired (PK-5) |
| `docs/generics.md` §Bounded generic `defn` | sigils in patterns (PK-4); the `:where` note for a wrapper under a template argument |
| `docs/errors.md` §`!T` | the `!(T …)` paren form |
| `docs/macros.md:420` | `~x:(T)` reads as `(unquote (x (T)))`; the list form stays the idiom |
| `docs/toplevel.md:26` | reader-macro table: `&` (ref) |
| `docs/structs-unions.md`, `collections.md`, `iterators.md`, `strings.md`, `builtins.md`, `stdlib.md`, `process.md`, `reading.md`, `testing.md`, `io.md`, `allocators.md`, `compiler.md` | the PK-5 noun sweep (`(addr-of` → `(ref` / `&x`) |
| `context/conventions.md:1145` | the entry "A standalone `&T` in a type slot is an `(addr-of T)` node" is **false after PK-1** — replace with one paragraph: `ref` has a value-position arm and its `node-type` twin (a future value-form head must be added to both); the colon-paren fuse fires in `read-form` on an *open* final segment, so a reader-macro operand and a literal element fuse too; `lib/read.nuc` must mirror any reader change or the parity units fail |
| `context/macros-jit.md:13` | the `~sym:type` note gains the `~sym:(Type)` reading |
| `design/stage16-ergonomics/ref-sigil.md` §6 | an **Update** line pointing here (original text kept) |
| `design/stage14/colon-paren-types.md` §2 "out of scope" | an **Update** line: the `!`/`?` + paren case and the `~sym:(Type)` reading are settled here |

---

## 9. Sequencing

Bootstrap facts this depends on (`context/build.md`, "Nucleus build flow" and
"Updating bootstrap artifacts"): `make` compiles `src/nucleusc.nuc` with the
committed boot compiler `bin/nucleusc` (rebuilt locally from `boot/nucleusc.ll`)
into `build/nucleusc`; `make bootstrap` diffs `build/nucleusc.ll` (emitted by the
boot) against `build/stage2.ll` (emitted by `build/nucleusc`); `make
update-bootstrap` rewrites `boot/nucleusc.ll`, copies `build/nucleusc` to
`bin/nucleusc`, and regenerates both Windows boot IRs (`make windows-boot`) —
only at a stable milestone. The boot reads `src/` and `lib/*.nuc` (the prelude
chain is inside the compiler's own translation unit) and **never** a committed
`lib/*.nuch`: `resolve-import` tries `.nuc` in every search directory before any
`.nuch`, and `make` regenerates nothing under `lib/`. The committed headers are
gated by `make test`'s `headers-generated` unit alone. A new *value* form the
compiler's own sources use — `(ref x)`, `(ref p 'f)` — is build.md's fourth root
cause ("renaming a spelling the source itself uses"): land the compiler accepting
both spellings, refresh the boot, then sweep and retire together. One refresh is
enough: the step-2 boot reads `(ref p 'f)`, so `src/` may drop `addr-of` in
step 3 without a second refresh, and the compiler that *refuses* `addr-of` is
never asked to read a source that still contains it.

**Item 2 lands between PK-1 and PK-2** ([one-reader.md](one-reader.md) §8:
PK-1 → R-1, R-2 → PK-2, PK-3, PK-4a → refresh → PK-5 → PK-4b, PK-6). PK-2's
fuse change — the open-segment gate, the segment split, the move from list
reading into form reading — is therefore made **once**, in the unified
`lib/read.nuc`, and the `lib/read.nuc` twins §1.5, §3 and §4 name apply only to
PK-1 (`rd-macro-name:494`, `&` → `"ref"`). The table below reads as written if
item 2 stalls (one-reader.md §8 says what reverses the order); otherwise step 1's
"`lib/read.nuc` twins land in the same commit" and the reader-parity gate hold
for PK-1 alone, and PK-2's gate is one-reader.md's `--dump-ast` corpus identity.

| Step | Content | Fixed-point argument | Gate |
| --- | --- | --- | --- |
| 1 | PK-1 + PK-2 + PK-3 + PK-4a | `src/`/`lib/` use no new spelling; `&x` emits identically under either head; every `fn-rewrite-captures`/`defvar-init-ir`/`defvar-check-init-order` arm is matched; `lib/read.nuc` twins land in the same commit | `make bootstrap` byte-identical; `make test` (with `check-headers.sh --fix` for the `&k` lines, §3); the reader-parity units |
| 2 | delete one-reader.md's `mint-collection-gensyms` (gensyms minted in `emit-collection-lit` instead), then `make update-bootstrap` | the deletion renumbers `__gs_N` and nothing else, so the bootstrap diverges by exactly that until the refresh — gated as Stage 20 S1 was: normalise `__gs_N`, diff, require identity; the refresh then absorbs it together with `(ref x)` | normalised-gensym identity before the refresh; `make clean && make && make bootstrap` after |
| 3 | PK-5a (the sweep script), then PK-5b | 5a: every rule rewrites to the same node, no literal touched — byte-identical `.ll` vs the step-2 build for the compiler, `ir-snapshot.sh verify` byte-identical for every other `.ll`, `.nuch` text diffs confined to signature spellings; 5b: `.ll` diff is string constants and removed arms | `make test`, `make bootstrap`, `ir-snapshot.sh verify`, `check-headers.sh` |
| 4 | PK-4b + PK-6 | may interleave with 3; PK-6's docs land with the code they describe | `make test`, `make bootstrap`, `examples/type-sugar.nuc` golden |

Every step ends with `make test` and `make bootstrap`. Step 1 is the only one
with a fixed-point risk, and its risk is entirely "a C site was missed": the
bootstrap diff, not a review, is what finds it.

---

## 10. Gates

* `make bootstrap` byte-identical after step 1 with no boot refresh; converged
  again after each of steps 2–4.
* `make test` green at every step; `reader-parity-{tests-fixtures,examples,lib,src}`
  and `headers-generated` in particular.
* PK-5a: `build/nucleusc.ll` byte-identical against the step-2 build;
  `scripts/stage17/ir-snapshot.sh verify` reports no `.ll` difference in any
  artifact, and its `.nuch` differences are signature spellings only;
  `sugar-sweep.py --dry-run` on the swept tree reports zero rewrites (idempotent)
  and its refusal list is recorded in progress.md.
* `grep -rn "addr-of" lib/*.nuch` empty after PK-5; `grep -rn "(addr-of " src lib
  examples tests` empty after PK-5a, save the retirement message and its test.
* `examples/type-sugar.nuc` compiles, runs and matches its golden output — every
  row of §1.1's matrix that this design claims to fix.
* The H5 regression unit fails on the pre-change binary and passes after PK-4a.
