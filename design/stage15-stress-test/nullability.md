# W6 — Nullability flow typing (design only)

**Finding:** §3.3. Also touches §3.4 (a `let` local bound to `null` is inferred
raw) and §1.1's cousin problem of `unsafe/cast` overuse.

**This item is a design document, not an implementation.** Produce the design;
implement in a later stage. The reason for the split is that the cheap version of
this feature is worse than nothing — see "Why not just narrow" below.

---

## The problem

Nucleus distinguishes non-null `ptr`/`ref` from explicitly-nullable `?T`/`raw`.
That is one of the language's stated advantages over C
(`design/overview.md`, "Language features"). But there is no flow-sensitive
narrowing, so:

```lisp
(when (!= expr null)
  (let (s:ptr:Sector expr) …))     ; dies
```

→ `assignment: raw pointer where non-null (ref …) is required — launder with
(as-ref …) + narrowing, or assert with (unsafe/cast (ref T) …)`

The guard is *right there*, one line above. Every such site needs
`(unsafe/cast ptr:T expr)`.

### Why this is worse than it looks

The Doom port hit this constantly — nullable back-pointers are everywhere in the
engine (`Line.frontsector`/`backsector`, `Mobj.target`, sector `specialdata`), and
they are **genuinely nullable in the original**, so the modeling is correct. In
`p_setup.nuc`'s `P_GroupLines` alone it recurs at every sector/line/side
back-pointer binding.

The consequence is not verbosity. It is that **a justified assertion and a genuine
unchecked bypass are written identically.** After a few hundred of them, `grep
unsafe/cast` no longer distinguishes "I checked this on the line above" from "I am
asserting something I have not verified" — which destroys the auditability that
having the `ptr`/`raw` distinction was supposed to buy. Stage 14's
`unsafe/` namespace work (`design/stage14/unsafe-namespace.md`) exists to make
unsafe operations *visible*; §3.3 is the largest source of noise in exactly that
signal.

## Why not just narrow

The naive fix — "if the condition is `(!= x null)`, treat `x` as non-null in the
`then` branch" — is unsound the moment `x` can change between the check and the
use:

```lisp
(when (!= (mo target) null)
  (some-call-that-may-clear-target mo)
  (let (t:ptr:Mobj (mo target)) …))     ; narrowing here would be WRONG
```

A field read is not a stable value. Neither is a global, nor a local that is
`set!` in the branch, nor anything reachable through a pointer a call could
mutate. C++'s and Rust's analogues both restrict narrowing to values the compiler
can prove stable, and the interesting design content is exactly where that line
goes.

**A narrowing rule that is unsound in the common case would be worse than the
current explicit cast**, because it would silently produce the null-deref the type
system exists to prevent. Hence: design first.

---

## What the design document must decide

1. **What can be narrowed.** A minimum viable set worth considering:
   * an immutable local (`let`-bound, never `set!` in scope) — clearly safe;
   * a parameter, same condition;
   * a **field read** — the hard and most valuable case, since it is what the port
     actually needs. Under what conditions? "No intervening call and no
     intervening store through any pointer" is sound but very restrictive; decide
     whether that restriction still covers the port's real sites (check
     `p_setup.nuc`'s `P_GroupLines` and `p_map.nuc` — most guards are immediately
     followed by the binding, which suggests yes).
2. **What syntactic forms establish a narrowing.** `(!= x null)` and `(= x null)`
   as `when`/`if`/`cond` conditions; the `and`-chain case
   (`(and (!= a null) (!= (a b) null))`); early-return guards
   (`(when (= x null) (return …))` narrowing the *rest of the body*, which is the
   dominant C idiom and probably the highest-value form).
3. **How it interacts with `if-some` / `match`.** Nucleus already has `if-some`
   and `?T` matching; those are the "blessed" narrowing paths today. Is
   flow-narrowing an alternative or a shorthand that desugars to them? Prefer
   desugaring if it works — less new machinery, and the semantics are already
   settled. Note `(Maybe ptr)` is niche-encoded and pointer element types cannot
   `match` (a known Stage 11 limitation) — check whether that blocks the
   desugaring route.
4. **How narrowing is invalidated.** Any `set!` of the narrowed name; any call
   (conservatively) for a field read; any store through a pointer of a compatible
   type. Spell out the conservative default and what could relax it later.
5. **Diagnostics.** When narrowing *does not* apply, the error must say why —
   "`(mo target)` is a field read and `foo` was called since the null check, so it
   is no longer known non-null" is the difference between a feature and a puzzle.
   This matters more than the narrowing itself.
6. **Whether §3.4 is the same feature.** A `let` local bound to `null` is inferred
   raw, so a later field write fails (**at line 0** — W4 fixes the location).
   Globals allow `defvar- g:ptr:T null`; locals do not. Decide whether that
   asymmetry is intentional. If a local's type can be declared explicitly and the
   `null` init accepted (as globals do), §3.4 dissolves without any flow analysis
   and should be split out as a separate cheap fix rather than waiting on W6.
   **Check this first — it may be a 10-line fix mislabeled as a hard problem.**

## What the document must contain

* The narrowing rule, precisely, with the stability conditions.
* Worked examples of accepted and rejected narrowings, including at least three
  real sites from the Doom port (`/home/zak/code/nuc-doom-claude/src/p_setup.nuc`
  `P_GroupLines`, and two from `src/p_map.nuc`), showing what each becomes.
* The desugar-to-`if-some` analysis and its verdict.
* The invalidation rules.
* The diagnostic text for the "cannot narrow here" cases.
* An implementation sketch naming the passes/files it would touch (`node-type` and
  the emit-side coercion chokepoints at minimum — and note the
  `node-type`↔`emit-node` lockstep discipline in `context/conventions.md`, since a
  narrowing known to one and not the other is exactly the W2 bug class).
* An explicit **non-goal** list. Full dataflow analysis, nullability
  *inference* across function boundaries, and `?T` monad ergonomics are all out.

## Accept criteria

* `design/stage15-stress-test/nullability.md` (this file) is replaced by, or
  expanded into, the full design per the list above.
* Referenced from `design/overview.md`'s document list.
* Concrete enough to be the source of truth for a later implementation prompt —
  the standard this repo already applies to design-only items
  (cf. `design/stage11/assoc-types.md`).
* §3.4 is triaged: either dissolved as a cheap independent fix (with a note here
  and the fix landed under W5), or confirmed as genuinely part of this feature.
* **No implementation.** If you find yourself editing `src/`, stop — the only
  exception is a §3.4 fix if item 6 concludes it is independent.
