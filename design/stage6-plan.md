# Stage 6 implementation plan

Implementation plan for the items in [stage6-cleanup.md](stage6-cleanup.md) that don't require further input from the designer. Items deferred for design discussion are listed at the end.

## Status

| # | Item                                                | Status    | Notes                                                                                  |
|---|-----------------------------------------------------|-----------|----------------------------------------------------------------------------------------|
| 1 | Float literals                                      | DONE      | `f32`/`f64` types, `+inf.0`/`-inf.0`/`+nan.0` literals, `fadd`/`fcmp`/`sitofp`/`fptrunc` codegen, C `float`/`double` interop. See [stage6-floats.md](stage6-floats.md). |
| 2 | Readable printing at the REPL                       | DONE      | NODE-STR and quoted forms short-circuit; ptr fallback uses `#<ptr 0x...>`.             |
| 3 | `macroexpand` / `macroexpand-1`                     | DONE      | REPL forms with optional depth arg.                                                    |
| 4 | Structured REPL error output                        | DONE      | `--repl-format=text\|json`. JSON form: `{"file":..,"line":..,"message":..}` per error. |
| 5 | Line-buffered REPL stdout                           | DONE      | `setvbuf(stdout, NULL, _IOLBF, 0)` in `repl-main`.                                     |
| 6 | Loosen REPL redefinition rule                       | DEFERRED  | LLVM C bindings lack resource tracker; ORC main JITDylib rejects redefinition. Design lives in [stage6-redefinition.md](stage6-redefinition.md). |
| 7 | N-ary arithmetic via macros                         | DONE      | Lives in `lib/varmath.nuc` (not `lib/macros.nuc`) to avoid bootstrap collision.        |
| 8 | Extract REPL into its own source file               | TODO      |                                                                                        |
| 9 | Extract C header handling into its own source file  | TODO      |                                                                                        |
|10 | Fix `macroexapnd1` typo                             | DONE      |                                                                                        |

## Discoveries during implementation

These are constraints/bugs that were not apparent from the design and that future work needs to know about:

**1. No float type at all.** The plan assumed a `double` type existed. It doesn't — there's no `TY-F32`/`TY-F64`, no `fadd`/`fmul` codegen, no float type name. Step 1 was descoped; floats need a dedicated design pass.

**2. `cond` does not propagate values.** `emit-cond` (`src/nucleusc.nuc:1573`) hard-codes `(return (alloc-val ty-void null))`. So `(cond test1 expr1 test2 expr2 ...)` always returns void, regardless of branch values. This forced the variadic-arithmetic macros into a `(let (result ...) (cond ... (set! result ...)) result)` shape. This is a concrete instance of the deferred "expressions-as-values" item in stage6-cleanup.md and is the highest-impact thing to fix in that area.

**3. Macro JIT names collide after sanitization.** `sanitize-for-ir` collapses any non-alphanumeric character to `_`, so `+ - * /` (and `->`) all sanitize to identical strings. With only `->` defined this is harmless; adding `+` would collide. Fixed by appending the macro index: `__macro_<sanitized>_<index>`.

**4. `bin/nucleusc` (committed bootstrap) cannot compile a source tree that uses the variadic macros directly via `(import macros)`.** The bootstrap predates the macro-name uniqueness fix. Worked around by putting variadic arithmetic in `lib/varmath.nuc` (not imported by the compiler itself). A bootstrap update would let us move them into `lib/macros.nuc`.

**5. Step 6 (redefinition) needs new LLVM bindings.** The current `lib/llvm.nuch` doesn't expose `LLVMOrcCreateNewResourceTracker` / `LLVMOrcResourceTrackerRemove` / `LLVMOrcLLJITAddLLVMIRModuleWithRT`. Without those, ORC's main JITDylib rejects symbol redefinition. The alternative is per-redef IR-renaming, which requires plumbing an `ir-name` parameter through `emit-defn`.

## Scope

Original plan items, ordered. (Status above.)

1. Float literals (read + print) — DEFERRED
2. Readable printing of values at the REPL
3. `macroexpand` / `macroexpand-1` REPL builtins
4. Structured REPL error output
5. Line-buffered REPL stdout
6. Loosen the "cannot redefine" REPL rule — DEFERRED
7. N-ary arithmetic via macros
8. Extract REPL into its own source file
9. Extract C header handling into its own source file
10. Fix `macroexapnd1` typo wherever it appears

Deferred (require designer input — see end of file):

- Polymorphic print/read mechanism
- `&rest` / `&optional` for `defn` — see [stage6-rest-optional.md](stage6-rest-optional.md)
- Implicit-return / expressions-as-values — see [stage6-expressions.md](stage6-expressions.md) (now also blocking step 6 of stage6-cleanup readability — see Discovery #2)
- C header library as a true external `.so` (vs. internal source split)
- Float type — see [stage6-floats.md](stage6-floats.md)

## Order of implementation

The order is chosen so each step is independently testable and so later steps build on the infrastructure of earlier ones. Float literals come first because they unblock test cases for printing. Modularization comes near the end because it churns line numbers and makes intermediate diffs noisy.

### 1. Float literals (read + print)

**Reader.** Extend the tokenizer to recognize `1.5`, `-0.25`, `1e10`, `1.5e-3` as a new node kind (`NODE-FLOAT`). The existing integer path in the reader already handles a leading `-` and digits — the float path is "saw a `.` or `e` while reading a numeric token." Reuse `strtod` from libc.

**Printer.** Add a float branch to `print-node` (`src/nucleusc.nuc:322`). Use `%g` for the default format. Round-trip is *not* guaranteed by `%g`; if that matters, use `%.17g` (the standard "exact double" precision) — pick `%.17g` and accept slightly uglier output over silent precision loss.

**Codegen.** The compiler may already lower float literals if any are emitted; verify, and if not, emit them as LLVM `double` constants.

**Test.** Round-trip: `(read (print 1.5))` returns a float node equal to 1.5. Self-host pass.

### 2. Readable printing at the REPL

The REPL's `repl-eval-form` (`src/nucleusc.nuc:3740`) currently prints the result as a raw integer / pointer regardless of the expression's static type.

**Approach.** The JIT knows the declared return type of the top-level expression. Dispatch on it:

- `i8`/`i16`/`i32`/`i64` → print as integer (current behavior).
- `double` → print via the new float printer (step 1).
- `ptr` returned from a string literal or a function declared as `:ptr` whose value is a `\0`-terminated byte array → print as a quoted string. Heuristic: if the expression is a string literal, print as string. Otherwise print `#<ptr 0x...>`. Don't try to guess.
- Quoted lists / `Node*` → reuse `print-node`.
- Structs (by-value) → print as `#<StructName ...>` with field values, recursively.
- Function pointers → `#<fn 0x...>`.

The reader must reject `#<...>` syntax with a clear error so a printed unreadable value is never silently accepted as input.

**Test.** REPL session demonstrating each type prints sensibly. Strings round-trip.

### 3. `macroexpand` / `macroexpand-1`

`emit-macro-expand` at `src/nucleusc.nuc:1651` already does the work. Expose two REPL-only forms:

- `(macroexpand-1 'form)` — one expansion step.
- `(macroexpand 'form)` — expand to fixpoint (head symbol is no longer a macro).

Optional depth: `(macroexpand 'form n)` — expand at most `n` steps. `n = -1` for fixpoint. Make the depth arg optional with default `-1`; this subsumes both names but keep `macroexpand-1` as an alias.

Result is a `Node*`, printed via the existing AST printer.

**Test.** Expanding `(when c body)` produces `(if c (do body))`. Expanding a non-macro returns the form unchanged. Expanding `(macroexpand-1 '(when ...))` shows one step only.

### 4. Structured REPL error output

Today's REPL errors print free-form text. Add an opt-in flag `--repl-format=json` (default `text`) that prints errors as a single JSON object per error: `{"file": ..., "line": ..., "form": ..., "message": ...}`.

Plumb the existing error sites in the REPL through a single `repl-error` helper that branches on the format. Don't try to retrofit every `fprintf(stderr, ...)` in the compiler — only the REPL's own error paths matter for an agent driver.

**Test.** Trigger a parse error, an IR error, and a JIT error in JSON mode and verify each is one valid JSON object on stderr.

### 5. Line-buffered REPL stdout

`docs/builtins.md` notes that JIT'd code's stdout is block-buffered when the REPL is driven by a pipe. Fix in `repl-main` (`src/nucleusc.nuc:4066`): call `setvbuf(stdout, NULL, _IOLBF, 0)` on entry. This is the standard C fix and costs nothing.

**Test.** `printf '(printf "hi\\n")\n' | nucleusc -i` prints `hi` before EOF.

### 6. Loosen the "cannot redefine" REPL rule

Currently the REPL refuses to redefine a function (JIT limitation noted in `docs/builtins.md`). The fix is to JIT each redefinition into a fresh module: ORC supports having multiple modules, and symbol resolution in a JIT dylib uses the *latest* definition.

**Approach.** When `repl-eval-form` encounters a `defn` for a name already defined:

1. Compile the new definition into a new LLVM module.
2. Add the module to the existing JIT dylib. ORC's default symbol-conflict policy is "first wins"; switch to "replace" by removing the old symbol first, or by compiling each REPL form into its own module from the start (simpler, recommended).

Changing every REPL form to live in its own module is the cleanest design: `repl-jit-module` (`src/nucleusc.nuc:3988`) becomes per-form, not per-session. It also makes structured errors per-form trivially correct.

Caveat: function pointers captured from the old definition still point to the old code. Document this; it's the same limitation any JIT'd Lisp has.

**Test.** Define `foo` returning 1, redefine returning 2, call `foo` and get 2. Define `foo` calling `bar`, define `bar`, call `foo` — works.

### 7. N-ary arithmetic via macros

Add to `lib/macros.nuc` (or wherever the standard macros live). For each of `+ - * /`:

```
(defmacro + (&rest args)
  (cond (nil? args)        0
        (nil? (cdr args))  (car args)
        true               (list '+ (car args) (cons '+ (cdr args)))))
```

…with the binary `+` being the existing builtin. Same shape for the others, with the right identity element (`-` and `/` need special-casing for the unary form: `(- x)` → `(- 0 x)`, `(/ x)` → `(/ 1 x)`).

Macro names collide with builtin names; the macro takes precedence at the form level, and the macro expansion calls the builtin. This works because the recursion in the macro expands `(+ a b c)` → `(+ a (+ b c))` → `(+ a (+ b c))` (binary builtin call); the head of the inner form is still the macro, so it expands again until it bottoms out at two args.

If symbol resolution doesn't currently let a macro shadow a builtin, this needs a small fix in the lookup order. Verify before implementing.

**Test.** `(+ 1 2 3 4)` → 10. `(+)` → 0. `(+ 5)` → 5. `(- 10 1 2 3)` → 4. Works in batch and at the REPL.

### 8. Extract REPL into `src/repl.nuc`

Move `repl-*` functions (`repl-read-input`, `repl-eval-form`, `repl-jit-module`, `repl-include-all-libc`, `repl-register-node`, `repl-main`, plus helpers — roughly `src/nucleusc.nuc:3669–4105`) into `src/repl.nuc`.

`src/nucleusc.nuc` does `(import repl)` as a *source* import. Resulting binary is unchanged; only the file layout differs.

The REPL needs access to compiler internals (the macro table, the type registry, `emit-*` functions). Source imports inline definitions, so this works without designing a public API. Document in `context/build.md` that the REPL's dependence on compiler internals is intentional.

**Test.** Compiler still self-hosts. REPL session still works. Diff is purely a move + an `import`.

### 9. Extract C header handling into `src/cheader.nuc`

Move `emit-include`, `emit-c-include`, `read-pipe-output`, the C declaration parser, and the cheader emitters (`emit-cheader-*`) into `src/cheader.nuc`. Same source-import strategy as step 8.

Approximate ranges in current source: `1867–1886`, `2187–2207`, `2208–~2400` (parser), `3323–3450` (emitters). Verify by reading before moving — line numbers will have drifted by the time this step runs.

**Test.** Self-host. `(include stdio)` still works. `--emit-cheader` still produces correct output for `lib/mathlib.nuc`.

### 10. Fix `macroexapnd1` typo

Grep the design directory for `macroexapnd1` and fix to `macroexpand-1`. Trivial — bundle with whichever of steps 3 or 8 lands first.

## Bootstrap considerations

Steps 1–7 add features without changing the bootstrap surface. Steps 8–9 are pure file moves with `import` glue; the bootstrap compiler must be rebuilt after the move because the source layout changed, but no semantic change is required.

## Completion criteria

This stage is complete when:

- Float literals can be read, printed, and round-tripped.
- The REPL prints values of every built-in type in a form distinguishable from a raw integer or pointer; strings round-trip.
- `(macroexpand 'form)` and `(macroexpand-1 'form)` are available at the REPL.
- The REPL has an opt-in JSON error format suitable for driving by an agent.
- JIT'd stdout is line-buffered in REPL mode regardless of whether stdin is a terminal or a pipe.
- A function can be redefined at the REPL.
- `(+ 1 2 3 4)` and the other arithmetic operators accept arbitrarily many arguments.
- `src/nucleusc.nuc` no longer contains the REPL or C header handling; `src/repl.nuc` and `src/cheader.nuc` exist and are source-imported.
- The compiler self-hosts and the existing test suite passes.

## Deferred — needs designer input

These items appear in `stage6-cleanup.md` but the implementation choice depends on a design call that should be made before coding starts.

- **Polymorphic print/read.** The honest minimum is a hash table from type-id to printer fn, populated by `def-print-method`. That's not a real generic-function system. Whether to ship it as a stopgap or wait for a designed polymorphism mechanism is a designer call.
- **`&rest` / `&optional` for `defn`.** Three reasonable designs (Node-list rest matching `defmacro`, C-style `...` for interop, named optional with default expression). Each constrains the others. Worth its own design pass.
- **Implicit-return / expressions-as-values.** Largest semantic change in the section. Touches every `defn` that relies on falling off the end. Needs a designer decision on `return` semantics in nested expressions and a flag-day plan for the bootstrap.
- **External-library form of cheader split.** Step 9 above does an internal source split. Promoting `cheader` to a real `.so` loaded at compiler startup is a separate decision tied to the broader question of whether the compiler should depend on runtime libraries.
