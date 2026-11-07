/* Fixture for the `cd*` units in tests/suite-declarators.nuc (Stage 16 CD-1/CD-2/CD-3,
   design/stage16-ergonomics/c-header-layout.md §8).

   Three C declarator shapes the parser used to drop:

     CD-1  a multi-declarator field line, `int a, b;`   — the struct went opaque
     CD-2  a typedef declarator list, `typedef int a, *b;` — all but the first
           declarator was discarded
     CD-3  a with-body aggregate array typedef,
           `typedef struct Tag { … } Name[N];` — the extent was discarded and
           the parameter passed byval where C decays it to a pointer (the one
           SILENT defect of the three; §2's D4-residue row)

   Each declarator carries its own pointer depth and its own extents over the
   shared declaration specifiers, so the gate asserts the exact `%X = type` line
   (which is the field offsets, not merely the size) and `sizeof` against `cc`
   from this same header. Every wrong row in §1.5's survey compiles fine, which
   is why "it compiled" is never the assertion.

   `int` / `short` / `char` throughout, so the stated sizes hold on any target
   with a 4-byte int. A later declarator starts from the base under the first
   one's stars, which c-ptr-to keeps (lua-bugfixes, nuc-lua ISSUE-040). */

/* ---- CD-1: multi-declarator field lines ---------------------------------- */

/* %cd_plain = type { i32, i32 }                                    sizeof 8 */
struct cd_plain { int a, b; };

/* Each declarator's own stars.  %cd_ptrs = type { ptr, ptr, i32 }  sizeof 24 */
struct cd_ptrs { char *s, *t; int n; };

/* Each declarator's own extents. %cd_arrays = type { i32, [3 x i32] } sz 16 */
struct cd_arrays { int x, y[3]; };

/* A bit-field run split across a declarator list — the `tcp_info` shape.
   %cd_bits = type { [1 x i8], i32 }                                sizeof 8 */
struct cd_bits { unsigned a : 3, b : 5; int c; };

/* Three declarators, to pin that the loop is a loop.
   %cd_three = type { i16, i16, i16, i32 }                         sizeof 12 */
struct cd_three { short p, q, r; int n; };

/* ---- CD-1: the base under the first declarator's stars ------------------ */

/* Declarators that disagree in POINTER DEPTH. `*p` keeps its pointee, so `q`
   is the `int` under it: %cd_mixed_ptr = type { ptr, i32 }      sizeof 16 */
struct cd_mixed_ptr { int *p, q; };

/* A later starred declarator points where the first does: `next` is a
   pointer to cd_link, which the test dereferences, not a bare `ptr`. */
struct cd_link { struct cd_link *prev, *next; int n; };

/* ---- CD-2: comma-separated typedef declarator lists ---------------------- */

typedef int cd_ta, *cd_tb;
typedef int *cd_te, cd_tf;
typedef long cd_tc, cd_td[4];

/* ---- CD-3: with-body aggregate array typedefs ---------------------------- */

/* Tagged: the element is the TAG, which the whole-unit prescan anchors on. */
typedef struct cd_tag { int x, y; } cd_tagarr[2];

/* Untagged: no tag to anchor on, so both passes mint `__carr.cd_anonarr`. */
typedef struct { int x, y; } cd_anonarr[3];

/* C decays an array parameter to a pointer; before CD-3 both of these were
   `declare void @f(i64)` — a 8-byte aggregate in a register. */
void cd_take_tagarr(cd_tagarr a);
void cd_take_anonarr(cd_anonarr a);
