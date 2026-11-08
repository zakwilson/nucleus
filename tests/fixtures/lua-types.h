/* nuc-lua ISSUE-029/030/031/037: shapes from lobject.h, llimits.h, lstate.h and lparser.h. */
#define LT_IDSIZE 60
#define LT_TNUMBER 3
#define lt_cast(t, exp) ((t)(exp))
#define lt_makevariant(t, v) ((t) | ((v) << 4))
#define LT_VNUMINT lt_makevariant(LT_TNUMBER, 0)
#define LT_VNUMFLT lt_makevariant(LT_TNUMBER, 1)
#define LT_FRESH (lt_cast(unsigned int, 1) << 8)
#define LT_ARITY lt_makevariant(1)
typedef struct LtGrid { int x; int a[3][2]; } LtGrid;
struct LtBlock;
typedef struct LtHolder { struct LtBlock *bl; int n; } LtHolder;
