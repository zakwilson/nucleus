#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/hash.nuc by nucleusc --emit-cheader */

size_t hash_pi32(void* self) asm("hash.pi32");
size_t hash_pi64(void* self) asm("hash.pi64");
size_t hash_pusize(void* self) asm("hash.pusize");
size_t hash_pf64(void* self) asm("hash.pf64");
size_t hash_pf32(void* self) asm("hash.pf32");
size_t hash_ppNode(void* self) asm("hash.ppNode");
void hash_null_cstr(void) asm("hash-null-cstr");
size_t hash_pcstr(void* self) asm("hash.pcstr");
