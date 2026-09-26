# `ptr` is the unchecked pointer; `raw` is retired

Stage 21 item 7. **Designed and built 2026-09-26** (BP-1 … BP-7; as built in
§7). The replacement for `(raw T)` was settled the same day (§4): `(ptr T)`
takes over the unchecked kind.

## 1. What drifted

`ref` and `ptr` were once one kind, with `raw` as the nullable one. Every
*typed* spelling still agrees: `(ptr T)`, `(ref T)`, `ptr:T`, `ref:T` and `&T`
all parse to `TY-PTR`/`PTR-REF`, and the 2026-09-25 probe matrix gave them
identical answers at every position. The drift is all in the **untyped**
pointer, which has three spellings and no agreed kind:

| Spelling | Kind today | Problem |
|---|---|---|
| bare `ptr` (`ty-ptr`, nucleusc.nuc:37) | `PTR-REF`, elem-less | The docs call it `void*`, but it is typed non-null. `pkind-flow-check` exempts it as a *destination* and passes it as a non-null *source*. |
| bare `raw` (`ty-raw`, nucleusc.nuc:55) | `PTR-RAW`, elem-less | It is the type of `null`, which makes it a third `void*`. |
| `(ptr void)` / `&void` | `PTR-REF` over `void` | It is a non-null `void*`. `(as &void &s)` is refused as a reinterpretation. |

What this causes:

- **A null hole.** Suppose `f` takes `(p:&S)`. Then
  `(let (q:ptr null) (f q))` compiles and segfaults.
- **A contradiction at `cond`.** `(when p …)` on a bare `ptr` is refused with
  "non-null, so this test is always true". Yet bare `ptr` is the type that
  holds `null` and every C `T*` (cheader.nuc `c-parse-type`).
- **Conflicting docs.** docs/types.md's table lists bare `ptr` as raw, while
  docs/special-forms.md:228 lists it as non-null.

## 2. The model after

| Surface | Meaning | Deref | Null? |
|---|---|---|---|
| `ptr` | **untyped, unchecked**: C's `void*`, and the type of `null` and of an imported C `T*` | no pointee | yes |
| `(ptr T)` ≡ `ptr:T` | **typed, unchecked**: today's `(raw T)` | allowed; safety is the author's problem | yes |
| `&T` ≡ `(ref T)` ≡ `ref:T` | **non-null** | always safe | no |
| `?&T` ≡ `(Maybe (ref T))` | **nullable, checked** | error until narrowed | yes |

The name says whether a pointer is checked. `ptr` in any form is unchecked,
`ref`/`&` is non-null, and `?` is checked. Unchecked pointers are unsafe, so
the policy (§6) is that most pointers become `&T` or `?&T`. `(ptr T)` is kept
only where the unchecked form saves significant complexity.

Rules:

- **Flow is unchanged from today's `raw` rules**, now under `ptr`'s name.
  - Widening is free: `&T` → `(ptr T)`/`?&T` → `ptr`, and `(ptr T)` ↔ `?&T`.
  - `null` flows into any nullable slot.
  - A `ptr` or `(ptr T)` source into a `&T` slot is refused everywhere,
    including `as`. The two ways out are `as-ref` followed by a narrow, or
    `unsafe/cast`.
  - `as` may still give a bare `ptr` an element type (`(as (ptr T) p)`), which
    is the existing `void*` hatch.
- **Condition.** `(when p …)` is allowed on both `ptr` and `(ptr T)`, alongside
  `?T` and `CStr`.
- **`void` pointee.** `(ptr void)`, `(ref void)`, `&void` and `?&void` are
  refused with the message "void has no pointee; write `ptr`". There is one
  use in the tree.
- **Retired spelling.** `raw`, `(raw T)` and `raw:T` become reserved names,
  with one targeted message naming `ptr`/`(ptr T)`, as `addr-of` was in PK-5b.
- **Diagnostics.** A diagnostic spells the unchecked kind `(ptr T)`. Messages
  that say "raw pointer" become "unchecked pointer".
- **`CStr` is out of scope.** It keeps its own type kind.

Internals:

- `PTR-RAW` stays as the kind (renaming it to `PTR-UNCHECKED` is optional).
- `ty-raw` merges into `ty-ptr`.
- `pkind-flow-check`'s elem-less *destination* exemption becomes the ordinary
  widening rule.
- `pkind-meet` is unchanged.

## 3. Measured scope

The measurements come from a scratch compiler, instrumented behind env flags,
that reports each refusal and continues. The hook printed a line but no module,
so the per-line counts for `src/` are approximate.

| Change | Compiler (distinct lines) | Each example |
|---|---|---|
| bare `ptr` becomes unchecked | 827 `as` refusals + 11 flow refusals | ~25, almost all in prelude/`lib/` |
| every `(raw T)` becomes checked `?&T` (the upper bound for §6) | 1,132 deref refusals | ~22, almost all in prelude/`lib/` |

Spelling counts (typed occurrences):

| Tree | `(ptr T)` / `ptr:T` (non-null today) | `(raw T)` / `raw:T` |
|---|---|---|
| src | 855 | 2,149 (1,002 of them `(raw Node)`) |
| lib | 17 | 298 |
| examples | 33 | 43 |
| tests | 281 | 144 |

Most of the 827 `as` refusals share one shape: `(aref (as &ptr vals) k)` or
`(as &i32 seen)`. That is an untyped buffer handed out as a typed element
pointer, and `as` passed it only because bare `ptr` was mislabelled.

The kind never reaches IR, so every step is gated **byte-identical** by
`ir-snapshot.sh`.

## 4. Decision: what replaces `(raw T)`

The options:

- (A) Checked `?&T`.
- (B) `?&T` absorbing the unchecked rules.
- (C) Keeping the kind under a new spelling.

The user chose a form of (C) with (A) as policy: **`(ptr T)` is the unchecked
kind**, usable everywhere `(raw T)` is today. Because unchecked pointers are
unsafe, the sweep then makes most of them `&T` or `?&T` (§6). This keeps the
rename mechanical, and it keeps the type-safety work as its own measurable
step. The earlier draft's retirement of `as-ref` is dropped: `as-ref` is still
how a `(ptr T)` becomes `?&T`.

## 5. Steps

`(ptr T)` changes meaning, and the source and the boot compiler must never
disagree about it. So the non-null uses leave the spelling first, the compiler
learns the new meaning while no source uses the spelling, and only after a boot
refresh does `raw` move onto it.

- **BP-1: small fixes, no sweep.**
  - `cond` accepts bare `ptr`.
  - The `void`-pointee spellings are refused.
  - docs/special-forms.md:228 is fixed.
- **BP-2: vacate the spelling.**
  - Every non-null `(ptr T)` / `ptr:T` in src, lib, examples and tests becomes
    `&T`. That is 1,186 sites.
  - The work is a new rule in `scripts/stage21/sugar-sweep.py`.
  - Bare `ptr` is untouched.
  - Gated byte-identical.
- **BP-3: the compiler reads `(ptr T)` as unchecked.**
  - The type parser gives `(ptr T)` / `ptr:T` the `PTR-RAW` kind.
  - No source uses the spelling any more, so nothing else changes.
  - **Boot refresh**, so the boot agrees about `(ptr T)`.
- **BP-4: move `raw` onto `ptr`.**
  - `(raw T)` → `(ptr T)` and bare `raw` → `ptr` across the whole tree.
  - `raw` becomes reserved with its message.
  - Diagnostics spell `(ptr T)`, and the tests that assert them are updated.
  - Behaviour-neutral and byte-identical. The whole tree is swept together,
    because the boot builds `nucleusc` from `lib/`.
- **BP-5: bare `ptr` becomes unchecked.**
  - Flip `ty-ptr`'s kind, and type `null` as `ptr` (`ty-raw` merges into it).
  - Clear the ~838 refusals. The preferred fix gives the holder its element
    type. `(as (ptr T) buf)` is for a buffer that really is untyped.
  - This closes the null hole. C pointers bound for a typed non-null slot now
    go through `as-ref`/narrow or `unsafe/cast`.
- **BP-6: make pointers well-typed** (§6). One module at a time,
  `(ptr T)` → `&T` / `?&T`, gated byte-identical.
- **BP-7: gates and docs.**
  - Tests:
    - the null hole as a refusal;
    - `cond` on `ptr` and `(ptr T)`;
    - the `raw` message;
    - the `void`-pointee message;
    - `(ptr T)` → `&T` refused through `as`.
  - Rewrite docs/types.md "Pointer kinds" and the diagnostic spelling table.
  - Update the matching rows in docs/builtins.md and docs/special-forms.md.
  - Re-baseline the goldens.
  - Final boot refresh.

## 6. The well-typing sweep (BP-6)

A pointer should be `&T` or `?&T` unless the unchecked form saves significant
complexity.

**Instrument.** Run the scratch compiler with `(ptr T)` treated as checked. It
lists every deref of an unchecked pointer, and the 1,132 figure is the upper
bound.

**Order.** Take the Node sites first:

- `ty-raw-node` and the macro-parameter type (nucleusc.nuc ~2605, ~16377)
  become `&Node`.
- Since item 6, `()` is non-null. So macro parameters, quasiquote results,
  `gensym` and in-range `node-at` are never null.
- That settles most of the 1,002 `(raw Node)` sites. It is the "`&Node`
  promotion" left open by item 6 §8.5.
- Macro bodies that test a node against `null` should ask `node-len` or
  `node-kind` instead.

Then work module by module, largest first.

**Classify each site** by what flows into it:

- If only `&`-valued expressions, compound literals or allocations flow in, it
  becomes **`&T`**.
- If `null`, a lookup or a "none" return flows in, it becomes **`?&T`**, and
  its derefs narrow through the existing idioms (`(when (= m null) (return
  …))`, `(when m …)`, `if-some`).

**Keep `(ptr T)`** only where narrowing would cost real structure. The
expected cases:

- intrusive links walked in hot loops, where the null test is the loop
  condition;
- fields that are null only during two-phase initialisation;
- C-boundary values.

Each kept category is recorded here as it is found, not commented per site.

**Adjacent but separate.** `(= r null)` on a non-null ref still compiles
silently (item 6's companion list). BP-5 gives every kind a distinct meaning,
which makes that check straightforward to add, but it is not part of this item.

## 7. As built (2026-09-26)

1,192 tests pass, `make bootstrap` converges, and the boot is refreshed.
Every step from BP-2 on kept the compiler's, every `lib/` module's and every
example's `.ll` byte-identical. Only diagnostic strings and the generated
`.nuch`/`.h` files changed.

**BP-5.**
- About 908 `(as &T p)` forms on a bare-`ptr` operand became
  `(unsafe/cast &T p)`. They were found by an instrumented compiler that
  reported each refusal and carried on.
- The rewrite must run **once**. A second pass over the same measurement
  respelled forms it had already fixed, and a repair script had to restore the
  heads from HEAD.
- `Maybe` over `(ptr T)` is a niche.
- `type-spelling` writes `ref:` for every pointer kind, so a template stamp
  ignores pointer kind.
- C headers write `T*` for every kind, with `/* nullable */` after a `?&T`.
  A `!&T` gets `/* niche: reserved top page = error */` instead
  (`niche-c-note` in cheader.nuc).
- The `generic-find-or-new` helper and the prelude's `new` macro produce a `&T`
  directly, so their callers need no cast.

**BP-6 method.** The site-by-site classification in §6 is not practical at
2,294 occurrences, so the classification was measured:

- A scratch compiler treats each `(ptr T)` as checked. At the point a `ref` or
  `Maybe` type is created during parsing, it records the Type* against the
  declaration line.
- Each refusal names the declaration that caused it. There are nine probes:
  flow, flow-into-Maybe, `as`, deref, `cond`, `defvar`, null-compare, `as`
  to Any, and no-op `as`.
- Round A starts with every declaration as `&T`, demotes to `?&T` each one
  that null reaches, and repeats until nothing moves. Round B does the same
  from `?&T`, moving each declaration whose deref is refused back to `(ptr T)`.
  Round C runs A and B together to a fixed point.
- Zero-initialised struct fields are invisible to every probe (see below). The
  null-compare probe found them.

**Outcome.** Of 2,294 occurrences:

| Result | Count |
|---|---|
| `&T` | 410 |
| `?&T` | ~1,505 |
| kept `(ptr T)` | 377 |
| `unsafe/cast` type arguments, left as written | 13 |

The kept sites are 244 locals, 85 `defn` signatures, 32 `as` targets and 15
struct fields. By element they are 150 `Node`, 98 `Type` and 44 `StructDef`.
Each falls into one of three categories:

- **Count-bounded arrays.** `(aref p i)` under an `i < n` bound.
- **Deref after a check narrowing cannot see.** For example, `node-first`
  after `(> (node-len n) 0)`.
- **Unchecked sources.** `aref`, `unsafe/cast` and C results, handed on
  without a test.

**The zero-init hole.** Struct fields are zero-initialised. So a `&T` field
that one constructor forgets to set holds null, and nothing refuses it. Loop A
promoted four such fields to `&T`. They were demoted by hand:

- `StructDef.fields` became `?&`, because a name-only pre-registered struct has
  none.
- `Method.constraints` stays `(ptr T)`.
- `Val.lvalue-sym` and `Sym.home` became `?&`.

**Node.**
- Macro parameters and `gensym` are `&Node`. Arity is checked and `&rest` is
  `()`, so none is null.
- `ty-raw-node` is renamed `ty-ptr-node`, still unchecked. It types the
  results of qq, `quote` and `ast-*`, because a macro body may test those.
- lib/macros.nuc's vacuous null tests on macro parameters are gone. A new test,
  `s21-macro-params-are-ref`, refuses one.

**Other changes.**
- The sweep left 266 `(as T x)` forms whose `x` already has type T. They were
  removed in src/ and lib/. The examples keep theirs, because and-narrow,
  as-conversions, errptr and maybe demonstrate `as`.
- The `Allocator` protocol's `alloc`/`realloc` results and pointer parameters
  are `?&ui8`.

**Found, not fixed.**
- **Vacuous null-compares.** Twelve `&T` values that predate this item are
  compared against `null` as a defensive check, which can never succeed. Among
  them are `g-boxedfn-table`, `g-dyn-table`, three in generics.nuc and two in
  examples/colon-paren-types.nuc. The `(= r null)` refusal (above) would flag
  them.
- **A `try` defcast gap.** docs/reading.md's `load` example fails with "err
  expects an Err (i32) value". A `defcast` is not applied on `try`'s error
  path. The failure predates this item and reproduces on the old boot.
