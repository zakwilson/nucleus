/* Fixture for `l2-layout-*` in tests/suite-cimport.nuc (Stage 16 L2,
   design/stage16-ergonomics/c-header-layout.md §1.5/§3.2).

   The C body parser had no array member type at all: a `[` after a field name
   abandoned the whole struct (D2), which is 132 of the 163 blocked bodies in
   the §1.5 census. L2 gave it `c-array-declarator` plus a constant-expression
   evaluator over literals, `sizeof`, parens/casts, unary +/-, * / %, + - and
   << >>. Anything that does not fold clears `ok`, and the struct stays opaque
   (L1) rather than being guessed at.

   Every row states its expected layout, and the gate asserts the exact
   `%X = type` line plus `(sizeof X)` — never "it compiled". Every wrong row in
   §1.5's survey compiles fine today, so a size-only or exit-code-only oracle
   sees nothing.

   Deliberately `int` / `short` / `char` throughout: the sizes below then hold
   on any target with a 4-byte int, so the stated numbers are not an x86_64
   assumption. The `long`-bearing shapes are covered by run_l2_libc_layouts,
   which compares against clang rather than against a number. */

#define L2_MACRO_N 6

/* ---- extents that must fold --------------------------------------------- */

/* A literal extent.            %l2_lit   = type { [4 x i32], i32 }   sizeof 20 */
struct l2_lit { int a[4]; int b; };

/* Multi-dimensional: C reads `[a][b]` left to right, so the extents wrap right
   to left.                %l2_multi = type { [2 x [3 x i32]], i32 }  sizeof 28 */
struct l2_multi { int m[2][3]; int b; };

/* Macro-expanded. `clang -E` has already substituted 6, so the parser only ever
   sees a literal — pinned because that is an assumption, not a guarantee.
                                %l2_macro = type { [6 x i8], i32 }    sizeof 12 */
struct l2_macro { char s[L2_MACRO_N]; int b; };

/* A `sizeof`-bearing constant expression — the `__ss_padding` idiom, 28 bodies
   in the census. Evaluated for the EMISSION target, never for clang's host.
     32 - sizeof(int)*2 == 24     %l2_sizeof = type { [24 x i8], i32 } sizeof 28 */
struct l2_sizeof { char pad[(32 - sizeof(int) * 2)]; int b; };

/* A shift and a parenthesised cast, together.
     ((int)1 << 3) == 8           %l2_shift = type { [8 x i8], i16 }   sizeof 10 */
struct l2_shift { char v[((int)1 << 3)]; short b; };

/* The `sockaddr` shape, verbatim — the single most common one in the census.
                             %l2_chararr = type { i16, [14 x i8] }    sizeof 16 */
struct l2_chararr { unsigned short sa_family; char sa_data[14]; };

/* ---- extents that must NOT fold ----------------------------------------- */
/* Each of these must leave the struct OPAQUE with a located error. An extent
   the evaluator guesses at is exactly the silent-wrong class L1/L2 remove. */

/* An enum constant: a name, and the evaluator resolves no names. */
enum { L2_ENUM_N = 5 };
struct l2_unfoldable_enum { int u[L2_ENUM_N]; int b; };

/* A flexible array member. C1a: the one shape here that DOES lay out (3b). */
struct l2_unfoldable_flex { int n; int f[]; };

/* A zero extent: legal as a GNU extension, not a positive count. */
struct l2_unfoldable_zero { int z[0]; int b; };
