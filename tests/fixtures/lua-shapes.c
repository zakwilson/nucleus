#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include "lua-shapes.h"
long long (ls_twice) (long long n) { return 2 * n; }
const char *(ls_name) (int i) { return i ? "one" : "zero"; }
void ls_die (const char *fmt, ...) {
  va_list ap; va_start(ap, fmt); vprintf(fmt, ap); va_end(ap);
  exit(0);
}
