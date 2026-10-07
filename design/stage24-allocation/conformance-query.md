# Stage 24 — asking about conformance at expansion time

**Status: CQ-1…CQ-4 built 2026-10-07.** §8 records how the build differs
from the analysis below. This answers the question raised in
[overview.md](overview.md) §6: what would have to change for a macro to ask
whether a type conforms to a protocol?

Probes ran against `bin/nucleusc` at `26ae536`. The probe sources are not kept.

## 1. The plumbing already exists; the form does not

Stage 22 ED-4.2 gave macro bodies `struct-fields` and `type-name`
([docs/macros.md](../../docs/macros.md#struct-fields-and-type-name--a-structs-shape-at-expansion-time)).
A conformance query can take the same path:

- **The form.** The form is special only inside a JIT module
  (`emit-macro-type-query`, `src/nucleusc.nuc:2862`). It compiles to a call to a
  function the compiler binary exports (`nucleus_struct_fields`).
- **Resolution.** The JIT runs in the middle of expansion, so the type operand
  resolves in the caller's file. `macro-struct-arg` resolves it with
  `parse-type-from-node`, and that also stamps a template instance such as
  `(Vector i32)`.
- **The check.** The answer comes from the test `generic-constraints-ok`
  (`src/generics.nuc:2882`) already applies to a `:where`: a blanket
  conformance, a nominal `conformance-lookup`, or a closure conformance from
  `derive-closure-conformance`. Moving that test into one function,
  `type-satisfies?`, used by both the query and dispatch, keeps a macro's answer
  identical to dispatch's.

The new form is `(conforms? t P)`, which returns `bool`. It is a fourth
reserved head beside the existing ones. Under the `node-type`/`emit-node`
lockstep
([context/conventions.md](../../context/conventions.md)), it has to be added
at `src/nucleusc.nuc:13694` (emit), `src/generics.nuc:6681` (`node-type`), and
in the reserved-name lists at `src/generics.nuc:3530` and
`src/nucleusc.nuc:20831`.

Adding the form alone would give wrong answers. §2–§5 cover the four problems,
in order of importance.

## 2. Conformance depends on source order

`extend` is recorded when the emit loop reaches it, not during a prescan.
Measured: `(loud &p)`, where `loud` is constrained `:where (Shout T)`, fails with
`arguments do not satisfy the required protocol constraint` when
`(extend Pt Shout)` appears *below* the call. Moving the `extend` above the call
fixes it. Dispatch has the same problem today.

A query would be worse than dispatch. Dispatch fails with an error. A query
answers "no" with nothing reported, and the macro then takes its other branch.
In `new`, that branch builds the object as a struct literal and skips `init`.

The fix has three parts:

- **CQ-1a. Record written `extend`s in a prescan.** Only the (type, protocol)
  pair is recorded early. The check that the methods exist stays where it is now.
  The prescan runs after `prescan-struct-names` and `prescan-protocols`, so the
  struct and protocol registries an `extend` resolves against are already
  filled. This also fixes the dispatch bug.
- **Stamped generic bodies are already safe.** `monomorphize` queues stamped
  bodies, and they are emitted after the top-level loop, which
  `check-generic-templates`' comment states. So they already see every written
  `extend`.
- **CQ-1b. Make a "no" answer stable.** An `extend` produced by an expansion,
  such as `derive-edn` or `derive-enc`, exists only once that expansion is
  spliced. No prescan can see it. Instead, record each pair the query answers
  "no" to. If that pair conforms later, refuse it with a located error naming
  both places, for example:

  ```
  file:30: error: Pt conforms to Init here
    note: file:12: conforms? answered no for (Pt, Init) before this
  ```

  A "yes" is always stable, because a conformance is never removed. This turns
  the remaining silent wrong answer into a compile error.

## 3. A type variable reaches the query unbound in one pass

There are two passes over a generic body, and they behave differently:

- **The stamp pass already works.** `monomorphize-form` substitutes the bound
  types into the body *before* emitting it (`subst-tyvars-node`). A macro in the
  body therefore receives `Pt`, not `T`. Measured: `(field-count T)` inside
  `(defn nfields (v:&(Vector T)) …)` returns 2 for `(Vector Pt)`.
- **The abstract check does not.** The A2 check (`check-generic-templates` →
  `gcheck`) expands macros in the *template* body at `src/generics.nuc:3634`,
  where `T` is unbound. Measured: the same macro in
  `(defn nfields (x:T :where (Shout T)) …)` fails with
  `unknown type: T — not defined anywhere in this compilation unit`.

  The parameter spelling matters. `x:&T` counts as a nested type variable, so A2
  skips the template and the bug does not show (`method-has-nested-tyvar`). That
  is why the `(Vector T)` probe above passed. **`struct-fields` and `type-name`
  have this bug today.** `derive-edn` has avoided it only because it is not
  called on a bare type variable.

The fix is **CQ-2: A2 skips a macro that asks about types.** Set a flag on
`MacroDef` when its body is compiled, if the body uses `struct-fields`,
`type-name` or `conforms?`. `gcheck` then returns null for a call to that macro,
deferring it to stamp time as it already does for `macrolet`. The flag is
static, so this needs no expansion-time abort or recovery.

Rejected alternative: answer a query on `T` from the template's `:where`. A
stated constraint can answer "yes". Only the concrete type can answer "no", so
this would still need the deferral.

## 4. The protocol is resolved in the wrong file

- **The type operand** belongs to the caller and resolves in the caller's file.
  That is correct.
- **The protocol operand** belongs to the macro's author. A quoted `'Init`
  evaluated during expansion would also resolve in the *caller's* file. Two
  things go wrong there: the protocol may not be reachable from the caller, or
  the caller may have its own unrelated `Init`. Quasiquote resolution does not
  help here (Stage 23 AN-4), because it rewrites names in template *data*, and
  this operand is code in the macro body.

The fix is **CQ-3: take the protocol operand as unevaluated syntax.** Resolve it
when the macro body is compiled, against the macro's own file, through
`protocol-canon-name`. The canonical name is then built into the JIT code. A
computed protocol is not needed for `new`/`make`. If it is wanted later, it can
be accepted only when fully qualified.

## 5. Parametric protocols

`(conforms? t (InitFrom StrView))` has to compare the protocol's arguments as
well as its name. They are recorded in the conformance (`conformance-args`), and
the parametric-`:where` path already compares them. The literal-operand rule
from §4 covers the arguments too: they resolve in the macro's file, with a
parameter of the macro unquoted (`(InitFrom ~v)`) where it is the caller's type.
This is **CQ-4**.

## 6. What this changes in overview.md

With CQ-1 through CQ-3, `new` can be a library macro. It chooses between `init`
and a struct literal at expansion time, using `(conforms? T Init)` and its
siblings.

`make` cannot be a library macro, because the name belongs to the `defunion`
special form. There are two ways out:

- the special form hands every non-union `T` to a library macro;
- the by-value form takes another name.

Either way, Q2's "compiler form" premise no longer holds. The ruling becomes a
choice between macros plus `conforms?` (CQ-1…CQ-4, smaller and reusable) and two
compiler forms (AL-3 as written).

## 7. Phases

- **CQ-1.** Prescan `extend` (1a) and refuse a later conformance to a pair the
  query answered "no" to (1b). 1a fixes a live dispatch bug and is worth doing
  even if CQ-3 is never built.
- **CQ-2.** A2 skips macros that ask about types. This fixes the live
  `struct-fields`/`type-name` bug.
- **CQ-3.** The `conforms?` form, with its protocol operand resolved in the
  macro's file, and `type-satisfies?` shared with dispatch.
- **CQ-4.** Parametric protocol operands.

## 8. As built (2026-10-07)

The form is documented in
[docs/macros.md](../../docs/macros.md#conforms--asking-about-a-protocol-at-expansion-time).
Tests: `tests/suite-s24.nuc` (`s24-conforms`) and the `s24-*` rows of
`tests/manifest/diagnostics.edn`.

- **CQ-1a is a promise, not an early record.** `prescan-extends` records each
  top-level `(extend Sym P …)` as a `ConformancePromise`, holding its file's
  name environment. The keys are resolved lazily, at the first lookup that
  misses, because an imported file's protocols are not registered during the
  prescan. A promise is redeemed only after emission begins
  (`g-promises-open`). Redeeming records the conformance and its known
  supers, marked `promised`. `verify-conformance-params` treats a promised
  record as not yet checked, so the `extend` still checks the methods when
  emission reaches it.
- **Who redeems.** `conformance-known` (lookup, then redeem) serves
  `type-satisfies?`, which `generic-constraints-ok` and `conforms?` both call,
  and the parametric path in `recover-one-constraint`. `conformance-lookup`
  itself is unchanged. `Drop`-ness and the other nominal checks therefore still
  see a conformance only once it is recorded.
- **Not promised:** a template subject, and protocol-on-protocol inheritance
  edges. A redemption matches a promise for a sub-protocol only when the
  inheritance edge is already recorded. CQ-1b covers both cases: the
  conformance that arrives later is refused, not silently missed.
- **CQ-1b also covers `Clone`.** The analysis said a yes is always stable. A
  blanket `Clone` yes is not: it holds only while the type is not `Drop`. So a
  `Clone` yes for a struct records a no for `(type, Drop)`, and the note says
  which question it came from.
- **CQ-2 covers `valid-walk` too.** It expands macros the same way `gcheck`
  does. The flag (`MacroDef.type-query`) is set by a syntactic walk of the
  `defmacro` form, before its body is compiled.
- **CQ-3's operand travels as data.** `emit-conforms` builds one quoted list
  `(protocol-key arg…)`. An argument resolved in the macro's file is a
  *string* node holding its canonical spelling. A `~v` argument is the caller's
  node, resolved by `nucleus_conforms` at expansion. A blanket protocol name
  (`Any`, `Struct`) is accepted as written.
- **AL-0a was hit again** while probing: a protocol method named `init` in user
  code breaks `for`. The tests use `setup`.
