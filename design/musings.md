# Musings

These thoughts about the language are not ready for implementation. They may be inconsistent and may not represent the eventual direction of the language.

## Types and macros

The colon syntax (defn main:int () ...) for types is easy to read and familiar to many developers. It's not an s-expression though and could be hard to manipulate in macros. One solution is an s-expression equivalent and a compile-time form to sugar and desugar it.

    (desugar-var 'main:int) -> '(var-type 'main 'int)
    
    (sugar-var '(var-type 'main 'int)) -> 'main:int

This quoting may be off.

The sexp should probably be the canonical form, but if we have to wait until late in compilation to use the sugared form, the compiler source will be ugly.
