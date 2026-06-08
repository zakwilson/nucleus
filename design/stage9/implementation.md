# Implementation in the compiler

#### Designer

Much of the current compiler source, libraries, and example code are from an earlier point in Nucleus development when the language had fewer features. Now is a good time to refactor the compiler, applying current features to improve readability, reduce bloat, and exercise the capabilities of the language.

Here are examples that might be improvable:

* strcmp/strncmp are used frequently throughout the compiler. Interned symbols may be a better choice in a lot of cases.
* The Eq protocol should also be extended to strings so bare calls to strcmp are no longer used to test string equality.
* Allocators getting passed `(cast i64 (sizeof T))` or the like is verbose. Methods that do the Right Thing with a symbol that resolves to a concrete type would be shorter and more readable.
* Hardcoding i64 is probably wrong when potential compilation targets are not all 64-bit.
* `set!` can be generic at this stage without requiring a new concept of a *place*. An arglist like `(s:T f:Sym v:V &where (T Struct) (V Any))` could call `.set!` internally, for example. `.set!` then becomes compiler-internal, mostly used to implement the method.
* `.` for field access should be replaced by the struct itself in the head position

#### Robot — review before refactoring (2026-06-08)

Checked each item against the tree. All six are worth doing, but two carry a
decision that should be made *before* touching code, and the items have shared
prerequisites that fix the order. Grounding refs in `src/nucleusc.nuc`.

**1. strcmp → interned symbols.** Sound; 145 `strcmp`/`strncmp` in the compiler.
But they are three populations with different mechanics and payoff, not one sweep:
  - *Symbol identity* (`&rest`/`&where`/`fn`, head-keyword dispatch). The clean
    win — the idiom already exists: head dispatch compares the **interned head
    node** by identity (`(= hp 'sizeof)`, src:1163+), not the spelling. Extend that
    pattern; an `Eq`-on-symbols method makes `(= sym 'foo)` read naturally **iff**
    item 2's type question is settled (see below).
  - *Field-name lookup* (`struct-field-index` src:3371, `emit-field-set` src:3432,
    src:1029). Can become identity **only after field names are interned**. Today
    they are not uniform: `extract-name-and-type` (src:782) yields a fresh
    `split-typed` substring in the simple-symbol case but the interned `(. car s)`
    in the desugar-cell case. So **intern field names at `defstruct`** (src:4756)
    first — this is also the prerequisite that makes item 6 fully identity-based
    (the callable-values `get` selector is already interned).
  - *Non-symbol strings* (type-name parsing src:637-653, float lexemes src:1232,
    `op-name-token` src:1758, mangled-name suffixes, IR text). These compare
    against C string *literals*, not symbols; interning doesn't apply without a
    keyword table. Mostly out of scope — leave them or do a separate table-lookup
    pass.

**2. Eq on strings — needs a designer decision; it is the gating item.** There is
**no string type**: a string literal is `TY-PTR` (`node-type` src:1154), and `=`
on `TY-PTR` already means **pointer identity** (`icmp eq`, granted to `ptr` by
`builtin-op-result-type` src:3189). So "extend `Eq` to strings" collides head-on
with "`Eq` on `ptr` = identity" — there is no string type to attach the strcmp
conformance to without redefining `=` on *all* `ptr` (or all `ptr:i8`), which
silently changes pointer comparison everywhere and breaks the compiler's own
`ptr` `=` and the bootstrap. Pick one before coding:
  - (a) introduce a distinct `Str` type (reader types `"..."` as `Str`, C interop
    treats it as `char*`); `=` on `Str` lowers to strcmp. Principled, unlocks both
    this item and the symbol-`Eq` ergonomics of item 1, but a real addition.
  - (b) keep a **named** `streq`/`str=` method (or an explicit `StrEq` protocol);
    do **not** overload `=`. Cheapest; preserves `ptr` identity semantics.
  - (c) overload `=` only on a new string type later; ship (b) now.
  Note: much "string equality" in the compiler is really *symbol* equality —
  route that through item 1's identity path, not a string `Eq`.

  **Resolved (2026-06-08) → option (a), named `CStr`. Landed.** C-style strings
  are now the `TY-CSTR` type (string literals are `CStr`); `=`/`!=` lower to a
  `strcmp` content comparison via the inline peephole (`emit-binop-vals`), and
  `CStr` conforms to `Eq` (`lib/numeric.nuc`). `CStr` is ABI-identical to `ptr`
  (lowers to `ptr`, `char*` in C) and interconverts freely in value positions;
  it is distinct only for `=`/`!=` dispatch. Unicode/`Ord` out of scope. See the
  Status section and `context/conventions.md` "CStr is ABI-identical to ptr".
  This does **not** auto-migrate the compiler's own `(= (strcmp a b) 0)` sites —
  those operate on `ptr`-typed fields/params (`name:ptr`), so the Phase-B item-1
  payoff (retype `ptr`→`CStr` where content equality is wanted) is still pending.

**3. allocator + `sizeof` verbosity.** Two distinct points:
  - `(cast i64 (sizeof T))` — the cast is **redundant**: `sizeof` already returns
    `ty-i64` (`emit-sizeof` src:3644). Drop the cast unconditionally, independent
    of everything else.
  - "method that DTRT with a symbol resolving to a concrete type" — a type is
    **compile-time**, not a runtime value, so this is a **macro/special form**, not
    a multimethod (multimethods dispatch on the runtime types of *value* args).
    `(new T)` → `(cast (ptr T) (arena-alloc (sizeof T)))` gives a correctly-typed
    pointer and collapses the cast+sizeof. Decide arena vs `malloc` flavor(s) and
    whether `new` zero-inits (`arena-alloc` already memsets; `malloc` does not).

**4. i64 hardcoding — real, but out of scope for *this* refactor.** This is target
portability, not "apply Stage 9 features," and has a different blast radius. The
compiler hardcodes `target triple = x86_64-pc-linux-gnu` in four places and only
targets x86-64, so the concern is latent (no 32-bit target exists). Doing it right
means a pointer-width int (`usize`/`size_t`) threaded through `sizeof`
(`ptrtoint … to i64`, src:3643), `type-size`'s ptr=8 (src:546), pointer
arithmetic, arena offsets, and `declare … @malloc(i64)`. **Recommend: separate
design note, sequenced last.** Item 3's macro already removes the verbosity that
motivates touching it now.

**5. generic `set!`.** Tractable and consistent with "no new *place* concept."
Today `emit-set` (src:4349) handles only `(set! sym val)` (local store);
`emit-field-set`/`.set!` (src:3416) handles the field store. Caveat: the
`(s:T f:Sym v:V &where …)` framing reads like a multimethod, but `set!` must
**not** evaluate its target as a value and `f` is a *field selector symbol*, not a
value — so this is **arity/shape dispatch in the special form** (2-arg sym ⇒
variable store; 3-arg `(set! s f v)` ⇒ `.set!`), not a true generic function.
Relationship to note: callable-values §4.3 explicitly **deferred** the
`(set! (s i) v)` place form; this item is the *symbol-selector slice* of that and
can land now while the integer/`invoke-set!` case stays deferred. (Also a parked
stage999 note: "`set!` should take multiple `let`-style pairs" — cheap to fold in
if touching `set!`.)

**6. `.` → struct in head position — already built; this is migration, not new
machinery.** Callable-values landed `(s 'field)` ≡ `(get s 'field)`,
**byte-identical** to `.`, with the literal-symbol static-GEP fast path. So the
work is mechanically migrating existing `(. s f)` sites and deciding **keep `.` as
sugar or remove it.** If *remove*: the compiler's own source uses `.`/`.set!`
pervasively and both are load-bearing (incl. `node-type` branches src:1191-1192
and `gcheck-special-form` src:2598), so sequence after items 1/5 and update
`node-type` in lockstep (per `context/conventions.md`). Standardize on one
selector spelling — bare `(s field)` (a bare symbol is *always* a field, §3.5) vs
quoted `(s 'field)`.

**Suggested order (each step `make bootstrap` byte-identical + `make test` green,
one commit per item so a regression bisects):**
  0. Decide item 2 (string type) and item 4 scope (likely: defer).
  1. Intern field names at `defstruct` (shared prereq for 1-fields + 6).
  2. Item 3 macros + drop redundant `(cast i64 …)` casts (isolated, cheap win).
  3. Item 1 symbol-identity sweep **with** item 6 `.`-migration (same interned
     machinery; both byte-identical by construction).
  4. Item 5 generic `set!`.
  5. Item 4 portability — separate note, only if in scope.

Items 1/3/5/6 should all be byte-identical at the IR level (same emission); only
item 2, if it changes `=` lowering, would require regenerating expected outputs.

**Status — landed (2026-06-08), `make test` 38/38 + `make bootstrap` byte-identical:**
- *Step 1 (field-name interning, item 1-fields).* Field names are interned at
  build time (`intern-str` helper, src/nucleusc.nuc); `struct-field-index` now
  matches by pointer identity, not `strcmp`; `node-type-field` and
  `emit-field-set` deduped onto it; `repl-register-node` interned to match. See
  `context/conventions.md` "Struct field names are interned." Unblocks item 6.
- *Step 2 (item 3).* Dropped the two redundant `(cast i64 (sizeof Node))` no-ops
  (the cast is i64→i64; `sizeof` already yields i64). Added `(new T)` to
  `lib/arena.nuc` (`(cast (ptr T) (arena-alloc (sizeof T)))`; arena-only, not
  prelude) and migrated the 7 single-object `(cast ptr:T (arena-alloc (sizeof T)))`
  sites in the compiler.
- *Item 2 — `CStr` + Eq.* New `TY-CSTR` kind (singleton `ty-cstr`, `type-to-ir`
  →`ptr`, `type-to-c`→`char*`, `type-size`→8, `type-mangle-token`→`cstr`,
  `type-spelling`→`CStr`, `parse-type-name "CStr"`); string literals typed `CStr`
  (`emit-string` + the 3 `node-type` NODE-STR sites). `=`/`!=` on two `CStr` lower
  to `strcmp`+`icmp` in `emit-binop-vals`; `builtin-op-result-type` grants `=`/`!=`
  to `CStr` so `(extend CStr Eq)` (in `lib/numeric.nuc`) verifies. Pointer-ABI
  parity via a new `is-ptr-like` predicate (`coerce-int-val` CStr↔ptr no-op,
  `emit-cast` no-op + inttoptr/ptrtoint, the `&rest` fold, and zero-init null).
  Example/test `examples/cstr.nuc` (+ `tests/expected/cstr.out`). Known boundary:
  `arg-adapts` does **not** adapt `CStr`→`ptr` (multimethod dispatch keeps `CStr`
  distinct on purpose); plain `ptr` functions still accept literals.
- *Item 1 Phase B — string-content `strcmp`→`=` migration.* All 229 content-equality
  `(= (strcmp a b) 0)` / `(!= … )` sites in `nucleusc.nuc` (151), `cheader.nuc` (59),
  and `repl.nuc` (19) rewritten to `(= a b)` / `(!= a b)`, plus 4 `->`-threading
  `(strcmp _ "x") (= _ 0)` forms → `(= _ "x")`. Enabled by a **mixed-operand rule**:
  `=`/`!=` where *either* operand is `CStr` lowers to strcmp (so `(= some-ptr "lit")`
  is a content test — a literal is `CStr`), while two plain `ptr` stay pointer
  identity. 15 genuine string fields/params retyped `ptr`→`CStr` (StructDef/Sym/
  Generic/Protocol/Conformance/MacroDef `name`s; a few lookup params) so both-`ptr`
  comparisons get a `CStr` operand; `Node.s` deliberately **kept `ptr`** (the
  interned-identity path from Step 1 must stay `icmp`). `strncmp` *prefix* tests
  (`-I`/`-l`/`-L`) stay. **`make update-bootstrap` was run first** (the boot binary
  predated `CStr` and would miscompile literals) — `boot/nucleusc.ll` + `bin/nucleusc`
  are now CStr-aware and part of the change set. Verified by `diff`ing the emitted
  `build/nucleusc.ll` before/after: **byte-identical** (every migrated `=` emits the
  same `strcmp`+`icmp` the old form did), so the refactor is provably behavior-neutral.

- *Item 6 — `.` → `_get` + head-position member access.* The `.` field-access
  special form was renamed **`_get`** (kept as the compiler-internal primitive;
  `emit-field-get` + dispatch in `emit-list`/`node-type`/`gcheck-special-form`).
  Ordinary code migrated to **head position `(s field)`** (the callable-values `get`
  path → Struct intrinsic, byte-identical GEP+load): ~1500 `(. s f)` → `(s f)`
  across `src`/`lib`/`examples`; 1-arg `->`-steps `(. f)` → `(_ f)` with the `->`
  macro extended to substitute `_` in **head** position (`lib/macros.nuc`). `.set!`
  unchanged (writes stay `(.set! s f v)`). Two collision classes handled with
  `_get` (see `context/conventions.md` "Member access is head position"): a
  special-form/macro-named variable in head position (only `cond`, in `emit-while`
  — renamed `cnd`), and a user `get` method reading its own field (`examples/callable.nuc`
  — recursion → `_get`). Compiler IR `diff`ed before/after: **only the `.`→`_get`
  string constants change** — otherwise byte-identical. `make update-bootstrap` run
  (boot now dispatches `_get`). 38/38 + bootstrap byte-identical.

**Still pending:** item 1's *symbol*-identity sweep over the non-string `strcmp`s
that are really symbol comparisons (now mostly already on the interned-identity
path); item 5 (generic `set!`); item 4 (portability).
