#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "allocator.h"

/* Generated from lib/nucleus/create.nuc by nucleusc --emit-cheader */

uint8_t* nuc_create_bytes(struct nuc_Alloc* a, size_t size, size_t align) asm("nuc_create-bytes");
void nuc_create_zero(void* p, size_t size) asm("nuc_create-zero");
