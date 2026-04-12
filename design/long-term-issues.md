# Long-term issues

These are potential problems that must be addressed eventually, but not during the early stages of development.

## Compile-time memory leaks

If the compile-time interpreter executes Nucleus code that manipulates cons cells, those cons cells need to exist in the compiler's address space at compile time. Either the interpreter shares its heap with the running compiler (easy, but means compile-time allocations leak into the compiler's memory)

