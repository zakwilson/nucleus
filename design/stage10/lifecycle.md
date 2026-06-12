# Stage 10 — Pointer lifecycle (`with`)

Expand `with` from "auto-free libc allocations" into a compile-time-verified
lifecycle: a resource created in a `with` may not outlive it. See
[safety.md](safety.md) for the umbrella and resolved decisions.

## 1. Where `with` is today

`emit-with` (src/nucleusc.nuc:4287) is `emit-let` plus, for any binding whose
init `is-libc-alloc` (src/nucleusc.nuc:4178) recognizes as `malloc`/`calloc`/
`realloc`/`strdup` (optionally through `cast`), a **cleanup slot** pushed onto
the `Scope` (`cleanup-slots`/`ncleanups`, src/nucleusc.nuc:94). `free` is emitted
in reverse order on fall-through (`emit-scope-cleanups`, :4198) and on early
`return` (`emit-walk-cleanups` from `emit-return`, :4214/:4220). A binding is
disarmed by storing `null` to it (`free(NULL)` is a no-op) — which is *also* the
current, unsafe way to smuggle a pointer out of the scope.

Two gaps: cleanup is recognized by **allocator spelling** (closed, brittle), and
nothing stops the freed pointer from **escaping** (return, store into outer
memory, alias). This spec closes both.

## 2. The escape model

Define, per `with`:

- **Owning binding** — a `with` binding that arms a cleanup (today: a libc-alloc
  init; after §5: any `Drop`-conforming init). Its storage will be freed at
  scope exit, so any pointer that still *aliases that storage* when the scope
  exits is a dangling pointer.
- **Tainted value** — a value statically known to alias an owning binding's
  resource.

The designer's stated rules — "returning the pointer is an error; binding a
second variable via nested `let` is an error; **returning the dereferenced value
is permissible**" — are exactly a taint/escape analysis. We formalize it.

### 2.1 Taint sources

A reference to an owning binding name is tainted.

### 2.2 Propagation — taint follows pointer *identity*, not pointee *contents*

Walking the body forward, taint flows through identity-preserving operations and
is **copied into** any binding initialized from a tainted value:

| Form | Taints result? | Rationale |
|---|---|---|
| `(let (q … p))`, `(with (q … p))`, `(set! q p)` | yes (q ← taint of p) | q now aliases the resource (covers the nested-`let` case) |
| `(cast U p)` | yes | reinterpretation, same address |
| `(ptr+ p k)` | yes | interior pointer into the resource |
| `(addr-of (p field))` | yes | interior address into the resource |
| `(deref p)` | **no** | copies the pointee *value* out |
| `(p field)` / `(get p field)` yielding a value | **no** | copies a field value out — *even if that value is itself a pointer* (see §2.4) |

So `(return (deref p))` and `(return (p count))` are fine; `(return p)`,
`(return (cast ptr p))`, `(return (ptr+ p 1))`, `(let (q p) (return q))` are not.

### 2.3 Escape sinks (error if the operand is tainted)

- **`return`** of a tainted value → *"resource bound by `with` escapes via
  return"*.
- **Store into longer-lived memory**: `(set! outer tainted)` where `outer` is
  bound outside the owning `with`'s scope or is a global; `(aset! a i tainted)`;
  `(.set! s field tainted)` / `(set! (s field) tainted)` where the target is not
  a same-or-inner-scope stack local. Conservative sound rule: *storing a tainted
  value anywhere other than a same-or-inner-scope local slot is an escape.*
- **Manual `free`/`drop`** of an owning binding → *"double free: binding is freed
  at scope exit; use `move` to transfer ownership"* (the cleanup will fire).

### 2.4 The one honest gap: passing to functions, and loaded pointers

Two deliberate, documented imprecisions keep the analysis cheap (intraprocedural,
`node-type`-shaped) and false-positive-free:

1. **Arguments are borrows (Tier 1).** Passing a tainted value as a function
   argument is **allowed**. The compiler can't know whether a callee retains the
   pointer, and forbidding all passing would reject `(printf "%p" p)`. The
   residual risk — a callee that squirrels the pointer into a global — is exactly
   C's risk and no worse; `with` still guarantees no-leak and no-use-after-free
   *within the lexical scope*. Ownership transfer to a callee is handled
   explicitly by `move` (§4).
2. **Loaded pointers are under-tainted.** A pointer *value stored inside* the
   resource and read back via `(p field)` is not tainted (per §2.2). Tightening
   this needs real points-to analysis; the deliberate gap is what makes
   "returning the dereferenced value is permissible" hold without it.

These are the boundary of the cheap tier, stated plainly rather than papered
over.

## 3. Implementation: a taint pass in `node-type`

The analysis is a forward walk over a `with` body, carried alongside the existing
type walk so it cannot drift from codegen:

- Extend the per-scope state with an **owned set** (binding names with armed
  cleanups; already implied by `cleanup-slots`) and a **taint set** (names
  currently aliasing an owned resource).
- For each body form, in order: classify per §2.2 to update the taint set; check
  per §2.3 to raise `die-at` on an escape, attributing the error to the offending
  form's line (the error-attribution machinery from Stage 9 cleanup applies).
- Nested `with`/`let` push a child frame; a name resolves to "outer" (escape
  target) iff it is bound in a strictly enclosing scope relative to the owning
  `with`.

This runs as a checking pass; emission is unchanged. L1 needs **no
representation change** and **no new surface** — it is pure analysis over the
existing `with`.

## 4. `move` — principled ownership transfer (Tier 2, phase L3)

Today, smuggling a resource out of a `with` means `(set! p null)` to disarm the
cleanup, then returning a separately-saved copy — silent and error-prone. Replace
it with an explicit form:

```
(move p)
```

`move`:
1. **disarms** `p`'s cleanup slot (store `null`, reusing the existing
   `free(NULL)`-is-safe disarm),
2. **clears taint** on the yielded value so it may legitimately `return` or store
   into outer memory, and
3. marks `p` **consumed** — any subsequent use of `p` is a compile-time error
   (*"use after move"*).

This is the safe primitive for "allocate here, hand ownership to the caller":

```
(defn make-node:(ref Node) ()
  (with (n:(ref Node) (new Node))      ; armed for cleanup
    (.set! n kind NODE-SYM)
    (return (move n))))                ; ownership leaves with the value; no free
```

`move` is *not* a borrow checker — it is affine ownership transfer at the two
points that matter (return, store-out). It pairs with the double-free check in
§2.3: once `with` knows the owned set, manual `free`/`drop` of an owned binding
is rejected, and `move` is the sanctioned way to opt out.

## 5. `Drop` — generalizing cleanup beyond libc (phase L2)

Replace the spelling-based `is-libc-alloc` with a Stage 9 protocol:

```
(defprotocol Drop (drop:void (self:Self)))
```

`with` arms a cleanup for any binding whose declared type conforms to `Drop`,
emitting `(drop binding)` (a static dispatch — zero overhead) at scope exit
instead of a hardcoded `free`. Benefits:

- **Extensible.** File handles, locks, arenas, sockets — anything with a `drop`
  becomes `with`-manageable. `with` stops being malloc-specific.
- **The libc allocators become one built-in instance.** A small `unsafe/`-named
  resource library wraps a raw allocation in a `Drop` type whose `drop` calls
  `free`; the compiler keeps the current libc fast-path as that instance so
  existing `(with (p (malloc …)) …)` code is unaffected during the transition.
- **`defer` falls out.** A `(defer expr)` that registers `expr` as an ad-hoc
  cleanup on the enclosing scope is the same machinery without a binding — useful
  for `(defer (fclose f))`-style pairs the allocator model can't express.

The escape analysis (§2) is unchanged by `Drop`: "owning binding" simply becomes
"`Drop`-conforming binding constructed in this `with`."

## 6. Staging recap

| Phase | Content | Surface change | Bootstrap |
|---|---|---|---|
| **L1** | Escape/taint analysis over existing `with` (§2–3) | none | byte-identical |
| **L2** | `Drop` protocol + libc instance + `defer` (§5) | `defprotocol Drop`, `defer` | byte-identical (libc fast-path retained) |
| **L3** | `move` / consume + double-free check (§4, §2.3) | `move` | byte-identical until code adopts it |

## 7. Worked examples (target diagnostics)

```
; ERROR: resource bound by `with` escapes via return
(defn leak:(ref Node) ()
  (with (n:(ref Node) (new Node))
    (return n)))                 ; n is owned; return is an escape sink

; ERROR: use `move` to transfer ownership (double free otherwise)
(defn oops:void ()
  (with (n:(ref Node) (new Node))
    (free n)))                   ; manual free of an owned binding

; OK: dereferenced value copies out
(defn first-kind:i32 ()
  (with (n:(ref Node) (new Node))
    (return (n kind))))          ; field value, not an alias — permitted

; OK: ownership transferred out
(defn make:(ref Node) ()
  (with (n:(ref Node) (new Node))
    (return (move n))))          ; cleanup disarmed; n consumed
```

## 8. Implementation status (landed 2026-06-12)

All three phases are implemented; `make test` and `make bootstrap` pass.

### L1 — escape/taint analysis — done
Taint is the owning with-`Scope*`, carried on `Val` (per value) and `Sym` (per
binding), seeded when `emit-with` arms a cleanup (`owns`/`cslot`/`taint` on
the binding's `Sym`). It propagates per §2.2 through binding init
(`let`/`with`), `set!`, `cast`, `ptr+`, `.&`, `addr-of`, and `cond` joins
(`taint-merge` keeps the deeper scope); value-copying ops (`deref`, field
loads, calls) start clean. Sinks per §2.3: explicit **and implicit** `return`;
`set!` to a binding whose home scope does not descend from the owning scope;
`aset!`/`.set!`/`ptr-set!` stores where the target memory is not owned by the
same-or-inner `with` (`taint-store-check` — untainted targets are
conservatively rejected, slightly stricter than §2.3's "same-or-inner local
slot"); and manual `(free b)` / `(drop b)` of an owning binding. One deviation
from §3's sketch: the checks run in the emitters, not a separate `node-type`
walk — the state lives on `Sym`, which the type pass shares, so the two
cannot drift.

### L2 — `Drop` + `defer` — done
`with-drop-method` arms a cleanup for any binding whose declared type is a
pointer to a struct with a recorded `Drop` conformance and an exactly
resolvable `drop` method (`type-eq` ignores pointer kinds, so `(ref S)`
resolves the same method as `(ptr S)`). `emit-drop-cleanup` emits a
null-guarded static call, so `move` / `(set! b null)` disarm Drop resources
exactly like libc ones; the libc spelling fast path is unchanged. Cleanups are
a tagged `Cleanup` record (free / drop / defer shapes). `(defer expr)`
registers on the enclosing binding scope and is re-emitted at every exit path —
including `let` fall-through and the function's implicit-return fall-off,
which now fire scope cleanups too. **`defer` is lexical, not dynamic**: it
runs at scope exit even if control never reached the defer site at runtime.

### L3 — `move` / consume — done
`(move b)` requires an owning binding; it loads the value, stores `null` to
the cleanup slot, marks the `Sym` consumed, and yields the value with taint
cleared. `emit-symbol-ref` rejects reads of a consumed binding ("use after
move"); a reassignment revives it. The §7 worked examples produce the designed
diagnostics verbatim; the success cases are in the test suite as
[examples/with-lifecycle.nuc](../../examples/with-lifecycle.nuc) and
[examples/drop-defer.nuc](../../examples/drop-defer.nuc).
