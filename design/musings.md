# Musings

These thoughts about the language are not ready for implementation. They may be inconsistent and may not represent the eventual direction of the language.

## Types and macros

The colon syntax (defn main:int () ...) for types is easy to read and familiar to many developers. It's not an s-expression though and could be hard to manipulate in macros. One solution is an s-expression equivalent and a compile-time form to sugar and desugar it.

    (desugar-var 'main:int) -> '(var-type 'main 'int)
    
    (sugar-var '(var-type 'main 'int)) -> 'main:int

This quoting may be off.

The sexp should probably be the canonical form, but if we have to wait until late in compilation to use the sugared form, the compiler source will be ugly.

## Compile-time dispatch

Since we have static types here, the compiler can decide at compile time what to do with something in the callable position. Struct member access is an obvious candidate:

  (foo bar)
  
instead of

  (. foo bar)
  
But what about making set! polymorphic?

  (set! (foo bar) 42)
  
instead of

  (.set! foo bar 42)

set! should probably be a macro rather than a special form. Special forms should be kept to a minimum.

## C implemantion removed

Upon removal, here was the state of the C implementation of the compiler:

$ tokei src/nucleusc.c
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Language              Files        Lines         Code     Comments       Blanks
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 C                         1         2490         2428           24           38
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Total                     1         2490         2428           24           38
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

The Nucleus version is already shorter, but that's probably because Nucleus formatting often involves more tokens on a line

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Language              Files        Lines         Code     Comments       Blanks
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Common Lisp               1         2667         2283          172          212
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Total                     1         2667         2283          172          212
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Macro definitions added some code to the compiler

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Language              Files        Lines         Code     Comments       Blanks
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Common Lisp               1         2737         2306          209          222
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Total                     1         2737         2306          209          222
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

then it started to shrink.
