/* C as the oracle for Nucleus variadics, in both directions. */
#include <stdarg.h>
#include <stdio.h>

typedef struct { long a, b, c; } Big;
typedef struct { long a, b; } Pair;

extern long n_sum(int n, ...);
extern long n_vsum(int n, va_list ap);
extern long n_copy(int n, ...);
extern Big n_big(int n, ...);
extern long n_pair(Pair p, int n, ...);
extern int n_forward(char *buf, int cap, const char *fmt, ...);

/* What n_sum does, in C: the same callee, for comparing against. */
long c_sum(int n, ...) {
  va_list ap;
  va_start(ap, n);
  long t = 0;
  for (int i = 0; i < n; i++) {
    t += va_arg(ap, int);
    t += (long)va_arg(ap, double);
    t += (long)va_arg(ap, long);
    t += (long)(*va_arg(ap, const char *));
  }
  va_end(ap);
  return t;
}

long c_vsum(int n, va_list ap) {
  long t = 0;
  for (int i = 0; i < n; i++) {
    t += va_arg(ap, int);
    t += (long)va_arg(ap, double);
    t += (long)va_arg(ap, long);
    t += (long)(*va_arg(ap, const char *));
  }
  return t;
}

static long via_list(int n, ...) {
  va_list ap;
  va_start(ap, n);
  long r = n_vsum(n, ap);
  va_end(ap);
  return r;
}

#define ROW(i) (signed char)(i), (float)(i) + 0.5f, (long)(i) * 1000, "A"

void c_main(void) {
  char buf[64];
  long want = c_sum(5, ROW(1), ROW(2), ROW(3), ROW(4), ROW(5));
  printf("%ld %ld\n", want, n_sum(5, ROW(1), ROW(2), ROW(3), ROW(4), ROW(5)));
  printf("%ld %ld\n", want, via_list(5, ROW(1), ROW(2), ROW(3), ROW(4), ROW(5)));
  printf("%ld %ld\n", want * 2, n_copy(5, ROW(1), ROW(2), ROW(3), ROW(4), ROW(5)));
  Big b = n_big(2, 7L, 8L);
  printf("%ld %ld %ld\n", b.a, b.b, b.c);
  Pair p = {10, 20};
  printf("%ld\n", n_pair(p, 2, 3, 4));
  printf("%d ", n_forward(buf, sizeof buf, "%s=%d/%.2f", "x", 7, 2.5));
  printf("%s\n", buf);
  fflush(stdout);
}
