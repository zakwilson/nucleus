# The AST as a collection: making `Node` lists conform to `Coll` and `Seq`

**Status:** options examined 2026-09-22; O3 chosen and built, landing
2026-09-23. §8 is the build plan (the bootstrap argument that shapes it, the
accessor API that is the layout seam, the three steps and their gates); §8.6
records what actually shipped and where the plan was wrong.

## 1. The question

Lisp's strength that Nucleus keeps is that the AST is a data structure as
natural to work with inside the language as any other. Today it is not: a
`Vector` answers `(count v)`, `(v i)`, `(conj v x)`, `doseq`, `into` and the
combinators through `Coll`/`Seq`; an AST list answers none of them. Macro code
reads its second argument as `((spec 'cdr) 'car)` (lib/macros.nuc:194) and
counts with a hand-rolled cdr walk. The `(List T)` prototype of 2026-09-22
(a header + cells, ~140 lines, conforms cleanly) showed the protocols are not
the obstacle. The obstacle is what an AST list *is*.

## 2. Why the cons list cannot conform as it stands

An AST list is a bare `(raw Node)`: the address of its first `NODE-CELL`, or
`null` for `()`. `Coll`/`Seq` are STL-style — every method takes `self:&Self`
and the mutators work in place. Four things break, and none is fixable by
adjusting a protocol:

1. **Identity.** A list has no object of its own; it is identified by its first
   cell. `conj`/`append`/`insert` must mutate *the list*, and a list whose
   identity is "the first cell" cannot be appended to when it is empty — there
   is no cell to mutate. Prepend cannot work either: the caller still holds the
   old first cell.
2. **`null` is `()`.** `&Self` is non-null; the empty list is `null`. `(count '())`
   has no receiver.
3. **The empty list is also "nothing".** Because `()` reads as `null`, the same
   value means "absent" in every API that returns a node: `node-at` answers
   `none` both for out-of-range and for an element that *is* `()`;
   `ListIter`'s `?ptr` answers `none` for a `()` element, so `'(a () b)`
   iterates as one element (verified: two cells whose second `car` is null
   count as 1); a macro that expands to `()` is refused with `returned null`
   (`expand-macro-call`); `node-kind` needs the out-of-band `NODE-NIL = -1`;
   `node-is-list` must say yes to `null`; `quoted-datum-type` special-cases it.
   Every one of these is the same hole.
4. **Element type.** A cell's `car` is `(raw Node)`; there is no `E` to bind
   other than that, which is fine — the AST is a list *of nodes* — but it
   means a conformance is `(Coll (raw Node) …)`, never `(Coll T …)`.

So the choice is between (a) keeping cons cells and accepting that `Node` can
conform only to the *read* half of the protocols, or (b) giving a list an
object — a header — after which the full mutating protocols fit. Both need
the empty list to stop being `null`.

## 3. Census (what a change touches)

| idiom | src/ | lib/ | examples/ | tests/ |
|---|---|---|---|---|
| `'car)` | 193 | 62 | 15 | 15 |
| `'cdr)` | 261 | 64 | 12 | 15 |
| `(node-at …)` | 753 | 7 | 0 | 3 |
| `(node-len …)` | 393 | 2 | 1 | 6 |
| `(make-cell …)` | 281 | 12 | 0 | 3 |
| `NODE-CELL` | 178 | 18 | 4 | 4 |
| `~@` splices | — | 62 (lib+examples) | | |
| `(= x null)` / `(!= x null)` in nucleusc.nuc, all types | 468 | | | |

Two things the numbers say. Random access already dominates: the compiler asks
`node-at`/`node-len` 1,146 times and walks `car`/`cdr` 454 times — the AST is
used as an array that happens to be stored as a chain. And the cdr-walks are
concentrated: `src/nucleusc.nuc` 235, `union-registry.nuc` 99, `cheader.nuc`
52, `generics.nuc` 30, `union-emit.nuc` 29; in `lib/`, `macros.nuc` (94) and
`read.nuc`.

Beyond the sites, the cell layout `{ i32, i32, i64, ptr, ptr, ptr }` is
hard-coded in three emitters: `emit-qq-helpers` (`@__cons`/`@__append`, the
quasiquote runtime, with a private host-sized mirror in the compile-time
module — Stage 20 L3), `emit-quote-tree` (quoted literals), and the `:rest`
call path (`emit-call`, builds the rest list right-to-left with `make-cell`).
`expand-macro-call` builds a macro's `:rest` the same way. The reader
(`rd-list`, `rd-lit-elems`, `read-all-with-macros`) already keeps a tail
pointer while building and throws it away.

## 4. Options

### O1 — a `nil` sentinel, cons cells kept, read-only conformance

Reserve one interned `Node` for `()` (as Lisp's `nil`: `car`/`cdr` of `nil` are
`nil`). The reader returns it; `node-at`, `node-len`, the quote/quasiquote
emitters and `@__append`'s null test compare against it; `NODE-NIL` and the
macro `returned null` refusal go away. `Node` then has a non-null receiver, and
`car`/`cdr` can stop being `(raw Node)` (the Stage 14 deferred item, unblocked).

But item 1 of §2 stands: `conj` cannot mutate `nil`, and the protocols bundle
the mutators. Conformance needs a **split** — `count`/`empty?`/`iter` and
`invoke`/`contains?` in read-only protocols that `Vector`, `HashMap`,
`HashSet`, `String` also conform to, with `conj`/`append`/`insert` beside them.
`doseq`, the combinators and `into`-*from* work on a list; `into`-*to*, `conj`
and every mutator do not. A Lisp list is a value, so this is honest; but the
user's complaint was exactly that `Node` is not as nice as `Vector`, and it
would stay a source-only collection with O(n) `count` and index.

Cost: reader 1 site, `lib/node.nuc` ~10 functions, the emitters ~8 sites, the
two runtime helpers, the `:rest` terminators, the protocol split across five
conformers — and the tail: every `(= n null)` guard on a node in `src/` that
meant "is it `()`" keeps compiling and silently never fires. A `&Box` compared
to `null` is accepted today with no diagnostic (verified), so the sweep has no
compiler help finding them. Days, not weeks; no relayout, but a boot refresh
(the reader changes what it produces).

### O2 — a header node over a cons spine

A list becomes its own `Node` of a new kind: `car` = first cell, `cdr` = last
cell, `i` = length; cells stay as the spine. The empty list is a fresh header
with length 0 — never null, never shared. `count` and `conj` (append via the
last pointer) are O(1); `first` is `header.car.car`; `rest` is a new header over
the second cell (O(1), tail-shared); `cons` is a new header + one cell (O(1)).
`Node` conforms to the full `Coll` and `Seq`.

Every consumer changes anyway: a list value is now a header, so each of the
454 cdr-walks starts from `(lst 'car)` and each of the 293 `make-cell`
constructions builds a header, and the three emitters change shape. That is
the same sweep as O3 with the same boot refresh — and it keeps O(i) indexing
for the 1,146 random-access sites plus a tail-sharing mutation hazard (`conj`
on a list whose spine another header shares corrupts the sharer; Lisp's
`nconc` problem). Dominated by O3.

### O3 — a header node over an array (recommended)

A list is a `Node` of kind `NODE-LIST` holding a growable array of element
pointers: relayout the tail of `Node` from `car cdr` (16 bytes) to
`elems:(raw &Node) len:i32 cap:i32` (16 bytes), size unchanged at 40. The
empty list is a header with `len 0`. Then:

* `(count form)` and `(form i)` are O(1) — the shape the compiler's own 1,146
  random accesses want; `node-at`/`node-len` become thin wrappers or retire.
* `(conj form x)`, `insert`, `append`, `contains?` (pointer identity; symbols
  are interned singletons so `(contains? form 'foo)` means what it says) —
  `Node` conforms to `Coll (raw Node) NodeIter` and `Seq (raw Node)` in
  `lib/node.nuc`, with a hand-rolled buffer (the prelude cannot depend on
  `lib/vector.nuc`). `doseq`, `into` in both directions, `map`/`filter`/
  `reduce` all apply to forms.
* `~@body` becomes an extend, O(len(body)); today's `@__append` copies its
  left operand cell by cell, so quasiquote gets *faster*.
* `first`/`rest` survive: `rest` is a **view** (a header whose `elems` points
  one past the parent's, `cap 0` marking it borrowed, copy-on-write on the
  first mutation), O(1), which keeps the recursive idioms. `cons` is a fresh
  header with one more element, O(n) — the price of arrays, paid where the
  cons idiom is used and nowhere else (the compiler builds lists left to
  right).
* Macro code reads `(spec 0)`, `(spec 1)`, `(count args)`, iterates `body`
  with `doseq` — the ergonomics the question is about.
* Items 2–3 of §2 vanish structurally: no null list, no `()`-is-absent, no
  `NODE-NIL`, no `returned null`, `NodeIter` yields `?&Node` with `none`
  meaning only "end".
* It unblocks the Stage 14 deferred promotion `Node.car/cdr → (ref Node)`: an
  element is never null, so the AST API can be `&Node` throughout (a second
  sweep, optional, and the one that turns `(as raw:Node (node-at …))` into
  `(form 1)`).

The relayout is the one moment to reconsider RD6 (`Node` as a `defunion`) —
not required, and Stage 14's reasons (hottest structure, shared mutation) still
hold; recorded, not proposed.

### O4 — a wrapper struct (`NodeList {head}`) that conforms

Cheap (it is the `(List T)` prototype with `E = (raw Node)`) and answers
nothing: the AST stays second-class and every use pays `(node-list n)` first.
Dismissed.

### O5 — protocols over nullable receivers (`self:?&Self`)

A compiler feature (conformance for a pointer kind) that lets `(count null)`
type-check. It does not touch items 1 or 3 of §2: the mutators still cannot
work and `()` is still "absent" everywhere. Dominated by O1. Dismissed.

## 5. O3 in more detail

**Layout.** `(defstruct Node kind:i32 line:i32 i:i64 s:Symbol (elems (raw &Node)) len:i32 cap:i32)`.
`NODE-CELL` is renamed `NODE-LIST` (the ordinal can stay). The header carries
the list's line as the cell did; elements carry their own.

**Runtime.** `lib/node.nuc`: `node-list-new (cap line)`, `conj` (arena
bump-allocate a doubled buffer on growth; the old one is arena garbage, which
is what an arena is for), `invoke`, `count`, `empty?`, `iter` (`NodeIter
{elems, pos, len}`), `append`, `insert`, `contains?`, `first`, `rest` (view),
`cons`; `(extend Node (Coll (raw Node) NodeIter))`, `(extend Node (Seq (raw Node)))`.
`lib/list.nuc`'s `cons`/`first`/`rest`/`append` over cells and `ListIter`
retire in favour of these (their five `src/` users are `list-iter` loops that
become `doseq`).

**Emitters.** `emit-qq-helpers` emits `@__list_new`/`@__list_push`/
`@__list_extend` (target-sized, plus the L3 private host mirror) instead of
`@__cons`/`@__append`; `emit-qq-list` builds left to right into one list —
a level-1 splice is an extend; `emit-quote-tree` allocates a header and pushes;
the `:rest` call path and `expand-macro-call` push in order instead of
consing right to left. `stamp-macro-lines`, `ct-subst-args`,
`macroexpand-form`, `node-type`'s quote arm follow.

**Reader and printer.** `rd-list`/`rd-lit-elems`/`read-all-with-macros` push
into a header (they already keep a tail); `node-write` iterates. `.nuch` text
is unchanged, so headers re-read identically; `lib/prelude.nuch` and the C
headers regenerate.

**The sweep.** 454 cdr-walks in `src/` become index loops or `doseq`; 293
`make-cell` chains become `node-list` builders (`(make-cell a (make-cell b
null L) L)` → `(node-list2 a b L)` is pattern-matchable, the way
`scripts/stage21/sugar-sweep.py` matched its eight rules); `lib/macros.nuc`'s
94 sites become indexing. A rewrite script handles the regular shapes and
refuses the rest for hand conversion.

**Companion diagnostic.** `(= r null)` on a non-null `&T` compiles silently
today. It should be an error (always false); it is what makes the stale `()`
guards visible during the sweep, and it is independently worth having.

## 6. Gates

* Byte-identical IR is impossible (a relayout); the gates are the ones item 2
  used for the reader: `--dump-ast` over the whole corpus identical before and
  after (the printed tree is representation-independent), the pinned reader
  and macro diagnostics unchanged, `make bootstrap` converged after one
  refresh, `ir-snapshot.sh verify` byte-identical for every artifact that does
  not `(import-use node)` (a program that never quotes or takes `:rest` has no
  `Node` in its IR).
* New units: a form as a `Coll`/`Seq` (`count`, index, `conj`, `insert`,
  `doseq`, `into` both ways), `()` as an element and as a macro result, `rest`
  views with copy-on-write, `~@` of a view, the null-compare diagnostic.

## 7. Cost and recommendation

| | O1 sentinel | O2 header+cells | O3 header+array |
|---|---|---|---|
| empty list a value | yes | yes | yes |
| full `Coll`/`Seq` (mutators) | no — read-only split | yes | yes |
| `count`/index | O(n) | O(1)/O(i) | O(1) |
| `rest`/`cons` | O(1) | O(1) | O(1) view / O(n) |
| `~@` | O(left) as today | O(left) | O(right) |
| `Node` relayout | no | no | yes |
| boot refresh | yes | yes | yes |
| sites rewritten | ~50 + the silent `null` tail | ~750 src + ~140 lib | ~750 src + ~140 lib |
| unblocks `&Node` AST API | yes | yes | yes |

O1 is the small fix that leaves the AST a second-class collection. O2 costs
what O3 costs and keeps the worse asymptotics and a sharing hazard. **O3** is
the representation under which `Node` is as natural as `Vector` — because it
*is* the same shape — and it is what the compiler's own access pattern has
been asking for. Size: a stage item on the order of item 2 (one reader):
emitter rewrite ~300 lines of real work, the rest a scripted sweep with a
hand-converted remainder, one boot refresh. Sequence: relayout + runtime +
reader/printer + emitters + sweep (one refresh) → conformances and docs →
the optional `&Node` promotion → retire `lib/list.nuc`'s cell primitives. The
generic `(List T)` prototype is a separate library, wanted or not on its own
merits; it is not the AST's representation.

## 8. Building O3: two boot refreshes, and why

### 8.1 The constraint a relayout runs into

A macro body is compiled from the *program's* source against the program's
`lib/prelude.nuc` `Node`, into a JIT module, and is then handed the
*compiler's own* AST nodes (`expand-macro-call`). So the compiler's internal
`Node` layout and the layout the prelude it compiles describes must be the
same — `L_compiler = L_prelude`, always, for every compilation that expands a
macro (which is every compilation: `when`, `+`, `cond`, `fstr` are macros).
The committed boot is `L_old` and cannot be changed; the working tree, the
moment the prelude's `Node` changes, cannot be compiled by it. There is no
single-refresh path: an intermediate compiler must exist whose *internals* are
`L_old` while what it *builds* is `L_new`, and that is only consistent if the
macro bodies it runs never touch the layout directly.

Every alternative measured on the way was worse: a scratch tree with two
`Node` structs (`Node` old for the JIT, `NodeNew` for the program) and a
patched boot that types quotes by module, a macro-boundary converter that
rebuilds every argument tree in the other layout (defeated by provenance —
`node-at` inside a macro resolves to the *host's* copy, so a converted node
meets an unconverted accessor), pre-expanding the compiler's own unit (loses
file boundaries). All of them exist to let a macro body see a layout the
running compiler does not have. The cheaper move is to make the bodies stop
looking.

### 8.2 The seam: a layout-neutral list API

`lib/node.nuc` grows a list API whose every function has one implementation
per representation and the same contract under both:

| read | contract |
|---|---|
| `node-len n` | element count; 0 for null |
| `node-at n i` | `?&Node`; `none` when null or out of range |
| `node-first n` | first element, null when null/empty/not a list |
| `node-rest n` | the elements after the first, **null when there are none** — so a `(while (!= r null) … (set! r (node-rest r)))` walk terminates under both representations |
| `node-kind n` | `NODE-NIL` for null — **and, after step 2, for `()` as well** |
| `node-is-list n` | true for null (an absent form reads as an empty list, as it always has) |
| `node-empty? n` | true for null **or** `()` — the "nothing where an operand belongs" test a definer wants |

| build | contract |
|---|---|
| `node-list-new line` | a list under construction |
| `node-push b x` | append |
| `node-extend b lst` | append every element of `lst` (null = nothing) |
| `node-list-done b` | the finished list — the *one* call whose result differs: the chain (null if empty) under cells, the builder itself under the header |
| `node-cons x lst line` | `(x …lst)` |
| `node-list1 … node-list5` | fixed-arity constructors |

Null keeps exactly one meaning, "absent" (an out-of-range `node-at`, a
missing form), and every reader tolerates it. Under cells `()` is also null;
under the header it is a length-0 list. That is the whole semantic delta a
consumer can observe, and it is confined to a site that asks `(= x null)`
about a value that may be `()` — which is why the rule for the sweep is
**never compare a list to null; ask `node-len`**.

`NODE-CELL` is renamed `NODE-LIST` at the same time (same ordinal, so
`.nuch`/C headers regenerate with the new name only). `require-node-runtime`
looks for `node-list-new` rather than `make-cell`, which will not survive.

**The seam does not reach a macro body, and the fix is special forms.** A body
is compiled from the *program's* prelude, which registers the `Node` type and
imports no node runtime, so it has no signature for `node-at` however well
provenance would resolve the call at run time (§8.1). The first attempt was to
have `lib/macros.nuc` carry hand-written `declare`s for the API; that was
abandoned — a `declare` pins an arity and a parameter type, which is exactly the
thing a relayout is allowed to move, so it reintroduces the coupling the seam
exists to break. What shipped instead is four **special forms** — `ast-first`,
`ast-rest`, `ast-at`, `ast-len` — with the same contracts as the `node-*` reads
above. A special form is lowered by *whichever compiler is running*, so the one
spelling is correct under `L_old` and `L_new` at once, which is the only thing
§8.1 actually requires of a body. `(p 'kind)` and `(p 's)` stay plain member
access: the scalar fields do not move.

### 8.3 Step 1 — the sweep under the old layout (boot refresh #1)

Every `'car`/`'cdr`/`make-cell`/`(set! (tail 'cdr) …)` in `src/`, `lib/`,
`examples/` and `tests/` is rewritten onto the API, with the representation
unchanged. `lib/list.nuc`'s cell primitives (`cons`/`first`/`rest`/`append`,
`ListIter`) lose their `src/` users (index loops). Gates: `make bootstrap`
converged; `make test`; `scripts/stage17/ir-snapshot.sh verify` byte-identical
for every artifact whose program does not import `node` (the emitters are
untouched, so a program's IR moves only by the new definitions `lib/node.nuc`
contributes); `scripts/stage21/dump-ast-corpus.sh verify`. Then
`make update-bootstrap`: the boot now exports the API and reads a `src/` that
never names a cell field.

This step is the one that is *fully* testable, because nothing about the
representation has moved; it is the bulk of the work, and it is what makes
step 2 small.

### 8.4 Step 2 — the relayout (boot refresh #2)

With the boot at step 1, the tree changes in exactly three places:

1. `lib/prelude.nuc`: `(car (raw Node)) (cdr (raw Node))` →
   `(elems (raw &Node)) len:i32 cap:i32` (size unchanged, 40).
2. `lib/node.nuc`: the same API over the header (`node-list-done` becomes the
   identity; `node-rest` a `cap 0` view, copy-on-write on its first push;
   `node-cons` a fresh header), `make-cell` deleted, and the conformances
   `(extend Node (Coll (ref Node) NodeIter))` / `(extend Node (Seq (ref Node)))`
   — `(ref Node)`, not `(raw Node)`, because `some` takes a non-null reference
   and `next` must be able to answer `none` (§8.6). `lib/read.nuc` needs
   nothing: it builds through the API and prints through `node-at`.
3. `src/nucleusc.nuc`'s three lowerings: `emit-quote-tree` (a `NODE-LIST` is
   `@node-list-new` + `@node-push` per element), the quasiquote emitters
   (`emit-qq-list` builds one list left to right; a level-1 `~@` is
   `@node-extend`; `emit-qq-tagged` is a two-push list) and the `:rest` call
   path (`@node-list-new` + `@node-push`, elements still `inttoptr`ed). The
   private `@__cons`/`@__append` runtime, `emit-qq-helpers`, `qq-cell-align`,
   `g-qq-used` and the two hand-copied CT variants go; the JIT modules
   `declare` the three API functions where they declared `@make-cell`
   (`g-node-ctor-used`), and `ct-mirror-classify` loses its `@__cons` case.

Why the boot from step 1 can compile this tree (the argument §8.1 asked for):
its macro boundary hands `L_old` nodes to bodies that only *call* the API,
and every call a body makes resolves — by Stage 20 L4's provenance rule, the
callee being under the library root and exported by the running binary — to
the **boot's own** implementation, which is `L_old` on `L_old` nodes.
Quasiquote inside a body lowers to the boot's private cell helpers, also
`L_old`. The compiler's *program* code quotes only symbols (verified: no
quoted list, no quasiquote, no `:rest` call outside a macro body in `src/` or
in the `lib/` files the compiler reaches), and a symbol node's first 24 bytes
are the same under both layouts, so the boot's `@intern-symbol` lowering
produces nodes the new runtime reads. The result, `build/nucleusc`, is the
first `L_new` compiler; it compiles the same tree again and that output is
the fixed point (`make bootstrap` diffs against the boot's output and
reports the expected lowering difference until `make update-bootstrap`).

Gates: `dump-ast-corpus.sh verify` identical (the printer is
representation-independent); the pinned reader and macro diagnostics
unchanged (`make test`); `ir-snapshot.sh verify` byte-identical for every
artifact whose program has no quote, quasiquote or `:rest` call, and a
recorded re-take for the rest; bootstrap converged after the refresh.

### 8.5 Step 3 — what the relayout unlocks

After refresh #2 the accessor spellings are wrappers, and the ergonomic
rewrites follow at leisure, each an ordinary change under a converged boot
(none of this list is done — O3 closed at the end of §8.6):
`(node-list-done b)` → `b`; `node-push` → `conj`; `(node-len x)`/`(node-at
x i)` → `(count x)`/`(x i)` and `doseq` where `lib/macros.nuc` and the
compiler read forms; the `&Node` promotion of the AST API (an element is
never null); `lib/list.nuc` retired; the companion diagnostic that `(= r
null)` on a non-null `&T` is an error; the new units of §6; docs.

### 8.6 What shipped, and where §8.4 was wrong

Landed 2026-09-23. `make test` 1094 passed / 0 failed / 0 skipped; `make
bootstrap` converged; both gates re-baselined with `--force` and re-verified
(see `design/progress.md` for the recorded reasons).

Six things the plan did not have:

1. **`()` needed `node-kind` to keep lying.** Once `()` is a non-null
   `NODE-LIST`, every definer that asked `node-kind` for "is this operand a
   name?" started seeing `NODE-LIST` and took its *template head* path instead
   of refusing — about twenty W9-item-45 diagnostics turned into segfaults,
   wrong messages and wrong exit codes. Making `node-kind` answer `NODE-NIL`
   for `()` as well as for null is the single lever that restored the whole
   family with no diagnostic rewritten; `node-empty?` guards went in at the ten
   sites that had to distinguish the two after all
   (`reject-colon-in-def-name`, `require-declare-name`,
   `require-extend-protocol`, `extract-name-and-type`, `defn-parse-sig`,
   `emit-node`'s W5f guard, `validate-decl-node`, and three arms of
   `validate-header-forms`).

2. **The element type is `(ref Node)`.** `(raw Node)` does not fit `some`,
   which takes a non-null reference, so `next` could not report the end. The
   one place that stores a null element is the `:rest` lowering (an `inttoptr`
   of a small integer), and it builds through `node-push`, not `conj`, so the
   conformance's promise holds.

3. **A `Seq` conformer with real struct fields is a new shape.** Adding
   `invoke` for `(ref Node)` made every `(n 'kind)` in `lib/macros.nuc` an
   overload error. The fix is a precedence-1 branch in `emit-callable-value`
   (`callee-selects-field`): a **literal** quoted selector naming a field of the
   receiver is a field access even when the type has an `invoke`. It is
   side-effect-free and asked before any argument is emitted. Because the boot
   had no such branch, the work staged into two bootstraps — `Coll` plus the
   router fix, `make update-bootstrap`, then `Seq`.

4. **Line attribution broke tree-wide, from two independent causes.** The
   quasiquote emitters built their lists with the *macro body's* line, but
   `node-line` falls back to the enclosing form precisely so a generated node
   is blamed on the **call** site; the old `@__cons` stored 0 and got that for
   free. Emitting `@node-list-new(i32 0)` restores it. Separately,
   `stamp-macro-lines` walked the spine with `node-rest` — a fresh view whose
   line it stamped and then discarded, so every element past the first went
   unstamped. It is an index loop now. The general rule, now in
   `context/conventions.md`: `node-rest` is a borrowed view, wrong as a
   mutation target and wrong as a recursion spine.

5. **`g-macro-decls` was per-module state that was reset but never restored.**
   A nested `macrolet` inside a `defmacro` left its set behind and the outer
   body died with `use of undefined value '@node-first'`. Save/restore fixes
   it, with the restore placed **after** the module's node-runtime declares —
   those write into this module's `ct-decl` and must be recorded in the current
   set.

6. **One genuine regression, caught only by the IR gate.**
   `type-node-to-c-decl` tested `(= plist null)` to mean "no parameters", so a
   C function-pointer return type emitted `f()` — unspecified arguments —
   instead of `(void)`. Pinned by a new unit
   (`fp5-cheader-fnptr-return-takes-void`). This is the canonical instance of
   the sweep rule: **never compare a list to null to mean empty; ask
   `node-len`.** `ct-eval-require-list` was the other, which had quietly become
   vacuous because its walk started at a node that is no longer a cons chain.

Costs taken knowingly:

- **`lib/node.nuc` now imports `coll` and `iterator`.** Nine IR artifacts gained
  `lib/iterator.nuc`'s concrete iterators as a result. The imports sit at the
  tail of the file, after the whole API, so the compiler's own bootstrap path
  reads the API before the protocol machinery.
- **The macro `:rest` list is built right-to-left with `node-cons`**, which is
  O(n²) over an array. Rest lists are a handful of forms; a forward push is the
  obvious follow-up and was not taken during the relayout.
- **`lib/list.nuc` survives but is retired in intent** (§8.5): `Node` conforms
  directly, so `ListIter` exists for the examples that still spell a list
  through it.

Of the 366 differing IR artifacts, 274 differ only in the `%Node`/`%NodeIter`
type declarations, 54 are quote/quasiquote/`:rest`/node-import programs (the
lowering change), 27 are sources edited in this tree, and 9 are the
`lib/iterator.nuc` pull-in above. `dump-ast-corpus verify` differed in exactly
the 20 edited sources, which is the gate's actual claim: the printer is
representation-independent.
