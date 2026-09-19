
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


### Pointer-kind spellings: make the sugar general, or ban the ambiguous half — **closed**

Closed 2026-09-19: PK-1 … PK-6 all landed (PK-6 last, with
`examples/type-sugar.nuc` — the §1.1 matrix as one golden — and the
`s21-matrix-compiles` / `s21-nuch-roundtrip` / `s21-ir-identical` /
`s21-match-ref-binder` units). `&` is `ref` in both worlds, the sigil-paren
forms read in every position, a sigil over a type variable is a wrapper, and
`addr-of` is retired; what stays open is the sweep's 14 `lib/` `(Maybe E)`
sites, boot-gated until the next refresh, and the template stamp's lost pointer
kind, which is its own entry in [overview.md](overview.md).

Taken up 2026-09-16 as
[stage21-cleanup/pointer-kind-spellings.md](../stage21-cleanup/pointer-kind-spellings.md),
on the **general** side. The design costs the general option lower than this
entry priced it: the node does not need to "remember it was written `&`",
because the type path already has a canonical head for the non-null pointer —
`ref` — and the value path already has a form whose result type is `(ref
(type-of x))`; the two worlds differed only in the *name* the reader macro
wrote, so `&` → `ref` makes them agree on one node with no new head at all,
and the six type-path `addr-of` arms are deleted rather than joined by a
seventh. The ban lost because it is a convention enforced by a diagnostic, it
retires the four blessed standalone forms, and it leaves untouched the two
defects the probe pass found beside this one: `?(Vector i32)` / `!(…)` parse in
no position at all (the fuse keys on a trailing `:`), and a sigil over a
concrete type in a generic pattern is collected as a **type variable**, so
`(Vector i32)` is silently accepted where `(Vector ?Pt)` was declared. `addr-of`
is retired outright after the boot refresh, since an alias would mean every
future head-match site must know two names — the failure this entry describes.
The `raw:T` → `void*` question in the last paragraph is not taken up there.

Raised 2026-09-07, after the `&`/`@` adoption sweep across `src/`, `lib/` and
`examples/` (see [progress.md](progress.md) and
[stage16-ergonomics/ref-sigil.md](stage16-ergonomics/ref-sigil.md) §5/§6).

The `&` sigil is split by position **inside the token**: `p:&T` is the lexer
rewrite to `ref:` and leaves no trace, while a standalone `&T` is the address-of
reader macro and reaches the parser as `(addr-of T)`. In a type slot that node is
accepted (`parse-type-from-node`, `node-is-ptr-wrapper`, and since 2026-09-06
`type-node-to-c`), so it compiles and emits identical IR — but `--emit-nuch`
prints `defprotocol` and generic-template forms **verbatim**, so the odd spelling
lands in a committed header. `a15f38e` wrote 2,469 of them into `src/` before
anyone noticed; the sweep that removed them is convention, not a rule the
compiler enforces.

Two coherent end-states, and they point opposite ways:

### String literal limit — **closed**

Closed 2026-09-18 by [stage21-cleanup/one-reader.md](../stage21-cleanup/one-reader.md)
R-1/R-2, as a side effect rather than a direct design target: the limit was
`src/reader.nuc`'s `lex-string`, which read into a 4096-byte alloca and refused
past 4095 bytes. `lib/read.nuc`'s `rd-string` reads into an unbounded `String`,
and R-2 made that the whole compiler's reader, so the cap did not move or
raise — it is simply gone. Probed 2026-09-16 as R-1's gate: a 6003-byte string
literal compiles, prints, and exports through `--emit-nuch` and `--dump-ast`;
a grep of `src/` for another 4095 found only the `deferror` id cap and
`:align`, both unrelated.

- **Make it general.** `&T` should be legal and canonical in every type slot,
  round-tripping through `--emit-nuch` as `&T` or `(ref T)`. The reader cannot
  decide by position, so the node has to *remember it was written `&`* — a
  distinct head both the type path and the value path accept, printed back as
  the source spelling. Cost is the usual reach list: the `node-type`↔`emit-node`
  lockstep, `gcheck`'s value-path wrapper test, and `fn-rewrite-captures`.
  §6 costed the wrapping-with-`addr-of` alternative at zero value-side changes
  precisely by *not* doing this; that trade should be re-priced now that the
  spelling has 3,000 uses rather than none.
- **Ban the ambiguous half.** Make a standalone `&T` in a type slot a
  diagnostic naming `ref:T` / `(ref T)`, so the convention is mechanical instead
  of a thing a sweep has to re-derive. Cheap — one arm in
  `parse-type-from-node` — but it retires `(sizeof &Pt)`, `(as &Pt q)`,
  `(link &Pt)` and `(Vector &Pt)`, which §"Where the two meet" blesses and
  `examples/ref-sigil.nuc` plus `s16-ref-sigil-both-meanings` exercise.

The general principle worth settling first: **a spelling whose meaning depends
on where the reader happens to be should not be silently accepted.** Today three
spellings of the same pointer kind (`ptr:T`, `ref:T`, `&T`) differ in nothing
the type system can see, yet differed for some time in what `--emit-cheader`
printed (`T*` vs `void*` — fixed 2026-09-06) and still differ in what
`--emit-nuch` prints. `raw:T` is the remaining case: it widens to `void*` in a C
header deliberately, which is defensible for a nullable pointer and is still a
header whose fidelity depends on which synonym the author typed.
