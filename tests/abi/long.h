/* Fixture for the `long` ABI-model test (tests/run-tests.sh). `long` is
 * 32-bit on ILP32 (i386/arm) and LLP64 (Windows x64), 64-bit on LP64
 * (Linux/macOS x86_64/aarch64); `long long` is always 64-bit. */
extern long lfn(long x);
extern long long llfn(long long x);
extern unsigned long ulfn(unsigned long x);
