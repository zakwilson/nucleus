/* C side of the struct-ABI interop acceptance test.
 * Nucleus (tests/abi/interop.nuc) calls these and must pass/return the
 * aggregates using the platform C ABI. Built with the system cc, so the
 * coercion Nucleus emits has to match clang's TargetInfo/ABIInfo exactly.
 *
 * Coverage (x86_64 SysV reference):
 *   Pair    {i32,i32}            -> single INTEGER eightbyte, coerced to i64
 *   Mixed   {i32,float}          -> single eightbyte, INTEGER wins -> i64
 *   Big     {i64,i64,i64} (24B)  -> MEMORY: byval param / sret return
 *   P2i     {i32,i32} (param struct template (P2 i32 i32)) -> INTEGER, i64
 *
 * Stage 15 W8 G-2 added the fixed-size ARRAY field cases. They are the real
 * gate on abi-class-eightbyte's array recursion:
 *   IArr2   {int[2]}     (8B)  -> one INTEGER eightbyte  -> i64
 *   FArr2   {float[2]}   (8B)  -> one SSE eightbyte      -> <2 x float>
 *                                 (this is the case that fails if an array
 *                                  field is classified as a scalar: it would
 *                                  come out INTEGER and the floats would
 *                                  travel in rdi instead of xmm0)
 *   IArr4   {int[4]}     (16B) -> two INTEGER eightbytes -> { i64, i64 }
 *   ABig    {int[6]}     (24B) -> MEMORY: byval / sret
 */
#include <stdint.h>

struct Pair  { int32_t a; int32_t b; };
struct Mixed { int32_t i; float f; };
struct Big   { int64_t x; int64_t y; int64_t z; };

/* C mirror of the stamped parametric struct (P2 i32 i32).
 * Nucleus emits %P2.i32.i32 = type { i32, i32 } — same layout as P2i.
 * SysV class: INTEGER (fits in one eightbyte), coerced to/from i64. */
typedef struct { int32_t a; int32_t b; } P2i;

/* Stage 15 W8 G-2: by-value structs whose fields are fixed-size arrays. */
struct IArr2 { int32_t v[2]; };
struct FArr2 { float   v[2]; };
struct IArr4 { int32_t v[4]; };
struct ABig  { int32_t v[6]; };

struct Pair pair_make(int32_t a, int32_t b) { struct Pair p = {a, b}; return p; }
int32_t     pair_sum(struct Pair p)         { return p.a + p.b; }

struct Big  big_make(int64_t x, int64_t y, int64_t z) { struct Big b = {x, y, z}; return b; }
int64_t     big_sum(struct Big b)                     { return b.x + b.y + b.z; }

double      mixed_get(struct Mixed m)                 { return (double)m.i + (double)m.f; }

P2i         p2_make(int32_t a, int32_t b)             { P2i p = {a, b}; return p; }
int32_t     p2_sum(P2i p)                             { return p.a + p.b; }

int32_t iarr2_sum(struct IArr2 a) { return a.v[0] + a.v[1]; }
struct IArr2 iarr2_make(int32_t x, int32_t y) { struct IArr2 a; a.v[0]=x; a.v[1]=y; return a; }

double  farr2_sum(struct FArr2 a) { return (double)a.v[0] + (double)a.v[1]; }
struct FArr2 farr2_make(float x, float y) { struct FArr2 a; a.v[0]=x; a.v[1]=y; return a; }

int32_t iarr4_sum(struct IArr4 a) { return a.v[0] + a.v[1] + a.v[2] + a.v[3]; }
struct IArr4 iarr4_make(int32_t x) { struct IArr4 a; for (int i=0;i<4;i++) a.v[i]=x+i; return a; }

int32_t abig_sum(struct ABig a) { int32_t s=0; for (int i=0;i<6;i++) s+=a.v[i]; return s; }
struct ABig abig_make(int32_t x) { struct ABig a; for (int i=0;i<6;i++) a.v[i]=x+i; return a; }
