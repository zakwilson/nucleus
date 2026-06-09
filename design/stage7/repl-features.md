# REPL features

#### Designer

The REPL needs functions for documentation, introspection, and connected editor interaction modes. They can be added as a library that the REPL adds to its prelude by default, or when necessary for technical reasons, to the REPL source itself.

It should be possible to add a docstring to anything that can be defined. .nuch headers should include them. They should be added to C headers as comments.

There should be `docstring` and `signature` functions for tool use, and probably a `doc` function for human use at the REPL that gets the docstring, signature, and anything else that might be interesting about a symbol for the developer.

Other useful functions:

* `dir` - list symbols defined in a namespace
* `apropos`- search symbols and docstrings, probably just a substring match for now
* `source` - print the definition of a symbol, if available

#### Robot

A few more candidates that fit the same shape — small, side-effect-free queries over what the REPL already knows — and would be useful for both human use and editor/agent integration:

* `defined?` - predicate: is this symbol bound? Cheaper than `doc` when the caller just needs to branch.
* `kind-of` - what *sort* of binding is this? (`fn`, `macro`, `rmacro`, `var`, `const`, `enum`, `struct`, `cast`). Lets tools render results without parsing `doc` output.
* `type-of` - the static type of a symbol or expression. For functions, the full signature; for vars/consts, the declared type. Distinct from `signature` in that it accepts arbitrary expressions, not just bound names.
* `expansion-of` - convenience wrapper over `macroexpand-all` that takes an unquoted form (`(expansion-of (when c b))`), since at the REPL the quoting boilerplate is the main friction point.
* `imports` - list currently imported libraries / included C headers. Pairs naturally with `dir`: `dir` answers "what's in this namespace?", `imports` answers "what namespaces are loaded?".
* `casts` - list registered `defcast` rules visible at the current point. Implicit conversions are otherwise invisible at the REPL and surprise readers of macro-heavy code.
* `reset!` / `forget` - drop a REPL-local definition (function, var, macro). Useful when iterating on a signature change, since today the docs note you have to restart the session.
* `time` - evaluate a form and print elapsed wall time. Standard REPL affordance; cheap to add on top of the JIT path.
* `trace` / `untrace` - toggle entry/exit logging for a named function via the existing thunk indirection (each call already routes through `@<name>` loading from `@<name>.tgt`, so a trace wrapper can be swapped in without recompiling callers).
* `last-error` - return the most recent recovered REPL error as a structured value. With `--repl-format=json` this is already on stderr; exposing it in-process lets agents react without parsing a side channel.
* `complete` - given a prefix string, return matching symbol names. Editor completion needs this and it's a strict subset of `apropos`.
* `locate` - return the source file and line of a symbol's definition, if available. Powers "go to definition" in editor modes and is a natural companion to `source`.

