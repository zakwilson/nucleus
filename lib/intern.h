#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "prelude.h"
#include "strview.h"

/* Generated from lib/intern.nuc by nucleusc --emit-cheader */

typedef struct Symbol {
    uint8_t* p;
} Symbol;

#define SYM_LEN_OFF -8
#define SYM_HASH_OFF -16
#define SYM_HEADER 16
size_t symbol_len(struct Symbol self) asm("symbol-len");
size_t symbol_cached_hash(struct Symbol self) asm("symbol-cached-hash");
struct StrView symbol_as_view(struct Symbol self) asm("symbol-as-view");
const char* symbol_as_cstr(struct Symbol self) asm("symbol-as-cstr");
#define INTERN_INIT_CAP 1024
extern void* g_sym_table asm("g-sym-table");
extern size_t g_sym_cap asm("g-sym-cap");
extern size_t g_sym_count asm("g-sym-count");
void intern_oom(void) asm("intern-oom");
uint8_t* intern_alloc_bytes(void* sv, size_t h) asm("intern-alloc-bytes");
void intern_place(void* tbl, size_t cap, uint8_t* p, size_t h) asm("intern-place");
void intern_grow(size_t newcap) asm("intern-grow");
struct Symbol symbol_intern(void* sv) asm("symbol-intern");
struct Symbol symbol_from_cstr(const char* cs) asm("symbol-from-cstr");
size_t symbol_count(void) asm("symbol-count");
bool eq_Symbol_Symbol(struct Symbol a, struct Symbol b) asm("eq.Symbol.Symbol");
bool ne_Symbol_Symbol(struct Symbol a, struct Symbol b) asm("ne.Symbol.Symbol");
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
