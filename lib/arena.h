#pragma once
#include <stdint.h>
#include <stdbool.h>

/* Generated from lib/arena.nuc by nucleusc --emit-cheader */

#define ARENA-SIZE 16777216
void arena-init(void);
void arena-grow(int64_t min-size);
void* arena-alloc(int64_t n);
void* arena-strndup(void* s, int64_t n);
void* arena-strdup(void* s);
