#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "prelude.h"
#include "strview.h"

/* Generated from lib/intern-str.nuc by nucleusc --emit-cheader */

size_t hash_pSymbol(struct Symbol* self) asm("hash.pSymbol");
/* to-str: uses an error-union or option type; not exported */
size_t byte_len_pSymbol(struct Symbol* self) asm("byte_len.pSymbol");
/* byte-at: uses an error-union or option type; not exported */
struct ByteIter bytes_pSymbol(struct Symbol* self) asm("bytes.pSymbol");
struct StrView as_view_pSymbol(struct Symbol* self) asm("as_view.pSymbol");
/* sub-bytes: uses an error-union or option type; not exported */
/* byte-find: uses a defunion-template instance type; not exported */
size_t char_count_pSymbol(struct Symbol* self) asm("char_count.pSymbol");
bool str_empty_QMARK_pSymbol(struct Symbol* self) asm("str_empty_QMARK.pSymbol");
/* char-at: uses an error-union or option type; not exported */
struct CharIter chars_pSymbol(struct Symbol* self) asm("chars.pSymbol");
bool starts_with_QMARK_pSymbol_pStrView(struct Symbol* self, struct StrView* prefix) asm("starts_with_QMARK.pSymbol.pStrView");
bool ends_with_QMARK_pSymbol_pStrView(struct Symbol* self, struct StrView* suffix) asm("ends_with_QMARK.pSymbol.pStrView");
bool contains_str_QMARK_pSymbol_pStrView(struct Symbol* self, struct StrView* needle) asm("contains_str_QMARK.pSymbol.pStrView");
