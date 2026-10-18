# Reading s-expressions

`lib/nucleus/read.nuc` — text to `Node`, at runtime.

Every Nucleus program is already handed `Node` and `NodeKind` by the prelude,
because macros are written against them. What the language did not ship was any
way to build one from text. This is that way: configuration, a saved value, a
wire protocol, a test-result file — and, since Stage 21, the whole of what the
compiler itself reads. `src/reader.nuc` is gone; `nucleusc` imports this file
directly, so a program and the compiler read the same syntax through the same
code.

```lisp
(import-use nucleus.read)

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
| `(read-syntax-all src)` | `read-all` in [syntax mode](#syntax-mode): the tree plus a source-shaped `Syn` per form. |

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
| `(node-write-sugared out n)` | Append `n`'s text in the house spelling: `&x`, `'x`, `[a b]`, `x:&T`, `\a`. |
| `(node-write-sugared-with out n table)` | The same, with `table`'s reader macros as the prefixes. |
| `(node-str-sugared n)` | The sugared text as a fresh `String`. |

The text `node-write` produces reads back as the same tree, and is identical to
what the compiler prints for that tree (`nucleusc --dump-ast`). Symbols compare
by interned identity, so `node-eq` on two reads of one spelling is a pointer
comparison rather than a string one.

`node-write` prints every form long, `(ref x)` and `(vector-lit 1 2)`, and
stays that way: `--dump-ast` and the corpus gates compare its bytes.
`node-write-sugared` is the printer for text a person reads next: a
refactoring template's output, a macro expansion. It uses each spelling below
**only when the text reads back `node-eq` to the form**, and otherwise
prints that form long. The check is a re-read of the form's own text, so it
needs no list of exceptions:

| Form | Sugared | Kept long when |
| --- | --- | --- |
| `(quote x)` and the other reader macros of `table` | `'x` `` `x `` `~x` `~@x` `@x` `&x` | the prefix would read differently: `(ref rest)` is not `&rest` (the retired marker); `(unquote (deref x))` is not `~@x` |
| `(vector-lit …)` `(hashmap-lit …)` `(hashset-lit …)` | `[…]` `{…}` `#{…}` | an odd map |
| `(tagged-lit tag v)` | `#tag v` | the tag is not a symbol that starts with a letter |
| a symbol or keyword with a `ref:` segment | `x:&T`, `?&Node`, `:k:&T` | the `&` would start the token: `ref:T` stays, since `&T` reads as `(ref T)` |
| a char | `\a`, `\(`, `\space`, `\newline` | not printable ASCII and not named: `\u{e9}` |

A form with the wrong arity for its sugar, such as `(quote)` or `(ref s 'f)`,
is an ordinary list. The type sugar that depends on position, `x:(T)` and
`?(T)` for `(x (T))` and `(? (T))`, is not used: the same tree in a value
position is a call. The printer adds no line breaks.

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
set elements — are `lib/nucleus/edn.nuc`'s.

## Syntax mode

A tool that rewrites source needs what the tree drops: where each form is,
how it was spelled (`&x` and `(ref x)` read as the same node), and where the
comments are. Syntax mode is the same read, by the same code, building a
source-shaped `Syn` tree beside the nodes. The types and queries are
`lib/nucleus/syntax.nuc`'s, so a tool imports both files:

```lisp
(import-use nucleus.read)
(import-use nucleus.syntax)

(match (read-syntax-all text)
  ((ok f) (let (forms:&(Vector &Syn) (ref f 'forms) i:usize 0)
            (while (< i (count forms))
              (let (s:&Syn (forms i))
                (print path ":" (s 'line) ":" (s 'col) ": " (syn-text f s) "\n"))
              (set! i (+ i 1)))))
  ((err e) (eprint path ":" (e 'line) ": " (e 'msg) "\n")))
```

| Form | Meaning |
| --- | --- |
| `(read-syntax-all src)` | `SynFileResult`: `(ok f)` with `f` a `&SynFile`, or the same `ReadError` `read-all` returns for `src`. |
| `(reader-syntax src)` | A `Reader` in syntax mode, with a fresh built-in macro table. |
| `(read-syntax-one r)` | `SynResult`: the next form's `&Syn`, or the `ReadError`. Check `reader-eof?` first. An ordinary reader is switched into syntax mode here. |
| `(reader-syn-file r)` | The `?&SynFile` a syntax-mode reader is building; null for an ordinary one. |
| `(syn-text f s)` | The raw source of `s`. |
| `(syn-slice f start end)` | Any byte range of the source. |
| `(syn-prefix f s)` | A `SYN-PREFIX`'s prefix as written (`'`, `&`, `~@`, a `def-rmacro` prefix); `""` for any other kind. |
| `(syn-has-comment? f s)` | Whether a `;` comment lies inside `s`. |
| `(syn-has-discard? f s)` | Whether a `#_` discard lies inside `s`. |
| `(syn-kid-for-elem s i)` | The `Syn` whose span is elem `i` of `(s 'node)`, or null when that elem has no span of its own. |
| `(syn-elem-index s k)` | The elem of `(s 'node)` that kid `k` spans, or `-1`. |
| `(syn-kid-for-node s n)` | The kid of a `SYN-FUSE` whose node is `n`, by identity; null otherwise. |

```lisp
(defenum SynKind SYN-ATOM SYN-STR SYN-CHAR SYN-LIST SYN-VEC SYN-MAP SYN-SET
                 SYN-PREFIX SYN-TAGGED SYN-FUSE)
(defstruct Syn kind:i32 start:usize end:usize line:i32 col:i32 open:i32
               node:?&Node parent:?&Syn kids:(Vector &Syn))
(defstruct SynSpan start:usize end:usize)
(defstruct SynFile src:StrView tree:&Node forms:(Vector &Syn)
                   comments:(Vector SynSpan) discards:(Vector SynSpan)
                   fragment:bool ends-in-string:bool)
```

- `start`/`end` are a half-open byte span, with the whitespace and comments
  around the form excluded. `line` and `col` are 1-based, and `col` counts
  bytes, so `path:line:col` points at the form.
- `open` is the length of the opening delimiter or the prefix spelling:
  1 for `(`, `[`, `{` and a tagged literal's `#`, 2 for `#{`, the prefix's
  bytes for a `SYN-PREFIX`, and 0 for a leaf or a fuse.
- `node` is the node the read produced for this span: the same pointer as
  the element of the tree, not a copy.
- `kids` are the source's children, in order. `parent` is null at the top level.
- `tree` is the list `read-all` returns for the same text. `forms` holds one
  top-level `Syn` per element of it.
- `comments` holds every `;` comment, from the `;` to the end of its line
  with the newline excluded. `discards` holds every `#_ form`, from the `#_`
  to the end of the dropped form. Both are in source order and include those
  inside a discarded form, so `#_ #_ a b` records two discards, one inside
  the other. A discarded form has no `Syn`.

| Source | Kind | Node, and kid *i* ↔ elem |
| --- | --- | --- |
| `a`, `x:&T`, `0x1F`, `:k` | `SYN-ATOM` | the symbol `x:ref:T`, `NODE-INT` 31, …; the span is the raw text |
| `"a\n"`, `c"a"` | `SYN-STR` | the decoded `NODE-STR` |
| `\a`, `\u{1F600}` | `SYN-CHAR` | `NODE-CHAR` |
| `(a b)` | `SYN-LIST` | `(a b)`; kid *i* ↔ elem *i* |
| `[a b]`, `{k v}`, `#{a}` | `SYN-VEC`, `SYN-MAP`, `SYN-SET` | `(vector-lit a b)` …; kid *i* ↔ elem *i+1* |
| `#tag v` | `SYN-TAGGED`, kids `tag` (an atom) and `v` | `(tagged-lit tag v)`; kid *i* ↔ elem *i+1* |
| `'x`, `&x`, `~@x`, a `def-rmacro` prefix | `SYN-PREFIX`, kid `x` | `(quote x)` …; kid 0 ↔ elem 1 |
| `x:(T)`, `x:ptr:(T)`, `f:(fn i32)(i32)`, `:(T)` | `SYN-FUSE`, kids the atom and each list | see below |

A fuse is two or three source forms read as one tree, so its rule is
identity rather than position. The atom kid corresponds to no elem. Its
`node` is the atom read on its own (`x:`), which is not in the tree. Each list
kid's node is a fresh list, so `syn-kid-for-node` finds it wherever it sits:

- `x:(T)` reads as `(x (T))`, and the list is elem 1.
- `x:ptr:(T)` reads as `(x (ptr (T)))`. Elem 1, `(ptr (T))`, is a wrapper the
  fuse made and has no span. The list is inside it.
- `f:(fn i32)(i32)` reads as `(f ((fn i32) (i32)))`, and both lists are inside
  elem 1.
- `:(T)` reads as `(T)` itself, so the fuse's node is its list kid's node, and
  `syn-kid-for-elem` answers through that kid.

**Guarantees**, checked over every `.nuc` and `.nuch` in `tests/fixtures`,
`examples`, `lib` and `src` by `scripts/stage26/syn-corpus.nuc`:

- `read-syntax-all` succeeds exactly when `read-all` does, with the same
  error. Its `tree` is `node-eq` to `read-all`'s.
- Every byte of the source is one of: inside an atom, string or char span;
  inside a comment or discard span; a delimiter or prefix byte of its
  innermost container (the `open` bytes, and the closing bracket); or
  whitespace or a comma.
- A `Syn`'s text, read on its own, is one form, `node-eq` to its `node`. The
  exception is a text containing a `def-rmacro` prefix, which needs the
  file's earlier `def-rmacro`.

The ordinary read pays one test of the `Reader`'s `syn` field per form (and
per comment) and allocates no `Syn`. In syntax mode everything is arena-allocated, like the
nodes, so nothing is dropped. The `SynFile` borrows `src`, which must
outlive it.

### Colon chains

An atom such as `x:ptr:T`, `?&Node` or a fuse's `x:&` is a colon chain.
`chain-segments` splits its raw text into segments, and a rewrite edits a
segment's span. The splitter is the reader's own: the `&` expansion, the
colon-paren fuse and the compiler's desugar all segment through
`chain-seg-at`. It is in `nucleus.read`.

```lisp
(defstruct ChainSeg start:usize body:usize end:usize colon:bool)
(defstruct Chain text:StrView keyword:bool segs:(Vector ChainSeg))
```

| Form | Meaning |
| --- | --- |
| `(chain-segments text)` | A `&Chain` with every segment of `text`, arena-allocated. |
| `(chain-seg c i)` | Segment `i`. |
| `(chain-sigils c i)` | Segment `i`'s sigil run: `"?&"` in `?&Node`, `""` in `ptr`. |
| `(chain-body c i)` | Segment `i` after its sigils: `"Node"`, `"ptr"`. |
| `(chain-open? c)` | Whether the last segment has no body (`x:`, `x:?`, `?&`). An open atom fuses with a `(` written right after it. |
| `(chain-seg-at text at)` | The segment starting at byte `at`: 0, or one past a segment's `:`. It allocates nothing. |
| `(chain-seg-next text seg)` | The segment after `seg`, which must have `colon` set. |
| `(chain-seg-text text seg)` | A segment's text, its sigils included and its `:` excluded. |

- A segment runs from its first byte to the next `:` or the end of the
  text. `start`, `body` and `end` are byte offsets into the chain's text, so
  `[start, body)` is the sigil run and `[body, end)` is the body. `colon` is
  set when a `:` follows at `end`. To get a file span, add the atom `Syn`'s
  `start`.
- The sigil run is the `?`, `!` and `&` bytes at the start of a segment.
  The same bytes later in a segment belong to its body, so `foo?` and `a&b`
  have no sigils. `!=` has the sigil `!` and the body `=`, and it is not
  open.
- A trailing `:` leaves an empty last segment, so `x:ptr:` has three
  segments. A lone `:` has two empty segments. `""` has one.
- A keyword's leading `:` separates nothing. `:k:T` has `keyword` set and
  the two segments `k` and `T`, starting at byte 1. A symbol's segment 0 is
  what a binding position reads as the name. A keyword has no name.
- The split is lexical, so the caller decides that the atom is a symbol.
  `chain-segments` reports the `&` of a retired `&rest` marker as a sigil,
  although the reader leaves that marker unexpanded.

`x:ptr:` → `x:&` is one replacement. In the source, replace the span from
segment 1's `body` to one past its `end` with `&`.

### String literals as source

A program can sit inside a string literal, as a test's input does. To read
it, decode the literal; to edit it, map an offset in the decoded text back
to the byte of the file that spells it. Both are in `nucleus.read`:

```lisp
(defstruct StrSource text:StrView map:(Vector usize))
```

| Form | Meaning |
| --- | --- |
| `(syn-string-source f s)` | `?&StrSource`: the value of the `SYN-STR` `s`, decoded by the reader's own escape decoder, and its map. Null for any other kind. Arena-allocated. |
| `(str-source-at ss i)` | The file offset where value byte `i` is spelled: the byte itself, or the `\` of its escape. `i` may be the value's length, which gives the closing quote's offset. |
| `(str-source-split? ss i)` | Whether value offset `i` falls inside the bytes one escape decodes to (the second byte of `\u00e9`), where no file offset corresponds. |
| `(str-source-escape out text)` | Append `text` spelled for the inside of a literal: `\"`, `\\` and NUL as `\0`; every other byte, line breaks included, as it is. |
| `(read-syntax-fragment src starts-in-string)` | `SynFileResult`: `read-syntax-all` over a piece of a program (below). |

The map has one entry per value byte plus one for the end, so a value span
`[a, b)` is the file span `[(str-source-at ss a), (str-source-at ss b))`
whenever neither end is split. Reading the value is the ordinary
`read-syntax-all` over `(ss 'text)`; its offsets are value offsets.

A test often builds its program from pieces, `(str "(defn f (p:" t ") …")`,
so a piece need not read on its own. `read-syntax-fragment` reads one
anyway:

- a closer with no opener is skipped;
- a form the text ends inside, a list or a string, is kept in `forms` with a
  null `node`, its `end` at the end of the text, and the kids it had read;
  it has no element in `tree`;
- with `starts-in-string` set, the text is taken to begin inside a string
  literal, and reading starts past the first unescaped `"`;
- any other error is returned, as `read-syntax-all` would return it.

`fragment` is set when any of these happened, and `ends-in-string` when the
text ends inside a string literal, so the next piece starts inside one.

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
