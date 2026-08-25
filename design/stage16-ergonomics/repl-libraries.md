# Stage 16 — The standard library in the REPL

**Status:** Designed 2026-08-24. **Complete: R1 (§3.4) 2026-08-24; R2 (§3.1),
R3 (§3.2), R4 (§3.3), R5 (§3.5) and D9 (§3.3's closing note) 2026-08-25** — see
the "as built" note at the end of each of those sections. One item is left open
on purpose: the `(import-use node)` duplicate-symbol item (§6). D9's own note
records the one batch shape it deliberately does not close — a CT-defined type
named in a *signature*, which fails in the prescan, before emission. Filed in
[overview.md](overview.md) as "`import` doesn't seem to work in the REPL".

The item as filed understates it. `import` works; what does not work is
**everything a library needs after the import**. Sixteen of the 34 modules in
`lib/` fail to import at all, including every collection, every string module,
and the prelude itself — and no generic function, no lambda and no collection
literal can be evaluated at the prompt at all, whether or not an import is
involved.

Seven defects, all independent, all verified against `bin/nucleusc` on
2026-08-24. Three of them are the same underlying mistake wearing different
clothes: **a compiler global whose invariant holds for one module and one
process is reused by a driver that assembles many modules and never exits.**

---

## 1. The observation

The reported session, in full:

```
nuc> (import-use hashset)
lib/iterator.nuc:47: error: (Maybe T): value-Maybe template not in scope (import the prelude)
nuc> (import prelude)
lib/iterator.nuc:1: error: unknown: import — not defined anywhere in this compilation unit
nuc> (import-use prelude)
lib/iterator.nuc:1: compile-time: IR parse error: <compile-time>:453:1: error: redefinition of type
%Node = type { i32, i32, i64, ptr, ptr, ptr }
nuc> (import-use hashset)
nuc> #{1 2 3}
lib/iterator.nuc:1: compile-time: IR parse error: <compile-time>:545:16: error: use of undefined type named 'HashSet.i32'
nuc> (import-use hash)
lib/iterator.nuc:1: compile-time: IR parse error: <compile-time>:807:46: error: base element of getelementptr must be sized
nuc> (import-use iterator)
  IntRangeIter does not implement Iterator.next
lib/iterator.nuc:45: error: type 'IntRangeIter' does not conform to protocol 'Iterator'
nuc> (import-use hash)
nuc> (import-use hashset)
nuc> (contains? #{1 2 3} 2)
lib/iterator.nuc:1: compile-time: IR parse error: <compile-time>:574:13: error: use of undefined value '@conj.pHashSet.i32.i32'
```

Read as a whole it looks like one confused feature. It is seven, and the
transcript is misleading in three specific ways that this section clears first.

### 1.1 It is not hashset

Every module in `lib/`, one fresh session each,
`printf '(import-use NAME)\n' | bin/nucleusc -i` — **16 of 34 fail**:

| result | modules |
|---|---|
| `lib/iterator.nuc:47: (Maybe T): value-Maybe template not in scope` | `iterator` `vector` `list` `hashset` `hashmap` `combinators` |
| `unknown type: StrView` (with the correct W1c note naming `lib/prelude.nuc`) | `string` `strview` `strview-str` `string-protocols` `string-split` `keyword` `parse` |
| `!T: (Result T E) template not in scope` | `char` |
| `IR parse error: redefinition of type %Node` | `prelude` |
| `JIT error: Duplicate definition of symbol 'alloc-node'` | `node` |
| clean | `allocator` `arena` `coll` `error` `hash` `numeric` `string-errors` `macros`, plus the demo/facade fixtures (`avr` `boxlib` `mathlib` `nsdescribe` `nsdescribe2` `nsgeom` `nsgfacade` `seq` `testmacros` `unsafe-priv-demo`) |

The clean set is exactly the modules that name no prelude type — eight real ones
and ten fixtures. Everything built on `Maybe`, `Result` or `StrView` is
unreachable, and the module the diagnostic tells you to import is the one that
cannot be imported.

### 1.2 It is not imports either

With no import in the session at all:

```
nuc> (defn ident (x:T :where (Any T)):T (return x))
  error: redefinition: lookup of ident.impl.0 failed: Symbols not found: [ ident.impl.0 ]
  defined
nuc> (ident 5)
<repl>:1: compile-time: IR parse error: use of undefined value '@ident.i32'

nuc> ((fn (x:i32):i32 (* x 2)) 5)
<repl>:1: compile-time: IR parse error: use of undefined value '@__fn_lift_0'
```

Every generic instantiation and every lambda lift in the REPL is a call to a
function that is never defined (§2 D3). `@conj.pHashSet.i32.i32` at the end of
the transcript is this defect, not a collections defect.

### 1.3 Two framings in the tree are wrong, and both cost reading time

**`<compile-time>` is not the compile-time path.** It is the hardcoded
MemoryBuffer name at `src/nucleusc.nuc:13804` and the hardcoded prefix at
`:13809`, shared by all four JIT module kinds. The module in these errors is the
REPL's own, whose ID is `'<repl>'` (`src/repl.nuc:857`). Anyone debugging a REPL
IR error will start by reading `context/macros-jit.md`, which is the wrong file.
Give each module kind its own buffer name.

**The prefix-qualified imports do not "fall to the compiler path".**
`src/repl.nuc:474-483` and `design/stage12/namespaces.md:202` both say they do.
There is no compiler path from the prompt: they fall to the *expression* arm and
are compiled as function calls (§2 D7).

### 1.4 Prior art

[../4a-repl-issues.md](../4a-repl-issues.md) reports this exact class against the
first-pass REPL:

```
nuc> (import node)     lib/node.nuc:7:   error: unknown: arena-alloc
nuc> (import macros)   lib/macros.nuc:47: error: unknown type: Node
```

`repl-register-node` and `repl-preload-macros` (`src/repl.nuc:907-979`) are the
patch that closed those two cases — by hand-mirroring two prelude items into the
REPL instead of loading the prelude. D1 and D2 are the bill for that decision
coming due.

---

## 2. Seven defects

### D1 — the REPL never loads the prelude

Batch `main` auto-prepends `(import-use prelude)` — `strip-exclude-prelude`
(`src/nucleusc.nuc:17750`) / `prepend-prelude-import` (`:17782`), spliced at
`:17913-17916`. But `main` returns to `repl-main` at `:17872`, before reaching
it. `do-import` never prepends the prelude for an imported file, and no
`lib/*.nuc` imports it itself — every library assumes an ambient prelude
(`lib/iterator.nuc`'s only imports are `"stdio.h"` and `seq`, at lines 24-25).

The REPL substitutes two hand-written stand-ins:

* `repl-register-node` (`src/repl.nuc:907-949`) registers the `Node` struct and
  **four** of the seven `NODE-*` ordinals — `NODE-FLOAT`, `NODE-KEYWORD` and
  `NODE-CHAR` are missing, so a REPL session already types
  `(= k NODE-CHAR)` differently from a batch compile;
* `repl-preload-macros` (`:955`) evaluates the literal string
  `"(import-use macros)"` — `lib/macros.nuc` only.

Nothing registers `Maybe`, `Result`, `StrView` or `Clone`. The failure lands at
`src/union-registry.nuc:1989`, in `parse-type-from-node`'s `(Maybe X)` branch,
when `union-template-lookup-ref "Maybe"` (`:696`) finds nothing.

Why `lib/iterator.nuc:47` specifically: it is the first *concrete-receiver*
`defn` in the reachable graph whose return type is a value-`Maybe`. Protocol
signatures are stored verbatim and parsed lazily (`src/nucleusc.nuc:16177-16178`)
and generic-template `defn`s are retained unparsed, so `defprotocol (Iterator E)`
at `iterator.nuc:34` and `HashSetIter`'s `next` sail past; only
`(defn next ((self (ref IntRangeIter))) (Maybe i32)` is parsed eagerly by
`prescan-defn-signatures`.

### D2 — and the prelude cannot be loaded on top of that mirror

`src/repl.nuc:933` writes the type line straight into the session preamble:

```nucleus
(fprintf g-repl-preamble "%%Node = type { i32, i32, i64, ptr, ptr, ptr }\n\n")
```

without setting the StructDef's `emitted` flag — `register-struct` defaults it 0
(`src/abi.nuc:1115`). `emit-defstruct`'s already-defined guard reads exactly that
flag (`src/nucleusc.nuc:13149-13155`, whose own comment names the interactive
case), so the prelude's `defstruct Node` re-emits into the module's type buffer
while the preamble already supplies it. `repl-jit-module-rt-rewrite`
(`src/repl.nuc:845`) concatenates preamble (`:862`) + type buffer (`:865`) with
no dedup, and LLVM rejects the module.

Reproduced on a cold session with no prior import, so it is a hardcoded
duplicate, not a double module load:

```
$ printf '(import-use prelude)\n' | bin/nucleusc -i
<repl>:1: compile-time: IR parse error: <compile-time>:453:1: error: redefinition of type
```

D1 and D2 are one decision seen twice: mirror a slice of the prelude by hand, and
the real prelude becomes unloadable.

### D3 — `drain-mono-worklist` is never called on any REPL path

`generic-instantiate-in` registers the concrete `Method` with its mangled
`ir-name` — so **call sites can name `@conj.pHashSet.i32.i32`** — and queues the
*body* separately at `src/generics.nuc:2394`. Three other producers feed the same
queue: lambda lifting (`src/nucleusc.nuc:7009`), closure `invoke`/`drop`
(`:7488`/`:7603`), and the blanket-impl path (`src/generics.nuc:3711`).

`drain-mono-worklist` (`src/generics.nuc:3062`) has **exactly one call site in
the whole compiler**: `src/nucleusc.nuc:16417`, at the tail of
`emit-toplevel-forms` — which a prompt entry never reaches. So the call is
emitted and the callee never is.

Two sibling queues were REPL-adapted and this one was not. `drain-init-worklist`
early-returns under `g-interactive` (`src/nucleusc.nuc:16110`) and the REPL owns
the drain itself (`repl-emit-init-fn` / `repl-run-init-fn`, `src/repl.nuc:128`,
`:136`, called at `:189-191` and `:505-510`). `dyn-annot-record` takes an
immediate path under `g-interactive` (`src/nucleusc.nuc:7781-7783`). The mono
worklist got neither treatment, and nothing records that it was considered.

### D4 — the error path restores nothing, and the recovery block is dead code

`die-at` calls `repl_throw` when `g-interactive != 0` (`src/reader.nuc:53-54`), a
raw `longjmp` (`src/repl_shim.c:65`). It unwinds through `do-import` and
`emit-toplevel-forms`, skipping every `let`-save / `set!`-restore pair, because
every one of them sits *after* the call that dies.

| global | restore site skipped | consequence |
|---|---|---|
| `g-source-path` | `src/nucleusc.nuc:16935` | every later diagnostic names the failed library |
| `g-importing` | `:16933` | a retry of that import takes the cycle path (`:16893`) and **silently does nothing** |
| `g-toplevel-depth` | `:16429` | permanently +1; every later depth-1 whole-graph prescan and `drain-dyn-annots` is disabled |
| `g-unit-entry-path` | never restored (`:16140`) | feeds `def-linkage`, `path-in-unit`, the unreachable-definer note |
| `g-current-ns`, `g-ns-seen`, `g-file-imports` | `:16941-16943` | the library's namespace and import environment leak into the prompt |
| `g-out`, `g-def-stream`, `g-ct-emitting` | `:16665-16669` | the ct memstream at `:16657` is leaked |
| `g-import-ct`, `g-import-include-private`, `g-defining-private`, `g-mono-context` | various | stranded |

The stale `g-source-path` is the transcript's most visible symptom, and it is
directly demonstrable:

```
fresh session:            nuc> (zzz 1)  →  <repl>:1: error: unknown: zzz — …
after a failed import:    nuc> (zzz 1)  →  lib/iterator.nuc:1: error: unknown: zzz — …
```

**And the recovery block never runs.** `repl-main` calls `repl_try` twice per
form (`src/repl.nuc:1024` and `:1033`). The second call re-arms the buffer, so a
throw resumes *there* with value 1, `(= 1 0)` is false, `repl-eval-form` is
skipped, and control falls through — the block at `:1024`, including the Stage 16
macrolet-stack drain it was added for, is unreachable.
`tests/expected/repl-s16-macrolet.out` documents this silently: its error line is
followed directly by the next prompt, with no `error (recovered)` line and no
drain.

Separately, `repl_try` calls `setjmp` in its **own** frame
(`src/repl_shim.c:59-61`) and that frame has returned by the time `repl_throw`
fires. Jumping into a frame that has returned is undefined behaviour; it happens
to land at `repl_try`'s second call site on glibc/x86-64, which is the only
reason error recovery appears to work at all.

### D5 — `g-prescan-sigs` is marked before the prescan succeeds

`src/nucleusc.nuc:15707-15710`, in `prescan-imported-signatures`:

```nucleus
(when (and (!= path null)
           (= (import-list-has g-prescan-sigs path) 0)
           (= (as ptr (import-list-find g-imported path)) null))
  (set! g-prescan-sigs (import-list-push g-prescan-sigs path))
  …read the file, prescan-protocols, prescan-defn-signatures…
```

The push happens **before** the file is read. When the prescan dies, the marker
survives and the registration does not. A later real import of that file samples
`sigs-done` at `:16148` and takes the else branch at `:16187-16196`, which runs
`finalize-generics` and **skips `prescan-defn-signatures` entirely** — so
`IntRangeIter`'s `next` is never registered, and emission then fails at the
`extend` on the line above it:

```
  IntRangeIter does not implement Iterator.next
lib/iterator.nuc:45: error: type 'IntRangeIter' does not conform to protocol 'Iterator'
```

That is the transcript's most mystifying line, and it is a bookkeeping artifact
rather than a conformance problem: the type identity is fine, the method was
simply never registered.

The marker cannot be made advisory. `:16203-16207` records why — a second
`prescan-defn-signatures` over one file is a duplicate-overload error, because
`generic-register-method` appends unconditionally. Idempotence is not available;
only ordering is.

### D6 — `StructDef.emitted` is a process-wide latch in a many-module world

`emitted` is set when a `%Name = type {…}` line reaches "the one shared
`g-type-bufp`" (`emit-pending-struct-ir-type`, `src/union-registry.nuc:136-144`;
the rationale at `:166-179` states the assumption outright: *"the one buffer
every module — batch, CT, macro-JIT, REPL — concatenates"*). In batch there is
one module, so once is exactly right.

The REPL opens a fresh stream trio per entry (`open-module-streams`,
`src/nucleusc.nuc:17567`) and frees all three buffers at `src/repl.nuc:881`. Only
four arms copy a type buffer forward into the preamble — `defstruct` (`:228`),
`defunion` (`:253-259`), `import` (`:507-513`), libc preload (`:899-903`). A type
written into a module that is then **discarded**, or into an arm with **no copy**
(the expression arm and the `defn` arm), is marked emitted forever and never
appears again.

Demonstrated in two lines, using D2's failure to discard a module:

```
nuc> (import-use prelude)   ; fails on %Node; its type buffer is freed unread
nuc> (defvar sv:StrView)
<repl>:1: compile-time: IR parse error: use of undefined type named 'StrView'
@sv = weak_odr global %StrView zeroinitializer, section ".bss.sv", align 8
```

`context/repl.md`'s "REPL preamble / module-assembly invariant" section is a
hand-maintained workaround for precisely this, and it is **already incomplete**:
`lookup-or-make-anon-struct` (`src/union-registry.nuc:63-89`) writes directly to
`g-type-stream` and sets `emitted 1`, bypassing the queue the invariant assumes
everything uses. A rule a human must remember at every new emission site has
already been forgotten once.

The `pending-union-deps-ready` deferral (`src/union-registry.nuc:180-193`) reads
the same flag to mean "the dependency is present in the module currently being
assembled" — a sentence that is true in batch and false in the REPL. This is why
`#{1 2 3}` first reported `use of undefined type named 'HashSet.i32'`:
`%HashSet.i32` has an `%AllocHandle` field, `AllocHandle.emitted` was 0 because
the allocator import had aborted, so the type deferred; and once `allocator`
was imported by hand it emitted into *that* module, after which the flag blocked
it everywhere else. One flag produced both halves of the transcript's type confusion.

### D7 — four of six import forms are missing, and stamps get no declare

`repl-eval-form`'s dispatch `cond` has exactly one import arm
(`src/repl.nuc:484-486`):

```nucleus
(and (!= h null) (or (= h "import-use") (= h "import-only")))
```

`import`, `import-prefixed`, `import-ct` and `unsafe/import-private` fall to the
`true` arm at `:559`, which wraps the form in `__repl_eval_N` and calls
`emit-node` — compiling `(import prelude)` as a **function call** whose head is
`import`. `emit-dispatch` finds no binding and reports
`unknown: import — not defined anywhere in this compilation unit`. All four
spellings behave this way; `import-only` works only by accident of being in the
list.

[overview.md](overview.md) already records the general rule this violates, from
the `deftype` work: *"A new top-level form has six dispatch sites here — prescan,
emit, `.nuch` export, `.nuch` import, C header, REPL — plus the special-form set
and `text-token-is-definer`; only the first two follow from the feature's
description."* The REPL is the site that gets forgotten, and this item is the
standing evidence for that claim.

Relatedly: the import path's declare-backfill (`:516-557`) walks `g-globals` for
entries whose type is `TY-FN`. Monomorphized instances are **`Method`s in the
generic registry, not `Sym`s in the scope**, so no stamp ever reaches the
preamble by that route — a second, independent reason a stamped body is invisible
to the next prompt entry (see §3.2).

---

## 3. The shape of the fix

Four themes, plus one alternative evaluated and deferred (§3.6). The ordering
in §4 is not the ordering here: §3.4 must land first because state corruption
masks everything else.

### 3.1 One unit-entry path for both drivers (D1, D2)

Delete `repl-register-node` and `repl-preload-macros`; boot the REPL by
evaluating `(import-use prelude)` through the ordinary import arm, exactly as
batch `main` splices it.

This is safe where `(import-use node)` is not, because **every form in
`lib/prelude.nuc` is compile-time only** — the file says so at its head, and
Stage 16's prelude split is what made it true. The node/arena runtime moved out
to `lib/node.nuc`, so the prelude emits type lines and nothing else, and there are
no function symbols to collide with the compiler's own (§6).

Two things to state in the commit rather than leave implicit:

* the hand mirror was **silently wrong**, not merely partial — three `NODE-*`
  ordinals missing means a REPL session and a batch compile disagreed about
  `NODE-CHAR`. The import is more correct, not just shorter.
* `(import-use "string.h")` at `lib/prelude.nuc:17` re-imports a header the REPL
  already preloaded (`repl-include-all-libc`, `src/repl.nuc:885`). Header dedup
  already handles this — a session that types `(import-use "stdio.h")` after
  preload succeeds silently today — but it should be *tested*, not assumed.

Measure and record REPL startup cost before and after; the prelude pulls in
`lib/macros.nuc`, which the REPL was loading anyway.

**Verified prerequisite:** with the prelude's registration in place (even from
the *failed* module of D2), `(import-use hashset)` succeeds and `#{1 2 3}` stamps
`HashSet.i32` correctly, leaving only D3's missing body. That is the evidence
that D1/D2 and D3 are genuinely independent and that fixing this theme unblocks
the whole `lib/` tree at once.

#### R2 as built (2026-08-25)

The plan held. `repl-register-node` is deleted; `repl-preload-macros` becomes
`repl-preload-prelude` (`src/repl.nuc`), differing only in the literal it feeds
the reader — `"(import-use prelude)"` instead of `"(import-use macros)"` — so the
boot goes through the same protected `read-program` → `desugar` →
`repl-eval-form` loop and lands in the ordinary `import-use` arm. The prelude
imports `lib/macros.nuc` itself, so nothing else was needed to keep the standard
macros. Three comments elsewhere named the deleted functions and were updated
(`src/nucleusc.nuc` `intern-str`, `jit-ensure-init`, the `defmacro` REPL arm).

**The probe is 33 of 34 clean.** One fresh session per module,
`printf '(import-use <mod>)\n' | timeout 90 build/nucleusc -i`: every module that
failed for a missing-prelude reason now passes, including all six
`(Maybe T)` modules, all seven `StrView` modules, `char`'s `(Result T E)`, and
`prelude` itself (D2 is closed — nothing hand-writes `%Node` into the preamble
any more, so `emit-defstruct` emits it exactly once). The lone survivor is
`node`, whose duplicate-symbol failure §6 already scopes out as a JIT
symbol-resolution item.

**`NODE-CHAR` agrees with batch.** All seven ordinals evaluate to 0..6 at the
prompt and a batch compile of the same seven constants prints `0 1 2 3 4 5 6`.
The three the mirror omitted were not merely absent — `NODE-FLOAT`,
`NODE-KEYWORD` and `NODE-CHAR` had no binding at all, so a REPL session refused
the spelling a batch compile accepted.

**Startup cost: +22 ms, from 188 ms to 210 ms** (median of 15 runs each,
`printf '' | nucleusc -i`, comparison binary built from the same tree with only
the boot literal changed back to `macros`). That is ~12% of a cold session and
is dominated by the prelude's own `defstruct`/`defenum`/template registrations;
`lib/macros.nuc` is common to both.

**Header dedup verified, not assumed.** `(import-use "string.h")` at
`lib/prelude.nuc:17` re-imports a header `repl-include-all-libc` already
preloaded, and a prompt-typed `(import-use "stdio.h")`/`(import-use "string.h")`
after boot is silent too. Both are pinned by the new `tests/repl/prelude.in`
fixture, alongside the seven ordinals, the standard macros, a `?i32` `defn` +
`match` and a `(ref StrView)` signature.

**Two things the fixture could not cover, and why.** A `?T`-returning `defn`
typed with *no* import first dies with `Cannot allocate unsized type
%Maybe.i32`: the union's type line goes into that form's own module buffer and
is never carried to the preamble, so the next entry cannot see it — R4's
`emitted` epoch (§3.3), and the fixture works around it by importing a library
first. And `(dotimes (i 3) (printf …))` at the prompt prints nothing, on this
build and on the pre-R1 boot binary alike; the fixture uses `->` and `if`
instead. Neither is an R2 regression.

#### D8 — a per-module declare latch is blind to the REPL preamble

Found while probing R2, **pre-existing** (the pre-R1 boot binary fails
identically) and not fixed here. `(import-use error)` followed by
`(import-use arena)` dies with

```
lib/arena.nuc:56: compile-time: IR parse error: invalid redefinition of function 'alloc-node'
declare ptr @alloc-node()
```

`lib/error.nuc:25` does `(import-ct node)`, which registers `alloc-node` as a
`TY-FN` global, so the import arm's declare-backfill writes
`declare ptr @alloc-node()` into `g-repl-preamble`. `lib/arena.nuc`'s
`defmacro new` then builds a node, and `macro-jit-declare-raw`
(`src/nucleusc.nuc:1222`) writes the same line again — its dedup list
`g-macro-decls` is scoped to the CT module's own buffers, while the assembled
module is *preamble + ct-decl + ct-def* (`:14361-14374`). Two `declare`s of one
name is an LLVM parse error.

R2 does not cause it and does not widen it — the boot prelude adds no function
declares at all (it is compile-time only, and `lib/macros.nuc` imports nothing).
What R2 changes is reachability: both halves of the pair used to fail on their
own, so the collision had nothing to collide with. It belongs with §3.2's
declare backfill (R3) or §3.3's "a latch is a claim about a buffer" (R4),
whichever lands first; the general rule is that every REPL emission site holding
an "already written" latch over the fresh buffers must also consult the preamble.

### 3.2 A REPL-owned mono drain (D3)

Follow the `drain-init-worklist` precedent: the queue keeps its batch drain, and
the REPL owns a drain of its own. Four constraints, all imposed by existing code:

1. **Order.** The mono drain must run *before* `drain-pending-union-irs`
   (`src/repl.nuc:848`), because a drained body can stamp new parametric
   instances that then need their type lines. Draining types first and bodies
   second leaves the new types queued.
2. **Placement.** `drain-mono-worklist-in` sets `g-out` to
   `g-def-stream-program`, which `open-module-streams` already aliases to
   `g-def-stream` — so bodies land correctly if the drain runs between the
   current form's function being closed and the module being assembled. A drain
   *inside* a function must be bracketed with
   `push-function-state`/`pop-function-state` (`src/scope.nuc:221`/`:250`), the
   `macrolet` precedent at `src/nucleusc.nuc:14443`.
3. **Cross-entry visibility.** `g-mono-drained` (`src/nucleusc.nuc:331`) is a
   *persistent* cursor: each body is emitted exactly once, into whichever module
   first triggered it. The next prompt entry that calls the same instance gets a
   call with no `define` and no `declare`. So the drain needs a preamble backfill
   of ABI-lowered `declare`s — the analogue of `src/repl.nuc:368-385` (defn) and
   `:535-557` (import), but keyed off `Method.ir-name`, since stamps are not
   `Sym`s (D7).
4. **Trackers.** Drained bodies must **not** land in a `defn`'s per-impl module.
   That module carries a resource tracker (`src/repl.nuc:388`) which the *next*
   redefinition of that `defn` removes — silently un-defining every unrelated
   stamp that happened to be drained alongside it.

Recommended shape, satisfying all four: a `repl-flush-mono` step that drains the
worklist into its **own** fresh module, JITs it untracked on the main dylib, and
appends its type buffer and one `declare` per new body to the preamble. Call it
before each `repl-jit-module` and after each import.

This is `context/repl.md` rule 2 generalized from types to functions, and it
fixes the import path's missing stamp declares in the same step — a stamp created
during `(import-use vector)` is as invisible to the next entry today as one
created at the prompt.

#### R3 as built (2026-08-25)

The plan held; the shape §3.2 recommended is the shape that got built.
`repl-flush-mono` (`src/repl.nuc:1053`) drains into a module of its own and is
called at five sites — `:190`, `:259`, `:422`, `:536` and `:686`, the
`repl-eval-form` arms that can stamp. All four named constraints are
satisfied, and each is load-bearing rather than defensive:

1. **Order.** `drain-mono-worklist` runs before `drain-pending-union-irs` inside
   the flush, because a drained body can stamp new parametric instances that
   then need their type lines.
2. **Cross-entry visibility.** `g-mono-drained` is a persistent cursor, so a
   body emitted here is invisible to the next entry unless its `declare` reaches
   the preamble. `repl-backfill-progdefn-decls` (`:1039`) walks the module's own
   `g-program-defns` and emits one ABI-lowered `declare` per `define`, **after**
   the module is assembled — a `declare` and a `define` of one name in one
   module is the same LLVM error a duplicate `declare` is.
3. **Tracker isolation.** The flush JITs untracked on the main dylib. A `defn`'s
   per-impl module carries a resource tracker that the next redefinition of that
   `defn` removes, which would silently un-define every unrelated stamp drained
   alongside it.
4. **Stream discipline.** `open-module-streams` rebinds eight globals plus two
   per-module registries; the flush saves and restores all of them, and nulls
   the three `*-bufp` globals the nested `fclose` left pointing at freed
   buffers.

**D8 is fixed, by a preamble-scoped declare latch.** The root cause was a dedup
list scoped to the wrong buffer: `g-macro-decls` describes the CT module's own
buffers, while the assembled module is *preamble + ct-decl + ct-def*, so a name
already declared in the preamble got a second `declare`. The fix is
`repl-preamble-has-decl`/`repl-preamble-note-decl` (`src/nucleusc.nuc:1223`,
`:1229`) — a latch keyed on the buffer that is actually prepended to every
module. This is §3.3's principle applied one level down: **a latch is a claim
about a buffer, and it is only correct if it names the buffer it is about.**
`repl-note-globals-decls` (`src/repl.nuc:1025`) records names for the two sites
that hand the preamble a whole declaration buffer verbatim (the libc preload and
`extern`) rather than one lowered line at a time.

The same work surfaced a second instance of the same defect, unrelated to
macros: the `extern` declare dedup was process-wide, so `(extern stderr:ptr)`
reached by two collection libraries emitted its line into the *first* import's
module only and left every later module without it.

**A belt-and-braces filter backs the latch.** `repl-put-preamble`
(`src/repl.nuc:995`) copies the preamble into a module minus any `declare` for a
function that module defines itself, since one name cannot be both in one
module. It filters the *copy*, not the source — other modules still need the
declare. It short-circuits when the module defines nothing, which is most prompt
entries.

**One asymmetry, deliberately recorded rather than fixed.** `repl-put-preamble`
is wired into the two assemblers in `src/repl.nuc` (`:818`, `:919`), but
`emit-compile-time` (`src/nucleusc.nuc:14071-14073`) still copies the preamble
raw. D8's own reproduction goes through that path and is fixed anyway, because
the latch stops the duplicate `declare` from being *written* rather than
filtering it on the way out. Five probes for a CT module that both defines a
name and finds it declared in the preamble (macro redefinition, a `compile-time`
form calling a prompt-defined `defn`, macro-bearing libraries imported in both
orders, a `defn` either side of a macro import) found nothing. Left as is: the
filter is a second line of defence, and adding a call site with no failing case
to justify it is how the D6 class of bug gets built. Re-check when R4 touches
module assembly.

**Verification.** `make test` 808 PASS / 0 FAIL (baseline 806; `repl-stdlib` and
`repl-generics` are the +2), `make bootstrap` at its fixed point, `make` clean.
The reported transcript works end to end — `(import-use hashset)`, `#{1 2 3}`,
`(contains? #{1 2 3} 2)` → `1` — as do a lambda applied in place, a bounded
generic `defn` called at a later entry, and `[1 2 3]` once `vector` is imported.
The across-entries bar is pinned explicitly: a `HashSet.i32` stamp created at
entry 2 still resolves at entry 6.

**Stopped before this stage's own bookkeeping.** The implementation session was
interrupted after the code landed and before this note existed; the note was
written afterwards by reading the diff, so it describes the code rather than the
author's intent. Anything here that reads as a rationale for a choice is
inferred from the source and its comments.

### 3.3 The invariant: `emitted` must mean "in *this* module" (D6)

This is the theme the item was widened to cover, and the only one that removes a
class rather than an instance.

Replace the boolean latch with a **module epoch**. `open-module-streams`
increments a `g-module-epoch`; a `StructDef` records the epoch whose type buffer
its line was written into, plus a separate `in-preamble` bit set when a buffer is
copied forward. A type is emitted into the module being assembled iff it is not
in the preamble and its recorded epoch is not the current one.
`pending-union-deps-ready` then asks a question that is *true as stated* —
"is the dependency present in the module currently being assembled" — instead of
one that is true only in batch.

Consequences to argue explicitly when this lands:

* **Batch has exactly one epoch and no preamble**, so nothing changes there. The
  acceptance bar is a byte-identical `build/nucleusc.ll` and a converging
  `make bootstrap`, per the standard set in
  [container-type-sugar.md](container-type-sugar.md) §3.10.
* The four ad-hoc "copy the type buffer to the preamble" sites collapse into one
  rule applied at module close, which is what stops the fifth site from being
  written without one.
* `lookup-or-make-anon-struct`'s bypass and `repl-register-node`'s unset flag
  both stop being special cases — the first because the epoch makes the direct
  write self-describing, the second because §3.1 deletes it.
* `context/repl.md`'s invariant section becomes a *description of a mechanism*
  rather than a rule a future session must remember at each new emission site.
  Rewrite it accordingly rather than deleting it.

#### R4 as built (2026-08-25)

The epoch is the deliverable and it landed as sketched, but the sketch was one
field short and the "one rule at module close" half needed the module's *shape*
changed, not just its call sites tidied.

**Three fields, not two.** `StructDef` gains `emit-epoch` (the `g-module-epoch`
whose buffer holds its `%Name = type {…}` line; 0 = never written),
`in-type-buf` (that buffer was the module's TYPE buffer) and `in-preamble`
(`src/compiler-types.nuc:298-304`). `g-module-epoch` (`src/nucleusc.nuc`, beside
the stream globals) starts at **1** and is incremented by `open-module-streams`,
so `--emit-nuch`/`--emit-cheader`, which open no module, still differ from a
StructDef's default 0. `emitted` stays, unchanged in meaning, as "this type has a
definition at all" — the question `emit-defstruct`'s redefinition guard
(`src/nucleusc.nuc:13181`) and `defunion-register`'s *"already names a struct"*
(`src/union-registry.nuc:1004`) actually ask. That split is Stage 15 W9 item 40's
lesson applied again: the two questions had one bit, and only one of them is
about a buffer.

Two functions in `src/type-utils.nuc:99-116`, beside `sdef-layout-pending`:
`sdef-in-module` (`in-preamble || emit-epoch == g-module-epoch`) and
`sdef-note-emitted (sd out)`. Every read of `emitted` that meant "present in the
module being assembled" now calls the first, and every write now calls the
second: the two guards and the two sets in `emit-pending-struct-ir-type` /
`emit-union-ir-type`, `pending-union-deps-ready`, `defunion-register`'s
would-this-dangle test and its eager write, both cheader writers,
`fn-make-env-struct` and `emit-defstruct`.

**Decision 1 — `in-preamble` is its own bit, not a reserved epoch.** The preamble
is not a module: it is prepended to *every* module from the moment a line enters
it, so its correct encoding is "all epochs from here on", not one value. Epoch 0
is already the "never written" default, so reserving it would have put `emitted`
back to answering two questions — the exact defect being removed.

**Decision 2 — `lookup-or-make-anon-struct`'s bypass keeps its direct write, and
stops being a special case anyway.** §3.3 expected the epoch to fold it into the
normal path. Deferring it to the queue *cannot* be done under this stage's
acceptance bar: position within the type section is observable, and routing the
`%__anon_struct_h*` lines through the drain moves every one of them in the
compiler's own IR (conventions.md already records the same finding for
`defunion-register`'s backing struct). What R4 does instead is **queue it as
well** (`src/union-registry.nuc:88`): the eager write records its epoch through
`sdef-note-emitted`, and the queue entry makes the line *replayable* into a later
module. In batch the drain then finds `sdef-in-module` already true and skips —
zero IR movement, measured. The bypass is now self-describing, which is what
§3.3 wanted; it is the *deferral*, not the description, that had to stay out.

**The copy sites were six, not four, and they collapsed into one rule — but only
after the module stopped including its own type buffer.** §3.3 counted four
(defstruct, defunion, import, libc preload); R3 added two more (the
generic-template `defn` branch, and `repl-flush-mono`). The obstacle to
collapsing them was `context/repl.md` rule 1: a REPL module was assembled as
*preamble + this module's type buffer*, so the preamble could only be appended to
**after** the JIT, which is why every arm carried its own `strdup`/`fputs` dance
and why the arms that JIT'd through a shared assembler still could not share it.
R4 inverts that: `repl-absorb-type-buf` (`src/repl.nuc:985`) appends the type
buffer to the preamble *before* assembly and marks every StructDef whose line is
in it, and `repl-jit-module-rt-rewrite` no longer emits the type buffer
separately — **the preamble is now the type section of every module the session
assembles.** The assembled text is byte-for-byte what it was (an append to the
end of the preamble sits exactly where the separate `fputs` used to), and rule 1
dissolves rather than being restated.

`repl-absorb-type-buf` is called from one assembler plus six arm closes
(`:231`, `:265`, `:303`, `:435`, `:449`, `:1122` — defstruct, extern,
generic-template `defn`, `compile-time`, `defmacro`, libc preload); the last two
are new closes that also plug a leak, since those arms left their trio open. No
arm contains copy logic any more.

**A nested module needs the entry's types, which the epoch made *visible* rather
than fixed.** `repl-flush-mono` assembles a module *inside* the entry's own, from
the same preamble. Once `emitted` stopped being process-wide, the drain inside
the flush correctly judged the entry's already-written types absent from the
flush module and re-emitted them — and the entry's module then defined them
twice. The fix is `repl-cycle-type-buf` (`src/repl.nuc:996`), called at the top
of the flush: close the entry's type buffer into the preamble, bump the epoch and
open a fresh one. Both modules then read those types from the preamble and
neither writes them again. The flush restores the post-cycle epoch along with the
streams, so no two live buffers ever share an epoch.

**One extra defect fell out, and it is the same one.** A capturing closure's
`%__vfn_env_N` line was written to `g-out` — the *def* buffer — while the
`invoke` body it types is drained into the flush module. Every capturing `vfn`/`mfn`
typed at the prompt died with `base element of getelementptr must be sized`,
before R3 and after it. Under the REPL the line now goes to the type stream
instead (`fn-make-env-struct`, `src/nucleusc.nuc:7448`), so the cycle carries it
to the preamble before the flush module is assembled. Batch keeps `g-out` and its
IR is unmoved. `in-type-buf` is what keeps the record honest here: in batch, and
in a REPL `(compile-time (defstruct …))`, the line is *not* in the buffer the
preamble absorbs, and the absorb must not claim otherwise. It is deliberately not
consulted by `sdef-in-module`, so outside the REPL `sdef-in-module` is
**identically** `emitted` and no batch decision can move.

**Verification.**

* **Emitted IR byte-identical for 186 fixed inputs** — every `examples/*.nuc`
  (152) and every `lib/*.nuc` (34), `--emit-llvm`, pre-R4 binary vs. rebuilt
  `build/nucleusc`, `diff -rq` clean on stdout *and* stderr.
  `examples/comb-shapes.nuc` fails to compile on both, identically (a pre-existing
  `as: lossy conversion from usize to i32`, untouched by R4). Header modes swept
  too: `--emit-nuch` and `--emit-cheader` over all 34 `lib/` + 14 `src/` modules,
  96 outputs, identical.
* `make bootstrap`: `PASS: stage1.ll == stage2.ll`, `PASS: bootstrap complete`,
  no boot refresh needed.
* `make test`: **808 PASS / 0 FAIL** (unchanged — the two new cases were appended
  to existing fixtures rather than added as files). `make abi-test` and
  `make layout-test` both PASS.
* All 12 `tests/repl/*.in` fixtures pass. `tests/repl/prelude.in` gains section 6,
  the D6 repro proper: a `?i16`-returning `defn`, then `match` at the next entry.
  `?i16` rather than `?i32` deliberately — nothing else in the session stamps
  `%Maybe.i16`, so the case fails on the pre-R4 binary *even after* the
  `(import-use strview)` that section 5 leans on. `tests/repl/generics.in` gains
  section 6, the capturing-closure case.
* **D6 before:** `(defn f (x:i32):?i32 …)` then `(match (f 5) …)` →
  `IR parse error: Cannot allocate unsized type %Maybe.i32`. **After:** `5`.
* R2's and R3's own bars re-run: 33 of 34 `lib/` modules import in a fresh
  session (`node` still excepted, §6); the hashset transcript, `[1 2 3]`,
  bounded generics across entries and the D8 two-import pair all still work.
  A 25-form differential probe over every `repl-eval-form` arm, old binary vs.
  new, differs in exactly two places: a printed stack address, and the closure
  case that now succeeds.
* REPL startup 213 ms → 218 ms (median of 15), the cost of the `g-structs` walk
  at each module close.

**What §3.3 got wrong.** The copy-site count (four; it was six by the time R4
ran). The claim that the anon-struct bypass folds into the normal path — the
description folds, the deferral cannot. And the implicit assumption that the
copy sites could collapse by tidying call sites: they could not, until the module
stopped carrying its own type buffer alongside the preamble.

**D9 as built (2026-08-25).** The general statement the epoch permits:
**a type is recoverable across modules only if it is queued or absorbed.** Both
measured instances are fixed; the note above got their framing wrong in the same
way twice, and the correction is worth stating plainly before the changes.

**What the note got wrong: the batch/REPL split, for *both* instances.** The
second bullet reads as though the flush were a REPL bug whose fix would merely
*touch* batch; it is a **plain batch defect** and always was. The identical
program

```lisp
(compile-time
  (defn ctm (n:i32):?i32 (some n))
  (match (ctm 7) ((some v) v) (none 0)))
(defn main ():i32 (return 0))
```

compiled with `--emit-llvm` dies `:1: compile-time: IR parse error:
<compile-time>:164:16: error: Cannot allocate unsized type / %t5 = alloca
%Maybe.i32` on the pre-D9 binary. The first bullet has the mirror-image error:
it is framed as a prompt-only problem, and the batch shape *does* exist — see
"what D9 does not close" below.

**The three changes.**

* **The missing flush** (`src/nucleusc.nuc:14089-14093`). `emit-compile-time`
  drained and flushed at its *top* and then copied `g-type-bufp` into the CT
  module at assembly with no second flush, so any type the CT body itself
  stamped was written to the stream after the buffer was last materialized.
  `drain-pending-union-irs` + `fflush g-type-stream` now run immediately before
  the assembly, which is exactly what `compile-macro-body` (`:14413-14414`) has
  always done. The drained line lands in the *program's* type buffer, so the
  program module keeps it too — one write, read by both modules.
* **The queue entry** (`src/nucleusc.nuc:13226-13228`). `emit-defstruct` now
  `conj`s its `StructDef` onto `g-pending-unions` after its eager write, the
  same shape R4 gave `lookup-or-make-anon-struct`.
* **The ruling** (`src/nucleusc.nuc:13998-14000`) — see the next section.

**The text-identity proof the note asked for, discharged.** The queue entry is
IR-neutral only if `emit-pending-struct-ir-type` (`src/union-registry.nuc:139-148`)
renders a plain `defstruct` exactly as `emit-defstruct` (`:13220-13224`) does.
It does, on all four counts:

* **Header and terminator.** Both print `%%%s = type { ` from `(sd ir-name)`,
  `", "` between fields and `" }\n\n"` at the end — character for character.
* **Field count.** `emit-defstruct` loops `nfields = (- (node-len cc) 2)`;
  `defstruct-fill-layout` computes that same expression from the same node and
  hands it to `struct-set-fields`, which sets `num-fields` to it. The queued
  renderer loops `(sdd num-fields)`. Equal by construction.
* **Per-field type.** `emit-defstruct` prints `(type-to-ir (aref ftp i))`;
  `struct-set-fields` stores `(aref ftypes i)` — the same `ftp` array — into
  `Field.type`, and the queued renderer prints `(type-to-ir ((field-at (sdd
  fields) i) type))`. The same `Type*`, element for element.
* **No inserted members.** `struct-set-fields` `conj`s exactly `nfields` records
  and adds no padding or repr member; the union wrapper's repr/padding rule lives
  in `emit-union-ir-type`, which dispatches to the plain renderer whenever
  `is-union` is 0, and a `defstruct` never sets it.

The queue entry is also inert wherever the eager write already landed, because
the drain re-checks `sdef-in-module` before writing. Measured rather than
argued: the corpus sweep below is byte-identical.

**RULING: a `defstruct` inside `(compile-time …)` defines a PROGRAM type.**
Taken 2026-08-25, and recorded here so it stays reversible. The first draft of
D9 fixed only the prompt case and left a **batch** defect standing, which the
`--emit-llvm` sweep is structurally unable to see:

```lisp
(compile-time (defstruct D9P x:i32 y:i32))
(defn getx ():i32 (let (q:ptr:D9P (as ptr:D9P (alloca D9P))) (.set! q x 3) (return (q x))))
(defn main ():i32 (return 0))
```

`P` *is* registered for the whole unit, so a body-position use compiles — and
before the ruling `--emit-llvm` exited **0** with three `%D9P` references and
**zero** `%D9P = type` lines, with `-o` dying only later at `failed to parse
generated IR: base element of getelementptr must be sized`. Silent invalid IR at
exit 0 is the worst failure shape available.

The queue entry could not close it and never could: in batch `g-module-epoch`
never advances, so `sdef-in-module` stays true and the drain skips. **Queueing
recovers a type across EPOCHS; the CT module is a different BUFFER in the same
epoch.** The fix is therefore to write the line where both modules read it —
`emit-compile-time`'s `defstruct` arm now sets `g-out` to **`g-type-stream`**
explicitly rather than to the CT module's own `ct-type`. Explicitly, not by
deleting the assignment: every arm in that loop sets `g-out`, so inheriting the
previous arm's would make the behaviour positional.

The ruling makes the two drivers agree, which is what this document exists for —
the REPL fix in the same change already asserts that a CT-defined struct is a
program type (its fixture calls `d9-sum` at run time), so batch disagreeing was
exactly the divergence class §3.1-§3.5 keep removing. Reversing it means putting
`ct-type` back in that arm and accepting that a CT `defstruct` is CT-private.

Three consequences worth recording:

* **The line appears exactly once in the CT module.** It arrives from
  `g-type-bufp` (which the flush above now materializes) and `ct-type-bufp` is
  empty for such a block. That is checked rather than asserted: LLVM refuses a
  duplicate `%X = type` outright (`error: redefinition of type`), so a CT module
  that parses contains the line once. `ct-type` is left in place — still opened,
  concatenated and freed — as the home for any future genuinely CT-private type;
  it is simply unused today.
* **The queue entry is now redundant, and is kept anyway.** Measured, not
  argued: a scratch compiler built with the `conj` removed reproduces
  `tests/expected/repl-prelude.out` byte-identically and still emits one
  `%D9P = type` in the batch case. With the ruling, **all six** `emit-defstruct`
  call sites write to a type buffer — `emit-toplevel-forms`, the two `.nuch`
  import paths, the private-definer arm, the REPL's own arm and now
  `emit-compile-time` — so absorption covers every shape. The entry stays
  because it is the general "replayable across epochs" property D9 states as a
  rule, and it was proven inert; it is a standing invariant, not a live fix.
* **Where the *name* is visible, the type line is now present. The name's
  visibility to the prescan is a separate, wider defect and stays out of
  scope.** Naming a CT-defined type in a **signature** — `(defn getx
  (p:D9P):i32 …)` — still fails `unknown type: D9P — not defined anywhere in
  this compilation unit`, because `prescan-struct-names`
  (`src/nucleusc.nuc:15260`) is a flat walk over the top-level form list and
  never descends into a `compile-time` body, so `prescan-defn-signatures` cannot
  resolve it. Confirmed by discriminator rather than by reading: putting a
  `(printf "CT RAN\n")` first in the CT block produces the diagnostic with **no**
  `CT RAN`, so the refusal precedes any emission. The same ordering exists one
  level in — `emit-compile-time`'s own defn-signature prescan loop
  (`:13940-13984`) runs before its body-form loop (`:13986-14016`), so
  `(compile-time (defstruct D9P …) (defn ct (p:D9P):i32 …))` fails too. Fixing
  that means changing what a prescan walks, which is a much wider blast radius
  than D9.

**Gates.**

* **Runtime-IR neutrality:** every `examples/*.nuc` (152) and every `lib/*.nuc`
  (34), `--emit-llvm`, pre-D9 binary vs. rebuilt `build/nucleusc`, `diff -rq`
  clean on `.ll`, stdout, stderr **and** exit code — 186/186 byte-identical.
  `examples/comb-shapes.nuc` fails on both, identically (the pre-existing
  `as: lossy conversion from usize to i32`). Header modes swept too:
  `--emit-nuch` and `--emit-cheader` over all 34 `lib/` + 14 `src/` modules,
  96 outputs, identical. Re-run in full after the ruling, since that change
  moves a `defstruct` from one stream to another: still 186/186 identical, which
  is a real result and not a formality — a form-aware scan of all 441 sources
  (including the `tests/run-tests.sh` heredoc programs, which a `*.nuc` grep
  misses) found exactly **one** `defstruct` inside a `compile-time` block in the
  whole tree, D9's own new fixture. Note what the sweep does *not* prove: it
  covers the **program** module, and the flush changes **CT-module** IR — which
  is why D9 needed its own gate rather than a ride-along, and why the batch case
  below exists.
* **New batch gate** `run_s16_d9_ct_types` (`tests/run-tests.sh`), four
  assertions. `s16-d9-ct-body-stamp` compiles the `?i32`-in-a-CT-body program
  above and requires the CT output `d9 ct some 7` **and** no `IR parse error`;
  `s16-d9-ct-type-once` counts `%Maybe.i32 = type` in the emitted program module
  and requires exactly 1 (a re-drain's failure mode is a *second* line, which
  LLVM rejects); `s16-d9-no-duplicate-type-lines` asserts no `%X = type` line is
  duplicated in `examples/struct.nuc`'s module, which is the queue entry's
  inertness stated as something a test can check;
  `s16-d9-ct-defstruct-is-program-type` compiles the `D9P` program above and
  requires exactly one `%D9P = type` line, no `IR parse error`, and a binary
  built through `-o` that prints `7` — the last two together are the
  exactly-once check on the *CT* module, which is not otherwise inspectable.
  On the pre-D9 binary the first two and the fourth FAIL (the fourth as
  `%D9P = type x0`) and the third PASSes; on the rebuilt compiler all four
  PASS.
* **New REPL section** `tests/repl/prelude.in` §7 (beside R4's §6, same theme):
  `(compile-time (defstruct D9Pt …))` then a `defn` that allocas one, then a call
  returning `7`. On the pre-D9 binary the `defn` dies `IR parse error: base
  element of getelementptr must be sized` and the call reports `unknown:
  d9-sum`. It asserts a **value**, not merely that the entry compiled.
* `make test`: **813 PASS / 0 FAIL** (809 + the four new assertions). All 13
  `tests/repl/*.in` fixtures pass. `make abi-test` and `make layout-test` both
  PASS.
* `make bootstrap`: `PASS: stage1.ll == stage2.ll`, `PASS: bootstrap complete`,
  no boot refresh needed.

**A recorded "known limitation" fell out with the flush.** `context/build.md`
listed *"`(Maybe StrView)` fails in JIT/macro modules — the macro-expansion JIT
module doesn't include struct type definitions from imported libraries"*.
Measured: a `?StrView` inside a **`defmacro`** body compiles and runs on the
pre-D9 binary too (`compile-macro-body` has always re-drained), so the stated
cause was wrong for that half; a `?StrView` inside a **`(compile-time …)`** body
died `base element of getelementptr must be sized` on `%Maybe.StrView` pre-D9
and works now. The note has been corrected in place, with the one shape that was
*not* re-measured — the original `(Iterator StrView)` conformance — flagged as
needing its own diagnosis rather than that explanation.

**R3's asymmetry, re-checked as asked.** `emit-compile-time` and
`compile-macro-body` still copy the preamble raw rather than through
`repl-put-preamble`'s declare filter. R4 adds only *type* lines to the preamble,
so it neither causes nor widens that gap, and the five probes R3 recorded still
find nothing. Left as is.

### 3.4 A real unwind for the error path (D4, D5)

Three parts, in this order.

**Fix the `setjmp` first, by changing the shim's shape.** Replace
`repl_try`/`repl_throw` with a protected-call form that takes the body as a
callback:

```c
/* repl_shim.c */
int32_t repl_protect(void (*body)(void *), void *ctx) {
    if (setjmp(repl_jmpbuf) == 0) { body(ctx); return 0; }
    return 1;                     /* arrived here via repl_throw */
}
```

This is a better fix than collapsing the double `repl_try` (`src/repl.nuc:1024`,
`:1033`) into one call, and it is strictly cheaper than it looks. It fixes both
halves of D4's mechanism defect at once:

* **The UB goes away.** The `setjmp` frame is still live when the `longjmp`
  fires, which is the condition C requires and which today's shim violates —
  `repl_try` has returned long before `repl_throw` runs. The current code works
  by luck of a static `jmp_buf` and a stack that happens to still look right;
  it is exactly the kind of thing that breaks under a new LLVM or a new target,
  and this document's siblings ([avr-targets.md](../stage14/avr-targets.md),
  [riscv-linux.md](../stage14/riscv-linux.md)) are about new targets.
* **The double-arm bug becomes unrepresentable.** There is one call, and its
  return value distinguishes "ran normally" from "unwound". With two
  `repl_try`s the question "which call re-armed the buffer?" is invisible in
  the source, which is how the recovery arm came to be dead code without anyone
  noticing. A shape that cannot express the bug beats a corrected instance of a
  shape that can.

Handing the shim a Nucleus function pointer for C to call back is already
established: `repl_print_f64`/`repl_print_f32` (`src/repl_shim.c:18`, `:39`)
take a `void *fp` and call it, invoked from `src/repl.nuc:661` and `:663`. The
`ctx` pointer carries the current `Node*`.

`tests/expected/repl-s16-macrolet.out` should gain the `error (recovered)` line
it has always been missing, which is the visible proof the arm now runs.

**Then a named snapshot.** A `ReplState` struct with `repl-snapshot` /
`repl-restore`, covering the full roster in D4's table, taken at the top of every
top-level form and restored on the throw path. The roster is spelled **once**.
[keyword-markers.md](keyword-markers.md)'s lesson applies directly: collapsing
fourteen recognition sites into three helpers that take the bare name is what
stopped the roster being re-spelled at each site, and the same failure mode is
what produced D4 — every site saves and restores correctly *in isolation*, and
none of them survives a longjmp.

**Then the ordering fix.** Move the `g-prescan-sigs` push
(`src/nucleusc.nuc:15710`) to after a successful prescan. Worth calling out
plainly: this is a **batch-path correctness fix**, the only change in this
document that can alter batch behaviour on its own, and it wants its own
bootstrap check.

**Then decide rollback.** A died import leaves partial entries in `g-globals`,
`g-generics`, `g-structs`, `g-uniondefs`, `g-protocols` and `g-conformances`.
`g-globals` slices are already tracked (`import-list-push-slice`), so
truncate-to-watermark is available for at least that one. Recommendation:
**truncate**, over "mark the file failed and allow a retry". A half-registered
library answers name lookups with symbols that have no body, which is worse than
having no library — after the aborted `hashset` import, `(hashset-oom)` resolves,
typechecks, and dies in the JIT with `use of undefined value '@hashset-oom'`.
Where truncation is not available for a registry, record which registry and why,
rather than leaving the gap silent.

#### R1 as built (2026-08-24)

Three corrections to the plan above, and one gap the plan asked to be recorded.

**The shim takes a callback, and also a depth.** `repl_protect` is as sketched,
plus a small `jmp_buf` stack (`REPL_MAX_PROTECT` 16) and a `repl_depth`
counter, because two protected steps are needed per input line rather than one:
`desugar` runs before any form does and can `die-at` too, so it gets its own
`repl_protect` step (`repl-protect-desugar`, handing the form list back through
`g-repl-forms`) ahead of the per-form one (`repl-protect-eval`). They are
sequential, not nested — but the counter is what makes the *unarmed* case
defined. Today a `die-at` from a path no protect covers (anything before
`repl-preload-macros`, e.g. `repl-include-all-libc`) longjmps through an
uninitialised or already-returned frame; `repl_throw` now prints and `exit(1)`s
instead, which is what batch does anyway.

**Handing a Nucleus `defn` to C is expressible, but not with `as`.** The
readable spelling is to give the shim's declaration a real function-pointer
parameter type and pass the bare name:

```nucleus
(declare repl_protect (body:(fn void)(ptr) ctx:ptr):i32)
...
(repl_protect repl-protect-eval f)
```

which emits `call i32 @repl_protect(ptr @repl-protect-eval, ptr %f)`. The
obvious `(as ptr repl-protect-eval)` is *refused* — `as: reinterpretation from
__fnty_0 to ptr -- use unsafe/cast` — so a `ptr`-typed shim parameter would have
forced an `unsafe/cast` at every call site. Type the parameter, not the argument.

**"Move the `g-prescan-sigs` push to after the prescan" needs a second list.**
Taken literally the move is unsound: the pre-order push is also the *cycle
breaker* for the walk, and a cycle that does not include the unit root
(`A → B → C → B`) recurses forever without it — the root is the only file the
walk finds already on the list, pushed by `emit-toplevel-forms`. R1 therefore
splits the marker in two: `g-prescan-inflight` is pushed before the file is read
and popped after (the cycle breaker), and `g-prescan-sigs` is pushed only once
the prescan has actually run (the "registration happened" claim `sigs-done`
reads). The guard tests both lists, and `path-in-unit-exact` consults
`g-prescan-inflight` as well, so it keeps giving the answer it gave when one list
did both jobs. Measured IR-neutral: `--emit-llvm` output for all 152
`examples/*.nuc` is byte-identical to the pre-change compiler's, and
`make bootstrap` converged with no boot refresh.

**Rollback: what is truncated, and what is not.** `ReplState` (`src/repl.nuc`)
carries the D4 roster plus a watermark per registry, and `repl-restore`
truncates to it. Truncated: `g-globals` (`Scope.len`), `g-structs`,
`g-uniondefs`, `g-union-templates`, `g-struct-templates`, `g-type-aliases`,
`g-enumdefs`, `g-pending-unions`, `g-generics`, `g-protocols`,
`g-conformances`, `g-proto-supers`, `g-tmpl-conformances`, `g-macros`,
`g-macrolet-stack`, `g-cast-rules`, `g-rmacros`, `g-vtable-table`,
`g-boxedfn-table`, `g-dyn-table`, `g-mono-worklist`, `g-init-worklist`,
`g-dyn-annots` (the last three with their drain cursors clamped), and every
prepend-only import list by restoring its head. `g-generics` needs a *second*
watermark, because truncating the vector only recovers the generics the failed
import **created**: `generic-register-method` also appends to generics that
already existed. `GenericMark` records each pre-existing generic's method count
plus its `finalized`/`mangled` bits — the bits because `generic-add-method`
clears `finalized` as a side effect, and restoring the method list without them
would let `finalize-generics` re-decide mangling for an unchanged method set.

Not rolled back, deliberately, each with its reason:

* **`g-repl-preamble`.** It is an `open_memstream` with no truncation primitive
  that survives the flush semantics, and the four sites that append to it all
  append *after* the JIT succeeds — so a form that dies has written nothing.
  What can still leak is a `declare` line from an import that JIT'd its module
  and then died in the declare backfill; an unreferenced `declare` is inert.
* **`g-strs`** (the string-literal pool). `emit-string-table` writes the whole
  pool into every module, so a rolled-back entry costs bytes, not correctness —
  and an already-emitted preamble line may hold a `@.str.N` reference into it,
  which truncation would dangle.
* **`g-ns-prefix-table`, `g-priv-files`, `g-fn-attr-table`.** All three are
  `raw` (nullable) rather than `ref`, so each needs a null guard before `count`;
  none of them is read by a path that a partial registration can mislead —
  they are keyed by name and a stale entry is simply re-derived.
* **`g-binops`, `g-blanket`, `g-binding-kinds`, `g-deferror-*`,
  `g-include-paths`, `g-link-args`.** Built at startup or from argv; an import
  does not append to them.
* **The JIT session.** A module that parsed and loaded before the form died stays
  loaded. This is not reachable today (every `repl_throw` on the JIT path fires
  *before* the module is added), but it is the shape to check when R3 adds a
  drain that JITs its own module.

### 3.5 Import coverage and diagnostics (D7)

Add arms for `import`, `import-prefixed`, `import-ct` and
`unsafe/import-private`. The stated objection at `src/repl.nuc:480-483` — that
the alias-injecting forms would confuse a name-keyed declare backfill —
dissolves once §3.2 backfills from the definition side rather than by walking
`g-globals`. If the four arms slip past this stage, they must at minimum get a
targeted error naming the limitation, in place of
`unknown: import — not defined anywhere in this compilation unit`.

Three diagnostic fixes, each small and each independently worth doing:

* **Route the "import the prelude" messages through the mechanism that already
  works.** The compiler contains both the bad message and the good one. Compare:

  ```
  lib/iterator.nuc:47: error: (Maybe T): value-Maybe template not in scope (import the prelude)

  lib/string.nuc:54: error: unknown type: StrView — not defined anywhere in this compilation unit
    note: 'StrView' is defined in lib/prelude.nuc, which no import in this unit reaches
  ```

  The second names the file, the symbol and the reason. Seven sites need it:
  `src/union-registry.nuc:287`, `:304`, `:316`, `:1712`, `:1718`, `:1989`, and
  `src/union-emit.nuc:835`. After §3.1 these should be nearly unreachable — which
  is the point: a message that fires only in a genuinely broken configuration
  should be the most informative one in the compiler, not the least.

* **Make `import-use` say what it did.** Success is silent and the dedup no-op is
  silent, so they are indistinguishable. In the transcript the user re-imported
  `hashset` and got nothing back; they had no way to learn that the retry had
  been swallowed by the dirty `g-importing` stack (D4). `  imported hashset` and
  `  hashset already imported` would have shown it. This is the cheapest single
  item in the document and it addresses the user's actual complaint — that the
  errors were unhelpful — more directly than any of the correctness fixes.

* **Move the conformance detail below its headline.** `src/generics.nuc:4023` is
  a bare `fprintf` to stderr, so its per-method lines print *above* the `error:`
  line that `:4065` then emits. Use the `\n  note:` convention every other
  multi-part diagnostic uses, so the message reads top-down.

#### R5 as built (2026-08-25)

**The objection was stale twice over, and is deleted rather than honoured.**
§3.5 predicted it dissolves once §3.2 backfills from the definition side, which
it does — `repl-backfill-progdefn-decls` walks `g-program-defns`. But the older
half was already gone: **Stage 15 B2b deleted `inject-import-aliases`**, so
*no* import spelling injects alias `Sym`s any more. A prefix is a scoped binding
in `g-file-imports` resolved by `resolve-spelling`, and the arm's name-keyed
`g-globals` walk therefore sees exactly the same `Sym`s for a prefixed import as
for a flattening one. The comment at the head of the arm (which named a function
that no longer exists) is gone.

**One arm, six spellings** (`src/repl.nuc:511-528`). The predicate is the
four-way `or` nest, and the body is a `cond` over the five emitters —
`emit-import-use`, `emit-import-only`, `emit-import-ct`,
`emit-unsafe-import-private`, and `emit-import-prefixed` for both `import` and
`import-prefixed` (batch's `emit-import` is a one-line forward to it). Nothing
else in the arm changed: the flush/drain/JIT/backfill sequence R2-R4 built is
what every spelling now goes through. `unsafe-import-private` (the bare Stage 14
spelling, retired) is deliberately *not* an arm; batch answers it with a
targeted error and the REPL still says `unknown:`.

**Two latent defects surfaced the moment the four arms worked, and neither is in
§3.5.** Both are REPL-only and both are fixed here.

* **`internal` linkage hides a private definition from every later module.**
  `def-linkage` (`src/nucleusc.nuc`) returns `"internal "` for a
  `g-defining-private` definition. In batch there is one module and that is
  right; in the REPL each entry is its own object, so `(unsafe/import-private
  unsafe-priv-demo pd)` imported `pd/priv-secret` successfully and then died
  `Symbols not found: [ unsafe_priv_demo_p1__priv-secret ]` at the call. Under
  `g-interactive` the linkage is `weak_odr` instead. Batch is untouched, which
  the sweep below measures.

* **`do-import` asks `ct-sink-here` three times and the answer moved between
  them.** An imported file at the *prompt* runs at `g-toplevel-depth` 1 — the
  depth that means "unit root" everywhere else, because the prompt itself is
  depth 0 — so `emit-toplevel-forms` re-sampled `g-real-reachable` from inside
  a file that was being *sunk*, adding that file to it. The first call (which
  chose the sink) said yes; the third (which files the path) then said no, so a
  compile-time-only import was recorded on **`g-imported`**, the EMITTED list.
  A later real `(import-use X)` of the same library was deduplicated away and
  the program silently had no bodies for it. The re-sample is now guarded on
  `g-ct-emitting == 0`: a file being sunk is not a unit root. Batch reaches
  depth 1 only at the real root, where `g-ct-emitting` is 0, so the guard is
  inert there. Measured before/after: `(import-ct L)` then `(import-use L)`
  re-reads and emits `L` (a `compile-time` print in `L` fires twice, once), and
  `(import-ct L)` twice is now the no-op it claims to be.

**Diagnostics (a): seven sites, one wrapper, no module-boundary work needed.**
`missing-template-message` (`src/nucleusc.nuc`, beside `unknown-type-message`)
is `fmt-2s "%s: %s"` over the tiered message, so `?T`/`?!T`/`!T`/`(Maybe T)`/
`err handler` keep naming which spelling asked while the answer itself is W1c's.
`src/union-registry.nuc` already called `unknown-type-message` at two sites, and
`src/union-emit.nuc` already resolves nucleusc.nuc emit helpers through the
whole-unit prescan, so a direct call links from both — the ptr-hook treatment
§3.5 flagged as a risk was not needed. Before/after, `(exclude-prelude)` +
`(defn f (x:i32):?i32 …)`:

```
- noprel.nuc:2: error: ?T: value-Maybe template not in scope (import the prelude)
+ noprel.nuc:2: error: ?T: unknown type: Maybe — not defined anywhere in this compilation unit
+   note: 'Maybe' is defined in lib/prelude.nuc, which no import in this unit reaches
```

**Diagnostics (b): measured, not mirrored.** "Already imported" is answered by
watching the four registries an import can grow — `g-imported`, `g-ct-imported`
and `g-import-aliased` (all prepend-only, so the head pointer is a snapshot)
plus `g-globals`' length — rather than by re-deriving `do-import`'s three dedup
gates in a second place. That is what makes it right for the C-header spelling,
which has no "already imported" list at all but does register externs exactly
once: `(import-use "stdio.h")` after the libc preload correctly answers
`  stdio.h already imported`. The `g-interactive` gate §3.5 asked for is
structural — `repl-eval-form` is REPL-only — and the case that actually needed
suppressing was the session's own boot `(import-use prelude)`, which goes
through this same arm; `g-repl-booting` covers it, so a session still opens with
one line.

**Diagnostics (c):** `proto-sigs-resolve`/`-in` take a `notes:ptr:ptr`
out-parameter and accumulate `\n  note: <T> does not implement <P>.<m>`;
`verify-conformance-params` folds it into the headline with `fmt-3s`. Three
conversions, three arguments — the arity was hand-checked, per the fixed-arity
trap.

**Verification.**

* **Batch output byte-identical for 186 fixed inputs** — every `examples/*.nuc`
  (152) and every `lib/*.nuc` (34), `--emit-llvm`, pre-R5 binary vs. rebuilt
  `build/nucleusc`, capturing `.ll` + stdout + stderr + exit code; `diff -rq`
  clean. `examples/comb-shapes.nuc` fails on both with the identical
  pre-existing `as: lossy conversion from usize to i32`. Header modes swept too:
  `--emit-nuch` and `--emit-cheader` over all 34 `lib/` + 14 `src/` modules, 96
  outputs, identical. **No stderr differed** — the seven rewritten messages are
  unreachable in a well-formed unit, which is the point of them.
* `make bootstrap`: `PASS: stage1.ll == stage2.ll`, `PASS: bootstrap complete`.
  `make abi-test` and `make layout-test` both PASS.
* `make test`: **809 PASS / 0 FAIL** (808 + the new `repl-import-forms`).
* **Five REPL fixtures were re-recorded**, each for the same reason and nothing
  else: the import confirmation lines. `repl-g3-init`, `repl-generics` and
  `repl-import-error` gain one `imported …` line apiece; `repl-stdlib` gains
  three (`imported hashset`, `imported vector`, `imported error`) plus
  `arena already imported` — truthful, since `hashset` pulls `arena` in for
  real long before line 29 asks for it; `repl-prelude` gains
  `string.h already imported`, `stdio.h already imported` and
  `imported strview`, which is R2's header-dedup bar becoming *visible* rather
  than merely silent. The failing import in `repl-import-error` prints no
  confirmation, as it should — `die-at` unwinds before the report.
* New fixture `tests/repl/import-forms.in` / `tests/expected/repl-import-forms.out`
  covers all six spellings in one session, including the `import-ct` refusal,
  the ct→real transition, both dedup no-ops, and a private symbol called through
  its prefix. Output is deterministic across runs.
* R2's, R3's and R4's own bars re-run: 33 of 34 `lib/` modules import in a fresh
  session (`node` still excepted, §6); the D8 `error`+`arena` pair, the hashset
  transcript, `[1 2 3]` and the R4 `?i16`-across-entries case all still work.

**What §3.5 got wrong.** Its line numbers (drifted through R2-R4). Its
objection, which was already dead when it was written. And the implicit
assumption that the four arms were the whole job: the two defects above are what
"compiled as a call" had been hiding, and neither is visible until the form
reaches its emitter.

**Still open after R5.** D9 (§3.3's closing note) and §6's `(import-use node)`
duplicate-symbol item are the only items this document leaves. *(D9 was closed
2026-08-25; §6 is the only one left. See §3.3's "D9 as built" note for the one
batch shape D9 deliberately did not close, and for the ruling that a CT
`defstruct` defines a program type.)*

---

### 3.6 Why not Nucleus's own error handling? (evaluated, deferred)

The obvious question about §3.4 is why the REPL unwinds with `setjmp`/`longjmp`
at all, when Nucleus has had a value-channel error tier since Stage 10. It is a
fair question with a pre-existing answer, and the answer is a prerequisite, not
a preference.

**The REPL already does both.** `src/repl.nuc:1017` matches on `(read-program)`
with `(ok raw)` / `(err e)` arms — the *reader* half of the loop is already a
Nucleus `!T` value channel, converted by Stage 10 E4. `repl_protect` guards only
the *emitter* half. So "use `!T` instead" is not a new idea to evaluate; it is
"finish E4 into the emitter", and [errors.md](../stage10/errors.md):415-418
already named it as the intended endpoint: *"`die-at` sites in library-ish code
(reader, coercion) could become `!T` returns, which is also what the REPL wants
(today's `repl_throw` longjmp would become an ordinary error return path)."*

**The merits are real.** A value return unwinds *through* each frame, so every
`let`-save/`set!`-restore pair on the stack runs on the way out — which is to
say D4's roster mostly stops needing to exist, and §3.4's `ReplState` with it.
(Not entirely: `g-globals`, `g-prescan-sigs` and the macrolet stack are registry
mutations, not stack saves, and still need explicit rollback under any unwind
mechanism.) It also removes the UB and drops a C shim from a self-hosting
compiler's control flow.

**The cost is a whole-compiler refactor gated on a missing feature.** Measured
against this tree:

| | |
|---|---|
| `(die-at` call sites | **634**, across 9 files |
| distinct functions containing one | **235** of 1048 `defn` in `src/` |
| count when E4 landed (`errors.md:920`) | ~347 — the panic tier has roughly **doubled** since |

235 is not the conversion surface, though. `try` propagates only inside a
function already declared `!T`, so converting one `die-at` in `emit-node` forces
`emit-node` to `!T`, forces every caller to `try`, forces *their* return types
to `!T`, transitively. The emitter is one connected call graph; the realistic
converted set is most of `src/`.

**And `!void` does not exist** — recorded as a live limitation at
`docs/strings.md:329`, worked around by returning `!i32` with `0` for success.
Most emit functions return `void` because they write to streams. Converting them
requires either implementing `!void` first (a real feature in the union/niche
machinery, currently on no stage's plan) or spraying meaningless `(ok 0)`
returns through hundreds of functions. This is the gate, and it is why the next
increment Stage 10 itself scoped — the coercion path, `errors.md:929` — was
deferred with the reason *"deep in the emitter."* The compiler has been stalled
at the reader boundary since E4 for structural reasons, not for lack of will,
and the doubled `die-at` count is what that stall looks like from outside.

Two further costs: the conversion forfeits the byte-identical bootstrap bar
exactly where the change is largest; and it fixes none of D1, D2, D3, D5, D6 or
D7. Beyond that, **most of those 634 sites belong in the panic tier on the
merits.** Stage 10 §7.3 reserves `die-at` for bugs and unrecoverable states, and
a large share of these are internal-consistency assertions — `node-type`↔
`emit-node` lockstep violations, unreachable ABI classes. Converting an
assertion into an `!T` hands the caller an error it can only re-propagate. The
reader was the ideal first consumer because *all* of its errors are bad user
input; the emitter is a mix, and mostly the other kind.

**The prize is not the REPL.** `die-at` calls `exit(1)`, and there is no
error-count or continue-after-error machinery anywhere in `src/` — the compiler
reports exactly one error per run. A value channel is the *precondition* for
reporting more than one (not sufficient on its own: recovery points that
resynchronize are also needed, which the reader does not yet have either). That
is a Stage-16-sized ergonomics prize, and it — not REPL tidiness — is the
argument that would justify the cost. REPL recovery falls out of it as a side
effect.

**Verdict.** Keep `longjmp` at the REPL boundary for now; take §3.4's shim
reshape, which buys the correctness for ~10 lines of C. Record `!void` as the
gating feature for any further `!T` adoption. Reopen this when the goal is
multi-error batch reporting, and stage it leaf-first from the coercion path,
which Stage 10 already scoped.

---

## 4. Staging

| stage | content | acceptance |
|---|---|---|
| **R1** *(done)* | §3.4 — `repl_protect` shim reshape, `ReplState`, `g-prescan-sigs` ordering, rollback | a failed import leaves the session exactly as it found it; `make bootstrap` converges (the prescan fix touches batch) |
| **R2** *(done)* | §3.1 — prelude at REPL startup | every `lib/` module imports cleanly; `NODE-CHAR` agrees with batch; startup cost recorded |
| **R3** *(done)* | §3.2 — REPL-owned mono drain + declare backfill | generics, lambdas and collection literals evaluate at the prompt, and across entries |
| **R4** *(done)* | §3.3 — the `emitted` epoch | **byte-identical `build/nucleusc.ll`**; `context/repl.md`'s invariant section rewritten as mechanism |
| **R5** *(done)* | §3.5 — import forms + diagnostics | all six import spellings work; the diagnostics above |

R1 first because every other fix is unobservable while state corruption masks it
— the transcript's second, fourth and sixth errors are all consequences of the
first one having poisoned the session, and debugging R2 or R3 through that noise
is the trap this document exists to prevent. R1→R2→R3 is the minimum chain that
makes the reported session work. R4 is what stops the class recurring; it is
deliberately *after* the fixes it would otherwise be a prerequisite for, because
its acceptance bar (byte-identical batch IR) is the strictest here and should not
gate user-visible progress.

---

## 5. Test plan

The existing harness is `run_repl` (`tests/run-tests.sh:89-105`, dispatched at
`:5543-5547`): pipe `tests/repl/<name>.in` into `./build/nucleusc -i`, diff
against `tests/expected/repl-<name>.out`.

**None of the eight REPL fixtures that existed when this was written imports a
Nucleus library** (R1 added a ninth and R2 a tenth). Not one uses `(Maybe T)`,
`?T`, `!T`, `StrView` or `Clone`; `unions.in` defines its own local `defunion`.
`lib/` is tested exclusively through *batch* compiles of `examples/*.nuc`
(`examples/hashset-test.nuc`, `iterator-test.nuc`, …), every one of which goes
through `main` and therefore gets the auto-prelude. That is the
whole reason a total failure of the REPL's library surface has never shown up in
`make test`, and the gap is itself a finding: the fixtures cover the REPL's
*own* features (redefinition, globals, macrolet, by-value structs) and nothing
about the REPL as a **client of the rest of the compiler**.

New fixtures:

| fixture | covers |
|---|---|
| `repl-prelude` *(added by R2; §6 by R4)* | the seven `NODE-*` ordinals, the standard macros, `"string.h"`/`"stdio.h"` re-import dedup, a `?i32` `defn` + `match`, a `(ref StrView)` signature, `(import-use strview)`; R4 adds the D6 repro proper — a `?i16` `defn`, matched at the *next* entry |
| `repl-stdlib` | `(import-use hashset)`, `#{1 2 3}`, `(contains? … 2)` — the reported session, end to end |
| `repl-generics` *(§6 by R4)* | bounded generic `defn` + call, a lambda in expression position, `[1 2 3]`, and the same instance used again in a *later* entry (the `g-mono-drained` cursor, §3.2 constraint 3); R4 adds a *capturing* `vfn`, whose env struct never reached the mono-flush module |
| `repl-import-error` | a failing import, then a diagnostic proving attribution is back to `<repl>`, then a successful retry of the same import — R1's whole surface in one file |
| `repl-import-forms` | all six import spellings, including `(import mathlib)` and `(import-ct …)` |
| `repl-s16-macrolet` (edit) | gains the `error (recovered)` line, proving the recovery arm runs |

One caution for whoever writes these: the fixtures diff **stdout+stderr
combined** and the prompt goes to stderr, so error-path tests are sensitive to
output ordering. `repl-import-error` in particular pins behaviour that is
currently undefined-behaviour-adjacent (§ D4); it should be written after R1, not
as a red test before it.

---

## 6. Out of scope, and why

**`(import-use node)` fails with a duplicate symbol.** The compiler is linked
`-rdynamic`, so its own copies of the node runtime are exported and ORC finds
them before the module's. Verified:

```
$ nm -D --defined-only bin/nucleusc | grep -E ' (alloc-node|make-cell|node-at|node-len|arena-alloc)$'
0000000000018a00 W alloc-node
0000000000017840 W arena-alloc
0000000000018a10 W make-cell
0000000000018dc0 W node-at
0000000000018e00 W node-len
```

That is a JIT symbol-resolution question — the fix is a definition generator that
prefers the module's own definitions, or a REPL that declares rather than defines
a function the host already exports — not an import question, and it wants its
own item. It is narrow: the Stage 16 prelude split means the compiler's node
runtime is no longer pulled in by every program, so this bites `(import-use node)`
and the handful of libraries that reach it, not the `lib/` tree at large. Noted
here so the next session does not rediscover it from scratch.

**Redefining a `defn` with a different signature** remains unsafe
(`context/repl.md` already says so), and the spurious
`redefinition: lookup of <name>.impl.0 failed` on a *generic template* `defn`
(§1.2) is a near neighbour of D3 but not the same bug: `emit-defn` returns early
for a template (`src/nucleusc.nuc:13432`), so no `define` exists for the thunk
machinery at `src/repl.nuc:388-397` to rename. Fixing it is a one-arm guard and
should ride along with R3, but it is not what R3 is *for*.
