# Ambient namespaces: revisiting Stage 15 R3

Stage 23. **Analysis, 2026-10-03. Decided and being built: see §8.**

The question: should a namespace be reachable by its full name (`edn/edn-put`)
from any file, once the compiler or the JIT knows about it, as in Clojure? A new
`require`, with a `require-ct` variant, would make a namespace available. And
would the quasiquote name resolution just built
([quasiquote-resolution.md](quasiquote-resolution.md)) be simpler or more robust
on top of that?

## 1. What R3 says today, and why

R3 is stated in [stage15-stress-test/name-resolution.md](../stage15-stress-test/name-resolution.md)
§8 and §8.3: *a namespace should not be reachable without an import*.
`resolve-spelling` (`src/nucleusc.nuc`) is the single canonicaliser. It accepts
exactly five kinds of qualifier:

- the file's own namespace;
- `user`;
- `unsafe`;
- a prefix this file bound;
- a namespace this file flattened with `import-use` or `import-only`.

Anything else is `NR-UNBOUND`: "'zn' is not in scope in this file".

R3 buys three things:

1. **A library's imports are not its API.** A consumer cannot come to depend
   on a namespace the library happens to load, so a library can drop or swap an
   internal dependency without breaking anyone.
2. **A library's namespace name is its own business.** A consumer spells
   through its chosen prefix (`docs/toplevel.md`: "an import prefix *is* the API
   the consumer chose"), so renaming a library's `(ns …)` breaks only
   `import-use` users who wrote `ns/x` to disambiguate.
3. **A file's meaning does not depend on the rest of the unit.** What a file can
   spell is decided by its own import forms.

Note what R3 does **not** cost: `(import edn)` with no prefix already binds the
prefix `edn` from the library's last path component. For a library whose
namespace matches its file name, "the full name" is one import line away today.
Ambient reach removes that line, and nothing else.

## 2. Three ways to scope "ambient"

"Reachable once the compiler or JIT knows about it" has three readings in a
static, whole-unit compiler:

| Scope | `ns/x` resolves when… | Order-free? | Same answer for a file in every program? |
|---|---|---|---|
| **Load order** (Clojure JVM) | the namespace was loaded earlier in this compilation | no | no |
| **Unit** | any reachable file in the unit declares the namespace | yes | no |
| **Import closure** | the namespace is declared by this file, or by a file this file reaches through imports | yes | **yes** |

- **Load order is ruled out.** It contradicts the "resolution is order-free"
  rule (`docs/toplevel.md` §"Resolution is order-free; initialization is not"),
  which Stage 15 W1 spent real effort to establish.
- **Unit scope keeps order-freedom but loses property 3.** A library file can
  spell `edn/x` without loading edn, compile inside one program, and fail
  inside another, or alone.
- **Import closure is the recommended reading.** It is Clojure's practical
  behaviour (a namespace you can reach is a namespace something you loaded
  required), stated statically. It keeps properties 2 and 3 apart from renames,
  and gives up only property 1. The macro case works under it: a caller
  imported the macro's library, so the library's namespace and everything it
  imports are in the caller's closure.

The REPL's closure is its session: whatever has been imported or required at
the prompt so far. That is exactly the Clojure workflow.

## 3. `require` and `require-ct`

| Form | Loads | Binds in this file |
|---|---|---|
| `(require lib)` | `lib`, as an ordinary import | nothing; `lib`'s namespace joins the closure |
| `(require-ct lib)` | `lib`'s compile-time surface, as `import-ct` does | nothing; the namespace is reachable, but a reference from run-time code is the existing located error "was imported compile-time-only" |

Both are imports that bind nothing, which is the one import shape the language
lacks. `import-use`/`import-prefixed` stay as they are; with `require` present
they read as "require + refer" and "require + alias". Folding them into
Clojure-style `(require lib :as p :refer …)` options is possible later, but it
is churn with no new capability, so it is not recommended now.

`require-ct` inherits `import-ct`'s unit rule unchanged: if any ordinary import
or `require` anywhere reaches the library, nothing is withheld.

## 4. Costs

**Compiler (small to medium; about one Stage 15 B-step):**

- **The resolver tier.** `resolve-spelling` gets one more branch after
  prefixes and flattened namespaces: a qualifier naming a namespace in this
  file's closure is `NR-QUALIFIED`. Privacy needs no change: every resolver
  already restricts a qualified reference to public entries unless the
  namespace is the file's own.
- **The closure.** A per-file transitive set over the `ImportBind` graph,
  memoized, plus one for the REPL session. The graph exists before emission
  (`prescan-file-imports`).
  - *To verify first:* that `g-file-ns` holds every reachable file's namespace
    at prescan time, not only after `emit-ns` runs.
- **Two new import heads, at every place that recognizes import forms.**
  Measured sites:
  - `import-form-bind`;
  - the top-level dispatch (`src/nucleusc.nuc` ~19332);
  - the import-head predicates (~17826, ~17897);
  - the reserved-name set (~20391);
  - `src/nuch.nuc` (219, 821);
  - the REPL build line (`src/repl.nuc` 1096, 1104).

  `src/` need not use the new forms, so no two-stage boot is needed.
- **Diagnostics.** The `NR-UNBOUND` tier's note changes from "'zn' is not in
  scope in this file" to "namespace 'zn' is not loaded by this file's imports;
  add (require …)". A did-you-mean can offer the full name.

**Tests and docs:**
- **Resolution matrix:** the 10 `zn/` cells in
  `tests/expected/resolution-matrix.baseline` flip from `err` to `ok`, as R3's
  own B2a/B2b moved cells the other way.
- **Suites:** about 8 suite and manifest assertions of "not in scope" need
  re-examining (5 in `tests/suite-namespaces.nuc`, 2 in
  `tests/suite-s21.nuc`, 1 in `tests/manifest/diagnostics.edn`).
- **Docs:** `docs/toplevel.md`'s three sections built on R3 need rewriting:
  - "Import prefixes are file-scoped";
  - "What an import brings into scope", whose first row says "**and not** the
    library's own namespace";
  - the namespace-qualifier edge.

**No run-time cost.** The closure exists only inside the compiler. A full name
resolves to the same registry entry and LLVM symbol a prefix does, and there is
no run-time namespace registry. `require` emits a library's definitions exactly
as `import` does; `require-ct` emits nothing.

**IR:** it should be byte-identical for every existing program. Every
qualifier that resolves today still resolves through the same earlier tier,
and no qualifier that is refused today appears in a program that compiles.

## 5. Risks

1. **Transitive reliance (R3's property 1 lost).** A consumer can come to
   depend on a namespace that a library loads only as an implementation
   detail. Clojure has the same hazard, and linters are its answer. The
   Nucleus equivalent is a warning, run on the reader's forms *before* macro
   expansion, for a qualified spelling whose namespace this file does not
   import or require directly. It has to run before expansion, because a
   rewritten template symbol (§6) is spelled exactly like user text and is
   legitimately transitive.
2. **Namespace names become public API.** Today a library can rename its
   `(ns …)` and break only `import-use` users' disambiguating spellings. Under
   ambient reach, every full-name spelling, and every macro expansion that
   names it (§6), depends on the name.
3. **A prefix that equals a namespace name.** If a file binds `e` to one
   library, and a library in its closure declares `(ns e)`, then `e/x` has two
   readings.
   - **Recommended:** the prefix wins, as a file's own binding shadows an
     outer one elsewhere in the language.
   - **Alternative:** a located ambiguity error at the use. This is safer,
     because adding an import deep in the closure could otherwise silently
     re-route nothing today but break later.
4. **Short namespace names collide across unrelated libraries.** Namespaces
   are open: two files that both declare `(ns util)` share one, and their
   definitions collide. This is no worse than today, but ambient reach puts
   more weight on names like `edn`, `geom`, `util`. Clojure's answer is
   reverse-domain naming; Nucleus may want guidance in the docs, not a rule.
5. **Per-file private namespaces stay unreachable.** `#pN` cannot be spelled.
   This is correct, and it matters to §6.
6. **REPL growth.** The closure only grows, which is the Clojure experience.
   No new rollback state is needed beyond the import edges the REPL already
   rolls back.

## 6. The quasiquote work, rebased on ambient namespaces

With closure-scoped ambient reach, the rewrite can emit what Clojure emits: the
plain full name of the definition the symbol resolved to (`edn/edn-put`,
`user/edn-put`, `mylib/Box`), instead of an environment tag `#hN/name`. The
caller can reach it because the macro's library is in its closure.

### 6.1 What would be deleted

Measured on `2246fb5`:

| Piece | Size | Fate |
|---|---|---|
| Tag machinery: `HygEnv`, `g-hyg-envs`, `hyg-index`/`-of`/`-inner`/`-enter`/`-mint` | ≈ 40 lines | deleted |
| Unwrapping at reference resolvers | 39 call sites, 61 added lines, in 4 files | deleted; a full name takes the existing qualified path |
| `resolve-spelling`'s tag assertion, and the planted-tag manifest row | — | deleted |
| Display: `hyg-display`, `hyg-scrub`, `hyg-scrub-in`, `hyg-symbol-byte?` | ≈ 45 lines | deleted; a full name prints as itself and re-reads |
| `.nuch` re-spelling and its refusal (`nuch-respell-since`, `hyg-respell`) | ≈ 50 lines | deleted; a header that imports the library resolves the full name |
| REPL roster entry for `g-hyg-envs` | 1 row | deleted |
| The `#h` reserved spelling | — | deleted |
| Classification pass: `qq-resolve*`, binder slots, typed-token leaf, prelude exemption, `note-file-macros`, `arm-spelling` | ≈ 256 lines | **kept**, with the minting step changed to spell `ns/name` |
| Binder refusal | — | kept, in a simpler form: "a binding name may not be qualified" applies to every binder, source-written or not |

That is roughly 140 lines of functions plus 39 resolver call sites gone. More
important than the count, the convention the tag approach imposed disappears
(`context/conventions.md`: *every new reference resolver must unwrap a tag*).
That rule is a permanent maintenance cost, and missing it is caught only by an
internal error at run time.

### 6.2 What would be lost or weakened

1. **D3, reaching the macro file's private names.** A full name reaches public
   names only, as in Clojure. `edn-str-node` would have to become public again,
   as it was before HY-3. A per-file private (`#pN`) of a namespace-less
   library is unreachable by any spelling.
   - **Keep D3 by keeping tags for private targets only:** a hybrid, with most
     of §6.1's machinery staying.
   - **Accept Clojure's rule:** the recommendation. It is the one place the
     tag design went *beyond* Clojure.
2. **D2's "defining file's bare view" for overloads.** A full name means one
   namespace plus protocol conformers anywhere. A macro whose overloaded callee
   draws methods from *several* namespaces flattened into its file can no
   longer be expressed in one spelling.
   - Protocol methods (`edn-encode`, `to-str`) are unaffected; they are the
     common case.
   - Every rewritten name in the tree today resolves into `user` or into one
     namespace, so the loss is currently zero. `--report-qq-resolution` can
     measure it before any switch. At rewrite time such a symbol should be
     refused, not silently narrowed.
3. **Unforgeability.** A tag cannot be written in source; a full name can.
   That is not a loss under ambient reach, since anyone may write it anyway.

### 6.3 What does not get simpler

- **Plain-`defn` quasiquotes stay exempt (D5).** It is tempting to think a
  stable full name lifts the exemption. It does not. `emit-defcast` builds
  syntax in the *compiler's* compilation for use in the *user's*. `user/foo`
  written there would name the user program's `user` namespace, a different
  unit with the same namespace name. Clojure avoids this because its compiler
  and program share one runtime namespace registry. Nucleus does not.
- **The prelude exemption (D1), the `macrolet`/`macmap` exemption,
  binder-position knowledge, arm names and forward macros** are all
  classification questions. They are the same either way.

### 6.4 Robustness

| Boundary | Tags (built) | Full names (rebased) |
|---|---|---|
| A reference resolver added later | must remember to unwrap; a miss is an internal error | nothing to remember |
| Diagnostics, REPL echo, `node-str` | scrubbed at each output point | the text is the name |
| macroexpand output pasted back | not re-readable (`#` is reader syntax) | re-reads |
| `.nuch` export | re-spelled, or refused when no spelling exists | written as is; the header's own imports resolve it |
| Two compilations (header in, REPL session) | ids are per compilation | stable |
| A library renames its namespace | invisible to callers | every caller's expansion follows automatically; only source text that wrote the old name breaks (risk 2) |
| A caller-file local or definition named the same | bypassed | bypassed (a qualified spelling never matches a local, and filters to one namespace, so q4/q5 stay fixed) |

## 7. Conclusion

- **Ambient reach:** the implementation is modest, and existing programs keep
  their IR. The cost is semantic: R3's first property is given up, and namespace
  names become API. Closure scope keeps the other two properties, which unit
  scope and load order would not. A pre-expansion lint for transitive spellings
  recovers most of what R3 protected, as a warning instead of an error.
- **Quasiquote resolution on top of it:** both simpler and more robust. The
  per-compilation tag, its 39 resolver call sites, the output scrubbing and the
  `.nuch` re-spelling all go away, and expansions print as text that re-reads.
  The price is D3 (private reach, which only `edn-str-node` uses) and a corner of
  D2 that is unused today.
- **The rebase is not a reason to reverse R3.** The built version works, and
  its main cost, unwrapping at every resolver, is already paid. If R3 is
  reversed for its own reasons (REPL ergonomics, fewer import lines, Clojure
  familiarity), rebasing the quasiquote work belongs in the same stage, as a net
  deletion.

### If pursued: order of work

1. **AN-0, ground truth.**
   - Check that `g-file-ns` is complete at prescan.
   - Measure the D2 multi-namespace overload loss and the D3 private-target
     count with `--report-qq-resolution`.
   - Decide the prefix/namespace clash rule (risk 3).
2. **AN-1.** The closure and the resolver tier. Flip the 10 matrix cells.
   Existing IR must stay byte-identical.
3. **AN-2.** `require` and `require-ct`, with `.nuch` and REPL support.
4. **AN-3.** The pre-expansion transitive-spelling warning.
5. **AN-4.** Rebase the quasiquote rewrite onto full names. Delete the tag
   machinery. Make `edn-str-node` public.
6. **AN-5.** Docs: `docs/toplevel.md`'s R3 sections, `docs/macros.md`, and
   context.

## 8. Rulings (2026-10-03) and build plan

**The user's rulings:**

- **R3 is reversed, scoped to the import closure (§2).**
- **`require` is an import that binds nothing (§3).** `require-ct` is its
  compile-time-only form.
- **Transitive reliance is user error (risk 1).** The language makes no effort
  to prevent it, so AN-3 (the pre-expansion warning) is dropped.
- **An import prefix shadows a namespace name (risk 3).** The prefix wins, with
  no diagnostic.
- **Dots in a library name in an import form are directories, as in Clojure.**
  `(import-use nucleus.edn)` finds `<lib root>/nucleus/edn.nuc` (or `.nuch`).
  Hyphens are not munged; files keep their names. String-path imports are
  unchanged. The default prefix of `(import a.b)` is still the last component,
  `b`.
- **The core libraries move to `lib/nucleus/`, and each declares
  `(ns nucleus.foo)`.** Dotted namespaces are the convention against
  namespace-name collisions (risk 4). This is pre-release, so old spellings
  such as `(import-use edn)` are not kept.

**Defaults taken where the session could not ask.** Each is reversible, and
recorded here so it can be overturned:

- **D-IR. Core libraries keep today's bare LLVM and C symbol names.**
  *Reversed 2026-10-05: core links as `nuc_` + name ([core-link-names.md](core-link-names.md)).* Each
  `nucleus.*` namespace composes an empty IR prefix. Source names are
  namespaced; link names are not. Program IR, the `lib/*.h` C API, the
  compile-time `-rdynamic` roster and the runtime names the compiler emits by
  hand (`@node-push`, `@intern-symbol`, …) stay as they are, and no two-stage
  boot is needed. The cost: a user definition with the same name and
  signature as a core function is a duplicate-symbol error rather than
  coexisting, which is exactly today's behaviour.
- **D-CORE. The prelude becomes `nucleus.core`** (`lib/nucleus/core.nuc`),
  still flattened into every file implicitly, like `clojure.core`. `user` then
  holds only program code.
- **D-HYG. AN-4 is built.** Quasiquote resolution emits full names in place of
  `#hN` tags. This reverses D3 (§6.2): a template may not name its file's
  private definitions, so `edn-str-node` becomes public again.
- **D-TESTLIB. The test and demo libraries stay at the root of `lib/`.** These
  are boxlib, mathlib, testmacros, nsdescribe, nsdescribe2, nsgeom,
  nsgfacade, unsafe-priv-demo and mapiterlib. They are not core, so they are
  not `nucleus.*`, and leaving them means no search-path change.

**Build phases:**

| Phase | Delivers | Gates |
|---|---|---|
| **AN-1** | Closure-scoped full-name reach in `resolve-spelling`, prefix-over-namespace precedence, `require`/`require-ct`, dotted import names as directories; matrix cells flipped; tests | suite; bootstrap; IR corpus byte-identical |
| **AN-2** | `lib/nucleus/` move, `nucleus.*` namespaces with an empty IR prefix, `nucleus.core` prelude, every import in the tree rewritten, `.nuch`/`.h` regenerated. Every reference the compiler synthesizes (literal lowering, `invoke`/`get` routing, `Drop`/`Clone`/`Hash`/`Eq`/`Iterator`/`ToStr` protocols, compile-time runtime) resolves whatever the user imported | suite; bootstrap converged; IR corpus identical except where a symbol name legitimately moved, each listed |
| **AN-4** | Quasiquote rewrite on full names; tag machinery deleted; D3 reversed | suite; bootstrap; corpus |
| **AN-5** | Docs and context | — |

### AN-1 as built (2026-10-03)

Built as the §8 table's AN-1 row: closure reach, prefix precedence, `require` /
`require-ct`, dotted names. Suite 1306 passed + the 5 known LLVM-datalayout
failures (13 new tests); `make bootstrap` fixed point first time; IR corpus
456/456 byte-identical, plus the two renamed `b2a-*` fixtures, which went from
`FAIL` to compiling.

**AN-0, answered: `g-file-ns` is complete when a name is first resolved, for
every file reached through ordinary imports.** Pass 1
(`prescan-imported-types`) runs `apply-leading-ns` → `emit-ns` →
`file-ns-record`, and `prescan-file-imports` (the import edges), for each file
*before* recursing into its imports, and every name-resolving prescan of the
root runs after pass 1. Inside pass 1 a file's own registrations run after its
imports' walk, so its closure is complete then too, with one exception: a cycle
back-edge to a file still on the walk's stack, whose later imports are not yet
visited. Not covered at all, by design: `import-ct`/`require-ct` targets, which
no prescan walks (so their namespace is known from the point emission reaches
the form, exactly as their macros are), and a non-leading `(ns …)`.

**Design as built:**

- **The graph.** `g-import-edges` (`ImportEdge from to`), one entry per
  importer/library pair, written by `file-import-record` with `g-source-path`
  as the importer — every caller has set it to the file being processed.
- **The closure is seeded from `g-file-imports`, not from `g-source-path`.**
  `NameEnv` already carries the import vector for every deferred body
  (templates, `:where` settles, `dyn` annotations); seeding from it keeps a
  re-read body on its own file's closure even where a restore site does not
  move the path. Transitive hops use the edge table.
- **Memo.** One entry, keyed on (env pointer, env count, edge count,
  `g-closure-gen`); `file-ns-record` bumps the generation. Reached only after
  every earlier tier missed, and gated on `g-ns-declared`, so a unit with no
  namespace never builds a closure.
- **`require` is an `ImportBind` with `bind-none`.** `file-flattened-ns-at`
  answers none for it; every other reader already skipped null-prefix binds or
  only looked at prefixes. A flattening import of the same path upgrades the
  bind (flatten wins), as `private` already upgraded.
- **`require` is walked by both prescans (`import-head?`); `require-ct` is not**,
  matching `import-ct`, so `g-real-reachable` still means "loaded for real" and
  `ct-sink-here` needed no change.
- **`require` of a C header is refused** — a header has no namespace to join a
  closure, so the form would be `import-use` under another name.
- **`.nuch` writes every `require`/`require-ct` verbatim.** It does not apply the
  `user`-namespace filter `import-use` lines get, since a `user` library's own
  imports can still carry namespaces into the closure.
- **Dotted names**: `import-name-relpath` in `resolve-import` (the one
  name → path chokepoint, so both prescans and `do-import` agree). An empty
  component (`.a`, `a..b`) is "cannot find", not `/a`.
- **Diagnostics.** The head keeps "'q' is not in scope in this file". The note
  has three tiers: another file binds `q` as a prefix (unchanged); some file of
  the unit declares namespace `q` outside this file's closure (names that file,
  suggests `(require …)`); otherwise the general rule, also suggesting
  `(require …)`. `binding-usable-spelling` and
  `generic-in-other-namespace-message` offer `ns/bare` for a closure namespace,
  so a bare name after `require` gets "write 'ns/name' here".

**Tests re-pointed, not deleted** (each keeps its name or says what it was):
`b2a-scope-diagnostic` now pins the namespace-outside-the-closure refusal (only
a non-root file can be in that position — the root's closure is the unit);
`b2b-prefixed-values-ns-reached`, `b4-qualified-generic-ns-reached` (the
filter still excludes `b4b`'s arity), `b7-macro-ns-reached`, and `s21`'s
`s21w-ns` now run; the manifest's two `b2a-*-not-in-scope` rows are
`b2a-*-through-closure` `:accept` rows over renamed fixtures.
`s22-hyg-nuch-unspellable` pinned `innerns/Secret` as unspellable; the full name
is spellable now, so it pins the macro file's *private* type instead and checks
`innerns/Secret` is exported. `tests/resolution-matrix.sh` had stale probes
(`(_get x n)` without the quoted selector) and two bare cells W9 items 43/35
had moved without a re-record; fixed and re-recorded — the ten `zn/` cells are
the only cells this phase moved.

**Open:**

- A `.nuch` header still omits an `import-use` of a `user` library, so a
  namespace reachable only *through* such a library is in the source's closure
  and not in the header's. Moot once AN-2 gives every core library a namespace.
- ~~The compile-time-only refusal still ends "(import-ct)" when the import was a
  `require-ct`.~~ Fixed in AN-2: it ends "(import-ct or require-ct)".
- REPL: a died import's bind and `g-file-ns` entry survive the rollback
  (pre-existing for `g-file-imports`, which is appended in place); the edge table
  is rolled back (`n-import-edges` in the roster).

### AN-2 as built (2026-10-04)

Built as the §8 table's AN-2 row. Suite 1310 passed + the 5 known
LLVM-datalayout failures (4 new tests in `suite-namespaces.nuc`); bootstrap
converged at each step (with the migration shims, after they were removed, and
after the compile-time memos), and the final boot was rebuilt from a clean `build/` with boot == stage1 ==
stage2. Examples 162/162 match `tests/expected`.

**The move.** 41 libraries went to `lib/nucleus/` by `git mv` (37 stems
plus `avr.nuc` and `avr/{atmega328p,attiny1634,avr32dd20}.nuc`; `lib/avr/` is
gone), with 36 `.nuch` and 36 `.h` alongside: 111 renames. Each declares
`(ns nucleus.<stem>)`; `prelude.nuc` became `core.nuc`; `edn`'s `(ns edn)` became
`nucleus.edn`. The D-TESTLIB set stays at the root. An import rewrite touched
330 files, and every changed path totals 355. Headers were regenerated with
`scripts/check-headers.sh --fix`. Against HEAD, they differ only in provenance
paths, `ns`/import lines, `prelude.h`→`core.h`, and `edn`'s now-bare link names.

**Mechanisms:**

- **D-IR**: `ns-ir-prefix` answers "" when `core-ns?` holds, meaning `nucleus`
  or any `nucleus.*`. Source keys are namespaced (`nucleus.core/Node`); link
  names are bare (`%Node`, `@node-push`). C headers and diagnostics print a
  core key bare, through `display-key`.
- **D-CORE**: `nucleus.core` and `nucleus.macros` are a virtual tier, appended to
  every file's flattened set (`prelude-ns?`, `name-ref-key-at`). It is never
  written as an import, and `.nuch` does not emit it.
- **Lookup order is own namespace → flattened imports → the core tier → `user`
  last**, for every kind: values, types, protocols (`protocol-lookup`'s bare probe
  moved after the loop) and globals. A C-header import records its bind under
  `user`, so `user` appeared among a library's *flattened* namespaces, ahead of
  the core. A program's own `StrView`/`Node`/`Vector` then hijacked the core
  library's references and literal lowering, and the result was a garbled
  type error inside `lib/`. The flattened walk now skips `user`. `user` is only
  ever the final slot.
- **What the compiler synthesizes resolves in two ways.** (A) *Synthesized
  source* (the collection literal types, keyword literals, and the `StrView`
  and `Node` literal element types) spells the full name through
  `core-spelling`. That name reaches the library through the closure, whatever
  form the user's import took, so it never depends on a bare name being
  flattened. `core-ns-require` refuses the construct, naming the library to
  import, when that library is not loaded or not in the file's closure.
  (B) *Semantic questions* ("is this `Drop`?", "the `Node` type") go by
  registry key: `core-named?`, `core-proto-key`, `core-global`, `core-struct`,
  `g-key-core-strview`. The `Node` types for `ty-ptr-node`/`ty-ref-node` and for
  macro parameters come from `core-struct "Node"`, not from parsing the
  spelling. The compiler never compares a key to a bare string.
- **A method on its own namespace's type implements the protocol for it**
  (`type-owned-by-ns?` in the conformance check), even above the file's
  `extend`. The core libraries define methods before the `extend` that their
  namespace's keys now separate from `user`.
- **Refusals D-IR made necessary:**
  - `struct-link-name-unique`: a non-core `defstruct` whose LLVM name equals
    another key's is refused, located, naming the rename or `(ns …)` fix.
    Before, it was an LLVM "redefinition of type".
  - `emit-operator-dispatch`: an exact operator method in the unit that the
    file cannot reach is refused, rather than falling to the built-in. For
    `StrView` that built-in was a `strcmp` of an unterminated view. This
    surfaced one real instance in the compiler: `src/union-emit.nuc` compared
    views with no `nucleus.strview` import.
  - `(extern stderr:ptr)` in two namespaces is two keys and one link name. The
    declaration is deduplicated by IR name.
- **Suite modules and `InitJob`s carry their own imports.** A deferred `defvar`
  initializer resolves in its file's environment, so each suite module imports
  what it uses (context/build.md).
- **Compile time.** The compiler's own unit is now namespaced, so every miss walks
  the flattened set. Self-compile went from 6.55 s to 8.50 s. Four memos bring
  it back to **7.1–7.2 s, about +9%**:
  - `g-globals-index` (HashMap Symbol→slot in `src/scope.nuc`; a stale slot
    falls back to the scan, which is what keeps a REPL rollback safe);
  - `g-nsq-memo` for `ns-qualify-in`;
  - `g-path-ns` for `import-path-ns`, written by `file-ns-record`;
  - `g-ns-user`.

  Measured as `nucleusc --emit-llvm src/nucleusc.nuc`, three runs each, AN-1
  compiler on the old tree versus the AN-2 compiler on the new one.

**Deltas from the plan:**

- `nucleus.edn` composes the empty prefix, so `edn`'s link names lose `edn__`.
  That is a legitimate symbol move, and it shows in the IR corpus.
- Anonymous-member type names (`__anon_union_h…`/`__anon_struct_h…`) hash
  member-type *keys*, which now carry `nucleus.x/`. The names change, the
  layouts do not.
- The migration shims (bare-key fallbacks in `core-named?`/`core-global`,
  bare `core-spelling`, old-name tolerance in `qq-prelude-file?` and
  `ct-lib-root-note`, `prelude-import-name`) were deleted before the final
  convergence.
- Tests re-pointed, not deleted:
  - `s21`'s `template-sig-nuch` now requires `(import-use nucleus.vector)` in the
    header and `mathlib` absent (a `user` library is still filtered);
  - `bind-error` pins line 2, after its added import;
  - `s22-hyg-planted-tag` pins line 8.
  - REPL fixtures print `imported nucleus.X`.
  - The `lib/` scans in `suite-cheader`, `suite-linking` and `suite-audits`
    cover `lib/nucleus/`. Left as they were, they would have passed while
    checking no core library.

**IR corpus** (458 files vs the AN-1 base, 456 by name in both): 390 are byte-identical, and every
rejection is unchanged.
- 62 differ only in the anonymous-type hash.
- `edn-read`, `edn-struct` and `self-test` also lose `edn__`. With both
  normalized, the sorted diff is empty.
- `examples/list.nuc` has `node-list-new` line arguments shifted by one, from
  its added import line.
- The two `b2a-*` fixtures were renamed in AN-1.

**Open:**

- A user `defvar`/`defn` whose link name equals a core one is still an
  unlocated LLVM or link error. Only structs are checked. Ruled 2026-10-05:
  [core-link-names.md](core-link-names.md).
- The anonymous-type hash would be layout-stable if it hashed `display-key`.
  It does not matter until something outside the unit spells these names.
- REPL: `g-path-ns` keeps a died import's namespace entry, as `g-file-ns`
  already did (see AN-1 Open).

### AN-4 as built (2026-10-04)

Built as the §8 table's AN-4 row, per §6 and D-HYG. Suite 1313 passed + the 5
known LLVM-datalayout failures (4 new `an4-*` units; the planted-tag row is
gone). Bootstrap converged from the AN-2 boot with no shim, the boot was
refreshed and copied back, and a clean rebuild gives boot == stage1 == stage2.
IR corpus vs the post-AN-2 corpus: 456 of 456 shared files byte-identical; the
only difference is the deleted `s22-hyg-planted-tag` fixture. Examples 162/162.

**Deletion size.** `src/`: 110 lines added, 316 deleted, **net −206**. Deleted:
`HygEnv`, `g-hyg-envs` and its REPL roster row, `g-hyg-unspellable`,
`hyg-index`/`-of`/`-inner`/`-enter`/`-mint`, the 14 resolver unwrap blocks plus
the C header's, `resolve-spelling`'s tag assertion and `unsafe-qualified-op`'s
tag test, `hyg-display`/`-respell`/`-refuse-binder`/`binding-display`,
`hyg-scrub`/`-scrub-in`/`-symbol-byte?` and their four call sites (`diag-emit`
twice, `fprint-node`, `header-out-close`), `nuch-respell-since`/`nuch-construct`,
and the `.nuch` `defmacro-` export. Tests: the planted-tag fixture and manifest
row; 72 lines of `an4-*` units added.

**Mechanism.**

- **Minting** (`qq-name` → `qq-full-name`): the classification is unchanged, and
  a resolved symbol becomes `ns/bare` from the hit's provenance (`binding-src-ns`;
  a type alias's `src-ns`; `g-current-ns` for a forward macro), `user/bare` in
  `user`. A prefixed spelling (`p/foo`) mints its resolved namespace. Resolution
  of the full name is the ordinary qualified path: `resolve-spelling` finds the
  namespace in the caller's closure and `ns-qualify-in` composes the registry
  KEY, so D-IR's bare link names never enter it.
- **D1 re-checked.** `qq-prelude-file?` matches `nucleus/core.nuc` and
  `nucleus/macros.nuc`. Of the spellings the compiler matches by name, the ones
  a non-core library also defines are `=`, `!=` (intrinsic methods, so exempt),
  `drop`, `get` and `union`; the census rewrites none of them.
- **D2.** `qq-generic-ns` picks the one namespace whose filter keeps every
  method of the template file's view, trying each protocol declaring the name
  first (its full name reaches every conformer), then each method's namespace.
  None covers → a located refusal naming the macro and the namespaces. Without
  the protocol step `src/strfmt.nuc`'s `emit` was refused: `byte-len` has
  methods in `nucleus.string` and `nucleus.intern-str`, and is a `ByteStr`
  method, so `nucleus.string-protocols/byte-len` covers both.
- **D3 reversed.** A private target in a real namespace is minted; a caller in
  another namespace gets the ordinary "private to namespace" error, and a caller
  in the same namespace works. A `user` file's private name (a `#pN` key) has no
  full name, so the template is refused where it is written. `edn-str-node` is
  public again, and with it the last reason for the `.nuch` `defmacro-` export
  went, so that row is removed (`edn-scalar-codec` is used only inside
  `lib/nucleus/edn.nuc`). A forward reference to a `user` file's `defmacro-`
  stays bare.
- **Binders.** `refuse-qualified-binder` replaces the tag refusal: any spelling
  with a qualifier (not `#`-initial) is refused in `scope-define` for local
  scopes, in `guard-name-kind` after its kind-collision check (so
  `b2b-unsafe-reserved` keeps its message), for `defn` and `defmacro`
  parameters at the form's line, and for a `defenum` name, which reaches no
  `guard-name-kind`. When the spelling resolves to a global, a note names it and
  suggests `~'name` or `(gensym)`. Pre-existing bug closed: a source-written
  `(let (a/b 1) …)`, a qualified parameter or `(defn foo/bar …)` reached LLVM as
  an IR syntax error, and `(defstruct foo/S …)` / `(defmacro foo/m …)` were
  accepted under names no reference could spell.
- **Arms.** `arm-spelling` strips a qualifier that resolves, so a template's
  `armlib/circle` in arm position still names the arm. Consequence: a
  source-written `(m/circle 3)` at a `Shape`-typed want now constructs the arm,
  where it used to fall through to the call.
- **C header.** A full type name in a signature renders as the struct it names
  (`cheader-type-c`); a non-struct qualified name falls through as before.

**`.nuch` (the s22-hyg-nuch-* decision).** A header writes full names as they
are. Its imports are the source file's, and the source compiled each name
through them, so the consumer resolves it the same way:
`s22-hyg-nuch-respell` now builds headers for all three files and compiles a
consumer against them. No export-time refusal remains, because nothing reaches
export that the source did not already resolve: the old unspellable case (a
template naming its file's private type) is now the ordinary privacy refusal
while the companion compiles, in every mode; `s22-hyg-nuch-unspellable` pins it
for `--emit-nuch` and `--emit-llvm`.

**Caller closure.** The caller needs the macro's library in its closure, which
an import of the library gives. A file using a `user` macro it reaches only
because `user` is unit-wide does not have it: `src/union-emit.nuc` used
strfmt's `emit` with no `nucleus.fmt` import and now imports it (context/conventions.md).

**Census** (`--report-qq-resolution` over `lib/`, `src/nucleusc.nuc`,
`examples/`, `tests/*.nuc`, `tests/fixtures/`, deduplicated): 89 rewrites in 31
macros across 14 files; D2 refusals 0; private-target refusals 0; binder
collisions 2, both the deliberate fixtures. The core tier's own rewrites
(`doseq`/`into`'s `next`, `new`'s `arena-alloc`) are the ones HY tagged; they
print `nucleus.iterator/next` or `user/next` by which methods the unit has.

**Gate: `macroexpand`.** `(macroexpand (derive-edn Pt))` in the REPL prints
`(do (nucleus.edn/edn-derive-struct Pt user/Pt edn-encode edn-decode
edn-release) (extend Pt nucleus.edn/EdnCodec))`; `macroexpand-all`'s output,
pasted into a file as source, compiles and prints `#user/Pt {:x 1 :y 2}`.
Pinned by `an4-macroexpand-full-names`.

**Tests re-pointed:** `s22-hyg-private-helper` (q2) is a refusal test;
`s22-hyg-binder`/`-typed-binder` rows carry the new message (notes unchanged);
`s22-macro-companion-nuch` and `s22-edn-companion-nuch` expect
`s22codec/Enc` and `nucleus.edn/EdnCodec` in their headers.

**Open:**

- A core-tier macro's rewrite (`doseq`'s `next`) depends on which `next`
  methods the unit loaded; the D2 check keeps it sound, but the printed
  expansion differs between units.
