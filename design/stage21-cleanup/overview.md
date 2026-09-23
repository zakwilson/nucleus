# Stage 21 — cleanup

**Status:** opened 2026-09-16. Five items designed and built (item 2 on 2026-09-18, items 1 and 3 on 2026-09-19, item 4 on 2026-09-21, item 5 on 2026-09-22).

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
   the sweep's paren-operand refusal is lifted; its tyvar refusal stays until
   the next boot refresh, because the boot compiler builds `nucleusc` from the
   `lib/` files those sites live in (pointer-kind-spellings.md §6 "as
   built"). PK-6 (built 2026-09-19, §8 "as built") closes the item with no
   compiler change: `examples/type-sugar.nuc` is the §1.1 matrix as one golden
   (two rows excluded for the lambda-return and `defunion`-arm defects below;
   both went back in when those defects were fixed, 2026-09-23),
   four units that no earlier milestone had pinned (`s21-matrix-compiles`,
   `s21-nuch-roundtrip`, `s21-ir-identical`, `s21-match-ref-binder`), and the
   docs table audited row by row. The item moves to
   [deferred/done.md](../deferred/done.md); the boot-gated `lib/` re-sweep is
   the one loose end, lifted at the next boot refresh.
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
  its type line before `%Pt` existed; it now writes only when every by-value
  field is in the module, and otherwise leaves the line to the queue.
- **A `defstruct` naming a *later* struct by value dies the same way when a
  macro module is built between them** (found auditing the fix above;
  pre-existing): `(defstruct A (b B) x:i32)`, a `defmacro` used, then
  `(defstruct B …)` → `use of undefined type named 'B'` in the compile-time
  module, because the defstruct emitter's eager `%A = type { %B, i32 }` has no
  readiness check. Not the one-line fix above: `StructDef.emitted` doubles as
  the redefinition tell for `defstruct` and `defunion` (`src/nucleusc.nuc`,
  `src/union-registry.nuc`), so deferring the write needs "defined" separated
  from "written" first.
- **`some`/`none` do not target-type in argument position.** `(make U mk
  (some pt) 7)` and a plain `(f (some pt) 7)` against a `?Pt` field or
  parameter are refused (`some: value must be non-null (ref ...)`; `none` is
  `argument 1 has type ptr`), where `(let (m:?Pt (some pt)) …)` then passing
  `m` works. `some` defaults to the pointer niche with no target in scope.
  Found testing the `defunion` fix above.
- **`emit-struct-lit` reads any 2-element `(sym x)` argument as a designated
  `(field value)` initializer** (`src/nucleusc.nuc:11236–11239`), so `(H &a)`
  fails `no field 'addr-of'` (after item 1: `no field 'ref'`), and any
  one-argument call `(H (f x))` in a compound literal is mis-read the same way.
- **`defprotocol` signatures are not parsed until an `extend`**, so a bad type
  in one is reported at the conformer — a parameter type at line 0, a return
  type at the `extend`'s line. This is why the two `defprotocol` rows are the
  only ones the failing spellings "pass".
- **A generic template's SIGNATURE resolves its concrete types in the
  instantiating file's environment** (found building PK-6's round-trip unit).
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
- **Receiver-inferred tyvar collection stops at a wrapper inside a template
  argument.** `(defn f (v:(ref (Vector (ref T)))):usize …)` fails `unknown type:
  T` at the definition unless `T` is declared with `:where (Any T)`; the bare
  argument form `(Vector T)` needs no `:where`. And the colon form `(Vector
  ref:T)` is collected as a tyvar under the spelling `ref:T`, which the unifier
  never binds — the same collect-but-never-bind shape as item 1's H5, on the
  pointer prefixes rather than the sigils (`src/generics.nuc:1363`, `:1400`,
  `:1459`). Still so after PK-4b (probed: `(Vector &T)`, `(Vector ref:T)` and
  `(Vector ?&T)` all `unknown type: T`); a `defunion` template other than
  `Maybe`/`Result` inside a template argument (`(Vector (Either T))`) is the
  same shape — `node-template-of` knows struct templates only.
- **A `deftype` alias or C typedef name in a template argument is a fake
  tyvar** (found building PK-4a). `tyname-resolvable` mirrors
  `parse-type-name`'s acceptance set without its alias and C-typedef arms, so
  `(deftype PtRef &Pt)` then `(defn f ((v (ref (Vector PtRef)))) …)` is silently
  a template that accepts `(Vector i32)` — H5 with the sigil replaced by an
  alias; `q:PtRef` in value position is refused as an unknown annotation for
  the same reason. Two arms in one function, gated like PK-4a's H5 unit.
- **The error docs hide the payload tier.** `docs/errors.md:10` presents
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
- **`extend` reads a cell subject as a template application**, so
  `(extend &Cents Ord)` — `(ref Cents)` after PK-1 — is refused where
  `(extend ptr:Cents Ord)` conforms the pointer type (`examples/operators.nuc:34`).
  Either the subject parser peels `ref`/`ptr`/`raw` heads before the template
  lookup, or the colon spelling stays the one way to conform a pointer type.
- ~~**A sigil over a type variable is a different symbol to `subst-tyvars-sym`.**~~
  (**fixed by PK-4b, 2026-09-19**.) `?E` in a protocol signature or template
  body is one bare symbol and substitution walked colon *segments*, so
  `(Maybe E)` substituted and `?E` did not. `subst-tyvar-segment`
  (`src/type-mangle.nuc`) strips the sigil run, looks the remainder up and
  re-prefixes. The sweep's 14 tyvar sites **stay refused** for a different
  reason: the boot compiler that builds `nucleusc` compiles the `lib/` files
  they live in and predates the fix — lift at the next boot refresh.
- **A sigil over a type variable in an `extend`'s protocol application** —
  `(extend (Wrap I) (Iterator ?E) :where ((Iterator E) I))` — was refused
  `protocol parameter '?E' is not determined` (found building PK-4b;
  **fixed by it**: `collect-constraint-arg-tyvars` and `node-mentions-tyvar-named`
  peel the sigil). A `:where` constraint's *own* compound argument
  (`((Peek ?E) S)`) is still a concrete pattern, not a recovery —
  `recover-one-constraint` recovers a bare tyvar only; pre-existing, recorded.
- **`--emit-nuch` and `--emit-cheader` swallow an unpreprocessable C header**
  (found gating item 3). `(import-use "no-such.h")` under `--emit-llvm` is
  `exit 1` with the located `c-include: failed to preprocess` error; under
  either header mode the `note:` and clang's `file not found` go to stderr and
  the mode **exits 0**, emitting a header with none of that import's names.
  The `die-at` (`src/cheader.nuc:2963`) is on the emit-time import path, which
  the header modes never reach; they run only the prescans, and the W3a name
  pre-scan (`:2766`) tolerates a null buffer. The fix is the prescan refusing
  what the emitter refuses — "What a header mode checks" (`docs/compiler.md`)
  extended from declarations to imports.
- **C enumerators are not imported as constants** (found walking the GTK demo
  through item 3). Stage 17 admits an object-like `#define` whose body folds to
  an integer; an `enum { G_APPLICATION_DEFAULT_FLAGS = 0, … }` enumerator is
  consumed by `c-parse-type` (`src/cheader.nuc:684`, the inline body) and
  registers nothing, so `G_APPLICATION_DEFAULT_FLAGS` is `undefined:` and the
  demo keeps a hand `defconst`. GTK's flags, signal-connect options and every
  `Gtk*Type` are enums, so this is the next wall a real GTK program meets after
  the include path and the struct cap. The shape is Stage 17's: the enumerator
  list is a sequence of `NAME [= const-expr]` with an implicit `+1`, foldable by
  the same `c-cexpr` evaluator, registered under the same `is-const` symbol
  path, and subject to the same predefine/private-name filters.
- **A mis-shaped `doseq`/`doseq-iter`/`dotimes` call is still unguarded; one
  shape of four still segfaults the compiler** (found when the GTK demo grew a
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
