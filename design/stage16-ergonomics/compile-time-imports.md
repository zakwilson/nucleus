# Compile-time-only imports

Stage 16. Status: **design note, measured, not implemented** (2026-08-15).

Raised in [overview.md](overview.md) alongside `macrolet` as "the current
inability to define macros without pulling `Node` and friends into built
artifacts and runtime memory".

## 1. The premise needs correcting

Defining a macro is not what pulls `Node` in. **Every** program pulls it in.

Measured with the stage-15 compiler (`bin/nucleusc`, x86_64), two programs that
differ only by a `defmacro`:

```nucleus
; with-macro.nuc                     ; no-macro.nuc
(defmacro twice (x) `(_+ ~x ~x))
(defn main ():i32                    (defn main ():i32
  (let (a:i32 21) (return (twice a))))  (let (a:i32 21) (return (_+ a a))))
```

| | `define`s emitted | IR lines |
|---|---|---|
| with the macro | 17 | 1119 |
| without the macro | 17 | 1118 |

Both emit the same sixteen library functions:

```
arena-init  arena-grow  arena-alloc  arena-strndup  arena-strdup
alloc-node  make-cell   intern-hash  intern-raw-insert  intern-grow
intern-symbol  node-at  node-len  node-line  node-is-list  node-kind
```

They survive linking (`nm` on the linked binary still shows `alloc-node`,
`make-cell`, `intern-symbol`, `arena-alloc` as `W`) — nothing is
garbage-collected, because the emitted linkage is `weak_odr` and the link line
uses neither `-ffunction-sections` nor `--gc-sections`. A trivial `main` costs
4569 bytes of `.text`.

The cause is `lib/prelude.nuc`'s unconditional `(import-use node)`, not
`defmacro`.

## 2. What compile time actually needs

A macro body compiled by `emit-defmacro` becomes its own JIT module. That module
carries `declare`s for `@alloc-node`, `@make-cell`, `@intern-symbol` and
resolves them **against the compiler process** through the ORC dylib generator —
which is exactly why the main module's globals are deliberately kept out of it
(src/nucleusc.nuc, the `defvar` arm's comment: "CT and macro JIT modules pull in
`g-decl-bufp` but not `g-def-bufp` … otherwise prelude globals (from node /
arena / intern table) would duplicate across modules").

So the program's own copies of `alloc-node`/`make-cell`/`intern-symbol` are
**never used at compile time**. They are needed at run time only by a program
that evaluates `'sym` or a quasiquote in emitted code — `emit-quote` lowers
those to calls.

That is the whole shape of the problem: the prelude bundles a compile-time-only
capability (the `Node` type, `lib/macros.nuc`, the constructors JIT'd macro
bodies call *in the compiler*) with a runtime one (the arena, the intern table,
the constructors emitted code calls *in the program*), and there is no way to
ask for the first alone.

## 3. Why it matters

`(exclude-prelude)` is the only current escape, and it is all-or-nothing:
`examples/avr-blink.nuc` takes it and thereby gives up `if`, `when`, `unless`,
the variadic arithmetic operators and `->` as well. Its own comment states the
constraint — the prelude's node/arena/intern runtime "references host-only libc
(`perror`/`malloc`) absent from freestanding avr-libc, so it would fail to
link".

An AVR part with 2 KB of flash cannot spend 4.5 KB on an intern table it never
reaches. Today the choice is "no macros at all" or "no AVR".

## 4. Options

**(a) A compile-time-only import form** — `(import-ct <lib>)`: register types,
signatures and macros; emit nothing. The register/emit split already exists and
is already understood — `.nuch` imports are exactly "REGISTER + EMIT, split by
mode" (conventions.md, "A `.nuch` import is REGISTER + EMIT — split it by mode,
and prove registration before emitting alone"). This is the form the overview
asks for, and it is the one that composes: any library can be imported for its
compile-time surface alone.

The catch is that it is a *promise the program must keep*: a program that
`import-ct`s `node` and then writes `'foo` has no `intern-symbol` to call. That
needs a diagnostic at the use, not a link error — `emit-quote` (and the
quasiquote lowering) must refuse when the constructors were registered
compile-time-only.

**(b) Split the prelude.** Independent of (a), and probably wanted anyway:
`Node`/`NodeKind`/`StrView` are type definitions that emit no IR, and
`lib/macros.nuc` emits no IR either (a `defmacro` produces a JIT module, not
program text). Only `lib/node.nuc` + `lib/arena.nuc` are runtime. A prelude that
imports the first group unconditionally and the second only on demand fixes the
measured case without any new user-facing form.

**(c) Demand-driven emission** — emit an imported library's `defn` only if
something references it. The most general answer and the largest change; it also
walks straight into the class conventions.md warns about twice (a pre-pass that
mirrors an emitter must mirror its skips; a non-emitting mode inherits none of
the emitter's diagnoses). Not recommended as the first step.

**(d) `-ffunction-sections -Wl,--gc-sections` in `build.sh`.** Not a language
feature and does not help the AVR link (the undefined host-libc references go
away with the sections, but only after the emitter has already produced them),
yet it is a few lines and would shrink every hosted binary. Worth doing
regardless of which of (a)–(c) is chosen.

## 5. Recommendation

**(b) then (a).** Splitting the prelude is a contained change that fixes the
measured regression for every program, needs no new syntax, and is a
prerequisite for (a) being useful (there is no point importing `node`
compile-time-only if the prelude has already imported it for real). `(import-ct
…)` then generalizes it, and carries the §4(a) diagnostic obligation.

(d) can land at any time and is independent.

## 6. Relationship to `macrolet`

None on the critical path. `macrolet` inherits `defmacro`'s compile-time
requirements exactly — the same `Node` type, the same JIT'd constructors in the
compiler process — so it neither worsens nor is blocked by this. The overview's
note that `macrolet` "may need a compile-time guard to ensure `Node` is
available" resolves to: it needs precisely what `defmacro` already needs, and
under `(exclude-prelude)` both are equally unavailable.
