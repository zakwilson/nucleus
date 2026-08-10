#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/hashset.nuc by nucleusc --emit-cheader */

void hashset-oom(void);
void hashset-init(void* s);
void hashset-init-alloc(void* s, void* a);
void* hashset-new(void);
void* hashset-new-alloc(void* a);
void* hashset-new-in(void* a);
void hashset-resize(void* s, size_t new-cap);
void insert(void* self, struct T elem);
int32_t contains_QMARK(void* self, struct T elem);
void set-remove(void* self, struct T elem);
size_t count(void* self);
int32_t empty_QMARK(void* self);
void conj(void* self, struct T elem);
void union(void* self, void* other);
void difference(void* self, void* other);
void intersection(void* self, void* other);
void drop(void** self);
void* next(void* self);
void hashset-iter(void* it, void* s);
void* iter(void* self);
