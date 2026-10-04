#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "string.h"

/* Generated from lib/fmt.nuc by nucleusc --emit-cheader */

/* write-str: uses an error-union or option type; not exported */
typedef struct CFile {
    void* f;
} CFile;

struct CFile cfile(void* f);
/* write-str: uses an error-union or option type; not exported */
void string_push_u64(struct String* out, uint64_t v) asm("string-push-u64");
void string_push_i64(struct String* out, int64_t v) asm("string-push-i64");
/* to-str: uses an error-union or option type; not exported */
/* to-str: uses an error-union or option type; not exported */
/* to-str: uses an error-union or option type; not exported */
/* to-str: uses an error-union or option type; not exported */
/* to-str: uses an error-union or option type; not exported */
/* to-str: uses an error-union or option type; not exported */
/* to-str: uses an error-union or option type; not exported */
/* to-str: uses an error-union or option type; not exported */
void string_push_f64(struct String* out, double v, const char* prec) asm("string-push-f64");
/* to-str: uses an error-union or option type; not exported */
/* to-str: uses an error-union or option type; not exported */
