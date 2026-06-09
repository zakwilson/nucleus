/* Struct-layout verification corpus (Phase E, design/stage8/platform.md
 * question 13(a)/14). This header is the single source of truth: it is
 * imported by layout.nuc (Nucleus computes sizeof/offset from its own layout
 * walk) and #included by layout.c (the platform C compiler is the oracle).
 * run-layout-test.sh diffs the two outputs; any disagreement is a layout bug.
 *
 * Only field types the Nucleus C-header parser can represent are used. Arrays,
 * unions, and bitfields are skipped by the parser by design (a struct with one
 * is registered as opaque ptr, not a partial layout), so they are out of scope
 * here; the calling-convention half of the ABI is covered by tests/abi/. */

/* Each primitive alone in a one-field struct. */
struct P_i8  { char a; };
struct P_i16 { short a; };
struct P_i32 { int a; };
struct P_i64 { long long a; };
struct P_f32 { float a; };
struct P_f64 { double a; };
struct P_ptr { void *a; };

/* Mixed-size pairs, both orders, to exercise padding and tail padding. */
struct M_8_64   { char a; long long b; };
struct M_32_8   { int a; char b; };
struct M_8_32   { char a; int b; };
struct M_16_64  { short a; long long b; };
struct M_8_16_8 { char a; short b; char c; };
struct M_64_8   { long long a; char b; };

/* Nested struct by value (named) and anonymous inline struct field. */
struct Inner { int x; int y; };
struct Outer { struct Inner pt; char tag; };
struct Anon  { struct { int x; long long y; } in; int tag; };

/* timespec-shaped and a larger mixed record. */
struct TimeSpec { long tv_sec; long tv_nsec; };
struct Rec      { char tag; long value; void *next; double d; };
