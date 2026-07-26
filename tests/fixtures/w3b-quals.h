/* Stage 15 W3b (design/stage15-stress-test/cheader.md §1.5): the C type-qualifier
 * matrix for the header importer.
 *
 * A qualifier is legal anywhere in a declaration-specifier sequence and after
 * every `*`. The importer used to accept only the LEADING position: an "east"
 * qualifier terminated the type, the qualifier token was consumed as the
 * parameter's name, and the following `*p` started a phantom second parameter
 * that defaulted to `ptr`. Only the `void` spelling produced IR LLVM rejects
 * (`declare void @_mm_clflush(void, ptr)`, from SDL_cpuinfo.h's intrinsics
 * chain); every other spelling produced a silently wrong arity and ABI.
 *
 * Both halves are pinned in tests/run-tests.sh (run_w3b_quals) — the previously
 * broken spellings AND the previously correct ones, so a future "fix" cannot
 * trade one for the other.
 */

struct W3bOp { int a; };

/* --- previously broken: a qualifier after the base type ------------------- */
void w3b_void_const(void const *p);
void w3b_int_const(int const *p);
void w3b_int_volatile(int volatile *p);
void w3b_struct_const(struct W3bOp const *p);
void w3b_ulong_const(unsigned long const *p);
void w3b_long_const(long const *p);
void w3b_double_const(double const *p);
void w3b_int_const_val(int const n);        /* no pointer at all */
void w3b_atomic(int _Atomic *p);

/* --- previously correct: must not regress -------------------------------- */
void w3b_const_void(const void *p);
void w3b_char_star_const(char * const p);
void w3b_const_char_star_const(const char * const p);
void w3b_volatile_int(volatile int *p);
void w3b_int_restrict(int * restrict p);
void w3b_no_params(void);
void w3b_variadic(const char *f, ...);

/* --- qualifiers on both sides, and in the return type -------------------- */
void w3b_east_restrict(int const * restrict const p);
int w3b_ret_int(void const *p);
void const *w3b_ret_east(void);
