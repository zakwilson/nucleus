#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "core.h"

/* Generated from lib/nucleus/keyword.nuc by nucleusc --emit-cheader */

typedef struct nuc_Keyword {
    struct nuc_Symbol sym;
} nuc_Keyword;

struct nuc_Keyword nuc_keyword_intern(struct nuc_StrView sv) asm("nuc_keyword-intern");
struct nuc_StrView nuc_keyword_name(struct nuc_Keyword self) asm("nuc_keyword-name");
struct nuc_Symbol nuc_keyword_symbol(struct nuc_Keyword self) asm("nuc_keyword-symbol");
bool nuc_eq_nuc_Keyword_nuc_Keyword(struct nuc_Keyword a, struct nuc_Keyword b) asm("nuc_eq.nuc_Keyword.nuc_Keyword");
bool nuc_ne_nuc_Keyword_nuc_Keyword(struct nuc_Keyword a, struct nuc_Keyword b) asm("nuc_ne.nuc_Keyword.nuc_Keyword");
size_t nuc_hash_pnuc_Keyword(struct nuc_Keyword* self) asm("nuc_hash.pnuc_Keyword");
/* to-str: uses an error-union or option type; not exported */
