/* Stage 15 W2d accept test — the C twin of tests/fixtures/w2d-dsp-biquad.nuc.
 *
 * Line-for-line the same kernel, with C's natural `f`-suffixed float literals.
 * Compiled by run_w2d_dsp_bitexact (tests/run-tests.sh) with
 * `-ffp-contract=off`: clang's default is to contract `a*b + c` into an FMA
 * where the target has one, and Nucleus never emits the `contract` fast-math
 * flag, so leaving it on would make the comparison a test of the *kernel*
 * rather than of literal typing. (On this container's baseline x86-64 target
 * clang emits no FMA either way — measured — so the flag is defensive, for a
 * host whose default -march has FMA.)
 *
 * Every expression is fully parenthesised into binary operations to match the
 * Nucleus side exactly (Nucleus's variadic `+`/`*` are right-associative).
 *
 * Note on the constants: Nucleus rounds a float literal decimal → double →
 * float, C's `0.29289323f` rounds decimal → float directly. The two agree for
 * every constant used here (verified), and that double rounding is the
 * long-standing semantics of `(unsafe/cast f32 …)` — W2d makes the conversion
 * implicit, it does not add a rounding step.
 */
#include <stdio.h>
#include <string.h>

#define NSAMP 24

static unsigned f32_bits(float x) {
    unsigned u;
    memcpy(&u, &x, sizeof u);
    return u;
}

static float dc_offset(void) { return 0.125f; }

static float scale(float x, float k) { return (x * k); }

int main(void) {
    float b0 = 0.29289323f;
    float b1 = 0.58578646f;
    float b2 = 0.29289323f;
    float a1 = -0.0f;
    float a2 = 0.17157288f;
    float x1 = 0.0f, x2 = 0.0f;
    float y1 = 0.0f, y2 = 0.0f;
    float u = 1.0f;
    float acc = 0.0f;
    int n;

    for (n = 0; n < NSAMP; n++) {
        u = ((u * 0.6f) + ((n % 2) == 0 ? -0.125f : 0.25f));
        {
            float x = (u + dc_offset());
            float y = 0.0f;
            y = ((((( b0 * x) + (b1 * x1)) + (b2 * x2)) - (a1 * y1)) - (a2 * y2));
            x2 = x1; x1 = x;
            y2 = y1; y1 = y;
            {
                float half = ((float)NSAMP / 2.0f);
                float d = ((float)n - half);
                float wgt = (1.0f - ((d < 0.0f ? (0.0f - d) : d) / half));
                acc = (acc + scale(y, wgt));
            }
            printf("%2d %08X %.9g\n", n, f32_bits(y), (double)y);
        }
    }
    printf("acc %08X %.9g\n", f32_bits(acc), (double)acc);
    return 0;
}
