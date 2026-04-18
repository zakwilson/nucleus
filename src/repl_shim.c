/* repl_shim.c — thin wrapper around setjmp/longjmp for the Nucleus REPL.
 *
 * jmp_buf is an opaque, platform-specific type that Nucleus cannot express
 * directly.  This shim hides it behind two simple functions callable from
 * Nucleus via -rdynamic symbol resolution.
 */

#include <setjmp.h>
#include <stdint.h>

static jmp_buf repl_jmpbuf;

/* Returns 0 on initial call (setjmp), 1 when jumped back via repl_throw. */
int32_t repl_try(void) {
    return setjmp(repl_jmpbuf) != 0 ? 1 : 0;
}

/* Jump back to the most recent repl_try call site.  Never returns. */
void repl_throw(void) {
    longjmp(repl_jmpbuf, 1);
}
