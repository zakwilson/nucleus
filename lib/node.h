#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/node.nuc by nucleusc --emit-cheader */

void* alloc-node(void);
void* make-cell(void* car, void* cdr, int32_t line);
typedef struct {
    void* spelling;
    void* node;
} InternEntry;

extern void* g_intern_table asm("g-intern-table");
extern int32_t g_intern_cap asm("g-intern-cap");
extern int32_t g_intern_len asm("g-intern-len");
int64_t intern-hash(void* s);
void intern-raw-insert(void* table, int32_t cap, void* sp, void* nd);
void intern-grow(void);
void* intern-symbol(void* s);
void* node-at(void* n, int32_t i);
int32_t node-len(void* n);
int32_t node-line(void* n, int32_t encl);
int32_t node-is-list(void* n);
