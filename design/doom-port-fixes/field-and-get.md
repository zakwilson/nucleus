# `field` reads fields; `get` is only a lookup (ISSUE-053)

Ruling (2026-11-03): overloading `get` for both field access and `Assoc`
lookups was a mistake, because every associative type is also a struct. Use
`field` for field access. A struct in head position is field access unless
`invoke` is defined to do something else.

## What was wrong

`get` was a special head with a Struct-blanket intrinsic. A user `get` method
for the receiver ran first, matched without widening
(`generic-resolve-nullable`); on a miss the call fell to the field intrinsic.
`(get &m 1)` on a `(HashMap i64 V)` missed (the literal is `i32`) and became a
positional read of field 1, "computed field access requires a homogeneous
struct". `contains?`, an ordinary function, took the same literal.

## The change

- `field` is a reserved special form, `(field s 'f)` / `(field s sel)`:
  `emit-field` → `emit-field-intrinsic`, typed by `field-access-type`. It never
  consults a method. It is a place for `set!` and `&`.
- `get` is not special: a call resolves through the ordinary generic path,
  tier-2 widening included. `die-if-get-reads-field` turns `get` on a struct no
  `get` method takes into an error that names `field`.
- Head position (`emit-callable-value`, `callable-value-type`): a literal
  selector naming a field → field; an `invoke` that takes the receiver →
  invoke; a struct → field. The custom-`get` step and `invoke`'s fallback to
  `get` are gone, so `HashMap` and `ConstMap` define `invoke` as `get` to keep
  `(m k)`.
- `callable-value-type` gained the literal-field step it lacked, so the type
  pass now follows the emitter's order exactly.
- `(set! (get m k) v)` is no longer a place; `(set! (m k) v)` is.

Messages from the field intrinsic say `field:` instead of `get:`.

## Migration

`scripts/doom-port/get-field-sweep.nuc` rewrote `(get X 'f)` to `(field X 'f)`
(122 sites in tests and examples, inside test strings too; none in `src/` or
`lib/`, so the boot compiler is unaffected). `examples/callable.nuc`'s `get`
override became an `invoke` taking a `&Node` selector.

`_get`, the literal-only spelling, still exists. Retiring it in favour of
`field` needs a boot step, since `lib/` uses it.
