# Lua-port fixes

The nuc-lua port (`/home/zak/code/nuc-lua`, `ISSUES.md`) filed 57 findings against
Nucleus. Twelve were fixed one commit each on `lua-bugfixes` as the port went. This
table is the owner's rulings of 2026-11-08 on the rest, and what was done with each.
Each built fix has its record in [../progress.md](../progress.md) and is noted in the
port's `ISSUES.md` under the issue.

| Issue | Ruling | Done |
|---|---|---|
| 004 | a function's address is a constant in an initializer, if that causes no problems | built: any `defvar` initializer, aggregates included; no storage class needed |
| 005 | defer | |
| 007 | not a bug | |
| 008 | not a bug | |
| 009 | defer | |
| 010 | `offsetof`, as a macro or, if better, a special form | built as a special form, `usize`, constant-folded |
| 011 | `sizeof` should take a type, not just a name | **question**: it already does; is the ask `type-of` or `countof`? |
| 012 | import string macros like `defconst` | built: a `c"…"` `defconst`, concatenating adjacent literals and string macros |
| 014 | import pointer casts, if 013's machinery can | built: a typed null, or an address; a non-zero function pointer is skipped |
| 015 | defer | |
| 016 | a `b\` byte literal by reader macro, else a written proposal | proposal: [byte-literal.md](byte-literal.md) |
| 017 | `aref` on a `CStr` | built: reads `i8`; `&(aref s i)` is a `CStr`; stores refused |
| 018 | expression macros, if practical with 012/013 | **question**: a C expression translator; scope proposed in the issue |
| 019 | `char *` joins a string literal / `CStr`, in `cond` too | built: the join is `CStr` |
| 020 | `set!` expands its place | built: a macro-headed place expands (since 051 no local can take a macro's name) |
| 021 | `unsafe/ptr-` | built: an element count, `ssize` |
| 022 | a definition missing its header's prototype is an error | **question**: conflicts with Stage 24's `free (self:&Box)` overload |
| 024 | drop the `_` spelling rule; check collisions | built |
| 025 | `sizeof` is `usize` | built, with a size query adapting as a literal beside a signed operand |
| 027 | special-case unary minus in the macro, else options | built: `(- x)` is `(_* -1 x)` |
| 045 | plan storage classes, defer the build | plan: [storage-classes.md](storage-classes.md) |
| 046 | `extern` of `(array T 0)` | built, and headers' array variables import |
| 049 | defer | |
| 050 | a file without `(ns …)` is `user`; else a namespace from the file | built: the per-file private namespace, reachable from the file's own macros |

A second reading of `ISSUES.md` the same day ruled on the later findings:

| Issue | Ruling | Done |
|---|---|---|
| 028, 041 | add the negative-literal rule to the macro | built in the operators, not the macro (below): a negative literal beside an unsigned operand of `bit-and`/`-or`/`-xor` is its bit pattern |
| 029 | explore a constant over a function-like macro; build it if under ~100 lines | built (≈90 lines): textual substitution, then the fold |
| 030 | fix | built: the layout prescan folds a pending constant only if it folds now |
| 031 | fix | built: a row of an array of arrays decays |
| 034 | check for the collision on import; error, suggesting `exclude-prelude` or a prefixed import | built **at the use**, not the import (below) |
| 035 | fix | built: `unsafe/cast` of a function pointer to an integer |
| 036 | fix | built: a macro-headed aggregate initializer expands first |
| 037 | let `defstruct` complete the empty declaration | built: one type, the header's and the program's |
| 038 | check for the collision and error | built: a special form's name is refused as a binding |
| 039 | add the `:programs` map | built: each program a project over the same settings; `--program=` |
| 042 | compare pointers first, contents for two non-null | built |
| 044 | a string literal conforms to `(array i8 …)` | built: a string initializes an `i8`/`ui8` array global, NUL-padded |
| 051 | refuse the binding, as with 038 | built |
| 052 | register macros graph-wide | built: compiled on demand at a cycle partner's use |
| 053 | internal linkage if practical, else the message | both: a private `defn-` links under its namespace's name; the message names both namespaces |
| 054 | look a string path up beside the importing file | built |
| 055 | compare pointers unsigned | built |
| 056 | defer, with 018 | |
| 057 | defer | |

Also in this directory: [variadic-functions.md](variadic-functions.md), built
2026-11-07.

## Decisions taken in building

- **050 took the fallback.** `user` can't hold private names: two namespace-less files
  with a `defn- helper` each would collide. A file's private names already lived in a
  synthetic `#pN` namespace (W5e); a template now writes that full name, and only that
  file resolves it.
- **027 stays in the macro.** The macro can't see its operand's type, but `-1 * x` is
  exact for every numeric type and bit-identical to `0 - x` on integers. A unary
  primitive would need a boot refresh first, since the boot compiler reads
  `lib/nucleus/macros.nuc`. The cost is a multiply at `-O0`.
- **012's constants are `CStr`, not `StrView`.** C's string macro is a `char *`, and a
  `c"…"` literal types without the prelude, which the REPL's boot imports headers
  before.
- **025's adaptation.** Making `sizeof` unsigned alone would have refused every
  `(* n (sizeof T))` with `n` signed. A size query beside a signed operand takes that
  type, widened to pointer width, as a literal adapts.
- **028/041 live in the operators.** The `bit-not` macro can't see its operand's
  type, as with 027, so it can't choose `-1` or the all-ones unsigned; the binary
  `_bit-*` see both operands and convert the literal, which covers `bit-not` and a
  written `(bit-and u -2)` alike.
- **034 refuses at the use, not the import.** Refusing every namespaced import of a
  header that defines a prelude name would have stopped 18 of the port's modules,
  including ones that already write `c/Node`. The use is where the meaning is
  ambiguous, so the message is there, with both ways out.
- **052 compiles the macro on demand, not in the prescan.** Its body may call what is
  defined above it, which exists only once its file is emitted that far. A use from
  the macro's own file, a binder check, and a `user`-namespace macro reached by a
  file that doesn't import its file directly don't fold: every C header import
  flattens to `user`, so without that last rule a library's local named `a` compiled
  the program's macro `a` early.
- **053's private link name.** Under `(set-ir-prefix "")` a `defn-` takes the
  namespace's sanitized name as its prefix; its linkage is internal, so the C-name
  promise of `""` is about public names.
- **The reserved-binder refusal (038, 051) needed renames** across the compiler and
  stdlib (`into`→`sink`, `label`→`lbl`, `field`→`fld`, `new`→`fresh` and others)
  and in 14 examples. A port has the same sweep to make.
