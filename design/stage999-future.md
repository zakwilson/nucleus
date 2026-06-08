# Future plans

## Lispiness

Nucleus is a replacement for C, but it should bring in as much Lisp goodness as it can without compromising C interop or adding runtime overhead.

### Lambda

Obviously

### Map/reduce/filter

Ideally polymorphic

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

## Safe constructs

Nucleus isn't trying to be Rust, but it should provide the option of safe constructs where it's practical to do so, and move things that should be avoided when possible to an unsafe/ namespace.

The `with` special form is a target for improvement. It should enforce a lexical *lifetime* rather than just preventing memory leaks. Attempting to return variables bound to pointers using `with` should be a compile-time error. That includes binding a second variable with a nested `let`. Returning the dereferenced value is permissible.

## Nullability

It would be **great** if most types and pointers could be non-nullable with a `Maybe` or `Option` type to provide nullability where it's desired. Even better would be safe pointers by default which cannot point to anything but a valid instance of the declared type, with raw pointers relegated to an `unsafe` namespace.

## Base features

* vector/hashmap/set in a library, use in the compiler
* case/switch for matching a value
* Unicode strings
* Str protocol

## Error attribution

A recent failed compile reported a malformed `cond` but not its location. The compiler should try to track the location of compile errors wherever practical.
