# Stage 10 — Error handling: options survey

#### Designer

Nucleus currently lacks an error handling mechanism (`die-at` isn't
error-handling — [../stage999-future.md](../stage999-future.md)). Survey the
options. Candidates include: an Error type with a shape similar to `Maybe`,
with definable error values representing errors or unusual conditions; a
traditional exception system; a condition/restart system. Add any good options
missing from that list. Include a summary of tradeoffs: C interop, runtime
overhead, implementation complexity, versatility.

#### Robot — response

This document is a survey, not a build spec; no decision is resolved here.
Where it helps, options are graded against the standing invariants
([safety.md](safety.md) §2): zero mandatory runtime cost, C-ABI neutrality,
raw escape hatches preserved, library-where-possible. One framing observation
up front: the modern systems languages (Rust, Zig, Swift, Go) all converged on
a **two-tier** shape — *recoverable errors are ordinary values in the return
type; unrecoverable bugs panic/abort* — while exceptions (C++, Java) and
conditions/restarts (Common Lisp) put recoverable errors on a separate,
dynamic control-flow channel. The tiers question (§7) is mostly independent of
which value representation or channel is picked.

## 1. What exists today

The current "mechanisms," for calibration:

- **`die-at`** (lib/reader.nuc:21) — `fprintf` + `exit(1)`; under the REPL it
  `repl_throw`s instead, a `longjmp` back to the driver loop
  (src/repl_shim.c). So a setjmp/longjmp non-local exit already exists in the
  tree, at exactly one boundary, established by C code.
- **`?T` / `Maybe`** (N1, [nullability.md](nullability.md)) — expresses
  *absence* with zero cost, but carries no reason. `scope-lookup` returning
  `none` can't say *why*.
- **C conventions through interop** — `errno`, negative returns, null returns;
  laundered with `as-ref` and guards.
- **Cleanups are lexical.** `with`/`defer`/`Drop` fire on fall-through and on
  early `return` — there is no dynamic-extent `unwind-protect`. Any option
  that introduces non-local exits must answer "what runs the cleanups in the
  skipped frames?"
- **`arena-alloc` aborts on exhaustion**; allocation failure is currently
  always fatal.

Two facts about the platform matrix constrain the exception options: the
supported triples span **three unwinding personalities** (DWARF/Itanium on
Linux and macOS, SEH on both windows-gnu and windows-msvc x86_64, and the
i386 variants), and Nucleus libraries must be **consumable from C**
(overview.md), which means errors must not propagate across an exported
function boundary by any mechanism C doesn't understand.

## 2. Option A — error values: `Result` / error unions

The designer's first candidate: mirror `Maybe`. A function that can fail
returns a value that is *either* the result *or* an error; the caller must
look before using it. Two sub-options, differing in how general the payload
is.

### A2 — error unions over pointers, niche-encoded (Zig-shaped)

The direct analogue of N1's `(Maybe (ref T))`. Errors are **definable values**
drawn from a program-wide set:

```
(deferror file-not-found "file not found")
(deferror parse-failed   "parse error")
```

Each `deferror` interns a static descriptor (name, message) and assigns a
small integer id. The error-union type — spelled here `(Result (ref T))`,
sugar `!T`; naming is a low-stakes default like `ref`/`Maybe` were — is
**niche-encoded in the same pointer**, ERR_PTR-style as in the Linux kernel:
`(err E)` is `inttoptr(-id)`, ids range 1..4095, and `is-err` is one unsigned
compare against `-4096`. The top page is never a valid object address on every
supported target, so:

- a `!T` **is a `T*` to C**, with a documented reserved range — this is
  literally a convention C programmers already use;
- no discriminant, no space cost, no ABI change — same trick, same machinery
  (`pkind`-like kind bit on `Type`, ignored by `type-eq`/mangling) as N1.

Surface forms mirror §3 of nullability.md deliberately:

| Form | Meaning |
|---|---|
| `(deferror name "msg")` | define an error value (static descriptor, interned id) |
| `(Result (ref T))` / `!T` | error-union type |
| `(ok v)` | wrap a `(ref T)` — no IR |
| `(err E)` | the error value as a `!T` |
| `(if-ok (x r) then else)` | narrow: bind `x:(ref T)` in `then`; in `else` the error is accessible (e.g. `(err-of r)`) |
| `(try r)` | **propagate**: if error, return it from the enclosing fn (whose return type must accept it); else yield `(ref T)` |
| `(unwrap r)` | die with the error's name/message if err |
| `(unwrap-or r default)` | default on err |
| `(errdefer expr)` | like `defer`, but runs only when the scope exits on the error path |

The N1 narrowing machinery (`sym-effective-type`, `cond`-test narrowing,
kill-on-assign) is exactly the machinery `if-ok`/guard idioms need; `if-ok`
can desugar to `cond` the same way `if-some` does. **Propagation is just an
early `return`**, so `with`/`defer`/`Drop` cleanups fire with no new
mechanism — the error path is ordinary control flow. Because the error set is
in the return *type*, signatures declare what can flow (the good half of
Java's checked exceptions, without the ceremony — the compiler can check that
`try` only propagates into a compatible return type).

Two known weak spots, worth recording now:

1. **Error context.** An error value is an id — it says *file-not-found*, not
   *which file*. The honest answers are: (a) callers attach context as they
   re-wrap/propagate (Zig's answer; error traces are tooling, context is your
   job); (b) a thread-local "last error detail" buffer (errno-style, with
   errno's known problems); (c) errors as pointers to structs, which
   reintroduces ownership/lifetime questions that `with`/`Drop` would have to
   answer. (a) is the only one with zero mandatory cost.
2. **Non-pointer payloads.** `!i64` can't niche without stealing value range
   (the `-errno` convention does exactly that, and it's fine *as a
   convention*, but it can't be the typed general case). The general payload
   needs a discriminant — which is A1.

### A1 — generic `(Result T E)` (Rust-shaped)

The fully general version: a two-armed sum type with arbitrary success and
error payloads, `{tag, union}` representation, returned by value (the stage-8
ABI classification already handles small structs in registers). Strictly more
expressive: error *structs* with context fields, `Result` over integers and
floats, user-chosen error enums per API rather than one global set.

This is gated on the **sum-types + `match` work**, now designed in
[unions.md](unions.md) (the same dependency nullability.md §1 notes for
`(Maybe T)` over non-pointers). Building `Result` ad hoc before sum types
exist would mean hand-rolling a one-off tagged union in the compiler —
exactly the kind of special case the "few special forms" principle counsels
against. The natural sequencing is A2 now (pointer
payloads, mirroring Maybe's scope), A1 later as a *consequence* of sum types,
with A2's encoding becoming a niche-optimization the sum-type layout engine
applies automatically (as Rust does for `Option<&T>`).

## 3. Option B — traditional exceptions

`throw` transfers control to the nearest dynamically enclosing `catch`,
unwinding every frame in between. Two implementation families, with very
different cost profiles and the same two fatal-looking problems.

### B1 — setjmp/longjmp

Each `try` block costs a `setjmp` (register/context spill — tens of cycles,
*paid on the happy path*); `throw` is a `longjmp`. The REPL shim is precedent.
But `longjmp` skips the intervening frames without running their
`with`/`defer`/`Drop` cleanups. Fixing that requires a **runtime cleanup
chain**: every function with cleanups pushes/pops records so the thrower can
walk them. That is a mandatory runtime cost imposed on *all* code using
`with`, whether or not exceptions are ever thrown near it — a direct violation
of the zero-mandatory-cost invariant, paid precisely by the code that adopted
the stage-10 safety features.

### B2 — zero-cost table-driven unwinding

The C++/Itanium model via LLVM: every call inside a frame with live cleanups
becomes `invoke` with a landingpad that re-emits the cleanups; a personality
function interprets static unwind tables. Happy path costs no cycles, but:
binary-size tables, inhibited optimization around invokes, a very slow cold
path, and the implementation is famously the most complex subsystem in C++
compilers. Nucleus would need it **three times**: DWARF/Itanium (Linux,
macOS), SEH funclets (`catchswitch`/`catchpad`) for x86_64 windows-msvc *and*
windows-gnu, plus whatever the i386 targets use. The `with`/`defer`/`Drop`
emission, which today is simple "re-emit at scope exit," becomes entangled
with EH scope nesting on every target.

### Shared problems (both B variants)

- **C interop is the worst of any option.** Unwinding *through* C frames is
  undefined-adjacent (C cleanups don't run; on some targets the unwinder can't
  even traverse frames built without tables), and an exception escaping a
  Nucleus function *into* a C caller breaks the "consumable from C" goal
  outright. Rust's answer — abort if unwinding hits an `extern "C"` boundary —
  is the only sound one, and it means every exported function needs a
  conceptual catch-all anyway.
- **Invisible control flow.** Every call becomes a potential exit; the
  reader can no longer see the error paths. This cuts against the explicitness
  that makes `?T`-narrowing work, and against "worse is better."
- What exceptions buy — multi-frame propagation without per-frame plumbing —
  is exactly what the `(try …)` macro provides for one token per call, with
  the paths visible.

## 4. Option C — conditions and restarts (Common Lisp-shaped)

The most general candidate. Split error handling into three roles: code that
*signals* a condition, code that *decides* policy (handlers, bound earlier on
the stack), and code that offers *recovery options* (restarts, bound near the
fault). The key property exceptions lack: **handlers run before any
unwinding, on top of the signaling frame**, so a handler can repair and
*resume* — return a replacement value, retry the operation, ignore the
problem — and unwinding happens only if the chosen restart demands it.

Mechanically: a thread-local handler stack; `signal` walks it calling handler
functions; `restart-case` registers restart points; invoking a restart in a
lower frame is a non-local exit to it. Costs are pay-as-you-go (push/pop where
handlers/restarts are bound, a stack walk when signaling) — compatible with
the zero-mandatory-cost rule, unlike B.

Three Nucleus-specific frictions:

1. **No closures** ([../stage999-future.md](../stage999-future.md)). CL's
   ergonomics lean entirely on closures for handlers and restarts. Without
   them, every handler is a fn-pointer + context-struct pair — workable (it's
   how C callbacks live) but heavy enough that the system loses much of its
   charm. Realistically this option *follows* closures, not precedes them.
2. **Unwinding restarts inherit all of §3.** When a restart in frame N is
   invoked from a signal in frame N+20, frames must unwind with cleanups —
   the same dynamic-extent problem (`defer` is lexical today), the same
   sjlj-vs-tables choice, the same C-frame hazards.
3. The **resumption-only subset is cheap and C-clean** — and is worth naming
   as its own option:

### C-lite — resumption-only conditions (no unwinding, library-only)

Handlers may repair (return a replacement value to the signaler) or decline;
if every handler declines, the signaler falls back to whatever it does today
(usually `die`). No restarts-by-unwinding, therefore no non-local exit, no
cleanup problem, and — notably — **signaling across C frames is perfectly
safe**, because handler invocation is just an ordinary call. A C callback
deep under Nucleus code can signal a Nucleus handler bound above it; no other
option here can say that. It is implementable *today* as a pure library with
zero compiler work. Since §7 proposes it as the cheap experiment, this
section sketches it concretely.

#### The whole library

A handler is a condition identity, a fn pointer, and a context pointer (no
closures yet, so the environment is manual), in a record **stack-allocated in
the binding frame** and linked into a chain (one global now; `_Thread_local`
via C interop when threads matter):

```lisp
(defstruct Handler
  what:ptr                  ; condition identity (interned symbol or error value)
  (hfn (fn ptr) (ptr ptr))  ; (ctx detail) → repair value, or null to decline
  ctx:ptr
  prev:ptr:Handler)

(defvar g-handler-top:ptr:Handler null)

; Offer `detail` to handlers for condition `c`, innermost first.
; Returns a repair value, or null if every handler declined.
(defn signal:ptr (c:ptr detail:ptr)
  (let (h:ptr:Handler g-handler-top)
    (while (!= h null)
      (when (= (h what) c)
        (let (saved:ptr:Handler g-handler-top)
          (set! g-handler-top (h prev))       ; CL rule: a handler runs unbound,
          (defer (set! g-handler-top saved))  ; so re-signaling finds outer ones
          (let (r:ptr ((h hfn) (h ctx) detail))
            (when (!= r null) (return r)))))
      (set! h (h prev)))
    (return null)))
```

That is essentially the entire runtime. A `with-handler` macro stack-allocates
the `Handler`, links it, and `defer`s the unlink — L2's `defer` is exactly
what makes the pop reliable across early returns — and the stage-9
callable-values work makes `((h hfn) …)` an ordinary indirect call. Null is
the reserved "decline" value (a repair may not itself be null — the same
one-reserved-value discipline as the niche encodings elsewhere in this
stage). Cost is confined to users: a few stores at bind, a chain walk at
signal, nothing anywhere else in the program.

#### Standalone

The motivating case from §7: allocation-failure policy. Today
`arena-grow` does `(perror "arena grow") (exit 1)` (lib/arena.nuc). With a
signal point, the *mechanism* stays in the arena and the *policy* lives
wherever someone cares:

```lisp
; lib/arena.nuc, the grow path:
(when (= block null)
  (set! block (signal 'out-of-memory (cast ptr need)))
  (when (= block null)                   ; declined by every handler:
    (perror "arena grow") (exit 1)))     ; …exactly today's behavior

; Policy, bound once near the top of the program:
(defn on-oom:ptr (ctx:ptr detail:ptr)
  (let (c:ptr:Cache (cast ptr:Cache ctx))
    (if (>= (c bytes) (cast i64 detail))
        (return (cache-evict-all c))     ; repair: hand the freed block over
        (return null))))                 ; decline: outer handlers / exit decide

(with-handler ('out-of-memory on-oom (cast ptr g-cache))
  (run-pipeline))
```

Nothing between `run-pipeline` and the arena — including any C library
frames in between — knows this negotiation exists. The same shape serves
warnings and diagnostics (signal a `'warning` condition whose default is
"continue"; a REPL or test harness binds a collector), fallback resources,
and retry policies.

Standalone, though, the honest assessment is that C-lite is a *complement to
the status quo*, not an error-handling system:

- **Ordinary fallibility is unserved.** "This call failed and my caller
  should deal with it" — the common case — still needs a return convention,
  so standalone C-lite leaves it on today's null returns, `?T`, and status
  codes. Routing per-call failures through the handler stack would be
  dynamic-scope spaghetti: the handler usually *is* the immediate caller,
  which already has a cheaper channel — the return value.
- **Every signal site must choose a no-handler fallback** (die, or a default
  and continue). Right granularity for emergencies and policy questions;
  wrong for "file not found."
- **No propagation help** — nothing like `try`, because nothing propagates.

#### Combined with Option A: signal first, propagate second

The two mechanisms answer different questions — A: "how do errors *return*?";
C-lite: "how does low-level code ask high-level code for *policy* without
returning?" — and they share a vocabulary: condition identities can simply
**be A2's `deferror` values**, one set of names for what is returned *and*
what is signaled. The combined protocol at a fault site is: *signal first
(someone above may repair, and then the failure never happened); propagate as
a value only if policy declines*:

```lisp
(deferror config-missing "config file not found")

(defn read-config:!Config (path:ptr)
  (let (raw:ptr (fopen path "r"))
    (when (= raw null)
      (set! raw (signal config-missing path)))   ; ask policy: alternate handle?
    (when (= raw null)
      (return (err config-missing)))             ; declined: propagate by value
    (return (parse-config (cast ref:FILE raw)))))

; Mid-stack code neither knows nor cares — it propagates by value as usual:
(defn load-app:!App (path:ptr)
  (let (cfg:ref:Config (try (read-config path)))
    …))

; Top-level policy: supply a fallback, without touching any signature between:
(defn use-default-config:ptr (ctx:ptr detail:ptr)
  (return (fopen "/etc/app/default.conf" "r")))  ; null ⇒ decline, conveniently

(with-handler (config-missing use-default-config null)
  (main-loop))
```

This reconstructs Common Lisp's `signal` → handler → `error` ladder with
`(return (err …))` standing in for the unwinding `error` — resumption *and*
typed propagation, still with no unwinding anywhere. What each side
contributes that the other lacks:

- **Without C-lite, pure-A code threads policy through signatures.** The only
  way for `main` to influence the `fopen` failure twenty frames down is to
  pass a config struct or callback through every intermediate call. The
  handler stack is dynamic scoping *for policy decisions only*, which is the
  one place dynamic scope earns its keep.
- **Without A, C-lite has nowhere to send a declined error.** The
  `(err config-missing)` arm is what lets the fault site give up gracefully;
  standalone it would have to die or limp.
- **The panic tier gets a hook for free:** `unwrap` (and `die-at`) can signal
  an `'unhandled-error` condition before aborting — a handler can log,
  pretty-print, or (in the REPL) record the error before the existing
  `repl_throw` boundary fires. That is CL's debugger hook, at the cost of one
  signal call on a path that was about to die anyway.

#### Hard limits (both modes)

`ctx`, `detail`, and repair values are untyped `ptr` — per-condition typed
wrapper macros recover some safety, and stage-9 bounded generics could
eventually type `signal` per condition value, but the floor is C-callback
typing. Ownership is by convention (`detail` is borrowed for the call; a
repair transfers to the signaler and must satisfy whatever contract the
missing value had, `Drop` included). Handlers execute at the fault site with
arbitrary stack below the binder, so they must be careful about reentrancy
and allocation (an out-of-memory handler that mallocs). And a handler can
never *abandon* the computation below it — no frame skipping, ever; when
"give up this whole subtree" is the right response, that is value propagation
(A) after a decline, or the full Option C machinery this subset deliberately
omits.

## 5. Option D — status codes + out-params, dignified by macros

The baseline the designer's list omits: keep doing what C does (int returns,
out-params, errno), and spend macros on the ergonomics (`check`-and-propagate
sugar). Zero compiler work, perfect C interop, and zero versatility gain — no
types, no narrowing, manual discipline throughout. Listed mostly so the table
has its floor; A2 dominates it on every axis except implementation effort,
and A2's effort is modest precisely because N1 built the machinery.

## 6. Tradeoff summary

| Option | C interop | Runtime overhead | Impl complexity | Versatility | Cleanup (`with`/`defer`/`Drop`) integration |
|---|---|---|---|---|---|
| **A2** error unions, niche-encoded (ptr payloads) | **Excellent** — a `!T` *is* a `T*` with a reserved range (existing C convention); exports/imports legible to C | Branch per check/`try`; zero where unused; same as handwritten C | **Low–moderate** — reuses N1's kind + narrowing machinery; `try`/`errdefer` macros; `deferror` table | Propagation + typed error sets in signatures; no resumption; weak on error *context* | **Free** — propagation is early `return`; cleanups already fire |
| **A1** generic `(Result T E)` | Good — by-value structs via stage-8 ABI; legible to C as tagged structs | Small-struct returns; pay-per-use; sret for large payloads | **Moderate, gated on sum types** ([unions.md](unions.md)) | A2 + arbitrary payloads, per-API error types | Free (same) |
| **B1** exceptions, sjlj | **Poor** — longjmp over C frames skips C cleanups; must not escape exported fns | `setjmp` per `try` on happy path; **mandatory** cleanup-chain cost in every fn using `with` | Moderate | Multi-frame transfer; invisible control flow | Broken without a runtime cleanup chain — which *is* the mandatory cost |
| **B2** exceptions, zero-cost tables | **Poor** — unwinding through/into C is UB-adjacent; abort-at-boundary needed | Zero happy-path cycles; table bloat; very slow cold path | **Very high** — invoke/landingpad everywhere, ×3 personalities (DWARF, 2× SEH) | Same as B1 | Requires landingpads re-emitting every cleanup, per target |
| **C** conditions + restarts (full) | Mixed — resumption is plain calls (C-safe); unwinding restarts inherit B's hazards | Pay-as-you-go (handler push/pop, signal walk) | **High** — library half moderate but hurt by no closures; unwind half = B | **Highest** — resumption, policy/mechanism separation, interactive recovery | Needs dynamic-extent unwind-protect; `defer` is lexical today |
| **C-lite** resumption-only | **Good** — no unwinding ever; signaling across C frames is safe | Pay-as-you-go | **Lowest** — pure library, today | Repair-or-die policy hooks; no non-local exit; complements A rather than replacing it (§4) | Unaffected |
| **D** status codes + macro sugar | Perfect (it *is* C) | Same as C | Trivial | Weakest — untyped, manual | Free |

## 7. Observations and a proposed direction

Not resolved — for the designer to decide — but the grading above points
somewhere specific:

1. **Both B variants conflict with two standing invariants** (zero mandatory
   cost; C-consumability of Nucleus libraries) and with the
   simplicity-of-implementation principle. They deliver nothing that `(try …)`
   propagation doesn't, except invisibility of the error paths. Recommend
   rejecting exceptions outright rather than deferring them.
2. **A2 is the natural next rung.** It is `Maybe` with a reason attached:
   same niche-encoding trick, same kind machinery, same narrowing engine, same
   migration playbook (opt-in, bootstrap byte-identical until converted), and
   its propagation rides the existing cleanup semantics. The compiler itself
   is the ideal first consumer — `die-at` sites in library-ish code
   (reader, coercion) could become `!T` returns, which is also what the REPL
   wants (today's `repl_throw` longjmp would become an ordinary error return
   path).
3. **Keep the second tier explicit:** `die`/`die-at` remains the
   panic-equivalent for bugs and unrecoverable states — abort, no unwinding
   (REPL boundary excepted, as today). Marking it `noreturn` is already the
   top friction item from N2 (nullability.md §9), so the two designs share
   their first piece of infrastructure.
4. **A1 should fall out of sum types**, not precede them; when sum types
   land, `(Result T E)` becomes a library type and A2's encoding becomes the
   niche optimization for the pointer case.
5. **C-lite is compatible with all of the above** and costs almost nothing to
   try as a library experiment once there's a use case (allocation-failure
   policy is the obvious one: arena exhaustion could signal before dying).
   §4 sketches the full library, the standalone shape, and the combined
   signal-then-propagate protocol with A2 — including sharing `deferror`
   values as the condition vocabulary. Full conditions/restarts should wait
   for closures and a dynamic-extent cleanup story, and can be re-evaluated
   then.

Open questions for the designer, if the A2 direction is taken: naming
(`Result`/`Err`/`!T` sugar — does `!` read acceptably given `!=`?); whether
error ids are one global set (Zig) or per-set declarations; composition with
`?T` (is `!?T` — "error, or none, or value" — allowed, as in Zig?); the
error-context answer (§2, weak spot 1); and the documented C-side encoding
contract for exported `!T` functions.


#### Designer

* With unions done, A1 should be unblocked. It's more general than A2 and avoids the weak spot, so it's my preferred version. A2 is deferred as a possible future optimization to use in special cases.
* `!` is good sugar here, and `!?` and `?!` should be allowed. They're useful, and having the interrobang as syntax is amusing.
* Error IDs are one global set. After we have namespaces, they should get namespaced.

I ilke C-lite a lot in concept, but the machinery at the error site is verbose and requires a deliberate opt-in. It would be more ergonomic and flexible if trying to return an error value checked for bound handlers and used them by default with an opt-out `err!` to bypass them and return the error value unconditionally. The default leaves it up to the caller whether to let an error propagate or handle it where it occurs.

The example then becomes

```lisp
(defn read-config:!Config (path:ptr)
  (let (raw:ptr (fopen path "r"))
    (when (= raw null)
      (return (err config-missing)))
    (return (parse-config (cast ref:FILE raw)))))
```

and a call with a handler bound to `config-missing` will try that handler before returning an error value.

This does mean the two mechanisms become complected a bit more than the original proposal, and C-lite probably can't stand alone as a library. 

#### Robot — response

Decisions recorded: **A1 is the version built** ([unions.md](unions.md) U1–U3
landed, so the gate is open); A2 is deferred alongside U4's niche layout as a
future optimization; `!` sugar adopted, `!?` and `?!` both legal; error ids
are one global set, namespaced when namespaces exist. The C-lite revision —
handler check as the *default* meaning of returning an error, `err!` as the
opt-out — is worked through in §11. It contains one genuine design problem
(typing the repair value, §11.2) whose proposed resolution shapes the
`with-handler` surface, so §13 ends with the rulings needed before
implementation. Sections continue the survey's numbering.

## 8. The vocabulary: `Err` and `deferror`

- **`Err` is a distinct scalar type, represented as `i32`.** Distinct (a
  builtin named type, not an alias) so target typing, `with-handler`, and
  U4's eventual rule-3 niche detection can key on it; `i32` so it is
  C-legible. Id 0 is reserved as "no error"; ids are assigned densely from 1
  in definition order.
- `(deferror config-missing "config file not found")` binds `config-missing`
  as a compile-time `Err` constant and registers `{id, name, message}` in a
  static descriptor table emitted into the binary. `err-name` / `err-message`
  are library accessors over the table; `unwrap` and the panic tier print
  through them.
- **Id cap 4095.** `deferror` dies past 4095 definitions. Free now, and it
  keeps every id inside the top-page range A2's ERR_PTR encoding needs, so
  the U4 rule-3 niche (`(Result (ref T) Err)` → tagged pointer) stays a pure
  layout optimization later — no renumbering, no semantic change.
- **Namespacing (per the directive).** When namespaces land, the *names*
  namespace like any global; the id space stays program-global and dense (it
  indexes the descriptor table and, post-U4, the niche range). Ids are
  assigned per program build and are not stable across builds — the name is
  the contract, the id is the representation. (Separately-compiled-and-linked
  Nucleus libraries would need link-time id reconciliation; out of scope
  pre-release.)
- **C export.** Constants as an enum/#defines plus the accessor
  declarations; an error crossing to C is an int with a documented meaning.

## 9. `!T` and the composition sugar

`(defunion (Result T E) (ok v:T) (err e:E))` moves from examples/unions.nuc
into the prelude. The sugar:

| Spelling | Expansion | Reading |
|---|---|---|
| `!T` | `(Result T Err)` | fallible value — T as written, by value for structs |
| `!?T` | `(Result (Maybe (ref T)) Err)` | error, or none, or value |
| `?!T` | `(Maybe (Result T Err))` | a fallible result that may be absent (§10) |
| `?T` | `(Maybe (ref T))` | unchanged |

Like `?`, `!` is recognized only in type-parsing positions
(`parse-type-name` recursion past the prefix char, exactly the `?`
mechanism), so there is no collision with `!=` — `!=` never occurs where a
type is parsed. The sugar is not just brevity: `name:(Result Config Err)`
does not parse (the U3 limitation on parenthesized types in colon
positions), while `name:!Config` does, so `!T` is what makes Result returns
usable in ordinary signatures.

One deliberate asymmetry, flagged for sign-off (§13): `?T` injects `(ref …)`
(its historical pointer-only meaning) while `!T` takes T as written — A1's
point is arbitrary payloads, so `!i64` must be `(Result i64 Err)`.
Consequently the composed `?!T` reads `?` as plain `(Maybe …)` over the
Result *value*, not as a pointer — the only sensible reading, since the
operand is already a complete value type. Long forms remain available; `!`
over a parenthesized payload (an error union over `(ref FILE)`, say) has no
sugar and is written `(Result (ref FILE) Err)`.

Surface forms — most already exist via U2/U3:

| Form | Status |
|---|---|
| `(ok v)` / `(err E)` in return position | U3 target typing, exists; `err` gains handler semantics in §11 |
| `(make (Result … Err) ok v)` | exists — the explicit spelling for non-return positions |
| `(err! E)` | new: unconditional error return, no handler check |
| `(try r)` | new — **a library macro**, expansion below |
| `match` | exists; the eliminator — no separate `if-ok` proposed (§13) |
| `(unwrap r)` / `(unwrap-or r d)` | extend the existing compiler forms to Result operands; `unwrap` dies printing `err-name`/`err-message` |

`try` needs no compiler support. Verified against `emit-cond` /
`emit-match-clauses`: a terminated clause contributes nothing to the join
phi, so a match whose err arm returns yields the ok arm's type:

```lisp
(defmacro try (r)
  (let (v (gensym) e (gensym))
    `(match ,r
       ((ok ,v) ,v)
       ((err ,e) (return (err! ,e))))))
```

The `(err! ,e)` re-wrap target-types against the *enclosing* function's
declared return, which is what lets `(try …)` cross from `!Config` into
`!App` — and is also why propagation never re-runs handlers (§11.3).
`(try r)` over a `!?T` yields `?T`, composing with the N1 narrowing forms
unchanged.

A2's `errdefer` is dropped from v1 — `defer` plus an explicit error path has
covered every case so far; reintroduce if adoption (E4) finds the pattern.

## 10. `(Maybe T)` over values — the gate `?!T` opens

nullability.md §1 deferred non-pointer `Maybe` to sum types; sum types exist
now. The prelude gains a `(defunion (Maybe T) (some v:T) none)`-shaped
template, and the parser's rejection of `(Maybe non-pointer)`
(src/nucleusc.nuc:1943) becomes a template stamp:

- `(Maybe (ref T))` keeps the N1 niche-encoded pointer — a parser special
  case until U4 makes it a layout rule;
- `(Maybe T)` for any other T stamps the two-arm `{tag, T}` union.

One spelling, two layouts — the convergence unions.md §6 anticipated; this
brings the spelling forward while the layout unification stays U4.

Scope is deliberately minimal: value-Maybe is eliminated with `match` and
constructed with `make` (or return-position target typing, where the
declared return type disambiguates `(some v)`/`none` from the pointer
relabels). The pointer forms — `if-some`/`when-some`/`unwrap`/`unwrap-or`,
`some`/`none` coercion outside return position — stay pointer-only in v1.
Beyond `?!T`, value-Maybe is the **decline channel for handlers**: a handler
returns `(Maybe T)`, `none` meaning "declined", which no longer needs a
reserved null and so lifts §4's "a repair may not itself be null"
restriction.

## 11. Handler-aware `err` — the complected redesign

Per the directive: returning an error checks bound handlers by default;
`err!` bypasses. The reading rule for the two spellings: **`err` means "give
up, unless someone above repairs"; `err!` means "give up."**

**11.1 Where the check attaches.** The check compiles in at exactly the
positions where return-position target typing already fires (U3): `(return
(err E))` and the implicit-return tail. There, `(err E)` means: find a
willing handler; if one repairs with `v`, the function returns `(ok v)`;
otherwise it returns the error value. In any other position `err` (or
`(make … err …)`, anywhere) is a bare constructor — a stored Result is data;
the negotiation happens only when a function *gives up*. The check is
emitted only when the error arm's type is `Err` — `!T`-shaped returns;
custom `(Result T MyErrStruct)` instances are plain unions with no implicit
machinery.

**11.2 The repair-typing problem and its resolution.** The repair becomes
the function's ok value, so a handler must produce the `T` of whichever `!T`
function it fires in — but binding is dynamic and `T` varies per site, since
the vocabulary is global (the same `parse-failed` returns from many
functions). Resolution: **handlers are keyed on the pair (error, repair
type)**. `with-handler` records the condition *and* a type token for the
repair type, read off the handler fn's declared return `(Maybe T)`; an err
site walks the chain matching its error id *and its own `T`*; only on a
double match is the stored fn pointer cast to `(fn (Maybe T) (ptr ptr))` and
called — the match is what makes the cast sound, without RTTI. The token is
the type's mangled-name string (pointer compare with strcmp fallback —
separate-compilation-safe). Handler returns ride the stage-8 struct ABI and
inherit its platform coverage. Consequence, stated as a feature: a handler
bound for `(config-missing, Config)` fires at `!Config` sites and is
invisible to a `!FILE` site returning the same error — which is what makes a
single global error set workable at all.

**11.3 Origin-only, once.** Handlers run where the error is constructed and
returned — the `err` site — not at propagation: `try` re-returns through
`err!`. One negotiation per fault, at the frame nearest the fault that has
the typed context; repeating the offer at every propagation frame would
re-ask the same question at ever-wronger types.

**11.4 The library/compiler split.** §4's pure library splits in two. The
`Handler` record `{what:Err, rty:ptr, hfn, ctx, prev}`, the chain global,
and the find-walk stay a small library (lib/error.nuc); `with-handler` is
the §4 macro unchanged (stack-allocate, link, `defer` the unlink) plus the
type token. But the **call side is compiler-emitted** at err sites — it
needs the site's `T` for the match, the cast, and the `(ok v)` re-wrap. The
CL unbind rule is kept: the emitted call saves/restores the chain top around
the handler, so an error inside a handler finds outer handlers only.

**11.5 `detail`.** `(err E detail)` — optional second argument, `ptr`,
passed to handlers and then dropped, never stored in the error value. This
recovers the context the explicit `signal` carried (the example above
dropped `path`; with this it is `(err config-missing path)`), under §4's
ownership convention: borrowed for the call.

**11.6 What the complecting costs, honestly.**

- **Resumption granularity moves from fault site to function boundary.**
  §4's handler repaired the *cause* (an alternate FILE handle; parsing
  continues); this design's handler supplies the *result* (a whole Config).
  Where fault-site granularity matters, factor the negotiable operation into
  its own `!`-returning function — an `(open-config (Result (ref FILE) Err))`
  whose handler supplies the handle — and the typing is automatic. The
  factoring pressure is real, but it points where the code should go anyway.
- **The standalone-policy shape is lost.** §4's arena case — `arena-grow`
  signaling `out-of-memory` and *continuing in place* with the repaired
  block, no error return anywhere — has no expression here unless the grow
  path itself becomes `!`-returning. If a use case demands
  signal-without-return, `signal` can be re-exposed over the same chain (the
  library half is unchanged); v1 does not provide it.
- **C-lite no longer stands alone**, as the directive anticipates: check
  emission, target typing, and the `Err`/`Result` types tie it to the
  compiler. The chain mechanics remain C-safe — handler invocation is still
  an ordinary call, and signaling across intervening C frames still works
  when the erring function is Nucleus.
- **Readability.** An `(err E)` return can now succeed. The site still reads
  linearly (the negotiation is at the `return`, not hidden in callees), but
  `err` no longer literally means "this function returns an error here" —
  hence the reading rule at the top of §11, and `err!` where the
  unconditional meaning is wanted.
- **Cost audit.** Happy path: zero — the check sits on the err return path
  only. Programs that never bind handlers: one global load + null compare
  per checked err return, on the error path. `err!` recovers exact zero.
  Bind/walk costs are confined to users, as before. This satisfies the
  zero-mandatory-cost invariant in spirit; the letter is one branch on a
  path already constructing a tagged struct.

**11.7 C interop of `!T` itself.** A `!T` crossing to C is the U2 tagged
struct plus the `Err` constants — fully legible. The known U3 gap applies:
`--emit-cheader` skips functions whose signatures mention template
instances, so exported `!T` functions need the instance-naming fix (e.g.
`nuc_Result_Config_Err`) before C callers get prototypes. Tracked under E4
if the exported surface adopts `!T`; otherwise it stays deferred with the
rest of the U3 note.

## 12. Staging

Each phase independently shippable, bootstrap byte-identical until a phase
deliberately converts code — the standing discipline.

| Phase | Content | Bootstrap |
|---|---|---|
| **E1** | `Err` + `deferror` + descriptor table + `err-name`/`err-message`; prelude `Result`; `!T`/`!?T` sugar; `try` macro; `unwrap`/`unwrap-or` over Result. No handlers yet, so `err` has no check to make. | byte-identical until something adopts `!T` |
| **E2** | Value-Maybe: `(Maybe T)` over non-pointers as a prelude template stamp; `?!T` sugar. | byte-identical |
| **E3** | Handler chain library + `with-handler` + compiler-emitted check at err returns + `err!`. From here `err` ≠ `err!`. | byte-identical until a handler exists |
| **E4** | Adoption: convert `die-at` sites in library-ish code (reader, coercion) to `!T` per §7.2 — the REPL's `repl_throw` boundary shrinks to true panics; cheader instance naming if the exported surface needs it. | byte-identical per step |
| *(later)* | Namespaced error names (post-namespaces); A2 via U4 niche layout — `(Result (ref T) Err)` becomes pointer-sized; §8's id cap already reserved the range. | — |

## 13. Open questions for the designer

1. **The `?` asymmetry (§9):** `?T` injects `(ref …)`; `?!T` reads `?` as
   value-Maybe over the Result. Accept as documented, or re-spell `?` as
   plain `(Maybe T)` uniformly at the safety flip (breaking, but the flip is
   already the breaking moment)?
2. **(error, repair-type)-keyed handlers (§11.2):** confirm — it makes the
   handler fn's declared return type load-bearing in `with-handler`, and
   gives the "same error, different sites, different handlers" behavior.
3. **`(err E detail)`** — optional transient detail pointer: in?
4. **`if-ok`:** proposal is *not* to provide it; `match` is the eliminator
   and is already two-arms-short. Object if the §2 table's spelling is
   wanted anyway.
5. **`errdefer`:** dropped from v1, reintroduced on demand — agreed?
6. **Standalone `signal`** (policy points with no error return — the
   arena-OOM shape): omitted from v1, recoverable later over the same chain —
   agreed?
7. **Id cap 4095** to keep A2's encoding reachable — agreed?

#### Designer

1. Add the safety flip to this pass and avoid the issue.

2. That's fine for now. I'm considering adding `dyn` to improve this, which would add cost to use, but calling error handlers shouldn't usually be on the hot path.

3. Yes, optional transient detail pointer.

4. `match` is good here.

5. Yes.

6. Omit `signal` for now.

7. The cap is fine for now.

#### Robot — implementation status

**E1 landed** (`make test` 69/69, `make bootstrap` fixed point holds). The build
spec is [errors-prompt.md](errors-prompt.md); status detail also lives in
[../progress.md](../progress.md) (stage 10 errors table); user-facing docs in
docs/builtins.md §"Error handling"; runtime coverage in `examples/errors.nuc`.
Implementation notes:

- **`Err` is a new type kind `TY-ERR`**, lowering to `i32` everywhere
  (`type-to-ir`/`type-size`/`is-int-type`/`int-width`/`abi-classify` treat it as
  a 4-byte signed int) but distinct under `type-eq` and mangling (`"Err"`), so a
  `(Result T Err)` is distinguishable from `(Result T i32)` for the E3 handler
  check. `Err`↔`i32` coerce freely in value positions (the `is-int-type` path),
  like `CStr`↔`ptr`.
- **`deferror` descriptor table.** Ids are dense from 1 (slot 0 reserved). The
  compiler accumulates `{name-sid, msg-sid}` and emits two `[N+1 x ptr]` arrays
  (`@nuc_err_names`/`@nuc_err_messages`) of `@.str` pointers at module assembly,
  **only when at least one deferror exists or an accessor is used** — so
  error-free programs (the compiler's own bootstrap included) are byte-identical.
- **`err-name`/`err-message` are compiler intrinsics, not library functions** —
  a deliberate deviation from §8's "library accessors". The build model makes a
  genuine library accessor impossible without friction: the table is emitted
  *conditionally* into the program module, but a `lib/error.nuc` accessor
  referencing it would need either an `extern` declaration (which collides with
  the in-module definition — verified: LLVM rejects decl+def of the same global)
  or an undeclared reference (also rejected). The intrinsic GEPs the table by
  element type, so it needs no length at the call site. Revisit if E3/E4 wants a
  first-class accessor (e.g. pass a base-pointer intrinsic to a library walker).
- **`unwrap` on a `Result`** branches on the tag: `ok` yields the payload; `err`
  prints `nucleus: unwrap on error <name>: <message>` via `printf` (required in
  scope — `(include stdio)`), `fflush`es, then `@llvm.trap`s. `unwrap-or` phis
  the `ok` payload against the default. The message goes to **stdout** for now
  (avoids the `@stderr` global-dedup problem); revisit with the panic-tier hook.
- **`!T` / signatures.** The `!` sugar in `parse-type-name` stamps
  `(Result <inner> Err)` from the prelude template, taking the payload as
  written. For `!T` to work in `defn` signatures (its whole point), the toplevel
  signature prescan had to see the prelude's `Result` — so **friction finding 2
  (prelude types in signatures) was pulled forward**: `prescan-imported-types`
  walks the import tree depth-first and registers imported struct names + union
  templates (names only, idempotent, no IR) before `prescan-defn-signatures`.
  This keeps the bootstrap byte-identical (verified) and also unblocks
  `ref:Node`/`?Node` in compiler signatures for the eventual flip.
- **`err!`** is handled in `union-target-rewrite` as the `err` arm with its `!`
  stripped (E1 has no handlers, so `err` == `err!`); E3 will split them by
  emitting the handler-chain check at the `err` site. `(err E detail)` is
  deferred to E3 (E1 takes the err arm's single `Err` field exactly).

**E2 landed** (`make test` 70/70, fixed point holds; `examples/value-maybe.nuc`):

- Prelude gains `(defunion (Maybe T) (some v:T) none)`. The parser's `(Maybe X)`
  block now dispatches on the payload: `(Maybe (ref T))` keeps the niche pointer
  (PTR-MAYBE in place), any other `X` stamps the value template (so the generic
  template-use path is told to skip `Maybe`). One spelling, two layouts.
- Value-Maybe is built with `make` / return-position target typing — `(some v)`
  rewrites like any arm, and **bare `none`** is special-cased in
  `union-target-rewrite` (it is a reserved keyword, never a user variable, so it
  can't shadow a binding; a niche-pointer return still gets the relabel because
  `uniondef-for-type` returns null for a TY-PTR). Eliminated with `match`.
- `?!T` is a dedicated prefix in `parse-type-name` (checked before plain `?`):
  it reads `?` as a *value* Maybe over the `!T` Result, per §10's "operand is a
  complete value type". `?Sym`-style niche pointers are untouched (they never
  begin `?!`). The pointer relabels (`some`/`none`/`as-ref`, `if-some`/etc.)
  remain pointer-only.

**E3 landed** (`make test` 71/71, fixed point holds, bootstrap byte-identical;
`examples/handlers.nuc`). What was built and the deviations:

- **Compiler half = one internal special form.** `union-target-rewrite` is the
  single chokepoint for both explicit `(return …)` and the implicit tail. When
  the returned form is a non-bang `(err E [detail])`, the enclosing return type
  is an `!T` (the `err` arm's single payload field has kind `TY-ERR` —
  `result-err-arm-is-err`), **and** the error library is in scope
  (`error-lib-in-scope`: `g-handler-top` + `err-find-handler` + the `Handler`
  struct all resolve), it rewrites to `(__err-handled E [detail])`. Otherwise
  `err` keeps the plain `(make … err …)` construct — identical to `err!`. The
  rewrite stays a pure node→node function; all IR is emitted by the new
  `emit-__err-handled` special form, where `scope` is available.
- **The negotiation (§11.1–§11.5)** is a value-expression of type
  `(Result T Err)`, `T = result-ok-type`. It builds `(err E)` **once** into a
  result alloca slot as the default (no handler / declined), then
  `h = err-find-handler(E, type-token(T))`; on a non-null `h` it applies the CL
  unbind rule (save `g-handler-top`, set it to `h->prev`), calls the handler,
  restores `g-handler-top`, and on `(some v)` overwrites the slot with `(ok v)`.
  The slot-default avoids a struct phi and re-evaluating side effects per path
  (E is a `deferror` compile-time constant in every real use, so building the
  err arm and passing E to the find-walk evaluates it twice harmlessly).
  Re-uses `emit-union-construct` for both `(ok v)` and `(err E)` (no synthesized
  `(Result T Err)` type node needed); `detail` is borrowed for the call and
  never stored.
- **The handler call rides the Stage-8 struct-return ABI** via
  `abi-emit-struct-call` (callee is the loaded `hfn` SSA value, arglist
  `"ptr %ctx, ptr %detail"`, `info = abi-classify((Maybe T))`), **not**
  `emit-funcall-value` — the latter emits an *uncoerced* struct-return call that
  mismatches the handler `defn`'s coerced `(Maybe T)` return. `(Maybe T)` is
  stamped in-compiler via `union-template-stamp-types` on the prelude `Maybe`
  template (`stamp-maybe-type`); the result is matched by reading its tag and
  loading the `some` payload. Limitation: a repair type that is itself a
  `(ref X)` (niche-encoded `(Maybe (ref X))`, a plain ptr not a struct) is not
  supported by the struct-call path — v1 repair types are value types.
- **Gating preserves byte-identical bootstrap.** The compiler imports no `error`
  and has no `err` sites, so `error-lib-in-scope` is false during self-compile
  and the rewrite never fires — stage1.ll == stage2.ll verified. `err` gains
  handler-awareness exactly when `(import error)` is present;
  `examples/errors.nuc` (imports error, binds no handler) is unchanged because
  `err-find-handler` returns null and the default `(err E)` stands.
- **Three incidental fixes the library half needed to actually run** (E1
  committed the `lib/error.nuc` macros before the compiler support, so they were
  dead/broken):
  1. **Macro/CT JIT modules now re-declare the ordinary program `defn`s a macro
     body calls** (e.g. `node-at` in `with-handler`). Such functions are
     `define`d only in the main module; the JIT module needs a local `declare`
     to resolve the symbol from the `-rdynamic` host binary. `emit-defn` records
     each main-module defn's signature (`g-program-defns`/`ProgDefn`);
     `emit-call-with-args` emits the declare into the JIT module's decl stream on
     first reference (`macro-jit-ensure-decl`, deduped per module). This also
     lifts the historical "`*Node` macros only work in the compiler" limitation.
  2. **`with-handler`'s binding spelling** changed from the typed-gensym form
     `~h:ptr:Handler` (the reader tokenizes a colon-typed gensym as one symbol
     and the type is lost) to the list form `((~h (ptr Handler)) …)`. Logic
     unchanged.
  3. **`(cast ptr <fn>)` / `(cast (fn …) <ptr>)`** are now a no-IR reinterpret
     in `emit-cast` (a function value is already `ptr` in opaque-pointer IR) —
     needed to type-erase a handler fn into `Handler.hfn:ptr`. `is-ptr-like` was
     left unchanged (broad widening would risk the bootstrap); the case is
     handled narrowly.

**Phase F (the safety flip) landed** (`make test` 71/71, `make bootstrap` fixed
point, all boot artifacts re-converged). Build plan and the full how is in
[flip.md](flip.md); status mirrored in [../progress.md](../progress.md),
[safety.md](safety.md) §5, and [nullability.md](nullability.md) §9.1. Headline:

- **A blocking self-compile crash was fixed first.** The Phase-F1 `noreturn`
  trailing-attribute probe in the `(declare …)` desugar (and the parallel
  `emit-nuch-declare-import` / `defn` body-position-0 sites) dereferenced the
  last node's `kind` without a null guard; an empty param list `()` reads as a
  null car (`node-at` returns null), so the compiler segfaulted compiling its own
  `(declare repl_try:i32 ())` — the examples use `include`, not explicit
  `declare`, which is why the test suite passed while self-compile died. Fixed by
  null-guarding all three probes. Leftover `TRACE` debug statements from the
  mid-flip session were removed.
- **Stage-1 (additive, byte-identical) groundwork:** the `(raw T)` / bare `raw` /
  `raw:T` spelling (PTR-RAW; new `ty-raw` singleton), colon-strings in
  `parse-type-name`, `?`/`!` prefixes on list-type heads (so the multi-colon
  desugar `?ptr:Node` → `(?ptr Node)` parses), and `?` niche-relabeling a pointer
  operand so `?ptr:Foo` ≡ the old `?Foo` (`TY-PTR(elem=Foo, MAYBE)`).
- **The flip:** `(ptr T)` / bare typed `ptr` are now non-null (PTR-REF); `null`
  is `raw`; `?` is uniform `(Maybe T)` (pointer operand → niche `?ptr:T`, value
  operand → value-`Maybe`). Two refinements keep the flip's teeth on **typed**
  pointers and avoid thousands of false positives: **CStr is ref-compatible**
  (string literals are non-null), and an **elem-less `void*` destination is
  exempt** (a non-null contract on a pointer with no pointee, that cannot be
  deref'd, protects nothing — the direct analogue of the CStr refinement). With
  both, the per-site conversion the plan budgeted (~329) collapsed to zero: every
  violation had a `void*` destination, and N2 had already typed the real
  pointer slots. `pkind` is ignored by `type-eq`/`hash-type`/mangling/`type-to-ir`,
  so the flip changed **no** emitted IR — the fixed-point bootstrap is the proof.

**Phase E4 (adoption — the reader) landed** (`make test` 71/71, `make bootstrap`
fixed point, all boot artifacts re-converged). The first real consumer of `!T`
is the compiler itself: the **reader pipeline** (`lib/reader.nuc`) no longer
aborts on a syntax error. This is the §7.2 direction — "`die-at` sites in
library-ish code (reader, coercion) become `!T` returns, which is also what the
REPL wants (today's `repl_throw` longjmp becomes an ordinary error return
path)."

- **What converted.** `lex-string`, `lex-atom`, `next-tok`, `peek-tok`,
  `eat-tok`, `read-form`, `read-list`, `read-program` now return `!ptr`
  (`(Result ptr Err)`). Every former `die-at` in the reader (unterminated
  string / list, unknown escape, literal-too-long, unexpected `)`, unexpected
  EOF) became `(do (report-at line msg) (return (err! parse-error)))`; internal
  reader calls propagate with `try`; success returns wrap with `(ok …)`. The
  reader `(import error)`s for `try` and declares one `(deferror parse-error …)`.
- **Diagnostics are byte-for-byte preserved.** `Err` carries only an id, not a
  line, so the human-readable message (with `g-source-path`:line and the
  `g-mono-context` note) is still printed *at the fault site* by `report-at` —
  `die-at` minus the `repl_throw`/`exit`. The propagated `parse-error` is purely
  the value-channel signal callers discriminate on. `err!` (not `err`) is used
  throughout, so no handler check is emitted — a syntax error is not a
  negotiable condition.
- **Boundaries.** The batch driver calls a new `read-program-or-die` wrapper
  (`match`; on `err`, `exit 1` — the diagnostic already printed, matching pre-E4
  behavior) at all three `nucleusc.nuc` read sites. The REPL (`repl.nuc`,
  macro-preload + main loop) `match`es `read-program` directly: on `err` it
  resets `g-peek-valid` and continues the session. This removed the reader's
  contribution to the `repl_throw` boundary — previously the main loop's read ran
  *outside* any `repl_try`, so a syntax error longjmp'd to a stale `jmp_buf`;
  now it is a clean value-path recovery (verified: `)` and `(foo` errors report
  and the session keeps evaluating).
- **`die-at` stays** the panic tier (still ~347 unrecoverable-bug sites). Only
  the reader's own recoverable calls moved to `!T`.
- **No codegen change**, so the fixed point held *without* a converge round —
  the change is entirely in what the reader/driver source does, not in `emit-*`.
  `(import error)` is now transitively pulled into the compiler (reader →
  error); this adds `g-handler-top`, `err-find-handler`, the `try`/`with-handler`
  macros, and a one-entry `deferror` descriptor table to the compiler binary,
  but activates no handler machinery (no non-`!` `err` sites exist in the
  compiler).
- **Not converted (future E4 increments):** the coercion path. `coerce-int-val`
  / `coerce-num-val` / `safe-coerce-val` already signal failure by returning
  `null` (not `die-at`); their real abort is `pkind-flow-check`, which is deep in
  the emit path and cascades through the whole code generator — a larger,
  separate adoption than the reader. The `--emit-cheader` template-instance gap
  (§11.7) is untouched because no *exported* surface adopted `!T`.

**Phase C1 landed (N2 cold-site cleanup, 2026-06-14)** (`make test` 71/71,
`make bootstrap` fixed point). The ~25 guarded `(cast ptr:Sym (scope-lookup …))`
nullable-launder casts in cold emitter paths (defvar/defconst/inc-dec/addr-of
emitters, gcheck/valid walkers, `src/repl.nuc`) were replaced with `?ptr:Sym`
bindings narrowed by their existing null-guards. Enabled by the Phase-F1
`noreturn die-at` annotation (now `die-at` is `noreturn`, so `(when (= sym null)
(die-at …))` narrows past the guard). Two deliberate hold-outs survive, both
outside the named clusters — the E3 `emit-err-handled` handler-chain lookups
(`err-find-handler` / `g-handler-top`), which are non-null by the
`error-lib-in-scope` precondition with no natural use-site guard; the casts there
are `§5`-audited "known valid" assertions. The legitimate non-lookup casts also
stay (pointer arithmetic over `(sc syms)` arrays; the `(.set! (cast ptr:Sym fsym)
noreturn 1)` field-stores). No surface change, no IR change — byte-identical
bootstrap. Documented as §9 finding 5 in
[nullability.md](nullability.md).

**Phase C2 landed (standalone `signal`, 2026-06-14)** (`make test` 71/71,
`make bootstrap` fixed point; `examples/signal.nuc`). Adds a
compiler-emitted special form `(signal E RepairType [detail])` — the
§4 / §13-Q6 "standalone policy query" that was explicitly deferred from E3. It
shares the extracted `emit-handler-call` core with `emit-err-handled`, so the
chain walk, the CL unbind rule, and the `(Maybe RepairType)` return are all
identical to the `err` path. Key distinctions from `(err E)`:

- Not tied to return position; may appear anywhere inside a function body.
- Returns `(Maybe RepairType)` directly (not wrapped in `(ok v)` or discarded).
- Does not require the enclosing function to return `!T`.
- `RepairType` is a type-position operand (parsed, not evaluated), identical to
  `with-handler`'s `type-token` argument.

Requires `(import error)` (hard-gated by `error-lib-in-scope`; a compile error
if the library is absent). The v1 limitation on value-type repair applies: a
`(ref X)` niche-pointer `RepairType` cannot be carried by the struct-return ABI
path.

**Phase C3 landed (panic-tier hook, 2026-06-14)** (`make test` 71/71,
`make bootstrap` fixed point). `unwrap` on a `Result` (the `emit-unwrap-result`
panic path) now calls `emit-handler-call(unhandled-error, i32, msg)` — the same
handler-chain walk `signal` uses — before printing the error message and
trapping. A handler bound on `unhandled-error` receives the message string
as `detail` (type `i32` for the repair type, which is discarded: the trap
happens regardless). Gating: fires only when `error-lib-in-scope` is true *and*
`unhandled-error` is resolved as a `deferror` constant — so a program without
`(import error)` or without a `(deferror unhandled-error …)` declaration pays
nothing (byte-identical). The hook is a no-op when no handler is bound; its
value (the allocator policy shape from §4) is logging and diagnostics before the
abort, not prevention of it. The niche-ERRPTR `unwrap` path (`emit-unwrap-niche-errptr`)
carries the same hook.

**Phase C4 / A2 landed (niche layout engine, 2026-06-14)** (`make test` 71/71,
`make bootstrap` fixed point; `examples/errptr.nuc`; `tests/layout/` niche gate).
The U4 niche layout rules from §6 are fully implemented. Concretely:

- **`(Result (ref T) Err)` over a typed payload** (`!ptr:T` in sugar) is
  `LAYOUT-NICHE-ERRPTR`: pointer-sized, C-ABI-identical to `T*`. The ERR_PTR
  encoding: `(ok p)` stores `p` directly; `(err E)` emits
  `inttoptr(0 - zext(id))`, placing the error id in the reserved top page
  (ids 1..4095, enforced by `deferror`'s cap). `is-err` is one unsigned compare
  against `0 - 4096`. All elimination forms (`match`, `try`, `unwrap`,
  `unwrap-or`) accept a niche-ERRPTR value and dispatch through the encoding
  transparently.
- **`(Maybe (ref T))`** (rule 2, `LAYOUT-NICHE-MAYBE`) was already the N1
  niche; C4 unifies it under the same `union-layout-classify` engine so both
  niche kinds are driven by one decision function.
- **`&repr tagged`** on a `defunion` forces LAYOUT-TAGGED unconditionally —
  the `{i32 tag; union payload}` struct, even for arms that would otherwise
  qualify for a niche. Use it when a C consumer needs the predictable struct
  layout.
- **`&repr niche`** requires a niche and emits a compile error if the arms do
  not qualify (not two arms / no typed `ref` arm). Optional; the layout engine
  applies niches automatically when arms qualify.
- **Elem-less `ptr` payloads do not qualify for niche rules 2/3.** This keeps
  the compiler's own `!ptr` (`(Result ptr Err)` with no `elem`) in
  LAYOUT-TAGGED, preserving the byte-identical bootstrap.
- **The §8 id cap (4095)** already reserved the full top-page range the
  ERRPTR encoding needs; no renumbering or semantic change.
- Full status in [unions.md](unions.md) robot section and [../progress.md](../progress.md);
  user-facing documentation in docs/builtins.md §"Unions and tagged sums" (niche
  layout + `&repr`) and §"Error handling" (pointer-sized `!ptr:T` contract).
