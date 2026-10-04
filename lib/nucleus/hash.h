#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "core.h"

/* Generated from lib/nucleus/hash.nuc by nucleusc --emit-cheader */

size_t hash_pi32(int32_t* self) asm("hash.pi32");
size_t hash_pi64(int64_t* self) asm("hash.pi64");
size_t hash_pusize(size_t* self) asm("hash.pusize");
size_t hash_pf64(double* self) asm("hash.pf64");
size_t hash_pf32(float* self) asm("hash.pf32");
size_t hash_ppNode(struct Node** self) asm("hash.ppNode");
size_t hash_pStrView(struct StrView* self) asm("hash.pStrView");
void hash_null_cstr(void) asm("hash-null-cstr");
size_t hash_pcstr(const char** self) asm("hash.pcstr");
