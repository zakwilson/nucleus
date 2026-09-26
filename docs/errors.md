# Error Handling (Stage 10)

Recoverable errors are ordinary return values (`design/stage10/errors.md`). A
fallible function returns a `(Result T E)` — `ok` with a `T`, or `err` with an
`E` — and the caller must `match`, `try`, or `unwrap` before using the value.
`E` comes in two tiers:

- **the code tier**: the builtin `Err`, a C-legible `i32` named by `deferror`.
  `(Result T Err)` is common enough to have the sugar `!T`, and only it gets
  the handler chain ([below](#handler-aware-err-and-with-handler-e3)).
- **the payload tier**: any type of your own, when a failure must carry data —
  a line, a formatted message. It is built and eliminated exactly like `!T`
  (bare `ok`/`err`/`err!` target-type against the declared return, no `make`),
  and one `defcast E Err` lets `try` carry it into a plain `!T` caller. See
  [`Err` is the code; `(Result T E)` is the payload](#err-is-the-code-result-t-e-is-the-payload).

The unrecoverable tier is unchanged: `die`/`die-at` still abort.

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

Like `defconst`, the name takes **no** type annotation — `(deferror MyErr:i32
"bad")` is rejected (`deferror: takes no type annotation; write (deferror
MyErr "message")`) rather than silently compiling and leaving `MyErr`
undefined at every use.

**The `!` type sugar** (recognized only in type positions, so no clash with
`!=`):

| Spelling | Expansion | Reading |
|---|---|---|
| `!T`  | `(Result T Err)`           | fallible value — `T` as written (`!i64` is `(Result i64 Err)`) |
| `!?T` | `(Result (Maybe T) Err)`   | error, or none, or value |
| `?!T` | `(Maybe (Result T Err))`   | a fallible result that may be absent (value-`Maybe` over a Result) |
| `!(T …)` | `(Result (T …) Err)`    | the paren form: `!(Vector i32)`, `?!(Vector i32)`, `r:!(ref FILE)` — reads as the list form `(! (Vector i32))`, which is the same type |

After the Phase F flip `?` is uniform `(Maybe T)` (no `(ref …)` injection), so
`?` and `!` compose without asymmetry — both take their payload as written
(`!?i64` is `(Result (Maybe i64) Err)`; `?ptr:T` is the niche-encoded
nullable pointer). The
`(Result T E)` template now lives in the prelude, always available. Because the
toplevel signature prescan now resolves imported (prelude) types, `name:!Config`
parses in ordinary signatures. (`name:(Result Config Err)` now parses too via
the colon-paren sugar, so `!` is no longer *required* for that — but it
remains the terser spelling and composes with the `?!` value-Maybe-over-Result
sugar.) `!` over a parenthesized payload is written attached, `!(ref FILE)`,
and reads as `(! (ref FILE))` — a bare `!` head is the canonical list form of
the sigil (Stage 21 PK-3; see [types.md](types.md#type-syntax-and-desugar)).
`! (ref FILE)` with a space is refused as a near-miss.

## Constructing and eliminating `!T`

**Construction.** In `return` position (and the implicit-return tail) of a
function declared `!T` — or declared to return any `(Result T E)`, `E` need
not be the builtin `Err` — bare `(ok v)` / `(err e)` resolve against the
declared return type (the union target-typing rule):

```lisp
(defn parse-line (s:StrView):(Result i32 ReadError)
  (when (bad? s) (return (err (ReadError read-bad-escape line msg ""))))
  (return (ok n)))
```

needs no `make`. **Reading rule (builtin `Err` only):** `(err E)` means "give
up unless a bound handler repairs"; `(err! E)` means "give up
unconditionally" — it bypasses the handler chain and returns the error value.
Use `err!` when you want an unconditional error return regardless of any
bound handlers; with a custom `E` there is no handler chain to bypass (only
the builtin `Err` gets one — [Handler-aware `err` and
`with-handler`](#handler-aware-err-and-with-handler-e3) below), so `err` and
`err!` behave alike there. Away from `return`, the same bare forms construct
against a typed binding, a `set!` target, a `make` or struct-literal field or a
call argument
(target typing — see [Templates](structs-unions.md#templates-defunion-result-t-e-)).
Handler negotiation yields a value of the function's return type, so only a
binding or `set!` of exactly that type negotiates as a return would; any other
slot, and every call, `make` or struct-literal argument, builds the error value as `err!` does.
With no type to construct against, write `(make (Result T E) ok v)`; stored
Results are plain data with no handler machinery either way.

**Elimination.**

| Form | Meaning |
|---|---|
| `match` | the eliminator — `((ok v) …)` / `((err e) …)` arms |
| `(try r)` | propagation **special form**: yields the `ok` value, or re-returns the error via `err!` from the enclosing `!T` function. Needs no import. On a `!void` operand the `ok` arm carries no payload, so `try` yields nothing — see [`!void`](#void--a-result-with-no-ok-payload). |
| `(unwrap r)` | the `ok` payload, or — on `err` — print `err-name`/`err-message` and abort (needs `printf` in scope for the message) |
| `(unwrap-or r d)` | the `ok` payload, or `d` (evaluated only on the `err` arm) |
| `(err-name e)` / `(err-message e)` | the descriptor strings for an `Err` value |

```lisp
(import-use "stdio.h")
(import-use error)
(deferror parse-failed "could not parse value")

(defn checked (n:i64):!i64
  (when (< n 0) (return (err parse-failed)))
  (return (ok n)))

(defn doubled (n:i64):!i64
  (let (v:i64 (try (checked n)))          ; propagate on err
    (return (ok (* v 2)))))

(match (checked x)
  ((ok v)  ...)
  ((err e) (printf "%s: %s\n" (err-name e) (err-message e))))
```

## `Err` is the code; `(Result T E)` is the payload

`Err` carries no payload by design: a C-legible `i32` enum, and the one
pointer `!ptr:T` needs for its [ERR_PTR niche](structs-unions.md#niche-layout-and-repr-stage-10-c4)
(`sizeof(!ptr:T) == sizeof(T*)`). A function whose failure needs a line
number, a formatted message, or any other data does not grow `Err` a payload
— it returns its own `E` instead. `(Result T E)` admits any `E`, constructed
and eliminated exactly like `!T` above, and one `(defcast E Err from-e-fn)`
is the bridge back to the code tier: `try` propagates an `(err e)` unchanged
into a caller returning the *same* `(Result T E)`, and — through the
`defcast` — converts it to the `Err` code at the `(return (err! e))` `try`
expands to when the caller is a plain `!T`:

```lisp
(defstruct ReadError code:Err line:i32 msg:StrView note:StrView)
(defn read-error-code (e:ReadError):Err (return (e 'code)))
(defcast ReadError Err read-error-code)

(defn parse-config (src:StrView):(Result Config ReadError)
  …)

(defn load (path:StrView):!Config        ; a plain !T caller
  (let (src:StrView (try (read-file-view path)))
    (return (ok (try (parse-config src))))))   ; ReadError -> Err, via the defcast
```

`lib/read.nuc`'s own `ReadError` ([Reading s-expressions](reading.md#readresult-and-readerror))
is exactly this shape, and is why `read-all`/`read-one` can hand a caller a
line and a formatted message without `Err` growing a payload or the reader
inventing side fields for it. A library whose failures carry context should
follow the same shape: return its own `E`, register one `defcast E Err`, and
let `try` do the conversion — not a fatter `Err` and not accessor fields
bolted onto some other value.

A `defunion` with an `ok` arm and an `err` arm is eliminated as a Result by
`match`/`try`/`unwrap`/`unwrap-or` **structurally** — it need not be a
`(Result T E)` template instance. `lib/read.nuc`'s `ReadResult` relies on
this: a template instance stamped over a nullable pointer payload
loses that pointer kind (`type-spelling` re-spells every stamped pointer as
non-null `ref:`), so `(Result ?&Node ReadError)` would refuse to hold a
null node, and `ReadResult` is a hand-written `(defunion ReadResult (ok
v:?&Node) (err e:ReadError))` instead. See [Unions and tagged
sums](structs-unions.md#unions-and-tagged-sums).

## `!void` — a Result with no `ok` payload

A fallible operation with nothing to return on success is spelled `!void`:

```lisp
(defn check (n:i32):!void
  (when (> n 100) (return (err! too-big)))
  (return (ok)))                       ; no payload

(defn use (n:i32):!i32
  (try (check n))                      ; propagates; yields nothing
  (return (ok (* n 2))))

(match (check 7)
  ((ok)    (printf "ok\n"))            ; no binder
  ((err e) (printf "%s\n" (err-name e))))
```

`!void` is `(Result void Err)` like any other `!T`, and needs no special
handling: a `void` field in a `defunion` arm carries no value, so it
contributes none, and the stamped `ok` arm is payload-less exactly like
`Maybe`'s `none`. So it is constructed `(ok)`, matched `((ok) …)`, and `try`d
with the value discarded. The backing layout is the ordinary tagged struct
`{i32 tag, Err}`.

This is why `try` is a special form rather than a library macro: the `ok` arm's
binder count depends on the operand's *type*, and a macro cannot see one.

In a `!void` function `(err E)` is `(err! E)`. The handler negotiation repairs
a failure by supplying the `ok` **value**, and a payload-less `ok` arm has none
to supply, so there is nothing for a handler to return — the chain is not
consulted. Everything else about `!void` is an ordinary `!T`.

See `examples/result-void.nuc`.

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
  Use `:repr tagged` on the `defunion` to opt out and force the struct layout
  when a C consumer needs it unconditionally (see [Niche layout and `:repr`](structs-unions.md#niche-layout-and-repr-stage-10-c4)).

Nothing propagates across a function boundary by a mechanism C doesn't
understand.

`--emit-cheader` does not yet *declare* the non-pointer case, though: `!T` is a
`(Result T Err)` template instance, and the header emits no typedef for a
template instance to declare against, so a function returning or taking one is
omitted with a comment in its place. The layout above is still the contract — a
C declaration written by hand against it works — but the header will not write
it for you. Pointer niches are declared normally. See
[Error-union and option types in a C header](compiler.md#error-union-and-option-types-in-a-c-header).

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
emitted. `with-handler`, `Handler`, and `err-find-handler` require the import;
`try` does not (it is a special form, not a library macro).

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
(defn load-num (n:i64):!i64
  (when (= n 0)
    (return (err config-missing)))    ; handler may repair → (ok v)
  (return (ok (* n 10))))

; A repairing handler: (some v) repairs, none declines.
(defn repair-from-ctx (ctx:ptr detail:ptr) (Maybe i64)
  (return (some (deref (as ptr:i64 ctx)))))

(defn main ():i32
  ; No handler bound: (err config-missing) returns the error value.
  (match (load-num 0)
    ((ok v)  (printf "ok %lld\n" v))
    ((err e) (printf "err: %s\n" (err-name e))))

  ; Repairing handler bound for (config-missing, i64): err → (ok 777).
  (let (fixed:i64 777)
    (with-handler (config-missing i64 repair-from-ctx (as ptr &fixed))
      (match (load-num 0)
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

(defn grow (need:i64):i64
  (match (signal out-of-memory i64 (as ptr &need))
    ((some sz) sz)               ; a handler supplied a size: continue
    (none      0)))              ; declined / no handler: the fallback

(defn grant-double (ctx:ptr detail:ptr) (Maybe i64)
  (return (some (* (deref (as ptr:i64 detail)) 2))))

(with-handler (out-of-memory i64 grant-double null)
  (grow 8))                      ; → 16
```

`signal` requires `(import-use error)` (it references the handler chain). Its result
is a **value** `(Maybe T)`, eliminated with `match` (not `if-some`, which is
pointer-only). The **v1 repair-type-is-a-value-type limitation** applies: a
`(ref X)` niche-pointer repair is not a struct, so the struct-return call path
cannot carry it (`examples/signal.nuc`).
