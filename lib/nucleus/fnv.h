#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/nucleus/fnv.nuc by nucleusc --emit-cheader */

int64_t fnv1a_byte(int64_t h, int64_t b) asm("fnv1a-byte");
int64_t fnv1a_int(int64_t h, int64_t v, int32_t n) asm("fnv1a-int");
size_t fnv1a_bytes(uint8_t* p, size_t n) asm("fnv1a-bytes");
