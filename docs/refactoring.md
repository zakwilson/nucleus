# Refactoring Nucleus source

`lib/nucleus/refactor.nuc` (`nucleus.refactor`) rewrites `.nuc` and `.nuch`
files by replacing byte spans of the source. A tool reads a file in the
reader's [syntax mode](reading.md#syntax-mode), finds the forms to change by
their `Node`, and records an edit for each one. Applying the edits copies
every untouched byte as it is, so whitespace, comments and spelling outside
the edited spans survive unchanged.

Most tools need no edit code of their own: [`defrewrite`](#rewrite-rules)
states the changes as patterns and templates, and
[`refactor-main`](#a-rewrite-tool) runs them over files. The edit layer
underneath is for the rest. The design is
[design/stage26-refactoring/overview.md](../design/stage26-refactoring/overview.md).

```lisp
(import-use nucleus.read)
(import-use nucleus.syntax)
(import-use nucleus.refactor)
```

## Rewrite rules

```lisp
(import-use nucleus.syntax)
(import-use nucleus.refactor)

(defrewrite tidy
  (rule (car ~x) `(node-first ~x))
  (rule (swap ~a ~b) `(swap ~b ~a) :when (not (same-text? a b)))
  (rule (old-api ~@args) :refuse "old-api has no replacement yet"))

(defn main (argc:i32 argv:ptr):i32
  (return (refactor-main argc argv (tidy))))
```

`(defrewrite NAME RULE…)` defines a function `(NAME)` that returns the rule
set, a `&Rules`. A tool is an ordinary program: run it with
[`nucleusc --run`](#a-rewrite-tool), or build it with `-o`. At the REPL, a
macro that expands to a top-level `defn` is not supported yet.

A rule is one of

| Rule | Effect |
| --- | --- |
| ``(rule PATTERN `TEMPLATE OPTION…)`` | Replace the form with the template's text. |
| `(rule PATTERN :refuse "REASON" OPTION…)` | Leave the form as written and report `REASON`. |
| `(rule PATTERN :emit EXPR OPTION…)` | Replace the form with what `EXPR` writes to `out` (below). |

**Patterns** match the tree as read, so `'x`, `(quote x)` and the spellings
of one form all match the same pattern; `[a b]` is `(vector-lit a b)`. `~x`
matches any one form and binds it; `~@xs`, last in its list, binds the rest of
the list, possibly nothing. Any other symbol matches only the same symbol.
`~self` and `~out` are reserved.

**Templates** are quasiquotes whose only unquotes are the pattern's holes:
`~x` for a `~x` hole, `~@xs` for a `~@xs` one. Anything else, such as
`~(f x)`, is refused when the rule is expanded, with the rule's line; to
compute text, use `:emit`. A hole is replaced by the form's current text:
the source as written, with the rewrites already made inside it. The rest of
the template is printed in the house spelling
([`node-write-sugared`](#printing-replacement-text)), one space between
elements. A `~@xs` keeps the source between its forms, comments included.

**Options**

| Option | Meaning |
| --- | --- |
| `:when GUARD` | Apply only where `GUARD` is true. |
| `:multiline` | A hole whose text spans lines is spliced as it is. |
| `:reindent` | A hole whose text spans lines is spliced with its continuation lines moved as far as its first line moved. Lines that start inside a string literal stay. |
| `:flag "REASON"` | Rewrite, and also report `REASON`, for a change a person should check. Not on `:refuse`. |

Without `:multiline` or `:reindent`, a hole whose text spans lines refuses
the rewrite: the template would leave its lines indented for where they were.

**Guards** are ordinary expressions. Each hole is bound to its `&Syn`
([reading.md](reading.md#syntax-mode)), a `~@` hole to a `&(Vector &Syn)`,
and the matched form to `self`:

| Helper | True when, or returns |
| --- | --- |
| `(src-text s)` | Returns `s` as written, a `StrView`. |
| `(same-text? a b)` | `a` and `b` are written identically. |
| `(prefix-form? s)` | `s` is written with a reader-macro prefix (`&x`, `'x`), not the long form. |
| `(spelled? s "&")` | `s` is written with that prefix. |
| `(has-comment? s)` / `(has-discard? s)` | A comment / a `#_` form lies inside `s`. |
| `(slot-kind s)` | Returns what `s` is to the form around it, a `SlotKind` ([below](#operand-slots)). |
| `(operand-of? s 'm 1)` | `s` is element 1 of a list headed by `m`; for a macro's operands, which have no slot. |
| `(in-quote? s)` | `s` is data under a `quote`. |
| `(in-quasiquote? s)` | `s` is inside a quasiquote template. |
| `(in-unquote? s)` | `s` is code again, under an unquote of a template. |
| `(in-string? s)` | `s` is in a program inside a string literal ([below](#programs-inside-string-literals)). |
| `(src-slice start end)` | Returns bytes `[start, end)` of the text being read, clamped to it: what lies around a `Syn`. |

**Refuse rather than guess.** A rule that cannot tell whether a site is the
one it means should refuse that site, so a person sees it, instead of
rewriting it or skipping it unseen. A guard that is false skips the rule
without a report; `:refuse` reports.

**Order.** One pass visits each form after the forms inside it, and the
first rule (in order) that matches and whose guard holds applies. Nested
matches compose: with `(car ~x)` above, `(car (car l))` becomes
`(node-first (node-first l))`. A rule that refuses leaves the form exactly as
written, rewrites inside it included.

**Refusals the pass makes itself**, reported like a rule's:

- a hole on a form with no source span of its own, such as the name in the
  colon fuse `x:(T)` (`~n has no source span of its own`);
- a hole spanning lines without `:multiline` or `:reindent`;
- a rewrite whose output would lose a comment or a `#_` form that was inside
  the matched form.

`(rewrite-source (tidy) src)` runs the rules over a string and returns a
`RewriteResult`: `(ok Rewrite)` with `text` (a `String`; `Rewrite` is
`Drop`), `reports` (each `RwReport` has `line`, `col`, `flagged` and
`reason`, in source order) and `rewrites`; or `(err ReadError)` when `src`
does not read. `(rewrite-source-in-strings (tidy) src)` also rewrites the
programs inside string literals, and fills `strings`, `fragments` and
`skipped` (below).

### Writing text with `:emit`

`:emit EXPR` evaluates `EXPR` with the holes, `self` and `out`, a `&RwMatch`,
bound; `EXPR` writes the replacement into `out`:

| Form | Writes |
| --- | --- |
| `(rw-put out text)` | `text`. |
| `(rw-put-syn out s)` | `s`'s current text, placed per the rule's line option. |
| `(rw-put-gap out from to indent)` | Source bytes `[from, to)`, normally the space between two `Syn`s. If they are only whitespace and break the line, the line breaks and `indent` spaces instead. |
| `(rw-form-col out)` | Returns the column the form starts at, 0-based. |
| `(rw-col out)` | Returns the column the next byte lands at. |

```lisp
; (swap A B) -> (swapped B A), each operand after the gap before its slot.
(defn emit-swap (out:&RwMatch s:&Syn a:&Syn b:&Syn):void
  (rw-put out "(swapped")
  (rw-put-gap out (((ref s 'kids) 0) 'end) (a 'start) (+ (rw-form-col out) 2))
  (rw-put-syn out b)
  (rw-put-gap out (a 'end) (b 'start) (+ (rw-form-col out) 2))
  (rw-put-syn out a)
  (rw-put out ")"))

(defrewrite swaps
  (rule (swap ~a ~b) :emit (emit-swap out self a b)))
```

`scripts/stage26/list-api-sweep.nuc` is a whole tool built this way.

### Programs inside string literals

A test writes its input program as a string literal. With `--in-strings`
(or `rewrite-source-in-strings`), each string literal's value is read as a
program and the same rules run over it, bottom-up, before the forms around
the string. Strings inside that program are read the same way in turn.

```lisp
(check-output "(defn f (p:ptr:Pt):i32 (return 0))" "")
```

Here a rule that rewrites `p:ptr:Pt` rewrites it inside the string too.

- **Edits are mapped back to the file.** A rewrite inside the value becomes
  an edit of the bytes that spell it, through
  [`syn-string-source`](reading.md#string-literals-as-source)'s map, so
  escapes elsewhere in the literal are kept as written.
- **Replacement text is escaped** for the literal: `"` as `\"`, `\` as
  `\\` and NUL as `\0`. Every other byte is written as it is, a line break
  included. A hole's text is taken from the value, so a byte the source spelled
  with an escape it did not need (`\n`, `\t`, `\x41`) comes back as the
  byte itself.
- **Reports point at the file.** A refusal inside a string prints the line
  and column where the form is written in the file, past the escapes before
  it.
- **Pieces of a program are read as fragments**
  ([`read-syntax-fragment`](reading.md#string-literals-as-source)). In
  `(str "(defn f (p:&Pt) (g " t "))")` neither piece reads alone. A closer
  with no opener is skipped, and a form a piece ends inside keeps what it had
  read, so the rules still reach the complete forms in it. When a string
  ends inside a string literal, as `"(import-use \""` does, the next string
  literal in the same form is read as starting inside one.
- **A string that does not read even so is skipped and counted**, not
  refused, for example one with a `#` that starts nothing. Most string
  literals are messages and read as harmless programs of symbols, which no
  rule matches.
- `(in-string? self)` restricts a rule to programs in strings.
- A rewrite inside a string whose edit would split the bytes of one escape
  (the two bytes `\u00e9` decodes to) is refused at the string: "a rewrite
  inside the string splits an escape".

`scripts/stage26/ptr-sweep.nuc` is a whole tool that uses this.

### Operand slots

`(slot-kind s)` says what `s` is to the forms around it: a binder, a type, an
expression, a name, and so on. A rule that changes one spelling into another
needs it whenever the two mean different things in different places. `(ptr T)`
is a type in a binder's type, but a call in an expression:

```lisp
(import-use nucleus.slots)

(defrewrite ptr-sugar
  (rule (ptr ~x) `&~x :when (= (slot-kind self) SLOT-TYPE))
  (rule (ptr ~x) :refuse "not in a type" :when (= (slot-kind self) SLOT-UNKNOWN)))
```

The answer comes from the table in `lib/nucleus/slots.nuc`
(`nucleus.slots`), which the compiler reads too, to split the binders of the
top-level forms it desugars. It knows the built-in forms only:

- **An operand of a call is `SLOT-UNKNOWN`**, whether the head is a function or
  a macro: `when`, `if`, `make`, `dotimes` and `doseq` are library macros, and
  what a macro does with an operand is not written anywhere a reader can see.
  Elem 0 of every form in code is `SLOT-HEAD`.
- **A quoted form is `SLOT-QUOTED` throughout.** A quasiquote's operand is
  `SLOT-TEMPLATE`, and the forms inside it get the slots their own heads give
  them, as if the template were code. `in-quasiquote?` says whether `s` is in
  one at all.
- **A form a fragment ends inside has no node**
  ([programs inside strings](#programs-inside-string-literals)), so its
  operands are `SLOT-UNKNOWN`; a complete form inside it knows its own.
- A top-level form is `SLOT-TOP`, and so is a form directly inside a top-level
  `do` or `compile-time`.

| Slot | Is | For example |
| --- | --- | --- |
| `SLOT-VALUE` | an expression | `x` in `(return x)`; a body |
| `SLOT-PLACE` | what `set!`, `inc!`, `dec!` write | `(p 'x)` in `(set! (p 'x) 1)` |
| `SLOT-NAME` | a name that is no expression | `S` in `(defstruct S …)`; a namespace; the name in `(x T)` |
| `SLOT-BINDER` | one binding: `x`, `x:T` or `(x T)` | `f` in `(defn f …)`; a parameter; `x` in a `let` |
| `SLOT-FIELD` | a struct or union member, spelled as a binder | `a:i32` in `(defstruct S a:i32)` |
| `SLOT-ATTR` | an attribute or marker keyword | `:volatile`, `:rest`, `:where` |
| `SLOT-BINDINGS` | a `let`, `with`, `if-some` or `when-some` list | `(x 1 y 2)` |
| `SLOT-PARAMS` | a parameter list | `(a b:i32)` in `(fn (a b:i32) …)` |
| `SLOT-DECL-PARAMS` | a `declare`'s parameters | `(x:i32 i64)`: `x:i32` is a binder, `i64` a type |
| `SLOT-OPTIONAL` | `(name default)` after `:optional` | `(z 3)` |
| `SLOT-RETURN` | a return type | `i32` in `(defn f () i32 …)` |
| `SLOT-TYPE` | a type | `T` in `(as T x)`; `(Vector T)` in a binder |
| `SLOT-TYPES` | a list of parameter types | `(i32 u8)` in `((fn void) (i32 u8))` |
| `SLOT-SIG` | a protocol method | `(m (self) i32)` |
| `SLOT-ARM` | a union arm | `(some v:T)` |
| `SLOT-CLAUSE` | a `match` clause | `((some x) x)` |
| `SLOT-PATTERN` | a `match` pattern, throughout | `(some x)` |
| `SLOT-QUOTED`, `SLOT-TEMPLATE` | above | |

A form in a colon fuse has the slot of the elem it reads as: in `p:(ptr T)`,
read as `(p (ptr T))`, `(ptr T)` is a `SLOT-TYPE`. `(slot-name k)` returns a
slot's name, `"type"` for `SLOT-TYPE`, for printing.

The table's other entry points, for code that reads a `Node` rather than a
`Syn`: `(slot-of-elem own n i)` is the slot of elem `i` of list `n` whose own
slot is `own` (`slot-kind` is this, asked recursively up the tree);
`(slots-desugared? n)` says whether the compiler splits `n`'s binders as it
reads a top-level form; `(form-slots n)` and `(form-slots-of head)` return the
row, a `FormSlots`, and `(slot-head n)` the head's text. `SLOT-INLINE`
appears only in the table; `slot-kind` never returns it.

`scripts/stage26/sugar-sweep.nuc` is a whole tool built on slots.

## A rewrite tool

`(refactor-main argc argv rules)` is `main` for a rewrite tool:

```
TOOL [--apply] [--strict] [--in-strings] FILE|DIR|GLOB...
```

`--dry-run` (the default) is accepted for clarity. Any other word starting
with `-` is an unknown option.

Run it with [`nucleusc --run`](compiler.md#running-a-program-without-linking),
which compiles the tool and calls its `main` without linking it. The words
after `--` are the tool's:

```
build/nucleusc --run scripts/tidy.nuc -- src/demo.nuc
build/nucleusc --run scripts/tidy.nuc -- --apply 'lib/**/*.nuc'
```

Compiling the tool takes about a second before its first file is read. A tool
run many times can be built once with `-o` instead.

Each argument is a file, a directory (every `.nuc` and `.nuch` file under
it, recursively) or a [glob](io.md#walking-and-globs) such as
`'lib/**/*.nuc'`. Without `--apply` nothing is written. The tidy tool above,
over a file holding

```lisp
(defn f (l)
  (car (car l))   ; nested
  (swap x y)
  (swap z z)
  (old-api 1 2))
```

prints

```
src/demo.nuc:5:3: tidy: old-api has no replacement yet
src/demo.nuc: 3 rewritten (dry run)

tidy: 3 rewritten in 1 of 1 files; sites reported: 1; dry run, nothing written (--apply writes)
  rule 1 (car ~x): 2 rewritten, 0 refused
  rule 2 (swap ~a ~b): 1 rewritten, 0 refused
  rule 3 (old-api ~@args): 0 rewritten, 1 refused
```

and with `--apply` leaves

```lisp
(defn f (l)
  (node-first (node-first l))   ; nested
  (swap y x)
  (swap z z)
  (old-api 1 2))
```

Each refused or flagged site is a line `path:line:col: NAME: reason`, where
`NAME` is the rule set's; a flagged one ends `(rewritten; check it)`. A file
that does not read, such as a fixture that is malformed on purpose, is
reported as `path:line:1: error: …`, counted in the summary and left alone.
`--in-strings` rewrites the [programs inside string
literals](#programs-inside-string-literals) too, and the summary adds how many
string literals read as programs, as fragments of one, and not at all.
The exit status is 0, or 1 when a file could not be opened or written or an
argument matched nothing, or with `--strict` when any site was reported or
any file did not read; 2 for a bad argument.

## Editing by hand

Every `(old-name …)` call becomes `(new-name …)`, and nothing else in the
file changes:

```lisp
(defn rename-in (f:&SynFile s:&Syn e:&Edits):void
  (let (ks:&(Vector &Syn) (ref s 'kids)
        i:usize 0)
    (when (and (= (s 'kind) SYN-LIST) (> (count ks) 0))
      (let (h:&Syn (ks 0))
        (when (and (= (h 'kind) SYN-ATOM) (= (syn-text f h) "old-name"))
          (edit-replace e h "new-name"))))
    (while (< i (count ks))
      (rename-in f (ks i) e)
      (set! i (+ i 1)))))

(defn rename (src:StrView):!String
  (let (f:&SynFile (match (read-syntax-all src)
                     ((ok v) v)
                     ((err x) (return (err (x 'code)))))
        fs:&(Vector &Syn) (ref f 'forms)
        i:usize 0)
    (with (e:Edits (edits-new))
      (while (< i (count fs))
        (rename-in f (fs i) &e)
        (set! i (+ i 1)))
      (return (ok (try (edits-apply src &e)))))))
```

Given `"; c\n(old-name 1  ; keep\n  (old-name 2))\n"`, `rename` returns the
same text with both heads replaced: the comment, the two spaces before
`; keep` and the line break all stay.

## Edits

| Form | Meaning |
| --- | --- |
| `(edits-new)` | An empty `Edits`. It is `Drop`; bind it with `with`. |
| `(edit-span e start end text)` | Replace source bytes `[start, end)` with `text`. `start` = `end` inserts. |
| `(edit-replace e s text)` | Replace `Syn` `s`'s span: `(edit-span e (s 'start) (s 'end) text)`. |
| `(edits-count e)` | How many edits `e` holds. |
| `(edits-apply src e)` | `EditsResult`: `src` with every edit applied, or the refusal. |
| `(edits-apply-range src e start end)` | `EditsResult`: bytes `[start, end)` of `src` with the edits inside them applied. |
| `(edits-drop-within e start end)` | Remove every edit inside `[start, end)`; returns how many. |
| `(edits-apply-outermost src e start end)` | Like `edits-apply-range`, but edits may nest: an edit inside another is ignored, and so is one enclosing the whole range. One that crosses another or a bound is refused. |

- **The replacement text is copied** into the `Edits`, so it may be a
  temporary: a `String` dropped right after the call is fine.
- **Edits may be added in any order.** They are sorted by start, then end,
  when applied.
- **Overlapping edits are refused, naming both.** Two edits overlap when
  they share a byte, when an insertion lies strictly inside a replacement,
  or when two insertions are at the same byte, since which text comes first
  would be a guess. Edits that only touch, `[1,3)` and `[3,5)`, are fine.
  An insertion at the byte where a replacement starts comes before the
  replacement's text.
- **An edit outside the text is refused**, and so is one whose start is
  after its end.
- **`src` must be the text the spans came from**, normally the `SynFile`'s
  `src`. An `Edits` checked against one text is not re-checked until it
  changes.

`edits-apply-range` and `edits-drop-within` are for rewriting from the inside
out. To rewrite a form whose operands have edits of their own, take each
operand's new text with `edits-apply-range` over the operand's span, build
the form's text from them, drop the edits inside the form, and replace the
form:

```lisp
(let (arg:String (try (edits-apply-range src &e (k 'start) (k 'end))))
  (edits-drop-within &e (s 'start) (s 'end))
  (let (t:String (str "(wrap " (string-as-view &arg) ")"))
    (edit-replace &e s (string-as-view &t))
    (drop &t))
  (drop &arg))
```

Comments and line breaks inside the operand come with its text. In
`edits-apply-range`, an edit wholly outside the range is ignored, an
insertion at either end of the range is inside it, and an edit that crosses
either end is refused.

### Results and errors

```lisp
(defstruct EditError code:Err msg:StrView first:SynSpan second:SynSpan)
(defunion EditsResult (ok v:String) (err e:EditError))
```

`EditsResult` has `Result`'s arms, so `match` and `try` work on it, and
`EditError` converts to `Err`, so `try` passes a refusal up a `!T` function.
The codes are `edit-overlap` and `edit-out-of-range`. `first` and `second` are
the two spans involved: two edits, earlier first, or an edit and the text or
range it does not fit. `msg` names both with line, column and byte span:

```
edit at 2:3 [5,10) overlaps the edit at 2:4 [6,9)
```

The `String` in `ok` is the caller's to drop. `msg` is arena-allocated.

## Printing replacement text

When a replacement is built from a `Node` rather than from source text, print
it with `node-write-sugared` ([reading.md](reading.md#writing-and-comparing)).
It writes `&x`, `'x`, `[a b]` and `x:&T` instead of `node-write`'s long
forms, and falls back to the long form wherever the short one would read back
as a different tree.

## Finding the files

`glob-files` and `walk-dir` in `nucleus.file` list files recursively in a
fixed, bytewise order. `glob-files` takes bash-style `globstar` patterns such as
`lib/**/*.nuc` ([io.md](io.md#walking-and-globs)).
