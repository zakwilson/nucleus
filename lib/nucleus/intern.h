#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "prelude.h"

/* Generated from lib/intern.nuc by nucleusc --emit-cheader */

typedef struct SymHeader {
    size_t hash;
    size_t len;
} SymHeader;

struct SymHeader* symbol_header(struct Symbol self) asm("symbol-header");
size_t symbol_len(struct Symbol self) asm("symbol-len");
size_t symbol_cached_hash(struct Symbol self) asm("symbol-cached-hash");
struct StrView symbol_as_view(struct Symbol self) asm("symbol-as-view");
const char* symbol_as_cstr(struct Symbol self) asm("symbol-as-cstr");
bool symbol_none_QMARK(struct Symbol self) asm("symbol-none_QMARK");
struct Symbol symbol_none(void) asm("symbol-none");
bool symbol_is(struct Symbol self, struct StrView other) asm("symbol-is");
bool eq_Symbol_StrView(struct Symbol a, struct StrView b) asm("eq.Symbol.StrView");
bool ne_Symbol_StrView(struct Symbol a, struct StrView b) asm("ne.Symbol.StrView");
bool symbol_contains_byte(struct Symbol self, int32_t b) asm("symbol-contains-byte");
int32_t symbol_byte_at(struct Symbol self, size_t i) asm("symbol-byte-at");
#define INTERN_INIT_CAP 1024
extern void* g_sym_table asm("g-sym-table");
extern size_t g_sym_cap asm("g-sym-cap");
extern size_t g_sym_count asm("g-sym-count");
void intern_oom(void) asm("intern-oom");
uint8_t* intern_alloc_bytes(uint8_t* src, size_t n, size_t h) asm("intern-alloc-bytes");
void intern_place(void* tbl, size_t cap, uint8_t* p, size_t h) asm("intern-place");
void intern_grow(size_t newcap) asm("intern-grow");
struct Symbol symbol_intern_bytes(uint8_t* src, size_t n) asm("symbol-intern-bytes");
struct Symbol symbol_intern_pStrView(struct StrView* sv) asm("symbol_intern.pStrView");
struct Symbol symbol_intern_StrView(struct StrView sv) asm("symbol_intern.StrView");
struct Symbol symbol_from_cstr(const char* cs) asm("symbol-from-cstr");
struct Symbol symbol_from_cstr_unchecked(const char* cs) asm("symbol-from-cstr-unchecked");
size_t symbol_count(void) asm("symbol-count");
bool eq_Symbol_Symbol(struct Symbol a, struct Symbol b) asm("eq.Symbol.Symbol");
bool ne_Symbol_Symbol(struct Symbol a, struct Symbol b) asm("ne.Symbol.Symbol");
