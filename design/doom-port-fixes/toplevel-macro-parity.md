# Anything possible at the top level, possible in a top-level expansion

The ruling on nuc-iron-doom ISSUE-011 (2026-11-05): anything possible at the top
level must be possible in a macro expanded at the top level; look for other bugs
of the same shape, consider multiple passes, and see whether ISSUE-006's special
case can go. This note holds the examination and what was built.

**Final ruling (2026-11-06):** option D, with no spelling rule. Reconsidering
option A is deferred until a real issue or growing compiler complexity demands it
(deferred/overview.md). **Built:** §4 as amended by §6.

## 1. What is broken

Each case below compiled a form written directly, then the same form from
`(defmacro gen () `FORM) (gen)`, using a compiler at this branch. Of 43 cases the
direct form accepts, 22 compile through a macro, one of them wrongly, and 21 are
refused.

| Class | Refused through a macro | Message |
|---|---|---|
| Type named in a signature | struct as parameter, return, `!T`; `(Bx Foo)`; template; union; parametric union; `deftype`, including a fn type | `unknown type: Foo` |
| Type named in a global | `(defvar g:Foo …)` | `unknown type: Foo` |
| Any name used above the call | `defn`, generic `defn`, `defvar`, `defconst`, `defenum` member | `unknown: z` / `undefined: N` |
| Import | `import-use`, `import-prefixed` | `unknown type: Vector` |
| Protocol | a macro's `defprotocol` with a written `extend`; a macro's `extend` above the written `:where` use | `type 'Q' does not conform` |

**One case compiles and means something else.** `(defn f (v:&(Vector Foo)) …)`,
below a macro that defines `Foo`, is accepted as a generic over a type variable
`Foo`. ISSUE-011's `(Fallible CommandLine)` is this case. It is the worst of the
set, because the failure is far from the cause or doesn't happen at all.

These work through a macro: a by-value or pointer field (ISSUE-006), a macro
below which uses the type only in bodies, `defconst` as a later array length,
`defmacro` used later, `deferror`, `declare`, `extern`, `export`, a template
method, and an overload (`~'k`; the qualified refusal without it is the documented
hygiene rule).

The reverse gap is harmless: a written top-level `(do …)` is refused, and an
expansion's is spliced.

## 2. Why

`emit-toplevel-forms` runs every prescan, then dispatches forms in order. A
top-level macro expands in the dispatch loop, because it can't run earlier:

- Its `defmacro` is JIT-compiled in the loop, and callees in the same file must
  already be emitted (stage20-macros/macro-call-linking.md).
- It may read earlier definitions: `derive-edn` and the port's `derive-record`
  read `struct-fields`, so the structs above it must already have layouts.

`late-prescan` (design/stage22-edn/macro-definitions.md) registers an expansion's
definitions when it is spliced. That closed "a macro can't define a method", but
everything that ran before the expansion stays wrong in three ways:

1. A prescan dies on a name a macro would have defined. Signatures die, and
   layouts did until ISSUE-006 made them defer.
2. A body emitted above the call has already missed the name. It can't be
   retried: emission writes IR with no rollback.
3. An unresolved name in a template argument silently becomes a type variable.

There is a fourth, narrower gap: `late-prescan` runs no import prescan and no
`prescan-extends`, which is the import and protocol rows.

The whole-graph prescan adds a constraint. `prescan-imported-signatures` re-reads
each file, so its forms are not the forms emission later expands. A splice into
one list never reaches the other, and an importer's signature is prescanned before
the imported file's macros have run.

## 3. Options

**A. Expand everything first (Racket-style phases).** Compile macros and their
helpers in a compile-time sink ahead of the prescans (`import-ct` and the ct mirror
exist), expand every file, then prescan the result. The cleanest semantics, and no
name is ever pending. But macros that read `struct-fields` need layouts before the
prescans that produce them, so the phase split isn't clean. Helpers would be
compiled twice, every file gets a form cache, and macro-defining macros need
iteration anyway. Largest change.

**B. Whole-unit fixpoint.** Run all the passes repeatedly until no macro call
remains. This is the ruling's "multiple passes". Registration is not idempotent
(`generic-register-method` appends, which is why `g-prescan-sigs` exists), so every
form needs its own registered state, and all of `emit-toplevel-forms`,
`prescan-imported-*`, `do-import`, the REPL, `.nuch` and `--resolve` move with it.
It repeats work that a macro call's file order already settles: expansions advance
monotonically, so only the forms that failed need another look.

**C. Park what fails (the issue's suggestion).** A form whose prescan hits an
unknown name waits, and is retried after each expansion. Small, and it generalizes
ISSUE-006. Alone it fixes macro-then-use but not use-then-macro: a body above the
call has already been emitted. It also can't see the silent type variable.

**D. C, plus body deferral.** Chosen; see §4. It is B restricted to the forms that
need a second look. As recommended it also had a spelling rule, which the ruling
removed (§6).

## 4. Option D

Expansion stays where it is, in the loop at its file position, so a macro still
sees everything above it and `struct-fields` keeps working. Three changes surround
it.

**Type variables settle.** With no spelling rule, an undeclared name in a template
argument stays a type variable until something defines it as a type. Each template
with such a variable is recorded (`g-implicit-templates`). When an expansion defines
a type of that name, in the template's own file environment, the template leaves its
generic and goes back through the signature prescan, which reads it as concrete. Its
`defn` always waits for the last macro call, so a body that turns concrete is emitted
then. A name nothing defines stays a variable, as it is today, and a misspelling
there stays silent.

**Pending forms.** Where a prescan would die on an unknown name, and the file still
has a top-level macro call or an import to process, the form goes on a pending list
with its `NameEnv` instead. Pending forms are retried after each expansion and each
import, and whatever is left when the file's dispatch ends dies with the message it
would have had. A file with nothing still to come dies exactly as today.

- This covers `prescan-defn-signatures`, the layouts, `defvar` types and
  `prescan-extends`. `late-prescan` gains the imports and extends it lacks.
- Crossing files works because a pending form carries its own environment: the
  whole-graph walk's copy waits until the import's dispatch has expanded the file,
  and an importer's signature waits for that import's form.
- **ISSUE-006's probe goes.** `g-layout-probe` becomes this path. `g-layout-defer`
  stays for an array length that won't fold yet, which is a different question.

**Bodies wait for the macros.** In a file with a top-level macro call, a `defn`
above the last such call has its body queued until after that call, unless a macro
can reach it. Reachability is syntactic and transitive over the file's `defn` names,
rooted at `defmacro` bodies and at the arguments of top-level macro calls (so
`(compile-time (f))` keeps working). It over-approximates, which is safe: a reachable
body is emitted exactly when it is today.

Every program takes this path through `lib/nucleus/fmt.nuc`, so unlike the first two
it changes emission order for existing code. The bootstrap fixpoint and the suite
are the check.

### Limits this leaves

- A helper a macro calls can't have a signature that names a type only a *later*
  macro defines. That is a real staging error, and `macro-call-linking`'s message
  covers it.
- A body above the last macro call would see a macro defined below it, where today
  it fails. A redefinition of an operator-like macro between the two could change
  what such a body means. One symbol, one kind makes this rare, and it can be
  refused if it ever matters.
- A name nothing defines stays a type variable, so `(Vector Fooo)` is a silent
  generic.
- Naming a function in a top-level macro call's arguments reaches it, even if the
  macro only copies it. Such a function can't use what a later macro defines.
- A form waits for its own file's macro calls and imports only. A type from a macro
  in a file it doesn't import has to exist by the time the form is reached.
- A body that waits sees a `defcast` below it, which changes what it means.
- A macro that reaches a function only through a library macro's expansion, under a
  name not in `REACH-IMPLICIT`, gets `ct-forward-ref-check`'s located refusal.
- The REPL expands per entry and is unaffected.

## 5. Phases

| Phase | Work | State |
|---|---|---|
| MP-1 | Type-variable spelling rule | not built, by ruling; `implicit-templates-recheck` does the job |
| MP-2 | `late-prescan` gains imports and extends | built |
| MP-3 | Pending forms, across files; `g-layout-probe` is now `g-type-probe` for every prescan | built |
| MP-4 | Body deferral with macro reachability | built |
| MP-5 | The §1 matrix as `tests/suite-macro-parity.nuc`; docs/macros.md rewritten | built |

## 6. Rulings and what changed in building

1. Option D, not A's phase separation. A stays deferred.
2. No spelling rule. §4's "Type variables settle" replaces it.
3. MP-4's emission reorder is accepted, as part of D.

Building changed four details:

- **Reachability skips templates.** A name inside a quasiquote runs nowhere until
  expanded, and treating it as reached made two macros' `defn`s unable to see each
  other. Instead each expansion is walked as it's spliced, and a waiting form a macro
  has come to reach goes back ahead of it (`waiting-released`).
- **Reachability also follows implicit calls.** A macro can call a method without
  naming it, through an operator, `invoke`, `get`, `set`, `field`, `drop`, `clone`,
  `iter` or `next`. A defn of those names or starting with `_` counts as reached.
  It also follows a global's initializer, which a mirror copies.
- **Imports count as macro calls** for deferral, since an imported file's macro can
  define what a body above the import names.
- **Non-defn forms wait only if they must.** A `defvar`, `defstruct`, `defunion` or
  concrete `extend` waits only if it can't be finished yet, so a macro's
  `struct-fields` and `conforms?` still see what's above them. A concrete `extend` left
  a promise, so `conforms?` already answers for one that waits.

A probe also doesn't stamp a template it can't finish (`template-body-known?`).
An instance is memoized, so a placeholder field would have stayed in its layout.
