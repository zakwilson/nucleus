# Collections - second cleanup pass

The addition of associated types means previous design decisions, documentation, and comments based on their absence must be revisited.

---

## 0. Premise

Associated types (A0–A4, [assoc-types.md](assoc-types.md)) are implemented and
**validated**: `examples/assoc-iter-return.nuc` confirms the load-bearing case — a
protocol method whose return type is a bare associated type, with a generic
consumer whose constraints are interdependent *through the conforming variable*
(`((IterColl It) C)` recovers `It`; `((Iterator E) It)` then makes the recovered
`It` a conforming variable and recovers `E`). It compiles, runs, and bootstraps
byte-identically.

Many Stage-11 decisions, doc paragraphs, and source comments were written while
this was impossible. They fall into three buckets, each handled below:

1. **"X can't be a protocol method — its return type is `Self`-derived."** Now
   expressible. Decide per case whether to *lift* it (real uniform-generic value)
   or *keep it standalone* (long tail) — but either way the **rationale comment is
   now false** and must change from "impossible" to a real design reason.
2. **"Element/arg types are fixed because protocols substitute only `Self`."** The
   parametric-protocol + associated-type rung has arrived; the fixed-type
   function-object / indexable protocols are legacy.
3. **Deferred-limitation tables** that list the "parametric-protocol `&where`
   frontier" / phantom-param workarounds as open. Those are resolved.

## 1. Scope and gate

- **Consolidation, not new features.** No new language capability is introduced
  here; this spends the capability already shipped.
- **Standing gate (every code step):** `make bootstrap` stays a byte-identical
  fixed point **and** the full test suite stays green. Each uplift adds/adjusts an
  `examples/*.nuc` + `tests/expected/*.out`.
- **Out of scope (still deferred, unrelated to associated types):** lambdas/
  closures, `dyn`/heterogeneous collections, persistent/immutable collections.
- **The lift-vs-keep judgement** (from [string.md](string.md) eval §2): each
  `Self`-derived return costs one associated param **plus an extra `&where` bound
  at every consumer**. Lift the ops that are genuinely used through a generic
  bound; leave one-off ops standalone and just correct their comment.

## 2. Work items

### C2.0 — Compiler: generalize `get` dispatch (prerequisite for C2.2a) — DONE

**Status: implemented.** `emit-get-with-callee` (`src/nucleusc.nuc`) now splits on
the selector kind; a new non-dying resolver `generic-resolve-nullable` (tier 0 exact
`METHOD-USER` + tier 1 `METHOD-GENERIC` bind/`&where`/instantiate, null on no match)
selects a parametric value-keyed `get` override. Branch A (literal symbol) is
unchanged, so `make bootstrap` is byte-identical. Exercised by
`examples/get-dispatch-test.nuc` (`CStr`- and `i32`-keyed `(Bag K V)`; a `'val`
selector still does field access). C2.2a is now unblocked.

**Decided (Q-get-name):** `get` is the associative lookup for `Assoc`; `_get` stays
the raw field intrinsic. The `get`/`_get` split already exists (`_get` →
`emit-field-get`, always a field; `get` → `emit-get-with-callee`, override-then-
intrinsic), so the model is sound — but **a parametric-map `get` override cannot be
selected today**, for two reasons in `emit-get-with-callee` (`src/nucleusc.nuc:7394`):

1. It resolves overrides with `generic-find-method-exact` (`:4390`), which matches
   only **concrete** (`METHOD-USER`) methods by exact param type and **ignores
   `METHOD-GENERIC`**. A `HashMap` key getter is generic over `(K V)`, so it is
   never found.
2. The selector arg type is **hardcoded to `ty-ptr`** (`:7402`) and emitted
   symbol-style (`emit-selector-value`). A non-pointer key (`i32`) cannot dispatch,
   and a `CStr` key (distinct from `ptr`) will not exact-match.

**Change.** In `emit-get-with-callee`, split on the selector:

- **Literal-symbol selector** (`'field` / bare `field`) → **unchanged** (symbol →
  interned ptr; exact-`USER`-override then field intrinsic). Field access is
  untouched.
- **Computed/value selector** → emit it as a value, take its **real type** `kt`,
  and resolve a `get` override on `(callee-type, kt)` with a **non-dying generic
  resolve** (binds tyvars + checks `&where`, like `generic-resolve` but returning
  null on no match). On a hit, call it; on a miss, fall back to the existing
  computed-field intrinsic.

**Byte-identical safety:** the compiler's own source uses only symbol selectors on
its own structs (no value-keyed `get` override exists), so every current call
resolves down the identical path; the new branch is reached only by code that
defines such an override (i.e. `Assoc`). Ship with an example exercising
`(get hashmap key)` for both a `CStr`-keyed and an `i32`-keyed map.

> Alternative considered and rejected: key access via `invoke:(Maybe V)` (`(m key)`)
> needs no compiler change, but cannot spell `(get m key)` and does not honour the
> `get`/`_get` distinction. C2.0 is the chosen path.

### C2.1 — Lift `iter` into `Coll`

`lib/coll.nuc` deliberately omits `iter` ("returns an iterator type derived from
`Self`, not expressible without associated types"). It now is.

- Add an associated iterator parameter: `(defprotocol (Coll E It) … (iter:It …))`.
- Conform `Vector`/`HashSet`/`HashMap` (the map iterates pairs — see C2.2c). The
  spike pattern is the template: a value-returning `iter` (`alloca` + set +
  `(deref …)`), driven via `(addr-of it)`.
- **Iterator convention — decided (Q-iter-convention): value return.** The protocol
  `iter` returns the iterator **by value**; consumers (`doseq`/`into`) take
  `(iter coll)` and `addr-of` internally to get the `(ref Iter)` that `next` wants
  (spike-proven). The existing fill-in-place `iter-init`/`hashset-iter`/
  `hmap-iter-keys` are demoted to internal helpers that the value-returning `iter`
  wraps (or are removed); the protocol surface is value-return only, one convention.
- **`doseq`/`into` migration.** They currently name those concrete initializers.
  With a protocol `iter` they dispatch generically over any `Coll`. This is the
  payoff and the riskiest part — do it after `iter` lands and is tested.

### C2.2 — Lift the `Assoc` query surface

[assoc-types.md](assoc-types.md) §5 explicitly parks this as "mechanically possible
… its own task." Split by difficulty:

- **C2.2a — key access via `get` (decided Q-get-name; gated on C2.0).** `hmap-get`
  returns `(Maybe V)`, and `V` is *already* an `Assoc` parameter, so no new
  associated type is needed: add `get:(Maybe V)` to `Assoc`, called as
  `(get m key)`. This depends on the C2.0 compiler change (a generic, value-keyed
  `get` override is unselectable until then). Once it lands, **delete the redundant
  `hmap-get`** and migrate its call sites (`docs/collections.md` examples, tests).
- **C2.2b — `keys`/`vals` (needs associated iterator types).** Return `Self`-derived
  iterators → add associated iterator parameter(s) to `Assoc`, same machinery as
  C2.1. Do after C2.1.
- **C2.2c — map-as-`Coll` element type = key/value pairs (decided Q-map-as-coll).**
  `HashMap`'s `Coll`/`iter` element is a **pair**, represented as a lightweight
  struct — e.g. `(defstruct (Entry K V) key:K val:V)` — so `HashMap` conforms to
  `(Coll (Entry K V) HashMapEntryIter)` and `iter` yields `Entry` values. This is
  what lets `into`/`doseq`/`reduce` work over a map uniformly. `keys`/`vals` (C2.2b)
  remain the separate single-projection iterators. (`Entry` is a plain value struct,
  returned by value like the spike iterator.)
- **C2.2d — `select-keys`.** Returns a new `Self` (Self-derived). Lower value;
  keep standalone, fix the comment.

### C2.3 — `Set.select`

Returns a Self-derived new set. The mutating algebra is already in the protocol;
`select` (filter to a new set) is the only omission. Low value for a generic bound
→ **keep standalone, correct the rationale** (it is a choice, not a limitation),
unless a concrete generic consumer appears.

### C2.4 — Reconcile the `Seq` design with the implemented lazy combinators

[collections.md](collections.md) §Seq still describes `map`/`reduce`/`filter` as
`Seq` protocol methods taking a `Call`. The implementation made them **generic lazy
iterator combinators** (`MapIter`/`FilterIter`/`reduce` in `lib/iterator.nuc`),
now fully element-generic via associated types. Update the design doc to match the
shipped lazy-iterator reality and retire the "Call-first, provisional until
lambdas" framing in favour of the `UnaryFn`/`FoldFn` function-object protocols.

### C2.5 — Retire the fixed-type function-object / indexable protocols

`lib/seq.nuc` (`Call` `ptr→ptr`, `BinaryCall` `ptr,ptr→ptr`, `IntIndexable` `i32`)
carries the comment "a `Seq` abstract over any element type **awaits the
parametric-generics rung**." That rung shipped: `(UnaryFn Arg Ret)` / `(FoldFn Acc
Elem)` are the generic replacements, and `Seq`/`Iterator` are parametric.

- **Decided (Q-legacy-removal): remove them.** Caller audit done — the only users
  are `examples/callable.nuc` (`extend Vec IntIndexable`, `extend Adder Call`) and
  the docs (`docs/special-forms.md`, `docs/builtins.md`, `docs/index.md`); **no
  compiler-internal use**. Migrate the example to `UnaryFn`/`FoldFn` (and a generic
  indexable for the `(v i)` demo), update those docs, then delete the protocols.
- **Variadic `Call` — confirmed not possible (and not in this pass).** `&rest` is
  macro-level (rest args are built as a `Node*` cons list *at the call site*, not a
  runtime varargs ABI), and Nucleus cannot `defn` a `va_list`-consuming variadic
  (stage888 C-interop boundaries). A function object is a value invoked at runtime
  through a uniform signature, so there is no mechanism for runtime-dispatched
  variable arity. If ever wanted, it is gated on lifting the stage888 "variadic
  functions defined in Nucleus" deferral first.

### C2.6 — Frame the phantom-param verbose forms as legacy

`examples/phantom-tyvar-test.nuc` (`MapIterVerbose I F S E`) and the
positional-tyvar-recovery path still compile and are a **valid orthogonal
feature** (phantom/field-less tyvar recovery), so **keep them as a regression
test** — but ensure every comment frames the verbose four-param form as
*superseded by associated types*, not as a recommended pattern. (assoc-types.md
§4.2/§4.3 already says new code should prefer the two-param form.)

### C2.7 — Documentation & comment rationale sweep (zero-risk)

Change "impossible / not expressible without associated types" to the accurate
"expressible via associated types; lifted (Cn) / deliberately standalone because …"
at every site:

| File:line | Current claim | Action |
|---|---|---|
| `lib/coll.nuc` 42–43, 73–74, 90 | `iter`/`get`/`keys`/`vals`/`select` "not expressible" | Point at C2.1/C2.2/C2.3 outcome |
| `lib/seq.nuc` 9 | "awaits the parametric-generics rung" | Point at C2.5 / `UnaryFn`/`FoldFn` |
| `docs/collections.md` 24, 58, 79 | iter/hmap-get/select "not in protocol" | Match the C2.1–C2.3 decisions |
| `docs/special-forms.md` ~200 | "no associated types yet" | Update; link generics.md assoc-type section |
| `docs/structs-unions.md` ~328 | "phantom params" framing | Note assoc-type supersession |
| `docs/generics.md` 192, 222 | already positive on assoc types | Verify consistent with new uplifts |
| `design/stage9/callable-values.md` 148–150 | "element type fixed today … needs associated types" | Update to "now available; see C2.5" |
| `design/stage11/string.md` | — | **already revised** (this round); no action |

### C2.8 — Close the resolved-limitation entries

- `design/stage11/parametric-structs.md` **Known limitations #3** (parametric-
  protocol `&where` frontier) — resolved by A1/A2; mark resolved (assoc-types.md
  already asserts this; make the source table agree).
- `design/stage11/progress.md` / `design/progress.md` — any row listing the
  `&where` frontier or "standalone `&where ((Seq E) Self)`" as deferred → resolved.
- `collections.md` "Functions as arguments (pre-lambda)" note ("with parametric
  protocols `Call` can range over actual types") — partially realized via
  `UnaryFn`; update to reflect C2.5.

## 3. Decisions (resolved)

| Q | Decision |
|---|---|
| **Q-get-name** | `Assoc` uses **`get`** (`(get m key)` → `get:(Maybe V)`), not `invoke`. `get` is overridable (`_get` is the raw field intrinsic), but a generic value-keyed override is **unselectable today** → needs the **C2.0** compiler change first; then delete `hmap-get`. |
| **Q-iter-convention** | Protocol `iter` returns the iterator **by value**; consumers `addr-of` internally. Fill-in-place `*-init` forms are demoted to internal helpers or removed. One convention. |
| **Q-map-as-coll** | `HashMap`'s `Coll` element is a **key/value pair**, a lightweight `(Entry K V)` struct returned by value; `iter` yields `Entry`. `keys`/`vals` stay as separate single-projection iterators. |
| **Q-legacy-removal** | **Remove** `Call`/`BinaryCall`/`IntIndexable` (only `examples/callable.nuc` + docs use them; no compiler use). **Variadic `Call` confirmed not possible** — `&rest` is macro-level, no Nucleus-definable varargs; gated on the stage888 variadic-defn deferral. |

No open design questions remain; the only residual is a C2.0 implementation detail
(a non-dying generic-resolve helper for the value-selector branch — add if absent).

## 4. Sequencing

1. **C2.7 + C2.8** — doc/comment/limitation-table fixes. Zero risk, no bootstrap
   impact; do first so the record stops asserting a false premise.
2. **C2.0** — the `get`-dispatch compiler change (prerequisite for C2.2a; gated
   hardest for byte-identity, so do it early and prove it green).
3. **C2.2a** — add `get:(Maybe V)` to `Assoc`, delete `hmap-get` (depends on C2.0).
4. **C2.1** — `iter` into `Coll` (value-return associated iterator), including the
   `(Entry K V)` pair type for `HashMap` (C2.2c), then the `doseq`/`into` generic
   migration (the main payoff).
5. **C2.2b** — `keys`/`vals` into `Assoc` (reuses C2.1 machinery).
6. **C2.5** — remove the fixed-type protocols; migrate `examples/callable.nuc` + docs.
7. **C2.3 / C2.4 / C2.6** — `select`, the `Seq` design reconciliation, and the
   phantom-form framing — judgement/cleanup, lowest urgency.

Each code step (2–5) ships with its example + expected output and must leave the
byte-identical bootstrap and full suite green.
