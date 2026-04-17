# The Read Eval Print Loop

### Designer:

Lisp developers traditionally develop with a long-running process connected to their editor providing information editors for other languages get through static analysis. LLM tools can interact similarly, iteratively testing improvements to a program in a tight loop without having to recompile the world and rebuild state from scratch.

Nucleus needs a REPL. That should be easy now that it has a JIT compiler. 
