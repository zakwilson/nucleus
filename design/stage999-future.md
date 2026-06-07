# Future plans

## Lispiness

Nucleus is a replacement for C, but it should bring in as much Lisp goodness as it can without compromising C interop or adding runtime overhead.

### Lambda

Obviously

### Map/reduce/filter

Ideally polymorphic

### Polymorphism in general

With static typing and compile-time dispatch, this should have no runtime cost. I'm imagining a protocol/interface system in addition to concrete types

### Redefinition

The ability to redefine vars and fns in the REPL would be helpful. We don't have dynamic scope and probably shouldn't add it, so that implies recompiling everything depending on the var in question. The time to do that is acceptable, but the implementation complexity may not be.

### Closures

Lexical closures are a huge win for abstraction. Representing them in C may be tricky, but maybe there's a workaround or a way to give C a limited interface. Lifecycle could also be tricky.


### Gensym reader macro

Probably `#`, semantics like Clojure but not the postfix syntax

## Data structures

### Vectors and hashes as part of the language

Clojure uses these well. Not included by default at runtime of course, but good general-purpose implementations people would want to import if they don't need something purpose-built.

## REPL documentation

It should be possible to add a docstring to anything that can be defined. .nuch headers should include them. They should be added to C headers as comments.

There should be `docstring` and `signature` functions for tool use, and probably a `doc` function for human use at the REPL that gets the docstring, signature, and anything else that might be interesting about a symbol for the developer.

## Cleanup

`set!` should take multiple pairs like `let`.

## Memory management

The `with` form (added in stage6) is `let` plus auto-free for any binding
whose init expression is a libc allocator (`malloc`/`calloc`/`realloc`/`strdup`,
including through `cast`). Cleanups fire on fall-through and on early `return`
inside the body. Disarming a single binding is done by storing `null` to it,
since `free(NULL)` is a no-op.

Open question: whether to flip the default so plain `let` itself auto-frees,
with `let*` as the opt-out (the original shape proposed here). `with` exists
alongside `let` for now; revisit once it has wider use.
<<<<<<< Updated upstream
=======

## Safe constructs

Nucleus isn't trying to be Rust, but it should provide the option of safe constructs where it's practical to do so, and move things that should be avoided when possible to an unsafe/ namespace.

The `with` special form is a target for improvement. It should enforce a lexical *lifetime* rather than just preventing memory leaks. Attempting to return variables bound to pointers using `with` should be a compile-time error. That includes binding a second variable with a nested `let`. Returning the dereferenced value is permissible.
>>>>>>> Stashed changes
