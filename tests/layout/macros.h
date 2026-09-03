/* Stage 17: the admission rules for object-like #define import
 * (design/stage17-native-strings/platform-constants.md). Each name below is a
 * case the importer must get right; tests/run-tests.sh asserts every one. */
#pragma once

/* Implementation-reserved: not registered, but must still FOLD — MP_PUB is
 * written in terms of it, which is how glibc writes S_IRWXU and F_GETOWN. */
#define _MP_BASE 010

#define MP_PUB   (_MP_BASE | 0x20)
#define MP_SHIFT (1 << 4)
#define MP_XOR   (0xF0 ^ 0x0F)
#define MP_AND   (0xFF & 0x3C)
#define MP_NEG   (-3)
#define MP_MAX   9223372036854775807

/* None of these is an integer constant expression. */
#define MP_FN(x) ((x) + 1)
#define MP_STR   "not an integer"
#define MP_FLOAT 3.5
#define MP_LOGIC (1 && 2)
#define MP_OVER  99223372036854775807
