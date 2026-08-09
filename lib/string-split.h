#pragma once
#include <stdint.h>
#include <stdbool.h>

/* Generated from lib/string-split.nuc by nucleusc --emit-cheader */

typedef struct {
    uint8_t* buf;
    struct usize rem;
    uint8_t* sep-data;
    struct usize sep-len;
    int32_t done;
    struct StrView cur;
} SplitIter;

int32_t split-iter-done(void* it);
struct StrView split-iter-next(void* it);
struct SplitIter strview-split(void* sv, void* sep);
void* next(void* self);
typedef struct {
    uint8_t* buf;
    struct usize rem;
    int32_t done;
    struct StrView cur;
} LineIter;

int32_t lines-iter-done(void* it);
struct StrView lines-iter-next(void* it);
struct LineIter strview-lines(void* sv);
void* next(void* self);
