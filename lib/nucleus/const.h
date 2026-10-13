#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Generated from lib/nucleus/const.nuc by nucleusc --emit-cheader */

int32_t nuc_const_cmp_i8_i8(int8_t a, int8_t b) asm("nuc_const_cmp.i8.i8");
int32_t nuc_const_cmp_i16_i16(int16_t a, int16_t b) asm("nuc_const_cmp.i16.i16");
int32_t nuc_const_cmp_i32_i32(int32_t a, int32_t b) asm("nuc_const_cmp.i32.i32");
int32_t nuc_const_cmp_i64_i64(int64_t a, int64_t b) asm("nuc_const_cmp.i64.i64");
int32_t nuc_const_cmp_ssize_ssize(ptrdiff_t a, ptrdiff_t b) asm("nuc_const_cmp.ssize.ssize");
int32_t nuc_const_cmp_u8_u8(uint8_t a, uint8_t b) asm("nuc_const_cmp.u8.u8");
int32_t nuc_const_cmp_u16_u16(uint16_t a, uint16_t b) asm("nuc_const_cmp.u16.u16");
int32_t nuc_const_cmp_u32_u32(uint32_t a, uint32_t b) asm("nuc_const_cmp.u32.u32");
int32_t nuc_const_cmp_u64_u64(uint64_t a, uint64_t b) asm("nuc_const_cmp.u64.u64");
int32_t nuc_const_cmp_usize_usize(size_t a, size_t b) asm("nuc_const_cmp.usize.usize");
int32_t nuc_const_cmp_bool_bool(bool a, bool b) asm("nuc_const_cmp.bool.bool");
int32_t nuc_const_cmp_f32_f32(float a, float b) asm("nuc_const_cmp.f32.f32");
int32_t nuc_const_cmp_cstr_cstr(const char* a, const char* b) asm("nuc_const_cmp.cstr.cstr");
/* const-cmp: generic template; not exported */
/* const-seal: generic template; not exported */
/* const-find: generic template; not exported */
/* count: generic template; not exported */
/* empty?: generic template; not exported */
void nuc_const_bounds(size_t i, size_t n) asm("nuc_const-bounds");
/* invoke: generic template; not exported */
/* contains?: generic template; not exported */
/* next: generic template; not exported */
/* iter: generic template; not exported */
/* count: generic template; not exported */
/* empty?: generic template; not exported */
/* contains?: generic template; not exported */
/* iter: generic template; not exported */
/* count: generic template; not exported */
/* empty?: generic template; not exported */
/* get: generic template; not exported */
/* contains?: generic template; not exported */
/* iter: generic template; not exported */
/* next: generic template; not exported */
/* next: generic template; not exported */
/* keys: generic template; not exported */
/* vals: generic template; not exported */
