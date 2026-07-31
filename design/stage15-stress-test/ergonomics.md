# W5 — Ergonomic gaps and the union crash

**Findings:** §1.1 (union with a function-pointer member segfaults the compiler),
§2.5 (`defn-` gives linkage but no name isolation), §4.3 (no unary `bit-not`),
§4.4 (no `\x` escapes), §3.7 (`defvar` cannot be typed `CStr`), §3.9
(`(array Struct …)` needs `deref` on each element), §3.10 (array-of-pointers local
binds as bare `ptr`).

A batch of independent, individually-small items. **They are independent — this is
the item to split across parallel subagents.** Sequence only where noted.

Ordered cheapest-first within the item.

---

## W5c — `defvar` typed `CStr` (§3.7) — small

**Status: done.** See the "W5c as built" section at the end of this document.
The line-0 half of the finding below had already been fixed by W4 and did not
reproduce; the fix uncovered a segfault the spec did not anticipate.

All three spellings fail: `(as CStr "")` → `init must be a literal`; `""` →
`string literal requires ptr type`; `null` → `null requires ptr type` (**at line
0**, cf. W4). No precedent exists in the compiler's own source — an untested
corner, not an intentional gap.

`CStr` and `ptr` are ABI-identical (`context/conventions.md`'s string-type
lattice), so the workaround is to declare `ptr` and `(as CStr …)` at the read
site. Make the direct spelling work: a `CStr`-typed `defvar` should accept a
string literal and `null`.

Note Stage 14 NS-3 flipped string literals to type as `StrView`, with `CStr`
reachable via `c"…"` — check how that interacts before assuming which literal form
should be accepted. This is the one W5 item with a live interaction with recent
work; read `design/stage14/native-strings.md` first.

*Accept:* `(defvar g:CStr null)` and `(defvar g:CStr c"lit")` compile; the line-0
diagnostic is gone either way (W4).

## W5d — array literal ergonomics (§3.9, §3.10) — small

**Status: done.** See the "W5d as built" section at the end of this document.
Both warts reproduced, but the surrounding behaviour did not match the finding:
§3.9 turned out to be a by-value-struct-slot gap that the *argument* position had
already closed (Stage 13 CE-3), so it was fixed once at the shared coercion
chokepoint rather than at the array literal; and §3.10 was narrower than stated
(the fully-annotated and the *unannotated* spellings both already worked, and the
failure is not specific to pointer elements). Fixing them exposed two
pre-existing `emit-zero-store` crashes on the same path.

Two independent warts:

* **§3.9** `(array StructType …)` cannot hold bare struct compound literals. A
  compound literal is alloca-backed and evaluates to `ptr:Struct`; the array's
  per-slot store has no auto-deref, so a bare `(StructName …)` element dies
  `array: type mismatch in positional initializer`. Every element must be wrapped
  `(deref (StructName …))`. Add the auto-deref at the array literal's coercion
  path — same-kind identity coercion already accepts the loaded struct value, so
  this is inserting one load, not new machinery.
  *This is load-bearing for generated tables*: it is how Doom's 967-row `states[]`
  is built (verified working at 1000-row scale, ~0.45 s compile). Do not regress
  that — it is the largest array literal any known program builds.
* **§3.10** `(let (a:ptr (array ptr …)) … (aref a i))` dies `aref: operand must be
  typed pointer` — an array-of-pointers local binds as bare `ptr`, requiring
  `(aref (unsafe/cast ptr:ptr a) i)`. Infer the element type from the array
  literal so the local binds as `ptr:ptr`.

*Accept:* both spellings work without the workaround; a 1000-row
`(array Struct …)` still compiles in the same ballpark of time; `make bootstrap`
byte-identical.

## W5e — `defn-` name isolation (§2.5) — medium, design decision required

Two `defn-` (private) functions with the same name in different files collide:
`duplicate method signature for overloaded 'ensure-channels'`. Private definers
are private to a **namespace**, and files default to the shared `user` namespace,
so `defn-` buys internal LLVM linkage but no name isolation.

Practical effect in a 60-file project: every short helper name (`ensure-*`,
`init-*`, `reset-*`, `clamp-*`) must be manually module-prefixed, and the error
surfaces in whichever file was written *second*, naming a function its author has
never seen.

This is a **design decision, not a bug fix.** Stage 12 built the namespace system
(`ns`, `import-prefixed`, `export`, `unsafe/import-private`); the question is
whether a file with no `(ns …)` should get an implicit per-file private scope.
Options:

1. **Implicit file-scoped namespace for private definers only.** A `defn-` in a
   file with no `ns` is keyed on (file, name, arity) rather than (name, arity).
   Public definers keep today's behaviour. Smallest user-visible change; makes
   `defn-` mean what its name implies.
2. **Require `ns`** and improve the error to say so: *"`defn-` names are private to
   a namespace, and both files are in `user`; add `(ns …)` or rename"*. Zero
   mechanism change, and it pushes users toward the namespace system that already
   exists.
3. **Nothing**, document the prefix convention.

Recommendation: **evaluate 1, implement 2 as the fallback.** Option 1 is the right
end state — "private" that leaks across files is a misleading keyword — but it
touches the global-key scheme that W1 is also changing. **Sequence W5e after W1**,
or accept option 2 for this stage and record option 1 as the follow-up. Do not do
both W1's key changes and W5e's key changes concurrently in separate subagents;
they will conflict.

*Accept:* whichever option, the error at minimum explains the namespace rule and
names both definitions' files. If option 1: two files may each define a private
`ensure-channels`; a public collision still errors.

## W5f — union with a function-pointer member (§1.1) — medium, crash

**Status: DONE (2026-07-31). Outcome: working code, not a diagnostic.**

**The framing above is wrong, and worth recording: this was never a union bug.**
Unions carry function-pointer members fine — `(union acv:(fn void) i:i32)` and the
list-form `(union (acv (fn void)()))` both compile today and always did, and
`hash-type`/`union-repr-member`/`emit-union-ir-type`/`abi-*` all handle `TY-FN`
correctly. Nothing in `src/union-registry.nuc` was at fault. The bisect that
settled it: swapping `union` for `struct` in the repro
(`(defstruct Row (action (struct acv:(fn void)())))`) crashes *identically*, and
the list-form union does not crash at all.

**Root cause: the colon-paren reader fuse cannot express a function-pointer type.**
A function-pointer type is *two* parenthesised groups, `(fn ret)` and its parameter
list, but `fuse-colon-paren` (`lib/reader.nuc`) absorbed only one. So
`acv:(fn void)()` read as the member `(acv (fn void))` **plus a separate `()`
member** — and `()` reads as a NULL node (`read-list` returns null for a
zero-element list), which the member loop then dereferenced. Segfault.

The same missing fuse silently mistyped every *other* binding position too:
**the spelling `docs/types.md` documented, `f:(fn i32) (i32 i32)`, never worked** —
`f` bound as a zero-parameter fn and `(i32 i32)` became a bogus extra parameter
(`(defn apply2 (f:(fn i32) (i32 i32) a:i32 b:i32) …)` died at the call site with
`call: expected 0 args, got -1`). Only the canonical list form
`(f (fn i32) (i32 i32))` ever worked.

**Fix (reader, ~15 lines).** `fuse-fn-params` (`lib/reader.nuc`, beside
`fuse-colon-paren`): when the just-read colon-paren form is `(fn …)`-headed and
the very next raw character is `(` with nothing peeked, absorb that group and
return the nested canonical spelling `((fn ret) (params))` — exactly what
`parse-type-from-node`'s function-pointer branch consumes. The name/colon-chain
wrapping then proceeds unchanged, so this composes for free with the chain
(`p:ptr:(fn i32)(i32)` → `(p (ptr ((fn i32) (i32))))`) and the lone-colon return
fuse. Adjacency is required, as for the first group: a *space*-separated second
group is genuinely ambiguous with the next binding in the enclosing list, so it is
not absorbed — `docs/types.md` was corrected rather than the reader made ambiguous.

**Second fix: `()` never segfaults again.** `()` → NULL node is a general trap,
not a union one; a raw `(n kind)` / `(n line)` on it faults. Ten sites were
hardened so every declaration/expression position gives a **located** diagnostic
(all ten were confirmed SIGSEGVs beforehand):

* `extract-name-and-type` / `extract-name-type` (`src/nucleusc.nuc`) — the shared
  chokepoint for struct fields, union/struct members, defn params, let/with
  bindings and defunion arm fields.
* `emit-node` (`src/nucleusc.nuc`) — `()` in *expression* position.
* `emit-defstruct` field loop, `emit-defn`'s `&rest`/`&optional` scan, its
  closure-exposure (L8) warning scan, and its parameter loop — each computed a
  diagnostic line with a raw deref; all now use the null-safe `node-line`.
* `defn-params-count` / `defn-params-to-types` / `params-where-index` /
  `defn-has-receiver-tyvars` / `binding-type-node` (`src/generics.nuc`) — the
  signature prescan.
* `defunion-strip-repr`'s arm and `&repr`-mode reads (`src/union-registry.nuc`).
* `emit-defmacro`'s `&rest` scan and param loop.

Switching those line computations to `node-line` also upgrades several
diagnostics from `:0:` to a real line (an interned symbol node's own line is
always 0 — the W4a class), which is why no expected fixture moved.

**Verification.** `examples/fn-ptr-union.nuc` + `tests/expected/fn-ptr-union.out`
round-trips a function pointer through the union in all four required spellings
(`(fn void)()`, `(fn i32)(ptr)`, mixed with a scalar, and standalone as both a
global and a local), plus the defn-param and `let`-binding forms the same reader
rule fixes. Four `tests/fixtures/w5f-empty-*.nuc` reject fixtures pin the
no-segfault guarantee (`run_reject_at` fails on a crash, since there is no message
to grep). `make test` 269 PASS / 0 FAIL; `make abi-test` / `make layout-test` green;
**`make bootstrap` byte-identical on the first pass** — every change is either
reader-additive (no existing source uses the new spelling) or error-path-only, so
no emitted IR for a valid program moved. Proven independently of the bootstrap:
`bin/nucleusc` (rebuilt from the committed `boot/nucleusc.ll`, i.e. the *pre-change*
compiler) and `build/nucleusc` were each run over every `examples/*.nuc`,
`lib/*.nuc` and `tests/fixtures/*.nuc` — **192 programs emit byte-identical IR, 0
differ**; the only files the old compiler cannot process are this chunk's own new
ones, which it segfaults on (confirming the four fixtures reproduce the bug).
`--emit-cheader` renders the union as C `union { void* acv; void* ac1; int32_t n; }`
and `--emit-nuch` round-trips it to the same memoization hash.

**Not done / follow-up:** the space-separated `f:(fn i32) (i32 i32)` spelling is
still accepted *silently* as a zero-parameter fn plus a junk parameter. Detecting
it needs a heuristic at the binding loop ("a `(fn ret)`-typed binding followed by a
bare list sibling") that is ambiguous by construction; the docs now state the rule
instead. A W4-class diagnostic could revisit it.

**The one new footgun, accepted deliberately.** In a `let`/`with` binding list the
element after the name *is the initializer*, so `(let (f:(fn i32)(choose)) …)` now
absorbs `(choose)` as the parameter list. It fails **loudly and located** (`let:
binding list must be even` — the pair became one element), no source in the tree
writes it (proven: the 192-program IR sweep below), and the fix is a space. No
better rule is available: the reader has no type context, and a single-symbol
parameter list `(i32)` is structurally identical to a single-symbol call
`(choose)`. Documented in `docs/types.md` and `context/conventions.md`.

### Original brief (retained)


**Confirmed live.** `build/nucleusc` on:

```lisp
(defstruct Row (action (union acv:(fn void)())))
(defn main ():i32 (return 0))
```

→ **SIGSEGV (exit 139, core dumped)**. Merely *registering* the `defstruct`
crashes; no construction or access needed. A standalone `(union acv:(fn void)())`
outside any struct crashes identically. A union of non-function-pointer members
(`docs/structs-unions.md`'s own `Scalar` example) is fine.

### Where to look

`src/union-registry.nuc:25` `hash-type` is the TY-FN-aware hasher, reached from
`hash-struct-shape` (`:44`) via `lookup-or-make-anon-union` (`:82`):

```lisp
(when (= k TY-FN)
  (set! h (hash-type h (tt ret)))
  (set! h (fnv-byte h (as i64 (tt num-params))))
  (dotimes (i (tt num-params))
    (set! h (hash-type h ((field-at (tt params) i) type)))))
```

`hash-type` guards `t == null` at entry, and the `dotimes` is bounded by
`num-params`, so the obvious null derefs are covered — **do not assume this is the
crash site.** Bisect it properly: the anon-union path, `union-repr-member` (`:99`),
`emit-union-ir-type` (`:125`), and the pending-deps drain (`:158`, `:180`) are all
candidates, as is type *parsing* of `(fn void)()` before the registry sees it. The
Stage 13 L7 note at `:274` about TY-FN spellings interned as `__fnty_<id>` is worth
reading — a function type that has no interned spelling yet may be the trigger.

### What "fixed" means

A crash must become either working code or a clean diagnostic. Both are
acceptable outcomes; prefer working.

The C construct this exists to model is `actionf_t` — several function arities
sharing one slot, which Doom's 967-row `states[]` table carries in every row. If
unions of function pointers are to remain unsupported, the diagnostic must say so
and point at the working alternative (a plain `ptr` field holding
`(unsafe/cast ptr some-fn)`, reinterpreted per call site with `funcall` — which the
port uses successfully and which is bit-identical to the union).

*Accept:* the repro either compiles and round-trips a function pointer through the
union, or produces a located diagnostic naming the unsupported construct and the
alternative. **No segfault under any spelling** — check `(fn void)()`,
`(fn i32)(ptr)`, a union mixing a fn-ptr with a scalar, and the standalone
non-struct form. Add all four to `tests/`.

---

## Accept criteria for W5 as a whole

* Every sub-item above either lands with its own accept criteria met, or is
  recorded **in this doc** as deferred with the reason and what was done instead.
* `make test` green; `make bootstrap` byte-identical after each sub-item. W5d and
  W5e are the two most likely to move IR — if either does, confirm the diff is
  exactly the intended change before `make update-bootstrap`.
* `docs/` updated for `\x`, `bit-not`, `CStr` defvars, the array-literal
  relaxations, and whatever W5e decides. `docs/structs-unions.md` gains the
  function-pointer-union status.
* New `tests/` cases with expected-output fixtures for each landed sub-item.

---

## W5c as built

**Status: done.** `make bootstrap` byte-identical (`stage1.ll == stage2.ll`, no
`update-bootstrap` needed), `make test` **267 PASS / 0 FAIL** (was 264).

### What actually reproduced

All three spellings still failed, but **the line-0 half of the finding was
already gone** — W4 fixed it, and every diagnostic on this path now reports a
real line:

| spelling | measured before W5c |
| --- | --- |
| `(defvar g:CStr (as CStr ""))` | `t.nuc:1: error: defvar: init must be a literal` |
| `(defvar g:CStr "")` | `t.nuc:1: error: defvar: string literal requires ptr type` |
| `(defvar g:CStr c"lit")` | `t.nuc:1: error: defvar: string literal requires ptr type` |
| `(defvar g:CStr null)` | `t.nuc:1: error: defvar: null requires ptr type` |

The `(as CStr …)` case is **not CStr-specific and was left alone**:
`(defvar g:ptr (as ptr "hello"))` fails identically. "Init must be a literal" is
a general restriction on *expressions* in constant position, already documented
as such, and W5c's accept criteria do not require lifting it.

### Which literal spelling is correct: **both**

The brief expected `c"…"`. The right answer is that **`ptr` and `CStr` accept
the same set**, which is both spellings, and this is what landed.

`defvar-init-ir` **already accepted a plain `"…"` for a `ptr` global** before
W5c (`(defvar gp:ptr "hello")` emits `@gp = global ptr @.str.N`). Since NS-3 a
plain `"…"` is a `StrView`, so that acceptance is already the hidden-NUL free
coercion, not a `CStr` leftover. At a *global initializer* the StrView/CStr
distinction has fully collapsed: the backing `@.str.N` rodata is NUL-terminated
either way, so an unmaterialized literal's value simply **is** its `data`
pointer — exactly what `coerce-int-val` does in value position, where it admits
a StrView literal into a `ptr` **and** a `CStr` target without distinguishing
them. Accepting `c"…"` but rejecting `"…"` for `CStr` would have invented an
asymmetry that neither the value path nor the `ptr` case has.

### The fix

Two gates in `defvar-init-ir` (`src/nucleusc.nuc`) tested a bare `TY-PTR` kind
where they should have tested `is-ptr-like` ({`TY-PTR`, `TY-CSTR`}) — the
standing rule in `context/conventions.md`'s string-type lattice. Both
diagnostics now also name the offending type. `emit-defvar`'s **no-init**
default already branched on `is-ptr-like`, so `(defvar g:CStr)` emitted
`global ptr null` while the explicit `(defvar g:CStr null)` was rejected; that
split is closed.

### The finding was bigger: making it compile exposed a segfault

`(defvar g:CStr null)` compiling is worthless on its own, because the obvious
thing to then do with it **crashed**:

```lisp
(defvar g:CStr null)
(if (= g null) …)      ; → call i32 @strcmp(ptr %t0, ptr null) → SIGSEGV
```

`emit-binop-vals` fires the strcmp content-comparison lowering whenever *either*
operand is `CStr`/`StrView` — including when the other operand is the `null`
literal. `strcmp(x, NULL)` is undefined behaviour in C and segfaults under
glibc. Measured: exit 139, core dumped.

**This is pre-existing and not global-specific** — a `CStr` *parameter* or local
null-checked with `=` lowered identically. It is precisely the "null-check trap"
`context/conventions.md` documents, whose stated mitigation was *never give a
null-checked value the `CStr` type*. W5c makes a `CStr` global spellable, which
promotes that trap from "avoid this in compiler internals" to "ordinary user
code hits it immediately", so it was fixed rather than documented:

`emit-binop-vals` now suppresses the strcmp branch when either **operand node**
is the symbol `null` (via the existing `node-is-null-sym`) and the other operand
is `is-ptr-like`, and the pointer-identity gate below it was widened from
`TY-PTR` to `is-ptr-like` so the escape lands on `icmp eq ptr`. Restricted to a
ptr-like partner deliberately: a `StrView` is a two-word struct that can never be
null, so `(= sv null)` is untouched and out of scope.

This is **strictly a bug fix** — no correct program can depend on a lowering
that is UB in C. It is also inert for the compiler's own IR: `boot/nucleusc.ll`
contains **zero** `strcmp(ptr %x, ptr null)` occurrences, confirming the
compiler's source never had a `CStr`-vs-`null` comparison (conventions.md's
guidance had kept every null-checked value typed `ptr`). That is why the
bootstrap converged byte-identically on the first pass.

*(Unrelated accounting note: total `@strcmp` calls differ 476 → 473 between
`boot/nucleusc.ll` and `build/nucleusc.ll`. That is entirely the already-
committed `Add bit-not` commit, which deleted `known-name-correction` and its
three `(= name "…")` comparisons; `boot/` is simply stale relative to HEAD. It
is not caused by this change.)*

### The `node-type` lockstep is not at risk

The change alters *which instruction* is emitted, never a result type: a
comparison returns `ty-i1` on both the strcmp and the identity path, and
`node-type-call`'s binop branch (`src/generics.nuc`) returns `ty-i1` for any
`is-cmp` binop regardless of operand type. No mirror edit was required.

### Tests added

* `examples/cstr-defvar.nuc` + `tests/expected/cstr-defvar.out` — the positive
  matrix, checked **by value** rather than by exit code, because "it compiles"
  was never the question (the `ptr` + `(as CStr …)` workaround compiled too).
  Covers both literal spellings, explicit `null`, no-init, `:const`, the private
  `defvar-` (the exact §3.7 spelling), `set!` from both a literal and a heap
  string, and every global handed to a libc function declared `const char *`
  (`strlen`, `strcmp`, `strdup`, `printf %s`). It also pins the fixed segfault,
  and proves the globals are genuinely `CStr`-typed rather than silently
  degraded to `ptr`: `g-mut` holds a `strdup` copy, so `content-eq=1` while
  `ptr-identity=0` — the `=` really is a content comparison over distinct
  buffers.
* `tests/fixtures/w5c-string-into-int.nuc`, `tests/fixtures/w5c-null-into-int.nuc`
  — the boundary the widened gate must not cross: a string literal and `null` in
  an `i32` global are still rejected, at their own lines. Both also feed the
  `run_no_line_zero` sweep, which stays green.

### Not done (out of scope, recorded)

* `(defvar g:CStr (as CStr ""))` still fails — the general "init must be a
  literal" restriction on expressions, identical for `(as ptr "…")`.
* `(defvar g:StrView "hi")` still fails (`string literal requires ptr or CStr
  type, not StrView`). A `StrView` global needs a two-word aggregate constant
  initializer, which is real new machinery and a different item.

### Interaction with the W6 null-safety hole (explicitly disjoint)

A separate finding surfaced mid-flight: **`defvar`'s global initializer bypasses
the null-safety check.** `(defvar g:ptr:Thing null)` and
`(defvar g:(ref Thing) null)` compile clean and segfault at runtime, while the
identical binding as a *local* is correctly rejected
(`assignment: raw pointer where non-null (ref ...) is required`). Cause: this
constant renderer never routes through `coerce-int-val`, so `pkind-flow-check`
never runs. Re-verified here against the post-W5c build: compile exit 0, run
exit 139.

**W5c neither widened nor closed it, and this was measured rather than
reasoned.** The old gate `(!= ty-kind TY-PTR)` accepted every `TY-PTR`
regardless of `pkind`; the new gate `(= (is-ptr-like ty) 0)` accepts
`TY-PTR ∪ TY-CSTR`. The delta is exactly `{TY-CSTR}` — every pkind of `TY-PTR`
was accepted before and is accepted now. Both repro programs above behave
identically before and after.

**The carve-out is now explicit, which is the part the follow-up needs.** `CStr`
is the C `char*` FFI type, flow-exempt by design (conventions.md's string-type
lattice groups it with `void*` outside the Phase-F non-null regime) — a null
`char*` is ordinary, meaningful C, and `(defvar g:CStr null)` is precisely the
"not yet set" global W5c exists to enable. `defvar-init-ir`'s `null` branch now
returns early on `TY-CSTR` as its own commented case rather than letting `CStr`
ride through the shared `is-ptr-like` test, so the exemption is *stated*. The
`TY-PTR` path below it is commented as the place the missing pkind check
belongs.

`tests/fixtures/w5c-cstr-null-exempt.nuc` pins this in the accept direction via
a new `run_accepts` harness helper (the inverse of `run_reject`): if a future
stricter check sweeps `CStr` up with `ptr`, that test fails. `run_no_line_zero`
would not have caught it — it only sweeps for `:0:`, not for a fixture that
stops compiling.

---

## W5d as built

**Status: done.** `make bootstrap` byte-identical (`stage1.ll == stage2.ll`, no
`update-bootstrap` needed), `make test` **274 PASS / 0 FAIL** (was 270).

### What actually reproduced

Both warts, on the current `build/nucleusc`. But the surrounding behaviour was
not what the finding described, and the difference decided both fixes:

| spelling | measured before W5d |
| --- | --- |
| `(array P (P 1 2) …)` | `error: array: type mismatch in positional initializer` |
| `(array P (deref (P 1 2)) …)` | compiles (the documented workaround) |
| `(take (P 1 2))` against `(defn take (p:P) …)` | **compiles** — the argument position already loads |
| `(let (v:P (P 1 2)) …)` | `error: let: init type mismatch for 'v'` |
| `(Row (P 1 2) 5)` — struct-typed field | `error: struct literal: type mismatch for positional initializer` |
| `(let (a:ptr (array ptr "one" "two")) (aref a 0))` | `error: aref: operand must be typed pointer` |
| `(let (a:ptr (array i32 1 2 3)) (aref a 1))` | **same error** — not ptr-of-ptr-specific |
| `(let (a:ptr:ptr (array ptr …)) (aref a 0))` | **compiles** |
| `(let (a (array ptr …)) (aref a 0))` | **compiles** — an unannotated binding already infers |

Two premise corrections fall out of that table.

**§3.9 is not an array-literal wart; it is a by-value-struct-slot wart, and the
argument position already had the fix.** Stage 13 CE-3 put a by-value
normalization in `emit-call-with-args` — if the parameter is a by-value `S` and
the argument is a pointer to that same `S`, it loads. So `(take (P 1 2))`
compiled while `(let (v:P (P 1 2)) …)` did not. Fixing this at the array literal
would have mirrored the CE-3 rule into a third place; fixing it at
`coerce-int-val` makes one rule reach all eight of its typed-slot callers
(let/with init, `set!`, `.set!`, `ptr-set!`/`aset!`, explicit and implicit
`return`, struct-literal and array initializers, union-variant construction),
which is why the struct-typed-field and by-value-`return` rows above are fixed
too without a line of extra code.

**§3.10 is narrower than "an array-of-pointers local binds as bare `ptr`".**
The fully-annotated spelling and the *unannotated* spelling both already worked;
the broken case is the annotated-but-imprecise middle one, and it has nothing to
do with pointer elements — an `(array i32 …)` bound to `:ptr` failed identically.
The workaround in the finding (`(aref (unsafe/cast ptr:ptr a) i)`) was also not
the only one available: dropping the annotation is enough.

### §3.9: one load at the chokepoint, and the "one load" claim is measurable

`coerce-int-val` (`src/abi.nuc`) gained one branch: source `TY-PTR` with a
non-null `elem`, target `TY-STRUCT`, and the pointee's `StructDef` identical to
the target's ⇒ `require-derefable` then one `emit-load`. That is byte-for-byte
what `emit-deref` does, and the proof is direct rather than by inspection: a
1000-row `(array St …)` compiles to **identical IR** under the bare and
`(deref …)` spellings — the only differing lines are the module ID and
`source_filename`. 1000 allocas, 1000 loads; linear, no copy loop.

`type-eq`'s TY-STRUCT rule (same `StructDef`) is spelled out inline rather than
called: `generics.nuc` is imported *after* `abi.nuc`, so a forward reference to
`type-eq` would not resolve when abi's bodies emit. (`alloc-val` and `emit-load`
live in `nucleusc.nuc` and *are* forward-referenced — the whole-unit prescan
covers the outermost file, not a later import.)

The new branch is **unreachable from the call-argument path**, twice over:
`safe-coerce-val` delegates only StrView / int↔int / float↔float / `defcast`
pairs down to `coerce-int-val` (a ptr→struct pair falls through to its own null
return), and the CE-3 block runs first in any case. This matters because of the
W2d hazard: `emit-call-with-args` reads a null return as *"leave the argument
alone"* rather than as a type error, so a coercion added at this chokepoint has
to be checked against the argument path separately. Here it cannot fire there,
so arguments are unchanged.

Because the conversion **is** a `deref`, it carries `deref`'s Stage 10
obligation: a `?T` source is rejected with the narrowing diagnostic
(`assignment: value may be null — narrow with if-some/when-some, …`) instead of
being silently loaded. The explicit spelling has always demanded that; the sugar
must not be a hole in the nullability system that the explicit form does not
have. `tests/fixtures/w5d-struct-slot-maybe-null.nuc` pins it.

### §3.10: deliberately syntactic, and here is why the general rule was rejected

`array-lit-binding-type` (`src/generics.nuc`) refines an elem-less declared
pointer to `ptr:T` when the initializer is literally an `(array T …)` form,
keeping the **declared** pointer kind and volatility. It is called from
`emit-let`/`emit-with` and mirrored in `node-type-block` — one rule function,
two callers, never two copies of the logic (the `node-type`↔`emit-node`
lockstep). It is IR-inert by construction: every pointer lowers to `ptr` with
size 8, so the binding's alloca, store and coercion are identical either way and
only the type recorded in the *scope* changes.

The obvious generalization — "an elem-less declared pointer adopts the
initializer's element type" — was **rejected on measurement, not taste**:

* `type-eq` compares pointer elements, so `ptr:Node` does **not** match a `ptr`
  parameter in multimethod dispatch. Adopting an element type silently re-routes
  (or breaks) every overloaded call taking that binding.
* A bare `:ptr` erases the **nullability claim** as well as the element type —
  `pkind-flow-check` exempts an elem-less target. Adopting an element without
  the source's pkind manufactures a non-null claim over a nullable value;
  adopting the pkind too silently overrides what the author declared.
* The blast radius is not hypothetical: this compiler has ~1550 bare `:ptr`
  bindings with call initializers, 113 of them from `addr-of` (always `(ref T)`)
  and 68 from `make-cell`.

An `(array T …)` initializer has none of those problems — it is an alloca, so
always non-null, and its element type is spelled by the author *in the
initializer*, so nothing is inferred that a reader of the binding cannot see.
`tests/fixtures/w5d-elemless-not-inferred.nuc` pins the boundary in the negative
direction (a `:ptr` bound from an `alloca` stays elem-less), so a later attempt
to "generalize" this has to argue with a failing test.

### Two pre-existing crashes on the path this opens

Both confirmed against the *pre-W5d* binary, so neither is a regression — but
both sit squarely on the shape §3.9 exists to make writable, and a sparse
generated table hits the first one immediately.

`emit-zero-store` filled an unspecified slot with the scalar `0` for every type
it did not special-case:

* a struct/union slot got `store %P 0` — LLVM: *"integer constant must have
  integer type"*. Reachable from `(array S (S 1 1) (3 (S 9 9)))`, i.e. any
  designated/sparse table of structs, and from a struct literal omitting a
  struct-typed field.
* a `CStr` (and `TY-FN`) slot got `store ptr 0` — the same parse error. This is
  `conventions.md`'s documented TY-PTR-vs-`is-ptr-like` trap, hit once more: the
  gate tested `(= (ft kind) TY-PTR)` where the standing rule is `is-ptr-like`.

Fixed with `zeroinitializer` for aggregates and `is-ptr-like` (plus `TY-FN`) for
pointers. `TY-PTR` itself still emits `null`, so every zero-fill that worked
before is byte-identical.

### Confinement proof

A per-function normalized diff of the compiler's own IR (`%`-names and
`@.str.N` numbers stripped, `build/nucleusc.ll` before vs after) shows **exactly**
five functions changed — `coerce-int-val`, `emit-let`, `emit-with`,
`emit-zero-store`, `node-type-block` — and one added,
`array-lit-binding-type`. Zero collateral movement across the other ~950
functions, which also confirms empirically that neither relaxation fires in the
compiler's own source: `src/` and `lib/` contain no `(array …)` literal and no
by-value struct slot fed a pointer.

### Deliberately out of scope

* **A by-value `union` target.** The new branch is gated on `TY-STRUCT`, mirroring
  CE-3 exactly. `(deref …)` still works for a union element, and tagged-sum
  construction has its own machinery (`union-target-rewrite`); widening the gate
  would cross into it without a repro to justify the risk.
* **Indexing a struct array reads a copy.** `(aref tbl i)` on `ptr:S` yields an
  `S` *value*, so `((aref tbl i) x)` fails ("not callable — not a
  pointer-to-struct") and the working spellings are `((unsafe/ptr+ tbl i) x)` or
  a `let`-bound copy. That is a separate ergonomic gap on the *read* side of the
  same table, unrelated to the literal, and is left for a future item.
