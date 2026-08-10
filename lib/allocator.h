#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/allocator.nuc by nucleusc --emit-cheader */

enum AllocKind {
    AllocKind_ALLOC-LIBC = 0,
    AllocKind_ALLOC-ARENA = 1
};

typedef struct {
    int32_t kind;
    void* data;
} AllocHandle;

void* alloc-handle-alloc(void* h, size_t size, size_t align);
void* alloc-handle-realloc(void* h, void* p, size_t old, size_t new, size_t align);
void alloc-handle-free(void* h, void* p, size_t size, size_t align);
extern AllocHandle g_default_alloc asm("g-default-alloc");
void* default-allocator(void);
void* libc-allocator(void* h);
void* arena-allocator(void* h);
