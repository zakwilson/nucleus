#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "string.h"

/* Generated from lib/nucleus/fmt.nuc by nucleusc --emit-cheader */

/* write-str: uses an error-union or option type; not exported */
typedef struct nuc_CFile {
    void* f;
} nuc_CFile;

struct nuc_CFile nuc_cfile(void* f);
/* write-str: uses an error-union or option type; not exported */
void nuc_string_push_u64(struct nuc_String* out, uint64_t v) asm("nuc_string-push-u64");
void nuc_string_push_i64(struct nuc_String* out, int64_t v) asm("nuc_string-push-i64");
/* to-str: uses an error-union or option type; not exported */
/* to-str: uses an error-union or option type; not exported */
/* to-str: uses an error-union or option type; not exported */
/* to-str: uses an error-union or option type; not exported */
/* to-str: uses an error-union or option type; not exported */
/* to-str: uses an error-union or option type; not exported */
/* to-str: uses an error-union or option type; not exported */
/* to-str: uses an error-union or option type; not exported */
void nuc_string_push_f64(struct nuc_String* out, double v, const char* prec) asm("nuc_string-push-f64");
/* to-str: uses an error-union or option type; not exported */
/* to-str: uses an error-union or option type; not exported */
