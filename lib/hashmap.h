#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/hashmap.nuc by nucleusc --emit-cheader */

void hashmap_oom(void) asm("hashmap-oom");
void hashmap_init(void* m) asm("hashmap-init");
void hashmap_init_alloc(void* m, void* a) asm("hashmap-init-alloc");
void* hashmap_new(void) asm("hashmap-new");
void* hashmap_new_alloc(void* a) asm("hashmap-new-alloc");
void* hashmap_new_in(void* a) asm("hashmap-new-in");
void hashmap_resize(void* m, size_t new_cap) asm("hashmap-resize");
void assoc(void* self, struct K key, struct V val);
void dissoc(void* self, struct K key);
void* get(void* self, struct K key);
size_t count(void* self);
int32_t empty_QMARK(void* self);
void conj(void* self, void* elem);
void drop(void** self);
void* next(void* self);
void hmap_iter_keys(void* it, void* m) asm("hmap-iter-keys");
void* next(void* self);
void hmap_iter_vals(void* it, void* m) asm("hmap-iter-vals");
void* keys(void* self);
void* vals(void* self);
void* next(void* self);
void hmap_iter_entries(void* it, void* m) asm("hmap-iter-entries");
void* iter(void* self);
