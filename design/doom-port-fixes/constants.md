# Constants (ISSUE-016, 017, 024)

## Aggregate `defconst` as a `defvar` initializer (016)

`emit-defconst` records an aggregate constant's folded initializer on its
symbol (`Sym.const-init`). `const-aggregate-init` hands it to a `defvar`
initializer that names the constant, so the global gets constant storage.

## Constant operator trees (017)

An operator tree whose leaves are all literals or literal `defconst`s
(`literal-operator-tree?`) folds first. It then adapts to its slot as a single
literal would: `(* 2 FRACUNIT)` in an `i16` slot is a literal that fits, not
an `i32` value. `node-type` uses `fold-literal-operand` too, so typing and
emission agree (the `node-type`↔`emit-node` lockstep).

## A computed `defconst` referenced before its form (024)

- **Prescan:** it records every computed `defconst` that the literal prescan
  can't fold, as a `PendingConst`: form, namespace, source path, imports,
  privacy and line. They are kept in `g-pending-consts` (key to index) and
  `g-pending-list`.
- **First reference:** when a global lookup misses, `globals-lookup-ref` asks
  `fold-pending-ref`. That resolves the spelling the way the lookup would
  (qualified, own namespace, flattened imports, bare). If it names a pending
  constant, `fold-pending-const` emits the form as its own file would:
  - It switches `g-source-path`, `g-current-ns`, `g-file-imports`,
    `g-defining-private` and `g-form-line`.
  - It calls `emit-defconst` and then retries the lookup.
  That is what lets a constant defined in one file of an import cycle be used
  in the other.
- **Each form is emitted once.** `state` is 0 (pending), 1 (being emitted) or 2
  (done).
  - `emit-defconst` asks `pending-const-done?`, matching the entry by path and
    line, and skips a form whose state is 2.
  - Otherwise `pending-const-done?` claims the entry by setting state 1. A
    lookup made while the form is being emitted then can't fold it a second
    time; that happened for template constants, and `@NAME` came out twice.
