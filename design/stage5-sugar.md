# Syntactic sugar and reader macros

## Reader macros

### Designer:

The hardcoded `'` / `` ` `` / `~` / `~@` should be converted to entries in a user-extensible reader macro table with `def-rchar` being analogous to Common Lisp `set-macro-character`.

### Robot:

## Syntactic sugar

### Designer:

Types have a non-sexp syntax that's currently treated as part of a symbol's name. `(defn main:int () ...)` offers a familiar syntax for many developers, but it means macros don't have a clean way to interact with types. I'm imagining a sugar/desugar mechanism something like this (perhaps with different quoting):

    (desugar-var 'main:int) --> '(var-type 'main 'int)
    
    (sugar-var '(var-type 'main 'int)) --> 'main:int


The Right Thing is probably making the sugar/desugar mechanism extensible. Users could register desugaring functions and the compiler would try all of them upon encountering unfamiliar syntax before giving up with an error. How complex would the implementation be? What would the compile-time performance cost look like?

Worse may be better here: types are a special case and users have to start any special syntax of their own with a reader macro.

A middle way: types get a reader macro like `(defn $main:int () ...)`. Right now, I think it's ugly, but accepting something ugly to simplify implementation fits the worse is better philosophy.

### Robot:
