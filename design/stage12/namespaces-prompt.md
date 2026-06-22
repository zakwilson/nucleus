# Modules and namespaces — implementation prompt

You are implementing namespaces, public/private symbols, the new import forms, and
the subsequent compiler split for Nucleus. The full design and rationale live in
[namespaces.md](namespaces.md); **read it first** — this file is the condensed build
order, the task split for the local subagents, and the acceptance gates. Read
namespaces.md for the *why*; read this file for *what to build, in what order, and
who builds it*.

## How to run this (orchestration)

This is a multi-phase compiler task. **Do not implement it in the orchestrating
thread.** Split it into the tasks below and dispatch each to the named local agent
(roster: [context/local.md](../../context/local.md)). Keep the main thread for
planning and integration only.

**Context-budget rule — keep every task well under 100K tokens.** `src/nucleusc.nuc`
is ~13.9K lines; an agent that reads it whole will blow its budget. Every task below
names the *specific functions / line anchors* to read. **Line numbers are approximate
anchors and will have drifted — grep by name.** Instruct each agent to read only the
named functions plus namespaces.md and this file, mirror existing mechanisms rather
than invent parallel ones, and return a concise summary (what changed, which
functions, surprises), not file dumps.

**Dependency order.** `N1` (namespace core) gates everything. `N2` (imports) and `N3`
(privacy) both depend on `N1` and touch the same file — **dispatch sequentially**, not
in parallel. `N4` (IR mangling) depends on `N1`–`N3` and is where IR can first diverge.
`N5` (export) depends on `N2`/`N4`. `N6` (tooling/`.nuch`) depends on `N4`. `N7`
(source migration) depends on `N2`–`N6`. `N8` (compiler split) depends on `N7`. `N9`
(docs) is last.

**After every implementation task**, dispatch **build-test-runner** to run `make test`
+ `make bootstrap` and confirm the boot artifacts re-converge. Do not start the next
task until the tree is green.

## Authoritative decisions (do not re-litigate)

From namespaces.md, including the resolved questions:

1. **`ns` sets the current namespace; default is `user`.** One `ns` per file
   (`export` aside). A second `ns`, or `ns` of an existing namespace, **warns** at
   compile time but is **silent in the REPL**. `ns` is deliberately minimal — it does
   nothing else (no Clojure-style `:require`).
2. **Slash is a resolver concern, not a lexer rewrite.** `/` is already a symbol
   character (`lib/reader.nuc:82`), so `foo/bar` reads as one `NODE-SYM` today. The
   **first interior slash** divides namespace from name; a leading/trailing slash is
   part of the name (so bare `/` is the division op, `_/` is untouched, `foo//bar` is
   `/bar` in `foo`). Slash is forbidden inside a namespace name.
3. **Public by default; `name-` definers are private.** Private = not importable from
   another namespace, **plus** internal LLVM linkage for forms that emit a link symbol
   (`defn-`, `defvar-`). Compile-time-only forms carry no linkage dimension. The
   private definers are exactly the name-introducing forms: `defn-`, `defvar-`,
   `defconst-`, `defenum-`, `defstruct-`, `defunion-`, `defmacro-`, `defprotocol-`.
   `extern`/`declare`/`extend`/`defcast`/`def-rmacro` get **no** private variant.
4. **Private types are allowed**, opaque through a public signature, with a warning —
   suppressed under `import-use`.
5. **Import forms:** `import` (prefix-qualified, prefix defaults to the lib name),
   `import-use` (old flatten-everything behavior; fine for REPL/libs), `import-only`
   (explicit symbol list), `unsafe-import-private` (namespace + prefix + `&rest`
   private symbols). Two imports may not share a prefix (error); the same lib under two
   prefixes is allowed; dedup is keyed on **(file, prefix)**. `include` is **removed**;
   C headers come through the import forms with a string path.
6. **`export`** re-exports an explicit symbol list under the host namespace's qualified
   name, reusing the original `ir-name` (an alias, no new code).
7. **IR mangling:** namespace name (or `set-ir-prefix`) lowers to a deterministic,
   C-legal prefix (`foo/bar` → `foo__bar`), composing **before** existing method/
   instance mangling (`Name.tok.tok`, `Vector.i32`). `set-ir-prefix` applies to the
   current namespace; **null/empty = no prefix = bare names**. The default `user`
   namespace has an empty prefix.
8. **Foreign (C-imported) symbols are never re-mangled** — their `ir-name` is the bare
   link name from the header, regardless of importing-namespace prefix (`c/printf` →
   `@printf`).
9. **Conformance/protocol facts stay global**, keyed on fully-qualified type+protocol
   identity.

## Non-negotiable invariants

- **The feature is additive at the IR level.** This is the analogue of the
  parametric-struct "inert until a stamp fires" property: code that stays in `user` and
  `import-use`s its dependencies emits **bare ir-names**, byte-identical to today.
  Mangling only bites when a file declares a non-`user` namespace or sets a prefix.
  **The compiler and libraries are not migrated to namespaces until N7/N8**, so
  `make bootstrap` must stay a fixed point and the boot artifacts (Linux + Windows IRs,
  `bin/nucleusc`) byte-identical through N1–N6. A diff in those phases is a bug.
- **Keep every step green.** This *is* a breaking change to the source surface, so do
  it opt-in-then-flip (the Stage 10 Phase F pattern): N2 **adds** the new forms while
  `import`/`include` keep their **current** behavior as aliases; the source is migrated
  in N7; only **then** is `import` flipped to prefix-required semantics and the
  `include` keyword deleted. At no intermediate commit may the tree fail to build or
  bootstrap.
- **C-ABI neutrality.** A public symbol's link name is its `ir-name`; namespacing
  changes *resolution*, not the C ABI. Exported names reaching C/`.nuch`/`--emit-cheader`
  must be C-legal (the `foo__bar` sanitization).
- **Zero overhead.** Resolution is compile-time only. No runtime namespace object, no
  dispatch indirection, no per-call cost.

---

## N1 — Namespace core: state, `ns`, qualified resolution

**Agent: systems-impl-engineer.** The meatiest, mechanism-defining task; gates the rest.

**Read (scoped):** `Sym` struct (src:231, the `name`/`ir-name` split — the whole
feature rides on this); `g-globals` (src:600); `scope-new`/`scope-define`/`scope-lookup`
(src:2919/2924/2943); the top-level form dispatch and how a bare symbol resolves to a
global (`emit-toplevel-forms` src:12806, and the body emitter's symbol-lookup path);
`prepend-prelude-import`/`strip-exclude-prelude` (src:13776/13762, the first-form
directive pattern `ns` mirrors); `lib/reader.nuc` `is-sym-char` (line 82) and the atom
scanner (~205) to **confirm no reader change is needed** for slashes.

**Build:**

1. A `g-current-ns` global (default `"user"`) and an `ns` top-level form that sets it.
   Mirror `exclude-prelude`'s first-form handling. A second `ns` / re-entry **warns**
   at compile time, **silent** under the REPL flag.
2. A `qualify-name` resolver step: given a source spelling, split on the **first
   interior slash** into (namespace, name) per decision 2 (leading/trailing slash stays
   in the name). An unqualified name resolves against `g-current-ns`.
3. **Storage keying:** globals are interned in `g-globals` under their **fully-qualified
   key**, except the `user` namespace stores **bare** keys, so existing lookups are
   unchanged. (Equivalently: `user/bar` and `bar` are the same key.) Define and lookup
   both route through `qualify-name`. The import **alias** layer (N2) injects additional
   keys pointing at the same `Sym`.

**Done when:** `(ns foo)` sets the namespace; defining `bar` in `foo` and referencing
it as `bar` (within `foo`) or `foo/bar` (elsewhere) resolves to the same `Sym`; a second
`ns` warns (compile) / is silent (REPL); a bare `/` still parses as division. **No code
stays in a non-`user` namespace yet, so bootstrap is byte-identical.** →
**build-test-runner.**

---

## N2 — Import forms (additive; old forms kept as aliases)

**Agent: systems-impl-engineer.** Depends on **N1**. Dispatch after N1 lands.

**Read (scoped):** `emit-import` (src:12977), `resolve-import` (src:12968),
`try-import-path` (src:12929), `import-list-has`/`import-list-push`/`import-list-pop`
(src:12889–12913, the dedup machinery), the `"include"` handling (grep `"include"`,
src:~12010/13523), `prescan-imported-types` (src:12634).

**Build:**

1. `import-use` = today's `import`/`include` flatten-everything behavior (factor it out;
   leave `import`/`include` calling it for now so existing source still builds).
2. `import` with an optional prefix symbol (default = lib name): inject the imported
   public symbols as `prefix/name` **alias keys** into the current namespace's view
   (pointing at the same `Sym`s). `import-only` takes an explicit symbol list.
   `unsafe-import-private` takes namespace + prefix + `&rest` private symbols.
3. **Dedup** keyed on **(file, prefix)** (extend `import-list-*`); same prefix from two
   imports → error; same file under two prefixes → allowed.
4. **C headers** flow through the same forms with a **string path**; foreign symbols
   keep their bare `ir-name` (decision 8). Keep `include` working as an alias for now.

**Done when:** `import-use`/`import`/`import-only`/`unsafe-import-private` all work;
prefixed import exposes `prefix/name`; collision and alias rules hold; a C header imports
and `c/printf` calls `@printf`. **Existing `import`/`include` unchanged → bootstrap
byte-identical.** → **build-test-runner.**

---

## N3 — Public/private + internal linkage

**Agent: focused-task-implementer.** Depends on **N1**. Dispatch after N2.

**Read (scoped):** `emit-defn` (src:11589) and its `define` line (src:11794);
`emit-defvar` (src:11255) and its `= global` line (src:11280); the existing
`define private`/internal-linkage emission already used for compiler-internal JIT
helpers (grep `define private`, src:~12061); the definer dispatch (grep `"defn"`/
`"defvar"`, src:~13523); how a symbol records visibility (add a flag to `Sym`/`Generic`).

**Build:** parse the `name-` definer spellings (decision 3) → mark the symbol **private**
(not importable). For link-emitting forms (`defn-`, `defvar-`) additionally emit
**internal** linkage (reuse the `define private` / `private global` form). Importers skip
private symbols (except `unsafe-import-private`). Add the **opaque-type warning** when a
private type appears in a public signature — **suppressed under `import-use`**.

**Done when:** a `defn-`/`defvar-` symbol is internal-linkage and not importable;
private compile-time forms are not importable; the opaque-type warning fires under
`import` and is silent under `import-use`. **Bootstrap byte-identical** (no compiler
symbol is private yet). → **build-test-runner.**

---

## N4 — IR mangling + `set-ir-prefix` + cross-namespace conformance

**Agent: systems-impl-engineer.** Depends on **N1**–**N3**. The first task where IR can
diverge — but only for non-`user` namespaces, so the compiler stays byte-identical.

**Read (scoped):** `type-mangle-token` (src:4431), `mangle-fn-name` (src:4487),
`finalize-generics` (src:4683) and the `Generic` `mangled` field (src:~377); the
mangled→C-legible sanitizer (grep `sanitize`); `register-imported-conformance`
(src:7196) and the conformance/protocol registries; the `Sym` `ir-name` assignment in
`scope-define` (src:2937).

**Build:**

1. Compute a symbol's `ir-name` from `<ns-prefix>__<name>` where `ns-prefix` is the
   `set-ir-prefix` value or the namespace name. **`user`/empty → bare name** (the
   byte-identity escape hatch). Namespace prefix composes **before** method/instance
   mangling (so an overloaded `foo/bar` is `foo__bar.tok.tok`).
2. `set-ir-prefix` form: set the current namespace's ir-prefix; null/empty = bare.
3. **Foreign symbols exempt** (decision 8) — never re-mangle a header symbol's `ir-name`.
4. **Conformance/protocol identity** (decision 9): key the registries on the
   **fully-qualified** type+protocol identity so `(extend coll/Vector coll/Seq)` resolves
   from any namespace. Verify a `Seq`-bounded generic call dispatches across a namespace
   boundary.
5. C-legible export name available for N6.

**Done when:** a symbol in namespace `foo` emits `@foo__bar`; the same symbol in `user`
emits `@bar` (bare); `set-ir-prefix ""` forces bare; a cross-namespace conformance
dispatches. **Bootstrap byte-identical** (compiler is still all-`user`). →
**build-test-runner.**

---

## N5 — `export` re-export

**Agent: focused-task-implementer.** Depends on **N2**/**N4**.

**Read (scoped):** the N1 alias mechanism; `emit-import`/the alias-injection path from
N2; `emit-nuch-import-forms` (src:13355) for how re-exports surface to importers.

**Build:** `export` takes an explicit symbol list; each becomes visible under the host
namespace's qualified name, reusing the original `ir-name` (alias, no code emitted). A
facade namespace re-exporting from its dependencies (the `lib/string.nuc` shape) is the
target use case.

**Done when:** `(export strview/find)` in namespace `string` makes `string/find`
resolve to the same `Sym`/`ir-name`; an importer of `string` sees it. **Bootstrap
byte-identical.** → **build-test-runner.**

---

## N6 — `.nuch` round-trip + tooling

**Agent: systems-impl-engineer** (`.nuch`) + **focused-task-implementer** (REPL/cheader).
Depends on **N4**.

**Read (scoped):** `emit-nuch-defstruct`/the `emit-nuch-*` family (src:13046–13355);
`g-emit-cheader`/`emit-cheader-header` (src:769/13884); the REPL `apropos`/`locate`/`doc`
sites and the `Sym` introspection fields (`src-file`/`src-line`/`docstring`, src:~238)
in `src/repl.nuc`.

**Build:** `.nuch` export/import carries the namespace so an imported symbol re-resolves
under its qualified name with the correct `ir-name`; `--emit-cheader` emits the C-legible
`foo__bar` names; `apropos`/`locate`/`doc` are namespace-aware (qualified display,
namespace-scoped search).

**Done when:** a namespaced library exports `.nuch`, an importer re-resolves it;
`--emit-cheader` is C-legal; REPL tooling shows/searches qualified names. **Bootstrap
byte-identical.** → **build-test-runner.**

---

## N7 — Migrate the tree, then flip (the breaking step)

**Agent: focused-task-implementer** for the mechanical rewrite; **systems-impl-engineer**
for the flip. Depends on **N2**–**N6**.

This is the Phase-F-style flip. Do it in this order, green at each sub-step:

1. **Rewrite** every `(include X)` → `(import-use "X.h")` and every existing `(import X)`
   → `(import-use X)` across `src/`, `lib/`, `examples/`. Pure source change; **IR must
   stay byte-identical** (same bare names, same flatten behavior). Keep the compiler and
   libs in the `user` namespace with empty prefix.
2. **Flip `import`** to the new prefix-required semantics and **delete the `include`
   keyword** (now unused). Re-run boot — still byte-identical, because nothing that
   builds the compiler depends on the old `import` spelling anymore.

**Done when:** no `include` keyword remains; `import` means prefix-qualified everywhere;
the compiler/libs/examples build and bootstrap **byte-identical** to before the stage. →
**build-test-runner.**

---

## N8 — Compiler split (one file at a time)

**Agent: systems-impl-engineer**, iterative. Depends on **N7**.

namespaces.md: once namespaces are stable, move as much as practical out of the
~13.9K-line core into separate files with a clean public interface, imported back.

**Method — pure byte-identical code motion:**

- Split **one file at a time**; **bootstrap + test after each** before the next.
- Keep each split-out module in the **`user` namespace with empty prefix** (or
  `import-use`d) so moved symbols keep their **bare ir-names** and the boot stays
  byte-identical. Code motion only — do **not** rename symbols or introduce real
  namespaces/privacy in the same step.
- Introducing genuine namespaces/privacy on a module (which *will* re-mangle its
  ir-names and re-converge boot) is a **separate, deliberate** follow-up per module,
  never bundled with the move.

**Done when:** the core is materially smaller, each extracted module imports cleanly, and
every intermediate state bootstrapped byte-identical. → **build-test-runner** after each
extraction.

---

## N9 — Docs, examples, progress (close-out)

**Agent: api-docs-writer** (+ **focused-task-implementer** for example code).

- `examples/namespaces.nuc` (+ `tests/expected/`) exercising `ns`, prefixed `import`,
  `import-only`, a private `defn-`, an `export` facade, and `c/printf`. Wire into
  `make test`.
- Update [docs/toplevel.md](../../docs/toplevel.md) (`ns`, the import forms, `export`,
  `set-ir-prefix`, the `name-` private definers; remove `include`), and any of
  `docs/compiler.md`/`docs/builtins.md`/`docs/stdlib.md` touching imports.
- Append a **"Robot — implementation status"** section to
  [namespaces.md](namespaces.md) recording what landed and any decision the
  implementation sharpened.
- Add a Stage 12 entry to [progress.md](progress.md); create
  `design/stage12/progress.md` for the detailed table; add both docs to
  [overview.md](../overview.md).

---

## Explicitly out of scope (do not build)

- **Namespace-qualified keywords** (`:foo/bar`).
- **Clojure-style `ns` options** (`:require`/`:refer`/`:as` blocks) — `ns` only sets the
  namespace; imports stay separate forms.
- **Multi-file namespaces** beyond `export` re-export — one namespace per file.
- **Private `defcast`/`def-rmacro`/`extend`** (namespace-scoped global facts) — deferred.
- **Renaming compiler symbols / per-module namespacing** during the N8 split — N8 is
  byte-identical code motion only; real namespacing of the compiler is a later pass.

## Close-out checklist (required by AGENTS.md)

- After **every** task: `make test` + `make bootstrap` green, compiler compiles itself —
  via **build-test-runner**.
- N1–N6 stayed byte-identical (compiler still all-`user`); N7 stayed byte-identical
  (source-only flip); N8 stayed byte-identical per extraction.
- N9 docs/progress/overview updates landed.
</content>
</invoke>
