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
| 11 | Collections — `Vector`/`HashSet`/`HashMap`/`String`, protocols, iterators, allocators | In progress — M1 (Allocator) + M2 (Iterator + doseq + generic lazy map/filter/reduce) + M3 (`Vector`) + M4 (`Hash`/`HashMap`/`HashSet`) + M5 (reader-macro literals `[…]`/`{…}`/`#{…}`) done; cleanup §1–§4a (colon-paren sugar, keyword/StrView, iterator-test flatten, phantom-tyvar fix) done; associated types (A0–A2) done; **A4 (A4.0–A4.4) done** — extend-site `&where` recovery fully implemented + `.nuch` round-trip + `lib/iterator.nuc` rewritten with generic element-agnostic `MapIter`/`FilterIter`/`UnaryFn`/`FoldFn`/`reduce` (retiring the `*I64` specializations); 89 tests pass ([stage11/assoc-types-extend.md](stage11/assoc-types-extend.md)); M6 (`String`) remaining | [stage11/collections.md](stage11/collections.md), [stage11/progress.md](stage11/progress.md) |

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
