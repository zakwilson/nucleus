# Globals

#### Designer

* `set!` must work on globals
* `defvar` must accept all literal values the language can express
* `extern` should work for Nucleus-to-C and Nucleus-to-Nucleus, not just C-to-Nucleus

Storage classes are deferred. Note it in stage888-deferred.md

#### Robot

Implemented in this branch:

* `set!` on globals already worked in `emit-set` (the `is-local`
  check passes because `defvar`/`extern` register globals with
  `is-local=1`). The REPL doc claim that it didn't was stale relative
  to the source — the bootstrap binary in `bin/nucleusc` predated
  the fix. The new tests (`examples/globals-literals.nuc`,
  `tests/repl/globals.in`) exercise both batch and REPL paths.
* `defvar` literals: added `defvar-init-ir` in
  `src/nucleusc.nuc`, accepting integer literals (any int width),
  float literals (`f32`/`f64`), string literals (storage type
  `ptr`), `null`, `true`/`false` (`i1`), `(char "x")`, and
  `defconst`/`defenum` names (the constant value is folded in).
  Type compatibility is checked at the init site so a bad pairing
  fails compilation. Missing init defaults to zero/`null`/`false`
  by type kind.
* `extern` producing side: a Nucleus `defvar` already emits a
  default-external-linkage LLVM global, so the symbol is visible to
  C and to other Nucleus modules at link time. `--emit-cheader` now
  emits `extern T name;` for `defvar`/`extern` forms (including
  `f32`/`f64` mappings to `float`/`double`), and `--emit-nuch` /
  the nuch importer round-trip `defvar` as `(extern name:type)`.
* Storage classes (`static`, `register`, `thread_local`) are
  recorded in `design/stage888-deferred.md`.

Known limitations not blocking this stage:

* `(import name)` with both `name.nuc` and `name.nuch` present in
  the search path still resolves `.nuc` first, which inlines the
  producing module and duplicates its prelude-derived symbols at
  link time. Workarounds: ship only the `.nuch`, or use
  `(exclude-prelude)` in producing libraries. Cross-module prelude
  deduplication is out of scope for the globals work.
* Struct/array compound literals are not accepted as `defvar`
  initializers — `(StructName ...)` and `(array T ...)` produce
  alloca-backed pointers, which can't appear in static-init position.
  These remain expressions, not literals.
