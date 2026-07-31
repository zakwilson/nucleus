# W7 — The bare-symbol selector always means "field name"

**Status: B + D + E implemented** (see "As built" at the end). F — marked
selectors — remains the recommended end state and is deferred to its own stage;
C is superseded by F and should not be built.

**Provenance.** Unlike W1–W6 this item is *not* from the Doom port's
`NUCLEUS-FINDINGS.md`. It came out of the author's own stress testing of the
language, and is filed here because it is the same class of finding the stage
exists to collect: something that only shows up when you write ordinary Nucleus
rather than compiler code.

**Symptom.** `examples/hashmap-lit-test.nuc:19`:

```lisp
(with ((m (ref (HashMap CStr i32))) {"foo" 42 "bar" 7 "baz" 99}
       k:CStr "foo")
  (match (m k) …))
```

```
examples/hashmap-lit-test.nuc:19: error: get: no field 'k' on struct 'HashMap.cstr.i32'
```

`(m "foo")` works. `(m k)` does not, and neither does the explicit `(get m k)`.
The only spellings that work today obfuscate the selector into a compound
expression so it stops looking like a symbol:

```lisp
(m (as CStr k))     ; works — compound expression takes the value path
(invoke m k)        ; error: value is not callable: no `invoke` method …
```

That last line is the second half of the problem: `invoke` — the form whose
arguments *are* always values — has no `get` fallback, so it cannot serve as the
explicit escape hatch. There is currently **no** clean way to spell "look this up
by the value in `k`".

## Root cause

Selector classification is purely syntactic and irreversible.

`selector-literal-sym` (`src/nucleusc.nuc:3234`) answers "is this a field name?"
by looking at the node kind alone: any `NODE-SYM`, or `'sym`, is a field name.
Nothing else is consulted — not the scope, not the callee type's field set.

`emit-get-with-callee` (`src/nucleusc.nuc:3418`) then commits:

| | selector | branch | resolves against |
|---|---|---|---|
| A | bare/quoted symbol | member access | a `(callee-type, ty-ptr)` `get` method, else the struct intrinsic |
| B | anything else | value-keyed | the `get` generic on the selector's **actual** type |

For `(m k)`: Branch A looks for a `get` keyed on `ty-ptr`; `HashMap`'s `get` is
keyed on `K` = `CStr`, so no match; control falls into `emit-get-intrinsic`,
which does a struct-field-index lookup and dies. **There is no edge from Branch A
back to Branch B** — once the selector is classified as a symbol, the value
interpretation is unreachable, even when the field interpretation provably cannot
work.

`emit-invoke-with-callee` (`src/nucleusc.nuc:3491`) compounds it: when the
`invoke` generic has no method for the callee it dies rather than falling back to
`get`.

## Measurements

I instrumented `emit-get-with-callee` Branch A with two temporary probes and
compiled `src/nucleusc.nuc` plus every file in `examples/`. (Probes removed; the
tree is back to its original state.)

**Probe 1 — the selector symbol is also a local binding in scope.** This is the
set of sites a scope-first rule would silently re-interpret.

- **79 sites in the compiler's own source.** By selector:
  `name` ×27, `line` ×17, `s` ×6, `ty` ×5, `proto-name` ×4, `type-name` ×3,
  `key` ×3, `proto`/`param-types`/`ns`/`args` ×2, then singles.
- 3 sites across `examples/`.

**Probe 2 — the callee type carries a value-keyed user `get`, yet we are taking
the field-access branch.** This is the set of sites that would break if a
value-keyed `get` type gave up callable-form field access the way `invoke` does.

- **23 sites, every one of them inside `lib/hashmap.nuc`** — its own `get`,
  `assoc`, `resize`, etc. read `(self cap)`, `(self keys)`, `(self vals)`,
  `(self states)`, `(self count)` in head position.
- Plus 3 in `examples/get-dispatch-test.nuc`'s toy `Bag`.
- `(defn get ((self (ref (HashMap K V))) key:K) (Maybe V))` is the **only**
  value-keyed `get` in the whole stdlib (`lib/hashmap.nuc:282`).

## Options

### A — Scope-first: a bound symbol is a value, an unbound one is a field name

**Rejected.** Probe 1 says this silently changes meaning at 79 sites in the
compiler alone. Worse, it breaks the documented idiom that a user `get` method
reads its own fields in head position — `lib/hashmap.nuc:283` is
`(- (self cap) 1)` inside a method whose parameter is `key`, and
`examples/get-dispatch-test.nuc:29` is literally `(= (self key) key)`. Under a
scope-first rule that second one becomes `(get self <value of key>)` — infinite
recursion, which `context/conventions.md` already lists as the hazard `_get`
exists to avoid. The failure mode is a silent miscompile, not a diagnostic.

### B — Field-first with a value fallback (recommended)

Keep Branch A's priority. Add the missing edge: **before** falling through to
`emit-get-intrinsic`'s hard error, if the callee type has no such field and no
`(ct, ty-ptr)` user `get`, and the selector symbol resolves to a **local**
binding, retry as Branch B. If Branch B also finds no method, report the original
"no field `k` on struct `…`" error so diagnostics do not regress.

Sketch, entirely inside `emit-get-with-callee`:

```
sym = selector-literal-sym(sel-node)
if sym != null
   and no (ct, ty-ptr) user get method
   and struct-field-index(ct-struct, sym) < 0
   and scope-lookup(scope, sym) is a local (is-local != 0):
       sym = null          ; demote to a value selector; Branch B runs
```

- **Blast radius: zero.** Every site that compiles today has a field that
  resolves, so the demotion condition is false at all 79 Probe-1 sites and all 23
  Probe-2 sites. IR is unchanged; the bootstrap stays byte-identical.
- It strictly converts a compile error into working code.
- Gate the demotion on the local's type actually resolving a `get` method, so a
  plain struct's typo (`(p k)` where `p:Point` and `k:i32`) still reports
  "no field 'k' on struct 'Point'" rather than falling into
  `emit-computed-field`'s homogeneous-struct error, which would read as noise.
- **Residual gap:** if a type has both a field `k` *and* a local `k` in scope,
  the field still wins. That is the one case option B does not fix, and it needs
  an explicit spelling — see option D.

### C — Value-keyed-`get` types give up callable field access (mirrors `invoke`)

Make the rule symmetric with the one already documented for `invoke`: a type that
defines a value-keyed `get` treats **every** callable-form argument as a value,
and reads its own fields with `_get`/`.field`. `(m k)`, `(m "foo")`, `(m 'foo)`
all become lookups; `(_get m count)` is the field read.

- **Blast radius: 26 distinct source lines**, ~23 of them mechanical `_get`
  conversions inside `lib/hashmap.nuc`, plus `examples/get-dispatch-test.nuc`
  (whose entire point is documenting the current split, so it gets rewritten) and
  the corresponding paragraphs in `docs/special-forms.md`.
- This is the **principled** option: it removes the ambiguity rather than
  papering over it, and it makes one rule cover both `invoke` and `get` instead
  of two rules that differ for no user-visible reason. `context/conventions.md`
  already tells user `get` methods to use `_get` for their own fields; this makes
  that guidance load-bearing instead of advisory.
- It is a real breaking change, but only for types with a value-keyed `get` — of
  which the stdlib has exactly one.
- Note this *subsumes* B's residual gap: with field access off the table for such
  types, a field/local name collision cannot arise.

### D — `invoke` falls back to `get` (companion to either B or C)

`emit-invoke-with-callee`, on finding no `invoke` method, should retry the
resolution against the `get` generic before dying. Cost is roughly five lines.

This gives the language an unambiguous **always-a-value** spelling, `(invoke m k)`,
which is what B's residual field/local collision needs and what a reader needs
when the intent is not obvious from context. It also makes the error message
honest: today `(invoke m k)` on a `HashMap` says "no `invoke` method is defined
for this type" when a perfectly good `get` is sitting right there.

Symmetrically, `(get m 'k)` remains the always-a-field spelling. The pair reads
well: quote it to mean the name, `invoke` it to mean the value.

### F — Marked selectors: a field name must be written `'field`

The option that removes the ambiguity instead of arbitrating it. A selector is a
*name* only when written as one; a bare symbol is a variable reference, the same
as it is everywhere else in the language. `(m k)` looks up by the value of `k`,
`(m 'name)` reads the field.

**Selector position is currently the only place in Nucleus where a bare symbol is
not a variable reference.** That is the whole wart, and it is what makes the
reported bug not a corner case but the rule working as designed.

**The mark is `'field`.** It works today: `selector-literal-sym` already accepts
`(quote sym)`, and `(get s 'field)` is already documented. No reader work.

**`:field` is rejected — keywords are HashMap keys.** The reader does already lex
a leading-colon atom to a `NODE-KEYWORD` (`lib/reader.nuc:887`), and the compiler
already treats `NODE-KEYWORD` as a compile-time name for type spellings
(`src/type-mangle.nuc:165-174`) and declaration attributes
(`src/union-registry.nuc:1174`), so the machinery would have been nearly free.
But `lib/keyword.nuc`'s entire stated purpose is "ergonomic, cheap `HashMap`
keys" — an interned name with an integer-compare `Eq` and a cached hash. Claiming
`:field` for member access would make `(m :name)` irreducibly ambiguous between
*the field `name`* and *the keyword key `:name`* — and the collision lands
precisely on the type that motivated keywords in the first place. A mark for
field access must be a spelling that can never also be a key.

**The residual, and why it is acceptable.** `'field` has the same shape of
collision against a **symbol-keyed** map — a `(HashMap ptr V)` keyed on interned
symbol pointers would find `(m 'foo)` ambiguous. That is judged rare enough not to
pay for: a type that genuinely wants symbol keys should define its own `get` for
the key type, which out-ranks the blanket intrinsic at tier 0 and takes ownership
of member access on that type. That escape already exists and is already
documented.

**Measured cost — this is the objection.** Probing every field access that
reaches `emit-get-with-callee`'s symbol branch:

- **4,151 emit-time occurrences** compiling `src/nucleusc.nuc` (≈3,800 distinct
  source sites; the gap is generic instantiation re-emitting template bodies).
- **0** of them are currently quoted. Every single one is a bare symbol.
- 14,578 emit-time occurrences across `examples/` (inflated — `lib/` is re-emitted
  per example).
- For contrast, `_get` — the existing unambiguous spelling — has **49** static
  uses.

So this is a ~3,800-site mechanical rewrite of the compiler and stdlib, and it
**reverses a completed migration**: Stage 9 deliberately renamed `.` to `_get` and
moved ordinary code *to* head-position `(s field)` precisely because it is the
terser spelling. That history should be weighed, not ignored.

**It is automatable, and the location data exists.** `g-source-path` is a per-file
global swapped as each source-import is read (`StructDef.src-file` snapshots it,
`lib/reader.nuc:42` prints it), so a `--warn-bare-selector` mode can emit exact
`file:line: field 'x'` triples for every site. A structural rewriter then converts
them — the compiler is the only thing that knows which `(a b)` forms are field
accesses rather than calls, so compiler-emitted locations are what makes a
textual rewrite safe.

**Staged path** (the shape this repo already used for the Stage 10 Phase F
nullability flip):

1. `'field` is already accepted alongside bare symbols, so step 1 is already
   done — there is no new spelling to introduce.
2. Add `--warn-bare-selector`. Run it over `src/`, `lib/`, `examples/`; feed the
   triples to a structural rewriter; convert the tree. Still no semantic change,
   so the bootstrap stays byte-identical and the boot artifacts do not move.
3. Flip the default: a bare symbol in selector position is a variable reference.
   Now `(m k)` works, and so does every other case of this class.

**What this does and does not fix.** It fixes the reported bug and the entire
class, including the field/local name collision option B leaves open. It does
**not** retire `_get`: a user `get` method reading its own fields still needs the
bypass, because `(self 'cap)` inside `(defn get (self …) …)` still dispatches
into that same method. The "variable named like a special form" collision
(`(cond field)`) is also unaffected — that is a dispatch-order issue, not a
selector one.

### E — Do nothing but improve the diagnostic

If neither behavioral change is wanted, at minimum `emit-get-intrinsic`'s
"no field 'k' on struct 'X'" should, when `k` is a local binding and the struct
has a value-keyed `get`, add: *"'k' is a local binding here; a bare symbol in
selector position is always a field name — write `(invoke m k)` or `(m (as CStr k))`
to look up by value."* This is worth doing regardless of which option is chosen,
since the current message actively misleads: it names a struct the user was not
trying to access a field of.

## Recommendation

The options are not exclusive, and they differ mostly in how much of the class
they retire:

| | Fixes reported bug | Fixes the whole class | Sites changed |
|---|---|---|---|
| **B** field-first + value fallback | yes | no (field/local collision remains) | **0** |
| **C** value-keyed types drop field access | yes | for `get` types only | **26** |
| **D** `invoke` → `get` fallback | as an escape hatch | no | ~5 lines |
| **F** marked selectors (`'field`) | yes | **yes** | **~3,800** |

**F is the correct end state.** The user-facing rule it produces — *a bare symbol
is a variable, everywhere, with no exceptions* — is the one that needs no
caveats, no scope-sensitivity, and no "it depends whether the callee type has a
value-keyed `get`". B and C are both tiebreak rules for an ambiguity that F
deletes. Its cost is real and large, but it is mechanical, automatable from
compiler-emitted locations, and stageable so that no step is simultaneously
breaking and unverifiable.

**Sequence: D + B now, F as its own stage.** D and B together are ~zero-risk (D
is five lines; B is provably zero-blast-radius) and they fix the reported bug in
this stage without foreclosing anything — B's demotion rule is deleted wholesale
when F lands, and D's `invoke`→`get` fallback is wanted under F too. E's
diagnostic should land with them.

**C is the option to skip if F is on the roadmap.** It costs 26 lines of churn
and buys a rule that F immediately replaces with a better one. C is only worth
doing if F is being ruled out — in which case C + D is the strongest combination,
since it makes `get` and `invoke` behave alike.

## Touch points

- `src/nucleusc.nuc:3234` `selector-literal-sym` — classification
- `src/nucleusc.nuc:3418` `emit-get-with-callee` — the A/B split (B and C)
- `src/nucleusc.nuc:3491` `emit-invoke-with-callee` — the `get` fallback (D)
- `src/nucleusc.nuc:3528` `emit-callable-value` — routing precedence (C)
- `src/nucleusc.nuc:3322` `emit-get-intrinsic` — the diagnostic (E)
- `lib/hashmap.nuc` — 23 `_get` conversions (C only)
- `examples/get-dispatch-test.nuc`, `examples/hashmap-lit-test.nuc`
- `docs/special-forms.md` "Callable values" section
- `context/conventions.md` "Member access is head position" section

For F specifically:

- `lib/reader.nuc:42` `g-source-path` — the per-file location source the
  `--warn-bare-selector` rewriter consumes
- ~3,800 sites across `src/`, `lib/`, `examples/` — mechanical, script-driven

---

## As built (B + D + E)

Three changes, all in `src/nucleusc.nuc`. Bootstrap fixed point holds; the test
suite went 296 pass / 1 fail → **297 pass / 0 fail**, the recovered test being
`hashmap-lit-test` itself.

**Two new predicates**, beside `selector-literal-sym`:

- `callee-has-field (ct sym)` — mirrors `emit-get-intrinsic`'s own unwrapping
  (TY-PTR with a TY-STRUCT/TY-UNION elem, then `struct-field-index`) so the two
  can never disagree about what "names a field" means.
- `selector-shadowed-by-local (scope sym)` — **locals only**. Globals are
  deliberately excluded: every function lives in the global scope too, so
  accepting non-locals would demote `(sd name)` the moment any global named
  `name` existed. A global genuinely used as a key has the `invoke` spelling.

**B — the demotion** in `emit-get-with-callee`, before the A/B split. A bare
symbol demotes to a value selector when the callee provably has no such field and
the name is a local. `(= sym sel-node)` is the bare-vs-quoted discriminator —
`selector-literal-sym` returns the node itself for a bare symbol and the *inner*
node for `'sym` — so a quoted selector is never demoted.

Diagnostics needed no special handling: when Branch B then finds no method it
falls through to `emit-get-intrinsic`, which re-reads the still-symbol `sel-node`
and reports the same "no field" error. The design sketch's proposed extra gate
("only demote if the local's type resolves a `get`") turned out to be unnecessary
for that reason, and was dropped — the fallthrough preserves the message on its
own.

**D — the `invoke` → `get` fallback** in `emit-invoke-with-callee`, gated on
`generic-has-receiver-method` returning 0 for the `invoke` generic. That probe is
side-effect-free and tolerates a null generic, and gating on it leaves the
ordinary invoke path **completely untouched** — importantly its tier-2
untyped-literal widening, which `generic-resolve-nullable` does not implement.
Resolving through the nullable resolver on the primary path would have silently
regressed `(v 3)`.

**E — the diagnostic**, via a new `fmt-3s` call in `emit-get-intrinsic`. Fires
only when the missing field name is a local binding.

### Verification

- **Zero blast radius, measured not argued.** `bin/nucleusc` is the pre-change
  compiler (rebuilt from `boot/nucleusc.ll`), so emitting IR for every example
  with both binaries is a direct A/B: **135 byte-identical, 0 differing, 1 newly
  compiling** (`hashmap-lit-test`), 1 failing on both. That last is
  `examples/comb-shapes.nuc`, which fails identically on both with an unrelated
  pre-existing `as: lossy conversion from usize to i32` at line 36 and is not
  covered by the test suite.
- `make bootstrap` passes — stage1.ll == stage2.ll.
- The field/local collision case behaves as designed: with a `cap:CStr "cap"`
  local over a `(HashMap CStr i32)`, `(m cap)` reads the `cap` **field** (8) and
  `(invoke m cap)` looks up the **value** (42).
- A plain-struct typo with no shadowing local reports the unchanged message.

### Known limits (deliberate)

1. **A field name wins over a local of the same name.** `(m cap)` is the field.
   `(invoke m cap)` is the escape hatch. F removes this.
2. **Globals do not demote** — see above for why. Same escape hatch.
3. **`_get` is not retired**, and F would not retire it either: a user `get`
   method reading its own fields still needs the bypass, since `(self 'cap)`
   inside `(defn get (self …) …)` dispatches straight back into that method.
