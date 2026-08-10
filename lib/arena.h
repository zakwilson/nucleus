#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/arena.nuc by nucleusc --emit-cheader */

#define ARENA_SIZE 16777216
extern void* g_arena asm("g-arena");
extern int64_t g_arena_used asm("g-arena-used");
extern int64_t g_arena_cap asm("g-arena-cap");
void arena_init(void) asm("arena-init");
void arena_grow(int64_t min_size) asm("arena-grow");
void* arena_alloc(int64_t n) asm("arena-alloc");
void* arena_strndup(void* s, int64_t n) asm("arena-strndup");
void* arena_strdup(void* s) asm("arena-strdup");
