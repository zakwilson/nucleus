/* Stage 16 CD-4 (design/stage16-ergonomics/c-header-layout.md §8.2): a
   declarator LIST after a struct/union body. Everything after the first
   declarator used to be dropped without a word.

   Deliberately every declarator kind the shape admits: a second plain name, a
   second name over an untagged body, a pointer declarator, an array
   declarator, and the non-typedef `struct S { … } x, y;` variable list — whose
   declarators the importer does not model but must consume, or the declaration
   after it is parsed from the wrong offset. */

typedef struct cd4_tag { int x; int y; } cd4_A, cd4_B;

typedef struct { int p; int q; } cd4_C, cd4_D;

typedef struct { int r; } cd4_E, *cd4_Ep;

typedef struct { char c; } cd4_F, cd4_G[3];

union cd4_u_tag { int i; float f; } ;
typedef union { int i; float f; } cd4_U, cd4_V;

/* Variables, not types: the importer models neither, and the type is the only
   thing it should take from the line. `cd4_after` is the witness that the list
   was consumed rather than left for the function-declaration parser. */
struct cd4_S { int a; long b; } cd4_x, cd4_y;

struct cd4_after { int z; };
