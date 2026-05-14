# Types and data

#### Designer

## Implement

* Unions, both anonymous `union` and named `defunion`. `(defunion Foo bar:int (baz (defunion Qux quux:f32)) (union corge:i64))`
* Bit fields as (name type size) canonical and name:type:size sugared.
* Anonymous structs with the `struct` form.
* Nested structs
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
