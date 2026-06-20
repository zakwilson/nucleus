# Strings

- C strings (`CStr`) were enough to bootstrap and must stay for interop, but are not
  a reasonable default in 2026.
- `String` is **UTF-8 and memory-safe**, plausibly built on `Vector` (`Vector u8`).
- Indexing is **not** O(1) random access over codepoints
  `Seq`. (This is why `Str` does not blanket-`extend Seq`.)
- Switching **string literals** to `String` should come *after* collections are
  stable — the compiler uses `CStr` heavily and that migration is part of the
  end-of-stage compiler-adoption step, not the start.

Robot claims `Str` does not blanket-`extend Seq` because indexing is not O(1). O(1) indexing is **not** part of `Seq`'s contract, only `Vector`'s; indexed access must be possible for `Seq`, not necessarily fast.

Robot proposed

>  `String` exposes **byte and codepoint iterators** rather than pretending to be a random-access

That's fine, but a programmer can still request the nth Char if they're willing to wait for it.

---

## Robot — design evaluation

The skeleton is right (UTF-8, byte-vector substrate on the existing `StrView`,
iterators over random access, `CStr` kept for interop). Five structural points
should be settled before any code, because they change the *shape* of the
protocols, not just their contents.

### 1. `Str` must not `extend Seq`/`Coll`/`Drop` — it is a *read-only* contract

The "Extends protocols: Coll, Seq, Drop" line under **Str protocol** below is the
one thing I'd reverse. The reason is **not** the O(1) argument (the Designer is
right that `Seq` never promised O(1)); it is **mutation and ownership**:

- `Seq` requires `append`/`insert`/`conj` — *mutating* adds. `CStr` is an
  immutable NUL-terminated literal and `StrView` is a borrowed view; neither can
  implement them. A protocol every string conforms to cannot demand mutation.
- `Coll` requires `conj` (mutating) and `count`, and `Coll` **extends `Eq`**.
  Same mutation problem, plus `count` is *ambiguous* for a string (bytes?
  codepoints? graphemes?) — see point 4.
- `Drop` marks a type as **owning** and feeds the Stage 10 escape/taint analysis.
  `CStr`/`StrView` own nothing; forcing them to conform to `Drop` would either be a
  lie to the lifetime analysis or a meaningless no-op requirement.

So **`Str` should extend only `Eq`** (content comparison — `CStr` already has it,
`StrView` already has it). Mutation lives on the concrete owning `String` (and,
if wanted, a dedicated mutator protocol), **not** on the shared read surface. This
mirrors Rust's split exactly: `&str` (≈ our `Str`/`StrView`) is read-only;
`String` adds the owning/mutating API.

### 2. Self-derived protocol returns are now a *choice*, not a barrier (associated types)

The old rule — "a protocol method can't return a `Self`-derived type, which is
why `iter` is not in `Coll`" (`lib/coll.nuc`) — **no longer holds**: the
associated-types work (A0–A2) dissolves it. A `Self`-derived return just needs a
*name*; add it as a protocol parameter and bind it per conformer, exactly as
`(Iterator E)` already names its element type:

```lisp
(defprotocol (Coll E It)                 ; It = the associated iterator type
  (iter:It ((self (ref Self)))))
(extend (Vector T) (Coll T (VecIter T))) ; It bound to (VecIter T)
```

A generic consumer recovers it via the now-implemented `&where`-on-parametric-
protocol shape: `&where ((Coll E It) C) ((Iterator E) It)`. Because generic
bodies are **monomorphized, then resolved on concrete types** (`generic-resolve`),
`(iter c)` resolves to the concrete `VecIter.i32`-returning method at stamp time;
no new return-type-inference pass is required. (`assoc-types.md` §5 already flags
the identical `get`/`keys`/`vals`-on-`Assoc` uplift as "mechanically possible …
its own task.")

So the protocol/standalone line is now a **tradeoff**: each `Self`-derived return
costs one associated param + one extra `&where` bound at every consumer. That is a
good trade for the **one or two canonical iterators** (`chars`, `bytes`) — lifting
them buys uniform generic iteration over any string — and a poor one for
`split`/`lines`/`trim`/`to-owned`, which return *different* types per pattern or
variant. **Recommendation:** lift `chars`/`bytes` into the protocols (associated
iterator types); keep the long tail standalone.

**Spike result (confirmed).** `examples/assoc-iter-return.nuc` exercises the one
genuinely-new requirement: a protocol method `mk-iter:It` returning a bare
associated type, with a generic consumer whose constraints are *interdependent
through the conforming variable* —

```lisp
(defn count-coll:i32 ((c (ref C))
                      &where ((IterColl It) C)      ; recover It from C
                             ((Iterator E) It))     ; It (recovered) is itself
                                                    ; the conforming var; recover E
  (let (it:It (mk-iter c) ...)                      ; recovered assoc type as a value
    ... (next (addr-of it)) ...))                   ; ... then used as a receiver
```

The existing MapIter/reduce examples thread a recovered tyvar through constraint
*args*, but never make a recovered tyvar the *conforming variable* of a later
constraint — that is what `chars` (returns `CharI`) → `((Iterator Char) CharI)`
needs, and it **compiles, runs (`count=5`), and the bootstrap stays
byte-identical**. The `chars`/`bytes` protocol-method form is therefore safe to
commit; no fallback to standalone functions is needed.

### 3. Three layers, not two: `ByteStr` ⊂ what's cheap, `Str` ⊂ what's encoding-aware

The doc already gestures at this; make it explicit and put each op in exactly one
layer by **what it costs and what it knows**:

- **`ByteStr`** — the byte substrate. Cheap, exact, encoding-agnostic. Byte length,
  byte-at, byte-range sub-slice (→ `StrView`), byte-substring search (→ byte
  index), whole-thing-as-`StrView`. Natural conformers: `StrView`, `String`, and
  `CStr` (with the caveat that its byte length is an O(n) `strlen`, and it cannot
  carry embedded NULs).
- **`Str`** — the codepoint layer on top. Some ops O(n): codepoint count, nth
  codepoint, prefix/suffix/contains by `Char`/substring/predicate, trim. Conformers:
  `CStr`, `StrView`, `String`.
- **`String`** — the concrete owning type: `ByteStr` + `Str` + mutation + `Drop` +
  the allocator-stored-field model from `collections.md`.

This answers the doc's open question **"can `CStr` extend `ByteStr`?" → yes**, with
the documented property that `byte-len` is O(n) for `CStr` (no stored length) and
that `CStr` cannot represent embedded NULs (so `byte-at`/`sub-bytes` past a NUL are
undefined for it). That is a property of the type, like its O(n) length — not a
reason to exclude it.

### 4. Pin down `count`/length semantics now (Rust's rule)

A bare `count` on a string is a trap. Adopt Rust's convention explicitly:

- **byte length** is the cheap, default size — name it `byte-len`, O(1) for
  `StrView`/`String`.
- **codepoint count** is explicit and advertised O(n) — `char-count`.

Never expose an unqualified `count` that hides which one it is. (This is also why
`String` should *not* satisfy `Coll.count` — there is no single right answer.)

### 5. String literals should become a *borrowed view*, not an owned `String`

The doc (and `collections.md`) say "switch string literals to `String`." I'd
push back hard: an owned `String` per literal means a heap allocation + an owner +
`Drop` + escape analysis for every `"…"`. The compiler is saturated with literals
like `"error: %s\n"` that are static, borrowed, and never mutated; Rust keeps
these as `&'static str`, **not** `String`, for exactly this reason. The right
successor to a literal is a **borrowed static `StrView`** over the program's
constant bytes — zero allocation, the full safe read API, and it drops to nothing.
`String` is for text you *build* or *own*, produced explicitly. This reframes the
end-of-stage migration from "literals → `String`" to "literals → static
`StrView`," which is both safer and far less disruptive to the compiler.

---

## Str protocol

The language provides a default string type, but that won't be the best
representation for every use case. The `Str` protocol provides a common,
**read-only** interface for operations all strings — `CStr`, `StrView`, `String`,
and types not implemented here — should support.

Methods like `split` that match a character or substring should take `Str`,
`Char`, or `Call`, similar to Rust. (`split` itself is a *standalone* multimethod,
not a protocol method — its result is a `Self`-derived `SplitIter`; see eval §2.)

**Extends:** `Eq` only (revised — see eval §1; *not* `Coll`/`Seq`/`Drop`, and
*not* `Ord` — `Ord` lives on the concrete `String`/`StrView`, decided Q-ord).

The protocol carries its codepoint-iterator type as an associated parameter
(`CharI`), so `chars` can be a real protocol method (eval §2):

```lisp
(defprotocol (Str CharI)            ; CharI = this string's char-iterator type
  ; Codepoint count. O(n): walks the UTF-8 bytes counting lead bytes.
  (char-count:usize ((self (ref Self))))
  ; Emptiness — cheap (byte-len == 0), no codepoint walk.
  (str-empty?:i32 ((self (ref Self))))
  ; nth codepoint, O(n). Errors with `str-index-out-of-bounds` when i is past
  ; the end (decided Q-bounds: indexing failures are errors, not Maybe).
  (char-at:!Char ((self (ref Self)) i:usize))
  ; Codepoint iterator — LIFTED into the protocol (eval §2). The returned CharI
  ; conforms to (Iterator Char), so map/filter/reduce/doseq/into work over it.
  (chars:CharI ((self (ref Self))))
  ; Pattern tests. Pattern given as a borrowed view; Char/predicate variants
  ; are multimethod overloads (see standalone list). Return 1/0.
  (starts-with?:i32 ((self (ref Self)) (prefix (ref StrView))))
  (ends-with?:i32   ((self (ref Self)) (suffix (ref StrView))))
  (contains-str?:i32 ((self (ref Self)) (needle (ref StrView)))))
```

Conformers bind `CharI` at the `extend` site:
`(extend String (Str StringCharIter))`, `(extend StrView (Str ViewCharIter))`, etc.

### Standalone (pattern multimethods / per-variant `Self`-derived returns)

```lisp
; Search returning a position — first BYTE index of a match, or none. `none` is
; a legitimate "not found", not an error, so this stays Maybe (not !usize).
; Multimethod over the pattern: (ref StrView) | Char | a Call predicate.
(defn (str-find (Maybe usize)) ((self (ref Self)) (pat …)))

; Trimming — returns a borrowed sub-view (no allocation). ASCII whitespace for
; the first pass (decided Q-case); full Unicode White_Space → stage888.
(defn trim:StrView       ((self (ref Self))))
(defn trim-start:StrView ((self (ref Self))))
(defn trim-end:StrView   ((self (ref Self))))

; Splitting / lines — lazy, yield borrowed StrViews, no intermediate Vector
; (matches the M2 lazy-iterator story; materialize with `into`). Kept standalone:
; split returns a different SplitIter per pattern variant, so lifting it would
; cost an associated param per variant for no real gain (eval §2).
(defn split:SplitIter ((self (ref Self)) (pat …)))   ; multimethod on pat
(defn lines:LineIter  ((self (ref Self))))

; parse — FromStr with the target type passed explicitly (decided Q-parse).
(defn (parse !T) (ty (s (ref Self))) &where ((FromStr T) ty))
```

`char-at` and `chars` are how the "nth Char if willing to wait" / "byte and
codepoint iterators" requirements are met without pretending to be a random-access
`Seq`.

### parse — decided (Q-parse)

Rust's `parse` is `FromStr::from_str` — the trait lives on the **target** type, not
on `Str`. Same shape here:

- A `FromStr` protocol, conformed by each parseable type, parameterized by the
  produced type. **The numeric libs implement it for the builtins** (`i32`/`i64`/
  `f64`/…) so they ship with the conformances.
- `parse` is a generic over it. **The target type is an explicit argument**
  (`(parse i32 s) → !i32`), *not* inferred from the return position — return-only
  tyvars need `dyn`, deferred (`assoc-types.md` §3.4). Mirrors `into (Vector i32)`.
- A parse failure is an **error** (`!T`), consistent with the error-handling
  decision below. No ad-hoc `(Valid T)` needed — a clean protocol works.

## ByteStr protocol

Describes functionality strings built on top of a `Seq` of bytes can support.
Operations that return or take a **byte index** belong here. This is the
encoding-agnostic byte substrate; it sits *below* `Str` (eval §3).

### Proposed protocol methods

```lisp
(defprotocol (ByteStr ByteI)        ; ByteI = this string's byte-iterator type
  ; Byte length. O(1) for StrView/String (stored len); O(n) strlen for CStr.
  (byte-len:usize ((self (ref Self))))
  ; i-th byte, O(1). Errors `str-index-out-of-bounds` when i >= byte-len
  ; (decided Q-bounds).
  (byte-at:!ui8 ((self (ref Self)) i:usize))
  ; Byte iterator — LIFTED into the protocol (eval §2). The returned ByteI
  ; conforms to (Iterator ui8).
  (bytes:ByteI ((self (ref Self))))
  ; Borrow the whole thing as a StrView VALUE (two words) — the bridge to
  ; every StrView byte op (strview-eq / strview-hash / …). Expressible because
  ; StrView is a fixed, non-Self type.
  (as-view:StrView ((self (ref Self))))
  ; Sub-slice by byte range [start,end) as a borrowed StrView (no copy).
  ; Two distinct errors (decided Q-bounds): `str-index-out-of-bounds` when the
  ; range is past the end, `invalid-char-boundary` when an endpoint falls
  ; mid-codepoint.
  (sub-bytes:!StrView ((self (ref Self)) start:usize end:usize))
  ; First byte index of a byte-substring, or none (not-found is legitimate).
  ((byte-find (Maybe usize)) ((self (ref Self)) (needle (ref StrView))))) 
```

`as-view` is the workhorse: it lets any `ByteStr` reuse the entire `StrView`
byte-layer (equality, hashing, the `CStr` bridge) that already exists, instead of
re-implementing it per type.

**Open question (answered):** *can `CStr` extend `ByteStr`?* **Yes** — with the
documented caveats that its `byte-len` is O(n) and it cannot model embedded NULs
(eval §3).

## Char types

`Char` is a **32-bit Unicode scalar value**, like Rust (a codepoint that is *not* a
surrogate — i.e. `0..=0x10FFFF` minus `0xD800..=0xDFFF`). "Character" here means
**codepoint, not grapheme cluster**; grapheme segmentation is a future library
(open question **Q-grapheme**).

**Representation — decided (Q-char-repr): a new built-in distinct scalar.** `Char`
is a compiler-level distinct scalar over `ui32`, the same kind of built-in distinct
type `CStr` already is (not a one-field `defstruct`, which would carry struct ABI
and have no literal form). This gives `=`/`!=` dispatch on `Char` and `Char`-vs-int
overloading. Implied prerequisite work, scoped as its own task ahead of the
`String` library (the way `usize`/`ssize` preceded the collections):

- the built-in distinct scalar `Char` over `ui32` (with the surrogate-excluded
  scalar-value range as its validity invariant),
- reader support for char literals — **syntax still open** (`\a`, `\newline`,
  `\u{1F600}`?); the representation is decided, the literal spelling is the one
  remaining sub-question (Q-char-literal).

### Proposed Char protocol / functions

`Char` provides UTF-8 encode/decode plus classification. (UTF-16 is deferred to
stage888 — decided Q-utf16.)

```lisp
; The decode result is a small struct (decided Q-decode-shape): (Maybe Char)
; alone loses the byte count, and an invalid lead/continuation byte must be
; distinguishable from end-of-input.
(defstruct DecodeResult
  ch:Char          ; the decoded codepoint (valid only when ok = 1)
  nbytes:usize     ; bytes consumed (1..4)
  ok:i32)          ; 1 = decoded, 0 = invalid/truncated UTF-8

; --- Encoding (UTF-8) ---
; Bytes needed to encode this codepoint: 1..4.
(defn char-utf8-len:usize ((c Char)))
; Encode into a caller buffer; returns bytes written (1..4).
(defn char-encode-utf8:usize ((c Char) (buf (ptr ui8))))
; Decode one codepoint from a byte pointer + remaining length.
(defn (char-decode-utf8 DecodeResult) ((p (ptr ui8)) (len usize)))

; --- Conversion ---
(defn char-to-u32:ui32 ((c Char)))
; Validate scalar-value range and reject surrogates; errors `invalid-codepoint`.
(defn char-from-u32:!Char ((n ui32)))

; --- Classification (ASCII-total for the first pass, decided Q-case; full
;     Unicode tables → stage888) ---
(defn char-is-ascii?:i32      ((c Char)))
(defn char-is-digit?:i32      ((c Char)))   ; ASCII 0-9
(defn char-is-alpha?:i32      ((c Char)))   ; ASCII a-zA-Z
(defn char-is-alnum?:i32      ((c Char)))
(defn char-is-whitespace?:i32 ((c Char)))   ; ASCII whitespace
(defn char-ascii-upper:Char   ((c Char)))   ; simple ASCII case, total
(defn char-ascii-lower:Char   ((c Char)))
```

## String implementation

### Selected implementaiton: thin wrapper over byte vector

Basically Rust's approach. A `String` is a vector of bytes with separate iterators
to produce bytes and characters. Byte index is O(1), but character index requires
iterating from the beginning.

**Make "thin wrapper over `Vector ui8`" literal.** Define

```lisp
(defstruct String bytes:(Vector ui8))
```

and get growth, capacity ops, the stored `AllocHandle`, and `Drop` *for free* by
delegating to the wrapped `Vector` (its `Drop` runs the buffer free; `String`'s
`Drop` just drops `bytes`). This inherits the whole `collections.md` memory model
(explicit-allocator constructors with a libc default, escape/taint analysis
preventing an owned `String` from leaking) rather than re-deriving it.

### Proposed `String` methods (concrete owning type)

```lisp
; --- Construction (allocator: explicit or libc default, per collections.md) ---
(defn string-new:String ())
(defn string-new-alloc:String ((a AllocHandle)))
(defn string-with-capacity:String (n:usize))
; Validating constructors (decided Q-validate): they CHECK UTF-8 well-formedness
; and return !String, so a String is always valid by construction (memory-safe
; default). They copy the bytes.
(defn string-from-cstr:!String ((cs CStr)))
(defn string-from-view:!String ((sv (ref StrView))))
; Escape hatch (decided Q-validate): trusts the caller, no validation. Kept for
; hot paths over known-good bytes. REMOVING it is deferred to a future `unsafe/`
; sub-library — blocked on a module/namespace system (stage888 "unsafe lexical
; block / namespaces"). Until then it lives here by naming convention.
(defn string-from-cstr-unchecked:String ((cs CStr)))

; --- Mutation (owning — NOT in the shared Str protocol; eval §1) ---
(defn push-char:void ((self (ref String)) (c Char)))      ; UTF-8 encode + append; Char is always valid
(defn push-str:!void ((self (ref String)) (s (ref StrView)))) ; validates the appended bytes
(defn (pop-char (Maybe Char)) ((self (ref String))))      ; remove last codepoint; none if empty (legit)
(defn clear:void    ((self (ref String))))                ; len←0, keep capacity
(defn truncate:!void ((self (ref String)) byte-len:usize)) ; errs invalid-char-boundary / str-index-out-of-bounds
(defn reserve:void  ((self (ref String)) extra:usize))
(defn shrink-to-fit:void ((self (ref String))))

; --- Conformances ---
(extend String (ByteStr StringByteIter))
(extend String (Str StringCharIter))
(extend String Eq) (extend String Ord)   ; Ord = byte-lexicographic (decided Q-ord)
(extend String Hash) (extend String Drop)
; Coll/Seq intentionally NOT extended (count ambiguity + byte-vs-char conj;
; decided Q-coll-conformance: no for now). split/lines/trim stay standalone (eval §2).
```

`StrView` likewise conforms to `Eq`/`Ord` (byte-lexicographic) and to `Str`/
`ByteStr` (it is the borrowed, read-only string); `CStr` conforms to `Str` and
`ByteStr` (with O(n) `byte-len`, no embedded NULs).

### Errors used (Stage 10 `deferror`)

The error-handling decision (Q-bounds, Q-validate) needs four distinct errors so a
caller can `match`/`try` on the specific failure:

```lisp
(deferror str-index-out-of-bounds "string index out of bounds")
(deferror invalid-char-boundary   "byte offset is not a UTF-8 codepoint boundary")
(deferror invalid-utf8            "bytes are not valid UTF-8")
(deferror invalid-codepoint       "value is not a Unicode scalar value")
```

### Rejected options

* Sparse index: The previous idea becomes a BaseString type and the default String builds on top of it with a sparse index to allow indexed access with good performance with small storage overhead. This could be a useful type, but overhead like that should be opt-in.
* Fixed-width encoding - more or less UTF-32. Up to 4x space penalty. If someone wants it, it wouldn't be hard to implement Str on (Vector Char).

## Decisions (resolved)

| Q | Decision |
|---|---|
| **Q-char-repr** | A new **built-in distinct scalar** `Char` over `ui32` (mirrors `CStr`). Its own prerequisite task, ahead of the `String` lib. |
| **Q-parse** | `FromStr` protocol with the **target type as an explicit argument** (`(parse i32 s) → !i32`); the **numeric libs implement it for the builtins**. |
| **Q-bounds** | **Error-handling**, not panic/`Maybe`. Out-of-bounds and invalid-boundary are **separate errors** (`str-index-out-of-bounds`, `invalid-char-boundary`); the *at* and slice ops return `!T`. |
| **Q-utf16** | **Defer** UTF-16 encode/decode → stage888. UTF-8 is the must-have. |
| **Q-ord** | `String`/`StrView` are **`Ord`** (byte-lexicographic); the `Str` *protocol* is **not** `Ord`. |
| **Q-validate** | **Validate** UTF-8; constructors/mutators return `!String`/`!void` (`invalid-utf8`). Ship an `*-unchecked` **escape hatch**; *removing* it is deferred to a future `unsafe/` sub-library (blocked on modules/namespaces — stage888). |
| **Q-grapheme** | "character" = **codepoint** (Rust's model); grapheme segmentation out of scope. |
| **Q-case** | **ASCII** `upcase`/`downcase` for the first pass; full Unicode case → stage888. |
| **Q-decode-shape** | `char-decode-utf8` returns a **small `DecodeResult` struct** (`ch`/`nbytes`/`ok`). |
| **Q-coll-conformance** | `String` does **not** conform to `Coll`/`Seq` for now. Uniform `into`/`doseq` comes via the `chars`/`bytes` iterators instead. |

## Open questions (still to settle)

- **Q-char-literal — decided.** Char-literal syntax is `\a` for printable scalars,
  `\newline` (and the other named control codes) for named ones, and `\u{1F600}`
  for an explicit codepoint. Backslash-led, so it collides with neither keywords
  (leading `:`) nor strings (`"`). Reader + lexer work, scoped with the built-in
  `Char` scalar (Q-char-repr).

- **Q-method-uplift-spike — done (this phase).** Lifting `chars`/`bytes` into the
  protocols (associated iterator types, eval §2) relies on a protocol method whose
  return is a bare associated type that is then itself a *receiver* (`next` on the
  recovered iterator). Confirmed by `examples/assoc-iter-return.nuc` (see the spike
  result recorded inline at eval §2). The protocol-method form for `chars`/`bytes`
  is therefore safe to commit.

## Deferred

- **Full Unicode case mapping / folding** (`upcase`/`downcase` beyond ASCII) — needs
  Unicode tables; ASCII-only ships first. **Noted in stage888** (Q-case).
- **UTF-16 encode/decode** — no concrete consumer for a UTF-8 language. **Noted in
  stage888** (Q-utf16).
- **Grapheme-cluster segmentation** and normalization (NFC/NFD) — future library
  (Q-grapheme).
- **Linguistic collation / locale-aware ordering** — byte-lexicographic `Ord` only
  (Q-ord).
- **Sparse-index and fixed-width (`Vector Char`) string representations** — opt-in
  alternatives, not the default (Rejected options above).
- **String literal → static `StrView` migration** — end-of-stage compiler-adoption
  step, after the types are stable (eval §5).
