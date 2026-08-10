#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/vector.nuc by nucleusc --emit-cheader */

void vector_oom(void) asm("vector-oom");
void vector_bounds(const char* what, size_t i, size_t n) asm("vector-bounds");
void vector_init(void* v) asm("vector-init");
void vector_init_alloc(void* v, void* a) asm("vector-init-alloc");
void* vector_new(void) asm("vector-new");
void* vector_new_alloc(void* a) asm("vector-new-alloc");
void* vector_new_capacity(size_t n) asm("vector-new-capacity");
void* vector_new_in(void* a) asm("vector-new-in");
void vector_grow(void* v) asm("vector-grow");
size_t count(void* self);
void conj(void* self, struct T elem);
int32_t empty_QMARK(void* self);
struct T invoke(void* self, size_t i);
void append(void* self, struct T elem);
int32_t contains_QMARK(void* self, struct T elem);
void insert(void* self, size_t i, struct T elem);
void remove_at(void* self, size_t i) asm("remove-at");
size_t capacity(void* self);
void reserve(void* self, size_t n);
void vector_init_capacity(void* v, size_t n) asm("vector-init-capacity");
void drop(void** self);
void* next(void* self);
void iter_init(void* it, void* v) asm("iter-init");
void* iter(void* self);
