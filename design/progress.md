# Nucleus — Progress Summary

Current branch: `stage6-cleanup`

---

## Done

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
| Structured REPL error output (`--repl-format=text\|json`) | Done |
| Line-buffered REPL stdout (`setvbuf` in `repl-main`) | Done |
| N-ary arithmetic macros (`lib/varmath.nuc`) | Done |
| Extract REPL → `src/repl.nuc` (source-imported by `nucleusc.nuc`) | Done |
| Extract C header handling → `src/cheader.nuc` | Done |
| Fix `macroexapnd1` typo | Done |
| `cond` intent / Emacs mode keywords | Done |
| Expressions as values: `cond`/`if` yield branch value; `do`/`let` yield last; `while` is `void`; `defn` implicit return | Done (`design/stage6-expressions.md`) |
| REPL function redefinition (thunk + ORC resource tracker; cross-module callers see new impl) | Done (`design/stage6-redefinition.md`) |

---

## Pending (designed, not yet implemented)

### `&rest` for `defn` (`design/stage6-rest-optional.md`)
Macro-style (Node list, call-site rewrite). `&optional` deferred after `&rest`.

---

## Deferred (needs design decision or blocked on above)

| Item | Blocker / Note |
|---|---|
| `&optional` for `defn` | After `&rest` |
| Polymorphic print/read (`def-print-method`) | Needs polymorphism mechanism |
| C header library as external `.so` | Separate from internal split already done |
| Stage 3c: unions, bit-fields, struct ABI, `long double`, `_Complex` | Deferred per `design/stage3c.md` |
| Lambda / closures | `design/stage999-future.md` |
| Map/reduce/filter | `design/stage999-future.md` |
| Polymorphism / protocol system | `design/stage999-future.md` |
| Vectors/hashes | `design/stage999-future.md` |
| Gensym reader macro | `design/stage999-future.md` |

---

## Known constraints / gotchas

- Bootstrap (`bin/nucleusc`) predates the macro-name uniqueness fix; variadic arithmetic must live in `lib/varmath.nuc`, not `lib/macros.nuc`.
- Macro JIT names collide after sanitization if two macros share the same non-alphanumeric character; fixed by appending macro index (`__macro_<sanitized>_<index>`).
- REPL `defn` redefinition uses thunk indirection (`@foo` → load `@foo.tgt` → call `@foo.impl.<N>`) because pure resource-tracker swap leaves cross-module call sites with stale baked-in addresses. See `design/stage6-redefinition.md` "Result".
