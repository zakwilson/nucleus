Nucleus is a replacement for C using Lisp style syntax and macros with LLVM as its target. It is a low level systems programming language meant to manipulate memory directly, and when required, unsafely.

## Goals

### True drop-in substitute for C

- Zero mandatory runtime overhead relative to C
- C interop - include C libraries and call C functions with no overhead
- Use C structs and arrays natively

### Lisp syntax

- The language is written as a direct representation of linked lists of symbols, numbers, and strings
- Reader macros add syntactic sugar for things like dereferencing pointers
- User-defined reader macros will be possible
- A vector type like Clojure could be useful, or at least improve readability
- Member access for arrays and structs by calling them like functions - maybe provide a way to overload this

### Full language at compile time

- Macros run at compile time have full access to the Nucleus language, as in most Lisps
- Language features and libraries required for macro expansion may not be necessary at runtime
- Something like Common Lisp's eval-when or a compile-time-only include form is probably required for some advanced macros

### Optional compiler at runtime

- It must be possible to compile and load code at runtime
- Because it adds overhead, the compiler is available as a library
- This allows eval, a REPL, and the ability to interrogate compile-time metadata during development
- For development, a REPL harness can load code files so the developer can use the REPL without the code including it

### Macros are the killer feature

- Macros allow significant abstraction at compile time without requiring runtime overhead
- Reader macros allow sugar for common syntactic patterns

### TODO/undecided:

- Syntax for storage class specifiers
- Other metadata or compiler hints

## Design principles

- Simplicity of implementation is prioritized over design purity ("worse is better")
- Small core - it's better to have few builtins and more libraries
- Few special forms - it's especially better to have few builtins with special behavior
- Many macros - where ergonomics or expressiveness require special behavior, macros are the preferred implementation
- Macros vs functions - In Lisp, it is conventional to prefer functions over macros wherever possible. In Nucleus, runtime overhead is is equally important.
- LLVM native - Nucleus targets LLVM and relies on its infrastructure to simplify implementation when possible.
- C-compatible - Nucleus is a drop-in replacement for C with a superset of C's functionality. It must be able to use any C library's functions and data structures, but not its macros. Likewise, any functions and data structures from a Nucleus library must be consumable from C.

## Design documents

- [initial.md](initial.md) — the stage-0 target program and expected output
- [stage0-plan.md](stage0-plan.md) — implementation plan for the stage-0 compiler (C host, LLVM IR backend)
- [stage1-self-host.md](stage1-self-host.md) — implementation plan for self-hosting the compiler
- [syntax.md](syntax.md) — notes on syntax
- [stage2-macros-jit.md](stage2-macros-jit.md) - early features following successful self-hosting: macros and JIT
- [stage3b-interop.md](stage3b-interop.md) — C interop: unsigned types, function pointers, C header parsing, `--emit-cheader`
- [stage3c.md](stage3c.md) — deferred C interop issues: unions, bit-fields, struct ABI, platform portability
- [stage6-cleanup.md](stage6-cleanup.md) — REPL, printing, macroexpand, n-ary arithmetic, modularization
- [stage6-plan.md](stage6-plan.md) — implementation plan for the non-blocked items in stage6-cleanup.md
- [stage6-floats.md](stage6-floats.md) — design for `f32` / `f64` types (deferred from stage 6)
- [stage6-redefinition.md](stage6-redefinition.md) — design for REPL function redefinition (deferred from stage 6)
- [stage9/polymorphism.md](stage9/polymorphism.md) — Stage 9 polymorphism: the dispatch engine. §§1–8 survey the options and the chosen hybrid (overloaded `defn` multimethods + protocols as a thin checked layer); §9 is the authoritative build spec with landed implementation status (rungs 1–4); §10 specifies the planned **engine extensions** — blanket protocols + `Any`, inferred structural bounds (`Valid`), and operators-as-ordinary-functions (`Num`/`Eq`/`Ord` + user operator overloading); design decisions resolved at the end
- [stage9/callable-values.md](stage9/callable-values.md) — Stage 9: what happens when a non-function is in the call position. **Landed** (impl-status section at end) — `(callee …)` desugars by argument type to `get` (symbol selector → member access, the struct default via the `Struct` blanket protocol, byte-identical to `.` and overridable) or `invoke` (general call; `Seq`/`Call` library protocols in `lib/seq.nuc`, e.g. integer → element). Field selectors are symbol *values* (literal → zero-overhead static GEP; computed → runtime field dispatch over homogeneous structs). Arbitrary-expression heads work and a fn-pointer head folds to `funcall`. Builds on the engine extensions in polymorphism.md §10
- [stage10/safety.md](stage10/safety.md) — Stage 10 umbrella: safety without breaking C compat or adding mandatory runtime cost. Resolved decisions (scope = lifecycle + nullability; non-null via opt-in `(ref T)` then flip; `unsafe` as a naming convention), shared invariants, and the L1→N1→L2→N2→L3 staging. Links the two workstream specs
- [stage10/lifecycle.md](stage10/lifecycle.md) — Stage 10: the `with` lifecycle. Escape/taint analysis in `node-type` (a `with`-owned pointer escaping via return or store-out is a compile-time error; deref/field copies are fine), a `Drop` protocol generalizing the libc-allocator special-case (+ `defer`), and `move` for ownership transfer (replacing the `(set! p null)` disarm) with a double-free check
- [stage10/nullability.md](stage10/nullability.md) — Stage 10: non-null `(ref T)` and nullable `(Maybe (ref T))` / `?T` (niche-encoded, C-ABI-identical to `T*`). Transition forms (`if-some`/`unwrap`/`unwrap-or`/`some`/`none`/`as-ref`), flow narrowing so existing `(when (= x null) …)` guards *are* the narrowing mechanism, and the opt-in-then-flip migration
- [stage10/flip.md](stage10/flip.md) — Stage 10 **Phase F build plan** (the safety flip, **landed**): the 5 parser edits, the measured ~343-site scope, the enumerate-then-batch strategy, and the byte-identity rationale. Implementation note (nullability.md §9.1): flipping the elem-less `ty-ptr` singleton overshoots to ~733 violations, all into untyped `void*` slots; `pkind-flow-check` exempts elem-less destinations so the flip's non-null teeth land only on typed `(ptr T)`/`(ref T)` pointers — the direct analogue of the CStr-is-ref-compatible refinement
- [stage10/errors.md](stage10/errors.md) — Stage 10: **error-handling options survey** (no decision resolved). Error values / error unions mirroring `?T` (niche-encoded ERR_PTR-style `!T`, `deferror`, `try`/`if-ok`/`errdefer`), generic `(Result T E)` gated on sum types, traditional exceptions (sjlj and zero-cost tables), conditions/restarts (full and resumption-only "C-lite", with a library sketch and a standalone-vs-combined-with-A comparison), status-code baseline; tradeoff matrix over C interop, runtime overhead, implementation complexity, versatility, and `with`/`defer` cleanup integration; proposes the two-tier values-plus-`die` shape and rejects exceptions. **Decisions resolved** at the end (A1 built; `!`/`!?`/`?!` sugar; global error ids; handler-aware `err` with `err!` opt-out; safety flip folded into this pass)
- [stage10/errors-prompt.md](stage10/errors-prompt.md) — condensed, actionable implementation prompt distilled from errors.md's resolved design: the authoritative decisions and invariants, then phase-by-phase build order — **E1** (`Err`/`deferror`/descriptor table, prelude `Result`, `!T`/`!?T`/`?!T` sugar, `try`, `err!`, `unwrap`), **E2** (value-`Maybe` + `?!T`), **E3** (handler chain library + `with-handler` + compiler-emitted handler-aware `err`), **E4** (adopt `!T` at `die-at` sites), and **Phase F** (the safety flip: `(ptr T)`→non-null, raw→`(raw T)`, `?`→uniform `(Maybe T)`, using the N2 friction findings as the map). Source-anchored to the U2/U3/N1 machinery it reuses; lists out-of-scope items (A2, `if-ok`, `errdefer`, standalone `signal`, `dyn`, exceptions)
- [stage10/cleanup-prompt.md](stage10/cleanup-prompt.md) — condensed, actionable implementation prompt for the **deferred tail of Stage 10**: **C1** (N2 cold-site cleanup — the ~25 nullable-launder `cast ptr:Sym` waivers), **C2** (standalone `signal` over the existing handler chain — call a handler outside return position), **C3** (E4 coercion-path adoption to `!T` for closed recoverable sub-graphs + a panic-tier `signal 'unhandled-error` hook), and **C4** the capstone (the niche layout engine: U4 `&repr` + rules 1–3 and A2's ERR_PTR encoding, sharing one `union-layout-classify`, with a typed-`(ref T)`-payload guard that keeps the reader's elem-less `!ptr` byte-identical). Lists authoritative decisions, the zero-cost / C-ABI / byte-identity invariants, and out-of-scope items (cleverer niches, whole-emitter `!T`, `dyn`)
- [stage10/unions.md](stage10/unions.md) — Stage 10: untagged unions + tagged sums, the type errors.md's A1 needs. Layer 1: raw `(union …)` (C parity — unblocks the stage-3c header skip, SysV class merging in `abi-classify`); layer 2: `defunion` tagged sums (`{tag, union}` struct, generated constructors, C-legible export) + `match` with exhaustiveness checking lowering to `case`/`switch`; explicit-instance templates for `(Result T E)` (memoized stamping, the constructor target-typing question); niche layout rules under which `?T`/`!T` become layout instances; U1–U4 staging
- [progress.md](progress.md) — overview/index of done / pending / deferred work; per-stage detail links below
- [stage8/progress.md](stage8/progress.md) — Stage 8 detailed progress tables (Phases A–F: target descriptor, multi-target backends, SysV ABI, long data model, struct layout, Windows build)
- [stage9/progress.md](stage9/progress.md) — Stage 9 detailed progress tables (polymorphism rungs 1–4, blanket protocols, callable values, Stage 9 cleanup)
- [stage10/progress.md](stage10/progress.md) — Stage 10 detailed progress tables (unions U1–U4, error handling E1–E4, safety flip Phase F, cleanup C1–C3)
- [stage6-rest-optional.md](stage6-rest-optional.md) — design for `&rest` / `&optional` parameters in `defn`
- [stage6-expressions.md](stage6-expressions.md) — design for expressions-as-values and implicit return
- [stage6-pointer-syntax.md](stage6-pointer-syntax.md) — replace `*T` pointer syntax with `(ptr T)` constructor
- [long-term-issues.md](long-term-issues.md) - potential problems for a mature implementation, deferred during early phases of development
- [stage7.md](stage7.md) — Stage 7 ergonomics overview; sub-plans: [implicit-cast](stage7/implicit-cast.md), [optional](stage7/optional.md) (`&optional` args), [macro-casts](stage7/macro-casts.md), [repl-features](stage7/repl-features.md), [interaction-mode](stage7/interaction-mode.md) (Emacs)
- [stage8.md](stage8.md) — Stage 8 C-parity overview, with [stage8-list.md](stage8-list.md) (candidate C features); sub-plans: [types](stage8/types.md), [globals](stage8/globals.md), [expressions](stage8/expressions.md), [platform](stage8/platform.md) (target descriptor + cross-compilation + struct ABI — Phases A–F), [volatile-plan](stage8/volatile-plan.md), [anon-struct-plan](stage8/anon-struct-plan.md), [cheader-struct-plan](stage8/cheader-struct-plan.md), [optimization](stage8/optimization.md)
- [stage888-deferred.md](stage888-deferred.md) — items deferred
- [stage9/cleanup.md](stage9/cleanup.md) — Stage 9 cleanup (`case` macro, error attribution, one-symbol-one-kind, target descriptor) and [stage9/implementation.md](stage9/implementation.md) (compiler implementation notes)
- [stage999-future.md](stage999-future.md) — far-future / wishlist work (safety constructs, nullability, optimization pipeline, base-feature libraries)
- [stage11/collections.md](stage11/collections.md) — Stage 11: mutable/low-overhead (STL-spirit) collection types as libraries (`Vector`/`HashSet`/`HashMap`/`String`) + core protocols (`Coll`/`Seq`/`Assoc`/`Set`/`Hash`/`Str`). Lazy iterator transforms (`map`/`filter`/`reduce` over an `Iterator` whose `next` returns `(Maybe E)`; `into`/`doseq`), an explicit-choice-with-default `Allocator` protocol (Zig-shaped) + `Drop`/`with` ownership, `usize`/`ssize` indices, reader-macro literals `[…]`/`{…}`/`#{…}`. Prereqs and end-of-stage compiler adoption called out
- [stage11/parametric-structs.md](stage11/parametric-structs.md) — Stage 11 prerequisite: generic structs `(defstruct (Vector T) …)`, the deferred-since-Stage-9 parametric-generics rung. A struct analogue of the existing `defunion` templates (`register-union-template`/`union-template-stamp-types`/`subst-tyvars-node`) reusing the rung-4 monomorphizer for methods; mangled-name stamping + memoization, deferred-IR emission, the type-application-vs-compound-literal construction crux, parametric-protocol conformance (`(extend (Vector T) (Seq T))`), SysV ABI + `.nuch` template export, and the `usize`/`ssize` scalar prerequisite
- [stage11/parametric-structs-prompt.md](stage11/parametric-structs-prompt.md) — condensed, actionable implementation prompt for parametric-structs.md: authoritative decisions + invariants (zero-overhead, byte-identical bootstrap since the registry is inert until a stamp fires), then tasks **T0** (`usize`/`ssize` scalars) → **T1** (template registry + stamping, the core) → **T2** (methods, tyvar-from-receiver + monomorphizer) → **T3** (construction + compound-literal ambiguity) → **T4** (parametric-protocol conformance) → **T5** (C ABI + `.nuch` export) → **T6** (examples/docs/progress), each scoped to specific functions and assigned to a local subagent (systems-impl-engineer / focused-task-implementer / build-test-runner / api-docs-writer) with a build-test-runner gate after each
- [stage11/progress.md](stage11/progress.md) — Stage 11 detailed progress tables: parametric structs (T0–T6 — `StructTemplate`, `register-struct-template`, `struct-template-stamp-types`, `sanitize-for-c`, etc.) and collections (M1–M5 done — `Allocator`/`AllocHandle` + libc/arena backends, `Iterator` + lazy combinators, `Vector T` (`Coll`/`Seq`/`Drop`), the `Hash` lib + `HashMap K V`/`HashSet T` open-addressing tables (`Assoc`/`Set`/`Coll`/`Drop`), and the reader-macro literals `[…]`/`{…}`/`#{…}` (kind-based element inference, `let`+init+conj expansion); the `Seq`→`IntIndexable` rename, the aggregate-`defvar` `zeroinitializer` fix, the deferred static-conformance/import-ordering limitation, and the `COMPILER_DEPS` Makefile fix; M6 `String` + literal switch remaining)
- [stage11/string.md](stage11/string.md) — Stage 11 M6 `String` design: UTF-8, memory-safe, "thin wrapper over a byte vector" (Rust approach); byte index O(1), codepoint index O(n); byte + codepoint iterators rather than blanket-`extend Seq`; `Char` = 32-bit Unicode scalar with a UTF-8/UTF-16 encode/decode protocol; string-literal `CStr`→`String` switch deferred to end-of-stage compiler adoption
- [stage11/cleanup.md](stage11/cleanup.md) — Stage 11 collections cleanup spec (source of truth): **(1)** colon-paren binding sugar `name:(ref (Vector T))` (reader-fuse a trailing-colon atom + adjacent paren into the existing list form); **(2)** keyword type `:foo` built on a **shared `StrView` substrate** (immutable length-prefixed UTF-8 byte slice reusing `lib/hash.nuc`'s FNV byte-fold) so M6 `String` reuses the same byte/eq/hash layer — examined overlap, keyword stays interned-immutable, `Char`/UTF-8 deferred to String; **(3)** multi-binding `let` already works (premise mistaken — flatten the example only); **(4)** generic iterators — basic single-param works, but phantom multi-param templates `(MapIter I F S E)` fail (`unknown type: S` / segfault): **4a** fix phantom/positional tyvar recovery (bug), **4b** associated types (design doc only)
- [stage11/cleanup-prompt.md](stage11/cleanup-prompt.md) — condensed, actionable implementation prompt for cleanup.md: required reading + delegation workflow + the boot-rebuild/ground-verify step, then items in cost order — **3** (flatten `iterator-test.nuc`) → **1** (colon-paren reader sugar) → **4a** (phantom-param tyvar-recovery fix) → **2** (keyword on the shared `lib/strview.nuc` substrate + intern pool + `Hash`/`Eq`) → **4b** (`design/stage11/assoc-types.md`, design only); landmines, keep-green/byte-identical gates, and definition of done
- [stage11/assoc-types.md](stage11/assoc-types.md) — **implemented (A0–A2, stage11-collections branch)** — associated types for protocols. **No new declaration syntax**: parametric protocols already shipped, and the conformance registry's one-per-`(type,proto)` dedup *is* associated-type coherence, so every parametric-protocol parameter is recoverable (no `(type …)` marker needed). The one new surface is generalizing the `&where` constraint `(Protocol Var)` to a protocol *application* `((Protocol Arg…) Var)` — the same spelling `extend` already uses — where each `Arg` is **recovered** if an unbound tyvar or **constrained** if concrete (e.g. `&where ((Iterator S) I) ((UnaryFn S E) F)`); no infix `=`, no `with` keyword. Changes: retain bound args in the `Conformance` record, `emit-extend`, `&where` parser + fixpoint determination check, `unify-tpat` fixpoint binding from conformance args. Subsumes the deferred parametric-protocol-`&where` frontier (Known limitation #3 resolved); migration from phantom-param verbose forms; out of scope (HKT, lambdas, multi-conformance). See §7 of the doc for implementation status and resolved open questions.
- [stage11/assoc-types-prompt.md](stage11/assoc-types-prompt.md) — condensed, actionable implementation prompt for assoc-types.md: required reading + delegation workflow + boot-rebuild/ground-verify step, then tasks in dependency order — **A0** (retain conformance args in the `Conformance` record; coherence check; `.nuch` round-trip) → **A1** (generalize the `&where` constraint parser to `((Protocol Arg…) Var)`; fixpoint determination check) → **A2** (dispatch-time fixpoint binding from conformance args in `unify-tpat`) → **A3** (examples/tests/docs/progress); landmines, byte-identical-bootstrap gates, definition of done
- [stage11/assoc-types-extend.md](stage11/assoc-types-extend.md) — **implemented (A4.0–A4.4, all done)** — extend-site associated-type recovery so generic combinators can *conform* to the protocol they implement and thus **compose**. A `&where` clause on `extend` runs A2's recovery fixpoint at struct stamp time, recording the per-instance `Conformance` with recovered args (`(MapIter IntRangeIter SqFn)` → `Conformance{Iterator,[i32]}`). `.nuch` round-trip of `&where`-bearing extends (A4.3). `lib/iterator.nuc` rewritten with generic `UnaryFn`/`FoldFn`/`MapIter`/`FilterIter`/`reduce`, retiring the `*I64` specializations (A4.4). 89 tests pass; byte-identical bootstrap. See §12 for the build-order record.

## Agent feedback

Some design documents are structured as a conversation between a designer and a robot. Agents tasked with responding to a design document should add their feedback to the robot sections.

Agents encountering new design documents should add them to the above list.

## Pre-release

Nucleus is currently in pre-release development. Breaking changes are expected without warning: at this point Nucleus is only used for its own compiler (and the examples), so it is acceptable to make breaking changes without regard to other projects, because there are none.
