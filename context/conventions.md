# Conventions

## Design documents

When a feature in a design document gets implemented, add a **Status:** note but preserve the original design discussion and commentary. The design reasoning is a valuable record of how decisions were made and remains useful context for future work even after implementation.

## Format helpers are fixed-arity (`src/format.nuc`)

`fmt-s` takes **exactly one** `%s` argument; `fmt-i32` exactly one `%d`/`%ld`, etc. They are plain functions, not variadic. Passing a format string with more conversions than the helper's parameter count makes `snprintf` read a garbage vararg and typically **segfaults the compiler** (no error — just a crash with empty output). For multiple substitutions use the dedicated variants: `fmt-2s` (two strings), `fmt-sd` (string + int), `fmt-i32-i32` (two ints), `fmt-2s-i` (two strings + int). If you need a new shape, add a helper in `src/format.nuc` rather than overloading an existing one.

## `node-type` mirrors `emit-node` (keep them in lockstep)

`emit-node` (`src/nucleusc.nuc`) sets the type a node propagates to its parent from
`node-type(n, scope)` (Stage 9 rung 3) whenever that returns non-null. So the
non-emitting type pass and codegen share **one typing rule per node kind**. Since
the Stage 12 module split the two halves live in **different files**: `emit-node`
and the `emit-*` family in `src/nucleusc.nuc`, the entire `node-type` family (the
`node-type` dispatcher plus `node-type-call` / `node-type-block` / `node-type-field`
/ … helpers) in `src/generics.nuc`. Editing one file without its partner is the
easy mistake. If you add a new special form to `emit-list`, or change the result
type any `emit-*` function returns, **update the matching branch in `node-type`
(generics.nuc) in the same change**.
The `make bootstrap` fixed-point test enforces this: a divergence makes the
compiler emit different IR than it consumes and `stage1.ll != stage2.ll`. A form
that `node-type` deliberately does not model returns null (codegen then keeps its
own type) — that's the escape hatch for control-flow/expansion-dependent results
(`cond`, macros, `quasiquote`), not a license to skip updating modelled forms.

## `defn` bodies are not desugared (colon-symbols survive)

`desugar` only rewrites **binding positions** of known forms: the `defn` name and
param list, `defvar`/`extern`/`declare` names, `defstruct` fields, and `let`/`with`
binding *names*. A `defn`'s **body is left untouched**, so a colon-typed symbol in
the body (`r:T`, `x:ptr:Node`, `(cast i32 …)`) stays a single `NODE-SYM` —
`split-typed`/`extract-name-and-type` parse it lazily in value position. So an AST
transform that walks a `defn` form sees the *desugared* shapes in the signature
(`(a T)`, `(maxv T)`) but the *raw colon* shapes in the body (`r:T`). The Stage 9
generic monomorphizer (`subst-tyvars-node`) therefore substitutes at the
colon-*segment* level (like `subst-self-node` for protocols), not by matching
standalone symbol nodes — that handles both shapes uniformly.

## Emitting a function mid-emission needs the worklist, not a direct `emit-defn`

`emit-defn` calls `reset-function-state`, clobbering the per-function streams
(`g-entry-stream`/`g-body-stream`). So you cannot synthesize and emit a new
function while another function's body is being emitted. The generic
monomorphizer (rung 4) handles this by *registering* the stamped method
immediately (so the active call site can name its `@name.<tok>…` symbol) but
*queuing the body* on `g-mono-worklist`, drained by `drain-mono-worklist` at the
end of `emit-toplevel-forms` when no function emission is in progress. LLVM
textual IR allows forward references to functions defined later in the module, so
the call emitted earlier links fine. Reuse this pattern for any future
"emit-a-function-on-demand-from-a-call-site" feature.

## `TY-TYVAR` is a check-only type — never let it reach codegen

The `TY-TYVAR` type kind exists solely for the Stage 9 rung-4 **A2** def-time check
of bounded-generic bodies (`gcheck`/`check-generic-templates`): it types a
parameter declared as an abstract type variable so the checker can verify only the
constraints' protocol methods are used. Generic templates emit code *only after
monomorphization* (every type concrete), so `TY-TYVAR` must never flow into
`emit-*`, `type-to-ir`, `type-size`, or `type-mangle-token`. The `node-type`↔`emit`
lockstep is not at risk because the abstract scope exists only inside the A2 walk;
during real emission no scope binding is `TY-TYVAR`. If you add a new place that
manufactures or stores types, keep `TY-TYVAR` confined to the checker.

## `?`/`!` in user function names break LLVM symbols

A solitary/overloaded `defn` named `lt?` is emitted as `@lt?` / `@lt?.i32.i32`,
which is **invalid LLVM IR** (`?` is not in the unquoted-identifier charset; it
would need `@"lt?"`). The compiler does not currently quote symbols, so user
*function* names should stick to `[A-Za-z0-9$._-]`. (`set!`/`inc!`/`lt?`-style
names are fine for special forms and macros, which never become `@`-symbols.)

## Struct field names are interned — StructDef builders must use `intern-str`

`struct-field-index` (src/nucleusc.nuc) matches a selector against a struct's
`field-names` by **pointer identity** (`=`), not `strcmp`. This works because both
sides are interned: selectors arrive interned (the reader / `quote` intern symbol
spellings at lex time, so `(. fn-node s)` is the canonical string) and stored field
names are interned at build time via `intern-str` (interns the spelling, returns the
canonical string pointer). The three field-access paths — `.` (`emit-field-get`),
the `get` intrinsic (`emit-get-intrinsic`), and the non-emitting type pass
(`node-type-field`) — all route through `struct-field-index`, so they cannot drift.

There are exactly **two** places that populate a StructDef's `field-names`:
`emit-defstruct` (the normal path, incl. `.nuch` imports) and `repl-register-node`
(the REPL's hand-built `Node`). **Both must intern each name** (`(intern-str fname)`).
A raw string literal would `strcmp`-equal a selector but **not** be pointer-identical,
so the field would silently look absent (`-1` ⇒ "no field" / null type). If you add a
third StructDef builder, intern its field names too. The `make bootstrap` fixed point
does **not** exercise the REPL path — the `repl-redefinition` test does (its `*`/`-`/`if`
macros do `(. (cast ptr:Node args) cdr)` at expansion time), so keep `make test` green,
not just `make bootstrap`, when touching field interning.

**Field TYPES drift too — `repl-register-node` must mirror `lib/prelude.nuc`'s `defstruct Node`.**
The same lockstep that applies to field *names* applies to field *types*: every field-type
slot `repl-register-node` writes must match the canonical `defstruct Node` in
`lib/prelude.nuc` (and `lib/list.nuc`). When `car`/`cdr` were retyped `ptr`→`(raw Node)`
for macro ergonomics, `repl-register-node` was missed and kept assigning bare `ty-ptr`.
The symptom is subtle: a macro that reads `(p car)` once and binds it works (bare `ptr`
flows into a `(raw Node)` slot), but a macro that **chains** without a cast — e.g.
`((spec cdr) car)` in `dotimes` (lib/macros.nuc) — dies in `emit-get-intrinsic`
(src/nucleusc.nuc:~2056, "callable value: not callable — no matching get/invoke method
and not a pointer-to-struct") because `(spec cdr)` returns an untyped `ptr` (elem=null),
so `ek` resolves to `TY-VOID` and the `TY-STRUCT`/`TY-UNION` gate fails. This fires the
moment the REPL JITs any new-ergonomics macro, so `nucleusc -i` dies at startup inside
`repl-preload-macros` and `(import-use macros)` dies interactively even with the preload
removed — the failure is independent of *when* the macro library loads. Build the typed
slot with the same pattern the macro emitter uses (src/nucleusc.nuc, `make-type TY-PTR`
+ `elem` = `(parse-type-name "Node" 0)` + `pkind PTR-RAW`); `parse-type-name` succeeds
because `register-struct "Node"` already ran earlier in the same function.

## `CStr` is ABI-identical to `ptr` — gate pointer ABI on `is-ptr-like`, not `TY-PTR`

`TY-CSTR` (the C-string type; string literals are `CStr`) lowers to `ptr` in IR
and is a plain `char*` at the ABI. It is a *distinct kind* only so `=` / `!=`
dispatch to a `strcmp` content comparison (`emit-binop-vals`) instead of pointer
identity. **Everywhere else it must behave exactly like `TY-PTR`:** `type-to-ir`
→ `ptr`, `type-size` → 8, zero-init → `null`, `cast` to/from `ptr` is a no-op,
and it must never be `inttoptr`'d (it is already a pointer). A bare `(= (. t
kind) TY-PTR)` ABI check therefore *misses* `CStr` — use the `is-ptr-like`
predicate ({`TY-PTR`, `TY-CSTR`}; `TY-FN` deliberately excluded). This bit the
`&rest` arg-folding (`emit-call-with-args`), which `inttoptr`'d any non-`TY-PTR`
arg and produced invalid `inttoptr ptr→ptr` for a `CStr` rest arg. When adding a
new pointer/integer ABI decision, branch on `is-ptr-like`.

Two deliberate asymmetries: (1) `CStr`↔`ptr` coerce freely in *value* positions
(`coerce-int-val`) but **not** in multimethod dispatch (`arg-adapts`) — `CStr` is
distinct there on purpose, so you can overload `CStr` vs `ptr`; pass a literal to
a plain `ptr` function freely, but to a `ptr` *multimethod* cast explicitly.
(2) Conformance is keyed by `type-spelling`, which must return `"CStr"` (not the
fall-through `"ptr"`) or `(extend CStr Eq)` won't match the call-site check.

**Mixed-operand rule (`emit-binop-vals`):** `=`/`!=` fire the strcmp lowering when
*either* operand is `CStr` (the other must be `ptr`/`CStr`); two plain `ptr` stay
`icmp` identity. So `(= some-ptr "literal")` is a content test (the literal is
`CStr`) — this is what lets the compiler write `(= name "i32")` instead of
`(= (strcmp name "i32") 0)` without retyping `name`. The corollary trap: any value
you retype `ptr`→`CStr` makes *all* its `=`/`!=` become strcmp, so never retype a
field/param that is compared for pointer identity (notably **`Node.s`** — the
interned-symbol path). `strncmp` (prefix) has no operator; leave those as calls.

**Verifying a behavior-neutral type migration:** retyping `ptr`→`CStr` and
rewriting `(= (strcmp a b) 0)`→`(= a b)` is **byte-identical at the IR level**
(`CStr` lowers to `ptr`; the `=` emits the same `strcmp`+`icmp`). So the migration
is provable: snapshot `build/nucleusc.ll`, migrate, rebuild, `diff`. A non-zero diff
is a regression — most commonly a both-`ptr` comparison that lost its strcmp (a
`< call @strcmp` / `> icmp eq ptr` hunk) because neither operand ended up `CStr`;
fix by giving one side a `CStr` type. `make bootstrap` (stage1==stage2) does **not**
catch this (both stages share the change); the before/after IR diff does.

## Member access is head position `(s field)`; `_get` is the bypass primitive

The `.` field-access special form was renamed **`_get`** (compiler-internal
primitive; `emit-field-get`) and ordinary code uses **head position `(s field)`**
instead (the callable-values `get` path: Struct-blanket intrinsic, byte-identical
GEP+load). `.set!` is unchanged (writes stay `(.set! s f v)`). Two non-obvious
hazards — both bit the `.`→head-position migration and are why `_get` still exists:

- **A user `get` method must read its own fields with `_get`, not head position.**
  `(self field)` inside a `(defn get … (self:ptr:T sel))` dispatches back into that
  same `get` method → infinite recursion → segfault. Use `(_get self field)` (direct,
  bypasses the override). Head position respects user `get` overrides; `_get` skips them.
- **A struct held in a variable named like a special form or macro collides.**
  `(cond field)` parses as the `cond` special form (special forms/macros are
  dispatched before scope lookup). Fix by renaming the variable (preferred) or using
  `(_get cond field)`. **Functions don't collide** — a local shadows them in scope
  lookup, so `(localvar field)` is member access even if a function shares the name.
  The migration script special-cases reserved-named *direct* heads (`(. cond f)` →
  `(_get cond f)`); a reserved-named **`->` base** (`(-> cond … (. type))`) is not
  caught and must be renamed.

The `->` macro (`lib/macros.nuc`) was extended to substitute `_` in **head**
position (it scans the whole form, not just args), so a threaded value can land in
call position: `(-> s (_ field))` ⇒ `(s field)`. The migration rewrites a 1-arg
`->`-step `(. field)` to `(_ field)` and a normal `(. s field)` to `(s field)`.

## C interop invariant

All Nucleus types must be representable in C. This is a core design requirement — Nucleus is a drop-in replacement for C, and any function or data structure defined in Nucleus must be consumable from C. If you encounter or are asked to create a type that cannot be represented as a C struct/function/enum (e.g. closures with hidden captured environments, tagged unions requiring runtime support), flag it as a design violation before proceeding.

## Stage 10 pointer-kind conversion gotchas (N2)

When converting a function or binding from `(ptr T)` to `(ref T)` / `?T`
(design/stage10/nullability.md §6), three recurring constraints:

- **`die-at` is not known to be noreturn.** A `(when (= x null) (die-at …))`
  guard does **not** narrow `x` past the guard — narrowing accumulates only
  when the guard body visibly terminates (`return`/`goto`). Restructure such
  sites to `(if-some (x m) then (die-at …))` instead. (A future `noreturn`
  attribute would make the guard idiom work as-is.)
- **Prelude types can't appear in `src/nucleusc.nuc` defn signatures.** The
  toplevel signature prescan parses types before `(import prelude)` is
  processed, so `ref:Node` / `?Node` in a *signature* dies with
  "unknown type: Node" at line 0. Bodies are fine; lib/*.nuc files are fine
  (their prescan runs at import time, after the prelude).
- **`type-eq` compares pointer elems, so mixed cond/if joins collapse.**
  Joining a bare `ptr` value with a `(ref T)`/`(ptr T)` value in a value
  position `if`/`cond` collapses the phi to void (pre-existing rule); if the
  result is used, you get a malformed-IR clang error or a flow-check error.
  Fix by giving the other branch's binding its real element type — never by
  casting the `ref` side back to bare `ptr`.

## `(Maybe ptr)` is niche-encoded — cannot use `match` on it

When the element type of `Maybe` is a pointer kind (`TY-PTR`), the compiler
niche-encodes `(Maybe ptr:T)` as a nullable pointer (no tag word, null = none).
This means `match` cannot be used on it — match expects a tagged sum. Use
`i32` or `i64` as iterator element types and `match` normally. If you need a
nullable pointer specifically, use `if-some`/`when-some`/`unwrap`/`unwrap-or`.

## `macros.nuc` is auto-imported — adding macros shifts the string pool

`lib/macros.nuc` is transitively auto-imported into **every** compilation
including the compiler itself (via `lib/prelude.nuc`). Adding new macro
definitions (with quasiquote string literals like `"let"`, `"i32"`, etc.) shifts
the compiler's internal string pool numbering. This causes a spurious bootstrap
diff that has nothing to do with correctness. Convergence requires two passes:
1. `make update-bootstrap` — install the new compiler binary as the new boot artifact
2. `make clean && make` — rebuild from the new boot so stage1 == stage2
Then `make bootstrap` passes. The `make bootstrap` target diffs stage1 vs stage2,
not the new binary vs old boot.

## `(Vector ptr)` cannot be iterated with `doseq` or combinators

All compiler registries are `(Vector ptr)`. The element type `ptr` causes
`(Maybe ptr)` niche-encoding (see the `(Maybe ptr)` section above). Since
`match` cannot handle niche-encoded types, `doseq`, `for-each`, `find`, `any?`,
`every?`, `reduce`, and all other combinators that use `(match (next it) …)`
internally will **crash at runtime** with "match: scrutinee must be a defunion
value" when driven over a `(VecIter ptr)`.

**For `(Vector ptr)` loops in `src/` compiler code: use `dotimes` only.**

For Node* linked-list loops (AST cdr-lists): `ListIter` yields `i64` which IS
matchable — `doseq-iter` + `list-iter` works correctly there.

## `dotimes` conversion gotchas (R3 compiler-loop refactor)

A trap recurs when converting a counted `(let (i:i32 0) (while (< i n) … (inc! i)))`
to `(dotimes (i:i32 n) …)` in `src/` compiler code:

   **A trailing `(return X)` must land OUTSIDE the dotimes body.** For a find-shape
   loop ending `(return FOUND)` after the scan with `(return NOTFOUND)` after the
   loop, close the dotimes on the `(return FOUND)` line and put `(return NOTFOUND)`
   on its own line after. If you close one paren too few, `(return NOTFOUND)` lands
   *inside* the dotimes body and the function returns NOTFOUND on the first
   non-matching iteration — silently breaking every lookup (hit `generic-binds-for`,
   `lbl-find`, `enumdef-lookup` during R3). The textual-IR signature is a missing
   `inc!`/`br-loop-back` immediately before a spurious `ret`.

A same-shape swap (zero start, unit stride, `inc!` last) expands to byte-identical
IR — no `make update-bootstrap` needed. Loops starting at non-zero, with non-unit
stride, or with `inc!` not last do **not** fit `dotimes`; leave them imperative.
`return` inside a `dotimes` body works (it expands to a `while`), so early-return
find loops convert fine — just mind the gotcha.
