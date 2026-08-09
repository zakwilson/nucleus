#pragma once
#include <stdint.h>
#include <stdbool.h>

/* Generated from lib/vector.nuc by nucleusc --emit-cheader */

void vector-oom(void);
void vector-bounds(const char* what, struct usize i, struct usize n);
void vector-init(void* v);
void vector-init-alloc(void* v, void* a);
void* vector-new(void);
void* vector-new-alloc(void* a);
void* vector-new-capacity(struct usize n);
void* vector-new-in(void* a);
void vector-grow(void* v);
struct usize count(void* self);
void conj(void* self, struct T elem);
int32_t empty_QMARK(void* self);
struct T invoke(void* self, struct usize i);
void append(void* self, struct T elem);
int32_t contains_QMARK(void* self, struct T elem);
void insert(void* self, struct usize i, struct T elem);
void remove-at(void* self, struct usize i);
struct usize capacity(void* self);
void reserve(void* self, struct usize n);
void vector-init-capacity(void* v, struct usize n);
void drop(void** self);
void* next(void* self);
void iter-init(void* it, void* v);
void* iter(void* self);
