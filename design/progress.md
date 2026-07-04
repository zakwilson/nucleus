# Nucleus — Progress Overview

Current branch: `stage11-collections`

---

## Stage summary

| Stage | Description | Status | Detail |
|---|---|---|---|
| 0 | Initial C-hosted compiler targeting LLVM IR | Done | — |
| 1 | Self-hosting (compiler compiles itself) | Done | — |
| 2 | Macros — `defmacro`/`gensym`/`funcall-ptr-1`, reader macros | Done | — |
| 3a | Libraries and linking | Done | — |
| 3b | C interop — unsigned types, function pointers, C header parsing, `--emit-cheader` | Done | — |
| 6 | REPL improvements, expressions-as-values, `&rest`/`&optional`, pointer syntax, symbol interning; Stage 7 `&optional` folded in | Done | below |
| 8 | C-parity / ABI — multi-target backends, SysV struct ABI, `long` data model, struct layout verification, Windows build | Done | [stage8/progress.md](stage8/progress.md) |
| 9 | Polymorphism — multimethods, protocols, bounded generics, callable values, operators, `Any`/`Valid`; Stage 9 cleanup | Done | [stage9/progress.md](stage9/progress.md) |
| 10 | Safety — untagged unions, `defunion`/`match`, `Result`/`Maybe`, error handling, niche layout, safety flip | Done | [stage10/progress.md](stage10/progress.md) |
| 11 (prereq) | Parametric generics — `(defstruct (Vector T) ...)` templates, stamping, methods, construction, parametric protocols, `usize`/`ssize`, C ABI + `.nuch` export | Done | [stage11/progress.md](stage11/progress.md) |
| 12 | Modules and namespaces — `ns`, import forms, `defn-`/`defvar-` private/internal, `set-ir-prefix`, IR mangling, `export`, `.nuch` round-trip, source migration, compiler split (14,477 → 7,193 lines) | Done | [stage12/namespaces.md](stage12/namespaces.md), [stage12/progress.md](stage12/progress.md) |
| 11 | Collections — `Vector`/`HashSet`/`HashMap`/`String`, protocols, iterators, allocators | Done — M1 (Allocator) + M2 (Iterator + doseq + generic lazy map/filter/reduce) + M3 (`Vector`) + M4 (`Hash`/`HashMap`/`HashSet`) + M5 (reader-macro literals `[…]`/`{…}`/`#{…}`) done; cleanup §1–§4a (colon-paren sugar, keyword/StrView, iterator-test flatten, phantom-tyvar fix) done; associated types (A0–A2) done; **A4 (A4.0–A4.4) done** — extend-site `&where` recovery fully implemented + `.nuch` round-trip + `lib/iterator.nuc` rewritten with generic element-agnostic `MapIter`/`FilterIter`/`UnaryFn`/`FoldFn`/`reduce` (retiring the `*I64` specializations); 89 tests pass ([stage11/assoc-types-extend.md](stage11/assoc-types-extend.md)); **C2.7+C2.8 done** — doc/comment rationale sweep + resolved-limitation close-out; **M6 S0 done** — the `Char` built-in distinct scalar + char literals (`\a`/`\newline`/`\u{…}`), the critical-path prerequisite, byte-identical-additive; M6 S2 done — `lib/string-errors.nuc` (four string `deferror` codes) + `lib/string-protocols.nuc` (`ByteStr ByteI`/`Str CharI` protocol shapes, `(extend Str Eq)` inheritance); **M6 S1 done** — `lib/char.nuc` (UTF-8 encode/decode, `DecodeResult`, `char-from-u32`/`char-to-u32`, ASCII classification + case, `invalid-codepoint` error; note: classification functions named without `?` suffix since `?` is invalid in non-generic LLVM identifiers); **M6 S3 done** — `lib/strview.nuc` (StrView + ByteIter/CharIter + full read layer + Eq/Ord/Hash), `lib/strview-str.nuc` (ByteStr/Str conformances); **M6 S4 done** — `lib/string.nuc` (String owning type wrapping Vector ui8, constructors, mutation API, Drop/ByteStr/Str/Eq/Ord/Hash conformances, works as HashMap key); **M6 S5 done** — `lib/parse.nuc` (`FromStr R` parametric protocol, `parse` macro, `i32`/`i64`/`f64` conformances via libc strtol/strtoll/strtod), `lib/string-split.nuc` (`SplitIter`/`LineIter` with done-flag design — avoids `(Maybe StrView)` JIT struct issue; `strview-split`/`strview-lines`); 102 tests pass; byte-identical bootstrap; **M6 S6 done** — `docs/strings.md` (§1–§8: Char, StrView, String, ByteStr/Str protocols, split/lines/trim, FromStr/parse, error codes); `docs/index.md` updated; M6 **complete** | [stage11/collections.md](stage11/collections.md), [stage11/progress.md](stage11/progress.md) |
| 13 | Lambdas, closures, and type erasure — `fn`/`vfn`/`mfn`/`cfn` (four capture modes), `Clone`, escape generalization, structural conformance derivation, `BoxedFn`, `(dyn Protocol)` | Done — four lambda/closure forms + `Clone` + structural function-protocol conformance (CE-1/CE-2/CE-3 enhancements); all three pre-existing compiler limitations lifted; type-erasure machine (`BoxedFn` + `(dyn Protocol)`) implemented (TE-0 … TE-7). **129 tests pass; byte-identical bootstrap.** | [stage13/progress.md](stage13/progress.md) |
| 14 | Type safety — retire the compiler's untyped-pointer legacy: element-type the 26 registry `Vector`s, type `compiler-types.nuc` cross-reference fields (`(raw T)`/`CStr`) and elem-less `:ptr` signatures, parallel-arrays → array-of-struct (`Arm`/`Constraint`/`Field`), hand-rolled growables → `Vector`, integer-tag closed sums → `defunion`/`case` (`Cleanup` pilot; `Type`/`Node` kind-ladders → `case` without relayout) | **Planned / not started** — design doc written; T14.0 ground-truth done (the "prelude types can't appear in `nucleusc.nuc` signatures" constraint verified **stale** — `prescan-imported-types` fixed it, a toplevel `Node`-typed signature compiles, no enabling fix needed; `(raw T)`-first is byte-identical/zero-obligation). Phases 14.1 registry element typing → 14.2 field typing → 14.3 param/return typing → 14.4 array-of-struct → 14.5 growables → 14.6 closed sums → 14.7 record-only. Type-safety complement to Stage 13 R2/R3 (loops/substrate); keeps the zero-cost hot-path invariant. | [stage14/type-safety.md](stage14/type-safety.md) |
| 14 (macro casts) | Macro conditionals without casts — shared `type-join` absorbing elem-less `ptr` into the typed side at pkind `raw` (MC-1), quasiquote/`gensym` results retyped `(raw Node)` (MC-2), cast deletion in `lib/macros.nuc` + castless test (MC-3), docs sweep (MC-4) | **Done — MC-1 + MC-2 + MC-3 + MC-4** — `type-join` in `src/generics.nuc` absorbs bare↔typed joins (MC-1, byte-identical); `ty-raw-node` accessor + retyped `emit-quote`/`emit-qq-list`/`emit-qq-form`/`gensym` + `node-type-call` lockstep (MC-2, required bootstrap reconverge); `lib/macros.nuc` MC-3 cleanup deletes all 38 vestigial `(cast ptr:Node …)` member-access casts and the 4 single-arg branch-unification `(cast ptr …)` casts across `+`, `*`, `-`, `/`, `and`, `or`, `case`, `->`, retypes `acc`/`cur`/`rest`/`result` locals to `(raw Node)`; design doc's claim that `tests/repl/redefinition.in` macros need cast migration verified **stale** (only `(cast i64 …)` there, no pointer casts); new castless test `examples/macro-cond-nocast.nuc`; 140 tests pass; `make bootstrap` byte-identical fixed-point. MC-4 (docs-only, no code changes) rewrote `docs/macros.md`'s sharp-edge section to the narrower element-type-only collapse rule and dropped its cast recipe, dropped the cast caveat pointer from `docs/toplevel.md`'s `defmacro` row, resolved the `design/progress.md` "Known constraints" bullet on the `(raw Node)` trap, and updated `context/conventions.md`'s Stage-10 N2 bullet 3 to the join-absorption rule. This workstream is **complete**. | [stage14/macro-conditional-casts.md](stage14/macro-conditional-casts.md) |
| 14 (AVR) | AVR microcontroller targets — cross-compile to ATtiny1634 (classic, `-mcpu=attiny1634`) and AVR32DD20 (modern Dx, via family `-mcpu=avrxmega3`); backend registration + `--mcpu`/`--mmcu` plumbing, 16-bit correctness (`ptr-int-ir` 2→`i16`, descriptor-parameterized qq helpers), avr-gcc link driver, volatile-MMIO device libs, `fn-attr`-based ISRs, Harvard hazards (addrspace(1) function values → v1 diagnostic; rodata placement; `defvar` const form; mapped-flash niche collision), all-`ABI-MEMORY` AVR aggregate ABI | **Planned / not started** — design doc written; toolchain ground-verified in-container (LLVM 19 AVR backend present; `attiny1634` a known `-mcpu`, no Dx device entries; valid AVR ELF object emitted end to end; the function-value addrspace(1) verifier error reproduced; `__mulhi3`/`__divmodhi4`/`__muldi3`/`__addsf3` libcalls confirm the avr-gcc/libgcc link dependency — toolchain not yet in the container, AVR-0 adds it); compiler blockers surveyed with file:line (binary 32/64 `ptr-int-ir`, 64-bit `emit-qq-helpers` in the *target* module, hardcoded clang+PIC link with empty CPU, no fn attrs/addrspace/const globals; in our favor: scalar code bypasses `abi-classify`, `volatile` landed, minimal programs reference zero runtime symbols). Phases AVR-0…AVR-8; the AVR-2 fixes are the long-standing 32-bit blockers too; byte-identical on hosted targets throughout. | [stage14/avr-targets.md](stage14/avr-targets.md) |
| 14 (RISC-V) | Linux on RISC-V — riscv64 RV64GC/lp64d; Tier A cross-compile + full test suite under `qemu-user`, Tier B native self-hosting (hardware-gated); backend registration + per-triple CPU/features defaults + first `!llvm.module.flags` emission (`target-abi=lp64d`), triple-keyed cross link driver, integer-convention aggregate ABI (`abi-is-riscv`; FP-flattening deferred like aarch64 HFA), per-arch boot-IR selection modeled on `windows-boot` | **Planned / not started** — design doc written; toolchain ground-verified in-container (RISCV backend present; **features cliff verified**: empty CPU/features → bare RV64I with silent soft-float `lp64` ABI (`__muldi3`, doubles in integer regs) vs correct `mul`/`fadd.d` with `+m,+a,+f,+d,+c`+`lp64d` — the current empty-features `LLVMCreateTargetMachine` calls make this the default failure mode; cross gcc/qemu not yet in container). Survey found two host-portability gaps worth fixing regardless: `repl.nuc:597/690` hardcode `"x86_64-pc-linux-gnu"` (bites aarch64 hosts) and no non-x86 Linux boot IR / bring-up recipe. Phases RV-0…RV-5; shares Target cpu/features + link-driver plumbing with AVR-1/AVR-3 (land once, in whichever goes first); byte-identical on existing targets. | [stage14/riscv-linux.md](stage14/riscv-linux.md) |
| 14 (int-widening) | Integer-literal widening — close the residual cast gaps: template-tier adaptation for stamped parametric methods (`conj`/`(v i)`/HashMap — the real friction), explicit-`return` coercion, representability checks + wide emission for out-of-i32-range literals, `node-type-call` lockstep mirror, ~991-site vestigial-cast sweep | **LW-1 + LW-2 + LW-3 + LW-4 done (2026-07-03); LW-5 pending** — a shared side-effect-free `generic-resolve-adapt-tier` (`src/generics.nuc`) runs the tier-2 pool for both emit (`generic-resolve`, dies/monomorphizes) and the type model (`node-type-call`, returns null); template candidates matched by `generic-method-bind-adapt` (receiver-bind then `arg-adapts` each remaining param, never binding a tyvar); `Method.origin-template` marks stamped instances so the pool skips a template's own cache (else the *second* widened call reads as a false `ambiguous overload`). `(conj v 3)`/`(insert v 1 7)`/`(v 0)` on `(Vector i64)` now compile castless; genuine width-only ambiguity still errors; `operator-user-resolve` has no template tier (left untouched). LW-3: `emit-return` (src/nucleusc.nuc) now runs `coerce-int-val` against `g-fn-ret-type` before the scalar `ret` (mirroring the implicit end-of-body path), guarded on `g-fn-ret-type != null`; on failure a source-level `die-at` names both types via `type-spelling` instead of falling through to a raw LLVM parse error; the struct-return (`emit-struct-ret`) branch is untouched since `abi-classify` only assigns non-`ABI-DIRECT` kinds to `TY-STRUCT`/`TY-UNION`, so the scalar branch never carries a struct return type. `(defn f:i64 () (return 0))` now compiles and runs; a genuine mismatch (e.g. `(return 1.5)` in an `:i64` fn) now dies cleanly at the source line instead of an LLVM parse error. LW-4: `Val` gains `is-lit`/`lit-i64` (set only by `emit-int`); the representability check lives in the single int→int chokepoint of `coerce-int-val` (abi.nuc) — every narrowing coercion of a literal (let/defvar init, field/`aset!` store, return, union variant, call args via `safe-coerce-val`, binop adoption via `coerce-num-val`) routes a tagged Val through it — dying `integer literal N does not fit <type>` on an out-of-range literal while leaving typed values untouched. Shared predicate `int-literal-fits` (type-utils.nuc, shift-built bounds so it is a bootstrap fixed point). `emit-int` now emits `i32` when the value fits, else `i64`, with `node-type`'s NODE-INT branch mirroring (lockstep); `(take64 5000000000)`→`5000000000` (was the 32-bit-wrap `705032704`). Lexer (`lex-atom`, reader.nuc): `strtol` errno-checked for `ERANGE`, non-negative overflow retries `strtoull` (ui64/usize scale), negative or >u64 overflow → positioned reader error; `errno` via hand-declared `__errno_location`. Latent bug fixed: the FNV hash constants were silently i32-truncated by old `emit-int` — now correct (updated `cstr-fold-test.out` to the real FNV-1a; `types.nuc`'s deliberate i8-wrap demo now uses an explicit `(cast i8 200)`). Bootstrap not byte-identical (Val grew, error strings, corrected FNV constants shift union-shape-hash names) — reconverged in **two** `update-bootstrap` rounds (corrected constant needs one extra generation to reach the naming code); 140 tests pass. LW-5's test/doc slice done (2026-07-03): `examples/int-widening.nuc` demonstrates castless `conj`/`insert`/`(v i)` on `(Vector i64)`, a castless explicit `(return 5)`, and `(take64 5000000000)` printing the untruncated value; negative fixtures `tests/fixtures/lw-ambiguous-widening.nuc` (two non-i32 overloads both reachable by tier-2 adaptation → `ambiguous overload for 'f' under argument widening`) and `tests/fixtures/lw-literal-range.nuc` (`(take8 300)` → `integer literal 300 does not fit ui8`) wired into `tests/run-tests.sh`; `docs/types.md`'s existing "Implicit Type Coercion"/"Literal Values" sections were checked against LW-1..LW-4 and found already accurate, no edit needed; the Keyword/StrView doc example and `examples/strview-test.nuc` were checked for a vestigial int-literal cast per the design doc's note — none found (their casts are unrelated `ptr`/`ui64`-format casts), so no change there either. 143 tests pass; bootstrap untouched (byte-identical, no `src`/`lib` changes). Remaining: LW-5's tree-wide vestigial-`(cast <int-type> <literal>)` sweep (~991 sites across src/lib/examples) stays deferred to a separate pass, per the design doc's own sequencing note. | [stage14/int-widening.md](stage14/int-widening.md) |
| 14 (mangling) | Symbol mangling for `?`/`!` in function names — shared `ir-name-token` (`?`→`_QMARK`, `!`→`_BANG`, Clojure munge precedent) at the base-token layer beside the operator mnemonic table; always-tokenize the solitary path (which **is** the single-conformer bug — fixes it and retires `_StrMangleShim`); REPL/cheader/`.nuch`/defvar/`%struct` alignment; source-level diagnostic backstop | **Done** — design doc written; ground-verified: plain `defn full?`/`push!` emit verbatim → raw LLVM parse error, no source diagnostic; overloads mangle lossily (`is-both?` → `@is_both_.pA`; `?`/`!`/`-` all → `_`); quoted `@"full?"` verified viable through llc/nm (ELF allows `?`) but rejected (touch-every-print-site, C-undeclarable); **landmine verified**: `sanitize-for-ir` excludes hyphens from its safe set — plain defns work only by bypassing it, so blanket sanitize would rename every hyphenated symbol and break bootstrap+C ABI. REPL derives names via raw `sanitize-for-ir` independently — suspected pre-existing hyphen-redefinition bug (verify in SM-2). No `?`/`!` names in src/ → bootstrap byte-identical. Phases SM-1…SM-5. **SM-1 done (2026-07-03)**: `ir-name-token` (+ `ir-name-append`) in `src/generics.nuc` maps `?`→`_QMARK`/`!`→`_BANG` with all other bytes (hyphens included) passing through unchanged (pointer-unchanged fast path for names with neither); wired into `op-name-token`'s `sanitize-for-ir` fallthrough, the solitary `finalize-generics` branch, and `ns-ir-base` (`src/nucleusc.nuc`) — the last a single chokepoint covering `defn-ir-name`'s fallback, `emit-defvar`/`extern` globals, and the symmetric `.nuch` solitary import + cheader function-name derivation. `_StrMangleShim` + its 4 dummy conformers deleted from `lib/strview-str.nuc`; `str-empty?`/`starts-with?`/`ends-with?`/`contains-str?` now resolve honestly on the solitary path. Because the compiler imports overloaded `?` lib methods (`contains?`/`empty?` on HashSet/HashMap), its own self-IR legitimately shifted `@contains_.…`→`@contains_QMARK.…`, needing the standard reconverge (`make update-bootstrap` + `make clean && make`); fixed point restored. New `examples/predicate-names.nuc` + expected out; `nm` shows `full_QMARK`/`push_BANG`/`blank_QMARK`/`zeroed_QMARK.pMeters`; 144/144 tests. Bonus: `--emit-cheader` now prints the real linkable symbol for solitary `?`/`!` names (was illegal `full?`). **SM-2 done (2026-07-03)**: `src/repl.nuc`'s two independent name-derivation roots (defvar `external global` decl at :161, defn `fname-ir` at :228) now derive via `ns-ir-base` (→ `ir-name-token`) instead of raw `sanitize-for-ir`, so REPL thunk/`@fname.impl.N`/`@fname.tgt` names and the `@fname(`→`@impl(` rewrite reference the exact symbol `emit-defn`/`emit-defvar` emit. **Both suspected bugs ground-verified real** (not just redefinition — the *first* definition already broke): a hyphenated `defn my-add` emitted `@my-add` while the REPL looked up `@my_add.impl.0` (raw sanitize drops hyphens); a `?`-named `defn even?` emitted `@even_QMARK` (SM-1) while the REPL looked up `@even_.impl.0`. Fix confirmed: hyphen/`?`/`!` all round-trip (define/call/redefine/call, incl. cross-fn thunk dispatch). REPL only handles the solitary non-overloaded case — exactly `defn-ir-name`'s `ns-ir-base` fallback — so no overload/mangle handling needed. `tests/repl/redefinition.in` + `tests/expected/repl-redefinition.out` extended with `my-add` (+ `use-add` caller) and `even?` cases; `make test` + `make bootstrap` (stage1==stage2) green. **SM-3 done (2026-07-03)**: export surfaces tell the truth. `sanitize-for-c`'s three call sites (all in `src/cheader.nuc`: the `emit-cheader-defstruct`/`emit-cheader-defunion` typedef names and the `struct %s` reference in `type-name-to-c`) now compose `(sanitize-for-c (ir-name-token name))` — `ir-name-token` first so `?`/`!` in a struct/union *type* name become `_QMARK`/`_BANG` before the blanket map (else `?` collapses to `_` and collides). Composed at the call sites (not inside `sanitize-for-c`) because format.nuc is imported before generics.nuc, so a call up to `ir-name-token` from a format body is an unresolved forward-ref at emit time; duplicating the map would break SM-1's single-helper invariant. No-op for `?`/`!`-free names → every existing header byte-identical; no string-pool shift (`_QMARK`/`_BANG` stay @.str.518/519); `make bootstrap` fixed point holds in one pass. `.nuch` round-trip **ground-verified** (solitary `full?`/`push!` via `ns-ir-base` → `@full_QMARK`/`@push_BANG`; overloaded `even?` i32/i64 via stored `(defmethod "@even_QMARK.i32" …)` string) — consumer imports the `.nuch`, links the lib object, and runs. Fixtures `tests/fixtures/sm3-predlib.nuc` + `sm3-typenames.nuc`; six new `sm3-*` checks in `tests/run-tests.sh`; `make test` + `make bootstrap` green. Two pre-existing out-of-scope gaps flagged (not fixed): overload-unaware `emit-cheader-declare` emits N identical prototypes for an overloaded function; union arm / enum variant / struct field names are printed raw (unsanitized) in the cheader. **SM-4 done (2026-07-03)**: `%Foo` struct/union LLVM *type* names. The design's "type-to-ir is the single reference chokepoint" premise proved **incomplete** (ground-verified: `(defstruct Full? …)` + field access emitted `getelementptr inbounds %Full?, …`, bypassing `type-to-ir`; GEP/alloca/load/store type-operands print the StructDef name directly). Fix = new `StructDef.ir-name` field (compiler-types.nuc) computed **once** in `register-struct` (abi.nuc, the sole StructDef allocator) as `(ir-name-token name)`; `name` stays the raw source spelling + `lookup-struct` key (mangling it breaks interned-pointer resolution of a `Full?` type token), `ir-name` is the LLVM spelling every reference/definition prints. ~35 IR sites in `union-emit.nuc`/`nucleusc.nuc` + `type-to-ir` + the def emitters (`emit-defstruct`, `emit-pending-struct-ir-type`, `emit-union-ir-type`, `defunion-register`) switched `(sd name)`→`(sd ir-name)`; diagnostics keep `name`. `ir-name-token`+`ir-name-append` **relocated** generics.nuc→format.nuc (beside `sanitize-for-ir`) — forced by import order (type-utils.nuc #567 / union-registry.nuc #584 precede generics.nuc #604, so a direct call forward-refs — verified `unknown: ir-name-token`; SM-3's later-call-site wrap can't apply since `type-to-ir`'s callers are everywhere). Anon/synth names (`__anon_*`/`__vfn_env_*`/`__fatptr`/`__boxedfn.*`/`__dyn.*`) left alone (all `?`/`!`-free → no-op). Out of scope, noted: goto label names (`%lbl.<arm>`) and cheader C-imported struct types (C ids can't hold `?`/`!`). Bootstrap fixed point (stage1==stage2) holds **in one pass** (compiler source has no `?`/`!` structs → transform inert); `build/nucleusc.ll` shifted only mechanically (helper relocation + `_QMARK`/`_BANG` `@.str` +2 renumber + extra StructDef field), no hyphen regression. New `examples/predicate-types.nuc` (+expected): `?`/`!` structs, `?`-union+`match`, `?`-struct embedded by value — emitted `.ll` shows `%Full_QMARK`/`%Reset_BANG`/`%Shape_QMARK` def+refs spelled identically, `%Gauge = type { %Full_QMARK, i32 }` cross-checks, `llvm-as` validates; 151/151 `make test`. SM-5 pending; deferred stale docs (context/build.md, docs/functions.md, the conventions.md `?`/`!`-break-symbols note) noted in the design doc. **SM-5 done (2026-07-03)**: diagnostic backstop. New pure predicate `ir-name-illegal-char` (src/format.nuc, beside `ir-name-token`) returns the first byte outside LLVM's identifier body `[A-Za-z0-9$._-]` (skips a leading `@`/`%` sigil; hyphen/`$` legal → never flagged, preserving SM-1's targeted-not-blanket invariant); die-at wrapper `check-ir-name-legal(line, orig, ir-name)` (src/abi.nuc, before `register-struct` — earliest home reachable by both `die-at` (reader #507) and the chokepoints, since format #420 precedes reader) turns a hit into a clean source diagnostic. Wired one line each into seven define/declare sites: `emit-defvar`/`emit-extern`/`emit-defn` (solitary `(defn-is-mangled)==0` branch only — mangled path already `sanitize-for-ir`'d)/`emit-defstruct` (nucleusc.nuc), `defunion-register` (union-registry.nuc), `emit-cheader-defstruct`/`emit-cheader-defunion` (cheader.nuc — provable no-ops, kept for consistency). NOT wired (documented): `type-name-to-c`/`register-struct` (no `line` param; real user-named structs covered via `sd.ir-name` at emit-defstruct/defunion-register), stamped template names, REPL derivation (flows through `emit-defn`). Verified `(defn weird%name …)` (`%` legal in a Nucleus symbol, illegal in LLVM, unchanged by `ir-name-token`) now dies `illegal character '%' in generated symbol for 'weird%name' (ir-name '@weird%name') — LLVM identifiers allow only [A-Za-z0-9$._-]` instead of a downstream LLVM parse error. New fixture `tests/fixtures/sm5-illegal-char.nuc` + `sm5-illegal-char-rejected` check. Purely additive/inert on existing names → `make bootstrap` converges in ONE pass (byte-identical); 152/152 `make test`. **Docs closed out (2026-07-03)**: `context/build.md`'s two stale gotcha bullets (the `_StrMangleShim` ≥2-conformer workaround and the "`!`/`?` invalid in a `defn` name" gotcha) deleted; `docs/generics.md`'s Symbol mangling section documents the `?`→`_QMARK`/`!`→`_BANG` mapping (solitary and overloaded, struct/union type names too) and the `_QMARK`/`_BANG` collision caveat, citing `examples/predicate-names.nuc`/`examples/predicate-types.nuc`; `context/conventions.md`'s stale "`?`/`!` in user function names break LLVM symbols" note rewritten to the current mapping plus a heads-up that internal `src`/`lib` adoption of `?`/`!` names will need the standard bootstrap reconverge. The symbol-mangling workstream (SM-1…SM-5) is now fully done, code and docs. Optional lib `?`-suffix re-adoption (e.g. `char-is-ascii?`) remains the user's call. | [stage14/symbol-mangling.md](stage14/symbol-mangling.md) |
| 14 (colon-paren) | Colon-paren type-sugar gap closure — chain fuse `name:ref:(Vector T)` (CP-1), lone-colon ret fuse `):(Maybe i32)` (CP-2, retires defn-signature's parenthesized-ret exception), trailing-colon-name diagnostic (CP-3)  | **Done** — CP-1/CP-2/CP-3 all implemented in lib/reader.nuc (`fuse-colon-paren`) + src/nucleusc.nuc (CP-3 diagnostics at the desugar/emit chokepoints); new example examples/colon-paren-types.nuc; 139 tests pass; bootstrap byte-identical (no re-baseline). | [stage14/colon-paren-types.md](stage14/colon-paren-types.md) |
| 14 (unsafe-ns) | The `unsafe` namespace + the `as` form — split `cast` into `as` (statically safe: the implicit-coercion set + pure pointer-contract weakening, honoring `pkind-flow-check`) and `unsafe/cast` (today's cast verbatim); move the always-unsafe roster (`funcall-ptr-*`, `ptr+`, `unsafe-import-private`→`unsafe/import-private`) under a reserved `unsafe/` pseudo-namespace so `grep -rn 'unsafe/'` audits every unchecked site; retire the bare spellings as targeted hard errors | **Planned / not started** — design doc written; ground-verified: `emit-cast` is one unchecked ladder that bypasses `pkind-flow-check` (silent `raw`→`ref` laundering); special-form dispatch is raw-head identity before `qualify-name`, so `unsafe/cast` routes with one identity compare and no reader change (`/` is a symbol char); `as` unclaimed (`as-ref` completes the family as the runtime-checked tier); `safe-coerce-val`/`coerce-int-val` already implement the safe set. ~5,340 cast sites tree-wide, most scheduled for *deletion* by 14.2/14.3 + LW-5 + MC-3 — hence the hard edge: the UN-4 split sweep runs after them, on survivors only. Phases UN-1 (`as`) → UN-2 (`unsafe/` routing) → UN-3 (refresh + roster sweep) → UN-4 (cast split sweep) → UN-5 (retirement + docs); UN-1/2 additive byte-identical, land early. | [stage14/unsafe-namespace.md](stage14/unsafe-namespace.md) |
| 14 (attributes) | Declaration attributes — the keyword-attribute slot on declarations (leading `:keyword` before the declared name in `defvar`/`let`/`with`/fields/params, registry-driven, unknown keyword = error; attributes never enter type identity/dispatch/mangling), resolving the stage-8 storage-class deferral; `:volatile` migrates off the postfix type-qualifier spelling (`(T volatile)`/`T:volatile` retired; pointer-target volatility keeps the one type-position form `(ptr :volatile T)`); `:thread-local` reserved with a targeted error (blocked on a threading stage); `:static`/`:align`/`:section`/`:weak`/fn-attrs sketched | **Planned / not started** — design doc written; ground-verified: volatile spellings exist only in examples/volatile.nuc + examples/logic.nuc (zero in src/lib → byte-identical throughout); lowering unchanged (`type-with-volatile`), pure front-end; `is-volatile` on `Type` already needs per-site mangle/hash judgment calls (compiler-types.nuc:78 vs union-registry.nuc:28) — the argument for keeping further storage metadata off `Type`. Phases AT-1 (slot + `:volatile` + `:thread-local` reservation, dual-accept) → AT-2 (example/doc migration, IR-identity-verified) → AT-3 (retire old spellings). No backbone edges; AT-1 before AVR-4 (MMIO device files in final spelling). | [stage14/attributes.md](stage14/attributes.md) |
| 14 (native-strings) | Native string literals — flip `"…"` from `CStr` to a length-carrying, borrowed `StrView`, with a free `StrView`→`CStr`/`ptr` coercion (hidden-NUL rodata backing global) keeping the compiler's own `fprintf`/`snprintf`/`=`-identity substrate byte-identical; `c"…"` FFI literal; selective, bounded compiler-internal adoption where a carried length removes a `strlen`/re-scan | **NS-1 + NS-2 + NS-3 done (2026-07-03); NS-4 done (2026-07-04); NS-5…NS-6 pending** — NS-1 moves the bare `(defstruct StrView (data (ptr ui8)) (len usize))` from `lib/strview.nuc` into `lib/prelude.nuc` (placed immediately after the `NodeKind` enum, before `(import-use macros)`), registering the type in every compilation unit — including the reader, macros, and bootstrap — rather than only files that `(import-use strview)`. `lib/strview.nuc` keeps every method (`strview-len`, `strview-eq`, etc.); only the `defstruct` line moved, replaced with a comment pointing to its new home. Confirmed exactly one `defstruct StrView` exists tree-wide. No literal typing, coercion, or emission change — this phase only makes the type *available*. Gate: `make bootstrap` converged on the first try (stage1.ll == stage2.ll, no `make update-bootstrap` refresh needed); a `build/nucleusc.ll` before/after diff showed exactly one additive delta — an unreferenced `%StrView = type { ptr, i64 }` type declaration (the compiler self-compiles with `lib/prelude.nuc` auto-imported, so the now-prelude-level inert struct type appears as dead code in the compiler's own IR) — not a string-pool renumbering cascade, so the design doc's byte-identical gate held in the sense that matters (no reconverge needed). `make test`: 152/152 passed, including every `(import-use strview)` client (strview-test, strview-read-test, string-test, string-split-test, split-iter-test, parse-test, keyword-test, etc.). Independently re-verified with a full `make clean && make` + `make bootstrap` + `make test` — all green, 152/152.

  **NS-2 done (2026-07-03)** — dormant emission + coexistence coercions, all inert (the literal type stays `CStr`; NS-3 is the actual flip). (1) `emit-string` (`src/nucleusc.nuc:894`) gained a `target:ptr` param; a dormant branch materializes a `{data, len}` StrView via two `insertvalue`s when `type-is-strview(target)`, using the already-known interned byte length (no runtime `strlen`). Sole caller `emit-node:795` passes `null` → the `CStr` path is textually identical to before. (2) `StrView`→`CStr`/`ptr` free coercion added to `coerce-int-val` (`src/abi.nuc:450`, the real value-coercion chokepoint), immediately after the existing `CStr`↔`ptr` no-op: a `StrView` source coercing to `ptr`/`CStr` extracts `.data` via one `extractvalue`; the literal-collapses-to-bare-GEP optimization is deferred to NS-3 (needs a literal flag no value carries yet). (3) `emit-binop-vals`'s mixed-operand `strcmp` rule (`src/nucleusc.nuc:~1580`, new helper `strview-data-ir` at `:1573`) extended to admit a `StrView` operand alongside the existing ptr-like guard, extracting `.data` before the `strcmp`; two plain `ptr` operands still compare by `icmp` identity (the `Node.s` path is untouched). (4) `node-type`'s three `NODE-STR` lockstep sites (`src/generics.nuc:1752/2028/3500`) needed **no change** — confirmed by investigation: there is no target-type threading through `emit-node` for the collection-literal case to mirror, `emit-string(n,null)` still resolves to `CStr`, which already agrees with `node-type`'s unconditional `ty-cstr`. New shared predicate `type-is-strview` added at `src/type-utils.nuc:82`. JIT visibility (design doc §1.7) confirmed automatic: the prelude `StrView` struct routes through `g-type-stream`/`g-type-bufp` into every CT/macro JIT module exactly like `Node` — `%StrView = type { ptr, i64 }` verified present beside `%Node` in the JIT IR. Gate: `make bootstrap` byte-identical on the first try, zero refresh; a per-`define` diff (with `@.str.N` normalized) shows exactly 2 functions added (`type-is-strview`, `strview-data-ir`) and 4 bodies changed (`emit-string`, its caller `emit-node`, `coerce-int-val`, `emit-binop-vals`) — every other function untouched. `make test`: 152/152 (lib/strview.nuc and examples already exercise real `StrView` values at runtime, which is what confirms the new paths stayed dormant rather than silently misfiring). Independently re-verified via a direct `make bootstrap` + `make test` run (subagent dispatch was gated by the 5-hour usage window at the time) — both green, 152/152.

  **NS-3 done (2026-07-04)** — the flip itself: `"…"` now types as `StrView`, not `CStr`. The three `node-type` `NODE-STR` lockstep sites (`src/generics.nuc:1769/2047/3525`) now return `(strview-type)` (`src/union-registry.nuc:310` — resolves the prelude `StrView` struct's `Type*` dynamically from the struct registry, since unlike `ty-cstr` it isn't an init-time global; falls back to a bare pointer if somehow unregistered). `emit-string` (`src/nucleusc.nuc:894`) is now target-aware for real: a `ptr`/`CStr` target still emits only the bare GEP, but the *default* (untargeted) path returns an **unmaterialized "chameleon" literal** — `is-lit=1`, `type=StrView`, `val`=the bare data pointer, `lit-i64`=the interned byte length — rather than immediately building a `{ptr,len}` struct. This chameleon is what keeps the compiler byte-identical: every coercion/cast/binop/vararg/&rest/match-arm/cond-arm chokepoint that used to see a `CStr` literal now special-cases `is-lit && type-is-strview` and collapses it back to the bare pointer with **zero extra IR**, only materializing a real `{ptr,len}` aggregate when a genuine `StrView`-typed target demands it. Touched chokepoints: `coerce-int-val` (`src/abi.nuc:444`, two new guards — the is-lit collapse-or-materialize, and a StrView-vs-other-struct rejection so the `sk==dk` identity fast path can't misreinterpret a chameleon as an unrelated struct), `abi-arg-frag` (`src/abi.nuc:~348`, a variadic chameleon arg passes as plain `ptr %data`), `emit-binop-vals`/`strview-data-ir` (`src/nucleusc.nuc:1600/1621`, a chameleon's `.data` is its `val` directly — no `extractvalue` — so `(= name "lit")` strcmp's exactly as before), the `cast` special form (`src/nucleusc.nuc:~1751/~1787`, a StrView-literal cast to a struct target routes through `coerce-int-val` instead of the identity/reinterpret fast paths, and a cast to `ptr`/`CStr` delegates the same way), the value-keyed `get`/`generic-resolve-nullable` retry (`src/nucleusc.nuc:~2334`, a StrView-literal map key that fails to resolve retries once as `CStr`), the `&rest` cons-list fold and C-variadic-call arg loop (`src/nucleusc.nuc:~2823/~2938` — a literal collapses to `CStr` via the new `collapse-strlit-cstr` helper, `src/type-utils.nuc:103`; a *materialized* (non-literal) StrView value at a variadic slot instead gets its `.data` extracted so only the pointer, not the `{ptr,len}` pair, occupies the vararg slot), and `cond`/`if`/`match` branch joins (`src/nucleusc.nuc:5589`, `src/union-emit.nuc` ×2 — a string-literal branch collapses via `collapse-strlit-cstr` so the phi stays a plain pointer). `arg-adapts` (`src/generics.nuc:409`) gained a rule: a `StrView`-typed argument adapts to a `CStr` multimethod parameter only (never a bare `ptr` parameter), reproducing the pre-flip overload-resolution outcome for a literal arg. `examples/cstr.nuc` updated: the `same "hi" "hi"` `Eq`-bounded-generic calls now `(cast CStr "hi")` explicitly, since a bare literal is `StrView` and the example doesn't `(import-use strview)` (no `Eq` conformance in scope to bind the generic at `StrView`). New regression `examples/strview-vararg-test.nuc` + `tests/expected/strview-vararg-test.out` locks two ABI facts: a *materialized* `StrView` passed as a `printf` `%s` vararg contributes only its `.data` pointer (not `{ptr,len}` as two variadic slots — a following `%d` must not shift), and a *fixed* `StrView` by-value parameter still receives the full two-eightbyte struct per the platform ABI. Gate: **byte-identical bootstrap** — the load-bearing proof for this phase — held: every compiler-internal string literal sits in `ptr`/`CStr`/binop/vararg/&rest/branch-join context, so each one collapses through a chokepoint above with no extra IR; `build/nucleusc.ll` before/after diff is empty; `make bootstrap` converges stage1==stage2 on the first try, no `make update-bootstrap` refresh needed. `make test`: **153/153** (152 prior + the new `strview-vararg-test`). Full clean rebuild (`make clean && make` + `make bootstrap` + `make test`) independently re-verified, all green. NS-5 (selective compiler-internal adoption) and NS-6 (interning-reconciliation docs/conventions note) remain pending.

  **NS-4 done (2026-07-04)** — the `c"…"` FFI literal: a `c` glued directly to a string literal (no whitespace) is an explicit `CStr` — the bare `char*`, no `StrView` view header, no target-typing — the direct "I mean `char*`" spelling for FFI/format hot spots (the default `"…"` is still a `StrView` that borrows to `char*` for free). Mechanism = reuse `Node.i` (i64, previously unused for `NODE-STR`) as a boolean CStr discriminant (`0` = `StrView` default, `1` = explicit `c"…"`) — the smallest, cleanest diff: no new `NodeKind`, so no new dispatch sites, and dormant for every existing literal (all `NODE-STR` keep `i=0`). Reader (`lib/reader.nuc`): `next-tok` detects `c` (99) immediately followed by `"` (34) via one-char lookahead (`char-at g-src (g-pos+1)`) — an adjacency otherwise unreachable, since a bare symbol `c` is delimiter-separated from a following string — consumes both, lexes the body exactly as a plain literal, and flags the token `i=1`; the `TOK-STRING`→`NODE-STR` conversion now copies `(t i)` into `NODE-STR.i` (a plain token has `i=0` from arena zero-fill, so byte-identical for every existing string). The three `node-type` `NODE-STR` lockstep sites (`src/generics.nuc:1769/2047/3525`) now branch: `i≠0` → `ty-cstr`, else `(strview-type)`. `emit-string` (`src/nucleusc.nuc:894`) gained an NS-4 short-circuit right after the bare GEP: `i≠0` returns the GEP as a plain `CStr` Val regardless of the ambient target, ahead of the NS-3 chameleon/StrView-materialization logic. Gate: **purely additive/dormant** — no compiler source uses `c"…"` (every internal `NODE-STR` has `i=0`), so `make bootstrap` converges stage1==stage2 **on the first try, byte-identical, no `update-bootstrap` refresh** (no new string-pool literals in `src`/`lib`; the added branches are present identically in both stages). New `examples/cstr-lit-test.nuc` + `tests/expected/cstr-lit-test.out` exercise all three contract cases: a `c"…"` literal as a `printf` `%s` vararg (bare `char*`), a `c"…"` literal into an `extern`-declared `strlen` expecting `char*`, and a plain `"…"` literal free-coercing to that same `char*` extern (NS-3 collapse, no regression); IR confirmed zero `insertvalue` for any of them. `make test`: **154/154** (153 prior + `cstr-lit-test`). Out of scope per the milestone split: quoted `c"…"` is not carried (`emit-quote-tree` deliberately does not store `Node.i` for `NODE-STR`, keeping quoted plain strings byte-identical); NS-5 selective adoption and NS-6 docs/conventions reconciliation (docs/strings.md, docs/types.md, the conventions note) are separate future items. | [stage14/native-strings.md](stage14/native-strings.md) |
| 14 (defn-signature) | `defn` return type after the parameter list — dual-accept `(defn name (params):ret body…)` (matching `fn`/`vfn`/`mfn`/`cfn`) alongside legacy `(defn name:ret (params) …)`, funneling every read site through one accessor as the prerequisite cleanup for the 14.3 param/return-typing work | **S1 done (2026-07-04); S2–S4 pending** — `defn-parse-sig` + `sig-name-is-bare`/`legacy-ret-node`/`normalize-ret-node`/`defn-ret-node`/`proto-sig-parse` (nucleusc.nuc) are the single style-detection/return-extraction chokepoint; a legacy form routes to the exact `extract-name-and-type`/`binding-type-node` parse (byte-identical), a new-style form reads the index-3 ret operand with the `fn` grammar (`fn-parse-ret-type`, reused as-is). Wired through `emit-defn`, `prescan-defn-signatures`, the compile-time block prescan, `desugar-form` (defn ret rides untouched in the body tail; declare rebuilt to preserve index-3+), generic template registration + tyvar counting (`defn-ret-node`), template stamping (`generic-instantiate` + a new `NODE-KEYWORD` branch in `subst-tyvars-node` so a new-style `:T` return substitutes at stamp time), protocol-sig readers (`proto-sig-parse`, `sig-provides-call`, `proto-sigs-resolve`, and `emit-dyn-forward` — the one read site the in-progress diff missed, which returned `void` for a new-style `(dyn P)` method), `extend`/conformance comparisons, cheader (`cheader-defn-ret-node`), `.nuch` export (`print-defn-name-legacy` normalizes solitary/overloaded to legacy `name:ret`; templates export verbatim new-style) + import (`emit-nuch-declare-import` new-style branch; `register-generic-defn` re-registers a verbatim new-style template), the toplevel `declare`, and REPL redefinition (needs no change — extracts the bare `fname`, delegates the sig parse to the patched `emit-defn`/prescan). The `emit-defn` early `<4` guard now emits `defn-parse-sig`'s targeted "expected return type after the parameter list" for a bare-name missing-ret (error path only; legacy bodyless names keep "bad form"). Change is additive — no source uses the new style yet — so **`make bootstrap` is byte-identical, no `update-bootstrap`**; a new-style program emits IR byte-identical to its legacy twin (verified by diff). Tests (+8, 162/162): `examples/defn-newstyle.nuc`, `tests/repl/s1-newstyle-defn.in`, and a `run-tests.sh` S1 block (`s1-sugar-rets`/`s1-missing-ret`/`s1-newlib` fixtures) covering keyword/`:void`/colon-chain/list-form/`?`/`!`-sugar/tyvar returns, `noreturn` in the new slot, the missing-ret diagnostic, and the cross-unit `.nuch`/cheader round-trip (plain + overloaded link-and-run, template stamps). Pre-existing out-of-scope gap flagged: `--emit-cheader` doesn't skip generic templates (garbage C in **both** styles; `cheader.nuc:1062` needs a `defn-is-generic-template` guard). | [stage14/defn-signature.md](stage14/defn-signature.md) |

---

## Deferral-doc cleanup (2026-07-02)

`stage888-deferred.md` and `stage999-future.md` pruned of done / stage-14-designed / obsolete items. Removed as done: lambdas+closures (13), map/filter/reduce + polymorphism (9/11), collections-in-language (11), Unicode strings + Str protocol (M6), REPL redefinition, `import-only` (12), sum types/`match` (10), colon-chain spellings incl. `car:raw:Node` (CP-1, repro-verified fixed), cast colon sugar, UnaryFn-for-invocables (L7). Removed as designed-in-stage-14: storage classes (attributes.md), `unsafe` block (unsafe-namespace.md), literal-conformance verbosity ×2 (int-widening.md), symbol mangling + `?`-shim (symbol-mangling.md), verbose registry cast bindings (type-safety.md). Removed as obsolete: the pre-stage-10 `with`/null-disarm description, stale `defvar`-integer-only complaint. Verified-still-real and kept (with refreshed anchors): cheader template-instance skip, handler repair over niche `(ref X)` (U4 blocker landed, path not extended — union-emit.nuc:828), `die-at` hook gap (rewritten from conversational leftover), strings-as-Seq (doseq still needs `doseq-iter`+`addr-of` ceremony).

## Portability fixes — ARM64 Linux / LLVM 21 (2026-07-02)

**Two fixes for cross-platform builds**, verified on x86-64/LLVM19 (byte-identical bootstrap, 136 tests pass).

### Makefile: robust LLVM detection

The Makefile hardcoded `llvm-config` without `--link-shared`, which fails on Alpine ARM64 (LLVM 21) where only the monolithic `libLLVM-21.so` is available (no individual component libs). The `2>/dev/null` swallowed the error, leaving all LLVM vars empty → linker errors for every LLVM C API symbol.

**Fix:** auto-detect `llvm-config` across naming conventions (`llvm-config`, `llvm-config-21`, `llvm-config-19`, Alpine paths `/usr/lib/llvm21/bin/llvm-config`), with a three-tier fallback:
1. `--link-shared` (monolithic shared lib)
2. Static component libs (if shared unavailable)
3. Bare `-lLLVM` (if `llvm-config` missing entirely)

Added `--system-libs` (already in `build.ps1` but missing from the Makefile) for musl's extra deps (`-lz`, `-ltinfo`, etc.). A diagnostic line (`LLVM: config=... ldflags=... libs=...`) prints at build time for remote debugging.

### C header parser: musl compatibility

musl's libc headers (Alpine ARM64) omit `extern` on function declarations — valid C, since file-scope functions are implicitly `extern`. glibc includes it. The C header parser at `src/cheader.nuc:654` only tried `c-parse-func-decl` when the token was `extern`, so musl's `int strcmp(...)` was skipped → `unknown: strcmp` error when `lib/macros.nuc` used `strcmp` (imported via the prelude's `(import-use "string.h")`).

**Fix:** restructured the parser to try `c-parse-func-decl` for **any** non-struct/union/typedef token. `c-parse-type` already skips `extern`/`static`/`inline` internally (line 134), so both styles parse identically. If parsing fails (not a function), falls through to the skip logic.

Also added `_Noreturn` (C11 keyword) to the list of qualifiers skipped by `c-parse-type`. musl declares `exit` as `_Noreturn void exit(int)`, and the parser didn't recognize `_Noreturn`, treating it as the base type name → `unknown: exit` error.

### Test portability: null pointer printing

Two tests (`implicit-cast` and `macro-passthrough`) printed null pointers with `printf("%p", NULL)`. This is implementation-defined: glibc (x86-64) prints `0`, musl (ARM64) prints `(nil)`. Tests expected `0` and failed on ARM64.

**Fix:** changed both tests to cast the pointer to `i64` before printing with `%lld`, making output platform-independent. `examples/implicit-cast.nuc:28` and `examples/macro-passthrough.nuc:14` now print pointer values as integers.

Bootstrap artifacts refreshed (`make update-bootstrap`); the new compiler declares additional C functions (`lldiv`, `getentropy`, etc.) because it now parses non-`extern` declarations — expected, not a regression.

---

## Stage 13 — Lambdas and closures (2026-06-25)

**Stage 13 complete.** The four lambda/closure forms landed, split by capture
mode: `fn` (no runtime capture → bare function pointer, C-callable, zero
overhead), `vfn` (clone-capture via the new `Clone` protocol; source always
survives), `mfn` (move-capture via the `move` sink; consumes the source and owns
the resource — the form that exports an owned value out of a `with`), and `cfn`
(reference-capture, allocator-backed env, escape-checked). All four lower to an
anonymous env struct plus a synthesized `invoke` method, callable through the
existing callable-values routing (no fixed arity, no mandatory conformance); a
non-capturing form folds to a plain function pointer.

Supporting work: the `with` escape analysis was **generalized** from owned heap
resources to all frame-local storage (a pointer-provenance check — `let` gains no
drop/lifetime semantics), closing the pre-existing `return &local` UAF; the
**`Clone`** protocol ships with automatic structural conformance for
trivially-copyable types (hand-written for owning types); and a **structural
function-protocol conformance derivation** lets a closure or `fn` literal satisfy
a `&where ((UnaryFn …) F)` / `((FoldFn …) G)` bound with no hand-written
function-object struct (recognized set: `{UnaryFn, FoldFn}`).
Capturing-closure-typed public `defn`s are excluded from `--emit-cheader` and
warn; `fn`-pointer signatures emit normally.

**117 tests pass; `make bootstrap` is a byte-identical fixed point** (L2–L9
additive and inert in the compiler's own source; L1 — the one non-additive phase
— re-converged after a measure-then-flip triage that found no genuine
`return &local` site in the compiler). `examples/closures.nuc` exercises all four
forms inline to `reduce`; `tests/fixtures/closure-escape.nuc` and
`tests/fixtures/closure-cheader.nuc` are the negative/cheader fixtures. Three
**pre-existing** compiler limitations (not closure bugs) cap what is runnable
end-to-end — by-value struct-return ABI corruption, `with`-drop arming for
`TY-PTR` only, and no type inference for anonymous env types — so owning-closure
cases are IR-level-verified only; POD closures over scalars are fully runnable.
Detail: [stage13/progress.md](stage13/progress.md).

---

## Stage 13 follow-up — Variadic `and`/`or` (2026-06-25)

**Variadic logical `and`/`or` landed** as prelude macros, mirroring the
`_+`/`+` split: `and`/`or` are now `&rest` right-fold macros in `lib/macros.nuc`
(`(and)`→`true`, `(or)`→`false`, `(and x)`→`x`, `(and a b c…)`→`(_and a (and b c…))`,
symmetrically for `or` over `_or`). The renamed binary short-circuit primitives
`_and`/`_or` are the actual special forms, routed to the existing
`emit-short-circuit` with unchanged IR labels, and are now **documented public
primitives** usable directly for hand-written binary short-circuit (same exposure
as `_+`).

**Cumulative narrowing is preserved** across variadic chains: the right-nested
binary spine means each clause narrows by all prior ones, so
`(and (!= m null) (m kind) (> (m x) 0))` typechecks (`(m kind)`/`(m x)` see `m`
non-null). The narrowing analyzers (`test-true-nonnull`/`test-false-nonnull`)
were retargeted from the old flat N-ary `(and…)`/`(or…)` loop to recurse both
arms of the new binary `_and`/`_or`.

**1-arg relaxation (accepted semantics change):** `(and x)`/`(or x)` now return
`x` **unchecked** (previously `(and x)` errored `"and expects 2 args"`). Matches
CL/`+` variadic semantics; the i1 check still fires for ≥2-arg forms inside
`emit-short-circuit`.

**Tests:** added `logic` (variadic 0/1/N-arg `and`/`or`) and `and-narrow` (the
3-arg narrowing proof); **117 → 119 pass.**

**Bootstrap deviation worth recording.** The design prompt predicted this change
would be bootstrap-inert (byte-identical, **no** refresh) like `_+`/`+`. That
prediction did **not** hold: renaming a *special form* (statically dispatched via
the hardcoded `(when (= hp …))` chain in the binary) is a breaking bootstrap
change — unlike **binops** like `_+`, which are *runtime-registered* via
`add-binop` at startup, so the old boot already dispatches them (which is why the
`_+`/`+` split is inert but a `_and`/`and` split is not). The fixed point
`build/nucleusc.ll == build/stage2.ll` **does** hold byte-identically after a
one-time regeneration. **Lesson: special-form renames break the boot; binop
additions do not.** (The gotcha and the 2-stage manual bridge are captured in
`context/build.md`; docs updated in `docs/special-forms.md` + `docs/macros.md`.)

---

## Stage 13 — Type erasure: `BoxedFn` + `(dyn Protocol)` (2026-06-27)

**Type erasure complete (TE-0 … TE-7).** 129 tests pass; `make bootstrap` is a
byte-identical fixed point.

The shared fat-pointer machine is built once and instantiated as two user-facing
types:

- **`(BoxedFn (params…) ret)`** — a spellable, fixed-size, owning, heap-boxed
  closure handle. Any `fn`/`vfn`/`mfn`/`cfn` literal assigned into a
  `(BoxedFn …)` slot is automatically heap-boxed; the fat pointer carries a
  static per-env vtable with `invoke` and `drop` slots. Enables
  `(Vector (BoxedFn …))`, `BoxedFn` struct fields, and — critically — a `defn`
  returning a boxed closure by value, closing the CE-4 env-naming gap. A bare
  `fn` pointer boxes via a synthesized per-signature forwarder thunk. Dispatch:
  `(box args…)` or `(invoke box args…)` → indirect vtable call.
- **`(dyn P)`** for an arbitrary user protocol `P` (requires `(extend T P)` on
  the source type) — erases the concrete implementation type. Enables **B2
  unbound-abstract returns** (a `defn` returning `(dyn P)` was previously
  rejected as "unknown type"; now it is a concrete 16-byte struct) and
  **heterogeneous collections** (`(Vector (dyn P))`). Dispatch: `(method-name
  box args…)` → indirect vtable call.

Both types are `Drop`-conforming (shared `@__boxedfn_drop` thunk); neither
requires a new calling-convention (both ride the CE-3 ABI-COERCE2 16-byte
by-value-struct path). Conformance admission is unified: structural for
`BoxedFn` (env `invoke` signature match), nominal `extend` for `(dyn P)`.
All TE phases were byte-identical (no bootstrap refresh needed): the compiler
itself boxes nothing, so zero box IR is emitted during self-compilation.

The CE-4 "design exploration only" designation is fully superseded; the Stage 9
rung-5 `(dyn Protocol)` deferral is implemented. v1 scope limits: single-method
protocols only for `(dyn P)`; no `clone` on boxes (move-only); process-default
libc allocator only (no per-box `AllocHandle`); `BoxedFn`/`(dyn P)` public
`defn`s excluded from `--emit-cheader`. Detail: [stage13/progress.md](stage13/progress.md).

## Stage 13 — Functional refactor R1: new `Iterator` conformers (2026-06-27)

**R1-iter done** (the iterator sub-task of
[functional-refactor.md](stage13/functional-refactor.md) R1; the eager and
closure-returning combinators are separate later dispatches — R1 is not yet
complete). 132 tests pass (+3 examples); `make bootstrap` is a byte-identical
fixed point with **no** `update-bootstrap` (library-only: the compiler imports
none of these libs).

New iterators so the (forthcoming) combinators reach more shapes:

- **`ListIter`** (`lib/list.nuc`) — conforms the cons-cell `Node*` list to
  `(Iterator i64)`, yielding each element (a `Node*`) cast to `i64`. `list-iter`
  constructs one by value. Lets element folds reach AST `Node` cdr-lists without
  changing the cons representation.
- **CStr byte/char iterators** (`lib/strview.nuc`) — `cstr-bytes`/`cstr-chars`
  return a `ByteIter`/`CharIter` over a `CStr`, so a `CStr` byte-folds with
  `reduce` like a `String`. Verified: the FNV-1a hash as a `reduce` over the byte
  iterator equals the hand-written `strview-hash`.
- **`SplitIter`/`LineIter` now conform to `(Iterator i64)`** (`lib/string-split.nuc`),
  replacing the deferred done-flag-only API. A new `cur:StrView` slot holds the
  yielded segment; `next` returns a `(ref StrView)` into it cast to `i64`. The
  `doseq-split` macro hides the decode. The done-flag API is retained and yields
  identical segments (verified by a parity test).

**Design note — the `i64`-pointer encoding.** An `Iterator` element type must
produce a *tagged, matchable* `(Maybe E)` (`reduce`/`doseq-iter` eliminate it
with `match`). `(Maybe ptr)` is niche-encoded and not matchable; `(Maybe StrView)`
(struct payload) breaks the macro-expansion JIT module. So iterators whose
logical element is a pointer or struct yield it cast to `i64` — the
`I64ArrayIter` precedent — and the consumer recovers it with a `cast`.
Examples: `examples/listiter-test.nuc`, `examples/cstr-fold-test.nuc`,
`examples/split-iter-test.nuc`.

---

## Stage 13 — Functional refactor R2: raw-array registry → `Vector` (2026-06-27)

**R2 done** ([functional-refactor.md](stage13/functional-refactor.md) §R2).
All 18 of the spec-listed compiler registries now ride `lib/vector.nuc`'s
`(Vector ptr)` substrate instead of hand-rolled `g-X:ptr` + `g-num-X`/`g-cap-X`
globals (with `malloc`/`memcpy`/`free` growth thunks) or fixed `MAX-*` arena
pre-allocs. 136 tests pass; **`make bootstrap` is a byte-identical fixed point**
(`stage1.ll == stage2.ll`); `make update-bootstrap` refreshed the committed
artifacts.

Converted, one at a time behind `make test` gates (Vector is append-only and
order-preserving, so iteration order is unchanged):

- **Batch 1 — hand-rolled growables** (each *deleted* its `g-num-*`/`g-cap-*`
  globals and `memcpy` growth thunk): `g-generics`, `g-protocols`,
  `g-conformances`, `g-proto-supers`, `g-tmpl-conformances` (all `src/generics.nuc`);
  `g-strs` (string-literal table, `src/scope.nuc` — id stays the element index);
  the parallel `g-fnty-names`/`g-fnty-types` (`src/type-mangle.nuc`); the parallel
  `g-deferror-name-sids`/`g-deferror-msg-sids` (the old `g-deferrors-len` is now
  `count - 1`; a reserved index-0 placeholder keeps the vector index equal to the
  1-based runtime error id; sids are stored in the `ptr` slot via an i64↔ptr cast).
- **Batch 2 — fixed arena pre-allocs** (each replaced its `MAX-*`-sized arena
  alloc with `make-vec`; the `MAX-*` overflow guards are kept, now testing
  `(cast i32 (count g-X))`, so behaviour is exactly preserved): `g-structs`,
  `g-uniondefs`, `g-union-templates`, `g-struct-templates`, `g-enumdefs`,
  `g-binops`, `g-macros`, `g-rmacros`, `g-blanket`, `g-cast-rules`.

**Representation note.** The old inline-array registries stored their entries
*by value* in one contiguous block (`generic-new`/`register-struct`/… returned a
pointer into the array). The migration keeps the **element type `ptr`** (per the
substrate-only invariant): each entry is now individually `arena-alloc`-ed and the
vector holds its pointer. This is strictly *safer* than the old code, whose
`memcpy`-on-grow left previously-returned element pointers dangling/stale; the
arena allocations are pointer-stable for the whole compilation.

**Byte-identical, not just re-converged.** The risk table predicted pointer-origin
drift requiring a controlled refresh. In practice the committed boot already
supports every `Vector` op used (`make-vec`/`conj`/`count`/`invoke`), and the IR
emitted for a given source is a function of registry *contents in order* (not the
internal substrate), so the old boot and the R2 compiler emit identical IR for the
same source — `stage1.ll == stage2.ll` held at every step.

**Out of spec (flagged, not converted).** Three more hand-rolled parallel-array
growables matching the same pattern were found that the §R2 list does **not**
enumerate (added later by the type-erasure commit `c4d973e`):
`g-boxedfn-keys`/`g-boxedfn-types` (`src/union-registry.nuc`),
`g-dyn-keys`/`g-dyn-types`/`g-dyn-protos` (`src/union-registry.nuc`), and
`g-vtable-keys`/`g-vtable-names` (`src/nucleusc.nuc`). They sit on the boxing /
vtable-emission path; converting them is a natural follow-up but was left to a
coordinator decision to avoid scope creep on the spec'd task.

---

## Stage 13 — Functional refactor R3: compiler loop refactor (2026-06-28)

**R3 done** ([functional-refactor.md](stage13/functional-refactor.md) §R3).
Converted `while` counted loops to `dotimes` and `Node*` cdr-list walks to
`doseq-iter + list-iter` across four source-imported compiler files:

- **`src/scope.nuc`**: `program-defn-lookup` (counted `(Vector ptr)` scan → `dotimes`)
- **`src/type-mangle.nuc`**: `fnty-intern`, `fnty-resolve`, `tyvar-index-of` (counted → `dotimes`); `subst-tyvars-sym` (cdr-list walk → `doseq-iter + list-iter`). Added `(import-use list)`.
- **`src/type-utils.nuc`**: no while loops present; left untouched.
- **`src/nuch.nuc`**: eight emission helpers (`emit-nuch-list`, `emit-nuch-defstruct`, `emit-nuch-declare`, `emit-nuch-defenum`, `emit-nuch-defmethod`, `emit-nuch-extend`, `emit-nuch-declare-import`, `emit-nuch-defmethod-import`) → `dotimes`; three cdr-list walks (`emit-nuch-header`, `emit-defunion-import`, `emit-nuch-import-forms`) → `doseq-iter + list-iter`. Added `(import-use list)`.
- **`src/union-registry.nuc`**: seven counted loops → `dotimes` (companion batch by sub-agent).

Non-unit-stride loops and the `scope-lookup` reverse scan were left
as-is per the leave-alone list. 136 tests pass; **`make bootstrap` is a
byte-identical fixed point** (`stage1.ll == stage2.ll`).

### R3 Batch 2 — `src/generics.nuc` counted-loop cluster (2026-06-29)

**Batch 2 complete.** Converted 12 functions' counted `while` scans to
`dotimes` (same-shape swaps; the only IR delta is the `dotimes` init
`(* n 0)` adopting the count's type — clang folds it, and both bootstrap
stages share the change so the fixed point holds):

- `generic-remove-matching-user-method` (first/scan loop only — the
  `(< (+ j 1) …)` in-place compaction loop is LEAVE-ALONE)
- `init-generics` (registry scan over `(count g-binops)`)
- `params-type-eq`, `mangle-fn-name`, `generic-find-method-exact`,
  `generic-binds-for` (method scan + tyvar/spellings scan),
  `generic-resolve` (tier-0/tier-1/tier-2 + nested arg-adapt scans),
  `operator-user-resolve` (exact + widen scans), `unify-tpat`,
  `valid-resolve-type` (widen + generic-template scans),
  `proto-sigs-resolve`, `tmpl-conformance-check-one` (4 scans: null-init,
  arg-seed, bound-recovery with early return, binding substitution)

Leave-alone list respected: `finalize-generics`, `register-generic-defn`,
`recover-assoc-into`, `drain-mono-worklist`, `derive-closure-conformance`,
`emit-extend`, and the `node-type` family are untouched. 136 tests pass;
byte-identical bootstrap.

**Gotcha hit:** a `(return X)` accidentally left inside the `dotimes`
body (one close-paren short on the last in-loop statement) silently
breaks lookups — the function returns on the first non-matching
iteration instead of after the loop. The IR signature is a missing
`inc!`/`br-loop-back` just before a spurious `ret`. Documented in
[functional-refactor.md](stage13/functional-refactor.md) §R3.

### R3 Batch 3 — `src/abi.nuc` + `src/union-emit.nuc` counted loops (2026-06-29)

**Batch 3 complete.** Four same-shape `dotimes` swaps, byte-identical bootstrap:

- `src/abi.nuc`: `abi-union-size`, `abi-struct-align`, `abi-struct-size`
  (counted scans over the `field-types` raw array; the running-offset and
  max-fold accumulators preserved; order-significant `abi-struct-size` stays
  in order since `dotimes` preserves it). `abi-class-eightbyte` is LEAVE-ALONE
  (SysV ABI codegen).
- `src/union-emit.nuc`: `emit-union-construct` (counted scan over `ftypes`;
  sequential GEP offsets preserved). The `emit-match*` family is LEAVE-ALONE.

`src/repl.nuc` `repl-eval-form` was a target but LEFT ALONE: both its remaining
loops start at non-zero (`si:i32 pre-len`, `dj:i32 (+ si 1)`) and don't fit the
counted-from-zero `dotimes` shape without a force-fit. 136 tests pass; byte-identical
bootstrap.

### R3 Batch 4 — `src/nucleusc.nuc` counted-cluster sweep (2026-06-29)

**Batch 4 complete.** 18 loops across 16 functions converted to `dotimes`,
byte-identical bootstrap. Find/lookup shape (`ns-ir-prefix-{set,get}`,
`struct-field-index`, `struct-field-idx`, `generic-resolve-nullable`,
`generic-has-receiver-method`, `vtable-memo-lookup`, `dyn-method-slot`,
`lbl-find`, `enumdef-lookup`, `try-import-path`) plus non-find scans
(`narrow-names`, `ns-prefix-sanitize` byte walk, `admit-erased-conformance`,
`union-drop-arm`, `expand-macro-call` scan, `emit-string-table`, `compile-and-link`).
The paren-placement gotcha from Batch 2 fired twice (`lbl-find`,
`enumdef-lookup`), caught pre-build. LEFT ALONE: `emit-export` (starts at
`i:i32 1`, skips head), `inject-import-aliases` (`[start,end)` slice,
non-zero start), `expand-macro-call` 2nd loop (reverse stride), and the entire
call-emit / body-emit / literal-lowering / closure-synthesis / fixpoint /
state-machine leave-alone list. 136 tests pass; byte-identical bootstrap.

**Strategic finding (Batches 3–4):** the original R3 cluster plan assumed
registry lookups → `find` and registry scans → `any?`/`every?`. That is
**not viable**: every compiler registry is `(Vector ptr)`, and `(Maybe ptr)`
niche-encoding crashes every combinator that internally does
`(match (next it) …)` over a `(VecIter ptr)`. So clusters 1, 2, 6 (the
registry find/any?/for-each sites) stay `dotimes`; only the **AST `Node*`
cdr-list walks** (via `ListIter`, which yields matchable `i64`) can move to
`doseq-iter`+`list-iter`. The remaining R3 work is the `doseq-iter` cluster
over AST cdr-lists (expected to drift; controlled refresh per the bootstrap
policy). See [functional-refactor.md](stage13/functional-refactor.md) §R3.

---

## Stage 13 — Functional refactor R4: library & examples (2026-06-30)

**R4 done** ([functional-refactor.md](stage13/functional-refactor.md) §R4).
Library and examples refactored to use the R1 combinators, `dotimes`, `doseq`,
`doseq-iter`, `doseq-split`, and `memset` where they fit. 138 tests pass;
bootstrap byte-identical (no refresh — examples don't affect the boot, and the
lib/ changes are inert).

**lib/ changes:**
- `lib/strview.nuc`: `strview-char-count` counted loop → `dotimes`; `strview-hash`
  FNV fold → `reduce` over `ByteIter` (requires `ByteIter` definition to precede
  `strview-hash` in the file — moved the struct + conformance above the hash function)
- `lib/string.nuc`: `string-push-bytes-raw` counted loop → `dotimes`
- `lib/hashmap.nuc`: three state-zeroing loops (`hashmap-init`,
  `hashmap-init-alloc`, `hashmap-resize`) → `memset` (matching `hashset.nuc` pattern)

**lib/ evaluated, left alone:**
- hashset set-algebra (`union`/`difference`/`intersection`): walk raw internal
  `states[]` arrays — probe-table internals, leave-alone per design doc.
- UTF-8 validators (`string-push-str`, `string-from-view`, `string-from-cstr`):
  stateful decode (variable `nbytes` advance per step), not a simple counted loop.
- hash-table probe internals, iterator `next` bodies, parser/lexer state machines
  in `reader.nuc`, `memmove`/capacity-doubling in `vector.nuc`: all leave-alone.

**examples/ changes:**
- Counted loops → `dotimes`: `hello.nuc`, `ifwhile.nuc`, `mutual.nuc`
- Hand-rolled → combinators: `assoc-types.nuc` (`collect-all` → `into-iter`,
  `sum-i32-iter` → `sum`, MapIter drive → `for-each`, Vector print → `for-each`);
  `assoc-iter-return.nuc` (`count-coll` → `reduce`); `rest-defn.nuc` (`sum` →
  `reduce` over `ListIter`, `print-each` → `for-each` over `ListIter`);
  `entry-test.nuc` (HashMapEntryIter → `doseq-iter`)
- Vector iteration → `doseq`: `boxedfn.nuc`, `dyn-protocol.nuc`,
  `comb-transform.nuc`, `comb-order.nuc`
- Cons-list walks → `doseq-iter` over `ListIter`: `list.nuc`, `quasiquote.nuc`
- String-split done-flag loops → `doseq-split`: `string-split-test.nuc` (6 sites),
  `split-iter-test.nuc`

**New dogfood examples:**
- `examples/comb-storage.nuc`: wires R1 closure-returning combinators
  (`compose`/`partial`/`complement`/`constantly`) to a `(Vector (BoxedFn (i32) i32))`,
  walks with `doseq`, invokes each box. Proves combinators compose with storable
  closures end-to-end.
- `examples/dyn-comb.nuc`: heterogeneous values behind `(dyn Render)` in a
  `(Vector (dyn Render))`, walked with `doseq` dispatching the protocol method
  through each box's vtable. Proves combinators compose with `(dyn P)` storage.

**Surprises:**
- `sum` combinator name conflicts with user `sum` defn in `rest-defn.nuc` —
  renamed to `sum-args`.

---

## Stage 13 — Niche-encoded Maybe iterator integration (2026-06-29)

**Iterator conversion complete.** The pointer-yielding iterators (`ListIter`,
`SplitIter`, `LineIter`) now yield `ptr` directly instead of `i64` (with explicit
casts). This closes the last major gap in niche-encoded `(Maybe ptr)` support:
iterators over pointer collections can now use the standard `(Iterator E)`
protocol with `match`-able `(Maybe ptr)` results.

**Root fix:** `niche-layout-of` in `src/union-emit.nuc:495` rejected niche-encoded
`(Maybe ptr)` because it checked `elem=null` before checking `pkind`. Since bare
`ptr` has `elem=null` (but `pkind=PTR-REF` after the Phase F flip), niche-encoding
`(Maybe ptr)` produced a type with `pkind=PTR-MAYBE` and `elem=null`, which the
function rejected. Removed the `elem=null` check, allowing it to recognize
`PTR-MAYBE` and `PTR-ERRPTR` regardless of whether `elem` is null.

**Changes:**
- `lib/list.nuc`: `ListIter` conforms to `(Iterator ptr)` instead of `(Iterator i64)`;
  `next` returns `(Maybe ptr)` instead of `(Maybe i64)`
- `lib/string-split.nuc`: `SplitIter` and `LineIter` similarly converted
- `src/union-emit.nuc`: removed `elem=null` check from `niche-layout-of`
- `src/generics.nuc`, `src/nuch.nuc`, `src/type-mangle.nuc`: updated cast patterns
  from `(cast ptr:Node (cast ptr cur))` to `(cast ptr:Node cur)` since elements are
  now `ptr` directly
- `examples/comb-shapes.nuc`, `examples/listiter-test.nuc`, `examples/split-iter-test.nuc`:
  updated consumers to use `ptr` instead of `i64`
- `context/conventions.md`: updated documentation to reflect that `ListIter` yields
  `ptr` directly

**Bootstrap:** `make update-bootstrap` required (the `niche-layout-of` fix changes
the compiler's emit behavior). 136 tests pass; `make bootstrap` is a byte-identical
fixed point.

---

## Stage 12 N9 — Docs, examples, close-out (2026-06-22)

**N9 complete.** Stage 12 fully closed out.

- **`examples/namespaces.nuc`**: comprehensive namespace showcase exercising `import-prefixed` (two libraries: `nsgeom` as `geom/`, `nsgfacade` as `g/`), `import-only` (bare `square` from `mathlib`), `(import "stdio.h" c)` → `c/printf`, `defn-` private helper (`double-area`), and the `export` facade path. 111 tests pass.
- **`docs/toplevel.md`**: added `export` row and "Private definers" combined row covering all 8 `name-` forms (`defn-`/`defvar-`/`defconst-`/`defenum-`/`defstruct-`/`defunion-`/`defmacro-`/`defprotocol-`) with linkage semantics.
- **`design/stage12/progress.md`**: new detailed N1–N9 task table.
- **`design/overview.md`**: reference to `stage12/progress.md` added.

---

## Stage 12 N8 — split `src/nucleusc.nuc` into focused files (2026-06-22)

**N8 complete — six extractions landed (all from `src/nucleusc.nuc`).** Iterative, one-file-at-a-time code motion; `make` + `make test` (110) + `make bootstrap` green after each, boot refreshed and reconverged when relocation perturbed the IR ordering. `src/nucleusc.nuc`: 12,428 → **7,193** lines.

- **`src/type-utils.nuc` (286 lines):** the `; Types` + `; Stage 10: pointer kinds` sections (`make-type`/`types-init`/`type-to-ir`/`type-to-c`/`ptr-int-ir`/`type-size`/`is-int-type`/…/`ptr-pkind`/`type-as-pkind`/`pkind-meet`/`pkind-flow-check`/`require-derefable`). Imported at the same position (before `abi`); depends only on `compiler-types`, the type singletons, `alloc-type`, `fmt-s`, `die-at`.
- **`src/scope.nuc` (177 lines):** symbol table (`scope-new`/`scope-define`/`scope-lookup`/`terminate-after-noreturn`/`scope-push-cleanup`), string-literal table (`intern-string`), codegen helpers (`new-tmp`/`new-label-id`/`reset-function-state`/`in-jit-module`/`program-defn-lookup`/`program-defn-record`). Imported **before** `abi` because `abi.nuc` calls `scope-define`/`new-tmp`; the lone abi-dependent helper `macro-jit-ensure-decl` stays in `nucleusc.nuc` (after the abi import) to break the otherwise-mutual cycle.
- **`src/generics.nuc` (1,962 lines):** the polymorphism registry + bounded-generic def-time checking + Stage 11 T2 tyvar inference/structural unification + Valid inferred-bound checker. Imported **before** `node-type`/emit-* dispatch (just after `union-registry`), since those resolve `generic-lookup`/`generic-find-method-exact`/`generic-has-receiver-method` at emit time.
  - **`src/type-mangle.nuc` (125 lines) — cycle break:** `generics`↔`union-registry` are mutually dependent (`generics` calls `lookup-struct`/`parse-type-from-node`/…; `union-registry` calls `type-spelling`/`type-mangle-token`/`subst-tyvars-node`). The five cross-edge mangling/substitution helpers (`type-spelling`/`type-mangle-token`/`tyvar-index-of`/`subst-tyvars-sym`/`subst-tyvars-node`, transitive closure, needing only `split-colon-segments`) were pulled out and imported **before** `union-registry`, so each file then sees the other's needed functions.
- **Protocols & node-type → appended to `src/generics.nuc` (D + F):** the `; Protocols & conformances` section (≈920 lines) and the `; node-type` non-emitting typing pass (≈324 lines) are each **mutually recursive with the generics machinery** (generics ↔ protocol-lookup/conformance-lookup/emit-extend/…; generic-body checkers `gcheck`/`valid-walk` ↔ node-type/node-type-call/node-type-sym), so neither can sit in a separately-imported file. Both are co-located in `generics.nuc` (1,962 → 3,232 lines), where a single `(import-use generics)` registers all halves before any body emits — the same cycle-break the plan prescribed for protocols. (A standalone `node-type.nuc` was tried and rejected at build: `unknown: node-type-sym`.)
- **Tagged-sum / Maybe / error-handling codegen → `src/union-emit.nuc` (E, 1,554 lines):** the adjacent, mutually-recursive `; Maybe transition forms` + `; tagged-sum construction and elimination` sections (≈1,535 lines, 33 defns: `emit-make`/`emit-union-construct`/`emit-niche-*`/`emit-match*`/`union-target-rewrite`/`stamp-maybe-type`/`emit-not`/`emit-short-circuit`/`emit-ptr-add`/`emit-signal`/`emit-handler-call`/`niche-layout-of`/…). Imported at the section's original position; nothing before it calls in, the forward callers (emit-* dispatch) follow.
- **Late-binding function-pointer hooks (two new back-edges):** moving the protocol/node-type code into `generics.nuc` and the tagged-sum code into the later `union-emit.nuc` created two single back-edges from earlier-imported files: `union-registry.nuc`'s `struct-template-stamp-types` → `tmpl-conformance-check-instance` (now in generics), and `node-type-call` (generics) → `stamp-maybe-type` (now in union-emit). Each is bridged by a `ptr`-typed global hook (`g-tmpl-conf-check-hook`, `g-stamp-maybe-type-hook`), installed in `init-blanket` at compiler-init time and `funcall`ed at the call site after a `cast` to the precise `(fn …)` type. **No bootstrap-host change was needed** — the hooks are plain `ptr` (the committed host cannot null-initialise an `(fn …)`-typed global), so the new source compiles under the old boot.
- **Mechanism:** `import-use` processes a file inline (prescan-then-emit), and the whole-unit defn-signature prescan registers only `nucleusc.nuc`'s own defns (it does not recurse into imports). So an imported file's functions are visible only at/after its import point; a cross-file cycle is resolved either by co-locating the mutually-recursive halves in one file (D/F), by extracting the smaller cross-edge earlier (the `type-mangle.nuc` precedent), or — for a single irreducible back-edge — by a late-binding function-pointer hook (the two above). All N8 moves are pure code motion but not raw-byte-identical to the prior boot (relocation renumbers `@.str.N`/`%N` and reorders `define`s — identical sorted `define` set + string-constant set); each is a self-reproducing fixed point, so the boot was refreshed (`boot/nucleusc.ll` + both Windows boot IRs + `bin/nucleusc`) and reconverged. New/grown files: `src/generics.nuc` 3,232; `src/union-emit.nuc` 1,554.

---

## Stage 12 N7 — source migration + `import` flip (2026-06-21)

**N7 landed (the Phase-F-style breaking flip).** Two green sub-steps:

- **Sub-step 1 (mechanical rewrite):** all `(include X)` → `(import-use "X.h")`, all legacy `(import X)`/`(import "x.h")` → `(import-use …)` across `src/`/`lib/`/`examples/`/`tests/`; the auto-prelude (`prepend-prelude-import`) and the REPL macro-preload string switched to `import-use`. Pure source change — the only IR delta from N6 was the two intended embedded string constants.
- **Sub-step 2 (flip + delete):** `emit-import` now delegates to `emit-import-prefixed`, so bare `import` is prefix-qualified (default prefix = lib's last dotted component, or `c` for a C-header string path). The `include` keyword is fully removed (both dispatch cases, `g-special-form-set` membership, the dead `emit-include` in `src/cheader.nuc`, the REPL `include` branch). C headers now flow only through `import`/`import-use`/`import-only` with a string path.
- **Bootstrap:** N1–N6 had left the committed boot at stage 11 (it only knew the old `include`/`import`, which N1–N6 source still used), so N7 needed the documented two-stage refresh — build the N6 compiler with the stage-11 boot, `make update-bootstrap`, then apply N7 and re-converge. Each sub-step reaches a self-reproducing fixed point (`build/nucleusc.ll == boot/nucleusc.ll`).
- **Verified:** `include` is an unknown form; `(import lib prefix)` resolves `prefix/name`; `(import nsgeom)` dispatches `nsgeom/area` to `@geom__area`. No `(import …)`/`(include …)` call sites remain — only `import-use`/`import-only`/`import-prefixed`/`unsafe-import-private`. Docs swept (`docs/toplevel.md` + ~13 other doc files; the `include` row removed, `import` documented as prefix-qualified). 110 tests pass, bootstrap byte-identical.

---

## Stage 12 N6 — `.nuch` round-trip + tooling (2026-06-21)

**N6 landed (`.nuch` + `--emit-cheader`).** Namespace awareness for the header-emit and import paths so a namespaced library's symbols round-trip with the correct mangled link name.

- **`.nuch` producer (`emit-nuch-header`)**: applies a leading `(ns NAME)` / `set-ir-prefix` before the prescans so `finalize-generics` bakes namespace-mangled overload symbols (`@geom__area.tok`); emits `(ns NAME)` (+ `(set-ir-prefix "...")` when overridden) into the header for non-`user` namespaces.
- **`.nuch` importer (`emit-nuch-import-forms`)**: new `ns` / `set-ir-prefix` dispatch cases set `g-current-ns` (scoped by `do-import`'s save/restore); `emit-nuch-declare-import` (solitary functions) and `emit-extern` (globals) now compute the link name via `ns-ir-base` instead of a hardcoded `@%s`, so `(declare area:i32 …)` rebinds to `@geom__area`.
- **`--emit-cheader` (`emit-cheader-header`/`emit-cheader-declare`)**: applies the leading `ns` / `set-ir-prefix` and emits each C function name via `ns-ir-base` — the C-legal `geom__area`, never `geom/area`.
- All three are identity under `user` → existing headers and the bootstrap stay byte-identical (verified: pre-N6 `bin/nucleusc` and N6 `build/nucleusc` emit identical IR for the compiler source; `make bootstrap` is a fixed point).
- **Deferred:** REPL `apropos`/`locate`/`doc` (and the rest of the documented meta-forms) no longer exist in `repl-eval-form` — dropped in the Stage 11 collections/protocols rewrite of `src/repl.nuc` (last present in commit `f9a4a83`). Restoring the meta-form facility is a separate task; making it namespace-aware presupposes it exists.

**New test:** `tests/fixtures/nsgeomlib.nuc` + a `run-tests.sh` N6 section (`.nuch` carries `(ns geom)`; cheader emits `geom__area` and never `geom/area`; importing the `.nuch` by path resolves `g/area` → `@geom__area`; lib + prelude-excluded consumer link and run `area=42 perimeter=26`). 110 checks pass.

## Stage 12 N5 — `export` re-export (2026-06-21)

**N5 landed.** The `export` facade form (`emit-export`): re-exports an explicit list of qualified symbols under the current namespace's name, reusing the original `Sym`/`ir-name` (a pure resolution alias, no code emitted). `lib/nsgfacade.nuc` (`gfacade` re-exporting `geom/area`/`geom/perimeter`) + `examples/export-test.nuc`. Bootstrap byte-identical.

## Stage 12 N4 — IR mangling + `set-ir-prefix` + cross-namespace conformance (2026-06-21)

**N4 landed.** First stage where IR names diverge for non-`user` namespaces.

- **IR mangling**: symbols in namespace `foo` emit `@foo__bar`; `user` stays `@bar` (bare). `Generic.ir-prefix` snapshots the defining namespace's prefix at `generic-new()` time so monomorphizations in other namespaces still mangle correctly.
- **`set-ir-prefix`**: overrides the IR prefix for the current namespace. An `apply-early-set-ir-prefix` pre-pass applies a leading `set-ir-prefix` before the signature prescan so `finalize-generics` sees the override. Empty string forces bare names (C-ABI escape hatch).
- **String-path `.nuc`/`.nuch` imports**: `do-import` now routes `.nuc`/`.nuch` string paths as Nucleus files, not C headers. Enables `(import-prefixed "/abs/path/lib.nuc" prefix)`.
- **`import-alias-one` fix**: strips namespace qualifier before forming the alias key, so a symbol `geom/area` in the global table aliases as `prefix/area` (not `prefix/geom/area`).
- **Cross-namespace conformance**: `emit-extend` and `verify-conformance-params` apply `strip-ns-qualifier` to type/protocol names so `(extend Circle Area)` in namespace `shapes` resolves against bare-keyed registries.
- **`g-current-ns` initialization** moved before `init-generics` in `compiler-init` to prevent null-pointer crash in `ns-ir-prefix(g-current-ns)`.

**Bootstrap invariant:** Compiler and all libraries are still in `user` namespace — all IR names unchanged. 105 tests pass, `make bootstrap` green.

**New test:** `lib/nsgeom.nuc` (geom namespace library) + `examples/ns-mangle.nuc` + `tests/expected/ns-mangle.out` exercise IR mangling (`@geom__area`) and cross-namespace calls.

---

## Stage 12 N3 — Public/private + internal linkage (2026-06-21)

**N3 landed.** The trailing-`-` private definer variants are implemented across all
name-introducing forms:

- `defn-` / `defvar-` emit LLVM `internal` linkage (equivalent to C `static`) and
  mark the `Sym` with `sym-private=1`. These symbols cannot link from outside the
  compilation unit.
- `defconst-` / `defenum-` mark their `Sym`(s) `sym-private=1` (no linkage
  dimension; compile-time only).
- `defstruct-` / `defunion-` / `defmacro-` / `defprotocol-` route through the same
  handlers with the `g-defining-private` flag set (no `Sym` in `g-globals`; privacy
  is purely about visibility).

**Import filtering:** `inject-import-aliases` (called by prefixed import forms —
`import-prefixed`, `unsafe-import-private`) skips `sym-private=1` symbols unless
`g-import-include-private=1` is set (set by `unsafe-import-private`). `import-use`
imports everything as before (flat-everything behavior).

**Prescans:** `prescan-struct-names` now also handles `"defstruct-"` / `"defunion-"`;
`prescan-defn-signatures` handles `"defn-"` / `"defunion-"`;
`prescan-protocols` handles `"defprotocol-"` — so private type/protocol/fn definitions
work correctly within the same file.

**Bootstrap invariant:** No compiler symbol is private, so all boot artifacts are
byte-identical. 103 tests pass, `make bootstrap` green.

**New test:** `examples/private-defn.nuc` + `tests/expected/private-defn.out` exercise
`defn-` / `defvar-` / `defconst-` within one file; IR shows `define internal` /
`internal global` linkage.

---

## Compiler self-adoption of collections (2026-06-20)

Refactor of `src/nucleusc.nuc` to use the Stage 11 collections where they add
safety or clarity, per [stage11/compiler-collections-refactor.md](stage11/compiler-collections-refactor.md).
Two milestones landed, each byte-identical-bootstrap-preserving (102/102 tests):

- **Hand-rolled `Vec` → `(Vector ptr)`** (was behind a `make-vec`/`vec-*`
  wrapper); the `Vec` struct is removed. Every indexed read of the compiler's
  dynamic pointer tables is now bounds-checked.
- **`special-form-named` / `primitive-type-named`** (`(or (= name "lit") …)` walls)
  → `(HashSet CStr)` membership (`init-name-sets` at startup).
- **cleanup3 Steps A+B** (`[stage11/cleanup3.md](stage11/cleanup3.md)`): deleted
  the `vec-push`/`vec-len`/`vec-get`/`vec-pop` wrappers — globals/locals holding a
  table are typed `(ref (Vector ptr))` / `(ref (HashSet CStr))` and use sites call
  `conj`/`count`/`invoke`/`contains?` directly (no per-use cast); predicate params
  typed `CStr`. Collections are built against a shared **arena** `AllocHandle`
  (`g-arena-alloc`, init first in `compiler-init`; new `hashset-init-alloc` /
  `hashmap-init-alloc` mirror `vector-init-alloc`) — no malloc/leak. Residual casts
  confined to construction sites + four Vec-param helpers. **Bootstrap constraint
  found:** a `(ref (Vector ptr))` in any `defn` *signature* stamps `%Vector.ptr`
  at the whole-unit signature prescan, ahead of the allocator import, breaking the
  prelude's macro-JIT module (`%AllocHandle` undefined) under the unmodified boot —
  so `make-vec` returns `:ptr` and the helpers take `:ptr` (one internal cast).
  Full root-cause + the deferred proper fix in `stage11/cleanup3.md`.
- **cleanup3 Stages 1+2 — drain deferral + `make-vec` retype** (two-stage boot
  refresh, `stage11/cleanup3.md`): **Stage 1** taught `drain-pending-union-irs` to
  skip a queued type whose `TY-STRUCT`/`TY-UNION` field deps aren't yet emitted
  (`pending-union-deps-ready`), leaving it queued for a later drain. Emitted-flag
  tracking is global but `g-type-bufp` is one shared buffer every module
  concatenates, so the flag already means "present in the current module." Dormant
  + byte-identical, then baked into boot (`make update-bootstrap`, incl. Windows
  IRs). **Stage 2** retyped `make-vec` → `(ref (Vector ptr))` and the four helpers'
  Vec params to `(ref (Vector ptr))`, removing all workaround casts; the prescan
  now stamps `%Vector.ptr` early and the deferral defers it past `%AllocHandle`.
  Byte-identical against the refreshed boot, 102/102, abi-test green. Parametric
  defn signatures must use the **list form** (`(make-vec (ref (Vector ptr)))`),
  not colon-sugar (`:ref:(Vector ptr)`), which mis-parses the name. Final
  `update-bootstrap` deferred to Step C.
- **cleanup3 Step C — `(v i)` routes `invoke → get → _get`** (`stage11/cleanup3.md`):
  `emit-callable-value` and its type-pass mirror `callable-value-type` now decide by
  the **callee type** via the new side-effect-free predicate
  `generic-has-receiver-method` (first-param `type-eq` for METHOD-USER, `unify-tpat`
  over the receiver for METHOD-GENERIC). A type with an `invoke` method indexes its
  argument as a **value**, so `(v idx)` evaluates a local `idx` and indexes instead
  of reading a field named `idx`; a plain struct (no `invoke`, no custom `get`) still
  lands on the raw `_get` field intrinsic with byte-identical IR. Byte-identical
  bootstrap required purging the callable field-read form from the `(ref (Vector …))`
  method bodies in `lib/vector.nuc` and `lib/string.nuc` (rewritten to `_get`; only
  `Vector` has `invoke`). `examples/callable.nuc` updated to the new contract and
  demonstrates the local-index case. Final `make update-bootstrap` (incl. Windows
  IRs) run; reconverges byte-identically, 102/102, abi-test green.

- **cleanup3 `into` + `#{…}` for name-sets**: the 72-`insert` run for
  `g-special-form-set` and the 19-`insert` run for `g-primitive-type-set` in
  `init-name-sets` replaced by single `(into g-set #{ … } (HashSetIter CStr))`
  forms. Arena allocation + `hashset-init-alloc` lines unchanged. This is the
  endorsed in-function alternative to global collection literals (which remain out —
  no pre-main static-init). Byte-identical bootstrap, 102/102, abi-test green.

By-value fixed-cap tables (`g-structs`, `g-uniondefs`, `g-*-templates`,
`g-enumdefs`, `g-cast-rules`, `g-strs`), symbol-identity dispatch chains, and
map/reduce/filter were evaluated and left as-is (poor fits — interior-pointer
stability, marginal gain, or closure-less boilerplate; reasons in the design doc
§7). No language surface changed. `make update-bootstrap`/commit pending user
go-ahead.

---

## Stage 0–6 completed items

### Stage 0–5 (complete)
- Stage 0: initial C-hosted compiler targeting LLVM IR
- Stage 1: self-hosting (compiler compiles itself)
- Stage 2: macros, `defmacro`/`gensym`/`funcall-ptr-1`, reader macros
- Stage 3a: libraries and linking
- Stage 3b: C interop — unsigned types, function pointers, C header parsing, `--emit-cheader`

### Stage 6 (all planned items done or deferred)
| Item | Status |
|---|---|
| Float literals (`f32`/`f64`, `+inf.0`/`-inf.0`/`+nan.0`, `fadd`/`fcmp`/`sitofp`/`fptrunc`, C interop) | Done |
| Readable REPL printing (NODE-STR/quoted short-circuit, `#<ptr 0x...>` fallback) | Done |
| `macroexpand` / `macroexpand-1` (REPL forms, optional depth arg) | Done |
| `macroexpand-all` (recursive descent through all subforms) | Done |
| Structured REPL error output (`--repl-format=text\|json`) | Done |
| Line-buffered REPL stdout (`setvbuf` in `repl-main`) | Done |
| N-ary arithmetic macros (`lib/varmath.nuc` → `lib/macros.nuc` via prelude) | Done |
| Extract REPL → `src/repl.nuc` (source-imported by `nucleusc.nuc`) | Done |
| Extract C header handling → `src/cheader.nuc` | Done |
| Move `lib/format.nuc` → `src/format.nuc`, `lib/llvm.nuch` → `src/llvm.nuch` | Done (`design/stage6-libs.md`) |
| Prelude (`lib/prelude.nuc`): auto-prepended to every compilation; `exclude-prelude` opt-out | Done (`design/stage6-libs.md`) |
| Binary primitives renamed `__+` → `_+` etc.; old `__ binops` removed | Done |
| Binary output (`--emit-binary` / `-o`), optimization flag (`-O`) | Done |
| Fix `macroexapnd1` typo | Done |
| `cond` intent / Emacs mode keywords | Done |
| Expressions as values: `cond`/`if` yield branch value; `do`/`let` yield last; `while` is `void`; `defn` implicit return | Done (`design/stage6-expressions.md`) |
| REPL function redefinition (thunk + ORC resource tracker; cross-module callers see new impl) | Done (`design/stage6-redefinition.md`) |
| `&rest` for `defn` (macro-style: cons list built at call site via `@make-cell`) | Done (`design/stage6-rest-optional.md`) |
| `&optional` for `defn` (defaults evaluated at call site, fixed-arity ABI) | Done (`design/stage7/optional.md`) |
| Pointer syntax: `*Node` → `(ptr Node)` / `ptr:Node` sugar; `*` syntax removed | Done (`design/stage6-pointer-syntax.md`) |
| Symbol interning: `(= 'foo 'foo)` is true; reader and `quote` share a process-global intern table; special-form dispatch uses identity instead of `strcmp` | Done (`design/stage6-symbols.md`) |

---

## Deferred (needs design decision or blocked on above)

| Item | Blocker / Note |
|---|---|
| Polymorphic print/read (`def-print-method`) | Now expressible via Stage 9 multimethods/protocols |
| C header library as external `.so` | Separate from internal split already done |
| Stage 3c: bit-fields, `long double`, `_Complex` | Deferred per `design/stage3c.md`; unions done (stage 10), struct ABI done (stage 8) |
| Lambda / closures | `design/stage999-future.md` |
| Map/reduce/filter | Done — M2: lazy `MapIterI64`/`FilterIterI64` + `reduce-*` in `lib/iterator.nuc`; `doseq`/`into` macros in `lib/macros.nuc` |
| Polymorphism / protocol system | Done — Stage 9 (`design/stage9/polymorphism.md`) |
| `dyn`, `defcast` tier | Deferred — see `design/stage9/` §11 / `callable-values.md` |
| Parametric generics (generic structs) | Implemented — Stage 11 prereq; see [stage11/progress.md](stage11/progress.md) |
| Vectors/hashes | Implemented (Stage 11 M3–M5): `Vector`, `HashMap`, `HashSet`, protocols (`Coll`/`Seq`/`Assoc`/`Set`/`Hash`/`Drop`), reader-macro literals `[…]`/`{…}`/`#{…}` — see `design/stage11/progress.md` |
| Gensym reader macro | `design/stage999-future.md` |

---

## Known constraints / gotchas

- **`Node.car`/`Node.cdr` and macro parameters are `(raw Node)`** (were untyped `ptr`). This lets macros and AST-walking code chain member access cast-free — `(p car)`, `((p cdr) car)` — instead of `((cast ptr:Node p) car)`. Existing `(cast ptr:Node …)` on node values stays valid (a no-op `ptr`↔`(raw Node)` reinterpret) but is no longer needed. **Resolved** ([stage14/macro-conditional-casts.md](stage14/macro-conditional-casts.md), MC-1…MC-4 all done): a shared `type-join` now absorbs a bare, elem-less `ptr` branch (quasiquote/`gensym`/`null` results) into the typed side's element type at pkind `raw` — so a `cond`/`if` mixing `(raw Node)` with a bare `ptr` branch joins to `(raw Node)` with **no cast**, and quasiquote/`gensym` results are themselves now typed `(raw Node)` rather than bare `ptr`. Pointer *kind* was never actually a collapse source — kinds meet via `pkind-meet`. Only branches of genuinely different *element* types (`(raw Node)` vs `i32`, or two different struct types) still collapse the join to `void`, which remains a real type error (`let`/`set!` `init type mismatch`, or a macro whole-body `cond` silently returning `null`). All vestigial `(cast ptr:Node …)`/`(cast ptr …)` casts have been deleted from `lib/macros.nuc`. See [docs/macros.md](../docs/macros.md) and [docs/types.md](../docs/types.md).
- Variadic arithmetic macros now live in `lib/macros.nuc` and are auto-prepended via `lib/prelude.nuc`; binary primitives are `_+ _- _* _/`.
- Macro JIT names collide after sanitization if two macros share the same non-alphanumeric character; fixed by appending macro index (`__macro_<sanitized>_<index>`).
- REPL `defn` redefinition uses thunk indirection (`@foo` → load `@foo.tgt` → call `@foo.impl.<N>`) because pure resource-tracker swap leaves cross-module call sites with stale baked-in addresses. See `design/stage6-redefinition.md` "Result".
