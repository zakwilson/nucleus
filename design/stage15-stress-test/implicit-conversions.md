# Implicit conversions: one step, everywhere

*Stage 15 W9, items 42 and 47. Written 2026-08-15, as built.*

Two questions came out of W9 item 33's fix, and they look like one question until
you measure them:

1. **Does a built-in conversion chain into a user `defcast`?** (item 42 — a
   ruling)
2. **Where is the `defcast` registry consulted at all?** (item 47 — a defect,
   found while answering 1)

The answers are "no" and "at every typed slot, now". They pull in opposite
directions on purpose: the rule set stays deliberately small, and the places it
applies stop being an accident of which function a code path happened to call.

## 1. The ruling: conversions do not compose

**One conversion, built-in or user, never both.** A bare integer literal is
`i32`, so a rule registered `i64 → ptr` is *not* reached by `(take 0)`, and the
`i32 → i64` widening the compiler would happily do on its own does not run first
to make it reachable. `(take (as i64 0))` is the spelling that reaches it.

This is C++'s answer (at most one user-defined conversion in an implicit
sequence), and it is the recommendation item 42's row already carried. The
reasons, in the order they mattered:

- **Composition makes `lookup-cast-rule` order-sensitive.** With chaining, "is
  there a conversion from A to Z" becomes a search over paths, not a lookup of a
  pair. Two rules `i64 → ptr` and `i32 → CStr` plus built-in widening give
  `(f 0)` more than one derivation the moment a target is reachable both ways,
  and nothing in the registry ranks them. The registry is a flat `Vector` scanned
  in registration order (`lookup-cast-rule`, `src/nucleusc.nuc`) — "first
  match wins" is fine for exact pairs and indefensible for paths.
- **A rule from the narrow type is spellable.** Someone who wants `(take 0)` to
  work can write `(defcast i32 ptr …)`. Nothing is unreachable; the cost of the
  restriction is one explicit `as` at the call.
- **The restriction is already what the compiler does**, uniformly — measured in
  all five positions (argument, `as`, `let`/`with` init, explicit return,
  implicit return) before any of this was written. Ruling "no" is confirming an
  invariant rather than imposing one.

### The ruling only holds up if the compiler says so

The reason item 42 was filed rather than dismissed is that `defcast` is
documented as taking *any* pair and an integer literal is the most natural thing
to write, so "no composition" is indistinguishable, from the outside, from "your
rule was never registered". `examples/implicit-cast.nuc` carried a comment
claiming a cast fired for as long as the example existed; it never did, and only
item 33's new error revealed it.

So the refusal now names the rule that almost applied:

```
a.nuc:5: error: show-ptr: argument 1 has type i32, which does not match parameter type ptr
  note: a defcast rule converts i64 to ptr, but implicit conversions do not compose — write (as i64 …) on the operand to reach it
```

The note fires only on a **near miss** — a registered rule whose `to` is this
exact target and whose `from` is not this source. A mismatch against a target no
rule mentions gets no note, so a file containing one `defcast` does not grow a
note on every unrelated type error.

Mechanism: `note-cast-rule-near-miss` stages the text in `g-diag-note`, and
`die-at`/`report-at` render and clear it after the error line. This is the same
shape as `g-mono-context` and exists for the same reason — a note must *follow*
its error and `die-at` is `noreturn`, so the only way to append is to hand it the
text beforehand. (Nesting a second `fmt-*` call into each `die-at` argument would
also work — the helpers `alloca` their own buffers — but the five raising sites
have five different message shapes, and none should have to know the wording.)

The `as` position is the one where the bare diagnostic was actively *wrong*:

```
error: as: reinterpretation from i32 to ptr -- use unsafe/cast
```

`unsafe/cast` throws away exactly the safety the `defcast` was written to buy,
and `(as ptr (as i64 0))` was available the whole time.

## 2. The defect: the registry had two customers out of nine

`safe-coerce-val` was the only function that consulted `g-cast-rules`. Two paths
call it — the call-argument loop in `emit-call-with-args`, and `as`. Every other
typed slot calls `coerce-int-val` instead, which knew every *built-in*
conversion and nothing about the user's.

So a rule was refused **on its own exact pair** at:

| slot | before | after |
|---|---|---|
| call argument | ✅ | ✅ |
| `as` | ✅ | ✅ |
| `let` init | ❌ `let: init type mismatch for 'q'` | ✅ |
| `with` init | ❌ `with: init type mismatch for 'q'` | ✅ |
| explicit `return` | ❌ `return type mismatch — …` | ✅ |
| implicit return | ❌ | ✅ |
| `.set!` field store | ❌ | ✅ |
| `aset!` / array element | ❌ | ✅ |
| struct-literal field, union payload | ❌ | ✅ |

This is the reason item 42 *looked* like "unreachable from an integer literal":
the rule was unreachable from most of the language, literal or not.

### The fix is a chokepoint, not nine call sites

The last line of `coerce-int-val` (`src/abi.nuc`) — the single final
fallthrough, reached when no built-in conversion applies — now returns
`coerce-via-cast-rule`. Every typed slot already funnels through that function,
so all nine positions get the behaviour at once, and a tenth added later gets it
for free. Hand-wiring the argument position and forgetting the other eight is
precisely the defect being fixed; repeating the pattern nine times would have
been the same bug with a longer fuse.

Three properties make this safe rather than merely convenient:

- **Built-in first, user second.** `coerce-via-cast-rule` runs only where the
  function previously returned `null`, i.e. only where the caller was about to
  die. Nothing that compiled before can change meaning. This is also the order
  `docs/types.md` already stated ("built-in coercion always wins").
- **Only the final fallthrough.** The earlier `(return null)`s in
  `coerce-int-val` are deliberate refusals of a *specific* pair (a StrView into
  an unrelated by-value struct) rather than "no built-in applies", and they keep
  refusing.
- **`safe-coerce-val` did not get a second copy** — its inline rule branch was
  deleted, since it already falls through to `coerce-int-val`. The pairs it
  converts, the order it tries them in, and the IR it emits are unchanged; the
  argument path is byte-identical.

### Import order: the wall is not where a comment says it is

`lookup-cast-rule` needs `type-eq` (`src/generics.nuc`), and `coerce-int-val`
lives in `src/abi.nuc`, which is inlined *earlier* in the stream
(`nucleusc.nuc:1036` vs `1058`). `coerce-int-val`'s own W5d comment says a
forward reference like that "would not resolve when abi.nuc's bodies emit", and
spells out a `type-eq` rule inline to avoid one.

That reasoning no longer holds. `union-registry.nuc` (inlined at 1038) already
up-calls `intern-str` (defined at 3873), and this change up-calls
`coerce-via-cast-rule` (defined at ~3220) from `abi.nuc` — both compiled by the
**committed** boot compiler on the first try. A forward up-call into
`nucleusc.nuc` resolves; the signature prescan registers it long before any body
emits. The inline `type-eq` rule in W5d is still correct code, but "it would not
resolve" is not the reason to keep it, and should not be cited as one for the
next such decision. See `context/conventions.md`.

## Measurement

- 697 tests pass (6 new, `run_w9_defcast_reach`), 0 fail.
- Corpus sweep, committed boot vs. fixed compiler over 365 programs: **205
  identical, 0 differing, 0 new errors, 0 changed error texts.** Purely additive
  — the only programs whose behaviour changes are ones the baseline rejected.
- `make bootstrap` converges; ABI, layout and 69 generated headers unchanged.

## What is deliberately not done

- **No transitive `defcast` chaining** (`A → B` then `B → C`). Same argument as
  the built-in composition above, one step further out.
- **The note is best-effort, the behaviour is uniform.** The near-miss note is
  wired at the five positions that hold both types and phrase the failure in
  user terms; the *rule lookup* is at the chokepoint and therefore everywhere.
  A field-store mismatch gets the fix without the hint, which is the right way
  round — the note is an explanation, not a mechanism.
