# A `bool` type, and how much punning to put behind it

Evaluation of the overview's "Broad auto-cast to bool" item. The proposal is two
changes wearing one name, and they have opposite risk profiles:

1. **A dedicated `bool` type**, distinct from the integers.
2. **Broad auto-cast to it** — "all primitive values are true, `null`/`none` are
   false".

Recommendation up front: **do (1); do a restricted form of (2); drop the "all
numbers are true" rule.** That rule is the only part of the proposal that adds no
expressive power, and it is also the only part that cannot be revised later.

## What already exists

Measured against the tree at `136ac49`, not assumed:

| Claim | Actual |
|---|---|
| "Nucleus just uses i1" | `bool` is already a spelling — `builtin-type-name` maps it to `ty-i1` (src/union-registry.nuc:258), and it is documented in types.md, builtins.md and toplevel.md |
| No dedicated boolean | Correct in *semantics*: `(+ b:bool c:i1)` compiles and yields `1` |
| No broad acceptance | Correct: six sites raise on a non-`i1` condition — `cond` test, `while` condition, `not` operand, and `_and`/`_or` × lhs/rhs |
| Auto-cast is "obviously lossy" | The compiler already says so: `(as bool n:i32)` is `lossy conversion from i32 to i1 -- use unsafe/cast` |

Two more facts that matter for the design:

- **`bool` already dispatches.** `(defn g (x:i32))` and `(defn g (b:bool))`
  coexist and select correctly, because `TY-I1` is its own `TypeKind`. A distinct
  `bool` does not have to invent an overload key; it has one.
- **`0` and `1` already reach a `bool` slot.** `(g 1)`/`(g 0)` typecheck against
  `(defn g (b:bool))` — types.md's rule that `i1` holds exactly `{0, 1}`.

So "add a `bool` type" is not a new type so much as a **divorce**: stop `bool`
being an integer.

## Part 1 — the dedicated type is worth doing, and it is small

The change is: `TY-BOOL` becomes its own kind; `true`/`false` are its only
literals; `i1` stops being a user-facing integer (retire the spelling, or keep it
as a deprecated alias for `bool`); `(as i32 b)` stays legal and explicit;
`type-to-ir` still emits `i1`, so **no IR moves** and no ABI question arises —
the `_Bool` mapping in `type-utils.nuc:280` becomes honest rather than
coincidental.

What it buys:

- `(+ b c)` becomes an error instead of `1`.
- `(let (a:i1 0) …)` as a spelling of `false` goes away, and with it the
  documented `{0, 1}` range-check rule in types.md — this change **removes** a
  rule rather than adding one.
- A 1-bit integer is not useful as an integer. It holds `{0,1}`, so every
  arithmetic operation on it either wraps or is a boolean operation misspelled.
  There is nothing to lose by taking arithmetic away.

What it costs — measured, not estimated:

| Site | Count |
|---|---|
| `:i1` annotations in `src/` + `lib/` | 46 |
| of those, `):i1` return types | 25 |
| `:i1` in `examples/` + `tests/` | 16 |
| existing `bool` spellings | 3 |

Under 70 sites, mechanical. This is a smaller sweep than the `&rest`→`:rest`
marker flip already completed in this stage.

There is a second, larger, **optional** sweep hiding behind it: the ~40
predicates in `lib/` and `src/` that return `i32` (`str-empty?`,
`char-is-digit`, `node-is-list`, `contains-str?`, …). Retyping those to `bool`
is good hygiene on its own — and, as §3 shows, it is a hard prerequisite for any
version of part 2 that touches numbers.

## Part 1 and the C boundary

The reassuring half first: **part 1 changes nothing about the ABI, the IR, or the
generated headers.** The divorce is source-level. Every boundary mapping already
treats `bool` and `_Bool` as the same thing, and none of them is keyed on `bool`
being an integer:

| Surface | Today | After part 1 |
|---|---|---|
| `type-to-ir` | `i1` | `i1` — unchanged |
| `type-to-c` (`type-utils.nuc:280`) | `_Bool` | unchanged |
| `c-type-to-nucleus` (`cheader.nuc:329`) | `_Bool` → `ty-i1` | unchanged |
| C header parser on `bool` | works — `<stdbool.h>` expands to `_Bool` before the parser sees it (verified) | unchanged |
| `.nuch` round-trip | already spells it **`bool`**, not `i1` (`(declare pred ((a bool)) :bool)`) | unchanged |
| `sizeof` / align | 1 / 1 | unchanged |
| Struct layout | `{flag:bool n:i32}` is 8 bytes; the same C struct is 8 (both measured) | unchanged |
| `check-headers.sh` gate | green | stays green — no header output moves |

So there is no interop *migration*. `abi-classify` never looks at `TY-I1` (it
returns ABI-DIRECT for everything that is not a struct or union), and the 14
already-committed `_Bool` exports in `lib/strview.h`, `lib/string.h` and
`lib/keyword.h` — the comparison-operator overloads — keep the signatures they
have.

### What part 1 fixes at the boundary

`bool` being an integer today means a C `_Bool` that comes back through a header
is an arithmetic value. It cannot escape `{0,1}` — `(* b 2)` is already refused
(`integer literal 2 does not fit i1`) — but it can be silently *wrong*:
`(+ true true)` is **`false`**, because `i1` addition wraps at one bit. Part 1
makes that an error. This is the interop argument for part 1 on its own terms.

### What part 1 does not fix, and newly exposes

Three boundary gaps are **pre-existing**; part 1 neither creates nor repairs
them. It matters because part 1 takes `bool` from 3 sites in the whole tree to
the return type of every predicate, so all three go from theoretical to routine.

**1. No `zeroext` on `_Bool` parameters or returns.** Clang's `_Bool` ABI is
`i1` *with* the attribute:

```
clang:    define dso_local zeroext i1 @c_pred(i1 noundef zeroext %0, i32 noundef %1)
nucleusc: declare i1 @c_pred(i1, i32)
          define i1 @nuc_pred(i1 %a.arg, i32 %b.arg)
          define weak_odr i1 @eq.StrView.StrView(…)     ; an exported one
```

There are **zero** occurrences of `zeroext` or `signext` in `src/`, `lib/`,
`docs/` or `context/`. Every one of the 14 exported `_Bool` functions a C caller
can already reach is declared this way. It has not bitten yet because LLVM's
x86-64 lowering materialises `i1` into a zeroed register anyway — a backend
courtesy, not the contract the psABI states.

**2. Variadic calls skip C's default argument promotions — and this one is
already a live miscompile.** C promotes `_Bool`/`char`/`short` → `int` and
`float` → `double` in a variadic slot. Nucleus passes the narrow type:

```
nucleusc: call i32 (ptr, ...) @printf(ptr %t8, i8 %t9, i16 %t10, i8 %t11, float %t12, i1 %t13)
clang:    call i32 (ptr, ...) @printf(ptr @.str, i32 …, i32 …, i32 …, double …, i32 …)
```

One `printf` of five values, Nucleus against C:

| Argument | Nucleus prints | C prints |
|---|---|---|
| `a:i8 65` | `65` | `65` |
| `b:i16 -300` | **`1321270996`** | `-300` |
| `c:ui8 200` | `200` | `200` |
| `d:f32 2.5` | **`0.000000`** | `2.500000` |
| `e:bool true` | `1` | `1` |

Two wrong answers today, and the three right ones are right only by luck of
register lowering. **This is a general varargs bug, not a `bool` bug** — `f32`
and `i16` are broken *now*, with no `bool` involved. `bool` is simply next in
line, and part 1 is what makes `(printf "%d" (empty? s))` an ordinary thing to
write. The fix is one promotion rule at the variadic argument site
(`i1`/`i8`/`i16` → `i32`, `f32` → `f64`), and it should land regardless of
whether either part of this item does.

**3. `i1` versus `i8` as the in-memory `_Bool`.** Clang lays the struct out as
`%struct.BF = type { i8, i32 }`; Nucleus emits `%BF = type { i1, i32 }`. Size,
alignment and field offsets agree (8 bytes both sides, measured), so a struct
crossing the boundary is safe. The residue is that an `i1` load reads bit 0
only, so a `_Bool` byte holding `2` — which C already calls undefined — reads as
`false` rather than `true`. Narrow, but it is the reason the `i8` spelling is
what clang picked.

### The export direction: can C still consume Nucleus libraries?

**Scoping decision (2026-08-18): there are no consumers outside the compiler
itself, so breaking changes are free. Long-term interop *correctness* is the
objective instead.** That retires most of this question and inverts one answer.

**The type divorce alone breaks nothing.** A C consumer sees the generated `.h`
and the object's symbols, and neither moves: `bool` already emits `_Bool` in the
header and `i1` in the IR. `lib/*.h` stays byte-identical and nothing relinks.

**The predicate-retyping sweep is an API break, and no longer a concern.** It
changes `int32_t is_pos(int32_t)` to `_Bool is_pos(int32_t)`, and a stale
consumer gets silently inverted booleans — measured, `is_pos(-2)` returns `-256`
through a stale `int32_t` declaration, so `if (is_pos(-2))` fires when the
predicate is false (`setg %al` leaves the input's `0xFFFFFF00` in `eax`'s upper
bits, and `_Bool` is defined in `al` only). Worth recording because it is a real
property of the change, but with no external consumer the remedy — regenerate
headers, recompile — is a `make` away and `check-headers.sh --fix` does the first
half.

Note for anyone reading this later: **`zeroext` is not a shim for that.** It
lowers to `setg %al; andb $1,%al`, which masks `al` and says nothing about bits
8–31; re-measured with the attribute, a stale consumer still reads `-256`.

### Long-term interop: what actually deserves fixing

Ranked by whether the divergence is a *demonstrated wrong answer* or a
*divergence from spec that no target currently punishes*.

**1. Variadic default argument promotions — was a live miscompile, and not about
`bool` at all. FIXED (2026-08-18), see
[varargs-promotion.md](varargs-promotion.md).** `f32 2.5` printed `0.000000`
and `i16 -300` printed garbage, with no `bool` anywhere in the program — the one
item on this page that was a bug rather than a design question, so it was fixed
independently of and ahead of the rest. 10 of 149 examples changed IR and none
changed output: the corpus carried only the latent `bool`-through-`%d` form.

**2. `zeroext` on `_Bool` parameters and returns — real divergence, no
demonstrated miscompile.** Clang declares `zeroext i1`; Nucleus declares bare
`i1`, with zero occurrences of `zeroext`/`signext` in the tree. Attempts to break
it on two targets both failed: x86-64 lowers to `setg %al` and RISC-V to
`sgtz a0, a0`, each producing a clean 0/1 in the full register, in both the
return and the argument direction. So it is **cheap insurance and correct by
spec, not a fire.** Worth adding while part 1 is already touching every `bool`
signature; not worth blocking on. (Nucleus also emits a redundant `sext.w` on
RISC-V `i32` parameters for the mirror-image reason — no `signext` — which is an
efficiency wart, not a correctness one.)

**3. `i1` versus `i8` as the in-memory `_Bool` — narrower than it looked.**
Clang lays the struct out as `{ i8, i32 }`, Nucleus as `{ i1, i32 }`; size, align
and offsets agree. Testing the case that would bite — Nucleus stores a `bool`
field over a byte pre-dirtied to `0xAA`, C reads the raw byte — gives `0x01` and
`0x00` at both `-O0` and `-O2`. LLVM zero-extends an `i1` store to a full clean
byte. **Recommend leaving it**, even under a no-compatibility-constraint regime:
switching the memory representation is a codegen change with a bootstrap
re-converge behind it, and there is no observed defect to justify it.

### The one recommendation that flips

Earlier drafts of this page said **keep the mangle token `"i1"`**, because
`type-mangle-token` (`src/type-mangle.nuc:20`) puts it in four places at once:

```
define i32 @ov.i1(i1 %a.arg) section ".text.ov.i1"
int32_t ov_i1(_Bool a) asm("ov.i1");      /* in the generated header */
```

— the ELF symbol, the `--gc-sections` section name, the `asm()` label and the
C-side function name. That advice existed only to protect consumers that would
have to relink. **With no such consumers, the token should be renamed to
`"bool"`.** It is a permanent, user-visible name in every generated C header, and
leaving it spelled after a type the language no longer has is exactly the
long-term wart this scoping decision says to avoid. No committed `lib/*.h`
contains one today (no bool overload set exists yet), so the rename costs
nothing now and gets more expensive with every overload set added later.

The same reasoning applies, smaller, to the header spelling: `type-to-c` emits
`_Bool`, and the generated preamble already `#include`s `<stdbool.h>`, so
emitting `bool` is free and is the spelling a C23 reader expects. Cosmetic, but
it is the moment.

### What the scoping decision does *not* relax

**The bootstrap staging is an internal constraint, not a compatibility one.**
`.nuch` records the *source spelling* — `:i1` round-trips as `i1`, `:bool` as
`bool` — and there are 24 `i1` spellings across 7 committed `.nuch` files
(`keyword`, `strview`, `coll`, `hashset`, `string`, `numeric`, `vector`). The
compiler is its own consumer of that format during bootstrap, so retiring the
`i1` spelling still needs the dual-accept → refresh → retire shape the
`&rest`→`:rest` flip used: the boot compiler must be able to *read* the new
source before the old spelling can be rejected. "Breaking changes are fine" is
about downstream users; it does not make a one-commit flip converge.

## Part 2 — truthiness

### The structural point: part 2 requires part 1

"All numbers are true" and "`bool` is an `i1`" cannot both hold: `false` would be
a number, and therefore true. So the type divorce is not an independent nicety —
it is load-bearing for the punning rule. Any staging must land part 1 first.

### The rule as proposed silently breaks the standard library

Under "all primitive values are true":

```
(when (str-empty? s)     …)   ; always taken — str-empty? returns i32
(when (char-is-digit c)  …)   ; always taken
(when (strcmp a b)       …)   ; always taken; in C this means "differs"
(when (feof f)           …)   ; always taken
```

`str-empty?` returning `1` was confirmed by running it. These are not
hypotheticals or badly-written code: `empty?` is a first-party stdlib function
whose name ends in `?`, and a bare `(when (empty? s) …)` is the single most
likely thing a user writes on the first day the feature ships. It compiles, it
runs, and it is wrong.

Retyping the 40 first-party predicates to `bool` fixes the first two lines. It
cannot fix the last two: C returns `int` from its predicates, and `import-use
"stdio.h"` will keep handing them over for as long as Nucleus talks to C. The C
boundary stays a permanent hazard zone under this rule.

### The project has already recorded this exact failure mode

`context/conventions.md` §"A wrong value that only reaches a truthiness test is
invisible to every gate" documents Stage 15 W9 item 31: `is-unsigned` had no
`TY-I1` arm, so `(as i32 true)` was `−1` and both `(< false true)` and
`(> true false)` were false — and it **survived every bootstrap for the whole
project**, because the six places holding that value all fed `(!= x 0)`.

The generalisation recorded there is: *a wrong value leaves no trace in any fixed
point if it only ever flows into a truthiness test.* Broad truthiness is,
precisely, a proposal to enlarge the set of values whose only consumer is a
truthiness test — and to delete the type error that today forces the author to
write `(!= x 0)` and thereby say which comparison they meant. It aims the change
at the one blind spot the project has already paid to discover.

### In a static language the number rule is not the ergonomic win it is in a Lisp

Lisp punning pays because the code does not know the type: one `(when x …)`
handles nil, the empty list, and a struct. Nucleus always knows the type. So
under "all numbers true":

- `(when n:i32 …)` is a **constant**. It cannot be anything else.
- `(when p:ptr:Node …)` is also a constant — Stage 10 made `ptr` non-null by
  type. Only `raw`, `CStr`, `?T` and value-`Maybe` can be false at all.

Every conditional the number rule newly admits is one whose answer the compiler
already knows. It does not shorten a single line of working code; it only accepts
lines that are mistakes. Note the asymmetry with the pointer rule, which admits
conditionals whose answer is genuinely unknown at compile time — that is the half
that carries the value.

### It is also the one choice that cannot be revised

Three candidate rules, with the payoff measured against the compiler's own source
(35,788 lines):

| Rule | Sites it shortens in `src/` | Revisable later? |
|---|---|---|
| Nil punning only (`raw`/`CStr`/`?T`/`Maybe` false when absent) | 1,135 null tests | **Yes** — `(when n:i32)` stays an error, so both extensions below remain open |
| \+ zero-is-false (C semantics) | \+522 zero tests = 1,657 | Yes, as a later additive step |
| All numbers true (as proposed) | 0 | **No** |

The first two rules leave `(when n:i32 …)` a compile error, so a later decision
can give it a meaning. "All numbers true" gives it a meaning immediately, and
gives it the *opposite* of the meaning anyone would later want — so it can never
be corrected without breaking programs. Of the three, the proposed one has the
lowest payoff and the only irreversible failure.

Worth noting on the middle row: **C semantics, not Lisp semantics, is what
matches this codebase.** The `(!= flag 0)` idiom is used 522 times, and the 40
`i32`-returning predicates are correct under zero-is-false and inverted under
all-numbers-true. That is the counterintuitive part of this evaluation — the more
Lisp-like rule is the one that breaks the Lisp-ish codebase.

### Do it at condition position, not as a coercion

The overview words it as "automatic casts when something wants `bool`" — i.e. in
the implicit-coercion set. That placement costs more than the feature is worth:

- **It contradicts a stated invariant.** types.md defines implicit coercion as
  *exactly* `as`'s safe set plus one pointer allowance, and routes everything
  lossy to `unsafe/cast`. A lossy conversion in the implicit set makes that
  sentence false and every rule downstream of it negotiable.
- **It turns `bool` into a universal sink.** A `bool` parameter, field or `let`
  slot would accept any value of any type. Overload resolution is the sharp edge:
  `(defn g (b:bool))` would become a candidate for every call — and dispatch is
  the one place the language has already decided to be *stricter* than assignment
  (types.md, "Multimethod dispatch is stricter than assignment"). Placing
  truthiness in the coercion path picks a fight with that precedent for no gain.
- **Condition position is where the ergonomics actually live.** Nobody wants
  `(defn f (b:bool))` called with a pointer. They want `(when p …)`.

So: make truthiness an elimination rule at the **six sites already listed** —
`cond` test, `while` condition, `not` operand, `_and`/`_or` operands — and leave
the coercion chokepoint alone. `if`, `when`, `unless`, `case` and `if-some` are
all macros over `cond` (`lib/macros.nuc:83`), so those six sites are the whole
surface.

### The one non-obvious implementation cost: narrowing is syntactic

`test-true-nonnull` / `test-false-nonnull` (src/nucleusc.nuc:2388/2418) prove
non-nullness by **matching node shapes** — `(!= x null)`, `(= x null)`, and
recursion through `and`/`or`/`not`. Nil punning introduces a new shape, the bare
symbol, and without a matching arm:

```
(when m (m kind))     ; condition compiles; body fails to typecheck
```

That is worse than not shipping the feature — the sugar would work everywhere
except the case that motivates it. The fix is roughly five lines in each
function (a bare `NODE-SYM` naming a nullable binding proves itself non-null when
true), but it must land in the same change, and `emit-cond`'s `is-final-true`
special case must keep recognising the literal `true` that `if` generates for its
else branch.

Also worth deciding explicitly: a bare `(when p:ptr:Node …)` on a **non-null**
pointer should be a **diagnostic**, not a silent `true`. Today
`(!= p:ptr:i8 null)` compiles clean and returns 1 — the hazard exists already,
but it is at least explicit. Punning makes it look like a null check, so this is
the moment to name it.

### Where nil punning does *not* reach

- **`Result` / `!T`.** The proposal is silent. If an `Err` is not falsy,
  `(if (try …) …)` is a trap; if it is, `Result` and `Maybe` become
  indistinguishable in a condition. Recommend: **not falsy, and not truthy** —
  `Result` is not a condition, `match` and `try` handle it.
- **`(dyn P)` and `BoxedFn`.** Fat pointers, two halves. A truthiness rule has to
  say which half, or refuse. Recommend: refuse.
- **Empty collections and empty strings.** Not covered by any of these rules —
  and correctly so; CL agrees (`""` and `#()` are true). `(when (empty? s))` with
  `empty?` retyped to `bool` is the spelling, and it is already fine.

## Recommendation

**Do, as one item:**

1. `TY-BOOL` as a distinct kind; `true`/`false` its literals; `i1` retired as an
   integer spelling; `{0,1}`-as-`bool` range rule deleted. ~70 sites, no IR
   movement.
2. Retype the ~40 `i32`-returning first-party predicates to `bool`.

**Do, as a second item, after 1 lands:**

3. Nil punning at the six condition sites only, for `raw` / `CStr` / `?T` /
   value-`Maybe`. Not a coercion — an elimination rule.
4. The matching bare-symbol arm in `test-true-nonnull`/`test-false-nonnull`, in
   the same change.
5. A diagnostic for a bare non-null pointer in condition position.

**Do not do:** "all primitive values are true". It shortens nothing, it silently
inverts 40 stdlib predicates and every C `int` predicate, it enlarges the exact
blind spot `conventions.md` documents, and it is the only option on the table
that forecloses its own correction.

**Leave open:** zero-is-false. It is the rule with the largest measured payoff
(1,657 sites) and the one that matches this codebase's `(!= flag 0)` idiom, but
it conflates absent with zero and revives `(when (strcmp a b))`. Because item 3
leaves `(when n:i32 …)` an error, this decision stays available indefinitely.

## As built — Part 2 (2026-08-29)

Items 3, 4 and 5 of the Recommendation, as one change. Item 1 (the type divorce)
and item 2 (predicate retyping) landed earlier in `db895b2 Bool type, deftype`;
`bool-type-plan.md` is that half.

### What landed

**One shared rule, called from six sites.** `condition-bool`
(`src/union-emit.nuc`, immediately above `emit-not`) takes an already-emitted
`Val` plus a line and a context word, and returns a `bool` `Val`:

| Condition type | Result |
|---|---|
| `bool` | returned unchanged — no IR, so every existing program is byte-identical |
| `is-ptr-like` at pkind `PTR-RAW`/`PTR-MAYBE` (`raw`, bare `raw`, `CStr`, `?T`) | `icmp ne ptr … null` |
| `TY-STRUCT` recognised by `value-maybe-union-of` | `extractvalue` of the tag word, `icmp eq i32 … <some-arm>` |
| `TY-PTR` at `PTR-REF` (`ptr`, `(ref T)`) | **diagnostic**: "is non-null, so this test is always true -- spell the value (raw T) or ?T if it can be null" |
| `TY-PTR` at `PTR-ERRPTR` (`!T`) | **diagnostic**: "a Result (!T) is neither true nor false -- eliminate it with match, try or unwrap" |
| anything else | "condition must be bool, not `<type>` -- compare explicitly" |

The six callers are `emit-cond` (`src/nucleusc.nuc`), `emit-while`
(`src/nucleusc.nuc`), `emit-not` and `emit-short-circuit` × lhs/rhs
(`src/union-emit.nuc`). Each one previously carried its own inline
`(!= kind TY-BOOL)` test and its own message; those five tests are gone, which
is what makes it one rule rather than six copies (the shape `conventions.md`
§"`node-type` mirrors `emit-node`" argues for).

**`value-maybe-union-of`** (`src/union-registry.nuc`, beside `result-union-of`)
recognises a value `(Maybe T)` **structurally** — two arms, a payload-carrying
`some` and a payload-less `none` — for the same reason `result-union-of` does:
a stamped instance is named `Maybe.<mangled-arg>`, so the name is not a stable
key and the arms are.

**Item 4** is one arm at the top of `test-true-nonnull` (`src/nucleusc.nuc`): a
bare `NODE-SYM` conjs its binding name into the fact accumulator, exactly as
`(!= x null)` does. `narrow-apply` already filters to local `PTR-MAYBE`
bindings, so the arm is a no-op for a `bool`, a `raw` or a non-pointer and needs
no type test of its own.

**Item 5** is the `PTR-REF` row above. It fires for a typed `(ptr T)`/`(ref T)`
*and* for the elem-less bare `ptr`. That is a deliberate simplification worth
naming: `pkind-flow-check` exempts an elem-less bare `ptr` destination from the
non-null obligation (the `void*` escape hatch, ~1550 bindings in this compiler),
so a bare `ptr` can in practice hold `null` and its "always true" claim is
weaker than the typed case's. Punning it instead would have been defensible.
One rule was chosen over two because the diagnostic names the fix — `raw` is
itself a bare, elem-less spelling — so the escape is one word away in both
cases.

### Where the plan diverged from what was found

1. **"roughly five lines in each function" — `test-false-nonnull` needs no arm
   at all.** A bare symbol being *false* proves the binding **null**, not
   non-null, so there is nothing to record. The inverted guard still narrows,
   because `test-false-nonnull`'s existing `not` arm delegates to
   `test-true-nonnull`: `(when (not m) (return))` reaches the new arm through
   that delegation and narrows `m` past the guard. Adding a mirror arm would
   have been unsound.
2. **The condition sites' line attribution was already `:0:` for a bare
   symbol.** `emit-while` and `emit-short-circuit` blamed
   `((unsafe/cast ptr:Node (node-at cc 1)) line)`, which is 0 for an interned
   symbol node (`conventions.md` §"Symbol nodes are interned singletons"). That
   was invisible while a bare symbol could not *be* a condition; the sugar makes
   it the common case. Both now use `node-line … (cc line)`, as `emit-cond`
   already did.
3. **The five inline messages differed in wording** ("cond: test must be bool",
   "while condition must be bool", "not expects a bool operand", "%s expects
   bool operands"). Unifying them was necessary to share the rule and cost
   nothing — no test or doc quoted any of them.
4. **`(when c"lit" …)` compiles and is always true.** A `c"…"` literal is a
   materialised, non-null `CStr`, and `CStr` is nullable *by type*, so it takes
   the punning row rather than item 5's diagnostic. Same class as `(when true
   …)`; not worth a special case.

### Test counts

`make test`: **883 → 888** (five new units in `run_s16_bool_truthiness`; 0 FAIL,
exit 0, both before and after). `make bootstrap` converges **without a boot
refresh** — the compiler's own IR does not move, because nothing in `src/` uses
the sugar and the new arm in `test-true-nonnull` is a no-op for every condition
the compiler currently writes. `make abi-test`, `make layout-test` and
`make check-headers` (69 headers) stay green.

The five units are: `s16-truthiness-six-sites` (all six sites × `raw`/`CStr`/
`?T`/value-`Maybe`, as a bitmask, plus IR assertions for both eliminations —
a truthiness test is precisely the shape `conventions.md` §"A wrong value that
only reaches a truthiness test is invisible to every gate" says a run cannot
audit); `s16-truthiness-narrows-bare-symbol` (item 4, all four shapes);
`s16-truthiness-numbers-stay-refused`; `s16-truthiness-nonnull-and-result-refused`
(item 5); `s16-truthiness-is-not-a-coercion` (a pointer still refused at a
`bool` argument, `let` slot and struct field).

### Deliberately not done

- **"All primitive values are true"** and **zero-is-false** — the design's own
  rulings. `(when n:i32 …)` and `(when f:f64 …)` are both still errors, which is
  what keeps zero-is-false available.
- **`TY-FN` (a function pointer) in condition position.** `(= hook null)` is a
  real idiom (W9 item 18), so `(when hook …)` is a plausible extension. It is
  not in the Recommendation's list, and `is-ptr-like` deliberately excludes
  `TY-FN` (`conventions.md` §"The string-type lattice"), so admitting it means
  asking `is-ptr-repr` and deciding whether a fn pointer is "nullable" — a
  separate ruling. Refused for now, with the generic message.
- **`(dyn P)` / `BoxedFn` / `StrView`** — refused, as the design's §"Where nil
  punning does not reach" says. They reach the generic message
  (`condition must be bool, not __dyn.Describe`), not a bespoke one.
- **Adopting the sugar in `src/`.** The 1,135 measured null-test sites are the
  payoff, but rewriting them moves the compiler's own IR and needs its own
  `make update-bootstrap` cycle; it is a separate, purely mechanical item.
- **Retyping the ~40 `i32`-returning predicates** (Recommendation item 2) —
  belongs to Part 1 and is not in this change.

### Found, not fixed

`docs/types.md` still documents `i1` as a live spelling (the Built-in Types
table's `` `i1` / `bool` `` row, the `{0, 1}` range-rule paragraph under
Implicit Type Coercion, and the Literal Values table's "bool (i1)") even though
Part 1 retired it — the compiler answers `i1 is no longer a type — use bool`.
Part 1 also has no entry in `design/progress.md`. Both are Part 1's doc debt,
left untouched here rather than silently rewritten.
