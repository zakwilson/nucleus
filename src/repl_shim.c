/* repl_shim.c — thin wrapper around setjmp/longjmp for the Nucleus REPL.
 *
 * jmp_buf is an opaque, platform-specific type that Nucleus cannot express
 * directly.  This shim hides it behind simple functions callable from
 * Nucleus via -rdynamic symbol resolution.
 */

#include <setjmp.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define REPL_MAX_PROTECT 16
static jmp_buf repl_jmpbufs[REPL_MAX_PROTECT];
static int repl_depth = 0;

/* Call a function pointer that returns a `double` (no args) and print the
 * result on stderr as a Nucleus float literal — `%.17g`, with `.0` appended
 * if the result has neither a decimal point nor an exponent. Used by the
 * REPL value printer for f64-typed top-level expressions. */
void repl_print_f64(void *fp) {
    double (*f)(void) = (double (*)(void))fp;
    double v = f();
    char buf[64];
    snprintf(buf, sizeof(buf), "%.17g", v);
    int has_dot_or_e = 0;
    for (char *p = buf; *p; p++) {
        if (*p == '.' || *p == 'e' || *p == 'E' || *p == 'n' || *p == 'i') {
            has_dot_or_e = 1;
            break;
        }
    }
    if (has_dot_or_e) {
        fprintf(stderr, "  %s\n", buf);
    } else {
        fprintf(stderr, "  %s.0\n", buf);
    }
}

/* Same, for `float`-returning function pointers. Uses %.9g (shortest
 * round-trip width for binary32). */
void repl_print_f32(void *fp) {
    float (*f)(void) = (float (*)(void))fp;
    float v = f();
    char buf[64];
    snprintf(buf, sizeof(buf), "%.9g", (double)v);
    int has_dot_or_e = 0;
    for (char *p = buf; *p; p++) {
        if (*p == '.' || *p == 'e' || *p == 'E' || *p == 'n' || *p == 'i') {
            has_dot_or_e = 1;
            break;
        }
    }
    if (has_dot_or_e) {
        fprintf(stderr, "  %s\n", buf);
    } else {
        fprintf(stderr, "  %s.0\n", buf);
    }
}

/* Run `body(ctx)`: 0 if it returned normally, 1 if repl_throw unwound out of it.
 * A callback, not the caller's own continuation, so this setjmp frame is still
 * live when the longjmp fires (design/stage16-ergonomics/repl-libraries.md §3.4). */
int32_t repl_protect(void (*body)(void *), void *ctx) {
    int d = repl_depth;
    if (d >= REPL_MAX_PROTECT) {
        fprintf(stderr, "nucleus: repl_protect nested deeper than %d\n",
                REPL_MAX_PROTECT);
        exit(1);
    }
    repl_depth = d + 1;
    if (setjmp(repl_jmpbufs[d]) == 0) {
        body(ctx);
        repl_depth = d;
        return 0;
    }
    repl_depth = d;
    return 1;
}

/* Unwind to the innermost repl_protect.  Never returns. */
void repl_throw(void) {
    if (repl_depth == 0) {
        /* Exiting is what batch does, and beats jumping into a dead frame. */
        fprintf(stderr, "nucleus: fatal error outside the REPL's protected region\n");
        exit(1);
    }
    longjmp(repl_jmpbufs[repl_depth - 1], 1);
}
