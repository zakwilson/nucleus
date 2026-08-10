#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/parse.nuc by nucleusc --emit-cheader */

uint8_t* parse_nul_copy(void* sv) asm("parse-nul-copy");
struct _BANGi32 from_str_i32_pStrView(int32_t self, void* sv) asm("from_str.i32.pStrView");
struct _BANGi64 from_str_i64_pStrView(int64_t self, void* sv) asm("from_str.i64.pStrView");
struct _BANGf64 from_str_f64_pStrView(double self, void* sv) asm("from_str.f64.pStrView");
