#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/vector.nuc by nucleusc --emit-cheader */

void vector-oom(void);
void vector-bounds(const char* what, size_t i, size_t n);
void vector-init(void* v);
void vector-init-alloc(void* v, void* a);
void* vector-new(void);
void* vector-new-alloc(void* a);
void* vector-new-capacity(size_t n);
void* vector-new-in(void* a);
void vector-grow(void* v);
size_t count(void* self);
void conj(void* self, struct T elem);
int32_t empty_QMARK(void* self);
struct T invoke(void* self, size_t i);
void append(void* self, struct T elem);
int32_t contains_QMARK(void* self, struct T elem);
void insert(void* self, size_t i, struct T elem);
void remove-at(void* self, size_t i);
size_t capacity(void* self);
void reserve(void* self, size_t n);
void vector-init-capacity(void* v, size_t n);
void drop(void** self);
void* next(void* self);
void iter-init(void* it, void* v);
void* iter(void* self);
