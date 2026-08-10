#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/string-split.nuc by nucleusc --emit-cheader */

typedef struct SplitIter {
    uint8_t* buf;
    size_t rem;
    uint8_t* sep_data;
    size_t sep_len;
    int32_t done;
    struct StrView cur;
} SplitIter;

int32_t split_iter_done(void* it) asm("split-iter-done");
struct StrView split_iter_next(void* it) asm("split-iter-next");
struct SplitIter strview_split(void* sv, void* sep) asm("strview-split");
/* next: uses a defunion-template instance type; not exported */
typedef struct LineIter {
    uint8_t* buf;
    size_t rem;
    int32_t done;
    struct StrView cur;
} LineIter;

int32_t lines_iter_done(void* it) asm("lines-iter-done");
struct StrView lines_iter_next(void* it) asm("lines-iter-next");
struct LineIter strview_lines(void* sv) asm("strview-lines");
/* next: uses a defunion-template instance type; not exported */
