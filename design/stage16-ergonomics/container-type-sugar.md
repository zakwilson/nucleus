# Stage 16 — Container type sugar

**Status:** Evaluated 2026-08-22. **Complete 2026-08-22** — CT-B phase 1
(`deftype`/`deftype-`), CT-D (§1.2's silent mis-parse is now a located error),
CT-B adoption (§3.10), and CT-B phase 2 (parametric aliases, §3.7) all landed.
**799 tests (was 778), `make bootstrap` byte-identical**, every adoption commit
verified IR-identical, example at `examples/type-aliases.nuc`. Corrections from
implementation are marked inline (§3.4a, §3.8, §3.8a, §3.7). **CT-A is dropped**
(§4 step 5); CT-C rejected (§2).

The item as filed: `(ref (HashMap CStr i32))` is ugly, and something like
`ref:HashMap:(CStr i32)` would be more pleasant.

The proposed spelling turns out to buy **zero characters** over a sugar that
already ships, and probing for it surfaced a silent mis-parse that is worth
fixing on its own. Both findings are below, then the four options.

---

## 1. Ground truth (verified 2026-08-22 against `build/nucleusc`)

`ref:(HashMap CStr i32)` — the Stage 14 CP-1 chain fuse
([../stage14/colon-paren-types.md](../stage14/colon-paren-types.md),
`docs/types.md` §Colon-chain fuse) — **already works** in every type position:
`defn` param, `defn` return, `defstruct` field, `let`/`with` binding, and `as`.
It was never applied to collections in the docs or in any source file.

| Spelling | Chars | Status |
|---|---|---|
| `(ref (HashMap CStr i32))` | 24 | canonical list form |
| `ref:(HashMap CStr i32)` | 22 | **works today** |
| `ref:HashMap:(CStr i32)` | 22 | the filed proposal — errors today |
| `ref:HashMap:CStr:i32` | 20 | works, single-token arguments only (§1.2) |
| `m:SymTab` | 6 | CT-B; no such feature today |

### 1.1 Why the filed spelling buys nothing

CP-1 wraps the paren group as a **unary constructor argument**, not as an
argument list: `ref:HashMap:(CStr i32)` folds to `(ref (HashMap (CStr i32)))`,
and the type parser reports

```
'CStr' is a type, not a type constructor -- (CStr ...) is not a type;
a doubled annotation like x:T:T desugars to exactly this
```

Making the group *splice* instead is possible, but the reader would have to
special-case pointer kinds to keep `p:ptr:(fn i32)` → `(p (ptr (fn i32)))`
working, so `ref:` and `HashMap:` would behave differently in front of an
identical-looking paren. That is a rule nobody will remember, in exchange for
the same 22 characters `ref:(…)` already costs. **Drop this spelling.**

### 1.2 The paren-free chain is half-built, and fails silently *(fixed by CT-D)*

`ref:HashMap:CStr:i32` works. It reaches `(ref HashMap CStr i32)`, whose `ref`
branch absorbs its whole multi-element tail as one type
(`parse-type-from-node`, `src/union-registry.nuc:1730`; mirrored by
`wrapper-inner-pattern`, `src/generics.nuc:1219`), and `struct-template-stamp`
then takes each remaining element as one type argument.

But `struct-template-stamp` (`src/union-registry.nuc:1344`) does **no**
arity-driven folding, so as soon as an argument is itself a chain the segment
count overshoots the template's arity:

| Spelling | Result |
|---|---|
| `ref:HashMap:CStr:i32` | OK |
| `ref:Vector:i32`, `ref:Vector:CStr`, `?ref:Vector:i32` | OK |
| `ref:Vector:(ptr i8)` | OK |
| `ref:Vector:ptr:i8` | error — `Vector: wrong number of type arguments` |
| `ref:Vector:ref:Node` | **silent** — no define emitted |
| `ref:HashMap:CStr:ref:Vector:i32` | **silent** — no define emitted |
| `ref:HashMap:ref:Vector:i32:i32` | **silent** — no define emitted |

The silent cases are the defect. `(Vector ref Node)` puts `ref` and `Node` in
template-argument position, where `collect-pattern-tyvars`
(`src/generics.nuc:1281`) collects any symbol that is not resolvable as a
concrete type as a **tyvar**. Bare `ref` is not resolvable (bare `ptr` is —
which is exactly why `ref:Vector:ptr:i8` gets an honest arity error and
`ref:Vector:ref:Node` does not). So the `defn` is classified as an
unmonomorphized template, `emit-defn` skips its define, and nothing is
reported. Reproduced:

```lisp
(import-use vector)
(defn f (x:ref:Vector:ref:Node):i32 (return 21))
(defn main ():i32
  (let (v:ref:(Vector (ref Node)) ((Vector (ref Node))))
    (printf "%d\n" (f v)))
  (return 0))
```

→ `error: no matching method for overloaded 'f' with argument types
(ptr:Vector.pNode)`, and `-S` shows zero `define`s for `f`. The function was
dropped from the module and the diagnostic points at the call site.

**Closed 2026-08-22 (CT-D), in `collect-pattern-tyvars`.** Two guards, because
the three silent rows and the honest one differ only in whether the surplus
symbol happens to be a type:

- A pointer kind in type-argument position is refused by name, since it can only
  be a chain that tried to nest: `Vector: 'ref' is a pointer kind, not a type
  argument -- a colon chain cannot nest, so parenthesize the inner type:
  ref:(Vector (ref X))`. Only `ref` can reach it — `tyname-resolvable` answers
  yes for bare `ptr` and `raw`, which is precisely the asymmetry above.
- Any type *pattern* whose argument count misses the template's arity now gets
  the arity error the concrete path already gave, with the count:
  `Vector: wrong number of type arguments for defstruct template (2 given)`.

The second is the general net; the first exists only to say something better
than "wrong number of arguments" for the case that actually occurs. Adding the
arity check to the pattern path cost nothing — 792 tests and a byte-identical
bootstrap — which is itself the evidence that no legitimate pattern in the tree
was relying on the gap.

### 1.3 Adoption

The CP-1 sugar appears in **no** real source file — the only hits in the tree
are `examples/colon-paren-types.nuc` (5) and one incidental match in
`src/reader.nuc`. Meanwhile the list form is everywhere:

| Type expression | Occurrences |
|---|---|
| `(ref (Vector T))` | 55 |
| `(ref (HashSet T))` | 43 |
| `(ref (HashMap K V))` | 36 |
| `(ref (Vector i32))` | 29 |
| `(ref (Vector ptr))` | 24 |
| `(ref (Vector CStr))` | 18 |
| `(ref (Vector (ref ImportBind)))` | 14 |
| `(ref (HashSet CStr))` | 12 |
| `(ref (HashMap CStr i32))` | 10 |

Two characters is not why nobody adopted it. **The type expression itself is
the cost, not its punctuation** — which is what decides between the options.

---

## 2. Options

### CT-A — finish the flat chain *(dropped; §4 step 5)*

Make `ref:HashMap:CStr:ref:Vector:i32` parse by consuming chain segments
left-to-right against each constructor's declared arity, in
`parse-type-from-node` / `struct-template-stamp`. The reader stays
type-ignorant, as its invariant requires — arity lives in the registries.
Closes §1.2 as a side effect. 20 chars vs 24.

Cost: arity-driven parsing means **adding a type parameter to a template
silently re-parses every existing chain spelling of it**. Tolerable
pre-release, but it is a real coupling between a template's signature and the
meaning of its use sites. It also only helps *multi-token* type expressions —
the thing CT-B removes (§3.9).

### CT-B — type aliases *(recommended; implemented — §3)*

There is no way to name a type in Nucleus — no `deftype`, no alias form
anywhere in `src/`, `docs/`, or `design/`. This is the only option that removes
the type expression from the use sites instead of compressing it, and it adds
no reader rule at all.

### CT-C — implicit `ref` for collections

`m:(HashMap CStr i32)` meaning `(ref (HashMap CStr i32))`. Shortest of all, and
justified by the fact that collections are essentially never used by value. But
the spelling would then lie about representation, against the Stage 10
pointer-kind discipline that made `ptr` non-null and `raw` nullable precisely so
a type says what it is. **Rejected.**

### CT-D — document, and fix the silent case *(implemented; §1.2)*

Publicize `ref:(HashMap CStr i32)`; turn §1.2's silent template into a located
error. Independent of which of A/B lands, and a prerequisite for both: CT-A
because it must not merely move where the silence happens, CT-B because an
alias body is a type expression like any other.

---

## 3. CT-B in detail — `deftype`

### 3.1 Surface syntax

```lisp
(deftype  SymTab (ref (HashMap CStr i32)))   ; public
(deftype- SymTab (ref (HashMap CStr i32)))   ; file-private, per the four
                                             ; private definers' convention
```

The body is an **ordinary type expression** — anything `parse-type-from-node`
accepts. So the existing sugars compose without any new rule:

```lisp
(deftype SymTab ref:(HashMap CStr i32))      ; CP-1 sugar in the body
(deftype NodeVec (raw (Vector (ref Node))))
(deftype Ctors (Vector (ref Constraint)))    ; unwrapped; wrap at use sites
```

### 3.2 Semantics: transparent, not nominal

An alias is **a second spelling for one type**, not a new type. After
`(deftype SymTab (ref (HashMap CStr i32)))`:

- `SymTab` and `(ref (HashMap CStr i32))` are `type-eq`;
- they stamp the same `StructDef` and mangle identically (`HashMap.cstr.i32`);
- they are the *same* overload for dispatch — declaring one method on each is a
  redefinition, not two candidates;
- `type-spelling` (`src/type-mangle.nuc:98`) is **not** taught aliases, so the
  spelling of a type remains its structural spelling everywhere it matters:
  IR names, `.nuch` round-trips, generic substitution.

That last point is what keeps the change cheap and keeps `make bootstrap`
byte-identical until a source file actually adopts an alias.

State the non-goal in the docs: a *nominal* alias (a newtype — distinct
identity, distinct dispatch, no implicit conversion) is a different feature
with a different name, and is out of scope here.

### 3.3 Where resolution happens

Two sites, mirroring how struct templates are already reached:

1. **Bare name** — `parse-type-name` (`src/union-registry.nuc:277`), beside the
   `struct-lookup-ref` probe at :353. Look up the alias, then
   `parse-type-from-node` its stored body node.
2. **Applied parametric alias** (phase 2, §3.7) — `parse-type-from-node`
   (`src/union-registry.nuc:1665`), beside the `struct-template-lookup-ref`
   probe, so `(Table i32)` is recognized as a list head the same way
   `(Vector i32)` is.

Because expansion is **lazy** — the registry stores the body `Node*`, parsed on
each use — declaration order inside a file does not matter, and an alias whose
body names a template registered later in the same prescan still resolves.

Everything else composes for free through those two sites:

| Spelling | Path |
|---|---|
| `m:SymTab` | `desugar-symbol` → `(m SymTab)` → `parse-type-name` |
| `ref:SymTab` | `split-colon-segments` → `(ref SymTab)` → `ref` branch → `parse-type-name` |
| `?SymTab`, `!SymTab` | `parse-type-name` strips the sigil and recurses (:283–:320) |
| `(Vector SymTab)` | `struct-template-stamp` parses each argument through `parse-type-from-node` |

### 3.4 Registry and name resolution

A `TypeAlias` record mirroring `StructTemplate`
(`src/compiler-types.nuc:394`) — the provenance fields are not optional, they
are what Stage 15 B3′/B4/B5 require of every registry:

```lisp
(defstruct TypeAlias
  name:CStr
  (body (raw Node))   ; retained type expression, expanded lazily
  tyvars:ptr          ; phase 2 (§3.7); null / ntv 0 for a plain alias
  ntv:i32
  priv:i32            ; Stage 15 B5 — as StructDef.priv
  src-ns:CStr
  src-file:CStr       ; Stage 15 B4
  src-line:i32)
```

held in `g-type-aliases`, a `(ref (Vector (ref TypeAlias)))` beside
`g-struct-templates` (`src/nucleusc.nuc:183`), keyed by `qualify-name` like
every other B3′ registry.

One new binding-kind row (`src/nucleusc.nuc:10590`), so an alias participates in
the one-symbol-one-kind guard and in `binding-probe`:

```
(add-binding-kind v BK-TYPE-ALIAS  "a type alias"  NK-TYPE  1  1  1)
```

with `BK-TYPE-ALIAS 13` and `BINDING-KIND-COUNT` 13 → 14, plus its
`binding-probe` arm (`src/nucleusc.nuc:10755`). `guard-name-kind` then rejects
`(deftype Vector …)` against the existing template, and `(defstruct SymTab …)`
against an existing alias, with no site-specific code.

### 3.4a Collisions — **added during implementation**

The design assumed `guard-name-kind` would cover collisions "with no
site-specific code". It does not, and cannot: it skips every row reporting the
kind being defined, and struct / template / enum / alias all report `NK-TYPE`,
so a **type-over-type** collision is invisible to it by construction. It still
earns its row — it catches an alias against a *function*, *value*, *macro* or
*protocol* name — but not against another type.

The codebase leaves that gap open generally: `(defenum Pt …)` over a `defstruct
Pt` is accepted today, verified. An alias cannot afford it, because
`parse-type-name` probes aliases **last** — so a colliding alias is not merely
ambiguous, it is dead on arrival and silently so, which is precisely the class
of defect §1.2 exists to complain about.

Hence `type-name-collision` (`src/union-registry.nuc`), scoped to `deftype`
rather than a general fix: probe builtins, structs, both template registries and
enums, and refuse with the offending kind named. It runs **ahead of the
same-site early return**, so it fires on both the prescan call and the emit
call — the prescan pass catches a type defined *above* the alias, the emit pass
one defined *below* it, by which point the whole unit is registered.

One direction is still uncovered: `defenum` *after* an alias, because
`prescan-defenum-names` takes a single form and runs per-form during emission
rather than as a whole-file pass, so the enum is not yet registered when the
alias re-checks. This is the same pre-existing gap as `defenum`-over-`defstruct`
and is left to whoever closes that one generally.

### 3.5 Prescan

Register the name in `prescan-struct-names` (`src/nucleusc.nuc:15124`) — a new
arm alongside the `defstruct`/`defunion` ones — so `defn` signatures naming an
alias resolve in `prescan-defn-signatures`, which runs after it. Registration
records the name and body only; §3.4's `priv`/`src-ns` are written at emission,
per the rule that comment already states.

### 3.6 Cycles

`(deftype A (ref B))` + `(deftype B (ref A))` must not recurse forever. Carry a
small expansion-depth counter through alias expansion and die at the limit with
the alias name in the message. A depth cap rather than a visited-set: expansion
is a plain recursive descent with no natural place to hang set state, and no
legitimate alias chain is deep.

### 3.7 Parametric aliases — phase 2 *(landed 2026-08-22)*

```lisp
(deftype (Table V) (ref (HashMap CStr V)))
(deftype (Vec T)   (ref (Vector T)))
```

Deliberately not in phase 1: it is where the interaction with
`collect-pattern-tyvars` needs care. Shipped on its own gates once phase 1's
were green.

**Node substitution, not spelling substitution.** The sketch said "same tyvar
machinery `StructTemplate` uses". That machinery (`subst-tyvars-node`) replaces
a tyvar with a *spelling string*, which a template can afford because it stamps
only from concrete `Type*` arguments it can call `type-spelling` on. An alias is
applied in pattern position too, where an argument may still be a **free
tyvar with no Type at all** — so `subst-alias-args` substitutes the argument
*node*. One case does fall back to spellings: a parameter written inside a colon
chain in the body (`(deftype (Ref T) ref:T)`) has to be rebuilt segment-wise, so
there its argument must be a single token. That is a located error, not a
surprise at the use site.

**Four resolution sites, not one.** §3.8a's lesson repeated at a smaller scale.
`parse-type-name` handles the plain form because a plain alias is a bare symbol;
an *application* is a list, so it needs a hook wherever a list-shaped type is
consumed: `parse-type-from-node` (the concrete path), `collect-pattern-tyvars`
and `unify-tpat` (the pattern paths), and `type-node-to-c`. The receiver case is
the one the sketch flagged, and the diagnosis was right — an unexpanded
`(Vec T)` matches no template and no pointer wrapper, so `collect-pattern-tyvars`
walks straight past it, `T` is never collected, and the template is misread as
concrete. (The sketch said the *alias name* would be collected as a free tyvar;
the actual failure is the opposite — nothing is collected at all. Same
consequence, opposite mechanism.)

**The cycle guard has to sit at every recursion site.** `MAX-TYPE-ALIAS-DEPTH`
in `parse-type-from-node` does not protect `collect-pattern-tyvars`, which
reaches a `defn` parameter *first*: `(deftype (A T) (A T))` hung the compiler
until the pattern path got its own guard. A depth counter is not a property of
the alias — it is a property of each descent, and the counter is only as good as
its least-guarded caller.

### 3.8 `.nuch` export — **correction, this needed code**

The evaluation claimed "nothing to build", reasoning from `lib/hashmap.nuch:3`
being a literal `(defstruct (Entry K V) …)`. That inference was wrong: both
`.nuch` sides are **explicit form lists**, not a verbatim pass-through. The
export dispatch (`src/nuch.nuc:197`) names each head it carries, and the import
dispatch (`src/nuch.nuc:694`) names each head it re-registers. A form absent
from either list is silently dropped, which is exactly what happened first
time — the header emitted `(declare twice ((n Count)) :Count)` naming a `Count`
it did not carry, so the importer failed on an unresolvable type.

Both need an arm: export prints the alias verbatim (like `defunion`/`deferror`),
import calls `register-type-alias`. `deftype-` correctly needs neither, since
the export list holds only public spellings.

The general lesson, and the reason the wrong guess was cheap to make: **"the
format carries X verbatim" is a claim about a dispatch table, not about the
format.** Reading one output file cannot distinguish the two.

### 3.8a Two more explicit dispatches, found the same way

Neither was in the evaluation, and both were real defects rather than missing
polish:

- **`--emit-cheader`.** `type-node-to-c` (`src/cheader.nuc:1976`) resolves a
  `NODE-SYM` by *spelling*, so an alias leaked into the header as
  `struct Count twice(struct Count n);` — naming a struct the header never
  defines, i.e. a header that does not compile. It now expands the alias body,
  and the emitted header is byte-identical to the spelled-out program's.
- **The REPL.** `src/repl.nuc` has its own top-level form chain; without an arm,
  `deftype` was `unknown: deftype` and every later use of the name failed too.
  An alias emits no IR and defines no layout, so unlike `defstruct` its arm
  opens no module and pushes no preamble — registering is the whole job.

The pattern worth carrying forward: a new top-level form has **six** dispatch
sites in this compiler, not one — the prescan, the emit pass, the `.nuch`
export, the `.nuch` import, the C header, and the REPL — plus the special-form
set and `text-token-is-definer`. Only the first two are obvious from the
feature's own description.

### 3.9 Composition with the colon sugar — and why that is the point

The two are complementary, not competing, and the combination is worth more
than either half. Verified 2026-08-22: a **single-token** type name already
works in every declaration position through the plain colon sugar — `defvar`
name, `defstruct` field, `defn` param, `defn` return, `let`, `with`, and in the
chain tail (`x:ref:NameSet`). No fuse, no paren, nothing new to implement.

So on `src/nucleusc.nuc:210`:

| Binding | Chars |
|---|---|
| `(g-special-form-set (ref (HashSet CStr)))` — today | 41 |
| `g-special-form-set:(ref (HashSet CStr))` — sugar alone | 39 |
| `(g-special-form-set NameSet)` — alias alone | 28 |
| `g-special-form-set:NameSet` — **both** | 26 |

The sugar alone saves 5%. The alias alone saves 32%. Together, 37%.

This also explains §1.3. **The colon sugar is at its best exactly when the type
is one token** — there it replaces a whole list wrapper — and at its worst on a
paren type, where it saves two characters and costs a reader rule you have to
remember. Nobody adopted it because the tree has almost no single-token
collection types to use it on. Aliases create them.

And it further weakens CT-A: arity-driven chains only help *multi-token* type
expressions, which is precisely what an alias removes.

Two unrelated limits found while verifying, worth knowing before writing the
examples: `defconst` refuses a type annotation outright (`defconst: takes no
type annotation`), and `gv:ptr:Pt` on a `defvar` hits the Stage 10 non-null
rule, not a spelling problem.

### 3.10 What it looks like on real code

```lisp
; src/nucleusc.nuc:210-211, :17306
(deftype NameSet (ref (HashSet CStr)))
(defvar g-special-form-set:NameSet (build-special-form-set))
(defvar g-primitive-type-set:NameSet (build-primitive-type-set))
(defn build-special-form-set ():NameSet …)

; src/compiler-types.nuc — beside the struct each names
(deftype ConstraintVec (Vector (ref Constraint)))
  constraints:raw:ConstraintVec        ; 6 sites
  constraints:ref:ConstraintVec        ; 4 sites

(deftype ImportVec (Vector (ref ImportBind)))
  g-file-imports:raw:ImportVec         ; 8 sites
  tbl:ref:ImportVec                    ; 7 sites
```

Note the second and third: because an alias is transparent, the pointer kind
can either live *inside* the alias (best at the use sites) or be applied
outside it (the use sites keep a wrapper, but one alias covers both kinds).
Prefer the former for types whose kind is stable, the latter where the same
element type is genuinely held both ways.

**As landed, that rule decided all three.** `NameSet` is only ever a `ref`, so
the kind went inside. `ConstraintVec` and `ImportVec` are each held both ways —
and the difference is *nullability*, which the Stage 10 pointer-kind discipline
exists to keep visible at the declaration — so the kind stayed outside and the
sketch's `RawConstraintVec`/`ConstraintVec` pair collapsed to one alias apiece.
All three were verified byte-identical against a pre-adoption `build/nucleusc.ll`.

Two counts from §1.3 were deliberately **not** adopted. `(ref (Vector ptr))`
(24 sites) is the target of Stage 14's type-safety work, which retypes those
vectors *individually*; a single alias name over all 24 would have to be unwound
site by site to do it, so the alias would actively obstruct the migration.
`(Vector CStr)` (26 sites across both kinds) is one shape but several roles, and
no name covers them that is more informative than the type already is. The rest
of §1.3's table is `(ref (Vector T))`-shaped — generic, and now reachable only
through the parametric form (§3.7).

### 3.11 Gates — as landed

`run_s16_type_aliases` in `tests/run-tests.sh`, nine units: every declaration
position; **transparency asserted as IR equality** against the spelled-out
program (the load-bearing claim); the §3.3 composition matrix; collisions in
both orders; malformed forms and the cycle guard; `.nuch` round-trip;
`deftype-` privacy through a namespaced library and a prefixed consumer (the
`run_b5_private_definers` convention); C-header expansion asserted against the
spelled-out program; and the REPL.

Two fixture bugs worth recording, both of which first read as product bugs:
a shared header defining `(defenum E A B)` made `(deftype A …)` a genuine
collision with an enum *member*, and a public `defn` with a private-alias
signature put the private name in the header through its own `declare` — a
pre-existing export leak that has nothing to do with aliases.

`run_s16_chain_nesting` (CT-D), four units: the three silent rows of §1.2, each
located and naming its template; the arity net behind them; the working
spellings asserted as a `define` per function, because a *missing* define is the
bug; and the `ref:(…)` fuse asserted IR-identical to the list form.

`run_s16_parametric_aliases` (§3.7), seven units: every declaration position
including a colon-spelled body; the generic-receiver case instantiated at two
element types; transparency as IR equality (with a generic whose stamped
instance must mangle from the expansion, not the alias name); arity in both
directions, a bare application, the colon-body limit, and both a self- and a
mutual cycle *through the pattern path*; `.nuch` round-trip through a real
object-file link; C-header expansion; and the REPL.

**799 tests (was 778), `make bootstrap` byte-identical**, plus `abi-test`,
`layout-test`, `avr-test` and `check-headers`. `examples/type-aliases.nuc`
covers both forms.

---

## 4. Staging

1. ~~**CT-B phase 1**~~ — **done 2026-08-22.** Non-parametric `deftype` /
   `deftype-` (§3.1–§3.6, §3.8, §3.8a), landed ahead of CT-D because it is the
   recommendation and CT-D's fix is independent of it.
2. ~~**CT-D**~~ — **done 2026-08-22.** §1.2's three silent rows are located
   errors: a pointer kind in type-argument position names itself, and any
   over-long argument list in a type *pattern* now gets the arity error the
   concrete path already gave. `docs/types.md` gained the container-chain
   spellings and the no-nesting limit.
3. ~~**CT-B adoption**~~ — **done 2026-08-22.** The §3.10 sites, each verified
   byte-identical against a pre-adoption `build/nucleusc.ll`. Required a
   `make update-bootstrap` first: `boot/nucleusc.ll` is the compiler that builds
   `src/`, so `src/` cannot use a form the committed boot IR does not know —
   the same two-step the repo's own history shows (`Boot for …` then `Support …`).
4. ~~**CT-B phase 2**~~ — **done 2026-08-22.** Parametric aliases (§3.7). The
   "if demand" condition was met by §1.3's own table: everything left after
   adoption is `(ref (Vector T))`-shaped, which no plain alias can carry.
5. ~~**CT-A**~~ — **dropped 2026-08-22**, as expected. Arity-driven chains only
   compress *multi-token* type expressions, and both an alias and a parenthesised
   argument now remove those; what CT-A would buy is a coupling between a
   template's arity and the meaning of its existing use sites. §1.2, the one
   defect that motivated it, is closed by CT-D instead.

## 5. Docs

- `docs/types.md` §Type aliases — `deftype` (transparency, privacy, the
  composition matrix, collisions, the newtype non-goal) and its §Parametric
  aliases; §Type Syntax gained "Container types in a chain, and where the chain
  stops" (CT-D).
- `docs/toplevel.md` — the `deftype` row (including type parameters) and
  `deftype-` in the private-definer roster (four of **nine** definers get file
  scope, not four of eight).
- `context/conventions.md` — the six-dispatch-site rule, the
  `guard-name-kind` type-over-type blind spot, and the two traps phase 2 hit.
- `design/progress.md`, `design/stage16-ergonomics/overview.md`.
