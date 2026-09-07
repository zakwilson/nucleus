#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "prelude.h"

/* Generated from lib/keyword.nuc by nucleusc --emit-cheader */

typedef struct Keyword {
    struct Symbol sym;
} Keyword;

struct Keyword keyword_intern(struct StrView sv) asm("keyword-intern");
struct StrView keyword_name(struct Keyword self) asm("keyword-name");
struct Symbol keyword_symbol(struct Keyword self) asm("keyword-symbol");
bool eq_Keyword_Keyword(struct Keyword a, struct Keyword b) asm("eq.Keyword.Keyword");
bool ne_Keyword_Keyword(struct Keyword a, struct Keyword b) asm("ne.Keyword.Keyword");
size_t hash_pKeyword(struct Keyword* self) asm("hash.pKeyword");
/* to-str: uses an error-union or option type; not exported */
