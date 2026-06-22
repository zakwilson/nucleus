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

- Variadic arithmetic macros now live in `lib/macros.nuc` and are auto-prepended via `lib/prelude.nuc`; binary primitives are `_+ _- _* _/`.
- Macro JIT names collide after sanitization if two macros share the same non-alphanumeric character; fixed by appending macro index (`__macro_<sanitized>_<index>`).
- REPL `defn` redefinition uses thunk indirection (`@foo` → load `@foo.tgt` → call `@foo.impl.<N>`) because pure resource-tracker swap leaves cross-module call sites with stale baked-in addresses. See `design/stage6-redefinition.md` "Result".
