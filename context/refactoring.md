## Rewriting `.nuc` / `.nuch` source with `defrewrite`

API and rule syntax: [docs/refactoring.md](../docs/refactoring.md). Design and
as-built notes: `design/stage26-refactoring/overview.md`.

**Scope: `.nuc` and `.nuch` files only.** The library reads Nucleus source.
Do not use it on Markdown, EDN or other text (docs, `design/`, `context/`,
manifests). Edit those with ordinary tools (Edit, Python, sed).

### When to reach for it

Use a `defrewrite` tool when one change must be made at many sites in `.nuc`
files and the sites differ only in their operands: a renamed function, a
changed argument order, a spelling migration (`(ptr T)` to `&T`). It keeps
comments and layout, and it reports sites it is unsure of. Edit by hand when
the change is under about a dozen sites, or each site needs judgement. Do not
use `sed`/Python on source: they cannot tell a call from a quoted symbol, a
type from an expression, or code from a string.

### A tool

```lisp
(import-use nucleus.syntax)
(import-use nucleus.refactor)

(defrewrite tidy
  (rule (car ~x) `(node-first ~x))
  (rule (old-api ~@args) :refuse "old-api has no replacement yet"))

(defn main (argc:i32 argv:ptr):i32
  (return (refactor-main argc argv (tidy))))
```

Run it (dry run by default, then `--apply`):

```
build/nucleusc --run scripts/stageN/tidy.nuc -- src/foo.nuc            # prints sites, writes nothing
build/nucleusc --run scripts/stageN/tidy.nuc -- --apply 'lib/**/*.nuc'
```

Arguments are files, directories (every `.nuc`/`.nuch` under them) or quoted
globs. Run it from the repo root. From another directory, pass `-I <repo>/lib`
and absolute paths, or a `lib/nucleus/` there shadows the library. Read the
dry-run summary (per-rule rewritten/refused counts) before applying, and
`git diff` after.

### Refusal discipline

**Refuse rather than guess.** A rule that cannot be sure a site is the one it
means says so with `:refuse "reason"`, which leaves the site as written and
lists it (`path:line:col: NAME: reason`) for a human. A refusal list is a
work item: fix those sites by hand, or sharpen the rule. A silent skip is
for sites that are certainly not the target.

- `--strict` makes the exit status 1 when any site was reported or any file
  did not read. Use it when a script must stop on unresolved sites.
- `:flag "reason"` rewrites and also lists the site, for a change that needs a
  second look.
- The pass refuses by itself where its output would be wrong: a template that
  would lose a comment, a hole spanning lines (without `:multiline` or
  `:reindent`), a hole with no source span.
- A file the reader rejects is reported and left alone. Fixtures that are
  malformed on purpose will appear there.

### Spelling guards and trees

Patterns match the **read tree**, so `'x`, `(quote x)` and `[a b]` /
`(vector-lit a b)` all match one pattern. Spelling is invisible to a pattern;
ask for it in a `:when` guard: `(spelled? x "&")`, `(prefix-form? x)`,
`(same-text? a b)`, `(has-comment? x)`. A template is printed in the house
spelling (`(ref ~x)` comes out `&x`); the author cannot choose it.

### `slot-kind`: position decides meaning

`(ptr T)` is a type in a binder and a call in an expression. A rule whose
meaning depends on position asks `(slot-kind self)` (`nucleus.slots`):
`SLOT-TYPE`, `SLOT-BINDER`, `SLOT-VALUE`, `SLOT-PLACE`, …

**A macro call is `SLOT-UNKNOWN` by design.** An operand of `when`, `if`,
`make`, `dotimes` or any other library macro, or of a function call, has no
slot: what a macro does with an operand is not written anywhere a reader can
see. Treat `SLOT-UNKNOWN` as "refuse and list", not "assume value". A quoted
form is `SLOT-QUOTED`; a quasiquote's operand is `SLOT-TEMPLATE` and the forms
in it are checked with `in-quasiquote?` first when templates need other
handling. A new built-in special form needs a row in `lib/nucleus/slots.nuc`
(see `context/conventions.md`).

### `--in-strings`

Tests and macros write programs as string literals. Without `--in-strings` the
tool leaves them alone. With it, each literal that reads as a program is
rewritten by the same rules, escapes re-applied. Pass it when a migration
changes syntax that tests spell inside strings. `(in-string? self)` restricts
a rule to them. Check the summary's "skipped" count.

### Renaming a local: `rename-local`

To rename one local variable or parameter in a `.nuc`/`.nuch` file, use
`scripts/stage26/rename-local.nuc` rather than Edit or a rule. It edits exactly
the occurrences the compiler resolved to that binder (docs/refactoring.md,
"Renaming a local"):

```
build/nucleusc --run scripts/stage26/rename-local.nuc -- --root src/nucleusc.nuc src/foo.nuc:120:14 count
```

Dry run first, then `--apply`. A file in `src/` needs `--root src/nucleusc.nuc`
(it does not compile alone); each run resolves the whole unit, about 10 s for
the compiler. A refusal names the blocking site. Rename there by hand, or pick
another name; do not work around it. After renaming in a file with a generated
`.nuch`, run `scripts/check-headers.sh --fix`. Globals, fields and macros are
not renamed by it.

### Renaming a definition: `rename-global`

For a top-level definition (function with its overloads, global, constant,
struct, union, type alias, macro) use `scripts/stage26/rename-global.nuc`
(docs/refactoring.md, "Renaming a definition"):

```
build/nucleusc --run scripts/stage26/rename-global.nuc -- --root src/nucleusc.nuc --root tests/nuctests.nuc src/scope.nuc:40:7 scope-find
```

Name every unit that may use it with `--root`; a unit left out is not
checked. Resolving the compiler costs about 10 s and 1 GB per root. Library
definitions the compiler names by spelling, and globals it shares with macro
bodies (`:host`), refuse; that is the design, not a bug to route around. Regenerate
headers afterwards as the tool says.

### Where a tool lives, and checking a port

A one-off tool goes in `scripts/stageN/*.nuc` for the current stage, with a
header comment saying what it migrates. A
Python script that a Nucleus port replaces is deleted once the port passes
replay; do not port a script without a reason.

`scripts/stage26/replay.sh` checks a port against the original: it exports a
revision twice, runs the two commands, and requires identical files and
identical refusal sites (`path:line`, wording ignored). Its header holds the
three worked invocations (list-api, ptr and sugar sweeps). To check a new
tool against an old one, copy one of them. Weaken a condition on purpose and
confirm replay fails; a condition no site exercises is untested.

Build the tool before a migration that changes the reader: see
[context/build.md](build.md#tools-and-the-bootstrap).
