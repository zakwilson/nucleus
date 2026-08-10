#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/node.nuc by nucleusc --emit-cheader */

void* alloc_node(void) asm("alloc-node");
void* make_cell(void* car, void* cdr, int32_t line) asm("make-cell");
typedef struct InternEntry {
    void* spelling;
    void* node;
} InternEntry;

extern void* g_intern_table asm("g-intern-table");
extern int32_t g_intern_cap asm("g-intern-cap");
extern int32_t g_intern_len asm("g-intern-len");
int64_t intern_hash(void* s) asm("intern-hash");
void intern_raw_insert(void* table, int32_t cap, void* sp, void* nd) asm("intern-raw-insert");
void intern_grow(void) asm("intern-grow");
void* intern_symbol(void* s) asm("intern-symbol");
void* node_at(void* n, int32_t i) asm("node-at");
int32_t node_len(void* n) asm("node-len");
int32_t node_line(void* n, int32_t encl) asm("node-line");
int32_t node_is_list(void* n) asm("node-is-list");
