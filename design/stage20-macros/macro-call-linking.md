# Stage 20, part three — What a macro body may call

*Designed 2026-09-11. Brought back from the deferral in
[deferred/overview.md](../deferred/overview.md) §"A macro body may call only what
the compiler binary exports", which filed it as "a substantial feature, and not
one Stage 20 needs". Part of Stage 20 rather than a stage of its own for the
same reason [quasiquote-levels.md](quasiquote-levels.md) is: it is the same
subject — what a macro can do — and [overview.md](overview.md) §1.3 is where the
defect was found. Phases keep their own `L` prefix (linking), the way part two
kept `Q`.*

The deferral filed this as a missing feature. It is also a **soundness bug**:
when the program's name collides with one of the compiler's 2,285 exported
symbols the call does not fail, it silently binds to the *compiler's* function —
and with a mismatched signature it segfaults the compiler (§1.3). The fix for
the bug and the fix for the feature are the same change, and §6 shows the
bootstrap pays nothing for either.

---

## 1. What is broken

A macro body that calls a `defn` of the program being compiled fails in one of
three ways, chosen by where the callee sits and what the compiler happens to
export. All three were probed 2026-09-11 against `build/nucleusc` at `66ec31e`.

| # | shape | today |
| --- | --- | --- |
| 1 | callee defined **above** the macro | `JIT session error: Symbols not found: [ f ]` |
| 2 | callee defined **below** the macro | `compile-time: IR parse error: … use of undefined value '@f'` |
| 3 | callee's name is also a **compiler** symbol | binds to the compiler's function — silently, or a SIGSEGV |

### 1.1 Mode 1 — the link error

```lisp
(import-use node)
(defn my-ident (n:(raw Node)):(raw Node) (return n))
(defmacro ident (x) (my-ident x))
(defn main ():i32 (return (ident 7)))
```
```
JIT session error: Symbols not found: [ my-ident ]
probe-a.nuc: macro 'ident': JIT lookup failed
```

`macro-jit-ensure-decl` (`src/nucleusc.nuc:1383`) did its job: the macro module
carries a correct ABI-lowered `declare` for `@my-ident`. Nothing ever *defines*
it. The program's `define` is text in `g-def-buf`, waiting to be written to
stdout — it will not be compiled until `llc` runs, long after the macro had to
execute.

The same source compiles and runs in the REPL (§1.5).

### 1.2 Mode 2 — the raw LLVM parse error

Move the callee below the macro and the failure moves earlier, to IR parsing:

```lisp
(defmacro probe () (if (= (helper) 7) `7 `99))
(defn helper ():i32 (return 7))
```
```
probe.nuc:1: compile-time: IR parse error: <compile-time>:189:18: error: use of undefined value '@helper'
  %t0 = call i32 @helper()
```

`program-defn-lookup` (`src/scope.nuc:308`) searches `g-program-defns`, which is
populated by `program-defn-record` at the moment `emit-defn` writes the
`define` — so a callee the unit has prescanned but not yet emitted has no
`ProgDefn`, gets no `declare`, and the module is malformed. The diagnostic is
LLVM's, with LLVM's line numbers, against text the user cannot see.

### 1.3 Mode 3 — the silent bind, and the segfault

This is the one that makes the item a bug. `-rdynamic` exports **2,285**
symbols from `build/nucleusc`, of which **1,658** are spelled as ordinary
lowercase-hyphenated Nucleus identifiers. A program defn that lands on one of
them resolves to the compiler's copy, and nothing says so:

```lisp
(defn in-jit-module ():i32 (return 7))            ; also a compiler symbol
(defmacro probe () (if (= (in-jit-module) 7) `7 `99))
(defn main ():i32 (return (probe)))
```
```
$ ./probe ; echo $?
99
```

The program's `in-jit-module` never ran. The compiler's did, mid-compilation,
and its answer chose the expansion. The program compiles clean.

With a mismatched signature the same path is memory-unsafe. `desugar-form` takes
a `Node*`; give the program one that takes an `i32`, call it from a macro body
with `41`, and the compiler dereferences `41`:

```
$ build/nucleusc crash.nuc -o crash
Segmentation fault (core dumped)          # exit 139
```

No cast, no `unsafe/`, no C. An ordinary program with an unlucky function name
crashes the compiler.

### 1.4 What it costs

Beyond mode 3, the restriction the deferral recorded:

* **A macro body cannot call a helper of its own**, so no macro can share code
  with another macro, and no macro body can be factored.
* **A macro body cannot recurse.** A self-reference in head position is a macro
  *call*, so the only recursion available was a helper — which is mode 1. Every
  tree walk a macro needs is therefore written iteratively and inline, which is
  why [overview.md](overview.md) §8 had to rule out `macmap` over a computed row
  list and why `lib/fmt.nuc` hand-rolls what part two's nesting levels were
  supposed to free.
* **The 1,658-name minefield is an unversioned API.** Today it is load-bearing:
  `node-at` in `lib/error.nuc`'s `with-handler` body works *because* the
  compiler links `lib/node.nuc`. Nothing distinguishes that legitimate use from
  mode 3.

### 1.5 The REPL already does this, and that is a divergence

The mode-1 program runs at the prompt. So does a genuinely recursive helper:

```lisp
(defn depth (n:(raw Node)):i32 (if (= n null) (return 0) (return (+ 1 (depth (n 'cdr))))))
(defn mk-int (v:i64):(raw Node) …)
(defmacro dep (:rest xs) (mk-int (as i64 (depth xs))))
(dep 1 2 3 4)
```
```
nuc>   4
```

The identical file compiled in batch: `Symbols not found: [ mk-int, depth ]`.

The REPL JIT-compiles every top-level form as it arrives, so by the time a macro
expands, its callees are real code in the JITDylib; Stage 16 R3/R4 built the
preamble-of-`declare`s machinery that makes those modules agree
(`repl-preamble-declare-progdefn`, `repl-put-preamble`, `repl-backfill-progdefn-decls`,
`src/repl.nuc:1489-1598`). **The capability is not missing from the compiler. It
is missing from one of its two modes**, and a language whose REPL accepts
programs its compiler rejects has the defect in the compiler.

`(compile-time …)` blocks fail exactly as macros do — `Symbols not found:
[ twice ]` for a block calling a program `defn` — so this is one mechanism with
two consumers, not two problems.

---

## 2. Why

Four steps, each individually reasonable:

1. `emit-defn` writes a program function's whole `define … { … }` contiguously
   into `g-out` at the end of its work (`src/nucleusc.nuc:14675-14720`), which
   in batch is `g-def-buf`. It is **text**, assembled into a module only at
   `assemble-module-ir` (`:18707`), after every macro has run.
2. `macro-jit-ensure-decl` therefore cannot supply a definition and supplies a
   `declare` instead.
3. `jit-ensure-init` (`:14727`) attaches no definition generator — correctly,
   per [stage16-ergonomics/repl-jit-symbol-precedence.md](../stage16-ergonomics/repl-jit-symbol-precedence.md).
   LLJIT carries `LinkProcessSymbolsByDefault`, so the main JITDylib links a
   `<Process Symbols>` dylib **last**.
4. So an undefined `@f` in a macro module resolves against the compiler's own
   `-rdynamic` symbol table, or not at all. Mode 1 is "not at all"; mode 3 is
   "or".

That fourth step also holds the fix. Probes B and D of
repl-jit-symbol-precedence.md establish the precedence we need: **a definition
in the main JITDylib beats the process's copy**, and a module already added but
not yet materialised binds to it. So a definition put into the JIT before the
macro's lookup wins, with no generator, no filter, and no C shim.

---

## 3. The rule

### 3.1 Provenance decides, not the linker

> A name in a macro body means what it means in the program — **except** for the
> compile-time runtime, which is the compiler's.

The compile-time runtime is the set a macro body shares with the host *by
necessity*, because the host allocates, interns and reads the nodes the macro
returns. Concretely, a callee resolves to the **host** when both hold:

1. its defining file is under the library root **this invocation resolved the
   prelude through** (§3.5 — Q1 answered as option (a)), and
2. `build/nucleusc` exports the symbol.

Everything else resolves to **the program's own definition**, JIT-compiled on
demand into a *compile-time mirror* module (§5.5).

| callee | today | after |
| --- | --- | --- |
| `node-at` via `(import-use node)` | host | host — condition 1 ∧ 2 |
| `lib/test.nuc` helper (compiler links none of it) | `Symbols not found` | program's |
| the program's own `my-ident` | `Symbols not found` | program's |
| the program's own `in-jit-module` | **compiler's, silently** | program's |
| `printf`, `malloc` | host libc | host libc — unchanged |

Condition 2 is what keeps a `lib/` module the compiler does *not* link (mode 1
today) from turning into an unresolvable `declare`. Condition 1 is what closes
mode 3: a program defn is never silently displaced by a compiler symbol it
happens to collide with, because the program's is the one the mirror defines,
and the mirror is in main.

### 3.2 Why the runtime stays on the host

Not conservatism — three shared-state invariants:

* **One arena.** `alloc-node` → `arena-alloc` reads `g-arena`/`g-arena-cap`
  (`lib/arena.nuc:18-47`, lazily initialised). A mirrored copy would carry its
  own globals and hand the host nodes from an arena the host does not own. Since
  the mirror *declares* rather than defines anything host-exported, `g-arena`
  included, mirrored code allocates from the host's arena. The invariant falls
  out of the rule rather than needing a rule of its own.
* **One intern table.** Same argument for `intern-symbol` /
  `symbol-intern-bytes`: two tables means two `Symbol` identities for one
  spelling, and `Symbol` comparison is `icmp` on the interned pointer
  (`ProgDefn.ir-name`'s comment says so).
* **One `Node` layout.** During self-compilation the program *is* the compiler.
  A mirrored `make-cell` would build nodes to the new layout and hand them to a
  host that reads the old one. Keeping the constructors on the host keeps every
  node in one compilation on one layout — which is what happens today, and the
  one property of today's behaviour worth preserving deliberately.

The first four of these are already the set `compile-macro-body` hand-declares
(`:15255-15262`): `@alloc-node`, `@make-cell`, `@intern-symbol`,
`@symbol-intern-bytes`, plus `@nucleus_gensym` and `@nucleus_macro_error`. The
rule in §3.1 generalises that hand-written list into a derived one, and the
hand-written declares stay as they are.

### 3.3 What falls out

* Mode 3 closes without a diagnostic: the right function is simply called.
* Mode 1 closes for every program that is not the compiler.
* **The bootstrap flushes nothing** — every symbol a macro body in this tree
  calls satisfies both conditions (§6). Byte-identity is therefore not a hurdle
  to clear but a consequence.
* Cross-compilation must refuse the mirror (§5.9): the spans in `g-def-buf` were
  ABI-lowered for the *target*, and a macro body runs on the *host*.

### 3.4 Condition 1, spelled exactly — the prelude's root

**Decided: option (a), a path prefix** (§11 Q1 weighs all three). The root is not
a property of the binary: `try-import-path` (`src/nucleusc.nuc:17697`) searches
the current source file's directory, `lib/` **relative to cwd**, each `-I`,
`$NUCLEUS_LIB`, then the compiled-in `/usr/local/share/nucleus/lib/`, so a
development build finds its library at step 2 and an installed one at step 5.

So the root is defined by the one import every compilation makes and no program
writes: **the directory `lib/prelude.nuc` resolved through in this invocation.**
Captured once, at the auto-prelude import, into `g-ct-lib-root`;
`from-lib` on a `ProgDefn` is then "`g-source-path` begins with `g-ct-lib-root`"
evaluated at `program-defn-record`.

This is the right anchor rather than a convenient one: the prelude is the
compiler's own library by construction, it is resolved before any program form
is read, and whichever of the five steps found it is by definition the library
this invocation is using.

### 3.5 The sharp edges of (a)

Five, and each is a consequence of the sentence above rather than an oversight.
All five belong in `docs/` at L8, not only here.

**1. A cwd-relative `lib/` can capture the root.** Step 2 searches `lib/`
relative to cwd. A program run from a directory holding its own
`lib/prelude.nuc` makes *that* the root, and every module beside it is then
treated as compile-time runtime. The narrow failure: a project with a
`lib/node.nuc` of its own gets its `node-at` bound to the **compiler's** at
compile time, silently — mode 3 in miniature, surviving in exactly one shape.

An earlier draft said `--warn-ct-shadow` would be "re-aimed" to cover this, with
the warnable event being condition 1 ∧ 2 under a root that is not the compiled-in
install path. **That is wrong, and the arithmetic says so**: in this repo the root
*is* cwd-relative (step 2), so the condition holds for `node-at` in
`with-handler` and the warning would fire on every compile of anything that
prints — destroying the measured "fires zero times" property that lets
`--warn-ct-shadow` default on at all (§6, L4).

The two cases are not distinguishable from the path, which is Q1's (a)-versus-(b)
problem wearing a different hat: in-repo a cwd `lib/node.nuc` *is* the compiler's,
and in a user project it is not, and the resolved root reads identically. A
heuristic exists — warn only when the compiled-in install path exists **and**
differs from the resolved root — but it is environment-dependent in a way a
diagnostic should not be. So this edge is **documented and left unwarned**;
`--warn-ct-shadow` covers only the mode-3 shape (§11 Q2), which is the one with
the zero-fire measurement behind it.

**2. In-repo, the root is this checkout's `lib/`.** That is correct and is why
the bootstrap is free, but it means the rule's behaviour inside the repo is not
the behaviour an installed compiler gives. A test that passes from the repo root
may not be testing what a user sees; §8's tests must pin the root explicitly
rather than inherit cwd.

**3. Editing a `lib/` file does not change what a macro body calls until the
compiler is rebuilt.** Condition 2 asks the *running binary*, so a modified
`lib/node.nuc` under the root still binds to the host's old `node-at` at compile
time. This is §3.1's commitment stated as a consequence — at compile time,
library code is the compiler's build of it — and it is a real trap for anyone
debugging a `lib/` change by way of a macro.

**4. `-I` and `$NUCLEUS_LIB` can name a library the compiler was not built
from.** The root is then that one, and condition 2 still answers from the
running binary, so the two can disagree about what a module contains. The pair
is safe (a symbol either exists in the host or does not) but is not coherent;
the honest reading is that `-I` over the standard library is unsupported for
compile-time purposes.

**5. The comparison is on path spelling.** `resolve-import` interns the
concatenated candidate, so `lib/node.nuc` and `/abs/…/lib/node.nuc` are distinct
roots, and a symlinked or `..`-containing path may not prefix-match a root it is
genuinely under. This inherits `g-imported`'s spelling-equality limit (W9-1,
recorded at `def-linkage`) rather than adding a new one, and the failure
direction is safe: a spelling mismatch makes `from-lib` **0**, which mirrors —
a slower, more isolated answer, never a wrong-function one.

**And one non-edge, worth stating so it is not mistaken for one:** a program that
suppresses the auto-prelude has no root, so `from-lib` is 0 everywhere and every
program defn mirrors. That is the safe direction and needs no special case.

---

## 4. Four other designs, and why not

**A — JIT every program function as it is emitted.** The REPL's model applied
unconditionally. Correct and simple; it doubles LLVM codegen for every program
in the tree including the compiler's own 13 MB of IR. Rejected on cost alone.

**B — a second JITDylib with an explicit link order.** The semantically clean
way to express "host first, program second" or its inverse. LLVM 19's C API
exposes a search order only for explicit `ExecutionSession` lookups
(`LLVMOrcCJITDylibSearchOrder`, `Orc.h:216-229`); there is no
`JITDylib::setLinkOrder`. Reaching it needs C++, and Stage 16 retired
`src/repl_shim.c` on the standing rule that the compiler is pure Nucleus.
Rejected as unreachable, not as wrong — and filed as the first concrete want
for C++ interop in [deferred/overview.md](../deferred/overview.md) §"C interop
boundaries", where it belongs as a library question rather than a language one.

**C — copy the closure into each macro's own module.** Self-contained modules,
no shared dylib state, no precedence question. It forks the program's globals
per macro: two macros calling one helper get two copies of every global it
touches, and neither is the host's. Rejected — §3.2's invariants are the whole
point.

**D — diagnostics only.** Turn all three modes into located errors and keep the
restriction. Cheap, and a real improvement over a segfault. Rejected as the
*whole* answer, kept as the floor: L5 and L8 are exactly this, for the two
shapes that stay unsupported (forward reference, cross-compilation).

**E — the chosen design.** One *compile-time mirror* module per flush,
containing exactly the program definitions the macro closure needs and the
`declare`s for everything else, added to the main JITDylib before the macro's
lookup materialises.

---

## 5. The change

### 5.1 `ProgDefn` grows a span and a provenance bit

```
(defstruct ProgDefn
  ir-name:Symbol  (ret (raw Type))  ptypes:ptr  nparams:i32  variadic:i32
  ir-start:usize   ; byte offset of "define" in g-def-buf
  ir-end:usize     ; one past the closing "}\n\n"
  from-lib:i32)    ; defining file was under the compiler's lib root
```

`program-defn-record` (`src/scope.nuc:320`) is called at almost exactly the right
instant — **one line after** `emit g-out "define "`, not before it, as L1 found;
moving it above that `emit` is emission-neutral (`defn-ir-name` and
`program-defn-record` are both pure with respect to the streams) and makes
`ir-start` the byte `define` lands on. `ir-end` is the same expression after
`emit g-out "}\n\n"` at `src/nucleusc.nuc:14719`. `from-lib` is a path test on
`g-source-path` at record time.

Two details L1 settled that the sketch leaves open. The record is idempotent by
`ir-name` and now returns the fresh `ProgDefn` or **null** when it declined, so a
second emission of one name cannot pair its `ir-end` with the first's
`ir-start` — `program-defn-note-end` is a no-op on null. And `ir-start == 0` is a
legitimate offset (the first `define` in the buffer), so `note-end` re-asks the
`g-out` guard rather than reading `ir-start` as a flag; only `ir-start == ir-end
== 0` means "no span".

The root is stored as a bare directory (`lib`), and `path-under-ct-lib-root`
requires a `/` after it, so a root of `lib` does not claim `libfoo/x.nuc` — a
false positive there would be §1.3's silent bind surviving, which is the one
direction §3.5 edge 5's tolerance may not take.

**The one trap:** `g-out` is not always `g-def-buf`. `emit-defn` runs inside
`compile-macro-body`'s redirect, inside the REPL's per-entry buffers, and inside
the `sink` redirect at `:17762`. Record a span only when
`g-out == g-def-stream-program` and that is `&g-def-buf`; otherwise store
`ir-start == ir-end == 0`, which the flush reads as "no span, not mirrorable".

This phase is inert — nothing reads the fields yet — which is what makes it
gateable on its own.

### 5.2 `host-exports?`

```lisp
(defn host-exports? (irn:Symbol):i32)   ; process symbol lookup, memoised
```

**Through LLVM, not `dlsym`.** The obvious spelling is
`dlsym(RTLD_DEFAULT, name)` — `-ldl` is already linked (Makefile:76) and
`RTLD_DEFAULT` is `((void*)0)` on glibc, so it needs no constant. It is the wrong
one: `make windows-boot` cross-emits `boot/nucleusc-x86_64-windows-{gnu,msvc}.ll`
from this same source (Makefile:224-226), and a POSIX-only extern lands in both.
The same mistake shape as the `[1 x %__jmp_buf_tag]` caveat that Stage 16's shim
retirement left behind.

`llvm-c/Support.h` has the portable pair, and the compiler already links LLVM and
carries `src/llvm.nuch` for its declares:

```c
LLVMBool LLVMLoadLibraryPermanently(const char *Filename);   /* NULL = this process */
void    *LLVMSearchForAddressOfSymbol(const char *symbolName);
```

`SearchForAddressOfSymbol` iterates the handles `LoadLibraryPermanently` opened,
so `LLVMLoadLibraryPermanently(null)` must be called once — memoised — before the
first lookup, or the search set is empty and every answer is a false negative.
A false negative is the safe direction (it mirrors instead of binding the host),
which is exactly why it would go unnoticed: **L2's gate has to prove a positive**,
not just that nothing crashed.

Exported names carry their hyphens verbatim, so no mangling is involved. Memoise
the per-name answer on `Symbol` identity — the closure walk asks once per callee.

### 5.3 The roots: `macro-jit-ensure-decl` splits

It keeps emitting the `declare` in both cases — the macro module needs one
either way. It gains one branch:

```
from-lib ∧ host-exports?  →  declare only                    (today's path)
otherwise                 →  declare, and note as a mirror root
```

Roots accumulate per macro/CT body, alongside the existing per-module
`g-macro-decls` latch, and are stored on the `MacroDef`
(`src/compiler-types.nuc:1076`) so the flush at expansion time can find them.
A `compile-time` block's roots go on its own record, keyed by its
`@__compile_time_main_N` symbol.

Mode 2's callees have no `ProgDefn` at all and are handled by L5, not here.

### 5.4 The closure walk is over IR text

From each root, scan its span for `@`-prefixed tokens and classify each:

| token | action |
| --- | --- |
| a `ProgDefn` satisfying §3.1's two conditions | `declare` (ABI-lowered from the `ProgDefn`) |
| any other `ProgDefn` with a span | include its span; recurse |
| a `ProgDefn` with no span | refuse (L5's diagnostic) |
| a `ProgGlobal` | L6: the same three-way split — declare when host-owned or already mirrored, else copy the span and scan it |
| any other name in `g-globals` that is not a function | refuse |
| `@.str.*`, `@__cons`, `@__append` | skip — already in the module (§5.5) |
| anything else (libc, externs) | skip — `g-decl-stream` already declares it |

Text, not a recorded call graph, because the IR is the ground truth of what a
function references — a call the emitter made through a path nobody thought to
instrument still appears as `@name`. It is safe to scan a *function body* span
this way: inline `c"…"` bytes appear only in global definitions, never inside a
`define`, so no `@` inside the span is a string's.

The ABI-lowered `declare` already exists twice — `macro-jit-ensure-decl`'s own
body and `repl-preamble-declare-progdefn` (`src/repl.nuc:1489`). Generalise the
REPL's to take an out-`String` (the `abi-print-param-to` treatment) and call it
from all three places rather than writing a fourth.

### 5.5 The mirror module

Assembled exactly as `compile-macro-body` assembles a macro module:

```
; ModuleID = '<ct-mirror N>'
target triple = <host>
<g-type-stream>            ; already copied into every JIT module
<string table>             ; emit-string-table, as macro modules already do
<g-decl-stream>            ; externs and includes
<declares for host-resolved callees>
<the chosen spans, verbatim>
```

Added with `jit-add-module` on the main JITDylib, untracked. ORC materialises a
module on lookup, so adding it costs an IR parse and nothing more until a macro
actually calls into it.

**When.** At `expand-macro-call` (`src/nucleusc.nuc:11136`), immediately before
`LLVMOrcLLJITLookup` at `:11169` — not at `defmacro` time, because a callee
defined between the `defmacro` and its first call site is only emitted by then.
Same treatment at `jit-call-ct-main-sym` (`:14781`). A flush with an empty
closure emits no module and is free.

**No symbol twice.** A session-wide `g-ct-mirror-defined` set gates every span:
a second flush that needs an already-mirrored function declares it instead.
Without this, the second flush is `Duplicate definition of symbol`.

**REPL.** Gate the whole path on `(= g-interactive 0)`. The REPL reaches the
same end by its own route and must not grow a second one.

### 5.6 `internal` → `weak_odr`, in the copy only

`def-linkage` (`:776`) emits `internal ` for a `defn-` in batch and `weak_odr `
in the REPL, and its comment gives the reason this phase needs:

> A REPL module is its own object, so `internal` would hide a private definition
> from the later entry that spells it.

A mirror module is its own object too. Since a span is copied text, rewrite it
at the one place that copies: a span beginning `define internal ` is written as
`define weak_odr `. The program's own bytes are untouched, so nothing moves in
the emitted `.ll`; only the CT copy changes linkage, and only for private defns
a macro body actually calls.

Two private defns of one spelling in different namespaces would collide under
`weak_odr`. Stage 12 N4's IR mangling gives namespaced defns distinct IR names,
so the collision needs two same-named privates in the *same* namespace, which
the one-symbol-one-kind rule already refuses. Noted, not defended against.

### 5.7 Globals, and the single-cursor trap

A mirrored function touching a program global needs the global *defined* in the
mirror (it is not host-exported, or §3.1 sent us to the host's) and, if its
initializer is a runtime one, *run*.

`emit-defvar` gets the same span treatment as §5.1. The initializer is the
hazard: `init-emit-function` (`:17026`) drains `g-init-worklist` through the
single cursor `g-init-drained`, and the program's own `@__nucleus_init` is
emitted from what is left at the end of the unit. **A CT drain that consumes the
cursor silently deletes those initializers from the program.** So the mirror
emits its own `@__ct_init_N` — the jobs are emitted twice, into two modules,
which is correct and is the only arrangement that is.

**Corrected at L6: "from a snapshot of the cursor, and restore it" is the wrong
filter, and the cursor is not needed at all.** A snapshot drain emits *every*
pending job, including `set!`s for globals this mirror does not define — an
undefined `@g` in the module — and restoring the cursor makes the *next* flush
emit the same jobs again, running a shared global's initializer twice, which is
exactly what this phase's "one value, not two" gate refuses. The filter that is
correct is the one `InitJob.ir-name` was added for: **the jobs of the globals
this mirror DEFINES**, which `g-ct-mirror-defined` already makes a
define-exactly-once set. `g-init-drained` is then never touched, and the
program's `@__nucleus_init` keeps every job by construction rather than by a
restore that has to be remembered. See §7 L6.

`@__ct_init_N` is called once, before the first expansion that needs it. Jobs
queued after a flush belong to the next one.

This is the largest sub-piece and is why L6 is separate: a macro body calling a
pure helper needs none of it, and §6's gate is met without it.

### 5.8 Forward references (mode 2)

Supporting them means deferring the whole macro module until first expansion,
which reorders macro compilation against everything else in the unit. Not in
this stage. L5 replaces LLVM's parse error with a located one:

```
probe.nuc:1: error: macro 'probe' calls 'helper', which is defined later in this unit
  note: a macro body may only call functions defined above it — move 'helper' above the macro
```

Reachable precisely: the name resolves in `g-globals` to a `TY-FN` `Sym` with no
`ProgDefn`, at `macro-jit-ensure-decl`. That is also the check that turns
"`ProgDefn` with no span" (§5.4) into a message instead of a malformed module.

**Corrected at L5: that test is not precise, it is one condition short.** A
`defn` defined inside the `(compile-time …)` block being compiled satisfies it
exactly and must not error. See §7 L5 for the fourth condition and the
measurement.

### 5.9 Cross-compilation

`g-def-buf`'s text was ABI-lowered for `g-target`; a macro body runs on
`g-host-target`. Splicing target spans into a host-triple module is wrong
wherever the two ABIs differ, which for the Stage 14 targets is everywhere. When
a flush is required and the target differs from the host, refuse with a located
diagnostic naming the macro and both triples. Calls that resolve to the host
(§3.1) are unaffected, so cross-compiling anything in this tree today is
unaffected.

**Corrected at L8: the comparison is on the two TRIPLES, not on `g-target` vs
`g-host-target`.** `target-init` builds a second `Target` for any `--target=`,
including one spelling the host's own triple, so the object test refuses an
identical ABI. See §7 L8.

---

## 6. The gate

**Bootstrap must flush zero mirror modules and move zero bytes.** Both follow
from §3.1, and the argument is structural rather than empirical:

* A `lib/` macro body can only name what is in `lib/` scope, and `lib/` imports
  nothing from `src/`. So **no macro body in this tree can call a `src/`
  function**, whatever it wanted to.
* Measured 2026-09-11 over all 42 `defmacro`s in `lib/`+`src/`, the 16 in
  `examples/`, and the 9 `macrolet` sites: **at expansion time they call
  `gensym`, and `node-at` once.** Everything else inside a body is quasiquoted
  — emitted code, not a compile-time call — or is member access on a
  `(raw Node)`, which is a GEP and a load rather than a call (`lib/macros.nuc`'s
  25 macros, the `+ - * /` and `and`/`or` arms included, are all of this shape;
  `lib/macros.nuc:374` says so deliberately).
* The one call is `node-at` in `lib/error.nuc`'s `with-handler`
  (`lib/error.nuc:83-86`), a `lib/` defn the compiler links. Both conditions
  hold, so it declares, as today, byte for byte.

So the mirror flushes nothing anywhere in the tree — not during the bootstrap,
not under `make test`, not in the examples — and §8's new tests are the only
thing that exercises the path. That is a comfort for the gate and a warning
about coverage: a change to `ct-mirror-flush` breaks nothing the rest of the
suite would notice.

The gate is therefore two assertions, not a diff review: `make bootstrap`
converges byte-identical, and a counter of mirror modules emitted during the
compiler's own compilation reads **0**. If either fails, §3.1's provenance test
is wrong, and that is the thing to fix.

The compiler is also the *reason* the rule is shaped this way rather than
"the program always wins": the program-always-wins rule is semantically tidier
and would make self-compilation mirror `lib/node.nuc` into a second arena, which
§3.2 rules out.

---

## 7. Phases

Each phase states its own gate. L1–L4 are the feature; L5–L8 are the edges.

### L1 — spans and provenance
**Status: done 2026-09-11.** `g-ct-lib-root` (`src/nucleusc.nuc`, captured by
`ct-lib-root-note` from `do-import`'s resolved path); `ProgDefn.ir-start` /
`ir-end` / `from-lib` (`src/compiler-types.nuc`); `ct-span-recordable`,
`path-under-ct-lib-root`, `program-defn-note-end` and a `?ptr:ProgDefn`-returning
`program-defn-record` (`src/scope.nuc`). One correction to §5.1 below: the record
call sat one line **after** the `define` emit, not before it, so it had to move
for `ir-start` to mean what the field says. Gate met — `make bootstrap`
byte-identical, `make test` 996/0/0, and a throwaway `--dump-spans` equivalent
(since removed) verified 1,946 spans over the compiler's own 12.5 MB of
definitions: ascending, disjoint, each exactly one `define …}\n\n` block whose
`@name` matches its `ir-name`, with `@__nucleus_init` and the `@g-*` globals the
only text outside a span, and `g-ct-lib-root` = `lib` from the repo root.

Three pieces, all inert:

* `g-ct-lib-root`, captured at the auto-prelude import from the directory
  `lib/prelude.nuc` resolved through (§3.4). Empty when no prelude is imported,
  which reads as "nothing is from-lib".
* `ProgDefn` grows `ir-start`/`ir-end`/`from-lib`; `program-defn-record` fills
  `ir-start` and `from-lib`, the tail of `emit-defn` fills `ir-end`.
* The `g-out`-is-not-`g-def-buf` guard (§5.1): record a span only when `g-out`
  is `g-def-stream-program` and that is `&g-def-buf`; otherwise store
  `ir-start == ir-end == 0`, read downstream as "no span".

*Gate:* byte-identical bootstrap (nothing reads the fields), plus a temporary
`--dump-spans` assertion that concatenating every span in record order
reproduces `g-def-buf` minus its non-`defn` text, and that `g-ct-lib-root` is
this checkout's `lib` when building from the repo root (§3.5 edge 2).

### L2 — `host-exports?`
**Status: done 2026-09-11.** `LLVMLoadLibraryPermanently` /
`LLVMSearchForAddressOfSymbol` in `src/llvm.nuch`; `host-exports?` and its
index-parallel memo in `src/nucleusc.nuc`, beside the macro/CT declare latches.
Nothing calls it. The `dlsym` spelling this entry originally carried is wrong and
§5.2 is the correction: `make windows-boot` emitted both IRs clean with **0**
occurrences of `dlsym`, carrying the two LLVM declares instead. Gate met —
`make bootstrap` byte-identical, `make test` 996/0/0, and a throwaway probe
answered **1** for `node-at`, `alloc-node`, `intern-symbol`, `desugar-form` and
`printf`, **0** for `__gs_no_such_symbol_42`. §5.2's precondition is real: with
the `LLVMLoadLibraryPermanently(null)` call removed, the same probe answered
**0 for all five** positives.

*Gate:* a unit test asserting `node-at` yes, a gensym'd name no; byte-identical
bootstrap.

### L3 — the mirror module — **done 2026-09-11**
`ct-mirror-flush`: closure walk (§5.4), span copy with the `internal` rewrite
(§5.6), declares, assembly, `g-ct-mirror-defined`, the `g-interactive` gate, the
mirror counter. Not called from anywhere; L4 wires it.

The `declare` emitter **was** unifiable emission-neutrally: `progdefn-declare-to`
now serves all three sites (`src/repl.nuc:1492`, `macro-jit-ensure-decl`, the
mirror). `emit-qq-helpers` grew a target and a visibility prefix so a mirror gets
`private`, host-sized helpers; the two existing call sites pass `g-target ""` and
reproduce their old bytes. A refusal records a reason/name pair
(`g-ct-mirror-refuse`) rather than raising — L5 turns that pair into the located
diagnostic, and the three reasons are "is defined where no span was recorded",
"reads a program global" (L6), and "is neither defined nor declared in this unit".

*Gate, met:* `PASS: stage1.ll == stage2.ll`; the closure walk probed end to end —
a macro's helper chain three deep including a `defn-`, mirrored and **called**
through the JIT for the right answers, with the walk stopping at `alloc-node` as
a `declare`; a second, overlapping flush declaring `@ctm-mid` instead of
redefining it; and the program's `.ll` keeping `define internal
i32 @ctm_p1__ctm-priv()` where the mirror copy reads `define weak_odr`.
**Counter 0 as a measurement, not an inference** — the gate harness emitted an
unconditional marker, and a full `make bootstrap` plus `make test` produced none.

Two things the phase taught, neither of them in this document beforehand:

* **§5.6's `weak_odr` collision worry is already answered by N4.** A private
  defn's IR name is namespace-mangled (`@ctm_p1__ctm-priv`), so two same-named
  privates do not meet in the mirror's symbol table in the first place.
* **`tests/suite-audits.nuc`'s `cstr-residue` is a working tripwire for exactly
  this kind of phase.** The gate harness's one `(as CStr (LLVMGetErrorMessage
  err))` took `src/nucleusc.nuc` from 15 C-string sites to 16 and failed the
  suite — which is how the leftover instrumentation was caught rather than
  shipped. A throwaway that adds an FFI seam will always be caught here; one that
  does not, will not.

### L4 — the roots, the feature, and `--warn-ct-shadow`
**Status: done 2026-09-11 — this is the phase that turns the feature on.**
`macro-jit-ensure-decl` takes the call's line and splits on §3.1; roots land on
`MacroDef.ct-roots` (and on a new `CtBlock` record for a `compile-time` block);
`expand-macro-call` and `jit-call-ct-main-sym` flush before their lookups;
`--warn-ct-shadow` / `--no-warn-ct-shadow` in `main`'s argv loop.

Gate met. `make bootstrap` byte-identical with the mirror counter **measured**
at 0 — a throwaway unconditional marker (since removed) over `make bootstrap`
plus a 435-file sweep of `examples/`, `lib/`, `tests/fixtures/` and
`src/nucleusc.nuc` produced 273 markers, every one `0`, and **zero**
`--warn-ct-shadow` fires. `make test` 1005/0/0 (996 + 9). All four of §1's
probes flipped: mode 1 exits 7, §1.5's `depth`/`mk-int` exits 4 (the deferral's
"cannot recurse" retired), mode 3 exits 7 with the warning and is silent under
`--no-warn-ct-shadow`, and the `desugar-form` probe runs instead of dumping core
(exit 139 → 7). §3.1 condition 2 was probed separately with
`lib/mathlib.nuc`'s `square` — under the root, not exported, mirrored. L7's
`(compile-time (println (twice 21)))` probe prints 42 with nothing added beyond
the second flush site, so L7 is closed here too.

Two corrections to this document, both in §5.3/§5.5:

* **"alongside the existing per-module `g-macro-decls` latch" is a trap.** That
  latch is reset per body and **never restored**, which is survivable for a dedup
  set and fatal for a result the caller reads. A `macrolet` compiled inside a
  `defmacro` body opens a second body midway through the first, so the reset
  points the global at the inner binding's vector and the outer macro's roots
  land nowhere. Measured, not inferred: with the restore removed,
  `(defmacro outer () (macrolet ((inner (k) `(mk (_+ (base) ~k)))) (inner 2)))`
  fails `Symbols not found: [ mk, base ]`. The roots are saved and restored
  beside `g-out`/`g-decl-out`; `s20-macro-roots-survive-nested-macrolet` pins it.
  `macrolet` is not mentioned anywhere in §5.3, and it is the shape that
  distinguishes a correct root set from a lost one.
* **§5.5's stated reason for flushing at expansion rather than at `defmacro` time
  is wrong.** A root is recorded by `macro-jit-ensure-decl`, which needs a
  `ProgDefn`; `program-defn-record` runs at `emit-defn`, so "a callee defined
  between the `defmacro` and its first call site" has no `ProgDefn` when the body
  compiles, gets no `declare`, and never becomes a root — it is mode 2 either
  way (verified: the probe still reports `use of undefined value '@helper'`).
  The site is still right, for two reasons not given: a macro defined and never
  called emits no module, and a `macrolet` compiled mid-`emit-defn` would
  otherwise meet the enclosing function's span with `ir-end` still 0.

Smaller: `ct-sym` carries no `@` (§5.3 spells the key `@__compile_time_main_N`),
and the line numbers in §5.5 are stale — `expand-macro-call` is at `:11194` with
its lookup at `:11227`, `jit-call-ct-main-sym` at `:14843`.

`macro-jit-ensure-decl` splits (§5.3); `expand-macro-call` and
`jit-call-ct-main-sym` flush before their lookups.

With it, `--warn-ct-shadow` / `--no-warn-ct-shadow`, **defaulting on**. It warns
on exactly the §1.3 shape now doing the right thing: a macro or CT body calls a
program `defn` that resolves to the program's copy (§3.1 branch 2) *and*
`host-exports?` is true of its name.

```
probe.nuc:2: warning: macro 'probe' calls 'in-jit-module', which is also a symbol
  exported by the compiler; the program's definition is the one that runs
  note: before Stage 20 L4 the compiler's ran instead — rename to silence this
```

On by default because §6's measurement says it fires **zero times** across
`lib/`, `src/` and `examples/`: the only compile-time call in the tree is
`node-at`, which takes the host branch and is not a shadow. A warning that
nothing in the tree raises costs nothing to leave on, and the thing it names is
a program that would have segfaulted the compiler a phase earlier — worth
saying out loud even though it now works. Revisit the default if adoption finds
a legitimate shadow; the flag is there so the answer is a flag and not a patch.

*Gate:* §1.1's and §1.5's probes compile in batch and produce the REPL's
answers; mode-3's `in-jit-module` probe exits **7**, with the warning, and is
silent under `--no-warn-ct-shadow`; the `desugar-form` probe compiles and runs
instead of dumping core; bootstrap byte-identical, counter 0, **and no new
warning text anywhere in `make test` or the examples**.

### L5 — mode 2 becomes a diagnostic
**Status: done 2026-09-11.** `ct-forward-ref-check` at `macro-jit-ensure-decl`'s
no-`ProgDefn` return, `ct-mirror-report-refusal` at the two flush sites, and
`g-ct-module-defns` — the discriminator §5.8 is missing (below). Gate met:
`make bootstrap` byte-identical with the mirror counter **measured** 0 (the
throwaway marker again, since removed and grepped for); `make test` 1014/0/0
(1005 + 9); a 478-file sweep of `examples/`, `lib/`, `tests/` and `src/`
produced 282 markers, all 0, **zero** `--warn-ct-shadow` fires, **zero**
occurrences of `use of undefined value` or `IR parse error`, and **zero** of
L5's own messages.

**§5.8's stated test admits a case that must not error.** "The name resolves in
`g-globals` to a `TY-FN` `Sym` with no `ProgDefn`" is true of a `defn` defined
inside the `(compile-time …)` block being compiled: `program-defn-record`
declines under `in-jit-module` (that is its documented job — such a defn already
lives in the CT module), while `emit-compile-time`'s signature prescan registers
it in `g-globals` as a global `TY-FN` `Sym` with `@fname`. Measured by building
the check without the fourth condition: `(compile-time (defn ct-outer …) (defn
ct-inner …) (printf … (ct-outer 21)))` — which compiles and prints 42 today —
fails `compile-time block calls 'ct-inner', which is defined later in this
unit`. So the check is **four** conditions, not three: not a local, `TY-FN`, not
in `g-decl-stream`, **and not in `g-ct-module-defns`**, a per-body set fed from
the CT block's prescan (which is what lets one CT defn call another defined
below it) and from `emit-defn` under `in-jit-module` (which carries the mangled
ir-name when the two spellings differ). `s20-ct-block-defines-own-defn` pins it.
The other three reasons each got a probe of their own — a C-header extern, a
top-level `declare`, a call through a function-pointer local — and are
`s20-macro-calls-c-header-fn` / `-declared-fn` / `-through-fn-ptr`.

**A JIT module needs the `declare` for a function it NAMES, not only one it
calls.** `macro-jit-ensure-decl` had exactly one call site,
`emit-call-with-args`, so a macro body that took a program defn's *address* —
`(let (f:(fn i32)(i32) twice) (f 21))` — emitted `store ptr @twice` into a
module that declared nothing and leaked `use of undefined value '@twice'` for a
callee defined **above** the macro. That is mode 2's diagnostic without mode 2's
cause, and the gate's "no raw LLVM text on any macro path" does not hold without
fixing it. One added call at `emit-symbol-ref-bound`'s function-materialization
branch — the chokepoint AVR-6's addrspace check already names as the only path a
function becomes a value — supplies the declare and the mirror root together;
emission-neutral outside a JIT module, and `s20-macro-names-defn-as-value` pins
it.

Two smaller notes. L3's refusal reason `"reads a program global"` records the
**global's** name, not the reading function's, so it cannot ride the shared
"`<who>` needs '`<name>`', which `<reason>`" template and gets its own sentence.
And a **bounded generic** called from a macro body now takes this message too:
its stamp is emitted when the mono worklist drains, at the end of the unit, so
`@ident.i32` genuinely has no `ProgDefn` yet. The message is accurate and the
note's "move it above the macro" is not advice that helps there; before L5 the
same shape leaked `use of undefined value '@ident.i32'`, so it is an improvement
either way. Calling a generic from a macro body stays unsupported.

*Gate:* `tests/suite-refusals.nuc` entry; no raw LLVM text on any macro path.

### L6 — globals
**Status: done 2026-09-12.** `ProgGlobal` + its registry trio (`src/scope.nuc`),
spans opened in `emit-defvar` above the array backing global, `InitJob.ir-name`,
`ct-mirror-classify`'s global split, `ct-mirror-put-global-span` /
`ct-mirror-global-declare-to`, `ct-scan-body-globals`, `ct-mirror-build-init`
and the `@__ct_init_N` call site in `ct-mirror-emit-module`
(`src/nucleusc.nuc`). Gate met: `make bootstrap` byte-identical with the mirror
counter **measured** 0 (a throwaway marker, since removed and grepped for) — a
478-file sweep of `examples/`, `lib/`, `tests/` and `src/` produced 282 markers,
every one `0 0`, with **zero** `--warn-ct-shadow` fires and **zero** occurrences
of `use of undefined value` or `IR parse error`. `make test` 1022/0/0 (1014, less
the retired refusal, plus 9). `make abi-test`, `make layout-test`, `make
avr-test` green.

**Q3, measured.** `weak_odr`, and the failure under `internal` is not "two
copies, silently diverging" — it is a hard one. Two macros, each with its own
private helper reading one `defvar- g-s20p`: the second flush is a real second
module that *declares* the global the first defined, and `internal` keeps that
definition out of the dylib's symbol table, so the second module cannot bind it:
`JIT session error: Symbols not found: [ q3_p1__g-s20p ]` — and then `nucleusc`
**dumped core** rather than reporting, which is worth knowing as a property of a
failed materialisation (§1.1's clean `JIT lookup failed` is what an unresolved
symbol looks like when the module was never added; a poisoned one is not).
`weak_odr` gives one copy: the probe's two expansions read 1 and 2.
`s20-macro-global-two-flushes-one-copy` is that probe. The rewrite is at
`ct-mirror-put-global-span`, on the global's own line only — an `@g.data`
backing global keeps its `private`, since nothing outside the mirror names it.

**Three things this document did not have.**

* **A macro module needs the `declare` for a global it NAMES, and there is no
  chokepoint that produces it.** §5.7 says only that `emit-defvar` gets a span;
  it never says how a *reference* becomes a root. §5.3's mechanism has no global
  analogue, so a macro body reading a global directly (no helper) had no root at
  all and leaked `use of undefined value '@g-s20k'` — L5's own "no raw LLVM text
  on any macro path" gate, failing in a shape L5 could not have reached. This is
  L5's `emit-symbol-ref-bound` lesson one level further out: a call has one site,
  a global reference has four (a read, a `set!`, an `addr-of`, a member GEP), and
  instrumenting them one at a time is how you get a fifth. The IR the module
  already contains is the ground truth §5.4 trusts for the closure walk, so
  `ct-scan-body-globals` asks *that* — once per macro/CT body, over its finished
  text, with the declares written to a side buffer so `ct-decl` is never grown
  under a live `StrView`.
* **§5.7's snapshot-and-restore is wrong** — see the correction inline there.
* **A flush NESTS.** `ct-mirror-build-init` emits the initializer with
  `emit-node`, which expands any macro in it, and that expansion flushes a mirror
  of its own. L3 wrote the per-flush vectors as globals reset at entry — the
  `g-macro-decls` idiom that L4 already found fatal once — and with a macro in a
  `defvar`'s initializer the outer walk resumes on the inner's state:
  `Symbols not found: [ s20-readn ]`, measured. `ct-mirror-flush` is now a
  save/restore wrapper around `ct-mirror-flush-1`, and `g-ct-init-id` is claimed
  at mint time so two live flushes cannot both be `@__ct_init_0`.
  `s20-macro-global-init-expands-macro` pins it.

Smaller: the copied-global set and the initializer IR grow each other (a job's
body can read a global whose own job is still queued), so the walk iterates to a
fixpoint rather than running spans-then-init once —
`s20-macro-global-init-chain`. And a global span is the one span whose own
definitions must be skipped by the scan, because G-2 shape 4 puts two `@name = `
lines in it.

*Gate:* a macro body calling a helper that reads a program global with a runtime
initializer sees the initialized value; the program's own `@__nucleus_init`
still contains that initializer — the second half is the whole point and needs
its own assertion, not an eyeball; and two flushes that share one global see one
value, not two.

### L7 — `compile-time` parity
**Status: done 2026-09-11, inside L4; confirmed and pinned at L5.** The CT-block
path needed nothing beyond the second flush site and its own `CtBlock` record;
the probe prints 42 and `s20-ct-block-calls-own-defn` pins it. L5 probed the two
shapes past the simple one and both were already right with **no further code**:
a CT block calling a *recursive* helper (`fib(10)` = 55, the closure walk meeting
a span it has already chosen — `s20-ct-block-calls-recursive-helper`), and a CT
block whose callee is defined **below** it, which now takes L5's message naming
the block rather than LLVM's (`s20-ct-block-forward-reference`). The only CT-only
code L5 added is the prescan half of `g-ct-module-defns`, which exists because a
CT block can define `defn`s and a macro body cannot — the one place the two paths
are not symmetric.
*Gate:* §1's `(compile-time (println (twice 21)))` probe prints 42.

### L8 — refusals and documentation
**Status: done 2026-09-12 — the stage is closed.** The cross-target refusal in
`ct-mirror-flush` and its branch in `ct-mirror-report-refusal`; `--warn-ct-shadow`
extended to globals (`warn-ct-shadow-global`, fired from `ct-body-global-note`,
which now takes the body's line); `docs/macros.md` gains §3.5's five edges and the
cross-target one; `docs/compiler.md`'s `--target=` and `--warn-ct-shadow` rows say
what changed. `context/macros-jit.md` bullet 11 was already §3.1 (L4 rewrote it,
L5/L6 extended it) and needed the two L8 sentences, not a rewrite; the
[deferred/overview.md](../deferred/overview.md) entry was already reduced to the
`-rdynamic` rule before this phase. Gate met: `make bootstrap` byte-identical with
the mirror counter **measured** 0 (a throwaway marker, since removed and grepped
for — 0 over `make bootstrap`, 0 over a 478-file sweep of `examples/`, `lib/`,
`tests/` and `src/`, and 5 under `make test`, every one of them in a unit that
exists to exercise the mirror, which is what makes the zeroes a measurement);
`make test` 1025/0/0 (1022 + 3); `make avr-test`, `make abi-test`,
`make layout-test`, `make check-headers` green; and both Windows boot IRs
cross-emit clean (into a scratch directory — `make windows-boot` overwrites the
committed artifacts) with **0** refusals.

**§5.9's test is wrong as written.** "`g-target != g-host-target`" compares the
two `Target` *objects*, and `target-init` builds a second one for **any**
`--target=`, the host's own triple included. So `--target=x86_64-pc-linux-gnu` on
an x86_64 host — the same ABI, the same datalayout, the same everything — would be
refused for nothing. The test that is correct is the one `src/cheader.nuc` already
uses for the same question: `g-target-triple` against
`((as ref:Target g-host-target) 'triple)`, two interned `Symbol`s. Measured: under
the triple test that invocation exits 0 and an `avr`/`riscv64` one takes the
refusal.

**The refusal makes §6's counter externally observable, which §8 wanted and no
phase could give it.** A flush is refused iff a flush is *required*, so "this unit
needs no mirror" is now a compile that succeeds under a cross target. The
compiler's own source cross-emits clean for `riscv64-unknown-linux-gnu` and both
Windows triples, and every AVR and RISC-V example still compiles — which is §6's
"the bootstrap flushes nothing" as an exit code rather than as instrumentation.
§8's `tests/suite-audits.nuc` entry is still not shipped (a whole-tree cross sweep
costs ~30 s for `src/nucleusc.nuc` alone), but `s20-macro-cross-target-host-resolved`
pins the shape and the throwaway marker remains how the counter itself is read.

**The global-shadow extension shipped, on its measurement.** §3.5's arithmetic is
the whole licence for `--warn-ct-shadow` to default on, so the widening was gated
on the same zero-fire property: a 478-file sweep of `examples/`, `lib/`, `tests/`
and `src/` produced **0** fires of either spelling, and `make test` is clean of
both. The hazard is not quite symmetric with the call, and the note says so —
before L6 a mirrored global was *refused*, not silently bound — but the collision
and the rule are the same, and the probe is equally discriminating: the compiler's
own `g-block-term` is never 7 mid-compilation
(`s20-macro-shadows-compiler-global`).

Smaller, from the consistency pass. `docs/macros.md` said "Three consequences" over
four bullets (L6 added the fourth). `(invoke v 0:usize)` does not parse — the
`name:type` sugar needs a name, so an index literal is `(as usize 0)`. `&rest` in
test code is read as the variadic marker, not as `addr-of rest`. And
[deferred/overview.md](../deferred/overview.md)'s **"Name pasting"** entry is stale:
its stated blocker was "no `intern` over formatted parts reachable from a macro
body", and after L4 a macro body may call its own helper, so
`(str "g-" …)` → `intern-node` → a spliced symbol works — measured, exit 42.

*Gate:* `make test`; the deferred entry is gone rather than edited.

---

## 8. Tests

In `tests/suite-s16.nuc` beside the other `s20-` tests:

* `s20-macro-calls-own-defn` — §1.1's program, exit 7.
* `s20-macro-calls-recursive-helper` — §1.5's `depth`/`mk-int`, exit 4. The
  deferral's headline claim ("cannot recurse"), retired.
* `s20-macro-helper-shares-arena` — two macros calling one helper that allocates
  a node; both expansions survive to runtime. Guards §3.2's one-arena invariant,
  which design C would have broken silently.
* `s20-macro-shadows-compiler-symbol` — the `in-jit-module` probe, exit 7. This
  is the mode-3 regression test and it must name the hazard in a comment: it
  passes today with exit 99.
* `s20-macro-calls-private-defn` — a `defn-` helper, exercising §5.6.
* `s20-ct-block-calls-own-defn` — L7's probe.

L6 adds eight beside them: `s20-macro-helper-reads-program-global` (the unit L5
refused), `-reads-program-global-directly` (no helper — the shape §5.7 has no
mechanism for), `s20-macro-global-runtime-init` (the initialized value *and* the
program's own `@__nucleus_init`, asserted against the emitted `.ll`),
`-init-chain` (the fixpoint), `-init-expands-macro` (a nested flush),
`-two-flushes-one-copy` (Q3), `-array-backing` (two definitions in one span), and
`s20-macro-lib-global-is-the-hosts` (§3.2 on the global rather than the
allocator), plus `s20-ct-block-reads-program-global` for L7 parity.

L8 adds `s20-macro-shadows-compiler-global` beside the two mode-3 units — the
same collision on a `defvar`, and equally discriminating.

In `tests/suite-refusals.nuc`:

* `s20-macro-forward-reference` — L5's message.
* `s20-macro-cross-target` — L8's refusal. The target triple is pinned; the
  host's is read back out of a native `--emit-llvm` (`host-triple`, in
  `tests/nuctests.nuc`) so the unit says what it means on any machine.
* `s20-macro-cross-target-host-resolved` — the other half: a body calling only
  the compile-time runtime still cross-compiles, which is what `make avr-test`
  depends on.

The bootstrap counter assertion (§6) belongs in `tests/suite-audits.nuc`, which
is where Stage 18 put the whole-tree invariants. **Not shipped through L8**: the
counter has no external spelling, and the cross-target compile that now stands in
for it costs ~30 s for `src/nucleusc.nuc` alone. Every phase measured it with a
throwaway unconditional marker instead.

---

## 9. What does not change

* **Macro recursion.** A macro that names itself in head position is still a
  macro *call*, and expansion still has no depth limit — L8 checked what that
  costs, and a runaway expansion **segfaults** the compiler rather than hanging
  or diagnosing. Pre-existing (`bin/nucleusc`, which predates L1, does the same),
  and not this stage's to fix. A macro body may now recurse through a helper,
  which is the useful half.
* **`lib/` may not reach into the compiler.** §1.3 shows the surface is 1,658
  plausible names wide; the rule against `macroexpand-form`, `desugar-form` and
  `find-macro` appearing in `lib/` is unchanged, and after §3.1 a `lib/` file
  that spells one of them gets the compiler's — which is exactly why the rule
  stays written down.
* **No macro-authored diagnostics.** `die-at`/`report-at` remain out of a macro
  body's scope; `macro-error` (Stage 20 M3) remains the one channel. §3.1 does
  not change this — the blocker is *scope*, not linkage, and `src/reader.nuc` is
  imported by nothing a program reaches. Re-probed at L8: `unknown: die-at`.
* **The REPL.** Same behaviour, same code path, one added `g-interactive` gate.
* **The string table.** Every macro module still interns its quasiquote
  spellings into the one shared `g-strs`; the mirror inherits the dead-constant
  cost stage888 measured at 92 per hello-world. Not this stage's to fix, and the
  per-module string table it asks for would simplify §5.5.

---

## 10. Deferred

* **Forward references from a macro body** (§5.8) — L5 makes it a message. Real
  support means deferring macro-module assembly to first expansion.
* **Cross-compiled macro bodies** (§5.9) — L8 makes it a located refusal naming
  both triples. Real support needs the program re-emitted at host ABI for CT,
  which is a second lowering of every mirrored function. The clean version of
  this is a CT-specific emission pass, not a span copy.
* **Per-function lazy materialisation.** ORC materialises a whole module on
  lookup, so a flush compiles its whole closure even if one leaf is never
  reached. A module-per-function would make it lazy at the cost of one parse per
  function. Measure before building.
* **A stable compile-time API.** §3.1 makes the program's own code callable, but
  what the *compiler* offers a macro body is still whatever `-rdynamic` happens
  to export. Naming a supported subset — and hiding the rest behind a visibility
  pass — is a separate, larger item.

---

## 11. Open questions

### Q1 — what should `from-lib` actually test? **Resolved: option (a).**

**Decided 2026-09-11: (a), anchored on the prelude's resolved directory
(§3.4), with its five sharp edges documented (§3.5) and `--warn-ct-shadow`
re-aimed to cover the one that keeps a trace of mode 3.** The reasoning that led
there is kept below, because the argument against (b) is the part worth
re-reading if this is ever revisited.

§3.1's condition 1 is written as "its defining file is under the compiler's own
`lib/` root". That sentence hides a choice between three different tests, and
they disagree on real programs.

First, the fact that shapes all three: **there is no single compiler lib root.**
`try-import-path` (`src/nucleusc.nuc:17697`) searches five places in order — the
current source file's directory, `lib/` **relative to cwd**, each `-I`, then
`$NUCLEUS_LIB`, then the compiled-in `/usr/local/share/nucleus/lib/`. The
development build finds its own library at step 2; an installed compiler finds
it at step 5. "The compiler's lib root" is a per-invocation search result, not a
property the binary carries.

**(a) Path prefix** against whichever root this invocation resolved. One string
compare at `program-defn-record`. Its failure is narrower than "vendoring": step
2 means an ordinary user project's `lib/util.nuc` is already not under an
installed compiler's root and mirrors correctly. What breaks it is a program
whose **cwd-relative `lib/` holds a file named like one of the compiler's own**
while the compiler's own root is also cwd-relative — which is, in practice,
working inside a checkout of this repo. There the two files are usually the same
file, so the wrong answer is usually right by accident.

**(b) "This defn came from a module that is also in the compiler's own import
closure."** The exact statement of what §3.2 needs — the same *module*, not the
same directory. Three costs, in increasing order of how much they should weigh:

* **Path cannot be the identity.** `resolve-import` interns the resolved path and
  everything downstream compares by identity, but the build resolves
  `lib/node.nuc` and an installed compiler resolves
  `/usr/local/share/nucleus/lib/node.nuc`. A manifest of build-time paths does
  not survive `make install`. Identity has to be **import name plus a content
  hash** — which is in fact *better* than module identity, since a byte-identical
  vendored copy legitimately binds to the host and a modified one legitimately
  mirrors. `lib/hash.nuc`'s `hash` over a `StrView` is right there, though it is
  a hash-table hash and this would be the first correctness-relevant use of one.
* **The manifest is chicken-and-egg.** The closure is a fact of the compilation
  that produces the binary, so it cannot be written by hand and kept true. Either
  a new `--emit-deps` pass feeds a generated `src/` table and `$(BIN)` becomes a
  two-pass build, or the compiler emits its own manifest while compiling itself.
  Either way the Makefile grows a step and `lib/`'s composition becomes a build
  input — against `COMPILER_DEPS`' stated preference for over-approximating
  (`$(wildcard src/*.nuc) $(wildcard lib/*.nuc)`) precisely because the exact
  closure "was wrong three times".
* **The manifest freezes into `boot/nucleusc.ll`, and that is the decisive one.**
  The bootstrap is not a committed binary — it is 13.5 MB of committed LLVM IR
  that clang turns into `bin/nucleusc`. A baked manifest is frozen at the last
  boot refresh, so the moment any `lib/` file changes, the boot compiler's hashes
  stop matching the tree and it classifies those modules as *not its own* while
  building `$(BIN)`. In today's tree that flips exactly one call — `node-at` in
  `with-handler` — from host-resolved to mirrored, keyed on nothing but whether
  someone has touched `lib/node.nuc` since the last refresh. **(b) makes the
  mirror's behaviour a function of boot staleness**, and promotes every ordinary
  library edit into a potential boot-refresh trigger —
  [context/build.md](../../context/build.md)'s fourth root cause, which today
  binds only on language changes.

**(c) `host-exports?` alone — drop condition 1.** The rule collapses to "the
host wins wherever it can", which is what the compiler does today. Smallest
change by a wide margin, bootstrap free, arena shared under any vendoring. It
also **leaves §1.3 open**: `in-jit-module` still binds to the compiler's, so the
silent bind and the segfault survive, and this document's claim to be a
soundness fix goes with them. Worth naming precisely because everything except
mode 3 works under (c).

The trade, restated on what was measured rather than assumed: **(a) is cheaper
and fails more narrowly than it first looked; (b) is more expensive than "a
manifest" suggested and buys nothing in this tree** — the two classify every
module identically for every compilation that happens in this repo, and diverge
only where a program's cwd-relative `lib/` shadows a compiler module name —
**and (c) forfeits the bug that makes this a soundness item.** The structural
asymmetry is that (a) and (c) carry no baked state: (a) is evaluated fresh per
compile, (c) is a `dlsym` on the running binary, and both therefore always
describe the compiler that is actually running. (b) is the only one that can be
*stale*.

**The decision was (a) plus L4's `--warn-ct-shadow` re-aimed at the
shadowed-module case**, so the one narrow wrong answer is at least a loud one.
(b) stays available if a real program ever hits it — and if it is ever revisited,
the cost that decided against it was not the manifest but the *staleness*: a
frozen closure in `boot/nucleusc.ll` makes compile-time behaviour depend on how
long since the last boot refresh.

### Q2 — should mode 3 warn once it does the right thing? **Resolved: yes, on by default.**

`--warn-ct-shadow`, added in L4 and defaulting on. §6's measurement is the
reason it can default on: no macro body in `lib/`, `src/` or `examples/` takes
the branch, so nothing in the tree raises it. See L4.

### Q3 — `internal` or `weak_odr` for a mirrored global? **Resolved: `weak_odr`, by probe.**

Both directions argued plausibly — `internal` hides the program's globals from
the dylib's symbol table, `weak_odr` keeps two flushes on one copy — and a
plausible argument was not evidence. Measured 2026-09-12 (L6): under `internal`
the second flush fails to link at all (`Symbols not found`, then a core dump),
not "two copies, silently diverging" as this section guessed; under `weak_odr`
the two flushes share one copy and read 1 then 2. `weak_odr` it is, rewritten on
the global's own line only. See §7 L6.

The question also turns out to be narrower than it reads: the span already says
`weak_odr` for an imported file's global and carries no linkage word at all for
a public `defvar` in the entry file, so only a `defvar-` reaches the rewrite.
