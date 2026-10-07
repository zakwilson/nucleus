/* A function definition ends at `}`, with no `;`: the declaration after it must
   still reach the signature prescan (GTK's G_DECLARE_* blocks do this). */
static inline int pai_helper (int x) { if (x) { return x; } return 0; }
typedef struct _PaiThing PaiThing;
struct _PaiThing { int v; };
static inline int pai_twice (int x) __attribute__((unused)) { return 2 * x; }
typedef struct _PaiOther PaiOther;
void pai_take (PaiThing *t);
