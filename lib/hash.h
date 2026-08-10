#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/hash.nuc by nucleusc --emit-cheader */

int64_t fnv1a_byte(int64_t h, int64_t b) asm("fnv1a-byte");
int64_t fnv1a_int(int64_t h, int64_t v, int32_t n) asm("fnv1a-int");
size_t hash(void* self);
size_t hash(void* self);
size_t hash(void* self);
void hash_null_cstr(void) asm("hash-null-cstr");
size_t hash(void* self);
