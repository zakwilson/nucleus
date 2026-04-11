# Nucleus syntax

Nucleus is based on Lisp syntax. Code is lists of symbols, numbers, strings, and other lists.

## Syntax

It uses colons for type declarations, for example:

    (defn square:int (x:int)
      (return (* x x)))

## Conventions

Lisp style conventions are used. Names should be kebab-case.
