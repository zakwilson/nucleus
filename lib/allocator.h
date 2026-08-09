#pragma once
#include <stdint.h>
#include <stdbool.h>

/* Generated from lib/allocator.nuc by nucleusc --emit-cheader */

enum AllocKind {
    AllocKind_ALLOC-LIBC = 0,
    AllocKind_ALLOC-ARENA = 1
};

typedef struct {
    int32_t kind;
    void* data;
} AllocHandle;

void* alloc-handle-alloc(void* h, struct usize size, struct usize align);
void* alloc-handle-realloc(void* h, void* p, struct usize old, struct usize new, struct usize align);
void alloc-handle-free(void* h, void* p, struct usize size, struct usize align);
void* default-allocator(void);
void* libc-allocator(void* h);
void* arena-allocator(void* h);
