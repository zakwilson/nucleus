# Future plans

## Lispiness

Nucleus is a replacement for C, but it should bring in as much Lisp goodness as it can without compromising C interop or adding runtime overhead.

### Variadic functions

Arithmetic functions in Lisp usually take arbitrarily many arguments. That would be nice. Optional or rest parameters for user-defined functions would also be nice.

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

### Macro expansion

`macroexpand` and `macroexapnd1` (or maybe an optional depth arg) need to be available in the REPL

### Gensym reader macro

Probably `#`, semantics like Clojure but not the postfix syntax

### Read/Print

Most things should be printable at the REPL and the printed representation should be readable. Right now even a quoted list just prints a bare address.

### Expressions

In Lisp, everything is an expression that returns a value. C has statements which do not.

Expressions are better if they don't add overhead. If they do, perhaps the compiler can optimize it away if the return value isn't used.

The last expression in a form should usually be the return value of the enclosing form if there's no explicit `return`.

## Data structures

### Vectors and hashes as part of the language

Clojure uses these well. Not included by default at runtime of course, but good general-purpose implementations people would want to import if they don't need something purpose-built.

### Cleanup

`set!` should take multiple pairs like `let`.

