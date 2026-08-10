#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/parse.nuc by nucleusc --emit-cheader */

uint8_t* parse-nul-copy(void* sv);
struct _BANGi32 from-str(int32_t self, void* sv);
struct _BANGi64 from-str(int64_t self, void* sv);
struct _BANGf64 from-str(double self, void* sv);
