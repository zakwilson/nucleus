/* Stage 15 W3b (design/stage15-stress-test/cheader.md §1.5): declarations the
 * header importer recognizes as functions but cannot faithfully describe.
 *
 * Each must be SKIPPED with a `<header>:<line>: warning: …` naming the function,
 * never emitted. Emitting them is what §1.5 documented: invalid IR reaching the
 * LLVM parser thousands of lines later as `failed to parse generated IR`, with
 * nothing pointing at the header or the function responsible.
 *
 * Line numbers below are asserted by run_w3b_skip in tests/run-tests.sh — adding
 * or removing a line here means updating it.
 */

struct W3bHidden;

/* Representable: an opaque handle behind a pointer. Must still be imported. */
void w3b_keep(struct W3bHidden *p);

/* A by-value aggregate with no layout — `%W3bHidden` has no definition, so a
 * `declare void @w3b_skip_byval(%W3bHidden)` would not parse. */
void w3b_skip_byval(struct W3bHidden h);

/* A `void` parameter in a non-empty list. Never valid C; the exact shape LLVM
 * rejects with "void type only allowed for function results". */
void w3b_skip_void(int a, void b);

/* More parameters than the fixed parameter array holds: the arity is counted
 * past the cap so the gate sees the real count and skips, rather than silently
 * registering a truncated signature. */
void w3b_skip_many(int a1, int a2, int a3, int a4, int a5, int a6, int a7, int a8, int a9, int a10, int a11, int a12, int a13, int a14, int a15, int a16, int a17, int a18, int a19, int a20, int a21, int a22, int a23, int a24, int a25, int a26, int a27, int a28, int a29, int a30, int a31, int a32, int a33);
