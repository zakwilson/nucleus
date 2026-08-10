# Top-Level Forms

| Name | Description | C Equivalent |
|------|-------------|--------------|
| `defn` | Define a function. **Signature.** The mandatory return type is written as its own operand after the parameter list (`(defn name (params):ret body…)`), matching the anonymous forms `fn`/`vfn`/`mfn`/`cfn`. A parenthesized return type is written space-separated or with the `:(…)` lone-colon fuse — `(defn name (params) (Maybe i32) …)` / `(defn name (params):(Maybe i32) …)`. An optional `noreturn` attribute follows the return type. `defprotocol` method signatures and `declare` use the same grammar. (The legacy return-in-the-name spelling `(defn name:ret (params) …)` was retired in Stage 14 and is now a hard error.) Supports `&rest` for variadic functions: `(defn name (a:t &rest xs:elem) ...)`. The rest parameter receives a `Node*` cons-list head built at the call site (so each call site emits `@make-cell` calls and the program must define a compatible `make-cell`). The element type annotation is documentation only — non-`ptr` args are `inttoptr`'d into `Node.car`. `&rest` functions are not directly C-callable; calling through a function pointer requires manually constructing the rest list. `&rest` must be the second-to-last param. Supports `&optional` for trailing parameters with defaults: `(defn name (a:t &optional (b:t default) ...) ...)`. Each `&optional` param must be a 2-element list `(name:type default-expr)`. Defaults are evaluated at the call site in the caller's scope (Common Lisp semantics), so non-constant defaults like `(next-counter)` produce a fresh value per call. Implicit casts apply to defaults. The compiled function has fixed maximum arity at the LLVM/C ABI level — calling through a function pointer or from C requires supplying every argument including the optional ones. `&optional` cannot be combined with `&rest`. **Calls are arity-checked** against the signature — exactly `num-params` for a plain `defn`, a band for `&optional`, a floor for `&rest` (see [Call arity](compiler.md#call-arity)). A struct-by-value parameter or return is lowered to the platform C ABI (see [Passing and returning structs by value](structs-unions.md#passing-and-returning-structs-by-value)). **Docstring**: if the first body form is a string literal AND there is at least one more form after it, that string is captured as the function's docstring (visible via `(doc fn)` and `(apropos)`); a function whose body is a single string literal is treated as returning the string, not as having a docstring. The same convention applies to `defmacro`. **Overloadable:** defining `defn` again with the same name but different parameter types adds a method — see [Polymorphism](generics.md#polymorphism-overloaded-defn-multimethods). | function definition |
| `defconst` | Define a compile-time constant `(defconst name value)`, where `value` is an integer literal. **The name behaves exactly like the literal it stands for**: it is typed by its value (`i32`, or `i64` when the value does not fit — `(defconst BIG 5000000000)` is `i64`), it *adapts* to the other operand of a binary operator the way a bare literal does (`(<= ans:ui32 K)` compiles iff `(<= ans:ui32 512)` does, in either operand order), and it is rejected — not silently wrapped — where its value does not fit the slot it flows into. See [Integer literals](types.md#integer-literals) and [Binary operators](types.md#implicit-type-coercion). The name takes **no** type annotation — `(defconst K:i32 2)` is rejected (`defconst: takes no type annotation; write (defconst K 2)`) rather than silently accepted, since the value already determines the type. | `#define` / `enum` constant |
| `defenum` | Define an enumeration `(defenum Name member ...)` — a flat list of member names, each bound to its 0-based ordinal as an `i32` constant. A member is a named integer literal and adapts at a use site exactly as `defconst` does (`(= c:ui32 GREEN)` is as legal as `(= c:ui32 1)`). Like `defconst`, the enum's own name takes no type annotation. | `enum` |
| `defvar` | Define a global variable `(defvar name:type [init])`. **The initializer grammar has three tiers.** (1) A **compile-time constant** — a literal, a `defconst` / `defenum` name, a constant *expression* over them (arithmetic, bit operations, `(sizeof T)`, `(as T x)`), `(addr-of g)`, and constant **aggregates**: an `(array T …)` literal and an `(S …)` struct literal, nested to any depth. These are baked into the emitted global, applied by the loader before any code runs, and cost nothing. (2) Anything else — a call, an allocation, a read of another global — is a **run-time initializer**: the slot is emitted zero-filled and the initializer runs at **startup, before `main`**, as an ordinary assignment, so `(defvar g:ptr:T (make-thing))` typechecks with `g` non-null. (3) **Refused:** a run-time initializer at an `(array T N)` slot, for a `:const` global, or inside a `compile-time` / `defmacro` body; a non-constant *element* of a constant aggregate; a scalar at an aggregate slot; and an initializer that syntactically names a global whose own `defvar` has not been reached yet (the error names both sites). See [Global initializers](#global-initializers) for the constant grammar and the arithmetic rules, and [Run-time initializers](#run-time-initializers) for the ordering rule and its diagnostic, the zero-cost-when-unused guarantee, and the targets (AVR) that refuse one. An integer initializer, literal, named or folded, that does not fit the declared type is a compile-time error rather than a silent truncation. Omitted inits default to zero / `null` / `false`; a global of **aggregate** type (struct, union, or `(array T N)`) with no init is zero-filled (`zeroinitializer`), so e.g. `(defvar g:MyStruct)` and `(defvar g:(array i32 256))` are valid. **An omitted init is refused for a non-null typed pointer** — `(defvar g:ptr:T)` is an error, because the zero it would take is `null`; give it an initializer or declare it `(raw T)`. See [A non-null global must be initialized](#a-non-null-global-must-be-initialized). `set!` works on the result. The symbol is exported with default linkage and is visible to C consumers (`extern T name;` in the generated C header -- with an `asm("...")` label when the Nucleus name is not a C identifier; see [Reaching a library's globals from C](compiler.md#reaching-a-librarys-globals-from-c)) and other Nucleus modules (`(extern name:type)`). **Storage class specifiers:** file-scope `static` is the private definer `defvar-` (internal linkage); `register` is a no-op (LLVM ignores it); `thread_local` is reserved in the declaration-attribute slot (`:thread-local`) but not yet implemented — it errors with a targeted diagnostic pointing at the threading-stage blocker (`design/stage14/attributes.md` §5). Function-scope `static` locals and `:align`/`:section`/`:weak` are sketched but not implemented (same doc, §6). Function attributes ARE implemented (Stage 14 AVR-5) — but as the separate top-level `fn-attr` directive below, not as a keyword in this decl-attribute slot. C's global `const` is the `:const` declaration attribute (Stage 14 AVR-6): `(defvar :const name:type init)` emits an LLVM `constant` instead of `global`, and is rejected everywhere else the attribute registry applies since only a `defvar` global has an independent storage class to select — see [Const globals](types.md#const-globals). | global variable definition |
| `defstruct` | Define a struct type, or a parametric struct template when the name is a list: `(defstruct (Name T ...) ...)`. Like `defconst`, a **bare** (non-template) name takes no type annotation — `(defstruct S:i32 (f i32))` is rejected (`defstruct: takes no type annotation; write (defstruct S ...)`); a genuine template head such as `(Vector T)` is unaffected. See [Parametric struct templates](structs-unions.md#parametric-struct-templates-defstruct-name-t-). | `struct` |
| `defunion` | Define a tagged sum `(defunion Name (arm field:type ...) ... bare-arm)` or a template `(defunion (Name T ...) ...)`. Like `defconst`, a **bare** (non-template) name takes no type annotation — `(defunion U:i32 (a x:i32) b)` is rejected (`defunion: takes no type annotation; write (defunion U ...)`); a genuine template head is unaffected. See [Unions and tagged sums](structs-unions.md#unions-and-tagged-sums). | tagged `struct {int tag; union {...} payload;}` |
| `defprotocol` | Define a protocol: a named set of required method signatures (types may mention `Self` and extra element parameters). Compile-time only; emits no code. Like `defconst`, a **bare** (non-parametric) name takes no type annotation — `(defprotocol P:i32 ...)` is rejected (`defprotocol: takes no type annotation; write (defprotocol P ...)`); a genuine parametric head such as `(Seq E)` is unaffected. See [Protocols](generics.md#protocols-defprotocol-and-extend) and [Parametric protocols](generics.md#parametric-protocols). | — (concept: interface/trait) |
| `extend` | Assert conformance `(extend Type Protocol)` or parametric conformance `(extend (Name T) (Protocol T))`: checks that each required signature resolves, then records the fact. Code-free. See [Protocols](generics.md#protocols-defprotocol-and-extend) and [Parametric protocols](generics.md#parametric-protocols). | — |
| `import` | **Prefix-qualified import** (the default, deliberate-API form). `(import lib [prefix])` exposes each public symbol of `lib` as `prefix/name`, pointing at the same definition (no new code; a foreign C symbol keeps its bare link name, so `c/printf` calls `@printf`). `lib` resolves `name.nuc` (source) or `name.nuch` (header) from source directory, `lib/`, `-I` paths, `$NUCLEUS_LIB`, or `/usr/local/share/nucleus/lib` (the install-time default used by `make install`); a string path imports a C header (`(import "stdio.h")`, preprocessed with `clang -E`) or an explicit `.nuc`/`.nuch` file by path. The prefix defaults to the lib's last dotted component (`foo.bar.baz` → `baz`); a string-path C header defaults to `c` (`(import "stdio.h" c)` → `c/printf`). The **same library** may be imported under **multiple** prefixes (aliasing); two different libraries **may not share** a prefix (error). Dedup is keyed on `(file, prefix)`. **A prefix binds only in the file that declares the import** — see [Import prefixes are file-scoped](#import-prefixes-are-file-scoped). Source imports inline all definitions; header imports emit `declare` (extern) for functions. *(`import` and `import-prefixed` are synonyms.)* | — |
| `import-use` | **Flatten import** — brings **every** symbol of a library or C header into the current namespace under its bare name, including private symbols (the opt-out from the prefixing discipline). Good for the REPL and for libraries; discouraged for deliberate API design. `(import-use name)` / `(import-use "hdr.h")`. The prelude is auto-`import-use`d into every unit. | — |
| `import-prefixed` | Explicit spelling of the prefix-qualified `import` above: `(import-prefixed lib [prefix])`. Identical to `import`. | — |
| `import-only` | Import a concrete list of symbols: `(import-only lib sym1 sym2 ...)`. The listed symbols are brought in under their bare names. *(Currently flattens like `import-use`; the restriction to only the listed symbols is enforced once private/visibility filtering lands.)* | — |
| `unsafe-import-private` | **Retired in Stage 14** — bare `unsafe-import-private` is now a targeted hard error: `'unsafe-import-private' was split in Stage 14: use 'unsafe/import-private'`. | — |
| `unsafe/import-private` | Prefix-qualified import that also reaches a library's private (`defn-`/`defvar-`/etc.) symbols: `(unsafe/import-private lib prefix sym...)`. Discouraged; for breaking encapsulation deliberately. The listed symbols are advisory (not yet filtered) — every private symbol from the library is aliased under the prefix. See [Special Forms](special-forms.md#special-forms). | — |
| `declare` | Declare an external function signature `(declare name (params...) :rettype)`. Used in `.nuch` header files and at the top level. **Parameters carry their types in both spellings.** A parameter may be written *named* — `(declare lseek (fd:i32 off:i64 whence:i32):i64)` — or *unnamed*, as its bare type — `(declare lseek (i32 i64 i32):i64)`; the two produce the same signature, and a list may mix them. In a declaration the name is documentation only (nothing binds it), so an unnamed parameter is a **type operand**: any type spelling works there, including a keyword (`:i64`), a compound (`(Vector i32)`), and a struct name (passed by value under the platform C ABI). A spelling that names no type is a compile-time error — there is no default. **An element carrying a `name:type` annotation is a named parameter**, exactly as in a `defn`, so `(declare f (ptr:FILE):void)` declares a parameter *named* `ptr` of type `FILE` (by value), not a pointer to `FILE` — write `p:ptr:FILE`, or a bare `ptr`, for a pointer parameter. `&rest` / `&optional` are `defn`-only and are rejected here; a C variadic function needs no marker, because **a declared signature is open-tailed** — [call arity](compiler.md#call-arity) requires the declared (fixed) parameters and admits any number of extra arguments after them, so the variadic tail simply rides the call site. Too *few* arguments is still an error. Importing the function's C header is the precise route: the header carries a real variadic flag, so the fixed prefix is checked exactly. See also [Declaration precedence](structs-unions.md#declaration-precedence-an-explicit-declare-wins). | function prototype |
| `extern` | Declare a foreign global variable `(extern name:type)`. The compiler emits `@name = external global T`, leaving storage and initialization to the linker. Works for both C-defined and Nucleus-defined producers; the matching `defvar` may live in another `.o` file. | `extern` declaration |
| `defmacro` | Define a compile-time macro `(defmacro name (params...) body...)`. The name takes **no** type annotation — `(defmacro m:i32 (x) x)` is rejected (`defmacro: takes no type annotation; write (defmacro m ...)`) rather than silently compiling and failing at the call site. Supports `&rest` for variadic macros: `(defmacro name (a b &rest rest) ...)` — `rest` receives a cons list of remaining args. Parameters (and the `&rest` list) are typed `(raw Node)` inside the body, so `(p car)`, `(p cdr)`, chains like `((p cdr) car)`, `(p kind)`, and `(p s)` work directly with no `(as ptr:Node ...)`. The macro can splice a parameter into a quasiquote regardless of the value type the user-supplied expression evaluates to at the call site — see [Macros and pass-through arguments](macros.md#macros-and-pass-through-arguments). | macro |
| `defcast` | Register an implicit conversion `(defcast From To conv-fn)`. `conv-fn` must be a unary function with signature `To (From)` already in scope; the compiler emits a call to it whenever an arg of `From` is supplied where `To` is expected. Pairs already covered by built-in coercion (identity, int↔int, `f32`→`f64`) are rejected at registration. Rules are unidirectional and non-transitive — declare each direction explicitly, and chain through an intermediate type by writing the chain yourself. Exported in `.nuch` headers. | implicit conversion |
| `def-rmacro` | Define a reader macro `(def-rmacro "prefix" symbol)`. When `prefix` appears at the start of a token, the reader wraps the next form: `(symbol form)`. Built-in reader macros: `'` (quote), `` ` `` (quasiquote), `~` (unquote), `~@` (unquote-splice), `@` (deref). | — |
| `exclude-prelude` | Suppress the implicit `(import-use prelude)` for this source file. Must be the first top-level form; takes no arguments. Use when a file should compile against the bare language without the standard macros, `Node` struct, or `(import-use "string.h")` declarations. The directive applies to the **compilation unit's entry file only** — the prelude is a property of the unit, not of a file — so a copy of it in a file that is *imported* is ignored rather than being an error. | — |
| `ns` | Set the current namespace for this source file: `(ns name)`. `name` must be a slash-free symbol. Symbols defined after this form are stored under `namespace/name` qualified keys. A second `ns` in the same file warns at compile time (silent in the REPL). The default namespace is `user`, which stores bare keys — byte-identical to pre-namespace behavior. Conventionally the first form in a file. **Everything defined after `(ns …)` is namespaced**: functions, values, protocols and **types** alike — a `defstruct`/`defunion`/`defenum`/template declared in `(ns shapes)` defines `shapes/Circle`, exactly as a `defn` there defines `shapes/area` (see [Protocols are namespaced](generics.md#protocols-are-namespaced) and [Namespaced type names](types.md#namespaced-type-names)). Two namespaces may each declare a type of the same name — they are two distinct types — and a reference to either, bare or qualified, resolves through the writing file's own import environment exactly like any other name; see [What an import brings into scope](#what-an-import-brings-into-scope). | — (concept: C++ `namespace` / Clojure `ns`) |
| `set-ir-prefix` | Override the IR-mangling prefix for the current namespace: `(set-ir-prefix "prefix")`. An empty string forces bare IR names regardless of the namespace (C-ABI escape hatch). A non-empty string replaces the namespace name in emitted IR identifiers. Applies to symbols defined after this directive. Typically placed immediately after `ns`. | — |
| `export` | Re-export symbols from this namespace: `(export sym1 sym2 ...)`. Makes the listed symbols visible to importers of this namespace under their unqualified names (the part after the last `/`). Typically used in facade libraries to re-expose imported symbols without the importer needing to know the original source namespace. The symbols must already be in scope (via `import-prefixed` or defined in this file). No new IR is emitted — it adds alias entries to the module's export table. Example: `(export geom/area geom/perimeter)` in a `gfacade` namespace causes `(import-prefixed gfacade g)` to expose `g/area` and `g/perimeter` to the importer. **Functions, values, protocols, structs, unions, enums, templates and macros can be re-exported.** Types are on this list because type identity is namespaced (see [Namespaced type names](types.md#namespaced-type-names)): a facade that re-exports `geom/area` but not `geom/Pt` would export a function whose signature names a type the consumer has no way to spell. **An overloaded function, a special form, or a built-in type name cannot** — none of them is keyed by namespace, so a re-export would not change how it resolves. An overloaded name is the deliberate case: one entry per bare name carries every namespace's methods (see [Qualifying an overloaded function](#qualifying-an-overloaded-function)), so it is already reachable everywhere. Naming one is refused with `export: 'X' is a function — that kind is not keyed by namespace, so a re-export would not change how it resolves` (the noun changes with the kind: "a special form", "a built-in type"). | — (closest C analogue: a header that `extern`-declares symbols from another translation unit) |
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
* **Only four of the eight definers get file scope. The other four are always
  namespace-scoped.** `defn-`, `defvar-`, `defconst-` and `defenum-` name
  *values*, whose registry key can carry a synthetic per-file namespace, so in a
  file with no `(ns …)` they are private to that file. `defstruct-`,
  `defunion-`, `defmacro-` and `defprotocol-` name *types, macros and
  protocols*, which have no per-file key space — `(ns …)` is what makes their
  privacy mean anything — so in the default `user` namespace they are visible
  to the whole unit, and a file that declares `(ns …)` is what actually hides
  them. Reaching one from outside its namespace is an error at the reference —
  a type reports `unknown type: Name`, a macro or value `unknown: name`, and a
  protocol `extend: unknown protocol 'Name'`. **For a type**, since type
  identity is namespaced (see
  [Namespaced type names](types.md#namespaced-type-names)), that failure comes
  in two tiers rather than one: a *bare* reference to a private type in another
  namespace fails for the ordinary scope reason first — the same message a
  *public* type in an unimported namespace gets, since the bare spelling was
  never in scope to begin with — and only a *qualified* reference spelled
  through a prefix that actually reaches the namespace gets as far as finding
  the (hidden) entry, where privacy then refuses it: `unknown type: p/Name`,
  using the qualified spelling. A macro behaves the same way as of the macro
  cut-over: a bare reference to a private macro in another namespace fails for
  the ordinary scope reason, and only a prefixed spelling reaches the privacy
  check.
* Privacy affects only the *name*. The emitted symbol still exists (with internal
  linkage); it is simply spelled per-file, so nothing outside the file can name
  it and nothing collides at link time.
* A namespace name may not begin with `#` — that shape is reserved for the
  implicit per-file scope this rule is built on.

## Import prefixes are file-scoped

**An import prefix binds only in the file whose own `import` form declares it.**
Importing a library under a prefix somewhere in the unit does not make that
prefix spellable everywhere:

```lisp
; mid.nuc
(import-prefixed geometry gx)
(defn mid-area (w:i32 h:i32):i32 (return (gx/area w h)))   ; fine — mid.nuc declared gx

; main.nuc — imports mid, never declares gx
(import-use mid)
(defn main ():i32 (return (gx/area 3 4)))                  ; error
```

```
main.nuc:2: error: unknown: gx/area — 'gx' is not in scope in this file
  note: an import prefix is file-scoped: another file in this unit binds 'gx' to
  lib/geometry.nuc, but a prefix reaches only the file whose own import declares
  it. This file has no import qualifiers in scope.
```

The fix is to write the import you meant in the file that uses it — a repeated
`(import-prefixed geometry gx)` is free (the library is loaded once; the second
import only binds the name).

This is a scope rule, not a reachability one. The definition is in the unit and
the import graph reaches it, which is why the diagnostic says the *spelling* is
out of scope rather than claiming the name is undefined. Note the two rules
compose in the usual direction: a prefix declared in a library is invisible to
that library's consumers, so a library's choice of prefix is its own business
and can be changed without breaking anyone.

Two edges:

* The **same prefix in two files** for the same library is fine and common;
  two *different* libraries may still not share one prefix within a unit.
* A **namespace** qualifier is subject to the same file scope — see the next
  section.

## What an import brings into scope

**A qualifier means something only in a file whose own import form bound it.**
There is no ambient list of namespaces: an import declares what this file can
spell, and that declaration is the whole answer.

| Import form | What the file can spell |
|---|---|
| `(import-prefixed lib p)` / `(import lib p)` | `p/name` — **and not** the library's own namespace |
| `(import-use lib)` | `name` (unqualified) **and** `<lib-namespace>/name` |
| `(import-only lib a b)` | as `import-use` today; the filter is not yet built |
| implicit prelude | as `import-use` — so `user/` and every bare prelude name are always in scope |
| the file's own `(ns n)` | `name` and `n/name` |
| implicit `unsafe` | as `import-prefixed` — `unsafe/cast`, `unsafe/ptr+`, `unsafe/funcall-ptr-*`, `unsafe/import-private`, and **nothing unqualified** |

The second column of row 1 is the point: an import prefix *is* the API the
consumer chose, so the library's internal namespace stays the library's business.
Row 2's second clause is the escape hatch for a collision — when two flattened
libraries both define `Vector`, `a/Vector` disambiguates without rewriting the
import form.

The last row is why bare `cast`, `ptr+` and `funcall-ptr-*` are errors: `unsafe`
is a real built-in namespace, bound in every file the way a prefixed import
binds — so it is never flattened, and there is nothing to write unqualified.
`(ns unsafe)` is refused for the same reason: the name is already bound.

```lisp
(import-prefixed shapes sh)     ; lib/shapes.nuc declares (ns shapes)

(extend Circle sh/Shape)        ; ok — sh is what this file bound
(extend Circle shapes/Shape)    ; error — the namespace is not in scope here
```

```
main.nuc:6: error: extend: unknown protocol 'shapes/Shape'
  note: 'shapes' is not in scope in this file — a prefixed import binds its
  library under the prefix it names and not under the library's own namespace,
  and an unimported namespace is not nameable at all. In scope here: sh.
```

**Scope of the rule today.** It governs **protocol** references (`extend`,
`(dyn P)`, `&where` constraints, protocol inheritance), every **global** —
functions, `defvar`s, `defconst`s, enum members, `extern`s and `declare`d C
functions — and every **type** — struct, union, enum and template names alike.
`anything/Circle` no longer resolves the way it used to: a type reference needs
its qualifier in scope in exactly the way a global or protocol reference does.
**Overloaded** functions are on this path too, by a different mechanism — see
[Qualifying an overloaded function](#qualifying-an-overloaded-function) below.
**Macros** are on it as well: `p/my-macro` resolves through an import prefix,
the defining namespace does not, and two namespaces may each declare a macro of
the same name. Every name-keyed kind now answers the same scope question.

Two namespaces may therefore each define a type of the same name — they are
genuinely distinct types, with distinct layouts and distinct conformances —
and a consumer that imports both keeps them apart by the qualifier each was
bound under:

```lisp
; lib/veca.nuc
(ns va) (defstruct Vector x:i32 y:i32)

; lib/vecb.nuc
(ns vb) (defstruct Vector x:i32 y:i32 z:i32)

; consumer
(import-prefixed veca a) (import-prefixed vecb b)

(defn main ():i32
  (let (p:a/Vector (a/Vector 1 2)
        q:b/Vector (b/Vector 1 2 3))
    (return 0)))   ; p and q have unrelated layouts, though both read "Vector"
```

Three consequences of globals and types sharing this path, all new:

* **A prefixed import reaches globals, constants, enum members and types**,
  not just functions and protocols. It used to reach functions (and, more
  recently, protocols) only — the prefix was implemented by copying entries
  out of one registry, and the copy was filtered on fields that meant
  something else (`defvar`s and constants were skipped by accident; types
  were not keyed by namespace at all). There is no copy any more: the prefix
  names a file, the file names a namespace, and the namespace composes the
  key the library already registered — for a type as much as for a `defn`.
* **A qualified reference needs its qualifier in scope even inside the unit.**
  Cross-file *reachability* (next section) is unchanged for bare names, but
  `otherns/thing` requires an import in **this** file that binds `otherns` —
  either `(import-use otherlib)` or a prefix of your own. This applies to
  `otherns/Circle` exactly as to `otherns/some-fn`.
* **A bare type reference to a type defined in a namespace this file did not
  import** gets a located diagnostic naming the defining namespace, plus a
  note offering the spelling this file can actually write when it has bound
  some prefix that reaches that namespace — see
  [Namespaced type names](types.md#namespaced-type-names) for the exact
  message. The same tier fires in head position too, so a bare struct
  constructor for a type in an unimported namespace gets the same answer.

### Qualifying an overloaded function

An **overloaded** name — a `defn` with two or more methods, dispatched by
argument type, which is also what every protocol method is — is stored
differently from everything above. There is exactly **one** entry per bare name
for the whole unit, with the methods of every namespace merged into it, because
that is what an open multimethod needs: two libraries that each declare a
`describe` method must be usable together rather than colliding on sight.

A qualifier is therefore not a different key; it is a **filter**. `p/describe`
means "the `describe` methods that came from the namespace `p` names":

```lisp
; lib/liba.nuc            ; lib/libb.nuc
(ns na)                   (ns nb)
(defn desc (x:i32):i32    (defn desc (x:i32 y:i32):i32
  (return (+ x 100)))       (return (+ (+ x y) 20)))

; consumer
(import-prefixed liba pa)
(import-prefixed libb pb)

(pa/desc 1)      ; 101
(pb/desc 1 2)    ; 23
(pa/desc 1 2)    ; error: no matching method for overloaded 'desc'
                 ;        with argument types (i32, i32)
(na/desc 1)      ; error: 'na' is not in scope in this file
```

The third line is the point: the qualifier really does restrict the method set,
so an overload another namespace contributed is not reachable through `pa/`.
The fourth is the ordinary scope rule — a prefixed import binds the prefix, not
the library's namespace.

Two consequences of the merged registry, both deliberate:

* **A bare call still sees every reachable overload**, including ones from a
  library this file imported *prefixed*. Bare `desc` above resolves; the
  qualifier is what narrows, not what enables.
* **Two overloads with the same parameter types are still an error**, wherever
  they come from — a merged registry with two identical signatures has no
  dispatch answer. That is the function row of the redefinition rule below.

Bounded-generic templates (`&where`) and their stamped instances follow the
same rule: a stamp belongs to the namespace that declared the template, not to
the file that triggered it.

### One definition per name

A name may be defined **once** in a compilation unit. A second `defstruct`,
`defunion`, `defprotocol`, `defmacro`, `defenum`, `defvar`, `defconst`, enum
member or `defstruct`/`defunion` template of the same name is an error that
names both definitions:

```
b.nuc:1: error: redefinition of 'Node' — it already names a type defined at a.nuc:13
  note: a name may be defined only once in a compilation unit. If two imported
  libraries both define it, rename one — or give one an (ns ...) of its own and
  import that library with `import-prefixed`.
```

For a **function** the rule is the same one it always was, and it is about the
signature rather than the name: two `defn`s of one name are overloads, and only
two overloads with the *same* parameter types collide (`duplicate definition of
'f' — the same parameter types are already defined at …`).

Notes on what this does and does not cover:

* **It is a per-unit rule, so importing one file through several paths stays
  legal.** The diamond every non-trivial program has — two libraries that both
  import a third — is not a redefinition; the file is processed once.
* **Giving one definition a namespace is the fix for a genuine clash**, and the
  diagnostic says so: `(ns …)` in one library plus `import-prefixed` in the
  consumer keeps both names alive under different qualifiers.
* **The REPL is exempt.** An interactive session is a sequence of units typed
  one at a time, and redefining a name is the point of it.

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

  **Three things a cycle does not carry**, because they only exist once a file
  has been *emitted*, and a cycle member's body is emitted before the rest of
  the file it back-imports. Each is refused with a located diagnostic naming the
  cycle, never a wrong answer:

  | Across a cycle | Diagnostic |
  |---|---|
  | A `defmacro` the partner defines | `unknown: NAME — defined in a file this unit imports circularly` |
  | A `deferror` id or an `extern` declaration the partner defines | `undefined: NAME — defined in a file this unit imports circularly` |
  | A struct/union **layout** the partner defines — a field access, a struct literal, a by-value parameter/return/argument, or a by-value field of another struct | `<use>: 'S' has no layout at this point` |

  A fourth used to be listed here — a `prefix/name` spelling over a cycle
  member — and is gone: a prefix now names the imported *file*, whose namespace
  and signatures the whole-graph prescan has already recorded, so it resolves
  across a cycle like any other reference.

  What *does* work across a cycle: calling the partner's functions (the point of
  the feature), reading its globals, constants and enum members, naming its types
  **behind a pointer** (`ptr:S`, `(ref S)`), and `(sizeof S)` / `(alloca S)` —
  those lower to a GEP over the LLVM named type, which is resolved from the
  definition emitted later in the same module.

  If you hit one of these, the fix is the common-parent spelling above, or
  moving the shared macro/error/type into a third file both import.
* **Reordering imports cannot change what resolves.** Alphabetizing an import
  list, or inserting a new import anywhere, changes nothing about which names a
  program sees. It *can* change the order **run-time initializers** run in —
  that is a sequencing question rather than a resolution one, and it is the one
  place in the language where import order is observable. A *constant*
  initializer has no order at all: it is applied by the loader before any code
  runs. See [Order](#order) below, and
  [Resolution is order-free; initialization is not](#resolution-is-order-free-initialization-is-not)
  for why the two rules are not in tension.
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
* **A `.nuch` header is outside the graph walk, and stays ordinal.** The names a
  header contributes — a `declare`d function, an `extern` global, a `defconst`,
  a `defenum` member — register when the header is imported, so **import the
  header before the file that uses it**. This holds for functions and values
  alike, so there is no asymmetry between the two kinds of name. Its *types* are
  not affected: a `defstruct` in a header is pre-registered like any other, so a
  signature may name it before the import.
  *(A `.nuc` file imported by string path — `(import-use "lib/foo.nuc")` — used
  to have the same limit and no longer does: both spellings of an import are
  walked identically.)*
* **A name overloaded anywhere in its namespace gets the mangled symbol
  everywhere in that namespace.** Whether a `defn` keeps the plain `@name` LLVM
  symbol or gets an overload-mangled one is decided from the *whole* unit's
  method set for that namespace, before any function is emitted — so it no longer
  depends on where in the import order the second overload happens to appear.
  Another namespace defining the same name is not an overload of yours and does
  not affect your symbol (see [symbol mangling](generics.md#polymorphism-overloaded-defn-multimethods)).
  If you link C against a Nucleus function, make sure no other reachable file *in
  its namespace* overloads its name (or expose a uniquely named wrapper).
* Everything else about a name — visibility (`defn-`), namespaces, and prefix
  qualification — is unchanged; only *when* a file's signatures and value names
  become visible moved. In particular a **private** value (`defvar-`,
  `defconst-`, `defenum-`) is registered under its own file's scope from the
  start, so a forward reference to one inside its own file resolves to it and
  not to some other file's public name of the same spelling.

### Resolution is order-free; initialization is not

The rule above says import order does not affect resolution. The rule under
[Order](#order) says a run-time initializer runs when its `defvar` is reached,
which *is* import order. These are not in tension, and the difference is worth
stating plainly because they look alike:

* **Resolution has exactly one right answer, independent of order.** Whether
  `LIMIT` names that `defconst` does not depend on where anything sits; an
  order-dependent answer was simply a bug, which is what the reachability rule
  above fixed. An import establishes *reachability*, not visibility.
* **Initialization is inherently sequential.** Two assignments cannot both run
  first, so *some* order has to exist and be specified. Making it emission order
  is a choice about sequencing, not a return to the ordinal resolution rule that
  was retired. C++ has the same rule within a translation unit, and leaves it
  unspecified across them.

The two stay separate because nothing about initialization feeds back into
resolution: every reachable file's `defvar` / `defconst` / `defenum` names are
registered before the first form is emitted, so a `defvar` initializer naming a
global declared later still *resolves* to it. That is why the forward-reference
case gets an ordering diagnostic naming both sites rather than an "undefined"
error — the compiler knows exactly what the name means and is objecting to
*when*, not to *what*.

In short: **what a name means never depends on order; when a global's
initializer runs always does** — and only for a run-time initializer, since a
constant one has no order at all.

## Global initializers

A `defvar` initializer is preferably a value the compiler can compute while
compiling: it is then baked into the emitted `@g = global …` line, applied by
the loader before any code runs, and costs nothing at run time. A global with no
initializer is zero-filled the same way.

An initializer the compiler **cannot** reduce to a constant — a call, an
allocation, a read of another global — is legal too, and runs at **startup**,
before `main`. See [Run-time initializers](#run-time-initializers) below for the
ordering rule, what it costs, and the targets on which it is refused.

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
  `ptr`, `(raw T)` / `?T`, or a **function-pointer type** `(fn ret)(params)` —
  the pointer kinds do not apply to a fn pointer, so it is nullable like `CStr`,
  and the implicit zero for the same slot is `null` anyway (see
  [Function-pointer globals](types.md#function-pointer-globals)). A *typed
  non-null* pointer (`ptr:T`, `(ref T)`) rejects it with the same diagnostic the
  identical local binding gets, since a non-null slot holding `null` compiles
  clean and faults on first use — and that includes `ptr:(fn ret)(params)`,
  which is a pointer *to* a function pointer, not a function pointer.
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
  or same-width reinterpret is fine, and so is a narrowing whose value fits the
  target (`(as i8 5)`); a narrowing that does not fit must be spelled
  `unsafe/cast`. Every operand here has folded to a known constant, so the
  "does it fit" question always has an answer.

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

### What is not folded

These are not compile-time constants. At a **scalar, pointer or struct** slot
they are accepted as [run-time initializers](#run-time-initializers); at an
`(array T N)` slot, and as an element of any constant aggregate, they are
refused — see the list after next.

* **Anything that has to run** — a function call, an allocation, a value read
  out of another global.
* **Float arithmetic.** A float *literal* initializer is folded; `(+ 1.0 2.0)`
  is not.
* **Comparisons and `and` / `or`.** They yield `i1` and are not part of the
  folded domain; write the answer.

### What is still refused

* **A run-time initializer at an `(array T N)` slot.** An array binding names
  storage, not a value — `set!` cannot target one — so there is nothing for a
  startup assignment to do. Declare the pointer form instead
  (`(defvar g:ptr:T (make-table))`), or keep the table constant.
* **A non-constant element of a constant aggregate.** An aggregate constant is
  filled at link time and there is no assignment that could fill one slot of it,
  so an element that has to run is `init must be a compile-time constant`.
* **A run-time initializer for a `:const` global.** `:const` storage is
  read-only; there is no store that could initialize it.
* **A run-time initializer inside a `compile-time` or `defmacro` body.** Those
  modules have no program globals and no startup, so the initializer would never
  run; it is refused rather than silently left at zero.
* **Union initializers.** A `(defvar u:MyUnion)` is zero-filled, but there is no
  constant *union* literal — a union has no unambiguous member to initialize —
  so assign a member at run time (a run-time initializer at a union slot works
  and is the supported route).
* **A scalar at an aggregate slot.** `(defvar p:P 5)` names what would work
  rather than being treated as a run-time initializer.
* **A type whose layout the current import cycle has not produced yet.**
  `(sizeof S)` answers from the compiler's layout table here rather than from
  LLVM, so across an import cycle it is refused with the same message a by-value
  use gets, instead of silently folding to zero.
* **An initializer that names a global whose own `defvar` has not been reached
  yet** — including the two-global cycle. The error names both sites; see
  [Order](#order), which also states exactly which forward references the
  compiler can and cannot see.

## Run-time initializers

An initializer that is not a compile-time constant runs at **program startup,
before `main`**:

```lisp
(defstruct Thing n:i32)
(defvar g-thing:ptr:Thing (make-thing))     ; runs before main
(defvar g-limit:i32       (read-limit))
```

The slot itself is still emitted zero-filled; the compiler collects every such
initializer into one synthesized `void @__nucleus_init()` and registers it with
`llvm.global_ctors`, i.e. the platform's ordinary `.init_array` mechanism — the
same one a C++ static constructor uses. Nothing about `main` changes: it is an
ordinary function, is not renamed, and is not wrapped.

**Each initializer is exactly an assignment**, so it is checked exactly as
`(set! g …)` is. In particular the nullability rule applies unchanged, which is
the point of the feature: a **non-null** global can be declared and initialized
in one operation.

```lisp
(defn mk    ():ptr:Thing   …)
(defn mkraw ():(raw Thing) …)

(defvar ok:ptr:Thing  (mk))       ; fine — ptr:Thing is non-null, and so is (mk)
(defvar bad:ptr:Thing (mkraw))    ; error: raw pointer where non-null (ref ...) is required
```

### A non-null global must be initialized

Because there is now a way to write the initializer, **there is no longer a way
to declare a non-null global without one**. `(defvar g:ptr:T)` with no
initializer is a compile-time error:

```
demo.nuc:12: error: defvar: 'g' has a non-null pointer type but no initializer --
  the slot would start as null, which is exactly the value its type says it can
  never hold
  note: give it an initializer, or declare it nullable with `raw` (`(raw T)` /
  `raw:T`) if it genuinely may be null before first use
```

This closes the last position in the language where `ptr:T` did not mean
non-null. Every other slot — a `let`/`with` binding, a `set!`, a field or
element store, an argument, a return — has refused a null-valued `ptr:T` since
the safety flip; a global's implicit zero was the one place that produced one
anyway, and it was tolerable only while an initializer could not be written at
all.

The rule is exactly `pkind-flow-check`'s: it fires when the declared type is a
**non-null pointer with an element type**, so the existing exemptions come with
it rather than being restated.

```lisp
(defvar g:ptr:Thing)              ; error
(defvar g:ptr:Thing (make-thing)) ; fine — run-time initializer
(defvar g:ptr:Thing (addr-of x))  ; fine — constant initializer
(defvar g:(raw Thing))            ; fine — `raw` is honestly nullable
(defvar g:?ptr:Thing)             ; fine — a Maybe pointer may be none
(defvar g:ptr)                    ; fine — bare `ptr` names no pointee
(defvar g:CStr)                   ; fine — not a typed pointer kind
(defvar g:MyStruct)               ; fine — an aggregate zero is a valid MyStruct
```

A global's *storage* is still zero-filled either way; what changed is whether a
declaration is allowed to leave the slot holding a value its own type forbids.

### Order

**Initializers run in the order their `defvar` forms are reached during
compilation** — source order within a file, import order across files (an
imported file's forms are reached where its `import` appears). This is the same
rule C++ uses within a translation unit.

```lisp
(defvar g-n:i32     (compute))    ; runs first
(defvar g-after:i32 (+ g-n 1))    ; runs second, and sees g-n's value
```

Reading a global whose `defvar` has **not** been reached yet would get that
slot's zero rather than its initialized value. **When the compiler can see that
happening it refuses to compile the program**, naming both sites:

```lisp
(defvar g-after:i32 (+ g-n 1))    ; error, at this line
(defvar g-n:i32     (compute))
```

```
demo.nuc:1: error: defvar: the initializer for 'g-after' names global 'g-n',
  whose own defvar has not been reached yet -- it still holds its zero at this point
  note: 'g-n' is declared at demo.nuc:2; initializers run in the order their
  defvars are reached (source order within a file, import order across files),
  so move that defvar above this one -- unless it depends on this one in turn,
  which is a cycle no order satisfies
```

Swapping the two forms is the fix. Across files, the same diagnostic names the
other file and line, and the fix is to move the `import` (or the `defvar`).

**What the check does and does not see.** The boundary is exact, and the half it
cannot see is a permanent limit rather than an unfinished feature:

* **A name written in the initializer is checked.** `(defvar a:i32 (+ b 1))`,
  `(defvar a:i32 b)`, a call *through* a function-pointer global — anything that
  spells the global's name in the initializer expression.
* **A read reached through a call is not checked, and cannot be.** In
  `(defvar a:i32 (f))` where `f`'s body reads `b`, nothing in `a`'s initializer
  mentions `b`. Detecting it needs whole-program summaries of what every callee
  reads, which Nucleus does not do and does not plan to. Such a read silently
  gets the zero. If an initializer calls something that touches other globals,
  their `defvar`s must come first, and it is on you to arrange that.
* **`(addr-of g)` is not a read** and is never flagged, even when `g`'s `defvar`
  comes later. A global's address is a link-time constant that needs no
  initialization to have happened; the *value* is the thing that would be zero.
* **A cycle** — `a`'s initializer names `b` and `b`'s names `a` — is caught by
  the same rule, since whichever runs first names a global the other has not
  reached. Unlike a plain forward reference it cannot be fixed by reordering;
  one of the two dependencies has to go. A cycle laundered through calls is, as
  above, not detected: both globals simply read zeros.
* **The compiler does not compute an initialization order for you.** It reports
  and refuses; it never reorders. That is deliberate — a correct automatic order
  needs the same interprocedural analysis the second bullet rules out.

None of this affects what names *resolve*: an initializer naming a global
declared later still resolves to it, which is why the error above talks about
ordering rather than saying "undefined". See
[Resolution is order-free; initialization is not](#resolution-is-order-free-initialization-is-not).

### Cost, and targets that refuse

**A program with no run-time initializer emits nothing at all** for this
feature: no `@__nucleus_init`, no `llvm.global_ctors` entry, no extra symbol of
any kind. The whole mechanism is emitted at one point, and only when at least
one initializer was queued. This is a guarantee, not an optimization — it is
what makes the feature free on a microcontroller.

Because it rides `.init_array`, it also works where no Nucleus `main` exists at
all: a library compiled to a `.o` and exported through `--emit-nuch` (or
`--emit-cheader`) initializes its own globals when the final program starts,
even if `main` belongs to another translation unit and is written in C.

**On a target with no working startup-constructor mechanism a run-time
initializer is a compile-time error** naming the offending `defvar`. Today that
is **AVR**: LLVM emits `.init_array` there, but avr-libc's startup walks
`.ctors`, which the linker leaves empty — the constructor would be emitted,
linked, occupy RAM and never run. Refusing is deliberate; on such a target give
the global a constant initializer, or declare it without one and assign it
explicitly at the start of the program.

In the **REPL** there is no queue: each form is its own unit, so a `defvar` with
a run-time initializer is initialized immediately, as the form is entered — and
likewise for a global reached through `(import-use …)`.

## One symbol, one kind

A symbol may name only **one** kind of thing: a special form, a built-in type (`i32`, `ptr`, `double`, …), a struct type, a protocol, a macro, a function, or a value (`defvar`/`defconst`/`defenum` member/`extern`). Defining a name that already names a *different* kind is an error, e.g. `(defn double …)` clashes with the `double` type alias, and `(defstruct i32 …)` clashes with the built-in type. Same-kind reuse is still allowed: overloaded `defn` (multimethods) and REPL/`defstruct` redefinition. This keeps name resolution unambiguous across the language's namespaces.
