#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "prelude.h"

/* Generated from lib/intern.nuc by nucleusc --emit-cheader */

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
