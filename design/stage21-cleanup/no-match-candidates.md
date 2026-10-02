# No-match diagnostics: candidates and reasons

Built 2026-10-01. Prompted by `charge.nuc`: `(-> &options (_ cur-idx))` with
`cur-idx:i32` failed with only

```
no matching method for overloaded 'invoke' with argument types (&(Vector i32), i32)
```

which named neither `Vector`'s `invoke` nor its `i:usize`. And `(options i)`
on a by-value `Vector` said `get: computed field access requires a homogeneous
struct`, which is about a fallback, not the mistake.

## 1. Candidate notes (`src/generics.nuc`, `candidate-notes`)

One site raises every overload no-match: `generic-resolve`'s final `die-at`.
It now appends one note per method that takes the first argument
(`method-receiver-fit`):

- **Concrete method:** `params-accept-args` on the receiver, so the Stage 17
  implicit address-of counts ([borrow-conventions.md](../stage17-native-strings/borrow-conventions.md) §3.4).
- **Template:** the receiver pattern unifies with the argument type
  (`template-receiver-binds`, also used by `generic-has-receiver-method`).

Each note gives the definition site, the signature, and a reason per argument
that does not fit. A template shows its signature with types substituted when
every type variable is bound, otherwise as written. The list is capped at
eight.

**Reasons** (`arg-mismatch-reason`) are computed only for arguments
`arg-adapts` refuses, so they agree with tier 2:

| case | reason |
|---|---|
| int → int, narrower | narrow with `unsafe/cast` |
| int → int, sign differs | `(as T …)` |
| float → narrower float | narrow with `unsafe/cast` |
| int ↔ float | `unsafe/cast` (what `as` routes it to) |
| struct value → `&S` | pass `&name` (a binding only) |
| anything else | `A is not P` |

Arity is reported first, since nothing else applies to the wrong count.

**Template binding mirrors `generic-method-bind-adapt`'s pass 1**: literals do
not bind a type variable. If the receiver is a literal, its binding from the
fit is discarded. Without this, `(wrap 1 v)` blamed `v` against
`&(Vector i32)` when `T` is really `ui8`. A by-value struct argument may bind as
its `&` form, so the reason can tell the user to take its address.

**Concrete address-of plus widening.** The implicit address-of runs in tier 0,
which does not widen, and tier 2 does not take addresses. So `(scale p w)`
with `p:Pt`, `w:i32` against `(scale &Pt i64)` fails even though each argument
fits alone. The note names the widened argument: `must be exactly i64 while
argument 1 is passed by address -- use (as i64 ...), or pass &p`.

**No method takes the first argument.** Notes appear only if one method would
take `&` of it (`(count options)` on a by-value `Vector`). Otherwise the
message is unchanged: a list of every method of a name is noise.

## 2. By-value `(v i)` (`src/nucleusc.nuc`, `invoke-address-hint`)

`emit-callable-value` routes to `invoke` only when a method's receiver
unifies with the callee's type. A by-value `(Vector i32)` does not unify with
`&(Vector T)`, so the call falls through to the `get` intrinsic. The hint is
raised where that fallback fails (heterogeneous struct, non-symbol selector),
not in the router: a homogeneous struct that also defines `invoke` on `&S`
still reads a computed field by value
(`tests/fixtures/callable-homogeneous-by-value.nuc`).

## 3. Not done: implicit address-of for templates and `(v i)`

Concrete methods take a by-value binding for `&S` (§3.4 above); templates and
callable routing do not. That is why `(count options)` and `(options i)` need
an explicit `&` while a concrete `(f p)` does not. Extending the lvalue-only
rule to tier 1/2 template binding and to `generic-has-receiver-method` would
make both compile. That is a language change and was left as a decision; this
item only makes the errors say what to write.

## Tests

`tests/manifest/diagnostics.sexp`: `nomatch-invoke-sign`, `nomatch-overloads`,
`nomatch-addr-widen`, `nomatch-template-addr`, `nomatch-by-ref-receiver`,
`callable-by-value-invoke`, `callable-homogeneous-by-value` (accept).
