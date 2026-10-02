# Stage 21 — cleanup

**Status:** opened 2026-09-16. Item 8 designed and built 2026-09-28 (1,211 tests). Item 7 designed and built 2026-09-26 (1,192 tests, boot refreshed). Earlier items designed and built (item 2 on 2026-09-18, items 1 and 3 on 2026-09-19, item 4 on 2026-09-21, item 5 on 2026-09-22).

**Goal.** Close the deferred items and rough edges the prior stages left behind
— the ones recorded in [deferred/overview.md](../deferred/overview.md) and the
ones nobody wrote down. Each item gets its own document here, its own gates, and
a move from `deferred/overview.md` to [deferred/done.md](../deferred/done.md)
when it lands. The stage has no single feature; its deliverable is a tree with
fewer "convention, not a rule" edges in it.

## Items

1. **Pointer-kind and type-sigil spellings** — **built 2026-09-19** (PK-1 … PK-4a, PK-5a, PK-5b 2026-09-18; PK-4b and PK-6 2026-09-19) —
   [pointer-kind-spellings.md](pointer-kind-spellings.md) (designed 2026-09-16,
   PK-1 … PK-6). `&` becomes `ref` in both the type and the value world, so a
   standalone `&T` is the same node the type path already canonicalises and
   `--emit-nuch` stops printing `addr-of` into committed headers; the
   colon-paren fuse gates on an *open* final chain segment and moves into
   `rd-form` (PK-2, made once in `lib/read.nuc`), so `?(Vector i32)`, `!(…)`,
   `?!(…)`, `&?(…)` *read* as `(? (Vector i32))` etc. in every position (before,
   the paren form dangled as a sibling in all of them); a bare-sigil head `(? X)` is the
   canonical list form (PK-3: the type parser reads it as `?X`, exports it
   structurally, and names the `? (V)` space near-miss at the form's line); the
   generic-pattern walkers learn that a sigil over a concrete type is concrete
   (PK-4a: closes the soundness hole where `(Vector i32)` was accepted for
   `(Vector ?Pt)`, and with it the value-position `q:?&Pt` annotation; a sigil
   over a real tyvar is refused until PK-4b); after one boot refresh a paren-aware sweep
   script (`scripts/stage21/sugar-sweep.py`, eight rules, refuses what it
   cannot classify) retires `addr-of` and adopts the sugar across `src/`,
   `lib/` and `examples/`, gated byte-identical by `ir-snapshot.sh` (PK-5a);
   then the compiler stops reading `addr-of` at all (PK-5b): the four
   cell-building sites mint `ref`, every reading arm is gone, the name stays
   reserved and answers `'addr-of' was retired: write &x, or (ref x) /
   (ref p 'field)` on the value path, in `gcheck`, and from the type parser's
   fall-through, and `tests/` was swept with R1/R2 (`--rules`). Then a sigil
   over a type *variable* is a wrapper under every spelling (PK-4b, built
   2026-09-19): one `sigil-split` feeds eight pattern walkers, the substituter
   strips the run per colon segment, the cheader classifiers read the cell,
   the sweep's paren-operand refusal is lifted; its tyvar refusal stayed until
   the boot carried PK-4b, because the boot compiler builds `nucleusc` from the
   `lib/` files those sites live in (pointer-kind-spellings.md §6 "as
   built"; lifted and swept 2026-09-23). PK-6 (built 2026-09-19, §8 "as built") closes the item with no
   compiler change: `examples/type-sugar.nuc` is the §1.1 matrix as one golden
   (two rows excluded for the lambda-return and `defunion`-arm defects below;
   both went back in when those defects were fixed, 2026-09-23),
   four units that no earlier milestone had pinned (`s21-matrix-compiles`,
   `s21-nuch-roundtrip`, `s21-ir-identical`, `s21-match-ref-binder`), and the
   docs table audited row by row. The item moves to
   [deferred/done.md](../deferred/done.md); the boot-gated `lib/` re-sweep, its
   one loose end, was done 2026-09-23 (progress.md).
2. **There are two readers** — **built 2026-09-18** —
   [one-reader.md](one-reader.md) (designed 2026-09-16, R-1 … R-4).
   `lib/read.nuc` and `src/reader.nuc` contain significant duplicated work
   and maintaining both is technical debt. It should not be necessary for both
   to exist; if it is, that points to a deficiency in the language or compiler
   deserving its own item or stage depending on scope. Verdict: it is not
   necessary. What kept them apart was a structural habit (reader state in five
   globals, saved and restored by hand at every nested read), a premise false
   since Stage 16 (type inference in the reader — collection literals are
   typed at emit), a feature registered in the wrong place (`def-rmacro`
   extends the table from the emitter, after the file is read, so it never
   affected its own file — fixed by registering while reading, file-scoped and
   forward-only, ~40 lines in the reader), and a misreading of the error
   model — `Err` is an `i32` code, but the language already has a payload tier:
   `(Result T E)` admits any `E`, and a `defcast E Err` lets `try` propagate
   such a value into a plain `!T` caller unchanged (probed; no compiler change).
   So the reader returns `(Result raw:Node ReadError)` with the line, message
   and note in the value; the alternatives — side fields on the `Reader`
   (errno with an object) and a fat `Err` (spends the C enum and the `ERR_PTR`
   niche, adds an ownership burden) — are weighed and rejected in one-reader.md
   §2.1. The library reader gains collection literals (no gensym element), W4c
   bracket tracking and the typed error; the compiler adopts it through one
   shim that renders the error via `report-at` and mints the literal gensyms
   in the reader's own post-order, so
   every emitted `.ll` is byte-identical and no boot refresh is needed;
   `src/reader.nuc` is deleted, its diagnostics layer moves to
   `src/diagnostics.nuc` (macro bodies still cannot call it), `def-rmacro`
   starts working, the 4095-byte string-literal cap goes, and the four parity units
   become one read → print → read round-trip unit. **As built**: the error
   value shipped as a hand-written `ReadResult` union rather than a
   `(Result raw:Node ReadError)` instance (a template stamp loses the pointer
   kind — filed as its own deferred item); landing it also fixed two
   pre-existing compiler bugs, a `coerce-via-cast-rule` struct-passing
   segfault reached through `defcast E Err` and a syntax error inside an
   imported file killing the whole REPL session (one-reader.md §10). **The
   last step landed 2026-09-18** with item 1's boot refresh (§8):
   `mint-collection-gensyms` (`src/nucleusc.nuc`) is deleted,
   `emit-collection-lit` mints the gensym itself, and the `__gs_N`
   renumbering was absorbed by that one refresh (one-reader.md §10).
3. **A C header outside the default search path cannot be imported** —
   **built 2026-09-19** —
   [c-header-include-paths.md](c-header-include-paths.md) (CF-1 … CF-4).
   `(import-use "gtk/gtk.h")` is fatal wherever GTK 4 is installed: the
   `clang -E` that reads a header import (`cheader-cpp-command`,
   `src/cheader.nuc:1399`) carries no include directory and nothing on the
   compiler's command line can add one — `-I` is the Nucleus module search
   path and never reaches clang, and an absolute header path dies at the
   header's own first nested `#include`. Found through a GTK demo beside the
   checkout, not on the deferred list. The fix is `--cflag=<arg>`: one
   verbatim argument to the preprocessor, repeatable, the twin of
   `--link-arg=<arg>`. Forwarding `-I` itself is rejected with a proof, not an
   argument: `lib/` holds 44 generated C headers including `lib/string.h`, and
   `clang -E -I lib -include string.h` opens that one, so every out-of-tree
   build (`-I ../nucleus/lib`) would have the prelude read the C header of
   `lib/string.nuc` in place of libc's. `CPATH` already works (the child
   inherits the environment) and stays documented as a fact, not the answer.
   Five units, no boot refresh, byte-identical `.ll` for the compiler's own
   build. **As built** (c-header-include-paths.md §10): as designed, 1071
   tests, `make bootstrap` converged; one pre-existing finding recorded below
   — the header modes swallow an unpreprocessable header — and two walls the
   GTK probes on the host hit: `MAX-STRUCTS` 1024 → 16384 (a guard, not a
   size; GTK's dependency tree registers thousands), and an attribute run
   between an enum body and its declarator (`} __attribute__((flag_enum))
   Name;`, GLib 2.86's spelling of every flags enum), which the typedef parser
   read as the declarator. The demo now compiles against the host's exact
   `clang -E` stream, 13,233 declarations imported (1072 tests).
4. **The REPL has no build line** — **designed and built 2026-09-21** —
   [repl-build-line.md](repl-build-line.md) (RC-0 … RC-6). Item 3's flag
   reaches a session only from argv, and an editor launches the REPL from one
   global argument list (`nucleus-repl-program-args`), so a per-project GTK
   build line has nowhere to go. Four gaps compound: no prompt-time spelling
   for `--cflag=`, `-I` or a library; `-l`/`-L` under `-i` are **silently
   nothing** (`g-link-args` is the link step's, and the REPL never links —
   `Symbols not found` at the first call, probed); a header import that failed
   for want of a flag is **cached as a failure** (`cheader-preprocess-mode`
   parks a null buffer, keyed on path + mode because item 3 took flags to be
   process-constant), so a retry after any fix is served the old answer; and
   the `-dM` baseline is latched once at startup, so a later `-D` would be
   admitted as a constant. Verdict: four meta forms mirroring four flags —
   `(cflag …)`, `(import-path …)`, `(library-path …)`, `(load-library …)` —
   each adding with arguments and reporting with none, arguments validated
   before any is applied; `cheader-flags-changed` empties the cache and re-arms
   the baseline; `-l`/`-L` under `-i` load through `LLVMLoadLibraryPermanently`
   (already declared, `src/llvm.nuch:45`; `RTLD_GLOBAL` joins the process
   scope LLJIT's `<Process Symbols>` dylib already searches — pinned by a C
   probe against LLVM 19: `Symbols not found` before the load, `41` after,
   no generator, and the failed module does not poison the later one); an
   optional `(pkg-config "gtk4")` composes them from
   pkg-config's two outputs. The flag vectors and loaded libraries stay
   outside `ReplState` by design. **Prerequisite found on the first probe
   (RC-0):** a void-typed expression at the prompt is compiled, JITed and
   **never called** — `(bump)` twice leaves `counter` at 0 — because the
   eval path's `TY-VOID` arm and fall-through are `(do)`; every GTK setup call
   is void. No boot refresh; batch neutrality by construction and by
   `ir-snapshot.sh verify`. **As built** (repl-build-line.md §12): as
   designed, 1079 tests (six units + the void-runs golden), `make bootstrap`
   converged, roster clean, 2780 snapshot artifacts byte-identical; the
   directory test is `dir-exists?` not `read-dir`, `pkg-config: not found`
   also covers a silent exit 127, glibc's `libm.so` is a linker script so the
   soname is the spelling to load, and freedesktop pkg-config prints its
   missing-package line unquoted.
5. **Frame storage could escape through `alloca`, the literals and a `defvar`
   initializer** — **designed and built 2026-09-22** —
   [frame-storage-escape.md](frame-storage-escape.md) (FS-1 … FS-5). The GTK
   demo's `(defvar options:&(Vector i32) [500 …])` read `len 0` at run time:
   the literal is a stack header (only the elements are on the heap), a
   run-time initializer executes in `@__nucleus_init`, and the global kept
   that frame's address. Nothing refused it because `&x` was the only
   frame-taint source; `(return (alloca Box))`, `(defn f ():&Pt (Pt 1 2))` and
   `(defvar g:&Box (alloca Box))` were all silent. Every producer of a stack
   slot — `alloca`, the struct/array literals, the TC-3 materialization —
   now taints its address (FS-1); a by-value struct slot **discharges** frame
   taint, since the load copies through the address (FS-2, the rule that
   keeps `(defvar opts:(Vector i32) […])` and `(defn mk ():Pt (return
   (alloca-backed p)))` legal, consulted at every sink and adoption); the
   `defvar` initializer becomes the one global-store sink, and the implicit
   return stops firing in a `void` function (FS-3); and the frame flag now
   travels through every join — `cond`, both `match` shapes, `unwrap`,
   `unwrap-or`, `if-some`, `some`/`ok`, union construction — and through
   `emit-set`'s result and `binding-address-val`, three sites that copied the
   scope without the flag and so reported a frame address as a `with` resource
   (FS-4). Chosen by measurement: tainting `alloca` alone costs one fixture
   (the by-value shape FS-2 fixes) across the self-compile and 1079 tests;
   making *every* global store a sink trips 17 scoped push/pop sites (the
   `with-handler` shape, the compiler's own `g-out` save/restore) with no
   launder to offer. 1087 tests, bootstrap converged, no boot refresh; two
   fixtures that had used a dangling return as scaffolding were repaired.

6. **The AST as a collection** — **built 2026-09-23** —
   [ast-as-collection.md](ast-as-collection.md) (options examined 2026-09-22,
   O3 chosen and built the next day). A list `Node` is a header over an array
   (`elems`/`len`/`cap` replacing `car`/`cdr`, `NODE-CELL` → `NODE-LIST`), so
   it conforms to `(Coll (ref Node) NodeIter)` and `(Seq (ref Node))` and a
   form is an ordinary collection: `count`, `(xs i)`, `conj`, `append`,
   `insert`, `contains?`, `doseq`, `into`. `()` stops being `null` — null now
   means only "absent" — and the sweep rule is **never compare a list to null
   to mean empty; ask `node-len`**. Built in two boot refreshes behind a
   layout-neutral list API (§8.2), with `ast-first`/`ast-rest`/`ast-at`/
   `ast-len` as special forms so a macro body reads a list under either layout.
   Two mechanisms it cost: `node-kind` answers `NODE-NIL` for `()` as well as
   for null, which is what preserved the twenty W9-item-45 diagnostics
   unchanged; and a literal quoted selector naming a field of the receiver now
   outranks `invoke` in the callable-value router, which is what lets a type be
   both indexable and a struct. 1094 tests, bootstrap converged, both gates
   re-baselined. Outcome and the six surprises in §8.6.

7. **`ptr` is the unchecked pointer; `raw` is retired** — **designed and
   built 2026-09-26** — [ptr-is-unchecked.md](ptr-is-unchecked.md) (BP-1 … BP-7).
   The typed spellings never drifted. The untyped pointer did: bare `ptr` is
   typed non-null yet holds `null` and every C `T*`, which leaves a null hole
   into `&T` slots and makes `cond` refuse to test it. Bare `raw` is a second
   `void*` and `&void` a third. After: `ptr` is the untyped unchecked pointer
   and `(ptr T)` the typed one, taking over everything `(raw T)` does; `&T` is
   non-null; `?&T` is checked; `raw` is reserved. Unchecked pointers are
   unsafe, so a final sweep makes most of them `&T`/`?&T`, keeping `(ptr T)`
   only where it saves significant complexity. Measured with an instrumented
   compiler: ~840 bare-`ptr` sites and ≤1,130 unchecked derefs in `src/`. Every
   step is IR-neutral, with one boot refresh mid-way (BP-3), because
   `(ptr T)` changes meaning. As built: of 2,294 unchecked occurrences, 410
   became `&T`, ~1,505 `?&T` and 377 stay `(ptr T)`. The classification was
   measured by fixed-point rounds of an instrumented compiler. Four
   zero-initialised struct fields had to be demoted by hand, since a `&T`
   field a constructor forgets holds null. Macro parameters and `gensym` are
   `&Node`. 1,192 tests (ptr-is-unchecked.md §7).

8. **`defconst` takes literals and constant aggregates** — **designed and
   built 2026-09-28** — [defconst-values.md](defconst-values.md) (DC-0 … DC-3
   and DC-5 done; DC-4, float folding, not built; §8 is the as-built record).
   `defconst` used to accept only an integer literal, refusing even `(+ 2 3)`
   and any annotation. Nothing blocked the change. The value's shape picks a
   tier:
   - **L** — a literal, re-emitted at each use and so adapting like the
     literal, with no storage and no address;
   - **A** — an aggregate or address, in `constant` storage; `&NAME` is
     writable and documented as such.

   An annotation is legal and stops adaptation. A run-time initializer is
   refused and deferred. Two `defvar :const` defects found by the probe were
   fixed first (DC-0): a field `set!` through a `:const` global compiled and
   segfaulted, and `.nuch` exported one as `(extern :const)`. Then
   `defvar :const` was retired (DC-5). Found while building: a program read
   of a global withheld by `import-ct` emitted invalid IR rather than the
   located error; that is fixed too.

9. **Optimization flags restored** — **built 2026-09-28** —
   [optimization-flags.md](optimization-flags.md). The `-O1`+ middle-end
   pipeline, `-ffast-math`, `-Ofast` and `-march=native` from stage 8 were
   lost in merge `f065de8a` while `docs/compiler.md` still documented them.
   `nucleusc -O3` ran Leibniz-π at `clang -O0` speed, about 10× off
   `clang -Ofast -march=native`. Fast-math is now applied to the parsed output
   module, so JIT bodies and `--emit-llvm` stay strict. A `.bss.` global
   whose ctor store GlobalOpt folds moves to `.data.`. The benchmark is at
   parity with C at every level. 1214 tests.
10. **No-match errors name the candidates** — **built 2026-10-01** —
   [no-match-candidates.md](no-match-candidates.md). An overload no-match
   lists each method that takes the first argument and why the rest do not
   fit; `(v i)` on a by-value struct says to write `(&v i)`. Extending implicit
   address-of to templates is recorded there, not done.

## Sequencing

Item 2 lands between item 1's PK-1 and PK-2: **PK-1 → R-1, R-2 (R-3 optional)
→ PK-2, PK-3, PK-4a → delete the gensym walk → boot refresh → PK-5 →
PK-4b, PK-6.** Everything up to and including the boot refresh landed
2026-09-18 (progress.md, "Boot refresh for Stage 21"), then PK-5a and PK-5b
the same day and PK-4b and PK-6 on 2026-09-19 — the sequence is complete.
PK-1 is one line in each reader and stops the header leak now;
PK-2 is structural in the reader and would otherwise be written twice; R is
fixed-point-preserving on its own, so its gensym walk can be deleted as the last
commit before the refresh and that one refresh absorbs the renumbering (deleting
it after would leave the bootstrap diverged until the next); and R-4's `--dump-ast` corpus gate is
the instrument PK-2 wants. If R-2 stalls, PK-2 proceeds in both readers with the
twin edits pointer-kind-spellings.md §4 specifies. Rationale in
[one-reader.md](one-reader.md) §8. Item 3 is independent of both and of the
boot: a `defvar`, a `cond` arm and two loops in `src/`, no new spelling, so it
lands whenever. Item 4 is independent of all three the same way (REPL-only
reach, no new spelling); its RC-0 may land alone. Item 5 touches only `Val`
bookkeeping and diagnostics — the compiler's own IR is byte-identical — so it
is independent of everything above.
Item 7 runs BP-1 → BP-7 in order: the non-null `(ptr T)` uses become `&T`
before the compiler changes the spelling's meaning, and a boot refresh sits
between that change and moving `raw` onto it (ptr-is-unchecked.md §5).

## Item 6 in full: the AST as a collection

[ast-as-collection.md](ast-as-collection.md); **built 2026-09-23**, the options
below are the 2026-09-22 examination that chose O3. An AST list could not conform to
`Coll`/`Seq` as it stands — not for want of a protocol, but because a cons
list has no object of its own (nothing to mutate when empty), `()` is `null`,
and that `null` also means "absent" in every node API (`node-at`, `ListIter`,
a macro's return, `node-kind`'s `NODE-NIL`). Three real options, all needing a
boot refresh: a `nil` sentinel with a read-only protocol split (small; the AST
stays a source-only collection), a header over the cons spine (same sweep as
the next with worse asymptotics and a tail-sharing hazard), or a header over an
array — `Node`'s tail relaid as `elems/len/cap`, O(1) `count`/index, `~@` as an
extend, `rest` as a view — which is recommended: it is the shape the compiler's
own access pattern already has (1,146 `node-at`/`node-len` against 454
`car`/`cdr` walks), it makes `Node` literally `Vector`-shaped, and it unblocks
the deferred `&Node` AST API. Companion, still open: `(= r null)` on a non-null
ref compiles silently today and should not — as is the rest of §8.5's ergonomic
list (`node-push` → `conj`, `node-at` → `(x i)` in the compiler's own reads, the
`&Node` promotion, retiring `lib/list.nuc`), which O3 unblocked rather than
did.

## Candidate rough edges (found while probing items 1–3; recorded, not designed)

- ~~**A lambda's declared return type loses its pointer kind.**~~ (**fixed
  2026-09-23**, progress.md.) `(fn
  (x:raw:Pt):raw:Pt (return x))` is refused `return: raw pointer where non-null
  (ref ...) is required`, and `?&Pt` / `?ptr:(V)` returns are refused the same
  way (`value may be null where non-null (ref ...) is required`); a `defn` with
  the identical signature is fine. Five rows of the spelling matrix fail only
  for this. Cause: the lift to a synthesized `defn` (`emit-fn`, and
  `fn-make-invoke-method` for `vfn`/`mfn`/`cfn`, which had it too) re-spelled
  the return through `type-spelling`, which writes every pointer as `ptr:`;
  both now reuse the lambda's own return operand, and the five rows are back in
  `examples/type-sugar.nuc`.
- ~~**A `defunion` arm carrying a value-`Maybe`/`Result` field of a struct dies
  in the compile-time module**~~ (**fixed 2026-09-23**, progress.md): `(defunion U (mk a:?Pt b:i32) …)` → `use of
  undefined type named 'Maybe.Pt'` reported at `lib/macros.nuc:19`. The list
  form fails identically, so it is not a spelling issue — the stamped union type
  is missing from the CT module's type stream. Wider than recorded: *any*
  multi-field arm with a by-value struct field (`a:Pt b:i32`), and a
  `(struct a:Pt …)` signature preceding `Pt`'s definition. The payload is an
  anonymous struct, made at the prescan, and `lookup-or-make-anon-struct` wrote
  its type line before `%Pt` existed; it now writes only when
  `type-line-resolves` (every by-value field is in the module or queued and
  itself resolvable), and otherwise leaves the line to the queue.
- ~~**A `defstruct` naming a *later* struct by value dies the same way when a
  macro module is built between them**~~ (**fixed 2026-09-23**, progress.md; found auditing the fix above;
  pre-existing): `(defstruct A (b B) x:i32)`, a `defmacro` used, then
  `(defstruct B …)` → `use of undefined type named 'B'` in the compile-time
  module, because the defstruct emitter's eager `%A = type { %B, i32 }` had no
  readiness check. It now asks `type-line-resolves` like the anonymous-struct
  writer; `emitted` stays the "defined" tell, and a `queued` flag plus a
  fixed-point drain let the check see types that will be written later.
- ~~**`some`/`none` do not target-type in argument position.**~~ (**fixed
  2026-09-23**, progress.md) `(make U mk
  (some pt) 7)` and a plain `(f (some pt) 7)` against a `?Pt` field or
  parameter are refused (`some: value must be non-null (ref ...)`; `none` is
  `argument 1 has type ptr`), where `(let (m:?Pt (some pt)) …)` then passing
  `m` works. `some` defaults to the pointer niche with no target in scope.
  Found testing the `defunion` fix above. Now `some`/`none`/`ok`/`err`/`err!`
  are target-typed as `make`/constructor/call arguments when the slot type is
  known without resolving the overload (a `make` field, a single-definition
  parameter, or a type every same-arity overload agrees on). Struct-literal
  arguments followed with the misread below. Still untyped: user arm names, and
  overloads that disagree at the position.
- ~~**A bare `(err E)` bound or `set!` with the error library imported dies**~~
  (**fixed 2026-09-23**, found documenting the item above; pre-existing): `(let
  (r:!i32 (err bad)) …)` in a function not returning `!i32` →
  `__err-handled: enclosing return type is not a Result`, since the rewrite
  chose handler negotiation, which builds a return-typed value, for any `!T`
  want. Negotiation now needs the want to be the return type; elsewhere `err`
  is `err!`.
- ~~**`emit-struct-lit` reads any 2-element `(sym x)` argument as a designated
  `(field value)` initializer**~~ (**fixed 2026-09-23**, progress.md) (`src/nucleusc.nuc:11236–11239`), so `(H &a)`
  fails `no field 'addr-of'` (after item 1: `no field 'ref'`), and any
  one-argument call `(H (f x))` in a compound literal is mis-read the same way.
  So was a one-field nested literal `(W (One 2) 3)`, in a body and in a
  `defvar`. Now `struct-lit-designated` decides for both: designated only when
  `x`'s head is a field of the struct (which still wins over a same-named
  function), or names nothing at all (still reported as a missing field).
  Struct-literal field values are target-typed like `make` fields.
- ~~**`defprotocol` signatures are not parsed until an `extend`**~~ (**fixed
  2026-09-23**, progress.md), so a bad type in one is reported at the conformer
  — a parameter type at line 0, a return type at the `extend`'s line. This is
  why the two `defprotocol` rows are the only ones the failing spellings
  "pass". `prescan-defn-signatures` now parses each signature where it parses a
  `defn`'s (`proto-sigs-check-form`), in a dry mode of the type parser
  (`g-dry-parse-ntv`) that reads `Self`, the protocol's parameters and a
  `:where`'s variables as type variables and stamps or registers nothing — so
  the error lands on the signature's line with no `extend`, and no valid
  program's IR moves.
- ~~**A generic template's SIGNATURE resolves its concrete types in the
  instantiating file's environment**~~ (**fixed 2026-09-23**, progress.md): a
  generic `defn`'s signature and `:where`, and a struct or union template's
  fields and arms, are now read under the defining file's namespace and imports
  (`name-env-enter`), with the substituted type arguments marked as registry
  keys (`spelling-as-key`) so they stay the caller's. (Found building PK-6's round-trip unit.)
  W9 item 43 gave a stamped *body* the library's environment, but a template
  in `(ns lib)` whose signature names the library's own type — `(defn
  count-some ((v (ref (Vector ?T))) q:&Pt) …)`, or a plain `(defn g (x:T q:&Pt
  :where (Any T)) …)` — cannot be stamped from `(import lib k)`: `unknown type:
  Pt — defined in namespace 'lib'`, `note: write 'k/Pt' here`, reported at the
  caller's line (and, through a `.nuch`, at the caller's *file* with the
  header's line). `import-use`, which makes `Pt` spellable bare, stamps it;
  the source import and the `.nuch` import fail alike, so it is the signature
  walk, not the header replay. Independent of spelling — `(ref Pt)` and
  `(Vector T)` reproduce it.
- ~~**Receiver-inferred tyvar collection stops at a wrapper inside a template
  argument.**~~ (**fixed 2026-09-23**, progress.md) `(defn f (v:(ref (Vector (ref T)))):usize …)` fails `unknown type:
  T` at the definition unless `T` is declared with `:where (Any T)`; the bare
  argument form `(Vector T)` needs no `:where`. And the colon form `(Vector
  ref:T)` is collected as a tyvar under the spelling `ref:T`, which the unifier
  never binds — the same collect-but-never-bind shape as item 1's H5, on the
  pointer prefixes rather than the sigils (`src/generics.nuc:1363`, `:1400`,
  `:1459`). Still so after PK-4b (probed: `(Vector &T)`, `(Vector ref:T)` and
  `(Vector ?&T)` all `unknown type: T`); a `defunion` template other than
  `Maybe`/`Result` inside a template argument (`(Vector (Either T))`) is the
  same shape — `node-template-of` knows struct templates only. The collector
  (`collect-tyvars-at`) now carries "this is a template argument" through a
  sigil, a pointer wrapper in either spelling and an alias, and reads an
  unresolvable `ref:T` as `(ref T)`; a `defunion` template application is a
  template application to it, `unify-tpat` and `pattern-determines-tyvar`
  alike, and the two mention walkers split a colon spelling the same way.
- ~~**A `deftype` alias or C typedef name in a template argument is a fake
  tyvar**~~ (**fixed 2026-09-23**, progress.md) (found building PK-4a). `tyname-resolvable` mirrors
  `parse-type-name`'s acceptance set without its alias and C-typedef arms, so
  `(deftype PtRef &Pt)` then `(defn f ((v (ref (Vector PtRef)))) …)` is silently
  a template that accepts `(Vector i32)` — H5 with the sigil replaced by an
  alias; `q:PtRef` in value position is refused as an unknown annotation for
  the same reason. Two arms in one function, gated like PK-4a's H5 unit.
  `tyname-resolvable` answers yes for any alias or C typedef the unit knows,
  of any arity or representability, so `parse-type-name` reports what is
  wrong with one instead of a tyvar binding anything.
- ~~**The error docs hide the payload tier.**~~ (**fixed 2026-09-24**,
  progress.md) `docs/errors.md`'s introduction now names both tiers of `E` and
  points at the payload section item 2 wrote; `emit-macro-error` takes any
  `StrView`/`String` message, extracting the view's two fields for the same
  `nucleus_macro_error(ptr, ptr, i64)` call a literal makes, so a body that
  imports `fmt`/`read` can say `(str "m: got " (string-as-view &t))`.
  `docs/errors.md:10` presented
  `Err` as *the* error type and its `(Result T E)` section says a custom `E`
  needs `make` — stale: bare `err`/`err!`/`ok` target-type against any return
  type, and `defcast E Err` is the bridge that lets `try` propagate a typed
  error into a `!T` caller (item 2 §1.7 probes). Item 2 rewrites that section;
  nothing in the compiler is missing. What *is* missing is on the compiler's
  side: a macro body can raise a located diagnostic (`macro-error`, Stage 20
  M3) but not a formatted one — the message must be a string literal
  (`context/conventions.md` §"Member access on a null node…").
- ~~**The C-header classifiers do not read a `(? X)` / `(! X)` cell**~~ (found
  building PK-5a; **fixed by PK-4b, 2026-09-19**). `cheader-template-instance` keyed
  on a cell whose *head* is a union template — `(Maybe …)`, `(Result …)` — and
  `cheader-niche-no-c` on a sigil-led *symbol*; the PK-3 list form
  `(! (Vector Diagnostic))` was neither, so a public `(defn read-diagnostics
  (…):!(Vector Diagnostic) …)` exported `void* read_diagnostics(...)` — a
  by-value tagged struct declared as a pointer, the ABI-wrong declaration both
  classifiers exist to refuse. Both now read the cell through `sigil-split`
  (`cheader-sigil-operand`), which also caught the *symbol* form's hole: a
  `q:?&Pt` parameter desugars to the glued-head cell `(?ref Pt)` and rendered
  `void*` where a field rendered `struct Pt*`. The two swept sites are in.
- ~~**`extend` reads a cell subject as a template application**~~ (**fixed
  2026-09-23**, progress.md), so
  `(extend &Cents Ord)` — `(ref Cents)` after PK-1 — is refused where
  `(extend ptr:Cents Ord)` conforms the pointer type (`examples/operators.nuc:34`).
  Worse, `ref:Cents`, `raw:Cents` and `?&Cents` were accepted and recorded under
  their verbatim spelling, a key dispatch never asks. `extend-subject-typed`
  (`src/generics.nuc`) now sends every pointer and sigil spelling past the
  template path to `extend-subject-key` — `type-spelling` of the parsed type,
  the dispatch key — so each conforms the kind-erased `ptr:Cents`; the `.nuch`
  replay (`register-imported-conformance`) does the same.
- ~~**An alias or colon-template `extend` subject is recorded and never matched**~~
  (**fixed 2026-09-23**, progress.md) (found fixing the item above). `(deftype Money i32) (extend Money P)` keys
  `Money` and `(extend Vector:i32 P)` keys `Vector:i32`, while dispatch asks
  `i32` and the stamped struct's name; both compile and fail at a `:where` call as `no
  matching method … required protocol constraint`. `extend-subject-typed` now
  sends an alias or C typedef name, a colon spelling and a template application
  over concrete types to `extend-subject-key`, so an alias conforms its target
  (a second extend through the target is a same-type re-extend) and
  `(Vector i32)` conforms one instance instead of the template.
- ~~**A `:where` names an imported namespaced protocol only by its canonical key**~~
  (**fixed 2026-09-23**, progress.md) (found fixing the item above; pre-existing, the boot fails alike). A library in
  `(ns geom)` defining `Show` and `(extend Pt Show)`: under `(import-use geoval)`
  the consumer calls `show` bare, but `(defn f (x:T :where (Show T)) …)` dies
  `defn: :where names unknown protocol 'Show'`, and under `(import-prefixed geoval
  gx)` `(gx/Show T)` dies the same way. Only `(geom/Show T)` resolves, under
  either import — the `:where` lookup skips the file's import environment. A
  `Constraint` now keeps the writing file's environment and resolves through
  `protocol-lookup` when first read (`constraint-settle`), after the imported
  protocols exist. The sibling bare `(dyn Show)` under `import-use` now keys the
  library's `geom/Show` through a prescan table of imported protocol names.
- ~~**A sigil over a type variable is a different symbol to `subst-tyvars-sym`.**~~
  (**fixed by PK-4b, 2026-09-19**.) `?E` in a protocol signature or template
  body is one bare symbol and substitution walked colon *segments*, so
  `(Maybe E)` substituted and `?E` did not. `subst-tyvar-segment`
  (`src/type-mangle.nuc`) strips the sigil run, looks the remainder up and
  re-prefixes. The sweep's 14 tyvar sites stayed refused until the boot
  carried the fix; they were swept 2026-09-23 (progress.md), and the boot
  compiled them.
- ~~**A sigil over a type variable in an `extend`'s protocol application**~~ —
  `(extend (Wrap I) (Iterator ?E) :where ((Iterator E) I))` — was refused
  `protocol parameter '?E' is not determined` (found building PK-4b;
  **fixed by it**: `collect-constraint-arg-tyvars` and `node-mentions-tyvar-named`
  peel the sigil). ~~A `:where` constraint's *own* compound argument
  (`((Peek ?E) S)`) is still a concrete pattern, not a recovery —
  `recover-one-constraint` recovers a bare tyvar only; pre-existing, recorded.~~
  (**fixed 2026-09-23**, progress.md): a compound argument over tyvars (`?E`,
  `&E`, `(Vector E)`) is unified against the recorded argument
  (`unify-tpat`), and the collector walks it as a template argument.
- ~~**A flat type-variable parameter cannot call a parametric protocol method that
  returns a protocol parameter**~~ (**fixed 2026-09-24**, progress.md). The A2
  check's `sig-provides-call` reads a protocol parameter in the signature as the
  constraint's argument (`sig-spelling-type`): a type variable of the template,
  a concrete type read in the template's file, or, for a pattern over variables,
  left to the stamp. (Found testing the item above; pre-existing.)
  `(defn pk (s:S :where ((Peek E) S)):E (return (peek s)))` over
  `(defprotocol (Peek E) (peek (x:Self):E))` dies `unknown type: E` at the
  `defn`; the same body with `s:&S` and `(x:&Self)` compiles. `lib/` uses
  `&I` receivers throughout, which is why nothing there meets it.
- ~~**A parametric-alias `extend` subject is refused**~~ (**fixed 2026-09-24**,
  progress.md). `extend-subject-template-app` peels pointers and parametric
  aliases down to the struct-template application; a `TmplConformance` records
  how many pointers it peeled (`ptr-depth`), and each stamp conforms that many
  `ptr:` over the instance, so `&(Vector T)` is a template subject too. (Found
  fixing the alias item; pre-existing.) `(deftype (Vec T) (ref (Vector T)))` then
  `(extend (Vec T) (Firsty T))` is `extend: 'Vec' is not a struct template`.
  A plain alias of an instance (`(deftype Wide (Vector i64))`) works.
- ~~**A template-level `extend` ignores its subject's argument names**~~
  (**fixed 2026-09-24**, progress.md). The conformance's variables are the
  subject's arguments (`extend-subject-tyvar-args`), which must be distinct type
  variables, one per template parameter; a `:where`-free extend's protocol
  arguments may name only those. (Found alongside; pre-existing.) `(defstruct (Wrap T) v:T)` then
  `(extend (Wrap X) (Inner X))` records `(Inner X)` against the template's own
  `T`, so a `:where ((Inner E) S)` call dies `unknown type: X` when it stamps.
  Spelling the subject with the template's own name works.
- ~~**A `.nuch` drops its file's imports**~~ (**fixed 2026-09-23**, progress.md;
  the header-side face of the item above): a header now carries its source's
  prefixed imports and non-`user` flattening imports (`emit-nuch-import-env`),
  which the importer binds but does not load (`import-form-bind`), so the
  template text resolves as it did in its source. (Found probing item 2; pre-existing.)
  An exported generic that spells a prefixed name —
  `(defn f (x:T :where (gx/Show T)) …)` under `(import-prefixed geoval gx)` —
  is written verbatim, and the header carries no `import-prefixed`, so an
  importer's call is refused `no matching method … required protocol
  constraint`.
- ~~**A `:where` refusal reaches the author late**~~ (**fixed 2026-09-24**,
  progress.md). A failing call first asks its candidates' `:where`s
  (`refuse-unknown-where`), reporting the `defn` with a `while binding a call`
  note, and a `parameter mismatch` found binding a call is reported at the call
  with a note naming the constraint. (Found probing item 2;
  pre-existing ordering.) A `:where` naming an invisible protocol is diagnosed
  by the A2 pass, which runs after emission, so when the file also calls the
  generic the first error is the call's `no matching method`, not
  `defn: :where names unknown protocol`. Likewise a `parameter mismatch` is
  reported at the constraint's line, not the call that bound it.
- ~~**`--emit-nuch` and `--emit-cheader` swallow an unpreprocessable C header**~~
  (**fixed 2026-09-24**, progress.md). `cheader-prescan-opaque` now refuses a
  null buffer with the emitter's own `die-at` at the import form's line, so all
  three modes print clang's report once and the same located error, exit 1; a
  `.nuch`-carried C import, which only binds, is exempt.
  (Found gating item 3.) `(import-use "no-such.h")` under `--emit-llvm` is
  `exit 1` with the located `c-include: failed to preprocess` error; under
  either header mode the `note:` and clang's `file not found` go to stderr and
  the mode **exits 0**, emitting a header with none of that import's names.
  The `die-at` (`src/cheader.nuc:2963`) is on the emit-time import path, which
  the header modes never reach; they run only the prescans, and the W3a name
  pre-scan (`:2766`) tolerates a null buffer. The fix is the prescan refusing
  what the emitter refuses — "What a header mode checks" (`docs/compiler.md`)
  extended from declarations to imports.
- ~~**C enumerators are not imported as constants**~~ (**fixed 2026-09-24**,
  progress.md). `c-parse-type`'s enum body is now `c-parse-enum-body`, which
  folds each initializer through `c-cexpr` and registers it through the one
  `cheader-define-int-const` the `#define`s use; the evaluator gained C's
  integer typing (a rank per expression, casts that convert, `~`, character
  constants, enumerator references), and matches clang on all 4,648 enumerators
  and 1,538 folded macros of a GTK 4 and a 17-header system probe.
  (Found walking the GTK demo through item 3.) Stage 17 admits an object-like `#define` whose body folds to
  an integer; an `enum { G_APPLICATION_DEFAULT_FLAGS = 0, … }` enumerator is
  consumed by `c-parse-type` (`src/cheader.nuc:684`, the inline body) and
  registers nothing, so `G_APPLICATION_DEFAULT_FLAGS` is `undefined:` and the
  demo keeps a hand `defconst`. GTK's flags, signal-connect options and every
  `Gtk*Type` are enums, so this is the next wall a real GTK program meets after
  the include path and the struct cap. The shape is Stage 17's: the enumerator
  list is a sequence of `NAME [= const-expr]` with an implicit `+1`, foldable by
  the same `c-cexpr` evaluator, registered under the same `is-const` symbol
  path, and subject to the same predefine/private-name filters.
- ~~**A mis-shaped `doseq`/`doseq-iter`/`dotimes` call is still unguarded; one
  shape of four still segfaults the compiler**~~ (**fixed 2026-09-23**,
  progress.md): the three bodies now carry the guard chain and name the shape
  they want at the call's line (a symbol or null `macro-error` subject now blames
  the call being expanded, not line 0). `src/ct-fault.nuc` arms a SIGSEGV/SIGBUS
  handler around every JIT call, so a crash in any macro body, `~e` or
  `compile-time` block is `macro 'm': crashed while expanding` at the call's line
  and exit 1. The REPL exits there too. The "garbage bytes" were an em dash seen
  through `cat -v`. (Found when the GTK demo grew a
  combo box, 2026-09-20; **re-measured after item 6, 2026-09-23**). The demo
  wrote `(doseq item v (VecIter i32) …)` — the `(var coll IterType)` binding
  list unparenthesised — and `nucleusc` died with SIGSEGV (exit 139), no
  diagnostic, no line. `doseq` (`lib/macros.nuc:224`), `doseq-iter` (`:251`)
  and `dotimes` (`:189`) destructure a binding list the *user* writes with no
  shape guard.

  Item 6 changed the symptom, not the bug. The three bodies now read through
  `ast-at`, which is null-safe, so a mis-shaped spec yields **null operands**
  rather than a null dereference inside the macro body, and the crash moved
  from the body to whatever the emitter does with a null element in the
  expansion. Measured today: `(doseq item v (VecIter i32) …)` and
  `(doseq (x) …)` exit 1 with `let: missing :type on '__gs_1'`;
  `(dotimes (i) …)` exits 1 with `'()' is not an expression`; `(doseq-iter x it
  …)` exits 1 with `unknown: next` followed by **garbage bytes** (a null
  symbol formatted into the message); and `(dotimes i 3 …)` **still exits
  139**. So four of five shapes now get a located line and a message that does
  not say what was wrong, and one still takes the compiler down. This is the
  hazard `context/conventions.md`
  §"Member access on a null node in a macro body kills the COMPILER" recorded
  when Stage 20 M3 gave `macmap` its guard chain; the three prelude macros whose
  first argument is a user-written list never got theirs (the operator folds,
  `->` and `case` walk compiler-built `:rest` lists behind null/kind tests and
  are safe). Two fixes, both real: **library** — the convention's guard chain
  plus `macro-error` in the three bodies (`doseq: the first argument must be
  (var coll IterType)`), which is what says what was wrong; **compiler** — a
  fault boundary at the chokepoint, a SIGSEGV/SIGBUS handler armed for the
  duration of the JIT call (and of `ct-eval-node`'s and `compile-time`'s) that
  reports `macro 'doseq': crashed while expanding` at the call-site line and
  exits 1, so no macro body, a user's included, can take the compiler down
  without a located diagnostic — the one that makes "the compiler never
  segfaults" a property rather than a discipline. Past the shape, the demo's
  next wall is the known one: `(iter options)` on a by-value `(Vector i32)` is
  `no matching method for overloaded 'iter'` (template-tier methods never
  adapt a by-value receiver, Stage 14 LW), so the binding is `&options`.
- ~~**A null element in a macro's expansion still crashes the emitter**~~
  (**fixed 2026-09-24**, progress.md). `stamp-macro-lines`, which walks exactly
  the macro-built cells, refuses a null element at the call's line — `macro 'm':
  the expansion has an empty element at position 1 of (inc! …)` — and an empty
  `:rest` is `()`, so `(str)`'s pass-through is an empty list, not an absent
  element. (Found
  fixing the item above; pre-existing.) A body that unquotes a null node into a
  binding position — `` `(let (~z 0) 1) `` or `` `(inc! ~z) `` with `z` null —
  makes `nucleusc` exit 139, no diagnostic. The crash comes after the JIT call
  has returned, so the fault boundary does not see it; in an expression
  position the same null is already `'()' is not an expression`. It is how
  `(dotimes i 3 …)` crashed before the guards. `stamp-macro-lines` visits
  exactly the macro-built cells, so it is the chokepoint. A warn-only sweep
  (461 files, positive control firing) found one existing null element: `(str)`
  (`examples/fmt-test.nuc:50`) hands its empty `:rest`, which is null, to
  `macmap`. Refusing a null element outright would break it. The fix is
  probably an empty `:rest` becoming `()` (`context/macros-jit.md` records the
  null as a leftover), then a located refusal of any remaining null element there.
- ~~**A void-typed expression at the prompt is never called**~~ (found probing
  item 4, 2026-09-21; **fixed by its RC-0 the same day**). The expression arm of
  `repl-eval-form` emits `__repl_eval_N`, JITs it and looks it up, then
  dispatches on the result kind to call-and-print (`src/repl.nuc:1180–1209`);
  the `TY-VOID` arm and the fall-through — every kind the return-emitting
  `cond` lowers to `ret void`, so a struct- or `String`-valued expression too
  — are `(do)`. `(defn bump ():void (set! counter (+ counter 1)) (return))`
  then `(bump)` twice leaves `counter` at `0`; a void `defn` with a `printf`
  prints nothing; `(dotimes (i 2) (printf "hi\n"))` prints nothing. Every
  value-returning kind is called, which is why no golden pins it. The fix is
  `funcall-void` (what `repl-run-init-fn` already uses, `:610`) in both arms.
- ~~**`-l<lib>` / `-L<dir>` under `-i` are silently ignored**~~ (same probe;
  **fixed by item 4's RC-3, 2026-09-21**). They land in `g-link-args`, which only the link step
  reads, and the REPL never links, so `nucleusc -i -lfoo` then a call into
  `libfoo` is `JIT session error: Symbols not found`. `--link-arg=` is ignored
  the same way and stays so — it has no REPL meaning — but `-l`/`-L` do.
- ~~**A `:where` inside a protocol signature is refused at every `extend`**~~
  (**fixed 2026-09-24**, progress.md). Such a signature is a generic
  requirement: `proto-sig-generic-method` reads it as a template with abstract
  variables, and the conformer's generic method must bind for it under
  constraints it implies, through the A2 checker's `abstract-call-via-generic`.
  `(dyn P)` refuses one. (Found fixing the `defprotocol` item; pre-existing.)
  `(defprotocol M (mapx (self:&Self v:T :where (Any T)):T))` passes its
  `defprotocol`, whose check reads `T` as a type variable, but `extend` dies
  `unknown type: T` at the `extend`'s line: `proto-sigs-resolve-in`
  substitutes only `Self` and the protocol's parameters, then parses the whole
  parameter list, `:where` included, as concrete types. Nothing in the tree
  writes one.
- ~~**Two other signatures are still checked only when used**~~ (**fixed
  2026-09-24**, progress.md). `prescan-defn-signatures` dry-parses a `deftype`
  body (`alias-body-check`) and a source template's parameters, return and
  constraint arguments (`generic-sig-check`) with their type variables.
  (Found alongside; pre-existing.) An unused `deftype` with an unknown body —
  `(deftype A (Vector Nope))`, `(deftype B Nope)`, a parametric `(deftype (C T)
  (Vector Nope))` — compiles, because the body is re-parsed on use
  (`docs/types.md` says so). The same goes for a generic template's signature
  before it is stamped. A flat `:where` template's parameters are checked by the
  A2 pass, but its return type is not: `(defn gr (x:T :where (Any T)):Nope …)`
  compiles. A receiver-inferred template checks neither:
  `(defn nq (v:&(Vector T) y:Nope):i32 …)` compiles, since
  `method-has-nested-tyvar` skips A2. The `defprotocol` fix's dry parse, armed
  with the alias's or template's type variables, answers all three at the
  prescan.
- ~~**The REPL does not roll back `g-type-alias-depth`**~~ (**fixed
  2026-09-24**, progress.md). Both globals are on the `ReplState` roster, with
  every other scoped depth or mode an audit of the compiler's `defvar`s found
  (`g-array-ok`, `g-want-type`, `g-decl-out`, the C importer's folding flags, …;
  context/conventions.md lists them and what is deliberately left off). (Found
  adding the dry
  parse's globals to the roster; pre-existing, the pre-change compiler fails
  alike.) A `die-at`
  inside an alias expansion unwinds past the decrement, and the roster
  (`ReplState`) does not carry the counter. After 32 failed uses of
  `(deftype A (Vector Nope))` at the prompt, a valid `(deftype B i32)` is
  refused `type alias 'B' expands into a cycle` for the rest of the session.
  `g-type-key-ok` is not on the roster either, so a die inside a stamp would
  leave the exact-key fallback armed.
- ~~**A three-element `(import lib k)` is invisible to the import prescans**~~
  (**fixed 2026-09-24**, progress.md). Every walk that follows imports asks
  one predicate, `import-head?`, of the head alone, so the two prescans,
  header validation and the C-constant pass read `(import lib k)` as they read
  `import-prefixed`. (Found fixing the template-environment item; pre-existing, the pre-change
  compiler fails alike.) `prescan-imported-types` and
  `prescan-imported-signatures` accept `import` only at `node-len` 2, so a
  library imported as `(import imp3lib k)` whose own signature names a type its
  `(import-use vector)` brings in dies `unknown type: Vector … which no import in
  this unit reaches` unless the root imports `vector` too; a root signature
  naming `k/T` fails the same way. `(import-prefixed imp3lib k)` works, and
  `--emit-nuch` already writes that spelling.
- ~~**A `deftype` alias body and a protocol signature are still read in the
  user's environment**~~ (**fixed 2026-09-24**, progress.md). `TypeAlias` and
  `Protocol` record their file's imports. The alias's body and the protocol's
  signatures are read under that file's `NameEnv`, the environment the
  dry-parse check already used.
  A spelling from the caller — an alias argument, `Self`, a protocol parameter —
  is substituted as an `#env-arg-N` marker, which reads it back in the caller's
  environment (`EnvArg`). It is not a `spelling-as-key` key, which a private conformer
  would fail. A body's mistake is reported at its own line with a `while reading …` note.
  (Found alongside; pre-existing.) `(ns alib) (deftype PtRef &Pt)`
  used as `k/PtRef` from `(import alib k)` dies `unknown type: Pt — defined in
  namespace 'alib'`; `(defprotocol Probe (probe (x:&Self q:&Pt):i32))` in
  `(ns plib)` dies at `(extend Foo k/Probe)` as `u.nuc:0: unknown type: Pt`.
  The protocol fix is this one's (the `NameEnv` swap plus `spelling-as-key` on
  `Self` and the parameters) at the six readers of `Protocol.sigs`; the Protocol
  does not yet record its file's environment. A *parametric* alias splices the
  caller's nodes into the library's text, so it needs the keys marked first.
- ~~**A generic body cannot construct a struct positionally**~~ (**fixed
  2026-09-24**, progress.md). `gcheck` finds a struct head through the binding
  table as `emit-dispatch` does, checks each initializer (a designated one's
  value) and types the literal `&S`. (Found writing this
  item's units; pre-existing, no namespace needed.) `(defn mk (x:T :where (Any
  T)):i32 (let (p:Pt (Pt 1 2)) …))` is refused by the A2 check as `in generic
  body: unknown function 'Pt'`; `make` or a receiver-inferred template works.
- ~~**An error in a template's own text found while binding a call has no
  call-site note**~~ (**fixed 2026-09-24**, progress.md). The resolvers arm
  `g-bind-call` (name, file, line) around their candidate loops, and
  `diag-error` builds `while binding a call to …` from it only when an error is
  emitted. Since source templates are now checked at the prescan, this reaches
  a header's trusted template. (Found alongside.) Instantiation and stamping add `while
  instantiating …` / `while stamping …`; a parameter type that fails in
  `generic-method-bind` (`y:Nope`) is reported at the template's file and line
  alone. The bind runs once per candidate, so the note wants building lazily.
- ~~**A `.nuch` does not carry `export` re-exports or `unsafe/import-private`**~~
  (**fixed 2026-09-24**, progress.md). The header writes both verbatim and replays `export`
  through `emit-export`. The private import binds with its permission, for the
  header's text alone. An export whose library the consumer did not import is
  refused at the header's line with a note saying the carried import loads
  nothing. (Found alongside; pre-existing for `export`.) `lib/nsgfacade.nuch` has no
  `export` line, so `(import-prefixed "lib/nsgfacade.nuch" g)` then `g/area` is
  `unknown: g/area`; only the `.nuc` route re-exports. A private import binds
  names the header's declarations could name; neither is written yet.
- ~~**A template stamped with a private type argument from another namespace
  cannot see it**~~ (**fixed 2026-09-25**, progress.md). A stamp substitutes a
  private argument as a type marker (`env-arg-of-type`) that carries the
  resolved Type, so no spelling is looked up in the template's file.
  (Found fixing the alias item; follows from the
  template-environment fix.) `spelling-as-key` marks the argument
  `user/app/Foo`. That key is then re-resolved in the template's namespace,
  where `binding-visible` hides a `defstruct-`. `(k/use-probe &f &p)` with `f` a
  `defstruct- Foo` in `(ns app)` dies `unknown type: user/app/Foo` at the
  library's line. The alias and protocol readers use an `#env-arg-N` marker
  instead; template stamping wants the same.
- ~~**A library generic cannot call a protocol method whose conformer is in a
  namespaced file**~~ (**fixed 2026-09-25**, progress.md). The generic filter
  also admits a method that answers a protocol the spelling names, for a type
  with a recorded conformance; a solitary one with no global row in scope is
  called through the registry. (Found alongside; pre-existing, the pre-change compiler
  fails identically.) `(defn use-probe (x:&T :where (Probe T)) … (probe x))` in
  `(ns plb)`, instantiated from `(ns app)` whose `probe` conforms, dies
  `unknown: probe — defined in namespace 'app', which this file does not
  import`. The stamped body resolves the method in the library's environment.
  This happens whether `probe` is solitary or overloaded.
- ~~**A foreign parametric alias in a receiver pattern still expands in the
  pattern's file**~~ (**fixed 2026-09-25**, progress.md). `type-alias-apply`
  replaces each body name that means something else in the pattern's file with a
  node marker read in the alias's file, segment-wise; the five `-lookup-ref`
  resolvers and cheader read through a marker. (Found alongside.) `collect-tyvars-at`, `unify-tpat`,
  `pattern-determines-tyvar` and cheader's `type-node-to-c` expand through
  `type-alias-apply`, with no environment. They are syntactic and resolve the
  expansion's names where they stand. `(defn bw (b:&(k/PBox T) :where (Any T)) …)` over `blib`'s
  `(deftype (PBox T) (Box T))` then binds the consumer's own `Box`, or none.
  Marking the *body's* names — the inverse of the argument markers — would
  need `node-template-of` and friends to read through a marker.
- ~~**`unsafe/import-private` of a namespaced library reaches none of its private
  names**~~ (**fixed 2026-09-25**, progress.md). A qualified probe through a private
  prefix arms `g-priv-reach-ns`, which `binding-visible` honours for that one
  lookup, and `globals-lookup-ref` probes the full frame. (Found alongside; pre-existing.) `globals-lookup-ref` reaches the
  file-private key space (`#pN/name`) of a `user` library only. A `defconst-`,
  `defn-` or `defstruct-` in `(ns hid)` is `undefined: p/K` or `unknown type:
  p/Hidden — defined in namespace 'hid', which this file does not import`.
  `docs/toplevel.md` states the limit.
- ~~**A type variable through an anonymous-struct alias body is not collected**~~
  (**fixed 2026-09-25**, progress.md). An alias whose expansion is an inline
  `(struct …)`/`(union …)` makes its members template-argument positions:
  `collect-tyvars-at` walks them, and `unify-aggregate` and
  `pattern-determines-tyvar` bind them field by field against the anonymous
  aggregate. (Found alongside; pre-existing.) `(deftype (Two T) (struct a:T b:&Pt))` then
  `(defn bx (t:&(Two T) :where (Any T)) …)` dies `unknown type: T` at the
  `defn`, even in one file.
- ~~**A diagnostic names a pointer type by its registry key**~~ (**fixed
  2026-09-24**, progress.md). `type-display` prints `&T`, `(raw T)`, `?&T`,
  `!&T` and bare `ptr`, and every message that spelled a type through
  `type-spelling` (57 calls) or printed a stored conformance key
  (`key-display`/`conf-arg-display`, 9 calls) now goes through it; the REPL's `type-of` too. The key and
  the mangling are untouched, so no IR moved. (Found writing the
  `macro-error` message check, 2026-09-24.) `type-display` (`src/abi.nuc`) is
  `type-spelling`, the conformance key, so a `(raw Node)` prints `ptr:Node`: the
  retired spelling, and one that now reads as the non-null kind. Every
  diagnostic built on `type-display` does the same; it wants a renderer that
  prints the PK spellings (`(raw T)`, `&T`, `?&T`).
- ~~**A `defstruct` after a C import cannot reuse an imported constant's name**~~
  (**fixed 2026-09-24**, progress.md). An imported constant is marked `c-const`,
  and `guard-name-kind` — every definer's first step — moves one out of the
  name's way (`cconst-yield`), so any Nucleus definition wins before or after the
  import and at the REPL; `cheader-define-int-const` also skips a name any
  colliding binding row holds, except a C header's own struct tag (`from-c`).
  (Found testing the enumerator item, 2026-09-24; pre-existing for `#define`s.)
  `(import-use "fcntl.h")` then `(defstruct O_CREAT …)` is refused `'O_CREAT'
  already names a value`; the same `defstruct` *before* the import compiles,
  since `cheader-define-int-const` skips a name `g-globals` already holds but not
  one only the struct registry holds. Enumerators make it likelier — GTK alone
  brings 3,462 names — though C's UPPER_CASE convention keeps it rare.
- ~~**A header mode writes an imported C constant with nothing to define it**~~
  (**fixed 2026-09-24**, progress.md). Both header modes now run
  `prescan-value-names` and the file's C imports (`cheader-import-constants`), and
  write an extent naming an imported constant as its value — `int32_t a[64];`,
  `(array i32 64)` — while one naming the file's own `defconst` keeps its name.
  (Found alongside; pre-existing for `#define`s.) `(defstruct S (a (array i32
  O_CREAT)))` exports `int32_t a[O_CREAT];` with no `#include <fcntl.h>`, and
  the `.nuch` copy `(array i32 O_CREAT)` with no `(import-use "fcntl.h")`, so
  neither header compiles on its own. The C-typedef case already borrows its
  header (`cheader-note-c-include`); a constant wants the same, or its value.
- ~~**The C constant evaluator types the result, not each operation**~~
  (**fixed 2026-09-24**, progress.md). A rank is now a C type (`bits*2 +
  unsigned`), set per literal by C11's suffix/base table with the target's `int`
  and `long` widths; each operator converts to the larger rank and wraps its
  result (`c-arith`, `c-shift`), and an over-wide shift or `/0` does not fold.
  Matches clang on 40 edge probes (38 on AVR) and every enumerator and macro of
  the GTK and system probes. (Found alongside.) `g-cexpr-rank` is the widest operand's C type, applied once by
  `c-int-result`, so `/`, `%` and `>>` over a value that crossed the
  `int`/`unsigned` line mid-expression can differ from C: `(0u - 1) / 2` folds
  to 0, clang says 2147483647 (the plain i64 fold said 0 too). No instance in
  the 6,186 names measured; `?:` and comparisons are not folded at all.
- ~~**The C constant evaluator refuses a decimal literal above `INT64_MAX`**~~
  (**fixed 2026-09-25**, progress.md). `c-cexpr-number` now overflows only past
  `UINT64_MAX` (`c-u64-digit-over?`), and `c-literal-rank` lets a decimal that no
  signed type holds fall through to `unsigned long long`, as clang reads it.
  (Found fixing the item above; pre-existing.) `18446744073709551615ull` is
  `unsigned long long` in C and clang folds it; `c-cexpr-number` still refuses any
  decimal that overflows an `i64`, `u` or not. `?:` and comparisons, above, remain.
- ~~**`--emit-cheader` refuses an expression extent a compile accepts**~~
  (**fixed 2026-09-25**, progress.md). Both header modes buffer their output
  (`header-out-open`/`-close`), so a refusal leaves stdout empty. `const-fold-int`
  expands the stock arithmetic macros itself (`header-stock-op-expand`), and a
  `sizeof` of a type whose layout is not yet known answers "not folded". An extent
  is then checked by the compile's own `parse-type-from-node`. (Found fixing the
  header-mode constant item; pre-existing.) `(array i32 (+ 2 1))` compiles, but a
  header mode registers no macros, so `const-fold-int` fails on `+`, and the
  header written so far is left on stdout.
- ~~**`--emit-cheader` writes a by-value array alias or inline struct field as
  `void*`**~~ (**fixed 2026-09-25**, progress.md). `cheader-unalias` resolves an
  alias before every declarator, an inline `(struct …)` renders its members like
  a `(union …)`, an `:anon` inline body is written as C's anonymous member, and an
  array `defvar` is `extern T name[N];`. (Found alongside; pre-existing.)
  `(deftype Blk (array i8 512))` then
  `(defstruct T (blk Blk) (u (struct x:(array i16 4))))` exports `void* blk;` and
  `void* u;`: a silently wrong layout. A `defvar` of array type is not exported
  either ("type has no C spelling here").
- ~~**`--emit-cheader` exports a non-pointer template instance as `void*`**~~
  (**fixed 2026-09-25**, progress.md). A struct-template instance is a guarded `typedef struct Vector_i32`,
  defined before the first form that names it (`cheader-inst-c`); a
  defunion-template field omits its struct (tag still declared); the skip
  reason unaliases. (Found fixing the item above; pre-existing.) A field or signature of `(Vector ui8)`
  by value is `void*`, a silently wrong layout: `lib/string.h` writes
  `String { void* bytes; }`, and `Command`'s `offs`/`envs` in `lib/process.h`
  and `lib/file.h` are the same. A `defn` taking an alias to `(Maybe i32)` is
  declared with a `void*` parameter, where one taking `(Maybe i32)` itself is
  skipped, because `cheader-defn-skip-reason` does not unalias.
- ~~**A header mode refuses an array length computed by a user macro**~~
  (**fixed 2026-09-25**, progress.md). A header mode now runs the compile first,
  IR discarded, and walks the forms against the registries it filled; the
  header-only validation layer and the stock-macro mirror are deleted. (Found
  alongside.) A compile accepts `(array i8 (three))`, but header modes
  registered no macros, and running one needs its callees JIT-emitted.
- ~~**A by-value inline-struct parameter is declared with an anonymous struct**~~
  (**fixed 2026-09-25**, progress.md). A signature's inline aggregate is a guarded, named
  `nuc_anon_struct_h…` typedef, shared by every signature of that shape. (Found
  alongside; minor.) `(defn f (p:(struct a:i32)):i32 …)` declares
  `f(struct { int32_t a; } p)`. That is valid C, but no caller can name a
  compatible type.
- ~~**A declaration whose name is not a symbol crashes the compiler**~~ (**fixed
  2026-09-25**, progress.md). Every name position asks one of three readers
  (`require-name-slot`, `require-sig-name`, `require-decl-name`), which quote what
  was found at its line; the header modes ask the same ones. (Found
  auditing the REPL roster, 2026-09-24; pre-existing, the boot fails alike.)
  `(defstruct S (1 i32))`, `(defstruct S 1)`, `(defstruct S ("a" i32))`,
  `(defn f ((1 i32)):i32 …)`, `(let ((1 i32) 0) …)` and `(defvar (1 i32) 0)` all
  exit 139 with no diagnostic, in batch and at the prompt (where it ends the
  session); `(defstruct S (x 1))` is diagnosed. The fault is before
  `extract-name-and-type`'s `()` guard — probably a prescan or the desugar
  reading `(n 's)` off a non-symbol — so a macro that builds such a binding
  crashes the same way.
- ~~**A message names a stamped template instance by its registry name**~~
  (**fixed 2026-09-25**, progress.md). `type-display` and `key-display` print a
  stamped struct or union from its recorded origin (`sdef-display`), nested, with
  `?T`/`!T` for Maybe and Result; keys and IR names are unchanged. (Found
  alongside.) `argument 1 has type &Vector.i32, which does not match parameter
  type &Vector.pPt` — the pointer kind is now spelled, but `Vector.pPt` is the
  mangled stamp name, not `(Vector &Pt)`. A `StructDef` records no template and
  arguments to print from.
- ~~**An unnamed compound `declare` parameter is read as `(name type)`**~~
  (**fixed 2026-09-25**, progress.md). A list whose head is a type constructor (`type-form-list?`) is a
  type; `declare` params skip the colon desugar, so `ptr:FILE` is still a name;
  `--emit-nuch` exports a cell named like a constructor under `_`. (Found
  fixing the name item; pre-existing.) `(declare f ((Vector i32)):i32)` declares
  `@f(i32)`, and `((ptr i8))` declares `i8`: docs/toplevel.md says an unnamed
  parameter is a type. `(("q" i32))` is then "unable to parse type expression".
- ~~**A `defprotocol` signature whose parameters are not a list is accepted**~~
  (**fixed 2026-09-25**, progress.md). A signature must be `(name (params) ret)` at registration. (Found
  alongside.) `(defprotocol P (x y))` registers; nothing reads the
  signature until an `extend`.
- ~~**A header mode accepts a union arm field with no type**~~ (**fixed 2026-09-25**, progress.md).
  `require-decl-type` asks each declaration site in the compile's words, and
  `validate-header-declare-params` checks a `declare`'s parameter shapes. (Found
  alongside.)
  `(defunion U (a x) b)` is "defunion: field 'x' missing :type" in a compile;
  `--emit-cheader` and `--emit-nuch` exit 0. Header modes also check no
  `declare` parameter.
- ~~**The cycle-layout message prints a registry name**~~ (**fixed 2026-09-25**, progress.md).
  `cycle-layout-message` takes the StructDef: `sdef-display` for the text,
  the template's name for the definer lookup. Still no reproduction. (Found
  alongside.)
  `cycle-layout-message` takes `(sd 'name)` for both the definer lookup and the
  text, so a stamped instance pending layout across a cycle would print
  `Vector.Pt` and advise `&Vector.Pt`. No reproduction was built.
- ~~**A `defunion` template cannot be a template `extend` subject**~~ (**fixed
  2026-09-25**, progress.md). `TmplConformance.template` holds either template;
  the union stamp calls `tmpl-conformance-check-union` and the recheck walks the
  union stamps, keyed by `type-spelling`; niche instances are left out. (Found fixing
  the parametric-alias item; pre-existing.) `(extend (Either T) P)`, or an
  alias to `(Maybe T)`, is `extend: 'Either' is not a struct template`: only
  `struct-template-stamp-types-in` runs the stamp-time conformance hook
  (`g-tmpl-conf-check-hook`), so a union stamp has nothing to check against.
- ~~**An unknown protocol in a protocol signature's `:where` is caught only at an
  `extend`**~~ (**fixed 2026-09-24**, progress.md). `proto-sig-check` queues each
  constraint on `g-where-checks`, drained before the A2 pass once every file's
  protocols (`.nuch` ones register at emission) exist. (Found alongside.) The `defprotocol` dry parse reads the
  constraint's variables but never asks whether its protocol exists, so
  `(defprotocol M (m (x:&Self v:T :where (Nope T)):T))` compiles until
  something extends `M`, then fails at the signature's line. `defn` checks
  the same thing in its A2 pass.
- ~~**A generic signature's parameter that nests its variable is checked by
  arity only**~~ (**fixed 2026-09-25**, progress.md). `tpat-canon` reads both
  patterns, each in its own file, into one shape, and `tpat-match` binds the
  conformer's variables to the signature's shapes; its constraints are then
  asked of the signature's. (Found alongside.) For `(m (x:&Self v:(Vector T) :where (Any
  T)):i32)`, any generic `m` of two parameters conforms; the A2 model types only
  a bare variable or a concrete type (`proto-sig-generic-method`). Left open on
  2026-09-24: not the dry-parse mechanism. It needs pattern-against-pattern
  binding (or a skolem stamp) in `abstract-call-via-generic`.
- ~~**A struct literal is not an argument where its struct is expected**~~
  (**fixed 2026-09-25**, progress.md). `generic-resolve` and `node-type-call`
  retry the tiers with each `(S …)` literal read as `S` (`literal-arg-types`)
  once the `&S` reading has resolved nothing, so no existing call moves. (Found
  probing the struct-literal item; pre-existing.) `(conj &v (Pt 1 2))` on a
  `(Vector Pt)`, or `(rq &v (Pt 3 4))` for a `p:Pt` parameter, is `no matching
  method … (&Vector.Pt, &Pt)`: a literal types as `&S`, and a generic's bind
  does not load it for a by-value `S` as a plain call does
  (docs/structs-unions.md "Compound literals in by-value struct positions").
  `(let (p:Pt (Pt 1 2)) …)` then `p` works.
- ~~**A user operator overload does not take a struct literal**~~ (**fixed
  2026-09-25**, progress.md). A literal operand is a value: once no method takes
  the operands as written, `operator-resolve` reads them by value (an `&S` loaded
  through) and emit refuses rather than take the intrinsic. (Found fixing the
  struct-literal item.) With `(defn = (a:Pt b:Pt):bool …)`, `(= p (Pt 1 9))` is
  `= expects integer operands`, and `(= (Pt 1 2) (Pt 1 3))` compares two stack
  addresses. `operator-user-resolve` falls back to the intrinsic, so reading the
  literal as `Pt` there would change what the second form means.
- ~~**A user operator overload on a built-in type captures narrower operands**~~
  (**fixed 2026-09-25**, progress.md). `operator-user-resolve` yields to an exact intrinsic before its
  widen tier. (Found fixing the operator-literal item; pre-existing.) With `(defn >= (a:i64
  b:i64):bool …)`, `(>= x y)` over two `i32` calls it: `operator-user-resolve`'s
  widen tier runs before the intrinsic, which answers `(i32, i32)` exactly. The
  Valid walk (`valid-resolve-type`) asks the intrinsic first, so the two disagree.
- ~~**A user `=` over a built-in type stops the prelude compiling**~~ (**fixed 2026-09-25**, progress.md).
  A user method on one built-in non-pointer type the intrinsic takes is refused
  at its definition; widened pairs go to the intrinsic (item above). (Found
  alongside; pre-existing.) `(defn = (a:i64 b:i64):bool …)` is refused at
  `lib/macros.nuc:21`: `macro 'macfoldr' calls '=', which is defined later in
  this unit`. The macro's `=` is the intrinsic, but once `=` has a user method
  the call counts as one to a later definition.
- ~~**A message names an anonymous aggregate by its registry name**~~ (**fixed 2026-09-25**, progress.md).
  `sdef-display` prints it inline, `(struct a:i32 …)`. (Found alongside.) `no matching method for overloaded 'getb' with argument types
  (&__anon_struct_h62122248fcf3e9a2)`: `sdef-display` prints a stamped instance
  from its origin but an inline `(struct …)` from its hash name.
- ~~**A `defn-` template cannot be called, even in its own file**~~ (**fixed 2026-09-25**, progress.md).
  The real cause: `desugar-form` skipped `defn-`/`defvar-`/`defstruct-`, so a
  template's `x:T` never split. Also keyed and marked private as
  `generic-register-method` does. (Found fixing the private-reach item;
  pre-existing, no namespace needed.) `(defn- inner (x:T
  :where (Any T)):i32 …)` then `(inner a)` is `cannot infer type variable 'T' for
  'inner'`; the public spelling works. `register-generic-defn` keys it under the
  public name and never sets `Method.priv`, so the privacy rules do not reach a
  private template either.
- ~~**A generic body cannot annotate a local over its variable**~~ (**fixed 2026-09-25**, progress.md).
  `gbind-nested-tyvar?` dry-parses the spelling and leaves the local to the
  stamp. (Found writing the private-argument units; pre-existing.) `(let (o:?T (some x)) …)` or `(let
  (v:(Vector T) (vector-new)) …)` in a `:where (Any T)` template is `unknown type:
  T` at the A2 check: `gbind-decl-type` parses any annotation that is not bare
  `T`. `y:T` works.
- ~~**`(make (U T) arm x)` in a generic body is refused**~~ (**fixed 2026-09-25**, progress.md). `gcheck`
  skips a union-template application as it does a struct template's; `make`
  then passes. (Found alongside; pre-existing.) The A2 check reads `(Either T)` as a call, `in generic body:
  unknown function 'Either'`. Skipping it the way `node-template-of` skips a
  struct template then fails at `make`'s node-type, `unknown type: T`.
- ~~**A name private to an imported file is called "not defined anywhere"**~~ (**fixed 2026-09-25**, progress.md). `private-name-message` asks `file-private-owner`: `unknown: inner — private to pa.nuc`.
  (found fixing the `defn-` template item; pre-existing). With `(defn- inner …)`
  in `pa.nuc`, a call from a file that imports `pa` is `unknown: inner — not
  defined anywhere in this compilation unit`, which is false. The
  namespaced case says `private to namespace 'n'` (`private-name-message`); the
  file-private case has no such message.
- ~~**`lib/node.h` declares `conj`, which C's `<complex.h>` also declares**~~ (**fixed 2026-09-25**, progress.md). File-scope C names escape C17's library names too (`cheader-c-global-view`); `conj_(…) asm("conj")`.
  (found
  compiling every generated header; pre-existing). clang warns `incompatible
  redeclaration of library function 'conj'`. It is a warning, but a program
  that includes both headers cannot compile.
- ~~**A `defunion` arm field in a C header is not a declarator**~~ (**fixed 2026-09-25**, progress.md). Arm fields go through `type-node-to-c-decl`.
  (found fixing the
  template-instance item; pre-existing). `emit-cheader-defunion` writes
  `type-node-to-c` then the name, so an array or function-pointer arm field is
  written wrong; `emit-cheader-defstruct` uses `type-node-to-c-decl`.
- ~~**A defunion-template instance inside a struct-template instance is spelled by
  its registry name in a C header**~~ (**fixed 2026-09-25**, progress.md). Such an instance declares only its tag (`cheader-sdef-no-c?`); a by-value use is omitted.
  (found alongside; minor). `cheader-type-c`
  renders an instance's fields from Types, and a `(Maybe i32)` element by value
  reaches `type-name-to-c` as `Maybe.i32`, an incomplete C type. The C compile
  fails, so nothing silent.
- ~~**`(fn i32 (i32))` silently types a zero-parameter function pointer**~~
  (**fixed 2026-09-25**, progress.md). An extra operand in either `fn` shape is
  refused, naming `(fn i32)(i32 i64)`. (Found fixing the arm-declarator item;
  pre-existing.)
- ~~**A C header declares `:optional`/`:rest` functions as invalid C**~~ (**fixed
  2026-09-25**, progress.md). `int32_t add(int32_t a, , void* b_int);` is now
  the full arity, and a rest slot is `struct Node*`. (Found by the instance item's
  parse; pre-existing.)
- ~~**A C header declares `main`**~~ (**fixed 2026-09-25**, progress.md). It is
  omitted; `main(int32_t argc, void* argv)` did not compile. (Found compiling every
  snapshot header; pre-existing.)
