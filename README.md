nucleus
=======

Nucleus is a new systems programming language. I initially conceived of it as "a replacement for C" adding syntactic abstraction with Lisp-style structural macros, but it has grown beyond that concept. It still aims to be a drop-in replacement for C with full ABI compatibility and no mandatory runtime overhead, but it adds modern capabilities:

* Guaranteed non-null reference types
* Maybe/match semantics for nullables
* Polymorphic functions dispatched on argument types
* Protocols for constraining polymorphic matches
* Optional lexically-enforced lifetimes to prevent both memory leaks and use-after-free
* Lisp-style macros

While it already has most of the capabilities required for serious use like hosting its own compiler, using it for anything important is risky at this stage. Breaking changes are likely to happen without warning, and it's probably buggy.
