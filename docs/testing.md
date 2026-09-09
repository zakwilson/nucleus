# Testing

`lib/test.nuc` — declare tests, assert, and report.

A test suite is an ordinary Nucleus program. `deftest` registers each test before
`main` runs, so `main` is one call to `test-main`, and the binary answers
`--list`, `--run <name>`, or no arguments at all.

```lisp
(import-use error)
(import-use strview)
(import-use string)
(import-use io)
(import-use test)

(deftest greeting-is-friendly
  (try (check-contains (greeting) "hello"))
  (try (check-not-contains (greeting) "goodbye")))

(defn main (argc:i32 argv:ptr):int
  (return (as int (test-main argc argv))))
```

```
$ ./suite
(test (name "greeting-is-friendly") (file "suite.nuc") (line 7) (status pass))
```

See `examples/self-test.nuc` for a worked suite, two of whose tests do not pass
on purpose so the output shows what a skip record and a failure record look
like.

## Declaring

| Form | Meaning |
| --- | --- |
| `(deftest name body…)` | A test named `name`, run in registration order. |
| `(test-main argc argv)` | The suite's `main`: `--list`, `--run <name>`, or all. |
| `(skip! parts…)` | End the test as **skipped**, with a reason. |

`deftest` takes a bare symbol, not a string. The body is a function body
returning `!void`, which is why each assertion is wrapped in `try`: the first
failure ends the test, and nothing after it runs. That is the point of the
`!void` shape — a hand-rolled `ok=1 … || ok=0` accumulator passes
unconditionally the one time you forget to write it.

The file and line in a record come from `(source-file)` and `(source-line)`,
which resolve at the `deftest` call site rather than inside the macro.

## Skipping

A test whose subject is not present to be tested — a host without the C
compiler an oracle needs, a toolchain feature the compiler probes for — ends
with `skip!`:

```lisp
(deftest layout-matches-cc
  (when (not (try (have-cc?))) (skip! "needs a host C compiler"))
  …)
```

A skip is a **third verdict**, not a quiet pass. It emits its own record with
its reason, it is counted separately, and the run still exits 0 for it:

```
(test (name "…") (file "…") (line N) (status skip) (message "…"))
```

The reason is required, for the same reason a failure's is: a skip nobody can
read is attrition nobody can audit. `make test` prints every skip line and ends
with `N passed, M failed, K skipped`.

**`--no-skip` turns every skip into a failure**, for a run that will not accept
one — a release check, or a machine that is supposed to have the whole
toolchain. The record becomes a `fail` whose message is `skipped: <reason>`, so
what was skipped is still legible. It is a policy flag, not a mode, so it
composes with `--list` and `--run`:

```
$ ./build/nuctests --run layout-matches-cc --no-skip
$ make run-nuctests NUCTESTS_ARGS=--no-skip
```

## Asserting

Every predicate returns `!void` and every one renders its own failure text, so a
`try` is all a call site needs.

| Assertion | Passes when |
| --- | --- |
| `(check-contains hay needle)` | `needle` occurs anywhere in `hay`. |
| `(check-not-contains hay needle)` | it does not. |
| `(check-line hay want)` | some line of `hay` is exactly `want`. |
| `(check-eq got want)` | the two views are equal. |
| `(check-eq-int got want what)` | two `i64`s are equal; `what` names the quantity. |
| `(check-match hay pat)` | some line of `hay` matches the glob `pat` in full. |
| `(check-not-match hay pat)` | no line does. |
| `(check-empty s)` | `s` has no bytes. |
| `(check-non-empty s)` | `s` has some. |
| `(check-golden got want)` | two blobs are identical; names the first differing line. |
| `(check-files-eq a b)` | two files have identical contents. |
| `(check cond what)` | `cond` is true; the escape hatch for the rest. |

In a glob, `*` stands for any run of bytes and `?` for any single byte. A glob
matches a **whole line**, so `"define i32 @add(*)*"` is anchored at both ends —
which is what makes it an assertion rather than a search.

`(read-file path)` returns `!String` and is the usual way to get a haystack.

### IR assertions

A compiler test asserting about generated IR usually means "inside *this*
function", and a search over the whole module cannot say that: `ret void` is in
the module whenever any function returns void.

| Assertion | Passes when |
| --- | --- |
| `(check-in-define module fname pat)` | a line of `@fname`'s `define` block matches `pat`. |
| `(check-not-in-define module fname pat)` | none does. |
| `(ir-define module fname)` | `(Maybe StrView)` — the block itself. |

## Compiler diagnostics

`nucleusc --diagnostics=sexp` writes each diagnostic as an s-expression rather
than as text ([Structured diagnostics](compiler.md#structured-diagnostics)).
`read-diagnostics` reads them back, and the assertions then compare **fields**.

```lisp
(let (ds:(Vector Diagnostic) (try (read-diagnostics stderr-text)))
  (try (check-error-at (addr-of ds) "x.nuc" 12 "no field 'z'"))
  (try (check-note-at  (addr-of ds) "x.nuc" 12 "did you mean")))
```

| Form | Meaning |
| --- | --- |
| `(read-diagnostics text)` | `!(Vector Diagnostic)` — every diagnostic in `text`, which may be raw stderr. |
| `(check-error-at ds file line needle)` | An `error` at exactly `file:line` whose message contains `needle`. |
| `(check-warning-at ds file line needle)` | The same for a `warning`. |
| `(check-note-at ds file line needle)` | A diagnostic at `file:line` with a note containing `needle`. |
| `(check-error-anywhere ds needle)` | Some `error` contains `needle`; no location pinned. |
| `(check-note-anywhere ds needle)` | Some note contains `needle`; no location pinned. |
| `(check-no-errors ds)` | No diagnostic has severity `error`. |
| `(check-no-line-zero ds)` | No diagnostic reports line 0. |
| `(check-diagnostic ds severity file line needle)` | The general form the located three call. |

A `Diagnostic` has `severity` (a `Symbol`), `file`, `line`, `message`, and
`notes` (a `(Vector StrView)`).

The point of matching four fields against one record is that **the alternative
cannot express the assertion at all.** Grepping stderr for a location and then
grepping it again for a message never checks that the two came from the same
diagnostic — and notes carry locations too, so a note can satisfy the location
probe while the error says something else somewhere else.

`read-diagnostics` skips any line that is not a diagnostic, so the raw stderr of
a compile that also invoked another tool can be handed to it unfiltered.

## Data-driven tests

`deftest` names one test in source. When a suite's tests differ only in their
data — the same assertion over a hundred fixtures — register them from a table
instead, with `test-add`:

```lisp
(defn run-row (data:ptr):!void
  (let (row:raw:Node (unsafe/cast raw:Node data))
    …))

(test-add name file line run-row row)
```

`test-add` takes the name as a `StrView`, so it can come from a file, and the
`data` pointer is handed back to the function as its argument. A `deftest`
registers through the same path and ignores the argument.

A table is not the only source. `tests/nuctests.nuc` also registers a test per
`examples/*.nuc` that has a golden file, and per `tests/repl/*.in`, by walking
the directory with `read-dir` — so a new example is a new test with no edit
anywhere.

`tests/nuctests.nuc` is the worked example: it reads
`tests/manifest/diagnostics.sexp` with `lib/read.nuc` and registers one test per
row. Each row names a fixture, an optional line, and the messages and notes the
compiler must produce for it — the whole of the compiler's rejection suite as
data rather than as control flow.

## Source fixtures

A test whose subject is *the compiler* usually varies one line of a small
program. Writing a hundred of those as files is unreadable; a string literal in
Nucleus may span lines, so the program goes in the test:

```lisp
(deftest bool-is-not-an-integer
  (try (check-source-rejects
         "(defvar g:bool 1)
(defn main ():i32 (return 0))
"
         "defvar: integer literal incompatible with type bool")))
```

`tests/nuctests.nuc` defines these over `lib/process.nuc`; they are the suite's,
not the library's, because they run `./build/nucleusc`.

| Form | Meaning |
| --- | --- |
| `(compile-source src)` | `!Compiled` — `ok?`, `ir`, `raw` stderr, and `diags`. |
| `(compile-path path)` | The same for a file. |
| `(check-source-rejects src needle)` | The compile must fail, and some error must contain `needle`. |
| `(check-file-rejects dir path needle)` | The same for a file, resolving imports under `-I dir`. |
| `(check-source-accepts src)` | The compile must succeed with no diagnostic at all. |
| `(source-compiles? src)` | `!bool` — whether it compiled, for a table whose rows differ in the answer. |
| `(source-ir src)` | `!String` — the emitted IR; fails if the compile did. |
| `(source-cheader src)` | `!String` — the generated C header. |
| `(build-run-source src)` | `!String` — compile, run, stdout and stderr on one stream. |
| `(check-source-exit src n)` | Compile, run, and require exit status `n`. |
| `(check-file-exit dir path n)` | The same for a file, resolving imports under `-I dir`. |

Every fixture is written to the same `t.nuc`, so two programs compiled this way
differ only where they *should*: `; ModuleID`, `source_filename` and the C
header's `/* Generated from` banner are already equal, and `check-golden` can
compare two whole artifacts rather than two filtered ones.

A unit that exports a `.nuch` and imports it from a second file needs an
include directory, and one about the REPL needs a session:

| Form | Meaning |
| --- | --- |
| `(compile-path-in dir path)` | `!Compiled`, resolving imports under `-I dir`. |
| `(compiled-ir c)` | `StrView` over a `Compiled`'s emitted IR. |
| `(scratch-file name)` | `!String` — where a fixture written by `compile-source` and friends lands, for pinning the `file` field of a diagnostic about it. |
| `(check-ir-parses ir)` | The module must pass `llvm-as`. |
| `(opt-o2 stem ir)` | `!String` — the module after `opt -O2 -S`. |
| `(emit-for-file dir flag path)` | `!String` — stdout of `nucleusc [-I dir] flag path`. |
| `(compile-object path out)` | `!void` — `nucleusc -c path -o out`, for a real link. |
| `(compile-object-in dir path out)` | The same, resolving imports under `-I dir`. |
| `(cc-link-run idir parts)` | `!String` — build the space-separated `.c`/`.o`/`.ll` paths with `clang -Wall -Werror [-I idir]` and run the result. |
| `(cxx-link-run idir parts)` | The same through `c++`, for a header read behind `extern "C"`. |
| `(link-run parts)` | `cc-link-run` with no include directory. |
| `(write-into dir name content)` | `!String` — write into a subdirectory of the scratch tree; yields the path. |
| `(emit-into idir flag src dir name)` | `!String` — `nucleusc [-I idir] flag src` written to `dir/name`. |
| `(build-run-file dir extra path)` | `!String` — build `path` under `-I dir` with one extra argument, and run it. |
| `(repl-session text)` | `!String` — `text` is `nucleusc -i`'s stdin, the transcript is the answer. |
| `(line-with hay needle)` | `!StrView` — the first line containing `needle`. |
| `(count-lines-with-prefix hay prefix)` | `i64` — how many lines begin with `prefix`. |
| `(duplicate-type-name ir)` | `StrView` — a `%Name = type` defined twice, or `""`. |
| `(check-same-decl-set a b)` | Two modules carry the same `type`/`define`/`declare` lines, as a set. |

A unit whose claim is *what the platform C compiler does* needs clang's own
answer, and a claim about another machine needs `nucleusc` pointed at it:

| Form | Meaning |
| --- | --- |
| `(cc-emit-llvm path)` | `!CcIr` — `ok?`, `ir` and `err` from `clang -S -emit-llvm -O0 -w` on a C file. |
| `(cc-syntax-only-for target path)` | `!CcCheck` — `ok?` and `err` from `clang --target=<target> -ffreestanding -fsyntax-only`. |
| `(cc-compile-strict path)` | `!CcCheck` — the same, from `clang -std=gnu11 -Wall -Wextra -Werror -c … -o /dev/null`. |
| `(cc-run-file idir path)` | `!String` — build a C program with `cc [-I idir]` and run it; stdout is the answer. |
| `(cc-syntax-only-in idir path)` | `!CcCheck` — `clang -fsyntax-only [-I idir]`, for a claim whose answer is "it does not compile". |
| `(have-program? name)` | Whether `name` is on PATH, asked by running it. |
| `(have-cc?)` / `(require-cc)` | Whether `cc` is on PATH; the second `skip!`s when it is not. |
| `(have-cxx?)` | The same for `c++`. |
| `(compile-path-for target path)` | `!Compiled`, under `--target=<target>`. |
| `(check-emit-rejects flag path needle)` | `nucleusc <flag> <path>` must fail, with `needle` in some error. |
| `(nm-defined path)` | `!String` — the global symbols an object file defines, one per line. |

clang is not optional — `nucleusc` uses it as the default linker driver — so a
missing clang is a broken toolchain rather than something to skip over. What is
conditional is narrower: whether a particular clang's target *has* `_Float16`
or `__float128`, which `tests/suite-float.nuc` asks by compiling a two-line
probe and answers with `skip!`. `cc` **is** conditional — nothing in the build
needs it — so a unit whose oracle is the platform compiler starts with
`(try (require-cc))`.

`cc-syntax-only-for` is what makes a machine this one cannot execute testable:
`_Static_assert`s over sizes read back out of a cross-compiled module are a
complete `sizeof`/`offsetof` oracle with no sysroot, no link and no run.
`check-emit-rejects` reaches the refusals `--emit-llvm` never can, since
`--emit-cheader`'s fire while rendering the header.

A test that writes a header and a C consumer of it side by side must
`#include` the header by **base name**: a quoted include resolves from the
including file's own directory, and the path `test-write-file` hands back is
relative to the project root, which is where `nucleusc` resolves an
`import-use` from.

`check-ir-parses` exists because `--emit-llvm` never reads back what it writes:
exiting 0 says the compiler produced text, not that the text is a valid module.
`opt-o2` answers the one question a function attribute raises — whether it
changes what the optimizer does — and its assertions want a negative control,
since "`-O2` did not tail-call this" also holds on an `-O2` that tail-calls
nothing.

An empty `dir` or `extra` contributes no argument. `line-with` is for a claim
about one instruction: `i8 %` is in every module, so `check-not-contains` over
the whole IR asserts nothing. `count-lines-with-prefix` is for a claim that
something is emitted *once* — a presence test cannot catch a double emit.

`link-run` is what tests a `.nuch`. A unit that compiles the library and its
consumer together proves nothing about the header: the compiler has seen the
source either way. Compiling the two separately and linking makes the LINKER
resolve the symbol, so the claim is that the header promised the name the
library actually exports — and a wrong answer is an undefined reference rather
than a silently different program.

A generated **C** header is the same argument one step further out, which is why
`cc-link-run` is strict: reading the header cannot tell a correct `asm` label
from one naming a symbol no object defines, and a header that merely parses can
still disagree about layout. Build a C consumer, link it against the real
object, and read what it prints. `nm-defined` is the independent witness for the
half a consumer cannot reach — that the C identifier and the ELF symbol really
are different strings.

`(test-scratch-sub name)` makes a subdirectory of the test's scratch directory
and yields its path. A unit that exports a `.nuch` needs one: `resolve-import`
tries `.nuc` in every search directory before any `.nuch`, so the source has to
sit outside them or the header is never read.

Each test gets its own scratch directory, `build/out/nt/<test-name>`, made on
first use. `--run <name>` therefore reproduces exactly the files the full run
made, and no two tests can collide.

| Form | Meaning |
| --- | --- |
| `(test-scratch)` | `!StrView` — this test's directory, created if needed. |
| `(test-write-file name content)` | `!String` — writes into it, yields the path. |

## Failing

Failure text is written in one place — the assertion — and never at the call
site. To write an assertion of your own, use `fail!`:

```lisp
(defn check-sorted ((v (ref (Vector i64)))):!void
  (let (i:usize 1)
    (while (< i (count v))
      (when (< (invoke v i) (invoke v (- i 1)))
        (fail! "not sorted at " i ": " (invoke v (- i 1)) " > " (invoke v i)))
      (set! i (+ i 1))))
  (return (ok)))
```

`fail!` renders its pieces with `str-into` and returns `(err! test-failed)`, so
it is a `return`: nothing after it in the assertion runs. Pieces are anything
with a `ToStr` conformance. `(sexp-quote s)` renders a `StrView` as a quoted
s-expression string, and `(test-show s)` truncates a long haystack to 400 bytes,
which is enough to recognise what was actually there.

A test that returns an error which is *not* an assertion failure — a file that
would not open, say — still produces a failure record, naming the error.

## Reporting

Every run emits one record per test, on stdout, one line each:

```
(test (name "…") (file "…") (line N) (status pass))
(test (name "…") (file "…") (line N) (status fail) (message "…"))
(test (name "…") (file "…") (line N) (status skip) (message "…"))
```

The record is an s-expression, so `lib/read.nuc` reads it back: a tool that
collects results across suites parses them rather than scraping them. Strings are
escaped, so a message containing a quote or a newline survives the round trip.

`test-main` exits 0 when everything passed or skipped and 1 when anything
failed; under `--no-skip` a skip is one of the things that failed. `--list`
prints one name per line, which is what a parallel runner needs to shard a
suite; `build/nuctest` drives the shell suite through the same two-verb
interface.
