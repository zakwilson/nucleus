# Reading s-expressions

`lib/read.nuc` — text to `Node`, at runtime.

Every Nucleus program is already handed `Node` and `NodeKind` by the prelude,
because macros are written against them. What the language did not ship was any
way to build one from text. This is that way: configuration, a saved value, a
wire protocol, a test-result file — and, since Stage 21, the whole of what the
compiler itself reads. `src/reader.nuc` is gone; `nucleusc` imports this file
directly, so a program and the compiler read the same syntax through the same
code.

```lisp
(import-use read)

(match (read-all "(port 8080)")
  ((ok forms) (let (s:String (node-str (node-first forms)))
                (print (string-as-view &s) "\n")
                (drop &s)))
  ((err e)    (eprint "bad input, line " (e 'line) ": " (e 'msg) "\n")))
```

See `examples/read-sexp.nuc` for a worked example.

## Reading

| Form | Meaning |
| --- | --- |
| `(read-all src)` | `ReadResult` — every form in `src`, as a list. |
| `(read-all-with-macros src table)` | The same, reading through a caller-owned reader-macro table instead of a fresh built-in one. |
| `(reader src)` | A `Reader` over `src`, for reading one form at a time, with a fresh built-in macro table. |
| `(reader-with-macros src table)` | The same, sharing a caller-owned table. |
| `(reader-eof? r)` | `true` when only whitespace, comments and `#_` discards remain. |
| `(read-one r)` | `ReadResult` — the next form. |
| `(reader-edn src)` | A `Reader` in [EDN mode](#edn-mode). |
| `(read-all-edn src)` | `read-all` in EDN mode. |

Check `reader-eof?` before `read-one`: at end of input `read-one` is a
`read-eof` error. `()` reads as an empty list, not a null node.

`read-all` is the whole-text form and keeps its `Reader` private; use the
`reader`/`read-one` pair when a line number matters as you go, or when several
buffers must share one reader-macro table (the REPL's own use, below).

Nodes come from the arena, so nothing here is owned and nothing is dropped.

## `ReadResult` and `ReadError`

`read-one`/`read-all` (and their `-with-macros` twins) return a `ReadResult`,
not a plain `!ptr:Node`:

```lisp
(defunion ReadResult (ok v:?&Node) (err e:ReadError))
(defstruct ReadError code:Err line:i32 msg:StrView note:StrView)
(defcast ReadError Err read-error-code)
```

- `code` — one of the twelve `deferror` ids below (§Errors).
- `line` — the line to blame.
- `msg` — the specific, formatted message for this failure (`unknown escape
  \q`, not just `read-bad-escape`'s generic `deferror` text — `err-message`
  gives you that generic text back from `code` alone, if that is all you
  want).
- `note` — a second line of context, empty unless the fault stages one (an
  unterminated form names where it opened; `unexpected )` names where it was
  already closed).

`msg` and `note` are built in the **arena** — the reader's allocator for
everything it returns — so nothing here is owned either, and a `Reader` needs
no `drop`.

`match` binds the struct by field:

```lisp
(match (read-all text)
  ((ok forms) …)
  ((err e)
    (eprint path ":" (e 'line) ": " (e 'msg))
    (when (> ((e 'note) 'len) 0) (eprint "\n  note: " (e 'note)))
    (eprint "\n")))
```

`try` propagates a `ReadError` unchanged into a caller that also returns
`(Result T ReadError)`; into a caller declared `!T`, it propagates the `code`
alone, converted automatically through the `defcast` at the `(return (err!
e))` `try` expands to:

```lisp
(defn load (src:StrView):!ptr:Node
  (return (ok (try (read-all src)))))    ; on err, ReadError -> Err via the defcast
```

This is the general shape a library with a rich error returns, not a reader
special case — see [Error Handling](errors.md#err-is-the-code-result-t-e-is-the-payload).

`ReadResult` is a hand-written `defunion`, not a `(Result ?&Node ReadError)`
instance: a template stamped over a nullable pointer payload loses
that pointer kind (`type-spelling` re-spells every stamped pointer as `ref:`,
non-null), so the template's `ok` arm would refuse a null node. `try`, `match`
and `unwrap` do not care — a `defunion` with an `ok` arm and an `err` arm is
eliminated as a Result **structurally**, whether or not it is literally a
`(Result T E)` instance. See [Unions and tagged sums](structs-unions.md#unions-and-tagged-sums).

## `def-rmacro`

A `Reader` registers `(def-rmacro "prefix" symbol)` **as it reads it** — the
readtable is the reader's own, as in any Lisp — so the prefix takes effect for
every form read afterward through that same `Reader` or `read-all` buffer:
**file-scoped and forward-only**. A form before the `def-rmacro`, a different
file, or a fresh `read-all` call with no shared table never sees it. The REPL
is the exception that proves the rule: every prompt's `Reader` is built with
`reader-with-macros` over one session table, so a `def-rmacro` typed at one
prompt is visible at the next.

```lisp
(def-rmacro "$" interpolate)   ; from here on, $x reads as (interpolate x)
```

Refused, all `read-bad-rmacro`:

| Refusal | When |
| --- | --- |
| `def-rmacro: expects (def-rmacro "prefix" symbol)` | wrong shape |
| `def-rmacro: prefix must be a string` | |
| `def-rmacro: wrap symbol must be a symbol` | |
| `def-rmacro: '<p>' is already a reader macro` | including the six built-ins |
| `def-rmacro: prefix must not begin with a byte that can start an atom` | see below |

The last refusal exists because nothing else caught it: an unguarded
`(def-rmacro "my" w)` used to read `myvar` as `(w var)`, and `(def-rmacro "<"
w)` broke `<=`. A prefix may begin only with one of the eight bytes no atom
starts with — `` $ ' @ ^ ` | ~ `` — everything else (a letter, digit, sign,
`?`/`!`/`&`/`#`/`:`/`.`, an operator character, a delimiter, a comma, which is
whitespace, or an empty string) is refused.

## Table API

| Form | Meaning |
| --- | --- |
| `(read-macro-table-new)` | A fresh `(ref (Vector RMacro))`, seeded with the six built-ins. |
| `(reader-register-macro r prefix wrap line)` | `ReadResult` — register a macro on an existing `Reader`, under the same checks `def-rmacro` gets. |
| `(rd-macro-find table prefix)` | The table index for `prefix`, or `-1`. |

`RMacro` is `prefix:StrView wrap:Symbol`.

## Writing and comparing

| Form | Meaning |
| --- | --- |
| `(node-write out n)` | Append `n`'s canonical text to a `String`. |
| `(node-str n)` | That text as a fresh `String` (drop it). |
| `(node-eq a b)` | Structural equality. |

The text `node-write` produces reads back as the same tree, and is identical to
what the compiler prints for that tree (`nucleusc --dump-ast`). Symbols compare
by interned identity, so `node-eq` on two reads of one spelling is a pointer
comparison rather than a string one.

## What it reads

The s-expression language, and Nucleus's atom syntax:

| | |
| --- | --- |
| Lists | `(a b c)`, and `()` as a null node |
| Symbols | including colon chains — `ptr:i8`, `x:ref:T` |
| Integers | decimal and `0x` hex, signed; a positive literal too big for `i64` is read at `ui64` width |
| Floats | `1.5`, `2e10`, `0x1p0`, and `+inf.0` / `-inf.0` / `+nan.0` |
| Strings | `"…"` with `\n \t \r \0 \\ \"`, `\xHH` and `\uXXXX`, and `c"…"` for a `CStr`; no length cap |
| Chars | `\a`, `\newline`, `\u{1F600}`, `\u00e9` |
| Keywords | `:name` |
| Comments | `;` to end of line |
| Whitespace | the C `isspace` set, **and the comma**: `{:a 1, :b 2}` |
| Discard | `#_ form` reads `form` and drops it, wherever a form may appear — `#_ #_ a b` drops two; a map's even-count check counts what is left |
| Tagged literals | `#tag form` → `(tagged-lit tag form)`; the tag starts with a letter. Data syntax: the compiler refuses one in source (`tagged literal '#tag' is data syntax`) |
| Reader macros | `'` `` ` `` `~` `~@` `@` `&` → `quote` `quasiquote` `unquote` `unquote-splice` `deref` `ref` — one head for both worlds: `&T` in a type slot is the non-null pointer `(ref T)`, `&x` in a value slot is the address-of `(ref x)` |
| Type sugar | `&T` → `ref:T`, and the colon-paren fuse `name:(Type)` → `(name (Type))` — on any atom whose final chain segment is open (`x:`, `x:?`, `?`, `?!`, the lone `:`) and is immediately followed by `(`, wherever the atom is read: a list element, a reader-macro operand, a literal element, a top-level form ([types.md](types.md#type-syntax-and-desugar)) |
| Collection literals | `[a b]` → `(vector-lit a b)`, `{k v}` → `(hashmap-lit k v)`, `#{a b}` → `(hashset-lit a b)` — **no element-type inference and no gensym**; the compiler infers a literal's element type and mints its hygiene symbol itself, at emit time. The cell's `i` field holds its `LitMark` — `LIT-VECTOR`, `LIT-MAP`, `LIT-SET`, `LIT-TAGGED`, or `LIT-NONE` (0) for every other list — so `[1]` can be told from the text `(vector-lit 1)`. `node-write` and `node-eq` ignore the mark. |
| `def-rmacro` | registers a new reader macro as it is read (above) |

## EDN mode

`reader-edn` / `read-all-edn` read [EDN](edn.md) data rather than Nucleus
source. Everything above applies, except:

- no reader macros: `'q`, `&x` and `@x` are symbols;
- no `&` sigil in an atom (`a:&b` stays `a:&b`) and no colon-paren fuse
  (`a:(1)` is two forms);
- `(def-rmacro …)` is a list, not a directive, and `c"…"` is the symbol `c`
  then a string;
- an integer must fit a signed 64 bits (no `ui64` widening), and may carry an
  `N` suffix; a number with an `M` suffix reads as a float whose text keeps the
  `M`;
- hex numbers and `+inf.0`/`-inf.0`/`+nan.0` are symbols.

The EDN rules the reader does not check — legal symbols, unique map keys and
set elements — are `lib/edn.nuc`'s.

## Errors

`deferror` codes: `read-eof`, `read-unterminated-list`, `read-unexpected-close`,
`read-unterminated-string`, `read-bad-escape`, `read-bad-char`,
`read-int-range`, `read-empty-segment`, `read-map-odd`, `read-bad-rmacro`,
`read-bad-tag` (a `#` with no tag, or a tag with no value), `read-bad-discard`
(a `#_` with no form after it).

`(err-name (e 'code))` / `(err-message (e 'code))` give the code's stable name
and its generic `deferror` text; `(e 'msg)` / `(e 'note)` give the specific
text for this failure, including the parts a bare `Err` id cannot carry (the
bad character, the line count, the colon-chain segment).
