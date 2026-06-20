# Modules and namespaces

Nucleus currently has two import forms, `import`, and `include`, both of which make all of a library's symbols available in the current file. This invites name collisions and makes all symbols public, limiting API design.

## Namespaces

The `ns` form sets the current namespace. A file or REPL session that does not set a namespace gets the default namespace 'user.

Calling import forms on symbols attempts to resolve a path. 'foo.bar.baz could describe "foo/bar/baz.nuc", "foo/bar/baz.h", etc... similar to the current import resolution. Using a string argument resolves the filename by path relative to the library search path.

## Public and private

Global symbols are default public. `defn-`, `defvar-`, etc... create private symbols.

### Import

This phase adds new import forms to control name collisions.

`import` takes an additional optional symbol parameter used as a prefix for symbols from the import. The sole parameter is used as the prefix if no optional prefix is specified. If library foo exports symbol bar, then (import 'foo 'baz) makes it available as `baz/bar` in the current namespace. This makes **all** current invocations invalid, forcing an intentional choice about which kind of import to use.

`import-use` is the old import form, making all symbols available. Discouraged in production code. Good for REPL and libraries.

`unsafe-import-private` takes a namespace, prefix, and `&rest` private symbols. Obviously discouraged in normal situations. Alternately, this can go in the "unsafe" *library* and be `unsafe/import-private`.

## Compiler refactor

Most of the compiler is in a single file that's about ~14K lines long. That's a lot.

