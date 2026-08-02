# Top-Level Forms

| Name | Description | C Equivalent |
|------|-------------|--------------|
| `defn` | Define a function. **Signature.** The mandatory return type is written as its own operand after the parameter list (`(defn name (params):ret body…)`), matching the anonymous forms `fn`/`vfn`/`mfn`/`cfn`. A parenthesized return type is written space-separated or with the `:(…)` lone-colon fuse — `(defn name (params) (Maybe i32) …)` / `(defn name (params):(Maybe i32) …)`. An optional `noreturn` attribute follows the return type. `defprotocol` method signatures and `declare` use the same grammar. (The legacy return-in-the-name spelling `(defn name:ret (params) …)` was retired in Stage 14 and is now a hard error.) Supports `&rest` for variadic functions: `(defn name (a:t &rest xs:elem) ...)`. The rest parameter receives a `Node*` cons-list head built at the call site (so each call site emits `@make-cell` calls and the program must define a compatible `make-cell`). The element type annotation is documentation only — non-`ptr` args are `inttoptr`'d into `Node.car`. `&rest` functions are not directly C-callable; calling through a function pointer requires manually constructing the rest list. `&rest` must be the second-to-last param. Supports `&optional` for trailing parameters with defaults: `(defn name (a:t &optional (b:t default) ...) ...)`. Each `&optional` param must be a 2-element list `(name:type default-expr)`. Defaults are evaluated at the call site in the caller's scope (Common Lisp semantics), so non-constant defaults like `(next-counter)` produce a fresh value per call. Implicit casts apply to defaults. The compiled function has fixed maximum arity at the LLVM/C ABI level — calling through a function pointer or from C requires supplying every argument including the optional ones. `&optional` cannot be combined with `&rest`. A struct-by-value parameter or return is lowered to the platform C ABI (see [Passing and returning structs by value](structs-unions.md#passing-and-returning-structs-by-value)). **Docstring**: if the first body form is a string literal AND there is at least one more form after it, that string is captured as the function's docstring (visible via `(doc fn)` and `(apropos)`); a function whose body is a single string literal is treated as returning the string, not as having a docstring. The same convention applies to `defmacro`. **Overloadable:** defining `defn` again with the same name but different parameter types adds a method — see [Polymorphism](generics.md#polymorphism-overloaded-defn-multimethods). | function definition |
| `defconst` | Define a compile-time constant `(defconst name value)`, where `value` is an integer literal. **The name behaves exactly like the literal it stands for**: it is typed by its value (`i32`, or `i64` when the value does not fit — `(defconst BIG 5000000000)` is `i64`), it *adapts* to the other operand of a binary operator the way a bare literal does (`(<= ans:ui32 K)` compiles iff `(<= ans:ui32 512)` does, in either operand order), and it is rejected — not silently wrapped — where its value does not fit the slot it flows into. See [Integer literals](types.md#integer-literals) and [Binary operators](types.md#implicit-type-coercion). The name takes **no** type annotation — `(defconst K:i32 2)` is rejected (`defconst: takes no type annotation; write (defconst K 2)`) rather than silently accepted, since the value already determines the type. | `#define` / `enum` constant |
| `defenum` | Define an enumeration `(defenum Name member ...)` — a flat list of member names, each bound to its 0-based ordinal as an `i32` constant. A member is a named integer literal and adapts at a use site exactly as `defconst` does (`(= c:ui32 GREEN)` is as legal as `(= c:ui32 1)`). Like `defconst`, the enum's own name takes no type annotation. | `enum` |
| `defvar` | Define a global variable `(defvar name:type [init])`. The optional init must be a **compile-time constant**: a literal, a name bound by `defconst` / `defenum`, or a constant *expression* over them — see [Global initializers](#global-initializers) for the full grammar, the arithmetic rules, and what is still refused. An integer initializer, literal, named or folded, that does not fit the declared type is a compile-time error rather than a silent truncation. Omitted inits default to zero / `null` / `false`; a global of **aggregate** type (struct, union, or `(array T N)`) with no init is zero-filled (`zeroinitializer`), so e.g. `(defvar g:MyStruct)` and `(defvar g:(array i32 256))` are valid. `set!` works on the result. The symbol is exported with default linkage and is visible to C consumers (`extern T name;`) and other Nucleus modules (`(extern name:type)`). **Storage class specifiers:** file-scope `static` is the private definer `defvar-` (internal linkage); `register` is a no-op (LLVM ignores it); `thread_local` is reserved in the declaration-attribute slot (`:thread-local`) but not yet implemented — it errors with a targeted diagnostic pointing at the threading-stage blocker (`design/stage14/attributes.md` §5). Function-scope `static` locals and `:align`/`:section`/`:weak` are sketched but not implemented (same doc, §6). Function attributes ARE implemented (Stage 14 AVR-5) — but as the separate top-level `fn-attr` directive below, not as a keyword in this decl-attribute slot. C's global `const` is the `:const` declaration attribute (Stage 14 AVR-6): `(defvar :const name:type init)` emits an LLVM `constant` instead of `global`, and is rejected everywhere else the attribute registry applies since only a `defvar` global has an independent storage class to select — see [Const globals](types.md#const-globals). | global variable definition |
| `defstruct` | Define a struct type, or a parametric struct template when the name is a list: `(defstruct (Name T ...) ...)`. Like `defconst`, a **bare** (non-template) name takes no type annotation — `(defstruct S:i32 (f i32))` is rejected (`defstruct: takes no type annotation; write (defstruct S ...)`); a genuine template head such as `(Vector T)` is unaffected. See [Parametric struct templates](structs-unions.md#parametric-struct-templates-defstruct-name-t-). | `struct` |
| `defunion` | Define a tagged sum `(defunion Name (arm field:type ...) ... bare-arm)` or a template `(defunion (Name T ...) ...)`. Like `defconst`, a **bare** (non-template) name takes no type annotation — `(defunion U:i32 (a x:i32) b)` is rejected (`defunion: takes no type annotation; write (defunion U ...)`); a genuine template head is unaffected. See [Unions and tagged sums](structs-unions.md#unions-and-tagged-sums). | tagged `struct {int tag; union {...} payload;}` |
| `defprotocol` | Define a protocol: a named set of required method signatures (types may mention `Self` and extra element parameters). Compile-time only; emits no code. Like `defconst`, a **bare** (non-parametric) name takes no type annotation — `(defprotocol P:i32 ...)` is rejected (`defprotocol: takes no type annotation; write (defprotocol P ...)`); a genuine parametric head such as `(Seq E)` is unaffected. See [Protocols](generics.md#protocols-defprotocol-and-extend) and [Parametric protocols](generics.md#parametric-protocols). | — (concept: interface/trait) |
| `extend` | Assert conformance `(extend Type Protocol)` or parametric conformance `(extend (Name T) (Protocol T))`: checks that each required signature resolves, then records the fact. Code-free. See [Protocols](generics.md#protocols-defprotocol-and-extend) and [Parametric protocols](generics.md#parametric-protocols). | — |
| `import` | **Prefix-qualified import** (the default, deliberate-API form). `(import lib [prefix])` exposes each public symbol of `lib` as `prefix/name`, pointing at the same definition (no new code; a foreign C symbol keeps its bare link name, so `c/printf` calls `@printf`). `lib` resolves `name.nuc` (source) or `name.nuch` (header) from source directory, `lib/`, `-I` paths, `$NUCLEUS_LIB`, or `/usr/local/share/nucleus/lib` (the install-time default used by `make install`); a string path imports a C header (`(import "stdio.h")`, preprocessed with `clang -E`) or an explicit `.nuc`/`.nuch` file by path. The prefix defaults to the lib's last dotted component (`foo.bar.baz` → `baz`); a string-path C header defaults to `c` (`(import "stdio.h" c)` → `c/printf`). The **same library** may be imported under **multiple** prefixes (aliasing); two different libraries **may not share** a prefix (error). Dedup is keyed on `(file, prefix)`. Source imports inline all definitions; header imports emit `declare` (extern) for functions. *(`import` and `import-prefixed` are synonyms.)* | — |
| `import-use` | **Flatten import** — brings **every** symbol of a library or C header into the current namespace under its bare name, including private symbols (the opt-out from the prefixing discipline). Good for the REPL and for libraries; discouraged for deliberate API design. `(import-use name)` / `(import-use "hdr.h")`. The prelude is auto-`import-use`d into every unit. | — |
| `import-prefixed` | Explicit spelling of the prefix-qualified `import` above: `(import-prefixed lib [prefix])`. Identical to `import`. | — |
| `import-only` | Import a concrete list of symbols: `(import-only lib sym1 sym2 ...)`. The listed symbols are brought in under their bare names. *(Currently flattens like `import-use`; the restriction to only the listed symbols is enforced once private/visibility filtering lands.)* | — |
| `unsafe-import-private` | **Retired in Stage 14** — bare `unsafe-import-private` is now a targeted hard error: `'unsafe-import-private' was split in Stage 14: use 'unsafe/import-private'`. | — |
| `unsafe/import-private` | Prefix-qualified import that also reaches a library's private (`defn-`/`defvar-`/etc.) symbols: `(unsafe/import-private lib prefix sym...)`. Discouraged; for breaking encapsulation deliberately. The listed symbols are advisory (not yet filtered) — every private symbol from the library is aliased under the prefix. See [Special Forms](special-forms.md#special-forms). | — |
| `declare` | Declare an external function signature `(declare name (params...) :rettype)`. Used in `.nuch` header files and at the top level. **Parameters carry their types in both spellings.** A parameter may be written *named* — `(declare lseek (fd:i32 off:i64 whence:i32):i64)` — or *unnamed*, as its bare type — `(declare lseek (i32 i64 i32):i64)`; the two produce the same signature, and a list may mix them. In a declaration the name is documentation only (nothing binds it), so an unnamed parameter is a **type operand**: any type spelling works there, including a keyword (`:i64`), a compound (`(Vector i32)`), and a struct name (passed by value under the platform C ABI). A spelling that names no type is a compile-time error — there is no default. **An element carrying a `name:type` annotation is a named parameter**, exactly as in a `defn`, so `(declare f (ptr:FILE):void)` declares a parameter *named* `ptr` of type `FILE` (by value), not a pointer to `FILE` — write `p:ptr:FILE`, or a bare `ptr`, for a pointer parameter. `&rest` / `&optional` are `defn`-only and are rejected here; a C variadic function needs no marker, since call arity is not checked against a declaration and the extra arguments are passed positionally (importing the function's C header is the precise route). See also [Declaration precedence](structs-unions.md#declaration-precedence-an-explicit-declare-wins). | function prototype |
| `extern` | Declare a foreign global variable `(extern name:type)`. The compiler emits `@name = external global T`, leaving storage and initialization to the linker. Works for both C-defined and Nucleus-defined producers; the matching `defvar` may live in another `.o` file. | `extern` declaration |
| `defmacro` | Define a compile-time macro `(defmacro name (params...) body...)`. The name takes **no** type annotation — `(defmacro m:i32 (x) x)` is rejected (`defmacro: takes no type annotation; write (defmacro m ...)`) rather than silently compiling and failing at the call site. Supports `&rest` for variadic macros: `(defmacro name (a b &rest rest) ...)` — `rest` receives a cons list of remaining args. Parameters (and the `&rest` list) are typed `(raw Node)` inside the body, so `(p car)`, `(p cdr)`, chains like `((p cdr) car)`, `(p kind)`, and `(p s)` work directly with no `(as ptr:Node ...)`. The macro can splice a parameter into a quasiquote regardless of the value type the user-supplied expression evaluates to at the call site — see [Macros and pass-through arguments](macros.md#macros-and-pass-through-arguments). | macro |
| `defcast` | Register an implicit conversion `(defcast From To conv-fn)`. `conv-fn` must be a unary function with signature `To (From)` already in scope; the compiler emits a call to it whenever an arg of `From` is supplied where `To` is expected. Pairs already covered by built-in coercion (identity, int↔int, `f32`→`f64`) are rejected at registration. Rules are unidirectional and non-transitive — declare each direction explicitly, and chain through an intermediate type by writing the chain yourself. Exported in `.nuch` headers. | implicit conversion |
| `def-rmacro` | Define a reader macro `(def-rmacro "prefix" symbol)`. When `prefix` appears at the start of a token, the reader wraps the next form: `(symbol form)`. Built-in reader macros: `'` (quote), `` ` `` (quasiquote), `~` (unquote), `~@` (unquote-splice), `@` (deref). | — |
| `exclude-prelude` | Suppress the implicit `(import-use prelude)` for this source file. Must be the first top-level form; takes no arguments. Use when a file should compile against the bare language without the standard macros, `Node` struct, or `(import-use "string.h")` declarations. | — |
| `ns` | Set the current namespace for this source file: `(ns name)`. `name` must be a slash-free symbol. Symbols defined after this form are stored under `namespace/name` qualified keys. A second `ns` in the same file warns at compile time (silent in the REPL). The default namespace is `user`, which stores bare keys — byte-identical to pre-namespace behavior. Conventionally the first form in a file. | — (concept: C++ `namespace` / Clojure `ns`) |
| `set-ir-prefix` | Override the IR-mangling prefix for the current namespace: `(set-ir-prefix "prefix")`. An empty string forces bare IR names regardless of the namespace (C-ABI escape hatch). A non-empty string replaces the namespace name in emitted IR identifiers. Applies to symbols defined after this directive. Typically placed immediately after `ns`. | — |
| `export` | Re-export symbols from this namespace: `(export sym1 sym2 ...)`. Makes the listed symbols visible to importers of this namespace under their unqualified names (the part after the last `/`). Typically used in facade libraries to re-expose imported symbols without the importer needing to know the original source namespace. The symbols must already be in scope (via `import-prefixed` or defined in this file). No new IR is emitted — it adds alias entries to the module's export table. Example: `(export geom/area geom/perimeter)` in a `gfacade` namespace causes `(import-prefixed gfacade g)` to expose `g/area` and `g/perimeter` to the importer. | — (closest C analogue: a header that `extern`-declares symbols from another translation unit) |
| `fn-attr` | Attach one or more LLVM string function attributes to a `defn`: `(fn-attr name "attr" ...)`. `name` is a bare function-name symbol (not a string) matched against the target `defn`'s source name (equal to the emitted `@`-symbol in the default `user` namespace); each remaining argument must be a string literal. Attributes accumulate — several strings in one call, or several `fn-attr` calls naming the same function, all apply — and are stored/emitted verbatim (Nucleus does not validate the string; an unrecognized attribute is an LLVM-level error, not a compiler diagnostic). Emitted as a space-prefixed quoted attribute directly on that function's `define` line (e.g. `define void @tick() "signal" {`), coexisting with `noreturn` when both apply. **The `fn-attr` directive must appear before the `defn` it targets** — there is no forward-reference prescan for the attribute table (the same order-sensitive-directive pattern as `set-ir-prefix`, above, which likewise takes effect only for what follows it in source order). Deliberately generic: the first consumer is AVR interrupt handlers (the `"signal"`/`"interrupt"` attributes make the AVR backend emit the interrupt prologue/epilogue and `reti` instead of `ret`; see the block comment in `lib/avr.nuc` and `examples/avr-isr.nuc`), but any LLVM function-attribute string works the same way. A unit that never calls `fn-attr` is byte-identical to before this directive existed. | — (closest C analogue: `__attribute__((...))` on a function declaration) |
| Private definers: `defn-` `defvar-` `defconst-` `defenum-` `defstruct-` `defunion-` `defmacro-` `defprotocol-` | The `-` suffix marks a definition as private. **In a file with no `(ns …)` the name is private to that file** (see [Private names are file-scoped](#private-names-are-file-scoped) below); in a file that declares a namespace it is private to that namespace. Private symbols are not placed in the module's export table and cannot be imported by other namespaces. For link-emitting forms (`defn-`, `defvar-`), the LLVM symbol also receives internal linkage (`define internal` / `internal global`), preventing link-time name collisions with other translation units — equivalent to C `static`. For compile-time-only forms (`defconst-`, `defenum-`, `defstruct-`, `defunion-`, `defmacro-`, `defprotocol-`), there is no linkage dimension; private means the name is invisible to importers. All other semantics (type checking, overloading, parametric templates, protocol conformance) are identical to the public form. | `static` function / `static` global (for `defn-` / `defvar-`); — for compile-time-only forms |

## Private names are file-scoped

**Two files may each define a private `helper`.** A private definer (`defn-`,
`defvar-`, `defconst-`, `defenum-`) in a file that declares no `(ns …)` names
something visible only inside that file; the two definitions are independent, and
each file's calls reach its own.

```lisp
; a.nuc
(defn- helper ():i32 (return 11))
(defn a-value ():i32 (return (helper)))   ; a.nuc's helper

; b.nuc
(defn- helper ():i32 (return 22))
(defn b-value ():i32 (return (helper)))   ; b.nuc's helper

; main.nuc — imports both; prints "11 22"
(import-use a) (import-use b)
(defn main ():i32 (printf "%d %d\n" (a-value) (b-value)) (return 0))
```

The rule and its edges:

* **A file's private name shadows a public one elsewhere.** If `a.nuc` declares
  `(defn- helper …)` and `c.nuc` declares a public `(defn helper …)`, calls
  inside `a.nuc` reach `a.nuc`'s; calls anywhere else reach `c.nuc`'s. This is
  the same shadowing a namespace-local name gets over an imported one.
* **Public names are still unique across the whole unit.** Two files defining
  the same public name and parameter types is an error, and the diagnostic names
  both files.
* **In a file that declares `(ns …)`, privacy is per *namespace*, not per file** —
  `defn-` there means "private to this namespace", which is a real, chosen scope.
  Two files sharing one `(ns …)` therefore still collide on a private name, and
  the diagnostic says so. Give one file its own namespace, or rename.
* Privacy affects only the *name*. The emitted symbol still exists (with internal
  linkage); it is simply spelled per-file, so nothing outside the file can name
  it and nothing collides at link time.
* A namespace name may not begin with `#` — that shape is reserved for the
  implicit per-file scope this rule is built on.

## Cross-file resolution: reachability, not import order

**A `defn`, a `defvar`, a `defconst` or a `defenum` member in any reachable file
of the compilation unit is usable from any other; import order does not affect
resolution.** A file is *reachable* when some chain of `import` forms leads to it
from the file being compiled. Before any form is emitted, the compiler walks the
whole import graph and registers every reachable file's type names, protocols,
`defn` signatures and **value names**, so a reference resolves against the entire
unit rather than against the part of it processed so far.

*Position within a file does not matter either.* A function body may name a
global, a constant or an enum member declared **later in the same file**, exactly
as it may call a function defined later:

```lisp
(defn read-limit ():i32 (return LIMIT))   ; resolves
(defconst LIMIT 99)
```

Consequences worth knowing:

* **Mutually dependent files need no ordering trick, and no import edge between
  them.** Two files whose functions call each other are spelled by having a
  common parent `import` both — in either order, and with *neither* importing
  the other. An import establishes *reachability*, not visibility: once both
  files are in the unit, each one's functions resolve from the other. This is
  the recommended spelling.

  If one of the pair must also be importable on its own, `(declare f
  (params):ret)` is the spelling — see the `declare` bullet below.
* **Two files may also import each other.** An import cycle is legal: the
  compiler emits each file at most once, at first reach, and skips a re-entry of
  a file whose processing is already in progress. Cycles of any length work, as
  does a file that imports itself. Since signatures and value names are
  registered graph-wide before emission, every function, global, constant and
  enum-member reference inside the cycle resolves.

  **Four things a cycle does not carry**, because they only exist once a file
  has been *emitted*, and a cycle member's body is emitted before the rest of
  the file it back-imports. Each is refused with a located diagnostic naming the
  cycle, never a wrong answer:

  | Across a cycle | Diagnostic |
  |---|---|
  | A `defmacro` the partner defines | `unknown: NAME — defined in a file this unit imports circularly` |
  | A `deferror` id or an `extern` declaration the partner defines | `undefined: NAME — defined in a file this unit imports circularly` |
  | A struct/union **layout** the partner defines — a field access, a struct literal, a by-value parameter/return/argument, or a by-value field of another struct | `<use>: 'S' has no layout at this point` |
  | A `prefix/name` alias over a cycle member | `unknown: p/n — the prefix 'p' has no aliases here` |

  What *does* work across a cycle: calling the partner's functions (the point of
  the feature), reading its globals, constants and enum members, naming its types
  **behind a pointer** (`ptr:S`, `(ref S)`), and `(sizeof S)` / `(alloca S)` —
  those lower to a GEP over the LLVM named type, which is resolved from the
  definition emitted later in the same module.

  If you hit one of these, the fix is the common-parent spelling above, or
  moving the shared macro/error/type into a third file both import.
* **Reordering imports cannot break a build.** Alphabetizing an import list, or
  inserting a new import anywhere, changes nothing about which names resolve.
  This includes `defvar` initializers: they are constants, applied before any
  code runs, so no reordering can change one.
* **`(declare f (params):ret)` is still available** as a local prototype, and
  matching a real `defn` of the same name is not a redefinition — the
  declaration stands down for the definition. It is no longer *needed* for
  cross-file references.
* **Reachability is still required.** A `defn`, global or constant in a file that
  no import chain reaches is not part of the unit and does not resolve — order is
  what stopped mattering, not reachability. The same holds for a struct type
  named in a signature, and now for a type named in a `defvar`'s annotation: its
  defining file must be reachable. When the name *is* defined in a file the
  compiler can see on the import search path, the diagnostic says so and names
  it, so the fix is a one-line import — see
  [Unresolved names](compiler.md#unresolved-names).
* **Two import spellings are outside the graph walk, and stay ordinal.** A file
  imported by *string path* (`(import-use "lib/foo.nuc")`) and a `.nuch` header
  are both left to emission order — for functions and values alike, so there is
  no asymmetry between the two kinds of name. Prefer the symbol spelling
  wherever the file is on the search path; with a `.nuch`, import the header
  before the file that uses it.
* **A name overloaded anywhere in the unit gets the mangled symbol everywhere.**
  Whether a `defn` keeps the plain `@name` LLVM symbol or gets an overload-mangled
  one is decided from the *whole* unit's method set, before any function is
  emitted — so it no longer depends on where in the import order the second
  overload happens to appear. If you link C against a Nucleus function, make sure
  no other reachable file overloads its name (or expose a uniquely named wrapper).
* Everything else about a name — visibility (`defn-`), namespaces, and prefix
  qualification — is unchanged; only *when* a file's signatures and value names
  become visible moved. In particular a **private** value (`defvar-`,
  `defconst-`, `defenum-`) is registered under its own file's scope from the
  start, so a forward reference to one inside its own file resolves to it and
  not to some other file's public name of the same spelling.

## Global initializers

A `defvar` initializer is not an expression the program evaluates — it is baked
into the emitted `@g = global …` line, so it must be a value the compiler can
compute while compiling. Nothing runs before `main`, and a global with no
initializer is zero-filled by the loader.

### What is accepted

**Literals.**

* An **integer** literal, at any int width, signed or unsigned.
* A **float** literal (`f32` / `f64`). An `f32` initializer is rounded to single
  precision at compile time, so `(defvar g:f32 3.14)` is valid and equals C's
  `3.14f`.
* A **string** literal, at a `ptr` or `CStr` destination. Both the plain `"…"`
  and the explicit `c"…"` spelling work for either, since a literal's backing
  storage is NUL-terminated and an unmaterialized literal's value simply *is*
  its `data` pointer.
* `null`, at a **nullable** pointer destination only: `CStr`, an elem-less bare
  `ptr`, or `(raw T)` / `?T`. A *typed non-null* pointer (`ptr:T`, `(ref T)`)
  rejects it with the same diagnostic the identical local binding gets, since a
  non-null slot holding `null` compiles clean and faults on first use.
* `true` / `false`, at `i1` / `bool` only.
* `(char "x")`, at any int type.

**Names.** A name bound by `defconst` or `defenum` stands for the literal it
names and folds in. Ordering does not matter: a constant defined later in the
same file, or in another reachable file, resolves exactly as one defined
earlier (see [Cross-file resolution](#cross-file-resolution-reachability-not-import-order)).

**Constant expressions.** At an **integer** destination the initializer may be
an arbitrary expression over the above:

* arithmetic — `+`, `-` (binary and unary), `*`, `/`, `%`;
* bit operations — `bit-and`, `bit-or`, `bit-xor`, `bit-shl`, `bit-shr`,
  `bit-not`;
* `(sizeof T)`, for any type with a known layout;
* `(as T x)`, subject to the same rule `as` obeys in an expression: a widening
  or same-width reinterpret is fine, a narrowing must be spelled
  `unsafe/cast`.

```lisp
(defconst WIDTH 320)
(defvar g-pitch:i32  (* WIDTH 4))
(defvar g-mask:i32   (bit-or (bit-shl 1 8) 15))
(defvar g-stride:i32 (* (sizeof Pixel) WIDTH))
(defvar g-limit:i64  (as i64 (* WIDTH WIDTH)))
```

**`(as T x)` at a pointer destination**, which is what makes a constant C string
spellable:

```lisp
(defvar g-name:CStr (as CStr "doom"))
```

**`(addr-of g)`, the address of another global.** A global's address is a
link-time constant *and* is provably non-null, so this is the one initializer
that fills a non-null `ptr:T` / `(ref T)` global with no runtime store. The
target may be defined later in the file, or in another file:

```lisp
(defvar g-head:Node)
(defvar g-cursor:ptr:Node (addr-of g-head))
```

**Constant aggregates** — an `(array T …)` literal and a `(S …)` struct
literal. Both nest to any depth, and every element is itself an ordinary
constant initializer, so all the rules above apply one level down.

```lisp
(defstruct Pt x:i32 y:i32)

; A fixed-size table. Missing slots take the element type's zero.
(defvar g-table:(array i32 5) (array i32 10 20 30))
; Designated indices, in any order; unlisted slots are zeroed.
(defvar g-sparse:(array i32 6) (array i32 (0 100) (5 500)))
; A constant struct, positional or designated by field name.
(defvar g-origin:Pt (Pt 3 4))
(defvar g-unit:Pt   (Pt (y 9)))
; They compose: arrays of structs, structs with array fields.
(defvar g-corners:(array Pt 3) (array Pt (Pt 1 2) (2 (Pt 7 8))))
```

An `(array T N)` global with **no** initializer is zero-filled, like any other
aggregate:

```lisp
(defvar g-scratch:(array i32 1024))    ; @g-scratch = global [1024 x i32] zeroinitializer
```

**A pointer global initialized with an array literal** gets an anonymous
constant table and points at it — C's `static const T tbl[] = {…}; T *p = tbl;`
in one declaration. The pointer is the address of a global, so it is provably
non-null and satisfies a `ptr:T` / `(ref T)` annotation with no runtime store:

```lisp
(defvar g-names:ptr:CStr (array CStr (as CStr "red") (as CStr "green")))
;  → @g-names.data = internal global [2 x ptr] [ptr @.str.0, ptr @.str.1]
;    @g-names      = global ptr @g-names.data
```

Note the two readings of `(array T …)`, which are distinguished by **position**
and mean different things: in *type* position `(array i32 4)` is a four-element
array type, while in *value* position it is a one-element array literal holding
the value `4`. `(defvar g:(array i32 4))` and `(defvar g:ptr:i32 (array i32 4))`
are both legal and are not the same thing.

An initializer that does not match its slot is refused with a message naming
what would work: too many initializers, a designated index past the end or given
twice, an element type that disagrees with the declared one, a field the struct
does not have, and a scalar where a compound literal is required.

### Arithmetic rules

Constant folding evaluates in **signed 64-bit**, exactly as an untyped integer
literal does, and the result is then range-checked against the declared type —
so `(defvar g:i32 (* 2000000000 3))` is rejected for the same reason
`(defvar g:i32 6000000000)` is, rather than being truncated. `bit-shr` is an
*arithmetic* shift (`-16 >> 2` is `-4`), and `/` and `%` truncate toward zero
(`-7 / 2` is `-3`, `-7 % 2` is `-1`), matching what the same expression computes
at runtime.

Anything that cannot produce a value is a **compile-time error at the
initializer's line**, never a wrap and never a poisoned constant:

| Situation | Result |
|---|---|
| `+` / `-` / `*` leaves the 64-bit signed range | `constant initializer overflows 64-bit signed integer arithmetic` |
| `(/ x 0)` | `division by zero in constant initializer` |
| `(% x 0)` | `remainder by zero in constant initializer` |
| shift count outside `0..63` | `shift amount N out of range in constant initializer` |
| folded value does not fit the declared type | `constant expression value N does not fit T` |

### What is still refused

* **Anything that has to run** — a function call, an allocation, a value read
  out of another global. `(defvar g:ptr:T (make-thing))` is
  `init must be a compile-time constant`.
* **Float arithmetic.** A float *literal* initializer is fine; `(+ 1.0 2.0)` is
  not folded.
* **Comparisons and `and` / `or`.** They yield `i1` and are not part of the
  folded domain; write the answer.
* **Union initializers.** A `(defvar u:MyUnion)` is zero-filled, but there is no
  constant *union* literal — a union has no unambiguous member to initialize —
  so assign a member at run time.
* **Non-constant aggregate elements.** The rules above apply to each element, so
  an element that has to run is refused exactly as a scalar one is.
* **A type whose layout the current import cycle has not produced yet.**
  `(sizeof S)` answers from the compiler's layout table here rather than from
  LLVM, so across an import cycle it is refused with the same message a by-value
  use gets, instead of silently folding to zero.

## One symbol, one kind

A symbol may name only **one** kind of thing: a special form, a built-in type (`i32`, `ptr`, `double`, …), a struct type, a protocol, a macro, a function, or a value (`defvar`/`defconst`/`defenum` member/`extern`). Defining a name that already names a *different* kind is an error, e.g. `(defn double …)` clashes with the `double` type alias, and `(defstruct i32 …)` clashes with the built-in type. Same-kind reuse is still allowed: overloaded `defn` (multimethods) and REPL/`defstruct` redefinition. This keeps name resolution unambiguous across the language's namespaces.
