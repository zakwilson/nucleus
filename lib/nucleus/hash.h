#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "core.h"

/* Generated from lib/nucleus/hash.nuc by nucleusc --emit-cheader */

size_t nuc_hash_pi32(int32_t* self) asm("nuc_hash.pi32");
size_t nuc_hash_pi64(int64_t* self) asm("nuc_hash.pi64");
size_t nuc_hash_pusize(size_t* self) asm("nuc_hash.pusize");
size_t nuc_hash_pf64(double* self) asm("nuc_hash.pf64");
size_t nuc_hash_pf32(float* self) asm("nuc_hash.pf32");
size_t nuc_hash_ppnuc_Node(struct nuc_Node** self) asm("nuc_hash.ppnuc_Node");
size_t nuc_hash_pnuc_StrView(struct nuc_StrView* self) asm("nuc_hash.pnuc_StrView");
void nuc_hash_null_cstr(void) asm("nuc_hash-null-cstr");
size_t nuc_hash_pcstr(const char** self) asm("nuc_hash.pcstr");
