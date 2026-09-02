#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/node.nuc by nucleusc --emit-cheader */

void* alloc_node(void) asm("alloc-node");
void* make_cell(void* car, void* cdr, int32_t line) asm("make-cell");
void* node_at(void* n, int32_t i) asm("node-at");
int32_t node_len(void* n) asm("node-len");
int32_t node_line(void* n, int32_t encl) asm("node-line");
bool node_is_list(void* n) asm("node-is-list");
#define NODE_NIL -1
int32_t node_kind(void* n) asm("node-kind");
typedef struct InternEntry {
    void* spelling;
    void* node;
} InternEntry;

extern void* g_intern_table asm("g-intern-table");
extern int32_t g_intern_cap asm("g-intern-cap");
extern int32_t g_intern_len asm("g-intern-len");
void sym_node_place(void* table, int32_t cap, void* sp, void* nd, int64_t h) asm("sym-node-place");
int64_t sym_node_hash(void* sp) asm("sym-node-hash");
void sym_node_grow(void) asm("sym-node-grow");
void* intern_symbol(const char* s) asm("intern-symbol");
