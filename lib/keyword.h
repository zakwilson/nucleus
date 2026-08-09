#pragma once
#include <stdint.h>
#include <stdbool.h>

/* Generated from lib/keyword.nuc by nucleusc --emit-cheader */

typedef struct {
    struct StrView* name;
    struct usize id;
    struct usize cached-hash;
} Keyword;

#define KEYWORD-MAX 256
void keyword-overflow(void);
struct Keyword keyword-intern(const char* cs);
void* keyword-name(void* self);
_Bool =(struct Keyword a, struct Keyword b);
_Bool _BANG=(struct Keyword a, struct Keyword b);
struct usize hash(void* self);
