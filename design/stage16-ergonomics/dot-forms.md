# Retiring the `.` forms, and the selector rule underneath them

**Status: in progress** (2026-08-30). **Steps 0 and 1 done** — every member form
takes the quoted selector, and `--strict-selectors` enumerates the sites that
still do not. See §5.

Three special forms are spelled with a leading dot — `.` (member read), `.&`
(member address) and `.set!` (member write). They are the last forms whose name
is punctuation rather than a word, and two of the three have a word-spelled
equivalent already. Retiring them turns out to be mostly a question about
something else: **what a bare symbol means in selector position**.

## 1. What is already true

Measured on this tree. Every one of these compiles and yields the same value:

```lisp
(. pp x)   (get pp x)   (get pp 'x)   (pp x)   (pp 'x)   (_get pp x)
```

`emit-get-intrinsic` is documented as byte-identical to `.`, and `get` is a
**generic**: user `get` methods are tried first and the field-access intrinsic
is the fallback. `selector-literal-sym` accepts either a bare `NODE-SYM` or a
`(quote sym)` cell, which is why the quoted spelling already works on every
read path.

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

Today a bare symbol in selector position **always** names a field. That is the
one place in the language where a symbol is not a variable reference, and the
W7 diagnostic exists to say so when a local shares the name.

The cost lands on the case that wants a field name in a *variable*:

```lisp
(get foo (quote bar))     ; producing the symbol
(get foo sel:ptr)         ; consuming one — the annotation is the only way to
                          ; force a symbol to read as a value
```

That is the defect. Computed access itself already works —
`emit-computed-field` lowers a runtime selector to a `select` chain over the
field indices — but its spelling is an escape hatch rather than a rule.

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

But head-position sites do not break *silently* under the new rule, because the
computed path is double-gated: the selector must evaluate to a `ptr`
(`computed selector must evaluate to a symbol (ptr)`) and the struct must be
homogeneous (`computed field access requires a homogeneous struct`). So
`(nn kind)` becomes `undefined: kind`, and `(nn line)` under a local `line:i32`
hits the ptr gate. Silent breakage needs all three of: a local shadowing the
field name, typed `ptr`, on a homogeneous struct.

So the migration is driven by the compiler, not by a regex: `--strict-selectors`
(§5 step 1) reports every bare selector, the tree builds at every step, and the
flag becomes the default when the list is empty.

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
invisible here too. There are only 5, and step 2 rewrites them by hand.

## 3. Retiring the forms

- **`.` → `get`.** Already equivalent; delete the form and rename 53 sites.
- **`.&` → `(addr-of p f)`.** An arity overload: 1-arg is today's `(addr-of x)`
  (which already requires a bare symbol), 2-arg is the member address. No
  ambiguity, no new dispatch.
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
2. Migrate `src`/`lib`/`examples`/fixtures under the flag; `make
   update-bootstrap` so the boot compiler speaks the new source. Drive it from
   the flag's output, deduplicated, and re-run per directory — one unit does not
   cover the tree (see §2).
3. Flip the default; retire the annotation escape hatch.
4. `.` → `get`, `.&` → `(addr-of p f)`.
5. `set!` as a place form; fold in `ptr-set!` and `aset!`.
6. The `set` generic.

Selectors before places: `(set! (p 'x) v)` and `(set! (p x) v)` are different
migrations over the same 1428 sites, and places-first rewrites them twice.
