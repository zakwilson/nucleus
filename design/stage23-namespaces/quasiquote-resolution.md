# Quasiquote names resolve where the macro was written

> **AN-4 rebase (2026-10-04).** Stage 23 AN-4 rebased this design onto ambient
> namespaces ([ambient-namespaces.md](ambient-namespaces.md) §6, "AN-4 as
> built"). The rule (§3.1), the classification (§3.2, §3.6–§3.8, §3.10) and D1,
> D4, D5 stand. Superseded: the `#h<N>/` tag (§3.3) is now the definition's full
> name `ns/name`, resolved by the ordinary qualified path, so §3.4's per-resolver
> unwrapping, §3.9's display scrub and §3.11's `.nuch` re-spelling and refusal
> are deleted; §3.5's binder refusal is now "a binding name may not be
> qualified", for every binder. D2 holds with a refusal where one namespace
> cannot cover the defining file's methods. D3 is reversed: a template reaches
> public names only. The HY sections below are kept as the record of what was
> built first.

Stage 22 follow-on. **Designed 2026-10-03; HY-0 to HY-6 built 2026-10-03**
(uncommitted; see the answers and as-built notes at the end of §5). Not
built: namespacing `lib/fmt.nuc` and `lib/io.nuc` (HY-5, measured and deferred). Prompted by the ED-4
caveat ([ed4-struct-codecs.md](ed4-struct-codecs.md) §6, `docs/edn.md`): a file
calling `derive-edn` needs `(import-use edn)`, because the expansion names
`lib/edn` functions by bare name and they resolve in the caller.

Clojure's syntax-quote resolves each symbol in the namespace where the macro
was *read*. This document adapts that rule to Nucleus: a name a template
mentions means what it meant in the file that wrote the template.

## 1. What fails today

Probed against `build/nucleusc` at `342ad50`. `mylib.nuc` declares `(ns mylib)`,
a public `helper`, a private `secret` and a struct `Box`. Each of its macros
expands to one of those names.

| # | Caller | Result |
|---|---|---|
| q1 | `(import mylib m)`, `(m/twice-helper 1)` → `` `(helper (helper ~e)) `` | `unknown: helper — defined in namespace 'mylib'` |
| q2 | `(import-use mylib)`, `(use-secret 1)` → `` `(secret ~e) `` | `unknown: secret — private to namespace 'mylib'` |
| q3 | `(import mylib m)`, `(m/make-box 3)` → `` `(Box ~e) `` | `unknown: Box — defined in namespace 'mylib'` |
| q4 | `(let (helper:i32 5) (twice-helper 1))` | `value is not callable` — the caller's local captured `helper` |
| q5 | `(ns caller)`, defines its own `edn-put`, `(derive-edn Pt)` | `ambiguous call to 'edn-put'` — `caller/edn-put` vs `user/edn-put` |

Some cases already work. `(import edn e)` + `(e/derive-edn Pt)` compiles, and so
does `(f/str …)` through a prefixed `fmt`, namespaced caller or not. The reason
is that `lib/edn.nuc` and `lib/fmt.nuc` declare no `(ns …)`. Their names are in
`user`, which every file flattens. So the bug a user meets today is q4/q5:
capture and collision. q1–q3 are what stops any library with a macro from
taking a namespace.

## 2. What transfers from Clojure, and what does not

Clojure rewrites `foo` to `the.ns/foo` at read time, and any loaded namespace
can be named from anywhere. Five Nucleus facts change the shape:

1. **No ambient namespaces.** A qualifier means something only in a file whose
   own import bound it (Stage 15 R3, `docs/toplevel.md` §"What an import brings
   into scope"). A rewritten `mylib/helper` would fail in q1's caller exactly as
   `helper` does. The rewritten symbol needs a spelling that bypasses the
   file's import table, and source must not be able to forge it.
2. **Symbols are interned singletons** (`stamp-macro-lines`' W4a note). A symbol
   node cannot carry provenance in a field, because every occurrence of the
   spelling shares it. Provenance has to be in the *spelling*.
3. **Overloads are open multimethods filtered by namespace.** `p/desc` filters
   the method set to one namespace. Protocol methods add conformers from
   anywhere (`method-answers-protocol-here`). A rewritten reference to
   `edn-encode` must still reach a conformer that a third companion library
   defines.
4. **Runtime has no namespace registry.** A quasiquote in an ordinary `defn`
   builds data that may be used in a *later* compilation. `emit-defcast` in the
   compiler is the live case: it builds user-program syntax. Provenance that
   only means something within one compilation cannot go there.
5. **Nucleus already has the rule for templates.** A generic, parametric struct,
   alias or protocol "is read as the file that wrote it" (`NameEnv`,
   `name-env-enter`, `src/union-registry.nuc:1808`). A macro template is the
   case this rule does not yet cover. This design extends the same mechanism
   rather than adding a second one.

## 3. Design

### 3.1 The rule

> A symbol in a **data position** of a quasiquote compiled into a
> **compile-time module**, which names a **global** in the file that wrote the
> quasiquote, is resolved in that file. Every other symbol is unchanged.

"Global" means a function (solitary or overloaded), `defvar`, `defconst`, enum
member, `extern`/`declare`/C-header name, type (struct, union, enum, template
or alias), protocol, or `defmacro`. The check runs when the quasiquote is
compiled. At that point `g-current-ns`, `g-source-path` and `g-file-imports`
belong to the defining file, and the whole-graph prescan has registered every
reachable signature, value and type (`docs/toplevel.md` §"Cross-file
resolution"). Macros are the exception; see §3.10.

### 3.2 What is rewritten

| Symbol in the template | Rewritten? | Why |
|---|---|---|
| Names a global of the defining file's view (own ns, flattened imports, prefixes, `user`) | **yes** | the point |
| Already qualified through the defining file's prefix (`p/foo`) | **yes** | the caller cannot spell `p` |
| Special form (the reserved set at `src/nucleusc.nuc:19876`) | no | not a name, and cannot be shadowed |
| Defined **by the prelude**, or an intrinsic operator (`when`, `->`, `and`, `!=`, `+`, `Node`, `NODE-SYM`, …) | no | in every file by construction; compiler recognizers match these spellings (narrowing on `(!= x null)`, …) |
| `unsafe/…` | no | bound in every file |
| Resolves to nothing (template locals, caller locals, type variables, fields, arm names, gensyms) | no | it means the caller's thing, as today. Clojure qualifies these to the current ns; Nucleus templates name caller-side things too often for that. |
| Inside `(quote …)` in the template (`'x` selectors, `'~f`) | no | data that stays data |
| `name:TYPE` typed token | **type part only** | the name is a binder (§3.8) |
| `true`, `false`, `null`, keywords, literals | no | not names |

### 3.3 Representation: a tagged spelling

A rewritten symbol is the interned spelling `#h<N>/<original>`, where `N`
indexes `g-hyg-envs`, a per-compilation table of `NameEnv` deduplicated by
source path. For example `#h3/edn-put` or `#h3/p/foo`. The tag:

- **Cannot be forged.** Since ED-1 a leading `#` is reader syntax. The tag joins
  `#pN`, `#env-arg-N`, `#c/` and `#dry` in the reserved list
  ([overview.md](overview.md) §1.5).
- **Survives the trip.** It survives copying, `ct-subst-args`, desugaring,
  `node-extend`, being passed as an argument to a second macro, and
  `struct-fields` returning it as a field type. Pointer equality still works
  because the tag is an ordinary interned symbol.
- **Records an environment, not a namespace.** Section 7 (a) explains why: a
  namespace alone loses the defining file's flattened imports and its per-file
  `#pN` privacy space.

### 3.4 Resolution

Every **reference** resolver entry point does the same thing before its normal
work. If the spelling is tagged, it enters `g-hyg-envs[N]` with
`name-env-enter`, resolves the inner spelling, and restores the environment.
The entry points are `globals-lookup-ref`, `generic-lookup-ref`, `find-macro`,
`binding-alias-find`, the protocol resolver, and the type registries'
`name-ref-key-count`/`name-ref-key-at` walk. HY-0 lists them exhaustively,
including `node-type`'s paths, because of the `node-type`↔`emit-node`
lockstep. The **key** entry points (`conventions.md`: "a name-resolution rule
has TWO entry points") never see a tag.

`resolve-spelling` aborts with an internal error if it is handed a tag. Without
that check, an entry point the plumbing missed would report `'#h3' is not in
scope`. With it, the miss is loud during testing.

Consequences:

- **Locals are bypassed.** No local is ever bound under a tagged name (§3.5),
  so `scope-lookup` falls through to the global frame. This fixes q4.
- **Privacy is the defining file's.** `binding-visible` reads the entered
  `g-current-ns`, so the template may name its own file's private helpers. This
  fixes q2, and lets `edn-str-node` become `defmacro-`. Clojure refuses a
  private var here. Nucleus already allows it for templates, so it is allowed
  here too.
- **Overloads use the defining file's bare view, plus conformers anywhere.**
  `generic-filter-by-ns` runs inside the entered environment, so
  `method-answers-protocol-here` still admits a nested struct's `edn-encode`
  from another companion. The caller's own bare view is **not** merged in,
  because that merge is exactly q5. The cost: a *namespaced* caller that
  extends a non-protocol overload, which a library macro then calls, is no
  longer reached. It should conform to the protocol instead. A caller in `user`
  is unaffected, since `user` is in every view.

### 3.5 Binders refuse a tag

`scope-define` (`src/scope.nuc:27`), the chokepoint for locals and parameters,
and the global definers' registration refuse a tagged name with a located
error:

```
caller.nuc:6: error: macro 'm' binds 'count', which its file resolves to the function 'mylib/count'
  note: a template name that names a global in the macro's file refers to that global;
  write ~'count to bind the caller's name, or use (gensym)
```

This is Clojure's "can't let qualified name", with a message saying why. A
template that defines a protocol method in the caller, as derive-edn does,
writes `~'edn-encode`.

### 3.6 Which quasiquotes

Only those compiled into a compile-time JIT module: `defmacro` bodies,
`compile-time` blocks and `~e` arguments. These are the cases where the tag is
consumed in the compilation that minted it (§2.4).

- **Plain `defn`s are excluded.** The tree has three such sites, all in `src/`
  (`emit-defcast`, `emit-cheader-declare`, `text-token-is-definer`'s
  `macrolet`) and none in `lib/`. `emit-defcast` *must* stay unresolved,
  because it builds syntax for programs the compiler compiles later.
- **`macrolet` and `macmap` templates are excluded.** They are expanded in the
  file that wrote them, so the definition environment is the call environment.
  Capturing the enclosing function's locals is what they are for
  (`docs/macros.md` §macrolet), and a local that shadows a global would
  silently become the global. A `macmap` written inside a `defmacro` template
  is different: it is data of the `defmacro`'s quasiquote and is resolved by
  it (§3.7), which is what `str-into` needs.

### 3.7 Nested quasiquotes

Symbols are resolved at **every** quasiquote level, as long as no `unquote`
lies between them and the template root. Under a nested unquote, a symbol is
code of an inner macro body, so it is left alone. Example:

```lisp
(defmacro str-into (out :rest parts)
  `(macmap ((p) `(to-str ~p ~'~out)) ~parts))
```

`to-str` is level-2 data and becomes `#hF/to-str`. `p` sits under the inner
`~`; it is the `macmap` parameter, and it stays `p`. `macmap` is a prelude
macro, so it is not rewritten either. The rewrite is a pure `Node → Node` pass
in `emit-quasiquote`, ahead of `emit-qq-form`. It reuses the level counting
from `qq-is-tagged` and leaves `emit-qq-*` unchanged.

### 3.8 Typed tokens

`r:ReadResult` → `r:#h3/ReadResult`. The pass splits at the first colon with
`split-typed`, walks the type spelling past `&`, `?&` and `ref:`/`ptr:`
prefixes, and rewrites the leaf name. List-form types such as
`(dst (ref ~t))` need nothing special: `ref` is a pointer-kind word, not a
global, and a type name inside the list is just a symbol. HY-0 confirms how
the lone-colon return token (`):ReadResult`) reaches the macro body.

### 3.9 Display

Messages, `node-str`/`node-write` and REPL macroexpansion render a tag as the
defining environment's spelling: `mylib/helper`, or plain `edn-put` for `user`.
A tag never reaches a diagnostic raw. The rendered text is for reading only and
is not re-read.

### 3.10 Macros defined later in the file

`find-macro` knows only macros already emitted, so a template naming a macro
defined **below** it would stay bare. The prescan already locates definer files
by name for its circular-import diagnostic (`cycle-definer-file`). HY-0 checks
whether the same data answers "this file defines a macro named X". If it does,
such names are tagged. If it does not, the rule is "a macro a template names
must be defined above the template", and violations get a warning.

### 3.11 `.nuch` export

A header holds source text, and a tag's `N` means nothing in another
compilation. When a library file's macro-produced code is exported (a generic
body, template, alias or protocol signature that came out of an expansion), the
header writer re-spells each tag in the header's own import environment:
bare, `ns/x` for a flattened namespace, or `p/x` through a prefix. If no
spelling exists, it refuses with a located error naming the construct. Derived
codecs export only signatures, which are written from resolved types. HY-0
confirms that `s22-edn-companion-nuch` writes no tag.

> **Correction (2026-10-03, HY-0 Q6).** Signatures are printed from the source
> nodes, not resolved types, and `s22-edn-companion-nuch` did write
> `:#h12/ReadResult`. HY-3 built the minimal handling described under "As built".

## 4. Effect on existing code

- **`derive-edn`** (`lib/edn.nuc:851`, `:916`). The protocol-method names passed
  as definer names become `~'edn-encode ~'edn-decode ~'edn-release`. The
  callee symbols `fe`/`fd`/`fr` become `` `edn-encode `` (a quasiquoted lone
  symbol, so the call is resolved) instead of `'edn-encode`. `edn-str-node`
  becomes `defmacro-`. The `import-use` caveat leaves `docs/edn.md` and
  `docs/macros.md`. "There is no hygiene" in `docs/macros.md` becomes a
  description of this rule.
- **Every other library macro** (about 45 `defmacro`s with quasiquotes across
  `lib/` and `src/`). HY-1's census lists each rewrite and each binder
  collision. Collisions are fixed with `~'x` or `gensym`. `lib/macros.nuc` and
  the prelude are mostly prelude-to-prelude, so their rewrites should be few.
- **IR.** Tags live in compile-time modules, and per-module string tables
  (Stage 20 S1) keep their spellings out of the program. A program whose
  resolution does not change therefore emits **byte-identical IR**. The census
  lists the programs whose resolution does change, so the gate is checkable.

## 5. Milestones

**HY-0: ground truth.** Throwaway probes; record the answers here before
building.
1. List every reference resolver entry point, including `node-type`'s symbol
   paths and the protocol, `:where`, `extend` and `(dyn P)` parsers. This is
   the HY-2 checklist.
2. List every registry that stores a **spelling** rather than a resolved
   identity: conformance keys (`type-spelling`), `spelling-as-key`, mangling
   inputs, union-arm lookup by spelling. A tag must not leak into any of them.
3. Are union arm constructors and match patterns resolved as globals? If they
   are, `((circle r) …)` patterns must be excluded from the rewrite.
4. How the lone-colon return token and colon-paren types reach a macro body.
5. Whether the prescan can answer "file F defines macro X" (§3.10).
6. Whether `.nuch` export ever writes expansion text (§3.11).
7. Does `--dump-ast` print reader output or expansions? If expansions, it
   needs the §3.9 renderer.

**HY-1: census, no behavior change.** Add `--report-qq-resolution`. It runs
the §3.2 classification at each quasiquote and prints, per site, what would be
rewritten and which binder positions would collide. Run it over `lib/`, `src/`,
`examples/` and `tests/`, and record the counts here. The gate is the
recorded counts, with every collision triaged.

**HY-2: resolver plumbing, inert.** Tag parse and the `g-hyg-envs` table, which
joins the REPL snapshot roster (`scripts/check-repl-roster.py`). Add the tag
branch at every HY-0 entry point, the `resolve-spelling` assertion, and the
§3.9 renderer. Nothing produces a tag yet. Gates: stage-2 IR is
byte-identical to stage-1 and the suite is green. Unit probes build tags by
hand with `symbol-intern` in a `compile-time` block.

**HY-3: the rewrite.** The §3.7 pass in `emit-quasiquote` (compile-time
modules only, not `macrolet`/`macmap`), and the §3.5 binder refusal. Fix the
census collisions. Boot refresh. Gates: convergence; a green suite; program IR
identical outside the census list; q1–q5 pass as suite tests (q5 also
exercising derive-edn in a namespaced caller with its own `edn-put`); and
diagnostics manifest rows for the binder refusal and the `resolve-spelling`
assertion. The assertion is reachable only through a planted tag.

**HY-4: edges.** Forward macros (§3.10), `.nuch` re-spelling or refusal
(§3.11), and nested quasiquote tests (`str-into` through a prefixed `fmt` in a
caller that defines its own `to-str` overload).

**HY-5: dogfood.** Give `lib/edn.nuc` `(ns edn)`, make `edn-str-node` private,
and change the imports that need it: `lib/test.nuc`, `tests/`, `examples/`.
Add a test where a namespaced companion derives through `(import edn e)` with
no `import-use`. Optionally namespace `lib/fmt.nuc` and `lib/io.nuc` the same
way, if HY-1's numbers say they are clean.

**HY-6: docs and context.** Rewrite "There is no hygiene" in `docs/macros.md`,
the macro row of `docs/toplevel.md` §"What an import brings into scope", and
the `docs/edn.md` caveat. Update `context/macros-jit.md` (the tag and its
reserved spelling) and `context/conventions.md` (a new reference resolver
must unwrap tags).

**HY-0 answers (2026-10-03):**

1. **Reference entry points** (the HY-2 checklist, all given a tag branch):
   `globals-lookup-ref` (which covers `scope-lookup`'s global frame; no local is
   bound under a tag), `generic-lookup-ref`, `generic-lookup` (`gcheck`,
   `valid-walk` and `abstract-call-via-generic` pass it source heads),
   `find-macro` (skips the `macrolet` stack for a tag), `protocol-lookup` (covers
   `protocol-resolve-any`, `protocol-canon-name`, constraint settling, `extend`
   and `:where`), the five type `*-lookup-ref`s, `enumdef-lookup-ref`,
   `resolve-type-name`, `binding-alias-find`, `dyn-proto-key` (`(dyn P)`
   identity) and `unsafe-qualified-op` (reached through `special-form-named`;
   answers no for a tag). `node-type` reaches names only through these, so the
   lockstep needs nothing of its own. HY-3 found one more: the C header's
   `type-node-to-c`, which sanitizes a spelling before any text sink sees it.
2. **No spelling registry sees a tag.** Conformance keys and `spelling-as-key`
   are `type-spelling` of resolved types. Mangling inputs are definer names,
   which refuse a tag. A `Constraint` keeps its spelling plus its env and
   resolves through `protocol-lookup`. The special-form and primitive sets are
   excluded by classification. A field name is a binder, but a typed token keeps
   its name part, so a template cannot tag one.
3. **Union arms are not globals.** `union-arm-index` matches by spelling for
   `match` patterns, `make` and target-typed constructors. *Delta:* the pass
   leaves each `match` arm's pattern and `make`'s arm operand as written.
   Residual: a target-typed `(arm …)` whose arm name also names a global of the
   defining file is tagged, and is then a call rather than a constructor.
4. **`):Ret`** reaches the body as a keyword node right after the parameter
   list: index 3 of `defn`/`defn-`/`extern`, index 2 of `fn` and of a
   `defprotocol` signature. A colon-paren type is already the list
   `(name (T …))`, and `x:&Foo` reads as `x:ref:Foo`. The pass tags the leaf of
   a typed token's type part and of a return keyword, after `ref:`/`ptr:`
   segments and `?`/`&`/`!`/`*` sigils, and only when it names a type or
   protocol.
5. **No.** The only per-file answer is the textual `file-defines-name` scan,
   which re-reads the file, cannot tell a `defmacro` from a `defn`, and matches
   a quasiquoted definer. HY-4 needs a per-kind variant with a cache. Until
   then a template naming a macro defined below it stays bare, with no warning.
6. **Yes** (see the §3.11 correction). `emit-nuch-header` walks the root forms,
   which hold expansions.
7. **Reader output**, before desugaring or expansion. No renderer needed.

**HY-1 census (2026-10-03).** `--report-qq-resolution` over every file in
`lib/`, `src/nucleusc.nuc`, `examples/`, `tests/*.nuc` and `tests/fixtures/`,
deduplicated by site: **90 rewrites and 3 binder collisions in 29 macros
across 12 files.** By file: `lib/edn.nuc` 31, `lib/io.nuc` 16, `lib/test.nuc`
9, `src/strfmt.nuc` 9, `lib/macros.nuc` 8, `lib/fmt.nuc` 7, `examples/macmap.nuc`
5, `lib/error.nuc` 4, and one each in `lib/arena.nuc`, `lib/parse.nuc`,
`examples/macro-cond-nocast.nuc` and `tests/fixtures/s22-macro-extend-missing.nuc`.
The static collisions were `edn-scalar-codec`'s three `defn` names. The suite
found four more at run time, outside the census's reach: `derive-edn` passing
the protocol method names to `edn-derive-struct`, and three inline test macros
in `tests/suite-s22.nuc` that define an overload of a same-file global
(`s22-macro-overloads`, `s22-macro-overload-not-a-value`,
`s22-conditional-conformance-retry`). All seven were fixed with `~'x`. After
HY-3 the census is 88 rewrites in 30 macros across 13 files, and its one
collision is the deliberate `s22-hyg-binder` fixture.

**As built (HY-2, HY-3), with the deltas from §3:**

- **Table entry.** A `HygEnv` is `{env, who, kind}` and is deduplicated on the
  whole of it (namespace, path, imports, body name, body kind), not on the path
  alone, because the §3.5 message names the body that wrote the template.
- **Arming.** `g-qq-resolve` is set around `compile-macro-body` by `defmacro`
  and `~e`, and for a `compile-time` block; `macrolet` clears it. The pass also
  requires `in-jit-module`. Both globals are on the REPL roster.
- **"Defined by the prelude"** is decided by provenance: a binding whose
  `src-file` is `prelude.nuc` or `macros.nuc` under the library root, or a
  generic with any intrinsic or prelude method. A C name (no `src-file`, or a
  `.h` file) is not tagged either: `user` makes it visible everywhere.
- **Unquote at any level** stops the walk, so no level counting is needed.
- **Display.** `node-write` in `lib/read.nuc` stays raw, because a library must
  compile alone. The scrub runs at the compiler's chokepoints instead:
  `diag-emit` (message and staged notes), `fprint-node` (the REPL) and the header
  sink.
- **`.nuch` (minimal; HY-4 is the real thing).** The header sink re-spells each
  tag the way the exporting file would (`binding-usable-spelling`), falling back
  to the display spelling. `type-node-to-c` unwraps a tag. A `.nuch` now also
  exports `defmacro-` forms, because a public macro's body is compiled in the
  importer and may call one. Without that, making `edn-str-node` private would
  have broken every consumer of `lib/edn.nuch`.
- **Refusal sites.** `scope-define` (blamed at `g-form-line`) and
  `guard-name-kind`. A top-level expansion's late prescan now runs with the
  call's line as `g-form-line`; before, its refusal reported line 0.
- **IR.** The 455-file corpus (examples and fixtures) is byte-identical to the
  pre-HY baseline. No program's resolution changed, because every library that
  defines a rewritten name is in `user`. No compiler recognizer matches any
  rewritten spelling; the matches are the compiler's own bare-name lookups.

**As built (HY-4 to HY-6, 2026-10-03):**

- **Arm names (closes the HY-0 Q3 residual).** An arm is never a global, so a
  tag on an arm name can mean only the name its file wrote. `arm-spelling`
  (`src/union-registry.nuc`) unwraps the tag. It is applied once in
  `union-arm-index` and once at arm registration, which covers `match`, `make`
  and target-typed constructors. The pass still tags such a name, because the
  same symbol may be a call elsewhere in the template. Test:
  `s22-hyg-arm-name` (an arm `circle` beside a `defn circle` in the macro's
  file).
- **Pre-existing bug fixed on the way.** A union rewrite (a target-typed arm
  constructor) re-spelled its target as the bare `UnionDef` key, such as
  `armlib/Shape`. A caller that reaches the namespace only through a prefix
  cannot resolve that key, so `(let (s:a/Shape (circle 8)) …)` failed on the
  baseline compiler too. `union-target-spelling` (`src/union-emit.nuc`) writes
  the resolved type as an `env-arg` marker whenever the key is qualified. An
  unqualified key keeps its spelling, so IR is unchanged.
- **Forward macros (§3.10): record, not warn.** `note-file-macros` runs when a
  file's top-level forms start emitting. It appends each top-level `defmacro`
  and `defmacro-` name to `g-file-macros` (path and name). `qq-resolvable`
  falls back to that list when `binding-find` misses, and treats a hit as a
  macro defined by this file. The warn option needed the same per-file answer,
  plus a second check at expansion, so recording is the cheaper of the two.
  It costs one walk of the root forms, and the prescan is unchanged. A
  `defmacro` inside a `do` or produced by an expansion is not seen, which is
  the same reach `find-macro` has before emission. Test:
  `s22-hyg-forward-macro`.
- **`.nuch` re-spelling (§3.11).** `emit-nuch-header` records the buffer
  length before each root form. `nuch-respell-since` then scrubs that form's
  text with re-spelling (`hyg-scrub-in … true`). `hyg-respell` notes the last
  tag it could not spell in `g-hyg-unspellable`. When that is set, the export
  is refused at the form's line. The message names the form as `(head name …)`
  and the tag by its display spelling, for example: `--emit-nuch: cannot export
  '(defn peek …)': it names 'innerns/Secret', which this file has no spelling
  for`. A staged note says to import the namespace or keep the definition out
  of the header. The scrub at `header-out-close` still runs, as a fallback for
  text no form produced. Tests: `s22-hyg-nuch-respell` (writes `m/Cfg`) and
  `s22-hyg-nuch-unspellable`.
- **Nested quasiquotes (§3.7).**
  - `s22-hyg-level-two`: a macro-defining macro whose inner template names its
    file's `helper`. The caller binds a local `helper`.
  - `s22-hyg-str-prefixed-fmt`: `str`/`str-into` through `(import fmt f)` in a
    namespaced caller that has its own `to-str` overload, for its own type.
  - A caller overload of `to-str` for `i32` is ambiguous, not captured. Under D2
    a protocol method's set includes conformers from anywhere, and `i32`
    already conforms. That is the intended behavior, not a capture. A caller's
    *local* named `to-str` never captured a call, even before HY: a generic
    outranks a local in head position.
- **HY-5: `lib/edn.nuc` is `(ns edn)`.** Nothing outside `lib/edn.nuc` needed
  an import change:
  - every file that imports edn already wrote `(import-use edn)`;
  - the suites, `tests/suite-audits.nuc` among them, reach it through
    `tests/nuctests.nuc`'s `(import-use test)`, and `lib/test.nuc`
    flattens `edn`;
  - `lib/edn.h`, `lib/edn.nuch` and `lib/test.nuch` were regenerated.

  The user-visible spellings are unchanged:
  - a derived tag is the caller type's qualified name, so `#user/Point` and
    test records still read the same;
  - the suite's `--diagnostics=edn` rows and `tests/manifest` pass as before.

  The IR of `examples/edn-read`, `examples/edn-struct` and
  `examples/self-test` differs only by the `edn__` prefix. Test:
  `s22-hyg-edn-prefix-only`, a namespaced companion that derives through
  `(import edn e)` with no `import-use`.
- **HY-5: `fmt` and `io` measured, not namespaced.** About 30 files use one of
  `fmt`'s 12 names without importing `fmt`: 11 in `src/`, about 17 test
  suites and 2–3 examples. They get the names transitively through `user`. For
  `io`, about 11 files rely on `write-str` or `eprint` the same way. Namespacing
  `fmt` would also rename every program's `to-str` mangling and the boot IR. That
  is an import sweep across the tree plus a byte-level IR change everywhere, so
  it is deferred. Neither library needs it for hygiene, because their templates
  already resolve.
- **Typed binders (an HY-3 hole, found while adding the REPL test).** The pass
  tagged only a typed token's type part, so `(let (thing:i32 41) (+ thing 1))`
  in a file that defines `thing` bound a bare `thing` while the body's `thing`
  was tagged. The body then meant the file's global. With a function `thing`
  this was a type error; with a global variable of the same type it compiled
  silently. The baseline compiler printed 42.
  - In binder positions, a typed token now tags its name part as well, so
    `scope-define` refuses it like an untyped binder. The binder positions are:
    - the bindings of `let`/`with`, `fn`/`defn`/`defmacro` parameters, the
      `when-some`/`if-some`/`dotimes`/`doseq`/`for` binder, and a
      `defvar`/`defconst` name (`qq-binder-slot`);
    - struct fields and protocol signatures are not binder positions, and
      stay untagged, because a field is never a reference.
  - The census's binder check now strips the type part. Its only collisions
    are the two deliberate fixtures. Fixture: `s22-hyg-typed-binder`.
- **REPL rollback.** `g-file-macros` is on the roster (`n-file-macros`). An
  import that dies at a prompt drops the macro names it recorded. Otherwise,
  re-importing the fixed file would still count a removed macro as its file's,
  and refuse a binder of that name. Test: `s22-hyg-repl-file-macros-rollback`.
  - Separate, pre-existing and not fixed: re-importing a file whose failed
    import had already compiled a `defmacro` fails with a duplicate JIT symbol
    (`__macro_<name>_N`), because the compile-time module is not rolled back.
- **Pre-existing, not fixed:**
  - Through a prefix, a user-namespace library's qualified `f/to-str` does not
    narrow the overload set, so it is as ambiguous as the bare name.
  - A namespaced file importing `"stdio.h"` alongside `lib/edn` declares
    `@remove` twice. The baseline compiler does the same.

## 6. Decisions to confirm

Each has a recommendation; the design above assumes it.

- **D1. Prelude names stay unresolved** (§3.2). *Alternative:* resolve them too,
  which is more hygienic, but every recognizer that matches `when`/`!=`/`and`
  by spelling would then need to see through tags. Recommend: exclude.
- **D2. Overloads use the defining view only** (§3.4). *Alternative:* union
  with the caller's bare view, which keeps namespaced plain-overload extension
  working but re-creates q5. Recommend: defining view only.
- **D3. Templates may name their own file's private names** (§3.4).
  Recommend: yes. Clojure says no; Nucleus templates already say yes.
- **D4. Unresolved symbols stay bare** (§3.2). Clojure qualifies them to the
  current namespace. Recommend: bare.
- **D5. `macrolet`/`macmap` templates and plain `defn` quasiquotes are exempt**
  (§3.6). Plain `defn`s are not optional: see `emit-defcast`.

## 7. Alternatives considered

- **(a) Namespace-absolute tags** (`#edn/edn-put`, an exact registry key).
  Resolution is simpler, but an overloaded name loses the defining file's
  flattened imports. A per-file private name needs its own spelling (`#pN`),
  and tags would not compose with the existing `NameEnv` machinery.
- **(b) Fallback lookup.** Record the macro's environment on the expansion and
  retry there when the caller's lookup fails. This fixes q1–q3 only. It
  resolves in the wrong order for q4/q5, which are the bugs users hit today.
- **(c) Sets of scopes (Racket).** This needs per-occurrence identity on
  interned symbols and binder renaming throughout. It is much larger, and it
  goes beyond what was asked (Clojure parity).
- **(d) Allow any loaded namespace as a qualifier** (Clojure's actual model).
  This reverses Stage 15 R3, which was a deliberate decision.
