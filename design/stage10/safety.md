# Stage 10 — Safety

#### Designer

Nucleus is not trying to be Rust, but it does seek to be safer than C without
breaking C compatibility or incurring mandatory runtime costs. Two areas:

1. **Pointer lifecycle.** The `with` form (stage 6) is `let` plus auto-free for
   any binding whose init is a libc allocator (`malloc`/`calloc`/`realloc`/
   `strdup`, including through `cast`). It prevents leaks but allows dangling
   pointers. Its functionality should expand to enforce a lifecycle on all
   pointers it creates, verified at compile time. **A pointer escaping `with`
   should be a compile-time error.**

2. **Nullability.** It would be great if most types and pointers could be
   non-nullable, with a `Maybe`/`Option` type providing explicit nullability
   where desired. Better still: safe pointers by default that cannot point to
   anything but a valid instance of the declared type, manipulated only through
   facilities that enforce that rule. Raw pointers must remain available, but
   making their use an edge case rather than the default would greatly improve
   safety.

#### Robot — response

The architecture already carries most of what this needs. `node-type`
(src/nucleusc.nuc:1019+) is a non-emitting pass that mirrors codegen to compute
types without producing IR — the natural host for a compile-time escape /
null-flow analysis. Stage 9's protocol + multimethod + bounded-generic engine
gives compile-time dispatch with zero runtime cost, so `Maybe`, safe accessors,
and a `Drop` cleanup protocol can be ordinary library types the compiler merely
*checks*. And every safe representation here is **C-ABI-identical** to a plain
pointer, so "safer than C" costs nothing at runtime and nothing at the boundary.

This is the umbrella. The two workstreams are specified in:

- [lifecycle.md](lifecycle.md) — the `with` lifecycle: a `Drop` protocol that
  generalizes the hardcoded libc-allocator detection, plus an escape/taint
  analysis in `node-type` that makes a pointer escaping `with` a compile-time
  error, with an explicit `move` for legitimate ownership transfer.
- [nullability.md](nullability.md) — `(ref T)`, an opt-in **non-null** pointer
  (C-ABI-identical to `T*`), and `(Maybe (ref T))` / `?T` for explicit
  nullability (niche-encoded as the raw pointer, null = none), with flow
  narrowing so the compiler's own `(when (= x null) …)` idioms *are* the
  narrowing mechanism.

## 1. The spine: safe by default, raw at the edges

The organizing idea is to treat the unchecked operations as a named frontier:
`cast`, bare `ptr`, `ptr+`, unchecked `aref`/`aset!`, manual `free`, and the
`funcall-ptr-*` family are where you sign the waiver. Everything else gets
checked.

**Resolved (see §3): `unsafe` is a naming convention, not an enforced lexical
construct, in this stage.** The genuinely dangerous helpers are gathered under
an `unsafe/`-named namespace / library so that reaching for them is greppable
and auditable, but there is no compiler-enforced `(unsafe …)` block yet. The
*safety* comes from the checks in the two specs; the *convention* gives the
audit trail. A first-class enforced `unsafe` boundary is left as a future option
once the checks have proven out and we know where the raw ops genuinely cluster.

## 2. Two workstreams, one set of invariants

Both specs hold to the same invariants, which are also the project's standing
constraints (overview.md, AGENTS.md "Pre-release"):

- **Zero mandatory runtime cost.** Non-null pointers and niche-encoded
  `Maybe`-of-pointer lower to IR `ptr`; the only runtime cost is a branch at an
  explicit `unwrap`/narrow, paid solely where nullability is opted into. Escape
  analysis and `Drop` arming are compile-time.
- **C-ABI neutrality.** A `(ref T)` *is* a `T*`; a `(Maybe (ref T))` *is* a `T*`
  with `null` meaning none. C functions keep returning raw, nullable `(ptr T)`;
  values are laundered into the safe world through checks.
- **Raw escape hatches preserved.** `(ptr T)` / bare `ptr` / `cast` keep their
  current meaning unchanged for the entire transition. Nothing in stage 10
  forces existing code to change.
- **Library where possible, compiler where necessary.** The `Drop` protocol, the
  libc `Drop` instance, and the `Maybe` transition forms live in libraries
  (Stage 9 makes this free); the compiler supplies only the *checking*
  (escape/taint, null-flow narrowing) and the pointer-kind representation.

## 3. Resolved decisions (2026-06-09)

| Decision | Resolution |
|---|---|
| **Scope of Stage 10** | Lifecycle **and** nullability — the two areas above. Bounds-checked slices, `const`/read-only pointers, and sum-types+`match` are noted as adjacent follow-ons but are **out of scope** here (tracked in [../stage999-future.md](../stage999-future.md)). |
| **Non-null rollout** | **Opt-in spelling first, flip later.** Introduce `(ref T)` as a new non-null pointer type; `(ptr T)` keeps today's raw/nullable meaning so the bootstrap is untouched. Convert the compiler to `(ref T)` incrementally (leaning on its existing null-guards for narrowing). The eventual **flip** — making `(ptr T)` itself mean non-null and retiring raw to an `unsafe`-named spelling — is deferred to a later stage and decided with conversion data. Mirrors the Stage 9 byte-identical-bootstrap discipline. |
| **`unsafe` frontier** | **Naming convention only.** Relegate raw ops to an `unsafe/`-named namespace/library; no enforced lexical `(unsafe …)` block in this stage. |

## 4. Staging

The two workstreams interleave; each phase is independently shippable and
preserves a byte-identical bootstrap until a phase deliberately converts code.

1. **L1 — escape analysis on existing `with`.** Pure `node-type`-hosted taint
   analysis over `with` bodies; makes a `with`-owned pointer escaping via
   `return` or a store into longer-lived memory a compile-time error. No new
   surface, no representation change. Closes the dangling-pointer hole the
   designer named, at near-zero false-positive cost. *(See lifecycle.md §2–4.)*
2. **N1 — `(ref T)` + `Maybe` + narrowing.** Add the non-null pointer kind, the
   `(Maybe (ref T))` / `?T` nullable kind, the transition forms
   (`if-some`/`when-some`/`unwrap`/`unwrap-or`/`some`/`none`), and flow narrowing
   in `node-type`. `(ptr T)` unchanged. *(See nullability.md §2–5.)*
3. **L2 — `Drop` protocol.** Generalize `with`'s libc-allocator special-case to a
   `Drop` protocol; the libc allocators become one built-in `Drop` instance.
   Enables user resources (fds, locks, arenas) and a `defer` for ad-hoc cleanup.
   *(See lifecycle.md §5.)*
4. **N2 — convert the compiler to `(ref T)`** where pointers are known-non-null,
   measuring friction. *(See nullability.md §6.)*
5. **L3 — `move` / consume.** Principled ownership transfer that disarms a
   binding's cleanup and forbids further use — the safe replacement for today's
   `(set! p null)` disarm — plus a double-free check. *(See lifecycle.md §4.)*
6. **(Later stage) — the default flip.** Reinterpret `(ptr T)` as non-null;
   retire raw to an `unsafe`-named spelling. Decided with N2 data.

## 5. Implementation status

Pending — design only. Update this section as phases land (mirror the Stage 9
docs' per-rung status tables).
