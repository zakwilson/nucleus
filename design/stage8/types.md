# Types and data

#### Designer

## Implement

* Unions, both anonymous `union` and named `defunion`. `(defunion Foo bar:int (baz (defunion Qux quux:f32)) (union corge:i64))`
* Bit fields as (name type size) canonical and name:type:size sugared.
* ~~Anonymous structs with the `struct` form~~ (done — `(struct field:type ...)` is a type expression, memoized by content-hash)
* ~~Nested structs~~ (done — nested *by reference*; `(defstruct Outer (pt (struct ...)))` or `(defstruct Outer (pt (ptr (struct ...))))` both work. Value-typed nested-struct *writes* still need a field-address operator that doesn't exist yet — see open item below.)
* Packed and alligned structs usin the `&attributes` special symbol after the members in the struct definition
* `long double` as `f80` - Nucleus types should be concrete rather than system-dependent.
* Complex numbers as `cf32` and `cf64` with list syntax `(3.0 4.0)` representing 3.0+4.0i.
* ~~`volatile` keyword in type declarations, both list and sugared form~~ (done — postfix `(T volatile)` and `T:volatile`)
* Handle C enums in headers
* Handle function pointers in structs. Nucleus has function pointers, and if they're missing functionality equivalent to C, that needs to be addressed.

## Deferred - note these in stage888-deferred.md

* Conditional compilation to use system-dependent types where that is desired.
* `restrict` and `const` qualifiers or equivalent
* Typedef aliases 

#### Robot

BEEP BOOP. Questions before implementation:

## Syntax/semantics

1. **Unions** — Is anonymous `(union foo:i32 bar:f32)` a type expression usable anywhere a type is expected? For `defunion`, the example nests a `defunion` inline and also inlines an anonymous `union` as a member. Confirm:
   - Members follow the same `name:type` / `(name type)` pattern as `struct`.
   - A nested `defunion` both *defines* the named type and *uses* it as that field's type.
   - Anonymous `union` as a member contributes its members to the parent's namespace (C-style) or is accessed via the wrapping field name?

2. **Bit fields** — `(name type size)` canonical and `name:type:size` sugared. Allowed only inside structs (and unions)? Constraint that `type` must be integral? Behavior when total width crosses storage-unit boundaries — match C, or define explicitly?

3. **Packed/aligned `&attributes`** — concrete syntax? Options:
   - `(struct a:i32 b:i8 &attributes packed)`
   - `(struct a:i32 b:i8 &attributes (packed) (aligned 16))`
   - Single trailing `&attributes` form vs. multiple. Which?

4. **`f80`** — strictly x86 80-bit extended precision (10 bytes, 16-byte aligned in structs per SysV), or "whatever the platform's `long double` is"? "Concrete rather than system-dependent" suggests the former — confirm.

5. **Complex literals** — `(3.0 4.0)` collides with list syntax. Parsed as complex only in a `cf32`/`cf64`-typed context (initializer, cast, typed binding), or is there a reader tag like `#c(3.0 4.0)`?

6. **`volatile`** — list form `(volatile i32)` plus sugared form. Sugared as `volatile:i32` (prefix-style) or `x:i32:volatile` (postfix)? Confirm which.

7. **C enums in headers** — "handle" means:
   - Treat as `i32` (or underlying type) with enum constants bound as `def` values? Or
   - A real enum type with name-based dispatch? Or
   - Just round-trip through header import without exposing enum-ness to Nucleus?

8. **Function pointers in structs** — what's the specific gap you've observed? If there's a failing case in mind, point me at it; otherwise I'll need to write probe tests against current behavior before I know what to fix.

## Process

- What's already wired in stage8? Should I survey `design/stage8/` siblings and the parser/typer before proposing a design, or do you want a fresh design pass first?
- Implementation ordering preference, or pick cheapest-first?

Resolve at least 1, 3, 5, 7, 8 and I'm ready. END TRANSMISSION.

#### Designer

1. An anonymous union is a type expression. A named union both defines and "returns" it as a type expression.  Match C for anonymous union field names - I think we need to for interop.
2. Bit fields are only inside structs and unions for now. Match C.
3. &attributes takes a variable number of attributes which can be symbols or lists (and must be lists if they take arguments)
4. `f80` is strictly the 80-bit extended precision implementation. Implementing whatever other platforms do with `long double` is deferred. Note in stage888-deferred.md
5. Use the type name like a constructor: `(cf32 3.0 4.0)`
6. Postfix for both (i32 volatile) and i32:volatile. That shouldn't require any changes to sugaring.
7. A real enum type
8. I'm not aware of any gaps, but we currently *don't* handle function pointers in structs from C headers and we should.

#### Robot — anonymous & nested structs (next sub-task)

BEEP BOOP. Volatile is landed (commit cdd1c46). Picking up anonymous + nested structs next per volatile-plan.md. State of the world after a survey of `src/nucleusc.nuc`:

- `defstruct` registers a named `StructDef` in `g-structs` (cap `MAX-STRUCTS = 64`, src:27/641) and emits `%Name = type { ... }` to `g-type-stream`. Field types are parsed by `extract-name-and-type` → `parse-type-name`/`parse-type-from-node` (src:870, 727).
- `parse-type-from-node` handles symbols, `(ptr T)`, `(fn ret params)`, and postfix `volatile`. There is **no** `(struct ...)` clause anywhere in type position. The literal word `struct` does not appear as a keyword in `nucleusc.nuc`.
- Nested struct fields by *name* (a defstruct whose field type is another already-defined struct) work today via `parse-type-name` returning a `TY-STRUCT` wrapper. The gap is the inline anonymous form.
- `type-eq` (src:662) compares struct types by `StructDef*` identity. Structural equivalence is not used anywhere.
- C-header parser (`src/cheader.nuc`) skips anonymous inner structs entirely; that is a separate gap.

Questions before I write the implementation plan:

1. **Structural equivalence.** Two occurrences of `(struct x:i32 y:i32)` at different sites — same type, or distinct? C says distinct (no name = no compatible type). Nucleus options:
   - (a) **Distinct each time.** Each `(struct ...)` literal allocates a fresh anonymous `StructDef`. Matches C; means you cannot pass `(struct x:i32)` across function boundaries cleanly without a `defstruct`.
   - (b) **Structurally memoized.** Identical field-name+type lists share one `StructDef`. More Lisp-y; lets you write `(defn f:void (p:(struct x:i32 y:i32)))` and call it with a matching literal type at the call site.
   - (c) **Distinct, but assignment-compatible by structure.** Two distinct StructDefs but `type-eq` (or a separate compat check) treats matching layouts as interchangeable.
   I lean (b) — single source of truth, simplest reasoning. Confirm?

2. **Synthetic naming.** Anonymous structs still need an LLVM type name (`%foo = type {...}`). Options:
   - (a) `%__anon_struct_0`, `%__anon_struct_1`, ... monotonic counter.
   - (b) Content-hashed: `%__anon_struct_h<hex>` derived from the field list. Natural fit for option 1(b) — memoization key and IR name come from the same hash.
   - Recommend (b) iff we go with 1(b); otherwise (a). OK?

3. **Where is `(struct ...)` allowed?** I plan to accept it everywhere `parse-type-from-node` is called:
   - `defstruct` field types (nested anonymous struct).
   - `defn` parameter and return types.
   - `let` / `defvar` / `extern` bindings.
   - `(ptr (struct ...))`, `(cast (ptr (struct ...)) p)`, defcast pairs.
   Any place you'd want to *exclude*?

4. **MAX-STRUCTS cap.** Current 64 is tight once anonymous structs start showing up. Two options:
   - (a) Bump to a generous flat cap (e.g. 1024). Cheap, one-line.
   - (b) Growable backing (`realloc`-style). More work; uncertain payoff at current program sizes.
   With memoization (1b) we'll dedupe heavily, so (a) almost certainly suffices. (a) OK?

5. **Sugared form.** Does `p:(struct x:i32 y:i32)` need to work via the existing colon desugarer? I believe it already does — `split-typed`/`desugar-symbol` only triggers on `:` in a symbol token; a parenthesized type on the RHS of a `(name type)` list binding goes straight through `parse-type-from-node`. The sugared form would have to be written `p:struct` which is meaningless. So: anonymous struct only appears in **list** binding form, never in colon-sugar. Confirm that's acceptable?

6. **Field access through anonymous nested structs.** `(defstruct Outer point:(struct x:i32 y:i32))` — access is `(. (. o point) x)`, fully qualified. No C-style anonymous-member-namespace-injection for `(struct ...)`. (That C-style flattening only applies to `union` per your answer #1.) Confirm?

7. **Scope of this sub-task.** I propose: implement Nucleus-side `(struct ...)` only. The C-header side (cheader.nuc skipping anonymous inner structs) is a separate item, even though stage8-list.md lumps them. OK to defer the header-import half?

8. **Tests.** I'll add `examples/anon-struct.nuc` covering: anonymous struct as `let` binding type, as defstruct field, passed to a function, returned from a function (if option 1b), and a `(ptr (struct ...))` round-trip. Anything specific you want exercised?

Resolve at least 1, 2, 4, 7 and I'm ready to write the plan file (`design/stage8/anon-struct-plan.md`). END TRANSMISSION.

#### Designer

1. I like the structurally memoized option.

2. Content hashed seems like the right thing here.

3. Don't exclude using `struct` arbitrarily.

4. Add growable backing and eliminate the MAX-STRUCTS cap.

5. Anonymous struct is always a list form. Sugared symbols for members should work.

6. No C-style namespace injection, but add `..` (probably as a macro) for flattened access in the style of `->`.

7. Do the header import task immediately after completion of anonymous structs unless there are blockers. No need to wait for a commit between.

8. Those tests are fine.

#### Robot — status after anonymous structs landed

BEEP BOOP. Nucleus-side `(struct ...)` is live with memoization:

- Growable struct registry (`MAX-STRUCTS` removed). `register-struct` arena-allocates each `StructDef`; index table grows via `realloc`-style doubling.
- `hash-struct-shape` (FNV-1a 64-bit) over field names + recursive type shape. Synthetic name `__anon_struct_h<16-hex>`. Collisions are not handled — treated as program bugs.
- `(struct ...)` clause in `parse-type-from-node` accepts the form anywhere a type is expected.
- `examples/anon-struct.nuc` / `tests/expected/anon-struct.out` cover let-binding, nested defstruct field (via `(ptr (struct ...))`), function param round-trip, and memoization across two call sites. All passing.

**Two blockers / open items before tackling the header-import half (answer #7):**

1. **C-header struct ingestion is greenfield.** Today `src/cheader.nuc` returns `ty-ptr` for *every* C struct type (`is-struct` → opaque ptr at src/cheader.nuc:184). No `typedef struct {...}` body is ever parsed into a Nucleus `defstruct`. So "anonymous inner structs skipped" understates it — *all* structs are skipped. Bringing in anonymous + nested requires first building a real C struct-body parser, recognizing typedef'd and tag'd struct definitions, recursing into nested braces, and synthesizing `defstruct` calls (plus `(struct ...)` for anonymous inner ones). That's a stage-8-sized chunk on its own. Confirm you still want me to fold it in here, or split into its own item?

2. **Value-typed nested struct field writes are awkward.** With `(defstruct Outer (pt (struct x:i32 y:i32)) ...)` there's no way to write `(. o pt) .x = 10` directly — `addr-of` only takes symbols, and `.set!` requires a pointer. Workarounds today: use `(ptr (struct ...))` instead, or write through a helper function. Designer item #6 (the `..` macro) hints at the path forward; I'd suggest adding a complementary `.&` (field-address) operator. Want me to land `.&` as a follow-on, or defer?

END TRANSMISSION.
