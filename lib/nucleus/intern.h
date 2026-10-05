#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "core.h"

/* Generated from lib/nucleus/intern.nuc by nucleusc --emit-cheader */

typedef struct nuc_SymHeader {
    size_t hash;
    size_t len;
} nuc_SymHeader;

struct nuc_SymHeader* nuc_symbol_header(struct nuc_Symbol self) asm("nuc_symbol-header");
size_t nuc_symbol_len(struct nuc_Symbol self) asm("nuc_symbol-len");
size_t nuc_symbol_cached_hash(struct nuc_Symbol self) asm("nuc_symbol-cached-hash");
struct nuc_StrView nuc_symbol_as_view(struct nuc_Symbol self) asm("nuc_symbol-as-view");
const char* nuc_symbol_as_cstr(struct nuc_Symbol self) asm("nuc_symbol-as-cstr");
bool nuc_symbol_none_QMARK(struct nuc_Symbol self) asm("nuc_symbol-none_QMARK");
struct nuc_Symbol nuc_symbol_none(void) asm("nuc_symbol-none");
bool nuc_symbol_is(struct nuc_Symbol self, struct nuc_StrView other) asm("nuc_symbol-is");
bool nuc_eq_nuc_Symbol_nuc_StrView(struct nuc_Symbol a, struct nuc_StrView b) asm("nuc_eq.nuc_Symbol.nuc_StrView");
bool nuc_ne_nuc_Symbol_nuc_StrView(struct nuc_Symbol a, struct nuc_StrView b) asm("nuc_ne.nuc_Symbol.nuc_StrView");
bool nuc_symbol_contains_byte(struct nuc_Symbol self, int32_t b) asm("nuc_symbol-contains-byte");
int32_t nuc_symbol_byte_at(struct nuc_Symbol self, size_t i) asm("nuc_symbol-byte-at");
#define INTERN_INIT_CAP 1024
extern void* nuc_g_sym_table asm("nuc_g-sym-table");
extern size_t nuc_g_sym_cap asm("nuc_g-sym-cap");
extern size_t nuc_g_sym_count asm("nuc_g-sym-count");
void nuc_intern_oom(void) asm("nuc_intern-oom");
uint8_t* nuc_intern_alloc_bytes(uint8_t* src, size_t n, size_t h) asm("nuc_intern-alloc-bytes");
void nuc_intern_place(void* tbl, size_t cap, uint8_t* p, size_t h) asm("nuc_intern-place");
void nuc_intern_grow(size_t newcap) asm("nuc_intern-grow");
struct nuc_Symbol nuc_symbol_intern_bytes(uint8_t* src, size_t n) asm("nuc_symbol-intern-bytes");
struct nuc_Symbol nuc_symbol_intern_pnuc_StrView(struct nuc_StrView* sv) asm("nuc_symbol_intern.pnuc_StrView");
struct nuc_Symbol nuc_symbol_intern_nuc_StrView(struct nuc_StrView sv) asm("nuc_symbol_intern.nuc_StrView");
struct nuc_Symbol nuc_symbol_from_cstr(const char* cs) asm("nuc_symbol-from-cstr");
struct nuc_Symbol nuc_symbol_from_cstr_unchecked(const char* cs) asm("nuc_symbol-from-cstr-unchecked");
size_t nuc_symbol_count(void) asm("nuc_symbol-count");
bool nuc_eq_nuc_Symbol_nuc_Symbol(struct nuc_Symbol a, struct nuc_Symbol b) asm("nuc_eq.nuc_Symbol.nuc_Symbol");
bool nuc_ne_nuc_Symbol_nuc_Symbol(struct nuc_Symbol a, struct nuc_Symbol b) asm("nuc_ne.nuc_Symbol.nuc_Symbol");
