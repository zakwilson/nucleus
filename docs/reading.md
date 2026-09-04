# Reading s-expressions

`lib/read.nuc` — text to `Node`, at runtime.

Every Nucleus program is already handed `Node` and `NodeKind` by the prelude,
because macros are written against them. What the language did not ship was any
way to build one from text. This is that way: configuration, a saved value, a
wire protocol, a test-result file.

```lisp
(import-use read)

(match (read-all "(port 8080)")
  ((ok forms) (let (s:String (node-str (forms 'car)))
                (print (string-as-view (addr-of s)) "\n")
                (drop (addr-of s))))
  ((err e)    (eprint "bad input: " (err-message e) "\n")))
```

See `examples/read-sexp.nuc` for a worked example.

## Reading

| Form | Meaning |
| --- | --- |
| `(read-all src)` | `!(raw Node)` — every form in `src`, as a list. |
| `(reader src)` | A `Reader` over `src`, for reading one form at a time. |
| `(reader-eof? r)` | `true` when only whitespace and comments remain. |
| `(read-one r)` | `!(raw Node)` — the next form. |
| `(reader-error-line r)` | The line to blame for the last failure. |

Check `reader-eof?` before `read-one`: `()` reads as a **null node**, so a null
return is an empty list, not end of input.

The `!` channel carries a code; the position is in the reader. A caller that
wants both reports them together:

```lisp
(match (read-one (addr-of r))
  ((ok n)  …)
  ((err e) (eprint path ":" (reader-error-line (addr-of r)) ": " (err-message e) "\n")))
```

`read-all` is the whole-text form and keeps its `Reader` private, so use the
`reader`/`read-one` pair when a line number matters.

Nodes come from the arena, so nothing here is owned and nothing is dropped.

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
| Strings | `"…"` with `\n \t \r \0 \\ \"` and `\xHH`, and `c"…"` for a `CStr` |
| Chars | `\a`, `\newline`, `\u{1F600}` |
| Keywords | `:name` |
| Comments | `;` to end of line |
| Reader macros | `'` `` ` `` `~` `~@` `@` `&` → `quote` `quasiquote` `unquote` `unquote-splice` `deref` `addr-of` |
| Type sugar | `&T` → `ref:T`, and the colon-paren fuse `name:(Type)` → `(name (Type))` |

## What it does not read

Two pieces of compiler-only surface syntax, both rejected with a positioned
error rather than parsed into a different tree:

- **Collection literals** — `[…]`, `{…}`, `#{…}`. Their desugaring infers an
  element *type* from the elements, which is type inference living in a reader.
  It belongs to the compiler.
- **User reader macros** — `def-rmacro` extends the compiler's own table, which
  a library has no access to. The six built-ins above are here because they are
  part of the written language rather than a per-compilation registration.

This is the whole of the difference, and it is checked rather than asserted:
`run_reader_parity` compiles every file in `tests/fixtures/`, `examples/`,
`lib/` and `src/` with both readers and diffs the results — 429 files agree
exactly, and the only rejections are the ten files using collection literals.

## Errors

`deferror` codes: `read-eof`, `read-unterminated-list`, `read-unexpected-close`,
`read-unterminated-string`, `read-bad-escape`, `read-bad-char`,
`read-int-range`, `read-empty-segment`, `read-collection-literal`.
