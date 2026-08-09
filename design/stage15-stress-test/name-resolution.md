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
| overloaded fn `(zov s)` | reaches the generic | **err** | ~~err~~ ok (B4) | err |
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
>   *(Closed in B6 — §9.5. The two positions now agree, which is the acceptance
>   criterion: the row matches `protocol-dyn-box` cell for cell.)*
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
   templates and enums have no prefixed spelling. *(Protocols closed in B2a,
   types/templates/enums in B3′, generics in B4. **Macros remain** — `g-macros`
   is keyed by the bare source name with no `qualify-name` anywhere, so `p/mac`
   cannot resolve and `binding-usable-spelling` will not suggest one. It is the
   last of this defect; §9.6.)*
2. **`import-prefixed` skips globals, constants and enum members** — the
   `is-local`/`ir-name` filter (§1.1).
3. **The defining namespace is always in scope**, whether or not the consumer
   asked for it. `import-prefixed` adds a spelling; it removes none.
4. **A qualifier on a type is never validated** (§2.2).
5. **Generics are unqualifiable** (§2.3). *(Closed in B4 — §9.6. `p/name`
   resolves to the bare generic with its method set filtered by
   `Method.src-ns`; the registry stays bare-keyed, which is R2's ruling.)*
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

Two more were found while implementing, and are numbered here so the staging
table and the matrix can name them:

10. **A `(dyn P)` in an ANNOTATION is never validated** — found in B2a (§9.2),
    recorded as "the tenth defect" from then on. `(defn f ((b (dyn nope/X))) …)`
    compiled and fabricated a box type for a protocol that exists nowhere.
    *(Closed in B6 — §9.5.)*
11. **A `(dyn P)` box's identity is keyed on a spelling-derived name** — found in
    B3′ (§9.4). Two spellings of one protocol minted two `StructDef`s, and
    `type-eq` is `StructDef`-pointer identity, so a library taking `(dyn P)` could
    not be called from a consumer holding `(dyn prefix/P)`. Strictly this is #7
    (identity) for the box type rather than a new defect, which is why §9.4
    reported it as inherited work rather than adding a number.
    *(Closed in B6 — §9.5.)*

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
   *(B3′, measured: the policy claim held, the count did not. The function
   stays, with 6 live call sites, none of them a resolution — a did-you-mean
   edit distance, the "same bare name, other namespace" diagnostic scan,
   `strip-priv-qualifier`, `export`'s bare-name derivation and
   `register-struct`'s ir-name base. It stopped being a canonicaliser; it did
   not go away. §9.4.)*
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
| ~~B3′~~ | re-key the type registries + `StructDef.ir-prefix` + ns-aware mangling token | #4, #7, R1 |
| **B3′** | **Done 2026-08-09.** All six type rows (6–11) re-keyed on `resolve-spelling` in one step rather than the planned struct/union-first split — the audit found the rows share `parse-type-name` and could not be separated (§9.4). Five *reference* resolvers (`struct-lookup-ref` / `uniondef-lookup-ref` / `struct-template-lookup-ref` / `union-template-lookup-ref` / `enumdef-lookup-ref`) over the shared candidate-key walk, with the old bodies kept as the *key* lookups; `parse-type-name`'s `strip-ns-qualifier` deleted; `StructDef.ir-name`/`ir-prefix` derived from **the key's own namespace**, so `(ns dp) (defstruct Fox …)` emits `%dp__Fox`; conformance keys namespaced on **both** halves (`type-canon-name`); `export` generalised to the type and protocol rows (`reregisterable` flipped); `prescan-file-imports` added so a file's import environment exists before any prescan that resolves a name. The new mechanism is `g-type-key-ok`, a scoped *synthesis-region* permission (`g-defvar-soft`'s shape). `type-annot nope/` moved `ok` → `err` — the last wrongly-`ok` matrix cell. See §9.4 | #4, #7, R1 |
| ~~B4~~ | per-kind collision rule; `Method.src-ns` filtering for qualified generic references | #5, R2 |
| **B4** | **Done 2026-08-09.** `generic-lookup-ref` (`src/generics.nuc`) resolves a qualified generic reference to the bare `Generic` with its method set **filtered by `Method.src-ns`** — R2's shape, and `BK-GENERIC`'s probe arm is the only consumer, as §14.7 predicted. Two provenance holes had to be closed first, neither of them predicted: `register-generic-template` never recorded `src-ns` at all (a METHOD-GENERIC filtered to nothing, so `p/tmpl` did not resolve), and a *stamp* records the CALL SITE's namespace, which had to be re-owned to the template's or the second call re-stamps. Plus R4's eager rule at ten definers, R2's `collides` policy measured per row (`BK-ENUM` was a real hole, `BK-UNION` redundant, `BK-FNTY` correctly 0), and the three tree casualties R4 found. One matrix cell moved: `overloaded-fn` `zx/` err → ok. See §9.6 | #5, R2, R4 |
| ~~B6~~ | `(dyn P)` identity vs admission | #10 |
| **B6** | **Done 2026-08-09.** `dyn-proto-key` (`src/nucleusc.nuc`) replaces `protocol-canon-name-ns` as the `(dyn P)` box's identity key: the canonical name derived from `resolve-spelling` and **no registry**, so one protocol has one box `StructDef` whichever legal spelling reached it. Admission moved to the annotation site — `dyn-annot-record` / `drain-dyn-annots` / `DynAnnot`, a deferred worklist carrying each spelling's `{path, line, ns, imports}` and drained at `emit-toplevel-forms` depth 1 after `drain-mono-worklist`; box construction downgraded to a key lookup (`dyn-resolve-protocol`). Plus `box-require-same-kind`, the `type-eq` the erased-slot coercion never had, called from **both** its call sites. Three `protocol-dyn-annot` cells moved `ok` → `err` (`zx/` stays `ok`, correctly); `examples/w9-dyn-ns.nuc`'s box types are renamed `dpx`/`dpx2` → `dp`/`dp2` and are the only IR that moved in the tree. See §9.5 | #10, #11 |
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
  **The rule survived B6 intact and is what B6 was built on; only the two
  placements moved (§9.5).** The key is still phase-stable but is now
  environment-derived rather than namespace-derived, which is *more* phase-stable
  — `protocol-canon-name-ns` consulted `g-protocols` and was stable only by
  accident of import order. And the permission is asked where it is known, which
  turned out to be the **annotation site**, not box construction: once identity is
  canonical, the name a box stores is not a name the constructing file can
  necessarily spell, so box construction is the one place the scope question must
  *not* be asked.
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

* ~~**The tenth defect stays open, and the blocker is prescan ordering, not the
  canonicaliser.**~~ *(Closed in B6 — §9.5.)* `(dyn nope/Wholly-Absent)` in an
  *annotation* still compiles.
  Closing it means validating in `dyn-type`, and `dyn-type` runs inside
  `prescan-defn-signatures` — which for the unit's root file runs *before*
  `prescan-imported-signatures`, so no imported protocol is registered yet, and
  before any import form is emitted, so `g-file-imports` is empty. Both facts
  make a check there reject every legal reference. The two real fixes are (a)
  defer annotation-site validation to a worklist drained after the whole-graph
  prescan, or (b) fill the prescan's import environment and move the imported
  signature prescan ahead of the root's own. (b) is the better one and is
  adjacent to B3′, which re-keys registries the prescan also writes.
  **B6 took (a), and (b) is now recorded as the wrong recommendation.** Moving
  the imported-signature prescan ahead of the root's own reorders every
  registration in the unit — the comment on `prescan-imported-signatures` says so
  and the bootstrap enforces it — and, more decisively, it would still not be
  enough: a `.nuc` imported by **string path** is walked by no prescan at all, so
  no reordering of the prescans makes its protocols visible to one. (a) is not a
  weaker substitute for (b); it is the only one of the two that terminates. What
  B6 additionally found is that the drain must run after *emission*, not merely
  after the prescans, for that same reason.
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
  *(Closed in B3′ — §9.4.)*

### 9.4 What B3′ built

**Status: done 2026-08-09.** R1 as §8.1 decomposed it, plus §11.6's `export`
generalisation, plus one mechanism §8.1 did not anticipate.

**The planned split did not survive the audit, and that is the first finding.**
The staging assumed types could be cut over the way protocols and globals were:
one kind at a time, each with its own reference/key split. Measured, the six type
rows (6–11) are **not separable**, and the reason is structural rather than
incidental: `parse-type-name` (`src/union-registry.nuc`) is the single entry point
for every `:T` spelling in the language, and its resolution cascade consults
`g-structs`, `g-uniondefs`, `g-struct-templates`, `g-union-templates`,
`g-enumdefs` and `g-fnty` **in one function**. Cutting `g-structs` over alone
would have left `(ref zzz/Fox)` refused while `(ref zzz/Shape)` — a union
template — still resolved, i.e. defect #4 half-closed with no way to say which
half. So B3′ re-keyed all six, and the reference resolvers are five near-identical
functions sharing one candidate-key walk (`name-ref-key-count` /
`name-ref-key-at`, `src/nucleusc.nuc`). `BK-FNTY` is the exception and is left
bare on purpose: a `__fnty_N` is minted by the compiler, has no source spelling,
and nothing can write a qualified one.

That confirms §12.7's measurement from the other direction. The per-registry
probe is ~2 lines; the *policy* — which keys to try, in what order — is one
shared function; and the audit is the work. What changes for types is only where
the audit's line falls (below).

**The reference/key line, and whether types had a tell.** Globals had one (a key
site is paired with a `scope-define`); protocols had none (§12.6). Types have a
**third** shape, and it is the one worth recording: the line is not a property of
the *call site* at all but of the **dynamic extent** the call happens in.

* A `:T` annotation, a `defstruct` field, an `extend` subject, a `(sizeof T)`
  operand — every spelling a *file* wrote — is a reference, and they all arrive
  at `parse-type-name`. There is no second call site to classify.
* But `type-spelling` renders a `Type` back to its **canonical** name, and the
  compiler re-parses that string in five places: a template stamp, a
  monomorphized body, a protocol-signature `Self` substitution, a stored
  conformance argument, and a `.nuch` replay. Those strings were written by no
  file, and the file they are re-parsed *in* is routinely not the file that
  produced them.

Classifying those per call site was tried and abandoned: they are not call sites,
they are whole *regions* — `drain-mono-worklist` re-parses arbitrarily many
spellings through `emit-node`, and threading a "this is a key" flag down every
emitter is the shape the codebase already rejects. The mechanism is therefore a
scoped permission, **`g-type-key-ok`** (`src/nucleusc.nuc`), armed with
save/set/restore around each synthesis region; the five reference resolvers take
an **exact-key fallback only while it is armed**, and only *after* the reference
walk has missed. This is W8 G-3's `g-defvar-soft` shape — soften one exit, leave
every other raise alone — and it inherits its two properties: the default is
refuse, and the permitted set is enumerable by grepping the arm sites. It is 0
for every program in the tree that declares no namespace, and the fallback runs
only after a miss, so the whole mechanism is provably inert there.

**What that mechanism costs, stated plainly, because it is the honest weakness of
this chunk.** A permission with a dynamic extent has no compile-time evidence
that its extent is complete. A *missing* arm is not a wrong answer in some corner
— it is a **false rejection of a legal program**, with a diagnostic that reads
like a user error (`unknown type: gg/Pt — 'gg' is not in scope in this file`) and
that nothing in the tree reproduces, because the tree has no namespaced type used
across a namespace boundary. Three arms were missing when B3′ was first measured
end to end, and all three were found by *running a namespaced type through the
ordinary idioms*, not by reading:

* **`tmpl-conformance-check-one` (`src/generics.nuc`)** — the per-instance check of
  a template-level `(extend (Vector T) (Seq T))`, which runs at **stamp** time in
  the stamping file. This is the widest one: every collection in `lib/` carries
  such an `extend`, so **no namespaced type could be a collection element at all**
  — `(Vector (ref gx/Pt))` was refused at `lib/vector.nuc`'s own `extend` line.
  Note the near miss: the sibling branch of the same function (`conf-arg-to-type`,
  the assoc-types path) *was* armed. One of two branches.
* **`generic-instantiate` (`src/generics.nuc`)** — the stamped **signature** parse.
  `drain-mono-worklist` already armed the stamped **body**; the signature is
  parsed earlier, before the job is queued, and was outside it. So the arm existed
  for the half of stamping that was easy to see.
* **`resolve-param-type-bound` (`src/generics.nuc`)** — the shared
  substitute-the-bound-tyvars-and-reparse helper behind `method-bound-ret-type`
  and `subst-param-types-bound`, i.e. how a return-only-tyvar generic
  (`vector-new`, the whole `*-new` family) resolves against a want. Armed at the
  helper, not at its two callers, for the reason W2a gives: mirroring a call
  cannot drift.

Generalise: **when a permission is scoped to a dynamic extent, the arm sites are
not "the functions that parse" but "the functions that produce a spelling nobody
wrote", and those are found by exercise, not by grep.** `tests/run-tests.sh`'s
`b3a-ns-type-in-collection` links and runs the composite idiom (a namespaced
struct as a `Vector` element, reached through generic dispatch, with a
cross-namespace `extend` over it) precisely because each of the three was
invisible to every other test.

**One fix was not an arm, and it is the §9.2 rule reasserting itself.**
`emit-extend` computed `typename = (type-canon-name (type-node s))` and then, a
few lines down, re-parsed *`typename`* to "validate single-token subject types
eagerly for a clean diagnostic". That is canonicalize-then-look-up-again — the
exact shape B2a removed from the protocol half — and under a scoped resolver it
asks the scope question twice and gets two answers: `(extend gx/Pt P)`
canonicalises to `b3ang/Pt` and is then refused as an unknown type. The
validation now runs on **the spelling the author wrote**, which is also a better
diagnostic (it quotes the source text). The lesson §9.2 recorded for protocols is
not protocol-shaped: any canonicaliser that can *fail* makes
`canonicalize → re-resolve` wrong, and the second half of the pair is easy to add
years later because it looks like a local validity check.

**What `strip-ns-qualifier` became.** §8.1 predicted its "10 call sites go away".
Measured: the function stays and has **6** live call sites, none of which is a
resolution any more. `parse-type-name`'s call — the one that discarded a
qualifier without checking it, i.e. defects #4 and #7 — is deleted, and the
conformance registry's type half now goes through `type-canon-name`. What remains
is `strip-ns-qualifier` as a pure **string** operation: the bare-name basis for a
did-you-mean edit distance (`suggest-better`), the "same bare name, other
namespace" diagnostic scan (`type-in-other-namespace-message`, twice),
`strip-priv-qualifier`, `export`'s bare-name derivation, and `register-struct`'s
ir-name base. The prediction was right about the *policy* and wrong about the
*count*; the accurate statement is that it stopped being a canonicaliser.

**The mangling half was already inert-correct and only had to be switched on.**
`StructDef` carries `ir-name` and `ir-prefix`, and `register-struct` derives the
prefix from **the key's own namespace** (`key-namespace` → `ns-ir-prefix` →
`ns-compose`) rather than from `g-current-ns`. That distinction is load-bearing
and is the `Generic.ir-prefix` precedent: a template instance is stamped, and an
imported type is registered, while some *other* namespace is current. `user`
composes the empty prefix and `ns-compose` is the identity on it, so every type in
`src/` and `lib/` is byte-identical; `(ns dp) (defstruct Fox …)` now emits
`%dp__Fox`, and `--emit-cheader` composes the same prefix for the same collision
reason (two namespaces' `Pt` would otherwise emit the same C typedef).

**`export` for types (§11.6), and the shape it forced.** B5 left `reregisterable`
as a stated 0 with a located diagnostic; B3′ flips it for the type and protocol
rows. The mechanism is *not* a second registration in the host namespace — a type
is identified by its `StructDef` pointer, so re-registering would mint a second
identity, which is R1's whole point inverted. It is a **re-export alias table**
(`binding-alias-find`, consulted by each reference resolver after its key walk and
before the synthesis fallback): the facade's name maps to the *same* payload. That
is the honest reading of §13.3's `re-register(binding, new-canonical)` for a kind
whose identity is a pointer, and it is why §11.6's "re-register under the host
namespace" needed rewording rather than implementing.

**Two things §14.7 got right and one it did not.** `src-ns` at emission and the
`type-annot nope/` cell both landed as predicted. The third bullet —
"`binding-usable-spelling`'s `BK-GLOBAL`/`BK-PROTOCOL` restriction is a one-line
widening" — was correct as a *diff* and incomplete as a *plan*: widening it is
what makes the `unknown type: Fox — defined in namespace 'dp' / note: write
'dpx/Fox' here` diagnostic possible, and that diagnostic needed its own tier
order in `unknown-type-message` (out-of-scope qualifier → unreachable definer →
other namespace → did-you-mean) to avoid degrading into W1c's "not defined
anywhere in this compilation unit" for a type that is defined and reachable. The
tier is a cold path, so it also needed a fixture that *executes* it
(`b3-type-typo`) — the first cut called `fmt-3s` with two arguments, which
conventions.md's fixed-arity rule says is invisible forever otherwise.

**What B3′b/B4 inherits.**

* ~~**The `(dyn P)` box's identity is still keyed on a spelling-derived name, and
  a prefix spelling splits it.**~~ *(Closed in B6 — §9.5, which also corrects the
  measurement below.)* Measured, and live in the tree:
  `examples/w9-dyn-ns.nuc` imports one library under two prefixes and emits
  **two** `{data,vtable}` `StructDef`s for one protocol (`%__dyn.dpx_Describe`
  and `%__dyn.dpx2_Describe`), plus two vtables for one conformance.
  **Wrong, and B6 measured it.** That file imports **two different libraries**
  (`nsdescribe` in `(ns dp)`, `nsdescribe2` in `(ns dp2)`) which declare two
  different protocols that share the bare name `Describe`; two box types and two
  vtables are *correct* there. What was actually wrong is that the two were named
  after the consumer's **prefixes** rather than the protocols' namespaces, which
  is the same keying defect seen from one file instead of two — and it is why the
  file could be a witness for the naming and never for the split. The real
  witness has to cross a file boundary, and B6's
  `run_b6_dyn_cross_ns` is it.
  The consequence is not cosmetic: a library that takes `(dyn Describe)` and a
  consumer that constructs `(dyn dpx/Describe)` is a **legal program that fails**
  — not with a diagnostic, but with `nucleusc: failed to parse generated IR:
  '%t25' defined with type '%__dyn.dp_Describe' but expected
  '%__dyn.dpx_Describe'`, no source location. The cause is exactly §9.2's rule
  working as designed: `dyn-type` keys on the environment-free
  `protocol-canon-name-ns`, which cannot map a *prefix* to a namespace. Two fixes
  were designed and both are larger than an arm, which is why neither is here:
  (a) key on `resolve-spelling`'s canonical name — now phase-stable, since
  `prescan-file-imports` gives every prescan the environment — but that breaks
  **admission**, because `dyn-require-protocol` asks the scope question against
  the *stored* name and a canonical `dp/Describe` is not nameable in the
  consumer; or (b) move admission to the annotation site, where the spelling is,
  via a deferred-validation worklist drained after the whole-graph prescan. (b)
  is §9.2's fix (a) and it also closes the tenth defect (`protocol-dyn-annot`,
  all four cells still `ok`). Identity and admission need different data; the
  clean split is to ask admission where the spelling is.
  **B6 did (a) and (b) together, which is what the paragraph above concludes
  without quite saying: (b) alone leaves two box types, (a) alone refuses every
  legal box. Two corrections: `prescan-file-imports` does NOT make (a)
  phase-stable on its own — the canonicaliser has to consult no registry as well
  — and "all four cells" is three: `zx/` is the legal spelling and must stay
  `ok`.**
* ~~**A `(dyn P)` value is accepted where `(dyn Q)` is required**~~ *(Closed in
  B6.)* For genuinely different `P`/`Q`, and caught only by LLVM's parser with no
  source location. Pre-existing (Stage 13 TE-3's box-to-box coercion returns its
  input untouched), namespace-independent, and the reason the split above is not
  *louder*. Worth a `type-eq` check at the erased-slot coercion. **Right about
  the fix and understated about the reach: at an ARGUMENT position LLVM does not
  catch it either, because the SysV ABI decomposes the fat pointer into two i64s
  at the call — the program links and runs against the wrong vtable. And there
  are two coercion sites, not one.**
* **`collides` 0 on `BK-UNION`/`BK-ENUM`/`BK-FNTY`** is unchanged and still B4's.
* **The `import-use`-flattened bare spelling of a namespaced protocol** takes the
  same `dyn-type` path as the prefix spelling and splits identically; it is one
  case of the first bullet, not a separate one. **Half right, and B6 leaves it
  open on purpose — see §9.5's last section. It is not the same case: the prefix
  spelling is resolvable from the environment alone, the flattened bare one needs
  a registry probe, and a registry probe is exactly what cannot be phase-stable
  here.**

### 9.5 What B6 built — identity vs admission for `(dyn P)`

**Status: done 2026-08-09.** §9.4's first two inherit-bullets, plus defects #10
and #11.

**The line fell exactly where §9.4 said it would, and the reason is worth stating
as a rule.** A `(dyn P)` box asks two questions of one spelling and they need
different data:

* **identity** — *which* protocol is this? — must be answerable **identically at
  every phase**, because the answer is a memo key and two keys mint two
  `StructDef`s, and `type-eq` is `StructDef`-pointer identity. It is asked from a
  `defn` signature during `prescan-defn-signatures` and again from the same
  signature at emission.
* **admission** — *may this file name it?* — must be asked **where the spelling
  is**, because it is a question about the writing file's import environment, and
  the canonical answer to the first question is routinely not a spelling that
  file can write.

B2a satisfied the first by keying on a namespace-only canonicaliser and the
second by asking at box construction. That works only while the two questions
have the same subject; the moment identity became canonical, box construction
started asking "may this file name `dp/Describe`?" in a file that only bound
`dpx`, and the answer is *no* for every legal box. So the two moved apart: the
key became canonical and admission moved to the annotation site.

**Identity: `dyn-proto-key`, and the load-bearing property is that it consults no
registry.** §9.4 wrote that keying on `resolve-spelling`'s canonical name is "now
phase-stable, since `prescan-file-imports` gives every prescan the environment".
That is necessary and not sufficient, and the difference is the whole design.
`prescan-file-imports` makes the *environment* available; a canonicaliser that
went on to consult `g-protocols` would still answer differently in the two
phases, because the root file's `prescan-defn-signatures` runs **before**
`prescan-imported-signatures` (§9.2 recorded this) and the traversal is pre-order
inside pass 2 as well, so a file's own signatures are prescanned before its
imports' protocols are registered. A registry probe there returns *not found* at
prescan and *found* at emission — which is worse than the bug being fixed,
because the two keys then disagree **inside one program** and produce the very IR
parse error the fix is for. So:

* `NR-QUALIFIED` → the canonical name. Resolving a prefix needs `g-file-imports`
  and `g-file-ns`, and both are complete for the whole reachable graph before any
  prescan that resolves a name — `prescan-file-imports` for this file's own binds
  (B3′), `prescan-imported-types`' recursion for every reachable file's `(ns …)`
  via `apply-leading-ns` → `emit-ns`. No registry.
* `NR-BARE` → `qualify-name`'s key when this file's own namespace declares the
  protocol, else the bare spelling. This *is* a registry probe, and it is
  phase-stable for a different and narrower reason: it is `-exact`, on the
  current namespace's key only, and a file's own `prescan-protocols` runs before
  its own `prescan-defn-signatures` in every prescan and before emission. It
  reproduces `protocol-canon-name-ns`'s answer for **every** bare spelling, which
  is why every namespace-free program keys byte-identically and 181 of 182 files
  in the tree emit unchanged IR.
* `NR-UNBOUND` → verbatim. In a `g-type-key-ok` synthesis region that string
  already *is* the canonical key; outside one it is a scope error and the
  annotation check reports it.

`protocol-canon-name-ns` was deleted — it existed for this one caller.

**Admission: a worklist, and how its completeness is checked.** `dyn-annot-record`
(`src/nucleusc.nuc`, beside `dyn-require-protocol`) is called from `dyn-type` for
every `(dyn P)` a file writes, and records `{spelling, path, line, ns, imports}`
— a `DynAnnot`. `drain-dyn-annots` restores those three globals per job and calls
`dyn-require-protocol` **on the spelling**, so the question is asked as the file
that asked it and the diagnostic quotes what the author wrote. Two exits skip the
record, and both are enumerable:

* `g-type-key-ok` armed — the spelling was synthesized by the compiler, so there
  is no file to ask. Same permission and same arm sites as B3′'s type reference
  resolvers, which is the point: one flag now marks "compiler-written spelling"
  for two mechanisms rather than each growing its own.
* `g-interactive` **and** `g-toplevel-depth == 0` — a REPL form typed at the
  prompt, answered on the spot so the error lands on the form just typed. The
  depth test is not decoration: a REPL `(import-use …)` runs
  `emit-toplevel-forms` at depth 1, and without it an imported library's
  `(dyn ri/Ip)` — a protocol from the *library's own* import — would be refused,
  because that library's signature prescan precedes its imported-signature
  prescan. Measured before the test was added.

The drain runs at `emit-toplevel-forms` depth 1, **after** `drain-mono-worklist`,
i.e. after everything. That placement is forced by a file kind no prescan walks:
a `.nuc` imported by **string path** (`(import-prefixed "lib/x.nuc" p)`) is read
only at emission, so neither its namespace nor its protocols exist until then.
Draining right after the whole-graph prescan — which is what §9.4 proposed —
would falsely reject every `(dyn p/P)` naming such a library. The cost is that an
annotation error is reported after the unit is emitted rather than before, which
is invisible in output (nothing is written until `flush-module-ir`) and visible
only in *which* of two errors a doubly-broken program reports first.

Completeness is **asserted, not argued**: `main` checks
`g-dyn-annots-drained == (count g-dyn-annots)` after `emit-toplevel-forms` and
fails as an internal error otherwise. §9.4's honest weakness about dynamic-extent
mechanisms — "a missing drain is a false rejection or a silently unclosed hole,
invisible to the tree because nothing in it uses namespaced types across a
boundary" — applies verbatim here, and a cursor-versus-count assertion is the one
form of evidence a worklist can actually offer. The drain itself loops on the
cursor rather than a snapshot, so a job appended during the drain is still
processed exactly once.

**What box construction became.** `dyn-require-protocol` is unchanged and now has
exactly one caller, the annotation check. `emit-box-value` and
`dyn-vtable-method-irname` call the new `dyn-resolve-protocol`, which is
`protocol-resolve-any` (reference, else key) plus the same diagnostic — §9.2's
"downstream of a gate, do not gate again", applied to the site that *was* the
gate. The visible consequence is that `(dyn zn/Zp)` now *resolves* at box
construction and is refused by the drain instead; same message, same line, and
the matrix records no change for `protocol-dyn-box`.

**The adjacent item made it in, and it is louder than §9.4 thought.**
`box-require-same-kind` is a `type-eq` on the two canonical box Types (both come
from one memo, so `type-eq` is box identity exactly). Two findings:

* **There are two erased-slot coercions, not one.** `maybe-box-into-slot` covers
  `let`/`with` init and `return`; the **argument** position has its own pair of
  blocks in `emit-call-with-args`, added by Stage 13 TE-3/TE-6 and never routed
  through the chokepoint. This is `coerce-int-val`'s lesson recurring exactly
  (conventions.md: "one absent conversion is a rejection in eight positions and a
  silent miscompile in the ninth") — and here the argument path was the *only*
  one that mattered, because…
* **…at an argument position LLVM never sees the mismatch.** The SysV ABI
  decomposes a `{data,vtable}` fat pointer into two `i64`s at the call, so
  `(takes-q p)` with `p:(dyn P)` linked and ran, dispatching against a vtable
  built for the wrong protocol. §9.4 called this "caught only by LLVM's parser";
  measured, that is true only for the binding path
  (`tests/fixtures/b6-dyn-box-mismatch-let.nuc`), and
  `b6-dyn-box-mismatch-arg.nuc` is the one that was silent. Both fixtures exist
  for that reason.

**What surprised me.**

1. **`examples/w9-dyn-ns.nuc` was never a witness for the split.** §9.4 reads it
   as "one library imported under two prefixes, two `StructDef`s for one
   protocol". It is two *different* libraries (`nsdescribe`/`nsdescribe2`, in
   namespaces `dp`/`dp2`) declaring two different protocols that share the bare
   name `Describe`; two box types there are correct. What was wrong was the
   *names* — `%__dyn.dpx_Describe` rather than `%__dyn.dp_Describe`, i.e. keyed on
   the consumer's prefix. The generalisable half: **a defect about identity
   across a boundary cannot be witnessed inside one file**, and a single-file
   fixture will show you the naming symptom and hide the failure. The real
   witness (`run_b6_dyn_cross_ns`) needed a second file and had to *run*.
2. **The failing direction was the opposite of the documented one.** §9.4 quotes
   an LLVM parse error for a box crossing *into* a consumer. Measured on a `HEAD`
   compiler, the same program fails *earlier* and in the other direction: passing
   a consumer's value into a library's `(dyn Describe)` **parameter** dies
   `(dyn b6dp/Describe): 'b6dp/Describe' is not a declared protocol`, because
   admission was already being asked against a name the consumer cannot spell.
   That is fix (a)'s predicted failure mode — present in the tree *before*
   anyone applied fix (a), because a library writing `(dyn P)` bare inside its
   own namespace already stored a canonical name.
3. **The `zx/` cell must not move.** The brief and §9.4 both say "all four
   `protocol-dyn-annot` cells must move". Three must; the fourth is the one
   spelling the consumer may legally write, and moving it would be precisely the
   false rejection the deferral exists to prevent. The row now matches
   `protocol-dyn-box` exactly, which is the real acceptance criterion: an
   annotation and a construction of the same protocol must not disagree about
   whether the name is in scope.

**Verification.**

* `make` clean from `make clean`; `make bootstrap` at its fixed point
  (`stage1.ll == stage2.ll`) with **no reconverge** — the compiler's own source
  spells no `(dyn P)`, so every new mechanism is inert for it. Stage 2 compiles
  and runs `hello.nuc`. `make abi-test`, `make layout-test` green.
* `make test` (parallel default) → **467 PASS, 0 FAIL** (463 + 4 new).
* **IR inertness**, against a compiler built from the clean `HEAD` tree: of the
  182 files in `examples/` + `lib/`, **181 byte-identical** (IR, stderr and exit
  code). The 182nd is `examples/w9-dyn-ns.nuc`, and its whole diff is 70 lines of
  one rename: `%__dyn.dpx_Describe` → `%__dyn.dp_Describe`,
  `%__dyn.dpx2_Describe` → `%__dyn.dp2_Describe`, and the three `@__vt.*` symbols
  that embed those names. That is the fix — a box is now named after the protocol
  it erases, not after the prefix that reached it.
* `tests/resolution-matrix.sh --check` → **exactly the three predicted cells
  moved**, `protocol-dyn-annot` `bare`/`nope/`/`zn/` `ok` → `err`, with the
  messages predicted; `zx/` stayed `ok`; nothing else changed status or message.
  Re-recorded.
* **Diagnostic sweep**: all **180** pre-existing fixtures compiled under both
  compilers with byte-identical stderr and exit code. Nothing moved.
  `b2a-dyn-ns-not-in-scope` is the one whose *reason* moved — the same rejection
  at the same line now comes from the annotation drain rather than from box
  construction — so its header was re-pointed inline rather than re-baselined,
  along with the tenth-defect note it used to carry as open.
* Each new test was checked to **fail on a `HEAD`-built compiler**:
  `b6-dyn-cross-ns` (compile error), `b6-dyn-box-mismatch-let` (LLVM parse error
  at link), `b6-dyn-annot-unknown` and `b6-dyn-box-mismatch-arg` (compiled,
  linked and ran — the silent ones).

**What the next unit inherits.**

* **The `import-use`-flattened bare spelling of a namespaced protocol still keys
  bare, and closing it needs a phase-complete protocol registry.** A consumer in
  `user` that `import-use`s `(ns dp)` and writes `(dyn Describe)` keys
  `Describe`, while the library's own `(dyn Describe)` keys `dp/Describe` — so
  the two still split. Unlike the prefix case this is **not** resolvable from the
  environment: which flattened namespace owns a bare name is a registry question,
  and §9.5's whole argument is that a registry probe at `dyn-type` is unsound
  while an imported protocol may not be registered yet. Two real options: register
  every reachable file's protocols in **pass 1** (`prescan-imported-types` already
  reads and `apply-leading-ns`es each file, and `protocol-register-form` is
  idempotent — the risk is that `guard-name-kind` then runs in a different order
  and a `defprotocol`/`defstruct` clash is reported at a different definer, or
  not at all); or accept the split and rely on the net below. It is **not silent
  any more** — `box-require-same-kind` turns the meeting point into a located
  `type mismatch: a (dyn Describe) value cannot be used where (dyn Describe) is
  required`, which is confusing but findable, and B4 or a successor should
  either close the keying or make that message name the two namespaces.
* **A `.nuc` imported by STRING path is walked by no prescan**, so its namespace
  and its protocols do not exist until emission. B6 works around it by draining
  last; the underlying gap is wider than `(dyn P)` — a `defn` signature naming a
  namespaced *type* from such an import has the same problem (B3′'s territory).
  Extending pass 1 and pass 2 to `.nuc` string paths is the root fix and was not
  attempted here.
* **Two files in one namespace, where the second writes `(dyn P)` for a protocol
  the first declares**, key bare if the second is prescanned first. The
  `NR-BARE` exact probe is phase-stable per *file*, not per *namespace*. No file
  in the tree does this; pass-1 protocol registration would close it along with
  the flattened case.
* **`set!` / `.set!` into a box-typed slot** reaches neither erased-slot
  coercion, so it neither boxes nor type-checks. Pre-existing and unchanged;
  found while auditing the call sites of `maybe-box-into-slot`.
* `collides` 0 on `BK-UNION`/`BK-ENUM`/`BK-FNTY`, and `Method.src-ns` filtering,
  are still B4's and are untouched. *(All four done in B4 — §9.6.)*

### 9.6 What B4 built — a qualified spelling for generics, and R4's eager rule

**Status: done 2026-08-09.** Defect #5, the generic half of #1, R2's per-kind
`collides` policy and R4's eager same-kind rule.

**The generic half went exactly as §14.7 predicted, and its two prerequisites
did not exist.** `generic-lookup-ref` (`src/generics.nuc`) is the reference
resolver: a bare spelling is the old `generic-lookup` unchanged, a qualified one
goes through `resolve-spelling` and then `generic-filter-by-ns`, which restricts
the bare generic's method set to the methods whose `Method.src-ns` is the
namespace the qualifier denotes. `BK-GENERIC`'s probe arm is the only consumer,
so `emit-dispatch`, `node-type-call` and `guard-name-kind` inherit it from the
one table — the prediction held. The filtered view is a fresh `Generic` over the
same `Method` pointers, built per reference and deliberately not memoized: a
cache would go stale the moment a later import adds a method (`generic-add-method`
exists because that happens), and the two answers that matter allocate nothing
(all methods match → the generic itself; none → null).

**`Method.src-ns` was not provenance. It was a diagnostic field that happened to
be set on one path.** Filtering on it exposed two writers that disagreed with it,
and neither was visible from reading:

1. **`register-generic-template` records nothing.** A bounded-generic template is
   built with a bare `(new Method)` and never goes through
   `generic-register-method`, so its `src-ns` was null. A qualified reference to
   a template therefore filtered to *zero* methods and did not resolve at all —
   `pg/b4-twice` reported "not defined anywhere in this compilation unit", the
   same text a genuinely absent name gets.
2. **A stamp is registered under the CALL SITE's namespace.** `generic-instantiate-in`
   calls `generic-register-method`, which writes `g-current-ns` — and the line
   immediately below it already says the *mangling* must use `(gg ir-prefix)`,
   "the template's defining namespace, not the call site's". The same argument
   applies to ownership and had not been made: without re-owning the stamp, the
   second `p/tmpl` call in another namespace filters the first stamp out,
   `generic-find-method-exact`'s memo probe in `generic-instantiate-in` misses,
   and the instance is stamped and emitted **twice under one symbol** — a link
   error, not a diagnostic.

   The general rule, which is the finding worth keeping: *when a field starts
   being read as provenance, audit every writer of it, not the canonical one.*
   A field with three writers and one reader tolerates two of them being wrong.

**R2's `collides` policy, measured per row** rather than argued. §14.2 listed
three 0s and asked B4 to revisit them; they are not one question:

* **`BK-UNION` was redundant, and is 1 anyway.** `register-uniondef` also
  registers the union's backing `StructDef` under the same key and `BK-STRUCT` is
  an earlier row, so it always answered first. Measured inert. Set to 1 because
  the row is where a kind's participation is *declared*, and leaving it 0 made
  the rule depend on another registry's implementation detail.
* **`BK-ENUM` was a genuine hole.** An enum registers its *members* in
  `g-globals` and never its own name, so nothing probed `g-enumdefs`:
  `(defenum Colour …)` followed by `(defn Colour …)`, `(defvar Colour …)` or
  `(defmacro Colour …)` all compiled, with `Colour` naming two things at once.
* **`BK-FNTY` stays 0**, on the same ground as its `reregisterable`: a
  `__fnty_N` is minted by `fnty-intern`, has no source spelling, and cannot be
  the subject of a definer.

**R4's eager rule needed ten sites and four different "is this a second
definition?" tells.** §14.7 said the enumeration operation the interface lacks
would have to live at the definer rather than in the table, and named
`emit-defstruct`'s guard as *the* site. That was right about the shape and short
by nine. The message is one function (`die-redefinition`, beside
`guard-name-kind`, taking the row's `noun` from the table); what is per-kind is
the fact, and the facts do not rhyme:

| Definer | The tell | Why not the others |
|---|---|---|
| `defstruct` | `StructDef.emitted` | `prescan-struct-names` registers a name-only entry; existence means nothing |
| `defunion`, `defprotocol`, `defstruct`/`defunion` template, `defmacro` | the defining **(file, line)** | these registrars are legitimately re-entered for one form — a whole-graph prescan and again per file, a `.nuch` replay — so existence means nothing either, and there is no state flag |
| `defvar` | `Sym.defvar-state == DEFVAR-REACHED` | W8 G-0 front-loads every reachable file's `defvar` names into the same frame, so a Sym under the key is the *normal* state; only emission promotes one to REACHED |
| `defconst`, `defenum` member | the defining **(file, line)**, plus "blame the later one" | the prescan registers *exactly* the Sym the emitter goes on to register, so there is no state difference at all |

The last row carries a wrinkle worth stating because the first cut got it
backwards: G-0's prescan registers **every** form's Sym before **any** form is
emitted, and `scope-lookup-key` scans backwards — so while emitting the *first*
`defconst` the probe lands on the *second* one's prescan entry, and the pair was
reported at the first definition's line. A hit below this form in the same file
is therefore skipped; the later form finds the earlier one's emitted Sym when it
reaches its own check, and blames itself.

`Protocol`, `StructTemplate`, `UnionTemplate` and `EnumDef` gained `src-file` /
`src-line`, `UnionDef` gained `src-file`, and `MacroDef`'s two fields existed and
had never been written. That is what lets the diagnostic name **both**
definitions, which is the whole value in the cross-file case R4 was written for.

**The REPL is a sequence of compilation units, and one predicate says so.**
Every check routes through `same-definition-site`, which answers "same
definition" whenever `g-interactive` is set — so each definer falls back to its
own pre-B4 behaviour rather than to a shared no-op, which matters because four of
them used to `return` and four used to fall through. Verified by diffing a REPL
transcript (redefining a struct, a defvar, a macro, a defconst, an enum and a
defn) against the pre-B4 compiler: **byte-identical**.

**R4's casualty count was one; measured, it is three — and §11.1 says why.**
That count came from a scan of `src/*.nuc` + `lib/*.nuc`, and `examples/` was
not in it:

* `examples/list.nuc` and `examples/quasiquote.nuc` each carried their own
  `(defstruct Node … car:ptr cdr:ptr)` over the prelude's `(raw Node)` one —
  the identical defect §11.7 removed from `lib/list.nuc`, twice more.
* `examples/defmacro.nuc` defined `when` and `unless`, which the auto-imported
  prelude already defines *with `&rest body`*. `find-macro` returns the first
  match and the prelude registers first, so **neither definition in the example
  was ever expanded**: the file demonstrated a macro it did not use. Renamed to
  `when1`/`unless1`, output unchanged.

All three are §11.1's class — a silent shadow whose winner is decided by import
order — and all three were fixed rather than worked around, per §11.7.

**Verification.** `make test` 485 PASS / 0 FAIL (467 before B4, so 18 new);
`make bootstrap` re-converges (`stage1.ll == stage2.ll`); `abi-test`,
`layout-test`, `avr-test`, `riscv-test`, `riscv-abi-test` all pass; the matrix
moved exactly one cell. And the whole-tree sweep §9.2's note calls for: a
compiler built from a clean `HEAD` worktree and the B4 compiler emit
`diff`-identical IR for **all 178** compilable files in `examples/` + `lib/`
(the four that do not compile fail identically under both, and are the known
standalone-compilation artifacts `build.md` records).

**What B4 leaves open, stated rather than omitted.**

* **Macros still have no qualified spelling** — the last of defect #1.
  `g-macros` is keyed by the bare source name with no `qualify-name` anywhere, so
  `p/mac` cannot resolve; `binding-usable-spelling` therefore still refuses to
  *suggest* one for `BK-MACRO`, which is now the only row it refuses. B4 makes a
  second macro of one name an error, so the gap is a missing spelling rather
  than a silent shadow.
* **A bare generic reference reaches namespaces the file imported PREFIXED.**
  §8.2 says "one `Generic` per bare name with methods merged from every
  *flattened* namespace"; the registry merges from every namespace, full stop, so
  `(import-prefixed lib p)` plus a bare call reaches `lib`'s overloads. Filtering
  the bare path symmetrically is *not* the same one-line change as the qualified
  path, and the reason is the second finding above: it would run on every head
  symbol, and it would trust `Method.src-ns` on paths B4 only had to correct for
  the two it measured. Wants its own audit of every `Method` writer first.
* **`import-only` still filters nothing** (R5, §11.2). Unrelated to B4 and still
  unassigned.

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

> **Measured in B4, 2026-08-09: three, not one.** The table above scans
> `src/*.nuc` + `lib/*.nuc`, and `examples/` is not in it. `examples/list.nuc`
> and `examples/quasiquote.nuc` each carry the *same* `Node` redefinition
> §11.7 removed from `lib/list.nuc`, and `examples/defmacro.nuc` redefines the
> prelude's `when`/`unless` — where the consequence is sharper than a
> nullability difference, because `find-macro` is first-match and the prelude
> registers first, so neither definition in that example was ever expanded.
> All three fixed rather than worked around; §9.6.

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

> **Corrected by B3′ (2026-08-09), §9.4.** "Re-registers under the host
> namespace" is right for `g-globals`, whose payload is a `Sym` that may be
> duplicated, and wrong for a type, whose payload *is* its identity: a second
> `StructDef` under `facade/Pt` would make `facade/Pt` and `geom/Pt` two types,
> which is R1 inverted. The implemented shape is a **re-export alias table** —
> the facade's name maps to the *same* payload, consulted by each reference
> resolver after its key walk. The paragraph's conclusion survives (the resolver
> must be able to express the operation); only the word "re-register" was
> load-bearing in a way it should not have been.

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
| 7 | `BK-UNION` | `g-uniondefs` | ~~0~~ **1 (B4)** | 1 | 0 |
| 8 | `BK-STRUCT-TEMPLATE` | `g-struct-templates` | **1 (new)** | 1 | 0 |
| 9 | `BK-UNION-TEMPLATE` | `g-union-templates` | 1 | 1 | 0 |
| 10 | `BK-ENUM` | `g-enumdefs` | ~~0~~ **1 (B4)** | 1 | 0 |
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
  *(B4 measured all three and they are not one question: `BK-UNION` was
  redundant and is 1 anyway — the row is where participation is declared, not a
  place to encode another registry's implementation detail; `BK-ENUM` was a
  genuine hole, since an enum registers only its members; `BK-FNTY` stays 0.
  §9.6.)*

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
token, generalise `export`) — **done 2026-08-09; §9.4 records what was built.**
Kept as written, with the three corrections B3′ measured marked inline.

* The rows to re-key are 6–11. Each one's `binding-probe` arm is the *only*
  place its key policy is expressed for the shared concerns, so re-keying is:
  change the arm to `resolve-spelling` + an exact probe (exactly what `BK-GLOBAL`
  and `BK-PROTOCOL` already are), and delete the corresponding
  `strip-ns-qualifier` call in `parse-type-name`.
  **Wrong on both counts.** The arm is *not* the only place the key policy is
  expressed — `parse-type-name` calls each registry's lookup **directly**, which
  is the same fact §14.4 recorded for privacy ("a check inside `binding-probe`
  alone would have left `parse-type-name` unguarded"), reappearing for keying.
  And the rows are not separable: `parse-type-name`'s cascade consults all six in
  one function, so cutting one over alone half-closes defect #4 with no way to
  say which half. All six moved together, with the reference resolvers as the
  per-kind unit and `binding-probe` a consumer of them (§9.4).
* `export` is already routed through `binding-re-register`; generalising it is
  flipping `reregisterable` to 1 on those rows and adding their arm. The
  diagnostic it currently raises is the specification of what has to appear.
  **Half right.** The flag and the arm are the diff, but the arm cannot
  *re-register* — a type is identified by its `StructDef` pointer, so a second
  registration under the host namespace mints a second identity. It is an alias
  table mapping the facade's name to the same payload (§9.4).
* Two things B3′ inherits from §14.4 rather than discovers: `src-ns` must be
  captured at **emission** (pass 1's `prescan-struct-names` runs under the
  importer's namespace), and re-keying will *also* fix `type-annot nope/`, the
  last matrix cell still wrongly `ok`. **Both held.**
* `binding-usable-spelling`'s `BK-GLOBAL`/`BK-PROTOCOL` restriction is a
  one-line widening once types have a qualified spelling that resolves.
  **Correct as a diff, incomplete as a plan** — widening it is what makes the
  "defined in namespace 'dp' / note: write 'dpx/Fox' here" diagnostic possible,
  and that needed its own tier order in `unknown-type-message` plus a fixture
  that *executes* the cold did-you-mean tier (§9.4).

**B4** (R4's eager collision rule, R2's per-kind policy) — **done 2026-08-09;
§9.6 records what was built.** Kept as written, with what B4 measured marked
inline.

* The per-kind policy has a home: the `collides` column. R2's table (§8.2) maps
  onto it directly, and the three rows that are 0 today are enumerated in §14.2
  with the reason. **Held**, and the three turned out to be three different
  answers rather than one — see §14.2's inline note.
* R4's "two definitions of one name reaching one scope" needs an *enumeration*
  operation the interface does not have — `probe` answers one key. That is the
  one place B4 will have to extend the table rather than consume it, and the
  honest note is that `emit-defstruct`'s `(when (and (!= existing null) (!= (existing emitted) 0)) (return))`
  guard (§11.1's `Node` finding) is the site, not the table.
  **Right about the shape and short by nine.** It is ten definer sites, and the
  "is this a second definition?" tell is different at four of them — `emitted`
  is a state flag, most registrars are legitimately re-entered and need a
  (file, line) identity instead, `defvar` needs `defvar-state`, and `defconst` /
  enum members need (file, line) *plus* a rule about which of the pair to blame.
  Nothing was enumerated: the table supplies the noun, each definer the fact.
* R2's "recover the qualified spelling from `Method.src-ns`" is already the
  interface's `src-ns` for `BK-GENERIC` — it reads method 0. Filtering a
  generic's method set by `src-ns` is a change to `BK-GENERIC`'s probe arm and
  nothing else. **Correct as a diff, and it was not the work.** The arm is two
  lines; what it cost was discovering that `Method.src-ns` had three writers and
  only one of them meant "the namespace that owns this method" (§9.6).
* `guard-name-kind`'s question (first binding of a *different* kind) is what B4
  should extend, not replace: an eager same-kind collision is the complementary
  query over the same walk. **Half right — complementary yes, same walk no.**
  The walk skips its own kind precisely because every definer's prescan has
  already registered it, so the same-kind query cannot be posed to the table at
  all; it can only be posed where the definer knows its own entry.

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
