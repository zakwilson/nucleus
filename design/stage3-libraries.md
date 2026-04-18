## Libraries

The Nucleus compiler already supports loading C libraries, but lacks libraries of its own. They are added in this phase.

### Native libraries

#### Designer:

Nucleus must be able to use libraries written in Nucleus. `import` should be usable with Nucleus code and should be able to import everything defined there including macros.

There should be a way to use a library *only* at compile-time. It would be simple if that could just be `(compile-time (import foo))`. It would be *great* if there was a good error message for code that uses something imported only for compile-time at run-time.

The ideal implementation would have a more sophisticated module system with a way to mark symbols private and optionally aliased imports:

`(import foo.bar :as bar)
`(bar/baz)

or without adding keyword arguments

`(import-as foo.bar bar)
`(bar/baz)

It must be possible to import Nucleus libraries, including their macros without their source code. That ability must come without a runtime cost or bloating binaries produced by the Nucleus compiler. That implies a dedicated .nuch header file format for Nucleus. It should use an S-expression syntax.

#### Robot:

The current `include` only handles C libraries via a hardcoded libc declaration table (`emit-include` / `g-libc`). Nucleus-native import needs a completely separate path that reads `.nuc` source (or `.nuch` headers) and processes the forms into the current compilation.

**Import mechanism.** A reasonable approach:

1. `(import foo)` resolves `foo` to a file path (e.g. `lib/foo.nuc` relative to a search path). The compiler opens the file, runs the reader on it, and processes the resulting forms as top-level definitions — emitting LLVM IR into the current module's declaration stream the same way inline code would be.

2. Macros defined via `defmacro` in the imported file get JIT'd and registered in the global macro table as usual. Since `defmacro` already works through the JIT pipeline, this should compose naturally — the imported file's `defmacro` forms go through `emit-defmacro` just like local ones.

3. A symbol table per-import tracks what names came from where, enabling duplicate detection and future aliasing.

**Compile-time-only imports.** `(compile-time (import foo))` should work with the existing `emit-compile-time` infrastructure. The key constraint: names defined in a compile-time import get registered in a "compile-time-only" scope. If codegen later tries to reference one of those names outside `compile-time`, the compiler can emit a clear error like `"symbol 'bar' was imported compile-time-only (from foo); it is not available at run-time"`. This requires tagging scope entries with a "ct-only" flag and checking it during `emit-ref`.

**Module system / aliased imports.** The `(import-as foo.bar bar)` form is simpler to implement than keyword arguments since the language doesn't have keywords yet. Internally this is just a prefix rewrite: every symbol `baz` exported from `foo.bar` gets registered in the current scope as `bar/baz`. The `/` is already a legal identifier character in Nucleus symbols, so no lexer changes needed — the aliased names are just symbols that happen to contain `/`.

Private symbols could use a convention: names starting with `_` or a dedicated `(private)` declaration. A `(private)` form is more explicit and doesn't conflict with C interop naming.

**The `.nuch` header format.** This is essential for distributing compiled libraries without source. A `.nuch` file would be an S-expression file containing:

- Function signatures: `(declare foo (fn (i32 ptr) i64))` — name, parameter types, return type
- Struct definitions: `(defstruct Point x:i32 y:i32)`
- Macro definitions: the full `defmacro` form, since macros are source-level transforms and must be available as source
- Constants: `(defconst FOO 42)`

When the compiler sees `(import foo)` and finds `foo.nuch` (but no `foo.nuc`), it processes declarations without emitting function bodies — just `declare` in the IR — and registers macros for JIT as usual. The linker then resolves the function symbols from the corresponding `.o` or `.a` file. No runtime cost, no binary bloat beyond what's actually called.

**Risks.** Circular imports need cycle detection (a simple "currently importing" set). Macro ordering across files could be tricky — if file A's macro uses file B's macro, import order matters. The compiler currently processes forms sequentially, which is actually an advantage here: imports are processed in order, and all their definitions are available to subsequent forms.

#### Designer:

This is not the time to add keyword arguments (if ever, given C compatibility). An `import-as` macro or special form will do.

For now, built-in forms that create symbols as private get a `-` appended, like Clojure. `defn-`, `defstruct-`, and so on.

### C compatibility

#### Designer:

Nucleus libraries must be consumable from C. A tool is required to produce C-compatible .h headers from Nucleus code or .nuch headers.

C obviously can't use Nucleus macros, so they should not be exposed in .h headers.

#### Robot:

Straightforward. Once the compiler can read `.nuch` headers, generating C-compatible `.h` files is a translation pass over the same data:

- Function declarations map directly: `(declare foo (fn (i32 ptr) i64))` → `int64_t foo(int32_t, void*);`
- Struct definitions map to C structs with the corresponding C types.
- Macros are skipped entirely (as noted).
- Constants become `#define` or `extern const` depending on whether they're compile-time-known.

A standalone tool (`nuc-header` or a compiler flag like `nucleusc --emit-header foo.nuch > foo.h`) is cleanest. The type mapping is mechanical — Nucleus already has a fixed set of primitive types that correspond 1:1 with C types. The only subtlety is `ptr` which maps to `void*`, and struct pointers which should map to the named struct type.

This tool should also emit an include guard (`#ifndef FOO_H` / `#define FOO_H` / `#endif`) and optionally `extern "C"` wrapping for C++ consumers.

### Compiler refactor

#### Designer:

Once libraries work, the compiler should be refactored to use them. Its data structures and functions for manipulating code should be a library usable by other code. The inlined macros are already in a separate file, but not yet usable as a library.

#### Robot:

This is the payoff step. The compiler (`nucleusc.nuc`) currently has several components that are general-purpose but trapped inside the monolith:

1. **Reader/parser** — S-expression reader, `Node` allocation, token handling. This is useful to any tool that processes Nucleus source (linters, formatters, REPL, the header tool above).

2. **Node/list utilities** — `node-at`, `node-len`, `cons`, `first`, `rest`, etc. Already partially extracted to `lib/list.nuc`, but the compiler uses its own inline versions. These should converge into one library.

3. **Type system** — `Type` structs, `type-to-ir`, `kind-to-type`, type checking. Useful for any tool that needs to reason about Nucleus types.

4. **Scope/symbol table** — `scope-define`, `scope-lookup`. General-purpose and useful for macro expanders or analysis tools.

5. **Macro infrastructure** — `lib/macros.nuc` is already a separate file but must be copy-pasted (the file itself says so). Once import works, this becomes `(import macros)` and the copy-paste comment can be deleted.

The refactoring order matters. The import mechanism should be built first (previous section), then:

1. Extract reader into `lib/reader.nuc` + `reader.nuch`
2. Unify `lib/list.nuc` with the compiler's inline list operations
3. Extract type system into `lib/types.nuc`
4. Extract scope into `lib/scope.nuc`
5. Have the compiler `(import reader)`, `(import list)`, etc.

Each extraction step should be followed by a self-compilation test — the compiler must still compile itself after each change. This is the project's existing correctness gate and it's well-suited here since any breakage in the extraction will show up immediately.

The result: the compiler becomes a relatively thin driver that imports its components, and those components become available to other Nucleus programs. The `nuc-header` tool from the C compatibility section would be one of the first consumers.

### Pre-implementation

#### Robot:

Questions and decisions that should be resolved before implementation begins.

**1. Import search path.** Where does `(import foo)` look for `foo.nuc` / `foo.nuch`? Options: relative to the importing file, relative to a `lib/` directory alongside the compiler, an environment variable (`NUC_PATH`), or some combination. The compiler currently has no concept of a search path — `read-file` takes an absolute or relative path and that's it. A minimal first pass could be: look relative to the importing file first, then relative to a built-in `lib/` directory.

**2. Linking model.** The compiler currently emits a single LLVM IR module to stdout (`printf` at the end of `main`). Importing a `.nuc` file can inline its definitions into that same IR stream, but importing a `.nuch` header implies separate compilation — the imported library's code lives in a `.o` or `.a` that the linker must pull in. The current build flow (`nucleusc foo.nuc | llc | clang`) has no mechanism for passing extra object files to the linker. This needs a solution before `.nuch` imports are useful. Options: (a) the compiler emits link flags as comments or a manifest, (b) a build driver / wrapper script handles it, (c) `import` of `.nuc` files always inlines (no separate compilation initially) and `.nuch` + separate linking comes later.

**3. Re-export semantics.** If library A imports library B, and program C imports A — does C see B's symbols? Transitive re-export is simpler to implement (just flatten everything into the global scope) but pollutes the namespace. Non-transitive requires tracking which symbols are "owned" vs "imported" and only exposing owned ones. The private-symbol convention (`defn-`) partially addresses this, but a non-private helper from B would still leak through A if re-export is transitive.

**4. Private macros and `.nuch`.** The designer specifies `defn-`, `defstruct-`, etc. for privacy. This convention needs to extend to `.nuch` generation: private symbols should be excluded from `.nuch` headers. But a public macro might expand into calls to private helper functions. Those helpers must still be accessible at link time even though they're not in the `.nuch`. The `.nuch` generator should omit private *declarations* but the `.o` still contains their definitions — the linker resolves them. This works as long as nothing else tries to call them by name.

**5. Compile-time import of header-only libraries.** `(compile-time (import foo))` with only `foo.nuch` + `foo.o` available: macros work (they're source in the `.nuch`), but compile-time *functions* can't be JIT'd from a native `.o`. The JIT needs LLVM IR or bitcode. Options: (a) require `.nuc` source for compile-time imports, (b) distribute `.bc` (LLVM bitcode) alongside `.o` for libraries that support compile-time use, (c) defer this — compile-time import of header-only libraries is an edge case that can wait.

**6. `include` vs `import` unification.** Should `(include stdio)` eventually become `(import stdio)` with the C libc table treated as a built-in set of `.nuch`-like declarations? Or do they stay permanently separate? Unifying them simplifies the mental model (one way to bring in external code) but the C declarations are hardcoded in `init-libc` / `add-libc` and are structurally different from Nucleus declarations. A pragmatic path: keep `include` for C libraries now, but design `import` so that a future `(import c.stdio)` could replace it if the C declarations were moved to actual `.nuch` files.

**7. Duplicate import guards.** If two files both `(import list)`, the second import should be a no-op rather than redefining everything. This requires tracking which modules have already been imported in the current compilation (a simple set of resolved paths). The `compile-time` variant needs the same guard for its JIT module table.

**8. Order of implementation.** Revised based on designer decisions. Imports are inlines; linking, `.nuch`, and header-only are deferred.

   1. **Extract the top-level dispatch into a function.** The main emit loop and pre-scan are currently inline in `main`. A function like `(defn emit-toplevel-forms:void (forms:ptr ...))` that takes a form list and the output streams is needed so that `import` can call it recursively on the imported file's forms. The pre-scan (forward-declaring `defn` signatures) must also run on the imported forms before emitting them.

   2. **Save/restore reader state around imports.** The reader uses four globals: `g-src`, `g-pos`, `g-line`, `g-source-path`. Importing a file means saving these, running `read-file` + `read-program` on the new source, processing the forms, then restoring the originals. This is straightforward — save to locals, restore after.

   3. **Add file resolution.** Resolve the import symbol to a `.nuc` path. Check `NUC_PATH` env var first (colon-separated list of directories), then fall back to: directory of the importing source file, then `lib/` relative to cwd. Use `access(path, F_OK)` or `fopen` to test existence.

   4. **Add duplicate import guard.** A global array or linked list of resolved absolute paths (via `realpath`). Before processing an import, check if it's already been imported. If so, skip silently. This must be in place before testing to avoid infinite loops in the circular-import case, and because compile-time side effects must not double-fire.

   5. **Add cycle detection.** A "currently importing" set (separate from the "already imported" set). If a file appears in the currently-importing set, it's a circular import — emit an error. Entries are added on import entry and removed on import completion.

   6. **Wire up `import` in the dispatch.** Add `(= (strcmp h "import") 0)` to the main `cond` in the emit loop. The handler calls the extracted top-level dispatch on the imported forms.

   7. **Test with `lib/macros.nuc`.** Write a test program that does `(import macros)` and uses `if`, `when`, `->`, etc. Verify the compiler compiles itself with `(import macros)` replacing the inlined macro definitions. This is the first real validation.

   8. **Add `import-as` prefix rewriting.** `(import-as foo bar)` imports `foo.nuc` but registers all its exported symbols with a `bar/` prefix. Requires intercepting `scope-define` calls during import to prepend the alias.

   9. **Add `defn-` / `defstruct-` / `defmacro-` private forms.** New top-level form variants that set a "private" flag on the symbol. Private symbols are not re-exported when a module is imported by another module (relevant once non-transitive export is enforced).

   10. **Enforce no transitive re-export.** During import, track which symbols are "owned" (defined in this file) vs "imported" (brought in from another file). Only owned symbols are visible to importers of this file. This interacts with step 9 — private symbols are not exported at all, imported symbols are not re-exported.

#### Designer:

Import search path should be read from an environment variable and a compiler flag. If unset, it should default to relative to the source file and the `lib` directory relative to the working directory.

For a first pass, imports are inlines. Linking is deferred at this stage, but C-compatible linking is the goal.

No implicit transitive re-export. A namespace only exports symbols it creates or explicitly exports.

Preventing users from shooting themselves in the foot by using private symbols in macros is deferred. Using private symbols in public macros is simply discouraged for the moment, but may become an error.

Header-only libraries are deferred because linking is deferred.

`import` and `include` are separate for now. Using arbitrary C libraries is a near-future goal, perhaps by linking clang.

Nucleus will guard against duplicate imports. This is important because code can have side-effects at compile-time.
