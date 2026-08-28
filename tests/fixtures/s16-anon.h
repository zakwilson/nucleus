/* Stage 16 AN-1/AN-2: C11 anonymous members.
   design/stage16-ergonomics/c-boundary-defects.md §9.

   The shapes glibc actually uses, in one file: an anonymous union inside a
   struct (siginfo/sigcontext), an anonymous struct nested inside THAT union
   (two levels of minted name), and an anonymous struct at the top of a
   declaration (rusage's timeval pair). A named member of an anonymous type is
   here too, because it must keep behaving like an ordinary member. */

#ifndef S16_ANON_H
#define S16_ANON_H
#include <stdint.h>

typedef struct {
  int32_t code;
  union {
    int32_t si_int;
    struct { int32_t pid; int32_t uid; };
  };
  struct { int32_t a; int32_t b; } named;
} s16_sig;

typedef struct {
  struct { int64_t sec; int64_t usec; };
  int32_t maxrss;
} s16_rus;

#endif
