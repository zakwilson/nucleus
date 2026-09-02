#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "strview.h"
#include "prelude.h"

/* Generated from lib/intern-str.nuc by nucleusc --emit-cheader */

size_t hash_pSymbol(void* self) asm("hash.pSymbol");
/* to-str: uses an error-union or option type; not exported */
size_t byte_len_pSymbol(void* self) asm("byte_len.pSymbol");
/* byte-at: uses an error-union or option type; not exported */
struct ByteIter bytes_pSymbol(void* self) asm("bytes.pSymbol");
struct StrView as_view_pSymbol(void* self) asm("as_view.pSymbol");
/* sub-bytes: uses an error-union or option type; not exported */
/* byte-find: uses a defunion-template instance type; not exported */
size_t char_count_pSymbol(void* self) asm("char_count.pSymbol");
bool str_empty_QMARK_pSymbol(void* self) asm("str_empty_QMARK.pSymbol");
/* char-at: uses an error-union or option type; not exported */
struct CharIter chars_pSymbol(void* self) asm("chars.pSymbol");
bool starts_with_QMARK_pSymbol_pStrView(void* self, void* prefix) asm("starts_with_QMARK.pSymbol.pStrView");
bool ends_with_QMARK_pSymbol_pStrView(void* self, void* suffix) asm("ends_with_QMARK.pSymbol.pStrView");
bool contains_str_QMARK_pSymbol_pStrView(void* self, void* needle) asm("contains_str_QMARK.pSymbol.pStrView");
