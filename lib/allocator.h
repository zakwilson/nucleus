#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/allocator.nuc by nucleusc --emit-cheader */

enum AllocKind {
    AllocKind_ALLOC_LIBC = 0,
    AllocKind_ALLOC_ARENA = 1
};

typedef struct {
    int32_t kind;
    void* data;
} AllocHandle;

void* alloc_handle_alloc(void* h, size_t size, size_t align) asm("alloc-handle-alloc");
void* alloc_handle_realloc(void* h, void* p, size_t old, size_t new, size_t align) asm("alloc-handle-realloc");
void alloc_handle_free(void* h, void* p, size_t size, size_t align) asm("alloc-handle-free");
extern AllocHandle g_default_alloc asm("g-default-alloc");
void* default_allocator(void) asm("default-allocator");
void* libc_allocator(void* h) asm("libc-allocator");
void* arena_allocator(void* h) asm("arena-allocator");
