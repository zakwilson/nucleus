# Test reporting in EDN — plan

**Status:** built 2026-10-03 (§7, "As built"). Milestones TR-0, TR-1, TR-3,
TR-4, TR-5 (TR-2 was dropped by Q4). Q1–Q4 were decided by the user on 2026-10-03
(§5): all three formats, plain maps, `nil` for a missing location, and the
Makefile keeps its grep.

**The request:** the test suite reports results in a bespoke s-expression
format. Replace it with EDN, which Stage 22 built (`lib/edn.nuc`,
[overview.md](overview.md), [ed4-struct-codecs.md](ed4-struct-codecs.md)).

## 1. Ground truth (verified 2026-10-03)

Three formats share the same hand-rolled `(head (key value) …)` shape. They
were chosen together in Stage 18
([stage18-tooling/overview.md](../stage18-tooling/overview.md) §T8.5): "no new
format to specify, and `lib/read.nuc` reads both". That section also records the
cost: "tools that are not this compiler cannot read it without one" (§T9.3).
EDN removes that cost, since every EDN reader can read it.

| Format | Written by | Read by |
| --- | --- | --- |
| **Result records**, one per test on the runner's stdout | `test-report`, `lib/test.nuc:557` | The `run-nuctests` recipe (`Makefile:131-146`) greps the shards' concatenated output for `(status pass)`, `(status fail)` and `(status skip)`. No Nucleus code reads them. |
| **Compiler diagnostics**, `nucleusc --diagnostics=sexp`, one per line on stderr | `diag-render` / `diag-write-string`, `src/diagnostics.nuc:62-105`; selected by `g-diag-sexp`, flag at `src/nucleusc.nuc:20283` | `read-diagnostics`, `lib/test.nuc:410`, which keeps only lines starting with `(diagnostic `, then `diag-of-node` |
| **The rejection manifest**, 212 rows in `tests/manifest/diagnostics.sexp` | by hand | `register-manifest`, `run-reject-row` and `run-manifest-row` (`tests/nuctests.nuc:1485-1614`). It is also a prerequisite of the runner, `Makefile:121` |

The records today:

```
(test (name "substrings") (file "examples/self-test.nuc") (line 36) (status pass))
(test (name "…") (file "…") (line 89) (status fail) (message "expected to contain \"au revoir\"\n     in: hello, world"))
(diagnostic (severity error) (file "a.nuc") (line 12) (message "…") (notes "…" "…"))
(reject "s22-macro-dup-defn" (file "tests/fixtures/s22-macro-dup-defn.nuc") (line 8)
        (message "duplicate definition of 'area'"))
```

Other facts the plan depends on:

- **`sexp-quote`** (`lib/test.nuc:547`) wraps a `StrView` so that `str-into`
  writes it as a quoted string literal. Assertion messages use it: 24 sites in
  `lib/test.nuc` and 11 in `tests/`. It is a quoting style for people reading
  the message, not part of any record. Only its escapes depend on the format.
- **The compiler cannot import `lib/edn`.** `lib/edn`'s macros use
  `struct-fields`, which the boot compiler (`bin/nucleusc`) does not know. The
  compiler does not need it anyway: writing a diagnostic is string formatting.
  The ct-fault boundary (`src/ct-fault.nuc:68`) also requires `diag-render` to
  allocate nothing beyond its output buffer.
- **Escapes.** The diagnostic writer escapes `\0` and `\xHH`, which EDN does
  not have. `edn-write-string` (`lib/edn.nuc`) escapes `"`, `\`, `\n`, `\t`,
  `\r`, and every other control character as `\uXXXX`, which ED-1 taught the
  reader. Bytes 128 and above pass through unchanged in both writers.
- **The stream is mixed.** stderr carries `clang -E` output beside diagnostics,
  so a diagnostic must be recognizable from the start of its line.
  `read-diagnostics` already skips any line that is not one.
- **Consumers to migrate:**
  - 18 `--diagnostics=sexp` command sites: `nuctests` 9, `suite-target` 5,
    `suite-audits` 3, `suite-s21` 1;
  - the `s18-diagnostics-sexp` audit and its round-trip sibling,
    `tests/suite-audits.nuc:359` and `:411`;
  - the canned compiler stderr in `examples/self-test.nuc:65-69`;
  - the goldens `tests/expected/self-test.out`;
  - `docs/testing.md`, `docs/compiler.md` (`:22`, `:63`) and `context/build.md`.
  - Older design documents also mention the format. They are records of their
    time and are left alone.

## 2. Shapes

Each record is one EDN map, on one line, with its keys in a fixed order. The
key that tells you what a record is comes first.

**Result record:**

```
{:status :pass :name "substrings" :file "examples/self-test.nuc" :line 36}
{:status :skip :name "…" :file "…" :line 86 :message "no oracle for hello, world on this host"}
{:status :fail :name "…" :file "…" :line 89 :message "expected to contain \"au revoir\"\n     in: hello, world"}
```

- **`:status` comes first.** The summary can then count lines beginning with
  `{:status :pass ` and know it has counted records. Today's
  `grep -cF '(status pass)'` also counts a failure whose message happens to
  contain that text.
- **`:name` is a string.** A test name built from a manifest row or a file name
  need not be a legal EDN symbol.
- **`:message` is present** only for `:skip` and `:fail`, exactly as now.

**Diagnostic:**

```
{:severity :error :file "a.nuc" :line 12 :message "get: no field 'z' on struct 'Pt'" :notes []}
{:severity :error :file nil :line nil :message "clang: …" :notes []}
```

- **A missing location is `nil`**, not `""` and `-1` (Q3). This keeps the
  conventions' rule that absence is written out, never omitted.
- **`:notes` is always a vector**, possibly empty.
- **`read-diagnostics` keeps lines that begin with `{:severity `.** A tool's
  output can still go to the same stream.

**Manifest row** (TR-4):

```
; Stage 22 ED-4.1: …rationale, carried over verbatim…
{:name "s22-macro-dup-defn" :expect :reject
 :file "tests/fixtures/s22-macro-dup-defn.nuc" :line 8
 :messages ["duplicate definition of 'area'"]}
{:name "s21-frame-discharge-accepts" :expect :accept
 :file "tests/fixtures/s21-frame-discharge-accepts.nuc"}
```

- **Optional keys:** `:line` (absent means not pinned), `:messages` and
  `:notes`.
- **Strict otherwise:** a row with an unknown key, or a `:reject` row with no
  `:messages` and no `:notes`, fails to register, naming the row's line.
- **Read through the `lib/edn` view** (`edn-get` and friends), not
  `derive-edn`: derived codecs are strict and have no optional fields
  (ed4-struct-codecs.md §4).
- **Comments and `#_` work.** `;` rationale blocks carry over unchanged, and
  `#_` disables a row without deleting it.

## 3. Milestones

### TR-0 — ground truth

Quick probes in the scratch tree; record the answers here.

1. `lib/test.nuc` importing `lib/edn`: `build/nuctests` and
   `examples/self-test.nuc` still build. Measure the change in the runner's
   build time.
2. Every byte 0–255 in a message survives `edn-write-string` → `edn-parse`
   unchanged. The compiler-side writer (TR-3) must produce the same bytes.
3. `edn-parse`, one line at a time, reads a full run's records (about 1,300
   lines) in reasonable time. Every string is interned (Q8), which is fine at
   this size, but measure it.

### TR-1 — result records (`lib/test.nuc`, `Makefile`)

- **Writing.** `test-report` writes §2's record, using `lib/edn`'s writers
  (`edn-write` for `StrView` and `Keyword`). `lib/test.nuc` gains
  `(import-use edn)`.
- **`sexp-quote` becomes `quoted`.** It is a format-neutral name, rendered with
  EDN escapes. All of its ~35 call sites and the `SexpStr` struct (renamed `Quoted`)
  change with it; `docs/testing.md:394` lists the name.
- **The summary.** `run-nuctests` counts `^{:status :pass ` and the other two
  verdicts with `grep -c`, and prints failing and skipped records exactly as
  now (Q4).
- **Goldens.** Regenerate `tests/expected/self-test.out`.
- **Test:** a unit that runs a two-test suite (one pass, one failure whose
  message contains a quote, a newline and `{:status :pass `), reads its stdout
  back with `edn-parse`, and checks the fields and the summary count.

### TR-2 — dropped

A `--summarize` verb that parsed records for the `make test` summary. Q4 kept
the Makefile's grep instead (§5).

### TR-3 — diagnostics (`src/diagnostics.nuc`, `lib/test.nuc`)

- **The flag.** `--diagnostics=edn` replaces `--diagnostics=sexp`, and `sexp`
  is removed outright, since pre-release needs no compatibility. `g-diag-sexp`
  becomes `g-diag-edn`.
- **The writer.**
  - `diag-render` writes §2's map. It is still one line and still allocates
    nothing beyond `out`.
  - `diag-write-string` switches to EDN escapes: `\uXXXX` for every control
    character, including NUL, in place of `\0`/`\xHH`.
  - Severity becomes a keyword; a missing location becomes `nil`.
- **The reader.**
  - `read-diagnostics` keeps lines starting with `{:severity ` and parses each
    with `edn-parse`. `diag-of-node` reads its fields with `edn-get`.
  - `Diagnostic.severity` becomes a `Keyword`, and the check helpers compare
    keywords.
  - A malformed line that does start with `{:severity ` is still an error, as
    a malformed `(diagnostic ` line is now.
- **Callers.**
  - The 18 command sites change their flag.
  - `s18-diagnostics-sexp` becomes `s18-diagnostics-edn`, with the golden line
    rewritten. Its round-trip sibling switches to `edn-parse` and gains a NUL
    and a control byte in the message.
  - The canned stderr in `examples/self-test.nuc` is rewritten.
- **Docs:** `docs/compiler.md` (the flag table and "Structured diagnostics")
  and `docs/testing.md` ("Compiler diagnostics").

### TR-4 — the manifest (`tests/manifest/diagnostics.edn`)

- **Convert the 212 rows** with a throwaway program in the scratch tree:
  - read the old file with `read-all`;
  - write §2's maps;
  - carry each row's `;` block across by its line span;
  - check that the converted file registers the same 212 names with the same
    fields.

  The program itself is not committed.
- **The runner.**
  - `register-manifest` reads the new file with `edn-parse-all`.
  - `run-reject-row` and `run-accept-row` read `:file`, `:line`, `:messages`
    and `:notes`.
  - The strict-row check from §2 runs at registration, so a malformed row
    fails the build of the test list, not one test.
- **The `Makefile:121` prerequisite and `manifest-path`** point at
  `diagnostics.edn`; the old file is deleted.
- **Test:** a malformed row (an unknown key, or a `:reject` with nothing to
  match) is refused at registration with its line. To keep the real manifest
  clean, this runs on a scratch file.

### TR-5 — docs and close-out

- `docs/testing.md`:
  - "Reporting": the records, the `:status`-first rule, and reading them back
    with `lib/edn`;
  - the manifest section;
  - `quoted`.
- `context/build.md`: `build/nuctests.out` is EDN, and how to grep it.
- `design/stage18-tooling/overview.md` §T8.5 gets a one-line note that Stage
  22 replaced the s-expression formats with EDN, linking here.
- `design/progress.md`, `design/overview.md`, and this file's "As built".

**Gates, at every milestone:**

- `make test`. The number of tests is unchanged (1275 now, plus the new units).
  TR-1 moves no verdict and TR-4 registers exactly the same names.
- `make bootstrap`. TR-3 is the only compiler change.
- `check-headers`. `lib/test.nuch`/`.h` change with TR-1 and TR-3.
- The dump-ast corpus: only edited sources differ, plus the new manifest file.

## 4. Order

TR-0 → TR-1 → TR-3 → TR-4 → TR-5. TR-1 is
independent of the compiler and can be built and checked on its own. TR-3 must
change the compiler and its readers in one step, because the flag is a contract
between them.

## 5. Decisions (2026-10-03, by the user)

| Q | Decision | What it rules out |
| --- | --- | --- |
| Q1 — scope | **All three:** result records (TR-1), compiler diagnostics (TR-3), and the rejection manifest (TR-4). | Keeping an s-expression reader in the suite for any of them. |
| Q2 — shape | **Plain maps**, recognized by their first key (`:status`, `:severity`). | Tagged records (`#nucleus/test-result {…}`), which an outside EDN reader rejects without a handler. |
| Q3 — no location | **`:file nil :line nil`.** | `""` and `-1` as part of the format. |
| Q4 — summary | **Keep the Makefile grep,** counting lines that begin `{:status :pass ` (and `:fail`, `:skip`). The key order makes the count exact. | TR-2's `--summarize` verb. |

## 6. Risks

- **Bytes that are not UTF-8.** EDN text is UTF-8. A message that quotes a
  stray byte (a C header, a binary fixture) passes through as-is in both
  writers today, so the record would not be valid EDN to an outside reader.
  Our reader accepts it.
  - Escaping invalid sequences as `�` would lose the byte.
  - Leave it unchanged; TR-0 item 2 records what happens.
- **`lib/test` now depends on `lib/edn`,** and through it on the collection
  libraries. A suite with an `edn-*` name of its own now collides. TR-0 item 1
  checks the cost; the collision is ordinary namespace hygiene and is
  documented.
- **Interning.** `edn-parse` interns every string (Q8). For a full run's
  records and every diagnostic a test reads, that is a few megabytes in a
  short-lived process. Acceptable; revisit with the deferred non-interning
  reader.

## 7. As built (2026-10-03)

**TR-0 answers.**
1. `build/nuctests` already linked `lib/edn` through `tests/suite-s22.nuc`, so
   it costs the runner nothing. `examples/self-test.nuc` builds in 1.27 s
   instead of 1.08 s, and its binary grows from 219 KiB to 240 KiB.
2. All 256 byte values survive `edn-write-string` → `edn-parse`. Bytes of 0x80
   and above pass through raw (§6), and the compiler's `diag-write-string`
   now escapes exactly as `edn-write-string` does.
3. 1,300 records parse in 11 ms. **An empty last line fails `edn-parse`**
   (`edn-no-value`), so every reader keeps lines by prefix (`{:status `,
   `{:severity `) rather than parsing every line.

**As planned, with these specifics:**
- **TR-1.** `lib/test.nuc`'s `quoted` (was `sexp-quote`) wraps
  `edn-write-string`. `s22-test-records` builds a two-test suite whose failing
  message contains a quote, a newline and `{:status :pass `, parses every
  record, and checks that the line-start grep counts one pass.
- **TR-3.**
  - `--diagnostics=edn` replaces `sexp`; `g-diag-edn` replaces `g-diag-sexp`.
  - `Diagnostic.severity` is a `Keyword`. The check helpers keep taking the
    severity as a `StrView` and compare `keyword-name`.
  - A `nil` `:file` or `:line` reads back as `""` or `-1`. A row that lacks
    either key is refused.
  - `s18-diagnostics-edn`'s round trip uses a path holding `"` and byte 0x01.
    **NUL is not covered end to end,** because no filename or message can
    carry one to the compiler. The escaper's NUL arm is the same `\u00XX`
    arm as every other control byte.
- **TR-4.**
  - The 212 rows were converted by a throwaway script that also asserted every
    row's shape. The converted file registers the same 212 names.
  - `manifest-rows` (`tests/nuctests.nuc`) parses with `edn-parse-all` and
    runs `row-check` on every row before any is registered.
    `s22-manifest-row-refused` drives its seven refusals from strings, not a
    scratch file.
  - A registration failure now prints the failure text, not "assertion
    failed".
  - **A manifest test's record carries its row's line** (it was 0), so a
    failing row is located in `diagnostics.edn`.
- **TR-5.** Docs: `docs/testing.md`, `docs/compiler.md` and `docs/macros.md`.
  Context: `context/build.md` and `context/conventions.md`. Stage 18 §T8.5
  is marked superseded.

**Gates:**
- `make test`: 1277 passed, plus the 5 known LLVM-22 data-layout failures.
- `make bootstrap`: PASS.
- `check-headers`: clean (89 headers).
- The previous and new compilers emit identical IR for 211 inputs.
- dump-ast corpus: only the edited sources and `w5e-ns-hash-reserved` differ.
