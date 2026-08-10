#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/keyword.nuc by nucleusc --emit-cheader */

typedef struct Keyword {
    struct StrView* name;
    size_t id;
    size_t cached_hash;
} Keyword;

#define KEYWORD_MAX 256
extern void* g_keyword_table asm("g-keyword-table");
extern size_t g_keyword_count asm("g-keyword-count");
void keyword_overflow(void) asm("keyword-overflow");
struct Keyword keyword_intern(const char* cs) asm("keyword-intern");
void* keyword_name(void* self) asm("keyword-name");
_Bool _(struct Keyword a, struct Keyword b) asm("=");
_Bool _BANG_(struct Keyword a, struct Keyword b) asm("_BANG=");
size_t hash(void* self);
