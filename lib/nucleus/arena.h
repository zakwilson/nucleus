#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/nucleus/arena.nuc by nucleusc --emit-cheader */

#define ARENA_SIZE 16777216
extern void* nuc_g_arena asm("nuc_g-arena");
extern int64_t nuc_g_arena_used asm("nuc_g-arena-used");
extern int64_t nuc_g_arena_cap asm("nuc_g-arena-cap");
void nuc_arena_init(void) asm("nuc_arena-init");
void nuc_arena_grow(int64_t min_size) asm("nuc_arena-grow");
void* nuc_arena_alloc(int64_t n) asm("nuc_arena-alloc");
void* nuc_arena_bytes(void* src, int64_t n) asm("nuc_arena-bytes");
