#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "core.h"

/* Generated from lib/nucleus/string-split.nuc by nucleusc --emit-cheader */

typedef struct nuc_SplitIter {
    uint8_t* buf;
    size_t rem;
    uint8_t* sep_data;
    size_t sep_len;
    bool done;
} nuc_SplitIter;

bool nuc_split_iter_done(struct nuc_SplitIter* it) asm("nuc_split-iter-done");
struct nuc_StrView nuc_split_iter_next(struct nuc_SplitIter* it) asm("nuc_split-iter-next");
struct nuc_SplitIter nuc_strview_split(struct nuc_StrView* sv, struct nuc_StrView* sep) asm("nuc_strview-split");
/* next: uses an error-union or option type; not exported */
typedef struct nuc_LineIter {
    uint8_t* buf;
    size_t rem;
    bool done;
} nuc_LineIter;

bool nuc_lines_iter_done(struct nuc_LineIter* it) asm("nuc_lines-iter-done");
struct nuc_StrView nuc_lines_iter_next(struct nuc_LineIter* it) asm("nuc_lines-iter-next");
struct nuc_LineIter nuc_strview_lines(struct nuc_StrView* sv) asm("nuc_strview-lines");
/* next: uses an error-union or option type; not exported */
