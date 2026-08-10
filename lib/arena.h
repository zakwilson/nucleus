#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/arena.nuc by nucleusc --emit-cheader */

#define ARENA-SIZE 16777216
extern void* g_arena asm("g-arena");
extern int64_t g_arena_used asm("g-arena-used");
extern int64_t g_arena_cap asm("g-arena-cap");
void arena-init(void);
void arena-grow(int64_t min-size);
void* arena-alloc(int64_t n);
void* arena-strndup(void* s, int64_t n);
void* arena-strdup(void* s);
