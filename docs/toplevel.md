# Top-Level Forms

| Name | Description | C Equivalent |
|------|-------------|--------------|
| `defn` | Define a function. **Signature.** The mandatory return type is written as its own operand after the parameter list (`(defn name (params):ret body…)`), matching the anonymous forms `fn`/`vfn`/`mfn`/`cfn`. A parenthesized return type is written space-separated or with the `:(…)` lone-colon fuse — `(defn name (params) (Maybe i32) …)` / `(defn name (params):(Maybe i32) …)`. Optional [declaration attributes](#declaration-attributes) (`:noreturn`, `:returns-twice`) follow the return type. `defprotocol` method signatures and `declare` use the same grammar. (The legacy return-in-the-name spelling `(defn name:ret (params) …)` was retired in Stage 14 and is now a hard error.) Supports `:rest` for variadic functions: `(defn name (a:t :rest xs:elem) ...)`. The rest parameter receives a list `Node` built at the call site, so **calling** a `:rest` function needs `(import-use nucleus.node)` in the caller's unit — the call emits `@nuc_node-list-new` and `@nuc_node-push`, which since Stage 16 the prelude no longer supplies (see [The node runtime is a library](#the-node-runtime-is-a-library)). The element type annotation is documentation only — non-`ptr` args are `inttoptr`'d into the element slot. `:rest` functions are not directly C-callable; calling through a function pointer requires manually constructing the rest list. `:rest` must be the second-to-last param. Supports `:optional` for trailing parameters with defaults: `(defn name (a:t :optional (b:t default) ...) ...)`. Each `:optional` param must be a 2-element list `(name:type default-expr)`. Defaults are evaluated at the call site in the caller's scope (Common Lisp semantics), so non-constant defaults like `(next-counter)` produce a fresh value per call. Implicit casts apply to defaults. The compiled function has fixed maximum arity at the LLVM/C ABI level — calling through a function pointer or from C requires supplying every argument including the optional ones. `:optional` cannot be combined with `:rest`. **Both describe a solitary name.** Overload dispatch matches on exact arity and on the *declared* parameter types, so an overloaded `:optional` method is reachable only when every optional argument is supplied, and an overloaded `:rest` method is not reachable at all (its rest slot is typed `ptr`, which no ordinary argument adapts to). **Calls are arity-checked** against the signature — exactly `num-params` for a plain `defn`, a band for `:optional`, a floor for `:rest` (see [Call arity](compiler.md#call-arity)). A struct-by-value parameter or return is lowered to the platform C ABI (see [Passing and returning structs by value](structs-unions.md#passing-and-returning-structs-by-value)). **Docstring**: if the first body form is a string literal AND there is at least one more form after it, that string is captured as the function's docstring (visible via `(doc fn)` and `(apropos)`); a function whose body is a single string literal is treated as returning the string, not as having a docstring. The same convention applies to `defmacro`. **Overloadable:** defining `defn` again with the same name but different parameter types adds a method — see [Polymorphism](generics.md#polymorphism-overloaded-defn-multimethods). | function definition |
| `defconst` | Define a compile-time constant `(defconst name[:T] value)`. The value is a **literal** (integer, float, string, character, `true`/`false`/`null`, or a folded integer expression) or a constant **aggregate** (`(S …)`, `(array T …)`, `&g`). A literal constant has no storage: each use is the literal, so an unannotated one types and adapts exactly as the literal would (`(defconst K 512)` makes `(<= ans:ui32 K)` legal exactly when `(<= ans:ui32 512)` is). An aggregate lives in read-only storage. An annotation fixes the type. Every write to a constant is a compile-time error, and a value that needs run-time work is refused. See [Constants](#constants). | `#define` / `static const` |
| `defenum` | Define an enumeration `(defenum Name member ...)` — a flat list of member names, each bound to its 0-based ordinal as an `i32` constant. A member is a named integer literal and adapts at a use site exactly as `defconst` does (`(= c:ui32 GREEN)` is as legal as `(= c:ui32 1)`). The enum's own name takes no type annotation. | `enum` |
| `defvar` | Define a global variable `(defvar name:type [init])`. **The initializer grammar has three tiers.** (1) A **compile-time constant** — a literal, a `defconst` / `defenum` name, a constant *expression* over them (arithmetic, bit operations, `(sizeof T)`, `(as T x)`), `&g`, and constant **aggregates**: an `(array T …)` literal and an `(S …)` struct literal, nested to any depth. These are baked into the emitted global, applied by the loader before any code runs, and cost nothing. (2) Anything else — a call, an allocation, a read of another global — is a **run-time initializer**: the slot is emitted zero-filled and the initializer runs at **startup, before `main`**, as an ordinary assignment, so `(defvar g:ptr:T (make-thing))` typechecks with `g` non-null. (3) **Refused:** a run-time initializer at an `(array T N)` slot, or inside a `compile-time` / `defmacro` body; a non-constant *element* of a constant aggregate; a scalar at an aggregate slot; and an initializer that syntactically names a global whose own `defvar` has not been reached yet (the error names both sites). See [Global initializers](#global-initializers) for the constant grammar and the arithmetic rules, and [Run-time initializers](#run-time-initializers) for the ordering rule and its diagnostic, the zero-cost-when-unused guarantee, and the targets (AVR) that refuse one. An integer initializer, literal, named or folded, that does not fit the declared type is a compile-time error rather than a silent truncation. Omitted inits default to zero / `null` / `false`; a global of **aggregate** type (struct, union, or `(array T N)`) with no init is zero-filled (`zeroinitializer`), so e.g. `(defvar g:MyStruct)` and `(defvar g:(array i32 256))` are valid. **An omitted init is refused for a non-null pointer** — `(defvar g:&T)` is an error, because the zero it would take is `null`; give it an initializer or declare it `?&T`. See [A non-null global must be initialized](#a-non-null-global-must-be-initialized). `set!` works on the result. The symbol is exported with default linkage and is visible to C consumers (`extern T name;` in the generated C header -- with an `asm("...")` label when the Nucleus name is not a C identifier; see [Reaching a library's globals from C](compiler.md#reaching-a-librarys-globals-from-c)) and other Nucleus modules (`(extern name:type)`). **Storage class specifiers:** file-scope `static` is the private definer `defvar-` (internal linkage); `register` is a no-op (LLVM ignores it); `thread_local` is reserved in the declaration-attribute slot (`:thread-local`) but not yet implemented — it errors with a targeted diagnostic pointing at the threading-stage blocker (`design/stage14/attributes.md` §5). Function-scope `static` locals and `:align`/`:section`/`:weak` are sketched but not implemented (same doc, §6). Function attributes ARE implemented (Stage 14 AVR-5) — but as the separate top-level `fn-attr` directive below, not as a keyword in this decl-attribute slot. A read-only global — C's `const` — is a [`defconst`](#constants); `(defvar :const …)` was retired and is an error naming it. | global variable definition |
| `defstruct` | Define a struct type, or a parametric struct template when the name is a list: `(defstruct (Name T ...) ...)`. A **bare** (non-template) name takes no type annotation — `(defstruct S:i32 (f i32))` is rejected (`defstruct: takes no type annotation; write (defstruct S ...)`); a genuine template head such as `(Vector T)` is unaffected. See [Parametric struct templates](structs-unions.md#parametric-struct-templates-defstruct-name-t-). | `struct` |
| `defunion` | Define a tagged sum `(defunion Name (arm field:type ...) ... bare-arm)` or a template `(defunion (Name T ...) ...)`. A **bare** (non-template) name takes no type annotation — `(defunion U:i32 (a x:i32) b)` is rejected (`defunion: takes no type annotation; write (defunion U ...)`); a genuine template head is unaffected. See [Unions and tagged sums](structs-unions.md#unions-and-tagged-sums). | tagged `struct {int tag; union {...} payload;}` |
| `deftype` | Define a **type alias**: `(deftype Name Type)` gives an existing type a second spelling. Not a new type — the alias and its body are the same type everywhere (same `type-eq`, same mangled name, one overload), and a program using aliases emits byte-identical IR to the spelled-out form. The body is any type expression and may name another alias; a forward reference works, since the body is re-parsed on use. The body is still checked at the `deftype`, so an unknown type in it is an error at its line whether or not the alias is used. The name may take type parameters — `(deftype (Vec T) (ref (Vector T)))` — which are substituted into the body at each application, including in a generic method's receiver. A name that already names a type is refused rather than silently ignored. Compile-time only; emits no code. See [Type aliases](types.md#type-aliases--deftype). | `typedef` (but never a new type) |
| `defprotocol` | Define a protocol: a named set of required method signatures (types may mention `Self` and extra element parameters). Compile-time only; emits no code. Each signature's types are checked at the `defprotocol`, as a `defn`'s are, so an unknown type is an error at its signature's line whether or not the protocol is ever extended. A **bare** (non-parametric) name takes no type annotation — `(defprotocol P:i32 ...)` is rejected (`defprotocol: takes no type annotation; write (defprotocol P ...)`); a genuine parametric head such as `(Seq E)` is unaffected. See [Protocols](generics.md#protocols-defprotocol-and-extend) and [Parametric protocols](generics.md#parametric-protocols). | — (concept: interface/trait) |
| `extend` | Assert conformance `(extend Type Protocol)` or parametric conformance `(extend (Name X) (Protocol X))`, where the subject's arguments are distinct type variables that the rest of the form names, and the template may sit under pointers or behind a parametric alias (`(extend &(Vector T) P)`, `(extend (Vec T) P)`): checks that each required signature resolves — a signature with its own `:where` by a method generic over it — then records the fact. Code-free. See [Protocols](generics.md#protocols-defprotocol-and-extend) and [Parametric protocols](generics.md#parametric-protocols). | — |
| `import` | **Prefix-qualified import** (the default, deliberate-API form). `(import lib [prefix])` exposes each public symbol of `lib` as `prefix/name`, pointing at the same definition (no new code; a foreign C symbol keeps its bare link name, so `c/printf` calls `@printf`). `lib` resolves `name.nuc` (source) or `name.nuch` (header) from source directory, `lib/`, `-I` paths, `$NUCLEUS_LIB`, or `/usr/local/share/nucleus/lib` (the install-time default used by `make install`); a string path imports a C header (`(import "stdio.h")`, preprocessed with `clang -E`) or an explicit `.nuc`/`.nuch` file by path. The prefix defaults to the lib's last dotted component (`foo.bar.baz` → `baz`); a string-path C header defaults to `c` (`(import "stdio.h" c)` → `c/printf`). The **same library** may be imported under **multiple** prefixes (aliasing); two different libraries **may not share** a prefix (error). Dedup is keyed on `(file, prefix)`. **A prefix binds only in the file that declares the import** — see [Import prefixes are file-scoped](#import-prefixes-are-file-scoped). Source imports inline all definitions; header imports emit `declare` (extern) for functions, and also bring in the header's object-like `#define`s whose bodies fold to integer constants, and its enumerators, under their C names — see [Integer constants from a C header](compiler.md#integer-constants-from-a-c-header). *(`import` and `import-prefixed` are synonyms.)* | — |
| `import-use` | **Flatten import** — brings **every** symbol of a library or C header into the current namespace under its bare name, including private symbols (the opt-out from the prefixing discipline). Good for the REPL and for libraries; discouraged for deliberate API design. `(import-use name)` / `(import-use "hdr.h")`. The prelude is auto-`import-use`d into every unit. | — |
| `import-ct` | **Compile-time-only import** — `(import-ct lib)` registers everything `import-use` would (types, signatures, constants, macros) and emits **none** of the library's definitions. For a library whose surface a macro body needs at compile time but whose code the program never calls: a macro body is JIT'd against the compiler process, so it resolves those symbols there. Reaching a withheld definition from program code is refused at the use — `'node-len' was imported compile-time-only` — rather than left to fail at link. Compile-time-only is a property of the **unit**, not of one import: if any ordinary import in the unit reaches the same library, it is imported normally and nothing is withheld, in either order. See [Compile-time-only imports](#compile-time-only-imports). | — |
| `import-prefixed` | Explicit spelling of the prefix-qualified `import` above: `(import-prefixed lib [prefix])`. Identical to `import`. | — |
| `import-only` | Import a concrete list of symbols: `(import-only lib sym1 sym2 ...)`. The listed symbols are brought in under their bare names. *(Currently flattens like `import-use`; the restriction to only the listed symbols is enforced once private/visibility filtering lands.)* | — |
| `unsafe-import-private` | **Retired in Stage 14** — bare `unsafe-import-private` is now a targeted hard error: `'unsafe-import-private' was split in Stage 14: use 'unsafe/import-private'`. | — |
| `unsafe/import-private` | Prefix-qualified import that also reaches a library's private (`defn-`/`defvar-`/etc.) symbols: `(unsafe/import-private lib prefix sym...)`. Discouraged; for breaking encapsulation deliberately. The listed symbols are advisory (not yet filtered) — every private symbol from the library is reachable under the prefix. This holds for a library with no `(ns …)`, whose private names are file-private, and for a namespaced one, where `p/name` reaches each private kind (`defn-`, `defvar-`, `defconst-`, `defenum-` and its members, `defstruct-`, `defunion-`, a private template, `deftype-`, `defmacro-`, `defprotocol-`). Only the prefixed spelling reaches them: the permission belongs to that one qualifier, never to a bare name. A `.nuch` header carries the form verbatim, so a template in the header that uses the prefix keeps its access. The access stays with the header's text; it does not pass to the file importing the header (see [The imports a header carries](compiler.md#the-imports-a-header-carries)). See [Special Forms](special-forms.md#special-forms). | — |
| `declare` | Declare an external function signature `(declare name (params...) :rettype)`. Used in `.nuch` header files and at the top level. **Parameters carry their types in both spellings.** A parameter may be written *named* — `(declare lseek (fd:i32 off:i64 whence:i32):i64)` — or *unnamed*, as its bare type — `(declare lseek (i32 i64 i32):i64)`; the two produce the same signature, and a list may mix them. In a declaration the name is documentation only (nothing binds it), so an unnamed parameter is a **type operand**: any type spelling works there, including a keyword (`:i64`), a compound (`(Vector i32)`), and a struct name (passed by value under the platform C ABI). A written list is a type when its head is a type constructor (`ptr`, `ref`, `array`, `fn`, `struct`, `union`, `dyn`, `BoxedFn`, `Maybe`, a `?`/`!` sigil, a template or a parametric alias), so `((ptr i8))` is a pointer parameter; any other list is a `(name type)` cell. A spelling that names no type is a compile-time error — there is no default. **An element carrying a `name:type` annotation is a named parameter**, exactly as in a `defn`, so `(declare f (ptr:FILE):void)` declares a parameter *named* `ptr` of type `FILE` (by value), not a pointer to `FILE` — write `p:ptr:FILE`, or a bare `ptr`, for a pointer parameter. `:rest` / `:optional` are `defn`-only and are rejected here; a C variadic function needs no marker, because **a declared signature is open-tailed** — [call arity](compiler.md#call-arity) requires the declared (fixed) parameters and admits any number of extra arguments after them, so the variadic tail simply rides the call site. Too *few* arguments is still an error. Importing the function's C header is the precise route: the header carries a real variadic flag, so the fixed prefix is checked exactly. A declaration of a name that is already declared is a no-op — a diamond import, a top-level `declare` used as a [cycle-breaker](#cross-file-resolution-reachability-not-import-order), or one libc function named by both a C header and a `.nuch`; but a **`.nuch`** entry for a name the importing unit *defines* is a conflict, not a re-declaration, and is reported. A `declare` may carry the same [declaration attributes](#declaration-attributes) a `defn` does, written after the return type: `(declare my_abort ():void :noreturn)`. See also [Declaration precedence](structs-unions.md#declaration-precedence-an-explicit-declare-wins). | function prototype |
| `extern` | Declare a foreign global variable `(extern name:type)`. The compiler emits `@name = external global T`, leaving storage and initialization to the linker. Works for both C-defined and Nucleus-defined producers; the matching `defvar` may live in another `.o` file. | `extern` declaration |
| `defmacro` | Define a compile-time macro `(defmacro name (params...) body...)`. The name takes **no** type annotation — `(defmacro m:i32 (x) x)` is rejected (`defmacro: takes no type annotation; write (defmacro m ...)`) rather than silently compiling and failing at the call site. Supports `:rest` for variadic macros: `(defmacro name (a b :rest rest) ...)` — `rest` receives a list `Node` holding the remaining args — the empty list `()`, never null, when there are none. Parameters (and the `:rest` list) are typed `&Node` inside the body — never null — so `(p 'kind)` and `(p 's)` read fields directly with no cast — the selector is quoted, a bare symbol there being an ordinary variable. Elements come out through the `ast-first` / `ast-rest` / `ast-at` / `ast-len` special forms, which a macro body must use in place of the `node-*` functions (see [A form is a collection](macros.md#a-form-is-a-collection)). The macro can splice a parameter into a quasiquote regardless of the value type the user-supplied expression evaluates to at the call site — see [Macros and pass-through arguments](macros.md#macros-and-pass-through-arguments). | macro |
| *a macro call* | A top-level form whose head names none of the forms in this table, but does name a `defmacro`, **expands** — and its expansion is dispatched as a top-level form in turn. An expansion to `(do …)` splices, so one call can define several things. Because the built-in forms are matched first, a macro can never change what `defn` means; because expansion happens during the dispatch loop rather than in a pre-scan, the macro must be defined earlier in file order and what it defines is not forward-referenceable. See [Macros in top-level position](macros.md#macros-in-top-level-position). | — |
| `defcast` | Register an implicit conversion `(defcast From To conv-fn)`. `conv-fn` must be a unary function with signature `To (From)` already in scope; the compiler emits a call to it wherever a value of `From` reaches a slot expecting `To` — **every** implicit position, not only arguments: `let`/`with` init, explicit and implicit `return`, every `set!` place, struct-literal fields, union payloads and `as` all consult the rule. Pairs already covered by built-in coercion (identity, int↔int, `f32`→`f64`) are rejected at registration, so built-in conversion always wins. Rules are unidirectional and non-transitive, and they **do not compose with built-in coercion** either — a rule is matched on the exact pair, so an `i64 → ptr` rule is not reached by the `i32` literal in `(take 0)` (write `(take (as i64 0))`, or register from `i32`). A failure that a rule *almost* covers says so in a note. Exported in `.nuch` headers. See [implicit-conversions.md](../design/stage15-stress-test/implicit-conversions.md). | implicit conversion |
| `def-rmacro` | Define a reader macro `(def-rmacro "prefix" symbol)`. When `prefix` appears at the start of a token, the reader wraps the next form: `(symbol form)`. The reader registers the macro **as it reads it**, so it takes effect only for the forms after it — in its own file (a different file never sees it; a REPL session keeps one table across prompts, so a `def-rmacro` at one prompt is visible at the next). Refused if `prefix` is already registered, or begins with a byte that can start an atom — a prefix may open only with one of `` $ ' , @ ^ ` \| ~ ``. Built-in reader macros: `'` (quote), `` ` `` (quasiquote), `~` (unquote), `~@` (unquote-splice), `@` (deref), `&` (ref). See [Reading s-expressions](reading.md#def-rmacro). | — |
| `exclude-prelude` | Suppress the implicit `(import-use nucleus.core)` for this source file. Must be the first top-level form; takes no arguments. Use when a file should compile against the bare language without the standard macros, `Node` struct, or `(import-use "string.h")` declarations. The directive applies to the **compilation unit's entry file only** — the prelude is a property of the unit, not of a file — so a copy of it in a file that is *imported* is ignored rather than being an error. | — |
| `ns` | Set the current namespace for this source file: `(ns name)`. `name` must be a slash-free symbol. Symbols defined after this form are stored under `namespace/name` qualified keys. A second `ns` in the same file warns at compile time (silent in the REPL). The default namespace is `user`, which stores bare keys — byte-identical to pre-namespace behavior. Conventionally the first form in a file. **Everything defined after `(ns …)` is namespaced**: functions, values, protocols and **types** alike — a `defstruct`/`defunion`/`defenum`/template declared in `(ns shapes)` defines `shapes/Circle`, exactly as a `defn` there defines `shapes/area` (see [Protocols are namespaced](generics.md#protocols-are-namespaced) and [Namespaced type names](types.md#namespaced-type-names)). Two namespaces may each declare a type of the same name — they are two distinct types — and a reference to either, bare or qualified, resolves through the writing file's own import environment exactly like any other name; see [What an import brings into scope](#what-an-import-brings-into-scope). | — (concept: C++ `namespace` / Clojure `ns`) |
| `set-ir-prefix` | Override the IR-mangling prefix for the current namespace: `(set-ir-prefix "prefix")`. An empty string forces bare IR names regardless of the namespace (C-ABI escape hatch). A non-empty string replaces the namespace name in emitted IR identifiers. Applies to symbols defined after this directive. Typically placed immediately after `ns`. A prefix of `nuc` or one beginning `nuc_` is refused: that space belongs to the [core libraries](#the-core-libraries-nucleus). | — |
| `export` | Re-export symbols from this namespace: `(export sym1 sym2 ...)`. Makes the listed symbols visible to importers of this namespace under their unqualified names (the part after the last `/`). Typically used in facade libraries to re-expose imported symbols without the importer needing to know the original source namespace. The symbols must already be in scope (via `import-prefixed` or defined in this file). No new IR is emitted — it adds alias entries to the module's export table. Example: `(export geom/area geom/perimeter)` in a `gfacade` namespace causes `(import-prefixed gfacade g)` to expose `g/area` and `g/perimeter` to the importer. The facade's `.nuch` header carries the `export` form along with the import forms it names through. Those imports load nothing, so a consumer of the header must also import `nsgeom`; otherwise the export is refused at the header's line with a note saying so (see [The imports a header carries](compiler.md#the-imports-a-header-carries)). **Functions, values, protocols, structs, unions, enums, templates and macros can be re-exported.** Types are on this list because type identity is namespaced (see [Namespaced type names](types.md#namespaced-type-names)): a facade that re-exports `geom/area` but not `geom/Pt` would export a function whose signature names a type the consumer has no way to spell. **An overloaded function, a special form, or a built-in type name cannot** — none of them is keyed by namespace, so a re-export would not change how it resolves. An overloaded name is the deliberate case: one entry per bare name carries every namespace's methods (see [Qualifying an overloaded function](#qualifying-an-overloaded-function)), so it is already reachable everywhere. Naming one is refused with `export: 'X' is a function — that kind is not keyed by namespace, so a re-export would not change how it resolves` (the noun changes with the kind: "a special form", "a built-in type"). | — (closest C analogue: a header that `extern`-declares symbols from another translation unit) |
| `fn-attr` | Attach one or more LLVM string function attributes to a `defn`: `(fn-attr name "attr" ...)`. `name` is a bare function-name symbol (not a string) matched against the target `defn`'s source name (equal to the emitted `@`-symbol in the default `user` namespace); each remaining argument must be a string literal. Attributes accumulate — several strings in one call, or several `fn-attr` calls naming the same function, all apply — and are stored/emitted verbatim (Nucleus does not validate the string; an unrecognized attribute is an LLVM-level error, not a compiler diagnostic). Emitted as a space-prefixed quoted attribute directly on that function's `define` line (e.g. `define void @tick() "signal" {`), coexisting with `noreturn`/`returns_twice` when both apply (see [Declaration attributes](#declaration-attributes)). **The `fn-attr` directive must appear before the `defn` it targets** — there is no forward-reference prescan for the attribute table (the same order-sensitive-directive pattern as `set-ir-prefix`, above, which likewise takes effect only for what follows it in source order). Deliberately generic: the first consumer is AVR interrupt handlers (the `"signal"`/`"interrupt"` attributes make the AVR backend emit the interrupt prologue/epilogue and `reti` instead of `ret`; see the block comment in `lib/nucleus/avr.nuc` and `examples/avr-isr.nuc`), but any LLVM function-attribute string works the same way. A unit that never calls `fn-attr` is byte-identical to before this directive existed. | — (closest C analogue: `__attribute__((...))` on a function declaration) |
| Private definers: `defn-` `defvar-` `defconst-` `defenum-` `defstruct-` `defunion-` `defmacro-` `defprotocol-` `deftype-` | The `-` suffix marks a definition as private. **In a file with no `(ns …)`, a `defn-`, `defvar-`, `defconst-` or `defenum-` name is private to that file** (see [Private names are file-scoped](#private-names-are-file-scoped) below); in a file that declares a namespace, every private name is private to that namespace. Private symbols are not placed in the module's export table and cannot be imported by other namespaces. For link-emitting forms (`defn-`, `defvar-`), the LLVM symbol also receives internal linkage (`define internal` / `internal global`), preventing link-time name collisions with other translation units — equivalent to C `static`. For compile-time-only forms (`defconst-`, `defenum-`, `defstruct-`, `defunion-`, `defmacro-`, `defprotocol-`, `deftype-`), there is no linkage dimension; private means the name is invisible to importers. All other semantics (type checking, overloading, parametric templates, protocol conformance) are identical to the public form: a `defn-` template is called in its own file as a public one is, and two files' private templates of one name stamp separately. | `static` function / `static` global (for `defn-` / `defvar-`); — for compile-time-only forms |

## Declaration attributes

A `defn` or a `declare` may carry attribute keywords after its return type. They
are written in either order, and both go on the same function if both apply:

```lisp
(defn spin (m:CStr):void :noreturn
  (while true (printf "%s\n" m)))

(defn my-setjmp (b:ptr):i32 :returns-twice
  …)

(declare my_abort ():void :noreturn)
(declare my_sj (b:ptr):i32 :returns-twice)
```

| Attribute | Meaning |
|---|---|
| `:noreturn` | Control never leaves the function. Emitted as LLVM's `noreturn`, and a statement-position call to it **terminates its block**, so a `(when (= x null) (bail))` guard narrows the tested binding past it. |
| `:returns-twice` | The function may return more than once — the `setjmp` family. Emitted as LLVM's `returns_twice`, which stops the optimizer tail-calling it and reusing the frame the later `longjmp` has to return into. It has no Nucleus-level consequence; a local that must survive the jump still needs [`:volatile`](types.md#volatile-qualifier). |

Both are properties of the *signature*, so they ride an exported `.nuch` entry
and are re-applied to the `declare` an importing unit emits. They are also
recognized by name on a handful of libc functions arriving through a C header —
see [Recognized libc function attributes](structs-unions.md#recognized-libc-function-attributes-noreturn-and-returns_twice).

A **lone** trailing form is always the body, never an attribute, so
`(defn kw ():Keyword :noreturn)` is a function returning the keyword
`:noreturn`.

The bare-symbol spellings `noreturn` and `returns_twice` that predated the
keyword form are retired; each is a located error naming its replacement.

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
* **Another file's private value is refused by name.** A call to `helper` from
  `main.nuc` above is `unknown: helper — private to a.nuc`, with a note that
  only `unsafe/import-private` reaches it.
* **Public names are still unique across the whole unit.** Two files defining
  the same public name and parameter types is an error, and the diagnostic names
  both files.
* **In a file that declares `(ns …)`, privacy is per *namespace*, not per file** —
  `defn-` there means "private to this namespace", which is a real, chosen scope.
  Two files sharing one `(ns …)` therefore still collide on a private name, and
  the diagnostic says so. Give one file its own namespace, or rename.
* **Only four of the nine definers get file scope. The other five are always
  namespace-scoped.** `defn-`, `defvar-`, `defconst-` and `defenum-` name
  *values*, whose registry key can carry a synthetic per-file namespace, so in a
  file with no `(ns …)` they are private to that file. `defstruct-`,
  `defunion-`, `defmacro-`, `defprotocol-` and `deftype-` name *types, macros and
  protocols*, which have no per-file key space — `(ns …)` is what makes their
  privacy mean anything — so in the default `user` namespace they are visible
  to the whole unit, and a file that declares `(ns …)` is what actually hides
  them. Reaching one from outside its namespace is an error at the reference.
  A spelling that reaches the entry says so: `unknown type: p/Name — private to
  namespace 'n'`, and `unknown: p/name` / `undefined: p/name` with the same
  tail for a function, macro or value (a bare name through `import-use` alike).
  A protocol reports `extend: unknown protocol 'Name'`. The rule covers a namespaced
  `defn-` too, solitary or overloaded: neither a prefixed nor a flattened import
  reaches it. **For a type**, since type
  identity is namespaced (see
  [Namespaced type names](types.md#namespaced-type-names)), that failure comes
  in two tiers rather than one: a *bare* reference to a private type in another
  namespace fails for the ordinary scope reason first — the same message a
  *public* type in an unimported namespace gets, since the bare spelling was
  never in scope to begin with — and only a *qualified* reference spelled
  through a prefix that actually reaches the namespace gets as far as finding
  the (hidden) entry, where privacy then refuses it, using the qualified
  spelling. A macro behaves the same way as of the macro
  cut-over: a bare reference to a private macro in another namespace fails for
  the ordinary scope reason, and only a prefixed spelling reaches the privacy
  check.
* Privacy affects only the *name*. The emitted symbol still exists (with internal
  linkage); it is simply spelled per-file, so nothing outside the file can name
  it and nothing collides at link time. A private definition that reaches another
  file by *identity* rather than by spelling therefore still works there. A
  `defstruct-` type handed to another namespace's template stamps it (`(k/Box Foo)`,
  `(k/sz &f)`). A private conformer's method answers a library generic's call to
  the protocol method. A private template behind a public alias expands wherever
  the alias is used.
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
* A **namespace** qualifier is not a prefix: it reaches every file whose
  imports, followed transitively, load the library that declares it — see the
  next section. A prefix is never reachable that way.

## What an import brings into scope

**A prefix means something only in the file whose own import form bound it; a
namespace's full name means something in every file whose import closure loads
it.** A file's *import closure* is the file plus every file its import forms
reach, transitively (cycles included). A qualifier resolves, in order, as the
file's own namespace, `user`, `unsafe`, a prefix this file bound, a namespace
this file flattened, and last a namespace any file in the closure declares — so
a prefix shadows a namespace of the same name, silently.

| Import form | What the file can spell |
|---|---|
| `(import-prefixed lib p)` / `(import lib p)` | `p/name`, and (through the closure) `<lib-namespace>/name` |
| `(import-use lib)` | `name` (unqualified) **and** `<lib-namespace>/name` |
| `(require lib)` | nothing new unqualified: the library is loaded as `import-use` loads it, and `<lib-namespace>/name` — plus every namespace `lib` itself loads — is reachable by full name |
| `(require-ct lib)` | as `require`, compile-time-only like `import-ct` (below) |
| `(require "x.h")` | refused — a C header has no namespace to require |
| `(import-only lib a b)` | as `import-use` today; the filter is not yet built |
| `(import-ct lib)` | as `import-use` — the *names* are identical; what differs is that the definitions behind them are not emitted |
| implicit prelude | as `import-use nucleus.core` and `import-use nucleus.macros`, after the file's own import forms — so every bare prelude name is always in scope |
| the file's own `(ns n)` | `name` and `n/name` |
| implicit `unsafe` | as `import-prefixed` — `unsafe/cast`, `unsafe/ptr+`, `unsafe/funcall-ptr-*`, `unsafe/import-private`, and **nothing unqualified** |

Full-name reach follows the closure, not the unit: a library that spells
`edn/x` must load `edn` itself (an `import` or a `require`), or it compiles in
one program and fails in another. Leaning on a namespace that a library loads
only as an implementation detail is allowed and is the user's risk. Privacy is
unchanged — a full name reaches public names only, unless it is the file's own
namespace. (Stage 23 reversed the earlier rule that a namespace was reachable
only through an import form that bound it;
design/stage23-namespaces/ambient-namespaces.md.)

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
(extend Circle shapes/Shape)    ; ok — the same protocol, by its full name
(extend Circle shapez/Shape)    ; error — no file in the closure declares shapez
```

```
main.nuc:7: error: extend: unknown protocol 'shapez/Shape'
  note: 'shapez' is neither an import prefix this file binds nor a namespace its
  imports load — (require …) a library to reach its namespace by its full name.
  In scope here: sh.
```

When some *other* file of the unit declares the namespace, the note names it
instead: `namespace 'shapez' (declared in lib/shapez.nuc) is not loaded by this
file's imports — add (require …) naming its library to reach it by its full name.`

### Library names: dots are directories

A dotted library name in any import form names a subdirectory of a search root:
`(require nucleus.edn)` finds `<root>/nucleus/edn.nuc` (or `.nuch`) on the same
search path a bare name uses. Hyphens are kept as written. The default prefix of
`(import a.b)` is the last component, `b`. A string-path import is a path and is
unchanged.

**Scope of the rule today.** It governs **protocol** references (`extend`,
`(dyn P)`, `:where` constraints, protocol inheritance), every **global** —
functions, `defvar`s, `defconst`s, enum members, `extern`s and `declare`d C
functions — and every **type** — struct, union, enum and template names alike.
`anything/Circle` no longer resolves the way it used to: a type reference needs
its qualifier in scope in exactly the way a global or protocol reference does.
**Overloaded** functions are on this path too, by a different mechanism — see
[Qualifying an overloaded function](#qualifying-an-overloaded-function) below.
**Macros** are on it as well: `p/my-macro` resolves through an import prefix
and `ns/my-macro` through the closure, and two namespaces may each declare a
macro of the same name. The names *inside* a macro's quasiquote are resolved in the
macro's own file and written as full names, which the caller reaches through the
macro's library in its closure; so the caller needs to reach only the macro (see
[A template's names mean the macro file's names](macros.md#a-templates-names-mean-the-macro-files-names)).
Every name-keyed kind now answers the same scope question.

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
  `otherns/thing` requires a prefix this file bound or a namespace this file's
  import closure loads — the unit alone is not enough. This applies to
  `otherns/Circle` exactly as to `otherns/some-fn`.
* **A bare type reference to a type defined in a namespace this file did not
  import** gets a located diagnostic naming the defining namespace, plus a
  note offering the spelling this file can actually write when it has bound
  some prefix that reaches that namespace — see
  [Namespaced type names](types.md#namespaced-type-names) for the exact
  message. The same tier fires in head position too, so a bare struct
  constructor for a type in an unimported namespace gets the same answer.

### The core libraries: `nucleus.*`

The standard libraries live in `lib/nucleus/` and each declares its namespace:
`lib/nucleus/string.nuc` is `(ns nucleus.string)`, imported as
`(import-use nucleus.string)`; the AVR support is `nucleus.avr` and
`nucleus.avr.attiny1634` etc. The prelude is `nucleus.core`
(`lib/nucleus/core.nuc`), flattened into every file with `nucleus.macros` as if
each file ended its import forms with `(import-use nucleus.core)`;
`(exclude-prelude)` still removes it. A file that uses a library's names imports
that library — another file of the unit loading it is not enough.

**Lookup order.** A bare name is looked up in the file's own namespace, then
each namespace the file flattened (its `import-use`s, then the prelude), then
`user`. So inside a namespaced library a `user` definition never shadows a core
one, while in a `user` file the file's own definitions come first.

**Core link names carry `nuc_`.** Every `nucleus.*` namespace links under the one
reserved prefix `nuc_`, joined with no separator: `string-push-char` links as
`@nuc_string-push-char`, `String` is `%nuc_String`, and the C names in
`lib/nucleus/*.h` are `nuc_string_push_char` and `struct nuc_String`. A program's own
names stay bare, so a `user` type, function or global named like a core one is a
different symbol and coexists with it. `main` always links as `main`, whatever
namespace defines it, and a hand-written `extern` keeps the foreign symbol's own
name.

**`nuc_` is reserved.** A definition outside the core libraries whose link name
would begin with `nuc_` is refused where it is written, and so is an `ns` or
`set-ir-prefix` whose prefix composes such names:

```
main.nuc:1: error: defn 'nuc_foo' links as @nuc_foo, and the nuc_ prefix is reserved for the core libraries — rename it
main.nuc:1: error: ns: link prefix 'nuc_x' is reserved for the core libraries
```

A private definer (`defn-`, `defvar-`) links under its file's own prefix and
reserves nothing. Externs and C-header declarations are exempt: a foreign
library may own such names.

**What the compiler writes for you names the library too.** A collection or
keyword literal lowers to calls into its library by full name, so the file must
load that library:

```
main.nuc:3: error: a vector literal needs nucleus.vector — add (import-use nucleus.vector)
```

(`#{…}` needs `nucleus.hashset`, `{…}` `nucleus.hashmap`, `:kw` `nucleus.keyword`.)
The types and protocols the compiler itself reasons about — `StrView` for a
string literal, `Node` in a macro, `Drop`, `Clone`, `Maybe`, `Result`, `Err`'s
handler chain — are the core library's by key, whatever the file names them.

**An operator method the file cannot reach is refused, not replaced.** `=` on
two `StrView`s is a method in `nucleus.strview`. Where some file of the unit
loads it but this file does not import it, the comparison is refused with a note
naming the namespace, rather than falling to the built-in, which compares a
view's bytes only up to a NUL.

### A template is read as the file that wrote it

A generic `defn`, a parametric `defstruct` or `defunion`, and every instance
stamped from them are the defining file's text. So are a `deftype` alias's body
and a `defprotocol`'s method signatures. Every name in them — the signature, the
`:where` constraints, the fields and arms, the body, what the alias stands for —
therefore resolves through **that** file's namespace and imports, wherever the
instance is requested or the alias or protocol is used. A library may name its own types unqualified in a template and still
be stamped from a prefixed importer:

```lisp
; lib/shapes.nuc
(ns shapes)
(defstruct Pt x:i32 y:i32)
(defstruct (Box T) v:T at:&Pt)
(defn nudge (x:T p:&Pt :where (Any T)):i32 (return (p 'x)))

; consumer, which has a Pt of its own
(import shapes sh)
(defstruct Pt a:i64 b:i64 c:i64)
(defn main ():i32
  (let (p:sh/Pt (sh/Pt 1 2)
        mine:Pt (Pt 7 8 9)
        b:(sh/Box Pt) ((sh/Box Pt) mine &p))  ; v: the consumer's Pt, at: shapes/Pt
    (return (sh/nudge 3 &p))))
```

The type *arguments* are the caller's and stay the caller's: `(sh/Box Pt)` holds
the consumer's three-field `Pt`, although `shapes` has a `Pt` of its own. An
argument may be a type the template's file cannot spell at all — the consumer's
private `defstruct-` — and still stamps, since the instance carries the type
itself rather than a spelling for `shapes` to look up. A call
that does not fit — `(sh/nudge 3 &mine)` — is refused at the call's line with
`no matching method …`. A mistake in the template's own text is reported at the
template's file and line; when it surfaces while a call is being bound or the
instance stamped, a `while binding a call to …` / `while instantiating …` /
`while stamping …` note names the call that asked for it. The same holds through a `.nuch` header, which carries the import forms
its text is read through — see [.nuch Header Format](compiler.md#nuch-header-format).

An alias or protocol works the same way. With `(deftype (Two T) (struct a:T b:&Pt))`
and `(defprotocol Probe (probe (x:&Self q:&Pt):i32))` in `shapes`, the
consumer's `(sh/Two Pt)` has an `a` that is the consumer's `Pt` and a `b` that
points at `shapes/Pt`. `(extend Foo sh/Probe)` asks for a `probe` taking
`&Foo` and `&shapes/Pt`. `Self` and the protocol's type arguments are the
extending file's, and so are the methods that answer. A private `defstruct-` conformer, or one that shares a name
with a type of the protocol's library, is found. A generic in `shapes` that calls
`(probe x q)` under `:where (Probe T)` reaches the conformer's `probe` in the
extending file's namespace, solitary, overloaded or `defn-`, although `shapes`
imports nothing of it: dispatch finds a conformance wherever it is defined. A
method that answers no protocol the calling file can name gets no such pass.
An alias applied in a generic method's receiver pattern (`(defn f (b:&(sh/PBox
T)) …)`) is matched, not parsed, and its body still names `shapes`' types: the
consumer's own `Box` does not capture `PBox`'s. A mistake in the body or
signature is reported at the defining file's line. A source library's is found
at the definition; a header's is trusted until a use reads it, and then carries a
`while reading type alias 'shapes/Two'` or `while reading protocol
'shapes/Probe'` note naming that use.

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
(na/desc 1)      ; 101 — liba's own namespace, through the import closure
(nz/desc 1)      ; error: 'nz' is not in scope in this file
```

The third line is the point: the qualifier really does restrict the method set,
so an overload another namespace contributed is not reachable through `pa/`.
The fourth filters by the namespace's full name exactly as `pa/` does; the fifth
is the ordinary scope rule — no file this one loads declares `nz`.

The registry is merged, but **the merge is not what a bare call sees**. A bare
name is filtered too, by the same rule every other kind of name obeys: it
reaches the namespaces this file can name *without* a qualifier — its own, each
one it flattened with `import-use`/`import-only`, and `user`. A prefixed import
binds its library under the prefix and under nothing else, for an overloaded
function exactly as for a type or a global.

So in the example above `(pa/desc 1)` works and a bare `(desc 1)` does not
resolve at all:

```
c.nuc:9: error: unknown: desc — defined in namespaces 'na' and 'nb'
  note: write 'pa/desc' or 'pb/desc' here
```

This matters most when the importing file has a definition of its own. A file
defining `helper (x:i64)` and calling `(helper 3)` calls **its own** function;
adding `(import-prefixed somelib w)`, where `somelib` also exports
`helper (x:i32)`, does not change that. Before this rule the library's method
joined the same bare set, scored better on the untyped literal, and the
unchanged call silently became a call to a function reached through a prefix it
never spelled.

Two further consequences, both deliberate:

* **`import-use` really does merge.** Flattening a namespace puts its overloads
  in the unqualified space on purpose — that is what makes two libraries'
  `describe` methods usable together, and it is the escape hatch to reach for
  when you want the merged multimethod rather than the qualified one.
* **Two namespaces may each define one name with the same parameter types.**
  They are two functions and two symbols (`@na__desc`, `@nb__desc`), so the
  definitions are fine; what cannot be answered is a *bare call* that sees both,
  and that is where the error is reported:

  ```
  c.nuc:3: error: ambiguous call to 'desc' — two namespaces define it for these argument types
    note: 'na/desc' (defined at liba.nuc:2) and 'nb/desc' (defined at libb.nuc:2)
    both match; qualify the call to choose one
  ```

  Flatten only one of them and there is nothing to report. Within **one**
  namespace two identical signatures are still an error at the definition — that
  pair really would emit one symbol twice, and it is the function row of the
  redefinition rule below.

Bounded-generic templates (`:where`) and their stamped instances follow the
same rule: a stamp belongs to the namespace that declared the template, not to
the file that triggered it. So does the template's **body** — the names in it
are resolved in the library's import environment, not in the environment of
whichever file instantiated it, so a template may freely call anything its own
file can see.

### One definition per name

A name may be defined **once** in a compilation unit. A second `defstruct`,
`defunion`, `defprotocol`, `defmacro`, `defenum`, `defvar`, `defconst`, enum
member or `defstruct`/`defunion` template of the same name is an error that
names both definitions. The value definers share one name space, so a `defvar`
and a `defconst` of one name collide in either order:

```
b.nuc:1: error: redefinition of 'Node' — it already names a type defined at a.nuc:13
  note: a name may be defined only once in a compilation unit. If two imported
  libraries both define it, rename one — or give one an (ns ...) of its own and
  import that library with `import-prefixed`.
```

For a **function** the rule is about the signature rather than the name, and it
is scoped to one namespace: two `defn`s of one name are overloads, and two
overloads with the *same* parameter types collide only when they would emit the
same symbol — that is, when they are in the same namespace, or in two namespaces
that `set-ir-prefix` to the same string (`duplicate definition of 'f' — the same
parameter types are already defined at …`). Two *different* namespaces may each
define `f (x:i32)`; see [Qualifying an overloaded
function](#qualifying-an-overloaded-function) for where that pair is reported
instead.

**Two definitions may not share a link name either.** Distinct names can still
compose one symbol — `foo?` and `foo_QMARK` both link as `@foo_QMARK`, and two
namespaces that `set-ir-prefix` to the same string share one symbol space — so
each `defn`, `defvar` and type claims its link name, and a second holder is
refused at its own line, naming the first:

```
main.nuc:2: error: 'foo_QMARK' links as @foo_QMARK, the symbol of 'foo?' at main.nuc:1 — rename one, or give one file an (ns …)
```

**A `defn` of a name a C header or a `declare` also binds is either the
implementation of that C function or an overload beside it.** It is the
implementation when it is a plain user-namespace `defn` that writes the C
parameter and return types (only a bare `ptr` writes `void *`). Then it takes
the C symbol: `(defn puts (s:CStr):int …)` is the program's `@puts`. Otherwise
the C function joins the generic as one more overload and keeps its symbol, and
the `defn` is mangled like any overload. So a struct can have a `free`, `realloc`
or `remove` method without displacing libc's, in the user's files and in
namespaced libraries alike:

```
(import-use "stdlib.h")
(defstruct Box n:i32)
(defn free (self:&Box):void (set! (self 'n) 0))   ; Box's free
(defn main ():i32
  (let (b:Box (Box 5))
    (free &b)                ; Box's free
    (free (malloc 16))       ; libc free
    (return (b 'n))))
```

A call that only one `defn` can take by arity is checked and converted the way a
call to a lone function is. Among same-arity candidates the usual overload tiers
pick, and the C function takes whatever no `defn` claimed, with C's argument
conversions.

The REPL has no overloads, so there a `defn` of a C function's name is still its
implementation and must match its LLVM signature:

```
main.nuc:2: error: 'puts' links as @puts, which /usr/include/stdio.h:714 declares as i32 (ptr), not i64 (i64) — match that declaration, or rename it
```

The same refusal applies when a C header is imported after a `defn` of the name
has already been emitted.

Notes on what this does and does not cover:

* **It is a per-unit rule, so importing one file through several paths stays
  legal.** The diamond every non-trivial program has — two libraries that both
  import a third — is not a redefinition; the file is processed once.
* **Giving one definition a namespace is the fix for a genuine clash**, and the
  diagnostic says so: `(ns …)` in one library plus `import-prefixed` in the
  consumer keeps both names alive under different qualifiers.
* **The REPL is exempt.** An interactive session is a sequence of units typed
  one at a time, and redefining a name is the point of it.
* **Defining the same value twice is still a redefinition.** Two files that
  each write `(defconst SEEK_SET 0)` collide, and the equal value is not an
  exemption: the rule exists so that no name's meaning is decided by import
  order, and a compiler that let equal values through would be deciding which
  collisions matter. A constant two files both need belongs in one of them (or
  in a third), reached by `import` — which, per [Cross-file
  resolution](#cross-file-resolution-reachability-not-import-order), works from
  anywhere in the unit.

## The node runtime is a library

`lib/nucleus/core.nuc` is auto-imported into every unit, and until Stage 16 it ended
with `(import-use nucleus.node)` — so every program, including one that never wrote a
quote, carried `alloc-node`, the list builders, `intern-symbol`, the symbol
intern table and the arena behind them: sixteen definitions and 4.5 KB of `.text` for a
`main` that reaches none of it. On a freestanding target it was worse than
wasteful; the arena calls `malloc`/`perror`, which avr-libc does not have, so the
only way to build for AVR was `(exclude-prelude)` — giving up `if`, `when`,
`unless`, `->` and the variadic operators as well.

The prelude now holds only forms that emit no IR: the `Node`, `StrView` and
`Symbol` **types**, the `NODE-*` enum, the standard macros, `Clone`, and the
`Result` / `Maybe` templates. The runtime is `lib/nucleus/node.nuc`, imported like any
other library. A prelude-only program emits **one** definition, its own `main`.

`Node.s` is a [`Symbol`](stdlib.md#symbol-libinternnuc-stage-17) — one word pointing at interned
bytes. `lib/nucleus/node.nuc` keeps the canonical-`Node`-per-spelling map on top of it:
`intern-node` takes the `Symbol`, `intern-symbol` is the `CStr` wrapper `'foo`
lowers to. `lib/nucleus/intern.nuc` owns the byte table itself and imports nothing but
libc and `lib/nucleus/fnv.nuc`, so a macro-using program does not drag the string stack
— and, on AVR, does not become uncompilable for it.

Three things lower to calls on that runtime, so a program using any of them needs
`(import-use nucleus.node)`:

| Written | Lowers to |
|---|---|
| `'sym`, `'(a b)`, `` `(…) `` in ordinary code | `@nuc_intern-symbol` / `@nuc_node-list-new` + `@nuc_node-push` / `@nuc_alloc-node` |
| a call to a `:rest` function | `@nuc_node-list-new`, then `@nuc_node-push` per trailing argument |
| a literal selector reaching a user `get` method | `@intern-symbol` |

Each is refused by name — `quote needs the node runtime — add (import-use nucleus.node)`
— rather than left to fail at link with no location. A **macro body** needs no
import: it is compiled into its own JIT module and resolves those symbols against
the compiler process, which is why defining a macro costs a program nothing.

## Compile-time-only imports

`(import-ct lib)` registers a library's compile-time surface — types,
signatures, constants, macros — and emits none of its definitions.

The case it exists for is a macro that calls a library function to build its
expansion. `lib/nucleus/error.nuc`'s `with-handler` destructures its spec with `node-at`;
that is a compile-time call, made by a JIT'd macro body against the compiler
process, but writing `(import-use nucleus.node)` to get the signature would have emitted
the whole node runtime into every program that handles an error. `(import-ct
node)` registers `node-at` and emits nothing.

Two rules make it safe to use:

* **The promise is checked at the use.** A withheld definition referenced from
  program code — a call, a global read, a function taken as a value — is a
  located error (`'node-len' was imported compile-time-only — it has no
  definition in this program`), not an undefined symbol at link time. A
  literal `defconst` is exempt: it is a compile-time substitution with no
  storage, so it survives the import that dropped every definition. An
  aggregate `defconst` has storage and is withheld like a `defvar`.
* **Compile-time-only is a property of the unit, not of one import edge.** If any
  ordinary import anywhere in the unit reaches the same library, that library is
  imported normally and nothing is withheld — so a library asking for a
  compile-time surface can never take a runtime away from a program that imports
  it for real. This holds in both orders and through nesting: a library imported
  compile-time-only may itself `import-use` a library the program uses, and that
  one stays real.

`(require-ct lib)` is the same import binding nothing (see
[What an import brings into scope](#what-an-import-brings-into-scope)): the
library's names are reachable only by full name, and a run-time reference to a
withheld one is the same located error.

A C header (`(import-ct "stdio.h")`) is imported normally: a header emits only
declarations, and libc supplies the definitions either way, so there is nothing
to withhold.

**`import-ct` only works for a library the compiler itself links.** Withholding
the definitions is exactly what leaves nothing for the compile-time JIT to run,
so the symbol has to already be in the compiler process — which is the first
condition in [What a macro body may call](macros.md#what-a-macro-body-may-call),
and is true of `node`, `intern`, `strview` and the rest of the standard library.
Reaching a library of your own this way is refused at the macro:

```
probe.nuc:3: error: macro 'probe' needs 'mydouble', which is defined where no span was recorded
  note: only a function defined at the top level of this unit can be copied into the compile-time JIT
```

Import it with `import-use` instead — a macro body may call the program's own
code, and then there is a definition to copy.

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

  **Two things a cycle does not carry**, because they only exist once a file
  has been *emitted*, and a cycle member's body is emitted before the rest of
  the file it back-imports. Each is refused with a located diagnostic naming the
  cycle, never a wrong answer:

  | Across a cycle | Diagnostic |
  |---|---|
  | A `defmacro` the partner defines | `unknown: NAME — defined in a file this unit imports circularly` |
  | A `deferror` id or an `extern` declaration the partner defines | `undefined: NAME — defined in a file this unit imports circularly` |

  Two more used to be listed here and are gone. A `prefix/name` spelling over a
  cycle member: a prefix now names the imported *file*, whose namespace and
  signatures the whole-graph prescan has already recorded, so it resolves across
  a cycle like any other reference. And a struct/union **layout** the partner
  defines: field tables are registered graph-wide before emission too, so a field
  access, a struct literal and a by-value parameter/return/argument all work
  across a cycle. The `'S' has no layout at this point` diagnostic remains for
  the one case that still cannot be settled early — a struct with an `(array T
  N)` field whose extent is a macro-expanded expression, since macros are
  registered by the emitter (see the row above).

  What *does* work across a cycle: calling the partner's functions (the point of
  the feature), reading its globals, constants and enum members, using its
  structs and unions by value or by pointer, and `(sizeof S)` / `(alloca S)`.

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
* **A `.nuch` header is inside the graph walk, like any other file.** The names a
  header contributes — a `declare`d function, an `extern` global, a `defconst`, a
  `defenum` member, and each arm of an exported overload set — are registered by
  the same whole-graph prescan, so the import form may sit anywhere in the file,
  and a library reached only through a header behaves exactly as one reached
  through its source. Its *types* were always registered this way.
  *(Both of these used to be ordinal: a `.nuc` file imported by string path —
  `(import-use "lib/foo.nuc")` — and every `.nuch`.)*
* **A header may not declare a function this unit also defines.** A `.nuch`
  describes some *other* unit's exports, so a name it declares and this unit
  defines is two different functions sharing one name — and one name is one key,
  so nothing, not even a qualified `lib/helper`, is left that reaches the
  header's. It is a compile-time error, located on the header entry and naming
  the definition it collides with. Two ways out: rename one, or give the library
  an `(ns …)`, after which its exports key as `lib/helper` and link as
  `@lib__helper` and the two coexist. *(Before this the header entry was dropped
  whole — no binding, no `declare`, no method — and `(lib/helper 3)` silently
  called the unit's own `helper`, at whatever type that one had.)* Neither a
  top-level `(declare …)` in a `.nuc` file nor one libc function declared by both
  a C header and a `.nuch` is affected: the first is a forward declaration *of*
  this unit's own function — the cross-file cycle-breaker above — and the second
  really is one function named twice. Both stay silent no-ops.
* **A `defmacro` still needs the import above the use, in either spelling.** A
  macro is not a registration but a *compiled function* — defining one runs
  codegen and materializes a JIT module — so it exists only once the defining
  file has been emitted, which is the same reason the cycle table above lists it.
  A use above the import reports `unknown: NAME`. This is a property of what a
  macro is, not of the file's extension: `.nuc` and `.nuch` behave identically.

  Struct and union **layouts** used to be listed here beside it and are not any
  more: a literal, a field access, a by-value parameter/return/field and
  union literals and `match` over an imported union all resolve on reachability, in both
  spellings — a `.nuch` header's `defunion` included, which was the last case
  listed here and now behaves exactly like its `.nuc` source, namespaced or not.
  One narrow case still needs the import above the use: a struct whose `(array
  T N)` field extent is a **macro-expanded** expression (`(array i32 (* K 2))` —
  plain constants and arithmetic-free extents are fine), which follows from the
  macro rule above rather than from anything about layouts.
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

## Constants

`(defconst NAME value)` names a value known at compile time. It takes the same
compile-time values a `defvar` initializer does, in two kinds:

* **A literal**: an integer, float, string (`"…"` or `c"…"`), character,
  `true`, `false` or `null`, or an integer expression that folds to one
  (`(+ 2 3)`, `(* WIDTH 4)`, `(sizeof Pixel)`). It has **no storage**. Each use
  of the name is that literal, so it types and adapts exactly as the literal
  would. `(defconst PI 3.25)` is an `f32` in `(let (x:f32 PI) …)` and an `f64`
  as a `printf` argument. `(defconst K 512)` compiles in `(<= ans:ui32 K)`
  exactly when `(<= ans:ui32 512)` does. `(defconst BIG 5000000000)` is `i64`.
  A use that does not fit its slot is rejected rather than wrapped.
* **An aggregate**: a struct literal `(S …)`, an array literal `(array T …)`,
  `&g`, or any other annotated compound value. It is emitted once, into
  read-only storage (an LLVM `constant`), and each use reads it like a global.
  `(ORIGIN 'x)`, `(aref TABLE 2)` and `(sum TABLE 4)` all work; an array
  constant decays to `&T` where a pointer is wanted. On a target with separate
  program and data memory (AVR), such a table stays in flash.

```lisp
(defconst PI 3.25)
(defconst GREETING "hello")
(defconst WIDTH 320)
(defconst ORIGIN (Pt 0 0))
(defconst TABLE (array i32 10 20 30 40))
```

**An annotation fixes the type.** `(defconst K:ui8 200)` is a `ui8` everywhere,
and it does not adapt the way a bare literal does: `(< s:i8 K)` is the
mixed-sign error two typed values give. `(as T v)` in the value position is the
same thing as annotating `(defconst K:T v)`. An annotated literal must fit its
type: `(defconst K:ui8 300)` is refused at the definition. A `defconst` whose
value is another typed constant takes that constant's type.

**A constant is read-only.** Each of these is a compile-time error at the write:

* `(set! K v)`, `(inc! K)` and `(dec! K)`;
* a field write, `(set! (ORIGIN 'x) 5)`;
* an element write, `(set! (aref TABLE 0) 5)`.

Reading a stored constant into a local copies it, and the copy is an ordinary
mutable value. A literal constant has no address, so `&K` is refused (`ref:
constant 'K' has no storage -- bind it with let or defvar to take its address`).

> **Hole: `&NAME` on an aggregate is writable.** `&ORIGIN` yields a plain `&Pt`
> and `&TABLE` a plain `&(array i32 4)`, and the compiler does not track that
> they point into read-only storage. Passing `ORIGIN` to a `&Pt` parameter or
> `TABLE` to a `&i32` one passes the same address. A write through one compiles, and then
> faults at run time on a host or is silently ignored on a flash part. There is
> no read-only pointer type yet to give them.

**What is refused.** A value that needs run-time work, such as a call, an
allocation or a read of a mutable global, is refused with `defconst: 'R' needs a
run-time initializer; a constant's value must be known at compile time -- use
defvar`. Run-time constants are deferred (`design/deferred/overview.md`). A
`defconst` takes no declaration attribute (`:volatile`, `:const`), since a
constant is read-only already.

**Order does not matter.** A constant may be used above its definition, in the
same file or in any reachable file (see
[Cross-file resolution](#cross-file-resolution-reachability-not-import-order)).
A `defvar` initialized from a literal constant folds it in. A `defvar`
initialized from an aggregate constant *reads* it, so that `defvar` is a
[run-time initializer](#run-time-initializers).

**Across modules.** In a `.nuch` header, a literal constant is exported as
`(defconst NAME literal)`, and an aggregate as `(extern :const (NAME Type))`
naming the library's read-only symbol. An importer's writes to the aggregate
are refused in the same way. In a C header, a literal constant becomes
`#define NAME value` (`((uint8_t)200)` when annotated), and an aggregate becomes
`extern const T NAME;`. See [Reaching a library's globals from C](compiler.md#reaching-a-librarys-globals-from-c).

`defvar :const` was the older spelling of a read-only global and has been
retired; `(defvar :const g:T v)` is now an error that names `(defconst g:T v)`.
`:const` remains valid only on an `extern`, where it declares that another
unit's global is read-only.

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
  `ptr`, `(ptr T)` / `?T`, or a **function-pointer type** `(fn ret)(params)` —
  the pointer kinds do not apply to a fn pointer, so it is nullable like `CStr`,
  and the implicit zero for the same slot is `null` anyway (see
  [Function-pointer globals](types.md#function-pointer-globals)). A
  non-null `&T` rejects it with the same diagnostic the identical local binding
  gets, since a non-null slot holding `null` compiles clean and faults on first
  use — and that includes `&(fn ret)(params)`, which is a pointer *to* a
  function pointer, not a function pointer.
* `true` / `false`, at `bool` only.
* `(char "x")`, at any int type.

**Names.** A name bound by a literal `defconst` or a `defenum` member stands
for the literal it names and folds in. An aggregate `defconst` is a read of
storage, so an initializer naming one runs at startup. Ordering does not matter: a constant defined later in the
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

**`&g`, the address of another global.** A global's address is a
link-time constant *and* is provably non-null, so this is the one initializer
that fills a non-null `&T` global with no runtime store. The
target may be defined later in the file, or in another file:

```lisp
(defvar g-head:Node)
(defvar g-cursor:&Node &g-head)
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
non-null and satisfies a `&T` annotation with no runtime store:

```lisp
(defvar g-names:&CStr (array CStr (as CStr "red") (as CStr "green")))
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
* **Comparisons and `and` / `or`.** They yield `bool` and are not part of the
  folded domain; write the answer.

### What is still refused

* **A run-time initializer at an `(array T N)` slot.** An array binding names
  storage, not a value — `set!` cannot target one — so there is nothing for a
  startup assignment to do. Declare the pointer form instead
  (`(defvar g:&T (make-table))`), or keep the table constant.
* **A non-constant element of a constant aggregate.** An aggregate constant is
  filled at link time and there is no assignment that could fill one slot of it,
  so an element that has to run is `init must be a compile-time constant`.
* **A run-time initializer for a `defconst`.** A constant's storage is
  read-only, so there is no store that could initialize it. Use `defvar`.
* **A run-time initializer inside a `compile-time` or `defmacro` body.** Those
  modules have no program globals and no startup, so the initializer would never
  run; it is refused rather than silently left at zero.
* **Union initializers.** A `(defvar u:MyUnion)` is zero-filled, but there is no
  constant *union* literal — a union has no unambiguous member to initialize —
  so assign a member at run time (a run-time initializer at a union slot works
  and is the supported route).
* **A scalar at an aggregate slot.** `(defvar p:P 5)` names what would work
  rather than being treated as a run-time initializer.
* **A type whose layout has not been produced yet.** `(sizeof S)` answers from
  the compiler's layout table here rather than from LLVM, so it is refused with
  the same message a by-value use gets, instead of silently folding to zero.
  Layouts are now registered graph-wide before emission, so this is reachable
  only for the residue listed under [Order](#order) — a macro-expanded `(array T
  N)` extent, across an import cycle.
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
(defn mk    ():&Thing      …)
(defn mkraw ():ptr:Thing   …)

(defvar ok:&Thing  (mk))          ; fine — &Thing is non-null, and so is (mk)
(defvar bad:&Thing (mkraw))       ; error: unchecked pointer where non-null (ref ...) is required
```

**The initializer's frame is gone before `main`.** `@__nucleus_init` is an
ordinary function, so anything it stack-allocates is reclaimed when it
returns — and an `(alloca T)`, a struct or array literal, or a collection
literal `[…]` evaluated as an initializer lives in that frame. Storing such an
address into the global is refused (the escape sink of
[Pointer lifecycle](special-forms.md#pointer-lifecycle-escape-analysis)):

```lisp
(defvar opts:&(Vector i32) [1 2 3])   ; error: defvar: the initializer of 'opts' is the
                                       ;   address of frame-local storage, reclaimed when
                                       ;   the initializer function returns
(defvar opts:(Vector i32) [1 2 3])    ; fine — the header is copied into the global and
                                       ;   the copy owns the heap buffer; use &opts at call sites
(defvar opts:&(Vector i32) (new (Vector i32) heap))  ; fine — heap-placed header (nucleus.create)
```

### A non-null global must be initialized

Because there is now a way to write the initializer, **there is no longer a way
to declare a non-null global without one**. `(defvar g:&T)` with no
initializer is a compile-time error:

```
demo.nuc:12: error: defvar: 'g' has a non-null pointer type but no initializer --
  the slot would start as null, which is exactly the value its type says it can
  never hold
  note: give it an initializer, or declare it nullable (`?&T`) if it genuinely
  may be null before first use
```

This closes the last position in the language where `&T` did not mean
non-null. Every other slot — a `let`/`with` binding, a `set!`, a field or
element store, an argument, a return — has refused a null-valued `&T` since
the safety flip; a global's implicit zero was the one place that produced one
anyway, and it was tolerable only while an initializer could not be written at
all.

The rule is exactly `pkind-flow-check`'s: it fires when the declared type is a
**non-null pointer with an element type**, so the existing exemptions come with
it rather than being restated.

```lisp
(defvar g:&Thing)                 ; error
(defvar g:&Thing (make-thing))    ; fine — run-time initializer
(defvar g:&Thing &x)              ; fine — constant initializer
(defvar g:?&Thing)                ; fine — a Maybe pointer may be none
(defvar g:ptr:Thing)              ; fine — an unchecked pointer is nullable
(defvar g:ptr)                    ; fine — bare `ptr` is nullable
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
* **`&g` is not a read** and is never flagged, even when `g`'s `defvar`
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
