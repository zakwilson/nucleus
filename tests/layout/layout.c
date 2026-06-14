/* C oracle for the struct-layout verification harness (Phase E). Prints
 * sizeof + per-field byte offsets for every struct in structs.h, one line
 * each, using the platform C compiler's own layout. layout.nuc prints the
 * same lines from Nucleus's layout walk; run-layout-test.sh diffs them. */
#include <stdio.h>
#include <stddef.h>
#include "structs.h"

#define SZ(S)     (long long)sizeof(struct S)
#define OFF(S, F) (long long)offsetof(struct S, F)

int main(void) {
    printf("P_i8 sizeof=%lld a=%lld\n",  SZ(P_i8),  OFF(P_i8, a));
    printf("P_i16 sizeof=%lld a=%lld\n", SZ(P_i16), OFF(P_i16, a));
    printf("P_i32 sizeof=%lld a=%lld\n", SZ(P_i32), OFF(P_i32, a));
    printf("P_i64 sizeof=%lld a=%lld\n", SZ(P_i64), OFF(P_i64, a));
    printf("P_f32 sizeof=%lld a=%lld\n", SZ(P_f32), OFF(P_f32, a));
    printf("P_f64 sizeof=%lld a=%lld\n", SZ(P_f64), OFF(P_f64, a));
    printf("P_ptr sizeof=%lld a=%lld\n", SZ(P_ptr), OFF(P_ptr, a));

    printf("M_8_64 sizeof=%lld a=%lld b=%lld\n",   SZ(M_8_64),  OFF(M_8_64, a),  OFF(M_8_64, b));
    printf("M_32_8 sizeof=%lld a=%lld b=%lld\n",   SZ(M_32_8),  OFF(M_32_8, a),  OFF(M_32_8, b));
    printf("M_8_32 sizeof=%lld a=%lld b=%lld\n",   SZ(M_8_32),  OFF(M_8_32, a),  OFF(M_8_32, b));
    printf("M_16_64 sizeof=%lld a=%lld b=%lld\n",  SZ(M_16_64), OFF(M_16_64, a), OFF(M_16_64, b));
    printf("M_8_16_8 sizeof=%lld a=%lld b=%lld c=%lld\n", SZ(M_8_16_8), OFF(M_8_16_8, a), OFF(M_8_16_8, b), OFF(M_8_16_8, c));
    printf("M_64_8 sizeof=%lld a=%lld b=%lld\n",   SZ(M_64_8),  OFF(M_64_8, a),  OFF(M_64_8, b));

    printf("Inner sizeof=%lld x=%lld y=%lld\n",  SZ(Inner), OFF(Inner, x), OFF(Inner, y));
    printf("Outer sizeof=%lld pt=%lld tag=%lld\n", SZ(Outer), OFF(Outer, pt), OFF(Outer, tag));
    printf("Anon sizeof=%lld in=%lld tag=%lld\n",  SZ(Anon), OFF(Anon, in), OFF(Anon, tag));

    printf("TimeSpec sizeof=%lld tv_sec=%lld tv_nsec=%lld\n", SZ(TimeSpec), OFF(TimeSpec, tv_sec), OFF(TimeSpec, tv_nsec));
    printf("Rec sizeof=%lld tag=%lld value=%lld next=%lld d=%lld\n", SZ(Rec), OFF(Rec, tag), OFF(Rec, value), OFF(Rec, next), OFF(Rec, d));

    printf("U_scalar sizeof=%lld\n", (long long)sizeof(union U_scalar));
    printf("U_mixed sizeof=%lld\n",  (long long)sizeof(union U_mixed));
    printf("U_pad sizeof=%lld\n",    (long long)sizeof(union U_pad));
    printf("UWrap sizeof=%lld tag=%lld u=%lld\n", SZ(UWrap), OFF(UWrap, tag), OFF(UWrap, u));
    printf("UAnon sizeof=%lld kind=%lld data=%lld tail=%lld\n", SZ(UAnon), OFF(UAnon, kind), OFF(UAnon, data), OFF(UAnon, tail));

    /* Stage 10 U4/A2 niche unions (design/stage10/unions.md §6 rules 2/3): a
     * `(Maybe (ref T))` / `(Result (ref T) Err)` over a typed pointer payload is
     * niche-encoded *in the pointer*, so to C it IS a `struct Pt *` — pointer-
     * sized, no discriminant. The oracle is sizeof(void*); the .nuc side prints
     * sizeof of its niche unions. The round-trip check confirms (ok p) carries p
     * unchanged (the C-ABI promise that `!ptr:Pt` is a `Pt*`). */
    printf("NICHE_MAYBE sizeof=%lld\n",  (long long)sizeof(struct Pt *));
    printf("NICHE_ERRPTR sizeof=%lld\n", (long long)sizeof(struct Pt *));
    printf("NICHE_okptr_roundtrip=%d\n", 1);
    return 0;
}
