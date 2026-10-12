# `(dyn P)` for arbitrary protocols, and the borrowing `(dyn &P)`

**Status: Stage 24; complete. DP-1 … DP-6, BD-1 and BD-2 built 2026-10-10
(§5). AL-5 is next.**
Written 2026-07-07 as a future
item (`design/future/`); reviewed against the tree and brought into Stage 24
on 2026-10-09, because AL-5 ([overview.md](overview.md) §4.3, §9) changes
`Alloc` to `(dyn &Allocator)` and needs both halves of this document. The
review's findings are §0 and §1; the borrowing `dyn` is new, §4. The phases
(§5) run before AL-5. Q1–Q9 (§7) were ruled 2026-10-10, every one as
recommended.

Extends Stage 13's type-erasure machine
([stage13/type-erasure.md](../stage13/type-erasure.md), TE-6) from
single-method, non-parametric protocols to (nearly) arbitrary ones:
multi-method protocols, parametric protocol *applications* with concrete
arguments (`(dyn (Iterator i32))`), a per-method dyn-safety rule instead of the
blanket gate, and a non-owning form. Clients: `Alloc` (AL-5), and the native-IO
`Writer` protocol ([future/native-io.md](../future/native-io.md) §1.1), which
shipped single-method (Option A) and can gain `flush` (Option B) once this
lands.

The borrowing `dyn` is a section of this document rather than a sibling,
because it is the same machine: the same vtable (§4.2), the same dyn-safety
rules, the same coercion sites and the same dispatch. Only ownership differs.
Two documents would describe one phase list twice.

## 0. What changed since 2026-07-07

Verified against `ce2084a` on 2026-10-09: every function the original named,
by name, plus the probes in §1.2 (compiled with a build of that tree).

- **Two claims were wrong when written.**
  - *"No formal super-protocols exist."* `(extend Sub Super)` between two
    protocols has recorded an edge in `g-proto-supers` (`proto-super-add`,
    `src/generics.nuc`) since 2026-06-08. Conforming to `Sub` requires
    conforming to `Super`, and Stage 24 uses it (`InitFrom` and `TryInitFrom`
    extend `Init`). Super edges are plain-protocol only. §2 now defers
    super-protocol vtables for want of a client, not of a mechanism.
  - *"Methods that mention `Self` outside the receiver are rejected,
    whole-protocol, at the dyn site."* Nothing checks this. A box of such a
    protocol is built, and the *call* fails with `unknown type: Self`. A
    by-value `Self` receiver is worse: it compiles and runs, and returns
    garbage (§1.2, probe 4).
- **Renamed or reshaped, same role.**
  - The parallel `g-vtable-keys`/`g-vtable-names` arrays are one
    `g-vtable-table` of `VtableEntry` (Stage 14 §14.5). The key is still
    `"<type-spelling>/<proto>"`.
  - The two v1 gates live in `dyn-vtable-method-irname-in`. A wrapper,
    `dyn-vtable-method-irname`, arms `g-type-key-ok` around it (Stage 15 B3′).
    There is now a third gate, for a signature with its own `:where`.
  - `Conformance.args` is a `?&(Vector Symbol)` compared by
    `conformance-args-eq` (Stage 14 §14.4).
  - The `"Fn"` special case in `ensure-vtable-for` is `(= proto "Fn")`, not a
    `strcmp`.
  - Receivers are spelled `self:&Self` (Stage 21 pointer kinds). `(ref Self)`
    still reads as the same type.
- **Added since, and in the way.**
  - **Box identity is the protocol's canonical name**, from `dyn-proto-key`
    (Stage 15 B6), which consults no registry so that it answers the same at
    the signature prescan and at emission. *May this file name `P`?* is asked
    separately, at the annotation site, by `dyn-annot-record` and
    `drain-dyn-annots`. A parametric key (§3.4) must keep both properties.
  - **Two coercion sites, not one.** `maybe-box-into-slot` covers `let`/`with`
    and `return`; `emit-call-with-args` has its own pair of blocks for
    arguments. Both call `box-require-same-kind`. Struct-literal fields and
    `set!` reach neither (§3.5).
  - **Two dispatch hooks, not one.** `emit-generic-call` forwards a call whose
    first argument is a box, and so does `emit-call-with-args`, for a method
    with a single conformer (W9 item 41). Both take a box *value*, not `&box`.
  - **AVR refuses every box.** `ensure-vtable-for` calls
    `avr-reject-fn-value`, because a vtable holds function addresses as data.
    AL-1 made indirect calls work on AVR (`fnptr-callee` casts into the program
    address space), and `allocator.nuc` is compiled for AVR whenever a program
    reaches it through `import-ct`. So AL-5 needs AVR vtables (§3.6).
  - **Conformance promises** (Stage 24 CQ-1a). `conformance-known` answers for
    an `extend` written below its use, but box admission still asks
    `conformance-lookup`, so a box built above its `extend` is refused.
  - **Generic protocol methods** (a signature with its own `:where`) are
    supported by `extend`. They are the rule-3 case of §3.3.
- **The emitted forward is not ABI-lowered.** `emit-dyn-forward` prints each
  argument as a raw `type-to-ir` aggregate. Stage 16 FP-2 fixed the same
  defect in `emit-box-invoke` (the BoxedFn path) and not here. A 24-byte
  struct argument or return through a `(dyn P)` produces garbage (probe 5).
  `Writer`'s `StrView` argument and `!void` return happen to work, because a
  16-byte aggregate decomposes the same way the callee's coerced pair does.
- **Bootstrap inertness still holds for every phase before AL-5.** No
  `(dyn …)` appears in `src/` or `lib/`, and `lib/`'s `BoxedFn`s are in
  `combinators.nuc` templates the compiler does not import. AL-5 is the step
  where the compiler starts using `dyn`, and it takes a boot refresh
  ([overview.md](overview.md) §9).

## 1. Ground truth

Grep by NAME; line numbers drift. Sites are in `src/nucleusc.nuc` unless noted.

### 1.1 The machine

- **Representation.** A `(dyn P)` is a 16-byte `TY-STRUCT` `{data, vtable}`.
  Each protocol gets its own StructDef, `%__dyn.<P>`, from `dyn-type`
  (`src/union-registry.nuc`), memoized in `g-dyn-table` (`DynEntry`:
  `key`, `ty`, `proto`). `type-eq` is StructDef identity, so two protocols are
  two types. It rides the CE-3 `ABI-COERCE2` path. (`%__fatptr` from
  `ensure-fatptr-sdef` is the TE-1 layout, still registered on the first box.)
- **The type form.** `parse-type-from-node`'s `dyn` arm (`union-registry.nuc`)
  accepts only a bare symbol. `(dyn (Iterator i32))` and `(dyn &P)` (which
  reads as `(dyn (ref P))`) both die: `protocol must be a bare symbol`.
- **The vtable.** `ensure-vtable-for` emits
  `@__vt.<type-mangle-token T>.<proto> = internal constant { ptr, ptr }
  { ptr method0, ptr drop-or-null }` (in its own `.rodata` section when IR
  sections are on), memoized in `g-vtable-table`. The protocol half of the name is the canonical
  key passed through `sanitize-for-ir` (`dp/Describe` → `dp_Describe`), while
  the type half uses `type-mangle-token` (`dp/Fox` → `dp__Fox`). Slot 0 comes
  from `dyn-vtable-method-irname` (or the closure's `invoke` for `"Fn"`), slot
  1 from `vtable-drop-irname`.
- **Synthesis.** `dyn-vtable-method-irname-in`: `dyn-resolve-protocol`, the
  three gates (`num-sigs != 1`, `num-params > 0`, a `:where` in sig 0), then
  `subst-proto-sig-node sig <Self> (ppp 'params) null 0`, and
  `generic-find-method-exact` on the method's name. Protocols from another
  file are read in that file's environment (`protocol-foreign?`,
  `env-arg-sym`, `protocol-env-enter`), and a per-sig loop must keep that.
- **Boxing.** `emit-box-value`: the source must be a `(ref Struct)`. A by-value
  binding is refused (`can only box a concrete struct value`), and a `&T` is
  copied bitwise into a `heap-allocate`d block (`emit-box-struct-move`). Then
  `admit-erased-conformance` (structural closure match, else
  `conformance-lookup`), `ensure-vtable-for`, and `ensure-box-drop-fn`, which
  registers `(box, Drop)` and emits the shared `@__boxedfn_drop` once per
  module. That thunk reads the drop slot at index 1, calls it, then calls
  libc `free` on `data`.
- **Dispatch.** `dyn-method-slot` scans `P`'s sigs by name and returns the sig
  index (checking a qualifier with `same-ns-qualifier`). `emit-dyn-forward`
  parses the *raw* sig (no `Self` or argument substitution), GEPs a hardcoded
  `{ ptr, ptr }`, loads the slot, coerces each argument with `coerce-int-val`,
  and emits the indirect call with `data` first.
- **Diagnostics.** `dyn-require-protocol` (annotation site) and
  `dyn-resolve-protocol` (construction, a key lookup). `box-spelling` prints
  `(dyn P)`, but `type-display` still prints `__dyn.P` in most messages
  (fixed in DP-6).
- **Records.** `Protocol` is `{name, sigs, num-sigs, params, num-params, priv,
  src-ns, src-file, src-line, src-imports}`. `subst-proto-sig-node`'s
  params/args path is exercised on every parametric `extend`
  (`proto-sigs-resolve-in`), so DP-3 reuses tested code.

### 1.2 Probes

Small programs compiled with a build of `ce2084a`. The sources are not kept.

| # | Program | Result |
|---|---|---|
| 1 | Two conformers of a one-method protocol, boxed and called | Runs. IR as in §1.1. |
| 2 | A two-method protocol | `(dyn Two): only single-method protocols are boxable in v1` |
| 3 | `(dyn (Src i32))`, `(dyn &Show)` | `protocol must be a bare symbol (parametric protocols are not boxable)` for both |
| 4 | `(defprotocol Val (val (self:Self):i32))`, boxed and called | **Prints garbage.** The forward passes `data`; the method expects the struct by value. |
| 5 | A method taking a 24-byte struct and returning a 16-byte one | **Prints garbage.** The forward passes `%Big` where the callee takes `byval`, and expects `%Two` where it returns `{ i64, i64 }`. |
| 6 | A method with `o:&Self`, and one returning `Self` | Box built; the call dies `unknown type: Self`. |
| 7 | A `Drop` value boxed from `&p` inside `(with (p …))` | **Drops twice.** The box copies the value and both copies are dropped. |
| 8 | `(extend Pt Show)` written below the box | `type 'Pt' does not conform to the protocol` |
| 9 | A struct-literal field of type `(dyn Show)` given a `(Pt 2)`; `(set! a (Pt 5))` on a box | Both refused as type mismatches. Neither position boxes. |
| 10 | `(show &a)` with `a` a box; `(twice &a)` with `twice` over `:where (Show T)` | Neither forwards. The first is an argument mismatch; the second fails the constraint (a box does not conform to its own protocol). |
| 11 | A library that declares `Show`, takes `(dyn Show)` and calls `show`, with no conformer in the unit | `unknown: show — not defined anywhere in this compilation unit` |
| 12 | `--emit-cheader` of a struct with a `(dyn Show)` field | **The field is written `void* s;`**, eight bytes for a sixteen-byte field. |
| 13 | `--emit-nuch` of `(deftype AnyShow (dyn Show))` and a `(dyn Show)` parameter | Written as `(dyn Show)`, so it round-trips textually. *Found in DP-2:* importing that header keyed the parameter as a bare `Show` (the `.nuch` prescan read signatures before protocols), so passing a box to it was a type mismatch. Fixed in DP-2. |
| 14 | A `(Vector (dyn Show))` holding two conformers, filled through `let`-bound boxes | Runs. `conj` with an unboxed `(Q 4)` is refused: overload resolution does not box. |
| 15 | An AVR vtable (`llc-19`, `-mtriple=avr`) with slots typed `ptr addrspace(1)`, called through a `ptr addrspace(1)` load | Assembles. The slots are `.short pm(m0)`. A plain-`ptr` slot holding an `addrspacecast` constant also assembles. |

Probes 4, 5, 7 and 12 are silent wrong answers in shipped code. DP-1, DP-2,
DP-4 and BD-2 fix them as part of the work they belong to.

## 2. Scope

**In:**
- multi-method protocols;
- parametric applications with every argument concrete (`(dyn (Iterator i32))`);
- per-method dyn-safety, with call-site diagnostics;
- the coercion positions a box is missing (struct-literal fields, `set!`);
- dispatch on `&box`;
- AVR vtables;
- the borrowing `(dyn &P)` (§4);
- the C header rendering of both box kinds;
- the BoxedFn cleanup this enables (optional, §3.7).

**Out, with reasons:**

- **Multi-protocol boxes** (`(dyn (Show Eq))`). The spelling collides with a
  parametric application, and a combined protocol with `extend` covers the
  need. No client.
- **Downcasting / RTTI.** Needs a type-identity word the vtable does not carry.
  Vtables are `internal` per module, so a vtable's address is not an identity
  either.
- **Super-protocol methods through a box.** The mechanism exists (§0). The
  standard shape is to append the supers' slots after `P`'s own and to give an
  upcast `(dyn Sub)` → `(dyn Super)` its own vtable. No client: `Allocator` has
  no supers. Deferred.
- **A box conforming to its own protocol** (probe 10, second half): `(dyn P)`
  satisfying `:where (P T)` and `conforms?`. It needs a forwarding method per
  (box, method), emitted through the worklist. §7 Q8.
- **Boxing at overload resolution** (probe 14). A generic call does not apply
  an erased coercion, which matches §4.1 of [overview.md](overview.md): there
  is no implicit conversion at a call site. A typed binding or `handle` does it.
- **Unchanged TE deferrals:** `clone` on boxes, per-allocator *owning* boxes
  (the fat pointer has no word for the allocator), the `cfn`-box drop gap.

## 3. Design (owning boxes; most of it serves both kinds)

### 3.1 Vtable layout: append, don't relayout

For a protocol with methods `m0 … m(k-1)` (declaration order):

```
{ ptr m0, ptr drop, ptr m1, …, ptr m(k-1) }
```

The existing two slots keep their positions and further methods append at
`2…k`. `slot(i) = (if (= i 0) 0 (+ i 1))`.

The reason is unchanged: `@__boxedfn_drop` reads index 1, the BoxedFn path
loads index 0, and a one-method protocol still emits `{ ptr, ptr }`. The
alternative, a fixed header `{drop, m0, m1, …}`, is cleaner and would leave
room for size and alignment words if owning boxes ever allocate through an
`Alloc`. Nothing gates on the old text (there is no IR snapshot gate, and the
compiler boxes nothing), so the choice is open: §7 Q6.

The constant's IR type is a struct of `k+1` `ptr`s. `ensure-vtable-for` and
`emit-dyn-forward` derive it from `num-sigs`; `@__boxedfn_drop` reads only
index 1 and keeps `{ ptr, ptr }` as its GEP type, which is valid for any `k`.

A method that is not dyn-callable (§3.3) still owns its slot, as `ptr null`.
Slots are positional and never compacted.

### 3.2 Synthesis and dispatch

- **`dyn-vtable-method-irname-in` becomes a loop over `sigs[0…k)`.** The body
  stays: resolve the protocol, substitute `Self` and the application's
  arguments (§3.4), parse, `generic-find-method-exact`, in the protocol's file
  environment. The `num-sigs` and `num-params` gates go. A sig that fails §3.3
  yields a null slot. A callable sig with no implementation dies, as today.
- **`admit-erased-conformance` asks `conformance-known`**, not
  `conformance-lookup`, so an `extend` below the box is found (probe 8). The
  vtable is built only after the promise is redeemed, and the per-sig loop
  still checks every method exists.
- **`dyn-method-slot`** returns the sig index; its callers apply `slot(i)`.
- **`emit-dyn-forward`:**
  - GEP against the `k+1` type;
  - die at the call when the method is not dyn-callable, naming the method and
    the rule (`(dyn Same): 'same?' is not dyn-callable: Self appears in a
    parameter`);
  - parse the sig with the application's arguments substituted (§3.4). A
    callable sig mentions `Self` only in the receiver, which the forward does
    not parse, so no `Self` substitution is needed;
  - **lower the call the way `emit-box-invoke` does**: coerce each argument
    with `coerce-call-argument`, then `abi-args-begin`, `abi-arg-frag` for
    `data` and each argument, and `abi-emit-struct-call` for a non-`DIRECT`
    return. This fixes probe 5. Keep it one helper with `emit-box-invoke`
    rather than a third copy.
- **Dispatch on `&box`** (probe 10, first half). Both hooks also accept a first
  argument of type `&B` or `(ptr B)` for a box type `B`, and load the box. A
  `?&B` must be narrowed first, as for any `?&` receiver. Collections call
  `(allocate (ref self 'alloc) …)`, so AL-5 needs this.
- **A box call needs no conformer in the unit** (probe 11). Today the hooks
  run only once the head names a `Generic` or a solitary `defn`. Before a call
  reports an unknown head, check whether the first argument's type is a box
  whose protocol declares that name, and forward. A library that only takes
  `(dyn P)` must be able to call `P`'s methods.

### 3.3 Per-method dyn-safety

A method is **dyn-callable** if:

1. **Its first parameter is a pointer to `Self`**: `&Self`, `?&Self` or
   `(ptr Self)`. The forward passes `data`, a pointer. A by-value `Self`
   receiver, or none, makes the method not callable. (Today such a method is
   called anyway, with the wrong argument: probe 4.)
2. **`Self` appears nowhere else**, in any parameter or the return, at any
   depth (`o:&Self`, `?Self`, `(Vector Self)`). The concrete type is erased at
   the call site. `Eq`'s binary methods and `Clone`'s `clone` are the standard
   exclusions.
3. **The signature has no `:where` of its own.** A generic method has no single
   implementation for a slot.
4. **After the application's arguments are substituted (§3.4), every type is
   concrete.**

Struct parameters and returns by value are allowed, since the forward is
ABI-lowered (§3.2).

A protocol is boxable if at least one method is dyn-callable. A protocol with
no methods is refused (no client; a marker protocol has nothing to dispatch).
This is Rust's per-method `where Self: Sized` shape rather than a
whole-protocol wall: a protocol with one binary method keeps `dyn` for the
rest.

The classification is a pure function of `(P, args)`, shared by synthesis
(null slot) and the forward (diagnostic). `Allocator`'s methods all pass.

### 3.4 Parametric applications: `(dyn (Iterator i32))`

- **Parse.** The `dyn` arm accepts `(dyn (P arg…))` beside the bare name. A
  list whose head is `ref` is the borrowing form (§4.1), never an application,
  since `ref` cannot name a protocol. Every `arg` must be a concrete type; a
  type variable is an error (`(dyn (Iterator E))` is not a thing).
- **Box identity.** `DynEntry` gains `args:?&(Vector Symbol)` (canonical type
  spellings, as in `Conformance.args`) and `borrowed:bool` (§4). The memo key
  is `dyn.<P>` plus one `type-mangle-token` per argument. The arguments are
  read by `parse-type-from-node` like any other type in the signature being
  prescanned, so the key is no less phase-stable than the signature itself.
  DP-3 must still prove that with a probe whose argument is a type from
  another file's namespace (the B6 failure mode was two keys, hence two
  StructDefs, for one type).
- **Vtable name.** `__vt.<T>.<P>.<argtoks>`. Stage 11's coherence rule (a type
  conforms to a parametric protocol at most once,
  [deferred/overview.md](../deferred/overview.md)) makes the arguments
  redundant today, but naming them costs nothing and keeps the name correct if
  that rule is ever relaxed.
- **Substitution.** Pass the arguments through `subst-proto-sig-node`'s
  params/args parameters (today `null 0`), in synthesis and in the forward.
- **Admission.** The conformance record's `args` must equal the application's
  (`conformance-args-eq`). `(extend Foo (Iterator i32))` admits
  `(dyn (Iterator i32))` and not `(dyn (Iterator i64))`, with a message that
  names both.
- **Safety.** Rule 4 runs after substitution, so `next`'s `?E` is callable once
  `E` is `i32`.

### 3.5 Coercion positions

A value is boxed (or, for §4, borrowed) where it meets a box-typed slot. Today
that is `let`/`with` initialization, `return`, and a direct call's argument.
Two positions are missing, and AL-5 needs both:

- **A struct-literal field**, positional or named, including a `defvar`'s
  constant initializer (§4.6);
- **`set!` of a box-typed place**: a local, a global, or a field.

Both call `maybe-box-into-slot`, as the conventions note on erased-slot
coercion asks ("give it the same call, not a copy").

**Boxing a `Drop` value from a reference** (probe 7). An owning box copies the
value, so boxing `&p` where `p`'s type conforms to `Drop` leaves two owners.
Refuse it, and point at `(dyn &P)` to borrow or at an rvalue to move. §7 Q5.

### 3.6 AVR: vtables in the program address space

On a target whose functions live in another address space (`prog-as != 0`,
AVR's `P1`), the vtable's slots are typed `ptr addrspace(N)` and loaded as
such, and the forward calls through them directly (probe 15). Then
`ensure-vtable-for` stops calling `avr-reject-fn-value`.

- `@__boxedfn_drop` loads its slot the same way.
- `ensure-fnfwd-vtable` keeps the refusal. A BoxedFn over a bare `fn` stores a
  function pointer in a heap cell, which is still a function used as a value.
- avr-ld places `.rodata` in RAM, so a vtable costs two bytes of RAM per slot
  (ten for `Allocator`). Placing vtables in flash would need `LPM` loads
  (`addrspace(1)` loads of the slots). Deferred.

### 3.7 `BoxedFn` convergence (optional tail)

With multi-method and parametric `dyn`, `(BoxedFn (i32) i32)` and
`(dyn (UnaryFn i32 i32))` coincide. `ensure-vtable-for`'s `(= proto "Fn")` arm
could fold into the general parametric route, with structural derivation as
`admit-erased-conformance`'s closure branch. Pure cleanup, last or never.

## 4. The borrowing `(dyn &P)`

### 4.1 Spelling

`(dyn &P)`, which the reader delivers as `(dyn (ref P))`. Parametric:
`(dyn &(Iterator i32))`.

- It matches Stage 21: `&` says what the data word is, a non-null borrow.
  `(dyn P)` stays the owning box.
- `&(dyn P)` is already a type: a reference to an owning box. Reusing it would
  change its meaning.
- Rust writes `&dyn Trait`; this is the same idea with the pointer kind inside
  the form, the way `(ptr T)` puts it.
- `(dyn ?&P)` and `(dyn (ptr P))` are not accepted. A nullable borrow is
  `(Maybe (dyn &P))`, tagged (a niche on the data word is possible later).

### 4.2 Representation

The same 16 bytes, `{data, vtable}`: two pointers, the CE-3 `COERCE2` path, two
registers on SysV and RISC-V lp64d, four bytes on AVR.

- `data` points at an existing instance. There is no heap block.
- `vtable` is **the same `@__vt.<T>.<P>` an owning box uses**, drop slot
  included. A borrowing box never reads the drop slot. Sharing it means one
  vtable per (type, protocol), and makes an owning box → borrowing box view a
  copy of two words (§4.3). Leaving the drop slot out would save one word per
  vtable and cost that.
- Its own StructDef, `%__dynref.<P>`, so `type-eq` keeps `(dyn P)` and
  `(dyn &P)` apart (`DynEntry.borrowed`, key `dyn&.<P>…`).

### 4.3 Forming one

| Source | Into `(dyn &P)` | Into `(dyn P)` (owning, for comparison) |
|---|---|---|
| `&T`, `T` conforms to `P`; a binding of type `T` is taken by address, as `handle` takes one today | `{source, @__vt.T.P}` | heap copy (§3.5 refuses a `Drop` `T`) |
| struct literal `(T …)` (a frame slot) | `{slot, vtable}`, frame-tainted | heap move |
| a call's by-value result | refused: no address (bind it first) | heap move |
| `?&T` | refused: narrow it first | refused |
| `(ptr T)` | refused: `(dyn &P)` promises non-null; convert with `as` first | as today |
| `(dyn &P)` / `&(dyn &P)` | copied / loaded | refused: a borrow cannot become an owner |
| `(dyn P)` / `&(dyn P)` (owning, same application) | the same two words: a view | identity / load |
| `(dyn &Q)`, `Q` ≠ `P` | refused by `box-require-same-kind` | refused |

The "already a box of the same kind" rows matter more here than for owning
boxes. Without them, `&Alloc` into an `Alloc` slot would wrap a box in a box.

### 4.4 Lifetime

A borrowing box carries its source pointer's taint, exactly as `&x` does.

- The coercion copies `taint` and `taint-frame` from the source `Val`; a view
  of an owning box takes the box binding's own taint, as `&box` would.
- **`frame-taint-survives` treats a `(dyn &P)` destination as a pointer**, so
  the FS-2 discharge (a `(ref S)` into a by-value struct slot is loaded through)
  does not apply. Without this, a borrowing box is a 16-byte struct and every
  frame address would launder through it.
- The sinks are Stage 21's: `return` refuses a frame- or `with`-tainted
  borrowing box, and a `defvar` initializer refuses a frame-tainted one.
  `(defn f ():(dyn &Show) (let (p (Pt 1)) (return &p)))` is refused, as
  `(return &p)` is for a `&Pt`.
- Stores into heap fields stay borrows the analysis does not follow, as for
  any pointer ([frame-storage-escape.md](../stage21-cleanup/frame-storage-escape.md)
  §7). A collection that outlives its allocator is overview.md §8's contract,
  unchanged.

### 4.5 Drop, `with`, equality

- **Never dropped.** A `(dyn &P)` does not conform to `Drop`. `with` binds it
  without arming a cleanup, and a struct field of that type has no field drop.
  `ensure-box-drop-fn` and `boxedfn-drop-target` return without effect for it.
- **No `=`**, for either kind, as today. Comparing data pointers is easy to
  write wrongly (a view and its owner are equal; two vtables for one type in
  two modules are not), and no client needs it (§7 Q9).

### 4.6 Constants, headers and `.nuch`

- **A constant.** A borrowing box of a global's address, `&g`, is the link-time
  constant `{ ptr @g, ptr @__vt.T.P }`. The global-init constant folder (Stage
  15 G-1) folds it, in a `defvar` initializer and in a struct literal there, the
  way it already folds `(H &g 4)` into `@h = global %H { ptr @g, i32 4 }`.
  `g-arena` needs this under §7 Q3's recommendation.
- **C headers.** Today a `(dyn P)` field is written `void*` (probe 12), which
  is wrong. Both kinds become `typedef struct nuc_dyn_<P> { void* data;
  const void* vtable; } nuc_dyn_<P>;`, and `nuc_dynref_<P>` for the borrowing
  kind. That matches the ABI and lets C hold, pass and return one. C cannot
  build one or call through it.
  - A function signature mentioning an owning box stays excluded (L8: it
    carries ownership C cannot honor).
  - One mentioning a borrowing box is emitted. Otherwise, after AL-5, every
    `init` and every function taking an `Alloc` would drop out of the
    library's headers.
- **`.nuch`** writes `(dyn (ref P))`, which reads back (probe 13 shows the
  owning form does).
- **Link names.** Mangled names spell a parameter's type token. After AL-5 the
  token for `Alloc` is the box's, so every `init` overload and every function
  taking `Alloc` gets a new link name. The headers regenerate; nothing else
  depends on the old names.

### 4.7 `Allocator` through a borrowing box

All four of `Allocator`'s methods pass §3.3. `handle` is the odd one: it
returns `Alloc`, which under AL-5 *is* `(dyn &Allocator)`. Kept as a method,
every allocator writes `(defn handle (self:&X):Alloc (return self))`, and the
vtable carries a slot that returns a copy of the box it was called through.
The coercion of §4.3 already is the handle. So:

- **`handle` leaves the protocol** (§7 Q2). The library keeps `handle` as a
  function, so `new`/`make` and user code are unchanged:
  `(defn handle (a:&T :where (Allocator T)):Alloc (return a))` coerces any
  allocator, and `(defn handle (a:&Alloc):Alloc (return @a))` passes an
  existing handle through. A user allocator then writes three methods and
  `drop`.
- **`alloc-zeroes?` needs a replacement.** `create-bytes` skips the `memset`
  for an arena by reading `Alloc.kind`, recursively through `Tracking`. A
  borrowing box has no kind. The Rust shape is a fourth method,
  `allocate-zeroed`: `Heap` uses `calloc`, `Arena` is `allocate` (its blocks
  are zero), `FixedBuffer` zero-fills, `Tracking` forwards to its parent's
  `allocate-zeroed`. `new` calls it, and the double-zero fix of `ce2084a`
  survives (§7 Q4).
- **The zero value.** Today a zero-filled `Alloc` is the heap handle, so
  `g-arena`, a zero `Arena` and a zero `Tracking` need no initializer. A
  zero-filled `(dyn &P)` is `{null, null}`, and a call through it faults. §7
  Q3 has the options. The recommendation is no zero value: `(dyn &P)` is
  non-null like `&T`. `Arena` conforms to `Init` (`(make Arena)` is over the
  heap, `(make Arena a)` over `a`), and `g-arena` gets a constant initializer.
- **The plain functions stay.** `alloc-allocate`, `alloc-reallocate` and
  `alloc-deallocate` are what compiler-synthesized code calls (the `cfn`
  environment, `create.nuc`). Each becomes one forward. A `cfn` environment
  keeps storing a pointer to its handle (`__alloc`).

## 5. Phases

Each phase ends with `make test` and `make bootstrap`; DP-5 adds
`make avr-test`, BD-2 adds `make check-headers`. Every phase through DP-6 is
inert under self-compilation (nothing in `src/` or `lib/` mints a box), so each
should be **byte-identical**; verify, do not assume. Orchestration follows
type-erasure.md: scoped reads, grep by name, one implementation agent per
phase, a build-test-runner gate.

Order: DP-1 → DP-2 → DP-3, DP-4, DP-5 (any order) → BD-1 → BD-2 → DP-6 → AL-5.
AL-5 needs everything except DP-3. DP-3 comes before AL-5 to keep the stage's
order simple, not because AL-5 uses it.

- **DP-0 — ground-verify. Done 2026-10-09** (§0, §1). Re-run the §1.2 probes
  if the tree has moved by the time DP-1 starts.
- **DP-1 — layout, safety, synthesis.** §3.1 slots and `k+1` constants; §3.3
  as one predicate; the per-sig loop with null slots; promise-aware admission.
  A one-method protocol's vtable keeps its text.
  *Gate:* a two-method protocol boxes; a by-value-`Self` method gets a null
  slot (probe 4 no longer runs); a box above its `extend` builds (probe 8).
  **Built 2026-10-10.** In `src/nucleusc.nuc`:
  - `dyn-sig-safety` is §3.3 rules 1–3 and returns a `DynSafety` reason
    (`src/compiler-types.nuc`). The receiver test (`dyn-self-ptr-node?`) is
    syntactic and sees through the reader's spellings: `self:&Self` reads as
    the symbol `self:ref:Self`, so it goes through `colon-spelling-node`, and
    `?` through `sigil-split`. Rule 2 uses `node-mentions-tyvar-named`.
  - `dyn-require-boxable` replaces the `num-sigs` gate in `emit-box-value`.
    It refuses a protocol with no methods, and one where no method is
    callable, listing each method's reason.
  - `dyn-vtable-method-irnames` loops over the sigs, giving the none symbol
    (emitted `ptr null`) for an unsafe one. `ensure-vtable-for` builds
    `vtable-ir-type (k+1)`. For `k = 1` the text is the old text, and so is
    every existing dyn/BoxedFn example's IR.
  - `admit-erased-conformance` asks `conformance-known`.

  Deviations:
  - The `num-params` gate stays, in `dyn-require-boxable`. It belongs to DP-3,
    which removes it.
  - Rule 4 is not implemented, because without applications there is nothing
    to substitute.
- **DP-2 — dispatch.** `slot(i)` at the consumers; the ABI-lowered forward
  shared with `emit-box-invoke`; the not-dyn-callable diagnostic; `&box`
  receivers in both hooks; a box call with no conformer in the unit.
  *Gate:* both methods of a two-method protocol through one box; a mixed
  protocol errors only on the unsafe call, with the rule named; probe 5's
  24-byte argument and 16-byte return round-trip; `(show &a)` forwards; probe
  11 compiles and runs from a second file; `w9-dyn-solitary` still passes.
  **Built 2026-10-10.**
  - `emit-erased-call` is the single ABI-lowered indirect call, shared by
    `emit-box-invoke` and `emit-dyn-forward`. `emit-vtable-slot-load` is the
    single slot GEP and load.
  - `emit-dyn-forward` now takes `scope`. It calls `dyn-require-callable`
    first, then parses the sig in the protocol's environment and coerces each
    argument with `coerce-call-argument`. The old legacy-sig branch is gone.
    A `&B`/`(ptr B)` receiver is loaded after `require-derefable`, so a `?&B`
    must be narrowed.
  - `dyn-receiver-box` is the box test in both hooks (`emit-call-with-args`
    and `emit-generic-call`).
  - `emit-dyn-call-unbound` has the no-conformer path: `emit-dispatch` asks it
    before the unknown-name diagnostic.

  Bugs fixed:
  - Probe 4 is now refused.
  - Probe 5 round-trips.
  - Probe 5's shape on a *one-method* protocol printed garbage too (`356
    12582976` for `101 320`), which this also fixes.
  - Probe 8 builds.
  - Probe 10's first half forwards, as do `(ref h 'b)` and `(ptr (dyn P))`
    receivers.
  - Probe 11 runs from a second file.

  Beyond scope: the `.nuch` import prescan now runs `prescan-protocols` before
  `prescan-nuch-signatures`. Without it a `(dyn P)` in a header `declare` was
  keyed as a bare `P` (probe 13's note), which probe 11 needs.

  Tests: `tests/suite-dyn.nuc` has 10 tests; there are 7 diagnostic fixtures
  (`dp1-*`, `dp2-*`). `s21-protocol-sig-where` now expects the rule-3 message.
  Totals: 1379 tests, 1374 pass, and the 5 failures are the known
  suite-target ones. Byte-identical: the new compiler's IR for the old source
  equals the old compiler's, and `make bootstrap` passes.

  Still open:
  - Probe 10's second half (a box conforming to its own protocol) stays out
    of scope (§2).
  - Struct-literal and `set!` boxing is DP-4.
- **DP-3 — parametric applications** (§3.4).
  *Gate:* a `(Vector (dyn (Iterator i32)))` holding two conformers iterates via
  `next`; `(dyn (Iterator i64))` refuses an `(Iterator i32)` conformer, naming
  both; the same box type from two files when the argument is a type from a
  third file's namespace.
  **Built 2026-10-10.**
  - The `dyn` arm takes `(dyn (P arg…))` (`dyn-app-type`). A type-variable
    argument and a `ref` head are refused at the annotation; `(dyn &P)` says
    the borrowing box is not supported yet.
  - The arity is checked with the protocol's existence, at the drained
    annotation (`dyn-require-arity`): `(dyn Iterator)` and
    `(dyn (Iterator i32 i64))` are refused there.
  - `DynEntry` keeps the canonical spellings (`args`, compared by
    `conformance-args-eq`) and the parsed Types (`arg-types`). The forward and
    synthesis substitute them through `env-arg-of-type` markers
    (`dyn-arg-markers`), which read back as those Types in any file.
  - The memo key, the box StructDef and the vtable name carry one
    `type-mangle-token` per argument (`%__dyn.Sink.Big`, `@__vt.S1.Sink.Big`).
  - `dyn-require-app-args` admits a conformer only for the application it
    conforms to, naming both.
  - Messages spell the box as written: `box-spelling` prints `(dyn (P a))`.

  Deviations:
  - Rule 4 is "no parameter the box does not bind" (`DYN-UNBOUND`). With the
    arity enforced at the annotation it cannot fire today; it guards any later
    partial application.
  - `DynEntry.borrowed` is BD-1's.
- **DP-4 — coercion positions** (§3.5): struct-literal fields and `set!`
  through `maybe-box-into-slot`; the `Drop`-from-reference refusal if Q5 is
  ruled as recommended.
  *Gate:* probe 9's two forms box; probe 7 is refused with the message
  pointing at `(dyn &P)`.
  **Built 2026-10-10.**
  - `maybe-box-into-slot` runs in `emit-struct-lit` (both branches) and in
    `emit-set`, `emit-field-set`, `emit-ptr-set` and `emit-aset`, so `set!`
    boxes into a local, a global, a field, a `deref` and an `aref`.
  - `Val.fresh` marks a `(ref S)` that no binding owns: a struct literal's
    slot or a `move`. `emit-box-value` refuses a non-fresh source whose type
    has a drop, naming `(dyn &P)` (`dyn-borrow-subject`) and the owned forms.
  - A `defvar` whose struct literal boxes a field gets a run-time initializer
    (`const-lit-boxes?` in `defvar-const-init-ir`); before, it died asking for
    a compound literal. BD-2 folds the borrowing case to a constant.

  Deviations: `set!` through `deref` and `aref` box too (the design named a
  local, a global and a field). A by-value struct local cannot be boxed at all
  (`can only box a concrete struct value`); that predates this phase.
- **DP-5 — AVR vtables** (§3.6).
  *Gate:* an AVR compile of a two-method dyn program links through the AVR-3
  driver, and runs under simavr if the device is one simavr has; `avr-test`
  stays within its budgets.
  **Built 2026-10-10.**
  - `vtable-slot-ir` types a slot `ptr addrspace(N)` when `prog-as` is
    non-zero. `vtable-ir-type`, `emit-vtable-slot-load` and
    `@__boxedfn_drop` use it, so a slot is called as loaded.
  - `ensure-vtable-for` no longer calls `avr-reject-fn-value`, so capturing
    closures box on AVR too. `ensure-fnfwd-vtable` keeps the refusal.
  - `@__boxedfn_drop` loads at the target's pointer alignment, not `align 8`.

  Bug found: at `-O0` the program failed in LLVM's AVR backend ("ran out of
  registers during register allocation", in every function that calls
  through a slot). The fast allocator, the only one LLVM permits at
  CodeGenOpt `None`, cannot make an AVR indirect call through a pointer
  loaded in the function. Reloading the pointer from a stack slot did not
  help. Two fixes in `compile-and-link`:
  - `codegen-level-for-triple` runs AVR codegen at `Less` at least. Existing
    examples shrank: blink 604 → 550 bytes, uart-hello 862 → 762.
  - Before this, the error printed but nucleusc exited 0 with a broken ELF. A
    context diagnostic handler (`llvm-diag-handler`) now counts codegen
    errors, and the compile fails.

  Tests: `examples/avr-dyn.nuc` (two `dyn` methods and a boxed closure;
  simavr prints `HI45A`) is in `run-avr-test.sh`. `suite-target.nuc` has
  `dp5-avr-vtable-ir` and `dp5-avr-dyn-link`. On the DP-2 compiler both fail
  (the box is refused). On a compiler with the handler but codegen at `None`,
  the link fails.

  Open: the box machinery hard-codes `align 8` elsewhere (the heap store, the
  fat-pointer stores) and the library hard-codes `align 4` on `i32`.
  Both overstate alignment on AVR. The backend does not use it today.
- **BD-1 — the borrowing box** (§4.1–§4.5): the type form, `DynEntry.borrowed`,
  every row of §4.3, the views, taint and `frame-taint-survives`, no `Drop`.
  *Gate:* a `(dyn &Show)` over a `with`-bound `Drop` value calls through and
  the value drops once; returning one over a local is refused at the `return`;
  `&Alloc`-shaped pass-through does not double-wrap; an owning box viewed as
  borrowing calls through.
  **Built 2026-10-10.**
  - The type form. `dyn-app-type` (`src/union-registry.nuc`) takes
    `(dyn (ref P))` and `(dyn (ref (P a…)))`, through `dyn-name-type` and
    `dyn-args-type` with `borrowed` set. `(dyn ?&P)` and `(dyn (ptr P))` are
    refused at the annotation and name the spelling to use. DP-3's "not
    supported yet" refusal is gone.
  - `DynEntry.borrowed`; the memo key `dyn&.<P>…`; the StructDef
    `%__dynref.<P>…`. `dyn-borrowed?` is the one test.
  - `emit-borrow-into` (`src/nucleusc.nuc`) is §4.3's table. Both erased-slot
    sites call it for a borrowed destination: `maybe-box-into-slot` (let, with,
    return, `set!`, struct-literal fields) and `coerce-call-argument`.
    - A `&B` to a box is loaded first, so `&(dyn &P)` passes through unwrapped.
    - A borrowing box passes through after `box-require-same-kind`.
    - An owning box of the same application is viewed: two `extractvalue`s
      (`dyn-require-view`).
    - A by-value struct is borrowed only through `lvalue-sym`, using
      `binding-address-val`. A call result has no address and is refused.
  - `dyn-admit` is the conformance question both kinds ask. `emit-box-value`
    and `box-require-same-kind` refuse a borrowing box into an owning slot
    (`dyn-refuse-borrow-to-owner`).
  - Taint.
    - The box takes its source's taint (`val-copy-taint`). A view takes the
      box binding's own address taint.
    - `frame-taint-survives` keeps the taint for a borrowed destination.
    - `emit-let` / `emit-with` adopt from the boxed value
      (`box-taint-source`): `(let (b:(dyn &P) p))` takes `&p`'s frame taint,
      which the by-value `p` does not carry.
    - Return (explicit and implicit) and the `defvar` initializer refuse it
      with the existing messages.
  - No drop: `ensure-box-drop-fn` and `boxedfn-drop-target` return without
    effect for a borrowed box, so `with` arms nothing.

  Deviations and holes:
  - A struct literal does not merge its fields' taint (frame-storage-escape.md
    §7), so `(Holder &p)` over a local escapes through a by-value return.
    BD-2 refuses the one `defvar` shape of this; the rest is filed in
    deferred/overview.md.
  - A borrowing box loaded through a `&(dyn &P)` carries no taint. This is the
    same untracked load boundary as for any pointer.
  - Arity messages from the drained annotation spell `(dyn Iterator)`, not
    `(dyn &Iterator)`: `DynAnnot` has no borrowed flag. Fixed in DP-6.
  - `type-display` still prints `__dynref.Show` in the messages that use it
    (`=` refusal). Fixed in DP-6.

  Tests: three suite tests (`bd1-borrow-with-drop`, `bd1-borrow-sources`,
  `bd1-borrow-parametric`) and nine fixtures (`bd1-*`). All twelve fail on the
  DP-5 compiler. Totals: 1403 tests, 1398 pass, the 5 known suite-target
  failures. Byte-identical; `bootstrap`, `check-headers`, `abi-test`,
  `avr-test` pass.
- **BD-2 — constants, headers, `.nuch`** (§4.6): constant folding of
  `&global` into a borrowing box, the C typedefs for both kinds (fixing probe
  12), header emission of borrowing-box signatures, the `.nuch` round trip.
  *Gate:* `(defvar h:Holder (Holder &g))` with a `(dyn &Show)` field is a
  constant global; the generated header's struct `sizeof` agrees with the
  compiler's (as `s21-cheader-union-arm-declarator` checks unions);
  `check-headers` clean.
  **Built 2026-10-10.**
  - Constants (`src/nucleusc.nuc`).
    - `dyn-borrow-const-target` accepts `&g` or a bare `g` naming a non-const
      global struct that is not itself a box.
    - `dyn-borrow-const-ir` renders `{ ptr @g, ptr @__vt.T.P }` after
      `dyn-admit`.
    - `defvar-const-init-ir` answers a top-level borrowing box. A
      `const-lit-boxes?` field folds rather than sending the struct literal to
      startup, which is DP-4's path.
    - The aggregate is streamed in one line, so `defvar-const-vtables` emits
      every vtable it needs first, still inside the global's L6 span. The walk
      covers `defvar`, `defconst`, struct literals, `(array T N)` and the
      `ptr:T` backing global. `type-embeds-dynref?` gates it.
    - A borrowing field that does not fold still goes to startup (a copy of
      another box global, a view of an owning one). A struct literal there is
      refused, because it would borrow the init function's frame.
  - Headers (`src/cheader.nuc`).
    - `cheader-inst-entry` gives each box StructDef a guarded
      `typedef struct nuc_dyn_<P> { void* data; const void* vtable; }`, or
      `nuc_dynref_<P>` for the borrowing kind. `<P>` is the C-sanitized
      remainder of the StructDef name, e.g. `nuc_dynref_hdr_Show` or
      `nuc_dynref_Src_i64`.
    - `type-node-to-c` and `cheader-type-c` route a box there. Probe 12's
      `void*` field is now `struct nuc_dyn_Show o;`.
  - `cheader-erased-class` splits L8's predicate.
    - `cheader-mentions-closure` still excludes closures, `BoxedFn` and the
      owning box from signatures and globals.
    - A borrowing box is exported, and its definition-site warning is gone.
    - `cheader-scan-type-node` still renders an owning-box field so that its
      typedef precedes the struct. The `defvar` scan skips the owning globals
      the emitter omits.
    - `cheader-defvar-type-ok` admits a `dyn` cell.
  - `.nuch`: no change was needed. BD-1's reader of `(dyn (ref P))` is the
    whole round trip: the writer prints the node as `(dyn (ref Show))` and
    `(dyn (ref (Src i32)))`.

  Tests:
  - Suite tests: `bd2-const-global` (IR lines; no `__nucleus_init`),
    `bd2-cheader-box-typedefs` (C `sizeof(Bd2H)` 40 = Nucleus 40; C calls a
    borrowing-box signature with a box returned from Nucleus and with the
    exported global), `bd2-nuch-round-trip`.
  - Fixtures: `bd2-literal-field` and `bd2-const-nonconforming`.
  - Three fail on the BD-1 compiler. Two pass on it by design:
    - `bd2-nuch-round-trip`, because the round trip came with BD-1's reader;
    - `bd2-const-nonconforming`, which BD-1 refuses at startup with the same
      message and line.

    Both fail on the DP-5 compiler.
  - Totals: 1408 tests, 1403 pass, the 5 known failures. Byte-identical
    against both the BD-1 and the DP-5 compilers; `bootstrap`, `check-headers`
    (91 headers, no change), `abi-test`, `avr-test` pass.

  Open: a `BoxedFn` field is still `void*` in a header, probe 12's bug for the
  closure box (deferred/overview.md). A CT body that reads a constant box
  global, whose vtable was emitted earlier, finds the vtable outside the
  global's span. The mirror then refuses as it does for any unrecorded name.
- **DP-6 — docs and close-out.**
  - docs/generics.md: replace "v1 scope limits" with the four rules, the slot
    model, and the borrowing form. Its "the parser rejects them" claim about
    `Self` is wrong today. Its worked example still uses `vector-push` and the
    old protocol syntax.
  - `type-display` of a box prints `(dyn P)` / `(dyn &P)`, not `__dyn.P`.
  - Examples: `examples/dyn-multi.nuc`, `examples/dyn-parametric.nuc`,
    `examples/dyn-borrow.nuc`.
  - progress.md.

  **Built 2026-10-10.**
  - `type-display`. `sdef-display` (`src/abi.nuc`) asks `dyn-sdef-spelling`
    for a StructDef named `__dyn…`, and that answers `box-spelling` of the
    memo entry. Every message that goes through either function now spells
    `(dyn &Show)` or `(dyn (Iterator i32))`, and so does `type-display-node`,
    so `struct-fields` gives a box field as a readable `(dyn …)` form.
    - The lookup lives in `src/nucleusc.nuc`, not beside `dyn-entry-of`: `abi.nuc`
      is emitted before `union-registry.nuc` starts, so it cannot call into it,
      while the entry file's definitions are prescanned first.
    - No fixture asserted the old text. Every `__dyn` in the tests is IR.
  - Arity. `DynAnnot.borrowed` is threaded through `dyn-annot-record`,
    `dyn-annot-check`, `dyn-require-arity` and `dyn-require-boxable`.
    `(dyn &Iterator)` and `(dyn &(Iterator i32 i64))` are refused with the
    `&`, and the hint reads `write (dyn &(Iterator ...))`.
  - Found by the new display: the operator refusal's note on a box suggested
    `(extend (dyn &Show) Eq)`, which `extend` refuses (`'dyn' is not a struct
    or union template`). `operator-refusal` now suggests only the method for a
    box. A user `=` over boxes works.
  - Docs.
    - The type-erasure section of `docs/generics.md` is rewritten: the slot
      model, the four rules, coercion positions, admission below the `extend`,
      `&box` receivers, parametric boxes, the borrowing box with its lifetime,
      drop and constant rules, one Limits list, and one C-header section.
    - Both worked examples (`BoxedFn` and `dyn`) are in current syntax and were
      compiled and run.
    - Stale "`(dyn …)` is deferred / not implemented" lines are fixed in
      `docs/builtins.md` and `docs/generics.md`, `Writer`'s "single-method, so
      it can be erased" in `docs/strings.md`, and the generics row and
      zero-cost bullet in `docs/index.md`.
    - The doc's "the parser rejects them" claim about `Self` was already gone.
  - Examples, each with a golden in `tests/expected/`, which `register-golden`
    discovers:
    - `dyn-multi.nuc`: a four-method protocol with one method that is not
      dyn-callable, and struct arguments and returns through the box;
    - `dyn-parametric.nuc`: a `(Vector (dyn (Iterator i32)))` over three
      conformers;
    - `dyn-borrow.nuc`: a `(dyn &P)` over a by-value local, a `Drop` value
      (dropped once), a view of an owning box, and a constant over a global.

  Tests: four fixtures (`dp6-display-borrow`, `dp6-display-application`,
  `dp6-borrow-missing-arguments`, `dp6-borrow-extra-arguments`) and the suite
  test `dp6-box-eq-note`, which also requires that no diagnostic says `__dyn`
  or `(extend (dyn`. All five fail on the BD-2 compiler. The three goldens pass
  on it too; they are examples, not regression tests. Totals: 1416 tests, 1411
  pass, the 5 known suite-target failures. Byte-identical: the new compiler's IR equals the
  BD-2 compiler's for both the pre-change and the new source. `bootstrap`,
  `check-headers` (91 headers, no change), `abi-test` and `avr-test` pass.

  Open, for AL-5: the DP-5 alignment note and BD-2's `BoxedFn`-field and
  CT-mirror notes stand. An `extend` whose subject is a box is refused, which
  is consistent with Q8's deferral.

AL-5 itself, and the measurement it is gated on, are in
[overview.md](overview.md) §9.

## 6. Clients

- **`Alloc`** (AL-5): `(dyn &Allocator)` replaces the tagged handle and the
  `CUSTOM` table. A user allocator needs no table and no adapter functions.
- **`Writer`** ([future/native-io.md](../future/native-io.md)): Option B adds
  `flush` to the protocol. A borrowing `(dyn &Writer)` also fits a formatter
  that writes to a stream it does not own, which is the common case.
- **Heterogeneous iteration**: `(Vector (dyn (Iterator T)))`.
- **Computed/reflective field access** (callable-values.md) remains a future
  client.

## 7. Questions for a ruling

**Ruled 2026-10-10: every question as recommended.** The phases above already
assume these answers.

The questions as they were put:

- **Q1. Spelling.** `(dyn &P)` for the borrowing box, as AL-5 already writes
  it? Alternatives: `(dyn-ref P)`, or flipping the default so `(dyn P)`
  borrows and the owning box is `(Box (dyn P))`. *Recommended:* `(dyn &P)`
  (§4.1). It changes nothing that exists, and the owning box keeps its name.
- **Q2. `handle`.** Remove it from `Allocator` and keep it as a library function
  over the coercion, or keep it as a protocol method returning the box?
  *Recommended:* remove it (§4.7). It saves every allocator a method whose body
  is the coercion.
- **Q3. A zero `Alloc`.**
  - (a) No zero value: `(dyn &P)` is non-null like `&T`. `Arena` conforms to
    `Init`, `g-arena` gets a constant initializer (§4.6), and AL-5 starts with
    a census of every zero-filled `Alloc` that is used without `init`.
  - (b) Keep "zero is the heap": `alloc-allocate` and friends test the vtable
    word for null, and collections call them rather than the protocol
    methods. The cost is a branch per call, and `Alloc` stops being plainly a
    `(dyn &Allocator)`.

  *Recommended:* (a). It keeps the box's rule the same as `&T`'s. The
  convenience it removes is known in three places (`g-arena`, a zero `Arena`,
  a zero `Tracking`); the census finds any others.
- **Q4. Zeroed memory.** Add `allocate-zeroed` to `Allocator` (§4.7), or have
  `new` always `memset` (undoing `ce2084a`'s fix for arenas)? *Recommended:*
  add the method. It is Rust's shape, and `calloc` is cheaper than
  `malloc` plus `memset` for the heap.
- **Q5. Owning a `Drop` value boxed from a reference.** Refuse it (probe 7
  drops twice), or keep the bitwise copy? *Recommended:* refuse, and name
  `(dyn &P)` in the message.
- **Q6. Vtable layout.** Keep the append layout `{m0, drop, m1, …}` or move
  to a fixed header `{drop, m0, m1, …}`? *Recommended:* keep the append
  layout. Nothing gates either way. A header only pays off if owning boxes
  later store size and alignment for an allocator, and that is a TE deferral
  with no client.
- **Q7. Header emission.** Emit `(dyn &P)` signatures and both kinds' struct
  fields to C as an opaque two-pointer struct (§4.6)? *Recommended:* yes.
  Otherwise AL-5 removes every `init` and every function taking an `Alloc`
  from the generated headers, and every collection struct keeps today's
  eight-byte `void*` field for a sixteen-byte handle.
- **Q8. A box conforming to its own protocol** (`(dyn P)` satisfying
  `:where (P T)`; `conforms?`). Build it now or defer? *Recommended:* defer.
  `&box` dispatch (DP-2) covers the calls AL-5 makes, and synthesized
  forwarders are worklist work with no client yet.
- **Q9. Equality.** No `=` on either box kind? *Recommended:* none (§4.5).
