#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/hashset.nuc by nucleusc --emit-cheader */

void hashset_oom(void) asm("hashset-oom");
void hashset_init(void* s) asm("hashset-init");
void hashset_init_alloc(void* s, void* a) asm("hashset-init-alloc");
void* hashset_new(void) asm("hashset-new");
void* hashset_new_alloc(void* a) asm("hashset-new-alloc");
void* hashset_new_in(void* a) asm("hashset-new-in");
void hashset_resize(void* s, size_t new_cap) asm("hashset-resize");
void insert(void* self, struct T elem);
int32_t contains_QMARK(void* self, struct T elem);
void set_remove(void* self, struct T elem) asm("set-remove");
size_t count(void* self);
int32_t empty_QMARK(void* self);
void conj(void* self, struct T elem);
void union(void* self, void* other);
void difference(void* self, void* other);
void intersection(void* self, void* other);
void drop(void** self);
void* next(void* self);
void hashset_iter(void* it, void* s) asm("hashset-iter");
void* iter(void* self);
