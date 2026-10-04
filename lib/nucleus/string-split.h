#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "core.h"

/* Generated from lib/nucleus/string-split.nuc by nucleusc --emit-cheader */

typedef struct SplitIter {
    uint8_t* buf;
    size_t rem;
    uint8_t* sep_data;
    size_t sep_len;
    bool done;
} SplitIter;

bool split_iter_done(struct SplitIter* it) asm("split-iter-done");
struct StrView split_iter_next(struct SplitIter* it) asm("split-iter-next");
struct SplitIter strview_split(struct StrView* sv, struct StrView* sep) asm("strview-split");
/* next: uses an error-union or option type; not exported */
typedef struct LineIter {
    uint8_t* buf;
    size_t rem;
    bool done;
} LineIter;

bool lines_iter_done(struct LineIter* it) asm("lines-iter-done");
struct StrView lines_iter_next(struct LineIter* it) asm("lines-iter-next");
struct LineIter strview_lines(struct StrView* sv) asm("strview-lines");
/* next: uses an error-union or option type; not exported */
