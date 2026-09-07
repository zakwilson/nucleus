# The `&` type sigil, and the `&` address-of operator

**Status: done** (2026-08-30). `&T` is sugar for `ref:T` in every type position
(§1–§5); `&x` is sugar for `(addr-of x)` in every value position (§6). The two
are split by position *within the token*, not by context. Bootstrap
byte-identical, `examples/ref-sigil.nuc` plus a six-part test unit
(`s16-ref-sigil-*`).

## 1. What it is

`ref:T` — the non-null pointer — is the most-written type constructor in the
tree, and it is spelled with the longest name of the three pointer kinds. The
`&` character has been reserved for this since
[keyword-markers.md](keyword-markers.md) retired the `&rest`/`&where`/
`&optional`/`&repr` special symbols; that item's stated motive was to free `&`
as a *prefix sigil*, and this is the sigil.

```
&T          ==  ref:T           ==  (ref T)
x:&T        ==  x:ref:T         ==  (x (ref T))
x:&(T …)    ==  x:ref:(T …)     ==  (x (ref (T …)))
):&T        ==  ):ref:T                             [return position]
&&T         ==  ref:ref:T       ?&T  ==  ?ref:T     &raw:T  ==  ref:raw:T
```

It is sugar in the strict sense: the two spellings emit **byte-identical IR**
(`s16-ref-sigil-ir-identical`), because they are the same string by the time
anything but the lexer sees them.

## 2. Where it is expanded, and why there

In the **lexer**, at the single point an atom's text is finalized
(`expand-ref-sigil`, `src/reader.nuc`, called from `lex-atom`'s TOK-SYMBOL and
TOK-KEYWORD tails). A `&` that starts a chain segment is rewritten to `ref:`;
the token that reaches the parser is the colon chain the source meant.

The alternative — recognizing `&` in the *type parser* (`parse-type-name` /
`parse-type-from-node`, beside the existing `?`/`!` prefixes) — looks more
principled and is worse, because a type spelling is read by more than the type
parser. `x:&T` desugars through `split-colon-segments`; `(Vector &T)` is walked
by `collect-pattern-tyvars`, which collects any unresolvable symbol as a
**tyvar** — so a bare `&T` in a template argument would have silently
registered `&T` as a type variable rather than failing. Every such consumer
would have needed its own arm. Expanding in the lexer gives all of them the
canonical spelling for free, and is the reason this change needed no edit to
the desugar pass, the generics machinery, or the type parser at all.

Two spellings come out of the reader for free as a consequence:

- **`x:&(Vector T)`** — the atom is `x:&`, which expands to `x:ref:`, which
  *ends in a colon* and so is picked up by the existing colon-paren fuse
  (`fuse-colon-paren`) with no change to it.
- **`):&(Vector T)`** — the keyword body `&` expands to `ref:`, and the same
  fuse produces the lone return type.

## 3. What `&` is *not*

**Not an interior symbol character.** The sigil is only a `&` at the start of a
chain segment — offset 0, after a `:`, after another sigil, or after a `?`/`!`
type prefix (`ref-sigil-seg-next` is the one place that rule lives, shared by
the count and build passes). `.&`, the field-address special form with ~200
uses in the compiler, is untouched, and so is any other interior `&`.

**Not a claim on the four retired markers.** `&rest`, `&where`, `&optional`
and `&repr` are left unexpanded, so `reject-legacy-marker` still answers them
with `'&rest' is no longer a marker -- write ':rest'` rather than letting them
read as `ref:rest` and fail somewhere else as `unknown type: rest`. The roster
was already written once, in `legacy-marker-name`; it is now
`legacy-marker-tail` (a `CStr`-level function beside it) so the reader consults
the same list rather than a copy.

**Not the address-of operator.** That is a separate rule at a separate layer —
the reader-macro table, §6 — which fires only on a `&` that begins a whole
token. The sigil proper is the mid-atom `&`, and it never means address-of.

**Not a weaker `ref`.** `&T` carries every obligation `(ref T)` does — a null
initializer is refused at a `defvar`, and a `raw` argument is refused at an
`&T` parameter, with the same diagnostics (`s16-ref-sigil-rules-preserved`).

**Not a serialization format.** A `.nuch` header carries the canonical
`(ref T)` / `:ref:T`, since the sigil is gone before any node exists to print
(`s16-ref-sigil-nuch-roundtrip`).

## 4. Known rough edge

The whitespace near-miss `x:& (Vector T)` reports

```
binding name ends in ':' (x:ref:) -- write name:(Type) with no space, or (name Type)
```

— it quotes the *expanded* atom, not the `x:&` the user typed. The token no
longer carries its original spelling by the time `split-colon-segments` raises
CP-3, and threading one through for a near-miss message is not worth a field on
`Node`. The guidance in the message is still the right fix, and the expansion it
shows is at least a true statement about what `&` means.

## 5. Adoption

Deliberately **not** adopted in `src/` or `lib/` in this change. Adopting a new
spelling in the compiler's own sources requires `make update-bootstrap` first
(the committed boot compiler is what builds `src/`, and it does not know the
sigil) — the two-commit dance recorded in
[container-type-sugar.md](container-type-sugar.md)'s adoption section. Leaving
`src/` alone keeps this change a pure fixed-point-preserving addition:
`make bootstrap` converges byte-identically with no boot refresh.

Whether to adopt is a separate call with a real trade-off. `ref:` appears ~1100
times in `src/`+`lib/`; `&` would save three characters at each and put the
pointer kind in a sigil, which is denser to read at a glance and easier to miss
when scanning for a pointer-kind mistake. If it is adopted, do it as one
mechanical sweep against a pre-adoption `build/nucleusc.ll`, the way the
`deftype` adoption was verified.

**Adopted 2026-09-06/07** — `src/` in `a15f38e`, then `lib/`+`examples/` (see
[progress.md](../progress.md)). One line was drawn that this section did not
anticipate: the sweep takes `&` only at an **interior** chain segment
(`p:ptr:T` → `p:&T`, `?ptr:V` → `?&V`), never standalone (`(as ptr:T x)`,
`(p (ref T))`). The interior form is the lexer rewrite of §2 and leaves no trace;
the standalone form is §6's reader macro, so the node is `(addr-of T)` and
`--emit-nuch`'s verbatim export of protocols and generic templates carries it
into the committed header. §6's "a spelling nobody writes" is true of
hand-written source and not of a mechanical sweep: `a15f38e` wrote 2,469 of them
into `src/` before the rule existed, and they were swept back out on 2026-09-07
— a cast operand to `ref:T`, a type expression to `(ref T)`, a binding pair to
the attached `name:&T` — with `build/nucleusc.ll` byte-identical across the
change, which is the proof that the two spellings only ever differed as text.

## 6. `&x` is `(addr-of x)`

`(addr-of x)` is written ~854 times in the tree (530 `src/`, 198 `examples/`,
109 `lib/`, 17 fixtures) and it is the most verbose thing in ordinary Nucleus
code. `&x` is the C++/Go/Rust/Zig spelling for it, and it is now the Nucleus
one:

```lisp
(sum-xy &a)                 ==  (sum-xy (addr-of a))
(let (ap:&Point &a) …)      ; the type sigil and the operator, one binding list
((as &Pt &p) x)             ; …and one form
```

### The layer: the reader-macro table, not the lexer

`@p` → `(deref p)` is `(register-rmacro v "@" "deref")` in `build-rmacros`
(`src/nucleusc.nuc`), and `def-rmacro` exposes the same table to users.
`&` → `addr-of` is one more line there.

The table is matched in `next-tok` **before** `lex-atom` runs, and only at a
token boundary. That is the whole design: a `&` that begins a token never
reaches `expand-ref-sigil`, and a `&` that does reach it (`p:&T`, `?&T`,
`):&T`) was by construction preceded by something. The two rules partition the
character by position in the token, and neither needs to know anything about
context.

The alternative — extending §2's lexer expansion to value position, so `&x`
becomes the symbol `ref:x` and something downstream re-reads it — is wrong, and
worth recording because it looks like the natural continuation of §2. Value
position **already has a grammar for `name:Type`**: it is an ascription that
lowers to `as` (`emit-symbol-ref`, `src/nucleusc.nuc` — `split-typed`, then
`as-convert` to the annotation). So `ref:x` there already parses, as *the
variable `ref`, cast to type `x`* — and `ref` is a legal binding name (a
*definition* may no longer take it, name-resolution.md §15, but a `let` or a
parameter still can, and that is the position this ambiguity lives in). Making
it mean address-of would carve a keyword exception out of a general rule, in
the same position the compiler's own source writes `q:CStr`, and would need
matching arms in `emit-symbol-ref`, `node-type-sym` (the `node-type`↔`emit-node`
lockstep) and `fn-rewrite-captures`. Wrapping with the existing `addr-of` head
instead costs **zero** value-side changes: the emitter, `node-type-addr-of` and
the closure capture rewrite all already match on that cell.

`def-rmacro` cannot be used for this from source — a unit is read in full
before its forms are processed, so a `(def-rmacro "&" addr-of)` does not affect
its own file (it does work in the REPL, which reads a form at a time). Hence
the built-in registration.

### Where the two meet

Exactly one spelling is shared: a standalone `&T` in a type slot — `(sizeof
&Pt)`, `(as &Pt q)`, `(link &Pt)`, `(Vector &Pt)`. The reader has no position
information, so it writes the value form, and the type slot is handed
`(addr-of T)`.

The fix is to read that head as `ref`, in the two places that classify a
pointer wrapper by head symbol:

- `parse-type-from-node` (`src/union-registry.nuc`) — the `(ref T)` arm
- `node-is-ptr-wrapper` (`src/generics.nuc`) — which is what
  `collect-pattern-tyvars` and `unify-tpat` both go through, so the tyvar
  collector and the pattern unifier come along for free

Nothing else needed an arm: `gcheck`'s wrapper-head test is a *value*-path
check (`(addr-of X)` there is a real call and must stay one), and the cheader
walkers see types, not the source node.

The cost is that `(addr-of T)` becomes a legal, strange way to spell `(ref T)`.
That is the price of a reader that decides before position is known. "A spelling
nobody writes" turned out to be wrong once a sweep was pointed at it — see §5,
and `--emit-nuch` prints the node.

### The retired markers, again

The rmacro fires before `lex-atom`, so it fires before §3's `legacy-marker-tail`
check can protect `&rest` — measured, it turned the located `'&rest' is no
longer a marker` into `unknown type: rest`. `at-legacy-marker` (`src/reader.nuc`)
restores it: a `&` at a token boundary whose token spells one of the four falls
through to `lex-atom`, where §3's rule takes over. It consults the same
`legacy-marker-tail` roster, so there is still one list.

### On the choice of `&`

`&` is the address-of operator in C, C++, Go, Rust, Zig, D, Swift, Hare and
Odin. The alternatives considered were `@` — Pascal/Delphi's address-of, and
the split Pascal itself uses (`^T` type, `@x` operator) — which is taken here
for `deref`, after Clojure; and `^`, which is wrong twice over: in the
Pascal/Odin family `^T` is the *pointer type*, the role `&T` already has here,
and in Clojure `^` is the metadata reader macro whose `^Type x` form reads as a
type hint. No language uses prefix `^` for address-of.
