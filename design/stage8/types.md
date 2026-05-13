# Types and data

## Implement

* Unions, both anonymous `union` and named `defunion`. `(defunion Foo bar:int (baz (defunion Qux quux:f32)) (union corge:i64))`
* Bit fields as (name type size) canonical and name:type:size sugared.
* Anonymous structs with the `struct` form.
* Nested structs
* Packed and alligned structs usin the `&attributes` special symbol after the members in the struct definition
* `long double` as `f80` - Nucleus types should be concrete rather than system-dependent.
* Complex numbers as `cf32` and `cf64` with list syntax `(3.0 4.0)` representing 3.0+4.0i.
* `volatile` keyword in type declarations, both list and sugared form
* Handle C enums in headers
* Handle function pointers in structs. Nucleus has function pointers, and if they're missing functionality equivalent to C, that needs to be addressed.

## Deferred - note these in stage888-deferred.md

* Conditional compilation to use system-dependent types where that is desired.
* `restrict` and `const` qualifiers or equivalent
* Typedef aliases 
