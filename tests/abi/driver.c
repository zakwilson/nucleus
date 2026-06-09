/* C driver that calls Nucleus-defined struct-by-value functions
 * (tests/abi/callee.nuc). The C compiler lowers these calls per the platform
 * ABI, so Nucleus's defn-side lowering must agree. */
#include <stdio.h>
#include <stdint.h>

struct Pair { int32_t a; int32_t b; };
struct Big  { int64_t x; int64_t y; int64_t z; };

struct Pair nuc_pair_make(int32_t a, int32_t b);
int32_t     nuc_pair_sum(struct Pair p);
struct Big  nuc_big_make(int64_t x, int64_t y, int64_t z);
int64_t     nuc_big_sum(struct Big b);

int main(void) {
    struct Pair p = nuc_pair_make(3, 4);
    printf("c2n pair=%d,%d sum=%d\n", p.a, p.b, nuc_pair_sum(p));
    struct Big b = nuc_big_make(100, 200, 300);
    printf("c2n big=%lld,%lld,%lld sum=%lld\n",
           (long long)b.x, (long long)b.y, (long long)b.z,
           (long long)nuc_big_sum(b));
    return 0;
}
