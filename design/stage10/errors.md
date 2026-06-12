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
