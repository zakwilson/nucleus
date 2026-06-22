# Error Handling (Stage 10)

Recoverable errors are ordinary return values (`design/stage10/errors.md`). A
fallible function returns `(Result T Err)`, written with the sugar `!T`. The
caller must `match`, `try`, or `unwrap` before using the value. The
unrecoverable tier is unchanged: `die`/`die-at` still abort.

## `Err`, `deferror`, and `!T`

**`Err`** is a distinct builtin scalar type represented as `i32` (C-legible),
distinguished from a plain `i32` so the error machinery can key on it. Id `0`
is reserved ("no error"); real ids are dense from `1`.

**`deferror`** defines an error value and registers its name + message:

```lisp
(deferror config-missing "config file not found")
```

`config-missing` becomes a compile-time `Err` constant. The name is the stable
contract; the id is a per-build representation (assigned in definition order,
capped at 4095). Names are program-global. `.nuch` headers export `deferror`
verbatim; importers re-register and get their own dense ids.

**The `!` type sugar** (recognized only in type positions, so no clash with
`!=`):

| Spelling | Expansion | Reading |
|---|---|---|
| `!T`  | `(Result T Err)`           | fallible value — `T` as written (`!i64` is `(Result i64 Err)`) |
| `!?T` | `(Result (Maybe T) Err)`   | error, or none, or value |
| `?!T` | `(Maybe (Result T Err))`   | a fallible result that may be absent (value-`Maybe` over a Result) |

After the Phase F flip `?` is uniform `(Maybe T)` (no `(ref …)` injection), so
`?` and `!` compose without asymmetry — both take their payload as written
(`!?i64` is `(Result (Maybe i64) Err)`; `?ptr:T` is the niche-encoded
nullable pointer). The
`(Result T E)` template now lives in the prelude, always available. Because the
toplevel signature prescan now resolves imported (prelude) types, `name:!Config`
parses in ordinary signatures — which is the point of the sugar, since
`name:(Result Config Err)` does not parse (parenthesized type in a colon
position). `!` over a parenthesized payload has no sugar; write
`(Result (ref FILE) Err)` longhand.

## Constructing and eliminating `!T`

**Construction.** In `return` position (and the implicit-return tail) of a
function declared `!T`, bare `(ok v)` / `(err E)` resolve against the return
type (the union target-typing rule). **Reading rule:** `(err E)` means "give up
unless a bound handler repairs"; `(err! E)` means "give up unconditionally" —
it bypasses the handler chain and returns the error value. Use `err!` when you
want an unconditional error return regardless of any bound handlers. Elsewhere
(non-return positions, custom `(Result T MyErrStruct)` types), use
`(make (Result T Err) ok v)`; stored Results are plain data with no handler
machinery.

**Elimination.**

| Form | Meaning |
|---|---|
| `match` | the eliminator — `((ok v) …)` / `((err e) …)` arms |
| `(try r)` | propagation macro (`lib/error.nuc`, needs `(import-use error)`): yields the `ok` value, or re-returns the error via `err!` from the enclosing `!T` function |
| `(unwrap r)` | the `ok` payload, or — on `err` — print `err-name`/`err-message` and abort (needs `printf` in scope for the message) |
| `(unwrap-or r d)` | the `ok` payload, or `d` (evaluated only on the `err` arm) |
| `(err-name e)` / `(err-message e)` | the descriptor strings for an `Err` value |

```lisp
(import-use "stdio.h")
(import-use error)
(deferror parse-failed "could not parse value")

(defn checked:!i64 (n:i64)
  (when (< n (cast i64 0)) (return (err parse-failed)))
  (return (ok n)))

(defn doubled:!i64 (n:i64)
  (let (v:i64 (try (checked n)))          ; propagate on err
    (return (ok (* v (cast i64 2))))))

(match (checked x)
  ((ok v)  ...)
  ((err e) (printf "%s: %s\n" (err-name e) (err-message e))))
```

## C layout of `!T`

The representation depends on the payload:

- `!SomeStruct`, `!i64`, `!f32`, etc. (non-pointer payload) — the tagged
  struct `{i32 tag; union payload}` plus the `Err` id constants as an enum.
  Fully legible and constructible from C. `sizeof(!T) == sizeof(Result.T.Err)`.
- `!ptr:T` (`(Result (ref T) Err)` over a typed pointer, rule 3 niche layout)
  — a bare `T*` with the ERR_PTR convention: `ok` values are the pointer
  directly; `err` values occupy the top-page range
  `[ptrtoint(-4095), ptrtoint(-1)]` (ids 1–4095). C code that understands the
  ERR_PTR convention can consume it directly. `sizeof(!ptr:T) == sizeof(T*)`.
  Use `&repr tagged` on the `defunion` to opt out and force the struct layout
  when a C consumer needs it unconditionally (see [Niche layout and `&repr`](structs-unions.md#niche-layout-and-repr-stage-10-c4)).

Nothing propagates across a function boundary by a mechanism C doesn't
understand.

## Handler-aware `err` and `with-handler` (E3)

When `(import-use error)` is in scope, returning `(err E)` from a `!T` function
consults the dynamically-bound handler chain before returning the error value. A
matching handler can **repair** the fault: the function returns `(ok v)` instead
of the error. `(err! E)` always bypasses the chain.

**Where the check fires.** Only at `(return (err E))` and the implicit-return
tail of a function whose declared return type is `!T` (i.e. `(Result T Err)`
with the builtin `Err` as the error arm). A stored `Result`, an `(err …)` in
any non-return position, or a custom `(Result T MyErrStruct)` type are plain
values — no handler machinery applies.

**`(err E detail)`.** An optional second argument of type `ptr` passes a
transient context pointer to the handler. It is borrowed for the call and never
stored in the error value:

```lisp
(return (err config-missing path))   ; handler receives path as detail
```

**`with-handler`.** Binds a handler in the current dynamic extent (from
`lib/error.nuc`; requires `(import-use error)`):

```lisp
(with-handler (error-value repair-type handler-fn ctx) body…)
```

- `error-value` — a `deferror` constant; the handler fires only on this error.
- `repair-type` — the value type `T` of the `!T` function being repaired.
  Declared explicitly because the handler may be active across many sites
  returning different `T`s, and the compiler needs the type at the `err` site
  to make the match sound and to wrap `(ok v)` correctly.
- `handler-fn` — a function `(fn (Maybe repair-type) (ptr ptr))` taking `(ctx
  detail)` and returning `(Maybe repair-type)`. Return `(some v)` to repair;
  return `none` to decline (the error propagates).
- `ctx` — an arbitrary `ptr` forwarded to every call of `handler-fn`.

**Handler keying.** A handler matches only when **both** the error id and the
site's repair type `T` agree. A handler bound for `(config-missing, Config)`
fires at `!Config` sites and is invisible to a `!FILE` site raising the same
error. The type key is the type's mangled-name string (pointer-compare with
`strcmp` fallback, separate-compilation-safe).

**Semantics.**

- *Origin-only, once.* Handlers run at the `(err E)` site, never at `(try …)`
  propagation. `try` re-returns via `err!`, so propagation never re-checks
  handlers.
- *CL unbind rule.* While a handler executes, the chain is rewound past that
  handler. An error raised inside a handler finds only outer handlers — no
  self-match, no infinite recursion.
- *Zero happy-path cost.* The handler check sits only on the `(err E)` return
  path. Programs that bind no handlers pay one global pointer load and null
  compare per `err` return, on the error path only. `err!` costs nothing extra.

**Gating.** The handler machinery lives in `lib/error.nuc`. Without
`(import-use error)`, `(err E)` behaves like `(err! E)` — the check is never
emitted. `try`, `with-handler`, `Handler`, and `err-find-handler` all require
the import.

**v1 limitation.** Handler repair types must be value types. A repair type that
is a `(ref X)` (i.e. a `(Maybe (ref X))`-shaped return from the handler fn) is
not supported in v1.

**Example** (see also `examples/handlers.nuc`):

```lisp
(import-use "stdio.h")
(import-use error)

(deferror config-missing "config file not found")

; A fallible function. (err config-missing) consults bound handlers first.
; err! would bypass them unconditionally.
(defn load-num:!i64 (n:i64)
  (when (= n (cast i64 0))
    (return (err config-missing)))    ; handler may repair → (ok v)
  (return (ok (* n (cast i64 10)))))

; A repairing handler: (some v) repairs, none declines.
(defn (repair-from-ctx (Maybe i64)) (ctx:ptr detail:ptr)
  (return (some (deref (cast ptr:i64 ctx)))))

(defn main:i32 ()
  ; No handler bound: (err config-missing) returns the error value.
  (match (load-num (cast i64 0))
    ((ok v)  (printf "ok %lld\n" v))
    ((err e) (printf "err: %s\n" (err-name e))))

  ; Repairing handler bound for (config-missing, i64): err → (ok 777).
  (let (fixed:i64 (cast i64 777))
    (with-handler (config-missing i64 repair-from-ctx (cast ptr (addr-of fixed)))
      (match (load-num (cast i64 0))
        ((ok v)  (printf "repaired: %lld\n" v))   ; prints: repaired: 777
        ((err e) (printf "err: %s\n" (err-name e))))))
  0)
```

## Standalone `signal`

```lisp
(signal E RepairType)            ; → (Maybe RepairType)
(signal E RepairType detail)     ; detail:ptr, borrowed for the handler call
```

`signal` asks bound handlers for *policy* without returning. It walks the same
handler chain `with-handler` binds, looking for a handler keyed on `(E,
RepairType)` — exactly `err-find-handler`'s key — and, on a match, calls it
under the CL unbind rule and yields its `(Maybe RepairType)`; `none` (no handler
matched, or the handler declined) is the default. `RepairType` is a **type**
operand (parsed, not evaluated), like `with-handler`'s `type-token`.

Unlike `(err E)`, `signal` is **not tied to return position** and does **not**
wrap the result in `(ok v)` — it hands the `(Maybe RepairType)` straight back, so
the caller decides what to do (continue in place, fall back, propagate). This is
errors.md §4's "low-level code asks high-level code for policy" shape — e.g. an
allocator's grow path signalling for a replacement block, falling back to its own
behavior if policy declines:

```lisp
(import-use error)
(deferror out-of-memory "allocation grow needs a policy decision")

(defn grow:i64 (need:i64)
  (match (signal out-of-memory i64 (cast ptr (addr-of need)))
    ((some sz) sz)               ; a handler supplied a size: continue
    (none      (cast i64 0))))   ; declined / no handler: the fallback

(defn (grant-double (Maybe i64)) (ctx:ptr detail:ptr)
  (return (some (* (deref (cast ptr:i64 detail)) (cast i64 2)))))

(with-handler (out-of-memory i64 grant-double null)
  (grow (cast i64 8)))           ; → 16
```

`signal` requires `(import-use error)` (it references the handler chain). Its result
is a **value** `(Maybe T)`, eliminated with `match` (not `if-some`, which is
pointer-only). The **v1 repair-type-is-a-value-type limitation** applies: a
`(ref X)` niche-pointer repair is not a struct, so the struct-return call path
cannot carry it (`examples/signal.nuc`).
