#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/nucleus/iterator.nuc by nucleusc --emit-cheader */

typedef struct nuc_IntRangeIter {
    int32_t start;
    int32_t end;
} nuc_IntRangeIter;

/* next: uses an error-union or option type; not exported */
typedef struct nuc_I64ArrayIter {
    int64_t* data;
    size_t pos;
    size_t len;
} nuc_I64ArrayIter;

/* next: uses an error-union or option type; not exported */
/* next: generic template; not exported */
/* next: generic template; not exported */
/* reduce: generic template; not exported */
