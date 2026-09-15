# The compiler's exported surface, as an API rather than an accident

**Status: deferred, no plan.** Raised 2026-09-15, out of
[overview.md](overview.md)'s "Nothing in `lib/` may reach into the compiler's
exported surface" and the fourth bullet of
[../stage20-macros/macro-call-linking.md](../stage20-macros/macro-call-linking.md)
§10. Not scoped to a stage.

---

## 1. Why the rule is not the end state

The rule reads: `-rdynamic` exports 2,285 symbols from `build/nucleusc`, 1,658
of them spelled as ordinary lowercase-hyphenated Nucleus identifiers, and no
library file may name any of them.

It is the right defensive rule and the wrong permanent one, for two reasons the
rule itself names:

* **The forbidden examples are the useful ones.** `macroexpand-form`,
  `desugar-form` and `find-macro` are cited as what must not be touched, and
  they are exactly what a macro-expansion tool, a formatter or a linter would
  reach for. The rule forbids tooling and accidental capture in the same breath.
* **It is already load-bearing in the other direction.** `node-at` in
  `lib/error.nuc`'s `with-handler` works *because* the compiler links
  `lib/node.nuc`. §1.4 of macro-call-linking says the quiet part: nothing
  distinguishes that legitimate use from the mode-3 collision.

## 2. Three facts any fix has to start from

1. **Nothing enforces the rule.** There is no audit unit and no compiler check.
   `lib/` names none of the three cited symbols today, and nothing in the build
   would notice if it did.
2. **Stage 20 L4 gave the rule teeth it did not have when it was written.**
   Provenance is `from-lib ∧ host-exports?`
   ([../stage20-macros/macro-call-linking.md](../stage20-macros/macro-call-linking.md)
   §3.1), so a `lib/` file that spells one of the 1,658 now resolves to *the
   compiler's* definition — and cannot shadow it with its own. The rule is no
   longer style advice; it is what stops a library being silently captured.
3. **`host-exports?` (`src/nucleusc.nuc:1444`) is the hinge, and it asks the
   running binary.** So anything that narrows the export set narrows provenance
   for free: a hidden name stops resolving to the host and routes to the
   program's own definition, which is the behaviour you would want anyway. The
   visibility change and the semantic change are the same change.

## 3. The cut that makes this tractable

The minefield is overwhelmingly **`src/`** names — `desugar-form`,
`find-macro`, `in-jit-module`. The names libraries legitimately need are
**`lib/`** names — `node-at`, `alloc-node`, `intern-symbol`, `make-cell`.

And `-rdynamic` cannot simply be dropped: the REPL resolves JIT-compiled code
against the process's exports (see
[../stage16-ergonomics/repl-jit-symbol-precedence.md](../stage16-ergonomics/repl-jit-symbol-precedence.md)),
so some set has to stay exported regardless — at minimum §3.2's compile-time
runtime, whose whole point is that one arena, one intern table and one `Node`
layout serve the entire compilation. **Exactly what a REPL session's code
resolves from the process is the first thing to measure**, because it sets the
floor.

That gives a natural boundary: **export `lib/` wholesale, hide `src/` except a
named list.** It is defensible without a curation argument, it matches what
each half is *for*, and it is a boundary the compiler already computes — the
`from-lib` half of provenance is `path-under-ct-lib-root` against
`g-ct-lib-root`.

## 4. Options

**A. Enforce what is already written.** An audit unit over `lib/` against the
live export roster, with an allowlist for the legitimate uses. Buys honesty, not
capability. Small, and worth having under any option below as the regression
net — it is what catches a `lib/` file drifting into the roster while the larger
question is still open.

**B. Narrow the export surface.** Replace blanket `-rdynamic` with a curated
export list (`--dynamic-list` on ELF; Mach-O and the two Windows triples the
compiler cross-emits need their own mechanism). Hidden names cannot collide, so
the minefield shrinks to what was deliberately published, and by fact 3 the
provenance hazard shrinks with it.

**C. Give the API a name.** Expose the supported subset under an explicit
namespace, reusing Stage 12 N4's `set-ir-prefix` machinery, so reaching into the
compiler is spelled and greppable rather than accidental. Pairs with B: **B
decides what is reachable, C decides how it is spelled.**

**D. Tier it.** A stable core — node constructors and accessors — for
third-party libraries, plus an opt-in spelling for the unstable rest, following
the tree's existing `unsafe/` convention
([../stage14/unsafe-namespace.md](../stage14/unsafe-namespace.md)). The tooling
three land in the second tier: available, not promised.

**E. Generate a CT header.** Ship the supported API as a generated `.nuch` and
check it the way the 87 existing generated headers are checked
(`scripts/check-headers.sh`), so drift is mechanical rather than noticed.

## 5. What it would cost

* **B moves bytes in every committed boot artifact.** Linkage and visibility are
  in the IR, and `boot/*.ll` is committed IR, so B carries a boot convergence
  and wants its own commit — the same shape as
  [../stage20-macros/string-table-per-module.md](../stage20-macros/string-table-per-module.md)
  §4.
* **B needs a story per object format.** `--dynamic-list` is ELF. The compiler
  cross-emits `boot/nucleusc-x86_64-windows-{gnu,msvc}.ll`, and
  [context/build.md](../../context/build.md) records that a POSIX-only extern
  landing in both is a real failure mode, not a hypothetical one.
* **D is a promise, and promises are the expensive part.** Everything in the
  stable tier is a signature that cannot change without a deprecation. That is
  the real cost of this work, and it is not a code cost.

## 6. Reading

**D is the policy question, and it is the one that has to be answered first** —
what gets promised is not a thing the implementation can decide. B+C is the
mechanism that makes an answer real. A is worth landing regardless of when the
rest happens, because it is small and the rule it enforces is currently
enforced by nothing.

One consequence worth noting: B is also what would let `--warn-ct-shadow`
retire for hidden names, because the collision it warns about stops being
expressible.
