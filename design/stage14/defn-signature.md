# Stage 14 — `defn` signature syntax: return type after the parameter list

**Goal:** change the named-function signature from

```lisp
(defn foo:ret (var1:type var2:type) body…)          ; today
```

to

```lisp
(defn foo (var1:type var2:type):ret body…)          ; target
```

matching the anonymous-function forms (`fn`/`vfn`/`mfn`/`cfn`), which already
spell `(fn (params):ret body…)`. One signature grammar everywhere; the function
name becomes a plain symbol.

This is a **syntax-only** change: no type-system, ABI, or IR semantics move. It
requires an intermediate release of the compiler that accepts **both** styles
(the bootstrap artifact must be able to compile the rewritten source), followed
by a global, mechanical rewrite of all `defn` forms, then removal of the old
style. Pre-release policy applies: no long-term back-compat, only the temporary
bootstrap shim.

Why (beyond consistency with `fn`):

- The name stays a bare symbol — greppable (`(defn foo `), no colon parsing on
  the name, and the awkward **list-head form** for parenthesized return types
  disappears: `(defn (next (Maybe T)) (params) …)` becomes
  `(defn next (params) (Maybe T) …)` (36 such heads exist today).
- The signature reads left-to-right like a call: name, arguments, result.
- Every internal consumer of the defn shape funnels through one accessor
  (today the ret-extraction logic is duplicated at ~12 sites), which is a
  prerequisite cleanup for the Stage 14 type-safety work that edits the same
  signature lines (see "Ordering" below).

---

## Ground truth — how signatures parse today

### Reader facts (`lib/reader.nuc`)

The change needs **zero reader changes**. The relevant mechanics:

1. **Colon is an ordinary symbol character.** `foo:i32` and `foo:ptr:Node` lex
   as single `NODE-SYM`s; `split-typed` / `desugar-symbol` split them lazily.
2. **A colon-led atom is a `NODE-KEYWORD`** (reader.nuc:328, Stage 11 cleanup
   §2): `:i32` lexes as a keyword carrying `"i32"` — only the *first* colon is
   stripped, so `:ptr:Node` is one keyword carrying `"ptr:Node"`. This is why
   `(fn (x:i32):i32 …)` works today: after the params' `)`, the atom `:i32`
   lands as a keyword node at the next list index.
3. **Colon-paren fuse** (reader.nuc:782, `fuse-colon-paren`): in list context,
   `name:(ref (Vector T))` fuses to the list node `(name (ref (Vector T)))`.
   The fuse requires a *named* symbol ending in `:`; a **lone `:` before `(`
   does not work** — `):( ` mis-lexes (this is the "colon-paren caveat" noted
   at emit-fn). Consequence: a parenthesized return type in the new position
   is spelled **space-separated**, exactly as `fn` accepts it today:
   `(defn next (params) (Maybe i32) …)`.
   **Update (2026-07-02):** [colon-paren-types.md](colon-paren-types.md) CP-2
   has **landed** — the lone-colon fuse (`:(T…)` → the paren form itself) is
   implemented in `fuse-colon-paren`, so this exception is now retired:
   `(defn next (params):(Maybe i32) …)` works and the S3 mechanical rewrite
   can emit `):(…)` uniformly. The space-separated form stays accepted either
   way.
4. Keyword nodes are otherwise value literals (`lib/keyword.nuc`) — using one
   in ret position is positional, not a new node kind.

### The `fn` precedent — the target grammar already exists

`fn-parse-ret-type` (src/nucleusc.nuc:3092) is the exact grammar we want for
the defn ret operand. It accepts, at a fixed index after the param list:

- `NODE-KEYWORD` — `:i32`, `:ptr:Node`, `:!T`, `:?ptr:Node` … The keyword's
  name goes to `parse-type-name`, which handles colon chains (delegates to
  `parse-type-from-node` via `split-colon-segments`, union-registry.nuc:244)
  and the `?`/`!`/`?!` sugars. All existing defn return spellings are covered.
- `NODE-SYM` — a space-separated bare type name.
- `NODE-CELL` — a parenthesized list-form type: `(ref T)`, `(Maybe i32)`,
  `(ref (Vector ptr))`.

`emit-fn` (nucleusc.nuc:3111) fixes ret at index 2 unconditionally; defn's new
style fixes it at index 3. **The return type stays mandatory** (emit-defn
already dies on a missing `:type`), which is what keeps parsing unambiguous —
index 3 is *always* the ret operand, never the first body form.

### Current defn anatomy and its satellites

`(defn name-node params-node body…)` where:

- **name-node** is either a `NODE-SYM` `name[:ret[:ret2…]]` (multi-colon
  desugars to a list) or a `NODE-CELL` `(name ret-form)` (the list-head form
  for parenthesized types, also produced by the colon-paren fuse). Ret is
  recovered by `extract-name-and-type` (nucleusc.nuc:695).
- **params-node** — unchanged by this design. `&rest`/`&optional` markers and
  the **`&where` clause live inside the param list**
  (`(defn max:T (a:T b:T &where (Ord T)) …)`, generics.nuc:532), so generic
  templates are unaffected structurally.
- **`noreturn`** — an attribute symbol at body-position 0 (index 3,
  emit-defn:6885). In the new style it shifts to index 4 (after the ret).
- **body** starts at index 3 (4 with noreturn).

`defn-` (private), `declare`, `defprotocol` method signatures, and the `.nuch`
`defmethod`/`declare` entries all reuse the same `name:ret` convention — see
"Scope decisions".

---

## Every consumer of the defn shape

The refactor's correctness hinges on finding *all* readers and synthesizers of
the `name:ret` convention. Ground-truthed inventory (2026-07):

### Read sites (parse ret / body-start from a defn form)

| Site | Location | Notes |
|---|---|---|
| `emit-defn` | nucleusc.nuc:6845 | ret + noreturn + body-start |
| `prescan-defn-signatures` | nucleusc.nuc:8047 | whole-unit signature prescan; routes templates to `register-generic-defn` |
| `compile-time` block prescan | nucleusc.nuc:7243 | registers defn sigs for JIT'd blocks |
| `desugar-form` defn branch | nucleusc.nuc:7801 | desugars name + params, rebuilds `(defn name params body…)` — the ret keyword rides in the body tail untouched; new-style name desugar becomes a no-op |
| generic template registration | generics.nuc:~517 | extracts ret from `(node-at form 1)`; templates retained as **source nodes** |
| template stamping | generics.nuc:~1304 (+ `split-typed` uses at 1368/1401/1541/1755) | re-extracts ret from the stamped form; tyvar substitution operates at colon-*segment* level on the name symbol today |
| protocol method sigs | generics.nuc:~2563 | `(area:i32 (self:ptr:Self))` inside `defprotocol` |
| `extend` / conformance checks | generics.nuc:~3092/3325 | method-sig comparisons |
| C header generation | cheader.nuc:1031 (`emit-cheader-declare`) | reads defn name:ret |
| `.nuch` export | nuch.nuc:169→ (`emit-nuch-defn`, extract at 218/289) | writes `defmethod`/`declare` entries; exports generic-template defns **verbatim** (`print-node`) |
| `.nuch` import | nuch.nuc:371 (`defn`→`register-generic-defn`), `defmethod` import (nuch.nuc:~280), `declare` import (nuch.nuc:~205) | all extract `name:ret` |
| REPL redefinition | repl.nuc:209 | defn redefinition path |
| `declare` toplevel form | nucleusc.nuc (declare handler) | `(declare name:ret (params…))` |

### Synthesis sites (build `name:ret` symbols, all compiler-internal)

| Site | Location | What it builds |
|---|---|---|
| lambda lift | nucleusc.nuc:3175 | `(intern-symbol (fmt-2s "%s:%s" lifted (type-spelling ret)))` — synthesizes a defn for the mono worklist |
| closure invoke/drop | nucleusc.nuc:3642, 3750 | same pattern for `vfn`/`mfn`/`cfn` env methods |
| defunion arm ctors | nucleusc.nuc:6726 | `Name-arm:Name` ctor defns |
| type-erasure forwarding methods | generics.nuc:2280/2316 | `method:retspelling` forwarding defn |
| generic stamping | generics.nuc (instantiation) | `mangled:retspelling` stamped names |

**No macros outside the compiler generate defn forms** (verified: no
`` `(defn ``/`intern-symbol "defn"` in lib/, examples/, tests/), so the
synthesis inventory above is closed.

---

## Design

### Target grammar

```
(defn  NAME PARAMS RET [noreturn] body…)
(defn- NAME PARAMS RET [noreturn] body…)
```

- `NAME` — bare `NODE-SYM`, no colon (final state; a colon is a legacy-style
  marker during migration, an error after).
- `RET` — exactly `fn-parse-ret-type`'s operand grammar: `NODE-KEYWORD`
  (`:i32`, `:ptr:Node`, `:!T`, `:?ptr:Node`), bare `NODE-SYM`, or `NODE-CELL`
  (`(Maybe i32)`, `(ref (Vector ptr))`). Mandatory, index 3.
- `noreturn` moves from index 3 to index 4; body starts at 4 (5 with
  noreturn).

Style guidance for the rewrite: keep the keyword spelling (`):i32`,
`):ptr:Node`) wherever the type has a colon-chain spelling; use the
space-separated list form only for parenthesized types (which today use the
list-head form). Do **not** attempt `):( …)` — the reader caveat above.

### One central accessor: `defn-parse-sig`

Add a single helper (nucleusc.nuc, near `extract-name-and-type`) that all read
sites route through:

```
defn-parse-sig(form, out-name, out-ret-node, out-params, out-body-start) → style
```

- If `(node-at form 1)` is a `NODE-SYM` containing `:`, or a `NODE-CELL` →
  **legacy**: ret from the name node (existing `extract-name-and-type` path),
  body-start 3.
- Else → **new style**: name is the bare symbol, ret-node is
  `(node-at form 3)`, body-start 4.
- Returns the **ret node**, not a parsed `Type*`: the template-registration
  path must *not* eagerly `parse-type-name` a free-tyvar return (`TY-TYVAR`
  confinement — conventions.md), and the stamper substitutes into the node.
  Non-generic callers parse it with (a generalized) `fn-parse-ret-type`.
- Missing/unparseable ret with a bare name produces the targeted diagnostic:
  `defn 'foo': expected return type after the parameter list, e.g.
  (defn foo (params):i32 …)` — this is also the error legacy spellings get in
  Phase S4, so stale code self-explains.
- `fn-parse-ret-type` is generalized (form-name parameter in the diagnostic)
  and shared between `emit-fn` and the new-style defn path — the two grammars
  must not drift.

Keyword nodes may carry line 0 (interned atoms); diagnostics must use the
*form's* line (same rule as `emit-ns`, nucleusc.nuc:8104).

### Scope decisions (what else migrates)

| Form | Decision | Rationale |
|---|---|---|
| `defn-` | **Yes** | same code path, free. |
| `defprotocol` method sigs | **Yes** — `(area:i32 (self:ptr:Self))` → `(area (self:ptr:Self):i32)`; list-form heads `((next (Maybe Elem)) (params))` → `(next (params) (Maybe Elem))` | the uniformity argument is identical; leaving them old-style would preserve the duplicated convention forever. Parsed at generics.nuc:2563 + `.nuch` re-registration. |
| `declare` | **Yes** — `(declare name (params…):ret [noreturn])` | same helper; small count; keeps "function signature" a single grammar. |
| `.nuch` `defmethod` / `declare` entries | **Yes**, writer+reader in the same commit | machine-generated and regenerated each build; no compatibility window needed beyond the phase ordering below. |
| `defmacro` | No | macros have no return type; untyped params. |
| `defvar` / `defconst` / `extern` / struct fields / `let` bindings | **No** | `name:type` on a *binding* is the core binding syntax, not function-signature syntax. This design deliberately does not touch it. |
| internal synthesis (lambda lift, closures, arm ctors, forwarding, stamping) | **Yes**, in Phase S3 | switching a synthesized form's style is invisible in final IR (ir-names derive from the colon-stripped name and the types); `.nuch` text changes are an intermediate artifact. |

### Migration plan

Bootstrap constraint: the boot artifact (checked-in LLVM IR) must always be
able to compile `src/`. Hence dual-acceptance must be *in the boot* before any
source line is rewritten.

**Phase S1 — dual acceptance (no source rewrites).**
Implement `defn-parse-sig`, generalize `fn-parse-ret-type`, and route every
read site in the inventory through it (`emit-defn`, prescan, compile-time,
desugar, generics registration/stamping/protocol sigs, cheader, nuch
import/export readers, repl, declare). Synthesis sites stay old-style (zero
behavior change). Add tests exercising the new style end-to-end (see Test
plan). All existing source still parses as legacy. Gate: `make && make test &&
make bootstrap` green.

**Phase S2 — boot refresh.**
`make update-bootstrap`, then `make clean && make` (two-pass reconvergence,
conventions.md §macros/string-pool). The boot now accepts both styles. Commit
the refreshed artifact — everything after this point may use the new syntax.

**Phase S3 — the mechanical rewrite.**
A script (precedent: the `.`→head-position migration script) rewrites all of
`src/`, `lib/`, `tests/`, `examples/`:

- `(defn foo:ret (params…)` → `(defn foo (params…):ret` — **must be
  paren-aware, not line-regex**: param lists span multiple lines; the ret may
  be a colon chain (`foo:ptr:ptr:Node`) or carry `!`/`?` sugar.
- list-head form `(defn (next (Maybe T)) (params…)` →
  `(defn next (params…) (Maybe T)`.
- `noreturn` moves after the ret operand.
- protocol sigs and `declare` analogously.
- update the five internal synthesis sites + the `.nuch` writer to emit
  new-style.

Scale (2026-07 counts of old-style heads): **src 606, lib 234, examples 281,
tests 31** (~1,150 defn forms), 36 list-head forms, plus protocol sigs and
`declare`s.

**Verification — emitted-IR identity** (the CStr-migration technique,
conventions.md): snapshot `build/nucleusc.ll`, run the rewrite, rebuild with
the S2 boot, `diff`. The diff must be empty: ir-names derive from the
colon-stripped name (`defn-ir-name`), types parse identically through either
style, string *literals* are untouched, and no user macro quasiquotes a defn.
A non-empty diff is a rewrite bug — fix forward (never `git restore`). Note
`make bootstrap` does **not** prove behavior-neutrality here (both stages
share the rewrite); only the before/after diff does. `.nuch` text is expected
to change (templates export verbatim); that artifact is regenerated per build
and excluded from the identity check.

**Phase S4 — retire the legacy style.**
`make update-bootstrap` again (boot is now built from new-style source). Then
make a colon-bearing defn/protocol/declare name a **hard error** with the
targeted diagnostic from `defn-parse-sig` (keep the cheap colon *detection*
precisely so the error can say what moved). Rewrite the ~116 defn mentions in
`docs/` and any design-doc examples that claim to describe current syntax;
final `make && make test && make bootstrap`.

### Ordering relative to the rest of Stage 14

Independent of [type-safety.md](type-safety.md) semantically, but it rewrites
**every signature line in the tree** — the same lines phase 14.3
(param/return typing) edits. Do this migration **first**, or in a window when
no 14.x signature work is in flight, to avoid a cross-cutting merge mess.

### Risks / gotchas (ground-truthed)

- **Stamping and tyvar substitution.** Generic templates keep their *source
  form*; today the stamper rewrites the name symbol to `mangled:retspelling`
  and `subst-tyvars` substitutes at colon-segment level in symbols
  (conventions.md §defn-bodies-not-desugared). With a new-style template
  (`(defn max (a:T b:T &where (Ord T)):T …)`) the ret tyvar lives in a
  `NODE-KEYWORD`'s spelling — the substitution/stamp path must handle keyword
  nodes (or the stamper swaps the ret node wholesale). This is the one
  genuinely fiddly consumer; route it to a careful implementer with
  conventions.md read first.
- **`desugar-form`** rebuilds `(defn name params body…)` — verify the ret
  operand (index 3) survives in the rebuilt tail for new-style forms (it is
  part of the "body…" tail there) and that a bare name is a desugar no-op.
- **Diagnostics lines**: interned keyword/symbol nodes can carry line 0 — use
  the form's line.
- **The rewrite script** must handle multi-line param lists, comments between
  head and params, and strings containing `(defn ` (docs code blocks are
  rewritten deliberately; `.ll`/`.nuch` build artifacts are not inputs).
- **`?`/`!` in names** (conventions.md) is orthogonal — unchanged.
- **String-pool shifts**: the rewrite changes symbol spellings, not string
  literals, so no pool shift is expected; if the IR diff shows `.str` renumbering,
  a literal was touched — investigate, don't reconverge over it.
- **House rule**: a failed build mid-migration is fixed forward at file:line;
  destructive git commands are never the recovery path.

### Test plan

Phase S1 adds (and S4 flips the legacy ones to expect-error):

- new-style defn: keyword ret (`:i32`), colon-chain ret (`:ptr:Node`), sugar
  rets (`:!i32`, `:?ptr:Node`), space-separated list-form ret
  (`(Maybe i32)`, `(ref (Vector ptr))`), `:void`.
- `noreturn` in the new position; `&rest`/`&optional`/`&where` with new style.
- generic template with tyvar ret in new style + call-site stamping.
- new-style `defprotocol` sig + `extend` conformance; parametric protocol.
- cross-unit: new-style defn exported/imported via `.nuch` (template and
  plain), C header generation, REPL redefinition of a new-style defn.
- diagnostics: missing ret (`(defn foo (x) x)`), legacy spelling after S4.

Gates at every phase: `make`, `make test`, `make bootstrap`; the S3 IR
identity diff.

---

## Status

Design written 2026-07-02; not yet implemented. Phases S1–S4 pending.
