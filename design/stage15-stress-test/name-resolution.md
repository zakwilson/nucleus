# Name resolution — one path, or many?

> **Status: investigation, 2026-08-08.** No code changed. Everything in §2 was
> measured against the committed compiler (`./build.sh` on probe files), not
> inferred from reading. The prompt was: *`examples/w9-dyn-ns.nuc` reaches a
> protocol as `dp/Describe` (the library's own namespace) when the consumer
> asked for it under the prefix `dpx`; the prefix should win and the namespace
> should be out of scope. Is a single resolution path feasible?*

**Verdict.** The diagnosis is right and understated. There are **three
incompatible key policies** across **eleven name-keyed registries**, and
`import-prefixed` is not a resolution mechanism at all — it is a post-hoc copy
of one registry's entries, filtered by two fields (`is-local`, `ir-name`) that
mean something else. The result is not "protocols leak"; it is that *every
kind of name has a different answer* to "which spellings reach me", and none
of them is the documented one.

The proposed shape — **spelling → canonical name → binding → kind check** — is
feasible and is the right target. But it should be split in two, because the
two halves have wildly different costs:

* the **front half** (spelling → canonical name, with the prefix as a *scoped
  binding*) is ~13 code sites and fixes every defect in §3 except #7. It does
  not touch type identity, mangling, the ABI, or `.nuch`;
* the **back half** (one binding table replacing eleven registries) is ~200
  call sites and entangles *identity* (is `a/Vector` the same type as
  `b/Vector`?) with *resolution* (which spellings reach it?). Identity is
  deliberately global today — Stage 12 decision 9 — and changing it moves
  emitted IR.

Recommendation: **Option B** (§5.2) — do the front half, add a one-field
provenance record to the back half's registries, and leave identity alone.
Option A (full unification) stays the stated end state and B is a strict
subset of it, so nothing done for B is thrown away.

> **Amended by §8, 2026-08-08.** The author ruled on all three §7 questions the
> same day. R1 ("two namespaces may both define `Vector`") pulls identity into
> scope, which this verdict deferred — but investigating it showed the cost was
> **overstated**: `type-eq` compares `StructDef` *pointers*, so identity is
> already pointer-based, and R1 is a **re-keying plus an IR-token change**, not
> an identity change (§8.1). The consequence is that **B3 is withdrawn** — once
> the qualifier is part of the key, provenance fields are unnecessary and #4
> falls out for free. §1–§4 stand as the ground truth (with §4.3(b) corrected);
> **§8–§10 are the plan**. §5.2's B3 bullet, §6 and §7 are kept as the
> superseded record.

---

## 1. Ground truth — the resolution paths that exist

A "resolution path" here means: a registry that is keyed by a **source-visible
name** and probed to answer "what does this spelling denote".

| # | Registry | Lookup | Key policy | Prefix-aliasable |
|---|---|---|---|---|
| 1 | `g-globals` (a `Scope`) — `defn` (solitary), `defvar`, `defconst`, `defenum` members, `extern`, `declare`, C-header fns, `export` | `scope-lookup` | **ns-qualified**, via `qualify-name(priv-key-*(n))`; no bare fallback | partly — see §3.2 |
| 2 | `g-generics` — every overload set / multimethod | `generic-lookup` | **bare** (`priv-key-define`, *no* `qualify-name`) | no |
| 3 | `g-structs` — struct layouts + stamped template instances | `lookup-struct` | **bare** (raw head symbol) | n/a — qualifier discarded |
| 4 | `g-uniondefs` | `uniondef-lookup` | bare | n/a |
| 5 | `g-struct-templates` | `struct-template-lookup` | bare | n/a |
| 6 | `g-union-templates` | `union-template-lookup` | bare | n/a |
| 7 | `g-enumdefs` (+ member scan) | `enumdef-lookup` | bare | no |
| 8 | `g-protocols` | `protocol-lookup` | **ns-qualified, then bare fallback** | no |
| 9 | conformances | `conformance-lookup` | (bare type, canonical protocol) | n/a |
| 10 | `g-macros` | `find-macro` | bare, as written | no |
| 11 | fn-type aliases | `fnty-resolve` | bare | no |

Plus two name-keyed sets that are correctly global and not at issue:
`special-form-named`, `primitive-type-named`.

Three distinct key policies, then: **ns-qualified** (1, 8), **bare** (2–7,
9–11), and **ns-qualified with a bare fallback** (8 only). `import-prefixed`
overlays #1 alone.

### 1.1 How the prefix actually works

`import-prefixed` does not create a scope. `do-import` records the
`[start, end)` slice of `g-globals` that the imported file contributed, then
`inject-import-aliases` walks that slice and, for each entry, calls
`import-alias-one` to `scope-define` a **second** `Sym` under the key
`prefix/bare-name`, pointing at the same type and `ir-name`
(`src/nucleusc.nuc:13022`).

Two filters decide what gets an alias:

```
(when (and (= (sym is-local) 0)
           (!= (sym ir-name) null)
           (or (= (sym sym-private) 0) (!= g-import-include-private 0)))
```

Neither `is-local` nor `ir-name` means "aliasable". `emit-defvar` registers
its global with **`is-local` 1** (`src/nucleusc.nuc:10190`); `defconst` and
`defenum` members register with **`ir-name` null** (`:10248`, `:10382`). So
the filter silently excludes every global variable, every constant, and every
enum member. That is not a policy — it is two proxies drifting.

And because the alias is just another `g-globals` key, and `qualify-name`
splits on the *first* interior slash, the key `zx/zfun` is the same string in
every namespace. An alias injected while compiling file A is therefore visible
in file B — measured in §2.4.

---

## 2. Measured behaviour

Library under test (`lib/zzlib.nuc`):

```lisp
(ns zn)
(defprotocol Zp (zmeth ((self (ref Self))) i32))
(defstruct Zs n:i32)
(defn zfun (x:i32):i32 (return (+ x 1)))
(defn zov ((x (ref Zs))):i32 …)   ; + a second overload, to make `zov` overloaded
(defconst ZK 7)
(defvar zg:i32 3)
(defenum ZE ZE-A ZE-B)
```

Consumer: `(import-prefixed zzlib zx)`. So `zn` is the library's namespace and
`zx` is the prefix the consumer asked for. **Only the `zx/` column should be
`ok`.**

| Reference | bare | `zn/` (namespace) | `zx/` (prefix) | `nope/` (bogus) |
|---|---|---|---|---|
| type annotation `(ref Zs)` | ok | ok | ok | **ok** |
| struct constructor `(Zs 4)` | **ok** | err | err | err |
| plain fn `(zfun 1)` | err | **ok** | ok | err |
| overloaded fn `(zov s)` | reaches the generic | **err** | **err** | err |
| `defvar` `zg` | err | **ok** | **err** | err |
| `defconst` `ZK` | err | **ok** | **err** | err |
| `defenum` member `ZE-B` | err | **ok** | **err** | err |
| protocol `(dyn Zp)` / `extend` | falls back | **ok** | **err** | err |

Bold = wrong. Every row is wrong in some column, and no two rows are wrong the
same way.

> **B0 re-measurement, 2026-08-08.** The table above was measured by hand; B0
> re-measured every cell mechanically (`tests/resolution-matrix.sh`, recorded in
> `tests/expected/resolution-matrix.baseline`). **Every cell reproduces except
> the protocol row's `bare` column, and that one splits in two.**
>
> * **`extend` with a bare protocol name is `err`, not "falls back".** The
>   library registers `zn/Zp`; `protocol-lookup`'s second probe only fires when
>   `protocol-key` actually rewrote the spelling, and under `user` a bare name is
>   returned unchanged — so there is one probe, it misses, and the result is
>   `extend: unknown protocol 'Zp'`. (This is the same shape
>   `tests/fixtures/w9-ns-proto-ambiguous.nuc` already pins.) The bare *fallback*
>   is real, but it runs in the other direction: it is what lets a file inside
>   `(ns dp)` still see the `user`-namespace protocols it imports.
> * **Boxing into `(dyn Zp)` is likewise `err`** — same lookup, reached through
>   `dyn-require-protocol`.
> * **But a `(dyn …)` ANNOTATION validates nothing at all**, in any column.
>   `dyn-type` deliberately does not probe the registry at type-parse time (it
>   may run during a prescan, before the protocol's file has registered it —
>   `src/nucleusc.nuc`, `dyn-require-protocol`'s header), so
>   `(defn f ((box (dyn nope/Wholly-Absent))):i32 …)` compiles and emits a
>   `%__dyn.nope_Wholly-Absent` box type for a protocol that does not exist.
>   This is a **tenth** defect, adjacent to #4 (an unvalidated qualifier on a
>   type) but distinct: here the whole *name* is unvalidated, not just its
>   qualifier. The baseline records it as the `protocol-dyn-annot` row, kept
>   separate from `protocol-dyn-box` precisely because the two positions answer
>   different questions.
>
> The baseline also carries the §2.4 prefix leak and both §11.2 `import-only`
> non-filtering cells as rows, so B1/B2 can diff them like any other cell.

### 2.1 The reported defect

```
examples/zz-t2.nuc:7: error: extend: unknown protocol 'dpx/Describe'
```

`protocol-lookup` (`src/generics.nuc:2697`) probes `qualify-name(spelling)`
then the raw spelling. The prefix `dpx` is not a namespace, so neither probe
can hit; and nothing consults the prefix table, because the prefix table is
not consulted by anything — it is materialised into `g-globals` instead, and
protocols do not live in `g-globals`.

### 2.2 A bogus qualifier resolves

```lisp
(defn f2 ((x (ref zzz/Fox))):i32 (return (x n)))   ; compiles, links, runs
```

`strip-ns-qualifier` (`src/nucleusc.nuc:3405`) discards everything before the
first interior slash and looks the bare name up in the flat `g-structs`. The
qualifier is never checked against anything, so **any** qualifier works on a
type — including one naming a namespace that does not exist.

### 2.3 Overloaded functions have no qualified spelling at all

`generic-register-method` keys on `priv-key-define(fname)` with **no**
`qualify-name` (`src/generics.nuc:404`). A generic is therefore a unit-global
bare name. `zn/zov` and `zx/zov` both fail; only bare `zov` reaches it. So
once a function has two overloads it silently becomes unqualifiable — and
since `defprotocol` method names *are* generics, this is the load-bearing
reason `examples/w9-dyn-ns.nuc` has to route `describe` through a vtable.

### 2.4 A prefix declared in one file is visible in another

```lisp
; lib/zzmid.nuc
(import-prefixed zzlib zx)
(defn mid (x:i32):i32 (return (zx/zfun x)))

; examples/zz-leak.nuc — never declares the prefix `zx`
(import-use zzmid)
(defn main ():i32 (printf "%d\n" (zx/zfun 1)) (return 0))   ; prints 2
```

Prefixes are unit-global, not file-scoped. This is also why "two imports may
not share a prefix" is a whole-unit error rather than a per-file one — an
API-design knob that leaks into unrelated files.

> **Status: closed by B1, 2026-08-08 (§9.1).** `zz-leak.nuc` above is now
> refused with `unknown: zx/zfun — 'zx' is not an import prefix in this file`
> plus a note naming the file that *does* bind it and the prefixes this file
> has. The "two imports may not share a prefix" rule is still whole-unit —
> nothing here relaxes it — but the *visibility* half is file-scoped, so a
> library's choice of prefix is no longer observable by its consumers.

### 2.5 Two smaller ones found on the way

* `NK-PROTOCOL` is declared and used as an *input* to `guard-name-kind`, but
  `name-existing-kind` never probes `g-protocols`, so it can never be
  *returned*. A protocol/struct clash is caught only because the struct
  prescan wins the race — and the message then says the protocol collided with
  "a type", pointing at the wrong line.
* The did-you-mean suggester prints the *bare* name of a qualified candidate,
  producing `error: unknown: zfun (did you mean 'zfun'?)`.

---

## 3. The defect list

1. **Prefixes reach only `g-globals`.** Protocols, types, generics, macros,
   templates and enums have no prefixed spelling.
2. **`import-prefixed` skips globals, constants and enum members** — the
   `is-local`/`ir-name` filter (§1.1).
3. **The defining namespace is always in scope**, whether or not the consumer
   asked for it. `import-prefixed` adds a spelling; it removes none.
4. **A qualifier on a type is never validated** (§2.2).
5. **Generics are unqualifiable** (§2.3).
6. **Prefixes are unit-scoped, not file-scoped** (§2.4).
7. **Type identity is bare and global**, so two namespaces cannot both define
   `Vector`. (Distinct from #4: #4 is *resolution*, this is *identity*.)
8. **Two priority orders disagree.** `name-existing-kind`
   (`src/nucleusc.nuc:8988`) ranks special > builtin > type > macro > function
   > value. `emit-dispatch` (`:8766`) probes generic → scope → struct →
   struct-template → macro → special form. The one-symbol-one-kind invariant is
   *enforced* in one order and *consumed* in another.
9. `NK-PROTOCOL` is unreachable; the did-you-mean suggester echoes its input
   (§2.5).

---

## 4. Feasibility of the proposed shape

> *bare-or-prefixed symbol → original namespaced symbol → pointer → thing,
> then check the kind is right for the position.*

### 4.1 Most of it already exists, in the wrong place

`name-existing-kind` **is** the single resolution path, already written: one
function, name in, kind out, every registry probed in a documented priority
order, with `kind-noun` for diagnostics and `NK-*` for the tags. It is used at
**definition** sites only, via `guard-name-kind`, to enforce one-symbol-one-kind.

The whole proposal can be stated as: *promote `name-existing-kind` from a
definition-time collision check to the reference-time resolver, make it return
the payload as well as the tag, and give it a canonicalising front end.* That
is a much smaller conceptual leap than it looks from the outside, and it means
the "check the kind is right for this position" half is already designed and
already has its diagnostics.

### 4.2 Where the naive shape breaks: one name is several things

"pointer → thing" implies one name denotes one thing. It does not:

* `(defstruct S …)` yields a **type** `S`, a **constructor callable** `S`, a
  conformance subject `S`, and a `.nuch`/C-header name;
* `(defprotocol P …)` yields a **protocol** `P`, the box type `(dyn P)`, and a
  **generic per method signature**;
* `(defn f …)` yields a `Generic` *always*, plus a `g-globals` `Sym` *only*
  while `f` stays solitary — `finalize-generics` withdraws the `Sym` the moment
  a second overload appears. That transition is why #5 exists.

So the entry must be a small record with a discriminant and the payload
pointers a name can legitimately carry — `{canonical, kind, sym, type, generic,
proto, macro, src-ns}` — not a tagged `void*`. That is an amendment, not an
obstacle; it is also the honest description of what `name-existing-kind`
already computes.

### 4.3 The three real obstacles

**(a) Phase spread.** Names are registered by the reader-adjacent prescans
(`prescan-defn-signatures`, `prescan-imported-signatures`, `prescan-value-names`),
by emission, by macro expansion inside a JIT module, by `.nuch` replay, by the
C-header importer, and by **template stamping**, which mints `StructDef`s named
`Vector.i32` at arbitrary points during emission. A unified table must be
written by all of them or it is not authoritative. This is the main reason to
prefer a *directory alongside* the registries (Option B) over a *replacement*
of them (Option A): a directory can be filled incrementally, kind by kind, with
the old lookup as the fallback, and each step is independently verifiable.

**(b) Resolution vs identity.** ~~Making the registries ns-keyed would fix #4
and #7 together — and would change conformance keys, `.nuch` round-trip, the C
header exporter and IR mangling, i.e. emitted IR.~~

**Corrected, 2026-08-08 (§8.1).** This overstated the cost by assuming type
identity is name-based. It is not: `type-eq`'s `TY-STRUCT`/`TY-UNION` arms are
`(= (aa sdef) (bb sdef))` — **pointer** identity on the `StructDef`
(`src/generics.nuc:152`). A type's *name* is only two things: a registry key,
and a mangling token. Re-keying therefore does not change what "the same type"
means anywhere in the compiler; it changes which spelling finds it, and what
its symbol is called. That is why R1 is affordable and why B3 is withdrawn.

**(c) Bootstrap exposure is near zero, and that is the good news.** No file in
`src/` declares a namespace; the only `(ns …)` in the tree are four demo
libraries (`lib/nsgeom.nuc`, `lib/nsdescribe.nuc`, `lib/nsdescribe2.nuc`,
`lib/nsgfacade.nuc`). The compiler and the standard library are entirely `user`
+ `import-use`, where `qualify-name` is the identity and no prefix path is
taken. So the whole area can be reworked with the byte-identical-bootstrap gate
intact — the same escape hatch that let Stage 12 land namespaces at all.

---

## 5. Options

### 5.1 Option A — full unification

One `Binding` table, canonical-name keyed, written by every definer; the
eleven registries demoted to payload stores; all lookups routed through
`resolve-name` + a kind assertion.

* **Fixes:** all of #1–#9.
* **Cost:** ~200 name-lookup call sites (`scope-lookup` 59, `generic-lookup`
  28, `lookup-struct` 27, `protocol-lookup` 13, `union-template-lookup` 12,
  `conformance-lookup` 10, `struct-template-lookup` 7, `uniondef-lookup` 6,
  `find-macro` 5, `enumdef-lookup` 2), plus every definer and every phase in
  §4.3(a). Forces the identity decision (#7) at the same time.
* **Risk:** high, and concentrated in the one place this repo has been most
  careful about — the `node-type` ↔ `emit-node` lockstep and the bootstrap
  fixed point.

### 5.2 Option B — unify the front half; add provenance to the back **(recommended)**

Three pieces, each shippable alone:

**B1 — a real import environment.** Replace the alias-injection model with a
per-file table of `{prefix → namespace}` plus the set of namespaces flattened
by `import-use`. `do-import` records it; it is saved/restored around imports
exactly as `g-current-ns` already is.

**B2 — one canonicaliser.** `resolve-spelling(spelling) → {ns, bare, canonical}`,
replacing the three ad-hoc splitters (`qualify-name` 3 sites,
`strip-ns-qualifier` 10, `protocol-key`). Rules, applied to a *reference*:

* split at the first interior slash (unchanged — the §"Syntax" rule stands);
* a qualifier is looked up **in the import environment only**. A bound prefix
  names its namespace. A qualifier that is not a bound prefix is an **error**
  naming the prefixes that are in scope — not a silent fall-through to a raw
  namespace name. *This is what makes `dpx/` win and `dp/` lose;*
* a bare name probes the current namespace, then the flattened set, then
  errors — with ambiguity across two flattened namespaces reported, not
  silently resolved.

**B3 — provenance, not re-keying.** Add `src-ns` to `StructDef`, `UnionDef`,
`Generic`, `EnumDef`, and the template records (`Protocol` already carries its
namespace in its key; `Method` already has the field). Registry keys stay
**bare**; the resolver validates the qualifier against `src-ns` after the hit.
`zzz/Fox` is rejected; `Fox`'s identity, mangling, conformance key and `.nuch`
round-trip are untouched.

* **Fixes:** #1, #3, #4, #6 outright. #2 and #5 become one-line consequences
  (the prefix stops being a `g-globals` overlay, so the `is-local`/`ir-name`
  filter disappears with it, and generics get a qualified spelling for free
  once qualification is a resolver concern rather than a key concern).
  #8 and #9 are cheap to fold in.
* **Leaves open:** #7 (identity).
* **Cost:** ~13 splitter sites + ~8 definers + the import forms. The ~200
  lookup call sites are **not** touched — they keep calling `lookup-struct`,
  and the qualifier is consumed before they see it.
* **Risk:** low. Every changed path is inert under `user` + `import-use`, which
  is 100% of `src/` and `lib/` outside the four demo files.

### 5.3 Option C — point fixes

Teach `protocol-lookup` about the prefix table; add the missing alias-injection
cases; validate qualifiers in `strip-ns-qualifier`.

* **Fixes:** #1 and #2 for the kinds you remember to patch.
* **Cost:** small.
* **Why not:** it adds a *fourth* key policy and leaves #3 (the namespace stays
  in scope) untouched, which is the actual complaint. It is the shape that
  produced this bug.

### 5.4 Option D — invert the default instead

Leave resolution as-is and make `import-prefixed` *rename* rather than
*alias*: the importing file sees the library's namespace as the prefix,
everywhere, for every kind.

* Attractive because it is one concept ("a prefix renames a namespace within a
  file") and it makes `dp/` disappear for free.
* **Cost is deceptive:** "everywhere, for every kind" is exactly the unification
  work in B1/B2 — there is nowhere to put the rename *except* a single
  canonicaliser. D is B with a different name unless implemented as a
  per-registry hack, in which case it is C.

---

## 6. Recommendation and staging

**B, in order, each step gated on `make test` + byte-identical bootstrap:**

1. **B0 — pin the matrix.** Turn §2's table into fixtures. Most cells are
   currently `err`-expected; they become the regression net for everything
   after. Cheap, and it makes each later step's blast radius visible.
2. **B1 — import environment**, with prefixes file-scoped (#6). Old alias
   injection stays alongside it, unused, until B2 lands.
3. **B2 — the canonicaliser**, cut over kind by kind: protocols first (it is
   the reported bug, it has the fewest call sites at 13, and `protocol-key` is
   already a canonicaliser in miniature), then types, then globals, then
   generics. Delete alias injection when the last kind is cut over.
4. **B3 — provenance fields**, closing #4.
5. **B4 — reconcile the priority orders** (#8): make `emit-dispatch` and
   `name-existing-kind` share one table, and give `name-existing-kind` its
   missing `g-protocols` probe (#9).

Steps 1–3 fix the reported defect. Steps 4–5 are independent and can slip.

## 7. Wants a decision before B3

* **#7, type identity.** Should two namespaces be able to define `Vector`?
  Today they cannot, and Stage 12 decision 9 says conformance keys off global
  type identity deliberately. B3 preserves that. Making identity namespaced is
  a separate stage: it moves emitted IR, changes `.nuch`, and needs the C
  header exporter to agree.
* **Should `import-use` still flatten into an unqualified space?** B2 makes
  ambiguity across two flattened namespaces an error rather than a silent
  pick. That is strictly better, but it can newly reject code that compiled
  before — including, potentially, `lib/`.
* **Should a namespace ever be reachable without an import that names it?**
  B2 as written says no, which is the stated goal. Note this makes
  `examples/w9-dyn-ns.nuc` invalid as written; it should become the fixture
  for the fix, spelling `dpx/Describe` throughout.

---

## 8. Rulings (2026-08-08) and what they cost

The three §7 questions were answered by the author:

* **R1** — two namespaces should be able to define `Vector`.
* **R2** — `import-use` flattens into an unqualified space; a name collision is
  an error.
* **R3** — a namespace should not be reachable without an import. The `unsafe`
  pseudo-namespace, which currently gets special handling, is the existing use
  this touches.

### 8.1 R1 is a re-keying, not an identity change

§4.3(b) assumed making types namespaced would move identity. Measured, it does
not. `type-eq` compares `StructDef` pointers (`src/generics.nuc:152`), and
every downstream consumer — dispatch, `unify-tpat`, ABI classification, layout
— works off the `Type`/`StructDef` pointer. A type name is a **registry key**
and a **mangling token**, nothing more. R1 therefore decomposes into:

1. **Key on the canonical name.** `register-struct` / `lookup-struct`, and the
   union, template and enum equivalents, take the resolver's canonical name
   instead of the raw head symbol. `strip-ns-qualifier`'s 10 call sites go
   away with it — the qualifier stops being discarded, which is #4 fixed as a
   side effect rather than as its own mechanism.
2. **An IR-legal namespaced token.** `type-mangle-token`'s `TY-STRUCT`/
   `TY-UNION` arms return `(sd name)` verbatim (`src/type-mangle.nuc:36`).
   With a qualified name that emits a `/` into an LLVM symbol. The fix is the
   composition that **already exists for function names**: `ns-ir-base` is
   `ns-compose(ns-ir-prefix(ns), ir-name-token(name))` (`src/nucleusc.nuc:3568`),
   backed by the per-namespace prefix table and overridable with
   `set-ir-prefix`. `StructDef` needs an `ir-prefix` snapshot taken at
   registration, exactly as `Generic.ir-prefix` already does
   (`src/generics.nuc:62`) and for the same reason — a stamp or a finalize may
   run while another namespace is current.
3. **Consequential re-keying**, all mechanical once (1) lands: conformance
   keys, the vtable / `dyn` / `boxedfn` memo keys, `.nuch` round-trip,
   `--emit-cheader`.

Bootstrap exposure stays near zero: `user` composes the empty prefix, so every
token is unchanged for every type in `src/` and `lib/` outside the four demo
namespaces.

**Sequencing.** Step 2 is the same work as
[../stage14/symbol-mangling.md](../stage14/symbol-mangling.md) (SM-1…SM-5),
which owns `ir-name-token` and carries the standing warning that
`sanitize-for-ir` maps hyphens to `_` and must never be applied blanket. Do SM
first, or fold this token into it — not beside it.

### 8.2 R2 needs a per-kind collision rule

For types, protocols, macros and values, "same name = collision" is
unambiguous and right. For **functions** it cannot be, because Nucleus
dispatches on name *and* argument types, and protocol method names are the
common case. Under a name-only rule, `(import-use dp)` plus `(import-use dq)`
where each declares a `describe` method is an instant hard error — which is
precisely the `examples/w9-dyn-ns.nuc` scenario, and would make protocols and
`import-use` mutually unusable.

**Recommended rule, per kind:**

| Kind | A collision is… |
|---|---|
| type, union, template, protocol, macro, `defvar`/`defconst`/enum member | the same name from two flattened namespaces |
| function | the same name **and** an overlapping signature — the rule `duplicate-signature-message` already implements inside `user` |

This also settles how generics should be keyed, which R1 would otherwise
force. Do **not** re-key `g-generics` to canonical names: keep one `Generic`
per bare name with methods merged from every flattened namespace — that is
what an open multimethod wants, and it keeps `generic-resolve` untouched.
Recover the qualified spelling (#5) from `Method.src-ns`, which **already
exists** (`src/generics.nuc:427`, added in W5e for diagnostics): a qualified
reference `a/describe` resolves to the bare `describe` generic with its method
set *filtered* to `src-ns == a`. Cheap, no dispatch surgery, and it makes
flattening free.

**When to report** is the one genuinely open sub-question. Eager (at the
import) gives the better message but rejects programs that never touch the
ambiguous name — and the prelude is `import-use`d into everything, so the
blast radius is unknown until measured. Lazy (at first ambiguous *use*) is
recommended: name both candidates, tell the author to qualify. An eager
`--strict` pass can be added later if wanted.

### 8.3 R3 — what an import binds, and where `unsafe` lands

Resolution consults **only** the file's import environment. Proposed bindings:

| Form | Binds |
|---|---|
| `(import-use lib)` | every public name **unqualified**, *and* the namespace's own name as a qualifier |
| `(import-prefixed lib p)` | every public name under **`p/` only** |
| `(import-only lib (a b))` | those names unqualified, plus the namespace qualifier |
| implicit prelude | as `import-use` |
| implicit `unsafe` | as `import-prefixed`, under the prefix `unsafe` |

Row 2 is the reported bug fixed: the prefix binds, the defining namespace does
not. Row 1's second clause is deliberate — it is **R2's escape hatch**. When
two `import-use`d libraries both define `Vector`, `a/Vector` disambiguates
without editing the import form; without it, the only remedy for a collision
is changing how you imported. It does not weaken R3, because the namespace is
reachable *precisely because it was imported*.

**`unsafe` stops being special.** Today the seven `unsafe/*` spellings are
literal string members of the special-form set (`src/nucleusc.nuc:13683`),
matched whole-string before any slash-splitting — so they never reach the
resolver at all. Making `unsafe` a built-in namespace bound as a prefix in
every file's environment gives three things:

* the seven hard-coded strings leave the set, and `unsafe/cast` resolves
  through the one path like any other qualified name;
* **bare `cast` / `ptr+` / `funcall-ptr-*` stop resolving for free** — the
  namespace is bound *prefixed*, never flattened. That is exactly UN-5's
  intent, currently implemented as seven hard-coded targeted errors; those can
  stay as did-you-mean text rather than as the mechanism;
* `(ns unsafe)` stays rejected, now because the name is pre-owned by a
  built-in binding rather than by a bespoke check.

---

## 9. Revised plan

B3 is withdrawn (§8.1). The staging becomes:

| Step | Delivers | Closes |
|---|---|---|
| **B0** | §2's matrix as fixtures — most cells `err`-expected | — |
| ~~B0~~ | **Done 2026-08-08.** `tests/resolution-matrix.sh` + `tests/expected/resolution-matrix.baseline` (43 cells) — a *recorder*, not a gate: it generates its own library and consumers under a temp dir, compiles+links each probe, and `--check` diffs against the committed baseline. Plus three genuine regression tests in `tests/run-tests.sh` for the cells that are already correct (`import-use` flatten, `import-prefixed` `p/fn` for namespaced and non-namespaced libraries); the `export` facade path was already covered by `examples/export-test.nuc`. One §2 cell was measured differently — see the note under §2's table | — |
| ~~B1~~ | file-scoped import environment; old alias injection left inert beside it | #6 |
| **B1** | **Done 2026-08-08.** `ImportBind` + `g-file-imports` (a `(Vector (ref ImportBind))`, the `NsPrefixEntry` idiom), saved/cleared/restored around every imported file exactly as `g-current-ns` is. `do-import` records one bind per import form — prefix non-null for `import-prefixed`/`import`/`unsafe/import-private`, null for the flattening `import-use`/`import-only` — **before** every early return, because the (file, prefix) dedup, the already-loaded flatten dedup and the W1d cycle skip all leave the import *declared here* while doing no further work. Alias injection is untouched; what B1 adds is the gate, `prefix-out-of-scope`, consulted by `scope-lookup` on the global scope only. Exactly one matrix cell moved: `xfile-prefix-leak zx/` `ok` → `err`. See §9.1 | #6 |
| ~~B2~~ | the canonicaliser, cut over kind by kind (protocols first — the reported bug, fewest sites, and `protocol-key` is already this in miniature), then types, then globals. Delete alias injection when the last kind cuts over | #1, #3, R3 |
| **B2a** | **Done 2026-08-08.** `resolve-spelling` (`src/nucleusc.nuc`) + `NameRef`/`NR-*` (`src/compiler-types.nuc`) — one canonicaliser, resolving a qualifier through `g-file-imports` and nothing else — plus the `path → ns` record B1 left open (`g-file-ns`, written by `emit-ns`). **Protocols cut over**; types and globals still on the old path. Four matrix cells moved, exactly as predicted: `protocol-extend`/`protocol-dyn-box` `zx/` err→ok and `zn/` ok→err. `examples/w9-dyn-ns.nuc` rewritten to `dpx/`. See §9.2 | #1, #3, R3 — for protocols |
| ~~B2b~~ | globals; `unsafe` as a built-in namespace; delete `inject-import-aliases` | the rest of #1, #2, #3 |
| **B2b** | **Done 2026-08-08.** `scope-lookup` split into a reference resolver (its global frame delegating to `globals-lookup-ref`, `src/nucleusc.nuc`) and `scope-lookup-key` (the pre-B1 body, for the 8 definition-side sites). B1's `prefix-out-of-scope` / `unbound-prefix-message` folded into `resolve-spelling` / `qualifier-scope-note`, removing the §9.2 disagreement. `unsafe` bound as an implicit prefix in every file; the seven `unsafe/*` strings left the special-form set. `inject-import-aliases` / `import-alias-one` / `alias-cinclude-collected` **deleted** (64 lines), taking §1.1's `is-local`/`ir-name` filter with them. Seven matrix cells moved, exactly as predicted. See §9.3 | the rest of #1, #2, #3 |
| **B3′** | re-key the type registries + `StructDef.ir-prefix` + ns-aware mangling token | #4, #7, R1 |
| **B4** | per-kind collision rule; `Method.src-ns` filtering for qualified generic references | #5, R2 |
| ~~B5~~ | reconcile the two priority orders; add the missing `g-protocols` probe to `name-existing-kind`; fix the did-you-mean echo | #8, #9 |
| **B5** | **Done 2026-08-09**, and upgraded per §13.4 from "reconcile the two orders" to the **shared binding interface** of §13.3. One table, `build-binding-kinds` (`src/nucleusc.nuc`), thirteen rows — §1's eleven registries plus the two correctly-global name sets — each carrying `noun` / `nk` / `collides` / `name-keyed` / `reregisterable`, and the row order IS the resolution order, walked by `name-existing-kind`, `emit-dispatch` and `node-type-call`. `NK-PROTOCOL` is returned (a row plus a prescan reorder); privacy for the four `Sym`-less private definers is implemented once against `is-private`; the did-you-mean renders through `src-ns` instead of echoing its input; `export` re-registers through the interface. See §14 | #8, #9 |

B0–B2 fix the reported defect. B3′ wants
[../stage14/symbol-mangling.md](../stage14/symbol-mangling.md) first or folded
in (§8.1). B4 is independent of B3′. B5 can slip.

### 9.1 What B1 measured, and what B2 inherits

**The gate is narrower than "resolve through the environment", deliberately.**
`prefix-out-of-scope` fires only when the qualifier is a prefix *some other file
in this unit bound*. A qualifier naming a **namespace** still resolves as it did
(that is #3, which is B2's), and a qualifier naming **nothing at all** still
falls through to the existing unresolved-name tiers (that is the `nope/` column,
which stayed put). This is exactly why one cell moved and not fourteen: the
matrix's `zn/` column is the namespace half and B1 does not touch it.

Four things B2 should know:

* **The prefix→namespace half of the table is not recorded.** `ImportBind`
  carries `{prefix, path}`; a bind's *namespace* is derivable but was not
  materialised, because nothing in B1 reads it and a memo nothing reads is a
  memo that drifts. B2 wants a `path → ns` record written where `do-import`
  finishes a fresh load (`g-current-ns` at that point is the imported file's own
  namespace) and read for the already-loaded and cycle-skip paths, which never
  see it. The flattened-namespace set of §8.3 is then the null-prefix binds
  mapped through it.
* **Every import path *was* a clean nesting, with one caveat.** `do-import`'s
  two load blocks (symbol path, `.nuc`/`.nuch` string path) and
  `prescan-imported-signatures` are the three file boundaries, and all three
  already save/restore `g-current-ns`; adding the environment beside it was
  mechanical. The caveat is the **early returns**: three of them (prefix dedup,
  flatten dedup, cycle skip) return *before* the load block, so a bind recorded
  inside the block would be missing in precisely the cases where a file legally
  re-declares an import the unit has already processed. The record therefore
  happens the moment `path` is known. The cycle case is the one with teeth — a
  missing bind there would make B1's diagnostic answer a question W1d's
  `cycle-prefix-message` already answers correctly, and the two would have
  reported different causes for one failure.
* **The REPL needed nothing.** A prefixed import in the REPL routes through the
  ordinary top-level dispatcher into `do-import`, and the session's environment
  is simply the one that is never saved/restored — so prefixes accumulate across
  commands, which is what a session wants. (`src/repl.nuc` intercepts only
  `import-use`/`import-only`, for the declare-backfill, and those record a bind
  through `do-import` like any other.)
* **One known imprecision, left in.** A qualifier that is *both* a namespace
  somewhere and a prefix bound by another file is refused in a third file that
  binds neither — the gate cannot tell which mechanism the author meant, and it
  has no list of declared namespaces to consult. `examples/ns-mangle.nuc` and
  `lib/nsgfacade.nuc` both bind the prefix `geom` for the namespace `geom`, so
  the collision is real in the tree; it does not bite because neither file
  references `geom/` without binding it. B2 removes the imprecision by making
  the environment the *only* authority for both mechanisms (R3), at which point
  "not bound here" is the whole answer and the namespace half stops being a
  separate path.

### 9.2 What B2a built, and what B2b inherits

**The canonicaliser.** `resolve-spelling(spelling) → ref:NameRef`
(`src/nucleusc.nuc`, in the section after B1's import environment; the record and
its `NR-*` tags in `src/compiler-types.nuc`). It splits at the first interior
slash — `qualify-name`'s rule, unchanged — and resolves the qualifier through the
file's import environment only:

* the file's own namespace, and `user` (the prelude is flattened everywhere, and
  `user` *is* the unqualified space), are always legal;
* a bound prefix names its library's namespace (`file-prefix-path` →
  `import-path-ns`);
* a namespace some `import-use`/`import-only` in this file flattened may be named
  by its own name — §8.3 row 1's second clause, R2's escape hatch;
* anything else is `NR-UNBOUND`: `canonical` is null and the reference resolves
  to **nothing**, deliberately, even when the raw spelling happens to *be* a
  registry key. That last clause is the whole fix.

An unqualified spelling is `NR-BARE`, whose `canonical` is the current
namespace's key; the caller then walks the flattened set itself
(`file-imports-count` / `file-flattened-ns-at`), because the *probe* is
per-registry and the canonicaliser is not.

**The `path → ns` record B1 left open** is `g-file-ns`, written by **`emit-ns`**
rather than at the end of `do-import`'s load block as §9.1 suggested. `emit-ns`
is strictly better and it is the same size: it is the single point at which any
file's namespace becomes known, it is reached from every file entry (the root,
both load blocks, and `prescan-imported-signatures` via `apply-leading-ns`), and
because the whole-graph prescan runs first, every reachable file's namespace is
recorded *before* the first import form is emitted — so the already-loaded and
cycle-skip paths need no special handling at all. A path with no record is in
`user` (a file with no `(ns …)` never reaches `emit-ns`), so absence is an
answer, not a gap.

**Five things B2b and B3′ should know.**

* **The reference side and the key side are different questions, and protocols
  needed both.** `protocol-lookup` is now the *reference* resolver;
  `protocol-lookup-ns` (the old body, renamed) is the *key* lookup, for a stored
  `Constraint.proto`, a super-protocol edge, a `.nuch` replay's protocol name, and
  the canonical name a resolved `extend` passes down its own call chain. Routing a
  canonical key through the reference resolver is wrong for a structural reason,
  not an incidental one: **the file that reads a canonical key is routinely not
  the file that wrote it**, and B2a's rule is that a file cannot name a namespace
  it did not import. Every kind cut over after this one will need the same split;
  it is the single largest piece of work per kind.
* **The pattern that makes it safe is "resolve once, at the reference, then carry
  the record."** `emit-extend` used to canonicalize the spelling and then look the
  *canonical name* up again; under B2a that asks the scope question twice and gets
  two different answers. It now calls `protocol-lookup` once, keeps
  `proto-rec:?ptr:Protocol`, and passes `(p name)` downward. Copy this shape
  rather than the canonicalize-then-lookup shape.
* **`(dyn P)` splits identity from admission, and the split is forced by
  phase.** `dyn-type` mints the box's `StructDef` from a `defn` signature during
  `prescan-defn-signatures`, where the file's import environment is empty by
  construction, and again from the same signature at emission, where it is not. A
  memo key that changed between those two moments would mint two `StructDef`s for
  one protocol and `type-eq` is `StructDef`-pointer identity — the exact W9
  defect-21 bug. So `dyn-type` keeps the **environment-free** canonicalizer
  (`protocol-canon-name-ns`) and the scope question is asked once, at box
  construction, by `dyn-require-protocol`. Generalize: **a memo key must be
  phase-stable; a permission check must be asked where the permission is
  known.** Any kind whose registry key is computed during a prescan inherits this.
* **Downstream of a gate, do not gate again.** `protocol-resolve-any` (reference,
  else key) exists for the three `(dyn P)` consumers — `dyn-method-slot`,
  `emit-dyn-forward`, `derive-closure-conformance` — which run after
  `emit-box-value` has already ruled, and which may be reached in a file that
  never named the protocol at all.
* **The diagnostic is the deliverable again.** `qualifier-scope-note` /
  `with-qualifier-note` (`src/nucleusc.nuc`, beside the canonicaliser) turn any
  "unknown X" head into a scope diagnostic when the qualifier is the reason. B2b
  should route through the same pair rather than writing a second note — and note
  that B1's `unbound-prefix-message` is the *narrow* version of this (a prefix
  another file bound) and should fold into it when globals cut over.

**Two things measured, not assumed.**

* **Byte-for-byte inert on emitted IR.** A compiler built from a clean `HEAD`
  worktree and the working-tree compiler emit `diff`-identical IR for all 182
  files in `examples/` + `lib/`; the sole difference is the *exit code* on
  `examples/w9-dyn-ns.nuc`, which the pre-fix compiler now rejects because the
  file has been rewritten to the spellings only the fix accepts. (`make bootstrap`
  reaches its fixed point independently.)
* **The `protocol-dyn-box` row of the matrix needed its fixture re-pointed.** Its
  `extend` was pinned at `(extend Cs zn/Zp)` — "the one spelling that works" —
  which B2a makes an error, so without the re-point all four cells would have
  moved to the *extend*'s diagnostic and the row would have measured nothing. A
  fixture that pins a defect becomes unreachable when the defect is fixed; the
  re-point is part of the change, not a re-baseline.

**Still open after B2a**, both reported rather than forced:

* **The tenth defect stays open, and the blocker is prescan ordering, not the
  canonicaliser.** `(dyn nope/Wholly-Absent)` in an *annotation* still compiles.
  Closing it means validating in `dyn-type`, and `dyn-type` runs inside
  `prescan-defn-signatures` — which for the unit's root file runs *before*
  `prescan-imported-signatures`, so no imported protocol is registered yet, and
  before any import form is emitted, so `g-file-imports` is empty. Both facts
  make a check there reject every legal reference. The two real fixes are (a)
  defer annotation-site validation to a worklist drained after the whole-graph
  prescan, or (b) fill the prescan's import environment and move the imported
  signature prescan ahead of the root's own. (b) is the better one and is
  adjacent to B3′, which re-keys registries the prescan also writes.
* **B1's one imprecision is removed for protocols and remains for globals.** A
  qualifier that is both a namespace and another file's prefix now resolves
  correctly in a protocol position — `resolve-spelling` never consults
  `g-import-prefixes`, so "is it in *my* environment?" is the whole question.
  Measured: with `lib/nsgfacade.nuc` binding the prefix `geom`, a third file that
  `import-use`s a namespaced library can name its protocols by namespace. The
  global path still goes through `scope-lookup` → B1's `prefix-out-of-scope`, so
  the same file is still refused `geom/area`. **The two halves now disagree**,
  which is a reason to sequence B2b sooner rather than later: `prefix-out-of-scope`
  should disappear into `resolve-spelling` when globals cut over.
  *(Done in B2b — §9.3. One gate, one note, two tiers of explanation.)*


### 9.3 What B2b built

**The split, and how the line was drawn.** `scope-lookup` had 59 call sites and
was answering two questions. The line is the *provenance of the string*, exactly
as §12.6 predicted — and for globals it turns out to coincide with a syntactic
property, which protocols did not have: **a definition-side existence check is a
key; everything else is a reference.**

* **8 key sites** (`scope-lookup-key`, the pre-B1 body verbatim): the `.nuch`
  `declare` replay's "already defined?" (`src/nuch.nuc`), the C-header
  registrar's (`src/cheader.nuc`), `emit-deferror`'s re-import dedup,
  `emit-extern`'s redeclaration dedup, `cheader-yield-to-explicit-declare`'s
  "has the explicit declare been reached yet", and the REPL's three redefinition
  probes. Every one is paired with a `scope-define`: it asks about the key the
  compiler is about to write, or has just written. Routing these through the
  reference resolver would have been actively wrong, not merely conservative — a
  bare definer name would additionally probe every flattened namespace and
  report an *imported* symbol as a redefinition.
* **49 reference sites**: every `emit-*` / `node-type-*` lookup of a name that
  appears in the source being compiled, plus `emit-export`'s argument (a source
  spelling — it now resolves `geom/area` through the facade's own prefix rather
  than through an injected alias that happened to have the same text).
* **2 sites deleted** with alias injection.

**The one genuinely ambiguous class**, called out because the reasoning is not
obvious: the ~15 sites that look up a **literal string the compiler wrote
itself** — `"printf"`, `"fflush"`, `"g-handler-top"`, `"err-find-handler"`,
`"unhandled-error"`, `"default-allocator"`, `"alloc-handle-alloc"`, and the
`"fn"`/`"vfn"`/`"mfn"`/`"cfn"` shadow tests. They are neither a user's spelling
nor a stored key. They were classified as **references**, because the question
they ask is "is this reachable *from the file being compiled*", and that is the
reference question. The classification is observable: it is what gives a file
with an explicit `(ns …)` the `user` fallback, which closes the gap
`lib/nsdescribe.nuc`'s header had recorded since W9 ("a namespaced file cannot
construct a box at all today" — measured: it can now, verified with a
`(ns …)` library that boxes into `(dyn dp/Describe)` and returns 507). Had they
been classified as keys, that gap would have stayed open and nothing would have
failed — which is exactly why this class is worth naming.

**The bare path grew two fallbacks, and both are gated to nothing here.** An
unqualified reference probes the current namespace's key (the pre-B2b rule,
unchanged), then each namespace this file flattened, then `user`. Both additions
sit behind `g-ns-declared`, which is 0 for every build of this compiler and every
program in `lib/`: with no namespace in the unit every flattened namespace *is*
`user` and `qualify-name` is the identity, so the extra probes are provably the
same scan that just missed. They can only ever add a resolution, never move one —
the first probe is unchanged and runs first.

**What deleting alias injection removed.** 64 lines (`import-alias-one`,
`inject-import-aliases`, `alias-cinclude-collected`), plus the
`g-cinclude-collecting` / `g-cinclude-collected` collect mode in `do-import` and
`src/cheader.nuc` that existed only to feed it. Three defects closed *by
deletion* rather than by fix:

* **#2** — the `is-local` / `ir-name` filter. There is no slice to filter.
* **#1's global half** — a prefix reaches `defvar`s, `defconst`s and enum members
  because it reaches whatever key the library registered, and those keys are
  ordinary.
* **W1d's prefix-over-a-cycle coupling.** A skipped cycle re-entry has no
  global-scope slice, so injection was suppressed and `prefix/name` resolved
  nowhere; W1d diagnosed it (`cycle-prefix-message`, tier 2a). B2b's prefix names
  the *file*, and the W1a prescan has already registered that file's signatures
  and `emit-ns` its namespace, so the spelling resolves. The tier,
  `g-cycle-prefixes` and `cycle-suppressed-prefix-path` are gone, and the
  `w1d-cycle-prefix-diagnosed` probe is now `w1d-cycle-prefix-resolves`,
  asserting the answer (6). Three of W1d's "four things a cycle does not carry"
  remain.

**One filter was NOT accidental and had to become a rule.** `sym-private`.
Injection skipped a private symbol unless `unsafe/import-private` had set
`g-import-include-private`; that flag is transient, so with injection gone the
permission has to live on the *binding*. `ImportBind` gained `private:i32`,
`scope-frame-find-public` is the filtered scan, and a private prefixed import
additionally probes the imported file's W5e `#pN/` key space. Two things about
that are worth keeping:

* An imported file with no `(ns …)` is in `user`, so when the importing file is
  *also* in `user` the two namespaces compare equal — the "a file may see its own
  namespace's private names" branch fires and swallowed the private probe on the
  first cut. That is the ordinary case, not a corner;
  `examples/unsafe-spellings.nuc` caught it immediately. The fix is to make the
  private probe a fallback of the whole qualified path, not of its else-branch.
* The rule is **stricter** than injection in one place, correctly: a private
  definer inside an explicit `(ns …)` keys as `ns/name` with `sym-private` set,
  so a plain prefixed import would otherwise have found it through the namespace.

**`unsafe`: what fell out for free, and what did not.**

* **Free.** Binding it is four lines in `resolve-spelling`'s cascade. With that,
  `unsafe/x` is never reported as an out-of-scope qualifier, and `(ns unsafe)`'s
  refusal is genuinely "the name is pre-owned" rather than a bespoke check.
* **Not free, and §8.3 had the mechanism backwards.** It says the seven
  `unsafe/*` strings are "matched whole-string before any slash split, so they
  never reach the resolver". Measured: the *dispatch* never consulted the set at
  all — `emit-list` and `node-type-call` compare the interned head pointer against
  `'unsafe/cast` and friends. `g-special-form-set` has exactly **one** consumer,
  `name-existing-kind`, so the seven strings were purely a *reservation*.
  Removing them is therefore a reservation change, not a dispatch change, and it
  requires `special-form-named` to answer by resolving the qualifier and
  consulting a roster (`unsafe-qualified-op` / `unsafe-op-named`). Without that,
  `(defn unsafe/cast …)` would have become legal and permanently shadowed —
  silently, since the ladder would still win.
* **Half free.** "Bare `cast`/`ptr+`/`funcall-ptr-*` stop resolving for free" is
  true for **six** of the seven refusals. Their bare spelling *is* the namespace
  member's bare name, so deleting the refusal leaves them unbound, and a roster
  tier (`unsafe-bare-message`) reproduces the old sentence verbatim — five pinned
  diagnostics unchanged, including `w4a-bare-cast-head`'s line attribution. The
  seventh, `unsafe-import-private`, is a *different string* from
  `import-private`: it is not a bare spelling of a namespace member under any
  name, so no binding can refuse it and its own top-level arm stays. The six had
  to leave `emit-list` and `node-type-call` **together** — the lockstep — or the
  non-emitting pass would die where codegen no longer does.

**Two gates became one, and the diagnostic kept both tiers.** `resolve-spelling`
is the only gate; `prefix-out-of-scope` is deleted.
`unresolved-name-message`'s prefix tier became `qualifier-scope-message`, whose
head is uniform ("'q' is not in scope in this file") and whose note has two
tiers: B1's — naming the file that *does* bind the prefix, the actionable half —
and B2a's general rule. That is what removes §9.2's measured disagreement: a file
that `import-use`s a namespaced library can now name `geom/area` as well as its
protocols, and a file that binds neither is refused both, with one explanation.

**Verification.**

* `make` clean; `make bootstrap` at its fixed point (`stage1.ll == stage2.ll`),
  stage 2 compiles and runs `hello.nuc`.
* `NUCLEUS_TEST_JOBS=1 make test` → **441 PASS, 0 FAIL** (438 + three new; the
  W1d probe converted from a rejection to a run, which is net zero).
* **Byte-for-byte inert on emitted IR**, measured twice. Against a compiler built
  from a clean `HEAD` worktree: **181 of 182** files in `examples/` + `lib/`
  `diff`-identical; the 182nd is `examples/w9-dyn-ns.nuc`, which the `HEAD`
  compiler *rejects* (B2a rewrote it to the `dpx/` spellings only the fix
  accepts), so there is no IR to compare — the artefact B2a already reported.
  Against B2a's own recorded post-fix IR for the same 182 files: **182 of 182
  identical**, which is the sharper statement because it isolates B2b.
* `tests/resolution-matrix.sh --check` → the seven predicted cells moved and
  nothing else changed *status*. Eleven cells changed *message* only, all of them
  the folded qualifier tier now answering where W1c's reachability message used
  to: every `nope/` cell, `overloaded-fn zn/`, `struct-ctor zn/`, and
  `xfile-prefix-leak zx/` (B1's head folding into the shared one). Re-recorded.
* `examples/export-test.nuc`, `import-prefix.nuc`, `ns-mangle.nuc`,
  `w9-dyn-ns.nuc`, `unsafe-spellings.nuc` all build and run against their
  expected output. `import-prefix.nuc` is the one that proves the C-header path
  needs no aliasing: `c/printf` canonicalises back to `printf` because a header
  spelling has no `(ns …)` and therefore answers `user`.

**Still open after B2b.**

* **`g-import-include-private` stays set for the whole nested import**, so a
  library imported *by* an `unsafe/import-private` target records its own binds
  as private too. Pre-existing (the flag was equally global under injection) and
  faithfully preserved rather than tightened; save/clear/restore around the
  imported file's body is the one-line fix if it ever matters.
* **A prefixed import of a `user`-namespace library still leaks its bare
  names**, because `do-import` registers the imported file's globals under their
  own keys and a `user` key *is* bare. §8.3 row 2 says the prefix should be the
  whole of what the import binds. Closing it needs per-file visibility over
  `g-globals` — the same machinery `import-only`'s filter (R5) needs. Neither is
  B2b's.
* **`type-annot nope/` is still `ok`** — the type registries are B3′.

## 10. Still open *(resolved by §11)*

* **Collision reporting: eager or lazy** (§8.2). Recommended lazy; wants a
  measurement of how many `import-use` pairs in `lib/` would collide eagerly
  before committing.
* **Does `import-only` bind the namespace qualifier too?** Table in §8.3 says
  yes, for consistency with `import-use`; arguably it should not, since the
  point of `import-only` is a narrow surface.
* **`export`** re-exports under the host namespace by re-`scope-define`-ing
  into `g-globals` (`src/nucleusc.nuc:12419`) — a `g-globals`-only mechanism
  with the same blind spot as `import-prefixed`. Under R1 its keys change.
  `lib/nsgfacade.nuc` is the existing fixture.
* **`examples/w9-dyn-ns.nuc` becomes invalid as written** and should be
  rewritten to spell `dpx/Describe` throughout — it is the natural acceptance
  fixture for B2.

---

## 11. Second ruling round (2026-08-08) — measured

§10's three questions were answered, plus a confirmation on the w9 fixture.
The A-vs-B choice is **still open**; §11.5 records what these rulings do to it.

### 11.1 R4 — eager collision reporting

> *Eager. If this collides inside the compiler or libraries, the `import-use`
> was already sloppy and should become `import-only` (few symbols, no real
> collision) or `import-prefixed` (many symbols, or genuine collisions).*

**Measured across `src/*.nuc` + `lib/*.nuc`, public definers only:**

| Kind | Total | Defined in 2+ files |
|---|---|---|
| `defstruct` | 67 | **1** — `Node` |
| `defprotocol` | 19 | 1 — `Describe` (the deliberate `dp`/`dp2` w9 fixture, never co-flattened) |
| `defunion` / `defmacro` / `defconst` / `defenum` / `defvar` | 3 / 29 / 38 / 6 / 181 | **0** |
| `defn` | 1053 | 29 — overloads; collide only on *signature* under §8.2, and a same-signature pair is already an error today |

Conversion surface: **123 `import-use`** (31 `src/`, 92 `lib/`), **0
`import-only`**, **1 `import-prefixed`**.

So eager reporting costs **one** casualty — and it is not sloppy hygiene, it
is a latent bug:

**`Node` is defined twice, with different field types.**

```lisp
; lib/prelude.nuc:13          ; lib/list.nuc:17
(defstruct Node                (defstruct Node
  kind:i32 line:i32 i:i64        kind:i32 line:i32 i:i64
  s:ptr                          s:ptr
  (car (raw Node))               car:ptr
  (cdr (raw Node)))              cdr:ptr)
```

`src/type-mangle.nuc:10` does `(import-use list)` and the prelude is implicit,
so **every compiler build has both**. `emit-defstruct` silently discards the
second, by an explicit guard that names the case:

```lisp
; Skip if its definition was already written to IR — covers
; redefinition (the prelude defines Node and some programs also do).
(when (and (!= existing null) (!= (existing emitted) 0)) (return))
```

The prelude wins on import order. Nothing has broken because the two layouts
are ABI-identical (six slots; `(raw Node)` is a pointer) — but the declared
*nullability* differs, and which one a `.nuc` file gets is decided by import
order. This is the same class of defect W1 spent a whole item removing.

**One clarification the measurement forces.** §8.2 phrased a collision as
"two flattened *namespaces* both define N". Under that phrasing `Node` is
**not** caught — `prelude` and `list` are both `user`. The rule that catches
it is the broader one: **two definitions of one name reaching one scope**,
regardless of namespace. Recommend the broader phrasing; it is the reading
that finds bugs, and it subsumes the cross-namespace case. Note it makes the
"already emitted, skip" guard above an error site rather than a silent return
— which is the whole point.

**Consequence for the tree:** `lib/list.nuc` should stop redefining `Node`
(it is the prelude's type, and `list.nuc`'s own `cons` already type-checks
against the prelude's). That is a one-file fix, not a 123-import migration —
the `import-use` count is *not* a conversion backlog, because same-namespace
`import-use` of non-colliding names stays legal.

### 11.2 R5 — `import-only` does not bind the namespace qualifier

> *Probably shouldn't; its goal is a small surface. Push back if that is worse
> than it sounds.*

**Accepted — mild push-back only.** But the ruling governs a form that does
not yet do its job: **`import-only` currently filters nothing.**
`emit-import-only` calls `do-import` with `prefix = null` — full flatten — and
the symbol list is a comment (`src/nucleusc.nuc:13397`, "the documented intent
(and the N3 visibility filter's input)"). Measured: `(import-only zzonly
only-a)` still resolves the unlisted `only-b` *and* the unlisted type `OnlyS`.
So R5 is a rule for a filter that B-work has to build first.

Two consequences of not binding the qualifier, neither fatal:

1. **Every type you name must be listed.** If `(import-only vector vector-new)`
   returns a `(Vector T)`, you cannot write `Vector` in an annotation without
   listing it. Survivable — inference covers most positions — but it is a real
   ergonomic edge, and the small-surface goal is what pays for it.
2. **The diagnostic becomes load-bearing.** An unlisted name must not
   degrade into W1c's `not defined anywhere in this compilation unit`, which
   would be a lie. It needs: *"`Vector` is defined in `coll`, which this file
   imports with `import-only`; add it to the list, or use `import-prefixed`."*
   Treat that as part of the ruling, not a follow-up.

No disambiguation escape hatch is lost — R4 already routes genuine collisions
to `import-prefixed`.

### 11.3 R6 — `export` is correct as shown

Confirmed, and §10's bullet is withdrawn as a question. `lib/nsgfacade.nuc`
re-exports `geom/area` and `geom/perimeter` under `gfacade`, and
`examples/export-test.nuc` reaches them through a *third* name (`g/area`, via
`import-prefixed nsgfacade g`) resolving to the original `@geom__area`. That
is the intended facade behaviour and it survives §8.3 unchanged.

`export` is `g-globals`-only, so a facade can re-export functions and values
but not a type, protocol, macro or template. `examples/export-test.nuc`
exercises functions only. **This is a scope limit today and a blocker after
R1** — see §11.6, which supersedes the "not a defect" reading.

### 11.4 R7 — `examples/w9-dyn-ns.nuc` becomes invalid

Confirmed. It is the acceptance fixture for **B2**: rewritten to spell
`dpx/Describe` and `dpx2/Describe` throughout, with `dp/Describe` expected to
*fail*. Its header comment — which currently explains that an import prefix
"aliases `g-globals` entries; it does not name protocols" — documents the
defect as if it were the design, and must be rewritten with it.

> **Done in B2a, 2026-08-08.** The example spells `dpx/`/`dpx2/` throughout, its
> header records the fixed behaviour, and `tests/expected/w9-dyn-ns.out` is
> unchanged (105/207/309). `dp/Describe` is pinned as an error by
> `tests/fixtures/b2a-ns-not-in-scope.nuc` (the `extend` position) and
> `tests/fixtures/b2a-dyn-ns-not-in-scope.nuc` (the box position), with
> `run_b2a_scope_diagnostic` asserting the note and its non-degradation.
> `tests/fixtures/w9-ns-proto-nonconform.nuc` moved to `dpx/` as well and its
> expected message is unchanged — the reference resolves through the import
> environment but still lands on the protocol's namespaced identity
> `dp/Describe`, which is what the message names.

### 11.5 What the rulings do to the A-vs-B choice

They **narrow the gap, and then argue for B.**

* R1 already forces the type registries to be re-keyed (B3′). Re-keying was
  the main back-half work distinguishing B from A, so B has absorbed most of
  what made A attractive.
* What still separates them is unchanged: A replaces the eleven registries
  with one table and routes ~200 call sites through it; B keeps the registries
  and canonicalises in front of them.
* **R2 is now evidence against A.** §8.2 concluded generics should stay
  bare-keyed with methods merged across namespaces and the qualified spelling
  recovered by filtering `Method.src-ns` — because that is what an open
  multimethod wants. A single uniform binding table would need a per-kind
  exception for exactly that case, i.e. A cannot be uniform where it matters
  most. The kinds genuinely differ, and B is the shape that admits it.

The honest statement of the remaining choice: **A buys one lookup path and one
priority order at the cost of ~200 call sites and a per-kind exception it
cannot avoid; B buys the same observable semantics — every defect in §3
closed — with the registries left in place.** B5 (reconciling the two priority
orders) is what recovers A's main non-cosmetic benefit without A's cost.

### 11.6 Why a facade cannot re-export a type or protocol

Measured — both fail, identically:

```
lib/zzfac.nuc:3: error: export: symbol not found: 'zg/Pt'
lib/zzfac.nuc:3: error: export: symbol not found: 'zg/Zproto'
```

**The mechanism.** `emit-export` (`src/nucleusc.nuc:12419`) is two lines of
real work: `scope-lookup g-globals spelling`, then `scope-define g-globals`
under the host namespace with the same type and `ir-name`. Types live in
`g-structs` and protocols in `g-protocols` — neither is in `g-globals` — so the
lookup misses and the form dies. It is not that re-export is hard for these
kinds; it is that `export` was written as a `g-globals` operation.

**Why it was written that way, and why it was fine.** Under the current model
`g-globals` holds the *only* names with namespace-scoped visibility. A type
name is bare-keyed and globally reachable from anywhere under any qualifier
(§2.2, defects #4/#7) — so a type never *needed* re-exporting. `export` covers
exactly the set of names that can be out of scope. Consistent, given the
model.

**R1 breaks that.** Once type identity is namespaced, `geom/Pt` stops being
globally visible. A facade that re-exports `geom/area` but cannot re-export
`geom/Pt` then exports a function whose signature names a type the consumer
has no way to spell — a facade that does not work. The same argument applies
to protocols the moment a facade re-exports a method (`(dyn P)` needs `P`
nameable) and to templates.

**So generalising `export` moves into B3′, not "later".** It is small once the
canonicaliser exists: `export` resolves its argument through `resolve-name`
(which already returns the kind and the payload), then re-registers under the
host namespace in *whichever* registry the kind names. That is the same
one-path shape as everything else in this document, and it is a good check on
it — a resolver that cannot express "re-register this binding under a
different name" is not carrying enough information.

### 11.7 The duplicate `Node` — fixed, not worked around

> *Ruling: `Node` having two definitions is a mistake — probably an artifact of
> needing it available for macros before namespaces existed. Fixing it is
> preferable to working around it.*

**Done.** `lib/list.nuc`'s `(defstruct Node …)` is removed; the file now uses
the prelude's. The header comment records what was there and why it went.

The change is inert by construction: `emit-defstruct`'s "already emitted"
guard meant the prelude's declaration *already* won in every build containing
both, so `list.nuc`'s own `cons`/`car`/`cdr` were already type-checking against
the prelude's `Node`. Nothing in the tree imports `list` without the prelude —
the `exclude-prelude` users (`lib/avr.nuc`, the four AVR examples,
`tests/fixtures/*`) import no list.

**Verification:**

* `make` clean; `make bootstrap` reaches its fixed point (`stage1.ll ==
  stage2.ll`) and the stage-2 compiler builds and runs `hello.nuc`;
* `NUCLEUS_TEST_JOBS=1 make test` → **429 PASS, 0 FAIL**;
* **byte-for-byte inert on emitted IR**, proven rather than assumed: the IR
  emitted from a clean `HEAD` worktree by the same boot compiler is
  `diff`-identical to the IR emitted from the working tree. (`boot/nucleusc.ll`
  is *not* a valid baseline for this — it is stale at `HEAD`, differing by
  ~27k lines from what `HEAD` itself emits.)

This closes R4's one measured casualty ahead of the eager-collision work, so
when that rule lands it should find the tree already clean.

---

## 12. A vs B from first principles

With R1–R7 resolved, the comparison simplifies. Written short deliberately;
§5 and §11.5 carry the longer versions.

### 12.1 What the job is

Resolution is four steps, not one:

1. **spelling → canonical name** — split on the first interior slash; resolve
   the qualifier in the *file's import environment*; qualify a bare name by the
   current namespace and the flattened set.
2. **canonical name → binding** — find the thing.
3. **binding → kind check** — is a type legal in this position? a macro? a
   value?
4. **definition side** — the same canonicalisation, plus collision detection.

**A and B are identical on 1, 3 and 4.** Both need the import environment, both
need `name-existing-kind` promoted to return a payload, both need the same
collision rule. Everything in §9's B0–B2 and B4–B5 is common ground.

The entire difference is **step 2**: is there *one* map from canonical name to
binding, or *eleven* payload stores probed in a fixed order?

### 12.2 The principle that actually separates them

Eleven registries exist for a real reason: eleven kinds have different
**payloads** and different **lifecycles** — template stamping mints
`StructDef`s mid-emission, macros are JIT-compiled, a `Generic` accumulates
methods across imports. That is storage, and it is irreducibly per-kind.

But **naming is not storage.** Scope, visibility, collision, provenance,
re-export, enumeration — these are uniform concerns that do not care what a
name denotes. Today they are implemented eleven times, which is why §3 has
nine defects and no two rows of §2's matrix are wrong the same way.

So the question is narrow: **should the name→binding map be authoritative (A),
or advisory over registries that remain the truth (B)?**

### 12.3 What the rulings did to the balance

**Toward B — the kinds genuinely differ (R2).** §8.2 concluded generics stay
bare-keyed, methods merged across flattened namespaces, with a qualified
reference filtering on `Method.src-ns`. That is what an open multimethod wants,
and it means one binding maps to a *set* spanning namespaces. A's table cannot
be uniform there; it needs a per-kind arm regardless. Add §4.2 — a struct is a
type *and* a constructor, a protocol is a protocol *and* a box type *and* a
family of generics — and "one name, one thing" is simply not true.

**Toward A — every binding-moving operation is O(kinds) under B (R6).**
`export` must take a resolved binding and re-register it under another name in
whichever registry its kind names. Under A: assign one entry. Under B: a switch
over eleven kinds. And `export` is not alone — `import-only`'s filter (R5, not
yet built), REPL redefinition, `.nuch` replay, and the apropos/locate/doc
tooling that [../stage12/namespaces.md](../stage12/namespaces.md) §Tooling
plans, are all *enumerate* or *move* operations over bindings. Each is one
line under A and eleven under B, forever.

**Toward A — collision detection becomes structural (R4).** Eager reporting
under one table is `if present, error` — impossible to miss. Under eleven it is
`name-existing-kind` probing all of them in the right order at every definer,
which is precisely the mechanism that already has a hole: `NK-PROTOCOL` is
declared, accepted as an input, and **never returned**, so a protocol/struct
clash is caught only by the accident of prescan ordering. That bug is not
incidental — it is the failure mode of the B shape.

**Neutral — R1 narrowed the gap.** Re-keying the type registries was the main
back-half work distinguishing the two. B now does it anyway (B3′), so B has
absorbed most of A's re-keying cost without acquiring its benefits.

### 12.4 Scorecard

| | A | B |
|---|---|---|
| Fixes §3's nine defects | yes | yes |
| Call sites touched | ~200 | the same key *computations*, but call sites mostly keep their spelling |
| Collision invariant | structural | maintained (and today's version has a hole) |
| Cost of the *next* namespace feature | O(1) | O(kinds) |
| Cut-over | all-or-nothing per kind, no fallback | kind-by-kind, old lookup as fallback |
| Bootstrap risk | higher — every edited site is a lockstep hazard | lower, and independently verifiable per step |
| Honest uniformity | needs per-kind arms anyway (R2, §4.2) | admits it up front |

### 12.5 How to decide

The two are not alternatives in sequence: **B is a strict prefix of A.** The
import environment, the canonicaliser, the re-keying, the collision policy and
the shared priority table are all prerequisites for A and all survive it. The
only B work A would delete is the per-kind switches. Roughly: B is most of the
work, and none of it is wasted if A follows.

That makes the real question **not** "which end state" but "**how much do we
pay now for the operations we have not written yet**". If `export` for types,
`import-only`'s filter, and namespace-aware REPL tooling are all coming — and
R5 and R6 say the first two are — the O(kinds) tax in §12.3 is paid repeatedly,
and A is worth its cost. If they are not, B's observable semantics are
identical and its risk is materially lower.

**Recommendation: commit to B0–B2 now** — they are unconditional, they fix the
reported defect, and they are the front half either way. Take the A/B decision
at the B3′ boundary, when the canonicaliser exists and the remaining cost is
measurable rather than estimated.

### 12.6 Measured from B2a: what one kind actually cost

The canonicaliser now exists and one kind has been cut over, so §12.5's
"measurable rather than estimated" is available for the first kind. Recorded
before the second one, deliberately.

**The mechanism is genuinely shared.** `resolve-spelling`, `NameRef`/`NR-*`, the
`path → ns` record, `ns-qualify-in`, the prefix/flattened-set accessors, and the
`qualifier-scope-note` / `with-qualifier-note` diagnostic pair — roughly 200 of
the ~290 new lines — contain no mention of protocols and are reusable verbatim.
Nothing about them was bent to fit the first kind. That is the good news and it
is real: B2b gets the front half for free, and so does B3′.

**But "cut a kind over" is not "call the canonicaliser."** The per-kind work was
three things, and only the first is small:

1. a ~20-line probe cascade over that kind's registry (canonical key; stop if
   qualified; else bare; else the flattened set) — mechanical, and the part A's
   single table would delete;
2. **splitting the kind's lookup into a reference resolver and a key lookup**
   (`protocol-lookup` vs `protocol-lookup-ns`, plus `protocol-resolve-any` for
   the positions downstream of a gate);
3. **classifying every existing call site as one or the other** — 13 sites, by
   hand, by reading what each one holds. Not mechanical: `(protocol-lookup
   (crec proto))` and `(protocol-lookup (type-node s))` are the same expression
   over different provenance, and getting one wrong is either a false rejection
   or a silently unclosed hole.

(2) and (3) were the whole risk and most of the thinking. And the load-bearing
observation for the A/B decision is this: **A does not remove them.** The
distinction is between a *source spelling*, which must be resolved in the file
that wrote it, and a *stored canonical key* read back later — from a `.nuch`, a
`Constraint`, a super-protocol edge, a `(dyn P)` box, a prescan — usually in a
different file. That distinction is a property of the *provenance of the string*,
not of the shape of the registry, so a single authoritative binding table needs
exactly the same two entry points and exactly the same call-site audit. A deletes
item (1) and leaves (2) and (3) untouched.

So the honest answer to "one shared mechanism absorbing a kind, or a per-kind
special case wearing a shared name" is **the former for the front half and
neither for the back half**: the back half is not per-kind *special-casing*, it
is a per-kind *audit*, and it is invariant under the A/B choice. That moves the
scorecard's "cost of the *next* namespace feature: O(1) vs O(kinds)" row — the
O(kinds) term is smaller than §12.3 assumed, because the dominant per-kind cost
is paid under A as well.

One further data point, toward neither: the hardest single decision in B2a —
that `(dyn P)`'s *memo key* must stay phase-stable and environment-free while its
*admission check* is environment-gated (§9.2) — is not a resolution question at
all. It is a question about when a registry key is computed relative to when the
file's environment exists. Any kind whose key is minted during a prescan has it,
under either design.

### 12.7 Measured from B2b: the largest kind, and what it says about A vs B

§12.6 recorded the cost of the first kind (13 sites, protocols). B2b is the
largest (59 sites, every function/global/constant/enum member in the compiler),
so the estimate is now bracketed at both ends. **B2a's conclusion survives, with
one correction and two additions.**

**(i) What a single authoritative binding table would have saved: less than
§12.6 implies, and the reason is new.** §12.6 said A deletes item (1), the
per-registry probe cascade. Measured for globals, the cascade is *not* mostly
per-registry. `globals-lookup-ref` is ~40 lines, of which the registry-specific
part — "scan this frame for this key" — is two lines, and the rest is **policy**:
which keys to try (current namespace, then each flattened namespace, then
`user`), in which order, and whether a private entry counts. That policy is
identical for every kind and would still have to be written once under A. So A
deletes roughly *two lines per kind*, not twenty, and only once the policy exists
somewhere to be shared. Against the actual size of this chunk, that is noise.

**(ii) The call-site audit was the chunk.** 59 sites, read individually. But the
new observation is that the split's *difficulty is not uniform across kinds*,
and globals were easier than protocols for a structural reason worth recording:
for `g-globals` the reference/key line coincides with a syntactic property — a
key site is one paired with a `scope-define`. Eight of the 59 have that shape and
every one of them is a key. Protocols had no such tell (§12.6's
`(protocol-lookup (crec proto))` vs `(protocol-lookup (type-node s))`).

That makes the audit cheaper per site here, but it does **not** make it
mechanical, and the residue is the interesting part: ~15 sites look up a string
the *compiler itself* wrote (`"printf"`, `"default-allocator"`, `"fn"`), which is
neither a user spelling nor a stored key. Nothing in the code distinguishes them,
both classifications compile, and every test passes either way — the only
observable consequence is whether a namespaced file can reach the prelude. That
is a silent decision, and A does not remove it: it is a question about what the
string *means*, and a single table has the same two entry points. §12.6's core
claim is confirmed by the larger sample.

**(iii) Two things that argue FOR the one table, neither recorded in §12.**

**A kind with no storage has nowhere to live under B.** `unsafe` is a namespace
with no registry: no payload, no entries, nothing to canonicalise *in front of*.
Under B it had to be expressed three times — an arm in `resolve-spelling`'s
cascade, a hand-written roster (`unsafe-op-named`), and a hook in
`special-form-named` so the qualified spellings stay reserved. Under A it is
seven rows in the binding table with kind `NK-SPECIAL` and a null payload; the
roster and the hook both disappear, and the reservation is structural rather than
remembered. B's organising idea is "naming is a front end over the registries",
and this is the case where there is no registry — the shape B admits it does not
have. §12.2 argued the eleven registries exist because payloads and lifecycles
differ; it did not consider a binding with *no* payload, and the language has at
least one.

**Privacy is a uniform naming concern that is currently enforced for exactly one
kind — and B2b is what made that visible.** Deleting alias injection moved the
`sym-private` filter out of a copy loop and into resolution, which is right; but
it also showed that `private` lives on `Sym` and nowhere else. `defstruct-`,
`defunion-`, `defmacro-` and `defprotocol-` are accepted spellings that "have no
Sym at all" (`emit-toplevel-forms`' own comment), so their privacy is **not
enforced by anything**. That is §12.2's list — scope, visibility, collision,
provenance — with visibility implemented once out of five kinds, and B3′/B4 will
each have to add their own. This is the same failure mode §12.3 identified in
`NK-PROTOCOL` (declared, accepted as input, never returned), found independently
in a second uniform concern. Two instances of one class is a pattern, and it is
the strongest single argument for A that this work has produced.

**Net.** B2b does not change the recommendation to take the decision at the B3′
boundary, and it does not change §12.6's finding that the dominant per-kind cost
survives either choice. What it adds is that the *case for A* is better than §12
records: not because the probe cascades are expensive (they are not), but because
B has no home for a binding without a registry, and because per-kind
implementation of a uniform naming concern is already demonstrably
under-delivered — twice.

---

## 13. The decision, with the shared work built

B0, B1, B2a and B2b are done: 441 tests, `make bootstrap` at its fixed point,
IR byte-for-byte inert. §12 was written before any of it. This section is the
synthesis, and it changes the recommendation — not toward A or B, but to a
third shape that the measurements point at and §12 did not consider.

### 13.1 What the build measured

Two of §12's claims did not survive contact.

**§12.4's "cost of the next kind: O(1) vs O(kinds)" was wrong.** Cutting a kind
over is three things — a per-registry probe, splitting the kind's lookup into a
reference resolver and a key lookup, and a by-hand audit of every existing call
site by provenance. A removes only the first, and B2b narrowed even that: in
`globals-lookup-ref`, ~40 lines, the *registry-specific* part is **two** (scan
this frame for this key). The rest is policy — which keys to try, in what
order, whether a private entry counts — which is identical across kinds and
belongs in the shared canonicaliser under either design. **A deletes ~2 lines
per kind here, not ~20.**

**§12.3's structural-defect argument was half right.** A prevents
*forgot-to-probe* bugs. It does nothing for *wrong-phase* bugs: B2a found the
`(dyn P)` annotation gap is blocked by prescan ordering — validating in
`dyn-type` would reject every legal reference, because the root file's prescan
runs before any import is processed — and any kind whose key is minted during a
prescan inherits that under either design.

Set against that, B's incremental method is now *demonstrated* rather than
argued: three cutovers, each with zero test regressions and IR proven identical
against a clean `HEAD` worktree.

### 13.2 The two findings that strengthen A

Both are B2b's, and neither is in §12.

**A binding with no payload has no home under B.** `unsafe` is a namespace with
no registry at all. Under B it took three hand-written pieces — a cascade arm,
a roster, and a `special-form-named` hook. Under A it is seven table rows with
a null payload, and the reservation becomes structural. §12.2's framing
("naming is not storage") is right, but it assumed every binding *has* storage.

**Uniform naming concerns are demonstrably under-delivered per kind — twice.**
- Collision detection: `NK-PROTOCOL` is declared, accepted as an input to
  `guard-name-kind`, and **never returned**, because `name-existing-kind` never
  probes `g-protocols`.
- Privacy: moving `sym-private` into resolution exposed that `defstruct-`,
  `defunion-`, `defmacro-` and `defprotocol-` are accepted spellings whose
  privacy **nothing enforces** — they have no `Sym`, and `Sym` is where privacy
  lives. One of five kinds implemented.

Two independent concerns, same failure mode, neither found by reading. That is
a pattern, and it is the strongest evidence this work produced.

### 13.3 The shape the evidence actually points at

The pattern in §13.2 is not an argument for one *storage* table. It is an
argument for one *interface*. The concerns that keep going missing — collision,
privacy, kind-checking, enumeration, re-export — need five operations per kind,
not a shared payload:

```
probe(canonical) -> binding | none
kind-noun
is-private(binding)
src-ns(binding)
re-register(binding, new-canonical)
```

One table of eleven rows, each exposing those. The registries stay; the ~200
lookup call sites keep their spelling. Only the uniform concerns route through
the interface — and adding a kind means adding a row, so a missing one is
visible rather than silent.

This answers both of §13.2's findings directly: a payload-free binding is a row
whose probe consults a roster (the `unsafe` case), and privacy is implemented
once against `is-private` rather than once per kind. It also subsumes B5 —
reconciling `name-existing-kind` and `emit-dispatch`'s disagreeing priority
orders is what the shared `probe` column *is*. And it recovers §12.3's
`export`-for-types argument via `re-register`, which §11.6 independently
concluded the resolver must be able to express.

Cost: an interface row per kind, plus rewriting the five concerns against it.
Not ~200 call sites. Call it **B+**.

### 13.4 Recommendation

**Take B's path; make B5 a shared binding interface (§13.3) rather than merely
reconciling the two priority orders.** B+ captures what A is genuinely for —
uniform concerns implemented once, and a missing kind that is visible instead
of silent — without A's call-site rewrite through the compiler's hottest path,
and without forcing the per-kind exception A needs anyway for generics (§8.2)
and multi-facet names (§4.2).

Full A stays available: B+ is still a strict prefix of it, and after B3′ the
remaining delta is one payload move behind an interface that already exists.

**What would change this:** if namespaces become pervasive in user code, or
several more kinds arrive, the per-kind audit recurs often enough that
consolidating storage pays too. Speculative today — the compiler and stdlib are
entirely `user` + `import-use`.

### 13.5 Correction to §8.3

§8.3 said removing the seven `unsafe/*` strings from the special-form set is "a
dispatch change, not a resolver change". **That is backwards.** `emit-list` and
`node-type-call` compare interned head pointers and never consult
`g-special-form-set`, which has exactly **one** consumer: `name-existing-kind`.
The strings were purely a *reservation* — removing them without replacing it
would have made `(defn unsafe/cast …)` legal and permanently shadowed.

Relatedly, §8.3's "bare `cast`/`ptr+`/`funcall-ptr-*` stop resolving for free"
holds for **six** of the seven, not seven: `unsafe-import-private` is a
different string from `import-private`, so no binding can refuse it and its
top-level arm remains.

---

## 14. What B5 built — the shared binding interface

**Status: done 2026-08-09.** §13.4's recommendation, taken as written: B's path,
with B5 upgraded from "reconcile the two priority orders" to the interface of
§13.3. It is the frame B3′ and B4 fill in, which is why it landed before them.

### 14.1 The encoding, and why not fn-pointer fields

**A kind tag plus a `case` dispatch**, not fn-pointer struct fields — chosen
deliberately, and the reason is cost, not taste. Three open W9 defects sit in
the fn-pointer path: `(= h null)` does not compile for a `TY-FN` value
(`emit-binop-vals` gates on `is-ptr-like`, which excludes `TY-FN`), `type-size`
has no `TY-FN` case so a fn-pointer slot emits `align 1`, and `coerce-int-val`
has no `raw`→`TY-FN` case. A vtable-shaped table would have had to fix all
three first — moving the emitted IR of every fn-pointer program
(`examples/fnptr.nuc`, `fn-ptr-union.nuc`, `l7-probe.nuc`) — to buy nothing this
interface needs, since the dispatch is over a *closed* set of thirteen rows that
changes only when a registry is added. A tag is still exactly one table; the
five operations are `case` functions beside it, and each one is a single
thirteen-arm `case` whose missing arm is a compile-time-visible omission rather
than a null field.

`BindingKind` and `BindingHit` (`src/compiler-types.nuc`) follow the established
`NsPrefixEntry` / `ImportBind` / `NameRef` idiom: a record plus a
`(Vector (ref BindingKind))` built by `build-binding-kinds` (`src/nucleusc.nuc`,
immediately above `emit-dispatch`) through a `defvar` runtime initializer, with
the appender taking the collection (W8 G-5's rule).

`BindingHit` carries `{kind:i32, payload:ptr}`. The payload is a bare `ptr`
because eleven registries hold eleven record types; `kind` is what makes it a
discriminated union and every consumer `case`s on it before casting. This is the
one place in the compiler where an untyped pointer is the honest representation
rather than an escape hatch.

### 14.2 The rows, and what each genuinely supports

| # | Row | Registry | `collides` | `name-keyed` | `reregisterable` |
|---|---|---|---|---|---|
| 0 | `BK-MACRO` | `g-macros` | 1 | 1 | 0 |
| 1 | `BK-SPECIAL` | `g-special-form-set` + the `unsafe/` roster | 1 | 1 | 0 |
| 2 | `BK-PRIMITIVE` | `g-primitive-type-set` | 1 | 1 | 0 |
| 3 | `BK-GENERIC` | `g-generics` | 1 | 1 | 0 |
| 4 | `BK-GLOBAL` | `g-globals` | 1 | 1 | **1** |
| 5 | `BK-PROTOCOL` | `g-protocols` | **1 (new)** | 1 | 0 |
| 6 | `BK-STRUCT` | `g-structs` | 1 | 1 | 0 |
| 7 | `BK-UNION` | `g-uniondefs` | 0 | 1 | 0 |
| 8 | `BK-STRUCT-TEMPLATE` | `g-struct-templates` | **1 (new)** | 1 | 0 |
| 9 | `BK-UNION-TEMPLATE` | `g-union-templates` | 1 | 1 | 0 |
| 10 | `BK-ENUM` | `g-enumdefs` | 0 | 1 | 0 |
| 11 | `BK-FNTY` | `g-fnty` | 0 | 1 | 0 |
| 12 | `BK-CONFORMANCE` | the conformance relation | 0 | **0** | 0 |

Unsupported-by-design, stated rather than omitted:

* **`BK-CONFORMANCE` has no probe at all.** It is keyed by a *pair* of names
  (type, protocol), so `probe(canonical)` is not a question it can answer. That
  is the one genuine misfit in §1's eleven, and `name-keyed` 0 is how the table
  says so. Everything else about it — privacy, provenance, re-export — is a
  property of its two operands, not of the fact.
* **`re-register` is supported only for `g-globals`.** Every other row raises a
  located diagnostic naming the kind rather than silently doing nothing:
  `'B5ExpS' is a type — only functions and values can be re-exported`. That is
  §11.6's conclusion (a facade cannot re-export a type or protocol) said in one
  place instead of being unrepresentable. B3′ flips `BK-STRUCT` and friends when
  it re-keys them.
* **`collides` 0 on `BK-UNION` / `BK-ENUM` / `BK-FNTY`** is today's behaviour
  made visible, and it is **B4's** to revisit: a `defunion` also registers its
  backing `StructDef` under the same key so `BK-STRUCT` already answers for it;
  an enum's own name and a compiler-minted `__fnty_N` have never participated.
  `BK-STRUCT-TEMPLATE` was turned **on** — `register-struct-template` already
  *guarded* as `NK-TYPE` while nothing probed it, the same one-directional
  asymmetry `BK-UNION-TEMPLATE` did not have.

### 14.3 The two priority orders: unified, with one site named

They unified, and the reconciliation was **not** "pick emit's order". Picking it
directly *weakened* the guard, measurably: with `generic` first, a
`(defn Shape …)` over an existing `defprotocol Shape` finds the `Generic` its own
signature prescan registered a moment earlier, reports `NK-FUNCTION`, matches
what it is about to define, and never looks at the protocol. Every definer
registers its own name in a prescan before its own guard runs, so *any* order
that answers "what is the highest-priority binding?" is self-defeating for the
definer at the front of it.

The rule that makes one order possible is to change the question:
**`guard-name-kind` asks for the first binding whose kind is NOT the one being
defined** (`binding-find`'s `skip-nk`). `name-existing-kind` — which asked the
other question, and had `guard-name-kind` as its only caller — is folded into it
and gone; `binding-nk` is where a kind (including, at last, `NK-PROTOCOL`) is
now produced. That question is order-*independent* —
the table order then only chooses which of several conflicting kinds to name —
and it is strictly stronger than what it replaced: `(defprotocol P) (defn P)`
compiled clean before B5 and is now refused.

Three consumers, one list:

* `emit-list` answers rows 0–2 (its macro loop, then its interned-pointer
  special-form ladder). Its macro-before-special order is *provably* the same
  function as the table's, because the guard refuses to register a macro over a
  special form, so no name can be in both rows. That ladder was left alone: it
  dispatches by interned head pointer, not by registry probe, and rewriting it
  would move IR for no gain.
* `emit-dispatch` walks from `BK-DISPATCH-FIRST` (row 3) to the end.
* `node-type-call` walks the same list through a *window* that stops after
  `BK-GLOBAL` — the rows that yield a type. Beyond it emit only produces a
  diagnostic, and returning null there is the standing lockstep escape hatch.
  The window is the mechanism by which the mirror cannot drift: it is the same
  `binding-find` call with a different bound, not a second copy of the order.

**One site resisted and is recorded rather than forced.** Rows 1–2
(`BK-SPECIAL`, `BK-PRIMITIVE`) are deliberately outside `emit-dispatch`'s
window. Probing them there would let a bare `cast` / `ptr+` / `funcall-ptr-*`
report *"'cast' names a special form, not a function"* and lose UN-5's targeted
`unsafe-bare-message` text, which five fixtures pin and which is a strictly
better answer. The boundary is stated as a constant with that reason attached.

**A prescan had to move.** `prescan-protocols` now runs *before*
`prescan-struct-names`. The struct prescan registers a name-only `StructDef`
without guarding, so whichever ran first won every `defprotocol`/`defstruct`
clash — and the struct always ran first, which is exactly why §2.5's report was
"the message says the protocol collided with 'a type', pointing at the wrong
line". `protocol-register-form` stores its method sigs verbatim and parses them
lazily, so it needs no struct name registered yet; the reorder is safe by
construction. Both source orders now report at the *defstruct*'s own line with
`'P' already names a protocol`.

Residue, deliberate: for an **imported** file the two prescans still run in the
old order (pass 1 `prescan-imported-types` → `prescan-struct-names` for the whole
graph, then `prescan-imported-signatures` → `prescan-protocols`), so a
protocol/struct clash *inside a library* keeps the old noun. Fixing it means
giving pass 1 the per-file namespace, which is adjacent to B3′ (§9.2's (b)).

### 14.4 The privacy hole — what verifying it turned up

The hypothesis (§13.2) held: `defstruct-`, `defunion-`, `defmacro-` and
`defprotocol-` had **no carrier at all** for privacy. `StructDef`, `UnionDef`,
`StructTemplate`, `UnionTemplate`, `MacroDef` and `Protocol` had no `priv` field
and no `src-ns`, `prescan-protocols` treated `defprotocol-` as identical to
`defprotocol`, and the top-level dispatch's own comment for `defprotocol-` —
"the private flag is honored by prescan-protocols (N3)" — was **false**. Three
further things the implementation turned up, none of which reading predicted:

* **The rule is one function, but it needed six call sites, not one.** Privacy
  has to be enforced at each kind's *reference* lookup (`lookup-struct`,
  `uniondef-lookup`, `struct-template-lookup`, `union-template-lookup`,
  `find-macro`, `protocol-lookup`) because those are what a source spelling
  actually reaches; a check inside `binding-probe` alone would have left
  `parse-type-name` — every `:T` annotation in the language — unguarded. The
  *rule* is still written once (`binding-visible`, taking `priv` and `src-ns`);
  what is per-kind is supplying its two inputs, which is precisely the interface's
  `is-private` / `src-ns` columns.
* **`emit-list` had an inline macro scan, not a `find-macro` call.** It is now the
  call, which is what puts `defmacro-` behind the filter; the two scans were
  otherwise identical (first-match, content comparison).
* **The provenance must be captured at EMISSION, never in the prescan.**
  `prescan-struct-names` is reached from `prescan-imported-types`, which does not
  apply an imported file's leading `(ns …)` — so `g-current-ns` there is the
  *importer's*. Capturing `src-ns` in the prescan recorded the wrong namespace,
  and because the entry was also marked private it then became invisible to
  `emit-defstruct`'s own `lookup-struct`, which registered a **second**
  `StructDef` under the same name; the stale first entry, carrying `src-ns` =
  `user`, stayed visible to everyone. The prescan now records nothing (a
  `priv` 0 entry never consults its `src-ns`), and the four definers write both
  fields at emission. Templates needed an explicit update there, because
  `register-struct-template` early-returns once the prescan has created the entry.

Whole mechanism is short-circuited by `g-priv-bindings`, 0 for every build of
this compiler and every program in `lib/`, `examples/` and `tests/` — so it is
provably inert rather than believed to be.

Scope, per W5e's split and unchanged by B5: privacy for these four is
**namespace-level**, never file-level. A type, macro or protocol name is
bare-keyed and globally identified (Stage 12 decision 9), so in the default
`user` namespace `defstruct-` still hides nothing; a `(ns …)` is what makes it
mean something. Known residue: a consumer's *signature* prescan resolves types
before the library is emitted, so a private type named in a `defn` signature is
caught at emission rather than at the prescan; and a private type referenced from
a monomorphization running under another namespace would be refused. Both need a
private type to exist, and none does.

### 14.5 The did-you-mean echo (#9)

`closest-known-name` printed the candidate's raw registry key, and a generic is
keyed **bare** (defect #5) — so a library function reachable only as `zx/zfun`
was offered as `zfun`, the exact spelling that had just failed. Two rules now,
and the second is the belt to the first's braces: `binding-usable-spelling`
renders a candidate through the interface's `src-ns` into a spelling *this file*
can write (bare for its own namespace / `user` / a flattened one, `prefix/bare`
for a bound prefix, **null** for a candidate this file cannot reach), and a
suggestion equal to the input is never emitted. Distance is measured against the
candidate's bare name, so a qualified key can be near something.

Two restrictions are stated in the code rather than left implicit: a
`prefix/name` spelling is offered only for `BK-GLOBAL` and `BK-PROTOCOL`, the
two registries where a qualified reference actually resolves today (offering
`p/mac` or `p/SomeType` would be a suggestion that fails on the next compile —
defects #1 and #5, B3′/B4's); and a candidate that is private-and-invisible is
dropped, so the suggester cannot leak a name the resolver just hid.

### 14.6 Verification

* `make` clean from `make clean`; `make bootstrap` at its fixed point
  (`stage1.ll == stage2.ll`), stage 2 compiles and runs `hello.nuc`;
  `make abi-test` and `make layout-test` green.
* `NUCLEUS_TEST_JOBS=1 make test` → **453 PASS, 0 FAIL** (441 + 12 new).
* **IR inertness**, measured against a compiler built from a clean `HEAD`
  worktree: of the 182 files in `examples/` + `lib/`, **181 are identical** —
  177 compile and emit byte-identical IR, 4 (`examples/comb-shapes.nuc`,
  `lib/arena.nuc`, `lib/node.nuc`, `lib/reader.nuc`) are refused by *both*
  compilers with byte-identical stderr and byte-identical partial output. The
  182nd is `examples/w9-dyn-ns.nuc`, which `HEAD` **rejects** (B2a rewrote it to
  the `dpx/` spellings only the fix accepts), so there is no IR to compare — the
  same single artefact B2a and B2b reported.
* `tests/resolution-matrix.sh --check` → **no cell changed status**; two changed
  message, both of them defect #9's fix and both accounted for:
  `plain-fn bare` `(did you mean 'zfun'?)` → `(did you mean 'zx/zfun'?)`, and
  `defenum-member bare` gaining a `(did you mean 'zx/ZE-B'?)` it previously could
  not produce (the globals candidate `zn/ZE-B` was compared as a whole key and so
  was never near `ZE-B`). `defvar zg` and `defconst ZK` did **not** move: at two
  characters they are under `name-suggest-limit`'s floor. Re-recorded.
* Two existing pins were **re-pointed, not re-baselined**:
  `w8-fnptr-global-name-collision` and `g0-value-fn-collision-order2` both still
  assert *rejection*; what moved is which of the two definitions is blamed and
  therefore the noun, because the guard now fires at whichever definer is emitted
  first (§14.3). Both fixtures carry the reason inline.

### 14.7 For B3′ and B4

**B3′** (re-key the type registries, `StructDef.ir-prefix`, an ns-aware mangling
token, generalise `export`):

* The rows to re-key are 6–11. Each one's `binding-probe` arm is the *only*
  place its key policy is expressed for the shared concerns, so re-keying is:
  change the arm to `resolve-spelling` + an exact probe (exactly what `BK-GLOBAL`
  and `BK-PROTOCOL` already are), and delete the corresponding
  `strip-ns-qualifier` call in `parse-type-name`.
* `export` is already routed through `binding-re-register`; generalising it is
  flipping `reregisterable` to 1 on those rows and adding their arm. The
  diagnostic it currently raises is the specification of what has to appear.
* Two things B3′ inherits from §14.4 rather than discovers: `src-ns` must be
  captured at **emission** (pass 1's `prescan-struct-names` runs under the
  importer's namespace), and re-keying will *also* fix `type-annot nope/`, the
  last matrix cell still wrongly `ok`.
* `binding-usable-spelling`'s `BK-GLOBAL`/`BK-PROTOCOL` restriction is a
  one-line widening once types have a qualified spelling that resolves.

**B4** (R4's eager collision rule, R2's per-kind policy):

* The per-kind policy has a home: the `collides` column. R2's table (§8.2) maps
  onto it directly, and the three rows that are 0 today are enumerated in §14.2
  with the reason.
* R4's "two definitions of one name reaching one scope" needs an *enumeration*
  operation the interface does not have — `probe` answers one key. That is the
  one place B4 will have to extend the table rather than consume it, and the
  honest note is that `emit-defstruct`'s `(when (and (!= existing null) (!= (existing emitted) 0)) (return))`
  guard (§11.1's `Node` finding) is the site, not the table.
* R2's "recover the qualified spelling from `Method.src-ns`" is already the
  interface's `src-ns` for `BK-GENERIC` — it reads method 0. Filtering a
  generic's method set by `src-ns` is a change to `BK-GENERIC`'s probe arm and
  nothing else.
* `guard-name-kind`'s question (first binding of a *different* kind) is what B4
  should extend, not replace: an eager same-kind collision is the complementary
  query over the same walk.

### 14.8 Where the interface is a worse fit than eleven bespoke registries

Recorded as §13 asks, because it is a real finding.

1. **The conformance registry does not fit at all.** It is a *relation*, not a
   name→thing map, and giving it a row costs a `name-keyed` 0 that every walk
   must skip. Keeping it in the table is still right — §1 counts it, and leaving
   it out would make "eleven registries, eleven rows" false — but the row carries
   no behaviour.
2. **A payload-free row costs a sentinel.** `BK-SPECIAL` and `BK-PRIMITIVE` have
   no record, so their probe returns the spelling itself as a non-null "yes".
   §12.7 argued a payload-free binding is what B could not house; it turns out A's
   shape does not house it *free* either — it houses it with a null payload and a
   convention, which is the same convention in a different place.
3. **The window and the `skip-nk` flag are the price of one order for three
   different questions.** `binding-find` now takes six parameters. That is the
   honest cost of "one order consumed by three callers who each want a different
   slice of it", and it is cheaper than three orders — but it is not free, and a
   fourth consumer wanting a fourth slice should be a prompt to reconsider rather
   than a seventh parameter.
4. **`emit-dispatch`'s hot path pays for rows it will never use.** A struct
   literal now probes `g-generics`, `g-globals` and `g-protocols` before
   `g-structs`, where before it probed the first two. The extra scan is ~20
   strcmp. Measured on this host, best of three, both compilers emitting IR for
   the *same* `src/nucleusc.nuc`: committed boot 738 ms, B5 compiler 723 ms —
   i.e. inside the noise and if anything slightly faster. But the general shape — a table walk where a hand-written ladder used to short-circuit
   — is a real cost that grows with the number of rows, and B3′ adding per-row
   canonicalisation will grow it again.
