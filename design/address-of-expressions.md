# Address-of any expression

**Status:** investigated 2026-10-15; Q1–Q3 ruled 2026-10-15 (§4; Q3 deferred); built 2026-10-15 (§7).
No stage assigned.

## 1. The problem

`charge.nuc` (the GTK demo) stopped compiling after cf1a6de. Two separate limits
meet there:

1. **The implicit address-of lost `str`.** `(string-as-cstr (str item))` passes a
   `String` value to a `&String` parameter. The implicit address-of
   ([borrow-conventions.md](stage17-native-strings/borrow-conventions.md) §3.4)
   takes a value's address only when `Val.lvalue-sym` is set, and only
   `emit-symbol-ref-bound` sets it. The old `str` ended with the bare symbol
   `~s`, which counted. The new one ends with `(deref ~s)` (it has to
   `alloca`, because a `String` has no zero value since AL-5), which doesn't.
2. **The explicit fix is refused.** Writing `&(str item)`, or `ref` as a step
   in `->`, dies with `ref: target must be symbol`. 1-argument `ref` accepts
   only a bare binding name.

§3.4 meant the explicit form to be the escape hatch: it keeps temporaries out of
the implicit form so that "the `(addr-of …)` the author must write is honest
about what is happening". But the explicit form could never take a temporary,
so a call result had no route at all. This document lifts limit 2.

Limit 1 stays an error (ruled 2026-10-15). No implicit extension (Q3, deferred): when something wants a ref, the idiom is to pass one, as in
`(string-as-cstr &(str item))`. `str` keeps its `(deref ~s)` tail.

## 2. Today

| Site | What it does with `(ref X)` |
|---|---|
| `emit-ref` (`src/nucleusc.nuc`) | 2 args → `emit-field-addr`. 1 arg: X must be `NODE-SYM`, then `binding-address-val`. |
| `node-type-ref` (`src/generics.nuc`) | Lockstep mirror; returns null for a non-symbol X. |
| `emit-lvalue-receiver` | The 2-argument receiver: a by-value binding gives its slot; a temporary struct is refused ("bind it to a name first"). |
| `ref-cell-is-address` | Tells `&x` from a reader-fused `name:(ref T)` at a callable-value argument; a list X reads as a **type**. |
| `fn-rewrite-captures` | Rewrites `&cap` for a captured symbol only; other operands go through the generic rewrite. |
| `gcheck` TC-4 | Skips every `ref`/`ptr` head in a check-only generic body (it may be a type spelling). |

Every local slot, including `alloca` and `let`, goes to `g-entry-stream`, so a
slot is valid for the whole function. A temporary's slot can therefore outlive
the expression that made it at no extra cost, the same as a `let` slot.

## 3. Proposal: places and values

Follow Rust's split. The operand of 1-argument `ref` is either a **place**,
whose address already exists, or a **value**, which gets a temporary.

**Places**, classified by syntax after macro expansion:

| Operand | Address |
|---|---|
| binding `x` | `binding-address-val`, as today |
| `(deref p)` | `p` itself (with `require-derefable`), at `p`'s pointee type, as `&T` |
| `(s 'f)`, `(_get s 'f)`, `s.f` with a literal selector that names a field | `emit-field-addr`, the 2-argument form, recursively for `((a 'b) 'c)` |
| `(aref p i)` | the element GEP that `aref` already computes |

**Values** are everything else: calls, literals, `let`/`do`/`if`/`cond`, and so
any macro that expands to one (`str`, `str-alloc`). The operand is emitted,
stored into a fresh entry-block slot, and its address returned. Do this by
defining a hidden `Sym` in the **current** scope and reusing
`binding-address-val`, so the escape rule keeps one owner:

- the slot address is frame-tainted with the current scope, so `return`ing it
  is rejected, as for `&local`;
- the hidden sym adopts the stored value's taint through `sym-adopt-taint` /
  `box-taint-source`, as `emit-let` does, so a borrowing box or a `with`
  resource can't be laundered through a temporary.

A value temporary is never dropped. That matches a `let` value binding, which
isn't dropped either; only `with` drops. `str`'s heap buffer leaks either way,
as it did before cf1a6de.

With this, both `charge.nuc` sites compile as `(string-as-cstr &(str item))` and
`(-> … (str "Selected: " _ " mA") ref string-as-cstr)`.

## 4. Decisions (ruled 2026-10-15)

- **Q1. Indexing and custom `get` look like places but are calls.**
  `&(v 0)` on a `Vector` routes to `invoke` and returns a copy, so a temporary
  would give the address of the copy, and a write through it would go nowhere
  (borrow-conventions.md §3.3). **Ruled: refuse.** A non-function head that
  routes to `invoke` or a custom `get` is not a place and is not
  materialized. The note says to bind the element first. A literal field
  selector on a plain struct stays a place.
- **Q2. A temporary receiver for the 2-argument form.** **Ruled: allow.**
  `(ref (mk) 'f)` materializes `(mk)` and takes the field's address, the same
  as `&((mk) 'f)`. `_get` and `set!` keep refusing a temporary receiver,
  because a field store into a temporary is lost.
- **Q3. The implicit form.** **Ruled: no extension; deferred.** The implicit
  address-of stays binding-reads only: a field, an `aref` element and a
  `deref` are not taken implicitly, and `(show (s 'p))` against `&P` stays the
  ordinary argument-type error. When something wants a ref, pass one. To be
  revisited if this proves a mistake; the extension would record the address
  at those emitters (`Val.lvalue-addr`) rather than relax the coercion rule.

**Type spelling vs value** (a required change, not a question).
`(ref (Vector i32))` is a type spelling in a type slot. `ref-cell-is-address`
treats every list operand as a type. It must classify instead: a list whose
head is a type application or a pointer-kind head is a type, anything else is a
value. Otherwise `(cb &(f x))` on a callable value gets the `name:(ref T)` cast
diagnostic.

## 5. Sites to change

1. `emit-ref`: classify the operand; place → address, value → hidden-sym slot,
   call-shaped non-place (Q1) → refused. Factor the classifier as
   `emit-place-address`.
2. `node-type-ref`: same classification. Places type as today. A value types
   as `(ref (node-type X))`. The node-type ↔ emit-node lockstep in
   `context/conventions.md` applies.
3. `ref-cell-is-address`: type spelling vs value (§4).
4. `fn-rewrite-captures`: no change for symbols. Confirm a list operand
   containing a capture goes through the generic rewrite (`&(cap 'f)` → field
   of the env field).
5. `gcheck` TC-4: keep skipping type spellings, but check a value operand, so
   a generic body gets checked inside `&(…)`.
6. Q2: `emit-lvalue-receiver` materializes instead of dying, for `ref` only.
   `_get`/`set!` callers keep the refusal, since a field store into a
   temporary is lost.
7. Docs: `docs/special-forms.md` (`ref` row), `docs/builtins.md` (`ref` row),
   the `&` sigil note in `docs/types.md`.

## 6. Tests and gates

Positives: one per place kind, a call result, a macro result (`&(str 1)`),
`ref` as a `->` step, `&((mk) 'f)`, `(ref (mk) 'f)`. Negatives: returning `&(f)` (escape), `&(v 0)` on
a `Vector` (Q1), a taint carried through a temporary, `(cb &(Vector i32))`,
`(string-as-cstr (str 1))` and a field passed to a `&P` parameter (Q3), `_get`/`set!` on a temporary
receiver.

The compiler uses none of the new forms, so the change should be inert under
self-compilation: `make bootstrap` should be byte-identical without a boot
refresh, and there is no `.nuch` or type-system churn. Gates: `make test`,
`make bootstrap`, `make check-headers`.

## 7. As built (2026-10-15)

Built as §3–§5 with Q3 dropped: no `Val.lvalue-addr`, and the argument
coercion and `params-accept-args` are untouched. `make test` 1463 passed, 5
failed (the five known `suite-target` datalayout units under Debian's LLVM,
the same five as the pre-change tree's 1454/5); `make bootstrap` reaches
`stage1.ll == stage2.ll` with no boot refresh; `make check-headers` passes (93
headers). Every `examples/*.nuc` emits byte-identical IR to the pre-change
compiler except the new `address-of-expressions.nuc`, which it rejected.

**Sites.**

- `emit-ref` (`src/nucleusc.nuc`) expands the operand's head macros
  (`ref-operand-expand`, the same `find-macro` + `desugar` step `emit-list`
  takes) and emits the expanded node, so a macro is expanded once. A symbol
  goes to `emit-binding-address`, the old 1-argument body. A list goes to
  `emit-place-address`; null from it means a value, which
  `emit-ref-temporary` stores.
- `emit-place-address` handles `(deref p)`, `(aref p i)` (its own GEP, without
  the load), `(_get s 'f)`, `(get s 'f)`, a callable-value symbol head, and a
  non-symbol head that is not a template literal.
- `emit-callable-place` routes on `node-type` of the receiver, before emitting
  anything. `callable-place-route` (`src/generics.nuc`) mirrors
  `emit-callable-value`: a `TY-FN` callee is a value (an indirect call), a
  literal selector naming a field is a place, and `invoke`, a `BoxedFn`, a
  custom `get` or a computed selector is refused (Q1). When `node-type` cannot
  type the receiver, it is emitted and routed on its Val. A value route then
  finishes through `emit-callable-value` / `emit-get-with-callee` with that Val,
  so the receiver is emitted once.
- `callable-value-head-sym` asks the question `emit-dispatch` asks of a symbol
  head: not a special form (except a locally bound `fn`/`vfn`/`mfn`/`cfn`), and
  the `BK-GLOBAL` row hit is not a `defn`/`extern`.
- The 2-argument `ref` and the field place share `emit-place-receiver` and
  `emit-member-address`, the two halves of the old `emit-field-addr`. The
  receiver is a struct binding's slot, a struct-typed place's address (so
  `&((a 'b) 'c)` reaches `a`'s own storage), a pointer value, or a temporary
  (Q2). `emit-lvalue-receiver` now serves only the `.set!` path, which keeps
  its refusal.
- `emit-ref-temporary` stores the coerced value in an entry-block `%ref.tmp.N`
  slot. It defines a hidden `#ref-tmp` `Sym` in the current scope with
  `sym-adopt-taint`, and returns `binding-address-val` of it. `maybe-box-into-slot`
  is not called, because the slot's type is the value's own. It refuses a void
  value and a scope with no parent (no function to hold the slot).
- `node-type-ref` splits the same way through `node-type-ref-operand`. A
  macro-headed operand is null (emit's type stands), a refused form is null,
  and a value is `(ref (node-type X))`. `node-type-field-addr` now takes the
  receiver and selector nodes.
- `ref-cell-is-address` and `gcheck` TC-4 share `ref-operand-type-spelling?`:
  a struct or union template application, or a `ptr`/`ref`/`raw`/`fn`/`dyn`/`array`
  head.
- `fn-rewrite-captures` needed no change. `&(cap 'f)` rewrites to
  `&((_get self 'cap) 'f)` (vfn/mfn) or `&((deref (_get self 'cap)) 'f)` (cfn),
  both places. The example checks that a cfn's write lands in the captured local.

**Deviations.**

1. A pointer-typed temporary is frame-tainted explicitly. `binding-address-val`
   exempts a `TY-PTR` binding, so without this `(return &(f))` for an `f`
   returning a pointer would have passed. Nothing can load the hidden slot, so
   the exemption's reason does not apply.
2. A `BoxedFn` or closure call (`invoke`) under `&` is refused, following Q1
   literally, although it is a call rather than something that looks like a
   place. A function-pointer callee materializes.
3. `(ref T)` with `array` or `fn` heads stays a type at a callable value's
   argument, so `(cb &(array …))` and `(cb &(fn …))` get the annotation
   diagnostic. An array literal is already a pointer.
4. The pre-existing s16 unit that pinned `(ref (mk 1) 'x)`'s refusal now pins
   the frame escape when the result is returned (Q2).

**Tests.** `examples/address-of-expressions.nuc` covers every place kind
(including nested, through a pointer, `_get` and `get`), call/literal/block/macro
values, both temporary-receiver spellings, a callable-value argument, closures,
a generic body, and the two `charge.nuc` shapes. Manifest rows `aoe-*` in
`tests/manifest/diagnostics.edn` cover the negatives: returning a temporary, a
`with` taint kept through a temporary, `&(&v 0)` (Q1), `(rd &(Vector i32))`,
`(string-as-cstr (str 1))` and `(show (s 'p))` staying argument-type errors,
`(set! (_get (mk 1) 'x) 5)`, and a generic body checked inside `&(…)`.
