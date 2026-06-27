# Stage 9 — Polymorphism

#### Designer

Stage 9 will add a polymorphism mechanism. Hard requirement: **no runtime
overhead when types are known at compile time.** Something to explore: being
able to **extend/implement any function for new types** — which probably
requires **decoupling function names from implementations at compile time.**
It might be messy. It might be worth it.

#### Robot — survey + options

## 1. State of the language relevant to dispatch

I surveyed `src/nucleusc.nuc` for how a call gets from a name to code today.
The mechanism is a strict **one name → one implementation** pipeline:

- **A function name is an IR symbol.** `emit-defn` registers each `defn` in the
  global scope with IR name `@<name>` verbatim (`emit-defn`, ~src:3944-3945:
  `(scope-define g-globals fname ft (fmt-s "@%s" fname) 0)`). The Nucleus name
  *is* the LLVM symbol.
- **Lookup is single-valued.** `scope-lookup` (src:1464) walks scopes
  backward and returns the *first* (i.e. most-recently-defined) `Sym` whose
  name matches by `strcmp`. A second `defn` of the same name shadows the
  first; there is no notion of a set.
- **The dispatch point is one place.** `emit-list` (src:3514) resolves a list
  head in this order: macro table (by name) → special forms (by symbol
  identity) → binops → `scope-lookup` → struct-constructor → error. The whole
  function-call path is the last two lines (~src:3574-3581): look the head up,
  call `emit-call`. **This is the single insertion point for any dispatch
  scheme.**
- **Argument types are known before the call is emitted.** `emit-call`
  (src:2389) emits every argument into a `Val[]` array first — each `Val`
  carries its `Type*` (src:115) — then coerces and emits the call. So a
  resolver can run *after* args are typed and *before* the call instruction is
  chosen. Static dispatch on argument types fits the existing control flow
  with no reordering.
- **`type-eq` already gives a usable dispatch key.** src:1144: primitives are
  singletons compared by kind; structs compare by `StructDef*` identity
  (including memoized anonymous structs); pointers are kind-only. Good enough
  to key a method table.
- **All top-level signatures are known before any body is emitted.**
  `prescan-defn-signatures` (src:4907) forward-declares every `defn` signature,
  recursing imports in dispatch order, before bodies compile. So every method
  of a generic is visible at every call site regardless of source order.
- **There is already a registry precedent.** `defcast` keeps a parallel global
  table of `(from, to, ir-name)` keyed by `type-eq` (`register-cast-rule`
  src:1170, `lookup-cast-rule` src:1159) and exports rules in `.nuch`. A
  method table is the same shape.

Two facts constrain the design space:

- **Typing and emission are fused.** The only way to learn an expression's type
  today is to `emit-node` it (which writes IR as a side effect). There is no
  "what type would this be?" query. For argument dispatch we dodge this (emit
  args, read their types, then pick) — but several richer features below want a
  real non-emitting type pass, which does not exist yet.
- **Macros see AST, not types.** A macro parameter's `(. x kind)` is the *node*
  kind (`NODE-INT`, `NODE-SYM`…), never the resolved `Type` of the value (see
  the `tprint` example, `docs/builtins.md` §"Macros and pass-through
  arguments"). Macros therefore cannot dispatch on inferred types today — only
  on syntactic shape.
- **No return-type inference.** The compiler types bottom-up with no expected
  type pushed down. Dispatch must be decidable from **argument** types;
  return-type-only polymorphism (Haskell `read :: String -> a`) is out of reach
  without adding bidirectional checking.

## 2. The core reframe: what "decouple name from implementation" actually means

Concretely, four things change, regardless of which surface we pick:

1. **A name owns a method set**, not a single `Sym`. New registry
   `g-generics` (name → vector of method `Sym`s), mirroring `g-cast-rules` /
   the struct registry.
2. **Each implementation gets a mangled IR symbol.** Proposed scheme:
   `@<name>.<tok0>.<tok1>…` where the per-arg token is the type's IR/struct
   name — `area` for `Circle` → `@area.Circle`; `add` for `(i32,i32)` →
   `@add.i32.i32`; typed pointers → `p_<elem>`. LLVM identifiers allow `.`/`$`.
   Readable, stable, collision-free given struct names are unique and anon
   structs already carry a content hash.
3. **The call site resolves and emits a direct call.** At `emit-list`'s
   function branch: if the head names a generic, emit args, build the argument
   type tuple, select the unique best method, emit a direct `call` to its
   mangled symbol. A statically-resolved call is byte-identical to a normal
   call — **zero overhead, requirement met.**
4. **`.nuch` carries the whole set** so importers can resolve across modules.

The pieces above are shared by Options 1 and 2; they differ only in the
*surface* (how you spell "add a method") and the *dispatch arity*.

---

## 3. Options

### Option 1 — Open overload sets / static multimethods ("extend any function")

The most direct reading of the kickoff. Any `defn` whose name already exists
but whose parameter types differ *adds a method* rather than shadowing:

```lisp
(defn area:f64 (c:Circle) (* PI (* (. c r) (. c r))))
(defn area:f64 (r:Rect)   (* (. r w) (. r h)))
(area some-circle)   ; → direct call @area.Circle
(area some-rect)     ; → direct call @area.Rect
```

To extend a *foreign* function for your type, you just write another `defn` of
that name with your type — the name is now a dispatch key, not a symbol.
Dispatch is **multiple** (on the whole argument tuple) because the compiler
already has every arg's type and overload resolution is inherently n-ary.

- **Maps to:** `g-generics` registry; resolver at `emit-list`; mangled IR
  names; prescan registers methods (extend `prescan-defn-signatures` to append
  instead of shadow); `.nuch` exports each method as a `declare` plus a
  `generic`/`method` marker.
- **Resolution rules (the crux).** Rank candidates in tiers and require a
  unique minimum: (0) every arg `type-eq` the param (exact); (1) every arg is
  exact or a built-in safe widen (`sext`/`zext`/`fpext`); (2) a `defcast`
  applies. Tie or empty ⇒ compile error naming the candidates. Start coarse
  (no C++/Julia "most specific" partial order); tighten later if needed.
- **Pros:** literally "extend any function for new types"; no new top-level
  form (overloading `defn` is the whole feature); multiple dispatch for free;
  very CLOS/Julia-flavoured; zero runtime cost.
- **Cons:** overload-resolution predictability is the perennial footgun
  (interaction with implicit coercion especially); `(addr-of area)` is
  ambiguous → needs typed disambiguation; no *name* for a capability, so you
  can't write code generic over "any T you can `area`"; complicates REPL
  redefinition (thunk indirection keys on `@name`, src
  `design/stage6-redefinition.md`).

### Option 2 — Protocols / traits (opt-in named interfaces, single dispatch)

Name the capability; implement it per type. Clojure-protocol / Rust-trait /
Swift-protocol shape:

```lisp
(defprotocol Show
  (show:ptr (self:Self)))

(extend Circle Show
  (defn show:ptr (self:Circle) (fmt-s "Circle(%g)" (. self r))))
```

Dispatch is **single** (on the `Self` argument), resolved statically when the
concrete type is known. Same registry/mangling/resolver core as Option 1, but
the surface is `defprotocol` + `extend`, and the method set is *closed to the
protocol's signatures* (better errors, named capability).

Two things this unlocks that Option 1 does not:

- **Bounded parametric polymorphism** (leads into Option 3): a function generic
  over "any `T` implementing `Show`", monomorphized per instantiation.
- **An optional dynamic escape hatch** for type-erased values: a boxed form
  `(dyn Show)` = a fat pointer `{ptr vtable, ptr data}`. Static calls never
  touch the vtable (zero overhead); you only pay when you *explicitly* box, e.g.
  to put mixed types in one array. The vtable is a global constant per impl.
  This is how you get heterogeneous collections without compromising the static
  path — and it stays entirely opt-in.

- **Pros:** clean, named abstraction; excellent diagnostics ("Circle does not
  implement Show"); the controlled dynamic form covers the cases static
  dispatch can't; familiar to Rust/Clojure/Swift users; the static path is the
  same zero-overhead direct call as Option 1.
- **Cons:** new top-level forms (`defprotocol`, `extend`, `Self`, eventually a
  `where`-clause); single dispatch only (multi-dispatch needs more); it extends
  *protocol methods*, not literally any pre-existing function (you wrap a
  function as a protocol method to make it extensible) — slightly less than the
  kickoff's "any function".

### Option 3 — Parametric generics via monomorphization (templates)

Orthogonal axis: code reuse *over* types, not choosing *among* implementations.

```lisp
(defn swap:void (a:(ptr T) b:(ptr T))
  (let (t:T @a) (ptr-set! a @b) (ptr-set! b t)))
(defstruct (Pair A B) first:A second:B)
```

`T` is bound at the call site by unifying the parameter type `(ptr T)` against
the argument's `(ptr Circle)`; the compiler stamps out `swap.Circle`,
`swap.i32`, … on demand and caches instantiations. Zero overhead, full
specialization (C++-template quality). Composes with 1 and 2 (overload-bounded
or protocol-bounded generics).

- **Maps to:** the biggest type-system change — type variables in `Type`,
  unification at call sites, an instantiation cache, and parameterized
  `StructDef` layout. Could be **prototyped as a `defgeneric` macro** that
  captures the body and re-expands per concrete type through the existing
  macro/JIT path (a very Nucleus "do it as a macro first" move) — but a macro
  cannot *infer* `T` from argument types, so the user would annotate; it's a
  stepping stone, not the destination.
- **Pros:** real reuse; zero overhead; composes with everything; specialization
  as good as C++.
- **Cons:** most type-system work of any option; classic template pain
  (instantiation blow-up, error quality); generic struct layout interacts with
  the prescan ordering; the macro prototype can't infer type args.

### Option 4 — Type-directed macros (smallest core; "do it in the language")

Lean on the stated philosophy ("macros are the killer feature; few special
forms; many macros"): instead of baking dispatch into the compiler, expose the
*one* missing capability — the resolved type of an expression at
macro-expansion time — and let `defmulti`/`defprotocol` be **library macros**.
Today a macro sees `(. x kind)` = node kind; add a compile-time `(type-of
expr)` → a type token plus predicates (`type=`, `struct-name`), and a macro can
branch on static type and splice the right call itself.

- **Maps to:** requires the **non-emitting type pass** that doesn't exist yet
  (typing is fused with emission), plus a bridge so the JIT-resident macro can
  call back into the host to type a sub-form and receive a type handle. One
  general mechanism, but a real one.
- **Pros:** smallest addition to the *core*; maximally flexible; canonical fit
  for the design principles; the same `type-of` primitive serves future
  reflection.
- **Cons:** the type/emit split is arguably as much work as Option 1's
  resolver; pushes dispatch *semantics* into userland (every library invents
  its own discipline; no canonical overload resolution or error story); the
  macro/JIT type-token boundary is fiddly.

---

## 4. Shared foundation

Options 1 and 2 are the same engine with different faceplates. Build the engine
once:

- `g-generics`: name → method-set registry (mirrors the defcast table).
- IR-name mangling + a rule for when a name stays unmangled (see §5).
- A resolver keyed on the argument `Type` tuple via `type-eq`, with the tiered
  ranking from Option 1.
- Prescan + `.nuch` export of the whole set.

A genuinely useful, somewhat independent prerequisite worth funding regardless
of surface choice: **a non-emitting `type-of-node` pass** (split typing from
emission). Options 1/2 can avoid it (emit-args-then-pick), but it is the
enabling primitive for `addr-of` of an overload, generic `set!`-places, Option
3's unification, and all of Option 4. Doing it early de-risks the later stages.

## 5. Is it worth it? Where's the mess?

The kickoff's "messy but maybe worth it" is right; the mess is specific and
bounded:

- **C ABI symbol stability.** Once `area` is a dispatch key, `@area` is no
  longer a single C-callable symbol. Rule: a name with exactly one method (and
  not declared generic) keeps the unmangled `@name` and stays C-callable;
  overloaded sets get mangled symbols and `--emit-cheader` either skips them or
  emits the mangled names with a documented scheme. C consumers can't see an
  overload set as one symbol — that's inherent, not incidental.
- **`addr-of` / function pointers.** `(addr-of area)` is ambiguous across an
  overload set. Needs a typed disambiguator, e.g. `(addr-of area:(fn f64
  (Circle)))` selecting one method. Cheap to add, must be specified.
- **Resolution predictability.** The interaction of overloading with the
  existing implicit-coercion machinery (`safe-coerce-val`, `defcast`) is where
  users get surprised. Keeping the coarse tiered ranking (exact ≫ widen ≫
  defcast, unique-or-error) is the antidote; resist "most specific" cleverness
  until there's demand.
- **REPL redefinition.** The thunk-indirection scheme keys on `@name`
  (`design/stage6-redefinition.md`); per-method symbols need per-method thunks.
  Deferrable — redefining a method in the REPL can be a later refinement.

**Verdict:** worth it. The static-dispatch core is a contained change at a
single dispatch site, reuses the args-typed-before-call structure and the
defcast-style registry, and delivers the zero-overhead requirement directly.
The messes are at the edges (C export, `addr-of`, REPL) and are individually
small and deferrable.

## 6. Suggested staging

1. **Foundation:** `g-generics` registry + mangling + resolver at `emit-list` +
   prescan + `.nuch`. (Optionally: the non-emitting `type-of-node` pass first.)
2. **Surface — pick one to ship first** (see decisions below): overloaded
   `defn` (Option 1) *or* `defprotocol`/`extend` (Option 2). They share step 1;
   shipping one does not preclude the other.
3. **Dynamic escape hatch** (`(dyn Protocol)` fat pointer) — only if/when
   type-erased/heterogeneous use shows up. Keeps the static path untouched.
4. **Parametric generics** (Option 3) — when reuse-over-types is the bottleneck;
   biggest type-system lift; compose as bounds on 1/2.

---

## 7. Decisions for the designer

1. **Opt-in or universal?** Protocols (name the capability; Option 2) vs. any
   `defn` is overloadable (Option 1). This is the main fork; both share §4.
2. **Single or multiple dispatch?** Single (Self) is simpler and matches
   protocols; multiple falls out of overloading and is more Lispy/CLOS.
3. **Static only, or a dynamic boxed form too?** The `(dyn Protocol)` fat
   pointer is the only piece with any runtime cost, and it's strictly opt-in.
   In scope for Stage 9 or deferred?
4. **Parametric generics now or later?** Type variables (Option 3) are the big
   lift; fine to defer behind the ad-hoc core.
5. **Coercion in resolution.** Confirm the coarse tiered ranking (exact ≫
   built-in widen ≫ `defcast`, unique-or-error), or do you want stricter
   exact-match-only selection to start?
6. **C export.** Solitary names stay unmangled/C-callable; overload sets get
   mangled symbols. Acceptable? Any requirement for C to call a specific
   overload by a stable name?
7. **Fund the non-emitting `type-of-node` pass up front** (enables Options 3/4,
   `addr-of`-of-overload, generic places), or dodge it for now with
   emit-args-then-pick?

END TRANSMISSION.

---

## 8. Hybrid: Option 1 substrate + protocols as a thin abstraction layer

#### Designer — direction

Adopt **Option 1 as the implementation substrate**, essentially as written: any
`defn` whose name exists but whose parameter types differ *adds a method*;
multiple dispatch; mangled symbols; resolver at `emit-list`; prescan + `.nuch`.
Add **protocols** as a layer on top, for the one thing Option 1 lacks — a
*named* capability you can be generic over, letting function parameters (and
maybe return types) be abstract. `extend` is mostly a **type checker**: because
the concrete implementations are already supplied by Option 1 overloads,
`extend Type Protocol` *verifies the required methods exist* rather than
introducing them.

#### Robot — developing the hybrid

This is coherent, and it lands on a good point in the design space: roughly
Rust traits, but with one property Rust lacks that falls straight out of
"decouple name from implementation."

### 8.1 The payoff: one implementation, many protocols

Because impls are **free overloaded `defn`s** rather than bodies nested inside an
`impl`/`extend` block, a single concrete function can satisfy *several*
protocols at once with no re-declaration. If `show:ptr (Circle)` exists, then
`Circle` conforms to `Show`, to `Display`, to any protocol whose required
signature it happens to match — you just `extend` it to each. The implementation
is not owned by a protocol; the protocol is a *predicate over the method set*.
This is strictly more expressive than Rust/Swift, where a method belongs to one
trait impl, and it is the natural dividend of decoupling the name from the
implementation. Worth treating as a feature, not an accident: it means protocols
can be added *after the fact* over existing concrete code (yours or a library's)
without touching it.

### 8.2 Three roles, cleanly separated

| Role | Form | Produces |
|---|---|---|
| **Implementation** | overloaded `defn` (Option 1) | mangled concrete code `@show.Circle` |
| **Capability** | `defprotocol` | a name + required signatures (compile-time only) |
| **Conformance** | `extend Type Protocol` | a *checked, recorded* fact; **no code** |
| **Abstraction** | protocol-bound parameter / return | a monomorphized concrete instance per use |

`extend` defining no code is exactly the designer's "mostly type checking." It
runs as a **post-prescan pass** (all method signatures are already
forward-declared by `prescan-defn-signatures` before any body emits, src:4907),
looks up each of the protocol's required signatures with `Self → Type`
substituted, and confirms `g-generics` contains a matching method. Present ⇒
record `(Type, Protocol)` in a `g-conformances` registry and export it in
`.nuch`. Missing ⇒ compile error naming exactly which methods are absent — the
diagnostic Option 1 alone can't give you.

(Optional sugar, not required: `extend` *may* accept inline `defn`s that simply
desugar to top-level overloaded `defn`s plus the conformance assertion — a
grouping convenience. Semantically nothing new; purely ergonomic.)

### 8.3 The hidden cost: "abstract parameters" ≡ a bounded monomorphizer

The one thing to be explicit about: making a parameter *abstract* is not free
faceplate work like `extend` is. A function with an abstract parameter must be
**monomorphized** — the body re-emitted per concrete argument type, cached. That
is a constrained slice of Option 3, not Option 1:

```lisp
(defn describe:ptr (x:Show)
  (str-cat "shape: " (show x)))   ; (show x) is an Option-1 call

(describe some-circle)            ; stamps describe.Circle; (show x) → show.Circle
```

The good news is this slice is **far cheaper than full Option 3**, because the
type variable is introduced by a protocol-bound parameter and fixed *directly*
by that parameter's argument type — there is no unification of a variable buried
in `(ptr T)` or `(Pair T U)`. So:

- **Restrict abstract protocol types to bare parameter/return position** for the
  first cut (`x:Show`, `:Show`), **not** nested (`(ptr Show)`). Nested positions
  need a real unifier and are deferred to Option 3.
- Reuse the macro/JIT machinery that already retains and re-expands bodies: a
  generic `defn` retains its AST and re-emits it with the type variable
  substituted, caching `name.<tuple>`.

### 8.4 Refinement: prefer *one named type variable + bound* over bare `x:Show`

Bare protocol-typed parameters have two gaps that hit the *most common*
protocols (Eq, Ord, arithmetic, Clone), all of which are same-type binary ops
returning Self:

1. **Same-type constraint.** `(defn max (a:Ord b:Ord) …)` with independent
   occurrences can't say "a and b are the *same* concrete type."
2. **Abstract returns that mirror a parameter (case B1 below).** "returns the
   same concrete type as `x`" is inexpressible if each occurrence is its own
   anonymous variable.

Both are solved by giving the variable a name and binding it once:

```lisp
(defn max:T (a:T b:T) :where (Ord T)
  (if (gt? a b) a b))            ; T fixed by args; return is T; gt? is Option-1
```

Binding needs **no unification engine** while we stay in bare positions: gather
the concrete type at every bare occurrence of `T` among the arguments, require
they are all equal, substitute, stamp, cache. `x:Show` then becomes the
degenerate case — sugar for a fresh single-use variable `x:T :where (Show T)`.
This is barely more than bare params yet covers same-type binary protocols and
gives B1 returns for free. **Recommendation: build the named-tyvar form; expose
bare `x:Show` as sugar over it.**

### 8.5 Abstract return types ("maybe return types") — the honest answer

Two cases, only one of which is cheap:

- **B1 — return bound by an argument** (`max:T … :where (Ord T)`): the concrete
  return type is known per instantiation (`max.i32` returns `i32`). **Zero
  overhead, no inference, comes for free with §8.4.** This is the useful case;
  include it.
- **B2 — return abstract but bound by *no* argument** (`(defn parse:Show (s:ptr))`,
  Haskell `read`): genuinely undecidable by argument dispatch (the doc's "no
  return-type inference" wall). It requires either an explicit type argument at
  the call site or the **`(dyn Show)` fat pointer** — the only piece with runtime
  cost. **Defer B2** behind `dyn`; until then, reject "returns an unbound
  protocol" with a clear error.

So "maybe return types" resolves to: **yes (B1) via the named type variable;
B2 only when/if `dyn` lands.**

### 8.6 Resolution: concrete beats protocol-bound

Adding generic methods to a name's set extends the tiered ranking with a tier
*below* concrete. A protocol-bound parameter is a wildcard that matches any
conforming argument; an exact concrete method must win over it:

```
(defn render:void (s:Show)   …)   ; generic
(defn render:void (c:Circle) …)   ; concrete
(render a-circle)  ; → render.Circle (concrete), not the generic
```

Tiers, per argument position: **(0) exact `type-eq` ≫ (1) protocol-bound match
(arg conforms) ≫ (2) safe widen ≫ (3) `defcast`.** Rank a candidate by its
multiset of tiers; fewer/less-specific beats nothing, more-concrete beats
more-generic; unresolved tie ⇒ error listing candidates. This is a *natural
two-tier* (concrete vs. bound), not the open-ended "most specific" partial order
§5 warned against — keep it there until there's demand.

Note the clean split this yields: **dispatch among concrete impls is multiple**
(Option 1, on the whole tuple); **abstraction is single-variable** (a protocol
has one `Self`; a generic `defn` binds named variables). Multi-parameter type
classes stay out of scope; concrete multi-dispatch already covers the n-ary
cases people reach for.

### 8.7 C-ABI neutrality (relevant to the current c-parity work)

Protocols, `extend`, and abstract parameters are **entirely compile-time and
vanish after monomorphization**, leaving ordinary mangled concrete functions —
the same artifacts Option 1 already produces. `defprotocol`/`extend` emit *no*
code at all. The only construct that would add a runtime artifact is `(dyn
Protocol)` (a per-impl vtable global), which is opt-in and deferred. So the
hybrid does **not** worsen the C story beyond Option 1's existing rule (solitary
name → unmangled/C-callable; overload set → mangled). C consumers call concrete
monomorphized instances by mangled name; the abstraction itself is invisible to
C, which is inherent (C has no generics), not a regression.

### 8.8 Registries and hook points

- `g-generics` — name → method-set (Option 1; mirrors `g-cast-rules` src:1170).
- `g-protocols` — protocol name → required signatures (with `Self`).
- `g-conformances` — `(Type, Protocol)` set; consulted by tier (1) of the
  resolver and by generic-call binding; exported in `.nuch`.
- Resolver at `emit-list`'s function branch (src:~3574) gains: protocol-bound
  matching + the new tier; generic-`defn` calls trigger monomorphize-or-cache.
- A generic-instantiation cache keyed `name.<concrete-tuple>` (reuses the
  body-retention/re-emit path from macros/JIT).

### 8.9 Checked vs. unchecked generic bodies (where `type-of-node` re-enters)

- **A1 (cheap):** don't type-check the generic body up front; just stamp it per
  concrete type and let Option 1 resolve protocol calls *at stamp time*. Calling
  a method the protocol doesn't guarantee fails only when stamping for a type
  that lacks it — **C++-template-quality errors.** Needs only body retention +
  re-emit.
- **A2 (right):** type-check the body **once** against the protocol's abstract
  interface (inside `max`, `T` is "some Ord"; the only ops on it are Ord's
  declared methods, whose signatures are known). Errors at *definition*. This
  needs the **non-emitting `type-of-node` pass** (decision #7) so the body can be
  typed against an abstract `Self` before any concrete type exists.

A2 = A1 + an up-front check; the *runtime model is identical*. **Ship A1, add the
A2 check later** without disturbing emitted code. This is also the moment the
`type-of-node` investment (which §4 flags as enabling Options 3/4,
`addr-of`-of-overload, generic places) starts paying for itself.

### 8.10 Revised staging

1. **Option 1 core** — `g-generics` + mangling + resolver + prescan + `.nuch`.
   Ships multimethods; independently useful.
2. **`defprotocol` + `extend`** — `g-protocols`/`g-conformances` + post-prescan
   check pass + `.nuch` export. Named capability, great diagnostics, *no
   runtime*.
3. **Bounded generic `defn`** — one named type variable + protocol bound, bare
   positions only; monomorphizer (retain body, substitute, stamp, cache).
   Delivers abstract parameters **and** B1 abstract returns together. Land A1
   first; add the A2 `type-of-node` check after.
4. **`(dyn Protocol)`** — fat pointer; enables B2 returns and heterogeneous
   collections; the only runtime-cost rung; opt-in; deferred until needed. *This
   deferral is now realized by [stage13/type-erasure.md](../stage13/type-erasure.md),
   which builds `(dyn Protocol)` and `BoxedFn` as one shared fat-pointer machine.*
5. **Full Option 3** — nested type-variable positions, multiple variables,
   generic struct layout, real unification.

The runtime model only changes at rung 4; rungs 1–3 are pure compile-time and
C-ABI-neutral.

### 8.11 Open forks for the designer

- **§8.4** — adopt the *named type variable + `:where`* form (with `x:Show` as
  sugar), or keep literally-bare protocol parameters and accept that same-type
  binary protocols (Eq/Ord/Add) and B1 returns are out of reach? *Recommend
  named.*
- **§8.5** — confirm B2 (unbound abstract return) is deferred behind `dyn` and
  rejected until then.
- **§8.9** — ship A1 (stamp-time errors) first and retrofit A2, or fund
  `type-of-node` up front so generic bodies are checked at definition from day
  one?
- **Conformance** — nominal via `extend` (chosen: explicit, best errors,
  exportable) vs. structural/implicit (Go-style, no `extend`). Recommend keeping
  nominal as chosen; the structural alternative is noted only for the record.

---

## 9. Designer decisions — resolved (2026-06-06)

This section is the authoritative build spec. Where it differs from §§1–8 (which
record the exploration), **this section wins**. Line numbers below are current as
of the 3899-line `src/nucleusc.nuc`; the `src:` refs scattered through §§1–8 are
stale (they cite up to src:4907) and should be read as approximate.

### 9.1 Surface & semantics

- **Substrate:** the §8 hybrid — Option 1 overloaded `defn` (a `defn` whose name
  exists but whose parameter types differ *adds a method*) as the implementation
  layer, with protocols as a thin checked abstraction on top. Dispatch among
  concrete impls is **multiple** (on the whole argument tuple); abstraction is
  **single-variable**.
- **Named type variables (§8.4), constraints inside the param list.** Canonical
  form:
  ```lisp
  (defn max:T (a:T b:T &where (Ord T)) (if (lt? a b) b a))
  ```
  `&where` follows all value params (and `&rest` if present); each constraint is
  single-variable `(Protocol Var)` — multi-parameter constraints are out of scope
  (§8.6). `x:Show` is **sugar** for a fresh single-use variable
  `x:T &where (Show T)`. Binding: gather the concrete type at every bare
  occurrence of a tyvar among the arguments, require equality, substitute, stamp,
  cache. No unification engine while we stay in bare positions.
- **Tyvar identification: declared-only.** A name is a type variable *iff* it is
  bound in a `&where` constraint (or introduced by the bare-protocol sugar). Any
  other unknown type identifier remains an `unknown type` error — typos stay
  caught (`(x:Circel …)` errors, it does not silently become a tyvar). The
  capitalization/lexical convention was rejected.
- **Conformance: nominal `extend`, no code.** `extend Type Protocol` runs as a
  post-prescan pass: for each required signature with `Self → Type` substituted,
  confirm it **resolves to a method at the exact tier**; record `(Type, Protocol)`
  in `g-conformances` and export in `.nuch`. Missing ⇒ compile error naming the
  absent methods. A concrete impl is required (blanket-generic satisfaction
  deferred).
- **No `dyn` (§8.5).** B1 (abstract return *bound by a parameter* tyvar, e.g.
  `max:T`) is supported and free per instantiation. B2 (abstract return bound by
  *no* argument, Haskell `read`) is **rejected with a clear error** until/unless
  `dyn` lands.
- **Nested tyvar positions deferred.** `(ptr T)`, `(Pair T U)`, etc. are rejected
  ("deferred to Option 3"); tyvars appear only in bare param/return position.

### 9.2 Operators routed through dispatch — with a hard intrinsic rule

**Decision:** all operators become generic names. The built-ins currently in
`init-binops` (src:1066) and resolved at `emit-list` (src:2209, *before* function
lookup) — `+ - * / % bit-* = != < <= > >=` — are pre-registered as **intrinsic
seed methods** in `g-generics` (e.g. `+` has methods `(i32,i32)→i32`,
`(f64,f64)→f64`, …). Operator dispatch and function dispatch unify into one path.

**Zero-overhead rule (non-negotiable — from the kickoff requirement).** An
intrinsic method, when selected, **emits its inline instruction** (`add nsw`,
`icmp slt`, …) exactly as `emit-binop` does today. It must **not** lower to
`call @+.i32.i32`. Even at `-O0`, `(+ a b)` on two `i32`s emits a single `add`,
byte-identical to current output. The resolver returns one of:
*intrinsic → inline* / *user method → `call`* / *generic → monomorphize-or-cache*.

Two fidelity requirements (match current behavior, not merely "resolve somehow"):

- **Numeric promotion / mixed operands.** `(+ i32 i64)` must resolve via the
  widen tier to the same result type the current binop coercion picks.
- **Untyped int literals.** `(+ x 1)` must let the literal adapt to the other
  operand's method, as `emit-binop` does now.

**Fast path:** head is an intrinsic operator **and** all args are the same
built-in numeric ⇒ short-circuit straight to existing `emit-binop` instruction
emission. Protects compile speed and the self-hosting bootstrap (operators are
the hottest path in the compiler itself).

**Dividend:** with operators unified into dispatch, `node-type` (§9.3) needs *no
separate binop typing rule* — operator calls type exactly like any other generic
call (and for abstract `T` with `(Add T)`, type to `T`).

### 9.3 `type-of-node` via shared refactor

**Decision:** build the non-emitting type pass by **factoring type computation out
of `emit-node` into a shared `node-type(n, scope) → Type`** that `emit-node` then
calls before emitting. One typing rule per node kind, used by both paths, so the
type pass and codegen **cannot drift** — critical, since a divergence corrupts
the next bootstrap. (Separate parallel pass and subset-only were rejected for the
drift risk and because generic bodies are nearly the whole language.)

- Total over the language, built incrementally behind emit, validated by the
  bootstrap at each step.
- Enables **A2 (§8.9):** generic bodies are type-checked **once at definition**
  against the abstract interface (inside `max`, `T` is "some Ord"; only Ord's
  declared methods are callable on it). Errors land at the `defn`, not at stamp
  time.

### 9.4 Registries & hook points (current line numbers)

- `g-generics` — name → method set; mirror `g-cast-rules`
  (`register-cast-rule` / `lookup-cast-rule`, src:1159–1170). **Seeded with the
  intrinsic operator methods** (subsumes the standalone role of `init-binops`).
- `g-protocols` — protocol name → required signatures (with `Self`).
- `g-conformances` — `(Type, Protocol)` set; consulted by resolver tier (1) and
  by `extend`; exported in `.nuch`.
- Resolver folded into `emit-list` across the binop region (src:2209) and the
  function-call region (src:~3574): unified resolve-then-emit.
- Generic-instantiation cache keyed `name.<concrete-tuple>`; reuse the
  macro/JIT body-retention/re-emit path.
- Tyvar-aware parsing: `parse-type-name` (src:535), `emit-defn` (src:2331), and
  `prescan-defn-signatures` (src:3195) must skip eager parse for declared tyvars
  and **retain** generic bodies instead of emitting/declaring them.
- `.nuch`: generic `defn`s export the **whole form** like `emit-nuch-defmacro`
  (src:3475), not a bare `declare`, so importers can instantiate.
- Mangle-or-not is decided **after prescan** (full method set per name known), so
  a set's first and later methods stay consistent. Solitary name → unmangled
  `@name` (stays C-callable); overloaded set → mangled `@name.<tok>…`.

### 9.5 Revised staging

"type-of-node up front" = do A2 (def-time checking) when generics land, *not*
A1-then-retrofit; it does **not** reorder the project. Because operators now route
through dispatch, the resolver + intrinsic seed methods are part of rung 1, so
rung 1 is **larger** than §8.10 implied.

1. **Resolver core** — `g-generics` + operators-as-intrinsics + mangling +
   prescan + `.nuch`. Multimethods work; operators emit byte-identical IR;
   bootstrap green.
2. **`defprotocol` + `extend`** — `g-protocols` / `g-conformances` + post-prescan
   check + `.nuch`. Named capability, great diagnostics, no runtime.
3. **`node-type` shared refactor** — land before bounded generics so A2 is
   available from day one.
4. **Bounded generic `defn`** — named tyvar + `&where`, bare positions only;
   monomorphizer (retain body, substitute, stamp, cache) + A2 def-time check via
   `node-type`. Delivers abstract params and B1 returns together.
5. **Deferred:** `dyn` (B2, heterogeneous collections); full Option 3 (nested /
   multiple tyvars, generic struct layout, real unification); REPL per-method
   redefinition; `(addr-of overloaded-name)` disambiguation.

The runtime model is pure compile-time through rung 4; only `dyn` (rung 5) adds a
runtime artifact.

### 9.6 Low-stakes defaults (will implement unless redirected)

- `&where` after all value params (after `&rest` if both present); multiple
  single-variable constraints allowed.
- Nested tyvar positions rejected with a deferral error.
- `extend` satisfied iff each substituted signature resolves at the exact tier
  (concrete impl required).
- REPL per-method redefinition and `addr-of`-of-overload disambiguation deferred.

### 9.7 Implementation status

**Rung 1 (Resolver core) — landed.** As of this commit, `src/nucleusc.nuc` has:

- `g-generics` registry (`Generic`/`Method` structs); operators seeded as
  **intrinsic** methods (`init-generics`) and routed through `emit-dispatch`,
  emitting byte-identical IR (`emit-binop` fast path) — verified by diffing every
  `examples/*.nuc` against the prior bootstrap binary and by the `make bootstrap`
  fixed point.
- Overloaded `defn`: a repeated name with differing parameter types adds a
  method. Methods are registered in `prescan-defn-signatures`; mangling is decided
  after the prescan by `finalize-generics` (solitary → unmangled `@name`,
  C-callable; overloaded → `@name.<tok>…` per method). `emit-defn` emits each
  under its resolved symbol; `emit-generic-call` resolves the call and reuses the
  shared `emit-call-with-args`.
- Dispatch is **exact structural match** (`type-eq`): tier 0 only. Tiers 1–3
  (protocol-bound, widen, `defcast`) and untyped-int-literal adaptation for user
  calls are **not yet implemented**; non-exact overloaded calls error clearly.
  (Operators keep full numeric promotion via `emit-binop`.)
- Root-cause fix enabling struct-typed parameters: `prescan-struct-names`
  pre-registers struct names before signatures are scanned (previously *any*
  `defn` with a struct-typed param failed at prescan, in the old compiler too).
- `.nuch` export/import of overloads via a new `defmethod` form
  (`emit-nuch-defn` / `emit-nuch-defmethod` / `emit-nuch-defmethod-import`);
  cross-unit dispatch verified end-to-end.
- Test: `examples/overload.nuc` + `tests/expected/overload.out`.

**Rung 2 (`defprotocol` + `extend`) — landed.** As of this commit:

- `g-protocols` registry (`Protocol` struct: name + array of raw signature
  Nodes) and `g-conformances` registry (`Conformance` struct: type-name +
  proto-name). Both grow like `g-generics`.
- `defprotocol` is registered in a `prescan-protocols` pass (alongside
  `prescan-struct-names` / `prescan-defn-signatures`) and emits **no code**.
  Required signatures are stored raw so their `Self` occurrences aren't parsed
  until conformance time.
- `extend Type Protocol` (`emit-extend`) runs in the top-level emit loop —
  i.e. after the whole-file prescan, so every method signature is registered and
  finalized. For each required signature it substitutes `Self → Type` via
  `subst-self-node` (colon-segment-level: `self:ptr:Self` → `self:ptr:Circle`),
  reuses `defn-params-to-types` / `defn-params-count` / `generic-find-method-exact`
  to require an **exact-tier** concrete method, reports every missing method to
  stderr, then `die-at`s if any were absent. Success records the conformance.
- `Self` substitution replaces only colon-delimited segments equal to `Self`, so
  pointer (`ptr:Self`) and by-value (`Self`) forms both work and unrelated names
  containing the substring are untouched.
- `.nuch`: `defprotocol`/`extend` export verbatim (`emit-nuch-defprotocol` /
  `emit-nuch-extend`); on import the protocol re-registers and the conformance is
  recorded **without** re-checking (the exporter already verified it). Verified
  end-to-end: a consumer importing only the generated `.nuch` dispatches across
  units correctly.
- Test: `examples/protocol.nuc` + `tests/expected/protocol.out`.

The `g-conformances` registry is populated but not yet *consulted* — its consumer
is the protocol-bound resolution tier in rung 4.

**Rung 3 (`node-type` shared refactor) — landed.** As of this commit:

- `node-type(n, scope) → Type` is a non-emitting type pass, total over the
  language's value forms (leaves; symbol/const/fn lookup; operators; ordinary,
  overloaded, and function-pointer calls; `cast`/`alloca`/`sizeof`/`char`;
  `deref`/`aref`/`ptr+`/`addr-of`; `.` field access; `do`/`let`/`with` blocks;
  the void-typed statement forms). One rule per node kind, derived directly from
  the corresponding `emit-*` function.
- **Integration (no drift).** `emit-node` sets the type a node propagates to its
  parent from `node-type` (when non-null). So codegen now *consumes* the shared
  rule rather than each `emit-*` computing types independently — a divergence
  corrupts the next bootstrap and is caught immediately. Verified: `make
  bootstrap` fixed point holds (stage1.ll == stage2.ll) and all examples emit
  byte-identical IR, i.e. `node-type` agrees with `emit` on every node across the
  entire self-hosting compiler.
- **Coverage / frontier.** Compiling the compiler, `node-type` returns a concrete
  type for ~88% of nodes; it returns null (→ "keep the emit-computed type") only
  for the forms whose result type can't be reproduced purely: macro calls (incl.
  `if`/`when`/`->`, which are prelude macros), `cond` (termination-dependent phi
  typing), and `quasiquote` of a bare unquote — plus any node whose relevant
  child is one of those. These are exactly the cases §9.3 flagged; modelling
  value-position conditionals exactly (so A2 can type `(if … a b)` bodies) is
  folded into rung 4, where generic bodies are macro-expanded before checking.
- **Invariant for future edits:** changing an `emit-*` form's result type, or
  adding a new special form to `emit-list`, requires updating `node-type`'s
  matching rule in lockstep; the bootstrap enforces it.

**Rung 4 (bounded generic `defn` + monomorphizer) — landed.** As of this commit:

- A `defn` whose parameter list carries a `&where` clause is a bounded-generic
  template: `(defn maxv:T (a:T b:T &where (Ord T)) …)`. `&where` follows all value
  params; each constraint is single-variable `(Protocol Var)`; multiple
  constraints are allowed. Type variables are **declared-only** (a name is a tyvar
  iff bound in a constraint), so unrelated unknown types still error. Bare
  positions only — nested (`(ptr T)`) and return-only (B2) variables are rejected
  with clear deferral errors at the `defn`; `&rest`+`&where` is rejected.
- `Method` gains `METHOD-GENERIC` fields (tyvar names + `(proto,var)` constraints
  + retained body). Templates are registered by `register-generic-defn` from
  `prescan-defn-signatures` (instead of the eager type parse); `finalize-generics`
  routes any generic-bearing name through the mangled/dispatch path with no
  solitary `@name` binding.
- **Resolution.** `generic-resolve` keeps tier 0 (exact concrete wins, §8.6) and
  adds tier 1: `generic-method-bind` unifies the bare-tyvar params against the
  argument types (repeats must agree), `generic-constraints-ok` requires each
  bound type to conform (nominally, via `g-conformances` — now *consulted*) to its
  protocol. A unique tier-1 match triggers `generic-instantiate`.
- **Monomorphizer.** `generic-instantiate` caches on the concrete param tuple
  (`generic-find-method-exact`); on a miss it stamps a concrete method via
  `monomorphize-form` (colon-spelling substitution through `subst-tyvars-node`,
  reusing the `Self`-substitution idea — necessary because `defn` *bodies* are not
  desugared, so type annotations remain colon-symbols like `r:T`), registers it
  with its mangled `@name.<tok>…` symbol *immediately* (so the call site can name
  it), and queues the body (a `MonoJob` carrying the stamped form + an
  instantiation-context string). `drain-mono-worklist` (persistent cursor,
  recursion-safe) emits queued bodies at the end of the top-level loop; stamping
  inside a drained body extends the same worklist. B1 abstract returns come for
  free. While a body emits, `g-mono-context` holds its context so any stamp-time
  emit error (a deferred operator/overload that the concrete type can't satisfy)
  gets a `die-at` note — `while instantiating @weird.f64.f64 (requested at
  file:line)` — pointing back to the requesting call site.
- **Cross-unit.** A template exports verbatim through `.nuch`
  (`(defn (maxv T) (… &where (Ord T)) …)`); an importing unit re-registers it and
  monomorphizes its own instantiations locally, calling the exporter's concrete
  methods by mangled symbol. Verified at the codegen level.
- **A2 def-time checking (landed, lenient).** Each template body is type-checked
  once at its definition against the abstract protocol interface, *before* any
  instantiation. A new abstract type kind `TY-TYVAR` (carrying the owning template
  + tyvar index; `type-eq` compares those) types the parameters; `gcheck` walks
  the macro-expanded body. A call on an abstract value that resolves to a protocol
  method of the relevant tyvar's constraints (`Self → T`, via
  `abstract-call-via-protocol`) or to another generic whose constraints the
  caller's tyvar constraints satisfy (`abstract-call-via-generic`) is checked
  precisely and yields a precise result type. The check is **lenient**: the only
  hard def-time error is a genuinely unknown function name (a typo) — a *known*
  operation the abstract interface can't confirm (an operator, or a
  foreign/variadic call like `printf` on an abstract value) is deferred to
  stamp-time (A1) rather than rejected, since it may be valid for the concrete
  type. `TY-TYVAR` never reaches codegen (templates emit only after
  monomorphization), so there is no drift with `emit`. `check-generic-templates`
  runs at the **outermost** `emit-toplevel-forms` (after all imports/includes/
  conformances are registered, g-source-path restored) and before the worklist
  drain, so the A2 error precedes the A1 stamp-time error. Imported templates are
  trusted (the exporter already ran A2) and skipped.
- Test: `examples/generic.nuc` + `tests/expected/generic.out`. `make test` (33
  cases) and `make bootstrap` (stage1==stage2) green.

**Not yet started:** rung 5 (`dyn`, full Option 3). Deferred within rung 4:
same-name overloading where the importing unit *also* defines methods for the
same name; widen/cast resolution tiers and untyped-int-literal adaptation for
user calls; user-defined operator overloads; REPL generic instantiation (the
worklist is only drained from the batch top-level loop); the inline-`defn` sugar
inside `extend`; bare-protocol parameter sugar (`x:Show` for `x:T &where (Show
T)`); blanket-generic conformance; and exact value-position typing of
`cond`/`if`/macro results in `node-type`. A2 is deliberately lenient (defers
known-but-unconfirmable operations to A1); a strict mode that rejects any
operation the constraints don't prove is possible later but was judged too
restrictive for everyday generics.

---

## 10. Stage 9 extensions — planned (2026-06-07)

Three further **engine / generics** features are committed (designer direction;
this section carries the same build-spec authority as §9). The call-position work
that motivated two of them lives in [callable-values.md](callable-values.md),
which depends on this section. Together they **supersede several items previously
parked** in §9.5/§9.7 — user-defined operator overloads, the widen/`defcast`
resolution tiers, untyped-int-literal adaptation for user calls, and
blanket-generic conformance are now *planned here*, not deferred.

Unifying theme: remove the last constructs that are *not* ordinary generic
methods, so generic bodies, `Valid` inference, and protocol bounds see one uniform
world.

### 10.1 Blanket protocols + `Any`

A **blanket protocol** is a built-in protocol with **automatic conformance** — the
compiler records `(T, Protocol)` for every qualifying `T` without an `extend`. It
remains a *pure predicate* (§8.1): it provides no method bodies; it only asserts
required signatures, satisfied by methods that already exist (intrinsic or user).
This is the one mechanism the §9-era model lacked, and it is strictly smaller than
"protocols that provide methods" (Rust-style defaults), which stays out of scope.

Two ship:

- **`Any`** — requires no methods; every type conforms. It introduces a **type
  variable with no obligations** while keeping tyvars *declared-only* (§9.1):
  `(defn id:T (x:T &where (Any T)) (return x))`. Without it, declared-only forces
  every generic to name a constraining protocol; `Any` is the no-constraint
  constraint, so typos (`x:Circel`) still error rather than silently becoming
  tyvars. `generic-constraints-ok` short-circuits `(any-type, Any)` to true. Under
  lenient A2, operations on an `Any`-bound value defer to stamp time (A1) and error
  only on a concrete type that can't support them — C++-template-quality.
- **`Struct`** — requires the field-access method (`get`); every struct type
  conforms because the built-in `get` intrinsic already satisfies it. Its
  *semantics* (member access by symbol selector) are specified in
  [callable-values.md](callable-values.md); it is listed here only as the second
  instance of the blanket mechanism.

Implementation: a `g-blanket` set (or a flag on `Protocol`) consulted by
`generic-constraints-ok` and `emit-extend` *before* the nominal `g-conformances`
lookup. Exported in `.nuch` as built-in (importers re-derive, don't re-check).
**`Any` and `Struct` are hardcoded** for now; a *declarable* blanket-protocol facility
(libraries defining their own) is parked in `design/stage999-future.md`.

### 10.2 Inferred structural bounds — `Valid`

`&where (Valid T)` bounds a tyvar **structurally** (`Valid` chosen over `Duck`; the
name *nominates structural* checking): rather than naming a protocol,
the compiler **infers** the required interface from the body — every operation
applied to a `T`-typed value becomes a required signature, an *anonymous protocol
synthesized from usage*. It completes the spectrum of how a tyvar's obligations
are fixed:

| bound | obligations | conformance | checked |
|---|---|---|---|
| `Any` (§10.1) | none | trivial (blanket) | nothing — ops defer to stamp (A1) |
| **`Valid`** | inferred from body | structural | call site, vs. the inferred set |
| named protocol | declared | nominal (`extend`) | def site (A2) + `extend` |

Reuses the rung-4 A2 walk, reorganized: A2 walks the macro-expanded body with the
tyvar as abstract `TY-TYVAR` and *checks* each operation against declared
constraints; `Valid` instead **collects** each operation as a required signature.
The **call-site check is an automatic, anonymous `extend`** — for the concrete
argument type, confirm every collected signature resolves, exactly what
`emit-extend` (src:2600) does against a named protocol (substitute the tyvar,
require each resolves). Checking at the **call site** (not stamp time) is what
makes it beat plain A1: the error reads "`Circle` has no `less:i1(Circle,Circle)`,
required by `f`", localized before instantiation.

Frontier (same as lenient A2): cleanly inferable = *named* generic/protocol calls
directly on `T`-typed values (incl. call-position `get`/`invoke`). Operators become
inferable **once §10.3 lands** (they turn into ordinary calls); foreign/variadic
calls and requirements on values *derived* from `T` defer to stamp. First cut:
direct operations on `T`.

**Derived values — why "direct only" is a real boundary.** A *direct* operation has a
`T`-typed operand (`(less x x)` ⇒ require `less:(T,T)`). A **derived** value is the
*result* of such an operation, used further:

```lisp
(defn g:T (x:T &where (Valid T))
  (bar (foo x)))        ; (foo x):σ  — σ = foo's return for T, unknown at def time
                        ; ⇒ (bar (foo x)) requires  bar:(σ)→_
```

`σ` is **a function of `T`**, so the obligation is not a flat signature over `T` but an
**associated-type constraint** ("foo maps `T` to some `σ`; `bar` must exist on `σ`").
The anonymous protocol stops being a *set* and becomes a *constraint graph* with
type-level edges (`foo:T→σ₁`, `bar:σ₁→σ₂`, …). Three rungs of ambition:

- **Direct-only (first cut).** Infer a flat signature over `T`; a derived value's further
  use is **deferred to stamp** (lenient-A2 style). Cheap, no associated types — but the
  call-site guarantee covers only direct ops; derived misuse still surfaces at stamp.
- **Per-call-site non-emitting stamp (locality without a solver).** At each call site,
  with `T := C` known, substitute (`subst-tyvars-node`) and run the rung-3
  `node-type`/`gcheck` pass over the whole body *without emitting*, attributing any
  unresolved op to the call. Localizes derived-value errors by reusing the
  monomorphizer's substitution + the existing type pass. Cost: re-checks per concrete
  type (no reusable signature), and completeness is bounded by `node-type`'s coverage
  (null for macro/`cond`/quasiquote results — the rung-3 frontier). Converges toward A1
  but runs *before* emission and points at the call site.
- **Closed associated-type signature (the fixpoint).** Compute an
  instantiation-independent description: introduce a fresh tyvar per derived result and
  take the **least fixpoint** of "collect ops → discover derived types → collect their
  ops" until stable. Recursion ties the graph onto itself
  (`(h (next x))` ⇒ "next: Self→Self′ where Self′ satisfies P") and needs **cycle
  detection / coinduction** — the same hazard as recursive trait/typeclass resolution
  (Rust's recursion-overflow, Haskell `UndecidableInstances`). This is associated types
  + unification, i.e. the **deferred parametric-generics rung (Option 3 / rung 5)**, not
  a `Valid` increment.

**Plan:** ship direct-only; handle derived values by deferral *or* the per-call-site
stamp; reserve the closed-signature fixpoint for the parametric-generics rung.

Trade-off (acknowledged, not blocking): a structural bound is *implicit*, so
editing a body silently changes a generic's public requirements and loses the
documentation a named protocol carries. But **`Valid` is itself nominal** — you write
`&where (Valid T)` explicitly; it merely *nominates structural* checking rather than a
named interface. The default stays **always nominal** (§8.11): a bare `&where (T)` with
no protocol remains an error, never an implicit `Valid`. So `Valid` is an opt-in
structural bound beside the nominal default — as C++20 concepts are optional over bare
templates — not a replacement.

### 10.3 Operators as ordinary functions (supersedes §9.2's intrinsic *category*)

Arithmetic and comparison operators (`+ - * / %`, `bit-*`, `= != < <= > >=`) become
**ordinary generic methods**, retiring the distinct `METHOD-INTRINSIC` *category*
at the dispatch surface. This is the natural completion of §9.2 (operators already
route through dispatch) and removes the standing exception that complicates A2,
`Valid`, and protocol bounds: `(+ a b)` on a tyvar is now a clean required signature
`(+:T (T T))`, so **`Num`/`Eq`/`Ord` protocols are expressible** and `&where (Num
T)` works, and **user operator overloading falls out** of the multimethod
substrate.

**Protocol membership (resolved).** `Num` = `{+ - * /}` only — *not* `%` or `bit-*`,
which live in a **superset** protocol (e.g. `Integral`/`Bits`). `Ord` is a **superset
of `Eq`**: every `Ord` type is an `Eq` type but not vice-versa, declared as protocol
inheritance with **`(extend Ord Eq)`** — i.e. `extend`'s subject may be a *protocol*,
so conformance to `Ord` additionally requires conformance to `Eq`. This
protocol-on-protocol `extend` is the one small new mechanism the numeric hierarchy
needs (it also expresses the `Num`→superset relation).

Zero-overhead is preserved by a **front-end inline peephole**, *not* the optimizer:
the built-in numeric methods still emit their inline instruction (`add nsw`, `icmp
slt`, …) exactly as `emit-binop` does today. A plain function would emit `call
@+.i32.i32` at `-O0` (LLVM inlines nothing there), regressing dev/bootstrap builds
and breaking the byte-identical-IR invariant the `make bootstrap` fixed point
depends on — so the peephole is the **long-term default** (in code, not stone: not
planned to change, though not framed as an immutable invariant). The
special-casing **migrates** from a method *kind* (dispatch surface) to an *inlining
rule* (emission); it shrinks but does not disappear. Operators are the compiler's
hottest path, so the §9.2 fast path stays for compile speed.

This **requires finishing the deferred resolution work** (no longer optional): the
**widen/`defcast` tiers and untyped-int-literal adaptation** move into the shared
resolver so `(+ i32 i64)` and `(+ x 1)` resolve to the same result `emit-binop`
picks today — arithmetic fidelity and the bootstrap depend on byte-exact promotion.
`addr-of` of an operator needs an out-of-line copy emitted on demand. Short-circuit
`and`/`or`/`not` **stay special forms** (they don't evaluate all arguments).

Variadic arithmetic stays a **compile-time fold** (a function's arity is fixed;
`&rest`/varargs are runtime, not zero-overhead). The fold (today `lib/macros.nuc`,
or recast as a compiler-internal n-ary→binary expansion) now targets the
**polymorphic binary method**, so `(+ v1 v2 v3)` works over a user `Num` type. The
binary primitives `_+ _- _* _/` stop being special; the n-ary surface stays
expansion-based.

### 10.4 Staging (extends the §9.5 ladder)

Each step keeps `make bootstrap` green and is pure compile-time / C-ABI-neutral
(like rungs 1–4); only `dyn` (original rung 5) adds a runtime artifact.

1. **Resolution tiers** — widen/`defcast` + untyped-int-literal in the shared
   resolver. Prerequisite for §10.3; independently closes the rung-1 deferral.
2. **Operators as functions** (§10.3) — reclassify operators as methods + the
   front-end inline peephole; ship `Num`/`Eq`/`Ord` + user operator overloading.
   **Highest-risk step** (byte-identical-IR invariant, hottest path).
3. **Blanket protocols + `Any`** (§10.1) — `g-blanket`; trivial conformance path.
   *Prerequisite for the `Struct` member-access default in callable-values.md.*
4. **`Valid`** (§10.2) — collect-mode A2 + call-site auto-`extend`.

The call-position feature (callable-values.md) slots after step 3 (it needs the
`Struct` blanket protocol) and benefits from steps 1–2 (operator/`Num` uniformity)
but does not block on them.

## Open questions (Stage 9 extensions) — resolved 2026-06-07

1. **Operator peephole permanence (§10.3).** Confirm the front-end inline peephole
   is a permanent part of the model (my position — `-O0` byte-identical is
   non-negotiable), vs. a stopgap behind an always-on inlining pass (simpler front
   end, but `-O0` semantics then depend on a pass).
2. **`Num`/`Eq`/`Ord` membership.** Which operators each standard numeric protocol
   requires (does `Num` include `%` / `bit-*`? is ordering `Ord` separate from
   equality `Eq`?), and whether they ship in the prelude or an importable library.
3. **`Duck` naming & frontier (§10.2).** `Duck` vs `Valid` vs `Structural`; and
   whether the first cut also infers requirements on values *derived* from `T`
   (needs a fixpoint) or strictly direct operations only.
4. **Blanket mechanism generality (§10.1).** Expose blanket conformance as a
   declarable facility (libraries define their own blanket protocols) or keep
   `Any`/`Struct` as the only two, hard-coded?
5. **Structural-vs-nominal default.** With `Duck` available, keep nominal `extend`
   as the default (my recommendation), or let a bare `&where (T)` with no named
   protocol imply `Duck`?


#### Designer

1. Let's say long-term, not permanent. It's written in code, not stone, but I don't plan to change it.
2. `Num` does not include `%` or `bit-and`. There could be a superset protocol which does. `Ord` is a superset of `Eq`. Something can be `Eq` without being `Ord`, but nothing can be `Ord` without being `Eq`. We can presumably just `(extend Ord Eq)`.
3. Cute as `Duck` is, I think `Valid` is the best name. Implement Per-call-site non-emitting stamp (locality without a solver).
4. Hardcode `Any`/`Struct` for now. The possibility of a declarable facility is added to stage999.
5. Always nominal. Even `Valid` is nominal in a sense; it just nominates structural.

---

## 11. Implementation status — §10 extensions landed (2026-06-07)

All four rungs of the §10.4 ladder are implemented in `src/nucleusc.nuc`; `make
test` (36 cases) and `make bootstrap` (stage1.ll == stage2.ll, byte-identical)
are green. As with §9.7, this section is authoritative where it refines §10.

**Step 1 — resolution tiers (§10.4.1).** The widen and untyped-int-literal tiers
are in the shared resolver. `binop-coerce` / `coerce-num-val` adapt mixed operands
for operators (`emit-binop-vals` is the split-out inline core; `emit-binop` is the
arg-emitting wrapper); `arg-adapts` + a tier-2 search in `generic-resolve` (and the
parallel `operator-user-resolve`) do the same for user calls, with
`emit-generic-call`/`emit-resolved-call` coercing the arguments to the chosen
parameter types. So `(+ i32 i64)`, `(+ x 1)`, and a `(foo i32)` call resolving to an
`i64` overload all work. **`defcast` was found absent from the current tree** (the
§1 references are stale); the cast tier is therefore *not* implemented (no
cast-rule registry exists). The widen + literal tiers are what §10.3 actually
requires; literalness is probed (via a bounded `macroexpand` that sees through the
variadic-operator wrappers) only after operand types are known to differ, so the
same-type hot path costs nothing and stays byte-identical.

**Step 2 — operators as ordinary functions (§10.3).** `METHOD-INTRINSIC` is kept
as the *emission* marker (the inline peephole) rather than deleted, exactly the
"special-casing migrates to an inlining rule" the section describes. A pure
operator (no user overloads) short-circuits to `emit-binop` (byte-identical); an
operator that has gained user methods routes through `emit-operator-dispatch`,
which resolves a user method (call) or falls back to the inline peephole.
`finalize-generics` now mangles user methods on operator names (`op-name-token`
maps `=`/`<`/`_+`/… to IR-safe mnemonics — `eq`/`lt`/`add` — since the raw symbols
are illegal LLVM identifiers and collide under blanket sanitizing). Built-in
numeric/pointer types satisfy operator protocol requirements via
`builtin-op-result-type` (consulted by `method-satisfies-sig`), so `(extend i32
Ord)` holds with no user method. **`Num`/`Eq`/`Ord` ship in `lib/numeric.nuc`**;
protocol-on-protocol `(extend Ord Eq)` records an inheritance edge (`g-proto-supers`)
that `verify-conformance` recurses. `node-type-call` mirrors the operator dispatch
(shared `operator-user-resolve`) so the rung-3 no-drift invariant holds.
Two latent bugs surfaced and were fixed at the root (both byte-identical for the
bootstrap): `emit-cond` compared branch types by pointer instead of `type-eq` (so
a cond/`if` returning a typed pointer silently yielded void); and
`extract-name-and-type`'s desugared-cell branch called the single-token
`parse-type-name` on a colon-bearing type symbol (which a pointer-typed generic
instantiation produces). Example: `examples/operators.nuc`.

**Step 3 — blanket protocols + `Any` (§10.1).** A hardcoded `g-blanket` set
(`Any`, `Struct`) with `blanket-conforms` (structural: `Any` ⇒ every type;
`Struct` ⇒ struct or pointer-to-struct). `generic-constraints-ok` consults it
before the nominal registry; `constraint-proto-known` lets `&where (Any T)` /
`(Struct T)` name a valid bound while keeping tyvars declared-only (typos still
error). Explicit `extend` to a blanket is a no-op (conformance is automatic).
Constraint-protocol typo checking moved from the prescan into the A2 pass so an
*imported* protocol can be named in a `&where`. Example: `examples/blanket.nuc`.

**Step 4 — `Valid` (§10.2).** Realized as the **per-call-site non-emitting stamp**
(designer decision 3). At each instantiation of a `Valid`-bounded template,
`valid-check-instance` walks the substituted concrete body (`valid-walk`) without
emitting; each generic/operator call is resolved non-destructively
(`valid-resolve-type`), and a call the concrete type can't satisfy aborts *at the
call site* (`type 'C' does not satisfy the Valid bound of 'g'`). Because the walk
carries concrete types throughout, **derived values** (`(bar (foo x))`) are checked
without an associated-type solver — the chain types `(foo x)` concretely and then
checks `bar` on that. The def-time A2 walk stays lenient for `Valid` bodies
(operations defer to the call-site stamp). Example: `examples/valid.nuc`.

**Implemented (TE-0 … TE-7):** the `(dyn Protocol)` fat pointer (B2 returns /
heterogeneous collections) — realized in
[stage13/type-erasure.md](../stage13/type-erasure.md) as one shared machine
with `BoxedFn` (TE-5/TE-6); 129 tests pass, byte-identical bootstrap. See
`docs/generics.md` §Type erasure for the user-facing reference.

**Still deferred:** `defcast` and a cast resolution tier (no registry in-tree);
nested / multiple type-variable positions and a real unifier (full Option 3);
REPL per-method redefinition; `(addr-of overloaded-name)` disambiguation;
`extend`'s inline-`defn` sugar; bare-`x:Show` parameter sugar; a
user-declarable blanket facility (parked in stage999-future.md); and exact
value-position typing of `cond`/`if`/macro results in `node-type` (the rung-3
frontier `Valid` and A2 inherit). The `Struct` blanket's `get` member-access
method is specified in callable-values.md and not part of this section.
