# EDN

`lib/edn.nuc` — [EDN](https://github.com/edn-format/edn) data, read and written
through the Nucleus reader.

An EDN value is the `Node` the reader builds in [EDN mode](reading.md#edn-mode).
This library classifies it, checks the EDN rules the reader leaves alone,
converts it to Nucleus scalars, and writes EDN back. Nothing is copied:
collections are the reader's lists, and strings, symbols and keywords are
interned for the life of the process, so a `StrView` taken from a value never
dangles. That suits configuration-sized input; nothing is ever freed.

The library declares `(ns edn)`. `(import-use edn)` names everything bare;
`(import edn e)` names it `e/edn-parse`, `e/derive-edn` and so on.

```lisp
(import-use read)
(import-use edn)

(match (edn-parse "{:host \"localhost\", :port 8080}")
  ((ok cfg)
    (let (port:i32 0)
      (try (edn-read &port (edn-get cfg "port")))
      (println "port " port)))
  ((err e) (eprintln "line " (e 'line) ": " (e 'msg))))
```

See `examples/edn-read.nuc` for a worked example, and
[Structs and collections](#structs-and-collections) for reading straight into
typed values (`examples/edn-struct.nuc`).

## Reading

| Form | Meaning |
| --- | --- |
| `(edn-parse src)` | `ReadResult` — exactly one value. No value is `edn-no-value`; a second is `edn-trailing`. |
| `(edn-parse-all src)` | `ReadResult` — every value in `src`, as a list. |

Both report failures as a `ReadError` (`code line msg note`), the reader's own
error type — see [Reading s-expressions](reading.md#readresult-and-readerror).
On top of the reader's errors they refuse what EDN forbids and the reader
accepts:

| Code | When |
| --- | --- |
| `edn-bad-symbol` | a symbol, keyword or tag that is not legal EDN (`'q`, `1abc`, `a/b/c`, `::k`) |
| `edn-dup-key` | a map with the same key twice |
| `edn-dup-elem` | a set with the same element twice |

## Kinds

`(edn-kind v)` answers one of the `EdnKind` constants; `(edn-kind-name k)` is
its English name ("an integer", "a map", …), for messages.

| Kind | What it is |
| --- | --- |
| `EDN-NIL` | `nil` — and a null node, which is how a missing value reads |
| `EDN-BOOL` | `true`, `false` |
| `EDN-INT` | an integer, signed 64-bit; `7N` reads as `7` |
| `EDN-FLOAT` | a float; `1.5M` keeps its `M` |
| `EDN-STR`, `EDN-CHAR` | a string, a character |
| `EDN-SYM`, `EDN-KEYWORD` | a symbol, a keyword |
| `EDN-LIST`, `EDN-VECTOR`, `EDN-MAP`, `EDN-SET` | `(…)`, `[…]`, `{…}`, `#{…}` |
| `EDN-TAGGED` | `#tag value` |

A vector is not a list here, though the reader spells both as a list `Node`:
the bracket is the cell's `LitMark` ([reading.md](reading.md#what-it-reads)).

## Accessors

Each scalar accessor returns `!T`, failing with `edn-type` on the wrong kind.

| Form | Result |
| --- | --- |
| `(edn-bool v)` | `!bool` |
| `(edn-int v)` | `!i64` |
| `(edn-float v)` | `!f64` — an integer is accepted; an unparsable `M` decimal is `edn-range` |
| `(edn-str v)` | `!StrView` — the string's text |
| `(edn-char v)` | `!Char` |
| `(edn-symbol v)` | `!StrView` — the symbol's name |
| `(edn-keyword v)` | `!Keyword` |
| `(edn-tag v)` | `!StrView` — a tagged value's tag, without `#` |
| `(edn-tagged-value v)` | `?&Node` — the value a tag applies to, or null |

Collections:

| Form | Result |
| --- | --- |
| `(edn-count v)` | elements of a list, vector or set; entries of a map; 0 otherwise |
| `(edn-nth v i)` | element `i` of a list, vector or set, or null |
| `(edn-elems v)` | the elements as a plain list `Node`, to walk with `(doseq (x xs NodeIter) …)`; null for a non-collection |
| `(edn-key m i)` / `(edn-val m i)` | the key and value of map entry `i` |
| `(edn-get m "name")` | the value under keyword `:name`, or null |
| `(edn-lookup m key)` | the value under any key node, compared with `edn-eq`, or null |
| `(edn-eq a b)` | EDN equality: by kind and value; maps and sets compare in written order |

## Converting to Nucleus values

`(edn-read dst v)` stores value `v` into `*dst`, returning a `ReadResult`
whose `ok` carries `v`. One overload per destination type:

| EDN value | Destination | Rule |
| --- | --- | --- |
| integer | `&i8` … `&i64`, `&ui8` … `&ui64` | range-checked: out of range is `edn-range` |
| integer, float | `&f64`, `&f32` | an `f32` refuses a value beyond its range; lost precision is not an error |
| string | `&StrView` | borrows the interned text |
| string | `&String` | copies into a new `String`; `dst` is uninitialized storage (see [Ownership](#ownership)) |
| keyword | `&Keyword` | |
| character | `&Char` | |
| `true` / `false` | `&bool` | |

Anything else is `edn-type` (`expected an integer, got a string`), including
`nil` and a missing map key. The error's `line` is the value's; a symbol and a
missing value carry none, so theirs is 0.

## Writing

| Form | Meaning |
| --- | --- |
| `(edn-write out v)` | Append value `v` (a `Node`) to `out` as single-line EDN. |
| `(edn-text v)` | That text as a fresh `String` (drop it). |
| `(edn-write out x)` | Append a Nucleus scalar — any integer width, `f32`, `f64`, `bool`, `Char`, `StrView`, `&String`, `Keyword`. Returns `!void`. |

Written text reads back as an `edn-eq` value. Floats always carry a `.` or an
exponent (`2.0`, not `2`), so they read back as floats. Characters are written
`\a`, `\newline`, `\return`, `\space`, `\tab`, or `\uXXXX`; a character beyond
`￿` has no EDN spelling and is written `\u{…}`, which this reader accepts
and other EDN readers do not. EDN cannot spell a `ui64` above the `i64` range
or a non-finite float: writing one is `edn-range`.

## Structs and collections

Every scalar above conforms to the `EdnCodec` protocol, and so do collections
of conforming types and any struct given a derived codec. `edn-read` and
`edn-write` take all of them; the scalar overloads still win for scalars.

```lisp
(defstruct Endpoint (host String) port:ui16)
(defstruct Service (name String) (at Endpoint) (replicas (Vector Endpoint)))
(derive-edn Endpoint Service)

(let (svc:&Service (alloca Service))
  (try (edn-read svc n))          ; n: #user/Service {:name "search" :at … :replicas […]}
  …
  (edn-release svc))
```

### `derive-edn`

`(derive-edn T …)` gives each named struct `T` an `EdnCodec` conformance. It is
a top-level macro, so its call has to come before any use of the codecs. Its
expansion's names [resolve in `lib/edn`](macros.md#a-templates-names-mean-the-macro-files-names),
so the calling file only has to reach `derive-edn` itself, through
`(import-use edn)` or `(import edn e)` and `(e/derive-edn T)`. A caller's own
`edn-put`, or a local with the same name, does not capture the derived code.

- **Written as a tagged map:** `#ns/T {:field value …}`, keys in declaration
  order. The tag is `T`'s qualified name: `#geom/Point` for a struct defined
  under `(ns geom)`, `#user/Point` for one in a file with no `(ns …)`.
- **Read strictly, in this order:**
  1. The value must carry exactly that tag: otherwise `edn-wrong-tag`
     (`expected #geom/Point, got #geom/Pt`, or `…, got a map` when untagged).
  2. The tagged value must be a map: otherwise `edn-type`.
  3. Every key must be a keyword naming a field: otherwise `edn-unknown-key`.
  4. Every field must have a key: otherwise `edn-missing-key`.
  5. Each field reads through its own codec.
- **Errors name the path** to the value that failed, outermost key first, at
  that value's line: `:replicas :port: 70000 is out of range for ui16`.
- **Fields** may be any type with a codec: scalars, `String`, collections,
  other derived structs. A field of an anonymous struct type
  (`(struct lo:f64 hi:f64)`) is written and read inline as
  `#nucleus/struct {:lo … :hi …}`.
- **Refused:** a pointer field, at the `derive-edn` call
  (`derive-edn: field 'next' is a pointer, which EDN cannot spell`). A field
  whose type has no codec fails where the derived code is compiled, with no
  matching `edn-decode`. Template structs, unions and bit-fields are not
  supported.

**Codecs can live in a separate library.** Nothing is derived unless asked, so
a library's types carry no EDN code. A companion library can derive codecs for
them, and only programs that import it pay for them:

```lisp
(ns geometry-edn)
(import-use geometry)
(import-use edn)
(derive-edn Point Rect)
```

A struct field whose type is another library's struct needs that type's
companion imported too.

### Collections

| EDN | Destination | Rule |
| --- | --- | --- |
| `[…]` | `(Vector T)` | A list `(…)` is `edn-type`. Written in order. |
| `#{…}` | `(HashSet T)` | `T` must be a key type. |
| `{…}` | `(HashMap K V)` | Untagged only. `K` must be a key type. A repeated key is `edn-dup-key`. |

The **key types** are `Keyword`, `StrView`, `i32` and `i64`: hashable, and
owning nothing. `HashMap` and `HashSet` never drop their keys, so a `String`
key would leak; any other key type has no codec, and its use is a compile-time
error. Sets and maps are written in hash order, so compare a round trip by
value, not by text.

### Ownership

The destination of `edn-read` is **uninitialized storage**, for every type:

- on `ok`, it owns everything the read built;
- on `err`, it owns nothing: a read that fails part-way releases what it built.

`(edn-release v)` frees a successfully read value deeply: a `Vector` of
`String`s releases each string and then the vector. Collections do not drop
their elements themselves, so use `edn-release`, not `drop`, on a value
`edn-read` built.

### The protocol

```lisp
(defprotocol EdnCodec
  (edn-decode  (dst:&Self n:?&Node):ReadResult)
  (edn-encode  (out:&String v:&Self):!void)
  (edn-release (v:&Self):void))
```

To give a type a hand-written codec, define the three methods and
`(extend T EdnCodec)`. `edn-decode` must follow the ownership rule above.
`derive-edn` builds on two macro-time primitives, `struct-fields` and
`type-name` ([macros.md](macros.md#struct-fields-and-type-name--a-structs-shape-at-expansion-time)),
which another format's library can derive from the same way.

## Not yet

- No built-in readers for `#inst` or `#uuid`: they are ordinary tagged values.
- No codecs for unions, enums, template structs, nullable fields, or default
  values; no float, composite or `String` keys.
- No pretty-printing, and no bignum or decimal type behind `N`/`M`.
- Strings are interned; a non-interning reader for large inputs is deferred.
