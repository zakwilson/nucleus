nucleus
=======

Nucleus is a replacement for C

That's probably a silly thing to make, yet here we are. Here it is. Here **you** are reading about it for some reason. C is the bedrock on which all modern computing is built. How could it possibly need a replacement? It doesn't, but if we only made things we need, we'd still be living in caves.

People called C a high-level language when it was young because it abstracted away the differences between CPU instruction sets. Now, people usually call C a low-level language because it manipulates memory directly and has a limited capacity for abstraction.

Nucleus aims to add more capacity for abstraction with zero runtime overhead by way of compile-time manipulation of source code. Someone is surely about to object that the C preprocessor can already do that. It can, but it's limited to manipulating code as a string. Nucleus can manipulate code as a parse tree, like Lisp can.

That means it looks like Lisp. Some people won't like that, but it's my language and I like that.
