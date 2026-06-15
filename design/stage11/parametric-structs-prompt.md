# Parametric structs — implementation prompt

You are implementing generic structs for Nucleus. The full design, rationale, and
hook points live in [parametric-structs.md](parametric-structs.md); **read it
first** — this file is the condensed build order, the task split for the local
subagents, and the acceptance gates. Read parametric-structs.md for the *why* and
the mechanism; read this file for *what to build, in what order, and who builds it*.

This feature is the deferred-since-Stage-9 "parametric generics" rung and the hard
prerequisite for Stage 11 collections ([collections.md](collections.md)).

## How to run this (orchestration)

This is a multi-phase compiler task. **Do not implement it in the orchestrating
thread.** Split it into the tasks below and dispatch each to the named local agent
(roster: [context/local.md](../../context/local.md)). Keep the main thread for
planning and integration only.

**Context-budget rule — keep every task well under 100K tokens.** `src/nucleusc.nuc`
is enormous; an agent that reads it whole will blow its budget. So every task below
names the *specific functions / line anchors* to read, modeled on the matching
union-template code. Instruct each agent to:

- read only the named functions (grep by name — **line numbers are approximate
  anchors and will have drifted**), plus parametric-structs.md and this file;
- mirror the existing union-template / monomorphizer code rather than invent a
  parallel mechanism;
- return a concise summary (what changed, which functions, any surprises), not file
  dumps.

**Dependency order:** `T0` is independent (do first). `T1` is the core and gates the
rest. `T2`, `T3` both depend on `T1` and are logically independent but touch the same
file — **dispatch them sequentially**, not in parallel, to avoid merge friction.
`T4` depends on `T1`+`T2`; `T5` depends on `T1`. `T6` (docs) is last.

**After every implementation task**, dispatch **build-test-runner** to run
`make test` + `make bootstrap` and confirm the boot artifacts re-converge. Do not
start the next task until the tree is green.

## Authoritative decisions (do not re-litigate)

From parametric-structs.md, including the resolved open questions:

1. **Reuse, don't parallel.** Struct templates are the union-template mechanism
   applied to `defstruct`; methods reuse the rung-4 monomorphizer (`monomorphize-form`)
   unchanged. Any new code that duplicates `union-template-*`/`subst-tyvars-*` instead
   of mirroring it is wrong.
2. **Type parameters only** (no value/const params, no higher-kinded params, no
   variance). `(Vector Cat)` is unrelated to `(Vector Animal)`.
3. **Index scalars are `usize` (unsigned) + `ssize` (signed)**, pointer-sized via the
   target descriptor (decision §8/OQ4).
4. **Method tyvars are inferred from the parametric receiver** (OQ2); `&where` stays
   available only for *extra* bounds.
5. **Construction:** type application `(Vector i32)` is recognized in **type position
   only**; value-position construction is the explicit `((Vector i32) v0 …)`; bare
   `(Vector v0 …)` for a template name is an **error** (OQ3).
6. **Conformance errors fire at stamp time** (OQ5), naming the missing method.
7. **Parametric protocols** `(Protocol Self E…)` with the element bound at `extend`
   are the v1 answer; full associated types stay deferred (OQ1).

## Non-negotiable invariants

- **Zero overhead.** A stamped instance must be byte-identical IR/layout/ABI/`sizeof`
  to the same struct written by hand. Field access on a stamped instance is the same
  static GEP+load as any concrete struct. No dispatch object, no RTTI.
- **Byte-identical bootstrap throughout.** The template registry is *inert until a
  stamp fires*, exactly like union templates — so every task here must keep
  `make bootstrap` a fixed point and the boot artifacts (Linux + Windows IRs,
  `bin/nucleusc`) byte-identical. **Nothing in this prompt makes the compiler adopt a
  parametric struct** (that is Stage 11 collections, a later pass), so there is no
  legitimate reason for the bootstrap to diverge. A diff means a bug.
- **C-ABI neutrality.** A stamped instance is an ordinary monomorphic `TY-STRUCT`; the
  Stage 8 SysV classifier applies unchanged. Cross-language consumption works through
  a C-legible exported name.
- **Library where possible.** This rung is compiler machinery, but the collection
  *protocols* it enables (`Coll`/`Seq`/…) are library code (Stage 11) — do not pull
  any collection types into the compiler here.

---

## T0 — `usize` / `ssize` builtin scalars

**Agent: focused-task-implementer.** Small, well-specified, independent; unblocks
every signature in the later tasks.

**Read (scoped):** `parse-type-name` (src:~1633, the scalar-name `when` ladder where
`i64`/`ui64` are returned); the pointer-sized-integer IR helper (src:~901, "size_t /
intptr_t for the target"); `g-target-ptr-bytes` and how `sizeof` (src:~5919) derives a
pointer-sized integer; `type-to-ir` for scalar singletons. Grep for `ty-ui64`/`ty-i64`
singleton definitions.

**Build:** two new builtin scalar `Type` singletons, `usize` (unsigned) and `ssize`
(signed), that resolve in `parse-type-name` to a target-pointer-sized integer via
`g-target-ptr-bytes` (4 bytes ILP32 → `i32`, 8 bytes LP64 → `i64` in IR; signedness
tracked exactly like the existing `ui*`/`i*` split for comparisons, division, and
printing). They are *distinct named types* at the source level but lower to the
target's pointer-sized integer in IR. Make sure `sizeof`/`type-size`, `type-to-ir`,
mangling (`type-mangle-token`), and `type-eq` all handle them.

**Done when:** `usize`/`ssize` parse in any type position, lower to the correct
target-sized integer, and round-trip through `sizeof`/mangling/`type-eq`; a tiny
example using `usize` compiles and runs. **Bootstrap byte-identical** (the compiler
uses neither yet). → **build-test-runner.**

---

## T1 — Template registry + stamping (the core)

**Agent: systems-impl-engineer.** This is the meatiest, most mechanism-heavy task and
gates everything after it.

**Read (scoped):** the whole union-template path as the blueprint —
`UnionTemplate` struct (src:~150), `register-union-template` (src:~2057),
`union-template-lookup` (src:~1736), `union-template-stamp-types` /
`union-template-stamp` (src:~2128), `subst-tyvars-node`/`subst-tyvars-sym`
(src:~4402/4380), `type-mangle-token` (src:~3915); the struct side —
`register-struct` (src:~1472), `emit-defstruct` (src:~9603), `lookup-struct`,
`type-for-sdef`, the `StructDef` `emitted` flag (src:~9614); the deferred-union-IR
queue (`drain-pending-union-irs`, grep it) and where it drains; `parse-type-from-node`
(src:~2152, esp. the `(Maybe …)`/`!T` list-head branch that already shows the
stamp-from-a-list-head pattern); and the **prescan** functions
(`prescan-struct-names`, `prescan-defn-signatures`, `prescan-imported-types` — grep)
so a `(Vector i32)` mentioned in a `defn` *signature* resolves.

**Build:**

1. A **`StructTemplate`** registry `{name, tyvars, ntv, form}` beside `UnionTemplate`,
   with `register-struct-template` (mirror `register-union-template`: a *list* name
   `(Vector T)` → name + tyvar-name array; retain the form; register no type, emit no
   IR; re-import is a no-op; `guard-name-kind` the name) and a `struct-template-lookup`.
2. Route `emit-defstruct` (src:~9603): a **list** name → `register-struct-template`; a
   symbol name → today's path unchanged. Register templates during the **prescan**
   pass (mirror `prescan-struct-names`/`prescan-imported-types`) so signatures that
   mention `(Vector i32)` parse.
3. **`struct-template-stamp-types`** mirroring `union-template-stamp-types`: mangle
   `Vector` + `.` + `type-mangle-token` per arg → `Vector.i32`; **memoize** via
   `lookup-struct`; on a miss, `subst-tyvars-node` over the retained field-spec list,
   feed the substituted `(defstruct Vector.i32 …)` through the existing `emit-defstruct`
   body under the mangled name, and **queue** its `%Vector.i32 = type {…}` IR line on
   the same deferred-emission discipline unions use (drain at top-level boundaries / the
   REPL preamble; the `emitted` flag guards double-emit).
4. **`parse-type-from-node`** (src:~2152): a list head naming a registered struct
   template routes to the stamp (model on the existing `(Maybe …)`/`!T` branch). The
   colon-sugar must compose: `ptr:(Vector i32)`, `(ref (HashMap CStr i32))`.
5. **Recursion:** a self-reference through a pointer (`(defstruct (Tree T) … (ptr (Tree T)))`)
   stamps (the name is reserved by `register-struct` before fields fill); a by-value
   self-embed is the existing infinite-layout error.

**Done when:** `(defstruct (Vector T) data:(ptr T) len:usize cap:usize)` registers and
emits nothing; `(Vector i32)` in a field type / `defn` signature / `cast` / `sizeof` /
`alloca` stamps a concrete `%Vector.i32` struct; field access and `sizeof` on it are
byte-identical to the hand-written equivalent; double-stamp is memoized; the pointer
self-reference case works. **Bootstrap byte-identical.** → **build-test-runner.**

---

## T2 — Methods over a parametric struct

**Agent: systems-impl-engineer.** Tyvar-from-receiver inference is the one genuinely
new piece; the stamping reuses the rung-4 monomorphizer.

**Read (scoped):** `monomorphize-form` (src:~4583) and the rung-4 `&where` generic
path (the instantiation worklist src:~578, `METHOD-GENERIC`/bounded-generic registry
fields around src:~319–350); the `defn` signature **prescan** and how `&where` tyvars
are currently collected; `generic-resolve`/`generic-find-method-exact` (grep) for how
a stamped method is selected; `node-type` for the receiver-type path. Depends on **T1**.

**Build:** when a `defn` parameter or return type mentions a registered struct
template applied to **free symbols** (`(Vector T)`, or a bare `T` that is one of the
template's params), treat those free symbols as the method's tyvars — *inferred from
the receiver*, equivalent to an `&where` list naming them. Queue the method for
monomorphization; each concrete receiver instance (`Vector.i32`) stamps the body via
`monomorphize-form` (`T` → `i32`). `&where` stays available purely for **extra bounds**
(`&where (T Ord)`). A resolved call (`(push v 3)`, `v : (ref Vector.i32)`) must be a
direct `call` (inlinable, no dispatch object); `(. v len)` stays a static GEP+load.

**Done when:** methods like `count`/`push` written over `(Vector T)` compile, stamp
per concrete instance, resolve to direct calls, and type-check (return/field types
substitute correctly); `&where` extra bounds still work. **Bootstrap byte-identical.**
→ **build-test-runner.**

---

## T3 — Construction + the compound-literal ambiguity

**Agent: focused-task-implementer.** Well-specified now that the surface is decided;
contained to the compound-literal sites. Depends on **T1**.

**Read (scoped):** the struct compound-literal / struct-name-as-constructor sites
(src:~8834 "(S e0 e1 …) compound literal", src:~9159 "struct-name-as-constructor");
how a struct name in head position is recognized today; `parse-type-from-node` (from
T1) for stamping the inner `(Vector i32)`.

**Build:** value-position construction is the **explicit** `((Vector i32) v0 v1 …)` —
the inner `(Vector i32)` stamps the concrete instance (T1), the outer application is
the ordinary compound literal over that instance. A **bare `(Vector v0 …)`** with a
template name in head position is a clear def-time **error** pointing at the explicit
form (it is ambiguous: type arg vs first field). Plain (non-template) struct compound
literals are untouched.

**Done when:** `((Vector i32) 1 2 3)` builds a `Vector.i32` value; bare
`(Vector 1 2 3)` errors with a message naming the explicit form; existing plain-struct
compound literals are unchanged. **Bootstrap byte-identical.** → **build-test-runner.**

---

## T4 — Parametric-protocol conformance

**Agent: systems-impl-engineer.** The element-binding generalization of `extend` is
new design surface. Depends on **T1** + **T2**.

**Read (scoped):** `emit-extend` (src:~2600) and the `g-protocols`/`g-conformances`
registries; `defprotocol` registration and how `Self` is substituted today
(`lib/seq.nuc`/`lib/numeric.nuc` show the `Self`-only protocols); the rung-2 checked
conformance path; the stamp site from **T1** (where the per-instance check must hook).

**Build:** support **parametric protocols** `(defprotocol (Seq E) (get:E (self:(ref Self) i:usize)) …)`
where the extra parameters beyond `Self` are bound at the `extend` site:
`(extend (Vector T) (Seq T))` binds `E := T`. This is a direct generalization of the
existing `Self`-only substitution — substitute the extra params alongside `Self` when
checking required-method signatures. **Conformance is checked at stamp time:** when
`Vector.i32` is stamped (T1), the required methods of any protocol the template extends
must resolve for that instance, else a def-time error naming the missing method. Full
associated types (element *derived from* `Self`) stay **out of scope** — the element is
always spelled explicitly at `extend`.

**Done when:** `(extend (Vector T) (Seq T))` records conformance; stamping `Vector.i32`
checks the required `Seq` methods resolve and errors (naming the method) if not; a
conforming instance satisfies a `Seq`-bounded generic call. **Bootstrap byte-identical.**
→ **build-test-runner.**

---

## T5 — C ABI + `.nuch` template export

**Agent: systems-impl-engineer.** Mostly mirrors union-template export; the
C-legible-name and importer re-stamp are the careful bits. Depends on **T1**.

**Read (scoped):** `emit-nuch-defstruct` (src:~11205) and the union-template `.nuch`
export/import path (how a `(defunion (Result T E) …)` template exports verbatim and the
importer re-registers + re-stamps; grep `emit-nuch` for the union-template branch);
`sanitize-for-ir` (src:~3965) and the mangled→C-legible name mapping; the Stage 8 ABI
sites only enough to confirm a stamped instance needs **no** special handling
(`abi-classify` already applies).

**Build:**

1. **`.nuch` export:** export the **template verbatim** (`(defstruct (Vector T) …)`)
   plus any stamped instances the unit used; the importer re-registers the template (a
   re-import is a no-op) and **re-stamps on demand**. Methods over the template export
   through the existing rung-4 generic `defmethod`/monomorphization export.
2. **C-legible name:** `Vector.i32` → a legal C identifier (e.g. `Vector_i32`) via the
   `sanitize-for-ir`-style mapping, so `--emit-cheader` and `.nuch` consumers see a
   valid name.
3. **ABI:** confirm (with a by-value param/return test across the C boundary vs system
   `cc`, in the spirit of `tests/abi/`) that a stamped instance goes through the
   existing SysV classifier unchanged — no new ABI code.

**Done when:** a parametric struct + its methods export to `.nuch`, an importing unit
re-stamps and uses them; `--emit-cheader` emits a C-legible name; a by-value ABI test
over a stamped instance matches `cc`. **Bootstrap byte-identical.** → **build-test-runner.**

---

## T6 — Examples, docs, progress (close-out)

**Agent: api-docs-writer** (docs/progress) with **focused-task-implementer** for the
example program if code is needed.

- Add `examples/parametric.nuc` (+ `tests/expected/parametric.out`) exercising
  `(Vector T)` definition, stamping, a method, construction via `((Vector i32) …)`, and
  a `(Seq T)` conformance — wire it into `make test`.
- Update [docs/builtins.md](../../docs/builtins.md): document `(defstruct (Name T …) …)`
  templates, `(Name T …)` type application, the `((Name T …) …)` constructor, the
  `usize`/`ssize` scalars, and parametric `defprotocol`/`extend`.
- Append a **"Robot — implementation status"** section to
  [parametric-structs.md](parametric-structs.md) (as unions.md/callable-values.md do),
  recording what landed and refining any decision the implementation sharpened; mark
  OQ2/OQ3/OQ5 resolved-as-recommended.
- Add a Stage 11 entry to [progress.md](progress.md) / create
  `design/stage11/progress.md` for the detailed table, and flip the "Parametric
  generics … unimplemented" row in the top-level Deferred list. Add any new docs to
  [overview.md](../overview.md).

---

## Explicitly out of scope (do not build)

- **Non-type / value parameters** (`(Array T N)` with integer `N`), partial
  application, higher-kinded params, variance/subtyping.
- **Full associated types** (element derived from `Self`) — parametric protocols with
  explicit element params are the v1 answer (T4).
- **Heterogeneous instances / `dyn`** — deferred to stage999.
- **The collection types themselves** (`Vector`/`HashMap`/…) and their protocols — that
  is Stage 11 [collections.md](collections.md), a *later* pass. This prompt builds only
  the generic-struct machinery they need.
- **Compiler adoption** of any parametric struct — keeps the byte-identical bootstrap
  intact; adoption is the end-of-stage collections step.

## Close-out checklist (required by AGENTS.md)

- After **every** task: `make test` + `make bootstrap` green, boot artifacts converged,
  compiler compiles itself — via **build-test-runner**.
- T6 docs/progress/overview updates landed.
- Bootstrap stayed byte-identical across the whole pass (no task here adopts a
  parametric struct in the compiler).
</content>
