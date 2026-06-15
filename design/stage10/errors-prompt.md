# Stage 10 — Error handling: implementation prompt

You are implementing the error-handling feature for Nucleus. The full design,
rationale, and the rejected alternatives live in [errors.md](errors.md); this
file is the condensed, actionable spec. Read [errors.md](errors.md) §8–§13 when
you need the *why*; read this file for *what to build and in what order*. The
foundation it builds on is [unions.md](unions.md) (U1–U3, **landed**) and
[nullability.md](nullability.md) (N1/N2, **landed**); skim their
implementation-status sections before starting.

## What's being built (the resolved design)

A two-tier error model:

- **Recoverable errors are ordinary return values.** A fallible function
  returns `(Result T Err)`, sugar `!T`. The caller must `match` (or `try`,
  `unwrap`) before using the value. This is **A1** — the generic
  `(Result T E)` from [unions.md](unions.md), now unblocked because tagged sums
  landed. (A2, the niche-encoded pointer optimization, is **deferred** to U4.)
- **`die`/`die-at` stays the panic tier** for bugs and unrecoverable states —
  abort, no unwinding (the REPL `repl_throw` boundary excepted, as today).
- **Handler-aware `err`**: returning an error *checks dynamically-bound
  handlers first by default*; if a handler repairs, the function returns the
  repaired value instead. `err!` is the opt-out that returns the error
  unconditionally. This is the "C-lite resumption" idea (errors.md §4) folded
  into the return path per the designer's directive (errors.md §11).

### Authoritative decisions (do not re-litigate)

1. **A1 is the version built**; A2 / niche layout / `:repr` are deferred with U4.
2. **`!` sugar adopted**; `!?` and `?!` are both legal. `!` is recognized only
   in type-parsing positions, so there is no collision with `!=`.
3. **Error ids are one global set**, dense from 1, namespaced later when
   namespaces exist. **Id cap 4095** (keeps A2's future encoding reachable).
4. **Returning an error checks bound handlers by default**; `err!` bypasses.
   Reading rule: `err` = "give up unless someone above repairs"; `err!` = "give
   up."
5. **Handlers are keyed on the pair (error, repair-type)** (errors.md §11.2,
   confirmed §13.2). The repair type is **declared explicitly** in the
   `with-handler` form (not inferred from the handler fn's return type — that
   would need compile-time metadata interrogation, which doesn't exist). The
   handler fn must return `(Maybe repair-type)`.
6. **`(err E detail)`** — optional transient `ptr` detail argument: **in**.
7. **`match` is the eliminator** — do **not** add `if-ok`.
8. **No `errdefer`** in v1 (reintroduce on demand). **No standalone `signal`**
   in v1. **No `dyn`** (a future musing only).
9. **The safety flip is part of this pass** (decision §13.1 — see "Phase F"
   below). It removes the `?` asymmetry by re-spelling `?` uniformly.

### Non-negotiable invariants (errors.md §1, safety.md §2)

- **Zero mandatory runtime cost.** The happy path costs nothing. The handler
  check sits *only* on the error-return path; `err!` recovers exact zero.
  Programs that bind no handlers pay one global load + null compare per checked
  `err` return, on the error path only.
- **C-ABI neutrality / consumable from C.** A `!T` is the U2 tagged struct
  `{i32 tag; union payload}` plus the `Err` constants — fully C-legible. An
  error must never propagate across an exported function boundary by a
  mechanism C doesn't understand (no unwinding — that's why exceptions were
  rejected outright).
- **Library where possible, compiler where necessary.** Keep the `Handler`
  record, the chain global, and the find-walk in a library (`lib/error.nuc`);
  the compiler supplies only the check emission, target typing, and the
  `Err`/`Result` types.
- **Bootstrap discipline.** Each phase is independently shippable and keeps a
  **byte-identical bootstrap** until a phase deliberately converts code. After
  every phase: `make test` (examples + REPL sessions) and `make bootstrap`
  (fixed point) must pass, and all boot artifacts (Linux + Windows IRs,
  `bin/nucleusc`) must re-converge in lock-step. Breaking changes may use
  temporary bootstrap shims (AGENTS.md "Pre-release").

---

## Phase E1 — `Err`, `deferror`, `Result`, `!T` sugar, `try`

No handlers yet, so `err` has no check to make (it behaves unconditionally,
exactly like `err!`). Byte-identical bootstrap until something adopts `!T`.

### `Err` and `deferror` (errors.md §8)

- **`Err` is a distinct builtin scalar type, represented as `i32`** (not an
  alias — `with-handler` and U4's future niche detection must key on it; `i32`
  so it is C-legible). **Id 0 is reserved** as "no error"; ids are assigned
  densely from 1 in definition order.
- `(deferror config-missing "config file not found")` binds `config-missing`
  as a **compile-time `Err` constant** and registers `{id, name, message}` in a
  static descriptor table emitted into the binary.
- `err-name` / `err-message` are **library accessors** over the descriptor
  table. `unwrap` and the panic tier print through them.
- **`deferror` dies past 4095 definitions** (keeps every id in the top-page
  range A2's future ERR_PTR encoding needs — no renumbering later).
- **C export.** Emit the constants as an enum / `#define`s plus the accessor
  declarations. An error crossing to C is an `int` with a documented meaning.
- Names are program-global now; namespace the *names* (not the id space) when
  namespaces land. Ids are per-build, not stable across builds — **the name is
  the contract, the id is the representation.**

### `Result`, the `!` sugar, and surface forms (errors.md §9)

- Move `(defunion (Result T E) (ok v:T) (err e:E))` from
  [examples/unions.nuc](../../examples/unions.nuc) into
  [lib/prelude.nuc](../../lib/prelude.nuc) so it is always available.
- Add the type-sugar in `parse-type-name` (src/nucleusc.nuc:1499 — the same
  recursion-past-the-prefix-char mechanism `?` already uses):

  | Spelling | Expansion (after Phase F; see note) | Reading |
  |---|---|---|
  | `!T`  | `(Result T Err)`                     | fallible value — **T as written**, by value for structs |
  | `!?T` | `(Result (Maybe T) Err)`             | error, or none, or value |
  | `?!T` | `(Maybe (Result T Err))`             | a fallible result that may be absent |
  | `?T`  | `(Maybe T)`                          | (re-spelled uniformly in Phase F) |

  **Note on `!T` taking T as written:** unlike the historical pointer-only `?`,
  `!T` does *not* inject `(ref …)` — A1's whole point is arbitrary payloads, so
  `!i64` must be `(Result i64 Err)`. This is why Phase F (the flip) re-spells
  `?` to plain `(Maybe T)` uniformly: it removes the asymmetry so `?` and `!`
  compose cleanly. **If E1 ships before Phase F**, `?T` still means
  `(Maybe (ref T))` and `!?T` reads `?` as value-Maybe over the Result value
  (the only sensible reading since the operand is already a complete value
  type); document the asymmetry until F lands.
- **Why the sugar matters (not just brevity):** `name:(Result Config Err)` does
  **not** parse (the U3 limitation on parenthesized types in colon positions),
  while `name:!Config` does. `!T` is what makes `Result` returns usable in
  ordinary signatures.
- `!` over a parenthesized payload has no sugar — write
  `(Result (ref FILE) Err)` longhand.

Surface forms (most already exist from U2/U3):

| Form | Status / work |
|---|---|
| `(ok v)` / `(err E)` in return position | **exists** (U3 target typing). `err` gains handler semantics in E3 |
| `(make (Result … Err) ok v)` | **exists** — explicit spelling for non-return positions |
| `(err! E)` | **new** — unconditional error return, no handler check. Needed by `try`, so lands here; only becomes *distinct* from `err` in E3 |
| `(try r)` | **new** — a library macro (no compiler support), expansion below |
| `match` | **exists** — the eliminator. Do not add `if-ok` |
| `(unwrap r)` / `(unwrap-or r d)` | **extend** the existing compiler forms to `Result` operands; `unwrap` dies printing `err-name`/`err-message` |

The `try` macro (verified against `emit-cond`/`emit-match-clauses`: a
terminated clause contributes nothing to the join phi, so the match yields the
ok arm's type):

```lisp
(defmacro try (r)
  (let (v (gensym) e (gensym))
    `(match ,r
       ((ok ,v) ,v)
       ((err ,e) (return (err! ,e))))))
```

`(err! ,e)` re-wraps and target-types against the **enclosing** function's
declared return — this is what lets `(try …)` cross from `!Config` into
`!App`, and is also why propagation never re-runs handlers (E3, origin-only).
`(try r)` over a `!?T` yields `?T`.

**E1 done when:** `deferror`/`Err`/descriptor table/`err-name`/`err-message`,
prelude `Result`, the `!T`/`!?T`/`?!T` sugar, `try`, `err!`, and
`unwrap`/`unwrap-or` over `Result` all work; bootstrap byte-identical.

---

## Phase E2 — `(Maybe T)` over values; `?!T`

[nullability.md](nullability.md) §1 deferred non-pointer `Maybe` to sum types;
sum types now exist. Byte-identical bootstrap.

- Add a `(defunion (Maybe T) (some v:T) none)`-shaped template to the prelude.
- Turn the parser's rejection of `(Maybe non-pointer)`
  (src/nucleusc.nuc:~1939, the `(when (= head 'Maybe) …)` block that currently
  `die-at`s `"Maybe: payload must be (ref T) …"`) into a **template stamp**:
  - `(Maybe (ref T))` keeps the N1 niche-encoded pointer (a parser special case
    until U4 makes it a layout rule);
  - `(Maybe T)` for any other T stamps the two-arm `{tag, T}` union.
  One spelling, two layouts.
- **Scope is deliberately minimal.** Value-`Maybe` is eliminated with `match`
  and constructed with `make` (or return-position target typing). The
  pointer-only forms (`if-some`/`when-some`/`unwrap`/`unwrap-or`,
  `some`/`none`/`as-ref` coercion outside return position) **stay pointer-only
  in v1**.
- Add the `?!T` sugar from E1's table.
- Value-`Maybe` is also the **decline channel for handlers** (E3): a handler
  returns `(Maybe T)`, `none` meaning "declined" — which removes any need for a
  reserved-null sentinel.

**E2 done when:** `(Maybe T)` over non-pointers stamps and is usable via
`match`/`make`; `?!T` parses; bootstrap byte-identical.

---

## Phase E3 — handler-aware `err` + `with-handler` + `err!`

From here `err` ≠ `err!`. Byte-identical bootstrap until a handler exists.

### The reading rule

`(err E)` means "give up **unless someone above repairs**"; `(err! E)` means
"give up." The check compiles in at exactly the positions where
**return-position target typing already fires** (U3): `(return (err E))` and the
implicit-return tail. In any other position, `err` (or `(make … err …)`) is a
**bare constructor** — a stored `Result` is just data; the negotiation happens
only when a function *gives up*.

**The check is emitted only when the error arm's type is `Err`** (i.e.
`!T`-shaped returns). A custom `(Result T MyErrStruct)` is a plain union with no
implicit machinery.

### Semantics at an `err` site (errors.md §11.1–§11.3)

At `(return (err E))` / tail in a function returning `!T`: find a willing
handler; if one repairs with `v`, the function returns `(ok v)`; otherwise it
returns the error value `(err E)`.

- **Keyed on (error, repair-type)** (§11.2): a handler matches only if **both**
  its error id **and** the site's own `T` match. The repair type is identified
  by a **type token = the type's mangled-name string** (pointer-compare with
  strcmp fallback, separate-compilation-safe). Only on a double match is the
  stored fn pointer cast to `(fn (Maybe T) (ptr ptr))` and called — the match
  is what makes the cast sound, without RTTI. Consequence (a feature): a
  handler bound for `(config-missing, Config)` fires at `!Config` sites and is
  invisible to a `!FILE` site returning the same error.
- **Origin-only, once** (§11.3): handlers run *only* at the `err` site nearest
  the fault, never at propagation. `try` re-returns through `err!`, so
  propagation never re-checks handlers.
- **CL unbind rule** (§11.4): the emitted call saves/restores the chain top
  around the handler invocation, so an error raised *inside* a handler finds
  only outer handlers.
- **`detail`** (§11.5): `(err E detail)` — optional second argument, `ptr`,
  passed to handlers and then dropped; **never stored** in the error value.
  Borrowed for the call (ownership by convention).

### The library/compiler split (errors.md §11.4)

**Library half** — small, in `lib/error.nuc`:

```lisp
(defstruct Handler
  what:Err          ; condition identity (a deferror value)
  rty:ptr           ; repair-type token (mangled-name string)
  hfn:ptr           ; type-erased handler fn pointer
  ctx:ptr
  prev:ptr:Handler)

(defvar g-handler-top:ptr:Handler null)
```

plus a find-walk over the chain. `with-handler` is the errors.md §4 macro
(stack-allocate the `Handler` in the binding frame, link it, `defer` the
unlink — L2's `defer` makes the pop reliable across early returns) **plus** the
repair-type token. The repair type is **declared explicitly** in the
`with-handler` form, so the surface is:

```lisp
(with-handler (error-value repair-type handler-fn ctx) body…)
```

`with-handler` mangles the declared `repair-type` to its name token and stores
it in the `Handler`'s `rty` field. Declaring it explicitly avoids the
compile-time metadata interrogation that reading the token off the handler fn's
return type would require (which doesn't exist; unions.md §4). The handler fn
must return `(Maybe repair-type)`; `none` declines, `(some v)` repairs.

**Compiler half** — the **call side is compiler-emitted** at `err` sites,
because it needs the site's `T` for the match, the cast, and the `(ok v)`
re-wrap. The chain walk matches `(error, T-token)`, invokes on a double match
(with the save/restore around it), re-wraps a non-`none` repair as `(ok v)`, and
falls through to returning the error value when the handler returns `none` or no
handler matches.

### Honest costs to keep in mind (errors.md §11.6)

- Resumption granularity is the **function boundary**, not the fault site. If
  fault-site granularity matters, factor the negotiable operation into its own
  `!`-returning function. (This is the right pressure — it points where the code
  should go anyway.)
- The standalone signal-and-continue-in-place shape (errors.md §4's arena case)
  has no expression here; `signal` is omitted from v1 (recoverable later over
  the same chain).
- `err` can now succeed, so it no longer literally means "returns an error
  here" — hence the reading rule and `err!`.

**E3 done when:** `with-handler` binds/unlinks correctly; an `err` return in a
`!T` function consults matching handlers and returns the repaired `(ok v)` when
one repairs; `err!` always returns the error; re-entrancy uses the CL unbind
rule; `(err E detail)` passes `detail`; bootstrap byte-identical until a handler
is bound.

---

## Phase E4 — adoption

Convert `die-at` sites in library-ish code (reader, coercion) to `!T` returns
per errors.md §7.2, so the REPL's `repl_throw` longjmp boundary
(`src/repl_shim.c`) shrinks to true panics and today's error returns become
ordinary value paths. Candidate first sites: `lib/reader.nuc:21` (`die-at`),
coercion helpers. Byte-identical per step (convert one site at a time).

- **C-header gap (errors.md §11.7, unions.md §9):** `--emit-cheader` skips
  functions whose signatures mention template instances — exported `!T`
  functions need an instance-naming fix (e.g. `nuc_Result_Config_Err`) before C
  callers get prototypes. Do this only if/when the exported surface adopts `!T`.

**E4 done when:** the chosen `die-at` sites return `!T`; tests still pass;
the REPL behaves as before on the converted paths.

---

## Phase F — the safety flip (decision §13.1; folded into this pass)

This is the **largest and most invasive** item and the only one that is
*breaking*. It is the deferred "default flip" from
[safety.md](safety.md) §3/§4.6 and [nullability.md](nullability.md) §6, pulled
into this pass so that `?` can be re-spelled uniformly (which removes the E1
sugar asymmetry). Use temporary bootstrap shims as needed.

**What the flip does:**

1. **Reinterpret `(ptr T)` / bare `ptr` as non-null** (what `(ref T)` means
   today). `(ref T)` stays as the explicit blessed spelling.
2. **Retire raw nullable pointers to the `(raw T)` spelling** (parallel to
   `(ref T)`/`(ptr T)`, greppable). No `unsafe`-namespaced spelling now — an
   `unsafe` namespace arrives later, with namespaces.
3. **Re-spell `?` to plain `(Maybe T)` uniformly** — `?T` no longer
   auto-injects `(ref …)`. For pointer T it still niche-encodes
   (`(Maybe (ref T))`); for value T it is the E2 value-`Maybe`. This is the step
   that makes the E1 sugar table's `?`/`!`/`?!`/`!?` compose without asymmetry.

**Use the N2 friction findings as the implementation map**
([nullability.md](nullability.md) §9, "Friction findings"). The two
highest-leverage enablers, both called out there:

- **A `noreturn` function attribute for `die-at`** (finding 1, "the single
  highest-leverage enabler"). The pervasive `(when (= x null) (die-at …))` idiom
  does not currently narrow past the guard because nothing marks `die-at`
  noreturn. Adding `noreturn` lets all those guards become narrowing points and
  erases most of the flip's conversion cost. (This is also N2's top item and the
  errors-design's §7.3 shared-infrastructure note — do it early.)
- **Fix the prescan/prelude ordering** (finding 2) so prelude types
  (`Node`/`ref:Node`/`?Node`) can appear in `nucleusc.nuc` `defn` *signatures*,
  not just bodies. Until fixed, such signatures must stay `ptr`.

Also account for findings 3–5: mixed `cond`/`if` join collapse when one side is
bare `ptr`, the one correlated-field waiver, and the ~25 remaining guarded-cast
sites plus the `?i8`-shaped string returns left raw.

**F done when:** `(ptr T)` means non-null throughout; raw has its `(raw T)`
spelling; `?` is uniform `(Maybe T)`; the compiler compiles itself and all tests
pass; boot artifacts re-converge.

> **Sequencing.** Phase F's `?` re-spelling is what the E1/E2 sugar assumes, so
> the cleanest order is **F (or at least its `?` re-spelling + `noreturn`
> enabler) before or alongside E1**. Because F is heavy and breaking, an
> acceptable alternative is to ship E1–E3 with the documented `?` asymmetry,
> then do F and drop the asymmetry. Decide based on how much E-phase code would
> need rewording when `?` flips. Whichever order: F is in scope for this pass.

---

## Reference: the combined protocol (errors.md §4, §11)

Signal-first-via-handler, propagate-as-a-value-second, all without unwinding:

```lisp
(deferror config-missing "config file not found")

(defn read-config:!Config (path:ptr)
  (let (raw:ptr (fopen path "r"))
    (when (= raw null)
      (return (err config-missing path)))   ; (1) handler may repair → (ok cfg);
    (return (parse-config (cast ref:FILE raw))))) ;     else returns the error value

; Mid-stack code just propagates by value:
(defn load-app:!App (path:ptr)
  (let (cfg:ref:Config (try (read-config path)))   ; (2) try: never re-checks handlers
    …))

; Top-level policy supplies a fallback without touching any signature between.
; Returns (Maybe Config): (some cfg) repairs, none declines.
(defn use-default-config:(Maybe Config) (ctx:ptr detail:ptr) …)

(with-handler (config-missing Config use-default-config null)  ; repair type declared explicitly
  (main-loop))
```

The panic tier gets a hook for free (errors.md §4): `unwrap`/`die-at` may signal
an `'unhandled-error` condition before aborting once standalone `signal` exists
— but `signal` is **out of v1**, so don't build it now.

---

## Explicitly out of scope (do not build)

- **A2** niche-encoded `!T`, U4 niche layout, `:repr` — deferred (A1 is the core
  feature; A2 becomes a layout optimization later, and §8's id cap already
  reserves its range).
- **`if-ok`** — `match` is the eliminator.
- **`errdefer`** — `defer` + an explicit error path covers it; reintroduce on
  demand.
- **Standalone `signal`** (policy points with no error return, e.g. the
  arena-OOM continue-in-place shape) — recoverable later over the same chain.
- **`dyn`** — a future idea for improving handler typing; not this pass.
- **Exceptions** (sjlj or table-driven) — rejected outright (errors.md §7.1).

---

## Close-out checklist (required by AGENTS.md)

- Update language docs: [docs/builtins.md](../../docs/builtins.md) — extend the
  "Unions and tagged sums" (§~192) and "Pointer kinds" (§~126) sections for
  `Err`/`deferror`/`Result`/`!T`/handlers, and rewrite the `?`/`ref`/`ptr`
  description after the flip.
- Update [design/stage10/progress.md](progress.md) — add a Stage 10 errors table
  (mirror the unions table at lines ~114–125) and flip the N2/flip rows in the
  safety/nullability status.
- Record implementation notes back into [errors.md](errors.md) (the doc is
  designer↔robot; append a "robot — implementation status" section as
  [unions.md](unions.md) does) and reconcile the "flip: open" status in
  [safety.md](safety.md) §5 and [nullability.md](nullability.md) §9.
- After each phase: `make test` + `make bootstrap` green, boot artifacts
  converged. The compiler must compile itself.
