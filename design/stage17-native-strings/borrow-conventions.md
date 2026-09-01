# Borrow conventions: by-value producers, by-reference consumers

Status: **open decision**, raised by Stage 17 A2/A3, wanted before B1.
Register entries: [library-gaps.md](library-gaps.md) #18, #24, #25.

---

## 1. The observation

`strview-from-cstr`, `strview-sub-bytes`, `strview-trim*` and
`split-iter-next` return `StrView` **by value**. `strview-byte-len`,
`strview-eq`, `strview-hash`, `strview-starts-with`, `str-empty?` and every
`ByteStr`/`Str` method take **`(ref StrView)`**. So the natural code is

```lisp
(let (av:StrView (strview-from-cstr "hello")
      a:ptr:StrView (addr-of av))
  (strview-byte-len a))
```

— a two-line binding for one value, repeated at every site. A2 hit it in six
examples; A3 hit it again when `SplitIter` began yielding segments by value.
The compiler conversion will hit it thousands of times.

## 2. Why it is not a style inconsistency

The tempting reading is that someone was careless and the library needs a
consistent convention applied. That reading is wrong in both directions.

**The producer side must be by value.** `StrView` is `{data, len}` — two words,
classified DIRECT by `abi-classify`, so it returns in two registers. The
alternatives are the heap wrapper (a `malloc` per FFI crossing, which is exactly
the defect A2 deleted — #7) or an out-parameter, which reintroduces the
`alloca`-then-`set!`-twice pattern that B0's `strview` constructor deleted (#8).
Both are worse than what they would replace.

**The consumer side must be by reference.** `ByteStr` and `Str` declare their
receivers `((self (ref Self)))`, and `Self` binds to **both** `StrView` and
`String`. One protocol method cannot be by-value for one conformer and
by-reference for another. And `String` cannot be the by-value one: it wraps a
`Vector ui8` — data, len, cap, and an `AllocHandle` — so it is well past the
two-register window, and it has `Drop`, which makes a by-value pass a *move*.
A move is the wrong semantics for a read-only query like `byte-len`, and it
fights the Drop protocol directly.

So the seam is **structural**. Neither uniform convention is reachable, and the
real question is not *which convention* but **who bridges the seam: the call
site, or the compiler.**

### 2.1 The two uniform conventions, for the record

Both were considered and both fail, but each fails informatively.

**All by value** is genuinely attractive for `StrView` alone. Two words in two
registers is often *fewer* instructions than a reference — no store to a stack
slot in the caller, no load in the callee — and it composes directly with the
producers. The library is already half-committed: `Eq` and `Ord` on `StrView`
take it **by value** today, because the protocol shape is `(= (a:Self b:Self))`
(`lib/strview.nuc`, the Eq conformance note). It fails only on the shared
protocol surface, and only because `String` is on it.

**All by reference** has the stronger claim to being the existing convention —
every protocol receiver already is one, it works uniformly across sizes and
`Drop` types, and B1's `Writer`/`Fmt`/`ToStr` would inherit a single rule. It
fails because it is not the consumers that create the friction; it is the
*mismatch*. Making the convention uniformly by-reference means the producers
must hand back something addressable, and both ways of doing that are the
defects B0 just removed.

## 3. Option (c): the compiler bridges it

Half of this already exists. TC-3 target-typed materialization copies a struct
value into a stack temporary and stores its address, so

```lisp
(let (p:ptr:StrView (strview-from-cstr "x")) …)
```

is correct today — verified in the IR (`%tc3.mat.N = alloca %StrView` … `store
ptr %tc3.mat.N`). Member access auto-addresses too (#19). Only **argument
position** does not, and the reason it *looked* like it did was #25.

### 3.1 Precedent

Two families.

**Implicit only in receiver position.** Rust requires `f(&v)` for an ordinary
`&T` parameter but auto-refs the method receiver, so `v.len()` inserts the `&`.
Go does the same: `v.M()` with a pointer receiver is shorthand for `(&v).M()`,
but only when `v` is addressable. This is where Nucleus already is — not by
design, but the position is the same one Rust and Go argued their way to.

**Implicit at every parameter.** A C++ reference *is* "pointer parameter,
implicit address-of at the call site, implicit deref in the body". C# 7.2's `in`
is the sharpest precedent because it is a deliberate split: `in` needs no
call-site keyword, while `ref` and `out` still require one. Pascal's `var`,
Ada's parameter modes, Fortran, and D's `ref` all pass by reference with nothing
at the call site.

Zig is worth naming as a third answer: it does not put the distinction in
signatures at all for the read-only case. Parameters are immutable and the
compiler passes by reference when that is cheaper; pointers require `&`.

### 3.2 The line every one of them draws

| | lvalue (a local) | rvalue (a call result) |
|---|---|---|
| **read-only** (`const&`, `in`) | implicit | implicit, via a temporary |
| **mutating** (`T&`, `ref`, `inout`) | implicit in C++/Pascal/D; explicit in C#/Swift | **rejected everywhere** |

Nobody lets a mutating reference silently bind a temporary. C++ rejects
`T&` ← rvalue outright; C# requires `ref` at the call site; Swift requires `&`
for `inout`. Where C# *does* permit it (`in` with a non-lvalue) the known cost
is the defensive-copy footgun.

### 3.3 Why unrestricted option (c) is unsafe here

Nucleus's `(ref T)` sits on neither axis. `strview-byte-len` and `conj` are
spelled identically. So an unrestricted (c) would let

```lisp
(string-push-str (string-new) sv)
```

materialize a temporary `String`, append into it, and drop it — a write that
silently goes nowhere. That is the same class of defect as #25, which this stage
has just finished closing.

### 3.4 The safe subset: lvalue-only

Implicit address-of **when the argument is an addressable local**, never when it
is a call result or a literal. This covers the whole of #24's observed friction
— every instance is `(f local)` — and leaves the temporary-materializing case an
error, where the `(addr-of …)` the author must write is honest about what is
happening. It also keeps TC-3 the only place a temporary is materialized, which
is a far smaller thing to reason about than "any argument position might".

No type-system change. No `.nuch` churn. No bootstrap shim.

## 4. The other option: split `(ref T)`

Distinguish a read-only borrow from a mutable one. This is what makes the *full*
option (c) safe, but it is worth arguing on its own merits, because the
ergonomics alone would not justify it.

**It is the missing axis of a lattice that already exists.** Stage 10 built
`pkind-flow-check` (`src/type-utils.nuc:1184`) because nullability is a promise
a pointer parameter makes and an unchecked promise is a segfault. It runs on the
argument path at `src/nucleusc.nuc:6926` — three lines above the coercion that
caused #25. Mutability is the *other* promise a pointer parameter makes, and it
is untracked. This is not new infrastructure; it is a second bit riding a flow
check that already exists at the chokepoint that already exists.

**In this codebase it turns signatures into documentation.** `src/` is 40,712
lines of passing `Node`, `Scope`, `Type` and `StructDef` pointers around.
`(node-type n scope)` — does it mutate `scope`? Nothing in the signature says,
and the only way to find out is to read the body, transitively. That is the most
useful fact about a function in a compiler and it is invisible at every one of
those call sites. **This, not the `addr-of` noise, is the case for the change.**

**It makes conformances checkable.** `lib/string-protocols.nuc`'s header calls
`ByteStr` and `Str` "read-only string protocols" — the intent exists, in a
comment, where nothing enforces it. `Eq`'s `=`, `Hash`'s `hash` and `ByteStr`'s
`byte-len` cannot mutate; `Coll`'s `conj` must; all four are spelled
`(ref Self)`. Once split, a conformance that writes where the protocol promised
not to is a compile error — and B1–B4 are about to add four libraries' worth of
protocol surface.

**It would let the compiler emit parameter attributes.** A read-only borrow is
`readonly` in LLVM IR. Today every `(ref T)` lowers to a bare `ptr` with nothing
attached, so LLVM must assume any call may write through any pointer argument.
Honest cost: the compiler emits no function or parameter attributes at all right
now — the same gap [avr-targets.md](../stage14/avr-targets.md) records as an AVR
blocker — so this is a real benefit sitting behind machinery that does not exist
yet, not a free one.

### 4.1 Making the sweep small

Keep `(ref T)` meaning the **read-only** borrow — the large majority — and give
the mutable one a distinct spelling. Then flipping the default and rebuilding
makes the *compiler* enumerate every mutator, which is the smaller set, with a
diagnostic at each. That is the shape of Stage 10's Phase F default flip, which
worked in this codebase. Bootstrap costs one shim generation, like `try-boot`
(conventions.md, "A form whose SHAPE depends on its operand's type").

Cost that does not go away: every `.nuch` and `.h` is regenerated, and every
protocol signature in `lib/` is re-stated. Pre-release, so allowed.

## 5. Recommendation

The options **compose** rather than compete.

1. **Lvalue-only implicit address-of, now.** Bridges the seam for every instance
   of #24 that actually occurs, costs no type-system change, and leaves the
   unsafe case an error.
2. **The `(ref T)` split, before B1 if at all.** Justified by §4 independent of
   this problem. B1–B4 add four libraries of protocol signatures; retrofitting
   them later doubles the sweep.
3. **Full option (c)** falls out of 2 for free, once mutation is something the
   type can refuse.

Doing 1 alone is coherent and cheap, and does not foreclose 2. Doing 2 for the
ergonomics alone is not worth it; doing it for signatures-as-documentation
across `src/` may well be.

Uniform by-value and uniform by-reference (§2.1) are **not** on this list. They
are not achievable, and the effort of attempting either is better spent on 1.
