# Future plans

Nothing here is fleshed out. Some ideas may be bad. Things here may never be implemented, or may be impossible.

## Lispiness

Nucleus is a replacement for C, but it should bring in as much Lisp goodness as it can without compromising C interop or adding runtime overhead.

### Lambda

Obviously

### Map/reduce/filter

Polymorphic on Seq

### Polymorphism in general

With static typing and compile-time dispatch, this should have no runtime cost. I'm imagining a protocol/interface system in addition to concrete types

### Declarable blanket protocols

Stage 9 hardcodes the two blanket (auto-conforming) protocols `Any` (every type) and `Struct` (every struct) — see `design/stage9/polymorphism.md` §10.1. A general, *declarable* facility — letting a library define its own blanket protocol with a compiler-checkable conformance predicate — is deferred here. It would generalize the hardcoded pair into one mechanism, at the cost of a way to express "which types conform" in source.

### Redefinition

The ability to redefine vars and fns in the REPL would be helpful. We don't have dynamic scope and probably shouldn't add it, so that implies recompiling everything depending on the var in question. The time to do that is acceptable, but the implementation complexity may not be.

### Closures

Lexical closures are a huge win for abstraction. Representing them in C may be tricky, but maybe there's a workaround or a way to give C a limited interface. Lifecycle could also be tricky.

### Gensym reader macro

Probably `#`, semantics like Clojure but not the postfix syntax

## Data structures

### Vectors and hashes as part of the language

Clojure uses these well. Not included by default at runtime of course, but good general-purpose implementations people would want to import if they don't need something purpose-built.

### defcall

Probably a subset of polymorphism. In Clojure, many things that are not fns in the traditional sense can be called as fns.

A type should be a cast (and maybe this should rely on defcast, or maybe it should be a new mechanism allowing destructive operations). A struct should be field access.

## Sum types and match

Tagged unions with a `match` form, noted as adjacent follow-ons from stage 10
(see stage10/safety.md §3) along with bounds-checked slices and
`const`/read-only pointers. `(Maybe T)` over a non-pointer payload needs this
(stage10/nullability.md §1), as does the generic `(Result T E)` error-handling
option (stage10/errors.md §2). Niche encoding for the pointer cases should be
something the layout engine applies, not a special case.

**Now designed in [stage10/unions.md](stage10/unions.md)** (untagged C
unions + `defunion`/`match` + explicit-instance templates + the niche layout
rules). Bounds-checked slices and `const` pointers remain here.

## Editor integration

Local Emacs interaction (eval-from-buffer, completion, jump-to-definition,
describe, macroexpand, REPL plumbing over `nucleusc -i`) landed in stage 7
— see `design/stage7/interaction-mode.md` and `docs/emacs.md`. Other
editors (VS Code, neovim) and any network protocol are deferred.


## Memory management

The `with` form (added in stage6) is `let` plus auto-free for any binding
whose init expression is a libc allocator (`malloc`/`calloc`/`realloc`/`strdup`,
including through `cast`). Cleanups fire on fall-through and on early `return`
inside the body. Disarming a single binding is done by storing `null` to it,
since `free(NULL)` is a no-op.

Open question: whether to flip the default so plain `let` itself auto-frees,
with `let*` as the opt-out (the original shape proposed here). `with` exists
alongside `let` for now; revisit once it has wider use.

## Base features

* vector/hashmap/set in a library, use in the compiler
* Unicode strings
* Str protocol
* `addr-of` probably needs a reader macro
* `defvar` only accepts integer literals, wat?
* `set!` should take multiple pairs like `let` and/or be polymorphic

## Bounds checking for C str/array

Safe accessors with runtime cost seem like a good idea here, but it would be even better if there are ways to improve safety with no runtime cost.

## import-only

`import-only` takes a library name and a list of symbols, importing only those symbols and the dependencies of the functions/structs/etc... they resolve to. This is intended for very constrained targets like microcontrollers. It's OK if this has limitations like only working for Nucleus (not C libraries) or requiring the source, not just a header.

## errata

(Maybe StrView) fails in JIT modules, !void unsupported, struct-in-Result returns zeroed fields, and single-conformer generic ?-methods need a shim for IR mangling.

 name:ref:(Param T) colon-chain doesn't parse for a defn name/param — fuse-colon-paren mangles it. Use the list form (name (ref (Param T))).

Sigil/rmacro for ref in type signatures, addr-of in code

Symbol mangling for any name LLVM or C might not like

UnaryFn protocol should extend to a lot of things that can be invoked

inc!/dec! predate macros; they should probably become macros over set!
