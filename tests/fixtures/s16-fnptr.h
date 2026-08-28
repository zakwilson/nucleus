/* Stage 16 FP-4 (design/stage16-ergonomics/c-boundary-defects.md §2.1): one
   header carrying all four C function-pointer declarator positions. Every one
   of them used to collapse to `ptr`, so a Nucleus function could not be passed
   to any of these and nothing could be called back through them. */

/* 1: typedef — how glibc names most callbacks. */
typedef int (*s16_cmp)(const void *, const void *);
int s16_apply_td(s16_cmp f, int a, int b);

/* 2: parameter, spelled inline. */
int s16_apply_inline(int (*f)(int, int), int a, int b);

/* 3: struct member, whose NAME the old parser also dropped — which is why the
   whole enclosing struct came out opaque. */
struct S16Hold {
  int (*cb)(int);
  int n;
};

/* 4: return — a function returning a function pointer, C's `signal` shape.
   Skipped outright before FP-4. */
void (*s16_signal(int, void (*)(int)))(int);
int (*s16_get(void))(int, int);

/* A nested function-pointer parameter, and `(void)` as "no parameters". */
int s16_nest(int (*f)(void (*)(int), int));
