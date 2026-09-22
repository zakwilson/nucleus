# Stage 21 item 5 — frame storage cannot escape: `alloca`, the literals, and the initializer function

**Status:** designed and built 2026-09-22 (FS-1 … FS-5). 1087 tests, bootstrap converged, no boot refresh.

## 1. The bug

A GTK demo beside the checkout declared its options as

```lisp
(defvar options:&(Vector i32) [500 1000 1500 2000 2500])
```

and read `vector: get index 0 out of bounds (len 0)` at run time. The literal
expands (`emit-collection-lit`) to `(let (g:(ref (Vector i32)) (alloca (Vector
i32))) (vector-init g) (conj g …) … g)`: its value is a pointer to a **stack**
header, and only the element buffer is on the heap. A `defvar` with a run-time
initializer runs it inside `@__nucleus_init` (global-init.md §5), so the
global keeps the address of that function's frame; by the time `main` reads
it the 32-byte header has been overwritten. `(count options)` is already `0`
at `main`'s first instruction.

Nothing refused it because the escape analysis (lifecycle.md §2, lambda.md
§"Lifetime and escape analysis") had exactly one frame-taint source, `&x` on
a value binding (`binding-address-val`), and a bare `(alloca …)` result was an
untainted `(ref T)` — a documented boundary, but one that made the whole
family silent: `(return (alloca Box))`, `(defn f ():&Pt (Pt 1 2))`, `(return
[1 2 3])` and `(defvar g:&Box (alloca Box))` all compiled. The mistake is not
specific to collection literals (whose expansion may change in a later
stage); it is that a form which *produces* a stack slot did not say so.

## 2. FS-1 — every producer of a stack slot is a taint source

`val-taint-frame` (beside the other taint helpers in `src/nucleusc.nuc`)
marks a `Val` as the address of storage in the current frame; the four
producers call it:

| producer | site |
|---|---|
| `(alloca T [n])` | `emit-alloca-form` |
| struct compound literal `(S …)` | `emit-struct-lit` |
| array literal `(array T …)` | `emit-array-lit` |
| the TC-3 materialization slot | `tc3-materialize` (which now takes the scope; `materialize-struct-value`'s own copy of the rule is gone) |

Collection literals need no site of their own — their `alloca` is the first
row. The closure envs (`emit-cfn`'s joined-taint block, the vfn/mfn stack env)
are left as lambda.md governs them; their return path is the `BoxedFn` box.

The region is the current lexical scope, as `&x` uses the binding's home. An
entry-block `alloca` in truth lives for the whole frame, so this is deeper
than reality; nothing today distinguishes the two (only `return` enforces
frame taint), and a future nested-region pass is the place to revisit it.

## 3. FS-2 — a by-value slot discharges frame taint

Frame taint is a property of an **address**. A `(ref S)` flowing into a
by-value `S` slot is loaded through (W5d in `coerce-int-val`; `emit-struct-ret`
copies the bytes out on the aggregate-return path), so the address never
arrives. Without this rule FS-1 refuses `(defn pt-make ():Pt (let (p (alloca
Pt)) … (return p)))` — one existing fixture, `w37base.nuc`, is exactly that —
and the by-value `(defvar options:(Vector i32) […])`, which is the *correct*
spelling of the motivating program (the copy owns the heap buffer).

`frame-taint-survives (v dst)` is the one predicate: frame taint reaches
`dst` unless `v` is a `TY-PTR` and `dst` a `TY-STRUCT`. It is consulted at
every sink and at every **adoption** — `sym-adopt-taint` for let/with/set!
bindings — so a struct-typed binding never carries stale frame taint (which
would otherwise leak back out through `&binding`), and in
`emit-union-construct`, where a `(ref S)` literal placed in a by-value payload
field is likewise loaded (this is why `(err (S21Err …))` in the s21 fixture
stays clean).

## 4. FS-3 — the sinks

* **`return`**, explicit and implicit, refuses a frame address that survives
  into the declared return type. The implicit sink no longer fires for a
  `void` function (nothing leaves it) and now names frame storage rather than
  a `with` resource.
* **A `defvar` initializer.** `g-init-fn-active` is 1 while
  `init-emit-function` drains the worklist (cleared there and by
  `reset-function-state`, so a failed initializer at the REPL does not leave
  it armed). `emit-set` on a global with a surviving frame address under that
  flag dies: `defvar: the initializer of 'options' is the address of
  frame-local storage, reclaimed when the initializer function returns — store
  the value itself, or place it with an allocator`. This is the one global
  store that is provably an escape; every other global store stays an
  intra-frame borrow (§6).

## 5. FS-4 — the frame flag travels through joins (bugs found on the way)

Three sites copied `taint` without `taint-frame`, so a frame address arrived
at a sink classified as a `with` resource:

* `emit-set`'s **result** value (`(set! g &b)` as the last form of a `void`
  function was refused with `resource bound by `with` escapes via implicit
  return` — wrong message, wrong verdict; the `void` half of §4 is the other
  half of that fix);
* `binding-address-val` — `&p` where `p` is a pointer local bound to a frame
  address;
* every control-flow **join**: `cond`'s phi, `match` over a tagged union and
  over both niches, `unwrap`, `unwrap-or`, `if-some`'s binder, `some`/`ok`
  construction and `emit-union-construct`'s payload merge — all through
  `taint-merge`, which merges scopes only.

`taint-join-frame` folds a contributor into an accumulator: the join is
frame taint only when every tainted contributor is; one `with` contributor
makes it `with` (the stronger constraint, the direction the cfn capture join
already picks). `taint-acc-join` is the same over a `Val` accumulator; the
niche `match` arms carry a `tfbox` beside `ttbox`. `(if c &a &b)` returned
now says `address of frame-local storage escapes via return`.

## 6. Measured before choosing (the options, and why 1 + 2)

Each candidate was added to the compiler for one build and run over the
self-compile (all 263 `alloca` sites in `src/` and `lib/`) and the 1079-test
suite, then reverted.

1. **Taint `alloca` results** — self-compile clean; 1076/1079, the three
   failures one fixture (`w37base.nuc`) returning a `(ref Pt)` into a by-value
   `Pt` — the false positive §3 removes. Does not catch the `defvar` case on
   its own: the initializer is a `set!`, and `emit-set`'s sink deliberately
   skips frame taint.
2. **The `defvar` initializer as a sink** — zero false positives by
   construction; useless without 1 for `alloca`/literal initializers.
3. **Every global store as a sink** — 9 sites in `src/nucleusc.nuc` (`(set!
   g-decl-out &ct-decl)`, the `g-out`/`g-def-stream` save/restore pairs) and 8
   in `examples/` (every `with-handler` expansion: `(set! g-handler-top (as ptr
   ~h))`, `lib/error.nuc:82–89`), all the scoped push/pop shape the compiler
   cannot prove, with no launder available (`as`, `cast` and `unsafe/cast` all
   preserve taint on purpose). Rejected: it needs a new spelling applied 17
   times and half-reverses the L1 "stores are borrows" rule without going all
   the way to heap fields.
4. **A syntactic check at `defvar`** (`(ref …)` type, `alloca` head) — misses
   `(let …)`, macros, `&local` and the literal (its `alloca` is in the emitter).

1 + 2 with the discharge rule: ~five small edits, zero measured false
positives across `src/`, `lib/`, `examples/` (167 compile) and the suite.

## 7. Boundary (unchanged, now restated)

Still outside, as lifecycle.md §3 documents: a frame address stored into a
heap struct field or a global from an ordinary function and read after the
frame is gone (option 3's territory); a pointer smuggled inside a by-value
struct (a `StrView` over an `alloca` buffer — struct literals do not merge
field taint); a `cfn` capturing a pointer-typed local (its slot address is
untainted by design, `binding-address-val`); the closure envs (§2).

## 8. Gates and as built

* `build/nucleusc.ll` byte-identical stage 1 → stage 2 (the change is to
  diagnostics and `Val` bookkeeping only); no boot refresh.
* Fixtures: `tests/fixtures/s21-frame-*.nuc` — six rejections (alloca return,
  literal implicit return, vector-literal return, defvar from `alloca`, defvar
  from a vector literal, `cond` join) and one accept fixture also run as a
  golden (`s21-frame-discharge-runs`): the by-value defvar literal reads `len
  5`, by-value copies out of `alloca`d and literal-backed pointers read their
  fields, a `pick`ed borrowed pointer through `cond`, the `with-handler` shape
  in an ordinary function, a tainted `set!` as a `void` function's last form.
* Two fixtures that used a dangling return as scaffolding were repaired to
  say what they meant: `w5d-struct-slot-maybe-null.nuc` returns `&gp` of a
  global (its row moves to line 13), and `s16-pk-access-align`'s `lit` reads
  the packed field inside the function instead of returning the literal.
* Docs: special-forms.md "Pointer lifecycle" (sources, discharge, the two
  sinks, the `void` rule), toplevel.md "Run-time initializers", collections.md
  literal errors.
