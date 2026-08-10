#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/parse.nuc by nucleusc --emit-cheader */

uint8_t* parse_nul_copy(void* sv) asm("parse-nul-copy");
struct _BANGi32 from_str(int32_t self, void* sv) asm("from-str");
struct _BANGi64 from_str(int64_t self, void* sv) asm("from-str");
struct _BANGf64 from_str(double self, void* sv) asm("from-str");
