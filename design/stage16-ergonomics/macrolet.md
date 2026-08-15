# macrolet — lexically scoped macros

Stage 16, item 1. Status: **DONE** (2026-08-15). 721 tests (was 704), `make
bootstrap` converges, 146 example programs emit byte-identical IR.

Implementation notes and the three pre-existing bugs it surfaced are in §11.

## 1. Goal

`let`, but for macros. A macro whose expansion deliberately captures names from
the surrounding code is the most reliable way to abstract a repeated pattern —
but `defmacro` is global, and a globally-visible macro that only makes sense
inside one function body is a name-space cost paid for a local convenience.
`macrolet` binds a macro over a body and nowhere else.

```nucleus
(defn sum-fields ((p (ref Point))):i32
  (let (total:i32 0)
    (macrolet ((take (f) `(set! total (_+ total (. p ~f)))))
      (take x)
      (take y))
    total))
```

`take` names `total` and `p` — locals of the enclosing function. It is
deliberate capture: the macro is written *for* this body, so it is spelled
inside it.

## 2. Syntax

```
(macrolet (BINDING BINDING ...) BODY-FORM ...)

BINDING ::= (NAME (PARAM ...) MACRO-BODY-FORM ...)
```

Common Lisp's shape, and the same shape as `defmacro` minus the head symbol.
The nested binding list (rather than Nucleus `let`'s flat one) is forced by a
binding having three parts, not two.

`&rest` works exactly as in `defmacro` — the parameter list is parsed by the
same code.

## 3. Semantics

**Scope.** A binding is visible from its own definition to the end of the
`macrolet` body, and nowhere else. Emission is a tree walk, so "dynamically
scoped over the emission of the body" and "lexically scoped over the body" are
the same set of forms.

**Sequential, like `let`.** Nucleus `let` is sequential (`emit-let` defines
into the inner scope as it goes, so a later initializer sees an earlier
binding). `macrolet` matches: the second binding's body is compiled with the
first already visible. This diverges from Common Lisp, where `macrolet`
bindings are parallel and `flet`-like — the Nucleus rule is the one consistent
with the rest of the language.

**A binding is visible inside its own body**, matching `defmacro`, which
registers its `MacroDef` before compiling the body. This costs nothing: a
self-reference inside a quasiquote is data, and expands at the call site.

**Shadowing.** A `macrolet` name shadows a global macro, a function, or a local
of the same spelling in head position — `emit-list` consults the macro table
before anything else, so this falls out. It may **not** shadow a special form
(§6).

**Capture.** No hygiene, exactly as `defmacro`: names in the expansion resolve
at the call site. `gensym` is available in a `macrolet` body for the cases that
want a fresh name.

**No new runtime scope.** `macrolet` emits its body like `do` — same value
(the last form's), same `g-want-type` re-arm for the tail form. It introduces
no `Scope`, so `let`/`defer` inside it behave as they would inside a `do`.

## 4. Why not a `defmacro` desugar

Because top-level dispatch does not expand user macros, and a definer is a
top-level form (conventions.md, "Top-level dispatch does not expand user
macros"). More to the point, the whole feature *is* the scoping — a desugar to
`defmacro` would put the name back in the global table.

## 5. Implementation

### 5.1 Split `emit-defmacro` in two

`emit-defmacro` (src/nucleusc.nuc:13454) currently does two jobs in one
function: it validates + registers a `MacroDef` in `g-macros`, then compiles
the body into a fresh JIT module. Split at the `; Flush main streams` line:

- **`emit-defmacro (form)`** — unchanged behaviour: parse, guard, register,
  then call the second half.
- **`compile-macro-body (mdef:(raw MacroDef) params-node:ptr pnames:ptr pcount:i32 form:(raw Node) body-start:i32)`**
  — everything from the flush to `jit-add-module`.

`macrolet` builds its own `MacroDef`, does **not** append it to `g-macros`, and
calls `compile-macro-body` directly. Two callers of one function, not two
copies — the shape conventions.md keeps asking for.

Keep the `priv`/`g-defining-private` write in the *registration* half: inside a
`defn-` body `g-defining-private` is still 1 (the top-level dispatcher sets it
around the whole `emit-defn` call), and a `macrolet` binding has no privacy —
it has no reachable name at all.

### 5.2 The re-entrancy problem

`compile-macro-body` calls `reset-function-state`, which clobbers
`g-entry-stream`/`g-body-stream` — the streams the *enclosing* function is
being emitted into. This is the same hazard as
conventions.md's "Emitting a function mid-emission needs the worklist, not a
direct `emit-defn`", but the worklist answer does not apply: a `macrolet`'s
macro must exist *before* the body it scopes over is emitted, so it cannot be
deferred to a drain.

The answer is to make the per-function codegen state save/restorable. Add,
**immediately below `reset-function-state` in src/scope.nuc** so the two drift
together:

```nucleus
(defn push-function-state ():ref:FnState   ; snapshot only
(defn pop-function-state (s:ref:FnState):void
```

`FnState` (src/compiler-types.nuc) holds exactly what `reset-function-state`
writes, plus the three ambient argument-register globals and the want channel:

| field | why |
|---|---|
| `g-tmp`, `g-label`, `g-block-term` | counters/flags the inner body advances |
| `g-lbl-tbl`, `g-nundo` | per-function vectors |
| `g-cur-fname`, `g-fn-ret-abi`, `g-fn-sret-name`, `g-fn-ret-type` | current-function identity |
| `g-loop-depth` | `break`/`continue` depth |
| `g-entry-stream`/`-bufp`/`-sizep`, `g-body-stream`/`-bufp`/`-sizep` | the streams the outer function is mid-way through |
| `g-abi-gpr-left`, `g-abi-fpr-left`, `g-abi-varargs` | ambient argument-register budget (conventions.md, "Argument-register state is AMBIENT") — a `macrolet` in argument position sits mid-walk |
| `g-want-type` | target-typing channel |
| `g-form-line` | diagnostic attribution |

`push-function-state` snapshots and does **not** reset: `compile-macro-body`
opens its own entry/body streams, and resetting in both places opens a memstream
pair nothing closes. `compile-macro-body` `fclose`s and frees the pair it
created, so `pop-function-state` restores the outer ones over a cleanly torn
down inner pair. `g-out`, `g-decl-out`, `g-qq-used` and `g-macro-decls` are
already saved and restored inside the existing body-compilation code.

The alternative considered — a pre-pass that hoists every `macrolet` in a
top-level form and compiles its macros before emission begins — avoids
re-entrancy entirely, but keys compiled macros on node identity, cannot see a
`macrolet` produced by a macro expansion, and needs its own nesting-aware
ordering to let an inner binding use an outer one. The save/restore is smaller
and has no such holes; its one risk (an ambient global nobody remembered) is
contained by putting the pair next to `reset-function-state`.

### 5.3 The binding stack

```nucleus
(defvar (g-macrolet-stack (ref (Vector (ref MacroDef)))) …)
```

Scanned **back to front** (innermost binding wins) and consulted **before**
`g-macros`. Matching is on the bare spelling only: a `macrolet` binding is not
namespace-qualified, not exported, and not visible to `find-macro-exact`'s key
lookup.

`find-macro` (src/nucleusc.nuc:9930) gains one probe at the top:

```nucleus
(let (local:?ptr:MacroDef (find-macrolet spelling))
  (when (!= local null) (return local)))
```

That is the whole visibility change — `find-macro` is the macro registry's only
reader (conventions.md / Stage 15 B7), so one probe covers `emit-list`'s
dispatch, `node-type`, `gcheck`, `valid-walk` and the `BK-MACRO` name-kind
lookup at once. The redefinition guard uses `find-macro-exact` and is
deliberately untouched: a `macrolet` binding is not a redefinition of anything.

For a program with no `macrolet`, the probe is one `count == 0` test.

### 5.4 `emit-macrolet`

```
1. validate the form
2. for each binding, in order:
     build a MacroDef (name = bare spelling, jit-name = __macrolet_<name>_<id>)
     conj it onto g-macrolet-stack
     push-function-state
     compile-macro-body …
     pop-function-state
3. emit body forms like emit-do (want re-armed for the tail form)
4. remove-at the bindings from g-macrolet-stack, innermost first
5. return the last body form's Val
```

`jit-name` uniqueness comes from a monotonic `g-macrolet-id`, not from
`(count g-macros)` — these `MacroDef`s never enter `g-macros`, and a `macrolet`
inside a generic template body is compiled once per monomorphization.

### 5.5 Dispatch and lockstep

- `emit-list` (src/nucleusc.nuc): `(when (= hp 'macrolet) (return (emit-macrolet n scope)))`,
  placed with the other block forms near `do`/`let`.
- `g-special-form-set`: add `"macrolet"` — a reservation, so no `defn`/`defvar`
  may shadow it (conventions.md, "`g-special-form-set` is a RESERVATION, not
  the dispatcher").
- `node-type` (src/generics.nuc): add a `macrolet` arm returning **null**. The
  form's type is expansion-dependent, which is the documented escape hatch
  (`cond`, macros, `quasiquote`). This is the `node-type`↔`emit-node` lockstep
  edit and must land in the same change.
- `gcheck` / `valid-walk` (src/generics.nuc) reach a `macrolet` head as an
  unknown function today. Both already walk `let`/`with` specially; give
  `macrolet` an arm that walks the body forms and returns null. Without it a
  `macrolet` inside a generic template body dies "in generic body: unknown
  function 'macrolet'".
- **Not** a top-level form: `macrolet` is an expression, so the `case hp`
  dispatcher in `emit-toplevel-forms` gets no arm and a top-level `(macrolet …)`
  keeps dying "unknown top-level form", which is correct.

### 5.6 REPL

`g-macrolet-stack` must be empty at the start of every top-level form. `die-at`
exits the process in batch mode, so nothing can leak; the REPL's `repl_try`
recovery arm (src/repl.nuc:1010) longjmps past the pop, so **truncate the stack
to zero there**, beside the existing recovery work.

## 6. Diagnostics

| condition | message |
|---|---|
| fewer than 3 elements | `macrolet: expects a binding list and at least one body form` |
| binding list is not a list | `macrolet: bindings must be a list` |
| binding is not a list of ≥ 2 | `macrolet: binding must be (name (params) body...)` |
| name is not a symbol | `macrolet: macro name must be a symbol` |
| name has a `:type` | reuse `reject-colon-in-def-name` |
| params not a list | `macrolet: params must be a list` |
| param not a symbol | `macrolet: param must be a symbol` |
| name is a special form | `macrolet: '%s' is a special form and may not be shadowed` |

The special-form refusal matters more here than for `defmacro`: because the
macro table is consulted *before* special forms, a `macrolet` named `let` would
otherwise silently take over `let` for the whole body.

## 7. Out of scope for v1

- `symbol-macrolet` (no operand-position macro mechanism exists).
- `macroexpand` visibility of `macrolet` bindings from outside the body.
- Converting compiler source to use `macrolet` — that shifts the string pool
  and perturbs the bootstrap for no functional gain. Left as a follow-up.
- Reader macros (`def-rmacro`) remain global.

## 8. Tests

Landed as `run_s16_macrolet`, `run_s16_macrolet_refused` and `run_s16_atom_macro`
in `tests/run-tests.sh` (16 checks, fixtures written to a temp dir in the house
style), plus `examples/macrolet.nuc` + `tests/expected/macrolet.out` and the
`tests/repl/s16-macrolet.in` transcript. The behavioural programs return a
**bitmask of failed checks** as their exit code, so a regression names itself.
The plan they were built from:

1. **basic** — a `macrolet` macro capturing an enclosing `let` local, called twice.
2. **scope-ends** — the same name used after the `macrolet` body resolves to a
   global macro (or errors); proves the pop.
3. **shadowing** — a `macrolet` binding of a name that is also a global macro;
   inside, the local wins; outside, the global does.
4. **sequential** — binding 2's body uses binding 1's macro.
5. **nesting** — an inner `macrolet` rebinds an outer name; the outer is
   restored after the inner body.
6. **&rest** — a variadic `macrolet` macro.
7. **argument position** — `(f (macrolet (…) …))` inside a call with enough
   by-value struct arguments to prove the argument-register budget survives
   (the `push-function-state` ABI fields).
8. **inside a loop / inside `cond`** — proves the entry/body stream restore.
9. **diagnostics** — one fixture per row of §6 that the harness expects to fail.

Plus a REPL transcript in `tests/repl/` covering a `macrolet` and an error
inside one (the §5.6 truncate).

## 9. Gates — measured

- `make test`: **721 PASS, 0 FAIL** (704 before). 17 new tests.
- `make bootstrap`: **converges on the first attempt.** The two-pass
  string-pool refresh this section originally predicted was **not** needed —
  that procedure exists for a shift in `lib/macros.nuc`, which is auto-imported
  into every unit including the compiler's own boot artifact. Strings added to
  `src/nucleusc.nuc` itself shift only the compiler's own pool, and stage1 ==
  stage2 still holds because both stages compile the same source.
- **No IR change for programs that do not use `macrolet`**: all 146
  `examples/*.nuc` emit byte-identical IR under the old boot compiler and the
  new one.

## 10. Related

The `Node`-in-the-artifact problem raised alongside this item is **not** caused
by `defmacro` and is not on `macrolet`'s critical path — see
[compile-time-imports.md](compile-time-imports.md) for the measurement and the
design.

## 11. What implementation found

### 11.1 The design held, including the case that decided it

Every §5 decision survived contact. The one that earned its keep is §5.2's
choice of save/restore over a hoisting pre-pass: **a `macrolet` inside a
`defmacro` body works** — one macro JIT module compiled while another is
compiling — and a hoist keyed on node identity could not have served it without
its own nesting-aware ordering. `tests/run-tests.sh` pins it as
`s16-macrolet-in-defmacro`.

The other cases verified: argument position mid-ABI-walk (by-value structs of
both classes, `s16-macrolet-abi`), inside a `while` body, inside a `cond` arm,
inside a bounded-generic template body (compiled once per monomorphization —
which is why the `jit-name` counter is monotonic rather than a stack depth),
and in the REPL including the error-recovery path.

### 11.2 Three pre-existing bugs, all found through `macrolet`, all fixed

Each reproduced identically on the **stage-15 boot compiler**, so none is a
regression from this work. They are here because a small local macro makes each
one the common case rather than the exotic one.

**(a) A macro whose whole expansion is an ATOM emitted calls to undeclared
symbols.** `` (defmacro one () `1) `` died with LLVM `use of undefined value
'@alloc-node'`. `g-qq-used` — the flag gating the `declare`s for
`alloc-node`/`make-cell`/`intern-symbol` in a macro/CT JIT module — is set only
by `emit-qq-list`. But `emit-quote-tree`, which a plain `'x` and a quasiquoted
*atom* both reach, emits exactly those calls and never touches the
`__cons`/`__append` helpers `g-qq-used` is really about. One flag was answering
two questions.

Fix: `g-node-ctor-used`, set by `emit-quote-tree`, gates the three constructor
declares; `g-qq-used` keeps gating the `__cons`/`__append` *definitions* and
`@malloc` (only they need it). The program module is untouched either way — it
*defines* all three — which is why this is invisible outside a JIT module and
why the fix is IR-inert.

While there: the four hand-written `declare` lines now route through
`macro-jit-declare-raw`, which shares `g-macro-decls` with
`macro-jit-ensure-decl`. A macro body that both quotes *and* calls one of the
constructors by name would otherwise have emitted two `declare`s for one
symbol, which LLVM rejects.

**(b) A non-symbol macro parameter segfaulted the compiler.**
`(defmacro m (5) …)` crashed rather than diagnosing. The `&rest` scan read
`(vp s)` on a node it had only null-checked, and `Node.s` is null on an INT
node while the `=` beside it is a *content* compare — `strcmp(null, "&rest")`.
The comment above the loop already promised the located "param must be a
symbol" diagnostic that the crash pre-empted. Fixed by testing `NODE-SYM`
before touching `s`, in `macro-parse-params` — the function extracted for
`macrolet` to share, so one edit fixed both definers. That extraction paying
for itself immediately is the argument for §5.1's split.

**(c) A user `defmacro` typed at the REPL aborted the session.**
`Fatal error: glibc detected an invalid stdio handle`. `compile-macro-body`
opens with `fflush` of `g-type-stream`/`g-decl-stream`, and between REPL forms
those `FILE*`s are closed; the REPL's `defmacro` arm was missing the
`(open-module-streams)` call its `compile-time` neighbour makes for exactly
this reason. The prelude's own macros never hit it — they load through
`repl-preload-macros`, not that arm — which is why a REPL that can expand
`when` and `dotimes` still died on the first macro a user wrote.

### 11.3 One deviation from §6

The colon-in-name check is spelled out in `macrolet-bind` rather than routed
through `reject-colon-in-def-name`. The *rule* is not duplicated (both call
`split-typed`); only the suggested repair differs, because a `macrolet` binding
is a binding-list element and its fix is `(m (params) …)`, not
`(macrolet m …)`. The shared helper's message template hard-codes the
definer-name shape.
