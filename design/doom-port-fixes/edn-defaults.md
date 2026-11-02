# derive-edn: absent keys (ISSUE-045)

Ruling: add both a per-field default and a whole-struct "absent keys keep the
destination's value" mode.

## Spelling

```lisp
(derive-edn (Opt :edn-default (volume 8 iwad (str "doom1.wad")))
            (Cfg :edn-keep-absent))
```

The options go on the `derive-edn` call, not on the `defstruct` fields. A struct
carries no EDN code unless something derives it, and a companion library can
derive codecs for another library's types (`docs/edn.md`). A field attribute
would have put EDN knowledge in the type's own definition and needed
`struct-fields` to carry it. A `(T option …)` list is unambiguous because
`derive-edn` already refuses template structs, so a list in that position can't
be a type.

## Semantics

- **`:edn-default`**: the value is a Nucleus expression of the field's type,
  evaluated at read time in the caller's file. It isn't EDN text. Its value
  becomes the field's owned value, so `edn-release` and the partial-failure undo
  release it like a read value. A field with a default is dropped from the
  required list `edn-struct-keys` checks. Unknown keys stay refused.
- **`:edn-keep-absent`**: no field is required. A present key reads over the
  field. The destination must hold a valid value beforehand; that is the one
  exception to "the destination is uninitialized storage".
  - It is transactional. The decoder snapshots `*dst` shallowly, and a gensym
    flag per field records which fields were replaced.
  - When a read fails, the decoder releases the replaced fields, restores the
    snapshot and returns the error.
  - When every read succeeds, the decoder releases the snapshot's copies of the
    replaced fields.
  - Releasing as each field reads would leave a dangling value if a later field
    failed and the snapshot came back.
- The two options together are refused. Defaults mean nothing when absent keys
  keep the old value.

The anonymous-struct codecs a field gets are always strict; they take `()` as
their options.
