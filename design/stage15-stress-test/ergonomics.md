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

## W5a — `\x` escapes in string literals (§4.4) — trivial

`"MUS\x1a"` dies `unknown escape \x`. The port had to poke a four-byte magic
number into an `(alloca ui8 N)` byte by byte.

`lib/reader.nuc`'s escape handling already supports `\a`, `\newline`, `\u{…}`
(Stage 11 M6 S0 char literals). Add `\xHH` — one or two hex digits, matching C.
Decide and document whether `\x` is greedy like C (C consumes *all* following hex
digits, which is a known C footgun) or capped at two. **Recommend capped at two**
and say so in the docs: C-compatible for every practical case, without C's
"`"\x41BC"` is one character" surprise.

*Accept:* `"MUS\x1a"` is four bytes; `\x` with no hex digits is a located error;
docs state the two-digit cap.

## W5b — unary `bit-not` (§4.3) — trivial

Only binary `bit-and`/`bit-or`/`bit-xor`/`bit-shl`/`bit-shr` exist; C's `~x` must
be written `(bit-xor x -1)`.

Add `bit-not` as a **one-argument macro** expanding to `(bit-xor x -1)`, per this
repo's "prefer macros over builtins" principle in `design/overview.md`. That
expansion is exactly correct for two's complement at every width and needs no
codegen. `lib/macros.nuc` is the home.

Coordinate with W4a: until this lands, `unknown: bit-not` should suggest the
`bit-xor` form; once it lands, delete that suggestion.

*Accept:* `(bit-not x)` works for every integer width, signed and unsigned;
`(bit-not 3)` is `-4`; the W4a suggestion is removed.

## W5c — `defvar` typed `CStr` (§3.7) — small

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
