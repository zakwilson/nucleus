## Libraries

The Nucleus compiler already supports loading C libraries, but lacks libraries of its own. They are added in this phase.

### Native libraries

Designer
========
Nucleus must be able to use libraries written in Nucleus. `import` should be usable with Nucleus code and should be able to import everything defined there including macros.

There should be a way to use a library *only* at compile-time. It would be simple if that could just be `(compile-time (import foo))`. It would be *great* if there was a good error message for code that uses something imported only for compile-time at run-time.

The ideal implementation would have a more sophisticated module system with a way to mark symbols private and optionally aliased imports:

`(import foo.bar :as bar)
`(bar/baz)

or without adding keyword arguments

`(import-as foo.bar bar)
`(bar/baz)

It must be possible to import Nucleus libraries, including their macros without their source code. That ability must come without a runtime cost or bloating binaries produced by the Nucleus compiler. That implies a dedicated .nuch header file format for Nucleus. It should use an S-expression syntax.

Robot
=====


### C compatibility

Designer
========
Nucleus libraries must be consumable from C. A tool is required to produce C-compatible .h headers from Nucleus code or .nuch headers.

C obviously can't use Nucleus macros, so they should not be exposed in .h headers.

Robot
=====
