# Future plans

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

## REPL documentation

It should be possible to add a docstring to anything that can be defined. .nuch headers should include them. They should be added to C headers as comments.

There should be `docstring` and `signature` functions for tool use, and probably a `doc` function for human use at the REPL that gets the docstring, signature, and anything else that might be interesting about a symbol for the developer.

## set!

`set!` should take multiple pairs like `let`.

## Base features

* vector/hashmap/set in a library, use in the compiler
* Unicode strings
* Str protocol

## Bounds checking for C str/array

Safe accessors with runtime cost seem like a good idea here, but it would be even better if there are ways to improve safety with no runtime cost.
