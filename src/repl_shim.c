/* repl_shim.c — thin wrapper around setjmp/longjmp for the Nucleus REPL.
 *
 * jmp_buf is an opaque, platform-specific type that Nucleus cannot express
 * directly.  This shim hides it behind two simple functions callable from
 * Nucleus via -rdynamic symbol resolution.
 */

#include <setjmp.h>
#include <stdint.h>
#include <stdio.h>

static jmp_buf repl_jmpbuf;

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

/* Returns 0 on initial call (setjmp), 1 when jumped back via repl_throw. */
int32_t repl_try(void) {
    return setjmp(repl_jmpbuf) != 0 ? 1 : 0;
}

/* Jump back to the most recent repl_try call site.  Never returns. */
void repl_throw(void) {
    longjmp(repl_jmpbuf, 1);
}
