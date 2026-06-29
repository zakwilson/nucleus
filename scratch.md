       L4 is complete. Here's the summary.

       L4 (vfn + closure environment + invoke) — Complete

       All work is in /home/zak/code/nucleus/src/nucleusc.nuc (plus a doc row in /home/zak/code/nucleus/docs/special-forms.md).

       Functions added / changed

       Capture-collection refactor (factored for L5/L6 reuse):
       - fn-capture-check → generalized into fn-capture-walk (node scope bound cap-box:ptr:ptr line). cap-box == null = reject mode (fn); non-null = collect
       mode (a one-slot ptr:ptr box holding a deduped NODE-STR capture-name list built via import-list-push). fn-capture-check is now a thin wrapper
       passing a null box. Transitive captures through nested lambdas are collected because the box threads through the nested-lambda recursion.

       Env / invoke / drop synthesis:
       - fn-make-env-struct — register-structs a fresh dot-free __vfn_env_N (one field per capture), emits %name = type {…}.
       - fn-make-invoke-method — synthesizes (defn invoke:<ret> ((self (ref Env)) <orig-params>) <body'>), registers it on the invoke generic with a pre-set
       mangle-fn-name ir-name, queues a MonoJob (mirrors generic-instantiate; emit-defn's defn-ir-name re-derives the same name → define==call).
       - fn-rewrite-captures (+ fn-rewrite-list/-rest/-from/fn-rewrite-let-binds) — rewrites the body so a capture → (. self f) and (addr-of cap) → (.& self
       f), with the same position-skip discipline as the walker (field names, quote, let/with/nested-lambda shadowing).
       - fn-emit-env-value — emits the env directly (alloca + per-field GEP/store), classifying each capture: POD → bare-symbol bitwise copy (zero
       overhead); Drop-with-Clone → (clone (addr-of x)); Drop-without-Clone → the directed "vfn cannot clone-capture 'x' (type T is Drop with no Clone); use
       mfn to move it instead" error.
       - fn-make-drop-method — for an owning env, records the (Env, Drop) conformance and synthesizes (defn drop:void ((self (ptr Env))) (drop (.& self
       fK))…) in reverse field order.
       - fn-force-generic-mangled, fn-caps-count, fn-env-ref-type, fn-env-ptr-type, emit-vfn, and the vfn dispatch line in emit-list.

       Key decisions / surprises

       - Direct env emission, not a struct literal — emit-struct-lit misreads (clone (addr-of x)) as a designated field initializer (clone:=). Emitting the
       env directly avoids that and keeps the POD path a bitwise copy.
       - fn-force-generic-mangled is the load-bearing gotcha. A solitary drop/invoke generic (one conformer) keeps an unmangled @drop and a bare scope
       binding; adding the synthesized method as a second method made emit-defn re-bind @drop to the closure method, hijacking all drops. Forcing
       mangled=1+finalized=1 (without re-mangling already-emitted methods) routes dispatch by type and stops the re-bind. In any program using collections
       drop is already mangled, so this only bites lone-Drop-type cases.
       - self is prepended onto the whole params spine (not its cdr — that dropped the first real param).

       Validation (scratch /tmp, not added to the suite — that's L9)

       - POD vfn: ((vfn (x:i32):i32 (* x factor)) 5) → correct, factor unchanged, env IR is a plain alloca {i32} + load/store (no clone/malloc — zero
       overhead). Multi-capture + body-let shadowing + field-name-vs-capture all correct. Non-capturing vfn folds to a bare fn pointer (no env).
       - Drop vfn: directed "use mfn" error fires for a Drop-without-Clone capture. With a hand-written clone+drop, the IR is fully correct: env type
       {%Tok}, env build calls @clone into the field (deep copy, source untouched, clones=1), invoke reads (. self t), synthesized @drop.p__vfn_env_0 GEPs
       the field and calls the field's drop, (Env,Drop) recorded.
       - 112 tests PASS; self-hosts as a byte-identical fixed point (stage1.ll == stage2.ll) — L4 is additive and inert in the compiler's own source.

       Incomplete / blocked (not L4's fault)

       - End-to-end Drop-firing-at-with-exit is not demonstrable as a runnable test. Two pre-existing limitations (both reproduce on the boot bin/nucleusc,
       independent of L4) block it: (1) returning/passing a struct by value corrupts via an emit-struct-ret ABI bug (store ptr, sret instead of memcpy), so
       a by-value Drop local — and clone's by-value return — can't round-trip; (2) the anonymous env type can't be named in a with binding, and let/with
       have no type inference. The synthesized drop + (Env, Drop) conformance are correctly generated and are exactly what with-drop-method consults to arm
       cleanup — verified at the IR level. Once a binding path exists (L5/mfn, L6/cfn, or a future binding sugar) the drop will arm; the mechanism is in
       place.

       L5 (mfn = move instead of clone) and L6 (cfn = pointers + allocator) reuse fn-capture-walk, fn-make-env-struct, fn-make-invoke-method,
       fn-rewrite-captures, fn-make-drop-method, and fn-force-generic-mangled directly — only the per-field population mode differs.

       L5 is complete. Here's the summary.

       L5 (mfn — move-capture) — Complete

       All work is in /home/zak/code/nucleus/src/nucleusc.nuc (plus the mfn doc row in docs/special-forms.md). 112 tests PASS; byte-identical fixed point (stage1.ll == stage2.ll).

       Functions added / changed

       - fn-emit-env-value (src/nucleusc.nuc ~3537) — gained a mode:i32 param. mode 0 = vfn clone (textually the original body, nested one level in (if (= mode 0) …); evaluated at emit time so the else-branch is never taken on the vfn path → vfn IR byte-identical). mode 1 = mfn move.
       - emit-vfn (~3690) — call site passes mode 0.
       - emit-mfn (~3693) — new, mirrors emit-vfn exactly except it passes mode 1. Reuses fn-capture-walk (COLLECT), fn-make-env-struct, fn-make-invoke-method (runs fn-rewrite-captures), fn-make-drop-method, fn-force-generic-mangled, the no-capture→emit-fn decay, and the owns-drop pre-scan unchanged. No parallel machinery.
       - mfn dispatch line in emit-list (~5103), gated on mfn not being a bound local (same shadow rule as fn/vfn).

       Per-field population (the mode-1 difference)

       Classification is by sym.owns (scope-lookup):
       - owns == 1 (a with-owned binding) → synthesize a (move cname) node and call emit-move directly. emit-move loads the value, emits store ptr null, ptr %cslot (disarm), sets moved=1, returns the value via alloc-val (taint=null). Consumption enforced by emit-symbol-ref (~1270): any later VALUE reference to the moved binding dies "use after move".
       - owns == 0 (a let binding / by-value param) → bare-symbol bitwise copy (move == copy, nothing to disarm).

       Env-name prefix: reuses __vfn_env_N (shared counter g-vfn-env-id) via fn-make-env-struct as-is. The env struct is structurally identical per capture set and the unique N keeps (Env, Drop) conformances distinct, so the prefix is cosmetic. sanitize-for-ir guarantees IR-legal names.

       Key decisions / surprises

       - A single mode flag on fn-emit-env-value, not a forked emit-mfn-env. emit-mfn and emit-vfn share everything else verbatim. Minimal factoring.
       - Export-from-with CONFIRMED at IR level: an mfn inside a with capturing a with-owned ptr:Res, returned. IR = load + store null to %cslot (disarm) + env-field store; the with-exit drop loads null → null-guard skips (no double-free); ret returns the env with NO escape error (env Val built via alloc-val, taint=null; the move cleared the source's taint). Baseline (return (addr-of o)) fires "resource bound by with escapes via return" — the contrast proving the move is what makes the return sound.

       Pre-existing limitations (NOT L5, reproduce on boot bin/nucleusc — flag for L6/future)

       1. with-drop-method (~2800) only arms Drop for TY-PTR bindings (the ptr:Res idiom), NOT struct-value bindings. So with (o:Owning …) has owns=0 → emit-move would die "does not own". The design's buf:(Buffer) export-from-with example assumes Buffer is a pointer type OR with-drop-method is generalized to struct values. OUT OF SCOPE for L5; L6/cfn and the eventual runnable examples (L9) will hit this.
       2. type-conforms-drop (src/generics.nuc ~2036) only sees TY-STRUCT/TY-UNION as Drop. So a movable ptr:Res capture (with-owned, owns=1) gets NO synthesized env drop, while a struct-value Drop capture (type-conforms-drop=1) has owns=0 → bitwise-copied, not moved. Net: move-and-consume and synthesized-drop are mutually exclusive under the current compiler (the with-drop-method↔type-conforms-drop inconsistency). I demonstrated each half separately: move+disarm+consume on ptr:Res; synthesized drop on a let-bound Owning struct. L6 should check whether cfn (reference-capture, allocator env) needs either path reconciled.
       3. Field-access-on-captured-struct: (. o p) rewrites to (. (. self o) p); the inner . yields a value but _get needs a pointer subject → "_get: operand must be pointer to struct or union". Reproduces on L4 vfn. Workaround in tests: use (addr-of o) (rewrites cleanly to (.& self o)).
       4. Known ABI blocker (from L4 scratch, still out of scope): by-value struct return/passing corrupts via the emit-struct-ret ABI bug, and the anonymous env type can't be named in a with/let binding (no type inference). So end-to-end runnable drop-firing is NOT demonstrable — IR-level verification only. Do NOT touch the ABI bug in L5/L6.

       L6 (cfn = pointers + allocator) reuses the same machinery; its per-field mode will be "store a pointer to the captured local into the env" (not clone, not move). It will additionally need the AllocHandle model and region inheritance (L1), and must confront limitations 1–2 above for any owning-referent case.

       L6 (cfn — reference-capture + allocator) — Complete. Reuses fn-capture-walk/fn-make-env-struct/fn-make-invoke-method/fn-rewrite-captures/fn-force-generic-mangled; the per-field population is "store a pointer to the captured local into the env" (neither clone nor move). Region inheritance (L1) handles referent lifetime. Bootstrap byte-identical.

       L7 (structural function-protocol conformance derivation) — Complete. No bugs found on verification; both code paths confirmed working.
       - Core: derive-closure-conformance (src/generics.nuc ~2233), wired into recover-one-constraint (~1194) and generic-constraints-ok (~1332). Derives a FORWARDING conformance: the generated method is named after the protocol's method (apply/fold) and delegates to the closure's invoke — so the invoke↔apply/fold NAME mismatch is bridged by shape, not by name. Two call styles: call-style 0 = capturing closure env (forwards via (invoke self …)); call-style 1 = bare fn/function-pointer TY-FN (forwards via (deref self) — indirect call of the loaded fn ptr).
       - TY-FN interning: src/type-mangle.nuc fnty-intern/fnty-resolve give each distinct function type a stable __fnty_N name (type-spelling returns it; parse-type-name resolves it back). unify-tpat binds a tyvar G to a TY-FN flowing into a (ref G) param; emit-resolved-call (src/nucleusc.nuc ~5177) adapts calling convention (alloca+store) when a bare TY-FN arg meets a (ref TY-FN) param.
       - RESOLVED SCOPING DECISION (the lambda.md "open mechanism question"): derivation fires ONLY for a recognized set {UnaryFn, FoldFn}, NOT arbitrary single-method protocols. Hard-gated in derive-closure-conformance step 2. Accepted narrowing.
       - Verified end-to-end: fn + vfn + mfn + cfn literals each work as the FoldFn G to reduce AND as the UnaryFn F (via a generic map-reduce helper, since the anonymous env type can't be spelled in a (MapIter I F) literal). Distinct param/return types, multi-capture, and same-tyvar-twice (FoldFn Acc) all correct. Arity mismatch yields a clean overload error, no crash.
       - Latent gap NOT fixed (rationale: unreachable): conformance-lookup itself is not a derivation site — only its two constraint-path callers derive. Other callers (emit-time) could miss derivation, but no current program hits that. Cross-call-site idempotency of a single env type is likewise unreachable (each vfn mints a fresh __vfn_env_N; can't name/reuse one across sites).

       L8 (C interop: cheader exclusion + warning) — Complete. Purely additive.
       - Closure-type detection uses the __vfn_env_ NAME PREFIX (src/cheader.nuc cheader-mentions-closure), NOT a StructDef flag — because --emit-cheader runs BEFORE emit-toplevel-forms (nucleusc.nuc ~8514), so it's AST-only and env structs aren't registered yet (they're created at codegen by fn-make-env-struct). The prefix is the only signal in both paths; it's compiler-reserved (sanitize-for-ir). A bare fn/TY-FN is NOT flagged (it's C-ABI).
       - emit-cheader-declare skips the prototype (leaves a /* <name>: exposes a closure type; …omitted */ comment) when return/any param mentions a closure. Depth: direct sym + arbitrary (ptr/(ref nesting; no struct-field traversal (registry unavailable in AST-only path).
       - emit-defn warns "'<name>' exposes a closure type and will be excluded from generated C headers", GATED on g-defining-private==0 (public) AND g-mono-context==null (real top-level defn, NOT a synthesized invoke/drop method whose self is (ref Env)).

       L9 (docs/examples/progress close-out) — Complete. 117 tests pass; byte-identical bootstrap.
       - examples/closures.nuc: all four forms RUN correctly via reduce (each closure passed inline — the anonymous env can't be bound to a name). fn (defn-ptr + literal referencing defconst), vfn (POD clone, source survives), mfn (move, source consumed), cfn (ref). mfn export-from-with / drop-firing is IR-level-only (blocked by pre-existing limitations below).
       - tests/fixtures/closure-escape.nuc + run-tests.sh closure-escape-rejected: cfn returning a let-local-by-ref → error "address of frame-local storage escapes via return" (the pure L1 proof; the with-owned-let variant hits an unrelated binding-type error).
       - tests/fixtures/closure-cheader.nuc + run-tests.sh l8-cheader-* (3 checks): omit closure-typed proto + comment, emit fn-ptr proto, warn on stderr. (Fixture uses a hand defstruct __vfn_env_0 to make the type resolvable at prescan, since real envs are minted post-prescan.)
       - Docs: special-forms.md (invoke-lowering note + two-concerns split), generics.md (structural-derivation section; Clone already existed), lambda.md (## Robot — implementation status), design/stage13/progress.md (new L0–L9 table), design/progress.md (Stage 13 row + narrative), design/overview.md (lambda.md flipped to implemented).

       Pre-existing limitations STILL BLOCKING some runnable closure demos (NOT closure bugs; documented in lambda.md impl-status + stage13/progress.md + closures.nuc comments):
       1. By-value struct return/passing corrupts via emit-struct-ret ABI bug → owning/Drop env struct can't round-trip by value through a binding.
       2. with-drop-method arms Drop only for TY-PTR bindings → a with-bound owning closure's synthesized drop does NOT fire at scope exit (export-from-with drop-firing is IR-level-only).
       3. Anonymous env types can't be named in let/with (no type inference) → closures must be passed inline as combinator args; can't bind-and-call-later.
       Net: the four forms compute correctly and derive conformances; only the owning-closure-Drop-firing-at-scope-exit demo is not end-to-end runnable. Mechanism is in place; awaits an ABI fix (#1) and a with-drop-method generalization (#2, scratch L5 limitation 1).
