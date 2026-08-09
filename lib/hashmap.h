#pragma once
#include <stdint.h>
#include <stdbool.h>

/* Generated from lib/hashmap.nuc by nucleusc --emit-cheader */

void hashmap-oom(void);
void hashmap-init(void* m);
void hashmap-init-alloc(void* m, void* a);
void* hashmap-new(void);
void* hashmap-new-alloc(void* a);
void* hashmap-new-in(void* a);
void hashmap-resize(void* m, struct usize new-cap);
void assoc(void* self, struct K key, struct V val);
void dissoc(void* self, struct K key);
void* get(void* self, struct K key);
struct usize count(void* self);
int32_t empty_QMARK(void* self);
void conj(void* self, void* elem);
void drop(void** self);
void* next(void* self);
void hmap-iter-keys(void* it, void* m);
void* next(void* self);
void hmap-iter-vals(void* it, void* m);
void* keys(void* self);
void* vals(void* self);
void* next(void* self);
void hmap-iter-entries(void* it, void* m);
void* iter(void* self);
