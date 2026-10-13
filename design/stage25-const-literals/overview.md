# Stage 25 — `Const` collection literals

**Status: designed 2026-10-12, revised 2026-10-13 (Q1, Q6), ruled 2026-10-13.
CL-0 … CL-6 built 2026-10-13, uncommitted; as-built notes and measurements are
in §11.** Q7, the prelude half of Q8 and the rest of Q11 are deferred.
Measured against `800bf1f` plus the working tree. Every probe ran in a scratch
copy of the tree built with the system LLVM 19.

## 1. The brief

1. The source repeatedly allocates a collection, binds a literal to a variable,
   then calls `into`. Building from a literal should take one call, and the
   literal itself should be purely compile-time.
2. The name is `Const`. A literal's type is a `Const` collection:
   `(Const (Vector E))`, `(Const (HashSet E))`, `(Const (HashMap K V))`. When
   its elements are constants, it lives in a private constant global, with no
   allocator, no init, no drop and static lifetime. It supports read-side
   operations only.
3. Lookup does not hash. The compiler chooses the layout, duplicates are a
   compile-time error, and the design says which element types can be ordered
   at compile time.
4. A mutable collection comes from a `Const` in one library call, through
   `make`, `new`, `init` and a binding with a declared mutable type.
   `create-form`'s literal sniffing goes; `into` stays for run-time sources.
5. Out of scope: reader extensibility (the syntax and the reserved heads stay
   as they are, [deferred](../deferred/overview.md) "Reader extensibility"), and
   a compile-time hash layout through the JIT.

## 2. Ground truth (measured 2026-10-12)

### 2.1 How a literal lowers today

The reader makes a `(vector-lit …)`, `(hashset-lit …)` or `(hashmap-lit …)`
cell, marked for EDN in its `i` field (`lib/nucleus/read.nuc` `rd-lit-cell`).
`emit-collection-lit` (`src/nucleusc.nuc:13972`) rewrites the cell into

```lisp
(let (g:(ref Coll) (alloca Coll)) (init g) (conj g e) … g)
```

and emits that. The header lives in the frame and the buffer on the heap, and
nothing frees the buffer. The want channel (`g-want-type`, read by
`collection-lit-want-node` at 13950) names `Coll` when a binding, `return`,
field or `as` arms it (5150, 7948, 11040, 11204…). Otherwise the element types
name it (`collection-lit-elem-type`, 13894). A call argument arms nothing.
`node-type` answers null for the three heads (`src/generics.nuc:7012–7014`),
on purpose: Rung 3 overwrites emit's type, and emit's type depends on the want
([collection-literal-variables.md](../stage16-ergonomics/collection-literal-variables.md)
§"node-type returns null").

**Probe `leak.nuc`: the per-call cost.** Two functions each test membership in a
literal set: `#{40 41 …}` (8 ints, bare) and an 8-`StrView` set bound as
`&(HashSet StrView)`. Called 100,000 times each, they make 800,001 `malloc`
calls (4 per evaluation) and allocate 52.8 MB, none of it freed: 264 bytes per
evaluation, at `-O0` and `-O2` alike. Scaled to 4M evaluations, the loop takes
2.25 s at `-O0` and 0.85 s at `-O2`; the same test written as an `or` chain
takes 0.053 s and 0.003 s. That is about 560 ns and 210 ns per evaluation,
almost all of it building the set.

**Probe `mk.nuc`: `(make (Vector i32) heap [1 2 3])`.** `create-form`
(`lib/nucleus/create.nuc:46`) recognizes the literal by its head symbol (57–59)
and splices `(nucleus.allocator/init p h)` plus one `(conj p e)` per element. It
does this because "initializing from the temporary it builds would leak its
buffer" (its own comment, 44–45). The IR is `handle`, `init` and three `conj`
calls, and 7 calls survive `-O2`. `new` and a `{…}` operand take the same path,
using `assoc`.

### 2.2 Census

Probe `census.nuc` reads every file with `nucleus.read` and, recursively, every
string in a test suite that parses as a program. Each literal is classified by
its elements (all constant or not), by what happens to it, and by where it
lives.

| Tree | Sites | Constant elements | Non-constant | Mutated after building |
|---|---:|---:|---:|---:|
| `src/` | 12 | 11 | 1 (`'sym` × 64) | 0 |
| `lib/` | 0 | — | — | — |
| `examples/` | 21 in 7 files | 17 | 4 (`'sym`, one file) | 0 |
| `tests/fixtures/` | 10 | 10 | 0 | 0 |
| `tests/suite-*.nuc` (embedded programs) | 35, plus about 6 in strings that do not parse alone | 24 | 11 | 0 |
| `tests/repl/*.in` | 11 | 11 | 0 | 0 |

By kind: `src/` holds 8 constant sets, 3 constant maps and the one quoted-symbol
set. No site anywhere calls `conj`, `assoc` or `disj` on a bare literal. The
mutable uses are building a collection from a literal (the `make`/`new`
operands in `suite-s24` at 460 and 666, and the five by-value
`defvar options:(Vector i32) […]` fixtures).

The non-constant sites fall into three groups:
- quoted symbols, which lower to a run-time `nuc_intern-symbol` call: `src/generics.nuc:3681`,
  `examples/symbol-keys-test.nuc` 76/80/85/89, and a `check-kwlit` keyword test;
- the Stage 16 tests that pin variables as elements (`suite-s16` 499/550/564 and
  the refusals at 591–611);
- `suite-s24`'s `(make (Vector ui8) heap [b0 b1])`.

None of them is in production code apart from the quoted-symbol set.

**Literals passed as call arguments** (re-read from the same census output,
2026-10-13, by each literal's immediately enclosing form):

| Position | Sites |
|---|---:|
| a `let`/`with` binding | 66 (6 in `tests/repl/`) |
| `make`/`new` operand | 7 (`suite-s24`) |
| `defvar` initializer | 6 (fixtures) |
| `contains?` operand | 8 (`src/generics.nuc:3681`, `src/nucleusc.nuc:3286`, `examples/as-sugar.nuc:21`, 5 in `tests/repl/stdlib.in`) |
| `return`, or a `defn` body's value | 2 (`suite-s21`, `s21-frame-discharge-accepts`) |
| any other function's argument | 0 |

The `tests/repl/*.in` rows come from a grep, because the census program does not
read transcripts. One more census line is a `die-at` message string in
`nucleusc.nuc` that happens to parse as a program; it is not counted.

So no site passes a literal to a function that takes a mutable collection,
which is the one case the argument rule (§5.4) turns into a type error. The
caveats are the six suite strings that do not parse alone, and the docs, which
the census does not read.

The twelve `src/` sites:

| Site | What | Shape | Evaluated |
|---|---|---|---|
| `cheader.nuc:32` `c-fn-noreturn` | 8 `StrView` | bound `&(HashSet StrView)` | per C function declaration |
| `cheader.nuc:40` `c-fn-returns-twice` | 7 `StrView` | same | same |
| `cheader.nuc:604` `quals` | 12 `StrView` | same | per token of a C declarator |
| `cheader.nuc:625` `ints` | 6 `StrView` | same | per `unsigned`/`signed` token |
| `cheader.nuc:1741` `specs` | 19 `StrView` | same | per lookahead in `c-cexpr-type-ahead` |
| `cheader.nuc:3858` `type-name-to-c` | map, 22 pairs | bound `&(HashMap StrView StrView)`, read as `(mapping k)` | per type written to a C header |
| `generics.nuc:452` `op-name-token` | map, 16 pairs | same | per mangled operator name |
| `generics.nuc:3681` `gcheck-special-form` | 64 quoted symbols | bare, in `contains?` | per head in a generic body check |
| `nucleusc.nuc:3286` `source-name-char` | 8 `i32` | bare, in `contains?` | per character, but only on the unresolved-name diagnostic path |
| `nucleusc.nuc:4782` float ops | map, 11 pairs | bound `&(HashMap …)` | per float binary operation |
| `nucleusc.nuc:21393` `build-special-form-set` | 105 `StrView` | bound, then `into` an arena set | once, at startup |
| `nucleusc.nuc:21454` `build-primitive-type-set` | 21 `StrView` | same | once, at startup |

The two builder comments' counts ("89 members", "18 members") are stale: the sets
hold 105 and 21. `NameSet` (`nucleusc.nuc:189`) has exactly two consumers:
the `contains?` calls at 14276 and 14282.

### 2.3 What the leak costs the compiler

I measured with an `LD_PRELOAD` allocation counter (`probes/mcount.c`) and
emulated the sweep: a copy of the tree in which ten `src/` sites are moved into
globals built once (`probes/hoist.py`). Both compilers produce byte-identical IR
for the same input.

| Compile | Heap calls before → after | Bytes allocated | Median time |
|---|---|---|---|
| The compiler compiling itself | 13,920,050 → 13,792,375 (−0.9%; −176,731 `malloc`, +49K `realloc` noise) | ≈3.02 GB both | 7.84 s → 7.71 s (inside run-to-run noise) |
| `glib.h` + `SDL2/SDL.h` + `cairo.h` imported | 328,929 → 75,994 (−77%) | 64.8 → 38.7 MB | 0.671 → 0.638 s (−5%; ranges disjoint) |
| One unresolved name, `(no-such-fn 1)` | 554,495 → 41,348 (−93%) | 29.7 → 14.2 MB | 0.162 → 0.145 s (−10%) |

The self-compile is dominated by LLVM's own allocation (the macro JIT's
LLParser re-reading the declaration buffer per module), so the literals barely
show there. The header compile pays for the `cheader` sets per token. The
failing compile pays for `source-name-char`, which runs on every character of
every file in the closure while the compiler looks for the file that would
define the missing name. **The win is in header imports and error paths, not in
the self-compile.** §9 measures all three.

### 2.4 Conformances and protocols that exist

- `Vector` conforms to `Init` and `(InitFrom (Vector T))`, and has `init`
  overloads taking `&(Vector T)` and `(Vector T)` (`lib/nucleus/vector.nuc:207–218`).
  `HashSet` and `HashMap` conform to `Init` only. `String` adds
  `(InitFrom StrView)`, `(TryInitFrom (Vector ui8))` and a plain `&String`
  overload.
- `HashSet` and `HashMap` have no `reserve`.
- **Probe:** a second template conformance
  `(extend (Vector T) (InitFrom (Box T)))` is silently not recorded:
  `(conforms? (Vector i32) (InitFrom (Box i32)))` answers no, with no
  diagnostic. A concrete type gets "re-extends protocol
  'nucleus.allocator/InitFrom' with different associated arguments". So a
  `Vector` cannot conform to both `(InitFrom (Vector T))` and
  `(InitFrom (Const …))`, and if you try, the second fails without a word
  ([deferred](../deferred/overview.md) "A type conforms to a parametric
  protocol at most once").
- `create-form` asks only `(conforms? t Init)`. Every collection is `Init`, so
  any `init` overload with an extra operand already serves `make`/`new` through
  ordinary dispatch.
- There is no read-only protocol. `Coll` has `conj`, `Seq` has
  `append`/`insert`, `Assoc` has `assoc`/`dissoc`, and `Set` has the algebra
  (`lib/nucleus/coll.nuc`). `doseq` and `into` call `iter`/`next` by name and
  need no conformance. The only library generic bounded on `Coll` is
  `flat-map`.
- `Entry` is defined in `lib/nucleus/hashmap.nuc:57`.

### 2.5 Constant storage

- **Probes `dc.nuc`, `dct3.nuc`.** `defconst` tier A writes an aggregate to
  `.rodata`. A header over a constant table works for a plain struct, and for a
  template struct when the type is declared:

  ```
  @TBL = constant [3 x i32] [i32 10, i32 20, i32 30], section ".rodata.TBL"
  @V   = constant %CV.i32 { ptr @TBL, i64 3 }, section ".rodata.V"
  ```

  `(defconst V ((CV i32) &TBL 3))` without the declared type is refused
  ("needs a run-time initializer"). The classifier `const-struct-lit?`
  (`nucleusc.nuc:14760`) needs the `StructDef` from the declared type. This is
  minor, and only a user writing headers by hand meets it.
- **Probe `hdr.nuc`.** With a `&i32` field, `(View &TBL 3)` gives "too many
  initializers for struct 'View'". `(ref TBL)` is read as a field pair. A `ptr`
  field works. The library uses `ptr`.
- **Quoted symbols and keywords have no compile-time value.** `'let` is
  `call @nuc_intern-symbol(ptr @.str.N)` at each evaluation, and returns
  `&Node`. `:k` is a run-time `keyword-intern`. Identity is the pointer, so no
  constant can stand for one.

### 2.6 A prototype (`probes/proto/pconst.nuc`)

`(ConstVec T)` and `(ConstSet T)` as `{data:ptr len:usize}`, with `count`,
`invoke`, `contains?` (linear for the vector, binary search for the set) and an
`(Iterator T)`, over headers built from `defconst` tables. It runs:

```
count=3 v1=20 has20=1 has21=0 / 10 20 30 / delim ( 1 a 0 } 1 / hs=2 mv=40 mc=4
```

What it showed:
- **The methods take the header by value.** With `&` receivers, a by-value
  global fails with "no matching method" and no notes. Tier-1 (template)
  dispatch does not take a by-value binding's address
  ([deferred](../deferred/overview.md) "An overloaded method's argument does not
  apply the borrowing coercion"). `StrView` takes its header by value for the
  same reason.
- **The `init` overload from a `Const` must live in the collection's file.**
  Defined in `pconst`, `make` did not reach it, because a qualified
  `nucleus.allocator/init` reaches a method only from a namespace that conforms
  one of its own types to the protocol. Moved into `vector.nuc` (which imports
  `pconst`), `(make (Vector i32) heap V)` worked: `init` then
  `vector-extend-raw`, one `memcpy`.
- **`-O2` folds the lookup.** Checked with `opt -O2` because `--emit-llvm` is
  unoptimized: `contains?` on a constant header inlines into a binary search
  over the constant table, with no call and no allocation.
- **AVR.** A library importing only `allocator`, `coll` and `iterator`
  compiles and links for `atmega328p`. Today no literal compiles for AVR:
  `[1 2 3]` stops at `lib/nucleus/numeric.nuc:41` and `#{1 2}` at
  `lib/nucleus/hash.nuc:84` ("f64 is not supported on AVR").

## 3. The model

A literal denotes a value, not a construction. Its type is `(Const C)`, a
read-only view `{data, len}` over storage the compiler chose, in the way that
`StrView` is a view over bytes. A mutable collection is one `init` away from it,
and that `init` reads the view.

| Literal | Elements | Storage | Lifetime |
|---|---|---|---|
| any position | all constant | private constant global(s) in `.rodata` | static |
| inside a function | some not constant | the frame, filled and sealed in place | the frame (tainted) |
| at top level (`defvar`) | some not constant | a private global, filled and sealed by the global initializer | static |
| with a declared mutable type | either | built from the `Const` above with `init` | the collection's |

The value is the header. A constant-element header is an LLVM constant
expression (`{ ptr @.const.N, i64 3 }`), so a bare literal used once costs no
instruction beyond the table.

## 4. Representation

### 4.1 Three library templates

`lib/nucleus/const.nuc`, `(ns nucleus.const)`:

```lisp
(defstruct (ConstVec T) data:ptr len:usize)
(defstruct (ConstSet T) data:ptr len:usize)      ; sorted by const-cmp, no duplicates
(defstruct (ConstMap K V) data:ptr len:usize)    ; (Entry K V)s sorted by key, keys distinct
```

`data` is `ptr`, not `&T`, for the reason in §2.5. The methods take `self` by
value:
- `count`, `empty?`, `iter` (and `(Iterator T)` on the iterator), `contains?`;
- `invoke` on a `ConstVec` (index → `T`);
- `get` on a `ConstMap` (key → `?V`, as `HashMap`'s `get`, so `(m k)` routes the
  same way), plus `keys`, `vals` and `iter` over `(Entry K V)`.

`contains?` and `get` on the sorted types do a linear scan below a small
threshold (8) and a binary search above it. The scan is correct on a sorted
array, so the compiler needs no flag to choose between them. A `switch` for
integer sets is left to LLVM, and not measured.

`const.nuc` imports `allocator`, `coll` and `iterator`, and nothing that
names `f64`, so a `Const` literal works on AVR, which no literal does today
(§2.6). `vector.nuc`, `hashset.nuc` and `hashmap.nuc` import `nucleus.const`.

### 4.2 `(Const C)` is a type spelling, resolved by shape

`(Const C)` is parsed beside `dyn` (`src/union-registry.nuc:2698`, and the
type-head predicate at 2321). It resolves by the shape protocol `C` conforms
to, not by `C`'s name. The arguments come from that conformance, through the
same recovery a `:where` uses (`conformance-args`):

| If `C` conforms to | `(Const C)` is |
|---|---|
| `(Assoc K V Ki Vi)` | `(nucleus.const/ConstMap K V)` |
| `(Set E)` | `(nucleus.const/ConstSet E)` |
| `(Seq E)` | `(nucleus.const/ConstVec E)` |

- **The rows are checked in that order.** A type conforming to more than one
  shape takes the first. A map is also a collection of entries, and a sorted set
  could also be indexed, so the most specific shape wins. `Coll` is not a shape:
  every collection conforms to it.
- **Today's three collections each conform to exactly one shape:**
  `(extend (Vector T) (Seq T))` (`vector.nuc:207`), `(extend (HashSet T) (Set T))`
  (`hashset.nuc:299`), and `(extend (HashMap K V) (Assoc …))` (`hashmap.nuc:407`).
  So the rule gives the same three results the table would have.
- **A user collection joins through the protocol.** A `BTreeSet` that conforms
  to `(Set E)` has a `(Const BTreeSet)`. A `#{…}` literal with a declared
  `BTreeSet` want builds through `BTreeSet`'s own `init` overload from a
  `(ConstSet E)`, written in `BTreeSet`'s file (§2.6). The compiler changes
  nothing per collection.
- **Why not a type kind.** A `Const` kind over any `C` would still have to pick
  one of the three layouts the compiler can produce. A new kind also costs
  every switch on `TypeKind` (`TY-ARRAY`, the last composite kind added, has 40
  references in `src/`), and it would need dispatch to accept a type
  constructor as a method receiver, which DP-6 refused for `(extend (dyn &P) …)`.
  Resolving by protocol gets the extensibility through the language's existing
  extension point, and the read methods stay library code on ordinary templates.
- **Conformance must be known when the type is parsed.** `prescan-extends`
  promises (conformance-query.md, CQ-1) already make a written `extend` visible
  above it, so `(Const C)` may appear before `C`'s `extend`.

An operand that conforms to none of the three is refused: "`Const` takes a type
conforming to `Seq`, `Set` or `Assoc`; `Foo` conforms to none". Messages print
the type as written, as `box-spelling` does for `dyn` (`nucleusc.nuc:10206`). `.nuch` writes the written spelling, and the
C header writes the instance typedef (`ConstVec_i32` …), which a C reader sees
as `{const void *data; size_t len;}` through the Stage 11 template export.
Nothing in the tree uses the name `Const` today.

The mapping uses the full name `nucleus.const/…`, so `core-ns-require`
(`nucleusc.nuc:6110`) checks that `nucleus.const` is in the file's closure.
Every file that uses a literal today imports `vector`, `hashset` or `hashmap`,
and those import `nucleus.const`, so nothing has to add an import (Q8).
*(Wrong for methods: §11.)*

### 4.3 `Entry` moves to `nucleus.coll`

`ConstMap` iterates `(Entry K V)`, and so does `HashMap`. `const.nuc` cannot
import `hashmap.nuc`, which reaches `f64`. Moving `Entry` to `coll.nuc`, which
both import, gives one element type for both maps. `init` from a `ConstMap` and
`into` from a `HashMap` then read the same records (Q9).

## 5. Lowering

### 5.1 Constant elements

An element is constant when tier A `defconst` would accept it as a value: a
literal number, `bool`, `Char`, string, a constant struct literal, or a nested
constant-element literal. A quoted symbol, a keyword and a name are not.

When every element is constant, `emit-collection-lit` does the following:
1. It coerces each element to `E` at compile time, through the same
   `coerce-int-val` checks a binding uses. `(Const (HashSet ui8))` refuses
   `300`.
2. For a set or map, it sorts the coerced values with the compile-time order
   (§5.2). It refuses equal neighbours: "duplicate element 20 in a set literal
   (line N)", or "duplicate key …" for a map.
3. It emits `@.const.N = private unnamed_addr constant [n x E] […]`. Each
   `StrView` element points at its own string constant, the way a string
   literal does today.
4. It returns a `Val` whose text is the header constant
   `{ ptr @.const.N, i64 n }` and whose type is the instance.

An empty literal has `data` = `null` and `len` = 0, and its element type comes
from the want. With no want it is refused, as today.

### 5.2 Which element types order at compile time

The run-time order is `const-cmp`. It is one generic, with one overload per
type, and each overload lives in the file that owns the type: integers, `bool`,
`f32` and `CStr` in `const.nuc`; `f64` in `numeric.nuc`; `StrView` in
`strview.nuc`; `Char` in `char.nuc`. Keeping each overload with its type keeps
`const.nuc` free of `f64`.

The compiler orders constants of a closed list of types, and must agree with
those overloads exactly:

| Type | Order | Duplicates |
|---|---|---|
| `i8`…`i64`, `ssize` | signed | equal values |
| `ui8`…`ui64`, `usize`, `bool`, `Char` | unsigned | equal values |
| `f32`, `f64` | numeric; NaN refused | `0.0` and `-0.0` are one value, as under `=` |
| `StrView` | bytes (`memcmp`), then length, as `strview-cmp-raw` | equal bytes |
| `CStr` | bytes to the NUL, as `strcmp` | equal bytes |

This list is a lockstep between the compiler's comparator and the library's
overloads. One test per row builds a set in reverse order and checks, at run
time with `const-cmp`, that the table is ascending.

Any other set-element or map-key type, a struct for example, is ordered only
at run time (§5.3), and only if it has a `const-cmp` overload. A type without
one is refused as a key: "a Const set element needs `const-cmp`; Pt has none".
Map values and vector elements need no order.

### 5.3 Non-constant elements

Inside a function, the compiler allocates `[n x E]` in the frame, stores the
elements in source order, and, for a set or map, calls
`(nucleus.const/const-seal data n)`. That sorts with `const-cmp`. For a set it
drops duplicates; for a map, a later key wins. It returns the new length, which
becomes `len`. A run-time duplicate cannot be refused cheaply, so it is
resolved this way and documented. The header carries the alloca's frame taint
(FS-1).

**Prerequisite: a by-value slot of a `Const` type keeps that taint.** Today a
by-value slot discharges the taint (FS-2). That is the open defect "A struct
literal does not carry its fields' escape taint"
([deferred](../deferred/overview.md)). Without the fix,
`(defn f () (let (s #{a b}) (return s)))` would return a pointer into a dead
frame. The narrow fix is that a slot whose type is a `Const` instance adopts the
value's taint instead of discharging it. Its pointer is the only one in the
header, so this is exact for these three types. The general content-taint fix
would subsume it.

At top level, the storage is a private zero global, and the global initializer
fills and seals it.

The quoted-symbol sets (`gcheck-special-form`, `symbol-keys-test`) take this
path: `&Node` elements ordered by address, so `contains?` is an identity
lookup, as it is today, without the heap.

### 5.4 The want decides what the literal builds

| Want | Result |
|---|---|
| none (bare: `contains?` operand, untyped `let`, argument with no rule below) | `(Const C)`, `C` from the elements, as today's element inference |
| `(Const C)` | that type; elements adapt to it |
| `(Vector E)` / `(HashSet E)` / `(HashMap K V)` by value | `(make C heap <the Const>)`: a heap collection, as a by-value literal binding builds today |
| `(ref C)` | the same in an `alloca`'d header (TC-3), frame-tainted as today |

A declared mutable type keeps the literal's heap build. That is what a mutable
type asks for, but it means the `src/` annotations `&(HashSet StrView)` would
keep allocating on every call. The sweep removes them (§7).

**A call argument takes its want from the parameter** (Q6). Today a call
argument arms no want, so without this rule `[1 2 3]` passed to `init` falls
back to `i32`, and a `(Vector i64)` cannot be built from it: the table is laid
out before the call resolves, and a collection's elements cannot widen after
that. The rule applies only when the argument is a collection literal:

1. **A solitary function:** the want is the parameter's declared type.
2. **A generic or overloaded call:** bind type variables from the other
   arguments' `node-type`s, without emitting them, and drop the candidates those
   arguments rule out. Of the rest, count the candidates whose parameter at the
   literal's position is a `Const` **of the literal's shape**: `ConstVec` for
   `[…]`, `ConstSet` for `#{…}`, `ConstMap` for `{…}`. If exactly one is left,
   that parameter, with its variables substituted, is the want. Otherwise there
   is no want, and the literal infers from its elements.
3. **The literal is built to the want.** Its elements adapt, and an element
   that cannot adapt is refused at the element, as for a declared binding.

Examples:
- `(nucleus.allocator/init p h [1 2 3])` with `p:&(Vector i64)` binds `T = i64`
  from `p`. Of the three-argument `init`s, only `Vector`'s fit `p`, and one of
  those takes a `(ConstVec T)`, so the literal is `(Const (Vector i64))`. This
  is what lets `create-form` stop sniffing.
- `(contains? #{1 2 3} x)` with `x:i64` binds `T = i64` from `x`. The one
  candidate with a set-shaped `Const` receiver is `ConstSet`'s, so the table is
  laid out in `i64`, not `i32`.
- `(mean [1 2 3])` against `(defn mean (xs:(Const (Vector f64))):f64 …)` lays
  out `f64`s.
- With `f` overloaded on `(Const (Vector i32))` and `(Const (HashSet i32))`,
  `(f [1 2])` is not ambiguous: only the vector candidate matches the brackets.

What the rule does not do:
- **A call never allocates because of a literal argument.** Only a `Const`
  parameter supplies a want. Against a parameter of type `(Vector i64)` or
  `&(Vector i64)`, `(f [1 2 3])` is a type error naming `make`, not a hidden heap
  build. No site in the tree does this today (§2.2).
- **It does not change the dispatch of other arguments**, since it reads only
  literal arguments.
- **It does not change evaluation order**, since the want is computed from
  static types before anything is emitted.

Failure modes:
- **The want's candidate choice is a small copy of overload resolution.** If
  the two disagree, the literal still has a definite type, and dispatch accepts
  or refuses it. The result is a type error at the call, never a wrong answer.
- **`node-type` answers null for some forms** (`cond`, macros, the literals
  themselves). If another argument is one of those, its variables stay unbound
  and the literal falls back to element inference. That is deterministic, but
  the error names the element type rather than the call. The fix is an `as` or a
  typed binding.

### 5.5 `node-type`, `defconst`, the REPL

- **`node-type`** keeps answering null for the three heads, for the reason in
  §2.1. A bare constant literal's type does not depend on the want, so it could
  be answered. But returning it in some positions and null in others would put
  the lockstep in two places.
- **`defconst NAME <literal>`** gets a tier A arm in `defvar-const-init-ir`
  (`nucleusc.nuc:15422`). The table is emitted under `NAME`'s private
  companion, and `NAME` holds the header constant. A literal with non-constant
  elements is refused by the existing "needs a run-time initializer". The same
  change makes `const-struct-lit?` accept an undeclared template head (§2.5).
- **The REPL** compiles one module per entry. Each literal's table is a private
  global of its entry's module, named by that module's counter, the way `@.str.N`
  is. There is no process-wide memo
  ([conventions](../../context/conventions.md): an internal-symbol memo is per
  module). A `defconst` literal survives across entries like any `defconst`
  aggregate.
- **EDN** is unaffected: the reader is unchanged and EDN reads the marks, not
  the lowering.

### 5.6 A mutating call on a `Const`

`conj`, `assoc`, `disj`, `append`, `insert`, `set!` through `invoke`, and the
`Set` algebra find no method on a `Const` instance. The no-match diagnostic
gets a note when the receiver's type is one of the three templates: "a Const
collection is read-only — build one with `(make (Vector i32) heap …)`". The note
names the mutable type spelled from the instance's arguments.

## 6. One call from a `Const` to a mutable collection

Each collection file defines plain `init` overloads, not `InitFrom`
conformances:

```lisp
; vector.nuc
(defn init (self:&(Vector T) a:Alloc v:(ConstVec T)):void
  (init self a) (vector-extend-raw self (unsafe/cast &T (v 'data)) (v 'len)))
; hashset.nuc: init, reserve (v 'len), insert each element; no rehash
; hashmap.nuc: init, reserve (v 'len), insert each entry; no rehash
```

This is the `String` precedent (`&String` is a plain overload). It is the only
option that works: a `Vector` cannot conform to a second `InitFrom`, and a
second template conformance is dropped without a diagnostic (§2.4). `make`,
`new` and `init` all reach these overloads through ordinary dispatch, because
`create-form` asks only `(conforms? t Init)`. `conforms?` cannot see them;
nothing in the tree asks it about them (Q5).

`create-form` loses its `lit` variable, the head test and the two splice arms
(`create.nuc:51–59`, 83–100). A literal operand then takes the general path
`(nucleus.allocator/init p h v)`, which the argument rule in §5.4 types. The
comment about the leaking temporary goes too, because a `Const` has no buffer.

`HashSet` and `HashMap` gain `reserve n`, sized so that `n` inserts do not
rehash. `into` stays, for run-time sources.

## 7. The sweep

After the boot refresh (§8, CL-4), `src/` uses the forms. Each change removes
an allocation. None changes behavior.

**`c-fn-noreturn`** (`src/cheader.nuc:28`). Before:

```lisp
(defn c-fn-noreturn (fname:Symbol):bool
  (let (names:&(HashSet StrView)
        #{"exit" "abort" "_exit" "_Exit" "quick_exit"
          "abort_handler_s" "longjmp" "siglongjmp"})
    (return (contains? names (symbol-as-view fname)))))
```

After:

```lisp
(defn c-fn-noreturn (fname:Symbol):bool
  (return (contains? #{"exit" "abort" "_exit" "_Exit" "quick_exit"
                       "abort_handler_s" "longjmp" "siglongjmp"}
                     (symbol-as-view fname))))
```

Per call this was an alloca, `init`, eight inserts (four `malloc`s) and a hashed
lookup. Now it is a lookup over a constant table of eight sorted `StrView`s.
The same edit applies to `c-fn-returns-twice`, `quals`, `ints`, `specs`, and
the three maps, which lose their `&(HashMap …)` annotations. A
`(let (mnemonic {…}) …)` with no type is a `Const` map.

**`source-name-char`** (`src/nucleusc.nuc:3284`). The source does not change:

```lisp
(when (contains? #{40 41 91 93 123 125 59 34} c) ; ()[]{};"
  (return 0))
```

The lowering does. Before, the IR held an `alloca %HashSet.i32`, `init` and
eight `conj` calls on every character. After, there is
`@.const.N = [8 x i32] [34, 40, 41, 59, 91, 93, 123, 125]`, a header constant,
and a call to a scan that `-O2` inlines. This is the site behind the −93% in
§2.3.

**`op-name-token`** (`src/generics.nuc:450`). The annotation goes, and the
`match` on `(invoke mnemonic …)` reads `(mnemonic …)`:

```lisp
(defn op-name-token (name:Symbol):StrView
  (let (mnemonic {"_+" "add" "_-" "sub" … "bit-shr" "bshr"})
    (match (mnemonic (symbol-as-view name))
      ((some res) (return res))
      (none (return (sanitize-for-ir (ir-name-token (symbol-as-view name))))))))
```

**`build-primitive-type-set`** (`src/nucleusc.nuc:21451`). Before: a builder
function, a `NameSet` global initialized at startup, and an arena set filled by
`into`. After:

```lisp
(defconst- PRIMITIVE-TYPE-NAMES
  #{ ; integer types (plus bool, which is not one)
     "int" "bool" "i8" "i16" "i32" "i64" "ui8" "ui16" "ui32" "ui64"
     ; float types
     "f32" "f64" "float" "double" "f16" "f80" "f128"
     ; pointer / special
     "ptr" "void" "CStr" "Err" })
```

and line 14282 reads `(contains? PRIMITIVE-TYPE-NAMES (symbol-as-view name))`.
`build-special-form-set` becomes `SPECIAL-FORM-NAMES` the same way, with its
105 names and their comments. `NameSet`, both `build-*` functions and both
`g-*-set` globals are deleted (Q10). They were their only consumers (§2.2).
Two startup initializers go with them.

**`gcheck-special-form`** (`src/generics.nuc:3679`). It tests 64 quoted symbols.
Under §5.3 it would already stop allocating, but it would still intern 64
symbols and sort them on every call. It becomes a `StrView` set over the head's
spelling, checked for a symbol first. That is a `defconst-` like the two above.

## 8. Phases

Every phase must pass `make test`, `make bootstrap`, `make check-headers`,
`make abi-test` and `make avr-test`. Each new test must fail on the tree
before its phase. "Byte-identical" means that the new compiler's IR for the
compiler's own source equals the previous compiler's, checked by the
sort-normalized diff.

- **CL-0. Library groundwork.** Move `Entry` to `nucleus.coll`; `hashmap.nuc`
  re-exports it, so a file importing only `hashmap` still sees it. Add
  `reserve` to `HashSet` and `HashMap`. In `defvar-const-init-ir`, accept an
  undeclared template-head struct literal. File the silent second template
  conformance (§2.4) and the "too many initializers" message for
  `(View &TBL 3)` in [deferred](../deferred/overview.md).
  - **Gate:** byte-identical. Tests: `reserve` then N inserts, with the
    allocator's call count unchanged (a `Tracking` allocator); `defconst` of a
    template literal.
- **CL-1. `lib/nucleus/const.nuc`.** Add the three templates, their iterators,
  `const-cmp` with its per-file overloads, and `const-seal`. Add the
  `init`-from-`Const` overloads in the three collection files.
  - **Tests:** headers built by hand, with `defconst` tables and typed
    `defvar`s, as the prototype did. Cover lookup on each side of the
    threshold, iteration, `make`/`new` from a `Const` for all three
    collections, and `const-seal` on duplicates.
  - **AVR:** an `examples/avr-const.nuc` run under simavr (a `ConstVec` and a
    `ConstSet` of `ui8`). The gate is byte-identical, since the compiler's
    source does not use the templates.
- **CL-2. The `(Const C)` spelling.** Add the shape resolution (§4.2), the
  type-head predicate, display, the refusal for a type with no shape, `.nuch`
  writing and reading, and the C header typedef.
  - **Tests:**
    - a `(Const (Vector i32))` parameter on a hand-built value;
    - a user collection conforming to `(Set E)`, whose `(Const …)` resolves to a
      `ConstSet`;
    - a type conforming to two shapes takes the first row;
    - `(Const C)` written above `C`'s `extend`;
    - the refusal;
    - a `.nuch` round trip;
    - `check-headers` over a header with a `Const` parameter.
  - **Gate:** byte-identical.
- **CL-3. The literal is a `Const`.** This is the compiler change, in three
  parts.
  - **Lowering and checks.** The new lowering in `emit-collection-lit` (§5.1):
    the compile-time order and duplicate refusals (§5.2), the frame and global
    seal path (§5.3), and the `Const`-slot taint rule. Then the want table and
    the argument rule (§5.4), the `defconst` arm (§5.5), and the mutating-call
    note (§5.6).
  - **In the same phase.** Delete `create-form`'s sniffing (§6). No `src/` or
    `lib/` site uses `make` or `new` with a literal (§2.2), so the boot does not
    depend on the order. Re-point the tests that pinned the old lowering: the
    duplicate lines in `examples/hashset-lit-test.nuc` (24, 31, 38) move to
    refusal tests, and the `0.0`/`-0.0` case is kept with `conj`. In
    `tests/repl/al5-vtable-per-module.in`, lines 9–10 relied on a literal
    boxing `&heap`; they become `make` calls. Every golden that prints a
    literal set's or map's iteration order changes from hash order to sorted
    order; list each one in the phase's notes. *(None changed: §11.)*
  - **Literals as call arguments.** The census (§2.2) found none passed to a
    function that takes a mutable collection. Re-run it at the start of the
    phase, adding the six suite strings that do not parse alone and the code
    blocks in `docs/`, and convert any site it finds to `make`.
  - **New tests:**
    - a function that tests `#{…}` membership has no `call` in its
      `--emit-llvm` output except `contains?`;
    - the leak probe as a test: a million evaluations, under a `Tracking`
      allocator for the `make` case;
    - duplicate refusals for each ordered type;
    - NaN refused;
    - `(Const (HashSet ui8))` refuses `300`;
    - returning a frame-backed literal is refused;
    - the mutating-call note;
    - `(make (Vector i64) heap [1 2 3])` with no splice;
    - a literal argument typed from its parameter, for a solitary function and
      for `contains?` with an `i64` key;
    - two overloads taking a `Const` vector and a `Const` set, each reached by
      its own brackets;
    - a literal passed to a `(Vector i64)` parameter is refused, naming `make`;
    - a user collection conforming to `(Set E)`, built from `#{…}` through its
      own `init` overload;
    - a REPL entry pair, each with its own table;
    - the `const-cmp` agreement test per §5.2 row.
  - **Gate:** `make bootstrap` converges. The compiler's own literals now lower
    differently, so its IR is not byte-identical to CL-2's, and the IR diff
    should show only literal sites.
- **CL-4. Boot refresh.** `make update-bootstrap`, so that `src/` and `lib/` may
  spell `(Const …)`, use `defconst` literals, and rely on the argument rule.
  - **Gate:** a clean copy builds from the committed boot, and
    `make bootstrap` reaches its fixed point.
- **CL-5. The sweep (§7).** All twelve `src/` sites; `NameSet` and the
  builders deleted.
  - **Gate:** fixed point; the measurements in §9.
- **CL-6. Docs and examples.**
  - `docs/collections.md` "Literal sugar" is rewritten for `Const`: the model
    table, the order table, duplicates, the mutable wants, the AVR line.
  - `docs/allocators.md` gets `make` from a literal.
  - `docs/special-forms.md` "Pointer lifecycle (escape analysis)" gets the
    `Const`-slot taint rule.
  - The quoted-symbol and keyword examples are noted as run-time-sealed.
  - The deferred entries filed in CL-0 are cross-referenced.

## 9. Measurement

The measurements below run at CL-2 (before) and CL-5 (after), with the
allocation counter and five runs each, reporting medians and ranges:

1. **Self-compile time.** The emulation (§2.3) predicts a change inside the
   noise, about −1.7%. The gate is no regression beyond the noise.
2. **Header-heavy compile** (`glib.h`, `SDL2/SDL.h`, `cairo.h`). The gate is
   heap calls at or below the emulation's 75,994. `Const` builds nothing at
   startup, whereas the emulation built each set once.
3. **Failing compile** (`(no-such-fn 1)`). Same gate, at or below 41,348.
4. **The leak probe**: zero `malloc` from the loop, and the `-O2` loop within 2×
   of the `or` chain.

## 10. Questions for a ruling

**Ruled 2026-10-13:**

| | Ruling |
|---|---|
| Q1 | `(Const C)` resolves by the shape protocol `C` conforms to: `Assoc` gives `ConstMap`, `Set` gives `ConstSet`, `Seq` gives `ConstVec`. |
| Q2 | Non-constant elements use frame storage with taint (global storage at top level). |
| Q3 | A duplicate in a constant literal is a compile-time error. A run-time seal behaves as recommended. |
| Q4 | Sets and maps iterate in sorted order, and the order is documented as reliable. The cost is a compile-time sort of a literal that is likely small. |
| Q5 | Plain `init` overloads, with no `InitFrom` conformance. |
| Q6 | Yes: a literal argument takes its want from the one candidate with a `Const` of its shape. |
| Q7 | Deferred ([deferred](../deferred/overview.md) "A read-only collection protocol"). |
| Q8 | A literal requires `nucleus.const` in the file's import closure. Revisiting the prelude is deferred ([deferred](../deferred/overview.md) "`nucleus.const` in the prelude"). |
| Q9 | `Entry` moves to `nucleus.coll`. |
| Q10 | The startup sets become `defconst-` sets, and `NameSet` goes. |
| Q11 | Quoted symbols and keywords stay on the run-time seal path. The constant form is deferred ([deferred](../deferred/overview.md) "Constant symbols and keywords in `Const` literals"). |

The questions as they were put:

- **Q1. Representation.** Should a literal be `(Const C)` over three library
  templates, `nucleus.const/ConstVec`, `ConstSet` and `ConstMap`, which live in
  `lib/nucleus/const.nuc` and take `self` by value, with `(Const C)` resolved by
  the shape protocol `C` conforms to (`Assoc`, then `Set`, then `Seq`) rather
  than by `C`'s name (§4.2)? *Recommend yes.*
  - A user collection gets a `Const` form by conforming to a shape protocol,
    with no compiler change.
  - The other option weighed was a new type kind (2026-10-13). It gains no
    layouts, because the compiler can produce only three. It costs every
    `TypeKind` switch, its own C-header and `.nuch` story, and method dispatch
    on a type constructor.
- **Q2. Non-constant elements.** Use frame storage with taint, filled and sealed
  in place, and global storage at top level (§5.3)? This requires the
  `Const`-slot taint rule. *Recommend yes.* The alternative is to refuse
  non-constant elements unless the want is mutable. That is simpler, but it
  breaks the quoted-symbol and keyword sets (§2.2), and they would have to
  allocate.
- **Q3. Duplicates.** Should a duplicate in a constant literal be a
  compile-time error for sets and map keys, including `0.0` with `-0.0`, while
  a run-time seal drops set duplicates and lets the last map key win?
  *Recommend yes.* The only literals with duplicates in the tree are the three
  `hashset-lit-test` lines that pin today's dedupe.
- **Q4. Iteration order.** Should a `Const` set or map iterate in sorted order?
  *Recommend yes, documented.* Today's order is the hash order, which no code
  relies on. Keeping source order would need a second index for no use found.
- **Q5. `InitFrom`.** Use plain `init` overloads from `Const` in each
  collection file, with no `(InitFrom (Const …))` conformance (§6)?
  *Recommend yes.* It is the only option that works under the
  one-conformance rule, and `make`/`new` need only `Init`. Lifting that rule
  stays deferred.
- **Q6. How a literal argument is typed.** Should a literal call argument take
  its want from the one candidate whose parameter there is a `Const` of the
  literal's shape, after binding from the other arguments (§5.4)? *Recommend
  yes.*
  - It removes `create-form`'s sniffing for good, types lookups such as
    `(contains? #{1 2 3} x)` from `x`, and helps any function that takes a
    `Const`.
  - It fails loudly: a literal against a mutable-collection parameter is a type
    error naming `make`. The census found no such site (§2.2).
  - **Rejected for now: literals that adapt like integer literals.** That needs
    an "adaptable collection" rank in overload resolution for every call. It
    belongs with the deferred "An overloaded method's argument does not apply
    the borrowing coercion".
  - **Fallback if the rule proves too invasive:** a one-line ascription in
    `create-form`, `(as (Const ~t) ~v)` when the operand is a literal. That
    fixes only `make`, `new` and `init`, and keeps one head test.
- **Q7. A read-only protocol** (`Lookup`, `Count` or similar), so that a
  function can take a `Const` or a mutable collection. *Recommend deferring it.*
  Nothing in the census needs it: every lookup is on the literal itself.
- **Q8. Imports.** Should a literal need `nucleus.const` in the file's closure,
  which every current user already has through `vector`, `hashset` or
  `hashmap`? *Recommend yes.* The alternative is to put `nucleus.const` in the
  `nucleus.core` prelude, which costs every compile for files without literals.
- **Q9. `Entry`.** Move it to `nucleus.coll` and re-export it from `hashmap`
  (§4.3)? *Recommend yes.*
- **Q10. The startup sets.** Make them `defconst-` `Const` sets and delete
  `NameSet`, rather than keep them as one-call `new` sets? *Recommend
  `defconst-`.* Their only use is `contains?`, and a constant needs no startup
  code.
- **Q11. Symbols and keywords as constants.** Should quoted symbols and
  keywords stay on the run-time seal path? *Recommend yes, and defer the rest.*
  A spelling-keyed constant form is possible: store each one in the interner's
  layout, compare by spelling, and re-intern when read as a value. But it makes
  `=` on an iterated element differ from `=` on an interned one, and the one
  `src/` user is better written over spellings (§7).

## 11. As built (2026-10-13)

All gates in §8 passed except the §9 leak-probe timing, below:
`make test` 1459/0/0, `check-headers`, `abi-test`, `avr-test`, `lib-so`,
`make bootstrap`, and a clean copy building from the refreshed boot.

Where the build differs from the design:

- **`ConstOrd`.** A template body resolves names in its defining file, so a
  `const-cmp` overload in `strview.nuc` was unreachable from `const.nuc`'s
  `const-find`; a `StrView` adapted to the `CStr` overload with no error.
  `nucleus.coll/ConstOrd` carries the order. The conformances sit beside the
  types: integers, `bool`, `f32`, `CStr` and `Entry` are in `const`; `f64` is
  in `numeric`, `Char` in `char`, `StrView` in `strview`, `&Node` in `node` (by
  address) and `Keyword` in `keyword` (by symbol address).
- **Order needs the type's library.** Because `const.nuc` must not reach `f64`
  (AVR), a set or map literal of `StrView`, `Char` or `f64` needs that library
  in the closure. `lit-require-order` refuses a missing library by name, and
  refuses a type with no `ConstOrd` by naming the protocol.
- **Core protocol methods always mangle** (`core-protocol-method?`). Two core
  libraries each had a lone `const-cmp` overload, both linked as
  `nuc_const-cmp`, and they collided in `lib-so`.
- **`ShapeExtend` prescan.** `(Const C)` resolves through shape records
  gathered before emission, so the spelling works above the `extend` that
  makes `C` a shape.
- **Methods need a direct import.** §4.2's "nothing has to add an import" holds
  for the type, not for calls. Method dispatch sees only directly imported
  namespaces, so `(contains? #{…} x)` needs `(import-use nucleus.const)`. A
  failed call now says so: when `nucleus.const` has a method of that name, the
  no-match diagnostic adds an import note; when it has none, the note is the
  read-only one (§5.6). `src/nucleusc.nuc`, `generics.nuc` and `cheader.nuc`
  import it.
- **Element fit.** Each element is checked against the element type with
  `arg-adapts`, so a literal no longer narrows silently through `set!`.
- **The argument rule skips stamped instances.** A template's stamped instance
  is a second candidate with the same parameter, and counting it made every
  call look ambiguous. Generic parameters spelled `(Const (Vector T))` unify
  by rewriting the pattern to `nucleus.const/ConstVec T`.
- **Run-time literals in a global initializer** fill an internal zero global
  (`@.const.N`), not a frame array, and take no frame taint.
- **NaN cannot be spelled** as a literal, so the NaN refusal has no test.
- **No golden changed iteration order.** Every order-printing golden binds a
  mutable type, which still builds a hash collection.
- **The census before CL-3** found no literal passed to a mutable parameter.
  The re-pointed tests are listed in [progress.md](../progress.md).
- **`.nuch` keeps the written spelling** `(Const (HashSet i32))`; C headers
  write the instance typedef.
- **`make bootstrap` after a lowering change** fails on its boot-vs-stage-1
  diff, as expected. Before CL-4, stage 2 == stage 3 was checked by hand, and
  stage 1 → stage 2 differed only in literal functions and template instances.

**Measurements (§9, medians of 5, CL-2 against CL-5):**

| Compile | CL-2 heap calls | CL-5 heap calls | Gate | CL-2 time | CL-5 time |
|---|---|---|---|---|---|
| Header-heavy | 334,332 | 81,377 (−76%) | 75,994 | 0.698 s | 0.671 s |
| Failing | 588,982 | 47,891 (−92%) | 41,348 | 0.166 s | 0.142 s |
| Self-compile | 13,951,445 | 13,992,731 | noise | 7.72 s | 7.82 s |

- **The two absolute gates are missed** by the heap calls CL-0 to CL-2 added to
  the baseline. The savings themselves meet the emulation: 252,955 against
  252,935 for the header compile, and 541k against 513k for the failing one.
- **Self-compile time is inside the noise.** The ranges overlap (7.69–7.84 s
  against 7.74–7.88 s). The rows compile different sources. On the same CL-5
  source, the swept compiler makes 196k fewer heap calls than the pre-sweep one
  (−1.4%), at equal time.
- **Leak probe.** An 8-int `#{…}` membership test, evaluated 4M times at `-O2`,
  makes no allocation, and `contains?` inlines to a call-free binary search. It
  takes 17.8 ms. The `or` chain takes 5.3 ms, because LLVM folds it to a range
  check, so **the 2× gate is missed (3.4×)**. The cost before CL-3 was about
  210 ns per evaluation; it is now 4.4 ns. Closing the rest needs a linear scan
  or comparison-chain lowering for small tables, which is not built.
