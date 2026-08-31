# Retiring the `.` forms, and the selector rule underneath them

**Status: in progress** (2026-08-31). **Steps 0-5 done.** The selector rule has
flipped — a quoted `'x` is the field, and a bare symbol in selector position is
an ordinary variable reference like a symbol anywhere else — and every
punctuation-named form is gone: `.` is `get`, `.&` is a 2-argument `addr-of`,
and `.set!`/`ptr-set!`/`aset!` are all `set!` over a **place**. Getting there
took a migration aid (`--strict-selectors`, now retired) and ~9300 rewritten
sites. What remains is step 6, the `set` generic. See §5.

Three special forms are spelled with a leading dot — `.` (member read), `.&`
(member address) and `.set!` (member write). They are the last forms whose name
is punctuation rather than a word, and two of the three have a word-spelled
equivalent already. Retiring them turns out to be mostly a question about
something else: **what a bare symbol means in selector position**.

## 1. What was already true

Measured on this tree before step 3. Every one of these compiled and yielded
the same value:

```lisp
(. pp x)   (get pp x)   (get pp 'x)   (pp x)   (pp 'x)   (_get pp x)
```

`emit-get-intrinsic` is documented as byte-identical to `.`, and `get` is a
**generic**: user `get` methods are tried first and the field-access intrinsic
is the fallback. Six spellings of one thing is what made the migration a
provable no-op (§5 step 2) — and three of them are gone now that a bare symbol
is a variable.

Textual occurrences (what a grep sees — §2 counts the sites the compiler
actually emits, which is the number that governs the migration):

| form | src | lib | examples | fixtures | ≈ |
|---|---:|---:|---:|---:|---:|
| `.` | 12 | 0 | 39 | 2 | 53 |
| `.&` | 7 | 42 | 55 | 0 | 104 |
| `.set!` | 1017 | 205 | 197 | 9 | **1428** |
| `ptr-set!` | 104 | 2 | 21 | — | 127 |
| `aset!` | 339 | 38 | 33 | — | 410 |

`.` has withered to 12 uses in `src/` because head-position `(p x)` is the
idiomatic read. `.set!` is 93% of the retirement work.

## 2. The selector rule is the real subject

Before step 3 a bare symbol in selector position **always** named a field. That
was the one place in the language where a symbol was not a variable reference,
and the W7 diagnostic existed to say so when a local shared the name.

The cost landed on the case that wants a field name in a *variable*:

```lisp
(get foo (quote bar))     ; producing the symbol
(get foo sel:ptr)         ; consuming one — the annotation is the only way to
                          ; force a symbol to read as a value
```

That was the defect. Computed access itself already worked —
`emit-computed-field` lowers a runtime selector to a `select` chain over the
field indices — but its spelling was an escape hatch rather than a rule.

### The decision: the quoted selector becomes the only literal spelling

A bare symbol in selector position goes back to being an ordinary variable
reference. `(get p 'x)` is the field; `(get p sel)` is computed, with no
annotation. This removes the exception rather than adding a second one.

What it costs is `'` on the most common read in the language, and a migration.

### Why the migration is affordable

Two populations, and only one of them is hard.

**Fixed-position selectors** — `.` / `.&` / `.set!` argument 2. The position is
known from the form, so this is a regex.

**Head-position `(p x)`** — not regexable, because `(foo bar)` is a function
call, a callable-value invoke, or a field access and nothing in the shape says
which.

Head-position sites do not break *silently* under the new rule, though, because the
computed path is double-gated: the selector must evaluate to a `ptr`
(`computed selector must evaluate to a symbol (ptr)`) and the struct must be
homogeneous (`computed field access requires a homogeneous struct`). So
`(nn kind)` becomes `undefined: kind`, and `(nn line)` under a local `line:i32`
hits the ptr gate. Silent breakage needs all three of: a local shadowing the
field name, typed `ptr`, on a homogeneous struct.

So the migration was driven by the compiler, not by a regex: `--strict-selectors`
(§5 step 1) reported every bare selector, the tree built at every step, and the
flag became the default — and was then deleted — when the list was empty.

### How big it actually is

Counted by the flag itself, compiling `src/nucleusc.nuc` (which pulls in all of
`src/` and the `lib/` prelude) — **6106 sites**, deduplicated on file:line:name:

| form | sites |
|---|---:|
| head-position / `get` | 4976 |
| `.set!` | 1094 |
| `_get` (incl. `.`) | 21 |
| `.&` | 15 |

Head position is **81%** of the work, which the earlier estimate here understated
by 5× — it sampled 80 field names from one header and found 1002, and the tail
past that sample is most of the total. Three consequences:

- The flag is not a convenience, it is the only way to do step 2 at all.
- Step 2 is a script over the flag's own output (`file:line:name` is enough to
  rewrite a site precisely), not a regex pass with hand cleanup.
- `.` is already dead — 21 sites, and `_get` counts them together. Step 4's
  rename is a rounding error next to step 2.

**The flag sees emitted code, not source.** It reports what one compilation unit
actually emits, which is narrower than the tree in two ways, both of which step 2
has to cover by other means:

- 27 files under `src/`+`lib/` report nothing, because nothing in this unit
  reaches them (`lib/string.nuc`, `lib/parse.nuc`, `lib/nsdescribe*.nuc`, …).
  `examples/` and `tests/fixtures/` need their own runs.
- An **uninstantiated generic is unchecked**, and an instantiated one is checked
  once per instantiation — `lib/vector.nuc`'s 29 `_get` sites report 629 times.
  Dedup on file:line:name; the raw stream was 7555 lines for 6106 sites.

A `.set!` inside a quasiquote template is data, not emitted code, so it is
invisible here too; step 2 rewrote those by hand.

Both blind spots proved out. `examples/` and `tests/fixtures/` added 983 sites
on their own runs — `lib/strview.nuc`, `lib/string.nuc` and `lib/string-split.nuc`
appear only there, exactly the uninstantiated-generic gap — and the REPL
transcripts another 31. **7254 tree-wide.**

## 3. Retiring the forms

- **`.` → `get`.** (Done — §5 step 4.) Equivalent *for a plain struct*: `.`
  lowered to `_get`, which bypasses a user `get` override, so the rename is
  proved by IR diff rather than assumed. 77 sites.
- **`.&` → `(addr-of p 'f)`.** (Done — §5 step 4.) An arity overload: 1-arg is
  today's `(addr-of x)` (which already requires a bare symbol), 2-arg is the
  member address. No ambiguity, no new dispatch — but `node-type` has to split
  on the same arity or the 2-arg form types as the binding's address. 154 sites.
- **`.set!` → `set!`**, as a **place form**, not an arity overload:

```lisp
(set! x 5)            ; place = symbol        — today's set!, unchanged
(set! (p 'field) 5)   ; place = member access — replaces .set!
(set! (deref p) 5)    ; place = deref         — replaces ptr-set!
(set! (aref a i) 5)   ; place = element       — replaces aset!
(set! (get m k) v)    ; place = a user get    — new: writable collections
```

Today's `(set! x v)` is the degenerate case, so the place form subsumes it. The
alternative — a 3-arg `(set! p f v)` — is a pure rename of `.set!` that buys
nothing, leaves `ptr-set!` and `aset!` standing, and is *not* a stepping stone
(the migration differs), so it is either the place form or nothing.

The place form costs `set!` a uniform evaluation rule for its first argument.
That is CL's `setf` tradeoff, taken deliberately.

### Extensibility

A `set` generic paired with the existing `get` generic, not `setf` expanders:
`(set! (get m k) v)` dispatches to a user `set` method on `(m, k, v)` exactly as
`(get m k)` dispatches today, reusing the multimethod machinery rather than
introducing a second extension protocol.

What that gives up is single evaluation of subforms — `setf` expanders exist so
that `(incf (aref a (f i)))` calls `(f i)` once. `inc!`/`dec!` over a place
would either evaluate twice or be restricted to simple places; restricting them
is the answer unless a case appears.

## 4. What none of this fixes

Field iteration over a **heterogeneous** struct — see
[stage888-deferred.md](../stage888-deferred.md#what-survives-that-fix-field-iteration-over-a-heterogeneous-struct).
The homogeneity gate is a typing fact, not a spelling one, and no selector
syntax removes it.

## 5. Staging

0. **Every member form accepts `'x`. (done 2026-08-30.)** Purely additive, and
   it is what lets step 2 rewrite into a spelling the *current* compiler
   accepts. Four sites, all now routed through `selector-literal-sym`:
   `emit-field-set` (`.set!`), `emit-field-addr` (`.&`), the `_get` emitter —
   which is where `.` lands, so `(. p 'x)` was refused too even though
   `(get p 'x)` and `(p 'x)` worked — and the `node-type-field` mirror
   (`src/generics.nuc`), without which the type pass and codegen would resolve a
   quoted selector differently. `_get` was missed on the first pass and caught
   by `s16-quoted-selector-ir-identical`, which is why that assertion diffs the
   IR of a *whole* member vocabulary rather than one form.
1. **`--strict-selectors`. (done 2026-08-30.)** One helper, `note-bare-selector`,
   called from the four sites step 0 unified — `emit-field-set`,
   `emit-field-addr`, `emit-field-get`, and `emit-get-with-callee`, which covers
   both `get` and head position. The discriminator is the one step 0 already
   relied on: `selector-literal-sym` returns the node itself for a bare symbol
   and the *inner* node for `'x`.

   Two decisions worth keeping:

   - It **reports and continues**, then fails in `main` on the count, rather than
     dying at the first site. Enumerating a tree is the entire purpose; a fatal
     diagnostic would need 6106 compiles. No output is written when the count is
     nonzero, so a strict run still reads as a failed compile.
   - In `emit-get-with-callee` the call sits **after** the W7 demotion, so a
     selector that already reads as a value — the callee has no such field and a
     local shadows it — is not reported. That case is what step 3 makes the
     universal rule, so it is not a site the migration has to touch.

   Off by default, so `make`, the bootstrap, and every other test are unaffected.
2. **Migrate the tree. (done 2026-08-30.)** **7254 sites**: 6240 in `src`+`lib`,
   983 in `examples`+`tests/fixtures`, 31 in `tests/repl/*.in`. The flag reports
   zero everywhere, 926 tests pass, and a clean-room `make` from the committed
   `boot/nucleusc.ll` reconverges.

   **`make update-bootstrap` comes FIRST, not last.** The staging above had it
   backwards. `make` compiles `src/` with `bin/nucleusc`, built from the
   committed `boot/nucleusc.ll` — so the boot compiler must already accept
   `(.set! p 'x v)` before a single source file is rewritten. Verified the hard
   way: the pre-refresh boot answered `.set!: field name must be symbol`.

   **The flag found a defect no source migration could have fixed.** Closure
   capture rewriting (`fn-rewrite-captures`) *synthesizes* `(. self field)` with
   a bare selector — 12 construction sites, plus the env-drop and `__alloc`
   paths. There is no source text to rewrite, and step 3 would have broken every
   closure in the language. Now routed through a `quoted-selector` helper. This
   is the case for having built the flag before touching any source: a grep over
   the tree cannot see a cell the compiler builds rather than reads.

   Two populations the oracle cannot locate on its own, both hand-fixed:

   - **Macro templates.** A `.set!` inside a quasiquote is data, so it is
     reported at the *use* site with a gensym receiver (`recv=__gs_0`). Six in
     `with-handler` (`lib/error.nuc`), one in a `macrolet` in
     `examples/macrolet.nuc` — where `(. p ~f)` becomes `(. p '~f)`, since the
     unquote splices a symbol and the quote is what keeps it one.
   - **REPL transcripts.** `nucleusc -i` reports every form as `<repl>:1`, so
     the line is not a key at all; those files match on (form, receiver,
     selector) anywhere in the file.

   The rewriter needs a **real s-expression parser**, not regexes, for two
   shapes: `->` threading, where the source says `(_ field)` but the compiler
   reports the receiver of the *expansion* (and a wrapped chain reports every
   step at the line the chain opens on), and chained access `((tt sdef) name)`,
   whose receiver is a cell and reports as `recv=()`.

   **Verification is IR identity, not review.** Every spelling in §1 emits the
   same IR, so the migration must be a no-op: the same compiler compiling
   pre- and post-migration `src/` produced byte-identical output across all 6240
   sites, and the 12-slot closure fix emitted byte-identical IR for all 154
   examples. The one legitimate exception is a **macro template** — quoting a
   selector inside one changes the template's *data*, so 29 examples' IR grew by
   exactly the added `quote` nodes; those are held by `make test`'s byte
   comparison of runtime output instead.
3. **Flip the default. (done 2026-08-30.)** `selector-literal-sym` now accepts
   `(quote x)` and nothing else, which makes a bare symbol in selector position
   an ordinary variable reference — the whole point of the exercise. Five
   consequences, each of which had to be built rather than merely allowed:

   - **The three fixed-position forms refuse a bare symbol** rather than reading
     it as a variable. `.`, `.&` and `.set!` name a field statically; there is
     nothing for a computed selector to mean there. `die-nonliteral-selector`
     says which spelling is missing (`-- write 'x`), because "field name must be
     symbol" would describe a bare symbol as failing a test it appears to pass.
   - **Head position and `get` route on the RECEIVER, not on the argument's
     shape.** `emit-callable-value` used to reach the member-access path only
     for a single literal-symbol argument; with the literal gone, `(p sel)`
     would have fallen through to `emit-invoke-with-callee` and reported "quote
     needs the node runtime". The gate is now `is-member-access-receiver`
     (`src/generics.nuc`), which answers the question `emit-get-intrinsic`
     actually asks: is this a struct/union value, or a pointer to one.
     `access-receiver-sdef` could not be reused — it answers with a `StructDef`
     and so cannot speak for a `TY-UNION`, which is exactly the case a
     receiver-shaped gate must not drop.
   - **An unbound bare symbol that names a real field is a missed quote**, and
     `emit-computed-field` says so with the spelling (`-- write (p 'x)`). A
     plain "undefined variable" would be true and useless: it is what every
     un-migrated line in a downstream tree will hit. The message names the
     receiver because `(p x)` and a call `(f x)` read alike on the page.
   - **The W7 demotion is dead.** `callee-has-field` and
     `selector-shadowed-by-local` existed to rescue the value reading when the
     callee provably had no such field; that is now the unconditional meaning of
     a bare symbol, and neither reading can be foreclosed by what the callee
     happens to contain. The collision case `(m 'count)` vs `(m count)` — which
     W7 could not express at all — is now just the quote.
   - **The `k:CStr` annotation hatch is retired** along with
     `--strict-selectors` itself. A field name held in a variable is spelled
     `(p sel)`, so there is nothing left to escape from.

   `w7-local-not-a-field` now pins the *opposite* refusal: `(p k)` with an `i32`
   local reaches the computed path and is refused for the selector's type, not
   for the field's absence.
4. **`.` → `get`, `.&` → the 2-argument `addr-of`. (done 2026-08-30.)**
   Both forms are deleted from the emit dispatch but stay **reserved**, so the
   spelling cannot be shadowed and a retired-form message reaches the user with
   the replacement in it — the shape Stage 14 gave `cast` / `ptr+`.

   - **`.&` → `(addr-of p 'f)`** is an arity overload, and the arity is the
     whole dispatch: 1-arg takes a bare binding name, 2-arg a receiver plus a
     quoted selector. `emit-addr-of` forwards a 3-cell call to
     `emit-field-addr` unchanged, so every shape `.&` covered — plain field,
     nested field, array field (which decays to `ptr:elem`), union member,
     by-value struct receiver — emits **byte-identical** IR, verified by
     diffing the two spellings of one program.
   - **`node-type` needed the same split, and this is the trap.** Without it
     the 2-arg form falls into `node-type-addr-of`'s 1-arg path and types
     `(addr-of p 'f)` as the address of the *binding* — `ptr:ptr:Point` rather
     than `ptr:i32`. It is invisible in the value itself and only surfaces
     where the type is load-bearing (an argument position, an annotated
     binding), which is exactly how the `node-type`↔`emit-node` lockstep bites.
     `node-type-field-addr` mirrors `emit-field-addr` including the array decay
     — reusing `node-type-field`'s already-decayed answer would have produced
     `ptr:ptr:elem`.
   - **`.` → `get`.** `.` *was* `_get` verbatim, and `_get` bypasses a user
     `get` override while `get` respects one, so "already equivalent" holds
     only for a plain struct. The migration is therefore proved rather than
     assumed: rewrite every site to `get`, diff the IR, and demote to `_get`
     wherever it moved. Nothing moved — 43 `.&` sites in `src`+`lib` and 63
     `.`/`.&` sites across `examples`/`tests` are byte-identical, 152 of 154
     examples unchanged.
   - **The compiler synthesizes both forms**, the same hazard step 2 found:
     eight `(intern-symbol ".")` and two `(intern-symbol ".&")` construction
     sites in the closure-capture and env-drop paths. They became `_get` and
     `addr-of` — `_get`, not `get`, because a synthesized read of a
     compiler-generated env struct means *raw field load*, which is what the
     bypass primitive is for. These are the only intended IR differences in
     the whole step (ten string constants), and the one legitimate example
     diff is `macrolet.nuc`, whose quasiquote template holds a `.` as **data**.

   Two things deliberately kept: `_get` (the documented override bypass, still
   needed by a user `get` method reading its own fields) and `.set!`, which
   step 5 turns into the place form rather than renaming twice.
5. **`set!` as a place form; fold in `ptr-set!` and `aset!`. (done 2026-08-31.)**
   `set!`'s first operand is a place, and `.set!`, `ptr-set!` and `aset!` are
   retired — reserved, with a message naming the place that replaced them.
   **2068 sites**: 1982 in `src`+`lib`, 63 in `tests/run-tests.sh`, 23 in the
   docs' fenced blocks.

   - **Each place rebuilds the call its writer would have been given** — same
     children, same line — and hands it straight to that writer's emitter.
     That is what makes the spelling change provable by IR identity, and it is
     also why the places inherit one set of diagnostics rather than growing a
     parallel set. The three emitters' own messages were renamed to `set!`,
     the only spelling left.
   - **The return-value asymmetry is preserved exactly.** `set!` on a name
     yields the assigned value (the REPL echoes it); `ptr-set!`, `aset!` and
     `.set!` all yielded `void`, so the corresponding places do too. Unifying
     them would change `cond`/`do` branch typing, and preserving them is what
     keeps the migration a no-op.
   - **The capture hazard, a third time.** `.set!` walked its *receiver*
     explicitly (index 1); the place form puts that receiver in **head
     position**, which `fn-capture-walk` skipped as "a call/special-form name,
     not a value reference" and `fn-rewrite-captures` kept verbatim. Both now
     walk index 0 — `is-local` (walk) and membership in `caps` (rewrite) are
     what keep a call to a global from being mistaken for a capture. This also
     closes the same hole for head-position member *reads*, which steps 3-4
     made idiomatic without noticing: `(get p 'x)` captured `p` and `(p 'x)`
     did not.
   - **`()` reads as a null node**, so the place judgement has to precede any
     deref. `emit-set` read `(target 'kind)` unconditionally, so `(set! () 3)`
     segfaulted — before this step as well; `emit-ptr-set` reached `emit-node`
     and got the real diagnostic.
   - **`node-type` needs the mirror split**, as in step 4: a non-`NODE-SYM`
     place yields `ty-void`. Guarding on the kind is also what keeps
     `split-typed` off a cell's null `s`.
   - **The rewriter needed a real s-expression parser again**, and two things
     about spans: the parser consumes a sigil (`'` `` ` `` `~` `@` `&`) *before*
     the atom it belongs to, so a naive span turns `'x` into `x`; and the
     backwards scan for those sigils must be floored by the previous sibling's
     end, or `v:&(Vector T)` claims the `&` twice. Every file was reassembled
     with rewriting *off* and asserted byte-identical first — 434 of 434.
   - **Verification is IR identity.** The same compiler compiling pre- and
     post-migration `src/` differs by **five string constants**, all inside the
     `with-handler` quasiquote template in `lib/error.nuc` — the same macro-
     template exception step 2 documented, since a template's selector is data.
     29 of 154 examples differ by exactly those five constants and nothing else.

   `inc!`/`dec!` stay symbol-only, which §3 already settled: a place form for
   them would either evaluate subforms twice or need `setf` expanders.
6. The `set` generic.

Selectors before places: `(set! (p 'x) v)` and `(set! (p x) v)` are different
migrations over the same 1428 sites, and places-first rewrites them twice.
