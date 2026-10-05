#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/nucleus/allocator.nuc by nucleusc --emit-cheader */

enum AllocKind {
    AllocKind_ALLOC_LIBC = 0,
    AllocKind_ALLOC_ARENA = 1
};

typedef struct nuc_AllocHandle {
    int32_t kind;
    void* data;
} nuc_AllocHandle;

uint8_t* /* nullable */ nuc_alloc_handle_alloc(struct nuc_AllocHandle* h, size_t size, size_t align) asm("nuc_alloc-handle-alloc");
uint8_t* /* nullable */ nuc_alloc_handle_realloc(struct nuc_AllocHandle* h, uint8_t* /* nullable */ p, size_t old, size_t new_, size_t align) asm("nuc_alloc-handle-realloc");
void nuc_alloc_handle_free(struct nuc_AllocHandle* h, uint8_t* /* nullable */ p, size_t size, size_t align) asm("nuc_alloc-handle-free");
extern struct nuc_AllocHandle nuc_g_default_alloc asm("nuc_g-default-alloc");
struct nuc_AllocHandle* nuc_default_allocator(void) asm("nuc_default-allocator");
struct nuc_AllocHandle* nuc_libc_allocator(struct nuc_AllocHandle* h) asm("nuc_libc-allocator");
struct nuc_AllocHandle* nuc_arena_allocator(struct nuc_AllocHandle* h) asm("nuc_arena-allocator");
