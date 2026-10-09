#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/nucleus/allocator.nuc by nucleusc --emit-cheader */

enum AllocKind {
    AllocKind_ALLOC_HEAP = 0,
    AllocKind_ALLOC_ARENA = 1,
    AllocKind_ALLOC_FIXED = 2,
    AllocKind_ALLOC_CUSTOM = 3,
    AllocKind_ALLOC_TRACKING = 4
};

typedef struct nuc_Alloc {
    int32_t kind;
    void* data;
} nuc_Alloc;

typedef struct nuc_CustomAlloc {
    void* instance;
    uint8_t* /* nullable */ (*allocate_fn)(void*, size_t, size_t);
    uint8_t* /* nullable */ (*reallocate_fn)(void*, uint8_t* /* nullable */, size_t, size_t, size_t);
    void (*deallocate_fn)(void*, uint8_t* /* nullable */, size_t, size_t);
} nuc_CustomAlloc;

size_t nuc_align_pad(size_t addr, size_t align) asm("nuc_align-pad");
bool nuc_align_ok_QMARK(size_t align) asm("nuc_align-ok_QMARK");
size_t nuc_alloc_addr(void* p) asm("nuc_alloc-addr");
typedef struct nuc_Heap {
} nuc_Heap;

extern struct nuc_Heap nuc_heap;
size_t nuc_heap_malloc_align(void) asm("nuc_heap-malloc-align");
void** nuc_heap_raw_slot(void* p) asm("nuc_heap-raw-slot");
uint8_t* /* nullable */ nuc_heap_allocate(size_t size, size_t align) asm("nuc_heap-allocate");
void nuc_heap_deallocate(uint8_t* /* nullable */ p, size_t size, size_t align) asm("nuc_heap-deallocate");
uint8_t* /* nullable */ nuc_heap_reallocate(uint8_t* /* nullable */ p, size_t old, size_t new_, size_t align) asm("nuc_heap-reallocate");
uint8_t* /* nullable */ nuc_allocate_pnuc_Heap_usize_usize(struct nuc_Heap* self, size_t size, size_t align) asm("nuc_allocate.pnuc_Heap.usize.usize");
uint8_t* /* nullable */ nuc_reallocate_pnuc_Heap_pu8_usize_usize_usize(struct nuc_Heap* self, uint8_t* /* nullable */ p, size_t old, size_t new_, size_t align) asm("nuc_reallocate.pnuc_Heap.pu8.usize.usize.usize");
void nuc_deallocate_pnuc_Heap_pu8_usize_usize(struct nuc_Heap* self, uint8_t* /* nullable */ p, size_t size, size_t align) asm("nuc_deallocate.pnuc_Heap.pu8.usize.usize");
struct nuc_Alloc nuc_handle_pnuc_Heap(struct nuc_Heap* self) asm("nuc_handle.pnuc_Heap");
void nuc_drop_pnuc_Heap(struct nuc_Heap* self) asm("nuc_drop.pnuc_Heap");
typedef struct nuc_ArenaBlock {
    struct nuc_ArenaBlock* /* nullable */ next;
    size_t size;
} nuc_ArenaBlock;

typedef struct nuc_Arena {
    struct nuc_ArenaBlock* /* nullable */ first;
    struct nuc_ArenaBlock* /* nullable */ cur;
    size_t off;
    size_t block_size;
    struct nuc_Alloc parent;
} nuc_Arena;

size_t nuc_arena_block_align(void) asm("nuc_arena-block-align");
size_t nuc_arena_default_block(void) asm("nuc_arena-default-block");
size_t nuc_arena_block_cap(void) asm("nuc_arena-block-cap");
struct nuc_Arena nuc_arena_in(struct nuc_Alloc parent, size_t block_size) asm("nuc_arena-in");
uint8_t* nuc_arena_base(struct nuc_ArenaBlock* b) asm("nuc_arena-base");
size_t nuc_arena_fit(struct nuc_ArenaBlock* b, size_t from, size_t size, size_t align) asm("nuc_arena-fit");
uint8_t* /* nullable */ nuc_arena_take(struct nuc_Arena* a, struct nuc_ArenaBlock* b, size_t start, size_t size) asm("nuc_arena-take");
size_t nuc_arena_next_size(struct nuc_Arena* a, struct nuc_ArenaBlock* /* nullable */ tail, size_t need) asm("nuc_arena-next-size");
uint8_t* /* nullable */ nuc_arena_allocate(struct nuc_Arena* a, size_t size, size_t align) asm("nuc_arena-allocate");
bool nuc_arena_top_QMARK(struct nuc_Arena* a, uint8_t* /* nullable */ p, size_t size) asm("nuc_arena-top_QMARK");
void nuc_arena_deallocate(struct nuc_Arena* a, uint8_t* /* nullable */ p, size_t size) asm("nuc_arena-deallocate");
uint8_t* /* nullable */ nuc_arena_reallocate(struct nuc_Arena* a, uint8_t* /* nullable */ p, size_t old, size_t new_, size_t align) asm("nuc_arena-reallocate");
void nuc_arena_reset(struct nuc_Arena* a) asm("nuc_arena-reset");
uint8_t* /* nullable */ nuc_allocate_pnuc_Arena_usize_usize(struct nuc_Arena* self, size_t size, size_t align) asm("nuc_allocate.pnuc_Arena.usize.usize");
uint8_t* /* nullable */ nuc_reallocate_pnuc_Arena_pu8_usize_usize_usize(struct nuc_Arena* self, uint8_t* /* nullable */ p, size_t old, size_t new_, size_t align) asm("nuc_reallocate.pnuc_Arena.pu8.usize.usize.usize");
void nuc_deallocate_pnuc_Arena_pu8_usize_usize(struct nuc_Arena* self, uint8_t* /* nullable */ p, size_t size, size_t align) asm("nuc_deallocate.pnuc_Arena.pu8.usize.usize");
struct nuc_Alloc nuc_handle_pnuc_Arena(struct nuc_Arena* self) asm("nuc_handle.pnuc_Arena");
void nuc_drop_pnuc_Arena(struct nuc_Arena* self) asm("nuc_drop.pnuc_Arena");
typedef struct nuc_FixedBuffer {
    void* buf;
    size_t len;
    size_t off;
    size_t live;
} nuc_FixedBuffer;

struct nuc_FixedBuffer nuc_fixed_buffer(void* p, size_t len) asm("nuc_fixed-buffer");
uint8_t* /* nullable */ nuc_fixed_allocate(struct nuc_FixedBuffer* fb, size_t size, size_t align) asm("nuc_fixed-allocate");
bool nuc_fixed_top_QMARK(struct nuc_FixedBuffer* fb, uint8_t* /* nullable */ p, size_t size) asm("nuc_fixed-top_QMARK");
void nuc_fixed_deallocate(struct nuc_FixedBuffer* fb, uint8_t* /* nullable */ p, size_t size) asm("nuc_fixed-deallocate");
uint8_t* /* nullable */ nuc_fixed_reallocate(struct nuc_FixedBuffer* fb, uint8_t* /* nullable */ p, size_t old, size_t new_, size_t align) asm("nuc_fixed-reallocate");
uint8_t* /* nullable */ nuc_allocate_pnuc_FixedBuffer_usize_usize(struct nuc_FixedBuffer* self, size_t size, size_t align) asm("nuc_allocate.pnuc_FixedBuffer.usize.usize");
uint8_t* /* nullable */ nuc_reallocate_pnuc_FixedBuffer_pu8_usize_usize_usize(struct nuc_FixedBuffer* self, uint8_t* /* nullable */ p, size_t old, size_t new_, size_t align) asm("nuc_reallocate.pnuc_FixedBuffer.pu8.usize.usize.usize");
void nuc_deallocate_pnuc_FixedBuffer_pu8_usize_usize(struct nuc_FixedBuffer* self, uint8_t* /* nullable */ p, size_t size, size_t align) asm("nuc_deallocate.pnuc_FixedBuffer.pu8.usize.usize");
struct nuc_Alloc nuc_handle_pnuc_FixedBuffer(struct nuc_FixedBuffer* self) asm("nuc_handle.pnuc_FixedBuffer");
void nuc_drop_pnuc_FixedBuffer(struct nuc_FixedBuffer* self) asm("nuc_drop.pnuc_FixedBuffer");
typedef struct nuc_Tracking {
    struct nuc_Alloc parent;
    size_t live;
    size_t bytes;
} nuc_Tracking;

bool nuc_tracking_owes_QMARK(struct nuc_Tracking* tr, size_t size) asm("nuc_tracking-owes_QMARK");
uint8_t* /* nullable */ nuc_tracking_allocate(struct nuc_Tracking* tr, size_t size, size_t align) asm("nuc_tracking-allocate");
uint8_t* /* nullable */ nuc_tracking_reallocate(struct nuc_Tracking* tr, uint8_t* /* nullable */ p, size_t old, size_t new_, size_t align) asm("nuc_tracking-reallocate");
void nuc_tracking_deallocate(struct nuc_Tracking* tr, uint8_t* /* nullable */ p, size_t size, size_t align) asm("nuc_tracking-deallocate");
uint8_t* /* nullable */ nuc_allocate_pnuc_Tracking_usize_usize(struct nuc_Tracking* self, size_t size, size_t align) asm("nuc_allocate.pnuc_Tracking.usize.usize");
uint8_t* /* nullable */ nuc_reallocate_pnuc_Tracking_pu8_usize_usize_usize(struct nuc_Tracking* self, uint8_t* /* nullable */ p, size_t old, size_t new_, size_t align) asm("nuc_reallocate.pnuc_Tracking.pu8.usize.usize.usize");
void nuc_deallocate_pnuc_Tracking_pu8_usize_usize(struct nuc_Tracking* self, uint8_t* /* nullable */ p, size_t size, size_t align) asm("nuc_deallocate.pnuc_Tracking.pu8.usize.usize");
struct nuc_Alloc nuc_handle_pnuc_Tracking(struct nuc_Tracking* self) asm("nuc_handle.pnuc_Tracking");
void nuc_drop_pnuc_Tracking(struct nuc_Tracking* self) asm("nuc_drop.pnuc_Tracking");
uint8_t* /* nullable */ nuc_alloc_allocate(struct nuc_Alloc* a, size_t size, size_t align) asm("nuc_alloc-allocate");
uint8_t* /* nullable */ nuc_alloc_reallocate(struct nuc_Alloc* a, uint8_t* /* nullable */ p, size_t old, size_t new_, size_t align) asm("nuc_alloc-reallocate");
void nuc_alloc_deallocate(struct nuc_Alloc* a, uint8_t* /* nullable */ p, size_t size, size_t align) asm("nuc_alloc-deallocate");
struct nuc_Alloc nuc_custom_alloc(struct nuc_CustomAlloc* c) asm("nuc_custom-alloc");
uint8_t* /* nullable */ nuc_allocate_pnuc_Alloc_usize_usize(struct nuc_Alloc* self, size_t size, size_t align) asm("nuc_allocate.pnuc_Alloc.usize.usize");
uint8_t* /* nullable */ nuc_reallocate_pnuc_Alloc_pu8_usize_usize_usize(struct nuc_Alloc* self, uint8_t* /* nullable */ p, size_t old, size_t new_, size_t align) asm("nuc_reallocate.pnuc_Alloc.pu8.usize.usize.usize");
void nuc_deallocate_pnuc_Alloc_pu8_usize_usize(struct nuc_Alloc* self, uint8_t* /* nullable */ p, size_t size, size_t align) asm("nuc_deallocate.pnuc_Alloc.pu8.usize.usize");
struct nuc_Alloc nuc_handle_pnuc_Alloc(struct nuc_Alloc* self) asm("nuc_handle.pnuc_Alloc");
/* init: generic template; not exported */
void nuc_init_pnuc_Tracking_nuc_Alloc(struct nuc_Tracking* self, struct nuc_Alloc a) asm("nuc_init.pnuc_Tracking.nuc_Alloc");
