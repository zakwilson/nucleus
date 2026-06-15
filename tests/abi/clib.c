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
 */
#include <stdint.h>

struct Pair  { int32_t a; int32_t b; };
struct Mixed { int32_t i; float f; };
struct Big   { int64_t x; int64_t y; int64_t z; };

/* C mirror of the stamped parametric struct (P2 i32 i32).
 * Nucleus emits %P2.i32.i32 = type { i32, i32 } — same layout as P2i.
 * SysV class: INTEGER (fits in one eightbyte), coerced to/from i64. */
typedef struct { int32_t a; int32_t b; } P2i;

struct Pair pair_make(int32_t a, int32_t b) { struct Pair p = {a, b}; return p; }
int32_t     pair_sum(struct Pair p)         { return p.a + p.b; }

struct Big  big_make(int64_t x, int64_t y, int64_t z) { struct Big b = {x, y, z}; return b; }
int64_t     big_sum(struct Big b)                     { return b.x + b.y + b.z; }

double      mixed_get(struct Mixed m)                 { return (double)m.i + (double)m.f; }

P2i         p2_make(int32_t a, int32_t b)             { P2i p = {a, b}; return p; }
int32_t     p2_sum(P2i p)                             { return p.a + p.b; }
