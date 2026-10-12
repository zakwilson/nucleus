#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/nucleus/create.nuc by nucleusc --emit-cheader */

uint8_t* nuc_create_bytes(uint8_t* /* nullable */ p) asm("nuc_create-bytes");
void nuc_create_zero(void* p, size_t size) asm("nuc_create-zero");
