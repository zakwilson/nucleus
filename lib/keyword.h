#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/keyword.nuc by nucleusc --emit-cheader */

typedef struct {
    struct StrView* name;
    size_t id;
    size_t cached-hash;
} Keyword;

#define KEYWORD-MAX 256
extern void* g_keyword_table asm("g-keyword-table");
extern size_t g_keyword_count asm("g-keyword-count");
void keyword-overflow(void);
struct Keyword keyword-intern(const char* cs);
void* keyword-name(void* self);
_Bool =(struct Keyword a, struct Keyword b);
_Bool _BANG=(struct Keyword a, struct Keyword b);
size_t hash(void* self);
