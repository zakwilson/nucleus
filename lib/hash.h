#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/hash.nuc by nucleusc --emit-cheader */

int64_t fnv1a-byte(int64_t h, int64_t b);
int64_t fnv1a-int(int64_t h, int64_t v, int32_t n);
size_t hash(void* self);
size_t hash(void* self);
size_t hash(void* self);
size_t hash(void* self);
