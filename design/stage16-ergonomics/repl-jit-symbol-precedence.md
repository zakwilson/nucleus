# JIT symbol precedence in the REPL

*Closes the last item [repl-libraries.md](repl-libraries.md) §6 left open:
`(import-use node)` at the prompt failed with `Duplicate definition of symbol`.*

## 1. The item as filed

§6 recorded the symptom and the `nm -D` evidence — the compiler is linked
`-rdynamic`, so its own copies of the node runtime are exported — and named two
candidate fixes without designing either:

> the fix is a definition generator that prefers the module's own definitions,
> or a REPL that declares rather than defines a function the host already
> exports

It filed the item as a JIT symbol-resolution question rather than an import
question. That framing was right. The diagnosis underneath it was not: the
problem is not that the host exports those symbols, and not that ORC prefers
them. **It is that the compiler asks ORC to reflect them into the wrong
JITDylib.**

## 2. The mechanism, measured

`jit-ensure-init` (`src/nucleusc.nuc`) created an LLJIT and then attached a
process-symbol generator to the **main** JITDylib:

```
(LLVMOrcCreateDynamicLibrarySearchGeneratorForProcess (addr-of gen) prefix null null)
(LLVMOrcJITDylibAddGenerator g-jit-dylib gen)
```

A `DynamicLibrarySearchGenerator` does not merely *resolve* a symbol; when it
fires it **defines** the symbol, as an absolute address, in the JITDylib it is
attached to. So the first lookup that reaches an unresolved `alloc-node` — which
in a REPL session is a macro module materialising during the prelude preload —
permanently claims `alloc-node` *in main*. Every later module that **defines**
`alloc-node` is then a redefinition, and `LLVMOrcLLJITAddLLVMIRModule` rejects it:

```
<repl>:1: JIT error in AddLLVMIRModule: Duplicate definition of symbol 'alloc-node'
```

Four probes against the real LLVM 19.1.7 in this container
(`scratchpad/orc_probe.c`, built against `llvm-config --cflags/--libs`) pin each
step:

| probe | setup | result |
|---|---|---|
| A | reflect `probe_target`, then add a module defining it | `Duplicate definition of symbol 'probe_target'` |
| B | add the defining module first, then the using one | both bind to the module's definition (99, not the process's 41) |
| C | attach the generator **with** a `LLVMOrcSymbolPredicate` filter | filter is called **once per looked-up symbol**, per generate attempt — it is a live, per-lookup hook, not a construction-time one |
| D | flip the filter to hide the name between the two adds | the module defines it, and the earlier module — not yet materialised — binds to the module's copy |

So the filter argument the item's first candidate fix would need **does exist and
is consulted per lookup**. It was not needed.

### The generator was redundant

Probe E hid `probe_target` from the filter unconditionally, expecting the lookup
to fail. It resolved anyway. A fifth probe with **no explicit generator at all**
(`scratchpad/orc_probe2.c`) explains why:

```
== NO explicit generator at all ==
  uses: added ok
  lookup uses_it -> 41          <- a process symbol, resolved
  lookup uses_libc -> 6         <- puts(), resolved
  defines: added ok             <- NO duplicate-definition error
  lookup calls_own -> 99        <- the module's own definition wins
```

`LLJITBuilderState` carries `LinkProcessSymbolsByDefault = true`
(`llvm/ExecutionEngine/Orc/LLJIT.h`), and its setter documents the contract
exactly:

> If true, the Process JITDylib will be added as the **last item in the default
> link order**.

LLJIT therefore already creates a `<Process Symbols>` JITDylib with a process
search generator and links main against it **last**. Reflection lands *there*,
never in main, so main stays free to define whatever it likes and its own
definitions win. The compiler's extra generator was a second, redundant copy of
a facility LLJIT provides — attached to the one JITDylib where it does harm.

`-rdynamic` remains load-bearing exactly as
[compile-time-imports.md](compile-time-imports.md) §9 says. Rebuilding the same
probe without it:

```
JIT session error: Symbols not found: [ probe_target ]
```

The process JITDylib reflects the dynamic symbol table; nothing about this change
touches that.

## 3. The two candidates, evaluated

**(a) "A definition generator that prefers the module's own definitions."**
Chosen — but it is a *deletion*, not a new generator. ORC already prefers a
JITDylib's own definitions over anything in its link order; the compiler was
defeating that by injecting process definitions into the dylib doing the
preferring. A filtered generator (probes C/D) could have been made to work, but
it would need to know, before the fact, every name the session will later define
— and it would be re-implementing, with a hand-maintained name set, the
precedence LLJIT gives for free.

**(b) "A REPL that declares rather than defines a function the host already
exports."** Rejected as the primary fix, for a reason worth stating because it
is not obvious: the discriminator would have to be `dlsym` on the emitted
symbol name, and that question is *not* the question we mean. It cannot
distinguish "this is `lib/node.nuc`, which the compiler links, so it is
literally the same code" from "this user's library happens to define a function
named `emit-defn`". The first is what we want; the second silently binds a
user's function to a compiler internal **with a different signature**, which is
ABI corruption rather than a diagnosable error. Today that same collision is a
loud `Duplicate definition`. Trading a loud failure for a silent miscompile is
the wrong direction, so (b) is not available as a *general* rule.

(b) is, however, exactly right for a *specific* library — see §5.

## 4. What landed

One deletion in `jit-ensure-init` (`src/nucleusc.nuc`): the
`LLVMOrcCreateDynamicLibrarySearchGeneratorForProcess` /
`LLVMOrcJITDylibAddGenerator` pair, replaced by the comment that explains why
there is nothing there. `g-jit-dylib` is still set from
`LLVMOrcLLJITGetMainJITDylib`.

The three `.nuch` declarations (`src/llvm.nuch:24-26`) are left in place: they
declare real LLVM entry points, an unreferenced `declare` costs nothing in a
program's IR, and the filter argument is the natural hook if §5's follow-up ever
wants a custom generator.

**Result at the prompt.** `(import-use node)` loads; `'a` and `'(a b)`
evaluate; `node-len`, `make-cell` and friends are callable. All **34** modules
in `lib/` now import in a fresh session, where `context/repl.md` previously
recorded 33 of 34 with `node` as the exception.

**Version dependency, stated honestly.** This relies on
`LinkProcessSymbolsByDefault`, present since LLVM 17 and in the 19/20/21 range
the Makefile probes for. There is no C API to query it. If a future LLVM dropped
it, the failure mode is loud and immediate — the first `compile-time` block in
any batch compile would fail to find `printf` — not silent.

## 5. What the fix implies, and the residual it exposes

The choice is: **in the REPL, a name the session defines wins over the same name
in the host compiler.** That is the right default — a prompt-typed
`(defn emit-node …)` must be the user's function, not the compiler's — and it is
what the prelude preload has already relied on since R2, because the session
defines its own copy of `lib/prelude.nuc` and `lib/macros.nuc` every time it
starts.

It is *not* right for one class of library: **one whose state the compiler's own
correctness depends on.** `lib/node.nuc` is the only such library, and the
dependence is interning. From conventions.md:

> Interning is not removable: symbol identity is compared **by pointer**
> throughout the compiler (`(= n 'null)`, `(= head 'label)`, the special-form
> `case hp` dispatch)

`emit-node` dispatches every special form as `(when (= hp 'cond) …)` — a pointer
compare against a symbol the *compiler's* `intern-symbol` minted. After
`(import-use node)`, main defines `intern-symbol`, so a macro JIT module
materialised afterwards calls the **session's** copy, backed by the session's
`g-intern-table`. A `cond` from that second table is a different pointer:

```
nuc> (import-use node)
  imported node
nuc> (defmacro mc (a) `(cond (> ~a 5) 111 true 222))
  defined
nuc> (mc 9)
<repl>:1: error: unknown: cond — not defined anywhere in this compilation unit
```

The residual is precisely: **a macro whose JIT module is first materialised
after `(import-use node)`, and whose expansion has a special-form head, is not
recognised.** Three bounds, all measured and pinned by
`tests/repl/host-runtime.in`:

* It is **loud**. The failure is `unknown: <form>` at the call site, never a
  silent misexpansion, because the head simply falls through every arm.
* It is confined to **special-form heads**. A function head is resolved by
  spelling (`find-macro h:CStr`, then the scope lookup), so `(-> 3 (+ 4))` and a
  `` `(+ ~a ~b) `` macro are unaffected.
* ORC materialisation is lazy and one-shot, so a macro **already expanded**
  before the import keeps working across it — `(case 1 1 101 999)` before the
  import still answers after it.

This is not a regression: before this change `(import-use node)` could not be
evaluated at all, so none of it was reachable. It is the next item on the same
path, and it has a different root cause — pointer identity of interned symbols
across the JIT boundary, not symbol precedence.

### The fork for closing it

The requirement is one sentence: **`intern-symbol` must be a process singleton.**
Three routes, in increasing cost:

1. **Register-and-declare import for the host's own runtime.** The REPL treats
   `lib/node.nuc` the way `repl-include-all-libc` already treats libc: the host
   binary provides the definitions, so the session registers node's names and
   emits `declare`s instead of `define`s. This is candidate (b) from §3, scoped
   to the one library where it is not a heuristic — the compiler *is* the node
   runtime, structurally, not incidentally. Needs a seventh ABI-lowered
   `declare` emitter (conventions.md counts six and records that three had
   silently drifted), so it is not free.
2. **A JITDylib for macro/CT modules.** Give them a bare dylib whose search
   order is host-first, session-second. The C API has no `setLinkOrder`, so the
   session half needs `LLVMOrcCreateCustomCAPIDefinitionGenerator` plus
   `LLVMOrcAbsoluteSymbols` over a by-value `LLVMOrcCSymbolMapPair` array. It is
   the most general answer and by far the most machinery.
3. **Host-pinned aliases.** `jit-ensure-init` defines `@__host.intern-symbol`
   (etc.) as absolute symbols at the compiler's own addresses, and quasiquote
   lowering emits those names when it is emitting into a macro/CT module.
   Cheaper than (2), but it puts a spelling rule into the emitter and touches
   the `node-type`/`emit-node` neighbourhood.

Route 1 is the recommendation: it is the smallest, it states a true fact about
the compiler rather than a heuristic, and it makes the session's node runtime
*be* the compiler's — which is what a user who imports `node` at the prompt in
order to write macros actually wants.

## 6. Gates

* `make test` — **913 PASS / 0 FAIL** (was 912; the one new unit is
  `repl-host-runtime`).
* **Batch neutrality.** Baseline compiler built from HEAD's source minus this
  edit (the committed boot is a fixed point but carries the `src/nucleusc.nuc`
  path in its `ModuleID`, so it is not directly diffable). `--emit-llvm` over
  153 `examples/*.nuc` + 34 `lib/*.nuc`, comparing `.ll`, stderr **and** exit
  code: **187/187 byte-identical**. `--emit-nuch` + `--emit-cheader` over 34
  `lib/` + 14 `src/` modules: **96/96 identical**. (187 and 96 still, but the
  split is 153/34 and 34/14 now — repl-libraries.md §D9a's 152/35 and 35/13
  were the tree as it stood then.)
* `make bootstrap` converges; the compiler's own IR moved (one string constant
  removed, which renumbers the pool below it), so `make update-bootstrap` ran
  and the new fixed point is confirmed — `build/nucleusc.ll` equals
  `boot/nucleusc.ll` and stage1 equals stage2.
* `make abi-test`, `make layout-test`, `make check-headers` (69/69),
  `make avr-test` (8/8) all green.
