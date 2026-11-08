# A byte literal: proposal (not built)

Asked for by the nuc-lua port's ISSUE-016, ruled 2026-11-08: a byte literal should be
possible with a reader macro, `b\` as the prefix if that is practical; if not, write up a
proposal for a builtin and don't implement it. **It is not practical as a reader macro,
so this is the write-up. Nothing here is built.**

## 1. Why a reader macro can't do it

`def-rmacro` (docs/toplevel.md) refuses a prefix that begins with a byte that can start
an atom. Only `` $ ' @ ^ ` | ~ `` may open one, because a reader macro is recognized at
the start of a token and an atom-starting prefix would make every symbol that begins
`b` ambiguous with it. `b\e` starts with `b`, so `(def-rmacro "b\\" byte)` is refused.

A reader macro also wraps the *next form*: `$\e` would read as `($ \e)`, a call on the
`Char` literal `\e`. That much works today. A user can write

```lisp
(defmacro byte (c) …)          ; NODE-CHAR → NODE-INT, refusing a codepoint over 127
(def-rmacro "$" byte)
(= (aref s 1) $\e)
```

But it costs a prefix from a set of seven, every file has to repeat both forms (a reader
macro never crosses a file), and it is not the spelling the ruling asked for.

## 2. Proposal: `b\` in the reader

The reader reads `b\` followed by a character literal's body as one token, a byte
literal:

| Source | Reads as |
|---|---|
| `b\e` | the integer literal `101` |
| `b\newline`, `b\space`, `b\tab`, `b\return`, `b\nul` | `10`, `32`, `9`, `13`, `0` |
| `b\x41` | `65` (exactly two hex digits) |
| `b\é`, `b\u{e9}` | refused: "a byte literal is one ASCII character; write (as ui8 0xE9) for a byte past 0x7F" |

- **An integer literal, not a new type.** The node is a `NODE-INT`, so it adapts to its
  partner as any literal does (`(= (aref p 1) b\e)` with `p:(ptr i8)` compares `i8`s)
  and is range-checked by `coerce-int-val`. No `Byte` type, no operator, mangling or
  `node-type` work. `node-write` prints it back as the integer, so a refactoring
  round trip changes its spelling. Recording the spelling on the node (as reader-macro
  prefixes are) would keep it.
- **ASCII only.** Past 0x7F the value of a C `char` depends on the target's signedness,
  which is why the C header importer refuses `'\xE9'` too (`c-cexpr-char`).
- **The clash.** `b\e` reads today as a *symbol*: the reader doesn't end an atom at `\`.
  Nothing in the tree spells one, and a local of that name doesn't even compile (checked
  2026-11-08: `(let (b\e 1) …)` emits `%b\e.addr.0`, which LLVM refuses, a separate
  defect). So the reader arm reclaims a spelling no working program uses. A symbol
  ending in `b` followed by a character literal, `(f b \e)`, is unaffected: the space
  separates them.
- **Cost.** One arm in the reader's atom path (`lib/nucleus/read.nuc`, which both the
  compiler and the REPL use), the escapes table it shares with `Char` literals,
  `node-write`'s sugared printer, the Emacs mode's font-lock, and a docs row in
  types.md's literal table. The reader is in the bootstrap, so the compiler's own source
  can't use `b\` until the boot is refreshed.

## 3. Alternatives considered

- **Let `as` narrow a `Char` constant to `i8`.** `(as i8 \e)` is refused as lossy because
  a `Char` is 32 bits. A rule that a *literal* `Char` under 0x80 converts exactly would
  fix the port's `(= (aref a 1) (as i8 \e))` with no reader change, at three tokens more
  per comparison than `b\e`.
- **A comparison rule**: `=` between an `i8` and a `Char` literal compares bytes. It
  helps one operator and makes `Char` mean two things.
- **A `byte` macro in the prelude**, `(byte \e)` → `101`: no reader change, but it is the
  port's `ch` workaround moved into the library, and its spelling is longer than the
  workaround it replaces.

## 4. Questions for the owner

1. Build `b\` in the reader (§2), or prefer the `as` rule (§3, first bullet)?
2. Should `b\x80`…`b\xFF` be allowed, typed for a `ui8` partner only?
