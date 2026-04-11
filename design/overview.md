Nucleus is a replacement for C using Lisp style syntax and macros with LLVM as its target. It is a low level systems programming language meant to manipulate memory directly, and when required, unsafely.

It uses colons for type declarations, for example:

    (defn square:int (x:int)
      (return (* x x)))

