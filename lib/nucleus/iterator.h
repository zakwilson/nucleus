#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/nucleus/iterator.nuc by nucleusc --emit-cheader */

typedef struct IntRangeIter {
    int32_t start;
    int32_t end;
} IntRangeIter;

/* next: uses an error-union or option type; not exported */
typedef struct I64ArrayIter {
    int64_t* data;
    size_t pos;
    size_t len;
} I64ArrayIter;

/* next: uses an error-union or option type; not exported */
/* next: generic template; not exported */
/* next: generic template; not exported */
/* reduce: generic template; not exported */
