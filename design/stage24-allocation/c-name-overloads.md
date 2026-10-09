# Stage 24 — AL-0a and AL-0b: two name collisions

Built 2026-10-07, uncommitted. These are the two bugs that
[overview.md](overview.md) §2.1 and §2.5 found while it was designing
allocation. Both were fixed at their cause. Neither fix renames anything in the
library.

## 1. AL-0a — a user `init` broke `for` and `dotimes`

**Symptom.** Any program that defined `init` and used `for` (or `dotimes`, which
expands to `for`) failed with
`lib/nucleus/macros.nuc:180: error: macro 'for' calls 'init', which is defined later in this unit`.

**Cause.** `for` is `` `(let ~init (while ~test ~body ~step)) ``, and its
`init` is a macro parameter. Quasiquote hygiene (`qq-resolve`) rewrites a
template's free names to full names, and it handles binder slots separately in
`qq-resolve-binders`, which treats `let`'s second element as a binding list. In
`for` that element is not a list of bindings. It is the form `(unquote init)`.
`qq-resolve-binders` walked it with stride 2: `unquote` sat in the name
position, and `init` sat in the value position, where it was resolved like an
expression. The `user` namespace is flattened into every file, so a user `init`
made the name resolvable, and it was rewritten to `user/init`. The template
became `(let (unquote user/init) …)`. The body then referred to a
function instead of to its own parameter.

**Why "defined later" was wrong.** The macro body never calls `init`. The
parameter is a local of the macro function. The rewritten `user/init` is a
reference to the user's function, which does sit later in the unit than the
prelude's `defmacro for`, because `macros.nuc` is emitted first. The diagnostic
reported, correctly, a reference that hygiene had invented. The rule in
docs/macros.md, that a name under an unquote is left alone, already covered
this case. The binder-slot path just didn't follow it.

**Fix** (`src/nucleusc.nuc`). `qq-escaped?` says whether a node is a `quote`,
`unquote` or `unquote-splice` form. `qq-resolve-binders`, `qq-check-binder` and
`qq-check-binder-list` return early on one. An unquoted binder slot is the
caller's code, as any unquote is.

**Test.** `s24-user-init-and-core-loops` defines user `init` and `params`
functions. It uses `for`, `dotimes`, and two local macros that unquote a binder
slot (`` `(let ~init …) `` and `` `(fn ~params …) ``).

## 2. AL-0b — a `defn` named after a C function replaced it

**Symptom.** A struct method `(defn free (self:&Box):void …)` in a unit that
also includes `stdlib.h` (and the prelude does) became the program's `@free`.
Every libc `free` call in the unit, the library's included, went to it, or
failed arity checking.

**Cause.** Two registries answer a name: `g-globals` (one `Sym` per key) and
`g-generics` (the overloads). The C header registers `free` in `g-globals` only.
A `defn free` registers a method. With one method the generic is solitary, and
`finalize-generics` binds the key to it, so the `defn` took the key. A solitary
generic also emits under its plain name, so it took the symbol `@free` too.
CL-3's link-claim check then saw a definition of a symbol that C declares, and
it treated that as the program implementing the declaration. A
`(defn puts (s:i64):i64 …)` was refused for a signature mismatch.

### 2.1 Design: the C function is one more overload

When a generic of the C function's name exists, and no user method *implements*
the C declaration, the C function joins the generic as a method. That method is
`ir-fixed` with ir-name `@fname`, and the new field `Method.c-decl` is true. The
generic now has at least two methods, so it is mangled: every Nucleus method gets
a mangled symbol, and `@free` stays libc's.

**What implements a declaration** (`c-implements?`, `c-impl-slot?`). The
method is a plain `defn` (`METHOD-USER`, not a template stamp) in the user
symbol space (`method-ir-prefix` equals the user prefix, so a namespaced
library can never implement it). Its arity and variadic flag match. Each slot,
the return type included, matches as a Nucleus program would write it:
`slot-type-compat`, except that a C `void *` must be written as a bare `ptr`.
Comparing link signatures was tried first and is wrong: `free (self:&Box)`
links as `void (ptr)`, exactly like libc `free`. `(defn puts (s:CStr):int …)`
still implements `@puts`, which keeps the CL-3 meaning of a matching definition.

**Routing.**
- *A call only one `defn` can take by arity* goes the solitary way
  (`generic-c-sole-at-arity`, from `emit-dispatch`'s mangled branch). It gets
  the same lax conversions, arity check and target typing as before the C
  function joined. Without this, the user's own 4-argument
  `(free &h null 0 0)` failed: strict tiers do not adapt a literal `0` to
  `usize`. `node-type-call` mirrors the branch, which is the node-type↔emit
  lockstep.
- *Same-arity candidates* use the ordinary tiers. The C method ranks after them
  as `generic-resolve`'s last resort (`generic-c-fallback`). It takes what no
  `defn` claimed, through `emit-call` with C's own argument conversions
  (`emit-resolved-call` returns early for a `c-decl` method).
- `method-call-sym` hands back the header's own `Sym`, which carries the
  `noreturn`/`returns_twice` flags, when the ir-names agree.

**The two orders.**
- *C first, then the defn* (the W1a prescan registers every `defn` signature
  before any import is emitted). `c-finish-fn-decl` (`src/cheader.nuc`) calls
  `generic-adopt-c-fn` before its "already bound?" check, then re-finalizes,
  and registers the key for the C `Sym` as usual.
- *A macro-made `defn` after the header bound the key.* `finalize-generics`
  calls `generic-adopt-bound-c-fn`, which rebuilds the C signature from the
  bound `Sym` and adopts it before the generic takes the key.
- *An explicit `declare`* (`src/nuch.nuc`, `nuch-declare-import`) adopts the
  same way for a `.nuc` file in the user namespace. `cheader-yield-to-explicit-declare`
  now treats a key held by a Nucleus `defn` as unbound
  (`defn-holds-key?`), so the declaration still takes effect.

**Where it does not apply.**
- *The REPL.* It has no overloads, and a `defn` of a bound name is a
  redefinition there. Adoption in the late hook broke the redefinition thunk
  (`lookup of free.impl.0 failed`), so `generic-adopt-bound-c-fn` returns
  early under `g-interactive`. The CL-3 signature refusal still applies there.
- *A header included after a colliding `defn` was already emitted.*
  `link-claim-find` shows that a Nucleus definition holds the symbol, and
  adoption declines, so the old behaviour stands.
- *A `.nuch` declare.* Item 36 keeps a `.nuch` binding authoritative, so it is
  not adopted.

### 2.2 Measurements

- The IR of all 502 examples, tests and fixtures matched HEAD's, and the
  compiler's own IR was unchanged. No boot refresh was needed. No program in
  the tree had a colliding name that compiled before, because every collision
  was an error or a silent misroute.
- The suite had 1350 tests: 1345 passed, and 5 failed. The 5 are the
  `suite-target` datalayout tests that fail under the container's LLVM 23.
  `make bootstrap` reached its fixed point.
- `cl3-c-declaration-signature` changed by design. `(defn puts (s:i64):i64 …)`
  is now an overload beside C's `puts`, where it used to be refused.

### 2.3 Tests

- `s24-c-name-overloads`:
  - a 4-argument `Heap` `free`, a 1-argument `Box` `free`, a macro-made `realloc`
    (the late order), and a `Box` `remove`;
  - libc `malloc`/`realloc`/`free`/`remove`, and a `Vector` that grows through
    the library's own `realloc`/`free`;
  - an IR check that `@free` and `@realloc` are declared and not defined.
- `s24-c-name-overload-declare`: an explicit `(declare free …)` beside a `Box`
  `free`.
- `s24-c-name-overload-namespaced`: a namespaced library whose `free` method
  calls libc `free`, and whose template `remove` sits beside libc `remove`.

The first two fail on the HEAD compiler. On HEAD the namespaced case fails with
`call to 'nsheap/free': expected 2 args, got 1`.

### 2.4 Consequences

- `HashSet`'s `set-remove` no longer needs its name for this reason. The
  workaround notes in docs/collections.md and `lib/nucleus/hashset.nuc` are
  gone. The name stays as it is.
- AL-1 can call allocator methods `free`/`realloc` without breaking libc.
  It still renames them to `allocate`/`reallocate`/`deallocate` (Q3), because
  that naming is clearer, not because the collision forces it.
- `init` is safe as a protocol method name (AL-2). A library template that
  quotes it as data resolves it through hygiene to the protocol's namespace,
  and a caller's unquoted binder is no longer touched.
