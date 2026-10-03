# EDN support

Nucleus needs a first-class format for serializing data as text, configuration for a future build system, etc.... I have selected EDN (https://edn-format.dev/).

## Implementation

EDN support should be implemented as a library, but it should rely on the Nuleus reader as much as practical. It is preferable to modify the reader rather than add workarounds; tagged literals may require this.

## Serializing structs

For a first pass, the library should be able to serialize and deserialize simple structs. The serialized format should be a tagged map with values as literals or subsequent tagged maps. When reading, string and numeric literals should be conformed to compatible types.

Avoid implementing anything especially complex for the first pass. Potential examples of complexity include structs with specific memory layouts or complex C interop.

---

# Implementation plan

**Status:** designed 2026-10-02; **ED-1 … ED-3 built 2026-10-02**, with their
ED-5 tests and ED-6 docs (§7 "As built"). Q1, Q2, Q7 and Q8 decided 2026-10-02
(§6). Q3–Q6 were decided at the checkpoint, 2026-10-02. **ED-4 is built**
(2026-10-03): [ed4-struct-codecs.md](ed4-struct-codecs.md) §6, with ED-4.1 in
[macro-definitions.md](macro-definitions.md) §6. Q8's non-interning follow-up is
deferred within the stage. **Follow-on built 2026-10-03:** the test suite's
reports, `--diagnostics=edn` and the rejection manifest are EDN maps,
[test-records.md](test-records.md) §7.

## Decisions (2026-10-02)

| Q | Decision |
| --- | --- |
| Q1 — where the new reader syntax applies | **Universal**: commas, `#_`, `#tag`, `\uXXXX` are Nucleus syntax too |
| Q2 — data model | **A typed view over `Node`**, not an owned value type |
| Q3 — how struct codecs are derived | **A compiler primitive** (2026-10-02): struct reflection that any library can use to derive its own format. A list of field name/type pairs that a macro can walk is enough. Derivation is **explicit**: implicit derivation would cost memory or artifact size. A library's codecs can live in an optional companion library (`geometry` → `geometry-edn`) that a program which never serializes those types does not import or link |
| Q4 — struct tag spelling | **Namespace-qualified, as the EDN spec requires of user tags** (revised 2026-10-02): a user type is tagged with its own namespace (`#geom/Point`), and a Nucleus builtin with `nucleus/`. The tag must match the destination's qualified name exactly. Supersedes the earlier "bare name" answer |
| Q5 — unknown and missing keys | **Strict** (2026-10-02): both are errors |
| Q6 — untagged collections | **A plain map is a `HashMap`, a vector a `Vector`, a set a `HashSet`** (2026-10-02). Keys may be any EDN value per the spec. Key types the current `HashMap` cannot cleanly handle may be excluded for now. A named struct is always tagged, and an anonymous struct carries a `nucleus/` builtin tag |
| Q7 — `N` / `M` suffixes | **Accept when the value fits** |
| Q8 — interning | **Intern everything for now.** A non-interning path *may* belong in Stage 22. That decision is deferred within the stage (reaffirmed 2026-10-02) |

---

## 1. Ground truth (verified 2026-10-02)

### 1.1 One reader

`lib/read.nuc` is the only reader; the compiler imports it
(`src/nucleusc.nuc:1151`). Public API: `read-all`, `read-all-with-macros`,
`reader`, `reader-with-macros`, `reader-eof?`, `read-one`, all returning
`ReadResult` (`:55`, `(ok v:?&Node) | (err e:ReadError)`); `ReadError` is
`code line msg note` with a `defcast` to `Err`. Errors carry a **line, no
column**. Nodes and messages live in the arena; nothing is dropped.

There is **no mode flag**. The only knob is the reader-macro table
(`read-macro-table-new`, `:101`).

### 1.2 Node

`(defstruct Node kind line i s elems len cap)` (`lib/prelude.nuc:29`), kinds
INT STR SYM LIST FLOAT KEYWORD CHAR.

- FLOAT keeps its **source text** in `s`, never a parsed value.
- STR and SYM text is **interned** (never freed). SYM nodes are interned
  singletons, so their `line` is 0.
- `[…]`, `{…}`, `#{…}` read as `(vector-lit …)`, `(hashmap-lit …)`,
  `(hashset-lit …)` cells (`rd-lit-cell`, `:800`). Nothing marks the bracket:
  the text `(vector-lit 1)` and `[1]` read as the same tree.
- A LIST node's `i` field is **unused**, and `node-eq` (`:1012`) ignores it for
  lists.

### 1.3 EDN against the reader

| EDN element | Today |
| --- | --- |
| `nil` `true` `false` | plain symbols |
| strings | `\n \t \r \0 \\ \"` and `\xHH` (`rd-string`, escape `cond` at `:457`); **no `\uXXXX`** |
| chars | `\c`, `\newline`, `\return`, `\space`, `\tab`, `\u{…}`; **`\uXXXX` fails** as an unknown named char |
| symbols | fine, incl. `/` and `.`; but a leading `&` is a reader macro and `&` at a colon segment start expands (`a:&b` → `a:ref:b`) |
| keywords | `:a`, `:ns/name` → KEYWORD with `s` = text after `:` |
| integers | signed decimal, `0x`; **no `N`**; > ui64 is `read-int-range` |
| floats | decimal, exponent, hex, `±inf.0`, `+nan.0`; **no `M`** |
| `()` `[]` `{}` `#{}` | yes, as §1.2 cells; `{}` odd count refused in the reader (`:851`) |
| `;` comments | yes |
| **commas** | **not whitespace** (`rd-space?` `:197`, `rd-sym-char?` `:223`): `{:a 1, :b 2}` reads `1,` as a symbol |
| **`#_`** | **no** — `#` matters only before `{` (`:842`); `#_` is a symbol |
| **`#tag v`** | **no** — `#inst "x"` is two siblings, the symbol `#inst` and a string |

Because the odd-count check runs **inside** the reader, `{:a #inst "x"}` and
`{:a 1 #_ :b}` fail with `read-map-odd` before any library sees them, and
even-count cases mis-pair silently. A library-side workaround is not possible;
the reader has to change, as the brief anticipated.

Nucleus-only behaviour that is wrong for EDN data:

- reader macros `'` `` ` `` `~` `~@` `@` `&` (`&foo` → `(ref foo)`);
- `&` sigil expansion inside atoms (`rd-expand-sigil`);
- the colon-paren fuse (`a:(1)` → `(a (1))`);
- `def-rmacro` registering as a side effect of `read-one` (`:901`);
- `c"…"` strings (`:877`).

### 1.4 Printer

`node-write` / `node-str` (`:972`, `:1005`) print what the compiler prints:
`(vector-lit …)` heads, `\u{hex}` chars, `\0`, `c"…"`. Not EDN. Reusable:
`sexp-write-string` (`:965`).

### 1.5 `#`-leading names are compiler hygiene

The compiler synthesizes names that begin with `#` and relies on source being
unable to collide with them: W5e private namespaces `#pN`
(`src/compiler-types.nuc:1317`; `src/nucleusc.nuc:18129` refuses `(ns #…)`),
`#env-arg-N` (`src/union-registry.nuc:1659`), `#c/` (`src/cheader.nuc:3031`),
`#dry` (`src/generics.nuc:4949`), and since HY-3 the quasiquote tag `#h<N>/`
(quasiquote-resolution.md §3.3). Today a source `#foo` reads as a symbol and
only the `ns` check guards it. After ED-1 a leading `#` is reader syntax, which
makes these names unspellable — stronger hygiene — **provided none of them is
ever printed by `node-write` and read back** (a `--dump-ast` corpus, an emitted
`.nuch`, a REPL echo). No committed `.nuch` contains one today; ED-1 must
confirm the other paths.

### 1.6 Building blocks for the library

- Output: `ToStr` / `str-into` (`lib/fmt.nuc`), `String`, `sexp-write-string`.
  `Keyword`'s `to-str` drops the leading `:`.
- Numbers: `(parse T sv)` for i32, i64, ui64, f64 (`lib/parse.nuc`), strict.
- Keywords: `Keyword` (`lib/keyword.nuc`), interned, `Hash`/`Eq`.
- Rich errors: `ReadError` + `defcast` + hand-written `defunion` result
  (`docs/reading.md` §ReadResult) is the pattern to copy.
- Structs: **no** reflection over fields, compile-time or runtime
  (`StructDef.fields` is unreachable from macros; `design/stage6-cleanup.md:15`,
  `deferred/overview.md:144`). Relevant only to the deferred ED-4.

---

## 2. Verdict

1. **New syntax in the shared reader, for everyone (Q1).** Commas are
   whitespace; `#_` discards the next form; `#tag form` reads as
   `(tagged-lit tag form)`; strings and chars accept `\uXXXX`. Nucleus source
   gains `#_` for free; a `tagged-lit` reaching the compiler gets a targeted
   diagnostic.
2. **An EDN mode on `Reader`** turns *off* what is Nucleus-only (§1.3's list)
   and turns *on* `N`/`M`. Compiler reads never set it.
3. **Bracket marker.** The reader stamps the unused `i` of each literal cell, so
   `[1]` and `(vector-lit 1)` are distinguishable without a new `NodeKind` (which
   would ripple through every `(n 'kind)` switch in the compiler). `node-eq`
   already ignores `i`, so the reader↔printer round-trip audit is unaffected.
4. **`lib/edn.nuc` is a typed view over `Node` (Q2)**: an `EdnKind`
   classification plus accessors and validation, a writer, and per-type scalar
   `edn-read` / `edn-write` overloads. No copy of the tree, no owned values;
   every string interned (Q8).
5. **Struct codecs wait (Q3–Q6).** The scalar overloads from ED-3 are what any
   derivation will call, so they are built now regardless of which derivation
   is chosen.

---

## 3. Milestones

### ED-1 — reader: new syntax and EDN mode

Files: `lib/read.nuc` (regenerate `lib/read.nuch`, `lib/read.h`), one compiler
diagnostic, tests.

1. **Commas are whitespace.** `rd-space?` adds `,`; that removes it from
   `rd-sym-char?` and from the eight bytes a `def-rmacro` prefix may start with
   (`docs/reading.md` §def-rmacro). No source in `src/`, `lib/`, `examples/` or
   `tests/fixtures` uses a comma outside a string or comment (checked
   2026-10-02).
2. **`#_` discard.** In `rd-form`, `#_` reads and drops the next form, then
   reads again. The discard lives in the element loop of lists and literal
   cells too, so the map odd-count check counts forms *after* discards. `#_` at
   end of input or before a closer is a new error `read-bad-discard`.
3. **`#tag form`.** `#` followed by a letter reads a symbol (the tag) and then
   one form, yielding `(tagged-lit tag form)` with marker `TAGGED`. A tag with no
   following form is `read-bad-tag`. `#` followed by anything other than a
   letter, `_` or `{` is `read-bad-tag` as well, so no `#`-leading symbol can be
   read.
4. **`\uXXXX`** — exactly four hex digits — in strings and chars. `\u{…}` stays;
   `\u` alone is still the letter `u`. Code points that are UTF-16 surrogates are
   refused (`read-bad-escape` / `read-bad-char`).
5. **Bracket markers.** `rd-form` sets `(cell 'i)` after `rd-lit-cell`: a
   `defenum LitMark` of `LIT-NONE LIT-VECTOR LIT-MAP LIT-SET LIT-TAGGED`
   (`LIT-NONE` = 0, so every other list is unchanged).
6. **EDN mode.** A `Reader` field `edn:bool`; constructors `edn-reader` and
   `read-edn-all`. In EDN mode: an empty macro table; no `rd-expand-sigil`; no
   colon-paren fuse; no `def-rmacro` registration; no `c"`; `N` after an
   integer reads it as NODE-INT (range-checked as today); `M` after a number
   reads it as NODE-FLOAT with the `M` stripped from the text (Q7). Outside EDN
   mode `1N` / `1.5M` stay symbols. Adding the field changes the `Reader`
   layout; every construction goes through the constructors, so only
   `read.nuch`/`read.h` change.
7. **Compiler side.** A `(tagged-lit …)` form in Nucleus source dies with
   *"tagged literal '#tag' is data syntax; Nucleus source has no reader for
   it"*. Where it is caught: at the top of `emit-list`'s special-form dispatch,
   with `node-type` returning null for it (an error path, so the lockstep in
   `context/conventions.md` is satisfied by the escape). One manifest row.
8. **W5e fixture.** `(ns #p1)` now fails in the reader (`read-bad-tag`: `#p1`
   is followed by `)`) and no source spelling reaches the `ns` check any more.
   Keep the check as defence in depth for synthesized names, and change the
   `w5e-ns-hash-reserved` manifest row to expect the reader error.
9. **§1.5 audit.** Confirm no synthesized `#`-leading symbol is printed and
   re-read: `--dump-ast`, `--emit-nuch`, REPL echo, macro expansion printing.

**Gates.** `make`, `make test`, `make bootstrap` (stage1 = stage2),
`scripts/stage21/dump-ast-corpus.sh` byte-identical (the corpus has no commas,
`#_`, `#tag` or `\uXXXX`, and markers are invisible to the printer), `make
check-headers`. No boot refresh: `src/` does not use the new syntax.

**Tests** (`tests/suite-s22.nuc`, new, registered in `tests/nuctests.nuc`):
commas in each position (list, vector, map, between key and value); `#_` in
each position including nested `#_ #_ a b c` and inside a map; `#tag` on each
form kind and nested tags; each new error with its line; `\uXXXX` in strings and
chars, and the surrogate refusal; markers on each literal; EDN mode against
Nucleus mode for `&x`, `a:&b`, `a:(1)`, `'x`, `c"s"`, `1N`, `1.5M`, and a
`(def-rmacro …)` form that EDN mode must leave alone.

### ED-2 — `lib/edn.nuc`: reading and the view

Imports: `read node keyword string strview parse error` (model:
`lib/read.nuc`'s header and error boilerplate).

- **Errors.** `deferror`s `edn-type` (wrong kind), `edn-range` (does not fit),
  `edn-dup-key`, `edn-dup-elem`, `edn-bad-symbol`, plus reader errors passed
  through. `(defstruct EdnError code:Err line:i32 msg:StrView)` with
  `(defcast EdnError Err edn-error-code)`; results as hand-written
  `defunion`s, `EdnResult (ok v:?&Node) | (err e:EdnError)`, following
  `ReadResult` (a `(Result ?&Node E)` instance loses the nullable pointer kind,
  `docs/reading.md`). A `ReadError` converts to `EdnError` field for field.
- **Reading.** `read-edn (src:StrView):EdnResult` — exactly one form, trailing
  non-whitespace is an error; `read-edn-all (src):EdnResult` — every form, as a
  list. Both read in EDN mode and then **validate**: duplicate map keys and
  duplicate set elements (`node-eq` with markers compared, an O(n²) scan per
  collection — fine at configuration size), and symbols that are not legal EDN
  symbols (the reader accepts a wider set).
- **The view.** `(defenum EdnKind EDN-NIL EDN-BOOL EDN-INT EDN-FLOAT EDN-STR
  EDN-CHAR EDN-SYM EDN-KEYWORD EDN-LIST EDN-VECTOR EDN-MAP EDN-SET
  EDN-TAGGED)`; `edn-kind (n:?&Node):i32` classifies by node kind, the three
  reserved symbols, and the marker. Accessors, each returning `!T` and
  `edn-type` on the wrong kind: `edn-bool`, `edn-int` (i64), `edn-float` (f64,
  parsed from the node text; an EDN int is accepted), `edn-str` / `edn-sym-name`
  / `edn-keyword` (StrView / `Keyword`; interned, so valid for the process),
  `edn-char` (`Char`), `edn-count`, `edn-nth`, `edn-tag` / `edn-tagged-value`,
  `edn-map-get (m k):?&Node` (linear scan by `node-eq`) and a keyword
  convenience `edn-get (m kw:StrView)`. Iteration: lists and literal cells are
  `Seq` already (Stage 21 item 6); the view offers element iteration that skips
  a literal cell's head symbol, and pairwise iteration for maps.
- **`#inst` / `#uuid`.** Read and preserved as ordinary tagged values. No
  built-in conversion: Nucleus has no time or UUID type.

**Tests:** example golden `examples/edn-read.nuc` /
`tests/expected/edn-read.out` (read a config-like document, walk it, print
values); deftests for each `EdnKind`, each accessor's wrong-kind error, the
duplicate checks, `(vector-lit 1)` written as a list vs `[1]`.

### ED-3 — writer and scalar codecs

- **`edn-write (out:&String n:?&Node):!void`** — canonical single-line EDN for
  any view node: brackets from markers, EDN string escapes (`\uXXXX` for
  control characters), `\newline`/`\return`/`\space`/`\tab`/`\uXXXX` chars (a character outside
  the BMP is written as its UTF-8 text, since `\uXXXX` cannot spell it),
  `#tag v`, keywords with `:`, floats as their stored text (an `M` value prints
  with its `M`). `edn-str (n):String` wraps it. Pretty-printing is out of
  scope.
- **Scalar writers**, overloads `edn-write (out:&String v:T):!void` for i8–i64,
  ui8–ui64, f32, f64, bool, `Char`, `StrView`, `String` (via `&`), `Keyword`.
  Floats must print so they read back as floats (`1.0`, not `1`) and must
  round-trip (`%.17g` / `%.9g`, then add `.0` if the text has no `.`/`e`).
  EDN has no spelling for a non-finite value, so writing one is an
  `edn-range` error.
- **Scalar readers**, overloads `edn-read (dst:&T n:&Node):EdnResult` for the
  same types — the conformance rules:

  | EDN value | Accepted target | Rule |
  | --- | --- | --- |
  | int | any int width | range-checked; out of range is `edn-range` |
  | int | f32, f64 | converted |
  | float | f32, f64 | f32 narrowing allowed |
  | float | int | refused (`edn-type`) |
  | string | `StrView`, `String` | `StrView` borrows the interned text; `String` copies |
  | keyword | `Keyword` | |
  | char | `Char` | |
  | `true` / `false` | `bool` | |
  | `nil` | — | refused |

  These are useful on their own (`(edn-read &port (try (edn-get cfg "port")))`)
  and are what any struct derivation will call per field.

**Tests:** read → write → read round-trip over the ED-1/ED-2 corpus, compared
with `node-eq` **and** markers; every row of the conformance table, including
each range edge (i8 at 127/128, ui64 at max, f32 overflow).

### Checkpoint — after ED-3

Answer Q3–Q6 (§6) and Q8's follow-up with the scalar codecs in hand, then
write up ED-4 in its own document in this directory. **Done 2026-10-02:** Q3–Q6
are answered, Q8's follow-up is deferred within the stage, and ED-4 is in
[ed4-struct-codecs.md](ed4-struct-codecs.md).

### ED-4 — struct codecs

Designed 2026-10-02 and built 2026-10-03 in
[ed4-struct-codecs.md](ed4-struct-codecs.md) (ED-4.0 … ED-4.6). The parts:

- a `struct-fields` / `type-name` compiler primitive;
- macro-produced definitions registered as real methods
  ([macro-definitions.md](macro-definitions.md));
- an `EdnCodec` protocol, with `Vector`/`HashSet`/`HashMap` conformances;
- a `derive-edn` macro, for use in optional companion libraries;
- namespace-qualified tags.

### ED-5 — tests and examples

Land with each milestone (listed under each), not at the end. Also: commit
`lib/edn.nuch` / `lib/edn.h` (`headers-generated` audit); the `w9-lib-*` units
cover standalone compilation; the `reader-printer-roundtrip` audit reads every
new example and fixture. The golden `examples/edn-struct.nuc` landed with ED-4.

### ED-6 — docs and close-out

- New `docs/edn.md`; rows in `docs/index.md` (reference table and stdlib list).
- `docs/reading.md`: "What it reads" (commas, `#_`, `#tag`, `\uXXXX`, markers),
  EDN mode, the new error codes, the comma removed from the `def-rmacro` prefix
  bytes, and the stale claim that `()` reads as a null node (it reads as an
  empty, non-null list).
- `docs/collections.md` literal-sugar note; `docs/types.md` / `docs/builtins.md`
  wherever reader syntax is listed.
- `design/progress.md` narrative and status; this file's As built;
  `context/` if anything non-obvious turns up.

---

## 4. Sequencing

1. **ED-1** alone, with its gates — the only milestone that touches what the
   compiler reads.
2. **ED-2 → ED-3**, tests alongside.
3. **Checkpoint**: Q3–Q6 and Q8's follow-up (passed 2026-10-02).
4. **ED-4 → ED-6.**

---

## 5. Risks

- **The reader is the compiler's reader.** Every ED-1 change is a compiler
  change. Gate on the dump-ast corpus as well as bootstrap: a reader that
  changes the tree for existing source is a bug even if the compiler still
  converges.
- **`#` hygiene (§1.5).** If any synthesized `#name` is printed and re-read,
  ED-1 breaks it. The audit in ED-1 step 9 is the guard.
- **Interning (Q8).** Every string in an EDN document joins the process-lifetime
  symbol table. Fine for configuration, wrong for large or untrusted data.
  Recorded as the open half of Q8.

---

## 6. Questions

Each with options, tradeoffs, and the decision or its deferral.

**Q1. Where the new syntax applies.**
(a) Universal: one grammar, `#_` useful in source; costs `,` as a `def-rmacro`
prefix, a compiler diagnostic for `tagged-lit`, and the W5e fixture.
(b) EDN mode only: no compiler risk, two dialects.
**Decision: (a), universal.**

**Q2. Data model.**
(a) A view over `Node`: no copy, literally the reader's output; strings interned
forever, maps are linear, nothing owned.
(b) An owned `EdnValue` union over `Vector`/`HashMap`: needs `Hash`/`Eq` over a
recursive union — too much for a first pass.
**Decision: (a), a view over `Node`.**

**Q3. How struct codecs are derived.**
(a) A `defedn` wrapper macro: library-only, but structs must be defined through
it.
(b) A compiler primitive (`struct-fields`) so `(derive-edn Point)` works on any
struct: general, but a compiler and bootstrap change — the reflection item
deferred in `deferred/overview.md:144`.
**Decision (2026-10-02): (b).** It also gives a future or external library the
tools to derive a different serialization format. A walkable list of field
name/type pairs is enough. Derivation is explicit, so a type's codecs can live
in an optional companion library.

**Q4. How struct tags are spelled.** The EDN spec reserves tags without a
namespace prefix.
(a) Bare struct name `#Point`: simple, inside the reserved space.
(b) Qualified, with an optional `:tag`, defaulting to e.g. `nucleus/Point`
(a macro cannot learn the current `ns`).
(c) `:tag` always required.
**Decision (revised 2026-10-02): namespace-qualified.** The EDN spec requires
a prefix on user tags. A user type uses its own namespace (`#geom/Point`), and a
Nucleus builtin uses `nucleus/`. The macro cannot learn the namespace itself,
but the Q3 primitive can supply it: a struct's registry key is already
`<ns>/<bare>`. The first answer, the bare name, is superseded.

**Q5. Unknown and missing keys when reading a struct.**
Strict (both errors; catches config typos) vs. ignoring unknown keys (forward
compatibility).
**Decision (2026-10-02): strict.**

**Q6. Untagged nested maps.** Must a nested struct field carry its tag, as the
brief's "subsequent tagged maps" says, or may it be a plain map?
**Decision (2026-10-02): a plain map is a `HashMap`, a vector a `Vector`, a
set a `HashSet`; an anonymous struct (`(struct x:i32 …)`) takes a builtin tag.**
A named struct is always tagged. Keys may be any EDN value. Key types the
current `HashMap` cannot cleanly handle may be excluded for now.

**Q7. `N` / `M` suffixes.**
Accept when the value fits (keeping exact text in FLOAT nodes for a later
decimal type) vs. refuse.
**Decision: accept when the value fits.**

**Q8. Interning.**
Intern every string (simple; never freed) vs. a non-interning path for large
data (strings owned by the document or an arena).
**Decision: intern everything for now. Whether a non-interning option belongs
in Stage 22 is decided later, within the stage.**

---

## 7. As built (2026-10-02)

ED-1 … ED-3 landed as designed except where listed here.

**Names.** The reader's EDN entry points are `reader-edn` and `read-all-edn`
(the plan said `edn-reader` / `read-edn-all`); the library's are `edn-parse`
and `edn-parse-all`, so no `read-*` name is spelled two ways. The writer to a
fresh `String` is `edn-text`, because `edn-str` is the string accessor.

**One error type.** `lib/edn.nuc` reports through the reader's `ReadError` /
`ReadResult` rather than a parallel `EdnError`: the shapes were identical, and
the text-to-`Node` layer now has one error type. The scalar `edn-read`
overloads return `ReadResult` with `ok` carrying the value read, which also
settled §3's open question about a payload-less `ok` arm by not needing one.

**ED-1 details.**
- `#_` lives in `rd-skip-discard`, called where `rd-skip-ws` was in `rd-form`,
  `rd-list` and `rd-lit-elems`, and by `reader-eof?`, which restores the reader
  if a discard fails so `read-one` reports it. A `#_` before a closer or EOF is
  the new `read-bad-discard`.
- The mark is `(defenum LitMark LIT-NONE LIT-VECTOR LIT-MAP LIT-SET
  LIT-TAGGED)` on the cell's `i`.
- EDN mode's "`N` when the value fits" (Q7) is concrete: an EDN integer must
  fit a signed 64 bits, with or without `N` — the `ui64` widening Nucleus
  literals get is off. `M` **keeps** its suffix in the FLOAT text, so
  `edn-write` round-trips it (the plan said strip it).
- In EDN mode hex numbers and `+inf.0`/`-inf.0`/`+nan.0` read as symbols;
  `edn-parse` then refuses `0x10` as an illegal symbol.
- The compiler reserves `tagged-lit` and refuses it in `emit-list` (*"tagged
  literal '#inst' is data syntax: Nucleus source has no reader for it"*);
  `node-type` answers null for it. Manifest row `s22-tagged-lit-source`.
- W5e: `(ns #p1)` now fails in the reader; the manifest row expects
  `tagged literal '#p1' has no value` and the `ns` check stays.
- §1.5 audit: no committed `.nuch` or expected output contains a synthesized
  `#` name, and `--dump-ast` prints only what the reader built.

**ED-3 details.** A character outside the BMP is written `\u{…}`, not as UTF-8
text as planned: this reader reads a char literal's spelling as one atom, so a
multi-byte `\é` would not read back. Floats try `%.15g` and fall back to
`%.17g` (`%.7g` / `%.9g` for `f32`), adding `.0` when the digits would read
as an integer. `edn-eq` compares floats by their text and maps and sets in
written order.

**Gates.** `--dump-ast` over the 504-file corpus: 1,512 artifacts
byte-identical but for `w5e-ns-hash-reserved`'s three (by design, above).
`make check-headers` clean (89 headers, `lib/edn.nuch`/`.h` new). `make
bootstrap`: stage1 = stage2. `make test`: 1,246 passed, 5 failed — the five
`suite-target` datalayout units that fail in this container before the change
too (1,230 passed, 5 failed at the pre-change baseline).
