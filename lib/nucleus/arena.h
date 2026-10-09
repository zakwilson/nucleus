#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "allocator.h"

/* Generated from lib/nucleus/arena.nuc by nucleusc --emit-cheader */

extern struct nuc_Arena nuc_g_arena asm("nuc_g-arena");
void* nuc_arena_alloc(int64_t n) asm("nuc_arena-alloc");
void* nuc_arena_bytes(void* src, int64_t n) asm("nuc_arena-bytes");
