#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/allocator.nuc by nucleusc --emit-cheader */

enum AllocKind {
    AllocKind_ALLOC_LIBC = 0,
    AllocKind_ALLOC_ARENA = 1
};

typedef struct AllocHandle {
    int32_t kind;
    void* data;
} AllocHandle;

void* alloc_handle_alloc(struct AllocHandle* h, size_t size, size_t align) asm("alloc-handle-alloc");
void* alloc_handle_realloc(struct AllocHandle* h, void* p, size_t old, size_t new_, size_t align) asm("alloc-handle-realloc");
void alloc_handle_free(struct AllocHandle* h, void* p, size_t size, size_t align) asm("alloc-handle-free");
extern struct AllocHandle g_default_alloc asm("g-default-alloc");
struct AllocHandle* default_allocator(void) asm("default-allocator");
struct AllocHandle* libc_allocator(struct AllocHandle* h) asm("libc-allocator");
struct AllocHandle* arena_allocator(struct AllocHandle* h) asm("arena-allocator");
