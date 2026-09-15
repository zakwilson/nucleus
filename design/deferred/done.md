
### `macmap` over a computed row list — **no longer deferred**

Taken up 2026-09-14 as
[stage20-macros/computed-macro-arguments.md](stage20-macros/computed-macro-arguments.md).
The blocker recorded here — that it "would need `macmap` to expand its own rows
argument, which means calling `macroexpand-form` from `lib/macros.nuc`" — was
never the real one. It assumed *expansion* is the only route to a computed
argument. **Evaluation is another, it was already legal, and it reaches no
compiler internals**: `~` inside a macro body is ordinary code running at
expansion time, and since
[macro-call-linking.md](stage20-macros/macro-call-linking.md) §3.1 that code may
call the program's own functions, so a wrapper macro that computes its rows with
a `defn` and splices them into a `macmap` already worked with no compiler change
(probed, exit 13). What was missing was the same spelling one level out, at
source level, where `~e` is the error `unquote outside quasiquote` — which is
what makes the spelling free to claim.

The second half of the entry stands and is why the wrapper idiom remains the
baseline any feature had to beat: it works today and costs one adapter macro per
site.




### The string-literal table is one per compilation, not one per module — **FIXED**

Taken up 2026-09-15 as
[stage20-macros/string-table-per-module.md](stage20-macros/string-table-per-module.md),
and **built the same day**, all four phases: `S1` the fix, `S2` the boot
convergence, `S3` the assertion, `S4` the residue `S1`'s own sweep found. The
tree is now at **zero** dead `@.str` constants over the 229 program modules in
`tests/fixtures/` and `examples/`, and that claim is asserted with no allowlist
by `tests/suite-audits.nuc`. The analysis below stands as written and is the
design's §1; what the entry lacked was the two checks that make the fix small
(`intern-string` keeps no dedup cache, and the CT paths already save and restore
sibling globals) and the one exception that stops it being a find-and-replace
(`ct-mirror-flush` must keep emitting the *program's* table, because the spans
it copies reference program `@.str` ids).

Two corrections the build made to the paragraphs below. **The "save and restore
`g-strs`" fix is not the one that works** — a mirror flush nests inside the very
bodies the swap brackets, so the exception above cannot be honoured by a swap at
all; the shipped form is a watermark into the one shared table, per §6.1 there.
And the **125 dead constants** attributed to `src/repl.nuc`'s two `macrolet`
tables measured 145, low because several of their spellings are minted by other
macro bodies too. Everything else held: 92 dead constants in a hello-world-sized
program had grown to 106 by the time of the fix, and is now **0**.

**And the per-module table was not the whole of it.** A third mechanism reaches
the same defect from outside any compile-time module: `emit-import-forms` points
the definition stream at a throwaway sink for a compile-time-only import and
runs the emitter unchanged into it, so the bodies' `@.str` *references* are
discarded while `intern-string` still appends. No watermark or swap can separate
that window's two kinds of string, because a `drain-mono-worklist` inside it
writes to the real program buffer. `S4`'s answer is at the consumer instead —
emit what the module *references* rather than what was interned, which closes
the class by construction rather than by enumeration.

`g-strs` is a single global vector and `emit-string-table` writes **all** of it
into whichever module is being assembled. So every macro body's quasiquote
interns its symbol spellings into the same table the program module emits, and
those constants are emitted into the program and never referenced by it.

Measured 2026-09-11: a hello-world-sized program carries **92 dead
`@.str` constants** before its first line of code — `_+`, `+`, `_*`, `cond`,
`let`, `while`, `match`, `macrolet` and the rest of `lib/prelude.nuc`'s macro
bodies. Adding one macro to `lib/macros.nuc` adds its own, and renumbers every
string after it in every program, which is why a change to the prelude can never
be byte-identical.

It is not only the prelude. Every `defmacro` or `macrolet` in `src/` pays the
same way, in proportion to how many distinct symbols its templates name: Stage
20 M5's two `macrolet` bindings in `src/repl.nuc` — a 54-row table, twice — put
**125 dead constants** into `build/nucleusc.ll` on their own. A table-driven
refactor is exactly the shape that pays most, so the cost lands on the idiom the
compiler is being pushed toward.

The fix is a per-module string table — save and restore `g-strs` around
`compile-macro-body` and the CT module path, the way `push-function-state`
already saves the entry/body streams. It is contained, but it moves bytes in
every program in the tree, so it wants its own gate and its own commit rather
than riding along with a feature.
