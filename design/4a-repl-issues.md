# REPL issues

#### Designer:

The following unexpected behaviors occur with the first-pass REPL:

##### Observed:

nuc> (compile-time (+ 2 2))
<repl>:1: compile-time: IR parse error: <compile-time>:4:1: error: expected top-level entity
��i%�U0Ddefine void @__compile_time_main_0() {

(process exited)

##### Expected:

4

##### Observed:

nuc> (defn foo:int () (return 0))
  defined
nuc> (defn foo:int () (return 1))
  warning: redefining 'foo'
<repl>:1: compile-time: IR parse error: <compile-time>:7:12: error: invalid redefinition of function 'foo'
define i32 @foo() {
           ^
(process exited)

##### Expected:

`foo` redefined with lexically subsequent calls returning 1. I would also accept a refusal to redefine an already-defined function at this stage, but the process exiting is bad.

##### Observed:

nuc> (import node)
lib/node.nuc:7: error: unknown: arena-alloc

nuc> (import macros)
lib/macros.nuc:47: error: unknown type: Node

##### Expected:

The libraries are compiled and their functions and macros are available in the REPL.

##### Observed:

nuc> (import mathlib)
nuc> (cube 4)
lib/macros.nuc:1: compile-time: IR parse error: <compile-time>:17:18: error: use of undefined value '@cube'
  %t0 = call i32 @cube(i32 4)
                 ^
(process exited)

##### Expected:

64

##### Observed:

nuc> (defvar foo:*i64 666)
<repl>:1: compile-time: IR parse error: <compile-time>:5:19: error: integer constant must have integer type
@foo = global ptr 666, align 8
                  ^

(process exited)

##### Expected:

Type error without exit

##### Observed:

nuc> (defvar foo:ptr (malloc (cast i64 32)))
<repl>:1: error: defvar: init must be integer literal

nuc> (malloc 32)
<repl>:1: error: unknown: malloc

##### Expected:

Var foo defined, malloc prints a number representing a memory address

##### Observed:

Nucleus REPL (type Ctrl-D to exit)
nuc> (defvar qux:int 32)
<repl>:1: compile-time: IR parse error: <compile-time>:5:1: error: redefinition of global '@qux'
@qux = global i32 32, align 4
^

(process exited)

##### Expected:

"defined", or maybe 32. Not an error, definitely not a crash.
