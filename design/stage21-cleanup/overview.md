# Stage 21 — cleanup

**Status:** opened 2026-09-16. Two items designed, none built.

**Goal.** Close the deferred items and rough edges the prior stages left behind
— the ones recorded in [deferred/overview.md](../deferred/overview.md) and the
ones nobody wrote down. Each item gets its own document here, its own gates, and
a move from `deferred/overview.md` to [deferred/done.md](../deferred/done.md)
when it lands. The stage has no single feature; its deliverable is a tree with
fewer "convention, not a rule" edges in it.

## Items

1. **Pointer-kind and type-sigil spellings** — **PK-1 … PK-4a, PK-5a, PK-5b built 2026-09-18** —
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
   fall-through, and `tests/` was swept with R1/R2 (`--rules`). PK-4b and
   PK-6's remaining docs rows (`generics.md`, `errors.md`, `macros.md`,
   `toplevel.md`'s reader-macro table) are what is left.
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

## Sequencing

Item 2 lands between item 1's PK-1 and PK-2: **PK-1 → R-1, R-2 (R-3 optional)
→ PK-2, PK-3, PK-4a → delete the gensym walk → boot refresh → PK-5 →
PK-4b, PK-6.** Everything up to and including the boot refresh landed
2026-09-18 (progress.md, "Boot refresh for Stage 21"), then PK-5a and PK-5b
the same day; PK-4b and PK-6 are next.
PK-1 is one line in each reader and stops the header leak now;
PK-2 is structural in the reader and would otherwise be written twice; R is
fixed-point-preserving on its own, so its gensym walk can be deleted as the last
commit before the refresh and that one refresh absorbs the renumbering (deleting
it after would leave the bootstrap diverged until the next); and R-4's `--dump-ast` corpus gate is
the instrument PK-2 wants. If R-2 stalls, PK-2 proceeds in both readers with the
twin edits pointer-kind-spellings.md §4 specifies. Rationale in
[one-reader.md](one-reader.md) §8.

## Candidate rough edges (found while probing items 1 and 2; recorded, not designed)

- **A lambda's declared return type loses its pointer kind.** `(fn
  (x:raw:Pt):raw:Pt (return x))` is refused `return: raw pointer where non-null
  (ref ...) is required`, and `?&Pt` / `?ptr:(V)` returns are refused the same
  way (`value may be null where non-null (ref ...) is required`); a `defn` with
  the identical signature is fine. Five rows of the spelling matrix fail only
  for this.
- **A `defunion` arm carrying a value-`Maybe`/`Result` field of a struct dies
  in the compile-time module**: `(defunion U (mk a:?Pt b:i32) …)` → `use of
  undefined type named 'Maybe.Pt'` reported at `lib/macros.nuc:19`. The list
  form fails identically, so it is not a spelling issue — the stamped union type
  is missing from the CT module's type stream.
- **`emit-struct-lit` reads any 2-element `(sym x)` argument as a designated
  `(field value)` initializer** (`src/nucleusc.nuc:11236–11239`), so `(H &a)`
  fails `no field 'addr-of'` (after item 1: `no field 'ref'`), and any
  one-argument call `(H (f x))` in a compound literal is mis-read the same way.
- **`defprotocol` signatures are not parsed until an `extend`**, so a bad type
  in one is reported at the conformer — a parameter type at line 0, a return
  type at the `extend`'s line. This is why the two `defprotocol` rows are the
  only ones the failing spellings "pass".
- **Receiver-inferred tyvar collection stops at a wrapper inside a template
  argument.** `(defn f (v:(ref (Vector (ref T)))):usize …)` fails `unknown type:
  T` at the definition unless `T` is declared with `:where (Any T)`; the bare
  argument form `(Vector T)` needs no `:where`. And the colon form `(Vector
  ref:T)` is collected as a tyvar under the spelling `ref:T`, which the unifier
  never binds — the same collect-but-never-bind shape as item 1's H5, on the
  pointer prefixes rather than the sigils (`src/generics.nuc:1363`, `:1400`,
  `:1459`).
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
  side: `context/macros-jit.md:16` — a macro body cannot raise a diagnostic at
  all.
- **The C-header classifiers do not read a `(? X)` / `(! X)` cell** (found
  building PK-5a). `cheader-template-instance` (`src/cheader.nuc:3690`) keys on
  a cell whose *head* is a union template — `(Maybe …)`, `(Result …)` — and
  `cheader-niche-no-c` (`:3758`) on a sigil-led *symbol*; the PK-3 list form
  `(! (Vector Diagnostic))` is neither, so a public `(defn read-diagnostics
  (…):!(Vector Diagnostic) …)` exports `void* read_diagnostics(...)` — a
  by-value tagged struct declared as a pointer, the ABI-wrong declaration both
  classifiers exist to refuse. PK-3's "the cheader walkers need no change" held
  for the *pointer* walkers only. The sweep refuses the paren operand in an
  exported slot (`lib/test.nuc:410`, `lib/hashmap.nuc:472`) until an arm for the
  sigil-head cell is added beside the two existing ones.
- **`extend` reads a cell subject as a template application**, so
  `(extend &Cents Ord)` — `(ref Cents)` after PK-1 — is refused where
  `(extend ptr:Cents Ord)` conforms the pointer type (`examples/operators.nuc:34`).
  Either the subject parser peels `ref`/`ptr`/`raw` heads before the template
  lookup, or the colon spelling stays the one way to conform a pointer type.
- **A sigil over a type variable is a different symbol to `subst-tyvars-sym`.**
  `?E` in a protocol signature or template body is one bare symbol and
  substitution walks colon *segments*, so `(Maybe E)` substitutes and `?E` does
  not — the same collect-but-never-bind family as H5/PK-4b, on the substituter
  rather than the unifier. PK-5a refuses R6/R7 over a tyvar (14 sites, all in
  `lib/`); PK-4b's walker change should take the substituter with it.
