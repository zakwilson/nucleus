# C7 — the interned substrate

Track C's last conversion phase, and the one [overview.md](overview.md) §3 calls
"highest-risk and deliberately last". C6 closed on 2026-09-02 having converted
every string in the compiler that is *text*; what is left is the single class it
deliberately did not touch — strings that are **names**, read for identity.

This document is the plan for moving them to `Symbol`. It exists because the
overview's one-paragraph sketch leaves three decisions unmade, and each of them
changes what the edit looks like at several hundred sites.

---

## 1. What is actually left

`make strict-cstr` reports 3,320 residual sites. Grouped by what the string *is*:

| Class | Sites | Where |
|---|---|---|
| `strcmp`, compiler-synthesized (`=` on two `CStr`s) | 468 | everywhere |
| `to-str` on a `CStr` argument | 411 | every `fstr`/`emit` whose argument is a name |
| `conj` of a `CStr` | 177 | `(Vector CStr)` registries |
| `string-as-cstr` (what `fcstr` expands to) | 173 | 197 remaining `fcstr` sites |
| `strcmp`, written | 149 | `lib/node.nuc`'s table, arm/field lookups |
| `intern-symbol` / `intern-str` / `arena-strndup` arguments | 212 | the interner itself |
| `type-spelling` returns | 87 | conformance keys, generic substitution |
| `strlen` | 81 | length of a name |
| `assoc` / `scope-lookup` / `scope-define` / `generic-lookup` / `conformance-lookup` / `tyvar-index-of` / `lookup-struct` / `union-arm-index` / `marker-named` arguments | ~300 | every registry |
| `strchr` for `:` or `/` in a spelling | 37 | colon-chains, namespace qualifiers |

Every row is the same underlying value read through a different hole: a name the
reader interned, or a name the compiler minted and interned. There is no second
class hiding in the count.

Source-side the surface is **574 `'s` field reads** across `src/` (some of which
are `Tok.s`, not `Node.s`) plus the registry signatures they feed.

## 2. The three decisions

### 2.1 A spelling test against a literal is `symbol-is`, not a pre-interned global

326 sites compare a name against a written literal — `(= (n 's) "ptr")`,
`(= h "defstruct")`. Three ways to keep those working once the left side is a
`Symbol`:

- **(a) intern the literal at the comparison.** One hash of the literal per
  test. Strictly worse than today's `strcmp` for the short names these are.
- **(b) `symbol-is sym "lit"` — compare the symbol's view against the literal.**
  Length check, then `memcmp`. Same cost as the `strcmp` it replaces, minus the
  `strlen` (the length is a load behind the pointer).
- **(c) pre-intern every keyword into a global `Symbol` and compare by
  identity.** Fastest — one `icmp eq ptr` — but it needs ~200 globals, an
  initializer that must run before the reader, and a rule that no site may
  compare against a literal that is not in the table. A name that *should* have
  been in the table and is not fails silently: the comparison compiles and is
  always false.

**Decision: (b).** It is a wash on cost against what it replaces and it cannot
fail silently. (c) is a legitimate later optimization *on top of* (b) —
`symbol-is` against a literal is exactly the shape a peephole could fold — and
it is not worth buying a whole-program initialization order problem for while
the conversion is in flight.

Note also what does **not** need this: the compiler already compares *head
positions* by interned `Node*` identity (`(= hd0 'as)`, 151 sites). Those are
untouched — they are already one `icmp`, and `Symbol` neither helps nor hurts
them.

### 2.2 `Symbol` is promoted to the prelude; its methods are not

`Node.s` becoming a `Symbol` requires the *type* to be registered in every
compilation unit — the reader, the macro JIT module, and the bootstrap all build
`Node`s. That is precisely the situation `StrView` was in at NS-1, and it gets
the same answer: the bare

```lisp
(defstruct Symbol p:(ptr ui8))
```

moves into `lib/prelude.nuc` beside `StrView`, and `lib/intern.nuc` keeps every
`defn`/`extend`.

**`Symbol` is one word, so `Node`'s layout does not move.** This is the property
§2.4 was designed around and it is what makes C7 survivable: the macro ABI, the
JIT's view of `%Node`, and every `sizeof Node` are unchanged, so a mistake
manifests as a type error rather than as a wrong-layout miscompile.

### 2.3 `lib/intern.nuc` splits, because `lib/node.nuc` cannot import it

`intern-symbol` must delegate to `symbol-intern` — two intern tables over the
same names would defeat the identity invariant the whole design rests on. But
`lib/node.nuc` today imports only `arena`, while `lib/intern.nuc` imports
`fmt`, `vector`, `string`, `strview-str` and `error`. Making every program that
uses `:rest` or a macro pull the entire string stack is not acceptable.

**Decision: split it the way `strview` is already split.**

- `lib/intern.nuc` — `symbol-intern`, `symbol-from-cstr`, the table, `symbol-len`,
  `symbol-cached-hash`, `symbol-as-view`, `symbol-as-cstr`, `Eq`, `Hash`.
  Imports: `strview`, `hash`, `error`, `char`, `numeric`.
- `lib/intern-str.nuc` — the `ByteStr` / `Str` / `ToStr` conformances, which are
  what need `fmt`, `string`, `vector` and `strview-str`.

`lib/strview.nuc` / `lib/strview-str.nuc` is the same split for the same reason,
so this introduces no new pattern.

**Amended at C7-2 (2026-09-02): the cut above is not deep enough.** The AVR
16-bit gate failed the moment `lib/node.nuc` imported `intern`, because
`avr-reject-f64` (src/abi.nuc) refuses an `f64` *annotation* anywhere in the
translation unit, and `lib/numeric.nuc:39` and `lib/hash.nuc`'s `f64`
conformance are both reached from `strview`. "Not acceptable" in the paragraph
above turned out to be literal: those imports do not merely bloat a macro-using
program, they make it un-compilable for an 8-bit target.

So `lib/intern.nuc` imports **libc and `lib/fnv.nuc`, and nothing else**:

- `lib/fnv.nuc` (new) — `fnv1a-byte`, `fnv1a-int`, `fnv1a-bytes`, lifted out of
  `lib/hash.nuc`. `strview-hash` and `symbol-intern-bytes` now share one fold
  instead of two copies of the loop.
- `lib/intern.nuc` — the table, `symbol-intern-bytes` (the primitive; `src`+`n`
  rather than a `(ref StrView)`, so it needs no constructor), `symbol-intern`,
  `symbol-from-cstr`, the header accessors, and the bare `=`/`!=` overloads.
  `StrView` is a prelude type, so taking and returning one costs no import; the
  view is built with `alloca` + `set!` because `strview` itself is a method.
- `lib/intern-str.nuc` — the `Eq` and `Hash` conformance *records* as well as
  the text conformances. The `=`/`!=` overloads resolve on their own; only the
  registry rows need `numeric` and `hash`.

The header offsets moved with it: `-8`/`-16`/`16` were 64-bit literals, and
`usize` is two bytes on AVR. They are now a `SymHeader` struct and `sizeof`.

---

## 3. Steps

Each step gates on the full set — `ir-snapshot.sh verify`, `make test`,
`make bootstrap`, `make strict-cstr` with the borrow count at 0 — and lands
before the next begins.

### C7-1 — split `lib/intern.nuc`, promote `Symbol` to the prelude

No compiler change. Purely additive to every artifact (a new prelude struct with
no methods), so the snapshot moves only by that addition.

### C7-2 — `lib/node.nuc`'s table becomes `lib/intern.nuc`'s

`intern-symbol` keeps its signature and its `ref:Node` result, but the canonical
bytes it stores in `Node.s` come from `symbol-intern` instead of `arena-strdup`.
`Node.s` stays typed `ptr` for this step.

The observable change is that the bytes now carry the `[hash][len]` header, which
nothing yet reads — and that `intern-hash` and the `strcmp` per probe are gone.

`InternEntry` survives, unlike the sketch above: `lib/node.nuc` still owns a
canonical-`Node`-per-spelling map, which is what `(= hd0 'as)` compares, and the
bytes it keys on are now the interner's, so the probe is a pointer compare. Its
helpers were renamed `sym-node-place` / `sym-node-hash` / `sym-node-grow` —
`intern-grow` collided with `lib/intern.nuc`'s, and the collision was resolving
by overload mangling (`@intern_grow.usize`) in every module that imported both.

Gate note: identity is preserved by construction (one table of bytes), and the
bytes stay NUL-terminated, so every `(n 's)`-as-`CStr` read is unaffected. This
step is where a mistake would show up as a *wrong* program rather than a type
error, so it lands alone.

### C7-3 — `Node.s : Symbol`

The bulk. 574 read sites, of which the mechanical majority are one of:

| Today | Becomes |
|---|---|
| `(= (n 's) "lit")` | `(symbol-is (n 's) "lit")` |
| `(= (a 's) (b 's))` | unchanged — `=` on two `Symbol`s is the identity compare |
| `(strlen (n 's))` | `(symbol-len (n 's))` |
| `(fstr … (n 's) …)` | unchanged — `Symbol` conforms to `ToStr` |
| `(n 's)` into a `CStr` parameter | `(symbol-as-cstr (n 's))` |
| `(strchr (n 's) 58)` | `(strview-find-byte …)` on `(symbol-as-view (n 's))` |

`Tok.s` moves with it (the reader builds `Node`s from `Tok`s), and
`nucleus_gensym` mints its `__gs_N` through `symbol-intern` — which is a
correctness improvement in passing, since a gensym symbol is currently the one
`Node` whose `s` is not interned at all.

**Done, in two commits.** C7-3a landed `symbol-is` and the `=`/`!=` overloads
over `(Symbol, StrView)` as a library addition; C7-3b flipped the field. The
table above is what the step *would* have cost with `symbol-is` spelled out —
the operator overload is why row 1 needed no edit at any of its 326 sites, and
`ToStr` is why row 4 needed none at any of its. What was actually written is
rows 5 and 6, and those are **bridges, not conversions**: 178 `(sym-ptr …)` and
18 `(sym-of …)` calls, both one-liners in `src/strfmt.nuc`, deleted by C7-4 and
C7-5 when the registries stop being `ptr`-keyed. They exist because the field
moved before its consumers did; converting the consumers in the same commit is
what the phase split exists to avoid.

Three findings the step produced. **`emit-quote-tree` had to start interning** —
it wrote a bare `@.str.N` pointer into `Node.s`, which has no `[hash][len]`
behind it, so the first `symbol-len` on a quoted literal SIGBUS'd the
self-compile; it now emits a `@symbol-intern-bytes` call. **A cell has no name
rather than a null one** — `Symbol.p` is non-null by type, so `cons` allocates
with `calloc` and asks `symbol-none?`. And **string literals now carry embedded
NULs**, because the length `lex-string` always computed finally has somewhere to
live; `examples/hex-escape-test.nuc` had pinned the old truncation precisely so
that this would be a visible change.

### C7-4 — the registries

Scope keys, struct-field names, `type-spelling`, `fnty-intern`'s `__fnty_N`,
`Sym.ir-name`, `Method.ir-name`. Each is a `Symbol`-keyed lookup afterwards, so
the per-probe `strcmp` becomes an `icmp` and `tyvar-index-of`'s
already-identity-based scan becomes honestly typed rather than accidentally
correct.

`type-spelling` is the interesting one: it is *both* a conformance-registry key
and generic-substitution replacement text, which is why C6 left it alone. As a
`Symbol` it is honestly the first and `symbol-as-view` gives it the second.

**Split in two.** C7-4a converts every registry **key** — what a lookup is keyed
*by*. C7-4b converts the ir-name substrate — `Sym.ir-name`, `Method.ir-name`,
`ProgDefn.ir-name`, `StructDef.ir-name`/`ir-prefix`, `trace-saved` — which is not
a key but an *emitted spelling*, produced by `ir-name-token`/`sanitize-for-ir`
and compared by identity only as an optimization. Keeping them `ptr` through
C7-4a is what lets the key conversion be a single typechecker-driven sweep: an
`ir-name` retyped in the same pass would have dragged `src/format.nuc`'s return
types with it, and those feed the byte-identical bootstrap.

**C7-4a done (2026-09-02).** 45 struct fields, ~200 signatures. Three defects it
exposed, all of them the same shape — a *name-shaped* thing that was not a name:

- `binding-probe` returns a registry **payload record**, not a spelling. Two of
  its fourteen rows (`BK-SPECIAL`, `BK-PRIMITIVE`) have no record and return the
  spelling itself as the payload-free "yes", which is what made the whole return
  look like a name. Interning a `MacroDef*` as a C string segfaults on the first
  trivial program.
- `op-name-token` composes `ir-name-token` *then* `sanitize-for-ir`; dropping the
  inner call silently downgraded `?`→`_QMARK` to the blanket `?`→`_`, which the
  bootstrap caught as `@contains_.pHashSet` against `@contains_QMARK.pHashSet`.
  This is exactly the SM-3 ordering `src/format.nuc`'s header comment pins.
- `NameRef.qual` is a **slice** of the spelling, so it is a `StrView` and not a
  `Symbol`; `(as CStr view)` compiles (it takes the `data` word) and then prints
  to the NUL — `'dp/Describe' is not in scope` for a qualifier that is `dp`.

The first is why a payload pointer must never be bridged with `sym-of`, and the
other two are why the gate set is three gates: neither the segfault nor the
mangling regression is visible to `make test` alone.

**C7-4b done (2026-09-02).** The substrate splits again, and the split is the
step's one real judgement:

- **`StrView`, not `Symbol`** — `Sym.ir-name`, `Sym.cslot`, `Sym.trace-saved`,
  `CastRule.ir-name`, `Cleanup`'s `slot`, and the `type-mangle-token` /
  `sanitize-for-ir` / `sanitize-for-c` / `ir-name-token` return types. This is IR
  *operand* text — `%x.addr.7`, with a per-binding counter — and the local
  population dominates by orders of magnitude, so interning it would pay a hash
  per binding to buy an identity nothing asks about. `ir-name-token`'s fast path
  now returns its argument with no copy at all, which the `ptr` return could not
  do.
- **`Symbol`** — `Method.ir-name`, `StructDef.ir-name`/`ir-prefix`,
  `ProgDefn.ir-name`, `Generic.ir-prefix`, `NsPrefixEntry.prefix`,
  `PrivFile.prefix`, `Cleanup`'s `dropfn`. These are link names and prefixes,
  and every one of them is identity-compared.

The two consumers that need identity over a *local's* ir-name —
`program-defn-lookup` and the macro-JIT declare set — are global-only, so they
intern at their own boundary (`macro-jit-ensure-decl`, `program-defn-record`).
`program-defn-lookup`'s membership test was a `strcmp` and is now one `icmp`.

Three defects, all of them the silent borrow rather than the wrong type:

- Five `(strview-from-cstr (as CStr null))` sites the driver produced from
  declarations it had just retyped: `strview-from-cstr` is **strict** where
  `(as CStr …)` was lazy, so `strlen(null)` crashed on `prescan-defenum-names`
  over the prelude's `(defenum NodeKind …)`.
- `%unbound.addr.49%` in `stage2.ll`: `(strview-from-cstr (as CStr slot))` where
  `slot` had become an `fstr` result. An `fstr` buffer is **not** NUL-terminated,
  so `strlen` ran into the next arena allocation.
- `(!= (sym 'ir-name) null)` in `repl-note-globals-decls` — see below.

The last one is the reason C7-4b also changes the language. A `StrView` operand
against the `null` literal fell into the `CStr` `strcmp` lowering and compared
its `.data` word against `NULL`: the documented null-check trap, one level down,
and invisible to `--strict-cstr` because the borrow happens inside the operator's
own lowering rather than at a `CStr` parameter. It is a type error now
(`a StrView is never null — use (str-empty? &v)`), with a regression test. Every
REPL test failed on it and nothing else did, which is the argument for `make
test` being in the gate set beside the bootstrap and the snapshot.

The snapshot gate needed **no re-baseline**: all 2,624 artifacts stayed
byte-identical, which is the evidence that the substrate retype changed no
emitted spelling.

### C7-5 — `intern-str`, `arena-strndup` and the last producers

`intern-str` becomes `symbol-intern` at its 88 sites; the `arena-strndup`
producers that feed a name (rather than a buffer) go with them.

---

## 4. Risks

- **The macro JIT resolves `intern-symbol` against the compiler process.** A
  JIT'd macro body calling it must see the same table the compiler's reader used,
  which it does today only because there is one process-global. `symbol-intern`'s
  globals live in `lib/intern.nuc`, which the JIT module imports separately —
  **verify before C7-2** that the JIT resolves to the compiler's copy and not to
  a second set of globals. If it does not, the identity invariant breaks across
  the macro boundary and the failure is a quoted symbol that is `!=` to a
  reader-produced one of the same spelling.
  *Resolved at C7-2:* it does. The JIT resolves `g-sym-table` against the
  compiler process like any other program global, and the whole macro/quasiquote
  half of the suite (`examples/symbol-identity.nuc` included) passes with one
  table. No shim was needed.
- **`Symbol` is a struct, so `(n 's)` in a variadic position contributes its
  word rather than decaying.** The `%s`/`printf` seams are gone (C1/C2), so this
  should be unreachable — but `--strict-cstr`'s borrow check does not cover it,
  and `docs/strings.md` records that a `StrView` vararg contributes only `.data`.
  Audit the remaining `fprintf`s in `src/repl.nuc` before C7-3.
- **Bootstrap.** Every step changes a type the boot compiler must already
  understand. `Symbol` is a plain one-word struct, so this is the ordinary
  `make update-bootstrap` refresh rather than a shim — but C7-3 changes
  `lib/prelude.nuc`, which the boot compiler reads, so the refresh has to land
  *between* C7-1 and C7-3 rather than after.

## 5. What C8 then has left

The residual `CStr` list of §2.7 — `src/llvm.nuch`, `argv`/`getenv`, the
`popen` command lines and the linker command line, `declare`d C signatures, and
the `.nuch`/`--emit-cheader` surfaces. Anything else the tripwire reports is a
bug or an explicit addition to that list.
